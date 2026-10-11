--[[
    NAYZEEE WorldControl - Server Actions, Restart Warning, Commands & Exports
    discord.gg/nayzeeedev
]]

-- ══════════════════════════════════════════════════════════════
-- WORLD / TRAFFIC SETTERS
-- ══════════════════════════════════════════════════════════════

function SetWorld(values, src)
    local w, changed = State.world, {}

    if values.blackout ~= nil then w.blackout = values.blackout == true; changed[#changed + 1] = w.blackout and 'blackout ON' or 'blackout OFF' end
    if values.snowOnGround ~= nil then w.snowOnGround = values.snowOnGround == true; changed[#changed + 1] = w.snowOnGround and 'snow on ground ON' or 'snow on ground OFF' end
    if values.wind ~= nil then
        local wind = NWC.Clamp(values.wind, -1, 12)
        if wind then w.wind = wind < 0 and -1 or NWC.Round(wind, 1); changed[#changed + 1] = w.wind < 0 and 'wind auto' or ('wind %.1f'):format(w.wind) end
    end
    if values.windDirection ~= nil then
        local dir = NWC.Clamp(values.windDirection, 0, 359)
        if dir then w.windDirection = math.floor(dir); changed[#changed + 1] = ('wind direction %d°'):format(w.windDirection) end
    end
    if values.rain ~= nil then
        local rain = NWC.Clamp(values.rain, -1, 1)
        if rain then w.rain = rain < 0 and -1 or NWC.Round(rain, 2); changed[#changed + 1] = w.rain < 0 and 'rain auto' or ('rain %d%%'):format(math.floor(w.rain * 100)) end
    end

    if #changed == 0 then return end
    Broadcast({ world = w })
    if src then AddLog(src, 'set ' .. table.concat(changed, ', '), 'mountain-sun') end
    MarkDirty()
end

local function SanitizeDensity(values)
    local out = {}
    for _, key in ipairs(NWC.DensityKeys) do
        local v = values[key] ~= nil and NWC.Clamp(values[key], 0, Config.Traffic.maxDensity) or nil
        out[key] = v and NWC.Round(v, 2) or State.traffic.density[key]
    end
    return out
end

function SetDensity(values, src, label)
    State.traffic.density = SanitizeDensity(values)
    Broadcast({ traffic = State.traffic })
    if src then
        AddLog(src, label or ('set traffic to peds %d%%, vehicles %d%%'):format(
            math.floor(State.traffic.density.pedestrians * 100 + 0.5),
            math.floor(State.traffic.density.vehicles * 100 + 0.5)), 'car')
    end
    MarkDirty()
end

function SetService(key, value, src)
    if State.traffic.services[key] == nil then return end
    State.traffic.services[key] = value == true
    Broadcast({ traffic = State.traffic })
    if src then AddLog(src, ('turned %s %s'):format(key, value and 'ON' or 'OFF'), 'tower-broadcast') end
    MarkDirty()
end

function ApplyTrafficPreset(id, src)
    local preset = NWC.TrafficPresetById[id]
    if not preset then return false end
    SetDensity(preset, src, ('applied traffic preset %s'):format(preset.label))
    return true
end

-- ══════════════════════════════════════════════════════════════
-- RESTART WARNING
-- ══════════════════════════════════════════════════════════════

function StartRestartWarning(minutes, src)
    if not Config.RestartWarning.enabled then return false end
    minutes = NWC.Clamp(minutes or Config.RestartWarning.minutes, 0.5, 60)
    if not minutes then return false end

    local r = State.restart
    r.active = true
    r.duration = math.floor(minutes * 60)
    r.endsAt = os.time() + r.duration

    Broadcast({ restart = RestartPayload() })
    AddLog(src or 0, ('started a %s minute restart warning'):format(NWC.Round(minutes, 1)), 'triangle-exclamation')
    return true
end

function CancelRestartWarning(src)
    if not State.restart.active then return false end
    State.restart.active = false
    State.restart.endsAt = 0

    -- Hand everyone the real world back
    Broadcast({
        restart = RestartPayload(),
        weather = WeatherPayload(false),
        time = TimePayload('smooth'),
        world = State.world,
    })
    ResetWeatherTimer()
    AddLog(src or 0, 'cancelled the restart warning', 'ban')
    return true
end

-- Auto-end once the timer runs out (the server is usually gone by then)
CreateThread(function()
    while true do
        Wait(1000)
        if State.restart.active and os.time() >= State.restart.endsAt + 30 then
            CancelRestartWarning()
        end
    end
end)

if Config.RestartWarning.txAdmin then
    AddEventHandler('txAdmin:events:scheduledRestart', function(eventData)
        local seconds = eventData and tonumber(eventData.secondsRemaining)
        if not seconds or State.restart.active then return end
        if seconds <= Config.RestartWarning.minutes * 60 then
            StartRestartWarning(seconds / 60)
        end
    end)

    AddEventHandler('txAdmin:events:scheduledRestartSkipped', function()
        CancelRestartWarning()
    end)
end

-- ══════════════════════════════════════════════════════════════
-- SCENES
-- ══════════════════════════════════════════════════════════════

function ApplyScene(id, src)
    local scene = NWC.SceneById[id]
    if not scene then return false end

    if scene.weather and NWC.WeatherById[scene.weather] then
        if State.weather.method == 'real' then State.weather.method = 'game'; State.weather.real = nil end
        SetWeather(scene.weather, nil)
    end
    if scene.hour then
        if State.time.method == 'real' then State.time.method = 'game' end
        SetTime(scene.hour, scene.minute or 0, nil)
    end
    SetWorld({
        blackout = scene.blackout,
        snowOnGround = scene.snowOnGround,
        wind = scene.wind,
        rain = scene.rain,
    })
    if scene.traffic then
        local preset = NWC.TrafficPresetById[scene.traffic]
        if preset then SetDensity(preset) end
    end

    AddLog(src, ('applied scene %s'):format(scene.label), scene.icon)
    return true
end

-- ══════════════════════════════════════════════════════════════
-- PANEL ACTIONS (validated, called from the client dispatcher)
-- ══════════════════════════════════════════════════════════════

Actions = {}

Actions.setWeather = function(src, d)
    if State.weather.method == 'real' then
        State.weather.method = 'game'
        State.weather.real = nil
    end
    if not SetWeather(d.weather, d.instant == true or nil, src) then
        NotifyPlayer(src, 'Unknown weather type', 'error')
    end
end

Actions.weatherOptions = function(src, d)
    local w = State.weather
    if d.dynamic ~= nil then
        w.dynamic = d.dynamic == true
        ResetWeatherTimer()
        AddLog(src, w.dynamic and 'enabled dynamic weather' or 'disabled dynamic weather', 'rotate')
    end
    if d.instant ~= nil then
        w.instant = d.instant == true
        AddLog(src, w.instant and 'set weather changes to instant' or 'set weather changes to smooth', 'bolt')
    end
    if d.interval ~= nil then
        local interval = NWC.Clamp(d.interval, 1, 240)
        if interval then
            w.interval = math.floor(interval)
            ResetWeatherTimer()
            AddLog(src, ('set weather interval to %d min'):format(w.interval), 'hourglass-half')
        end
    end
    if d.method == 'game' or d.method == 'real' then
        if d.method == 'real' and (Config.Weather.real.apiKey == '' or Config.Weather.real.apiKey == 'CHANGE_ME') then
            NotifyPlayer(src, 'Real weather needs an OpenWeatherMap API key in config.lua', 'error')
            return
        end
        w.method = d.method
        if d.method == 'real' then
            FetchRealWeather(src)
        else
            w.real = nil
            ResetWeatherTimer()
            RebuildForecast()
        end
        AddLog(src, ('switched weather to %s weather'):format(d.method == 'real' and 'real-world' or 'game'), 'earth-americas')
    end
end

Actions.skipWeather = function(src)
    if State.weather.method ~= 'game' then return end
    AdvanceWeather(src)
end

Actions.rerollForecast = function(src)
    if State.weather.method ~= 'game' then return end
    RebuildForecast()
    AddLog(src, 'rerolled the forecast', 'dice')
end

Actions.setTime = function(src, d)
    SetTime(d.hour, d.minute, d.instant == true or nil, src)
end

Actions.timeOptions = function(src, d)
    if d.frozen ~= nil then SetFrozen(d.frozen == true, src) end
    if d.msPerMinute ~= nil then SetTimeSpeed(d.msPerMinute, src) end
    if d.method ~= nil then SetTimeMethod(d.method, src) end
    if d.instant ~= nil then
        State.time.instant = d.instant == true
        AddLog(src, State.time.instant and 'set time changes to instant' or 'set time changes to smooth', 'bolt')
    end
end

Actions.setWorld = function(src, d)
    SetWorld(d, src)
end

Actions.setDensity = function(src, d)
    local values = NWC.Copy(State.traffic.density)
    if type(d.values) == 'table' then
        for _, key in ipairs(NWC.DensityKeys) do
            if d.values[key] ~= nil then values[key] = d.values[key] end
        end
    elseif d.key then
        values[d.key] = d.value
    end
    SetDensity(values, src)
end

Actions.trafficPreset = function(src, d)
    if not ApplyTrafficPreset(d.id, src) then
        NotifyPlayer(src, 'Unknown preset', 'error')
    end
end

Actions.resetTraffic = function(src)
    SetDensity(Config.Traffic.defaults, src, 'reset traffic to defaults')
    State.traffic.services = NWC.Copy(Config.Traffic.services)
    Broadcast({ traffic = State.traffic })
end

Actions.setService = function(src, d)
    SetService(d.key, d.value == true, src)
end

Actions.purge = function(src)
    TriggerClientEvent(EV .. 'purge', -1)
    AddLog(src, 'cleared ambient peds & vehicles', 'broom')
end

Actions.scene = function(src, d)
    if not ApplyScene(d.id, src) then
        NotifyPlayer(src, 'Unknown scene', 'error')
    end
end

Actions.lightning = function(src)
    TriggerClientEvent(EV .. 'lightning', -1)
    AddLog(src, 'called down lightning', 'bolt-lightning')
end

Actions.restartStart = function(src, d)
    if State.restart.active then
        NotifyPlayer(src, 'A restart warning is already running', 'error')
        return
    end
    StartRestartWarning(d.minutes, src)
end

Actions.restartCancel = function(src)
    CancelRestartWarning(src)
end

-- ══════════════════════════════════════════════════════════════
-- QUICK COMMANDS
-- ══════════════════════════════════════════════════════════════

local function AddSuggestions(src)
    local qc = Config.QuickCommands
    local list = {}
    if qc.weather then list[#list + 1] = { name = '/' .. qc.weather, help = 'Set the weather', params = { { name = 'type', help = 'e.g. RAIN, THUNDER, XMAS' }, { name = 'instant', help = 'optional: instant' } } } end
    if qc.time then list[#list + 1] = { name = '/' .. qc.time, help = 'Set the time', params = { { name = 'hour', help = '0-23' }, { name = 'minute', help = '0-59' } } } end
    if qc.freeze then list[#list + 1] = { name = '/' .. qc.freeze, help = 'Freeze / unfreeze time' } end
    if qc.blackout then list[#list + 1] = { name = '/' .. qc.blackout, help = 'Toggle city blackout' } end
    if qc.restart then list[#list + 1] = { name = '/' .. qc.restart, help = 'Start or cancel the restart warning', params = { { name = 'minutes', help = 'minutes, or "cancel"' } } } end
    TriggerClientEvent('chat:addSuggestions', src, list)
end

RegisterNetEvent(EV .. 'requestSuggestions', function()
    local src = source
    if HasPermission(src) then AddSuggestions(src) end
end)

local function Guarded(fn)
    return function(src, args)
        if not HasPermission(src) then
            NotifyPlayer(src, 'You do not have permission to use this command', 'error')
            return
        end
        fn(src, args)
        RefreshAdmins()
    end
end

local qc = Config.QuickCommands

if qc.weather then
    RegisterCommand(qc.weather, Guarded(function(src, args)
        local weather = args[1] and args[1]:upper()
        if not weather or not NWC.WeatherById[weather] then
            local ids = {}
            for _, w in ipairs(Config.WeatherTypes) do ids[#ids + 1] = w.id end
            NotifyPlayer(src, 'Weather types: ' .. table.concat(ids, ', '), 'error')
            return
        end
        Actions.setWeather(src, { weather = weather, instant = args[2] == 'instant' })
        NotifyPlayer(src, ('Weather set to %s'):format(NWC.WeatherById[weather].label), 'success')
    end), false)
end

if qc.time then
    RegisterCommand(qc.time, Guarded(function(src, args)
        local h, m = tonumber(args[1]), tonumber(args[2] or 0)
        if not h or h < 0 or h > 23 or not m or m < 0 or m > 59 then
            NotifyPlayer(src, ('Usage: /%s [0-23] [0-59]'):format(qc.time), 'error')
            return
        end
        if SetTime(h, m, nil, src) then
            NotifyPlayer(src, ('Time set to %02d:%02d'):format(h, m), 'success')
        end
    end), false)
end

if qc.freeze then
    RegisterCommand(qc.freeze, Guarded(function(src)
        SetFrozen(not State.time.frozen, src)
        NotifyPlayer(src, State.time.frozen and 'Time frozen' or 'Time unfrozen', 'success')
    end), false)
end

if qc.blackout then
    RegisterCommand(qc.blackout, Guarded(function(src)
        SetWorld({ blackout = not State.world.blackout }, src)
        NotifyPlayer(src, State.world.blackout and 'Blackout enabled' or 'Blackout disabled', 'success')
    end), false)
end

if qc.restart then
    RegisterCommand(qc.restart, Guarded(function(src, args)
        if args[1] == 'cancel' or args[1] == 'stop' then
            if CancelRestartWarning(src) then NotifyPlayer(src, 'Restart warning cancelled', 'success') end
            return
        end
        if State.restart.active then
            NotifyPlayer(src, 'A restart warning is already running', 'error')
            return
        end
        if StartRestartWarning(tonumber(args[1]), src) then
            NotifyPlayer(src, 'Restart warning started', 'success')
        end
    end), false)
end

-- ══════════════════════════════════════════════════════════════
-- EXPORTS
-- ══════════════════════════════════════════════════════════════

exports('GetState', function() return BuildAdminData() end)
exports('GetWeather', function() return State.weather.current end)
exports('SetWeather', function(weather, instant) local ok = SetWeather(weather, instant, 0); RefreshAdmins(); return ok end)
exports('GetTime', function() local t = TimePayload(); return t.hour, t.minute, t.second end)
exports('SetTime', function(hour, minute, instant) local ok = SetTime(hour, minute, instant, 0); RefreshAdmins(); return ok end)
exports('FreezeTime', function(frozen) SetFrozen(frozen, 0); RefreshAdmins() end)
exports('SetTimeSpeed', function(msPerMinute) SetTimeSpeed(msPerMinute, 0); RefreshAdmins() end)
exports('SetBlackout', function(enabled) SetWorld({ blackout = enabled == true }, 0); RefreshAdmins() end)
exports('SetWorld', function(values) SetWorld(values or {}, 0); RefreshAdmins() end)
exports('GetDensity', function() return NWC.Copy(State.traffic.density) end)
exports('SetDensity', function(values) SetDensity(values or {}, 0); RefreshAdmins() end)
exports('ApplyTrafficPreset', function(id) local ok = ApplyTrafficPreset(id, 0); RefreshAdmins(); return ok end)
exports('SetService', function(key, value) SetService(key, value, 0); RefreshAdmins() end)
exports('ApplyScene', function(id) local ok = ApplyScene(id, 0); RefreshAdmins(); return ok end)
exports('StartRestartWarning', function(minutes) local ok = StartRestartWarning(minutes, 0); RefreshAdmins(); return ok end)
exports('CancelRestartWarning', function() local ok = CancelRestartWarning(0); RefreshAdmins(); return ok end)

-- Legacy nayzeee-traffic exports
exports('GetServerSettings', function() return NWC.Copy(State.traffic.density) end)
exports('SetServerSettings', function(values) SetDensity(values or {}, 0); RefreshAdmins() end)
