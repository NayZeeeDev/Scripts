--[[
    NAYZEEE AMBULANCE - Client core: treatments & procedure sessions (NZA.Treat, NZA.Proc)

      NZA.Treat.Do(action, target, payload, opts) → ok, result
          lib.callback 'nza:treat'. Shows result.msg (or the error) as a toast unless
          opts.silent. ARCHITECTURE §5.1.

      NZA.Proc.Run(name, target, payload, runner, opts) → ok, outcome | false, reason
          ARCHITECTURE §5.2. Blocks until the session ends (call it from a thread; every
          NZA.Interact onSelect already runs in one).
            1. 'nza:proc:start' (name, target, payload) → { ok, token, data, easy, ... }
            2. easy mode → ox_lib progress (Config.EasyMode.style 'bar' | 'circle') with a
               fitting medic animation, result { score = Config.EasyMode.score, easy = true }
               otherwise → runner(ctx) runs the module's minigame
            3. ctx.finish(result) → 'nza:proc:finish' (token, result) → toast with the grade
               ctx.abort(reason) → event 'nza:proc:abort' (token)
          ctx = { token, data, easy, target, name, payload, entity, startedAt, label,
                  finish(result) → ok, outcome, abort(reason), onEnd(fn(outcome|nil, reason)),
                  done() → bool, elapsed() → seconds }
          Errors are shown with the server's localized msg when it sends one.
          The session is cancelled automatically when the patient entity disappears, the
          medic moves further than maxDist + 2 m (maxDist from the server's registration;
          the server itself aborts at + 4 m), the patient dies during it (unless the
          procedure allows dead patients), the medic goes down, or maxTime runs out.
          onEnd callbacks fire in every case, so modules close their NUI there.
          target may be a target table or a ped / body bag entity.
          opts = { label, anim = { dict, clip, flag } | { scenario }, maxDist, silent }
      NZA.Proc.Active() → ctx | nil      NZA.Proc.Abort(reason)

      NZA.Anim.Kneel(ped) → token        kneel down (enter clip → looping base, exit on Stop)

    Callbacks used: nza:treat, nza:proc:start, nza:proc:finish
    Events sent: nza:proc:abort (token)
    Net events handled: nza:proc:aborted (token, reason, msg) - server ended the session
    Bus events emitted: proc:started (ctx), proc:ended (name, ok, outcome|reason)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Treat = NZA.Treat or {}
NZA.Proc = NZA.Proc or {}
NZA.Anim = NZA.Anim or {}
local Treat = NZA.Treat
local Proc = NZA.Proc
local Anim = NZA.Anim
local U = NZA.Util

local KNEEL_ENTER = { 'amb@medic@standing@kneel@enter', 'enter' }
local KNEEL_BASE = { 'amb@medic@standing@kneel@base', 'base' }
local KNEEL_EXIT = { 'amb@medic@standing@kneel@exit', 'exit' }

-- Easy-mode animation per procedure; anything else kneels (patient on the ground)
-- or works standing (patient upright) / on yourself.
local PROC_ANIMS = {
    cpr = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
}
local ANIM_KNEEL = { dict = KNEEL_BASE[1], clip = KNEEL_BASE[2], flag = 1 }
local ANIM_STAND = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 }
local ANIM_SELF = { dict = 'missmic4', clip = 'michael_tux_fidget', flag = 49 }

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function errText(err)
    if type(err) == 'table' then err = err.msg or err.message or err.error or err.err end
    if type(err) ~= 'string' or err == '' then return NZA.L('core_client.err.generic') end
    local key = 'core_client.err.' .. err
    local loc = NZA.L(key)
    if loc ~= key then return loc end
    return err
end

local function toast(kind, title, message, extra)
    if not NZA.UI or not NZA.UI.Toast then return end
    local t = { type = kind, title = title, message = message }
    if extra then for k, v in pairs(extra) do t[k] = v end end
    NZA.UI.Toast(t)
end

local function patientLying(entity)
    if entity == 0 then return false end
    local st = NZA.Target.State(entity)
    local s = type(st) == 'table' and st.st or 'alive'
    if s ~= 'alive' then return true end
    return IsPedRagdoll(entity) or IsPedFatallyInjured(entity) or IsEntityDead(entity)
end

local function pickAnim(name, entity, isSelf, opts)
    if opts and opts.anim then return opts.anim end
    if PROC_ANIMS[name] then return PROC_ANIMS[name] end
    if isSelf then return ANIM_SELF end
    if patientLying(entity) then return ANIM_KNEEL end
    return ANIM_STAND
end

-- ════════════════════════════════════════════════════════════════════════
-- KNEEL
-- ════════════════════════════════════════════════════════════════════════

function Anim.Kneel(ped)
    ped = ped or PlayerPedId()
    local ok, token = Anim.Play(ped, KNEEL_ENTER[1], KNEEL_ENTER[2], { flag = 2, blendIn = 4.0, blendOut = -4.0 })
    if not ok then
        -- no enter clip available: go straight to the loop
        ok, token = Anim.Play(ped, KNEEL_BASE[1], KNEEL_BASE[2], { flag = 1, blendIn = 4.0 })
        if ok and Anim._SetExit then Anim._SetExit(ped, token, KNEEL_EXIT[1], KNEEL_EXIT[2]) end
        return token
    end
    if Anim._SetExit then Anim._SetExit(ped, token, KNEEL_EXIT[1], KNEEL_EXIT[2]) end
    CreateThread(function()
        local started = Anim.Current(ped)
        local dur = started and started.token == token and started.duration or 0
        if not dur or dur <= 0 then dur = 1200 end
        Wait(math.max(200, dur - 150))
        local cur = Anim.Current(ped)
        if not cur or cur.token ~= token then return end
        local okBase = pcall(lib.requestAnimDict, KNEEL_BASE[1], 2000)
        if not okBase then return end
        TaskPlayAnim(ped, KNEEL_BASE[1], KNEEL_BASE[2], 4.0, -4.0, -1, 1, 0.0, false, false, false)
        RemoveAnimDict(KNEEL_BASE[1])
        cur.dict, cur.clip = KNEEL_BASE[1], KNEEL_BASE[2]
    end)
    return token
end

-- ════════════════════════════════════════════════════════════════════════
-- INSTANT TREATMENTS
-- ════════════════════════════════════════════════════════════════════════

function Treat.Do(action, target, payload, opts)
    opts = opts or {}
    if type(target) == 'number' then target = NZA.Target.FromEntity(target) end
    local ok, res, extra = pcall(lib.callback.await, 'nza:treat', false, action, target, payload or {})
    if not ok then
        if not opts.silent then toast('error', nil, NZA.L('core_client.err.generic')) end
        return false, 'error'
    end
    local success, result = res, extra
    if not opts.silent then
        if success then
            local msg = type(result) == 'table' and (result.msg or result.message) or nil
            if msg then toast('success', result.title, msg) end
        else
            toast('error', nil, errText(result))
        end
    end
    return success == true, result
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURES
-- ════════════════════════════════════════════════════════════════════════

local active = nil

function Proc.Active()
    return active
end

function Proc.Abort(reason)
    if active and active.abort then active.abort(reason or 'cancel') end
end

local function procLabel(name, resp, opts)
    if opts and opts.label then return opts.label end
    if resp and resp.label then return resp.label end
    if resp and type(resp.data) == 'table' and resp.data.label then return resp.data.label end
    local key = name .. '.title'
    local loc = NZA.L(key)
    if loc ~= key then return loc end
    return NZA.L('core_client.proc.working')
end

-- ox_lib progress in the configured style; returns true when it ran to the end
local function progress(duration, label, anim)
    local style = Config.EasyMode and Config.EasyMode.style or 'bar'
    local data = {
        duration = duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        allowRagdoll = false,
        disable = { move = true, car = true, combat = true, sprint = true },
        anim = anim and (anim.scenario and { scenario = anim.scenario } or
            { dict = anim.dict, clip = anim.clip, flag = anim.flag or 1 }) or nil,
    }
    if style == 'circle' then
        data.position = 'bottom'
        return lib.progressCircle(data)
    end
    return lib.progressBar(data)
end

function Proc.Run(name, target, payload, runner, opts)
    opts = opts or {}
    if active then
        if not opts.silent then toast('error', nil, NZA.L('core_client.proc.busy')) end
        return false, 'busy'
    end
    if type(target) == 'number' then target = NZA.Target.FromEntity(target) end
    if type(target) ~= 'table' then return false, 'invalid' end

    -- reserve the slot before awaiting so a double click cannot start two sessions
    local ctx = { name = name, target = target, payload = payload or {}, starting = true }
    active = ctx

    local okCall, resp = pcall(lib.callback.await, 'nza:proc:start', false, name, target, payload or {})
    if not okCall or type(resp) ~= 'table' or not resp.ok then
        active = nil
        local reason = okCall and type(resp) == 'table' and (resp.err or resp.error) or 'error'
        if not opts.silent then
            toast('error', procLabel(name, resp, opts), errText(okCall and type(resp) == 'table' and resp or reason))
        end
        return false, reason
    end

    local isSelf = NZA.Target.IsSelf(target)
    local entity = NZA.Target.Entity(target)
    local startState = (function()
        local st = NZA.Target.State(target)
        return type(st) == 'table' and st.st or 'alive'
    end)()
    -- the server aborts at maxDist + 4 m; the client stops the minigame a little earlier
    local maxDist = (tonumber(opts.maxDist) or tonumber(resp.maxDist) or 3.0) + 2.0
    local maxTime = tonumber(resp.maxTime) or 900
    local minTime = tonumber(resp.minTime)
    local allowDead = resp.allowDead == true
    local label = procLabel(name, resp, opts)
    local finished = promise.new()
    local endFns = {}
    local isDone = false

    ctx.starting = nil
    ctx.token = resp.token
    ctx.data = resp.data or {}
    ctx.easy = resp.easy == true
    ctx.entity = entity
    ctx.startedAt = GetGameTimer()
    ctx.label = label

    local function close(ok, outcome, reason)
        if active == ctx then active = nil end
        for _, fn in ipairs(endFns) do
            local s, err = pcall(fn, ok and outcome or nil, reason)
            if not s then NZA.Warn('proc onEnd failed: ' .. tostring(err)) end
        end
        NZA.Bus.Emit('proc:ended', name, ok, ok and outcome or reason)
        finished:resolve({ ok, ok and outcome or reason })
    end

    function ctx.done() return isDone end
    function ctx.elapsed() return (GetGameTimer() - ctx.startedAt) / 1000 end
    function ctx.onEnd(fn)
        if type(fn) == 'function' then endFns[#endFns + 1] = fn end
    end

    -- serverMsg is set when the server already ended the session ('nza:proc:aborted')
    function ctx.abort(reason, serverMsg)
        if isDone then return end
        isDone = true
        reason = reason or 'cancel'
        if not ctx.serverEnded then TriggerServerEvent('nza:proc:abort', ctx.token) end
        if lib.progressActive() then lib.cancelProgress() end
        if not opts.silent and reason ~= 'silent' then
            local msg = serverMsg
            if type(msg) ~= 'string' or msg == '' then
                local key = 'core_client.proc.cancel_' .. tostring(reason)
                msg = NZA.L(key)
                if msg == key then msg = NZA.L('core_client.proc.aborted') end
            end
            toast('error', label, msg)
        end
        close(false, nil, reason)
    end

    function ctx.finish(result)
        if isDone then return false, 'done' end
        isDone = true
        if type(result) ~= 'table' then result = {} end
        result.score = U.clamp(math.floor(tonumber(result.score) or 0), 0, 100)
        -- never hand the server a finish it would reject as too fast
        if minTime and not ctx.easy then
            local wait = minTime - ctx.elapsed()
            if wait > 0 then Wait(math.floor(wait * 1000) + 150) end
        end
        local ok, res = pcall(lib.callback.await, 'nza:proc:finish', false, ctx.token, result)
        if not ok or type(res) ~= 'table' or not res.ok then
            local reason = ok and type(res) == 'table' and (res.err or res.error) or 'error'
            if not opts.silent then toast('error', label, errText(ok and type(res) == 'table' and res or reason)) end
            close(false, nil, reason)
            return false, reason
        end
        local outcome = res.outcome or {}
        if not opts.silent then
            local score = U.clamp(math.floor(tonumber(outcome.score) or result.score), 0, 100)
            local grade = U.Grade(score)
            local msg = outcome.msg or outcome.message or NZA.L('core_client.proc.done')
            toast(score >= 40 and 'success' or 'warning', label,
                msg .. ' · ' .. NZA.L('core_client.proc.grade', grade, score),
                { grade = grade, score = score })
        end
        close(true, outcome, nil)
        return true, outcome
    end

    NZA.Bus.Emit('proc:started', ctx)

    -- watchdog: patient gone / too far / died, medic down, time limit
    local medicWasUp = not (NZA.Self and NZA.Self.State) or NZA.Self.State() == 'alive'
    CreateThread(function()
        while not isDone do
            Wait(250)
            if isDone then break end
            local ent = NZA.Target.Entity(target)
            local reason = nil
            if medicWasUp and NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then
                reason = 'down'
            elseif ent == 0 then
                reason = 'gone'
            elseif not isSelf and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ent)) > maxDist then
                reason = 'far'
            elseif ctx.elapsed() > maxTime then
                reason = 'time'
            else
                local st = NZA.Target.State(target)
                local s = type(st) == 'table' and st.st or 'alive'
                if s == 'dead' and startState ~= 'dead' and not allowDead then reason = 'dead' end
            end
            if reason then
                ctx.abort(reason)
                break
            end
        end
    end)

    if ctx.easy then
        CreateThread(function()
            local anim = pickAnim(name, entity, isSelf, opts)
            local easyTime = tonumber(resp.easyTime) or tonumber(ctx.data.easyTime) or 10
            if entity ~= 0 and not isSelf then TaskTurnPedToFaceEntity(PlayerPedId(), entity, 600) Wait(600) end
            local completed = progress(math.floor(easyTime * 1000), label, anim)
            if isDone then return end
            if completed then
                ctx.finish({ score = (Config.EasyMode and Config.EasyMode.score) or 78, easy = true })
            else
                ctx.abort('cancel')
            end
        end)
    elseif type(runner) == 'function' then
        CreateThread(function()
            local ok, err = pcall(runner, ctx)
            if not ok then
                NZA.Warn(('procedure "%s" runner failed: %s'):format(name, tostring(err)))
                ctx.abort('error')
            end
        end)
    else
        ctx.abort('error')
    end

    local r = Citizen.Await(finished)
    return r[1], r[2]
end

-- the server ended the session itself (patient died / left, medic too far, timeout)
RegisterNetEvent('nza:proc:aborted', function(token, reason, msg)
    local ctx = active
    if not ctx or not ctx.abort or ctx.token ~= token then return end
    ctx.serverEnded = true
    ctx.abort(type(reason) == 'string' and reason or 'server', msg)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    if active and active.token then TriggerServerEvent('nza:proc:abort', active.token) end
end)
