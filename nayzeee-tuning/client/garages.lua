--[[
    Garage integration: a car fresh out of a garage gets its tuning straight away.
    The garage sets the plate on the spawning client first and the server only sees it a sync later,
    so the client sends the plate it sees and the server applies the data once its own copy matches.
]]

Garages = {}

local watching = {}

-- some garages pass a net id instead of the entity
local function resolve(v)
    if type(v) ~= 'number' then return nil end
    if DoesEntityExist(v) and GetEntityType(v) == 2 then return v end
    if NetworkDoesEntityExistWithNetworkId(v) then return NetToVeh(v) end
end

function Garages.Spawned(vehicle)
    local veh = resolve(vehicle)
    if not veh or veh == 0 or watching[veh] then return end
    watching[veh] = true
    CreateThread(function()
        for _ = 1, 10 do
            if not DoesEntityExist(veh) or Entity(veh).state.nzTune then break end
            if NetworkGetEntityIsNetworked(veh) then
                TriggerServerEvent('nayzeee-tuning:requestData', VehToNet(veh), GetVehicleNumberPlateText(veh))
            end
            Wait(1000)
        end
        watching[veh] = nil
    end)
end

-- for garages without an event: exports['nayzeee-tuning']:VehicleSpawned(vehicle)
exports('VehicleSpawned', Garages.Spawned)
AddEventHandler('nayzeee-tuning:vehicleSpawned', Garages.Spawned)

for _, name in ipairs(Config.Garages and Config.Garages.Events or {}) do
    AddEventHandler(name, function(vehicle) Garages.Spawned(vehicle) end)
end
