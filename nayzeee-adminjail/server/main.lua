--[[
    NAYZEEE Admin Jail — server core

    The server owns every sentence. Clients never send time, they only say
    "I'm ready", "I'm placed" or "I'm outside". The timer is a stored `remaining`
    plus a `stamp`, so nothing ticks per second and nothing drifts:

        remaining_now = remaining - (now - stamp)    -- only while the sentence is ticking

    A sentence ticks while the player is placed in jail (or always, with countOffline).
    State: 'offline' -> 'placing' (waiting for the client to spawn & get moved) -> 'active'
]]

Sentences = {}

local Jailed = {}  -- [identifier] = sentence
local Sources = {} -- [source] = identifier
local Known = {}   -- [source] = { identifier, name, account } — cached so we still know them on drop
local Recent = {}  -- recently disconnected players (offline jailing)
local loaded = false

local Event = AJ.Event
local SPAWN_KINDS = { jail = true, restore = true, transfer = true }

local function now() return os.time() end

local function ticking(e)
    return Config.Sentence.countOffline or e.state == 'active'
end

local function remaining(e)
    if ticking(e) then return math.max(0, e.remaining - (now() - e.stamp)) end
    return e.remaining
end

--- Folds elapsed time into `remaining`. Call before any change to state or time.
local function stamp(e)
    e.remaining = remaining(e)
    e.stamp = now()
end

local function setState(e, state)
    stamp(e)
    e.state = state
end

local function hourCap() return Config.Work.maxPerHour * 60 end

local function payload(e)
    local loc = AJ.GetLocation(e.location)
    return {
        location = e.location,
        locationName = loc and loc.name,
        remaining = remaining(e),
        total = e.total,
        ticking = ticking(e),
        reason = e.reason,
        admin = e.admin,
        escapes = e.escapes,
        cycles = e.cycles,
        reduced = e.reduced,
        hourReduced = e.hourReduced,
        hourCap = hourCap(),
    }
end

local function sync(e)
    if e.source then TriggerClientEvent(Event('client:sync'), e.source, payload(e)) end
end

local function setBag(src, value)
    local player = Player(src)
    if player and player.state then player.state:set('adminJailed', value, true) end
end

--- Tells the client to move into jail. Time is paused until the client confirms placement.
local function enforce(e, opts)
    if not e.source then return end
    opts = opts or {}
    setState(e, 'placing')
    e.enforcedAt = now()
    e.kind = opts.kind or 'restore'

    local data = payload(e)
    data.kind = e.kind
    data.instant = opts.instant
    data.penalty = opts.penalty
    TriggerClientEvent(Event('client:enforce'), e.source, data)
    AJ.Debug('enforce', e.identifier, e.kind)
end

local function activate(e)
    setState(e, 'active')
    local t = now()
    e.graceUntil = t + Config.Escape.grace
    e.strikes = 0
    if SPAWN_KINDS[e.kind] then e.pullbackUntil = t + Config.Spawn.pullbackWindow end
    sync(e)
    Work.OnActive(e)
    AJ.Debug('active', e.identifier, remaining(e))
end

local function releaseCoords(e)
    if Config.Release.mode == 'previous' and e.returnCoords then return e.returnCoords end
    local loc = AJ.GetLocation(e.location)
    local c = loc and loc.release or Config.Release.coords
    return { x = c.x, y = c.y, z = c.z, w = c.w or 0.0 }
end

local function fromRow(row)
    local e = {
        identifier = row.identifier,
        name = row.name,
        account = row.account,
        reason = row.reason,
        admin = row.admin,
        location = AJ.GetLocation(row.location) and row.location or AJ.DefaultLocation().id,
        total = row.total,
        remaining = row.remaining,
        escapes = row.escapes,
        cycles = row.cycles,
        reduced = row.reduced,
        hourStart = row.hour_start,
        hourReduced = row.hour_reduced,
        returnCoords = row.return_coords and json.decode(row.return_coords) or nil,
        jailedAt = row.jailed_at,
        state = 'offline',
        stamp = now(),
        work = { step = 0 },
    }
    if Config.Sentence.countOffline then
        e.remaining = math.max(0, e.remaining - (now() - row.updated_at))
    end
    return e
