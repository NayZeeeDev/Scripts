if not NAYZEEE_LOCK_OK then return end

--[[
    Tracks: listing with world records and personal bests, create (track builder), edit, delete.
]]

Tracks = { cache = {} }

local SELECT = [[
    SELECT t.id, t.name, t.description, t.creator, t.private, t.type, t.length, t.plays, UNIX_TIMESTAMP(t.created) AS created,
        p.alias AS creatorAlias, p.crew_id AS creatorCrew
    FROM nayzeee_racing_tracks t LEFT JOIN nayzeee_racing_profiles p ON p.id = t.creator
    WHERE t.deleted_at IS NULL]]

-- World records: circuits use the best lap, sprints the best total time
local function records(ids)
    if #ids == 0 then return {} end
    local marks = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(([[
        SELECT h.track_id, h.profile_id, p.alias, h.time_ms, h.best_lap_ms, t.type
        FROM nayzeee_racing_history h
        JOIN nayzeee_racing_tracks t ON t.id = h.track_id
        JOIN nayzeee_racing_profiles p ON p.id = h.profile_id
        WHERE h.status = 'finished' AND h.mode <> 'drift' AND h.track_id IN (%s)]]):format(marks), ids) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local v = r.type == 'circuit' and r.best_lap_ms or r.time_ms
        if v and v > 0 then
            local cur = out[r.track_id]
            if not cur or v < cur.time then out[r.track_id] = { time = v, holder = { id = r.profile_id, alias = r.alias } } end
        end
    end
    return out
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

-- Preview line for the UI: centers only, rounded
local function preview(cps)
    local out = {}
    for i, cp in ipairs(cps) do out[i] = { math.floor(cp.center.x), math.floor(cp.center.y) } end
    return out
end

local function dto(r, rec, pb)
    local cps = checkpointsOf(r.id)
    return {
        id = r.id, name = r.name, description = r.description, type = r.type, length = r.length, plays = r.plays,
        private = r.private == 1 or r.private == true, created = r.created,
        owner = { id = r.creator, alias = r.creatorAlias },
        checkpoints = #cps, preview = preview(cps),
        worldRecord = rec, personalBest = pb,
    }
end

function Tracks.CanSee(r, p)
    if r.private ~= 1 and r.private ~= true then return true end
    if r.creator == p.id then return true end
    return p.crewId ~= nil and r.creatorCrew == p.crewId
end

-- Full track for racing (checkpoints included)
function Tracks.Load(id)
    local r = MySQL.single.await(SELECT .. ' AND t.id = ?', { id })
    if not r then return nil end
    local t = dto(r)
    t.creatorCrew = r.creatorCrew
    t.creator = r.creator
    t.private = r.private == 1 or r.private == true
    t.gates = checkpointsOf(id)
    local rec = records({ id })
    t.worldRecord = rec[id]
    return t
end

Handle('track:list', function(src, p)
    local rows = MySQL.query.await(SELECT .. ' ORDER BY t.plays DESC, t.id DESC') or {}
    local visible, ids = {}, {}
    for _, r in ipairs(rows) do
        if Tracks.CanSee(r, p) then visible[#visible + 1] = r ids[#ids + 1] = r.id end
    end
    local rec, pb = records(ids), personal(p.id, ids)
    local out = {}
    local admin = CanManageTracks(src)
    for i, r in ipairs(visible) do
        local t = dto(r, rec[r.id], pb[r.id])
        t.canEdit = admin and (r.creator == p.id or Bridge.IsAdmin(src))
        out[i] = t
    end
    return out
end)

Handle('track:get', function(_, p, d)
    local id = tonumber(d.id) or 0
    local r = MySQL.single.await(SELECT .. ' AND t.id = ?', { id })
    if not r or not Tracks.CanSee(r, p) then return nil, 'TRACK_NOT_FOUND' end
    local t = dto(r, records({ id })[id], personal(p.id, { id })[id])
    t.top = MySQL.query.await([[SELECT h.profile_id AS id, p.alias, p.color, MIN(NULLIF(h.time_ms, 0)) AS time, MIN(NULLIF(h.best_lap_ms, 0)) AS lap
        FROM nayzeee_racing_history h JOIN nayzeee_racing_profiles p ON p.id = h.profile_id
        WHERE h.track_id = ? AND h.status = 'finished' AND h.mode <> 'drift' GROUP BY h.profile_id ORDER BY ]] ..
        (r.type == 'circuit' and 'lap' or 'time') .. ' ASC LIMIT 10', { id }) or {}
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

Handle('track:create', function(src, p, d)
    if not CanManageTracks(src) then return nil, 'ERR_NO_PERMISSION' end
    local name = NZR.Trim(d.name)
    if #name < 1 or #name > 60 then return nil, 'TRACK_NAME_REQUIRED' end
    local circuit = d.type == TrackType.CIRCUIT
    local cps, err = cleanCheckpoints(d.checkpoints, circuit)
    if not cps then return nil, err end
    local length = NZR.TrackLength(cps, circuit)
    local id = MySQL.insert.await('INSERT INTO nayzeee_racing_tracks (name, description, creator, checkpoints, private, type, length) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { name, NZR.Trim(d.description):sub(1, 500), p.id, json.encode(cps), d.private and 1 or 0, circuit and 'circuit' or 'sprint', length })
    if not id then return nil, 'ERR_GENERIC' end
    DiscordLog('Tracks', L('LOG_TRACK_CREATED'), { ('**%s** (#%d)'):format(name, id), L('LOG_BY', p.alias), ('%s · %d m · %d CP'):format(circuit and 'circuit' or 'sprint', length, #cps) })
    return { id = id }
end)

local function ownTrack(src, p, id)
    local r = MySQL.single.await(SELECT .. ' AND t.id = ?', { id })
    if not r then return nil, 'TRACK_NOT_FOUND' end
    if not CanManageTracks(src) then return nil, 'ERR_NO_PERMISSION' end
    if r.creator ~= p.id and not Bridge.IsAdmin(src) then return nil, 'ERR_NO_PERMISSION' end
    return r
end

Handle('track:update', function(src, p, d)
    local r, err = ownTrack(src, p, tonumber(d.id) or 0)
    if not r then return nil, err end
    local name = NZR.Trim(d.name)
    if #name < 1 or #name > 60 then return nil, 'TRACK_NAME_REQUIRED' end
    MySQL.update.await('UPDATE nayzeee_racing_tracks SET name = ?, description = ?, private = ? WHERE id = ?',
        { name, NZR.Trim(d.description):sub(1, 500), d.private and 1 or 0, r.id })
    return true
end)

Handle('track:delete', function(src, p, d)
    local r, err = ownTrack(src, p, tonumber(d.id) or 0)
    if not r then return nil, err end
    MySQL.update.await('UPDATE nayzeee_racing_tracks SET deleted_at = CURRENT_TIMESTAMP WHERE id = ?', { r.id })
    Tracks.cache[r.id] = nil
    DiscordLog('Tracks', L('LOG_TRACK_DELETED'), { ('**%s** (#%d)'):format(r.name, r.id), L('LOG_BY', p.alias) })
    return true
end)

Handle('builder:start', function(src)
    if not CanManageTracks(src) then return nil, 'ERR_NO_PERMISSION' end
    return true
end)
