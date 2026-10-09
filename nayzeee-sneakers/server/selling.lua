--[[
    Selling to NPC buyers through the Plug app.

    Offers  - buyers DM a price for one of your pairs (after "Find buyers", or now and then on their own)
    Deals   - accept an offer and you get a meet spot; the buyer walks or drives up
    Handover- the server settles it the moment the handover starts (paid, or a fake caught),
              then the client plays the cinematic for that result
]]

Selling = {}

local S, B, LC, R = Config.Selling, Config.Buyers, Config.LegitCheck, Config.Rep
local offers = {}       -- [src] = { [id] = offer }
local deals = {}        -- [src] = deal
local findWait = {}     -- [src] = { [serial] = os.time() when they can post it again }
local cooldown = {}     -- [src] = os.time() when they can take the next deal
local nextId = 0

local function newId() nextId = nextId + 1 return nextId end
local function pick(list) return list[math.random(1, #list)] end
local function rnd(range) return range[1] + math.random() * (range[2] - range[1]) end

--------------------------------------------------------------------------------
-- What a pair is worth
--------------------------------------------------------------------------------

--- The pair's value before the buyer's own multiplier
function Selling.Value(meta, boxed)
    local shoe = Config.Shoes[meta.shoe]
    if not shoe then return 0 end
    local v = (shoe.retail or 200) * Hype.Get(shoe.model)
    v = v * (S.Condition[meta.condition] or 0.5)
    v = v * (1.0 - math.min(100, tonumber(meta.dirt) or 0) / 100 * S.DirtPenalty)
    if not boxed then v = v * S.NoBox end
    local popular = false
    for _, size in ipairs(S.PopularSizes[shoe.gender == 'female' and 'female' or 'male']) do
        if size == tostring(meta.size) then popular = true end
    end
    return v * (popular and S.SizeBonus or S.SizeMalus)
end

local function repMult(rep) return 1.0 + (rep / R.Max) * R.PriceBonus end
local function round5(n) return math.max(5, math.floor(n / 5 + 0.5) * 5) end

--------------------------------------------------------------------------------
-- The player's pairs (loose and boxed), found by serial
--------------------------------------------------------------------------------

local function allPairs(src)
    local out = {}
    for _, name in ipairs({ Config.Items.shoes, Config.Items.boxed }) do
        for _, it in ipairs(Inv.List(src, name)) do
            if it.metadata and Config.Shoes[it.metadata.shoe] then
                out[#out + 1] = { slot = it.slot, item = name, boxed = name == Config.Items.boxed, meta = Items.Clean(it.metadata) }
            end
        end
    end
    return out
end

local function findPair(src, serial)
    for _, p in ipairs(allPairs(src)) do
        if p.meta.serial == serial then return p end
    end
end

--------------------------------------------------------------------------------
-- Offers
--------------------------------------------------------------------------------

local function weightedBuyer(pair)
    local pool, total = {}, 0
    for _, t in ipairs(B.Types) do
        local ok = (not t.boxed or pair.boxed) and (not t.ds or pair.meta.condition == 'DS')
        if ok then pool[#pool + 1] = t total = total + t.weight end
    end
    local r = math.random() * total
    for _, t in ipairs(pool) do
        r = r - t.weight
        if r <= 0 then return t end
    end
    return pool[#pool]
end

local function push(src)
    TriggerClientEvent('nayzeee-sneakers:client:plugUpdate', src)
end

local function makeOffer(src, pair)
    local t = weightedBuyer(pair)
    if not t then return end
    local shoe = Config.Shoes[pair.meta.shoe]
    local gender = math.random() < 0.5 and 'male' or 'female'
    if deals[src] and deals[src].offer.serial == pair.meta.serial then return end   -- already being sold
    local mult = rnd(t.offer) * repMult(Stats.Rep(src))
    local price = round5(Selling.Value(pair.meta, pair.boxed) * mult)
    local o = {
        id = newId(), serial = pair.meta.serial, shoe = pair.meta.shoe, size = pair.meta.size, boxed = pair.boxed,
        pair = Shared.ShoeName(pair.meta), image = shoe.image .. (pair.boxed and '_box' or ''),
        buyer = { name = pick(B.Names), type = t.id, label = t.label, gender = gender, check = t.check, drive = math.random() < t.drive },
        price = price, mult = mult, expires = os.time() + S.OfferLife,
    }
    local list = offers[src] or {}
    offers[src] = list
    -- full: the one closest to expiring makes room
    local count, oldest = 0, nil
    for _, x in pairs(list) do
        count = count + 1
        if not oldest or x.expires < oldest.expires then oldest = x end
    end
    if count >= S.MaxOffers and oldest then list[oldest.id] = nil end
    list[o.id] = o
    Bridge.PhoneMessage(src, Config.Text.offerIn:format(o.buyer.name, o.pair, lib.math.groupdigits(price)), o.buyer.name)
    return o
end

local function cleanOffers(src)
    local list, now = offers[src], os.time()
    if not list then return {} end
    local out = {}
    for id, o in pairs(list) do
        if o.expires <= now then list[id] = nil else out[#out + 1] = o end
    end
    table.sort(out, function(a, b) return a.expires > b.expires end)
    return out
end

lib.callback.register('nayzeee-sneakers:plugFind', function(src, serial)
    local pair = findPair(src, serial)
    if not pair then return false, Config.Text.pairGone end
    if deals[src] and deals[src].offer.serial == serial then return false, Config.Text.dealBusy end
    findWait[src] = findWait[src] or {}
    if (findWait[src][serial] or 0) > os.time() then return false, Config.Text.findCooldown end
    findWait[src][serial] = os.time() + S.FindCooldown

    local count = math.random(S.FindCount[1], S.FindCount[2])
    if R.MoreOffers and Stats.Rep(src) >= R.Max / 2 then count = count + 1 end
    SetTimeout(math.random(S.FindDelay[1], S.FindDelay[2]) * 1000, function()
        if GetPlayerPed(src) == 0 then return end
        local still = findPair(src, serial)
        if not still then return end
        for i = 1, count do
            SetTimeout((i - 1) * math.random(1500, 4000), function()
                if GetPlayerPed(src) ~= 0 and findPair(src, serial) then
                    makeOffer(src, still)
                    push(src)
                end
            end)
        end
    end)
    return true, findWait[src][serial]
end)

lib.callback.register('nayzeee-sneakers:plugDecline', function(src, id)
    if offers[src] then offers[src][id] = nil end
    return true
end)

-- buyers who DM on their own
if S.Passive.Enabled then
    CreateThread(function()
        while true do
            Wait(S.Passive.Every * 1000)
            for _, sid in ipairs(GetPlayers()) do
                local src = tonumber(sid)
                if math.random() < S.Passive.Chance then
                    local mine = allPairs(src)
                    if #mine > 0 then
                        makeOffer(src, pick(mine))
                        push(src)
                    end
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Deals
--------------------------------------------------------------------------------

local function meetFor(src)
    local pos = GetEntityCoords(GetPlayerPed(src))
    local fits, nearest, nearestD = {}, nil, nil
    for _, m in ipairs(Config.Meets) do
        local d = #(pos - m.coords.xyz)
        if d >= S.MeetDistance[1] and d <= S.MeetDistance[2] then fits[#fits + 1] = m end
        if not nearestD or d < nearestD then nearest, nearestD = m, d end
    end
    return #fits > 0 and pick(fits) or nearest
end

local function endDeal(src, reason, repLoss)
    local d = deals[src]
    if not d then return end
    deals[src] = nil
    if repLoss and repLoss > 0 then Stats.Add(src, { rep = -repLoss }) end
    TriggerClientEvent('nayzeee-sneakers:client:dealEnd', src, reason)
    push(src)
end

lib.callback.register('nayzeee-sneakers:plugAccept', function(src, id)
    if Bridge.Framework == 'none' then return false, 'No framework running: sales can\'t pay out' end
    if deals[src] then return false, Config.Text.dealBusy end
    if (cooldown[src] or 0) > os.time() then return false, Config.Text.dealCooldown end
    local o = offers[src] and offers[src][id]
    if not o or o.expires <= os.time() then return false, Config.Text.dealGone end
    if not findPair(src, o.serial) then
        offers[src][id] = nil
        return false, Config.Text.pairGone
    end
    -- that pair is spoken for: drop every other offer on it
    for oid, x in pairs(offers[src]) do if x.serial == o.serial then offers[src][oid] = nil end end

    local meet = meetFor(src)
    local deal = {
        id = o.id, offer = o, meet = { label = meet.label, x = meet.coords.x, y = meet.coords.y, z = meet.coords.z, w = meet.coords.w },
        expires = os.time() + S.DealTime, left = S.DealTime,
        ped = pick(B.Models[o.buyer.gender]), car = o.buyer.drive and pick(B.Cars) or nil, idle = pick(B.Idle),
    }
    deals[src] = deal
    Bridge.PhoneMessage(src, Config.Text.dealText:format(o.pair, o.size, meet.label), o.buyer.name)
    TriggerClientEvent('nayzeee-sneakers:client:deal', src, deal)
    push(src)
    return true
end)

lib.callback.register('nayzeee-sneakers:plugCancel', function(src)
    if not deals[src] then return false end
    endDeal(src, 'cancelled', S.CancelRep)
    return true
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for src, d in pairs(deals) do
            if d.expires <= now and not d.settling then
                Bridge.Notify(src, Config.Text.dealExpired:format(d.offer.buyer.name), 'error')
                endDeal(src, 'expired', S.CancelRep)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    offers[src], deals[src], findWait[src], cooldown[src] = nil, nil, nil, nil
end)

--------------------------------------------------------------------------------
-- Handover: settle it, then the client plays it out
--------------------------------------------------------------------------------

local function xpFor(price)
    return math.min(S.XP.Max, S.XP.Base + math.floor(price / 100) * S.XP.Per100)
end

lib.callback.register('nayzeee-sneakers:handover', function(src, dealId)
    local d = deals[src]
    if not d or d.id ~= dealId or d.settling then return nil end
    local meet = vector3(d.meet.x, d.meet.y, d.meet.z)
    local pos = GetEntityCoords(GetPlayerPed(src))
    if #(pos - meet) > 40.0 then
        Bridge.Notify(src, Config.Text.tooFar, 'error')
        return nil
    end
    local o = d.offer
    local pair = findPair(src, o.serial)
    if not pair then
        Bridge.Notify(src, Config.Text.pairGone, 'error')
        endDeal(src, 'gone')
        return nil
    end
    local t
    for _, x in ipairs(B.Types) do if x.id == o.buyer.type then t = x end end
    t = t or B.Types[1]

    -- the pair has to be what they were offered for: same box state, and still DS for a buyer who only wants DS
    if pair.boxed ~= o.boxed or (t.ds and pair.meta.condition ~= 'DS') then
        Bridge.Notify(src, Config.Text.pairChanged, 'error')
        endDeal(src, 'changed', S.CancelRep)
        return nil
    end
    -- worn or dirtied since the offer: the price only ever goes down
    o.price = math.min(o.price, round5(Selling.Value(pair.meta, pair.boxed) * (o.mult or 1.0)))
    d.settling = true
    local fake = pair.meta.real == false
    local checked = math.random() < t.check
    local serialRun = checked and math.random() < t.serial
    local caught = false
    if fake and checked then
        if serialRun and not Shared.SerialValid(pair.meta.serial) then
            caught = true
        else
            local quality = tonumber(pair.meta.quality) or 50
            caught = math.random() < (t.eye * (100 - quality) / 100 + LC.Floor)
        end
    end

    local res = {
        verdict = caught and 'caught' or 'sold', checked = checked, serial = serialRun,
        price = o.price, pair = o.pair, image = Config.Shoes[pair.meta.shoe].image, boxed = pair.boxed,
        box = Shared.BoxTypeForShoe(pair.meta.shoe), buyer = o.buyer.name, xp = 0, rep = 0,
    }

    if caught then
        local s = Stats.Add(src, { rep = -LC.Caught.Rep, caught = 1 })
        res.rep, res.repNow = -LC.Caught.Rep, s and s.rep
        res.police = math.random() < LC.Caught.Police
        res.aggressive = math.random() < LC.Caught.Aggressive
        if res.police then
            Bridge.Dispatch({ title = Config.Text.alertTitle, message = Config.Text.alertFake, coords = meet, src = src })
        end
        Logs.Send('Fake caught', { { 'Player', Logs.Who(src) }, { 'Pair', o.pair }, { 'Serial', o.serial }, { 'Buyer', ('%s (%s)'):format(o.buyer.name, t.label) }, { 'Police', res.police and 'called' or 'no' } }, 0xE5484D)
    else
        if not Inv.Remove(src, pair.item, 1, pair.slot) then
            d.settling = false
            return nil
        end
        Bridge.AddMoney(src, S.Account, o.price, 'nayzeee-sneakers sale')
        local gain = fake and LC.FakeSoldRep or R.PerSale
        local s = Stats.Add(src, { rep = gain, sold = 1, earned = o.price, fakesSold = fake and 1 or 0 })
        res.rep, res.repNow = gain, s and s.rep
        res.xp = xpFor(o.price)
        XP.Add(src, res.xp)
        Logs.Send('Pair sold', { { 'Player', Logs.Who(src) }, { 'Pair', o.pair }, { 'Price', '$' .. o.price }, { 'Real', fake and 'no (got through)' or 'yes' }, { 'Buyer', ('%s (%s)'):format(o.buyer.name, t.label) } })
    end

    -- a passer-by might call it in either way
    if not res.police and math.random() < Config.SellPolice.TipOff then
        Bridge.Dispatch({ title = Config.Text.alertTitle, message = Config.Text.alertTip, coords = meet, src = src })
    end

    deals[src] = nil
    cooldown[src] = os.time() + S.Cooldown
    push(src)
    return res
end)

--------------------------------------------------------------------------------
-- The app's data
--------------------------------------------------------------------------------

lib.callback.register('nayzeee-sneakers:plugData', function(src)
    local stash = {}
    local waits = findWait[src] or {}
    for _, p in ipairs(allPairs(src)) do
        local shoe = Config.Shoes[p.meta.shoe]
        local v = Selling.Value(p.meta, p.boxed) * repMult(Stats.Rep(src))
        stash[#stash + 1] = {
            serial = p.meta.serial, name = shoe.label, colourway = shoe.colourway, size = p.meta.size,
            image = shoe.image .. (p.boxed and '_box' or ''), boxed = p.boxed, real = p.meta.real ~= false,
            quality = p.meta.quality, condition = p.meta.condition, conditionLabel = Shared.ConditionLabel(p.meta.condition),
            dirt = math.floor(tonumber(p.meta.dirt) or 0),
            low = round5(v * 0.8), high = round5(v * 1.3),
            wait = math.max(0, (waits[p.meta.serial] or 0) - os.time()),
        }
    end
    table.sort(stash, function(a, b) return a.high > b.high end)

    local xp = XP.Get(src)
    local level, from, to = Shared.LevelFor(xp)
    local st = Stats.Get(src)
    local hype = Hype.Board()
    local d = deals[src]
    return {
        stash = stash,
        offers = cleanOffers(src),
        deal = d and { id = d.id, offer = d.offer, meet = d.meet, left = d.expires - os.time() } or nil,
        profile = { level = level, xp = xp, from = from, to = to, rep = st.rep, repMax = R.Max,
                    sold = st.sold, earned = st.earned, caught = st.caught, made = st.made, cleaned = st.cleaned },
        hype = Config.Hype.Enabled and hype or {}, trending = Config.Hype.Trending,
        props = Config.Studio.PropsResource,
        now = os.time(),
    }
end)
