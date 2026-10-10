--[[
    Equipment actions. Two kinds:

    * first person actions (Config.Actions): the client claims the action, plays the
      steps, then finishes. The server checks the claim again on finish, and rejects
      a finish that came faster than `minSeconds`.
    * panels (packaging, drying rack, mixing, oven loading): instant server calls.

    Nothing here trusts the client for items, counts or results.
]]

Stations = {}

local claims = {}  -- src -> { action, oid, args, t }

local G, PR = Config.Grow, Config.Processing

local function now() return os.time() end

--[[ ─────────────── helpers ─────────────── ]]

local function potLike(obj)
    return obj.type == 'pot' or obj.type == 'tent'
end
Stations.potLike = potLike

local function boostFor(P, obj)
    local own = Config.Stations[obj.type] and Config.Stations[obj.type].boost
    if own then return own end
    for _, o in pairs(P.objects) do
        if o.type == 'light' then
            local dx, dy = o.x - obj.x, o.y - obj.y
            if dx * dx + dy * dy <= G.lightRadius * G.lightRadius then return G.lightBoost end
        end
    end
    return 1.0
end

local function tick(P, obj)
    if potLike(obj) or obj.type == 'bed' then Grow.tick(obj.st, now(), boostFor(P, obj)) end
    return obj.st
end

function Stations.tickAll(src)
    local P = Profile.get(src)
    if not P then return end
    for _, o in pairs(P.objects) do tick(P, o) end
end

local function firstOf(src, list, wanted)
    if wanted and list[wanted] and Inv.has(src, wanted, 1) then return wanted end
    if wanted then return nil end
    for item in pairs(list) do
        if Inv.has(src, item, 1) then return item end
    end
end

local function hasAll(src, needs)
    for item, n in pairs(needs) do
        if not Inv.has(src, item, n) then return false, Utils.itemLabel(item) end
    end
    return true
end

local function removeAll(src, needs)
    for item, n in pairs(needs) do
        if not Inv.remove(src, item, n) then return false end
    end
    return true
end

local function give(src, item, count, meta)
    if not Inv.canCarry(src, item, count) then
        TriggerClientEvent('nzde:notify', src, 'Your pockets are full', 'error')
        return false
    end
    return Inv.add(src, item, count, meta)
end

local function save(src, obj)
    Profile.dirty(src)
    RV.push(src, obj)
end

local function level(P) return Profile.level(P) end

--[[ ─────────────── first person actions ───────────────
    validate(src, P, obj, args) -> ok, err, extra     apply(src, P, obj, args) ]]
local A = {}

A.pot_soil = {
    validate = function(src, P, obj, args)
        if not potLike(obj) then return false end
        if (obj.st.soil or 0) > 0 then return false, 'The pot already has soil' end
        if not firstOf(src, G.soils, args.item) then return false, 'You need soil' end
        return true
    end,
    apply = function(src, P, obj, args)
        local item = firstOf(src, G.soils, args.item)
        if not item or not Inv.remove(src, item, 1) then return false end
        local s = G.soils[item]
        obj.st = { soil = s.uses, soilQ = s.quality, water = 0.0, growth = 0.0, t = now() }
        Quests.progress(src, 'pot:soil')
        return true
    end,
}

A.pot_seed = {
    validate = function(src, P, obj, args)
        if not potLike(obj) then return false end
        tick(P, obj)
        if (obj.st.soil or 0) <= 0 then return false, 'Add soil first' end
        if obj.st.seed then return false, 'Something is already growing' end
        local item = firstOf(src, G.seeds, args.item)
        if not item then return false, 'You need a seed' end
        if level(P) < (G.seeds[item].unlock or 1) then return false, 'You can\'t grow that yet' end
        return true
    end,
    apply = function(src, P, obj, args)
        local item = firstOf(src, G.seeds, args.item)
        if not item or not Inv.remove(src, item, 1) then return false end
        local seed = G.seeds[item]
        tick(P, obj)
        obj.st.seed = item
        obj.st.crop = seed.crop
        obj.st.product = seed.product
        obj.st.growth = 0.0
        obj.st.rs = math.random(1, 9999)
        Quests.progress(src, 'pot:seed')
        return true
    end,
}

