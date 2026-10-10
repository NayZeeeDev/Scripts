--[[
    Customers: samples, deal requests by text, counter offers, hand-overs.

    P.customers[cid] = { u = unlocked, rel = 0..5, add = 0..1, last = ts, cool = ts (sample cooldown), dealer = id }
    P.deals = { { id, cid, pid, qty, price, spot, exp, state = 'offer'|'accepted', countered } }
]]

Customers = {}

local D, R = Config.Deals, Config.Relationship

local function cstate(P, cid)
    local c = P.customers[cid]
    if not c then
        c = { u = false, rel = R.start, add = 0.0 }
        P.customers[cid] = c
    end
    return c
end
Customers.state = cstate

function Customers.unlock(src, cid, silent)
    local P = Profile.get(src)
    local cfg = Config.Customers[cid]
    if not P or not cfg then return end
    local c = cstate(P, cid)
    if c.u then return end
    c.u = true
    c.rel = math.max(c.rel, R.start)
    Profile.dirty(src)
    if not silent then
        Messages.push(src, cid, { f = 'them', m = ("Alright, that was decent. I'll hit you up when I need more.") })
    end
end

local function linksAvailable(P, cid)
    for oid, o in pairs(P.customers) do
        local cfg = Config.Customers[oid]
        if o.u and cfg and (o.rel or 0) >= R.unlockConnections and Utils.contains(cfg.links, cid) then return true end
    end
    return false
end

--- can be sampled: locked, region open, introduced (a Friendly customer links to them, or the tutorial)
function Customers.sampleable(P, cid)
    local cfg = Config.Customers[cid]
    local c = P.customers[cid]
    if not cfg or (c and c.u) then return false end
    if not Utils.regionUnlocked(cfg.region, Profile.level(P)) then return false end
    if c and c.cool and c.cool > os.time() then return false end
    -- the tutorial: anyone directly linked to a starter customer is available
    for _, s in ipairs(Config.Story.starterCustomers) do
        if Utils.contains(Config.Customers[s].links, cid) then return true end
    end
    return linksAvailable(P, cid)
end

