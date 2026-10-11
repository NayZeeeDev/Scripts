--[[ Tuning tablet: per-player settings, apps by job / rank, messages, parts supplier, ECU map flashing. ]]

local T = Config.Tablet

local function rankOf(src)
    for id, shop in pairs(Config.Shops) do
        if shop.job and Core.IsEmployee(src, id) then
            return id, {
                access = true,
                manager = Core.HasShopRank(src, id, 'manager'),
                boss = Core.HasShopRank(src, id, 'boss'),
            }
        end
    end
    return nil, { access = false, manager = false, boss = false }
end
Tablet = { RankOf = rankOf }

local function settingsOf(identifier)
    local row = MySQL.single.await('SELECT accent, wallpaper FROM nz_tuning_tablet WHERE identifier = ?', { identifier })
    return { accent = row and row.accent or T.Accents[1], wallpaper = row and row.wallpaper or 'carbon' }
end

lib.callback.register('nayzeee-tuning:tablet:open', function(src, viaItem)
    if not T.Enabled then return false end
    if not viaItem and T.Item and T.CommandNeedsItem and Bridge.ItemCount(src, T.Item) < 1 then
        -- the boss desk opens it without the item
        local shopId = rankOf(src)
        local nearDesk = shopId and Config.Shops[shopId].boss and #(GetEntityCoords(GetPlayerPed(src)) - Config.Shops[shopId].boss) < 4.0
        -- so does the supply storage point
        if not nearDesk and not (shopId and Stock.Near(src, shopId)) then return false, L('missing_item') end
    end
    local identifier = Bridge.GetIdentifier(src)
    local shopId, rank = rankOf(src)
    local job = Bridge.GetJob(src)
    local avatar = Avatars.Of(identifier)
    Avatars.Refresh(src, false, function(url)
        if url and url ~= avatar then TriggerClientEvent('nayzeee-tuning:avatar', src, url) end
    end)
    return true, {
        version = Config.Version, avatar = avatar, brand = T.Brand or 'PITWALL', osName = T.OSName or 'NZ-OS',
        name = Bridge.GetName(src), job = job.label, grade = job.gradeLabel, onDuty = job.onDuty,
        shop = shopId and { id = shopId, label = Config.Shops[shopId].label } or nil,
        rank = rank,
        settings = settingsOf(identifier),
        accents = T.Accents, customWallpaper = T.AllowCustomWallpaper,
        supplier = Config.Supplier.Enabled and shopId ~= nil and Core.HasShopRank(src, shopId, Config.Supplier.MinRank),
        missions = Config.Missions.Enabled, upgrades = Config.ShopUpgrades.Enabled, discounts = Config.Discounts.Enabled,
        diagnostics = Config.Diagnostics.Enabled and (shopId ~= nil and not T.DiagnosticsNeedsScanner or (Config.Diagnostics.Item and Bridge.ItemCount(src, Config.Diagnostics.Item) > 0)),
        ecu = Config.ECU.Enabled and shopId ~= nil and (not Config.ECU.Map.Jobs or NZ.InList(Config.ECU.Map.Jobs, job.name)),
        ecuMap = Config.ECU.Map,
        perf = Config.PerfTest.Enabled, assists = Config.DriverAssists.Enabled,
        storage = Config.Storage.Enabled and shopId ~= nil,
        partSource = shopId and NZ.PartSource(shopId) or nil,
        bays = shopId and NZ.BayClaims(shopId) or false,
        supplyRuns = Config.SupplyRuns.Enabled and { discount = Config.SupplyRuns.Discount, max = Config.SupplyRuns.MaxCrates * Config.SupplyRuns.ItemsPerCrate,
            minutes = Config.SupplyRuns.TimeLimit } or nil,
    }
end)

