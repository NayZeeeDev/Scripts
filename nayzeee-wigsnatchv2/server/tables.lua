-- Wig tables players place in the world, saved between restarts. Same system as the
-- nayzeee-sneakers crafting tables.
--
-- The server only keeps positions; each client spawns the table model itself (Dragons Lab's
-- model if that client has her pack, otherwise the fallback). The jobs done at a table are
-- in server/workshop.lua.

Tables = {}

local T = Config.Tables
local KVP = 'nzwig:tables'
local tables = {}      -- [id] = { id, item, coords, heading, owner, fixed, user }
local nextId = 1

local function isAdmin(src)
    return IsPlayerAceAllowed(tostring(src), 'command')
end

local function save()
    local out = {}
    for _, t in pairs(tables) do
        if not t.fixed then
            out[#out + 1] = { id = t.id, item = t.item, x = t.coords.x, y = t.coords.y, z = t.coords.z, h = t.heading, owner = t.owner }
        end
    end
    SetResourceKvp(KVP, json.encode(out))
end

local function load()
    local ok, list = pcall(json.decode, GetResourceKvpString(KVP) or '[]')
    for _, t in ipairs(ok and type(list) == 'table' and list or {}) do
        if T.Items[t.item] then
            tables[t.id] = { id = t.id, item = t.item, coords = vector3(t.x, t.y, t.z), heading = t.h, owner = t.owner }
            nextId = math.max(nextId, t.id + 1)
        end
    end
    for i, f in ipairs(T.Fixed) do
        local id = 'fixed' .. i
        tables[id] = { id = id, item = f.item, coords = f.coords.xyz, heading = f.coords.w, fixed = true }
    end
end

-- what a client gets to see (never the owner's identifier)
local function view(t, ownerSrc)
    return { id = t.id, item = t.item, coords = t.coords, heading = t.heading, fixed = t.fixed, ownerSrc = ownerSrc }
end

function Tables.Get(id) return tables[id] end

-- close enough to work at the table
function Tables.Near(src, t, extra)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - t.coords) <= T.InteractDistance + (extra or 1.5)
end

-- someone is working here right now
function Tables.InUseBy(t)
    if t.user and GetPlayerPed(t.user) ~= 0 then return t.user end
    t.user = nil
end

function Tables.CanUse(src, t)
    if t.fixed or T.AnyoneCanUse then return true end
    return t.owner == Bridge.GetIdentifier(src) or isAdmin(src)
end

-- the player is standing at a table they may use (for vault actions that need one)
function Tables.AtAny(src)
    for _, t in pairs(tables) do
        if Tables.Near(src, t) and Tables.CanUse(src, t) then return t end
    end
end

if not T.Enabled then return end
load()

lib.callback.register('nz-wig:tables', function(src)
    local me = Bridge.GetIdentifier(src)
    local out = {}
    for _, t in pairs(tables) do
        out[#out + 1] = view(t, (me and t.owner == me) and src or nil)
    end
    return out
end)

lib.callback.register('nz-wig:placeTable', function(src, item, coords, heading)
    if type(item) ~= 'string' or not T.Items[item] then return false end
    if type(coords) ~= 'vector3' or type(heading) ~= 'number' then return false end
    if not (SafeNumber(coords.x) and SafeNumber(coords.y) and SafeNumber(coords.z) and SafeNumber(heading)) then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - coords) > 6.0 then return false end
    if Inv.Count(src, item) < 1 then return false end

    local me = Bridge.GetIdentifier(src)
    if not me then return false end
    local mine = 0
    for _, t in pairs(tables) do
        if t.owner == me then mine = mine + 1 end
        if #(t.coords - coords) < 1.2 then
            Notify(src, L('table_too_close'), 'error')
            return false
        end
    end
    if mine >= T.MaxPerPlayer then
        Notify(src, L('table_limit', T.MaxPerPlayer), 'error')
        return false
    end
    if not Inv.Remove(src, item, 1) then return false end

    local t = { id = nextId, item = item, coords = coords, heading = heading % 360.0, owner = me }
    nextId = nextId + 1
    tables[t.id] = t
    save()
    TriggerClientEvent('nz-wig:c:tableAdded', -1, view(t, src))
    Log('workshop', 'Wig table placed', ('**%s** placed a %s at %.1f, %.1f, %.1f'):format(
        GetPlayerName(src) or src, T.Items[item].label, coords.x, coords.y, coords.z))
    return true
end)

lib.callback.register('nz-wig:pickUpTable', function(src, id)
    local t = tables[id]
    if not t or t.fixed or not Tables.Near(src, t) then return false end
    if t.owner ~= Bridge.GetIdentifier(src) and not isAdmin(src) then
        Notify(src, L('table_not_yours'), 'error')
        return false
    end
    if Tables.InUseBy(t) then
        Notify(src, L('table_busy'), 'error')
        return false
    end
    if not Inv.CanCarry(src, t.item, 1) or not Inv.Add(src, t.item, 1) then
        Notify(src, L('pockets_full'), 'error')
        return false
    end
    tables[id] = nil
    save()
    TriggerClientEvent('nz-wig:c:tableRemoved', -1, id)
    return true
end)

CreateThread(function()
    for name in pairs(T.Items) do
        Bridge.RegisterUsable(name, function(src)
            TriggerClientEvent('nz-wig:c:placeTable', src, name)
        end)
    end
end)

OnPlayerDrop(function(src)
    for _, t in pairs(tables) do
        if t.user == src then t.user = nil end
    end
end)

CreateThread(function()
    Wait(2500)
    print(('^5[%s]^7 wig tables: Dragons Lab Wig Crafting Table pack by SasDragon - buy it at %s'):format(RESOURCE, T.Store))
end)
