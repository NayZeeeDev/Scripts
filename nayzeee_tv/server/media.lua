--[[ Media engine: playback state, queue, playlists, link groups ]]

Media = {}

local MEDIA_FIELDS = { 'media', 'queue', 'loop', 'history', 'channel' }

function Media.leader(tv)
    if not tv.group then return tv end
    local best
    for _, t in pairs(TV.list) do
        if t.group == tv.group and (not best or t.id < best.id) then best = t end
    end
    return best or tv
end

function Media.position(m, now)
    if not m then return 0 end
    if m.paused then return m.pausedAt or 0 end
    return math.max(0, ((now or TV.now()) - m.startedAt) / 1000)
end

--- Run fn on every linked screen and broadcast the result.
local function apply(tv, fn, fields)
    for _, t in ipairs(TV.members(tv)) do
        fn(t)
        TV.patch(t, fields or MEDIA_FIELDS)
    end
end
Media.apply = apply

local function pushHistory(t, entry)
    for i = #t.history, 1, -1 do
        if t.history[i].url == entry.url then table.remove(t.history, i) end
    end
    table.insert(t.history, 1, entry)
    while #t.history > Config.Media.MaxHistory do table.remove(t.history) end
end

local function httpGet(url, headers, timeout)
    local p = promise.new()
    PerformHttpRequest(url, function(status, body) p:resolve({ status = status, body = body }) end, 'GET', '', headers or {})
    SetTimeout(timeout or 3500, function() if p.state == 0 then p:resolve({ status = 0 }) end end)
    return Citizen.Await(p)
end

local function resolveKick(desc)
    if not Config.Media.KickResolve then return end
    local res = httpGet('https://kick.com/api/v2/channels/' .. desc.channel, { ['Accept'] = 'application/json', ['User-Agent'] = 'Mozilla/5.0' })
    if res.status ~= 200 or not res.body then return end
    local ok, data = pcall(json.decode, res.body)
    if ok and type(data) == 'table' then
        if data.playback_url and data.playback_url ~= '' then desc.hls = data.playback_url end
        if data.livestream and type(data.livestream) == 'table' then
            desc.title = data.livestream.session_title or desc.title
            if data.livestream.thumbnail and type(data.livestream.thumbnail) == 'table' then
                desc.thumb = data.livestream.thumbnail.url or desc.thumb
            end
        end
        if data.user and data.user.username then desc.channelName = data.user.username end
    end
end

--- Build a playable media descriptor from a link.
function Media.describe(url)
    local desc, err = Utils.parseMedia(url)
    if not desc then return nil, err end
    if desc.kind == 'kick' then resolveKick(desc) end
    if desc.src == 'local' then
        for _, l in ipairs(Config.Library) do
            if l.file == desc.file then desc.title = l.title desc.thumb = l.thumb end
        end
    end
    return desc
end

function Media.start(t, desc, opts)
    local now = TV.now()
    local m = Utils.copy(desc)
    m.key       = Utils.id(6)
    m.title     = (opts and opts.title) or desc.title
    m.startedAt = now - math.floor((desc.start or 0) * 1000)
    m.paused    = false
    m.by        = opts and opts.by or nil
    m.index     = opts and opts.index or (desc.items and 1 or nil)
    t.media = m
    t.power = true
    pushHistory(t, { url = desc.url, title = m.title or Utils.fallbackTitle(m), thumb = m.thumb, kind = m.kind, by = m.by, at = os.time() })
end

function Media.play(tv, url, title, opts)
    opts = opts or {}
    local desc, err = Media.describe(url)
    if not desc then return false, err end
    local wasOff = not tv.power
    apply(tv, function(t)
        Media.start(t, desc, { title = title, by = opts.by })
    end, { 'media', 'history', 'power' })
    return true, nil, wasOff
end

function Media.stop(tv)
    apply(tv, function(t) t.media = nil end, { 'media' })
end

function Media.pause(tv)
    local now = TV.now()
    apply(tv, function(t)
        local m = t.media
        if m and not m.paused and not m.live then
            m.pausedAt = Media.position(m, now)
            m.paused = true
        end
    end, { 'media' })
end

function Media.resume(tv)
    local now = TV.now()
    apply(tv, function(t)
        local m = t.media
        if m and m.paused then
            m.startedAt = now - math.floor((m.pausedAt or 0) * 1000)
            m.paused = false
            m.pausedAt = nil
        end
    end, { 'media' })
end

function Media.seek(tv, pos)
    local now = TV.now()
    apply(tv, function(t)
        local m = t.media
        if not m or m.live then return end
        pos = math.max(0, pos)
        if m.duration then pos = math.min(pos, m.duration - 0.5) end
        if m.paused then m.pausedAt = pos else m.startedAt = now - math.floor(pos * 1000) end
    end, { 'media' })
