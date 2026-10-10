--[[ Wash units — private floors in GTA's (emptied) counterfeit cash factory.
     One routing bucket per unit: a crew only ever sees its own floor and machines. ]]

Facility = { list = {}, flags = {} }

local F = Config.Facility
local now = os.time

local function fail(msg) return { ok = false, err = msg } end

function Facility.bucket(id) return F.bucketBase + id end

function Facility.byBucket(bucket)
    local id = (tonumber(bucket) or 0) - F.bucketBase
    return id > 0 and Facility.list[id] or nil
end

function Facility.get(id) return Facility.list[tonumber(id)] end

function Facility.entranceCoords() return F.entrance.xyz end

local function save(f)
    MySQL.update('UPDATE nzmw_facilities SET members = ?, upgrades = ? WHERE id = ?',
        { json.encode(f.members), json.encode(f.upgrades), f.id })
end

local function load(row)
    local f = {
        id = row.id, owner = row.owner, ownerName = row.owner_name,
        members = json.decode(row.members or '{}') or {},
        upgrades = json.decode(row.upgrades or '{}') or {},
    }
    for key in pairs(F.upgrades) do f.upgrades[key] = tonumber(f.upgrades[key]) or 0 end
    Facility.list[f.id] = f
    return f
end

function Facility.start()
    if not F.enabled then return end
    for _, row in ipairs(MySQL.query.await('SELECT * FROM nzmw_facilities') or {}) do load(row) end
end

-- 'owner' | 'member' | nil
function Facility.role(cid, id)
    local f = Facility.list[id]
    if not f or not cid then return nil end
    if f.owner == cid then return 'owner' end
    if f.members[cid] then return 'member' end
end

function Facility.isMember(src, id)
    return Facility.role(Bridge.getIdentifier(src), id) ~= nil
end

function Facility.slots(f)
    return F.baseSlots + (f.upgrades.expansion or 0) * 2
end