local function relBump(src, P, cid, delta)
    local c = cstate(P, cid)
    local before = c.rel
    c.rel = Utils.clamp(c.rel + delta, 0.0, 5.0)
    if before < R.unlockConnections and c.rel >= R.unlockConnections then
        local cfg = Config.Customers[cid]
        local names = {}
        for _, l in ipairs(cfg.links or {}) do
            if Config.Customers[l] and not (P.customers[l] and P.customers[l].u) then names[#names + 1] = Config.Customers[l].name end
        end
        if #names > 0 then
            Messages.push(src, cid, { f = 'them', m = ('You know what, my friends %s could use you too. Swing by with a sample.'):format(table.concat(names, ', ')) })
        end
    end
end

--[[ ─────────────── samples ─────────────── ]]

--- phone: mark a customer as the sample target (blip + ped at their spot)
Guard.callback('nzde:cust:sampleTarget', function(src, cid)
    local P = Profile.get(src)
    if not P then return false end
    if cid == false then P.sample = nil Profile.sync(src) return true end
    if not Customers.sampleable(P, cid) then return false, 'Not available' end
    local cfg = Config.Customers[cid]
    P.sample = { cid = cid, spot = cfg.home, name = cfg.name, model = cfg.model }
    Profile.dirty(src)
    Profile.sync(src)
    return true
end)

local function sampleChance(P, cid, pid, q)
    local cfg = Config.Customers[cid]
    local p = Products.get(pid)
    if not p then return 0 end
    if not Utils.contains(cfg.buys, Mix.kind(p.base)) then return 0.05 end
    local chance = 0.45 + 0.15 * Mix.matches(p.effects, cfg.favorites) + 0.15 * (q - Utils.standards(cfg.standards).minQuality)
    return Utils.clamp(chance, 0.1, 0.95)
end

Guard.callback('nzde:cust:sample', function(src, pid, q)
    local P = Profile.get(src)
    if not P or not P.sample or not Guard.rate(src, 'sample', 3000) then return false end
    local cid = P.sample.cid
    local cfg = Config.Customers[cid]
    local spot = Config.Spots[cfg.home]
    if not Guard.near(src, spot.coords, D.handoverDistance + 4.0) then return false end
    if not Customers.sampleable(P, cid) then return false end
    q = math.floor(tonumber(q) or 2)
    if not Products.takePackaged(src, pid, 1, q) then return false, 'You need a bagged product' end
    local chance = sampleChance(P, cid, pid, q)
    local first = (P.stats.samples or 0) == 0
    P.sample = nil
    local c = cstate(P, cid)
    if first or math.random() < chance then
        P.stats.samples = (P.stats.samples or 0) + 1
        Customers.unlock(src, cid)
        Products.discover(src, pid)
        Quests.progress(src, 'sample')
        Profile.addXp(src, Config.Ranks.xp.sample, 'New customer')
        Profile.sync(src)
        return true, { ok = true, name = cfg.name }
    end
    c.cool = os.time() + 10 * 60
    Profile.dirty(src)
    Profile.sync(src)
    return true, { ok = false, name = cfg.name }
end)

--[[ ─────────────── deal requests ─────────────── ]]

local function openCount(P, cid)
    local n, mine = 0, false
    for _, d in ipairs(P.deals) do
        n = n + 1
        if d.cid == cid then mine = true end
    end
    return n, mine
end

local function pickProduct(P, cfg)
    local best, bestScore
    for pid, mine in pairs(P.products) do
        local p = Products.get(pid)
        if p and Utils.contains(cfg.buys, Mix.kind(p.base)) then
            local score = Mix.matches(p.effects, cfg.favorites) * 2 + Mix.value(p.base, p.effects) / 100 + math.random()
            if not bestScore or score > bestScore then best, bestScore = pid, score end
        end
    end
    return best
end

local function spotFor(cfg)
    local list = {}
    for id, s in pairs(Config.Spots) do
        if s.region == cfg.region then list[#list + 1] = id end
    end
    table.sort(list)
    return #list > 0 and Utils.pick(list) or cfg.home
end

--- one deal request for a player, if anyone wants something
function Customers.request(src)
    local P = Profile.get(src)
    if not P or not P.story.app then return false end
    if openCount(P) >= D.maxOpen then return false end
    local level = Profile.level(P)
    local candidates = {}
    for cid, c in pairs(P.customers) do
        local cfg = Config.Customers[cid]
        local _, busy = openCount(P, cid)
        if cfg and c.u and not c.dealer and not busy and Utils.regionUnlocked(cfg.region, level) and (os.time() - (c.last or 0)) > 5 * 60 then
            candidates[#candidates + 1] = cid
        end
    end
    if #candidates == 0 then return false end
    local cid = Utils.pick(candidates)
    local cfg, c = Config.Customers[cid], cstate(P, cid)
    local pid = pickProduct(P, cfg)
    if not pid then return false end

    local value = Products.value(pid)
    local std = Utils.standards(cfg.standards)
    local qty = 1 + math.floor((c.add or 0) * 4) + math.random(0, 2)
    local budget = cfg.budget * (0.8 + c.rel * 0.1) * (1.0 + (c.add or 0))
    qty = Utils.clamp(math.min(qty, math.floor(budget / math.max(1, value))), 1, 12)
    local ask = P.products[pid] and P.products[pid].price or value
    local price = math.floor(math.min(ask, value * 1.3) * qty * std.spend * (0.92 + math.random() * 0.16) + 0.5)

    local deal = {
        id = Profile.nextId(P, 'd'), cid = cid, pid = pid, qty = qty, price = price,
        spot = spotFor(cfg), exp = os.time() + D.windowMinutes * 60, state = 'offer',
    }
    P.deals[#P.deals + 1] = deal
    Profile.dirty(src)
    local lines = {
        "Yo, can you do %dx %s? %s. I've got %s.",
        "Need %dx %s. Meet me %s? %s cash.",
        "You around? %dx %s, %s. Paying %s.",
    }
    local spotLabel = Config.Spots[deal.spot].label:lower()
    Messages.push(src, cid, { f = 'them', m = Utils.pick(lines):format(qty, Products.label(pid), spotLabel, Utils.money(price)), deal = deal.id })
    return true
end

local function findDeal(P, id)
    for i, d in ipairs(P.deals) do
        if d.id == id then return d, i end
    end
end

local function closeDeal(P, id)
    local _, i = findDeal(P, id)
    if i then table.remove(P.deals, i) end
end

Guard.callback('nzde:deal:respond', function(src, id, answer, counter)
    local P = Profile.get(src)
    local d = P and findDeal(P, id)
    if not d or d.state ~= 'offer' or not Guard.rate(src, 'deal', 600) then return false end
    local cfg = Config.Customers[d.cid]
    if answer == 'accept' then
        d.state = 'accepted'
        Messages.push(src, d.cid, { f = 'me', m = "Deal. See you there." }, false)
        Messages.push(src, d.cid, { f = 'them', m = "Cool. Don't be late." }, false)
    elseif answer == 'counter' then
        if d.countered then return false, 'Already countered' end
        local price = math.floor(tonumber(counter) or 0)
        if price < 1 then return false end
        d.countered = true
        local greed = price / d.price
        local chance = greed <= 1.0 and 1.0 or Utils.clamp(D.counterSuccess * (2.0 - greed) * (0.8 + cstate(P, d.cid).rel * 0.08), 0.0, 0.95)
        Messages.push(src, d.cid, { f = 'me', m = ('How about %s?'):format(Utils.money(price)) }, false)
        if math.random() < chance then
            d.price = price
            d.state = 'accepted'
            Messages.push(src, d.cid, { f = 'them', m = "Ugh, fine. See you there." }, false)
        else
            closeDeal(P, id)
            relBump(src, P, d.cid, -0.05)
            Messages.push(src, d.cid, { f = 'them', m = "Nah, forget it." }, false)
        end
    else
        closeDeal(P, id)
        relBump(src, P, d.cid, -0.05)
        Messages.push(src, d.cid, { f = 'me', m = "Can't today." }, false)
        Messages.push(src, d.cid, { f = 'them', m = "Whatever." }, false)
    end
    Profile.dirty(src)
    Profile.sync(src)
    return true, { state = (findDeal(P, id) or {}).state or 'closed', cid = cfg and d.cid }
end)

--- the hand-over at the meeting spot
Guard.callback('nzde:deal:handover', function(src, id, q)
    local P = Profile.get(src)
    local d = P and findDeal(P, id)
    if not d or d.state ~= 'accepted' or not Guard.rate(src, 'handover', 2000) then return false end
    local spot = Config.Spots[d.spot]
    if not Guard.near(src, spot.coords, D.handoverDistance + 4.0) then return false, 'Too far away' end
    local cfg = Config.Customers[d.cid]
    local std = Utils.standards(cfg.standards)
    q = math.floor(tonumber(q) or 0)
    local lowest = Products.takePackaged(src, d.pid, d.qty, q)
    if not lowest then return false, ('You need %dx %s bagged'):format(d.qty, Products.label(d.pid)) end
    closeDeal(P, id)

    local c = cstate(P, d.cid)
    local p = Products.get(d.pid)
    local late = os.time() > d.exp
    local happy = lowest >= std.minQuality and not late
    local delta = happy and (R.perDeal + R.perFavorite * Mix.matches(p.effects, cfg.favorites)) or R.badDeal
    relBump(src, P, d.cid, delta)
    c.add = math.min(1.0, (c.add or 0) + Mix.addictiveness(p.base, p.effects) * 0.1)
    c.last = os.time()

    Inv.payMoney(src, d.price, nil, 'drugempire-deal')
    P.stats.sold = P.stats.sold + d.qty
    P.stats.earned = P.stats.earned + d.price
    P.stats.deals = P.stats.deals + 1
    Profile.dirty(src)
    Quests.progress(src, 'deal')
    Profile.addXp(src, Config.Ranks.xp.deal + d.qty, 'Deal')
    Messages.push(src, d.cid, { f = 'them', m = happy and Utils.pick({ 'Pleasure doing business.', 'Good stuff. Thanks.', "That's the one." }) or "This isn't what I'm used to..." }, false)
    if math.random(100) <= D.alertChance then
        Dispatch.alert(src, { coords = spot.coords, title = 'Suspicious hand-off', message = ('Possible drug deal reported: %s.'):format(spot.label), code = '10-31' })
    end
    if Logs then Logs.send('Deal', ('%s sold %dx %s to %s for %s'):format(P.name or src, d.qty, p.name, cfg.name, Utils.money(d.price))) end
    Profile.sync(src)
    return true, { price = d.price, happy = happy, name = cfg.name }
end)

--- what the player can hand over for a deal / sample (packaged units by product + quality)
Guard.callback('nzde:cust:stock', function(src)
    local out = {}
    for pid, byQ in pairs(Products.packaged(src)) do
        for q, n in pairs(byQ) do
            local p = Products.get(pid)
            out[#out + 1] = { pid = pid, q = q, n = n, name = p.name, effects = p.effects, base = p.base }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end)

--- heartbeat: expire offers / missed deals, maybe text a new request
function Customers.tick(src)
    local P = Profile.get(src)
    if not P or not P.story.app then return end
    local now = os.time()
    local changed = false
    for i = #P.deals, 1, -1 do
        local d = P.deals[i]
        if d.state == 'offer' and now > d.exp then
            table.remove(P.deals, i)
            changed = true
        elseif d.state == 'accepted' and now > d.exp + D.lateGrace * 60 then
            table.remove(P.deals, i)
            relBump(src, P, d.cid, R.missed)
            Messages.push(src, d.cid, { f = 'them', m = "You never showed. Not cool." })
            changed = true
        end
    end
    P.nextDeal = P.nextDeal or (now + 60)
    if now >= P.nextDeal then
        P.nextDeal = now + Utils.range(D.requestEvery) * 60
        if Customers.request(src) then changed = true end
    end
    if changed then
        Profile.dirty(src)
        Profile.sync(src)
    end
end

--- contacts view for the app
function Customers.view(P)
    local out = {}
    for cid, cfg in pairs(Config.Customers) do
        local c = P.customers[cid]
        local unlocked = c and c.u
        local available = not unlocked and Customers.sampleable(P, cid)
        if unlocked or available then
            out[#out + 1] = {
                id = cid, name = cfg.name, region = cfg.region, home = cfg.home, standards = cfg.standards,
                favorites = cfg.favorites, buys = cfg.buys, links = cfg.links,
                unlocked = unlocked == true, rel = c and c.rel or R.start, add = c and c.add or 0,
                dealer = c and c.dealer, target = P.sample and P.sample.cid == cid,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.unlocked ~= b.unlocked then return a.unlocked end
        return a.name < b.name
    end)
    return out
end

function Customers.dealsView(P)
    local out = {}
    for _, d in ipairs(P.deals) do
        local cfg = Config.Customers[d.cid]
        out[#out + 1] = {
            id = d.id, cid = d.cid, name = cfg and cfg.name, pid = d.pid, product = Products.label(d.pid), qty = d.qty,
            price = d.price, spot = d.spot, spotLabel = Config.Spots[d.spot] and Config.Spots[d.spot].label, exp = d.exp,
            state = d.state, countered = d.countered,
        }
    end
    return out
end

-- asking price per product (phone)
Guard.callback('nzde:product:price', function(src, pid, price)
    local P = Profile.get(src)
    if not P or not P.products[pid] then return false end
    price = math.floor(tonumber(price) or 0)
    local value = Products.value(pid)
    if price < 1 or price > value * 3 then return false, 'That price is unrealistic' end
    P.products[pid].price = price
    Profile.dirty(src)
    return true
end)
