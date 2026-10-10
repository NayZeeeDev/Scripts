DB = {}

local schema = {
    [[CREATE TABLE IF NOT EXISTS `nzmw_batches` (
        `id` VARCHAR(24) NOT NULL, `owner` VARCHAR(64) NOT NULL, `data` LONGTEXT NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`))]],
    [[CREATE TABLE IF NOT EXISTS `nzmw_stations` (
        `id` VARCHAR(48) NOT NULL, `data` LONGTEXT NOT NULL, PRIMARY KEY (`id`))]],
    [[CREATE TABLE IF NOT EXISTS `nzmw_equipment` (
        `id` INT NOT NULL AUTO_INCREMENT, `type` VARCHAR(16) NOT NULL, `owner` VARCHAR(64) NOT NULL,
        `owner_name` VARCHAR(64) NOT NULL DEFAULT '', `share` VARCHAR(64) NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`), KEY `owner` (`owner`))]],
    [[CREATE TABLE IF NOT EXISTS `nzmw_ledger` (
        `id` INT NOT NULL AUTO_INCREMENT, `front` VARCHAR(32) NOT NULL, `citizenid` VARCHAR(64) NOT NULL,
        `name` VARCHAR(64) NOT NULL, `amount` INT NOT NULL, `payout` INT NOT NULL, `allocation` TEXT NOT NULL,
        `suspicion` FLOAT NOT NULL, `flagged` TINYINT(1) NOT NULL DEFAULT 0, `serials` TEXT NOT NULL,
        `created_at` INT NOT NULL, PRIMARY KEY (`id`), KEY `front_time` (`front`, `created_at`))]],
    [[CREATE TABLE IF NOT EXISTS `nzmw_clearing` (
        `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(64) NOT NULL, `front` VARCHAR(32) NOT NULL,
        `amount` INT NOT NULL, `seized` INT NOT NULL DEFAULT 0, `release_at` INT NOT NULL,
        `status` VARCHAR(12) NOT NULL DEFAULT 'pending', PRIMARY KEY (`id`), KEY `status_release` (`status`, `release_at`))]],
}

schema[#schema + 1] = [[CREATE TABLE IF NOT EXISTS `nzmw_facilities` (
        `id` INT NOT NULL AUTO_INCREMENT, `owner` VARCHAR(64) NOT NULL, `owner_name` VARCHAR(64) NOT NULL DEFAULT '',
        `members` LONGTEXT NOT NULL, `upgrades` LONGTEXT NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`), KEY `owner` (`owner`))]]

function DB.init()
    for _, q in ipairs(schema) do MySQL.query.await(q) end
    -- v1.1: machines can belong to a wash unit
    local has = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'nzmw_equipment' AND COLUMN_NAME = 'facility']])
    if tonumber(has) == 0 then
        MySQL.query.await('ALTER TABLE `nzmw_equipment` ADD COLUMN `facility` INT NULL')
    end
end

function DB.saveBatch(b)
    MySQL.prepare('INSERT INTO nzmw_batches (id, owner, data) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { b.id, b.owner, json.encode(b) })
end

function DB.deleteBatch(id)
    MySQL.prepare('DELETE FROM nzmw_batches WHERE id = ?', { id })
end

function DB.loadBatches()
    local rows = MySQL.query.await('SELECT data FROM nzmw_batches') or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ok, b = pcall(json.decode, r.data)
        if ok and b and b.id then out[b.id] = b end
    end
    return out
end

function DB.saveStation(id, data)
    MySQL.prepare('INSERT INTO nzmw_stations (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { id, json.encode(data) })
end

function DB.deleteStation(id)
    MySQL.prepare('DELETE FROM nzmw_stations WHERE id = ?', { id })
end

function DB.loadStationMeta()
    local rows = MySQL.query.await('SELECT id, data FROM nzmw_stations') or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ok, d = pcall(json.decode, r.data)
        if ok and d then out[r.id] = d end
    end
    return out
end
