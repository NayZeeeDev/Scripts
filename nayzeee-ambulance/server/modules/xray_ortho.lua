--[[
    NAYZEEE AMBULANCE - Fracture care (server): set the bone (closed reduction) and apply a cast

    Procedures (ARCHITECTURE §5.2)
      NZA.Proc.Register('xray_reduce', { perm = Config.Xray.Reduce.perm, ... })
        payload { injury = 'i7' }
        onStart  → displaced limb fracture, not reduced yet, read on an X-ray film (treat.xray / xrayMarked)
                   and the patient on a hospital point (patient.meta.bed) - both skipped in easy mode.
                   data → { injury, region, bone, kind, angle, phi, short, side, view, analgesia, painBase, tolerance }
        onFinish → result { score, angle (degrees left), short (mm left), slips, painOver, fluoro (s) } is clamped;
                   sets fracture.angle to what is left (never more than before), treat.reduced when
                   angle ≤ Reduce.tolerance, quality.reduced, bills; pulling far too hard adds pain.
      NZA.Proc.Register('xray_cast', { perm = Config.Xray.Cast.perm, items = { [Config.Items.cast] = 1 }, ... })
        payload { injury = 'i7' }
        onStart  → limb fracture without a cast, aligned (not displaced or reduced), open fractures cleaned /
                   closed first (Cast.openNeedsWoundCare), patient on a hospital point (skipped in easy mode)
        onFinish → treat.cast, quality.cast, heal boost (Cast.healBoost × score), removes the splint of that limb,
                   leg casts recommend / give crutches (Cast.crutches), bills.
    Bus events emitted: xray:reduced (src, p, injury, outcome), xray:cast (src, p, injury, outcome)
    Uses NZA.Xray.* from server/modules/xray.lua at runtime only.
]]

if not NAYZEEE_LOCK_OK then return end

local U = NZA.Util

local function cfg(section)
    local c = Config.Xray or {}
    return c[section] or {}
end

local function L(key, ...)
    return NZA.L('xray.' .. key, ...)
end

local function X()
    return NZA.Xray or {}
end

local function fail(err)
    return { err = err, msg = L('err_' .. err) }
end

local function boneLabel(bone)
    local key = 'core.bone_' .. tostring(bone)
    local s = NZA.L(key)
    if s == key then return tostring(bone) end
    return s
end

-- Config.Items key → count  ⇒  { [item name] = count }
local function itemsFrom(list)
    local out = {}
    for key, n in pairs(list or {}) do
        local name = Config.Items and Config.Items[key] or nil
        if name and (tonumber(n) or 0) > 0 then out[name] = math.floor(tonumber(n)) end
    end
    return out
end

local function injuryOf(p, payload)
    local id = type(payload) == 'table' and payload.injury or nil
    if type(id) ~= 'string' and type(id) ~= 'number' then return nil end
    local inj = p.injuries and p.injuries[id]
    if not inj then
        for _, i in pairs(p.injuries or {}) do
            if tostring(i.id) == tostring(id) then inj = i break end
        end
    end
    return inj
end

local function atHospital(p)
    local bed = p.meta and p.meta.bed
    if type(bed) == 'table' then return true end
    if p.meta and (p.meta.inBed or p.meta.bay) then return true end
    if X().OnTable then
        local ok = X().OnTable(p)
        if ok then return true end
    end
    return false
end

local function viewOf(region)
    local R = NZA.Const.Region[region or '']
    return R and R.xray or nil
end

local function legRegion(region)
    local R = NZA.Const.Region[region or '']
    return R and R.limb == 'leg'
end

local function castType(inj)
    local bone = inj.fracture and inj.fracture.bone or ''
    if bone == 'femur' then return 'long_leg' end
    if bone == 'humerus' then return 'long_arm' end
    if legRegion(inj.region) then return 'short_leg' end
    return 'short_arm'
end

-- active pain relief 0..0.8 (morphine, lidocaine, painkillers)
local function analgesia(p, inj)
    local an = cfg('Reduce').analgesia or {}
    local total = 0
    local active = NZA.Patients.MedActive
    for med, share in pairs(an) do
        local on = false
        if type(active) == 'function' then
            local ok, res = pcall(active, p, med)
            on = ok and res == true
        elseif p.meds and p.meds[med] then
            on = (tonumber(p.meds[med]) or 0) > os.time()
        end
        if on then total = total + (tonumber(share) or 0) end
    end
    if inj and inj.treat and inj.treat.anesthetized then total = total + 0.2 end
    return U.clamp(total, 0, 0.8)
end

local function hashSeed(str)
    local h = 2166136261
    for i = 1, #str do
        h = (h ~ str:byte(i)) * 16777619 % 4294967296
    end
    return math.floor(h % 2147483646) + 1
