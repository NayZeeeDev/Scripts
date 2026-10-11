if not NAYZEEE_LOCK_OK then return end

--[[
    Racer profiles: sign in / sign up, stats, achievements, leaderboards, search and the inbox.
]]

Profiles = { cache = {}, stats = {} }
local board = { at = 0, data = nil }

-- Practice runs stay out of races / wins / podiums unless Config.Practice.CountsForStats
local REAL = Config.Practice.CountsForStats and '1 = 1' or "type <> 'practice'"
local REAL_H = Config.Practice.CountsForStats and '' or " AND h.type <> 'practice'"
Profiles.REAL, Profiles.REAL_H = REAL, REAL_H

local function mapRow(r)
    return {
        id = r.id, identifier = r.identifier, alias = r.alias, avatar = r.avatar or '', color = r.color or '#08afa2',
        elo = r.elo or 0, eloRewardMin = r.elo_reward_min or 0, crewId = r.crew_id,
        crewPerms = DB.Decode(r.crew_perms, {}), created = r.created,
    }
end

function Profiles.Load(id)
    local r = MySQL.single.await('SELECT * FROM nayzeee_racing_profiles WHERE id = ?', { id })
    if not r then return nil end
    local p = mapRow(r)
    local cached = Profiles.cache[id]
    p.source = cached and cached.source or nil
    Profiles.cache[id] = p
    return p
end

function Profiles.Get(id)
    return Profiles.cache[id] or Profiles.Load(id)
end

function Profiles.BySource(src)
    local id = Core.Sessions[src]
    return id and Profiles.cache[id] or nil
end

function Profiles.SignIn(src)
    local existing = Profiles.BySource(src)
    if existing then return existing end
    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return nil end
    local r = MySQL.single.await('SELECT * FROM nayzeee_racing_profiles WHERE identifier = ?', { identifier })
    if not r then return nil end
    -- keep one object per profile: lobbies hold a reference to it
    local p = Profiles.cache[r.id]
    if p then
        for k, v in pairs(mapRow(r)) do p[k] = v end
    else
        p = mapRow(r)
    end
    p.source = src
    Profiles.cache[p.id] = p
    Core.Sessions[src] = p.id
    Core.Online[p.id] = src
    return p
end

function Profiles.SignOut(src)
    local id = Core.Sessions[src]
    Core.Sessions[src] = nil
    if id then
        Core.Online[id] = nil
        if Profiles.cache[id] then Profiles.cache[id].source = nil end
        if not Core.Active[id] then Profiles.cache[id] = nil end
    end
end

-- What the UI gets about a racer
function Profiles.Dto(p)
    local crew = p.crewId and Crews.Brief(p.crewId) or nil
    return {
        id = p.id, alias = p.alias, avatar = p.avatar, color = p.color, elo = p.elo,
        crewId = p.crewId, crewPerms = p.crewPerms, crew = crew,
    }
end

function Profiles.Brief(p)
    return { id = p.id, alias = p.alias, avatar = p.avatar, color = p.color, elo = p.elo, crewId = p.crewId }
end

-- ── validation ──────────────────────────────────────────────────────────
local function validColor(c) return type(c) == 'string' and c:match('^#%x%x%x%x%x%x$') ~= nil end

local function domainOf(url) return tostring(url):match('^https?://([^/:]+)') end

