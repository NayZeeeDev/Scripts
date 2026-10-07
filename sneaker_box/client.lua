local STATE_KEY = 'nzShoeboxOpen'

-- [baseEntity] = { lid, angle, from, to, startTime, duration, opening }
local boxes = {}
local animating = 0
local warnedMissing = false

-- Easing -----------------------------------------------------------------------

local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1.0
    return 1.0 + c3 * (t - 1.0) ^ 3 + c1 * (t - 1.0) ^ 2
end

local function easeOutBounce(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1.0 / d1 then
        return n1 * t * t
    elseif t < 2.0 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    end
    t = t - 2.625 / d1
    return n1 * t * t + 0.984375
end

-- Helpers ----------------------------------------------------------------------

local function modelAvailable()
    if IsModelInCdimage(Config.BaseModel) and IsModelInCdimage(Config.LidModel) then
        return true
    end
    if not warnedMissing then
        warnedMissing = true
        print(('^1[sneaker_box]^7 %s'):format(Config.Text.noModel))
    end
    return false
end

local function loadModel(model)
    if HasModelLoaded(model) then return true end
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        if GetGameTimer() > timeout then return false end
        Wait(0)
    end
    return true
end

local function isOpen(base)
    return Entity(base).state[STATE_KEY] == true
end

local function attachLid(base, lid, angle)
    local h = Config.HingeOffset
    AttachEntityToEntity(lid, base, 0, h.x, h.y, h.z, angle, 0.0, 0.0,
        false, false, false, false, 2, true)
end

local function playInteractAnim()
    if not Config.Anim then return end
    local ped = PlayerPedId()
    RequestAnimDict(Config.Anim.dict)
    local timeout = GetGameTimer() + 1000
    while not HasAnimDictLoaded(Config.Anim.dict) and GetGameTimer() < timeout do Wait(0) end
    TaskPlayAnim(ped, Config.Anim.dict, Config.Anim.clip, 8.0, -8.0, Config.Anim.time, 0, 0.0, false, false, false)
    RemoveAnimDict(Config.Anim.dict)
end

-- Lid animation ----------------------------------------------------------------

local function animateTo(base, open)
    local box = boxes[base]
    if not box then return end

    local target = open and Config.OpenAngle or 0.0
    if box.to == target then return end

    if not box.startTime then animating = animating + 1 end
    box.from = box.angle
    box.to = target
    box.opening = open
    box.startTime = GetGameTimer()
    box.duration = open and Config.OpenTime or Config.CloseTime
end

local function stepAnimations()
    local now = GetGameTimer()
    for base, box in pairs(boxes) do
        if box.startTime then
            local t = math.min((now - box.startTime) / box.duration, 1.0)
            local eased = box.opening and easeOutBack(t) or easeOutBounce(t)
            box.angle = box.from + (box.to - box.from) * eased
            if t >= 1.0 then
                box.angle = box.to
                box.startTime = nil
                animating = animating - 1
            end
            if DoesEntityExist(box.lid) then
                attachLid(base, box.lid, box.angle)
            end
        end
    end
end

CreateThread(function()
    while true do
        if animating > 0 then
            stepAnimations()
            Wait(0)
        else
            Wait(100)
        end
    end
end)

AddStateBagChangeHandler(STATE_KEY, nil, function(bagName, _, value)
    local base = GetEntityFromStateBagName(bagName)
    if base ~= 0 and boxes[base] then
        animateTo(base, value == true)
    end
end)

-- Lid streaming ----------------------------------------------------------------
-- The base is a networked object; every client spawns its own local lid on it
-- and animates it from the synced open state, so the swing is smooth for all.

local function removeBox(base)
    local box = boxes[base]
    if not box then return end
    if box.startTime then animating = animating - 1 end
    if DoesEntityExist(box.lid) then DeleteEntity(box.lid) end
    boxes[base] = nil
end

local function addBox(base)
    if not loadModel(Config.LidModel) then return end
    if not DoesEntityExist(base) or boxes[base] then return end

    local coords = GetEntityCoords(base)
    local lid = CreateObject(Config.LidModel, coords.x, coords.y, coords.z, false, false, false)
    SetEntityCollision(lid, false, false)
    SetEntityInvincible(lid, true)

    local angle = isOpen(base) and Config.OpenAngle or 0.0
    attachLid(base, lid, angle)
    boxes[base] = { lid = lid, angle = angle, to = angle }
    SetModelAsNoLongerNeeded(Config.LidModel)
end

CreateThread(function()
    while true do
        if modelAvailable() then
            local myPos = GetEntityCoords(PlayerPedId())
            local baseHash = Config.BaseModel & 0xFFFFFFFF
            for _, obj in ipairs(GetGamePool('CObject')) do
                if not boxes[obj] and (GetEntityModel(obj) & 0xFFFFFFFF) == baseHash
                    and #(GetEntityCoords(obj) - myPos) < Config.StreamDistance then
                    addBox(obj)
                end
            end
            for base in pairs(boxes) do
                if not DoesEntityExist(base)
                    or #(GetEntityCoords(base) - myPos) > Config.StreamDistance + 5.0 then
                    removeBox(base)
                end
            end
        end
        Wait(500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for base in pairs(boxes) do removeBox(base) end
end)

-- Interaction ------------------------------------------------------------------

local function closestBox(maxDist)
    local myPos = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, maxDist
    for base in pairs(boxes) do
        local dist = #(GetEntityCoords(base) - myPos)
        if dist < bestDist then best, bestDist = base, dist end
    end
    return best
end

local function toggleBox(base)
    if not base or not NetworkGetEntityIsNetworked(base) then return end
    playInteractAnim()
    TriggerServerEvent('nz_shoebox:toggle', NetworkGetNetworkIdFromEntity(base))
end

local function useTarget()
    return Config.UseTarget and GetResourceState('ox_target') == 'started'
end

CreateThread(function()
    if useTarget() then
        exports.ox_target:addModel(Config.BaseModel, {
            {
                name = 'nz_shoebox_open',
                icon = 'fa-solid fa-box-open',
                label = Config.Text.open,
                distance = Config.InteractDistance,
                canInteract = function(entity) return not isOpen(entity) end,
                onSelect = function(data) toggleBox(data.entity) end,
            },
            {
                name = 'nz_shoebox_close',
                icon = 'fa-solid fa-box',
                label = Config.Text.close,
                distance = Config.InteractDistance,
                canInteract = function(entity) return isOpen(entity) end,
                onSelect = function(data) toggleBox(data.entity) end,
            },
        })
        return
    end

    while true do
        local base = next(boxes) and closestBox(Config.InteractDistance)
        if base then
            Config.ShowPrompt(isOpen(base) and Config.Text.close or Config.Text.open)
            if IsControlJustReleased(0, Config.Key) then
                toggleBox(base)
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

-- Commands ---------------------------------------------------------------------

RegisterCommand(Config.Commands.spawn, function()
    if not modelAvailable() then
        Config.Notify(Config.Text.noModel)
        return
    end

    local ped = PlayerPedId()
    local spot = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.65, 0.0)
    local found, groundZ = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 1.0, false)
    if found then spot = vector3(spot.x, spot.y, groundZ) end

    -- Front of the box faces the player
    local heading = (GetEntityHeading(ped) + 180.0) % 360.0
    playInteractAnim()
    TriggerServerEvent('nz_shoebox:spawn', spot, heading)
end, false)

RegisterCommand(Config.Commands.delete, function()
    local base = closestBox(2.5)
    if not base or not NetworkGetEntityIsNetworked(base) then
        Config.Notify(Config.Text.noBox)
        return
    end
    TriggerServerEvent('nz_shoebox:delete', NetworkGetNetworkIdFromEntity(base))
end, false)

RegisterNetEvent('nz_shoebox:notify', function(key)
    if Config.Text[key] then Config.Notify(Config.Text[key]) end
end)
