-- ═══════════════════════════════════════════════════════════════════════════
--  NAYZEEE AMBULANCE - database tables (oxmysql, MySQL 5.7+ / MariaDB 10.3+)
-- ═══════════════════════════════════════════════════════════════════════════
--
--  You usually do NOT need to run this file: every module creates its own
--  tables on start with CREATE TABLE IF NOT EXISTS. Run it once when your
--  database user is not allowed to create tables, or when you want the tables
--  in place (utf8mb4) before the first start.
--
--  Running it again is safe: nothing is dropped and no data is changed.
--
--  16 tables, in dependency order. There are no foreign keys; the order only
--  follows what the data refers to (a department is the hospital - every
--  point, staff row, ticket, blood bank and pharmacy pool belongs to one).
--
--    core       nza_patients, nza_records             server/core/patients.lua, records.lua
--    hospital   nza_departments, nza_points,          server/modules/hospital.lua
--               nza_staff, nza_hospital_stash
--    checkin    nza_tickets                           server/modules/checkin.lua
--    blood      nza_blood, nza_blood_donors,          server/modules/blood.lua
--               nza_blood_log
--    pharmacy   nza_pharmacy_stock,                   server/modules/pharmacy.lua
--               nza_pharmacy_sales
--    billing    nza_insurance, nza_bills              server/modules/pharmacy_billing.lua
--    dispatch   nza_calls                             server/modules/dispatch_log.lua
--    medbag     nza_bags                              server/modules/medbag.lua
--
--  Every column matches the statement in the file named above. If a module
--  ever changes its table, change it here too.
-- ═══════════════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────────────
--  CORE
-- ───────────────────────────────────────────────────────────────────────────

