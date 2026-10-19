--[[
    NAYZEEE AMBULANCE - Client core: NUI bridge (NZA.UI)

    The resource has ONE NUI page (html/index.html) that hosts every app. This file is
    the only place that talks to it directly.

      NZA.UI.Open(app, data, opts)     action 'open' and push the app on the focus stack
                                       opts = { focus = true, cursor = true, keepInput = false,
                                                look = false, controls = { extra ids to block } }
      NZA.UI.Close(app)                action 'close' and drop it from the focus stack
      NZA.UI.SetFocus(app, opts)       change focus flags of an app that is already open
      NZA.UI.Send(app, action, data)   SendNUIMessage({ app = app, action = action, data = data })
      NZA.UI.On(app, event, fn)        NUI callback '<app>:<event>' → fn(data, cb). Call cb({...})
                                       before returning (Wait inside the handler is fine).
      NZA.UI.Off(app, event, fn)
      NZA.UI.IsOpen(app) / Top() / OpenApps() / CloseAll() / Ready()
      NZA.UI.Toast({ title, message, type, duration })      '_core' action 'toast'
      NZA.UI.Speech(name, text, ms, extra)                  '_core' action 'speech'
      NZA.UI.Prompt(id, { key = 'E', label, sub, hold, progress, tone = 'red' | danger })
                                                            '_core' action 'prompt'
      NZA.UI.PromptProgress(id, 0..1)                       re-sends 'prompt' with progress
      NZA.UI.HidePrompt(id)                                 '_core' action 'promptHide'
      NZA.UI.Hold(id, opts) → bool     blocking "hold [E] to ..." helper driven from Lua
      NZA.UI.PushConfig()              '_core' action 'config' (font, shape, scale, sounds,
                                       signature, locale = NZA.LocaleTable('ui') with every key
                                       also present as 'ui.<key>' - nza.js t('ui.close'))

    Focus: several apps may be open. SetNuiFocus(anyFocus, anyCursor) over all open apps,
    SetNuiFocusKeepInput(true) while any focused app asked for keepInput (game controls that
    would fight the cursor are disabled every frame while that is the case). After every
    change '_core' gets action 'focus' { top, apps } so the JS router knows which app owns
    the keyboard.

    NUI callbacks registered here:
      '<app>:close'     for every app that was opened (auto) - releases focus, runs module
                        handlers, then emits bus 'ui:closed' (app). Only JS-initiated closes
                        emit 'ui:closed'; NZA.UI.Close() from Lua does not.
      '_core:ready'     JS booted → flush queued messages, push config
      '_core:camInput'  optional mouse input forwarded by JS to NZA.Cam (see cam.lua)
    Net events handled: nza:ui:toast, nza:ui:speech
    Bus events emitted: ui:closed (app)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.UI = NZA.UI or {}
local UI = NZA.UI

local CORE = '_core'
local READY_FALLBACK_MS = 8000     -- assume the page is up after this long even without '_core:ready'
local QUEUE_MAX = 256
local CB_TIMEOUT_MS = 10000        -- safety net for NUI callbacks whose handler never replied

-- Controls disabled every frame while a focused app keeps game input (cursor + game keys)
local KEEP_INPUT_BLOCK = {
    24, 25, 37, 44, 45, 47, 58, 68, 69, 70, 91, 92, 114, 140, 141, 142, 143,
    199, 200, 257, 263, 264, 322, 14, 15, 16, 17, 99, 100, 81, 82, 83, 84, 85,
}
local KEEP_INPUT_LOOK = { 1, 2, 3, 4, 5, 6, 106 }

local opened = {}         -- [app] = { focus, cursor, keepInput, look, controls, at }
local stack = {}          -- open app names, oldest → newest
local handlers = {}       -- ['app:event'] = { fn, ... }
local registered = {}     -- ['app:event'] = true once RegisterNUICallback ran
local prompts = {}        -- [id] = prompt payload currently shown
local ready = false
local queue = {}
local startedAt = GetGameTimer()
local keepInputActive = false

-- ════════════════════════════════════════════════════════════════════════
-- SENDING
-- ════════════════════════════════════════════════════════════════════════

local function rawSend(app, action, data)
    SendNUIMessage({ app = app, action = action, data = data })
end

local function markReady()
    if ready then return end
    ready = true
    local q = queue
    queue = {}
    for i = 1, #q do rawSend(q[i][1], q[i][2], q[i][3]) end
end

function UI.Ready()
    return ready
end

function UI.Send(app, action, data)
    if data == nil then data = {} end
    if not ready then
        -- anchors are a 30 Hz stream; queueing stale frames is pointless
        if action ~= 'anchors' and #queue < QUEUE_MAX then
            queue[#queue + 1] = { app, action, data }
        end
        return
    end
    rawSend(app, action, data)
end

-- ════════════════════════════════════════════════════════════════════════
-- FOCUS STACK
-- ════════════════════════════════════════════════════════════════════════

local function removeFromStack(app)
    for i = #stack, 1, -1 do
        if stack[i] == app then table.remove(stack, i) end
    end
end

local function topFocused()
    for i = #stack, 1, -1 do
        local o = opened[stack[i]]
        if o and o.focus then return stack[i] end
    end
    return nil
end

local function keepInputLoop()
    if keepInputActive then return end
    keepInputActive = true
    CreateThread(function()
        while keepInputActive do
            local any, look = false, true
            local extra = nil
            for i = 1, #stack do
                local o = opened[stack[i]]
                if o and o.focus and o.keepInput then
                    any = true
                    if not o.look then look = false end
                    if o.controls then
                        extra = extra or {}
                        for _, c in ipairs(o.controls) do extra[#extra + 1] = c end
                    end
                end
            end
            if not any then break end
            for i = 1, #KEEP_INPUT_BLOCK do DisableControlAction(0, KEEP_INPUT_BLOCK[i], true) end
            if not look then
                for i = 1, #KEEP_INPUT_LOOK do DisableControlAction(0, KEEP_INPUT_LOOK[i], true) end
            end
            if extra then
                for i = 1, #extra do DisableControlAction(0, extra[i], true) end
            end
            Wait(0)
        end
        keepInputActive = false
    end)
end

local function refreshFocus()
    local focus, cursor, keep = false, false, false
    for i = 1, #stack do
        local o = opened[stack[i]]
        if o and o.focus then
            focus = true
            if o.cursor then cursor = true end
            if o.keepInput then keep = true end
        end
    end
    SetNuiFocus(focus, cursor)
    SetNuiFocusKeepInput(focus and keep)
    if focus and keep then keepInputLoop() end

    local apps = {}
    for i = 1, #stack do apps[i] = stack[i] end
    UI.Send(CORE, 'focus', { top = topFocused(), apps = apps })
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

local function dispatch(name, data, cb)
    local done = false
    local function reply(res)
        if done then return end
        done = true
        if res == nil then res = {} end
        cb(res)
    end

    local app, event = name:match('^(.-):(.+)$')
    local closing = event == 'close' and app ~= CORE

    -- The JS router already hid the app; release its focus before anything else
    local wasOpen = false
    if closing and opened[app] then
        wasOpen = true
        opened[app] = nil
        removeFromStack(app)
        refreshFocus()
    end

    local list = handlers[name]
    local count = list and #list or 0
    for i = 1, count do
        local fn = list[i]
        if fn then
            local ok, err = pcall(fn, data, reply)
            if not ok then
                NZA.Warn(('NUI callback "%s" failed: %s'):format(name, tostring(err)))
                reply({ ok = false, error = 'handler' })
            end
        end
    end

    if closing then
        reply({ ok = true })
        if wasOpen then NZA.Bus.Emit('ui:closed', app) end
        return
    end

    if not done then
        if count == 0 then
            reply({ ok = false, error = 'unhandled' })
        else
            -- A handler may reply later from its own thread; never leave the JS promise hanging
            CreateThread(function()
                Wait(CB_TIMEOUT_MS)
                reply({ ok = false, error = 'timeout' })
            end)
        end
    end
end

local function ensureCallback(name)
    if registered[name] then return end
    registered[name] = true
    RegisterNUICallback(name, function(data, cb)
        markReady()
        if type(data) ~= 'table' then data = {} end
        dispatch(name, data, cb)
    end)
end

function UI.On(app, event, fn)
    local name = app .. ':' .. event
    local list = handlers[name]
    if not list then
        list = {}
        handlers[name] = list
    end
    list[#list + 1] = fn
    ensureCallback(name)
    return fn
end

function UI.Off(app, event, fn)
    local list = handlers[app .. ':' .. event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- OPEN / CLOSE
-- ════════════════════════════════════════════════════════════════════════

local function focusRecord(opts)
    opts = opts or {}
    local focus = opts.focus ~= false
    local cursor = opts.cursor
    if cursor == nil then cursor = focus end
    return {
        focus = focus,
        cursor = focus and cursor == true,
        keepInput = focus and opts.keepInput == true,
        look = opts.look == true,
        controls = type(opts.controls) == 'table' and opts.controls or nil,
        at = GetGameTimer(),
    }
end

function UI.Open(app, data, opts)
    if type(app) ~= 'string' or app == '' then return false end
    ensureCallback(app .. ':close')
    opened[app] = focusRecord(opts)
    removeFromStack(app)
    stack[#stack + 1] = app
    UI.Send(app, 'open', data or {})
    refreshFocus()
    return true
end

function UI.SetFocus(app, opts)
    if not opened[app] then return false end
    opened[app] = focusRecord(opts)
    refreshFocus()
    return true
end

function UI.Close(app)
    local was = opened[app] ~= nil
    opened[app] = nil
    removeFromStack(app)
    UI.Send(app, 'close', {})
    if was then refreshFocus() end
    return was
end

function UI.CloseAll()
    local list = {}
    for i = 1, #stack do list[i] = stack[i] end
    for i = 1, #list do
        opened[list[i]] = nil
        UI.Send(list[i], 'close', {})
    end
    stack = {}
    refreshFocus()
end

function UI.IsOpen(app)
    return opened[app] ~= nil
end

function UI.Top()
    return topFocused()
end

function UI.OpenApps()
    local out = {}
    for i = 1, #stack do out[i] = stack[i] end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- TOASTS, SPEECH, PROMPTS
-- ════════════════════════════════════════════════════════════════════════

local TOAST_TYPES = { success = true, error = true, warning = true, info = true }

function UI.Toast(data)
    if type(data) == 'string' then data = { message = data } end
    if type(data) ~= 'table' then return end
    local t = {
        title = data.title,
        message = data.message or data.description or data.text,
        type = TOAST_TYPES[data.type] and data.type or (data.type == 'inform' and 'info') or 'info',
        duration = tonumber(data.duration) or 4500,
        icon = data.icon,
        grade = data.grade,
        score = data.score,
    }
    if ready then
        UI.Send(CORE, 'toast', t)
        return
    end
    -- NUI not up yet: fall back to the external notification (Bridge.Notify itself routes
    -- back into nza:ui:toast, so call its external path directly)
    local external = Bridge and (Bridge.NotifyExternal or Bridge.Notify)
    if external then
        local ok = pcall(external, { title = t.title, message = t.message, type = t.type, duration = t.duration })
        if ok then return end
    end
    lib.notify({ title = t.title, description = t.message, type = t.type == 'info' and 'inform' or t.type, duration = t.duration })
end
UI.Notify = UI.Toast

function UI.Speech(name, text, ms, extra)
    if type(text) ~= 'string' or text == '' then return end
    local d = { name = name, text = text, ms = tonumber(ms) or 4000 }
    if type(extra) == 'table' then
        for k, v in pairs(extra) do if d[k] == nil then d[k] = v end end
    end
    UI.Send(CORE, 'speech', d)
end

local function samePrompt(a, b)
    return a and b and a.key == b.key and a.label == b.label and a.sub == b.sub and a.hold == b.hold
        and a.progress == b.progress and a.tone == b.tone
end

-- opts = { key = 'E', label, sub (small grey suffix), hold = seconds, progress = 0..1
--          (shows the fill ring), tone = 'red' | danger = true }
function UI.Prompt(id, opts)
    if id == nil then return end
    opts = opts or {}
    local p = {
        id = id,
        key = opts.key or 'E',
        label = opts.label or '',
        sub = opts.sub,
        hold = tonumber(opts.hold),
        progress = tonumber(opts.progress),
        tone = opts.tone or (opts.danger and 'red') or nil,
    }
    if samePrompt(prompts[id], p) then return end
    prompts[id] = p
    UI.Send(CORE, 'prompt', p)
end

function UI.PromptProgress(id, progress)
    local p = prompts[id]
    if not p then return end
    progress = NZA.Util.clamp(tonumber(progress) or 0, 0, 1)
    progress = math.floor(progress * 100 + 0.5) / 100
    if p.progress == progress then return end
    p.progress = progress
    UI.Send(CORE, 'prompt', p)
end

function UI.HidePrompt(id)
    if not prompts[id] then return end
    prompts[id] = nil
    UI.Send(CORE, 'promptHide', { id = id })
end

function UI.IsPrompt(id)
    return prompts[id] ~= nil
end

-- Blocking hold helper. opts = { key = 'E', control = 38, seconds = 2, label,
--   cancel = function() return true to stop end, timeout = ms, danger = bool }
-- Shows the prompt, fills it while the control is held, resets when released.
-- Returns true once held long enough, false when cancelled or timed out.
function UI.Hold(id, opts)
    opts = opts or {}
    local control = opts.control or 38
    local seconds = math.max(0.1, tonumber(opts.seconds or opts.hold) or 2)
    local started = GetGameTimer()
    local held = 0.0
    UI.Prompt(id, { key = opts.key or 'E', label = opts.label, sub = opts.sub, hold = seconds, progress = 0,
        tone = opts.tone, danger = opts.danger })
    while true do
        if opts.cancel and opts.cancel() then break end
        if opts.timeout and GetGameTimer() - started > opts.timeout then break end
        if IsControlPressed(0, control) or IsDisabledControlPressed(0, control) then
            held = held + GetFrameTime()
            UI.PromptProgress(id, held / seconds)
            if held >= seconds then
                UI.HidePrompt(id)
                return true
            end
        elseif held > 0 then
            held = 0.0
            UI.PromptProgress(id, 0)
        end
        Wait(0)
    end
    UI.HidePrompt(id)
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- CONFIG PUSH
-- ════════════════════════════════════════════════════════════════════════

-- ui.* strings under both spellings: nza.js looks up 'ui.close', apps may use 'close'
local function uiLocale()
    local out = {}
    for k, v in pairs(NZA.LocaleTable('ui')) do
        out[k] = v
        out['ui.' .. k] = v
    end
    return out
end

function UI.PushConfig()
    local c = Config.UI or {}
    UI.Send(CORE, 'config', {
        font = c.font,
        shape = c.shape,
        scale = c.scale,
        sounds = c.sounds,
        signature = c.signature,
        quality3d = c.quality3d, renderScale = c.renderScale, adaptive = c.adaptive,
        locale = uiLocale(),
        lang = Config.Locale or 'en',
        resource = NZA.Resource,
    })
end

UI.On(CORE, 'ready', function(_, cb)
    markReady()
    UI.PushConfig()
    -- re-sync focus (the page may have reloaded while apps were open)
    refreshFocus()
    cb({ ok = true })
end)

UI.On(CORE, 'camInput', function(data, cb)
    if NZA.Cam and NZA.Cam.Input then NZA.Cam.Input(data) end
    cb({ ok = true })
end)

-- ════════════════════════════════════════════════════════════════════════
-- SERVER → CLIENT
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:ui:toast', function(data)
    UI.Toast(data)
end)

RegisterNetEvent('nza:ui:speech', function(data)
    if type(data) ~= 'table' then return end
    local extra = {}
    for k, v in pairs(data) do
        if k ~= 'name' and k ~= 'text' and k ~= 'ms' then extra[k] = v end
    end
    UI.Speech(data.name, data.text, data.ms, extra)
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    -- Wait for the page; if the JS never says hello, assume it is up after a few seconds
    while not ready and GetGameTimer() - startedAt < READY_FALLBACK_MS do Wait(250) end
    markReady()
    UI.PushConfig()
end)

CreateThread(function()
    Wait(0)
    if Bridge and Bridge.OnPlayerLoaded then
        Bridge.OnPlayerLoaded(function()
            UI.PushConfig()
        end)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)
