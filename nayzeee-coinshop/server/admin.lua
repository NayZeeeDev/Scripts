if not NAYZEEE_LOCK_OK then return end

--[[
    Admin panel: dashboard, catalogue editor (packages, categories, deals), players and coins,
    Tebex codes, promo codes, purchase logs with refunds, appearance.
]]

local A = { admin = true }

local function slug(s)
    return (tostring(s or ''):lower():gsub('%s+', '_'):gsub('[^%w_]', ''):sub(1, 40))
end

local function strList(v, max)
    local out = {}
    if type(v) ~= 'table' then return out end
    for _, x in ipairs(v) do
        x = NZC.Trim(x)
        if x ~= '' and #out < (max or 20) then out[#out + 1] = x:sub(1, 300) end
    end
    return out
end

local function nilIfEmpty(v)
    v = NZC.Trim(v)
    return v ~= '' and v or nil
end

local function adminLog(src, title, fields)
    table.insert(fields, 1, { 'Admin', Who(src) })
    Webhook('admin', title, fields)
end

-- ── dashboard ───────────────────────────────────────────────────────────
Handle('admin:dashboard', function()
    local s = MySQL.single.await([[SELECT
        IFNULL(SUM(price), 0) AS total,
        IFNULL(SUM(IF(purchased_at >= NOW() - INTERVAL 1 DAY, price, 0)), 0) AS day,
        IFNULL(SUM(purchased_at >= NOW() - INTERVAL 1 DAY), 0) AS dayCount,
        COUNT(*) AS count
        FROM nayzeee_coinshop_purchases WHERE refunded = 0]]) or {}
    local w = MySQL.single.await('SELECT IFNULL(SUM(coins), 0) AS circulating, COUNT(*) AS wallets FROM nayzeee_coinshop_wallets') or {}
    local c = MySQL.single.await("SELECT IFNULL(SUM(status = 'pending'), 0) AS pending, IFNULL(SUM(IF(status = 'redeemed' AND redeemed_at >= NOW() - INTERVAL 7 DAY, coins, 0)), 0) AS week FROM nayzeee_coinshop_codes") or {}
    local days = MySQL.query.await([[SELECT DATE_FORMAT(purchased_at, '%Y-%m-%d') AS day, SUM(price) AS coins, COUNT(*) AS sales
        FROM nayzeee_coinshop_purchases WHERE refunded = 0 AND purchased_at >= CURDATE() - INTERVAL 13 DAY GROUP BY day ORDER BY day]]) or {}
    local recent = MySQL.query.await([[SELECT id, player, identifier, kind, item_name AS name, item_id AS itemId, quantity, price, gifted_name AS giftedTo, refunded,
        UNIX_TIMESTAMP(purchased_at) AS date FROM nayzeee_coinshop_purchases ORDER BY id DESC LIMIT 8]]) or {}
    local top = MySQL.query.await([[SELECT item_id AS id, MAX(item_name) AS name, SUM(quantity) AS sales, SUM(price) AS coins
        FROM nayzeee_coinshop_purchases WHERE refunded = 0 GROUP BY item_id ORDER BY sales DESC LIMIT 6]]) or {}
    for _, r in ipairs(top) do
        local it = Catalog.Get(r.id)
        r.name = r.name or (it and it.name) or r.id
        r.image = it and it.images[1] or nil
    end
    for _, r in ipairs(recent) do r.name = r.name or r.itemId end
    local active = 0
    for _ in pairs(Core.Open) do active = active + 1 end
    return {
        packages = #Catalog.items, totalSales = tonumber(s.total) or 0, daySales = tonumber(s.day) or 0, dayCount = tonumber(s.dayCount) or 0,
        purchases = tonumber(s.count) or 0, online = #GetPlayers(), shopping = active, circulating = tonumber(w.circulating) or 0,
        wallets = tonumber(w.wallets) or 0, pendingCodes = tonumber(c.pending) or 0, redeemedWeek = tonumber(c.week) or 0,
        days = days, recent = recent, top = top,
    }
end, A)

