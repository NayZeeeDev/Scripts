--[[ Empire app: one data call, plus small actions. The app re-fetches after each action. ]]

local function productsView(P)
    local out = {}
    for pid, mine in pairs(P.products) do
        local v = Products.view(pid, mine.price)
        if v then out[#out + 1] = v end
    end
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.value > b.value
    end)
    return out
end

local function mapView(P, src)
    local pins = {}
    local function add(kind, label, x, y, extra)
        local p = { kind = kind, label = label, x = x, y = y }
        if extra then for k, v in pairs(extra) do p[k] = v end end
        pins[#pins + 1] = p
    end
    local veh = RV.vehicle(src)
    if veh then
        local c = GetEntityCoords(veh)
        add('rv', 'Your RV', c.x, c.y)
    elseif P.rv.pos then
        add('rv', 'Your RV (last seen)', P.rv.pos.x, P.rv.pos.y)
    end
    if P.story.met then
        local b = Story.bensonSpot(P)
        add('benson', Config.Story.benson.name, b.x, b.y)
    end
    for _, d in ipairs(P.deals) do
        if d.state == 'accepted' then
            local s = Config.Spots[d.spot]
            local c = Config.Customers[d.cid]
            add('deal', ('Deal: %s'):format(c and c.name or d.cid), s.coords.x, s.coords.y, { sub = s.label })
        end
    end
    for cid, c in pairs(P.customers) do
        local cfg = Config.Customers[cid]
        if c.u and cfg then
            local s = Config.Spots[cfg.home]
            add('customer', cfg.name, s.coords.x, s.coords.y, { sub = s.label })
        end
    end
    if P.sample then
        local s = Config.Spots[P.sample.spot]
        add('sample', 'Sample: ' .. P.sample.name, s.coords.x, s.coords.y, { sub = s.label })
    end
    for id, d in pairs(P.dealers) do
        local cfg = Config.DealerList[id]
        if d.hired and cfg then add('dealer', cfg.name, cfg.coords.x, cfg.coords.y) end
    end
    for _, o in ipairs(P.orders) do
        if not o.done and o.drop ~= 'rv' then
            local d = Deliveries.drop(o.drop)
            if d then add('drop', d.label, d.coords.x, d.coords.y, { ready = o.ready <= os.time() }) end
        end
    end
    local regions = {}
    local level = Profile.level(P)
    for _, r in ipairs(Config.Regions) do
        regions[#regions + 1] = { id = r.id, label = r.label, x = r.center.x, y = r.center.y, locked = level < r.unlock, rank = Utils.rankLabel(r.unlock) }
    end
    return { pins = pins, regions = regions }
end

Guard.callback('nzde:phone:data', function(src)
    local P = Profile.get(src)
    if not P then return false end
    if not P.story.app then return { locked = true } end
    local level, into, need = Utils.levelFromXp(P.xp)
    local water = P.water
    return {
        now = os.time(),
        me = {
            name = P.name, level = level, rank = Utils.rankLabel(level), xp = into, need = need,
            nextRank = need and Utils.rankLabel(level + 1) or nil, stats = P.stats, water = water, cap = Config.WateringCan.capacity,
        },
        threads = Messages.view(P),
        deals = Customers.dealsView(P),
        journal = Quests.view(P),
        products = productsView(P),
        contacts = Customers.view(P),
        dealers = Dealers.view(P),
        deliveries = Deliveries.view(P),
        map = mapView(P, src),
        rv = { owned = P.rv.owned, exists = RV.vehicle(src) ~= nil, towFee = Config.RV.towFee },
        effects = Config.Effects,
        regions = Config.Regions,
        spots = (function()
            local s = {}
            for id, sp in pairs(Config.Spots) do s[id] = { label = sp.label, region = sp.region } end
            return s
        end)(),
        standards = Config.Standards,
        quality = Config.Quality,
        kinds = Config.Kinds,
        drugs = Config.Drugs,
    }
end)

Guard.callback('nzde:phone:read', function(src, thread)
    if type(thread) ~= 'string' then return false end
    Messages.read(src, thread)
    return true
end)

Guard.callback('nzde:phone:tab', function(src, tab)
    if tab == 'contacts' then Quests.progress(src, 'app:contacts') end
    return true
end)
