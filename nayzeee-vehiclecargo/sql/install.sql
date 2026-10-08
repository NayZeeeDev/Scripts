-- nayzeee-vehiclecargo
-- Optional: the resource creates these tables by itself on first start,
-- and adds any missing columns when you update from an older version.

CREATE TABLE IF NOT EXISTS `nz_cargo_profiles` (
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
        `prestige` INT NOT NULL DEFAULT 0,
        `contract_cd` LONGTEXT DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE IF NOT EXISTS `nz_cargo_locations` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `name` VARCHAR(64) NOT NULL,
        `price` INT NOT NULL DEFAULT 0,
        `door` VARCHAR(160) NOT NULL,
        `garage` VARCHAR(160) NOT NULL,
        `spawn` VARCHAR(160) NOT NULL,
        `garage_exit` VARCHAR(160) DEFAULT NULL,
        `enabled` TINYINT NOT NULL DEFAULT 1
    );

CREATE TABLE IF NOT EXISTS `nz_cargo_warehouses` (
        `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        `owner` VARCHAR(64) NOT NULL,
        `owner_name` VARCHAR(64) DEFAULT NULL,
        `location` INT NOT NULL,
        `upgrades` LONGTEXT DEFAULT NULL,
        `associates` LONGTEXT DEFAULT NULL,
        `paid` INT NOT NULL DEFAULT 0,
        `layout` LONGTEXT DEFAULT NULL,
        `preset` VARCHAR(32) DEFAULT NULL,
        `tracker_spot` LONGTEXT DEFAULT NULL,
        `prefs` LONGTEXT DEFAULT NULL,
        `heat` INT NOT NULL DEFAULT 0,
        `heat_at` INT NOT NULL DEFAULT 0,
        `claims` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX `owner_idx` (`owner`)
    );

CREATE TABLE IF NOT EXISTS `nz_cargo_stock` (
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
        `floor` VARCHAR(8) NOT NULL DEFAULT 'main',
        `insured` TINYINT NOT NULL DEFAULT 0,
        `hot` TINYINT NOT NULL DEFAULT 0,
        `offers` LONGTEXT DEFAULT NULL,
        `offers_at` INT NOT NULL DEFAULT 0,
        `sourced_by` VARCHAR(64) DEFAULT NULL,
        `sourced_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX `wh_idx` (`warehouse`)
    );

CREATE TABLE IF NOT EXISTS `nz_cargo_custom_vehicles` (
        `model` VARCHAR(64) NOT NULL PRIMARY KEY,
        `label` VARCHAR(64) NOT NULL,
        `rarity` VARCHAR(16) NOT NULL,
        `value` INT NOT NULL DEFAULT 0,
        `enabled` TINYINT NOT NULL DEFAULT 1
    );

CREATE TABLE IF NOT EXISTS `nz_cargo_ledger` (
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
    );

CREATE TABLE IF NOT EXISTS `nz_cargo_settings` (
        `k` VARCHAR(32) NOT NULL PRIMARY KEY,
        `v` LONGTEXT DEFAULT NULL
    );
