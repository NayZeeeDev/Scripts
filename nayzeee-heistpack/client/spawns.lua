--[[
    Spawner: when the server picks this client to spawn a stage (guards, vehicles, peds, objects)
    it creates networked entities here and reports the net ids back. Guard AI settings are
    applied on every client through the `nzhGuard` state bag, so ownership migration is safe.
]]

local GUARD_GROUP = joaat('NZH_GUARDS')
AddRelationshipGroup('NZH_GUARDS')
SetRelationshipBetweenGroups(5, GUARD_GROUP, joaat('PLAYER'))
SetRelationshipBetweenGroups(5, joaat('PLAYER'), GUARD_GROUP)
SetRelationshipBetweenGroups(0, GUARD_GROUP, GUARD_GROUP)
SetRelationshipBetweenGroups(1, GUARD_GROUP, joaat('COP'))
SetRelationshipBetweenGroups(1, joaat('COP'), GUARD_GROUP)

local DEFAULT_GUARD = 's_m_m_highsec_01'
local DEFAULT_WEAPON = 'WEAPON_CARBINERIFLE'

local function setupGuard(ped)
    if not DoesEntityExist(ped) then return end
    SetPedRelationshipGroupHash(ped, GUARD_GROUP)
    SetPedCombatAttributes(ped, 46, true)  -- always fight
    SetPedCombatAttributes(ped, 5, true)   -- can fight armed peds when unarmed
    SetPedCombatAttributes(ped, 0, true)   -- use cover
    SetPedCombatAbility(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedAccuracy(ped, Config.Gameplay.guardAccuracy)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedSeeingRange(ped, 60.0)
    SetPedHearingRange(ped, 60.0)
    SetPedAlertness(ped, 3)
    SetPedKeepTask(ped, true)
    SetCanAttackFriendly(ped, false, false)
    SetPedSuffersCriticalHits(ped, true)
end

AddStateBagChangeHandler('nzhGuard', nil, function(bagName, _, value)
    if not value then return end
    local ent = GetEntityFromStateBagName(bagName)
    if ent == 0 then
        -- entity not created locally yet; retry briefly
        CreateThread(function()
            for _ = 1, 20 do
                Wait(200)
                ent = GetEntityFromStateBagName(bagName)
                if ent ~= 0 then setupGuard(ent) return end
            end
        end)
        return
    end
    setupGuard(ent)
end)

local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelValid(hash) then return nil end
    lib.requestModel(hash, 15000)
    return hash
end

local function spawnPed(spec, isGuard)
    local hash = loadModel(spec.model or DEFAULT_GUARD)
    if not hash then return nil end
    local c = spec.coords
    local z = c.z
    if spec.ground then
        local found, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 4.0, false)
        if found then z = gz + 1.0 end
    end
    local ped = CreatePed(4, hash, c.x, c.y, z - 1.0, c.w or 0.0, true, true)
    local timeout = 0
    while not DoesEntityExist(ped) and timeout < 50 do Wait(20) timeout = timeout + 1 end
    if not DoesEntityExist(ped) then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    SetModelAsNoLongerNeeded(hash)
    if isGuard then
        GiveWeaponToPed(ped, joaat(spec.weapon or DEFAULT_WEAPON), 500, false, true)
        SetPedArmour(ped, spec.armour or Config.Gameplay.guardArmour)
        setupGuard(ped)
        if spec.scenario then TaskStartScenarioInPlace(ped, spec.scenario, 0, true)
        else TaskGuardCurrentPosition(ped, 15.0, 10.0, true) end
    else
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedFleeAttributes(ped, 0, false)
        if spec.scenario then TaskStartScenarioInPlace(ped, spec.scenario, 0, true) end
        if spec.invincible then SetEntityInvincible(ped, true) end
        if spec.freeze then FreezeEntityPosition(ped, true) end
    end
    return ped
end

local TRAIN_MODELS = { 'freight', 'freightcar', 'freightcont1', 'freightcont2', 'freightgrain', 'tankercar', 'metrotrain' }

