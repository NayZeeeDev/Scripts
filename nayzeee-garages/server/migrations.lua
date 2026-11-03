--[[
  nayzeee-garages — database migrations (NZ.DB.migrate, NZ.DB.loadSchema).

  Creates the nz_* tables, adds the nz_* extension columns and indexes to the framework
  vehicle table (checked through INFORMATION_SCHEMA, so it works on MySQL and MariaDB),
  runs the one-time backfill and caches the vehicle table column map that server/db.lua
  uses to build statements only from columns that actually exist.
]]

local DB = NZ.DB
local isEsx = NZ.Framework == 'esx'

--- Framework vehicle table: QBCore / Qbox `player_vehicles`, ESX `owned_vehicles`.
DB.vehicleTable = isEsx and 'owned_vehicles' or 'player_vehicles'

--- Cached schema information, filled by NZ.DB.loadSchema() (and NZ.DB.migrate()).
---   loaded         boolean  the column map was read successfully at least once
---   exists         boolean  the vehicle table exists (has a `plate` column)
---   columns        { [lowercase column] = true } columns of the vehicle table
---   financeMode    'none' | 'columns' (qb player_vehicles) | 'table' (qbx vehicle_financing)
---   financeColumns { [lowercase column] = true } columns of vehicle_financing
---   version        bumped on every reload; statement caches in db.lua key on it
DB.schema = DB.schema or {
  loaded = false,
  exists = false,
  columns = {},
  financeMode = 'none',
  financeColumns = {},
  version = 0,
  lastAttempt = nil,
}

local MIGRATION_KEY = 'migration_v1'
local RELOAD_THROTTLE_MS = 10000

