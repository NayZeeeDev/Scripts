-- ═══════════════════════════════════════════════════════════
--  DISPATCH — alerts, blips, panic, on-screen card
-- ═══════════════════════════════════════════════════════════

Dispatch = {
    blips   = {},      -- [ref] = { blip, radius, expires }
    feed    = {},      -- newest calls first, for the card
    widget  = false,
    panics  = {},      -- [identifier] = { name, callsign, street, x, y, z, blip, expires }
    index   = 0,
    lastActivity = 0
}

local MAX_FEED = Config.Widget and Config.Widget.maxCalls or 10

local function soundsOn() return MDT.setting('sounds', true) ~= false end

-- ═══════════════════════════════════════════════════════════
--  BLIPS
-- ═══════════════════════════════════════════════════════════
local function dropBlip(ref)
    local entry = Dispatch.blips[ref]
    if not entry then return end
    if entry.blip and DoesBlipExist(entry.blip) then RemoveBlip(entry.blip) end
    if entry.radius and DoesBlipExist(entry.radius) then RemoveBlip(entry.radius) end
    Dispatch.blips[ref] = nil
end

local function placeBlip(call, sprite, colour, duration, radius)
    if not call.x or not call.y then return end
    dropBlip(call.ref)

    local blip = AddBlipForCoord(call.x + 0.0, call.y + 0.0, (call.z or 0.0) + 0.0)
    SetBlipSprite(blip, sprite or 280)
    SetBlipColour(blip, colour or 1)
    SetBlipScale(blip, 0.85)
    SetBlipAsShortRange(blip, false)
    SetBlipFlashes(blip, call.priority == 1)
    if call.priority == 1 then SetBlipFlashTimer(blip, 8000) end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('%s · %s'):format(call.ref, call.title))
    EndTextCommandSetBlipName(blip)

    local area
    if radius and radius > 0 then
        area = AddBlipForRadius(call.x + 0.0, call.y + 0.0, (call.z or 0.0) + 0.0, radius + 0.0)
        SetBlipColour(area, colour or 1)
        SetBlipAlpha(area, 70)
    end

    Dispatch.blips[call.ref] = {
        blip = blip, radius = area,
        expires = GetGameTimer() + ((duration or 300) * 1000)
    }
end

local function dropPanic(identifier)
    local p = Dispatch.panics[identifier]
    if not p then return end
    if p.blip and DoesBlipExist(p.blip) then RemoveBlip(p.blip) end
    Dispatch.panics[identifier] = nil
end

-- ═══════════════════════════════════════════════════════════
--  ON-SCREEN DISPATCH CARD
--  One call at a time, paged with the keyboard. It never takes
--  NUI focus, so the player keeps driving while they read it.
-- ═══════════════════════════════════════════════════════════
local function keyLabels()
    local k = Config.Widget.keys
    return { prev = k.prev.key, next = k.next.key, accept = k.accept.key }
end

