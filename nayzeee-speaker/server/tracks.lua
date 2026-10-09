Tracks = {}

local meta = {}            -- video id -> { track = ..., at = ... }
local META_TTL = 6 * 3600

local function urldecode(s)
    return (s:gsub('+', ' '):gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- title / channel / thumbnail without needing an audio source
local function oembed(id)
    local r = Sources.Http(('https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=%s'):format(id), nil, 8000)
    if r.code ~= 200 or not r.body then return nil end
    local ok, d = pcall(json.decode, r.body)
    if not ok or not d then return nil end
    return d.title, d.author_name
end

-- Returns track or nil, errorKey
function Tracks.Resolve(input)
    local kind, value = NZ.ParseInput(input)
    if not kind then return nil, 'invalid_input' end

    if kind == 'url' then
        if not Config.DirectLinks then return nil, 'direct_disabled' end
        local file = value:match('([^/%?#]+)%.%w+[%?#]?[^/]*$') or 'Audio'
        return {
            mode = 'file', src = 'url', id = nil, url = value,
            title = urldecode(file):gsub('[_%-]+', ' '),
            author = value:match('^https://([^/%?#]+)') or 'Link',
            duration = 0, thumb = nil,
        }
    end

    local hit = meta[value]
    if hit and os.time() - hit.at < META_TTL then
        local t = copy(hit.track)
        -- the audio link itself expires sooner than the title does, so re-check it
        if t.mode == 'file' then
            local f = Sources.File(value)
            if f and f.url then t.url = f.url else t.mode, t.url = 'iframe', nil end
        end
        return t
    end

    local file, err = Sources.File(value)
    if err == 'too_long' then return nil, 'too_long' end

    local track
    if file and file.url then
        track = {
            mode = 'file', src = 'yt', id = value, url = file.url,
            title = file.title or value, author = file.author or 'YouTube',
            duration = tonumber(file.duration) or 0,
            thumb = file.thumb or ('https://i.ytimg.com/vi/%s/hqdefault.jpg'):format(value),
        }
    else
        local title, author = oembed(value)
        if not title and Config.Audio.source == 'api' then return nil, 'resolve_failed' end
        track = {
            mode = 'iframe', src = 'yt', id = value, url = nil,
            title = title or value, author = author or 'YouTube',
            duration = 0,
            thumb = ('https://i.ytimg.com/vi/%s/hqdefault.jpg'):format(value),
        }
    end

    if Config.Limits.maxDuration > 0 and track.duration > Config.Limits.maxDuration then
        return nil, 'too_long'
    end
    meta[value] = { track = copy(track), at = os.time() }
    return track
end

-- A favorite / recent / playlist entry replayed from the UI
function Tracks.FromSaved(saved)
    if type(saved) ~= 'table' then return nil, 'invalid_input' end
    if saved.src == 'url' and type(saved.url) == 'string' then return Tracks.Resolve(saved.url) end
    if type(saved.id) == 'string' then return Tracks.Resolve(saved.id) end
    if type(saved.search) == 'string' then
        local hitId = Search.Song(saved.search)
        if hitId then return Tracks.Resolve(hitId) end
        return nil, 'resolve_failed'
    end
    return nil, 'invalid_input'
end

function Tracks.Forget(id) meta[id] = nil end
