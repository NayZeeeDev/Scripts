Core = {
    Shops    = {},      -- [shopId] = { balance, margin, commission, upgrades = {} }
    Prices   = {},      -- [modelName] = price
    HashName = {},      -- [modelHash] = modelName
    Ready    = false,
}

--------------------------------------------------------------------- boot

CreateThread(function()
    DB.Init()

    local rows = MySQL.query.await('SELECT * FROM nz_tuning_shops') or {}
    local byId = {}
    for _, r in ipairs(rows) do byId[r.id] = r end
    for id, shop in pairs(Config.Shops) do
        local r = byId[id]
        if not r then
            MySQL.insert.await('INSERT INTO nz_tuning_shops (id, balance, margin) VALUES (?, 0, 0)', { id })
            r = { balance = 0, margin = 0 }
        end
        Core.Shops[id] = {
            balance = r.balance or 0,
            margin = r.margin or 0,
            commission = r.commission or Config.Business.MechanicCommission,
            labour = r.labour,
            upgrades = DB.Decode(r.upgrades, {}),
        }
    end

    if Config.Economy.PriceSource ~= 'config' then
        for model, price in pairs(Bridge.LoadVehiclePrices()) do Core.Prices[model] = price end
    end
    if Config.Economy.PriceSource ~= 'database' then
        for model, price in pairs(Config.VehiclePrices) do Core.Prices[model:lower()] = price end
    end
    for model in pairs(Core.Prices) do Core.HashName[joaat(model)] = model end

    Core.Ready = true
    NZ.Debug(('loaded %d shops, %d vehicle prices (%s)'):format(NZ.Count(Core.Shops), NZ.Count(Core.Prices), Bridge.Framework))
end)

-- shops created in the editor get their account row the first time they show up
function Core.EnsureShop(id)
    if Core.Shops[id] then return end
    local r = MySQL.single.await('SELECT * FROM nz_tuning_shops WHERE id = ?', { id })
    if not r then
        MySQL.insert.await('INSERT INTO nz_tuning_shops (id, balance, margin) VALUES (?, 0, 0)', { id })
        r = {}
    end
    Core.Shops[id] = { balance = r.balance or 0, margin = r.margin or 0, commission = r.commission or Config.Business.MechanicCommission,
        labour = r.labour, upgrades = DB.Decode(r.upgrades, {}) }
end

--------------------------------------------------------------------- helpers

function Core.Notify(src, msg, kind)
    TriggerClientEvent('nayzeee-tuning:notify', src, msg, kind or 'inform')
end

function Core.ModelName(hash)
    return Core.HashName[hash]
end

function Core.VehiclePrice(hash)
    local name = Core.HashName[hash]
    local p = name and Core.Prices[name] or Config.Economy.DefaultVehiclePrice
    return NZ.Clamp(p, Config.Economy.MinVehiclePrice, Config.Economy.MaxVehiclePrice), name
end

function Core.Unlocked(shopId)
    if not Config.ShopUpgrades.Enabled then return nil end
    local s = Core.Shops[shopId]
    return s and s.upgrades or {}
end

-- 'access' | 'manager' | 'boss'
function Core.HasShopRank(src, shopId, rank)
    local shop = Config.Shops[shopId]
    if not shop or not shop.job then return false end
    local job = Bridge.GetJob(src)
    if job.name ~= shop.job then return false end
    local need = (shop.grades or {})[rank or 'access'] or 0
    return job.grade >= need
end

function Core.IsEmployee(src, shopId) return Core.HasShopRank(src, shopId, 'access') end

function Core.NearShop(src, shopId, extra)
    local shop = Config.Shops[shopId]
    if not shop then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - shop.center) <= shop.radius + (extra or 15.0)
end

function Core.MechanicsOnDuty(shopId)
    local shop = Config.Shops[shopId]
    if not shop or not shop.job then return 0 end
    local n = 0
    for _, src in ipairs(Bridge.GetPlayersWithJob(shop.job, true)) do
        if Core.HasShopRank(src, shopId, 'access') then n = n + 1 end
    end
    return n
end

-- modes a customer may use right now: { 'self' } / { 'order' } / { 'self', 'order' }
function Core.ShopModes(shopId)
    local shop = Config.Shops[shopId]
    if not shop then return { 'self' } end
    if shop.mode == 'self' then return { 'self' } end
    local staffed = Core.MechanicsOnDuty(shopId) > 0
    if shop.mode == 'hybrid' then
        if not staffed then return { 'self' } end
        return Config.Business.CustomerChoosesMode and { 'order', 'self' } or { 'order' }
    end
    return { 'order' }
end

function Core.LabourRate(shopId)
    local s = Core.Shops[shopId]
    return s and s.labour or Config.Economy.LaborPerItem
end

-- effective mode for a shop right now
function Core.ShopMode(shopId)
    local shop = Config.Shops[shopId]
    if not shop then return 'self' end
    if shop.mode == 'hybrid' then return Core.MechanicsOnDuty(shopId) > 0 and 'mechanic' or 'self' end
    return shop.mode or 'self'
