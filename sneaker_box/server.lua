local STATE_KEY = 'nzShoeboxOpen'

-- [entity] = { owner = src, lastToggle = ms }
local spawned = {}

local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'nz_shoebox.admin')
end

local function countOwned(src)
    local n = 0
    for _, info in pairs(spawned) do
        if info.owner == src then n = n + 1 end
    end
    return n
end

local function nearPlayer(src, coords, maxDist)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - coords) <= maxDist
end

local function isBoxModel(ent)
    -- Compare unsigned; server and backtick hashes don't always share a sign
    return (GetEntityModel(ent) & 0xFFFFFFFF) == (Config.BaseModel & 0xFFFFFFFF)
end

local function boxFromNetId(netId)
    if type(netId) ~= 'number' then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or not DoesEntityExist(ent) or not isBoxModel(ent) then
        return nil
    end
    return ent
end

local function deleteBox(ent)
    spawned[ent] = nil
    if DoesEntityExist(ent) then DeleteEntity(ent) end
end

-- Spawning --------------------------------------------------------------------

local function spawnBox(coords, heading, owner)
    local ent = CreateObjectNoOffset(Config.BaseModel, coords.x, coords.y, coords.z, true, true, false)

    local timeout = GetGameTimer() + 3000
    while not DoesEntityExist(ent) do
        if GetGameTimer() > timeout then return nil end
        Wait(0)
    end

    SetEntityHeading(ent, heading + 0.0)
    FreezeEntityPosition(ent, true)
    Entity(ent).state:set(STATE_KEY, false, true)
    spawned[ent] = { owner = owner, lastToggle = 0 }
    return ent
end

local function setOpen(ent, open)
    Entity(ent).state:set(STATE_KEY, open == true, true)
end

RegisterNetEvent('nz_shoebox:spawn', function(coords, heading)
    local src = source
    if type(coords) ~= 'vector3' or type(heading) ~= 'number' then return end
    if Config.AdminOnly and not isAdmin(src) then return end
    if not nearPlayer(src, coords, 3.0) then return end
    if countOwned(src) >= Config.MaxPerPlayer and not isAdmin(src) then
        TriggerClientEvent('nz_shoebox:notify', src, 'limit')
        return
    end
    spawnBox(coords, heading, src)
end)

RegisterNetEvent('nz_shoebox:delete', function(netId)
    local src = source
    local ent = boxFromNetId(netId)
    if not ent then return end

    local info = spawned[ent]
    if not isAdmin(src) and (not info or info.owner ~= src) then
        TriggerClientEvent('nz_shoebox:notify', src, 'noBox')
        return
    end
    deleteBox(ent)
end)

-- Open / close ----------------------------------------------------------------

RegisterNetEvent('nz_shoebox:toggle', function(netId)
    local src = source
    local ent = boxFromNetId(netId)
    if not ent then return end
    if not nearPlayer(src, GetEntityCoords(ent), Config.InteractDistance + 1.5) then return end

    -- Ignore spam while the lid is still swinging
    local info = spawned[ent]
    local now = GetGameTimer()
    if info then
        if now - info.lastToggle < math.min(Config.OpenTime, Config.CloseTime) then return end
        info.lastToggle = now
    end

    setOpen(ent, not Entity(ent).state[STATE_KEY])
end)

-- Cleanup ---------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    if not Config.CleanupOnDrop then return end
    local src = source
    for ent, info in pairs(spawned) do
        if info.owner == src then deleteBox(ent) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for ent in pairs(spawned) do deleteBox(ent) end
end)

-- Exports for other resources (shoe stores, stash props, etc.) ----------------
--   local netId = exports.sneaker_box:SpawnBox(vector3(x, y, z), heading)
--   exports.sneaker_box:SetBoxOpen(netId, true)

exports('SpawnBox', function(coords, heading)
    local ent = spawnBox(coords, heading or 0.0, nil)
    return ent and NetworkGetNetworkIdFromEntity(ent)
end)

exports('SetBoxOpen', function(netId, open)
    local ent = boxFromNetId(netId)
    if ent then setOpen(ent, open) end
end)

exports('DeleteBox', function(netId)
    local ent = boxFromNetId(netId)
    if ent then deleteBox(ent) end
end)
