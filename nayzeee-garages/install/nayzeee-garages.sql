-- nayzeee-garages database schema.
-- You do NOT need to run this manually: the resource creates/updates everything on start
-- (server/migrations.lua). It is provided for reference and for manual installs.

CREATE TABLE IF NOT EXISTS `nz_locations` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `kind` VARCHAR(16) NOT NULL,                -- garage | job | private | impound
  `name` VARCHAR(100) NOT NULL,
  `enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `data` LONGTEXT NOT NULL,                   -- JSON, see docs/ARCHITECTURE.md §4.2
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `nz_locations_kind` (`kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_interiors` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(100) NOT NULL,
  `enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `data` LONGTEXT NOT NULL,                   -- JSON, see docs/ARCHITECTURE.md §4.3
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_groups` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `location_id` INT UNSIGNED NOT NULL,
  `label` VARCHAR(100) NOT NULL,
  `owner` VARCHAR(64) NOT NULL,
  `price` INT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `nz_groups_location` (`location_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_group_members` (
  `group_id` INT UNSIGNED NOT NULL,
  `identifier` VARCHAR(64) NOT NULL,
  `name` VARCHAR(100) NOT NULL DEFAULT '',
  `role` VARCHAR(16) NOT NULL DEFAULT 'member', -- owner | member
  `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`group_id`, `identifier`),
  KEY `nz_group_members_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_favourites` (
  `identifier` VARCHAR(64) NOT NULL,
  `plate` VARCHAR(16) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`, `plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_shares` (
  `plate` VARCHAR(16) NOT NULL,
  `identifier` VARCHAR(64) NOT NULL,
  `name` VARCHAR(100) NOT NULL DEFAULT '',
  `shared_by` VARCHAR(64) NOT NULL DEFAULT '',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`plate`, `identifier`),
  KEY `nz_shares_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_vehicle_events` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `kind` VARCHAR(16) NOT NULL,                -- owner | service
  `data` LONGTEXT NOT NULL,                   -- JSON
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `nz_vehicle_events_plate_kind` (`plate`, `kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_settings` (
  `key` VARCHAR(64) NOT NULL,
  `value` LONGTEXT NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nz_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event` VARCHAR(48) NOT NULL,
  `identifier` VARCHAR(64) DEFAULT NULL,
  `plate` VARCHAR(16) DEFAULT NULL,
  `data` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `nz_logs_plate` (`plate`),
  KEY `nz_logs_event` (`event`),
  KEY `nz_logs_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Built-in car lock (config/carlock.lua): persistent virtual keys an owner gave to other
-- characters (virtual key mode). Temporary keys live in memory only.
CREATE TABLE IF NOT EXISTS `nz_keys` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,               -- normalized (trimmed, upper-case)
  `identifier` VARCHAR(64) NOT NULL,          -- character that holds the key
  `granted_by` VARCHAR(64) NOT NULL DEFAULT '', -- character that gave it
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `nz_keys_plate_identifier` (`plate`, `identifier`),
  KEY `nz_keys_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Extension columns added to the framework vehicle table
-- (QBCore / Qbox: `player_vehicles`, ESX: `owned_vehicles`).
-- The resource adds them only when missing (checked through INFORMATION_SCHEMA).
--
--   nz_garage    VARCHAR(64)  NULL       garage key: L<id> | G<id> | H<id>
--   nz_state     TINYINT      NOT NULL DEFAULT 1   0 out, 1 garaged, 2 impounded
--   nz_nickname  VARCHAR(64)  NULL
--   nz_type      VARCHAR(8)   NULL       car | sea | air
--   nz_job       VARCHAR(64)  NULL       job-owned fleet vehicle
--   nz_gang      VARCHAR(64)  NULL       gang-owned fleet vehicle
--   nz_mileage   DOUBLE       NOT NULL DEFAULT 0   kilometres
--   nz_damage    LONGTEXT     NULL       JSON (NZ.Damage format)
--   nz_trailer   LONGTEXT     NULL       JSON { hash, model, props, damage }
--   nz_impound   LONGTEXT     NULL       JSON ImpoundInfo
--   nz_blocked   TINYINT(1)   NOT NULL DEFAULT 0
--   nz_last_out  INT          NULL       unix time the vehicle was last taken out
--   nz_finance_total INT      NULL       total number of finance payments (progress display)
--   nz_key_version INT        NOT NULL DEFAULT 0   car lock: key items of an older version stop working
--   nz_key_owner VARCHAR(64)  NULL       car lock: owner (hashed owner / job / gang) the keys were
--                                         cut for; a different owner gets a new key version
--   nz_plate_norm VARCHAR(64) VIRTUAL    LEFT(UPPER(TRIM(plate)), 64), optional (a failure
--                                         to create it is only a warning)
--
-- Indexes added when missing:
--   nz_idx_plate_norm (nz_plate_norm)    fast lookups of plates with odd spacing / case
--   nz_idx_fw_state   (state | pound)    impound staff list (qb `state` / ESX `pound`)
--
-- Example for QBCore / Qbox (MariaDB syntax):
-- ALTER TABLE `player_vehicles`
--   ADD COLUMN IF NOT EXISTS `nz_garage` VARCHAR(64) NULL,
--   ADD COLUMN IF NOT EXISTS `nz_state` TINYINT NOT NULL DEFAULT 1,
--   ADD COLUMN IF NOT EXISTS `nz_nickname` VARCHAR(64) NULL,
--   ADD COLUMN IF NOT EXISTS `nz_type` VARCHAR(8) NULL,
--   ADD COLUMN IF NOT EXISTS `nz_job` VARCHAR(64) NULL,
--   ADD COLUMN IF NOT EXISTS `nz_gang` VARCHAR(64) NULL,
--   ADD COLUMN IF NOT EXISTS `nz_mileage` DOUBLE NOT NULL DEFAULT 0,
--   ADD COLUMN IF NOT EXISTS `nz_damage` LONGTEXT NULL,
--   ADD COLUMN IF NOT EXISTS `nz_trailer` LONGTEXT NULL,
--   ADD COLUMN IF NOT EXISTS `nz_impound` LONGTEXT NULL,
--   ADD COLUMN IF NOT EXISTS `nz_blocked` TINYINT(1) NOT NULL DEFAULT 0,
--   ADD COLUMN IF NOT EXISTS `nz_last_out` INT NULL,
--   ADD COLUMN IF NOT EXISTS `nz_finance_total` INT NULL,
--   ADD COLUMN IF NOT EXISTS `nz_key_version` INT NOT NULL DEFAULT 0,
--   ADD COLUMN IF NOT EXISTS `nz_key_owner` VARCHAR(64) NULL;
