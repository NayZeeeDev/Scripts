-----------------------------------------------------------------
-- Placeable bags
--
-- The ghost follows where you look (a raycast from the camera), so
-- you can set a bag on the floor, a table, a counter, anywhere in
-- reach. [E] place, [SCROLL] rotate (SHIFT = fine), [BACKSPACE] cancel.
--
-- The placement loop is written for resmon: natives cached as
-- upvalues, an async shape test (read next frame instead of forcing
-- a synchronous one), the ghost only moved when the hit actually
-- changes, and the help text sent to the UI once instead of per frame.
-----------------------------------------------------------------

if not Config.Placement or not Config.Placement.enabled then return end

local cfg = Config.Placement
local placing = false

local placed = {}      -- [placedId] = entity (only bags in render range)
local placedData = {}  -- [placedId] = entry from the server
local placedZones = {} -- [placedId] = ox_target zone id

-----------------------------------------------------------------
-- placement mode
-----------------------------------------------------------------

-- cached natives: every lookup saved here is a lookup not done per frame
local Wait = Wait
local PlayerPedId = PlayerPedId
local DisableControlAction = DisableControlAction
local IsControlJustPressed = IsControlJustPressed
local IsControlPressed = IsControlPressed
local GetFinalRenderedCamCoord = GetFinalRenderedCamCoord
local GetFinalRenderedCamRot = GetFinalRenderedCamRot
local StartShapeTestLosProbe = StartShapeTestLosProbe
local GetShapeTestResult = GetShapeTestResult
local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
local SetEntityHeading = SetEntityHeading
local SetEntityAlpha = SetEntityAlpha
local GetEntityCoords = GetEntityCoords
local IsPedInAnyVehicle = IsPedInAnyVehicle
local IsEntityDead = IsEntityDead
local msin, mcos, mrad, mabs = math.sin, math.cos, math.rad, math.abs

local BLOCK = { 14, 15, 16, 17, 24, 25, 37, 44, 45, 140, 141, 142, 257, 263, 264 }
local NBLOCK = #BLOCK

--- Origin for the ghost so the bottom-centre of the MESH sits on the hit point.
--- These props are converted from clothing, so their origin is nowhere near
--- the mesh; placing the origin would float or bury the bag.
local function originFor(hx, hy, hz, heading, cx, cy, minZ)
    local r = mrad(heading)
    local c, s = mcos(r), msin(r)
    return hx - (cx * c - cy * s), hy - (cx * s + cy * c), hz - minZ
end

local function finish(ghost)
    placing = false
    if ghost then Util.delete(ghost) end
    lib.hideTextUI()
end

