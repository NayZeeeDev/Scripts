Bridge.OnPlayerLoaded(function()
    TriggerServerEvent('nz_sneakers:server:loaded')
    Wait(Config.Wear.reapplyDelay)
    Shoes.Reapply()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Busy then
        Cam.Stop(true)
        ClearPedTasks(PlayerPedId())
    end
end)
