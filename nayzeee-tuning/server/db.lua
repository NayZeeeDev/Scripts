DB = {}

local schema = {
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_vehicles` (
        `plate` VARCHAR(12) NOT NULL,
        `model` VARCHAR(64) NULL,
        `data` LONGTEXT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`plate`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_shops` (
        `id` VARCHAR(64) NOT NULL,
        `balance` INT NOT NULL DEFAULT 0,
        `margin` INT NOT NULL DEFAULT 0,
        `commission` INT NULL,
        `upgrades` LONGTEXT NULL,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_history` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `plate` VARCHAR(12) NOT NULL,
        `shop` VARCHAR(64) NOT NULL,
        `kind` VARCHAR(16) NOT NULL DEFAULT 'self',
        `customer` VARCHAR(64) NULL,
        `customer_name` VARCHAR(100) NULL,
        `mechanic` VARCHAR(64) NULL,
        `mechanic_name` VARCHAR(100) NULL,
        `items` LONGTEXT NULL,
        `total` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `plate` (`plate`), KEY `shop` (`shop`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_orders` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `shop` VARCHAR(64) NOT NULL,
        `plate` VARCHAR(12) NOT NULL,
        `model` VARCHAR(64) NULL,
        `label` VARCHAR(100) NULL,
        `customer` VARCHAR(64) NOT NULL,
        `customer_name` VARCHAR(100) NULL,
        `items` LONGTEXT NOT NULL,
        `props` LONGTEXT NULL,
        `extras` LONGTEXT NULL,
        `totals` LONGTEXT NULL,
        `total` INT NOT NULL DEFAULT 0,
        `paid_with` VARCHAR(16) NULL,
        `status` VARCHAR(16) NOT NULL DEFAULT 'open',
        `mechanic` VARCHAR(64) NULL,
        `mechanic_name` VARCHAR(100) NULL,
        `progress` LONGTEXT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `shop_status` (`shop`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_codes` (
        `code` VARCHAR(32) NOT NULL,
        `shop` VARCHAR(64) NOT NULL,
        `percent` INT NOT NULL,
        `uses` INT NOT NULL,
        `created_by` VARCHAR(100) NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`code`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_tx` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `shop` VARCHAR(64) NOT NULL,
        `kind` VARCHAR(24) NOT NULL,
        `amount` INT NOT NULL,
        `actor` VARCHAR(100) NULL,
        `note` VARCHAR(255) NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `shop` (`shop`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_announcements` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `shop` VARCHAR(64) NOT NULL,
        `author` VARCHAR(100) NULL,
        `message` VARCHAR(512) NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `shop` (`shop`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_stats` (
        `shop` VARCHAR(64) NOT NULL,
        `day` DATE NOT NULL,
        `revenue` INT NOT NULL DEFAULT 0,
        `jobs` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`shop`, `day`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_mechanics` (
        `identifier` VARCHAR(64) NOT NULL,
        `shop` VARCHAR(64) NOT NULL,
        `name` VARCHAR(100) NULL,
        `installs` INT NOT NULL DEFAULT 0,
        `earned` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`identifier`, `shop`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_builds` (
        `code` VARCHAR(16) NOT NULL,
        `owner` VARCHAR(64) NOT NULL,
        `owner_name` VARCHAR(100) NULL,
        `name` VARCHAR(48) NOT NULL,
        `model` VARCHAR(64) NULL,
        `items` LONGTEXT NOT NULL,
        `uses` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`code`), KEY `owner` (`owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_perf` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(64) NOT NULL,
        `name` VARCHAR(100) NULL,
        `model` VARCHAR(64) NOT NULL,
        `label` VARCHAR(64) NULL,
        `plate` VARCHAR(12) NULL,
        `test` VARCHAR(16) NOT NULL,
        `time` FLOAT NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `test_model` (`test`, `model`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_tablet` (
        `identifier` VARCHAR(64) NOT NULL,
        `accent` VARCHAR(16) NULL,
        `wallpaper` VARCHAR(255) NULL,
        `data` LONGTEXT NULL,
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_shop_edits` (
        `id` VARCHAR(64) NOT NULL,
        `data` LONGTEXT NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_supply` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `shop` VARCHAR(64) NOT NULL,
        `identifier` VARCHAR(64) NOT NULL,
        `name` VARCHAR(100) NULL,
        `items` LONGTEXT NOT NULL,
        `total` INT NOT NULL DEFAULT 0,
        `status` VARCHAR(16) NOT NULL DEFAULT 'active',
        `kind` VARCHAR(16) NOT NULL DEFAULT 'run',
        `eta` INT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `shop` (`shop`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_stock` (
        `shop` VARCHAR(64) NOT NULL,
        `item` VARCHAR(64) NOT NULL,
        `qty` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`shop`, `item`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nz_tuning_messages` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `order_id` INT NOT NULL,
        `sender` VARCHAR(64) NOT NULL,
        `sender_name` VARCHAR(100) NULL,
        `side` VARCHAR(12) NOT NULL DEFAULT 'customer',
        `body` VARCHAR(500) NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `order_id` (`order_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- columns added by updates (safe to keep: only added when missing)
local columns = {
    { 'nz_tuning_shops', 'labour', 'INT NULL' },
    { 'nz_tuning_tablet', 'avatar', 'VARCHAR(255) NULL' },
    { 'nz_tuning_tablet', 'avatar_at', 'INT NULL' },
    { 'nz_tuning_supply', 'kind', "VARCHAR(16) NOT NULL DEFAULT 'run'" },
    { 'nz_tuning_supply', 'eta', 'INT NULL' },
}

function DB.Init()
    for _, q in ipairs(schema) do MySQL.query.await(q) end
    for _, c in ipairs(columns) do
        local exists = MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?', { c[1], c[2] })
        if (tonumber(exists) or 0) == 0 then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(c[1], c[2], c[3])) end
    end
    DB.Ready = true
    NZ.Debug('database ready')
end

function DB.Decode(s, fallback)
    if type(s) ~= 'string' or s == '' then return fallback end
    local ok, v = pcall(json.decode, s)
    return ok and v or fallback
end
