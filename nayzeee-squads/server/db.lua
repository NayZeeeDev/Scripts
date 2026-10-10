-- Persistence layer. Every function is a safe no-op when persistence is off.
DB = {}

-- temporary squads live above this offset so their ids can never collide with database ids
DB.TEMP_BASE = 1000000

local ON = Config.Persistence == true
local ready = false

function DB.On() return ON and ready end
local function temp(id) return id >= DB.TEMP_BASE end

-- ─── schema ────────────────────────────────────────────────
-- Created and upgraded on start. Each statement is safe to run on every boot.
local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `nz_squads` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `name` VARCHAR(32) NOT NULL,
        `tag` VARCHAR(8) DEFAULT NULL,
        `image` VARCHAR(300) DEFAULT NULL,
        `description` VARCHAR(160) DEFAULT NULL,
        `motd` VARCHAR(255) DEFAULT NULL,
        `blip_color` SMALLINT UNSIGNED NOT NULL DEFAULT 2,
        `blip_sprite` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
        `password` VARCHAR(64) DEFAULT NULL,
        `invite_only` TINYINT(1) NOT NULL DEFAULT 0,
        `member_limit` TINYINT UNSIGNED NOT NULL DEFAULT 8,
        `owner` VARCHAR(64) NOT NULL,
        `ranks` TEXT DEFAULT NULL,
        `elo` SMALLINT UNSIGNED NOT NULL DEFAULT 1000,
        `wins` INT UNSIGNED NOT NULL DEFAULT 0,
        `losses` INT UNSIGNED NOT NULL DEFAULT 0,
        `draws` INT UNSIGNED NOT NULL DEFAULT 0,
        `kills` INT UNSIGNED NOT NULL DEFAULT 0,
        `deaths` INT UNSIGNED NOT NULL DEFAULT 0,
        `assists` INT UNSIGNED NOT NULL DEFAULT 0,
        `created` INT UNSIGNED NOT NULL,
        `last_active` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uq_name` (`name`),
        UNIQUE KEY `uq_tag` (`tag`),
        KEY `idx_elo` (`elo`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_squad_members` (
        `squad_id` INT UNSIGNED NOT NULL,
        `identifier` VARCHAR(64) NOT NULL,
        `name` VARCHAR(64) NOT NULL,
        `nick` VARCHAR(24) DEFAULT NULL,
        `rank` TINYINT UNSIGNED NOT NULL DEFAULT 1,
        `kills` INT UNSIGNED NOT NULL DEFAULT 0,
        `deaths` INT UNSIGNED NOT NULL DEFAULT 0,
        `assists` INT UNSIGNED NOT NULL DEFAULT 0,
        `revives` INT UNSIGNED NOT NULL DEFAULT 0,
        `playtime` INT UNSIGNED NOT NULL DEFAULT 0,
        `joined` INT UNSIGNED NOT NULL,
        `last_seen` INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (`squad_id`, `identifier`),
        KEY `idx_identifier` (`identifier`),
        CONSTRAINT `fk_nz_member_squad` FOREIGN KEY (`squad_id`) REFERENCES `nz_squads` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_squad_allies` (
        `squad_id` INT UNSIGNED NOT NULL,
        `ally_id` INT UNSIGNED NOT NULL,
        `created` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`squad_id`, `ally_id`),
        KEY `idx_ally` (`ally_id`),
        CONSTRAINT `fk_nz_ally_squad` FOREIGN KEY (`squad_id`) REFERENCES `nz_squads` (`id`) ON DELETE CASCADE,
        CONSTRAINT `fk_nz_ally_other` FOREIGN KEY (`ally_id`) REFERENCES `nz_squads` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_squad_matches` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `squad_a` INT UNSIGNED NOT NULL,
        `squad_b` INT UNSIGNED NOT NULL,
        `name_a` VARCHAR(32) NOT NULL,
        `name_b` VARCHAR(32) NOT NULL,
        `kills_a` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        `kills_b` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        `delta_a` SMALLINT NOT NULL DEFAULT 0,
        `delta_b` SMALLINT NOT NULL DEFAULT 0,
        `winner` INT UNSIGNED DEFAULT NULL,
        `ended` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`id`),
        KEY `idx_a` (`squad_a`),
        KEY `idx_b` (`squad_b`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `nz_squad_log` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `squad_id` INT UNSIGNED NOT NULL,
        `kind` VARCHAR(16) NOT NULL,
        `text` VARCHAR(200) NOT NULL,
        `at` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`id`),
        KEY `idx_squad` (`squad_id`, `id`),
        CONSTRAINT `fk_nz_log_squad` FOREIGN KEY (`squad_id`) REFERENCES `nz_squads` (`id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Columns added after the first release. Missing ones are added in place on boot.
local COLUMNS = {
    { 'nz_squads',        'blip_color',  'SMALLINT UNSIGNED NOT NULL DEFAULT 2 AFTER `image`' },
    { 'nz_squads',        'blip_sprite', 'SMALLINT UNSIGNED NOT NULL DEFAULT 1 AFTER `blip_color`' },
    { 'nz_squads',        'draws',       'INT UNSIGNED NOT NULL DEFAULT 0 AFTER `losses`' },
    { 'nz_squads',        'description', 'VARCHAR(160) DEFAULT NULL AFTER `image`' },
    { 'nz_squads',        'motd',        'VARCHAR(255) DEFAULT NULL AFTER `description`' },
    { 'nz_squad_members', 'nick',        'VARCHAR(24) DEFAULT NULL AFTER `name`' },
    { 'nz_squad_members', 'playtime',    'INT UNSIGNED NOT NULL DEFAULT 0 AFTER `revives`' },
    { 'nz_squad_members', 'last_seen',   'INT UNSIGNED NOT NULL DEFAULT 0 AFTER `joined`' },
}

local function migrate()
    for i = 1, #SCHEMA do MySQL.query.await(SCHEMA[i]) end

    local added = 0
    for i = 1, #COLUMNS do
        local tbl, col, def = COLUMNS[i][1], COLUMNS[i][2], COLUMNS[i][3]
        local exists = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { tbl, col })
        if (tonumber(exists) or 0) == 0 then
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tbl, col, def))
            added = added + 1
        end
    end
    if added > 0 then
        print(('^2[nayzeee-squads]^7 Database upgraded: added %d column(s).'):format(added))
    end
end

--- Why permanent squads are unavailable, or nil when they work.
local reason = nil
function DB.Unavailable() return reason end

function DB.Init()
    if not ON then
        reason = 'Squads are not saved on this server'
        print('^3[nayzeee-squads]^7 Config.Persistence is false: every squad is temporary and no stats are kept.')
        return
    end
    local waited = 0
    while GetResourceState('oxmysql') == 'starting' and waited < 10000 do
        Wait(250); waited = waited + 250
    end

    if GetResourceState('oxmysql') ~= 'started' then
        reason = 'The database is offline, so squads cannot be saved right now'
        print('^1[nayzeee-squads]^7 oxmysql is not started. Permanent squads are disabled until it is.')
        print('^1[nayzeee-squads]^7 Make sure "ensure oxmysql" comes BEFORE "ensure nayzeee-squads" in server.cfg.')
        ON = false
        return
    end

    local ok, err = pcall(migrate)
    if not ok then
        reason = 'The squad tables could not be set up, ask staff to check the server console'
        print('^1[nayzeee-squads]^7 Could not create or upgrade the database tables:')
        print('^1[nayzeee-squads]^7 ' .. tostring(err))
        ON = false
        return
    end

    ready = true
    print('^2[nayzeee-squads]^7 Database ready. Permanent squads are enabled.')
end

--- Loads every stored squad. Returns { [id] = squad }, highest id.
function DB.LoadAll()
    if not DB.On() then return {}, 0 end

    local rows    = MySQL.query.await('SELECT * FROM nz_squads') or {}
    local members = MySQL.query.await('SELECT * FROM nz_squad_members') or {}
    local allies  = MySQL.query.await('SELECT * FROM nz_squad_allies') or {}
    local logs    = MySQL.query.await('SELECT squad_id, kind, text, at FROM nz_squad_log ORDER BY id DESC LIMIT 3000') or {}
    local byId, maxId = {}, 0

    for i = 1, #rows do
        local r = rows[i]
        local ranks
        if r.ranks then
            local ok, decoded = pcall(json.decode, r.ranks)
            if ok and type(decoded) == 'table' and #decoded >= 2 then ranks = decoded end
        end
        byId[r.id] = {
            id = r.id, name = r.name, tag = r.tag, image = r.image, description = r.description, motd = r.motd,
            password = r.password, inviteOnly = r.invite_only == 1, limit = r.member_limit, owner = r.owner,
            temporary = false, blipColor = r.blip_color, blipSprite = r.blip_sprite, allies = {},
            ranks = ranks or Ranks.Default(), elo = r.elo,
            wins = r.wins, losses = r.losses, draws = r.draws,
            kills = r.kills, deaths = r.deaths, assists = r.assists,
            created = r.created, persistent = true,
            roster = {}, online = {}, chat = {}, invites = {}, requests = {}, log = {},
        }
        if r.id > maxId then maxId = r.id end
    end

    local count = 0
    for i = 1, #members do
        local m = members[i]
        local sq = byId[m.squad_id]
        if sq then
            sq.roster[m.identifier] = {
                name = m.name, nick = m.nick, rank = m.rank, kills = m.kills, deaths = m.deaths,
                assists = m.assists, revives = m.revives, playtime = m.playtime or 0,
                joined = m.joined, lastSeen = m.last_seen or m.joined,
            }
            count = count + 1
        end
    end

    for i = 1, #allies do
        local a = allies[i]
        if byId[a.squad_id] and byId[a.ally_id] then byId[a.squad_id].allies[a.ally_id] = a.created end
    end

    -- newest first in the query, so insert at the front to end up oldest -> newest
    for i = 1, #logs do
        local l = logs[i]
        local sq = byId[l.squad_id]
        if sq and #sq.log < 40 then
            table.insert(sq.log, 1, { kind = l.kind, text = l.text, at = l.at })
        end
    end

    print(('^2[nayzeee-squads]^7 Loaded %d squads, %d members and %d alliances.'):format(#rows, count, #allies))
    return byId, maxId
end

--- Returns the new squad id. Must be called from inside a coroutine (every callback is).
function DB.CreateSquad(sq)
    if not DB.On() then return nil end
    return MySQL.insert.await('INSERT INTO nz_squads (name, tag, image, description, motd, blip_color, blip_sprite, password, invite_only, member_limit, owner, ranks, elo, created, last_active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { sq.name, sq.tag, sq.image, sq.description, sq.motd, sq.blipColor, sq.blipSprite, sq.password, sq.inviteOnly and 1 or 0,
          sq.limit, sq.owner, json.encode(sq.ranks), sq.elo, sq.created, os.time() })
end

function DB.SaveSquad(sq)
    if not DB.On() or not sq.persistent then return end
    MySQL.update('UPDATE nz_squads SET name = ?, tag = ?, image = ?, description = ?, motd = ?, blip_color = ?, blip_sprite = ?, password = ?, invite_only = ?, member_limit = ?, owner = ?, ranks = ?, elo = ?, wins = ?, losses = ?, draws = ?, kills = ?, deaths = ?, assists = ?, last_active = ? WHERE id = ?',
        { sq.name, sq.tag, sq.image, sq.description, sq.motd, sq.blipColor, sq.blipSprite, sq.password, sq.inviteOnly and 1 or 0,
          sq.limit, sq.owner, json.encode(sq.ranks), sq.elo, sq.wins, sq.losses, sq.draws,
          sq.kills, sq.deaths, sq.assists, os.time(), sq.id })
end

function DB.SaveMember(squadId, identifier, m)
    if not DB.On() or temp(squadId) then return end
    MySQL.prepare('INSERT INTO nz_squad_members (squad_id, identifier, name, nick, rank, kills, deaths, assists, revives, playtime, joined, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), nick = VALUES(nick), rank = VALUES(rank), kills = VALUES(kills), deaths = VALUES(deaths), assists = VALUES(assists), revives = VALUES(revives), playtime = VALUES(playtime), last_seen = VALUES(last_seen)',
        { squadId, identifier, m.name, m.nick, m.rank or 1, m.kills or 0, m.deaths or 0, m.assists or 0, m.revives or 0,
          m.playtime or 0, m.joined or os.time(), m.lastSeen or os.time() })
end

function DB.RemoveMember(squadId, identifier)
    if not DB.On() or temp(squadId) then return end
    MySQL.prepare('DELETE FROM nz_squad_members WHERE squad_id = ? AND identifier = ?', { squadId, identifier })
end

function DB.DeleteSquad(id)
    if not DB.On() or temp(id) then return end
    MySQL.prepare('DELETE FROM nz_squads WHERE id = ?', { id })
end

function DB.AddAlly(a, b)
    if not DB.On() then return end
    MySQL.prepare('INSERT IGNORE INTO nz_squad_allies (squad_id, ally_id, created) VALUES (?, ?, ?), (?, ?, ?)',
        { a, b, os.time(), b, a, os.time() })
end

function DB.RemoveAlly(a, b)
    if not DB.On() then return end
    MySQL.prepare('DELETE FROM nz_squad_allies WHERE (squad_id = ? AND ally_id = ?) OR (squad_id = ? AND ally_id = ?)',
        { a, b, b, a })
end

function DB.SaveMatch(m)
    if not DB.On() then return end
    MySQL.prepare('INSERT INTO nz_squad_matches (squad_a, squad_b, name_a, name_b, kills_a, kills_b, delta_a, delta_b, winner, ended) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { m.a, m.b, m.nameA, m.nameB, m.killsA, m.killsB, m.deltaA, m.deltaB, m.winner, os.time() })
end

function DB.AddLog(squadId, kind, text, at)
    if not DB.On() or temp(squadId) then return end
    MySQL.prepare('INSERT INTO nz_squad_log (squad_id, kind, text, at) VALUES (?, ?, ?, ?)', { squadId, kind, text:sub(1, 200), at })
end

function DB.TopSquads(limit, cb)
    if not DB.On() then return cb({}) end
    MySQL.query([[SELECT s.id, s.name, s.tag, s.image, s.elo, s.wins, s.losses, s.draws, s.kills, s.deaths, s.assists,
                  (SELECT COUNT(*) FROM nz_squad_members m WHERE m.squad_id = s.id) AS members
                  FROM nz_squads s ORDER BY s.elo DESC, s.wins DESC LIMIT ?]], { limit },
        function(rows) cb(rows or {}) end)
end

function DB.TopPlayers(limit, cb)
    if not DB.On() then return cb({}) end
    MySQL.query([[SELECT COALESCE(m.nick, m.name) AS name, m.kills, m.deaths, m.assists, m.revives, m.playtime, s.name AS squad, s.tag, s.image
                  FROM nz_squad_members m JOIN nz_squads s ON s.id = m.squad_id
                  WHERE m.kills > 0 OR m.assists > 0 OR m.revives > 0
                  ORDER BY m.kills DESC, m.assists DESC LIMIT ?]], { limit },
        function(rows) cb(rows or {}) end)
end

function DB.MatchHistory(squadId, limit, cb)
    if not DB.On() or temp(squadId) then return cb({}) end
    MySQL.query('SELECT * FROM nz_squad_matches WHERE squad_a = ? OR squad_b = ? ORDER BY id DESC LIMIT ?',
        { squadId, squadId, limit }, function(rows) cb(rows or {}) end)
end

--- Removes stored squads nobody has touched in a while, and old log lines.
function DB.Prune()
    if not DB.On() then return end
    if Config.InactiveDays > 0 then
        local cutoff = os.time() - Config.InactiveDays * 86400
        MySQL.update('DELETE FROM nz_squads WHERE last_active < ?', { cutoff }, function(affected)
            if affected and affected > 0 then
                print(('^3[nayzeee-squads]^7 Removed %d squads inactive for over %d days.'):format(affected, Config.InactiveDays))
            end
        end)
    end
    if Config.LogRetentionDays > 0 then
        MySQL.update('DELETE FROM nz_squad_log WHERE at < ?', { os.time() - Config.LogRetentionDays * 86400 })
    end
end