lib.callback.register('nayzeee-tuning:tablet:settings', function(src, accent, wallpaper)
    if type(accent) ~= 'string' or not accent:match('^#%x%x%x%x%x%x$') then return false end
    if type(wallpaper) ~= 'string' or #wallpaper > 255 then return false end
    if wallpaper:match('^https?://') then
        if not T.AllowCustomWallpaper then return false, L('no_permission') end
        local host = wallpaper:match('^https?://([^/]+)')
        if not NZ.InList(T.WallpaperHosts, host) then return false, L('wallpaper_host') end
    elseif not wallpaper:match('^[%w_%-]+$') then
        return false
    end
    MySQL.insert.await('INSERT INTO nz_tuning_tablet (identifier, accent, wallpaper) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE accent = VALUES(accent), wallpaper = VALUES(wallpaper)',
        { Bridge.GetIdentifier(src), accent, wallpaper })
    return true
end)

--------------------------------------------------------------------- my work / my cars

lib.callback.register('nayzeee-tuning:tablet:myWork', function(src)
    local id = Bridge.GetIdentifier(src)
    local rows = MySQL.query.await('SELECT id, plate, shop, kind, customer_name, items, total, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_history WHERE mechanic = ? ORDER BY id DESC LIMIT 60', { id }) or {}
    for _, r in ipairs(rows) do
        r.items = DB.Decode(r.items, {})
        r.shopLabel = Config.Shops[r.shop] and Config.Shops[r.shop].label or r.shop
    end
    local stats = MySQL.single.await('SELECT SUM(installs) AS installs, SUM(earned) AS earned FROM nz_tuning_mechanics WHERE identifier = ?', { id }) or {}
    local week = MySQL.scalar.await('SELECT COUNT(*) FROM nz_tuning_history WHERE mechanic = ? AND created_at > NOW() - INTERVAL 7 DAY', { id }) or 0
    return { rows = rows, installs = tonumber(stats.installs) or 0, earned = tonumber(stats.earned) or 0, week = week }
end)

lib.callback.register('nayzeee-tuning:tablet:myCars', function(src)
    local id = Bridge.GetIdentifier(src)
    local out = {}
    for _, v in ipairs(Bridge.GetOwnedVehicles(id)) do
        local d = Vehicles.Get(v.plate)
        local last = MySQL.single.await('SELECT shop, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_history WHERE plate = ? ORDER BY id DESC LIMIT 1', { v.plate })
        out[#out + 1] = {
            plate = v.plate, model = v.model, km = d.km or 0, wear = d.wear, nitrous = d.nitrous, ecu = d.ecu ~= nil,
            locator = d.locator == true, swap = d.swap and NZ.SwapBySound[d.swap] and NZ.SwapBySound[d.swap].label or nil,
            tcs = d.tcs == true, esc = d.esc == true, manual = d.gearbox == 'manual', drive = d.drive, tyres = d.tyres,
            lastShop = last and (Config.Shops[last.shop] and Config.Shops[last.shop].label or last.shop), lastTime = last and last.t,
        }
    end
    return out
end)

--------------------------------------------------------------------- order messages

local function orderFor(src, orderId)
    local o = MySQL.single.await('SELECT id, shop, plate, label, model, customer, customer_name, mechanic, status FROM nz_tuning_orders WHERE id = ?', { tonumber(orderId) or -1 })
    if not o then return nil end
    local me = Bridge.GetIdentifier(src)
    if o.customer == me then return o, 'customer' end
    if Core.IsEmployee(src, o.shop) then return o, 'shop' end
    return nil
end

lib.callback.register('nayzeee-tuning:tablet:threads', function(src)
    local me = Bridge.GetIdentifier(src)
    local shopId = rankOf(src)
    local rows = MySQL.query.await([[
        SELECT o.id, o.shop, o.plate, o.label, o.model, o.status, o.customer, o.mechanic, o.customer_name, o.mechanic_name,
               (SELECT body FROM nz_tuning_messages m WHERE m.order_id = o.id ORDER BY m.id DESC LIMIT 1) AS last,
               (SELECT UNIX_TIMESTAMP(created_at) FROM nz_tuning_messages m WHERE m.order_id = o.id ORDER BY m.id DESC LIMIT 1) AS lastAt
        FROM nz_tuning_orders o
        WHERE o.customer = ? OR o.shop = ?
        ORDER BY COALESCE(lastAt, UNIX_TIMESTAMP(o.updated_at)) DESC LIMIT 40]], { me, shopId or '' }) or {}
    for _, r in ipairs(rows) do
        r.mine = r.customer == me
        r.avatar = r.mine and Avatars.Of(r.mechanic) or Avatars.Of(r.customer)
        r.customer, r.mechanic = nil, nil
        r.shopLabel = Config.Shops[r.shop] and Config.Shops[r.shop].label or r.shop
    end
    return rows
end)

