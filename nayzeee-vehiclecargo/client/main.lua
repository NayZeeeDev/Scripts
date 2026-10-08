-----------------------------------------------------------------
-- Client core: doors, brokers, blips, NUI bridge, shared helpers
-----------------------------------------------------------------
Client = {
    locations = {},     -- [id] = location
    access    = {},     -- warehouses this player can open
    brokers   = {},
    interior  = nil,
    inside    = nil,    -- enter payload while inside
    mission   = nil,    -- active source / sell mission
    nui       = false,
    static    = nil,
}

local blips, brokerPeds = {}, {}

-----------------------------------------------------------------
-- NUI
-----------------------------------------------------------------
function Client.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- Rarities, upgrades etc. The UI gets them straight away so the spec card
-- has its colours even before any menu was opened.
function Client.Static()
    if not Client.static then
        Client.static = lib.callback.await('nz_cargo:static', false)
        if Client.static then Client.Send('static', Client.static) end
    end
    return Client.static
end

-- Close any prompt, menu or dialog of ours that could be left on screen
function Client.ClosePrompts()
    Bridge.HideText()
    local menu = lib.getOpenContextMenu()
    if menu and tostring(menu):find('^nz_cargo') then lib.hideContext(false) end
    if Client.knocking then lib.closeAlertDialog() end
end

function Client.OpenUI(view, data, keepInput)
    Client.nui = true
    SetNuiFocus(true, true)
    if keepInput then SetNuiFocusKeepInput(true) end
    Client.Send('open', { view = view, data = data, static = Client.Static() })
end

function Client.CloseUI()
    if not Client.nui then return end
    Client.nui = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    Client.Send('close')
end

-- One router for every UI request
local handlers = {}
Client.Handlers = handlers

RegisterNUICallback('req', function(body, cb)
    local fn = handlers[body.action]
    if not fn then cb({ ok = false }) return end
    CreateThread(function()
        local ok, res = pcall(fn, body.data or {})
        if not ok then print('^1[vehiclecargo] UI handler error (' .. tostring(body.action) .. '): ' .. tostring(res) .. '^7') end
        cb(ok and (res == nil and { ok = true } or res) or { ok = false })
    end)
end)

handlers.close = function()
    if Laptop and Laptop.open then Laptop.Close() return true end
    Client.CloseUI()
    if Workshop and Workshop.active then Workshop.Close(true) end
    return true
end

-----------------------------------------------------------------
-- Helpers shared by modules
-----------------------------------------------------------------
function Client.LoadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    lib.requestModel(hash, 10000)
    return hash
end

function Client.NetEntity(netId, timeout)
    local t = GetGameTimer() + (timeout or 8000)
    while GetGameTimer() < t do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local e = NetToVeh(netId)
            if e ~= 0 and DoesEntityExist(e) then return e end
        end
        Wait(50)
    end
    return nil
end

function Client.Control(entity, timeout)
    local t = GetGameTimer() + (timeout or 2000)
    NetworkRequestControlOfEntity(entity)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < t do
        NetworkRequestControlOfEntity(entity)
        Wait(25)
    end
    return NetworkHasControlOfEntity(entity)
end

function Client.Blip(coords, sprite, colour, label, route)
    local b = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(b, sprite or 1)
    SetBlipColour(b, colour or 5)
    SetBlipScale(b, 0.9)
    if route then SetBlipRoute(b, true) SetBlipRouteColour(b, colour or 5) end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or 'Objective')
    EndTextCommandSetBlipName(b)
    return b
end

function Client.Fade(out, ms)
    ms = ms or 400
    if out then
        DoScreenFadeOut(ms)
        while not IsScreenFadedOut() do Wait(10) end
    else
        DoScreenFadeIn(ms)
    end
end

-- Teleport and wait for the ground to load (stops floating / falling)
function Client.Teleport(c, heading)
    local ped = cache.ped
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    if heading then SetEntityHeading(ped, heading) end
    local t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(20) end
end

-----------------------------------------------------------------
-- Doors (enter / knock), owned blips
-----------------------------------------------------------------
local function clearDoors()
    for id in pairs(Client.locations) do Bridge.RemovePoint('nz_door_' .. id) end
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
end