end

-- ════════════════════════════════════════════════════════════════════════
-- SET THE BONE
-- ════════════════════════════════════════════════════════════════════════

do
    local rc = cfg('Reduce')
    NZA.Proc.Register('xray_reduce', {
        perm = rc.perm or 'splint',
        label = L('reduce_title'),
        maxDist = tonumber(rc.maxDist) or 3.0,
        minTime = tonumber(rc.minTime) or 14,
        maxTime = tonumber(rc.maxTime) or 300,
        easyTime = tonumber(rc.easyTime) or 10,
        states = { alive = true, wounded = true },
        consume = 'finish',
        items = function() return itemsFrom(cfg('Reduce').items) end,

        onStart = function(src, p, payload, info)
            local c = cfg('Reduce')
            local inj = injuryOf(p, payload)
            if not inj or inj.type ~= 'fracture' or type(inj.fracture) ~= 'table' then return false, fail('not_fracture') end
            if not (c.regions or {})[inj.region] then return false, fail('region') end
            local f = inj.fracture
            local treat = inj.treat or {}
            if treat.cast then return false, fail('cast_done') end
            if not f.displaced or (tonumber(f.angle) or 0) <= (tonumber(c.tolerance) or 3) then return false, fail('not_displaced') end
            local easy = type(info) == 'table' and info.easy == true
            if not easy then
                if c.requireXray ~= false and not (treat.xray or treat.xrayMarked) then return false, fail('need_xray') end
                if c.requireHospital ~= false and not atHospital(p) then return false, fail('hospital') end
            end
            local seed = hashSeed(p.pid .. ':' .. tostring(inj.id))
            local R = NZA.Const.Region[inj.region]
            return true, {
                injury = inj.id, region = inj.region, regionLabel = U.RegionLabel(inj.region), bone = f.bone,
                boneLabel = boneLabel(f.bone), kind = f.kind or 'closed', angle = math.floor(tonumber(f.angle) or 0),
                phi = ((seed % 1000) / 1000) * 1.2 + 0.15, short = 4 + (seed % 14), side = R and R.side or 'r',
                view = viewOf(inj.region), upper = tostring(inj.region):find('upper') ~= nil,
                analgesia = analgesia(p, inj), painBase = math.floor(tonumber(inj.pain) or 50),
                tolerance = tonumber(c.tolerance) or 3, fluoroBudget = tonumber(c.fluoroBudget) or 12,
                name = p.name, sev = inj.severity,
            }
        end,

        onFinish = function(src, p, session, result)
            local c = cfg('Reduce')
            local data = session.data or {}
            local inj = p.injuries and p.injuries[data.injury]
            if not inj or type(inj.fracture) ~= 'table' then return { msg = L('err_not_fracture'), failed = true } end
            local before = math.floor(tonumber(inj.fracture.angle) or 0)
            local left
            if result.easy then
                left = 0
            else
                left = math.floor(U.clamp(tonumber(result.angle) or before, 0, before) + 0.5)
                -- a poor score can never be a perfect reduction
                local floorByScore = math.floor((100 - result.score) / 100 * before * 0.6 + 0.5)
                if left < floorByScore then left = floorByScore end
            end
            local tol = tonumber(c.tolerance) or 3
            local reduced = left <= tol
            local patch = {
                fracture = { angle = reduced and 0 or left, displaced = not reduced },
                quality = { reduced = result.score },
            }
            if reduced then patch.treat = { reduced = true } end
            -- pulling far too hard hurts and swells
            local over = tonumber(result.painOver) or 0
            local spike = 0
            if not result.easy and over >= 2 then
                local oldPain = tonumber(inj.pain) or 50
                patch.pain = U.clamp(oldPain + math.min(tonumber(c.painSpike) or 25, over * 4), 0, 100)
                spike = patch.pain - oldPain
            end
            NZA.Patients.UpdateInjury(p.pid, inj.id, patch)
            if spike > 0 then
                local pid, id = p.pid, inj.id
                SetTimeout(90000, function()
                    local pp = NZA.Patients.Get(pid)
                    local ii = pp and pp.injuries and pp.injuries[id]
                    if ii then NZA.Patients.UpdateInjury(pid, id, { pain = U.clamp((tonumber(ii.pain) or 0) - spike, 0, 100) }) end
                end)
            end
            X().Bill(src, p, 'reduce', L('bill_reduce', boneLabel(inj.fracture.bone)))
            if p.kind == 'player' and p.src and p.src ~= src then
                X().Notify(p.src, L(reduced and 'reduce_patient_ok' or 'reduce_patient_partial', boneLabel(inj.fracture.bone)), 'info')
            end
            local outcome = {
                reduced = reduced, angle = left, before = before,
                msg = reduced and L('reduce_ok', boneLabel(inj.fracture.bone), left) or L('reduce_partial', left),
                record = L('record_reduce', boneLabel(inj.fracture.bone), before, left),
            }
            NZA.Bus.Emit('xray:reduced', src, p, inj, outcome)
            return outcome
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- CAST
-- ════════════════════════════════════════════════════════════════════════

local function woundCared(inj)
    local t = inj.treat or {}
    return t.irrigated or t.sutured or t.dressed or t.bandaged
end

do
    local cc = cfg('Cast')
    NZA.Proc.Register('xray_cast', {
        perm = cc.perm or 'splint',
        label = L('cast_title'),
        maxDist = tonumber(cc.maxDist) or 3.0,
        minTime = tonumber(cc.minTime) or 14,
        maxTime = tonumber(cc.maxTime) or 300,
        easyTime = tonumber(cc.easyTime) or 10,
        states = { alive = true, wounded = true },
        consume = 'finish',
        items = function()
            local name = Config.Items and Config.Items.cast
            return name and { [name] = 1 } or {}
        end,

        onStart = function(src, p, payload, info)
            local c = cfg('Cast')
            local inj = injuryOf(p, payload)
            if not inj or inj.type ~= 'fracture' or type(inj.fracture) ~= 'table' then return false, fail('not_fracture') end
            if not (c.regions or {})[inj.region] then return false, fail('region') end
            local treat = inj.treat or {}
            if treat.cast then return false, fail('cast_done') end
            local f = inj.fracture
            local tol = tonumber(cfg('Reduce').tolerance) or 3
            if f.displaced and not treat.reduced and (tonumber(f.angle) or 0) > tol then return false, fail('reduce_first') end
            if c.openNeedsWoundCare ~= false and f.kind == 'open' and not woundCared(inj) then return false, fail('wound_first') end
            local easy = type(info) == 'table' and info.easy == true
            if not easy and c.requireHospital ~= false and not atHospital(p) then return false, fail('hospital') end
            local layers = c.layers or { 3, 6 }
            local R = NZA.Const.Region[inj.region]
            return true, {
                injury = inj.id, region = inj.region, regionLabel = U.RegionLabel(inj.region), bone = f.bone,
                boneLabel = boneLabel(f.bone), castType = castType(inj), side = R and R.side or 'r',
                leg = legRegion(inj.region), layersMin = tonumber(layers[1]) or 3, layersMax = tonumber(layers[2]) or 6,
                name = p.name, upper = tostring(inj.region):find('upper') ~= nil,
            }
        end,

        onFinish = function(src, p, session, result)
            local c = cfg('Cast')
            local data = session.data or {}
            local inj = p.injuries and p.injuries[data.injury]
            if not inj then return { msg = L('err_not_fracture'), failed = true } end
            local boost = math.floor((tonumber(c.healBoost) or 15) * result.score / 100 + 0.5)
            NZA.Patients.UpdateInjury(p.pid, inj.id, {
                treat = { cast = true },
                quality = { cast = result.score },
                heal = U.clamp((tonumber(inj.heal) or 0) + boost, 0, 99),
            })
            if c.removeSplint ~= false and p.devices and type(p.devices.splints) == 'table' and p.devices.splints[inj.region] then
                NZA.Patients.SetDevice(p.pid, 'splints', inj.region, false)
            end
            local castLabel = L('cast_' .. tostring(data.castType or castType(inj)))
            local outcome = {
                cast = true, castType = data.castType, msg = L('cast_ok', castLabel),
                record = L('record_cast', castLabel, boneLabel(inj.fracture and inj.fracture.bone)),
            }
            if legRegion(inj.region) and c.crutches then
                outcome.crutches = c.crutches
                outcome.msg = outcome.msg .. ' · ' .. L('crutches_recommend')
                if p.kind == 'player' and p.src then
                    local given = false
                    if c.crutches == 'give' and Config.Items and Config.Items.crutches and NZA.Core and NZA.Core.B then
                        local have = tonumber(NZA.Core.B('Inv.Count', p.src, Config.Items.crutches)) or 0
                        if have < 1 then given = NZA.Core.B('Inv.AddItem', p.src, Config.Items.crutches, 1) == true end
                    end
                    if p.src ~= src or given then
                        X().Notify(p.src, L(given and 'crutches_given' or 'crutches_patient'), 'info')
                    end
                end
            end
            X().Bill(src, p, 'cast', L('bill_cast', castLabel))
            if p.kind == 'player' and p.src and p.src ~= src then
                X().Notify(p.src, L('cast_patient', castLabel), 'info')
            end
            NZA.Bus.Emit('xray:cast', src, p, inj, outcome)
            return outcome
        end,
    })
end
