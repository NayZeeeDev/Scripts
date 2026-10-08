-----------------------------------------------------------------
-- Database: schema, caches and small query helpers
-----------------------------------------------------------------
DB = {}

local schema = {
    [[CREATE TABLE IF NOT EXISTS `nz_cargo_profiles` (
        `identifier` VARCHAR(64) NOT NULL PRIMARY KEY,
        `name` VARCHAR(64) DEFAULT NULL,
        `xp` INT NOT NULL DEFAULT 0,
        `sourced` INT NOT NULL DEFAULT 0,
        `sold` INT NOT NULL DEFAULT 0,
        `failed` INT NOT NULL DEFAULT 0,
        `earned` BIGINT NOT NULL DEFAULT 0,
        `best_sale` INT NOT NULL DEFAULT 0,
        `clean_streak` INT NOT NULL DEFAULT 0,
        `source_cd` INT NOT NULL DEFAULT 0,
        `sell_cd` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]],
    [[CREATE TABLE IF NOT EXISTS `nz_cargo_locations` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `name` VARCHAR(64) NOT NULL,
        `price` INT NOT NULL DEFAULT 0,
        `door` VARCHAR(160) NOT NULL,
        `garage` VARCHAR(160) NOT NULL,
        `spawn` VARCHAR(160) NOT NULL,
        `enabled` TINYINT NOT NULL DEFAULT 1
    )]],
    [[CREATE TABLE IF NOT EXISTS `nz_cargo_warehouses` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `owner` VARCHAR(64) NOT NULL,
        `owner_name` VARCHAR(64) DEFAULT NULL,
        `location` INT NOT NULL,
        `upgrades` LONGTEXT DEFAULT NULL,
        `associates` LONGTEXT DEFAULT NULL,
        `paid` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX `owner_idx` (`owner`)
    )]],
    [[CREATE TABLE IF NOT EXISTS `nz_cargo_stock` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `warehouse` INT NOT NULL,
        `model` VARCHAR(64) NOT NULL,
        `label` VARCHAR(64) NOT NULL,
        `base_rarity` VARCHAR(16) NOT NULL,
        `rarity` VARCHAR(16) NOT NULL,
        `value` INT NOT NULL DEFAULT 0,
        `cond` INT NOT NULL DEFAULT 100,
        `build` LONGTEXT DEFAULT NULL,
        `score` INT NOT NULL DEFAULT 0,
        `props` LONGTEXT DEFAULT NULL,
        `plate` VARCHAR(12) DEFAULT NULL,
        `status` VARCHAR(16) NOT NULL DEFAULT 'stored',
        `offers` LONGTEXT DEFAULT NULL,
        `offers_at` INT NOT NULL DEFAULT 0,
        `sourced_by` VARCHAR(64) DEFAULT NULL,
        `sourced_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX `wh_idx` (`warehouse`)
    )]],
    [[CREATE TABLE IF NOT EXISTS `nz_cargo_custom_vehicles` (
        `model` VARCHAR(64) NOT NULL PRIMARY KEY,
        `label` VARCHAR(64) NOT NULL,
        `rarity` VARCHAR(16) NOT NULL,
        `value` INT NOT NULL DEFAULT 0,
        `enabled` TINYINT NOT NULL DEFAULT 1
    )]],
    [[CREATE TABLE IF NOT EXISTS `nz_cargo_ledger` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `identifier` VARCHAR(64) NOT NULL,
        `warehouse` INT DEFAULT NULL,
        `kind` VARCHAR(16) NOT NULL,
        `label` VARCHAR(64) DEFAULT NULL,
        `rarity` VARCHAR(16) DEFAULT NULL,
        `amount` INT NOT NULL DEFAULT 0,
        `data` LONGTEXT DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX `ident_idx` (`identifier`),
        INDEX `wh_idx` (`warehouse`)
    )]],
    [[CREATE TABLE IF NOT EXISTS `nz_cargo_settings` (
        `k` VARCHAR(32) NOT NULL PRIMARY KEY,
        `v` LONGTEXT DEFAULT NULL
    )]],
}

-- caches
DB.Locations  = {}   -- [id] = location
DB.Warehouses = {}   -- [id] = warehouse
DB.ByOwner    = {}   -- [identifier] = { id, ... }
DB.Settings   = {}
DB.Custom     = {}   -- [model] = row
DB.Ready      = false

local function v4(t) return { x = t.x, y = t.y, z = t.z, w = t.w or 0.0 } end
DB.V4 = v4

local function decode(s, fallback)
    if not s or s == '' then return fallback end
    local ok, v = pcall(json.decode, s)
    if ok and v ~= nil then return v end
    return fallback
end
DB.Decode = decode

local function defaultUpgrades()
    return { capacity = 0, workshop = 0, intel = 0, contacts = 0, repair = 0, lower = 0, tracker = 0, style = 'basic' }
end

local function hydrateWarehouse(row)
    local up = decode(row.upgrades, {})
    local def = defaultUpgrades()
    for k, v in pairs(def) do if up[k] == nil then up[k] = v end end
    return {
        id = row.id, owner = row.owner, owner_name = row.owner_name,
        location = row.location, upgrades = up,
        associates = decode(row.associates, {}), paid = row.paid,
        layout = decode(row.layout), preset = (row.preset ~= '' and row.preset) or nil, trackerSpot = decode(row.tracker_spot), prefs = decode(row.prefs, {}), heat = row.heat or 0, heat_at = row.heat_at or 0, claims = row.claims or 0,
    }
end

-- Adds a column to an existing table (older installs) without touching data.
local function ensureColumn(tbl, col, def)
    local found = MySQL.query.await(('SHOW COLUMNS FROM `%s` LIKE \'%s\''):format(tbl, col))
    if not found or #found == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tbl, col, def))
    end
end

function DB.Init()
    for _, q in ipairs(schema) do MySQL.query.await(q) end
    ensureColumn('nz_cargo_stock', 'floor', "VARCHAR(8) NOT NULL DEFAULT 'main'")
    ensureColumn('nz_cargo_warehouses', 'layout', 'LONGTEXT DEFAULT NULL')
    ensureColumn('nz_cargo_warehouses', 'preset', 'VARCHAR(32) DEFAULT NULL')
    ensureColumn('nz_cargo_warehouses', 'tracker_spot', 'LONGTEXT DEFAULT NULL')
    ensureColumn('nz_cargo_warehouses', 'prefs', 'LONGTEXT DEFAULT NULL')
    ensureColumn('nz_cargo_warehouses', 'heat', 'INT NOT NULL DEFAULT 0')
    ensureColumn('nz_cargo_warehouses', 'heat_at', 'INT NOT NULL DEFAULT 0')
    ensureColumn('nz_cargo_warehouses', 'claims', 'INT NOT NULL DEFAULT 0')
    ensureColumn('nz_cargo_stock', 'insured', 'TINYINT NOT NULL DEFAULT 0')
    ensureColumn('nz_cargo_stock', 'hot', 'TINYINT NOT NULL DEFAULT 0')
    ensureColumn('nz_cargo_profiles', 'prestige', 'INT NOT NULL DEFAULT 0')
    ensureColumn('nz_cargo_profiles', 'contract_cd', 'LONGTEXT DEFAULT NULL')
    ensureColumn('nz_cargo_profiles', 'last_inside', 'INT NOT NULL DEFAULT 0')

    ensureColumn('nz_cargo_locations', 'garage_exit', 'VARCHAR(160) DEFAULT NULL')

    -- seed locations on first start
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM nz_cargo_locations')
    if (count or 0) == 0 then DB.ImportSeeds() end

    for _, r in ipairs(MySQL.query.await('SELECT * FROM nz_cargo_locations') or {}) do
        DB.Locations[r.id] = {
            id = r.id, name = r.name, price = r.price, enabled = r.enabled == 1,
            door = decode(r.door), garage = decode(r.garage), spawn = decode(r.spawn), garageExit = decode(r.garage_exit),
        }
    end

    for _, r in ipairs(MySQL.query.await('SELECT * FROM nz_cargo_warehouses') or {}) do
        local w = hydrateWarehouse(r)
        DB.Warehouses[w.id] = w
        DB.ByOwner[w.owner] = DB.ByOwner[w.owner] or {}
        table.insert(DB.ByOwner[w.owner], w.id)
    end

    for _, r in ipairs(MySQL.query.await('SELECT * FROM nz_cargo_settings') or {}) do
        DB.Settings[r.k] = decode(r.v)
    end

    if not DB.Settings.brokers then
        local list = {}
        for _, b in ipairs(Config.SeedBrokers) do list[#list + 1] = v4(b) end
        DB.SetSetting('brokers', list)
    end

    for _, r in ipairs(MySQL.query.await('SELECT * FROM nz_cargo_custom_vehicles') or {}) do
        DB.Custom[r.model] = { model = r.model, label = r.label, rarity = r.rarity, value = r.value, enabled = r.enabled == 1, custom = true }
    end

    -- anything mid-sale when the server stopped goes back on the floor
    MySQL.update.await("UPDATE nz_cargo_stock SET status = 'stored' WHERE status <> 'stored'")

    DB.Ready = true
end

-----------------------------------------------------------------
-- Warehouses
-----------------------------------------------------------------
-- Seed warehouses from config/locations.lua (new keys, old keys still work).
-- Same name = coords and price updated, new name = added. Returns how many.
function DB.ImportSeeds()
    local n = 0
    for _, s in ipairs(Config.SeedWarehouses) do
        local door, gin = s.frontDoor or s.door, s.garageIn or s.garage
        local gout, sale = s.garageOut or s.garageExit, s.saleSpawn or s.spawn
        if s.name and door and gin and sale then
            local d, g, sp = json.encode(v4(door)), json.encode(v4(gin)), json.encode(v4(sale))
            local go = gout and json.encode(v4(gout)) or ''
            local id = MySQL.scalar.await('SELECT id FROM nz_cargo_locations WHERE name = ? LIMIT 1', { s.name })
            if id then
                MySQL.update.await('UPDATE nz_cargo_locations SET price = ?, door = ?, garage = ?, spawn = ?, garage_exit = ? WHERE id = ?', { s.price or 0, d, g, sp, go, id })
                local l = DB.Locations[id]
                if l then l.price, l.door, l.garage, l.spawn, l.garageExit = s.price or 0, v4(door), v4(gin), v4(sale), gout and v4(gout) or nil end
            else
                id = MySQL.insert.await('INSERT INTO nz_cargo_locations (name, price, door, garage, spawn, garage_exit) VALUES (?, ?, ?, ?, ?, ?)', { s.name, s.price or 0, d, g, sp, go })
                if id and next(DB.Locations) then
                    DB.Locations[id] = { id = id, name = s.name, price = s.price or 0, enabled = true, door = v4(door), garage = v4(gin), spawn = v4(sale), garageExit = gout and v4(gout) or nil }
                end
            end
            n = n + 1
        end
    end
    return n
end

function DB.CreateWarehouse(owner, ownerName, location, paid)
    local up = defaultUpgrades()
    local id = MySQL.insert.await('INSERT INTO nz_cargo_warehouses (owner, owner_name, location, upgrades, associates, paid) VALUES (?, ?, ?, ?, ?, ?)', {
        owner, ownerName or '', location, json.encode(up), '[]', paid,
    })
    local w = { id = id, owner = owner, owner_name = ownerName, location = location, upgrades = up, associates = {}, paid = paid, prefs = {}, heat = 0, heat_at = 0, claims = 0 }
    DB.Warehouses[id] = w
    DB.ByOwner[owner] = DB.ByOwner[owner] or {}
    table.insert(DB.ByOwner[owner], id)
    return w
end

function DB.SaveWarehouse(w)
    MySQL.update('UPDATE nz_cargo_warehouses SET upgrades = ?, associates = ?, owner_name = ?, layout = ?, preset = ?, tracker_spot = ?, prefs = ?, heat = ?, heat_at = ?, claims = ? WHERE id = ?', {
        json.encode(w.upgrades), json.encode(w.associates), w.owner_name or '',
        w.layout and json.encode(w.layout) or '', w.preset or '', w.trackerSpot and json.encode(w.trackerSpot) or '',
        json.encode(w.prefs or {}), math.floor(w.heat or 0), math.floor(w.heat_at or 0), math.floor(w.claims or 0), w.id,
    })
end

-- Move a warehouse (and everything in it) to another building
function DB.MoveWarehouse(w, location, paid)
    w.location, w.paid = location, paid
    MySQL.update.await('UPDATE nz_cargo_warehouses SET location = ?, paid = ? WHERE id = ?', { location, paid, w.id })
end

function DB.DeleteWarehouse(id)
    local w = DB.Warehouses[id]
    if not w then return end
    MySQL.query.await('DELETE FROM nz_cargo_stock WHERE warehouse = ?', { id })
    MySQL.query.await('DELETE FROM nz_cargo_warehouses WHERE id = ?', { id })
    local list = DB.ByOwner[w.owner] or {}
    for i = #list, 1, -1 do if list[i] == id then table.remove(list, i) end end
    DB.Warehouses[id] = nil
end

-----------------------------------------------------------------
-- Stock
-----------------------------------------------------------------
local function hydrateStock(r)
    return {
        id = r.id, warehouse = r.warehouse, model = r.model, label = r.label,
        base_rarity = r.base_rarity, rarity = r.rarity, value = r.value, condition = r.cond,
        build = decode(r.build, {}), score = r.score, props = decode(r.props, {}), plate = r.plate,
        status = r.status, offers = decode(r.offers), offers_at = r.offers_at, sourced_by = r.sourced_by,
        floor = r.floor or 'main', insured = (r.insured or 0) == 1, hot = (r.hot or 0) == 1,
    }
end

function DB.GetStock(warehouse)
    local rows = MySQL.query.await('SELECT * FROM nz_cargo_stock WHERE warehouse = ? ORDER BY id ASC', { warehouse }) or {}
    local out = {}
    for i, r in ipairs(rows) do out[i] = hydrateStock(r) end
    return out
end

function DB.GetStockItem(id)
    local r = MySQL.single.await('SELECT * FROM nz_cargo_stock WHERE id = ?', { id })
    return r and hydrateStock(r)
end

function DB.CountStock(warehouse, floor)
    return MySQL.scalar.await('SELECT COUNT(*) FROM nz_cargo_stock WHERE warehouse = ? AND floor = ?', { warehouse, floor or 'main' }) or 0
end

function DB.AddStock(s)
    return MySQL.insert.await([[INSERT INTO nz_cargo_stock
        (warehouse, model, label, base_rarity, rarity, value, cond, build, score, props, plate, sourced_by, floor, hot)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        s.warehouse, s.model, s.label, s.base_rarity, s.rarity, s.value, s.condition,
        json.encode(s.build or {}), s.score or 0, json.encode(s.props or {}), s.plate or '', s.sourced_by or '', s.floor or 'main', s.hot and 1 or 0,
    })
end

function DB.UpdateStock(s)
    MySQL.update.await([[UPDATE nz_cargo_stock SET rarity = ?, cond = ?, build = ?, score = ?, props = ?,
        status = ?, offers = ?, offers_at = ? WHERE id = ?]], {
        s.rarity, s.condition, json.encode(s.build or {}), s.score or 0, json.encode(s.props or {}),
        s.status or 'stored', s.offers and json.encode(s.offers) or '', s.offers_at or 0, s.id,
    })
end

function DB.SetStockInsured(id, on)
    MySQL.update.await('UPDATE nz_cargo_stock SET insured = ? WHERE id = ?', { on and 1 or 0, id })
end

function DB.SetStockStatus(id, status)
    MySQL.update.await('UPDATE nz_cargo_stock SET status = ? WHERE id = ?', { status, id })
end

function DB.DeleteStock(id)
    MySQL.query.await('DELETE FROM nz_cargo_stock WHERE id = ?', { id })
end

-----------------------------------------------------------------
-- Profiles
-----------------------------------------------------------------
local profiles = {}

function DB.GetProfile(identifier, name)
    if profiles[identifier] then return profiles[identifier] end
    local r = MySQL.single.await('SELECT * FROM nz_cargo_profiles WHERE identifier = ?', { identifier })
    if not r then
        MySQL.insert.await('INSERT IGNORE INTO nz_cargo_profiles (identifier, name) VALUES (?, ?)', { identifier, name or '' })
        r = { identifier = identifier, name = name, xp = 0, sourced = 0, sold = 0, failed = 0, earned = 0,
              best_sale = 0, clean_streak = 0, source_cd = 0, sell_cd = 0, prestige = 0, last_inside = 0 }
    end
    r.prestige = r.prestige or 0
    r.contract_cd = type(r.contract_cd) == 'table' and r.contract_cd or decode(r.contract_cd, {})
    profiles[identifier] = r
    return r
end

function DB.SaveProfile(p)
    MySQL.update([[UPDATE nz_cargo_profiles SET name = ?, xp = ?, sourced = ?, sold = ?, failed = ?, earned = ?,
        best_sale = ?, clean_streak = ?, source_cd = ?, sell_cd = ?, prestige = ?, contract_cd = ? WHERE identifier = ?]], {
        p.name or '', p.xp, p.sourced, p.sold, p.failed, p.earned, p.best_sale, p.clean_streak, p.source_cd, p.sell_cd, p.prestige or 0,
        json.encode(p.contract_cd or {}), p.identifier,
    })
end

function DB.DropProfile(identifier) profiles[identifier] = nil end

-- Which warehouse this character is inside (0 = none). Survives restarts and relogs.
function DB.SetLastInside(p, wid)
    wid = wid or 0
    if (p.last_inside or 0) == wid then return end
    p.last_inside = wid
    MySQL.update('UPDATE nz_cargo_profiles SET last_inside = ? WHERE identifier = ?', { wid, p.identifier })
end

-----------------------------------------------------------------
-- Ledger
-----------------------------------------------------------------
function DB.Log(identifier, warehouse, kind, label, rarity, amount, data)
    MySQL.insert('INSERT INTO nz_cargo_ledger (identifier, warehouse, kind, label, rarity, amount, data) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        identifier, warehouse or 0, kind, label or '', rarity or '', math.floor(amount or 0), data and json.encode(data) or '',
    })
end

function DB.GetLedger(warehouse, limit)
    return MySQL.query.await([[SELECT id, kind, label, rarity, amount, data, UNIX_TIMESTAMP(created_at) AS t
        FROM nz_cargo_ledger WHERE warehouse = ? ORDER BY id DESC LIMIT ?]], { warehouse, limit or 40 }) or {}
end

-----------------------------------------------------------------
-- Settings
-----------------------------------------------------------------
function DB.SetSetting(k, v)
    DB.Settings[k] = v
    MySQL.query.await('INSERT INTO nz_cargo_settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { k, json.encode(v) })
end
