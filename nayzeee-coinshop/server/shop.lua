if not NAYZEEE_LOCK_OK then return end

--[[
    Shop: catalogue cache, boot data, purchases (items, vehicles, weapons, deals, gifts),
    Tebex + promo redeem, coin transfers, favourites and history.
]]

Catalog = { items = {}, byId = {}, categories = {}, deals = {}, sold = {}, settings = {} }

DefaultSettings = {
    accent = '#08afa2', danger = '#e5484d', background = '#08090a', text = '#f2f4f5',
    bgImage = '', bgOpacity = '0.18', bgBlur = '0', cardRadius = '10', coinIcon = Config.UI.CoinIcon or '',
}

local function bool(v) return v == 1 or v == true end

local function mapItem(r)
    return {
        id = r.id, name = r.name, description = r.description or '', category = r.category,
        tags = DB.Decode(r.tags, {}), price = r.price, salePrice = r.sale_price, saleEnds = r.sale_ends_ts,
        images = DB.Decode(r.images, {}), spawnName = r.spawn_name, itemName = r.item_name, itemCount = r.item_count or 1,
        weaponName = r.weapon_name, trending = bool(r.trending), customCategory = r.custom_category,
        stock = r.stock, playerLimit = r.player_limit, enabled = bool(r.enabled), sort = r.sort, created = r.created_ts,
    }
end

