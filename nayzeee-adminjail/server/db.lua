DB = {}

local ACTIVE = Config.Database.active
local HISTORY = Config.Database.history

local function createTables()
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `identifier`     VARCHAR(80)  NOT NULL PRIMARY KEY,
            `name`           VARCHAR(100) NULL,
            `account`        VARCHAR(100) NULL,
            `reason`         VARCHAR(255) NULL,
            `admin`          VARCHAR(100) NULL,
            `location`       VARCHAR(50)  NOT NULL,
            `total`          INT          NOT NULL,
            `remaining`      INT          NOT NULL,
            `escapes`        INT          NOT NULL DEFAULT 0,
            `cycles`         INT          NOT NULL DEFAULT 0,
            `reduced`        INT          NOT NULL DEFAULT 0,
            `hour_start`     INT          NOT NULL DEFAULT 0,
            `hour_reduced`   INT          NOT NULL DEFAULT 0,
            `return_coords`  VARCHAR(100) NULL,
            `jailed_at`      INT          NOT NULL,
            `updated_at`     INT          NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(ACTIVE))

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id`           INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `identifier`   VARCHAR(80)  NOT NULL,
            `name`         VARCHAR(100) NULL,
            `account`      VARCHAR(100) NULL,
            `reason`       VARCHAR(255) NULL,
            `admin`        VARCHAR(100) NULL,
            `location`     VARCHAR(50)  NULL,
            `total`        INT          NOT NULL DEFAULT 0,
            `served`       INT          NOT NULL DEFAULT 0,
            `escapes`      INT          NOT NULL DEFAULT 0,
            `cycles`       INT          NOT NULL DEFAULT 0,
            `reduced`      INT          NOT NULL DEFAULT 0,
            `outcome`      VARCHAR(20)  NOT NULL,
            `released_by`  VARCHAR(100) NULL,
            `jailed_at`    INT          NOT NULL,
            `released_at`  INT          NOT NULL,
            INDEX `idx_identifier` (`identifier`),
            INDEX `idx_name` (`name`),
            INDEX `idx_admin` (`admin`),
            INDEX `idx_jailed_at` (`jailed_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(HISTORY))
end

local function tableExists(name)
    return MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?',
        { name }
    ) > 0
end

--- One-time import of v1 data (minutes -> seconds, old column names).
local function importLegacy()
    if not Config.Database.legacyImport then return end
    if not tableExists('nayzeee_adminjail') then return end

    local already = MySQL.scalar.await(('SELECT COUNT(*) FROM `%s`'):format(ACTIVE)) > 0
        or MySQL.scalar.await(('SELECT COUNT(*) FROM `%s`'):format(HISTORY)) > 0
    if already then return end

    local imported = MySQL.update.await(([[
        INSERT IGNORE INTO `%s` (identifier, name, reason, admin, location, total, remaining, escapes, cycles, reduced, jailed_at, updated_at)
        SELECT identifier, player_name, LEFT(reason, 255), admin_name, COALESCE(location_id, ?), jail_time * 60, jail_time * 60,
               escape_attempts, work_completed, time_reduced * 60, jailed_at, updated_at
        FROM `nayzeee_adminjail`
    ]]):format(ACTIVE), { AJ.DefaultLocation().id }) or 0

    local history = 0
    if tableExists('nayzeee_adminjail_history') then
        history = MySQL.update.await(([[
            INSERT INTO `%s` (identifier, name, reason, admin, location, total, served, escapes, cycles, reduced, outcome, jailed_at, released_at)
            SELECT identifier, player_name, LEFT(reason, 255), admin_name, location_id, jail_time * 60, jail_time * 60,
                   escape_attempts, work_completed, time_reduced * 60,
                   CASE WHEN release_type = 'Time Served' THEN 'served' ELSE 'released' END,
                   jailed_at, released_at
            FROM `nayzeee_adminjail_history`
        ]]):format(HISTORY)) or 0
    end

    print(('^2[%s]^7 Imported ^5%d^7 active sentences and ^5%d^7 history records from v1'):format(AJ.Resource, imported, history))
end

function DB.Init()
    createTables()
    local ok, err = pcall(importLegacy)
    if not ok then print(('^3[%s]^7 Legacy import skipped: %s'):format(AJ.Resource, err)) end
