--[[ Database: tables are created automatically on first start ]]

DB = {}

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nzh_profiles` (
            `identifier` VARCHAR(64) NOT NULL,
            `nickname` VARCHAR(24) DEFAULT NULL,
            `avatar` TINYINT UNSIGNED NOT NULL DEFAULT 1,
            `xp` INT UNSIGNED NOT NULL DEFAULT 0,
            `completed` INT UNSIGNED NOT NULL DEFAULT 0,
            `failed` INT UNSIGNED NOT NULL DEFAULT 0,
            `earned` BIGINT UNSIGNED NOT NULL DEFAULT 0,
            `stats` LONGTEXT DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`),
            KEY `xp_idx` (`xp`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nzh_history` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `heist` VARCHAR(32) NOT NULL,
            `location` VARCHAR(64) DEFAULT NULL,
            `crew` LONGTEXT NOT NULL,
            `success` TINYINT(1) NOT NULL DEFAULT 0,
            `payout` INT UNSIGNED NOT NULL DEFAULT 0,
            `duration` INT UNSIGNED NOT NULL DEFAULT 0,
            `reason` VARCHAR(64) DEFAULT NULL,
            `finished_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `finished_idx` (`finished_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    DB.ready = true
end)

function DB.getProfile(identifier)
    return MySQL.single.await('SELECT * FROM nzh_profiles WHERE identifier = ?', { identifier })
end

function DB.createProfile(identifier, nickname)
    MySQL.insert.await('INSERT IGNORE INTO nzh_profiles (identifier, nickname, stats) VALUES (?, ?, ?)', { identifier, nickname, '{}' })
end

function DB.saveProfile(p)
    MySQL.update('UPDATE nzh_profiles SET nickname = ?, avatar = ?, xp = ?, completed = ?, failed = ?, earned = ?, stats = ? WHERE identifier = ?', {
        p.nickname, p.avatar, p.xp, p.completed, p.failed, p.earned, json.encode(p.stats or {}), p.identifier,
    })
end

function DB.nicknameTaken(nickname, identifier)
    return MySQL.scalar.await('SELECT 1 FROM nzh_profiles WHERE nickname = ? AND identifier <> ? LIMIT 1', { nickname, identifier }) ~= nil
end

function DB.leaderboard(limit)
    return MySQL.query.await('SELECT nickname, avatar, xp, completed, earned FROM nzh_profiles ORDER BY xp DESC LIMIT ?', { limit or 15 }) or {}
end

function DB.addHistory(row)
    MySQL.insert('INSERT INTO nzh_history (heist, location, crew, success, payout, duration, reason) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        row.heist, row.location, json.encode(row.crew), row.success and 1 or 0, row.payout or 0, row.duration or 0, row.reason,
    })
end

function DB.history(identifier, limit)
    return MySQL.query.await(
        "SELECT heist, location, success, payout, duration, reason, UNIX_TIMESTAMP(finished_at) AS ts FROM nzh_history WHERE crew LIKE ? ORDER BY id DESC LIMIT ?",
        { '%"' .. identifier .. '"%', limit or 15 }) or {}
end
