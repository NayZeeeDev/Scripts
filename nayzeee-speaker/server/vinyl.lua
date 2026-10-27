--[[
    Records for the turntable. Every record item is a whole album that plays in order.

    Every player's turntable props (client/turntable.lua) are driven from Vinyl.View, so this file
    also owns their timing: when a record goes on, or the arm moves to another track, the music is
    held back until the tonearm has had time to swing over and drop the needle.
]]
Vinyl = {}
--[[ item -> { item, artist, album, year, cover, tracks = { { title, id | url, search } }, titles, custom,
              genre, price, description }   (the last three are for the record shop, all optional) ]]
Records = {}

local T = Config.Turntable or {}

local function now() return GetGameTimer() end

---------------------------------------------------------------- needle drop timing
--[[
    Seconds from the moment something happens until the needle lands (client/turntable.lua animates
    exactly this, keep the two in step):
      insert  the record shows in the hand at 0.55, is let go at 1.05, sits on the spindle at 2.35,
              then the arm lifts (0.35 s), swings to the lead-in (about 0.9 s) and lowers (0.5 s)
      rest    play pressed while the arm is home: lift + swing + lower
      skip    the arm lifts out of one groove, moves to the next track and lowers
      swap    a record goes on while another is playing: the old one comes off first
    MIN_CUE is the least warning players get, for a song that took a while to find.
]]
local INSERT_LEAD, REST_LEAD, SKIP_LEAD, SWAP_DELAY, MIN_CUE = 4.4, 2.0, 1.7, 2.6, 0.9

-- Only wait for a needle when players can actually see one: 'auto' = once the turntable props are
-- in stream/ (until the new models are converted the music starts right away, like before).
local function propsShipped()
    for _, name in ipairs({ 'nayzeee_tt_platter', 'nayzeee_tt_arm', 'nayzeee_vinyl' }) do
        local found = false
        for _, dir in ipairs({ 'stream/', 'stream/turntable/', 'stream/props/' }) do
            if LoadResourceFile(RES, dir .. name .. '.ydr') then found = true break end
        end
        if not found then return false end
    end
    return true
end

local NEEDLE = T.needleDrop
if T.visuals == false then
    NEEDLE = false
elseif NEEDLE == nil or NEEDLE == 'auto' then
    NEEDLE = propsShipped()
else
    NEEDLE = NEEDLE == true
end
Vinyl.NeedleDrop = NEEDLE

-- The needle only exists on the record console upgrade: a deck placed with the old turntable model
-- has its own baked platter and record, so its music starts right away, as before.
local CONSOLE = T.consoleModel or 'nayzeee_console'
local function needle(e) return NEEDLE and e ~= nil and e.model == CONSOLE end

-- tell everyone about a change; linked speakers mirror their leader
local function push(e)
    Broadcast(e)
    if e.group and Links then Links.Sync(e) end
end

---------------------------------------------------------------- record list
local function str(v) return type(v) == 'string' and v ~= '' and v or nil end