end

function DB.LoadActive()
    return MySQL.query.await(('SELECT * FROM `%s`'):format(ACTIVE)) or {}
end

local UPSERT = ([[
    INSERT INTO `%s` (identifier, name, account, reason, admin, location, total, remaining, escapes, cycles, reduced,
                      hour_start, hour_reduced, return_coords, jailed_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE name = VALUES(name), account = VALUES(account), location = VALUES(location),
        total = VALUES(total), remaining = VALUES(remaining), escapes = VALUES(escapes), cycles = VALUES(cycles),
        reduced = VALUES(reduced), hour_start = VALUES(hour_start), hour_reduced = VALUES(hour_reduced),
        updated_at = VALUES(updated_at)
]]):format(ACTIVE)

local function upsertParams(e)
    return {
        e.identifier, e.name, e.account, e.reason, e.admin, e.location, e.total, e.remaining,
        e.escapes, e.cycles, e.reduced, e.hourStart, e.hourReduced,
        e.returnCoords and json.encode(e.returnCoords) or nil, e.jailedAt, os.time(),
    }
end

--- Expects `remaining` to already be stamped.
function DB.Save(e)
    MySQL.prepare(UPSERT, upsertParams(e))
end

function DB.SaveMany(list)
    if #list == 0 then return end
    local params = {}
    for i = 1, #list do params[i] = upsertParams(list[i]) end
    MySQL.prepare(UPSERT, params)
end

function DB.Archive(e, outcome, releasedBy)
    MySQL.insert(([[
        INSERT INTO `%s` (identifier, name, account, reason, admin, location, total, served, escapes, cycles, reduced,
                          outcome, released_by, jailed_at, released_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]):format(HISTORY), {
        e.identifier, e.name, e.account, e.reason, e.admin, e.location, e.total,
        math.max(0, e.total - e.remaining), e.escapes, e.cycles, e.reduced,
        outcome, releasedBy, e.jailedAt, os.time(),
    })
    MySQL.query(('DELETE FROM `%s` WHERE identifier = ?'):format(ACTIVE), { e.identifier })
end

function DB.History(filter, page)
    local where, params = '', {}
    local query = filter and filter.query
    if query and query ~= '' then
        local like = '%' .. query:sub(1, 60) .. '%'
        if filter.field == 'player' then
            where, params = 'WHERE name LIKE ? OR account LIKE ? OR identifier = ?', { like, like, query }
        elseif filter.field == 'admin' then
            where, params = 'WHERE admin LIKE ?', { like }
        else
            where, params = 'WHERE name LIKE ? OR account LIKE ? OR admin LIKE ? OR reason LIKE ?', { like, like, like, like }
        end
    end
    local limit = 25
    params[#params + 1] = limit + 1
    params[#params + 1] = math.max(0, (tonumber(page) or 0)) * limit

    local rows = MySQL.query.await(
        ('SELECT * FROM `%s` %s ORDER BY id DESC LIMIT ? OFFSET ?'):format(HISTORY, where), params
    ) or {}
    local more = #rows > limit
    if more then rows[#rows] = nil end
    return rows, more
end

--- Prior sentence counts for a list of identifiers -> { [identifier] = count }
function DB.Priors(identifiers)
    local out = {}
    if #identifiers == 0 then return out end
    local marks = string.rep('?,', #identifiers):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT identifier, COUNT(*) AS c FROM `%s` WHERE identifier IN (%s) GROUP BY identifier'):format(HISTORY, marks),
        identifiers
    ) or {}
    for i = 1, #rows do out[rows[i].identifier] = rows[i].c end
    return out
end

function DB.TodayStats(since)
    local row = MySQL.single.await(
        ('SELECT COUNT(*) AS sentenced, COALESCE(SUM(escapes), 0) AS escapes FROM `%s` WHERE jailed_at >= ?'):format(HISTORY),
        { since }
    )
    return row or { sentenced = 0, escapes = 0 }
end

function DB.Recent(limit)
    return MySQL.query.await(('SELECT * FROM `%s` ORDER BY id DESC LIMIT ?'):format(HISTORY), { limit }) or {}
end
