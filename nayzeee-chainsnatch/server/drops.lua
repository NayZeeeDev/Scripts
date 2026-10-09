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

local orphans = {}     -- saved drops of chains this server doesn't know right now (props missing?): kept as they are

local function flush()
    dirty = false
    local out = {}
    for _, d in pairs(Drops.list) do out[#out + 1] = d end
    for _, d in ipairs(orphans) do out[#out + 1] = d end
    local ok, txt = pcall(json.encode, out)
    if ok then SaveResourceFile(RES, FILE, txt, -1) else print(('^1[%s] could not save %s: %s^0'):format(RES, FILE, tostring(txt))) end
end

-- adds are saved within 5s; removals at once, so a crash can't leave a picked-up chain on the floor too
local function save(now)
    if not cfg.Persist then return end
    if now then flush() else dirty = true end
end

CreateThread(function()
    while true do
        Wait(5000)
        if dirty then flush() end
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
    save(true)
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
            else
                orphans[#orphans + 1] = d
            end
        end
    end
end

load()

RegisterNetEvent('nzc:s:drops', function()
    if Logs.throttle(source, 'drops', 5000) then return end
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
    if not Config.Place.Enabled or Worn.busy(src) then return end
    local c = Logs.vec(coords, 20000)
    local r = rot and Logs.vec(rot, 720) or vector3(0.0, 0.0, 0.0)
    if not c or not r then return end
    local pc = pedCoords(src)
    if not pc or #(pc - c) > (Config.Place.MaxDistance or 3.5) + 2.0 then
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
        meta = meta, coords = { x = c.x, y = c.y, z = c.z }, rot = { x = r.x, y = r.y, z = r.z },
        owner = Bridge.GetIdentifier(src), ownerSrc = src, thrown = false,
    })
    Logs.send('info', 'Chain set down', ('%s put down %s at %.1f, %.1f, %.1f'):format(Logs.who(src), meta.label or '?', c.x, c.y, c.z))
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
    if wear and meta.broken then Worn.notify(src, T.broken, 'error') end
    if wear and not Worn.get(src) and not meta.broken then
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
