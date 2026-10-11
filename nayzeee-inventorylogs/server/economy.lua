-- Economy (money sources vs sinks, item sources) and the staff leaderboard.
local RANGES = { ['24h'] = 86400, ['7d'] = 604800, ['30d'] = 2592000 }
local function since(r) return os.time() - (RANGES[r] or RANGES['24h']) end
local T = '`nayzeee_inventory_logs`'
-- money moved between players or between a player's own accounts isn't income or spending
local NOT_ECONOMY = " AND (`resource` IS NULL OR `resource` <> 'transfer')"

local function groupCol(by) return by == 'reason' and 'COALESCE(`inventory_from`, \'No reason given\')' or 'COALESCE(`resource`, \'unattributed\')' end

NZ.Route('eco:money', 'view', function(src, d)
    local from = since(d.range)
    local g = groupCol(d.by)
    local W = ' WHERE `type` = \'money\' AND `timestamp` >= FROM_UNIXTIME(?)' .. NOT_ECONOMY
    local out = {}
    out.totals = MySQL.single.await(('SELECT COALESCE(SUM(CASE WHEN `item_count` > 0 THEN `item_count` END), 0) AS `inflow`, COALESCE(-SUM(CASE WHEN `item_count` < 0 THEN `item_count` END), 0) AS `outflow`, COUNT(*) AS `n`, COALESCE(SUM(CASE WHEN `resource` IS NULL THEN ABS(`item_count`) END), 0) AS `unattributed` FROM %s%s'):format(T, W), { from })
    out.sources = MySQL.query.await(('SELECT %s AS `k`, SUM(`item_count`) AS `total`, COUNT(*) AS `n` FROM %s%s AND `item_count` > 0 GROUP BY `k` ORDER BY `total` DESC LIMIT 20'):format(g, T, W), { from }) or {}
    out.sinks = MySQL.query.await(('SELECT %s AS `k`, -SUM(`item_count`) AS `total`, COUNT(*) AS `n` FROM %s%s AND `item_count` < 0 GROUP BY `k` ORDER BY `total` DESC LIMIT 20'):format(g, T, W), { from }) or {}
    out.accounts = MySQL.query.await(('SELECT `item_name` AS `account`, COALESCE(SUM(CASE WHEN `item_count` > 0 THEN `item_count` END), 0) AS `inflow`, COALESCE(-SUM(CASE WHEN `item_count` < 0 THEN `item_count` END), 0) AS `outflow` FROM %s%s GROUP BY `item_name`'):format(T, W), { from }) or {}
    local bucket = d.range == '24h' and 3600 or 86400
    out.bucket = bucket
    out.flow = MySQL.query.await(('SELECT FLOOR(UNIX_TIMESTAMP(`timestamp`) / %d) AS `b`, COALESCE(SUM(CASE WHEN `item_count` > 0 THEN `item_count` END), 0) AS `inflow`, COALESCE(-SUM(CASE WHEN `item_count` < 0 THEN `item_count` END), 0) AS `outflow` FROM %s%s GROUP BY `b` ORDER BY `b`'):format(bucket, T, W), { from }) or {}
    out.bridged = FrameworkBridged()
    return out
end)

--- One source/sink: reasons (or scripts), accounts, and the characters involved
NZ.Route('eco:moneyDetail', 'view', function(src, d)
    local from = since(d.range)
    local byReason = d.by == 'reason'
    local keyCol = groupCol(d.by)
    local other = byReason and groupCol('resource') or groupCol('reason')
    local sign = d.side == 'sink' and '<' or '>'
    local W = (' WHERE `type` = \'money\' AND `timestamp` >= FROM_UNIXTIME(?) AND `item_count` %s 0 AND %s = ?'):format(sign, keyCol) .. NOT_ECONOMY
    local p = { from, d.key }
    return {
        breakdown = MySQL.query.await(('SELECT %s AS `k`, ABS(SUM(`item_count`)) AS `total`, COUNT(*) AS `n` FROM %s%s GROUP BY `k` ORDER BY `total` DESC LIMIT 15'):format(other, T, W), p) or {},
        accounts = MySQL.query.await(('SELECT `item_name` AS `account`, ABS(SUM(`item_count`)) AS `total` FROM %s%s GROUP BY `item_name` ORDER BY `total` DESC'):format(T, W), p) or {},
        players = MySQL.query.await(('SELECT MAX(`source_name`) AS `name`, `source_identifier` AS `identifier`, ABS(SUM(`item_count`)) AS `total`, COUNT(*) AS `n` FROM %s%s GROUP BY `source_identifier` ORDER BY `total` DESC LIMIT 15'):format(T, W), p) or {},
    }
end)

NZ.Route('eco:items', 'view', function(src, d)
    local from = since(d.range)
    return MySQL.query.await(('SELECT COALESCE(`resource`, \'unknown\') AS `k`, SUM(`item_count`) AS `total`, COUNT(*) AS `n`, COUNT(DISTINCT `item_name`) AS `kinds`, COUNT(DISTINCT `source_identifier`) AS `players` FROM %s WHERE `type` = \'created\' AND `timestamp` >= FROM_UNIXTIME(?) GROUP BY `k` ORDER BY `n` DESC LIMIT 25'):format(T), { from }) or {}
end)

