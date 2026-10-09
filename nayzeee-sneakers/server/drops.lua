--[[
    Limited drops (Config.Drops).

    announce ─▶ raffle (Config.Drops.Raffle min) ─▶ live: winners collect at the store (Claim min),
    leftovers go to whoever walks in first ─▶ done (sold out or the claim time is up)

    GlobalState.nzsDrop holds what everyone can see (shoe, price, stock, phase, times); who entered
    and who won stays on the server and goes to each player on its own (Drops.View).
]]

Drops = {}

local D = Config.Drops
local current = nil       -- the drop that's on, or nil
local nextAt = 0
local counter = 0

local function rand(range) return math.random(range[1], range[2]) end
local function round5(n) return math.max(5, math.floor(n / 5 + 0.5) * 5) end

local function publish()
    if not current then GlobalState.nzsDrop = nil return end
    local c = current
    GlobalState.nzsDrop = {
        id = c.id, shoe = c.shoe, label = c.label, colourway = c.colourway, image = c.image, price = c.price,
        stock = c.stock, left = c.stock - c.sold, phase = c.phase, closeAt = c.closeAt, claimUntil = c.claimUntil,
        entries = c.entryCount, store = D.Store.label,
    }
    TriggerClientEvent('nayzeee-sneakers:client:plugUpdate', -1)
end

local function textAll(text)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        Bridge.PhoneMessage(src, text, Config.Text.dropFrom)
    end
end

