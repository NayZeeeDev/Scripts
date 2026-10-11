-- Database: schema, batched log inserts, log queries and dashboard stats.
local TABLE = 'nayzeee_inventory_logs'

local function columnExists(tbl, col)
    return (MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?', { tbl, col }) or 0) > 0
end

local function indexExists(tbl, idx)
    return (MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?', { tbl, idx }) or 0) > 0
end

local ready = false
local queue = {}

CreateThread(function()
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
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
            INDEX `idx_timestamp` (`timestamp`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(TABLE))

    -- upgrades from 2.x
    if not columnExists(TABLE, 'resource') then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `resource` VARCHAR(64) DEFAULT NULL AFTER `details`'):format(TABLE))
    end
    if not indexExists(TABLE, 'idx_type_time') then
        MySQL.query.await(('ALTER TABLE `%s` ADD INDEX `idx_type_time` (`type`, `timestamp`)'):format(TABLE))
    end

    MySQL.query.await([[
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
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_inventory_snapshots` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `kind` VARCHAR(16) NOT NULL,
            `players` INT(11) NOT NULL DEFAULT 0,
            `data` LONGTEXT NOT NULL,
            `taken_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_kind_time` (`kind`, `taken_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_inventory_supply` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `item` VARCHAR(128) NOT NULL,
            `total` BIGINT NOT NULL DEFAULT 0,
            `taken_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_item_time` (`item`, `taken_at`),
            INDEX `idx_time` (`taken_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    if not indexExists(TABLE, 'idx_type_resource') then
        MySQL.query.await(('ALTER TABLE `%s` ADD INDEX `idx_type_resource` (`type`, `resource`, `timestamp`)'):format(TABLE))
    end

    ready = true
    NZ.Print('Database ready.')

    -- retention runs once at start and then every 6 hours
    while true do
        local days = Config.Logs.RetentionDays or 0
        if days > 0 then
            local n = MySQL.update.await(('DELETE FROM `%s` WHERE `timestamp` < DATE_SUB(NOW(), INTERVAL ? DAY)'):format(TABLE), { days }) or 0
            if n > 0 then NZ.Print(('Removed %d logs older than %d days.'):format(n, days)) end
        end
        local adays = Config.Logs.AuditRetentionDays or 0
        if adays > 0 then
            MySQL.update.await('DELETE FROM `nayzeee_inventory_audit` WHERE `timestamp` < DATE_SUB(NOW(), INTERVAL ? DAY)', { adays })
        end
        Wait(6 * 3600 * 1000)
    end
end)

-- ─── writes (batched: one query per second at most) ─────────────────────────
local COLS = { 'type', 'source_name', 'source_identifier', 'source_id', 'target_name', 'target_identifier', 'target_id',
    'item_name', 'item_label', 'item_count', 'metadata', 'inventory_from', 'inventory_to', 'coords', 'details', 'resource' }
local flushing = false

local function flush()
    if #queue == 0 or not ready then return end
    local batch = queue
    queue = {}
    -- nil values become literal NULLs so the parameter list never has holes
    local rows, params = {}, {}
    for i, l in ipairs(batch) do
        local ph = {}
        for j, c in ipairs(COLS) do
            local v = l[c]
            if c == 'metadata' then v = (type(v) == 'table' and next(v)) and json.encode(v) or nil end
            if c == 'item_label' then v = v or l.item_name end
            if c == 'item_count' then v = math.floor(tonumber(v) or 1) end
            if type(v) == 'string' and c ~= 'metadata' and #v > 1000 then v = v:sub(1, 1000) end
            if v == nil then ph[j] = 'NULL'
            else ph[j] = '?'; params[#params + 1] = v end
        end
        rows[i] = '(' .. table.concat(ph, ',') .. ')'
    end
    MySQL.insert(('INSERT INTO `%s` (`%s`) VALUES %s'):format(TABLE, table.concat(COLS, '`,`'), table.concat(rows, ',')), params)
    TriggerEvent('nzinv:logged', #batch)
end

function InsertLog(l)
    if not l or not l.type or not l.item_name then return end
    if Config.Logs.Enabled[l.type] == false then return end
    queue[#queue + 1] = l
    if not flushing then
        flushing = true
        SetTimeout(1000, function() flushing = false flush() end)
    end
end

AddEventHandler('onResourceStop', function(r) if r == NZ.Resource then flush() end end)

-- ─── queries ────────────────────────────────────────────────────────────────
local function buildWhere(f)
    local where, params = {}, {}
    f = f or {}
    if f.type and f.type ~= '' and f.type ~= 'all' then
        if f.type == 'admin' then
            where[#where + 1] = '`type` IN (\'admin_give\', \'admin_remove\', \'global_give\', \'global_remove\')'
        elseif f.type == 'dupes' then
            where[#where + 1] = '`type` IN (\'dupe\', \'dupe_attempt\', \'supply_spike\')'
        else
            where[#where + 1] = '`type` = ?'
            params[#params + 1] = f.type
        end
    end
    if f.player and f.player ~= '' then
        local q = '%' .. f.player .. '%'
        where[#where + 1] = '(`source_name` LIKE ? OR `source_identifier` LIKE ? OR `target_name` LIKE ? OR `target_identifier` LIKE ? OR `source_id` = ? OR `target_id` = ?)'
        local n = tonumber(f.player) or -1
        params[#params + 1], params[#params + 2], params[#params + 3], params[#params + 4], params[#params + 5], params[#params + 6] = q, q, q, q, n, n
    end
    if f.identifier and f.identifier ~= '' then
        where[#where + 1] = '(`source_identifier` = ? OR `target_identifier` = ?)'
        params[#params + 1], params[#params + 2] = f.identifier, f.identifier
    end
    if f.item and f.item ~= '' then
        local q = '%' .. f.item .. '%'
        where[#where + 1] = '(`item_name` LIKE ? OR `item_label` LIKE ?)'
        params[#params + 1], params[#params + 2] = q, q
    end
    if f.inventory and f.inventory ~= '' then
        where[#where + 1] = '(`inventory_from` = ? OR `inventory_to` = ?)'
        params[#params + 1], params[#params + 2] = f.inventory, f.inventory
    end
    if f.resource and f.resource ~= '' then
        where[#where + 1] = '`resource` = ?'
        params[#params + 1] = f.resource
    end
    if tonumber(f.from) then
        where[#where + 1] = '`timestamp` >= FROM_UNIXTIME(?)'
        params[#params + 1] = tonumber(f.from)
    end
    if tonumber(f.to) then
        where[#where + 1] = '`timestamp` <= FROM_UNIXTIME(?)'
        params[#params + 1] = tonumber(f.to)
    end
    if tonumber(f.after) then
        where[#where + 1] = '`id` > ?'
        params[#params + 1] = tonumber(f.after)
    end
    return (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''), params
end

local SELECT = 'SELECT `id`, `type`, `source_name`, `source_identifier`, `source_id`, `target_name`, `target_identifier`, `target_id`, `item_name`, `item_label`, `item_count`, `metadata`, `inventory_from`, `inventory_to`, `coords`, `details`, `resource`, UNIX_TIMESTAMP(`timestamp`) AS `time` FROM `' .. TABLE .. '`'

function FetchLogs(filters, page, perPage)
    perPage = perPage or Config.Logs.PerPage or 50
    page = math.max(1, tonumber(page) or 1)
    local where, params = buildWhere(filters)
    local total = MySQL.scalar.await('SELECT COUNT(*) FROM `' .. TABLE .. '`' .. where, params) or 0
    local p2 = { table.unpack(params) }
    p2[#p2 + 1] = perPage
    p2[#p2 + 1] = (page - 1) * perPage
    local rows = MySQL.query.await(SELECT .. where .. ' ORDER BY `id` DESC LIMIT ? OFFSET ?', p2) or {}
    return { logs = rows, total = total, page = page, pages = math.max(1, math.ceil(total / perPage)) }
end

function FetchLogsRaw(filters, limit)
    local where, params = buildWhere(filters)
    params[#params + 1] = limit or 100
    return MySQL.query.await(SELECT .. where .. ' ORDER BY `id` DESC LIMIT ?', params) or {}
end

NZ.Route('logs:list', 'view', function(src, d)
    return FetchLogs(d.filters or {}, d.page)
end)

NZ.Route('logs:since', 'view', function(src, d)
    local f = d.filters or {}
    f.after = tonumber(d.after) or 0
    return FetchLogsRaw(f, 100)
end)

NZ.Route('logs:export', 'view', function(src, d)
    local limit = math.min(tonumber(d.limit) or 5000, Config.Logs.ExportLimit or 10000)
    return FetchLogsRaw(d.filters or {}, limit)
end)

NZ.Route('logs:wipe', 'wipe', function(src, d)
    local days = tonumber(d.olderThanDays) or 0
    local n
    if days > 0 then
        n = MySQL.update.await(('DELETE FROM `%s` WHERE `timestamp` < DATE_SUB(NOW(), INTERVAL ? DAY)'):format(TABLE), { days })
    else
        n = MySQL.update.await(('DELETE FROM `%s`'):format(TABLE))
    end
    NZ.Audit(src, 'logs_wipe', days > 0 and ('older than %d days'):format(days) or 'all', { removed = n })
    NZ.NotifyStaff(('%s wiped %s inventory logs'):format(GetPlayerName(src) or 'Console', days > 0 and ('logs older than %d days'):format(days) or 'all'), 'warning', 'staff', src)
    return n or 0
end)

NZ.Route('dashboard', 'view', function(src)
    local H24 = 'WHERE `timestamp` >= DATE_SUB(NOW(), INTERVAL 24 HOUR)'
    local out = {}
    out.total = MySQL.scalar.await('SELECT COUNT(*) FROM `' .. TABLE .. '`') or 0
    out.day = MySQL.scalar.await('SELECT COUNT(*) FROM `' .. TABLE .. '` ' .. H24) or 0
    out.players = MySQL.scalar.await('SELECT COUNT(DISTINCT `source_identifier`) FROM `' .. TABLE .. '` ' .. H24) or 0
    out.suspicious = MySQL.scalar.await('SELECT COUNT(*) FROM `' .. TABLE .. '` ' .. H24 .. ' AND `type` = \'suspicious\'') or 0
    out.admin = MySQL.scalar.await('SELECT COUNT(*) FROM `nayzeee_inventory_audit` WHERE `timestamp` >= DATE_SUB(NOW(), INTERVAL 24 HOUR)') or 0
    out.hourly = MySQL.query.await('SELECT FLOOR(UNIX_TIMESTAMP(`timestamp`) / 3600) AS `h`, COUNT(*) AS `c` FROM `' .. TABLE .. '` ' .. H24 .. ' GROUP BY `h` ORDER BY `h`') or {}
    out.types = MySQL.query.await('SELECT `type`, COUNT(*) AS `c` FROM `' .. TABLE .. '` ' .. H24 .. ' GROUP BY `type` ORDER BY `c` DESC LIMIT 10') or {}
    out.items = MySQL.query.await('SELECT `item_name`, MAX(`item_label`) AS `label`, SUM(`item_count`) AS `moved`, COUNT(*) AS `c` FROM `' .. TABLE .. '` ' .. H24 .. ' AND `type` NOT IN (\'money\', \'suspicious\') GROUP BY `item_name` ORDER BY `moved` DESC LIMIT 8') or {}
    out.actors = MySQL.query.await('SELECT MAX(`source_name`) AS `name`, `source_identifier` AS `identifier`, COUNT(*) AS `c` FROM `' .. TABLE .. '` ' .. H24 .. ' AND `type` <> \'money\' GROUP BY `source_identifier` ORDER BY `c` DESC LIMIT 6') or {}
    out.resources = MySQL.query.await('SELECT `resource`, COUNT(*) AS `c`, SUM(`item_count`) AS `n` FROM `' .. TABLE .. '` ' .. H24 .. ' AND `type` = \'created\' AND `resource` IS NOT NULL GROUP BY `resource` ORDER BY `c` DESC LIMIT 8') or {}
    out.money = MySQL.single.await('SELECT COALESCE(SUM(CASE WHEN `item_count` > 0 THEN `item_count` ELSE 0 END), 0) AS `inflow`, COALESCE(SUM(CASE WHEN `item_count` < 0 THEN -`item_count` ELSE 0 END), 0) AS `outflow` FROM `' .. TABLE .. '` ' .. H24 .. ' AND `type` = \'money\'') or { inflow = 0, outflow = 0 }
    out.recent = FetchLogsRaw({}, 8)
    out.flagged = FetchLogsRaw({ type = 'suspicious' }, 6)
    out.online = #GetPlayers()
    out.spikes = GetMoneySpikes and GetMoneySpikes() or {}
    return out
end)
