RES = GetCurrentResourceName()
Emitters = {}                 -- id -> emitter snapshot from the server
UI = { open = false, id = nil }
Settings = {
    master = 1.0, effects = true, streamer = false, compact = false,
    hud = true, hudX = Config.NowPlaying.x, hudY = Config.NowPlaying.y, hudScale = Config.NowPlaying.scale,
    bass = Config.Audio.eq.bass, mid = Config.Audio.eq.mid, treble = Config.Audio.eq.treble,
    skin = Config.NowPlaying.skin, cover = Config.NowPlaying.cover,
    glow = Config.NowPlaying.glow, blur = Config.NowPlaying.blur, viz = true,
    font = Config.NowPlaying.font, animIn = Config.NowPlaying.animIn, animOut = Config.NowPlaying.animOut,
}

local SKINS = { compact = true, boxy = true, gallery = true, minimal = true, macos = true, shell = true, bar = true }
local COVERS = { square = true, canvas = true, vinyl = true, none = true }
local ANIMS = {
    fade = true, slideLeft = true, slideRight = true, slideTop = true, slideBottom = true,
    grow = true, shrink = true, swingLeft = true, swingRight = true, tiltLeft = true, tiltRight = true,
}
local FONTS = { Lexend = true, System = true, Inter = true, Roboto = true, Montserrat = true,
    Oswald = true, ['Bebas Neue'] = true, ['Courier New'] = true }
MyServerId = GetPlayerServerId(PlayerId())

local KVP = 'nzspk:settings'

---------------------------------------------------------------- helpers
function Notify(msg, kind) Bridge.Notify(msg, kind) end
RegisterNetEvent(RES .. ':client:notify', function(msg, kind) Notify(msg, kind) end)

local function ranges(kind)
    return kind == 'vehicle' and Config.Ranges.vehicle or Config.Ranges.boombox
end

-- what the NUI gets (no vectors, plus a few client-side flags)
function NuiPack(e)
    local r = ranges(e.kind)
    return {
        id = e.id, kind = e.kind, item = e.item, label = e.label, state = e.state,
        track = e.track, playing = e.playing, startedAt = e.startedAt, pos = e.pos,
        volume = e.volume, range = e.range, rangeMin = r.min, rangeMax = r.max,
        loop = e.loop, shuffle = e.shuffle, queue = e.queue, access = e.access,
        mine = e.ownerSrc == MyServerId, carriedByMe = e.carrier == MyServerId,
        canPickup = Config.Actions.pickup == 'anyone' or e.ownerSrc == MyServerId,
        portable = e.item and Config.Boomboxes[e.item] and Config.Boomboxes[e.item].portable or false,
        unit = e.kind == 'vehicle' and Config.Carplay.install.use or false,
        turntable = e.turntable or false, vinyl = e.vinyl,
    }
end

function IsMine(e) return e and e.ownerSrc == MyServerId end

---------------------------------------------------------------- settings
local function loadSettings()
    local raw = GetResourceKvpString(KVP)
    if raw then
        local ok, s = pcall(json.decode, raw)
        if ok and type(s) == 'table' then
            for k, v in pairs(s) do if Settings[k] ~= nil then Settings[k] = v end end
        end
    end
    if not Config.StreamerMode.enabled then Settings.streamer = false end
end

local function saveSettings() SetResourceKvp(KVP, json.encode(Settings)) end

local function pushSettings() SendNUIMessage({ action = 'settings', data = Settings }) end

function SetStreamer(on)
    if not Config.StreamerMode.enabled then return end
    Settings.streamer = on and true or false
    saveSettings()
    pushSettings()
    Notify(NZ.L(Settings.streamer and 'streamer_on' or 'streamer_off'), 'inform')
end

if Config.StreamerMode.enabled and Config.StreamerMode.command ~= '' then
    RegisterCommand(Config.StreamerMode.command, function() SetStreamer(not Settings.streamer) end, false)
end

---------------------------------------------------------------- server sync
RegisterNetEvent(RES .. ':client:emitter', function(e)
    Emitters[e.id] = e
    SendNUIMessage({ action = 'emitter', data = NuiPack(e) })
end)

RegisterNetEvent(RES .. ':client:remove', function(id)
    Emitters[id] = nil
    ForgetEmitter(id)
    SendNUIMessage({ action = 'remove', id = id })
    if UI.open and UI.id == id then CloseUI() end
end)

