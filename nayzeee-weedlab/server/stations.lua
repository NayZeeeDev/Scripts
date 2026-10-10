--[[
    Equipment actions. The client claims an action, plays it out in first person, then
    finishes it. The server checks the claim again on finish and rejects a finish that came
    faster than the action allows. Nothing here trusts the client for items, counts or results.
]]

Stations = {}

local claims = {}  -- src -> { action, oid, args, t }

local G, PR, PROD = Config.Grow, Config.Processing, Config.Product

local function now() return os.time() end

local function isGrow(obj) return obj and Config.Equipment[obj.type] and Config.Equipment[obj.type].grow end

local function level(P) return Profile.level(P) end

local function give(src, item, count, meta)
    if not Inv.canCarry(src, item, count) then
        TriggerClientEvent('nzwl:notify', src, 'Your pockets are full', 'error')
        return false
    end
    return Inv.add(src, item, count, meta)
end

local function objects(src)
    local P, rec = Profile.get(src), Labs.inside(src)
    if not P or not rec then return nil end
    return P.labs[rec.lab].objects
end

local function tick(src, obj)
    if isGrow(obj) then
        Grow.tick(obj.st, now(), Labs.boostFor(objects(src) or {}, obj))
    end
    return obj.st
end

--- bring every pot in the current lab up to date (before lights / layout change)
function Stations.tickAll(src)
    local list = objects(src)
    if not list then return end
    for _, o in pairs(list) do tick(src, o) end
end

local function save(src, obj)
    Profile.dirty(src)
    Labs.push(src, obj)
end

--[[ ─────────────── actions: validate(src, P, obj, args) -> ok, err, extra / apply(src, P, obj, args, extra) ─────────────── ]]
local A = {}

A.pot_soil = {
    validate = function(src, P, obj, args)
        if not isGrow(obj) then return false end
        if (obj.st.soil or 0) > 0 then return false, 'It already has soil' end
        local s = G.soils[args.item or '']
        if not s or not Inv.has(src, args.item, 1) then return false, 'You need soil' end
        if level(P) < (s.level or 0) then return false, ('Unlocks at level %d'):format(s.level) end
        return true
    end,
    apply = function(src, P, obj, args)
        if not Inv.remove(src, args.item, 1) then return false end
        local s = G.soils[args.item]
        obj.st = { soil = s.uses, soilQ = s.quality, water = 0.0, growth = 0.0, t = now() }
        return true
    end,
}

A.pot_seed = {
    validate = function(src, P, obj, args)
        if not isGrow(obj) then return false end
        tick(src, obj)
        if (obj.st.soil or 0) <= 0 then return false, 'Add soil first' end
        if obj.st.seed then return false, 'Something is already growing' end
        local strain, s = Utils.strainOfSeed(args.item or '')
        if not strain or not Inv.has(src, args.item, 1) then return false, 'You need a seed' end
        if level(P) < (s.level or 0) then return false, ('%s unlocks at level %d'):format(s.label, s.level) end
        return true
    end,
    apply = function(src, P, obj, args)
        if not Inv.remove(src, args.item, 1) then return false end
        tick(src, obj)
        local st = obj.st
        st.seed, st.strain = args.item, (Utils.strainOfSeed(args.item))
        st.growth, st.q, st.yb, st.used = 0.0, 0, 0, {}
        st.rs = math.random(1, 9999)
        return true
    end,
}

A.pot_water = {
    validate = function(src, P, obj)
        if not isGrow(obj) then return false end
        if (obj.st.soil or 0) <= 0 then return false, 'There\'s nothing to water' end
        if not Inv.has(src, Config.WateringCan.item, 1) then return false, 'You need a watering can' end
        if (P.water or 0) < 1 then return false, 'The watering can is empty. Fill it at the tap.' end
        tick(src, obj)
        if obj.st.water > 0.9 then return false, 'It\'s already wet' end
        return true
    end,
    apply = function(src, P, obj)
        tick(src, obj)
        obj.st.water = 1.0
        P.water = math.max(0, (P.water or 0) - 1)
        TriggerClientEvent('nzwl:water', src, P.water)
        return true
    end,
}

