--[[
    Song search. Tried in order:
      1. YouTube Data API key, if one is set (most reliable, 100 free searches/day)
      2. an Invidious / Piped instance from Config.Audio.instances
      3. the public youtube.com results page
]]
Search = {}

local cache = {}
local TTL = 12 * 3600

local function cached(key)
    local hit = cache[key]
    if hit and os.time() - hit.at < TTL then return hit.list end
end

local function store(key, list)
    cache[key] = { list = list, at = os.time() }
    return list
end

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

---------------------------------------------------------------- providers
local function viaDataApi(query, limit)
    local key = Config.Search.youtubeApiKey or ''
    if key == '' then return nil end
    local url = ('https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoCategoryId=10&maxResults=%d&q=%s&key=%s')
        :format(limit, Search.Encode(query), key)
    local r = Sources.Http(url, { ['Accept'] = 'application/json' }, 9000)
    if r.code ~= 200 then return nil end
    local ok, d = pcall(json.decode, r.body)
    if not ok or not d or not d.items then return nil end
    local out = {}
    for _, it in ipairs(d.items) do
        if it.id and it.id.videoId then
            out[#out + 1] = {
                src = 'yt', id = it.id.videoId,
                title = clean(it.snippet.title),
                author = clean(it.snippet.channelTitle),
                duration = 0,
                thumb = ('https://i.ytimg.com/vi/%s/mqdefault.jpg'):format(it.id.videoId),
            }
        end
    end
    return #out > 0 and out or nil
end

local function viaInstance(query, limit)
    for _, host in ipairs(Config.Audio.instances or {}) do
        host = host:gsub('/+$', '')
        local r = Sources.Http(('%s/api/v1/search?q=%s&type=video&page=1'):format(host, Search.Encode(query)),
            { ['Accept'] = 'application/json' }, 9000)
        if r.code == 200 and r.body then
            local ok, d = pcall(json.decode, r.body)
            if ok and type(d) == 'table' then
                local out = {}
                -- invidious returns a list; piped wraps it in .items
                local items = d.items or d
                for _, it in ipairs(items) do
                    local id = it.videoId or (type(it.url) == 'string' and it.url:match('v=([%w_%-]+)'))
                    if id and #out < limit then
                        out[#out + 1] = {
                            src = 'yt', id = id,
                            title = clean(it.title),
                            author = clean(it.author or it.uploaderName),
                            duration = tonumber(it.lengthSeconds) or tonumber(it.duration) or 0,
                            thumb = ('https://i.ytimg.com/vi/%s/mqdefault.jpg'):format(id),
                        }
                    end
                end
                if #out > 0 then return out end
            end
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
            local len = block:match('"lengthText":{[^}]-"simpleText":"(.-)"')
            out[#out + 1] = {
                src = 'yt', id = id,
                title = clean(title) ~= '' and clean(title) or id,
                author = clean(author),
                duration = hms(len),
                thumb = ('https://i.ytimg.com/vi/%s/mqdefault.jpg'):format(id),
            }
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
    query = tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #query < 2 then return {} end
    limit = math.min(tonumber(limit) or 12, 20)
    local key = query:lower() .. '|' .. limit
    local hit = cached(key)
    if hit then return hit end

    local list = viaDataApi(query, limit) or viaInstance(query, limit) or viaScrape(query, limit) or {}
    return store(key, list)
end

-- best single match, used by vinyl tracks and playlist imports
function Search.Song(query)
    local list = Search.Query(query, 3)
    return list[1] and list[1].id or nil
end

---------------------------------------------------------------- YouTube playlists
-- Returns { title = ..., tracks = { { title, id } } }
function Search.Playlist(input)
    local id = tostring(input or ''):match('[?&]list=([%w_%-]+)') or tostring(input):match('^([%w_%-]{12,})$')
    if not id then return nil, 'invalid_input' end

    local key = Config.Search.youtubeApiKey or ''
    if key ~= '' then
        local out, page, title = {}, '', nil
        for _ = 1, 4 do
            local url = ('https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&maxResults=50&playlistId=%s&key=%s%s')
                :format(id, key, page ~= '' and ('&pageToken=' .. page) or '')
            local r = Sources.Http(url, { ['Accept'] = 'application/json' }, 9000)
            if r.code ~= 200 then break end
            local ok, d = pcall(json.decode, r.body)
            if not ok or not d or not d.items then break end
            for _, it in ipairs(d.items) do
                local vid = it.snippet and it.snippet.resourceId and it.snippet.resourceId.videoId
                if vid and it.snippet.title ~= 'Private video' and it.snippet.title ~= 'Deleted video' then
                    out[#out + 1] = { title = clean(it.snippet.title), id = vid }
                    title = title or clean(it.snippet.channelTitle)
                end
            end
            page = d.nextPageToken or ''
            if page == '' then break end
        end
        if #out > 0 then return { title = title or 'Playlist', tracks = out } end
    end

    for _, host in ipairs(Config.Audio.instances or {}) do
        host = host:gsub('/+$', '')
        local r = Sources.Http(('%s/api/v1/playlists/%s'):format(host, id), { ['Accept'] = 'application/json' }, 10000)
        if r.code == 200 and r.body then
            local ok, d = pcall(json.decode, r.body)
            if ok and type(d) == 'table' then
                local items = d.videos or d.relatedStreams
                if items then
                    local out = {}
                    for _, it in ipairs(items) do
                        local vid = it.videoId or (type(it.url) == 'string' and it.url:match('v=([%w_%-]+)'))
                        if vid then out[#out + 1] = { title = clean(it.title), id = vid } end
                    end
                    if #out > 0 then return { title = clean(d.title) or 'Playlist', tracks = out } end
                end
            end
        end
    end
    return nil, 'resolve_failed'
end
