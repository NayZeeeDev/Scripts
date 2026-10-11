Sessions = {}   -- [src] = { shop, netId, plate, role, free }
local Quotes, quoteSeq = {}, 0

local function blacklisted(veh)
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    for _, p in ipairs(Config.Ownership.BlacklistedPlates) do if p == plate then return true end end
    local hash = GetEntityModel(veh)
    for _, m in ipairs(Config.Ownership.BlacklistedModels) do if joaat(m) == hash then return true end end
    return false
end

local function nearEntity(src, ent, dist)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(ent)) <= (dist or 8.0)
end

local function unlockedList(shopId)
    local u = Core.Unlocked(shopId)
    if not u then return nil end
    local out = {}
    for k in pairs(u) do out[#out + 1] = k end
    return out
end

--------------------------------------------------------------------- open

lib.callback.register('nayzeee-tuning:open', function(src, shopId, netId, class, asMechanic)
    local shop = Config.Shops[shopId]
    local free = Admin.IsFree(src)
    if not shop and not free then return false, L('not_in_shop') end
    if shopId and not free and not Core.NearShop(src, shopId) then return false, L('not_in_shop') end
    local veh = Core.VehicleFromNet(netId)
    if not veh or not nearEntity(src, veh, 10.0) then return false, L('no_vehicle') end
    if blacklisted(veh) and not free then return false, L('vehicle_blocked') end
    if Config.Ownership.BlockedClasses[tonumber(class) or -1] and not free then return false, L('vehicle_blocked') end

    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local identifier = Bridge.GetIdentifier(src)
    local owner = Bridge.GetVehicleOwner(plate)
    local isOwner = owner ~= nil and owner == identifier
    local role = 'customer'
    if free then role = 'admin'
    elseif asMechanic and Core.IsEmployee(src, shopId) then role = 'mechanic' end

    local canBuy, reason = true, nil
    if role == 'customer' and Config.Ownership.OnlyOwnerCanTune and not isOwner then
        if not Config.Ownership.AllowUnownedPreview then return false, L('not_owner') end
        canBuy, reason = false, L('not_owner')
    end

    local vehPrice, modelName = Core.VehiclePrice(GetEntityModel(veh))
    local data = Vehicles.Get(plate)
    Sessions[src] = { shop = shopId, netId = netId, plate = plate, role = role, free = free }

    local mode = free and 'self' or Core.ShopMode(shopId)
    local showPrices = Config.Economy.ShowPricesToCustomers or role ~= 'customer' or mode == 'self'
    local comp = Config.Economy.Components

    -- open order on this car?
    local openOrder = MySQL.single.await("SELECT id, status FROM nz_tuning_orders WHERE plate = ? AND status IN ('open','accepted','working') LIMIT 1", { plate })

    return true, {
        version = Config.Version,
        shop = { id = shopId or 'admin', label = shop and shop.label or 'Admin', mode = mode, job = shop and shop.job },
        role = role, canBuy = canBuy, reason = reason, owned = isOwner,
        vehPrice = vehPrice, model = modelName, plate = plate,
        margin = (shop and shop.job) and (Core.Shops[shopId] or {}).margin or 0,
        unlocked = unlockedList(shopId),
        extras = data, showPrices = showPrices,
        payments = Config.Economy.PaymentMethods,
        components = comp.Enabled and { value = comp.Value, count = Bridge.ItemCount(src, comp.Item) } or nil,
        money = { cash = Bridge.GetMoney(src, 'cash'), bank = Bridge.GetMoney(src, 'bank') },
        swaps = NZ.SwapsFor(modelName, tonumber(class)),
        openOrder = openOrder and openOrder.id or nil,
        mechanics = shop and shop.job and Core.MechanicsOnDuty(shopId) or 0,
        modes = free and { 'self' } or Core.ShopModes(shopId),
        labour = shop and shop.job and Core.LabourRate(shopId) or Config.Economy.LaborPerItem,
        surcharge = Config.Business.SelfServiceSurcharge or 0,
        partsMode = Config.PartItems.Mode,
    }
end)

RegisterNetEvent('nayzeee-tuning:closed', function()
    Sessions[source] = nil
end)

AddEventHandler('playerDropped', function()
    Sessions[source] = nil
end)

--------------------------------------------------------------------- persistence helpers

local function plateTaken(newPlate)
    if Bridge.PlateExists(newPlate) then return true end
    if Vehicles.FindByPlate(newPlate) then return true end
    return false
end

-- write GTA props + extras for a finished job. Returns the final plate.
function Checkout_Persist(veh, plate, lines, props, owned, src)
    local newPlate = plate
    for _, l in ipairs(lines) do
        if l.id == 'plateText' then newPlate = l.value:upper() end
    end

    local data = NZ.Copy(Vehicles.Get(plate))
    for _, l in ipairs(lines) do NZ.ApplyToExtras(data, l.id, l.value) end

    if newPlate ~= plate then
        if owned then Bridge.UpdatePlate(plate, newPlate) end
        MySQL.update.await('DELETE FROM nz_tuning_vehicles WHERE plate = ?', { plate })
        Vehicles.cache[plate] = nil
        MySQL.update('UPDATE nz_tuning_history SET plate = ? WHERE plate = ?', { newPlate, plate })
        SetVehicleNumberPlateText(veh, newPlate)
        if src and Config.Plates.GiveKeys then Bridge.GiveKeys(src, newPlate, NetworkGetNetworkIdFromEntity(veh)) end
    end

    if type(props) == 'table' then
        props.plate = newPlate
        if owned then Bridge.SaveVehicleProps(newPlate, props) end
    end

    Vehicles.Save(newPlate, data, Core.ModelName(GetEntityModel(veh)))
    Vehicles.Push(veh, newPlate)
    for _, l in ipairs(lines) do
        if l.id == 'repair' then TriggerEvent('nayzeee-tuning:repaired', newPlate) end
    end
    return newPlate, data
end

local function summary(lines)
    local out = {}
    for _, l in ipairs(lines) do out[#out + 1] = { id = l.id, label = l.label, price = l.price } end
    return out
end

--------------------------------------------------------------------- checkout

lib.callback.register('nayzeee-tuning:checkout', function(src, p)
    if not Core.Throttle(src, 'checkout', 2000) then return false, L('slow_down') end
    local s = Sessions[src]
    if type(p) ~= 'table' or not s or s.netId ~= p.netId then return false, L('session_expired') end
    local shopId = s.shop
    local veh = Core.VehicleFromNet(p.netId)
    if not veh or not nearEntity(src, veh, 10.0) then return false, L('no_vehicle') end
    if not s.free and not Core.NearShop(src, shopId) then return false, L('not_in_shop') end

    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    if plate ~= s.plate then return false, L('session_expired') end
    local identifier = Bridge.GetIdentifier(src)
    local owner = Bridge.GetVehicleOwner(plate)
    local owned = owner ~= nil
    if Config.Ownership.OnlyOwnerCanTune and not s.free and owner ~= identifier then return false, L('not_owner') end

    local modes = s.free and { 'self' } or Core.ShopModes(shopId)
    local mode = NZ.InList(modes, p.mode) and p.mode or modes[1]

    local ok, res = Pricing.Cart(shopId, veh, p.items, { class = p.class, code = p.code, free = s.free, mode = mode })
    if not ok then return false, res end

    -- self-service with real parts: the customer brings them
    if mode == 'self' and Config.PartItems.Mode == 'all' and not s.free then
        for item, count in pairs(res.required) do
            if Bridge.ItemCount(src, item) < count then return false, L('missing_part', Bridge.ItemLabel and Bridge.ItemLabel(item) or item, count) end
        end
    end

    for _, l in ipairs(res.lines) do
        if l.id == 'plateText' and l.value:upper() ~= plate and plateTaken(l.value:upper()) then
            return false, L('plate_taken')
        end
    end

    local total = res.totals.total
    local method = p.payment
    if total > 0 and not NZ.InList(Config.Economy.PaymentMethods, method) and not (method == 'components' and Config.Economy.Components.Enabled) then
        return false, L('payment_invalid')
    end
    local paid, paidWith = Core.Charge(src, method, total, 'Vehicle tuning')
    if not paid then return false, method == 'components' and L('not_enough_components') or L('not_enough_money') end
    if res.code then Pricing.UseCode(res.code) end

    local name = Bridge.GetName(src)
    if mode == 'order' and not (Config.Shops[shopId] and Config.Shops[shopId].job) then mode = 'self' end
    local shop = Config.Shops[shopId]

    if mode == 'self' then
        if Config.PartItems.Mode == 'all' and Config.PartItems.Consume and not s.free then
            for item, count in pairs(res.required) do Bridge.RemoveItem(src, item, count) end
        end
        local newPlate = Checkout_Persist(veh, plate, res.lines, p.props, owned, src)
        MySQL.insert('INSERT INTO nz_tuning_history (plate, shop, kind, customer, customer_name, items, total) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { newPlate, shopId or 'admin', s.free and 'admin' or 'self', identifier, name, json.encode(summary(res.lines)), total })
        if shop and shop.job and total > 0 then
            local cut = math.floor(total * Config.Business.ShopCutSelfService / 100)
            Core.ShopAdd(shopId, cut, 'sale', name, ('Self-service %s'):format(newPlate))
        end
        if shop then Core.AddStats(shopId, total, 1) end
        Core.Log(s.free and 'admin' or 'purchase', s.free and 'Admin tune' or 'Tuning purchased',
            { Shop = shop and shop.label or 'admin', Plate = newPlate, Items = #res.lines, Total = '$' .. total }, src)
        return true, { mode = 'self', plate = newPlate, total = total, lines = summary(res.lines) }
    end

    -- mechanic order, money is held until the job is finished
    local extras = NZ.Copy(Vehicles.Get(plate))
    for _, l in ipairs(res.lines) do NZ.ApplyToExtras(extras, l.id, l.value) end
    local items = {}
    for i, l in ipairs(res.lines) do items[i] = { id = l.id, value = l.value, label = l.label, price = l.price } end
    local orderId = MySQL.insert.await([[INSERT INTO nz_tuning_orders
        (shop, plate, model, label, customer, customer_name, items, props, extras, totals, total, paid_with, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open')]],
        { shopId, plate, res.model, p.label, identifier, name, json.encode(items), json.encode(p.props or {}), json.encode(extras),
          json.encode(res.totals), total, paidWith })
    Orders.Broadcast(shopId, 'new', orderId, ('%s - %s'):format(p.label or res.model, plate))
    Core.Log('order', 'Tuning order placed', { Shop = shop.label, Order = '#' .. orderId, Plate = plate, Total = '$' .. total }, src)
    return true, { mode = 'order', orderId = orderId, total = total }
end)

--------------------------------------------------------------------- mechanic quotes

lib.callback.register('nayzeee-tuning:nearbyCustomers', function(src)
    local s = Sessions[src]
    if not s or s.role ~= 'mechanic' then return {} end
    local veh = Core.VehicleFromNet(s.netId)
    local out = {}
    local myPed = GetPlayerPed(src)
    for _, id in ipairs(GetPlayers()) do
        local t = tonumber(id)
        if t ~= src then
            local ped = GetPlayerPed(t)
            if ped ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(myPed)) < 15.0 then
                local driver = veh and GetPedInVehicleSeat(veh, -1) == ped
                out[#out + 1] = { id = t, name = Bridge.GetName(t), driver = driver }
            end
        end
    end
    return out
end)

lib.callback.register('nayzeee-tuning:sendQuote', function(src, p)
    if not Core.Throttle(src, 'quote_send', 3000) then return false, L('slow_down') end
    local s = Sessions[src]
    if type(p) ~= 'table' or not s or s.role ~= 'mechanic' or s.netId ~= p.netId then return false, L('session_expired') end
    local target = tonumber(p.target)
    if not target or not GetPlayerName(target) then return false, L('player_gone') end
    local veh = Core.VehicleFromNet(p.netId)
    if not veh then return false, L('no_vehicle') end
    local tPed = GetPlayerPed(target)
    if #(GetEntityCoords(tPed) - GetEntityCoords(GetPlayerPed(src))) > 15.0 then return false, L('player_gone') end

    local ok, res = Pricing.Cart(s.shop, veh, p.items, { class = p.class })
    if not ok then return false, res end

    quoteSeq = quoteSeq + 1
    Quotes[quoteSeq] = {
        id = quoteSeq, shop = s.shop, netId = p.netId, plate = res.plate, model = res.model, label = p.label,
        items = p.items, props = p.props, class = p.class, mechanic = src, target = target,
        expires = os.time() + Config.Orders.QuoteTimeout,
    }
    TriggerClientEvent('nayzeee-tuning:quote', target, {
        id = quoteSeq, shop = Config.Shops[s.shop].label, mechanic = Bridge.GetName(src), plate = res.plate,
        label = p.label, lines = summary(res.lines), totals = res.totals, payments = Config.Economy.PaymentMethods,
        components = Config.Economy.Components.Enabled and Config.Economy.Components.Value or nil,
        timeout = Config.Orders.QuoteTimeout, shopId = s.shop,
    })
    Core.Log('quote', 'Quote sent', { Shop = Config.Shops[s.shop].label, Plate = res.plate, Total = '$' .. res.totals.total }, src)
    return true, { id = quoteSeq, total = res.totals.total }
end)

lib.callback.register('nayzeee-tuning:answerQuote', function(src, id, accept, payment, code)
    local q = Quotes[tonumber(id) or -1]
    if not q or q.target ~= src then return false, L('quote_expired') end
    Quotes[q.id] = nil
    if os.time() > q.expires then return false, L('quote_expired') end
    if not accept then
        Core.Notify(q.mechanic, L('quote_declined', Bridge.GetName(src)), 'error')
        TriggerClientEvent('nayzeee-tuning:quoteAnswered', q.mechanic, false)
        return true
    end

    local veh = Core.VehicleFromNet(q.netId)
    if not veh then return false, L('no_vehicle') end
    local identifier = Bridge.GetIdentifier(src)
    local ok, res = Pricing.Cart(q.shop, veh, q.items, { class = q.class, code = code })
    if not ok then return false, res end
    local paid, paidWith = Core.Charge(src, payment, res.totals.total, 'Vehicle tuning')
    if not paid then
        Core.Notify(q.mechanic, L('quote_no_money'), 'error')
        TriggerClientEvent('nayzeee-tuning:quoteAnswered', q.mechanic, false)
        return false, L('not_enough_money')
    end
    if res.code then Pricing.UseCode(res.code) end

    local extras = NZ.Copy(Vehicles.Get(res.plate))
    for _, l in ipairs(res.lines) do NZ.ApplyToExtras(extras, l.id, l.value) end
    local items = {}
    for i, l in ipairs(res.lines) do items[i] = { id = l.id, value = l.value, label = l.label, price = l.price } end

    local mechId = GetPlayerName(q.mechanic) and Bridge.GetIdentifier(q.mechanic)
    local orderId = MySQL.insert.await([[INSERT INTO nz_tuning_orders
        (shop, plate, model, label, customer, customer_name, items, props, extras, totals, total, paid_with, status, mechanic, mechanic_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { q.shop, res.plate, res.model, q.label, identifier, Bridge.GetName(src), json.encode(items), json.encode(q.props or {}),
          json.encode(extras), json.encode(res.totals), res.totals.total, paidWith, mechId and 'accepted' or 'open',
          mechId, mechId and Bridge.GetName(q.mechanic) or nil })

    if mechId then
        Core.Notify(q.mechanic, L('quote_accepted', Bridge.GetName(src)), 'success')
        TriggerClientEvent('nayzeee-tuning:quoteAnswered', q.mechanic, true, orderId)
    end
    Orders.Broadcast(q.shop, 'new', orderId, ('%s - %s'):format(q.label or res.model, res.plate))
    return true, { orderId = orderId }
end)

CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for id, q in pairs(Quotes) do
            if now > q.expires then
                Quotes[id] = nil
                if GetPlayerName(q.mechanic) then
                    TriggerClientEvent('nayzeee-tuning:quoteAnswered', q.mechanic, false)
                end
            end
        end
    end
end)

--------------------------------------------------------------------- history for the UI

lib.callback.register('nayzeee-tuning:history', function(src, plate)
    if not Core.Throttle(src, 'history', 800) then return {} end
    plate = NZ.TrimPlate(tostring(plate or ''))
    local rows = MySQL.query.await('SELECT shop, kind, customer_name, mechanic_name, items, total, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_history WHERE plate = ? ORDER BY id DESC LIMIT 40', { plate }) or {}
    for _, r in ipairs(rows) do
        r.items = DB.Decode(r.items, {})
        r.shopLabel = Config.Shops[r.shop] and Config.Shops[r.shop].label or r.shop
    end
    local data = Vehicles.Get(plate)
    return { rows = rows, km = data.km or 0, wear = data.wear }
end)
