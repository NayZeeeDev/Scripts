--[[
    Playlists: a player's own song lists, optionally shared with the whole city.
    A shared playlist can be browsed and played by anyone; its owner (and collaborators, see
    server/social.lua) can change it.
]]
Playlists = {}

local function decode(s)
    local ok, v = pcall(json.decode, s or '[]')
    return ok and type(v) == 'table' and v or {}
end

function Playlists.Collaborators(r) return decode(r.collaborators) end

local function isCollaborator(r, ident)
    for _, c in ipairs(Playlists.Collaborators(r)) do
        if c == ident then return true end
    end
    return false
end

local function canEdit(r, ident) return r.owner == ident or isCollaborator(r, ident) end

-- a TINYINT(1) column: oxmysql hands these over as true / false, other drivers as 1 / 0
local function flag(v) return v == true or v == 1 or v == '1' end

local function row(r, me)
    local tracks, collab = decode(r.tracks), Playlists.Collaborators(r)
    return {
        id = r.id, name = r.name, shared = flag(r.shared),
        owner = r.owner_name or 'Someone', mine = r.owner == me,
        kind = r.kind or 'normal', mixed = flag(r.mixed), collabs = #collab, canEdit = canEdit(r, me),
        count = #tracks, tracks = tracks,
    }
end

function Playlists.Get(id)
    id = tonumber(id)
    return id and MySQL.single.await('SELECT * FROM nayzeee_speaker_playlists WHERE id = ?', { id }) or nil
end

