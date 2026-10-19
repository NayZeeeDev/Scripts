--[[
    NAYZEEE AMBULANCE - First aid (server): helpers, worn-device state bag, timers,
    usable items and the instant first-aid treatments.

    Files of this module
      server/modules/firstaid.lua        (this) helpers, state bag, timers, usable items, instant treatments
      server/modules/firstaid_procs.lua  NZA.Proc 'stopbleed', 'tourniquet', 'collar'
      server/modules/firstaid_meds.lua   NZA.Treat 'fa_med' (medic dose panel) + naloxone wake-up

    Server API (NZA.Firstaid)
      FA.Cfg(section) → Config.Firstaid[section] or {}
      FA.ItemsOf({ [itemKey] = n }) → { [inventoryName] = n }
      FA.Limb(region) → { kind = 'arm'|'leg', upper, lower, seg = 'upper'|'lower' } | nil
      FA.TqCovers(p, region) → bool          (a tourniquet on this segment or the one above)
      FA.WorstBleed(p, filterFn) → injury | nil
      FA.Plan(p, inj) → { steps = { 'pressure', 'pack'?, 'wrap'|'dressing'? }, items = {...}, deep }
      FA.Eligible[key](p) → target | nil, reasonKey     (bandage medkit ice_pack burn_dressing painkillers foil_blanket)
      FA.SyncBag(p)                           push the 'nzaFa' state bag now
      FA.ReconcileTq(p)                       clear treat.tourniquet on injuries no longer under a tourniquet
      FA.Bill(src, p, kind)                   optional fee (Config.Firstaid.Billing)
      FA.Notify(p, key, kind, ...)            toast the patient (players) + the medics watching

    State bag 'nzaFa' (player: Player(src).state, NPC: Entity(ped).state), set only here:
      { o2 = true|nil, foil = true|nil, rec = true|nil, tq = { [region] = fraction along the bone } }
    Core's 'nza' bag already carries tq{ region = true } and collar (used for the props too).

    Treatments registered (NZA.Treat, callback 'nza:treat')
      fa_bandage   fa_medkit   fa_painkillers   fa_ice   fa_burn         (self + others, item each)
      fa_foil  fa_foil_off  fa_oxygen  fa_oxygen_off  fa_tq_off  fa_collar_off
      fa_recovery  (recovery position: sets meta.recovery, which core physiology reads to stop an
                    unconscious patient's snoring airway; cleared again when they are moved,
                    intubated or leave the wounded state)

    Callbacks:  nza:firstaid:kit (target) → { name, self, items = { { key, item, usable, text } } }
    Net events: nza:firstaid:use (S→C, itemKey) - the player used a first aid item from the inventory
    Bus listened: device:changed, patient:created, patient:revived, player:loaded, state:changed,
                  transport:carry
    Bus emitted:  firstaid:tq_warn (p, region), firstaid:tq_damage (p, region), firstaid:soaked (p, inj)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Firstaid = NZA.Firstaid or {}
local FA = NZA.Firstaid
local U = NZA.Util
local Core = NZA.Core

-- ════════════════════════════════════════════════════════════════════════
-- CONFIG & SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

function FA.Cfg(section)
    local c = Config.Firstaid or {}
    if section then return c[section] or {} end
    return c
end

function FA.ItemsOf(map)
    local out = {}
    if type(map) ~= 'table' then return out end
    for key, n in pairs(map) do
        local name = Config.Items and Config.Items[key]
        if name then out[name] = (out[name] or 0) + (tonumber(n) or 1) end
    end
    return out
end

function FA.Item(key)
    return Config.Items and Config.Items[key] or nil
end

local function L(key, ...) return NZA.L('firstaid.' .. key, ...) end
FA.L = L

local function regionLabel(region) return U.RegionLabel(region) end
local function injLabel(inj) return U.InjuryLabel(inj.type) end
FA.RegionLabel = regionLabel

local LIMBS = {
    l_upper_arm = { kind = 'arm', upper = 'l_upper_arm', lower = 'l_lower_arm', seg = 'upper' },
    l_lower_arm = { kind = 'arm', upper = 'l_upper_arm', lower = 'l_lower_arm', seg = 'lower' },
    r_upper_arm = { kind = 'arm', upper = 'r_upper_arm', lower = 'r_lower_arm', seg = 'upper' },
    r_lower_arm = { kind = 'arm', upper = 'r_upper_arm', lower = 'r_lower_arm', seg = 'lower' },
    l_upper_leg = { kind = 'leg', upper = 'l_upper_leg', lower = 'l_lower_leg', seg = 'upper' },
    l_lower_leg = { kind = 'leg', upper = 'l_upper_leg', lower = 'l_lower_leg', seg = 'lower' },
    r_upper_leg = { kind = 'leg', upper = 'r_upper_leg', lower = 'r_lower_leg', seg = 'upper' },
    r_lower_leg = { kind = 'leg', upper = 'r_upper_leg', lower = 'r_lower_leg', seg = 'lower' },
}
FA.Limbs = LIMBS

function FA.Limb(region) return LIMBS[region] end

function FA.TqCovers(p, region)
    local tq = p and p.devices and p.devices.tourniquet
    if type(tq) ~= 'table' then return false end
    if tq[region] then return true end
    local limb = LIMBS[region]
    return limb ~= nil and limb.seg == 'lower' and tq[limb.upper] ~= nil
end

local EXTERNAL = { gunshot = true, shrapnel = true, stab = true, laceration = true, abrasion = true, fracture = true, burn = true }

function FA.WorstBleed(p, filter)
    local best, bestB = nil, -1
    for _, inj in pairs(p.injuries or {}) do
        if EXTERNAL[inj.type] and (not filter or filter(inj)) then
            local b = tonumber(inj.bleed) or 0
            if b > bestB or (b == bestB and best and (inj.severity or 0) > (best.severity or 0)) then
                best, bestB = inj, b
            end
        end
    end
    return best
end

local function hasValue(list, v)
    if type(list) ~= 'table' then return false end
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end
FA.Has = hasValue

-- ════════════════════════════════════════════════════════════════════════
-- STOP BLEEDING PLAN (shared by the procedure, the exam route and the items)
-- ════════════════════════════════════════════════════════════════════════

function FA.NeedsPack(inj)
    local sb = FA.Cfg('StopBleed')
    local minSev = (sb.pack or {})[inj.type]
    if minSev and (inj.severity or 1) >= minSev then return true end
    if (tonumber(inj.depth) or 0) >= (sb.packDepth or 15) and (inj.type == 'gunshot' or inj.type == 'stab'
        or inj.type == 'shrapnel' or inj.type == 'laceration') then
        return true
    end
    return false
end

-- → plan { steps, items (inventory names), deep, method } or nil, reasonKey
function FA.Plan(p, inj)
    if not inj then return nil, 'no_wound' end
    local sb = FA.Cfg('StopBleed')
    if not hasValue(sb.types, inj.type) then return nil, 'wrong_type' end
    local t = inj.treat or {}
    local deep = FA.NeedsPack(inj)
    local R = NZA.Const.Region[inj.region]
    local method = (R and R.limb) and 'wrap' or 'dressing'
    local steps = { 'pressure' }
    local itemKeys = {}
    if deep and not t.packed then
        steps[#steps + 1] = 'pack'
        for k, n in pairs((sb.items or {}).pack or {}) do itemKeys[k] = (itemKeys[k] or 0) + n end
    end
    if not t.bandaged and not t.dressed and not t.sutured then
        steps[#steps + 1] = method
        for k, n in pairs((sb.items or {})[method] or {}) do itemKeys[k] = (itemKeys[k] or 0) + n end
    end
    if #steps == 1 then return nil, 'already_dressed' end
    return { steps = steps, items = FA.ItemsOf(itemKeys), itemKeys = itemKeys, deep = deep, method = method }
end

-- the bleed the minigame shows: the current bleed, or what it would be without a tourniquet
function FA.ShownBleed(p, inj)
    local b = tonumber(inj.bleed) or 0
    if b < 0.5 and FA.TqCovers(p, inj.region) then b = tonumber(inj.bleedBase) or 0 end
    return b
end

-- ════════════════════════════════════════════════════════════════════════
-- SELF-USE ITEM ELIGIBILITY (the kit preview and the handlers agree on this)
-- ════════════════════════════════════════════════════════════════════════

FA.Eligible = {}
local E = FA.Eligible

local function itemCfg(key) return (FA.Cfg('Items'))[key] or {} end

-- prefer = injury id the user picked (exam route); used when it qualifies
local function preferred(p, prefer, ok)
    local inj = type(prefer) == 'string' and p.injuries and p.injuries[prefer] or nil
    if inj and ok(inj) then return inj end
    return nil
end

function E.bandage(p, prefer)
    local sb = FA.Cfg('StopBleed')
    local function ok(i)
        local t = i.treat or {}
        if t.bandaged or t.dressed or t.sutured then return false end
        if i.type == 'fracture' then return i.fracture ~= nil and i.fracture.kind ~= 'closed' end
        return hasValue(sb.types, i.type)
    end
    local minB, maxB = sb.minBleed or 0.5, itemCfg('bandage').maxBleed or 25
    local function bleed(i) return tonumber(i.bleed) or 0 end
    -- the wound the user picked, when it is one a bandage can handle
    local pick = preferred(p, prefer, function(i) return ok(i) and bleed(i) >= minB end)
    if pick then
        if bleed(pick) > maxB then return nil, 'too_heavy', pick end
        return pick
    end
    -- else the worst MINOR bleed; heavy bleeds need the Stop bleeding procedure
    local minor = FA.WorstBleed(p, function(i) return ok(i) and bleed(i) >= minB and bleed(i) <= maxB end)
    if minor then return minor end
    local heavy = FA.WorstBleed(p, function(i) return ok(i) and bleed(i) > maxB end)
    if heavy then return nil, 'too_heavy', heavy end
    return nil, 'nothing_bleeding'
end

local function medkitList(p)
    local maxSev = itemCfg('medkit').maxSeverity or 2
    local list = {}
    for _, inj in pairs(p.injuries or {}) do
        local t = inj.treat or {}
        local sev = inj.severity or 1
        if inj.type == 'abrasion' and sev <= maxSev and not (t.bandaged or t.dressed) then
            list[#list + 1] = inj
        elseif inj.type == 'contusion' and sev <= maxSev and not t.cooled then
            list[#list + 1] = inj
        elseif inj.type == 'laceration' and sev <= 1 and not (t.bandaged or t.dressed or t.sutured) then
            list[#list + 1] = inj
        end
    end
    return list
end
FA.MedkitList = medkitList

function E.medkit(p)
    local list = medkitList(p)
    if #list == 0 then return nil, 'nothing_minor' end
    return list
end

function E.ice_pack(p, prefer)
    local pick = preferred(p, prefer, function(i)
        return (i.type == 'contusion' and not (i.treat or {}).cooled) or (i.type == 'fracture' and not i.iced)
    end)
    if pick then return pick end
    local best
    for _, inj in pairs(p.injuries or {}) do
        local t = inj.treat or {}
        if inj.type == 'contusion' and not t.cooled then
            if not best or best.type ~= 'contusion' or (inj.severity or 0) > (best.severity or 0) then best = inj end
        elseif inj.type == 'fracture' and not inj.iced and (not best or best.type == 'fracture') then
            if not best or (inj.severity or 0) > (best.severity or 0) then best = inj end
        end
    end
    if not best then return nil, 'nothing_swelling' end
    return best
end

function E.burn_dressing(p, prefer)
    local c = itemCfg('burn_dressing')
    local pick = preferred(p, prefer, function(i)
        local t = i.treat or {}
        local deg = i.burn and i.burn.degree or 1
        return i.type == 'burn' and not (t.dressed or t.grafted) and deg <= (c.maxDegree or 2) and (i.severity or 1) <= (c.maxSeverity or 2)
    end)
    if pick then return pick end
    local best, tooBad
    for _, inj in pairs(p.injuries or {}) do
        if inj.type == 'burn' then
            local t = inj.treat or {}
            local deg = inj.burn and inj.burn.degree or 1
            if not (t.dressed or t.grafted) then
                if deg <= (c.maxDegree or 2) and (inj.severity or 1) <= (c.maxSeverity or 2) then
                    if not best or (inj.severity or 0) > (best.severity or 0) then best = inj end
                else
                    tooBad = inj
                end
            end
        end
    end
    if best then return best end
    if tooBad then return nil, 'burn_too_bad', tooBad end
    return nil, 'nothing_burnt'
end

function E.painkillers(p)
    local c = itemCfg('painkillers')
    if c.stack == false and NZA.Patients.MedActive(p, 'painkillers') then return nil, 'already_painkillers' end
    if NZA.Patients.MedActive(p, 'morphine') then return nil, 'on_morphine' end
    return true
end

function E.foil_blanket(p)
    if p.devices and p.devices.foil then return nil, 'already_foil' end
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- NOTIFY / BILL
-- ════════════════════════════════════════════════════════════════════════

-- toast the patient (when a player) and every medic watching them
function FA.Notify(p, msg, kind, title)
    local sent = {}
    if p.kind == 'player' and p.src then
        Core.Notify(p.src, msg, kind or 'warning', title)
        sent[p.src] = true
    end
    for src in pairs(p.watchers or {}) do
        if not sent[src] then
            Core.Notify(src, msg, kind or 'warning', title)
            sent[src] = true
        end
    end
    return sent
end

function FA.Bill(src, p, kind)
    local amount = tonumber((FA.Cfg('Billing'))[kind]) or 0
    if amount <= 0 or p.kind ~= 'player' or (p.src and p.src == src) then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local rec = NZA.Staff.Get(src)
    if not (rec and rec.medic and rec.onDuty) then return end
    local target = p.src or p.identifier
    if not target then return end
    local ok, err = pcall(NZA.Billing.Charge, target, amount, L('bill_' .. kind), { medic = src, kind = 'firstaid_' .. kind })
    if not ok then NZA.Warn('firstaid: billing failed: ' .. tostring(err)) end
end

-- ════════════════════════════════════════════════════════════════════════
-- STATE BAG 'nzaFa' (oxygen / foil / tourniquet positions for the worn props)
-- ════════════════════════════════════════════════════════════════════════

local lastBag = {}   -- [pid] = encoded value

local function bagOf(p)
    if p.kind == 'player' then
        if p.src and Core.Online(p.src) then return Player(p.src).state end
        return nil
    end
    local ped = NZA.Patients.Ped(p)
    if ped and ped ~= 0 and DoesEntityExist(ped) then return Entity(ped).state end
    return nil
end

function FA.BagValue(p)
    local d = p.devices or {}
    local pos = type(p.meta) == 'table' and type(p.meta.tqPos) == 'table' and p.meta.tqPos or {}
    local tq = nil
    for region in pairs(type(d.tourniquet) == 'table' and d.tourniquet or {}) do
        tq = tq or {}
        local at = pos[region]
        tq[region] = type(at) == 'table' and { s = at.s, f = tonumber(at.f) } or false
    end
    local rec = type(p.meta) == 'table' and p.meta.recovery and true or nil
    return { o2 = d.oxygen and true or nil, foil = d.foil and true or nil, rec = rec, tq = tq }
end

function FA.SyncBag(p, force)
    if not p then return end
    local bag = bagOf(p)
    if not bag then return end
    local v = FA.BagValue(p)
    local enc = json.encode(v)
    if not force and lastBag[p.pid] == enc then return end
    lastBag[p.pid] = enc
    if v.o2 == nil and v.foil == nil and v.rec == nil and v.tq == nil then
        bag:set('nzaFa', nil, true)
    else
        bag:set('nzaFa', v, true)
    end
end

-- injuries keep treat.tourniquet only while a tourniquet still covers them
function FA.ReconcileTq(p)
    for id, inj in pairs(p.injuries or {}) do
        local t = inj.treat or {}
        if t.tourniquet and not FA.TqCovers(p, inj.region) then
            NZA.Patients.UpdateInjury(p.pid, id, { treat = { tourniquet = false } })
        end
    end
    -- forget the bookkeeping of tourniquets that are gone
    local meta = p.meta or {}
    local tq = p.devices and p.devices.tourniquet or {}
    for _, key in ipairs({ 'tqPos', 'tqBy', 'tqWarn', 'tqDmg' }) do
        local m = meta[key]
        if type(m) == 'table' then
            local changed = false
            for region in pairs(m) do
                if not tq[region] then m[region] = nil; changed = true end
            end
            if changed then NZA.Patients.SetMeta(p.pid, key, m) end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- TIMERS: tourniquet warnings / limb damage, dressings soaking through
-- ════════════════════════════════════════════════════════════════════════

local function metaMap(p, key)
    local m = p.meta[key]
    if type(m) ~= 'table' then m = {} end
    return m
end

local function tqTick(p, now)
    local tq = p.devices and p.devices.tourniquet
    if type(tq) ~= 'table' or next(tq) == nil then return end
    local c = FA.Cfg('Tourniquet')
    for region, since in pairs(tq) do
        local t0 = tonumber(since)
        if t0 then
            local elapsed = now - t0
            local warn = metaMap(p, 'tqWarn')
            if elapsed >= (c.warnAfter or 1200) and not warn[region] then
                warn[region] = true
                NZA.Patients.SetMeta(p.pid, 'tqWarn', warn)
                local mins = math.floor(elapsed / 60)
                local sent = FA.Notify(p, L('tq_warn', regionLabel(region), mins), 'warning', L('title_tq'))
                local by = metaMap(p, 'tqBy')[region]
                if by and Core.Online(by) and not sent[by] then Core.Notify(by, L('tq_warn', regionLabel(region), mins), 'warning', L('title_tq')) end
                NZA.Bus.Emit('firstaid:tq_warn', p, region)
            end
            local dmg = metaMap(p, 'tqDmg')
            if elapsed >= (c.damageAfter or 2400) and not dmg[region] and p.state ~= 'dead' then
                dmg[region] = true
                NZA.Patients.SetMeta(p.pid, 'tqDmg', dmg)
                local limb = LIMBS[region]
                local target = limb and limb.lower or region
                local d = c.damage or {}
                NZA.Patients.AddInjury(p.pid, {
                    region = target, type = d.type or 'contusion', severity = d.severity or 3,
                    cause = 'tourniquet', complications = false,
                })
                FA.Notify(p, L('tq_damage', regionLabel(target)), 'error', L('title_tq'))
                NZA.Bus.Emit('firstaid:tq_damage', p, region)
            end
        end
    end
end

local function soakTick(p, now)
    for id, inj in pairs(p.injuries or {}) do
        local at = tonumber(inj.soakAt)
        if at and at <= now then
            local t = inj.treat or {}
            if t.bandaged and not t.packed and not t.sutured and not t.dressed then
                NZA.Patients.UpdateInjury(p.pid, id, { soakAt = false, treat = { bandaged = false }, quality = { bandaged = 0 } })
                FA.Notify(p, L('soaked', regionLabel(inj.region)), 'error', L('title_bleed'))
                NZA.Bus.Emit('firstaid:soaked', p, inj)
            else
                NZA.Patients.UpdateInjury(p.pid, id, { soakAt = false })
            end
        end
    end
end

-- recovery position (meta.recovery): only while wounded, lying on the ground, without a tube
local HELD = { 'carried', 'stretcher', 'bed', 'inBed', 'bay', 'vehicle', 'bodybag' }

function FA.RecoveryHeld(p)
    local m = type(p.meta) == 'table' and p.meta or {}
    for _, k in ipairs(HELD) do
        if m[k] then return true end
    end
    return false
end

function FA.ClearRecovery(p)
    if not (p and type(p.meta) == 'table' and p.meta.recovery) then return false end
    NZA.Patients.SetMeta(p.pid, 'recovery', nil)
    FA.SyncBag(p)
    return true
end

local function recoveryTick(p)
    if not (type(p.meta) == 'table' and p.meta.recovery) then return end
    if p.state ~= 'wounded' or (p.devices and p.devices.intubated) or FA.RecoveryHeld(p) then FA.ClearRecovery(p) end
end

CreateThread(function()
    Wait(5000)
    while true do
        local every = math.max(5, tonumber(FA.Cfg('Tourniquet').checkEvery) or 15)
        local now = os.time()
        for _, p in pairs(NZA.Patients.All()) do
            local ok, err = pcall(function()
                if p.state ~= 'dead' then
                    tqTick(p, now)
                    soakTick(p, now)
                end
                recoveryTick(p)
                FA.SyncBag(p)
            end)
            if not ok then NZA.Warn('firstaid timer failed: ' .. tostring(err)) end
        end
        Wait(every * 1000)
    end
end)

NZA.Bus.On('device:changed', function(p, name, value)
    if name == 'tourniquet' then FA.ReconcileTq(p) end
    if name == 'tourniquet' or name == 'oxygen' or name == 'foil' then FA.SyncBag(p) end
    if name == 'intubated' and value then FA.ClearRecovery(p) end
end)
NZA.Bus.On('state:changed', function(p, _, new)
    if new ~= 'wounded' then FA.ClearRecovery(p) end
end)
NZA.Bus.On('transport:carry', function(_, p, on)
    if on and type(p) == 'table' then FA.ClearRecovery(p) end
end)
NZA.Bus.On('patient:created', function(p) SetTimeout(500, function() FA.SyncBag(p, true) end) end)
NZA.Bus.On('patient:revived', function(p) SetTimeout(250, function() FA.SyncBag(p, true) end) end)
NZA.Bus.On('player:loaded', function(src)
    SetTimeout(3000, function()
        local p = NZA.Patients.GetBySource(src)
        if p then FA.SyncBag(p, true) end
    end)
end)
NZA.Bus.On('patient:removed', function(pid) lastBag[pid] = nil end)

-- ════════════════════════════════════════════════════════════════════════
-- INSTANT TREATMENTS - self-use items (also usable on others)
-- ════════════════════════════════════════════════════════════════════════

local function failMsg(key, ...) return false, { err = key, msg = L('err_' .. key, ...) } end
FA.Fail = failMsg

local function itemPerm(key)
    if key == 'foil_blanket' then return FA.Cfg('Foil').perm end
    return 'basic'
end

local function itemEnabled(key)
    local c = itemCfg(key)
    return c.enabled ~= false and FA.Item(key) ~= nil
end

NZA.Treat.Register('fa_bandage', {
    perm = itemPerm('bandage'), self = true, maxDist = 3.0,
    items = function() return FA.ItemsOf({ bandage = 1 }) end,
    handler = function(src, p, payload)
        if not itemEnabled('bandage') then return failMsg('disabled') end
        local inj, why, heavy = E.bandage(p, type(payload) == 'table' and payload.injury or nil)
        if not inj then
            if why == 'too_heavy' and heavy then return failMsg('too_heavy', regionLabel(heavy.region)) end
            return failMsg(why)
        end
        local q = itemCfg('bandage').quality or 55
        local patch = { treat = { bandaged = true }, quality = { bandaged = q } }
        local soak = FA.Cfg('StopBleed').soak or {}
        if soak.enabled ~= false and (tonumber(inj.bleedBase) or 0) >= (soak.minBleed or 40) and q < (soak.quality or 70)
            and not (inj.treat and inj.treat.packed) then
            patch.soakAt = os.time() + (soak.after or 240)
        end
        NZA.Patients.UpdateInjury(p.pid, inj.id, patch)
        local where = regionLabel(inj.region)
        return true, { msg = L('ok_bandage', injLabel(inj), where), record = L('rec_bandage', injLabel(inj), where) }
    end,
})

NZA.Treat.Register('fa_medkit', {
    perm = itemPerm('medkit'), self = true, maxDist = 3.0,
    items = function() return FA.ItemsOf({ medkit = 1 }) end,
    handler = function(src, p)
        if not itemEnabled('medkit') then return failMsg('disabled') end
        local list, why = E.medkit(p)
        if not list then return failMsg(why) end
        for _, inj in ipairs(list) do
            local patch
            if inj.type == 'contusion' then
                patch = { treat = { cooled = true } }
            elseif inj.type == 'abrasion' then
                patch = { treat = { bandaged = true, irrigated = true }, quality = { bandaged = 70 }, contamination = math.floor((inj.contamination or 0) * 0.4) }
            else
                patch = { treat = { bandaged = true, dressed = true }, quality = { bandaged = 70, dressed = 60 } }
            end
            NZA.Patients.UpdateInjury(p.pid, inj.id, patch)
        end
        NZA.Patients.Heal(p.pid, itemCfg('medkit').heal or 8)
        return true, { msg = L('ok_medkit', #list), record = L('rec_medkit', #list) }
    end,
})

NZA.Treat.Register('fa_painkillers', {
    perm = itemPerm('painkillers'), self = true, maxDist = 3.0,
    states = { alive = true, wounded = true },
    items = function() return FA.ItemsOf({ painkillers = 1 }) end,
    handler = function(src, p)
        if not itemEnabled('painkillers') then return failMsg('disabled') end
        local ok, why = E.painkillers(p)
        if not ok then return failMsg(why) end
        local avpu = p.vitals and p.vitals.avpu or 'A'
        if avpu ~= 'A' and avpu ~= 'V' then return failMsg('cant_swallow') end
        local given = NZA.Patients.GiveMed(p.pid, 'painkillers', { dose = 1, route = 'po', by = src })
        if not given then return failMsg('failed') end
        return true, { msg = L('ok_painkillers'), record = L('rec_painkillers') }
    end,
})

NZA.Treat.Register('fa_ice', {
    perm = itemPerm('ice_pack'), self = true, maxDist = 3.0,
    items = function() return FA.ItemsOf({ ice_pack = 1 }) end,
    handler = function(src, p, payload)
        if not itemEnabled('ice_pack') then return failMsg('disabled') end
        local inj, why = E.ice_pack(p, type(payload) == 'table' and payload.injury or nil)
        if not inj then return failMsg(why) end
        local where = regionLabel(inj.region)
        if inj.type == 'contusion' then
            NZA.Patients.UpdateInjury(p.pid, inj.id, { treat = { cooled = true }, pain = math.floor((inj.pain or 0) * 0.75) })
        else
            local f = itemCfg('ice_pack').fracturePain or 0.8
            NZA.Patients.UpdateInjury(p.pid, inj.id, { iced = os.time(), pain = math.floor((inj.pain or 0) * f) })
        end
        return true, { msg = L('ok_ice', injLabel(inj), where), record = L('rec_ice', injLabel(inj), where) }
    end,
})

NZA.Treat.Register('fa_burn', {
    perm = itemPerm('burn_dressing'), self = true, maxDist = 3.0,
    items = function() return FA.ItemsOf({ burn_dressing = 1 }) end,
    handler = function(src, p, payload)
        if not itemEnabled('burn_dressing') then return failMsg('disabled') end
        local inj, why, bad = E.burn_dressing(p, type(payload) == 'table' and payload.injury or nil)
        if not inj then
            if why == 'burn_too_bad' and bad then return failMsg('burn_too_bad', regionLabel(bad.region)) end
            return failMsg(why)
        end
        local burn = inj.burn or {}
        NZA.Patients.UpdateInjury(p.pid, inj.id, {
            treat = { cooled = true, dressed = true }, quality = { dressed = 65, cooled = 60 },
            burn = { temp = math.min(tonumber(burn.temp) or 34, 33) },
            contamination = math.floor((inj.contamination or 0) * 0.5),
        })
        local where = regionLabel(inj.region)
        return true, { msg = L('ok_burn', where), record = L('rec_burn', where) }
    end,
})

NZA.Treat.Register('fa_foil', {
    perm = itemPerm('foil_blanket'), self = true, maxDist = 3.0,
    items = function() return FA.ItemsOf({ [FA.Cfg('Foil').item or 'foil_blanket'] = 1 }) end,
    handler = function(src, p)
        if not itemEnabled('foil_blanket') then return failMsg('disabled') end
        local ok, why = E.foil_blanket(p)
        if not ok then return failMsg(why) end
        NZA.Patients.SetDevice(p.pid, 'foil', true)
        return true, { msg = L('ok_foil'), record = L('rec_foil') }
    end,
})

local function giveBack(src, key)
    local name = FA.Item(key)
    if not name or not src or src <= 0 then return end
    if Core.Has('Inv.CanCarry') and not Core.B('Inv.CanCarry', src, name, 1) then return end
    Core.B('Inv.AddItem', src, name, 1)
end

NZA.Treat.Register('fa_foil_off', {
    perm = itemPerm('foil_blanket'), self = true, maxDist = 3.0, record = false,
    handler = function(src, p)
        if not (p.devices and p.devices.foil) then return failMsg('no_foil') end
        NZA.Patients.SetDevice(p.pid, 'foil', false)
        if FA.Cfg('Foil').removeReturns then giveBack(src, FA.Cfg('Foil').item or 'foil_blanket') end
        return true, { msg = L('ok_foil_off') }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- OXYGEN / COLLAR OFF / TOURNIQUET OFF
-- ════════════════════════════════════════════════════════════════════════

NZA.Treat.Register('fa_oxygen', {
    perm = FA.Cfg('Oxygen').perm or 'airway', self = false, maxDist = 3.0,
    states = { alive = true, wounded = true, arrest = true },
    items = function()
        local c = FA.Cfg('Oxygen')
        if c.consume == false then return {} end
        return FA.ItemsOf({ [c.item or 'oxygen_mask'] = 1 })
    end,
    handler = function(src, p)
        local c = FA.Cfg('Oxygen')
        if p.devices.oxygen then return failMsg('already_oxygen') end
        if p.devices.intubated then return failMsg('intubated') end
        if c.consume == false then
            local name = FA.Item(c.item or 'oxygen_mask')
            if name and not Core.CheckItems(src, { [name] = 1 }) then return failMsg('need_item', Core.B('Inv.Label', name) or name) end
        end
        NZA.Patients.SetDevice(p.pid, 'oxygen', true)
        FA.Bill(src, p, 'oxygen')
        local spo2 = p.vitals and p.vitals.spo2
        return true, { msg = spo2 and L('ok_oxygen_spo2', math.floor(spo2)) or L('ok_oxygen'), record = L('rec_oxygen') }
    end,
})

NZA.Treat.Register('fa_oxygen_off', {
    perm = FA.Cfg('Oxygen').perm or 'airway', self = true, maxDist = 3.0, record = false,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p)
        if not p.devices.oxygen then return failMsg('no_oxygen') end
        NZA.Patients.SetDevice(p.pid, 'oxygen', false)
        if FA.Cfg('Oxygen').removeReturns then giveBack(src, FA.Cfg('Oxygen').item or 'oxygen_mask') end
        return true, { msg = L('ok_oxygen_off') }
    end,
})

NZA.Treat.Register('fa_collar_off', {
    perm = FA.Cfg('Collar').perm or 'splint', self = false, maxDist = 3.0,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p)
        if not p.devices.collar then return failMsg('no_collar') end
        NZA.Patients.SetDevice(p.pid, 'collar', false)
        if FA.Cfg('Collar').removeReturns ~= false then giveBack(src, FA.Cfg('Collar').item or 'cervical_collar') end
        local warn = p.conditions and p.conditions.spinal
        return true, { msg = warn and L('ok_collar_off_spinal') or L('ok_collar_off'), record = L('rec_collar_off') }
    end,
})

NZA.Treat.Register('fa_tq_off', {
    perm = FA.Cfg('Tourniquet').removePerm or 'basic', self = true, maxDist = 3.0,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p, payload)
        local tq = p.devices.tourniquet or {}
        local region = type(payload) == 'table' and payload.region or nil
        if type(region) ~= 'string' or not tq[region] then
            region = next(tq)
            if not region then return failMsg('no_tq') end
        end
        local since = tonumber(tq[region]) or os.time()
        NZA.Patients.SetDevice(p.pid, 'tourniquet', region, false)
        if FA.Cfg('Tourniquet').removeReturns ~= false then giveBack(src, FA.Cfg('Tourniquet').item or 'tourniquet') end
        NZA.Physiology.Refresh(p)
        -- does it bleed again now?
        local again = 0
        for _, inj in pairs(p.injuries) do
            local limb = LIMBS[inj.region]
            if inj.region == region or (limb and limb.upper == region) then again = again + (tonumber(inj.bleed) or 0) end
        end
        local mins = math.floor((os.time() - since) / 60)
        local msg
        if again >= 1 then
            msg = L('ok_tq_off_bleeding', regionLabel(region), math.floor(again + 0.5))
        else
            msg = L('ok_tq_off', regionLabel(region), mins)
        end
        return true, { msg = msg, record = L('rec_tq_off', regionLabel(region), mins) }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- RECOVERY POSITION (basic airway: an unconscious patient on their back snores,
-- core physiology reads meta.recovery; FA.ClearRecovery undoes it)
-- ════════════════════════════════════════════════════════════════════════

NZA.Treat.Register('fa_recovery', {
    perm = FA.Cfg('Recovery').perm or 'basic', self = false, maxDist = 3.0,
    states = { wounded = true },
    handler = function(src, p)
        if FA.Cfg('Recovery').enabled == false then return failMsg('recovery_disabled') end
        if p.meta.recovery then return failMsg('already_recovery') end
        if p.devices.intubated then return failMsg('recovery_tube') end
        if FA.RecoveryHeld(p) then return failMsg('recovery_held') end
        local avpu = p.vitals and p.vitals.avpu or 'A'
        if avpu == 'A' or avpu == 'V' then return failMsg('recovery_awake') end
        -- a collar or a spinal injury: log-roll with the head kept in line
        local spine = (p.devices.collar or (p.conditions and p.conditions.spinal)) and true or false
        NZA.Patients.SetMeta(p.pid, 'recovery', true)
        FA.SyncBag(p)
        return true, { msg = L(spine and 'ok_recovery_logroll' or 'ok_recovery'), record = L('rec_recovery') }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- KIT PREVIEW (what each first aid item would do to this patient)
-- ════════════════════════════════════════════════════════════════════════

local KIT_ORDER = { 'bandage', 'medkit', 'ice_pack', 'burn_dressing', 'painkillers', 'foil_blanket' }
FA.KitOrder = KIT_ORDER

local function kitText(key, p, isSelf)
    local fn = E[key]
    if not fn then return false, L('kit_none') end
    local res, why, extra = fn(p)
    if not res then
        if why == 'too_heavy' and extra then return false, L('err_too_heavy', regionLabel(extra.region)) end
        if why == 'burn_too_bad' and extra then return false, L('err_burn_too_bad', regionLabel(extra.region)) end
        return false, L('err_' .. tostring(why))
    end
    if key == 'bandage' or key == 'ice_pack' then
        return true, L('kit_' .. key, injLabel(res), regionLabel(res.region))
    elseif key == 'burn_dressing' then
        return true, L('kit_burn_dressing', regionLabel(res.region))
    elseif key == 'medkit' then
        return true, L('kit_medkit', #res)
    elseif key == 'painkillers' then
        return true, L('kit_painkillers', math.floor(tonumber(p.pain) or 0))
    elseif key == 'foil_blanket' then
        local temp = tonumber(p.temp) or (p.vitals and tonumber(p.vitals.temp)) or 37
        return true, L(temp < 35.5 and 'kit_foil_cold' or 'kit_foil', U.round(temp, 1))
    end
    return true, ''
end

lib.callback.register('nza:firstaid:kit', function(src, target)
    if not Core.Rate('nza:firstaid:kit', src, 4, 1000) then return nil end
    local p = NZA.Patients.Resolve(target)
    if not p then return nil end
    local isSelf = p.kind == 'player' and p.src == src
    if not isSelf and Core.DistanceTo(src, p) > 4.5 then return nil end
    local out = {}
    for _, key in ipairs(KIT_ORDER) do
        if itemEnabled(key) and NZA.Staff.Can(src, itemPerm(key)) then
            local usable, text = kitText(key, p, isSelf)
            out[#out + 1] = { key = key, item = FA.Item(key), usable = usable, text = text }
        end
    end
    return { name = p.name, self = isSelf, state = p.state, items = out }
end)

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS (inventory → client flow 'nza:firstaid:use' → progress → nza:treat)
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1500)
    if not Core.Has('Inv.RegisterUsable') then
        NZA.Warn('firstaid: Bridge.Inv.RegisterUsable is missing - first aid items are not usable from the inventory')
        return
    end
    for _, key in ipairs(KIT_ORDER) do
        local c = itemCfg(key)
        local name = FA.Item(key)
        if name and c.enabled ~= false and c.self ~= false then
            Core.B('Inv.RegisterUsable', name, function(src)
                src = tonumber(src)
                if not src or not Core.Rate('nza:firstaid:use', src, 2, 1500) then return end
                TriggerClientEvent('nza:firstaid:use', src, key)
            end)
        end
    end
end)
