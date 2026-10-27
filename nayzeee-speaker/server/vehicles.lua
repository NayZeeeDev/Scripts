-- CarPlay: music in a vehicle, optionally only once a unit is installed in it (remembered by plate).
local cp = Config.Carplay
local noUnit = NZ.Cache(60)         -- plates just checked and found without a unit (saves a query per open)

local function hasUnit(veh)
    if not cp.install.use then return true end
    if Entity(veh).state.nzCarplay then return true end
    local plate = NZ.Trim(GetVehicleNumberPlateText(veh))
    if plate == '' or noUnit.get(plate) then return false end
    if DB.CarplayInstalled(plate) then
        Entity(veh).state:set('nzCarplay', true, true)
        return true
    end
    noUnit.set(plate, true)
    return false
end

-- the player's vehicle for a netId they sent, if they are within `max` metres of it
local function vehicleNear(src, netId, max)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local ped = GetPlayerPed(src)
    if veh == 0 or ped == 0 or not DoesEntityExist(veh) then return nil end
    return #(GetEntityCoords(ped) - GetEntityCoords(veh)) <= max and veh or nil
end

-- Garage scripts can call this when a vehicle spawns (optional, the check also runs when someone opens it)
local function checkCarPlay(netId)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if veh ~= 0 and DoesEntityExist(veh) then hasUnit(veh) end
end
exports('CheckCarPlay', checkCarPlay)
RegisterNetEvent(RES .. ':server:CheckCarPlay', checkCarPlay)

NZ.RegisterCallback('vehicle:open', function(src, netId)
    if not cp.enabled then Notify(src, 'carplay_disabled') return nil end
    netId = tonumber(netId)
    local veh = NetworkGetEntityFromNetworkId(netId or 0)
    if veh == 0 or GetVehiclePedIsIn(GetPlayerPed(src), false) ~= veh then return nil end
    local bl = Config.BlacklistedVehicles
    if bl.models and bl.models[GetEntityModel(veh)] then Notify(src, 'blacklisted_vehicle') return nil end
    if not hasUnit(veh) then Notify(src, 'carplay_needed') return nil end

    local id = 'v' .. netId
    if not Emitters[id] then
        if NZ.InBlacklistedZone(GetEntityCoords(veh)) then Notify(src, 'blacklisted_zone') return nil end
        Broadcast(NewEmitter({
            id = id, kind = 'vehicle', label = 'CarPlay', vehNet = netId,
            plate = NZ.Trim(GetVehicleNumberPlateText(veh)),
            owner = Bridge.GetIdentifier(src), ownerSrc = src,
            bucket = GetPlayerRoutingBucket(src), range = Config.Ranges.vehicle.default,
        }))
    end
    return id, cp.install.use
end)

RegisterNetEvent(RES .. ':carplay:install', function(netId)
    local src = source
    if not cp.install.use then return end
    local veh = vehicleNear(src, netId, 6.0)
    if not veh then return Notify(src, 'carplay_no_vehicle') end
    if hasUnit(veh) then return Notify(src, 'carplay_already') end
    local plate = NZ.Trim(GetVehicleNumberPlateText(veh))
    if not Bridge.HasItem(src, cp.install.item) or not Bridge.RemoveItem(src, cp.install.item) then return Notify(src, 'no_item') end
    DB.CarplaySet(plate, Bridge.GetIdentifier(src), true)
    noUnit.set(plate, false)
    Entity(veh).state:set('nzCarplay', true, true)
    Notify(src, 'carplay_installed', 'success')
    Log('CarPlay installed', ('**%s** (%s) installed a unit in `%s`'):format(GetPlayerName(src), src, plate))
end)

RegisterNetEvent(RES .. ':carplay:remove', function(netId)
    local src = source
    if not cp.install.use then return end
    local veh = vehicleNear(src, netId, 6.0)
    if not veh then return Notify(src, 'carplay_no_vehicle') end
    if not hasUnit(veh) then return end
    local plate = NZ.Trim(GetVehicleNumberPlateText(veh))
    if cp.install.ownerOnly and not Bridge.OwnsVehicle(src, plate) and not Bridge.IsAdmin(src) then
        return Notify(src, 'carplay_not_owner')
    end
    DB.CarplaySet(plate, nil, false)
    Entity(veh).state:set('nzCarplay', false, true)
    local e = Emitters['v' .. tonumber(netId)]
    if e then RemoveEmitter(e) end
    Bridge.AddItem(src, cp.install.item)
    Notify(src, 'carplay_removed', 'success')
end)

if cp.install.use then
    Bridge.RegisterUsable(cp.install.item, function(src) TriggerClientEvent(RES .. ':client:installCarplay', src) end)
end

-- cleanup: deleted vehicles, empty vehicles (only CarPlay emitters are looked at)
CreateThread(function()
    while true do
        Wait(3000)
        for _, e in pairs(Emitters) do
            if e.kind == 'vehicle' then
                local veh = NetworkGetEntityFromNetworkId(e.vehNet)
                if veh == 0 or not DoesEntityExist(veh) then
                    RemoveEmitter(e)
                elseif Config.StopMusicWhenVehicleIsEmpty and e.playing then
                    local anyone = false
                    for seat = -1, 6 do
                        if GetPedInVehicleSeat(veh, seat) ~= 0 then anyone = true break end
                    end
                    if not anyone then PauseEmitter(e) end
                end
            end
        end
    end
end)
