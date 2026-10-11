local KVP = 'nhud:settings'
local settingsOpen = false

local function applyLuaSettings(s)
    if type(s) ~= 'table' then return end
    if type(s.map) == 'table' and s.map.mode then
        NHUD.settings.minimap = s.map.mode
    end
    -- status under the minimap: lift the radar so the row fits beneath it
    local under = type(s.status) == 'table' and s.status.place ~= 'side' and s.status.enabled ~= false
    local shape = type(s.map) == 'table' and s.map.shape or Config.Minimap.shape
    NHUD.setMinimapLayout(shape, under and Config.Minimap.raiseForStatus or 0.0)
    NHUD.updateRadar(nil, true)
    NHUD.flush()
end

local function loadSettings()
    local raw = GetResourceKvpString(KVP)
    if not raw or raw == '' then return false end
    local ok, data = pcall(json.decode, raw)
    return ok and type(data) == 'table' and data or false
end

local function keyList()
    local k = Config.Keys
    local list = {
        { label = 'HUD settings', key = '/' .. Config.Commands.settings },
        { label = 'Toggle HUD', key = '/' .. Config.Commands.toggle },
        { label = 'Vehicle control panel', key = k.vehicleMenu ~= '' and k.vehicleMenu or ('/' .. Config.Commands.vehicleMenu) },
        { label = 'Left indicator', key = k.indicatorLeft },
        { label = 'Right indicator', key = k.indicatorRight },
        { label = 'Hazard lights', key = k.hazard },
    }
    if NHUD.builtinBelt then table.insert(list, 3, { label = 'Seatbelt', key = k.seatbelt }) end
    if Config.Cruise.enabled then table.insert(list, 4, { label = 'Cruise / limiter', key = k.cruise }) end
    return list
end

RegisterNUICallback('ready', function(_, cb)
    NHUD.ready = true
    local saved = loadSettings()
    applyLuaSettings(saved or { status = { place = 'under' }, map = { shape = Config.Minimap.shape } })
    NHUD.send('init', {
        settings = saved,
        defaults = Config.Defaults,
        watermark = Config.Watermark,
        weaponImages = Config.WeaponImages,
        belt = NHUD.builtinBelt,
        keys = keyList(),
        framework = HudBridge.framework,
        squads = SquadsConfig ~= nil and SquadsConfig.Enabled == true,
        stressNotify = Config.Stress.enabled and Config.Stress.notify,
    })
    NHUD.sendMap(true)
    NHUD.resend()
    NHUD.send('vis', { v = NHUD.visible and HudBridge.loaded })
    if Config.Discord.enabled then TriggerServerEvent('nhud:server:avatar') end
    cb('ok')
end)

RegisterNUICallback('save', function(data, cb)
    if type(data) == 'table' then
        SetResourceKvp(KVP, json.encode(data))
        applyLuaSettings(data)
    end
    cb('ok')
end)

RegisterNUICallback('preview', function(data, cb)
    applyLuaSettings(data)
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    if NHUD.isPanelOpen() then
        NHUD.closePanel()
    else
        settingsOpen = false
        NHUD.focus = false
        SetNuiFocus(false, false)
    end
    cb('ok')
end)

RegisterNUICallback('vehAction', function(data, cb)
    cb(NHUD.vehicleAction(data.a, data.i) or false)
end)

local function openSettings()
    if settingsOpen or NHUD.focus or MenuOpen then return end
    settingsOpen = true
    NHUD.focus = true
    SetNuiFocus(true, true)
    NHUD.send('settings', { open = true })
end

local function setVisible(state)
    NHUD.visible = state
    NHUD.send('vis', { v = state and HudBridge.loaded })
    NHUD.updateRadar(nil, true)
    NHUD.flush()
end

-- framework login / logout
function NHUD.setLoaded(state)
    if not NHUD.ready then return end
    setVisible(NHUD.visible)
end

RegisterCommand(Config.Commands.settings, openSettings, false)
RegisterCommand(Config.Commands.toggle, function() setVisible(not NHUD.visible) end, false)

TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.settings, 'Open HUD settings')
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.toggle, 'Show / hide the HUD')

exports('OpenSettings', openSettings)
exports('ToggleHud', function(state)
    if state == nil then state = not NHUD.visible end
    setVisible(state)
end)
exports('IsHudVisible', function() return NHUD.visible end)

-- /cash and /bank (qb-hud) + the event other scripts fire to show a balance
local function showAccount(kind, amount)
    NHUD.send('accounts', { kind = kind, amount = math.floor(tonumber(amount) or 0) })
end
RegisterNetEvent('hud:client:ShowAccounts', showAccount)
if Config.MoneyCommands.cash ~= '' then
    RegisterCommand(Config.MoneyCommands.cash, function() showAccount('cash', HudBridge.data.cash) end, false)
end
if Config.MoneyCommands.bank ~= '' then
    RegisterCommand(Config.MoneyCommands.bank, function() showAccount('bank', HudBridge.data.bank) end, false)
end

-- esx_hud compatibility
RegisterNetEvent('esx_hud:HudToggle', function(state) setVisible(state ~= false) end)
exports('HudToggle', function(state) setVisible(state ~= false) end)
