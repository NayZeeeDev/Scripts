--[[
    NAYZEEE AMBULANCE - Dispatch (client): the dispatch board window (NUI app 'dispatch')

    Overview (stats, active calls, units), calls (detail, timeline, patients, actions),
    units roster, live unit map, call log (nza_calls) and the hospital queue (check-in
    module, plus ambulances transporting). Opened with Config.Dispatch.board.command
    (/dispatch), the radial (Dispatch → Call log / Hospital queue / Unit map) or
    NZA.Dispatch.OpenBoard(tab). Refreshes every Config.Dispatch.board.refresh ms.

    NUI callbacks (all reply { ok }):
      dispatch:respond {id}   dispatch:assign {id, src}   dispatch:unassign {id, src}
      dispatch:clear {id}     dispatch:closeCall {id}     dispatch:priority {id, priority}
      dispatch:gps {id} | {x, y}   dispatch:status {code}  dispatch:npc {on}
      dispatch:log {priority, search} → { rows, db }
      dispatch:callNext {hospital?}    ER intake: call the next check-in ticket (nza:checkin:callNext)
    Actions sent: open (board data + tab + locale), data (board data)
    Callbacks used: nza:dispatch:board, nza:dispatch:log
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Dispatch = NZA.Dispatch or {}
local D = NZA.Dispatch

local APP = 'dispatch'
local open = false
local loopToken = 0

local function cfg(section, key, default)
    local root = Config.Dispatch
    local c = type(root) == 'table' and root[section] or nil
    if type(c) ~= 'table' then return default end
    local v = c[key]
    if v == nil then return default end
    return v
end

local function fetch()
    local data = lib.callback.await('nza:dispatch:board', false)
    if type(data) ~= 'table' then return nil end
    data.clock = ('%02d:%02d'):format(GetClockHours(), GetClockMinutes())
    local p = GetEntityCoords(PlayerPedId())
    data.self = { x = p.x, y = p.y }
    return data
end

local function refreshSoon(ms)
    if not open then return end
    SetTimeout(ms or 350, function()
        if not open then return end
        local data = fetch()
        if data and open then NZA.UI.Send(APP, 'data', data) end
    end)
end

local function startLoop()
    loopToken = loopToken + 1
    local token = loopToken
    CreateThread(function()
        local every = math.max(1000, tonumber(cfg('board', 'refresh', 2000)) or 2000)
        while open and token == loopToken do
            Wait(every)
            if not (open and token == loopToken and NZA.UI.IsOpen(APP)) then break end
            local data = fetch()
            if data and open and token == loopToken then NZA.UI.Send(APP, 'data', data) end
        end
    end)
end

function D.OpenBoard(tab)
    if cfg('board', 'enabled', true) == false then return end
    local m = (D.S and D.S.me) or {}
    if not (D.IsOnDuty and D.IsOnDuty()) and not m.canAssign then
        D.Toast('error', 'dispatch.err_not_unit')
        return
    end
    CreateThread(function()
        local data = fetch()
        if not data then
            D.Toast('error', 'dispatch.err_board')
            return
        end
        data.tab = type(tab) == 'string' and tab or 'overview'
        data.locale = NZA.LocaleTable('dispatch')
        data.logLimit = tonumber(cfg('board', 'logLimit', 60)) or 60
        open = true
        NZA.UI.Open(APP, data, { focus = true, cursor = true })
        startLoop()
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

local function idOf(d) return type(d) == 'table' and type(d.id) == 'string' and #d.id <= 24 and d.id or nil end

NZA.UI.On(APP, 'respond', function(d, cb)
    local id = idOf(d)
    cb({ ok = id ~= nil and D.Respond(id) or false })
    refreshSoon()
end)

NZA.UI.On(APP, 'assign', function(d, cb)
    local id, src = idOf(d), type(d) == 'table' and tonumber(d.src) or nil
    if id and src then TriggerServerEvent('nza:dispatch:assign', id, src) end
    cb({ ok = id ~= nil and src ~= nil })
    refreshSoon()
end)

NZA.UI.On(APP, 'unassign', function(d, cb)
    local id, src = idOf(d), type(d) == 'table' and tonumber(d.src) or nil
    if id and src then TriggerServerEvent('nza:dispatch:unassign', id, src) end
    cb({ ok = id ~= nil and src ~= nil })
    refreshSoon()
end)

NZA.UI.On(APP, 'clear', function(d, cb)
    local id = idOf(d)
    TriggerServerEvent('nza:dispatch:clear', id)
    cb({ ok = true })
    refreshSoon()
end)

NZA.UI.On(APP, 'closeCall', function(d, cb)
    local id = idOf(d)
    if id then TriggerServerEvent('nza:dispatch:closeCall', id) end
    cb({ ok = id ~= nil })
    refreshSoon()
end)

NZA.UI.On(APP, 'priority', function(d, cb)
    local id = idOf(d)
    local prio = type(d) == 'table' and tonumber(d.priority) or nil
    if id and prio then TriggerServerEvent('nza:dispatch:priority', id, prio) end
    cb({ ok = id ~= nil and prio ~= nil })
    refreshSoon()
end)

NZA.UI.On(APP, 'gps', function(d, cb)
    local x, y
    local c = D.Get(idOf(d) or '')
    if c then
        x, y = c.x, c.y
    elseif type(d) == 'table' and tonumber(d.x) and tonumber(d.y) then
        x, y = tonumber(d.x), tonumber(d.y)
    end
    if x then
        SetNewWaypoint(x + 0.0, y + 0.0)
        D.Toast('success', 'dispatch.gps_set')
    end
    cb({ ok = x ~= nil })
end)

NZA.UI.On(APP, 'status', function(d, cb)
    local code = type(d) == 'table' and d.code
    if code == '10-8' or code == '10-7' then D.SetStatus(code) end
    cb({ ok = true })
    refreshSoon()
end)

NZA.UI.On(APP, 'npc', function(d, cb)
    local on = type(d) == 'table' and d.on == true
    if D.S and D.S.me then D.S.me.npc = on end
    D.SetNpcCalls(on)
    cb({ ok = true })
    refreshSoon()
end)

-- ER intake page: call the next waiting check-in ticket to a free bed (the server checks
-- Config.Checkin.desk.perm, resolves the department and answers with a toast)
NZA.UI.On(APP, 'callNext', function(d, cb)
    local hospital = type(d) == 'table' and type(d.hospital) == 'string' and #d.hospital <= 64 and d.hospital or nil
    TriggerServerEvent('nza:checkin:callNext', hospital)
    cb({ ok = true })
    refreshSoon(600)
end)

NZA.UI.On(APP, 'log', function(d, cb)
    d = type(d) == 'table' and d or {}
    local res = lib.callback.await('nza:dispatch:log', false, {
        priority = tonumber(d.priority), search = type(d.search) == 'string' and d.search:sub(1, 40) or nil,
        limit = tonumber(cfg('board', 'logLimit', 60)) or 60,
    })
    cb(type(res) == 'table' and res or { rows = {}, db = false })
end)

NZA.Bus.On('ui:closed', function(app)
    if app == APP then open = false end
end)

-- ════════════════════════════════════════════════════════════════════════
-- COMMAND / KEY
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(0)
    if cfg('board', 'enabled', true) == false then return end
    local cmd = cfg('board', 'command', 'dispatch')
    if type(cmd) == 'string' and cmd ~= '' then
        RegisterCommand(cmd, function() D.OpenBoard() end, false)
    end
    local key = cfg('board', 'key', false)
    if type(key) == 'string' and key ~= '' then
        lib.addKeybind({
            name = 'nza_dispatch_board',
            description = NZA.L('dispatch.bind_board'),
            defaultMapper = 'keyboard',
            defaultKey = key,
            onPressed = function() if not IsPauseMenuActive() then D.OpenBoard() end end,
        })
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if open then NZA.UI.Close(APP) end
    open = false
end)
