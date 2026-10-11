-- The resource creates and upgrades these tables on start. This file is only for manual installs.

CREATE TABLE IF NOT EXISTS `nayzeee_inventory_logs` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `type` VARCHAR(32) NOT NULL,
    `source_name` VARCHAR(128) DEFAULT NULL,
    `source_identifier` VARCHAR(128) DEFAULT NULL,
    `source_id` INT(11) DEFAULT NULL,
    `target_name` VARCHAR(128) DEFAULT NULL,
    `target_identifier` VARCHAR(128) DEFAULT NULL,
    `target_id` INT(11) DEFAULT NULL,
    `item_name` VARCHAR(128) NOT NULL,
    `item_label` VARCHAR(128) DEFAULT NULL,
    `item_count` INT(11) NOT NULL DEFAULT 1,
    `metadata` LONGTEXT DEFAULT NULL,
    `inventory_from` VARCHAR(128) DEFAULT NULL,
    `inventory_to` VARCHAR(128) DEFAULT NULL,
    `coords` VARCHAR(128) DEFAULT NULL,
    `details` TEXT DEFAULT NULL,
    `resource` VARCHAR(64) DEFAULT NULL,
    `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_type` (`type`),
    INDEX `idx_source_identifier` (`source_identifier`),
    INDEX `idx_target_identifier` (`target_identifier`),
    INDEX `idx_item_name` (`item_name`),
    INDEX `idx_timestamp` (`timestamp`),
    INDEX `idx_type_time` (`type`, `timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nayzeee_inventory_audit` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `admin_name` VARCHAR(128) DEFAULT NULL,
    `admin_identifier` VARCHAR(128) DEFAULT NULL,
    `action` VARCHAR(64) NOT NULL,
    `target` VARCHAR(128) DEFAULT NULL,
    `details` LONGTEXT DEFAULT NULL,
    `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_action` (`action`),
    INDEX `idx_timestamp` (`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nayzeee_inventory_snapshots` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `kind` VARCHAR(16) NOT NULL,
    `players` INT(11) NOT NULL DEFAULT 0,
    `data` LONGTEXT NOT NULL,
    `taken_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_kind_time` (`kind`, `taken_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nayzeee_inventory_supply` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `item` VARCHAR(128) NOT NULL,
    `total` BIGINT NOT NULL DEFAULT 0,
    `taken_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_item_time` (`item`, `taken_at`),
    INDEX `idx_time` (`taken_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
