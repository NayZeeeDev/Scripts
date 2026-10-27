--[[
    Phone app, server side.

    The app controls speakers from a distance, so main.lua's Guard() (which wants the player standing
    at the speaker) would turn every phone command down. Phone requests are checked here instead:
        allowed(src)        the app is enabled and the player has the item it needs (if any)
        reachable(me, e)    the player may control this speaker from where they are right now
    and only then handed to the normal playback code, for exactly that one call (see remote()).
]]
local RES = GetCurrentResourceName()
local P = Config.Phone
local OTHERS_RANGE = 25.0      -- with range = 0, other people's speakers still have to be this close
local MAX_LISTED = 40          -- speakers one phone lists at most (admins can reach every speaker)

---------------------------------------------------------------- who may do what
local function allowed(src)
    if not P.enabled then return false end
    local item = P.needItem or ''
    return item == '' or (Bridge.HasItem(src, item) and true or false)
end

-- everything about the player a check needs, looked up once per request
local function who(src)
    local ped = GetPlayerPed(src)
    return { src = src, ped = ped, id = Bridge.GetIdentifier(src), coords = ped ~= 0 and GetEntityCoords(ped) or nil }
end

local function isAdmin(me)
    if me.admin == nil then me.admin = Bridge.IsAdmin(me.src) and true or false end
    return me.admin
end

-- true, or false + the locale key that says why not
local function reachable(me, e)
    if not e then return false, 'no_access' end
    if e.kind == 'jam' then
        -- a jam has no place in the world: its members control it from anywhere
        if Social and Social.CanUseJam(me.src, e) then return true end
        return false, 'no_access'
    end
    if me.ped == 0 then return false, 'too_far' end
    if e.kind == 'vehicle' then
        -- only while you're sitting in that car
        local veh = NetworkGetEntityFromNetworkId(e.vehNet or 0)
        if veh == 0 or GetVehiclePedIsIn(me.ped, false) ~= veh then return false, 'too_far' end
        if Config.Carplay.controlBy == 'driver' and GetPedInVehicleSeat(veh, -1) ~= me.ped and not isAdmin(me) then
            return false, 'not_driver'
        end
        return true
    end
    local mine = e.owner == me.id
    if e.access == 'owner' and not mine and not isAdmin(me) then return false, 'no_access' end
    local range = tonumber(P.range) or 0
    if range <= 0 then
        if mine or isAdmin(me) then return true end
        range = OTHERS_RANGE
    end
    local pos = EmitterPosition(e)
    if not pos or not me.coords or #(me.coords - pos) > range then return false, 'too_far' end
    return true
end

-- the speaker a phone request is for, or nil (after telling the player why)
local function target(src, id)
    if type(id) ~= 'string' or not allowed(src) then return nil end
    local e = Emitters[id]
    local ok, why = reachable(who(src), e)
    if not ok then
        if e then Notify(src, why or 'no_access') end
        return nil
    end
    return e
end

---------------------------------------------------------------- remote control
-- One checked phone call may pass main.lua's Guard() for the same player and speaker, music control
-- only (never pick up / pack up). Guard() runs before anything in those calls can yield, so the pass
-- is used up (or cleared below) within the same tick and can't leak into another request.
local pass
local guard = Guard
assert(guard, 'server/phone.lua has to load after server/main.lua')
function Guard(src, id, control)
    local p = pass
    if p and control and p.src == src and p.id == id then
        pass = nil
        return Emitters[id]
    end
    return guard(src, id, control)
end

local function remote(src, id, fn, ...)
    local p = { src = src, id = id }
    pass = p
    local ok, err = pcall(fn, ...)
    if pass == p then pass = nil end
    if not ok then print(('^1[%s] phone command failed: %s^7'):format(RES, err)) end
end

