--[[
    NAYZEEE RADIO - Alerts (server): emergency button, gunfire over an open mic, roster

    EMERGENCY  'nzr:alerts:emergency' (device). Config.Emergency: enabled, jobs (false =
               everyone), cooldown per player. Needs a powered radio with a frequency on the
               TX slot (handheld) or an operating seat in a car whose head unit is on and
               tuned (vehicle). Everyone on that frequency - members of the channel, muted
               ones too, and everyone inside a car tuned to it - gets 'nzr:alerts:emergency'.
               The caller's mic then stays open for Config.Emergency.hotMic seconds (a forced
               transmission through NZR.Routing, rx info emergency = true, heard by muted
               radios as well). ServerConfig.EmergencyHook runs in a pcall; webhook 'emergency'.
    GUNFIRE    'nzr:alerts:shots' (shots). Only while that player has a live transmission.
               ≤ 30 shots per batch, dt integer 0..1000 ms, kind from a fixed list, d
               0..Config.Gunfire.radius m, at most Config.Gunfire.maxPerSecond shots a second.
               Relayed as 'nzr:rx:shots' to the talker's current listeners with each one's q.
    ROSTER     'nzr:roster:watch' (on). A watcher sees the channel on their TX slot:
               'nzr:roster:data' (fkey, { label, access, count, members = { { id, name, callsign, bars, talking } } })
               on join / leave / talk / callsign changes and every Config.Roster.refresh ms.
               bars are from the watcher's point of view (NZR.Signal); name follows
               Config.Roster.nameFormat; at most Config.Roster.maxRows rows, talking first,
               then by name. fkey = nil (empty members) when the watcher's TX slot is empty.

    API
      NZR.Alerts.Emergency(src, device)     → ok, reason ('disabled' | 'denied' | 'cooldown' | 'nofreq')
      NZR.Alerts.Roster(fkey, viewer)       → { label, members }
      NZR.Alerts.PushRoster(src)            NZR.Alerts.RosterDirty(fkey)

    Events handled (C→S)
      nzr:alerts:emergency (device)   nzr:alerts:shots (shots)   nzr:roster:watch (on)
    Events sent (S→C)
      nzr:alerts:emergency ({ talker, name, callsign, fkey, coords })   every listener of fkey
      nzr:tx:denied ('cooldown' | 'nofreq')                              the caller
      nzr:rx:shots (talker, shots, q)                                    the talker's listeners
      nzr:roster:data (fkey | nil, { label, members })                   watchers
    Bus (emitted): radio:emergency (src, fkey)
    Bus (listens): radio:joined / radio:left / radio:talking (src, fkey), radio:callsign (src),
                   radio:txslot (src), radio:power (src), player:dropped (src)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Alerts = NZR.Alerts or {}
local A = NZR.Alerts
local Core = NZR.Core

local MAX_SHOTS = 30
local KINDS = { pistol = true, smg = true, rifle = true, shotgun = true, sniper = true, heavy = true, silenced = true }

local lastAlert = {}      -- [src] = os.time() of the last emergency
local watchers = {}       -- [src] = { fkey = last fkey sent | false }
local dirty = {}          -- [fkey] = true, waiting for the next roster flush
local flushQueued = false

local function L(key, ...) return NZR.L('server.' .. key, ...) end

-- ════════════════════════════════════════════════════════════════════════
-- EMERGENCY
-- ════════════════════════════════════════════════════════════════════════

local function emergencyFkey(src, device)
    if device == 'vehicle' then
        local veh, _, st = NZR.Routing.VehicleOf(src)
        if not veh then return nil end
        return NZR.Freq.Key(st.f)
    end
    local rec = NZR.Radio.players[src]
    if not rec or not rec.power or not rec.model then return nil end
    return NZR.Freq.Key(rec.slots[rec.txSlot])
end

-- Every member of the channel (muted too) and everyone in a car tuned to it.
local function emergencyAudience(src, fkey)
    local out, seen = {}, { [src] = true }
    for id in pairs(NZR.Radio.members[fkey] or {}) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    local coords = NZR.Routing.RefreshCoords(true)
    local tuned = NZR.Vehicles.Tuned(fkey)
    if next(tuned) then
        for id, c in pairs(coords) do
            if c.veh and tuned[c.veh] and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    return out
end

function A.Emergency(src, device)
    local cfg = Config.Emergency or {}
    if not cfg.enabled then return false, 'disabled' end
    if device ~= 'vehicle' then device = 'handheld' end

    if type(cfg.jobs) == 'table' and not Bridge.JobMatches(Core.B('GetJob', src), cfg.jobs, false) then
        Core.Notify(src, L('emergency_denied'), 'error')
        return false, 'denied'
    end

    local now = os.time()
    local cooldown = math.max(0, tonumber(cfg.cooldown) or 30)
    if lastAlert[src] and now - lastAlert[src] < cooldown then
        TriggerClientEvent('nzr:tx:denied', src, 'cooldown')
        return false, 'cooldown'
    end

    local fkey = emergencyFkey(src, device)
    if not fkey then
        TriggerClientEvent('nzr:tx:denied', src, 'nofreq')
        return false, 'nofreq'
    end
    lastAlert[src] = now

    local rec = NZR.Radio.players[src]
    local p = Core.SrcCoords(src)
    local coords = p and vector3(p.x, p.y, p.z) or nil
    local payload = {
        talker = src,
        name = (rec and rec.name) or Core.Name(src),
        callsign = rec and rec.callsign or nil,
        fkey = fkey,
        coords = coords,
    }
    for _, id in ipairs(emergencyAudience(src, fkey)) do
        TriggerClientEvent('nzr:alerts:emergency', id, payload)
    end

    local hot = math.max(0, tonumber(cfg.hotMic) or 0)
    if hot > 0 then
        NZR.Routing.Start(src, device, { emergency = true, duration = hot * 1000, silent = true })
    end

    local hook = ServerConfig and ServerConfig.EmergencyHook
    if type(hook) == 'function' then
        local ok, err = pcall(hook, src, fkey, coords)
        if not ok then NZR.Warn('ServerConfig.EmergencyHook failed: ' .. tostring(err)) end
    end

    Core.Webhook('emergency', L('wh_emergency'), {
        Core.WebhookField(L('wh_player'), ('%s (%d)'):format(payload.name, src)),
        Core.WebhookField(L('wh_callsign'), payload.callsign or '-'),
        Core.WebhookField(L('wh_freq'), fkey),
        Core.WebhookField(L('wh_coords'), coords and ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z) or '-', false),
    })
    NZR.Bus.Emit('radio:emergency', src, fkey)
    return true