local function pool()
    local out = {}
    if D.Pool then
        for _, id in ipairs(D.Pool) do
            local s = Config.Shoes[id]
            if s and not s.hidden then out[#out + 1] = id end
        end
    else
        for id, s in pairs(Config.Shoes) do
            if not s.hidden then out[#out + 1] = id end
        end
        table.sort(out)
    end
    return out
end

--- Starts a drop now. shoeId / stock are optional.
function Drops.Start(shoeId, stock)
    if current then return false, 'a drop is already on' end
    if not shoeId then
        local list = pool()
        if #list == 0 then return false, 'no shoes to drop' end
        shoeId = list[math.random(#list)]
    end
    local shoe = Config.Shoes[shoeId]
    if not shoe then return false, 'unknown shoe ' .. tostring(shoeId) end
    counter = counter + 1
    local now = os.time()
    current = {
        id = ('%x%x'):format(now, counter), shoe = shoeId, label = shoe.label, colourway = shoe.colourway,
        image = shoe.image, gender = shoe.gender, model = shoe.model,
        price = round5((shoe.retail or 300) * D.PriceMult), stock = math.max(1, tonumber(stock) or rand(D.Stock)), sold = 0,
        phase = 'raffle', closeAt = now + D.Raffle * 60, claimUntil = nil,
        entries = {}, entryCount = 0, winners = {}, claimed = {},
    }
    if Hype and Hype.Boost then Hype.Boost(shoe.model, D.HypeBoost) end
    publish()
    local msg = Config.Text.dropAnnounce:format(Shared.ShoeName({ shoe = shoeId }), current.stock, current.price, D.Raffle)
    textAll(msg)
    TriggerClientEvent('nayzeee-sneakers:client:dropNews', -1, 'announce', msg)
    Logs.Send('Limited drop', { { 'Shoe', Shared.ShoeName({ shoe = shoeId }) }, { 'Pairs', current.stock }, { 'Price', '$' .. current.price } })
    return true
end

function Drops.Stop()
    if not current then return false end
    current = nil
    nextAt = os.time() + rand(D.Every) * 60
    publish()
    return true
end

--- Raffle closes: draw the winners
local function draw()
    local c = current
    local list = {}
    for ident, e in pairs(c.entries) do list[#list + 1] = { ident = ident, src = e.src } end
    for i = #list, 2, -1 do local j = math.random(i) list[i], list[j] = list[j], list[i] end
    local won = 0
    for i, e in ipairs(list) do
        if i <= c.stock then
            c.winners[e.ident] = true
            won = won + 1
            if GetPlayerName(e.src) then
                Bridge.PhoneMessage(e.src, Config.Text.dropWon:format(c.label, D.Store.label, D.Claim), Config.Text.dropFrom)
                Bridge.Notify(e.src, Config.Text.dropWon:format(c.label, D.Store.label, D.Claim), 'success')
            end
        elseif GetPlayerName(e.src) then
            Bridge.PhoneMessage(e.src, Config.Text.dropLost:format(c.label), Config.Text.dropFrom)
        end
    end
    c.phase = 'live'
    c.claimUntil = os.time() + D.Claim * 60
    if won < c.stock then
        TriggerClientEvent('nayzeee-sneakers:client:dropNews', -1, 'walkin', Config.Text.dropWalkIn:format(c.stock - won, c.label, D.Store.label))
    end
    publish()
end

--- Pairs a walk-in can still buy (winners' pairs are held until the claim time is up)
local function walkInLeft(c)
    local held = 0
    if os.time() < (c.claimUntil or 0) then
        for ident in pairs(c.winners) do if not c.claimed[ident] then held = held + 1 end end
    end
    return c.stock - c.sold - held
end

--- What one player sees
function Drops.View(src)
    local c = current
    if not c then return nil end
    local ident = Bridge.GetIdentifier(src)
    return {
        id = c.id, shoe = c.shoe, label = c.label, colourway = c.colourway, image = c.image, price = c.price,
        stock = c.stock, left = c.stock - c.sold, walkIn = c.phase == 'live' and walkInLeft(c) or 0,
        phase = c.phase, closeAt = c.closeAt, claimUntil = c.claimUntil, entries = c.entryCount,
        entered = ident and c.entries[ident] ~= nil or false, won = ident and c.winners[ident] or false,
        claimed = ident and c.claimed[ident] or false, store = D.Store.label, account = D.Account,
    }
end

function Drops.Enter(src)
    local c = current
    if not c or c.phase ~= 'raffle' then return false, Config.Text.dropClosed end
    local ident = Bridge.GetIdentifier(src)
    if not ident then return false end
    if c.entries[ident] then return false, Config.Text.dropAlready end
    c.entries[ident] = { src = src }
    c.entryCount = c.entryCount + 1
    publish()
    return true, Config.Text.dropEntered:format(c.label)
end

local function atStore(src)
    local s = D.Store.coords
    return #(GetEntityCoords(GetPlayerPed(src)) - vector3(s.x, s.y, s.z)) < 6.0
end

--- Collect a won pair, or buy a leftover one, at the store
function Drops.Buy(src, size)
    local c = current
    if not c or c.phase ~= 'live' then return false, Config.Text.dropClosed end
    if not atStore(src) then return false, Config.Text.dropGoStore:format(D.Store.label) end
    local ident = Bridge.GetIdentifier(src)
    if not ident or c.claimed[ident] then return false, Config.Text.dropOnePer end
    local isWinner = c.winners[ident] and os.time() < c.claimUntil
    if not isWinner and walkInLeft(c) <= 0 then return false, Config.Text.dropSoldOut end
    local sizes = Config.Sizes[c.gender == 'female' and 'female' or 'male']
    local okSize = false
    for _, s in ipairs(sizes) do if s == tostring(size) then okSize = true end end
    if not okSize then return false end
    if not Bridge.RemoveMoney(src, D.Account, c.price, 'sneaker-drop') then return false, Config.Text.dropNoMoney:format(c.price) end
    local meta = Items.NewPair(c.shoe, size, true, 'DS')
    meta.limited = true
    meta.boxColour = D.BoxColour
    if not Items.GivePair(src, meta, true) then
        Bridge.AddMoney(src, D.Account, c.price, 'sneaker-drop-refund')
        return false, Config.Text.noSpace
    end
    c.claimed[ident] = true
    c.sold = c.sold + 1
    Logs.Send('Drop pair bought', { { 'Player', Logs.Who(src) }, { 'Pair', Shared.ShoeName(meta) }, { 'Price', '$' .. c.price }, { 'Raffle winner', isWinner and 'yes' or 'no' } })
    if c.sold >= c.stock then
        TriggerClientEvent('nayzeee-sneakers:client:dropNews', -1, 'soldout', Config.Text.dropSoldOutAll:format(c.label))
        Drops.Stop()
    else
        publish()
    end
    return true, Config.Text.dropBought:format(Shared.ShoeName(meta))
end

-- ------------------------------------------------------------------ callbacks

lib.callback.register('nayzeee-sneakers:dropView', function(src) return Drops.View(src) end)
lib.callback.register('nayzeee-sneakers:dropEnter', function(src) return Drops.Enter(src) end)
lib.callback.register('nayzeee-sneakers:dropBuy', function(src, size) return Drops.Buy(src, size) end)

RegisterCommand(D.Command or 'sneakerdrop', function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local reply = function(t) if src == 0 then print(t) else Bridge.Notify(src, t, 'inform') end end
    if args[1] == 'stop' then
        reply(Drops.Stop() and 'Drop ended' or 'No drop is on')
        return
    end
    local ok, why = Drops.Start(args[1], tonumber(args[2]))
    reply(ok and 'Drop started' or ('No drop: ' .. tostring(why)))
end, false)

-- ------------------------------------------------------------------ clock

CreateThread(function()
    GlobalState.nzsDrop = nil
    if not D.Enabled then return end
    nextAt = os.time() + rand(D.Every) * 60
    while true do
        Wait(15000)
        local now = os.time()
        local c = current
        if c then
            if c.phase == 'raffle' and now >= c.closeAt then
                draw()
            elseif c.phase == 'live' and now >= c.claimUntil then
                -- unclaimed winners' pairs went to walk-ins at claimUntil; give walk-ins a little longer, then close
                if walkInLeft(c) <= 0 or now >= c.claimUntil + D.Claim * 60 then
                    TriggerClientEvent('nayzeee-sneakers:client:dropNews', -1, 'over', Config.Text.dropOver:format(c.label))
                    Drops.Stop()
                end
            end
        elseif now >= nextAt and #GetPlayers() >= (D.MinPlayers or 1) then
            Drops.Start()
        end
    end
end)