-- ── logs + refunds ──────────────────────────────────────────────────────
Handle('admin:logs', function(_, _, d)
    local q = NZC.Trim(d.q)
    local like = '%' .. q:gsub('[%%_]', '') .. '%'
    local rows = MySQL.query.await([[SELECT id, player, identifier, kind, item_id AS itemId, item_name AS name, quantity, price, gifted_name AS giftedTo,
        plate, refunded, UNIX_TIMESTAMP(purchased_at) AS date FROM nayzeee_coinshop_purchases
        WHERE (? = '' OR player LIKE ? OR identifier LIKE ? OR item_name LIKE ? OR item_id LIKE ? OR plate LIKE ?)
        ORDER BY id DESC LIMIT 100]], { q, like, like, like, like, like }) or {}
    for _, r in ipairs(rows) do r.refunded = r.refunded == 1 or r.refunded == true r.name = r.name or r.itemId end
    return rows
end, A)

-- Gives the coins back. The delivered goods are NOT taken back (remove them by hand if needed).
Handle('admin:refund', function(src, _, d)
    local row = MySQL.single.await('SELECT identifier, item_id, item_name, quantity, price, refunded FROM nayzeee_coinshop_purchases WHERE id = ?', { tonumber(d.id) or 0 })
    if not row then return nil, 'ERR_NOT_FOUND' end
    local n = MySQL.update.await('UPDATE nayzeee_coinshop_purchases SET refunded = 1 WHERE id = ? AND refunded = 0', { tonumber(d.id) })
    if n ~= 1 then return nil, 'ERR_ALREADY_REFUNDED' end
    Wallet.Refund(row.identifier, row.price, row.item_name or row.item_id)
    Catalog.sold[row.item_id] = math.max(0, (Catalog.sold[row.item_id] or 0) - row.quantity)
    local s = Core.Online[row.identifier]
    if s then Notify(s, T('N_REFUNDED', row.price, Config.General.CoinName, row.item_name or row.item_id), 'inform') end
    adminLog(src, T('LOG_REFUND'), { { 'Purchase', '#' .. d.id }, { 'Identifier', row.identifier }, { 'Coins', row.price } })
    return true
end, A)

