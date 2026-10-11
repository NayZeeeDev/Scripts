--[[
    Supply runs: buy parts cheaper, then go and fetch them with a box truck.
    Packages: warehouse -> van (crate) -> back at the shop: van -> supply storage (unload, store).
    The parts land in the shop's supply storage when the last package is stored.
]]

local SR = Config.SupplyRuns
local Runs = {}          -- [src] = run
local items = {}
for _, it in ipairs(Config.Supplier.Items) do items[it.item] = it end

local function truckOk(veh)
    if not veh then return false end
    local m = GetEntityModel(veh)
    for _, name in ipairs(SR.TruckModels) do if m == joaat(name) then return true end end
    return false
end

local function close(src, status, refundPct)
    local r = Runs[src]
    if not r then return end
    Runs[src] = nil
    MySQL.update('UPDATE nz_tuning_supply SET status = ? WHERE id = ?', { status, r.id })
    if refundPct and refundPct > 0 then
        local back = math.floor(r.total * refundPct / 100)
        if back > 0 then Core.ShopAdd(r.shop, back, 'refund', 'Supply run', ('Run %d %s'):format(r.id, status)) end
    end
    Stock.Ping(r.shop)
end

lib.callback.register('nayzeee-tuning:supply:start', function(src, cart)
    -- the run's parts go into supply storage, so it needs storage on
    if not SR.Enabled or not Config.Supplier.Enabled or not Config.Storage.Enabled then return false, L('no_permission') end
    if not Core.Throttle(src, 'supply', 2000) then return false, L('slow_down') end
    local shopId = Tablet.RankOf(src)
    if not shopId or not Core.HasShopRank(src, shopId, SR.MinRank) then return false, L('no_permission') end
    if Runs[src] then return false, L('supply_busy') end
    if type(cart) ~= 'table' then return false end
    local full, qtyTotal, lines = 0, 0, {}
    for item, qty in pairs(cart) do
        local it = items[item]
        qty = NZ.Int(qty, 0)
        if not it or qty < 1 or qty > Config.Supplier.MaxPerOrder then return false, L('amount_invalid') end
        if Stock.Count(shopId, item) + qty > Config.Storage.Max then return false, L('storage_full') end
        full = full + it.price * qty
        qtyTotal = qtyTotal + qty
        lines[item] = qty
    end
    if qtyTotal == 0 then return false end
    local maxQty = SR.MaxCrates * SR.ItemsPerCrate
    if qtyTotal > maxQty then return false, L('supply_too_much', maxQty) end
    local shop = Config.Shops[shopId]
    local drop, storage = Missions_DropOf(shopId), NZ.StorageOf(shopId)
    if not drop or not storage then return false, L('tow_no_drop') end
    local total = math.floor(full * (100 - SR.Discount) / 100)
    local name = Bridge.GetName(src)
    if not Core.ShopTake(shopId, total, 'supply', name, 'Supply run') then return false, L('shop_no_money') end
    local whIdx = math.random(1, #SR.Warehouses)
    local wh = SR.Warehouses[whIdx]
    local expires = os.time() + SR.TimeLimit * 60
    local id = MySQL.insert.await('INSERT INTO nz_tuning_supply (shop, identifier, name, items, total, kind, eta) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { shopId, Bridge.GetIdentifier(src), name, json.encode(lines), total, 'run', expires })
    local crates = NZ.Clamp(math.ceil(qtyTotal / SR.ItemsPerCrate), 1, SR.MaxCrates)
    Runs[src] = { id = id, shop = shopId, cart = lines, total = total, wh = whIdx, crates = crates,
        loaded = 0, unloaded = 0, stored = 0, carrying = false, last = 0, expires = expires }
    Core.Log('order', 'Supply run started', { Shop = shop.label, Paid = '$' .. total, Saved = '$' .. (full - total) }, src)
    Stock.Ping(shopId)
    return true, {
        id = id, crates = crates, total = total, saved = full - total, limit = SR.TimeLimit * 60,
        warehouse = { label = wh.label, crates = NZ.Plain(wh.crates), truck = NZ.Plain(wh.truck) },
        drop = NZ.Plain(drop), storage = NZ.Plain(storage), truckSpawn = NZ.Plain(shop.truckSpawn), shopLabel = shop.label,
    }
end)

local function paced(r)
    local now = GetGameTimer()
    if now - r.last < SR.LoadTime - 400 then return false end
    r.last = now
    return true
end

-- one package carried into the van at the warehouse
lib.callback.register('nayzeee-tuning:supply:crate', function(src, netId)
    local r = Runs[src]
    if not r or not paced(r) then return false end
    local wh = SR.Warehouses[r.wh]
    local veh = Core.VehicleFromNet(netId)
    local me = GetEntityCoords(GetPlayerPed(src))
    if not truckOk(veh) or #(me - GetEntityCoords(veh)) > 8.0 or #(me - wh.crates) > 60.0 then return false, L('supply_need_truck') end
    if r.loaded < r.crates then r.loaded = r.loaded + 1 end
    return true, r.loaded
end)

-- back at the shop: take one package out of the van
lib.callback.register('nayzeee-tuning:supply:unload', function(src, netId)
    local r = Runs[src]
    if not r or r.loaded < r.crates then return false, L('supply_not_loaded') end
    if r.carrying then return true, r.unloaded end
    if r.unloaded >= r.crates then return false end
    local drop = Missions_DropOf(r.shop)
    local veh = Core.VehicleFromNet(netId)
    local me = GetEntityCoords(GetPlayerPed(src))
    if not drop or not truckOk(veh) or #(GetEntityCoords(veh) - drop) > SR.DropRadius + 6.0 or #(me - GetEntityCoords(veh)) > 8.0 then
        return false, L('tow_not_at_drop')
    end
    r.unloaded, r.carrying = r.unloaded + 1, true
    return true, r.unloaded
end)

-- set the package down in supply storage; the last one puts every part in stock
lib.callback.register('nayzeee-tuning:supply:store', function(src)
    local r = Runs[src]
    if not r or not r.carrying then return false end
    if not paced(r) then return false end
    local at = NZ.StorageOf(r.shop)
    if not at or #(GetEntityCoords(GetPlayerPed(src)) - at) > Config.Storage.UseRadius + 2.0 then return false, L('storage_too_far') end
    r.carrying = false
    r.stored = r.stored + 1
    if r.stored < r.crates then return true, { stored = r.stored } end
    for item, qty in pairs(r.cart) do Stock.Add(r.shop, item, qty) end
    local id = r.id
    close(src, 'done')
    return true, { stored = r.stored, done = true, id = id }
end)

lib.callback.register('nayzeee-tuning:supply:cancel', function(src)
    if not Runs[src] then return false end
    close(src, 'cancelled', 100 - SR.CancelFee)
    return true, SR.CancelFee
end)

-- runs that were on the road when the server stopped are refunded like a cancelled run
CreateThread(function()
    while not DB.Ready or not Core.Ready do Wait(500) end
    local rows = MySQL.query.await("SELECT id, shop, total FROM nz_tuning_supply WHERE status = 'active' AND kind = 'run'") or {}
    for _, r in ipairs(rows) do
        MySQL.update.await("UPDATE nz_tuning_supply SET status = 'expired' WHERE id = ?", { r.id })
        local back = math.floor(r.total * (100 - SR.CancelFee) / 100)
        if back > 0 and Core.Shops[r.shop] then Core.ShopAdd(r.shop, back, 'refund', 'Supply run', ('Run %d expired (restart)'):format(r.id)) end
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for src, r in pairs(Runs) do
            if now > r.expires then
                close(src, 'expired', 100 - SR.CancelFee)
                Core.Notify(src, L('supply_expired', SR.CancelFee), 'error')
                TriggerClientEvent('nayzeee-tuning:supplyEnd', src)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Runs[src] then close(src, 'cancelled', 100 - SR.CancelFee) end
end)
