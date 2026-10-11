--[[
    Supply storage: each job shop's own parts stock.
      Filled by "Deliver now" orders (after the delivery timer) and supply runs (carried in by hand).
      Emptied by work orders (PartSource 'supply' / 'both') or by mechanics taking parts out ('inventory').
]]

Stock = {}

local ST = Config.Storage
local cache = {}          -- [shop] = { [item] = qty }
local labels = {}
for _, it in ipairs(Config.Supplier.Items) do labels[it.item] = it end

CreateThread(function()
    while not DB.Ready do Wait(250) end
    for _, r in ipairs(MySQL.query.await('SELECT shop, item, qty FROM nz_tuning_stock WHERE qty > 0') or {}) do
        cache[r.shop] = cache[r.shop] or {}
        cache[r.shop][r.item] = r.qty
    end
end)

function Stock.Count(shop, item) return (cache[shop] or {})[item] or 0 end

local function set(shop, item, qty)
    cache[shop] = cache[shop] or {}
    cache[shop][item] = qty > 0 and qty or nil
    MySQL.insert('INSERT INTO nz_tuning_stock (shop, item, qty) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE qty = VALUES(qty)', { shop, item, qty })
end

-- tell everyone working there to refresh the storage app
local function ping(shop)
    local s = Config.Shops[shop]
    if not s or not s.job then return end
    for _, src in ipairs(Bridge.GetPlayersWithJob(s.job, false)) do
        TriggerClientEvent('nayzeee-tuning:stockChanged', src, shop)
    end
end
Stock.Ping = ping

