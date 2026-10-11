if not NAYZEEE_LOCK_OK then return end

--[[
    Database: tables, default track seeds and the one-time bablo-racing import.
]]

DB = { ready = false }

local tables = {
    [[CREATE TABLE IF NOT EXISTS nayzeee_racing_crews (
        id INT NOT NULL AUTO_INCREMENT,
        name VARCHAR(50) NOT NULL,
        tag VARCHAR(8) NOT NULL,
        avatar VARCHAR(255) DEFAULT NULL,
        description VARCHAR(255) NOT NULL DEFAULT '',
        color VARCHAR(7) NOT NULL DEFAULT '#08afa2',
        owner INT DEFAULT NULL,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_name (name),
        UNIQUE KEY uq_tag (tag)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_racing_profiles (
        id INT NOT NULL AUTO_INCREMENT,
        identifier VARCHAR(100) NOT NULL,
        alias VARCHAR(50) NOT NULL,
        avatar VARCHAR(512) NOT NULL DEFAULT '',
        color VARCHAR(7) NOT NULL DEFAULT '#08afa2',
        elo INT NOT NULL DEFAULT 500,
        elo_reward_min INT NOT NULL DEFAULT 0,
        crew_id INT DEFAULT NULL,
        crew_perms VARCHAR(64) DEFAULT NULL,
        crew_joined TIMESTAMP NULL DEFAULT NULL,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_identifier (identifier),
        UNIQUE KEY uq_alias (alias),
        KEY k_crew (crew_id),
        KEY k_elo (elo),
        CONSTRAINT fk_nzr_profile_crew FOREIGN KEY (crew_id) REFERENCES nayzeee_racing_crews (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_racing_crew_invites (
        id INT NOT NULL AUTO_INCREMENT,
        crew_id INT NOT NULL,
        profile_id INT NOT NULL,
        perms VARCHAR(64) DEFAULT NULL,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_invite (crew_id, profile_id),
        CONSTRAINT fk_nzr_inv_crew FOREIGN KEY (crew_id) REFERENCES nayzeee_racing_crews (id) ON DELETE CASCADE,
        CONSTRAINT fk_nzr_inv_profile FOREIGN KEY (profile_id) REFERENCES nayzeee_racing_profiles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_racing_crew_activity (
        id INT NOT NULL AUTO_INCREMENT,
        crew_id INT NOT NULL,
        type VARCHAR(32) NOT NULL,
        message VARCHAR(255) DEFAULT NULL,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY k_crew_created (crew_id, created),
        CONSTRAINT fk_nzr_act_crew FOREIGN KEY (crew_id) REFERENCES nayzeee_racing_crews (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_racing_tracks (
        id INT NOT NULL AUTO_INCREMENT,
        name VARCHAR(100) NOT NULL,
        description TEXT NOT NULL,
        creator INT DEFAULT NULL,
        checkpoints LONGTEXT NOT NULL,
        private TINYINT(1) NOT NULL DEFAULT 0,
        type VARCHAR(16) NOT NULL DEFAULT 'sprint',
        length INT UNSIGNED NOT NULL DEFAULT 0,
        plays INT UNSIGNED NOT NULL DEFAULT 0,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        updated TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted_at TIMESTAMP NULL DEFAULT NULL,
        PRIMARY KEY (id),
        KEY k_creator (creator),
        CONSTRAINT fk_nzr_track_creator FOREIGN KEY (creator) REFERENCES nayzeee_racing_profiles (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_racing_history (
        id INT NOT NULL AUTO_INCREMENT,
        lobby_id VARCHAR(16) NOT NULL,
        track_id INT NOT NULL,
        profile_id INT NOT NULL,
        position TINYINT UNSIGNED NOT NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'finished',
        time_ms INT DEFAULT NULL,
        best_lap_ms INT DEFAULT NULL,
        distance INT DEFAULT NULL,
        mode VARCHAR(16) NOT NULL DEFAULT 'standard',
        type VARCHAR(16) NOT NULL DEFAULT 'unranked',
        vehicle VARCHAR(64) DEFAULT NULL,
        elo_delta INT DEFAULT NULL,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY k_profile_created (profile_id, created),
        KEY k_track (track_id),
        CONSTRAINT fk_nzr_hist_profile FOREIGN KEY (profile_id) REFERENCES nayzeee_racing_profiles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_racing_elo_history (
        id INT NOT NULL AUTO_INCREMENT,
        profile_id INT NOT NULL,
        elo INT NOT NULL,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY k_profile (profile_id, created),
        CONSTRAINT fk_nzr_elo_profile FOREIGN KEY (profile_id) REFERENCES nayzeee_racing_profiles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS nayzeee_racing_messages (
        id INT NOT NULL AUTO_INCREMENT,
        profile_id INT NOT NULL,
        type VARCHAR(32) NOT NULL DEFAULT 'standard',
        message VARCHAR(255) DEFAULT NULL,
        metadata LONGTEXT DEFAULT NULL,
        `read` TINYINT(1) NOT NULL DEFAULT 0,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY k_profile (profile_id),
        CONSTRAINT fk_nzr_msg_profile FOREIGN KEY (profile_id) REFERENCES nayzeee_racing_profiles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

local seeds = {
    'north-side', 'humane-hills', 'round-the-circle', 'oil-fields', 'grus-guld',
    'norra-grand-prix', 'semester', 'midnattsrundan', 'northside-hills-v2', 'harbor-round',
}

local function tableExists(name)
    return MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name }) > 0
end

-- One time copy of bablo-racing data (ids preserved so history / crews line up)
local function importBablo()
    if not Config.Env.ImportFromBablo or not tableExists('bablo_racing_profiles') then return end
    if MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_racing_profiles') > 0 then return end
    Log('info', 'Importing bablo-racing data...')
    local steps = {
        [[INSERT IGNORE INTO nayzeee_racing_crews (id, name, tag, avatar, description, color, created)
            SELECT id, name, UPPER(tag), avatar, description, color, created FROM bablo_racing_crews]],
        [[INSERT IGNORE INTO nayzeee_racing_profiles (id, identifier, alias, avatar, color, elo, elo_reward_min, crew_id, crew_perms, crew_joined, created)
            SELECT id, identifier, alias, avatar, color, elo, elo_reward_min, crew_id, permission_level, crew_joined, created FROM bablo_racing_profiles]],
        [[UPDATE nayzeee_racing_crews c JOIN bablo_racing_crews b ON b.id = c.id
            JOIN nayzeee_racing_profiles p ON p.id = CAST(b.creator AS UNSIGNED) SET c.owner = p.id]],
        [[INSERT IGNORE INTO nayzeee_racing_tracks (id, name, description, creator, checkpoints, private, type, length, created, deleted_at)
            SELECT id, name, description, creator, checkpoints, private, type, length, created, deleted_at FROM bablo_racing_tracks]],
        [[INSERT INTO nayzeee_racing_history (lobby_id, track_id, profile_id, position, time_ms, best_lap_ms, distance, mode, created)
            SELECT CAST(lobby_id AS CHAR), track_id, profile_id, position, time_ms, best_lap_time_ms, distance, mode, created FROM bablo_racing_history]],
        [[INSERT INTO nayzeee_racing_elo_history (profile_id, elo, created) SELECT profile_id, elo, created FROM bablo_racing_elo_history]],
    }
    for _, q in ipairs(steps) do
        local ok, err = pcall(MySQL.query.await, q)
        if not ok then Log('warn', 'Import step failed: %s', tostring(err)) end
    end
    Log('info', 'bablo-racing import complete')
end

local function systemProfile()
    local id = MySQL.scalar.await('SELECT id FROM nayzeee_racing_profiles WHERE identifier = ?', { 'SYSTEM' })
    if id then return id end
    return MySQL.insert.await('INSERT INTO nayzeee_racing_profiles (identifier, alias, avatar, color, elo) VALUES (?, ?, ?, ?, 0)',
        { 'SYSTEM', 'City Tracks', '', '#08afa2' })
end

local function seedTracks()
    if not Config.Races.DefaultTracks then return end
    local sys = systemProfile()
    if not sys then return end
    local added = 0
    for _, name in ipairs(seeds) do
        local raw = LoadResourceFile(NZR.Resource, ('seed/tracks/%s.json'):format(name))
        local ok, t = pcall(json.decode, raw or '')
        if ok and type(t) == 'table' and t.name and t.checkpoints then
            local exists = MySQL.scalar.await('SELECT 1 FROM nayzeee_racing_tracks WHERE name = ? AND creator = ? LIMIT 1', { t.name, sys })
            if not exists then
                MySQL.insert.await('INSERT INTO nayzeee_racing_tracks (name, description, creator, checkpoints, private, type, length) VALUES (?, ?, ?, ?, 0, ?, ?)',
                    { t.name, t.description or '', sys, json.encode(t.checkpoints), t.type, t.length or NZR.TrackLength(t.checkpoints, t.type == 'circuit') })
                added = added + 1
            end
        end
    end
    if added > 0 then Log('info', 'Seeded %d default tracks', added) end
end

MySQL.ready(function()
    for _, q in ipairs(tables) do
        local ok, err = pcall(MySQL.query.await, q)
        if not ok then Log('error', 'Table setup failed: %s', tostring(err)) return end
    end
    importBablo()
    seedTracks()
    DB.ready = true
    Log('info', 'Database ready')
end)

-- JSON helpers used by every module
function DB.Decode(s, fallback)
    if type(s) ~= 'string' or s == '' then return fallback end
    local ok, v = pcall(json.decode, s)
    return ok and v or fallback
end
