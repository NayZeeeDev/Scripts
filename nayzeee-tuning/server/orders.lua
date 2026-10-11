Orders = {}

local ACTIVE = "('open','accepted','working')"

function Orders.Broadcast(shopId, kind, id, text)
    local shop = Config.Shops[shopId]
    if not shop or not shop.job or not Config.Business.NotifyMechanicsOnOrder then return end
    for _, src in ipairs(Bridge.GetPlayersWithJob(shop.job, true)) do
        TriggerClientEvent('nayzeee-tuning:orderEvent', src, { kind = kind, id = id, text = text, shop = shopId })
    end
end

local function load(id)
    local o = MySQL.single.await('SELECT * FROM nz_tuning_orders WHERE id = ?', { tonumber(id) or -1 })
    if not o then return nil end
    o.items = DB.Decode(o.items, {})
    o.props = DB.Decode(o.props, {})
    o.extras = DB.Decode(o.extras, {})
    o.totals = DB.Decode(o.totals, {})
    o.progress = DB.Decode(o.progress, {})
    return o
end

local function itemLabels(list)
    local out = {}
    for _, item in ipairs(list) do out[#out + 1] = { item = item, label = Bridge.ItemLabel(item) } end
    return out
end

local function public(o)
    local items = {}
    local wear = Vehicles.Get(o.plate).wear
    for i, it in ipairs(o.items) do
        local part = Config.Parts[it.id] or {}
        items[i] = { id = it.id, label = it.label, price = it.price, value = it.value, done = o.progress[it.id] == true,
            pile = part.pile, spot = part.spot, kind = part.kind, icon = part.icon,
            needs = itemLabels(NZ.RequiredItems(it.id, it.value, wear)) }
    end
    return {
        id = o.id, shop = o.shop, plate = o.plate, model = o.model, label = o.label, customer = o.customer_name,
        mechanic = o.mechanic_name, status = o.status, total = o.total, items = items, props = o.props,
        customerAvatar = Avatars.Of(o.customer), mechanicAvatar = Avatars.Of(o.mechanic),
        created = o.created_at,
    }
end

local function save(o, fields)
    local sets, vals = {}, {}
    for k, v in pairs(fields) do
        sets[#sets + 1] = ('`%s` = ?'):format(k)
        vals[#vals + 1] = type(v) == 'table' and json.encode(v) or v
        o[k] = v
    end
    vals[#vals + 1] = o.id
    MySQL.update.await(('UPDATE nz_tuning_orders SET %s WHERE id = ?'):format(table.concat(sets, ', ')), vals)
end

-- where each needed part comes from: pockets and / or supply storage (Config.Storage.PartSource)
-- returns plan { pockets = { item = n }, stock = { item = n } }, missing list, source
function Orders.PartPlan(src, o, line)
    local source = NZ.PartSource(o.shop)
    local needs = {}
    for _, item in ipairs(NZ.RequiredItems(line.id, line.value, Vehicles.Get(o.plate).wear)) do needs[item] = (needs[item] or 0) + 1 end
    local plan, missing = { pockets = {}, stock = {} }, {}
    for item, count in pairs(needs) do
        local pocket = source ~= 'supply' and Bridge.ItemCount(src, item) or 0
        local stock = source ~= 'inventory' and Stock.Count(o.shop, item) or 0
        local fromPocket = math.min(pocket, count)
        local fromStock = math.min(stock, count - fromPocket)
        if fromPocket > 0 then plan.pockets[item] = fromPocket end
        if fromStock > 0 then plan.stock[item] = fromStock end
        if fromPocket + fromStock < count then
            missing[#missing + 1] = { item = item, label = Bridge.ItemLabel(item), need = count, have = fromPocket + fromStock,
                stock = Stock.Count(o.shop, item) }
        end
    end
    return plan, missing, source
end

local function assignedTo(o, src)
    return o.mechanic ~= nil and o.mechanic == Bridge.GetIdentifier(src)
end

--------------------------------------------------------------------- lists

lib.callback.register('nayzeee-tuning:orders', function(src, shopId)
    if not Core.IsEmployee(src, shopId) then return {} end
    local rows = MySQL.query.await(('SELECT * FROM nz_tuning_orders WHERE shop = ? AND (status IN %s OR (status IN (\'done\',\'cancelled\') AND updated_at > NOW() - INTERVAL 2 DAY)) ORDER BY FIELD(status, \'working\', \'accepted\', \'open\', \'done\', \'cancelled\'), id DESC LIMIT 60'):format(ACTIVE), { shopId }) or {}
    local out = {}
    for _, o in ipairs(rows) do
        o.items = DB.Decode(o.items, {})
        o.progress = DB.Decode(o.progress, {})
        o.props, o.extras = {}, {}
        local p = public(o)
        p.mine = assignedTo(o, src)
        out[#out + 1] = p
    end
    return out
end)

lib.callback.register('nayzeee-tuning:myOrders', function(src)
    local id = Bridge.GetIdentifier(src)
    local rows = MySQL.query.await(('SELECT id, shop, plate, label, model, status, total, mechanic_name, items, progress FROM nz_tuning_orders WHERE customer = ? AND (status IN %s OR updated_at > NOW() - INTERVAL 1 DAY) ORDER BY id DESC LIMIT 20'):format(ACTIVE), { id }) or {}
    for _, r in ipairs(rows) do
        local items, prog = DB.Decode(r.items, {}), DB.Decode(r.progress, {})
        local done = 0
        for _, it in ipairs(items) do if prog[it.id] then done = done + 1 end end
        r.count, r.done, r.items, r.progress = #items, done, nil, nil
        r.shopLabel = Config.Shops[r.shop] and Config.Shops[r.shop].label or r.shop
    end
    return rows
end)

--------------------------------------------------------------------- mechanic flow

lib.callback.register('nayzeee-tuning:orderAccept', function(src, id)
    local o = load(id)
    if not o or not Core.IsEmployee(src, o.shop) then return false, L('no_permission') end
    if o.status ~= 'open' and not assignedTo(o, src) then return false, L('order_taken') end
    if o.status == 'open' then
        save(o, { status = 'accepted', mechanic = Bridge.GetIdentifier(src), mechanic_name = Bridge.GetName(src) })
        Orders.Broadcast(o.shop, 'accepted', o.id, Bridge.GetName(src))
        local cust = Bridge.GetSourceFromIdentifier(o.customer)
        if cust then Core.Notify(cust, L('order_accepted_customer', o.id, Bridge.GetName(src)), 'inform') end
    end
    return true, public(o)
end)

lib.callback.register('nayzeee-tuning:orderRelease', function(src, id)
    local o = load(id)
    if not o or not assignedTo(o, src) or o.status == 'done' or o.status == 'cancelled' then return false end
    MySQL.update.await("UPDATE nz_tuning_orders SET status = 'open', mechanic = NULL, mechanic_name = NULL WHERE id = ?", { o.id })
    Orders.Broadcast(o.shop, 'released', o.id, o.plate)
    return true
end)

-- the car must be the order's car and next to the mechanic
local function orderVehicle(src, o, netId)
    local veh = Core.VehicleFromNet(netId)
    if not veh then return nil, L('no_vehicle') end
    if NZ.TrimPlate(GetVehicleNumberPlateText(veh)) ~= NZ.TrimPlate(o.plate) then return nil, L('wrong_vehicle') end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > Config.Orders.MaxDistanceFromCar then return nil, L('too_far') end
    return veh
end

lib.callback.register('nayzeee-tuning:orderStart', function(src, id, netId)
    local o = load(id)
    if not o or not assignedTo(o, src) then return false, L('no_permission') end
    if o.status ~= 'accepted' and o.status ~= 'working' then return false, L('order_closed') end
    local veh, err = orderVehicle(src, o, netId)
    if not veh then return false, err end
    if o.status ~= 'working' then save(o, { status = 'working' }) end
    local shop = Config.Shops[o.shop]
    return true, { order = public(o), stockpiles = shop.stockpiles or {}, parts = shop.parts or {}, booths = shop.booths or {},
        physical = Config.Orders.PhysicalInstall and shop.stockpiles ~= nil, source = NZ.PartSource(o.shop),
        storage = NZ.Plain(NZ.StorageOf(o.shop)) }
end)

lib.callback.register('nayzeee-tuning:orderStep', function(src, id, itemId, netId)
    if not Core.Throttle(src, 'step', 1500) then return false end
    local o = load(id)
    if not o or not assignedTo(o, src) or o.status ~= 'working' then return false, L('no_permission') end
    local veh, err = orderVehicle(src, o, netId)
    if not veh then return false, err end
    local found
    for _, it in ipairs(o.items) do if it.id == itemId then found = it end end
    if not found then return false end
    if o.progress[itemId] then return true end

    -- the parts come from the mechanic's pockets and / or the shop's supply storage
    local plan, missing = Orders.PartPlan(src, o, found)
    if #missing > 0 then
        local m = missing[1]
        return false, L('missing_part', m.label, m.need - m.have)
    end
    if Config.PartItems.Consume then
        for item, count in pairs(plan.pockets) do Bridge.RemoveItem(src, item, count) end
        if next(plan.stock) and not Stock.Take(o.shop, plan.stock) then return false, L('storage_not_enough') end
    end
    o.progress[itemId] = true
    save(o, { progress = o.progress })
    return true
end)

lib.callback.register('nayzeee-tuning:orderComplete', function(src, id, netId)
    local o = load(id)
    if not o or not assignedTo(o, src) or o.status ~= 'working' then return false, L('no_permission') end
    for _, it in ipairs(o.items) do
        if not o.progress[it.id] then return false, L('order_unfinished') end
    end
    local veh, err = orderVehicle(src, o, netId)
    if not veh then return false, err end

    local owned = Bridge.GetVehicleOwner(o.plate) ~= nil
    local custSrc = Bridge.GetSourceFromIdentifier(o.customer)
    local lines = {}
    for i, it in ipairs(o.items) do lines[i] = { id = it.id, value = it.value, label = it.label, price = it.price } end
    local newPlate = Checkout_Persist(veh, o.plate, lines, o.props, owned, custSrc)
    Vehicles.SendProps(veh, o.props)

    -- repair / clean / service happen on the car now
    TriggerClientEvent('nayzeee-tuning:serviceActions', -1, NetworkGetNetworkIdFromEntity(veh), lines)

    local commission = math.floor(o.total * (Core.Shops[o.shop].commission or Config.Business.MechanicCommission) / 100)
    if commission > 0 then Bridge.AddMoney(src, 'bank', commission, 'Tuning commission') end
    Core.ShopAdd(o.shop, o.total - commission, 'order', Bridge.GetName(src), ('Order #%d %s'):format(o.id, newPlate))
    Core.AddStats(o.shop, o.total, 1)
    Core.AddMechanicStats(src, o.shop, #o.items, commission)

    save(o, { status = 'done', plate = newPlate })
    MySQL.insert('INSERT INTO nz_tuning_history (plate, shop, kind, customer, customer_name, mechanic, mechanic_name, items, total) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { newPlate, o.shop, 'order', o.customer, o.customer_name, o.mechanic, o.mechanic_name, json.encode(lines), o.total })

    if custSrc then Core.Notify(custSrc, L('order_done_customer', o.id), 'success') end
    Orders.Broadcast(o.shop, 'done', o.id, newPlate)
    Core.Log('order_done', 'Order completed', { Order = '#' .. o.id, Plate = newPlate, Total = '$' .. o.total, Commission = '$' .. commission }, src)
    return true, { commission = commission }
end)

--------------------------------------------------------------------- cancel / refund

local function cancel(o, why)
    save(o, { status = 'cancelled' })
    Core.Refund(o.customer, o.total, o.paid_with)
    local cust = Bridge.GetSourceFromIdentifier(o.customer)
    if cust then Core.Notify(cust, L('order_refunded', o.id, o.total), 'inform') end
    Orders.Broadcast(o.shop, 'cancelled', o.id, why or '')
end

lib.callback.register('nayzeee-tuning:orderCancel', function(src, id)
    local o = load(id)
    if not o or o.status == 'done' or o.status == 'cancelled' then return false end
    local isCustomer = o.customer == Bridge.GetIdentifier(src) and o.status == 'open'
    if not isCustomer and not Core.HasShopRank(src, o.shop, 'manager') then return false, L('no_permission') end
    cancel(o, Bridge.GetName(src))
    return true
end)

CreateThread(function()
    while true do
        Wait(10 * 60000)
        local rows = MySQL.query.await(('SELECT id FROM nz_tuning_orders WHERE status IN %s AND created_at < NOW() - INTERVAL ? HOUR'):format(ACTIVE), { Config.Business.OrderExpireHours }) or {}
        for _, r in ipairs(rows) do
            local o = load(r.id)
            if o then cancel(o, 'expired') end
        end
    end
end)

lib.callback.register('nayzeee-tuning:orderNeeds', function(src, id, itemId)
    local o = load(id)
    if not o or not assignedTo(o, src) then return false end
    for _, it in ipairs(o.items) do
        if it.id == itemId then
            local _, missing, source = Orders.PartPlan(src, o, it)
            return true, missing, source
        end
    end
    return false
end)