end

--[[ Attach / detach — linking a sentence to an online source ]]

local function remember(src)
    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return nil end
    Known[src] = { identifier = identifier, name = Bridge.GetName(src), account = Bridge.GetAccountName(src) }
    return identifier
end

local function detach(e, saveNow)
    setState(e, 'offline')
    if e.source then
        Sources[e.source] = nil
        setBag(e.source, false)
    end
    e.source = nil
    Work.Reset(e)
    if saveNow ~= false then DB.Save(e) end
end

local function attach(src, kind)
    if not loaded then return end
    local identifier = remember(src)
    if not identifier then return end

    -- Character scope: a different character may still be linked to this source.
    local linked = Sources[src]
    if linked and linked ~= identifier and Jailed[linked] then
        detach(Jailed[linked])
        TriggerClientEvent(Event('client:suspend'), src)
    end

    local e = Jailed[identifier]
    if not e then return end

    -- Multiple spawn events fire together; one enforce is enough.
    if e.source == src and e.state == 'placing' and now() - (e.enforcedAt or 0) < 3 then return end

    if e.source and e.source ~= src then Sources[e.source] = nil end
    e.source = src
    e.account = Known[src].account
    Sources[src] = identifier
    setBag(src, true)
    enforce(e, { kind = kind or 'restore' })
end

--[[ Public API (used by admin.lua, work.lua, commands.lua, exports) ]]

Sentences.Remaining = remaining
Sentences.Stamp = stamp
Sentences.Sync = sync
Sentences.Payload = payload
Sentences.Ticking = ticking

function Sentences.Get(identifier) return Jailed[identifier] end
function Sentences.BySource(src) local id = Sources[src] return id and Jailed[id] end
function Sentences.All() return Jailed end
function Sentences.Known(src) return Known[src] or (remember(src) and Known[src]) end

function Sentences.FindSource(identifier)
    for src, info in pairs(Known) do
        if info.identifier == identifier and GetPlayerName(src) then return src end
    end
end

