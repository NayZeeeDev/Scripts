--[[ Drive the unpaid build for a short time, then return to the bay with the cart intact. ]]

TestDrive = { active = false }

function TestDrive.Start(veh, bay, heading, onEnd)
    if TestDrive.active then return end
    TestDrive.active = true
    TriggerServerEvent('nayzeee-tuning:testDrive', VehToNet(veh), true)
    Notify(L('testdrive_start', Config.TestDrive.Duration), 'inform')

    CreateThread(function()
        local endsAt = GetGameTimer() + Config.TestDrive.Duration * 1000
        local reason
        while true do
            local left = math.max(0, math.floor((endsAt - GetGameTimer()) / 1000))
            local dist = #(GetEntityCoords(veh) - bay)
            UI.Send('hud:testdrive', { show = true, left = left, dist = math.floor(dist), radius = math.floor(Config.TestDrive.Radius) })
            if left <= 0 then reason = L('testdrive_time') break end
            if dist > Config.TestDrive.Radius then reason = L('testdrive_radius') break end
            if not DoesEntityExist(veh) or cache.vehicle ~= veh then reason = L('testdrive_left') break end
            if IsEntityDead(cache.ped) then reason = L('testdrive_left') break end
            Wait(250)
        end
        UI.Send('hud:testdrive', { show = false })

        DoScreenFadeOut(500)
        Wait(600)
        if DoesEntityExist(veh) then
            SetEntityCoords(veh, bay.x, bay.y, bay.z, false, false, false, false)
            SetEntityHeading(veh, heading)
            SetVehicleForwardSpeed(veh, 0.0)
            SetVehicleOnGroundProperly(veh)
            if cache.vehicle ~= veh and not IsEntityDead(cache.ped) then TaskWarpPedIntoVehicle(cache.ped, veh, -1) Wait(300) end
        end
        TriggerServerEvent('nayzeee-tuning:testDrive', VehToNet(veh), false)
        TestDrive.active = false
        Notify(reason, 'inform')
        Wait(250)
        DoScreenFadeIn(500)
        onEnd()
    end)
end