function Facility.machines(id)
    local out = {}
    for _, st in pairs(Stations.list) do
        if st.facility == id then out[#out + 1] = st end
    end
    return out
end

-- soundproofing: each level cuts 911 calls from machines by 35%
function Facility.noiseMult(st)
    local f = st.facility and Facility.list[st.facility]
    if not f then return 1.0 end
    return math.max(0.1, 1.0 - 0.35 * (f.upgrades.soundproof or 0))
end

function Facility.flag(id) Facility.flags[id] = now() end

local function crewSources(f)
    local out = {}
    local function add(cid)
        local s = Bridge.getSourceByIdentifier(cid)
        if s then out[#out + 1] = s end
    end
    add(f.owner)
    for cid in pairs(f.members) do add(cid) end
    return out
end

local function nearDoor(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - F.entrance.xyz) <= 4.0
end

local function insideUnit(src)
    return Facility.byBucket(GetPlayerRoutingBucket(src))
end

---------------------------------------------------------------------------------------------------
-- entering / leaving
---------------------------------------------------------------------------------------------------
local moving = {} -- src → time of the last enter/leave teleport (watchdog grace)

local function moveIn(src, f, role)
    moving[src] = now()
    local bucket = Facility.bucket(f.id)
    SetRoutingBucketPopulationEnabled(bucket, false)
    SetPlayerRoutingBucket(src, bucket)
    Player(src).state:set('nzmwBucket', bucket, true)
    Player(src).state:set('nzmwUnit', { id = f.id, role = role }, true)
    TriggerClientEvent('nzmw:unit:teleport', src, { x = F.interior.inside.x, y = F.interior.inside.y, z = F.interior.inside.z, w = F.interior.inside.w })
end

local function moveOut(src)
    moving[src] = now()
    SetPlayerRoutingBucket(src, 0)
    Player(src).state:set('nzmwBucket', 0, true)
    Player(src).state:set('nzmwUnit', nil, true)
    TriggerClientEvent('nzmw:unit:teleport', src, { x = F.entrance.x, y = F.entrance.y, z = F.entrance.z, w = (F.entrance.w + 180.0) % 360 })
end

lib.callback.register('nzmw:unit:list', function(src)
    if not F.enabled or not nearDoor(src) then return fail('Not here.') end
    local cid = Bridge.getIdentifier(src)
    local units, owned = {}, 0
    for id, f in pairs(Facility.list) do
        local role = Facility.role(cid, id)
        if role then
            if role == 'owner' then owned = owned + 1 end
            units[#units + 1] = { id = id, role = role, ownerName = f.ownerName, machines = #Facility.machines(id), slots = Facility.slots(f) }
        end
    end
    table.sort(units, function(a, b) return a.id < b.id end)
    local res = { ok = true, units = units, canBuy = owned < F.maxOwned, price = F.price, bank = Bridge.getAccount(src, 'bank'), now = now() }
    if NZ.isPoliceJob(Bridge.getJob(src)) then
        res.police = true
        res.flagged = {}
        for id, t in pairs(Facility.flags) do
            if now() - t <= F.flagMinutes * 60 and Facility.list[id] then
                res.flagged[#res.flagged + 1] = { id = id, at = t }
            end
        end
        table.sort(res.flagged, function(a, b) return a.at > b.at end)
        res.breachTime = F.breachTime
    end
    return res
end)

local buying = {} -- one lease purchase in flight per player

lib.callback.register('nzmw:unit:buy', function(src)
    if not F.enabled or not nearDoor(src) then return fail('Not here.') end
    if buying[src] then return fail('Hold on…') end
    buying[src] = true
    local res = Facility.buy(src)
    buying[src] = nil
    return res
end)

function Facility.buy(src)
    local cid = Bridge.getIdentifier(src)
    local owned = 0
    for _, f in pairs(Facility.list) do if f.owner == cid then owned = owned + 1 end end
    if owned >= F.maxOwned then return fail('You already lease a unit.') end
    if Bridge.getAccount(src, 'bank') < F.price then return fail(('The lease is %s. Your bank can\'t cover it.'):format(NZ.money(F.price))) end
    if not Bridge.removeAccount(src, 'bank', F.price, 'nz_moneywash unit lease') then return fail('Payment failed.') end
    local name = Bridge.getName(src)
    local id = MySQL.insert.await('INSERT INTO nzmw_facilities (owner, owner_name, members, upgrades) VALUES (?, ?, ?, ?)',
        { cid, name, '{}', '{}' })
    if not id then
        Bridge.addMoney(src, 'bank', F.price, 'nz_moneywash refund')
        return fail('Database error — you were refunded.')
    end
    local f = load({ id = id, owner = cid, owner_name = name, members = '{}', upgrades = '{}' })
    Bridge.log('Unit leased', { { 'Player', name .. ' (' .. src .. ')' }, { 'Unit', '#' .. id }, { 'Price', NZ.money(F.price) } })
    moveIn(src, f, 'owner')
    return { ok = true, id = id }
end

lib.callback.register('nzmw:unit:enter', function(src, id)
    local f = Facility.get(id)
    if not f or not nearDoor(src) then return fail('Not here.') end
    local role = Facility.role(Bridge.getIdentifier(src), f.id)
    if not role then return fail('You don\'t have a key to that unit.') end
    moveIn(src, f, role)
    return { ok = true }
end)

lib.callback.register('nzmw:unit:breach', function(src, id, phase)
    local f = Facility.get(id)
    if not f then return fail('No unit with that number.') end
    if not NZ.isPoliceJob(Bridge.getJob(src)) then return fail('Police only.') end
    if not nearDoor(src) then return fail('Not here.') end
    f.breach = f.breach or {}
    if phase == 'start' then
        f.breach[src] = now()
        if (f.upgrades.alarm or 0) > 0 then
            for _, s in ipairs(crewSources(f)) do
                Bridge.notify(s, 'Door alarm', ('Police are breaching unit #%d!'):format(f.id), 'error', 12000)
            end
        end
        return { ok = true }
    end
    local started = f.breach[src]
    if not started or now() - started < math.floor(F.breachTime / 1000 * 0.8) then return fail('You were interrupted.') end
    f.breach[src] = nil
    moveIn(src, f, 'police')
    Bridge.log('Unit breached', { { 'Officer', Bridge.getName(src) }, { 'Unit', '#' .. f.id }, { 'Owner', f.ownerName } })
    return { ok = true }
end)

lib.callback.register('nzmw:unit:leave', function(src)
    if not insideUnit(src) then return fail('You are not in a unit.') end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - F.interior.inside.xyz) > 4.0 then return fail('Go to the door.') end
    moveOut(src)
    return { ok = true }
end)

---------------------------------------------------------------------------------------------------
-- terminal
---------------------------------------------------------------------------------------------------
local function terminalData(src, f)
    local cid = Bridge.getIdentifier(src)
    local role = Facility.role(cid, f.id)
    local machines = {}
    for _, st in ipairs(Facility.machines(f.id)) do
        machines[#machines + 1] = { id = st.id, type = st.type, label = st.label, state = st.state, wear = NZ.round(st.wear or 0, 1),
            endsAt = st.endsAt, count = st.count, placedBy = st.ownerName }
    end
    table.sort(machines, function(a, b) return a.id < b.id end)
    local members = {}
    for mcid, name in pairs(f.members) do members[#members + 1] = { cid = mcid, name = name } end
    table.sort(members, function(a, b) return a.name < b.name end)
    local upgrades = {}
    for key, u in pairs(F.upgrades) do
        local lvl = f.upgrades[key] or 0
        upgrades[#upgrades + 1] = { key = key, label = u.label, desc = u.desc, level = lvl, max = u.max, price = u.price[lvl + 1] }
    end
    table.sort(upgrades, function(a, b) return a.label < b.label end)
    return {
        ok = true, id = f.id, ownerName = f.ownerName, role = role, isOwner = role == 'owner',
        slots = Facility.slots(f), used = #machines, machines = machines, members = members,
        upgrades = upgrades, shop = F.shop, bank = Bridge.getAccount(src, 'bank'), now = now(),
        name = Bridge.getName(src), labels = Config.ItemLabels,
    }
end

-- the terminal only works from inside your own unit
local function myUnit(src)
    local f = insideUnit(src)
    if not f then return nil, fail('Use the terminal inside your unit.') end
    if not Facility.isMember(src, f.id) then return nil, fail('This isn\'t your unit.') end
    return f
end

lib.callback.register('nzmw:unit:data', function(src)
    local f, err = myUnit(src)
    if not f then return err end
    return terminalData(src, f)
end)

lib.callback.register('nzmw:unit:addMember', function(src, target)
    local f, err = myUnit(src)
    if not f then return err end
    if f.owner ~= Bridge.getIdentifier(src) then return fail('Only the leaseholder can hand out keys.') end
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return fail('No player with that ID.') end
    local tcid = Bridge.getIdentifier(target)
    if not tcid then return fail('That player isn\'t loaded in.') end
    if tcid == f.owner or f.members[tcid] then return fail('They already have a key.') end
    f.members[tcid] = Bridge.getName(target)
    save(f)
    Bridge.notify(target, 'New key', ('%s gave you a key to wash unit #%d.'):format(Bridge.getName(src), f.id), 'success', 8000)
    return terminalData(src, f)
end)

lib.callback.register('nzmw:unit:removeMember', function(src, mcid)
    local f, err = myUnit(src)
    if not f then return err end
    if f.owner ~= Bridge.getIdentifier(src) then return fail('Only the leaseholder can take keys back.') end
    if not f.members[mcid] then return fail('Not on the key list.') end
    f.members[mcid] = nil
    save(f)
    -- anyone booted while inside gets walked out
    local s = Bridge.getSourceByIdentifier(mcid)
    if s and GetPlayerRoutingBucket(s) == Facility.bucket(f.id) then moveOut(s) end
    return terminalData(src, f)
end)

lib.callback.register('nzmw:unit:order', function(src, key)
    local f, err = myUnit(src)
    if not f then return err end
    local item
    for _, it in ipairs(F.shop) do if it.key == key then item = it break end end
    if not item then return fail('Unknown item.') end
    if Bridge.getAccount(src, 'bank') < item.price then return fail('Your bank can\'t cover that.') end
    if not Inv.canCarry(src, item.item, item.amount) then return fail('You can\'t carry that.') end
    if not Bridge.removeAccount(src, 'bank', item.price, 'nz_moneywash supplies') then return fail('Payment failed.') end
    Inv.add(src, item.item, item.amount)
    local res = terminalData(src, f)
    res.toast = ('%s delivered.'):format(item.label)
    return res
end)

lib.callback.register('nzmw:unit:upgrade', function(src, key)
    local f, err = myUnit(src)
    if not f then return err end
    if f.owner ~= Bridge.getIdentifier(src) then return fail('Only the leaseholder can renovate.') end
    local u = F.upgrades[key]
    if not u then return fail('Unknown upgrade.') end
    local lvl = f.upgrades[key] or 0
    if lvl >= u.max then return fail('Already maxed out.') end
    local price = u.price[lvl + 1]
    if Bridge.getAccount(src, 'bank') < price then return fail('Your bank can\'t cover that.') end
    if not Bridge.removeAccount(src, 'bank', price, 'nz_moneywash upgrade') then return fail('Payment failed.') end
    f.upgrades[key] = lvl + 1
    save(f)
    local res = terminalData(src, f)
    res.toast = ('%s level %d installed.'):format(u.label, lvl + 1)
    return res
end)

-- dropped players reset to the world bucket on reconnect; the client walks them out of the interior
AddEventHandler('playerDropped', function()
    local src = source
    moving[src] = nil
    if GetPlayerRoutingBucket(src) ~= 0 then SetPlayerRoutingBucket(src, 0) end
end)

-- Watchdog: nobody stays in a unit bucket outside the factory (death/respawn, logout, /tp …),
-- and nobody stands in the factory while in the world bucket (reconnected inside).
CreateThread(function()
    if not F.enabled then return end
    while true do
        Wait(5000)
        for _, sid in ipairs(GetPlayers()) do
            local src = tonumber(sid)
            local ped = GetPlayerPed(src)
            if ped ~= 0 and now() - (moving[src] or 0) > 8 then
                local pos = GetEntityCoords(ped)
                local dist = #(pos - F.interior.coords)
                local down = pos.z < F.interior.coords.z + 12.0 -- actually in the interior, not on the docks above it
                local bucket = GetPlayerRoutingBucket(src)
                if Facility.byBucket(bucket) and dist > 80.0 then
                    SetPlayerRoutingBucket(src, 0)
                    Player(src).state:set('nzmwBucket', 0, true)
                    Player(src).state:set('nzmwUnit', nil, true)
                elseif bucket == 0 and down and dist < 45.0 and Bridge.getIdentifier(src) then
                    moveOut(src)
                end
            end
        end
    end
end)
