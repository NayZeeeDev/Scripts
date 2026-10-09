-- nayzeee-bodybag install
-- OPTIONAL since 1.2.0: the resource creates these tables by itself on start.
-- Run this by hand only if your DB user isn't allowed to CREATE/ALTER tables.

CREATE TABLE IF NOT EXISTS `nayzeee_bodybag_cks` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `identifier` VARCHAR(60) NOT NULL,
  `char_name` VARCHAR(100) DEFAULT NULL,
  `reason` TEXT DEFAULT NULL,
  `requested_by` VARCHAR(100) DEFAULT NULL,
  `forced` TINYINT(1) DEFAULT 0,
  `created` DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_identifier` (`identifier`)
);

CREATE TABLE IF NOT EXISTS `nayzeee_bodybag_graves` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `coords` TEXT NOT NULL,
  `heading` FLOAT DEFAULT 0.0,
  `data` TEXT DEFAULT NULL,
  `cemetery` TINYINT(1) DEFAULT 0,
  `created` DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `nayzeee_bodybag_evidence` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `type` VARCHAR(30) NOT NULL,
  `coords` TEXT NOT NULL,
  `source_name` VARCHAR(100) DEFAULT NULL,
  `details` TEXT DEFAULT NULL,
  `created` DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Upgrading from 1.1.x? (MariaDB syntax - on MySQL 8 drop the "IF NOT EXISTS")
ALTER TABLE `nayzeee_bodybag_evidence` ADD COLUMN IF NOT EXISTS `details` TEXT DEFAULT NULL;

-- CK lock flag on characters (used when Config.CK.DeleteCharacter = false)
ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `ck_locked` TINYINT(1) DEFAULT 0;
