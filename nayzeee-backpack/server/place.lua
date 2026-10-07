-----------------------------------------------------------------
-- Placeable bags (server)
--
-- Server owns the list. Clients only render what it tells them.
-----------------------------------------------------------------

if not Config.Placement or not Config.Placement.enabled then return end

local ox = exports.ox_inventory
local cfg = Config.Placement

local placed = {}   -- [id] = { id, bag, metadata, coords, heading, owner, variant, at }
local nextId = 1

local function countFor(identifier)
    local n = 0
    for _, p in pairs(placed) do
        if p.owner == identifier then n = n + 1 end
    end
    return n
end

local function ownerOf(src)
    -- character identifier so ownership survives a reconnect
    return Framework.getIdentifier(src)
end

-----------------------------------------------------------------
-- persistence
-----------------------------------------------------------------

local hasDb = cfg.persist and GetResourceState('oxmysql') == 'started'

local function saveOne(p)
    if not hasDb then return end
    MySQL.insert('INSERT INTO nayzeee_placed_bags (id, bag, metadata, x, y, z, heading, owner, variant, access) '..
                 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '..
                 'ON DUPLICATE KEY UPDATE x=VALUES(x), y=VALUES(y), z=VALUES(z), access=VALUES(access)',
        { p.id, p.bag, json.encode(p.metadata or {}), p.coords.x, p.coords.y, p.coords.z,
          p.heading or 0.0, p.owner, p.variant or 0, p.access or 'private' })
end

local function deleteOne(id)
    if not hasDb then return end
    MySQL.query('DELETE FROM nayzeee_placed_bags WHERE id = ?', { id })
end

CreateThread(function()
    if not hasDb then
        if cfg.persist then
            print('^3[nayzeee-backpack] persist is on but oxmysql is not running; placed bags will not survive a restart^0')
        end
        return
    end

    Wait(1500)
    local rows = MySQL.query.await('SELECT * FROM nayzeee_placed_bags') or {}

    for _, row in ipairs(rows) do
        local id = tonumber(row.id)
        placed[id] = {
            id = id,
            bag = row.bag,
            metadata = json.decode(row.metadata or '{}'),
            coords = vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0),
            heading = row.heading + 0.0,
            owner = row.owner,
            variant = row.variant,
            access = row.access or 'private',
            at = os.time(),
        }
        if id >= nextId then nextId = id + 1 end
    end

    if #rows > 0 then
        print(('[nayzeee-backpack] restored %d placed bag(s)'):format(#rows))
    end
end)

--- Send a placed bag to everyone, tagging each client with whether
--- it belongs to them so the target options can differ per player.
function BroadcastPlaced(entry)
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local copy = {
            id = entry.id, bag = entry.bag, coords = entry.coords,
            heading = entry.heading, variant = entry.variant,
            access = entry.access,
            mine = entry.owner == ownerOf(src),
        }
        TriggerClientEvent('nayzeee-backpack:spawnPlaced', src, copy)
    end
end

-----------------------------------------------------------------
-- place
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:place', function(bagKey, coords, heading, access)
    local src = source
    access = (access == 'public') and 'public' or 'private'

    if not bagKey or not Config.Backpacks[bagKey] then return end
    if type(coords) ~= 'vector3' and type(coords) ~= 'table' then return end
    if not tonumber(coords.x) or not tonumber(coords.y) or not tonumber(coords.z) then return end

    local ped = GetPlayerPed(src)
    local pc = GetEntityCoords(ped)
    local target = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    -- never trust the client's coords
    -- the origin of these props sits a little off the mesh, hence the margin
    if #(pc - target) > (cfg.maxDistance or 4.0) + 2.0 then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.place_far, 'error')
    end

    local identifier = ownerOf(src)
    if (cfg.maxPerPlayer or 0) > 0 and countFor(identifier) >= cfg.maxPerPlayer then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.place_max, 'error')
    end

    local item = FindBagItem(src)
    if not item or item.name ~= bagKey then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.no_bag, 'error')
    end

    local metadata = item.metadata or {}
    if not ox:RemoveItem(src, bagKey, 1, metadata, item.slot) then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.place_bad, 'error')
    end

    local id = nextId
    nextId = nextId + 1

    metadata.stowed = nil -- picking it back up puts it on your back

    local entry = {
        id = id,
        bag = bagKey,
        metadata = metadata,
        coords = target,
        heading = tonumber(heading) or 0.0,
        owner = identifier,
        variant = metadata.variant,
        access = access,
        at = os.time(),
    }

    placed[id] = entry
    saveOne(entry)

    RefreshBagState(src)
    BroadcastPlaced(entry)
    TriggerEvent('nayzeee-backpack:server:placed', src, bagKey, target, id)

    if Logs then Logs.place(src, bagKey, target, access, id) end
    TriggerClientEvent('nayzeee-backpack:notify', src, Strings.placed, 'success')
