--[[
    Playlists: a player's own song lists, optionally shared with the whole city.
    A shared playlist can be browsed and played by anyone, but only its owner can change it.
]]
Playlists = {}
local RES = GetCurrentResourceName()

local function slim(t)
    return {
        src = t.src, id = t.id, url = t.src == 'url' and t.url or nil, search = t.search,
        title = t.title, author = t.author, duration = t.duration, thumb = t.thumb,
    }
end

local function row(r, me)
    local ok, tracks = pcall(json.decode, r.tracks)
    if not ok then tracks = {} end
    local ok2, collab = pcall(json.decode, r.collaborators or '[]')
    if not ok2 or type(collab) ~= 'table' then collab = {} end
    local canEdit = r.owner == me
    for _, c in ipairs(collab) do if c == me then canEdit = true break end end
    return {
        id = r.id, name = r.name, shared = r.shared == 1,
        owner = r.owner_name or 'Someone', mine = r.owner == me,
        kind = r.kind or 'normal', mixed = r.mixed == 1, collabs = #collab, canEdit = canEdit,
        count = #tracks, tracks = tracks,
    }
end

-- playlists shared with me as a collaborator
function Playlists.Collab(identifier)
    local rows = MySQL.query.await(
        "SELECT * FROM nayzeee_speaker_playlists WHERE kind = 'collab' AND collaborators LIKE ? ORDER BY updated_at DESC",
        { '%' .. identifier .. '%' }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local entry = row(r, identifier)
        if entry.canEdit and not entry.mine then out[#out + 1] = entry end
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

local function get(id)
    local r = MySQL.single.await('SELECT * FROM nayzeee_speaker_playlists WHERE id = ?', { id })
    return r
end

---------------------------------------------------------------- callbacks
NZ.RegisterCallback('pl:list', function(src)
    if not Config.Playlists.enabled then return {}, {} end
    local id = Bridge.GetIdentifier(src)
    local mine = Playlists.Mine(id)
    for _, p in ipairs(Playlists.Collab(id)) do mine[#mine + 1] = p end
    return mine, Config.Playlists.sharing and Playlists.Shared(id) or {}
end)

NZ.RegisterCallback('pl:create', function(src, name)
    if not Config.Playlists.enabled then return nil end
    local id = Bridge.GetIdentifier(src)
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 60)
    if #name == 0 then return nil end
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_speaker_playlists WHERE owner = ?', { id }) or 0
    if n >= Config.Playlists.perPlayer then Notify(src, 'pl_full') return nil end
    MySQL.insert.await('INSERT INTO nayzeee_speaker_playlists (owner, owner_name, name, tracks) VALUES (?, ?, ?, ?)',
        { id, Bridge.GetName(src), name, '[]' })
    Notify(src, 'pl_created', 'success', name)
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:add', function(src, plId, track)
    local id = Bridge.GetIdentifier(src)
    local r = get(plId)
    if not r then return nil end
    if r.owner ~= id and not row(r, id).canEdit then return nil end
    if type(track) ~= 'table' or type(track.src) ~= 'string' then return nil end
    local ok, tracks = pcall(json.decode, r.tracks)
    if not ok then tracks = {} end
    if #tracks >= Config.Playlists.maxTracks then Notify(src, 'pl_track_full') return nil end
    local key = (track.id or track.url or '')
    for _, t in ipairs(tracks) do
        if (t.id or t.url or '') == key then Notify(src, 'pl_dupe') return nil end
    end
    tracks[#tracks + 1] = slim(track)
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET tracks = ? WHERE id = ?', { json.encode(tracks), plId })
    Notify(src, 'pl_added', 'success', r.name)
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:remove', function(src, plId, idx)
    local id = Bridge.GetIdentifier(src)
    local r = get(plId)
    if not r or r.owner ~= id then return nil end
    local ok, tracks = pcall(json.decode, r.tracks)
    if not ok then return nil end
    idx = tonumber(idx)
    if not idx or not tracks[idx] then return nil end
    table.remove(tracks, idx)
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET tracks = ? WHERE id = ?', { json.encode(tracks), plId })
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:share', function(src, plId, on)
    local id = Bridge.GetIdentifier(src)
    local r = get(plId)
    if not r or r.owner ~= id then return nil end
    if not Config.Playlists.sharing then return nil end
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET shared = ? WHERE id = ?', { on and 1 or 0, plId })
    Notify(src, on and 'pl_shared' or 'pl_unshared', 'inform', r.name)
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:delete', function(src, plId)
    local id = Bridge.GetIdentifier(src)
    local r = get(plId)
    if not r or r.owner ~= id then return nil end
    MySQL.query.await('DELETE FROM nayzeee_speaker_playlists WHERE id = ?', { plId })
    return Playlists.Mine(id)
end)

NZ.RegisterCallback('pl:rename', function(src, plId, name)
    local id = Bridge.GetIdentifier(src)
    local r = get(plId)
    if not r or r.owner ~= id then return nil end
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 60)
    if #name == 0 then return nil end
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET name = ? WHERE id = ?', { name, plId })
    return Playlists.Mine(id)
end)

-- queue a whole playlist onto a speaker
RegisterNetEvent(RES .. ':pl:play', function(emitterId, plId, mode)
    local src = source
    local e = Guard(src, emitterId, true)
    if not e then return end
    e = Links.Leader(e)
    if IsTurntable(e) then return Notify(src, 'vinyl_only') end
    local r = get(plId)
    if not r then return end
    if r.owner ~= Bridge.GetIdentifier(src) and r.shared ~= 1 then return Notify(src, 'no_access') end
    local ok, tracks = pcall(json.decode, r.tracks)
    if not ok or #tracks == 0 then return Notify(src, 'pl_empty') end

    TriggerClientEvent(RES .. ':client:loading', src, e.id, true)
    local added, first = 0, nil
    for i, saved in ipairs(tracks) do
        if #e.queue >= Config.Limits.maxQueue then break end
        local track = Tracks.FromSaved(saved)
        if track then
            track.by = Bridge.GetName(src)
            if i == 1 and mode ~= 'queue' then first = track
            else e.queue[#e.queue + 1] = track end
            added = added + 1
        end
        if i % 4 == 0 then Wait(0) end
    end
    TriggerClientEvent(RES .. ':client:loading', src, e.id, false)
    if added == 0 then return Notify(src, 'resolve_failed') end
    if first then StartTrack(e, first) end
    Broadcast(e)
    Links.Sync(e)
    Notify(src, 'pl_queued', 'success', added, r.name)
    Log('Playlist played', ('**%s** queued `%s` (%d songs) on `%s`'):format(GetPlayerName(src), r.name, added, e.id))
end)

-- import a Spotify or YouTube playlist straight into a player's own playlist
NZ.RegisterCallback('pl:import', function(src, link)
    if not Config.Playlists.enabled then return nil end
    local id = Bridge.GetIdentifier(src)
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_speaker_playlists WHERE owner = ?', { id }) or 0
    if n >= Config.Playlists.perPlayer then Notify(src, 'pl_full') return nil end

    local name, tracks = nil, {}
    if tostring(link):find('spotify') then
        local d, err = Spotify.Import(link)
        if not d then Notify(src, err or 'resolve_failed') return nil end
        name = d.title
        for i, t in ipairs(d.tracks) do
            tracks[i] = { src = 'yt', search = t.search, title = t.title, author = d.artist, duration = 0, thumb = d.cover }
            if i >= Config.Playlists.maxTracks then break end
        end
    else
        local d, err = Search.Playlist(link)
        if not d then Notify(src, err or 'resolve_failed') return nil end
        name = d.title
        for i, t in ipairs(d.tracks) do
            tracks[i] = { src = 'yt', id = t.id, title = t.title, author = '', duration = 0,
                thumb = ('https://i.ytimg.com/vi/%s/mqdefault.jpg'):format(t.id) }
            if i >= Config.Playlists.maxTracks then break end
        end
    end
    if #tracks == 0 then Notify(src, 'resolve_failed') return nil end

    MySQL.insert.await('INSERT INTO nayzeee_speaker_playlists (owner, owner_name, name, tracks) VALUES (?, ?, ?, ?)',
        { id, Bridge.GetName(src), (name or 'Imported'):sub(1, 60), json.encode(tracks) })
    Notify(src, 'pl_imported', 'success', #tracks, name or 'playlist')
    return Playlists.Mine(id)
end)
