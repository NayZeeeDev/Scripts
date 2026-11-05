-- ═══════════════════════════════════════════════════════════════
--  FUNERAL HOME (server)
--  duty · hearse garage · coroner calls · morgue records · death
--  certificates · cremation · shop · funeral services · headstones
-- ═══════════════════════════════════════════════════════════════
if not FuneralEnabled() then
    Console.check('funeral', 'info', 'Funeral home', 'disabled (Config.Funeral.Enabled = false)')
    return
end

local F = Config.Funeral
local L = F.Locations

if F.SetupDone then
    Console.check('funeral', 'ok', 'Funeral home', ('%d plot(s), job "%s"'):format(#F.Plots, F.Job))
else
    Console.check('funeral', 'warn', 'Funeral home',
        'placeholder spots: use /nzcoords in-game, then set Config.Funeral.SetupDone = true')
end
Console.wait('funeral')

local Hearses     = {} -- src -> vehicle entity
local paidFor     = {} -- identifier -> os.time() of the last morgue payout for that character
local Services    = {} -- plot index -> { obj, body, director, stage = 'placed'|'service', startedAt, epitaph, name }
local Memorials   = {} -- plot index -> { obj, dbId, name, epitaph, died, respects, flowers }
local respected   = {} -- 'plot:identifier' -> true (one "pay respects" per character per restart)
local coronerWait = {} -- src -> os.time() of their last coroner call

local function deny(src, msg)
    if msg then Notify(src, msg, 'error', 'Funeral Home') end
    return false
end

local function pay(src, amount, reason)
    if not amount or amount <= 0 then return end
    Config.Hooks.FuneralPay(src, amount, reason)
    Notify(src, ('You earned $%d (%s).'):format(amount, reason), 'success', 'Funeral Home')
end

local function v3(v) return vector3(v.x, v.y, v.z) end

-- where is the prepared coffin of this morgue record right now? (prep table, carried, trunk, plot)
local function findRecordBody(id)
    for netId, c in pairs(Containers) do
        if c.body.record == id then return 'container', netId, c.body end
    end
    for vehNetId, t in pairs(Trunks) do
        for _, item in ipairs(t.items) do
            if item.body.record == id then return 'trunk', vehNetId, item.body end
        end
    end
    for i, sv in pairs(Services) do
        if sv.body.record == id then return 'service', i, sv.body end
    end
end

-- called by ReleaseBody (server/main.lua) when a prepared coffin is lost:
-- the body goes back into its drawer instead of vanishing
function ReturnRecordToMorgue(body)
    if not body.record then return end
    MySQL.update("UPDATE nayzeee_funeral_morgue SET status = 'stored' WHERE id = ?", { body.record })
    body.record = nil
end

-- players within radius of coords
local function playersNear(coords, radius)
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local pid = tonumber(id)
        local pc = GetPlayerCoords(pid)
        if pc and #(pc - coords) <= radius then list[#list + 1] = pid end
    end
    return list
end

-- ═══════════════════════════════════════════════════════════════
--  PLOT STATE (replicated so every client's menu knows what a plot is doing)
-- ═══════════════════════════════════════════════════════════════
local function syncPlots()
    local states = {}
    for i in ipairs(F.Plots) do
        local s, m = Services[i], Memorials[i]
        if s then
            states[i] = { s = s.stage, name = s.name, director = s.director }
        elseif m then
            states[i] = { s = 'memorial', name = m.name }
        else
            states[i] = { s = 'free' }
        end
    end
    GlobalState.nzFuneralPlots = states
end

-- ═══════════════════════════════════════════════════════════════
--  DUTY
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:funeralDuty', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or xPlayer.job.name ~= F.Job then return deny(src, 'You don\'t work at the funeral home.') end
    if not IsNear(src, L.Duty, 5.0) then return end

    local on = not Player(src).state.nzFuneralDuty
    Player(src).state:set('nzFuneralDuty', on, true)
    Notify(src, on and 'You are now ON duty.' or 'You are now OFF duty.', on and 'success' or 'inform', 'Funeral Home')
    if on then Tip(src, 'Grab a hearse from the garage. Coroner calls will appear on your map.') end
    Log(src, on and 'FUNERAL_DUTY_ON' or 'FUNERAL_DUTY_OFF', xPlayer.getName())
end)

-- changed job -> automatically off duty
AddEventHandler('esx:setJob', function(src, job)
    if job and job.name ~= F.Job and Player(src).state.nzFuneralDuty then
        Player(src).state:set('nzFuneralDuty', false, true)
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  HEARSE GARAGE
-- ═══════════════════════════════════════════════════════════════
lib.callback.register('nayzeee-bodybag:funeral:takeHearse', function(src)
    if not IsFuneral(src, 'Hearse') then return deny(src, 'Clock in first - only on-duty staff can take a hearse.') end
    if not IsNear(src, L.Garage, 8.0) then return false end
    if Hearses[src] and DoesEntityExist(Hearses[src]) then return deny(src, 'You already have a hearse out. Return it first.') end

    local sp = L.HearseSpawn
    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - v3(sp)) < 3.0 then return deny(src, 'The parking spot is blocked.') end
    end

    local veh = CreateVehicleServerSetter(F.Hearse.Model, 'automobile', sp.x, sp.y, sp.z, sp.w)
    local timeout = GetGameTimer() + 3000
    while not DoesEntityExist(veh) and GetGameTimer() < timeout do Wait(10) end
    if not DoesEntityExist(veh) then return deny(src, 'The hearse failed to spawn.') end

    local plate = (F.Hearse.Plate .. math.random(10, 99)):sub(1, 8)
    SetVehicleNumberPlateText(veh, plate)
    Hearses[src] = veh
    Log(src, 'HEARSE_OUT', plate)
    return { netId = NetworkGetNetworkIdFromEntity(veh), plate = plate }
end)

RegisterNetEvent('nayzeee-bodybag:server:funeralReturnHearse', function()
    local src = source
    local veh = Hearses[src]
    if not veh or not DoesEntityExist(veh) then
        Hearses[src] = nil
        return deny(src, 'You don\'t have a hearse out.')
    end
    if #(GetEntityCoords(veh) - L.Garage) > 20.0 then return deny(src, 'Bring the hearse back to the garage first.') end
    if Trunks[NetworkGetNetworkIdFromEntity(veh)] then return deny(src, 'Unload the bodies first.') end
    DeleteEntity(veh)
    Hearses[src] = nil
    Notify(src, 'Hearse returned.', 'success', 'Funeral Home')
end)

-- ═══════════════════════════════════════════════════════════════
--  CORONER CALLS (anyone can call, on-duty staff get a blip)
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:callCoroner', function(coords)
    local src = source
    local cfg = F.CoronerCalls
    if not cfg.Enabled then return end
    coords = ToVec3(coords)
    if not coords or not IsNear(src, coords, 10.0) then return end

    local now = os.time()
    if now - (coronerWait[src] or 0) < cfg.Cooldown then
        return deny(src, 'You already called the coroner. They\'re on their way.')
    end
    coronerWait[src] = now

    local sent = FuneralAlert(coords, 'Coroner Call', ('Body pickup requested by %s.'):format(GetCharName(src)))
    if sent > 0 then
        Notify(src, ('The coroner has been called (%d on duty).'):format(sent), 'success', 'Funeral Home')
    else
        Notify(src, 'No morticians are on duty right now.', 'error', 'Funeral Home')
    end
    Log(src, 'CORONER_CALLED', ('%d staff alerted'):format(sent))
end)

