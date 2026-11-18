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

    -- whatever a YouTube channel is streaming right now: "ytlive:<channel id>"
    local ytChannel = url:match('^ytlive:([%w_-]+)$')
    if ytChannel then
        if Config.Media.YouTube == false then return nil, 'blocked_url' end
        return { kind = 'youtube', src = 'youtube', liveChannel = ytChannel, live = true, url = url, start = 0 }
    end

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

    local M = Config.Media
    local function on(flag) return flag ~= false end

    -- TikTok — tiktok.com/@user/video/ID · vm.tiktok.com/CODE · tiktok.com/t/CODE (short links resolved on the server)
    if host == 'tiktok.com' or host == 'm.tiktok.com' or host == 'vm.tiktok.com' or host == 'vt.tiktok.com' then
        if not on(M.TikTok) then return nil, 'blocked_url' end
        local id = url:match('/video/(%d+)') or url:match('/player/v1/(%d+)') or url:match('/embed/v2/(%d+)')
        if not id and not (host:find('^v[mt]%.') or url:find('/t/')) then return nil, 'invalid_url' end
        return { kind = 'tiktok', src = 'tiktok', id = id, url = url, short = id == nil }
    end

    -- Vimeo — vimeo.com/ID[/HASH] · player.vimeo.com/video/ID?h=HASH
    if host == 'vimeo.com' or host == 'player.vimeo.com' then
        if not on(M.Vimeo) then return nil, 'blocked_url' end
        local id = url:match('vimeo%.com/video/(%d+)') or url:match('vimeo%.com/(%d+)') or url:match('vimeo%.com/channels/[%w_-]+/(%d+)')
        if not id then return nil, 'invalid_url' end
        local hash = query(url, 'h') or url:match('vimeo%.com/%d+/(%x+)')
        return { kind = 'vimeo', src = 'vimeo', id = id, hash = hash, url = url, start = parseTime((url:match('#t=([%w]+)'))) }
    end

    -- SoundCloud — tracks and sets
    if host == 'soundcloud.com' or host == 'm.soundcloud.com' or host == 'on.soundcloud.com' then
        if not on(M.SoundCloud) then return nil, 'blocked_url' end
        if not url:match('soundcloud%.com/[%w_-]+/[%w_-]+') and host ~= 'on.soundcloud.com' then return nil, 'invalid_url' end
        return { kind = 'soundcloud', src = 'soundcloud', url = (url:gsub('m%.soundcloud%.com', 'soundcloud.com')), set = url:find('/sets/') ~= nil }
    end

    -- Streamable — streamable.com/CODE · streamable.com/e/CODE
    if host == 'streamable.com' then
        if not on(M.Streamable) then return nil, 'blocked_url' end
        local code = url:match('streamable%.com/[eo]/([%w]+)') or url:match('streamable%.com/([%w]+)')
        if not code then return nil, 'invalid_url' end
        return { kind = 'streamable', src = 'streamable', id = code, url = url }
    end

    -- Medal — medal.tv/games/GAME/clips/ID/… · medal.tv/clip/ID
    if host == 'medal.tv' then
        if not on(M.Medal) then return nil, 'blocked_url' end
        local id = url:match('/clips?/([%w_-]+)')
        if not id then return nil, 'invalid_url' end
        return { kind = 'medal', src = 'medal', id = id, url = url }
    end

    -- Instagram — posts, reels, IGTV
    if host == 'instagram.com' then
        if not on(M.Instagram) then return nil, 'blocked_url' end
        local typ, code = url:match('instagram%.com/(%a+)/([%w_-]+)')
        if typ == 'reels' then typ = 'reel' end
        if not code or (typ ~= 'p' and typ ~= 'reel' and typ ~= 'tv') then return nil, 'invalid_url' end
        return { kind = 'instagram', src = 'instagram', id = code, ptype = typ, url = url }
    end

    -- Dailymotion — dailymotion.com/video/ID · dai.ly/ID
    if host == 'dailymotion.com' or host == 'dai.ly' then
        if not on(M.Dailymotion) then return nil, 'blocked_url' end
        local id = url:match('/video/([%w]+)') or url:match('dai%.ly/([%w]+)')
        if not id then return nil, 'invalid_url' end
        return { kind = 'dailymotion', src = 'dailymotion', id = id, url = url, start = parseTime(query(url, 'start')),
            thumb = 'https://www.dailymotion.com/thumbnail/video/' .. id }
    end

    -- Reddit — posts with video, v.redd.it links (played as HLS)
    if host == 'reddit.com' or host == 'old.reddit.com' or host == 'v.redd.it' or host == 'redd.it' then
        if not on(M.Reddit) then return nil, 'blocked_url' end
        local vid = host == 'v.redd.it' and url:match('v%.redd%.it/([%w]+)') or nil
        local post = url:match('/comments/([%w]+)') or (host == 'redd.it' and url:match('redd%.it/([%w]+)'))
        if not vid and not post then return nil, 'invalid_url' end
        return { kind = 'reddit', src = 'reddit', vid = vid, post = post, url = url,
            hls = vid and ('https://v.redd.it/' .. vid .. '/HLSPlaylist.m3u8') or nil }
    end

    -- Rumble — rumble.com/vXXXX-title.html · rumble.com/embed/ID
    if host == 'rumble.com' then
        if not on(M.Rumble) then return nil, 'blocked_url' end
        local embed = url:match('rumble%.com/embed/([%w]+)')
        if not embed and not url:match('rumble%.com/v[%w]+') then return nil, 'invalid_url' end
        return { kind = 'rumble', src = 'rumble', embed = embed, url = url }
    end

    -- Plex's website (watch.plex.tv / app.plex.tv) only runs inside Plex's own player: it can't be embedded.
    -- Its free live channels work as a channel playlist, and your own server works through ServerConfig.Plex.
    if host == 'watch.plex.tv' or host == 'app.plex.tv' or host == 'plex.tv' then return nil, 'plex_web' end

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
    if e == 'm3u8' then
        local plexLive = host:find('plex%.tv$') ~= nil -- Plex's free live channels
        local brand = (host:find('pluto%.tv$') and 'pluto') or ((plexLive or url:find('X%-Plex%-Token') or url:find(':32400')) and 'plex') or nil
        return { kind = (brand == 'plex' and not plexLive) and 'plex' or 'hls', src = 'direct', url = url, brand = brand,
            live = (brand == 'pluto' or plexLive) or nil }
    end
    if url:find('X%-Plex%-Token') then return { kind = 'plex', src = 'direct', url = url, brand = 'plex' } end
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
    local named = { tiktok = 'TikTok video', vimeo = 'Vimeo video', soundcloud = 'SoundCloud track', streamable = 'Streamable clip',
        medal = 'Medal clip', instagram = 'Instagram post', dailymotion = 'Dailymotion video', reddit = 'Reddit video', rumble = 'Rumble video' }
    if named[m.kind] then return named[m.kind] end
    if m.src == 'local' then return m.file end
    if m.kind == 'youtube' then return m.list and not m.id and 'YouTube playlist' or 'YouTube video' end
    local file = (m.url or ''):match('([^/?#]+)[?#]?[^/]*$')
    return file or m.url
end