local function waterValidate(kind)
    return function(src, P, obj)
        if (kind == 'pot' and not potLike(obj)) or (kind ~= 'pot' and obj.type ~= kind) then return false end
        if (obj.st.soil or 0) <= 0 then return false, 'There\'s nothing to water' end
        if not Inv.has(src, 'nz_wateringcan', 1) then return false, 'You need a watering can' end
        if (P.water or 0) < 1 then return false, 'The watering can is empty. Fill it at the tap.' end
        tick(P, obj)
        if obj.st.water > 0.9 then return false, 'It\'s already wet' end
        return true
    end
end

local function waterApply(quest)
    return function(src, P, obj)
        tick(P, obj)
        obj.st.water = 1.0
        P.water = math.max(0, (P.water or 0) - 1)
        TriggerClientEvent('nzde:water', src, P.water)
        if quest then Quests.progress(src, quest) end
        return true
    end
end

A.pot_water = { validate = waterValidate('pot'), apply = waterApply('pot:water') }
A.bed_mist = { validate = waterValidate('bed'), apply = waterApply(nil) }

A.pot_additive = {
    validate = function(src, P, obj, args)
        if not potLike(obj) then return false end
        local item = args.item
        local add = G.additives[item or '']
        if not add or not Inv.has(src, item, 1) then return false, 'You need that additive' end
        tick(P, obj)
        if not obj.st.seed or obj.st.growth >= 1.0 then return false, 'Use it on a growing plant' end
        if add.quality and (obj.st.q or 0) >= 1 then return false, 'Already fertilized' end
        if add.yield and (obj.st.yb or 0) > 0 then return false, 'Already has PGR' end
        return true
    end,
    apply = function(src, P, obj, args)
        local add = G.additives[args.item]
        if not Inv.remove(src, args.item, 1) then return false end
        tick(P, obj)
        if add.quality then obj.st.q = (obj.st.q or 0) + add.quality end
        if add.yield then obj.st.yb = (obj.st.yb or 0) + add.yield end
        if add.growth then obj.st.growth = math.min(1.0, obj.st.growth + add.growth) end
        return true
    end,
}

A.pot_harvest = {
    validate = function(src, P, obj)
        if not potLike(obj) then return false end
        tick(P, obj)
        if Grow.stage(obj.st) ~= 4 then return false, 'Not ready yet' end
        if not Inv.has(src, 'nz_trimmers', 1) then return false, 'You need trimmers' end
        return true, nil, { count = Grow.harvestCount(obj.st, obj.st.rs) }
    end,
    apply = function(src, P, obj)
        local st = obj.st
        local n = Grow.harvestCount(st, st.rs)
        local ok
        if st.crop == 'coca' then
            ok = give(src, G.coca.item, n)
            if ok then Quests.progress(src, 'grow:coca') end
        else
            ok = give(src, G.weed.item, n, Products.meta(st.product, Grow.quality(st)))
            if ok then Products.discover(src, st.product) end
        end
        if not ok then return false end
        st.seed, st.crop, st.product, st.rs, st.q, st.yb = nil, nil, nil, nil, nil, nil
        st.growth = 0.0
        st.soil = math.max(0, (st.soil or 1) - 1)
        if st.soil == 0 then st.water = 0.0 st.soilQ = nil end
        P.stats.harvests = P.stats.harvests + 1
        Quests.progress(src, 'pot:harvest')
        Profile.addXp(src, Config.Ranks.xp.harvest, 'Harvest')
        return true
    end,
}

