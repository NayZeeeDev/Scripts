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

local jams = {}           -- jamId -> { id, host, hostSrc, name, members = { [src] = identifier } }
local jamOf = {}          -- src -> jamId
local jamSeq = 0

---------------------------------------------------------------- jam
local function jamEmitterId(id) return 'j' .. id end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function view(j, src)
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

-- tell the jam's speaker who listens, and every member what the jam looks like now
local function broadcastJam(j)
    local e = Emitters[jamEmitterId(j.id)]
    if not e then return end
    local list = {}
    for src in pairs(j.members) do list[#list + 1] = src end
    e.listeners = list
    e.owner, e.ownerSrc = j.host, j.hostSrc
    Broadcast(e)
    for _, src in ipairs(list) do
        TriggerClientEvent(RES .. ':client:jam', src, view(j, src))
    end
end

local function createJam(src, name)
    jamSeq = jamSeq + 1
    name = NZ.Trim(name, 40)
    local ident = Bridge.GetIdentifier(src)
    local j = {
        id = jamSeq, host = ident, hostSrc = src,
        name = name ~= '' and name or (Bridge.GetName(src) .. "'s Jam"):sub(1, 40),
        members = { [src] = ident },
    }
    jams[j.id] = j
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

-- dropped = the player left the server (nothing to send them)
local function leaveJam(src, dropped)
    local j = jams[jamOf[src] or 0]
    jamOf[src] = nil
    if not j then return end
    j.members[src] = nil
    if not dropped then TriggerClientEvent(RES .. ':client:jam', src, false) end

    if not next(j.members) then
        local e = Emitters[jamEmitterId(j.id)]
        if e then RemoveEmitter(e) end
        jams[j.id] = nil
        return
    end
    if j.hostSrc == src then
        local s, ident = next(j.members)
        j.hostSrc, j.host = s, ident
    end
    broadcastJam(j)
end

NZ.RegisterCallback('jam:create', function(src, name)
    if not Config.Social.jam then return nil end
    if jamOf[src] then leaveJam(src) end
    local j = createJam(src, name)
    Notify(src, 'jam_started', 'success', j.name)
    return view(j, src)
end)

NZ.RegisterCallback('jam:list', function(src)
    local out = {}
    for _, j in pairs(jams) do
        out[#out + 1] = { id = j.id, name = j.name, host = Bridge.GetName(j.hostSrc), count = count(j.members), mine = jamOf[src] == j.id }
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    local mine = jams[jamOf[src] or 0]
    return out, mine and view(mine, src) or nil
end)

NZ.RegisterCallback('jam:join', function(src, id)
    if not Config.Social.jam then return nil end
    local j = jams[tonumber(id) or 0]
    if not j then return nil end
    if jamOf[src] == j.id then return view(j, src) end
    if count(j.members) >= Config.Social.jamMax then Notify(src, 'jam_full') return nil end
    if jamOf[src] then leaveJam(src) end
    j.members[src] = Bridge.GetIdentifier(src)
    jamOf[src] = j.id
    broadcastJam(j)
    Notify(src, 'jam_joined', 'success', j.name)
    return view(j, src)
end)

NZ.RegisterCallback('jam:leave', function(src)
    leaveJam(src)
    return true
end)

-- members may control the jam's music, so Guard() in main.lua lets them through
function Social.CanUseJam(src, e)
    if e.kind ~= 'jam' then return false end
    local id = jamOf[src]
    return id ~= nil and jamEmitterId(id) == e.id
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
    local function add(t)
        local k = t and (t.id or t.url or t.search)
        if k and not seen[k] and #out < Config.Playlists.maxTracks then
            seen[k] = true
            out[#out + 1] = t
        end
    end
    for i = 1, math.max(#mine, #theirs) do add(mine[i]) add(theirs[i]) end

    local first = function(s) return Bridge.GetName(s):match('^%S+') end
    local name = ('%s x %s'):format(first(src) or 'You', first(targetSrc) or 'Them')
    MySQL.insert.await('INSERT INTO nayzeee_speaker_playlists (owner, owner_name, name, tracks, kind) VALUES (?, ?, ?, ?, ?)',
        { a, Bridge.GetName(src), name:sub(1, 60), json.encode(out), 'blend' })
    Notify(src, 'blend_made', 'success', #out, name)
    return Playlists.Mine(a)
end)

---------------------------------------------------------------- prompted
local prompting = {}        -- src -> true while their searches run (one prompt at a time)

NZ.RegisterCallback('pl:prompted', function(src, prompt)
    if not Config.Social.prompted or prompting[src] then return nil end
    prompt = NZ.Trim(prompt, 80)
    if #prompt < 3 then return nil end
    local id = Bridge.GetIdentifier(src)

    -- a few angles on the same idea so the list isn't 20 versions of one song
    prompting[src] = true
    local out, seen = {}, {}
    for _, shape in ipairs({ '%s songs', '%s playlist', 'best %s', '%s mix' }) do
        local ok, res = pcall(Search.Query, shape:format(prompt), 8)
        for _, r in ipairs(ok and res or {}) do
            if not seen[r.id] and #out < Config.Social.promptedSize then
                seen[r.id] = true
                out[#out + 1] = { src = 'yt', id = r.id, title = r.title, author = r.author, duration = r.duration, thumb = r.thumb }
            end
        end
        if #out >= Config.Social.promptedSize then break end
    end
    prompting[src] = nil
    if #out == 0 then Notify(src, 'resolve_failed') return nil end
    MySQL.insert.await('INSERT INTO nayzeee_speaker_playlists (owner, owner_name, name, tracks, kind) VALUES (?, ?, ?, ?, ?)',
        { id, Bridge.GetName(src), prompt:sub(1, 60), json.encode(out), 'prompted' })
    Notify(src, 'prompted_made', 'success', #out)
    return Playlists.Mine(id)
end)

AddEventHandler('playerDropped', function() prompting[source] = nil end)

---------------------------------------------------------------- collaborative
NZ.RegisterCallback('pl:collab', function(src, plId, targetSrc)
    if not Config.Social.collab then return nil end
    local id = Bridge.GetIdentifier(src)
    local r = Playlists.Get(plId)
    if not r or r.owner ~= id then return nil end
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then return nil end
    local list, other = Playlists.Collaborators(r), Bridge.GetIdentifier(targetSrc)
    local at
    for i, c in ipairs(list) do
        if c == other then at = i break end
    end
    -- the same button adds a collaborator or takes them off again
    if at then table.remove(list, at) else list[#list + 1] = other end
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET collaborators = ?, kind = ? WHERE id = ?',
        { json.encode(list), #list > 0 and 'collab' or 'normal', r.id })
    if at then
        Notify(src, 'collab_removed', 'inform', Bridge.GetName(targetSrc))
    else
        Notify(src, 'collab_added', 'success', Bridge.GetName(targetSrc))
        Notify(targetSrc, 'collab_invited', 'inform', Bridge.GetName(src), r.name)
    end
    return Playlists.Mine(id)
end)

---------------------------------------------------------------- mixed
NZ.RegisterCallback('pl:mixed', function(src, plId, on)
    if not Config.Social.mixed then return nil end
    local r = Playlists.Get(plId)
    local id = Bridge.GetIdentifier(src)
    if not r or r.owner ~= id then return nil end
    MySQL.query.await('UPDATE nayzeee_speaker_playlists SET mixed = ? WHERE id = ?', { on and 1 or 0, r.id })
    return Playlists.Mine(id)
end)

-- players you can blend or collaborate with right now
NZ.RegisterCallback('social:players', function(src)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        if s and s ~= src then out[#out + 1] = { src = s, name = Bridge.GetName(s) } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end)