-- ═══════════════════════════════════════════════════════════════
--  MORGUE
-- ═══════════════════════════════════════════════════════════════
local function getRecord(id)
    return MySQL.single.await('SELECT * FROM nayzeee_funeral_morgue WHERE id = ?', { tonumber(id) or 0 })
end

local function recordName(r)
    return (r.identifiable == 1 and r.npc ~= 1 and r.name) or ('John Doe #' .. r.id)
end

local function recordDate(r)
    return type(r.created) == 'number' and os.date('%m/%d/%Y', math.floor(r.created / 1000)) or tostring(r.created or '?')
end

-- carried body -> morgue drawer
lib.callback.register('nayzeee-bodybag:funeral:storeBody', function(src, netId)
    if not IsFuneral(src, 'Morgue') then return deny(src, 'Only on-duty funeral staff can use the morgue.') end
    if not IsNear(src, L.Morgue, 6.0) then return false end
    local c = Containers[netId]
    if not c or c.carrier ~= src then return false end

    local body = c.body

    -- a prepared coffin that comes back just goes back into its drawer
    if body.record then
        local record = body.record
        RemoveContainer(netId)
        ReturnRecordToMorgue(body)
        Notify(src, ('Returned to drawer #%d.'):format(record), 'success', 'Morgue')
        return true
    end

    -- log it FIRST: if the database fails, nothing happens to the body
    local d = DescribeBody(body, true)
    local id = MySQL.insert.await([[INSERT INTO nayzeee_funeral_morgue
        (name, identifier, npc, identifiable, stage, dna, stored_by) VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        body.name, body.identifier, body.npc and 1 or 0, d.name and 1 or 0, d.stage,
        json.encode(body.dna or {}), GetCharName(src),
    })
    if not id then return deny(src, 'The morgue database is unavailable. Tell staff (sql/install.sql).') end
    if Containers[netId] ~= c then -- someone else dealt with it while we were saving
        MySQL.update('DELETE FROM nayzeee_funeral_morgue WHERE id = ?', { id })
        return false
    end
    RemoveContainer(netId) -- the bag / crate / coffin stays with the morgue
    DestroyBody(body, 'taken to the morgue')

    -- the same character only pays out once per cooldown (stops respawn-mode farming)
    local key = body.identifier
    local cooldown = (F.Pay.SameBodyCooldown or 30) * 60
    if not key or os.time() - (paidFor[key] or 0) >= cooldown then
        if key then paidFor[key] = os.time() end
        pay(src, body.npc and F.Pay.MorgueNPC or F.Pay.MorgueBody, 'morgue intake')
    end
    Notify(src, ('%s logged as record #%d.'):format(d.name or 'John Doe', id or 0), 'success', 'Morgue')
    Tip(src, 'Open the morgue records to issue a death certificate, cremate, or prepare a coffin for a funeral.')
    Log(src, 'MORGUE_IN', ('#%s %s'):format(id or '?', body.name or 'NPC'))
    return true
end)

lib.callback.register('nayzeee-bodybag:funeral:records', function(src)
    local police = IsPolice(src)
    if not IsFuneral(src) and not police then return nil end
    if not IsNear(src, L.Morgue, 8.0) and not IsNear(src, L.Crematory, 8.0) then return nil end

    local rows = MySQL.query.await('SELECT * FROM nayzeee_funeral_morgue ORDER BY id DESC LIMIT 50') or {}
    local list = {}
    for _, r in ipairs(rows) do
        list[#list + 1] = {
            id = r.id, name = recordName(r), identified = r.identifiable == 1 and r.npc ~= 1,
            npc = r.npc == 1, stage = r.stage, status = r.status, storedBy = r.stored_by, date = recordDate(r),
            dna = (police and Config.Evidence.PoliceSeeDna) and json.decode(r.dna or '[]') or nil,
        }
    end
    return list
end)

RegisterNetEvent('nayzeee-bodybag:server:funeralCertificate', function(id)
    local src = source
    if not IsFuneral(src, 'Certificate') or not IsNear(src, L.Morgue, 8.0) then return deny(src, 'You can\'t issue certificates.') end
    local r = getRecord(id)
    if not r then return end
    if not exports.ox_inventory:CanCarryItem(src, Config.Items.deathCertificate, 1) then return deny(src, 'Your pockets are full.') end
    exports.ox_inventory:AddItem(src, Config.Items.deathCertificate, 1, {
        description = ('Deceased: %s  \nDate: %s  \nCondition: %s  \nCertified by: %s'):format(
            recordName(r), recordDate(r), r.stage or 'unknown', GetCharName(src)),
    })
    Notify(src, 'Death certificate issued.', 'success', 'Morgue')
    Log(src, 'DEATH_CERTIFICATE', recordName(r))
end)

lib.callback.register('nayzeee-bodybag:funeral:cremate', function(src, id)
    if not IsFuneral(src, 'Cremate') then return deny(src, 'You\'re not trained to run the crematory.') end
    if not IsNear(src, L.Crematory, 6.0) then return false end
    local r = getRecord(id)
    if not r then return false end
    if not exports.ox_inventory:CanCarryItem(src, Config.Items.urn, 1) then return deny(src, 'Make room for the urn first.') end
    -- atomic: two employees can't cremate the same record
    if (MySQL.update.await("DELETE FROM nayzeee_funeral_morgue WHERE id = ? AND status = 'stored'", { r.id }) or 0) == 0 then
        return deny(src, 'That body isn\'t in its drawer.')
    end
    exports.ox_inventory:AddItem(src, Config.Items.urn, 1, {
        description = ('The ashes of %s  \nCremated %s'):format(recordName(r), os.date('%m/%d/%Y')),
    })
    pay(src, r.npc == 1 and (F.Pay.CremationNPC or 0) or F.Pay.Cremation, 'cremation')
    Tip(src, 'Hand the urn to the family - or lay it to rest yourself.')
    Log(src, 'FUNERAL_CREMATION', recordName(r))
    return true
end)

lib.callback.register('nayzeee-bodybag:funeral:prepare', function(src, id)
    if not IsFuneral(src, 'Morgue') then return deny(src, 'Only on-duty funeral staff can prepare bodies.') end
    if not IsNear(src, L.Morgue, 8.0) then return false end
    -- take the coffin FIRST so it can't be dropped / given away while we wait on the database
    if not exports.ox_inventory:RemoveItem(src, Config.Items.coffin, 1) then
        return deny(src, 'You need a coffin (buy one at the counter).')
    end
    local r = getRecord(id)
    if not r or (MySQL.update.await("UPDATE nayzeee_funeral_morgue SET status = 'prepared' WHERE id = ? AND status = 'stored'", { r.id }) or 0) == 0 then
        exports.ox_inventory:AddItem(src, Config.Items.coffin, 1)
        return deny(src, 'That body has already been prepared.')
    end

    local p = L.PrepTable
    local obj, netId = SpawnProp('coffin', vector3(p.x, p.y, p.z), p.w)
    if not obj then
        MySQL.update("UPDATE nayzeee_funeral_morgue SET status = 'stored' WHERE id = ?", { r.id })
        exports.ox_inventory:AddItem(src, Config.Items.coffin, 1)
        return deny(src, 'The coffin couldn\'t be placed.')
    end

    AddContainer(obj, netId, 'coffin', {
        name = recordName(r), npc = r.npc == 1 or r.identifiable ~= 1, dna = json.decode(r.dna or '[]') or {},
        resolved = true, embalmed = true, record = r.id, baggedAt = os.time(),
    })
    Notify(src, ('%s is embalmed and laid in the coffin on the prep table.'):format(recordName(r)), 'success', 'Morgue')
    Tip(src, 'Pick up the coffin, load it into the hearse, and drive to a cemetery plot.')
    Log(src, 'FUNERAL_PREPARED', recordName(r))
    return true
end)

RegisterNetEvent('nayzeee-bodybag:server:funeralDiscard', function(id)
    local src = source
    if not IsFuneral(src, 'ClearPlot') and not IsStaff(src) then return deny(src, 'Only the director can discard records.') end
    if not IsNear(src, L.Morgue, 8.0) then return end
    local r = getRecord(id)
    if not r then return end
    MySQL.update('DELETE FROM nayzeee_funeral_morgue WHERE id = ?', { r.id })

    -- remove its prepared coffin, wherever it is
    local where, key, body = findRecordBody(r.id)
    if body then body.record = nil end
    if where == 'container' then
        RemoveContainer(key)
    elseif where == 'trunk' then
        RemoveFromTrunk(key, body)
    elseif where == 'service' then
        EndServiceForBody(key, body)
    end
    Notify(src, ('Record #%d discarded.'):format(r.id), 'inform', 'Morgue')
    Log(src, 'MORGUE_DISCARD', recordName(r))
end)

-- ═══════════════════════════════════════════════════════════════
--  SHOP (public counter)
-- ═══════════════════════════════════════════════════════════════
lib.callback.register('nayzeee-bodybag:funeral:buy', function(src, index, amount)
    local entry = F.Shop.Items[tonumber(index) or 0]
    amount = math.floor(tonumber(amount) or 1)
    if not entry or amount < 1 or amount > 10 then return false end
    if not IsNear(src, L.Shop, 6.0) then return false end
    if entry.jobOnly and not IsFuneral(src) then return deny(src, 'That\'s for funeral staff only.') end

    local xPlayer = ESX.GetPlayerFromId(src)
    local account = xPlayer and xPlayer.getAccount(F.Shop.Account)
    local price = entry.price * amount
    if not account or account.money < price then return deny(src, ('You need $%d.'):format(price)) end
    if not exports.ox_inventory:CanCarryItem(src, entry.item, amount) then return deny(src, 'You can\'t carry that.') end

    xPlayer.removeAccountMoney(F.Shop.Account, price, 'Funeral home purchase')
    exports.ox_inventory:AddItem(src, entry.item, amount)
    Notify(src, ('Bought %dx %s for $%d.'):format(amount, entry.label, price), 'success', 'Funeral Home')
    return true
end)

-- ═══════════════════════════════════════════════════════════════
--  FUNERAL SERVICES
--  Place Casket  ->  Begin Service  ->  (MinDuration)  ->  Lower Casket
-- ═══════════════════════════════════════════════════════════════
local function plotAt(i)
    i = tonumber(i)
    return i and F.Plots[i] and i or nil, i and F.Plots[i]
end

local function announce(coords, msg, title)
    for _, pid in ipairs(playersNear(coords, F.Service.MournerRadius)) do
        Notify(pid, msg, 'inform', title or 'Funeral')
    end
end

lib.callback.register('nayzeee-bodybag:funeral:placeCasket', function(src, plotIndex, netId)
    local i, plot = plotAt(plotIndex)
    if not i then return false end
    if not IsFuneral(src, 'Service') then return deny(src, 'Only funeral directors can hold a service.') end
    if Services[i] or Memorials[i] then return deny(src, 'That plot is taken.') end
    if not IsNear(src, plot.coords, 8.0) then return false end
    local c = Containers[netId]
    if not c or c.carrier ~= src or c.kind ~= 'coffin' then return deny(src, 'You need to be carrying a coffin.') end

    local name = DescribeBody(c.body).name or 'an unknown soul'
    local sv = { body = c.body, director = src, stage = 'placed', name = name }
    Services[i] = sv -- reserve the plot before we wait for the prop
    RemoveContainer(netId)
    local obj = SpawnProp('coffin', PlotCasketCoords(plot), plot.heading)
    if not obj then
        Services[i] = nil
        ReleaseBody(c.body)
        return deny(src, 'The casket couldn\'t be placed.')
    end
    sv.obj = obj
    c.body.where = { type = 'service', key = i }
    SetVictimStatus(c.body, 'coffin')
    syncPlots()
    Tip(src, 'When the mourners are here, open the plot menu and Begin Service.')
    return true
end)

RegisterNetEvent('nayzeee-bodybag:server:funeralBegin', function(plotIndex, epitaph)
    local src = source
    local i, plot = plotAt(plotIndex)
    local s = i and Services[i]
    if not s or s.stage ~= 'placed' or not IsFuneral(src, 'Service') or not IsNear(src, plot.coords, 10.0) then return end

    epitaph = tostring(epitaph or ''):gsub('[<>]', ''):sub(1, F.Service.EpitaphMaxLength)
    s.stage, s.startedAt, s.epitaph, s.director = 'service', os.time(), epitaph, src
    syncPlots()

    announce(plot.coords, ('The funeral service for %s has begun. Please gather round.'):format(s.name))
    if F.Service.AnnounceServerWide then
        TriggerClientEvent('nayzeee-bodybag:client:funeralAnnounce', -1, plot.coords, s.name, true)
    end
    Notify(src, ('Service started. You can lower the casket in %s.'):format(FormatTime(F.Service.MinDuration)), 'success', 'Funeral')
    Log(src, 'FUNERAL_SERVICE_START', s.name)
end)

local function spawnMemorial(i, m)
    local plot = F.Plots[i]
    local obj = SpawnProp('tombstone', plot.coords, plot.heading)
    if not obj then return false end
    m.obj = obj
    Memorials[i] = m
    Entity(obj).state:set('nzMemorial', {
        plot = i, name = m.name, epitaph = m.epitaph, died = m.died, respects = m.respects, flowers = m.flowers,
    }, true)
    return true
end

local function updateMemorialState(i)
    local m = Memorials[i]
    if not m or not m.obj or not DoesEntityExist(m.obj) then return end
    Entity(m.obj).state:set('nzMemorial', {
        plot = i, name = m.name, epitaph = m.epitaph, died = m.died, respects = m.respects, flowers = m.flowers,
    }, true)
end

RegisterNetEvent('nayzeee-bodybag:server:funeralLower', function(plotIndex)
    local src = source
    local i, plot = plotAt(plotIndex)
    local s = i and Services[i]
    if not s or s.stage ~= 'service' or not IsFuneral(src, 'Service') or not IsNear(src, plot.coords, 10.0) then return end
    local left = F.Service.MinDuration - (os.time() - s.startedAt)
    if left > 0 then return deny(src, ('Give the mourners a moment - %s left.'):format(FormatTime(left))) end

    -- the headstone claims the plot right away so nothing can be placed while we save
    local m = { name = s.name, epitaph = s.epitaph, died = os.date('%m/%d/%Y'), respects = 0, flowers = 0 }
    Services[i] = nil
    Memorials[i] = m
    if s.obj and DoesEntityExist(s.obj) then DeleteEntity(s.obj) end
    DestroyBody(s.body, 'funeral')
    if s.body.record then
        MySQL.update('DELETE FROM nayzeee_funeral_morgue WHERE id = ?', { s.body.record })
        s.body.record = nil
    end

    m.dbId = MySQL.insert.await(
        'INSERT INTO nayzeee_funeral_memorials (plot, name, epitaph, died, director) VALUES (?, ?, ?, ?, ?)',
        { i, m.name, m.epitaph, m.died, GetCharName(src) })
    spawnMemorial(i, m)
    syncPlots()

    announce(plot.coords, ('%s has been laid to rest.'):format(s.name))
    if F.Service.AnnounceServerWide then
        TriggerClientEvent('nayzeee-bodybag:client:funeralAnnounce', -1, plot.coords, s.name, false)
    end
    pay(src, F.Pay.Service, 'funeral service')
    Log(src, 'FUNERAL_COMPLETE', ('%s at plot %d'):format(s.name, i))
end)

RegisterNetEvent('nayzeee-bodybag:server:funeralCancel', function(plotIndex)
    local src = source
    local i, plot = plotAt(plotIndex)
    local s = i and Services[i]
    if not s or not IsFuneral(src, 'Service') or not IsNear(src, plot.coords, 10.0) then return end

    Services[i] = nil
    if not s.obj then return end -- still being placed
    local spot = DoesEntityExist(s.obj) and GetEntityCoords(s.obj) or PlotCasketCoords(plot)
    if DoesEntityExist(s.obj) then DeleteEntity(s.obj) end
    local obj, netId = SpawnProp('coffin', spot, plot.heading)
    if obj then AddContainer(obj, netId, 'coffin', s.body) else ReleaseBody(s.body) end
    syncPlots()
    if s.stage == 'service' and F.Service.AnnounceServerWide then
        TriggerClientEvent('nayzeee-bodybag:client:funeralAnnounce', -1, plot.coords, s.name, false)
    end
    Notify(src, 'Service cancelled. The coffin is back on the ground.', 'inform', 'Funeral')
end)

-- ═══════════════════════════════════════════════════════════════
--  HEADSTONES - pay respects / lay flowers / clear
-- ═══════════════════════════════════════════════════════════════
RegisterNetEvent('nayzeee-bodybag:server:memorialRespects', function(plotIndex)
    local src = source
    local i = plotAt(plotIndex)
    local m = i and Memorials[i]
    if not m or not IsNearEntity(src, m.obj, 5.0) then return end
    local key = i .. ':' .. (GetIdentifier(src) or src)
    if respected[key] then return deny(src, 'You already paid your respects here today.') end
    respected[key] = true
    m.respects = m.respects + 1
    MySQL.update('UPDATE nayzeee_funeral_memorials SET respects = respects + 1 WHERE id = ?', { m.dbId })
    updateMemorialState(i)
    Notify(src, ('You paid your respects to %s.'):format(m.name), 'inform', 'Rest In Peace')
end)

RegisterNetEvent('nayzeee-bodybag:server:memorialFlowers', function(plotIndex)
    local src = source
    local i = plotAt(plotIndex)
    local m = i and Memorials[i]
    if not m or not IsNearEntity(src, m.obj, 5.0) then return end
    if not HasItem(src, Config.Items.flowers) then return deny(src, 'You need flowers (sold at the funeral home).') end
    exports.ox_inventory:RemoveItem(src, Config.Items.flowers, 1)
    m.flowers = m.flowers + 1
    MySQL.update('UPDATE nayzeee_funeral_memorials SET flowers = flowers + 1 WHERE id = ?', { m.dbId })
    updateMemorialState(i)
    Notify(src, ('You laid flowers for %s.'):format(m.name), 'success', 'Rest In Peace')
end)

RegisterNetEvent('nayzeee-bodybag:server:memorialClear', function(plotIndex)
    local src = source
    local i = plotAt(plotIndex)
    local m = i and Memorials[i]
    if not m then return end
    if not IsFuneral(src, 'ClearPlot') and not IsStaff(src) then return deny(src, 'Only the director can clear a plot.') end
    Memorials[i] = nil
    if m.obj and DoesEntityExist(m.obj) then DeleteEntity(m.obj) end
    MySQL.update('DELETE FROM nayzeee_funeral_memorials WHERE id = ?', { m.dbId })
    syncPlots()
    Notify(src, ('Plot %d is free again.'):format(i), 'inform', 'Funeral Home')
    Log(src, 'PLOT_CLEARED', ('%s (plot %d)'):format(m.name, i))
end)

-- ═══════════════════════════════════════════════════════════════
--  SERVICE CLEANUP (used by revive, discard, admin "clear all")
-- ═══════════════════════════════════════════════════════════════
-- remove a casket from its plot without a funeral (body is handled by the caller)
function EndServiceForBody(i, body)
    local sv = Services[i]
    if not sv or (body and sv.body ~= body) then return end
    Services[i] = nil
    if sv.obj and DoesEntityExist(sv.obj) then DeleteEntity(sv.obj) end
    if sv.stage == 'service' and F.Service.AnnounceServerWide then
        TriggerClientEvent('nayzeee-bodybag:client:funeralAnnounce', -1, F.Plots[i].coords, sv.name, false)
    end
    syncPlots()
end

function ClearAllServices()
    local n = 0
    for i, sv in pairs(Services) do
        EndServiceForBody(i)
        ReleaseBody(sv.body)
        n = n + 1
    end
    return n
end

-- caskets that vanish (cleanup scripts) free their victim; victims stay next to their casket
CreateThread(function()
    while true do
        Wait(3000)
        for i, sv in pairs(Services) do
            if sv.obj then
                if not DoesEntityExist(sv.obj) then
                    Services[i] = nil
                    ReleaseBody(sv.body)
                    syncPlots()
                elseif sv.body.victimId then
                    TriggerClientEvent('nayzeee-bodybag:client:syncToBag', sv.body.victimId, GetEntityCoords(sv.obj))
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  STARTUP / CLEANUP
-- ═══════════════════════════════════════════════════════════════
local function restoreFuneral()
    -- prepared coffins don't survive a restart -> back into their drawers
    MySQL.update.await("UPDATE nayzeee_funeral_morgue SET status = 'stored' WHERE status = 'prepared'")
    if (F.Morgue.RecordLifetimeDays or 0) > 0 then
        MySQL.update.await('DELETE FROM nayzeee_funeral_morgue WHERE created < (NOW() - INTERVAL ? DAY)', { F.Morgue.RecordLifetimeDays })
    end
    local records = MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_funeral_morgue') or 0
    Console.check('morgue', 'info', 'Morgue', records > 0
        and ('%d %s in the drawers'):format(records, records == 1 and 'body' or 'bodies') or 'empty')

    local restored, skipped = 0, 0
    for _, row in ipairs(MySQL.query.await('SELECT * FROM nayzeee_funeral_memorials') or {}) do
        local i = tonumber(row.plot)
        if i and F.Plots[i] and not Memorials[i] then
            if spawnMemorial(i, { dbId = row.id, name = row.name, epitaph = row.epitaph, died = row.died,
                respects = row.respects or 0, flowers = row.flowers or 0 }) then restored = restored + 1 end
        else
            skipped = skipped + 1
        end
    end
    syncPlots()
    Console.check('memorials', restored > 0 and 'info' or 'ok', 'Headstones',
        restored > 0 and ('%d back on their plots'):format(restored) or 'none yet')
    if skipped > 0 then
        Console.log('warn', '%d headstone(s) point at a plot that no longer exists in Config.Funeral.Plots', skipped)
    end
end

AddEventHandler('nayzeee-bodybag:databaseReady', function(dbOk)
    if not dbOk then
        Console.check('memorials', 'warn', 'Headstones', 'not restored: the database is not ready')
        return Console.done('funeral')
    end
    local ok, err = pcall(restoreFuneral)
    if not ok then
        Console.check('memorials', 'error', 'Headstones', 'restore failed: see the note below')
        Console.log('error', 'funeral restore: %s', tostring(err))
    end
    Console.done('funeral')
end)

AddEventHandler('playerDropped', function()
    local src = source
    coronerWait[src] = nil
    local veh = Hearses[src]
    -- an empty hearse is returned; one with bodies inside stays put so a colleague can unload it
    if veh and DoesEntityExist(veh) and not Trunks[NetworkGetNetworkIdFromEntity(veh)] then DeleteEntity(veh) end
    Hearses[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, veh in pairs(Hearses) do if DoesEntityExist(veh) then DeleteEntity(veh) end end
    for _, s in pairs(Services) do
        ReleaseBody(s.body)
        if s.obj and DoesEntityExist(s.obj) then DeleteEntity(s.obj) end
    end
    for _, m in pairs(Memorials) do if m.obj and DoesEntityExist(m.obj) then DeleteEntity(m.obj) end end
end)
