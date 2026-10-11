if not NAYZEEE_LOCK_OK then return end

DB = { ready = false }

local schema = {
    [[CREATE TABLE IF NOT EXISTS `nayzeee_multichar` (
        `charid`       VARCHAR(80)  NOT NULL,
        `owner`        VARCHAR(80)  NOT NULL,
        `playtime`     INT UNSIGNED NOT NULL DEFAULT 0,
        `last_played`  INT UNSIGNED NULL DEFAULT NULL,
        `created_at`   INT UNSIGNED NULL DEFAULT NULL,
        `nationality`  VARCHAR(48)  NULL DEFAULT NULL,
        `height`       SMALLINT UNSIGNED NULL DEFAULT NULL,
        `backstory`    TEXT         NULL DEFAULT NULL,
        `pose`         VARCHAR(32)  NULL DEFAULT NULL,
        `favorite`     TINYINT(1)   NOT NULL DEFAULT 0,
        `disabled`     TINYINT(1)   NOT NULL DEFAULT 0,
        `partner`      VARCHAR(80)  NULL DEFAULT NULL,
        `partner_type` VARCHAR(12)  NULL DEFAULT NULL,
        PRIMARY KEY (`charid`),
        INDEX `owner` (`owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nayzeee_multichar_slots` (
        `owner` VARCHAR(80) NOT NULL,
        `extra` TINYINT NOT NULL DEFAULT 0,
        `note`  VARCHAR(128) NULL DEFAULT NULL,
        PRIMARY KEY (`owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nayzeee_multichar_redeem` (
        `tid`        VARCHAR(80) NOT NULL,
        `owner`      VARCHAR(80) NOT NULL,
        `slots`      TINYINT     NOT NULL DEFAULT 0,
        `redeemed_at` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`tid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

MySQL.ready(function()
    for i = 1, #schema do
        local ok, err = pcall(MySQL.query.await, schema[i])
        if not ok then print(('^1[nzm] table setup failed: %s^0'):format(err)) end
    end
    DB.ready = true
end)

function DB.Wait()
    while not DB.ready do Wait(50) end
end

-- meta for a list of char ids -> map[charid] = row
function DB.Meta(ids)
    if #ids == 0 then return {} end
    local rows = MySQL.query.await(('SELECT * FROM `nayzeee_multichar` WHERE charid IN (%s)'):format(('?,'):rep(#ids):sub(1, -2)), ids) or {}
    local map = {}
    for i = 1, #rows do map[rows[i].charid] = rows[i] end
    return map
end

function DB.Ensure(charid, owner)
    MySQL.insert.await('INSERT IGNORE INTO `nayzeee_multichar` (charid, owner, created_at) VALUES (?, ?, ?)', { charid, owner, os.time() })
end

local allowed = { pose = true, favorite = true, backstory = true, disabled = true, partner = true, partner_type = true, nationality = true, height = true, last_played = true }

function DB.Set(charid, key, value)
    if not allowed[key] then return end
    MySQL.update.await(('UPDATE `nayzeee_multichar` SET `%s` = ? WHERE charid = ?'):format(key), { value, charid })
end

function DB.AddPlaytime(charid, seconds)
    if seconds <= 0 then return end
    MySQL.update('UPDATE `nayzeee_multichar` SET playtime = playtime + ? WHERE charid = ?', { seconds, charid })
end

function DB.Delete(charid)
    MySQL.update.await('DELETE FROM `nayzeee_multichar` WHERE charid = ?', { charid })
    MySQL.update.await('UPDATE `nayzeee_multichar` SET partner = NULL, partner_type = NULL WHERE partner = ?', { charid })
end

function DB.Extra(owner)
    return tonumber(MySQL.scalar.await('SELECT extra FROM `nayzeee_multichar_slots` WHERE owner = ?', { owner })) or 0
end

function DB.SetExtra(owner, extra, note)
    MySQL.insert.await('INSERT INTO `nayzeee_multichar_slots` (owner, extra, note) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE extra = VALUES(extra), note = COALESCE(VALUES(note), note)', { owner, extra, note })
end
