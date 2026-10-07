-- Database: tables are created automatically on start

DB = {}

local schema = {
    [[CREATE TABLE IF NOT EXISTS `nz_wig_players` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `nz_wig_feed` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `nz_wig_bounties` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `nz_wig_catalog` (
        `identifier` VARCHAR(64) NOT NULL,
        `style` VARCHAR(48) NOT NULL,
        `tier` VARCHAR(16) NOT NULL,
        `times` INT NOT NULL DEFAULT 1,
        `first_at` INT NOT NULL,
        PRIMARY KEY (`identifier`, `style`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
}

function DB.Init()
    for _, q in ipairs(schema) do MySQL.query.await(q) end
    -- keep the feed small
    MySQL.query.await('DELETE FROM nz_wig_feed WHERE created < ?', { os.time() - 86400 * 14 })
    Debug('database ready')
end

-- Columns the server is allowed to write through DB.SavePlayer
local SAVE_COLS = {
    'name', 'xp', 'snatches', 'defends', 'fails', 'snatched', 'streak', 'best_streak',
    'buzzes', 'cuts', 'revenges', 'wigs_sold', 'earned', 'bounties_claimed', 'bounty_earned',
    'best_tier', 'catalog_rewards', 'glue_until', 'passive', 'passive_at', 'first_seen', 'last_seen',
}
local SAVE_SQL do
    local sets = {}
    for i, c in ipairs(SAVE_COLS) do sets[i] = ('`%s` = ?'):format(c) end
    SAVE_SQL = ('UPDATE nz_wig_players SET %s, `hair` = ? WHERE identifier = ?'):format(table.concat(sets, ', '))
end

function DB.LoadPlayer(identifier, name)
    local now = os.time()
    MySQL.insert.await([[INSERT INTO nz_wig_players (identifier, name, first_seen, last_seen) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), last_seen = VALUES(last_seen)]], { identifier, name, now, now })
    local row = MySQL.single.await('SELECT * FROM nz_wig_players WHERE identifier = ?', { identifier })
    if row and row.hair then row.hair = json.decode(row.hair) end
    return row
end

function DB.SavePlayer(row)
    local params = {}
    local n = #SAVE_COLS
    for i = 1, n do
        local v = row[SAVE_COLS[i]]
        if v == nil then v = '' end
        if type(v) == 'boolean' then v = v and 1 or 0 end
        params[i] = v
    end
    params[n + 1] = json.encode(row.hair or {})
    params[n + 2] = row.identifier
    MySQL.prepare(SAVE_SQL, params)
end

function DB.AddFeed(kind, actor, actorName, target, targetName, tier, label, amount)
    local now = os.time()
    MySQL.insert('INSERT INTO nz_wig_feed (kind, actor, actor_name, target, target_name, tier, label, amount, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { kind, actor, actorName, target, targetName, tier, label, amount or 0, now })
end

function DB.RecentFeed(limit)
    return MySQL.query.await('SELECT kind, actor_name, target_name, tier, label, amount, created FROM nz_wig_feed ORDER BY id DESC LIMIT ?', { limit })
end

-- people who snatched this identifier within the window
function DB.RecentSnatchers(identifier, since)
    return MySQL.query.await([[SELECT actor AS identifier, actor_name AS name, MAX(created) AS last, COUNT(*) AS times
        FROM nz_wig_feed WHERE target = ? AND kind IN ('snatch','buzz') AND created >= ? AND actor IS NOT NULL
        GROUP BY actor, actor_name ORDER BY last DESC LIMIT 10]], { identifier, since })
end

function DB.HasSnatched(actor, target, since)
    local n = MySQL.scalar.await([[SELECT COUNT(*) FROM nz_wig_feed WHERE actor = ? AND target = ? AND kind IN ('snatch','buzz') AND created >= ?]],
        { actor, target, since })
    return (n or 0) > 0
end

function DB.Catalog(identifier)
    return MySQL.query.await('SELECT style, tier, times, first_at FROM nz_wig_catalog WHERE identifier = ?', { identifier })
end

-- returns true when this style is new for the player
function DB.CatalogAdd(identifier, style, tier)
    local row = MySQL.single.await('SELECT tier FROM nz_wig_catalog WHERE identifier = ? AND style = ?', { identifier, style })
    if not row then
        MySQL.insert.await('INSERT INTO nz_wig_catalog (identifier, style, tier, times, first_at) VALUES (?, ?, ?, 1, ?)',
            { identifier, style, tier, os.time() })
        return true
    end
    local better = (TierIndex[tier] or 1) > (TierIndex[row.tier] or 1)
    MySQL.update('UPDATE nz_wig_catalog SET times = times + 1' .. (better and ', tier = ?' or '') .. ' WHERE identifier = ? AND style = ?',
        better and { tier, identifier, style } or { identifier, style })
    return false
end

function DB.CatalogCount(identifier)
    return MySQL.scalar.await('SELECT COUNT(*) FROM nz_wig_catalog WHERE identifier = ?', { identifier }) or 0
end

local LB_COLS = { snatches = true, defends = true, best_streak = true, earned = true, xp = true, bounty_earned = true }
function DB.Leaderboard(col, limit)
    if not LB_COLS[col] then return {} end
    return MySQL.query.await(('SELECT identifier, name, xp, %s AS value FROM nz_wig_players WHERE %s > 0 ORDER BY %s DESC LIMIT ?'):format(col, col, col), { limit })
end
