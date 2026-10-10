-- THE WASH — tables are also created automatically on first start.

CREATE TABLE IF NOT EXISTS `nzmw_batches` (
    `id` VARCHAR(24) NOT NULL,
    `owner` VARCHAR(64) NOT NULL,
    `data` LONGTEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `nzmw_stations` (
    `id` VARCHAR(48) NOT NULL,
    `data` LONGTEXT NOT NULL,
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `nzmw_equipment` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `type` VARCHAR(16) NOT NULL,
    `owner` VARCHAR(64) NOT NULL,
    `owner_name` VARCHAR(64) NOT NULL DEFAULT '',
    `share` VARCHAR(64) NULL,
    `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `owner` (`owner`)
);

CREATE TABLE IF NOT EXISTS `nzmw_ledger` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `front` VARCHAR(32) NOT NULL,
    `citizenid` VARCHAR(64) NOT NULL,
    `name` VARCHAR(64) NOT NULL,
    `amount` INT NOT NULL,
    `payout` INT NOT NULL,
    `allocation` TEXT NOT NULL,
    `suspicion` FLOAT NOT NULL,
    `flagged` TINYINT(1) NOT NULL DEFAULT 0,
    `serials` TEXT NOT NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `front_time` (`front`, `created_at`)
);

CREATE TABLE IF NOT EXISTS `nzmw_clearing` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(64) NOT NULL,
    `front` VARCHAR(32) NOT NULL,
    `amount` INT NOT NULL,
    `seized` INT NOT NULL DEFAULT 0,
    `release_at` INT NOT NULL,
    `status` VARCHAR(12) NOT NULL DEFAULT 'pending',
    PRIMARY KEY (`id`),
    KEY `status_release` (`status`, `release_at`)
);
