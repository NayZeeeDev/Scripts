--[[
    Jam, Blend, Collaborative, Mixed and Prompted playlists.

    These are our own versions of the ideas, built on this script's own playback — they do not
    connect to Spotify's features of the same name.

      Jam        a listening session. Everyone who joins hears the host's music through their own
                 ears at full volume, anywhere in the city, and any member can queue songs.
      Blend      one playlist made from what two or more players have liked.
      Collab     a playlist several named players can all add to.
      Mixed      a playlist that crossfades between songs instead of cutting.
      Prompted   a playlist built from a sentence ("late night drive rap") by searching for it.
]]
Social = {}
local RES = GetCurrentResourceName()

Jams = {}                 -- jamId -> { id, host, hostSrc, name, members = { src -> identifier }, emitter }
local jamSeq = 0
local jamOf = {}          -- src -> jamId

---------------------------------------------------------------- jam
local function jamEmitterId(id) return 'j' .. id end

local function broadcastJam(j)
    local e = Emitters[jamEmitterId(j.id)]
    if not e then return end
    local list = {}
    for src in pairs(j.members) do list[#list + 1] = src end
    e.listeners = list
    Broadcast(e)
    for _, src in ipairs(list) do
        TriggerClientEvent(RES .. ':client:jam', src, Social.View(j, src))
    end
end

function Social.View(j, src)
    local members = {}
    for s in pairs(j.members) do
        members[#members + 1] = { name = Bridge.GetName(s), host = s == j.hostSrc }
    end
    return {
        id = j.id, name = j.name, emitter = jamEmitterId(j.id),
        host = Bridge.GetName(j.hostSrc), isHost = src == j.hostSrc,
        members = members, count = #members,
    }
end

local function createJam(src, name)
    jamSeq = jamSeq + 1
    local j = {
        id = jamSeq, host = Bridge.GetIdentifier(src), hostSrc = src,
        name = (name and name ~= '' and name or (Bridge.GetName(src) .. "'s Jam")):sub(1, 40),
        members = { [src] = Bridge.GetIdentifier(src) },
    }
    Jams[j.id] = j
    jamOf[src] = j.id

    -- a jam's music lives on its own emitter that every member hears at full volume
    local e = NewEmitter({
        id = jamEmitterId(j.id), kind = 'jam', label = j.name,
        owner = j.host, ownerSrc = src, range = 0, access = 'anyone',
    })
    e.listeners = { src }
    Broadcast(e)
    return j
end

local function leaveJam(src, silent)
    local id = jamOf[src]
    local j = id and Jams[id]
    jamOf[src] = nil
    if not j then return end
    j.members[src] = nil
    TriggerClientEvent(RES .. ':client:jam', src, false)

    local left = 0
    for _ in pairs(j.members) do left = left + 1 end
    if left == 0 then
        local e = Emitters[jamEmitterId(j.id)]
        if e then RemoveEmitter(e) end
        Jams[j.id] = nil
        return
    end
    if j.hostSrc == src then
        for s in pairs(j.members) do j.hostSrc = s j.host = Bridge.GetIdentifier(s) break end
    end
    if not silent then broadcastJam(j) end
end

NZ.RegisterCallback('jam:create', function(src, name)
    if not Config.Social.jam then return nil end
    if jamOf[src] then leaveJam(src) end
    local j = createJam(src, name)
    Notify(src, 'jam_started', 'success', j.name)
    return Social.View(j, src)
end)

NZ.RegisterCallback('jam:list', function(src)
    local out = {}
    for _, j in pairs(Jams) do
        local n = 0
        for _ in pairs(j.members) do n = n + 1 end
        out[#out + 1] = { id = j.id, name = j.name, host = Bridge.GetName(j.hostSrc), count = n, mine = jamOf[src] == j.id }
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out, jamOf[src] and Social.View(Jams[jamOf[src]], src) or nil
end)

NZ.RegisterCallback('jam:join', function(src, id)
    if not Config.Social.jam then return nil end
    local j = Jams[tonumber(id) or 0]
    if not j then return nil end
    local n = 0
    for _ in pairs(j.members) do n = n + 1 end
    if n >= Config.Social.jamMax then Notify(src, 'jam_full') return nil end
    if jamOf[src] and jamOf[src] ~= j.id then leaveJam(src) end
    j.members[src] = Bridge.GetIdentifier(src)
    jamOf[src] = j.id
    broadcastJam(j)
    Notify(src, 'jam_joined', 'success', j.name)
    return Social.View(j, src)
end)

NZ.RegisterCallback('jam:leave', function(src)
    leaveJam(src)
    return true
end)

function Social.JamOf(src) return jamOf[src] and Jams[jamOf[src]] or nil end

-- members may control the jam's music, so the guard in main.lua allows them through
function Social.CanUseJam(src, e)
    if e.kind ~= 'jam' then return false end
    local j = Social.JamOf(src)
    return j ~= nil and jamEmitterId(j.id) == e.id
end

AddEventHandler('playerDropped', function() leaveJam(source, true) end)

---------------------------------------------------------------- blend
NZ.RegisterCallback('pl:blend', function(src, targetSrc)
    if not Config.Social.blend then return nil end
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) or targetSrc == src then return nil end
    local a, b = Bridge.GetIdentifier(src), Bridge.GetIdentifier(targetSrc)
    local mine = DB.GetList(a, 'fav', Config.Limits.favorites)
    local theirs = DB.GetList(b, 'fav', Config.Limits.favorites)
    if #mine == 0 and #theirs == 0 then Notify(src, 'blend_empty') return nil end

    -- alternate between the two libraries so the result really is a mix
    local out, seen = {}, {}
    for i = 1, math.max(#mine, #theirs) do
        for _, t in ipairs({ mine[i], theirs[i] }) do
            local k = t and (t.id or t.url or '')
            if t and k ~= '' and not seen[k] and #out < Config.Playlists.maxTracks then
                seen[k] = true
                out[#out + 1] = t
            end
        end
    end
    local name = ('%s x %s'):format(Bridge.GetName(src):match('^%S+') or 'You', Bridge.GetName(targetSrc):match('^%S+') or 'Them')
    MySQL.insert.await('INSERT INTO nayzeee_speaker_playlists (owner, owner_name, name, tracks, kind) VALUES (?, ?, ?, ?, ?)',
        { a, Bridge.GetName(src), name:sub(1, 60), json.encode(out), 'blend' })
    Notify(src, 'blend_made', 'success', #out, name)
    return Playlists.Mine(a)
end)

---------------------------------------------------------------- prompted
NZ.RegisterCallback('pl:prompted', function(src, prompt)
    if not Config.Social.prompted then return nil end
    prompt = tostring(prompt or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 80)
    if #prompt < 3 then return nil end
    local id = Bridge.GetIdentifier(src)

    -- a few angles on the same idea so the list isn't 20 versions of one song
    local angles = { '%s songs', '%s playlist', 'best %s', '%s mix' }
    local out, seen = {}, {}
    for _, shape in ipairs(angles) do
        local res = Search.Query(shape:format(prompt), 8)
        for _, r in ipairs(res) do
            if not seen[r.id] and #out < Config.Social.promptedSize then
                seen[r.id] = true
                out[#out + 1] = { src = 'yt', id = r.id, title = r.title, author = r.author, duration = r.duration, thumb = r.thumb }
            end
        end
        if #out >= Config.Social.promptedSize then break end
        Wait(0)
    end
    if #out == 0 then Notify(src, 'resolve_failed') return nil end
    MySQL.insert.await('INSERT INTO nayzeee_speaker_playlists (owner, owner_name, name, tracks, kind) VALUES (?, ?, ?, ?, ?)',
        { id, Bridge.GetName(src), prompt:sub(1, 60), json.encode(out), 'prompted' })
    Notify(src, 'prompted_made', 'success', #out)
    return Playlists.Mine(id)
end)

---------------------------------------------------------------- collaborative
NZ.RegisterCallback('pl:collab', function(src, plId, targetSrc)
    if not Config.Social.collab then return nil end
    local id = Bridge.GetIdentifier(src)
    local r = MySQL.single.await('SELECT * FROM nayzeee_speaker_playlists WHERE id = ?', { plId })
    if not r or r.owner ~= id then return nil end
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then return nil end
    local ok, list = pcall(json.decode, r.collaborators or '[]')
    if not ok or type(list) ~= 'table' then list = {} end
    local other = Bridge.GetIdentifier(targetSrc)
    for i, c in ipairs(list) do
        if c == other then
            table.remove(list, i)
            MySQL.query.await('UPDATE nayzeee_speaker_playlists SET collaborators = ?, kind = ? WHERE id = ?',
                { json.encode(list), #list > 0 and 'collab' or 'normal', plId })
            Notify(src, 'collab_removed', 'inform', Bridge.GetName(targetSrc))
            return Playlists.Mine(id)
        end
    end
    list[#list + 1] = other
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET collaborators = ?, kind = ? WHERE id = ?',
        { json.encode(list), 'collab', plId })
    Notify(src, 'collab_added', 'success', Bridge.GetName(targetSrc))
    Notify(targetSrc, 'collab_invited', 'inform', Bridge.GetName(src), r.name)
    return Playlists.Mine(id)
end)

---------------------------------------------------------------- mixed
NZ.RegisterCallback('pl:mixed', function(src, plId, on)
    if not Config.Social.mixed then return nil end
    local id = Bridge.GetIdentifier(src)
    local r = MySQL.single.await('SELECT * FROM nayzeee_speaker_playlists WHERE id = ?', { plId })
    if not r or r.owner ~= id then return nil end
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET mixed = ? WHERE id = ?', { on and 1 or 0, plId })
    return Playlists.Mine(id)
end)

-- players you can blend or collaborate with right now
NZ.RegisterCallback('social:players', function(src)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        if s and s ~= src then
            out[#out + 1] = { src = s, name = Bridge.GetName(s) }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end)