--- Panics sit ahead of calls, same order the card draws them.
local function entries()
    local out = {}
    for _, p in pairs(Dispatch.panics) do out[#out + 1] = { kind = 'panic', data = p } end
    for _, c in ipairs(Dispatch.feed) do out[#out + 1] = { kind = 'call', data = c } end
    return out
end

local function pushWidget(open)
    local panics = {}
    for identifier, p in pairs(Dispatch.panics) do
        panics[identifier] = { name = p.name, callsign = p.callsign, street = p.street, x = p.x, y = p.y }
    end
    local pos = GetEntityCoords(PlayerPedId())

    SendNUIMessage({
        action = 'widget',
        open   = open,
        data   = {
            calls    = Dispatch.feed,
            panics   = panics,
            index    = Dispatch.index,
            keys     = keyLabels(),
            position = Config.Widget.position,
            me       = MDT.identifier,
            pos      = { x = pos.x, y = pos.y }
        }
    })
end

function Dispatch.showWidget(open)
    if not Config.Widget.enabled then return end
    if MDT.isOpen then return end

    Dispatch.widget = open
    if open then Dispatch.lastActivity = GetGameTimer() end
    pushWidget(open)
end

function Dispatch.toggleWidget()
    Dispatch.showWidget(not Dispatch.widget)
end

--- Move through the queue, wrapping at both ends.
function Dispatch.page(step)
    if not Dispatch.widget then return end

    local list = entries()
    if #list == 0 then return end

    Dispatch.index = (Dispatch.index + step) % #list
    if Dispatch.index < 0 then Dispatch.index = Dispatch.index + #list end

    Dispatch.lastActivity = GetGameTimer()
    pushWidget(true)
    PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

local function refreshFeed()
    local board = lib.callback.await('nz_mdt:dispatch:board', false, false)
    if board and board.ok then
        Dispatch.feed = {}
        for i, c in ipairs(board.calls) do
            if i > MAX_FEED then break end
            Dispatch.feed[#Dispatch.feed + 1] = c
        end
    end
end

--- Attach to the call on screen and take the route.
function Dispatch.accept()
    if not Dispatch.widget then return end

    local entry = entries()[Dispatch.index + 1]
    if not entry then return end
    Dispatch.lastActivity = GetGameTimer()

    if entry.kind == 'panic' then
        local p = entry.data
        if p.x then
            SetNewWaypoint(p.x + 0.0, p.y + 0.0)
            lib.notify({ title = 'Responding', description = ('Routing to %s.'):format(p.callsign or p.name), type = 'inform' })
        end
        return
    end

    local call = entry.data
    local res = lib.callback.await('nz_mdt:dispatch:attach', false, call.id)

    if res and res.ok then
        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        if Config.Widget.routeOnAccept and call.x then SetNewWaypoint(call.x + 0.0, call.y + 0.0) end
        lib.notify({ title = 'Responding', description = ('You are attached to %s.'):format(call.ref), type = 'success' })
        refreshFeed()
        pushWidget(true)
    else
        lib.notify({ title = 'Dispatch', description = res and res.msg or 'That did not go through.', type = 'error' })
    end
end

-- ── commands and keybinds ───────────────────────────────────
RegisterCommand('dispatchwidget', function() Dispatch.toggleWidget() end, false)
if Config.DispatchKey then
    RegisterKeyMapping('dispatchwidget', 'Toggle the dispatch card', 'keyboard', Config.DispatchKey)
end

do
    local k = Config.Widget.keys

    RegisterCommand(k.prev.command, function() Dispatch.page(-1) end, false)
    RegisterKeyMapping(k.prev.command, 'Dispatch — previous call', 'keyboard', k.prev.key)

    RegisterCommand(k.next.command, function() Dispatch.page(1) end, false)
    RegisterKeyMapping(k.next.command, 'Dispatch — next call', 'keyboard', k.next.key)

    RegisterCommand(k.accept.command, function() Dispatch.accept() end, false)
    RegisterKeyMapping(k.accept.command, 'Dispatch — respond to the call', 'keyboard', k.accept.key)
end

--- One slow housekeeping loop: expire blips and panics, fade an idle card.
CreateThread(function()
    while true do
        Wait(2000)
        local now = GetGameTimer()

        for ref, entry in pairs(Dispatch.blips) do
            if entry.expires and now > entry.expires then dropBlip(ref) end
        end

        local panicGone = false
        for identifier, p in pairs(Dispatch.panics) do
            if p.expires and now > p.expires then dropPanic(identifier) panicGone = true end
        end

        if Dispatch.widget then
            if Config.Widget.autoHide > 0 and now - Dispatch.lastActivity > Config.Widget.autoHide * 1000 then
                Dispatch.showWidget(false)
            elseif panicGone then
                pushWidget(true)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  INCOMING ALERTS
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('nz_mdt:alert', function(payload)
    if type(payload) ~= 'table' or type(payload.call) ~= 'table' then return end
    local call = payload.call

    table.insert(Dispatch.feed, 1, call)
    while #Dispatch.feed > MAX_FEED do table.remove(Dispatch.feed) end

    -- a fresh call takes the card, so the player sees it without paging
    Dispatch.index = 0
    Dispatch.lastActivity = GetGameTimer()

    if Config.Dispatch.blipDuration > 0 then
        placeBlip(call, payload.blip, payload.colour, payload.duration, payload.radius)
    end

    if payload.sound and soundsOn() then
        PlaySoundFrontend(-1, call.priority == 1 and 'Lose_1st' or 'Menu_Accept', 'Phone_SoundSet_Default', true)
    end

    if MDT.isOpen then
        -- the tablet already got dispatch:new through the live channel
        return
    end

    if payload.widget and Config.Widget.autoShow and MDT.setting('widgetAuto', true) ~= false then
        Dispatch.widget = true
        pushWidget(true)
    elseif Dispatch.widget then
        pushWidget(true)
    end

    lib.notify({
        title       = ('%s · %s'):format(call.code or '10-00', call.title),
        description = call.street or 'Location unknown',
        type        = call.priority == 1 and 'error' or 'inform',
        position    = 'top-right',
        duration    = 7000
    })
end)

RegisterNetEvent('nz_mdt:panicAlert', function(data)
    if type(data) ~= 'table' or not data.identifier then return end

    dropPanic(data.identifier)
    local entry = {
        name = data.name, callsign = data.callsign, street = data.street,
        x = data.x, y = data.y, z = data.z,
        expires = GetGameTimer() + (data.duration or 120) * 1000
    }

    if data.sound and soundsOn() then
        PlaySoundFrontend(-1, 'Lose_1st', 'Phone_SoundSet_Default', true)
    end

    if Config.Panic.autoBlip and data.x then
        local blip = AddBlipForCoord(data.x + 0.0, data.y + 0.0, (data.z or 0.0) + 0.0)
        SetBlipSprite(blip, 303)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 1.1)
        SetBlipFlashes(blip, true)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(('PANIC — %s'):format(data.callsign or data.name))
        EndTextCommandSetBlipName(blip)
        entry.blip = blip
    end

    Dispatch.panics[data.identifier] = entry

    if MDT.isOpen then
        SendNUIMessage({ action = 'live', event = 'panic', data = data })
    else
        Dispatch.index = 0
        Dispatch.widget = Config.Widget.enabled
        if Dispatch.widget then Dispatch.lastActivity = GetGameTimer() pushWidget(true) end
    end

    lib.notify({
        title       = 'PANIC BUTTON',
        description = ('%s — %s'):format(data.callsign or data.name, data.street or 'unknown location'),
        type        = 'error',
        position    = 'top-right',
        duration    = 10000
    })
end)

--- The panicking officer's position, relayed while the panic is live.
RegisterNetEvent('nz_mdt:panicMove', function(identifier, x, y, z, street)
    local p = Dispatch.panics[identifier]
    if not p or type(x) ~= 'number' or type(y) ~= 'number' then return end
    p.x, p.y, p.z = x, y, z or p.z
    if street then p.street = street end
    if p.blip and DoesBlipExist(p.blip) then SetBlipCoords(p.blip, x + 0.0, y + 0.0, (z or 0.0) + 0.0) end

    if MDT.isOpen then
        SendNUIMessage({ action = 'live', event = 'panic:move', data = { identifier = identifier, x = x, y = y } })
    end
end)

--- We hit the panic button: report where we are until it times out.
RegisterNetEvent('nz_mdt:panicTrack', function(seconds, every)
    local untilAt = GetGameTimer() + (tonumber(seconds) or 120) * 1000
    local step = math.max(2, tonumber(every) or 3) * 1000
    CreateThread(function()
        local last
        while GetGameTimer() < untilAt do
            Wait(step)
            local pos = GetEntityCoords(PlayerPedId())
            if not last or #(pos - last) > 5.0 then
                last = pos
                TriggerServerEvent('nz_mdt:panic:pos', pos.x, pos.y, pos.z, MDT.streetName(pos))
            end
        end
    end)
end)

--- Board changes reach every on-duty unit, tablet open or not.
RegisterNetEvent('nz_mdt:live', function(event, payload)
    if event == 'dispatch:closed' and type(payload) == 'table' then
        if payload.all then
            for ref in pairs(Dispatch.blips) do dropBlip(ref) end
            Dispatch.feed = {}
        elseif payload.ref then
            dropBlip(payload.ref)
            for i = #Dispatch.feed, 1, -1 do
                if Dispatch.feed[i].ref == payload.ref then table.remove(Dispatch.feed, i) end
            end
        end
        if Dispatch.widget then pushWidget(true) end
    elseif event == 'dispatch:update' and type(payload) == 'table' and payload.ref then
        for i, call in ipairs(Dispatch.feed) do
            if call.ref == payload.ref then Dispatch.feed[i] = payload break end
        end
        if Dispatch.widget then pushWidget(true) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for ref in pairs(Dispatch.blips) do dropBlip(ref) end
    for identifier in pairs(Dispatch.panics) do dropPanic(identifier) end
end)

-- ═══════════════════════════════════════════════════════════
--  AUTOMATIC GUNSHOT DETECTION
--  Event driven — nothing runs until a shot is actually fired.
--  The game raises CEventGunShot on the shooter's own client
--  with the peds that heard it, so only the shooter reports it.
-- ═══════════════════════════════════════════════════════════
local shots = Config.Alerts and Config.Alerts.shotsFired
if shots and shots.enabled then
    local ignored = {}
    for _, name in ipairs(shots.ignoredWeapons or {}) do ignored[joaat(name)] = true end
    local nextAllowed = 0

    AddEventHandler('CEventGunShot', function(witnesses, shooter)
        local ped = PlayerPedId()
        if shooter ~= ped then return end

        local now = GetGameTimer()
        if now < nextAllowed then return end

        -- department members on duty never trip it
        if shots.ignoreJobs and MDT.onDuty then return end
        if shots.requireWitness and (type(witnesses) ~= 'table' or #witnesses == 0) then return end
        if IsPedCurrentWeaponSilenced(ped) then return end

        local _, weapon = GetCurrentPedWeapon(ped, true)
        if ignored[weapon] then return end

        nextAllowed = now + (shots.cooldown or 900) * 1000

        local pos = GetEntityCoords(ped)
        TriggerServerEvent('nz_mdt:alert:shotsFired', MDT.streetName(pos), pos.x, pos.y, pos.z)
    end)
end