function Sentences.Recent()
    local cutoff = now() - 3 * 3600
    local out = {}
    for i = #Recent, 1, -1 do
        local r = Recent[i]
        if r.droppedAt < cutoff then
            table.remove(Recent, i)
        elseif not Sentences.FindSource(r.identifier) then
            out[#out + 1] = r
        end
    end
    return out
end

--- opts: { source?, identifier?, name?, account?, minutes, reason, location, admin, adminSrc? }
function Sentences.Jail(opts)
    local minutes = math.floor(tonumber(opts.minutes) or 0)
    if minutes < 1 or minutes > Config.Sentence.maxMinutes then
        return false, locale('invalid_time', Config.Sentence.maxMinutes)
    end

    local loc = AJ.GetLocation(opts.location or Config.Sentence.defaultLocation)
    if not loc then return false, locale('invalid_location') end

    local src = opts.source and tonumber(opts.source)
    local identifier = opts.identifier

    if src then
        if not GetPlayerName(src) then return false, locale('player_not_found') end
        identifier = remember(src)
    elseif identifier then
        src = Sentences.FindSource(identifier)
        if src then remember(src) end
    end

    if not identifier then return false, locale('player_not_found') end
    if Jailed[identifier] then return false, locale('already_jailed') end

    local info = src and Known[src] or {}
    local reason = tostring(opts.reason or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 255)
    if reason == '' then reason = 'No reason given' end

    local t = now()
    local e = {
        identifier = identifier,
        name = info.name or opts.name or 'Unknown',
        account = info.account or opts.account,
        reason = reason,
        admin = opts.admin or 'System',
        location = loc.id,
        total = minutes * 60,
        remaining = minutes * 60,
        escapes = 0,
        cycles = 0,
        reduced = 0,
        hourStart = t,
        hourReduced = 0,
        jailedAt = t,
        state = 'offline',
        stamp = t,
        work = { step = 0 },
    }

    if src then
        local ped = GetPlayerPed(src)
        if ped ~= 0 then
            local c = GetEntityCoords(ped)
            if c.x ~= 0.0 or c.y ~= 0.0 then
                e.returnCoords = { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }
            end
        end
    end

    Jailed[identifier] = e
    DB.Save(e)

    if src then
        local linked = Sources[src]
        if linked and Jailed[linked] and linked ~= identifier then detach(Jailed[linked]) end
        e.source = src
        Sources[src] = identifier
        setBag(src, true)
        enforce(e, { kind = 'jail' })
        Bridge.Notify(src, locale('jailed_target', minutes), 'error')
    end

    Webhook('jail', src and 'Player jailed' or 'Player jailed (offline)', {
        WebhookField('Player', ('%s (%s)'):format(e.name, e.account or identifier)),
        WebhookField('Admin', e.admin),
        WebhookField('Length', minutes .. ' min'),
        WebhookField('Location', loc.name),
        WebhookField('Reason', reason, false),
    })

    return true, e
end

function Sentences.Release(e, outcome, by)
    stamp(e)
    if outcome == 'served' then e.remaining = 0 end
    DB.Archive(e, outcome, by)
    Jailed[e.identifier] = nil

    local src = e.source
    if src then
        Sources[src] = nil
        setBag(src, false)
        TriggerClientEvent(Event('client:release'), src, releaseCoords(e))
        Bridge.Notify(src, locale('released'), 'success')
    end

    Webhook('release', outcome == 'served' and 'Sentence served' or 'Player released', {
        WebhookField('Player', ('%s (%s)'):format(e.name, e.account or e.identifier)),
        WebhookField('Released by', by or 'System'),
        WebhookField('Served', ('%d / %d min'):format(math.floor((e.total - e.remaining) / 60), math.floor(e.total / 60))),
        WebhookField('Escapes', e.escapes),
        WebhookField('Work cycles', e.cycles),
    })
    return true
end

function Sentences.Adjust(e, minutes, by)
    minutes = math.floor(tonumber(minutes) or 0)
    if minutes == 0 or math.abs(minutes) > Config.Sentence.maxMinutes then
        return false, locale('invalid_time', Config.Sentence.maxMinutes)
    end

    stamp(e)
    local delta = minutes * 60
    e.remaining = math.max(0, e.remaining + delta)
    if delta > 0 then e.total = e.total + delta end

    Webhook('adjust', 'Sentence adjusted', {
        WebhookField('Player', e.name),
        WebhookField('Admin', by),
        WebhookField('Change', ('%+d min'):format(minutes)),
        WebhookField('Remaining', math.ceil(e.remaining / 60) .. ' min'),
    })

    if e.remaining <= 0 then return Sentences.Release(e, 'released', by) end

    DB.Save(e)
    sync(e)
    if e.source then Bridge.Notify(e.source, locale('adjusted_target', ('%+d'):format(minutes)), minutes > 0 and 'error' or 'success') end
    return true
end

function Sentences.Transfer(e, locationId, by)
    local loc = AJ.GetLocation(locationId)
    if not loc then return false, locale('invalid_location') end
    if loc.id == e.location then return true end

    stamp(e)
    e.location = loc.id
    Work.Reset(e)
    DB.Save(e)

    if e.source then
        Bridge.Notify(e.source, locale('transferred_target', loc.name), 'inform')
        enforce(e, { kind = 'transfer', instant = true })
    end

    Webhook('transfer', 'Player transferred', {
        WebhookField('Player', e.name),
        WebhookField('Admin', by),
        WebhookField('Location', loc.name),
    })
    return true
end

--[[ Escapes ]]

local function penaltyFor(e)
    local esc = Config.Escape
    return math.min(esc.maxPenalty, esc.penalty + esc.escalation * e.escapes)
end

local function onOutside(e, fromServer, spawned)
    if e.state ~= 'active' then return end
    local t = now()

    local silent = not Config.Escape.enabled
        or spawned
        or t < (e.graceUntil or 0)
        or t < (e.pullbackUntil or 0)

    if silent then
        enforce(e, { kind = 'pullback', instant = true })
        return
    end

    local penalty = penaltyFor(e)
    stamp(e)
    e.escapes = e.escapes + 1
    e.remaining = e.remaining + penalty * 60
    e.total = e.total + penalty * 60
    DB.Save(e)

    enforce(e, { kind = 'escape', instant = true, penalty = penalty })

    -- A tampered client might ignore the event; OneSync lets us move the ped ourselves.
    if fromServer then
        local ped = GetPlayerPed(e.source)
        local spawn = AJ.GetLocation(e.location).spawn
        if ped ~= 0 then SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false) end
    end

    if Config.Escape.broadcast then
        TriggerClientEvent(Event('client:notify'), -1, locale('escape_broadcast', e.name, penalty), 'error')
    end

    Webhook('escape', 'Escape attempt', {
        WebhookField('Player', ('%s (%s)'):format(e.name, e.account or e.identifier)),
        WebhookField('Penalty', '+' .. penalty .. ' min'),
        WebhookField('Attempt', '#' .. e.escapes),
        WebhookField('Detected by', fromServer and 'Server (OneSync)' or 'Client'),
    })
