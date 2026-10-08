-- Optional: the resource creates these tables automatically on first start.
CREATE TABLE IF NOT EXISTS `nzh_profiles` (
    `identifier` VARCHAR(64) NOT NULL,
    `nickname` VARCHAR(24) DEFAULT NULL,
    `avatar` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `xp` INT UNSIGNED NOT NULL DEFAULT 0,
    `completed` INT UNSIGNED NOT NULL DEFAULT 0,
    `failed` INT UNSIGNED NOT NULL DEFAULT 0,
    `earned` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `stats` LONGTEXT DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`),
    KEY `xp_idx` (`xp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nzh_history` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `heist` VARCHAR(32) NOT NULL,
    `location` VARCHAR(64) DEFAULT NULL,
    `crew` LONGTEXT NOT NULL,
    `success` TINYINT(1) NOT NULL DEFAULT 0,
    `payout` INT UNSIGNED NOT NULL DEFAULT 0,
    `duration` INT UNSIGNED NOT NULL DEFAULT 0,
    `reason` VARCHAR(64) DEFAULT NULL,
    `finished_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `finished_idx` (`finished_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