local function additive(item)
    local add = G.additives[item]
    return {
        validate = function(src, P, obj)
            if not isGrow(obj) then return false end
            if not Inv.has(src, item, 1) then return false, ('You need %s'):format(add.label) end
            if level(P) < (add.level or 0) then return false, ('Unlocks at level %d'):format(add.level) end
            tick(src, obj)
            if not obj.st.seed or (obj.st.growth or 0) >= 1.0 then return false, 'Use it on a growing plant' end
            if obj.st.used and obj.st.used[item] then return false, ('It already has %s'):format(add.label) end
            return true
        end,
        apply = function(src, P, obj)
            if not Inv.remove(src, item, 1) then return false end
            tick(src, obj)
            local st = obj.st
            st.used = st.used or {}
            st.used[item] = true
            st.q = (st.q or 0) + (add.quality or 0)
            st.yb = (st.yb or 0) + (add.yield or 0)
            if add.growth then st.growth = math.min(1.0, (st.growth or 0) + add.growth) end
            return true
        end,
    }
end
for item, add in pairs(G.additives) do A[add.action] = additive(item) end

A.pot_harvest = {
    validate = function(src, P, obj)
        if not isGrow(obj) then return false end
        tick(src, obj)
        if Grow.stage(obj.st) ~= 4 then return false, 'Not ready yet' end
        if not Inv.has(src, Config.Trimmers, 1) then return false, 'You need trimmers' end
        return true, nil, { count = Grow.harvestCount(obj.st, Config.Equipment[obj.type].yieldMult), rs = obj.st.rs, strain = obj.st.strain }
    end,
    apply = function(src, P, obj)
        local st = obj.st
        local n = Grow.harvestCount(st, Config.Equipment[obj.type].yieldMult)
        local q = Grow.quality(st)
        if not give(src, PROD.loose, n, Products.meta(st.strain, q)) then return false end
        Products.discover(src, st.strain)
        st.seed, st.strain, st.rs, st.q, st.yb, st.used = nil, nil, nil, nil, nil, nil
        st.growth = 0.0
        st.soil = math.max(0, (st.soil or 1) - 1)
        if st.soil == 0 then st.water = 0.0 st.soilQ = nil end
        P.stats.harvests = (P.stats.harvests or 0) + 1
        P.stats.buds = (P.stats.buds or 0) + n
        Profile.addXp(src, Config.Levels.xp.harvest + Config.Levels.xp.perBud * n, 'Harvest')
        Story.progress(src, 'harvest')
        return true
    end,
}

A.tap_fill = {
    point = true,
    validate = function(src, P, _, _, rec)
        local cfg = Labs.cfg(rec)
        if not cfg.tap or not Labs.nearPoint(src, cfg.tap, 2.5) then return false end
        if not Inv.has(src, Config.WateringCan.item, 1) then return false, 'You need a watering can' end
        if (P.water or 0) >= Config.WateringCan.capacity then return false, 'The can is full' end
        return true
    end,
    apply = function(src, P)
        P.water = Config.WateringCan.capacity
        TriggerClientEvent('nzwl:water', src, P.water)
        return true
    end,
}

--[[ packaging: args = { pid, q, kind, n }. finish extra = { done } (packages actually closed and dropped in) ]]
local function packCfg(kind)
    if kind == 'jar' then return 'nzw_jar_empty', PROD.jar, PROD.unitsPerJar end
    return 'nzw_baggie_empty', PROD.baggie, PROD.unitsPerBaggie
end
Stations.packCfg = packCfg