--- Enter placement mode for the bag the player is wearing.
--- `access` is 'private' or 'public'.
function StartPlacing(bagKey, access)
    if placing then return end
    access = access or (cfg.defaultAccess or 'private')
    if not Bags.exists(bagKey) then return end

    local ped = PlayerPedId()
    if cfg.blockInVehicle and IsPedInAnyVehicle(ped, false) then
        return Config.Notify(Strings.place_bad, 'error')
    end

    local st = LocalPlayer.state.nayzeee_backpack or {}
    local ghost, hash = Util.spawnBag(bagKey, st.variant, GetEntityCoords(ped))
    if not ghost then return end

    FreezeEntityPosition(ghost, true)
    SetEntityAlpha(ghost, 200, false)

    local centre, mn = Util.modelCentre(hash)
    local cx, cy, minZ = centre.x, centre.y, mn.z

    placing = true
    lib.showTextUI(('%s  ·  %s'):format(Config.Prompts.placeHelp,
        access == 'public' and Config.Prompts.accessPublic or Config.Prompts.accessPrivate),
        { position = 'bottom-center', icon = 'hand-pointer' })

    CreateThread(function()
        local heading = (GetEntityHeading(ped) + 180.0) % 360.0
        local step = cfg.rotateStep or 10.0
        local reachMax = cfg.maxDistance or 4.0
        local slope = cfg.maxSlope or 0.55
        local reachSq = reachMax * reachMax

        local shape = nil
        local hx, hy, hz = nil, nil, nil
        local valid, shownValid = false, true
        local lastX, lastY, lastZ, lastH = 0.0, 0.0, 0.0, -1.0

        while placing do
            for i = 1, NBLOCK do DisableControlAction(0, BLOCK[i], true) end

            -- read last frame's ray, then fire the next one
            if shape then
                local status, hit, endCoords, normal = GetShapeTestResult(shape)
                if status ~= 1 then
                    shape = nil
                    if status == 2 then
                        if hit == 1 and normal.z >= slope then
                            local pc = GetEntityCoords(ped)
                            local dx, dy, dz = endCoords.x - pc.x, endCoords.y - pc.y, endCoords.z - pc.z
                            valid = (dx * dx + dy * dy + dz * dz) <= reachSq
                            hx, hy, hz = endCoords.x, endCoords.y, endCoords.z
                        else
                            valid = false
                        end
                    end
                end
            end

            if not shape then
                local cam = GetFinalRenderedCamCoord()
                local rot = GetFinalRenderedCamRot(2)
                local rx, rz = mrad(rot.x), mrad(rot.z)
                local cxr = mabs(mcos(rx))
                local len = reachMax + 8.0
                shape = StartShapeTestLosProbe(cam.x, cam.y, cam.z,
                    cam.x - msin(rz) * cxr * len, cam.y + mcos(rz) * cxr * len, cam.z + msin(rx) * len,
                    17, ped, 7)
            end

            -- rotate (SHIFT for fine steps)
            local s = IsControlPressed(0, 21) and step * 0.2 or step
            if IsControlJustPressed(0, 241) then heading = (heading + s) % 360.0
            elseif IsControlJustPressed(0, 242) then heading = (heading - s) % 360.0 end

            -- only touch the ghost when something moved
            if hx and (mabs(hx - lastX) > 0.002 or mabs(hy - lastY) > 0.002 or mabs(hz - lastZ) > 0.002 or heading ~= lastH) then
                lastX, lastY, lastZ, lastH = hx, hy, hz, heading
                local ox, oy, oz = originFor(hx, hy, hz, heading, cx, cy, minZ)
                SetEntityCoordsNoOffset(ghost, ox, oy, oz, false, false, false)
                SetEntityHeading(ghost, heading)
            end

            if valid ~= shownValid then
                shownValid = valid
                SetEntityAlpha(ghost, valid and 200 or 70, false)
            end

            if IsControlJustPressed(0, 38) then -- E
                if valid and hx then
                    local ox, oy, oz = originFor(hx, hy, hz, heading, cx, cy, minZ)
                    finish(ghost)
                    ghost = nil

                    TaskTurnPedToFaceCoord(ped, hx, hy, hz, 500)
                    Wait(450)
                    if Util.loadDict('random@domestic') then
                        TaskPlayAnim(ped, 'random@domestic', 'pickup_low', 6.0, -4.0, 1100, 48, 0, false, false, false)
                        Wait(700)
                    end

                    TriggerServerEvent('nayzeee-backpack:place', bagKey, vector3(ox, oy, oz), heading, access)
                    break
                else
                    Config.Notify(hx and Strings.place_far or Strings.place_bad, 'error')
                end
            end

            if IsControlJustPressed(0, 194) or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then -- BACKSPACE
                finish(ghost)
                ghost = nil
                break
            end

            Wait(0)
        end

        if ghost then finish(ghost) end
    end)
end

function IsPlacing() return placing end

-----------------------------------------------------------------
-- placed props (only spawned while in render range)
-----------------------------------------------------------------

local function centreOf(data, hash)
    local c = Util.modelCentre(hash)
    local r = math.rad(data.heading or 0.0)
    local co, si = math.cos(r), math.sin(r)
    return vec3(
        data.coords.x + c.x * co - c.y * si,
        data.coords.y + c.x * si + c.y * co,
        data.coords.z + c.z)
end

local function despawnPlaced(id)
    Util.delete(placed[id])
    placed[id] = nil

    if placedZones[id] then
        exports.ox_target:removeZone(placedZones[id])
        placedZones[id] = nil
    end
end

local function removePlaced(id)
    despawnPlaced(id)
    placedData[id] = nil
end

local function addZone(data)
    if not (Config.Prompts.useTarget and GetResourceState('ox_target') == 'started') then return end

    -- A sphere zone, not addLocalEntity. These models are converted from
    -- clothing, which strips their physics bounds, so ox_target's raycast
    -- passes straight through the prop and no options would ever appear.
    placedZones[data.id] = exports.ox_target:addSphereZone({
        coords = data.centre,
        radius = 0.6,
        debug  = Config.Debug,
        options = {
            {
                name = 'nayzeee_placed_open_' .. data.id,
                label = Config.Prompts.openPlaced,
                icon = 'fa-solid fa-box-open',
                distance = 2.0,
                canInteract = function()
                    return data.access ~= 'private' or data.mine == true
                end,
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
                label = data.access == 'private' and Config.Prompts.makePublic or Config.Prompts.makePrivate,
                icon = data.access == 'private' and 'fa-solid fa-lock-open' or 'fa-solid fa-lock',
                distance = 2.0,
                canInteract = function()
                    return cfg.allowRetoggle and data.mine == true
                end,
                onSelect = function()
                    TriggerServerEvent('nayzeee-backpack:toggleAccess', data.id)
                end,
            },
        }
    })