RegisterNetEvent(RES .. ':client:loading', function(id, on)
    SendNUIMessage({ action = 'loading', id = id, on = on })
end)

local function syncClock()
    local t0 = GetGameTimer()
    local server = NZ.Callback('time')
    if not server then return end
    local t1 = GetGameTimer()
    SendNUIMessage({ action = 'clock', server = server + (t1 - t0) / 2 })
end

local nuiReady = false
RegisterNUICallback('ready', function(_, cb) nuiReady = true cb(1) end)

local function boot()
    while not NetworkIsSessionStarted() do Wait(250) end
    -- don't send init / settings into a page that hasn't loaded yet (they'd be lost)
    local t = GetGameTimer()
    while not nuiReady and GetGameTimer() - t < 10000 do Wait(100) end
    Wait(500)
    MyServerId = GetPlayerServerId(PlayerId())
    loadSettings()
    local ui = (Locales[Config.Locale] or Locales.en).ui
    SendNUIMessage({
        action = 'init', locale = ui, version = Config.Version,
        audio = { panning = Config.Audio.panning, syncCheck = Config.Audio.syncCheck, drift = Config.Audio.driftTolerance,
            doppler = Config.Audio.doppler, dopplerAmount = Config.Audio.dopplerAmount },
        streamerAllowed = Config.StreamerMode.enabled,
        nowPlaying = { enabled = Config.NowPlaying.enabled, nearby = Config.NowPlaying.nearby, minLevel = Config.NowPlaying.minLevel,
            x = Config.NowPlaying.x, y = Config.NowPlaying.y, scale = Config.NowPlaying.scale },
        brand = { watermark = Config.Brand.watermark, logo = Config.Brand.logo, name = Config.Brand.name },
    })
    pushSettings()
    syncClock()
    local list = NZ.Callback('snapshot') or {}
    Emitters = {}
    local out = {}
    for _, e in ipairs(list) do
        Emitters[e.id] = e
        out[#out + 1] = NuiPack(e)
    end
    SendNUIMessage({ action = 'reset', list = out })
end

CreateThread(function()
    boot()
    while true do
        Wait(30000)
        syncClock()
    end
end)

-- a fresh snapshot after a character switch / respawn keeps everything in step
AddEventHandler('esx:playerLoaded', function() CreateThread(boot) end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() CreateThread(boot) end)

---------------------------------------------------------------- ui open / close
local lookThread = false

function OpenUI(id)
    local e = Emitters[id]
    if not e then return end
    UI.open, UI.id = true, id
    local keep = e.kind == 'vehicle' and Config.Carplay.keepInput
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(keep)
    SendNUIMessage({ action = 'open', id = id, compact = Settings.compact })

    if keep and not lookThread then
        lookThread = true
        CreateThread(function()
            while UI.open do
                DisableControlAction(0, 1, true)   -- look lr
                DisableControlAction(0, 2, true)   -- look ud
                DisableControlAction(0, 24, true)  -- attack
                DisableControlAction(0, 25, true)  -- aim
                DisableControlAction(0, 68, true)  -- veh aim
                DisableControlAction(0, 69, true)  -- veh attack
                DisableControlAction(0, 70, true)
                DisableControlAction(0, 91, true)
                DisableControlAction(0, 92, true)
                DisableControlAction(0, 106, true) -- veh mouse control
                DisableControlAction(0, 199, true) -- pause
                DisableControlAction(0, 200, true) -- esc
                DisableControlAction(0, 245, true) -- chat
                DisableControlAction(0, 85, true)  -- radio wheel
                Wait(0)
            end
            lookThread = false
        end)
    end

    CreateThread(function()
        local favs, recent = NZ.Callback('lists')
        SendNUIMessage({ action = 'lists', favs = favs or {}, recent = recent or {} })
    end)
end

function CloseUI()
    if not UI.open then return end
    UI.open = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb) CloseUI() cb(1) end)

---------------------------------------------------------------- nui -> server relays
for _, name in ipairs({ 'toggle', 'pause', 'seek', 'next', 'prev', 'volume', 'range', 'loop', 'shuffle', 'stop', 'queueRemove', 'queuePlay', 'access' }) do
    RegisterNUICallback(name, function(data, cb)
        if UI.id then TriggerServerEvent(RES .. ':' .. name, UI.id, data and data.value) end
        cb(1)
    end)
