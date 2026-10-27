--[[
    NAYZEEE RADIO - Client core: NUI bridge (NZR.UI)

    The resource has ONE NUI page (html/index.html) that hosts every app. This file is
    the only place that talks to it directly.

      NZR.UI.Open(app, data, opts)     action 'open' and push the app on the focus stack
                                       opts = { focus = true, cursor = true, keepInput = false,
                                                look = false, controls = { extra ids to block } }
                                       focus = false: a HUD app that never takes the mouse/keyboard
      NZR.UI.Close(app)                action 'close' and drop it from the focus stack
      NZR.UI.SetFocus(app, opts)       change focus flags of an app that is already open
      NZR.UI.Send(app, action, data)   SendNUIMessage({ app = app, action = action, data = data })
                                       queued until the page said '_core:ready'
      NZR.UI.On(app, event, fn)        NUI callback '<app>:<event>' → fn(data, cb). Call cb({...})
                                       before returning (Wait inside the handler is fine).
      NZR.UI.Off(app, event, fn)
      NZR.UI.IsOpen(app) / Top() / OpenApps() / CloseAll() / Ready()
      NZR.UI.Toast({ title, message, type, duration, icon })   '_core' action 'toast'
      NZR.UI.Prompt(id, { key = 'E', label, sub, hold, progress, tone = 'red' | danger })
                                                            '_core' action 'prompt'
      NZR.UI.PromptProgress(id, 0..1)                       re-sends 'prompt' with progress
      NZR.UI.HidePrompt(id) / IsPrompt(id)                  '_core' action 'promptHide'
      NZR.UI.PromptsBlocked() → bool   the third eye is open (prompts are hidden meanwhile)
      NZR.UI.WorldPrompts() → bool     true when world [E] prompts should exist (no target script)
      NZR.UI.Hold(id, opts) → bool     blocking "hold [E] to ..." helper driven from Lua
      NZR.UI.PushConfig()              '_core' action 'config' { font, shape, scale, sounds,
                                       signature, locale, lang, resource, sfx, clicks, keys }
                                       locale = NZR.LocaleTable('ui') with every key also present
                                       as 'ui.<key>' (nzr.js t('ui.close')); sfx = Config.Audio.sfx
                                       (0..1 master volume of NZR.sfx), clicks = Config.Audio.clicks,
                                       keys = Config.Keys (default key names for hints)

    Focus: several apps may be open. SetNuiFocus(anyFocus, anyCursor) over all open apps,
    SetNuiFocusKeepInput(true) while the TOP focused app asked for keepInput (game controls that
    would fight the cursor are disabled every frame while that is the case; camera look too
    unless the app passed look = true). A window opened over the head unit (admin, hack) takes
    the keyboard away from the game until it closes. After every change '_core' gets action 'focus'
    { top, apps } so the JS router knows which app owns the keyboard.

    NUI callbacks registered here:
      '<app>:close'     for every app that was opened (auto) - releases focus, runs module
                        handlers, then emits bus 'ui:closed' (app). Only JS-initiated closes
                        emit 'ui:closed'; NZR.UI.Close() from Lua does not.
      '_core:ready'     JS booted → flush queued messages, push config
    Net events handled: nzr:ui:toast (S→C, also triggered locally by bridge/client/notify.lua)
    Bus events emitted: ui:closed (app), ui:ready
]]

if not NAYZEEE_LOCK_OK then return end

NZR.UI = NZR.UI or {}
local UI = NZR.UI

local CORE = '_core'
local READY_FALLBACK_MS = 8000     -- assume the page is up after this long even without '_core:ready'
local QUEUE_MAX = 256
local CB_TIMEOUT_MS = 10000        -- safety net for NUI callbacks whose handler never replied

-- Controls disabled every frame while a focused app keeps game input (cursor + game keys):
-- attack / aim / weapon wheel / pause / phone / radio wheel ... everything a click or a
-- typed key would also trigger in the game. Driving (throttle, brake, steer) stays.
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
    NZR.Bus.Emit('ui:ready')
end

function UI.Ready()
    return ready
end

-- Streams that are stale a moment later are not worth queueing before the page is up.
local NO_QUEUE = { hover = true, rx = true, noise = true }

function UI.Send(app, action, data)
    if data == nil then data = {} end
    if not ready then
        if not NO_QUEUE[action] and #queue < QUEUE_MAX then
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
            -- only the top focused app decides: a plain window above a keepInput app owns the keys
            local top = topFocused()
            local o = top and opened[top]
            if not (o and o.keepInput) then break end
            local look = o.look == true
            local extra = o.controls
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
    local focus, cursor = false, false
    for i = 1, #stack do
        local o = opened[stack[i]]
        if o and o.focus then
            focus = true
            if o.cursor then cursor = true end
        end
    end
    local top = topFocused()
    local keep = top ~= nil and opened[top].keepInput == true
    SetNuiFocus(focus, cursor)
    SetNuiFocusKeepInput(focus and keep)
    if focus and keep then keepInputLoop() end

    local apps = {}
    for i = 1, #stack do apps[i] = stack[i] end
    UI.Send(CORE, 'focus', { top = top, apps = apps })
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
                NZR.Warn(('NUI callback "%s" failed: %s'):format(name, tostring(err)))
                reply({ ok = false, error = 'handler' })
            end
        end
    end

    if closing then
        reply({ ok = true })
        if wasOpen then NZR.Bus.Emit('ui:closed', app) end
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
-- TOASTS & PROMPTS
-- ════════════════════════════════════════════════════════════════════════

