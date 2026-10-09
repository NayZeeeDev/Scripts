--[[
    Registers the Speaker app on whichever phone the server runs.
    Supported: lb-phone, qs-smartphone (and qs-smartphone-pro), yseries.
    The app itself is html/phone/index.html — a normal web app the phone loads in an iframe.
]]
if not Config.Phone.enabled then return end

local P = Config.Phone
local appUrl = ('https://cfx-nui-%s/html/phone/index.html'):format(RES)
local icon = ('https://cfx-nui-%s/html/phone/icon.png'):format(RES)

local function detect()
    local want = P.app
    local function started(r) return GetResourceState(r) == 'started' end
    if want ~= 'auto' and want ~= 'none' then return started(want) and want or nil end
    if want == 'none' then return nil end
    if started('lb-phone') then return 'lb-phone' end
    if started('qs-smartphone-pro') then return 'qs-smartphone-pro' end
    if started('qs-smartphone') then return 'qs-smartphone' end
    if started('yseries') then return 'yseries' end
    return nil
end

local function addLb()
    local ok, err = pcall(function()
        return exports['lb-phone']:AddCustomApp({
            identifier = 'nayzeee_speaker',
            name = P.name,
            description = 'Control speakers and boomboxes',
            developer = 'NAYZEEE Development',
            defaultApp = true,
            size = 48000,
            ui = appUrl,
            icon = icon,
developerUrl = 'https://www.nayzeeedev.com',
        })
    end)
    if not ok then NZ.Debug('lb-phone app failed:', err) end
end

local function addQs(res)
    local ok, err = pcall(function()
        return exports[res]:CreateApp({
            appIdentifier = 'nayzeee_speaker',
            appName = P.name,
            appDeveloper = 'NAYZEEE Development',
            appIcon = icon,
            appUrl = appUrl,
            appSize = 48000,
            appDescription = 'Control speakers and boomboxes',
        })
    end)
    if not ok then NZ.Debug('qs app failed:', err) end
end

local function addY()
    local ok, err = pcall(function()
        return exports['yseries']:AddCustomApp({
            identifier = 'nayzeee_speaker',
            name = P.name,
            description = 'Control speakers and boomboxes',
            developer = 'NAYZEEE Development',
            defaultApp = true,
            ui = appUrl,
            icon = icon,
        })
    end)
    if not ok then NZ.Debug('yseries app failed:', err) end
end

CreateThread(function()
    local phone = detect()
    if not phone then
        if P.app ~= 'none' and P.app ~= 'auto' then NZ.Debug('phone resource not started:', P.app) end
        return
    end
    Wait(2500)   -- let the phone finish starting
    if phone == 'lb-phone' then addLb()
    elseif phone == 'yseries' then addY()
    else addQs(phone) end
    NZ.Debug('speaker app registered on ' .. phone)
end)

---------------------------------------------------------------- app <-> game
RegisterNUICallback('phoneList', function(_, cb) cb(NZ.Callback('phone:list') or {}) end)

RegisterNUICallback('phoneSearch', function(data, cb)
    cb(NZ.Callback('search', data and data.query or '') or {})
end)

RegisterNUICallback('phoneBrand', function(_, cb)
    cb({ watermark = Config.Brand.watermark, logo = Config.Brand.logo ~= '' and ('../' .. Config.Brand.logo) or '', name = Config.Brand.name })
end)

RegisterNUICallback('phonePlay', function(data, cb)
    if data and data.id and data.video then
        TriggerServerEvent(RES .. ':phone:play', data.id, data.video, data.mode)
    end
    cb(1)
end)

RegisterNUICallback('phonePlaySaved', function(data, cb)
    if data and data.id and data.track then
        TriggerServerEvent(RES .. ':phone:playSaved', data.id, data.track, data.mode)
    end
    cb(1)
end)

RegisterNUICallback('phoneAction', function(data, cb)
    if data and data.id and data.what then
        TriggerServerEvent(RES .. ':phone:action', data.id, data.what, data.value)
    end
    cb(1)
end)

RegisterNUICallback('phoneLibrary', function(_, cb)
    local favs = NZ.Callback('lists')
    local mine, shared = NZ.Callback('pl:list')
    cb({ favs = favs or {}, playlists = { mine = mine or {}, shared = shared or {} } })
end)

RegisterNUICallback('phoneFav', function(data, cb)
    local favs = NZ.Callback('favToggle', data and data.track)
    cb(type(favs) == 'table' and favs or false)
end)

RegisterNUICallback('phonePlCreate', function(data, cb)
    local mine = NZ.Callback('pl:create', data and data.name)
    local _, shared = NZ.Callback('pl:list')
    cb({ mine = mine or {}, shared = shared or {} })
end)

RegisterNUICallback('phonePlaylistPlay', function(data, cb)
    if data and data.id and data.playlist then
        TriggerServerEvent(RES .. ':pl:play', data.id, data.playlist, data.mode)
    end
    cb(1)
end)

RegisterNUICallback('phoneJams', function(_, cb)
    local list, mine = NZ.Callback('jam:list')
    cb({ list = list or {}, mine = mine or false })
end)

RegisterNUICallback('phoneJamCreate', function(data, cb) cb(NZ.Callback('jam:create', data and data.name or '') or false) end)
RegisterNUICallback('phoneJamJoin', function(data, cb) cb(NZ.Callback('jam:join', data and data.id) or false) end)
RegisterNUICallback('phoneJamLeave', function(_, cb) NZ.Callback('jam:leave') cb(1) end)