end

--[[ Net events ]]

-- Sent by the client on load, on every (re)spawn and on resource start.
RegisterNetEvent(Event('server:ready'), function()
    attach(source, 'restore')
end)

local function verifyPlacement(e, attempt)
    if not e.source or e.state ~= 'placing' then return end
    local loc = AJ.GetLocation(e.location)
    local ped = GetPlayerPed(e.source)
    if ped == 0 then return activate(e) end

    local c = GetEntityCoords(ped)
    local unknown = c.x == 0.0 and c.y == 0.0
    if unknown or AJ.InZone(loc, c) or AJ.Dist(c, loc.spawn) < 60.0 then
        return activate(e)
    end

    -- Server position lags a moment behind the client teleport.
    if attempt < 3 then
        SetTimeout(1500, function() verifyPlacement(e, attempt + 1) end)
    else
        enforce(e, { kind = e.kind, instant = true })
    end
end

RegisterNetEvent(Event('server:placed'), function()
    local e = Sentences.BySource(source)
    if e and e.state == 'placing' then verifyPlacement(e, 1) end
end)

RegisterNetEvent(Event('server:outside'), function(spawned)
    local e = Sentences.BySource(source)
    if e then onOutside(e, false, spawned == true) end
end)

Bridge.OnLoaded(function(src) attach(src, 'restore') end)

Bridge.OnUnloaded(function(src)
    local e = Sentences.BySource(src)
    if e then
        detach(e)
        TriggerClientEvent(Event('client:suspend'), src)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local e = Sentences.BySource(src)
    if e then detach(e) end

    local info = Known[src]
    if not info then
        local identifier = Bridge.GetIdentifier(src)
        if identifier then info = { identifier = identifier, name = Bridge.GetName(src), account = Bridge.GetAccountName(src) } end
    end
    Known[src] = nil

    if info then
        for i = #Recent, 1, -1 do
            if Recent[i].identifier == info.identifier then table.remove(Recent, i) end
        end
        Recent[#Recent + 1] = {
            identifier = info.identifier, name = info.name, account = info.account,
            droppedAt = now(), jailed = Jailed[info.identifier] ~= nil,
        }
        if #Recent > 30 then table.remove(Recent, 1) end
    end
end)

--[[ Main loop — 1 Hz over the (small) jailed table only ]]

