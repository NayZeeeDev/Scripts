--[[
    NAYZEEE AMBULANCE - Airway (server): bag-valve mask ventilation and video laryngoscope
    intubation. Authoritative for everything that changes the patient.

    Procedures (NZA.Proc, §5.2)
      'intubate'   perm Config.Intubation.perm, items: Config.Items.intubation_kit (consumed
                   on Config.Intubation.consumeKit), the medic must also carry Config.Items.bvm
                   (never consumed). Patient wounded (AVPU in downAvpu) or in arrest, not
                   intubated yet. onStart sends the patient's airway anatomy (difficulty grade
                   from weights + face trauma / swelling / c-spine, soiling from face bleeding /
                   overdose vomit / drowning / gastric air, safe apnoea time, tube size and depth).
                   onFinish validates and clamps the client result, then:
                     trachea     devices.intubated = true, meta.tube = { placed = 'trachea', … },
                                 airway condition cleared, ventilated for ventilateAfter s
                     oesophagus  devices.intubated = true but meta.tube.placed = 'oesophagus':
                                 the patient desaturates (hypoxia condition grows every tick)
                     none        failed airway: no tube
                   + hypoxia insult from the lowest SpO2 of the attempt, bill, record.
      'bvm'        perm Config.Intubation.bvm.perm, carries Config.Items.bvm (never consumed).
                   A ventilation round: hypoxia relief × quality, ventilates a tube for
                   bvm.ventilate s, mask ventilation sets meta.bagUntil, stomach air is
                   remembered in meta.gastric (vomit risk on a later intubation).
    Treatments (NZA.Treat, §5.1)
      'tube_check'   capnography check of an existing tube (finds an oesophageal tube,
                     NZA.Findings 'tube_oesophageal' with cond 'hypoxia')
      'tube_adjust'  pull a too deep (mainstem) tube back to the right depth
      'extubate'     remove the tube
    Tick (Config.Intubation.tick s): correct tubes relieve hypoxia; mainstem / oesophageal tubes
      add hypoxia (tracked in conditions.hypoxia.tube); ventilation windows and the bed /
      ambulance-bay ventilator keep meta.ventilated + meta.ventRate in sync; expired
      meta.bagUntil is cleared. Patients back to 'alive' are extubated (extubateOnWake).
    Usable items: intubation_kit / bvm → client event 'nza:intubation:use' (mode).
    API:  NZA.Intubation.Tube(p) → meta.tube | nil      NZA.Intubation.Extubate(p, reason) → bool
          NZA.Intubation.Ventilate(p, seconds) → bool  (keep a tube ventilated, e.g. a ventilator)
    Exports: IsIntubated(src|pid) → bool, placed   VentilatePatient(src|pid, seconds) → bool
    Bus emitted: intubation:done (src, p, outcome), intubation:extubated (p, reason)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Intubation = NZA.Intubation or {}
local I = NZA.Intubation
local P = NZA.Patients
local Core = NZA.Core
local U = NZA.Util

local anatomy = {}       -- pid → { at, base } (the same patient keeps the same airway for a while)
local billed = {}        -- 'src:pid:kind' → os.time()
local checks = {}        -- pid → os.time() of the last tube check

local function cfg() return Config.Intubation or {} end
local function sub(k)
    local c = cfg()[k]
    return type(c) == 'table' and c or {}
end
local function L(key, ...) return NZA.L('intubation.' .. key, ...) end
local function num(v, d)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
    return v
end
local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end
local function rnd(a, b) return a + math.random() * (b - a) end
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function item(key) return Config.Items and Config.Items[key] or nil end
local function perm() return cfg().perm or 'airway' end
local function bvmPerm() return sub('bvm').perm or perm() end
local function fail(err, msg) return false, { err = err, msg = msg or L('err_' .. err) } end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT HELPERS
-- ════════════════════════════════════════════════════════════════════════

function I.Tube(p)
    if type(p) ~= 'table' then p = P.Resolve(p) end
    if not p or not (p.devices and p.devices.intubated) then return nil end
    local t = p.meta and p.meta.tube
    return type(t) == 'table' and t or { placed = 'trachea' }
end

local function faceTrauma(p)
    local sev, bleed = 0, 0
    for _, inj in pairs(p.injuries or {}) do
        if inj.region == 'face' or inj.region == 'neck' then
            sev = math.max(sev, num(inj.severity, 0))
            bleed = bleed + num(inj.bleed, 0)
        end
    end
    return sev, bleed
end

local function cspineRisk(p)
    if p.devices and p.devices.collar then return true end
    local sp = p.conditions and p.conditions.spinal
    if type(sp) == 'table' and (sp.level == 'cervical' or sp.region == 'neck') then return true end
    for _, inj in pairs(p.injuries or {}) do
        if inj.region == 'neck' and (inj.type == 'fracture' or num(inj.severity, 0) >= 4) then return true end
    end
    return false
end

local function gastricOf(p)
    local g = p.meta and p.meta.gastric
    if type(g) ~= 'table' then return 0 end
    if os.time() - num(g.at, 0) > num(sub('bvm').gastricKeep, 900) then return 0 end
    return clamp(num(g.v, 0), 0, 100)
end

local function isDown(p)
    if p.state == 'arrest' then return true end
    if p.state ~= 'wounded' then return false end
    if cfg().requireDown == false then return true end
    local avpu = (p.vitals and p.vitals.avpu) or 'A'
    local allowed = cfg().downAvpu or { P = true, U = true }
    return allowed[avpu] == true
end

local function apnoeic(p)
    if p.state == 'arrest' or p.state == 'dead' then return true end
    local v = p.vitals or {}
    return v.breathing == 'absent' or v.breathing == 'agonal' or num(v.rr, 14) < 8
end

local function vitalsOf(p)
    local v = p.vitals or {}
    return {
        hr = num(v.ecgRate, num(v.hr, 100)), sys = num(v.sys, 100), dia = num(v.dia, 60), map = num(v.map, 75),
        spo2 = num(v.spo2, 92), rr = num(v.rr, 0), temp = num(v.temp, 36.6), rhythm = v.rhythm or 'sinus',
        etco2 = num(v.etco2, 0),
    }
end

local function weighted(weights)
    local total = 0
    for i = 1, 4 do total = total + math.max(0, num(weights[i], 0)) end
    if total <= 0 then return 1 end
    local r = math.random() * total
    for i = 1, 4 do
        r = r - math.max(0, num(weights[i], 0))
        if r <= 0 then return i end
    end
    return 4
end

-- the airway this patient presents (stable per patient for difficulty.keep seconds)
local function buildAnatomy(p)
    local c, d, so = cfg(), sub('difficulty'), sub('soil')
    local now = os.time()
    local cached = anatomy[p.pid]
    local base
    if cached and now - cached.at < num(d.keep, 900) then
        base = cached.base
    else
        local ml = c.cuffMl or { 7.5, 10.0 }
        base = {
            grade = weighted(d.weights or { 55, 28, 12, 5 }),
            cuffMl = r1(rnd(num(ml[1], 7.5), num(ml[2], 10.0))),
            open = rnd(0.78, 1.02), gx = rnd(-0.08, 0.08), gy = rnd(-0.04, 0.04), aryt = rnd(0.9, 1.15),
            tongue = math.random(), ant = math.random(), soilRoll = math.random(), secretRoll = math.random(),
        }
        anatomy[p.pid] = { at = now, base = base }
    end

    local sev, bleed = faceTrauma(p)
    local aw = p.conditions and p.conditions.airway
    local cspine = cspineRisk(p)
    local grade = base.grade
    if sev >= 3 then grade = grade + num(d.faceTrauma, 1) end
    if type(aw) == 'table' and (aw.kind == 'swelling' or aw.kind == 'obstructed') then grade = grade + num(d.swelling, 1) end
    if cspine then grade = grade + num(d.cspine, 1) end
    grade = clamp(grade, 1, 4)

    -- soiling: what the suction step has to clear
    local soil, kind, refill = 0, 'blood', 0
    if sev >= 2 and bleed > 0 then
        soil = num(so.faceBleed, 0.55) * sev / 4
        refill = clamp(bleed / 40, 0.1, 1)
    end
    local hx = p.conditions and p.conditions.hypoxia
    if type(hx) == 'table' and num(hx.water, 0) > 0 and base.soilRoll < num(so.drowning, 0.8) then
        local s = clamp(0.35 + num(hx.water, 0) / 1500 * 0.55, 0.35, 0.9)
        if s > soil then soil, kind, refill = s, 'water', 0.15 end
    end
    local od = p.conditions and p.conditions.overdose
    if type(od) == 'table' and od.drug ~= 'stimulant' and base.soilRoll < num(so.overdose, 0.45) then
        if 0.55 > soil then soil, kind, refill = 0.55, 'vomit', 0.05 end
    end
    local gastric = gastricOf(p)
    if gastric >= num(so.gastricLimit, 60) and 0.65 > soil then soil, kind, refill = 0.65, 'vomit', 0.08 end
    if soil <= 0 and base.secretRoll < num(so.base, 0.12) then soil, kind, refill = 0.22, 'water', 0 end

    -- oxygen reserve: sick patients desaturate much faster
    local loss = P.Loss and P.Loss(p) or 0
    local sick = loss > 0.2 or p.state == 'arrest' or hx ~= nil or num((p.vitals or {}).spo2, 98) < 90
        or (type(aw) == 'table') or (type(od) == 'table' and num(od.amount, 0) > 40)
    local sa = sub('safeApnoea')
    local sex = p.sex == 'f' and 'f' or 'm'
    local tube = c.tube or {}
    local depth = c.depth or {}
    local t = p.meta and p.meta.tube
    return {
        grade = grade, soil = r1(clamp(soil, 0, 1) * 100) / 100, soilKind = kind, bleed = r1(refill * 100) / 100,
        cspine = cspine, tube = num(tube[sex], sex == 'f' and 7.0 or 7.5), depth = num(depth[sex], sex == 'f' and 21 or 23),
        cuffMl = base.cuffMl,
        open = r1(base.open * 100) / 100 * (grade >= 3 and 0.92 or 1),
        gx = base.gx, gy = base.gy, aryt = base.aryt,
        tongue = clamp(base.tongue * 0.6 + (grade - 1) * 0.15, 0, 1), ant = clamp(base.ant * 0.5 + (grade - 1) * 0.17, 0, 1),
        desat = r1(clamp(1 + loss * 2 + (p.state == 'arrest' and 0.2 or 0), 0.8, 2.2) * 100) / 100,
        safe = sick and num(sa.sick, 35) or num(sa.healthy, 75),
        apnoeic = apnoeic(p), gastric = gastric,
        intubated = (p.devices and p.devices.intubated) and true or false,
        misplaced = type(t) == 'table' and t.placed == 'oesophagus' or false,
    }
end

local function clientCfg()
    local c, b = cfg(), sub('bvm')
    return {
        attempts = math.floor(clamp(num(c.attempts, 3), 1, 6)), cadence = clamp(num(c.cadence, 5), 3, 10),
        squeeze = clamp(num(c.squeeze, 1), 0.5, 2), preoxBreaths = math.floor(clamp(num(c.preoxBreaths, 6), 3, 12)),
        abortSpo2 = num(c.abortSpo2, 90), crashSpo2 = num(c.crashSpo2, 75), cuffBand = c.cuffBand or { 20, 30 },
        breaths = math.floor(clamp(num(b.breaths, 8), 3, 20)),
    }
end

local function startData(p, mode)
    return {
        mode = mode,
        patient = { name = p.name, sex = p.sex, age = p.age, npc = p.kind == 'npc' },
        vitals = vitalsOf(p),
        anat = buildAnatomy(p),
        cfg = clientCfg(),
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- HYPOXIA (conditions.hypoxia = { cause, water (mL), smoke (0..100), tube = our share })
-- ════════════════════════════════════════════════════════════════════════

local function addHypoxia(p, amount, fromTube)
    amount = num(amount, 0)
    if amount <= 0 then return end
    local c = U.deepcopy(p.conditions.hypoxia or {})
    c.cause = c.cause or (fromTube and 'oesophageal' or 'apnoea')
    c.smoke = r1(clamp(num(c.smoke, 0) + amount, 0, 100))
    c.water = num(c.water, 0)
    if fromTube then c.tube = r1(clamp(num(c.tube, 0) + amount, 0, 100)) end
    P.SetCondition(p.pid, 'hypoxia', c)
end

-- ventilation clears hypoxia, but never the part an oesophageal tube is still causing
local function relieve(p, amount)
    amount = num(amount, 0)
    local hx = p.conditions.hypoxia
    if amount <= 0 or type(hx) ~= 'table' then return end
    local c = U.deepcopy(hx)
    local smoke = num(c.smoke, 0)
    local keep = (I.Tube(p) or {}).placed == 'oesophagus' and math.min(smoke, num(c.tube, 0)) or 0
    local take = math.min(math.max(0, smoke - keep), amount)
    c.smoke = r1(smoke - take)
    local left = amount - take
    if left > 0 and num(c.water, 0) > 0 then c.water = r1(math.max(0, num(c.water, 0) - left * 8)) end
    if num(c.smoke, 0) <= 0 and num(c.water, 0) <= 0 then
        P.SetCondition(p.pid, 'hypoxia', nil)
    else
        P.SetCondition(p.pid, 'hypoxia', c)
    end
end

-- the oesophageal tube is out: what it caused stays (it wears off), but it stops growing
local function dropTubeShare(p)
    local hx = p.conditions.hypoxia
    if type(hx) ~= 'table' or hx.tube == nil then return end
    local c = U.deepcopy(hx)
    c.tube = nil
    if c.cause == 'oesophageal' then c.cause = 'apnoea' end
    P.SetCondition(p.pid, 'hypoxia', c)
end

-- ════════════════════════════════════════════════════════════════════════
-- TUBE STATE
-- ════════════════════════════════════════════════════════════════════════

local function setVent(p, on)
    if on then
        if not p.meta.ventilated then P.SetMeta(p.pid, 'ventilated', true) end
        local rate = math.floor(clamp(num(cfg().ventRate, 12), 6, 30))
        if p.meta.ventRate ~= rate then P.SetMeta(p.pid, 'ventRate', rate) end
    elseif p.meta.ventilated then
        P.SetMeta(p.pid, 'ventilated', nil)
        P.SetMeta(p.pid, 'ventRate', nil)
    end
end

local function clearTube(p, reason)
    local had = p.meta and p.meta.tube ~= nil
    if p.meta.tube ~= nil then P.SetMeta(p.pid, 'tube', nil) end
    setVent(p, false)
    dropTubeShare(p)
    if had then NZA.Bus.Emit('intubation:extubated', p, reason or 'removed') end
end

function I.Extubate(p, reason)
    if type(p) ~= 'table' then p = P.Resolve(p) end
    if not p then return false end
    if p.devices and p.devices.intubated then P.SetDevice(p.pid, 'intubated', false) end
    clearTube(p, reason)
    return true
end

function I.Ventilate(p, seconds)
    if type(p) ~= 'table' then p = P.Resolve(p) end
    local t = p and I.Tube(p)
    if not t or t.placed ~= 'trachea' then return false end
    local tube = U.deepcopy(p.meta.tube or t)
    tube.ventUntil = math.max(num(tube.ventUntil, 0), os.time() + math.floor(num(seconds, 60)))
    P.SetMeta(p.pid, 'tube', tube)
    setVent(p, true)
    return true
end

local function onBedOrBay(p)
    local m = p.meta or {}
    return m.bed ~= nil or m.bay ~= nil or m.inBed == true
end

local function tickTube(p, tube, minutes, now)
    if p.state == 'dead' then return end
    local c = cfg()
    if tube.placed == 'oesophagus' then
        setVent(p, false)
        addHypoxia(p, num(c.misplacedRate, 22) * minutes, true)
        return
    end
    local vent = num(tube.ventUntil, 0) > now or (c.bedVentilator ~= false and onBedOrBay(p))
    setVent(p, vent)
    if tube.mainstem then addHypoxia(p, num(c.mainstemRate, 6) * minutes, false) end
    relieve(p, num(c.hypoxiaRelief, 18) * minutes * (vent and 1 or 0.5))
end

CreateThread(function()
    while true do
        local dt = clamp(num(cfg().tick, 5), 1, 60)
        Wait(math.floor(dt * 1000))
        local now = os.time()
        for _, p in pairs(P.All()) do
            local ok, err = pcall(function()
                local meta = p.meta or {}
                if p.devices and p.devices.intubated and type(meta.tube) == 'table' then
                    tickTube(p, meta.tube, dt / 60, now)
                elseif type(meta.tube) == 'table' and not (p.devices and p.devices.intubated) then
                    clearTube(p, 'removed')           -- healed / revived by something else
                end
                if meta.bagUntil and num(meta.bagUntil, 0) <= now then P.SetMeta(p.pid, 'bagUntil', nil) end
            end)
            if not ok then NZA.Warn('intubation tick failed: ' .. tostring(err)) end
        end
        for pid, a in pairs(anatomy) do
            if now - a.at > num(sub('difficulty').keep, 900) * 2 then anatomy[pid] = nil end
        end
    end
end)

NZA.Bus.On('state:changed', function(p, _, new)
    if new == 'alive' and cfg().extubateOnWake ~= false and p and p.devices and p.devices.intubated then
        I.Extubate(p, 'wake')
    end
end)

NZA.Bus.On('device:changed', function(p, name, value)
    if name == 'intubated' and not value and p and p.meta and p.meta.tube ~= nil then clearTube(p, 'removed') end
end)

NZA.Bus.On('patient:removed', function(pid)
    anatomy[pid] = nil
    checks[pid] = nil
end)

-- ════════════════════════════════════════════════════════════════════════
-- BILLING
-- ════════════════════════════════════════════════════════════════════════

local function bill(src, p, kind)
    local amount = num(sub('price')[kind], 0)
    if amount <= 0 or p.kind ~= 'player' then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local key = ('%s:%s:%s'):format(src, p.pid, kind)
    local now = os.time()
    if billed[key] and now - billed[key] < 300 then return end
    billed[key] = now
    local ok, err = pcall(NZA.Billing.Charge, p.src or p.identifier, amount, L('bill_' .. kind), { medic = src, kind = 'airway' })
    if not ok then NZA.Debug('intubation billing failed', err) end
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE: INTUBATE
-- ════════════════════════════════════════════════════════════════════════

local PLACED = { trachea = true, oesophagus = true, none = true }
local CL = { ['1'] = true, ['2a'] = true, ['2b'] = true, ['3'] = true, ['4'] = true }

-- the client result is a claim: keep what is plausible, clamp every number
local function sanitize(result, anat)
    local r = type(result) == 'table' and result or {}
    local out = {
        placed = PLACED[r.placed] and r.placed or 'none',
        failed = r.failed == true,
        depth = math.floor(clamp(num(r.depth, anat.depth), 0, 32) + 0.5),
        cuff = math.floor(clamp(num(r.cuff, 0), 0, 80) + 0.5),
        leak = r.leak == true,
        capno = r.capno == true,
        attempts = math.floor(clamp(num(r.attempts, 1), 1, num(cfg().attempts, 3))),
        lowSpo2 = math.floor(clamp(num(r.lowSpo2, 90), 35, 100)),
        cl = CL[tostring(r.cl)] and tostring(r.cl) or '4',
        teeth = math.floor(clamp(num(r.teeth, 0), 0, 20)),
        firstPass = r.firstPass == true,
        gastric = clamp(num(r.gastric, 0), 0, 100),
        detected = r.detected == true,
    }
    if out.failed then out.placed = 'none' end
    if out.placed == 'none' then out.depth, out.cuff = 0, 0 end
    out.mainstem = out.placed == 'trachea' and out.depth > anat.depth + 2
    return out
end

local function onStartIntubate(src, p, _, info)
    if not isDown(p) then return fail('not_down') end
    if p.devices and p.devices.intubated then return fail('intubated') end
    if cfg().requireBvm ~= false and item('bvm') then
        local ok = Core.CheckItems(src, { [item('bvm')] = 1 })
        if not ok then return false, { err = 'missing_item', msg = L('err_no_bvm') } end
    end
    local data = startData(p, 'intubate')
    data.easy = info and info.easy or nil
    return true, data
end

local function onFinishIntubate(src, p, s, result)
    local data = type(s.data) == 'table' and s.data or startData(p, 'intubate')
    local anat = data.anat or buildAnatomy(p)
    local r
    if result.easy then
        r = { placed = 'trachea', failed = false, depth = anat.depth, cuff = 25, leak = false, capno = true, attempts = 1,
            lowSpo2 = math.max(90, num((p.vitals or {}).spo2, 92)), cl = '2a', teeth = 0, firstPass = true, gastric = 0,
            detected = false, mainstem = false }
    else
        r = sanitize(result, anat)
    end

    local c = cfg()
    local score = result.score
    if r.placed == 'oesophagus' then score = math.min(score, 20) end
    if r.placed == 'none' then score = math.min(score, 15) end

    -- the attempt itself costs oxygen
    local insult = math.max(0, 90 - r.lowSpo2) * num(c.attemptInsult, 0.8)
    if insult > 0 then addHypoxia(p, insult, false) end
    if r.gastric > 0 then P.SetMeta(p.pid, 'gastric', { v = math.floor(r.gastric), at = os.time() }) end

    local outcome = { score = score, placed = r.placed, easy = result.easy }
    if r.placed ~= 'none' then
        local now = os.time()
        local tube = {
            placed = r.placed, size = anat.tube, depth = r.depth, expected = anat.depth, mainstem = r.mainstem or false,
            cuff = r.cuff, leak = r.leak, capno = r.capno, at = now, by = Core.Name and Core.Name(src) or nil,
            ventUntil = r.placed == 'trachea' and now + math.floor(num(c.ventilateAfter, 180)) or nil,
        }
        P.SetDevice(p.pid, 'intubated', true)
        P.SetMeta(p.pid, 'tube', tube)
        if r.placed == 'trachea' then
            if c.clearAirway ~= false and p.conditions.airway then P.SetCondition(p.pid, 'airway', nil) end
            setVent(p, true)
            outcome.msg = r.mainstem and L('out_secured_deep', r.depth) or L('out_secured', anat.tube, r.depth)
        else
            setVent(p, false)
            addHypoxia(p, num(c.misplacedStart, 35), true)
            outcome.msg = L('out_tube', anat.tube, r.depth)
        end
        outcome.tube = { size = anat.tube, depth = r.depth }
        bill(src, p, 'intubate')
    else
        outcome.msg = L('out_failed')
    end

    outcome.record = {
        score = score, grade = U.Grade(score), easy = result.easy, seconds = math.floor(num(s.elapsed, 0)),
        tube = r.placed ~= 'none' and ('%s mm @ %d cm'):format(tostring(anat.tube), r.depth) or nil,
        placed = r.placed, cuff = r.cuff, view = 'CL ' .. r.cl, attempts = r.attempts, lowSpo2 = r.lowSpo2,
        capnography = r.capno, grade_airway = anat.grade,
    }
    NZA.Bus.Emit('intubation:done', src, p, outcome)
    return outcome
end

NZA.Proc.Register('intubate', {
    perm = perm(), label = L('proc_intubate'),
    items = function()
        local kit = item('intubation_kit')
        return kit and { [kit] = 1 } or {}
    end,
    maxDist = num(cfg().maxDistance, 3.0),
    minTime = num(cfg().minTime, 25), maxTime = num(cfg().maxTime, 900), easyTime = num(cfg().easyTime, 14),
    consume = cfg().consumeKit == 'start' and 'start' or 'finish',
    self = cfg().allowSelf == true, states = { wounded = true, arrest = true },
    onStart = onStartIntubate,
    onFinish = onFinishIntubate,
})

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE: BVM VENTILATION ROUND
-- ════════════════════════════════════════════════════════════════════════

local function onStartBvm(src, p, _, info)
    local b = sub('bvm')
    if b.enabled == false then return fail('disabled') end
    local states = b.states or { wounded = true, arrest = true }
    if not states[p.state] then return fail('not_down') end
    if item('bvm') then
        local ok = Core.CheckItems(src, { [item('bvm')] = 1 })
        if not ok then return false, { err = 'missing_item', msg = L('err_no_bvm') } end
    end
    local data = startData(p, 'bvm')
    data.easy = info and info.easy or nil
    return true, data
end

local function onFinishBvm(src, p, s, result)
    local b = sub('bvm')
    local nb = math.floor(clamp(num(b.breaths, 8), 3, 20))
    local q, breaths, gastric
    if result.easy then
        q, breaths, gastric = 0.8, nb, 0
    else
        breaths = math.floor(clamp(num(result.breaths, 0), 0, nb * 2))
        q = clamp(num(result.quality, 0), 0, 100) / 100 * clamp(breaths / nb, 0, 1)
        gastric = clamp(num(result.gastric, 0), 0, 100)
    end
    if gastric > 0 then P.SetMeta(p.pid, 'gastric', { v = math.floor(gastric), at = os.time() }) end

    local tube = I.Tube(p)
    local now = os.time()
    local outcome = { score = result.score, easy = result.easy, breaths = breaths }
    if tube and tube.placed == 'oesophagus' then
        outcome.msg = L('out_bvm_bad')
        outcome.ineffective = true
    elseif tube then
        I.Ventilate(p, num(b.ventilate, 120))
        relieve(p, num(b.relief, 30) * q)
        outcome.msg = L('out_bvm_tube', math.floor(num(b.ventilate, 120) / 60 + 0.5))
    else
        if breaths > 0 then P.SetMeta(p.pid, 'bagUntil', now + math.floor(num(b.ventilate, 120) * clamp(q, 0.2, 1))) end
        relieve(p, num(b.relief, 30) * q)
        outcome.msg = q >= 0.5 and L('out_bvm') or L('out_bvm_weak')
    end
    if breaths > 0 then bill(src, p, 'bvm') end
    outcome.record = { score = outcome.score, grade = U.Grade(outcome.score), easy = result.easy, breaths = breaths,
        quality = math.floor(q * 100), via = tube and 'tube' or 'mask', seconds = math.floor(num(s.elapsed, 0)) }
    return outcome
end

NZA.Proc.Register('bvm', {
    perm = bvmPerm(), label = L('proc_bvm'),
    items = {},
    maxDist = num(cfg().maxDistance, 3.0),
    minTime = num(sub('bvm').minTime, 14), maxTime = num(sub('bvm').maxTime, 600), easyTime = num(sub('bvm').easyTime, 8),
    self = false, states = { wounded = true, arrest = true },
    onStart = onStartBvm,
    onFinish = onFinishBvm,
})

-- ════════════════════════════════════════════════════════════════════════
-- TREATMENTS: tube check, depth correction, extubation
-- ════════════════════════════════════════════════════════════════════════

NZA.Treat.Register('tube_check', {
    perm = perm(), self = false, maxDist = num(cfg().maxDistance, 3.0), cooldown = 1500,
    states = { wounded = true, arrest = true, dead = true },
    handler = function(src, p)
        if sub('check').enabled == false then return fail('disabled') end
        local tube = I.Tube(p)
        if not tube then return fail('not_intubated') end
        local now = os.time()
        if checks[p.pid] and now - checks[p.pid] < num(sub('check').cooldown, 10) then return fail('cooldown') end
        checks[p.pid] = now
        bill(src, p, 'check')
        local depth = num(tube.depth, 0)
        if tube.placed == 'oesophagus' then
            if not tube.detected then
                local t = U.deepcopy(p.meta.tube)
                t.detected = now
                P.SetMeta(p.pid, 'tube', t)
            end
            if NZA.Findings and type(NZA.Findings.Add) == 'function' then
                pcall(NZA.Findings.Add, p.pid, 'tube_oesophageal', { cond = 'hypoxia', source = 'capnography', group = 'chest', by = src, text = L('find_oes') })
            end
            return true, { title = L('chk_title'), msg = L('chk_oes'), placed = 'oesophagus', etco2 = 0, tone = 'error' }
        end
        local et = num((p.vitals or {}).etco2, 35)
        if tube.mainstem then
            return true, { title = L('chk_title'), msg = L('chk_mainstem', depth), placed = 'trachea', mainstem = true, etco2 = et, tone = 'warning' }
        end
        return true, { title = L('chk_title'), msg = L('chk_trachea', depth, et), placed = 'trachea', etco2 = et }
    end,
})

NZA.Treat.Register('tube_adjust', {
    perm = perm(), self = false, maxDist = num(cfg().maxDistance, 3.0), cooldown = 1500,
    states = { wounded = true, arrest = true },
    handler = function(_, p)
        local tube = I.Tube(p)
        if not tube or not p.meta.tube then return fail('not_intubated') end
        local t = U.deepcopy(p.meta.tube)
        if not t.mainstem then return true, { msg = L('adj_ok', num(t.depth, 0)) } end
        t.depth = num(t.expected, t.depth)
        t.mainstem = false
        P.SetMeta(p.pid, 'tube', t)
        return true, { msg = L('adj_done', t.depth) }
    end,
})

NZA.Treat.Register('extubate', {
    perm = perm(), self = false, maxDist = num(cfg().maxDistance, 3.0), cooldown = 1500,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p)
        if not (p.devices and p.devices.intubated) then return fail('not_intubated') end
        local wasOes = (I.Tube(p) or {}).placed == 'oesophagus'
        I.Extubate(p, 'medic')
        bill(src, p, 'extubate')
        return true, { msg = wasOes and L('ext_oes') or L('ext_done') }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(2000)
    local usable = sub('usable')
    if not Core.Has('Inv.RegisterUsable') then
        NZA.Debug('intubation: Bridge.Inv.RegisterUsable missing - airway items are not usable from the inventory')
        return
    end
    local function register(key, mode, permName)
        local name = item(key)
        if not name or usable[key] == false then return end
        Core.B('Inv.RegisterUsable', name, function(src)
            src = tonumber(src)
            if not src or not Core.Rate('nza:intubation:use', src, 1, 1500) then return end
            if not NZA.Staff.Can(src, permName) then
                Core.Notify(src, L('err_no_perm'), 'error')
                return
            end
            TriggerClientEvent('nza:intubation:use', src, mode)
        end)
    end
    register('intubation_kit', 'intubate', perm())
    if sub('bvm').enabled ~= false then register('bvm', 'bvm', bvmPerm()) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════

exports('IsIntubated', function(x)
    local p = P.Resolve(x)
    local t = p and I.Tube(p)
    return t ~= nil, t and t.placed or nil
end)

exports('VentilatePatient', function(x, seconds)
    return I.Ventilate(x, seconds)
end)