end

--- Move a playlist forward/back, or pull from the queue.
function Media.next(tv, fromEnd)
    local leader = Media.leader(tv)
    local m = leader.media
    if m and m.items and m.index and m.index < #m.items then
        local idx = m.index + 1
        apply(tv, function(t)
            local mm = t.media
            if not mm then return end
            mm.index = idx
            mm.id = m.items[idx]
            mm.thumb = 'https://i.ytimg.com/vi/' .. mm.id .. '/hqdefault.jpg'
            mm.title, mm.duration, mm.start = nil, nil, 0
            mm.key = Utils.id(6)
            mm.startedAt = TV.now()
            mm.paused = false
        end, { 'media' })
        return true
    end
    if #leader.queue > 0 then
        local entry = table.remove(leader.queue, 1)
        local desc = Media.describe(entry.url)
        if desc then
            apply(tv, function(t)
                if t ~= leader then table.remove(t.queue, 1) end
                Media.start(t, desc, { title = entry.title, by = entry.by })
            end)
            return true
        end
    end
    if fromEnd and m and leader.loop then
        apply(tv, function(t)
            if t.media then t.media.startedAt = TV.now() t.media.paused = false t.media.key = Utils.id(6) end
        end, { 'media' })
        return true
    end
    if fromEnd then
        apply(tv, function(t) t.media = nil end, { 'media' })
    end
    return false
end

function Media.prev(tv)
    local leader = Media.leader(tv)
    local m = leader.media
    if not m then return end
    if m.items and m.index and m.index > 1 and Media.position(m) < 5 then
        local idx = m.index - 1
        apply(tv, function(t)
            local mm = t.media
            if not mm then return end
            mm.index, mm.id = idx, m.items[idx]
            mm.thumb = 'https://i.ytimg.com/vi/' .. mm.id .. '/hqdefault.jpg'
            mm.title, mm.duration = nil, nil
            mm.key = Utils.id(6)
            mm.startedAt = TV.now()
            mm.paused = false
        end, { 'media' })
    else
        Media.seek(tv, 0)
    end
end

function Media.ended(tv)
    -- a looping single item with an empty queue restarts
    local leader = Media.leader(tv)
    if leader.loop and #leader.queue == 0 and not (leader.media and leader.media.items) then
        apply(tv, function(t)
            if t.media then t.media.startedAt = TV.now() t.media.key = Utils.id(6) end
        end, { 'media' })
        return
    end
    Media.next(tv, true)
end

function Media.channel(tv, dir)
    local list = Config.Channels
    if #list == 0 then return false end
    local idx = ((tv.channel or 0) + dir - 1) % #list + 1
    local ch = list[idx]
    local ok = Media.play(tv, ch.url, ch.name, { by = 'CH ' .. (ch.number or idx) })
    if ok then apply(tv, function(t) t.channel = idx end, { 'channel' }) end
    return ok
end

-- ─── RPC: control ──────────────────────────────────────────────
local function reachable(src, tv)
    if not tv then return false, 'no_tv_near' end
    local ok, why = Perms.canControl(src, tv)
    if not ok then return false, why end
    if not Perms.inReach(src, tv) then return false, 'too_far' end
    return true
end

local Actions = {}

Actions.power = function(src, tv, v)
    local on = v
    if on == nil then on = not tv.power end
    for _, t in ipairs(TV.members(tv)) do
        t.power = on and true or false
        TV.patch(t, { 'power' })
    end
    if not on then Media.pause(tv) elseif tv.media and tv.media.paused then Media.resume(tv) end
    return true
end

Actions.play = function(src, tv, data)
    if type(data) ~= 'table' or type(data.url) ~= 'string' then return false, 'invalid_url' end
    local ok, err = Media.play(tv, data.url, data.title, { by = Bridge.name(src) })
    return ok, err
end

