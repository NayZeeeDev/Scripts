-- Created automatically on start. Only needed if your database user can't create tables.
CREATE TABLE IF NOT EXISTS `nayzeee_drugempire` (
    `identifier` VARCHAR(64) NOT NULL,
    `data` LONGTEXT NOT NULL,
    `updated` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nayzeee_drugempire_products` (
    `id` VARCHAR(16) NOT NULL,
    `mixkey` VARCHAR(255) NOT NULL,
    `base` VARCHAR(32) NOT NULL,
    `name` VARCHAR(64) NOT NULL,
    `effects` TEXT NOT NULL,
    `creator` VARCHAR(64) NULL,
    `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `mixkey` (`mixkey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
