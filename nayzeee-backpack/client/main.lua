local props = {}   -- [serverId] = entity
local myBag  = nil -- the bag key currently reported to the server
local myVariant = nil

-----------------------------------------------------------------
-- helpers
-----------------------------------------------------------------

local function debug(...)
    if Config.Debug then print('[nayzeee-backpack]', ...) end
end

local function loadModel(model)
    local hash = joaat(model)

    if not IsModelInCdimage(hash) then
        print(('^1[nayzeee-backpack] model "%s" is not registered.^0'):format(model))
        print('^3  - is the .ydr in a stream/ folder?^0')
        print('^3  - is its .ytyp there too, AND declared with data_file DLC_ITYP_REQUEST?^0')
        print('^3  - does the filename match the model name in Config.Backpacks exactly?^0')
        return nil
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() > timeout then
            print(('^1[nayzeee-backpack] model "%s" failed to load.^0'):format(model))
            return nil
        end
    end

    return hash
end

local function getOffset(bag)
    local d = Config.DefaultOffset
    local o = bag.offset

    if not o then return d.bone, d.pos, d.rot end

    return o.bone or d.bone,
           o.pos  or d.pos,
           o.rot  or d.rot
end

-----------------------------------------------------------------
-- prop handling
-----------------------------------------------------------------

local function removeProp(serverId)
    local entity = props[serverId]
    if not entity then return end

    if DoesEntityExist(entity) then
        DetachEntity(entity, true, true)
        DeleteEntity(entity)
    end

    props[serverId] = nil
    debug('removed prop for', serverId)
end

local function attachProp(serverId, bagKey, variant)
    removeProp(serverId)

    local bag = Config.Backpacks[bagKey]
    if not bag then return end

    local ped = serverId == GetPlayerServerId(PlayerId())
        and PlayerPedId()
        or GetPlayerPed(GetPlayerFromServerId(serverId))

    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    local hash = loadModel(bag.model)
    if not hash then return end

    local coords = GetEntityCoords(ped)
    local entity = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)

    if not entity or entity == 0 then
        print(('^1[nayzeee-backpack] could not create "%s".^0'):format(bag.model))
        SetModelAsNoLongerNeeded(hash)
        return
    end

    SetEntityCollision(entity, false, false)
    SetEntityCompletelyDisableCollision(entity, false, false)

    local bone, pos, rot = getOffset(bag)

    AttachEntityToEntity(
        entity, ped, GetPedBoneIndex(ped, bone),
        pos.x, pos.y, pos.z,
        rot.x, rot.y, rot.z,
        true, true, false, true, 1, true
    )

    -- texture variation, when the model ships with skins baked in
    if variant then
        SetObjectTextureVariation(entity, tonumber(variant) or 0)
    end

    SetModelAsNoLongerNeeded(hash)
    props[serverId] = entity
    debug('attached', bag.model, 'to', serverId)
end

-----------------------------------------------------------------
-- state sync
--
-- The server owns the truth. Every client watches the statebag so
-- other players' bags appear without extra events.
-----------------------------------------------------------------

AddStateBagChangeHandler('nayzeee_backpack', nil, function(bagName, _, value)
    local ply = GetPlayerFromStateBagName(bagName)
    if ply == 0 then return end

    local serverId = GetPlayerServerId(ply)

    -- wait for the ped to exist before touching it
    local tries = 0
    while not DoesEntityExist(GetPlayerPed(ply)) and tries < 50 do
        Wait(100)
        tries = tries + 1
    end

    if value and value.bag and not value.stowed then
        attachProp(serverId, value.bag, value.variant)
    else
        removeProp(serverId)
    end
end)

-----------------------------------------------------------------
-- inventory watch
-----------------------------------------------------------------

local function findBackpack()
    local items = exports.ox_inventory:GetPlayerItems()
    if not items then return nil end

    for _, item in pairs(items) do
        local bag = Config.Backpacks[item.name]
        if bag then
            return item.name, item.metadata and item.metadata.variant or nil
        end
    end

    return nil
end

local function syncBackpack(skipAnim)
    local bagKey, variant = findBackpack()

    if bagKey == myBag and variant == myVariant then return end

    local hadBag = myBag ~= nil
    myBag, myVariant = bagKey, variant

    if not skipAnim and Config.Animations and Config.Animations.enabled then
        if bagKey and not hadBag then
            Anim.playAsync('equip')
        elseif not bagKey and hadBag then
            Anim.playAsync('unequip')
        end
    end

    TriggerServerEvent('nayzeee-backpack:sync', bagKey, variant)
    debug('sync ->', bagKey or 'none', variant or '-')
end

AddEventHandler('ox_inventory:updateInventory', function()
    syncBackpack()
end)

RegisterNetEvent('ox_inventory:closedInventory', syncBackpack)

-----------------------------------------------------------------
-- lifecycle
-----------------------------------------------------------------

AddEventHandler('playerSpawned', function()
    myBag, myVariant = nil, nil
    Wait(1500)
    syncBackpack(true) -- no animation on spawn
end)

-- vehicle visibility
if not Config.ShowInVehicle then
    -- Only polls while the player actually has a bag on. With no bag this
    -- sits at a 2s idle instead of ticking twice a second forever.
    CreateThread(function()
        local hidden = false
        local me = nil

        while true do
            me = me or GetPlayerServerId(PlayerId())
            local entity = props[me]

            if entity and DoesEntityExist(entity) then
                local inVeh = IsPedInAnyVehicle(PlayerPedId(), false)
                if inVeh ~= hidden then
                    hidden = inVeh
                    SetEntityVisible(entity, not inVeh, false)
                end
                Wait(500)
            else
                hidden = false
                Wait(2000)
            end
        end
    end)
end

--- Hide the bag the player is already wearing, so the shop preview
--- doesn't stack a second one on their back.
function SetWornPropVisible(visible)
    local me = GetPlayerServerId(PlayerId())
    local entity = props[me]
    if entity and DoesEntityExist(entity) then
        SetEntityVisible(entity, visible, false)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(props) do removeProp(id) end
end)

-- clean up when a player leaves scope
AddEventHandler('playerDropped', function() end)

RegisterNetEvent('nayzeee-backpack:clear', function(serverId)
    removeProp(serverId)
end)