NZ.Route('eco:itemsDetail', 'view', function(src, d)
    local from = since(d.range)
    local W = ' WHERE `type` = \'created\' AND `timestamp` >= FROM_UNIXTIME(?) AND COALESCE(`resource`, \'unknown\') = ?'
    local p = { from, d.key }
    return {
        items = MySQL.query.await(('SELECT `item_name`, MAX(`item_label`) AS `label`, SUM(`item_count`) AS `total`, COUNT(*) AS `n` FROM %s%s GROUP BY `item_name` ORDER BY `total` DESC LIMIT 25'):format(T, W), p) or {},
        players = MySQL.query.await(('SELECT MAX(`source_name`) AS `name`, `source_identifier` AS `identifier`, SUM(`item_count`) AS `total`, COUNT(*) AS `n` FROM %s%s GROUP BY `source_identifier` ORDER BY `n` DESC LIMIT 15'):format(T, W), p) or {},
    }
end)

--- How one character got their money and items
NZ.Route('eco:player', 'view', function(src, d)
    if not d.identifier or d.identifier == '' then return {} end
    local from = since(d.range or '7d')
    local p = { d.identifier, from }
    return {
        income = MySQL.query.await(('SELECT COALESCE(`resource`, \'unattributed\') AS `k`, SUM(`item_count`) AS `total`, COUNT(*) AS `n` FROM %s WHERE `type` = \'money\' AND `source_identifier` = ? AND `timestamp` >= FROM_UNIXTIME(?) AND `item_count` > 0%s GROUP BY `k` ORDER BY `total` DESC'):format(T, NOT_ECONOMY), p) or {},
        spending = MySQL.query.await(('SELECT COALESCE(`resource`, \'unattributed\') AS `k`, -SUM(`item_count`) AS `total`, COUNT(*) AS `n` FROM %s WHERE `type` = \'money\' AND `source_identifier` = ? AND `timestamp` >= FROM_UNIXTIME(?) AND `item_count` < 0%s GROUP BY `k` ORDER BY `total` DESC'):format(T, NOT_ECONOMY), p) or {},
        items = MySQL.query.await(('SELECT COALESCE(`resource`, \'unknown\') AS `k`, `item_name`, MAX(`item_label`) AS `label`, SUM(`item_count`) AS `total`, COUNT(*) AS `n` FROM %s WHERE `type` = \'created\' AND `source_identifier` = ? AND `timestamp` >= FROM_UNIXTIME(?) GROUP BY `k`, `item_name` ORDER BY `total` DESC LIMIT 60'):format(T), p) or {},
    }
end)

-- ─── staff leaderboard ───────────────────────────────────────────────────────
local CATEGORY = {
    give = 'gives', global_give = 'globals',
    remove = 'removes', remove_from_inventory = 'removes', dupe_remove = 'removes', global_remove = 'globals',
    wipe_inventory = 'wipes', logs_wipe = 'wipes',
    rollback_money = 'rollbacks', rollback_inventory = 'rollbacks', snapshot_take = 'rollbacks',
}

NZ.Route('staff:board', 'view', function(src, d)
    local from = d.range == 'all' and 0 or since(d.range)
    local rows = MySQL.query.await('SELECT MAX(`admin_name`) AS `name`, `admin_identifier` AS `id`, `action`, COUNT(*) AS `c`, MAX(UNIX_TIMESTAMP(`timestamp`)) AS `last` FROM `nayzeee_inventory_audit` WHERE `timestamp` >= FROM_UNIXTIME(?) GROUP BY `admin_identifier`, `action`', { from }) or {}
    local staff = {}
    for _, r in ipairs(rows) do
        local s = staff[r.id]
        if not s then
            s = { id = r.id, name = r.name, total = 0, gives = 0, removes = 0, wipes = 0, edits = 0, rollbacks = 0, globals = 0, other = 0, last = 0, items = 0, money = 0 }
            staff[r.id] = s
        end
        local cat = CATEGORY[r.action] or (r.action:sub(1, 7) == 'editor_' and 'edits') or 'other'
        s[cat] = s[cat] + r.c
        s.total = s.total + r.c
        if r.last > s.last then s.last = r.last s.name = r.name end
    end
    -- how much each staff member handed out
    local handed = MySQL.query.await(('SELECT `source_name` AS `name`, SUM(CASE WHEN `item_name` IN (\'money\', \'black_money\', \'cash\') THEN 0 ELSE `item_count` END) AS `items`, SUM(CASE WHEN `item_name` IN (\'money\', \'black_money\', \'cash\') THEN `item_count` ELSE 0 END) AS `money` FROM %s WHERE `type` IN (\'admin_give\', \'global_give\') AND `timestamp` >= FROM_UNIXTIME(?) GROUP BY `source_name`'):format(T), { from }) or {}
    local byName = {}
    for _, h in ipairs(handed) do byName[h.name] = h end
    local list = {}
    for _, s in pairs(staff) do
        local h = byName[s.name]
        if h then s.items, s.money = tonumber(h.items) or 0, tonumber(h.money) or 0 end
        list[#list + 1] = s
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    return { staff = list, limits = Config.StaffBoard }
end)
