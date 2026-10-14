--[[
    NAYZEEE AMBULANCE - Check-in (client): desk, receptionist, ticket, reception queue, calls

    Position type 'checkin' (NZA.Points.RegisterType): a receptionist NPC behind the desk
    (local ped, seated or standing scenario), "[E] Check in — treat injuries · Check-in Desk"
    when you are close (no target needed) plus target options. Staff with
    Config.Checkin.desk.perm get "[G] Reception queue" and "Call next patient".

    The 'checkin' NUI app shows the thermal-paper receipt (mode 'ticket'), the small ticket chip
    while you wait, the receptionist's subtitles and the staff reception window (mode 'desk').

    When your number is called you get a toast, a waypoint and a marker on the bed
    ("[E] Lie down — Bed 3"). AI doctor calls can teleport you into the bed (config).

    Client API
      NZA.Checkin.Mine() → own ticket | nil          NZA.Checkin.OpenDesk(hospital?, pointId?)
      NZA.Checkin.CallNext(hospital?)                NZA.Checkin.ShowReceipt(ticket?)
    Internals shared with checkin_bed.lua / checkin_tv.lua: NZA.CheckinC
    Net events handled: nza:checkin:mine, nza:checkin:receipt, nza:checkin:staff, nza:checkin:desk
    Callbacks used: nza:checkin:checkin, :mine, :leave, :desk, :action, :lie
    NUI callbacks: checkin:action, checkin:deskClose, checkin:refresh, checkin:hospital, checkin:hidden
    Radial (NZA.RadialItems, parent 'dispatch'): checkin_next, checkin_queue
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Checkin = NZA.Checkin or {}
NZA.CheckinC = NZA.CheckinC or {}
local CI = NZA.Checkin
local K = NZA.CheckinC

local mine = nil          -- own open ticket (public table)
local peds = {}           -- [pointId] = receptionist ped
local deskOpen = false    -- reception window open
local appOpen = false     -- checkin app open (any mode)
local guide = nil         -- { ticket, gen } walking to the called bed
local guideGen = 0
local receiptGen = 0      -- receipt that waits for you to walk away (receiptTime 0)

local function cfg(section, key, default)
    local s = Config.Checkin and Config.Checkin[section]
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end
K.Cfg = cfg

local function L(key, ...) return NZA.L('checkin.' .. key, ...) end
K.L = L

local function deskPerm() return cfg('desk', 'perm', 'checkin') end
local function isStaff() return NZA.Perm(deskPerm()) end

local function toast(msg, kind, title, ms)
    NZA.UI.Toast({ title = title or L('title'), message = msg, type = kind or 'info', duration = ms, icon = 'ticket' })
end
K.Toast = toast

local function call(name, ...)
    local ok, res = pcall(lib.callback.await, name, false, ...)
    if not ok or type(res) ~= 'table' then return { ok = false, err = 'failed', msg = L('err_failed') } end
    return res
end
K.Call = call

-- clock data for the NUI (tickets and boards show in-game or real time)
function K.Clock()
    return {
        mode = cfg('misc', 'clock', nil) or (Config.Checkin and Config.Checkin.clock) or 'game',
        h = GetClockHours(), m = GetClockMinutes(),
        msPerMin = GetMillisecondsPerGameMinute and GetMillisecondsPerGameMinute() or 2000,
    }
end

function CI.Mine() return mine end

-- ════════════════════════════════════════════════════════════════════════
-- NUI APP
-- ════════════════════════════════════════════════════════════════════════

local function openApp(data, focus)
    data.locale = NZA.LocaleTable('checkin')
    data.clock = K.Clock()
    data.cfg = {
        receiptTime = tonumber(cfg('desk', 'receiptTime', 14)) or 14,
        ticketHud = cfg('desk', 'ticketHud', true) ~= false,
        printSound = cfg('desk', 'printSound', true) ~= false,
        estimate = cfg('queue', 'estimate', { 4, 8, 12 }),
    }
    data.mine = mine
    NZA.UI.Open('checkin', data, { focus = focus == true, cursor = focus == true })
    appOpen = true
end

local function receptionistName(pointId)
    local pt = pointId and NZA.Points.Get(pointId)
    local n = pt and pt.data and pt.data.name
    if type(n) == 'string' and n ~= '' then return n end
    local list = {}
    for name in tostring(L('receptionist_names')):gmatch('[^,]+') do list[#list + 1] = name:gsub('^%s+', ''):gsub('%s+$', '') end
    if #list == 0 then return L('reception') end
    return list[((tonumber(pointId) or 0) % #list) + 1]
end

local function say(pointId, key, ...)
    if cfg('receptionist', 'talk', true) == false then return end
    local text = L(key, ...)
    local ped = pointId and peds[pointId]
    if ped and DoesEntityExist(ped) then pcall(PlayPedAmbientSpeechNative, ped, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE') end
    local data = { name = receptionistName(pointId), role = L('reception'), text = text }
    if appOpen and NZA.UI.IsOpen('checkin') then
        NZA.UI.Send('checkin', 'say', data)
    else
        openApp({ mode = 'say', say = data }, false)
    end
end
K.Say = say

function CI.ShowReceipt(ticket, opts)
    ticket = ticket or mine
    if not ticket then return end
    opts = opts or {}
    openApp({ mode = 'ticket', ticket = ticket, print = opts.print == true,
              say = opts.say and { name = receptionistName(opts.point), role = L('reception'), text = L(opts.say, ticket.code, ticket.ahead or 0) } or nil },
        deskOpen)
    -- receiptTime 0: the receipt stays until you walk away from the desk
    local pt = opts.point and NZA.Points.Get(opts.point)
    if pt and (tonumber(cfg('desk', 'receiptTime', 14)) or 14) <= 0 then
        receiptGen = receiptGen + 1
        local gen = receiptGen
        local pos = vector3(pt.coords.x + 0.0, pt.coords.y + 0.0, pt.coords.z + 0.0)
        local range = (tonumber(cfg('desk', 'promptDistance', 2.6)) or 2.6) + 3.0
        CreateThread(function()
            while receiptGen == gen and appOpen do
                if #(GetEntityCoords(PlayerPedId()) - pos) > range then
                    NZA.UI.Send('checkin', 'hideReceipt', {})
                    break
                end
                Wait(500)
            end
        end)
    end
end

-- the app closes itself when nothing is left to show
NZA.UI.On('checkin', 'hidden', function(_, cb)
    cb({ ok = true })
    if not deskOpen then
        NZA.UI.Close('checkin')
        appOpen = false
    end
end)

NZA.Bus.On('ui:closed', function(app)
    if app ~= 'checkin' then return end
    appOpen = false
    if deskOpen then
        deskOpen = false
        CreateThread(function() call('nza:checkin:desk', { watch = false }) end)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- OWN TICKET
-- ════════════════════════════════════════════════════════════════════════

local function stopGuide()
    guideGen = guideGen + 1
    guide = nil
    NZA.UI.HidePrompt('nza_checkin_bed')
end
K.StopGuide = stopGuide

local function bedVec(ticket)
    local c = ticket and ticket.bedCoords
    if not c then return nil end
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
end

local function startGuide(ticket)
    stopGuide()
    local target = bedVec(ticket)
    if not target then return end
    guide = { ticket = ticket }
    local gen = guideGen
    SetNewWaypoint(target.x, target.y)
    CreateThread(function()
        local col = { 8, 175, 162 }
        while guide and guideGen == gen do
            local sleep = 500
            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            local d = #(me - target)
            if d < 45.0 then
                sleep = 0
                local bob = math.sin(GetGameTimer() / 260.0) * 0.06
                DrawMarker(2, target.x, target.y, target.z + 1.35 + bob, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.32, 0.32, 0.32,
                    col[1], col[2], col[3], 200, false, true, 2, false, nil, nil, false)
                DrawMarker(25, target.x, target.y, target.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.4, 1.4, 1.0,
                    col[1], col[2], col[3], 110, false, false, 2, false, nil, nil, false)
            end
            if d < 2.4 and not IsPedInAnyVehicle(ped, false) and K.Lying and not K.Lying() then
                NZA.UI.Prompt('nza_checkin_bed', { key = cfg('desk', 'key', 'E'), label = L('p_lie'), sub = guide.ticket.bed or L('bed') })
                if IsControlJustReleased(0, tonumber(cfg('desk', 'control', 38)) or 38) then
                    NZA.UI.HidePrompt('nza_checkin_bed')
                    local t = guide.ticket
                    if K.LieDown then K.LieDown(t, false) end
                    Wait(600)
                end
            else
                NZA.UI.HidePrompt('nza_checkin_bed')
            end
            Wait(sleep)
        end
        NZA.UI.HidePrompt('nza_checkin_bed')
    end)
end

local function travelTeleport(ticket)
    if not ticket.ai then return false end
    if cfg('ai', 'travel', 'walk') == 'teleport' then return true end
    return cfg('ai', 'downedTeleport', true) and NZA.Self.State() == 'wounded'
end

local function onCalled(ticket)
    toast(L('called_msg', ticket.code, ticket.bed or L('bed')), 'success', L('called_title'), 10000)
    NZA.UI.Send('_core', 'sound', { name = 'success' })
    if travelTeleport(ticket) then
        stopGuide()
        CreateThread(function()
            Wait(2500)
            if mine and mine.id == ticket.id and mine.status == 'called' and K.LieDown then K.LieDown(mine, true) end
        end)
    else
        startGuide(ticket)
    end
end

local function setMine(ticket, event, closed)
    local prev = mine
    mine = ticket or nil
    if appOpen then NZA.UI.Send('checkin', 'mine', { ticket = mine, event = event, closed = closed }) end
    if mine and mine.status == 'called' and (event == 'called' or not prev or prev.status ~= 'called' or prev.bedId ~= mine.bedId) then
        onCalled(mine)
    elseif not mine or mine.status ~= 'called' then
        stopGuide()
    end
    if not mine and event == 'closed' and closed and not (K.AIActive and K.AIActive()) then
        local st = closed.status
        if st == 'noshow' then toast(L('closed_noshow', closed.code), 'warning', nil, 8000)
        elseif st == 'left' then toast(L('closed_left', closed.code), 'info')
        elseif st == 'done' then toast(L('closed_done', closed.code), 'success')
        elseif st == 'cancelled' then toast(L('closed_cancelled', closed.code), 'info') end
    end
    if mine and cfg('desk', 'ticketHud', true) ~= false and not appOpen then openApp({ mode = 'chip' }, false) end
end

RegisterNetEvent('nza:checkin:mine', function(ticket, event, closed)
    setMine(type(ticket) == 'table' and ticket or nil, event, type(closed) == 'table' and closed or nil)
end)

RegisterNetEvent('nza:checkin:receipt', function(ticket)
    if type(ticket) ~= 'table' then return end
    CI.ShowReceipt(ticket, {})
end)

-- ════════════════════════════════════════════════════════════════════════
-- CHECK IN
-- ════════════════════════════════════════════════════════════════════════

local busy = false

local function checkIn(point)
    if busy or not point then return end
    busy = true
    if mine then
        CI.ShowReceipt(mine, { point = point.id })
        busy = false
        return
    end
    local res = call('nza:checkin:checkin', point.id)
    busy = false
    if res.ok and type(res.ticket) == 'table' then
        mine = res.ticket
        CI.ShowReceipt(res.ticket, { print = not res.again, say = res.say, point = point.id })
        if mine.status == 'called' then onCalled(mine) end
    elseif res.say then
        say(point.id, res.say)
    else
        toast(res.msg or L('err_failed'), 'error')
    end
end

local function leaveQueue()
    local res = call('nza:checkin:leave')
    if res.ok then
        toast(res.msg, 'info')
    else
        toast(res.msg or L('err_failed'), 'error')
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- RECEPTION WINDOW (staff)
-- ════════════════════════════════════════════════════════════════════════

function CI.OpenDesk(hospital, pointId)
    if not isStaff() then return toast(L('err_no_perm'), 'error') end
    local res = call('nza:checkin:desk', { hospital = hospital, point = pointId, watch = true })
    if not res.ok then return toast(res.msg or L('err_failed'), 'error') end
    deskOpen = true
    openApp({ mode = 'desk', desk = res.desk }, true)
end

function CI.CallNext(hospital, pointId)
    if not isStaff() then return toast(L('err_no_perm'), 'error') end
    local res = call('nza:checkin:action', 'callNext', { hospital = hospital, point = pointId })
    toast(res.msg or L('err_failed'), res.ok and 'success' or 'error')
end

local function closeDesk()
    if not deskOpen then return end
    deskOpen = false
    CreateThread(function() call('nza:checkin:desk', { watch = false }) end)
    if mine and cfg('desk', 'ticketHud', true) ~= false then
        NZA.UI.Send('checkin', 'deskClosed', {})
        NZA.UI.SetFocus('checkin', { focus = false, cursor = false })
    else
        NZA.UI.Close('checkin')
        appOpen = false
    end
end

RegisterNetEvent('nza:checkin:desk', function(desk)
    if deskOpen and type(desk) == 'table' then NZA.UI.Send('checkin', 'desk', desk) end
end)

NZA.UI.On('checkin', 'action', function(data, cb)
    data = type(data) == 'table' and data or {}
    local action = tostring(data.action or '')
    local res = call('nza:checkin:action', action, { id = data.id, bed = data.bed, hospital = data.hospital })
    cb(res)
end)

NZA.UI.On('checkin', 'deskClose', function(_, cb)
    cb({ ok = true })
    closeDesk()
end)

NZA.UI.On('checkin', 'refresh', function(data, cb)
    local res = call('nza:checkin:desk', { hospital = type(data) == 'table' and data.hospital or nil, watch = true })
    cb(res)
end)

NZA.UI.On('checkin', 'hospital', function(data, cb)
    local res = call('nza:checkin:desk', { hospital = type(data) == 'table' and data.id or nil, watch = true })
    cb(res)
end)

NZA.UI.On('checkin', 'leave', function(_, cb)
    cb({ ok = true })
    CreateThread(leaveQueue)
end)

-- ════════════════════════════════════════════════════════════════════════
-- STAFF NOTIFICATIONS
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:checkin:staff', function(note)
    if type(note) ~= 'table' or note.toast == false then return end
    local tri = tonumber(note.triage) or 3
    local triText = ('P%d %s'):format(tri, note.triageLabel or '')
    local msg, title
    if note.kind == 'new' then
        title, msg = L('staff_new_title', note.hospitalLabel or ''), L('staff_new', note.code or '?', triText)
    elseif note.kind == 'triage' then
        title, msg = L('staff_triage_title'), L('staff_triage', note.code or '?', triText)
    elseif note.kind == 'ai' then
        title, msg = L('staff_ai_title'), L('staff_ai', note.code or '?', note.bed or L('bed'))
    else
        return
    end
    NZA.UI.Toast({ title = title, message = msg, type = tri == 1 and 'error' or (tri == 2 and 'warning' or 'info'), duration = 7000, icon = 'ticket' })
    if note.sound ~= false and note.kind ~= 'ai' then NZA.UI.Send('_core', 'sound', { name = tri == 1 and 'pager' or 'success' }) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- RECEPTIONIST
-- ════════════════════════════════════════════════════════════════════════

local function removeReceptionist(id)
    local ped = peds[id]
    peds[id] = nil
    if ped and DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
end

local function spawnReceptionist(point)
    local rc = Config.Checkin and Config.Checkin.receptionist or {}
    if rc.enabled == false or (point.data and point.data.ped == false) then return end
    if peds[point.id] then return end
    peds[point.id] = false   -- loading
    CreateThread(function()
        local models = {}
        local custom = point.data and point.data.model
        if type(custom) == 'string' and custom ~= '' then models[1] = custom end
        for _, m in ipairs(rc.models or {}) do models[#models + 1] = m end
        local hash
        local start = (type(custom) == 'string' and custom ~= '') and 1 or ((tonumber(point.id) or 0) % math.max(1, #models)) + 1
        for i = 0, #models - 1 do
            local m = models[((start - 1 + i) % #models) + 1]
            local h = joaat(m)
            if IsModelInCdimage(h) and IsModelAPed(h) then hash = h break end
        end
        if not hash then peds[point.id] = nil return end
        local ok = pcall(lib.requestModel, hash, 8000)
        if not ok or not HasModelLoaded(hash) or peds[point.id] ~= false or not NZA.Points.Get(point.id) then
            if peds[point.id] == false then peds[point.id] = nil end
            return
        end
        local c = point.coords
        local z = c.z + (tonumber(point.data and point.data.z) or 0.0)
        local ped = CreatePed(4, hash, c.x + 0.0, c.y + 0.0, z, (c.w or 0.0) + 0.0, false, true)
        SetModelAsNoLongerNeeded(hash)
        if not ped or ped == 0 then peds[point.id] = nil return end
        if peds[point.id] ~= false or not NZA.Points.Get(point.id) then DeleteEntity(ped) return end
        peds[point.id] = ped
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityInvincible(ped, true)
        SetPedCanRagdoll(ped, false)
        SetPedFleeAttributes(ped, 0, false)
        SetPedDiesWhenInjured(ped, false)
        SetPedCanBeTargetted(ped, false)
        SetPedKeepTask(ped, true)
        SetPedConfigFlag(ped, 17, true)
        SetEntityCanBeDamaged(ped, false)
        local pose = point.data and point.data.pose or 'sit'
        if pose == 'stand' then
            SetEntityCoordsNoOffset(ped, c.x + 0.0, c.y + 0.0, z, false, false, false)
            SetEntityHeading(ped, (c.w or 0.0) + 0.0)
            FreezeEntityPosition(ped, true)
            TaskStartScenarioInPlace(ped, rc.standScenario or 'WORLD_HUMAN_CLIPBOARD', 0, true)
        else
            TaskStartScenarioAtPosition(ped, rc.sitScenario or 'PROP_HUMAN_SEAT_COMPUTER', c.x + 0.0, c.y + 0.0, z + 0.5,
                (c.w or 0.0) + 0.0, 0, true, true)
        end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- POSITION TYPE
-- ════════════════════════════════════════════════════════════════════════

local function targets()
    if cfg('desk', 'target', true) == false then return nil end
    if Bridge and Bridge.Target and Bridge.Target.Resource and Bridge.Target.Resource() == 'builtin' then return nil end
    return {
        { name = 'checkin', label = L('t_checkin'), icon = 'ticket',
          canInteract = function() return mine == nil end,
          onSelect = function(p) CreateThread(function() checkIn(p) end) end },
        { name = 'ticket', label = L('t_ticket'), icon = 'ticket',
          canInteract = function() return mine ~= nil end,
          onSelect = function(p) CI.ShowReceipt(mine, { point = p.id }) end },
        { name = 'leave', label = L('t_leave'), icon = 'logout',
          canInteract = function() return mine ~= nil and mine.status == 'waiting' end,
          onSelect = function() CreateThread(leaveQueue) end },
        { name = 'queue', label = L('t_queue'), icon = 'users', perm = deskPerm(),
          onSelect = function(p) CreateThread(function() CI.OpenDesk(p.hospital, p.id) end) end },
        { name = 'next', label = L('t_next'), icon = 'bell', perm = deskPerm(),
          onSelect = function(p) CreateThread(function() CI.CallNext(p.hospital, p.id) end) end },
    }
end

NZA.Points.RegisterType('checkin', {
    label = L('type_checkin'), icon = 'ticket', needsHeading = true, radius = 1.6,
    distance = tonumber(cfg('desk', 'promptDistance', 2.6)) or 2.6, desc = L('type_checkin_desc'),
    data = { prefix = cfg('desk', 'prefix', 'A'), ped = true, pose = 'sit', model = '', name = '', z = 0.0 },
    onSpawn = function(point) spawnReceptionist(point) end,
    onRemove = function(point) removeReceptionist(point.id) end,
    target = targets(),
})

-- ════════════════════════════════════════════════════════════════════════
-- DESK PROMPTS ([E] check in, [G] reception queue)
-- ════════════════════════════════════════════════════════════════════════

local function canUseDesk(ped)
    if IsPedInAnyVehicle(ped, false) or IsPauseMenuActive() then return false end
    if deskOpen or (K.Lying and K.Lying()) then return false end
    local st = NZA.Self.State()
    if st == 'alive' then return true end
    return st == 'wounded' and cfg('desk', 'allowDowned', true) ~= false
end

CreateThread(function()
    local shown, staffShown = false, false
    while true do
        local sleep = 600
        local ped = PlayerPedId()
        local me = GetEntityCoords(ped)
        local range = tonumber(cfg('desk', 'promptDistance', 2.6)) or 2.6
        local pt = NZA.Points.Nearest('checkin', me, range)
        if pt and canUseDesk(ped) then
            sleep = 0
            if mine then
                local sub = mine.status == 'called' and L('p_called_sub', mine.bed or L('bed'))
                    or (mine.status == 'waiting' and L('p_ahead', mine.ahead or 0) or L('p_in_treatment'))
                NZA.UI.Prompt('nza_checkin', { key = cfg('desk', 'key', 'E'), label = L('p_ticket', mine.code), sub = sub })
            else
                NZA.UI.Prompt('nza_checkin', { key = cfg('desk', 'key', 'E'), label = L('p_checkin'), sub = (pt.label and pt.label ~= '' and pt.label) or L('desk') })
            end
            shown = true
            if isStaff() then
                NZA.UI.Prompt('nza_checkin_staff', { key = cfg('desk', 'staffKey', 'G'), label = L('p_queue'), sub = L('p_queue_sub') })
                staffShown = true
                if IsControlJustReleased(0, tonumber(cfg('desk', 'staffControl', 47)) or 47) then
                    local id, h = pt.id, pt.hospital
                    CreateThread(function() CI.OpenDesk(h, id) end)
                    Wait(400)
                end
            elseif staffShown then
                NZA.UI.HidePrompt('nza_checkin_staff')
                staffShown = false
            end
            if IsControlJustReleased(0, tonumber(cfg('desk', 'control', 38)) or 38) then
                local p = pt
                CreateThread(function() checkIn(p) end)
                Wait(400)
            end
        else
            if shown then NZA.UI.HidePrompt('nza_checkin') shown = false end
            if staffShown then NZA.UI.HidePrompt('nza_checkin_staff') staffShown = false end
        end
        Wait(sleep)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- RADIAL (EMS job menu → Dispatch)
-- ════════════════════════════════════════════════════════════════════════

NZA.RadialItems = NZA.RadialItems or {}

table.insert(NZA.RadialItems, {
    id = 'checkin_next', parent = 'dispatch', label = L('r_next'), icon = 'bell', order = 25, perm = deskPerm(),
    desc = L('r_next_d'),
    canShow = function() return cfg('misc', 'radial', nil) ~= false and (Config.Checkin and Config.Checkin.radial) ~= false and NZA.OnDuty() end,
    onSelect = function() CreateThread(function() CI.CallNext(nil, nil) end) end,
})

table.insert(NZA.RadialItems, {
    id = 'checkin_queue', parent = 'dispatch', label = L('r_queue'), icon = 'ticket', order = 26, perm = deskPerm(),
    desc = L('r_queue_d'),
    canShow = function() return (Config.Checkin and Config.Checkin.radial) ~= false and NZA.OnDuty() end,
    onSelect = function() CreateThread(function() CI.OpenDesk(nil, nil) end) end,
})

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

local function syncMine()
    local res = call('nza:checkin:mine')
    if res.ok then setMine(type(res.ticket) == 'table' and res.ticket or nil, 'update') end
end

CreateThread(function()
    Wait(4000)
    syncMine()
end)

if Bridge and Bridge.OnPlayerLoaded then
    Bridge.OnPlayerLoaded(function() SetTimeout(3500, function() CreateThread(syncMine) end) end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(peds) do removeReceptionist(id) end
    NZA.UI.HidePrompt('nza_checkin')
    NZA.UI.HidePrompt('nza_checkin_staff')
    NZA.UI.HidePrompt('nza_checkin_bed')
end)