end

RegisterNUICallback('play', function(data, cb)
    if UI.id and type(data.input) == 'string' then
        TriggerServerEvent(RES .. ':play', UI.id, data.input, data.mode)
    end
    cb(1)
end)

RegisterNUICallback('playSaved', function(data, cb)
    if UI.id and type(data.track) == 'table' then
        TriggerServerEvent(RES .. ':playSaved', UI.id, data.track, data.mode)
    end
    cb(1)
end)

-- the UI expects the updated list back; anything else (false) leaves what it already shows
RegisterNUICallback('fav', function(data, cb)
    local favs = NZ.Callback('favToggle', data and data.track)
    cb(type(favs) == 'table' and favs or false)
end)

RegisterNUICallback('recentRemove', function(data, cb)
    local recent = NZ.Callback('recentRemove', data and data.track)
    cb(type(recent) == 'table' and recent or false)
end)

RegisterNUICallback('settings', function(data, cb)
    if type(data) == 'table' then
        if data.master ~= nil then Settings.master = NZ.Clamp(data.master, 0, 1) end
        if data.effects ~= nil then Settings.effects = data.effects and true or false end
        if data.compact ~= nil then Settings.compact = data.compact and true or false end
        if data.hud ~= nil then Settings.hud = data.hud and true or false end
        if data.hudX ~= nil then Settings.hudX = NZ.Clamp(data.hudX, 0, 100) end
        if data.hudY ~= nil then Settings.hudY = NZ.Clamp(data.hudY, 0, 100) end
        if data.hudScale ~= nil then Settings.hudScale = NZ.Clamp(data.hudScale, 0.8, 1.4) end
        for _, k in ipairs({ 'bass', 'mid', 'treble' }) do
            if data[k] ~= nil then Settings[k] = NZ.Clamp(data[k], -12, 12) end
        end
        if data.skin and SKINS[data.skin] then Settings.skin = data.skin end
        if data.cover and COVERS[data.cover] then Settings.cover = data.cover end
        if data.font and FONTS[data.font] then Settings.font = data.font end
        if data.animIn and ANIMS[data.animIn] then Settings.animIn = data.animIn end
        if data.animOut and ANIMS[data.animOut] then Settings.animOut = data.animOut end
        for _, k in ipairs({ 'glow', 'blur', 'viz' }) do
            if data[k] ~= nil then Settings[k] = data[k] and true or false end
        end
        if data.streamer ~= nil and (data.streamer and true or false) ~= Settings.streamer then
            SetStreamer(data.streamer)
        end
        saveSettings()
        pushSettings()
    end
    cb(1)
end)

-- engine reports (any loaded speaker, not only the open one)
RegisterNUICallback('duration', function(data, cb)
    TriggerServerEvent(RES .. ':duration', data.id, data.key, data.value)
    cb(1)
end)

RegisterNUICallback('ended', function(data, cb)
    TriggerServerEvent(RES .. ':ended', data.id, data.key)
    cb(1)
end)

-- the audio link died or the host sent no CORS header, so the song dropped to the embedded player
RegisterNUICallback('fellback', function(data, cb)
    NZ.Debug(('song %s fell back to the embedded player: 3D effects off for it'):format(tostring(data and data.key)))
    cb(1)
end)

RegisterNUICallback('carry', function(_, cb)
    local id = UI.id
    CloseUI()
    if id then TriggerServerEvent(RES .. ':carry', id) end
    cb(1)
end)

RegisterNUICallback('pack', function(_, cb)
    local id = UI.id
    CloseUI()
    if id then TriggerServerEvent(RES .. ':pack', id) end
    cb(1)
end)

RegisterNUICallback('removeUnit', function(_, cb)
    local e = UI.id and Emitters[UI.id]
    CloseUI()
    if e and e.kind == 'vehicle' then RemoveCarplayUnit(e.vehNet) end
    cb(1)
end)

---------------------------------------------------------------- key hints (placement / carry)
function ShowHints(list) SendNUIMessage({ action = 'hints', list = list }) end
function HideHints() SendNUIMessage({ action = 'hints', list = false }) end

---------------------------------------------------------------- search, library, playlists, links, jam
RegisterNUICallback('search', function(data, cb)
    cb(NZ.Callback('search', data and data.query or '') or {})
end)

