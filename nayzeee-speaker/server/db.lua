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
        KEY `idx_shared` (`shared`, `updated_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_speaker_carplay` (
        `plate` VARCHAR(16) NOT NULL,
        `installed_by` VARCHAR(80) NULL,
        `installed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`plate`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    -- columns added after the first release
    for _, col in ipairs({
        "ADD COLUMN `kind` VARCHAR(16) NOT NULL DEFAULT 'normal'",
        "ADD COLUMN `collaborators` LONGTEXT NULL",
        "ADD COLUMN `mixed` TINYINT(1) NOT NULL DEFAULT 0",
    }) do
        pcall(function() MySQL.query.await('ALTER TABLE `nayzeee_speaker_playlists` ' .. col) end)
    end
end)

-- only what the UI needs is stored, never the signed stream url
local function slim(t)
    return {
        src = t.src, id = t.id, url = t.src == 'url' and t.url or nil,
        title = t.title, author = t.author, duration = t.duration, thumb = t.thumb,
    }
end

function DB.TrackKey(t) return (t.src .. ':' .. (t.id or t.url or '')):sub(1, 180) end

function DB.GetList(identifier, list, limit)
    local rows = MySQL.query.await(
        'SELECT data FROM nayzeee_speaker_tracks WHERE identifier = ? AND list = ? ORDER BY updated_at DESC, id DESC LIMIT ?',
        { identifier, list, limit }) or {}
    local out = {}
    for i, r in ipairs(rows) do out[i] = json.decode(r.data) end
    return out
end

function DB.Push(identifier, list, track, limit)
    MySQL.query.await(
        'INSERT INTO nayzeee_speaker_tracks (identifier, list, track_key, data) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = CURRENT_TIMESTAMP',
        { identifier, list, DB.TrackKey(track), json.encode(slim(track)) })
    if list == 'recent' then
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
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_speaker_tracks WHERE identifier = ? AND list = ? AND track_key = ?', { identifier, list, key })
    return (tonumber(n) or 0) > 0
end

function DB.CarplayInstalled(plate)
    return MySQL.scalar.await('SELECT 1 FROM nayzeee_speaker_carplay WHERE plate = ?', { plate }) ~= nil
end

function DB.CarplaySet(plate, identifier, on)
    if on then
        MySQL.insert.await('INSERT IGNORE INTO nayzeee_speaker_carplay (plate, installed_by) VALUES (?, ?)', { plate, identifier })
    else
        MySQL.query.await('DELETE FROM nayzeee_speaker_carplay WHERE plate = ?', { plate })
    end
end
