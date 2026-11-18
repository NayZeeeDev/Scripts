Utils = {}

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
Utils.trim = trim

function Utils.round(n, d)
    local m = 10 ^ (d or 0)
    return math.floor(n * m + 0.5) / m
end

function Utils.clamp(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end

function Utils.copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Utils.copy(v) end
    return o
end

local charset = '0123456789abcdefghijklmnopqrstuvwxyz'
function Utils.id(len)
    local out = {}
    for i = 1, len or 8 do
        local r = math.random(1, #charset)
        out[i] = charset:sub(r, r)
    end
    return table.concat(out)
end

-- "1h2m3s", "90", "1:30" → seconds
local function parseTime(t)
    if not t or t == '' then return 0 end
    if t:match('^%d+$') then return tonumber(t) end
    local h = tonumber(t:match('(%d+)h')) or 0
    local m = tonumber(t:match('(%d+)m')) or 0
    local s = tonumber(t:match('(%d+)s')) or 0
    if h + m + s > 0 then return h * 3600 + m * 60 + s end
    local a, b = t:match('^(%d+):(%d+)$')
    if a then return tonumber(a) * 60 + tonumber(b) end
    return 0
end

local function query(url, key)
    return url:match('[?&#]' .. key .. '=([^&#]+)')
end

local function hostOf(url)
    local host = url:match('^%a[%w+.-]*://([^/?#:]+)')
    return host and host:lower():gsub('^www%.', '') or nil
end
Utils.host = hostOf

local function ext(url)
    local path = url:match('^[^?#]+') or url
    local e = path:match('%.(%w+)$')
    return e and e:lower() or nil
end

local VIDEO = { mp4 = true, webm = true, ogv = true, mov = true, m4v = true }
local AUDIO = { mp3 = true, wav = true, ogg = true, m4a = true, aac = true, flac = true, opus = true }
local IMAGE = { png = true, jpg = true, jpeg = true, gif = true, webp = true, avif = true }

--- Detect what a link is. Returns a descriptor table or nil, reason.
function Utils.parseMedia(raw)
    if type(raw) ~= 'string' then return nil, 'invalid_url' end
    local url = trim(raw)
    if url == '' or #url > (Config.Media.MaxUrlLength or 512) then return nil, 'invalid_url' end

    -- local library: "local:file.mp4"
    local localFile = url:match('^local:(.+)$')
    if localFile then
        if not Config.Media.Local then return nil, 'blocked_url' end
        if localFile:find('%.%.') or localFile:find('[\\/]') then return nil, 'invalid_url' end
        local e = ext(localFile)
        local kind = (IMAGE[e] and 'image') or (AUDIO[e] and 'audio') or 'video'
        return { kind = kind, src = 'local', file = localFile, url = url }
    end

    if not url:match('^https?://') then
        -- bare twitch/kick/youtube channel shortcuts typed on the remote keyboard
        if url:match('^[%w_.-]+%.[%a]+/') then url = 'https://' .. url else return nil, 'invalid_url' end
    end

    local host = hostOf(url)
    if not host then return nil, 'invalid_url' end
    for _, b in ipairs(Config.Media.Blacklist or {}) do
        if host == b or host:sub(-#b - 1) == '.' .. b then return nil, 'blocked_url' end
    end

    -- YouTube
    if host:find('youtube%.com$') or host == 'youtu.be' or host == 'youtube-nocookie.com' or host == 'm.youtube.com' then
        if not Config.Media.YouTube then return nil, 'blocked_url' end
        local id = query(url, 'v')
            or url:match('youtu%.be/([%w_-]+)')
            or url:match('/shorts/([%w_-]+)')
            or url:match('/live/([%w_-]+)')
            or url:match('/embed/([%w_-]+)')
        local list = query(url, 'list')
        if id and #id ~= 11 then id = id:sub(1, 11) end
        if not id and not list then return nil, 'invalid_url' end
        local start = parseTime(query(url, 't') or query(url, 'start'))
        return {
            kind = 'youtube', src = 'youtube', id = id, list = list, start = start, url = url,
            thumb = id and ('https://i.ytimg.com/vi/' .. id .. '/hqdefault.jpg') or nil,
        }
    end

    -- Twitch
    if host == 'twitch.tv' or host == 'm.twitch.tv' or host == 'clips.twitch.tv' or host == 'player.twitch.tv' then
        if not Config.Media.Twitch then return nil, 'blocked_url' end
        local video = url:match('/videos/(%d+)') or query(url, 'video')
        if video then
            video = video:gsub('^v', '')
            return { kind = 'twitch', src = 'twitch', video = video, start = parseTime(query(url, 't')), url = url }
        end
        local clip = (host == 'clips.twitch.tv' and url:match('clips%.twitch%.tv/([%w_-]+)')) or url:match('/clip/([%w_-]+)')
        if clip then return { kind = 'twitch', src = 'twitch', clip = clip, url = url } end
        local channel = query(url, 'channel') or url:match('twitch%.tv/([%w_]+)')
        if not channel then return nil, 'invalid_url' end
        channel = channel:lower()
        return {
            kind = 'twitch', src = 'twitch', channel = channel, live = true, url = url,
            thumb = 'https://static-cdn.jtvnw.net/previews-ttv/live_user_' .. channel .. '-640x360.jpg',
            title = channel,
        }
    end

    -- Kick
    if host == 'kick.com' or host == 'player.kick.com' then
        if not Config.Media.Kick then return nil, 'blocked_url' end
        local channel = url:match('kick%.com/([%w_-]+)')
        if not channel then return nil, 'invalid_url' end
        return { kind = 'kick', src = 'kick', channel = channel:lower(), live = true, url = url, title = channel }
    end

    -- Direct files / streams
    if not Config.Media.Direct then return nil, 'blocked_url' end
    if Config.Media.Whitelist then
        local ok = false
        for _, w in ipairs(Config.Media.Whitelist) do
            if host == w or host:sub(-#w - 1) == '.' .. w then ok = true break end
        end
        if not ok then return nil, 'blocked_url' end
    end

    local e = ext(url)
    if e == 'm3u8' then return { kind = 'hls', src = 'direct', url = url, live = nil } end
    if VIDEO[e] then return { kind = 'video', src = 'direct', url = url } end
    if AUDIO[e] then return { kind = 'audio', src = 'direct', url = url } end
    if IMAGE[e] then
        if not Config.Media.Images then return nil, 'blocked_url' end
        return { kind = 'image', src = 'direct', url = url }
    end
    return nil, 'invalid_url'
end

--- Pretty name for a descriptor when no title has been reported yet.
function Utils.fallbackTitle(m)
    if not m then return 'Nothing playing' end
    if m.title and m.title ~= '' then return m.title end
    if m.kind == 'twitch' then return m.channel or (m.video and ('Twitch VOD ' .. m.video)) or 'Twitch clip' end
    if m.kind == 'kick' then return m.channel end
    if m.src == 'local' then return m.file end
    if m.kind == 'youtube' then return m.list and not m.id and 'YouTube playlist' or 'YouTube video' end
    local file = (m.url or ''):match('([^/?#]+)[?#]?[^/]*$')
    return file or m.url
end
