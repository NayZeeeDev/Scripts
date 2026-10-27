--[[
    The Speaker app for lb-phone, qs-smartphone (and qs-smartphone-pro) and yseries.

    The app itself is html/phone/ (index.html + app.css + app.js): a normal web page the phone shows
    in an iframe. While it is open it asks for `phoneState` about once a second. That answer comes
    from the live copy of every speaker this client already keeps (Emitters); the server is only
    asked which speakers you may control every few seconds (the roster below).
]]
if not Config.Phone.enabled then return end

local P = Config.Phone
local APP = 'nayzeee_speaker'
local DESCRIPTION = 'Control speakers and boomboxes'
local DEVELOPER = 'NAYZEEE Development'
local ROSTER_TTL = 4000

-- room each phone keeps clear at the top (status bar / notch) and bottom (home bar), in CSS px.
-- Config.Phone.insets overrides these; the app also reads ?top= / ?bottom= from its own URL.
local INSETS = {
    ['lb-phone'] = { top = 50, bottom = 28 },
    ['qs-smartphone'] = { top = 44, bottom = 24 },
    ['qs-smartphone-pro'] = { top = 44, bottom = 24 },
    ['yseries'] = { top = 48, bottom = 26 },
}

local phone

local function started(res) return GetResourceState(res) == 'started' end

local function detect()
    local want = P.app or 'auto'
    if want == 'none' then return nil end
    if want ~= 'auto' then return started(want) and want or nil end
    for _, res in ipairs({ 'lb-phone', 'qs-smartphone-pro', 'qs-smartphone', 'yseries' }) do
        if started(res) then return res end
    end
    return nil
end

local function insets()
    local d = INSETS[phone] or { top = 46, bottom = 26 }
    local c = type(P.insets) == 'table' and P.insets or {}
    local top, bottom = tonumber(c.top) or 0, tonumber(c.bottom) or 0
    return { top = top > 0 and top or d.top, bottom = bottom > 0 and bottom or d.bottom }
end

local function appUrls()
    local base = ('https://cfx-nui-%s/html/phone/'):format(RES)
    local i = insets()
    return ('%sindex.html?phone=%s&top=%d&bottom=%d'):format(base, phone, i.top, i.bottom), base .. 'icon.png'
end

---------------------------------------------------------------- registration
local function register()
    local ui, icon = appUrls()
    local ok, res, err
    if phone == 'lb-phone' then
        ok, res, err = pcall(function()
            return exports['lb-phone']:AddCustomApp({
                identifier = APP, name = P.name, description = DESCRIPTION, developer = DEVELOPER,
                developerUrl = 'https://www.nayzeeedev.com',
                defaultApp = true, size = 48000, ui = ui, icon = icon,
            })
        end)
    elseif phone == 'yseries' then
        ok, res, err = pcall(function()
            return exports['yseries']:AddCustomApp({
                identifier = APP, name = P.name, description = DESCRIPTION, developer = DEVELOPER,
                defaultApp = true, ui = ui, icon = icon,
            })
        end)
    else
        -- qs-smartphone-pro has addCustomApp, older qs-smartphone builds CreateApp: use whichever exists
        local function pro()
            return exports[phone]:addCustomApp({
                app = APP, label = P.name, image = icon, ui = ui, creator = DEVELOPER,
                description = DESCRIPTION, category = 'social', isGame = false,
                job = false, blockedJobs = {}, timeout = 5000, age = '16+', extraDescription = {},
            })
        end
        local function legacy()
            return exports[phone]:CreateApp({
                appIdentifier = APP, appName = P.name, appDeveloper = DEVELOPER, appIcon = icon,
                appUrl = ui, appSize = 48000, appDescription = DESCRIPTION,
            })
        end
        local first, second = legacy, pro
        if phone == 'qs-smartphone-pro' then first, second = pro, legacy end
        ok, res, err = pcall(first)
        if not ok then ok, res, err = pcall(second) end
    end
    if not ok then return NZ.Debug(('%s: could not add the app: %s'):format(phone, tostring(res))) end
    if res == false then return NZ.Debug(('%s refused the app: %s'):format(phone, tostring(err))) end
    NZ.Debug('speaker app registered on ' .. phone)
end

local function unregister()
    if phone == 'lb-phone' then
        pcall(function() exports['lb-phone']:RemoveCustomApp(APP) end)
    elseif phone == 'qs-smartphone-pro' then
        pcall(function() exports[phone]:removeCustomApp(APP) end)
    end
end