--[[ packaging: args = { item, pid, q, n } ]]
local function packAction(kind)
    local per = kind == 'jar' and Config.Deals.unitsPerJar or Config.Deals.unitsPerBaggie
    local empty = kind == 'jar' and 'nz_jar_empty' or 'nz_baggie_empty'
    local out = kind == 'jar' and Config.ProductItems.jar or Config.ProductItems.baggie
    local function check(src, P, obj, args)
        if obj.type ~= 'packer' then return false end
        local n = math.floor(tonumber(args.n) or 0)
        local pid, item = args.pid, args.item
        if n < 1 or n > PR.pack.max or not Products.get(pid) or Products.looseItem(pid) ~= item then return false end
        if kind == 'jar' and level(P) < 5 then return false, 'Jars unlock at ' .. Utils.rankLabel(5) end
        if not Inv.has(src, empty, n) then return false, 'Not enough packaging' end
        local q = math.floor(tonumber(args.q) or 2)
        local have = 0
        for _, sl in ipairs(Inv.slots(src, item)) do
            local mp = sl.meta and sl.meta.pid
            if (mp == pid or (not mp and pid == Config.ProductItems.defaultPid[item])) and (sl.meta and sl.meta.quality or 2) == q then have = have + sl.count end
        end
        if have < n * per then return false, 'Not enough product' end
        return true
    end
    return {
        minTime = function(args) return (Config.Actions['pack_' .. kind].minSeconds or 3) + (math.floor(tonumber(args.n) or 1) - 1) * PR.pack.seconds * 0.8 end,
        validate = check,
        apply = function(src, P, obj, args)
            local n, q = math.floor(args.n), math.floor(tonumber(args.q) or 2)
            if not Stations.takeLoose(src, args.item, args.pid, q, n * per) then return false end
            if not Inv.remove(src, empty, n) then
                Inv.add(src, args.item, n * per, Products.meta(args.pid, q))
                return false
            end
            Inv.add(src, out, n, Products.meta(args.pid, q, per))
            Quests.progress(src, 'pack')
            return true
        end,
    }
end

A.pack_baggie = packAction('baggie')
A.pack_jar = packAction('jar')

A.sink_fill = {
    point = true,
    validate = function(src, P, _, _, rec)
        local cfg = RV.interiorCfg(rec.mode)
        if not cfg.sink or not RV.nearPoint(src, cfg.sink, 2.5) then return false end
        if not Inv.has(src, 'nz_wateringcan', 1) then return false, 'You need a watering can' end
        if (P.water or 0) >= Config.WateringCan.capacity then return false, 'The can is full' end
        return true
    end,
    apply = function(src, P)
        P.water = Config.WateringCan.capacity
        TriggerClientEvent('nzde:water', src, P.water)
        return true
    end,
}

local function timedStart(kind, busy, needsFn, minutes, quest)
    return {
        validate = function(src, P, obj)
            if obj.type ~= kind then return false end
            if obj.st.busy then return false, 'It\'s already running' end
            local ok, missing = hasAll(src, needsFn(obj))
            if not ok then return false, ('You need %s'):format(missing) end
            return true
        end,
        apply = function(src, P, obj)
            if not removeAll(src, needsFn(obj)) then return false end
            obj.st = { busy = busy, done = now() + minutes * 60 }
            if quest then Quests.progress(src, quest) end
            return true
        end,
    }
end

A.chem_start = timedStart('chem', 'meth_liquid', function() return PR.chem.needs end, PR.chem.minutes)
A.cauldron_start = timedStart('cauldron', 'base', function() return { nz_coca_dry = PR.cauldron.leaves, nz_gasoline = PR.cauldron.gasoline } end, PR.cauldron.minutes)
A.spawn_start = timedStart('spawn', 'spawn', function() return PR.spawn.needs end, PR.spawn.minutes)

A.oven_load = {
    validate = function(src, P, obj, args)
        if obj.type ~= 'oven' then return false end
        if obj.st.busy then return false, 'The oven is busy' end
        if args.mode == 'coke' then
            if Inv.count(src, PR.oven.coke.input) < 1 then return false, 'You need coca base' end
        elseif Inv.count(src, PR.oven.meth.input) < 1 then
            return false, 'You need liquid meth'
        end
        return true
    end,
    apply = function(src, P, obj, args)
        if args.mode == 'coke' then
            local n = math.min(Inv.count(src, PR.oven.coke.input), PR.oven.coke.max)
            if n < 1 or not Inv.remove(src, PR.oven.coke.input, n) then return false end
            obj.st = { busy = 'coke', n = n, done = now() + PR.oven.minutes * 60 }
        else
            if not Inv.remove(src, PR.oven.meth.input, 1) then return false end
            obj.st = { busy = 'meth', n = PR.oven.meth.output, done = now() + PR.oven.minutes * 60 }
        end
        return true
    end,
}

