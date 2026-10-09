--[[
    Crafting tables players place in the world. Saved between restarts.

    The server only keeps positions; each client spawns the table model itself
    (Dragons Lab's model if that client has her pack, otherwise the fallback).
]]

Tables = {}

local T = Config.Tables
local KVP = 'tables'
local tables = {}      -- [id] = { id, item, coords, heading, owner, fixed, user }
local nextId = 1

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
    for _, t in ipairs(json.decode(GetResourceKvpString(KVP) or '[]') or {}) do
        if T.items[t.item] then
            tables[t.id] = { id = t.id, item = t.item, coords = vector3(t.x, t.y, t.z), heading = t.h, owner = t.owner }
            nextId = math.max(nextId, t.id + 1)
        end
    end
    for i, f in ipairs(T.fixed) do
        local id = 'fixed' .. i
        tables[id] = { id = id, item = f.item, coords = f.coords.xyz, heading = f.coords.w, fixed = true }
    end
end
load()

--- What a client gets to see (never the owner's identifier)
local function view(t, ownerSrc)
    return { id = t.id, item = t.item, coords = t.coords, heading = t.heading, fixed = t.fixed, ownerSrc = ownerSrc }
end

function Tables.Get(id) return tables[id] end

--- Player is close enough to work at the table
function Tables.Near(src, t, extra)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - t.coords) <= T.interactDistance + (extra or 1.5)
end

--- Someone else is crafting here right now
function Tables.InUseBy(t)
    if t.user and GetPlayerPed(t.user) ~= 0 then return t.user end
    t.user = nil
end

function Tables.CanUse(src, t)
    if t.fixed or T.anyoneCanUse then return true end
    return t.owner == Bridge.GetIdentifier(src) or Bridge.IsAdmin(src)
end

lib.callback.register('nayzeee-sneakers:tables', function(src)
    local me = Bridge.GetIdentifier(src)
    local out = {}
    for _, t in pairs(tables) do
        out[#out + 1] = view(t, (me and t.owner == me) and src or nil)
    end
    return out
end)

lib.callback.register('nayzeee-sneakers:placeTable', function(src, slot, coords, heading)
    local it = Inv.GetSlot(src, slot)
    if not it or not T.items[it.name] then return false end
    if type(coords) ~= 'vector3' or type(heading) ~= 'number' then return false end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - coords) > 6.0 then return false end

    local me = Bridge.GetIdentifier(src)
    if not me then return false end
    local mine = 0
    for _, t in pairs(tables) do
        if t.owner == me then mine = mine + 1 end
        if #(t.coords - coords) < 1.2 then
            Bridge.Notify(src, Config.Text.tableTooClose, 'error')
            return false
        end
    end
    if mine >= T.maxPerPlayer then
        Bridge.Notify(src, Config.Text.tableLimit, 'error')
        return false
    end
    if not Inv.Remove(src, it.name, 1, slot) then return false end

    local t = { id = nextId, item = it.name, coords = coords, heading = heading % 360.0, owner = me }
    nextId = nextId + 1
    tables[t.id] = t
    save()
    TriggerClientEvent('nayzeee-sneakers:client:tableAdded', -1, view(t, src))
    return true
end)

lib.callback.register('nayzeee-sneakers:pickUpTable', function(src, id)
    local t = tables[id]
    if not t or t.fixed or not Tables.Near(src, t) then return false end
    if t.owner ~= Bridge.GetIdentifier(src) and not Bridge.IsAdmin(src) then
        Bridge.Notify(src, Config.Text.notYourTable, 'error')
        return false
    end
    if Tables.InUseBy(t) then
        Bridge.Notify(src, Config.Text.tableBusy, 'error')
        return false
    end
    if not Inv.CanCarry(src, t.item, 1) or not Inv.Add(src, t.item, 1) then
        Bridge.Notify(src, Config.Text.noSpace, 'error')
        return false
    end
    tables[id] = nil
    save()
    TriggerClientEvent('nayzeee-sneakers:client:tableRemoved', -1, id)
    return true
end)

CreateThread(function()
    for name in pairs(T.items) do
        Inv.RegisterUsable(name, function(src, it)
            TriggerClientEvent('nayzeee-sneakers:client:placeTable', src, it.slot, it.name)
        end)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, t in pairs(tables) do
        if t.user == src then t.user = nil end
    end
end)

CreateThread(function()
    Wait(2000)
    print(('^5[nayzeee-sneakers]^7 crafting tables: Dragons Lab Shoe Table Pack - buy it at %s'):format(T.store))
end)