-- ── players ─────────────────────────────────────────────────────────────
Handle('admin:players', function(_, _, d)
    local out, ids = {}, {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local id = Identify(src)
        if id then
            out[#out + 1] = { id = src, identifier = id, name = Bridge.GetName(src), online = true, shopping = Core.Open[src] == true }
            ids[#ids + 1] = id
        end
    end
    if #ids > 0 then
        local marks = ('?,'):rep(#ids):sub(1, -2)
        local rows = MySQL.query.await(('SELECT identifier, coins, spent FROM nayzeee_coinshop_wallets WHERE identifier IN (%s)'):format(marks), ids) or {}
        local by = {}
        for _, r in ipairs(rows) do by[r.identifier] = r end
        for _, p in ipairs(out) do
            local r = by[p.identifier]
            p.coins, p.spent = r and r.coins or 0, r and r.spent or 0
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    -- offline search by character name / identifier
    local q = NZC.Trim(d.q)
    if #q >= 2 then
        local like = '%' .. q:gsub('[%%_]', '') .. '%'
        for _, r in ipairs(MySQL.query.await('SELECT identifier, name, coins, spent FROM nayzeee_coinshop_wallets WHERE name LIKE ? OR identifier LIKE ? LIMIT 25', { like, like }) or {}) do
            if not Core.Online[r.identifier] then
                out[#out + 1] = { identifier = r.identifier, name = r.name or r.identifier, coins = r.coins, spent = r.spent, online = false }
            end
        end
    end
    return out
end, A)

Handle('admin:ledger', function(_, _, d)
    local id = NZC.Trim(d.identifier)
    return MySQL.query.await([[SELECT delta, balance, reason, note, UNIX_TIMESTAMP(created_at) AS date FROM nayzeee_coinshop_ledger
        WHERE identifier = ? ORDER BY id DESC LIMIT 60]], { id }) or {}
end, A)

Handle('admin:coins', function(src, _, d)
    local id = NZC.Trim(d.identifier)
    if id == '' and tonumber(d.id) then id = Identify(tonumber(d.id)) or '' end
    if id == '' then return nil, 'ERR_PLAYER_NOT_FOUND' end
    local amount = NZC.Int(d.amount, 0, 100000000, 0)
    local before = Wallet.Get(id)
    local after
    if d.mode == 'give' then
        if amount <= 0 then return nil, 'ERR_AMOUNT' end
        after = Wallet.Add(id, amount, 'admin_give', Who(src))
    elseif d.mode == 'remove' then
        if amount <= 0 then return nil, 'ERR_AMOUNT' end
        local _
        _, after = Wallet.Take(id, math.min(amount, before), 'admin_remove', Who(src))
    else
        after = Wallet.Set(id, amount, 'admin_set', Who(src))
    end
    local t = Core.Online[id]
    if t and t ~= src then Notify(t, T('N_COINS_NOW', after), 'inform') end
    adminLog(src, T('LOG_ADMIN_COINS'), { { 'Target', t and Who(t) or id }, { 'Mode', d.mode or 'set' }, { 'Balance', ('%d → %d'):format(before, after) } })
    return { coins = after }
end, A)

-- ── packages ────────────────────────────────────────────────────────────
local VALID = { vehicle = true, item = true, weapon = true, tool = true }

local function itemPayload(d)
    local name = NZC.Trim(d.name)
    if name == '' then return nil, 'ERR_NAME_REQUIRED' end
    local cat = VALID[d.category] and d.category or 'item'
    local v = {
        name = name:sub(1, 100), description = NZC.Trim(d.description):sub(1, 500), category = cat,
        tags = json.encode(strList(d.tags, 8)), price = NZC.Int(d.price, 0, 100000000, 0),
        salePrice = (tonumber(d.salePrice) and tonumber(d.salePrice) >= 0) and NZC.Int(d.salePrice, 0, 100000000, 0) or nil,
        saleEnds = tonumber(d.saleHours) and tonumber(d.saleHours) > 0 and NZC.Int(d.saleHours, 1, 24 * 365, 24) or nil,
        images = json.encode(strList(d.images, 8)), spawnName = nilIfEmpty(d.spawnName), itemName = nilIfEmpty(d.itemName),
        itemCount = NZC.Int(d.itemCount, 1, 100000, 1), weaponName = nilIfEmpty(d.weaponName), trending = d.trending and 1 or 0,
        customCategory = (d.customCategory ~= 'none' and nilIfEmpty(d.customCategory)) or nil,
        stock = (tonumber(d.stock) and tonumber(d.stock) >= 0) and NZC.Int(d.stock, 0, 10000000, 0) or nil,
        playerLimit = (tonumber(d.playerLimit) and tonumber(d.playerLimit) > 0) and NZC.Int(d.playerLimit, 1, 100000, 1) or nil,
        enabled = d.enabled == false and 0 or 1,
    }
    if v.salePrice and v.salePrice >= v.price then v.salePrice, v.saleEnds = nil, nil end
    if cat == 'vehicle' and not v.spawnName then return nil, 'ERR_SPAWN_REQUIRED' end
    if (cat == 'item' or cat == 'tool') and not v.itemName then return nil, 'ERR_ITEMNAME_REQUIRED' end
    if cat == 'weapon' and not v.weaponName and not v.itemName then return nil, 'ERR_WEAPON_REQUIRED' end
    return v
end

local function saleSql(v, keepExisting)
    if v.saleEnds then return 'DATE_ADD(NOW(), INTERVAL ' .. v.saleEnds .. ' HOUR)' end
    if keepExisting and v.salePrice then return 'sale_ends' end
    return 'NULL'
end

Handle('admin:item:save', function(src, _, d)
    local v, err = itemPayload(d)
    if not v then return nil, err end
    local id = NZC.Trim(d.id)
    local editing = id ~= '' and Catalog.Get(id) ~= nil
    if editing then
        MySQL.update.await(([[UPDATE nayzeee_coinshop_items SET name=?, description=?, category=?, tags=?, price=?, sale_price=?, sale_ends=%s, images=?,
            spawn_name=?, item_name=?, item_count=?, weapon_name=?, trending=?, custom_category=?, stock=?, player_limit=?, enabled=? WHERE id=?]]):format(saleSql(v, not d.saleHours)), {
            v.name, v.description, v.category, v.tags, v.price, v.salePrice, v.images, v.spawnName, v.itemName, v.itemCount, v.weaponName,
            v.trending, v.customCategory, v.stock, v.playerLimit, v.enabled, id })
    else
        id = slug(id ~= '' and id or v.name)
        if id == '' or Catalog.Get(id) then id = (id ~= '' and id or 'pkg') .. '_' .. math.random(1000, 9999) end
        local sort = (MySQL.scalar.await('SELECT IFNULL(MAX(sort), 0) + 1 FROM nayzeee_coinshop_items') or 1)
        MySQL.insert.await(([[INSERT INTO nayzeee_coinshop_items (id, name, description, category, tags, price, sale_price, sale_ends, images, spawn_name, item_name,
            item_count, weapon_name, trending, custom_category, stock, player_limit, enabled, sort) VALUES (?, ?, ?, ?, ?, ?, ?, %s, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]]):format(saleSql(v)), {
            id, v.name, v.description, v.category, v.tags, v.price, v.salePrice, v.images, v.spawnName, v.itemName, v.itemCount, v.weaponName,
            v.trending, v.customCategory, v.stock, v.playerLimit, v.enabled, sort })
    end
    Catalog.Changed()
    adminLog(src, editing and T('LOG_ITEM_EDITED') or T('LOG_ITEM_CREATED'), { { 'Package', ('%s (`%s`)'):format(v.name, id) }, { 'Category', v.category }, { 'Price', v.price } })
    return { id = id }
end, A)

Handle('admin:item:toggle', function(src, _, d)
    local it = Catalog.Get(d.id)
    if not it then return nil, 'ERR_ITEM_NOT_FOUND' end
    local field = d.field == 'trending' and 'trending' or 'enabled'
    local value = d.field == 'trending' and not it.trending or not it.enabled
    MySQL.update.await(('UPDATE nayzeee_coinshop_items SET %s = ? WHERE id = ?'):format(field), { value and 1 or 0, it.id })
    Catalog.Changed()
    adminLog(src, T('LOG_ITEM_EDITED'), { { 'Package', it.name }, { field, tostring(value) } })
    return true
end, A)

Handle('admin:item:delete', function(src, _, d)
    local it = Catalog.Get(d.id)
    if not it then return nil, 'ERR_ITEM_NOT_FOUND' end
    MySQL.update.await('DELETE FROM nayzeee_coinshop_items WHERE id = ?', { it.id })
    MySQL.update.await('DELETE FROM nayzeee_coinshop_favorites WHERE item_id = ?', { it.id })
    Catalog.Changed()
    adminLog(src, T('LOG_ITEM_DELETED'), { { 'Package', ('%s (`%s`)'):format(it.name, it.id) } })
    return true
end, A)

-- Reorder: list of ids in display order
Handle('admin:item:order', function(_, _, d)
    local ids = strList(d.ids, 1000)
    local q = {}
    for i, id in ipairs(ids) do q[#q + 1] = { query = 'UPDATE nayzeee_coinshop_items SET sort = ? WHERE id = ?', values = { i, id } } end
    if #q > 0 then MySQL.transaction.await(q) end
    Catalog.Changed()
    return true
end, A)

-- ── categories ──────────────────────────────────────────────────────────
Handle('admin:category:save', function(src, _, d)
    local name = NZC.Trim(d.name)
    if name == '' then return nil, 'ERR_NAME_REQUIRED' end
    local icon = NZC.Trim(d.icon):sub(1, 500)
    local id = NZC.Trim(d.id)
    local editing = false
    for _, c in ipairs(Catalog.categories) do if c.id == id then editing = true end end
    if editing then
        MySQL.update.await('UPDATE nayzeee_coinshop_categories SET name = ?, icon = ? WHERE id = ?', { name:sub(1, 100), icon, id })
    else
        id = slug(name)
        if id == '' then id = 'cat_' .. math.random(1000, 9999) end
        for _, c in ipairs(Catalog.categories) do if c.id == id then return nil, 'ERR_CATEGORY_EXISTS' end end
        local sort = (MySQL.scalar.await('SELECT IFNULL(MAX(sort), 0) + 1 FROM nayzeee_coinshop_categories') or 1)
        MySQL.insert.await('INSERT INTO nayzeee_coinshop_categories (id, name, icon, sort) VALUES (?, ?, ?, ?)', { id, name:sub(1, 100), icon, sort })
    end
    Catalog.Changed()
    adminLog(src, editing and T('LOG_CATEGORY_EDITED') or T('LOG_CATEGORY_CREATED'), { { 'Category', ('%s (`%s`)'):format(name, id) } })
    return { id = id }
end, A)

Handle('admin:category:delete', function(src, _, d)
    local id = NZC.Trim(d.id)
    MySQL.update.await('DELETE FROM nayzeee_coinshop_categories WHERE id = ?', { id })
    MySQL.update.await('UPDATE nayzeee_coinshop_items SET custom_category = NULL WHERE custom_category = ?', { id })
    Catalog.Changed()
    adminLog(src, T('LOG_CATEGORY_DELETED'), { { 'Category', '`' .. id .. '`' } })
    return true
end, A)

Handle('admin:category:move', function(_, _, d)
    local list = Catalog.categories
    local idx
    for i, c in ipairs(list) do if c.id == d.id then idx = i end end
    local to = idx and idx + (d.dir == 'up' and -1 or 1)
    if not idx or to < 1 or to > #list then return true end
    list[idx], list[to] = list[to], list[idx]
    local q = {}
    for i, c in ipairs(list) do q[#q + 1] = { query = 'UPDATE nayzeee_coinshop_categories SET sort = ? WHERE id = ?', values = { i, c.id } } end
    MySQL.transaction.await(q)
    Catalog.Changed()
    return true
end, A)

-- ── deals ───────────────────────────────────────────────────────────────
Handle('admin:deal:save', function(src, _, d)
    local name = NZC.Trim(d.name)
    if name == '' then return nil, 'ERR_NAME_REQUIRED' end
    local items = {}
    for _, iid in ipairs(strList(d.items, Config.Shop.DealMaxItems)) do if Catalog.Get(iid) then items[#items + 1] = iid end end
    if #items == 0 then return nil, 'ERR_DEAL_ITEMS', { Config.Shop.DealMaxItems } end
    local hours = tonumber(d.hours)
    local price = NZC.Int(d.price, 0, 100000000, 0)
    local id = NZC.Trim(d.id)
    local editing = false
    for _, x in ipairs(Catalog.deals) do if x.id == id then editing = true end end
    local expiry = (hours and hours > 0) and ('DATE_ADD(NOW(), INTERVAL %d MINUTE)'):format(math.floor(hours * 60)) or (editing and d.keepExpiry and 'expires_at' or 'NULL')
    if editing then
        MySQL.update.await(('UPDATE nayzeee_coinshop_deals SET name = ?, description = ?, price = ?, image = ?, items = ?, expires_at = %s WHERE id = ?'):format(expiry),
            { name:sub(1, 100), NZC.Trim(d.description):sub(1, 500), price, NZC.Trim(d.image):sub(1, 500), json.encode(items), id })
    else
        id = 'deal_' .. slug(name) .. '_' .. math.random(1000, 9999)
        MySQL.insert.await(('INSERT INTO nayzeee_coinshop_deals (id, name, description, price, image, items, expires_at) VALUES (?, ?, ?, ?, ?, ?, %s)'):format(expiry),
            { id, name:sub(1, 100), NZC.Trim(d.description):sub(1, 500), price, NZC.Trim(d.image):sub(1, 500), json.encode(items) })
    end
    MySQL.update('DELETE FROM nayzeee_coinshop_deals WHERE expires_at IS NOT NULL AND expires_at < NOW() - INTERVAL 7 DAY')
    Catalog.Changed()
    adminLog(src, editing and T('LOG_DEAL_EDITED') or T('LOG_DEAL_CREATED'), { { 'Deal', ('%s (`%s`)'):format(name, id) }, { 'Price', price }, { 'Packages', #items } })
    return { id = id }
end, A)

Handle('admin:deal:delete', function(src, _, d)
    MySQL.update.await('DELETE FROM nayzeee_coinshop_deals WHERE id = ?', { NZC.Trim(d.id) })
    Catalog.Changed()
    adminLog(src, T('LOG_DEAL_DELETED'), { { 'Deal', '`' .. NZC.Trim(d.id) .. '`' } })
    return true
end, A)

Handle('admin:deals', function() return Catalog.Deals(true) end, A)

Handle('admin:clear', function(src, _, d)
    if d.confirm ~= 'CLEAR' then return nil, 'ERR_CONFIRM' end
    MySQL.query.await('DELETE FROM nayzeee_coinshop_items')
    MySQL.query.await('DELETE FROM nayzeee_coinshop_categories')
    MySQL.query.await('DELETE FROM nayzeee_coinshop_deals')
    MySQL.query.await('DELETE FROM nayzeee_coinshop_favorites')
    Catalog.Changed()
    adminLog(src, T('LOG_CLEAR'), { { 'Action', 'All packages, categories and deals removed', false } })
    return true
end, A)

-- ── Tebex codes ─────────────────────────────────────────────────────────
Handle('admin:codes', function(_, _, d)
    local q = NZC.Trim(d.q)
    local like = '%' .. q:gsub('[%%_]', '') .. '%'
    local codes = MySQL.query.await([[SELECT c.tbx_id AS code, c.coins, c.status, c.source, c.redeemed_by AS redeemedBy, w.name AS redeemedName,
        UNIX_TIMESTAMP(c.redeemed_at) AS redeemedAt, UNIX_TIMESTAMP(c.created_at) AS created
        FROM nayzeee_coinshop_codes c LEFT JOIN nayzeee_coinshop_wallets w ON w.identifier = c.redeemed_by
        WHERE (? = '' OR c.tbx_id LIKE ? OR c.redeemed_by LIKE ? OR w.name LIKE ?) ORDER BY c.id DESC LIMIT 80]], { q, like, like, like }) or {}
    local promos = MySQL.query.await([[SELECT code, coins, max_uses AS maxUses, uses, UNIX_TIMESTAMP(expires_at) AS expires, created_by AS createdBy,
        UNIX_TIMESTAMP(created_at) AS created FROM nayzeee_coinshop_promos ORDER BY created_at DESC]]) or {}
    return { codes = codes, promos = promos }
end, A)

-- Manual gift card style code (same flow as Tebex codes)
Handle('admin:code:create', function(src, _, d)
    local coins = NZC.Int(d.coins, 0, 100000000, 0)
    if coins <= 0 then return nil, 'ERR_AMOUNT' end
    local code = NZC.Trim(d.code)
    if code == '' then
        local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
        local parts = {}
        for p = 1, 3 do
            local s = ''
            for _ = 1, 4 do local i = math.random(1, #chars) s = s .. chars:sub(i, i) end
            parts[p] = s
        end
        code = 'NZ-' .. table.concat(parts, '-')
    end
    local ok = pcall(MySQL.insert.await, "INSERT INTO nayzeee_coinshop_codes (tbx_id, coins, status, source) VALUES (?, ?, 'pending', 'manual')", { code:sub(1, 120), coins })
    if not ok then return nil, 'ERR_CODE_EXISTS' end
    adminLog(src, T('LOG_CODE_CREATED'), { { 'Code', '`' .. code .. '`' }, { 'Coins', coins } })
    return { code = code }
end, A)

Handle('admin:code:delete', function(src, _, d)
    MySQL.update.await("DELETE FROM nayzeee_coinshop_codes WHERE tbx_id = ? AND status = 'pending'", { NZC.Trim(d.code) })
    adminLog(src, T('LOG_CODE_DELETED'), { { 'Code', '`' .. NZC.Trim(d.code) .. '`' } })
    return true
end, A)

Handle('admin:promo:create', function(src, _, d)
    local code = NZC.Trim(d.code):upper():gsub('[^%w%-_]', ''):sub(1, 40)
    local coins = NZC.Int(d.coins, 0, 100000000, 0)
    if code == '' then return nil, 'ERR_NAME_REQUIRED' end
    if coins <= 0 then return nil, 'ERR_AMOUNT' end
    local hours = tonumber(d.hours)
    local expiry = (hours and hours > 0) and ('DATE_ADD(NOW(), INTERVAL %d MINUTE)'):format(math.floor(hours * 60)) or 'NULL'
    local ok = pcall(MySQL.insert.await, ('INSERT INTO nayzeee_coinshop_promos (code, coins, max_uses, expires_at, created_by) VALUES (?, ?, ?, %s, ?)'):format(expiry),
        { code, coins, NZC.Int(d.maxUses, 0, 10000000, 0), Bridge.GetName(src) })
    if not ok then return nil, 'ERR_CODE_EXISTS' end
    adminLog(src, T('LOG_PROMO_CREATED'), { { 'Code', '`' .. code .. '`' }, { 'Coins', coins }, { 'Max uses', NZC.Int(d.maxUses, 0, 10000000, 0) } })
    return { code = code }
end, A)

Handle('admin:promo:delete', function(src, _, d)
    local code = NZC.Trim(d.code)
    MySQL.update.await('DELETE FROM nayzeee_coinshop_promos WHERE code = ?', { code })
    MySQL.update.await('DELETE FROM nayzeee_coinshop_promo_uses WHERE code = ?', { code })
    adminLog(src, T('LOG_PROMO_DELETED'), { { 'Code', '`' .. code .. '`' } })
    return true
end, A)

-- ── appearance ──────────────────────────────────────────────────────────
Handle('admin:settings', function(src, _, d)
    if d.reset then
        MySQL.query.await("DELETE FROM nayzeee_coinshop_settings WHERE `key` NOT LIKE '\\_%'")
    else
        local q = {}
        for k in pairs(DefaultSettings) do
            local v = d.values and d.values[k]
            if type(v) == 'string' or type(v) == 'number' then
                q[#q + 1] = { query = 'INSERT INTO nayzeee_coinshop_settings (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)',
                    values = { k, tostring(v):sub(1, 500) } }
            end
        end
        if #q > 0 then MySQL.transaction.await(q) end
    end
    Catalog.Changed()
    adminLog(src, d.reset and T('LOG_SETTINGS_RESET') or T('LOG_SETTINGS'), {})
    return Catalog.settings
end, A)