A.oven_smash = {
    validate = function(src, P, obj)
        if obj.type ~= 'oven' or obj.st.busy ~= 'meth' then return false end
        if obj.st.done > now() then return false, 'Still baking' end
        return true
    end,
    apply = function(src, P, obj)
        if not give(src, Config.ProductItems.loose.meth, obj.st.n, Products.meta('meth', 2)) then return false end
        Products.discover(src, 'meth')
        obj.st = {}
        P.stats.cooks = P.stats.cooks + 1
        Quests.progress(src, 'cook:meth')
        Profile.addXp(src, Config.Ranks.xp.cook, 'Meth batch')
        return true
    end,
}

A.bed_fill = {
    validate = function(src, P, obj)
        if obj.type ~= 'bed' then return false end
        if (obj.st.soil or 0) > 0 then return false, 'The bed is already filled' end
        local ok, missing = hasAll(src, PR.bed.needs)
        if not ok then return false, ('You need %s'):format(missing) end
        return true
    end,
    apply = function(src, P, obj)
        if not removeAll(src, PR.bed.needs) then return false end
        obj.st = { soil = 1, soilQ = 2, seed = 'spawn', crop = 'shroom', product = 'shrooms', growth = 0.0, water = 0.0, t = now(), rs = math.random(1, 9999) }
        return true
    end,
}

A.bed_harvest = {
    validate = function(src, P, obj)
        if obj.type ~= 'bed' then return false end
        tick(P, obj)
        if Grow.stage(obj.st) ~= 4 then return false, 'Not ready yet' end
        return true, nil, { count = Grow.harvestCount(obj.st, obj.st.rs) }
    end,
    apply = function(src, P, obj)
        local st = obj.st
        local n = Grow.harvestCount(st, st.rs)
        if not give(src, G.shroom.item, n, Products.meta('shrooms', Grow.quality(st))) then return false end
        Products.discover(src, 'shrooms')
        obj.st = { soil = 0, water = 0.0, growth = 0.0, t = now() }
        P.stats.harvests = P.stats.harvests + 1
        Quests.progress(src, 'grow:shroom')
        Profile.addXp(src, Config.Ranks.xp.cook, 'Mushroom harvest')
        return true
    end,
}

Guard.callback('nzde:st:claim', function(src, action, oid, args)
    local P = Profile.get(src)
    local def, cfg = A[action], Config.Actions[action]
    local rec = RV.inside(src)
    if not P or not def or not cfg or not rec or rec.owner ~= src then return false end
    args = type(args) == 'table' and args or {}
    local obj
    if not def.point then
        obj = P.objects[oid]
        if not obj or not RV.nearObj(src, obj, 3.5) then return false end
    end
    local ok, err, extra = def.validate(src, P, obj, args, rec)
    if not ok then return false, err end
    claims[src] = { action = action, oid = oid, args = args, t = GetGameTimer() }
    return true, extra
end)

Guard.callback('nzde:st:finish', function(src)
    local c = claims[src]
    claims[src] = nil
    local P = Profile.get(src)
    if not c or not P then return false end
    local def, cfg = A[c.action], Config.Actions[c.action]
    local rec = RV.inside(src)
    if not rec or rec.owner ~= src then return false end
    local minTime = def.minTime and def.minTime(c.args) or cfg.minSeconds or 1
    if GetGameTimer() - c.t < minTime * 1000 then
        Guard.flag(src, ('finished %s too fast'):format(c.action))
        return false
    end
    local obj
    if not def.point then
        obj = P.objects[c.oid]
        if not obj or not RV.nearObj(src, obj, 3.5) then return false end
    end
    local ok, err = def.validate(src, P, obj, c.args, rec)
    if not ok then return false, err end
    if not def.apply(src, P, obj, c.args, rec) then return false end
    Profile.dirty(src)
    if obj then RV.push(src, obj) end
    return true
end)

