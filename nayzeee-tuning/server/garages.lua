--[[
    Garage hooks (Config.Garages.Hooks): put a car's tuning on it the moment a garage spawns it,
    instead of waiting for the plate to sync. Every hook is harmless when that garage isn't running.
]]

local H = Config.Garages and Config.Garages.Hooks or {}

-- ESX Legacy (esx_garage...): the plate comes from ESX's own database row, so it can be used right away
if H.esx then
    AddEventHandler('esx:createdExtendedVehicle', function(xVehicle)
        local plate = type(xVehicle) == 'table' and xVehicle.plate
        if type(plate) ~= 'string' then return end
        local veh = Bridge.ExtendedVehicleEntity(plate)
        if veh and veh ~= 0 then Vehicles.Watch(veh, plate, true) end
    end)

    -- ESX.OneSync.SpawnVehicle hands the props (and plate) to the owner client through this bag
    AddStateBagChangeHandler('VehicleProperties', '', function(bagName, _, value)
        if type(value) ~= 'table' or type(value.plate) ~= 'string' then return end
        local veh = GetEntityFromStateBagName(bagName)
        if veh and veh ~= 0 then Vehicles.Watch(veh, value.plate) end
    end)
end

-- qbx_garages, and anything else spawning with ox_lib's props bag
if H.qbx then
    AddEventHandler('qbx_garages:server:vehicleSpawned', function(veh)
        Vehicles.Watch(veh)
    end)

    AddStateBagChangeHandler('setVehicleProperties', '', function(bagName, _, value)
        if type(value) ~= 'table' or type(value.plate) ~= 'string' then return end
        local veh = GetEntityFromStateBagName(bagName)
        if veh and veh ~= 0 then Vehicles.Watch(veh, value.plate) end
    end)
end

-- garages / key scripts that send the plate to the server right after a spawn (Config.Garages.ServerPlateEvents)
-- the plate is only a hint: the car must carry it on the server before anything is pushed
if H.keys then
    for _, name in ipairs(Config.Garages.ServerPlateEvents or {}) do
        RegisterNetEvent(name, function(plate)
            if type(plate) ~= 'string' or not Core.Throttle(source, 'garage', 500) then return end
            local hint, ped = NZ.TrimPlate(plate), GetPlayerPed(source)
            CreateThread(function()
                -- the plate can reach the server a moment after the event
                for _ = 1, 15 do
                    local veh = Vehicles.FindByPlate(hint)
                    if veh then
                        if #(GetEntityCoords(veh) - GetEntityCoords(ped)) < 80.0 then Vehicles.Watch(veh, hint) end
                        return
                    end
                    Wait(200)
                end
            end)
        end)
    end
end

-- qb-garages: the client reports the car as out once its props are on
if H.qb then
    RegisterNetEvent('qb-garages:server:updateVehicleState', function(state, plate)
        if state ~= 0 or type(plate) ~= 'string' or not Core.Throttle(source, 'garage', 500) then return end
        local veh = Vehicles.FindByPlate(plate)
        if veh then Vehicles.Watch(veh, plate) end
    end)
end
