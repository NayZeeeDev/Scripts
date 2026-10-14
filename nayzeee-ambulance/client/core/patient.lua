--[[
    NAYZEEE AMBULANCE - Client core: medic view of a patient (NZA.Patient)

      NZA.Patient.Get(target)            → snapshot | nil, err   (callback 'nza:patient:get',
                                           medic snapshot §4.3; awaits)
      NZA.Patient.Watch(target, fn, opts) → stop()
          Live updates while the returned stop() has not been called:
            fn(snapshot)            initial snapshot, then every server push
            fn(nil, reason)         once when the watch ends on its own:
                                    'far' | 'gone' | 'denied' | 'removed'
          opts = { maxDist = metres (default Config.Physiology.examDistance + 2),
                   keep = true to never auto-stop on distance (bays, monitors in a room),
                   initial = false to skip the initial Get }
          Several watches on the same patient share one server subscription (ref counted).
      NZA.Patient.Last(pid)              → last snapshot pushed for that pid (or nil)

    Callbacks used: nza:patient:get (target), nza:patient:watch (target, on)
    Net events handled: nza:patient:update (pid, snapshot)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Patient = NZA.Patient or {}
local P = NZA.Patient

local subs = {}        -- [key] = { target, pid, refs, watchers = { [id] = w }, serverOn }
local byPid = {}       -- [pid] = key
local last = {}        -- [pid] = snapshot
local nextId = 0
local loopRunning = false

local function defaultDist()
    return ((Config.Physiology and Config.Physiology.examDistance) or 4.0) + 2.0
end

function P.Get(target)
    if type(target) ~= 'table' then return nil, 'invalid' end
    local ok, snap, err = pcall(lib.callback.await, 'nza:patient:get', false, target)
    if not ok then return nil, 'error' end
    if type(snap) == 'table' and snap.pid then last[snap.pid] = snap end
    return snap, err
end

function P.Last(pid)
    return last[pid]
end

local function deliver(w, snap, reason)
    local ok, err = pcall(w.fn, snap, reason)
    if not ok then NZA.Warn('patient watch callback failed: ' .. tostring(err)) end
end

local function serverWatch(sub, on)
    if sub.serverOn == on then return true end
    local ok, res = pcall(lib.callback.await, 'nza:patient:watch', false, sub.target, on)
    local granted = ok and res == true
    if on then sub.serverOn = granted else sub.serverOn = false end
    return granted
end

local function dropSub(key)
    local sub = subs[key]
    if not sub then return end
    subs[key] = nil
    if sub.pid and byPid[sub.pid] == key then
        byPid[sub.pid] = nil
        last[sub.pid] = nil
    end
    if sub.serverOn then
        CreateThread(function() serverWatch(sub, false) end)
    end
end

local function endWatch(key, id, reason)
    local sub = subs[key]
    if not sub then return end
    local w = sub.watchers[id]
    if not w then return end
    sub.watchers[id] = nil
    sub.refs = sub.refs - 1
    if reason then deliver(w, nil, reason) end
    if sub.refs <= 0 then dropSub(key) end
end

local function startLoop()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        while next(subs) do
            Wait(1000)
            local me = GetEntityCoords(PlayerPedId())
            for key, sub in pairs(subs) do
                local ent = NZA.Target.Entity(sub.target)
                for id, w in pairs(sub.watchers) do
                    if not w.keep then
                        if ent == 0 then
                            endWatch(key, id, 'gone')
                        elseif #(me - GetEntityCoords(ent)) > w.maxDist then
                            endWatch(key, id, 'far')
                        end
                    end
                end
            end
        end
        loopRunning = false
    end)
end

function P.Watch(target, fn, opts)
    if type(target) ~= 'table' or type(fn) ~= 'function' then
        return function() end
    end
    opts = opts or {}
    local key = NZA.Target.Key(target)
    if not key then return function() end end

    nextId = nextId + 1
    local id = nextId
    local w = { fn = fn, maxDist = tonumber(opts.maxDist) or defaultDist(), keep = opts.keep == true }

    local sub = subs[key]
    local fresh = sub == nil
    if fresh then
        sub = { target = { kind = target.kind, sid = target.sid, net = target.net }, refs = 0, watchers = {}, serverOn = false }
        subs[key] = sub
        local st = NZA.Target.State(target)
        if type(st) == 'table' and st.pid then
            sub.pid = st.pid
            byPid[st.pid] = key
        end
    end
    sub.watchers[id] = w
    sub.refs = sub.refs + 1
    startLoop()

    local stopped = false
    local function stop()
        if stopped then return end
        stopped = true
        endWatch(key, id, nil)
    end

    CreateThread(function()
        if fresh then
            if not serverWatch(sub, true) then
                if subs[key] == sub and sub.watchers[id] then
                    endWatch(key, id, 'denied')
                    stopped = true
                end
                return
            end
            -- every watcher of this sub may have stopped while we were waiting
            if subs[key] ~= sub then serverWatch(sub, false) return end
        end
        if opts.initial ~= false then
            local snap = P.Get(sub.target)
            if stopped or subs[key] ~= sub then return end
            if type(snap) == 'table' then
                if snap.pid and not sub.pid then
                    sub.pid = snap.pid
                    byPid[snap.pid] = key
                end
                deliver(w, snap)
            end
        elseif sub.pid and last[sub.pid] then
            deliver(w, last[sub.pid])
        end
    end)

    return stop
end

RegisterNetEvent('nza:patient:update', function(pid, snap)
    if type(pid) ~= 'string' then return end
    local key = byPid[pid]
    -- pid not known yet (state bag lagged): match by the target inside the snapshot
    if not key and type(snap) == 'table' then
        for k, sub in pairs(subs) do
            if not sub.pid and ((snap.src and sub.target.kind == 'player' and tonumber(snap.src) == tonumber(sub.target.sid))
                or (snap.net and sub.target.kind == 'npc' and tonumber(snap.net) == tonumber(sub.target.net))) then
                sub.pid = pid
                byPid[pid] = k
                key = k
                break
            end
        end
    end
    local sub = key and subs[key]
    if type(snap) ~= 'table' then
        last[pid] = nil
        if sub then
            for id in pairs(sub.watchers) do endWatch(key, id, 'removed') end
        end
        return
    end
    last[pid] = snap
    if not sub then return end
    for _, w in pairs(sub.watchers) do deliver(w, snap) end
end)
