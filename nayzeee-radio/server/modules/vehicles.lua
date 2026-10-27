--[[
    NAYZEEE RADIO - Vehicles (server): radio vehicle list and head unit state

    Which vehicles carry an MV-90 head unit: every model in Config.Vehicles.models, every
    vehicle class in Config.Vehicles.classes, and the list admins keep in /radioadmin
    (database; an admin entry overrides a config model with the same name). The list is
    published as GlobalState 'nzr_vehicles' for the clients.

    A head unit's state lives on the vehicle itself, in Entity(veh).state.nzr_vradio, and only
    the server writes it, after checking that the sender sits in an operating seat
    (Config.Vehicles.seats) of a radio vehicle. Tuning goes through 'nzr:vehicle:join' and the
    same access rules as a handheld (NZR.Channels.Check). Routing finds tuned cars through an
    index by frequency kept here (rebuilt on every state change, deleted vehicles pruned).

    The class check: GTA's vehicle class is only known on the client, so a vehicle whose
    model is not listed counts as a radio vehicle when classes are configured. The worst a
    cheater gets from that is a head unit in a car that has none; channel access is still
    checked here for every tune.

    API
      NZR.Vehicles.Publish()                   rebuild and publish GlobalState nzr_vehicles
      NZR.Vehicles.Reload()                    re-read the admin list (after a save), then Publish
      NZR.Vehicles.AdminList()                 → { { model, label, range_mult }, ... }
      NZR.Vehicles.IsRadioVehicle(veh)         → bool
      NZR.Vehicles.Seated(src, veh)            → bool (operating seat)
      NZR.Vehicles.State(veh)                  → nzr_vradio | nil
      NZR.Vehicles.Write(veh, state|nil)       set nzr_vradio (replicated) + index
      NZR.Vehicles.RangeMult(veh)              → number (1.0 when not listed)
      NZR.Vehicles.Tuned(fkey)                 → { [veh] = { vnet, state } }   powered head units on fkey
      NZR.Vehicles.TunedCounts()               → { [fkey] = n }
      NZR.Vehicles.Hash(h)                     → the same model hash as a signed 32-bit number

    Callbacks
      nzr:vehicle:join (vnet, freq, code?)     → { ok = true, label, access, freq } | { ok = false, reason }
                                                 reason ∈ denied, code, badcode, locked, invalid, busy
    Events handled (C→S)
      nzr:vehicle:set (vnet, patch = { on?, f? (false = clear; a frequency only if already
                       allowed without a code), v? (0..1), mute? })
    State bags / GlobalState
      Entity(veh).state.nzr_vradio = { on, f = fkey | nil, v = 0..1, mute, label }   (server only)
      GlobalState.nzr_vehicles = { models = { [hash] = { label, range, model } }, classes = { [n] = true } }
                                 hash = signed 32-bit (as GetEntityModel on the client),
                                 range = multiplier of Config.Vehicles.range
    Bus (emitted): vehicles:changed (fkeyOld | nil, fkeyNew | nil)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Vehicles = NZR.Vehicles or {}
local V = NZR.Vehicles
local Core = NZR.Core

V.models = V.models or {}     -- [hash] = { label, range, model }
V.classes = V.classes or {}   -- [class] = true
V.tuned = V.tuned or {}       -- [fkey] = { [veh] = true }
V.byVeh = V.byVeh or {}       -- [veh] = fkey (powered and tuned)

local adminList = {}
local written = {}            -- [veh] = true: every vehicle we put a state on (cleared on stop)

local function cfg()
    return Config.Vehicles or {}
end

-- Model hashes as signed 32-bit numbers, like GetEntityModel / GetHashKey give them on the
-- client: the server may hand the same hash back unsigned, and a table key must match.
local function signedHash(h)
    h = tonumber(h)
    if not h then return nil end
    h = math.floor(h) % 4294967296
    if h >= 2147483648 then h = h - 4294967296 end
    return h
end
V.Hash = signedHash

local function modelHash(veh)
    local ok, hash = pcall(GetEntityModel, veh)
    return ok and signedHash(hash) or nil
end

local function enabled()
    return cfg().enabled ~= false
end

-- ════════════════════════════════════════════════════════════════════════
-- RADIO VEHICLE LIST
-- ════════════════════════════════════════════════════════════════════════

function V.Publish()
    local models, classes = {}, {}
    if enabled() then
        for _, name in ipairs(cfg().models or {}) do
            if type(name) == 'string' and name ~= '' then
                models[signedHash(GetHashKey(name))] = { label = name:upper(), range = 1.0, model = name }
            end
        end
        for _, row in ipairs(adminList) do
            models[signedHash(GetHashKey(row.model))] = { label = row.label or row.model:upper(), range = row.range_mult or 1.0, model = row.model }
        end
        for _, c in ipairs(cfg().classes or {}) do
            local n = tonumber(c)
            if n then classes[math.floor(n)] = true end
        end
    end
    V.models, V.classes = models, classes
    local ok, err = pcall(function() GlobalState:set('nzr_vehicles', { models = models, classes = classes }, true) end)
    if not ok then NZR.Warn('could not publish the radio vehicle list: ' .. tostring(err)) end
end

function V.Reload()
    local rows = NZR.DB.LoadVehicles()
    local list = {}
    for _, row in ipairs(rows) do
        if type(row.model) == 'string' and row.model:match('^[%w_]+$') then
            list[#list + 1] = {
                model = row.model:lower(),
                label = Bridge.CleanText(row.label, 32),
                range_mult = NZR.Util.Clamp(tonumber(row.range_mult) or 1.0, 0.5, 3.0),
            }
        end
    end
    table.sort(list, function(a, b) return a.model < b.model end)
    adminList = list
    V.Publish()
end

function V.AdminList()
    local out = {}
    for i, row in ipairs(adminList) do
        out[i] = { model = row.model, label = row.label, range_mult = row.range_mult }
    end
    return out
end

function V.IsRadioVehicle(veh)
    if not enabled() or not veh or veh == 0 then return false end
    local hash = modelHash(veh)
    if hash and V.models[hash] then return true end
    if next(V.classes) == nil then return false end
    if type(GetVehicleClass) == 'function' then
        local ok, class = pcall(GetVehicleClass, veh)
        if ok and class ~= nil then return V.classes[class] == true end
    end
    return true
end

function V.RangeMult(veh)
    if not veh or veh == 0 then return 1.0 end
    local hash = modelHash(veh)
    local entry = hash and V.models[hash]
    return entry and tonumber(entry.range) or 1.0
end

function V.Seated(src, veh)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not veh or veh == 0 then return false end
    for _, seat in ipairs(cfg().seats or { -1, 0 }) do
        if GetPedInVehicleSeat(veh, seat) == ped then return true end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- HEAD UNIT STATE + TUNED INDEX
-- ════════════════════════════════════════════════════════════════════════

function V.State(veh)
    if not veh or veh == 0 then return nil end
    local ok, st = pcall(function() return Entity(veh).state.nzr_vradio end)
    if ok and type(st) == 'table' then return st end
    return nil
end

local function unindex(veh)
    local fkey = V.byVeh[veh]
    if not fkey then return nil end
    V.byVeh[veh] = nil
    local set = V.tuned[fkey]
    if set then
        set[veh] = nil
        if next(set) == nil then V.tuned[fkey] = nil end
    end
    return fkey
end

local function index(veh, st)
    local old = unindex(veh)
    local fkey = (type(st) == 'table' and st.on and NZR.Freq.Key(st.f)) or nil
    if fkey then
        V.byVeh[veh] = fkey
        V.tuned[fkey] = V.tuned[fkey] or {}
        V.tuned[fkey][veh] = true
    end
    return old, fkey
end

function V.Write(veh, st)
    if not veh or veh == 0 then return end
    local ok, err = pcall(function() Entity(veh).state:set('nzr_vradio', st, true) end)
    if not ok then
        NZR.Warn('could not write a head unit state: ' .. tostring(err))
        return
    end
    written[veh] = st ~= nil or nil
    local old, new = index(veh, st)
    NZR.Bus.Emit('vehicles:changed', old, new)
end

local function prune()
    for veh in pairs(V.byVeh) do
        if not DoesEntityExist(veh) then
            local fkey = unindex(veh)
            written[veh] = nil
            NZR.Bus.Emit('vehicles:changed', fkey, nil)
        end
    end
    for veh in pairs(written) do
        if not DoesEntityExist(veh) then written[veh] = nil end
    end
end

function V.Tuned(fkey)
    local out = {}
    local set = fkey and V.tuned[fkey]
    if not set then return out end
    for veh in pairs(set) do
        if DoesEntityExist(veh) then
            local st = V.State(veh)
            if st and st.on and NZR.Freq.Key(st.f) == fkey then
                out[veh] = { vnet = NetworkGetNetworkIdFromEntity(veh), state = st }
            end
        end
    end
    return out
end

function V.TunedCounts()
    local out = {}
    for fkey, set in pairs(V.tuned) do out[fkey] = NZR.Util.Count(set) end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- VALIDATION
-- ════════════════════════════════════════════════════════════════════════

local function defaultState()
    local v = (tonumber(Config.Radios and Config.Radios.volume) or 60) / 100
    return { on = false, f = nil, v = NZR.Util.Clamp(v, 0.0, 1.0), mute = false, label = nil }
end

local function copyState(st)
    local base = defaultState()
    if type(st) ~= 'table' then return base end
    return {
        on = st.on == true,
        f = NZR.Freq.Key(st.f),
        v = tonumber(st.v) and NZR.Util.Clamp(tonumber(st.v), 0.0, 1.0) or base.v,
        mute = st.mute == true,
        label = type(st.label) == 'string' and st.label or nil,
    }
end

-- The vehicle the sender may work: networked, a radio vehicle, sender in an operating seat.
local function vehicleFor(src, vnet)
    if not enabled() then return nil end
    vnet = tonumber(vnet)
    if not vnet or vnet ~= math.floor(vnet) or vnet <= 0 then return nil end
    local veh = NetworkGetEntityFromNetworkId(vnet)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    -- the seat check also turns away anything that is not a vehicle (no seats, no match)
    if not V.Seated(src, veh) then return nil end
    if not V.IsRadioVehicle(veh) then return nil end
    return veh
end

-- ════════════════════════════════════════════════════════════════════════
-- NET EVENTS / CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nzr:vehicle:set', function(vnet, patch)
    local src = source
    if Core.IsLocalSource(src) then return end
    src = tonumber(src)
    if type(patch) ~= 'table' then return end
    if not Core.Rate('nzr:vehicle:set', src, 12, 2000) then return end
    local veh = vehicleFor(src, vnet)
    if not veh then return end

    local st = copyState(V.State(veh))
    if patch.on ~= nil then st.on = patch.on == true end
    if patch.mute ~= nil then st.mute = patch.mute == true end
    if patch.v ~= nil then
        local v = tonumber(patch.v)
        if v and v == v then st.v = math.floor(NZR.Util.Clamp(v, 0.0, 1.0) * 100 + 0.5) / 100 end
    end
    if patch.f ~= nil then
        if patch.f == false then
            st.f, st.label = nil, nil
        else
            -- a plain set never tunes past a lock: code / job channels go through nzr:vehicle:join
            local fkey = NZR.Freq.Key(patch.f)
            if fkey and NZR.Freq.Valid(fkey) and NZR.Channels.Allowed(src, fkey) then
                st.f = fkey
                st.label = NZR.Channels.Label(fkey)
            end
        end
    end
    V.Write(veh, st)
end)

NZR.Callback('nzr:vehicle:join', function(src, vnet, freq, code)
    if not Core.Rate('nzr:vehicle:join', src, 8, 2000) then return { ok = false, reason = 'busy' } end
    local veh = vehicleFor(src, vnet)
    if not veh then return { ok = false, reason = 'denied' } end
    local f = NZR.Freq.Parse(freq)
    if not f or not NZR.Freq.Valid(f) then return { ok = false, reason = 'invalid' } end
    local fkey = NZR.Freq.Key(f)
    if code ~= nil and type(code) ~= 'string' and type(code) ~= 'number' then code = nil end
    local ok, reason = NZR.Channels.Check(src, fkey, code)
    if not ok then return { ok = false, reason = reason or 'denied' } end

    local st = copyState(V.State(veh))
    st.f = fkey
    local label, access = NZR.Channels.Label(fkey)
    st.label = label
    V.Write(veh, st)
    return { ok = true, label = label, access = access, freq = fkey }
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('entityRemoved', function(ent)
    if V.byVeh[ent] then
        local fkey = unindex(ent)
        NZR.Bus.Emit('vehicles:changed', fkey, nil)
    end
    written[ent] = nil
end)

CreateThread(function()
    Wait(0)
    V.Publish()      -- the configured models straight away, the admin list once the database answers
    V.Reload()
    while true do
        Wait(5000)
        prune()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    for veh in pairs(written) do
        if DoesEntityExist(veh) then
            pcall(function() Entity(veh).state:set('nzr_vradio', nil, true) end)
        end
    end
    pcall(function() GlobalState:set('nzr_vehicles', nil, true) end)
end)