lib.callback.register('nayzeee-tuning:tablet:messages', function(src, orderId)
    local o = orderFor(src, orderId)
    if not o then return false end
    local me = Bridge.GetIdentifier(src)
    local rows = MySQL.query.await('SELECT sender, sender_name, side, body, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_messages WHERE order_id = ? ORDER BY id ASC LIMIT 200', { o.id }) or {}
    for _, r in ipairs(rows) do
        r.me, r.avatar = r.sender == me, Avatars.Of(r.sender)
        r.sender = nil
    end
    return true, { order = { id = o.id, plate = o.plate, label = o.label or o.model, status = o.status, customer = o.customer_name, shop = Config.Shops[o.shop] and Config.Shops[o.shop].label }, rows = rows }
end)

lib.callback.register('nayzeee-tuning:tablet:send', function(src, orderId, body)
    if not Core.Throttle(src, 'msg', 1200) then return false, L('slow_down') end
    local o, side = orderFor(src, orderId)
    if not o or type(body) ~= 'string' then return false end
    body = body:gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 500)
    if #body < 1 then return false end
    local name = Bridge.GetName(src)
    MySQL.insert.await('INSERT INTO nz_tuning_messages (order_id, sender, sender_name, side, body) VALUES (?, ?, ?, ?, ?)', { o.id, Bridge.GetIdentifier(src), name, side, body })

    local targets = {}
    if side == 'shop' then
        local c = Bridge.GetSourceFromIdentifier(o.customer)
        if c then targets[#targets + 1] = c end
    else
        local mech = o.mechanic and Bridge.GetSourceFromIdentifier(o.mechanic)
        if mech then targets[#targets + 1] = mech
        else
            for _, t in ipairs(Bridge.GetPlayersWithJob(Config.Shops[o.shop].job, true)) do targets[#targets + 1] = t end
        end
    end
    for _, t in ipairs(targets) do
        if t ~= src then TriggerClientEvent('nayzeee-tuning:message', t, { order = o.id, from = name, body = body, side = side, avatar = Avatars.Of(Bridge.GetIdentifier(src)) }) end
    end
    return true
end)

--------------------------------------------------------------------- parts supplier

local supplierIndex = {}
for _, it in ipairs(Config.Supplier.Items) do supplierIndex[it.item] = it end

lib.callback.register('nayzeee-tuning:tablet:supplier', function(src)
    local shopId = rankOf(src)
    if not Config.Supplier.Enabled or not shopId or not Core.HasShopRank(src, shopId, Config.Supplier.MinRank) then return false, L('no_permission') end
    local items = {}
    for i, it in ipairs(Config.Supplier.Items) do
        items[i] = { item = it.item, label = it.label, price = it.price, cat = it.cat, have = Bridge.ItemCount(src, it.item), stock = Stock.Count(shopId, it.item) }
    end
    local incoming, now = Stock.Incoming(shopId)
    return true, { items = items, balance = Core.ShopBalance(shopId), max = Config.Supplier.MaxPerOrder, incoming = incoming, now = now,
        minutes = Config.Supplier.DeliveryMinutes or 0, storage = Config.Storage.Enabled }
end)

lib.callback.register('nayzeee-tuning:tablet:buy', function(src, cart)
    if not Core.Throttle(src, 'supplier', 1500) then return false, L('slow_down') end
    local shopId = rankOf(src)
    if not Config.Supplier.Enabled or not shopId or not Core.HasShopRank(src, shopId, Config.Supplier.MinRank) then return false, L('no_permission') end
    if type(cart) ~= 'table' then return false end
    local total, lines, n = 0, {}, 0
    for item, qty in pairs(cart) do
        local it = supplierIndex[item]
        qty = math.floor(tonumber(qty) or 0)
        if not it or qty < 1 or qty > Config.Supplier.MaxPerOrder then return false, L('amount_invalid') end
        total = total + it.price * qty
        lines[item] = qty
        n = n + 1
    end
    if n == 0 then return false end
    if not Core.ShopTake(shopId, total, 'supplier', Bridge.GetName(src), ('%d part lines'):format(n)) then return false, L('shop_no_money') end
    -- with supply storage the order is delivered to the shop after the delivery timer
    if Config.Storage.Enabled then
        local eta = Stock.QueueDelivery(src, shopId, lines, total)
        return true, { total = total, refunded = 0, eta = eta, now = os.time() }
    end
    local failed = 0
    for item, qty in pairs(lines) do
        if not Bridge.AddItem(src, item, qty) then failed = failed + supplierIndex[item].price * qty end
    end
    if failed > 0 then Core.ShopAdd(shopId, failed, 'refund', 'Supplier', 'Could not carry everything') end
    return true, { total = total - failed, refunded = failed }
end)

--------------------------------------------------------------------- ECU map

local function canFlash(src)
    local shopId = rankOf(src)
    if not shopId or not Config.ECU.Enabled then return false end
    local jobs = Config.ECU.Map.Jobs
    return not jobs or NZ.InList(jobs, Bridge.GetJob(src).name)
end

lib.callback.register('nayzeee-tuning:tablet:ecuRead', function(src, netId)
    local veh = Core.VehicleFromNet(netId)
    if not veh or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 8.0 then return false, L('too_far') end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local d = Vehicles.Get(plate)
    if not d.ecu then return false, L('no_ecu') end
    local params = {}
    for _, p in ipairs(Config.ECU.Params) do params[p.key] = d.ecu[p.key] or 0 end
    return true, { plate = plate, cells = d.ecu.map, fuel = d.ecu.fuel or 0, gain = d.ecu.mapGain or 0, knock = d.ecu.knock or 0,
        params = params, canFlash = canFlash(src) }
end)

-- cells: 8 numbers or false (stock map), fuel: 0-100, params: calibration sliders or false (stock)
lib.callback.register('nayzeee-tuning:tablet:ecuFlash', function(src, netId, cells, fuel, params)
    if not canFlash(src) then return false, L('no_permission') end
    if not Core.Throttle(src, 'ecuflash', 3000) then return false, L('slow_down') end
    local veh = Core.VehicleFromNet(netId)
    if not veh or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 8.0 then return false, L('too_far') end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    if not Vehicles.Get(plate).ecu then return false, L('no_ecu') end
    local stockMap = cells == false
    if not stockMap and not NZ.ValidMap(cells) then return false end
    if params ~= false and params ~= nil and not NZ.ValidEcuParams(params) then return false end
    fuel = NZ.Clamp(math.floor(tonumber(fuel) or 0), 0, 100)
    local gain, knock = 0, 0
    if not stockMap then gain, knock = NZ.EcuMap(cells, fuel) end
    Vehicles.Update(plate, veh, function(x)
        x.ecu = x.ecu or {}
        if stockMap then x.ecu.map, x.ecu.fuel, x.ecu.mapGain, x.ecu.knock = nil, nil, nil, nil
        else
            local clean = {}
            for i = 1, #cells do clean[i] = math.floor(cells[i] + 0.5) end
            x.ecu.map, x.ecu.fuel, x.ecu.mapGain, x.ecu.knock = clean, fuel, gain, knock
        end
        if params ~= nil then
            for _, p in ipairs(Config.ECU.Params) do
                local v = params and tonumber(params[p.key]) or 0
                x.ecu[p.key] = v ~= 0 and v or nil
            end
        end
    end)
    Core.Log('admin', 'ECU flashed', { Plate = plate, Gain = gain .. '%', Knock = knock, By = Bridge.GetName(src) }, src)
    return true, { gain = gain, knock = knock }
end)
