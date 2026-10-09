-- Wig Snatch V3 tables. The resource creates (and upgrades) these on its own; this file is only for manual installs.

CREATE TABLE IF NOT EXISTS `nz_wig_players` (
        `identifier` VARCHAR(64) NOT NULL,
        `name` VARCHAR(64) NOT NULL DEFAULT '',
        `xp` INT NOT NULL DEFAULT 0,
        `snatches` INT NOT NULL DEFAULT 0,
        `defends` INT NOT NULL DEFAULT 0,
        `fails` INT NOT NULL DEFAULT 0,
        `snatched` INT NOT NULL DEFAULT 0,
        `streak` INT NOT NULL DEFAULT 0,
        `best_streak` INT NOT NULL DEFAULT 0,
        `buzzes` INT NOT NULL DEFAULT 0,
        `cuts` INT NOT NULL DEFAULT 0,
        `revenges` INT NOT NULL DEFAULT 0,
        `wigs_sold` INT NOT NULL DEFAULT 0,
        `earned` INT NOT NULL DEFAULT 0,
        `bounties_claimed` INT NOT NULL DEFAULT 0,
        `bounty_earned` INT NOT NULL DEFAULT 0,
        `best_tier` VARCHAR(16) NULL,
        `catalog_rewards` INT NOT NULL DEFAULT 0,
        `hair` LONGTEXT NULL,
        `glue_until` INT NOT NULL DEFAULT 0,
        `passive` TINYINT(1) NOT NULL DEFAULT 0,
        `passive_at` INT NOT NULL DEFAULT 0,
        `first_seen` INT NOT NULL DEFAULT 0,
        `last_seen` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`identifier`),
        KEY `idx_xp` (`xp`),
        KEY `idx_snatches` (`snatches`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_wig_feed` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `kind` VARCHAR(16) NOT NULL,
        `actor` VARCHAR(64) NULL,
        `actor_name` VARCHAR(64) NULL,
        `target` VARCHAR(64) NULL,
        `target_name` VARCHAR(64) NULL,
        `tier` VARCHAR(16) NULL,
        `label` VARCHAR(96) NULL,
        `amount` INT NOT NULL DEFAULT 0,
        `created` INT NOT NULL,
        PRIMARY KEY (`id`),
        KEY `idx_target` (`target`, `created`),
        KEY `idx_created` (`created`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_wig_bounties` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `target` VARCHAR(64) NOT NULL,
        `target_name` VARCHAR(64) NOT NULL,
        `placer` VARCHAR(64) NOT NULL,
        `placer_name` VARCHAR(64) NOT NULL,
        `amount` INT NOT NULL,
        `status` VARCHAR(12) NOT NULL DEFAULT 'open',
        `claimed_by` VARCHAR(64) NULL,
        `claimed_name` VARCHAR(64) NULL,
        `created` INT NOT NULL,
        `closed` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `idx_target_status` (`target`, `status`),
        KEY `idx_placer_status` (`placer`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_wig_catalog` (
        `identifier` VARCHAR(64) NOT NULL,
        `style` VARCHAR(48) NOT NULL,
        `tier` VARCHAR(16) NOT NULL,
        `times` INT NOT NULL DEFAULT 1,
        `first_at` INT NOT NULL,
        PRIMARY KEY (`identifier`, `style`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_wig_listings` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `seller` VARCHAR(64) NOT NULL,
        `seller_name` VARCHAR(64) NOT NULL,
        `kind` VARCHAR(8) NOT NULL DEFAULT 'wig',
        `meta` LONGTEXT NOT NULL,
        `price` INT NOT NULL,
        `status` VARCHAR(12) NOT NULL DEFAULT 'open',
        `buyer` VARCHAR(64) NULL,
        `buyer_name` VARCHAR(64) NULL,
        `created` INT NOT NULL,
        `closed` INT NOT NULL DEFAULT 0,
        `settled` TINYINT(1) NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `idx_status` (`status`, `created`),
        KEY `idx_seller` (`seller`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Upgrading from V2 by hand? Add the new columns (skip any you already have):
-- ALTER TABLE `nz_wig_players` ADD COLUMN `tackles` INT NOT NULL DEFAULT 0;
-- ALTER TABLE `nz_wig_players` ADD COLUMN `ties` INT NOT NULL DEFAULT 0;
-- ALTER TABLE `nz_wig_players` ADD COLUMN `products` INT NOT NULL DEFAULT 0;
-- ALTER TABLE `nz_wig_players` ADD COLUMN `crafted` INT NOT NULL DEFAULT 0;
-- ALTER TABLE `nz_wig_players` ADD COLUMN `stolen_back` INT NOT NULL DEFAULT 0;
