--[[
    NAYZEEE WorldControl - Client
    0.00ms idle: no per-frame loops unless something actually needs one
    discord.gg/nayzeeedev
]]

EV = 'nayzeee-worldcontrol:'

-- Last state received from the server
Current = {
    weather = nil,
    time = nil,
    world = nil,
    traffic = nil,
    restart = nil,
}

local isMenuOpen = false
local staticSent = false

-- ══════════════════════════════════════════════════════════════
-- NOTIFICATIONS
-- ══════════════════════════════════════════════════════════════

function Notify(message, kind)
    kind = kind or 'info'
    local mode = Config.Notify
    if mode == 'auto' then
        mode = GetResourceState('ox_lib') == 'started' and 'ox_lib' or 'nui'
    end

    if mode == 'ox_lib' then
        TriggerEvent('ox_lib:notify', {
            title = 'World Control',
            description = message,
            type = kind == 'info' and 'inform' or kind,
        })
    elseif mode == 'qb' then
        TriggerEvent('QBCore:Notify', message, kind == 'info' and 'primary' or kind)
    elseif mode == 'esx' then
        TriggerEvent('esx:showNotification', message)
    elseif mode == 'chat' then
        TriggerEvent('chat:addMessage', { args = { '^3World Control', message } })
    else
        SendNUIMessage({ action = 'toast', message = message, kind = kind })
    end
end

RegisterNetEvent(EV .. 'notify', function(message, kind)
    Notify(message, kind)
end)

-- ══════════════════════════════════════════════════════════════
-- SYNC (partial state updates from the server)
-- ══════════════════════════════════════════════════════════════

RegisterNetEvent(EV .. 'sync', function(data)
    if type(data) ~= 'table' then return end

    if data.traffic then Traffic.Apply(data.traffic) end
    if data.world then World.ApplyWorld(data.world) end
    if data.weather then World.ApplyWeather(data.weather) end
    if data.time then World.ApplyTime(data.time) end
    if data.restart then World.ApplyRestart(data.restart) end
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    TriggerServerEvent(EV .. 'requestState')
    TriggerServerEvent(EV .. 'requestSuggestions')
end)

-- ══════════════════════════════════════════════════════════════
-- PANEL
-- ══════════════════════════════════════════════════════════════

local function BuildStatic()
    local build = GetGameBuildNumber()
    local weatherTypes = {}
    for _, w in ipairs(Config.WeatherTypes) do
        if not w.build or build >= w.build then
            weatherTypes[#weatherTypes + 1] = { id = w.id, label = w.label, icon = w.icon }
        end
    end

    local services = {}
    for _, key in ipairs(NWC.ServiceKeys) do services[#services + 1] = key end

    return {
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '2.0.0',
        weatherTypes = weatherTypes,
        presets = Config.TrafficPresets,
        scenes = Config.Scenes,
        quickTimes = Config.Time.quick,
        services = services,
        maxDensity = Config.Traffic.maxDensity,
        restartMinutes = Config.RestartWarning.minutes,
        restartEnabled = Config.RestartWarning.enabled,
        densityMode = Config.Performance.densityMode,
    }
end

function OpenMenu()
    if isMenuOpen then return end
    TriggerServerEvent(EV .. 'requestOpen') -- server checks permission, then replies with 'open'
end

function CloseMenu()
    if not isMenuOpen then return end
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerServerEvent(EV .. 'closed')
end

RegisterNetEvent(EV .. 'open', function(adminData)
    isMenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        static = not staticSent and BuildStatic() or nil,
        data = adminData,
    })
    staticSent = true
end)

RegisterNetEvent(EV .. 'adminData', function(adminData)
    if not isMenuOpen then return end
    SendNUIMessage({ action = 'adminData', data = adminData })
end)

RegisterNUICallback('close', function(_, cb)
    CloseMenu()
    cb('ok')
end)

RegisterNUICallback('action', function(data, cb)
    if type(data) == 'table' and type(data.name) == 'string' then
        TriggerServerEvent(EV .. 'action', data.name, data.data or {})
    end
    cb('ok')
end)

-- ══════════════════════════════════════════════════════════════
-- COMMANDS & KEYBIND
-- ══════════════════════════════════════════════════════════════

local function ToggleMenu()
    if isMenuOpen then CloseMenu() else OpenMenu() end
end

RegisterCommand(Config.Command, ToggleMenu, false)
TriggerEvent('chat:addSuggestion', '/' .. Config.Command, 'Open the NAYZEEE World Control panel')

for _, alias in ipairs(Config.CommandAliases or {}) do
    RegisterCommand(alias, ToggleMenu, false)
end

if Config.Keybind then
    RegisterKeyMapping(Config.Command, 'World Control Panel', 'keyboard', Config.Keybind)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isMenuOpen then SetNuiFocus(false, false) end
    World.Cleanup()
    Traffic.Cleanup()
end)

-- ══════════════════════════════════════════════════════════════
-- EXPORTS
-- ══════════════════════════════════════════════════════════════

exports('OpenMenu', OpenMenu)
exports('CloseMenu', CloseMenu)
exports('GetWeather', function() return Current.weather and Current.weather.current end)
exports('GetTime', function() return GetClockHours(), GetClockMinutes(), GetClockSeconds() end)
exports('GetDensity', function() return Current.traffic and NWC.Copy(Current.traffic.density) end)
exports('GetState', function() return NWC.Copy(Current) end)
exports('PauseSync', function(paused, hour) World.SetPaused(paused, hour) end)
exports('IsSyncPaused', function() return World.IsPaused() end)
exports('GetPauseSyncState', function() return World.IsPaused() end) -- cd_easytime compatible

-- Legacy nayzeee-traffic export: local-only override until the next server sync
exports('SetDensity', function(key, value)
    if not Current.traffic then return end
    local traffic = NWC.Copy(Current.traffic)
    traffic.density[key] = tonumber(value) or traffic.density[key]
    Traffic.Apply(traffic)
end)
