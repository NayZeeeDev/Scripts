--[[
    NAYZEEE AMBULANCE - Bullet / fragment extraction (server)

    Server side of the extraction surgery (ARCHITECTURE §5.2). The client plays the 3D
    minigame (html/apps/bullet: locate → disinfect → incise → expose → extract → control the
    bleeding → suture → dressing); the server decides which wounds qualify, where the
    fragments are, checks the room and the supplies, enforces the timing and applies the result.

    Procedure
      NZA.Proc.Register('bullet', { perm = Config.Bullet.perm, items (Config.Bullet.items), minTime,
                                    maxTime, easyTime, maxDist, onStart, onFinish, onAbort })
        payload  { injury = <injury id> }
        onStart  → the wound must be a gunshot / shrapnel wound that still holds metal; the patient
                   must lie on an operating table (meta.bed.type = 'surgery') or be in an ambulance
                   treatment bay (meta.bay) unless easy mode; every Config.Bullet.supplies item must be
                   carried. Builds the case: fragments (deterministic per wound), the X-ray film the
                   surgeon carries for this patient / region (if any), vitals, blood warning.
        onFinish → validates the minigame result against the session's fragments, clamps and
                   re-checks the score, takes the supplies that were used, applies:
                   injury.retained → pieces left, treat.extracted / sutured / dressed, quality.*,
                   bleedBase reduced, contamination by the prep, and the surgical blood loss.
      Easy mode: everything succeeds at Config.EasyMode.score, every supply is used,
                 Config.Bullet.Blood.easy mL are lost.
    Usable item: Config.Items.surgical_kit → client event 'nza:bullet:use' (start on the nearest patient)
    Net event:   nza:bullet:partial (token, loss) C→S just before an abort: the blood the opened wound cost
                 so far (session owner only, capped by Blood.max and Blood.perMinute × minutes), applied
                 in onAbort
    Bus events emitted: bullet:done (src, patient, injury, outcome)
    Lua API: NZA.Bullet.Eligible(injury) → ok, reason   NZA.Bullet.Location(patient) → ok, kind
             NZA.Bullet.Fragments(patient, injury) → { { id, x, y, depth, size, shape, rot, lodge } }
             NZA.Bullet.Film(src, patient, injury) → film info | nil
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Bullet = NZA.Bullet or {}
local Bx = NZA.Bullet
local U = NZA.Util

local function cfg()
    return Config.Bullet or {}
end

local function core()
    return NZA.Core or {}
end

local function L(key, ...)
    return NZA.L('bullet.' .. key, ...)
end

local function clamp(v, a, b)
    v = tonumber(v) or a
    if v ~= v then v = a end
    if v < a then return a end
    if v > b then return b end
    return v
end

local function round(v, d)
    local m = 10 ^ (d or 0)
    return math.floor((tonumber(v) or 0) * m + 0.5) / m
end

local function itemName(key)
    return Config.Items and Config.Items[key] or nil
end

local function count(src, key)
    local name = itemName(key)
    if not name or not core().B then return 0 end
    return tonumber(core().B('Inv.Count', src, name)) or 0
end

local function take(src, key, n)
    local name = itemName(key)
    n = math.floor(tonumber(n) or 0)
    if not name or n <= 0 or not core().TakeItems then return false end
    return core().TakeItems(src, { [name] = n }) == true
end

local function hash(str)
    local h = 5381
    str = tostring(str)
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 2147483647 end
    return h
end

-- small deterministic generator (Park-Miller) so a wound always holds the same fragments
local function rng(seed)
    local s = (math.floor(tonumber(seed) or 1) % 2147483646) + 1
    return function()
        s = (s * 16807) % 2147483647
        return (s - 1) / 2147483646
    end
end

-- Config.Bullet.items (Config.Items keys → count) → { [item name] = count }
local function itemsOf(map)
    local out = {}
    for key, n in pairs(map or {}) do
        local name = itemName(key)
        local c = math.floor(tonumber(n) or 0)
        if name and c > 0 then out[name] = c end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- RULES
-- ════════════════════════════════════════════════════════════════════════

-- Does this wound need the operation? → ok, reason ('no_injury' | 'type' | 'nothing')
function Bx.Eligible(inj)
    if type(inj) ~= 'table' then return false, 'no_injury' end
    if not (cfg().types or {})[inj.type] then return false, 'type' end
    if (tonumber(inj.retained) or 0) <= 0 then return false, 'nothing' end
    if inj.treat and inj.treat.extracted then return false, 'nothing' end
    return true
end

-- Operating table or ambulance treatment bay → ok, kind ('surgery' | 'bay' | 'bed' | 'field')
function Bx.Location(p)
    local meta = p and p.meta or {}
    local locs = cfg().locations or {}
    if type(meta.bed) == 'table' and meta.bed.type then
        if locs[meta.bed.type] then return true, meta.bed.type end
        return false, 'bed'
    end
    if meta.bay and locs.bay then return true, 'bay' end
    if meta.bay then return false, 'bay' end
    return false, 'field'
end

-- Fragment layout for this wound (mm offsets from the entry hole, +y toward the surgeon)
function Bx.Fragments(p, inj)
    local F = cfg().Fragments or {}
    local R = rng(hash(tostring(p.pid) .. ':' .. tostring(inj.id) .. ':frag'))
    local n = math.floor(clamp(inj.retained, 1, tonumber(F.maxPieces) or 5))
    local gun = inj.type == 'gunshot'
    local spread = tonumber(F.spread) or 11
    local depth0 = tonumber(inj.retainedDepth) or 0
    if depth0 <= 0 then depth0 = math.max(8, (tonumber(inj.depth) or 18) * 0.7) end
    local map = type(inj.xrayMap) == 'table' and inj.xrayMap or nil
    if map and tonumber(map.depth) then depth0 = tonumber(map.depth) end
    local spot = type(inj.spot) == 'table' and inj.spot or { x = 0.5, y = 0.5 }
    local bias = { (clamp(spot.x, 0, 1) - 0.5) * 6, (clamp(spot.y, 0, 1) - 0.5) * 6 }
    local list = {}
    for i = 1, n do
        local size
        if gun and i == 1 then
            local r = F.bulletSize or { 8.5, 11.5 }
            size = (tonumber(r[1]) or 8.5) + R() * ((tonumber(r[2]) or 11.5) - (tonumber(r[1]) or 8.5))
        else
            local r = F.shardSize or { 3, 6.5 }
            size = (tonumber(r[1]) or 3) + R() * ((tonumber(r[2]) or 6.5) - (tonumber(r[1]) or 3))
        end
        local a = R() * math.pi * 2
        local dist = (i == 1 and (2.5 + R() * spread * 0.55)) or (3 + R() * spread)
        local depth = depth0 * (i == 1 and 1 or (0.55 + R() * 0.7))
        list[i] = {
            id = 'f' .. i,
            x = round(math.cos(a) * dist + bias[1], 1),
            y = round(math.sin(a) * dist + bias[2], 1),
            depth = round(clamp(depth, 4, 80), 1),
            size = round(size, 1),
            shape = (gun and i == 1) and 'bullet' or 'shard',
            rot = round(R() * math.pi, 2),
            lodge = (R() < (tonumber(F.lodge) or 0.3)) and 1 or 0,
        }
    end
    return list
end

-- The X-ray film the surgeon carries that shows this wound's metal → film info for the NUI
function Bx.Film(src, p, inj)
    local name = itemName('xray_film')
    if not name or not core().B then return nil end
    local list = core().B('Inv.Search', src, name)
    if type(list) ~= 'table' then return nil end
    local reg = NZA.Const and NZA.Const.Region and NZA.Const.Region[inj.region] or nil
    local view = reg and reg.xray or nil
    local best = nil
    for _, item in pairs(list) do
        local m = type(item) == 'table' and (item.metadata or item.info) or nil
        if type(m) == 'table' and tostring(m.pid) == tostring(p.pid) then
            local shows = false
            for _, f in ipairs(type(m.findings) == 'table' and m.findings or {}) do
                if type(f) == 'table' and f.k == 'frag' and (tostring(f.inj) == tostring(inj.id) or f.region == inj.region) then
                    shows = true
                    break
                end
            end
            if shows and (not view or not m.view or m.view == view) then
                local read = type(m.read) == 'table'
                local cand = {
                    id = tostring(m.id or ''), view = m.view, viewLabel = m.viewLabel or (reg and reg.label) or inj.region,
                    taken = m.taken, quality = m.quality == 'motion' and 'motion' or 'sharp',
                    marked = (inj.treat and inj.treat.xrayMarked) == true or read,
                }
                if not best or (cand.marked and not best.marked) or (cand.quality == 'sharp' and best.quality ~= 'sharp') then
                    best = cand
                end
            end
        end
    end
    return best
end

-- vitals the NUI monitor starts with (the client keeps it live from the patient watch)
local function vitals(p)
    local v = p.vitals or {}
    local drip, infusing = 0, false
    for _, inf in pairs(p.infusions or {}) do
        if type(inf) == 'table' and not inf.paused and (tonumber(inf.left) or 0) > 0 then
            drip = drip + (tonumber(inf.rate) or 0)
            if inf.kind == 'blood' or inf.kind == 'plasma' then infusing = true end
        end
    end
    local max = tonumber(p.bloodMax) or 5000
    return {
        hr = round(v.hr or 0), ecgRate = round(v.ecgRate or v.hr or 0), rhythm = v.rhythm or 'sinus',
        spo2 = round(v.spo2 or 0), sys = round(v.sys or 0), dia = round(v.dia or 0), map = round(v.map or 0),
        rr = round(v.rr or 0), bloodPct = round((tonumber(p.blood) or max) / max * 100),
        drip = round(drip), infusing = infusing,
    }, infusing
end

local function numbed(p, inj)
    if inj.treat and inj.treat.anesthetized then return true end
    for _, med in ipairs(cfg().numbed or {}) do
        if NZA.Patients.MedActive and NZA.Patients.MedActive(p, med) then return true end
    end
    return false
end

local function conscious(p)
    local avpu = p.vitals and p.vitals.avpu or 'A'
    return p.state ~= 'arrest' and p.state ~= 'dead' and (avpu == 'A' or avpu == 'V')
end

local LOC_LABEL = { surgery = 'loc_surgery', bay = 'loc_bay', bed = 'loc_bed', field = 'loc_field' }

-- The case the NUI needs
function Bx.Case(src, p, inj, kind)
    local tones = cfg().skinTones or { 0.3 }
    local tone = tones[(hash(p.pid) % #tones) + 1] or 0.3
    local v, infusing = vitals(p)
    local B = cfg().Blood or {}
    local fr = Bx.Fragments(p, inj)
    local film = Bx.Film(src, p, inj)
    local meta = p.meta or {}
    return {
        injury = {
            id = inj.id, type = inj.type, region = inj.region, severity = inj.severity,
            regionLabel = U.RegionLabel and U.RegionLabel(inj.region) or inj.region,
            label = U.InjuryLabel and U.InjuryLabel(inj.type) or inj.type,
            bleed = round(inj.bleed, 1), retained = math.floor(tonumber(inj.retained) or #fr),
            depth = round(tonumber(inj.retainedDepth) or tonumber(inj.depth) or 0),
            contamination = math.floor(clamp(inj.contamination, 0, 100) + 0.5),
            pain = math.floor(clamp(inj.pain, 0, 100) + 0.5),
        },
        patient = {
            name = p.name, sex = p.sex, bloodType = p.bloodType,
            conscious = conscious(p), numb = numbed(p, inj),
        },
        fragments = fr,
        tone = tone,
        seed = hash(p.pid .. ':' .. tostring(inj.id)),
        film = film,
        items = { gauze = math.min(count(src, 'gauze'), math.floor(tonumber(cfg().gauzeMax) or 6)) },
        location = { kind = kind, label = L(LOC_LABEL[kind] or 'loc_field') },
        bay = meta.bay ~= nil and kind == 'bay',
        bloodWarn = v.bloodPct < (tonumber(B.warnBelow) or 85) and not infusing,
        vitals = v,
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE
-- ════════════════════════════════════════════════════════════════════════

local function onStart(src, p, payload, info)
    local id = type(payload) == 'table' and payload.injury or nil
    local inj = id and p.injuries and p.injuries[id] or nil
    if not inj then return false, { err = 'no_injury', msg = L('err_no_injury') } end
    local ok, why = Bx.Eligible(inj)
    if not ok then return false, { err = why, msg = L('err_' .. why) } end
    local easy = type(info) == 'table' and info.easy == true
    local okLoc, kind = Bx.Location(p)
    if cfg().requireLocation ~= false and not easy and not okLoc then
        return false, { err = 'location', msg = L('err_location') }
    end
    -- every supply must be carried (also in easy mode: easy only drops the room rule)
    local need = itemsOf(cfg().supplies)
    local okItems, missing = core().CheckItems(src, need)
    if not okItems then
        local label = missing and core().B and core().B('Inv.Label', missing) or missing
        return false, { err = 'missing_item', msg = L('err_missing', tostring(label or '?')), item = missing }
    end
    local case = Bx.Case(src, p, inj, kind)
    if p.kind == 'player' and p.src and p.src ~= src then
        core().Notify(p.src, L('notify_patient'), 'info', L('label'))
    end
    return true, case
end

local function weightsScore(parts)
    local W = (cfg().Game or {}).weights or {}
    local keys = { 'locate', 'disinfect', 'incise', 'expose', 'extract', 'haemostasis', 'suture', 'dressing' }
    local dflt = { locate = 10, disinfect = 10, incise = 15, expose = 10, extract = 25, haemostasis = 10, suture = 12, dressing = 8 }
    local sum, tw = 0, 0
    for _, k in ipairs(keys) do
        local w = tonumber(W[k]) or dflt[k]
        tw = tw + w
        sum = sum + clamp(parts[k], 0, 100) * w
    end
    if tw <= 0 then return 0 end
    return sum / tw
end

local function onFinish(src, p, session, result)
    local case = session.data or {}
    local id = case.injury and case.injury.id
    local inj = id and p.injuries[id] or nil
    if not inj then return { msg = L('gone'), score = 0 } end
    local C, B, I = cfg(), cfg().Blood or {}, cfg().Infection or {}
    result = type(result) == 'table' and result or {}
    local score = clamp(result.score, 0, 100)
    local frags = case.fragments or {}
    local N = #frags

    -- which pieces really came out (only ids of this session's fragments count, each once)
    local valid, out = {}, {}
    for _, f in ipairs(frags) do valid[f.id] = true end
    local nOut = 0
    if session.easy then
        nOut = N
    else
        for _, fid in ipairs(type(result.extracted) == 'table' and result.extracted or {}) do
            fid = tostring(fid)
            if valid[fid] and not out[fid] then
                out[fid] = true
                nOut = nOut + 1
            end
        end
    end
    local left = N - nOut

    local parts = type(result.parts) == 'table' and result.parts or {}
    local disinfected, sutured, dressed, haemo
    local gauze = 0
    local q = {}
    if session.easy then
        disinfected, sutured, dressed, haemo = true, true, true, true
        gauze = 1
        q = { extracted = score, sutured = score, dressed = score }
    else
        local fallback = result.fallback == true
        if fallback then score = math.min(score, 60) end
        disinfected = result.disinfected == true and clamp(result.coverage, 0, 1) >= 0.85
        haemo = result.haemostasis == true
        local secs = math.floor(clamp(result.sections, 1, 12))
        sutured = result.sutured == true and clamp(result.closed, 0, 1) >= 0.99
            and math.floor(clamp(result.stitches, 0, 30)) >= math.max(1, secs - 1)
        dressed = result.dressed == true and clamp(result.stuck, 0, 1) >= 0.5 and clamp(result.cover, 0, 1) >= 0.5
        gauze = math.floor(clamp(result.gauze, 0, tonumber(C.gauzeMax) or 6))
        -- the score must agree with the step scores and with what really happened
        if not fallback then score = math.min(score, weightsScore(parts) + 2) end
        if nOut == 0 then score = math.min(score, 30) end
        if not disinfected then score = math.min(score, 80) end
        if not sutured then score = math.min(score, 70) end
        q = {
            extracted = nOut > 0 and math.floor(clamp(parts.extract, 0, 100)) or nil,
            sutured = sutured and math.floor(clamp(parts.suture, 0, 100)) or nil,
            dressed = dressed and math.floor(clamp(parts.dressing, 0, 100)) or nil,
        }
    end

    -- supplies: the suture kit and the dressing only when used, gauze as opened (at least one)
    local used = { suture_kit = 0, dressing = 0, gauze = 0, surgical_kit = 0 }
    if sutured then
        if take(src, 'suture_kit', 1) then used.suture_kit = 1 else sutured = false; q.sutured = nil end
    end
    if dressed then
        if take(src, 'dressing', 1) then used.dressing = 1 else dressed = false; q.dressed = nil end
    end
    if gauze > 0 then
        local n = math.min(gauze, count(src, 'gauze'))
        if n > 0 and take(src, 'gauze', n) then used.gauze = n end
    end
    if C.consumeKit and take(src, 'surgical_kit', 1) then used.surgical_kit = 1 end

    -- blood the operation cost: the live estimate, kept inside what this work could cost
    local loss
    if session.easy then
        loss = tonumber(B.easy) or 110
    else
        local expect = (tonumber(B.base) or 45) + (tonumber(B.perFragment) or 20) * nOut
            + (tonumber(B.poorWork) or 220) * (1 - score / 100)
        loss = clamp(result.bloodLoss, tonumber(B.min) or 15, tonumber(B.max) or 900)
        loss = clamp(loss, expect * 0.5, expect * 2.5)
        loss = clamp(loss, tonumber(B.min) or 15, tonumber(B.max) or 900)
    end
    loss = math.floor(loss + 0.5)

    -- the wound
    local patch = { treat = {}, quality = {} }
    patch.retained = math.max(0, (tonumber(inj.retained) or N) - nOut)
    if patch.retained == 0 then
        patch.treat.extracted = true
        patch.retainedDepth = 0
    end
    if sutured then patch.treat.sutured = true end
    if dressed then patch.treat.dressed = true end
    for k, v in pairs(q) do patch.quality[k] = v end
    local Bl = C.Bleed or {}
    if nOut > 0 then
        local f = haemo and (tonumber(Bl.controlled) or 0.3) or (tonumber(Bl.open) or 0.7)
        patch.bleedBase = round((tonumber(inj.bleedBase) or tonumber(inj.bleed) or 0) * f, 2)
    end
    local cont = clamp(inj.contamination, 0, 100)
    if disinfected then
        local cov = session.easy and 1 or clamp(result.coverage, 0, 1)
        cont = cont * ((tonumber(I.prepKeeps) or 0.15) + (1 - cov))
    else
        cont = cont + (tonumber(I.noPrep) or 30)
    end
    cont = cont + patch.retained * (tonumber(I.leftPieces) or 15)
    patch.contamination = math.floor(clamp(cont, 0, 100) + 0.5)
    NZA.Patients.UpdateInjury(p.pid, inj.id, patch)
    if loss > 0 then NZA.Patients.AddBlood(p.pid, -loss) end

    local msg
    if nOut == 0 then
        msg = L('done_none')
    elseif patch.retained > 0 then
        msg = L('done_partial', nOut, patch.retained)
    elseif sutured and dressed then
        msg = L('done_msg', nOut, loss)
    else
        msg = L('done_open', nOut, loss)
    end
    local outcome = {
        score = math.floor(score + 0.5),
        msg = msg,
        extracted = nOut, left = patch.retained, sutured = sutured, dressed = dressed,
        disinfected = disinfected, haemostasis = haemo, bloodLoss = loss, quality = q, used = used,
        record = {
            action = 'bullet', injury = inj.type, region = inj.region, extracted = nOut, left = patch.retained,
            sutured = sutured, dressed = dressed, disinfected = disinfected, bloodLoss = loss,
            score = math.floor(score + 0.5), easy = session.easy or nil,
            seconds = math.floor(tonumber(session.elapsed) or 0),
        },
    }
    if p.kind == 'player' and p.src and p.src ~= src then
        core().Notify(p.src, nOut > 0 and L('notify_patient_done') or L('notify_patient_stop'), 'info', L('label'))
    end
    NZA.Bus.Emit('bullet:done', src, p, inj, outcome)
    return outcome
end

local function onAbort(src, p, session, reason)
    -- a wound opened and then abandoned still bled: the client reported its estimate just before
    local lost = session and tonumber(session.partialLoss) or 0
    if p and lost >= 1 and p.state ~= 'dead' then NZA.Patients.AddBlood(p.pid, -math.floor(lost + 0.5)) end
    if p and p.kind == 'player' and p.src and p.src ~= src and reason ~= 'replaced' then
        core().Notify(p.src, L('notify_patient_stop'), 'info', L('label'))
    end
end

-- C→S right before the surgeon stops: the blood the open wound cost so far (validated, applied in onAbort)
RegisterNetEvent('nza:bullet:partial', function(token, loss)
    local src = source
    if core().Rate and not core().Rate('nza:bullet:partial', src, 3, 5000) then return end
    local s = type(token) == 'string' and NZA.Proc.Session and NZA.Proc.Session(token) or nil
    if not s or s.src ~= src or s.name ~= 'bullet' or s.easy then return end
    local B = cfg().Blood or {}
    local elapsed = math.max(0, (GetGameTimer() - (tonumber(s.startedAt) or GetGameTimer())) / 1000)
    local cap = math.min(tonumber(B.max) or 900, elapsed / 60 * (tonumber(B.perMinute) or 160))
    s.partialLoss = clamp(loss, 0, cap)
end)

NZA.Proc.Register('bullet', {
    perm = cfg().perm or 'surgery',
    label = L('label'),
    items = function() return itemsOf(cfg().items) end,
    consume = 'finish',
    minTime = tonumber(cfg().minTime) or 45,
    maxTime = tonumber(cfg().maxTime) or 1500,
    easyTime = tonumber(cfg().easyTime) or 15,
    maxDist = tonumber(cfg().maxDist) or 3.0,
    self = cfg().allowSelf == true,
    states = { alive = true, wounded = true },
    onStart = onStart,
    onFinish = onFinish,
    onAbort = onAbort,
})

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEM
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1500)
    if not cfg().usableItem then return end
    local name = itemName('surgical_kit')
    if not name or not (Bridge and Bridge.Inv and Bridge.Inv.RegisterUsable) then return end
    local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src)
        src = tonumber(src)
        if not src then return end
        if core().Rate and not core().Rate('nza:bullet:use', src, 1, 1500) then return end
        if not NZA.Staff.Can(src, cfg().perm or 'surgery') then
            core().Notify(src, L('err_perm'), 'error', L('label'))
            return
        end
        TriggerClientEvent('nza:bullet:use', src)
    end)
    if not ok then NZA.Warn('bullet: RegisterUsable failed: ' .. tostring(err)) end
end)
