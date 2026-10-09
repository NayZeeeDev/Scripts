--[[
    nz_cpuchip - client

    Exports (call from other resources):
        exports.nz_cpuchip:SpawnChip(coords?, heading?)  -> object handle (physics enabled)
        exports.nz_cpuchip:HoldChip()                    -> attaches the chip to the right hand + inspect anim
        exports.nz_cpuchip:ReleaseChip()                 -> detaches / deletes the held chip
        exports.nz_cpuchip:InspectChip(durationMs?)      -> hold for a while, then release (used by the item)
        exports.nz_cpuchip:cpu_chip(data, slot)          -> ox_inventory client item export
]]

local model = joaat(Config.Model)
local held      -- object attached to the player's hand
local spawned = {}

local function loadModel()
    if HasModelLoaded(model) then return true end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        if GetGameTimer() > deadline then
            print(('[nz_cpuchip] model %s did not load - is the ytyp registered?'):format(Config.Model))
            return false
        end
        Wait(10)
    end
    return true
end

local function loadAnim(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end
        Wait(10)
    end
    return true
end

--- Spawn a loose chip with physics. Returns the object handle (0 on failure).
local function SpawnChip(coords, heading)
    if not loadModel() then return 0 end
    local ped = PlayerPedId()
    if not coords then
        coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.SpawnDistance, 0.2)
    end
    local obj = CreateObject(model, coords.x, coords.y, coords.z, true, true, true)
    SetEntityHeading(obj, heading or GetEntityHeading(ped))
    SetEntityDynamic(obj, true)
    ActivatePhysics(obj)
    PlaceObjectOnGroundProperly(obj)
    SetModelAsNoLongerNeeded(model)
    spawned[#spawned + 1] = obj
    return obj
end

local function ReleaseChip()
    local ped = PlayerPedId()
    if held and DoesEntityExist(held) then
        DetachEntity(held, true, true)
        DeleteEntity(held)
    end
    held = nil
    if IsEntityPlayingAnim(ped, Config.Hold.anim.dict, Config.Hold.anim.name, 3) then
        StopAnimTask(ped, Config.Hold.anim.dict, Config.Hold.anim.name, 1.0)
    end
end

--- Attach a chip to the right hand and play the inspect animation (loops until ReleaseChip()).
local function HoldChip()
    if held and DoesEntityExist(held) then return held end
    if not loadModel() then return 0 end
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local obj = CreateObject(model, pos.x, pos.y, pos.z + 0.2, true, true, false)
    local h = Config.Hold
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, h.bone),
        h.offset.x, h.offset.y, h.offset.z,
        h.rotation.x, h.rotation.y, h.rotation.z,
        true, true, false, false, 2, true)
    SetModelAsNoLongerNeeded(model)
    held = obj
    if loadAnim(h.anim.dict) then
        TaskPlayAnim(ped, h.anim.dict, h.anim.name, 4.0, -4.0, -1, h.anim.flag, 0.0, false, false, false)
    end
    return obj
end

--- Hold the chip for `duration` ms (default Config.Hold.duration), then put it away.
local function InspectChip(duration)
    if HoldChip() == 0 then return false end
    Wait(duration or Config.Hold.duration)
    ReleaseChip()
    return true
end

local function ClearChips()
    ReleaseChip()
    for _, obj in ipairs(spawned) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    spawned = {}
end

exports('SpawnChip', SpawnChip)
exports('HoldChip', HoldChip)
exports('ReleaseChip', ReleaseChip)
exports('InspectChip', InspectChip)
exports('ClearChips', ClearChips)

-- ox_inventory: items.lua -> client = { export = 'nz_cpuchip.cpu_chip' }
-- The chip is a PC component, so using it only inspects it; nothing is consumed.
exports('cpu_chip', function(data, slot)
    InspectChip()
end)

-- qb-core / esx usable item (triggered from server/main.lua)
RegisterNetEvent('nz_cpuchip:client:inspect', function()
    InspectChip()
end)

if Config.Debug then
    RegisterCommand('cpuchip', function(_, args)
        local sub = (args[1] or 'spawn'):lower()
        if sub == 'spawn' then
            local obj = SpawnChip()
            Config.Notify(obj ~= 0 and ('Spawned %s (%d)'):format(Config.Model, obj) or 'Model failed to load', obj ~= 0 and 'success' or 'error')
        elseif sub == 'hold' then
            HoldChip()
        elseif sub == 'drop' then
            ReleaseChip()
        elseif sub == 'clear' then
            ClearChips()
            Config.Notify('Removed all spawned chips')
        else
            Config.Notify('/cpuchip spawn | hold | drop | clear')
        end
    end, false)
    TriggerEvent('chat:addSuggestion', '/cpuchip', 'nz_cpuchip debug: spawn | hold | drop | clear')
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then ClearChips() end
end)
