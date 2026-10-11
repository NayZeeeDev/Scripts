if not NAYZEEE_LOCK_OK then return end

--[[
    Tracks: listing with world records and personal bests, create (track builder), edit, delete,
    crew-only tracks, crew boards and the split references used by the race HUD.
]]

Tracks = { cache = {}, wr = {}, refs = {} }

local SELECT = [[
    SELECT t.id, t.name, t.description, t.creator, t.private, t.type, t.length, t.plays, UNIX_TIMESTAMP(t.created) AS created,
        t.crew_id AS crewId, p.alias AS creatorAlias, p.crew_id AS creatorCrew
    FROM nayzeee_racing_tracks t LEFT JOIN nayzeee_racing_profiles p ON p.id = t.creator
    WHERE t.deleted_at IS NULL]]

local function isPrivate(v) return v == 1 or v == true end

-- World records (circuits: best lap, sprints: best time). One grouped query for the tracks
-- that are not cached yet, then served from memory until a race on that track finishes.
local function records(ids)
    local need = {}
    for _, id in ipairs(ids) do if Tracks.wr[id] == nil then need[#need + 1] = id end end
    if #need > 0 then
        local marks = ('?,'):rep(#need):sub(1, -2)
        local rows = MySQL.query.await(([[
            SELECT h.track_id, h.profile_id, p.alias, h.time_ms, h.best_lap_ms, m.type
            FROM (
                SELECT h2.track_id, t.type,
                    CASE WHEN t.type = 'circuit' THEN MIN(NULLIF(h2.best_lap_ms, 0)) ELSE MIN(NULLIF(h2.time_ms, 0)) END AS best
                FROM nayzeee_racing_history h2 JOIN nayzeee_racing_tracks t ON t.id = h2.track_id
                WHERE h2.status = 'finished' AND h2.mode <> 'drift' AND h2.track_id IN (%s)
                GROUP BY h2.track_id, t.type
            ) m
            JOIN nayzeee_racing_history h ON h.track_id = m.track_id AND h.status = 'finished' AND h.mode <> 'drift'
                AND (CASE WHEN m.type = 'circuit' THEN h.best_lap_ms ELSE h.time_ms END) = m.best
            JOIN nayzeee_racing_profiles p ON p.id = h.profile_id
            ORDER BY h.id]]):format(marks), need) or {}
        for _, id in ipairs(need) do Tracks.wr[id] = false end
        for _, r in ipairs(rows) do
            if not Tracks.wr[r.track_id] then -- ties: the first to set it keeps it
                Tracks.wr[r.track_id] = { time = r.type == 'circuit' and r.best_lap_ms or r.time_ms, holder = { id = r.profile_id, alias = r.alias } }
            end
        end
    end
    local out = {}
    for _, id in ipairs(ids) do out[id] = Tracks.wr[id] or nil end
    return out
end

-- Called after results are saved
function Tracks.InvalidateRecord(id)
    Tracks.wr[id] = nil
    Tracks.refs[id .. ':l'] = nil
    Tracks.refs[id .. ':r'] = nil
end

-- Split reference: the fastest run with its checkpoint splits.
-- lapBased = circuit laps (best lap + its splits), otherwise a full sprint run (laps = 0).
-- profileId = that racer's personal best, nil = world record (cached).
function Tracks.Reference(trackId, lapBased, profileId)
    local key = trackId .. (lapBased and ':l' or ':r')
    if not profileId and Tracks.refs[key] ~= nil then return Tracks.refs[key] or nil end
    local col = lapBased and 'best_lap_ms' or 'time_ms'
    local where = lapBased and 'h.best_lap_ms > 0' or 'h.time_ms > 0 AND IFNULL(h.best_lap_ms, 0) = 0 AND IFNULL(h.laps, 0) = 0'
    local r = MySQL.single.await(([[SELECT h.%s AS time, h.splits, h.profile_id, p.alias FROM nayzeee_racing_history h
        JOIN nayzeee_racing_profiles p ON p.id = h.profile_id
        WHERE h.track_id = ? AND h.status = 'finished' AND h.mode <> 'drift' AND %s %s
        ORDER BY h.%s ASC, h.id ASC LIMIT 1]]):format(col, where, profileId and 'AND h.profile_id = ?' or '', col),
        profileId and { trackId, profileId } or { trackId })
    local ref = r and { time = r.time, splits = DB.Decode(r.splits, nil), holder = { id = r.profile_id, alias = r.alias } } or false
    if not profileId then Tracks.refs[key] = ref end
    return ref or nil
end

local function personal(profileId, ids)
    if #ids == 0 then return {} end
    local marks = ('?,'):rep(#ids):sub(1, -2)
    local params = { profileId }
    for _, id in ipairs(ids) do params[#params + 1] = id end
    local rows = MySQL.query.await(([[SELECT track_id, MIN(NULLIF(time_ms, 0)) AS best, MIN(NULLIF(best_lap_ms, 0)) AS lap
        FROM nayzeee_racing_history WHERE profile_id = ? AND status = 'finished' AND mode <> 'drift' AND track_id IN (%s) GROUP BY track_id]]):format(marks), params) or {}
    local out = {}
    for _, r in ipairs(rows) do out[r.track_id] = { time = r.best, lap = r.lap } end
    return out
end

local function checkpointsOf(id)
    local c = Tracks.cache[id]
    if c then return c end
    local raw = MySQL.scalar.await('SELECT checkpoints FROM nayzeee_racing_tracks WHERE id = ?', { id })
    c = DB.Decode(raw, {})
    Tracks.cache[id] = c
    return c
end
Tracks.Checkpoints = checkpointsOf

-- Preview line for the UI: centers only, rounded
local function preview(cps)
    local out = {}
    for i, cp in ipairs(cps) do out[i] = { math.floor(cp.center.x), math.floor(cp.center.y) } end
    return out
end

local function visibility(r)
    if not isPrivate(r.private) then return 'public' end
    return r.crewId and 'crew' or 'private'
end

local function dto(r, rec, pb)
    local cps = checkpointsOf(r.id)
    return {
        id = r.id, name = r.name, description = r.description, type = r.type, length = r.length, plays = r.plays,
        private = isPrivate(r.private), visibility = visibility(r), created = r.created,
        crew = r.crewId and Crews.Brief(r.crewId) or nil,
        owner = { id = r.creator, alias = r.creatorAlias },
        checkpoints = #cps, preview = preview(cps),
        worldRecord = rec, personalBest = pb,
    }
end

-- Public: everyone. Crew track: that crew. Private: creator + the creator's crew.
function Tracks.CanSee(r, p)
    if not isPrivate(r.private) then return true end
    if r.creator == p.id then return true end
    if r.crewId then return p.crewId ~= nil and p.crewId == r.crewId end
    return p.crewId ~= nil and r.creatorCrew == p.crewId
end

-- Full track for racing (checkpoints included)
function Tracks.Load(id)
    local r = MySQL.single.await(SELECT .. ' AND t.id = ?', { id })
    if not r then return nil end
    local t = dto(r)
    t.creatorCrew = r.creatorCrew
    t.crewId = r.crewId
    t.creator = r.creator
    t.private = isPrivate(r.private)
    t.gates = checkpointsOf(id)
    t.worldRecord = records({ id })[id]
    return t
end

-- Public tracks with their start gate (quick race)
function Tracks.Public()
    local rows = MySQL.query.await(SELECT .. ' AND t.private = 0 ORDER BY t.plays DESC, t.id DESC') or {}
    for _, r in ipairs(rows) do
        local cps = checkpointsOf(r.id)
        r.start = cps[1] and cps[1].center or nil
    end
    return rows
end

local function canEdit(src, p, r, admin)
    if admin == nil then admin = Bridge.IsAdmin(src) end
    if admin then return true end
    if r.crewId and p.crewId == r.crewId and CanBuildCrewTracks(p) then return true end
    return r.creator == p.id and CanManageTracks(src)
end

Handle('track:list', function(src, p)
    local rows = MySQL.query.await(SELECT .. ' ORDER BY t.plays DESC, t.id DESC') or {}
    local visible, ids = {}, {}
    for _, r in ipairs(rows) do
        if Tracks.CanSee(r, p) then visible[#visible + 1] = r ids[#ids + 1] = r.id end
    end
    local rec, pb = records(ids), personal(p.id, ids)
    local out = {}
    local admin = Bridge.IsAdmin(src)
    for i, r in ipairs(visible) do
        local t = dto(r, rec[r.id], pb[r.id])
        t.canEdit = canEdit(src, p, r, admin)
        out[i] = t
    end
    return out
end)

-- Top 10 per racer. Circuits by best lap, sprints by time. crewId = only that crew's members
local function topTimes(r, crewId)
    local col = r.type == 'circuit' and 'lap' or 'time'
    return MySQL.query.await(([[SELECT h.profile_id AS id, p.alias, p.color, MIN(NULLIF(h.time_ms, 0)) AS time, MIN(NULLIF(h.best_lap_ms, 0)) AS lap
        FROM nayzeee_racing_history h JOIN nayzeee_racing_profiles p ON p.id = h.profile_id
        WHERE h.track_id = ? AND h.status = 'finished' AND h.mode <> 'drift' %s
        GROUP BY h.profile_id HAVING %s IS NOT NULL ORDER BY %s ASC LIMIT 10]]):format(crewId and 'AND p.crew_id = ?' or '', col, col),
        crewId and { r.id, crewId } or { r.id }) or {}
end

Handle('track:get', function(src, p, d)
    local id = tonumber(d.id) or 0
    local r = MySQL.single.await(SELECT .. ' AND t.id = ?', { id })
    if not r or not Tracks.CanSee(r, p) then return nil, 'TRACK_NOT_FOUND' end
    local t = dto(r, records({ id })[id], personal(p.id, { id })[id])
    t.top = topTimes(r)
    if p.crewId and Config.Trackbuilder.CrewTracks then t.crewTop = topTimes(r, p.crewId) end
    t.canEdit = canEdit(src, p, r)
    return t
end)

-- ── validation ──────────────────────────────────────────────────────────
local function num(v) return type(v) == 'number' and v == v and v > -20000 and v < 20000 end

local function cleanCheckpoints(list, circuit)
    local tb = Config.Trackbuilder
    if type(list) ~= 'table' or #list < tb.MinCheckpoints or #list > tb.MaxCheckpoints then return nil, 'TRACK_CHECKPOINT_COUNT' end
    local out = {}
    for i, cp in ipairs(list) do
        local c = {}
        for _, k in ipairs({ 'left', 'center', 'right' }) do
            local v = type(cp) == 'table' and cp[k]
            if type(v) ~= 'table' or not num(v.x) or not num(v.y) or not num(v.z) then return nil, 'TRACK_INVALID' end
            c[k] = { x = math.floor(v.x * 100) / 100, y = math.floor(v.y * 100) / 100, z = math.floor(v.z * 100) / 100 }
        end
        if i > 1 and #(NZR.V3(c.center) - NZR.V3(out[i - 1].center)) < tb.DistanceBetweenCheckpoints - 0.5 then return nil, 'TRACK_TOO_CLOSE' end
        out[i] = c
    end
    if circuit and #(NZR.V3(out[1].center) - NZR.V3(out[#out].center)) > tb.CircuitMinimumDistanceBetweenFirstAndLastCheckpoint then
        return nil, 'TRACK_NOT_CLOSED'
    end
    return out
end

-- public | private | crew  ->  private flag, crew id
local function visibilityOf(src, p, v)
    local full = CanManageTracks(src)
    if not full then
        -- crew builders can only make crew tracks
        if not CanBuildCrewTracks(p) then return nil, nil, 'ERR_NO_PERMISSION' end
        v = 'crew'
    end
    if v == 'crew' then
        if not Config.Trackbuilder.CrewTracks or not p.crewId then return nil, nil, 'CREW_NOT_IN' end
        return 1, p.crewId
    end
    return v == 'private' and 1 or 0, nil
end

Handle('track:create', function(src, p, d)
    local name = NZR.Trim(d.name)
    if #name < 1 or #name > 60 then return nil, 'TRACK_NAME_REQUIRED' end
    local priv, crewId, perr = visibilityOf(src, p, d.visibility or (d.private and 'private' or 'public'))
    if not priv then return nil, perr end
    local circuit = d.type == TrackType.CIRCUIT
    local cps, err = cleanCheckpoints(d.checkpoints, circuit)
    if not cps then return nil, err end
    local length = NZR.TrackLength(cps, circuit)
    local id = MySQL.insert.await('INSERT INTO nayzeee_racing_tracks (name, description, creator, checkpoints, private, crew_id, type, length) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { name, NZR.Trim(d.description):sub(1, 500), p.id, json.encode(cps), priv, crewId, circuit and 'circuit' or 'sprint', length })
    if not id then return nil, 'ERR_GENERIC' end
    DiscordLog('Tracks', L('LOG_TRACK_CREATED'), { ('**%s** (#%d)'):format(name, id), L('LOG_BY', p.alias), ('%s · %d m · %d CP'):format(circuit and 'circuit' or 'sprint', length, #cps) })
    return { id = id }
end)

local function ownTrack(src, p, id)
    local r = MySQL.single.await(SELECT .. ' AND t.id = ?', { id })
    if not r then return nil, 'TRACK_NOT_FOUND' end
    if not canEdit(src, p, r) then return nil, 'ERR_NO_PERMISSION' end
    return r
end

Handle('track:update', function(src, p, d)
    local r, err = ownTrack(src, p, tonumber(d.id) or 0)
    if not r then return nil, err end
    local name = NZR.Trim(d.name)
    if #name < 1 or #name > 60 then return nil, 'TRACK_NAME_REQUIRED' end
    local priv, crewId, perr = visibilityOf(src, p, d.visibility or (d.private and 'private' or 'public'))
    if not priv then return nil, perr end
    -- an admin editing someone's crew track keeps it with that crew
    if crewId and r.crewId then crewId = r.crewId end
    MySQL.update.await('UPDATE nayzeee_racing_tracks SET name = ?, description = ?, private = ?, crew_id = ? WHERE id = ?',
        { name, NZR.Trim(d.description):sub(1, 500), priv, crewId, r.id })
    return true
end)

Handle('track:delete', function(src, p, d)
    local r, err = ownTrack(src, p, tonumber(d.id) or 0)
    if not r then return nil, err end
    MySQL.update.await('UPDATE nayzeee_racing_tracks SET deleted_at = CURRENT_TIMESTAMP WHERE id = ?', { r.id })
    Tracks.cache[r.id] = nil
    Tracks.InvalidateRecord(r.id)
    DiscordLog('Tracks', L('LOG_TRACK_DELETED'), { ('**%s** (#%d)'):format(r.name, r.id), L('LOG_BY', p.alias) })
    return true
end)

Handle('builder:start', function(src, p)
    if CanManageTracks(src) then return { crewOnly = false } end
    if CanBuildCrewTracks(p) then return { crewOnly = true } end
    return nil, 'ERR_NO_PERMISSION'
end)

-- ── crew records ────────────────────────────────────────────────────────
-- Best time per track among the crew's members, plus the crew's own tracks
Handle('crew:records', function(_, p, d)
    local crewId = tonumber(d.id) or p.crewId
    if not crewId or not Config.Trackbuilder.CrewTracks then return {} end
    local mine = crewId == p.crewId
    local rows = MySQL.query.await(([[
        SELECT h.track_id, h.profile_id, p.alias, MIN(NULLIF(h.time_ms, 0)) AS time, MIN(NULLIF(h.best_lap_ms, 0)) AS lap
        FROM nayzeee_racing_history h JOIN nayzeee_racing_profiles p ON p.id = h.profile_id
        WHERE p.crew_id = ? AND h.status = 'finished' AND h.mode <> 'drift'
        GROUP BY h.track_id, h.profile_id]]), { crewId }) or {}
    local tracks = MySQL.query.await(SELECT .. ' AND (t.crew_id = ? OR t.id IN (SELECT DISTINCT h.track_id FROM nayzeee_racing_history h JOIN nayzeee_racing_profiles p ON p.id = h.profile_id WHERE p.crew_id = ?))',
        { crewId, crewId }) or {}
    local byId, ids = {}, {}
    for _, r in ipairs(tracks) do
        -- another crew's private tracks never show up here
        if not isPrivate(r.private) or (mine and Tracks.CanSee(r, p)) then byId[r.id] = r ids[#ids + 1] = r.id end
    end
    local best = {}
    for _, r in ipairs(rows) do
        local t = byId[r.track_id]
        local v = t and (t.type == 'circuit' and r.lap or r.time)
        if v and v > 0 and (not best[r.track_id] or v < best[r.track_id].time) then
            best[r.track_id] = { time = v, holder = { id = r.profile_id, alias = r.alias } }
        end
    end
    local wr = records(ids)
    local out = {}
    for _, id in ipairs(ids) do
        local t, b = byId[id], best[id]
        if b or t.crewId == crewId then
            out[#out + 1] = {
                track = { id = t.id, name = t.name, type = t.type, length = t.length, visibility = visibility(t), preview = preview(checkpointsOf(t.id)) },
                record = b, isWr = b ~= nil and wr[id] ~= nil and wr[id].time == b.time,
            }
        end
    end
    table.sort(out, function(a, b)
        if (a.record ~= nil) ~= (b.record ~= nil) then return a.record ~= nil end
        return a.track.name < b.track.name
    end)
    return out
end)
