--[[
    NAYZEEE AMBULANCE - Burn care & skin graft (server)

    Server side of the two burn procedures (ARCHITECTURE §5.2). The client plays one 3D app
    (html/apps/burn): 1 cool → 2 assess depth → 3 debride → (full thickness: 4 excise → 5 harvest
    → 6 mesh → 7 apply & staple) → 8 dress. Burn care covers steps 1-3 (+ 8 when the burn is
    only partial thickness or the medic dresses it now and grafts later); the graft covers 4-8.

    Procedures
      NZA.Proc.Register('burn',  { perm = Config.Burn.perm,       items = saline, ... })
        payload  { injury = <injury id> }
        onStart  → the burn must still need care; burn_dressing must be carried; returns the case
        onFinish → cooled / debrided / dressed (+ irrigated), quality per step, burn temp & soot,
                   pain relief, contamination, heal bonus, body cooling for over-cooling,
                   takes the burn dressing (when dressed) and the optional sterile dressing
      NZA.Proc.Register('graft', { perm = Config.Burn.Graft.perm, items = graft_kit, ... })
        payload  { injury = <injury id>, continue = bool (straight from burn care) }
        onStart  → full-thickness burn, care done (or continuing within continueWindow), patient in
                   surgery / the ambulance bay (skipped in easy mode), burn_dressing carried
        onFinish → excision, blood loss, donor-site graze, grafted / dressed, quality, heal bonus
    Callback   nza:burn:graftCheck (target, injuryId, continuing) → { ok, err, msg }
               used by the app before it offers "go on to the graft"
    Net event  nza:burn:use (S→C) when the graft kit item is used
    Bus        burn:done (src, patient, injury, outcome)   graft:done (src, patient, injury, outcome)
    Lua API    NZA.Burn.Find(p, id) · CareEligible(inj, easy) · GraftEligible(inj, easy, continued)
               · Location(p) · Donor(p, inj) · Case(src, p, inj, mode, info)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Burn = NZA.Burn or {}
local B = NZA.Burn
local U = NZA.Util

local careDone = {}      -- ['pid:injId'] = { at = os.time(), src = medic } (burn care that chose "go on to graft")

local function cfg()
    return Config.Burn or {}
end

local function gcfg()
    return (Config.Burn or {}).Graft or {}
end

local function game()
    return (Config.Burn or {}).Game or {}
end

local function core()
    return NZA.Core or {}
end

local function L(key, ...)
    return NZA.L('burn.' .. key, ...)
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
    if not name or (n or 0) <= 0 or not core().TakeItems then return false end
    return core().TakeItems(src, { [name] = n }) == true
end

local function hash(str)
    local h = 5381
    str = tostring(str)
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 2147483647 end
    return h
end

-- items that are always taken at the end (the dressing is taken by hand only when it was used)
local function alwaysItems(list)
    local out = {}
    for key, n in pairs(list or {}) do
        local name = itemName(key)
        local c = math.floor(tonumber(n) or 0)
        if name and c > 0 and key ~= 'burn_dressing' then out[name] = c end
    end
    return out
end

local function dressingNeed(list)
    return math.floor(tonumber((list or {}).burn_dressing) or 0)
end

-- ════════════════════════════════════════════════════════════════════════
-- RULES
-- ════════════════════════════════════════════════════════════════════════

function B.Find(p, id)
    local inj = id and p and p.injuries and p.injuries[id] or nil
    if inj and inj.type == 'burn' then return inj end
    return nil
end

local function burnOf(inj)
    local b = inj.burn or {}
    return {
        degree = math.floor(clamp(b.degree, 1, 3)),
        area = clamp(b.area, 1, 99),
        temp = clamp(b.temp, 30, 80),
        soot = clamp(b.soot, 0, 100),
        full = clamp(b.full, 0, 100),
    }
end

-- Does this burn still need burn care? → ok, reason ('type' | 'done' | 'graft')
function B.CareEligible(inj, easy)
    if type(inj) ~= 'table' or inj.type ~= 'burn' then return false, 'type' end
    local t = inj.treat or {}
    if t.grafted then return false, 'done' end
    local b = burnOf(inj)
    if b.degree <= 1 and t.dressed then return false, 'done' end
    if t.cooled and t.debrided and t.dressed then
        if b.degree >= 3 and b.full > 0 then return false, 'graft' end
        return false, 'done'
    end
    return true
end

-- Can this burn be grafted now? continued = straight from burn care (care flags may still be pending)
-- → ok, reason ('type' | 'done' | 'partial' | 'care')
function B.GraftEligible(inj, easy, continued)
    if type(inj) ~= 'table' or inj.type ~= 'burn' then return false, 'type' end
    local t = inj.treat or {}
    if t.grafted then return false, 'done' end
    local b = burnOf(inj)
    if b.degree < 3 or b.full <= 0 then return false, 'partial' end
    if easy or continued then return true end
    if gcfg().needCare ~= false and not (t.cooled and t.debrided) then return false, 'care' end
    return true
end

-- Surgery table / configured hospital point or the ambulance treatment bay
function B.Location(p)
    local meta = p and p.meta or {}
    local locs = gcfg().locations or {}
    if type(meta.bed) == 'table' and meta.bed.type and locs[meta.bed.type] then return true end
    if meta.bay and locs.bay then return true end
    return false
end

-- Donor thigh: the side away from the burn, else picked from the patient id
function B.Donor(p, inj)
    local list = gcfg().donorRegions or { 'l_upper_leg', 'r_upper_leg' }
    if #list == 0 then return 'l_upper_leg' end
    local R = NZA.Const.Region and NZA.Const.Region[inj and inj.region or ''] or nil
    local side = R and R.side or nil
    if side then
        for _, r in ipairs(list) do
            local D = NZA.Const.Region[r]
            if D and D.side and D.side ~= side and r ~= inj.region then return r end
        end
    end
    for _, r in ipairs(list) do
        if not inj or r ~= inj.region then
            if (hash(p and p.pid or '') % 2 == 0) or #list == 1 then return r end
        end
    end
    return list[#list] ~= (inj and inj.region) and list[#list] or list[1]
end

local function regionLabel(r)
    return (U.RegionLabel and U.RegionLabel(r)) or r
end

-- The case the NUI needs: burn geometry and numbers, patient, supplies and what comes next
function B.Case(src, p, inj, mode, info)
    info = info or {}
    local b = burnOf(inj)
    local t = inj.treat or {}
    local tones = cfg().skinTones or { 0.3 }
    local tone = tones[(hash(p.pid) % #tones) + 1] or 0.3
    local donor = B.Donor(p, inj)
    local raw = inj.burn or {}
    return {
        mode = mode,
        injury = {
            id = inj.id, type = 'burn', region = inj.region, severity = inj.severity,
            regionLabel = regionLabel(inj.region),
            label = (U.InjuryLabel and U.InjuryLabel('burn')) or 'Burn',
            pain = math.floor(clamp(inj.pain, 0, 100) + 0.5),
            contamination = math.floor(clamp(inj.contamination, 0, 100) + 0.5),
            burn = {
                degree = b.degree, area = round(b.area), temp = round(b.temp, 1), soot = round(b.soot),
                full = round(b.full), assessed = raw.assessed == true,
                assessedFull = raw.assessedFull and round(raw.assessedFull) or nil,
                excised = raw.excised and round(raw.excised, 2) or nil,
            },
            treat = {
                cooled = t.cooled == true, debrided = t.debrided == true,
                dressed = t.dressed == true, grafted = t.grafted == true,
            },
        },
        patient = { name = p.name, sex = p.sex, temp = round(p.temp or 37, 1), kind = p.kind },
        tone = tone,
        seed = hash(p.pid .. ':' .. tostring(inj.id)),
        donor = donor, donorLabel = regionLabel(donor),
        items = {
            burnDressing = count(src, 'burn_dressing'),
            dressing = (tonumber((cfg().optional or {}).dressing) or 0) > 0 and count(src, 'dressing') or 0,
            graftKit = count(src, 'graft_kit'),
            saline = count(src, 'saline'),
        },
        graft = info.graft,
        easy = info.easy == true,
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- GRAFT PRE-CHECK (shown before the app offers "go on to the graft")
-- ════════════════════════════════════════════════════════════════════════

local function graftCheck(src, p, inj, continuing)
    local G = gcfg()
    local perm = G.perm or 'graft'
    if not NZA.Staff.Can(src, perm) then return { ok = false, err = 'no_perm', msg = L('why_graft_perm') } end
    local easy = NZA.Staff.Easy and NZA.Staff.Easy(src, perm) or false
    local ok, why = B.GraftEligible(inj, easy, continuing)
    if not ok then return { ok = false, err = why, msg = L('err_graft_' .. why) } end
    local need = {}
    for key, n in pairs(G.items or {}) do
        local name = itemName(key)
        if name and (tonumber(n) or 0) > 0 then need[name] = math.floor(tonumber(n)) end
    end
    local okItems, missing = core().CheckItems(src, need)
    if not okItems then
        local label = missing and core().B and core().B('Inv.Label', missing) or missing
        return { ok = false, err = 'missing_item', msg = L('why_graft_item', tostring(label or '?')) }
    end
    if G.requireLocation ~= false and not easy and not B.Location(p) then
        return { ok = false, err = 'location', msg = L('why_graft_location') }
    end
    return { ok = true, easy = easy }
end

lib.callback.register('nza:burn:graftCheck', function(src, target, injuryId, continuing)
    src = tonumber(src)
    if not src or not core().Rate('nza:burn:check', src, 4, 2000) then return { ok = false, err = 'rate' } end
    local p, err = core().TargetChecks(src, { perm = cfg().perm or 'burn', maxDist = tonumber(cfg().maxDist) or 3.0, self = cfg().allowSelf == true,
        states = { alive = true, wounded = true } }, target, { slack = 2.0 })
    if not p then return { ok = false, err = err, msg = L('err_' .. tostring(err)) } end
    local inj = B.Find(p, injuryId)
    if not inj then return { ok = false, err = 'no_injury', msg = L('err_no_injury') } end
    return graftCheck(src, p, inj, continuing == true)
end)

-- ════════════════════════════════════════════════════════════════════════
-- BURN CARE
-- ════════════════════════════════════════════════════════════════════════

local function careStart(src, p, payload, info)
    local inj = B.Find(p, type(payload) == 'table' and payload.injury or nil)
    if not inj then return false, { err = 'no_injury', msg = L('err_no_injury') } end
    local easy = type(info) == 'table' and info.easy == true
    local ok, why = B.CareEligible(inj, easy)
    if not ok then return false, { err = why, msg = L('err_' .. why) } end
    local needD = dressingNeed(cfg().items)
    if needD > 0 and count(src, 'burn_dressing') < needD then
        local label = core().B and core().B('Inv.Label', itemName('burn_dressing')) or itemName('burn_dressing')
        return false, { err = 'missing_item', msg = L('err_item', tostring(label)) }
    end
    local gc = graftCheck(src, p, inj, true)
    local case = B.Case(src, p, inj, 'care', { easy = easy, graft = { ok = gc.ok == true, msg = gc.msg, err = gc.err } })
    if p.kind == 'player' and p.src and p.src ~= src then
        core().Notify(p.src, L('notify_patient'), 'info', L('label'))
    end
    return true, case
end

local function careFinish(src, p, session, result)
    local case = session.data or {}
    local inj = case.injury and B.Find(p, case.injury.id) or nil
    if not inj then return { msg = L('gone'), score = 0 } end
    local C, G = cfg(), game()
    local b = burnOf(inj)
    result = type(result) == 'table' and result or {}
    local score = clamp(result.score, 0, 100)
    local parts = type(result.parts) == 'table' and result.parts or {}
    local raw = inj.burn or {}

    local cooled, debrided, dressed, continue
    local q = {}
    local temp, soot = b.temp, b.soot
    local secured = false
    local fullEst = raw.assessedFull
    local overcool = 0

    if session.easy then
        cooled, debrided = true, true
        temp = math.min(b.temp, (tonumber(C.cooledBelow) or 31) - 2)
        soot = math.min(soot, 5)
        -- full-thickness burn and the medic can graft right away → leave the dressing to the graft
        continue = b.degree >= 3 and b.full > 0 and graftCheck(src, p, inj, true).ok == true
        dressed = not continue
        q = { cooled = score, debrided = score, dressed = dressed and score or nil }
        fullEst = b.full
    else
        temp = clamp(result.surfaceTemp, 10, 80)
        soot = clamp(result.sootLeft, 0, 100)
        cooled = result.cooled == true and temp <= (tonumber(C.cooledBelow) or 31) + 0.05
        local dfrac = clamp(result.debrided, 0, 1)
        local nothing = (tonumber(result.debrideTotal) or 0) <= 0
        debrided = nothing or dfrac >= (tonumber(C.debridedMin) or 0.75)
        if nothing and b.degree <= 1 then debrided = false end   -- superficial burns are never debrided
        continue = result.continue == true and b.degree >= 3 and b.full > 0
        -- "graft now" only counts when the graft could really start (perm, kit, room); otherwise the
        -- burn simply ends undressed and the medic is told so
        if continue and graftCheck(src, p, inj, true).ok ~= true then continue = false end
        dressed = not continue and result.dressed == true and clamp(result.stuck, 0, 1) >= 0.5 and clamp(result.cover, 0, 1) >= 0.5
        if result.tested then fullEst = clamp(result.fullEst, 0, 100) end
        overcool = clamp(result.overcool, 0, tonumber(session.elapsed) or 0)
        q = {
            cooled = cooled and math.floor(clamp(parts.cool, 0, 100)) or nil,
            debrided = debrided and math.floor(clamp(parts.debride, 0, 100)) or nil,
            dressed = dressed and math.floor(clamp(parts.dressing, 0, 100)) or nil,
        }
        -- the score must agree with the step scores (Config.Burn.Game.weights)
        local W = G.weights or {}
        local wc, wa, wd, wr = tonumber(W.cool) or 35, tonumber(W.assess) or 15, tonumber(W.debride) or 25, tonumber(W.dressing) or 25
        if continue then wr = 0 end
        local wsum = wc + wa + wd + wr
        if wsum > 0 then
            local calc = (clamp(parts.cool, 0, 100) * wc + clamp(parts.assess, 0, 100) * wa
                + clamp(parts.debride, 0, 100) * wd + clamp(parts.dressing, 0, 100) * wr) / wsum
            score = math.min(score, calc + 2)
        end
        if not cooled then score = math.min(score, 60) end
        if not continue and not dressed then score = math.min(score, 55) end
        secured = result.secured == true and dressed and b.area >= (tonumber(C.secureAbove) or 60)
    end

    -- supplies used by hand: the burn dressing (when dressed) and the optional sterile dressing
    if dressed and dressingNeed(C.items) > 0 then
        if not take(src, 'burn_dressing', dressingNeed(C.items)) then dressed = false; q.dressed = nil end
    end
    if secured then
        local n = math.floor(tonumber((C.optional or {}).dressing) or 0)
        if n <= 0 or count(src, 'dressing') < n or not take(src, 'dressing', n) then secured = false end
    end

    -- burn record, pain, contamination, healing
    local patch = { treat = {}, quality = {}, burn = {} }
    if cooled then patch.treat.cooled = true; patch.treat.irrigated = true end
    if debrided then patch.treat.debrided = true end
    if dressed then patch.treat.dressed = true end
    for k, v in pairs(q) do patch.quality[k] = v end
    patch.burn.temp = round(temp, 1)
    patch.burn.soot = math.floor(soot + 0.5)
    patch.burn.assessed = true
    if fullEst then patch.burn.assessedFull = math.floor(clamp(fullEst, 0, 100) + 0.5) end

    local coolQ = cooled and clamp(q.cooled or score, 0, 100) / 100 or 0
    patch.pain = math.floor(clamp((tonumber(inj.pain) or 0) * (1 - (tonumber(C.painRelief) or 0.2) * coolQ), 0, 100) + 0.5)
    local cont = clamp(inj.contamination, 0, 100)
    if cooled then cont = cont * (0.35 + 0.65 * soot / 100) end
    if debrided then cont = cont * 0.7 end
    if dressed then cont = cont * 0.8 end
    patch.contamination = math.floor(cont + 0.5)
    local definitive = (b.degree <= 1 and (cooled or dressed)) or (b.degree == 2 and dressed)
    if definitive then
        patch.heal = math.floor(clamp((tonumber(inj.heal) or 0) + (tonumber(C.healBonus) or 12) * score / 100, 0, 99))
    end
    NZA.Patients.UpdateInjury(p.pid, inj.id, patch)

    -- over-cooling chills the patient (core physiology reads meta.wet as body cooling)
    if overcool > 0.5 then
        local secs = math.min(tonumber(C.overcoolMax) or 420, overcool * (tonumber(C.overcoolWet) or 8))
        local untilT = os.time() + math.floor(secs)
        local cur = tonumber(p.meta and p.meta.wet) or 0
        NZA.Patients.SetMeta(p.pid, 'wet', math.max(cur, untilT))
    end

    if continue then
        careDone[p.pid .. ':' .. tostring(inj.id)] = { at = os.time(), src = src }
    end

    local msg
    if continue then msg = L('done_continue')
    elseif dressed and cooled then msg = L('done_msg')
    elseif dressed then msg = L('done_msg_warm')
    elseif cooled then msg = L('done_msg_nodress')
    else msg = L('done_partial') end

    local outcome = {
        score = math.floor(score + 0.5), msg = msg,
        cooled = cooled == true, debrided = debrided == true, dressed = dressed == true, secured = secured,
        continue = continue == true, temp = round(temp, 1), soot = math.floor(soot + 0.5),
        overcool = round(overcool, 1), quality = q, phase = 'care',
        record = {
            action = 'burn', region = inj.region, degree = b.degree, area = b.area,
            cooled = cooled == true, debrided = debrided == true, dressed = dressed == true,
            temp = round(temp, 1), soot = math.floor(soot + 0.5), score = math.floor(score + 0.5),
            easy = session.easy or nil, seconds = math.floor(tonumber(session.elapsed) or 0),
        },
    }
    NZA.Bus.Emit('burn:done', src, p, inj, outcome)
    return outcome
end

local function careAbort(src, p, session, reason)
    if p and p.kind == 'player' and p.src and p.src ~= src and reason ~= 'replaced' then
        core().Notify(p.src, L('notify_patient_stop'), 'info', L('label'))
    end
end

NZA.Proc.Register('burn', {
    perm = cfg().perm or 'burn',
    label = L('label'),
    items = function() return alwaysItems(cfg().items) end,
    consume = 'finish',
    minTime = tonumber(cfg().minTime) or 18,
    maxTime = tonumber(cfg().maxTime) or 900,
    easyTime = tonumber(cfg().easyTime) or 10,
    maxDist = tonumber(cfg().maxDist) or 3.0,
    self = cfg().allowSelf == true,
    states = { alive = true, wounded = true },
    onStart = careStart,
    onFinish = careFinish,
    onAbort = careAbort,
})

-- ════════════════════════════════════════════════════════════════════════
-- SKIN GRAFT
-- ════════════════════════════════════════════════════════════════════════

local function continued(src, p, inj, payload)
    if type(payload) ~= 'table' or payload.continue ~= true then return false end
    local rec = careDone[p.pid .. ':' .. tostring(inj.id)]
    if not rec or rec.src ~= src then return false end
    return os.time() - rec.at <= (tonumber(gcfg().continueWindow) or 180)
end

local function graftStart(src, p, payload, info)
    local G = gcfg()
    local inj = B.Find(p, type(payload) == 'table' and payload.injury or nil)
    if not inj then return false, { err = 'no_injury', msg = L('err_no_injury') } end
    local easy = type(info) == 'table' and info.easy == true
    local cont = continued(src, p, inj, payload)
    local ok, why = B.GraftEligible(inj, easy, cont)
    if not ok then return false, { err = why, msg = L('err_graft_' .. why) } end
    if G.requireLocation ~= false and not easy and not B.Location(p) then
        return false, { err = 'location', msg = L('why_graft_location') }
    end
    local needD = dressingNeed(G.items)
    if needD > 0 and count(src, 'burn_dressing') < needD then
        local label = core().B and core().B('Inv.Label', itemName('burn_dressing')) or itemName('burn_dressing')
        return false, { err = 'missing_item', msg = L('err_item', tostring(label)) }
    end
    local case = B.Case(src, p, inj, 'graft', { easy = easy })
    case.continued = cont
    if p.kind == 'player' and p.src and p.src ~= src and not cont then
        core().Notify(p.src, L('notify_patient_graft'), 'info', L('graft_label'))
    end
    return true, case
end

local function graftFinish(src, p, session, result)
    local case = session.data or {}
    local inj = case.injury and B.Find(p, case.injury.id) or nil
    if not inj then return { msg = L('gone'), score = 0 } end
    local C, G, GM = cfg(), gcfg(), game()
    local b = burnOf(inj)
    result = type(result) == 'table' and result or {}
    local score = clamp(result.score, 0, 100)
    local parts = type(result.parts) == 'table' and result.parts or {}
    local fullCm2 = b.area * b.full / 100

    local excised, grafted, dressed
    local excisedFrac, excisedCm2, donorCm2, coverage, staples, ratio
    local q = {}

    if session.easy then
        excisedFrac, coverage, staples = 1, 1, 1
        excisedCm2 = fullCm2
        donorCm2 = fullCm2 / 1.5
        ratio = '1:1.5'
        excised, grafted, dressed = true, true, true
        q = { grafted = score, dressed = score }
    else
        excisedFrac = clamp(result.excised, 0, 1)
        excisedCm2 = clamp(result.excisedCm2, 0, fullCm2 * 1.6 + 2)
        donorCm2 = clamp(result.donorCm2, 0, 400)
        coverage = clamp(result.coverage, 0, 1)
        staples = clamp(result.staples, 0, 1)
        ratio = result.ratio == '1:3' and '1:3' or '1:1.5'
        excised = excisedFrac >= (tonumber(G.minExcised) or 0.7)
        grafted = excised and donorCm2 > 0 and coverage >= (tonumber(G.minCoverage) or 0.7)
            and staples >= (tonumber(G.minStaples) or 0.6)
        dressed = result.dressed == true and clamp(result.stuck, 0, 1) >= 0.5 and clamp(result.cover, 0, 1) >= 0.5
        q = {
            grafted = grafted and math.floor(clamp(parts.graft, 0, 100)) or nil,
            dressed = dressed and math.floor(clamp(parts.dressing, 0, 100)) or nil,
        }
        local W = GM.graftWeights or {}
        local we, wh, wm = tonumber(W.excise) or 25, tonumber(W.harvest) or 20, tonumber(W.mesh) or 15
        local wg, wd = tonumber(W.graft) or 25, tonumber(W.dressing) or 15
        local wsum = we + wh + wm + wg + wd
        if wsum > 0 then
            local calc = (clamp(parts.excise, 0, 100) * we + clamp(parts.harvest, 0, 100) * wh + clamp(parts.mesh, 0, 100) * wm
                + clamp(parts.graft, 0, 100) * wg + clamp(parts.dressing, 0, 100) * wd) / wsum
            score = math.min(score, calc + 2)
        end
        if not grafted then score = math.min(score, 40) end
        if not dressed then score = math.min(score, 70) end
    end

    if dressed and dressingNeed(G.items) > 0 then
        if not take(src, 'burn_dressing', dressingNeed(G.items)) then dressed = false; q.dressed = nil end
    end

    -- blood: the excised bed and the donor site bleed
    local ml = excisedCm2 * (tonumber(G.bloodPerCm2) or 0.9) + donorCm2 * (tonumber(G.donorBloodPerCm2) or 0.3)
    ml = math.floor(math.min(tonumber(G.maxBlood) or 600, ml) + 0.5)
    if ml > 0 then NZA.Patients.AddBlood(p.pid, -ml) end

    local patch = { treat = {}, quality = {}, burn = {} }
    if grafted then patch.treat.grafted = true end
    if dressed then patch.treat.dressed = true end
    for k, v in pairs(q) do patch.quality[k] = v end
    patch.burn.excised = round(excisedFrac, 2)
    patch.burn.ratio = ratio
    if grafted then
        patch.contamination = math.floor(clamp(inj.contamination, 0, 100) * 0.3 + 0.5)
        patch.pain = math.floor(clamp((tonumber(inj.pain) or 0) * 0.8, 0, 100) + 0.5)
        patch.heal = math.floor(clamp((tonumber(inj.heal) or 0) + (tonumber(C.healBonus) or 12) * score / 100, 0, 99))
    elseif excised then
        -- an open, excised bed without a graft is raw: it bleeds and gets dirty unless dressed
        patch.contamination = math.floor(clamp((tonumber(inj.contamination) or 0) + (dressed and 0 or 15), 0, 100) + 0.5)
    end
    NZA.Patients.UpdateInjury(p.pid, inj.id, patch)

    -- the donor thigh: a shallow, dressed graze that heals by itself
    local donor = case.donor or B.Donor(p, inj)
    if G.donorInjury ~= false and donorCm2 > 0 and NZA.Const.Region[donor] then
        NZA.Patients.AddInjury(p.pid, {
            region = donor, type = 'abrasion', severity = 1, cause = 'graft', complications = false,
            pain = 18, contamination = 0, treat = { dressed = true, irrigated = true },
        }, true)
    end
    careDone[p.pid .. ':' .. tostring(inj.id)] = nil

    local msg
    if grafted and dressed then msg = L('graft_done_msg', ratio)
    elseif grafted then msg = L('graft_done_nodress')
    elseif excised then msg = L('graft_done_open')
    else msg = L('graft_done_partial') end

    local outcome = {
        score = math.floor(score + 0.5), msg = msg, phase = 'graft',
        grafted = grafted == true, excised = excised == true, dressed = dressed == true,
        ratio = ratio, blood = ml, coverage = round(coverage, 2), quality = q,
        record = {
            action = 'graft', region = inj.region, donor = donor, ratio = ratio,
            excised = round(excisedFrac, 2), coverage = round(coverage, 2), blood = ml,
            grafted = grafted == true, dressed = dressed == true, score = math.floor(score + 0.5),
            easy = session.easy or nil, seconds = math.floor(tonumber(session.elapsed) or 0),
        },
    }
    NZA.Bus.Emit('graft:done', src, p, inj, outcome)
    return outcome
end

local function graftAbort(src, p, session, reason)
    if p and p.kind == 'player' and p.src and p.src ~= src and reason ~= 'replaced' then
        core().Notify(p.src, L('notify_patient_stop'), 'info', L('graft_label'))
    end
end

NZA.Proc.Register('graft', {
    perm = gcfg().perm or 'graft',
    label = L('graft_label'),
    items = function() return alwaysItems(gcfg().items) end,
    consume = 'finish',
    minTime = tonumber(gcfg().minTime) or 30,
    maxTime = tonumber(gcfg().maxTime) or 1200,
    easyTime = tonumber(gcfg().easyTime) or 12,
    maxDist = tonumber(gcfg().maxDist) or 3.0,
    self = false,
    states = { alive = true, wounded = true },
    onStart = graftStart,
    onFinish = graftFinish,
    onAbort = graftAbort,
})

-- forget stale "go on to the graft" records
CreateThread(function()
    while true do
        Wait(60000)
        local now, win = os.time(), (tonumber(gcfg().continueWindow) or 180) + 60
        for k, rec in pairs(careDone) do
            if now - rec.at > win then careDone[k] = nil end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEM (graft kit; the burn dressing item belongs to first aid)
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1500)
    if not cfg().usableItem then return end
    local name = itemName('graft_kit')
    if not name or not (Bridge and Bridge.Inv and Bridge.Inv.RegisterUsable) then return end
    local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src)
        src = tonumber(src)
        if not src then return end
        if core().Rate and not core().Rate('nza:burn:use', src, 1, 1500) then return end
        if not NZA.Staff.Can(src, cfg().perm or 'burn') then
            core().Notify(src, L('err_perm'), 'error', L('label'))
            return
        end
        TriggerClientEvent('nza:burn:use', src)
    end)
    if not ok then NZA.Warn('burn: RegisterUsable failed: ' .. tostring(err)) end
end)