Actions.queue = function(src, tv, data)
    if type(data) ~= 'table' or type(data.url) ~= 'string' then return false, 'invalid_url' end
    local desc, err = Utils.parseMedia(data.url)
    if not desc then return false, err end
    if not tv.media then return Actions.play(src, tv, data) end
    if #tv.queue >= Config.Media.MaxQueue then return false, 'queue_full' end
    local entry = { url = desc.url, title = data.title or desc.title or Utils.fallbackTitle(desc), thumb = data.thumb or desc.thumb, kind = desc.kind, by = Bridge.name(src) }
    apply(tv, function(t) t.queue[#t.queue + 1] = Utils.copy(entry) end, { 'queue' })
    return true, 'added_queue'
end

Actions.pause  = function(_, tv) Media.pause(tv) return true end
Actions.resume = function(_, tv) Media.resume(tv) return true end
Actions.toggle = function(_, tv)
    if not tv.media then return false end
    if tv.media.paused then Media.resume(tv) else Media.pause(tv) end
    return true
end
Actions.seek    = function(_, tv, pos) if type(pos) == 'number' then Media.seek(tv, pos) end return true end
Actions.seekRel = function(_, tv, d) if type(d) == 'number' and tv.media then Media.seek(tv, Media.position(tv.media) + d) end return true end
Actions.stop    = function(_, tv) Media.stop(tv) return true, 'stopped' end
Actions.next    = function(_, tv) Media.next(tv, false) return true end
Actions.prev    = function(_, tv) Media.prev(tv) return true end
Actions.channel = function(_, tv, dir) return Media.channel(tv, dir == -1 and -1 or 1) end

Actions.loop = function(_, tv, v)
    local on = v
    if on == nil then on = not tv.loop end
    apply(tv, function(t) t.loop = on and true or false end, { 'loop' })
    for _, t in ipairs(TV.members(tv)) do TV.save(t) end
    return true
end

Actions.volume = function(_, tv, v)
    if type(v) ~= 'number' then return false end
    for _, t in ipairs(TV.members(tv)) do
        t.volume = Utils.clamp(v, 0.0, 1.0)
        t.muted = false
        TV.patch(t, { 'volume', 'muted' })
        TV.save(t)
    end
    return true
end

Actions.volStep = function(src, tv, d)
    return Actions.volume(src, tv, (tv.volume or 0.5) + (d == -1 and -0.05 or 0.05))
end

Actions.mute = function(_, tv)
    for _, t in ipairs(TV.members(tv)) do
        t.muted = not tv.muted
        TV.patch(t, { 'muted' })
    end
    return true
end

Actions.qRemove = function(_, tv, i)
    if type(i) ~= 'number' or not tv.queue[i] then return false end
    apply(tv, function(t) table.remove(t.queue, i) end, { 'queue' })
    return true
end

Actions.qMove = function(_, tv, data)
    if type(data) ~= 'table' then return false end
    local i, dir = data.i, data.dir
    local j = i + (dir == -1 and -1 or 1)
    if not tv.queue[i] or not tv.queue[j] then return false end
    apply(tv, function(t) t.queue[i], t.queue[j] = t.queue[j], t.queue[i] end, { 'queue' })
    return true
end

Actions.qPlay = function(src, tv, i)
    local entry = tv.queue[i]
    if not entry then return false end
    apply(tv, function(t) table.remove(t.queue, i) end, { 'queue' })
    return Actions.play(src, tv, { url = entry.url, title = entry.title })
end

Actions.qClear   = function(_, tv) apply(tv, function(t) t.queue = {} end, { 'queue' }) return true end
Actions.histClear= function(_, tv) apply(tv, function(t) t.history = {} end, { 'history' }) return true end

local PICTURE = { standard = true, vivid = true, cinema = true, warm = true, game = true }
local FIT = { contain = true, cover = true, stretch = true }
Actions.setting = function(_, tv, data)
    if type(data) ~= 'table' then return false end
    local k, v = data.key, data.value
    if k == 'picture' and not PICTURE[v] then return false end
    if k == 'fit' and not FIT[v] then return false end
    if (k == 'ambient' or k == 'osd') then v = v == true end
    if k ~= 'picture' and k ~= 'fit' and k ~= 'ambient' and k ~= 'osd' then return false end
    for _, t in ipairs(TV.members(tv)) do
        t.settings = t.settings or {}
        t.settings[k] = v
        TV.patch(t, { 'settings' })
        TV.save(t)
    end
    return true
end

RPC.control = function(src, id, action, data)
    local tv = TV.get(id)
    local ok, why = reachable(src, tv)
    if not ok then return false, why end
    local fn = Actions[action]
    if not fn then return false, 'unknown' end
    return fn(src, tv, data)
end

-- ─── reports from the in-world player (duration, title, playlists) ──
RPC.report = function(src, id, key, kind, data)
    local tv = TV.get(id)
    if not tv or not tv.media then return end
    local leader = Media.leader(tv)
    local m = leader.media
    if not m or m.key ~= key then
        -- the key of a linked member may differ; match by any member
        local found
        for _, t in ipairs(TV.members(tv)) do if t.media and t.media.key == key then found = t break end end
        if not found then return end
        leader, m = found, found.media
    end
    local pc = Perms.playerCoords(src)
    if not pc or #(pc - vector3(tv.coords.x, tv.coords.y, tv.coords.z)) > (tv.range + Config.Render.RenderPadding + 20.0) then return end

    if kind == 'duration' and type(data) == 'number' then
        if m.duration then return end
        apply(tv, function(t)
            if t.media then
                if data <= 0 then t.media.live = true else t.media.duration = data end
            end
        end, { 'media' })
    elseif kind == 'title' and type(data) == 'string' and #data < 200 then
        if m.title and m.title ~= '' then return end
        apply(tv, function(t)
            if t.media then t.media.title = data end
            if t.history[1] and t.history[1].url == m.url then t.history[1].title = data end
        end, { 'media', 'history' })
    elseif kind == 'playlist' and type(data) == 'table' then
        if m.items then return end
        local items = {}
        for i = 1, math.min(#data, 200) do
            if type(data[i]) == 'string' and #data[i] == 11 then items[#items + 1] = data[i] end
        end
        if #items == 0 then return end
        apply(tv, function(t)
            local mm = t.media
            if not mm then return end
            mm.items = items
            mm.index = mm.index or 1
            if not mm.id then
                mm.id = items[mm.index]
                mm.thumb = 'https://i.ytimg.com/vi/' .. mm.id .. '/hqdefault.jpg'
            end
        end, { 'media' })
    elseif kind == 'ended' then
        -- only trusted when we never learnt the duration
        if not m.duration and not m.live and Media.position(m) > 3 then Media.ended(tv) end
    elseif kind == 'error' then
        print(('^3[nayzeee_tv]^7 playback error on %s: %s'):format(tv.id, tostring(data)))
    end
end

-- ─── TV OS navigation relay ────────────────────────────────────
RPC.key = function(src, id, key)
    local tv = TV.get(id)
    local ok, why = reachable(src, tv)
    if not ok then return false, why end
    if type(key) ~= 'string' or #key > 16 then return false end
    tv.uiBy = src
    tv.uiSeq = (tv.uiSeq or 0) + 1
    TriggerClientEvent('nztv:key', -1, id, key, src, tv.uiSeq)
    return true
end

RPC.uiState = function(src, id, ui)
    local tv = TV.get(id)
    if not tv or tv.uiBy ~= src or type(ui) ~= 'table' then return end
    tv.ui = ui
    -- keeps every client's copy fresh so players walking in later see the same screen
    TV.patch(tv, { 'ui' })
end

-- typed text from the remote keyboard → the TV search field
RPC.type = function(src, id, text)
    local tv = TV.get(id)
    local ok, why = reachable(src, tv)
    if not ok then return false, why end
    if type(text) ~= 'string' or #text > 256 then return false end
    tv.uiBy = src
    TriggerClientEvent('nztv:typed', -1, id, text, src)
    return true
end

-- ─── favorites ─────────────────────────────────────────────────
RPC.favorites = function(src)
    return Storage.getFavorites(Bridge.identifier(src))
end

RPC.favorite = function(src, op, item)
    local ident = Bridge.identifier(src)
    local list = Utils.copy(Storage.getFavorites(ident))
    if type(item) ~= 'table' or type(item.url) ~= 'string' then return false end
    for i = #list, 1, -1 do if list[i].url == item.url then table.remove(list, i) end end
    if op == 'add' then
        if not Utils.parseMedia(item.url) then return false, 'invalid_url' end
        table.insert(list, 1, { url = item.url, title = tostring(item.title or ''):sub(1, 120), thumb = item.thumb, kind = item.kind })
        while #list > Config.Media.MaxFavorites do table.remove(list) end
    end
    Storage.setFavorites(ident, list)
    return list, op == 'add' and 'favorite_added' or 'favorite_removed'
end

-- ─── YouTube search (optional API key) ─────────────────────────
local searchCache = {}
RPC.search = function(src, q)
    if Config.Media.YouTubeApiKey == '' then return false, 'search_disabled' end
    if type(q) ~= 'string' or #q < 2 or #q > 100 then return false end
    local key = q:lower()
    if searchCache[key] and searchCache[key].t > os.time() then return searchCache[key].r end
    local url = ('https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&maxResults=18&safeSearch=moderate&q=%s&key=%s')
        :format((q:gsub('[^%w ]', function(c) return ('%%%02X'):format(c:byte()) end):gsub(' ', '+')), Config.Media.YouTubeApiKey)
    local res = httpGet(url, nil, 5000)
    if res.status ~= 200 then return false end
    local ok, data = pcall(json.decode, res.body)
    if not ok or not data or not data.items then return false end
    local out = {}
    for _, it in ipairs(data.items) do
        if it.id and it.id.videoId then
            out[#out + 1] = {
                url = 'https://www.youtube.com/watch?v=' .. it.id.videoId,
                title = it.snippet.title, channel = it.snippet.channelTitle,
                thumb = 'https://i.ytimg.com/vi/' .. it.id.videoId .. '/hqdefault.jpg', kind = 'youtube',
            }
        end
    end
    searchCache[key] = { t = os.time() + 600, r = out }
    return out
end

-- ─── panel snapshot ────────────────────────────────────────────
RPC.panel = function(src, id)
    local tv = TV.get(id)
    if not tv then return false, 'no_tv_near' end
    local canControl, why = Perms.canControl(src, tv)
    local manage = Perms.canManage(src, tv)
    if not canControl then return false, why end
    local out = {
        tv = TV.public(tv),
        canManage = manage,
        isOwner = Perms.isOwner(src, tv),
        isAdmin = Perms.isAdmin(src),
        favorites = Storage.getFavorites(Bridge.identifier(src)),
        me = Bridge.name(src),
        search = Config.Media.YouTubeApiKey ~= '',
        library = Config.Library,
        channels = Config.Channels,
    }
    if manage then
        out.perms = tv.perms
        local nearby = {}
        local c = vector3(tv.coords.x, tv.coords.y, tv.coords.z)
        for _, t in pairs(TV.list) do
            if t ~= tv and #(c - vector3(t.coords.x, t.coords.y, t.coords.z)) < 60.0 and (Perms.isAdmin(src) or t.owner == tv.owner) then
                nearby[#nearby + 1] = { id = t.id, label = t.label, group = t.group, linked = t.group ~= nil and t.group == tv.group }
            end
        end
        out.linkable = nearby
    end
    return out
end

-- ─── owner management ──────────────────────────────────────────
RPC.manage = function(src, id, op, data)
    local tv = TV.get(id)
    if not tv or not Perms.canManage(src, tv) then return false, 'no_permission' end
    if op == 'rename' and type(data) == 'string' then
        tv.label = data:sub(1, 40)
        TV.patch(tv, { 'label' })
    elseif op == 'lock' then
        tv.locked = not tv.locked
        TV.patch(tv, { 'locked' })
    elseif op == 'perms' and type(data) == 'table' then
        local p = { public = data.public == true, jobs = {}, gangs = {}, ace = nil, allowed = tv.perms and tv.perms.allowed or {} }
        for k, v in pairs(type(data.jobs) == 'table' and data.jobs or {}) do
            if type(k) == 'string' and #k < 40 then p.jobs[k] = tonumber(v) or 0 end
        end
        for k, v in pairs(type(data.gangs) == 'table' and data.gangs or {}) do
            if type(k) == 'string' and #k < 40 then p.gangs[k] = tonumber(v) or 0 end
        end
        if Perms.isAdmin(src) and type(data.ace) == 'string' and data.ace ~= '' then p.ace = data.ace:sub(1, 64) end
        tv.perms = p
        TV.patch(tv, { 'perms' })
    elseif op == 'allow' and type(data) == 'number' then
        if not GetPlayerName(data) then return false end
        tv.perms.allowed = tv.perms.allowed or {}
        tv.perms.allowed[Bridge.identifier(data)] = Bridge.name(data)
    elseif op == 'link' and type(data) == 'table' then
        local group = tv.group or ('g' .. Utils.id(6))
        tv.group = group
        local n = 1
        for _, otherId in ipairs(data) do
            local o = TV.get(otherId)
            if o and o ~= tv and (Perms.isAdmin(src) or o.owner == tv.owner) then
                o.group = group
                o.media, o.queue, o.loop, o.power = Utils.copy(tv.media), Utils.copy(tv.queue), tv.loop, tv.power
                TV.patch(o, { 'group', 'media', 'queue', 'loop', 'power' })
                TV.save(o)
                n = n + 1
            end
        end
        TV.patch(tv, { 'group' })
        TV.save(tv)
        return true, 'linked'
    elseif op == 'unlink' then
        tv.group = nil
        TV.patch(tv, { 'group' })
        TV.save(tv)
        return true, 'unlinked'
    else
        return false
    end
    TV.save(tv)
    return true, 'saved'
end

--- Relay data produced by the controller's TV OS (e.g. search results) to every screen.
RPC.osData = function(src, id, payload)
    local tv = TV.get(id)
    local ok = reachable(src, tv)
    if not ok or type(payload) ~= 'table' then return false end
    if #json.encode(payload) > 24000 then return false end
    TriggerClientEvent('nztv:osData', -1, id, payload)
    return true
end
