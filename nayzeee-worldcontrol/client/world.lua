--[[
    NAYZEEE WorldControl - Client World (weather, time, atmosphere, restart warning)
    discord.gg/nayzeeedev
]]

World = {}

local paused = false
local restartActive = false
local timeTransitioning = false
local transitionId = 0
local targetWeather = nil

local SNOW_WEATHERS = { XMAS = true, SNOW_HALLOWEEN = true }

-- Synced wind when the panel is on "Auto" (keeps every client identical)
local WEATHER_WIND = {
    EXTRASUNNY = 0.5, CLEAR = 1.0, CLOUDS = 2.0, OVERCAST = 3.0, CLEARING = 3.0,
    RAIN = 5.0, THUNDER = 9.0, SMOG = 0.5, FOGGY = 0.5, SNOWLIGHT = 3.0, SNOW = 5.0,
    BLIZZARD = 12.0, XMAS = 3.0, HALLOWEEN = 6.0, NEUTRAL = 1.0, RAIN_HALLOWEEN = 8.0, SNOW_HALLOWEEN = 6.0,
}

local FROZEN_MS_PER_MINUTE = 86400000 -- one game minute per real day = effectively stopped

-- ══════════════════════════════════════════════════════════════
-- LOW LEVEL
-- ══════════════════════════════════════════════════════════════

local function SetBlackoutState(enabled)
    if GetGameBuildNumber() >= 2372 then
        SetArtificialLightsState(enabled)
        SetArtificialLightsStateAffectsVehicles(enabled and Config.World.blackoutAffectsVehicles or false)
    else
        SetBlackout(enabled)
    end
end

local function ApplyAtmosphere()
    local w = Current.world
    local weather = targetWeather or (Current.weather and Current.weather.current) or 'CLEAR'
    if not w then return end

    -- Rain: -1 hands control back to the weather type
    SetRainLevel(w.rain >= 0 and w.rain + 0.0 or -1.0)

    -- Wind
    local wind = (w.wind >= 0 and w.wind or WEATHER_WIND[weather] or 1.0) + 0.0
    if restartActive then wind = 12.0 end
    SetWindSpeed(wind)
    SetWindDirection(math.rad(w.windDirection or 0) + 0.0)

    -- Snow on the ground + tracks
    local snowy = w.snowOnGround or SNOW_WEATHERS[weather] == true
    SetForceVehicleTrails(snowy)
    SetForcePedFootstepsTracks(snowy)
    ForceSnowPass(w.snowOnGround == true)
end

local function SetWeatherNow(weather, instant, seconds)
    targetWeather = weather
    ClearOverrideWeather()
    ClearWeatherTypePersist()

    if instant then
        SetWeatherTypeNow(weather)
        SetWeatherTypeNowPersist(weather)
        SetWeatherTypePersist(weather)
    else
        SetWeatherTypeOvertimePersist(weather, (seconds or Config.Weather.transitionTime) + 0.0)
    end

    ApplyAtmosphere()
end

local function ClockSeconds()
    return GetClockHours() * 3600 + GetClockMinutes() * 60 + GetClockSeconds()
end

local function SetClockSpeed(t)
    NetworkOverrideClockMillisecondsPerGameMinute((t.frozen or paused) and FROZEN_MS_PER_MINUTE or t.msPerMinute)
    PauseClock((t.frozen or paused) == true)
end

