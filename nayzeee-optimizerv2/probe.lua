--[[
    NAYZEEE OPTIMIZER - PROBE
    Version: 1.1.0

    This file is loaded INSIDE other resources through their manifest:

        shared_script '@nayzeee-optimizerv2/probe.lua'

    It never runs in the optimizer itself. Running inside the host
    resource's own Lua state lets it time exactly that resource's code:
    every thread slice between Wait() calls, every event handler, NUI
    callback, command, timeout and export. Nothing else in FiveM exposes
    per-resource CPU time to scripts.

    Every 5 seconds it sends one small report to the optimizer via a local
    event. Overhead is two timer reads per slice (well under 1 microsecond).

    Compatible with Lua 5.3 and 5.4 resources. Does nothing for JS or C#
    runtimes (the server deep scan covers those).

    Kill switch: `setr nz_probe_disabled 1` in server.cfg (server side).
]]

if rawget(_G, '__NZ_PROBE') then return end
__NZ_PROBE = true

local HOST = 'nayzeee-optimizerv2'
local resName = GetCurrentResourceName()
if resName == HOST then return end

local isServer = IsDuplicityVersion()
if isServer and GetConvar('nz_probe_disabled', '0') == '1' then return end

do
    local st = GetResourceState(HOST)
    if st ~= 'started' and st ~= 'starting' then
        -- Optimizer not running: stay inert. Put `ensure nayzeee-optimizerv2`
        -- before other resources in server.cfg.
        return
    end
end

-- ── Timer ──────────────────────────────────────────────────────────────────────
-- Server: os.clock() (CPU time on Linux at microsecond resolution, wall
-- time on Windows at millisecond resolution). Client: GetGameTimer() (ms).
-- A millisecond timer still gives an unbiased total over thousands of
-- slices; only the longest-slice figure is quantised.
local now
if isServer and type(os) == 'table' and type(os.clock) == 'function' then
    local clk = os.clock
    now = function() return clk() * 1000.0 end
else
    local gt = GetGameTimer
    now = function() return gt() + 0.0 end
end

local pack, unpack = table.pack, table.unpack
local corunning, costatus = coroutine.running, coroutine.status
local traceback = (debug and debug.traceback) or function(e) return e end

local LONG_MS = 5

local stack = {}      -- coroutines of ours currently on the CPU (sync nesting)
local t0, excl = 0.0, 0.0
local acc = { ms = 0.0, slices = 0, peak = 0.0, long = 0, events = 0, nui = 0, cmds = 0, exports = 0 }
local wrappedFns = setmetatable({}, { __mode = 'k' })

local function prune()
    local n = #stack
    while n > 0 do
        local co = stack[n]
        if type(co) == 'thread' and costatus(co) == 'dead' then
            stack[n] = nil
            n = n - 1
        else
            break
        end
    end
end

local function closeSlice()
    local d = now() - t0 - excl
    if d > 0 then
        acc.ms = acc.ms + d
        if d > acc.peak then acc.peak = d end
        if d >= LONG_MS then acc.long = acc.long + 1 end
    end
    acc.slices = acc.slices + 1
end

local function enter()
    prune()
    if #stack == 0 then
        t0 = now()
        excl = 0.0
    end
    stack[#stack + 1] = corunning()
end

local function leave()
    local n = #stack
    if n == 0 then return end
    stack[n] = nil
    if n == 1 then closeSlice() end
end

-- Time spent inside another resource (local TriggerEvent, export calls)
-- is subtracted so it is not counted twice.
local function excluded(fn, ...)
    if #stack == 0 then return fn(...) end
    local s = now()
    local r = pack(fn(...))
    excl = excl + (now() - s)
    return unpack(r, 1, r.n)
end

local function wrapfn(fn, counter)
    if type(fn) ~= 'function' or wrappedFns[fn] then return fn end
    local w = function(...)
        if counter then acc[counter] = acc[counter] + 1 end
        enter()
        local r = pack(xpcall(fn, traceback, ...))
        leave()
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2, r.n)
    end
    wrappedFns[w] = true
    return w
end

