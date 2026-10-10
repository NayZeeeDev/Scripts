-- The phone app's backend: quick sell, meet-ups, player listings and NPC orders

Phone = {}

local CP = Config.Phone
local QS, MU, LS, OR = CP.QuickSell, CP.Meetup, CP.Listings, CP.Orders

local function now() return os.time() end

Phone.Tiers, Phone.Grades = {}, {}
for i, t in ipairs(Config.Tiers) do Phone.Tiers[i] = { id = t.id, label = t.label, color = t.color } end
for i, g in ipairs(Config.Bundles.Grades) do Phone.Grades[i] = { id = g.id, label = g.label } end

local function perkOf(P) return GetPerks(P.row.xp).sell end

local function goodsByKey(src)
    local out = {}
    for _, s in ipairs(Wigs.Goods(src)) do out[s.key] = s end
    return out
end

local function demandKey(meta) return meta.bundle and 'bundle' or meta.tier end

-- sells the given keys at `rate` of their value. returns count, total
local function sellKeys(P, keys, rate, account, reason)
    local byKey, perk = goodsByKey(P.src), perkOf(P)
    local total, count, seen, lines = 0, 0, {}, {}
    for _, key in ipairs(keys) do
        local s = type(key) == 'string' and not seen[key] and byKey[key]
        if s then
            seen[key] = true
            local price = math.floor(Wigs.Value(s.meta, perk) * rate)
            if Wigs.Remove(P.src, s) then
                total = total + price
                count = count + 1
                Market.Sold(demandKey(s.meta), 1)
                lines[#lines + 1] = ('%s `%s` $%s'):format(s.meta.label or 'Wig', s.meta.serial or '-', price)
            end
        end
    end
    if count == 0 then return 0, 0 end
    Bridge.AddMoney(P.src, total, account, reason)
    P.row.wigs_sold = P.row.wigs_sold + count
    P.row.earned = P.row.earned + total
    SaveP(P)
    Log('sell', 'Hair sold', ('**%s** · %s · %s item(s) for **$%s** (%s)\n%s'):format(P.name, reason, count, total, account, table.concat(lines, '\n')))
    return count, total
end

local function cleanKeys(keys)
    if type(keys) ~= 'table' or #keys == 0 or #keys > 100 then return nil end
    for _, k in ipairs(keys) do if type(k) ~= 'string' then return nil end end
    return keys
end

-- orders --------------------------------------------------------------------------------------------

local orders, oseq = {}, 0

local function weightedTier()
    -- orders lean toward the middle tiers so they're actually fillable
    local pool = { 'common', 'uncommon', 'uncommon', 'rare', 'rare', 'epic', 'legendary' }
    local pick = pool[math.random(1, #pool)]
    return TierIndex[pick] and pick or Config.Tiers[1].id
end

local function newOrder()
    oseq = oseq + 1
    local o = { id = oseq, expires = now() + OR.Minutes * 60,
        mult = math.floor((OR.Bonus[1] + math.random() * (OR.Bonus[2] - OR.Bonus[1])) * 100) / 100 }
    if math.random() < 0.7 then
        o.kind = 'wig'
        o.tier = weightedTier()
        local entries = Wigs.CatalogEntries()
        if #entries > 0 and math.random() < 0.45 then
            local e = entries[math.random(1, #entries)]
            o.styleKey, o.fits = e.key, e.m
        end
        if not o.styleKey and math.random() < 0.3 then o.fits = math.random() < 0.5 and 'm' or 'f' end
    else
        o.kind = 'bundle'
        o.grade = Config.Bundles.Grades[math.random(1, math.min(3, #Config.Bundles.Grades))].id
        o.length = 10 + math.random(0, 6) * 2
    end
    local names = { 'Keisha', 'Tasha', 'Mo', 'Big Dre', 'Aunty Pat', 'Lil Mel', 'Vonnie', 'Shay', 'Coco', 'Rell' }
    o.from = names[math.random(1, #names)]
    return o
end

local function matches(o, meta)
    if o.kind == 'bundle' then
        return meta.bundle and (GradeIndex[meta.grade] or 1) >= (GradeIndex[o.grade] or 1) and (meta.length or 0) >= (o.length or 0)
    end
    if meta.bundle or meta.generic then return false end
    if (TierIndex[meta.tier] or 1) < (TierIndex[o.tier] or 1) then return false end
    if o.styleKey and CatalogKey(meta.hair) ~= o.styleKey then return false end
    if o.fits and (not meta.hair or meta.hair.m ~= o.fits) then return false end
    return true
end

local function refreshOrders()
    if not OR.Enabled then return {} end
    local t, keep = now(), {}
    for _, o in ipairs(orders) do
        if o.expires > t and not o.filled then keep[#keep + 1] = o end
    end
    while #keep < OR.Count do keep[#keep + 1] = newOrder() end
    orders = keep
    return orders
end

local function publicOrder(o)
    local style
    if o.styleKey then
        local m, d = o.styleKey:match('^([mf]):(%d+)$')
        style = StyleNameFor(m, tonumber(d), 0)
    end
    return { id = o.id, kind = o.kind, tier = o.tier, style = style, fits = o.fits, grade = o.grade,
        length = o.length, mult = o.mult, expires = o.expires, from = o.from }
end

-- listings ---------------------------------------------------------------------------------------------

local function settle(P)
    for _, r in ipairs(DB.ListingsUnsettled(P.id)) do
        if r.status == 'sold' then
            if DB.ListingSettle(r.id) then
                local pay = math.floor(r.price * (1 - LS.Fee))
                Bridge.AddMoney(P.src, pay, LS.Account, 'wig-listing')
                P.row.earned = P.row.earned + pay
                P.row.wigs_sold = P.row.wigs_sold + 1
                Notify(P.src, L('listing_paid', r.meta.label or 'item', r.buyer_name or '?', pay), 'success', 7000)
            end
        elseif r.status == 'expired' then
            if Wigs.CanCarry(P.src, r.meta) and DB.ListingSettle(r.id) then
                Wigs.Give(P.src, r.meta)
                Notify(P.src, L('listing_returned', r.meta.label or 'item'), 'info', 7000)
            end
        end
    end
    SaveP(P)
end
Phone.Settle = settle

local lastExpire = 0
local function expireListings()
    if not LS.Enabled or now() - lastExpire < 60 then return end
    lastExpire = now()
    DB.ListingsExpire(now() - LS.Hours * 3600)
end

local function publicListing(r, mine)
    local pub = Wigs.Public(r.meta, nil)
    pub.listing = r.id
    pub.price = r.price
    pub.seller = r.seller_name
    pub.created = r.created
    pub.mine = mine or nil
    pub.status = r.status
    pub.buyer = r.buyer_name
    return pub
end

-- app state ------------------------------------------------------------------------------------------------

lib.callback.register('nz-wig:phone', function(src)
    local P = GetP(src)
    if not P or not CP.Enabled then return nil end
    expireListings()
    settle(P)
    local lvl, ldata = GetLevel(P.row.xp)
    local perk = perkOf(P)

    local market, mine = {}, {}
    if LS.Enabled then
        for _, r in ipairs(DB.ListingsOpen(80)) do market[#market + 1] = publicListing(r, r.seller == P.id) end
        for _, r in ipairs(DB.ListingsBySeller(P.id)) do mine[#mine + 1] = publicListing(r, true) end
    end
    local ords = {}
    for _, o in ipairs(refreshOrders()) do ords[#ords + 1] = publicOrder(o) end

    local deal = P.deal and now() < P.deal.expires and { total = P.deal.total, count = #P.deal.keys, arrived = P.deal.arrived, expires = P.deal.expires } or nil
    return {
        now = now(),
        me = { name = P.name, title = ldata.title, level = lvl, perk = math.floor(perk * 100), money = Bridge.GetMoney(src, QS.Account) },
        goods = Wigs.GoodsList(src, perk),
        demand = Market.Snapshot(),
        quick = QS.Enabled and { rate = QS.Rate } or nil,
        meetup = MU.Enabled and { rate = MU.Rate, cooldown = math.max(0, (P.meetupCd or 0) - now()), deal = deal, dirty = MU.Account == 'black_money' } or nil,
        listings = LS.Enabled and { fee = LS.Fee, max = LS.MaxPerPlayer, hours = LS.Hours, min = LS.MinPrice, maxPrice = LS.MaxPrice, market = market, mine = mine } or nil,
        orders = OR.Enabled and ords or nil,
        hasMeta = Inv.HasMeta,
        tiers = Phone.Tiers,
        grades = Phone.Grades,
    }
end)

-- quick sell ---------------------------------------------------------------------------------------------------

lib.callback.register('nz-wig:phoneQuickSell', function(src, keys)
    local P = GetP(src)
    keys = cleanKeys(keys)
    if not P or not QS.Enabled or not keys then return false, L('invalid') end
    if P.busy then return false, L('busy') end
    local count, total = sellKeys(P, keys, QS.Rate, QS.Account, 'quick sell')
    if count == 0 then return false, L('invalid') end
    return true, L('sold', count, total)
end)

-- meet-up ----------------------------------------------------------------------------------------------------------

lib.callback.register('nz-wig:phoneMeetup', function(src, keys)
    local P = GetP(src)
    keys = cleanKeys(keys)
    if not P or not MU.Enabled or not keys then return false, L('invalid') end
    if P.busy then return false, L('busy') end
    if P.deal and now() < P.deal.expires then return false, L('buyer_active') end
    if now() < (P.meetupCd or 0) then return false, L('buyer_cooldown', P.meetupCd - now()) end
    if InVehicle(src) then return false, L('meetup_vehicle') end

    local byKey, perk, total, picked = goodsByKey(src), perkOf(P), 0, {}
    for _, k in ipairs(keys) do
        local s = byKey[k]
        if s then
            picked[#picked + 1] = k
            total = total + math.floor(Wigs.Value(s.meta, perk) * MU.Rate)
        end
    end
    if #picked == 0 then return false, L('invalid') end

    P.meetupCd = now() + MU.Cooldown
    P.deal = { keys = picked, total = total, expires = now() + 75 + MU.WaitTime, arrived = false, started = now() }
    TriggerClientEvent('nz-wig:c:meetupStart', src, { total = total, count = #picked })
    return true, L('buyer_coming')
end)

RegisterNetEvent('nz-wig:s:meetupArrived', function()
    local P = GetP(source)
    if P and P.deal then
        P.deal.arrived = true
        P.deal.expires = math.max(P.deal.expires, now() + MU.WaitTime)
    end
end)

RegisterNetEvent('nz-wig:s:meetupGone', function()
    local P = GetP(source)
    if P then P.deal = nil end
end)

lib.callback.register('nz-wig:meetupHandover', function(src)
    local P = GetP(src)
    if not P then return false end
    local d = P.deal
    if not d or not d.arrived or now() > d.expires then return false, L('buyer_session') end
    -- the buyer is a local ped the server can't see: he can't have run in faster than this
    if now() - (d.started or 0) < math.max(3, math.floor((MU.SpawnDistance or 35) / 8)) then return false, L('buyer_session') end
    if P.busy then return false, L('busy') end
    P.deal = nil
    local count, total = sellKeys(P, d.keys, MU.Rate, MU.Account, 'meet-up')
    if count == 0 then return false, L('meetup_nothing') end
    return true, L('sold', count, total)
end)

-- listings ------------------------------------------------------------------------------------------------------------

lib.callback.register('nz-wig:phoneList', function(src, key, price)
    local P = GetP(src)
    if not P or not LS.Enabled or type(key) ~= 'string' then return false, L('invalid') end
    if not Inv.HasMeta then return false, L('listing_no_meta') end
    if P.busy then return false, L('busy') end
    price = math.floor(SafeNumber(price) or 0)
    if price < LS.MinPrice or price > LS.MaxPrice then return false, L('listing_price', LS.MinPrice, LS.MaxPrice) end
    if DB.ListingCount(P.id) >= LS.MaxPerPlayer then return false, L('listing_max', LS.MaxPerPlayer) end
    local s = Wigs.FindGood(src, key)
    if not s or s.generic then return false, L('invalid') end
    if not Wigs.Remove(src, s) then return false, L('invalid') end
    local id = DB.ListingAdd(P.id, P.name, s.kind, s.meta, price)
    if not id then
        Wigs.Give(src, s.meta)
        return false, L('invalid')
    end
    Log('listing', 'Listed', ('**%s** listed %s `%s` for $%s'):format(P.name, s.meta.label or 'item', s.meta.serial or '-', price))
    return true, L('listing_added', s.meta.label or 'item', price)
end)

lib.callback.register('nz-wig:phoneBuy', function(src, id)
    local P = GetP(src)
    id = tonumber(id)
    if not P or not LS.Enabled or not id then return false, L('invalid') end
    if P.busy then return false, L('busy') end
    local r = DB.ListingGet(id)
    if not r or r.status ~= 'open' then return false, L('listing_gone') end
    if r.seller == P.id then return false, L('listing_own') end
    if not Wigs.CanCarry(src, r.meta) then return false, L('pockets_full') end
    if not Bridge.RemoveMoney(src, r.price, LS.Account, 'wig-listing-buy') then return false, L('no_money') end
    if not DB.ListingClose(id, 'open', 'sold', P.id, P.name) then
        Bridge.AddMoney(src, r.price, LS.Account, 'wig-listing-refund')
        return false, L('listing_gone')
    end
    if not Wigs.Give(src, r.meta) then
        -- couldn't hand it over: undo everything
        Bridge.AddMoney(src, r.price, LS.Account, 'wig-listing-refund')
        DB.ListingClose(id, 'sold', 'open', nil, nil)
        return false, L('pockets_full')
    end

    local sellerSrc = ById[r.seller]
    local S = sellerSrc and Players[sellerSrc]
    if S then settle(S) end
    Log('listing', 'Listing bought', ('**%s** bought %s `%s` from **%s** for $%s'):format(P.name, r.meta.label or 'item', r.meta.serial or '-', r.seller_name, r.price))
    return true, L('listing_bought', r.meta.label or 'item', r.price)
end)

lib.callback.register('nz-wig:phoneCancel', function(src, id)
    local P = GetP(src)
    id = tonumber(id)
    if not P or not id then return false, L('invalid') end
    local r = DB.ListingGet(id)
    if not r or r.seller ~= P.id or r.status ~= 'open' then return false, L('listing_gone') end
    if not Wigs.CanCarry(src, r.meta) then return false, L('pockets_full') end
    if not DB.ListingClose(id, 'open', 'cancelled', nil, nil) then return false, L('listing_gone') end
    DB.ListingSettle(id)
    Wigs.Give(src, r.meta)
    return true, L('listing_cancelled')
end)

-- orders -----------------------------------------------------------------------------------------------------------------

lib.callback.register('nz-wig:phoneOrder', function(src, orderId, key)
    local P = GetP(src)
    orderId = tonumber(orderId)
    if not P or not OR.Enabled or not orderId or type(key) ~= 'string' then return false, L('invalid') end
    if P.busy then return false, L('busy') end
    local o
    for _, x in ipairs(refreshOrders()) do if x.id == orderId then o = x end end
    if not o then return false, L('order_gone') end
    local s = Wigs.FindGood(src, key)
    if not s or not matches(o, s.meta) then return false, L('order_no_match') end
    local price = math.floor(Wigs.Value(s.meta, perkOf(P)) * o.mult)
    o.filled = true -- claim it before anything can yield
    if not Wigs.Remove(src, s) then o.filled = nil return false, L('invalid') end
    Market.Sold(demandKey(s.meta), 1)
    Bridge.AddMoney(src, price, OR.Account, 'wig-order')
    P.row.wigs_sold = P.row.wigs_sold + 1
    P.row.earned = P.row.earned + price
    SaveP(P)
    Log('sell', 'Order filled', ('**%s** filled %s\'s order with %s `%s` for $%s (x%s)'):format(P.name, o.from, s.meta.label or 'item', s.meta.serial or '-', price, o.mult))
    return true, L('order_filled', o.from, price)
end)

-- which of my goods fit an order (for the app's picker)
lib.callback.register('nz-wig:phoneOrderFits', function(src, orderId)
    local o
    for _, x in ipairs(refreshOrders()) do if x.id == tonumber(orderId) then o = x end end
    if not o then return {} end
    local out = {}
    for _, s in ipairs(Wigs.Goods(src)) do
        if matches(o, s.meta) then out[#out + 1] = s.key end
    end
    return out
end)

OnPlayerLoad(function(P)
    if LS.Enabled then SetTimeout(4000, function() if Players[P.src] == P then settle(P) end end) end
end)

OnPlayerDrop(function(_, P) P.deal = nil end)