end

RegisterNetEvent('nzr:alerts:emergency', function(device)
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    if not Core.Rate('nzr:alerts:emergency', src, 3, 5000) then return end
    A.Emergency(src, device)
end)

-- ════════════════════════════════════════════════════════════════════════
-- GUNFIRE
-- ════════════════════════════════════════════════════════════════════════

local function cleanShots(src, shots)
    local cfg = Config.Gunfire or {}
    local radius = tonumber(cfg.radius) or 60.0
    local perSecond = math.max(1, math.floor(tonumber(cfg.maxPerSecond) or 20))
    local out = {}
    for i = 1, #shots do
        local s = shots[i]
        if type(s) == 'table' then
            local dt, d = tonumber(s.dt), tonumber(s.d)
            if dt and d and KINDS[s.kind] and dt == math.floor(dt) and dt >= 0 and dt <= 1000 and d >= 0 and d <= radius then
                if not Core.Rate('nzr:alerts:shot', src, perSecond, 1000) then break end
                out[#out + 1] = { dt = math.floor(dt), kind = s.kind, d = math.floor(d * 10 + 0.5) / 10 }
            end
        end
    end
    return out
end

RegisterNetEvent('nzr:alerts:shots', function(shots)
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    if not (Config.Gunfire and Config.Gunfire.enabled) then return end
    if type(shots) ~= 'table' or #shots == 0 or #shots > MAX_SHOTS then return end
    -- the client flushes every 150 ms; a little headroom for timing jitter
    if not Core.Rate('nzr:alerts:shots', src, 12, 1000) then return end
    local tx = NZR.Routing.Get(src)
    if not tx then return end
    local clean = cleanShots(src, shots)
    if #clean == 0 then return end
    for id, info in pairs(tx.listeners) do
        TriggerClientEvent('nzr:rx:shots', id, src, clean, info.q)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- ROSTER
-- ════════════════════════════════════════════════════════════════════════

local function rosterCfg()
    return Config.Roster or {}
end

local function formatName(fmt, name, callsign, id)
    fmt = type(fmt) == 'string' and fmt or '{name} {callsign}'
    local out = fmt:gsub('{name}', function() return name or '' end)
        :gsub('{callsign}', function() return callsign or '' end)
        :gsub('{id}', function() return tostring(id) end)
    out = out:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if out == '' then out = name or ('#' .. tostring(id)) end
    return out
end

local function watcherFkey(src)
    local rec = NZR.Radio.players[src]
    if not rec or not rec.power then return nil end
    return NZR.Freq.Key(rec.slots[rec.txSlot])
end

function A.Roster(fkey, viewer)
    local coords = NZR.Routing.RefreshCoords()
    local jammers = NZR.Jammers.List()
    local me = NZR.Routing.SideOf(viewer)
    local rows, seen = {}, {}
    local fmt = rosterCfg().nameFormat

    local function add(id, side)
        if seen[id] then return end
        seen[id] = true
        local rec = NZR.Radio.players[id]
        local tx = NZR.Routing.active[id]
        local talking = tx ~= nil and tx.fkey == fkey
        local name = (rec and rec.name) or (tx and tx.name) or Core.Name(id)
        local callsign = (rec and rec.callsign) or (tx and tx.callsign) or nil
        local q = 0.0
        if coords[id] and coords[viewer] then
            q = NZR.Signal.Quality(me, side or NZR.Routing.SideOf(id), jammers)
        end
        rows[#rows + 1] = {
            id = id,
            name = formatName(fmt, name, callsign, id),
            callsign = callsign,
            bars = NZR.Signal.Bars(q),
            talking = talking,
            sortName = tostring(name):lower(),
        }
    end

    for id in pairs(NZR.Radio.members[fkey] or {}) do add(id) end
    -- people talking through a head unit are on the channel without a handheld
    for id, tx in pairs(NZR.Routing.active) do
        if tx.fkey == fkey then add(id, NZR.Routing.TalkerSide(id, tx)) end
    end

    table.sort(rows, function(a, b)
        if a.talking ~= b.talking then return a.talking end
        if a.sortName ~= b.sortName then return a.sortName < b.sortName end
        return a.id < b.id
    end)
    local max = math.max(1, math.floor(tonumber(rosterCfg().maxRows) or 10))
    local members = {}
    for i = 1, math.min(#rows, max) do
        local r = rows[i]
        r.sortName = nil
        members[i] = r
    end
    -- count = everyone on the channel (the card shows a few rows and counts the rest)
    local label, access = NZR.Channels.Label(fkey)
    return { label = label, access = access, count = #rows, members = members }
end

function A.PushRoster(src)
    local w = watchers[src]
    if not w then return end
    local fkey = watcherFkey(src)
    if not fkey then
        if w.fkey ~= nil then
            w.fkey = nil
            TriggerClientEvent('nzr:roster:data', src, nil, { label = nil, members = {} })
        end
        return
    end
    w.fkey = fkey
    TriggerClientEvent('nzr:roster:data', src, fkey, A.Roster(fkey, src))
end

local function flush()
    flushQueued = false
    local pending = dirty
    dirty = {}
    for src, w in pairs(watchers) do
        local fkey = watcherFkey(src)
        if (fkey and pending[fkey]) or fkey ~= w.fkey then A.PushRoster(src) end
    end
end

-- Several changes in a row (a whole squad tuning in) become one push.
local function queueFlush()
    if flushQueued then return end
    flushQueued = true
    SetTimeout(150, flush)
end

function A.RosterDirty(fkey)
    if not fkey or not next(watchers) then return end
    dirty[fkey] = true
    queueFlush()
end

-- A watcher whose own TX slot changed is picked up by flush (fkey ~= what it was sent).
local function dirtyPlayer(src)
    for fkey in pairs(NZR.Radio.FkeysOf(src)) do A.RosterDirty(fkey) end
    local tx = NZR.Routing.active[src]
    if tx then A.RosterDirty(tx.fkey) end
    if watchers[src] then queueFlush() end
end

RegisterNetEvent('nzr:roster:watch', function(on)
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    if not Core.Rate('nzr:roster:watch', src, 6, 2000) then return end
    if on and rosterCfg().enabled ~= false then
        watchers[src] = { fkey = false }
        A.PushRoster(src)
    else
        watchers[src] = nil
    end
end)

NZR.Bus.On('radio:joined', function(_, fkey) A.RosterDirty(fkey) end)
NZR.Bus.On('radio:left', function(_, fkey) A.RosterDirty(fkey) end)
NZR.Bus.On('radio:talking', function(_, fkey) A.RosterDirty(fkey) end)
NZR.Bus.On('radio:callsign', function(src) dirtyPlayer(src) end)
NZR.Bus.On('radio:txslot', function(src) dirtyPlayer(src) end)
NZR.Bus.On('radio:power', function(src) dirtyPlayer(src) end)

NZR.Bus.On('player:dropped', function(src)
    watchers[src] = nil
    lastAlert[src] = nil
end)

-- signal bars move as people move
CreateThread(function()
    while true do
        local every = math.max(1000, math.floor(tonumber(rosterCfg().refresh) or 5000))
        Wait(every)
        if next(watchers) then
            local ids = {}
            for src in pairs(watchers) do ids[#ids + 1] = src end
            for _, src in ipairs(ids) do
                if Core.Online(src) then A.PushRoster(src) else watchers[src] = nil end
            end
        end
    end
end)