-- Player patients: injuries, conditions, devices and state survive relog and restart
CREATE TABLE IF NOT EXISTS `nza_patients` (
  `identifier` VARCHAR(64) NOT NULL,
  `data` LONGTEXT NOT NULL,
  `state` VARCHAR(16) NOT NULL DEFAULT 'alive',
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Treatment log (who did what to whom)
CREATE TABLE IF NOT EXISTS `nza_records` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL,
  `medic` VARCHAR(64) NOT NULL DEFAULT 'system',
  `medic_name` VARCHAR(64) NULL,
  `action` VARCHAR(64) NOT NULL,
  `summary` LONGTEXT NULL,
  `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  HOSPITAL (departments built in game with /nzadmin)
-- ───────────────────────────────────────────────────────────────────────────

-- A department is one hospital / EMS organisation (ranks, uniforms, fleet, base point)
CREATE TABLE IF NOT EXISTS `nza_departments` (
  `id` VARCHAR(48) NOT NULL,
  `label` VARCHAR(64) NOT NULL,
  `job` VARCHAR(64) NULL DEFAULT NULL,
  `data` LONGTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sites placed in the world (duty, beds, X-ray table, pharmacy, morgue, ...)
CREATE TABLE IF NOT EXISTS `nza_points` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `department` VARCHAR(48) NOT NULL,
  `type` VARCHAR(32) NOT NULL,
  `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `h` DOUBLE NOT NULL DEFAULT 0,
  `label` VARCHAR(64) NULL DEFAULT NULL,
  `data` LONGTEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `department` (`department`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Staff roster (department + rank per character)
CREATE TABLE IF NOT EXISTS `nza_staff` (
  `identifier` VARCHAR(80) NOT NULL,
  `department` VARCHAR(48) NOT NULL,
  `grade` INT NOT NULL DEFAULT 0,
  `name` VARCHAR(80) NULL DEFAULT NULL,
  `excluded` TINYINT(1) NOT NULL DEFAULT 0,
  `hired_by` VARCHAR(80) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`),
  KEY `department` (`department`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Built-in staff store (used when the inventory has no stash of its own: anything but
-- ox_inventory, qb-inventory, ps-inventory, lj-inventory and qs-inventory)
CREATE TABLE IF NOT EXISTS `nza_hospital_stash` (
  `id` VARCHAR(120) NOT NULL,
  `items` LONGTEXT NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  CHECK-IN
-- ───────────────────────────────────────────────────────────────────────────

-- Queue numbers (A-001 ...) per department per day
CREATE TABLE IF NOT EXISTS `nza_tickets` (
  `id` VARCHAR(24) NOT NULL,
  `hospital` VARCHAR(64) NOT NULL,
  `day` CHAR(10) NOT NULL,
  `prefix` VARCHAR(4) NOT NULL,
  `number` INT NOT NULL,
  `identifier` VARCHAR(80) NULL,
  `name` VARCHAR(80) NULL,
  `triage` TINYINT NOT NULL DEFAULT 3,
  `status` VARCHAR(16) NOT NULL DEFAULT 'waiting',
  `bed` INT NULL,
  `handled_by` VARCHAR(80) NULL,
  `issued` INT NOT NULL,
  `called` INT NULL,
  `closed` INT NULL,
  `data` LONGTEXT NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_nza_tickets_day` (`hospital`, `day`, `prefix`),
  INDEX `idx_nza_tickets_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  BLOOD
-- ───────────────────────────────────────────────────────────────────────────

-- Every labelled blood unit (serial, group, volume, donor, expiry, which bank holds it)
CREATE TABLE IF NOT EXISTS `nza_blood` (
  `serial` VARCHAR(16) NOT NULL,
  `type` VARCHAR(4) NOT NULL,
  `ml` INT NOT NULL DEFAULT 450,
  `donor` VARCHAR(80) NULL,
  `donor_id` VARCHAR(80) NULL,
  `created` INT NOT NULL DEFAULT 0,
  `expires` INT NOT NULL DEFAULT 0,
  `used` TINYINT NOT NULL DEFAULT 0,
  `bank` VARCHAR(64) NULL,
  `updated` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`serial`),
  KEY `bank_used` (`bank`, `used`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Donors (donation cooldown, count, weak-after-donating)
CREATE TABLE IF NOT EXISTS `nza_blood_donors` (
  `identifier` VARCHAR(80) NOT NULL,
  `last` INT NOT NULL DEFAULT 0,
  `count` INT NOT NULL DEFAULT 0,
  `weak_until` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Blood bank log (in, out, fill, discard, expired, donated, seed)
CREATE TABLE IF NOT EXISTS `nza_blood_log` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `bank` VARCHAR(64) NULL,
  `action` VARCHAR(16) NOT NULL,
  `serial` VARCHAR(16) NULL,
  `type` VARCHAR(4) NULL,
  `actor` VARCHAR(80) NULL,
  `at` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `bank_at` (`bank`, `at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  PHARMACY
-- ───────────────────────────────────────────────────────────────────────────

-- Shelf stock per pool (department) and product
CREATE TABLE IF NOT EXISTS `nza_pharmacy_stock` (
  `pool` VARCHAR(48) NOT NULL,
  `item` VARCHAR(64) NOT NULL,
  `stock` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`pool`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sales log
CREATE TABLE IF NOT EXISTS `nza_pharmacy_sales` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `pool` VARCHAR(48) NOT NULL,
  `point` INT NOT NULL DEFAULT 0,
  `identifier` VARCHAR(80) NULL DEFAULT NULL,
  `name` VARCHAR(80) NULL DEFAULT NULL,
  `items` LONGTEXT NULL,
  `subtotal` INT UNSIGNED NOT NULL DEFAULT 0,
  `discount` INT UNSIGNED NOT NULL DEFAULT 0,
  `tax` INT UNSIGNED NOT NULL DEFAULT 0,
  `total` INT UNSIGNED NOT NULL DEFAULT 0,
  `method` VARCHAR(8) NULL DEFAULT NULL,
  `kind` VARCHAR(16) NOT NULL DEFAULT 'shop',
  `created` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `pool_created` (`pool`, `created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  BILLING & INSURANCE
-- ───────────────────────────────────────────────────────────────────────────

-- Health insurance plan per character
CREATE TABLE IF NOT EXISTS `nza_insurance` (
  `identifier` VARCHAR(80) NOT NULL,
  `plan` VARCHAR(32) NOT NULL,
  `expires` INT UNSIGNED NOT NULL DEFAULT 0,
  `started` INT UNSIGNED NOT NULL DEFAULT 0,
  `serial` VARCHAR(24) NULL DEFAULT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Medical bills (paid and unpaid)
CREATE TABLE IF NOT EXISTS `nza_bills` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(80) NOT NULL,
  `name` VARCHAR(80) NULL DEFAULT NULL,
  `amount` INT UNSIGNED NOT NULL DEFAULT 0,
  `covered` INT UNSIGNED NOT NULL DEFAULT 0,
  `reason` VARCHAR(120) NULL DEFAULT NULL,
  `kind` VARCHAR(32) NULL DEFAULT NULL,
  `medic` VARCHAR(80) NULL DEFAULT NULL,
  `medic_name` VARCHAR(80) NULL DEFAULT NULL,
  `society` VARCHAR(64) NULL DEFAULT NULL,
  `status` VARCHAR(12) NOT NULL DEFAULT 'unpaid',
  `created` INT UNSIGNED NOT NULL DEFAULT 0,
  `paid_at` INT UNSIGNED NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `identifier_status` (`identifier`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  DISPATCH
-- ───────────────────────────────────────────────────────────────────────────

-- Call log (player 911, NPC calls, phone calls)
CREATE TABLE IF NOT EXISTS `nza_calls` (
  `id` VARCHAR(16) NOT NULL,
  `code` VARCHAR(16) DEFAULT NULL,
  `priority` TINYINT NOT NULL DEFAULT 2,
  `title` VARCHAR(64) DEFAULT NULL,
  `type` VARCHAR(24) DEFAULT NULL,
  `x` FLOAT NOT NULL DEFAULT 0,
  `y` FLOAT NOT NULL DEFAULT 0,
  `z` FLOAT NOT NULL DEFAULT 0,
  `street` VARCHAR(80) DEFAULT NULL,
  `zone` VARCHAR(64) DEFAULT NULL,
  `caller` VARCHAR(64) DEFAULT NULL,
  `message` VARCHAR(255) DEFAULT NULL,
  `source` VARCHAR(12) DEFAULT NULL,
  `npc` TINYINT(1) NOT NULL DEFAULT 0,
  `status` VARCHAR(8) NOT NULL DEFAULT 'DSP',
  `units` LONGTEXT DEFAULT NULL,
  `reason` VARCHAR(32) DEFAULT NULL,
  `created` INT UNSIGNED NOT NULL,
  `responded` INT UNSIGNED DEFAULT NULL,
  `arrived` INT UNSIGNED DEFAULT NULL,
  `closed` INT UNSIGNED DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `created` (`created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  MEDICAL BAG
-- ───────────────────────────────────────────────────────────────────────────

-- Contents of every medical bag (items = JSON slots, lock, owner, world position)
CREATE TABLE IF NOT EXISTS `nza_bags` (
  `id` VARCHAR(32) NOT NULL,
  `owner` VARCHAR(64) NULL DEFAULT NULL,
  `items` LONGTEXT NULL,
  PRIMARY KEY (`id`),
  KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
