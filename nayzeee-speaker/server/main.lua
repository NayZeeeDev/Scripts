--[[
    Speakers on the server: every emitter (placed / carried boombox, car, jam), who may touch it, and
    the playback clock every client syncs to (startedAt / pos, in server ms).
]]
Emitters = {}               -- id -> emitter
local carrying = {}         -- src -> id of the boombox they carry
local lastSong, lastAction, lastButton = {}, {}, {}
local idSeq = 0
local BUTTON_COOLDOWN = 0.25    -- seconds between button actions (play, skip, stop...); sliders use Config.Limits.actionCooldown

local function now() return GetGameTimer() end

---------------------------------------------------------------- helpers
function Notify(src, key, kind, ...)
    TriggerClientEvent(RES .. ':client:notify', src, NZ.L(key, ...), kind or 'error')
end

function Log(title, desc)
    local hook = Config.Logs and Config.Logs.webhook
    if not hook or hook == '' then return end
    PerformHttpRequest(hook, function() end, 'POST', json.encode({
        username = 'Speaker',
        embeds = { { title = title, description = desc, color = 569250, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }), { ['Content-Type'] = 'application/json' })
end

local function cooldown(bucket, src, secs)
    local t = bucket[src]
    if t and now() - t < secs * 1000 then return false end
    bucket[src] = now()
    return true
end

-- a heading in degrees, whatever a client sent
local function toHeading(h) return NZ.Clamp(h, -720.0, 720.0) % 360.0 end

-- mode tells the NUI whether it got a real audio file (full 3D) or the YouTube embed (volume only);
-- mix marks a song queued from a mixed playlist (seconds of crossfade into the next one)
local function publicTrack(t)
    if not t then return nil end
    return { src = t.src, id = t.id, url = t.url, mode = t.mode, mix = t.mix,
        title = t.title, author = t.author, duration = t.duration, thumb = t.thumb, by = t.by }
end

local function trackKey(t) return t and (t.id or t.url) or nil end

-- the crossfade that is running right now (linked followers show their leader's)
local function liveXfade(e)
    local x = (e.group and Links.Leader(e) or e).xfade
    if x and now() - x.at < (x.secs + 5) * 1000 then return x end
    return nil
end

local function queueView(q)
    local out = {}
    for i, t in ipairs(q) do
        out[i] = { src = t.src, id = t.id, title = t.title, author = t.author, duration = t.duration, thumb = t.thumb, by = t.by }
    end
    return out
end

function IsTurntable(e)
    local cfg = e.item and Config.Boomboxes[e.item]
    return cfg and cfg.vinyl == true or false
end

-- what every client gets for an emitter
function Pack(e)
    local g = e.group and Links.GroupOf(e)
    return {
        id = e.id, kind = e.kind, item = e.item, label = e.label, model = e.model,
        state = e.state, coords = e.coords, heading = e.heading, netId = e.netId,
        carrier = e.carrier, vehNet = e.vehNet, ownerSrc = e.ownerSrc,
        track = publicTrack(e.track), playing = e.playing, startedAt = e.startedAt, pos = e.pos,
        volume = e.volume, range = e.range, loop = e.loop, shuffle = e.shuffle,
        queue = queueView(e.queue), access = e.access,
        turntable = IsTurntable(e), vinyl = Vinyl and Vinyl.View(e) or nil,
        group = e.group, groupSize = g and #g.members or 0, leader = g and g.leader == e.id or false,
        health = e.health, maxHealth = Config.Damage.health,
        listeners = e.listeners,
        xfade = liveXfade(e),
    }
end

function Broadcast(e)
    TriggerClientEvent(RES .. ':client:emitter', -1, Pack(e))
end

function Elapsed(e)
    if not e.track then return 0 end
    if e.playing then return math.max(0, (now() - e.startedAt) / 1000) end
    return e.pos or 0
end

function EmitterPosition(e)
    if e.kind == 'vehicle' then
        local veh = NetworkGetEntityFromNetworkId(e.vehNet)
        return veh ~= 0 and DoesEntityExist(veh) and GetEntityCoords(veh) or nil
    end
    if e.state == 'carried' and e.carrier then
        local ped = GetPlayerPed(e.carrier)
        return ped ~= 0 and GetEntityCoords(ped) or nil
    end
    return e.coords
end

-- true when `pos` is a real point within `max` metres of the player (NaN never is)
local function near(src, pos, max)
    local ped = GetPlayerPed(src)
    if ped == 0 or type(pos) ~= 'vector3' then return false end
    return #(GetEntityCoords(ped) - pos) <= max
end

-- the player carries this speaker or stands close enough to touch it
function InReach(src, e)
    return e.carrier == src or near(src, EmitterPosition(e), Config.Actions.useRange + 2.0)
end

local function shut(src, e)
    return e.access == 'owner' and e.owner ~= Bridge.GetIdentifier(src) and not Bridge.IsAdmin(src)
end

--[[
    Is this speaker locked against this player? Music actions on a linked speaker act on its group's
    leader, so a locked leader locks the music of every speaker linked to it. own = only this
    speaker's own lock counts (its volume / range, which belong to it alone).
]]
function LockedFor(src, e, own)
    if shut(src, e) then return true end
    if own or not e.group then return false end
    local lead = Links.Leader(e)
    return lead ~= e and shut(src, lead)
end

--[[
    Can this player act on this emitter? control = change the music, 'self' = change only this
    speaker (volume / range), false = only be near it (pick up, pack up). Tells the player why not and
    returns nil, or returns the emitter. A speaker whose prop is still being made can't be touched.
    server/phone.lua's PhonePass lets one checked remote command through without standing there.
]]
function Guard(src, id, control)
    local e = Emitters[id]
    if not e or e.spawning then return nil end
    if PhonePass and PhonePass(src, id, control) then return e end
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end

    if e.kind == 'jam' then
        -- a jam has no place in the world; only its members may touch it
        if Social and Social.CanUseJam(src, e) then return e end
        Notify(src, 'no_access')
        return nil
    end

    if e.kind == 'vehicle' then
        local veh = NetworkGetEntityFromNetworkId(e.vehNet)
        if veh == 0 or GetVehiclePedIsIn(ped, false) ~= veh then
            Notify(src, 'too_far') return nil
        end
        if control and Config.Carplay.controlBy == 'driver' and GetPedInVehicleSeat(veh, -1) ~= ped and not Bridge.IsAdmin(src) then
            Notify(src, 'not_driver') return nil
        end
        return e
    end

    if not InReach(src, e) then
        Notify(src, 'too_far') return nil
    end
    if control and LockedFor(src, e, control == 'self') then
        Notify(src, 'no_access') return nil
    end
    return e
end

-- Song reports (length, end) only count from players close enough to have that song loaded, so one
-- client can't cut or skip songs on speakers across the map.
local function hears(src, e)
    if e.kind == 'jam' then return Social ~= nil and Social.CanUseJam(src, e) end
    local unload = Config.Audio.unloadDistance or 1.35
    return near(src, EmitterPosition(e), (e.range or 0) * unload + 15.0)
end

-- how many players have this group's song loaded right now
local function earshot(lead)
    local members = Links.Members(lead)
    local n = 0
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        for _, m in ipairs(members) do
            if s and hears(s, m) then n = n + 1 break end
        end
    end
    return n
end

--[[
    Song reports (length, end, can't be played) come from the players' games, so they are weighed:
    one counts at once when it comes from a player who may control the speaker (passes its lock),
    otherwise only once more than half of the players in earshot have sent it. A modded client can't
    cut or skip songs on a speaker it isn't allowed to touch, and a song only counts as unplayable
    when most of the people listening can't play it (trust = false).
    Returns the value to use (for lengths: the reporter's, or the middle one of everyone's), or nil.
]]
local function vouch(lead, src, kind, value, trust)
    local key = trackKey(lead.track)
    local r = lead.reports
    if not r or r.key ~= key then r = { key = key } lead.reports = r end
    local k = r[kind]
    if not k then k = { n = 0, by = {} } r[kind] = k end
    if k.by[src] == nil then k.n = k.n + 1 end
    k.by[src] = value
    if trust then return value end
    if k.n * 2 <= earshot(lead) then return nil end
    if type(value) ~= 'number' then return value end
    local list = {}
    for _, v in pairs(k.by) do list[#list + 1] = v end
    table.sort(list)
    return list[(#list + 1) // 2]
end

---------------------------------------------------------------- playback core
-- at  = start this many seconds into the song
-- cue = start this many seconds from now: every client waits silently at 0:00 and starts on the
--       dot (the turntable uses it so the music begins when the needle lands)
function StartTrack(e, track, at, cue)
    e.track = track
    e.playing = true
    e.pos = 0
    e.startedAt = now() - math.floor((at or 0) * 1000) + math.floor((cue or 0) * 1000)
    e.endReported, e.reports = nil, nil
    e.xfade = nil
end

-- the song that is playing goes on the stack the prev button walks back through (last 20)
function PushHistory(e)
    if not e.track then return end
    e.history[#e.history + 1] = e.track
    if #e.history > 20 then table.remove(e.history, 1) end
end

-- fade = seconds of crossfade from the song that is ending into the next one (mixed playlists)
function Advance(e, manual, fade)
    if e.vinyl then return Vinyl.Advance(e, manual) end
    if e.track and e.loop and not manual then
        StartTrack(e, e.track)
    else
        local from = trackKey(e.track)
        PushHistory(e)
        if #e.queue > 0 then
            local idx = e.shuffle and math.random(1, #e.queue) or 1
            StartTrack(e, table.remove(e.queue, idx))
            if fade and fade > 0 and from then e.xfade = { from = from, secs = fade, at = now() } end
        else
            e.track, e.playing, e.pos, e.xfade = nil, false, 0, nil
        end
    end
    Broadcast(e)
    if e.group then Links.Sync(e) end
end

-- seconds before the end at which a mixed-playlist song hands over to the next one (0 = plays out)
local function mixFade(e)
    local mix = Config.Social.mixed ~= false and tonumber(e.track.mix) or 0
    if mix <= 0 or e.loop or e.vinyl or #e.queue == 0 then return 0 end
    return math.min(mix, e.track.duration / 4)
end

function StopEmitter(e)
    -- a record's next song may still be being looked up (server/vinyl.lua): it must not start
    -- by itself once it is found
    if e.vinyl then e.vinyl.token, e.vinyl.loading = nil, false end
    e.track, e.playing, e.pos, e.queue = nil, false, 0, {}
    Broadcast(e)
end

function PauseEmitter(e)
    if not e.track or not e.playing then return end
    e.pos = Elapsed(e)
    e.playing = false
    Broadcast(e)
end

-- song end watcher. Only group leaders advance: followers mirror them through Links.Sync.
CreateThread(function()
    while true do
        Wait(250)
        local t = now()
        for _, e in pairs(Emitters) do
            local dur = e.playing and e.track and e.track.duration or 0
            if dur > 0 and (not e.group or Links.Leader(e) == e) then
                local fade = mixFade(e)
                if fade > 0 then
                    if t >= e.startedAt + (dur - fade) * 1000 then Advance(e, false, fade) end
                elseif t >= e.startedAt + dur * 1000 + 800 then
                    Advance(e)
                end
            end
        end
    end
end)

---------------------------------------------------------------- registry
function NewEmitter(data)
    local e = {
        id = data.id, kind = data.kind, item = data.item, label = data.label, model = data.model,
        owner = data.owner, ownerSrc = data.ownerSrc,
        state = data.state or 'placed', coords = data.coords, heading = data.heading or 0.0,
        vehNet = data.vehNet, plate = data.plate, bucket = data.bucket or 0,
        track = nil, playing = false, startedAt = 0, pos = 0,
        volume = 0.7, range = data.range, loop = false, shuffle = false,
        health = Config.Damage.health,
        queue = {}, history = {}, access = data.access or 'anyone',
    }
    Emitters[e.id] = e
    return e
end

local function nextId()
    idSeq = idSeq + 1
    return ('b%d'):format(idSeq)
end

--[[
    true once the speaker's prop stands. false when it couldn't be made, false + 'gone' when the
    speaker was removed while it was being made (its prop is deleted again, nothing is handed back).
    While it is being made (`spawning`) nobody can touch the speaker (Guard, damage), so it can't be
    packed up or picked up halfway and leave a prop behind that nothing knows about.
]]
local function spawnObject(e)
    e.spawning = true
    local obj = CreateObjectNoOffset(joaat(e.model), e.coords.x, e.coords.y, e.coords.z, true, true, false)
    -- the server creates it on the next tick or two; give up after 3 s
    local t = now()
    while not DoesEntityExist(obj) and now() - t < 3000 do Wait(0) end
    e.spawning = nil
    if Emitters[e.id] ~= e then
        if DoesEntityExist(obj) then DeleteEntity(obj) end
        return false, 'gone'
    end
    if not DoesEntityExist(obj) then return false end
    SetEntityHeading(obj, e.heading + 0.0)
    FreezeEntityPosition(obj, true)
    SetEntityRoutingBucket(obj, e.bucket)
    if SetEntityOrphanMode then SetEntityOrphanMode(obj, 2) end
    Entity(obj).state:set('nzspk', e.id, true)
    e.entity = obj
    e.netId = NetworkGetNetworkIdFromEntity(obj)
    return true
end

local function despawnObject(e)
    if e.entity and DoesEntityExist(e.entity) then DeleteEntity(e.entity) end
    e.entity, e.netId = nil, nil
end

function RemoveEmitter(e)
    if e.group then Links.RemoveFrom(e) end
    despawnObject(e)
    if e.carrier then
        carrying[e.carrier] = nil
        TriggerClientEvent(RES .. ':client:stopCarry', e.carrier, e.id)
    end
    Emitters[e.id] = nil
    TriggerClientEvent(RES .. ':client:remove', -1, e.id)
end

---------------------------------------------------------------- callbacks
NZ.RegisterCallback('time', function() return now() end)

NZ.RegisterCallback('snapshot', function(src)
    local id = Bridge.GetIdentifier(src)
    local out = {}
    for _, e in pairs(Emitters) do
        if e.owner == id then e.ownerSrc = src end       -- back after a reconnect
        out[#out + 1] = Pack(e)
    end
    return out, now()
end)

NZ.RegisterCallback('lists', function(src)
    local id = Bridge.GetIdentifier(src)
    return DB.GetList(id, 'fav', Config.Limits.favorites), DB.GetList(id, 'recent', Config.Limits.history)
end)

NZ.RegisterCallback('favToggle', function(src, track)
    local slim = DB.Slim(track)
    if not slim then return nil end
    local id, key = Bridge.GetIdentifier(src), DB.TrackKey(slim)
    if DB.Has(id, 'fav', key) then
        DB.Remove(id, 'fav', key)
        Notify(src, 'fav_removed', 'inform')
    else
        if DB.Count(id, 'fav') >= Config.Limits.favorites then Notify(src, 'fav_full') return nil end
        DB.Push(id, 'fav', slim, Config.Limits.favorites)
        Notify(src, 'fav_added', 'success')
    end
    return DB.GetList(id, 'fav', Config.Limits.favorites)
end)

NZ.RegisterCallback('recentRemove', function(src, track)
    local slim = DB.Slim(track)
    if not slim then return nil end
    local id = Bridge.GetIdentifier(src)
    DB.Remove(id, 'recent', DB.TrackKey(slim))
    return DB.GetList(id, 'recent', Config.Limits.history)
end)

---------------------------------------------------------------- music actions
local function playResolved(src, e, track, mode)
    track.by = Bridge.GetName(src)
    if mode == 'queue' and e.track then
        if #e.queue >= Config.Limits.maxQueue then return Notify(src, 'queue_full') end
        e.queue[#e.queue + 1] = track
        Notify(src, 'queued', 'success')
    else
        PushHistory(e)
        StartTrack(e, track)
    end
    Broadcast(e)
    Links.Sync(e)
    CreateThread(function() DB.Push(Bridge.GetIdentifier(src), 'recent', track, Config.Limits.history) end)
    Log('Song played', ('**%s** (%s) on `%s`\n%s — %s'):format(GetPlayerName(src), src, e.id, track.title or '?', track.author or '?'))
end

local function handlePlay(src, id, resolver, arg, mode)
    local e = Guard(src, id, true)
    if not e then return end
    e = Links.Leader(e)
    if IsTurntable(e) then return Notify(src, 'vinyl_only') end
    if not cooldown(lastSong, src, Config.Limits.rateLimit) then return Notify(src, 'rate_limited') end
    TriggerClientEvent(RES .. ':client:loading', src, id, true)
    local track, err = resolver(arg)
    TriggerClientEvent(RES .. ':client:loading', src, id, false)
    if not track then
        if err == 'too_long' then return Notify(src, 'too_long', 'error', math.floor(Config.Limits.maxDuration / 60)) end
        return Notify(src, err or 'resolve_failed')
    end
    if Emitters[e.id] ~= e then return end       -- packed up / broken while the song was looked up
    playResolved(src, e, track, mode)
end

RegisterNetEvent(RES .. ':play', function(id, input, mode)
    handlePlay(source, id, Tracks.Resolve, input, mode)
end)

RegisterNetEvent(RES .. ':playSaved', function(id, saved, mode)
    handlePlay(source, id, Tracks.FromSaved, saved, mode)
end)

-- the phone app plays a saved song on a player's behalf
function PlaySavedFor(src, id, saved, mode)
    handlePlay(src, id, Tracks.FromSaved, saved, mode)
end

--[[
    Music actions act on the group's leader so linked speakers stay in step. Volume and range belong
    to the one speaker (nothing to copy to the rest of the group). They are sliders and may come in
    quick succession; buttons get a firmer limit, since every change is sent to every player.
]]
local actions = {}
local OWN = { volume = true, range = true }
local function runAction(name, src, id, ...)
    local fn = actions[name]
    if not fn then return end
    local slider = OWN[name]
    local ok = slider and cooldown(lastAction, src, Config.Limits.actionCooldown)
        or not slider and cooldown(lastButton, src, math.max(Config.Limits.actionCooldown, BUTTON_COOLDOWN))
    if not ok then return end
    local e = Guard(src, id, slider and 'self' or true)
    if not e then return end
    if slider then return fn(src, e, ...) end
    local target = Links.Leader(e)
    fn(src, target, ...)
    if target.group then Links.Sync(target) end
end

function ActionFor(src, name, id, ...) runAction(name, src, id, ...) end

local function action(name, fn)
    actions[name] = fn
    RegisterNetEvent(RES .. ':' .. name, function(id, ...)
        runAction(name, source, id, ...)
    end)
end

action('toggle', function(_, e)
    -- a record's next song is being looked up and starts by itself once it is found: e.track is
    -- still the song before it (stopped), which must not come back on
    if e.vinyl and e.vinyl.loading then return end
    if not e.track then
        if e.vinyl then Vinyl.PlayIndex(e, e.vinyl.idx or 1) end
        return
    end
    if e.playing then return PauseEmitter(e) end
    e.startedAt = now() - math.floor((e.pos or 0) * 1000)
    e.playing = true
    Broadcast(e)
end)

action('pause', function(_, e) PauseEmitter(e) end)

action('seek', function(_, e, pos)
    if not e.track then return end
    local dur = e.track.duration or 0
    pos = NZ.Clamp(pos, 0, dur > 0 and dur - 1 or 36000)
    if e.playing then e.startedAt = now() - math.floor(pos * 1000) else e.pos = pos end
    Broadcast(e)
end)

action('next', function(_, e) if e.track then Advance(e, true) end end)

action('prev', function(_, e)
    if not e.track then return end
    if e.vinyl then return Vinyl.Prev(e, Elapsed(e)) end
    if Elapsed(e) > 5 or #e.history == 0 then
        StartTrack(e, e.track)
    else
        table.insert(e.queue, 1, e.track)
        StartTrack(e, table.remove(e.history))
    end
    Broadcast(e)
end)

action('volume', function(_, e, v)
    e.volume = NZ.Clamp(v, 0.0, 1.0)
    Broadcast(e)
end)

action('range', function(_, e, v)
    local r = e.kind == 'vehicle' and Config.Ranges.vehicle or Config.Ranges.boombox
    e.range = NZ.Clamp(v, r.min, r.max)
    Broadcast(e)
end)

action('loop', function(_, e) e.loop = not e.loop Broadcast(e) end)
action('shuffle', function(_, e) e.shuffle = not e.shuffle Broadcast(e) end)
action('stop', function(_, e) StopEmitter(e) end)

action('queueRemove', function(_, e, idx)
    idx = tonumber(idx)
    if idx and e.queue[idx] then table.remove(e.queue, idx) Broadcast(e) end
end)

action('queuePlay', function(_, e, idx)
    idx = tonumber(idx)
    if e.vinyl then return Vinyl.PlayIndex(e, idx) end
    if not idx or not e.queue[idx] then return end
    local t = table.remove(e.queue, idx)
    PushHistory(e)
    StartTrack(e, t)
    Broadcast(e)
end)

RegisterNetEvent(RES .. ':access', function(id, mode)
    local src = source
    local e = Emitters[id]
    if not e or e.kind ~= 'boombox' then return end
    if e.owner ~= Bridge.GetIdentifier(src) and not Bridge.IsAdmin(src) then return Notify(src, 'not_owner') end
    e.access = mode == 'owner' and 'owner' or 'anyone'
    Broadcast(e)
end)

-- clients tell us each song's length once it loads (weighed, see vouch)
RegisterNetEvent(RES .. ':duration', function(id, key, dur)
    local src = source
    local e = Emitters[id]
    dur = tonumber(dur)
    if not e or not dur or dur ~= dur or dur <= 0 or dur > 36000 or not hears(src, e) then return end
    -- linked speakers share one track table, so this sets it for the whole group
    local lead = Links.Leader(e)
    if not lead.track or (lead.track.duration or 0) > 0 or trackKey(lead.track) ~= key then return end
    dur = vouch(lead, src, 'duration', dur, not LockedFor(src, e))
    if not dur then return end
    if Config.Limits.maxDuration > 0 and dur > Config.Limits.maxDuration then
        Notify(src, 'too_long', 'error', math.floor(Config.Limits.maxDuration / 60))
        return Advance(lead, true)
    end
    lead.track.duration = math.floor(dur)
    Broadcast(lead)
    if lead.group then Links.Sync(lead) end
end)

--[[
    A client's song ended, or (failed) its game can't play the song at all: the video was removed or
    may not be embedded, or a direct link is dead. That happens a moment after the song starts, so it
    can't wait for the 3 s an ordinary end report needs; it moves on once most listeners have said so.
]]
RegisterNetEvent(RES .. ':ended', function(id, key, failed)
    local src = source
    local e = Emitters[id]
    if not e or not hears(src, e) then return end
    local lead = Links.Leader(e)
    if not lead.track or not lead.playing then return end
    if trackKey(lead.track) ~= key or lead.endReported then return end
    if failed == true then
        if not vouch(lead, src, 'failed', true, false) then return end
        lead.endReported = true
        return Advance(lead, true)       -- skips a looped song too: it would only fail again
    end
    if (lead.track.duration or 0) > 0 and Elapsed(lead) < lead.track.duration - 3 then return end
    if Elapsed(lead) < 3 then return end
    if not vouch(lead, src, 'ended', true, not LockedFor(src, e)) then return end
    lead.endReported = true
    Advance(lead)
end)

---------------------------------------------------------------- boombox lifecycle
for item in pairs(Config.Boomboxes) do
    Bridge.RegisterUsable(item, function(src)
        if carrying[src] then return Notify(src, 'already_carrying') end
        TriggerClientEvent(RES .. ':client:place', src, item)
    end)
end

RegisterNetEvent(RES .. ':place', function(item, coords, heading, hold)
    local src = source
    local cfg = type(item) == 'string' and Config.Boomboxes[item]
    if not cfg or type(coords) ~= 'vector3' then return end
    if carrying[src] then return Notify(src, 'already_carrying') end
    if not near(src, coords, Config.Actions.place.distance + 3.0) then return Notify(src, 'placement_far') end
    if NZ.InBlacklistedZone(coords) then return Notify(src, 'blacklisted_zone') end
    if hold and not cfg.portable then return Notify(src, 'not_portable') end
    if not Bridge.HasItem(src, item) or not Bridge.RemoveItem(src, item) then return Notify(src, 'no_item') end

    local e = NewEmitter({
        id = nextId(), kind = 'boombox', item = item, label = cfg.label, model = cfg.model,
        owner = Bridge.GetIdentifier(src), ownerSrc = src,
        coords = coords, heading = toHeading(heading),
        bucket = GetPlayerRoutingBucket(src), range = Config.Ranges.boombox.default,
        access = Config.Actions.control,
    })

    if hold then
        e.state, e.carrier = 'carried', src
        carrying[src] = e.id
        TriggerClientEvent(RES .. ':client:startCarry', src, e.id, item)
    else
        local ok, why = spawnObject(e)
        if not ok then
            if why ~= 'gone' then
                Emitters[e.id] = nil
                Bridge.GiveOrDrop(src, item)
            end
            return
        end
        Notify(src, 'placed', 'success')
    end
    Broadcast(e)
    Log('Boombox placed', ('**%s** (%s) placed `%s` (%s) at %s'):format(GetPlayerName(src), src, cfg.label, e.id, tostring(coords)))
end)

local function canPickup(src, e)
    if Config.Actions.pickup == 'anyone' then return true end
    return e.owner == Bridge.GetIdentifier(src) or Bridge.IsAdmin(src)
end

RegisterNetEvent(RES .. ':carry', function(id)
    local src = source
    local e = Guard(src, id, false)
    if not e or e.kind ~= 'boombox' or e.state ~= 'placed' then return end
    if carrying[src] then return Notify(src, 'already_carrying') end
    if not Config.Boomboxes[e.item].portable then return Notify(src, 'not_portable') end
    if not canPickup(src, e) then return Notify(src, 'not_owner') end
    despawnObject(e)
    e.state, e.carrier = 'carried', src
    carrying[src] = e.id
    TriggerClientEvent(RES .. ':client:startCarry', src, e.id, e.item)
    Broadcast(e)
end)

RegisterNetEvent(RES .. ':drop', function(id, coords, heading)
    local src = source
    local e = Emitters[id]
    if not e or e.carrier ~= src then return end
    -- set down where the client says, unless that isn't right next to the player
    if not near(src, coords, 6.0) then coords = GetEntityCoords(GetPlayerPed(src)) end
    -- no setting it down in a blacklisted zone either: it stays in their hands (their game already
    -- let go of it, so it is handed back)
    if NZ.InBlacklistedZone(coords) then
        Notify(src, 'blacklisted_zone')
        return TriggerClientEvent(RES .. ':client:startCarry', src, e.id, e.item)
    end
    carrying[src] = nil
    e.state, e.carrier = 'placed', nil
    e.coords, e.heading = coords, toHeading(heading)
    e.bucket = GetPlayerRoutingBucket(src)
    local ok, why = spawnObject(e)
    if not ok then
        if why ~= 'gone' then
            Bridge.GiveOrDrop(src, e.item)
            RemoveEmitter(e)
        end
        return
    end
    Broadcast(e)
end)

--[[
    Packing up hands the speaker (and a record on it) back, so it only goes ahead when there is room
    in the player's pockets: otherwise it stays where it is, nothing is taken off or lost.
]]
RegisterNetEvent(RES .. ':pack', function(id)
    local src = source
    local e = Emitters[id]
    if not e or e.kind ~= 'boombox' then return end
    if e.carrier ~= src then
        if not Guard(src, id, false) then return end
        if e.carrier then return end
        if not canPickup(src, e) then return Notify(src, 'not_owner') end
    end
    if not Bridge.CanCarry(src, e.item, 1) then return Notify(src, 'shop_full') end
    if e.vinyl and not Vinyl.Return(e, Vinyl.Taker(e, src), nil, true) then return Notify(src, 'shop_full') end
    if not Bridge.AddItem(src, e.item) then
        Broadcast(e)            -- its record may be off already
        return Notify(src, 'shop_full')
    end
    RemoveEmitter(e)
    Notify(src, 'packed', 'success')
    Log('Boombox packed', ('**%s** (%s) packed `%s` (%s)'):format(GetPlayerName(src), src, e.label, e.id))
end)

-- a record goes back to whoever put it on, if they are still here (never to a player who is leaving)
local function returnRecord(e, leaving)
    if not e.vinyl then return end
    local to = e.vinyl.ownerSrc
    Vinyl.Return(e, to ~= leaving and to or nil)
end

AddEventHandler('playerDropped', function()
    local src = source
    local ident = Bridge.GetIdentifier(src)
    lastSong[src], lastAction[src], lastButton[src] = nil, nil, nil
    for _, e in pairs(Emitters) do
        if e.kind == 'boombox' then
            local mine = e.ownerSrc == src or e.owner == ident
            if mine and Config.DeleteBoomboxWhenOwnerQuit then
                returnRecord(e, src)
                RemoveEmitter(e)
            elseif e.carrier == src then
                -- set the speaker down where they stood
                local ped = GetPlayerPed(src)
                local pos = ped ~= 0 and GetEntityCoords(ped) or e.coords
                carrying[src] = nil
                e.state, e.carrier = 'placed', nil
                if pos then
                    e.coords = pos - vector3(0.0, 0.0, 0.95)
                    if spawnObject(e) then Broadcast(e) elseif Emitters[e.id] == e then RemoveEmitter(e) end
                else
                    RemoveEmitter(e)
                end
            end
            if Emitters[e.id] and e.ownerSrc == src then e.ownerSrc = nil end
        end
    end
end)

-- Everything here lives in memory, so a stopping resource deletes the props it spawned and hands
-- records and speakers back to their owners who are online (otherwise a restart would eat them).
-- pcall: at shutdown the inventory may already be gone, and the props must go regardless.
AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, e in pairs(Emitters) do
        if e.entity and DoesEntityExist(e.entity) then DeleteEntity(e.entity) end
        pcall(returnRecord, e)
        if e.kind == 'boombox' and e.ownerSrc and GetPlayerName(e.ownerSrc) then pcall(Bridge.GiveOrDrop, e.ownerSrc, e.item) end
    end
end)

---------------------------------------------------------------- admin
RegisterCommand('speakerclear', function(src, args)
    if not Bridge.IsAdmin(src) then return Notify(src, 'no_permission') end
    local radius = tonumber(args[1])
    local origin = src ~= 0 and GetEntityCoords(GetPlayerPed(src)) or nil
    local n = 0
    for _, e in pairs(Emitters) do
        local pos = EmitterPosition(e)
        if not radius or (origin and pos and #(origin - pos) <= radius) then
            returnRecord(e)
            if e.kind == 'boombox' then RemoveEmitter(e) else StopEmitter(e) end
            n = n + 1
        end
    end
    if src ~= 0 then Notify(src, 'admin_cleared', 'success', n) else print(('[speaker] cleared %d'):format(n)) end
end, false)

RegisterCommand('speakerstop', function(src, args)
    if not Bridge.IsAdmin(src) then return Notify(src, 'no_permission') end
    if src == 0 then return print('[speaker] /speakerstop works around a player; use speakerclear from the console') end
    local radius = tonumber(args[1]) or 30.0
    local origin = GetEntityCoords(GetPlayerPed(src))
    local n = 0
    for _, e in pairs(Emitters) do
        local pos = EmitterPosition(e)
        local busy = e.track or (e.vinyl and e.vinyl.loading)      -- a record's song still being looked up too
        if busy and pos and #(origin - pos) <= radius then StopEmitter(e) n = n + 1 end
    end
    Notify(src, 'admin_cleared', 'success', n)
end, false)

exports('GetEmitters', function()
    local out = {}
    for id, e in pairs(Emitters) do out[id] = Pack(e) end
    return out
end)
