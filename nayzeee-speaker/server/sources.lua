--[[
    Where a song's audio actually comes from.

    'file'   → a real audio file the game can process: 3D direction, muffling, echo, doppler and EQ all work.
    'iframe' → YouTube's embedded player: it plays, but the browser will not let us touch the sound,
               so only volume works. This is the fallback when no file source is reachable.
]]
Sources = {}

local files = NZ.Cache(3 * 3600)    -- video id -> stream; signed links from public instances expire, so re-resolve
local DOWN_FOR = 300                -- seconds a failing host is skipped
local noStream, noAnswer = {}, {}   -- host -> os.time() it last failed to give a stream / didn't answer at all

local function recent(t) return t ~= nil and os.time() - t < DOWN_FOR end

-- One HTTP request that waits for its answer (or `timeout` ms): { code, body, headers }. code 0 = no answer.
function Sources.Http(url, headers, timeout, method, body)
    local p, done = promise.new(), false
    PerformHttpRequest(url, function(code, res, h)
        if done then return end
        done = true
        p:resolve({ code = code, body = res, headers = h })
    end, method or 'GET', body or '', headers or {})
    SetTimeout(timeout or 8000, function()
        if done then return end
        done = true
        p:resolve({ code = 0 })
    end)
    return Citizen.Await(p)
end

--[[
    Config.Audio.instances worth asking right now. Search uses them too, so a host that only fails to
    give streams (common: YouTube blocks the extraction, search still works) is only skipped for
    streams; one that doesn't answer at all (a 9 s timeout every time) is skipped by everything.
]]
function Sources.Hosts(streams)
    local out = {}
    for _, host in ipairs(Config.Audio.instances or {}) do
        host = host:gsub('/+$', '')
        if not recent(noAnswer[host]) and not (streams and recent(noStream[host])) then out[#out + 1] = host end
    end
    return out
end

function Sources.NoAnswer(host)
    noAnswer[host] = os.time()
    NZ.Debug('audio source not answering:', host)
end

local function getJson(url, headers, timeout)
    local r = Sources.Http(url, headers, timeout)
    if r.code ~= 200 or not r.body then return nil, r.code end
    local ok, d = pcall(json.decode, r.body)
    if not ok or type(d) ~= 'table' then return nil, r.code end
    return d, r.code
end

local function thumb(id) return ('https://i.ytimg.com/vi/%s/hqdefault.jpg'):format(id) end

-- the best audio stream at or under 160 kbps (opus around 128k), else the smallest one there is
local function pickAudio(list, isAudio)
    local best
    for _, f in ipairs(list) do
        if type(f) == 'table' and f.url and isAudio(f) then
            local br = tonumber(f.bitrate) or 0
            local fits = br <= 160000
            if not best or (fits and (not best.fits or br > best.br)) or (not fits and not best.fits and br < best.br) then
                best = { url = f.url, br = br, fits = fits }
            end
        end
    end
    return best
end

---------------------------------------------------------------- own API
local function viaOwnApi(id)
    local base = (Config.Audio.apiUrl or ''):gsub('/+$', '')
    if base == '' or recent(noAnswer[base]) then return nil end
    local d, code = getJson(('%s/resolve?id=%s'):format(base, id), { ['x-api-key'] = Config.Audio.apiKey or '' }, 20000)
    if code == 413 then return nil, 'too_long' end
    if code == 0 then Sources.NoAnswer(base) end   -- don't make every song wait 20 s on it
    if not d or not d.ok or not d.stream then return nil end
    return { url = d.stream, title = d.title, author = d.author, duration = tonumber(d.duration) or 0, thumb = d.thumbnail }
end

---------------------------------------------------------------- Invidious / Piped
-- a stream, or nil + the HTTP code (0 = no answer)

-- /api/v1/videos/<id> lists adaptiveFormats; we want an audio-only stream
local function viaInvidious(host, id)
    local d, code = getJson(('%s/api/v1/videos/%s?fields=title,author,lengthSeconds,adaptiveFormats'):format(host, id),
        { ['Accept'] = 'application/json' }, 9000)
    local best = d and type(d.adaptiveFormats) == 'table'
        and pickAudio(d.adaptiveFormats, function(f) return tostring(f.type or ''):find('audio') ~= nil end)
    if not best then return nil, code end
    return { url = best.url, title = d.title, author = d.author, duration = tonumber(d.lengthSeconds) or 0, thumb = thumb(id) }
end

local function viaPiped(host, id)
    local d, code = getJson(('%s/streams/%s'):format(host, id), { ['Accept'] = 'application/json' }, 9000)
    local best = d and type(d.audioStreams) == 'table' and pickAudio(d.audioStreams, function() return true end)
    if not best then return nil, code end
    return { url = best.url, title = d.title, author = d.uploader, duration = tonumber(d.duration) or 0, thumb = thumb(id) }
end

---------------------------------------------------------------- public entry
-- A table with url / title / author / duration / thumb, or nil (then the embed is used) [, 'too_long'].
function Sources.File(id)
    local mode = Config.Audio.source
    if mode == 'iframe' then return nil end

    local hit = files.get(id)
    if hit then return hit end

    local got, err = viaOwnApi(id)
    if err == 'too_long' then return nil, 'too_long' end

    if not got and mode ~= 'api' then
        for _, host in ipairs(Sources.Hosts(true)) do
            -- a Piped host only speaks Piped; anything else is tried as Invidious first
            -- (no answer at all = don't wait for a second timeout)
            local code
            if host:find('piped') then got, code = viaPiped(host, id)
            else
                got, code = viaInvidious(host, id)
                if not got and (code or 0) ~= 0 then got, code = viaPiped(host, id) end
            end
            if got then break end
            noStream[host] = os.time()
            if (code or 0) == 0 then Sources.NoAnswer(host) end
        end
    end

    if got then files.set(id, got) end
    return got
end
