if not NAYZEEE_LOCK_OK then return end

DB = { ready = false }

local schema = {
    [[CREATE TABLE IF NOT EXISTS `multichar_characters` (
        `charid`      VARCHAR(64)  NOT NULL,
        `owner`       VARCHAR(64)  NOT NULL,
        `theme`       VARCHAR(32)  NULL,
        `mood`        VARCHAR(32)  NULL,
        `pose`        VARCHAR(32)  NULL,
        `couple_pose` VARCHAR(32)  NULL,
        `weapon`      VARCHAR(64)  NULL,
        `pet`         VARCHAR(32)  NULL,
        `pet_name`    VARCHAR(24)  NULL,
        `nationality` VARCHAR(48)  NULL,
        `backstory`   VARCHAR(600) NULL,
        `favorite`    TINYINT(1)   NOT NULL DEFAULT 0,
        `disabled`    TINYINT(1)   NOT NULL DEFAULT 0,
        `created_at`  INT UNSIGNED NULL,
        `last_played` INT UNSIGNED NULL,
        `playtime`    INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (`charid`), KEY `owner` (`owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `multichar_slots` (
        `owner` VARCHAR(64) NOT NULL, `extra` INT NOT NULL DEFAULT 0, PRIMARY KEY (`owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `multichar_squads` (
        `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `sender`         VARCHAR(64) NOT NULL,
        `target`         VARCHAR(64) NOT NULL,
        `type`           ENUM('squad','couple') NOT NULL DEFAULT 'squad',
        `status`         ENUM('pending','accepted') NOT NULL DEFAULT 'pending',
        `pending_type`   ENUM('squad','couple') NULL,
        `pending_by`     VARCHAR(64) NULL,
        `sender_slot`    TINYINT UNSIGNED NULL,
        `target_slot`    TINYINT UNSIGNED NULL,
        `sender_visible` TINYINT(1) NOT NULL DEFAULT 1,
        `target_visible` TINYINT(1) NOT NULL DEFAULT 1,
        `created_at`     INT UNSIGNED NOT NULL,
        `updated_at`     INT UNSIGNED NOT NULL,
        PRIMARY KEY (`id`), UNIQUE KEY `pair` (`sender`,`target`), KEY `target` (`target`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `multichar_codes` (
        `code` VARCHAR(64) NOT NULL, `slots` INT NOT NULL DEFAULT 1, `uses` INT NOT NULL DEFAULT 1,
        `used` INT NOT NULL DEFAULT 0, `created_at` INT UNSIGNED NULL, PRIMARY KEY (`code`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    -- who redeemed which code (one redemption per owner per code)
    [[CREATE TABLE IF NOT EXISTS `multichar_redeemed` (
        `code` VARCHAR(64) NOT NULL, `owner` VARCHAR(64) NOT NULL, `at` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`code`, `owner`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

local function tableExists(name)
    return MySQL.scalar.await('SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? LIMIT 1', { name }) ~= nil
end

local function isEmpty(name)
    return MySQL.scalar.await(('SELECT 1 FROM `%s` LIMIT 1'):format(name)) == nil
end

-- One-time import from v1 tables (only into empty v2 tables, so deleted rows never come back)
local function migrate()
    local steps = {
        { from = 'nayzeee_multichar', to = 'multichar_characters', sql = [[INSERT IGNORE INTO `multichar_characters`
            (charid, owner, pose, nationality, backstory, favorite, disabled, created_at, last_played, playtime)
            SELECT LEFT(charid, 64), LEFT(owner, 64), pose, nationality, LEFT(backstory, 600), favorite, disabled, created_at, last_played, playtime
            FROM `nayzeee_multichar`]] },
        { from = 'nayzeee_multichar_slots', to = 'multichar_slots', sql = [[INSERT IGNORE INTO `multichar_slots` (owner, extra)
            SELECT LEFT(owner, 64), extra FROM `nayzeee_multichar_slots`]] },
        { from = 'nayzeee_multichar_redeem', to = 'multichar_codes', sql = [[INSERT IGNORE INTO `multichar_codes` (code, slots, uses, used, created_at)
            SELECT LEFT(tid, 64), slots, 1, 1, redeemed_at FROM `nayzeee_multichar_redeem`]] },
    }
    for _, st in ipairs(steps) do
        local ok, err = pcall(function()
            if tableExists(st.from) and isEmpty(st.to) then
                local n = MySQL.update.await(st.sql)
                print(('^2[nzm] imported %s row(s) from %s into %s^0'):format(n or 0, st.from, st.to))
            end
        end)
        if not ok then print(('^1[nzm] migration %s failed: %s^0'):format(st.from, err)) end
    end
end

MySQL.ready(function()
    for i = 1, #schema do
        local ok, err = pcall(MySQL.query.await, schema[i])
        if not ok then print(('^1[nzm] table setup failed: %s^0'):format(err)) end
    end
    migrate()
    DB.ready = true
end)

function DB.Wait()
    while not DB.ready do Wait(50) end
end

-- ── character meta / prefs ────────────────────────────────────────────────
-- meta for a list of char ids -> map[charid] = row
function DB.Prefs(ids)
    if #ids == 0 then return {} end
    local rows = MySQL.query.await(('SELECT * FROM `multichar_characters` WHERE charid IN (%s)'):format(('?,'):rep(#ids):sub(1, -2)), ids) or {}
    local map = {}
    for i = 1, #rows do map[rows[i].charid] = rows[i] end
    return map
end

function DB.Get(charid)
    return MySQL.single.await('SELECT * FROM `multichar_characters` WHERE charid = ?', { charid })
end

function DB.Ensure(charid, owner)
    MySQL.insert.await('INSERT IGNORE INTO `multichar_characters` (charid, owner, created_at) VALUES (?, ?, ?)', { charid, owner, os.time() })
end

-- pref key (contract name) -> column
local columns = {
    theme = 'theme', mood = 'mood', pose = 'pose', couplePose = 'couple_pose', weapon = 'weapon',
    pet = 'pet', petName = 'pet_name', nationality = 'nationality', backstory = 'backstory',
    favorite = 'favorite', disabled = 'disabled', lastPlayed = 'last_played',
}

function DB.Set(charid, key, value)
    local col = columns[key]
    if not col then return false end
    if type(value) == 'boolean' then value = value and 1 or 0 end
    MySQL.update.await(('UPDATE `multichar_characters` SET `%s` = ? WHERE charid = ?'):format(col), { value, charid })
    return true
end

-- Only one favourite per owner
function DB.SetFavorite(owner, charid, on)
    MySQL.update.await('UPDATE `multichar_characters` SET favorite = 0 WHERE owner = ?', { owner })
    if on then MySQL.update.await('UPDATE `multichar_characters` SET favorite = 1 WHERE charid = ?', { charid }) end
end

function DB.AddPlaytime(charid, seconds)
    if not charid or seconds <= 0 then return end
    MySQL.update('UPDATE `multichar_characters` SET playtime = playtime + ? WHERE charid = ?', { seconds, charid })
end

function DB.Delete(charid)
    MySQL.update.await('DELETE FROM `multichar_characters` WHERE charid = ?', { charid })
end

-- ── slots ─────────────────────────────────────────────────────────────────
function DB.Extra(owner)
    return tonumber(MySQL.scalar.await('SELECT extra FROM `multichar_slots` WHERE owner = ?', { owner })) or 0
end

function DB.SetExtra(owner, extra)
    MySQL.insert.await('INSERT INTO `multichar_slots` (owner, extra) VALUES (?, ?) ON DUPLICATE KEY UPDATE extra = VALUES(extra)', { owner, math.max(0, extra) })
end

-- Atomic add (redeem / exports), never below 0
function DB.AddExtra(owner, amount)
    MySQL.insert.await('INSERT INTO `multichar_slots` (owner, extra) VALUES (?, GREATEST(?, 0)) ON DUPLICATE KEY UPDATE extra = GREATEST(extra + ?, 0)', { owner, amount, amount })
    return DB.Extra(owner)
end