-- a record from vinyls.lua or the database (imported) the way the rest of the script uses it
local function normalise(item, raw)
    local tracks, titles = {}, {}
    local artist = str(raw.artist) or ''
    for i, t in ipairs(type(raw.tracks) == 'table' and raw.tracks or {}) do
        local tr
        if type(t) == 'string' then
            tr = { title = t }
        elseif type(t) == 'table' then
            local kind, value = NZ.ParseInput(t.link)
            tr = {
                title = str(t.title) or ('Track %d'):format(i),
                id = str(t.id) or (kind == 'yt' and value or nil),
                url = kind == 'url' and value or nil,
                search = str(t.search),
            }
        end
        if tr then
            -- searching "<artist> <title>" is always there as the last resort
            tr.search = tr.search or ('%s %s'):format(artist, tr.title)
            tracks[#tracks + 1] = tr
            titles[#titles + 1] = tr.title
        end
    end
    local price = raw.price
    if price ~= false then price = tonumber(price) end
    return {
        item = item, artist = artist, album = str(raw.album) or item,
        year = tonumber(raw.year), cover = str(raw.cover), tracks = tracks, titles = titles, custom = raw.custom or false,
        genre = str(raw.genre), price = price, description = str(raw.description),
    }
end

-- one record change per player per deck every half second: the arm takes seconds anyway, and it
-- keeps a spammed insert / eject from flooding every client with prop changes
local lastChange = {}       -- src -> { [deckId] = ms }
local function tooSoon(src, id)
    local t = lastChange[src] and lastChange[src][id]
    return t ~= nil and now() - t < 500
end
local function changed(src, id)
    lastChange[src] = lastChange[src] or {}
    lastChange[src][id] = now()
end

AddEventHandler('playerDropped', function() lastChange[source] = nil end)

-- using a record from the inventory puts it on the closest turntable
local registered = {}
function Vinyl.RegisterItems()
    for item in pairs(Records) do
        if not registered[item] then
            registered[item] = true
            Bridge.RegisterUsable(item, function(src)
                local e = Vinyl.Nearest(src)
                if not e then return Notify(src, 'no_turntable') end
                if tooSoon(src, e.id) or not Guard(src, e.id, true) then return end
                if Vinyl.Insert(src, e, item) then changed(src, e.id) end
            end)
        end
    end
end

function Vinyl.Reload()
    Records = {}
    local n = 0
    for item, raw in pairs(Config.Vinyls or {}) do
        Records[item] = normalise(item, raw)
        n = n + 1
    end
    local rows = MySQL.query.await('SELECT item, data FROM nayzeee_speaker_vinyls') or {}
    for _, r in ipairs(rows) do
        local ok, d = pcall(json.decode, r.data)
        if ok and type(d) == 'table' then
            d.custom = true
            if not Records[r.item] then n = n + 1 end
            Records[r.item] = normalise(r.item, d)
        end
    end
    Vinyl.RegisterItems()
    NZ.Debug(('loaded %d records'):format(n))
end

local function saveRecord(item, data)
    MySQL.query.await('INSERT INTO nayzeee_speaker_vinyls (item, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { item, json.encode(data) })
    data.custom = true
    Records[item] = normalise(item, data)
end

CreateThread(function()
    Wait(1500)          -- server/db.lua creates the table first
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

-- cover art for any record item (nil while it is still being looked up)
function Vinyl.Cover(item)
    local a = Records[item]
    return a and coverFor(a) or nil
end

---------------------------------------------------------------- view
local function album(e) return e.vinyl and Records[e.vinyl.item] end

local function phase(e, v)
    if v.loading then return 'loading' end
    if not e.track then return 'idle' end
    if not e.playing then return 'paused' end
    if (e.startedAt or 0) > now() then return 'cue' end
    return 'playing'
end

--[[
    What players get in emitter.vinyl. The turntable props use:
      by / at   server id of the player who put it on, and when (server ms; in the future while an
                old record is still coming off)
      on        the deck it was put on (linked decks show the same record without the hand)
      move      how the arm reaches the current track: 'drop' (lift, move, lower) | 'flow' (stays down)
      moveAt    when that started (server ms)
      land      when the needle lands (server ms; the real value is emitter.startedAt once known)
      phase     loading | cue | playing | paused | idle, as of this broadcast
]]
function Vinyl.View(e)
    local a = album(e)
    if not a then return nil end
    local v = e.vinyl
    return {
        item = a.item, artist = a.artist, album = a.album, year = a.year, cover = coverFor(a),
        idx = v.idx or 1, tracks = a.titles, loading = v.loading or false,
        by = v.by, at = v.at, on = v.on, move = v.move, moveAt = v.moveAt, land = v.land,
        phase = phase(e, v),
    }
end

---------------------------------------------------------------- playback
local function resolveTrack(a, idx)
    local t = a.tracks[idx]
    if not t then return nil end
    local track = t.id and Tracks.Resolve(t.id) or t.url and Tracks.Resolve(t.url) or nil
    if track then return track end
    local id = t.search and Search.Song(t.search)
    if id then
        t.id = id       -- remember it so the next play is instant
        return Tracks.Resolve(id)
    end
    return nil
end

-- warm up the next track while this one plays, so the gap between songs is short
local function prefetch(a, idx)
    local nxt = a.tracks[idx + 1]
    if not nxt or nxt.id or nxt.url or not nxt.search then return end
    CreateThread(function()
        local found = Search.Song(nxt.search)
        if found then nxt.id = found end
    end)
end

--[[
    how = 'insert' (the record just went on), 'flow' (the album carries on into the next groove and the
    needle stays down) or nil (the arm lifts and drops onto the track).
]]
function Vinyl.PlayIndex(e, idx, how)
    local a = album(e)
    if not a or not idx or not a.tracks[idx] then return end
    local v = e.vinyl
    local t = now()
    local token = {}
    v.token, v.idx, v.loading = token, idx, true
    v.move, v.moveAt = how == 'flow' and 'flow' or 'drop', t

    local land = t
    if needle(e) then
        if how == 'insert' then
            land = (v.at or t) + math.floor(INSERT_LEAD * 1000)
        elseif how ~= 'flow' then
            land = t + math.floor((e.track and SKIP_LEAD or REST_LEAD) * 1000)
        end
    end
    v.land = land
    -- the old song stops while the next one is found (and the arm moves). This also keeps the
    -- song-end watcher from firing again for a song that already ended while the search runs,
    -- which used to skip straight through a record whenever a track took a while to find.
    if e.track and e.playing then e.pos, e.playing = Elapsed(e), false end
    push(e)

    CreateThread(function()
        local track = resolveTrack(a, idx)
        if e.vinyl ~= v or v.token ~= token or not Emitters[e.id] then return end
        v.loading = false
        if not track then
            if a.tracks[idx + 1] then return Vinyl.PlayIndex(e, idx + 1, how == 'insert' and 'insert' or nil) end
            e.track, e.playing = nil, false
            return push(e)
        end
        track.title = a.tracks[idx].title or track.title
        track.author = a.artist
        track.thumb = coverFor(a) or track.thumb
        track.by = nil
        local cue = 0
        if needle(e) and how ~= 'flow' then cue = math.max((land - now()) / 1000, MIN_CUE) end
        StartTrack(e, track, 0, cue)
        v.land = e.startedAt
        push(e)
        prefetch(a, idx)
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
    if a.tracks[nextIdx] then
        -- straight on to the next song: on a real record that is just the next groove
        return Vinyl.PlayIndex(e, nextIdx, (not manual and nextIdx == idx + 1) and 'flow' or nil)
    end
    -- end of the record: the arm goes home
    e.track, e.playing, e.pos = nil, false, 0
    e.vinyl.idx = 1
    e.vinyl.loading = false
    push(e)
end

function Vinyl.Prev(e, pos)
    local idx = e.vinyl.idx or 1
    if pos > 5 or idx <= 1 then return Vinyl.PlayIndex(e, idx) end
    Vinyl.PlayIndex(e, idx - 1)
end

--[[
    Takes the record off a deck and hands the item back. usedId = the deck the player actually used
    (players near it see the record go back to that player's hand).
    A linked deck only mirrors its leader's record: clearing the mirror hands nothing back, and the
    leader's record clears every mirror, so one record can never come back twice.
]]
function Vinyl.Return(e, src, usedId)
    local v = e.vinyl
    if not v then return end
    local lead = Links and Links.Leader(e) or e
    if lead ~= e and lead.vinyl == v then
        e.vinyl = nil
        return
    end
    local to = src
    if Config.VinylReturn == 'owner' and v.ownerSrc and GetPlayerName(v.ownerSrc) then to = v.ownerSrc end
    if to and GetPlayerName(to) then Bridge.AddItem(to, v.item) else to = nil end
    -- linked speakers played this record too: they stop with it (told here, because a deck that is
    -- packed up or broken leaves its group without telling anyone)
    if e.group and Links then
        for _, m in ipairs(Links.Members(e)) do
            if m ~= e and m.vinyl == v then
                m.vinyl, m.track, m.playing, m.pos = nil, nil, false, 0
                Broadcast(m)
            end
        end
    end
    e.vinyl, v.token = nil, nil
    e.track, e.playing, e.pos = nil, false, 0
    TriggerClientEvent(RES .. ':client:vinylOff', -1, usedId or e.id, to or false, now())
end

---------------------------------------------------------------- putting records on
function Vinyl.Nearest(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local pos = GetEntityCoords(ped)
    local best, bestD
    for _, e in pairs(Emitters) do
        if IsTurntable(e) and e.state == 'placed' and e.coords then
            local d = #(pos - e.coords)
            if d <= Config.Actions.useRange + 1.0 and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best
end

-- true when the record went on
function Vinyl.Insert(src, e, item)
    if not Records[item] then return false end
    if not Bridge.HasItem(src, item) or not Bridge.RemoveItem(src, item) then return Notify(src, 'no_item') end
    -- linked decks share one record: it goes on the deck that leads the music (a deck following
    -- an ordinary speaker leaves that group to play it)
    local lead = Links and Links.Leader(e) or e
    if lead ~= e and not IsTurntable(lead) then
        Links.Detach(e)
        lead = e
    end
    local at = now()
    if lead.vinyl then
        Vinyl.Return(lead, src, e.id)
        if needle(lead) then at = at + math.floor(SWAP_DELAY * 1000) end
    end
    lead.track, lead.playing, lead.pos = nil, false, 0
    lead.vinyl = {
        item = item, owner = Bridge.GetIdentifier(src), ownerSrc = src, idx = 1,
        by = src, at = at, on = e.id,
    }
    lead.queue = {}
    Notify(src, 'vinyl_on', 'success')
    Vinyl.PlayIndex(lead, 1, 'insert')
    return true
end

RegisterNetEvent(RES .. ':vinyl:insert', function(id, item)
    local src = source
    if type(item) ~= 'string' or tooSoon(src, id) then return end
    local e = Guard(src, id, true)
    if e and IsTurntable(e) and Vinyl.Insert(src, e, item) then changed(src, id) end
end)

RegisterNetEvent(RES .. ':vinyl:eject', function(id)
    local src = source
    if tooSoon(src, id) then return end
    local e = Guard(src, id, true)
    if not e then return end
    local lead = Links and Links.Leader(e) or e
    if not lead.vinyl then return end
    Vinyl.Return(lead, src, e.id)
    changed(src, id)
    Notify(src, 'vinyl_off', 'inform')
    push(lead)
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

---------------------------------------------------------------- import
local function slugify(s)
    s = tostring(s):lower():gsub('[^%w]+', '')
    return s:sub(1, 24)
end

-- link: a Spotify album/playlist link or a YouTube playlist link
function Vinyl.Import(link, src)
    local data
    if tostring(link):find('spotify') then
        local d, err = Spotify.Import(link)
        if not d then return nil, err end
        data = { artist = d.artist, album = d.title, year = d.year, cover = d.cover, tracks = {} }
        for i, t in ipairs(d.tracks) do data.tracks[i] = { title = t.title, search = t.search } end
    else
        local d, err = Search.Playlist(link)
        if not d then return nil, err end
        data = { artist = d.title or 'Playlist', album = d.title or 'Playlist', tracks = {} }
        for i, t in ipairs(d.tracks) do data.tracks[i] = { title = t.title, id = t.id } end
    end
    if #data.tracks == 0 then return nil, 'resolve_failed' end

    local item = 'vinyl_' .. slugify(data.album)
    -- importing a record again keeps what the shop knows about it
    local old = Records[item]
    if old then data.genre, data.price, data.description = old.genre, old.price, old.description end
    saveRecord(item, data)
    Vinyl.RegisterItems()
    return item, data
end

RegisterCommand('vinylimport', function(src, args)
    if not Bridge.IsAdmin(src) then return Notify(src, 'no_permission') end
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
        print(('[speaker] imported "%s - %s" as item %s (%d tracks). Add that item to your inventory.')
            :format(data.artist, data.album, item, #data.tracks))
        if src ~= 0 then
            Notify(src, 'vinyl_imported', 'success', data.album, item)
            Log('Record imported', ('**%s** imported `%s` — %s, %d tracks'):format(GetPlayerName(src), item, data.album, #data.tracks))
        end
    end)
end, false)

RegisterCommand('vinyllist', function(src)
    if not Bridge.IsAdmin(src) then return Notify(src, 'no_permission') end
    local rows = {}
    for item, a in pairs(Records) do
        rows[#rows + 1] = ('%-28s %s - %s (%d tracks)%s'):format(item, a.artist, a.album, #a.tracks, a.custom and ' [imported]' or '')
    end
    table.sort(rows)
    print('[speaker] records:\n' .. table.concat(rows, '\n'))
    if src ~= 0 then Notify(src, 'vinyl_listed', 'inform', #rows) end
end, false)

RegisterCommand('vinyldelete', function(src, args)
    if not Bridge.IsAdmin(src) then return Notify(src, 'no_permission') end
    local item = args[1]
    if not item or not Records[item] then return print('[speaker] no such record') end
    if not Records[item].custom then return print('[speaker] that record comes from vinyls.lua, edit the file instead') end
    MySQL.query.await('DELETE FROM nayzeee_speaker_vinyls WHERE item = ?', { item })
    -- an import that replaced a vinyls.lua record leaves the original behind
    local base = Config.Vinyls and Config.Vinyls[item]
    Records[item] = base and normalise(item, base) or nil
    print(('[speaker] removed %s%s'):format(item, base and ' (the vinyls.lua version is back)' or ''))
end, false)

exports('ImportRecord', function(link) return Vinyl.Import(link, 0) end)
exports('GetRecords', function() return Records end)
