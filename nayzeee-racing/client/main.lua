if not NAYZEEE_LOCK_OK then return end

--[[
    Tablet: opening / closing, the NUI bridge, player settings, notifications and lobby markers.
]]

App = { open = false, ready = false, profile = nil }

-- ── settings (per player, stored in KVP) ────────────────────────────────
local DEFAULTS = {
    checkpointDui = true, checkpointDuiShowNext = true, checkpointDuiScale = 60, checkpointDuiCount = 3,
    soundEnabled = true, notifications = 'all', language = Config.UI.DefaultLocale, units = 'kmh',
    showBoard = true, showSpeed = true, showSplits = true, autoSpectate = true, mapStyle = '',
}

Settings = {}
do
    local raw = GetResourceKvpString('nzr:settings')
    local ok, saved = pcall(json.decode, raw or '{}')
    for k, v in pairs(DEFAULTS) do Settings[k] = v end
    if ok and type(saved) == 'table' then
        for k, v in pairs(saved) do if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then Settings[k] = v end end
    end
    if not Config.UI.Locales[Settings.language] then Settings.language = Config.UI.DefaultLocale end
    NZR.LoadLocale(Settings.language)
end

local function saveSettings() SetResourceKvp('nzr:settings', json.encode(Settings)) end

function PlaySound(s)
    if not s or not Settings.soundEnabled then return end
    PlaySoundFrontend(-1, s.name, s.set, true)
end

-- ── NUI helpers ─────────────────────────────────────────────────────────
function UI(action, data) SendNUIMessage({ action = action, data = data }) end

local function req(name, data) return lib.callback.await('nzr:req', false, name, data) end

-- Streamed map tiles (minimap_sea_*.ytd from any resource) shown in the tablet through nui-img
local streamDicts = {}
function LoadStreamMaps()
    for _, m in pairs(Config.UI.Maps and Config.UI.Maps.List or {}) do
        local st = m.stream
        if st then
            for r = 0, (st.rows or 3) - 1 do
                for c = 0, (st.cols or 2) - 1 do
                    local dict = st.dict:format(r, c)
                    if not streamDicts[dict] then
                        streamDicts[dict] = true
                        RequestStreamedTextureDict(dict, false)
                    end
                end
            end
        end
    end
end

function ReleaseStreamMaps()
    for dict in pairs(streamDicts) do SetStreamedTextureDictAsNoLongerNeeded(dict) end
    streamDicts = {}
end

function OpenApp()
    if App.open or not App.ready then return end
    if Race and Race.Busy() then return end
    if Builder and Builder.active then return end
    if IsPauseMenuActive() then return end
    if Spectate and Spectate.on then return end
    App.open = true
    LoadStreamMaps()
    SetNuiFocus(true, true)
    if Config.General.Blur then TriggerScreenblurFadeIn(250) end
    UI('open', { settings = Settings })
    Tablet.Start()
end

function CloseApp(fromNui)
    if not App.open then return end
    App.open = false
    SetNuiFocus(false, false)
    if Config.General.Blur then TriggerScreenblurFadeOut(250) end
    if not fromNui then UI('close') end
    Tablet.Stop()
    if not (Builder and Builder.active) then ReleaseStreamMaps() end
end

exports('openApp', OpenApp)
exports('closeApp', function() CloseApp() end)
exports('isInRace', function() return Race and Race.Busy() or false end)

if Config.General.OpenByCommand then
    RegisterCommand(Config.General.Command, OpenApp, false)
    RegisterKeyMapping(Config.General.Command, L('KEY_OPEN'), 'keyboard', Config.General.OpenKey)
end

RegisterNetEvent('nzr:useTablet', function()
    Bridge_CloseInventory()
    SetTimeout(150, OpenApp)
end)

RegisterCommand(Config.General.DnfCommand, function()
    if Race and Race.Busy() then TriggerServerEvent('nzr:race:dnf') end
end, false)

-- ── NUI callbacks ───────────────────────────────────────────────────────
RegisterNUICallback('ready', function(_, cb)
    App.ready = true
    cb({ locale = NZR.LoadLocale(Settings.language), settings = Settings, accent = Config.UI.Accent, danger = Config.UI.Danger,
        scale = Config.UI.Scale, hudScale = Config.UI.HudScale, locales = Config.UI.Locales, maps = Config.UI.Maps })
end)

RegisterNUICallback('close', function(_, cb)
    CloseApp(true)
    cb(true)
end)

RegisterNUICallback('req', function(d, cb)
    local res = req(d.name, d.data)
    if d.name == 'boot' and res and res.data then App.profile = res.data.profile end
    if (d.name == 'profile:create' or d.name == 'profile:update') and res and res.data then App.profile = res.data end
    cb(res or { error = 'ERR_GENERIC' })
end)

RegisterNUICallback('setting', function(d, cb)
    if DEFAULTS[d.key] == nil or type(d.value) ~= type(DEFAULTS[d.key]) then return cb(false) end
    Settings[d.key] = d.value
    saveSettings()
    if d.key == 'language' then
        return cb({ locale = NZR.LoadLocale(d.value) })
    end
    cb(true)
end)

