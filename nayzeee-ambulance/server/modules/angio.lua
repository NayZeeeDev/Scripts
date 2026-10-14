--[[
    NAYZEEE AMBULANCE - Angiography (server)

    Find an internal bleed with contrast runs and plug the vessel with a coil.
    Treats internal bleeding (spleen, liver, kidney, bowel, mesenteric, pelvic, femoral) and
    bleeding pelvic / thigh fractures. Server authoritative: the client plays the minigame,
    the server checks the suite, items, distance, timing and the run / coil log before it
    marks the injury coiled.

    Procedure (ARCHITECTURE §5.2):
      NZA.Proc.Register('angio', { perm = Config.Angio.perm, items, minTime, maxTime, easyTime, maxDist,
                                   onStart, onFinish, onAbort })
        onStart  → checks the injury, the angiography table (patient.meta.bed.type == 'angio',
                   skipped in easy mode) and returns the case data for the client
        onFinish → validates the session log, sets injury.treat.coiled, bleed 0, quality, bills,
                   returns the outcome (outcome.record = the treatment-log line the proc core saves)
    Callbacks:
      nza:angio:act (act, info) → { ok, left, bottles, err, msg }
          act = 'run' | 'puff'   uses contrast from the open bottle (info.kind, info.selective, info.blush)
          act = 'refill'         opens a new contrast bottle (takes the item now)
          act = 'coil'           releases a coil (info.dist cm, info.onPath); extra coils are taken now
    Net events (S→C): nza:angio:use - the angio kit item was used (Config.Angio.usable, perm checked here)
    Bus events emitted: angio:done (src, patient, injury, outcome)
    Exports: none. Lua API: NZA.Angio.Eligible(injury) → bool, NZA.Angio.Target(patient, injury) → key, side
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Angio = NZA.Angio or {}
local Angio = NZA.Angio
local U = NZA.Util

local sessions = {}      -- [src] = { pid, injury, startedAt, easy, contrast, bottles, coils = {}, runs = {}, access }

local function cfg()
    return Config.Angio or {}
end

local function core()
    return NZA.Core or {}
end

local function item(key)
    return Config.Items and Config.Items[key] or nil
end

-- Config.Angio.items (Config.Items keys) → { [item name] = count }
local function procItems()
    local out = {}
    for key, n in pairs(cfg().items or {}) do
        local name = item(key)
        if name and (tonumber(n) or 0) > 0 then out[name] = math.floor(tonumber(n)) end
    end
    return out
end

local function count(src, key)
    local name = item(key)
    if not name then return 0 end
    local c = core().B and core().B('Inv.Count', src, name) or nil
    return tonumber(c) or 0
end

local function take(src, key, n)
    local name = item(key)
    if not name then return false end
    if core().TakeItems then return core().TakeItems(src, { [name] = n or 1 }) end
    return false
end

-- the per-department easy flag (NZA.Staff.Get(src).easy[perm]) or the global default.
-- The proc core passes its own decision as info.easy; this is the fallback.
local function isEasy(src, extra)
    if type(extra) == 'table' and extra.easy ~= nil then return extra.easy == true end
    local perm = cfg().perm or 'angio'
    if NZA.Staff and type(NZA.Staff.Easy) == 'function' then
        local ok, res = pcall(NZA.Staff.Easy, src, perm)
        if ok then return res == true end
    end
    if NZA.Staff and type(NZA.Staff.Get) == 'function' then
        local ok, rec = pcall(NZA.Staff.Get, src)
        if ok and type(rec) == 'table' and type(rec.easy) == 'table' then
            if rec.easy[perm] ~= nil then return rec.easy[perm] == true end
            for _, v in ipairs(rec.easy) do
                if v == perm then return true end
            end
            return false
        end
    end
    return Config.EasyMode ~= nil and Config.EasyMode.default == true
end

local function hashSeed(str)
    local h = 2166136261
    for i = 1, #str do
        h = (h ~ str:byte(i)) * 16777619 % 4294967296
    end
    return math.floor(h % 2147483646) + 1
end

-- ════════════════════════════════════════════════════════════════════════
-- WHICH INJURIES
-- ════════════════════════════════════════════════════════════════════════

function Angio.Eligible(inj)
    if type(inj) ~= 'table' then return false end
    local treat = inj.treat or {}
    if treat.coiled then return false end
    local c = cfg()
    if inj.type == 'internal' then
        local organ = inj.internal and inj.internal.organ
        if not organ or not (c.organs or {})[organ] then return false end
        return (tonumber(inj.bleed) or 0) > 0 or (tonumber(inj.bleedBase) or 0) > 0
    elseif inj.type == 'fracture' then
        if not (c.fractures or {})[inj.region] then return false end
        return (tonumber(inj.bleed) or 0) >= (tonumber(c.minFractureBleed) or 1.0)
    end
    return false
end

-- injury → bleed key the client's anatomy understands, and the side ('l' | 'r' | '')
function Angio.Target(p, inj)
    local seed = hashSeed((p and p.pid or '') .. ':' .. tostring(inj.id))
    local region = inj.region or ''
    local side = ''
    if region:sub(1, 2) == 'l_' then side = 'l' elseif region:sub(1, 2) == 'r_' then side = 'r' end
    local internal = inj.internal or {}
    if side == '' and type(internal.side) == 'string' then side = internal.side:sub(1, 1):lower() end
    if side ~= 'l' and side ~= 'r' then side = (seed % 2 == 0) and 'l' or 'r' end

    if inj.type == 'fracture' then
        if region == 'pelvis' then
            local list = { 'iia', 'obturator', 'gluteal' }
            return list[(seed % #list) + 1], side
        end
        return 'profunda', side
    end
    local organ, vessel = internal.organ, internal.vessel
    if organ == 'spleen' then return 'splenic', '' end
    if organ == 'liver' then return 'hepatic', '' end
    if organ == 'kidney' then return 'renal', side end
    if organ == 'bowel' then return vessel == 'ileal' and 'ileal' or 'jejunal', '' end
    if organ == 'mesenteric' then return vessel == 'ima' and 'ima' or 'sma', '' end
    if organ == 'pelvic' then return vessel == 'superior_gluteal' and 'gluteal' or 'iia', side end
    if organ == 'femoral' then return vessel == 'profunda' and 'profunda' or 'femoral', side end
    return 'jejunal', ''
end

local function pickInjury(p, wanted)
    if type(wanted) == 'string' and p.injuries[wanted] then
        local inj = p.injuries[wanted]
        if Angio.Eligible(inj) then return inj end
        return nil
    end
    local best, bestBleed = nil, -1
    for _, inj in pairs(p.injuries or {}) do
        if Angio.Eligible(inj) then
            local b = tonumber(inj.bleed) or 0
            if b > bestBleed then best, bestBleed = inj, b end
        end
    end
    return best
end

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE
-- ════════════════════════════════════════════════════════════════════════

local function onStart(src, p, payload, extra)
    local c = cfg()
    if type(payload) ~= 'table' then payload = {} end
    local inj = pickInjury(p, payload.injury)
    if not inj then return false, NZA.L('angio.err.no_bleed') end

    -- one medic per patient on the table
    for other, s in pairs(sessions) do
        if other ~= src and s.pid == p.pid and core().Online and core().Online(other) then
            return false, NZA.L('angio.err.busy')
        end
    end

    local easy = isEasy(src, extra)
    local bed = p.meta and p.meta.bed or nil
    if not easy and c.requireSuite ~= false then
        if type(bed) ~= 'table' or bed.type ~= 'angio' then
            return false, NZA.L('angio.err.need_suite')
        end
    end

    local key, side = Angio.Target(p, inj)
    local seed = hashSeed(p.pid .. ':' .. tostring(inj.id))
    local budget = tonumber(c.contrastPerItem) or 100
    local reserved = c.consume == 'finish'

    sessions[src] = {
        pid = p.pid, injury = inj.id, startedAt = os.time(), easy = easy,
        contrast = budget, bottles = 1, coils = {}, runs = {}, reserved = reserved,
    }

    local vit = p.vitals or {}
    local holdTime = c.holdTime or {}
    return true, {
        label = NZA.L('angio.title'),
        injury = {
            id = inj.id, region = inj.region, type = inj.type, severity = inj.severity,
            organ = inj.internal and inj.internal.organ or nil, vessel = inj.internal and inj.internal.vessel or nil,
            bleed = U.round(tonumber(inj.bleed) or 0, 1),
        },
        bleed = { key = key, side = side },
        seed = seed,
        caseId = ('A-%04d'):format(seed % 10000),
        point = type(bed) == 'table' and bed.point or nil,
        patient = {
            name = p.name, sex = p.sex, age = p.age, bloodType = p.bloodType,
            avpu = vit.avpu, vitals = { hr = vit.hr, sys = vit.sys, dia = vit.dia, map = vit.map, spo2 = vit.spo2, rr = vit.rr, rhythm = vit.rhythm },
        },
        budget = budget,
        -- onStart runs before the proc core takes 'start' items, so in both modes the
        -- inventory still holds the first bottle / coil here
        bottles = math.max(0, count(src, 'contrast') - 1),
        coils = math.max(1, count(src, 'coil')),
        maxCoils = tonumber(c.maxCoils) or 6,
        coilDist = tonumber(c.coilDist) or 2.0,
        holdTime = { femoral = tonumber(holdTime.femoral) or 12, radial = tonumber(holdTime.radial) or 6 },
        runMl = tonumber(c.runMl) or 18, selectiveMl = tonumber(c.selectiveMl) or 8, puffMl = tonumber(c.puffMl) or 3,
        catheterSpeed = tonumber(c.catheterSpeed) or 4.0,
        parContrast = tonumber(c.parContrast) or 45, parFluoro = tonumber(c.parFluoro) or 150,
        easyTime = tonumber(c.easyTime) or 20,
        easy = easy,
    }
end

-- the run / coil log must tell the same story as the client's result
local function verify(s, result)
    local c = cfg()
    if s.easy then return true end
    if type(result) ~= 'table' or result.success ~= true then return false, 'not_sealed' end
    if #s.coils < 1 then return false, 'no_coil' end
    local fullRuns, lastRun = 0, nil
    for _, r in ipairs(s.runs) do
        if r.kind == 'run' then
            fullRuns = fullRuns + 1
            lastRun = r
        end
    end
    if fullRuns < 2 or not lastRun then return false, 'runs' end
    if lastRun.coils < #s.coils or lastRun.blush then return false, 'not_confirmed' end
    local limit = (tonumber(c.coilDist) or 2.0) + 0.3
    local good = false
    for _, coil in ipairs(s.coils) do
        if coil.onPath and coil.dist <= limit then good = true end
    end
    if not good then return false, 'coil_far' end
    return true
end

local function onFinish(src, p, session, result)
    local c = cfg()
    local s = sessions[src]
    sessions[src] = nil
    if type(result) ~= 'table' then result = {} end
    if not s or s.pid ~= p.pid then
        return { ok = false, failed = true, score = 0, msg = NZA.L('angio.err.unverified') }
    end
    local inj = p.injuries[s.injury]
    if not inj or not Angio.Eligible(inj) then
        return { ok = false, failed = true, score = 0, msg = NZA.L('angio.err.gone') }
    end
    local ok, why = verify(s, result)
    if not ok then
        NZA.Debug('angio: rejected finish from', src, why)
        return { ok = false, failed = true, score = 0, msg = NZA.L('angio.err.unverified') }
    end

    -- score: clamp, and cap it by what the log shows (extra coils, many runs)
    local score
    if s.easy then
        score = (Config.EasyMode and Config.EasyMode.score) or 78
    else
        score = U.clamp(math.floor(tonumber(result.score) or 0), 0, 100)
        local fullRuns = 0
        for _, r in ipairs(s.runs) do if r.kind == 'run' then fullRuns = fullRuns + 1 end end
        local cap = 100 - math.max(0, #s.coils - 1) * 6 - math.max(0, fullRuns - 3) * 3
        score = math.min(score, math.max(40, cap))
    end

    local patch = { treat = { coiled = true }, quality = { coiled = score }, bleed = 0 }
    if inj.type == 'internal' then
        patch.status = 'treated'
        patch.heal = math.min(100, (tonumber(inj.heal) or 0) + (tonumber(c.healBoost) or 0))
    else
        -- a coiled fracture bleed stays a fracture (splint / binder / cast still needed)
        patch.bleedBase = 0
    end
    NZA.Patients.UpdateInjury(p.pid, inj.id, patch)

    -- bill a player patient
    local price = tonumber(c.price) or 0
    if price > 0 and p.kind == 'player' and NZA.Billing and type(NZA.Billing.Charge) == 'function' then
        local target = p.src or p.identifier
        if target then
            local okBill, err = pcall(NZA.Billing.Charge, target, price, NZA.L('angio.bill'), { medic = src, kind = 'angio' })
            if not okBill then NZA.Warn('angio: billing failed: ' .. tostring(err)) end
        end
    end

    local access = type(result.access) == 'string' and result.access or 'femoral_r'
    if access ~= 'femoral_r' and access ~= 'femoral_l' and access ~= 'radial' then access = 'femoral_r' end
    local contrast = 0
    for _, r in ipairs(s.runs) do contrast = contrast + (r.ml or 0) end
    local summary = NZA.L('angio.record', NZA.L('angio.access.' .. access), #s.coils, math.floor(contrast + 0.5),
        U.formatTime(tonumber(result.fluoro) or 0), U.RegionLabel(inj.region), U.InjuryLabel(inj.type))

    local outcome = {
        ok = true, score = score, coiled = true, injury = inj.id, region = inj.region,
        msg = NZA.L('angio.done'), record = summary,
        summary = { access = access, coils = #s.coils, runs = #s.runs, contrast = contrast, fluoro = tonumber(result.fluoro) or 0 },
    }
    NZA.Bus.Emit('angio:done', src, p, inj, outcome)
    return outcome
end

local function onAbort(src)
    sessions[src] = nil
end

local function register()
    local c = cfg()
    NZA.Proc.Register('angio', {
        perm = c.perm or 'angio',
        items = function() return procItems() end,
        maxDist = tonumber(c.maxDist) or 6.0,
        minTime = tonumber(c.minTime) or 45,
        maxTime = tonumber(c.maxTime) or 1200,
        consume = c.consume or 'finish',
        easyTime = tonumber(c.easyTime) or 20,
        onStart = onStart,
        onFinish = onFinish,
        onAbort = onAbort,
    })
end

if NZA.Proc and type(NZA.Proc.Register) == 'function' then
    register()
else
    CreateThread(function()
        local waited = 0
        while not (NZA.Proc and type(NZA.Proc.Register) == 'function') and waited < 30000 do
            Wait(250)
            waited = waited + 250
        end
        if NZA.Proc and type(NZA.Proc.Register) == 'function' then
            register()
        else
            NZA.Warn('angio: NZA.Proc.Register is missing - the angiography procedure is disabled')
        end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- DURING THE PROCEDURE
-- ════════════════════════════════════════════════════════════════════════

local function fail(err, extra)
    local out = { ok = false, err = err, msg = NZA.L('angio.err.' .. err) }
    if extra then for k, v in pairs(extra) do out[k] = v end end
    return out
end

lib.callback.register('nza:angio:act', function(source, act, info)
    local src = tonumber(source)
    if not src then return fail('session') end
    local c = cfg()
    local s = sessions[src]
    if not s then return fail('session') end
    if core().Rate and not core().Rate('angio', src, 24, 10000) then return fail('rate') end
    if os.time() - s.startedAt > (tonumber(c.maxTime) or 1200) + 60 then
        sessions[src] = nil
        return fail('session')
    end
    local p = NZA.Patients.Get(s.pid)
    if not p then return fail('session') end
    if core().DistanceTo and core().DistanceTo(src, p) > (tonumber(c.maxDist) or 6.0) + 2.0 then return fail('far') end
    if type(info) ~= 'table' then info = {} end

    if act == 'run' or act == 'puff' then
        local kind = act == 'puff' and 'puff' or (info.kind == 'puff' and 'puff' or 'run')
        local ml
        if kind == 'puff' then ml = tonumber(c.puffMl) or 3
        elseif info.selective then ml = tonumber(c.selectiveMl) or 8
        else ml = tonumber(c.runMl) or 18 end
        if s.contrast < ml then
            return fail('contrast', { left = s.contrast, bottles = math.max(0, count(src, 'contrast') - (s.reserved and 1 or 0)) })
        end
        s.contrast = s.contrast - ml
        s.runs[#s.runs + 1] = { kind = kind, ml = ml, blush = info.blush == true, coils = #s.coils, at = os.time() }
        return { ok = true, left = s.contrast }
    elseif act == 'refill' then
        -- with consume = 'finish' the first bottle stays reserved for the end of the procedure
        local reserved = s.reserved and 1 or 0
        if count(src, 'contrast') < reserved + 1 then return fail('no_contrast', { bottles = 0 }) end
        if not take(src, 'contrast', 1) then return fail('no_contrast', { bottles = 0 }) end
        s.bottles = s.bottles + 1
        s.contrast = s.contrast + (tonumber(c.contrastPerItem) or 100)
        return { ok = true, left = s.contrast, bottles = math.max(0, count(src, 'contrast') - reserved) }
    elseif act == 'coil' then
        if #s.coils >= (tonumber(c.maxCoils) or 6) then return fail('max_coils') end
        local reserved = s.reserved and 1 or 0
        if #s.coils >= 1 then
            -- every coil after the first comes out of the inventory now
            if count(src, 'coil') < reserved + 1 then return fail('no_coil') end
            if not take(src, 'coil', 1) then return fail('no_coil') end
        end
        s.coils[#s.coils + 1] = {
            dist = U.clamp(tonumber(info.dist) or 99, 0, 99), onPath = info.onPath == true, at = os.time(),
        }
        return { ok = true, left = math.max(0, count(src, 'coil') - reserved) }
    end
    return fail('bad')
end)

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEM & CLEANUP
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1500)
    local name = item('angio_kit')
    if cfg().usable == false then return end
    if name and Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function' then
        local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src)
            src = tonumber(src)
            if not src or not (core().Rate and core().Rate('angio_use', src, 2, 3000)) then return end
            if not NZA.Staff.Can(src, cfg().perm or 'angio') then
                if core().Notify then core().Notify(src, NZA.L('angio.err.no_perm'), 'error', NZA.L('angio.title')) end
                return
            end
            TriggerClientEvent('nza:angio:use', src)
        end)
        if not ok then NZA.Warn('angio: could not register the usable kit: ' .. tostring(err)) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then sessions[src] = nil end
end)

NZA.Bus.On('patient:removed', function(pid)
    for src, s in pairs(sessions) do
        if s.pid == pid then sessions[src] = nil end
    end
end)