Guard.callback('nzde:st:cancel', function(src)
    claims[src] = nil
    return true
end)

--[[ ─────────────── timed collects (no first person part) ─────────────── ]]
local COLLECT = {
    chem = function(src, P, obj)
        if not give(src, PR.chem.output, 1) then return false end
        Quests.progress(src, 'cook:meth_liquid')
        return true
    end,
    cauldron = function(src, P, obj)
        if not give(src, 'nz_coca_base', PR.cauldron.output) then return false end
        Quests.progress(src, 'cook:base')
        Profile.addXp(src, Config.Ranks.xp.cook, 'Coca base')
        return true
    end,
    spawn = function(src, P, obj)
        if not give(src, PR.spawn.output, 1) then return false end
        Quests.progress(src, 'cook:spawn')
        return true
    end,
    oven = function(src, P, obj)
        if obj.st.busy ~= 'coke' then return false end
        if not give(src, Config.ProductItems.loose.coke, obj.st.n, Products.meta('cocaine', 2)) then return false end
        Products.discover(src, 'cocaine')
        P.stats.cooks = P.stats.cooks + 1
        Quests.progress(src, 'cook:coke')
        Profile.addXp(src, Config.Ranks.xp.cook, 'Cocaine batch')
        return true
    end,
}

Guard.callback('nzde:st:collect', function(src, oid)
    local P = Profile.get(src)
    local obj = P and P.objects[oid]
    if not obj or not RV.nearObj(src, obj, 3.5) then return false end
    local fn = COLLECT[obj.type]
    if not fn or not obj.st.busy then return false end
    if obj.st.done > now() then return false, 'Not done yet' end
    if not fn(src, P, obj) then return false end
    obj.st = {}
    save(src, obj)
    return true
end)

--[[ ─────────────── panels ─────────────── ]]