local function flush()
    local list = {}
    for _, e in pairs(Jailed) do
        stamp(e)
        list[#list + 1] = e
    end
    DB.SaveMany(list)
end

CreateThread(function()
    DB.Init()
    local rows = DB.LoadActive()
    for i = 1, #rows do
        local e = fromRow(rows[i])
        Jailed[e.identifier] = e
    end
    loaded = true

    print(('^2[%s]^7 v%s loaded  ·  framework: ^5%s^7  ·  active sentences: ^5%d^7'):format(
        AJ.Resource, GetResourceMetadata(AJ.Resource, 'version', 0), Bridge.Framework, #rows))

    -- Resource restarted while people are online.
    for _, id in ipairs(GetPlayers()) do attach(tonumber(id), 'restore') end

    local lastPos, lastFlush = 0, now()
    local interval = Config.Escape.serverInterval
    local resend = Config.Spawn.settleTimeout + 30

    while true do
        Wait(1000)
        local t = now()
        local game = GetGameTimer()
        local checkPos = Config.Escape.serverCheck and game - lastPos >= interval
        if checkPos then lastPos = game end

        for _, e in pairs(Jailed) do
            if ticking(e) and remaining(e) <= 0 then
                Sentences.Release(e, 'served', 'Time served')
            elseif e.source then
                if e.state == 'placing' and t - e.enforcedAt > resend then
                    enforce(e, { kind = e.kind })
                elseif checkPos and e.state == 'active' then
                    local ped = GetPlayerPed(e.source)
                    if ped ~= 0 then
                        if AJ.InZone(AJ.GetLocation(e.location), GetEntityCoords(ped)) then
                            e.strikes = 0
                        else
                            e.strikes = (e.strikes or 0) + 1
                            if e.strikes >= 2 then
                                e.strikes = 0
                                onOutside(e, true, false)
                            end
                        end
                    end
                end
            end
        end

        if t - lastFlush >= Config.Database.flushInterval then
            lastFlush = t
            local list = {}
            for _, e in pairs(Jailed) do
                if e.source then stamp(e) list[#list + 1] = e end
            end
            DB.SaveMany(list)
        end
    end
end)

AddEventHandler('txAdmin:events:serverShuttingDown', flush)
AddEventHandler('onResourceStop', function(res)
    if res ~= AJ.Resource or not loaded then return end
    flush()
    for src in pairs(Sources) do setBag(src, false) end
end)

--[[ Exports ]]

local function find(target)
    if type(target) == 'number' then return Sentences.BySource(target) end
    return Jailed[target]
end

local function public(e)
    if not e then return nil end
    local p = payload(e)
    p.identifier, p.name, p.source, p.state, p.jailedAt = e.identifier, e.name, e.source, e.state, e.jailedAt
    return p
end

exports('IsJailed', function(target) return find(target) ~= nil end)
exports('GetSentence', function(target) return public(find(target)) end)
exports('GetAll', function()
    local out = {}
    for _, e in pairs(Jailed) do out[#out + 1] = public(e) end
    return out
end)
exports('Jail', function(src, minutes, reason, location, admin)
    return Sentences.Jail({ source = src, minutes = minutes, reason = reason, location = location, admin = admin or 'System' })
end)
exports('JailOffline', function(identifier, minutes, reason, location, admin, name)
    return Sentences.Jail({ identifier = identifier, name = name, minutes = minutes, reason = reason, location = location, admin = admin or 'System' })
end)
exports('Release', function(target, by)
    local e = find(target)
    if not e then return false end
    return Sentences.Release(e, 'released', by or 'System')
end)
exports('AdjustTime', function(target, minutes, by)
    local e = find(target)
    if not e then return false end
    return Sentences.Adjust(e, minutes, by or 'System')
end)

-- v1 export names
exports('IsPlayerJailed', function(src) return Sentences.BySource(src) ~= nil end)
exports('GetJailedData', function(src) return public(Sentences.BySource(src)) end)
exports('JailPlayer', function(src, minutes, reason, location, admin)
    return (Sentences.Jail({ source = src, minutes = minutes, reason = reason, location = location, admin = admin or 'System' }))
end)
exports('ReleasePlayer', function(src)
    local e = Sentences.BySource(src)
    return e and Sentences.Release(e, 'released', 'Export') or false
end)
exports('GetAllJailed', function()
    local out = {}
    for _, e in pairs(Jailed) do out[#out + 1] = public(e) end
    return out
end)
