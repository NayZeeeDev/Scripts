--[[
    NAYZEEE AMBULANCE - Physiology (NZA.Physiology)                ARCHITECTURE §6

    One server tick (Config.Physiology.tick, default 1 s) over every patient that has
    something going on (healthy patients are skipped after a cheap check). Per tick:

      bleeding     Σ injury bleed × treatment modifiers (tourniquet ×0, bandage ×0.35,
                   packed ×0.25, sutured ×0.05, binder ×0.4 on pelvic/femoral, TXA ×0.6,
                   coiled ×0, splint/cast on fractures) × coagulopathy × perfusion,
                   + haemothorax bleeding; natural clotting of small / dressed wounds
      volume       blood & saline lost in proportion, infusions at their rate (mL/min),
                   saline decays (Config.Physiology.fluidDecay per minute), slow regeneration
      chest        haemothorax mL (chest drain drains it), pneumothorax / tension pressure,
                   cardiac tamponade growth
      airway       drowning water, smoke, airway swelling, unconscious snoring, gurgling
      drugs        opioid / stimulant / alcohol overdose, naloxone reversal, morphine,
                   adrenaline, painkillers, lidocaine, TXA, antibiotics, transfusion reaction
      temperature  blood loss, cold infusions, water, exposure; foil blanket / bed rewarm
      infection    contamination of open, uncovered wounds → infection → sepsis
      pain         injuries minus treatment and medication
      vitals       ATLS classes for HR/BP/MAP/RR, SpO2, temperature, EtCO2, rhythm, AVPU,
                   pupils, breathing & airway descriptors (smoothed, small jitter)
      state        alive → wounded → arrest → dead (and back) with the bleed-out clock
      healing      treated injuries heal (×4 in a hospital bed) and disappear at 100

    API
      NZA.Physiology.Tick(dt)                 one pass over all patients (the loop calls it)
      NZA.Physiology.Update(p, dt, now)       one patient
      NZA.Physiology.Refresh(p)               recompute bleeding / status / stabilized now
      NZA.Physiology.Recompute(p, snap)       Refresh + vitals (snap = no smoothing)
      NZA.Physiology.TimeToDeath(p)           seconds until death threshold at current bleed
      NZA.Physiology.PickArrestRhythm(p, why) 'vf'|'vt'|'pea'|'asystole'
      NZA.Physiology.HealMultiplier(p, inj)   0 = not healing
      NZA.Physiology.InjuryBleed(p, inj)      current mL/min of one injury
      NZA.Physiology.Status(p, inj)           'open'|'controlled'|'treated'|'healing'
      NZA.Physiology.SetModifier(pid, key, { sys, dia, hr, ttl = 3 } | nil)
                                              short-lived vitals offset (e.g. a resuscitation pressure
                                              model), added before smoothing, dropped after ttl s

    Ventilation: a tube on the bag / ventilator (devices.intubated + meta.ventilated, meta.ventRate)
      or a recent bag-valve-mask round (meta.bagUntil timestamp) counts as assisted breathing.
    Stabilized: total bleed < Config.Wounded.stableBleed, or < controlledBleed (default 5 mL/min)
      when no wound is still 'open' and no haemothorax is still filling (clock paused, may stand).
    Accumulators (blood, fluid, temp, heal, contamination, condition levels, infusion left, clock)
      keep full precision; patients.lua rounds them in the snapshots.

    Bus events: infusion:done (p, inf) · injury:updated (p, inj) on status change ·
      injury:removed (p, id) when healed · plus everything SetState emits.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Physiology = NZA.Physiology or {}
NZA.Patients = NZA.Patients or {}
local Phys = NZA.Physiology
local P = NZA.Patients

local function cfg(section, key, default)
    local s = Config[section]
    if s == nil or s[key] == nil then return default end
    return s[key]
end

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function r1(n) return math.floor(n * 10 + 0.5) / 10 end

-- Internal tuning
local K = {
    regen        = 6,      -- mL/min blood regeneration while alive and not bleeding (×4 in bed)
    arrestBleed  = 0.15,   -- bleed multiplier in cardiac arrest without CPR
    cprBleed     = 0.35,   -- ...with CPR going
    drainRate    = 180,    -- mL/min a chest drain removes from the pleural space
    tensionRate  = 0.55,   -- tension pneumothorax pressure points per second (100 = arrest)
    tamponadeArrest = 350, -- mL in the pericardium that stops the heart
    cprWindow    = 4,      -- seconds after the last compression that still count as "CPR in progress"
    infectAt     = 85,     -- wound contamination that starts an infection
}

local HR_CURVE  = { { 0, 0 }, { 0.15, 22 }, { 0.30, 46 }, { 0.40, 64 }, { 0.50, 80 }, { 0.60, 90 } }
local SYS_CURVE = { { 0, 0 }, { 0.15, -4 }, { 0.30, -26 }, { 0.40, -44 }, { 0.45, -56 }, { 0.50, -68 }, { 0.60, -85 } }
local DIA_CURVE = { { 0, 0 }, { 0.15, 6 }, { 0.30, -8 }, { 0.40, -24 }, { 0.45, -32 }, { 0.50, -40 }, { 0.60, -50 } }
local RR_CURVE  = { { 0, 0 }, { 0.15, 5 }, { 0.30, 13 }, { 0.40, 20 }, { 0.50, 26 } }

local function curve(pts, x)
    if x <= pts[1][1] then return pts[1][2] end
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
    end
    return pts[#pts][2]
end

local function med(p, name, now)
    local e = p.meds[name]
    return e ~= nil and e > now
end

local UPPER = { l_lower_arm = 'l_upper_arm', r_lower_arm = 'r_upper_arm', l_lower_leg = 'l_upper_leg', r_lower_leg = 'r_upper_leg' }

local function tqCovers(p, region)
    local tq = p.devices.tourniquet
    if type(tq) ~= 'table' then return false end
    if tq[region] then return true end
    local up = UPPER[region]
    return up ~= nil and tq[up] ~= nil
end

local function cprActive(p, now)
    return p.lastCpr ~= nil and (now - p.lastCpr) <= K.cprWindow
end

-- assisted ventilation: tube = bag / ventilator on a tube, mask = a bag-valve-mask round
-- (the intubation module sets meta.bagUntil for its duration)
local function ventilation(p, now)
    local tube = (p.devices.intubated and p.meta.ventilated) and true or false
    local mask = (not tube) and (tonumber(p.meta.bagUntil) or 0) > now
    return tube, mask
end

-- ════════════════════════════════════════════════════════════════════════
-- BLEEDING
-- ════════════════════════════════════════════════════════════════════════

local function context(p, now)
    local ctx = { now = now }
    ctx.txa = med(p, 'txa', now)
    local total = p.blood + p.fluid
    ctx.dilution = total > 0 and p.fluid / total or 0
    ctx.coag = 1 + math.max(0, ctx.dilution - 0.2) * 2.5          -- dilutional coagulopathy
    if p.temp < 35 then ctx.coag = ctx.coag * (1 + (35 - p.temp) * 0.06) end  -- cold blood doesn't clot
    local b = p.base or {}
    local baseMap = (b.dia or 78) + ((b.sys or 120) - (b.dia or 78)) / 3
    local map = (p.vitals and p.vitals.map) or baseMap
    ctx.perfusion = clamp(map / baseMap, 0.45, 1.1)               -- low pressure bleeds slower
    if p.state == 'arrest' or p.state == 'dead' then
        ctx.perfusion = cprActive(p, now) and K.cprBleed or K.arrestBleed
        if p.state == 'dead' then ctx.perfusion = 0 end
    end
    return ctx
end

local function injuryBleed(p, inj, ctx)
    local b = inj.bleedBase or 0
    if b <= 0 then return 0 end
    local t = inj.treat
    local R = NZA.Const.Region[inj.region]
    if t.tourniquet or (R and R.tourniquet and tqCovers(p, inj.region)) then return 0 end
    if t.coiled then return 0 end
    if inj.type == 'internal' then
        -- only surgery / angio / packing help inside the body
        if t.sutured then b = b * 0.05 end
        if t.packed then b = b * 0.25 end
    else
        if t.bandaged then b = b * 0.35 end
        if t.packed then b = b * 0.25 end
        if t.sutured then b = b * 0.05 end
        if t.dressed then b = b * (inj.type == 'burn' and 0.3 or 0.5) end
        if t.grafted then b = b * 0.1 end
    end
    if inj.type == 'fracture' then
        if t.splinted or t.cast then b = b * 0.5 end
        if t.reduced then b = b * 0.7 end
    end
    if p.devices.binder and (inj.region == 'pelvis'
        or (inj.internal and (inj.internal.organ == 'pelvic' or inj.internal.organ == 'femoral'))) then
        b = b * 0.4
    end
    if ctx.txa then b = b * 0.6 end
    b = b * ctx.coag * ctx.perfusion
    b = b * (1 - clamp(inj.heal or 0, 0, 100) / 100)
    return b
end

local function haemoBleed(p, ctx)
    local h = p.conditions.haemothorax
    if not h or h.stopped then return 0 end
    return (h.rate or 0) * (ctx.txa and 0.6 or 1) * ctx.coag * ctx.perfusion
end

function Phys.InjuryBleed(p, inj)
    return injuryBleed(p, inj, context(p, os.time()))
end

-- ════════════════════════════════════════════════════════════════════════
-- INJURY STATUS & HEALING
-- ════════════════════════════════════════════════════════════════════════

local function definitive(inj)
    local t, k = inj.treat, inj.type
    if k == 'gunshot' or k == 'shrapnel' or k == 'stab' then
        return (t.sutured or t.dressed or t.grafted) and true or false
    elseif k == 'laceration' then
        if inj.severity <= 1 then return (t.bandaged or t.dressed or t.sutured) and true or false end
        return t.sutured and true or false
    elseif k == 'abrasion' then
        return (t.bandaged or t.dressed or t.irrigated) and true or false
    elseif k == 'contusion' then
        return t.cooled and true or false
    elseif k == 'fracture' then
        local f = inj.fracture or {}
        local held = t.splinted or t.cast
        local aligned = (not f.displaced) or t.reduced
        local closed = f.kind == 'closed' or t.sutured or t.dressed
        return (held and aligned and closed) and true or false
    elseif k == 'burn' then
        local deg = inj.burn and inj.burn.degree or 1
        if deg <= 1 then return (t.cooled or t.dressed) and true or false end
        if deg == 2 then return (t.dressed or t.grafted) and true or false end
        return t.grafted and true or false
    elseif k == 'internal' then
        return (t.coiled or t.sutured or (inj.severity <= 1 and (inj.bleedBase or 0) <= 0.5)) and true or false
    end
    return false
end

-- wounds the body closes on its own (no treatment needed, just slower)
local function naturalHeal(inj)
    if inj.type == 'contusion' then return inj.severity >= 3 and 0.3 or 0.6 end
    if inj.type == 'abrasion' and inj.severity <= 1 then return 0.4 end
    return 0
end

function Phys.Status(p, inj)
    local def = definitive(inj)
    if (inj.heal or 0) > 0 and (def or naturalHeal(inj) > 0) then return 'healing' end
    if def then return 'treated' end
    local t = inj.treat
    if (inj.bleed or 0) < 0.5 or t.bandaged or t.packed or t.tourniquet or t.coiled or t.splinted
        or tqCovers(p, inj.region) then
        return 'controlled'
    end
    return 'open'
end

function Phys.HealMultiplier(p, inj)
    local m
    if definitive(inj) then
        m = 1
        if inj.type == 'fracture' then m = inj.treat.cast and 1 or 0.6 end
    else
        m = naturalHeal(inj)
        if m <= 0 then return 0 end
    end
    local inf = p.conditions.infection
    if inf and inf.region == inj.region then m = m * 0.25 end
    return m
end

local function healCap(inj)
    if (inj.retained or 0) > 0 and not inj.treat.extracted then return 60 end
    return 100
end

-- ════════════════════════════════════════════════════════════════════════
-- PAIN
-- ════════════════════════════════════════════════════════════════════════

local function painOf(p, now)
    local list = {}
    local lido = med(p, 'lidocaine', now)
    local c = p.conditions
    local infRegion = c.infection and c.infection.region
    for _, inj in pairs(p.injuries) do
        local v = (inj.pain or 0) * (1 - clamp(inj.heal or 0, 0, 100) / 100)
        local t = inj.treat
        if inj.type == 'fracture' then
            if t.splinted or t.cast then v = v * 0.5 end
            if t.reduced then v = v * 0.8 end
        elseif inj.type == 'burn' then
            if t.cooled then v = v * 0.7 end
            if t.dressed then v = v * 0.7 end
            if t.grafted then v = v * 0.6 end
        elseif t.bandaged or t.dressed or t.sutured then
            v = v * 0.85
        end
        if t.anesthetized and lido then v = v * 0.25 end
        if infRegion and infRegion == inj.region then v = v + 15 end
        list[#list + 1] = v
    end
    for _ in pairs(p.devices.tourniquet or {}) do list[#list + 1] = 25 end
    if c.pneumothorax then list[#list + 1] = 30 end
    if c.haemothorax then list[#list + 1] = 20 end
    if c.spinal then list[#list + 1] = 35 end
    if c.concussion then list[#list + 1] = 12 * (c.concussion.grade or 1) end
    if #list == 0 then return 0 end
    table.sort(list, function(a, b) return a > b end)
    local total = list[1] + 0.35 * (list[2] or 0)
    for i = 3, #list do total = total + 0.15 * list[i] end
    if med(p, 'painkillers', now) then total = total - 20 end
    if med(p, 'morphine', now) then total = total - 45 end
    return clamp(total, 0, 100)
end

-- ════════════════════════════════════════════════════════════════════════
-- DESCRIPTORS
-- ════════════════════════════════════════════════════════════════════════

local AVPU = { 'A', 'V', 'P', 'U' }

local function avpuOf(p, loss, spo2, map, now)
    local score = 0
    local function worse(n) if n > score then score = n end end
    if loss >= 0.44 then worse(3) elseif loss >= 0.38 then worse(2) elseif loss >= 0.30 then worse(1) end
    if spo2 < 65 then worse(3) elseif spo2 < 75 then worse(2) elseif spo2 < 85 then worse(1) end
    if map < 45 then worse(3) elseif map < 55 then worse(2) elseif map < 62 then worse(1) end
    local c = p.conditions
    if c.concussion then
        local g = c.concussion.grade or 1
        if g >= 3 then worse(2)
        elseif g == 2 and now - (c.concussion.since or now) < 300 then worse(1) end
    end
    if c.overdose and c.overdose.drug ~= 'stimulant' then
        local a = c.overdose.amount or 0
        if a > 80 then worse(3) elseif a > 60 then worse(2) elseif a > 40 then worse(1) end
    end
    if p.temp < 28 then worse(3) elseif p.temp < 30 then worse(2) elseif p.temp < 32 then worse(1) end
    if c.infection and (c.infection.level or 0) >= 90 then worse(1) end
    if c.hypoxia and (c.hypoxia.water or 0) > 500 then worse(2) end
    if c.spinal and c.spinal.complete and c.spinal.level == 'cervical' then worse(1) end
    return AVPU[score + 1]
end

local function airwayOf(p, avpu)
    if p.devices.intubated then return 'secured' end
    local c = p.conditions
    if c.airway and (c.airway.kind == 'obstructed' or (c.airway.level or 0) >= 100) then return 'obstructed' end
    if c.hypoxia and (c.hypoxia.water or 0) > 50 then return 'gurgling' end
    local down = avpu == 'P' or avpu == 'U'
    -- the recovery position (meta.recovery) lets vomit and blood drain out of the mouth and the
    -- tongue fall forward; water in the lungs (above) keeps gurgling until it is coughed up
    if down and not p.meta.recovery then
        if c.overdose and c.overdose.drug == 'alcohol' and (c.overdose.amount or 0) > 80 then return 'gurgling' end
        for _, inj in pairs(p.injuries) do
            if (inj.region == 'face' or inj.region == 'neck') and (inj.bleed or 0) >= 20 then return 'gurgling' end
        end
        return 'snoring'
    end
    if c.airway and c.airway.kind == 'swelling' and (c.airway.level or 0) >= 50 then return 'snoring' end
    return 'clear'
end

local AIRWAY_SPO2 = { clear = 0, secured = 0, snoring = 4, gurgling = 8, obstructed = 40 }

local function pupilsOf(p, avpu, spo2, opioid)
    local c = p.conditions
    if opioid > 30 or (P.MedActive(p, 'morphine') and opioid > 0) then return 'pinpoint' end
    if (c.concussion and (c.concussion.grade or 1) >= 3) then return 'unequal' end
    for _, inj in pairs(p.injuries) do
        if inj.region == 'head' and inj.severity >= 4 then return 'unequal' end
    end
    if c.overdose and c.overdose.drug == 'stimulant' and (c.overdose.amount or 0) > 40 then return 'dilated' end
    if spo2 < 80 then return 'dilated' end
    if avpu == 'U' or avpu == 'P' then return 'sluggish' end
    return 'normal'
end

local function breathingOf(p, rr, opioid)
    local c = p.conditions
    if rr < 1 then return 'absent' end
    if rr < 6 then return 'agonal' end
    if rr < 10 or opioid > 40 then return 'shallow' end
    if (c.pneumothorax) or (c.haemothorax and (c.haemothorax.ml or 0) > 500) or rr > 26 then return 'labored' end
    return 'normal'
end

-- ════════════════════════════════════════════════════════════════════════
-- VITALS
-- ════════════════════════════════════════════════════════════════════════

local function setDeadVitals(p)
    local v = p.vitals
    v.hr, v.sys, v.dia, v.map, v.spo2, v.rr, v.etco2, v.ecgRate = 0, 0, 0, 0, 0, 0, 0, 0
    v.rhythm, v.avpu, v.pupils, v.breathing = 'asystole', 'U', 'fixed', 'absent'
    v.airway = p.devices.intubated and 'secured' or 'clear'
    v.temp = r1(p.temp)
end

local ECG_RATE = { vf = 0, vt = 180, pea = 40, asystole = 0 }

local function setArrestVitals(p, now)
    local v = p.vitals
    local a = p.conditions.arrest or { rhythm = 'pea' }
    local since = now - (p.arrestAt or now)
    local cpr = cprActive(p, now)
    local q = clamp(tonumber(p.meta.cprQuality) or 70, 0, 100)
    v.hr = 0
    v.ecgRate = ECG_RATE[a.rhythm] or 0
    if a.rhythm == 'pea' then v.ecgRate = math.max(20, 48 - math.floor(since / 20)) end
    if cpr then
        v.sys, v.dia = math.floor(35 + q * 0.3), math.floor(12 + q * 0.1)
    else
        v.sys, v.dia = 0, 0
    end
    v.map = math.floor(v.dia + (v.sys - v.dia) / 3 + 0.5)
    v.spo2 = 0
    v.rr = since < 45 and 3 or 0
    local tube, mask = ventilation(p, now)
    if tube or mask then v.rr = tonumber(p.meta.ventRate) or 10 end
    if cpr then v.etco2 = math.floor(8 + q * 0.14 + 0.5) else v.etco2 = since < 60 and 6 or 2 end
    v.rhythm = a.rhythm
    v.avpu = 'U'
    v.pupils = since > 60 and 'fixed' or 'dilated'
    v.breathing = (since < 45 and not (p.meta.ventilated or mask)) and 'agonal' or 'absent'
    if p.devices.intubated then v.airway = 'secured'
    elseif p.conditions.hypoxia and (p.conditions.hypoxia.water or 0) > 50 then v.airway = 'gurgling'
    elseif p.conditions.airway and p.conditions.airway.kind == 'obstructed' then v.airway = 'obstructed'
    else v.airway = 'clear' end
    v.temp = r1(p.temp)
end

local function computeVitals(p, ctx, dt, snap)
    local v = p.vitals
    local now = ctx.now
    if p.state == 'dead' then return setDeadVitals(p) end
    if p.state == 'arrest' then return setArrestVitals(p, now) end

    local loss = P.Loss(p)
    local c = p.conditions
    local b = p.base
    local hr = b.hr + curve(HR_CURVE, loss)
    local sys = b.sys + curve(SYS_CURVE, loss)
    local dia = b.dia + curve(DIA_CURVE, loss)
    local rr = b.rr + curve(RR_CURVE, loss)
    local spo2 = 98.6
    local etco2 = 38

    local pain = p.pain or 0
    hr = hr + pain * 0.15
    sys = sys + pain * 0.08
    dia = dia + pain * 0.05
    rr = rr + pain * 0.04

    if med(p, 'adrenaline', now) then hr, sys, dia = hr + 25, sys + 25, dia + 10 end
    if med(p, 'morphine', now) then hr, sys, rr = hr - 4, sys - 6, rr - 2 end
    if med(p, 'reaction', now) then hr, sys, dia = hr + 20, sys - 20, dia - 10 end

    local opioid = 0
    local od = c.overdose
    if od then
        local a = od.amount or 0
        if od.drug == 'opioid' then
            opioid = a
            hr, sys = hr - a * 0.2, sys - a * 0.15
        elseif od.drug == 'stimulant' then
            hr, sys, dia, rr = hr + a * 0.6, sys + a * 0.4, dia + a * 0.2, rr + a * 0.06
        elseif od.drug == 'alcohol' then
            hr, sys, rr = hr + a * 0.1, sys - a * 0.1, rr - a * 0.04
        end
    end

    local inf = c.infection
    if inf then
        local l = inf.level or 0
        hr, rr = hr + l * 0.25, rr + l * 0.06
        if l > 50 then sys, dia = sys - (l - 50) * 0.5, dia - (l - 50) * 0.3 end
    end

    local t = p.temp
    if t > 37.5 then hr = hr + (t - 37.0) * 10 end
    if t < 35 then
        hr, rr, sys = hr - (35 - t) * 6, rr - (35 - t) * 1.2, sys - (35 - t) * 2
    end

    local h = c.haemothorax
    local hml = h and (h.ml or 0) or 0
    spo2 = spo2 - math.min(30, hml / 500 * 4)
    rr = rr + hml / 250
    if hml > 1500 then sys = sys - (hml - 1500) * 0.01 end

    local pn = c.pneumothorax
    if pn then
        local size, pr = pn.size or 20, pn.pressure or 0
        spo2 = spo2 - math.min(10, size * 0.1) - pr * 0.3
        rr = rr + size * 0.08 + pr * 0.12
        sys, dia, hr = sys - pr * 0.55, dia - pr * 0.3, hr + pr * 0.35
    end

    local tp = c.tamponade
    if tp and (tp.ml or 0) > 80 then
        local x = tp.ml - 80
        sys, dia, hr = sys - x * 0.22, dia - x * 0.08, hr + x * 0.15
        etco2 = etco2 - x * 0.03
    end

    local hx = c.hypoxia
    if hx then spo2 = spo2 - (hx.water or 0) * 0.04 - (hx.smoke or 0) * 0.25 end
    if c.airway and c.airway.kind == 'swelling' then spo2 = spo2 - (c.airway.level or 0) * 0.08 end

    if c.spinal and c.spinal.complete and (c.spinal.level == 'cervical' or c.spinal.level == 'thoracic') then
        sys, dia, hr = sys - 18, dia - 10, hr - 15   -- neurogenic shock
    end
    if c.concussion and (c.concussion.grade or 1) >= 3 then hr, sys = hr - 10, sys + 10 end

    -- breathing drive
    rr = rr * (1 - clamp((opioid - 20) / 100, 0, 0.85))
    local tube, mask = ventilation(p, now)
    if tube then
        rr = tonumber(p.meta.ventRate) or 14
    elseif mask then
        rr = math.max(rr, tonumber(p.meta.ventRate) or 10)   -- bagged breaths on top of the patient's own
    end
    local ventilated = tube or mask
    if rr < 10 then spo2 = spo2 - (10 - rr) * 3 end

    -- perfusion / dilution / cold probe
    if loss > 0.35 then spo2 = spo2 - (loss - 0.35) * 60 end
    if ctx.dilution > 0.25 then spo2 = spo2 - (ctx.dilution - 0.25) * 25 end
    if t < 34 then spo2 = spo2 - (34 - t) * 1.5 end

    local airway = airwayOf(p, v.avpu or 'A')
    spo2 = spo2 - (AIRWAY_SPO2[airway] or 0)
    if p.devices.oxygen then spo2 = spo2 + 6 end
    if ventilated then spo2 = spo2 + 4 end
    spo2 = clamp(spo2, 40, 100)

    if spo2 < 90 then hr = hr + (90 - spo2) * 0.8 end
    if spo2 < 70 then
        hr = hr - (70 - spo2) * 3.5     -- hypoxic bradycardia before arrest
        rr = rr * 0.7
    end

    -- short-lived module offsets (NZA.Physiology.SetModifier), dropped once expired
    local rtm = P.RT(p)
    if rtm.mods then
        for key, mod in pairs(rtm.mods) do
            if mod.exp <= now then
                rtm.mods[key] = nil
            else
                hr, sys, dia = hr + mod.hr, sys + mod.sys, dia + mod.dia
            end
        end
        if next(rtm.mods) == nil then rtm.mods = nil end
    end

    if rr > 24 then etco2 = etco2 - (rr - 24) * 0.6 elseif rr < 10 then etco2 = etco2 + (10 - rr) * 3 end
    local mapEst = dia + (sys - dia) / 3
    etco2 = etco2 * clamp(mapEst / 80, 0.4, 1.05)
    if ctx.dilution > 0.3 then etco2 = etco2 - (ctx.dilution - 0.3) * 10 end

    hr = clamp(hr, 20, 220)
    sys = clamp(sys, 30, 240)
    dia = clamp(dia, 15, sys - 8)
    rr = clamp(rr, 0, 60)
    etco2 = clamp(etco2, 5, 80)

    -- smooth (floats live in runtime so rounding never stalls the curve)
    local r = P.RT(p)
    local f = r.vf
    if not f or snap then
        f = { hr = hr, sys = sys, dia = dia, rr = rr, spo2 = spo2, etco2 = etco2 }
        if not snap and v.hr and v.hr > 0 then
            f = { hr = v.hr, sys = v.sys, dia = v.dia, rr = v.rr, spo2 = v.spo2, etco2 = v.etco2 }
        end
        r.vf = f
    end
    local k = snap and 1 or (1 - math.exp(-(dt or 1) / 4))
    f.hr = f.hr + (hr - f.hr) * k
    f.sys = f.sys + (sys - f.sys) * k
    f.dia = f.dia + (dia - f.dia) * k
    f.rr = f.rr + (rr - f.rr) * k
    f.spo2 = f.spo2 + (spo2 - f.spo2) * k
    f.etco2 = f.etco2 + (etco2 - f.etco2) * k

    local jit = snap and 0 or 1
    v.hr = math.floor(f.hr + (math.random() - 0.5) * 2 * jit + 0.5)
    v.sys = math.floor(f.sys + (math.random() - 0.5) * 2 * jit + 0.5)
    v.dia = math.floor(f.dia + 0.5)
    v.map = math.floor(v.dia + (v.sys - v.dia) / 3 + 0.5)
    v.rr = math.max(0, math.floor(f.rr + (math.random() - 0.5) * jit + 0.5))
    v.spo2 = math.min(100, math.floor(f.spo2 + (math.random() - 0.5) * 0.6 * jit + 0.5))
    v.etco2 = math.floor(f.etco2 + 0.5)
    v.temp = r1(p.temp)
    v.ecgRate = v.hr

    -- rhythm
    if p.temp < 32.5 then v.rhythm = 'afib'
    elseif v.hr >= 100 then v.rhythm = 'stach'
    elseif v.hr < 55 then v.rhythm = 'sbrady'
    else v.rhythm = 'sinus' end

    v.avpu = avpuOf(p, loss, v.spo2, v.map, now)
    v.airway = airwayOf(p, v.avpu)
    v.pupils = pupilsOf(p, v.avpu, v.spo2, opioid)
    v.breathing = breathingOf(p, v.rr, opioid)
    if tube then
        v.breathing = 'normal'
    elseif mask and (v.breathing == 'absent' or v.breathing == 'agonal' or v.breathing == 'shallow') then
        v.breathing = 'normal'      -- the bag makes up for poor breathing; laboured stays laboured
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CONDITIONS OVER TIME → extra bleed (haemothorax) in mL/min
-- ════════════════════════════════════════════════════════════════════════

local function stepConditions(p, dt, now, ctx)
    local c = p.conditions
    local d = p.devices
    local drains = d.chestDrain or {}
    local intubated = d.intubated
    local m = dt / 60

    -- haemothorax: bleeding into the chest; a drain on that side empties it
    local h = c.haemothorax
    if h then
        local eff = haemoBleed(p, ctx)
        h.ml = (h.ml or 0) + eff * m
        local drained = drains[h.side] or (h.side == 'both' and (drains.left or drains.right))
            or (h.side ~= 'left' and h.side ~= 'right' and (drains.left or drains.right))
        if drained then
            local out = math.min(h.ml, K.drainRate * m)
            h.ml = h.ml - out
            h.output = (h.output or 0) + out
        end
        local decay = drained and 0.04 or 0.015       -- clots / lung re-expansion tamponades the bleed
        if not h.stopped then
            h.rate = (h.rate or 0) * (1 - decay * m)
            if h.rate < 0.2 then h.rate = 0 end
        end
        if h.ml <= 0.5 and ((h.rate or 0) <= 0 or h.stopped) then c.haemothorax = nil end
    end

    -- pneumothorax / tension
    local pn = c.pneumothorax
    if pn then
        if drains[pn.side] or (pn.side ~= 'left' and pn.side ~= 'right' and (drains.left or drains.right)) then
            pn.tension, pn.pressure = false, 0
            pn.size = (pn.size or 0) - 10 * m
            if pn.size <= 0 then c.pneumothorax = nil end
        elseif pn.tension then
            local rate = K.tensionRate * ((intubated and p.meta.ventilated) and 1.5 or 1)
            pn.pressure = math.min(100, (pn.pressure or 0) + rate * dt)
        else
            pn.size = math.min(60, (pn.size or 20) + 0.5 * m)
            if (pn.pressure or 0) > 0 then pn.pressure = math.max(0, pn.pressure - 5 * dt) end
        end
    end

    -- cardiac tamponade
    local tp = c.tamponade
    if tp then
        if not tp.stopped then
            local rate = (tp.rate or 10) * (ctx.txa and 0.6 or 1)
            tp.ml = (tp.ml or 0) + rate * m
            tp.rate = (tp.rate or 10) * (1 - 0.01 * m)
        end
        if (tp.ml or 0) <= 0 and (tp.stopped or (tp.rate or 0) < 0.5) then c.tamponade = nil end
    end

    -- water / smoke in the lungs
    local hx = c.hypoxia
    if hx then
        local v = p.vitals
        local conscious = v.avpu == 'A' or v.avpu == 'V'
        if (hx.water or 0) > 0 then
            if p.state ~= 'arrest' and conscious and not intubated then
                hx.water = math.max(0, hx.water - 15 * m)      -- coughing it up
            elseif cprActive(p, now) then
                hx.water = math.max(0, hx.water - 20 * m)      -- compressions push water out
            end
        end
        if (hx.smoke or 0) > 0 then hx.smoke = math.max(0, hx.smoke - (d.oxygen and 12 or 4) * m) end
        if (hx.water or 0) <= 0 and (hx.smoke or 0) <= 0 then c.hypoxia = nil end
    end

    -- airway swelling closes the airway unless intubated
    local aw = c.airway
    if aw and aw.kind == 'swelling' and not intubated then
        aw.level = math.min(100, (aw.level or 0) + 2.5 * m)
        if aw.level >= 100 then aw.kind = 'obstructed' end
    end

    -- overdoses wear off (naloxone keeps antagonising opioids)
    local od = c.overdose
    if od then
        local rate = od.drug == 'stimulant' and 1.2 or (od.drug == 'alcohol' and 1.0 or 0.8)
        if od.drug == 'opioid' and med(p, 'naloxone', now) then rate = rate + 6 end
        od.amount = (od.amount or 0) - rate * m
        if od.amount <= 0 then c.overdose = nil end
    end

    -- concussion settles with rest
    local cc = c.concussion
    if cc and p.state == 'alive' then
        local per = p.meta.inBed and 300 or 600
        if now - (cc.since or now) >= per then
            cc.grade = (cc.grade or 1) - 1
            cc.since = now
            if cc.grade <= 0 then c.concussion = nil end
        end
    end

    -- spinal injury: resolves once the spine fracture is gone (collar speeds it up)
    local sp = c.spinal
    if sp and not sp.complete then
        sp.since = sp.since or now
        local spineFx = false
        for _, inj in pairs(p.injuries) do
            if inj.type == 'fracture' and inj.fracture and (inj.fracture.bone == 'c_spine' or inj.fracture.bone == 't_spine' or inj.fracture.bone == 'l_spine') then
                spineFx = true
                break
            end
        end
        if not spineFx and now - sp.since >= (d.collar and 1800 or 3600) then c.spinal = nil end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- INFECTION
-- ════════════════════════════════════════════════════════════════════════

local function stepInfection(p, dt, now)
    if cfg('Physiology', 'infection', true) == false then return end
    local m = dt / 60
    local abx = med(p, 'antibiotics', now)
    local wet = p.meta.wet and p.meta.wet > now
    local worst, worstRegion = 0, nil
    local OPEN = NZA.Injury.OpenTypes
    for _, inj in pairs(p.injuries) do
        local open = OPEN[inj.type]
            or (inj.type == 'fracture' and inj.fracture and inj.fracture.kind ~= 'closed')
            or (inj.type == 'internal' and inj.internal and inj.internal.organ == 'bowel')
        if open then
            local t = inj.treat
            local covered = t.dressed or t.sutured or t.grafted
            local g
            if abx then
                g = -2
            elseif covered then
                g = (inj.retained or 0) > 0 and not t.extracted and 0.15 or -0.3
            else
                g = 0.5 * (((inj.retained or 0) > 0 and not t.extracted) and 1.5 or 1) * (wet and 1.3 or 1)
                if t.irrigated then g = g * 0.5 end
            end
            inj.contamination = clamp((inj.contamination or 0) + g * m, 0, 100)
            if inj.contamination > worst and now - (inj.created or now) >= 600 then
                worst, worstRegion = inj.contamination, inj.region
            end
        end
    end
    local c = p.conditions.infection
    if abx then
        if c then
            c.level = (c.level or 0) - 3 * m
            if c.level <= 0 then p.conditions.infection = nil end
        end
    elseif worst >= K.infectAt then
        if not c then
            c = { region = worstRegion, level = 0, since = now }
            p.conditions.infection = c
        end
        c.level = math.min(100, (c.level or 0) + 0.8 * m * (worst / K.infectAt))
        c.region = worstRegion
    elseif c then
        c.level = (c.level or 0) - 0.3 * m
        if c.level <= 0 then p.conditions.infection = nil end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- TEMPERATURE
-- ════════════════════════════════════════════════════════════════════════

local function stepTemperature(p, dt, now, loss)
    if cfg('Physiology', 'hypothermia', true) == false then
        p.temp = 37.0
        return
    end
    local c = p.conditions
    local target = 37.0
    if c.infection then target = target + math.min(2.5, (c.infection.level or 0) * 0.025) end
    if c.overdose and c.overdose.drug == 'stimulant' then target = target + (c.overdose.amount or 0) * 0.02 end
    if med(p, 'reaction', now) then target = target + 1.2 end

    local wet = p.meta.wet and p.meta.wet > now
    local inBed, foil = p.meta.inBed, p.devices.foil
    local cool, warm = 0, 0
    if loss > 0.15 then cool = cool + (loss - 0.15) * 0.25 end
    if p.state ~= 'alive' and not inBed and not foil then cool = cool + 0.012 end
    if wet then cool = cool + (foil and 0.02 or 0.06) end
    if p.state == 'arrest' then cool = cool + 0.02 end
    if c.overdose and c.overdose.drug == 'alcohol' then cool = cool + 0.01 end
    -- °C per minute. A foil blanket / warm hospital bed must visibly fix hypothermia in
    -- a few minutes of play, so they are far stronger than real passive rewarming.
    if foil then warm = warm + 0.2 end
    if inBed then warm = warm + 0.25 end
    if p.state == 'alive' and loss < 0.15 and not wet then warm = warm + 0.05 end
    if p.state == 'wounded' and not wet and loss < 0.25 then warm = warm + 0.008 end

    local rate = -cool
    if p.temp < target then
        rate = rate + warm
    elseif p.temp > target + 0.05 then
        rate = rate - 0.05
    end
    local before = p.temp
    p.temp = clamp(p.temp + rate * dt / 60, 24, 42)
    if rate > 0 and before <= target and p.temp > target then p.temp = target end
    if rate < 0 and before >= target and p.temp < target and cool <= 0 then p.temp = target end

    if p.temp < 35 then
        c.hypothermia = c.hypothermia or { since = now }
        c.hypothermia.temp = r1(p.temp)
    elseif c.hypothermia and p.temp >= 35.3 then
        c.hypothermia = nil
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- INFUSIONS
-- ════════════════════════════════════════════════════════════════════════

local function stepInfusions(p, dt, now)
    local list = p.infusions
    local i = 1
    local m = dt / 60
    while i <= #list do
        local inf = list[i]
        if not inf.paused and (inf.left or 0) > 0 then
            local ml = math.min(inf.left, (inf.rate or 50) * m)
            inf.left = inf.left - ml
            local kind = inf.kind
            if kind == 'blood' then
                if inf.incompatible then
                    p.blood = p.blood + ml * 0.5
                    p.meds.reaction = now + 300
                else
                    p.blood = p.blood + ml
                end
                if not inf.warm then p.temp = p.temp - ml * 0.0006 end   -- refrigerated blood
                p.given.blood = (p.given.blood or 0) + ml
            elseif kind == 'plasma' then
                p.blood = p.blood + ml * 0.8
                p.given.plasma = (p.given.plasma or 0) + ml
            elseif kind == 'txa' then
                p.meds.txa = math.max(p.meds.txa or 0, now + 3600)
            else
                p.fluid = p.fluid + ml
                if not inf.warm then p.temp = p.temp - ml * 0.0005 end   -- room temperature saline
                p.given[kind] = (p.given[kind] or 0) + ml
            end
        end
        if (inf.left or 0) <= 0.05 then
            table.remove(list, i)
            if inf.kind == 'txa' then p.given.txa = (p.given.txa or 0) + 1 end
            NZA.Bus.Emit('infusion:done', p, inf)
        else
            i = i + 1
        end
    end
    p.blood = math.min(p.blood, p.bloodMax * 1.1)
end

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC HELPERS
-- ════════════════════════════════════════════════════════════════════════

function Phys.TimeToDeath(p, bleed)
    bleed = bleed or p.bleedTotal or 0
    local eff = p.blood + 0.35 * p.fluid
    local deathEff = p.bloodMax * (1 - cfg('Physiology', 'deathLoss', 0.50))
    local room = eff - deathEff
    if room <= 0 then return 0 end
    if bleed < 0.01 then return 1e6 end
    return room / (bleed / 60)
end

function Phys.PickArrestRhythm(p, why)
    local w
    if why == 'headshot' or why == 'trauma' or why == 'electrocution' or why == 'stimulant' or why == 'hypothermia' then
        w = { { 'vf', 5 }, { 'vt', 2 }, { 'pea', 2 }, { 'asystole', 1 } }
    elseif why == 'hypoxia' or why == 'drowning' or why == 'opioid' or why == 'overdose' then
        w = { { 'pea', 5 }, { 'asystole', 4 }, { 'vf', 1 } }
    elseif why == 'tension' or why == 'tamponade' then
        w = { { 'pea', 1 } }
    elseif why == 'hypovolemia' or why == 'bleedout' or why == 'hypotension' or why == 'exsanguination' then
        if P.Loss(p) > 0.48 then w = { { 'pea', 5 }, { 'asystole', 4 } }
        else w = { { 'pea', 6 }, { 'vf', 2 }, { 'asystole', 2 } } end
    elseif why == 'admin' or why == 'condition' then
        w = { { 'vf', 3 }, { 'vt', 1 }, { 'pea', 1 } }
    else
        w = { { 'vf', 4 }, { 'pea', 4 }, { 'asystole', 2 }, { 'vt', 1 } }
    end
    return NZA.Util.weightedPick(w) or 'pea'
end

-- STABILIZED (§6): the bleed-out clock pauses and the patient may be helped up. Any total under
-- Config.Wounded.stableBleed counts; up to Config.Wounded.controlledBleed it counts when every wound
-- that still bleeds is under control (bandaged / packed / tourniquet / splinted / treated - not
-- 'open') and no haemothorax is still filling. Untreated and internal ('open') bleeds keep the clock.
-- Needs fresh inj.bleed / inj.status (both callers set them first).
local function isStable(p, total)
    if p.state == 'arrest' or p.state == 'dead' then return false end
    if total < cfg('Wounded', 'stableBleed', 1.0) then return true end
    if total >= cfg('Wounded', 'controlledBleed', 5.0) then return false end
    local h = p.conditions.haemothorax
    if h and not h.stopped and (h.rate or 0) > 0 then return false end
    for _, inj in pairs(p.injuries) do
        if (inj.bleed or 0) >= 0.5 and inj.status == 'open' then return false end
    end
    return true
end

-- Recompute bleeding, injury status and the stabilized flag without moving time.
function Phys.Refresh(p)
    if not p or not p.injuries then return end
    local now = os.time()
    local ctx = context(p, now)
    local total = 0
    for _, inj in pairs(p.injuries) do
        inj.bleed = r1(injuryBleed(p, inj, ctx))
        total = total + inj.bleed
        inj.status = Phys.Status(p, inj)
    end
    total = total + haemoBleed(p, ctx)
    p.bleedTotal = r1(total)
    p.stabilized = isStable(p, p.bleedTotal)
    p.pain = math.floor(painOf(p, now) + 0.5)
end

function Phys.Recompute(p, snap)
    if not p or not p.vitals then return end
    Phys.Refresh(p)
    computeVitals(p, context(p, os.time()), 0, snap ~= false)
end

-- ════════════════════════════════════════════════════════════════════════
-- THE TICK
-- ════════════════════════════════════════════════════════════════════════

local function needsTick(p)
    if p.state == 'dead' then return false end
    if p.state ~= 'alive' then return true end
    if next(p.injuries) or next(p.conditions) or next(p.infusions) or next(p.meds) or next(p.watchers) then return true end
    if p.blood < p.bloodMax - 0.5 or p.fluid > 0.5 or math.abs(p.temp - 37) > 0.05 or (p.pain or 0) > 0 or (p.bleedTotal or 0) > 0 then
        return true
    end
    -- healthy: settle the numbers once, then skip until something changes
    local r = P.RT(p)
    if r.mods then return true end      -- a module offset (SetModifier) is running
    if r.active then
        p.blood, p.fluid, p.temp, p.pain, p.bleedTotal, p.stabilized = math.min(p.blood, p.bloodMax), 0, 37.0, 0, 0, true
        Phys.Recompute(p, true)
        P.Touch(p)
        r.active = false
    end
    return false
end

local function transition(p, to, why)
    P.SetState(p, to, why)
    return true
end

function Phys.Update(p, dt, now)
    if p.state == 'dead' then return end
    local r = P.RT(p)
    now = now or os.time()
    local m = dt / 60

    -- expired medication
    for name, exp in pairs(p.meds) do
        if exp <= now then p.meds[name] = nil end
    end

    local ctx = context(p, now)

    -- ── injuries: bleed, clot, heal
    local total = 0
    local healRate = cfg('Physiology', 'healRate', 0.4) * (p.meta.inBed and 4 or 1)
    local removed
    for id, inj in pairs(p.injuries) do
        local t = inj.treat
        -- natural clotting: small wounds and wounds under pressure slowly stop
        if (inj.bleedBase or 0) > 0 then
            local decay = 0
            if inj.type ~= 'internal' and (t.bandaged or t.packed or t.sutured or t.dressed) then decay = decay + 0.02 end
            if inj.severity <= 2 and (inj.type == 'abrasion' or inj.type == 'laceration' or inj.type == 'contusion'
                or inj.type == 'burn' or inj.type == 'shrapnel') then decay = decay + 0.03 end
            if inj.type == 'internal' and inj.severity <= 1 then decay = decay + 0.02 end
            if decay > 0 then
                inj.bleedBase = inj.bleedBase * (1 - decay / ctx.coag * m)
                if inj.bleedBase < 0.1 then inj.bleedBase = 0 end
            end
        end
        inj.bleed = r1(injuryBleed(p, inj, ctx))
        total = total + inj.bleed

        -- healing
        local hm = Phys.HealMultiplier(p, inj)
        if hm > 0 and p.state ~= 'arrest' then
            inj.heal = math.min(healCap(inj), (inj.heal or 0) + healRate * hm * m)
            if inj.heal >= 100 then
                removed = removed or {}
                removed[#removed + 1] = id
            end
        end
        local st = Phys.Status(p, inj)
        if st ~= inj.status then
            inj.status = st
            NZA.Bus.Emit('injury:updated', p, inj)
        end
    end
    if removed then
        for _, id in ipairs(removed) do
            p.injuries[id] = nil
            NZA.Bus.Emit('injury:removed', p, id)
        end
    end

    -- ── conditions (haemothorax adds to the bleed)
    total = total + haemoBleed(p, ctx)
    stepConditions(p, dt, now, ctx)

    -- ── blood & fluid accounting
    local minClock = cfg('Wounded', 'minClock', 60)
    local applied = total
    if p.state == 'wounded' and p.downAt and (now - p.downAt) < minClock and (p.clock or 0) > 0 then
        -- the first minClock seconds down are guaranteed: blood can't run out before the clock does
        local arrestEff = p.bloodMax * (1 - cfg('Physiology', 'arrestLoss', 0.45))
        local room = (p.blood + 0.35 * p.fluid) - arrestEff
        local maxRate = room > 0 and (room / math.max(1, p.clock)) * 60 or 0
        if applied > maxRate then applied = maxRate end
    end
    local lostMl = applied * m
    if lostMl > 0 then
        local circ = p.blood + p.fluid
        local fromFluid = circ > 0 and lostMl * (p.fluid / circ) or 0
        p.fluid = math.max(0, p.fluid - fromFluid)
        p.blood = math.max(0, p.blood - (lostMl - fromFluid))
    end
    stepInfusions(p, dt, now)
    if p.fluid > 0 then
        p.fluid = p.fluid * (1 - cfg('Physiology', 'fluidDecay', 0.01) * m)
        if p.fluid < 0.5 then p.fluid = 0 end
    end
    if p.state == 'alive' and total < 0.5 and p.blood < p.bloodMax then
        p.blood = math.min(p.bloodMax, p.blood + K.regen * (p.meta.inBed and 4 or 1) * m)
    end

    p.bleedTotal = r1(total)
    p.stabilized = isStable(p, p.bleedTotal)      -- statuses were refreshed in the injury loop above

    local loss = P.Loss(p)
    stepInfection(p, dt, now)
    stepTemperature(p, dt, now, loss)
    p.pain = math.floor(painOf(p, now) + 0.5)

    -- ── vitals
    computeVitals(p, context(p, now), dt, false)

    -- ── state machine
    local v = p.vitals
    local state = p.state

    if loss >= cfg('Physiology', 'deathLoss', 0.50) then
        transition(p, 'dead', 'exsanguination')
        return
    end

    if state == 'arrest' then
        if not cprActive(p, now) then
            p.arrestLeft = (p.arrestLeft or cfg('Death', 'arrestToDeath', 300)) - dt
            r.noCpr = (r.noCpr or 0) + dt
            local a = p.conditions.arrest
            if a then
                if a.rhythm == 'vt' and r.noCpr >= 90 then a.rhythm = 'vf' end
                if a.rhythm == 'vf' and r.noCpr >= 240 then a.rhythm = 'asystole' end
                if a.rhythm == 'pea' and r.noCpr >= 300 then a.rhythm = 'asystole' end
            end
        else
            r.noCpr = 0
        end
        if (p.arrestLeft or 0) <= 0 then
            p.arrestLeft = 0
            transition(p, 'dead', 'arrest')
            return
        end
        P.Touch(p)
        return
    end

    -- alive / wounded → arrest
    local why
    local grace = r.roscGrace and now < r.roscGrace
    if loss >= cfg('Physiology', 'arrestLoss', 0.45) and not grace then why = 'hypovolemia' end
    if (v.map or 90) < cfg('Physiology', 'arrestMap', 40) then r.lowMap = (r.lowMap or 0) + dt else r.lowMap = 0 end
    if (v.spo2 or 99) < cfg('Physiology', 'hypoxiaArrest', 60) then r.lowSpo2 = (r.lowSpo2 or 0) + dt else r.lowSpo2 = 0 end
    local delay = cfg('Physiology', 'arrestDelay', 20)
    if not why and r.lowMap >= delay then why = 'hypotension' end
    if not why and r.lowSpo2 >= delay then
        local hx = p.conditions.hypoxia
        why = (hx and (hx.water or 0) > 0) and 'drowning' or 'hypoxia'
    end
    local c = p.conditions
    if not why and c.pneumothorax and c.pneumothorax.tension and (c.pneumothorax.pressure or 0) >= 100 then why = 'tension' end
    if not why and c.tamponade and (c.tamponade.ml or 0) >= K.tamponadeArrest then why = 'tamponade' end
    if not why and p.temp < 28 then why = 'hypothermia' end
    if not why and c.overdose and c.overdose.drug == 'stimulant' and (c.overdose.amount or 0) >= 90
        and math.random() < 0.005 * dt then why = 'stimulant' end
    if why then
        transition(p, 'arrest', why)
        return
    end

    -- the bleed-out clock (§6)
    if state == 'wounded' then
        if p.stabilized then
            p.clockRate = 0
        else
            local ttd = Phys.TimeToDeath(p, total)
            local maxC = cfg('Wounded', 'maxClock', 300)
            local target = math.min(maxC, ttd)
            local prev = r.prevBleed
            if prev and prev > 0 and total < prev * 0.95 and target > (p.clock or 0) then
                -- treatment slowed the bleed: give part of the time back
                p.clock = p.clock + (target - p.clock) * (1 - total / prev)
            end
            -- real time while the bleed is significant, slower for a minor ooze
            local rate = clamp(total / 10, 0.25, 1.0)
            p.clockRate = rate
            p.clock = (p.clock or maxC) - dt * rate
            local inGrace = p.downAt and (now - p.downAt) < minClock
            if not inGrace and ttd < p.clock then p.clock = ttd end
            if p.clock > maxC then p.clock = maxC end
            if p.clock <= 0 then
                p.clock = 0
                transition(p, cfg('Death', 'bleedOutDeath', true) and 'dead' or 'arrest', 'bleedout')
                return
            end
        end
    end
    r.prevBleed = total

    -- alive → wounded
    if state == 'alive' then
        local lossDown = cfg('Wounded', 'lossDown', 0.30)
        if loss >= lossDown or v.avpu == 'P' or v.avpu == 'U' then
            local to = 'wounded'
            if p.kind == 'player' and cfg('Wounded', 'enabled', true) == false then to = 'arrest' end
            transition(p, to, loss >= lossDown and 'blood_loss' or 'unconscious')
            return
        end
    end

    P.Touch(p)
end

-- Short-lived vitals offset from a module, keyed so several can run side by side. mod =
-- { sys, dia, hr, ttl = seconds (default 3, 1..60) }; nil / false removes it. Call it again before
-- ttl runs out to keep it. Added to the living patient's targets before smoothing (not in arrest).
function Phys.SetModifier(pid, key, mod)
    local p = P.Resolve(pid)
    if not p or key == nil then return false end
    local r = P.RT(p)
    if mod == nil or mod == false then
        if r.mods then
            r.mods[key] = nil
            if next(r.mods) == nil then r.mods = nil end
        end
        return true
    end
    if type(mod) ~= 'table' then return false end
    r.mods = r.mods or {}
    r.mods[key] = {
        sys = clamp(tonumber(mod.sys) or 0, -120, 120),
        dia = clamp(tonumber(mod.dia) or 0, -80, 80),
        hr = clamp(tonumber(mod.hr) or 0, -120, 120),
        exp = os.time() + clamp(tonumber(mod.ttl) or 3, 1, 60),
    }
    return true
end

function Phys.Tick(dt)
    local now = os.time()
    local list = {}
    for _, p in pairs(P.All()) do list[#list + 1] = p end
    for i = 1, #list do
        local p = list[i]
        if P.Get(p.pid) == p and needsTick(p) then
            local ok, err = pcall(Phys.Update, p, dt, now)
            if not ok then NZA.Warn(('physiology failed for %s: %s'):format(tostring(p.pid), tostring(err))) end
        end
    end
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(math.max(250, cfg('Physiology', 'tick', 1000)))
        local nowMs = GetGameTimer()
        local dt = (nowMs - last) / 1000
        last = nowMs
        if dt > 5 then dt = 5 end      -- server hitch: don't jump minutes ahead
        if dt > 0 then Phys.Tick(dt) end
    end
end)
