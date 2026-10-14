--[[
    NAYZEEE AMBULANCE - Dispatch (client): the pager device (NUI app 'pager')

    A NAYZEEE pager with a backlit LCD, bottom right. It needs Config.Items.pager (unless
    Config.Dispatch.pager.requireItem = false). It pops up by itself when a call comes in
    (no focus, beeps, LED blinks) and stays on screen while you are on a call. Take it in
    your hand with the pager key / the item / /pager to use the buttons:
      ◀ menu / back   ▲ ▼ scroll calls or menu   BACK = decline / back   Y = acknowledge (respond)
    Menu: calls, pair with phone, mute, history, status (10-8 / 10-7), NPC calls, clear call.

    NUI callbacks: pager:ack {id} · pager:decl {id} · pager:clear · pager:gps {id} · pager:pair {on}
                   pager:mute {on} · pager:npc {on} · pager:status {code} · pager:hide
    Actions sent:  open, state, page, live, focus
    Net events handled: nza:dispatch:pager ('toggle')  (using the pager item)
    Keybind: nza_pager (Config.Dispatch.pager.key)   Command: Config.Dispatch.pager.command
    Client API: NZA.Dispatch.PagerVisible() · NZA.Dispatch.TogglePager() · NZA.Dispatch.HasPager()
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Dispatch = NZA.Dispatch or {}
local D = NZA.Dispatch

local APP = 'pager'
local P = { visible = false, focused = false, popupUntil = 0, history = {}, startDist = {}, changedAt = 0 }
-- game controls blocked while the pager is in your hand (phone arrows / back, team chat)
local BLOCK = { 172, 173, 174, 175, 177, 246 }

local function cfg(section, key, default)
    local root = Config.Dispatch
    local c = type(root) == 'table' and root[section] or nil
    if type(c) ~= 'table' then return default end
    local v = c[key]
    if v == nil then return default end
    return v
end

local function S() return D.S or {} end

local function muted()
    return GetResourceKvpInt('nza_pager_mute') == 1
end

function D.HasPager()
    if cfg('pager', 'enabled', true) == false then return false end
    if not cfg('pager', 'requireItem', true) then return true end
    local item = Config.Items and Config.Items.pager
    if not item then return true end
    if Bridge and Bridge.Inv and Bridge.Inv.Has then
        local ok, has = pcall(Bridge.Inv.Has, item, 1)
        return ok and has == true
    end
    return true
end

function D.PagerVisible() return P.visible end

local function onDuty()
    return D.IsOnDuty and D.IsOnDuty() or false
end

local function clock()
    return ('%02d:%02d'):format(GetClockHours(), GetClockMinutes())
end

local function callsList()
    local list = {}
    local mine = D.Current and D.Current() or nil
    if mine then list[1] = D.Public(mine) end
    for _, c in ipairs(D.Calls and D.Calls() or {}) do
        if not mine or c.id ~= mine.id then list[#list + 1] = D.Public(c) end
        if #list >= 12 then break end
    end
    return list
end

local function payload()
    local me = S().me or {}
    return {
        locale = NZA.LocaleTable('dispatch'),
        calls = callsList(),
        history = P.history,
        me = me,
        muted = muted(),
        beep = cfg('pager', 'beep', true) ~= false,
        phone = cfg('pager', 'phonePairing', true) ~= false,
        focused = P.focused,
        time = clock(),
        key = cfg('pager', 'key', 'F7'),
        ackWindow = tonumber(cfg('card', 'timeout', 30)) or 30,
        chain = D.Stages,
    }
end

local function pushState()
    if P.visible then NZA.UI.Send(APP, 'state', payload()) end
end
D.PagerPush = pushState

local function show(focus)
    focus = focus == true
    P.focused = focus
    P.changedAt = GetGameTimer()
    local opts = { focus = focus, cursor = focus, keepInput = focus, controls = focus and BLOCK or nil }
    if P.visible and NZA.UI.IsOpen(APP) then
        NZA.UI.SetFocus(APP, opts)
        NZA.UI.Send(APP, 'focus', { on = focus })
        pushState()
    else
        P.visible = true
        NZA.UI.Open(APP, payload(), opts)
    end
    if D.RefreshActive then D.RefreshActive() end
end

local function hide()
    P.changedAt = GetGameTimer()
    if P.visible then NZA.UI.Close(APP) end
    P.visible = false
    P.focused = false
    if D.RefreshActive then D.RefreshActive() end
end

local function wantPassive()
    local me = S().me or {}
    if cfg('pager', 'showWhileOnCall', true) and me.call then return true end
    return GetGameTimer() < P.popupUntil
end

local function unfocus()
    if wantPassive() and D.HasPager() and onDuty() then
        show(false)
    else
        hide()
    end
end

function D.TogglePager()
    if cfg('pager', 'enabled', true) == false then return end
    -- the key may reach both the NUI (while held) and the keybind: first one wins
    if GetGameTimer() - P.changedAt < 300 then return end
    if not D.HasPager() then
        D.Toast('error', 'dispatch.err_no_pager')
        return
    end
    if P.visible and P.focused then
        unfocus()
    else
        show(true)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- HISTORY & PAGES
-- ════════════════════════════════════════════════════════════════════════

local function addHistory(c)
    for _, h in ipairs(P.history) do if h.id == c.id then return end end
    table.insert(P.history, 1, {
        id = c.id, code = c.code, title = c.title, type = c.type, priority = c.priority, street = c.street or c.zone, time = clock(),
    })
    local max = tonumber(cfg('pager', 'history', 20)) or 20
    while #P.history > max do table.remove(P.history) end
end

local function markHistory(id, reason)
    for _, h in ipairs(P.history) do
        if h.id == id then h.closed = true; h.reason = reason end
    end
end

NZA.Bus.On('dispatch:call', function(c, flags)
    if not D.HasPager() then return end
    addHistory(c)
    if not (flags and flags.alert) then pushState() return end
    if cfg('pager', 'popup', true) and not P.visible then
        P.popupUntil = GetGameTimer() + (tonumber(cfg('pager', 'popupTime', 12)) or 12) * 1000
        show(false)
    elseif P.visible then
        P.popupUntil = math.max(P.popupUntil, GetGameTimer() + (tonumber(cfg('pager', 'popupTime', 12)) or 12) * 1000)
        pushState()
    end
    if P.visible then
        NZA.UI.Send(APP, 'page', { id = c.id, priority = c.priority, beep = cfg('pager', 'beep', true) ~= false and not muted() })
    end
end)

NZA.Bus.On('dispatch:update', function() pushState() end)
NZA.Bus.On('dispatch:close', function(id, reason)
    markHistory(id, reason)
    P.startDist[id] = nil
    pushState()
end)
NZA.Bus.On('dispatch:me', function() pushState() end)
NZA.Bus.On('dispatch:sync', function()
    if not onDuty() then hide() else pushState() end
end)
NZA.Bus.On('dispatch:stage', function(id, stage)
    if stage == 'ENR' then
        local c = D.Get(id)
        if c then P.startDist[id] = D.Live(c) end
    end
    pushState()
end)

NZA.Bus.On('ui:closed', function(app)
    if app == APP then
        P.visible = false
        P.focused = false
        if D.RefreshActive then D.RefreshActive() end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

local function idOf(data) return type(data) == 'table' and type(data.id) == 'string' and data.id or nil end

NZA.UI.On(APP, 'ack', function(data, cb)
    local id = idOf(data)
    cb({ ok = id ~= nil and D.Respond(id) or false })
    SetTimeout(400, pushState)
end)

NZA.UI.On(APP, 'decl', function(data, cb)
    local id = idOf(data)
    if id then D.Decline(id) end
    cb({ ok = true })
    SetTimeout(200, pushState)
end)

NZA.UI.On(APP, 'clear', function(_, cb)
    cb({ ok = D.Clear() })
end)

NZA.UI.On(APP, 'gps', function(data, cb)
    local c = D.Get(idOf(data) or '')
    if c then
        SetNewWaypoint(c.x + 0.0, c.y + 0.0)
        D.Toast('success', 'dispatch.gps_set')
    end
    cb({ ok = c ~= nil })
end)

NZA.UI.On(APP, 'pair', function(data, cb)
    D.Pair(type(data) == 'table' and data.on == true)
    cb({ ok = true })
end)

NZA.UI.On(APP, 'mute', function(data, cb)
    local on = type(data) == 'table' and data.on == true
    SetResourceKvpInt('nza_pager_mute', on and 1 or 0)
    cb({ ok = true, muted = on })
end)

NZA.UI.On(APP, 'npc', function(data, cb)
    local on = type(data) == 'table' and data.on == true
    local me = S().me
    if me then me.npc = on end
    D.SetNpcCalls(on)
    cb({ ok = true })
end)

NZA.UI.On(APP, 'status', function(data, cb)
    local code = type(data) == 'table' and data.code
    if code == '10-8' or code == '10-7' then D.SetStatus(code) end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'hide', function(_, cb)
    cb({ ok = true })
    unfocus()
end)

-- ════════════════════════════════════════════════════════════════════════
-- LOOPS
-- ════════════════════════════════════════════════════════════════════════

-- visibility (popup timeout, on-call display, item lost, off duty)
CreateThread(function()
    while true do
        Wait(500)
        if cfg('pager', 'enabled', true) ~= false then
            local has = D.HasPager()
            if P.visible and not NZA.UI.IsOpen(APP) then
                P.visible = false
                P.focused = false
            end
            if P.visible then
                if not has or not onDuty() then
                    hide()
                elseif not P.focused and not wantPassive() then
                    hide()
                end
            elseif has and onDuty() and cfg('pager', 'showWhileOnCall', true) and (S().me or {}).call and not IsPauseMenuActive() then
                show(false)
            end
        end
    end
end)

-- live numbers on the LCD
CreateThread(function()
    while true do
        if P.visible then
            local live = { time = clock(), calls = {} }
            local n = 0
            for _, c in ipairs(D.Calls and D.Calls() or {}) do
                local dist, dir, _, eta = D.Live(c)
                local entry = { dist = dist, dir = dir, eta = eta }
                local start = P.startDist[c.id]
                if start and start > 1 then entry.prog = math.max(0.0, math.min(1.0, 1.0 - dist / start)) end
                live.calls[c.id] = entry
                n = n + 1
                if n >= 12 then break end
            end
            NZA.UI.Send(APP, 'live', live)
            Wait(500)
        else
            Wait(800)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- KEYS, COMMAND, ITEM
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:dispatch:pager', function(action)
    if action == 'toggle' then D.TogglePager() end
end)

CreateThread(function()
    Wait(0)
    if cfg('pager', 'enabled', true) == false then return end
    local key = cfg('pager', 'key', 'F7')
    if type(key) == 'string' and key ~= '' then
        lib.addKeybind({
            name = 'nza_pager',
            description = NZA.L('dispatch.bind_pager'),
            defaultMapper = 'keyboard',
            defaultKey = key,
            onPressed = function()
                if IsPauseMenuActive() then return end
                D.TogglePager()
            end,
        })
    end
    local cmd = cfg('pager', 'command', 'pager')
    if type(cmd) == 'string' and cmd ~= '' then
        RegisterCommand(cmd, function() D.TogglePager() end, false)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if P.visible then NZA.UI.Close(APP) end
end)