end)

-----------------------------------------------------------------
-- open
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:openPlaced', function(id)
    local src = source
    local entry = placed[tonumber(id)]
    if not entry then return end

    local dist = #(GetEntityCoords(GetPlayerPed(src)) - entry.coords)
    if dist > 3.0 then return end

    if entry.access == 'private' and entry.owner ~= ownerOf(src) then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.is_private, 'error')
    end

    local bagid = entry.metadata and entry.metadata.bagid
    if not bagid then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.cannot_open, 'error')
    end

    TriggerClientEvent('nayzeee-backpack:open', src, PrepareStash(entry.bag, bagid))
end)

-----------------------------------------------------------------
-- pick up
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:pickup', function(id)
    local src = source
    id = tonumber(id)
    local entry = placed[id]
    if not entry then return end

    local dist = #(GetEntityCoords(GetPlayerPed(src)) - entry.coords)
    if dist > 3.0 then return end

    local mine = entry.owner == ownerOf(src)

    if entry.access == 'private' and not mine then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.is_private, 'error')
    end

    if cfg.ownerOnly and not mine then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.not_yours, 'error')
    end

    if not cfg.pickupAnyone and not mine then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.not_yours, 'error')
    end

    -- one-bag rule still applies
    if Config.OneBagOnly and FindBagItem(src) then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.one_bag_only, 'error')
    end

    if not ox:AddItem(src, entry.bag, 1, entry.metadata) then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.place_bad, 'error')
    end

    placed[id] = nil
    deleteOne(id)

    if Logs then Logs.pickup(src, entry.bag, entry.coords, mine, id) end

    TriggerClientEvent('nayzeee-backpack:removePlaced', -1, id)
    TriggerClientEvent('nayzeee-backpack:notify', src, Strings.picked_up, 'success')
end)

-----------------------------------------------------------------
-- sync
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:requestPlaced', function()
    local src = source
    local identifier = ownerOf(src)
    local list = {}

    for _, entry in pairs(placed) do
        list[#list + 1] = {
            id = entry.id, bag = entry.bag, coords = entry.coords,
            heading = entry.heading, variant = entry.variant,
            access = entry.access,
            mine = entry.owner == identifier,
        }
    end

    TriggerClientEvent('nayzeee-backpack:syncPlaced', src, list)
end)

-----------------------------------------------------------------
-- private / public toggle
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:toggleAccess', function(id)
    local src = source
    id = tonumber(id)
    local entry = placed[id]
    if not entry then return end

    if not cfg.allowRetoggle then return end
    if entry.owner ~= ownerOf(src) then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.not_yours, 'error')
    end

    local dist = #(GetEntityCoords(GetPlayerPed(src)) - entry.coords)
    if dist > 3.0 then return end

    entry.access = entry.access == 'private' and 'public' or 'private'
    saveOne(entry)

    if Logs then Logs.access(src, id, entry.access) end

    TriggerClientEvent('nayzeee-backpack:removePlaced', -1, id)
    BroadcastPlaced(entry)
    TriggerClientEvent('nayzeee-backpack:notify', src,
        entry.access == 'private' and Strings.now_private or Strings.now_public, 'success')
end)

if (cfg.despawn or 0) > 0 then
    CreateThread(function()
        while true do
            Wait(60000)
            local now = os.time()
            for id, entry in pairs(placed) do
                if now - entry.at > cfg.despawn then
                    placed[id] = nil
                    deleteOne(id)
                    TriggerClientEvent('nayzeee-backpack:removePlaced', -1, id)
                end
            end
        end
    end)
end
