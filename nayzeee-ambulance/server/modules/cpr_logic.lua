--[[
    NAYZEEE AMBULANCE - CPR (server): clinical maths                    NZA.Cpr.Logic

    Pure functions used by server/modules/cpr.lua (no events, no state of its own):

      Logic.Compression(d, fatigue, easy) → quality 0..100
          d = { timing, depth, recoil (0..100 each, from the client), rate (/min) }
          depth is reduced by the server-side fatigue of the compressor; a rate outside
          Config.Cpr.Compressions.rateMin..rateMax costs quality.
      Logic.Breath(hold, bvm, easy) → quality 0..100        one rescue breath
      Logic.Chance(code, p, kind, opts) → chance 0..1, factors
          kind 'shock' (opts.energy, opts.touching) | 'pea' | 'asystole'
          factors = { quality, ccf, energy, adrenaline, time, vent, causes, rescuer } for the debrief
      Logic.AfterShock(code, p) → new rhythm | nil         rhythm after a failed shock
      Logic.Evolve(code, p) → 'rosc' | new rhythm | nil    rhythm check on a non-shockable rhythm
      Logic.Causes(p, code) → { { k, s, v } }              reversible causes (Hs & Ts) for the device
          s = 'suspect' | 'treating' | 'ok' | 'unknown'
      Logic.Score(code) → score 0..100, parts              code performance (grade on the debrief)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Cpr = NZA.Cpr or {}
NZA.Cpr.Logic = NZA.Cpr.Logic or {}
local Logic = NZA.Cpr.Logic

local function cfg() return Config.Cpr or {} end
local function sub(name) return cfg()[name] or {} end

local function clamp(n, lo, hi)
    n = tonumber(n) or lo
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function round(n) return math.floor(n + 0.5) end

-- interpolate { { x, y }, ... } (sorted by x)
local function interp(points, x)
    if type(points) ~= 'table' or #points == 0 then return 1.0 end
    if x <= points[1][1] then return points[1][2] end
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        if x <= b[1] then
            local t = (x - a[1]) / math.max(1e-6, b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t
        end
    end
    return points[#points][2]
end
Logic.Interp = interp

local function causeCfg(name)
    local c = (sub('Rosc').causes or {})[name]
    return c
end

local function easyScore()
    return clamp((Config.EasyMode or {}).score or 78, 0, 100)
end

-- ════════════════════════════════════════════════════════════════════════
-- COMPRESSIONS & BREATHS
-- ════════════════════════════════════════════════════════════════════════

function Logic.Compression(d, fatigue, easy)
    local cc = sub('Compressions')
    if easy then return easyScore() end
    local timing = clamp(d.timing, 0, 100)
    local depth = clamp(d.depth, 0, 100) * (1 - clamp(fatigue or 0, 0, 100) / 100)
    local recoil = clamp(d.recoil, 0, 100)
    local q = timing * 0.45 + depth * 0.35 + recoil * 0.20
    local rate = clamp(d.rate, 0, 240)
    local lo, hi = cc.rateMin or 100, cc.rateMax or 120
    if rate > 0 and (rate < lo or rate > hi) then
        local off = rate < lo and (lo - rate) or (rate - hi)
        q = q * math.max(0.4, 1 - off / 60)
    end
    return clamp(q, 0, 100)
end

function Logic.Breath(hold, bvm, easy)
    local b = sub('Breaths')
    if easy then return easyScore() end
    hold = clamp(hold, 0, 6)
    local target = (b.hold or 1.0) * (bvm and 1 or (b.mouthSlower or 1.25))
    local short = (b.tooShort or 0.55) * (bvm and 1 or (b.mouthSlower or 1.25))
    local long = (b.tooLong or 1.7) * (bvm and 1 or (b.mouthSlower or 1.25))
    local q
    if hold < short then
        q = 25 * hold / math.max(0.05, short)
    elseif hold > long then
        q = 35                                -- over-inflation: air in the stomach
    else
        local off = math.abs(hold - target) / math.max(0.1, long - short)
        q = 100 - off * 70
    end
    if not bvm then q = q * clamp(b.mouthQuality or 60, 0, 100) / 100 end
    return clamp(q, 0, 100)
end

-- ════════════════════════════════════════════════════════════════════════
-- ROSC CHANCE
-- ════════════════════════════════════════════════════════════════════════

local function med(p, name)
    local e = p.meds and p.meds[name]
    return e ~= nil and e > os.time()
end

-- untreated reversible causes → product factor + the names that hurt
local function causesFactor(p, code)
    local f, hurt = 1.0, {}
    local c = p.conditions or {}
    local loss = NZA.Patients.Loss(p)
    local hv = causeCfg('hypovolemia') or {}
    if loss >= (hv.loss or 0.38) then
        f = f * (hv.factor or 0.25); hurt[#hurt + 1] = 'hypovolemia'
    elseif loss >= (hv.soft or 0.32) then
        f = f * (hv.softFactor or 0.6); hurt[#hurt + 1] = 'hypovolemia'
    end
    if c.pneumothorax and c.pneumothorax.tension then
        f = f * (causeCfg('tension') or 0.08); hurt[#hurt + 1] = 'tension'
    end
    local tp = causeCfg('tamponade') or {}
    if c.tamponade and (tonumber(c.tamponade.ml) or 0) >= (tp.ml or 100) then
        f = f * (tp.factor or 0.08); hurt[#hurt + 1] = 'tamponade'
    end
    local hx = causeCfg('haemothorax') or {}
    if c.haemothorax and (tonumber(c.haemothorax.ml) or 0) >= (hx.ml or 1500) then
        f = f * (hx.factor or 0.5); hurt[#hurt + 1] = 'haemothorax'
    end
    local ht = causeCfg('hypothermia') or {}
    local temp = tonumber(p.temp) or 37
    if temp < (ht.temp or 30) then
        f = f * (ht.factor or 0.3); hurt[#hurt + 1] = 'hypothermia'
    elseif temp < (ht.soft or 32) then
        f = f * (ht.softFactor or 0.7); hurt[#hurt + 1] = 'hypothermia'
    end
    local hy = causeCfg('hypoxia') or {}
    if c.hypoxia then
        local level = math.max(tonumber(c.hypoxia.water) or 0, tonumber(c.hypoxia.smoke) or 0)
        if level >= (hy.level or 40) then
            local vent = code and code.vent or 0
            f = f * ((vent >= 70) and (hy.ventilated or 0.85) or (hy.factor or 0.45)); hurt[#hurt + 1] = 'hypoxia'
        end
    end
    if c.airway and c.airway.kind == 'obstructed' and not (p.devices and p.devices.intubated) then
        f = f * (causeCfg('airway') or 0.3); hurt[#hurt + 1] = 'airway'
    end
    local tx = causeCfg('toxins') or {}
    if c.overdose and (tonumber(c.overdose.amount) or 0) >= (tx.amount or 50) and not med(p, 'naloxone') then
        f = f * (tx.factor or 0.5); hurt[#hurt + 1] = 'toxins'
    end
    return f, hurt
end
Logic.CausesFactor = causesFactor

function Logic.Chance(code, p, kind, opts)
    opts = opts or {}
    local R = sub('Rosc')
    local now = os.time()
    local base
    if kind == 'shock' then base = R.shockBase or 0.42
    elseif kind == 'asystole' then base = R.asystoleBase or 0.06
    else base = R.peaBase or 0.22 end

    local q = clamp(code.quality or 0, 0, 100) / 100
    local fq = 0.30 + 0.70 * (q ^ 1.25)
    local ccf = (code.elapsed or 0) > 5 and clamp((code.handsOn or 0) / code.elapsed, 0, 1) or 0.6
    local fccf = clamp(0.55 + ccf * 0.55, 0.55, 1.1)
    local fe = 1.0
    if kind == 'shock' then fe = interp(R.energy, tonumber(opts.energy) or 200) end

    local fa = 1.0
    if med(p, 'adrenaline') then
        fa = R.adrenaline or 1.3
    elseif ((code.shocks or 0) + (code.checks or 0)) >= 3 and (code.adrenaline and code.adrenaline.n or 0) == 0 then
        fa = R.noAdrenaline or 0.8
    end

    local arrestAt = p.arrestAt or code.arrestAt or now
    local total = math.max(0, now - arrestAt) / 60
    local noFlow = math.max(0, code.noFlow or 0) / 60
    local lowFlow = math.max(0, total - noFlow)
    local ft = clamp(1 - lowFlow * (R.lowFlowDecay or 0.035) - noFlow * (R.noFlowDecay or 0.11), R.minTime or 0.15, 1)

    local w = clamp(R.ventilation or 0.4, 0, 1)
    local vent = clamp(code.vent or 50, 0, 100) / 100
    if code.continuous then vent = 1 end
    local fv = (1 - w) + w * vent

    local fc, hurt = causesFactor(p, code)
    local fr = opts.touching and clamp(((sub('Defib').rescuerShock or {}).efficacy or 0.4), 0, 1) or 1

    local chance = base * fq * fccf * fe * fa * ft * fv * fc * fr
    chance = clamp(chance, 0, R.max or 0.88)
    return chance, {
        base = base, quality = fq, ccf = fccf, energy = fe, adrenaline = fa, time = ft,
        vent = fv, causes = fc, hurt = hurt, rescuer = fr,
    }
end

local function setRhythm(p, rhythm)
    local a = p.conditions and p.conditions.arrest
    if not a or a.rhythm == rhythm then return end
    NZA.Patients.SetCondition(p.pid, 'arrest', { rhythm = rhythm, since = a.since or os.time(), cause = a.cause })
end
Logic.SetRhythm = setRhythm

function Logic.AfterShock(code, p)
    local a = p.conditions and p.conditions.arrest
    if not a then return nil end
    local R = sub('Rosc')
    local q = code.quality or 0
    local roll = math.random()
    local new = a.rhythm
    if a.rhythm == 'vt' then
        if roll < 0.55 then new = 'vf' end
    elseif a.rhythm == 'vf' then
        local degrade = (R.degrade or 0.12) * (q < 50 and 1.6 or 0.6)
        if roll < degrade then new = 'asystole'
        elseif roll < degrade + 0.12 then new = 'pea' end
    end
    if new ~= a.rhythm then setRhythm(p, new); return new end
    return nil
end

function Logic.Evolve(code, p)
    local a = p.conditions and p.conditions.arrest
    if not a then return nil end
    local R = sub('Rosc')
    local rhythm = a.rhythm
    if rhythm == 'pea' or rhythm == 'asystole' then
        local chance = Logic.Chance(code, p, rhythm)
        if math.random() < chance then return 'rosc' end
        local roll = math.random()
        if rhythm == 'asystole' and med(p, 'adrenaline') and roll < (R.asystoleToVf or 0.14) then
            setRhythm(p, 'vf'); return 'vf'
        end
        if rhythm == 'pea' then
            if roll < (R.peaToVf or 0.08) then setRhythm(p, 'vf'); return 'vf' end
            if (code.quality or 0) < 40 and roll > 0.8 then setRhythm(p, 'asystole'); return 'asystole' end
        end
        return nil
    end
    if rhythm == 'vt' and math.random() < 0.3 then setRhythm(p, 'vf'); return 'vf' end
    if rhythm == 'vf' and (code.quality or 0) < 35 and math.random() < (R.degrade or 0.12) then
        setRhythm(p, 'asystole'); return 'asystole'
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════════
-- REVERSIBLE CAUSES (what the code team can know)
-- ════════════════════════════════════════════════════════════════════════

local function finding(p, cond)
    local fs = p.meta and p.meta.findings
    if type(fs) ~= 'table' then return nil end
    for key, f in pairs(fs) do
        if type(f) == 'table' and (f.cond == cond or (type(key) == 'string' and key:sub(1, #cond) == cond)) then
            return f
        end
    end
    return nil
end

local function infusing(p, kinds)
    for _, inf in ipairs(p.infusions or {}) do
        if kinds[inf.kind] and (tonumber(inf.left) or 0) > 0 and not inf.paused then return true end
    end
    return false
end

function Logic.Causes(p, code)
    local out = {}
    local c = p.conditions or {}
    local cause = (p.cause and p.cause.reason) or (c.arrest and c.arrest.cause) or ''

    -- hypovolaemia: blood on scene / shock index - visible to the team
    local loss = NZA.Patients.Loss(p)
    local lost = math.floor((p.bloodMax or 5000) * loss / 100 + 0.5) / 10
    local hv = causeCfg('hypovolemia') or {}
    local s = 'ok'
    if loss >= (hv.soft or 0.32) - 0.07 then s = 'suspect' end
    if s == 'suspect' and infusing(p, { blood = true, saline = true, plasma = true }) then s = 'treating' end
    out[#out + 1] = { k = 'hypovolemia', s = s, v = lost > 0.1 and ('~%.1f L'):format(lost) or nil }

    -- hypoxia: drowning / smoke / obstructed airway / poor ventilation
    s = 'ok'
    local hx = c.hypoxia
    if hx or cause == 'drowning' or cause == 'hypoxia' or (c.airway and c.airway.kind == 'obstructed') then s = 'suspect' end
    if code and not code.continuous and (code.ventN or 0) >= 2 and (code.vent or 0) < 45 then s = 'suspect' end
    if s == 'suspect' and code and ((code.vent or 0) >= 70 or code.continuous) and not (c.airway and c.airway.kind == 'obstructed') then s = 'treating' end
    out[#out + 1] = { k = 'hypoxia', s = s, v = code and (code.continuous and 'ETT' or (code.ventN or 0) > 0 and (round(code.vent or 0) .. '%')) or nil }

    -- hypothermia: thermometer
    local temp = tonumber(p.temp) or 37
    s = temp < 35 and 'suspect' or 'ok'
    if s == 'suspect' and p.devices and p.devices.foil then s = 'treating' end
    out[#out + 1] = { k = 'hypothermia', s = s, v = ('%.1f°'):format(temp) }

    -- tension pneumothorax / tamponade: only known once someone found them (auscultation, eFAST)
    local pn = c.pneumothorax
    s = 'unknown'
    if finding(p, 'pneumothorax') then s = (pn and pn.tension) and 'suspect' or 'treating' end
    if not pn and finding(p, 'pneumothorax') then s = 'ok' end
    out[#out + 1] = { k = 'tension', s = s }

    s = 'unknown'
    if finding(p, 'tamponade') then
        s = (c.tamponade and (tonumber(c.tamponade.ml) or 0) >= ((causeCfg('tamponade') or {}).ml or 100)) and 'suspect' or 'treating'
    end
    out[#out + 1] = { k = 'tamponade', s = s }

    -- toxins: overdose history / pinpoint pupils
    s = 'unknown'
    if c.overdose or cause == 'overdose' or cause == 'opioid' or finding(p, 'overdose') then
        s = med(p, 'naloxone') and 'treating' or 'suspect'
    end
    out[#out + 1] = { k = 'toxins', s = s }
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- SCORE
-- ════════════════════════════════════════════════════════════════════════

function Logic.Score(code)
    local q = (code.qN or 0) > 0 and (code.qSum / code.qN) or 0
    local ccf = (code.elapsed or 0) > 0 and clamp((code.handsOn or 0) / code.elapsed, 0, 1) or 0
    local vent = code.continuous and 100 or ((code.ventN or 0) > 0 and code.vent or 0)
    local protocol = 100
    protocol = protocol - 25 * (code.rescuerShocks or 0)
    protocol = protocol - 15 * (code.badShocks or 0)
    protocol = protocol - 10 * (code.longPauses or 0)
    protocol = protocol - 8 * (code.motionAborts or 0)
    if code.needAdrenaline and (code.adrenaline and code.adrenaline.n or 0) == 0 then protocol = protocol - 15 end
    protocol = clamp(protocol, 0, 100)
    local score = q * 0.40 + ccf * 100 * 0.25 + vent * 0.15 + protocol * 0.20
    return clamp(round(score), 0, 100), {
        quality = round(q), ccf = round(ccf * 100), vent = round(vent), protocol = round(protocol),
    }
end
