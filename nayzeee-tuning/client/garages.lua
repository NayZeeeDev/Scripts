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

local G = Config.Garages or {}
local H = G.Hooks or {}

-- JG Advanced Garages: fired on the client once the car is out (vehicle, vehicleDbData, type)
if H.jg then
    AddEventHandler('jg-advancedgarages:client:TakeOutVehicle:config', function(vehicle) Garages.Spawned(vehicle) end)
end

-- most QBCore / Qbox garages hand out keys for the plate right after spawning the car
if H.keys then
    RegisterNetEvent('vehiclekeys:client:SetOwner', function(plate)
        if type(plate) ~= 'string' then return end
        plate = NZ.TrimPlate(plate)
        CreateThread(function()
            -- the car (or its plate) can reach this client a moment after the event
            for _ = 1, 15 do
                local me = GetEntityCoords(cache.ped)
                for _, veh in ipairs(GetGamePool('CVehicle')) do
                    if NZ.TrimPlate(GetVehicleNumberPlateText(veh)) == plate and #(GetEntityCoords(veh) - me) < 60.0 then
                        return Garages.Spawned(veh)
                    end
                end
                Wait(200)
            end
        end)
    end)
end

-- any other garage: its client "vehicle taken out" event, first argument = the vehicle
for _, name in ipairs(G.Events or {}) do
    AddEventHandler(name, function(vehicle) Garages.Spawned(vehicle) end)
end
