--[[
    NAYZEEE AMBULANCE - Patient store & API (NZA.Patients)        ARCHITECTURE §4

    The authoritative patient model. Players and NPCs share the same data and API.
    Players are loaded from `nza_patients` when their character loads and saved when
    changed (throttled), when they leave and when the resource stops, so injuries,
    wounded / arrest / dead survive relogs and restarts.

    API (§4.1)
      Get(pid) GetBySource(src) GetByNet(net) Resolve(target) All()
      CreateNPC(opts) Remove(pid)
      AddInjury(pid, def) UpdateInjury(pid, id, patch) RemoveInjury(pid, id)
      SetCondition(pid, name, value) SetDevice(pid, name, value | key, value)
      AddInfusion(pid, inf) StopInfusion(pid, id) GiveMed(pid, name, opts) AddBlood(pid, ml)
      SetState(pid, state, reason) Revive(pid, opts) Heal(pid, amount)
      Snapshot(pid, level) Sync(pid) Watch(pid, src, on) Triage(pid) Save(pid)
    Extras
      SetMeta(pid, key, value)     meta field + resync (carried, stretcher, bodybag, bay, bed, inBed...)
      Cpr(pid, src, quality)       mark CPR in progress (pauses the arrest → death timer)
      CanStand(pid)                → ok, reason  (wounded → alive rules of §6)
      RegisterMed(name, fn)        add a medication: fn(p, opts) → ok, info
      Loss(p)                      → loss fraction 0..1 (blood + 0.35 × fluid)
      Ped(p) / Coords(p)           server-side ped entity / coords
      LoadPlayer(src) UnloadPlayer(src)
      Touch(p, deep)               mark changed (state bag, self push, save); deep = recompute bleeding now
      Flush()                      push pending state bags / self snapshots now

    Pushes to clients
      state bag 'nza' (Player(src).state / Entity(ped).state, replicated, ≤ every 250 ms)
      'nza:self:update' (snapshot)      own player, throttled 500 ms, only when changed
      'nza:patient:update' (pid, snap)  watchers, every Config.Physiology.watchRate ms ; (pid, nil) = watch ended
      'nza:revived' (opts)              when a player is revived to 'alive'

    Bus events: patient:created (p) · patient:removed (pid, reason) · injury:added (p, inj) ·
      injury:updated (p, inj) · injury:removed (p, id) · state:changed (p, old, new, reason) ·
      patient:arrest (p) · patient:death (p) · patient:revived (p, opts) ·
      condition:changed (p, name, value) · device:changed (p, name, value) ·
      infusion:started (p, inf) · infusion:stopped (p, inf) · med:given (p, name, opts)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Patients = NZA.Patients or {}
NZA.Physiology = NZA.Physiology or {}
NZA.Core = NZA.Core or {}
local P = NZA.Patients
local Phys = NZA.Physiology
local Core = NZA.Core

local store = {}    -- pid → Patient
local bySrc = {}    -- src → pid
local byNet = {}    -- netId → pid
local rt = {}       -- pid → runtime (never persisted): dirty flags, timers, last pushed payloads
local loading = {}  -- src → true while loading from the DB
local dbReady = false

local TRANSIENT_META = { carried = true, stretcher = true, bay = true, bed = true, inBed = true, bodybag = true,
    vehicle = true, seat = true, escort = true, recovery = true, ventilated = true }

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section, key, default)
    local s = Config[section]
    if s == nil or s[key] == nil then return default end
    return s[key]
end

local function persistence()
    return cfg('Persistence', 'enabled', true) ~= false and MySQL ~= nil
end

local function maxClock() return cfg('Wounded', 'maxClock', 300) end

local function blankDevices()
    return {
        tourniquet = {}, binder = false, collar = false, splints = {}, iv = nil, port = nil,
        intubated = false, chestDrain = { left = false, right = false },
        oxygen = false, foil = false, monitor = false,
    }
end

local function blankGiven()
    return { saline = 0, blood = 0, txa = 0, adrenaline = 0, naloxone = 0, morphine = 0,
             painkillers = 0, antibiotics = 0, lidocaine = 0 }
end

local function bloodMaxFor(sex)
    local t = cfg('Physiology', 'bloodMax', { m = 5000, f = 4500 })
    return (type(t) == 'table' and (t[sex] or t.m)) or 5000
end

local function baseVitals(p)
    local b = p.base
    return {
        hr = b.hr, sys = b.sys, dia = b.dia, map = math.floor(b.dia + (b.sys - b.dia) / 3 + 0.5),
        spo2 = 98, rr = b.rr, temp = 36.9, etco2 = 38, rhythm = 'sinus', avpu = 'A',
        pupils = 'normal', breathing = 'normal', airway = 'clear',
    }
end

local function newPatient(kind)
    local now = os.time()
    local p = {
        pid = nil, kind = kind, src = nil, net = nil, identifier = nil,
        name = 'Unknown', sex = 'm', age = 30, bloodType = 'O+',
        blood = 5000, bloodMax = 5000, fluid = 0,
        state = 'alive', stabilized = true, clock = maxClock(),
        injuries = {}, conditions = {}, devices = blankDevices(), infusions = {},
        given = blankGiven(), meds = {}, pain = 0, temp = 37.0,
        base = { hr = math.random(64, 82), sys = math.random(114, 128), dia = math.random(72, 82), rr = math.random(12, 16) },
        vitals = nil, bleedTotal = 0,
        arrestAt = nil, arrestLeft = nil, lastCpr = nil, downAt = nil, deadAt = nil, cause = nil,
        watchers = {}, meta = {}, seq = 0, created = now, updated = now,
    }
    p.vitals = baseVitals(p)
    return p
end

-- Make sure every sub-table exists (old saves, hand-edited DB rows, module mistakes).
local function normalize(p)
    p.injuries = type(p.injuries) == 'table' and p.injuries or {}
    p.conditions = type(p.conditions) == 'table' and p.conditions or {}
    local d = type(p.devices) == 'table' and p.devices or {}
    local blank = blankDevices()
    for k, v in pairs(blank) do if d[k] == nil and v ~= nil then d[k] = v end end
    if type(d.tourniquet) ~= 'table' then d.tourniquet = {} end
    if type(d.splints) ~= 'table' then d.splints = {} end
    if type(d.chestDrain) ~= 'table' then d.chestDrain = { left = false, right = false } end
    p.devices = d
    p.infusions = type(p.infusions) == 'table' and p.infusions or {}
    local g = type(p.given) == 'table' and p.given or {}
    for k, v in pairs(blankGiven()) do if g[k] == nil then g[k] = v end end
    p.given = g
    p.meds = type(p.meds) == 'table' and p.meds or {}
    p.meta = type(p.meta) == 'table' and p.meta or {}
    p.watchers = {}
    if type(p.base) ~= 'table' or not p.base.hr then
        p.base = { hr = math.random(64, 82), sys = math.random(114, 128), dia = math.random(72, 82), rr = math.random(12, 16) }
    end
    p.bloodMax = tonumber(p.bloodMax) or bloodMaxFor(p.sex)
    p.blood = math.max(0, math.min(p.bloodMax * 1.1, tonumber(p.blood) or p.bloodMax))
    p.fluid = math.max(0, tonumber(p.fluid) or 0)
    p.temp = tonumber(p.temp) or 37.0
    p.pain = tonumber(p.pain) or 0
    p.seq = tonumber(p.seq) or 0
    if not NZA.Const.States[p.state or ''] then p.state = 'alive' end
    p.clock = tonumber(p.clock) or maxClock()
    if type(p.vitals) ~= 'table' or not p.vitals.hr then p.vitals = baseVitals(p) end
    -- json turns sparse/empty tables into arrays; injuries must be keyed by id
    local fixed = {}
    for k, inj in pairs(p.injuries) do
        if type(inj) == 'table' and inj.region and inj.type then
            inj.id = inj.id or (type(k) == 'string' and k) or ('i' .. tostring(k))
            inj.treat = type(inj.treat) == 'table' and inj.treat or {}
            inj.quality = type(inj.quality) == 'table' and inj.quality or {}
            inj.heal = tonumber(inj.heal) or 0
            inj.bleedBase = tonumber(inj.bleedBase) or 0
            inj.bleed = tonumber(inj.bleed) or inj.bleedBase
            inj.retained = tonumber(inj.retained) or 0
            fixed[inj.id] = inj
        end
    end
    p.injuries = fixed
    local infs = {}
    for _, inf in pairs(p.infusions) do
        if type(inf) == 'table' and inf.id then infs[#infs + 1] = inf end
    end
    p.infusions = infs
    return p
end

local function runtime(p)
    local r = rt[p.pid]
    if not r then
        r = { sync = true, self = true, save = false, lowMap = 0, lowSpo2 = 0 }
        rt[p.pid] = r
    end
    return r
end

local function get(target)
    if type(target) == 'table' and target.pid and store[target.pid] == target then return target end
    if type(target) == 'string' then return store[target] end
    return P.Resolve(target)
end

-- Public internals for the other server/core files
P.RT = runtime

function P.Loss(p)
    local eff = (p.blood or 0) + 0.35 * (p.fluid or 0)
    local loss = 1 - eff / (p.bloodMax or 5000)
    if loss < 0 then loss = 0 elseif loss > 1 then loss = 1 end
    return loss
end

function P.Ped(p) return Core.PatientPed(get(p)) end
function P.Coords(p) return Core.PatientCoords(get(p)) end

function P.Touch(p, deep)
    p = get(p)
    if not p then return end
    p.updated = os.time()
    local r = runtime(p)
    r.sync, r.self = true, true
    if p.kind == 'player' then r.save = true end
    r.active = true
    if deep and Phys.Refresh then Phys.Refresh(p) end
end

-- ════════════════════════════════════════════════════════════════════════
-- LOOKUP
-- ════════════════════════════════════════════════════════════════════════

function P.Get(pid) return store[pid] end

function P.GetBySource(src)
    src = tonumber(src)
    local pid = src and bySrc[src]
    return pid and store[pid] or nil
end

function P.GetByNet(net)
    net = tonumber(net)
    local pid = net and byNet[net]
    return pid and store[pid] or nil
end

function P.Resolve(target)
    local t = type(target)
    if t == 'string' then
        if store[target] then return store[target] end
        local n = tonumber(target)
        if n then return P.GetBySource(n) end
        return nil
    elseif t == 'number' then
        return P.GetBySource(target)
    elseif t == 'table' then
        if target.pid and store[target.pid] then return store[target.pid] end
        if target.kind == 'npc' or (target.net and not target.sid) then return P.GetByNet(target.net) end
        if target.kind == 'player' or target.sid or target.src then return P.GetBySource(target.sid or target.src) end
    end
    return nil
end

function P.All() return store end

-- ════════════════════════════════════════════════════════════════════════
-- INJURIES
-- ════════════════════════════════════════════════════════════════════════

function P.AddInjury(pid, def, silent)
    local p = get(pid)
    if not p then return nil, 'no_patient' end
    if p.state == 'dead' and not (def and def.force) then return nil, 'dead' end
    local inj, err = NZA.Injury.Build(p, def)
    if not inj then return nil, err end
    p.injuries[inj.id] = inj
    if def.complications ~= false then
        NZA.Injury.Complications(p, inj)
    end
    P.Touch(p, true)
    if not silent and not runtime(p).creating then NZA.Bus.Emit('injury:added', p, inj) end
    return inj
end

local SUB = { treat = true, quality = true, fracture = true, burn = true, internal = true, spot = true }

function P.UpdateInjury(pid, id, patch)
    local p = get(pid)
    if not p then return nil, 'no_patient' end
    local inj = p.injuries[id]
    if not inj then return nil, 'no_injury' end
    if type(patch) ~= 'table' then return inj end
    for k, v in pairs(patch) do
        if SUB[k] and type(v) == 'table' then
            inj[k] = type(inj[k]) == 'table' and inj[k] or {}
            for k2, v2 in pairs(v) do inj[k][k2] = v2 end
        elseif (k == 'treat' or k == 'quality') then
            -- these must stay tables (physiology indexes them every tick); ignore bad values
        elseif k ~= 'id' then
            inj[k] = v
        end
    end
    inj.severity = math.max(1, math.min(4, math.floor(tonumber(inj.severity) or 1)))
    inj.heal = math.max(0, math.min(100, tonumber(inj.heal) or 0))
    inj.retained = math.max(0, math.floor(tonumber(inj.retained) or 0))
    inj.contamination = math.max(0, math.min(100, tonumber(inj.contamination) or 0))
    P.Touch(p, true)
    NZA.Bus.Emit('injury:updated', p, inj)
    return inj
end

function P.RemoveInjury(pid, id)
    local p = get(pid)
    if not p or not p.injuries[id] then return false end
    p.injuries[id] = nil
    P.Touch(p, true)
    NZA.Bus.Emit('injury:removed', p, id)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- CONDITIONS & DEVICES
-- ════════════════════════════════════════════════════════════════════════

function P.SetCondition(pid, name, value)
    local p = get(pid)
    if not p or type(name) ~= 'string' then return nil end
    if value == true then value = {} end
    if value == false then value = nil end
    if name == 'arrest' then
        if value == nil then
            -- ROSC goes through Revive(pid, { rosc = true }); never silently drop an arrest
            if p.state == 'arrest' then return p.conditions.arrest end
            p.conditions.arrest = nil
        elseif p.state ~= 'arrest' and p.state ~= 'dead' then
            P.SetState(p, 'arrest', value.cause or 'condition')
            if value.rhythm then p.conditions.arrest.rhythm = value.rhythm end
        else
            p.conditions.arrest = value
            value.since = value.since or p.arrestAt or os.time()
        end
    else
        p.conditions[name] = value
    end
    P.Touch(p, true)
    NZA.Bus.Emit('condition:changed', p, name, p.conditions[name])
    return p.conditions[name]
end

local MAP_DEVICES = { tourniquet = true, splints = true, chestDrain = true }

local function updateAccess(p)
    local has = p.devices.iv ~= nil or p.devices.port ~= nil
    for _, inf in ipairs(p.infusions) do
        if has then
            if inf.paused == 'access' then inf.paused = nil end
        elseif not inf.paused then
            inf.paused = 'access'
        end
    end
end

-- SetDevice(pid, 'binder', true)
-- SetDevice(pid, 'splints', { r_lower_leg = 'leg' })      map devices merge; a false value removes that key
-- SetDevice(pid, 'tourniquet', 'l_upper_leg', true)        single key form for map devices
-- SetDevice(pid, 'splints', nil)                           clears the whole map
function P.SetDevice(pid, name, value, value2)
    local p = get(pid)
    if not p or type(name) ~= 'string' then return nil end
    local d = p.devices
    if MAP_DEVICES[name] then
        local map = type(d[name]) == 'table' and d[name] or {}
        if type(value) == 'string' then
            value = { [value] = value2 == nil and true or value2 }
        end
        if value == nil or value == false then
            map = (name == 'chestDrain') and { left = false, right = false } or {}
        elseif type(value) == 'table' then
            for k, v in pairs(value) do
                if v == false or v == nil then
                    if name == 'chestDrain' then map[k] = false else map[k] = nil end
                else
                    if name == 'tourniquet' and v == true then v = os.time() end
                    map[k] = v
                end
            end
        end
        d[name] = map
    else
        if value == false and (name == 'iv' or name == 'port') then value = nil end
        d[name] = value
        if name == 'iv' or name == 'port' then updateAccess(p) end
    end
    P.Touch(p, true)
    NZA.Bus.Emit('device:changed', p, name, d[name])
    return d[name]
end

-- ════════════════════════════════════════════════════════════════════════
-- INFUSIONS
-- ════════════════════════════════════════════════════════════════════════

local DEFAULT_RATE = { saline = 50, blood = 40, txa = 10, plasma = 40 }

function P.AddInfusion(pid, inf)
    local p = get(pid)
    if not p or type(inf) ~= 'table' then return nil end
    local kind = inf.kind or 'saline'
    local ml = math.max(1, tonumber(inf.ml) or 500)
    local item = {
        id = inf.id or NZA.Util.uid('f'),
        kind = kind,
        ml = ml,
        left = math.max(0, tonumber(inf.left) or ml),
        rate = math.max(0.1, tonumber(inf.rate) or DEFAULT_RATE[kind] or 50),
        bag = inf.bag,
        warm = inf.warm or (type(inf.bag) == 'table' and inf.bag.warm) or false,
        started = os.time(),
        by = inf.by,
    }
    if type(inf.bag) == 'table' and kind == 'blood' then
        local donor = inf.bag.type or inf.bag.bloodType
        if donor and NZA.Const.CanReceive[p.bloodType] and not NZA.Const.CanReceive[p.bloodType][donor] then
            item.incompatible = true
        end
    end
    if inf.incompatible ~= nil then item.incompatible = inf.incompatible end
    -- flows straight away: callers check IV / IO access themselves (a module may allow bags
    -- without a line). It pauses ('access') when the last IV/IO is taken out and resumes when
    -- one goes back in (SetDevice → updateAccess).
    p.infusions[#p.infusions + 1] = item
    P.Touch(p, true)
    NZA.Bus.Emit('infusion:started', p, item)
    return item
end

function P.StopInfusion(pid, id)
    local p = get(pid)
    if not p then return false end
    for i, inf in ipairs(p.infusions) do
        if inf.id == id then
            table.remove(p.infusions, i)
            P.Touch(p, true)
            NZA.Bus.Emit('infusion:stopped', p, inf)
            return true, inf
        end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- MEDICATIONS
-- Each returns ok, info (info.msg is a locale key result for toasts)
-- ════════════════════════════════════════════════════════════════════════

P.Meds = P.Meds or {}
local Meds = P.Meds

local function active(p, name)
    local e = p.meds[name]
    return e ~= nil and e > os.time()
end
P.MedActive = function(p, name) p = get(p); return p ~= nil and active(p, name) end

local function addOpioid(p, amount)
    local od = p.conditions.overdose
    if od and od.drug == 'opioid' then
        od.amount = math.min(100, (od.amount or 0) + amount)
    elseif not od then
        p.conditions.overdose = { drug = 'opioid', amount = math.min(100, amount), since = os.time() }
    end
end

Meds.adrenaline = function(p, opts)
    local now = os.time()
    p.meds.adrenaline = now + 240
    p.meta.lastAdrenaline = now
    return true, { msg = NZA.L('core.med_adrenaline') }
end

Meds.naloxone = function(p, opts)
    local now = os.time()
    p.meds.naloxone = now + 1800
    p.meds.morphine = nil
    local od = p.conditions.overdose
    if od and od.drug == 'opioid' then
        od.amount = (od.amount or 0) - 60 * (opts.dose or 1)
        if od.amount <= 0 then p.conditions.overdose = nil end
    end
    return true, { msg = NZA.L('core.med_naloxone') }
end

Meds.morphine = function(p, opts)
    local now = os.time()
    if active(p, 'naloxone') then
        return true, { msg = NZA.L('core.med_blocked') }
    end
    if active(p, 'morphine') then
        -- stacking doses → opioid toxicity (slow breathing, pinpoint pupils)
        addOpioid(p, 22 * (opts.dose or 1))
    end
    p.meds.morphine = now + 1200
    return true, { msg = NZA.L('core.med_morphine') }
end

Meds.painkillers = function(p, opts)
    p.meds.painkillers = os.time() + 1800
    return true, { msg = NZA.L('core.med_painkillers') }
end

Meds.txa = function(p, opts)
    p.meds.txa = os.time() + 3600
    return true, { msg = NZA.L('core.med_txa') }
end

Meds.antibiotics = function(p, opts)
    p.meds.antibiotics = os.time() + 3600
    -- the first dose knocks wound contamination back
    for _, inj in pairs(p.injuries) do
        inj.contamination = math.floor((inj.contamination or 0) * 0.6)
    end
    return true, { msg = NZA.L('core.med_antibiotics') }
end

Meds.lidocaine = function(p, opts)
    p.meds.lidocaine = os.time() + 900
    local region, injId = opts.region, opts.injury
    for id, inj in pairs(p.injuries) do
        if (injId and id == injId) or (not injId and (not region or inj.region == region)) then
            inj.treat.anesthetized = true
        end
    end
    return true, { msg = NZA.L('core.med_lidocaine') }
end

function P.RegisterMed(name, fn)
    if type(name) == 'string' and type(fn) == 'function' then Meds[name] = fn end
end

function P.GiveMed(pid, name, opts)
    local p = get(pid)
    if not p then return false, { err = 'no_patient' } end
    local fn = Meds[name]
    if not fn then return false, { err = 'unknown_med' } end
    if p.state == 'dead' then return false, { err = 'dead', msg = NZA.L('core.err_dead') } end
    opts = type(opts) == 'table' and opts or {}
    local ok, info = fn(p, opts)
    if ok then
        p.given[name] = (p.given[name] or 0) + (opts.dose or 1)
        P.Touch(p, true)
        NZA.Bus.Emit('med:given', p, name, opts)
    end
    return ok, info or {}
end

function P.AddBlood(pid, ml)
    local p = get(pid)
    if not p then return nil end
    ml = tonumber(ml) or 0
    p.blood = math.max(0, math.min(p.bloodMax * 1.1, p.blood + ml))
    if ml > 0 then p.given.blood = (p.given.blood or 0) + ml end
    P.Touch(p, true)
    return p.blood
end

-- ════════════════════════════════════════════════════════════════════════
-- STATE MACHINE
-- ════════════════════════════════════════════════════════════════════════

local function initialClock(p)
    local minC, maxC = cfg('Wounded', 'minClock', 60), maxClock()
    local ttd = Phys.TimeToDeath and Phys.TimeToDeath(p) or maxC
    if ttd < minC then return minC end
    if ttd > maxC then return maxC end
    return math.floor(ttd)
end

function P.SetState(pid, state, reason)
    local p = get(pid)
    if not p or not NZA.Const.States[state] then return false end
    local old = p.state
    if old == state then return true end
    local now = os.time()
    local r = runtime(p)
    -- what stopped the heart (hypovolemia, tension, drowning, ...): kept when the arrest ends in death
    local prevArrestCause = (old == 'arrest' and type(p.conditions.arrest) == 'table' and p.conditions.arrest.cause) or nil
    local why = reason
    if type(reason) == 'table' then
        p.cause = reason
        why = reason.reason
    elseif reason and (state ~= 'alive') then
        p.cause = p.cause or {}
        p.cause.reason = reason
    end
    why = why or 'unknown'

    p.state = state
    p.stateAt = now
    r.lowMap, r.lowSpo2 = 0, 0

    if state == 'wounded' then
        if old == 'alive' or not p.downAt then
            p.downAt = now
            if type(reason) ~= 'table' then p.cause = { reason = why, at = now } else p.cause.at = now end
            if Phys.Refresh then Phys.Refresh(p) end
            p.clock = initialClock(p)
        else
            -- back from arrest/death: at least the minimum clock again
            p.clock = math.max(p.clock or 0, cfg('Wounded', 'minClock', 60))
            r.roscGrace = now + 20
        end
        p.conditions.arrest, p.arrestAt, p.arrestLeft, p.deadAt = nil, nil, nil, nil
    elseif state == 'arrest' then
        p.arrestAt = now
        p.arrestLeft = cfg('Death', 'arrestToDeath', 300)
        p.downAt = p.downAt or now
        r.noCpr = 0
        p.conditions.arrest = {
            rhythm = Phys.PickArrestRhythm and Phys.PickArrestRhythm(p, why) or 'pea',
            since = now, cause = why,
        }
    elseif state == 'dead' then
        p.deadAt = now
        p.downAt = p.downAt or now
        p.arrestLeft = 0
        if type(p.cause) == 'table' then
            if prevArrestCause and prevArrestCause ~= p.cause.reason then
                p.cause.arrestCause = prevArrestCause      -- e.g. reason 'arrest', arrestCause 'hypovolemia'
            elseif type(reason) ~= 'table' then
                p.cause.arrestCause = nil                  -- no stale cause from an earlier arrest
            end
        end
        p.conditions.arrest = { rhythm = 'asystole', since = p.arrestAt or now, cause = prevArrestCause or why }
    elseif state == 'alive' then
        p.downAt, p.deadAt, p.arrestAt, p.arrestLeft = nil, nil, nil, nil
        p.conditions.arrest = nil
        p.clock = maxClock()
        p.cause = nil
    end

    if Phys.Recompute then Phys.Recompute(p) end
    P.Touch(p, true)
    NZA.Debug(('patient %s: %s → %s (%s)'):format(p.pid, old, state, tostring(why)))
    NZA.Bus.Emit('state:changed', p, old, state, why)
    if state == 'arrest' then NZA.Bus.Emit('patient:arrest', p) end
    if state == 'dead' then NZA.Bus.Emit('patient:death', p) end
    return true
end

-- wounded → alive rules (§6): modules call this before 'pick up'
function P.CanStand(pid)
    local p = get(pid)
    if not p then return false, 'no_patient' end
    if p.state == 'alive' then return true end
    if p.state ~= 'wounded' then return false, 'state' end
    if not p.stabilized then return false, 'bleeding' end
    if (p.vitals and p.vitals.avpu or 'A') ~= 'A' then return false, 'avpu' end
    if P.Loss(p) >= cfg('Wounded', 'lossDown', 0.30) then return false, 'blood' end
    local c = p.conditions
    if (c.pneumothorax and c.pneumothorax.tension) or (c.tamponade and (c.tamponade.ml or 0) > 150) then
        return false, 'condition'
    end
    return true
end

local function clearAll(p)
    p.injuries = {}
    p.conditions = {}
    p.devices = blankDevices()
    p.infusions = {}
    p.meds = {}
    p.given = blankGiven()
    p.blood = p.bloodMax
    p.fluid = 0
    p.pain = 0
    p.temp = 37.0
    p.bleedTotal = 0
    p.stabilized = true
    p.vitals = baseVitals(p)
end

function P.Revive(pid, opts)
    local p = get(pid)
    if not p then return false, 'no_patient' end
    opts = type(opts) == 'table' and opts or {}

    if opts.rosc then
        if p.state ~= 'arrest' then return false, 'not_arrest' end
        P.SetState(p, 'wounded', 'rosc')
        local v = p.vitals
        v.hr, v.sys, v.dia, v.rhythm = 118, 82, 50, 'stach'
        v.map = math.floor(v.dia + (v.sys - v.dia) / 3 + 0.5)
        v.spo2, v.rr, v.etco2 = 88, 10, 45   -- the typical post-ROSC etCO2 spike
        runtime(p).vf = nil                  -- vitals smooth on from these numbers
        P.Touch(p, true)
        NZA.Bus.Emit('patient:revived', p, opts)
        return true
    end

    if opts.full then
        clearAll(p)
    else
        -- back on your feet: life threats fixed, injuries kept but patched
        local keep = 1 - cfg('Wounded', 'lossDown', 0.30) * 0.5
        p.blood = math.max(p.blood, p.bloodMax * keep)
        p.fluid = 0
        local c = p.conditions
        c.arrest, c.hypoxia, c.airway, c.overdose, c.tamponade = nil, nil, nil, nil, nil
        if c.pneumothorax then c.pneumothorax.tension, c.pneumothorax.pressure = false, 0 end
        if c.haemothorax then c.haemothorax.ml, c.haemothorax.rate = 0, 0 end
        if p.temp < 35.5 then p.temp = 36.0 end
        for _, inj in pairs(p.injuries) do
            if (inj.bleedBase or 0) > 0 then
                if inj.type == 'internal' then inj.treat.coiled = true
                else inj.treat.bandaged, inj.treat.packed = true, true end
            end
        end
    end

    P.SetState(p, 'alive', opts.reason or 'revive')
    if Phys.Recompute then Phys.Recompute(p, true) end
    P.Touch(p, true)
    NZA.Bus.Emit('patient:revived', p, opts)
    if p.kind == 'player' and p.src then
        TriggerClientEvent('nza:revived', p.src, { full = opts.full == true, reason = opts.reason })
        P.Sync(p)
    end
    return true
end

function P.Heal(pid, amount)
    local p = get(pid)
    if not p then return false end
    amount = tonumber(amount) or 100
    for id, inj in pairs(p.injuries) do
        inj.heal = math.min(100, (inj.heal or 0) + amount)
        if inj.heal >= 100 then
            p.injuries[id] = nil
            NZA.Bus.Emit('injury:removed', p, id)
        end
    end
    p.blood = math.min(p.bloodMax, p.blood + (p.bloodMax - p.blood) * math.min(1, amount / 100))
    if amount >= 100 then
        local arrest = p.conditions.arrest
        p.conditions = { arrest = p.state == 'arrest' and arrest or nil }
        p.temp = 37.0
        p.fluid = 0
        p.devices = blankDevices()
        p.infusions = {}
    end
    P.Touch(p, true)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- CPR / META helpers
-- ════════════════════════════════════════════════════════════════════════

function P.Cpr(pid, src, quality)
    local p = get(pid)
    if not p then return false end
    p.lastCpr = os.time()
    p.meta.cprQuality = tonumber(quality) or p.meta.cprQuality or 70
    p.meta.cprBy = src
    P.Touch(p)
    return true
end

function P.SetMeta(pid, key, value)
    local p = get(pid)
    if not p or type(key) ~= 'string' then return nil end
    p.meta[key] = value
    P.Touch(p)
    return value
end

-- ════════════════════════════════════════════════════════════════════════
-- TRIAGE
-- ════════════════════════════════════════════════════════════════════════

local function triageLevel(p)
    if p.state == 'arrest' then return 1 end
    if p.state == 'dead' then return 3 end
    local v, c = p.vitals or {}, p.conditions
    local loss, bleed = P.Loss(p), p.bleedTotal or 0
    local avpu = v.avpu or 'A'
    if (p.state == 'wounded' and not p.stabilized) or bleed >= 60 or loss >= 0.30
        or (v.spo2 or 99) < 88 or (v.map or 90) < 60 or avpu == 'P' or avpu == 'U'
        or (c.pneumothorax and c.pneumothorax.tension) or (c.tamponade and (c.tamponade.ml or 0) > 100)
        or (c.haemothorax and (c.haemothorax.ml or 0) > 1000) or (c.airway and c.airway.kind == 'obstructed')
        or (c.overdose and (c.overdose.amount or 0) > 60) or (p.temp or 37) < 32 then
        return 1
    end
    if p.state == 'wounded' or bleed >= 10 or loss >= 0.15 or (p.pain or 0) >= 60 or (v.spo2 or 99) < 94
        or c.haemothorax or c.pneumothorax or c.tamponade or c.overdose or c.hypothermia or c.spinal
        or c.hypoxia or c.airway or (c.concussion and (c.concussion.grade or 1) >= 2)
        or (c.infection and (c.infection.level or 0) >= 50) then
        return 2
    end
    for _, inj in pairs(p.injuries) do
        if inj.type == 'fracture' and not (inj.treat.splinted or inj.treat.cast) then return 2 end
        if inj.type == 'internal' and not inj.treat.coiled then return 2 end
        if inj.type == 'burn' and inj.burn and inj.burn.degree >= 2 and (inj.burn.area or 0) >= 20 then return 2 end
        if inj.severity >= 3 and inj.status == 'open' then return 2 end
    end
    return 3
end

function P.Triage(pid)
    local p = get(pid)
    if not p then return 3, NZA.L('core.triage_3'), NZA.Const.Triage[3].colour end
    local lvl = triageLevel(p)
    if p.state == 'dead' then return 3, NZA.L('core.triage_dead'), '#6b6f76' end
    return lvl, NZA.L('core.triage_' .. lvl), NZA.Const.Triage[lvl].colour
end

-- ════════════════════════════════════════════════════════════════════════
-- SNAPSHOTS (§4.3)
-- ════════════════════════════════════════════════════════════════════════

-- physiology keeps its accumulators at full precision; payloads carry them rounded
local function round(n, d)
    if type(n) ~= 'number' then return n end
    local f = 10 ^ (d or 1)
    return math.floor(n * f + 0.5) / f
end

-- numeric condition fields that physiology accumulates every tick (rounded to 0.1 in snapshots)
local COND_ROUND = { ml = true, output = true, size = true, pressure = true, water = true, smoke = true,
    level = true, amount = true }

local function bleedLevel(total)
    if total < cfg('Wounded', 'stableBleed', 1.0) then return 0 end
    if total < 10 then return 1 end
    if total < 60 then return 2 end
    return 3
end

local function shortName(name)
    if type(name) ~= 'string' then return '?' end
    local first, rest = name:match('^(%S+)%s+(.+)$')
    if first and rest then return first:sub(1, 1) .. '. ' .. rest end
    return name
end

local function injuryArray(p)
    local arr = {}
    for _, inj in pairs(p.injuries) do
        local c = NZA.Util.deepcopy(inj)
        c.heal = round(c.heal, 2)
        c.contamination = round(c.contamination, 1)
        arr[#arr + 1] = c
    end
    table.sort(arr, function(a, b)
        if a.severity ~= b.severity then return a.severity > b.severity end
        if (a.bleed or 0) ~= (b.bleed or 0) then return (a.bleed or 0) > (b.bleed or 0) end
        return tostring(a.id) < tostring(b.id)
    end)
    return arr
end

local function summary(p)
    local tags, seen, tq, splints = {}, {}, {}, {}
    for _, kind in ipairs(NZA.Const.InjuryOrder) do seen[kind] = false end
    for _, inj in pairs(p.injuries) do seen[inj.type] = true end
    for _, kind in ipairs(NZA.Const.InjuryOrder) do if seen[kind] then tags[#tags + 1] = kind end end
    for region in pairs(p.devices.tourniquet or {}) do tq[region] = true end
    for region in pairs(p.devices.splints or {}) do splints[region] = true end
    local clock = 0
    if p.state == 'wounded' then clock = math.floor(p.clock or 0)
    elseif p.state == 'arrest' then clock = math.floor(p.arrestLeft or 0) end
    local m = p.meta
    return {
        pid = p.pid,
        st = p.state,
        avpu = (p.vitals and p.vitals.avpu) or 'A',
        bleed = bleedLevel(p.bleedTotal or 0),
        stab = p.stabilized == true,
        clock = clock,
        inj = NZA.Util.tableCount(p.injuries),
        tri = (triageLevel(p)),
        tags = tags,
        tq = tq,
        splints = splints,
        binder = p.devices.binder and true or false,
        collar = p.devices.collar and true or false,
        iv = (p.devices.iv ~= nil or p.devices.port ~= nil),
        intub = p.devices.intubated and true or false,
        bag = m.bodybag and true or false,
        carried = m.carried and true or false,
        stretcher = m.stretcher,
        name = shortName(p.name),
        npc = p.kind == 'npc' or nil,
        plan = NZA.Care and NZA.Care.Compact(p) or nil,   -- what this patient still needs (core/care.lua)
    }
end

local SELF_CONDS = { concussion = true, hypothermia = true, infection = true, hypoxia = true, overdose = true, spinal = true }

local function selfSnapshot(p)
    local loss = P.Loss(p)
    local lossDown = cfg('Wounded', 'lossDown', 0.30)
    local v = p.vitals or {}
    local injuries = {}
    local limp, armShake = false, 0
    for _, inj in pairs(p.injuries) do
        local bleeding = (inj.bleed or 0) >= 1
        injuries[#injuries + 1] = {
            id = inj.id, region = inj.region, type = inj.type, severity = inj.severity,
            status = inj.status, bleeding = bleeding,
            label = NZA.Util.InjuryLabel(inj.type), regionLabel = NZA.Util.RegionLabel(inj.region),
        }
        local R = NZA.Const.Region[inj.region]
        if R and R.limb == 'leg' then
            local fixed = inj.treat.splinted or inj.treat.cast
            if (inj.type == 'fracture' and not fixed) or (inj.severity >= 3 and inj.type ~= 'contusion' and inj.type ~= 'abrasion') then
                limp = true
            end
        elseif R and R.limb == 'arm' then
            armShake = armShake + inj.severity * ((inj.type == 'fracture' and not (inj.treat.splinted or inj.treat.cast)) and 0.18 or 0.07)
        end
    end
    table.sort(injuries, function(a, b) return a.severity > b.severity end)
    local conds = {}
    for name in pairs(p.conditions) do
        if SELF_CONDS[name] then conds[#conds + 1] = name end
    end
    local meds = {}
    local now = os.time()
    for name, exp in pairs(p.meds) do if exp > now then meds[#meds + 1] = name end end
    local c = p.conditions
    local blur = 0
    if c.concussion then blur = blur + (c.concussion.grade or 1) * 0.2 end
    if loss > 0.15 then blur = blur + (loss - 0.15) * 2.5 end
    if (v.spo2 or 99) < 92 then blur = blur + (92 - v.spo2) * 0.03 end
    if c.overdose then blur = blur + (c.overdose.amount or 0) / 160 end
    local health = 100
    if p.state == 'alive' then
        health = math.floor(math.max(5, math.min(100, 100 * (1 - loss / lossDown))) + 0.5)
    else
        health = 0
    end
    local tq, splints = {}, {}
    for region in pairs(p.devices.tourniquet or {}) do tq[#tq + 1] = region end
    for region in pairs(p.devices.splints or {}) do splints[#splints + 1] = region end
    return {
        pid = p.pid,
        state = p.state,
        clock = math.floor(p.clock or 0),
        clockRate = p.state == 'wounded' and (p.stabilized and 0 or (p.clockRate or 1)) or nil,
        arrestLeft = p.arrestLeft and math.floor(p.arrestLeft) or nil,
        downAt = p.downAt, deadAt = p.deadAt,
        stabilized = p.stabilized == true,
        bleeding = bleedLevel(p.bleedTotal or 0),
        pain = math.floor((p.pain or 0) + 0.5),
        avpu = v.avpu or 'A',
        loss = math.floor(loss * 1000 + 0.5) / 1000,
        health = health,
        syncHealth = cfg('Physiology', 'syncHealth', true) ~= false,
        injuries = injuries,
        conditions = conds,
        meds = meds,
        devices = {
            tourniquet = tq, splints = splints, collar = p.devices.collar and true or false,
            binder = p.devices.binder and true or false, iv = p.devices.iv ~= nil or p.devices.port ~= nil,
            oxygen = p.devices.oxygen and true or false, foil = p.devices.foil and true or false,
            intubated = p.devices.intubated and true or false,
        },
        fx = {   -- 2 decimals: the push only goes out when something visibly changed
            limp = limp,
            shake = round(math.min(1, armShake), 2),
            blur = round(math.min(1, blur), 2),
            tunnel = round(math.min(1, math.max(0, (loss - 0.10) * 3)), 2),
            cold = (p.temp or 37) < 35.5,
            breathless = (v.spo2 or 99) < 90 or (v.breathing == 'labored'),
            drunk = (c.overdose and c.overdose.drug == 'alcohol') and round(math.min(1, (c.overdose.amount or 0) / 100), 2) or 0,
        },
        bloodType = p.bloodType,
        name = p.name,
    }
end

function P.Snapshot(pid, level)
    local p = get(pid)
    if not p then return nil end
    level = level or 'summary'
    if level == 'summary' then return summary(p) end
    if level == 'self' then return selfSnapshot(p) end
    -- medic: everything except watchers, plus derived values
    local out = {}
    for k, v in pairs(p) do
        if k ~= 'watchers' and k ~= 'injuries' then
            out[k] = type(v) == 'table' and NZA.Util.deepcopy(v) or v
        end
    end
    out.injuries = injuryArray(p)
    out.blood, out.fluid, out.temp, out.clock = round(p.blood, 1), round(p.fluid, 1), round(p.temp, 3), round(p.clock, 1)
    for _, inf in ipairs(out.infusions or {}) do inf.left = round(inf.left, 1) end
    for _, cond in pairs(out.conditions or {}) do
        if type(cond) == 'table' then
            for k, v in pairs(cond) do
                if COND_ROUND[k] and type(v) == 'number' then cond[k] = round(v, 1) end
            end
        end
    end
    local lvl, label, colour = P.Triage(p)
    out.triage = { level = lvl, code = NZA.Const.Triage[lvl].code, label = label, colour = colour }
    out.bleedTotal = math.floor((p.bleedTotal or 0) * 10 + 0.5) / 10
    out.bloodPct = math.floor(p.blood / p.bloodMax * 1000 + 0.5) / 10
    out.lossPct = math.floor(P.Loss(p) * 1000 + 0.5) / 10
    out.src = p.src
    out.clockText = NZA.Util.formatTime(p.state == 'arrest' and (p.arrestLeft or 0) or (p.clock or 0))
    out.care = NZA.Care and NZA.Care.Plan(p) or {}
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- SYNC (state bags + self pushes)
-- ════════════════════════════════════════════════════════════════════════

local function encode(t)
    local ok, s = pcall(json.encode, t)
    return ok and s or nil
end

local function setBag(p, value)
    if p.kind == 'player' then
        if not p.src then return false end
        local ok = pcall(function() Player(p.src).state:set('nza', value, true) end)
        return ok
    end
    local ent = Core.PatientPed(p)
    if ent == 0 then return false end
    local ok = pcall(function() Entity(ent).state:set('nza', value, true) end)
    return ok
end

local function pushBag(p, r, force)
    local s = summary(p)
    local enc = encode(s)
    if not force and enc and enc == r.bagStr then return end
    if setBag(p, s) then
        r.bagStr = enc
    else
        r.sync = true -- entity not there yet (NPC streaming in) — retry next flush
    end
end

local function pushSelf(p, r, force)
    if p.kind ~= 'player' or not p.src then return end
    local s = selfSnapshot(p)
    local enc = encode(s)
    if not force and enc and enc == r.selfStr then return end
    r.selfStr = enc
    TriggerClientEvent('nza:self:update', p.src, s)
end

function P.Flush(force)
    local nowMs = GetGameTimer()
    for pid, r in pairs(rt) do
        local p = store[pid]
        if p then
            if r.sync or force then
                r.sync = false
                pushBag(p, r, force)
            end
            if (r.self or force) and p.kind == 'player' and p.src and (force or nowMs - (r.selfAt or 0) >= 500) then
                r.self = false
                r.selfAt = nowMs
                pushSelf(p, r, force)
            end
        else
            rt[pid] = nil
        end
    end
end

function P.Sync(pid)
    local p = get(pid)
    if not p then return false end
    local r = runtime(p)
    r.sync = false
    pushBag(p, r, true)
    if p.kind == 'player' and p.src then
        r.self = false
        r.selfAt = GetGameTimer()
        pushSelf(p, r, true)
    end
    return true
end

function P.Watch(pid, src, on)
    local p = get(pid)
    src = tonumber(src)
    if not p or not src then return false end
    if on then
        p.watchers[src] = true
        TriggerClientEvent('nza:patient:update', src, p.pid, P.Snapshot(p, 'medic'))
    else
        p.watchers[src] = nil
    end
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- PERSISTENCE
-- ════════════════════════════════════════════════════════════════════════

local PERSIST = { 'name', 'sex', 'age', 'bloodType', 'blood', 'bloodMax', 'fluid', 'state', 'stabilized', 'clock',
    'injuries', 'conditions', 'devices', 'infusions', 'given', 'meds', 'pain', 'temp', 'base', 'vitals', 'bleedTotal',
    'arrestAt', 'arrestLeft', 'lastCpr', 'downAt', 'deadAt', 'cause', 'seq', 'created', 'stateAt' }

local function serialize(p)
    local data = { v = 1 }
    for _, k in ipairs(PERSIST) do data[k] = p[k] end
    local meta = {}
    for k, v in pairs(p.meta) do
        if not TRANSIENT_META[k] and type(v) ~= 'function' then meta[k] = v end
    end
    data.meta = meta
    return encode(data)
end

function P.Save(pid)
    local p = get(pid)
    if not p or p.kind ~= 'player' or not p.identifier then return false end
    if not persistence() or not dbReady then return false end
    local data = serialize(p)
    if not data then
        NZA.Warn('could not encode patient ' .. tostring(p.pid))
        return false
    end
    local r = runtime(p)
    r.save = false
    r.lastSave = os.time()
    MySQL.update('INSERT INTO nza_patients (identifier, data, state) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = ?, state = ?',
        { p.identifier, data, p.state, data, p.state })
    return true
end

local function saveAll()
    for pid, p in pairs(store) do
        if p.kind == 'player' then P.Save(pid) end
    end
end

local function waitDb(ms)
    local waited = 0
    while not dbReady and waited < (ms or 15000) do
        Wait(100)
        waited = waited + 100
    end
    return dbReady
end

local function namesFrom(key)
    local list = {}
    for n in tostring(NZA.L(key)):gmatch('[^,]+') do
        local s = n:gsub('^%s+', ''):gsub('%s+$', '')
        if s ~= '' then list[#list + 1] = s end
    end
    return list
end

local function randomName(sex)
    local firsts = namesFrom(sex == 'f' and 'core.names_f' or 'core.names_m')
    local lasts = namesFrom('core.names_last')
    local f = #firsts > 0 and firsts[math.random(#firsts)] or 'John'
    local l = #lasts > 0 and lasts[math.random(#lasts)] or 'Doe'
    return f .. ' ' .. l
end

local function ageFromDob(dob)
    if type(dob) ~= 'string' then return nil end
    local year = tonumber(dob:match('(%d%d%d%d)'))
    if not year then return nil end
    local now = tonumber(os.date('%Y'))
    local age = now - year
    if age < 14 or age > 110 then return nil end
    return age
end

local function applyIdentity(p, src, fresh)
    local info = Core.B('GetCharInfo', src)
    if type(info) == 'table' then
        local first, last = info.firstname or info.firstName, info.lastname or info.lastName
        if first or last then p.name = ((first or '') .. ' ' .. (last or '')):gsub('^%s+', ''):gsub('%s+$', '') end
        local sex = info.sex or info.gender
        if sex == 'f' or sex == 'F' or sex == 1 or sex == '1' or sex == 'female' then p.sex = 'f'
        elseif sex ~= nil then p.sex = 'm' end
        p.age = ageFromDob(info.dob or info.birthdate or info.dateofbirth) or p.age
        if info.bloodType or info.bloodtype then
            local bt = info.bloodType or info.bloodtype
            if NZA.Const.CanReceive[bt] then p.bloodType = bt end
        end
    end
    if not p.name or p.name == '' or p.name == 'Unknown' then p.name = Core.Name(src) end
    if fresh then
        p.bloodMax = bloodMaxFor(p.sex)
        p.blood = p.bloodMax
    end
end

-- Offline healing (Config.Persistence.offlineHeal): treated injuries keep healing while away.
local function offlineHeal(p, seconds)
    if not cfg('Persistence', 'offlineHeal', false) or seconds <= 0 then return end
    if p.state ~= 'alive' then return end
    local rate = cfg('Physiology', 'healRate', 0.4)
    local amount = rate * seconds / 60
    for id, inj in pairs(p.injuries) do
        if Phys.HealMultiplier and Phys.HealMultiplier(p, inj) > 0 then
            inj.heal = math.min(100, (inj.heal or 0) + amount)
            if inj.heal >= 100 then p.injuries[id] = nil end
        end
    end
    p.blood = math.min(p.bloodMax, p.blood + seconds / 60 * 6)
end

function P.LoadPlayer(src)
    src = tonumber(src)
    if not src or not Core.Online(src) then return nil end
    local identifier = Core.Identifier(src)
    if not identifier then return nil end
    local pid = 'p:' .. identifier

    if bySrc[src] == pid and store[pid] then return store[pid] end
    if bySrc[src] and bySrc[src] ~= pid then P.UnloadPlayer(src, 'switch') end

    if loading[src] then
        local waited = 0
        while loading[src] and waited < 15000 do Wait(100); waited = waited + 100 end
        return store[pid]
    end
    loading[src] = true

    local ok, err = pcall(function()
        local p = store[pid]
        local fresh = false
        if p and p.src and p.src ~= src then
            -- the same character is bound to an old source (ghost after a crash): rebind
            bySrc[p.src] = nil
        end
        if not p then
            local row
            if persistence() and waitDb() then
                row = MySQL.single.await('SELECT data, UNIX_TIMESTAMP(updated_at) AS ts FROM nza_patients WHERE identifier = ?', { identifier })
            end
            if row and row.data then
                local okDec, data = pcall(json.decode, row.data)
                if okDec and type(data) == 'table' then
                    p = newPatient('player')
                    for k, v in pairs(data) do if k ~= 'v' then p[k] = v end end
                    normalize(p)
                    for k in pairs(TRANSIENT_META) do p.meta[k] = nil end
                    offlineHeal(p, os.time() - (tonumber(row.ts) or os.time()))
                end
            end
            if not p then
                p = newPatient('player')
                p.bloodType = NZA.Util.RandomBloodType()
                fresh = true
            end
        end
        p.pid, p.kind, p.identifier, p.src = pid, 'player', identifier, src
        applyIdentity(p, src, fresh)
        store[pid] = p
        bySrc[src] = pid
        local r = runtime(p)
        r.sync, r.self = true, true
        r.bagStr, r.selfStr = nil, nil
        if Phys.Recompute then Phys.Recompute(p, true) end
        P.Touch(p, true)
        if fresh then r.save = true; P.Save(pid) end
        P.Sync(pid)
        NZA.Debug(('loaded patient %s (%s) state=%s injuries=%d'):format(pid, p.name, p.state, NZA.Util.tableCount(p.injuries)))
        NZA.Bus.Emit('patient:created', p)
    end)
    loading[src] = nil
    if not ok then
        NZA.Warn(('failed to load patient for %s: %s'):format(tostring(src), tostring(err)))
        return nil
    end
    return store[pid]
end

function P.UnloadPlayer(src, reason)
    src = tonumber(src)
    if not src then return end
    -- this player stops watching anything
    for _, p in pairs(store) do p.watchers[src] = nil end
    local pid = bySrc[src]
    if not pid then return end
    bySrc[src] = nil
    local p = store[pid]
    if not p then return end
    P.Save(pid)
    -- medics watching this player: the watch is over (client treats (pid, nil) as "ended")
    for w in pairs(p.watchers) do
        if w ~= src and Core.Online(w) then TriggerClientEvent('nza:patient:update', w, pid, nil) end
    end
    p.watchers = {}
    if reason ~= 'dropped' then pcall(function() Player(src).state:set('nza', nil, true) end) end
    p.src = nil
    store[pid] = nil
    rt[pid] = nil
    NZA.Bus.Emit('patient:removed', pid, reason or 'unload')
end

-- ════════════════════════════════════════════════════════════════════════
-- NPC PATIENTS
-- ════════════════════════════════════════════════════════════════════════

function P.CreateNPC(opts)
    opts = type(opts) == 'table' and opts or {}
    local net = tonumber(opts.net)
    if not net then return nil, 'no_net' end
    local pid = 'n:' .. net
    if store[pid] and not opts.replace then return store[pid] end
    if store[pid] then P.Remove(pid, 'replace') end

    local p = newPatient('npc')
    p.pid, p.net = pid, net
    p.sex = (opts.sex == 'f' or opts.sex == 'm') and opts.sex or (math.random() < 0.5 and 'f' or 'm')
    p.age = tonumber(opts.age) or math.random(18, 82)
    p.name = opts.name or randomName(p.sex)
    p.bloodType = (opts.bloodType and NZA.Const.CanReceive[opts.bloodType]) and opts.bloodType or NZA.Util.RandomBloodType()
    p.bloodMax = tonumber(opts.bloodMax) or bloodMaxFor(p.sex)
    p.blood = tonumber(opts.blood) or p.bloodMax
    if opts.loss then p.blood = p.bloodMax * (1 - math.max(0, math.min(0.6, tonumber(opts.loss) or 0))) end
    p.temp = tonumber(opts.temp) or 37.0
    p.meta = type(opts.meta) == 'table' and NZA.Util.deepcopy(opts.meta) or {}
    normalize(p)
    store[pid] = p
    byNet[net] = pid
    local r = runtime(p)
    r.creating = true

    for name, val in pairs(type(opts.conditions) == 'table' and opts.conditions or {}) do
        if name ~= 'arrest' then p.conditions[name] = NZA.Util.deepcopy(val == true and {} or val) end
    end
    for _, def in ipairs(type(opts.injuries) == 'table' and opts.injuries or {}) do
        local d = NZA.Util.deepcopy(def)
        if d.complications == nil then d.complications = opts.complications ~= false end
        P.AddInjury(p, d, true)
    end
    if type(opts.devices) == 'table' then
        for k, v in pairs(opts.devices) do P.SetDevice(p, k, v) end
    end
    for name, dur in pairs(type(opts.meds) == 'table' and opts.meds or {}) do
        p.meds[name] = os.time() + (tonumber(dur) or 600)
    end

    if Phys.Recompute then Phys.Recompute(p, true) end
    local arrest = type(opts.conditions) == 'table' and opts.conditions.arrest
    local st = opts.state or (arrest and 'arrest') or 'alive'
    if st ~= 'alive' and NZA.Const.States[st] then
        P.SetState(p, st, opts.reason or (type(arrest) == 'table' and arrest.cause) or 'scenario')
        if st == 'arrest' and type(arrest) == 'table' and arrest.rhythm then
            p.conditions.arrest.rhythm = arrest.rhythm
        end
        if opts.clock and st == 'wounded' then p.clock = tonumber(opts.clock) or p.clock end
    end
    r.creating = nil
    P.Touch(p, true)
    NZA.Bus.Emit('patient:created', p)
    return p
end

function P.Remove(pid, reason)
    local p = get(pid)
    if not p then return false end
    if p.kind == 'player' then
        if p.src then P.UnloadPlayer(p.src, reason or 'remove') end
        return true
    end
    pcall(function()
        local ent = Core.PatientPed(p)
        if ent ~= 0 then Entity(ent).state:set('nza', nil, true) end
    end)
    for src in pairs(p.watchers) do TriggerClientEvent('nza:patient:update', src, p.pid, nil) end
    store[p.pid] = nil
    if p.net then byNet[p.net] = nil end
    rt[p.pid] = nil
    NZA.Bus.Emit('patient:removed', p.pid, reason or 'remove')
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE & LOOPS
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('player:loaded', function(src)
    CreateThread(function() P.LoadPlayer(src) end)
end)

NZA.Bus.On('player:unloaded', function(src, reason)
    P.UnloadPlayer(src, reason)
end)

-- the ped behind an NPC patient was deleted
AddEventHandler('entityRemoved', function(entity)
    local ok, net = pcall(NetworkGetNetworkIdFromEntity, entity)
    if not ok or not net then return end
    local pid = byNet[net]
    local p = pid and store[pid]
    if p and not p.meta.keep then P.Remove(pid, 'despawned') end
end)

local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nza_patients` (
            `identifier` VARCHAR(64) NOT NULL,
            `data` LONGTEXT NOT NULL,
            `state` VARCHAR(16) NOT NULL DEFAULT 'alive',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

CreateThread(function()
    Wait(0)
    if persistence() and MySQL.ready then
        MySQL.ready(function()
            local ok, err = pcall(createTables)
            if not ok then NZA.Warn('nza_patients table: ' .. tostring(err)) end
            dbReady = true
        end)
    else
        dbReady = true
    end

    -- resource (re)started with players online: load them all
    waitDb(15000)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and not bySrc[src] then CreateThread(function() P.LoadPlayer(src) end) end
    end
end)

-- state bag / self push flush
CreateThread(function()
    while true do
        Wait(250)
        local ok, err = pcall(P.Flush)
        if not ok then NZA.Warn('flush failed: ' .. tostring(err)) end
    end
end)

-- watcher updates (live monitors / open exams)
CreateThread(function()
    local lastValidate = 0
    while true do
        Wait(math.max(250, cfg('Physiology', 'watchRate', 1000)))
        local nowMs = GetGameTimer()
        local validate = nowMs - lastValidate >= 5000
        if validate then lastValidate = nowMs end
        for pid, p in pairs(store) do
            if next(p.watchers) then
                local snap
                for src in pairs(p.watchers) do
                    local keep = Core.Online(src)
                    if keep and validate and Core.CanView then keep = Core.CanView(src, p, 2.0) end
                    if keep then
                        snap = snap or P.Snapshot(p, 'medic')
                        TriggerClientEvent('nza:patient:update', src, pid, snap)
                    else
                        p.watchers[src] = nil
                        if Core.Online(src) then TriggerClientEvent('nza:patient:update', src, pid, nil) end
                    end
                end
            end
        end
    end
end)

-- throttled saves + NPC housekeeping
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        local interval = cfg('Persistence', 'saveInterval', 30)
        for pid, p in pairs(store) do
            local r = rt[pid]
            if p.kind == 'player' then
                if r and r.save and now - (r.lastSave or 0) >= interval then P.Save(pid) end
            elseif p.net then
                local ent = NetworkGetEntityFromNetworkId(p.net)
                if not ent or ent == 0 or not DoesEntityExist(ent) then
                    r = runtime(p)
                    r.missing = (r.missing or 0) + 5
                    if r.missing >= 60 and not p.meta.keep then P.Remove(pid, 'despawned') end
                elseif r then
                    if r.missing then r.sync = true end
                    r.missing = nil
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    saveAll()
    for _, p in pairs(store) do
        if p.kind == 'player' and p.src then
            pcall(function() Player(p.src).state:set('nza', nil, true) end)
        elseif p.kind == 'npc' then
            pcall(function()
                local ent = Core.PatientPed(p)
                if ent ~= 0 then Entity(ent).state:set('nza', nil, true) end
            end)
        end
    end
end)

AddEventHandler('txAdmin:events:serverShuttingDown', saveAll)
AddEventHandler('txAdmin:events:scheduledRestart', function(data)
    if data and tonumber(data.secondsRemaining) and tonumber(data.secondsRemaining) <= 60 then saveAll() end
end)
