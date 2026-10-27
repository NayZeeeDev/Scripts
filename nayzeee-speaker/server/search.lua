--[[
    Song search. Tried in order:
      1. YouTube Data API key, if one is set (most reliable, 100 free searches/day)
      2. an Invidious / Piped instance from Config.Audio.instances
      3. the public youtube.com results page
]]
Search = {}

local results = NZ.Cache(12 * 3600)

local function clean(s)
    if type(s) ~= 'string' then return '' end
    return (s:gsub('\\u0026', '&'):gsub('\\"', '"'):gsub('\\n', ' '):gsub('&amp;', '&'):gsub('&quot;', '"'):gsub('&#39;', "'"))
end

local function hms(txt)
    if type(txt) ~= 'string' then return 0 end
    local parts = {}
    for n in txt:gmatch('%d+') do parts[#parts + 1] = tonumber(n) end
    if #parts == 2 then return parts[1] * 60 + parts[2] end
    if #parts == 3 then return parts[1] * 3600 + parts[2] * 60 + parts[3] end
    return 0
end

local function song(id, title, author, duration)
    return {
        src = 'yt', id = id, title = title ~= '' and title or id, author = author, duration = duration or 0,
        thumb = ('https://i.ytimg.com/vi/%s/mqdefault.jpg'):format(id),
    }
end

-- host = an instance: one that doesn't answer at all is skipped for a while (Sources.Hosts)
local function getJson(url, timeout, host)
    local r = Sources.Http(url, { ['Accept'] = 'application/json' }, timeout)
    if r.code == 0 and host then Sources.NoAnswer(host) end
    if r.code ~= 200 or not r.body then return nil end
    local ok, d = pcall(json.decode, r.body)
    return ok and type(d) == 'table' and d or nil
end

---------------------------------------------------------------- providers
local function viaDataApi(query, limit)
    local key = Config.Search.youtubeApiKey or ''
    if key == '' then return nil end
    local d = getJson(('https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoCategoryId=10&maxResults=%d&q=%s&key=%s')
        :format(limit, Search.Encode(query), key), 9000)
    if not d or type(d.items) ~= 'table' then return nil end
    local out = {}
    for _, it in ipairs(d.items) do
        if it.id and it.id.videoId and it.snippet then
            out[#out + 1] = song(it.id.videoId, clean(it.snippet.title), clean(it.snippet.channelTitle))
        end
    end
    return #out > 0 and out or nil
end

local function viaInstance(query, limit)
    for _, host in ipairs(Sources.Hosts()) do
        local d = getJson(('%s/api/v1/search?q=%s&type=video&page=1'):format(host, Search.Encode(query)), 9000, host)
        if d then
            local out = {}
            -- invidious returns a list; piped wraps it in .items
            for _, it in ipairs(d.items or d) do
                local id = it.videoId or (type(it.url) == 'string' and it.url:match('v=([%w_%-]+)'))
                if id and #out < limit then
                    out[#out + 1] = song(id, clean(it.title), clean(it.author or it.uploaderName),
                        tonumber(it.lengthSeconds) or tonumber(it.duration))
                end
            end
            if #out > 0 then return out end
        end
    end
end

local function viaScrape(query, limit)
    local r = Sources.Http('https://www.youtube.com/results?search_query=' .. Search.Encode(query) .. '&sp=EgIQAQ%253D%253D', {
        ['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        ['Accept-Language'] = 'en-US,en;q=0.9',
    }, 12000)
    if r.code ~= 200 or not r.body then return nil end
    local out, seen = {}, {}
    -- walk videoRenderer blocks so title / channel / length stay with the right id
    for block in r.body:gmatch('"videoRenderer":(%b{})') do
        local id = block:match('"videoId":"([%w_%-]+)"')
        if id and not seen[id] and #out < limit then
            seen[id] = true
            local title = block:match('"title":{"runs":%[{"text":"(.-)"') or block:match('"title":{"simpleText":"(.-)"')
            local author = block:match('"ownerText":{"runs":%[{"text":"(.-)"') or block:match('"longBylineText":{"runs":%[{"text":"(.-)"')
            out[#out + 1] = song(id, clean(title), clean(author), hms(block:match('"lengthText":{[^}]-"simpleText":"(.-)"')))
        end
    end
    return #out > 0 and out or nil
end

---------------------------------------------------------------- public
function Search.Encode(s)
    return (tostring(s):gsub('[^%w%-%.%_%~]', function(c)
        return ('%%%02X'):format(string.byte(c))
    end))
end

-- list of { src, id, title, author, duration, thumb }
function Search.Query(query, limit)
    query = NZ.Trim(query, 120)
    if #query < 2 then return {} end
    limit = math.floor(NZ.Clamp(limit or 12, 1, 20))
    local key = query:lower() .. '|' .. limit
    local hit = results.get(key)
    if hit then return hit end
    -- nothing found is not remembered: it is usually every provider being down for a moment
    local list = viaDataApi(query, limit) or viaInstance(query, limit) or viaScrape(query, limit)
    return list and results.set(key, list) or {}
end

-- best single match, used by records and imported playlists
function Search.Song(query)
    local list = Search.Query(query, 3)
    return list[1] and list[1].id or nil
end

-- the search box (main player and phone app)
local lastSearch = {}
NZ.RegisterCallback('search', function(src, query)
    if not Config.Search.enabled then return {} end
    local t = GetGameTimer()
    if lastSearch[src] and t - lastSearch[src] < 700 then return {} end
    lastSearch[src] = t
    return Search.Query(query, Config.Search.results)
end)

AddEventHandler('playerDropped', function() lastSearch[source] = nil end)

---------------------------------------------------------------- YouTube playlists
-- { title = ..., tracks = { { title, id } } } or nil, errorKey
function Search.Playlist(input)
    input = NZ.Trim(input)
    local id = input:match('[?&]list=([%w_%-]+)')
    if not id then
        local bare = input:match('^[%w_%-]+$')
        id = bare and #bare >= 12 and bare or nil
    end
    if not id then return nil, 'invalid_input' end

    local key = Config.Search.youtubeApiKey or ''
    if key ~= '' then
        local out, page, title = {}, '', nil
        for _ = 1, 4 do
            local d = getJson(('https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&maxResults=50&playlistId=%s&key=%s%s')
                :format(id, key, page ~= '' and ('&pageToken=' .. page) or ''), 9000)
            if not d or type(d.items) ~= 'table' then break end
            for _, it in ipairs(d.items) do
                local sn = it.snippet
                local vid = sn and sn.resourceId and sn.resourceId.videoId
                if vid and sn.title ~= 'Private video' and sn.title ~= 'Deleted video' then
                    out[#out + 1] = { title = clean(sn.title), id = vid }
                    title = title or clean(sn.channelTitle)
                end
            end
            page = d.nextPageToken or ''
            if page == '' then break end
        end
        if #out > 0 then return { title = title or 'Playlist', tracks = out } end
    end

    for _, host in ipairs(Sources.Hosts()) do
        local d = getJson(('%s/api/v1/playlists/%s'):format(host, id), 10000, host)
        local items = d and (d.videos or d.relatedStreams)
        if type(items) == 'table' then
            local out = {}
            for _, it in ipairs(items) do
                local vid = it.videoId or (type(it.url) == 'string' and it.url:match('v=([%w_%-]+)'))
                if vid then out[#out + 1] = { title = clean(it.title), id = vid } end
            end
            local title = clean(d.title)
            if #out > 0 then return { title = title ~= '' and title or 'Playlist', tracks = out } end
        end
    end
    return nil, 'resolve_failed'
end
