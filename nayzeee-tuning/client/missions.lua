--[[ Roadside callouts taken from the business menu. Everything spawned is local to the mechanic. ]]

Missions = { active = nil }

local function cleanup(keepCar)
    local m = Missions.active
    if not m then return end
    if m.blip and DoesBlipExist(m.blip) then RemoveBlip(m.blip) end
    Bridge.TextUI(false)
    if not keepCar then
        if m.ped and DoesEntityExist(m.ped) then DeleteEntity(m.ped) end
        if m.veh and DoesEntityExist(m.veh) then DeleteEntity(m.veh) end
    end
    Missions.active = nil
end

local function spawn(c)
    local vm, pm = joaat(c.vehicle), joaat(c.ped)
    if not lib.requestModel(vm, 5000) or not lib.requestModel(pm, 5000) then return nil end
    local veh = CreateVehicle(vm, c.coords.x, c.coords.y, c.coords.z, c.coords.w, false, false)
    SetVehicleOnGroundProperly(veh)
    SetVehicleDoorsLocked(veh, 2)
    SetEntityAsMissionEntity(veh, true, true)
    local fault = c.fault
    if fault == 'overheat' then SetVehicleEngineHealth(veh, 180.0) SetVehicleDoorOpen(veh, 4, false, false)
    elseif fault == 'tyre' then SetVehicleTyreBurst(veh, 0, true, 1000.0)
    elseif fault == 'battery' or fault == 'starter' then SetVehicleDoorOpen(veh, 4, false, false) SetVehicleEngineOn(veh, false, true, true)
    elseif fault == 'fuel' then SetVehicleFuelLevel(veh, 0.0) end
    SetVehicleIndicatorLights(veh, 0, true)
    SetVehicleIndicatorLights(veh, 1, true)

    local off = GetOffsetFromEntityInWorldCoords(veh, -2.2, 1.0, 0.0)
    local ped = CreatePed(4, pm, off.x, off.y, off.z, c.coords.w + 90.0, false, false)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    if lib.requestAnimDict('random@domestic', 2000) then
        TaskPlayAnim(ped, 'random@domestic', 'f_distressed_loop', 8.0, -8.0, -1, 1, 0, false, false, false)
    end
    SetModelAsNoLongerNeeded(vm)
    SetModelAsNoLongerNeeded(pm)
    return veh, ped
end

function Missions.Start(c)
    if c.kind == 'tow' then return Tow.Start(c) end
    if Missions.active or (Tow and Tow.active) then return Notify(L('callout_busy'), 'error') end
    local blip = AddBlipForCoord(c.coords.x, c.coords.y, c.coords.z)
    SetBlipSprite(blip, 446)
    SetBlipColour(blip, 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('callout_blip', c.faultLabel))
    EndTextCommandSetBlipName(blip)
    Missions.active = { data = c, blip = blip, stage = 'drive' }
    Notify(L('callout_started', c.faultLabel), 'inform')

    CreateThread(function()
        local target = vec3(c.coords.x, c.coords.y, c.coords.z)
        -- wait until close enough to spawn
        while Missions.active and #(GetEntityCoords(cache.ped) - target) > 120.0 do Wait(1000) end
        if not Missions.active then return end
        local veh, ped = spawn(c)
        if not veh then Notify(L('failed'), 'error') return cleanup() end
        Missions.active.veh, Missions.active.ped = veh, ped

        local shown
        while Missions.active do
            local m = Missions.active
            local me = GetEntityCoords(cache.ped)
            local sleep = 500
            if m.stage == 'drive' or m.stage == 'fix' then
                local spot = VehUtil.BoneCoords(veh, c.fault == 'tyre' and { 'wheel_lf' } or { 'engine', 'bonnet', 'bumper_f' })
                local d = #(me - spot)
                if d < 25.0 then sleep = 0 m.stage = 'fix' end
                if d < 1.8 and not cache.vehicle then
                    if shown ~= 'fix' then Bridge.TextUI(L('prompt_fix', c.faultLabel)) shown = 'fix' end
                    if IsControlJustPressed(0, Config.Keys.Interact) then
                        Bridge.TextUI(false) shown = nil
                        TaskTurnPedToFaceCoord(cache.ped, spot.x, spot.y, spot.z, 700)
                        Wait(700)
                        if Bridge.SkillCheck() and Bridge.Progress(L('fixing', c.faultLabel), Config.Missions.RepairTime,
                            c.fault == 'tyre' and { 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer', 1 } or { 'mini@repair', 'fixing_a_ped', 1 }) then
                            SetVehicleFixed(veh)
                            SetVehicleEngineHealth(veh, 1000.0)
                            SetVehicleFuelLevel(veh, 60.0)
                            SetVehicleDoorsShut(veh, false)
                            SetVehicleIndicatorLights(veh, 0, false)
                            SetVehicleIndicatorLights(veh, 1, false)
                            m.stage = 'pay'
                            Notify(L('callout_fixed'), 'success')
                        end
                    end
                elseif shown == 'fix' then Bridge.TextUI(false) shown = nil end
            elseif m.stage == 'pay' then
                sleep = 0
                local pc = GetEntityCoords(ped)
                DrawMarker(20, pc.x, pc.y, pc.z + 1.15, 0, 0, 0, 180.0, 0, 0, 0.25, 0.25, 0.25, 8, 175, 162, 200, true, true, 2, false, nil, nil, false)
                if #(me - pc) < 2.0 then
                    if shown ~= 'pay' then Bridge.TextUI(L('prompt_collect')) shown = 'pay' end
                    if IsControlJustPressed(0, Config.Keys.Interact) then
                        Bridge.TextUI(false) shown = nil
                        local ok, res = lib.callback.await('nayzeee-tuning:finishCallout', false, c.id)
                        if ok then
                            Notify(L('callout_paid', res.paid), 'success')
                            ClearPedTasks(ped)
                            SetVehicleDoorsLocked(veh, 1)
                            TaskEnterVehicle(ped, veh, 8000, -1, 1.0, 1, 0)
                            local v, p = veh, ped
                            SetTimeout(9000, function()
                                if DoesEntityExist(p) and DoesEntityExist(v) then TaskVehicleDriveWander(p, v, 18.0, 786603) end
                                SetTimeout(20000, function()
                                    if DoesEntityExist(p) then DeleteEntity(p) end
                                    if DoesEntityExist(v) then DeleteEntity(v) end
                                end)
                            end)
                            cleanup(true)
                        else
                            Notify(res or L('failed'), 'error')
                        end
                    end
                elseif shown == 'pay' then Bridge.TextUI(false) shown = nil end
            end
            Wait(sleep)
        end
    end)
end

RegisterCommand('cancelcallout', function()
    if not Missions.active and not Tow.active then return end
    lib.callback.await('nayzeee-tuning:abandonCallout', false)
    if Tow.active then Tow.Cleanup(true) end
    cleanup()
    Notify(L('callout_cancelled'), 'inform')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then cleanup() end
end)
