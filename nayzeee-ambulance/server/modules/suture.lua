--[[
    NAYZEEE AMBULANCE - Suture / wound closure (server)

    Server side of the suture procedure (ARCHITECTURE §5.2). The client plays the 3D minigame
    (html/apps/suture: irrigate → numb → stitch → dress); the server decides which injuries
    may be closed, checks the supplies, enforces the timing and applies the result.

    Procedure
      NZA.Proc.Register('suture', { perm = Config.Suture.perm, items, minTime, maxTime, easyTime, maxDist,
                                    onStart, onFinish, onAbort })
        payload  { injury = <injury id> }
        onStart  → the injury must be closable (Su.Eligible), optional location rule (skipped in easy
                   mode: easy mode only needs the injury's supplies); returns the case for the NUI
        onFinish → validates the minigame result, takes the optional supplies that were used
                   (lidocaine, gauze), sets injury.treat.irrigated / anesthetized / sutured / dressed,
                   quality per step, contamination 0 when irrigated; physiology then applies the
                   sutured bleed modifier (×0.05)
    Usable item: Config.Items.suture_kit → client event 'nza:suture:use' (start on the nearest patient)
    Bus events emitted: suture:done (src, patient, injury, outcome)
    Lua API: NZA.Suture.Eligible(injury, easy) → ok, reason   NZA.Suture.Location(patient) → ok
             NZA.Suture.Case(src, patient, injury) → client case table
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Suture = NZA.Suture or {}
local Su = NZA.Suture
local U = NZA.Util

local function cfg()
    return Config.Suture or {}
end

local function core()
    return NZA.Core or {}
end

local function L(key, ...)
    return NZA.L('suture.' .. key, ...)
end

local function clamp(v, a, b)
    v = tonumber(v) or a
    if v ~= v then v = a end
    if v < a then return a end
    if v > b then return b end
    return v
end

local function itemName(key)
    return Config.Items and Config.Items[key] or nil
end

-- Config.Suture.items (Config.Items keys → count) → { [item name] = count }
local function requiredItems()
    local out = {}
    for key, n in pairs(cfg().items or {}) do
        local name = itemName(key)
        local c = math.floor(tonumber(n) or 0)
        if name and c > 0 then out[name] = c end
    end
    return out
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

-- ════════════════════════════════════════════════════════════════════════
-- RULES
-- ════════════════════════════════════════════════════════════════════════

-- Can this injury be closed now? → ok, reason ('type' | 'done' | 'retained' | 'bleeding')
function Su.Eligible(inj, easy)
    if type(inj) ~= 'table' then return false, 'no_injury' end
    local mode = (cfg().types or {})[inj.type]
    if not mode then return false, 'type' end
    local t = inj.treat or {}
    if t.sutured then return false, 'done' end
    if mode == 'controlled' and (tonumber(inj.retained) or 0) > 0 and not t.extracted then
        return false, 'retained'
    end
    if easy then return true end
    local small = (tonumber(inj.severity) or 4) <= (tonumber(cfg().smallSeverity) or 2)
    local controlled = (tonumber(inj.bleed) or 0) <= (tonumber(cfg().maxBleed) or 12)
        or t.packed or t.bandaged or t.tourniquet
    if mode == 'controlled' then small = false end
    if not small and not controlled then return false, 'bleeding' end
    return true
end

-- Patient on a hospital bed / surgery table or inside an ambulance treatment bay
function Su.Location(p)
    local meta = p and p.meta or {}
    local locs = cfg().locations or {}
    if type(meta.bed) == 'table' and meta.bed.type and locs[meta.bed.type] then return true end
    if meta.bay and locs.bay then return true end
    return false
end

local DEFAULT_LEN = { laceration = 40, stab = 22, gunshot = 22, shrapnel = 20 }

-- The case the NUI needs: wound geometry and numbers, patient, supplies on the medic
function Su.Case(src, p, inj)
    local len = tonumber(inj.length) or 0
    if len <= 0 then len = DEFAULT_LEN[inj.type] or 30 end
    if inj.type == 'gunshot' or inj.type == 'shrapnel' then len = math.max(len, 22) end   -- extraction incision
    local tones = cfg().skinTones or { 0.3 }
    local tone = tones[(hash(p.pid) % #tones) + 1] or 0.3
    local opt = cfg().optional or {}
    return {
        injury = {
            id = inj.id, type = inj.type, region = inj.region, severity = inj.severity,
            regionLabel = U.RegionLabel and U.RegionLabel(inj.region) or inj.region,
            label = U.InjuryLabel and U.InjuryLabel(inj.type) or inj.type,
            length = math.floor(clamp(len, 10, 140) + 0.5), depth = tonumber(inj.depth) or 0,
            bleed = math.floor((tonumber(inj.bleed) or 0) * 10 + 0.5) / 10,
            contamination = math.floor(clamp(inj.contamination, 0, 100) + 0.5),
            pain = math.floor(clamp(inj.pain, 0, 100) + 0.5),
        },
        patient = { name = p.name, sex = p.sex },
        tone = tone,
        seed = hash(p.pid .. ':' .. tostring(inj.id)),
        items = {
            lidocaine = (tonumber(opt.lidocaine) or 0) > 0 and count(src, 'lidocaine') or 0,
            gauze = math.min(count(src, 'gauze'), math.floor(tonumber(opt.gauze) or 0)),
        },
    }
end

-- number of stitches the client asks for (same formula as the NUI)
local function sections(len)
    local g = cfg().Game or {}
    local per = tonumber(g.mmPerStitch) or 8
    return math.floor(clamp(math.floor(len / per + 0.5), tonumber(g.minStitches) or 3, tonumber(g.maxStitches) or 12))
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE
-- ════════════════════════════════════════════════════════════════════════

local function onStart(src, p, payload, info)
    local id = type(payload) == 'table' and payload.injury or nil
    local inj = id and p.injuries and p.injuries[id] or nil
    if not inj then return false, { err = 'no_injury', msg = L('err_no_injury') } end
    local easy = type(info) == 'table' and info.easy == true
    local ok, why = Su.Eligible(inj, easy)
    if not ok then return false, { err = why, msg = L('err_' .. why) } end
    if cfg().requireLocation and not easy and not Su.Location(p) then
        return false, { err = 'location', msg = L('err_location') }
    end
    local case = Su.Case(src, p, inj)
    case.sections = sections(case.injury.length)
    if p.kind == 'player' and p.src and p.src ~= src then
        core().Notify(p.src, L('notify_patient'), 'info', L('label'))
    end
    return true, case
end

local function onFinish(src, p, session, result)
    local case = session.data or {}
    local id = case.injury and case.injury.id
    local inj = id and p.injuries[id] or nil
    if not inj then return { msg = L('gone'), score = 0 } end
    local C, G = cfg(), cfg().Game or {}
    local opt = C.optional or {}
    result = type(result) == 'table' and result or {}
    local score = clamp(result.score, 0, 100)

    local irrigated, anesthetized, sutured, dressed
    local q = {}
    local used = { lidocaine = 0, gauze = 0 }
    local contamination = clamp(inj.contamination, 0, 100)

    if session.easy then
        irrigated, sutured, dressed = true, true, true
        anesthetized = count(src, 'lidocaine') > 0 and (tonumber(opt.lidocaine) or 0) > 0
        if anesthetized then used.lidocaine = 1 end
        q = { irrigated = score, anesthetized = anesthetized and score or nil, sutured = score, dressed = score }
        contamination = 0
    else
        local parts = type(result.parts) == 'table' and result.parts or {}
        local N = tonumber(case.sections) or 3
        local stitches = math.floor(clamp(result.stitches, 0, N + (tonumber(G.extraStitches) or 3)))
        local closed = clamp(result.closed, 0, 1)
        sutured = (closed >= 0.99 or stitches >= N) and stitches >= math.max(1, N - 1)
            and clamp(parts.suture, 0, 100) >= (tonumber(C.minStitchQuality) or 0)
        local left = clamp(result.contamination, 0, 100)
        irrigated = result.irrigated == true and left <= (tonumber(C.irrigatedBelow) or 10)
        if irrigated then contamination = 0 else contamination = math.min(contamination, math.max(left, contamination * 0.5)) end
        -- optional supplies are only taken when used, and only count when the medic still has them
        if result.lido == true and (tonumber(opt.lidocaine) or 0) > 0 and count(src, 'lidocaine') > 0 then
            used.lidocaine = 1
            anesthetized = true
        end
        local swabs = math.floor(clamp(result.gauze, 0, tonumber(opt.gauze) or 0))
        if swabs > 0 then used.gauze = math.min(swabs, count(src, 'gauze')) end
        dressed = result.dressed == true and clamp(result.stuck, 0, 1) >= 0.5 and clamp(result.cover, 0, 1) >= 0.5
        q = {
            irrigated = irrigated and math.floor(clamp(parts.irrigate, 0, 100)) or nil,
            anesthetized = anesthetized and math.floor(clamp(parts.anaesthetic, 0, 100)) or nil,
            sutured = sutured and math.floor(clamp(parts.suture, 0, 100)) or nil,
            dressed = dressed and math.floor(clamp(parts.dressing, 0, 100)) or nil,
        }
        -- the score must agree with the step scores (weights from Config.Suture.Game.weights)
        local W = G.weights or {}
        local wi, wa = tonumber(W.irrigate) or 20, tonumber(W.anaesthetic) or 15
        local ws, wd = tonumber(W.suture) or 45, tonumber(W.dressing) or 20
        local wsum = wi + wa + ws + wd
        if wsum > 0 then
            local calc = (clamp(parts.irrigate, 0, 100) * wi + clamp(parts.anaesthetic, 0, 100) * wa
                + clamp(parts.suture, 0, 100) * ws + clamp(parts.dressing, 0, 100) * wd) / wsum
            score = math.min(score, calc + 2)
        end
        -- a closure that never closed cannot score well, whatever the client claims
        if not sutured then score = math.min(score, 35) end
        if not irrigated then score = math.min(score, 85) end
    end

    if used.lidocaine > 0 and not take(src, 'lidocaine', used.lidocaine) then anesthetized = false; q.anesthetized = nil end
    if used.gauze > 0 then take(src, 'gauze', used.gauze) end

    local patch = { treat = {}, quality = {} }
    if irrigated then patch.treat.irrigated = true end
    if sutured then patch.treat.sutured = true end
    if dressed then patch.treat.dressed = true end
    for k, v in pairs(q) do patch.quality[k] = v end
    patch.contamination = math.floor(contamination + 0.5)
    NZA.Patients.UpdateInjury(p.pid, inj.id, patch)
    if anesthetized then
        NZA.Patients.GiveMed(p.pid, 'lidocaine', { injury = inj.id, region = inj.region })
    end

    local stitches = session.easy and (tonumber(case.sections) or 0) or math.floor(clamp(result.stitches, 0, 30))
    local msg
    if sutured then
        msg = dressed and L('done_msg', stitches) or L('done_msg_nodress', stitches)
    else
        msg = L('done_partial')
    end
    local outcome = {
        score = math.floor(score + 0.5),
        msg = msg,
        sutured = sutured, irrigated = irrigated, anesthetized = anesthetized == true, dressed = dressed,
        stitches = stitches, quality = q, used = used,
        record = {
            action = 'suture', injury = inj.type, region = inj.region, stitches = stitches,
            irrigated = irrigated, anesthetized = anesthetized == true, dressed = dressed,
            score = math.floor(score + 0.5), easy = session.easy or nil,
            seconds = math.floor(tonumber(session.elapsed) or 0),
        },
    }
    NZA.Bus.Emit('suture:done', src, p, inj, outcome)
    return outcome
end

local function onAbort(src, p, session, reason)
    if p and p.kind == 'player' and p.src and p.src ~= src and reason ~= 'replaced' then
        core().Notify(p.src, L('notify_patient_stop'), 'info', L('label'))
    end
end

NZA.Proc.Register('suture', {
    perm = cfg().perm or 'suture',
    label = L('label'),
    items = function() return requiredItems() end,
    consume = 'finish',
    minTime = tonumber(cfg().minTime) or 25,
    maxTime = tonumber(cfg().maxTime) or 900,
    easyTime = tonumber(cfg().easyTime) or 12,
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
    local name = itemName('suture_kit')
    if not name or not (Bridge and Bridge.Inv and Bridge.Inv.RegisterUsable) then return end
    local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src)
        src = tonumber(src)
        if not src then return end
        if core().Rate and not core().Rate('nza:suture:use', src, 1, 1500) then return end
        if not NZA.Staff.Can(src, cfg().perm or 'suture') then
            core().Notify(src, L('err_perm'), 'error', L('label'))
            return
        end
        TriggerClientEvent('nza:suture:use', src)
    end)
    if not ok then NZA.Warn('suture: RegisterUsable failed: ' .. tostring(err)) end
end)