local function vehicleEntry(plate, model, seated)
    if Config.Vehicles.IsBlacklisted(model) then return nil end
    local class = VehicleClass(model)
    if not class then return nil end
    local name = GetDisplayNameFromVehicleModel(model)
    if not name or name == 'CARNOTFOUND' then return nil end
    local label = GetLabelText(name)
    if not label or label == 'NULL' then label = name:sub(1, 1) .. name:sub(2):lower() end
    local make = GetMakeNameFromVehicleModel and GetMakeNameFromVehicleModel(model)
    local brand = make and make ~= '' and GetLabelText(make) or nil
    return {
        plate = NZR.CleanPlate(plate), name = name:lower(), label = label, class = class, seated = seated,
        brand = brand ~= 'NULL' and brand or nil,
        image = Config.General.VehicleImagesUrl and Config.General.VehicleImagesUrl:gsub('{car}', name:lower()) or nil,
    }
end

RegisterNUICallback('vehicles', function(_, cb)
    local res = req('vehicles', {})
    local list, seen = {}, {}
    local cur = cache.vehicle
    local curPlate = cur and NZR.CleanPlate(GetVehicleNumberPlateText(cur))
    if cur and GetPedInVehicleSeat(cur, -1) == cache.ped then
        local e = vehicleEntry(curPlate, GetEntityModel(cur), true)
        if e then list[#list + 1] = e seen[e.plate] = true end
    end
    for _, v in ipairs(res and res.data or {}) do
        local plate = NZR.CleanPlate(v.plate)
        if not seen[plate] then
            local model = type(v.model) == 'number' and v.model or joaat(tostring(v.model))
            local e = IsModelInCdimage(model) and vehicleEntry(plate, model, false)
            if e then list[#list + 1] = e seen[plate] = true end
        end
    end
    cb(list)
end)

RegisterNUICallback('waypoint', function(d, cb)
    if d and d.x and d.y then SetNewWaypoint(d.x + 0.0, d.y + 0.0) end
    cb(true)
end)

RegisterNUICallback('builder', function(d, cb)
    if Race and Race.Busy() then return cb({ error = 'LOBBY_ALREADY_IN' }) end
    local res = req('builder:start', {})
    if not res or res.error then return cb(res or { error = 'ERR_GENERIC' }) end
    CloseApp()
    Builder.Start(res.data and res.data.crewOnly)
    cb({ data = true })
end)

-- Watch a live lobby (the server answers with a 'spectate' race event)
RegisterNUICallback('spectate', function(d, cb)
    local res = req('lobby:spectate', { id = d.id })
    if res and res.data then CloseApp() end
    cb(res or { error = 'ERR_GENERIC' })
end)

-- Solo practice in the car you are driving
function StartPractice(d)
    local veh = cache.vehicle
    if veh then
        local name = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
        local label = GetLabelText(name)
        d.label = (label and label ~= 'NULL') and label or name
        d.name = name:lower()
    end
    local res = req('practice:start', d)
    if res and res.error == 'PRACTICE_GO_TO_START' and type(res.extra) == 'table' and res.extra.x then
        SetNewWaypoint(res.extra.x + 0.0, res.extra.y + 0.0)
    end
    return res
end

RegisterNUICallback('practice', function(d, cb)
    local res = StartPractice({ trackId = d.trackId, laps = d.laps, mode = d.mode })
    if res and res.data then CloseApp() end
    cb(res or { error = 'ERR_GENERIC' })
end)

-- ── server pushes ───────────────────────────────────────────────────────
RegisterNetEvent('nzr:push', function(channel, data)
    if channel == 'profile' then App.profile = data end
    UI('push', { channel = channel, data = data })
end)

RegisterNetEvent('nzr:notify', function(message, kind)
    if Settings.notifications == 'none' then return end
    if Settings.notifications == 'all' and Settings.soundEnabled then
        PlaySoundFrontend(-1, 'CONFIRM_BEEP', 'HUD_MINI_GAME_SOUNDSET', true)
    end
    if App.open then
        UI('toast', { text = message, kind = kind })
    else
        Config.Notify(message, kind)
    end
end)

-- ── lobby markers: flare at the start line once accepted ────────────────
local flare, startBlip

function ClearLobbyMarkers()
    if flare then StopParticleFxLooped(flare, false) flare = nil end
    if startBlip then RemoveBlip(startBlip) startBlip = nil end
end

local function setLobbyMarkers(c)
    ClearLobbyMarkers()
    startBlip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(startBlip, 315)
    SetBlipColour(startBlip, Config.UI.BlipColor)
    SetBlipScale(startBlip, 0.9)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('BLIP_START'))
    EndTextCommandSetBlipName(startBlip)
    if not Config.Races.GatherSmoke.enabled then return end
    local asset = 'scr_xm_ht'
    RequestNamedPtfxAsset(asset)
    local deadline = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < deadline do Wait(10) end
    UseParticleFxAssetNextCall(asset)
    local cfg = Config.Races.GatherSmoke
    flare = StartParticleFxLoopedAtCoord('scr_xm_ht_package_flare', c.x, c.y, c.z - 0.3, 0.0, 0.0, 0.0, cfg.scale, false, false, false, false)
    SetParticleFxLoopedColour(flare, cfg.rgb.r / 255.0, cfg.rgb.g / 255.0, cfg.rgb.b / 255.0, false)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    ClearLobbyMarkers()
    if App.open then SetNuiFocus(false, false) TriggerScreenblurFadeOut(0) end
end)

-- Lobby events arrive on the race channel too (see race.lua)
LobbyEvents = {
    accepted = function(c)
        setLobbyMarkers(c)
        Config.Notify(L('N_START_MARKED'), 'inform')
    end,
    removed = function(reason)
        ClearLobbyMarkers()
        if reason and reason ~= 'left' then Config.Notify(L(reason), 'error') end
        UI('push', { channel = 'active', data = false })
    end,
}