function Stock.Add(shop, item, n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return 0 end
    local now = Stock.Count(shop, item)
    local add = math.min(n, ST.Max - now)
    if add > 0 then set(shop, item, now + add) end
    return add
end

-- takes every count in needs ({ item = count }) or nothing; returns ok, missing list
function Stock.Take(shop, needs)
    local missing = {}
    for item, count in pairs(needs) do
        local have = Stock.Count(shop, item)
        if have < count then missing[#missing + 1] = { item = item, label = Bridge.ItemLabel(item), need = count, have = have } end
    end
    if #missing > 0 then return false, missing end
    for item, count in pairs(needs) do set(shop, item, Stock.Count(shop, item) - count) end
    ping(shop)
    return true
end

--------------------------------------------------------------------- deliveries ("Deliver now")

function Stock.QueueDelivery(src, shop, lines, total)
    local mins = Config.Supplier.DeliveryMinutes or 0
    local name = Bridge.GetName(src)
    if mins <= 0 then
        for item, qty in pairs(lines) do Stock.Add(shop, item, qty) end
        MySQL.insert('INSERT INTO nz_tuning_supply (shop, identifier, name, items, total, status, kind) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { shop, Bridge.GetIdentifier(src), name, json.encode(lines), total, 'delivered', 'delivery' })
        ping(shop)
        return 0
    end
    local eta = os.time() + mins * 60
    MySQL.insert.await('INSERT INTO nz_tuning_supply (shop, identifier, name, items, total, status, kind, eta) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { shop, Bridge.GetIdentifier(src), name, json.encode(lines), total, 'transit', 'delivery', eta })
    ping(shop)
    return eta
end

local function arrive(row)
    local lines = DB.Decode(row.items, {})
    for item, qty in pairs(lines) do Stock.Add(row.shop, item, qty) end
    MySQL.update.await("UPDATE nz_tuning_supply SET status = 'delivered' WHERE id = ?", { row.id })
    local s = Config.Shops[row.shop]
    if s and s.job then
        for _, src in ipairs(Bridge.GetPlayersWithJob(s.job, false)) do
            Core.Notify(src, L('delivery_arrived', row.id), 'success')
        end
    end
    ping(row.shop)
end

CreateThread(function()
    while not DB.Ready do Wait(500) end
    while true do
        local rows = MySQL.query.await("SELECT id, shop, items FROM nz_tuning_supply WHERE status = 'transit' AND eta <= ?", { os.time() }) or {}
        for _, r in ipairs(rows) do arrive(r) end
        Wait(15000)
    end
end)

-- incoming deliveries and supply runs still on the road
function Stock.Incoming(shop)
    local rows = MySQL.query.await("SELECT id, kind, name, items, total, status, eta, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_supply WHERE shop = ? AND status IN ('transit','active') ORDER BY id DESC LIMIT 20", { shop }) or {}
    for _, r in ipairs(rows) do
        local lines, out = DB.Decode(r.items, {}), {}
        for item, qty in pairs(lines) do out[#out + 1] = { item = item, label = labels[item] and labels[item].label or Bridge.ItemLabel(item), qty = qty } end
        r.items = out
    end
    return rows, os.time()
end

--------------------------------------------------------------------- storage app

local function nearStorage(src, shop)
    local at = NZ.StorageOf(shop)
    if not at then return false end
    return #(GetEntityCoords(GetPlayerPed(src)) - at) <= ST.UseRadius + 1.0
end
Stock.Near = nearStorage

lib.callback.register('nayzeee-tuning:stock:list', function(src)
    local shop = Tablet.RankOf(src)
    if not ST.Enabled or not shop then return false, L('no_permission') end
    local items, have = {}, cache[shop] or {}
    local seen = {}
    for _, it in ipairs(Config.Supplier.Items) do
        seen[it.item] = true
        items[#items + 1] = { item = it.item, label = it.label, cat = it.cat, qty = have[it.item] or 0, carry = Bridge.ItemCount(src, it.item) }
    end
    for item, qty in pairs(have) do
        if not seen[item] then items[#items + 1] = { item = item, label = Bridge.ItemLabel(item), cat = 'Other', qty = qty, carry = Bridge.ItemCount(src, item) } end
    end
    local incoming, now = Stock.Incoming(shop)
    return true, {
        items = items, incoming = incoming, now = now, source = NZ.PartSource(shop), near = nearStorage(src, shop),
        canTake = Core.HasShopRank(src, shop, ST.TakeRank), canPut = ST.PutBack, hasPoint = Config.Shops[shop].storage ~= nil,
    }
end)

lib.callback.register('nayzeee-tuning:stock:take', function(src, item, qty)
    if not Core.Throttle(src, 'stock', 600) then return false, L('slow_down') end
    local shop = Tablet.RankOf(src)
    qty = math.floor(tonumber(qty) or 0)
    if not ST.Enabled or not shop or not Core.HasShopRank(src, shop, ST.TakeRank) then return false, L('no_permission') end
    if type(item) ~= 'string' or qty < 1 or qty > 50 then return false, L('amount_invalid') end
    if not nearStorage(src, shop) then return false, L('storage_too_far') end
    if Stock.Count(shop, item) < qty then return false, L('storage_not_enough') end
    if not Bridge.AddItem(src, item, qty) then return false, L('pockets_full') end
    set(shop, item, Stock.Count(shop, item) - qty)
    Core.Log('order', 'Parts taken from storage', { Shop = Config.Shops[shop].label, Part = Bridge.ItemLabel(item), Amount = qty }, src)
    ping(shop)
    return true
end)

lib.callback.register('nayzeee-tuning:stock:put', function(src, item, qty)
    if not Core.Throttle(src, 'stock', 600) then return false, L('slow_down') end
    local shop = Tablet.RankOf(src)
    qty = math.floor(tonumber(qty) or 0)
    if not ST.Enabled or not ST.PutBack or not shop then return false, L('no_permission') end
    if type(item) ~= 'string' or qty < 1 or qty > 50 then return false, L('amount_invalid') end
    if not nearStorage(src, shop) then return false, L('storage_too_far') end
    if Bridge.ItemCount(src, item) < qty then return false, L('missing_item') end
    if Stock.Count(shop, item) + qty > ST.Max then return false, L('storage_full') end
    if not Bridge.RemoveItem(src, item, qty) then return false end
    Stock.Add(shop, item, qty)
    ping(shop)
    return true
end)