CreateThread(function()
    phone = detect()
    if not phone then
        if P.app ~= 'none' and P.app ~= 'auto' then NZ.Debug('phone resource not started:', P.app) end
        return
    end
    Wait(2500)   -- let the phone finish starting
    register()
end)

-- the phone started after us, or restarted and forgot every custom app
AddEventHandler('onClientResourceStart', function(res)
    if res == RES then return end
    phone = phone or detect()
    if phone and res == phone then SetTimeout(2500, register) end
end)

AddEventHandler('onResourceStop', function(res)
    if res == RES then unregister() end
end)

---------------------------------------------------------------- live state for the app
local roster, rosterAt, rosterBusy = {}, -ROSTER_TTL, false

-- which speakers the server lets us control (refreshed at most every few seconds)
local function refreshRoster(force)
    if rosterBusy then
        local t = GetGameTimer()
        while rosterBusy and GetGameTimer() - t < 3000 do Wait(50) end
        return
    end
    if not force and GetGameTimer() - rosterAt < ROSTER_TTL then return end
    rosterBusy = true
    local list = NZ.Callback('phone:list')
    local fresh = {}
    if type(list) == 'table' then
        for _, r in ipairs(list) do
            if type(r) == 'table' and r.id then fresh[r.id] = r end
        end
    end
    roster, rosterAt, rosterBusy = fresh, GetGameTimer(), false
end

local function iconOf(e)
    if e.kind == 'vehicle' then return 'car' end
    if e.kind == 'jam' then return 'jam' end
    if e.turntable then return 'vinyl' end
    return 'speaker'
end

