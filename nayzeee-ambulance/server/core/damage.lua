--[[
    NAYZEEE AMBULANCE - Damage → injuries (NZA.Damage)             ARCHITECTURE §17

    Turns the damage a player's client reports about ITSELF into injuries:
      weapons      weapon hash → Config.Damage.weapons override (keys are weapon names,
                   compared with joaat) → weapon group hash (client sends it; compared with
                   joaat('GROUP_PISTOL') ...) → Config.Damage.groups
      severity     GTA damage → Config.Damage.severityByDamage
      falls        fractures by height (Config.Damage.fall)
      crashes      speed lost in one tick, scaled by the seatbelt factor (Config.Damage.vehicle)
      fire         burns grow in area/degree on the same region instead of stacking, + smoke
      drowning     water in the lungs → hypoxia condition
      headshots    severe head/neck gunshots may stop the heart (Config.Damage.headshotArrest)
    Repeated hits on the same region+type stack as separate wounds up to 12 injuries,
    then merge into a worse injury. Contusions, abrasions, fractures and burns always merge.

    Net events (C→S, registered here):
      nza:damage  { weapon, group, bone, region, damage, attacker, attackerNet, melee,
                    fall, speedDrop, seatbelt, fire, drown }
      nza:down    { weapon, group, attacker, region }  GTA health hit 0, client stood back up in place

    API
      NZA.Damage.Apply(p, data, src, forced)    apply one damage report (also usable by modules; missing
                                                numbers default to 0, forced = ignore Config.Damage.minDamage)
      NZA.Damage.Sanitize(raw) → report         the clamping applied to client reports
      NZA.Damage.AddOrMerge(p, region, type, severity, extra) → Injury
      NZA.Damage.Burn(p, region, intensity, extra)          → Injury
      NZA.Damage.Drown(p, ml)
      NZA.Damage.Fall(p, height)   NZA.Damage.Crash(p, speedDrop, belted)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Damage = NZA.Damage or {}
NZA.Patients = NZA.Patients or {}
NZA.Core = NZA.Core or {}
local D = NZA.Damage
local P = NZA.Patients
local Core = NZA.Core

local MERGE_ALWAYS = { contusion = true, abrasion = true, fracture = true, burn = true }

local function maxInjuries() return (NZA.Injury and NZA.Injury.MaxInjuries) or 12 end

local function cfg(key, default)
    local s = Config.Damage
    if s == nil or s[key] == nil then return default end
    return s[key]
end

local function hash(name)
    if joaat then return joaat(name) end
    return GetHashKey(name)
end

-- hashes arrive signed or unsigned depending on the native that produced them
local function u32(h)
    h = tonumber(h)
    if not h then return nil end
    return math.floor(h) % 4294967296
end

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function num(v, lo, hi, def)
    v = tonumber(v)
    if not v or v ~= v then return def end
    return clamp(v, lo, hi)
end

-- ════════════════════════════════════════════════════════════════════════
-- WEAPON LOOKUP (built once, lazily — Config is final by then)
-- ════════════════════════════════════════════════════════════════════════

local weaponMap, groupMap, groupName, special

local function build()
    if weaponMap then return end
    weaponMap, groupMap, groupName = {}, {}, {}
    for name, types in pairs(cfg('weapons', {})) do
        weaponMap[u32(hash(name))] = types
    end
    for name, types in pairs(cfg('groups', {})) do
        local h = u32(hash(name))
        groupMap[h] = types
        groupName[h] = name
    end
    special = {
        fall = u32(hash('WEAPON_FALL')),
        explosion = u32(hash('WEAPON_EXPLOSION')),
        runover = u32(hash('WEAPON_RUN_OVER_BY_CAR')),
        rammed = u32(hash('WEAPON_RAMMED_BY_CAR')),
        fire = u32(hash('WEAPON_FIRE')),
        drown = u32(hash('WEAPON_DROWNING')),
        drownVeh = u32(hash('WEAPON_DROWNING_IN_VEHICLE')),
        bleeding = u32(hash('WEAPON_BLEEDING')),
        exhaustion = u32(hash('WEAPON_EXHAUSTION')),
        melee = u32(hash('GROUP_MELEE')),
        unarmed = u32(hash('GROUP_UNARMED')),
        heavy = u32(hash('GROUP_HEAVY')),
        thrown = u32(hash('GROUP_THROWN')),
    }
end

function D.Rebuild()
    weaponMap = nil
    build()
end

local function typesFor(d)
    build()
    local w = u32(d.weapon)
    if w and weaponMap[w] ~= nil then return weaponMap[w] end
    local g
    if type(d.group) == 'string' then g = u32(hash(d.group)) else g = u32(d.group) end
    if g and groupMap[g] then return groupMap[g], g end
    if d.melee then return { 'contusion' }, special.melee end
    return { 'contusion' }, nil
end

local function severityFor(dmg)
    local t = cfg('severityByDamage', { 15, 35, 60 })
    if dmg >= (t[3] or 60) then return 4 end
    if dmg >= (t[2] or 35) then return 3 end
    if dmg >= (t[1] or 15) then return 2 end
    return 1
end

-- ════════════════════════════════════════════════════════════════════════
-- REGIONS
-- ════════════════════════════════════════════════════════════════════════

local TORSO_WEIGHTS = {
    { 'chest', 4 }, { 'abdomen', 3 }, { 'back', 1 }, { 'pelvis', 1 }, { 'head', 1 },
    { 'l_upper_arm', 1 }, { 'r_upper_arm', 1 }, { 'l_upper_leg', 2 }, { 'r_upper_leg', 2 },
    { 'l_lower_leg', 1 }, { 'r_lower_leg', 1 }, { 'l_lower_arm', 1 }, { 'r_lower_arm', 1 },
}
local FIRE_WEIGHTS = {
    { 'l_lower_leg', 3 }, { 'r_lower_leg', 3 }, { 'l_upper_leg', 2 }, { 'r_upper_leg', 2 },
    { 'l_lower_arm', 2 }, { 'r_lower_arm', 2 }, { 'chest', 2 }, { 'abdomen', 1 }, { 'back', 2 },
    { 'face', 1 }, { 'l_upper_arm', 1 }, { 'r_upper_arm', 1 },
}

local function attackerPed(d)
    if d.attacker and d.attacker > 0 and Core.Online(d.attacker) then
        local ped = GetPlayerPed(d.attacker)
        if ped and ped ~= 0 then return ped end
    end
    if d.attackerNet then
        local ent = NetworkGetEntityFromNetworkId(d.attackerNet)
        if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    end
    return nil
end

-- Spine bones report 'chest'; a hit from behind is the back.
local function flipChest(region, d, src)
    if region ~= 'chest' or not src then return region end
    local ap = attackerPed(d)
    local victim = GetPlayerPed(src)
    if not ap or not victim or victim == 0 then return region end
    local vc, ac = GetEntityCoords(victim), GetEntityCoords(ap)
    local h = math.rad(GetEntityHeading(victim))
    local fx, fy = -math.sin(h), math.cos(h)
    if fx * (ac.x - vc.x) + fy * (ac.y - vc.y) < 0 then return 'back' end
    return region
end

local function resolveRegion(d, src)
    local region = d.region
    if not (region and NZA.Const.Region[region]) then
        region = d.bone and NZA.Const.BoneToRegion[d.bone] or nil
    end
    if not region then region = NZA.Util.weightedPick(TORSO_WEIGHTS) end
    return flipChest(region, d, src)
end

-- ════════════════════════════════════════════════════════════════════════
-- ADD OR MERGE
-- ════════════════════════════════════════════════════════════════════════

local PENETRATING = { gunshot = true, shrapnel = true, stab = true, laceration = true }

local function worsen(p, inj, sev, extra)
    local T = NZA.Const.InjuryTypes[inj.type]
    local newSev = math.max(inj.severity, sev)
    if sev >= inj.severity and inj.severity < 4 and math.random() < 0.5 then newSev = inj.severity + 1 end
    newSev = math.min(4, newSev)
    local base = NZA.Injury.BaseBleed(inj.type, inj.region, newSev, inj.internal and inj.internal.organ)
    local patch = {
        severity = newSev,
        bleedBase = math.floor(math.max(inj.bleedBase or 0, base) * 10 + 0.5) / 10,
        pain = math.max(inj.pain or 0, (T.pain[newSev] or 50)),
        heal = 0,
        weapon = (extra and extra.weapon) or inj.weapon,
    }
    if PENETRATING[inj.type] then
        -- another hole in the same spot: more blood (never beyond 1.5× the worst wound of
        -- that kind there), and the dressing is soaked through
        local ceiling = NZA.Injury.BaseBleed(inj.type, inj.region, 4) * 1.5
        local grown = math.min(ceiling, patch.bleedBase + (inj.bleedBase or 0) * 0.25)
        patch.bleedBase = math.floor(math.max(inj.bleedBase or 0, grown) * 10 + 0.5) / 10
        patch.treat = { bandaged = false, packed = false, sutured = false, dressed = false }
        patch.length = math.floor((inj.length or 0) * 1.2 + 0.5)
        patch.depth = math.min(160, math.floor((inj.depth or 0) * 1.1 + 0.5))
        if (T.retained or 0) > 0 and math.random() < T.retained then
            patch.retained = (inj.retained or 0) + 1
            patch.retainedDepth = inj.retainedDepth and inj.retainedDepth > 0 and inj.retainedDepth or math.random(10, 60)
        end
        patch.contamination = math.min(100, (inj.contamination or 0) + 10)
    elseif inj.type == 'fracture' and inj.fracture then
        local f = {}
        if newSev >= 2 and not inj.fracture.displaced and math.random() < 0.5 then
            f.displaced = true
            f.angle = math.random(10, 25)
        elseif inj.fracture.displaced then
            f.angle = math.min(60, (inj.fracture.angle or 10) + math.random(2, 8))
        end
        if newSev >= 4 and inj.fracture.kind == 'closed' and math.random() < 0.4 then f.kind = 'comminuted' end
        patch.fracture = f
        patch.treat = { reduced = false }
    elseif inj.type == 'contusion' or inj.type == 'abrasion' then
        patch.length = math.min(250, math.floor((inj.length or 30) * 1.25 + 0.5))
        if inj.type == 'abrasion' then patch.contamination = math.min(100, (inj.contamination or 0) + 8) end
    end
    return P.UpdateInjury(p.pid, inj.id, patch)
end

-- The body is full (12 injuries): make the worst wound in that region worse and return it,
-- or free a slot by replacing the most minor injury (returns nil → caller adds its injury).
function D.MakeRoom(p, region, sev, extra)
    if NZA.Util.tableCount(p.injuries) < maxInjuries() then return nil end
    local worst, minor
    for _, inj in pairs(p.injuries) do
        if inj.region == region and (not worst or inj.severity > worst.severity) then worst = inj end
        if not minor or inj.severity < minor.severity then minor = inj end
    end
    if worst then
        if worst.type == 'burn' then return D.Burn(p, region, sev, extra) end
        return worsen(p, worst, sev, extra)
    end
    if minor and minor.severity < sev then
        P.RemoveInjury(p.pid, minor.id)
        return nil
    end
    if minor.type == 'burn' then return D.Burn(p, minor.region, sev, extra) end
    return worsen(p, minor, sev, extra)
end

function D.AddOrMerge(p, region, kind, sev, extra)
    sev = math.floor(tonumber(sev) or 1)
    if sev < 1 or not NZA.Const.Region[region] or not NZA.Const.InjuryTypes[kind] then return nil end
    sev = math.min(4, sev)
    extra = extra or {}
    if kind == 'burn' then return D.Burn(p, region, sev, extra) end

    local same
    for _, inj in pairs(p.injuries) do
        if inj.region == region and inj.type == kind then
            if not same or inj.severity > same.severity then same = inj end
        end
    end
    local count = NZA.Util.tableCount(p.injuries)
    if same and (MERGE_ALWAYS[kind] or count >= maxInjuries()) then
        return worsen(p, same, sev, extra)
    end
    local merged = D.MakeRoom(p, region, sev, extra)
    if merged then return merged end
    local def = { region = region, type = kind, severity = sev, weapon = extra.weapon, attacker = extra.attacker, cause = extra.cause }
    if extra.fracture then def.fracture = extra.fracture end
    if extra.internal then def.internal = extra.internal end
    return P.AddInjury(p.pid, def)
end

-- Fire: an existing burn on the region grows (area, degree, temperature, soot)
function D.Burn(p, region, intensity, extra)
    extra = extra or {}
    intensity = intensity or 1
    local existing
    for _, inj in pairs(p.injuries) do
        if inj.region == region and inj.type == 'burn' then existing = inj break end
    end
    if not existing then
        local merged = D.MakeRoom(p, region, intensity, extra)
        if merged then return merged end
        local deg = intensity >= 4 and 3 or (intensity >= 3 and 2 or 1)
        local area = math.random(3, 8) * intensity
        return P.AddInjury(p.pid, {
            region = region, type = 'burn', weapon = extra.weapon, cause = extra.cause or 'fire',
            burn = { degree = deg, area = math.min(99, area), exposure = intensity, soot = extra.soot or math.random(50, 100) },
        })
    end
    local b = NZA.Util.deepcopy(existing.burn or { degree = 1, area = 5, temp = 42, soot = 60, full = 0, exposure = 1 })
    b.exposure = (b.exposure or 1) + intensity
    b.area = math.min(99, (b.area or 5) + math.random(2, 5) * intensity)
    local deg = b.exposure < 3 and 1 or (b.exposure < 7 and 2 or 3)
    if deg > (b.degree or 1) then b.degree = deg end
    if b.degree == 3 then b.full = math.min(100, math.max(b.full or 0, 30) + math.random(2, 6)) end
    b.temp = math.min(75, (b.temp or 42) + 1.5 * intensity)
    b.soot = math.min(100, (b.soot or 50) + 5)
    local sev = math.max(existing.severity, NZA.Injury.BurnSeverity(b))
    local T = NZA.Const.InjuryTypes.burn
    return P.UpdateInjury(p.pid, existing.id, {
        burn = b, severity = sev, heal = 0,
        bleedBase = math.floor(NZA.Injury.BaseBleed('burn', region, sev) * 10 + 0.5) / 10,
        pain = math.max(existing.pain or 0, T.pain[sev] or 60),
        treat = { cooled = false, dressed = false },
    })
end

function D.Drown(p, ml)
    local c = NZA.Util.deepcopy(p.conditions.hypoxia or {})
    c.cause = 'drowning'
    c.water = math.min(1500, (c.water or 0) + (ml or 60))
    c.smoke = c.smoke or 0
    P.SetCondition(p.pid, 'hypoxia', c)
    P.SetMeta(p.pid, 'wet', os.time() + 600)
end

local function smoke(p, amount)
    local c = NZA.Util.deepcopy(p.conditions.hypoxia or {})
    c.cause = c.cause or 'smoke'
    c.smoke = math.min(100, (c.smoke or 0) + amount)
    c.water = c.water or 0
    P.SetCondition(p.pid, 'hypoxia', c)
end

-- ════════════════════════════════════════════════════════════════════════
-- FALLS & CRASHES
-- ════════════════════════════════════════════════════════════════════════

local function otherSide(s) return s == 'l' and 'r' or 'l' end

function D.Fall(p, h, weapon)
    local fc = cfg('fall', { minHeight = 4.0, fractureHeight = 7.0 })
    if h < (fc.minHeight or 4.0) then return end
    local s = math.random() < 0.5 and 'l' or 'r'
    local ex = { weapon = weapon, cause = 'fall' }
    if h >= (fc.fractureHeight or 7.0) then
        local sev = h >= 20 and 4 or (h >= 13 and 3 or 2)
        D.AddOrMerge(p, s .. '_lower_leg', 'fracture', sev, ex)
        if h >= 10 and math.random() < 0.5 then D.AddOrMerge(p, otherSide(s) .. '_lower_leg', 'fracture', sev - 1, ex) end
        if h >= 12 and math.random() < 0.4 then D.AddOrMerge(p, s .. '_upper_leg', 'fracture', sev - 1, ex) end
        if h >= 14 and math.random() < 0.5 then D.AddOrMerge(p, 'pelvis', 'fracture', sev - 1, ex) end
        if h >= 16 and math.random() < 0.35 then
            D.AddOrMerge(p, 'back', 'fracture', 2, { weapon = weapon, cause = 'fall', fracture = { bone = 't_spine' } })
        end
        if h >= 18 then
            D.AddOrMerge(p, 'head', 'contusion', 3, ex)
            if math.random() < 0.5 then D.AddOrMerge(p, 'abdomen', 'internal', 2, ex) end
        end
        if math.random() < 0.45 then D.AddOrMerge(p, s .. '_lower_arm', 'fracture', math.random(1, 2), ex) end
        D.AddOrMerge(p, otherSide(s) .. '_lower_leg', 'contusion', 2, ex)
    else
        D.AddOrMerge(p, s .. '_lower_leg', math.random() < 0.3 and 'fracture' or 'contusion', h >= 5.5 and 2 or 1, ex)
        if math.random() < 0.5 then D.AddOrMerge(p, (math.random() < 0.5 and 'l' or 'r') .. '_lower_arm', 'abrasion', 1, ex) end
    end
end

function D.Crash(p, drop, belted, weapon)
    local vc = cfg('vehicle', {})
    if vc.enabled == false then return end
    local minDrop = vc.minSpeedDrop or 45.0
    local factor = belted and (vc.seatbeltFactor or 0.35) or 1.0
    local energy = (drop - minDrop) * factor
    local ex = { weapon = weapon, cause = 'crash' }
    if energy <= 0 then
        if belted then D.AddOrMerge(p, 'chest', 'contusion', 1, ex) end
        return
    end
    local base = energy < 20 and 1 or (energy < 45 and 2 or (energy < 80 and 3 or 4))
    D.AddOrMerge(p, 'chest', 'contusion', base, ex)
    if not belted then
        D.AddOrMerge(p, 'face', 'laceration', math.min(3, base), ex)
        if energy > 25 then D.AddOrMerge(p, 'head', 'contusion', base, ex) end
        if energy > 40 and math.random() < 0.5 then
            if math.random() < 0.5 then
                D.AddOrMerge(p, 'neck', 'fracture', base - 1, ex)
            elseif not p.conditions.spinal then
                P.SetCondition(p.pid, 'spinal', { level = 'cervical', complete = false, since = os.time() })
            end
        end
    end
    if energy > 30 then
        local leg = (math.random() < 0.5 and 'l' or 'r') .. (math.random() < 0.5 and '_lower_leg' or '_upper_leg')
        D.AddOrMerge(p, leg, 'fracture', base - 1, ex)
    end
    if energy > 45 then
        if math.random() < 0.5 then D.AddOrMerge(p, 'abdomen', 'internal', base - 1, ex) end
        if math.random() < 0.6 then
            D.AddOrMerge(p, 'chest', 'fracture', base - 1, { weapon = weapon, cause = 'crash', fracture = { bone = 'ribs' } })
        end
    end
    if energy > 70 and math.random() < 0.4 then D.AddOrMerge(p, 'pelvis', 'fracture', base - 1, ex) end
    if math.random() < 0.6 then
        D.AddOrMerge(p, (math.random() < 0.5 and 'l' or 'r') .. '_lower_arm', math.random() < 0.5 and 'abrasion' or 'laceration', math.max(1, base - 1), ex)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- APPLY
-- ════════════════════════════════════════════════════════════════════════

local function sanitize(data)
    local d = {}
    d.weapon = tonumber(data.weapon) or 0
    d.group = data.group or data.weaponGroup
    if type(d.group) ~= 'string' then d.group = tonumber(d.group) end
    d.bone = tonumber(data.bone)
    d.region = (type(data.region) == 'string' and NZA.Const.Region[data.region]) and data.region or nil
    d.damage = num(data.damage, 0, 400, 0)
    d.attacker = math.floor(num(data.attacker, 0, 65535, 0))
    d.attackerNet = tonumber(data.attackerNet)
    d.melee = data.melee == true
    d.fall = num(data.fall, 0, 300, 0)
    d.speedDrop = num(data.speedDrop, 0, 400, 0)
    d.seatbelt = data.seatbelt == true or (tonumber(data.belt) or 0) > 0.5
    d.fire = data.fire == true
    d.drown = data.drown == true
    return d
end
D.Sanitize = sanitize

function D.Apply(p, d, src, forced)
    if not p or p.state == 'dead' or type(d) ~= 'table' then return end
    build()
    -- modules may pass a partial report; every number below is compared directly
    d.weapon = tonumber(d.weapon) or 0
    d.damage = tonumber(d.damage) or 0
    d.fall = tonumber(d.fall) or 0
    d.speedDrop = tonumber(d.speedDrop) or 0
    d.attacker = math.floor(tonumber(d.attacker) or 0)
    if d.region and not NZA.Const.Region[d.region] then d.region = nil end
    local now = os.time()
    local r = P.RT(p)
    local downed = p.state ~= 'alive'
    local invincible = downed and (Config.Wounded and Config.Wounded.invincible ~= false)
    local w = u32(d.weapon)

    if w == special.bleeding or w == special.exhaustion then return end

    if d.drown or w == special.drown or w == special.drownVeh then
        if (cfg('drowning', {}).enabled ~= false) then D.Drown(p, 60) end
        return
    end

    if d.fire or w == special.fire then
        if (cfg('fire', {}).enabled ~= false) then
            local region = d.region or NZA.Util.weightedPick(FIRE_WEIGHTS)
            D.Burn(p, region, 1, { weapon = d.weapon, cause = 'fire' })
            if math.random() < 0.35 then D.Burn(p, NZA.Util.weightedPick(FIRE_WEIGHTS), 1, { weapon = d.weapon, cause = 'fire' }) end
            smoke(p, 6)
        end
        return
    end

    if d.fall >= (cfg('fall', {}).minHeight or 4.0) then
        D.Fall(p, d.fall, d.weapon)
        r.lastHit = { weapon = d.weapon, region = 'l_lower_leg', at = now, cause = 'fall' }
        if w == special.fall then return end
    elseif w == special.fall and d.damage >= cfg('minDamage', 4) then
        -- client could not measure the height: judge it by the damage
        D.Fall(p, d.damage >= 60 and 14 or (d.damage >= 30 and 8 or 5), d.weapon)
        return
    end

    if d.speedDrop >= ((cfg('vehicle', {}).minSpeedDrop) or 45.0) and cfg('vehicle', {}).enabled ~= false then
        D.Crash(p, d.speedDrop, d.seatbelt, d.weapon)
        r.lastHit = { weapon = d.weapon, region = 'chest', at = now, cause = 'crash' }
        return
    end

    if d.damage < cfg('minDamage', 4) and not forced then return end

    local list, group = typesFor(d)
    if list == false then return end
    if list == 'hypoxia' then
        D.Drown(p, 60)
        return
    end
    if type(list) == 'string' then list = { list } end
    if type(list) ~= 'table' or #list == 0 then return end

    local sev = severityFor(d.damage)
    local region = resolveRegion(d, src)
    local ex = { weapon = d.weapon, attacker = d.attacker > 0 and d.attacker or nil, cause = list[1] }
    local isMelee = d.melee or group == special.melee or group == special.unarmed
    local spread = w == special.explosion or w == special.runover or w == special.rammed
        or group == special.heavy or group == special.thrown

    local added = {}
    if isMelee and #list > 1 then
        local kind = math.random() < 0.6 and list[1] or list[math.random(2, #list)]
        if kind == 'fracture' and sev < 3 then kind = 'contusion' end
        added[#added + 1] = { kind, sev, region }
    else
        added[#added + 1] = { list[1], sev, region }
        for i = 2, #list do
            if spread or math.random() < 0.4 then added[#added + 1] = { list[i], sev - 1, region } end
        end
    end
    if spread then
        -- blasts and impacts hit more than one place
        for _ = 1, math.random(1, 3) do
            added[#added + 1] = { list[math.random(#list)], math.max(1, sev - 1), NZA.Util.weightedPick(TORSO_WEIGHTS) }
        end
    end

    local primary
    for _, a in ipairs(added) do
        local kind, s, reg = a[1], a[2], a[3]
        if kind == 'fracture' and s < 2 and not spread then kind = 'contusion' end
        local inj = D.AddOrMerge(p, reg, kind, s, ex)
        primary = primary or inj
    end
    r.lastHit = { weapon = d.weapon, attacker = ex.attacker, region = region, at = now, cause = list[1] }

    -- a severe head / neck gunshot may stop the heart outright
    if primary and (region == 'head' or region == 'neck') and primary.type == 'gunshot' and primary.severity >= 3
        and not invincible and p.state ~= 'arrest' then
        if math.random() < cfg('headshotArrest', 0.35) then
            P.SetState(p, 'arrest', { reason = 'headshot', weapon = d.weapon, attacker = ex.attacker, region = region, at = now })
            return
        end
    end
    -- without invincibility, massive trauma to a downed patient can stop the heart
    if downed and not invincible and p.state == 'wounded' and sev >= 4
        and (region == 'head' or region == 'neck' or region == 'chest') and math.random() < 0.5 then
        P.SetState(p, 'arrest', { reason = 'trauma', weapon = d.weapon, attacker = ex.attacker, region = region, at = now })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- NET EVENTS
-- ════════════════════════════════════════════════════════════════════════

local function patientFor(src)
    local p = P.GetBySource(src)
    if p then return p end
    return P.LoadPlayer(src)
end

RegisterNetEvent('nza:damage', function(data)
    local src = tonumber(source)
    if not src or src <= 0 or type(data) ~= 'table' then return end
    if Config.Damage and Config.Damage.enabled == false then return end
    if not Core.Rate('nza:damage', src, 25, 1000) then return end
    local p = patientFor(src)
    if not p then return end
    local ok, err = pcall(D.Apply, p, sanitize(data), src)
    if not ok then NZA.Warn('damage failed: ' .. tostring(err)) end
end)

RegisterNetEvent('nza:down', function(data)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if not Core.Rate('nza:down', src, 2, 3000) then return end
    local p = patientFor(src)
    if not p then return end
    data = type(data) == 'table' and data or {}

    if p.state ~= 'alive' then
        P.Sync(p.pid)          -- already down: make the client re-apply the right screen
        return
    end

    local r = P.RT(p)
    local weapon = tonumber(data.weapon) or (r.lastHit and r.lastHit.weapon) or 0
    local attacker = math.floor(num(data.attacker, 0, 65535, 0))
    local region = (type(data.region) == 'string' and NZA.Const.Region[data.region]) and data.region
        or (r.lastHit and r.lastHit.region) or nil

    -- no injuries at all (lost damage events, a script set health to 0): give the cause a body
    if next(p.injuries) == nil then
        local d = sanitize({ weapon = weapon, group = data.group, damage = 40, region = region, attacker = attacker })
        pcall(D.Apply, p, d, src, true)
        if p.state ~= 'alive' then return end
        if next(p.injuries) == nil then
            P.AddInjury(p.pid, { region = region or 'chest', type = 'contusion', severity = 2, weapon = weapon })
        end
    end

    local cause = { reason = 'down', weapon = weapon, attacker = attacker > 0 and attacker or nil, region = region, at = os.time() }
    local to = 'wounded'
    if Config.Wounded and Config.Wounded.enabled == false then to = 'arrest' end
    if P.Loss(p) >= ((Config.Physiology and Config.Physiology.arrestLoss) or 0.45) then
        to = 'arrest'
        cause.reason = 'hypovolemia'
    end
    P.SetState(p, to, cause)
end)
