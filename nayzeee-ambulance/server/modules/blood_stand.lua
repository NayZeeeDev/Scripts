--[[
    NAYZEEE AMBULANCE - IV stand & transfusion (server)

    The IV stand (NUI app 'ivstand') is opened by any module with NZA.Blood.OpenStand(target, info)
    on the client: ambulance treatment bay (F3), hospital beds, surgery, field.

    Instant treatments (NZA.Treat):
      'ivstand:hang'      perm Stand.perm (+ Stand.bloodPerm for blood)
                          payload { kind = 'saline'|'blood', serial?, slot?, type?, rate (mL/min), force?, hook?, at = {x,y,z}?, h? }
                          saline consumes Config.Items[Stand saline]; blood takes the unit with NZA.Blood.TakeBag.
                          Known mismatch (patient typed) needs force = true (and Stand.allowIncompatible).
                          → NZA.Patients.AddInfusion { kind, ml, rate, bag = label metadata, warm, by }
      'ivstand:rate'      payload { id, rate }      roller clamp / pressure infuser flow
      'ivstand:takedown'  payload { id }            NZA.Patients.StopInfusion (the rest of a blood unit is discarded)
      'ivstand:txa'       payload { seconds }       1 g TXA slow push (Stand.txa.item) → GiveMed 'txa'
      'ivstand:access'    payload {}                quick IV placement when the field module is not installed
    Callbacks:
      nza:blood:stand:info (target) → { ok, data }  everything the panel shows (access, bags, stock, vitals)
      nza:blood:stand:fill (type?) → { ok, msg }    'Bag a unit' from the ambulance fridge (in a bay)
    State bag 'nzaStand' on the patient (player or NPC ped), replicated, read by every client to draw
      the stand: { at = { x, y, z } | nil, h, bay = vehNet | nil, b = { { id, k, t, f (fill %), hook, done } } }
    Transfusion reaction: incompatible blood (core flags infusion.incompatible) → stages by mL received
      (Config.Blood.Reaction.stages): speech, condition 'reaction' { stage, ml }, haemolysis (AddBlood -mL/min)
      on top of the core reaction effect (fever, tachycardia, hypotension). Ends feverMinutes after the last drop.
    Bus (server): blood:hung (src, p, inf), blood:reaction (p, stage)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Blood = NZA.Blood or {}
local B = NZA.Blood
local Core = NZA.Core
local U = NZA.Util

local function sc() return (Config.Blood or {}).Stand or {} end
local function rc() return (Config.Blood or {}).Reaction or {} end
local function L(key, ...) return NZA.L('blood.' .. key, ...) end
local function fail(key, ...) return false, { err = key, msg = NZA.L('blood.err_' .. key, ...) } end

local function item(key) return key and Config.Items and Config.Items[key] or nil end

local stands = {}      -- [pid] = { at, h, bay, bags = { [infId] = { id, k, t, f, hook, done, doneAt } } }
local reactions = {}   -- [pid] = { ml, stage, lastAt, track = { [infId] = left }, by = { [src] = true } }

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function access(p)
    local d = p.devices or {}
    if type(d.iv) == 'table' then return { kind = d.iv.kind or 'iv', site = d.iv.site } end
    if d.iv == true then return { kind = 'iv' } end
    if d.port then return { kind = 'port', site = type(d.port) == 'table' and d.port.site or nil } end
    return nil
end

local function findInf(p, id)
    for _, inf in ipairs(p.infusions or {}) do
        if inf.id == id then return inf end
    end
    return nil
end

local function clampRate(r)
    return U.clamp(tonumber(r) or tonumber(sc().gravity) or 32, 0.1, tonumber(sc().maxRate) or 160)
end

local function stateOf(p)
    if p.kind == 'player' and p.src and GetPlayerName(p.src) then return Player(p.src).state end
    local ped = NZA.Patients.Ped(p)
    if ped and ped ~= 0 and DoesEntityExist(ped) then return Entity(ped).state end
    return nil
end

local function bagType(bag)
    return type(bag) == 'table' and (bag.type or bag.bloodType) or nil
end

local function push(p)
    local st = stateOf(p)
    if not st then return end
    local s = stands[p.pid]
    if not s or not next(s.bags) then
        st:set('nzaStand', nil, true)
        return
    end
    local list = {}
    for _, b in pairs(s.bags) do
        list[#list + 1] = { id = b.id, k = b.k, t = b.t, f = b.f, hook = b.hook, done = b.done or nil }
    end
    table.sort(list, function(a, c) return (a.hook or 9) < (c.hook or 9) end)
    st:set('nzaStand', {
        at = s.at and { x = s.at.x, y = s.at.y, z = s.at.z } or nil, h = s.h, bay = s.bay, b = list,
    }, true)
end

local function freeHook(s)
    local used = {}
    for _, b in pairs(s.bags) do if b.hook then used[b.hook] = true end end
    for i = 1, math.max(1, tonumber(sc().maxBags) or 2) do
        if not used[i] then return i end
    end
    return nil
end

local function fillOf(inf)
    local ml = tonumber(inf.ml) or 1
    return math.floor(U.clamp((tonumber(inf.left) or 0) / math.max(1, ml), 0, 1) * 20 + 0.5) * 5
end

local function standFor(src, p, payload)
    local s = stands[p.pid]
    local vehNet = NZA.Transport and NZA.Transport.InBay and NZA.Transport.InBay(src) or nil
    if not s then
        s = { bags = {} }
        stands[p.pid] = s
    end
    if vehNet then
        s.bay, s.at = vehNet, nil
        return s
    end
    s.bay = nil
    if not s.at then
        local pc = Core.PatientCoords(p)
        local at = type(payload) == 'table' and U.vec(payload.at) or nil
        if at and pc and #(at - pc) <= 3.0 then
            s.at = at
            s.h = tonumber(payload.h) or 0.0
        elseif pc then
            s.at = pc
            s.h = 0.0
        end
    end
    return s
end

-- infusions hung by other modules (field resuscitation...) get a hook on the stand too
local function adopt(p)
    local s = stands[p.pid]
    for _, inf in ipairs(p.infusions or {}) do
        if inf.kind == 'saline' or inf.kind == 'blood' or inf.kind == 'plasma' then
            if not s then
                s = { bags = {} }
                stands[p.pid] = s
                local pc = Core.PatientCoords(p)
                if p.meta and p.meta.bay then s.bay = p.meta.bay elseif pc then s.at = pc s.h = 0.0 end
            end
            if not s.bags[inf.id] then
                local hook = freeHook(s)
                if hook then
                    s.bags[inf.id] = { id = inf.id, k = inf.kind, t = bagType(inf.bag), f = fillOf(inf), hook = hook }
                end
            end
        end
    end
    if s then push(p) end
end

local function canWarm(p)
    if sc().warmInBay == false then return false end
    local m = p.meta or {}
    return m.bay ~= nil or m.bed ~= nil or m.inBed == true
end

-- ════════════════════════════════════════════════════════════════════════
-- TREATMENTS
-- ════════════════════════════════════════════════════════════════════════

local ALIVE = { alive = true, wounded = true, arrest = true }

NZA.Treat.Register('ivstand:hang', {
    perm = sc().perm or 'iv', maxDist = 3.5, cooldown = 500,
    states = ALIVE,
    items = function(src, p, payload)
        if type(payload) == 'table' and payload.kind == 'saline' then
            local name = item('saline_bag')
            return name and { [name] = 1 } or {}
        end
        return {}
    end,
    handler = function(src, p, payload)
        local cfg = sc()
        payload = type(payload) == 'table' and payload or {}
        local kind = payload.kind == 'blood' and 'blood' or payload.kind == 'saline' and 'saline' or nil
        if not kind then return fail('failed') end
        if cfg.requireAccess ~= false and not access(p) then return fail('no_access') end
        local s = stands[p.pid]
        if s and not freeHook(s) then return fail('hooks_full') end
        local rate = clampRate(payload.rate)
        local warm = canWarm(p)
        local inf
        if kind == 'saline' then
            inf = NZA.Patients.AddInfusion(p.pid, { kind = 'saline', ml = tonumber(cfg.salineMl) or 500, rate = rate, warm = warm, by = src })
        else
            if not NZA.Staff.Can(src, cfg.bloodPerm or 'blood') then return fail('no_blood_perm') end
            local sel = { serial = type(payload.serial) == 'string' and payload.serial or nil, slot = tonumber(payload.slot), type = payload.type }
            local list = B.BagsOf(src)
            local pick
            for _, b in ipairs(list) do
                if (sel.serial and b.serial == sel.serial) or (not sel.serial and sel.slot and b.slot == sel.slot)
                    or (not sel.serial and not sel.slot and (not sel.type or b.type == sel.type) and not b.expired) then
                    pick = b
                    break
                end
            end
            if not pick then return fail('no_bag') end
            local typed = B.IsTyped(p)
            local compatible = B.Compatible(p, pick.type)
            if typed and not compatible then
                if cfg.allowIncompatible == false then return fail('incompatible_block', pick.type, p.bloodType or '?') end
                if payload.force ~= true then return fail('incompatible', pick.type, p.bloodType or '?') end
            end
            local meta, why = B.TakeBag(src, pick.serial or pick.slot)
            if not meta then return false, { err = 'no_bag', msg = why } end
            inf = NZA.Patients.AddInfusion(p.pid, {
                kind = 'blood', ml = tonumber(meta.ml) or 450, rate = rate, bag = meta, warm = warm, by = src,
            })
        end
        if not inf then return fail('failed') end
        s = standFor(src, p, payload)
        local hook = freeHook(s) or 1
        local want = tonumber(payload.hook)
        if want and want >= 1 and want <= (tonumber(cfg.maxBags) or 2) then
            local taken = false
            for _, b in pairs(s.bags) do if b.hook == want then taken = true end end
            if not taken then hook = math.floor(want) end
        end
        s.bags[inf.id] = { id = inf.id, k = inf.kind, t = bagType(inf.bag), f = 100, hook = hook }
        push(p)
        B.Bill(src, p, kind == 'blood' and 'unit' or 'saline')
        NZA.Bus.Emit('blood:hung', src, p, inf)
        local label = kind == 'blood' and L('bag_blood', bagType(inf.bag) or '?', math.floor(inf.ml)) or L('bag_saline', math.floor(inf.ml))
        return true, {
            id = inf.id, kind = inf.kind, ml = inf.ml, left = inf.left, rate = inf.rate, hook = hook, warm = inf.warm,
            bag = type(inf.bag) == 'table' and { type = bagType(inf.bag), serial = inf.bag.serial, donor = inf.bag.donor,
                created = inf.bag.created, expires = inf.bag.expires, ml = inf.bag.ml } or nil,
            msg = L('ok_hung', label), record = L('rec_hung', label, math.floor(inf.rate)),
        }
    end,
})

NZA.Treat.Register('ivstand:rate', {
    perm = sc().perm or 'iv', maxDist = 4.5, cooldown = 200, record = false,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p, payload)
        payload = type(payload) == 'table' and payload or {}
        local inf = type(payload.id) == 'string' and findInf(p, payload.id) or nil
        if not inf then return fail('no_running') end
        local rate = clampRate(payload.rate)
        if math.abs((inf.rate or 0) - rate) < 0.5 then return true, { id = inf.id, rate = inf.rate, left = inf.left } end
        -- the core has no rate setter: re-hang the same bag (same id, what is left) at the new rate
        local ok, old = NZA.Patients.StopInfusion(p.pid, inf.id)
        if not ok or not old then return fail('no_running') end
        local n = NZA.Patients.AddInfusion(p.pid, {
            id = old.id, kind = old.kind, ml = old.ml, left = old.left, rate = rate, bag = old.bag, warm = old.warm, by = old.by,
            incompatible = old.incompatible,
        })
        if n and old.paused then n.paused = old.paused end
        return true, { id = old.id, rate = rate, left = n and n.left or old.left }
    end,
})

NZA.Treat.Register('ivstand:takedown', {
    perm = sc().perm or 'iv', maxDist = 4.5, cooldown = 300,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p, payload)
        payload = type(payload) == 'table' and payload or {}
        local id = type(payload.id) == 'string' and payload.id or nil
        if not id then return fail('no_running') end
        local s = stands[p.pid]
        local inf = findInf(p, id)
        local given, kind = 0, nil
        if inf then
            local _, old = NZA.Patients.StopInfusion(p.pid, id)
            old = old or inf
            given = math.floor((old.ml or 0) - (old.left or 0) + 0.5)
            kind = old.kind
            if old.kind == 'blood' and type(old.bag) == 'table' and old.bag.serial and B.SetUsed then
                B.SetUsed(old.bag.serial, 2, nil)
            end
        elseif not (s and s.bags[id]) then
            return fail('no_running')
        else
            kind = s.bags[id].k
            given = -1
        end
        if s then
            s.bags[id] = nil
            if not next(s.bags) then stands[p.pid] = nil end
        end
        push(p)
        local msg = given >= 0 and L('ok_takedown', given) or L('ok_takedown_empty')
        return true, { id = id, given = math.max(0, given), kind = kind, msg = msg, record = L('rec_takedown', kind or '?', math.max(0, given)) }
    end,
})

NZA.Treat.Register('ivstand:txa', {
    perm = (sc().txa or {}).perm or sc().perm or 'iv', maxDist = 3.5, cooldown = 1000,
    states = ALIVE,
    items = function()
        local name = item((sc().txa or {}).item or 'txa')
        return name and { [name] = 1 } or {}
    end,
    handler = function(src, p, payload)
        if sc().requireAccess ~= false and not access(p) then return fail('no_access') end
        if p.meds and p.meds.txa and p.meds.txa > os.time() + 1800 then return fail('txa_active') end
        local okMed = NZA.Patients.GiveMed(p.pid, 'txa', { dose = 1, route = 'iv', by = src })
        if not okMed then return fail('failed') end
        local secs = tonumber(type(payload) == 'table' and payload.seconds) or 0
        local fast = secs > 0 and secs < ((sc().txa or {}).push or 10) * 0.6
        if fast then Core.Speech(src, p.name, L('say_dizzy'), 3500) end
        B.Bill(src, p, 'txa')
        return true, { fast = fast, msg = fast and L('ok_txa_fast') or L('ok_txa'), record = L('rec_txa', math.floor(secs)) }
    end,
})

NZA.Treat.Register('ivstand:access', {
    perm = sc().perm or 'iv', maxDist = 3.0, cooldown = 2000,
    states = ALIVE,
    items = function()
        local name = item((sc().placeIv or {}).item or 'iv_kit')
        return name and { [name] = 1 } or {}
    end,
    handler = function(src, p)
        if (sc().placeIv or {}).fallback == false then return fail('failed') end
        if access(p) then return fail('has_access') end
        local site = (sc().placeIv or {}).site or 'l_lower_arm'
        NZA.Patients.SetDevice(p.pid, 'iv', { site = site, kind = 'iv', by = src, at = os.time() })
        return true, { msg = L('ok_access'), record = L('rec_access', U.RegionLabel(site)) }
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- PANEL DATA
-- ════════════════════════════════════════════════════════════════════════

local vehStock = {}    -- [vehNet] = { units = { [type] = n }, refill = { { type, at } } }

local function bayStock(vehNet)
    local now = os.time()
    local v = vehStock[vehNet]
    if not v then
        v = { units = {}, refill = {} }
        for bt, n in pairs(sc().bayStock or {}) do
            if B.ValidType(bt) then v.units[bt] = math.floor(tonumber(n) or 0) end
        end
        vehStock[vehNet] = v
    end
    for i = #v.refill, 1, -1 do
        local r = v.refill[i]
        if now >= r.at then
            v.units[r.type] = (v.units[r.type] or 0) + 1
            table.remove(v.refill, i)
        end
    end
    return v
end

local function infView(p, inf, s, typed, reacting)
    local sb = s and s.bags[inf.id] or nil
    local bag = type(inf.bag) == 'table' and inf.bag or nil
    return {
        id = inf.id, kind = inf.kind, ml = inf.ml, left = U.round(inf.left or 0, 1), rate = U.round(inf.rate or 0, 1),
        hook = sb and sb.hook or nil, paused = inf.paused and true or nil, warm = inf.warm or nil,
        mine = nil,
        bag = bag and { type = bagType(bag), serial = bag.serial, donor = bag.donor, created = bag.created, expires = bag.expires, ml = bag.ml } or nil,
        incompatible = (typed or reacting) and inf.incompatible or nil,
    }
end

local function panelData(src, p)
    adopt(p)
    local s = stands[p.pid]
    local typed = B.IsTyped(p)
    local react = p.conditions and p.conditions.reaction or nil
    local list = {}
    local running = {}
    for _, inf in ipairs(p.infusions or {}) do
        if inf.kind == 'saline' or inf.kind == 'blood' or inf.kind == 'plasma' then
            local v = infView(p, inf, s, typed, react ~= nil)
            v.mine = inf.by == src
            list[#list + 1] = v
            running[inf.id] = true
        end
    end
    -- finished bags still hanging
    if s then
        for id, b in pairs(s.bags) do
            if not running[id] then
                list[#list + 1] = { id = id, kind = b.k, ml = 0, left = 0, rate = 0, hook = b.hook, done = true, bag = b.t and { type = b.t } or nil }
            end
        end
    end
    table.sort(list, function(a, c) return (a.hook or 9) < (c.hook or 9) end)
    local vehNet = NZA.Transport and NZA.Transport.InBay and NZA.Transport.InBay(src) or nil
    local cfg = sc()
    local v = p.vitals or {}
    return {
        patient = {
            pid = p.pid, name = p.name, state = p.state, typed = typed, bloodType = typed and p.bloodType or nil,
            bloodPct = math.floor(((tonumber(p.blood) or 0) / math.max(1, tonumber(p.bloodMax) or 5000)) * 100 + 0.5),
            fluid = math.floor(tonumber(p.fluid) or 0), bleed = U.round(tonumber(p.bleedTotal) or 0, 1),
            given = { saline = math.floor((p.given or {}).saline or 0), blood = math.floor((p.given or {}).blood or 0), txa = (p.given or {}).txa or 0 },
            txaActive = p.meds and p.meds.txa and p.meds.txa > os.time() or false,
            vitals = { hr = v.hr, sys = v.sys, dia = v.dia, map = v.map, spo2 = v.spo2, temp = v.temp or p.temp },
            reaction = react and { stage = react.stage, ml = react.ml } or nil,
        },
        access = access(p),
        infusions = list,
        inventory = {
            saline = B.Count(src, item('saline_bag')), txa = B.Count(src, item((cfg.txa or {}).item or 'txa')),
            empty = B.Count(src, item((Config.Blood.Bags or {}).empty or 'empty_blood_bag')),
            ivkit = B.Count(src, item((cfg.placeIv or {}).item or 'iv_kit')),
            bags = B.BagsOf(src, typed and p or nil),
        },
        bay = vehNet and { stock = bayStock(vehNet).units, needEmpty = ((Config.Blood.Bank or {}).needEmptyBag ~= false) } or nil,
        perms = {
            iv = NZA.Staff.Can(src, cfg.perm or 'iv'), blood = NZA.Staff.Can(src, cfg.bloodPerm or 'blood'),
            type = NZA.Staff.Can(src, ((Config.Blood or {}).TypeScreen or {}).perm or 'blood'),
        },
        easy = NZA.Staff.Easy(src, cfg.perm or 'iv'),
        warm = canWarm(p),
        now = os.time(),
    }
end

lib.callback.register('nza:blood:stand:info', function(src, target)
    if not Core.Rate('blood:stand', src, 8, 3000) then return { ok = false, err = 'rate', msg = L('err_rate') } end
    local p = NZA.Patients.Resolve(target)
    if not p then return { ok = false, err = 'no_patient', msg = L('err_no_patient') } end
    if not NZA.Staff.Can(src, sc().perm or 'iv') then return { ok = false, err = 'no_perm', msg = L('err_no_perm') } end
    if Core.DistanceTo(src, p) > (tonumber(sc().range) or 6.0) + 2.0 then return { ok = false, err = 'too_far', msg = L('err_too_far') } end
    return { ok = true, data = panelData(src, p) }
end)

lib.callback.register('nza:blood:stand:fill', function(src, btype)
    if not Core.Rate('blood:stand', src, 8, 3000) then return { ok = false, msg = L('err_rate') } end
    if not NZA.Staff.Can(src, sc().bloodPerm or 'blood') then return { ok = false, msg = L('err_no_blood_perm') } end
    local vehNet = NZA.Transport and NZA.Transport.InBay and NZA.Transport.InBay(src) or nil
    if not vehNet then return { ok = false, msg = L('err_not_bay') } end
    local v = bayStock(vehNet)
    btype = B.ValidType(btype)
    if not btype then
        for bt, n in pairs(v.units) do if n > 0 then btype = bt break end end
    end
    if not btype or (v.units[btype] or 0) < 1 then return { ok = false, msg = L('err_bay_empty') } end
    local needEmpty = (Config.Blood.Bank or {}).needEmptyBag ~= false
    local empty = item((Config.Blood.Bags or {}).empty or 'empty_blood_bag')
    if needEmpty and B.Count(src, empty) < 1 then return { ok = false, msg = L('err_no_empty') } end
    local bagName = item((Config.Blood.Bags or {}).item or 'blood_bag')
    if Core.Has('Inv.CanCarry') and Core.B('Inv.CanCarry', src, bagName, 1) == false then return { ok = false, msg = L('err_cant_carry') } end
    if needEmpty and not Core.B('Inv.RemoveItem', src, empty, 1) then return { ok = false, msg = L('err_no_empty') } end
    local meta = B.CreateBag({ type = btype, donor = L('donor_onboard') })
    if not B.GiveBag(src, meta) then
        B.SetUsed(meta.serial, 3, nil)
        if needEmpty then Core.B('Inv.AddItem', src, empty, 1) end
        return { ok = false, msg = L('err_cant_carry') }
    end
    v.units[btype] = v.units[btype] - 1
    v.refill[#v.refill + 1] = { type = btype, at = os.time() + (tonumber(sc().bayRefill) or 30) * 60 }
    return { ok = true, msg = L('ok_fill', btype, meta.serial), serial = meta.serial, type = btype }
end)

-- ════════════════════════════════════════════════════════════════════════
-- TRANSFUSION REACTION
-- ════════════════════════════════════════════════════════════════════════

local function stageOf(ml)
    local st = rc().stages or { 40, 140, 280 }
    local stage = 0
    for i, v in ipairs(st) do
        if ml >= (tonumber(v) or math.huge) then stage = i end
    end
    return stage
end

local function sayTo(r, p, text)
    if rc().speech == false then return end
    local sent = {}
    for s in pairs(r.by) do
        if GetPlayerName(s) then
            Core.Speech(s, p.name, text, 4500)
            sent[s] = true
        end
    end
    for s in pairs(p.watchers or {}) do
        if not sent[s] and GetPlayerName(s) then Core.Speech(s, p.name, text, 4500) end
    end
end

local function reactionTick(dt)
    if rc().enabled == false then return end
    local now = os.time()
    for pid, p in pairs(NZA.Patients.All()) do
        local r = reactions[pid]
        local flowing = false
        for _, inf in ipairs(p.infusions or {}) do
            if inf.kind == 'blood' and inf.incompatible then
                r = r or { ml = 0, stage = 0, lastAt = now, track = {}, by = {} }
                reactions[pid] = r
                local prev = r.track[inf.id] or inf.ml or 0
                local delta = math.max(0, prev - (inf.left or 0))
                r.track[inf.id] = inf.left or 0
                if delta > 0 then
                    r.ml = r.ml + delta
                    r.lastAt = now
                    flowing = true
                end
                if inf.by then r.by[inf.by] = true end
            end
        end
        if r then
            local stage = stageOf(r.ml)
            if stage > r.stage then
                r.stage = stage
                NZA.Patients.SetCondition(pid, 'reaction', { stage = stage, ml = math.floor(r.ml), since = r.since or now })
                r.since = r.since or now
                sayTo(r, p, L('say_reaction_' .. stage))
                if rc().alertMedic ~= false then
                    for s in pairs(r.by) do
                        if GetPlayerName(s) then
                            Core.Notify(s, { title = L('reaction_title'), message = L('reaction_' .. stage, p.name or '?'), type = 'error', duration = 9000 })
                        end
                    end
                end
                NZA.Bus.Emit('blood:reaction', p, stage)
            elseif stage > 0 and p.conditions and p.conditions.reaction and math.floor(r.ml) - (p.conditions.reaction.ml or 0) >= 20 then
                NZA.Patients.SetCondition(pid, 'reaction', { stage = r.stage, ml = math.floor(r.ml), since = r.since })
            end
            -- haemolysis: the incompatible cells (and some of the patient's own) break down
            local h = (rc().haemolysis or {})[r.stage] or 0
            local active = now - r.lastAt < (tonumber(rc().feverMinutes) or 10) * 60
            if h > 0 and active and p.state ~= 'dead' then
                NZA.Patients.AddBlood(pid, -h * dt / 60)
            end
            if not flowing and not active then
                reactions[pid] = nil
                if p.conditions and p.conditions.reaction then NZA.Patients.SetCondition(pid, 'reaction', nil) end
            end
        end
    end
    for pid in pairs(reactions) do
        if not NZA.Patients.Get(pid) then reactions[pid] = nil end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- STAND SYNC
-- ════════════════════════════════════════════════════════════════════════

local function syncStands()
    local now = os.time()
    for pid, s in pairs(stands) do
        local p = NZA.Patients.Get(pid)
        if not p then
            stands[pid] = nil
        else
            local changed = false
            local seen = {}
            for _, inf in ipairs(p.infusions or {}) do
                local b = s.bags[inf.id]
                if b then
                    seen[inf.id] = true
                    local f = fillOf(inf)
                    if f ~= b.f then b.f = f changed = true end
                end
            end
            for id, b in pairs(s.bags) do
                if not seen[id] then
                    if b.done then
                        -- an empty bag keeps hanging for a while, then the nurse clears it
                        if b.doneAt and now - b.doneAt > 600 then s.bags[id] = nil changed = true end
                    elseif b.finished then
                        b.done, b.f, b.doneAt = true, 0, now
                        changed = true
                    else
                        -- stopped by another module or healed: gone from the stand
                        s.bags[id] = nil
                        changed = true
                    end
                end
            end
            -- the patient left the bay / was moved: the stand follows them
            local inBay = p.meta and p.meta.bay or nil
            if s.bay and s.bay ~= inBay then
                s.bay = inBay
                if not inBay then
                    s.at = Core.PatientCoords(p)
                    s.h = 0.0
                end
                changed = true
            elseif not s.bay and inBay then
                s.bay, s.at = inBay, nil
                changed = true
            elseif s.at then
                local pc = Core.PatientCoords(p)
                if pc and #(pc - s.at) > 5.0 then
                    s.at = pc
                    changed = true
                end
            end
            if not next(s.bags) then
                stands[pid] = nil
                push(p)
            elseif changed then
                push(p)
            end
        end
    end
end

NZA.Bus.On('infusion:done', function(p, inf)
    if not p or not inf then return end
    local s = stands[p.pid]
    local b = s and s.bags[inf.id]
    if b then b.finished = true end
    if inf.kind == 'blood' and type(inf.bag) == 'table' and inf.bag.serial and B.SetUsed then B.SetUsed(inf.bag.serial, 2, nil) end
end)

NZA.Bus.On('patient:removed', function(pid)
    stands[pid] = nil
    reactions[pid] = nil
end)

CreateThread(function()
    local last = GetGameTimer()
    local n = 0
    while true do
        Wait(2000)
        local now = GetGameTimer()
        local dt = (now - last) / 1000
        last = now
        n = n + 1
        local ok, err = pcall(reactionTick, dt)
        if not ok then NZA.Warn('blood: reaction tick failed: ' .. tostring(err)) end
        if n % 2 == 0 then
            local ok2, err2 = pcall(syncStands)
            if not ok2 then NZA.Warn('blood: stand sync failed: ' .. tostring(err2)) end
        end
    end
end)

function B.StandOf(pid) return stands[pid] end
