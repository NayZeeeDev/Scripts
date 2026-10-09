local cp = Config.Carplay

local function vehicleNear()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then return veh end
    local c = GetEntityCoords(ped)
    local f = GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.0)
    local h = StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, c.z, f.x, f.y, f.z, 2, ped, 7)
    local _, hit, _, _, ent = GetShapeTestResult(h)
    if hit == 1 and ent ~= 0 and IsEntityAVehicle(ent) then return ent end
    local near = GetClosestVehicle(c.x, c.y, c.z, 3.0, 0, 71)
    return near ~= 0 and near or nil
end

local function openPlayer()
    if UI.open then return CloseUI() end
    if Carrying then return OpenUI(Carrying.id) end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return end
    if not cp.enabled then return Notify(NZ.L('carplay_disabled'), 'error') end
    if not NZ.VehicleAllowed(GetEntityModel(veh), GetVehicleClass(veh)) then
        return Notify(NZ.L('blacklisted_vehicle'), 'error')
    end
    if cp.controlBy == 'driver' and GetPedInVehicleSeat(veh, -1) ~= ped then
        local e = Emitters['v' .. NetworkGetNetworkIdFromEntity(veh)]
        if not e then return Notify(NZ.L('not_driver'), 'error') end
    end
    if not NetworkGetEntityIsNetworked(veh) then return end
    local id = NZ.Callback('vehicle:open', NetworkGetNetworkIdFromEntity(veh))
    if not id then return end
    local t = GetGameTimer()
    while not Emitters[id] and GetGameTimer() - t < 2000 do Wait(0) end
    OpenUI(id)
end

RegisterCommand('+nzspk_player', function() CreateThread(openPlayer) end, false)
RegisterCommand('-nzspk_player', function() end, false)
RegisterKeyMapping('+nzspk_player', 'Speaker: open car / boombox player', 'keyboard', cp.key)

---------------------------------------------------------------- unit install / remove
RegisterNetEvent(RES .. ':client:installCarplay', function()
    local veh = vehicleNear()
    if not veh then return Notify(NZ.L('carplay_no_vehicle'), 'error') end
    if Entity(veh).state.nzCarplay then return Notify(NZ.L('carplay_already'), 'error') end
    local a = cp.install.install
    if Bridge.Progress(NZ.L('carplay_installed'), a, a.duration) then
        TriggerServerEvent(RES .. ':carplay:install', NetworkGetNetworkIdFromEntity(veh))
    end
end)

function RemoveCarplayUnit(netId)
    CreateThread(function()
        local a = cp.install.remove
        if Bridge.Progress(NZ.L('carplay_removed'), a, a.duration) then
            TriggerServerEvent(RES .. ':carplay:remove', netId)
        end
    end)
end

---------------------------------------------------------------- GTA radio lock
-- The radio is killed in every vehicle (not only while CarPlay plays) so the two never overlap.
if Config.DisableGTARadio then
    CreateThread(function()
        local current = 0
        while true do
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                if veh ~= current then
                    current = veh
                    SetVehRadioStation(veh, 'OFF')
                    SetVehicleRadioEnabled(veh, false)
                    SetUserRadioControlEnabled(false)
                end
                if GetPlayerRadioStationIndex() ~= 255 then SetVehRadioStation(veh, 'OFF') end
                DisableControlAction(0, 85, true)   -- radio wheel
                DisableControlAction(0, 81, true)   -- next station
                DisableControlAction(0, 82, true)   -- previous station
                HideHudComponentThisFrame(16)       -- radio station name
                Wait(0)
            else
                if current ~= 0 then
                    current = 0
                    SetUserRadioControlEnabled(true)
                end
                Wait(500)
            end
        end
    end)
end
