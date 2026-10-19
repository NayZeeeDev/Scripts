--[[
    NAYZEEE AMBULANCE - Procedures (NZA.Proc)                      ARCHITECTURE §5.2

    Minigame procedures with a server session. Modules register at their file top level:
      NZA.Proc.Register('suture', {
          perm = 'suture', items = {...} | fn(src, p, payload), maxDist = 3.0,
          minTime = 20, maxTime = 900,      -- seconds; finishing before minTime is rejected (anti-cheat)
          consume = 'start' | 'finish',     -- when the items are taken (default 'finish')
          easyTime = 12,                    -- progress-bar seconds in easy mode (also the easy-mode minTime);
                                            -- default: minTime clamped to 4..10 s (6 s when minTime is 0)
          label = 'Suture',                 -- optional: title of the client's progress bar / result toast
          self = false, states = {...}, npc = true, player = true,   -- same meaning as NZA.Treat
          onStart  = function(src, patient, payload, info) return true, data end,  -- data → client
          onFinish = function(src, patient, session, result) return outcome end,  -- apply effects
          onAbort  = function(src, patient, session, reason) end,                 -- patient may be nil
      })

    Callbacks
      nza:proc:start  (name, target, payload) → { ok, token, data, easy, easyTime, minTime, maxTime, maxDist,
                                                  label, allowDead, resumed, elapsed } | { ok = false, err, msg }
      nza:proc:finish (token, result)         → { ok, outcome } | { ok = false, err, msg }
      nza:proc:pause  (token, snapshot)       → { ok, keep } | { ok = false, err, msg }
    Pause (Config.ProcPause): the medic steps away from a running procedure (to fetch supplies). The
    session ends (onAbort runs with reason 'paused'); the game's snapshot, the active time so far and
    whether the items were already taken are kept for Config.ProcPause.keep seconds per medic +
    patient + procedure. Starting the same procedure on the same patient again resumes it: onStart
    runs again (fresh data; info.resume = true), data.resume = snapshot goes to the client,
    start-consumed items are not taken twice, and minTime / maxTime count the active time of both
    parts. def.pause = false opts a procedure out.
    Net event (C→S)
      nza:proc:abort  (token)
    Push (S→C)
      nza:proc:aborted (token, reason, msg)   the server ended a session (patient died / left / moved away / timeout)

    Rules: one session per medic (a new start replaces the old one), one session of the
    same procedure per patient, minTime / maxTime enforced on the server clock, score
    clamped 0..100 (easy mode forces Config.EasyMode.score), easy = NZA.Staff.Easy(src, perm),
    sessions abort on patient death / removal, medic leaving, distance > maxDist + 4 m,
    or timeout. Emits bus 'proc:done' (src, p, name, outcome) and 'proc:aborted'
    (src, p, name, reason); writes NZA.Records on success.

    Server API: NZA.Proc.Register(name, def) Get(name) Session(token) Active(src)
                Start(src, name, target, payload) Finish(src, token, result) Abort(token, reason)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Proc = NZA.Proc or {}
NZA.Core = NZA.Core or {}
local Pr = NZA.Proc
local Core = NZA.Core

Pr.registry = Pr.registry or {}
local sessions = {}   -- token → session
local byMedic = {}    -- src → token
local paused = {}     -- 'src:pid:name' → { snapshot, active (s), consumed, items, at (os.time) }

local function pauseKey(src, pid, name) return ('%s:%s:%s'):format(tostring(src), tostring(pid), tostring(name)) end
-- a parked session only resumes for the same payload (e.g. the same wound): flat values compared as text
local function samePayload(a, b)
    a = type(a) == 'table' and a or {}
    b = type(b) == 'table' and b or {}
    for k, v in pairs(a) do if type(v) ~= 'table' and tostring(b[k]) ~= tostring(v) then return false end end
    for k, v in pairs(b) do if type(v) ~= 'table' and tostring(a[k]) ~= tostring(v) then return false end end
    return true
end
local function pauseCfg() return Config.ProcPause or {} end
local function peekPaused(key)
    local e = paused[key]
    if e and os.time() - e.at > (tonumber(pauseCfg().keep) or 600) then
        paused[key] = nil
        return nil
    end
    return e
end

local function fail(code, extra)
    local r = { ok = false, err = code, msg = NZA.L('core.err_' .. code) }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    if r.item then r.msg = NZA.L('core.err_missing_item', Core.B('Inv.Label', r.item) or r.item) end
    return r
end

function Pr.Register(name, def)
    if type(name) ~= 'string' or type(def) ~= 'table' or type(def.onFinish) ~= 'function' then
        NZA.Warn('NZA.Proc.Register: bad definition for ' .. tostring(name))
        return false
    end
    def.name = name
    def.maxDist = tonumber(def.maxDist) or 3.0
    def.minTime = tonumber(def.minTime) or 0
    def.maxTime = tonumber(def.maxTime) or 900
    def.consume = def.consume == 'start' and 'start' or 'finish'
    -- easy mode: the client runs a progress bar for exactly easyTime seconds and the server
    -- uses the same number as the easy-mode minimum, so both sides always agree
    local easyTime = tonumber(def.easyTime)
    if not easyTime or easyTime <= 0 then
        easyTime = def.minTime > 0 and math.max(4, math.min(10, def.minTime)) or 6
    end
    def.easyTime = easyTime
    Pr.registry[name] = def
    return true
end

function Pr.Get(name) return Pr.registry[name] end
function Pr.Session(token) return sessions[token] end
function Pr.Active(src)
    local t = byMedic[tonumber(src) or -1]
    return t and sessions[t] or nil
end

local function newToken(src)
    return ('%x-%x-%x'):format(math.random(0, 0x7fffffff), GetGameTimer() % 0x7fffffff, (tonumber(src) or 0) * 7919 + math.random(0, 9999))
end

local function close(s)
    sessions[s.token] = nil
    if byMedic[s.src] == s.token then byMedic[s.src] = nil end
end

local function abort(s, reason, notify)
    if not sessions[s.token] then return end
    close(s)
    local p = NZA.Patients.Get(s.pid)
    if s.def.onAbort then
        local ok, err = pcall(s.def.onAbort, s.src, p, s, reason)
        if not ok then NZA.Warn(('proc %s onAbort failed: %s'):format(s.name, tostring(err))) end
    end
    if notify and Core.Online(s.src) then
        TriggerClientEvent('nza:proc:aborted', s.src, s.token, reason, NZA.L('core.abort_' .. reason))
    end
    NZA.Bus.Emit('proc:aborted', s.src, p, s.name, reason)
end

function Pr.Abort(token, reason)
    local s = sessions[token]
    if not s then return false end
    abort(s, reason or 'cancelled', true)
    return true
end

function Pr.Start(src, name, target, payload)
    src = tonumber(src)
    local def = Pr.registry[name]
    if not def then return fail('unknown_proc') end
    if not src or src <= 0 then return fail('no_perm') end
    if not Core.Rate('nza:proc:start', src, 2, 1000) then return fail('rate') end

    local old = byMedic[src] and sessions[byMedic[src]]
    if old then abort(old, 'replaced', false) end

    payload = type(payload) == 'table' and payload or {}
    local p, err = Core.TargetChecks(src, def, target)
    if not p then return fail(err) end
    for _, s in pairs(sessions) do
        if s.pid == p.pid and s.name == name then return fail('in_progress') end
    end

    -- carrying on after stepping away (Config.ProcPause): the saved state and the active time come back
    local resumeKey = pauseKey(src, p.pid, name)
    local resume = peekPaused(resumeKey)
    if resume and not samePayload(resume.payload, payload) then resume = nil end   -- parked on another wound: leave it parked

    local items = Core.ResolveItems(def, src, p, payload)
    if not items then return fail('failed') end
    local alreadyTaken = resume ~= nil and resume.consumed == true and def.consume == 'start'
    if alreadyTaken then
        items = resume.items or {}
    else
        local okItems, missing = Core.CheckItems(src, items)
        if not okItems then return fail('missing_item', { item = missing }) end
    end

    local easy = NZA.Staff.Easy(src, def.perm)
    local data
    if def.onStart then
        local ok, r1, r2 = pcall(def.onStart, src, p, payload, { easy = easy, resume = resume ~= nil })
        if not ok then
            NZA.Warn(('proc %s onStart failed: %s'):format(name, tostring(r1)))
            return fail('failed')
        end
        if not r1 then
            local r = fail('failed')
            if type(r2) == 'table' then
                r.err = r2.err or r.err
                r.msg = r2.msg or r.msg
            elseif type(r2) == 'string' then
                r.msg = r2
            end
            return r
        end
        data = r2
    end

    local consumed = alreadyTaken
    if not consumed and def.consume == 'start' and next(items) then
        Core.TakeItems(src, items)
        consumed = true
    end

    if resume then paused[resumeKey] = nil end
    local resumed = resume ~= nil and not easy
    local active = resumed and (tonumber(resume.active) or 0) or 0
    if resumed then
        if type(data) ~= 'table' then data = {} end
        data.resume = resume.snapshot
    end
    local s = {
        token = newToken(src), name = name, def = def, src = src, pid = p.pid,
        target = target, payload = payload, data = data, items = items, consumed = consumed,
        easy = easy, startedAt = GetGameTimer() - math.floor(active * 1000), started = os.time(),
        resumed = resumed,
    }
    sessions[s.token] = s
    byMedic[src] = s.token
    NZA.Bus.Emit('proc:started', src, p, name, s)
    return {
        ok = true, token = s.token, data = data, easy = easy,
        easyTime = def.easyTime, minTime = def.minTime, maxTime = def.maxTime,
        maxDist = def.maxDist, label = def.label,
        allowDead = type(def.states) == 'table' and def.states.dead == true or nil,
        resumed = resumed or nil, elapsed = resumed and active or nil,
        pausable = (pauseCfg().enabled ~= false and def.pause ~= false and not easy) and true or false,
    }
end

-- step away from a running session: keep its game state for the next start (Config.ProcPause)
function Pr.Pause(src, token, snapshot)
    src = tonumber(src)
    local s = token and sessions[token]
    if not s or s.src ~= src then return fail('no_session') end
    local pc = pauseCfg()
    if pc.enabled == false or s.easy or s.def.pause == false then return fail('failed') end
    if type(snapshot) ~= 'table' then return fail('failed') end
    local okJson, raw = pcall(json.encode, snapshot)
    if not okJson or type(raw) ~= 'string' or #raw > (tonumber(pc.maxBytes) or 24000) then return fail('failed') end
    local active = (GetGameTimer() - s.startedAt) / 1000
    if active > (s.def.maxTime or 900) then return fail('expired') end
    paused[pauseKey(src, s.pid, s.name)] = {
        snapshot = snapshot, active = active, consumed = s.consumed, items = s.items, payload = s.payload, at = os.time(),
    }
    abort(s, 'paused', false)
    return { ok = true, keep = tonumber(pc.keep) or 600 }
end

-- is there a paused session this medic can carry on for (patient id, procedure)?
function Pr.Paused(src, pid, name)
    return peekPaused(pauseKey(src, pid, name)) ~= nil
end

function Pr.Finish(src, token, result)
    src = tonumber(src)
    local s = token and sessions[token]
    if not s or s.src ~= src then return fail('no_session') end
    local def = s.def
    local elapsed = (GetGameTimer() - s.startedAt) / 1000

    local need = def.minTime or 0
    if s.easy then need = def.easyTime end
    if elapsed + 1.0 < need then
        abort(s, 'too_fast', false)
        return fail('too_fast')
    end
    if elapsed > (def.maxTime or 900) + 5 then
        abort(s, 'expired', false)
        return fail('expired')
    end

    local p = NZA.Patients.Get(s.pid)
    if not p then
        abort(s, 'no_patient', false)
        return fail('no_patient')
    end
    local p2, err = Core.TargetChecks(src, def, p, { slack = 2.0 })
    if not p2 then
        abort(s, err == 'too_far' and 'too_far' or 'patient_state', false)
        return fail(err)
    end

    result = type(result) == 'table' and result or {}
    local score = tonumber(result.score) or 0
    if score ~= score then score = 0 end
    result.score = math.floor(math.max(0, math.min(100, score)) + 0.5)
    if s.easy then
        result.score = (Config.EasyMode and Config.EasyMode.score) or 78
        result.easy = true
    else
        result.easy = nil
    end

    if def.consume == 'finish' and next(s.items) then
        local okItems, missing = Core.CheckItems(src, s.items)
        if not okItems then
            abort(s, 'missing_item', false)
            return fail('missing_item', { item = missing })
        end
        Core.TakeItems(src, s.items)
    end

    close(s)
    s.elapsed = elapsed
    local ok, outcome = pcall(def.onFinish, src, p, s, result)
    if not ok then
        NZA.Warn(('proc %s onFinish failed: %s'):format(s.name, tostring(outcome)))
        return fail('failed')
    end
    if type(outcome) ~= 'table' then outcome = { result = outcome } end
    outcome.score = outcome.score or result.score
    outcome.grade = outcome.grade or NZA.Util.Grade(outcome.score)
    outcome.easy = result.easy

    NZA.Patients.Touch(p, true)
    NZA.Bus.Emit('proc:done', src, p, s.name, outcome)
    if def.record ~= false then
        NZA.Records.Add(p, { medic = src, action = s.name, summary = outcome.record or {
            score = outcome.score, grade = outcome.grade, msg = outcome.msg, easy = outcome.easy, seconds = math.floor(elapsed),
        } })
    end
    return { ok = true, outcome = outcome }
end

lib.callback.register('nza:proc:start', function(src, name, target, payload)
    if type(name) ~= 'string' then return fail('unknown_proc') end
    return Pr.Start(src, name, target, payload)
end)

lib.callback.register('nza:proc:finish', function(src, token, result)
    if type(token) ~= 'string' then return fail('no_session') end
    return Pr.Finish(src, token, result)
end)

lib.callback.register('nza:proc:pause', function(src, token, snapshot)
    if type(token) ~= 'string' then return fail('no_session') end
    if not Core.Rate('nza:proc:pause', src, 2, 1000) then return fail('rate') end
    return Pr.Pause(src, token, snapshot)
end)

RegisterNetEvent('nza:proc:abort', function(token)
    local src = tonumber(source)
    local s = type(token) == 'string' and sessions[token]
    if s and s.src == src then abort(s, 'cancelled', false) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

local function abortForPatient(pid, reason, keepDead)
    for _, s in pairs(sessions) do
        if s.pid == pid then
            if not (keepDead and type(s.def.states) == 'table' and s.def.states.dead) then
                abort(s, reason, true)
            end
        end
    end
end

-- paused sessions go when their patient or their medic does
local function dropPaused(match)
    for k, e in pairs(paused) do
        if match(k, e) then paused[k] = nil end
    end
end
local function dropPatient(pid)
    local mid = ':' .. tostring(pid) .. ':'
    dropPaused(function(k) return k:find(mid, 1, true) ~= nil end)
end

NZA.Bus.On('patient:death', function(p)
    abortForPatient(p.pid, 'patient_state', true)
    dropPatient(p.pid)
end)
NZA.Bus.On('patient:removed', function(pid)
    abortForPatient(pid, 'no_patient', false)
    dropPatient(pid)
end)
NZA.Bus.On('player:unloaded', function(src)
    local s = Pr.Active(src)
    if s then abort(s, 'cancelled', false) end
    local head = tostring(src) .. ':'
    dropPaused(function(k) return k:sub(1, #head) == head end)
end)

CreateThread(function()
    local sweepAt = 0
    while true do
        Wait(2000)
        if GetGameTimer() > sweepAt then
            sweepAt = GetGameTimer() + 60000
            local keep = tonumber(pauseCfg().keep) or 600
            local now = os.time()
            dropPaused(function(_, e) return now - e.at > keep end)
        end
        local list = {}
        for _, s in pairs(sessions) do list[#list + 1] = s end
        for _, s in ipairs(list) do
            local elapsed = (GetGameTimer() - s.startedAt) / 1000
            local p = NZA.Patients.Get(s.pid)
            if not Core.Online(s.src) then
                abort(s, 'cancelled', false)
            elseif elapsed > (s.def.maxTime or 900) + 5 then
                abort(s, 'timeout', true)
            elseif not p then
                abort(s, 'no_patient', true)
            else
                local isSelf = p.kind == 'player' and p.src == s.src
                local allowed = (type(s.def.states) == 'table' and s.def.states[p.state]) or (type(s.def.states) ~= 'table' and p.state ~= 'dead')
                if not allowed then
                    abort(s, 'patient_state', true)
                elseif not isSelf and Core.DistanceTo(s.src, p) > (s.def.maxDist or 3.0) + 4.0 then
                    abort(s, 'too_far', true)
                end
            end
        end
    end
end)