local function distanceTo(e, r, me)
    if e.kind == 'jam' or e.kind == 'vehicle' then return 0 end
    local pos = e.coords
    if e.state == 'carried' and e.carrier then
        if e.carrier == MyServerId then return 0 end
        local pl = GetPlayerFromServerId(e.carrier)
        local ped = pl ~= -1 and GetPlayerPed(pl) or 0
        if ped == 0 then return r.d or 0 end
        pos = GetEntityCoords(ped)
    end
    if type(pos) ~= 'vector3' then return r.d or 0 end
    return math.floor(#(me - pos) + 0.5)
end

local function slimTrack(t)
    return {
        src = t.src, id = t.id, url = t.src == 'url' and t.url or nil,
        title = t.title, author = t.author, duration = tonumber(t.duration) or 0, thumb = t.thumb,
    }
end

local function device(e, r, me, active)
    local v = e.vinyl
    local d = {
        id = e.id, kind = e.kind, icon = iconOf(e),
        label = e.label or (e.item and Config.Boomboxes[e.item] and Config.Boomboxes[e.item].label) or 'Speaker',
        mine = r.mine and true or false, d = distanceTo(e, r, me),
        turntable = e.turntable or false,
        linked = (e.groupSize or 0) > 1 and e.groupSize - 1 or 0,
        playing = e.playing and true or false, startedAt = e.startedAt or 0, pos = e.pos or 0,
        volume = e.volume or 0, loop = e.loop or false, shuffle = e.shuffle or false,
        track = e.track and slimTrack(e.track) or nil,
        queued = e.queue and #e.queue or 0,
        record = v and {
            album = v.album, artist = v.artist, cover = v.cover, idx = v.idx or 1,
            count = type(v.tracks) == 'table' and #v.tracks or 0, phase = v.phase, loading = v.loading or false,
        } or nil,
    }
    -- the full queue (or the record's track list) only for the speaker the app is showing
    if active then
        local q = {}
        for i, t in ipairs(e.queue or {}) do
            if i > 50 then break end
            q[i] = slimTrack(t)
        end
        d.queue = q
        if d.record then d.record.tracks = v.tracks end
    end
    return d
end

local function visible(e, veh)
    if e.kind ~= 'vehicle' then return true end
    return veh ~= 0 and NetworkGetEntityIsNetworked(veh) and VehToNet(veh) == e.vehNet
end

RegisterNUICallback('phoneState', function(data, cb)
    refreshRoster(type(data) == 'table' and data.fresh == true)
    local active = type(data) == 'table' and data.active or nil
    local ped = PlayerPedId()
    local me = GetEntityCoords(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    local out = {}
    for id, r in pairs(roster) do
        local e = Emitters[id]
        if e and visible(e, veh) then out[#out + 1] = device(e, r, me, id == active) end
    end
    table.sort(out, function(a, b)
        local pa, pb = a.playing and a.track ~= nil, b.playing and b.track ~= nil
        if pa ~= pb then return pa end
        if a.mine ~= b.mine then return a.mine end
        if a.d ~= b.d then return a.d < b.d end
        return a.id < b.id
    end)
    cb({ now = ServerTime(), devices = out })
end)

-- lb-phone can message its custom apps: nudge the app to refresh as soon as one of its speakers changes
if GetResourceState('lb-phone') ~= 'missing' then
    local lastPoke = 0
    RegisterNetEvent(RES .. ':client:emitter', function(e)
        if phone ~= 'lb-phone' or type(e) ~= 'table' or not roster[e.id] then return end
        local t = GetGameTimer()
        if t - lastPoke < 250 then return end
        lastPoke = t
        pcall(function() exports['lb-phone']:SendCustomAppMessage(APP, { nzspk = 'poke' }) end)
    end)
end

---------------------------------------------------------------- app <-> game
local function phoneStrings()
    local out = {}
    for _, pack in ipairs({ Locales.en or {}, Locales[Config.Locale] or {} }) do
        if type(pack.phone) == 'table' then
            for k, v in pairs(pack.phone) do out[k] = v end
        end
    end
    return out
end

RegisterNUICallback('phoneInit', function(_, cb)
    local B = Config.Brand
    cb({
        name = P.name, phone = phone or 'none', insets = insets(), strings = phoneStrings(),
        brand = { watermark = B.watermark ~= false, logo = (B.logo or '') ~= '' and ('../' .. B.logo) or '', name = B.name or '' },
        features = {
            search = Config.Search.enabled ~= false,
            playlists = Config.Playlists.enabled ~= false,
            jam = Config.Social.jam ~= false,
        },
    })
end)

RegisterNUICallback('phoneSearch', function(data, cb)
    local q = type(data) == 'table' and data.query or ''
    cb(NZ.Callback('search', type(q) == 'string' and q:sub(1, 120) or '') or {})
end)

RegisterNUICallback('phoneAction', function(data, cb)
    if type(data) == 'table' and type(data.id) == 'string' and type(data.what) == 'string' then
        TriggerServerEvent(RES .. ':phone:action', data.id, data.what, data.value)
    end
    cb(1)
end)

RegisterNUICallback('phonePlay', function(data, cb)
    if type(data) == 'table' and type(data.id) == 'string' and type(data.track) == 'table' then
        TriggerServerEvent(RES .. ':phone:play', data.id, data.track, data.mode)
    end
    cb(1)
end)

RegisterNUICallback('phonePlayList', function(data, cb)
    if type(data) == 'table' and type(data.id) == 'string' and data.list ~= nil then
        TriggerServerEvent(RES .. ':phone:playList', data.id, data.list, tonumber(data.start) or 1, data.shuffle == true)
    end
    cb(1)
end)

local function playlists()
    local mine, shared = NZ.Callback('pl:list')
    return { mine = mine or {}, shared = shared or {} }
end

RegisterNUICallback('phoneLibrary', function(_, cb)
    local favs = NZ.Callback('lists')
    cb({ favs = favs or {}, playlists = playlists() })
end)

-- a heart gets the whole updated list back; anything else (false) means "keep what you show"
RegisterNUICallback('phoneFav', function(data, cb)
    local favs = NZ.Callback('favToggle', type(data) == 'table' and data.track or nil)
    cb(type(favs) == 'table' and favs or false)
end)

RegisterNUICallback('phonePlCreate', function(data, cb)
    local mine = NZ.Callback('pl:create', type(data) == 'table' and data.name or nil)
    if not mine then return cb(false) end
    cb(playlists())
end)

RegisterNUICallback('phonePlAdd', function(data, cb)
    if type(data) ~= 'table' or type(data.track) ~= 'table' then return cb(false) end
    local mine = NZ.Callback('pl:add', tonumber(data.playlist), data.track)
    if not mine then return cb(false) end
    cb(playlists())
end)

RegisterNUICallback('phoneJams', function(_, cb)
    local list, mine = NZ.Callback('jam:list')
    cb({ list = list or {}, mine = mine or false })
end)

RegisterNUICallback('phoneJamCreate', function(data, cb)
    cb(NZ.Callback('jam:create', type(data) == 'table' and data.name or '') or false)
end)

RegisterNUICallback('phoneJamJoin', function(data, cb)
    cb(NZ.Callback('jam:join', type(data) == 'table' and data.id or nil) or false)
end)

RegisterNUICallback('phoneJamLeave', function(_, cb)
    NZ.Callback('jam:leave')
    cb(1)
end)