-- playlists shared with me as a collaborator
function Playlists.Collab(identifier)
    local rows = MySQL.query.await(
        "SELECT * FROM nayzeee_speaker_playlists WHERE kind = 'collab' AND collaborators LIKE ? ORDER BY updated_at DESC",
        { '%' .. identifier .. '%' }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        if r.owner ~= identifier and isCollaborator(r, identifier) then out[#out + 1] = row(r, identifier) end
    end
    return out
end

function Playlists.Mine(identifier)
    local rows = MySQL.query.await('SELECT * FROM nayzeee_speaker_playlists WHERE owner = ? ORDER BY updated_at DESC', { identifier }) or {}
    local out = {}
    for i, r in ipairs(rows) do out[i] = row(r, identifier) end
    return out
end

function Playlists.Shared(identifier, limit)
    local rows = MySQL.query.await(
        'SELECT * FROM nayzeee_speaker_playlists WHERE shared = 1 ORDER BY updated_at DESC LIMIT ?', { limit or 40 }) or {}
    local out = {}
    for i, r in ipairs(rows) do out[i] = row(r, identifier) end
    return out
end

local function setTracks(id, tracks)
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET tracks = ? WHERE id = ?', { json.encode(tracks), id })
end

local function countMine(ident)
    return MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_speaker_playlists WHERE owner = ?', { ident }) or 0
end

-- true when the player owns as many playlists as Config.Playlists.perPlayer allows (blend / prompted use it too)
function Playlists.Full(ident) return countMine(ident) >= Config.Playlists.perPlayer end

---------------------------------------------------------------- callbacks
NZ.RegisterCallback('pl:list', function(src)
    if not Config.Playlists.enabled then return {}, {} end
    local id = Bridge.GetIdentifier(src)
    local mine = Playlists.Mine(id)
    for _, p in ipairs(Playlists.Collab(id)) do mine[#mine + 1] = p end
    return mine, Config.Playlists.sharing and Playlists.Shared(id) or {}
end)

NZ.RegisterCallback('pl:create', function(src, name)
    if not Config.Playlists.enabled then Notify(src, 'feature_off', 'inform') return nil end
    local id = Bridge.GetIdentifier(src)
    name = NZ.Trim(name, 60)
    if #name == 0 then return nil end
    if countMine(id) >= Config.Playlists.perPlayer then Notify(src, 'pl_full') return nil end
    MySQL.insert.await('INSERT INTO nayzeee_speaker_playlists (owner, owner_name, name, tracks) VALUES (?, ?, ?, ?)',
        { id, Bridge.GetName(src), name, '[]' })
    Notify(src, 'pl_created', 'success', name)
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:add', function(src, plId, track)
    if not Config.Playlists.enabled then Notify(src, 'feature_off', 'inform') return nil end
    local slim = DB.Slim(track)
    local id = Bridge.GetIdentifier(src)
    local r = slim and Playlists.Get(plId)
    if not r or not canEdit(r, id) then return nil end
    local tracks = decode(r.tracks)
    if #tracks >= Config.Playlists.maxTracks then Notify(src, 'pl_track_full') return nil end
    local key = slim.id or slim.url or slim.search
    for _, t in ipairs(tracks) do
        if (t.id or t.url or t.search) == key then Notify(src, 'pl_dupe') return nil end
    end
    tracks[#tracks + 1] = slim
    setTracks(r.id, tracks)
    Notify(src, 'pl_added', 'success', r.name)
    return Playlists.Mine(id)
end)

-- collaborators may take songs off as well as add them (the UI offers both to anyone who can edit)
NZ.RegisterCallback('pl:remove', function(src, plId, idx)
    local id = Bridge.GetIdentifier(src)
    local r = Playlists.Get(plId)
    if not r or not canEdit(r, id) then return nil end
    local tracks = decode(r.tracks)
    idx = tonumber(idx)
    if not idx or not tracks[idx] then return nil end
    table.remove(tracks, idx)
    setTracks(r.id, tracks)
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:share', function(src, plId, on)
    if not Config.Playlists.sharing then Notify(src, 'feature_off', 'inform') return nil end
    local id = Bridge.GetIdentifier(src)
    local r = Playlists.Get(plId)
    if not r or r.owner ~= id then return nil end
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET shared = ? WHERE id = ?', { on and 1 or 0, r.id })
    Notify(src, on and 'pl_shared' or 'pl_unshared', 'inform', r.name)
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:delete', function(src, plId)
    local id = Bridge.GetIdentifier(src)
    local r = Playlists.Get(plId)
    if not r or r.owner ~= id then return nil end
    MySQL.query.await('DELETE FROM nayzeee_speaker_playlists WHERE id = ?', { r.id })
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:rename', function(src, plId, name)
    local id = Bridge.GetIdentifier(src)
    local r = Playlists.Get(plId)
    if not r or r.owner ~= id then return nil end
    name = NZ.Trim(name, 60)
    if #name == 0 then return nil end
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET name = ? WHERE id = ?', { name, r.id })
    return Playlists.Mine(id)
end)

-- import a Spotify or YouTube playlist straight into a player's own playlist (one at a time per player:
-- an import is a lot of web requests)
local importing = {}
NZ.RegisterCallback('pl:import', function(src, link)
    if not Config.Playlists.enabled then Notify(src, 'feature_off', 'inform') return nil end
    if importing[src] then return nil end
    link = NZ.Trim(link, 500)
    local id = Bridge.GetIdentifier(src)
    if countMine(id) >= Config.Playlists.perPlayer then Notify(src, 'pl_full') return nil end

    importing[src] = true
    local spotify = link:find('spotify', 1, true) ~= nil
    local ok, d, err = pcall(spotify and Spotify.Import or Search.Playlist, link)
    importing[src] = nil
    if not ok or not d then Notify(src, ok and err or 'resolve_failed') return nil end

    local tracks = {}
    for i, t in ipairs(d.tracks) do
        if i > Config.Playlists.maxTracks then break end
        if spotify then
            tracks[i] = { src = 'yt', search = t.search, title = t.title, author = d.artist, duration = 0, thumb = d.cover }
        else
            tracks[i] = { src = 'yt', id = t.id, title = t.title, author = '', duration = 0,
                thumb = ('https://i.ytimg.com/vi/%s/mqdefault.jpg'):format(t.id) }
        end
    end
    if #tracks == 0 then Notify(src, 'resolve_failed') return nil end

    local name = NZ.Trim(d.title, 60)
    if name == '' then name = 'Imported' end
    MySQL.insert.await('INSERT INTO nayzeee_speaker_playlists (owner, owner_name, name, tracks) VALUES (?, ?, ?, ?)',
        { id, Bridge.GetName(src), name, json.encode(tracks) })
    Notify(src, 'pl_imported', 'success', #tracks, name)
    return Playlists.Mine(id)
end)

---------------------------------------------------------------- playing a whole list
local lastList, fills = {}, {}

AddEventHandler('playerDropped', function()
    lastList[source], importing[source] = nil, nil
end)

-- saved songs, display name, crossfade seconds (mixed playlists), or nil when not allowed
-- which = 'liked' (the player's Liked Songs) or a playlist id
local function loadList(src, which)
    local ident = Bridge.GetIdentifier(src)
    if which == 'liked' then
        local pack = Locales[Config.Locale] or Locales.en
        local name = pack.phone and pack.phone.liked or 'Liked Songs'
        return DB.GetList(ident, 'fav', Config.Limits.favorites), name, nil
    end
    if not Config.Playlists.enabled then Notify(src, 'feature_off', 'inform') return nil end
    local r = Playlists.Get(which)
    if not r then return nil end
    if r.owner ~= ident and not flag(r.shared) and not isCollaborator(r, ident) then Notify(src, 'no_access') return nil end
    -- songs from a mixed playlist carry their crossfade length; the end watcher hands over early
    local mix = flag(r.mixed) and Config.Social.mixed ~= false and (Config.Social.mixedFade or 4.0) or nil
    return decode(r.tracks), r.name, mix
end

-- the list starting at `start`, optionally shuffled (a tapped song stays first), at most a full queue
local function order(tracks, start, shuffle)
    local n = #tracks
    start = math.floor(tonumber(start) or 1)
    if start < 1 or start > n then start = 1 end
    local out = {}
    for i = 0, n - 1 do out[i + 1] = tracks[(start - 1 + i) % n + 1] end
    if shuffle then
        local from = start > 1 and 2 or 1
        for i = n, from + 1, -1 do
            local j = math.random(from, i)
            out[i], out[j] = out[j], out[i]
        end
    end
    for i = n, Config.Limits.maxQueue + 2, -1 do out[i] = nil end
    return out
end

--[[
    Plays a list on a speaker the player has already been checked for: the first song that loads
    starts right away and the rest are looked up in the background and appended to the queue, so a
    25-song playlist doesn't keep the speaker silent while every song is found. Starting another list,
    stopping the speaker or removing it ends the background fill.
      which   'liked' or a playlist id
      opts    { start = index of the song to start from, shuffle = bool }
]]
function Playlists.Play(src, e, which, opts)
    opts = opts or {}
    e = Links.Leader(e)
    if IsTurntable(e) then return Notify(src, 'vinyl_only') end
    local t = GetGameTimer()
    if lastList[src] and t - lastList[src] < Config.Limits.rateLimit * 1000 then return Notify(src, 'rate_limited') end
    lastList[src] = t

    local tracks, name, mix = loadList(src, which)
    if not tracks then return end
    if #tracks == 0 then return Notify(src, 'pl_empty') end
    local list = order(tracks, opts.start, opts.shuffle == true)

    TriggerClientEvent(RES .. ':client:loading', src, e.id, true)
    local first, i = nil, 1
    while not first and i <= math.min(#list, 3) do
        first = Tracks.FromSaved(list[i])
        i = i + 1
    end
    TriggerClientEvent(RES .. ':client:loading', src, e.id, false)
    if Emitters[e.id] ~= e then return end
    if not first then return Notify(src, 'resolve_failed') end

    local by = Bridge.GetName(src)
    first.by, first.mix = by, mix
    PushHistory(e)
    e.queue = {}
    StartTrack(e, first)
    Broadcast(e)
    Links.Sync(e)
    Log('Playlist played', ('**%s** (%s) played `%s` on `%s`'):format(GetPlayerName(src), src, name or '?', e.id))

    -- the rest, in the background (followers share the leader's queue table, so syncing every few
    -- songs is enough)
    local token = {}
    fills[e.id] = token
    local function live() return fills[e.id] == token and Emitters[e.id] == e and e.track ~= nil end
    local added, unsent = 1, 0
    for j = i, #list do
        if not live() or #e.queue >= Config.Limits.maxQueue then break end
        local track = Tracks.FromSaved(list[j])
        if not live() then break end
        if track then
            track.by, track.mix = by, mix
            e.queue[#e.queue + 1] = track
            added, unsent = added + 1, unsent + 1
            if unsent >= 4 then unsent = 0 Broadcast(e) Links.Sync(e) end
        end
    end
    if fills[e.id] == token then fills[e.id] = nil end
    if unsent > 0 and Emitters[e.id] == e then Broadcast(e) Links.Sync(e) end
    Notify(src, 'pl_queued', 'success', added, name or '')
end

-- main player: play a whole playlist on the speaker that is open
RegisterNetEvent(RES .. ':pl:play', function(emitterId, plId)
    local src = source
    local e = Guard(src, emitterId, true)
    if e then Playlists.Play(src, e, plId) end
end)