RegisterNUICallback('lists', function(_, cb)
    local favs, recent = NZ.Callback('lists')
    cb({ favs = favs or {}, recent = recent or {} })
end)

RegisterNUICallback('people', function(_, cb) cb(NZ.Callback('social:players') or {}) end)

local function playlistResult(mine)
    local m, shared = NZ.Callback('pl:list')
    return { mine = mine or m or {}, shared = shared or {} }
end

RegisterNUICallback('playlists', function(_, cb) cb(playlistResult()) end)
RegisterNUICallback('plCreate', function(data, cb) cb(playlistResult(NZ.Callback('pl:create', data.name))) end)
RegisterNUICallback('plAdd', function(data, cb) cb(playlistResult(NZ.Callback('pl:add', data.playlist, data.track))) end)
RegisterNUICallback('plRemove', function(data, cb) cb(playlistResult(NZ.Callback('pl:remove', data.playlist, data.index))) end)
RegisterNUICallback('plDelete', function(data, cb) cb(playlistResult(NZ.Callback('pl:delete', data.playlist))) end)
RegisterNUICallback('plImport', function(data, cb) cb(playlistResult(NZ.Callback('pl:import', data.link))) end)
RegisterNUICallback('plPrompted', function(data, cb) cb(playlistResult(NZ.Callback('pl:prompted', data.prompt))) end)
RegisterNUICallback('plBlend', function(data, cb) cb(playlistResult(NZ.Callback('pl:blend', data.target))) end)
RegisterNUICallback('plCollab', function(data, cb) cb(playlistResult(NZ.Callback('pl:collab', data.playlist, data.target))) end)

RegisterNUICallback('plShare', function(data, cb)
    local mine = NZ.Callback('pl:list')
    local on = true
    for _, p in ipairs(mine or {}) do
        if p.id == data.playlist then on = not p.shared break end
    end
    cb(playlistResult(NZ.Callback('pl:share', data.playlist, on)))
end)

RegisterNUICallback('plMixed', function(data, cb)
    local mine = NZ.Callback('pl:list')
    local on = true
    for _, p in ipairs(mine or {}) do
        if p.id == data.playlist then on = not p.mixed break end
    end
    cb(playlistResult(NZ.Callback('pl:mixed', data.playlist, on)))
end)

RegisterNUICallback('plPlay', function(data, cb)
    if UI.id then TriggerServerEvent(RES .. ':pl:play', UI.id, data.playlist, data.mode) end
    cb(1)
end)

RegisterNUICallback('linksNearby', function(_, cb) cb(NZ.Callback('link:nearby', UI.id) or {}) end)

RegisterNUICallback('link', function(data, cb)
    if UI.id and data.other then TriggerServerEvent(RES .. ':link', UI.id, data.other) end
    cb(1)
end)

RegisterNUICallback('unlink', function(_, cb)
    if UI.id then TriggerServerEvent(RES .. ':unlink', UI.id) end
    cb(1)
end)

RegisterNUICallback('jamList', function(_, cb)
    local list, mine = NZ.Callback('jam:list')
    cb({ list = list or {}, mine = mine or false })
end)

RegisterNUICallback('jamCreate', function(data, cb) cb(NZ.Callback('jam:create', data and data.name or '') or false) end)
RegisterNUICallback('jamJoin', function(data, cb) cb(NZ.Callback('jam:join', data and data.id) or false) end)
RegisterNUICallback('jamLeave', function(_, cb) NZ.Callback('jam:leave') cb(1) end)

RegisterNetEvent(RES .. ':client:jam', function(view)
    SendNUIMessage({ action = 'jam', data = view or false })
end)

---------------------------------------------------------------- vinyl
RegisterNUICallback('vinylOwned', function(_, cb) cb(NZ.Callback('vinyl:owned') or {}) end)

RegisterNUICallback('vinylInsert', function(data, cb)
    if UI.id and type(data.item) == 'string' then TriggerServerEvent(RES .. ':vinyl:insert', UI.id, data.item) end
    cb(1)
end)

RegisterNUICallback('vinylEject', function(_, cb)
    if UI.id then TriggerServerEvent(RES .. ':vinyl:eject', UI.id) end
    cb(1)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if UI.open then SetNuiFocus(false, false) end
end)
