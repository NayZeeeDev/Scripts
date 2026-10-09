Emitters = {}               -- id -> emitter
local carrying = {}         -- src -> emitter id
local lastSong, lastAction = {}, {}
local idSeq = 0
local RES = GetCurrentResourceName()

local function now() return GetGameTimer() end

---------------------------------------------------------------- helpers
local function notify(src, key, kind, ...)
    TriggerClientEvent(RES .. ':client:notify', src, NZ.L(key, ...), kind or 'error')
end
Notify = notify

local function log(title, desc)
    local hook = Config.Logs and Config.Logs.webhook
    if not hook or hook == '' then return end
    PerformHttpRequest(hook, function() end, 'POST', json.encode({
        username = 'Speaker',
        embeds = { { title = title, description = desc, color = 569250, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }), { ['Content-Type'] = 'application/json' })
end
Log = log

local function publicTrack(t)
    if not t then return nil end
    return { src = t.src, id = t.id, url = t.url, title = t.title, author = t.author, duration = t.duration, thumb = t.thumb, by = t.by }
end

local function queueView(q)
    local out = {}
    for i, t in ipairs(q) do
        out[i] = { src = t.src, id = t.id, title = t.title, author = t.author, duration = t.duration, thumb = t.thumb, by = t.by }
    end
    return out
end

function Pack(e)
    return {
        id = e.id, kind = e.kind, item = e.item, label = e.label, model = e.model,
        state = e.state, coords = e.coords, heading = e.heading, netId = e.netId,
        carrier = e.carrier, vehNet = e.vehNet, ownerSrc = e.ownerSrc,
        track = publicTrack(e.track), playing = e.playing, startedAt = e.startedAt, pos = e.pos,
        volume = e.volume, range = e.range, loop = e.loop, shuffle = e.shuffle,
        queue = queueView(e.queue), access = e.access,
        turntable = IsTurntable(e), vinyl = Vinyl and Vinyl.View(e) or nil,
        group = e.group, groupSize = e.group and Groups[e.group] and #Groups[e.group].members or 0,
        leader = e.group and Groups[e.group] and Groups[e.group].leader == e.id or false,
        health = e.health, maxHealth = Config.Damage.health,
        listeners = e.listeners,
    }
end

function IsTurntable(e)
    local cfg = e.item and Config.Boomboxes[e.item]
    return cfg and cfg.vinyl == true or false
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

local function isAdmin(src) return Bridge.IsAdmin(src) end

local function cooldown(bucket, src, secs)
    local t = bucket[src]
    if t and now() - t < secs * 1000 then return false end
    bucket[src] = now()
    return true
end

-- Can this player act on this emitter? control = change music, false = just be near it
function Guard(src, id, control)
    local e = Emitters[id]
    if not e then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end

    if e.kind == 'jam' then
        -- a jam has no place in the world; only its members may touch it
        if Social and Social.CanUseJam(src, e) then return e end
        notify(src, 'no_access')
        return nil
    end

    if e.kind == 'vehicle' then
        local veh = NetworkGetEntityFromNetworkId(e.vehNet)
        if veh == 0 or GetVehiclePedIsIn(ped, false) ~= veh then
            notify(src, 'too_far') return nil
        end
        if control and Config.Carplay.controlBy == 'driver' and GetPedInVehicleSeat(veh, -1) ~= ped and not isAdmin(src) then
            notify(src, 'not_driver') return nil
        end
        return e
    end

    local pos = EmitterPosition(e)
    if not pos or #(GetEntityCoords(ped) - pos) > Config.Actions.useRange + 2.0 then
        if e.carrier ~= src then notify(src, 'too_far') return nil end
    end
    if control and e.access == 'owner' and e.owner ~= Bridge.GetIdentifier(src) and not isAdmin(src) then
        notify(src, 'no_access') return nil
    end
    return e
end

---------------------------------------------------------------- playback core
function StartTrack(e, track, at)
    e.track = track
    e.playing = true
    e.pos = 0
    e.startedAt = now() - math.floor((at or 0) * 1000)
    e.endReported = nil
end

function Advance(e, manual)
    if e.vinyl then return Vinyl.Advance(e, manual) end
    if e.track and e.loop and not manual then
        StartTrack(e, e.track) return Broadcast(e)
    end
    if e.track then
        e.history[#e.history + 1] = e.track
        if #e.history > 20 then table.remove(e.history, 1) end
    end
    if #e.queue > 0 then
        local idx = e.shuffle and math.random(1, #e.queue) or 1
        StartTrack(e, table.remove(e.queue, idx))
    else
        e.track, e.playing, e.pos = nil, false, 0
    end
    Broadcast(e)
    if e.group then Links.Sync(e) end
end

function StopEmitter(e)
    e.track, e.playing, e.pos, e.queue = nil, false, 0, {}
    Broadcast(e)
end

function PauseEmitter(e)
    if not e.track or not e.playing then return end
    e.pos = Elapsed(e)
    e.playing = false
    Broadcast(e)
end

-- song end watcher
CreateThread(function()
    while true do
        Wait(500)
        local t = now()
        for _, e in pairs(Emitters) do
            if e.playing and e.track and (e.track.duration or 0) > 0 then
                if t >= e.startedAt + e.track.duration * 1000 + 800 then Advance(e) end
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

local function spawnObject(e)
    local obj = CreateObjectNoOffset(joaat(e.model), e.coords.x, e.coords.y, e.coords.z, true, true, false)
    local t = now()
    while not DoesEntityExist(obj) and now() - t < 3000 do Wait(0) end
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
    if e.group and Links then Links.RemoveFrom(e) end
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
        if e.owner == id then e.ownerSrc = src end
        out[#out + 1] = Pack(e)
    end
    return out, now()
end)

NZ.RegisterCallback('lists', function(src)
    local id = Bridge.GetIdentifier(src)
    return DB.GetList(id, 'fav', Config.Limits.favorites), DB.GetList(id, 'recent', Config.Limits.history)
end)

NZ.RegisterCallback('favToggle', function(src, track)
    if type(track) ~= 'table' or type(track.src) ~= 'string' then return nil end
    local id = Bridge.GetIdentifier(src)
    local key = DB.TrackKey(track)
    if DB.Has(id, 'fav', key) then
        DB.Remove(id, 'fav', key)
        notify(src, 'fav_removed', 'inform')
    else
        if DB.Count(id, 'fav') >= Config.Limits.favorites then notify(src, 'fav_full') return nil end
        DB.Push(id, 'fav', track, Config.Limits.favorites)
        notify(src, 'fav_added', 'success')
    end
    return DB.GetList(id, 'fav', Config.Limits.favorites)
end)

NZ.RegisterCallback('recentRemove', function(src, track)
    if type(track) ~= 'table' or type(track.src) ~= 'string' then return nil end
    local id = Bridge.GetIdentifier(src)
    DB.Remove(id, 'recent', DB.TrackKey(track))
    return DB.GetList(id, 'recent', Config.Limits.history)
end)

---------------------------------------------------------------- music actions
local function playResolved(src, e, track, mode)
    track.by = Bridge.GetName(src)
    if mode == 'queue' and e.track then
        if #e.queue >= Config.Limits.maxQueue then return notify(src, 'queue_full') end
        e.queue[#e.queue + 1] = track
        notify(src, 'queued', 'success')
        Broadcast(e)
    else
        if e.track then
            e.history[#e.history + 1] = e.track
            if #e.history > 20 then table.remove(e.history, 1) end
        end
        StartTrack(e, track)
        Broadcast(e)
    end
    CreateThread(function() DB.Push(Bridge.GetIdentifier(src), 'recent', track, Config.Limits.history) end)
    log('Song played', ('**%s** (%s) on `%s`\n%s — %s'):format(GetPlayerName(src), src, e.id, track.title or '?', track.author or '?'))
end

local function handlePlay(src, id, resolver, arg, mode)
    local e = Guard(src, id, true)
    if not e then return end
    e = Links.Leader(e)
    if IsTurntable(e) then return notify(src, 'vinyl_only') end
    if not cooldown(lastSong, src, Config.Limits.rateLimit) then return notify(src, 'rate_limited') end
    TriggerClientEvent(RES .. ':client:loading', src, id, true)
    local track, err = resolver(arg)
    TriggerClientEvent(RES .. ':client:loading', src, id, false)
    if not track then
        if err == 'too_long' then return notify(src, 'too_long', 'error', math.floor(Config.Limits.maxDuration / 60)) end
        return notify(src, err or 'resolve_failed')
    end
    if not Emitters[e.id] then return end
    playResolved(src, e, track, mode)
    Links.Sync(e)
end

RegisterNetEvent(RES .. ':play', function(id, input, mode)
    handlePlay(source, id, Tracks.Resolve, input, mode)
end)

-- entry points other files (phone app) use on behalf of a player
function PlayFor(src, id, input, mode)
    handlePlay(src, id, Tracks.Resolve, input, mode)
end

function PlaySavedFor(src, id, saved, mode)
    handlePlay(src, id, Tracks.FromSaved, saved, mode)
end

RegisterNetEvent(RES .. ':playSaved', function(id, saved, mode)
    handlePlay(source, id, Tracks.FromSaved, saved, mode)
end)

-- Music actions act on the group's leader so linked speakers stay in step.
local actions = {}
local function runAction(name, src, id, ...)
    local fn = actions[name]
    if not fn then return end
    if not cooldown(lastAction, src, Config.Limits.actionCooldown) then return end
    local e = Guard(src, id, true)
    if not e then return end
    local target = (name == 'volume' or name == 'range') and e or Links.Leader(e)
    fn(src, target, ...)
    if target ~= e or target.group then Links.Sync(Links.Leader(e)) end
end

function ActionFor(src, name, id, ...) runAction(name, src, id, ...) end

local function action(name, fn)
    actions[name] = fn
    RegisterNetEvent(RES .. ':' .. name, function(id, ...)
        runAction(name, source, id, ...)
    end)
end

action('toggle', function(_, e)
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
    if e.track then e.history[#e.history + 1] = e.track end
    StartTrack(e, t)
    Broadcast(e)
end)

RegisterNetEvent(RES .. ':access', function(id, mode)
    local src = source
    local e = Emitters[id]
    if not e or e.kind ~= 'boombox' then return end
    if e.owner ~= Bridge.GetIdentifier(src) and not isAdmin(src) then return notify(src, 'not_owner') end
    e.access = mode == 'owner' and 'owner' or 'anyone'
    Broadcast(e)
end)

-- clients tell us each song's length once it loads
RegisterNetEvent(RES .. ':duration', function(id, key, dur)
    local e = Emitters[id]
    dur = tonumber(dur)
    if not e or not e.track or not dur or dur <= 0 or dur > 36000 then return end
    if (e.track.duration or 0) > 0 then return end
    if (e.track.id or e.track.url) ~= key then return end
    if Config.Limits.maxDuration > 0 and dur > Config.Limits.maxDuration then
        notify(source, 'too_long', 'error', math.floor(Config.Limits.maxDuration / 60))
        return Advance(e, true)
    end
    e.track.duration = math.floor(dur)
    Broadcast(e)
end)

RegisterNetEvent(RES .. ':ended', function(id, key)
    local e = Emitters[id]
    if not e or not e.track or not e.playing then return end
    if (e.track.id or e.track.url) ~= key or e.endReported then return end
    if (e.track.duration or 0) > 0 and Elapsed(e) < e.track.duration - 3 then return end
    if Elapsed(e) < 3 then return end
    e.endReported = true
    Advance(e)
end)

---------------------------------------------------------------- boombox lifecycle
local function useBoombox(src, item)
    if carrying[src] then return notify(src, 'already_carrying') end
    TriggerClientEvent(RES .. ':client:place', src, item)
end

for item in pairs(Config.Boomboxes) do
    Bridge.RegisterUsable(item, function(src) useBoombox(src, item) end)
    Bridge.OnUse[item] = function(src) useBoombox(src, item) end
end

RegisterNetEvent(RES .. ':place', function(item, coords, heading, hold)
    local src = source
    local cfg = Config.Boomboxes[item]
    if not cfg or type(coords) ~= 'vector3' then return end
    if carrying[src] then return notify(src, 'already_carrying') end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - coords) > Config.Actions.place.distance + 3.0 then return notify(src, 'placement_far') end
    if NZ.InBlacklistedZone(coords) then return notify(src, 'blacklisted_zone') end
    if not Bridge.HasItem(src, item) then return notify(src, 'no_item') end
    if hold and not cfg.portable then return notify(src, 'not_portable') end
    if not Bridge.RemoveItem(src, item) then return notify(src, 'no_item') end

    local e = NewEmitter({
        id = nextId(), kind = 'boombox', item = item, label = cfg.label, model = cfg.model,
        owner = Bridge.GetIdentifier(src), ownerSrc = src,
        coords = coords, heading = tonumber(heading) or 0.0,
        bucket = GetPlayerRoutingBucket(src), range = Config.Ranges.boombox.default,
        access = Config.Actions.control,
    })

    if hold then
        e.state, e.carrier = 'carried', src
        carrying[src] = e.id
        TriggerClientEvent(RES .. ':client:startCarry', src, e.id, item)
    elseif not spawnObject(e) then
        Emitters[e.id] = nil
        Bridge.AddItem(src, item)
        return
    else
        notify(src, 'placed', 'success')
    end
    Broadcast(e)
    log('Boombox placed', ('**%s** (%s) placed `%s` (%s) at %s'):format(GetPlayerName(src), src, cfg.label, e.id, tostring(coords)))
end)

local function canPickup(src, e)
    if Config.Actions.pickup == 'anyone' then return true end
    return e.owner == Bridge.GetIdentifier(src) or isAdmin(src)
end

RegisterNetEvent(RES .. ':carry', function(id)
    local src = source
    local e = Guard(src, id, false)
    if not e or e.kind ~= 'boombox' or e.state ~= 'placed' then return end
    if carrying[src] then return notify(src, 'already_carrying') end
    if not Config.Boomboxes[e.item].portable then return notify(src, 'not_portable') end
    if not canPickup(src, e) then return notify(src, 'not_owner') end
    despawnObject(e)
    e.state, e.carrier = 'carried', src
    carrying[src] = e.id
    TriggerClientEvent(RES .. ':client:startCarry', src, e.id, e.item)
    Broadcast(e)
end)

RegisterNetEvent(RES .. ':drop', function(id, coords, heading)
    local src = source
    local e = Emitters[id]
    if not e or e.carrier ~= src or type(coords) ~= 'vector3' then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - coords) > 6.0 then coords = GetEntityCoords(GetPlayerPed(src)) end
    carrying[src] = nil
    e.state, e.carrier = 'placed', nil
    e.coords, e.heading = coords, tonumber(heading) or 0.0
    e.bucket = GetPlayerRoutingBucket(src)
    if not spawnObject(e) then
        Bridge.AddItem(src, e.item)
        return RemoveEmitter(e)
    end
    Broadcast(e)
end)

RegisterNetEvent(RES .. ':pack', function(id)
    local src = source
    local e = Emitters[id]
    if not e or e.kind ~= 'boombox' then return end
    if e.carrier ~= src then
        if not Guard(src, id, false) then return end
        if e.carrier then return end
        if not canPickup(src, e) then return notify(src, 'not_owner') end
    end
    if e.vinyl then Vinyl.Return(e, src) end
    RemoveEmitter(e)
    Bridge.AddItem(src, e.item)
    notify(src, 'packed', 'success')
    log('Boombox packed', ('**%s** (%s) packed `%s` (%s)'):format(GetPlayerName(src), src, e.label, e.id))
end)

AddEventHandler('playerDropped', function()
    local src = source
    local ident = Bridge.GetIdentifier(src)
    lastSong[src], lastAction[src] = nil, nil
    for _, e in pairs(Emitters) do
        if e.kind == 'boombox' then
            local mine = e.ownerSrc == src or e.owner == ident
            if mine and Config.DeleteBoomboxWhenOwnerQuit then
                RemoveEmitter(e)
            elseif e.carrier == src then
                local ped = GetPlayerPed(src)
                local pos = ped ~= 0 and GetEntityCoords(ped) or e.coords
                carrying[src] = nil
                e.state, e.carrier = 'placed', nil
                if pos then
                    e.coords = pos - vector3(0.0, 0.0, 0.95)
                    if spawnObject(e) then Broadcast(e) else RemoveEmitter(e) end
                else
                    RemoveEmitter(e)
                end
            end
            if Emitters[e.id] and e.ownerSrc == src then e.ownerSrc = nil end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, e in pairs(Emitters) do
        if e.entity and DoesEntityExist(e.entity) then DeleteEntity(e.entity) end
    end
end)

---------------------------------------------------------------- admin
RegisterCommand('speakerclear', function(src, args)
    if src ~= 0 and not isAdmin(src) then return notify(src, 'no_permission') end
    local radius = tonumber(args[1])
    local origin = src ~= 0 and GetEntityCoords(GetPlayerPed(src)) or nil
    local n = 0
    for _, e in pairs(Emitters) do
        local pos = EmitterPosition(e)
        if not radius or (origin and pos and #(origin - pos) <= radius) then
            if e.vinyl then Vinyl.Return(e, e.vinyl.ownerSrc) end
            if e.kind == 'boombox' then RemoveEmitter(e) else StopEmitter(e) end
            n = n + 1
        end
    end
    if src ~= 0 then notify(src, 'admin_cleared', 'success', n) else print(('[speaker] cleared %d'):format(n)) end
end, false)

RegisterCommand('speakerstop', function(src, args)
    if src ~= 0 and not isAdmin(src) then return notify(src, 'no_permission') end
    local radius = tonumber(args[1]) or 30.0
    local origin = src ~= 0 and GetEntityCoords(GetPlayerPed(src)) or nil
    local n = 0
    for _, e in pairs(Emitters) do
        local pos = EmitterPosition(e)
        if origin and pos and #(origin - pos) <= radius and e.track then StopEmitter(e) n = n + 1 end
    end
    if src ~= 0 then notify(src, 'admin_cleared', 'success', n) end
end, false)

exports('GetEmitters', function()
    local out = {}
    for id, e in pairs(Emitters) do out[id] = Pack(e) end
    return out
end)
