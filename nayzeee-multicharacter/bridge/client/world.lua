if not NAYZEEE_LOCK_OK then return end

--[[
    Weather / time sync pause while in character selection so the scene keeps its own weather.
    Add your weather resource here if it is not listed.
]]

World = {}

function World.PauseSync(paused)
    if GetResourceState('qb-weathersync') == 'started' then
        TriggerEvent(paused and 'qb-weathersync:client:DisableSync' or 'qb-weathersync:client:EnableSync')
    end
    if GetResourceState('cd_easytime') == 'started' then
        TriggerEvent('cd_easytime:PauseSync', paused)
    end
    if GetResourceState('vSync') == 'started' then
        TriggerEvent('vSync:toggle', not paused)
    end
    if GetResourceState('Renewed-Weathersync') == 'started' then
        LocalPlayer.state:set('syncWeather', not paused, false)
    end
    if GetResourceState('av_weather') == 'started' then
        TriggerEvent('av_weather:freeze', paused)
    end
end

function World.Apply(weather, hour, minute)
    if weather then
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        SetWeatherTypeNowPersist(weather)
        SetWeatherTypeNow(weather)
        SetOverrideWeather(weather)
        SetForceVehicleTrails(weather == 'XMAS')
        SetForcePedFootstepsTracks(weather == 'XMAS')
    end
    if hour then NetworkOverrideClockTime(hour, minute or 0, 0) end
end

function World.Restore()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetForceVehicleTrails(false)
    SetForcePedFootstepsTracks(false)
    NetworkClearClockTimeOverride()
end
