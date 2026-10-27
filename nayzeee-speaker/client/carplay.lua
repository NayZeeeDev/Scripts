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

local opening = false   -- a car player is being asked for: mashing the key doesn't stack requests

local function openPlayer()
    if UI.open then
        if UI.typing then return end      -- the key was typed into a text box of the car player
        return CloseUI()
    end
    if Carrying then return OpenUI(Carrying.id) end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        -- on foot with nothing in your hands: the jam you are in, if any (client/main.lua)
        local jam = MyJam()
        if jam then OpenUI(jam) end
        return
    end
    if not cp.enabled then return Notify(NZ.L('carplay_disabled'), 'error') end
    if not NZ.VehicleAllowed(GetEntityModel(veh), GetVehicleClass(veh)) then
        return Notify(NZ.L('blacklisted_vehicle'), 'error')
    end
    if not NetworkGetEntityIsNetworked(veh) then return end
    local net = NetworkGetNetworkIdFromEntity(veh)
    -- a passenger may open a player the driver already started, but not start one
    if cp.controlBy == 'driver' and GetPedInVehicleSeat(veh, -1) ~= ped and not Emitters['v' .. net] then
        return Notify(NZ.L('not_driver'), 'error')
    end
    if opening then return end
    opening = true
    local id = NZ.Callback('vehicle:open', net)
    if id then
        -- the snapshot of a new car player is on its way
        local t = GetGameTimer()
        while not Emitters[id] and GetGameTimer() - t < 2000 do Wait(50) end
        OpenUI(id)
    end
    opening = false
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
-- The control / HUD blocks only hold for the frame they are called in, so that part runs every
-- frame in a vehicle; which vehicle you are in and the station are checked four times a second.
if Config.DisableGTARadio then
    local current = 0

    CreateThread(function()
        local checkAt = 0
        while true do
            local t = GetGameTimer()
            if t >= checkAt then
                checkAt = t + 250
                local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                if veh ~= current then
                    current = veh
                    if veh ~= 0 then
                        SetVehRadioStation(veh, 'OFF')
                        SetVehicleRadioEnabled(veh, false)
                    end
                    SetUserRadioControlEnabled(veh == 0)
                elseif veh ~= 0 and GetPlayerRadioStationIndex() ~= 255 then
                    SetVehRadioStation(veh, 'OFF')
                end
            end
            if current ~= 0 then
                DisableControlAction(0, 85, true)   -- radio wheel
                DisableControlAction(0, 81, true)   -- next station
                DisableControlAction(0, 82, true)   -- previous station
                HideHudComponentThisFrame(16)       -- radio station name
                Wait(0)
            else
                Wait(500)
            end
        end
    end)

    AddEventHandler('onResourceStop', function(res)
        if res ~= RES then return end
        SetUserRadioControlEnabled(true)
        if current ~= 0 and DoesEntityExist(current) then SetVehicleRadioEnabled(current, true) end
    end)
end