local function spawnVehicle(spec)
    local hash
    if spec.train then
        for i = 1, #TRAIN_MODELS do loadModel(TRAIN_MODELS[i]) end
        hash = joaat('freight')
    else
        hash = loadModel(spec.model)
    end
    if not hash then return nil end
    local c = spec.coords
    local veh
    if spec.train then
        veh = CreateMissionTrain(spec.variation or 24, c.x, c.y, c.z, spec.direction or true, true, true)
        SetTrainSpeed(veh, 0.0)
        SetTrainCruiseSpeed(veh, 0.0)
    else
        veh = CreateVehicle(hash, c.x, c.y, c.z, c.w or 0.0, true, true)
    end
    local timeout = 0
    while not DoesEntityExist(veh) and timeout < 50 do Wait(20) timeout = timeout + 1 end
    if not DoesEntityExist(veh) then return nil end
    SetEntityAsMissionEntity(veh, true, true)
    if not spec.freeze and not spec.train then SetVehicleOnGroundProperly(veh) end
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    if spec.plate then SetVehicleNumberPlateText(veh, spec.plate) end
    if spec.livery then SetVehicleLivery(veh, spec.livery) end
    if spec.freeze then FreezeEntityPosition(veh, true) end
    FW.setFuel(veh, 100.0)
    SetModelAsNoLongerNeeded(hash)

    local crew = {}
    for i = 1, #(spec.passengers or {}) do
        local p = spec.passengers[i]
        local ped = spawnPed({ model = p.model or DEFAULT_GUARD, coords = vec4(c.x, c.y, c.z + 2.0, c.w or 0.0), weapon = p.weapon }, true)
        if ped then
            SetPedIntoVehicle(ped, veh, i - 1)
            crew[#crew + 1] = ped
        end
    end

    if spec.driver then
        local driver = spawnPed({ model = spec.driver.model or DEFAULT_GUARD, coords = vec4(c.x, c.y, c.z + 2.0, c.w or 0.0), weapon = spec.driver.weapon }, true)
        if driver then
            SetPedIntoVehicle(driver, veh, -1)
            if spec.route then
                local r = spec.route
                TaskVehicleDriveToCoordLongrange(driver, veh, r.x, r.y, r.z, spec.speed or 20.0, spec.style or 786603, 10.0)
            else
                TaskVehicleDriveWander(driver, veh, spec.speed or 18.0, spec.style or 786603)
            end
            SetDriverAbility(driver, 1.0)
        end
        return veh, driver, crew
    end
    return veh, nil, crew
end

local function spawnObject(spec)
    local hash = loadModel(spec.model)
    if not hash then return nil end
    local c = spec.coords
    local obj = CreateObjectNoOffset(hash, c.x, c.y, c.z, true, true, false)
    local timeout = 0
    while not DoesEntityExist(obj) and timeout < 50 do Wait(20) timeout = timeout + 1 end
    SetEntityHeading(obj, c.w or 0.0)
    if spec.ground ~= false then PlaceObjectOnGroundProperly(obj) end
    FreezeEntityPosition(obj, spec.freeze == true)
    SetEntityAsMissionEntity(obj, true, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

RegisterNetEvent('nzh:heist:doSpawn', function(uid, idx, spec)
    if GetInvokingResource() then return end
    local result = { guards = {}, entities = {} }

    for i = 1, #(spec.guards or {}) do
        local g = spec.guards[i]
        local ped = spawnPed(g, true)
        if ped then
            local group = g.group or 'guards'
            result.guards[group] = result.guards[group] or {}
            local list = result.guards[group]
            list[#list + 1] = NetworkGetNetworkIdFromEntity(ped)
        end
    end
    for i = 1, #(spec.vehicles or {}) do
        local v = spec.vehicles[i]
        local veh, driver, crew = spawnVehicle(v)
        if veh and v.key then result.entities[v.key] = NetworkGetNetworkIdFromEntity(veh) end
        local group = v.driver and v.driver.group or v.group
        if group then
            local list = result.guards[group] or {}
            if driver then list[#list + 1] = NetworkGetNetworkIdFromEntity(driver) end
            for j = 1, #(crew or {}) do list[#list + 1] = NetworkGetNetworkIdFromEntity(crew[j]) end
            result.guards[group] = list
        end
        if veh and v.attachTo then
            local parent = result.entities[v.attachTo] and NetworkGetEntityFromNetworkId(result.entities[v.attachTo])
            if parent and parent ~= 0 then AttachVehicleToTrailer(parent, veh, 1.1) end
        end
    end
    for i = 1, #(spec.peds or {}) do
        local p = spec.peds[i]
        local ped = spawnPed(p, false)
        if ped and p.key then result.entities[p.key] = NetworkGetNetworkIdFromEntity(ped) end
    end
    for i = 1, #(spec.objects or {}) do
        local o = spec.objects[i]
        local obj = spawnObject(o)
        if obj and o.key then result.entities[o.key] = NetworkGetNetworkIdFromEntity(obj) end
    end

    lib.callback.await('nzh:heist:spawned', false, uid, idx, result)
end)
