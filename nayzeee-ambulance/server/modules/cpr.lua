--[[
    NAYZEEE AMBULANCE - CPR & defibrillator (server, authoritative)          NZA.Cpr

    One "code" (resuscitation) per patient, run by up to Config.Cpr.maxTeam medics:
      comp  the compressor (Space on the beat; breaths too when alone)
      air   the partner: breaths, pads, analysis, charge / shock, adrenaline; swap at the 2-min check
    The server owns the phase machine and every clinical decision:
      compress → (30 compressions) breaths → compress …   analyse (hands off) → advised | no shock
      advised / manual → charging → charged ("stand clear") → shock → compress   …   rosc
    It validates distance (server coords), permissions (NZA.Staff.Can), items (Bridge), rate limits,
    clamps every client number and keeps the arrest → death timer paused with NZA.Patients.Cpr while
    CPR is really happening (compressions in the last 1.5 s or a planned pause).
    ROSC = NZA.Patients.Revive(pid, { rosc = true }) → patient 'wounded' with a perfusing rhythm.

    Callbacks (lib.callback, all return { ok, err?, msg?, ... }):
      nza:cpr:start    (target, { origin = { x, y, z, h } })  start a code or join one as the partner
      nza:cpr:pads     ()                attach the pads (needs a defibrillator, see Config.Cpr.Defib)
      nza:cpr:analyse  ()                analyse the rhythm (4 s, no compressions)
      nza:cpr:charge   ({ energy })      charge (manual: any time; AED: only when a shock is advised)
      nza:cpr:disarm   ()                dump the charge
      nza:cpr:shock    ({ energy })      deliver the shock → { ok, result = 'rosc'|'none'|'no_effect'|'induced' }
      nza:cpr:energy   ({ energy })      energy knob (manual mode)
      nza:cpr:mode     ({ mode })        'aed' | 'manual' (manual needs Config.Cpr.Defib.perm)
      nza:cpr:adrenaline ()              via NZA.Treat 'cpr_adrenaline' (item, perm, gap, access)
      nza:cpr:swap     ()                compressor ↔ partner
      nza:cpr:pulse    ()                carotid check → { pulse, rate }
    Net events C→S:
      nza:cpr:cycle  { n, timing, depth, recoil, rate, done }   compressions since the last report (≤ 1 s)
      nza:cpr:breath { hold }                                    one rescue breath (seconds Space was held)
      nza:cpr:hands  ()                                          compressor touched the chest while "stand clear"
      nza:cpr:leave  ()                                          leave the code (ESC)
    Net events S→C:
      nza:cpr:state  (view)                 participants, on every change (role-specific view)
      nza:cpr:event  ({ kind, ... })        one-off moments: advice, charged, disarmed, shock, zapped, rosc,
                                            rearrest, swap, joined, partner_left, promoted, breaths, adrenaline
      nza:cpr:ended  (summary)              your part in the code is over (summary.reason)
      nza:cpr:pose   ({ on, origin, mode, rate })   to a PLAYER patient: lie flat in the synced CPR pose
      nza:cpr:use    ()                     the defibrillator item was used (client starts CPR nearby)
    State bag 'nzaCpr' (player / NPC ped) = server id of the compressor while a code runs.
    NZA.Treat 'cpr_adrenaline' (perm Config.Cpr.Adrenaline.perm, item Config.Items.adrenaline).
    Bus: cpr:started (p, code), cpr:shock (p, src, energy, result), cpr:rosc (p, code), cpr:ended (p, code, reason, summary)
    Exports: IsInCpr(pidOrSrc) → bool, GetCode(pidOrSrc) → small table | nil
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Cpr = NZA.Cpr or {}
local C = NZA.Cpr
-- cpr_logic.lua loads after this file (alphabetical) and fills this same table
C.Logic = C.Logic or {}
local Logic = C.Logic
local Core = NZA.Core
local P = NZA.Patients
local U = NZA.Util

C.codes = C.codes or {}       -- [pid] = code
C.member = C.member or {}     -- [src] = pid
local codes, member = C.codes, C.member

local SHOCKABLE = (NZA.Const and NZA.Const.Shockable) or { vf = true, vt = true }
local TICK = 250

local function cfg() return Config.Cpr or {} end
local function sub(name) return cfg()[name] or {} end
local function L(key, ...) return NZA.L('cpr.' .. key, ...) end
local function fail(err, ...) return { ok = false, err = err, msg = L('err_' .. err, ...) } end
local function nowMs() return GetGameTimer() end
local function clamp(n, lo, hi)
    n = tonumber(n) or lo
    if n ~= n then n = lo end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end
local function round(n) return math.floor((tonumber(n) or 0) + 0.5) end

local function item(key) return Config.Items and Config.Items[key] or nil end
local function hasItem(src, key)
    local name = item(key)
    if not name then return false end
    return Core.B('Inv.HasItem', src, name, 1) == true
end
local function countItem(src, key)
    local name = item(key)
    if not name then return 0 end
    return tonumber(Core.B('Inv.Count', src, name)) or 0
end

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function rhythmOf(p)
    if p.state == 'arrest' or p.state == 'dead' then
        local a = p.conditions and p.conditions.arrest
        return (a and a.rhythm) or 'asystole'
    end
    return (p.vitals and p.vitals.rhythm) or 'sinus'
end

local function notBreathing(p)
    local v = p.vitals or {}
    return v.breathing == 'absent' or v.breathing == 'agonal' or (tonumber(v.rr) or 14) <= 4
end

local function eligible(p)
    if p.state == 'arrest' then return true end
    if p.state == 'wounded' and cfg().wounded ~= false then
        local v = p.vitals or {}
        if v.avpu == 'U' and notBreathing(p) then return true end
        return false, 'breathing'
    end
    if p.state == 'dead' then return false, 'dead' end
    return false, 'not_arrest'
end

local function patientBusy(p)
    local m = p.meta or {}
    return m.carried ~= nil and m.carried ~= false or m.bodybag ~= nil and m.bodybag ~= false
        or m.vehicle ~= nil and m.vehicle ~= false
end

local function inHospital(p)
    local d = sub('Defib')
    if d.hospital == false then return false end
    local m = p.meta or {}
    if m.bed ~= nil or m.inBed then return true end
    if NZA.Hospitals and type(NZA.Hospitals.Nearest) == 'function' then
        local c = Core.PatientCoords(p)
        if c then
            local ok, dept, dist = pcall(NZA.Hospitals.Nearest, c)
            if ok and dept and dist and dist <= (d.hospitalRadius or 60.0) then return true end
        end
    end
    return false
end

-- defibrillator source for this medic + patient: 'item' | 'bay' | 'hospital' | nil
local function defibSource(src, p)
    local d = sub('Defib')
    if d.bay ~= false and p.meta and p.meta.bay ~= nil then return 'bay' end
    for _, key in ipairs(d.items or { 'defibrillator', 'trauma_kit' }) do
        if hasItem(src, key) then return 'item' end
    end
    if inHospital(p) then return 'hospital' end
    return nil
end

local function codeDefib(code, p)
    for s in pairs(code.team) do
        local srcType = defibSource(s, p)
        if srcType then return srcType end
    end
    return nil
end

-- on a bed, stretcher or in the bay the patient stays where they are (no floor pose)
local function bedLike(p)
    local m = p.meta or {}
    return m.bed ~= nil or m.inBed == true or m.bay ~= nil or (m.stretcher ~= nil and m.stretcher ~= false)
end
C.BedLike = bedLike

local function canManual(src) return NZA.Staff.Can(src, sub('Defib').perm or 'defib') end
local function canAed(src) return NZA.Staff.Can(src, sub('Defib').aedPerm or 'cpr') end

local function setBag(p, value)
    if p.kind == 'player' and p.src then
        local ok = pcall(function() Player(p.src).state:set('nzaCpr', value, true) end)
        if not ok then NZA.Debug('cpr: state bag failed', p.pid) end
        return
    end
    local ped = Core.PatientPed(p)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        pcall(function() Entity(ped).state:set('nzaCpr', value, true) end)
    end
end

local function log(code, key, tone, ...)
    local t = math.max(0, os.time() - code.started)
    code.log[#code.log + 1] = { t = t, text = L('log_' .. key, ...), tone = tone }
    while #code.log > 40 do table.remove(code.log, 1) end
end

local function dirty(code) code.dirty = true end

local function memberCode(src)
    local pid = member[src]
    if not pid then return nil end
    local code = codes[pid]
    if not code or not code.team[src] then member[src] = nil; return nil end
    return code, code.team[src]
end

local function emit(code, data, only)
    for s in pairs(code.team) do
        if not only or only == s then TriggerClientEvent('nza:cpr:event', s, data) end
    end
end

local function breather(code) return code.air or code.comp end

local function continuous(p)
    if sub('Breaths').continuousIfVentilated == false then return false end
    local d = p.devices or {}
    return d.intubated == true and (p.meta and p.meta.ventilated) and true or false
end

-- ════════════════════════════════════════════════════════════════════════
-- VIEW (what each participant's device shows)
-- ════════════════════════════════════════════════════════════════════════

local function phaseLeft(code, now)
    local ph = code.phase
    if ph == 'analyse' then return math.max(0, (code.analyseEnd - now) / 1000) end
    if ph == 'charging' then return math.max(0, (code.chargeEnd - now) / 1000) end
    if ph == 'charged' then return math.max(0, ((sub('Defib').chargedFor or 25) * 1000 - (now - code.chargedAt)) / 1000) end
    if ph == 'breaths' then return math.max(0, ((sub('Breaths').timeout or 10) * 1000 - (now - code.phaseAt)) / 1000) end
    return nil
end

local function view(code, src, p)
    local m = code.team[src]
    local now = nowMs()
    local v = p.vitals or {}
    local monitorOn = code.pads or (p.devices and p.devices.monitor) or false
    local rhythm = monitorOn and rhythmOf(p) or nil
    local ad = sub('Adrenaline')
    local adLast = code.adrenaline.last
    local adSince = adLast and (os.time() - adLast) or nil
    local adDue = false
    if ad.enabled ~= false then
        if adLast then adDue = adSince >= (ad.due or 240)
        else adDue = code.needAdrenaline == true end
    end
    local d = sub('Defib')
    local partner = (src == code.comp) and code.air or code.comp
    local cyc = sub('Cycle')
    return {
        id = code.id, pid = code.pid, name = p.name, sex = p.sex, npc = p.kind == 'npc',
        role = (src == code.comp) and 'comp' or 'air', solo = code.air == nil,
        compName = code.team[code.comp] and code.team[code.comp].name or '', airName = code.air and code.team[code.air] and code.team[code.air].name or nil,
        partner = partner and code.team[partner] and code.team[partner].name or nil,
        phase = code.phase, phaseLeft = phaseLeft(code, now), state = p.state, kind = code.kind,
        rhythm = rhythm, monitor = monitorOn and true or false,
        hr = monitorOn and (p.state == 'arrest' and (tonumber(v.ecgRate) or 0) or (tonumber(v.hr) or 0)) or nil,
        etco2 = monitorOn and (tonumber(v.etco2) or 0) or nil,
        spo2 = (monitorOn and p.state ~= 'arrest') and (tonumber(v.spo2) or 0) or nil,
        sys = (monitorOn and p.state ~= 'arrest') and (tonumber(v.sys) or 0) or nil,
        dia = (monitorOn and p.state ~= 'arrest') and (tonumber(v.dia) or 0) or nil,
        set = code.set, perSet = sub('Compressions').perSet or 30, total = code.total,
        cycleNo = code.cycleNo, cycleElapsed = math.floor((now - code.cycleStart) / 1000), cycleLength = cyc.length or 120,
        quality = round(code.quality), rate = round(code.rate), depth = round(code.depth), recoil = round(code.recoil),
        ccf = code.elapsed > 0 and round(code.handsOn / code.elapsed * 100) or 0,
        vent = code.continuous and 100 or round(code.vent), ventN = code.ventN,
        fatigue = round(m.fatigue), compFatigue = code.team[code.comp] and round(code.team[code.comp].fatigue) or 0,
        pads = code.pads, mode = code.mode, canManual = canManual(src), canAed = canAed(src),
        defib = code.defib or false, energy = code.energy, energies = d.energies, aedEnergies = d.aedEnergies,
        advice = code.advice, shocks = code.shocks, lastEnergy = code.lastEnergy,
        adrenaline = {
            n = code.adrenaline.n, since = adSince, due = adDue, dueIn = (adLast and math.max(0, (ad.due or 240) - adSince)) or nil,
            gap = ad.minGap or 150, enabled = ad.enabled ~= false and NZA.Staff.Can(src, ad.perm or 'meds'),
            have = m.adCount or 0,
            access = (p.devices and (p.devices.iv or p.devices.port)) and true or false, needAccess = ad.needAccess == true,
        },
        bvm = m.bvm, breather = breather(code) == src, breathsLeft = code.breathsLeft,
        continuous = code.continuous, intubated = (p.devices and p.devices.intubated) and true or false,
        causes = Logic.Causes(p, code),
        log = { table.unpack(code.log, math.max(1, #code.log - 7), #code.log) },
        codeTime = os.time() - code.started, arrestTime = os.time() - (p.arrestAt or code.arrestAt),
        easy = m.easy == true, rosc = code.rosc ~= nil, maxTeam = cfg().maxTeam or 2, bed = bedLike(p),
    }
end

local function push(code, p)
    p = p or P.Get(code.pid)
    if not p then return end
    code.dirty = false
    for s in pairs(code.team) do
        TriggerClientEvent('nza:cpr:state', s, view(code, s, p))
    end
end
C.Push = push

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT POSE (player patients animate themselves; NPCs are animated by the compressor)
-- ════════════════════════════════════════════════════════════════════════

local function pose(code, p, on, mode)
    if p.kind ~= 'player' or not p.src then return end
    if on and (bedLike(p) or cfg().Anim and cfg().Anim.patientPose == false) then
        if code.poseSent and code.poseSent ~= 'off' then on = false else return end
    end
    local key = on and (mode or 'idle') or 'off'
    local rate = code.rate > 0 and round(code.rate / 5) * 5 or 0
    if code.poseSent == key and code.poseRate == rate and on then return end
    code.poseSent, code.poseRate = key, rate
    TriggerClientEvent('nza:cpr:pose', p.src, { on = on, origin = code.origin, mode = mode or 'idle', rate = rate, medic = code.comp })
end

-- ════════════════════════════════════════════════════════════════════════
-- END / LEAVE
-- ════════════════════════════════════════════════════════════════════════

local function summary(code, p, reason)
    local score, parts = Logic.Score(code)
    local easyAll = true
    for _, m in pairs(code.team) do if not m.easy then easyAll = false end end
    if easyAll and next(code.team) then score = clamp((Config.EasyMode or {}).score or 78, 0, 100) end
    return {
        reason = reason, rosc = code.rosc ~= nil, duration = os.time() - code.started,
        compressions = code.total, cycles = code.sets, shocks = code.shocks, adrenaline = code.adrenaline.n,
        score = score, grade = U.Grade(score), parts = parts, rhythmStart = code.rhythmStart,
        rhythmEnd = p and rhythmOf(p) or nil, name = p and p.name or nil, easy = easyAll,
    }
end

local function endCode(code, reason)
    if codes[code.pid] ~= code then return end
    codes[code.pid] = nil
    local p = P.Get(code.pid)
    local sum = summary(code, p, reason)
    for s in pairs(code.team) do
        member[s] = nil
        TriggerClientEvent('nza:cpr:ended', s, sum)
    end
    if p then
        setBag(p, nil)
        pose(code, p, false)
        if cfg().record ~= false and p.kind == 'player' and NZA.Records and NZA.Records.Add then
            local outcome = code.rosc and L('rec_rosc') or L('rec_' .. tostring(reason))
            pcall(NZA.Records.Add, p, {
                medic = code.starter, action = 'cpr',
                summary = L('rec_summary', U.formatTime(sum.duration), sum.compressions, sum.shocks, sum.adrenaline,
                    sum.parts.quality, sum.parts.ccf, outcome),
            })
        end
        NZA.Bus.Emit('cpr:ended', p, code, reason, sum)
    end
end
C.End = function(pid, reason)
    local code = codes[pid]
    if code then endCode(code, reason or 'stopped') end
end

local function removeMember(code, src, reason)
    local m = code.team[src]
    if not m then return end
    -- the last one out ends the code (everyone gets the full, graded summary)
    local n = 0
    for _ in pairs(code.team) do n = n + 1 end
    if n <= 1 then return endCode(code, reason == 'left' and 'stopped' or reason) end
    local p = P.Get(code.pid)
    local sum = summary(code, p, reason)
    sum.left = true
    code.team[src] = nil
    member[src] = nil
    TriggerClientEvent('nza:cpr:ended', src, sum)
    if code.comp == src then
        if code.air and code.team[code.air] then
            code.comp, code.air = code.air, nil
            local nm = code.team[code.comp]
            nm.compSince = nowMs()
            emit(code, { kind = 'promoted', name = m.name }, code.comp)
            if p then setBag(p, code.comp); code.poseSent = nil end
        else
            return endCode(code, reason == 'left' and 'stopped' or reason)
        end
    elseif code.air == src then
        code.air = nil
        emit(code, { kind = 'partner_left', name = m.name })
    end
    if p then log(code, 'left', nil, m.name) end
    dirty(code)
end

local function leaveAll(src, reason)
    local code = memberCode(src)
    if code then removeMember(code, src, reason or 'left') end
end
C.Leave = leaveAll

-- ════════════════════════════════════════════════════════════════════════
-- START / JOIN
-- ════════════════════════════════════════════════════════════════════════

local function newMember(src, p)
    return {
        src = src, name = Core.Name(src) or ('#' .. src), joined = os.time(),
        easy = NZA.Staff.Easy(src, cfg().perm or 'cpr') == true,
        bvm = hasItem(src, 'bvm'), fatigue = 0, compTime = 0, lastReport = nowMs(), lastBreath = 0,
        adCount = countItem(src, 'adrenaline'),
    }
end

local function startCode(src, p, origin)
    local now = nowMs()
    local arrestAt = p.arrestAt or os.time()
    -- time without CPR before we started (no-flow): only what was not covered by someone's compressions
    local lastFlow = arrestAt
    if p.lastCpr and p.lastCpr > lastFlow then lastFlow = p.lastCpr end
    local noFlow = math.max(0, os.time() - lastFlow)
    local code = {
        id = U.uid('code'), pid = p.pid, starter = src, started = os.time(), startedMs = now,
        kind = p.state == 'arrest' and 'arrest' or 'resp', arrestAt = arrestAt, noFlow = p.state == 'arrest' and noFlow or 0,
        team = {}, comp = src, air = nil,
        phase = 'compress', phaseAt = now, origin = origin,
        set = 0, total = 0, sets = 0, cycleNo = 1, cycleStart = now, checks = 0,
        lastComp = 0, quality = 0, qSum = 0, qN = 0, rate = 0, depth = 0, recoil = 0,
        handsOn = 0, elapsed = 0,
        vent = 0, ventN = 0, breathsLeft = 0,
        pads = false, mode = canManual(src) and 'manual' or 'aed', energy = sub('Defib').energy or 200,
        charged = false, chargeEnd = 0, chargedAt = 0, advice = nil, analyseEnd = 0, motion = false,
        shocks = 0, lastShockMs = 0, lastEnergy = nil, handsAt = 0,
        adrenaline = { n = 0, last = nil },
        rhythmStart = rhythmOf(p), rescuerShocks = 0, badShocks = 0, longPauses = 0, motionAborts = 0,
        log = {}, continuous = continuous(p),
    }
    code.needAdrenaline = p.state == 'arrest' and not SHOCKABLE[rhythmOf(p)]
    code.team[src] = newMember(src, p)
    code.team[src].compSince = now
    code.defib = codeDefib(code, p)
    codes[p.pid] = code
    member[src] = p.pid
    setBag(p, src)
    log(code, 'start', 'teal', code.team[src].name)
    if code.continuous then log(code, 'continuous', nil) end
    pose(code, p, true, 'idle')
    NZA.Bus.Emit('cpr:started', p, code)
    return code
end

local function validOrigin(o, p)
    if type(o) ~= 'table' then return nil end
    local x, y, z, h = tonumber(o.x), tonumber(o.y), tonumber(o.z), tonumber(o.h)
    if not (x and y and z and h) then return nil end
    local pc = Core.PatientCoords(p)
    if pc and #(vector3(x, y, z) - pc) > 3.0 then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0, h = (h % 360) + 0.0 }
end

lib.callback.register('nza:cpr:start', function(src, target, opts)
    if not Core.Rate('nza:cpr:start', src, 2, 1500) then return fail('rate') end
    opts = type(opts) == 'table' and opts or {}
    if not NZA.Staff.Can(src, cfg().perm or 'cpr') then return fail('perm') end
    local p = P.Resolve(target)
    if not p then return fail('no_patient') end
    if p.kind == 'player' and p.src == src then return fail('self') end
    if Core.DistanceTo(src, p) > (cfg().maxDist or 3.0) + 1.0 then return fail('too_far') end
    local own = P.GetBySource(src)
    if own and own.state ~= 'alive' then return fail('down') end

    local existing = codes[p.pid]
    if existing then
        if existing.team[src] then
            local pp = P.Get(existing.pid)
            return { ok = true, joined = false, view = view(existing, src, pp), resumed = true }
        end
        local n = 0
        for _ in pairs(existing.team) do n = n + 1 end
        if n >= (cfg().maxTeam or 2) or existing.air then return fail('full') end
        leaveAll(src, 'replaced')
        existing.team[src] = newMember(src, p)
        existing.air = src
        existing.defib = existing.defib or codeDefib(existing, p)
        member[src] = p.pid
        log(existing, 'joined', 'teal', existing.team[src].name)
        emit(existing, { kind = 'joined', name = existing.team[src].name }, existing.comp)
        dirty(existing)
        push(existing, p)
        return { ok = true, joined = true, view = view(existing, src, p), origin = existing.origin }
    end

    local ok, why = eligible(p)
    if not ok then return fail(why) end
    if patientBusy(p) then return fail('busy') end
    local origin = validOrigin(opts.origin, p)
    if not origin then
        local c = Core.PatientCoords(p) or vector3(0.0, 0.0, 0.0)
        origin = { x = c.x, y = c.y, z = c.z, h = 0.0 }
    end
    leaveAll(src, 'replaced')
    local code = startCode(src, p, origin)
    push(code, p)
    return { ok = true, joined = false, view = view(code, src, p), origin = code.origin }
end)

-- ════════════════════════════════════════════════════════════════════════
-- COMPRESSIONS & BREATHS
-- ════════════════════════════════════════════════════════════════════════

local function startBreaths(code)
    if code.continuous then code.set = 0; code.sets = code.sets + 1; return end
    code.phase = 'breaths'
    code.phaseAt = nowMs()
    code.breathsLeft = sub('Breaths').perSet or 2
    local b = breather(code)
    if b and code.team[b] then code.team[b].bvm = hasItem(b, 'bvm') end
    emit(code, { kind = 'breaths', breather = b, bvm = b and code.team[b] and code.team[b].bvm })
    dirty(code)
end

local function endBreaths(code, missed)
    if missed and missed > 0 then
        for _ = 1, missed do
            code.vent = code.vent + (0 - code.vent) * 0.35
            code.ventN = code.ventN + 1
        end
        emit(code, { kind = 'breaths_missed', n = missed })
    end
    code.phase = 'compress'
    code.phaseAt = nowMs()
    code.set = 0
    code.sets = code.sets + 1
    code.breathsLeft = 0
    dirty(code)
end

local COMPRESS_OK = { compress = true, advised = true, charging = true, charged = true }

RegisterNetEvent('nza:cpr:cycle', function(d)
    local src = source
    if not Core.Rate('nza:cpr:cycle', src, 8, 1000) then return end
    local code, m = memberCode(src)
    if not code or type(d) ~= 'table' or src ~= code.comp then return end
    local now = nowMs()
    local dt = now - (m.lastReport or now)
    m.lastReport = now
    local n = math.floor(clamp(d.n, 0, 12))
    if n <= 0 then return end
    local maxN = math.floor(math.max(0, dt) / 1000 * 2.7) + 2
    if n > maxN then n = maxN end
    if code.phase == 'analyse' then
        if not code.motion then emit(code, { kind = 'motion' }) end
        code.motion = true
        return
    end
    if code.phase == 'charged' then code.handsAt = now end
    if not COMPRESS_OK[code.phase] then return end

    local q = Logic.Compression(d, m.fatigue, m.easy)
    local rate = clamp(d.rate, 0, 220)
    if m.easy then rate = sub('Compressions').target or 110 end
    if code.qN == 0 then code.quality = q else code.quality = code.quality + (q - code.quality) * math.min(1, n / 20) end
    code.qSum = code.qSum + q * n
    code.qN = code.qN + n
    code.rate = code.rate > 0 and (code.rate + (rate - code.rate) * 0.5) or rate
    local depth = m.easy and q or clamp(d.depth, 0, 100) * (1 - clamp(m.fatigue, 0, 100) / 100)
    code.depth = code.depth > 0 and (code.depth + (depth - code.depth) * 0.4) or depth
    local recoil = m.easy and q or clamp(d.recoil, 0, 100)
    code.recoil = code.recoil > 0 and (code.recoil + (recoil - code.recoil) * 0.4) or recoil
    code.set = code.set + n
    code.total = code.total + n
    code.lastComp = now
    if code.phase == 'compress' then
        local per = sub('Compressions').perSet or 30
        if code.set >= per or (d.done == true and code.set >= per - 4) then startBreaths(code) end
    else
        code.set = math.min(code.set, (sub('Compressions').perSet or 30))   -- breaths wait until after the shock
    end
    dirty(code)
end)

RegisterNetEvent('nza:cpr:breath', function(d)
    local src = source
    if not Core.Rate('nza:cpr:breath', src, 4, 1000) then return end
    local code, m = memberCode(src)
    if not code or type(d) ~= 'table' or code.phase ~= 'breaths' or breather(code) ~= src then return end
    local now = nowMs()
    local hold = clamp(d.hold, 0, 5)
    if now - (m.lastBreath or 0) < math.max(450, hold * 1000 - 300) then return end
    m.lastBreath = now
    local bvm = m.bvm == true
    if not bvm and sub('Breaths').mouthToMouth == false then return end
    local q = Logic.Breath(hold, bvm, m.easy)
    local p = P.Get(code.pid)
    -- a tube in the oesophagus sends every breath into the stomach (intubation module's meta.tube)
    if p and p.devices and p.devices.intubated and type(p.meta) == 'table' and type(p.meta.tube) == 'table'
        and p.meta.tube.placed == 'oesophagus' then
        q = 0
    end
    code.vent = code.ventN == 0 and q or (code.vent + (q - code.vent) * 0.35)
    code.ventN = code.ventN + 1
    code.breathsLeft = math.max(0, code.breathsLeft - 1)
    -- good breaths push water / smoke out of the lungs
    if p and q >= 50 and p.conditions and p.conditions.hypoxia then
        local hx = U.deepcopy(p.conditions.hypoxia)
        if hx.water then hx.water = math.max(0, (tonumber(hx.water) or 0) - 3 * q / 100) end
        if hx.smoke then hx.smoke = math.max(0, (tonumber(hx.smoke) or 0) - 4 * q / 100) end
        P.SetCondition(p.pid, 'hypoxia', hx)
    end
    emit(code, { kind = 'breath', q = round(q), left = code.breathsLeft, bvm = bvm })
    if code.breathsLeft <= 0 then endBreaths(code, 0) else dirty(code) end
end)

RegisterNetEvent('nza:cpr:hands', function()
    local src = source
    if not Core.Rate('nza:cpr:hands', src, 6, 1000) then return end
    local code = memberCode(src)
    if not code or src ~= code.comp then return end
    if code.phase == 'charged' then code.handsAt = nowMs() end
end)

RegisterNetEvent('nza:cpr:leave', function()
    local src = source
    leaveAll(src, 'left')
end)

-- ════════════════════════════════════════════════════════════════════════
-- DEFIBRILLATOR & DRUGS
-- ════════════════════════════════════════════════════════════════════════

local function action(name, fn)
    lib.callback.register('nza:cpr:' .. name, function(src, data)
        if not Core.Rate('nza:cpr:act', src, 6, 1000) then return fail('rate') end
        local code, m = memberCode(src)
        if not code then return fail('no_code') end
        local p = P.Get(code.pid)
        if not p then return fail('no_patient') end
        if Core.DistanceTo(src, p) > (cfg().maxDist or 3.0) + 2.0 then return fail('too_far') end
        local res = fn(src, code, m, p, type(data) == 'table' and data or {})
        if code.dirty and codes[code.pid] == code then push(code, p) end
        return res
    end)
end

local function doRosc(code, p, how)
    if p.state == 'arrest' then
        local ok = P.Revive(p.pid, { rosc = true, reason = 'cpr' })
        if not ok then return false end
    end
    code.phase = 'rosc'
    code.phaseAt = nowMs()
    code.rosc = os.time()
    code.charged = false
    code.advice = nil
    log(code, 'rosc', 'teal')
    emit(code, { kind = 'rosc', how = how, name = p.name })
    NZA.Bus.Emit('cpr:rosc', p, code)
    local amount = tonumber(sub('Billing').rosc) or 0
    if amount > 0 and p.kind == 'player' and NZA.Billing and type(NZA.Billing.Charge) == 'function' then
        local ok, err = pcall(NZA.Billing.Charge, p.src or p.identifier, amount, L('bill_rosc'), { medic = code.comp, kind = 'cpr' })
        if not ok then NZA.Debug('cpr billing failed', err) end
    end
    dirty(code)
    return true
end

action('pads', function(src, code, m, p)
    if code.pads then return { ok = true } end
    local s = defibSource(src, p) or codeDefib(code, p)
    if not s then return fail('no_defib') end
    code.defib = s
    code.pads = true
    log(code, 'pads', nil, m.name)
    dirty(code)
    return { ok = true }
end)

action('mode', function(src, code, m, p, d)
    local mode = d.mode == 'manual' and 'manual' or 'aed'
    if mode == 'manual' and not canManual(src) then return fail('perm_defib') end
    if code.phase == 'charging' or code.phase == 'charged' then return fail('busy_charge') end
    code.mode = mode
    dirty(code)
    return { ok = true, mode = mode }
end)

action('energy', function(src, code, m, p, d)
    if code.mode ~= 'manual' then return fail('aed_energy') end
    if not canManual(src) then return fail('perm_defib') end
    local e = math.floor(tonumber(d.energy) or 0)
    local okE = false
    for _, v in ipairs(sub('Defib').energies or {}) do if v == e then okE = true end end
    if not okE then return fail('bad_energy') end
    if code.energy == e then return { ok = true, energy = e } end
    code.energy = e
    if code.phase == 'charging' or code.phase == 'charged' then
        code.phase = 'compress'
        code.charged = false
        log(code, 'disarm', nil)
        emit(code, { kind = 'disarmed', why = 'energy' })
    end
    dirty(code)
    return { ok = true, energy = e }
end)

action('analyse', function(src, code, m, p)
    if not code.pads then return fail('no_pads') end
    if code.phase == 'analyse' then return { ok = true } end
    if code.phase == 'breaths' or code.phase == 'charging' or code.phase == 'charged' or code.phase == 'rosc' then
        return fail('phase_' .. code.phase)
    end
    if not (canAed(src) or canManual(src)) then return fail('perm_defib') end
    code.phase = 'analyse'
    code.phaseAt = nowMs()
    code.analyseEnd = code.phaseAt + (sub('Defib').analyseTime or 4) * 1000
    code.motion = false
    code.advice = nil
    log(code, 'analyse', nil)
    emit(code, { kind = 'analysing' })
    dirty(code)
    return { ok = true }
end)

local function chargeTime(energy)
    return (sub('Defib').chargeTime or 2.5) * ((tonumber(energy) or 200) / 200) ^ 0.6
end

action('charge', function(src, code, m, p, d)
    if not code.pads then return fail('no_pads') end
    if code.phase == 'charging' or code.phase == 'charged' then return { ok = true } end
    if code.phase == 'analyse' or code.phase == 'rosc' or code.phase == 'breaths' then return fail('phase_' .. code.phase) end
    if not defibSource(src, p) and not codeDefib(code, p) then return fail('no_defib') end
    if code.mode == 'manual' then
        if not canManual(src) then return fail('perm_defib') end
    else
        if not canAed(src) then return fail('perm_defib') end
        if code.advice ~= 'shock' then return fail('not_advised') end
        local list = sub('Defib').aedEnergies or { 200, 300, 360 }
        code.energy = list[math.min(#list, code.shocks + 1)] or 200
    end
    code.phase = 'charging'
    code.phaseAt = nowMs()
    code.chargeEnd = code.phaseAt + math.floor(chargeTime(code.energy) * 1000)
    log(code, 'charge', nil, code.energy)
    emit(code, { kind = 'charging', energy = code.energy, ms = code.chargeEnd - code.phaseAt })
    dirty(code)
    return { ok = true, energy = code.energy }
end)

action('disarm', function(src, code)
    if code.phase ~= 'charging' and code.phase ~= 'charged' then return { ok = true } end
    code.phase = 'compress'
    code.phaseAt = nowMs()
    code.charged = false
    log(code, 'disarm', nil)
    emit(code, { kind = 'disarmed', why = 'manual' })
    dirty(code)
    return { ok = true }
end)

action('shock', function(src, code, m, p)
    if code.phase ~= 'charged' then return fail('not_charged') end
    if code.mode == 'manual' and not canManual(src) then return fail('perm_defib') end
    if code.mode ~= 'manual' and (not canAed(src) or code.advice ~= 'shock') then return fail('not_advised') end
    if not defibSource(src, p) and not codeDefib(code, p) then
        code.phase = 'compress'
        dirty(code)
        return fail('no_defib')
    end
    local now = nowMs()
    local d = sub('Defib')
    local touching = code.handsAt > 0 and (now - code.handsAt) <= (d.clearWindow or 0.9) * 1000
    local energy = code.energy
    code.shocks = code.shocks + 1
    code.lastEnergy = energy
    code.lastShockMs = now
    if code.lastComp > 0 and now - code.lastComp > 10000 then code.longPauses = code.longPauses + 1 end
    code.phase = 'compress'
    code.phaseAt = now
    code.set = 0
    code.charged = false
    code.advice = nil
    code.handsAt = 0

    if touching then
        code.rescuerShocks = code.rescuerShocks + 1
        local rs = d.rescuerShock or {}
        TriggerClientEvent('nza:cpr:event', code.comp, { kind = 'zapped', ragdoll = rs.ragdoll or 1800, health = rs.health or 0 })
        log(code, 'zapped', 'red', code.team[code.comp] and code.team[code.comp].name or '')
    end

    local result = 'none'
    local rhythm = rhythmOf(p)
    if p.state ~= 'arrest' then
        -- shocking a patient with a pulse can throw them into VF
        result = 'no_effect'
        code.badShocks = code.badShocks + 1
        if p.state == 'wounded' and math.random() < 0.35 then
            P.SetState(p.pid, 'arrest', 'electrocution')
            Logic.SetRhythm(p, 'vf')
            code.kind = 'arrest'
            code.rosc = nil
            result = 'induced'
        end
    elseif not SHOCKABLE[rhythm] then
        result = 'no_effect'
        code.badShocks = code.badShocks + 1
    else
        local chance = Logic.Chance(code, p, 'shock', { energy = energy, touching = touching })
        NZA.Debug(('cpr: shock %dJ on %s, chance %.2f'):format(energy, rhythm, chance))
        if math.random() < chance then
            result = 'rosc'
        else
            local new = Logic.AfterShock(code, p)
            if new then result = 'changed' end
        end
        code.needAdrenaline = code.needAdrenaline or code.shocks >= 2
    end
    log(code, 'shock', 'amber', energy, code.shocks)
    emit(code, { kind = 'shock', energy = energy, n = code.shocks, result = result, touching = touching })
    NZA.Bus.Emit('cpr:shock', p, src, energy, result)
    local price = tonumber(sub('Billing').shock) or 0
    if price > 0 and p.kind == 'player' and NZA.Billing and type(NZA.Billing.Charge) == 'function' then
        pcall(NZA.Billing.Charge, p.src or p.identifier, price, L('bill_shock'), { medic = src, kind = 'cpr' })
    end
    if result == 'rosc' then doRosc(code, p, 'shock') end
    dirty(code)
    return { ok = true, result = result, energy = energy, touching = touching }
end)

action('swap', function(src, code)
    if not code.air or not code.team[code.air] then return fail('no_partner') end
    if code.phase == 'charged' then return fail('busy_charge') end
    local old = code.comp
    code.comp, code.air = code.air, code.comp
    code.team[code.comp].compSince = nowMs()
    code.team[code.comp].lastReport = nowMs()
    code.team[old].compTime = 0
    local p = P.Get(code.pid)
    if p then setBag(p, code.comp) end
    code.poseSent = nil
    log(code, 'swap', 'teal', code.team[code.comp].name)
    emit(code, { kind = 'swap', comp = code.comp, compName = code.team[code.comp].name })
    dirty(code)
    return { ok = true }
end)

action('pulse', function(src, code, m, p)
    local pulse = p.state ~= 'arrest' and p.state ~= 'dead'
    local v = p.vitals or {}
    return { ok = true, pulse = pulse, rate = pulse and round(v.hr) or 0, weak = pulse and (tonumber(v.sys) or 0) < 80 }
end)

action('adrenaline', function(src, code, m, p)
    local ad = sub('Adrenaline')
    if ad.enabled == false then return fail('disabled') end
    local ok, res = NZA.Treat.Run(src, 'cpr_adrenaline', p.pid, {})
    if not ok then
        res = type(res) == 'table' and res or {}
        return { ok = false, err = res.err or 'failed', msg = res.msg or L('err_failed') }
    end
    return { ok = true, msg = res and res.msg }
end)

NZA.Treat.Register('cpr_adrenaline', {
    perm = sub('Adrenaline').perm or 'meds',
    self = false,
    states = { arrest = true, wounded = true },
    maxDist = (cfg().maxDist or 3.0),
    cooldown = 800,
    items = function()
        local name = item('adrenaline')
        return name and { [name] = 1 } or {}
    end,
    handler = function(src, p, payload)
        local code = codes[p.pid]
        if not code or not code.team[src] then return false, { err = 'no_code', msg = L('err_no_code') } end
        local ad = sub('Adrenaline')
        local last = code.adrenaline.last
        if last and os.time() - last < (ad.minGap or 150) then
            local wait = (ad.minGap or 150) - (os.time() - last)
            return false, { err = 'too_soon', msg = L('err_too_soon', U.formatTime(wait)) }
        end
        if ad.needAccess and not (p.devices and (p.devices.iv or p.devices.port)) then
            return false, { err = 'no_access', msg = L('err_no_access') }
        end
        local ok, info = P.GiveMed(p.pid, 'adrenaline', { dose = 1, route = 'iv', by = src })
        if not ok then return false, { err = 'failed', msg = (info and info.msg) or L('err_failed') } end
        code.adrenaline.n = code.adrenaline.n + 1
        code.adrenaline.last = os.time()
        if code.team[src] then code.team[src].adCount = math.max(0, (code.team[src].adCount or 1) - 1) end
        log(code, 'adrenaline', 'teal', code.adrenaline.n)
        emit(code, { kind = 'adrenaline', n = code.adrenaline.n })
        dirty(code)
        return true, { msg = L('adrenaline_given', code.adrenaline.n), record = L('rec_adrenaline') }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- ANALYSIS RESULT
-- ════════════════════════════════════════════════════════════════════════

local function resolveAnalysis(code, p, now)
    if code.motion then
        code.motionAborts = code.motionAborts + 1
        code.phase = 'compress'
        code.phaseAt = now
        code.advice = 'motion'
        log(code, 'motion', 'red')
        emit(code, { kind = 'advice', advice = 'motion' })
        return
    end
    local cyc = sub('Cycle')
    local elapsed = (now - code.cycleStart) / 1000
    local isCheck = elapsed >= (cyc.length or 120) - (cyc.checkGrace or 20)
    if isCheck then
        code.cycleNo = code.cycleNo + 1
        code.cycleStart = now
        code.checks = code.checks + 1
        if p.state == 'arrest' then
            local res = Logic.Evolve(code, p)
            if res == 'rosc' then
                code.advice = 'rosc'
                emit(code, { kind = 'advice', advice = 'organised' })
                doRosc(code, p, 'check')
                return
            end
        end
    end
    local rhythm = rhythmOf(p)
    code.phase = 'compress'
    code.phaseAt = now
    if p.state == 'arrest' and SHOCKABLE[rhythm] then
        code.advice = 'shock'
        code.phase = 'advised'
        if code.mode ~= 'manual' then
            local list = sub('Defib').aedEnergies or { 200, 300, 360 }
            code.energy = list[math.min(#list, code.shocks + 1)] or 200
        end
        log(code, 'advised', 'amber', NZA.L('cpr.rhythm_' .. rhythm))
    else
        code.advice = 'noshock'
        if p.state == 'arrest' then code.needAdrenaline = true end
        log(code, 'noshock', nil, NZA.L('cpr.rhythm_' .. rhythm))
    end
    emit(code, { kind = 'advice', advice = code.advice, rhythm = rhythm, check = isCheck, pulse = p.state ~= 'arrest' })
end

-- ════════════════════════════════════════════════════════════════════════
-- TICK
-- ════════════════════════════════════════════════════════════════════════

local function validateMembers(code, p)
    for s, m in pairs(code.team) do
        local reason
        if not Core.Online(s) then
            reason = 'offline'
        else
            local own = P.GetBySource(s)
            if own and own.state ~= 'alive' then reason = 'down'
            elseif Core.DistanceTo(s, p) > (cfg().maxDist or 3.0) + 2.0 then reason = 'far'
            elseif not NZA.Staff.Can(s, cfg().perm or 'cpr') then reason = 'perm' end
        end
        if reason then
            removeMember(code, s, reason)
            if codes[code.pid] ~= code then return false end
        end
    end
    return next(code.team) ~= nil
end

local function second(code, p, now)
    code.elapsed = code.elapsed + 1
    local compressing = code.lastComp > 0 and now - code.lastComp <= 1500 and COMPRESS_OK[code.phase]
    if compressing then code.handsOn = code.handsOn + 1 end

    -- fatigue (server side, per rescuer)
    local fc = sub('Compressions').fatigue or {}
    for s, m in pairs(code.team) do
        if fc.enabled == false then
            m.fatigue = 0
        elseif s == code.comp and compressing then
            m.compTime = m.compTime + 1
            if m.compTime > (fc.after or 120) then
                m.fatigue = math.min(fc.max or 40, m.fatigue + (fc.perMinute or 14) / 60)
            end
        else
            m.fatigue = math.max(0, m.fatigue - (fc.recover or 3))
            if s ~= code.comp then m.compTime = math.max(0, m.compTime - 2) end
        end
    end

    -- keep the arrest → death timer paused while CPR (or a planned pause) is going on
    local planned = (code.phase == 'breaths' and now - code.phaseAt <= (sub('Breaths').timeout or 10) * 1000)
        or code.phase == 'analyse' or code.phase == 'charging'
        or (code.phase == 'charged' and now - code.chargedAt <= 10000)
        or (code.lastShockMs > 0 and now - code.lastShockMs <= 3000)
    if compressing or planned then P.Cpr(p.pid, code.comp, math.max(10, code.quality)) end

    -- patient pose (players animate themselves)
    if code.phase ~= 'rosc' then pose(code, p, true, compressing and 'compress' or 'idle') end

    -- inventory-backed numbers are refreshed every few seconds, not on every push
    if code.elapsed % 5 == 1 then
        for s, m in pairs(code.team) do m.adCount = countItem(s, 'adrenaline') end
        code.defib = (code.pads and code.defib) or codeDefib(code, p)
    end
    dirty(code)   -- the device timers move every second
end

local function step(code, now)
    local p = P.Get(code.pid)
    if not p then return endCode(code, 'gone') end
    if p.state == 'dead' then return endCode(code, 'death') end
    if p.state == 'alive' then return endCode(code, code.rosc and 'rosc' or 'revived') end

    code.tickAcc = (code.tickAcc or 0) + TICK
    if code.tickAcc >= 1000 then
        code.tickAcc = code.tickAcc - 1000
        if not validateMembers(code, p) then return end
        code.continuous = continuous(p)
        second(code, p, now)
    end

    -- a respiratory code (wounded, unresponsive, not breathing) whose heart stopped becomes a cardiac arrest
    if p.state == 'arrest' and code.kind ~= 'arrest' and code.phase ~= 'rosc' then
        code.kind = 'arrest'
        code.arrestAt = p.arrestAt or os.time()
        code.needAdrenaline = not SHOCKABLE[rhythmOf(p)]
        log(code, 'arrested', 'red')
        emit(code, { kind = 'arrested', rhythm = code.pads and rhythmOf(p) or nil })
        dirty(code)
    end
    -- ...and one whose patient breathes again on their own is over
    if code.kind == 'resp' and p.state == 'wounded' then
        if notBreathing(p) then
            code.breathingSince = nil
        else
            code.breathingSince = code.breathingSince or now
            if now - code.breathingSince >= 4000 then return endCode(code, 'breathing') end
        end
    end

    -- state changes from outside (ROSC by someone else, re-arrest)
    if p.state == 'arrest' and code.phase == 'rosc' then
        code.phase = 'compress'
        code.phaseAt = now
        code.rosc = nil
        code.kind = 'arrest'
        code.arrestAt = p.arrestAt or os.time()
        log(code, 'rearrest', 'red')
        emit(code, { kind = 'rearrest' })
        dirty(code)
    elseif p.state == 'wounded' and code.kind == 'arrest' and code.phase ~= 'rosc' then
        doRosc(code, p, 'other')
    end

    local ph = code.phase
    if ph == 'analyse' and now >= code.analyseEnd then
        resolveAnalysis(code, p, now)
        dirty(code)
    elseif ph == 'charging' and now >= code.chargeEnd then
        code.phase = 'charged'
        code.charged = true
        code.chargedAt = now
        code.handsAt = 0
        emit(code, { kind = 'charged', energy = code.energy })
        dirty(code)
    elseif ph == 'charged' and now - code.chargedAt > (sub('Defib').chargedFor or 25) * 1000 then
        code.phase = 'compress'
        code.phaseAt = now
        code.charged = false
        log(code, 'disarm', nil)
        emit(code, { kind = 'disarmed', why = 'timeout' })
        dirty(code)
    elseif ph == 'breaths' and now - code.phaseAt > (sub('Breaths').timeout or 10) * 1000 then
        endBreaths(code, code.breathsLeft)
    elseif ph == 'rosc' and code.rosc and os.time() - code.rosc > (sub('Rosc').rearrestWatch or 45) then
        return endCode(code, 'rosc')
    end

    if code.dirty and codes[code.pid] == code then push(code, p) end
end

CreateThread(function()
    while true do
        Wait(TICK)
        if next(codes) then
            local now = nowMs()
            for _, code in pairs(codes) do
                local ok, err = pcall(step, code, now)
                if not ok then
                    NZA.Warn('cpr tick failed: ' .. tostring(err))
                    endCode(code, 'error')
                end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- BUS / LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('patient:death', function(p)
    local code = p and codes[p.pid]
    if code then endCode(code, 'death') end
end)

NZA.Bus.On('patient:removed', function(pid)
    local code = codes[pid]
    if code then endCode(code, 'gone') end
end)

NZA.Bus.On('player:unloaded', function(src)
    leaveAll(src, 'offline')
end)

AddEventHandler('playerDropped', function()
    leaveAll(source, 'offline')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, code in pairs(codes) do
        local p = P.Get(code.pid)
        if p then setBag(p, nil) end
    end
end)

-- defibrillator item: use it next to a patient in arrest to start (or open) CPR
CreateThread(function()
    Wait(2000)
    if cfg().usableDefib == false then return end
    local name = item('defibrillator')
    if not name then return end
    if not Core.Has('Inv.RegisterUsable') then
        NZA.Warn('cpr: Bridge.Inv.RegisterUsable is missing - the defibrillator item is not usable from the inventory')
        return
    end
    Core.B('Inv.RegisterUsable', name, function(src)
        src = tonumber(src)
        if not src or not Core.Rate('nza:cpr:use', src, 1, 2000) then return end
        if not NZA.Staff.Can(src, cfg().perm or 'cpr') then
            Core.Notify(src, L('err_perm'), 'error')
            return
        end
        TriggerClientEvent('nza:cpr:use', src)
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════

local function findCode(x)
    if type(x) == 'number' then
        local pid = member[x]
        if pid then return codes[pid] end
        local p = P.GetBySource(x)
        return p and codes[p.pid] or nil
    end
    if type(x) == 'string' then return codes[x] end
    return nil
end

function C.Get(x)
    local code = findCode(x)
    if not code then return nil end
    return { id = code.id, pid = code.pid, comp = code.comp, air = code.air, phase = code.phase, shocks = code.shocks,
        compressions = code.total, started = code.started, rosc = code.rosc ~= nil }
end

exports('IsInCpr', function(x) return findCode(x) ~= nil end)
exports('GetCode', function(x) return C.Get(x) end)