function Catalog.Load()
    local rows = MySQL.query.await([[SELECT *, UNIX_TIMESTAMP(sale_ends) AS sale_ends_ts, UNIX_TIMESTAMP(created_at) AS created_ts
        FROM nayzeee_coinshop_items ORDER BY sort ASC, created_at ASC]]) or {}
    local items, byId = {}, {}
    for i, r in ipairs(rows) do
        local it = mapItem(r)
        items[i], byId[it.id] = it, it
    end
    Catalog.items, Catalog.byId = items, byId
    Catalog.categories = MySQL.query.await('SELECT id, name, icon, type, sort FROM nayzeee_coinshop_categories ORDER BY sort ASC, created_at ASC') or {}
    Catalog.deals = MySQL.query.await([[SELECT id, name, description, price, image, items, UNIX_TIMESTAMP(expires_at) AS expires
        FROM nayzeee_coinshop_deals ORDER BY created_at DESC]]) or {}
    for _, d in ipairs(Catalog.deals) do d.items = DB.Decode(d.items, {}) end
    local sold = {}
    for _, r in ipairs(MySQL.query.await("SELECT item_id, SUM(quantity) AS n FROM nayzeee_coinshop_purchases WHERE refunded = 0 GROUP BY item_id") or {}) do
        sold[r.item_id] = tonumber(r.n) or 0
    end
    Catalog.sold = sold
    local settings = {}
    for k, v in pairs(DefaultSettings) do settings[k] = v end
    for _, r in ipairs(MySQL.query.await("SELECT `key`, `value` FROM nayzeee_coinshop_settings WHERE `key` NOT LIKE '\\_%'") or {}) do
        settings[r.key] = r.value
    end
    Catalog.settings = settings
    Debug('Catalogue loaded: %d packages, %d categories, %d deals', #items, #Catalog.categories, #Catalog.deals)
end

function Catalog.Get(id) return Catalog.byId[tostring(id or '')] end

function Catalog.Price(it)
    if it.salePrice and it.salePrice >= 0 and it.salePrice < it.price and (not it.saleEnds or it.saleEnds > os.time()) then
        return it.salePrice, true
    end
    return it.price, false
end

-- Items as the UI sees them
function Catalog.Items(admin)
    local out, now = {}, os.time()
    for _, it in ipairs(Catalog.items) do
        if admin or it.enabled then
            local price, sale = Catalog.Price(it)
            out[#out + 1] = {
                id = it.id, name = it.name, description = it.description, category = it.category, tags = it.tags,
                price = price, basePrice = it.price, sale = sale, saleEnds = sale and it.saleEnds or nil,
                salePrice = admin and it.salePrice or nil, saleEndsRaw = admin and it.saleEnds or nil,
                images = it.images, itemCount = it.itemCount, trending = it.trending, customCategory = it.customCategory,
                stock = it.stock, playerLimit = it.playerLimit, sold = Catalog.sold[it.id] or 0, created = it.created,
                single = it.category == Categories.VEHICLE or (it.category == Categories.WEAPON and (not it.itemName or it.itemName == '')),
                enabled = it.enabled, isNew = it.created and now - it.created < 7 * 86400 or false,
                spawnName = it.spawnName, itemName = admin and it.itemName or nil, weaponName = admin and it.weaponName or nil,
            }
        end
    end
    return out
end

function Catalog.DealValue(d)
    local value, list = 0, {}
    for _, iid in ipairs(d.items) do
        local it = Catalog.Get(iid)
        if it then
            value = value + it.price
            list[#list + 1] = { id = it.id, name = it.name, price = it.price, image = it.images[1], category = it.category }
        end
    end
    return value, list
end

function Catalog.Deals(admin)
    local out, now = {}, os.time()
    for _, d in ipairs(Catalog.deals) do
        local left = d.expires and (d.expires - now) or nil
        if admin or not left or left > 0 then
            local value, list = Catalog.DealValue(d)
            out[#out + 1] = {
                id = d.id, name = d.name, description = d.description, price = d.price, image = d.image,
                items = list, itemIds = d.items, value = value, remaining = left and math.max(0, left) or nil,
            }
        end
    end
    return out
end

function Catalog.Changed()
    Catalog.Load()
    for src in pairs(Core.Open) do Push(src, 'catalog', true) end
end

AddEventHandler('nzc:dbReady', Catalog.Load)

-- ── boot ────────────────────────────────────────────────────────────────
local function profile(src)
    local p = promise.new()
    local done = false
    DiscordProfile(src, function(d) if not done then done = true p:resolve(d) end end)
    SetTimeout(2500, function() if not done then done = true p:resolve(nil) end end)
    return Citizen.Await(p)
end

Handle('boot', function(src, id)
    Core.Open[src] = true
    Wallet.Ensure(id)
    local name = Bridge.GetName(src)
    MySQL.update('UPDATE nayzeee_coinshop_wallets SET name = ? WHERE identifier = ?', { name, id })
    local w = MySQL.single.await('SELECT coins, spent FROM nayzeee_coinshop_wallets WHERE identifier = ?', { id }) or {}
    local favs = {}
    for _, r in ipairs(MySQL.query.await('SELECT item_id FROM nayzeee_coinshop_favorites WHERE identifier = ?', { id }) or {}) do favs[#favs + 1] = r.item_id end
    local admin = IsAdmin(src)
    local d = profile(src)
    return {
        me = { name = d and d.name or name, character = name, avatar = d and d.avatar or '', coins = w.coins or 0, spent = w.spent or 0, serverId = src },
        admin = admin,
        items = Catalog.Items(admin),
        categories = Catalog.categories,
        deals = Catalog.Deals(false),
        favorites = favs,
        settings = Catalog.settings,
        config = {
            version = NZC.Version, coinName = Config.General.CoinName, storeUrl = Config.General.StoreUrl,
            testDrive = Config.TestDrive.Enabled, testDriveTime = Config.TestDrive.Duration,
            giftItems = Config.Gifting.Items, transfer = Config.Gifting.CoinTransfer, transferFee = Config.Gifting.TransferFee,
            transferMin = Config.Gifting.TransferMin, maxQty = Config.Shop.MaxQuantity, dealMaxItems = Config.Shop.DealMaxItems,
            tutorial = Config.UI.Tutorial, playtime = Config.Playtime.Enabled and { minutes = Config.Playtime.Minutes, coins = Config.Playtime.Coins } or nil,
        },
    }
end)

RegisterNetEvent('nzc:closed', function() Core.Open[source] = nil end)

Handle('catalog', function(src)
    local admin = IsAdmin(src)
    return { items = Catalog.Items(admin), categories = Catalog.categories, deals = Catalog.Deals(false) }
end)

Handle('player:lookup', function(src, _, d)
    local target = tonumber(d.id)
    if not target or target == src or not GetPlayerName(target) then return nil, 'ERR_TARGET_OFFLINE' end
    if not Identify(target) then return nil, 'ERR_TARGET_OFFLINE' end
    return { id = target, name = Bridge.GetName(target) }
end)

-- ── delivery ────────────────────────────────────────────────────────────
local function newPlate()
    local prefix = (Config.Vehicles.PlatePrefix or ''):upper():sub(1, 4)
    for _ = 1, 25 do
        local plate = prefix .. tostring(math.random(10 ^ (7 - #prefix), 10 ^ (8 - #prefix) - 1))
        if not Bridge.PlateExists(plate) then return plate end
    end
    return prefix .. tostring(math.random(1000, 9999))
end

-- Give one package to a player. Returns ok, plate
function Deliver(src, it, qty)
    qty = qty or 1
    if it.category == Categories.VEHICLE then
        if not it.spawnName or it.spawnName == '' then return false end
        local plate = Bridge.AddVehicle(src, it.spawnName, newPlate())
        if not plate then return false end
        Bridge.GiveKeys(src, plate)
        TriggerClientEvent('nzc:vehicle', src, it.spawnName, plate, Config.Vehicles.SpawnOnPurchase)
        return true, plate
    elseif it.category == Categories.WEAPON and (not it.itemName or it.itemName == '') then
        if not it.weaponName or it.weaponName == '' then return false end
        for _ = 1, qty do
            if not Bridge.GiveWeapon(src, it.weaponName, Config.Weapons.Ammo) then return false end
        end
        return true
    end
    if not it.itemName or it.itemName == '' then return false end
    return Bridge.GiveItem(src, it.itemName, (it.itemCount or 1) * qty)
end

-- ── purchases ───────────────────────────────────────────────────────────
local busy, last = {}, {}

local function lock(id)
    local now = GetGameTimer()
    if busy[id] or (last[id] and now - last[id] < Config.Shop.PurchaseDelay) then return false end
    busy[id], last[id] = true, now
    return true
end
local function unlock(id) busy[id] = nil end

-- Resolve an optional gift target. Returns targetSrc, targetId or error
local function target(src, id, giftTo)
    if not giftTo or giftTo == '' then return src, id end
    if not Config.Gifting.Items then return nil, 'ERR_DISABLED' end
    local t = tonumber(giftTo)
    if not t or t == src or not GetPlayerName(t) then return nil, 'ERR_TARGET_OFFLINE' end
    local tid = Identify(t)
    if not tid then return nil, 'ERR_TARGET_OFFLINE' end
    return t, tid
end

local function record(id, src, kind, itemId, itemName, qty, price, tsrc, tid, plate)
    local gift = tsrc ~= src
    MySQL.insert([[INSERT INTO nayzeee_coinshop_purchases (identifier, player, kind, item_id, item_name, quantity, price, gifted_to, gifted_name, plate)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], { id, Bridge.GetName(src), kind, itemId, itemName, qty, price,
        gift and tid or nil, gift and Bridge.GetName(tsrc) or nil, plate })
end

local function buyItem(src, id, d)
    local it = Catalog.Get(d.id)
    if not it or not it.enabled then return nil, 'ERR_ITEM_NOT_FOUND' end
    local single = it.category == Categories.VEHICLE or (it.category == Categories.WEAPON and (not it.itemName or it.itemName == ''))
    local qty = single and 1 or NZC.Int(d.qty, 1, Config.Shop.MaxQuantity, 1)
    local tsrc, tid = target(src, id, d.gift)
    if not tsrc then return nil, tid end

    if it.playerLimit and it.playerLimit > 0 then
        local had = tonumber(MySQL.scalar.await([[SELECT IFNULL(SUM(quantity), 0) FROM nayzeee_coinshop_purchases
            WHERE identifier = ? AND item_id = ? AND refunded = 0]], { id, it.id })) or 0
        if had + qty > it.playerLimit then return nil, 'ERR_LIMIT', { math.max(0, it.playerLimit - had) } end
    end
    if it.stock then
        local n = MySQL.update.await('UPDATE nayzeee_coinshop_items SET stock = stock - ? WHERE id = ? AND stock >= ?', { qty, it.id, qty })
        if n ~= 1 then return nil, 'ERR_OUT_OF_STOCK' end
        it.stock = it.stock - qty
    end
    local function restock()
        if it.stock then
            MySQL.update.await('UPDATE nayzeee_coinshop_items SET stock = stock + ? WHERE id = ?', { qty, it.id })
            it.stock = it.stock + qty
        end
    end

    local unit = Catalog.Price(it)
    local total = unit * qty
    local ok, balance = Wallet.Take(id, total, 'purchase', ('%s x%d'):format(it.name, qty), true)
    if not ok then restock() return nil, 'ERR_NOT_ENOUGH' end

    local delivered, plate = Deliver(tsrc, it, qty)
    if not delivered then
        restock()
        Wallet.Refund(id, total, it.name)
        return nil, it.category == Categories.VEHICLE and 'ERR_VEHICLE' or 'ERR_DELIVERY'
    end

    record(id, src, 'item', it.id, it.name, qty, total, tsrc, tid, plate)
    Catalog.sold[it.id] = (Catalog.sold[it.id] or 0) + qty
    local gift = tsrc ~= src
    if gift then Notify(tsrc, T('N_GIFT_RECEIVED', Bridge.GetName(src), it.name), 'success') end
    TriggerEvent('nayzeee-coinshop:purchased', src, id, it.id, qty, total, gift and tsrc or nil)
    Webhook('purchases', gift and T('LOG_GIFT') or T('LOG_PURCHASE'), {
        { 'Player', Who(src) }, { 'Identifier', id }, { 'Package', ('%s (`%s`) x%d'):format(it.name, it.id, qty), false },
        { 'Price', ('%d %s'):format(total, Config.General.CoinName) }, { 'Balance', balance },
        gift and { 'Gifted to', Who(tsrc) } or nil, plate and { 'Plate', plate } or nil,
    })
    return { coins = balance, plate = plate, gift = gift and Bridge.GetName(tsrc) or nil, stock = it.stock, category = it.category, id = it.id }
end

local function buyDeal(src, id, d)
    local deal
    for _, x in ipairs(Catalog.deals) do if x.id == d.id then deal = x end end
    if not deal or (deal.expires and deal.expires <= os.time()) then return nil, 'ERR_DEAL_NOT_FOUND' end
    local value, list = Catalog.DealValue(deal)
    if #list == 0 then return nil, 'ERR_DEAL_EMPTY' end
    local tsrc, tid = target(src, id, d.gift)
    if not tsrc then return nil, tid end

    local ok, balance = Wallet.Take(id, deal.price, 'deal', deal.name, true)
    if not ok then return nil, 'ERR_NOT_ENOUGH' end

    local failed, failedValue, plates = {}, 0, {}
    for _, entry in ipairs(list) do
        local it = Catalog.Get(entry.id)
        local good, plate = Deliver(tsrc, it, 1)
        if good then
            if plate then plates[#plates + 1] = plate end
        else
            failed[#failed + 1] = it.name
            failedValue = failedValue + it.price
        end
    end
    if #failed == #list then
        Wallet.Refund(id, deal.price, deal.name)
        return nil, 'ERR_DELIVERY'
    end
    -- items that could not be delivered are refunded at their share of the deal price
    local refund = 0
    if #failed > 0 and value > 0 then
        refund = math.floor(deal.price * failedValue / value)
        if refund > 0 then balance = Wallet.Refund(id, refund, deal.name) end
        Notify(src, T('N_PARTIAL', table.concat(failed, ', '), refund, Config.General.CoinName), 'error')
    end

    record(id, src, 'deal', deal.id, deal.name, 1, deal.price - refund, tsrc, tid, plates[1])
    Catalog.sold[deal.id] = (Catalog.sold[deal.id] or 0) + 1
    local gift = tsrc ~= src
    if gift then Notify(tsrc, T('N_GIFT_RECEIVED', Bridge.GetName(src), deal.name), 'success') end
    Webhook('purchases', T('LOG_DEAL'), {
        { 'Player', Who(src) }, { 'Identifier', id }, { 'Deal', ('%s (`%s`)'):format(deal.name, deal.id), false },
        { 'Price', ('%d %s'):format(deal.price - refund, Config.General.CoinName) }, { 'Balance', balance },
        gift and { 'Gifted to', Who(tsrc) } or nil, #failed > 0 and { 'Not delivered', table.concat(failed, ', '), false } or nil,
    })
    return { coins = balance, failed = failed, refund = refund, gift = gift and Bridge.GetName(tsrc) or nil }
end

local function guarded(fn)
    return function(src, id, d)
        if not lock(id) then return nil, 'ERR_BUSY' end
        local ok, res, err, extra = pcall(fn, src, id, d)
        unlock(id)
        if not ok then Log('^1Purchase error: %s^0', tostring(res)) return nil, 'ERR_GENERIC' end
        return res, err, extra
    end
end

Handle('buy:item', guarded(buyItem))
Handle('buy:deal', guarded(buyDeal))

-- ── redeem ──────────────────────────────────────────────────────────────
local fails = {}

local function tooMany(src)
    local f = fails[src]
    local now = os.time()
    if f and now - f.t < 60 and f.n >= 6 then return true end
    return false
end

local function failed(src)
    local now = os.time()
    local f = fails[src]
    if not f or now - f.t >= 60 then fails[src] = { t = now, n = 1 } else f.n = f.n + 1 end
end

Handle('redeem:tebex', guarded(function(src, id, d)
    if tooMany(src) then return nil, 'ERR_RATE' end
    local key = tostring(d.code or ''):gsub('%s+', '')
    if key == '' or #key > 120 then failed(src) return nil, 'ERR_CODE_INVALID' end
    local tsrc, tid = src, id
    if d.gift and d.gift ~= '' then
        tsrc = tonumber(d.gift)
        tid = tsrc and tsrc ~= src and GetPlayerName(tsrc) and Identify(tsrc)
        if not tid then return nil, 'ERR_TARGET_OFFLINE' end
    end
    local row = MySQL.single.await('SELECT coins, status FROM nayzeee_coinshop_codes WHERE tbx_id = ?', { key })
    if not row then failed(src) return nil, 'ERR_CODE_INVALID' end
    if row.status ~= 'pending' then return nil, 'ERR_CODE_USED' end
    local n = MySQL.update.await("UPDATE nayzeee_coinshop_codes SET status = 'redeemed', redeemed_by = ?, redeemed_at = NOW() WHERE tbx_id = ? AND status = 'pending'", { tid, key })
    if n ~= 1 then return nil, 'ERR_CODE_USED' end
    local balance = Wallet.Add(tid, row.coins, 'redeem', key)
    local gift = tsrc ~= src
    if gift then Notify(tsrc, T('N_COINS_GIFTED', Bridge.GetName(src), row.coins, Config.General.CoinName), 'success') end
    Webhook('redeems', gift and T('LOG_REDEEM_GIFT') or T('LOG_REDEEM'), {
        { 'Player', Who(src) }, { 'Identifier', id }, { 'Order', '`' .. key .. '`', false }, { 'Coins', row.coins },
        gift and { 'Gifted to', Who(tsrc) } or nil,
    })
    TriggerEvent('nayzeee-coinshop:redeemed', src, id, key, row.coins, gift and tsrc or nil)
    return { coins = gift and Wallet.Get(id) or balance, amount = row.coins, gift = gift and Bridge.GetName(tsrc) or nil }
end))

Handle('redeem:promo', guarded(function(src, id, d)
    if tooMany(src) then return nil, 'ERR_RATE' end
    local code = NZC.Trim(d.code):upper()
    local p = code ~= '' and MySQL.single.await('SELECT coins, max_uses, uses, UNIX_TIMESTAMP(expires_at) AS exp FROM nayzeee_coinshop_promos WHERE code = ?', { code })
    if not p then failed(src) return nil, 'ERR_PROMO_INVALID' end
    if p.exp and p.exp <= os.time() then return nil, 'ERR_PROMO_EXPIRED' end
    if p.max_uses > 0 and p.uses >= p.max_uses then return nil, 'ERR_PROMO_USED_UP' end
    local ok = pcall(MySQL.insert.await, 'INSERT INTO nayzeee_coinshop_promo_uses (code, identifier) VALUES (?, ?)', { code, id })
    if not ok then return nil, 'ERR_PROMO_ALREADY' end
    local n = MySQL.update.await('UPDATE nayzeee_coinshop_promos SET uses = uses + 1 WHERE code = ? AND (max_uses = 0 OR uses < max_uses)', { code })
    if n ~= 1 then
        MySQL.update('DELETE FROM nayzeee_coinshop_promo_uses WHERE code = ? AND identifier = ?', { code, id })
        return nil, 'ERR_PROMO_USED_UP'
    end
    local balance = Wallet.Add(id, p.coins, 'promo', code)
    Webhook('redeems', T('LOG_PROMO'), { { 'Player', Who(src) }, { 'Identifier', id }, { 'Code', '`' .. code .. '`' }, { 'Coins', p.coins } })
    return { coins = balance, amount = p.coins }
end))

-- ── coin transfer ───────────────────────────────────────────────────────
Handle('transfer', guarded(function(src, id, d)
    local g = Config.Gifting
    if not g.CoinTransfer then return nil, 'ERR_DISABLED' end
    local amount = NZC.Int(d.amount, 0, 100000000, 0)
    if amount < g.TransferMin then return nil, 'ERR_TRANSFER_MIN', { g.TransferMin } end
    local t = tonumber(d.to)
    local tid = t and t ~= src and GetPlayerName(t) and Identify(t)
    if not tid then return nil, 'ERR_TARGET_OFFLINE' end
    local fee = math.floor(amount * math.max(0, math.min(50, g.TransferFee)) / 100)
    local ok, balance = Wallet.Take(id, amount, 'transfer_out', Bridge.GetName(t))
    if not ok then return nil, 'ERR_NOT_ENOUGH' end
    Wallet.Add(tid, amount - fee, 'transfer_in', Bridge.GetName(src))
    Notify(t, T('N_COINS_GIFTED', Bridge.GetName(src), amount - fee, Config.General.CoinName), 'success')
    Webhook('redeems', T('LOG_TRANSFER'), { { 'From', Who(src) }, { 'To', Who(t) }, { 'Amount', amount }, { 'Fee', fee } })
    return { coins = balance, sent = amount - fee, name = Bridge.GetName(t) }
end))

-- ── favourites + history ────────────────────────────────────────────────
Handle('favorite', function(_, id, d)
    local it = Catalog.Get(d.id)
    if not it then return nil, 'ERR_ITEM_NOT_FOUND' end
    if d.on then
        MySQL.insert.await('INSERT IGNORE INTO nayzeee_coinshop_favorites (identifier, item_id) VALUES (?, ?)', { id, it.id })
    else
        MySQL.update.await('DELETE FROM nayzeee_coinshop_favorites WHERE identifier = ? AND item_id = ?', { id, it.id })
    end
    return true
end)

Handle('history', function(_, id)
    local purchases = MySQL.query.await([[SELECT id, kind, item_id AS itemId, item_name AS name, quantity, price, gifted_name AS giftedTo, plate, refunded,
        UNIX_TIMESTAMP(purchased_at) AS date FROM nayzeee_coinshop_purchases WHERE identifier = ? ORDER BY id DESC LIMIT ?]], { id, Config.Shop.HistorySize }) or {}
    for _, p in ipairs(purchases) do
        p.refunded = bool(p.refunded)
        if not p.name then local it = Catalog.Get(p.itemId) p.name = it and it.name or p.itemId end
    end
    local gifts = MySQL.query.await([[SELECT player AS sender, item_name AS name, quantity, UNIX_TIMESTAMP(purchased_at) AS date
        FROM nayzeee_coinshop_purchases WHERE gifted_to = ? ORDER BY id DESC LIMIT 20]], { id }) or {}
    local ledger = MySQL.query.await([[SELECT delta, balance, reason, note, UNIX_TIMESTAMP(created_at) AS date
        FROM nayzeee_coinshop_ledger WHERE identifier = ? ORDER BY id DESC LIMIT 50]], { id }) or {}
    local w = MySQL.single.await('SELECT coins, spent FROM nayzeee_coinshop_wallets WHERE identifier = ?', { id }) or {}
    return { purchases = purchases, gifts = gifts, ledger = ledger, coins = w.coins or 0, spent = w.spent or 0 }
end)
