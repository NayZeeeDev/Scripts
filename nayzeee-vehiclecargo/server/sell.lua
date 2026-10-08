-----------------------------------------------------------------
-- Selling: buyer offers, quick export, delivery with damage-based
-- price drops (server keeps the real number).
-----------------------------------------------------------------
Sell = {}
local missions = {}
local nextId = 0
local S = Config.Selling

local function deleteNet(netId)
    local e = netId and NetworkGetEntityFromNetworkId(netId)
    if e and e ~= 0 and DoesEntityExist(e) then DeleteEntity(e) end
end

local function streakBonus(p)
    return math.min((p.clean_streak or 0) * S.CleanStreak.step, S.CleanStreak.max)
end

-- A drop-off entry is { name, area, coords }, a plain vec4 also works
local function dropAt(i)
    local d = Config.Dropoffs[i]
    if not d then return nil, nil end
    return d.coords or d, d.name or ('Drop-off #' .. i)
end

-- Drop-offs sorted into near / mid / far from this warehouse
local function dropTiers(loc)
    local origin = vector3(loc.spawn.x, loc.spawn.y, loc.spawn.z)
    local list = {}
    for i in ipairs(Config.Dropoffs) do
        local d = dropAt(i)
        local dist = #(origin - vector3(d.x, d.y, d.z))
        if dist >= S.MinDropDistance then list[#list + 1] = { i = i, dist = dist } end
    end
    if #list == 0 then for i in ipairs(Config.Dropoffs) do list[#list + 1] = { i = i, dist = 0 } end end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    local third = math.max(1, math.floor(#list / 3))
    local tiers = { near = {}, mid = {}, far = {} }
    for n, e in ipairs(list) do
        local t = n <= third and 'near' or (n <= third * 2 and 'mid' or 'far')
        table.insert(tiers[t], e)
    end
    for k, t in pairs(tiers) do if #t == 0 then tiers[k] = list end end
    return tiers
end

local function sample(list, n)
    local copy, out = {}, {}
    for i, v in ipairs(list) do copy[i] = v end
    for i = 1, math.min(n, #copy) do
        local j = math.random(i, #copy)
        copy[i], copy[j] = copy[j], copy[i]
        out[#out + 1] = copy[i]
    end
    return out
end

local function generateBuyers(w, loc)
    local contacts = Cargo.Upgrade('contacts', w.upgrades.contacts)
    local count = contacts and contacts.buyers or 2
    local tiers = dropTiers(loc)
    local names = sample(S.BuyerNames, count)
    local buyers = {}
    for i = 1, count do
        local bt = S.BuyerTypes[((i - 1) % #S.BuyerTypes) + 1]
        if i > #S.BuyerTypes then bt = S.BuyerTypes[math.random(1, #S.BuyerTypes)] end
        local wants = {}
        for _, wnt in ipairs(sample(S.Wants, bt.wants)) do wants[#wants + 1] = wnt.id end
        local tier = tiers[bt.dist]
        local drop = tier[math.random(1, #tier)]
        buyers[i] = {
            name = names[i] or ('Buyer ' .. i), type = bt.id, label = bt.label,
            mult = bt.offer[1] + math.random() * (bt.offer[2] - bt.offer[1]),
            wants = wants, drop = drop.i, dist = math.floor(drop.dist), hot = math.random() < bt.hot,
        }
    end
    return buyers
end

-- Offer amounts for a stock car (recomputed every time from the buyer definitions)
local function priced(w, item, p)
    local base = Cargo.BaseValue(item, w.upgrades.contacts)
    local streak = streakBonus(p)
    local out = {}
    for i, b in ipairs(item.offers or {}) do
        local met, bonus = Cargo.MatchWants(item.build, item.condition, item.score, b.wants)
        out[i] = {
            index = i, name = b.name, type = b.type, label = b.label, wants = b.wants, met = met,
            dist = b.dist, place = select(2, dropAt(b.drop)), hot = b.hot, amount = math.floor(base * b.mult * (1 + bonus) * (1 + streak)),
        }
    end
    return out, base, streak
end

local function sellContext(src, stockId)
    local st = Server.Get(src)
    if not st or not st.inside or not Server.Can(src, st.inside, 'sell') then return nil end
    local w = DB.Warehouses[st.inside]
    local item = DB.GetStockItem(tonumber(stockId))
    if not item or item.warehouse ~= w.id or item.status ~= 'stored' then return nil end
    return st, w, item, DB.Locations[w.location]
end

lib.callback.register('nz_cargo:sell:offers', function(src, stockId)
    local st, w, item, loc = sellContext(src, stockId)
    if not st or not loc then return nil end
    if not item.offers or (Server.Now() - (item.offers_at or 0)) > S.OfferRefresh then
        item.offers = generateBuyers(w, loc)
        item.offers_at = Server.Now()
        DB.UpdateStock(item)
    end
    local p = Server.Profile(src)
    local offers, base, streak = priced(w, item, p)
    return {
        stockId = item.id, offers = offers, base = base, streak = streak,
        quick = math.floor(base * S.QuickSale), refreshIn = S.OfferRefresh - (Server.Now() - item.offers_at),
        cooldown = math.max(0, p.sell_cd - Server.Now()),
    }
end)

local function payout(src, st, w, item, amount, kind, extra)
    local p = Server.Profile(src)
    amount = math.floor(amount * Server.SaleMult(src))   -- prestige bonus
    Bridge.AddMoney(src, Config.Accounts.Payout, amount, 'vehiclecargo-sale')
    p.sold = p.sold + 1
    p.earned = p.earned + amount
    if amount > p.best_sale then p.best_sale = amount end
    DB.SaveProfile(p)
    DB.DeleteStock(item.id)
    DB.Log(st.identifier, w.id, kind, item.label, item.rarity, amount, extra)
    Server.Webhook('Vehicle sold', { Player = st.name, Vehicle = item.label, Rarity = item.rarity, Amount = '$' .. lib.math.groupdigits(amount), Type = kind })
    return amount
end

lib.callback.register('nz_cargo:sell:quick', function(src, stockId)
    local st, w, item = sellContext(src, stockId)
    if not st then return false end
    local amount = math.floor(Cargo.BaseValue(item, w.upgrades.contacts) * S.QuickSale)
    amount = payout(src, st, w, item, amount, 'export')
    Server.AddXp(src, math.floor(Cargo.Rarity[item.rarity].xp * S.SaleXpMult * 0.5))
    Server.Notify(src, L('sell_quick', item.label, lib.math.groupdigits(amount)), 'success')
    Warehouse.Refresh(w.id)
    return Warehouse.Payload(src, w.id)
end)

-----------------------------------------------------------------
-- Start a delivery sale
-----------------------------------------------------------------
lib.callback.register('nz_cargo:sell:start', function(src, stockId, buyerIndex)
    local st, w, item, loc = sellContext(src, stockId)
    if not st or not loc then return false end
    if st.mission then Server.Notify(src, L('busy'), 'error') return false end
    local p = Server.Profile(src)
    if p.sell_cd > Server.Now() then
        Server.Notify(src, L('cooldown', Cargo.FormatTime(p.sell_cd - Server.Now())), 'error') return false
    end
    if not item.offers then return false end
    local offers = priced(w, item, p)
    local offer = offers[tonumber(buyerIndex)]
    local buyerDef = item.offers[tonumber(buyerIndex)]
    if not offer or not buyerDef then return false end

    local sp = loc.spawn
    local entity = CreateVehicleServerSetter(joaat(item.model), Server.TypeOf(item.model), sp.x, sp.y, sp.z, sp.w)
    local tries = 0
    while not DoesEntityExist(entity) and tries < 50 do Wait(20) tries = tries + 1 end
    if not DoesEntityExist(entity) then return false end
    SetVehicleNumberPlateText(entity, item.plate or Source.Plate())
    SetVehicleDoorsLocked(entity, 1)

    DB.SetStockStatus(item.id, 'selling')
    Warehouse.Refresh(w.id)

    nextId = nextId + 1
    local drop, dropName = dropAt(buyerDef.drop)
    local m = {
        id = nextId, kind = 'sell', src = src, wid = w.id, stockId = item.id, entity = entity,
        netId = NetworkGetNetworkIdFromEntity(entity), label = item.label, rarity = item.rarity,
        offer = offer.amount, penalty = 0.0, counts = { hit = 0, rammed = 0, shot = 0, explosion = 0 },
        drop = DB.V4(drop), expires = Server.Now() + S.TimeLimit, peds = {}, lastHit = 0,
        buyer = { name = offer.name, label = offer.label, wants = offer.wants, met = offer.met, place = dropName },
        attack = Source.RollAttack('sell', item.rarity) or (buyerDef.hot and { cars = 1, delay = math.random(Config.Attackers.Delay[1], Config.Attackers.Delay[2]) }) or nil,
        illegal = Cargo.IsIllegal(item.rarity),
    }
    missions[m.id] = m
    st.mission = m
    Radio.Start(m)
    p.sell_cd = Server.Now() + S.Cooldown
    DB.SaveProfile(p)
    Entity(entity).state:set('nzCargo', { mission = m.id, owner = src, sale = true }, true)

    Server.PutInBucket(src, nil)
    if m.attack then
        SetTimeout(math.max(1, m.attack.delay - 6) * 1000, function()
            if missions[m.id] then Source.Text(src, m.illegal and 'illegal' or 'sell') end
        end)
    end
    return {
        id = m.id, netId = m.netId, label = m.label, rarity = m.rarity, model = item.model, props = item.props,
        offer = m.offer, drop = m.drop, spawn = sp, buyer = m.buyer, attack = m.attack, timeLimit = S.TimeLimit, illegal = m.illegal,
        cutscene = S.Cutscene.Enabled, buyerModel = S.Cutscene.BuyerModels[math.random(1, #S.Cutscene.BuyerModels)],
        minOffer = math.floor(m.offer * S.MinOffer), condition = item.condition,
    }
end)

local function owned(src, id)
    local m = missions[tonumber(id)]
    if not m or m.src ~= src then return nil end
    return m
end

local function currentOffer(m)
    return math.max(math.floor(m.offer * (1 - m.penalty / 100)), math.floor(m.offer * S.MinOffer))
end

local function finish(m, keepEntity)
    missions[m.id] = nil
    Radio.Stop(m)
    local st = Server.Players[m.src]
    if st and st.mission and st.mission.id == m.id then st.mission = nil end
    for _, n in ipairs(m.peds) do deleteNet(n) end
    if not keepEntity and m.entity and DoesEntityExist(m.entity) then DeleteEntity(m.entity) end
end

local function fail(m, reason, keep)
    finish(m)
    local st = Server.Players[m.src]
    if keep or S.ReturnOnFail then
        DB.SetStockStatus(m.stockId, 'stored')
    else
        local item, w = DB.GetStockItem(m.stockId), DB.Warehouses[m.wid]
        DB.DeleteStock(m.stockId)
        if item and w then Raid.Claim(w, item, 'lost') end
    end
    if st and st.identifier then
        local p = DB.GetProfile(st.identifier)
        p.failed = p.failed + 1
        p.clean_streak = 0
        DB.SaveProfile(p)
        DB.Log(st.identifier, m.wid, 'failed', m.label, m.rarity, 0, { reason = reason, sale = true })
    end
    Warehouse.Refresh(m.wid)
    if GetPlayerPing(m.src) > 0 then
        Server.Notify(m.src, L(m.deal and 'deal_car_lost' or 'sell_failed', reason), 'error', m.deal and 'Crew Sale' or 'Sale Failed')
        TriggerClientEvent('nz_cargo:sell:end', m.src, { success = false, reason = reason, deal = m.deal ~= nil })
    end
    if m.deal and Sell.DealLost then Sell.DealLost(m) end
end

lib.callback.register('nz_cargo:sell:peds', function(src, id, netIds)
    local m = owned(src, id)
    if not m or type(netIds) ~= 'table' then return false end
    for _, n in ipairs(netIds) do if #m.peds < 16 then m.peds[#m.peds + 1] = tonumber(n) end end
    return true
end)

-- Damage report from the driver. kind = hit | rammed | shot | explosion
lib.callback.register('nz_cargo:sell:damage', function(src, id, kind, healthLost)
    local m = owned(src, id)
    local def = S.Damage[kind]
    if not m or type(def) ~= 'table' then return nil end
    local now = GetGameTimer()
    if now - m.lastHit < 250 then return { offer = currentOffer(m), counts = m.counts } end
    m.lastHit = now
    healthLost = Cargo.Clamp(tonumber(healthLost) or 0, 0, 2000)
    local pct = def.pct + (healthLost / 100) * S.Damage.severityPer100
    m.penalty = math.min(m.penalty + pct, 100)
    m.counts[kind] = m.counts[kind] + 1
    return { offer = currentOffer(m), counts = m.counts, pct = pct }
end)

lib.callback.register('nz_cargo:sell:deliver', function(src, id)
    local m = owned(src, id)
    if not m then return false end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= m.entity then return false end
    local pos = GetEntityCoords(m.entity)
    if #(pos - vector3(m.drop.x, m.drop.y, m.drop.z)) > (m.deal and Config.CrewSale.DropRadius or 12.0) then return false end

    -- server-side sanity floor: the car's real health can't be better than reported
    local body = Cargo.Clamp(GetVehicleBodyHealth(m.entity), 0, 1000)
    local engine = Cargo.Clamp(GetVehicleEngineHealth(m.entity), 0, 1000)
    local lost = (1000 - body) + (1000 - engine)
    local floor = (lost / 100) * S.Damage.severityPer100 * 0.8
    if floor > m.penalty then m.penalty = math.min(floor, 100) end
    if m.deal then return Sell.DealArrive(m) end

    local st = Server.Get(src)
    local w = DB.Warehouses[m.wid]
    local item = DB.GetStockItem(m.stockId)
    if not item or not w then finish(m) return false end

    local total = currentOffer(m)
    local hits = m.counts.hit + m.counts.rammed + m.counts.shot + m.counts.explosion
    local clean = hits == 0 and m.penalty < 0.5

    -- associate cuts
    local cuts, paidOut = {}, 0
    for _, a in ipairs(w.associates) do
        for asrc, ast in pairs(Server.Players) do
            if ast.identifier == a.identifier and asrc ~= src then
                local d = #(GetEntityCoords(GetPlayerPed(asrc)) - pos)
                if d <= Config.Associates.CutRange then
                    local cut = math.floor(total * Config.Associates.Cut)
                    Bridge.AddMoney(asrc, Config.Accounts.Payout, cut, 'vehiclecargo-cut')
                    Server.Notify(asrc, L('sell_cut', st.name, lib.math.groupdigits(cut)), 'success')
                    Server.AddXp(asrc, math.floor(Cargo.Rarity[m.rarity].xp * 0.25))
                    cuts[#cuts + 1] = { name = ast.name, amount = cut }
                    paidOut = paidOut + cut
                end
            end
        end
    end
    local mine = total - paidOut

    -- the car stays for the handover cinematic, then the buyer drives it away and it is cleaned up
    finish(m, S.Cutscene.Enabled)
    if S.Cutscene.Enabled and DoesEntityExist(m.entity) then
        Entity(m.entity).state:set('nzCargo', { sold = true }, true)
        local ent = m.entity
        SetTimeout(45000, function() if DoesEntityExist(ent) then DeleteEntity(ent) end end)
    end
    mine = payout(src, st, w, item, mine, 'sale', { hits = m.counts, penalty = m.penalty, buyer = m.buyer.name })

    local p = Server.Profile(src)
    p.clean_streak = clean and (p.clean_streak + 1) or 0
    DB.SaveProfile(p)

    local xp = Cargo.Rarity[m.rarity].xp * S.SaleXpMult
    if clean then xp = xp * (1 + S.CleanXpBonus) end
    xp = math.floor(xp)
    Server.AddXp(src, xp)
    Server.Notify(src, L('sell_done', m.label, lib.math.groupdigits(mine)), 'success', 'Sale Complete')
    Warehouse.Refresh(w.id)

    return {
        label = m.label, rarity = m.rarity, buyer = m.buyer, agreed = m.offer, final = total, mine = mine,
        penalty = m.penalty, counts = m.counts, clean = clean, streak = p.clean_streak, xp = xp, cuts = cuts,
    }
end)

lib.callback.register('nz_cargo:sell:destroyed', function(src, id)
    local m = owned(src, id)
    if m then fail(m, L('src_destroyed')) end
    return true
end)

lib.callback.register('nz_cargo:sell:cancel', function(src, id)
    local m = owned(src, id)
    if m then fail(m, L('src_abandoned')) end
    return true
end)

CreateThread(function()
    while true do
        local any = false
        local now = Server.Now()
        for _, m in pairs(missions) do
            any = true
            if now >= m.expires then
                fail(m, L('src_timeout'))
            elseif not DoesEntityExist(m.entity) then
                fail(m, L('src_destroyed'))
            end
        end
        Wait(any and 2000 or 5000)
    end
end)

-- Disconnect mid-sale: the car goes back on the floor
table.insert(Server.Cleanup, function(src)
    for _, m in pairs(missions) do
        if m.src == src then fail(m, L('src_abandoned'), true) end
    end
end)

-----------------------------------------------------------------
-- Crew sales: several cars, one deal (Config.CrewSale)
-- Every car is its own sale mission (own driver, own damage, own
-- price). The deal pays out once no car is still on the road.
-----------------------------------------------------------------
local CS = Config.CrewSale
local deals, nextDeal, pending = {}, 0, {}

-- owner / associates inside this warehouse and free to drive
local function crewInside(wid)
    local out = {}
    for _, o in ipairs(Server.Occupants(wid)) do
        local r = Server.Access(o, wid)
        local st = Server.Get(o)
        if (r == 'owner' or r == 'associate') and st and not st.mission then out[#out + 1] = { src = o, name = st.name } end
    end
    return out
end

local function dealOptions(w, loc, items)
    local tiers = dropTiers(loc)
    local names = sample(S.BuyerNames, 3)
    local n = #items
    local function value(it) return Cargo.BaseValue(it, w.upgrades.contacts) end
    local function single(name, label, tier, lo, hi, hot)
        local d = tier[math.random(1, #tier)]
        local mult = (lo + math.random() * (hi - lo)) * (1 + CS.VolumeBonus * (n - 1))
        local cars, total = {}, 0
        for i, it in ipairs(items) do
            local amt = math.floor(value(it) * mult)
            cars[i] = { stockId = it.id, label = it.label, rarity = it.rarity, amount = amt, drop = d.i, place = select(2, dropAt(d.i)) }
            total = total + amt
        end
        return { mode = 'single', name = name, label = label, cars = cars, total = total, hot = hot, place = select(2, dropAt(d.i)), dist = math.floor(d.dist) }
    end
    local opts = {
        single(names[1] or 'Benny', 'Bulk Buyer', tiers.mid, 1.02, 1.08, false),
        single(names[2] or 'Hao', 'Export Broker', tiers.far, 1.12, 1.20, true),
    }
    -- split run: a different drop for every car
    local all = {}
    for _, t in pairs(tiers) do for _, e in ipairs(t) do all[#all + 1] = e end end
    local picks = sample(all, n)
    local cars, total = {}, 0
    for i, it in ipairs(items) do
        local d = picks[i] or all[math.random(1, #all)]
        local amt = math.floor(value(it) * (CS.SplitBonus[1] + math.random() * (CS.SplitBonus[2] - CS.SplitBonus[1])))
        cars[i] = { stockId = it.id, label = it.label, rarity = it.rarity, amount = amt, drop = d.i, place = select(2, dropAt(d.i)) }
        total = total + amt
    end
    opts[3] = { mode = 'split', name = names[3] or 'Gianni', label = 'Split Run', cars = cars, total = total, hot = true, place = ('%d drops'):format(n) }
    return opts
end

local function dealItems(w, ids)
    if type(ids) ~= 'table' then return nil end
    local items, seen = {}, {}
    for _, id in ipairs(ids) do
        id = tonumber(id)
        if not id or seen[id] then return nil end
        seen[id] = true
        local it = DB.GetStockItem(id)
        if not it or it.warehouse ~= w.id or it.status ~= 'stored' then return nil end
        items[#items + 1] = it
    end
    if #items < CS.MinCars or #items > CS.MaxCars then return nil end
    return items
end

lib.callback.register('nz_cargo:crewsale:offers', function(src, ids)
    if not CS.Enabled then return nil end
    local st = Server.Get(src)
    if not st or not st.inside or not Server.Can(src, st.inside, 'sell') then return nil end
    if st.mission then Server.Notify(src, L('busy'), 'error') return nil end
    local w = DB.Warehouses[st.inside]
    local loc = DB.Locations[w.location]
    local items = dealItems(w, ids)
    if not items or not loc then Server.Notify(src, L('deal_pick', CS.MinCars, CS.MaxCars), 'error') return nil end
    local p = Server.Profile(src)
    local options = dealOptions(w, loc, items)
    local list = {}
    for i, it in ipairs(items) do list[i] = it.id end
    pending[src] = { wid = w.id, ids = list, options = options, at = Server.Now() }
    return { options = options, crew = crewInside(w.id), cooldown = math.max(0, p.sell_cd - Server.Now()), me = src }
end)

local function spawnDealCar(item, at)
    local e = CreateVehicleServerSetter(joaat(item.model), Server.TypeOf(item.model), at.x, at.y, at.z, at.w)
    local tries = 0
    while not DoesEntityExist(e) and tries < 50 do Wait(20) tries = tries + 1 end
    return DoesEntityExist(e) and e or nil
end

-- assign = { [stockId] = driverSrc }
lib.callback.register('nz_cargo:crewsale:start', function(src, optionIndex, assign)
    local pd = pending[src]
    local st = Server.Get(src)
    if not pd or not st or st.inside ~= pd.wid or Server.Now() - pd.at > 300 then return false end
    if not Server.Can(src, pd.wid, 'sell') or st.mission then return false end
    local opt = pd.options[tonumber(optionIndex) or 0]
    local w = DB.Warehouses[pd.wid]
    local loc = DB.Locations[w.location]
    local items = dealItems(w, pd.ids)
    if not opt or not items or not loc or type(assign) ~= 'table' then return false end
    local p = Server.Profile(src)
    if p.sell_cd > Server.Now() then Server.Notify(src, L('cooldown', Cargo.FormatTime(p.sell_cd - Server.Now())), 'error') return false end

    -- every car needs its own free driver from the crew inside, and you drive one of them
    local free = {}
    for _, c in ipairs(crewInside(w.id)) do free[c.src] = true end
    local used, drivers, meIn = {}, {}, false
    for _, it in ipairs(items) do
        local d = tonumber(assign[tostring(it.id)] or assign[it.id])
        if not d or not free[d] or used[d] then Server.Notify(src, L('deal_drivers'), 'error') return false end
        used[d] = true
        drivers[it.id] = d
        if d == src then meIn = true end
    end
    if not meIn then Server.Notify(src, L('deal_you_drive'), 'error') return false end
    pending[src] = nil

    nextDeal = nextDeal + 1
    local deal = { id = nextDeal, leader = src, wid = w.id, mode = opt.mode, buyer = { name = opt.name, label = opt.label }, cars = {}, order = {}, members = {},
                   buyerModel = S.Cutscene.BuyerModels[math.random(1, #S.Cutscene.BuyerModels)] }
    deals[deal.id] = deal
    p.sell_cd = Server.Now() + CS.Cooldown
    DB.SaveProfile(p)

    local sp = loc.spawn
    local h = math.rad(sp.w or 0.0)
    local fx, fy = -math.sin(h), math.cos(h)
    for i, it in ipairs(items) do
        local line = opt.cars[i]
        -- queue the cars up behind each other out of the garage
        local at = { x = sp.x - fx * 7.0 * (i - 1), y = sp.y - fy * 7.0 * (i - 1), z = sp.z, w = sp.w }
        local entity = spawnDealCar(it, at)
        local driver = drivers[it.id]
        local dst = Server.Get(driver)
        if entity and dst then
            SetVehicleNumberPlateText(entity, it.plate or Source.Plate())
            SetVehicleDoorsLocked(entity, 1)
            DB.SetStockStatus(it.id, 'selling')
            nextId = nextId + 1
            local drop, dropName = dropAt(line.drop)
            local attack = Source.RollAttack('sell', it.rarity)
            if not attack and math.random() < CS.AttackChance then attack = { cars = 1, delay = math.random(Config.Attackers.Delay[1], Config.Attackers.Delay[2]) } end
            local m = {
                id = nextId, kind = 'sell', src = driver, wid = w.id, stockId = it.id, entity = entity,
                netId = NetworkGetNetworkIdFromEntity(entity), label = it.label, rarity = it.rarity,
                offer = line.amount, penalty = 0.0, counts = { hit = 0, rammed = 0, shot = 0, explosion = 0 },
                drop = DB.V4(drop), expires = Server.Now() + CS.TimeLimit, peds = {}, lastHit = 0,
                buyer = { name = opt.name, label = opt.label, wants = {}, met = {}, place = dropName },
                attack = attack, illegal = Cargo.IsIllegal(it.rarity), deal = deal.id,
            }
            missions[m.id] = m
            dst.mission = m
            Radio.Start(m)
            Entity(entity).state:set('nzCargo', { mission = m.id, owner = driver, sale = true }, true)
            deal.cars[it.id] = { m = m, state = 'driving', final = 0, label = it.label, rarity = it.rarity, driver = driver, item = it }
            deal.order[#deal.order + 1] = it.id
            deal.members[driver] = true
            Server.PutInBucket(driver, nil)
            if attack then
                SetTimeout(math.max(1, attack.delay - 6) * 1000, function()
                    if missions[m.id] then Source.Text(driver, m.illegal and 'illegal' or 'sell') end
                end)
            end
            TriggerClientEvent('nz_cargo:crewsale:begin', driver, {
                id = m.id, netId = m.netId, label = m.label, rarity = m.rarity, model = it.model, props = it.props,
                offer = m.offer, drop = m.drop, spawn = at, buyer = m.buyer, attack = m.attack, timeLimit = CS.TimeLimit, illegal = m.illegal,
                cutscene = false, minOffer = math.floor(m.offer * S.MinOffer), condition = it.condition,
                deal = { id = deal.id, mode = deal.mode, cars = #items, leader = src },
            })
        end
    end
    if #deal.order == 0 then deals[deal.id] = nil return false end
    deal.count = #deal.order
    Warehouse.Refresh(w.id)
    DB.Log(st.identifier, w.id, 'contract', ('Crew sale · %d cars'):format(deal.count), nil, 0, { buyer = opt.name, mode = opt.mode })
    if opt.mode == 'single' then Source.Contact(src, 'sale', opt.cars[1].place or 'the drop') end
    return { ok = true }
end)

local function dealMembers(deal)
    local out = {}
    for s2 in pairs(deal.members) do if GetPlayerPing(s2) > 0 then out[#out + 1] = s2 end end
    return out
end

-- Nothing left on the road: pay out and play the handover for the crew
local function dealFinish(deal)
    deals[deal.id] = nil
    local w = DB.Warehouses[deal.wid]
    local delivered, total, xp = {}, 0, 0
    for _, id in ipairs(deal.order) do
        local c = deal.cars[id]
        if c.state == 'waiting' then
            local ent = c.m.entity
            local d = c.m.drop
            -- a car driven off after it was dropped doesn't count
            if not ent or not DoesEntityExist(ent) or #(GetEntityCoords(ent) - vector3(d.x, d.y, d.z)) > 60.0 then
                c.state = 'lost'
            else
                delivered[#delivered + 1] = c
                total = total + c.final
                xp = xp + (Cargo.Rarity[c.rarity] and Cargo.Rarity[c.rarity].xp or 0) * S.SaleXpMult
            end
        end
    end
    for s2, stt in pairs(Server.Players) do
        if deal.members[s2] and stt.mission and stt.mission.waitingDeal == deal.id then stt.mission = nil end
    end
    local members = dealMembers(deal)
    if #delivered == 0 or not w then
        for _, s2 in ipairs(members) do TriggerClientEvent('nz_cargo:crewsale:finale', s2, { failed = true }) end
        if w then Warehouse.Refresh(w.id) end
        return
    end

    -- cuts for the crew, the rest to whoever set up the deal
    local leader = deal.leader
    local lst = Server.Get(leader)
    local shares, paidOut = {}, 0
    for _, s2 in ipairs(members) do
        if s2 ~= leader then
            local cut = math.floor(total * CS.Cut)
            shares[s2] = cut
            paidOut = paidOut + cut
            Bridge.AddMoney(s2, Config.Accounts.Payout, cut, 'vehiclecargo-crewsale')
            Server.AddXp(s2, math.floor(xp * CS.XpShare))
        end
    end
    local mine = math.floor((total - paidOut) * Server.SaleMult(leader))
    shares[leader] = mine
    if GetPlayerPing(leader) > 0 then
        Bridge.AddMoney(leader, Config.Accounts.Payout, mine, 'vehiclecargo-crewsale')
        Server.AddXp(leader, math.floor(xp))
        local p = Server.Profile(leader)
        p.sold = p.sold + #delivered
        p.earned = p.earned + mine
        if mine > p.best_sale then p.best_sale = mine end
        DB.SaveProfile(p)
    end
    local cars = {}
    for _, id in ipairs(deal.order) do
        local c = deal.cars[id]
        local ok = c.state == 'waiting'
        if ok then
            DB.DeleteStock(id)
            if lst then DB.Log(lst.identifier, w.id, 'sale', c.label, c.rarity, c.final, { crew = true, buyer = deal.buyer.name, penalty = c.m.penalty }) end
            local ent = c.m.entity
            Entity(ent).state:set('nzCargo', { sold = true }, true)
            SetTimeout(90000, function() if DoesEntityExist(ent) then DeleteEntity(ent) end end)
        end
        cars[#cars + 1] = { label = c.label, rarity = c.rarity, final = ok and c.final or 0, penalty = c.m.penalty, lost = not ok,
                            netId = ok and c.m.netId or nil, drop = c.m.drop, driver = c.driver }
    end
    Warehouse.Refresh(w.id)
    Server.Webhook('Crew sale', { Leader = lst and lst.name or '?', Cars = #delivered .. '/' .. deal.count, Total = '$' .. lib.math.groupdigits(total) })
    local director = GetPlayerPing(leader) > 0 and leader or members[1]
    for _, s2 in ipairs(members) do
        TriggerClientEvent('nz_cargo:crewsale:finale', s2, {
            mode = deal.mode, buyer = deal.buyer, buyerModel = deal.buyerModel, cars = cars, total = total,
            mine = shares[s2] or 0, leader = leader, director = director, delivered = #delivered, count = deal.count,
            xp = math.floor(s2 == leader and xp or xp * CS.XpShare),
        })
    end
end

local function dealCheck(deal)
    local done, lost, driving = 0, 0, 0
    for _, id in ipairs(deal.order) do
        local st = deal.cars[id].state
        if st == 'driving' then driving = driving + 1 elseif st == 'lost' then lost = lost + 1 else done = done + 1 end
    end
    if driving == 0 then return dealFinish(deal) end
    for _, s2 in ipairs(dealMembers(deal)) do
        TriggerClientEvent('nz_cargo:crewsale:progress', s2, { done = done, lost = lost, total = deal.count })
    end
end

-- A car made it to its drop: its price is locked, the driver waits for the crew
function Sell.DealArrive(m)
    local deal = deals[m.deal]
    local c = deal and deal.cars[m.stockId]
    if not c or c.state ~= 'driving' then return false end
    c.final = currentOffer(m)
    c.state = 'waiting'
    finish(m, true)
    local st = Server.Players[m.src]
    if st then st.mission = { kind = 'sell', id = m.id, waitingDeal = deal.id } end
    local done = 0
    for _, id in ipairs(deal.order) do if deal.cars[id].state ~= 'driving' then done = done + 1 end end
    local res = { waiting = true, final = c.final, label = m.label, rarity = m.rarity, penalty = m.penalty, counts = m.counts, done = done, total = deal.count }
    SetTimeout(0, function() dealCheck(deal) end)
    return res
end

function Sell.DealLost(m)
    local deal = deals[m.deal]
    local c = deal and deal.cars[m.stockId]
    if not c or c.state ~= 'driving' then return end
    c.state = 'lost'
    dealCheck(deal)
end