-- avatar: generated dicebear url or allowed custom image
function ValidImage(url, cfg)
    if url == nil or url == '' then return true end
    if type(url) ~= 'string' or #url > 500 or not url:match('^https://') then return false end
    local host = domainOf(url) or ''
    if host == 'api.dicebear.com' then
        if not cfg.AllowAvatars then return false end
        local style = url:match('^https://api%.dicebear%.com/%d+%.x/([%w%-]+)/')
        for _, s in ipairs(cfg.AvatarTypes) do if s == style then return true end end
        return false
    end
    if not cfg.AllowCustomImages then return false end
    if cfg.AllowAllDomains then return true end
    for _, d in ipairs(cfg.AllowedDomains) do
        if host == d or host:sub(-(#d + 1)) == '.' .. d then return true end
    end
    return false
end

local function validAlias(alias)
    alias = NZR.Trim(alias)
    local cfg = Config.Profiles
    if #alias < cfg.AliasMin or #alias > cfg.AliasMax then return nil, 'PROFILE_ALIAS_LENGTH' end
    if not alias:match('^[%w%._%- ]+$') then return nil, 'PROFILE_ALIAS_CHARS' end
    return alias
end

local function aliasTaken(alias, except)
    local id = MySQL.scalar.await('SELECT id FROM nayzeee_racing_profiles WHERE LOWER(alias) = LOWER(?) LIMIT 1', { alias })
    return id ~= nil and id ~= except
end

Handle('profile:aliasAvailable', function(src, _, d)
    local alias = validAlias(d.alias)
    if not alias then return false end
    local me = Profiles.BySource(src)
    return not aliasTaken(alias, me and me.id)
end, { profile = false })

Handle('profile:create', function(src, _, d)
    if Profiles.SignIn(src) then return nil, 'PROFILE_EXISTS' end
    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return nil, 'ERR_NO_CHARACTER' end
    local alias, err = validAlias(d.alias)
    if not alias then return nil, err end
    if aliasTaken(alias) then return nil, 'PROFILE_ALIAS_TAKEN' end
    if not validColor(d.color) then return nil, 'ERR_INVALID' end
    if not ValidImage(d.avatar, Config.Profiles) then return nil, 'ERR_IMAGE' end
    local id = MySQL.insert.await('INSERT INTO nayzeee_racing_profiles (identifier, alias, avatar, color, elo) VALUES (?, ?, ?, ?, ?)',
        { identifier, alias, d.avatar or '', d.color, Config.Profiles.StartingElo })
    if not id then return nil, 'ERR_GENERIC' end
    MySQL.insert('INSERT INTO nayzeee_racing_elo_history (profile_id, elo) VALUES (?, ?)', { id, Config.Profiles.StartingElo })
    local p = Profiles.SignIn(src)
    return p and Profiles.Dto(p)
end, { profile = false })

Handle('profile:update', function(src, p, d)
    local alias = p.alias
    if d.alias and d.alias ~= p.alias then
        local err
        alias, err = validAlias(d.alias)
        if not alias then return nil, err end
        if aliasTaken(alias, p.id) then return nil, 'PROFILE_ALIAS_TAKEN' end
    end
    local color = d.color or p.color
    if not validColor(color) then return nil, 'ERR_INVALID' end
    local avatar = d.avatar ~= nil and d.avatar or p.avatar
    if not ValidImage(avatar, Config.Profiles) then return nil, 'ERR_IMAGE' end
    MySQL.update.await('UPDATE nayzeee_racing_profiles SET alias = ?, color = ?, avatar = ? WHERE id = ?', { alias, color, avatar, p.id })
    p.alias, p.color, p.avatar = alias, color, avatar
    board.data = nil
    return Profiles.Dto(p)
end)

-- ── stats ───────────────────────────────────────────────────────────────
function Profiles.Invalidate(id) Profiles.stats[id] = nil board.data = nil end

-- positions: newest first. current > 0 = win streak, < 0 = races without a win
local function streaks(positions)
    local best, run = 0, 0
    for i = #positions, 1, -1 do
        if positions[i] == 1 then run = run + 1 if run > best then best = run end else run = 0 end
    end
    local current = 0
    for _, pos in ipairs(positions) do
        local win = pos == 1
        if current == 0 then current = win and 1 or -1
        elseif (current > 0) == win then current = current + (win and 1 or -1)
        else break end
    end
    return current, best
end

function Profiles.Stats(id)
    local c = Profiles.stats[id]
    if c then return c end
    local s = MySQL.single.await(([[
        SELECT SUM(%s) AS races,
            SUM(%s AND position = 1 AND status = 'finished') AS wins,
            SUM(%s AND position <= 3 AND status IN ('finished', 'eliminated')) AS podiums,
            AVG(CASE WHEN %s AND status IN ('finished', 'eliminated') THEN position END) AS avgPos,
            SUM(IFNULL(distance, 0)) AS distance,
            SUM(IFNULL(time_ms, 0)) AS timeMs,
            MIN(NULLIF(best_lap_ms, 0)) AS bestLap,
            SUM(%s AND status = 'disqualified') AS dnfs,
            SUM(type = 'ranked') AS ranked,
            SUM(%s AND created >= DATE_FORMAT(NOW(), '%%Y-%%m-01')) AS thisMonth
        FROM nayzeee_racing_history WHERE profile_id = ?]]):format(REAL, REAL, REAL, REAL, REAL, REAL), { id }) or {}
    local recent = MySQL.query.await([[
        SELECT h.id, h.position, h.status, h.time_ms AS time, h.best_lap_ms AS bestLap, h.mode, h.type, h.vehicle, h.elo_delta AS eloDelta,
            UNIX_TIMESTAMP(h.created) AS date, t.name AS track
        FROM nayzeee_racing_history h LEFT JOIN nayzeee_racing_tracks t ON t.id = h.track_id
        WHERE h.profile_id = ? ORDER BY h.id DESC LIMIT 100]], { id }) or {}
    local monthly = MySQL.query.await([[
        SELECT DATE_FORMAT(created, '%Y-%m') AS month, COUNT(*) AS races, SUM(position = 1 AND status = 'finished') AS wins
        FROM nayzeee_racing_history WHERE profile_id = ? AND created >= DATE_SUB(NOW(), INTERVAL 12 MONTH) AND ]] .. REAL .. [[
        GROUP BY month ORDER BY month]], { id }) or {}
    local elo = MySQL.query.await([[
        SELECT elo, UNIX_TIMESTAMP(created) AS date FROM (
            SELECT elo, created, id FROM nayzeee_racing_elo_history WHERE profile_id = ? ORDER BY id DESC LIMIT 40
        ) x ORDER BY id]], { id }) or {}

    -- streaks + finishing positions use real races only (no practice)
    local real = {}
    for _, r in ipairs(recent) do
        if r.type ~= 'practice' or Config.Practice.CountsForStats then real[#real + 1] = r end
    end
    local positions = {}
    for i, r in ipairs(real) do positions[i] = r.status == 'finished' and r.position or 99 end
    local current, best = streaks(positions)

    local dist = { first = 0, podium = 0, mid = 0, rest = 0 }
    for _, r in ipairs(real) do
        if r.status == 'finished' or r.status == 'eliminated' then
            if r.position == 1 then dist.first = dist.first + 1
            elseif r.position <= 3 then dist.podium = dist.podium + 1
            elseif r.position <= 5 then dist.mid = dist.mid + 1
            else dist.rest = dist.rest + 1 end
        end
    end

    local races = tonumber(s.races) or 0
    local stats = {
        races = races,
        wins = tonumber(s.wins) or 0,
        podiums = tonumber(s.podiums) or 0,
        dnfs = tonumber(s.dnfs) or 0,
        ranked = tonumber(s.ranked) or 0,
        avgPosition = tonumber(s.avgPos) and math.floor(tonumber(s.avgPos) * 10 + 0.5) / 10 or 0,
        distance = tonumber(s.distance) or 0,
        time = math.floor((tonumber(s.timeMs) or 0) / 1000),
        bestLap = tonumber(s.bestLap),
        thisMonth = tonumber(s.thisMonth) or 0,
        streak = current, bestStreak = best,
        distribution = dist,
        recent = { table.unpack(recent, 1, math.min(#recent, 25)) },
        monthly = monthly,
        eloHistory = elo,
    }
    stats.winRate = races > 0 and math.floor(stats.wins / races * 1000 + 0.5) / 10 or 0
    stats.podiumRate = races > 0 and math.floor(stats.podiums / races * 1000 + 0.5) / 10 or 0

    local values = { races = stats.races, wins = stats.wins, podiums = stats.podiums, streak = stats.bestStreak,
        distance = stats.distance, time = stats.time, ranked = stats.ranked }
    stats.achievements = {}
    for _, a in ipairs(Config.Achievements) do
        local v = values[a.stat] or 0
        stats.achievements[#stats.achievements + 1] = { id = a.id, progress = math.min(v, a.value), goal = a.value, unlocked = v >= a.value }
    end

    Profiles.stats[id] = stats
    return stats
end

Handle('profile:get', function(_, me, d)
    local id = tonumber(d.id) or me.id
    local p = Profiles.Get(id)
    if not p or p.identifier == 'SYSTEM' then return nil, 'PROFILE_NOT_FOUND' end
    local dto = Profiles.Dto(p)
    dto.stats = Profiles.Stats(id)
    dto.online = Core.Online[id] ~= nil
    dto.badges = Seasons and Seasons.Badges(id) or {}
    return dto
end)

Handle('profile:search', function(_, me, d)
    local q = NZR.Trim(d.q)
    if #q < 1 then return {} end
    local rows = MySQL.query.await([[SELECT id, alias, avatar, color, elo, crew_id FROM nayzeee_racing_profiles
        WHERE alias LIKE ? AND identifier <> 'SYSTEM' ORDER BY elo DESC LIMIT 12]], { q:gsub('[%%_]', '') .. '%' }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = r.id, alias = r.alias, avatar = r.avatar, color = r.color, elo = r.elo, crewId = r.crew_id,
            crew = r.crew_id and Crews.Brief(r.crew_id) or nil, online = Core.Online[r.id] ~= nil }
    end
    return out
end)

-- ── leaderboards ────────────────────────────────────────────────────────
local function boardQuery(order, having)
    return ([[
        SELECT p.id, p.alias, p.avatar, p.color, p.elo, p.crew_id AS crewId,
            COUNT(h.id) AS races, IFNULL(SUM(h.position = 1 AND h.status = 'finished'), 0) AS wins,
            IFNULL(ROUND(SUM(h.position = 1 AND h.status = 'finished') / NULLIF(COUNT(h.id), 0) * 100, 1), 0) AS winRate
        FROM nayzeee_racing_profiles p LEFT JOIN nayzeee_racing_history h ON h.profile_id = p.id%s
        WHERE p.identifier <> 'SYSTEM'
        GROUP BY p.id %s ORDER BY %s LIMIT %d]]):format(REAL_H, having or '', order, Config.Leaderboard.Size)
end

function Profiles.Leaderboard()
    if board.data and os.time() - board.at < Config.Leaderboard.CacheSeconds then return board.data end
    local data = {
        elo = MySQL.query.await(boardQuery('p.elo DESC')) or {},
        wins = MySQL.query.await(boardQuery('wins DESC, winRate DESC', 'HAVING wins > 0')) or {},
        winRate = MySQL.query.await(boardQuery('winRate DESC, wins DESC', ('HAVING races >= %d'):format(Config.Leaderboard.MinRacesForWinRate))) or {},
    }
    for _, list in pairs(data) do
        for _, r in ipairs(list) do
            r.crew = r.crewId and Crews.Brief(r.crewId) or nil
            r.streak = Profiles.stats[r.id] and Profiles.stats[r.id].streak or nil
        end
    end
    board.data, board.at = data, os.time()
    return data
end

function Profiles.InvalidateBoard() board.data = nil end

Handle('leaderboard', function() return Profiles.Leaderboard() end)

-- ── ELO ─────────────────────────────────────────────────────────────────
function Profiles.AddElo(p, delta)
    p.elo = math.max(0, p.elo + delta)
    MySQL.update('UPDATE nayzeee_racing_profiles SET elo = ? WHERE id = ?', { p.elo, p.id })
    MySQL.insert('INSERT INTO nayzeee_racing_elo_history (profile_id, elo) VALUES (?, ?)', { p.id, p.elo })
    if p.source then Push(p.source, 'profile', Profiles.Dto(p)) end
end

-- ── inbox ───────────────────────────────────────────────────────────────
-- Async on purpose: finishing a race sends many messages and must never wait on them
function Profiles.Message(profileId, kind, message, metadata)
    MySQL.insert('INSERT INTO nayzeee_racing_messages (profile_id, type, message, metadata) VALUES (?, ?, ?, ?)',
        { profileId, kind, message, metadata and json.encode(metadata) or nil }, function()
            local src = Core.Online[profileId]
            if src then Push(src, 'inbox', { new = true }) end
        end)
end

Handle('inbox:list', function(_, p)
    local rows = MySQL.query.await([[SELECT id, type, message, metadata, `read`, UNIX_TIMESTAMP(created) AS created
        FROM nayzeee_racing_messages WHERE profile_id = ? ORDER BY id DESC LIMIT 100]], { p.id }) or {}
    for _, r in ipairs(rows) do r.metadata = DB.Decode(r.metadata, {}) r.read = r.read == 1 or r.read == true end
    return rows
end)

Handle('inbox:read', function(_, p, d)
    MySQL.update('UPDATE nayzeee_racing_messages SET `read` = 1 WHERE profile_id = ? AND (id = ? OR ? = 0)', { p.id, tonumber(d.id) or 0, tonumber(d.id) or 0 })
    return true
end)

Handle('inbox:delete', function(_, p, d)
    local msg = MySQL.single.await('SELECT type FROM nayzeee_racing_messages WHERE id = ? AND profile_id = ?', { tonumber(d.id) or 0, p.id })
    if not msg then return nil, 'MSG_NOT_FOUND' end
    if msg.type == MsgType.REWARD then return nil, 'MSG_CLAIM_FIRST' end
    MySQL.update.await('DELETE FROM nayzeee_racing_messages WHERE id = ? AND profile_id = ?', { tonumber(d.id), p.id })
    return true
end)

Handle('inbox:count', function(_, p)
    return MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_racing_messages WHERE profile_id = ? AND `read` = 0', { p.id }) or 0
end)