A.pack = {
    validate = function(src, P, obj, args)
        if obj.type ~= 'packstation' then return false end
        local kind = args.kind == 'jar' and 'jar' or 'baggie'
        local empty, _, per = packCfg(kind)
        local n = math.floor(tonumber(args.n) or 0)
        local q = math.floor(tonumber(args.q) or -1)
        if n < 1 or n > PR.pack.max[kind] or not Products.get(args.pid) then return false end
        if level(P) < Utils.itemLevel(empty) then return false, ('Jars unlock at level %d'):format(Utils.itemLevel(empty)) end
        if not Inv.has(src, empty, n) then return false, 'Not enough packaging' end
        if Products.countLoose(src, args.pid, q) < n * per then return false, 'Not enough product' end
        return true, nil, { per = per, bud = Products.bud(args.pid) }
    end,
    minTime = function(args, extra)
        local done = math.floor(tonumber(extra and extra.done) or 0)
        return Config.Actions.pack.minSeconds + math.max(0, done - 1) * PR.pack.secondsPer
    end,
    apply = function(src, P, obj, args, extra)
        local kind = args.kind == 'jar' and 'jar' or 'baggie'
        local empty, out, per = packCfg(kind)
        local done = Utils.clamp(math.floor(tonumber(extra and extra.done) or 0), 0, math.floor(args.n))
        if done < 1 then return false end
        local q = math.floor(args.q)
        if not Products.takeLoose(src, args.pid, q, done * per) then return false end
        if not Inv.remove(src, empty, done) then
            Inv.add(src, PROD.loose, done * per, Products.meta(args.pid, q))
            return false
        end
        Inv.add(src, out, done, Products.meta(args.pid, q, per))
        P.stats.packaged = (P.stats.packaged or 0) + done
        Profile.addXp(src, Config.Levels.xp.pack * done, 'Packaging')
        Story.progress(src, 'pack')
        return true, done
    end,
}

--[[ drying rack: hang n loose units, one per clip ]]
local function freeSlots(obj)
    return #Config.Equipment.dryrack.slots - #(obj.st.slots or {})
end

