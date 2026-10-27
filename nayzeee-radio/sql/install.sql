-- ═══════════════════════════════════════════════════════════════════════════
--  NAYZEEE RADIO - database tables (oxmysql, MySQL 5.7+ / MariaDB 10.3+)
-- ═══════════════════════════════════════════════════════════════════════════
--
--  You usually do NOT need to run this file: server/core/db.lua creates these
--  tables on start with CREATE TABLE IF NOT EXISTS. Run it once when your
--  database user is not allowed to create tables, or when you want the tables
--  in place (utf8mb4) before the first start.
--
--  Running it again is safe: nothing is dropped and no data is changed.
--
--  oxmysql is optional. Without it the radio keeps the same data as JSON in
--  data/players.json, data/channels.json and data/vehicles.json inside the
--  resource (the data/ folder must be writable by the server).
--
--  3 tables, no foreign keys:
--
--    nzr_players    memory presets and callsign per character      server/core/db.lua
--                   (identifier = ESX identifier / QB citizenid / license)
--    nzr_channels   channel locks set in /radioadmin               server/modules/channels.lua
--    nzr_vehicles   radio vehicles added in /radioadmin            server/modules/vehicles.lua
--
--  Every column, key and default matches the statements in server/core/db.lua.
--  If that file ever changes a table, change it here too.
-- ═══════════════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────────────
--  PLAYERS
-- ───────────────────────────────────────────────────────────────────────────

-- presets = JSON list, one entry per memory: a frequency (155.5) or false (free)
CREATE TABLE IF NOT EXISTS `nzr_players` (
  `identifier` VARCHAR(80) NOT NULL,
  `presets` LONGTEXT NULL,
  `callsign` VARCHAR(16) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  CHANNELS
-- ───────────────────────────────────────────────────────────────────────────

-- access = 'open' | 'code' | 'job'; code = 4 digits; jobs = JSON { "police": 0 } (job → min grade)
-- These entries win over Config.Channels.Restricted for the same frequency.
CREATE TABLE IF NOT EXISTS `nzr_channels` (
  `freq` VARCHAR(8) NOT NULL,
  `access` VARCHAR(8) NOT NULL DEFAULT 'open',
  `code` VARCHAR(8) NULL,
  `jobs` LONGTEXT NULL,
  `label` VARCHAR(32) NULL,
  `updated_by` VARCHAR(80) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`freq`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ───────────────────────────────────────────────────────────────────────────
--  VEHICLES
-- ───────────────────────────────────────────────────────────────────────────

-- model = spawn name; range_mult multiplies Config.Vehicles.range (0.5 - 3.0)
CREATE TABLE IF NOT EXISTS `nzr_vehicles` (
  `model` VARCHAR(64) NOT NULL,
  `label` VARCHAR(32) NULL,
  `range_mult` FLOAT NOT NULL DEFAULT 1.0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