local TOAST_TYPES = { success = true, error = true, warning = true, info = true }

function UI.Toast(data)
    if type(data) == 'string' then data = { message = data } end
    if type(data) ~= 'table' then return end
    local t = {
        title = data.title,
        message = data.message or data.description or data.text,
        type = TOAST_TYPES[data.type] and data.type or 'info',
        duration = tonumber(data.duration) or 4500,
        icon = data.icon,
    }
    if ready then
        UI.Send(CORE, 'toast', t)
        return
    end
    -- NUI not up yet: fall back to the external notification (Bridge.Notify itself routes
    -- back into nzr:ui:toast, so call its external path directly)
    local external = Bridge and (Bridge.NotifyExternal or Bridge.Notify)
    if external then
        local ok = pcall(external, { title = t.title, message = t.message, type = t.type, duration = t.duration })
        if ok then return end
    end
    lib.notify({ title = t.title, description = t.message, type = t.type == 'info' and 'inform' or t.type, duration = t.duration })
end
UI.Notify = UI.Toast

local function samePrompt(a, b)
    return a and b and a.key == b.key and a.label == b.label and a.sub == b.sub and a.hold == b.hold
        and a.progress == b.progress and a.tone == b.tone
end

-- [E] prompts never show together with the third eye: while it is open the prompt layer hides
local promptsOff, promptWatch = false, false
local function watchTarget()
    if promptWatch then return end
    promptWatch = true
    CreateThread(function()
        while next(prompts) ~= nil do
            local on = Bridge and Bridge.Target and Bridge.Target.IsActive and Bridge.Target.IsActive() or false
            if on ~= promptsOff then
                promptsOff = on
                UI.Send(CORE, 'promptsOff', { on = on })
            end
            Wait(100)
        end
        if promptsOff then
            promptsOff = false
            UI.Send(CORE, 'promptsOff', { on = false })
        end
        promptWatch = false
    end)
end

-- true while the third eye is open: a module's own [E] check can skip the key then
function UI.PromptsBlocked() return promptsOff end

-- [E] prompts for world interactions only exist when there is no third eye: with
-- ox_target / qb-target / ... those actions are third-eye options instead.
-- (Action keys while placing a jammer are not world interactions and always show.)
local worldPromptsAt, worldPromptsOn = 0, true
function UI.WorldPrompts()
    local now = GetGameTimer()
    if now - worldPromptsAt > 2000 then
        worldPromptsAt = now
        local ok, res = pcall(function() return Bridge and Bridge.Target and Bridge.Target.Resource and Bridge.Target.Resource() end)
        worldPromptsOn = not ok or res == nil or res == 'builtin'
    end
    return worldPromptsOn
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
    watchTarget()
end

function UI.PromptProgress(id, progress)
    local p = prompts[id]
    if not p then return end
    progress = NZR.Util.Clamp(tonumber(progress) or 0, 0, 1)
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

-- Blocking hold helper. opts = { key = 'E', control = 38, seconds = 2, label, sub,
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

-- ui.* strings under both spellings: nzr.js looks up 'ui.close', apps may use 'close'
local function uiLocale()
    local out = {}
    for k, v in pairs(NZR.LocaleTable('ui')) do
        out[k] = v
        out['ui.' .. k] = v
    end
    return out
end

function UI.PushConfig()
    local c = Config.UI or {}
    local audio = Config.Audio or {}
    UI.Send(CORE, 'config', {
        font = c.font,
        shape = c.shape or 'cut',
        scale = c.scale,
        sounds = c.sounds,
        signature = c.signature,
        locale = uiLocale(),
        lang = Config.Locale or 'en',
        resource = NZR.Resource,
        sfx = tonumber(audio.sfx) or 0.8,
        clicks = audio.clicks ~= false,
        keys = Config.Keys or {},
    })
end

UI.On(CORE, 'ready', function(_, cb)
    markReady()
    UI.PushConfig()
    -- re-sync focus (the page may have reloaded while apps were open)
    refreshFocus()
    cb({ ok = true })
end)

-- ════════════════════════════════════════════════════════════════════════
-- SERVER → CLIENT
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nzr:ui:toast', function(data)
    UI.Toast(data)
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
    if res ~= NZR.Resource then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)
