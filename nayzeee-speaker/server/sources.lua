--[[
    Where a song's audio actually comes from.

    'file'   → a real audio file the game can process: 3D direction, muffling, echo, doppler and EQ all work.
    'iframe' → YouTube's embedded player: it plays, but the browser will not let us touch the sound,
               so only volume works. This is the fallback when no file source is reachable.
]]
Sources = {}

local cache = {}            -- video id -> { url = ..., at = ... }
local FILE_TTL = 3 * 3600   -- signed links from public instances expire; re-resolve regularly
local dead = {}             -- instance -> time it failed, so we stop hammering a dead host

local function http(url, headers, timeout)
    local p = promise.new()
    local done = false
    PerformHttpRequest(url, function(code, body, h)
        if done then return end
        done = true
        p:resolve({ code = code, body = body, headers = h })
    end, 'GET', '', headers or {})
    SetTimeout(timeout or 8000, function()
        if done then return end
        done = true
        p:resolve({ code = 0 })
    end)
    return Citizen.Await(p)
end
Sources.Http = http

local function alive(host)
    local t = dead[host]
    if t and os.time() - t < 300 then return false end
    return true
end

local function fail(host)
    dead[host] = os.time()
    NZ.Debug('audio source down:', host)
end

---------------------------------------------------------------- own API
local function viaOwnApi(id)
    local base = (Config.Audio.apiUrl or ''):gsub('/+$', '')
    if base == '' then return nil end
    local r = http(('%s/resolve?id=%s'):format(base, id), { ['x-api-key'] = Config.Audio.apiKey or '' }, 20000)
    if r.code == 413 then return nil, 'too_long' end
    if r.code ~= 200 or not r.body then return nil end
    local ok, d = pcall(json.decode, r.body)
    if not ok or not d or not d.ok or not d.stream then return nil end
    return { url = d.stream, title = d.title, author = d.author, duration = tonumber(d.duration) or 0, thumb = d.thumbnail }
end

---------------------------------------------------------------- Invidious
-- /api/v1/videos/<id> lists adaptiveFormats; we want the smallest audio-only stream.
local function viaInvidious(host, id)
    local r = http(('%s/api/v1/videos/%s?fields=title,author,lengthSeconds,adaptiveFormats'):format(host, id),
        { ['Accept'] = 'application/json' }, 9000)
    if r.code ~= 200 or not r.body then fail(host) return nil end
    local ok, d = pcall(json.decode, r.body)
    if not ok or type(d) ~= 'table' or not d.adaptiveFormats then fail(host) return nil end
    local best
    for _, f in ipairs(d.adaptiveFormats) do
        local t = f.type or ''
        if t:find('audio') and f.url then
            local br = tonumber(f.bitrate) or 0
            -- prefer opus/webm around 128k; fall back to whatever audio exists
            if not best or (br > (best.br or 0) and br <= 160000) then best = { url = f.url, br = br } end
        end
    end
    if not best then fail(host) return nil end
    return {
        url = best.url, title = d.title, author = d.author,
        duration = tonumber(d.lengthSeconds) or 0,
        thumb = ('https://i.ytimg.com/vi/%s/hqdefault.jpg'):format(id),
    }
end

---------------------------------------------------------------- Piped
local function viaPiped(host, id)
    local r = http(('%s/streams/%s'):format(host, id), { ['Accept'] = 'application/json' }, 9000)
    if r.code ~= 200 or not r.body then fail(host) return nil end
    local ok, d = pcall(json.decode, r.body)
    if not ok or type(d) ~= 'table' or not d.audioStreams then fail(host) return nil end
    local best
    for _, f in ipairs(d.audioStreams) do
        local br = tonumber(f.bitrate) or 0
        if f.url and (not best or (br > best.br and br <= 160000)) then best = { url = f.url, br = br } end
    end
    if not best then fail(host) return nil end
    return {
        url = best.url, title = d.title, author = d.uploader,
        duration = tonumber(d.duration) or 0,
        thumb = ('https://i.ytimg.com/vi/%s/hqdefault.jpg'):format(id),
    }
end

---------------------------------------------------------------- public entry
-- Returns a table with url/title/author/duration/thumb, or nil (then we fall back to the embed).
function Sources.File(id)
    local mode = Config.Audio.source
    if mode == 'iframe' then return nil end

    local hit = cache[id]
    if hit and os.time() - hit.at < FILE_TTL then return hit.data end

    local got, err = viaOwnApi(id)
    if err == 'too_long' then return nil, 'too_long' end

    if not got and mode ~= 'api' then
        for _, host in ipairs(Config.Audio.instances or {}) do
            host = host:gsub('/+$', '')
            if alive(host) then
                local kind = host:find('piped') and 'piped' or nil
                local res = kind == 'piped' and viaPiped(host, id) or viaInvidious(host, id)
                if not res and kind ~= 'piped' then res = viaPiped(host, id) end
                if res then got = res break end
            end
        end
    end

    if got then cache[id] = { data = got, at = os.time() } end
    return got
end

-- A link the game can stream and process directly (mp3/ogg/etc) is already a file source.
function Sources.IsDirect(url)
    return type(url) == 'string' and url:match('^https://') ~= nil
end

function Sources.Clear() cache = {} dead = {} end
