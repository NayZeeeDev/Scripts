--[[ Live channels (config + M3U playlists such as Pluto TV) and Plex libraries ]]

Channels = { list = {} }

-- ─── M3U channel playlists ─────────────────────────────────────
local function attr(line, name) return line:match(name .. '="([^"]*)"') end

local function parseM3U(body, src)
    local out, pending = {}, nil
    for raw in body:gmatch('[^\r\n]+') do
        local line = Utils.trim(raw)
        if line:find('^#EXTINF') then
            pending = {
                name  = line:match(',%s*(.-)%s*$') or 'Channel',
                thumb = attr(line, 'tvg%-logo'),
                group = attr(line, 'group%-title'),
            }
        elseif pending and line ~= '' and not line:find('^#') then
            local okGroup = not src.groups or (pending.group and src.groups[pending.group])
            if okGroup and line:match('^https?://') then
                pending.url = line
                pending.brand = src.brand
                out[#out + 1] = pending
                if #out >= (src.max or 200) then break end
            end
            pending = nil
        end
    end
    return out
end

local function httpGet(url, timeout)
    local p = promise.new()
    PerformHttpRequest(url, function(status, body) p:resolve({ status = status, body = body }) end, 'GET', '', { ['User-Agent'] = 'Mozilla/5.0 nayzeee_tv/1.0' })
    SetTimeout(timeout or 8000, function() if p.state == 0 then p:resolve({ status = 0 }) end end)
    return Citizen.Await(p)
end

function Channels.refresh()
    local list = {}
    for _, c in ipairs(Config.Channels) do
        list[#list + 1] = { name = c.name, url = c.url, thumb = c.thumb, brand = c.brand, group = c.group }
    end
    for _, src in ipairs(ServerConfig.ChannelPlaylists or {}) do
        local res = httpGet(src.url)
        if res.status == 200 and res.body then
            local got = parseM3U(res.body, src)
            for _, c in ipairs(got) do list[#list + 1] = c end
            print(('^2[nayzeee_tv]^7 %s: ^5%d^7 channels'):format(src.name or src.url, #got))
        else
            print(('^3[nayzeee_tv]^7 channel playlist failed (%s): %s'):format(tostring(res.status), src.name or src.url))
        end
    end
    for i, c in ipairs(list) do c.number = i end
    Channels.list = list
    TriggerClientEvent('nztv:channels', -1, list)
end

AddEventHandler('nztv:bridgeReady', function()
    CreateThread(function()
        Channels.refresh()
        while true do
            Wait((ServerConfig.ChannelRefreshHours or 6) * 3600000)
            Channels.refresh()
        end
    end)
end)

-- ─── Plex Media Server ─────────────────────────────────────────
local P = ServerConfig.Plex or {}
local plexCache = {}

function Channels.plexEnabled() return P.Enabled == true and (P.Token or '') ~= '' end

local function plexGet(path)
    local sep = path:find('?', 1, true) and '&' or '?'
    local url = P.Url:gsub('/$', '') .. path .. sep .. 'X-Plex-Token=' .. P.Token
    local p = promise.new()
    PerformHttpRequest(url, function(status, body) p:resolve({ status = status, body = body }) end, 'GET', '',
        { ['Accept'] = 'application/json', ['X-Plex-Product'] = 'NAYZEEE TV', ['X-Plex-Client-Identifier'] = 'nayzeee_tv' })
    SetTimeout(6000, function() if p.state == 0 then p:resolve({ status = 0 }) end end)
    local res = Citizen.Await(p)
    if res.status ~= 200 or not res.body then return nil end
    local ok, data = pcall(json.decode, res.body)
    return ok and data and data.MediaContainer or nil
end

local function public() return ((P.PublicUrl or '') ~= '' and P.PublicUrl or P.Url):gsub('/$', '') .. '' end

local function plexItem(m)
    local title = m.title
    if m.type == 'episode' then
        title = ('%s · S%02dE%02d · %s'):format(m.grandparentTitle or '', tonumber(m.parentIndex) or 0, tonumber(m.index) or 0, m.title or '')
    end
    local thumbPath = m.thumb or m.grandparentThumb
    local url
    if P.Transcode then
        -- universal HLS: plays anything the server can transcode; each TV adds its own session id
        url = ('%s/video/:/transcode/universal/start.m3u8?path=%s&protocol=hls&directPlay=0&directStream=1&fastSeek=1&mediaIndex=0&partIndex=0&videoQuality=%d&maxVideoBitrate=%d&X-Plex-Product=NAYZEEE%%20TV&X-Plex-Platform=Chrome&X-Plex-Token=%s')
            :format(public(), (('/library/metadata/' .. m.ratingKey):gsub('/', '%%2F')), 100, P.MaxBitrate or 8000, P.Token)
    else
        local part = m.Media and m.Media[1] and m.Media[1].Part and m.Media[1].Part[1]
        if not part then return nil end
        url = public() .. part.key .. '?X-Plex-Token=' .. P.Token
    end
    return {
        url = url, title = title, kind = 'plex', brand = 'plex',
        thumb = thumbPath and ('%s/photo/:/transcode?width=480&height=270&minSize=1&url=%s&X-Plex-Token=%s'):format(public(), (thumbPath:gsub('/', '%%2F')), P.Token) or nil,
        sub = m.year and tostring(m.year) or m.librarySectionTitle, duration = m.duration and math.floor(m.duration / 1000) or nil,
    }
end

RPC.plex = function(src, op, data)
    if not Channels.plexEnabled() then return false, 'plex_disabled' end
    local key = op .. ':' .. tostring(data)
    if plexCache[key] and plexCache[key].t > os.time() then return plexCache[key].r end
    local out
    if op == 'sections' then
        local c = plexGet('/library/sections')
        if not c then return false, 'plex_offline' end
        out = {}
        for _, d in ipairs(c.Directory or {}) do
            if (d.type == 'movie' or d.type == 'show') and (not P.Sections or P.Sections[d.title]) then
                out[#out + 1] = { key = d.key, title = d.title, type = d.type }
            end
        end
    elseif op == 'items' or op == 'recent' then
        local path
        if op == 'recent' then
            path = '/library/recentlyAdded?X-Plex-Container-Start=0&X-Plex-Container-Size=' .. (P.Limit or 60)
        else
            local sec = tostring(data or ''):match('^%d+$')
            if not sec then return false end
            path = ('/library/sections/%s/all?sort=addedAt:desc&X-Plex-Container-Start=0&X-Plex-Container-Size=%d'):format(sec, P.Limit or 60)
        end
        local c = plexGet(path)
        if not c then return false, 'plex_offline' end
        out = {}
        for _, m in ipairs(c.Metadata or {}) do
            if m.type == 'movie' or m.type == 'episode' then
                local it = plexItem(m)
                if it then out[#out + 1] = it end
            end
        end
    else
        return false
    end
    plexCache[key] = { t = os.time() + 120, r = out }
    return out
end