---------------------------------------------------------------- callbacks
-- Which speakers this player can control from the phone right now. The client adds the live
-- state (track, position, volume...) from its own copy of every speaker, so this stays small.
NZ.RegisterCallback('phone:list', function(src)
    if not allowed(src) then return {} end
    local me = who(src)
    local out = {}
    for id, e in pairs(Emitters) do
        if reachable(me, e) then
            local pos = e.kind ~= 'jam' and me.coords and EmitterPosition(e) or nil
            out[#out + 1] = { id = id, mine = e.owner == me.id, d = pos and math.floor(#(me.coords - pos) + 0.5) or 0 }
        end
    end
    table.sort(out, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        return a.d < b.d
    end)
    for i = #out, MAX_LISTED + 1, -1 do out[i] = nil end
    return out
end)

-- Song search (the phone and the player's own search box both use it)
local lastSearch = {}
NZ.RegisterCallback('search', function(src, query)
    if not Config.Search.enabled then return {} end
    local t = GetGameTimer()
    if lastSearch[src] and t - lastSearch[src] < 700 then return {} end
    lastSearch[src] = t
    return Search.Query(query, Config.Search.results)
end)

---------------------------------------------------------------- music commands
local ACTIONS = {
    toggle = true, pause = true, next = true, prev = true, stop = true, seek = true,
    volume = true, loop = true, shuffle = true, queuePlay = true, queueRemove = true,
}

RegisterNetEvent(RES .. ':phone:action', function(id, what, value)
    local src = source
    if not ACTIONS[what] or not target(src, id) then return end
    remote(src, id, ActionFor, src, what, id, value)
end)

-- play or queue one song (a search result, a liked song, a playlist entry)
RegisterNetEvent(RES .. ':phone:play', function(id, saved, mode)
    local src = source
    if type(saved) ~= 'table' or not target(src, id) then return end
    remote(src, id, PlaySavedFor, src, id, saved, mode == 'queue' and 'queue' or 'now')
end)

---------------------------------------------------------------- whole lists (Liked Songs, playlists)
local lastList, fills = {}, {}

local function isCollaborator(r, ident)
    local ok, list = pcall(json.decode, r.collaborators or '[]')
    if not ok or type(list) ~= 'table' then return false end
    for _, c in ipairs(list) do
        if c == ident then return true end
    end
    return false
end

-- saved songs, display name, crossfade seconds (mixed playlists) — or nil when not allowed
local function savedList(src, which)
    local ident = Bridge.GetIdentifier(src)
    if which == 'liked' then
        local pack = Locales[Config.Locale] or Locales.en
        local name = pack.phone and pack.phone.liked or 'Liked Songs'
        return DB.GetList(ident, 'fav', Config.Limits.favorites), name, nil
    end
    local plId = tonumber(which)
    if not plId or not Config.Playlists.enabled then return nil end
    local r = MySQL.single.await(
        'SELECT owner, name, shared, mixed, tracks, collaborators FROM nayzeee_speaker_playlists WHERE id = ?', { plId })
    if not r then return nil end
    if r.owner ~= ident and r.shared ~= 1 and not isCollaborator(r, ident) then Notify(src, 'no_access') return nil end
    local ok, tracks = pcall(json.decode, r.tracks or '[]')
    if not ok or type(tracks) ~= 'table' then tracks = {} end
    local mix = r.mixed == 1 and Config.Social.mixed ~= false and (Config.Social.mixedFade or 4.0) or nil
    return tracks, r.name, mix
end

-- the list starting at `start`, optionally shuffled (a tapped song stays first)
local function order(tracks, start, shuffle)
    local n = #tracks
    start = math.floor(tonumber(start) or 1)
    if start < 1 or start > n then start = 1 end
    local out = {}
    for i = 0, n - 1 do out[i + 1] = tracks[(start - 1 + i) % n + 1] end
    if shuffle then
        local from = start > 1 and 2 or 1
        for i = n, from + 1, -1 do
            local j = math.random(from, i)
            out[i], out[j] = out[j], out[i]
        end
    end
    for i = n, Config.Limits.maxQueue + 2, -1 do out[i] = nil end
    return out
end

-- Plays a list: the first song that loads starts right away, the rest are looked up in the background
-- and appended to the queue (so a 25-song playlist doesn't keep the speaker silent while it resolves).
-- Starting another list, stopping the speaker or removing it ends the background fill.
RegisterNetEvent(RES .. ':phone:playList', function(id, which, start, shuffle)
    local src = source
    local e = target(src, id)
    if not e then return end
    e = Links.Leader(e)
    if IsTurntable(e) then return Notify(src, 'vinyl_only') end
    local now = GetGameTimer()
    if lastList[src] and now - lastList[src] < Config.Limits.rateLimit * 1000 then return Notify(src, 'rate_limited') end
    lastList[src] = now

    local tracks, name, mix = savedList(src, which)
    if not tracks then return end
    if #tracks == 0 then return Notify(src, 'pl_empty') end
    local list = order(tracks, start, shuffle == true)

    TriggerClientEvent(RES .. ':client:loading', src, e.id, true)
    local first, i = nil, 1
    while not first and i <= math.min(#list, 3) do
        first = Tracks.FromSaved(list[i])
        i = i + 1
    end
    TriggerClientEvent(RES .. ':client:loading', src, e.id, false)
    if Emitters[e.id] ~= e then return end
    if not first then return Notify(src, 'resolve_failed') end

    local by = Bridge.GetName(src)
    first.by, first.mix = by, mix
    if e.track then
        e.history[#e.history + 1] = e.track
        if #e.history > 20 then table.remove(e.history, 1) end
    end
    e.queue = {}
    StartTrack(e, first)
    Broadcast(e)
    Links.Sync(e)
    Log('Phone list played', ('**%s** (%s) played `%s` on `%s`'):format(GetPlayerName(src), src, name or '?', e.id))

    local token = {}
    fills[e.id] = token
    local function live() return fills[e.id] == token and Emitters[e.id] == e and e.track ~= nil end
    local added, unsent = 1, 0
    for j = i, #list do
        if not live() or #e.queue >= Config.Limits.maxQueue then break end
        local track = Tracks.FromSaved(list[j])
        if not live() then break end
        if track then
            track.by, track.mix = by, mix
            e.queue[#e.queue + 1] = track
            added, unsent = added + 1, unsent + 1
            if unsent >= 4 then unsent = 0 Broadcast(e) Links.Sync(e) end
        end
    end
    if fills[e.id] == token then fills[e.id] = nil end
    if unsent > 0 and Emitters[e.id] == e then Broadcast(e) Links.Sync(e) end
    Notify(src, 'pl_queued', 'success', added, name or '')
end)

AddEventHandler('playerDropped', function()
    lastSearch[source], lastList[source] = nil, nil
end)

exports('PhoneCanUse', function(src) return allowed(src) end)