-- nz_* tables: identical to install/nayzeee-garages.sql
local TABLES = {
  [[CREATE TABLE IF NOT EXISTS `nz_locations` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `kind` VARCHAR(16) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `data` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `nz_locations_kind` (`kind`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS `nz_interiors` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `data` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS `nz_groups` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `location_id` INT UNSIGNED NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `owner` VARCHAR(64) NOT NULL,
    `price` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `nz_groups_location` (`location_id`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS `nz_group_members` (
    `group_id` INT UNSIGNED NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `name` VARCHAR(100) NOT NULL DEFAULT '',
    `role` VARCHAR(16) NOT NULL DEFAULT 'member',
    `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`group_id`, `identifier`),
    KEY `nz_group_members_identifier` (`identifier`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS `nz_favourites` (
    `identifier` VARCHAR(64) NOT NULL,
    `plate` VARCHAR(16) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `plate`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS `nz_shares` (
    `plate` VARCHAR(16) NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `name` VARCHAR(100) NOT NULL DEFAULT '',
    `shared_by` VARCHAR(64) NOT NULL DEFAULT '',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`plate`, `identifier`),
    KEY `nz_shares_identifier` (`identifier`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS `nz_vehicle_events` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(16) NOT NULL,
    `kind` VARCHAR(16) NOT NULL,
    `data` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `nz_vehicle_events_plate_kind` (`plate`, `kind`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS `nz_settings` (
    `key` VARCHAR(64) NOT NULL,
    `value` LONGTEXT NOT NULL,
    PRIMARY KEY (`key`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS `nz_logs` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `event` VARCHAR(48) NOT NULL,
    `identifier` VARCHAR(64) DEFAULT NULL,
    `plate` VARCHAR(16) DEFAULT NULL,
    `data` LONGTEXT DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `nz_logs_plate` (`plate`),
    KEY `nz_logs_event` (`event`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Extension columns of the framework vehicle table (see install/nayzeee-garages.sql).
local EXT_COLUMNS = {
  { 'nz_garage', 'VARCHAR(64) NULL DEFAULT NULL' },
  { 'nz_state', 'TINYINT NOT NULL DEFAULT 1' },
  { 'nz_nickname', 'VARCHAR(64) NULL DEFAULT NULL' },
  { 'nz_type', 'VARCHAR(8) NULL DEFAULT NULL' },
  { 'nz_job', 'VARCHAR(64) NULL DEFAULT NULL' },
  { 'nz_gang', 'VARCHAR(64) NULL DEFAULT NULL' },
  { 'nz_mileage', 'DOUBLE NOT NULL DEFAULT 0' },
  { 'nz_damage', 'LONGTEXT NULL' },
  { 'nz_trailer', 'LONGTEXT NULL' },
  { 'nz_impound', 'LONGTEXT NULL' },
  { 'nz_blocked', 'TINYINT(1) NOT NULL DEFAULT 0' },
  { 'nz_last_out', 'INT NULL DEFAULT NULL' },
  { 'nz_finance_total', 'INT NULL DEFAULT NULL' }, -- total number of finance payments (progress display)
}

-- Indexes on the vehicle table. Created only when no index already starts with the column.
-- plate / owner normally exist already (framework schema); they are checked for safety.
local INDEXES = {
  { name = 'nz_idx_plate', column = 'plate' },
  { name = 'nz_idx_owner', column = isEsx and 'owner' or 'citizenid' },
  { name = 'nz_idx_garage', column = 'nz_garage' },
  { name = 'nz_idx_state', column = 'nz_state' },
  { name = 'nz_idx_job', column = 'nz_job' },
  { name = 'nz_idx_gang', column = 'nz_gang' },
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function oneLine(sql)
  return (tostring(sql):gsub('%s+', ' '):sub(1, 240))
end

--- Run an oxmysql await method inside pcall. Returns result, ok.
local function run(method, sql, params)
  local ok, res = pcall(MySQL[method].await, sql, params or {})
  if not ok then
    lib.print.error(('[db] migration %s failed: %s | %s'):format(method, tostring(res), oneLine(sql)))
    return nil, false
  end
  return res, true
end

--- Column names of a table in the current database: { [lowercase] = true } or nil on error.
local function readColumns(tableName)
  local rows, ok = run('query', [[
    SELECT `COLUMN_NAME` AS `name` FROM `INFORMATION_SCHEMA`.`COLUMNS`
    WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = ?]], { tableName })
  if not ok then return nil end
  local map = {}
  for _, row in ipairs(rows or {}) do
    if type(row.name) == 'string' then map[row.name:lower()] = true end
  end
  return map
end

--- Columns that already lead an index on `tableName`, plus every index name.
local function readIndexes(tableName)
  local rows, ok = run('query', [[
    SELECT `INDEX_NAME` AS `name`, `COLUMN_NAME` AS `col`, `SEQ_IN_INDEX` AS `seq`
    FROM `INFORMATION_SCHEMA`.`STATISTICS`
    WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = ?]], { tableName })
  if not ok then return nil end
  local leading, names = {}, {}
  for _, row in ipairs(rows or {}) do
    if type(row.name) == 'string' then names[row.name:lower()] = true end
    if type(row.col) == 'string' and tonumber(row.seq) == 1 then leading[row.col:lower()] = true end
  end
  return leading, names
end

---------------------------------------------------------------------------------------
-- Schema cache
---------------------------------------------------------------------------------------

--- (Re)read the vehicle table column map and the finance storage mode into NZ.DB.schema.
--- Throttled when the database is unreachable so failing calls do not spam queries.
---@param force boolean|nil ignore the retry throttle
---@return boolean exists the vehicle table is usable
function DB.loadSchema(force)
  local s = DB.schema
  local now = GetGameTimer()
  if not force and not s.loaded and s.lastAttempt and now - s.lastAttempt < RELOAD_THROTTLE_MS then
    return false
  end
  s.lastAttempt = now

  local cols = readColumns(DB.vehicleTable)
  if not cols then return s.exists == true end

  local financeMode, financeCols = 'none', {}
  if not isEsx and cols.plate then
    local hasColumns = (cols.balance and cols.paymentamount and cols.paymentsleft and cols.financetime) ~= nil
    local hasTable = false
    if cols.id then
      local fc = readColumns('vehicle_financing')
      if fc and fc.vehicleid and fc.balance and fc.paymentamount and fc.paymentsleft and fc.financetime then
        hasTable, financeCols = true, fc
      end
    end
    if hasTable and (NZ.Framework == 'qbx' or not hasColumns) then
      financeMode = 'table'
    elseif hasColumns then
      financeMode = 'columns'
    end
  end

  s.columns = cols
  s.exists = cols.plate == true
  s.financeMode = financeMode
  s.financeColumns = financeCols
  s.loaded = true
  s.version = (s.version or 0) + 1
  return s.exists
end

---------------------------------------------------------------------------------------
-- Migration steps
---------------------------------------------------------------------------------------

local function createTables()
  local okAll = true
  for _, sql in ipairs(TABLES) do
    local _, ok = run('query', sql)
    okAll = okAll and ok
  end
  return okAll
end

local function addColumns(cols)
  local added = 0
  for _, def in ipairs(EXT_COLUMNS) do
    local name, definition = def[1], def[2]
    if not cols[name] then
      local _, ok = run('query', ('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(DB.vehicleTable, name, definition))
      if ok then
        cols[name] = true
        added = added + 1
      end
    end
  end
  return added
end

local function addIndexes(cols)
  local leading, names = readIndexes(DB.vehicleTable)
  if not leading then return 0 end
  local added = 0
  for _, idx in ipairs(INDEXES) do
    if cols[idx.column] and not leading[idx.column] and not names[idx.name] then
      local sql = ('ALTER TABLE `%s` ADD INDEX `%s` (`%s`)'):format(DB.vehicleTable, idx.name, idx.column)
      local _, ok = run('query', sql)
      if ok then
        added = added + 1
      else
        lib.print.warn(('[db] could not add index %s on %s.%s (continuing without it)')
          :format(idx.name, DB.vehicleTable, idx.column))
      end
    end
  end
  return added
end

--- SQL expression mapping the framework columns to an nz_state code, or nil if impossible.
local function frameworkStateSql(cols)
  if not isEsx then
    if not cols.state then return nil end
    return 'CASE WHEN `state` = 0 THEN 0 WHEN `state` = 2 THEN 2 ELSE 1 END'
  end
  if not cols.stored then return nil end
  local pound = cols.pound and "WHEN `pound` IS NOT NULL AND `pound` <> '' THEN 2 " or ''
  return 'CASE ' .. pound .. 'WHEN `stored` = 1 THEN 1 ELSE 0 END'
end

--- One-time backfill (guarded by nz_settings 'migration_v1'): nz_state from the framework
--- state columns and nz_type from the ESX `type` column, for rows never touched by us.
local function backfill(cols)
  local done, ok = run('scalar', 'SELECT `value` FROM `nz_settings` WHERE `key` = ? LIMIT 1', { MIGRATION_KEY })
  if not ok then return false end
  if done ~= nil then return true end
  if not cols.nz_state then return false end

  local sets = {}
  local stateSql = frameworkStateSql(cols)
  if stateSql then sets[#sets + 1] = '`nz_state` = (' .. stateSql .. ')' end
  if isEsx and cols.type and cols.nz_type then
    sets[#sets + 1] = [[`nz_type` = IFNULL(`nz_type`, CASE LOWER(`type`)
      WHEN 'boat' THEN 'sea' WHEN 'submarine' THEN 'sea'
      WHEN 'airplane' THEN 'air' WHEN 'plane' THEN 'air' WHEN 'helicopter' THEN 'air' WHEN 'heli' THEN 'air'
      ELSE 'car' END)]]
  end

  local affected = 0
  if #sets > 0 then
    local where = { '`nz_garage` IS NULL' }
    if cols.nz_last_out then where[#where + 1] = '`nz_last_out` IS NULL' end
    if cols.nz_impound then where[#where + 1] = '`nz_impound` IS NULL' end
    local sql = ('UPDATE `%s` SET %s WHERE %s'):format(DB.vehicleTable, table.concat(sets, ', '),
      table.concat(where, ' AND '))
    local res, updated = run('update', sql)
    if not updated then return false end
    affected = tonumber(res) or 0
  end

  local marker = json.encode({ at = os.time(), framework = NZ.Framework, rows = affected })
  local _, saved = run('update',
    'INSERT INTO `nz_settings` (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = ?',
    { MIGRATION_KEY, marker, marker })
  if saved then
    lib.print.info(('[db] one-time backfill done (%d vehicle rows mapped from %s)'):format(affected, DB.vehicleTable))
  end
  return saved
end

---------------------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------------------

--- Create / update every table, column and index this resource needs. Idempotent; called
--- once at boot by server/main.lua (must run inside a thread: it awaits queries).
---@return boolean ok the vehicle table is usable
function DB.migrate()
  local started = GetGameTimer()
  local tablesOk = createTables()
  if not tablesOk then
    lib.print.error('[db] some nz_* tables could not be created; check the oxmysql connection and permissions')
  end

  local cols = readColumns(DB.vehicleTable)
  if not cols then
    lib.print.error(('[db] could not read the schema of `%s` (database unreachable?)'):format(DB.vehicleTable))
    return false
  end
  if not cols.plate then
    lib.print.error(('[db] vehicle table `%s` was not found in the current database. Install the %s SQL first.')
      :format(DB.vehicleTable, NZ.Framework))
    DB.loadSchema(true)
    return false
  end

  local added = addColumns(cols)
  local missing = {}
  for _, def in ipairs(EXT_COLUMNS) do
    if not cols[def[1]] then missing[#missing + 1] = def[1] end
  end
  if #missing > 0 then
    lib.print.error(('[db] could not add columns to `%s`: %s (ALTER permission?)')
      :format(DB.vehicleTable, table.concat(missing, ', ')))
  end

  local indexes = addIndexes(cols)
  backfill(cols)

  local usable = DB.loadSchema(true)
  lib.print.info(('[db] database ready: %s (%s), %d column(s) and %d index(es) added, finance: %s, %d ms')
    :format(DB.vehicleTable, NZ.Framework, added, indexes, DB.schema.financeMode, GetGameTimer() - started))
  return usable and #missing == 0
end
