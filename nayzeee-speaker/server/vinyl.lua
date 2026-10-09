-- Turntable records: every record item is a whole album that plays in order.
Vinyl = {}
local RES = GetCurrentResourceName()

Records = {}            -- item -> { artist, album, year, cover, tracks = { {title, search|id} } }
local covers = {}       -- item -> fetched cover url (so we only ask Spotify once)

---------------------------------------------------------------- record list
local function normalise(item, raw)
    local tracks = {}
    for i, t in ipairs(raw.tracks or {}) do
        if type(t) == 'string' then
            tracks[i] = { title = t, search = ('%s %s'):format(raw.artist or '', t) }
        elseif type(t) == 'table' then
            tracks[i] = {
                title = t.title or ('Track %d'):format(i),
                id = t.id or (type(t.link) == 'string' and (NZ.ParseInput(t.link) == 'yt' and select(2, NZ.ParseInput(t.link)) or nil)) or nil,
                url = type(t.link) == 'string' and t.link:match('^https://') and not t.link:find('youtu') and t.link or nil,
                search = t.search or (t.link and nil) or ('%s %s'):format(raw.artist or '', t.title or ''),
            }
        end
    end
    return {
        item = item, artist = raw.artist or '', album = raw.album or item,
        year = tonumber(raw.year), cover = raw.cover, tracks = tracks, custom = raw.custom or false,
    }
end

