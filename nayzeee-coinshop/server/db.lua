if not NAYZEEE_LOCK_OK then return end

--[[
    Database: tables, first-start seed and a one-time import from FearX-Coinshop tables
    (wallets, catalogue, deals, Tebex codes, redeems and purchase history).
]]

DB = { ready = false }

local tables = {
    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_wallets (
        identifier VARCHAR(80) NOT NULL,
        coins INT NOT NULL DEFAULT 0,
        spent INT NOT NULL DEFAULT 0,
        name VARCHAR(100) DEFAULT NULL,
        playtime_day DATE DEFAULT NULL,
        playtime_coins INT NOT NULL DEFAULT 0,
        updated TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (identifier)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_items (
        id VARCHAR(60) NOT NULL,
        name VARCHAR(100) NOT NULL,
        description VARCHAR(500) NOT NULL DEFAULT '',
        category VARCHAR(16) NOT NULL DEFAULT 'item',
        tags TEXT,
        price INT NOT NULL DEFAULT 0,
        sale_price INT DEFAULT NULL,
        sale_ends TIMESTAMP NULL DEFAULT NULL,
        images TEXT,
        spawn_name VARCHAR(60) DEFAULT NULL,
        item_name VARCHAR(60) DEFAULT NULL,
        item_count INT NOT NULL DEFAULT 1,
        weapon_name VARCHAR(60) DEFAULT NULL,
        trending TINYINT(1) NOT NULL DEFAULT 0,
        custom_category VARCHAR(60) DEFAULT NULL,
        stock INT DEFAULT NULL,
        player_limit INT DEFAULT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        sort INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_categories (
        id VARCHAR(60) NOT NULL,
        name VARCHAR(100) NOT NULL,
        icon VARCHAR(500) NOT NULL DEFAULT '',
        type VARCHAR(16) DEFAULT NULL,
        sort INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_deals (
        id VARCHAR(60) NOT NULL,
        name VARCHAR(100) NOT NULL,
        description VARCHAR(500) NOT NULL DEFAULT '',
        price INT NOT NULL DEFAULT 0,
        image VARCHAR(500) NOT NULL DEFAULT '',
        items TEXT,
        stock INT DEFAULT NULL,
        player_limit INT DEFAULT NULL,
        cash INT NOT NULL DEFAULT 0,
        featured TINYINT(1) NOT NULL DEFAULT 1,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        sort INT NOT NULL DEFAULT 0,
        expires_at TIMESTAMP NULL DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_codes (
        id INT NOT NULL AUTO_INCREMENT,
        tbx_id VARCHAR(120) NOT NULL,
        coins INT NOT NULL DEFAULT 0,
        status VARCHAR(16) NOT NULL DEFAULT 'pending',
        source VARCHAR(16) NOT NULL DEFAULT 'tebex',
        redeemed_by VARCHAR(80) DEFAULT NULL,
        redeemed_at TIMESTAMP NULL DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_tbx (tbx_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_promos (
        code VARCHAR(40) NOT NULL,
        coins INT NOT NULL DEFAULT 0,
        max_uses INT NOT NULL DEFAULT 0,
        uses INT NOT NULL DEFAULT 0,
        expires_at TIMESTAMP NULL DEFAULT NULL,
        created_by VARCHAR(100) DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (code)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_promo_uses (
        code VARCHAR(40) NOT NULL,
        identifier VARCHAR(80) NOT NULL,
        used_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (code, identifier)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_purchases (
        id INT NOT NULL AUTO_INCREMENT,
        identifier VARCHAR(80) NOT NULL,
        player VARCHAR(100) DEFAULT NULL,
        kind VARCHAR(8) NOT NULL DEFAULT 'item',
        item_id VARCHAR(60) NOT NULL,
        item_name VARCHAR(100) DEFAULT NULL,
        quantity INT NOT NULL DEFAULT 1,
        price INT NOT NULL,
        gifted_to VARCHAR(80) DEFAULT NULL,
        gifted_name VARCHAR(100) DEFAULT NULL,
        plate VARCHAR(12) DEFAULT NULL,
        refunded TINYINT(1) NOT NULL DEFAULT 0,
        purchased_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY k_identifier (identifier, purchased_at),
        KEY k_item (item_id),
        KEY k_date (purchased_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_ledger (
        id INT NOT NULL AUTO_INCREMENT,
        identifier VARCHAR(80) NOT NULL,
        delta INT NOT NULL,
        balance INT NOT NULL,
        reason VARCHAR(24) NOT NULL,
        note VARCHAR(160) DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY k_identifier (identifier, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_favorites (
        identifier VARCHAR(80) NOT NULL,
        item_id VARCHAR(60) NOT NULL,
        PRIMARY KEY (identifier, item_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_coinshop_settings (
        `key` VARCHAR(50) NOT NULL,
        `value` TEXT NOT NULL,
        PRIMARY KEY (`key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

function DB.Decode(s, fallback)
    if type(s) ~= 'string' or s == '' then return fallback end
    local ok, v = pcall(json.decode, s)
    return ok and v or fallback
end

local function exists(tbl)
    return (MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { tbl }) or 0) > 0
end

local function hasColumn(tbl, col)
    return (MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?', { tbl, col }) or 0) > 0
end

-- Columns added after v1.0.0. Added one by one so it works on MySQL and MariaDB.
local columns = {
    { 'nayzeee_coinshop_deals', 'stock',        'INT DEFAULT NULL' },
    { 'nayzeee_coinshop_deals', 'player_limit', 'INT DEFAULT NULL' },
    { 'nayzeee_coinshop_deals', 'cash',         'INT NOT NULL DEFAULT 0' },
    { 'nayzeee_coinshop_deals', 'featured',     'TINYINT(1) NOT NULL DEFAULT 1' },
    { 'nayzeee_coinshop_deals', 'enabled',      'TINYINT(1) NOT NULL DEFAULT 1' },
    { 'nayzeee_coinshop_deals', 'sort',         'INT NOT NULL DEFAULT 0' },
}

local function migrate()
    for _, c in ipairs(columns) do
        if not hasColumn(c[1], c[2]) then
            local ok, err = pcall(MySQL.query.await, ('ALTER TABLE %s ADD COLUMN `%s` %s'):format(c[1], c[2], c[3]))
            if ok then Log('Added column %s.%s', c[1], c[2]) else Log('^1Could not add column %s.%s: %s^0', c[1], c[2], tostring(err)) end
        end
    end
end

local function flag(key)
    return MySQL.scalar.await('SELECT `value` FROM nayzeee_coinshop_settings WHERE `key` = ?', { key })
end

local function setFlag(key)
    MySQL.query.await('INSERT INTO nayzeee_coinshop_settings (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)', { key, '1' })
end

-- One time copy of FearX-Coinshop data so nobody loses coins or unredeemed codes
local function importFearx()
    if flag('_imported_fearx') or not exists('fearx_coinshop') then return end
    Log('Importing FearX-Coinshop data...')
    local steps = {
        [[INSERT IGNORE INTO nayzeee_coinshop_wallets (identifier, coins) SELECT identifier, coins FROM fearx_coinshop]],
        [[INSERT IGNORE INTO nayzeee_coinshop_categories (id, name, icon, type) SELECT id, name, IF(icon LIKE 'data:%', '', icon), type FROM fearx_coinshop_categories]],
        [[INSERT IGNORE INTO nayzeee_coinshop_items (id, name, description, category, tags, price, images, spawn_name, item_name, item_count, weapon_name, trending, custom_category, created_at)
            SELECT id, name, IFNULL(description, ''), category, tags, price, images, spawn_name, item_name, IFNULL(item_count, 1), weapon_name, IFNULL(trending, 0), custom_category, created_at FROM fearx_coinshop_items]],
        [[INSERT IGNORE INTO nayzeee_coinshop_deals (id, name, description, price, image, items, expires_at, created_at)
            SELECT id, name, IFNULL(description, ''), price, IFNULL(image, ''), items, expires_at, created_at FROM fearx_coinshop_deals]],
        [[INSERT IGNORE INTO nayzeee_coinshop_codes (tbx_id, coins, status, redeemed_by, redeemed_at, created_at)
            SELECT tbx_id, coins, status, redeemed_by, redeemed_at, created_at FROM fearx_coinshop_codes]],
        [[INSERT INTO nayzeee_coinshop_purchases (identifier, item_id, price, purchased_at)
            SELECT identifier, item_id, price, purchased_at FROM fearx_coinshop_purchases]],
    }
    for _, q in ipairs(steps) do
        local ok, err = pcall(MySQL.query.await, q)
        if not ok then Log('^3Import step skipped: %s^0', tostring(err)) end
    end
    -- default category icons for imported base categories
    for _, c in ipairs(SeedData.Categories) do
        MySQL.update.await("UPDATE nayzeee_coinshop_categories SET icon = ?, sort = ? WHERE id = ? AND icon = ''", { c.icon, c.sort, c.id })
    end
    setFlag('_imported_fearx')
    setFlag('_seeded')
    Log('FearX-Coinshop import complete')
end

local function seed()
    if flag('_seeded') then return end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_coinshop_categories') or 0) == 0 then
        for _, c in ipairs(SeedData.Categories) do
            MySQL.insert.await('INSERT INTO nayzeee_coinshop_categories (id, name, icon, type, sort) VALUES (?, ?, ?, ?, ?)', { c.id, c.name, c.icon, c.type, c.sort })
        end
    end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_coinshop_items') or 0) == 0 then
        local q = {}
        for i, it in ipairs(SeedData.Items) do
            q[#q + 1] = { query = [[INSERT INTO nayzeee_coinshop_items (id, name, description, category, tags, price, images, spawn_name, item_name, item_count, weapon_name, trending, sort)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], values = {
                it.id, it.name, it.desc or '', it.category, json.encode(it.tags or {}), it.price, json.encode(it.image ~= '' and { it.image } or {}),
                it.spawn, it.item, it.count or 1, it.weapon, it.trending and 1 or 0, i,
            } }
        end
        MySQL.transaction.await(q)
    end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_coinshop_deals') or 0) == 0 then
        for _, d in ipairs(SeedData.Deals) do
            local entries = {}
            for _, e in ipairs(d.items) do entries[#entries + 1] = type(e) == 'table' and e or { id = e, qty = 1 } end
            MySQL.insert.await([[INSERT INTO nayzeee_coinshop_deals (id, name, description, price, image, items, featured, sort, expires_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, 1, DATE_ADD(NOW(), INTERVAL ? DAY))]],
                { d.id, d.name, d.description, d.price, d.image, json.encode(entries), d.days })
        end
    end
    setFlag('_seeded')
    Log('Seeded the default catalogue (%d packages)', #SeedData.Items)
end

MySQL.ready(function()
    for _, q in ipairs(tables) do
        local ok, err = pcall(MySQL.query.await, q)
        if not ok then Log('^1Table setup failed: %s^0', tostring(err)) return end
    end
    migrate()
    importFearx()
    seed()
    DB.ready = true
    TriggerEvent('nzc:dbReady')
end)
