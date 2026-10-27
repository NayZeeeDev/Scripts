--[[
    Database: liked / recent songs, imported records, playlists and CarPlay units.
    The tables are created on start; columns added after the first release are added when missing.
]]
DB = {}

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_speaker_tracks` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(80) NOT NULL,
        `list` ENUM('fav','recent') NOT NULL,
        `track_key` VARCHAR(180) NOT NULL,
        `data` LONGTEXT NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uniq_track` (`identifier`,`list`,`track_key`),
        KEY `idx_owner` (`identifier`,`list`,`updated_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_speaker_vinyls` (
        `item` VARCHAR(64) NOT NULL,
        `data` LONGTEXT NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`item`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_speaker_playlists` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `owner` VARCHAR(80) NOT NULL,
        `owner_name` VARCHAR(80) NULL,
        `name` VARCHAR(60) NOT NULL,
        `shared` TINYINT(1) NOT NULL DEFAULT 0,
        `tracks` LONGTEXT NOT NULL,
        `kind` VARCHAR(16) NOT NULL DEFAULT 'normal',
        `collaborators` LONGTEXT NULL,
        `mixed` TINYINT(1) NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_owner` (`owner`),
        KEY `idx_shared` (`shared`, `updated_at`),
        KEY `idx_kind` (`kind`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_speaker_carplay` (
        `plate` VARCHAR(16) NOT NULL,
        `installed_by` VARCHAR(80) NULL,
        `installed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`plate`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    -- added after the first release; looked up first so a restart doesn't log "duplicate column" errors
    local have = {}
    local rows = MySQL.query.await([[SELECT COLUMN_NAME AS name FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'nayzeee_speaker_playlists']]) or {}
    for _, r in ipairs(rows) do have[r.name] = true end
    local columns = {
        { 'kind', "ADD COLUMN `kind` VARCHAR(16) NOT NULL DEFAULT 'normal'" },
        { 'collaborators', 'ADD COLUMN `collaborators` LONGTEXT NULL' },
        { 'mixed', 'ADD COLUMN `mixed` TINYINT(1) NOT NULL DEFAULT 0' },
    }
    for _, c in ipairs(columns) do
        if not have[c[1]] then pcall(MySQL.query.await, 'ALTER TABLE `nayzeee_speaker_playlists` ' .. c[2]) end
    end
    -- collaborative playlists are looked up by kind on every library open
    local indexed = MySQL.scalar.await([[SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'nayzeee_speaker_playlists' AND INDEX_NAME = 'idx_kind' LIMIT 1]])
    if not indexed then pcall(MySQL.query.await, 'ALTER TABLE `nayzeee_speaker_playlists` ADD KEY `idx_kind` (`kind`)') end
end)

---------------------------------------------------------------- saved songs
local function text(v, max) return type(v) == 'string' and v ~= '' and v:sub(1, max) or nil end
local function link(v) return type(v) == 'string' and #v <= 500 and v:match('^https?://') and v or nil end

--[[
    A song as it is stored in liked / recent / playlists: only what the UI shows and what replays it.
    Never the signed stream url (it expires), and nothing a player made up (players send these):
    src 'yt' needs a video id or a search ("<artist> <title>", imported playlists), src 'url' an https
    audio link. nil when it is neither.
]]
function DB.Slim(t)
    if type(t) ~= 'table' then return nil end
    local s = {
        title = text(t.title, 200), author = text(t.author, 120), thumb = link(t.thumb),
        duration = math.floor(NZ.Clamp(t.duration, 0, 36000)),
    }
    if t.src == 'url' then
        s.src, s.url = 'url', link(t.url)
        if not (s.url and s.url:match('^https://')) then return nil end
    elseif t.src == 'yt' then
        s.src = 'yt'
        s.id = type(t.id) == 'string' and #t.id <= 64 and t.id:match('^[%w_%-]+$') and t.id or nil
        s.search = not s.id and text(t.search, 200) or nil
        if not s.id and not s.search then return nil end
    else
        return nil
    end
    return s
end

function DB.TrackKey(t) return (t.src .. ':' .. (t.id or t.url or t.search or '')):sub(1, 180) end

function DB.GetList(identifier, list, limit)
    local rows = MySQL.query.await(
        'SELECT data FROM nayzeee_speaker_tracks WHERE identifier = ? AND list = ? ORDER BY updated_at DESC, id DESC LIMIT ?',
        { identifier, list, limit }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ok, t = pcall(json.decode, r.data)
        if ok and type(t) == 'table' then out[#out + 1] = t end
    end
    return out
end

function DB.Push(identifier, list, track, limit)
    local slim = DB.Slim(track)
    if not slim then return end
    MySQL.query.await(
        'INSERT INTO nayzeee_speaker_tracks (identifier, list, track_key, data) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = CURRENT_TIMESTAMP',
        { identifier, list, DB.TrackKey(slim), json.encode(slim) })
    if list == 'recent' then
        -- keep only the newest `limit` (no await: nothing waits on the trim)
        MySQL.query(
            'DELETE FROM nayzeee_speaker_tracks WHERE identifier = ? AND list = ? AND id NOT IN (SELECT id FROM (SELECT id FROM nayzeee_speaker_tracks WHERE identifier = ? AND list = ? ORDER BY updated_at DESC, id DESC LIMIT ?) keep)',
            { identifier, list, identifier, list, limit })
    end
end

function DB.Count(identifier, list)
    return MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_speaker_tracks WHERE identifier = ? AND list = ?', { identifier, list }) or 0
end

function DB.Remove(identifier, list, key)
    MySQL.query.await('DELETE FROM nayzeee_speaker_tracks WHERE identifier = ? AND list = ? AND track_key = ?', { identifier, list, key })
end

function DB.Has(identifier, list, key)
    return MySQL.scalar.await('SELECT 1 FROM nayzeee_speaker_tracks WHERE identifier = ? AND list = ? AND track_key = ? LIMIT 1',
        { identifier, list, key }) ~= nil
end

---------------------------------------------------------------- carplay units
function DB.CarplayInstalled(plate)
    return MySQL.scalar.await('SELECT 1 FROM nayzeee_speaker_carplay WHERE plate = ?', { plate }) ~= nil
end

-- how many rows it changed: 1 = installed / removed, 0 = there already was one / there was none
function DB.CarplaySet(plate, identifier, on)
    local n
    if on then
        n = MySQL.update.await('INSERT IGNORE INTO nayzeee_speaker_carplay (plate, installed_by) VALUES (?, ?)', { plate, identifier })
    else
        n = MySQL.update.await('DELETE FROM nayzeee_speaker_carplay WHERE plate = ?', { plate })
    end
    return tonumber(n) or 0
end
