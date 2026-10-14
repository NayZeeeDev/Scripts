--[[
    NAYZEEE AMBULANCE - Field resuscitation (server): helpers, instant treatments, callbacks

    Helpers (NZA.Field, used by field_procs.lua):
      F.Cfg(section)  F.L(key, ...)  F.Fail(key, ...)  F.Item(key)  F.Items({ key = n })
      F.Count(src, key)  F.HasKit(src)  F.Access(p)  F.Bleed(p, inj)  F.TargetInjuries(p)
      F.MainInjury(p)  F.BinderIndicated(p)  F.Summary(p, inj)  F.Vitals(p)  F.Bill(src, p, kind)
      F.BloodBags(src, p)  F.Counts(src)  F.CanStartResus(src)

    Instant treatments (NZA.Treat):
      'infuse'       perm Infusion.perm  payload { kind = 'saline'|'blood', rate (ml/min), serial?, warm? }
                     needs IV/IO access; saline consumes Config.Items[Infusion.saline]; blood takes a bag
                     through NZA.Blood.TakeBag (blood module) → { id, kind, ml, rate, bag }
      'infuse_rate'  payload { id, rate }      change the flow of a running bag (roller clamp / infuser)
      'infuse_stop'  payload { id }            take the bag down
      'txa'          payload { seconds }        1 g TXA slow push (item TXA.item) → GiveMed 'txa'
      'io_needle'    payload {}                 a new IO needle set during a running 'io' procedure
      'field_foil'   foil blanket (delegates to the first aid module's 'fa_foil' when it exists)
      'binder_off'   remove the pelvic binder (gives it back when Binder.removeReturns)
      'iv_off'       remove the IV / IO line (running infusions pause)
      'monitor' / 'monitor_off'   attach / remove the patient monitor (devices.monitor)
      'field_report' write the field resuscitation summary to the patient record

    Callbacks:
      nza:field:plan (target) → plan for the scene | nil, err      (perm Resus.perms, exam distance)
      nza:field:bags (target) → { saline, txa, foil, io, bags = { { serial, type, ml, compatible } }, blood }
    Net events: S→C nza:field:use (what)   ('resus' | 'iv' from the inventory)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Field = NZA.Field or {}
local F = NZA.Field
local Core = NZA.Core
local U = NZA.Util

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

function F.Cfg(section)
    local c = Config.Field or {}
    if section then return c[section] or {} end
    return c
end

local function L(key, ...) return NZA.L('field.' .. key, ...) end
F.L = L

function F.Fail(key, ...)
    return false, { err = key, msg = L('err_' .. key, ...) }
end
local fail = F.Fail

function F.Item(key)
    if not key then return nil end
    return Config.Items and Config.Items[key] or nil
end

function F.Items(map)
    local out = {}
    for key, n in pairs(map or {}) do
        local name = key and F.Item(key)
        if name and (tonumber(n) or 0) > 0 then out[name] = (out[name] or 0) + math.floor(tonumber(n)) end
    end
    return out
end

function F.Count(src, key)
    local name = F.Item(key)
    if not name or not src or src <= 0 then return 0 end
    if Core.Has('Inv.Count') then
        local n = tonumber(Core.B('Inv.Count', src, name))
        if n then return n end
    end
    return Core.B('Inv.HasItem', src, name, 1) and 1 or 0
end

function F.HasKit(src)
    local key = F.Cfg('Resus').kit
    if not key then return true end
    local name = F.Item(key)
    if not name then return true end
    return Core.B('Inv.HasItem', src, name, 1) == true
end

function F.Access(p)
    local d = p and p.devices
    if not d then return nil end
    if type(d.iv) == 'table' then return d.iv end
    if d.iv then return { site = 'unknown', kind = 'iv' } end
    if d.port then return type(d.port) == 'table' and d.port or { site = 'unknown', kind = 'port' } end
    return nil
end

function F.Bleed(p, inj)
    if NZA.Physiology and NZA.Physiology.InjuryBleed then
        local ok, b = pcall(NZA.Physiology.InjuryBleed, p, inj)
        if ok and tonumber(b) then return b end
    end
    return tonumber(inj.bleed) or 0
end

local TORSO = { pelvis = true, abdomen = true, chest = true, back = true }
local PELVIC_ORGANS = { pelvic = true, femoral = true }

-- injuries the clot step works on: torso / internal bleeding a tourniquet cannot stop,
-- plus any other heavy bleed still open
function F.TargetInjuries(p)
    local heavy = F.Cfg('Exam').heavyBleed or 25
    local list = {}
    for _, inj in pairs(p.injuries or {}) do
        local b = F.Bleed(p, inj)
        local organ = inj.internal and inj.internal.organ
        if b > 0.3 and (TORSO[inj.region] or inj.type == 'internal' or (organ and PELVIC_ORGANS[organ]) or b >= heavy) then
            list[#list + 1] = { inj = inj, bleed = b }
        end
    end
    table.sort(list, function(a, b) return a.bleed > b.bleed end)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.inj end
    return out
end

function F.MainInjury(p)
    local t = F.TargetInjuries(p)
    if t[1] then return t[1] end
    local best, bestB = nil, -1
    for _, inj in pairs(p.injuries or {}) do
        local b = F.Bleed(p, inj)
        if b > bestB then best, bestB = inj, b end
    end
    return best
end

-- pelvic fracture, pelvic / femoral vessel injury or a bleeding pelvis
function F.BinderIndicated(p)
    for _, inj in pairs(p.injuries or {}) do
        local organ = inj.internal and inj.internal.organ
        if organ and PELVIC_ORGANS[organ] then return true, 'vessel' end
        if inj.region == 'pelvis' and (inj.type == 'fracture' or inj.type == 'internal' or F.Bleed(p, inj) > 2) then
            return true, inj.type == 'fracture' and 'fracture' or 'bleed'
        end
    end
    return false, nil
end

-- why a limb region can't take a needle (IO / IV): fracture, tourniquet at or above it, deep burn, open wound
local PROXIMAL = { l_lower_leg = 'l_upper_leg', r_lower_leg = 'r_upper_leg', l_lower_arm = 'l_upper_arm', r_lower_arm = 'r_upper_arm' }
function F.SiteContra(p, region)
    if not region then return 'invalid' end
    local tq = p.devices and p.devices.tourniquet or {}
    if tq[region] or (PROXIMAL[region] and tq[PROXIMAL[region]]) then return 'tourniquet' end
    for _, inj in pairs(p.injuries or {}) do
        if inj.region == region then
            if inj.type == 'fracture' or inj.fracture then return 'fracture' end
            if inj.type == 'burn' and (inj.severity or 1) >= 3 then return 'burn' end
            if (inj.type == 'gunshot' or inj.type == 'shrapnel') and (inj.severity or 1) >= 2 then return 'wound' end
        end
    end
    return nil
end

function F.Sites(p, list)
    local out = {}
    for id, def in pairs(list or {}) do
        local region = type(def) == 'table' and def.region or id
        local why = F.SiteContra(p, region)
        out[id] = { region = region, ok = why == nil, why = why, label = U.RegionLabel(region) }
    end
    return out
end

function F.Summary(p, inj)
    if not inj then return nil end
    return {
        id = inj.id, region = inj.region, regionLabel = U.RegionLabel(inj.region),
        type = inj.type, typeLabel = U.InjuryLabel(inj.type), severity = inj.severity or 1,
        bleed = U.round(F.Bleed(p, inj), 1),
        organ = inj.internal and inj.internal.organ or nil,
    }
end

function F.Vitals(p)
    local v = p.vitals or {}
    return {
        hr = math.floor(tonumber(v.hr) or 0), ecgRate = math.floor(tonumber(v.ecgRate or v.hr) or 0),
        sys = math.floor(tonumber(v.sys) or 0), dia = math.floor(tonumber(v.dia) or 0),
        map = math.floor(tonumber(v.map) or 0), spo2 = math.floor(tonumber(v.spo2) or 0),
        rr = math.floor(tonumber(v.rr) or 0), temp = U.round(tonumber(v.temp or p.temp) or 37, 1),
        etco2 = math.floor(tonumber(v.etco2) or 0), rhythm = v.rhythm or 'sinus',
    }
end

function F.TotalBleed(p)
    local t = 0
    for _, inj in pairs(p.injuries or {}) do t = t + F.Bleed(p, inj) end
    return U.round(t, 1)
end

function F.Bill(src, p, kind)
    local amount = tonumber((F.Cfg('Billing'))[kind]) or 0
    if amount <= 0 or p.kind ~= 'player' or (p.src and p.src == src) then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local rec = NZA.Staff.Get(src)
    if not (rec and rec.medic and rec.onDuty) then return end
    local target = p.src or p.identifier
    if not target then return end
    local ok, err = pcall(NZA.Billing.Charge, target, amount, L('bill_' .. kind), { medic = src, kind = 'field_' .. kind })
    if not ok then NZA.Warn('field: billing failed: ' .. tostring(err)) end
end

function F.CanStartResus(src)
    for _, perm in ipairs(F.Cfg('Resus').perms or { 'iv', 'binder' }) do
        if NZA.Staff.Can(src, perm) then return true end
    end
    return false
end

-- blood bags the medic carries (needs the blood module for taking them)
local function bloodModule()
    return NZA.Blood ~= nil and type(NZA.Blood.TakeBag) == 'function'
end
F.BloodModule = bloodModule

local function bagCompatible(p, donor)
    if not donor then return nil end
    if donor == 'O-' then return true end
    -- the medic only knows the recipient's type once it was typed (blood module / lab)
    if not (p.meta and (p.meta.bloodTyped or p.meta.typed)) then return nil end
    if NZA.Blood and type(NZA.Blood.Compatible) == 'function' then
        local ok, res = pcall(NZA.Blood.Compatible, p.bloodType, donor)
        if ok then return res == true end
    end
    local can = NZA.Const.CanReceive and NZA.Const.CanReceive[p.bloodType]
    if can then return can[donor] == true end
    return nil
end

function F.BloodBags(src, p)
    local out = {}
    if not bloodModule() then return out end
    local name = F.Item(F.Cfg('Infusion').blood or 'blood_bag')
    if not name or not Core.Has('Inv.Search') then return out end
    local list = Core.B('Inv.Search', src, name) or {}
    local now = os.time()
    for _, it in ipairs(list) do
        local m = type(it.metadata) == 'table' and it.metadata or {}
        local btype = m.type or m.bloodType
        local expired = tonumber(m.expires) and tonumber(m.expires) < now or false
        if btype and not m.used and not expired and #out < 12 then
            out[#out + 1] = {
                serial = m.serial, type = btype, ml = tonumber(m.ml) or F.Cfg('Infusion').bloodMl or 450,
                compatible = bagCompatible(p, btype), slot = it.slot,
            }
        end
    end
    table.sort(out, function(a, b)
        local ca, cb = a.compatible == true and 0 or a.compatible == nil and 1 or 2, b.compatible == true and 0 or b.compatible == nil and 1 or 2
        if ca ~= cb then return ca < cb end
        return tostring(a.type) < tostring(b.type)
    end)
    return out
end

function F.Counts(src)
    local inf, txa, foil, io, binder = F.Cfg('Infusion'), F.Cfg('TXA'), F.Cfg('Foil'), F.Cfg('IO'), F.Cfg('Binder')
    return {
        saline = F.Count(src, inf.saline or 'saline_bag'),
        txa = F.Count(src, txa.item or 'txa'),
        foil = F.Count(src, foil.item or 'foil_blanket'),
        io = F.Count(src, io.item or 'io_kit'),
        binder = binder.item and F.Count(src, binder.item) or 99,
        lidocaine = io.lidocaine and F.Count(src, io.lidocaine) or 0,
        flush = io.saline and F.Count(src, io.saline) or 0,
        iv = F.Count(src, F.Cfg('IV').item or 'iv_kit'),
    }
end

local function infusionsOf(p, src)
    local out = {}
    for _, inf in ipairs(p.infusions or {}) do
        out[#out + 1] = {
            id = inf.id, kind = inf.kind, ml = inf.ml, left = U.round(inf.left or 0, 0), rate = U.round(inf.rate or 0, 0),
            mine = inf.by == src, bag = type(inf.bag) == 'table' and { type = inf.bag.type or inf.bag.bloodType, serial = inf.bag.serial } or nil,
            paused = inf.paused and true or nil,
        }
    end
    return out
end
F.InfusionsOf = infusionsOf

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:field:plan', function(src, target)
    if not Core.Rate('nza:field:plan', src, 3, 2000) then return nil, 'rate' end
    if not F.CanStartResus(src) then return nil, 'no_perm' end
    local p = NZA.Patients.Resolve(target)
    if not p then return nil, 'no_patient' end
    if p.kind == 'player' and p.src == src then return nil, 'no_self' end
    if p.state == 'dead' then return nil, 'state' end
    local ok, err = Core.CanView(src, p, 1.0)
    if not ok then return nil, err end
    if not F.HasKit(src) then return nil, 'no_kit' end
    local rc = F.Cfg('Resus')
    local indicated, why = F.BinderIndicated(p)
    local main = F.MainInjury(p)
    local access = F.Access(p)
    return {
        pid = p.pid, name = p.name, sex = p.sex, age = p.age, kind = p.kind, state = p.state,
        injury = F.Summary(p, main), bleed = F.TotalBleed(p), loss = U.round(NZA.Patients.Loss(p) * 100, 0),
        binder = { on = p.devices.binder and true or false, indicated = indicated, why = why,
                   perm = NZA.Staff.Can(src, F.Cfg('Binder').perm or 'binder') },
        access = access and { site = access.site, kind = access.kind } or nil,
        ioPerm = NZA.Staff.Can(src, F.Cfg('IO').perm or 'iv'),
        resusPerm = NZA.Staff.Can(src, F.Cfg('Infusion').perm or 'iv'),
        band = rc.band or { 60, 70 }, hold = rc.hold or 24,
        ioSites = F.Sites(p, F.Cfg('IO').sites), ivSites = F.Sites(p, F.Cfg('IV').sites),
        maxRate = F.MaxRate(p), blood = bloodModule(), bloodType = (p.meta and (p.meta.bloodTyped or p.meta.typed)) and p.bloodType or nil,
        txaActive = p.meds and p.meds.txa and p.meds.txa > os.time() or false, foilOn = p.devices.foil and true or false,
        vitals = F.Vitals(p), counts = F.Counts(src),
        easy = {
            binder = NZA.Staff.Easy(src, F.Cfg('Binder').perm or 'binder'),
            io = NZA.Staff.Easy(src, F.Cfg('IO').perm or 'iv'),
            resus = NZA.Staff.Easy(src, F.Cfg('Infusion').perm or 'iv'),
        },
    }
end)

lib.callback.register('nza:field:bags', function(src, target)
    if not Core.Rate('nza:field:bags', src, 4, 2000) then return nil, 'rate' end
    local p = NZA.Patients.Resolve(target)
    if not p then return nil, 'no_patient' end
    local ok, err = Core.CanView(src, p, 1.0)
    if not ok then return nil, err end
    local out = F.Counts(src)
    out.bags = F.BloodBags(src, p)
    out.blood = bloodModule()
    out.infusions = infusionsOf(p, src)
    out.txaActive = p.meds and p.meds.txa and p.meds.txa > os.time() or false
    out.foil = out.foil
    out.foilOn = p.devices.foil and true or false
    return out
end)

-- ════════════════════════════════════════════════════════════════════════
-- INFUSIONS
-- ════════════════════════════════════════════════════════════════════════

-- fastest flow the line allows: gravity (IO lines run slower) x the pressure infuser, hard capped
function F.MaxRate(p)
    local cfg = F.Cfg('Infusion')
    local a = F.Access(p)
    local gravity = (cfg.gravity or 60) * ((a and a.kind == 'io') and (cfg.ioFactor or 0.45) or 1)
    local best = gravity * (1 + (cfg.pressureGain or 1.4))
    return math.max(1, math.min(cfg.maxRate or 160, math.floor(best + 1.5)))
end

local function clampRate(rate, p)
    return U.clamp(math.floor((tonumber(rate) or 0) + 0.5), 1, F.MaxRate(p))
end

local function findInfusion(p, id)
    for _, inf in ipairs(p.infusions or {}) do
        if inf.id == id then return inf end
    end
    return nil
end

NZA.Treat.Register('infuse', {
    perm = F.Cfg('Infusion').perm or 'iv', maxDist = 3.5, cooldown = 300,
    states = { alive = true, wounded = true, arrest = true },
    items = function(src, p, payload)
        if type(payload) == 'table' and payload.kind == 'saline' then
            return F.Items({ [F.Cfg('Infusion').saline or 'saline_bag'] = 1 })
        end
        return {}
    end,
    handler = function(src, p, payload)
        local cfg = F.Cfg('Infusion')
        if not F.Access(p) then return fail('no_access') end
        local kind = payload.kind == 'blood' and 'blood' or payload.kind == 'saline' and 'saline' or nil
        if not kind then return fail('failed') end
        local running = 0
        for _, inf in ipairs(p.infusions or {}) do
            if (inf.left or 0) > 0 then running = running + 1 end
        end
        if running >= (cfg.maxBags or 3) then return fail('too_many_bags') end
        local rate = clampRate(payload.rate or cfg.gravity or 60, p)
        local inf
        if kind == 'saline' then
            inf = NZA.Patients.AddInfusion(p.pid, {
                kind = 'saline', ml = cfg.salineMl or 500, rate = rate, warm = cfg.warm == true, by = src,
            })
        else
            if not bloodModule() then return fail('no_blood_module') end
            local okTake, bag, why = pcall(NZA.Blood.TakeBag, src, { serial = payload.serial, type = payload.type, recipient = p.pid })
            if not okTake or type(bag) ~= 'table' then
                if not okTake then NZA.Warn('field: NZA.Blood.TakeBag failed: ' .. tostring(bag)) end
                return fail('no_blood', (type(why) == 'string' and why ~= '') and (' — ' .. why) or '')
            end
            inf = NZA.Patients.AddInfusion(p.pid, {
                kind = 'blood', ml = tonumber(bag.ml) or cfg.bloodMl or 450, rate = rate, bag = bag,
                warm = bag.warm or cfg.warm == true, by = src,
            })
        end
        if not inf then return fail('failed') end
        local label = kind == 'blood' and L('bag_blood', tostring(inf.bag and (inf.bag.type or inf.bag.bloodType) or '?')) or L('bag_saline', inf.ml)
        return true, {
            id = inf.id, kind = inf.kind, ml = inf.ml, left = inf.left, rate = inf.rate,
            bag = inf.bag and { type = inf.bag.type or inf.bag.bloodType, serial = inf.bag.serial } or nil,
            msg = L('ok_infuse', label), record = L('rec_infuse', label, inf.rate),
        }
    end,
})

NZA.Treat.Register('infuse_rate', {
    perm = F.Cfg('Infusion').perm or 'iv', maxDist = 4.0, cooldown = 250, record = false,
    states = { alive = true, wounded = true, arrest = true },
    handler = function(src, p, payload)
        local inf = type(payload.id) == 'string' and findInfusion(p, payload.id)
        if not inf then return fail('no_bag') end
        local rate = clampRate(payload.rate, p)
        if math.abs((inf.rate or 0) - rate) < 0.5 then return true, { id = inf.id, rate = inf.rate } end
        -- the core has no rate setter: re-hang the same bag (same id, what is left) at the new rate
        local ok, old = NZA.Patients.StopInfusion(p.pid, inf.id)
        if not ok or not old then return fail('no_bag') end
        local n = NZA.Patients.AddInfusion(p.pid, {
            id = old.id, kind = old.kind, ml = old.ml, left = old.left, rate = rate, bag = old.bag, warm = old.warm, by = old.by,
            incompatible = old.incompatible,
        })
        return true, { id = n and n.id or old.id, rate = rate, left = n and n.left or old.left }
    end,
})

NZA.Treat.Register('infuse_stop', {
    perm = F.Cfg('Infusion').perm or 'iv', maxDist = 4.0, cooldown = 300,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p, payload)
        local inf = type(payload.id) == 'string' and findInfusion(p, payload.id)
        if not inf then return fail('no_bag') end
        local _, old = NZA.Patients.StopInfusion(p.pid, inf.id)
        local given = old and math.floor((old.ml or 0) - (old.left or 0) + 0.5) or 0
        return true, { id = inf.id, given = given, msg = L('ok_bag_down', given), record = L('rec_bag_down', old and old.kind or '?', given) }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- TXA / FOIL / NEEDLES
-- ════════════════════════════════════════════════════════════════════════

NZA.Treat.Register('txa', {
    perm = F.Cfg('TXA').perm or 'iv', maxDist = 3.5,
    states = { alive = true, wounded = true, arrest = true },
    items = function() return F.Items({ [F.Cfg('TXA').item or 'txa'] = 1 }) end,
    handler = function(src, p, payload)
        if not F.Access(p) then return fail('no_access') end
        if p.meds and p.meds.txa and p.meds.txa > os.time() + 1800 then return fail('txa_active') end
        local okMed, info = NZA.Patients.GiveMed(p.pid, 'txa', { dose = 1, route = 'iv', by = src })
        if not okMed then return fail('failed') end
        local secs = tonumber(payload.seconds) or 0
        local fast = secs > 0 and secs < (F.Cfg('TXA').push or 10) * 0.6
        if fast then
            Core.Speech(src, p.name, L('say_dizzy'), 3500)
        end
        return true, { fast = fast, msg = fast and L('ok_txa_fast') or L('ok_txa'), record = L('rec_txa', math.floor(secs)) }
    end,
})

NZA.Treat.Register('field_foil', {
    perm = F.Cfg('Infusion').perm or 'iv', maxDist = 3.5,
    states = { alive = true, wounded = true, arrest = true },
    handler = function(src, p, payload)
        if p.devices.foil then return fail('foil_on') end
        if NZA.Treat.Get('fa_foil') then
            -- the first aid module owns the foil blanket (item, worn prop, state bag)
            return NZA.Treat.Run(src, 'fa_foil', p.pid, payload)
        end
        local items = F.Items({ [F.Cfg('Foil').item or 'foil_blanket'] = 1 })
        local okI = Core.CheckItems(src, items)
        if not okI then return fail('no_foil') end
        Core.TakeItems(src, items)
        NZA.Patients.SetDevice(p.pid, 'foil', true)
        return true, { msg = L('ok_foil'), record = L('rec_foil') }
    end,
})

-- needles used per IO session (token → count), checked again on finish
F.Needles = F.Needles or {}

NZA.Treat.Register('io_needle', {
    perm = F.Cfg('IO').perm or 'iv', maxDist = 3.5, cooldown = 600,
    states = { alive = true, wounded = true, arrest = true },
    items = function() return F.Items({ [F.Cfg('IO').item or 'io_kit'] = 1 }) end,
    handler = function(src, p)
        local s = NZA.Proc.Active(src)
        if not s or s.name ~= 'io' or s.pid ~= p.pid then return fail('no_session') end
        local used = (F.Needles[s.token] or 1) + 1
        if used > (F.Cfg('IO').attempts or 3) then return fail('no_attempts') end
        F.Needles[s.token] = used
        return true, { needles = used, msg = L('ok_needle'), record = false }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- REMOVE BINDER / LINE
-- ════════════════════════════════════════════════════════════════════════

local function giveBack(src, key)
    local name = F.Item(key)
    if not name or not src or src <= 0 then return end
    if Core.Has('Inv.CanCarry') and not Core.B('Inv.CanCarry', src, name, 1) then return end
    Core.B('Inv.AddItem', src, name, 1)
end

NZA.Treat.Register('binder_off', {
    perm = F.Cfg('Binder').perm or 'binder', maxDist = 3.0,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p)
        if not p.devices.binder then return fail('no_binder') end
        NZA.Patients.SetDevice(p.pid, 'binder', false)
        NZA.Patients.SetMeta(p.pid, 'binderQ', nil)
        -- the reduction a well-tightened strap gave the pelvic bleeding goes with it
        for id, inj in pairs(p.injuries or {}) do
            local f = tonumber(inj.fieldBinder)
            if f and f > 0 and f < 1 then
                NZA.Patients.UpdateInjury(p.pid, id, { bleedBase = (inj.bleedBase or 0) / f, fieldBinder = false })
            end
        end
        local cfg = F.Cfg('Binder')
        if cfg.removeReturns ~= false and cfg.item then giveBack(src, cfg.item) end
        local warn = F.BinderIndicated(p) and p.state ~= 'dead'
        return true, { msg = warn and L('ok_binder_off_warn') or L('ok_binder_off'), record = L('rec_binder_off') }
    end,
})

NZA.Treat.Register('iv_off', {
    perm = F.Cfg('IV').perm or 'iv', maxDist = 3.0,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p)
        local a = F.Access(p)
        if not a or a.kind == 'port' then return fail('no_line') end
        NZA.Patients.SetDevice(p.pid, 'iv', nil)
        local running = 0
        for _, inf in ipairs(p.infusions or {}) do if (inf.left or 0) > 0 then running = running + 1 end end
        if F.Cfg('IV').removeReturns and a.kind == 'iv' then giveBack(src, F.Cfg('IV').item or 'iv_kit') end
        return true, {
            msg = running > 0 and L('ok_line_off_paused', running) or L('ok_line_off'),
            record = L('rec_line_off', a.kind == 'io' and 'IO' or 'IV', U.RegionLabel(a.site or '')),
        }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT MONITOR
-- ════════════════════════════════════════════════════════════════════════

NZA.Treat.Register('monitor', {
    perm = F.Cfg('Monitor').perm or 'assess', maxDist = 3.0, record = false,
    states = { alive = true, wounded = true, arrest = true },
    handler = function(src, p)
        local key = F.Cfg('Monitor').requireItem
        local name = key and F.Item(key)
        if name and not Core.B('Inv.HasItem', src, name, 1) then return fail('no_kit') end
        if type(p.devices.monitor) == 'table' and p.devices.monitor.src and p.devices.monitor.src ~= src
            and Core.Online(p.devices.monitor.src) and Core.DistanceTo(p.devices.monitor.src, p) < 15.0 then
            -- someone else's monitor is already on: share the reading, do not replace it
            return true, { shared = true, msg = L('ok_monitor_shared') }
        end
        NZA.Patients.SetDevice(p.pid, 'monitor', { src = src, at = os.time() })
        return true, { msg = L('ok_monitor') }
    end,
})

NZA.Treat.Register('monitor_off', {
    perm = F.Cfg('Monitor').perm or 'assess', maxDist = 20.0, record = false,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p)
        if p.devices.monitor then NZA.Patients.SetDevice(p.pid, 'monitor', false) end
        return true, { msg = L('ok_monitor_off') }
    end,
})

-- free the monitor when its medic leaves
NZA.Bus.On('player:unloaded', function(src)
    for _, p in pairs(NZA.Patients.All()) do
        local m = p.devices and p.devices.monitor
        if type(m) == 'table' and m.src == src then NZA.Patients.SetDevice(p.pid, 'monitor', false) end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- FIELD REPORT (record of the whole scene, built from server state)
-- ════════════════════════════════════════════════════════════════════════

NZA.Treat.Register('field_report', {
    perm = nil, maxDist = 6.0, cooldown = 1000,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p, payload)
        if not F.CanStartResus(src) then return fail('no_perm') end
        local parts = {}
        if p.devices.binder then parts[#parts + 1] = L('rep_binder') end
        local a = F.Access(p)
        if a then parts[#parts + 1] = L('rep_access', a.kind == 'io' and 'IO' or 'IV', U.RegionLabel(a.site or '')) end
        local saline, blood = 0, 0
        for _, inf in ipairs(p.infusions or {}) do
            if inf.by == src then
                if inf.kind == 'blood' then blood = blood + (inf.ml or 0) else saline = saline + (inf.ml or 0) end
            end
        end
        if saline > 0 then parts[#parts + 1] = L('rep_saline', saline) end
        if blood > 0 then parts[#parts + 1] = L('rep_blood', blood) end
        if p.meds and p.meds.txa and p.meds.txa > os.time() then parts[#parts + 1] = L('rep_txa') end
        if p.devices.foil then parts[#parts + 1] = L('rep_foil') end
        local v = p.vitals or {}
        parts[#parts + 1] = L('rep_vitals', math.floor(v.sys or 0), math.floor(v.dia or 0), math.floor(v.map or 0), math.floor(v.hr or 0))
        local clot = p.meta and p.meta.fieldClot
        if type(clot) == 'table' then parts[#parts + 1] = L('rep_clot', math.floor(clot.firm or 0)) end
        return true, { record = L('rec_report') .. ': ' .. table.concat(parts, ' · '), bleed = F.TotalBleed(p), vitals = F.Vitals(p) }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS (trauma kit → field resuscitation, IV kit → cannulation)
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1600)
    if not Core.Has('Inv.RegisterUsable') then
        NZA.Warn('field: Bridge.Inv.RegisterUsable is missing - trauma kit / IV kit are not usable from the inventory')
        return
    end
    local function usable(key, what)
        local name = key and F.Item(key)
        if not name then return end
        Core.B('Inv.RegisterUsable', name, function(src)
            src = tonumber(src)
            if not src or not Core.Rate('nza:field:use', src, 1, 1500) then return end
            TriggerClientEvent('nza:field:use', src, what)
        end)
    end
    usable(F.Cfg('Resus').kit or 'trauma_kit', 'resus')
    usable(F.Cfg('IV').item or 'iv_kit', 'iv')
end)
