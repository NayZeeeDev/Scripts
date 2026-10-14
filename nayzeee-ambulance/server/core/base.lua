--[[
    NAYZEEE AMBULANCE - Server core helpers (NZA.Core)

    Small helpers every server/core file uses. Nothing here runs at load time except
    function definitions; the player-lifecycle hook is installed from a thread so the
    bridge (loaded earlier) and every core file are ready.

    NZA.Core.B(path, ...)              pcall-guarded Bridge call: NZA.Core.B('Inv.HasItem', src, 'bandage', 1)
    NZA.Core.Has(path)                 → true when that Bridge function exists
    NZA.Core.Identifier(src)           → character identifier (Bridge.GetIdentifier, license fallback)
    NZA.Core.IsAdmin(src)              → bool (console = true)
    NZA.Core.Name(src)                 → 'First Last'
    NZA.Core.Online(src)               → bool
    NZA.Core.SrcCoords(src)            → vector3 | nil (server-side ped coords)
    NZA.Core.PatientPed(p)             → entity | 0
    NZA.Core.PatientCoords(p)          → vector3 | nil
    NZA.Core.DistanceTo(src, p)        → metres (math.huge when unknown)
    NZA.Core.Rate(bucket, key, n, ms)  → true while under n calls per ms window
    NZA.Core.Notify(src, msg, type, title, duration)   → 'nza:ui:toast' to the client
    NZA.Core.NormalizeItems(items)     → { [name] = count }
    NZA.Core.CheckItems(src, items)    → ok, missingName
    NZA.Core.TakeItems(src, items)     → ok
    NZA.Core.IsLocalSource(src)        → true for server-originated (non-network) events
    NZA.Notify                         alias of NZA.Core.Notify for every server module

    Bus events emitted (server):
      player:loaded (src)              character loaded (Bridge.OnPlayerLoaded, or playerJoining fallback)
      player:unloaded (src)            character logged out (Bridge.OnPlayerUnloaded) or player dropped
      player:job (src, job)            Bridge.OnJobChanged
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Core = NZA.Core or {}
local Core = NZA.Core

-- ════════════════════════════════════════════════════════════════════════
-- BRIDGE ACCESS (always guarded: the bridge is written separately and may be
-- partially available on a broken install — core must never crash because of it)
-- ════════════════════════════════════════════════════════════════════════

local warned = {}

local function resolve(path)
    local node = Bridge
    if type(node) ~= 'table' then return nil end
    for part in path:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    if type(node) == 'function' then return node end
    -- callable tables (e.g. exported function references) count as functions
    if type(node) == 'table' then
        local mt = getmetatable(node)
        if mt and mt.__call then return node end
    end
    return nil
end

function Core.Has(path)
    return resolve(path) ~= nil
end

function Core.B(path, ...)
    local fn = resolve(path)
    if not fn then
        if not warned[path] then
            warned[path] = true
            NZA.Debug('bridge function missing:', path)
        end
        return nil
    end
    local res = table.pack(pcall(fn, ...))
    if not res[1] then
        NZA.Warn(('bridge call Bridge.%s failed: %s'):format(path, tostring(res[2])))
        return nil
    end
    return table.unpack(res, 2, res.n)
end

-- ════════════════════════════════════════════════════════════════════════
-- PLAYERS
-- ════════════════════════════════════════════════════════════════════════

function Core.Online(src)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    return GetPlayerName(src) ~= nil
end

function Core.Identifier(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    if Core.Has('GetIdentifier') then
        local id = Core.B('GetIdentifier', src)
        if id ~= nil and id ~= '' then return tostring(id) end
        return nil
    end
    -- No bridge: fall back to the Rockstar license so persistence still works.
    local lic = GetPlayerIdentifierByType(tostring(src), 'license')
    return lic
end

function Core.IsAdmin(src)
    src = tonumber(src)
    if src == 0 then return true end           -- server console
    if not src then return false end
    if Core.Has('IsAdmin') then
        if Core.B('IsAdmin', src) then return true end
    end
    local ace = (Config.Admin and Config.Admin.ace) or 'nza.admin'
    return IsPlayerAceAllowed(tostring(src), ace) and true or false
end

function Core.Name(src)
    src = tonumber(src)
    if not src then return '?' end
    local name = Core.B('GetName', src)
    if type(name) == 'string' and name ~= '' then return name end
    return GetPlayerName(src) or ('#' .. src)
end

-- Events triggered with TriggerEvent on the server have no player source.
function Core.IsLocalSource(src)
    if src == nil or src == '' then return true end
    local n = tonumber(src)
    return n == nil or n <= 0
end

-- ════════════════════════════════════════════════════════════════════════
-- POSITIONS (always server-side — never trust client coordinates)
-- ════════════════════════════════════════════════════════════════════════

function Core.SrcCoords(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function Core.PatientPed(p)
    if not p then return 0 end
    if p.kind == 'player' then
        if not p.src then return 0 end
        return GetPlayerPed(p.src) or 0
    end
    if p.net then
        local ent = NetworkGetEntityFromNetworkId(p.net)
        if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    end
    return 0
end

function Core.PatientCoords(p)
    local ped = Core.PatientPed(p)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function Core.DistanceTo(src, p)
    local a = Core.SrcCoords(src)
    local b = Core.PatientCoords(p)
    if not a or not b then return math.huge end
    return #(a - b)
end

-- ════════════════════════════════════════════════════════════════════════
-- RATE LIMIT (sliding window counters)
-- ════════════════════════════════════════════════════════════════════════

local buckets = {}

function Core.Rate(bucket, key, limit, windowMs)
    local b = buckets[bucket]
    if not b then
        b = {}
        buckets[bucket] = b
    end
    local now = GetGameTimer()
    local e = b[key]
    if not e or now - e.start >= windowMs then
        b[key] = { start = now, n = 1 }
        return true
    end
    e.n = e.n + 1
    return e.n <= limit
end

function Core.ClearRate(key)
    for _, b in pairs(buckets) do b[key] = nil end
end

-- ════════════════════════════════════════════════════════════════════════
-- NOTIFY (NUI toast through core-client; Bridge.Notify is the client-side fallback)
-- ════════════════════════════════════════════════════════════════════════

function Core.Notify(src, message, kind, title, duration)
    src = tonumber(src)
    if not src or src <= 0 then
        if message then print(('[nayzeee-ambulance] %s'):format(tostring(message))) end
        return
    end
    local data
    if type(message) == 'table' then
        data = message
    else
        data = { title = title or NZA.L('core.title'), message = message, type = kind or 'info', duration = duration or 5000 }
    end
    TriggerClientEvent('nza:ui:toast', src, data)
end

NZA.Notify = NZA.Notify or function(...) return Core.Notify(...) end

-- ════════════════════════════════════════════════════════════════════════
-- ITEMS — items may be { [name] = count } or { { name, count }, ... } or { 'name', ... }
-- ════════════════════════════════════════════════════════════════════════

function Core.NormalizeItems(items)
    local out = {}
    if type(items) ~= 'table' then return out end
    for k, v in pairs(items) do
        if type(k) == 'string' then
            local n = tonumber(v) or (v == true and 1) or 0
            if n > 0 then out[k] = (out[k] or 0) + math.floor(n) end
        elseif type(v) == 'string' then
            out[v] = (out[v] or 0) + 1
        elseif type(v) == 'table' then
            local name = v.name or v[1]
            local n = tonumber(v.count or v[2]) or 1
            if type(name) == 'string' and n > 0 then out[name] = (out[name] or 0) + math.floor(n) end
        end
    end
    return out
end

function Core.CheckItems(src, items)
    local list = Core.NormalizeItems(items)
    if next(list) == nil then return true end
    if not Core.Has('Inv.HasItem') then
        if not warned['inv'] then
            warned['inv'] = true
            NZA.Warn('Bridge.Inv.HasItem is missing - item checks fail until the inventory bridge loads')
        end
        return false, next(list)
    end
    for name, count in pairs(list) do
        if not Core.B('Inv.HasItem', src, name, count) then return false, name end
    end
    return true
end

function Core.TakeItems(src, items)
    local list = Core.NormalizeItems(items)
    local ok = true
    for name, count in pairs(list) do
        if not Core.B('Inv.RemoveItem', src, name, count) then ok = false end
    end
    return ok
end

-- ════════════════════════════════════════════════════════════════════════
-- PLAYER LIFECYCLE → BUS
-- One registration with the bridge; every core file listens on the bus instead
-- (a bridge that only keeps one handler per hook would otherwise drop some).
-- ════════════════════════════════════════════════════════════════════════

local hooked = false

function Core.HookPlayers()
    if hooked then return end
    hooked = true

    if Core.Has('OnPlayerLoaded') then
        Core.B('OnPlayerLoaded', function(src)
            src = tonumber(src)
            if src then NZA.Bus.Emit('player:loaded', src) end
        end)
    else
        NZA.Warn('Bridge.OnPlayerLoaded missing - falling back to playerJoining')
        AddEventHandler('playerJoining', function()
            local src = tonumber(source)
            SetTimeout(3000, function()
                if src and Core.Online(src) then NZA.Bus.Emit('player:loaded', src) end
            end)
        end)
    end

    if Core.Has('OnPlayerUnloaded') then
        Core.B('OnPlayerUnloaded', function(src)
            src = tonumber(src)
            if src then NZA.Bus.Emit('player:unloaded', src) end
        end)
    end

    if Core.Has('OnJobChanged') then
        Core.B('OnJobChanged', function(src, job)
            src = tonumber(src)
            if src then NZA.Bus.Emit('player:job', src, job) end
        end)
    end
end

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    NZA.Bus.Emit('player:unloaded', src, 'dropped')
    Core.ClearRate(src)
end)

CreateThread(function()
    Wait(0)
    Core.HookPlayers()
end)
