-- nayzeee-trading — tables are also created automatically on resource start

CREATE TABLE IF NOT EXISTS `nz_trading_profiles` (
        `owner` VARCHAR(64) NOT NULL PRIMARY KEY,
        `name` VARCHAR(32) NOT NULL,
        `settings` LONGTEXT NULL,
        `watchlist` LONGTEXT NULL,
        `active` VARCHAR(10) NOT NULL DEFAULT 'practice',
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_trading_accounts` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `owner` VARCHAR(64) NOT NULL,
        `type` VARCHAR(10) NOT NULL,
        `cash` DECIMAL(18,4) NOT NULL DEFAULT 0,
        `realized` DECIMAL(18,4) NOT NULL DEFAULT 0,
        `fees` DECIMAL(18,4) NOT NULL DEFAULT 0,
        `trades` INT NOT NULL DEFAULT 0,
        `day_start` DECIMAL(18,4) NOT NULL DEFAULT 0,
        `day_key` VARCHAR(10) NULL,
        `reset_at` INT NOT NULL DEFAULT 0,
        UNIQUE KEY `owner_type` (`owner`, `type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_trading_positions` (
        `account_id` INT NOT NULL,
        `symbol` VARCHAR(10) NOT NULL,
        `qty` DECIMAL(20,6) NOT NULL,
        `avg_price` DECIMAL(18,6) NOT NULL,
        PRIMARY KEY (`account_id`, `symbol`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_trading_orders` (
        `id` INT NOT NULL PRIMARY KEY,
        `account_id` INT NOT NULL,
        `symbol` VARCHAR(10) NOT NULL,
        `side` VARCHAR(4) NOT NULL,
        `type` VARCHAR(8) NOT NULL,
        `qty` DECIMAL(20,6) NOT NULL,
        `limit_price` DECIMAL(18,6) NULL,
        `stop_price` DECIMAL(18,6) NULL,
        `trail` DECIMAL(18,6) NULL,
        `tif` VARCHAR(4) NOT NULL DEFAULT 'gtc',
        `tp` DECIMAL(18,6) NULL,
        `sl` DECIMAL(18,6) NULL,
        `oco` INT NULL,
        `reduce` TINYINT(1) NOT NULL DEFAULT 0,
        `status` VARCHAR(10) NOT NULL,
        `fill_price` DECIMAL(18,6) NULL,
        `reason` VARCHAR(64) NULL,
        `created` INT NOT NULL,
        `updated` INT NOT NULL,
        INDEX `acc_status` (`account_id`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_trading_fills` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `account_id` INT NOT NULL,
        `order_id` INT NOT NULL,
        `symbol` VARCHAR(10) NOT NULL,
        `side` VARCHAR(4) NOT NULL,
        `qty` DECIMAL(20,6) NOT NULL,
        `price` DECIMAL(18,6) NOT NULL,
        `fee` DECIMAL(18,4) NOT NULL,
        `realized` DECIMAL(18,4) NOT NULL,
        `time` INT NOT NULL,
        INDEX `acc` (`account_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_trading_ledger` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `account_id` INT NOT NULL,
        `type` VARCHAR(12) NOT NULL,
        `amount` DECIMAL(18,4) NOT NULL,
        `time` INT NOT NULL,
        INDEX `acc` (`account_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_trading_alerts` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `owner` VARCHAR(64) NOT NULL,
        `symbol` VARCHAR(10) NOT NULL,
        `cond` VARCHAR(5) NOT NULL,
        `price` DECIMAL(18,6) NOT NULL,
        INDEX `owner` (`owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_trading_market` (
        `symbol` VARCHAR(10) NOT NULL PRIMARY KEY,
        `price` DECIMAL(18,6) NOT NULL,
        `prev_close` DECIMAL(18,6) NOT NULL,
        `anchor` DECIMAL(18,6) NOT NULL,
        `day_key` VARCHAR(10) NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_trading_props` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `owner` VARCHAR(64) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `heading` FLOAT NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