end

local function spawnPlaced(data)
    despawnPlaced(data.id)
    if not Bags.exists(data.bag) then return end

    local entity, hash = Util.spawnBag(data.bag, data.variant, data.coords)
    if not entity then return end

    SetEntityCoordsNoOffset(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false)
    SetEntityHeading(entity, data.heading or 0.0)
    FreezeEntityPosition(entity, true)

    data.centre = centreOf(data, hash)
    placed[data.id] = entity
    addZone(data)
end

RegisterNetEvent('nayzeee-backpack:spawnPlaced', function(data)
    data.coords = vec3(data.coords.x, data.coords.y, data.coords.z)
    despawnPlaced(data.id)
    placedData[data.id] = data

    local range = cfg.renderDistance or 60.0
    if #(GetEntityCoords(PlayerPedId()) - data.coords) < range then
        spawnPlaced(data)
    end
end)

RegisterNetEvent('nayzeee-backpack:syncPlaced', function(list)
    for id in pairs(placedData) do removePlaced(id) end
    for _, data in pairs(list) do
        data.coords = vec3(data.coords.x, data.coords.y, data.coords.z)
        placedData[data.id] = data
    end
end)

RegisterNetEvent('nayzeee-backpack:removePlaced', function(id)
    removePlaced(id)
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then
        TriggerServerEvent('nayzeee-backpack:requestPlaced')
    end
end)

Framework.onPlayerLoaded(function()
    TriggerServerEvent('nayzeee-backpack:requestPlaced')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    placing = false
    for id in pairs(placedData) do removePlaced(id) end
end)

-- streaming loop: spawn bags as you approach, clean them up as you leave
CreateThread(function()
    local range = cfg.renderDistance or 60.0
    local rangeSq = range * range
    local outSq = (range + 10.0) * (range + 10.0)

    while true do
        if next(placedData) then
            local pc = GetEntityCoords(PlayerPedId())
            for id, data in pairs(placedData) do
                local dx, dy, dz = data.coords.x - pc.x, data.coords.y - pc.y, data.coords.z - pc.z
                local d = dx * dx + dy * dy + dz * dz
                if not placed[id] and d < rangeSq then
                    spawnPlaced(data)
                elseif placed[id] and d > outSq then
                    despawnPlaced(id)
                end
            end
            Wait(1500)
        else
            Wait(3000)
        end
    end
end)

-----------------------------------------------------------------
-- Proximity fallback
--
-- Without ox_target a placed bag would be unreachable, so this gives
-- every placed bag a prompt and a menu regardless.
-----------------------------------------------------------------

local usingTarget = Config.Prompts.useTarget and GetResourceState('ox_target') == 'started'

--- Nearest spawned placed bag within reach, or nil.
local function nearestPlaced()
    local coords = GetEntityCoords(PlayerPedId())
    local bestId, bestDist = nil, 2.0

    for id in pairs(placed) do
        local data = placedData[id]
        if data and data.centre then
            local d = #(data.centre - coords)
            if d < bestDist then bestId, bestDist = id, d end
        end
    end

    return bestId
end

--- Menu for a placed bag, honouring who owns it.
function OpenPlacedMenu(id)
    local data = placedData[id]
    if not data then return end

    local canTake = data.access ~= 'private' or data.mine
    local locked = data.access == 'private' and not data.mine
    local options = {}

    options[#options + 1] = {
        title = Config.Prompts.openPlaced,
        description = locked and 'Locked' or 'Look inside',
        icon = 'box-open',
        disabled = locked,
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
            title = data.access == 'private' and Config.Prompts.makePublic or Config.Prompts.makePrivate,
            description = data.access == 'private' and 'Let anyone use it' or 'Lock it to you',
            icon = data.access == 'private' and 'lock-open' or 'lock',
            onSelect = function()
                TriggerServerEvent('nayzeee-backpack:toggleAccess', id)
            end,
        }
    end

    lib.registerContext({
        id = 'nayzeee_placed_menu',
        title = Bags.label(data.bag) or Config.Prompts.menuTitle,
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
                    lib.showTextUI('[E] Backpack')

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