end

function Core.VehicleFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return nil end
    return veh
end

--------------------------------------------------------------------- shop money

function Core.ShopAdd(shopId, amount, kind, actor, note)
    local s, shop = Core.Shops[shopId], Config.Shops[shopId]
    if not s or not shop or not shop.job or amount == 0 then return end
    if Config.Business.UseBuiltInBalance then
        s.balance = s.balance + amount
        MySQL.update('UPDATE nz_tuning_shops SET balance = balance + ? WHERE id = ?', { amount, shopId })
    elseif amount > 0 then
        Bridge.SocietyAdd(shop.society, amount)
    else
        Bridge.SocietyRemove(shop.society, -amount)
    end
    MySQL.insert('INSERT INTO nz_tuning_tx (shop, kind, amount, actor, note) VALUES (?, ?, ?, ?, ?)', { shopId, kind, amount, actor, note })
end

function Core.ShopBalance(shopId)
    local shop = Config.Shops[shopId]
    if not shop then return 0 end
    if Config.Business.UseBuiltInBalance then return (Core.Shops[shopId] or {}).balance or 0 end
    return Bridge.SocietyGet(shop.society)
end

function Core.ShopTake(shopId, amount, kind, actor, note)
    if Core.ShopBalance(shopId) < amount then return false end
    if Config.Business.UseBuiltInBalance then
        Core.ShopAdd(shopId, -amount, kind, actor, note)
        return true
    end
    if not Bridge.SocietyRemove(Config.Shops[shopId].society, amount) then return false end
    MySQL.insert('INSERT INTO nz_tuning_tx (shop, kind, amount, actor, note) VALUES (?, ?, ?, ?, ?)', { shopId, kind, -amount, actor, note })
    return true
end

function Core.AddStats(shopId, revenue, jobs)
    MySQL.insert('INSERT INTO nz_tuning_stats (shop, day, revenue, jobs) VALUES (?, CURDATE(), ?, ?) ON DUPLICATE KEY UPDATE revenue = revenue + VALUES(revenue), jobs = jobs + VALUES(jobs)', { shopId, revenue, jobs })
end

function Core.AddMechanicStats(src, shopId, installs, earned)
    local id = Bridge.GetIdentifier(src)
    if not id then return end
    MySQL.insert('INSERT INTO nz_tuning_mechanics (identifier, shop, name, installs, earned) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), installs = installs + VALUES(installs), earned = earned + VALUES(earned)',
        { id, shopId, Bridge.GetName(src), installs, earned })
end

--------------------------------------------------------------------- payments

-- method: 'cash' | 'bank' | 'components'. Returns true, paidWith
function Core.Charge(src, method, amount, reason)
    if amount <= 0 then return true, method end
    if method == 'components' then
        local c = Config.Economy.Components
        if not c.Enabled then return false end
        local need = math.ceil(amount / c.Value)
        if not Bridge.RemoveItem(src, c.Item, need) then return false end
        return true, 'components'
    end
    if method ~= 'cash' and method ~= 'bank' then return false end
    return Bridge.RemoveMoney(src, method, amount, reason), method
end

function Core.Refund(identifier, amount, paidWith)
    if amount <= 0 then return end
    local src = Bridge.GetSourceFromIdentifier(identifier)
    if paidWith == 'components' and src then
        Bridge.AddItem(src, Config.Economy.Components.Item, math.floor(amount / Config.Economy.Components.Value))
        return
    end
    if src then Bridge.AddMoney(src, paidWith == 'cash' and 'cash' or 'bank', amount, 'nayzeee-tuning refund')
    else Bridge.AddBankOffline(identifier, amount) end
end

--------------------------------------------------------------------- webhooks

function Core.Log(event, title, fields, src)
    local cfg = Config.Webhooks
    if not cfg.Enabled then return end
    local url = cfg.Events[event]
    if url == false then return end
    if not url or url == '' then url = cfg.Default end
    if not url or url == '' then return end
    local f = {}
    for k, v in pairs(fields or {}) do f[#f + 1] = { name = k, value = tostring(v), inline = true } end
    if src then f[#f + 1] = { name = 'Player', value = ('%s (%s)'):format(Bridge.GetName(src), Bridge.GetIdentifier(src) or src), inline = false } end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = 'Tuning',
        embeds = { { title = title, color = cfg.Color, fields = f, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }), { ['Content-Type'] = 'application/json' })
end

--------------------------------------------------------------------- rate limit

local last = {}
function Core.Throttle(src, key, ms)
    local k = src .. ':' .. key
    local now = GetGameTimer()
    if last[k] and now - last[k] < ms then return false end
    last[k] = now
    return true
end

AddEventHandler('playerDropped', function()
    local src = tostring(source)
    for k in pairs(last) do if k:sub(1, #src + 1) == src .. ':' then last[k] = nil end end
end)
