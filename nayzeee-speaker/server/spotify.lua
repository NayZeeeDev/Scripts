--[[
    Spotify import.

    Spotify will not let anything outside its own apps play its audio, so this does NOT stream Spotify.
    What it does: read an album or playlist you paste, pull the artist + track names, and find each
    one as a song to play. So you keep your Spotify playlists, the audio comes from YouTube.

    Needs a free Spotify developer app (client id + secret) in Config.Spotify.
]]
Spotify = {}

local token, tokenAt = nil, 0

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function b64(data)
    local out, len = {}, #data
    local i = 1
    while i <= len do
        local a, b, c = data:byte(i), data:byte(i + 1), data:byte(i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or '=')
            .. (c and B64:sub(c4 + 1, c4 + 1) or '=')
        i = i + 3
    end
    return table.concat(out)
end

local function post(url, body, headers)
    local p = promise.new()
    local done = false
    PerformHttpRequest(url, function(code, res)
        if done then return end
        done = true
        p:resolve({ code = code, body = res })
    end, 'POST', body, headers)
    SetTimeout(10000, function()
        if done then return end
        done = true
        p:resolve({ code = 0 })
    end)
    return Citizen.Await(p)
end

local function auth()
    if token and os.time() - tokenAt < 3300 then return token end
    local id, secret = Config.Spotify.clientId or '', Config.Spotify.clientSecret or ''
    if id == '' or secret == '' then return nil end
    local r = post('https://accounts.spotify.com/api/token', 'grant_type=client_credentials', {
        ['Content-Type'] = 'application/x-www-form-urlencoded',
        ['Authorization'] = 'Basic ' .. b64(id .. ":" .. secret),
    })
    if r.code ~= 200 then
        NZ.Debug('spotify auth failed', r.code, r.body)
        return nil
    end
    local ok, d = pcall(json.decode, r.body)
    if not ok or not d or not d.access_token then return nil end
    token, tokenAt = d.access_token, os.time()
    return token
end

local function api(path)
    local t = auth()
    if not t then return nil, 'spotify_off' end
    local r = Sources.Http('https://api.spotify.com/v1' .. path, { ['Authorization'] = 'Bearer ' .. t }, 10000)
    if r.code ~= 200 then return nil, 'resolve_failed' end
    local ok, d = pcall(json.decode, r.body)
    if not ok then return nil, 'resolve_failed' end
    return d
end

function Spotify.Enabled()
    return (Config.Spotify.clientId or '') ~= '' and (Config.Spotify.clientSecret or '') ~= ''
end

local function parseLink(link)
    link = tostring(link or '')
    local kind, id = link:match('spotify[%.:/]+.-(album)[/:]([%w]+)')
    if not kind then kind, id = link:match('spotify[%.:/]+.-(playlist)[/:]([%w]+)') end
    if not kind then kind, id = link:match('spotify[%.:/]+.-(track)[/:]([%w]+)') end
    return kind, id
end

--[[ Returns { kind, title, artist, year, cover, tracks = { { title, search } } } ]]
function Spotify.Import(link)
    if not Spotify.Enabled() then return nil, 'spotify_off' end
    local kind, id = parseLink(link)
    if not kind or not id then return nil, 'invalid_input' end

    if kind == 'album' then
        local d, err = api('/albums/' .. id)
        if not d then return nil, err end
        local tracks = {}
        for _, t in ipairs(d.tracks and d.tracks.items or {}) do
            local artist = t.artists and t.artists[1] and t.artists[1].name or (d.artists[1] and d.artists[1].name) or ''
            tracks[#tracks + 1] = { title = t.name, search = ('%s %s'):format(artist, t.name) }
        end
        return {
            kind = 'album', title = d.name,
            artist = d.artists and d.artists[1] and d.artists[1].name or '',
            year = tonumber((d.release_date or ''):sub(1, 4)),
            cover = d.images and d.images[1] and d.images[1].url,
            tracks = tracks,
        }
    elseif kind == 'playlist' then
        local d, err = api('/playlists/' .. id .. '?fields=name,images,owner(display_name),tracks(items(track(name,artists(name))),next)')
        if not d then return nil, err end
        local tracks = {}
        for _, it in ipairs(d.tracks and d.tracks.items or {}) do
            local t = it.track
            if t and t.name then
                local artist = t.artists and t.artists[1] and t.artists[1].name or ''
                tracks[#tracks + 1] = { title = t.name, search = ('%s %s'):format(artist, t.name) }
            end
        end
        -- pages past the first 100
        local page, guard = d.tracks and d.tracks.next, 0
        while page and guard < 4 do
            guard = guard + 1
            local more = api(page:gsub('^https://api%.spotify%.com/v1', ''))
            if not more or not more.items then break end
            for _, it in ipairs(more.items) do
                local t = it.track
                if t and t.name then
                    local artist = t.artists and t.artists[1] and t.artists[1].name or ''
                    tracks[#tracks + 1] = { title = t.name, search = ('%s %s'):format(artist, t.name) }
                end
            end
            page = more.next
        end
        return {
            kind = 'playlist', title = d.name,
            artist = d.owner and d.owner.display_name or '',
            cover = d.images and d.images[1] and d.images[1].url,
            tracks = tracks,
        }
    else
        local d, err = api('/tracks/' .. id)
        if not d then return nil, err end
        local artist = d.artists and d.artists[1] and d.artists[1].name or ''
        return {
            kind = 'track', title = d.name, artist = artist,
            cover = d.album and d.album.images and d.album.images[1] and d.album.images[1].url,
            tracks = { { title = d.name, search = ('%s %s'):format(artist, d.name) } },
        }
    end
end

-- Spotify's own search, used to find cover art for the preset records
function Spotify.FindAlbum(artist, album)
    if not Spotify.Enabled() then return nil end
    local q = Search.Encode(('album:%s artist:%s'):format(album, artist))
    local d = api('/search?type=album&limit=1&q=' .. q)
    local item = d and d.albums and d.albums.items and d.albums.items[1]
    if not item then return nil end
    return {
        cover = item.images and item.images[1] and item.images[1].url,
        year = tonumber((item.release_date or ''):sub(1, 4)),
        id = item.id,
    }
end