function Vinyl.Reload()
    Records = {}
    for item, raw in pairs(Config.Vinyls or {}) do Records[item] = normalise(item, raw) end
    local rows = MySQL.query.await('SELECT item, data FROM nayzeee_speaker_vinyls') or {}
    for _, r in ipairs(rows) do
        local ok, d = pcall(json.decode, r.data)
        if ok and d then
            d.custom = true
            Records[r.item] = normalise(r.item, d)
        end
    end
    NZ.Debug(('loaded %d records'):format(#Records))
end

local function saveRecord(item, data)
    MySQL.query.await('INSERT INTO nayzeee_speaker_vinyls (item, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { item, json.encode(data) })
    data.custom = true
    Records[item] = normalise(item, data)
end

CreateThread(function()
    Wait(1500)
    Vinyl.Reload()
end)

-- album art: iTunes (no setup) then Spotify. When it arrives we re-broadcast so players see it.
local function coverFor(rec)
    if rec.cover then return rec.cover end
    return Artwork.Album(rec.artist, rec.album, function(url, year)
        rec.cover = url
        if year and not rec.year then rec.year = year end
        for _, e in pairs(Emitters) do
            if e.vinyl and e.vinyl.item == rec.item then Broadcast(e) end
        end
    end)
end

---------------------------------------------------------------- view
local function album(e) return e.vinyl and Records[e.vinyl.item] end

function Vinyl.View(e)
    local a = album(e)
    if not a then return nil end
    local tracks = {}
    for i, t in ipairs(a.tracks) do tracks[i] = t.title end
    return {
        item = a.item, artist = a.artist, album = a.album, year = a.year, cover = coverFor(a),
        idx = e.vinyl.idx or 1, tracks = tracks, loading = e.vinyl.loading or false,
    }
end

---------------------------------------------------------------- playback
local function resolveTrack(a, idx)
    local t = a.tracks[idx]
    if not t then return nil end
    if t.id then return Tracks.Resolve(t.id) end
    if t.url then return Tracks.Resolve(t.url) end
    if t.search then
        local id = Search.Song(t.search)
        if id then
            t.id = id       -- remember it so the next play is instant
            return Tracks.Resolve(id)
        end
    end
    return nil
end

function Vinyl.PlayIndex(e, idx)
    local a = album(e)
    if not a or not idx or not a.tracks[idx] then return end
    local token = {}
    e.vinyl.token = token
    e.vinyl.idx = idx
    e.vinyl.loading = true
    Broadcast(e)
    CreateThread(function()
        local track = resolveTrack(a, idx)
        if not e.vinyl or e.vinyl.token ~= token or not Emitters[e.id] then return end
        e.vinyl.loading = false
        if not track then
            if a.tracks[idx + 1] then return Vinyl.PlayIndex(e, idx + 1) end
            e.track, e.playing = nil, false
            return Broadcast(e)
        end
        track.title = a.tracks[idx].title or track.title
        track.author = a.artist
        track.thumb = coverFor(a) or track.thumb
        track.by = nil
        StartTrack(e, track)
        Broadcast(e)
        -- warm up the next track while this one plays, so the gap between songs is instant
        local nxt = a.tracks[idx + 1]
        if nxt and not nxt.id and nxt.search then
            CreateThread(function()
                local found = Search.Song(nxt.search)
                if found then nxt.id = found end
            end)
        end
    end)
end

function Vinyl.Advance(e, manual)
    local a = album(e)
    if not a then return end
    local idx = e.vinyl.idx or 1
    if e.track and e.loop and not manual then return Vinyl.PlayIndex(e, idx) end
    local nextIdx
    if e.shuffle and #a.tracks > 1 then
        repeat nextIdx = math.random(1, #a.tracks) until nextIdx ~= idx
    else
        nextIdx = idx + 1
    end
    if a.tracks[nextIdx] then return Vinyl.PlayIndex(e, nextIdx) end
    e.track, e.playing, e.pos = nil, false, 0
    e.vinyl.idx = 1
    Broadcast(e)
end

function Vinyl.Prev(e, pos)
    local idx = e.vinyl.idx or 1
    if pos > 5 or idx <= 1 then return Vinyl.PlayIndex(e, idx) end
    Vinyl.PlayIndex(e, idx - 1)
end

function Vinyl.Return(e, src)
    if not e.vinyl then return end
    local to = src
    if Config.VinylReturn == 'owner' and e.vinyl.ownerSrc and GetPlayerName(e.vinyl.ownerSrc) then to = e.vinyl.ownerSrc end
    if to and GetPlayerName(to) then Bridge.AddItem(to, e.vinyl.item) end
    e.vinyl = nil
    e.track, e.playing, e.pos = nil, false, 0
end

---------------------------------------------------------------- putting records on
local function nearestTurntable(src)
    local pos = GetEntityCoords(GetPlayerPed(src))
    local best, bestD
    for _, e in pairs(Emitters) do
        if IsTurntable(e) and e.state == 'placed' and e.coords then
            local d = #(pos - e.coords)
            if d <= Config.Actions.useRange + 1.0 and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best
end

local function insert(src, e, item)
    if not Records[item] then return end
    if not Bridge.HasItem(src, item) or not Bridge.RemoveItem(src, item) then return Notify(src, 'no_item') end
    if e.vinyl then Vinyl.Return(e, src) end
    e.vinyl = { item = item, owner = Bridge.GetIdentifier(src), ownerSrc = src, idx = 1 }
    e.queue = {}
    Notify(src, 'vinyl_on', 'success')
    Vinyl.PlayIndex(e, 1)
end

RegisterNetEvent(RES .. ':vinyl:insert', function(id, item)
    local src = source
    local e = Guard(src, id, true)
    if not e or not IsTurntable(e) then return end
    insert(src, e, item)
end)

RegisterNetEvent(RES .. ':vinyl:eject', function(id)
    local src = source
    local e = Guard(src, id, true)
    if not e or not e.vinyl then return end
    Vinyl.Return(e, src)
    Notify(src, 'vinyl_off', 'inform')
    Broadcast(e)
end)

NZ.RegisterCallback('vinyl:owned', function(src)
    local out = {}
    for item, a in pairs(Records) do
        if Bridge.HasItem(src, item) then
            out[#out + 1] = { item = item, artist = a.artist, album = a.album, year = a.year, cover = coverFor(a), count = #a.tracks }
        end
    end
    table.sort(out, function(x, y) return (x.artist .. x.album) < (y.artist .. y.album) end)
    return out
end)

-- using a record from the inventory puts it on the closest turntable
local registered = {}
function Vinyl.RegisterItems()
    for item in pairs(Records) do
        if not registered[item] then
            registered[item] = true
            local function use(src)
                local e = nearestTurntable(src)
                if not e then return Notify(src, 'no_turntable') end
                if not Guard(src, e.id, true) then return end
                insert(src, e, item)
            end
            Bridge.RegisterUsable(item, use)
            Bridge.OnUse[item] = use
        end
    end
end

CreateThread(function()
    while true do
        Wait(5000)
        if next(Records) then Vinyl.RegisterItems() end
    end
end)

---------------------------------------------------------------- import
local function slugify(s)
    s = tostring(s):lower():gsub('[^%w]+', '')
    return s:sub(1, 24)
end

-- link: a Spotify album/playlist link or a YouTube playlist link
function Vinyl.Import(link, src)
    local data, err
    if tostring(link):find('spotify') then
        local d, e2 = Spotify.Import(link)
        if not d then return nil, e2 end
        data = {
            artist = d.artist, album = d.title, year = d.year, cover = d.cover,
            tracks = {},
        }
        for i, t in ipairs(d.tracks) do data.tracks[i] = { title = t.title, search = t.search } end
    else
        local d, e2 = Search.Playlist(link)
        if not d then return nil, e2 end
        data = { artist = d.title or 'Playlist', album = d.title or 'Playlist', tracks = {} }
        for i, t in ipairs(d.tracks) do data.tracks[i] = { title = t.title, id = t.id } end
    end
    if #data.tracks == 0 then return nil, 'resolve_failed' end

    local item = 'vinyl_' .. slugify(data.album)
    saveRecord(item, data)
    Vinyl.RegisterItems()
    return item, data
end

local function isAdmin(src) return src == 0 or Bridge.IsAdmin(src) end

RegisterCommand('vinylimport', function(src, args)
    if not isAdmin(src) then return Notify(src, 'no_permission') end
    local link = args[1]
    if not link then
        local msg = 'usage: /vinylimport <spotify album/playlist link | youtube playlist link>'
        if src == 0 then print(msg) else Notify(src, 'invalid_input') end
        return
    end
    CreateThread(function()
        local item, data = Vinyl.Import(link, src)
        if not item then
            local why = data or 'resolve_failed'
            if src == 0 then print('[speaker] import failed: ' .. why) else Notify(src, why) end
            return
        end
        local line = ('[speaker] imported "%s - %s" as item %s (%d tracks). Add that item to your inventory.')
            :format(data.artist, data.album, item, #data.tracks)
        print(line)
        if src ~= 0 then
            Notify(src, 'vinyl_imported', 'success', data.album, item)
            Log('Record imported', ('**%s** imported `%s` — %s, %d tracks'):format(GetPlayerName(src), item, data.album, #data.tracks))
        end
    end)
end, false)

RegisterCommand('vinyllist', function(src)
    if not isAdmin(src) then return Notify(src, 'no_permission') end
    local rows = {}
    for item, a in pairs(Records) do
        rows[#rows + 1] = ('%-28s %s - %s (%d tracks)%s'):format(item, a.artist, a.album, #a.tracks, a.custom and ' [imported]' or '')
    end
    table.sort(rows)
    print('[speaker] records:\n' .. table.concat(rows, '\n'))
    if src ~= 0 then Notify(src, 'vinyl_listed', 'inform', #rows) end
end, false)

RegisterCommand('vinyldelete', function(src, args)
    if not isAdmin(src) then return Notify(src, 'no_permission') end
    local item = args[1]
    if not item or not Records[item] then return print('[speaker] no such record') end
    if not Records[item].custom then return print('[speaker] that record comes from vinyls.lua, edit the file instead') end
    MySQL.query.await('DELETE FROM nayzeee_speaker_vinyls WHERE item = ?', { item })
    Records[item] = nil
    print('[speaker] removed ' .. item)
end, false)

exports('ImportRecord', function(link) return Vinyl.Import(link, 0) end)
exports('GetRecords', function() return Records end)
