--[[
    NAYZEEE AMBULANCE - Client: pharmacy counters, health insurance & billing (pharmacy module)

    Position type 'pharmacy' (NZA.Points.RegisterType): an optional pharmacist NPC stands at
    the position (local ped, scenario idle, turns and waves when you open the shop), a map
    blip, target options (Browse / Insurance / Bills / Manage stock) and our own
    "[E] Pharmacy" prompt at the counter (hidden when the bridge already shows its built-in
    [E] target prompt). The window is the 'pharmacy' NUI app (v5 window): shop with
    categories, search and cart, health insurance plans, open bills, staff stock & sales log.

    Check-in desks (the check-in module's 'checkin' positions) get "[H] Pay medical bills"
    while the player has open bills (Config.Pharmacy.desk): the window opens in desk mode
    (Bills + Insurance). The open-bill count is pushed by the server (nza:pharmacy:bills).

    Medics (Config.Pharmacy.invoice.perm, on duty) get "Send bill" on players (patient menu
    and EMS radial → Patient) which opens the app in its compact bill mode.

    Client API
      NZA.Pharmacy.Open(pointId, tab?) → bool     tab = 'shop'|'insurance'|'bills'|'stock'|'sales'
                                                  (works for 'pharmacy' and 'checkin' positions;
                                                  a check-in desk opens in desk mode: insurance + bills)
      NZA.Pharmacy.Close()                        NZA.Pharmacy.IsOpen() → bool
      NZA.Pharmacy.Bill(serverId) → bool          medic bill window for that player
    Exports: OpenPharmacy(pointId, tab?) · ClosePharmacy() · SendBill(serverId)

    Net events handled: nza:pharmacy:bills (count, total)
    Callbacks used: nza:pharmacy:open / refresh / buy / staff / restock, nza:pharmacy:bills:count,
                    nza:pharmacy:insurance:buy, nza:pharmacy:bills:pay,
                    nza:pharmacy:invoice:info / invoice:send
    NUI callbacks:  pharmacy:buy { lines[{id, qty}], method, total } · pharmacy:insurance { plan, method }
                    pharmacy:payBills { id | 'all', method } · pharmacy:refresh · pharmacy:staff
                    pharmacy:restock { id, qty, from } · pharmacy:invoice { sid, amount, reason }
                    pharmacy:close (core) → session ends
    Interactions:   nza_pharmacy_bill (players, order 90)   Radial: pharmacy_bill (parent 'patient')
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Pharmacy = NZA.Pharmacy or {}
local PH = NZA.Pharmacy
local APP = 'pharmacy'
local PROMPT = 'nza_pharmacy'
local PROMPT_DESK = 'nza_pharmacy_desk'

local peds = {}          -- [pointId] = ped entity | false while loading
local blips = {}         -- [pointId] = blip handle
local session = nil      -- { point, coords, mode, sid? }
local busy = false
local bills = { count = 0, total = 0, known = false }   -- own open bills (server push)

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function L(key, ...) return NZA.L('pharmacy.' .. key, ...) end

local function cfg(section)
    local c = Config.Pharmacy or {}
    if section then return type(c[section]) == 'table' and c[section] or {} end
    return c
end

local function toast(msg, kind, title)
    if not msg or msg == '' then return end
    NZA.UI.Toast({ title = title or L('title'), message = msg, type = kind or 'error', icon = 'pill' })
end

-- ox_lib callback with a safe reply table
local function call(name, ...)
    local ok, res = pcall(lib.callback.await, name, false, ...)
    if not ok or type(res) ~= 'table' then
        return { ok = false, err = 'error', msg = L('err_error') }
    end
    return res
end

local function pointData(point)
    local d = {}
    for k, v in pairs(cfg('pointDefaults')) do d[k] = v end
    if point and type(point.data) == 'table' then
        for k, v in pairs(point.data) do d[k] = v end
    end
    return d
end

local function pointPos(point)
    local c = point and point.coords
    if not c then return nil end
    return vector3((tonumber(c.x) or 0.0) + 0.0, (tonumber(c.y) or 0.0) + 0.0, (tonumber(c.z) or 0.0) + 0.0), (tonumber(c.w or c.h) or 0.0) + 0.0
end

local function staffRec()
    return (NZA.Staff and NZA.Staff.Get and NZA.Staff.Get()) or {}
end

local function memberOf(point)
    local rec = staffRec()
    if rec.admin then return true end
    local dept = rec.dept or rec.hospital
    return dept ~= nil and point ~= nil and point.hospital ~= nil and dept == point.hospital
end

-- may this player use the counter at all (staff-only counters hide for everyone else)
local function canUse(point)
    if cfg().enabled == false or not point then return false end
    if pointData(point).staffOnly == true then
        local rec = staffRec()
        return rec.admin == true or (memberOf(point) and rec.onDuty == true)
    end
    return true
end

local function deptLabel(point)
    if point and point.hospital and NZA.Hospitals and NZA.Hospitals.Department then
        local ok, d = pcall(NZA.Hospitals.Department, point.hospital)
        if ok and type(d) == 'table' and d.label then return d.label end
    end
    return nil
end

local function counterLabel(point)
    if point and type(point.label) == 'string' and point.label ~= '' then return point.label end
    return deptLabel(point) or L('title')
end

local function moneyText(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local out = tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if out:sub(1, 1) == ',' then out = out:sub(2) end
    return '$' .. out
end

local function builtinTarget()
    if not (Bridge and Bridge.Target and Bridge.Target.Resource) then return false end
    local ok, res = pcall(Bridge.Target.Resource)
    return ok and res == 'builtin'
end

-- ════════════════════════════════════════════════════════════════════════
-- PHARMACIST NPC
-- ════════════════════════════════════════════════════════════════════════

local function removePed(id)
    local ped = peds[id]
    peds[id] = nil
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
end

local function idle(ped)
    local sc = cfg('npc').scenario
    ClearPedTasks(ped)
    if type(sc) == 'string' and sc ~= '' then
        TaskStartScenarioInPlace(ped, sc, 0, true)
    end
end

local function spawnPed(point)
    local nc = cfg('npc')
    if nc.enabled == false or pointData(point).npc == false then return end
    if peds[point.id] ~= nil then return end
    peds[point.id] = false
    CreateThread(function()
        local models = {}
        local custom = point.data and point.data.model
        if type(custom) == 'string' and custom ~= '' then models[1] = custom end
        for _, m in ipairs(nc.models or {}) do models[#models + 1] = m end
        if #models == 0 then peds[point.id] = nil return end
        local start = (type(custom) == 'string' and custom ~= '') and 1 or ((tonumber(point.id) or 0) % #models) + 1
        local hash
        for i = 0, #models - 1 do
            local h = joaat(models[((start - 1 + i) % #models) + 1])
            if IsModelInCdimage(h) and IsModelAPed(h) then hash = h break end
        end
        if not hash then peds[point.id] = nil return end
        local ok = pcall(lib.requestModel, hash, 8000)
        if not ok or not HasModelLoaded(hash) or peds[point.id] ~= false or not NZA.Points.Get(point.id) then
            if peds[point.id] == false then peds[point.id] = nil end
            return
        end
        local pos, heading = pointPos(point)
        local ped = CreatePed(4, hash, pos.x, pos.y, pos.z, heading, false, true)
        SetModelAsNoLongerNeeded(hash)
        if not ped or ped == 0 then peds[point.id] = nil return end
        if peds[point.id] ~= false or not NZA.Points.Get(point.id) then
            DeleteEntity(ped)
            return
        end
        peds[point.id] = ped
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityHeading(ped, heading)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityInvincible(ped, true)
        SetEntityCanBeDamaged(ped, false)
        SetPedCanRagdoll(ped, false)
        SetPedFleeAttributes(ped, 0, false)
        SetPedDiesWhenInjured(ped, false)
        SetPedCanBeTargetted(ped, false)
        SetPedKeepTask(ped, true)
        SetPedConfigFlag(ped, 17, true)
        FreezeEntityPosition(ped, true)
        idle(ped)
    end)
end

-- the pharmacist looks at you and waves
local function greet(pointId)
    local ped = peds[pointId]
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local nc = cfg('npc')
    CreateThread(function()
        local me = PlayerPedId()
        ClearPedTasks(ped)
        TaskTurnPedToFaceEntity(ped, me, tonumber(nc.faceTime) or 1200)
        Wait(math.min(1500, tonumber(nc.faceTime) or 1200))
        if not DoesEntityExist(ped) then return end
        local g = nc.greet
        if type(g) == 'table' and g.dict and g.clip then
            local ok = pcall(lib.requestAnimDict, g.dict, 3000)
            if ok and HasAnimDictLoaded(g.dict) and DoesEntityExist(ped) then
                TaskPlayAnim(ped, g.dict, g.clip, 4.0, -4.0, -1, 48, 0.0, false, false, false)
                Wait(math.floor((GetAnimDuration(g.dict, g.clip) or 2.0) * 1000))
                RemoveAnimDict(g.dict)
            end
        end
        if DoesEntityExist(ped) then idle(ped) end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- BLIPS
-- ════════════════════════════════════════════════════════════════════════

local function clearBlips()
    for id, b in pairs(blips) do
        if b and DoesBlipExist(b) then RemoveBlip(b) end
        blips[id] = nil
    end
end

local function refreshBlips()
    clearBlips()
    local bc = cfg('blip')
    if cfg().enabled == false or bc.enabled == false then return end
    for _, point in pairs(NZA.Points.All('pharmacy') or {}) do
        local d = pointData(point)
        if d.blip ~= false and d.staffOnly ~= true then
            local pos = pointPos(point)
            if pos then
                local b = AddBlipForCoord(pos.x, pos.y, pos.z)
                SetBlipSprite(b, tonumber(bc.sprite) or 51)
                SetBlipColour(b, tonumber(bc.colour) or 2)
                SetBlipScale(b, (tonumber(bc.scale) or 0.75) + 0.0)
                SetBlipAsShortRange(b, bc.shortRange ~= false)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(counterLabel(point) ~= L('title') and (L('blip') .. ' · ' .. counterLabel(point)) or L('blip'))
                EndTextCommandSetBlipName(b)
                blips[point.id] = b
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- WINDOW
-- ════════════════════════════════════════════════════════════════════════

local function endSession()
    session = nil
end

function PH.IsOpen()
    return session ~= nil
end

function PH.Close()
    if not session then return end
    NZA.UI.Close(APP)
    endSession()
end

-- close the window when the player walks away, goes down or the counter disappears
local function watch()
    CreateThread(function()
        local s = session
        local maxD = tonumber(cfg('interact').maxDistance) or 4.0
        while session == s and s do
            Wait(400)
            if session ~= s then return end
            local state = NZA.Self and NZA.Self.State and NZA.Self.State() or 'alive'
            if state ~= 'alive' then
                PH.Close()
                toast(L('closed_down'), 'warning')
                return
            end
            if s.coords then
                local point = s.point and NZA.Points.Get(s.point)
                if s.point and not point then
                    PH.Close()
                    return
                end
                if #(GetEntityCoords(PlayerPedId()) - s.coords) > maxD + 0.5 then
                    PH.Close()
                    toast(L('closed_far'), 'warning')
                    return
                end
            elseif s.sid then
                local ped = GetPlayerPed(GetPlayerFromServerId(s.sid))
                if not ped or ped == 0 or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) > (tonumber(cfg('invoice').distance) or 4.0) + 3.0 then
                    PH.Close()
                    return
                end
            end
        end
    end)
end

function PH.Open(pointId, tab)
    if busy or session or cfg().enabled == false then return false end
    local point = NZA.Points.Get(pointId)
    if not point then return false end
    busy = true
    local res = call('nza:pharmacy:open', pointId, tab)
    busy = false
    if not res.ok or type(res.data) ~= 'table' then
        toast(res.msg or L('err_error'), 'error')
        return false
    end
    local data = res.data
    data.tab = data.tab or tab
    data.shop = data.shop or {}
    data.shop.location = data.shop.label or counterLabel(point)
    data.shop.dept = data.shop.dept or deptLabel(point)
    session = { point = pointId, coords = pointPos(point), mode = data.mode }
    NZA.UI.Open(APP, data, { focus = true, cursor = true })
    greet(pointId)
    watch()
    return true
end

-- medic → patient bill window
function PH.Bill(sid)
    sid = tonumber(sid)
    if busy or session or not sid then return false end
    busy = true
    local res = call('nza:pharmacy:invoice:info', sid)
    busy = false
    if not res.ok then
        toast(res.msg or L('err_error'), 'error', L('title_billing'))
        return false
    end
    res.mode = 'invoice'
    session = { sid = sid, mode = 'invoice' }
    NZA.UI.Open(APP, res, { focus = true, cursor = true })
    watch()
    return true
end

NZA.Bus.On('ui:closed', function(app)
    if app == APP then endSession() end
end)

-- ── NUI callbacks ──────────────────────────────────────────────────────

local function point() return session and session.point end

NZA.UI.On(APP, 'buy', function(data, cb)
    if not point() or type(data) ~= 'table' then return cb({ ok = false, msg = L('err_no_session') }) end
    local res = call('nza:pharmacy:buy', point(), data.lines, data.method, tonumber(data.total))
    if res.ok then
        local ped = peds[point()]
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            TaskTurnPedToFaceEntity(ped, PlayerPedId(), 900)
            SetTimeout(1000, function() if DoesEntityExist(ped) then idle(ped) end end)
        end
    end
    cb(res)
end)

NZA.UI.On(APP, 'insurance', function(data, cb)
    if not point() or type(data) ~= 'table' then return cb({ ok = false, msg = L('err_no_session') }) end
    cb(call('nza:pharmacy:insurance:buy', point(), tostring(data.plan or ''), data.method))
end)

NZA.UI.On(APP, 'payBills', function(data, cb)
    if not point() or type(data) ~= 'table' then return cb({ ok = false, msg = L('err_no_session') }) end
    local which = data.id == 'all' and 'all' or tonumber(data.id)
    cb(call('nza:pharmacy:bills:pay', point(), which, data.method))
end)

NZA.UI.On(APP, 'refresh', function(_, cb)
    if not point() then return cb({ ok = false, msg = L('err_no_session') }) end
    cb(call('nza:pharmacy:refresh', point()))
end)

NZA.UI.On(APP, 'staff', function(_, cb)
    if not point() then return cb({ ok = false, msg = L('err_no_session') }) end
    cb(call('nza:pharmacy:staff', point()))
end)

NZA.UI.On(APP, 'restock', function(data, cb)
    if not point() or type(data) ~= 'table' then return cb({ ok = false, msg = L('err_no_session') }) end
    cb(call('nza:pharmacy:restock', point(), tostring(data.id or ''), tonumber(data.qty), data.from == 'inventory' and 'inventory' or 'order'))
end)

NZA.UI.On(APP, 'invoice', function(data, cb)
    if not session or not session.sid or type(data) ~= 'table' then return cb({ ok = false, msg = L('err_no_target') }) end
    local res = call('nza:pharmacy:invoice:send', session.sid, tonumber(data.amount), tostring(data.reason or ''))
    cb(res)
    if res.ok then
        SetTimeout(900, function() if session and session.sid then PH.Close() end end)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- POSITION TYPE
-- ════════════════════════════════════════════════════════════════════════

local function staffPerm() return cfg('staff').perm or 'pharmacy' end

local function open(tab)
    return function(p) PH.Open(p.id, tab) end
end

local function targets()
    if cfg('interact').target == false then return nil end
    return {
        { name = 'shop', label = L('t_shop'), icon = 'pill', order = 1,
          canInteract = function(p) return canUse(p) and not session end, onSelect = open('shop') },
        { name = 'insurance', label = L('t_insurance'), icon = 'shield', order = 2,
          canInteract = function(p)
              return canUse(p) and not session and cfg('insurance').enabled ~= false and pointData(p).insurance ~= false
          end, onSelect = open('insurance') },
        { name = 'bills', label = L('t_bills'), icon = 'receipt', order = 3,
          canInteract = function(p) return canUse(p) and not session and pointData(p).bills ~= false end, onSelect = open('bills') },
        { name = 'stock', label = L('t_stock'), icon = 'box', order = 4, perm = staffPerm(),
          canInteract = function(p) return memberOf(p) and not session end, onSelect = open('stock') },
    }
end

local defaults = {}
for k, v in pairs(cfg('pointDefaults')) do defaults[k] = v end
defaults.model = ''

NZA.Points.RegisterType('pharmacy', {
    label = L('type_pharmacy'), icon = 'pill', needsHeading = true, radius = 1.4,
    distance = tonumber(cfg('interact').distance) or 2.0, desc = L('type_pharmacy_desc'),
    data = defaults,
    onSpawn = function(p) spawnPed(p) end,
    onRemove = function(p) removePed(p.id) end,
    target = targets(),
})

NZA.Bus.On('points:changed', function(reason, arg)
    if reason == 'sync' or reason == 'type' or reason == 'remove'
        or (reason == 'upsert' and type(arg) == 'table' and arg.type == 'pharmacy') then
        refreshBlips()
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- OPEN BILLS (server push) & PROMPTS ([E] Pharmacy, [H] Pay medical bills)
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:pharmacy:bills', function(count, total)
    bills.count = math.max(0, math.floor(tonumber(count) or 0))
    bills.total = math.max(0, math.floor(tonumber(total) or 0))
    bills.known = true
end)

local function syncBills()
    local res = call('nza:pharmacy:bills:count')
    if res.ok then
        bills.count = math.max(0, math.floor(tonumber(res.count) or 0))
        bills.total = math.max(0, math.floor(tonumber(res.total) or 0))
        bills.known = true
    end
end

local function promptSub(point)
    if pointData(point).staffOnly == true then return L('p_staff_only') end
    if bills.count > 0 and pointData(point).bills ~= false then
        return L('p_open_bills', bills.count, moneyText(bills.total))
    end
    return counterLabel(point)
end

local function canPrompt(ped)
    return not IsPedInAnyVehicle(ped, false) and not IsPauseMenuActive()
        and (not NZA.Self or not NZA.Self.State or NZA.Self.State() == 'alive')
end

CreateThread(function()
    local shown, deskShown = false, false
    while true do
        local sleep = 800
        local ic = cfg('interact')
        local dc = cfg('desk')
        local active = cfg().enabled ~= false and not session and not busy
        local ped = PlayerPedId()
        local me = GetEntityCoords(ped)
        local wantShop, wantDesk = nil, nil

        if active and ic.prompt ~= false then
            local near, nd = NZA.Points.Nearest('pharmacy', me, 12.0)
            if near and nd then sleep = 250 end
            -- the counter's options are third-eye / built-in target options; our own [E] only when it has none
            if near and nd and nd <= (tonumber(ic.distance) or 2.0) and ic.target == false
                and canUse(near) and canPrompt(ped) then
                wantShop = near
            end
        end
        -- (with a third eye the check-in desk carries a 'bills' option instead)
        if active and dc.enabled ~= false and NZA.UI.WorldPrompts() and (bills.count > 0 or dc.onlyWithBills == false) then
            local desk, dd = NZA.Points.Nearest('checkin', me, 12.0)
            if desk and dd then sleep = math.min(sleep, 250) end
            if desk and dd and dd <= (tonumber(dc.distance) or 2.6) and canPrompt(ped) then
                wantDesk = desk
            end
        end

        if wantShop then
            sleep = 0
            NZA.UI.Prompt(PROMPT, { key = ic.keyLabel or 'E', label = L('p_open'), sub = promptSub(wantShop) })
            shown = true
            if IsControlJustReleased(0, tonumber(ic.key) or 38) then
                NZA.UI.HidePrompt(PROMPT)
                shown = false
                PH.Open(wantShop.id, nil)
                Wait(400)
            end
        elseif shown then
            NZA.UI.HidePrompt(PROMPT)
            shown = false
        end

        if wantDesk then
            sleep = 0
            local label = bills.count > 0 and L('p_desk') or L('p_desk_ins')
            local sub = bills.count > 0 and L('p_desk_sub', bills.count, moneyText(bills.total)) or counterLabel(wantDesk)
            NZA.UI.Prompt(PROMPT_DESK, { key = dc.keyLabel or 'H', label = label, sub = sub })
            deskShown = true
            if IsControlJustReleased(0, tonumber(dc.key) or 74) then
                NZA.UI.HidePrompt(PROMPT_DESK)
                deskShown = false
                PH.Open(wantDesk.id, bills.count > 0 and 'bills' or 'insurance')
                Wait(400)
            end
        elseif deskShown then
            NZA.UI.HidePrompt(PROMPT_DESK)
            deskShown = false
        end

        Wait(sleep)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- SEND BILL (patient menu + EMS radial)
-- ════════════════════════════════════════════════════════════════════════

local function invoicePerm() return cfg('invoice').perm or 'assess' end

local function nearestPlayer(range)
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local best, bestD = nil, range
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if ped ~= me and ped ~= 0 and DoesEntityExist(ped) then
            local d = #(GetEntityCoords(ped) - pos)
            if d <= bestD then best, bestD = GetPlayerServerId(pl), d end
        end
    end
    return best
end

if cfg('invoice').enabled ~= false then
    NZA.Interact.Add({
        name = 'nza_pharmacy_bill', label = L('i_bill'), icon = 'receipt', order = 90,
        perm = invoicePerm(), player = true, npc = false, self = false,
        states = { alive = true, wounded = true },
        distance = math.min(tonumber(cfg('invoice').distance) or 4.0, 3.0),
        canInteract = function(_, target) return target ~= nil and target.kind == 'player' and not session end,
        onSelect = function(_, target)
            if target and target.sid then PH.Bill(target.sid) end
        end,
    })

    NZA.RadialItems = NZA.RadialItems or {}
    table.insert(NZA.RadialItems, {
        id = 'pharmacy_bill', parent = 'patient', label = L('r_bill'), icon = 'receipt', order = 90,
        perm = invoicePerm(), desc = L('r_bill_d'),
        canShow = function() return cfg('invoice').enabled ~= false and NZA.OnDuty() end,
        onSelect = function()
            CreateThread(function()
                local sid = nearestPlayer(tonumber(cfg('invoice').distance) or 4.0)
                if not sid then
                    toast(L('err_nobody'), 'error', L('title_billing'))
                    return
                end
                PH.Bill(sid)
            end)
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS & LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

exports('OpenPharmacy', function(pointId, tab)
    local ok, res = pcall(PH.Open, pointId, tab)
    return ok and res == true
end)
exports('ClosePharmacy', function() PH.Close() end)
exports('SendBill', function(sid)
    local ok, res = pcall(PH.Bill, sid)
    return ok and res == true
end)

CreateThread(function()
    Wait(3000)
    refreshBlips()
    Wait(2000)
    syncBills()
end)

if Bridge and Bridge.OnPlayerLoaded then
    Bridge.OnPlayerLoaded(function() SetTimeout(5000, function() CreateThread(syncBills) end) end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if session then NZA.UI.Close(APP) end
    session = nil
    NZA.UI.HidePrompt(PROMPT)
    NZA.UI.HidePrompt(PROMPT_DESK)
    clearBlips()
    for id in pairs(peds) do removePed(id) end
end)