-- Wait / Await: leaving the CPU closes the slice, coming back opens one.
local function wrapYield(orig)
    return function(...)
        local co = corunning()
        local n = #stack
        local mine = n > 0 and stack[n] == co
        if mine then
            stack[n] = nil
            if n == 1 then closeSlice() end
        end
        local r = pack(orig(...))
        if mine then
            if #stack == 0 then
                t0 = now()
                excl = 0.0
            end
            stack[#stack + 1] = co
        end
        return unpack(r, 1, r.n)
    end
end

-- ── Hooks ──────────────────────────────────────────────────────────────────────

local C = Citizen
local origCreateThread    = C.CreateThread
local origCreateThreadNow = C.CreateThreadNow
local origSetTimeout      = C.SetTimeout
local origWait            = C.Wait
local origAwait           = C.Await
local origTriggerEvent    = TriggerEvent

C.CreateThread = function(fn, ...) return origCreateThread(wrapfn(fn), ...) end
CreateThread = C.CreateThread

if origCreateThreadNow then
    C.CreateThreadNow = function(fn, ...) return origCreateThreadNow(wrapfn(fn), ...) end
    CreateThreadNow = C.CreateThreadNow
end

C.SetTimeout = function(ms, fn) return origSetTimeout(ms, wrapfn(fn)) end
SetTimeout = C.SetTimeout

C.Wait = wrapYield(origWait)
Wait = C.Wait

if origAwait then
    C.Await = wrapYield(origAwait)
end

do
    local orig = AddEventHandler
    AddEventHandler = function(name, fn) return orig(name, wrapfn(fn, 'events')) end
end

do
    local orig = RegisterNetEvent
    if orig then
        RegisterNetEvent = function(name, fn)
            if fn ~= nil then return orig(name, wrapfn(fn, 'events')) end
            return orig(name)
        end
    end
end

if not isServer and RegisterNUICallback then
    local orig = RegisterNUICallback
    RegisterNUICallback = function(name, fn) return orig(name, wrapfn(fn, 'nui')) end
end

do
    local orig = RegisterCommand
    if orig then
        RegisterCommand = function(name, fn, restricted) return orig(name, wrapfn(fn, 'cmds'), restricted) end
    end
end

do
    local orig = AddStateBagChangeHandler
    if orig then
        AddStateBagChangeHandler = function(key, bag, fn) return orig(key, bag, wrapfn(fn, 'events')) end
    end
end

TriggerEvent = function(...) return excluded(origTriggerEvent, ...) end

do
    local mt = type(exports) == 'table' and getmetatable(exports) or nil
    if type(mt) == 'table' then
        local origCall, origIndex = mt.__call, mt.__index
        if type(origCall) == 'function' then
            -- exports('name', fn): the function runs in OUR state when called
            mt.__call = function(t, ...)
                local args = pack(...)
                if type(args[2]) == 'function' then args[2] = wrapfn(args[2], 'exports') end
                return origCall(t, unpack(args, 1, args.n))
            end
        end
        if type(origIndex) == 'function' then
            -- exports.other:fn(): time spent in the other resource is excluded
            mt.__index = function(t, k)
                local inner = origIndex(t, k)
                if type(inner) ~= 'table' then return inner end
                return setmetatable({}, {
                    __index = function(_, fname)
                        local f = inner[fname]
                        if type(f) ~= 'function' then return f end
                        return function(_, ...) return excluded(f, inner, ...) end
                    end,
                })
            end
        end
    end
end

-- ── Reporter ───────────────────────────────────────────────────────────────────
-- Uses the ORIGINAL thread/wait/trigger so it never measures itself.

local interval = 5
if isServer then
    interval = tonumber(GetConvar('nz_probe_interval', '5')) or 5
    if interval < 2 then interval = 2 end
end

origCreateThread(function()
    local lastFrames = (not isServer) and GetFrameCount() or 0
    while true do
        origWait(interval * 1000)

        -- Full prune (dead coroutines anywhere in the stack)
        local live = {}
        for i = 1, #stack do
            local co = stack[i]
            if type(co) ~= 'thread' or costatus(co) ~= 'dead' then live[#live + 1] = co end
        end
        stack = live

        local frames = 0
        if not isServer then
            local f = GetFrameCount()
            frames = f - lastFrames
            lastFrames = f
        end

        local report = {
            res     = resName,
            side    = isServer and 'server' or 'client',
            win     = interval,
            ms      = acc.ms,
            slices  = acc.slices,
            peak    = acc.peak,
            long    = acc.long,
            events  = acc.events,
            nui     = acc.nui,
            cmds    = acc.cmds,
            exports = acc.exports,
            mem     = collectgarbage('count'),
            frames  = frames,
        }
        acc = { ms = 0.0, slices = 0, peak = 0.0, long = 0, events = 0, nui = 0, cmds = 0, exports = 0 }

        if GetResourceState(HOST) == 'started' then
            origTriggerEvent('nayzeee-optimizer:probe:report', report)
        end
    end
end)
