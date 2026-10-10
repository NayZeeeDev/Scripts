--[[
    Deliveries: order from a shop in the app, pick the box up at a dead drop (or inside
    the RV for a fee) once it's ready.

    P.orders = { { id, shop, items = { { item, count } }, total, ready, drop, done } }
]]

Deliveries = {}

local DC = Config.Deliveries

local function shopById(id)
    for _, s in ipairs(Config.Shops) do
        if s.id == id then return s end
    end
end

local function dropById(id)
    for _, d in ipairs(Config.DeadDrops) do
        if d.id == id then return d end
    end
end
Deliveries.drop = dropById

local function openOrders(P)
    local n = 0
    for _, o in ipairs(P.orders) do if not o.done then n = n + 1 end end
    return n
end

Guard.callback('nzde:order:place', function(src, shopId, cart, dropId, account)
    local P = Profile.get(src)
    local shop = shopById(shopId)
    if not P or not P.story.app or not shop or type(cart) ~= 'table' then return false end
    if openOrders(P) >= DC.maxOpen then return false, 'Too many open orders' end
    local level = Profile.level(P)
    local items, total = {}, 0
    for _, line in ipairs(shop.items) do
        local n = math.floor(tonumber(cart[line.item]) or 0)
        if n > 0 then
            if n > 100 then return false end
            if level < line.unlock then return false, Utils.itemLabel(line.item) .. ' is locked' end
            items[#items + 1] = { item = line.item, count = n }
            total = total + line.price * n
        end
    end
    if #items == 0 then return false, 'Your cart is empty' end
    local toRv = dropId == 'rv'
    if toRv then
        if not P.rv.owned then return false end
        total = total + DC.rvFee
    else
        local drop = dropById(dropId)
        if not drop or not Utils.regionUnlocked(drop.region, level) then return false, 'Pick a drop point' end
    end
    account = Utils.contains(Config.Money.shopAccounts, account) and account or Config.Money.shopAccounts[1]
    if not FW.removeMoney(src, account, total, 'drugempire-order') then return false, 'Not enough money' end
    local wait = Utils.range(toRv and DC.rvMinutes or DC.minutes)
    local order = { id = Profile.nextId(P, 'r'), shop = shopId, items = items, total = total, ready = os.time() + wait * 60, drop = dropId, done = false }
    P.orders[#P.orders + 1] = order
    while #P.orders > 12 do
        local removed = false
        for i, o in ipairs(P.orders) do
            if o.done then table.remove(P.orders, i) removed = true break end
        end
        if not removed then break end
    end
    Profile.dirty(src)
    Quests.progress(src, 'order')
    return true, { id = order.id, minutes = wait, total = total }
end)

Guard.callback('nzde:order:collect', function(src, id)
    local P = Profile.get(src)
    if not P or not Guard.rate(src, 'collect', 1500) then return false end
    local order
    for _, o in ipairs(P.orders) do if o.id == id then order = o break end end
    if not order or order.done or order.ready > os.time() then return false end
    if order.drop == 'rv' then
        local rec = RV.inside(src)
        if not rec or rec.owner ~= src then return false end
        local sp = RV.interiorCfg(rec.mode).spawn
        if not RV.nearPoint(src, sp, 4.0) then return false end
    else
        local drop = dropById(order.drop)
        if not drop or not Guard.near(src, drop.coords, DC.collectDistance + 3.0) then return false end
    end
    for _, it in ipairs(order.items) do
        if not Inv.canCarry(src, it.item, it.count) then return false, 'You can\'t carry all of it' end
    end
    order.done = true
    Profile.dirty(src)
    for _, it in ipairs(order.items) do Inv.add(src, it.item, it.count) end
    Profile.sync(src)
    return true
end)

--- ready orders that go to the RV (shown as a box inside)
function Deliveries.rvReady(src)
    local P = Profile.get(src)
    local out = {}
    for _, o in ipairs(P and P.orders or {}) do
        if not o.done and o.drop == 'rv' and o.ready <= os.time() then out[#out + 1] = o.id end
    end
    return out
end

function Deliveries.tick(src)
    local P = Profile.get(src)
    if not P then return end
    local now = os.time()
    for _, o in ipairs(P.orders) do
        if not o.done and not o.notified and o.ready <= now then
            o.notified = true
            local where = o.drop == 'rv' and 'in your RV' or ('at ' .. (dropById(o.drop) or { label = 'the drop' }).label)
            local shop = shopById(o.shop)
            TriggerClientEvent('nzde:text', src, { thread = 'deliveries', from = shop and shop.label or 'Delivery', text = 'Your order is ready ' .. where .. '.', app = true })
            Profile.dirty(src)
            Profile.sync(src)
        end
    end
end

function Deliveries.view(P)
    local level = Profile.level(P)
    local shops = {}
    for _, s in ipairs(Config.Shops) do
        local items = {}
        for _, line in ipairs(s.items) do
            items[#items + 1] = { item = line.item, label = Utils.itemLabel(line.item), price = line.price, unlock = line.unlock, locked = level < line.unlock, rank = Utils.rankLabel(line.unlock) }
        end
        shops[#shops + 1] = { id = s.id, label = s.label, icon = s.icon, desc = s.desc, items = items }
    end
    local drops = {}
    for _, d in ipairs(Config.DeadDrops) do
        drops[#drops + 1] = { id = d.id, label = d.label, region = d.region, locked = not Utils.regionUnlocked(d.region, level), x = d.coords.x, y = d.coords.y }
    end
    local orders = {}
    for i = #P.orders, 1, -1 do
        local o = P.orders[i]
        local shop = shopById(o.shop)
        local drop = o.drop == 'rv' and { label = 'Your RV' } or dropById(o.drop) or { label = '?' }
        orders[#orders + 1] = { id = o.id, shop = shop and shop.label or o.shop, items = o.items, total = o.total, ready = o.ready, drop = o.drop, dropLabel = drop.label, done = o.done }
    end
    return { shops = shops, drops = drops, orders = orders, rvFee = DC.rvFee, accounts = Config.Money.shopAccounts }
end