-- Smoothly roll the clock forward to the target (only loop that runs per-frame, and only during the roll)
local function RollClockTo(target)
    transitionId = transitionId + 1
    local myId = transitionId
    timeTransitioning = true

    CreateThread(function()
        local from = ClockSeconds()
        local diff = (target - from) % 86400
        local duration = Config.Time.transitionTime
        local started = GetGameTimer()

        while myId == transitionId do
            local progress = (GetGameTimer() - started) / duration
            if progress >= 1.0 then break end
            -- ease-in-out so the sky doesn't snap
            local eased = progress < 0.5 and 2 * progress * progress or 1 - ((-2 * progress + 2) ^ 2) / 2
            local secs = math.floor(from + diff * eased) % 86400
            NetworkOverrideClockTime(secs // 3600, (secs % 3600) // 60, secs % 60)
            Wait(0)
        end

        if myId == transitionId then
            -- land on the server's *current* time (it kept ticking during the roll)
            local t = Current.time
            local final = (target + ((GetGameTimer() - started) / ((t and t.frozen) and FROZEN_MS_PER_MINUTE or (t and t.msPerMinute or 2000))) * 60) % 86400
            final = math.floor(final)
            NetworkOverrideClockTime(final // 3600, (final % 3600) // 60, final % 60)
            timeTransitioning = false
        end
    end)
end

-- ══════════════════════════════════════════════════════════════
-- APPLY FROM SERVER
-- ══════════════════════════════════════════════════════════════

function World.ApplyWeather(payload)
    Current.weather = payload
    if paused or restartActive then return end
    SetWeatherNow(payload.current, payload.instant, payload.transitionTime)
end

function World.ApplyWorld(world)
    local wasBlackout = Current.world and Current.world.blackout
    Current.world = world
    if paused then return end

    if not restartActive and world.blackout ~= wasBlackout then
        SetBlackoutState(world.blackout)
    end
    ApplyAtmosphere()
end

function World.ApplyTime(t)
    Current.time = t
    if paused then return end

    SetClockSpeed(t)
    local target = t.hour * 3600 + t.minute * 60 + (t.second or 0)

    if t.snap == 'smooth' then
        RollClockTo(target)
    elseif t.snap == 'instant' then
        transitionId = transitionId + 1
        timeTransitioning = false
        NetworkOverrideClockTime(t.hour, t.minute, t.second or 0)
    elseif not timeTransitioning then
        -- 'drift' heartbeat: only touch the clock if we've wandered off
        local diff = math.abs((target - ClockSeconds() + 43200) % 86400 - 43200)
        if diff > (t.frozen and 0 or 90) then
            NetworkOverrideClockTime(t.hour, t.minute, t.second or 0)
        end
    end
end

-- ══════════════════════════════════════════════════════════════
-- RESTART WARNING (storm -> blackout + siren)
-- ══════════════════════════════════════════════════════════════

local function StormWeather()
    if GetGameBuildNumber() >= 3258 then return 'RAIN_HALLOWEEN' end
    return Config.RestartWarning.weather
end

function World.ApplyRestart(r)
    Current.restart = r

    if r.active and not restartActive then
        restartActive = true
        local received = GetGameTimer()
        local duration = math.max(r.duration, 1)
        local startElapsed = duration - r.remaining

        SendNUIMessage({
            action = 'restart',
            active = true,
            remaining = r.remaining,
            title = Config.RestartWarning.title,
            message = Config.RestartWarning.message,
        })

        if not paused then
            SetWeatherNow(StormWeather(), false, math.max(10.0, r.remaining * 0.25))
        end

        CreateThread(function()
            local blackedOut = false
            while restartActive do
                local elapsed = startElapsed + (GetGameTimer() - received) / 1000
                if not blackedOut and elapsed / duration >= Config.RestartWarning.blackoutAt then
                    blackedOut = true
                    if not paused then SetBlackoutState(true) end
                    if Config.RestartWarning.siren then
                        SendNUIMessage({ action = 'siren', play = true, volume = Config.RestartWarning.sirenVolume })
                    end
                end
                Wait(1000)
            end
        end)

    elseif not r.active and restartActive then
        restartActive = false
        SendNUIMessage({ action = 'restart', active = false })
        SendNUIMessage({ action = 'siren', play = false })
        if not paused then
            SetBlackoutState(Current.world and Current.world.blackout or false)
            if Current.weather then SetWeatherNow(Current.weather.current, false, 30.0) end
        end
    end
end

RegisterNetEvent(EV .. 'lightning', function()
    if not paused then ForceLightningFlash() end
end)

-- ══════════════════════════════════════════════════════════════
-- PAUSE SYNC (interiors / housing / other scripts)
-- ══════════════════════════════════════════════════════════════

function World.IsPaused() return paused end

function World.SetPaused(state, hour)
    state = state == true
    if state == paused then return end
    paused = state

    if paused then
        transitionId = transitionId + 1
        timeTransitioning = false
        SetWeatherNow(Config.Compat.pausedWeather, true)
        targetWeather = nil -- watchdog leaves paused weather alone
        SetBlackoutState(false)
        NetworkOverrideClockTime(hour or Config.Compat.pausedHour, 0, 0)
        SetClockSpeed({ frozen = true })
    else
        -- Re-apply the live server state instantly
        if Current.time then
            SetClockSpeed(Current.time)
            TriggerServerEvent(EV .. 'requestState')
        end
        if Current.world then SetBlackoutState(Current.world.blackout or restartActive) end
        if Current.weather then SetWeatherNow(restartActive and StormWeather() or Current.weather.current, true) end
    end
end

if Config.Compat.pauseEvents then
    RegisterNetEvent('qb-weathersync:client:DisableSync', function() World.SetPaused(true) end)
    RegisterNetEvent('qb-weathersync:client:EnableSync', function() World.SetPaused(false) end)
    RegisterNetEvent('vSync:toggle', function(disable) World.SetPaused(disable == true) end)
    RegisterNetEvent('cd_easytime:PauseSync', function(state, hour) World.SetPaused(state == true, hour) end)
    RegisterNetEvent('nayzeee-worldcontrol:PauseSync', function(state, hour) World.SetPaused(state == true, hour) end)
end

-- ══════════════════════════════════════════════════════════════
-- WATCHDOG (cheap: one check every few seconds)
-- Keeps weather/rain correct if the game or another script drifts it.
-- ══════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(Config.Performance.watchdogInterval)
        if not paused and targetWeather then
            if not IsNextWeatherType(targetWeather) then
                SetWeatherNow(targetWeather, false, 15.0)
            elseif Current.world and Current.world.rain >= 0 then
                SetRainLevel(Current.world.rain + 0.0)
            end
        end
    end
end)

function World.Cleanup()
    transitionId = transitionId + 1
    restartActive = false
    SetBlackoutState(false)
    SetForceVehicleTrails(false)
    SetForcePedFootstepsTracks(false)
    ForceSnowPass(false)
    PauseClock(false)
    SetRainLevel(-1.0)
end
