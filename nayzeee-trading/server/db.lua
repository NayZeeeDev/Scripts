DB = {}

local schema = {
    [[CREATE TABLE IF NOT EXISTS `nz_trading_profiles` (
        `owner` VARCHAR(64) NOT NULL PRIMARY KEY,
        `name` VARCHAR(32) NOT NULL,
        `settings` LONGTEXT NULL,
        `watchlist` LONGTEXT NULL,
        `active` VARCHAR(10) NOT NULL DEFAULT 'practice',
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_trading_accounts` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `owner` VARCHAR(64) NOT NULL,
        `type` VARCHAR(10) NOT NULL,
        `cash` DECIMAL(18,4) NOT NULL DEFAULT 0,
        `realized` DECIMAL(18,4) NOT NULL DEFAULT 0,
        `fees` DECIMAL(18,4) NOT NULL DEFAULT 0,
        `trades` INT NOT NULL DEFAULT 0,
        `day_start` DECIMAL(18,4) NOT NULL DEFAULT 0,
        `day_key` VARCHAR(10) NULL,
        `reset_at` INT NOT NULL DEFAULT 0,
        UNIQUE KEY `owner_type` (`owner`, `type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_trading_positions` (
        `account_id` INT NOT NULL,
        `symbol` VARCHAR(10) NOT NULL,
        `qty` DECIMAL(20,6) NOT NULL,
        `avg_price` DECIMAL(18,6) NOT NULL,
        PRIMARY KEY (`account_id`, `symbol`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_trading_orders` (
        `id` INT NOT NULL PRIMARY KEY,
        `account_id` INT NOT NULL,
        `symbol` VARCHAR(10) NOT NULL,
        `side` VARCHAR(4) NOT NULL,
        `type` VARCHAR(8) NOT NULL,
        `qty` DECIMAL(20,6) NOT NULL,
        `limit_price` DECIMAL(18,6) NULL,
        `stop_price` DECIMAL(18,6) NULL,
        `trail` DECIMAL(18,6) NULL,
        `tif` VARCHAR(4) NOT NULL DEFAULT 'gtc',
        `tp` DECIMAL(18,6) NULL,
        `sl` DECIMAL(18,6) NULL,
        `oco` INT NULL,
        `reduce` TINYINT(1) NOT NULL DEFAULT 0,
        `status` VARCHAR(10) NOT NULL,
        `fill_price` DECIMAL(18,6) NULL,
        `reason` VARCHAR(64) NULL,
        `created` INT NOT NULL,
        `updated` INT NOT NULL,
        INDEX `acc_status` (`account_id`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_trading_fills` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `account_id` INT NOT NULL,
        `order_id` INT NOT NULL,
        `symbol` VARCHAR(10) NOT NULL,
        `side` VARCHAR(4) NOT NULL,
        `qty` DECIMAL(20,6) NOT NULL,
        `price` DECIMAL(18,6) NOT NULL,
        `fee` DECIMAL(18,4) NOT NULL,
        `realized` DECIMAL(18,4) NOT NULL,
        `time` INT NOT NULL,
        INDEX `acc` (`account_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_trading_ledger` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `account_id` INT NOT NULL,
        `type` VARCHAR(12) NOT NULL,
        `amount` DECIMAL(18,4) NOT NULL,
        `time` INT NOT NULL,
        INDEX `acc` (`account_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_trading_alerts` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `owner` VARCHAR(64) NOT NULL,
        `symbol` VARCHAR(10) NOT NULL,
        `cond` VARCHAR(5) NOT NULL,
        `price` DECIMAL(18,6) NOT NULL,
        INDEX `owner` (`owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_trading_market` (
        `symbol` VARCHAR(10) NOT NULL PRIMARY KEY,
        `price` DECIMAL(18,6) NOT NULL,
        `prev_close` DECIMAL(18,6) NOT NULL,
        `anchor` DECIMAL(18,6) NOT NULL,
        `day_key` VARCHAR(10) NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_trading_props` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `owner` VARCHAR(64) NOT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `heading` FLOAT NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

function DB.Init()
    for _, q in ipairs(schema) do MySQL.query.await(q) end
end

-- ── profiles ────────────────────────────────────────────────────

function DB.GetProfile(owner)
    local row = MySQL.single.await('SELECT * FROM nz_trading_profiles WHERE owner = ?', { owner })
    if not row then return nil end
    return {
        owner = row.owner,
        name = row.name,
        settings = json.decode(row.settings or '{}') or {},
        watchlist = json.decode(row.watchlist or '[]') or {},
        active = row.active,
    }
end

function DB.CreateProfile(owner, name, watchlist)
    MySQL.insert.await('INSERT INTO nz_trading_profiles (owner, name, settings, watchlist) VALUES (?, ?, ?, ?)',
        { owner, name, '{}', json.encode(watchlist) })
end

function DB.SaveProfileField(owner, field, value)
    -- field is always one of the fixed column names below, never user input
    local cols = { settings = true, watchlist = true, active = true }
    if not cols[field] then return end
    if type(value) == 'table' then value = json.encode(value) end
    MySQL.update(('UPDATE nz_trading_profiles SET `%s` = ? WHERE owner = ?'):format(field), { value, owner })
end

function DB.Leaderboard(kind)
    return MySQL.query.await([[
        SELECT p.name, a.realized, a.trades, a.fees
        FROM nz_trading_accounts a JOIN nz_trading_profiles p ON p.owner = a.owner
        WHERE a.type = ? AND a.trades > 0
        ORDER BY a.realized DESC LIMIT 25
    ]], { kind }) or {}
end

-- ── accounts ────────────────────────────────────────────────────

function DB.CreateAccount(owner, kind, cash)
    return MySQL.insert.await('INSERT INTO nz_trading_accounts (owner, type, cash, day_start) VALUES (?, ?, ?, ?)',
        { owner, kind, cash, cash })
end

function DB.GetAccounts(owner)
    return MySQL.query.await('SELECT * FROM nz_trading_accounts WHERE owner = ?', { owner }) or {}
end

function DB.GetAccount(id)
    return MySQL.single.await('SELECT * FROM nz_trading_accounts WHERE id = ?', { id })
end

function DB.GetPositions(accountId)
    return MySQL.query.await('SELECT * FROM nz_trading_positions WHERE account_id = ?', { accountId }) or {}
end

function DB.GetWorkingOrders(accountId)
    return MySQL.query.await('SELECT * FROM nz_trading_orders WHERE account_id = ? AND status = ?', { accountId, 'working' }) or {}
end

function DB.ActiveAccountIds()
    return MySQL.query.await([[
        SELECT DISTINCT account_id FROM nz_trading_positions
        UNION SELECT DISTINCT account_id FROM nz_trading_orders WHERE status = 'working'
    ]]) or {}
end

function DB.MaxOrderId()
    local v = MySQL.scalar.await('SELECT MAX(id) FROM nz_trading_orders')
    return tonumber(v) or 0
end

function DB.SaveAccount(a)
    MySQL.update('UPDATE nz_trading_accounts SET cash = ?, realized = ?, fees = ?, trades = ?, day_start = ?, day_key = ?, reset_at = ? WHERE id = ?',
        { a.cash, a.realized, a.fees, a.trades, a.dayStart, a.dayKey, a.resetAt, a.id })
end

function DB.SavePosition(accountId, symbol, pos)
    if not pos or pos.qty == 0 then
        MySQL.query('DELETE FROM nz_trading_positions WHERE account_id = ? AND symbol = ?', { accountId, symbol })
    else
        MySQL.query('INSERT INTO nz_trading_positions (account_id, symbol, qty, avg_price) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE qty = VALUES(qty), avg_price = VALUES(avg_price)',
            { accountId, symbol, pos.qty, pos.avg })
    end
end

function DB.ClearPositions(accountId)
    MySQL.query('DELETE FROM nz_trading_positions WHERE account_id = ?', { accountId })
end

function DB.InsertOrder(o)
    MySQL.insert('INSERT INTO nz_trading_orders (id, account_id, symbol, side, type, qty, limit_price, stop_price, trail, tif, tp, sl, oco, reduce, status, fill_price, reason, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { o.id, o.acc, o.sym, o.side, o.type, o.qty, o.limit, o.stop, o.trail, o.tif, o.tp, o.sl, o.oco, o.reduce and 1 or 0, o.status, o.fillPrice, o.reason, o.created, o.updated })
end

function DB.UpdateOrder(o)
    MySQL.update('UPDATE nz_trading_orders SET status = ?, stop_price = ?, fill_price = ?, qty = ?, reason = ?, updated = ? WHERE id = ?',
        { o.status, o.stop, o.fillPrice, o.qty, o.reason, o.updated, o.id })
end

function DB.InsertFill(f)
    MySQL.insert('INSERT INTO nz_trading_fills (account_id, order_id, symbol, side, qty, price, fee, realized, time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { f.acc, f.order, f.sym, f.side, f.qty, f.price, f.fee, f.realized, f.time })
end

function DB.History(accountId)
    local orders = MySQL.query.await('SELECT * FROM nz_trading_orders WHERE account_id = ? AND status <> ? ORDER BY id DESC LIMIT 120', { accountId, 'working' }) or {}
    local fills = MySQL.query.await('SELECT * FROM nz_trading_fills WHERE account_id = ? ORDER BY id DESC LIMIT 250', { accountId }) or {}
    local ledger = MySQL.query.await('SELECT * FROM nz_trading_ledger WHERE account_id = ? ORDER BY id DESC LIMIT 50', { accountId }) or {}
    return orders, fills, ledger
end

function DB.InsertLedger(accountId, kind, amount)
    MySQL.insert('INSERT INTO nz_trading_ledger (account_id, type, amount, time) VALUES (?, ?, ?, ?)', { accountId, kind, amount, os.time() })
end

-- ── alerts ──────────────────────────────────────────────────────

function DB.GetAlerts(owner)
    return MySQL.query.await('SELECT * FROM nz_trading_alerts WHERE owner = ?', { owner }) or {}
end

function DB.InsertAlert(owner, symbol, cond, price)
    return MySQL.insert.await('INSERT INTO nz_trading_alerts (owner, symbol, cond, price) VALUES (?, ?, ?, ?)', { owner, symbol, cond, price })
end

function DB.DeleteAlert(id)
    MySQL.query('DELETE FROM nz_trading_alerts WHERE id = ?', { id })
end

-- ── market ──────────────────────────────────────────────────────

function DB.GetMarket()
    return MySQL.query.await('SELECT * FROM nz_trading_market') or {}
end

function DB.SaveMarket(rows)
    if #rows == 0 then return end
    MySQL.prepare('INSERT INTO nz_trading_market (symbol, price, prev_close, anchor, day_key) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE price = VALUES(price), prev_close = VALUES(prev_close), anchor = VALUES(anchor), day_key = VALUES(day_key)', rows)
end

-- ── props ───────────────────────────────────────────────────────

function DB.GetProps()
    return MySQL.query.await('SELECT * FROM nz_trading_props') or {}
end

function DB.InsertProp(owner, x, y, z, h)
    return MySQL.insert.await('INSERT INTO nz_trading_props (owner, x, y, z, heading) VALUES (?, ?, ?, ?, ?)', { owner, x, y, z, h })
end

function DB.DeleteProp(id)
    MySQL.query('DELETE FROM nz_trading_props WHERE id = ?', { id })
end
