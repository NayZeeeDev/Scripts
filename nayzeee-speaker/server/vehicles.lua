local RES = GetCurrentResourceName()
local cp = Config.Carplay

local function trimPlate(p) return p and (p:gsub('^%s+', ''):gsub('%s+$', '')) or nil end

local function hasUnit(veh)
    if not cp.install.use then return true end
    if Entity(veh).state.nzCarplay then return true end
    local plate = trimPlate(GetVehicleNumberPlateText(veh))
    local on = plate and DB.CarplayInstalled(plate)
    if on then Entity(veh).state:set('nzCarplay', true, true) end
    return on
end

-- Garage scripts can call this when a vehicle spawns (optional, the check also runs lazily)
local function checkCarPlay(netId)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if veh ~= 0 and DoesEntityExist(veh) then hasUnit(veh) end
end
exports('CheckCarPlay', checkCarPlay)
RegisterNetEvent(RES .. ':server:CheckCarPlay', checkCarPlay)

NZ.RegisterCallback('vehicle:open', function(src, netId)
    if not cp.enabled then Notify(src, 'carplay_disabled') return nil end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local ped = GetPlayerPed(src)
    if veh == 0 or GetVehiclePedIsIn(ped, false) ~= veh then return nil end
    local bl = Config.BlacklistedVehicles
    if bl.models and bl.models[GetEntityModel(veh)] then Notify(src, 'blacklisted_vehicle') return nil end
    if not hasUnit(veh) then Notify(src, 'carplay_needed') return nil end

    local id = 'v' .. netId
    local e = Emitters[id]
    if not e then
        if NZ.InBlacklistedZone(GetEntityCoords(veh)) then Notify(src, 'blacklisted_zone') return nil end
        e = NewEmitter({
            id = id, kind = 'vehicle', label = 'CarPlay', vehNet = netId,
            plate = trimPlate(GetVehicleNumberPlateText(veh)),
            owner = Bridge.GetIdentifier(src), ownerSrc = src,
            bucket = GetPlayerRoutingBucket(src), range = Config.Ranges.vehicle.default,
        })
        Broadcast(e)
    end
    return id, cp.install.use
end)

RegisterNetEvent(RES .. ':carplay:install', function(netId)
    local src = source
    if not cp.install.use then return end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if veh == 0 or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 6.0 then return Notify(src, 'carplay_no_vehicle') end
    local plate = trimPlate(GetVehicleNumberPlateText(veh))
    if hasUnit(veh) then return Notify(src, 'carplay_already') end
    if not Bridge.HasItem(src, cp.install.item) or not Bridge.RemoveItem(src, cp.install.item) then return Notify(src, 'no_item') end
    DB.CarplaySet(plate, Bridge.GetIdentifier(src), true)
    Entity(veh).state:set('nzCarplay', true, true)
    Notify(src, 'carplay_installed', 'success')
    Log('CarPlay installed', ('**%s** (%s) installed a unit in `%s`'):format(GetPlayerName(src), src, plate))
end)

RegisterNetEvent(RES .. ':carplay:remove', function(netId)
    local src = source
    if not cp.install.use then return end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if veh == 0 or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 6.0 then return Notify(src, 'carplay_no_vehicle') end
    local plate = trimPlate(GetVehicleNumberPlateText(veh))
    if not hasUnit(veh) then return end
    if cp.install.ownerOnly and not Bridge.OwnsVehicle(src, plate) and not Bridge.IsAdmin(src) then
        return Notify(src, 'carplay_not_owner')
    end
    DB.CarplaySet(plate, nil, false)
    Entity(veh).state:set('nzCarplay', false, true)
    local e = Emitters['v' .. netId]
    if e then RemoveEmitter(e) end
    Bridge.AddItem(src, cp.install.item)
    Notify(src, 'carplay_removed', 'success')
end)

if cp.install.use then
    local function use(src) TriggerClientEvent(RES .. ':client:installCarplay', src) end
    Bridge.RegisterUsable(cp.install.item, use)
    Bridge.OnUse[cp.install.item] = use
end

-- cleanup: deleted vehicles, empty vehicles
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