A.dry_hang = {
    validate = function(src, P, obj, args)
        if obj.type ~= 'dryrack' then return false end
        local n, q = math.floor(tonumber(args.n) or 0), math.floor(tonumber(args.q) or -1)
        if n < 1 or n > freeSlots(obj) then return false, 'Not enough room on the rack' end
        if not Products.get(args.pid) then return false end
        if q >= PR.dry.max then return false, 'It can\'t get any better' end
        if Products.countLoose(src, args.pid, q) < n then return false, 'Not enough weed' end
        return true, nil, { bud = Products.bud(args.pid), first = #(obj.st.slots or {}) + 1 }
    end,
    apply = function(src, P, obj, args)
        local n, q = math.floor(args.n), math.floor(args.q)
        if not Products.takeLoose(src, args.pid, q, n) then return false end
        obj.st.slots = obj.st.slots or {}
        for _ = 1, n do
            obj.st.slots[#obj.st.slots + 1] = { pid = args.pid, q = q, bud = Products.bud(args.pid), done = now() + PR.dry.minutes * 60 }
        end
        return true
    end,
}

--[[ mixing: n loose units + n of one ingredient -> n units of the new product ]]
A.mix = {
    validate = function(src, P, obj, args)
        if obj.type ~= 'mixstation' then return false end
        local n, q = math.floor(tonumber(args.n) or 0), math.floor(tonumber(args.q) or -1)
        local p, ing = Products.get(args.pid), Config.Ingredients[args.ingredient or '']
        if not p or not ing or n < 1 or n > Config.Mixing.maxBatch then return false end
        if level(P) < (ing.level or 0) then return false, ('%s unlocks at level %d'):format(ing.label, ing.level) end
        if not Inv.has(src, args.ingredient, n) then return false, 'Not enough ' .. ing.label end
        if Products.countLoose(src, args.pid, q) < n then return false, 'Not enough product' end
        return true, nil, { bud = Products.bud(args.pid), prop = ing.prop }
    end,
    apply = function(src, P, obj, args)
        local n, q = math.floor(args.n), math.floor(args.q)
        local p = Products.get(args.pid)
        local effects = Mix.apply(p.effects, args.ingredient)
        if not Products.takeLoose(src, args.pid, q, n) then return false end
        if not Inv.remove(src, args.ingredient, n) then
            Inv.add(src, PROD.loose, n, Products.meta(args.pid, q))
            return false
        end
        local newPid, first = Products.resolve(p.base, effects, Profile.identifier(src))
        Inv.add(src, PROD.loose, n, Products.meta(newPid, q))
        P.stats.mixed = (P.stats.mixed or 0) + n
        local xp = Config.Levels.xp.mixUnit * n
        if Products.discover(src, newPid) then xp = xp + Config.Levels.xp.mix end
        Profile.addXp(src, xp, 'Mixing')
        return true, { product = Products.view(newPid), first = first }
    end,
}

--[[ brick press: unitsPerBrick loose units of one product + quality -> a brick ]]
A.press = {
    validate = function(src, P, obj, args)
        if obj.type ~= 'brickpress' then return false end
        local q = math.floor(tonumber(args.q) or -1)
        if not Products.get(args.pid) then return false end
        if Products.countLoose(src, args.pid, q) < PROD.unitsPerBrick then return false, ('You need %d units'):format(PROD.unitsPerBrick) end
        return true, nil, { bud = Products.bud(args.pid) }
    end,
    apply = function(src, P, obj, args)
        local q = math.floor(args.q)
        if not Products.takeLoose(src, args.pid, q, PROD.unitsPerBrick) then return false end
        Inv.add(src, PROD.brick, 1, Products.meta(args.pid, q, PROD.unitsPerBrick))
        P.stats.bricks = (P.stats.bricks or 0) + 1
        Profile.addXp(src, Config.Levels.xp.brick, 'Brick')
        return true
    end,
}

Stations.actions = A

--[[ ─────────────── claim / finish / cancel ─────────────── ]]

Guard.callback('nzwl:st:claim', function(src, action, oid, args)
    local P = Profile.get(src)
    local def, cfg = A[action], Config.Actions[action]
    local rec = Labs.inside(src)
    if not P or not def or not cfg or not rec then return false end
    args = type(args) == 'table' and args or {}
    local obj
    if not def.point then
        obj = Labs.obj(src, oid)
        if not obj then return false end
    end
    local ok, err, extra = def.validate(src, P, obj, args, rec)
    if not ok then return false, err end
    claims[src] = { action = action, oid = oid, args = args, t = GetGameTimer(), lab = rec.lab }
    return true, extra
end)

Guard.callback('nzwl:st:finish', function(src, extra)
    local c = claims[src]
    claims[src] = nil
    local P = Profile.get(src)
    if not c or not P then return false end
    local def, cfg = A[c.action], Config.Actions[c.action]
    local rec = Labs.inside(src)
    if not rec or rec.lab ~= c.lab then return false end
    extra = type(extra) == 'table' and extra or {}
    local minTime = def.minTime and def.minTime(c.args, extra) or cfg.minSeconds or 1
    if GetGameTimer() - c.t < minTime * 1000 then
        Guard.flag(src, ('finished %s too fast'):format(c.action))
        return false
    end
    local obj
    if not def.point then
        obj = Labs.obj(src, c.oid)
        if not obj then return false end
    end
    local ok, err = def.validate(src, P, obj, c.args, rec)
    if not ok then return false, err end
    local applied, result = def.apply(src, P, obj, c.args, extra, rec)
    if not applied then return false end
    Profile.dirty(src)
    if obj then save(src, obj) end
    return true, result
end)

Guard.callback('nzwl:st:cancel', function(src)
    claims[src] = nil
    return true
end)

--[[ ─────────────── panels (no first person part) ─────────────── ]]

Guard.callback('nzwl:panel:open', function(src, oid)
    local obj, P = Labs.obj(src, oid)
    if not obj then return false end
    local stacks = Products.loose(src)
    local t = obj.type
    if t == 'packstation' then
        return {
            stacks = stacks, baggies = Inv.count(src, 'nzw_baggie_empty'), jars = Inv.count(src, 'nzw_jar_empty'),
            jarLevel = Utils.itemLevel('nzw_jar_empty'), level = level(P), max = PR.pack.max,
            per = { baggie = PROD.unitsPerBaggie, jar = PROD.unitsPerJar },
        }
    elseif t == 'dryrack' then
        local slots = {}
        for i, s in ipairs(obj.st.slots or {}) do slots[i] = { pid = s.pid, q = s.q, done = s.done, name = Products.label(s.pid) } end
        return { stacks = stacks, slots = slots, capacity = #Config.Equipment.dryrack.slots, now = now(), max = PR.dry.max, minutes = PR.dry.minutes }
    elseif t == 'mixstation' then
        local ings = {}
        local lvl = level(P)
        for item, ing in pairs(Config.Ingredients) do
            local n = Inv.count(src, item)
            if n > 0 then ings[#ings + 1] = { item = item, label = ing.label, effect = ing.effect, n = n, locked = lvl < (ing.level or 0), level = ing.level } end
        end
        table.sort(ings, function(a, b) return a.label < b.label end)
        return { stacks = stacks, ingredients = ings, max = Config.Mixing.maxBatch }
    elseif t == 'brickpress' then
        return { stacks = stacks, units = PROD.unitsPerBrick }
    end
    return false
end)

-- drying rack: take every dry unit off (or one slot early, without the bonus)
Guard.callback('nzwl:dry:collect', function(src, oid, idx)
    local obj, P = Labs.obj(src, oid)
    if not obj or obj.type ~= 'dryrack' then return false end
    local slots = obj.st.slots or {}
    local take = {}
    if idx then
        idx = math.floor(tonumber(idx) or 0)
        if not slots[idx] then return false end
        take[1] = idx
    else
        for i, s in ipairs(slots) do if s.done <= now() then take[#take + 1] = i end end
        if #take == 0 then return false, 'Nothing is dry yet' end
    end
    -- group by result so the inventory gets one stack per product + quality
    local out, dried = {}, 0
    for _, i in ipairs(take) do
        local s = slots[i]
        local ready = s.done <= now()
        local q = ready and math.min(PR.dry.max, s.q + PR.dry.quality) or s.q
        local key = s.pid .. '|' .. q
        out[key] = out[key] or { pid = s.pid, q = q, n = 0 }
        out[key].n = out[key].n + 1
        if ready then dried = dried + 1 end
    end
    local total = 0
    for _, g in pairs(out) do total = total + g.n end
    if not Inv.canCarry(src, PROD.loose, total) then return false, 'Your pockets are full' end
    table.sort(take, function(a, b) return a > b end)
    for _, i in ipairs(take) do table.remove(slots, i) end
    for _, g in pairs(out) do Inv.add(src, PROD.loose, g.n, Products.meta(g.pid, g.q)) end
    if dried > 0 then
        P.stats.dried = (P.stats.dried or 0) + dried
        Profile.addXp(src, Config.Levels.xp.dry * dried, 'Drying')
    end
    save(src, obj)
    return true, total
end)

AddEventHandler('nzwl:server:unload', function(src) claims[src] = nil end)

-- how many of each (known) item the player carries, for the client's choice lists
Guard.callback('nzwl:inv:counts', function(src, items)
    local out = {}
    if type(items) ~= 'table' or #items > 40 then return out end
    for _, item in ipairs(items) do
        if type(item) == 'string' and Config.Items[item] then out[item] = Inv.count(src, item) end
    end
    return out
end)
