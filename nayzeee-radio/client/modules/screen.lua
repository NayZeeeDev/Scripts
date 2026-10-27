--[[
    NAYZEEE RADIO - Screen (client): the live screen on the raised radio (DUI)

    The page is a screen and nothing more: html/dui/radio.html?skin=<skin> draws the state
    the firmware renders and never sends anything back. One runtime texture dictionary for
    the session (they can never be freed), one browser per radio model in use, each with
    its own texture name. Only the BODY model's screen is replaced ('nzr_<m>_body' /
    'nzr_scr'), and only the local player ever has a body model in the world, so every other
    radio keeps its idle screen. A browser nobody used for 2 minutes is closed.

      NZR.Screen.Attach(model) → bool   start (or reuse) the browser of that model and put it on
                                        the body's screen; returns at once, the browser comes up
                                        in its own thread
      NZR.Screen.Detach(model)          not seen any more: the browser closes after 2 min idle
      NZR.Screen.Push(model, state)     SendDuiMessage { type = 'state', state } - only when the
                                        state changed (at most every 40 ms); kept and re-sent
                                        in full once the page is ready
      NZR.Screen.Ready(model) → bool    NZR.Screen.Destroy(model)    NZR.Screen.DestroyAll()

    DUI messages: { type = 'state', state = <firmware screen state> }, { type = 'ping' }
    Natives: CreateDui, IsDuiAvailable, GetDuiHandle, CreateRuntimeTxd ('nzr_rt'),
             CreateRuntimeTextureFromDuiHandle ('scr_<skin>_<serial>'), AddReplaceTexture,
             RemoveReplaceTexture, DestroyDui
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Screen = NZR.Screen or {}
local Screen = NZR.Screen

local RT_TXD = 'nzr_rt'
local IDLE_MS = 120000
local AVAILABLE_MS = 3000
local THROTTLE_MS = 40
local KEEPALIVE_MS = 5000      -- re-send the last state now and then: a reloaded page starts blank

local txd = nil
local serial = 0
local duis = {}                -- [model] = { obj, tex, ready, replaced, inUse, idleSince, last, lastSig, lastSent, flushAt, gen }
local stopping = false

local function layoutOf(model)
    local L = PropsLayout and PropsLayout[model]
    if type(L) ~= 'table' or type(L.screen) ~= 'table' then return nil end
    return L
end

local function send(d, payload)
    if not d.obj then return end
    local ok, msg = pcall(json.encode, payload)
    if ok then SendDuiMessage(d.obj, msg) end
end

local function sendState(d, force)
    if not d.ready or not d.last then return end
    local ok, sig = pcall(json.encode, d.last)
    if not ok then return end
    if not force and sig == d.lastSig then return end
    d.lastSig = sig
    d.lastSent = GetGameTimer()
    SendDuiMessage(d.obj, '{"type":"state","state":' .. sig .. '}')
end

local function unreplace(d)
    if d.replaced then
        pcall(RemoveReplaceTexture, d.replaced.txd, d.replaced.tex)
        d.replaced = nil
    end
end

local function replace(d, L)
    if d.replaced or not d.tex then return end
    local scr = L.screen
    local dict = scr.txd or L.body
    local tex = scr.tex or 'nzr_scr'
    AddReplaceTexture(dict, tex, RT_TXD, d.tex)
    d.replaced = { txd = dict, tex = tex }
end

local function destroy(d)
    unreplace(d)
    if d.obj then pcall(DestroyDui, d.obj) end
    d.obj, d.tex, d.ready, d.lastSig = nil, nil, false, nil
    d.creating = false
end

local function create(d, L)
    local scr = L.screen
    local w, h = math.floor(tonumber(scr.w) or 512), math.floor(tonumber(scr.h) or 384)
    local skin = L.skin or (NZR.Firmware and NZR.Firmware.Skin(d.model)) or 'px740'
    local url = ('nui://%s/html/dui/radio.html?skin=%s&w=%d&h=%d'):format(NZR.Resource, skin, w, h)
    local ok, obj = pcall(CreateDui, url, w, h)
    if not ok or not obj then
        NZR.Warn('could not create the radio screen browser for ' .. tostring(d.model))
        d.creating = false
        return
    end
    -- a page that has not loaded yet drops whatever is sent to it
    local t = GetGameTimer()
    while not IsDuiAvailable(obj) and GetGameTimer() - t < AVAILABLE_MS do Wait(50) end
    local handle = GetDuiHandle(obj)
    if stopping or not handle then
        pcall(DestroyDui, obj)
        d.creating = false
        return
    end
    if not txd then
        txd = CreateRuntimeTxd(RT_TXD)
        -- the dictionary needs a moment before a texture can be built from a browser handle
        Wait(250)
    end
    serial = serial + 1
    d.tex = ('scr_%s_%d'):format(skin, serial)
    CreateRuntimeTextureFromDuiHandle(txd, d.tex, handle)
    d.obj = obj
    d.creating = false
    Wait(400)   -- the page script needs a moment to attach its message listener
    if stopping or d.obj ~= obj then return end
    d.ready = true
    if d.inUse then replace(d, L) end
    send(d, { type = 'ping' })
    sendState(d, true)
end

local function keepAlive(d, gen)
    CreateThread(function()
        while d.inUse and d.gen == gen and not stopping do
            Wait(1000)
            local now = GetGameTimer()
            if d.flushAt and now >= d.flushAt then
                d.flushAt = nil
                sendState(d, false)
            end
            if d.ready and d.last and now - (d.lastSent or 0) >= KEEPALIVE_MS then sendState(d, true) end
        end
    end)
end

function Screen.Attach(model)
    local L = layoutOf(model)
    if not L then return false end
    local d = duis[model]
    if not d then
        d = { model = model, gen = 0 }
        duis[model] = d
    end
    d.inUse = true
    d.gen = d.gen + 1
    d.idleSince = nil
    if d.obj then
        replace(d, L)
        sendState(d, true)
    elseif not d.creating then
        d.creating = true
        CreateThread(function() create(d, L) end)
    end
    keepAlive(d, d.gen)
    return true
end

function Screen.Detach(model)
    local d = duis[model]
    if not d or not d.inUse then return end
    d.inUse = false
    d.gen = d.gen + 1
    local gen = d.gen
    d.idleSince = GetGameTimer()
    SetTimeout(IDLE_MS, function()
        if d.gen == gen and not d.inUse then destroy(d) end
    end)
end

function Screen.Push(model, state)
    local d = duis[model]
    if not d or type(state) ~= 'table' then return end
    d.last = state
    if not d.ready then return end
    local now = GetGameTimer()
    if now - (d.lastSent or 0) < THROTTLE_MS then
        -- a burst of changes: the last one goes out shortly after
        if not d.flushAt then
            d.flushAt = now + THROTTLE_MS
            SetTimeout(THROTTLE_MS, function()
                if d.flushAt then
                    d.flushAt = nil
                    sendState(d, false)
                end
            end)
        end
        return
    end
    sendState(d, false)
end

function Screen.Ready(model)
    local d = duis[model]
    return d ~= nil and d.ready == true
end

function Screen.Destroy(model)
    local d = duis[model]
    if not d then return end
    d.inUse = false
    d.gen = d.gen + 1
    destroy(d)
end

function Screen.DestroyAll()
    for model in pairs(duis) do Screen.Destroy(model) end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    stopping = true
    Screen.DestroyAll()
end)
