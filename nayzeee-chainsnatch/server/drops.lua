-----------------------------------------------------------------
-- Chains in the world: set down, thrown, or snapped off in a
-- snatch. Every client spawns its own local prop for each one in
-- range (client/drops.lua); the server only keeps the list.
-----------------------------------------------------------------

Drops = { list = {}, nextId = 1 }

local RES = GetCurrentResourceName()
local FILE = 'data/drops.json'
local cfg = Config.Drops
local T = Config.Text
local dirty = false

local function v3(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

local function public(d)
    return { id = d.id, chain = d.chain, variant = d.variant, coords = d.coords, rot = d.rot, owner = d.ownerSrc, thrown = d.thrown, label = d.meta.label }
end

local function save()
    if not cfg.Persist then return end
    dirty = true
end

CreateThread(function()
    while true do
        Wait(5000)
        if dirty then
            dirty = false
            local out = {}
            for _, d in pairs(Drops.list) do out[#out + 1] = d end
            SaveResourceFile(RES, FILE, json.encode(out), -1)
        end
    end
end)

--- Put a chain on the ground. d = { meta, coords = {x,y,z}, rot = {x,y,z}, owner = ident, ownerSrc, thrown }
function Drops.add(d)
    local key, letter = Chains.fromMeta(d.meta)
    if not key then return nil end
    local id = Drops.nextId
    Drops.nextId = id + 1
    d.id, d.chain, d.variant = id, key, letter
    d.meta = Chains.meta(key, letter, d.meta)
    d.coords = { x = d.coords.x + 0.0, y = d.coords.y + 0.0, z = d.coords.z + 0.0 }
    d.rot = d.rot and { x = (d.rot.x or 0) + 0.0, y = (d.rot.y or 0) + 0.0, z = (d.rot.z or 0) + 0.0 } or { x = 0.0, y = 0.0, z = 0.0 }
    d.t = os.time()
    Drops.list[id] = d
    TriggerClientEvent('nzc:c:dropAdd', -1, public(d))
    save()
    return id
end

function Drops.remove(id)
    if not Drops.list[id] then return nil end
    local d = Drops.list[id]
    Drops.list[id] = nil
    TriggerClientEvent('nzc:c:dropRemove', -1, id)
    save()
    return d
end

local function load()
    if not cfg.Persist then return end
    local ok, data = pcall(json.decode, LoadResourceFile(RES, FILE) or '[]')
    if not ok or type(data) ~= 'table' then return end
    for _, d in ipairs(data) do
        if type(d) == 'table' and d.meta and d.coords then
            local key, letter = Chains.fromMeta(d.meta)
            if key then
                local id = Drops.nextId
                Drops.nextId = id + 1
                d.id, d.chain, d.variant, d.ownerSrc = id, key, letter, nil
                Drops.list[id] = d
            end
        end
    end
end

load()

RegisterNetEvent('nzc:s:drops', function()
    local out = {}
    for _, d in pairs(Drops.list) do out[#out + 1] = public(d) end
    TriggerLatentClientEvent('nzc:c:drops', source, 100000, out)
end)

AddEventHandler('nzc:registryChanged', function()
    -- labels may have changed; resend everything
    local out = {}
    for _, d in pairs(Drops.list) do d.meta = Chains.meta(d.chain, d.variant, d.meta); out[#out + 1] = public(d) end
    TriggerLatentClientEvent('nzc:c:drops', -1, 100000, out)
end)

-- expiry
if (cfg.ExpireMinutes or 0) > 0 then
    CreateThread(function()
        while true do
            Wait(60000)
            local cutoff = os.time() - cfg.ExpireMinutes * 60
            for id, d in pairs(Drops.list) do
                if (d.t or 0) < cutoff then Drops.remove(id) end
            end
        end
    end)
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end
Drops.pedCoords = pedCoords

-----------------------------------------------------------------
-- set down (from the neck / hand, or straight from the pockets)
-----------------------------------------------------------------

RegisterNetEvent('nzc:s:place', function(from, slot, coords, rot)
    local src = source
    if not Config.Place.Enabled or type(coords) ~= 'table' and type(coords) ~= 'vector3' then return end
    local pc = pedCoords(src)
    if not pc or #(pc - v3(coords)) > (Config.Place.MaxDistance or 3.5) + 2.0 then
        return Worn.notify(src, T.too_far, 'error')
    end

    local meta
    if from == 'slot' then
        meta = Inv.TakeSlot(src, slot)
    else
        meta = Worn.strip(src)
    end
    if not meta then return Worn.notify(src, T.no_chain, 'error') end

    Drops.add({
        meta = meta, coords = { x = coords.x, y = coords.y, z = coords.z },
        rot = type(rot) == 'table' and rot or nil,
        owner = Bridge.GetIdentifier(src), ownerSrc = src, thrown = false,
    })
    Logs.send('info', 'Chain set down', ('%s put down %s at %.1f, %.1f, %.1f'):format(Logs.who(src), meta.label or '?', coords.x, coords.y, coords.z))
end)

-----------------------------------------------------------------
-- pick up
-----------------------------------------------------------------

local picking = {}

RegisterNetEvent('nzc:s:pickup', function(id, wear)
    local src = source
    if picking[id] then return end
    local d = Drops.list[tonumber(id)]
    if not d then return end
    local pc = pedCoords(src)
    if not pc or #(pc - v3(d.coords)) > (cfg.PickupDistance or 2.0) + 2.0 then
        return Worn.notify(src, T.too_far, 'error')
    end
    if cfg.OwnerOnly and not d.thrown and d.owner and d.owner ~= Bridge.GetIdentifier(src) then
        return Worn.notify(src, 'That isn\'t yours.', 'error')
    end

    picking[id] = true
    local meta = d.meta
    local ok
    if wear and not Worn.get(src) then
        Drops.remove(d.id)
        ok = Worn.set(src, meta)
        if ok then Worn.notify(src, T.wearing:format(meta.label), 'success') end
    else
        if not Inv.CanCarry(src, meta) then
            picking[id] = nil
            return Worn.notify(src, T.no_room, 'error')
        end
        Drops.remove(d.id)
        ok = Inv.Add(src, meta)
        if not ok then Drops.add(d) end -- couldn't add after all: back on the floor
    end
    picking[id] = nil
    if ok then TriggerClientEvent('nzc:c:anim', src, 'pickup') end
end)

exports('DropChain', function(meta, coords) return Drops.add({ meta = meta, coords = coords, thrown = true }) end)
