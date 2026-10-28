--[[
    NAYZEEE RADIO - Jammers (server): placed jammers, expiry, pickup, hack

    A jammer item is used → the client places a ghost and sends 'nzr:jammer:place'. The
    server checks everything again: the type, that the player still has the item (and takes
    it), that the spot is within Config.Jammers.placeDistance + 1.5 m of the player's
    server-side position, that the player is on foot, the per-player limit and that the
    coordinates are real numbers. A jammer runs until its battery dies (Types[t].life
    minutes), its owner (or Config.Jammers.seizeJobs) picks it up, an admin removes it or
    someone hacks it.

    The hack: 'nzr:jammer:hackStart' locks the jammer to one player and hands out a one-use
    token, a seed for the puzzle and the stage count / time of that jammer type. The
    result only counts when the token matches, the player is still within 3 m, and the
    time taken is believable: at least bands x 2.5 s, at most time + 10 s. A failure (or a
    cancel) locks that player out of hacking for Config.Jammers.failLockout seconds. So does
    starting again while an attempt of theirs is still open: the client always posts a
    result, cancels included, so an open one was abandoned - and re-starting it would
    otherwise hold the jammer against everyone else for ever.

    JAMMER (NZR.Jammers.items[id])
      { id, t, x, y, z, h, o = owner server id (0 while offline), e = os.time() expiry,
        owner = identifier, ownerName, placed = os.time() }

    API
      NZR.Jammers.List()                      → { [id] = { t, x, y, z, h, o, e } }  (same as GlobalState)
      NZR.Jammers.Get(id)                     → jammer | nil
      NZR.Jammers.Begin(src, type)            item used: checks, then 'nzr:jammer:begin'
      NZR.Jammers.Place(src, type, coords, heading) → id | nil, err
      NZR.Jammers.Pickup(src, id)             → ok, err
      NZR.Jammers.Remove(id, reason?, by?)    → bool   reason = 'expired' | 'picked' | 'hacked' | 'admin'
      NZR.Jammers.AdminList()                 → { { id, type, label, owner, ownerId, x, y, z, expires, e } }
      NZR.Jammers.CountOf(src)                → active jammers of that player

    Callbacks
      nzr:jammer:hackStart (id) → { ok = true, token, bands, time, seed, type, label }
                                | { ok = false, reason = 'gone' | 'far' | 'busy' | 'denied' | 'lockout', wait }
    Events handled (C→S)
      nzr:jammer:place (type, coords, heading)   nzr:jammer:pickup (id)
      nzr:jammer:hackResult (id, token, success)
    Events sent (S→C)
      nzr:jammer:begin (type)        the user of a jammer item: start placing it
      nzr:jammer:hacked (id, by)     owner: their jammer was hacked (by = server id of the hacker)
    GlobalState
      nzr_jammers = { [id] = { t, x, y, z, h, o, e } }
    Bus (emitted): jammers:changed ()
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Jammers = NZR.Jammers or {}
local J = NZR.Jammers
local Core = NZR.Core

J.items = J.items or {}
J.public = J.public or {}

local hacks = {}          -- [id] = { src, token, started, bands, time }
local hackOf = {}         -- [src] = id
local lockouts = {}       -- [character identifier | src] = GetGameTimer() until which hacking is refused
local counter = 0

local REACH = 3.0         -- metres for pickup and hacking
local PLACE_SLACK = 1.5   -- metres on top of placeDistance (ped position vs. the ghost on the ground)
local TOKEN_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'

local function L(key, ...) return NZR.L('server.' .. key, ...) end

local function cfg()
    return Config.Jammers or {}
end

local function typeDef(t)
    local types = cfg().Types
    return type(t) == 'string' and types and types[t] or nil
end

local function finite(n)
    n = tonumber(n)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

local function distanceTo(src, j)
    local p = Core.SrcCoords(src)
    if not p then return math.huge end
    return NZR.Signal.Distance(p, j)
end

local function ownerSrc(j)
    local o = tonumber(j.o)
    if not o or o <= 0 or not Core.Online(o) then return nil end
    if j.owner and Core.Identifier(o) ~= j.owner then return nil end
    return o
end

local function isOwner(src, j)
    local id = Core.Identifier(src)
    if j.owner and id then return j.owner == id end
    return tonumber(j.o) == src
end

-- A failed hack locks the character, not the server id: reconnecting must not reset it.
local function lockKey(src)
    return Core.Identifier(src) or src
end

local function randomToken(n)
    local out = {}
    for i = 1, n do
        local k = math.random(1, #TOKEN_CHARS)
        out[i] = TOKEN_CHARS:sub(k, k)
    end
    return table.concat(out)
end

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRY
-- ════════════════════════════════════════════════════════════════════════

local function publicOf(j)
    return { t = j.t, x = j.x, y = j.y, z = j.z, h = j.h, o = j.o, e = j.e }
end

local function publish()
    local list = {}
    for id, j in pairs(J.items) do list[id] = publicOf(j) end
    J.public = list
    local ok, err = pcall(function() GlobalState:set('nzr_jammers', list, true) end)
    if not ok then NZR.Warn('could not publish jammers: ' .. tostring(err)) end
    NZR.Bus.Emit('jammers:changed')
end

function J.List()
    return J.public
end

function J.Get(id)
    return J.items[id]
end

function J.CountOf(src)
    local id = Core.Identifier(src)
    local n = 0
    for _, j in pairs(J.items) do
        if (id and j.owner == id) or (not id and tonumber(j.o) == src) then n = n + 1 end
    end
    return n
end

function J.Remove(id, reason, by)
    local j = J.items[id]
    if not j then return false end
    J.items[id] = nil
    local h = hacks[id]
    if h then
        hacks[id] = nil
        if hackOf[h.src] == id then hackOf[h.src] = nil end
    end
    publish()
    NZR.Debug('jammer removed', id, reason or '-', by or '-')
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- PLACE
-- ════════════════════════════════════════════════════════════════════════

local function inVehicle(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local veh = GetVehiclePedIsIn(ped, false)
    return veh ~= nil and veh ~= 0
end

function J.Begin(src, jtype)
    if cfg().enabled == false then return end
    if not typeDef(jtype) then return end
    if inVehicle(src) then
        Core.Notify(src, L('jammer_vehicle'), 'error')
        return
    end
    local max = math.floor(tonumber(cfg().maxPerPlayer) or 1)
    if J.CountOf(src) >= max then
        Core.Notify(src, L('jammer_limit', max), 'error')
        return
    end
    TriggerClientEvent('nzr:jammer:begin', src, jtype)
end

function J.Place(src, jtype, coords, heading)
    if cfg().enabled == false then return nil, 'disabled' end
    local def = typeDef(jtype)
    if not def then return nil, 'invalid' end
    local pos = Bridge.ToVec3(coords)
    local x, y, z = pos and finite(pos.x), pos and finite(pos.y), pos and finite(pos.z)
    if not x or not y or not z or math.abs(x) > 20000 or math.abs(y) > 20000 or z < -500 or z > 3000 then
        return nil, 'invalid'
    end
    local h = finite(heading) or 0.0
    h = h % 360.0

    if inVehicle(src) then return nil, 'vehicle' end
    local me = Core.SrcCoords(src)
    if not me then return nil, 'invalid' end
    local reach = (tonumber(cfg().placeDistance) or 3.0) + PLACE_SLACK
    if NZR.Signal.Distance(me, { x = x, y = y, z = z }) > reach then return nil, 'far' end

    local max = math.floor(tonumber(cfg().maxPerPlayer) or 1)
    if J.CountOf(src) >= max then return nil, 'limit' end

    local item = Config.Items and Config.Items[jtype]
    if type(item) ~= 'string' or (tonumber(Core.B('Inv.Count', src, item)) or 0) < 1 then return nil, 'noitem' end
    if not Core.B('Inv.RemoveItem', src, item, 1) then return nil, 'noitem' end

    counter = counter + 1
    local id = ('J%d%s'):format(counter, randomToken(3))
    local now = os.time()
    J.items[id] = {
        id = id, t = jtype,
        x = math.floor(x * 100 + 0.5) / 100, y = math.floor(y * 100 + 0.5) / 100, z = math.floor(z * 100 + 0.5) / 100,
        h = math.floor(h * 10 + 0.5) / 10,
        o = src, e = now + math.max(1, tonumber(def.life) or 15) * 60,
        owner = Core.Identifier(src), ownerName = Core.Name(src), placed = now,
    }
    publish()
    Core.Webhook('jammers', L('wh_jammer_placed'), {
        Core.WebhookField(L('wh_player'), ('%s (%d)'):format(Core.Name(src), src)),
        Core.WebhookField(L('wh_type'), def.label or jtype),
        Core.WebhookField(L('wh_coords'), ('%.1f, %.1f, %.1f'):format(x, y, z), false),
    })
    return id
end

-- ════════════════════════════════════════════════════════════════════════
-- PICKUP
-- ════════════════════════════════════════════════════════════════════════

local function canSeize(src)
    local jobs = cfg().seizeJobs
    if type(jobs) ~= 'table' then return false end
    return Bridge.JobMatches(Core.B('GetJob', src), jobs, false)
end

function J.Pickup(src, id)
    local j = J.items[id]
    if not j then return false, 'gone' end
    if distanceTo(src, j) > REACH then return false, 'far' end
    local owner = isOwner(src, j)
    if not owner and not canSeize(src) then return false, 'denied' end
    local item = Config.Items and Config.Items[j.t]
    if type(item) ~= 'string' then return false, 'gone' end
    if Core.Has('Inv.CanCarry') and not Core.B('Inv.CanCarry', src, item, 1) then return false, 'full' end

    -- off the map first, so two quick pickups can never hand out two items
    J.Remove(id, 'picked', src)
    if not Core.B('Inv.AddItem', src, item, 1) then
        J.items[id] = j
        publish()
        return false, 'full'
    end

    local def = typeDef(j.t) or {}
    if not owner then
        local o = ownerSrc(j)
        if o and o ~= src then Core.Notify(o, L('jammer_seized_owner', def.label or j.t), 'warning') end
    end
    Core.Webhook('jammers', L(owner and 'wh_jammer_picked' or 'wh_jammer_seized'), {
        Core.WebhookField(L('wh_player'), ('%s (%d)'):format(Core.Name(src), src)),
        Core.WebhookField(L('wh_type'), def.label or j.t),
        Core.WebhookField(L('wh_owner'), j.ownerName or '-'),
    })
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- HACK
-- ════════════════════════════════════════════════════════════════════════

local function hackAllowed(src)
    local jobs = cfg().hackJobs
    if type(jobs) ~= 'table' then return true end
    return Bridge.JobMatches(Core.B('GetJob', src), jobs, false)
end

local function releaseHack(id)
    local h = hacks[id]
    if not h then return end
    hacks[id] = nil
    if hackOf[h.src] == id then hackOf[h.src] = nil end
end

local function lockOut(src, now)
    local ms = math.max(0, tonumber(cfg().failLockout) or 20) * 1000
    lockouts[lockKey(src)] = now + ms
    return { ok = false, reason = 'lockout', wait = math.ceil(ms / 1000) }
end

function J.HackStart(src, id)
    local j = J.items[id]
    if not j then return { ok = false, reason = 'gone' } end
    if not hackAllowed(src) then return { ok = false, reason = 'denied' } end
    local now = GetGameTimer()
    local lock = lockouts[lockKey(src)]
    if lock and lock > now then
        return { ok = false, reason = 'lockout', wait = math.ceil((lock - now) / 1000) }
    end
    -- an attempt of this player's still open (this jammer or another) was abandoned: it
    -- counts as a failed one, and the jammer it held is free for others
    local open = hackOf[src]
    if open then
        hackOf[src] = nil
        local mine = hacks[open]
        if mine and mine.src == src then hacks[open] = nil end
        return lockOut(src, now)
    end
    if distanceTo(src, j) > REACH then return { ok = false, reason = 'far' } end

    local h = hacks[id]
    if h and now - h.started < (h.time + 10) * 1000 and Core.Online(h.src) then
        return { ok = false, reason = 'busy' }
    end
    -- a run-out attempt of someone else: theirs no longer, so their next start is not "open"
    if h and hackOf[h.src] == id then hackOf[h.src] = nil end

    local def = typeDef(j.t) or {}
    local bands = NZR.Util.Clamp(math.floor(tonumber(def.bands) or 1), 1, 5)
    local time = math.max(5, math.floor(tonumber(def.time) or 30))
    local session = {
        src = src, token = randomToken(24), started = now, bands = bands, time = time,
        seed = math.random(1, 2147483646),
    }
    hacks[id] = session
    hackOf[src] = id
    return { ok = true, token = session.token, bands = bands, time = time, seed = session.seed, type = j.t, label = def.label }
end

function J.HackResult(src, id, token, success)
    local h = hacks[id]
    if not h or h.src ~= src or type(token) ~= 'string' or token ~= h.token then return false end
    releaseHack(id)
    local j = J.items[id]
    if not j then return false end

    local now = GetGameTimer()
    local elapsed = now - h.started
    local believable = elapsed >= h.bands * 2500 and elapsed <= (h.time + 10) * 1000
    if success == true and believable and distanceTo(src, j) <= REACH then
        J.Remove(id, 'hacked', src)
        local o = ownerSrc(j)
        if o then TriggerClientEvent('nzr:jammer:hacked', o, id, src) end
        local def = typeDef(j.t) or {}
        Core.Webhook('jammers', L('wh_jammer_hacked'), {
            Core.WebhookField(L('wh_player'), ('%s (%d)'):format(Core.Name(src), src)),
            Core.WebhookField(L('wh_type'), def.label or j.t),
            Core.WebhookField(L('wh_owner'), j.ownerName or '-'),
            Core.WebhookField(L('wh_time'), ('%.1f s'):format(elapsed / 1000)),
        })
        return true
    end
    if success == true and not believable then
        NZR.Debug(('hack result from %d refused: %.1f s for %d bands'):format(src, elapsed / 1000, h.bands))
    end
    lockOut(src, now)
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- ADMIN
-- ════════════════════════════════════════════════════════════════════════

function J.AdminList()
    local out, now = {}, os.time()
    for id, j in pairs(J.items) do
        local def = typeDef(j.t) or {}
        out[#out + 1] = {
            id = id, type = j.t, label = def.label or j.t,
            owner = j.ownerName, ownerId = ownerSrc(j),
            x = j.x, y = j.y, z = j.z,
            expires = math.max(0, j.e - now), e = j.e, placed = j.placed,
        }
    end
    table.sort(out, function(a, b) return a.e < b.e end)
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- NET EVENTS / CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

local function cleanId(id)
    if type(id) ~= 'string' or #id > 24 then return nil end
    return id
end

RegisterNetEvent('nzr:jammer:place', function(jtype, coords, heading)
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    if not Core.Rate('nzr:jammer:place', src, 3, 5000) then return end
    local id, err = J.Place(src, jtype, coords, heading)
    if not id then Core.Notify(src, L('jammer_' .. tostring(err), math.floor(tonumber(cfg().maxPerPlayer) or 1)), 'error') end
end)

RegisterNetEvent('nzr:jammer:pickup', function(id)
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    id = cleanId(id)
    if not id or not Core.Rate('nzr:jammer:pickup', src, 4, 3000) then return end
    local ok, err = J.Pickup(src, id)
    if ok then
        Core.Notify(src, L('jammer_picked'), 'success')
    else
        Core.Notify(src, L('jammer_' .. tostring(err)), 'error')
    end
end)

NZR.Callback('nzr:jammer:hackStart', function(src, id)
    id = cleanId(id)
    if not id then return { ok = false, reason = 'gone' } end
    if not Core.Rate('nzr:jammer:hackStart', src, 4, 5000) then return { ok = false, reason = 'busy' } end
    return J.HackStart(src, id)
end)

RegisterNetEvent('nzr:jammer:hackResult', function(id, token, success)
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    id = cleanId(id)
    if not id or not Core.Rate('nzr:jammer:hackResult', src, 4, 3000) then return end
    J.HackResult(src, id, token, success == true)
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

-- batteries run flat
CreateThread(function()
    Wait(0)
    publish()
    while true do
        Wait(10000)
        local now = os.time()
        local gone = {}
        for id, j in pairs(J.items) do
            if j.e <= now then gone[#gone + 1] = id end
        end
        for _, id in ipairs(gone) do
            local j = J.items[id]
            local o = j and ownerSrc(j)
            J.Remove(id, 'expired')
            if o then
                local def = typeDef(j.t) or {}
                Core.Notify(o, L('jammer_expired', def.label or j.t), 'info')
            end
        end
        local t = GetGameTimer()
        for key, untilAt in pairs(lockouts) do
            if untilAt <= t then lockouts[key] = nil end
        end
    end
end)

-- the owner comes back on another server id: their jammers follow them
NZR.Bus.On('player:loaded', function(src)
    local id = Core.Identifier(src)
    if not id then return end
    local changed = false
    for _, j in pairs(J.items) do
        if j.owner == id and j.o ~= src then
            j.o = src
            changed = true
        end
    end
    if changed then publish() end
end)

NZR.Bus.On('player:dropped', function(src)
    lockouts[src] = nil   -- only the id-keyed entry: a character's lockout outlives the session
    local id = hackOf[src]
    if id then releaseHack(id) end
    local changed = false
    for _, j in pairs(J.items) do
        if tonumber(j.o) == src then
            j.o = 0
            changed = true
        end
    end
    if changed then publish() end
end)

-- A restart would swallow every running jammer: hand them back to owners who are online.
AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    for _, j in pairs(J.items) do
        local o = ownerSrc(j)
        local item = Config.Items and Config.Items[j.t]
        if o and type(item) == 'string' then
            pcall(function() Bridge.Inv.AddItem(o, item, 1) end)
        end
    end
    J.items, J.public = {}, {}
    pcall(function() GlobalState:set('nzr_jammers', nil, true) end)
end)
