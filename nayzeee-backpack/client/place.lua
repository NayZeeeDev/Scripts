-----------------------------------------------------------------
-- Placeable bags
--
-- Ghost preview you can rotate and set down, then a real prop that
-- stays put and stays lootable.
-----------------------------------------------------------------

if not Config.Placement or not Config.Placement.enabled then return end

local cfg = Config.Placement
local placing = false
local ghost   = nil
local ghostHeading = 0.0

local placed = {}      -- [placedId] = entity
local placedData = {}  -- [placedId] = the entry, for the proximity fallback
local placedZones = {} -- [placedId] = ox_target zone id

-----------------------------------------------------------------

local function loadModel(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then
        print(('^1[nayzeee-backpack] model "%s" is not registered — check its .ytyp is declared with data_file DLC_ITYP_REQUEST^0'):format(model))
        return nil
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() > timeout then return nil end
    end
    return hash
end

--- Where the player is aiming, clamped to the ground.
local function aimPoint()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local dist = cfg.maxDistance or 3.0

    local target = vector3(
        coords.x + forward.x * dist,
        coords.y + forward.y * dist,
        coords.z
    )

    local ok, ground = GetGroundZFor_3dCoord(target.x, target.y, coords.z + 1.0, false)
    return vector3(target.x, target.y, ok and ground or coords.z - 0.9)
end

local function clearGhost()
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
    ghost = nil
end

local function stopPlacing()
    placing = false
    clearGhost()
    lib.hideTextUI()
end

--- Enter placement mode for the bag the player is wearing.
--- `access` is 'private' or 'public'.
function StartPlacing(bagKey, access)
    if placing then return end
    access = access or (cfg.defaultAccess or 'private')

    local bag = Config.Backpacks[bagKey]
    if not bag then return end

    if cfg.blockInVehicle and IsPedInAnyVehicle(PlayerPedId(), false) then
        return Config.Notify(Strings.place_bad, 'error')
    end

    local hash = loadModel(bag.model)
    if not hash then return end

    placing = true
    ghostHeading = GetEntityHeading(PlayerPedId())

    local p = aimPoint()
    ghost = CreateObject(hash, p.x, p.y, p.z, false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    SetEntityInvincible(ghost, true)
    FreezeEntityPosition(ghost, true)
    SetModelAsNoLongerNeeded(hash)

    lib.showTextUI(('%s\n%s'):format(
        Config.Prompts.placeConfirm,
        access == 'public' and Config.Prompts.accessPublic or Config.Prompts.accessPrivate))

    CreateThread(function()
        while placing do
            local point = aimPoint()

            if ghost and DoesEntityExist(ghost) then
                SetEntityCoordsNoOffset(ghost, point.x, point.y, point.z, false, false, false)
                SetEntityHeading(ghost, ghostHeading)
            end

            -- scroll to rotate
            if IsControlJustPressed(0, 241) then       -- wheel up
                ghostHeading = (ghostHeading + (cfg.rotateStep or 15.0)) % 360.0
            elseif IsControlJustPressed(0, 242) then   -- wheel down
                ghostHeading = (ghostHeading - (cfg.rotateStep or 15.0)) % 360.0
            end

            -- confirm
            if IsControlJustPressed(0, 38) then        -- E
                local coords = GetEntityCoords(ghost)
                local heading = ghostHeading
                stopPlacing()
                TriggerServerEvent('nayzeee-backpack:place', bagKey, coords, heading, access)
                break
            end

            -- cancel
            if IsControlJustPressed(0, 73) then        -- X
                stopPlacing()
                break
            end

            Wait(0)
        end
    end)
end

-----------------------------------------------------------------
-- placed props
-----------------------------------------------------------------

local function removePlaced(id)
    local entity = placed[id]
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    placed[id] = nil
    placedData[id] = nil

    if placedZones[id] then
        exports.ox_target:removeZone(placedZones[id])
        placedZones[id] = nil
    end
end

local function spawnPlaced(data)
    removePlaced(data.id)

    local bag = Config.Backpacks[data.bag]
    if not bag then return end

    local hash = loadModel(bag.model)
    if not hash then return end

    local entity = CreateObject(hash, data.coords.x, data.coords.y, data.coords.z, false, false, false)
    SetEntityHeading(entity, data.heading or 0.0)
    FreezeEntityPosition(entity, true)
    SetModelAsNoLongerNeeded(hash)

    if data.variant then SetObjectTextureVariation(entity, data.variant) end

    placed[data.id] = entity
    placedData[data.id] = data
    Entity(entity).state:set('nayzeee_placed',
        { id = data.id, bag = data.bag, access = data.access }, false)

    if Config.Prompts.useTarget and GetResourceState('ox_target') == 'started' then
        -- A sphere zone, not addLocalEntity. These models are converted from
        -- clothing, which strips their physics bounds, so ox_target's raycast
        -- passes straight through the prop and no options ever appear.
        placedZones[data.id] = exports.ox_target:addSphereZone({
            coords = vec3(data.coords.x, data.coords.y, data.coords.z + 0.25),
            radius = 0.75,
            debug  = Config.Debug,
            options = {
                {
                    name = 'nayzeee_placed_open_' .. data.id,
                    label = Config.Prompts.openPlaced,
                    icon = 'fa-solid fa-box-open',
                    distance = 2.0,
                    onSelect = function()
                        TriggerServerEvent('nayzeee-backpack:openPlaced', data.id)
                    end,
                },
                {
                    name = 'nayzeee_placed_pickup_' .. data.id,
                    label = Config.Prompts.pickup,
                    icon = 'fa-solid fa-hand',
                    distance = 2.0,
                    canInteract = function()
                        if not cfg.pickupAnyone then return data.mine == true end
                        if data.access == 'private' then return data.mine == true end
                        return true
                    end,
                    onSelect = function()
                        TriggerServerEvent('nayzeee-backpack:pickup', data.id)
                    end,
                },
                {
                    name = 'nayzeee_placed_access_' .. data.id,
                    label = data.access == 'private'
                        and Config.Prompts.makePublic
                        or Config.Prompts.makePrivate,
                    icon = data.access == 'private' and 'fa-solid fa-lock-open' or 'fa-solid fa-lock',
                    distance = 2.0,
                    canInteract = function()
                        if not cfg.allowRetoggle then return false end
                        return data.mine == true
                    end,
                    onSelect = function()
                        TriggerServerEvent('nayzeee-backpack:toggleAccess', data.id)
                    end,
                },
            }
        })
    end
end

RegisterNetEvent('nayzeee-backpack:spawnPlaced', function(data)
    spawnPlaced(data)
end)

RegisterNetEvent('nayzeee-backpack:syncPlaced', function(list)
    for id in pairs(placed) do removePlaced(id) end
    for _, data in pairs(list) do spawnPlaced(data) end
end)

RegisterNetEvent('nayzeee-backpack:removePlaced', function(id)
    removePlaced(id)
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then
        TriggerServerEvent('nayzeee-backpack:requestPlaced')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopPlacing()
    for id in pairs(placed) do removePlaced(id) end
end)

-----------------------------------------------------------------
-- Proximity fallback
--
-- Without ox_target a placed bag would be unreachable, so this gives
-- every placed bag a prompt and a menu regardless.
-----------------------------------------------------------------

local usingTarget = Config.Prompts.useTarget and GetResourceState('ox_target') == 'started'

--- Nearest placed bag within reach, or nil.
local function nearestPlaced()
    local coords = GetEntityCoords(PlayerPedId())
    local bestId, bestDist = nil, 2.0

    for id, entity in pairs(placed) do
        if DoesEntityExist(entity) then
            local d = #(GetEntityCoords(entity) - coords)
            if d < bestDist then
                bestId, bestDist = id, d
            end
        end
    end

    return bestId
end

--- Menu for a placed bag, honouring who owns it.
function OpenPlacedMenu(id)
    local data = placedData[id]
    if not data then return end

    local bag = Config.Backpacks[data.bag]
    local canTake = data.access ~= 'private' or data.mine
    local options = {}

    options[#options + 1] = {
        title = Config.Prompts.openPlaced,
        description = data.access == 'private' and not data.mine
            and 'Locked' or 'Look inside',
        icon = 'box-open',
        disabled = data.access == 'private' and not data.mine,
        onSelect = function()
            TriggerServerEvent('nayzeee-backpack:openPlaced', id)
        end,
    }

    options[#options + 1] = {
        title = Config.Prompts.pickup,
        description = canTake and 'Put it back on' or 'Not yours',
        icon = 'hand',
        disabled = not canTake,
        onSelect = function()
            TriggerServerEvent('nayzeee-backpack:pickup', id)
        end,
    }

    if data.mine and cfg.allowRetoggle then
        options[#options + 1] = {
            title = data.access == 'private'
                and Config.Prompts.makePublic or Config.Prompts.makePrivate,
            description = data.access == 'private'
                and 'Let anyone use it' or 'Lock it to you',
            icon = data.access == 'private' and 'lock-open' or 'lock',
            onSelect = function()
                TriggerServerEvent('nayzeee-backpack:toggleAccess', id)
            end,
        }
    end

    lib.registerContext({
        id = 'nayzeee_placed_menu',
        title = bag and bag.label or Config.Prompts.menuTitle,
        options = options,
    })

    lib.showContext('nayzeee_placed_menu')
end

RegisterCommand('bagnearby', function()
    local id = nearestPlaced()
    if not id then
        return Config.Notify('No bag close enough.', 'error')
    end
    OpenPlacedMenu(id)
end, false)

RegisterKeyMapping('bagnearby', 'Use a placed backpack', 'keyboard', '')

-- floating prompt when ox_target isn't handling it
if not usingTarget then
    -- Two-tier loop: a cheap 800ms scan that costs nothing when no bags are
    -- placed nearby, dropping into a per-frame loop only while one is in reach.
    CreateThread(function()
        while true do
            local sleep = 800

            if next(placed) ~= nil and not placing then
                local id = nearestPlaced()

                if id then
                    sleep = 0
                    lib.showTextUI('[E] Backpack')

                    -- stay tight only while the player is still standing there
                    while id and not placing do
                        if IsControlJustPressed(0, 38) then -- E
                            lib.hideTextUI()
                            OpenPlacedMenu(id)
                            Wait(400)
                            break
                        end
                        Wait(0)
                        id = nearestPlaced()
                    end

                    lib.hideTextUI()
                    sleep = 400
                end
            end

            Wait(sleep)
        end
    end)
end