local function accessAt(locationId)
    local list = {}
    for _, a in ipairs(Client.access) do
        if a.location == locationId then list[#list + 1] = a end
    end
    table.sort(list, function(a, b) return a.role == 'owner' and b.role ~= 'owner' end)
    return list
end

local function enterMenu(loc)
    local list = accessAt(loc.id)
    if #list == 1 then Warehouse.Enter(list[1].id) return end
    local opts = {}
    for _, a in ipairs(list) do
        opts[#opts + 1] = {
            title = a.role == 'owner' and 'Your warehouse' or (a.owner or 'Associate') .. '\'s warehouse',
            icon = a.role == 'owner' and 'warehouse' or 'handshake',
            onSelect = function() Warehouse.Enter(a.id) end,
        }
    end
    lib.registerContext({ id = 'nz_cargo_door', title = loc.name, options = opts })
    lib.showContext('nz_cargo_door')
end

local function knock(loc)
    local list = lib.callback.await('nz_cargo:knockList', false, loc.id)
    if not list or #list == 0 then Bridge.Notify(L('knock_denied'), 'error') return end
    local function go(wid)
        Bridge.Notify(L('knock_sent'), 'info')
        local data = lib.callback.await('nz_cargo:knock', false, wid)
        if data then Warehouse.Load(data) end
    end
    if #list == 1 then go(list[1].id) return end
    local opts = {}
    for _, w in ipairs(list) do opts[#opts + 1] = { title = (w.owner or 'Someone') .. '\'s warehouse', icon = 'door-closed', onSelect = function() go(w.id) end } end
    lib.registerContext({ id = 'nz_cargo_knock', title = loc.name, options = opts })
    lib.showContext('nz_cargo_knock')
end

local function buildDoors()
    clearDoors()
    for _, loc in pairs(Client.locations) do
        local d = loc.door
        local owned = #accessAt(loc.id) > 0
        if owned and Config.Interact.Blips then
            local b = AddBlipForCoord(d.x, d.y, d.z)
            SetBlipSprite(b, Config.Interact.BlipSprite)
            SetBlipColour(b, Config.Interact.BlipColour)
            SetBlipScale(b, 0.85)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Warehouse · ' .. loc.name)
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
        local options = {
            { label = L('ti_enter'), icon = 'fa-solid fa-door-open', onSelect = function() enterMenu(loc) end,
              canInteract = function() return not Client.inside and #accessAt(loc.id) > 0 end },
        }
        if Config.Doors.Knock then
            options[#options + 1] = { label = L('ti_knock'), icon = 'fa-solid fa-hand-back-fist', onSelect = function() knock(loc) end,
                canInteract = function() return not Client.inside and #accessAt(loc.id) == 0 end }
        end
        Bridge.AddPoint('nz_door_' .. loc.id, vec3(d.x, d.y, d.z), Config.Interact.Distance, options)
    end
end

-----------------------------------------------------------------
-- Brokers (NPCs that sell warehouses)
-----------------------------------------------------------------
local function clearBrokers()
    for i, b in ipairs(brokerPeds) do
        Bridge.RemoveEntity(b.ped, 'nz_broker_' .. i)
        if DoesEntityExist(b.ped) then DeleteEntity(b.ped) end
        if b.blip then RemoveBlip(b.blip) end
    end
    brokerPeds = {}
end

function Client.OpenShop()
    local shop = lib.callback.await('nz_cargo:shop', false)
    if shop then Client.OpenUI('shop', shop) end
end

local function spawnBrokers()
    clearBrokers()
    local cfg = Config.Broker
    for i, c in ipairs(Client.brokers) do
        local entry = {}
        if cfg.Blip then
            local b = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(b, cfg.Blip.sprite)
            SetBlipColour(b, cfg.Blip.colour)
            SetBlipScale(b, cfg.Blip.scale)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(cfg.Blip.label)
            EndTextCommandSetBlipName(b)
            entry.blip = b
        end
        -- spawn the ped only when someone is close (keeps resmon flat)
        local p = lib.points.new({ coords = vec3(c.x, c.y, c.z), distance = 60.0 })
        function p:onEnter()
            local hash = Client.LoadModel(cfg.Model)
            if not hash then return end
            local ok, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
            local ped = CreatePed(4, hash, c.x, c.y, ok and gz or (c.z - 1.0), c.w or 0.0, false, true)
            SetModelAsNoLongerNeeded(hash)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            if cfg.Scenario then TaskStartScenarioInPlace(ped, cfg.Scenario, 0, true) end
            entry.ped = ped
            Bridge.AddEntity(ped, 'nz_broker_' .. i, {
                { label = L('ti_broker'), icon = 'fa-solid fa-warehouse', onSelect = Client.OpenShop },
            }, 2.5)
        end
        function p:onExit()
            if entry.ped then
                Bridge.RemoveEntity(entry.ped, 'nz_broker_' .. i)
                if DoesEntityExist(entry.ped) then DeleteEntity(entry.ped) end
                entry.ped = nil
            end
        end
        entry.point = p
        brokerPeds[i] = entry
    end
end

local function removeBrokerPoints()
    for _, b in ipairs(brokerPeds) do if b.point then b.point:remove() end end
end

RegisterNetEvent('nz_cargo:brokers', function(list)
    removeBrokerPoints()
    Client.brokers = list or {}
    spawnBrokers()
end)

-----------------------------------------------------------------
-- Refresh
-----------------------------------------------------------------
function Client.Refresh()
    local data = lib.callback.await('nz_cargo:locations', false)
    if not data then return end
    clearDoors()
    Client.locations = {}
    for _, l in ipairs(data.locations) do Client.locations[l.id] = l end
    Client.access = data.access or {}
    Client.interior = data.interior
    buildDoors()
    removeBrokerPoints()
    Client.brokers = data.brokers or {}
    spawnBrokers()
    Client.SetPrefs(data.prefs)
end

-- The player's own look (accent etc.). Used by the HUD, menus and markers.
function Client.SetPrefs(p)
    if not p then return end
    Client.prefs = p
    Client.Send('prefs', { prefs = p, mine = true, options = { accents = Config.Prefs.Accents, finishes = Config.Prefs.Finishes, wallpapers = Config.Prefs.Wallpapers } })
end

function Client.Accent()
    local id = Client.prefs and Client.prefs.accent
    for _, a in ipairs(Config.Prefs.Accents) do
        if a.id == id then
            local h = a.color:gsub('#', '')
            return tonumber(h:sub(1, 2), 16) or 8, tonumber(h:sub(3, 4), 16) or 175, tonumber(h:sub(5, 6), 16) or 162
        end
    end
    return 8, 175, 162
end

RegisterNetEvent('nz_cargo:accessChanged', function(access)
    Client.access = access or {}
    buildDoors()
end)

RegisterNetEvent('nz_cargo:locationsChanged', function() Client.Refresh() end)

-----------------------------------------------------------------
-- Shop (buying a warehouse at the broker)
-----------------------------------------------------------------
handlers.buy = function(d)
    local res = lib.callback.await('nz_cargo:buy', false, d.location)
    if not res then return { ok = false } end
    Client.CloseUI()
    Client.Refresh()
    if res.door then
        SetNewWaypoint(res.door.x, res.door.y)
        Bridge.Notify(('%s is marked on your GPS.'):format(res.name), 'success', 'Warehouse')
    end
    return { ok = true }
end

-- Sell a warehouse back to the broker: the shop stays open with fresh listings
handlers.whSell = function(d)
    if not lib.callback.await('nz_cargo:warehouse:sell', false, d.id) then return { ok = false } end
    return lib.callback.await('nz_cargo:shop', false) or { ok = false }
end

-- Move everything to another building
handlers.whMove = function(d)
    local res = lib.callback.await('nz_cargo:warehouse:move', false, d.id, d.location)
    if not res then return { ok = false } end
    Client.CloseUI()
    Client.Refresh()
    if res.door then SetNewWaypoint(res.door.x, res.door.y) end
    return { ok = true }
end

handlers.waypoint = function(d)
    if d.x and d.y then SetNewWaypoint(d.x + 0.0, d.y + 0.0) end
    return true
end

-----------------------------------------------------------------
-- Knock prompt (someone at the door)
-----------------------------------------------------------------
lib.callback.register('nz_cargo:knockPrompt', function(name)
    if Client.knocking then return false end
    local token = {}
    Client.knocking = token
    -- nobody answered: take the dialog off the screen instead of leaving it up
    SetTimeout((Config.Doors.KnockTimeout or 20) * 1000, function()
        if Client.knocking == token then lib.closeAlertDialog() end
    end)
    local res = lib.alertDialog({
        header = 'Someone is at the door', content = L('knock_prompt', name),
        centered = true, cancel = true, labels = { confirm = 'Let in', cancel = 'Ignore' },
    })
    Client.knocking = nil
    return res == 'confirm' and Client.inside ~= nil
end)

-----------------------------------------------------------------
-- Police dispatch (default built-in alert)
-----------------------------------------------------------------
RegisterNetEvent('nz_cargo:dispatch', function(data)
    Bridge.Notify(data.message, 'warning', ('%s %s'):format(data.code or '', data.title or ''))
    local c = data.coords
    if not c then return end
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, data.blip and data.blip.sprite or 225)
    SetBlipColour(b, data.blip and data.blip.colour or 1)
    SetBlipFlashes(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(data.title or 'Alert')
    EndTextCommandSetBlipName(b)
    local r = AddBlipForRadius(c.x, c.y, c.z, 80.0)
    SetBlipColour(r, 1)
    SetBlipAlpha(r, 90)
    SetTimeout((data.blipTime or 60) * 1000, function() RemoveBlip(b) RemoveBlip(r) end)
end)

-- Police: live tracker blips that follow the car while its tracker is on
local tracked = {}
RegisterNetEvent('nz_cargo:track', function(d)
    local t = tracked[d.id]
    if not t then
        local b = AddBlipForCoord(d.x, d.y, d.z)
        SetBlipSprite(b, 326)
        SetBlipColour(b, 1)
        SetBlipScale(b, 1.0)
        SetBlipFlashes(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(('Tracker · %s %s'):format(d.label or '', d.plate or ''))
        EndTextCommandSetBlipName(b)
        t = { blip = b }
        tracked[d.id] = t
    end
    SetBlipCoords(t.blip, d.x, d.y, d.z)
    t.seen = GetGameTimer()
end)

-- Scanner owners: tracked cars they could take
local hot = {}
RegisterNetEvent('nz_cargo:hot', function(d)
    local t = hot[d.id]
    if not t then
        local b = AddBlipForRadius(d.x, d.y, d.z, 120.0)
        SetBlipColour(b, 1)
        SetBlipAlpha(b, 110)
        local c = AddBlipForCoord(d.x, d.y, d.z)
        SetBlipSprite(c, 225)
        SetBlipColour(c, 1)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Tracked ' .. (d.label or 'vehicle'))
        EndTextCommandSetBlipName(c)
        t = { area = b, blip = c }
        hot[d.id] = t
        Bridge.Notify(L('hot_target', d.label or 'car'), 'warning', 'Scanner')
    end
    SetBlipCoords(t.area, d.x, d.y, d.z)
    SetBlipCoords(t.blip, d.x, d.y, d.z)
    t.seen = GetGameTimer()
end)

local function dropTrack(list, id)
    local t = list[id]
    if not t then return end
    for _, k in ipairs({ 'blip', 'area' }) do if t[k] and DoesBlipExist(t[k]) then RemoveBlip(t[k]) end end
    list[id] = nil
end

RegisterNetEvent('nz_cargo:untrack', function(id) dropTrack(tracked, id) dropTrack(hot, id) end)

-- stale blips fade out on their own
CreateThread(function()
    while true do
        Wait(10000)
        local now = GetGameTimer()
        for id, t in pairs(tracked) do if now - t.seen > 20000 then dropTrack(tracked, id) end end
        for id, t in pairs(hot) do if now - t.seen > 75000 then dropTrack(hot, id) end end
    end
end)

-----------------------------------------------------------------
-- Texts from an unknown number when no phone resource took them
-----------------------------------------------------------------
RegisterNetEvent('nz_cargo:sms', function(m)
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    Client.Send('sms', m)
end)

-----------------------------------------------------------------
-- Crew radio (channel picked by the server for the job)
-----------------------------------------------------------------
local radioPrev
RegisterNetEvent('nz_cargo:radio', function(d)
    if type(d) ~= 'table' then return end
    if d.join then
        local ok = d.display
        if not ok then
            radioPrev = Bridge.RadioCurrent()
            ok = Bridge.JoinRadio(d.channel)
        end
        if ok then
            Client.radio = d.channel
            Client.Send('radio', { channel = d.channel })
            Bridge.Notify(L('radio_join', d.channel), 'info', 'Crew radio')
        end
    elseif Client.radio == d.channel then
        if not d.display then Bridge.LeaveRadio(d.channel, radioPrev) end
        Client.radio, radioPrev = nil, nil
        Client.Send('radio', { channel = false })
        Bridge.Notify(L('radio_leave'), 'info', 'Crew radio')
    end
end)

RegisterNetEvent('nz_cargo:levelUp', function(level, prestige)
    Client.Send('levelUp', { level = level, prestige = prestige })
end)

-----------------------------------------------------------------
-- Movable mission HUD (/cargohud), saved per player
-----------------------------------------------------------------
local function hudPos()
    local raw = GetResourceKvpString('nz_cargo_hud')
    return raw and json.decode(raw) or nil
end

RegisterCommand(Config.Hud.Command, function()
    if Client.nui then return end
    Client.nui = true
    SetNuiFocus(true, true)
    Client.Send('hudEdit', { pos = hudPos() })
end, false)

handlers.prefs = function(d)
    local res = lib.callback.await('nz_cargo:prefs', false, d)
    if not res then return { ok = false } end
    -- your own warehouse: this is now your look everywhere
    if res.role == 'owner' then Client.prefs = res.prefs end
    return res
end

handlers.hudSave = function(d)
    if d.reset then
        DeleteResourceKvp('nz_cargo_hud')
    elseif not d.cancel and tonumber(d.x) and tonumber(d.y) then
        SetResourceKvp('nz_cargo_hud', json.encode({ x = math.floor(d.x), y = math.floor(d.y) }))
    end
    Client.nui = false
    SetNuiFocus(false, false)
    return true
end

-- "Move HUD now" from the laptop Settings app
handlers.hudMove = function()
    if Laptop and Laptop.open then Laptop.Close() end
    CreateThread(function()
        Wait(900)
        ExecuteCommand(Config.Hud.Command)
    end)
    return true
end

-----------------------------------------------------------------
-- Boot
-----------------------------------------------------------------
local function boot()
    while not lib.callback.await('nz_cargo:ready', false) do Wait(1000) end
    Client.static = nil
    Client.Static()
    Client.Send('hudPos', { pos = hudPos() })
    Client.Refresh()
    Client.booted = true
end

-----------------------------------------------------------------
-- Spawned inside the interior without being in a warehouse
-- (server restart, relog, character switch: the framework saved
-- your position inside). The server puts you back in your own
-- warehouse, or walks you out the front door. No multicharacter
-- hooks needed: it only looks at where your ped actually is.
-----------------------------------------------------------------
local function inInterior()
    local i = Config.Interior
    local p = GetEntityCoords(cache.ped)
    if #(p - i.Coords) < 70.0 then return true end
    return i.Lower and #(p - i.Lower.Coords) < 45.0 or false
end

local function stray()
    return Client.booted and not Client.inside and not Client.mission and not Client.warping
        and not IsPlayerSwitchInProgress() and IsScreenFadedIn() and inInterior()
end

local nextTry = 0
local function resume()
    local res = lib.callback.await('nz_cargo:resume', false)
    -- nothing to do (no character yet, or another script owns this player): back off
    if not res then nextTry = GetGameTimer() + 15000 return end
    if res.enter then
        -- the server already has them in the warehouse bucket
        Warehouse.Load(res.enter)
    elseif res.door and stray() then
        Client.Fade(true)
        Client.Teleport(res.door, (res.door.w or 0.0) + 180.0)
        Client.Fade(false)
        Bridge.Notify(L('resume_out'), 'info', 'Vehicle Cargo')
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        -- seen twice in a row, so a door teleport in progress never trips it
        if Config.Resume.Enabled and GetGameTimer() > nextTry and stray() then
            Wait(1500)
            if stray() then resume() end
        end
    end
end)

CreateThread(function()
    Wait(1500)
    if NetworkIsPlayerActive(PlayerId()) then boot() end
end)
Bridge.OnLoaded(function() CreateThread(boot) end)
Bridge.OnUnload(function()
    if Client.mission and Client.mission.cancel then Client.mission.cancel() end
    if Client.inside then Warehouse.Cleanup() end
    Client.ClosePrompts()
    clearDoors()
    Client.access = {}
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearDoors()
    clearBrokers()
    Client.ClosePrompts()
    if Client.nui then SetNuiFocus(false, false) end
end)
