--[[
    NAYZEEE AMBULANCE - First aid (server): procedures

      NZA.Proc 'stopbleed'   perm Config.Firstaid.StopBleed.perm ('basic')
          payload { injury = id? }  (default: the worst external bleed this treats)
          steps   pressure → pack (deep gunshot / stab / shrapnel...) → wrap (limbs) | dressing (torso)
          items   per step from Config.Firstaid.StopBleed.items (consumed on finish)
          data    + tone / seed for the 3D close-up (same skin as the suture / burn close-ups)
          result  { score, steps = { pressure, pack, wrap|dressing } (0..100), lost (mL) }
          effects treat.packed / treat.bandaged + quality, base bleed lowered by quality,
                  soak-through timer for unpacked heavy bleeds, optional fee

      NZA.Proc 'tourniquet'  perm Config.Firstaid.Tourniquet.perm ('basic'), item tourniquet
          payload { injury = id? , region = limb region? }
          data    + tone / seed for the 3D close-up (the same skin as the other close-ups)
          result  { score, seg = 'upper'|'lower', frac = 0..1 along that bone, pressure (mmHg),
                    over (s over-tightened), misLocks }
          effects devices.tourniquet[region] = os.time() (region = where it really sits),
                  meta.tqPos / tqBy, treat.tourniquet on the injuries it covers

      NZA.Proc 'collar'      perm Config.Firstaid.Collar.perm ('splint'), item cervical_collar
          result  { score, size = 'nonneck'|'short'|'regular'|'tall', align = 0..100 }
          effects devices.collar, spinal condition stabilised, neck fractures splinted

    Easy mode (NZA.Staff.Easy) skips every minigame requirement and only needs the supplies;
    the core sends { score = Config.EasyMode.score, easy = true } and the ideal technique is used.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Firstaid = NZA.Firstaid or {}
local FA = NZA.Firstaid
local U = NZA.Util

local function L(key, ...) return NZA.L('firstaid.' .. key, ...) end
local function fail(key, ...) return false, { err = key, msg = L('err_' .. key, ...) } end
local function clampScore(v) return U.clamp(math.floor(tonumber(v) or 0), 0, 100) end

local function easyScore() return (Config.EasyMode and Config.EasyMode.score) or 78 end

local function woundFrac(inj)
    if not inj or type(inj.spot) ~= 'table' then return 0.5 end
    return U.clamp(0.22 + 0.56 * (tonumber(inj.spot.y) or 0.5), 0.15, 0.85)
end

local function summary(p, inj)
    local R = NZA.Const.Region[inj.region] or {}
    local T = NZA.Const.InjuryTypes[inj.type] or {}
    return {
        id = inj.id, region = inj.region, regionLabel = U.RegionLabel(inj.region),
        type = inj.type, typeLabel = U.InjuryLabel(inj.type), short = T.short or inj.type,
        severity = inj.severity or 1, sevLabel = NZA.L('firstaid.sev_' .. tostring(inj.severity or 1)),
        bleed = U.round(FA.ShownBleed(p, inj), 1), depth = tonumber(inj.depth) or 0,
        length = tonumber(inj.length) or 0, limb = R.limb or false, side = R.side,
        spot = type(inj.spot) == 'table' and { x = tonumber(inj.spot.x) or 0.5, y = tonumber(inj.spot.y) or 0.5 } or { x = 0.5, y = 0.5 },
        frac = woundFrac(inj),
        arterial = (inj.severity or 1) >= 3 and (inj.type == 'gunshot' or inj.type == 'stab' or inj.type == 'shrapnel'),
    }
end
FA.Summary = summary

-- skin tone + seed for the 3D close-up (NUI apps/treat/bleed3d.js): the same pick as the suture /
-- burn / bullet close-ups (their skinTones, hashed on the patient id) so a patient looks the same in all
local function hash(str)
    local h = 5381
    str = tostring(str)
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 2147483647 end
    return h
end

local function skinTone(p)
    local tones = (Config.Suture and Config.Suture.skinTones) or (Config.Burn and Config.Burn.skinTones)
        or (Config.Bullet and Config.Bullet.skinTones) or { 0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88 }
    return tones[(hash(p.pid) % #tones) + 1] or 0.3
end

local function vitalsOf(p)
    local v = p.vitals or {}
    return { hr = math.floor(tonumber(v.hr) or 80), sys = math.floor(tonumber(v.sys) or 120), dia = math.floor(tonumber(v.dia) or 75),
             spo2 = math.floor(tonumber(v.spo2) or 98), rr = math.floor(tonumber(v.rr) or 16) }
end
FA.Vitals = vitalsOf

-- ════════════════════════════════════════════════════════════════════════
-- STOP BLEEDING
-- ════════════════════════════════════════════════════════════════════════

local function bleedFilter(p)
    local sb = FA.Cfg('StopBleed')
    return function(inj)
        if not FA.Has(sb.types, inj.type) then return false end
        if inj.type == 'abrasion' and FA.ShownBleed(p, inj) < (sb.abrasionMin or 2) then return false end
        if FA.ShownBleed(p, inj) < (sb.minBleed or 0.5) then return false end
        return FA.Plan(p, inj) ~= nil
    end
end

local function pickBleed(p, payload)
    local ok = bleedFilter(p)
    -- the wound the medic picked (exam), unless it is not one this procedure treats
    local id = type(payload) == 'table' and payload.injury or nil
    if type(id) == 'string' and p.injuries[id] and ok(p.injuries[id]) then return p.injuries[id] end
    local best, bestB = nil, -1
    for _, inj in pairs(p.injuries) do
        if ok(inj) then
            local b = FA.ShownBleed(p, inj)
            if b > bestB then best, bestB = inj, b end
        end
    end
    return best
end

do
    local sb = (Config.Firstaid or {}).StopBleed or {}
    NZA.Proc.Register('stopbleed', {
        perm = sb.perm or 'basic', maxDist = 3.0, label = L('title_bleed'),
        minTime = sb.minTime or 8, maxTime = sb.maxTime or 300, easyTime = sb.easyTime or 8,
        consume = 'finish', states = { alive = true, wounded = true, arrest = true },
        items = function(src, p, payload)
            local inj = pickBleed(p, payload)
            local plan = inj and FA.Plan(p, inj)
            return plan and plan.items or {}
        end,
        onStart = function(src, p, payload, info)
            local inj = pickBleed(p, payload)
            if not inj then return fail('nothing_bleeding') end
            local plan, why = FA.Plan(p, inj)
            if not plan then return fail(why) end
            local shown = FA.ShownBleed(p, inj)
            if shown < (sb.minBleed or 0.5) then return fail('nothing_bleeding') end
            local labels = {}
            for _, s in ipairs(plan.steps) do labels[#labels + 1] = L('step_' .. s) end
            return true, {
                mode = 'bleed', injury = summary(p, inj), steps = plan.steps, stepLabels = labels,
                method = plan.method, deep = plan.deep, underTq = FA.TqCovers(p, inj.region),
                vitals = vitalsOf(p), patient = { name = p.name, sex = p.sex, kind = p.kind },
                tone = skinTone(p), seed = hash(tostring(p.pid) .. ':' .. tostring(inj.id)),
                tune = {
                    pressureTarget = sb.pressureTarget or 0.3, pressureHold = sb.pressureHold or 2.5,
                    packStrips = sb.packStrips or 4, wrapTurns = sb.wrapTurns or 4,
                    tensionBand = sb.tensionBand or { 0.38, 0.72 }, failScore = sb.failScore or 30,
                },
                items = plan.itemKeys,
            }
        end,
        onFinish = function(src, p, session, result)
            local data = session.data or {}
            local id = data.injury and data.injury.id
            local inj = id and p.injuries[id]
            if not inj then return { msg = L('wound_gone') } end
            local failScore = sb.failScore or 30
            local scores = {}
            local rs = type(result.steps) == 'table' and result.steps or {}
            for _, s in ipairs(data.steps or {}) do
                scores[s] = result.easy and easyScore() or clampScore(rs[s])
            end
            -- a sub-second rush through every step is not believable: cap it
            local minPer = 2.5
            if not result.easy and (session.elapsed or 0) < #(data.steps or {}) * minPer then
                for s, v in pairs(scores) do scores[s] = math.min(v, 40) end
            end

            local patch = { treat = {}, quality = {} }
            local applied, sum, n = {}, 0, 0
            if scores.pack and scores.pack >= failScore then
                patch.treat.packed = true
                patch.quality.packed = scores.pack
                applied[#applied + 1] = L('step_pack')
                sum, n = sum + scores.pack, n + 1
            end
            local method = data.method
            local mScore = method and scores[method]
            if mScore and mScore >= failScore then
                patch.treat.bandaged = true
                patch.quality.bandaged = mScore
                applied[#applied + 1] = L('step_' .. method)
                sum, n = sum + mScore, n + 1
            end
            if n == 0 then
                return { msg = L('bleed_failed', U.RegionLabel(inj.region)), failed = true,
                         record = L('rec_bleed_failed', U.InjuryLabel(inj.type), U.RegionLabel(inj.region)) }
            end

            -- quality lowers the wound's base bleed on top of the dressing modifier
            local q = U.clamp(((sum / n) - 50) / 50, 0, 1)
            local base = tonumber(inj.bleedBase) or 0
            patch.bleedBase = U.round(base * (1 - (sb.qualityBonus or 0.4) * q), 2)

            -- an unpacked dressing on a heavy bleed may soak through later
            local soak = sb.soak or {}
            local packedNow = patch.treat.packed or (inj.treat and inj.treat.packed)
            if patch.treat.bandaged and not packedNow and soak.enabled ~= false and base >= (soak.minBleed or 40)
                and mScore < (soak.quality or 70) then
                patch.soakAt = os.time() + (soak.after or 240)
            end

            NZA.Patients.UpdateInjury(p.pid, inj.id, patch)
            NZA.Physiology.Refresh(p)
            local now = U.round(tonumber(p.injuries[inj.id] and p.injuries[inj.id].bleed) or 0, 1)
            FA.Bill(src, p, 'stopbleed')
            local where = U.RegionLabel(inj.region)
            local what = table.concat(applied, ' + ')
            return {
                msg = L('ok_bleed', what, where, now), bleed = now, packed = patch.treat.packed == true,
                bandaged = patch.treat.bandaged == true, soak = patch.soakAt ~= nil,
                record = L('rec_bleed', what, U.InjuryLabel(inj.type), where, math.floor((sum / n) + 0.5)),
            }
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- TOURNIQUET
-- ════════════════════════════════════════════════════════════════════════

local function pickLimb(p, payload)
    payload = type(payload) == 'table' and payload or {}
    if type(payload.injury) == 'string' and p.injuries[payload.injury] then
        local inj = p.injuries[payload.injury]
        if FA.Limb(inj.region) then return inj, inj.region end
        return nil, nil, 'not_limb'
    end
    if type(payload.region) == 'string' and FA.Limb(payload.region) then
        -- the worst bleed on that limb segment (or none: a tourniquet put on as a precaution)
        local best = FA.WorstBleed(p, function(i) return i.region == payload.region end)
        return best, payload.region
    end
    local best = FA.WorstBleed(p, function(i)
        return FA.Limb(i.region) ~= nil and not FA.TqCovers(p, i.region) and (tonumber(i.bleed) or 0) >= 0.5
    end)
    if not best then return nil, nil, 'no_limb_bleed' end
    return best, best.region
end

local function strapTime()
    local c = FA.Cfg('Tourniquet')
    if c.clock == 'real' then return os.date('%H:%M') end
    return nil   -- the client writes the in-game time
end

do
    local tc = (Config.Firstaid or {}).Tourniquet or {}
    NZA.Proc.Register('tourniquet', {
        perm = tc.perm or 'basic', maxDist = 3.0, label = L('title_tq'),
        minTime = tc.minTime or 6, maxTime = tc.maxTime or 240, easyTime = tc.easyTime or 7,
        consume = 'finish', states = { alive = true, wounded = true, arrest = true },
        items = function() return FA.ItemsOf({ [tc.item or 'tourniquet'] = 1 }) end,
        onStart = function(src, p, payload)
            local inj, region, why = pickLimb(p, payload)
            if not region then return fail(why or 'no_limb_bleed') end
            if FA.TqCovers(p, region) then return fail('already_tq', U.RegionLabel(region)) end
            local limb = FA.Limb(region)
            local v = vitalsOf(p)
            local occ = tc.occlusion or {}
            local occlusion = U.clamp(v.sys + (limb.kind == 'leg' and (occ.leg or 100) or (occ.arm or 60)), occ.min or 140, occ.max or 330)
            local gain = (tc.turnGain or {})[limb.kind] or 65
            return true, {
                mode = 'tq', injury = inj and summary(p, inj) or nil, region = region, regionLabel = U.RegionLabel(region),
                limb = limb.kind, upper = limb.upper, lower = limb.lower, woundSeg = limb.seg, woundFrac = woundFrac(inj),
                side = (NZA.Const.Region[region] or {}).side,
                vitals = v, patient = { name = p.name, sex = p.sex, kind = p.kind },
                -- the 3D close-up (NUI apps/treat/tq3d.js): the patient's skin, as in the other close-ups
                tone = skinTone(p), seed = hash(tostring(p.pid) .. ':tq:' .. tostring(region)),
                tune = {
                    occlusion = occlusion, turnGain = gain, overMargin = tc.overMargin or 110, unwind = tc.unwind or 22,
                    clipWindow = tc.clipWindow or 14, jointZone = tc.jointZone or 0.1, idealAbove = tc.idealAbove or { 5, 8 },
                    length = limb.kind == 'leg' and (tc.legLength or 88) or (tc.armLength or 62),
                },
                time = strapTime(),
            }
        end,
        onFinish = function(src, p, session, result)
            local d = session.data or {}
            local limb = FA.Limb(d.region or '')
            if not limb then return { msg = L('err_not_limb'), failed = true } end
            local seg, frac
            if result.easy then
                seg, frac = 'upper', 0.2
            else
                seg = result.seg == 'lower' and 'lower' or 'upper'
                frac = U.clamp(tonumber(result.frac) or 0.2, 0.0, 1.0)
            end
            local wSeg, wFrac = d.woundSeg or 'upper', tonumber(d.woundFrac) or 0.5
            -- where it really sits (physiology works per region)
            local region
            if seg == 'upper' then
                if wSeg == 'upper' and frac >= wFrac then region = limb.lower else region = limb.upper end
            else
                if wSeg == 'lower' and frac >= wFrac then
                    return { msg = L('tq_below', U.RegionLabel(d.region)), failed = true,
                             record = L('rec_tq_failed', U.RegionLabel(d.region)) }
                end
                region = limb.lower
            end
            local pressure = tonumber(result.pressure) or 0
            local tune = d.tune or {}
            if not result.easy and pressure < (tonumber(tune.occlusion) or 0) * 0.97 then
                return { msg = L('tq_loose'), failed = true, record = L('rec_tq_failed', U.RegionLabel(d.region)) }
            end
            if FA.TqCovers(p, region) and (p.devices.tourniquet or {})[region] then
                return { msg = L('err_already_tq', U.RegionLabel(region)), failed = true }
            end

            local score = clampScore(result.score)
            NZA.Patients.SetDevice(p.pid, 'tourniquet', region, os.time())
            local pos = type(p.meta.tqPos) == 'table' and p.meta.tqPos or {}
            pos[region] = { s = seg, f = U.round(frac, 3) }
            NZA.Patients.SetMeta(p.pid, 'tqPos', pos)
            local by = type(p.meta.tqBy) == 'table' and p.meta.tqBy or {}
            by[region] = src
            NZA.Patients.SetMeta(p.pid, 'tqBy', by)
            for _, key in ipairs({ 'tqWarn', 'tqDmg' }) do
                local m = p.meta[key]
                if type(m) == 'table' and m[region] then m[region] = nil; NZA.Patients.SetMeta(p.pid, key, m) end
            end

            local covered = 0
            for id, inj in pairs(p.injuries) do
                if FA.TqCovers(p, inj.region) and FA.Limb(inj.region) and FA.Limb(inj.region).kind == limb.kind
                    and (inj.region == limb.upper or inj.region == limb.lower) then
                    local patch = { treat = { tourniquet = true }, quality = { tourniquet = score } }
                    if not result.easy and (tonumber(result.over) or 0) > 3 and d.injury and id == d.injury.id then
                        patch.pain = math.min(100, (inj.pain or 0) + (tonumber(FA.Cfg('Tourniquet').overPain) or 15))
                    end
                    NZA.Patients.UpdateInjury(p.pid, id, patch)
                    covered = covered + 1
                end
            end
            NZA.Physiology.Refresh(p)
            FA.SyncBag(p)
            FA.Bill(src, p, 'tourniquet')
            local stamp = type(result.time) == 'string' and result.time:match('^%d%d:%d%d$') or os.date('%H:%M')
            local msg = L('ok_tq', U.RegionLabel(region), stamp)
            if region ~= d.region and seg == 'upper' and wSeg == 'upper' then msg = L('tq_low', U.RegionLabel(d.region)) end
            return { msg = msg, region = region, covered = covered, time = stamp,
                     record = L('rec_tq', U.RegionLabel(region), stamp, score) }
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- CERVICAL COLLAR
-- ════════════════════════════════════════════════════════════════════════

local SIZES = { 'nonneck', 'short', 'regular', 'tall' }
local SIZE_INDEX = { nonneck = 1, short = 2, regular = 3, tall = 4 }

-- the patient's neck height in finger widths (stable per patient)
local function neckFingers(p)
    local h = 0
    for i = 1, #p.pid do h = (h * 31 + p.pid:byte(i)) % 1000003 end
    local r = h % 100
    local base
    if r < 12 then base = 2 elseif r < 38 then base = 3 elseif r < 82 then base = 4 else base = 5 end
    if p.sex == 'f' and base > 2 and r % 3 == 0 then base = base - 1 end
    return base
end

do
    local cc = (Config.Firstaid or {}).Collar or {}
    NZA.Proc.Register('collar', {
        perm = cc.perm or 'splint', maxDist = 3.0, label = L('title_collar'),
        minTime = cc.minTime or 6, maxTime = cc.maxTime or 240, easyTime = cc.easyTime or 7,
        consume = 'finish', states = { alive = true, wounded = true, arrest = true },
        items = function() return FA.ItemsOf({ [cc.item or 'cervical_collar'] = 1 }) end,
        onStart = function(src, p)
            if p.devices.collar then return fail('already_collar') end
            local fingers = neckFingers(p)
            local neck = {}
            for _, inj in pairs(p.injuries) do
                if inj.region == 'neck' then neck[#neck + 1] = summary(p, inj) end
            end
            return true, {
                mode = 'collar', fingers = fingers, size = SIZES[fingers - 1], spinal = p.conditions.spinal ~= nil,
                neck = neck, vitals = vitalsOf(p), patient = { name = p.name, sex = p.sex, kind = p.kind },
                regionLabel = U.RegionLabel('neck'),
                tune = { fastenSeconds = cc.fastenSeconds or 4.0, drift = cc.drift or 1.0 },
            }
        end,
        onFinish = function(src, p, session, result)
            if p.devices.collar then return { msg = L('err_already_collar'), failed = true } end
            local d = session.data or {}
            local truth = SIZE_INDEX[d.size or 'regular'] or 3
            local chosen = result.easy and truth or (SIZE_INDEX[result.size] or 0)
            local align = result.easy and easyScore() or clampScore(result.align)
            local sizeScore = chosen == truth and 100 or (math.abs(chosen - truth) == 1 and 45 or 0)
            local score = math.min(clampScore(result.score), math.floor(sizeScore * 0.5 + align * 0.5 + 0.5))
            if result.easy then score = easyScore() end
            NZA.Patients.SetDevice(p.pid, 'collar', true)
            local sp = p.conditions.spinal
            if sp then
                local v = {}
                for k, val in pairs(sp) do v[k] = val end
                v.stable = true
                v.collar = os.time()
                NZA.Patients.SetCondition(p.pid, 'spinal', v)
            end
            for id, inj in pairs(p.injuries) do
                if inj.region == 'neck' and inj.type == 'fracture' then
                    NZA.Patients.UpdateInjury(p.pid, id, { treat = { splinted = true }, quality = { splinted = score } })
                end
            end
            FA.Bill(src, p, 'collar')
            local sizeLabel = L('size_' .. (SIZES[chosen] or 'regular'))
            local msg = chosen == truth and L('ok_collar', sizeLabel) or L('ok_collar_wrong', sizeLabel, L('size_' .. SIZES[truth]))
            return { msg = msg, size = SIZES[chosen], truth = SIZES[truth], record = L('rec_collar', sizeLabel, score) }
        end,
    })
end