--- loose product stacks: { { item, pid, q, n, name, kind } }
local function looseStacks(src, kinds)
    local agg, out = {}, {}
    for kind, item in pairs(Config.ProductItems.loose) do
        if not kinds or kinds[kind] then
            for _, s in ipairs(Inv.slots(src, item)) do
                local pid = s.meta and s.meta.pid or Config.ProductItems.defaultPid[item]
                if Products.get(pid) then
                    local q = s.meta and s.meta.quality or 2
                    local key = item .. '|' .. pid .. '|' .. q
                    if not agg[key] then
                        agg[key] = { item = item, pid = pid, q = q, n = 0, name = Products.label(pid), kind = kind, effects = Products.get(pid).effects, base = Products.get(pid).base }
                        out[#out + 1] = agg[key]
                    end
                    agg[key].n = agg[key].n + s.count
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function takeLoose(src, item, pid, q, n)
    return Inv.removeMatching(src, item, n, function(m)
        local mp = m.pid or Config.ProductItems.defaultPid[item]
        return mp == pid and (m.quality or 2) == q
    end)
end
Stations.takeLoose = takeLoose

local function panelFor(src, P, obj)
    local t = obj.type
    if t == 'packer' then
        return { type = t, stacks = looseStacks(src), baggies = Inv.count(src, 'nz_baggie_empty'), jars = Inv.count(src, 'nz_jar_empty') }
    elseif t == 'mixer' then
        local ings = {}
        for item, ing in pairs(Config.Ingredients) do
            local n = Inv.count(src, item)
            if n > 0 then ings[#ings + 1] = { item = item, label = ing.label, effect = ing.effect, n = n } end
        end
        table.sort(ings, function(a, b) return a.label < b.label end)
        return { type = t, stacks = looseStacks(src), ingredients = ings, max = Config.Mixing.maxBatch }
    elseif t == 'rack' then
        return { type = t, stacks = looseStacks(src, { weed = true }), leaves = Inv.count(src, 'nz_coca_leaf'), slots = obj.st.slots or {}, capacity = PR.rack.capacity, now = now() }
    end
    return nil
end

Guard.callback('nzde:panel:open', function(src, oid)
    local P = Profile.get(src)
    local obj = P and P.objects[oid]
    if not obj or not RV.nearObj(src, obj, 3.5) then return false end
    return panelFor(src, P, obj)
end)

-- mixing: n loose units + n of one ingredient -> n units of the resulting product
Guard.callback('nzde:panel:mix', function(src, oid, item, pid, q, ingredient, n)
    local P = Profile.get(src)
    local obj = P and P.objects[oid]
    if not obj or obj.type ~= 'mixer' or not RV.nearObj(src, obj, 3.5) then return false end
    n = math.floor(tonumber(n) or 0)
    local p = Products.get(pid)
    if not p or n < 1 or n > Config.Mixing.maxBatch or not Config.Ingredients[ingredient] or Products.looseItem(pid) ~= item then return false end
    if not Guard.rate(src, 'mix', Config.Mixing.seconds * 1000 - 500) then return false, 'The mixer is still running' end
    local effects = Mix.apply(p.effects, ingredient)
    if not Inv.has(src, ingredient, n) then return false, 'Not enough ' .. Config.Ingredients[ingredient].label end
    if not takeLoose(src, item, pid, q, n) then return false, 'Not enough product' end
    if not Inv.remove(src, ingredient, n) then
        Inv.add(src, item, n, Products.meta(pid, q))
        return false
    end
    local newPid, newToServer = Products.resolve(p.base, effects, Profile.identifier(src))
    Inv.add(src, item, n, Products.meta(newPid, q))
    if Products.discover(src, newPid) then
        Profile.addXp(src, Config.Ranks.xp.mix, 'New product')
        Quests.progress(src, 'mix')
    end
    return true, { product = Products.view(newPid), first = newToServer, panel = panelFor(src, P, obj) }
end)

-- drying rack
Guard.callback('nzde:panel:rackAdd', function(src, oid, what, n)
    local P = Profile.get(src)
    local obj = P and P.objects[oid]
    if not obj or obj.type ~= 'rack' or not RV.nearObj(src, obj, 3.5) then return false end
    n = math.floor(tonumber(n) or 0)
    obj.st.slots = obj.st.slots or {}
    local used = 0
    for _, s in ipairs(obj.st.slots) do used = used + s.n end
    if n < 1 or used + n > PR.rack.capacity then return false, 'Not enough room on the rack' end
    local slot
    if what == 'coca' then
        if not Inv.remove(src, 'nz_coca_leaf', n) then return false, 'Not enough coca leaves' end
        slot = { kind = 'coca', n = n, done = now() + PR.rack.minutes * 60 }
    else
        if type(what) ~= 'table' or not Products.get(what.pid) or Products.kind(what.pid) ~= 'weed' then return false end
        local q = math.floor(tonumber(what.q) or 2)
        if q >= 4 then return false, 'It can\'t get any better' end
        if not takeLoose(src, 'nz_weed', what.pid, q, n) then return false, 'Not enough weed' end
        slot = { kind = 'weed', pid = what.pid, q = q, n = n, done = now() + PR.rack.minutes * 60 }
    end
    obj.st.slots[#obj.st.slots + 1] = slot
    save(src, obj)
    return true, panelFor(src, P, obj)
end)

Guard.callback('nzde:panel:rackTake', function(src, oid, idx)
    local P = Profile.get(src)
    local obj = P and P.objects[oid]
    if not obj or obj.type ~= 'rack' or not RV.nearObj(src, obj, 3.5) then return false end
    local slot = obj.st.slots and obj.st.slots[tonumber(idx) or 0]
    if not slot then return false end
    local ready = slot.done <= now()
    local ok
    if slot.kind == 'coca' then
        ok = give(src, ready and 'nz_coca_dry' or 'nz_coca_leaf', slot.n)
        if ok and ready then Quests.progress(src, 'rack:coca') end
    else
        ok = give(src, 'nz_weed', slot.n, Products.meta(slot.pid, ready and math.min(4, slot.q + 1) or slot.q))
    end
    if not ok then return false end
    table.remove(obj.st.slots, idx)
    save(src, obj)
    return true, panelFor(src, P, obj)
end)

AddEventHandler('nzde:server:unload', function(src) claims[src] = nil end)
