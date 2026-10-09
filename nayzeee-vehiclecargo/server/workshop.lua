-----------------------------------------------------------------
-- Design bay: validate builds, charge, rescore, raise rarity
-----------------------------------------------------------------
local W = Config.Workshop

local validIds = {}
local function idSet(name, list, at)
    local set = {}
    for _, v in ipairs(list) do set[v[at] or v.id] = true end
    validIds[name] = set
end
idSet('finish', W.Finishes, 'id')
idSet('pearl', W.Pearls, 1)
idSet('wheel', W.WheelTypes, 1)
idSet('tint', W.Tints, 1)
idSet('xenon', W.XenonColors, 1)
idSet('plate', W.Plates, 1)
idSet('rim', W.RimColors, 1)

local function int(v, lo, hi)
    v = math.floor(tonumber(v) or lo)
    return Cargo.Clamp(v, lo, hi)
end

local function sanitizePart(p, v)
    if v == nil then return nil end
    if p.type == 'level' then
        local n = int(v, 0, p.max)
        return n > 0 and n or nil
    elseif p.type == 'toggle' then
        return v == true or nil
    elseif p.type == 'part' or p.type == 'livery' then
        local n = int(v, -1, 80)
        return n >= 0 and n or nil
    elseif p.type == 'paint' then
        if type(v) ~= 'table' then return nil end
        local f = tonumber(v.finish) or 0
        local pearl = tonumber(v.pearl) or 0
        return {
            p = int(v.p, 1, #W.Colors), s = int(v.s, 1, #W.Colors),
            finish = validIds.finish[f] and f or 0, pearl = validIds.pearl[pearl] and pearl or 0,
        }
    elseif p.type == 'wheels' then
        if type(v) ~= 'table' then return nil end
        local t, c = tonumber(v.type), tonumber(v.color)
        local color = (c and validIds.rim[c]) and c or nil
        if t and validIds.wheel[t] then return { type = t, index = int(v.index, 0, 250), custom = v.custom == true, color = color } end
        return color and { color = color } or nil
    elseif p.type == 'tint' then
        local n = tonumber(v)
        return (n and validIds.tint[n] and n ~= 0) and n or nil
    elseif p.type == 'plate' then
        local n = tonumber(v)
        return (n and validIds.plate[n] and n ~= 0) and n or nil
    elseif p.type == 'xenon' then
        local n = tonumber(v)
        return (n and validIds.xenon[n]) and n or nil
    elseif p.type == 'neon' then
        return int(v, 1, #W.NeonColors)
    end
end

local function context(src, stockId, perm)
    local st = Server.Get(src)
    if not st or not st.inside or not Server.Can(src, st.inside, perm or 'design') then return nil end
    local w = DB.Warehouses[st.inside]
    local item = DB.GetStockItem(tonumber(stockId))
    if not item or item.warehouse ~= w.id or item.status ~= 'stored' then return nil end
    return st, w, item
end

lib.callback.register('nz_cargo:workshop:open', function(src, stockId)
    local st, w, item = context(src, stockId)
    if not st then return nil end
    local lvl = Cargo.Upgrade('workshop', w.upgrades.workshop)
    if not lvl or #lvl.categories == 0 then Server.Notify(src, L('ws_locked'), 'error') return nil end
    return {
        stock = { id = item.id, model = item.model, label = item.label, base_rarity = item.base_rarity, rarity = item.rarity,
                  value = item.value, condition = item.condition, build = item.build, score = item.score, props = item.props, plate = item.plate },
        level = w.upgrades.workshop, levelName = lvl.name, groups = lvl.categories, maxRarityGain = lvl.maxRarityGain,
        contacts = w.upgrades.contacts, cash = Bridge.GetMoney(src, Config.Accounts.Purchase),
        mode = Config.Workshop.Mode,
        clean = (tonumber(item.props and item.props.dirtLevel) or 0) <= 1.0,
    }
end)

-- Wash & clean: the dirt level is saved on the car
lib.callback.register('nz_cargo:workshop:wash', Server.Once('stock', function(src, stockId)
    local st, w, item = context(src, stockId, 'wash')
    if not st then Server.Notify(src, L('no_perm'), 'error') return false end
    if not Server.Charge(src, W.WashPrice or 0, 'vehiclecargo-wash') then return false end
    item.props = type(item.props) == 'table' and item.props or {}
    item.props.dirtLevel = 0.0
    DB.UpdateStock(item)
    Server.Notify(src, L('ws_washed'), 'success')
    Warehouse.Refresh(w.id)
    return { ok = true, cash = Bridge.GetMoney(src, Config.Accounts.Purchase) }
end))

lib.callback.register('nz_cargo:workshop:buy', Server.Once('stock', function(src, stockId, build, props)
    local st, w, item = context(src, stockId)
    if not st or type(build) ~= 'table' then return false end
    local allowed = Cargo.AllowedGroups(w.upgrades.workshop)

    local old = item.build or {}
    local new = {}
    for _, p in ipairs(W.Parts) do
        local v = sanitizePart(p, build[p.id])
        if allowed[p.group] then
            new[p.id] = v
        else
            new[p.id] = old[p.id] -- locked groups can't change
        end
    end

    local cost = Cargo.BuildCost(old, new, item.base_rarity)
    if cost > 0 and not Server.Charge(src, cost, 'vehiclecargo-design') then return false end

    local lvl = Cargo.Upgrade('workshop', w.upgrades.workshop)
    local score = Cargo.ScoreBuild(new, w.upgrades.workshop)
    local before = item.rarity
    item.build = new
    item.score = score
    item.rarity = Cargo.RarityFromScore(item.base_rarity, score, lvl.maxRarityGain)
    item.offers, item.offers_at = nil, 0  -- buyers re-bid on the new build
    if type(props) == 'table' then
        props.plate = item.plate
        item.props = props
    end
    DB.UpdateStock(item)

    if cost > 0 then DB.Log(st.identifier, w.id, 'design', item.label, item.rarity, -cost, { score = score }) end
    Server.Notify(src, L('ws_saved', score), 'success')
    if item.rarity ~= before and Cargo.Rarity[item.rarity].index > Cargo.Rarity[before].index then
        Server.Notify(src, L('ws_rarity', Cargo.Rarity[item.rarity].label), 'success', 'Rarity Up')
        Server.Webhook('Rarity raised', { Player = st.name, Vehicle = item.label, From = before, To = item.rarity, Score = score })
    end
    Warehouse.Refresh(w.id)
    return {
        stock = { id = item.id, rarity = item.rarity, score = score, build = new, condition = item.condition },
        cost = cost, cash = Bridge.GetMoney(src, Config.Accounts.Purchase),
        baseValue = Cargo.BaseValue(item, w.upgrades.contacts),
    }
end))

-----------------------------------------------------------------
-- External mechanic: another resource did the work (and charged for
-- it). We read the build out of the props and rescore the car.
-- Parts from groups the Design Bay hasn't unlocked don't score.
-----------------------------------------------------------------
lib.callback.register('nz_cargo:workshop:external', function(src, stockId, props)
    if Config.Workshop.Mode == 'builtin' then return false end
    local st, w, item = context(src, stockId)
    if not st or type(props) ~= 'table' then return false end
    local allowed = Cargo.AllowedGroups(w.upgrades.workshop)
    local raw = Cargo.PropsToBuild(props)
    local build = {}
    for _, p in ipairs(W.Parts) do
        if allowed[p.group] then build[p.id] = sanitizePart(p, raw[p.id]) end
    end
    local lvl = Cargo.Upgrade('workshop', w.upgrades.workshop)
    local before = item.rarity
    local score = Cargo.ScoreBuild(build, w.upgrades.workshop)
    item.build, item.score = build, score
    item.rarity = Cargo.RarityFromScore(item.base_rarity, score, lvl.maxRarityGain)
    item.offers, item.offers_at = nil, 0
    props.plate = item.plate
    item.props = props
    DB.UpdateStock(item)
    Server.Notify(src, L('ws_saved', score), 'success')
    if Cargo.Rarity[item.rarity].index > Cargo.Rarity[before].index then
        Server.Notify(src, L('ws_rarity', Cargo.Rarity[item.rarity].label), 'success', 'Rarity Up')
    end
    Warehouse.Refresh(w.id)
    return { score = score, rarity = item.rarity }
end)
