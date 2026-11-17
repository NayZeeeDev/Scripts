-- nayzeee-multicharacter 2.0 — the resource also creates these tables automatically on start.

CREATE TABLE IF NOT EXISTS `multichar_characters` (
  `charid`      VARCHAR(64)  NOT NULL,
  `owner`       VARCHAR(64)  NOT NULL,
  `theme`       VARCHAR(32)  NULL DEFAULT NULL,
  `mood`        VARCHAR(32)  NULL DEFAULT NULL,
  `pose`        VARCHAR(32)  NULL DEFAULT NULL,
  `couple_pose` VARCHAR(32)  NULL DEFAULT NULL,
  `weapon`      VARCHAR(64)  NULL DEFAULT NULL,
  `pet`         VARCHAR(32)  NULL DEFAULT NULL,
  `pet_name`    VARCHAR(24)  NULL DEFAULT NULL,
  `nationality` VARCHAR(48)  NULL DEFAULT NULL,
  `backstory`   VARCHAR(600) NULL DEFAULT NULL,
  `favorite`    TINYINT(1)   NOT NULL DEFAULT 0,
  `disabled`    TINYINT(1)   NOT NULL DEFAULT 0,
  `created_at`  INT UNSIGNED NULL DEFAULT NULL,
  `last_played` INT UNSIGNED NULL DEFAULT NULL,
  `playtime`    INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`charid`),
  KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `multichar_slots` (
  `owner` VARCHAR(64) NOT NULL,
  `extra` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `multichar_squads` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sender`         VARCHAR(64) NOT NULL,
  `target`         VARCHAR(64) NOT NULL,
  `type`           ENUM('squad','couple') NOT NULL DEFAULT 'squad',
  `status`         ENUM('pending','accepted') NOT NULL DEFAULT 'pending',
  `pending_type`   ENUM('squad','couple') NULL DEFAULT NULL,
  `pending_by`     VARCHAR(64) NULL DEFAULT NULL,
  `sender_slot`    TINYINT UNSIGNED NULL DEFAULT NULL,
  `target_slot`    TINYINT UNSIGNED NULL DEFAULT NULL,
  `sender_visible` TINYINT(1) NOT NULL DEFAULT 1,
  `target_visible` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at`     INT UNSIGNED NOT NULL,
  `updated_at`     INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `pair` (`sender`, `target`),
  KEY `target` (`target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `multichar_codes` (
  `code`       VARCHAR(64) NOT NULL,
  `slots`      INT NOT NULL DEFAULT 1,
  `uses`       INT NOT NULL DEFAULT 1,
  `used`       INT NOT NULL DEFAULT 0,
  `created_at` INT UNSIGNED NULL DEFAULT NULL,
  PRIMARY KEY (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Upgrading from 1.x: copy pose / favorite / nationality / backstory over (optional)
-- INSERT IGNORE INTO multichar_characters (charid, owner, pose, nationality, backstory, favorite, disabled, created_at, last_played, playtime)
--   SELECT charid, owner, pose, nationality, backstory, favorite, disabled, created_at, last_played, playtime FROM nayzeee_multichar;
