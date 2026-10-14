--[[
    NAYZEEE AMBULANCE - Injury factory (NZA.Injury)

    Turns a short definition { region, type, severity } into a complete Injury table
    (ARCHITECTURE §4) with believable detail: wound size, depth, retained bullets or
    fragments, fracture kind/bone/displacement, burn degree/area/temperature/soot,
    internal organ and vessel. It also derives the complications a wound causes
    (haemothorax, pneumothorax, tamponade, internal bleeds, concussion, spinal
    injury, airway swelling) — NZA.Patients.AddInjury calls both.

    NZA.Injury.Build(p, def)            → Injury | nil, err   (not inserted)
    NZA.Injury.Complications(p, inj)    applies derived injuries/conditions through NZA.Patients
    NZA.Injury.BurnSeverity(burn)       → 1..4
    NZA.Injury.BaseBleed(type, region, severity, organ) → mL/min before treatment
    NZA.Injury.Bones / Organs / Vessels lookup tables (keys are localised as core.bone_* / core.organ_* / core.vessel_*)

    No events or callbacks are registered here.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Injury = NZA.Injury or {}
local I = NZA.Injury

local function rnd(a, b) return a + math.random() * (b - a) end
local function irnd(a, b) return math.random(math.floor(a), math.floor(b)) end
local function chance(p) return math.random() < p end
local function pick(list) return list[math.random(#list)] end
local function r1(n) return math.floor(n * 10 + 0.5) / 10 end
local function r3(n) return math.floor(n * 1000 + 0.5) / 1000 end

-- ════════════════════════════════════════════════════════════════════════
-- ANATOMY TABLES
-- ════════════════════════════════════════════════════════════════════════

I.Bones = {
    head        = { 'skull' },
    face        = { 'mandible', 'orbit', 'nasal', 'zygoma' },
    neck        = { 'c_spine' },
    chest       = { 'ribs', 'ribs', 'sternum', 'clavicle' },
    back        = { 't_spine', 'scapula', 'ribs' },
    abdomen     = { 'l_spine' },
    pelvis      = { 'pelvis', 'pelvis', 'acetabulum', 'sacrum' },
    l_upper_arm = { 'humerus' },  r_upper_arm = { 'humerus' },
    l_lower_arm = { 'radius', 'ulna', 'radius_ulna' }, r_lower_arm = { 'radius', 'ulna', 'radius_ulna' },
    l_upper_leg = { 'femur' },    r_upper_leg = { 'femur' },
    l_lower_leg = { 'tibia', 'fibula', 'tibia_fibula' }, r_lower_leg = { 'tibia', 'fibula', 'tibia_fibula' },
}

-- region → weighted organ list for internal bleeding
I.Organs = {
    abdomen     = { { 'spleen', 3 }, { 'liver', 3 }, { 'bowel', 2 }, { 'mesenteric', 2 }, { 'kidney', 1 } },
    back        = { { 'kidney', 3 }, { 'liver', 1 }, { 'spleen', 1 } },
    pelvis      = { { 'pelvic', 4 }, { 'femoral', 1 }, { 'bowel', 1 } },
    chest       = { { 'lung', 1 } },
    head        = { { 'brain', 1 } },
    face        = { { 'brain', 1 } },
    neck        = { { 'carotid', 1 } },
    l_upper_leg = { { 'femoral', 1 } }, r_upper_leg = { { 'femoral', 1 } },
    l_lower_leg = { { 'tibial', 1 } },  r_lower_leg = { { 'tibial', 1 } },
    l_upper_arm = { { 'brachial', 1 } }, r_upper_arm = { { 'brachial', 1 } },
    l_lower_arm = { { 'radial', 1 } },  r_lower_arm = { { 'radial', 1 } },
}

I.Vessels = {
    spleen = { 'splenic' }, liver = { 'hepatic' }, kidney = { 'renal' },
    bowel = { 'jejunal', 'ileal' }, mesenteric = { 'sma', 'ima' },
    pelvic = { 'internal_iliac', 'superior_gluteal' }, femoral = { 'femoral', 'profunda' },
    lung = { 'intercostal' }, brain = { 'middle_meningeal' }, carotid = { 'carotid' },
    tibial = { 'tibial' }, brachial = { 'brachial' }, radial = { 'radial' },
}

-- how hard each organ bleeds relative to the type table
I.OrganBleed = {
    spleen = 1.2, liver = 1.3, kidney = 0.8, bowel = 0.6, mesenteric = 1.0, pelvic = 1.1,
    femoral = 1.4, lung = 0.7, brain = 0.35, carotid = 1.5, tibial = 0.6, brachial = 0.8, radial = 0.5,
}

I.Penetrating = { gunshot = true, shrapnel = true, stab = true }
-- open wounds that can get contaminated / infected
I.OpenTypes = { gunshot = true, shrapnel = true, stab = true, laceration = true, abrasion = true, burn = true }

local function timeScale()
    return (Config.Physiology and Config.Physiology.timeScale) or 1.0
end

function I.BaseBleed(kind, region, severity, organ)
    local T = NZA.Const.InjuryTypes[kind]
    local R = NZA.Const.Region[region]
    if not T or not R then return 0 end
    local base = T.bleed[severity] or T.bleed[#T.bleed]
    local mul = R.lethal
    if kind == 'internal' then
        mul = I.OrganBleed[organ or ''] or 1.0
    elseif kind == 'fracture' and (region == 'l_upper_leg' or region == 'r_upper_leg' or region == 'pelvis') then
        mul = 1.5 -- big bones bleed a lot into the tissue
    end
    return base * mul * timeScale()
end

function I.BurnSeverity(burn)
    local deg, area = burn.degree or 1, burn.area or 0
    if deg >= 3 then return area >= 10 and 4 or 3 end
    if deg == 2 then
        if area >= 60 then return 4 end
        if area >= 20 then return 3 end
        return 2
    end
    return area >= 50 and 2 or 1
end

-- ════════════════════════════════════════════════════════════════════════
-- SUB-TABLES
-- ════════════════════════════════════════════════════════════════════════

local function buildFracture(region, sev, over, cause)
    over = over or {}
    local kind
    if sev <= 1 then kind = 'closed'
    elseif sev == 2 then kind = chance(0.1) and 'open' or 'closed'
    elseif sev == 3 then
        local r = math.random()
        kind = r < 0.35 and 'open' or (r < 0.5 and 'comminuted' or 'closed')
    else
        local r = math.random()
        kind = r < 0.45 and 'comminuted' or (r < 0.85 and 'open' or 'closed')
    end
    if cause == 'gunshot' or cause == 'shrapnel' then
        kind = chance(0.6) and 'comminuted' or 'open'
    end
    local displaced = sev >= 2 and chance(0.35 + 0.15 * sev)
    local f = {
        kind = kind,
        bone = pick(I.Bones[region] or { 'bone' }),
        displaced = displaced,
        angle = displaced and irnd(8, 12 + sev * 8) or 0,
    }
    for k, v in pairs(over) do f[k] = v end
    return f
end

local function buildBurn(sev, over)
    over = over or {}
    local degree = over.degree or ({ 1, 2, chance(0.5) and 3 or 2, 3 })[sev]
    local area = over.area or math.floor(({ rnd(4, 15), rnd(12, 35), rnd(30, 60), rnd(55, 95) })[sev] + 0.5)
    local b = {
        degree = math.max(1, math.min(3, degree)),
        area = math.max(1, math.min(99, area)),
        temp = over.temp or r1(degree == 1 and rnd(40.5, 43) or (degree == 2 and rnd(44, 52) or rnd(52, 68))),
        soot = over.soot or irnd(40, 100),
        full = 0,
        exposure = over.exposure or sev,
    }
    b.full = over.full or (b.degree == 3 and irnd(35, 90) or 0)
    for k, v in pairs(over) do if b[k] == nil then b[k] = v end end
    return b
end

local function buildInternal(region, over)
    over = over or {}
    local organ = over.organ or NZA.Util.weightedPick(I.Organs[region] or { { 'mesenteric', 1 } })
    local vessel = over.vessel or pick(I.Vessels[organ] or { organ })
    local t = { organ = organ, vessel = vessel }
    for k, v in pairs(over) do if t[k] == nil then t[k] = v end end
    return t
end

local SIZE = {
    -- length mm, depth mm ranges by severity (min/max scaled by severity 1..4)
    gunshot    = { len = { 6, 14 },  dep = { 25, 140 } },
    shrapnel   = { len = { 4, 30 },  dep = { 8, 70 } },
    stab       = { len = { 15, 45 }, dep = { 25, 130 } },
    laceration = { len = { 20, 140 }, dep = { 2, 18 } },
    abrasion   = { len = { 25, 160 }, dep = { 1, 3 } },
    contusion  = { len = { 25, 130 }, dep = { 0, 0 } },
    fracture   = { len = { 0, 0 },   dep = { 0, 0 } },
    burn       = { len = { 0, 0 },   dep = { 0, 0 } },
    internal   = { len = { 0, 0 },   dep = { 0, 0 } },
}

local function sized(range, sev)
    local lo, hi = range[1], range[2]
    if hi <= 0 then return 0 end
    local step = (hi - lo) / 4
    return math.floor(rnd(lo + step * (sev - 1), lo + step * sev) + 0.5)
end

-- ════════════════════════════════════════════════════════════════════════
-- BUILD
-- ════════════════════════════════════════════════════════════════════════

function I.Build(p, def)
    if type(def) ~= 'table' then return nil, 'bad_def' end
    local C = NZA.Const
    local region, kind = def.region, def.type
    local R, T = C.Region[region], C.InjuryTypes[kind]
    if not R then return nil, 'bad_region' end
    if not T then return nil, 'bad_type' end

    local sev = math.floor(tonumber(def.severity) or 2)
    sev = math.max(1, math.min(4, sev))

    p.seq = (p.seq or 0) + 1
    local inj = {
        id = def.id or ('i' .. p.seq),
        region = region,
        type = kind,
        severity = sev,
        pain = 0,
        contamination = 0,
        length = 0, depth = 0,
        retained = 0, retainedDepth = 0,
        spot = def.spot or { x = r3(rnd(0.2, 0.8)), y = r3(rnd(0.15, 0.85)) },
        treat = {},
        quality = {},
        status = 'open',
        heal = 0,
        created = def.created or os.time(),
        weapon = def.weapon,
    }

    -- sub-tables first (burn severity is derived from the burn itself)
    if kind == 'fracture' then
        inj.fracture = buildFracture(region, sev, def.fracture, def.cause)
    elseif kind == 'burn' then
        inj.burn = buildBurn(sev, def.burn)
        if not def.severity then
            sev = I.BurnSeverity(inj.burn)
            inj.severity = sev
        end
    elseif kind == 'internal' then
        inj.internal = buildInternal(region, def.internal)
    end

    -- size
    local sz = SIZE[kind]
    inj.length = def.length or sized(sz.len, sev)
    inj.depth = def.depth or sized(sz.dep, sev)

    -- retained projectiles / fragments
    if def.retained ~= nil then
        inj.retained = math.max(0, math.floor(tonumber(def.retained) or 0))
    elseif (T.retained or 0) > 0 and chance(T.retained) then
        if kind == 'shrapnel' then
            inj.retained = irnd(1, 1 + sev)
        else
            inj.retained = (sev >= 4 and chance(0.3)) and 2 or 1
        end
    end
    if inj.retained > 0 then
        inj.retainedDepth = def.retainedDepth or math.min(80, math.max(6, math.floor(rnd(0.35, 0.9) * math.max(inj.depth, 12))))
    end
    if kind == 'gunshot' then
        -- a bullet that stayed in has no exit wound
        if def.exit ~= nil then inj.exit = def.exit else inj.exit = inj.retained == 0 end
    end

    -- pain & contamination
    inj.pain = def.pain or math.max(0, math.min(100, (T.pain[sev] or 40) + irnd(-5, 5)))
    local cont = (T.contamination or 0) * rnd(0.7, 1.3)
    if kind == 'burn' and inj.burn then cont = cont + (inj.burn.soot or 0) * 0.15 end
    if kind == 'fracture' and inj.fracture and inj.fracture.kind == 'open' then cont = 45 * rnd(0.8, 1.2) end
    if kind == 'internal' and inj.internal and inj.internal.organ == 'bowel' then cont = 60 end
    inj.contamination = def.contamination or math.floor(math.max(0, math.min(100, cont)) + 0.5)

    -- bleeding
    local base = I.BaseBleed(kind, region, sev, inj.internal and inj.internal.organ)
    if kind == 'fracture' and inj.fracture and inj.fracture.kind ~= 'closed' then base = base * 1.3 end
    base = base * rnd(0.9, 1.1)
    inj.bleedBase = r1(def.bleedBase or base)
    inj.bleed = inj.bleedBase

    -- optional overrides
    if type(def.treat) == 'table' then for k, v in pairs(def.treat) do inj.treat[k] = v end end
    if type(def.quality) == 'table' then for k, v in pairs(def.quality) do inj.quality[k] = v end end
    if def.heal then inj.heal = math.max(0, math.min(100, tonumber(def.heal) or 0)) end
    if def.status then inj.status = def.status end
    if def.attacker then inj.attacker = def.attacker end
    if def.cause then inj.cause = def.cause end

    return inj
end

-- ════════════════════════════════════════════════════════════════════════
-- COMPLICATIONS — what a wound does to the rest of the body
-- ════════════════════════════════════════════════════════════════════════

local function sideOf(inj)
    local R = NZA.Const.Region[inj.region]
    if R and R.side == 'l' then return 'left' end
    if R and R.side == 'r' then return 'right' end
    -- front view: low x is the patient's right
    return (inj.spot and inj.spot.x or 0.5) < 0.5 and 'right' or 'left'
end

function I.Complications(p, inj)
    local P = NZA.Patients
    local kind, region, sev = inj.type, inj.region, inj.severity
    local cond = p.conditions
    local pen = I.Penetrating[kind]
    local now = os.time()

    -- ── chest & back: haemothorax, pneumothorax, tamponade
    if pen and (region == 'chest' or region == 'back') and sev >= 2 then
        if chance(({ 0, 0.45, 0.75, 0.95 })[sev]) then
            local share = inj.bleedBase * 0.4
            inj.bleedBase = r1(inj.bleedBase - share)
            local h = cond.haemothorax
            if h then
                h.rate = r1((h.rate or 0) + share)
                P.SetCondition(p.pid, 'haemothorax', h)
            else
                P.SetCondition(p.pid, 'haemothorax', { side = sideOf(inj), ml = 0, rate = r1(share), source = inj.id })
            end
        end
        if chance(({ 0, 0.25, 0.5, 0.65 })[sev]) then
            local tension = sev >= 3 and chance(0.35)
            local pn = cond.pneumothorax
            if pn then
                if tension and not pn.tension then
                    pn.tension, pn.pressure = true, pn.pressure or 0
                    P.SetCondition(p.pid, 'pneumothorax', pn)
                end
            else
                P.SetCondition(p.pid, 'pneumothorax', { side = sideOf(inj), size = irnd(15, 40), tension = tension, pressure = 0 })
            end
        end
        if region == 'chest' and (kind == 'gunshot' or kind == 'stab') and sev >= 3 and not cond.tamponade then
            if chance(sev >= 4 and 0.25 or 0.12) then
                P.SetCondition(p.pid, 'tamponade', { ml = 0, rate = r1(rnd(8, 18) * timeScale()) })
            end
        end
    end

    -- ── abdomen / pelvis / back: a penetrating wound usually hits something inside
    if pen and (region == 'abdomen' or region == 'pelvis' or region == 'back') and sev >= 2 then
        if chance(({ 0, 0.4, 0.75, 1.0 })[sev]) then
            local share = 0.4
            inj.bleedBase = r1(inj.bleedBase * (1 - share))
            P.AddInjury(p.pid, {
                region = region, type = 'internal', severity = math.max(1, sev - 1),
                weapon = inj.weapon, complications = false, cause = kind, spot = inj.spot,
            })
        end
    end

    -- ── fractures
    if kind == 'fracture' and inj.fracture then
        local bone = inj.fracture.bone
        if region == 'pelvis' and sev >= 3 and chance(0.8) then
            P.AddInjury(p.pid, { region = 'pelvis', type = 'internal', severity = math.max(1, sev - 1),
                internal = { organ = 'pelvic' }, complications = false, cause = 'fracture' })
        end
        if bone == 'ribs' and sev >= 3 then
            if not cond.pneumothorax and chance(0.35) then
                P.SetCondition(p.pid, 'pneumothorax', { side = sideOf(inj), size = irnd(10, 30), tension = sev >= 4 and chance(0.3), pressure = 0 })
            end
            if not cond.haemothorax and chance(0.3) then
                P.SetCondition(p.pid, 'haemothorax', { side = sideOf(inj), ml = 0, rate = r1(12 * sev * timeScale()) })
            end
        end
        if not cond.spinal then
            if bone == 'c_spine' and chance(0.7) then
                P.SetCondition(p.pid, 'spinal', { level = 'cervical', complete = sev >= 4 and chance(0.4) })
            elseif bone == 't_spine' and chance(0.5) then
                P.SetCondition(p.pid, 'spinal', { level = 'thoracic', complete = sev >= 4 and chance(0.3) })
            elseif bone == 'l_spine' and chance(0.5) then
                P.SetCondition(p.pid, 'spinal', { level = 'lumbar', complete = false })
            end
        end
        if bone == 'skull' then
            local c = cond.concussion
            local grade = math.min(3, sev)
            if not c or (c.grade or 0) < grade then
                P.SetCondition(p.pid, 'concussion', { grade = grade, since = now })
            end
        end
    end

    -- ── head trauma → concussion
    if region == 'head' and (kind == 'gunshot' or kind == 'contusion' or kind == 'shrapnel') and sev >= 2 then
        local p2 = (kind == 'contusion' and sev == 2) and 0.5 or 1.0
        if chance(p2) then
            local grade = sev >= 4 and 3 or (sev - 1)
            local c = cond.concussion
            if not c or (c.grade or 0) < grade then
                P.SetCondition(p.pid, 'concussion', { grade = grade, since = now })
            end
        end
    end

    -- ── airway: bleeding/swelling in the face & neck, inhalation burns
    if not cond.airway then
        if pen and (region == 'neck' or region == 'face') and sev >= 3 and chance(0.3) then
            P.SetCondition(p.pid, 'airway', { kind = 'swelling', level = irnd(20, 50) })
        elseif kind == 'burn' and (region == 'face' or region == 'neck') and inj.burn and inj.burn.degree >= 2 and chance(0.4) then
            P.SetCondition(p.pid, 'airway', { kind = 'swelling', level = irnd(10, 30) })
        end
    end
end
