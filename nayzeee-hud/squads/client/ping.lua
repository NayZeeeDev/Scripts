-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- Squad pings: tap to ping, hold to open the wheel.
local Types = SquadsConfig.Ping.Types
local Pings = {}           -- [key] = ping
local drawing = false
local holding, wheelOpen, pressAt = false, false, 0

local function removePing(key)
    local p = Pings[key]
    if p and p.blip and DoesBlipExist(p.blip) then RemoveBlip(p.blip) end
    Pings[key] = nil
end

--- Live pings for the compass: { coords, color, label }.
function CompassPings()
    local out = {}
    for _, p in pairs(Pings) do
        local pos = p.coords
        if p.net and NetworkDoesNetworkIdExist(p.net) then
            local ent = NetworkGetEntityFromNetworkId(p.net)
            if ent ~= 0 and DoesEntityExist(ent) then pos = GetEntityCoords(ent) end
        end
        out[#out + 1] = { coords = pos, color = p.color, label = p.label }
    end
    return out
end

local function clearPings()
    for k in pairs(Pings) do removePing(k) end
end

local function drawLabel(x, y, z, text, r, g, b)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(r, g, b, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function startDraw()
    if drawing then return end
    drawing = true
    CreateThread(function()
        while next(Pings) do
            local now = GetGameTimer()
            local me = GetEntityCoords(cache.ped)
            for key, p in pairs(Pings) do
                if now >= p.expires then
                    removePing(key)
                else
                    local pos = p.coords
                    if p.net and NetworkDoesNetworkIdExist(p.net) then
                        local ent = NetworkGetEntityFromNetworkId(p.net)
                        if ent ~= 0 and DoesEntityExist(ent) then
                            pos = GetEntityCoords(ent)
                            if p.blip then SetBlipCoords(p.blip, pos.x, pos.y, pos.z) end
                        end
                    end
                    local c = p.color
                    local dist = #(pos - me)
                    local lift = p.net and 1.4 or 0.9
                    DrawMarker(2, pos.x, pos.y, pos.z + lift, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                        0.35, 0.35, 0.35, c[1], c[2], c[3], 210, false, true, 2, false, nil, nil, false)
                    drawLabel(pos.x, pos.y, pos.z + lift + 0.45, ('%s  %dm'):format(p.label, math.floor(dist)), c[1], c[2], c[3])
                end
            end
            Wait(0)
        end
        drawing = false
    end)
end

local function sendPing(kind)
    if not Squad then return end
    local def = Types[kind]
    if not def then return end
    local hit, entity, coords = lib.raycast.cam(511, 4, SquadsConfig.Ping.MaxDistance)
    if not hit or not coords then return end

    if kind == 'go' and entity and entity ~= 0 and GetEntityType(entity) == 2 then kind = 'vehicle' end

    local net
    if (kind == 'vehicle' or kind == 'enemy') and entity and entity ~= 0 then
        local t = GetEntityType(entity)
        if (t == 1 or t == 2) and NetworkGetEntityIsNetworked(entity) then
            net = NetworkGetNetworkIdFromEntity(entity)
        end
    end
    TriggerServerEvent('nz_squads:ping', { type = kind, x = coords.x, y = coords.y, z = coords.z, net = net })
end

RegisterNetEvent('nz_squads:ping', function(data)
    if not Squad then return end
    local def = Types[data.type]
    if not def then return end

    local key = ('%d:%s'):format(data.from, data.type == 'waypoint' and 'wp' or (data.type == 'downed' and 'dn' or 'p'))
    removePing(key)

    local ttl = SquadsConfig.Ping.TTL
    if data.type == 'waypoint' then ttl = SquadsConfig.Ping.WaypointTTL
    elseif data.type == 'downed' then ttl = 45
    elseif data.net then ttl = SquadsConfig.Ping.FollowTTL end
    local coords = vec3(data.x, data.y, data.z)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, def.blip)
    SetBlipColour(blip, def.blipColor)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, false)
    SetBlipFlashes(blip, true)
    SetBlipFlashTimer(blip, 2500)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('%s - %s'):format(def.label, data.name))
    EndTextCommandSetBlipName(blip)
    if (data.type == 'waypoint' or data.type == 'downed') and data.from ~= Me() then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, def.blipColor)
    end

    Pings[key] = {
        coords = coords, net = data.net, blip = blip, color = def.color,
        label = def.label, expires = GetGameTimer() + ttl * 1000,
    }
    startDraw()

    if data.from ~= Me() then
        local isDown = data.type == 'downed'
        if isDown and not Settings.reviveAlerts then return end
        if Settings.pingNotify or isDown then NUI('pingToast', { type = data.type, name = data.name, auto = data.auto }) end
        if Settings.pingSound or isDown then
            PlaySoundFrontend(-1, isDown and 'Lose_1st' or SquadsConfig.Ping.Sound.name,
                isDown and 'GTAO_FM_Events_Soundset' or SquadsConfig.Ping.Sound.set, true)
        end
    end
end)

-- ─── input ─────────────────────────────────────────────────
-- The wheel takes the mouse for aiming the selection, but the game keeps keyboard input,
-- so you can keep walking, running or driving while it's open. Only looking around, firing
-- and the pause menu are blocked until it closes.
local BLOCKED = {
    1, 2,                       -- look left/right, up/down
    24, 25, 257, 263, 264,      -- attack, aim, melee attacks
    140, 141, 142,              -- melee light/heavy/alternate
    37,                         -- weapon wheel
    68, 69, 70, 91, 92, 114,    -- vehicle aim and attack
    106,                        -- vehicle mouse control override
    199, 200, 322, 177,         -- pause menu, ESC, cancel
}

local function blockWhileOpen()
    CreateThread(function()
        local player = PlayerId()
        while wheelOpen do
            for i = 1, #BLOCKED do DisableControlAction(0, BLOCKED[i], true) end
            DisablePlayerFiring(player, true)
            Wait(0)
        end
    end)
end

local function openWheel()
    wheelOpen = true
    SquadsFocus(true, true)
    SetNuiFocusKeepInput(true)
    NUI('wheel', true)
    blockWhileOpen()
end

local function closeWheel()
    wheelOpen = false
    SetNuiFocusKeepInput(false)
    if not MenuOpen then SquadsFocus(false, false) end
    NUI('wheel', false)
end

if SquadsConfig.Features.Pings then
    lib.addKeybind({
        name = 'nz_squads_ping',
        description = 'Squads: ping (tap) / ping wheel (hold)',
        defaultMapper = SquadsConfig.Ping.Mapper,
        defaultKey = SquadsConfig.Ping.Key,
        onPressed = function()
            if not Squad or MenuOpen or wheelOpen or IsPauseMenuActive() or IsNuiFocused() then return end
            holding, pressAt = true, GetGameTimer()
            SetTimeout(SquadsConfig.Ping.HoldMs, function()
                if holding and not wheelOpen and Squad then openWheel() end
            end)
        end,
        onReleased = function()
            if not holding then return end
            holding = false
            if wheelOpen then
                -- game input is kept while the wheel is open, so the release arrives here too:
                -- let the wheel place whatever slice is highlighted
                NUI('wheelRelease')
            elseif GetGameTimer() - pressAt < SquadsConfig.Ping.HoldMs then
                sendPing('go')
            end
        end,
    })
end

RegisterNUICallback('sq_wheelSelect', function(data, cb)
    cb(1)
    holding = false
    closeWheel()
    if data and data.type then sendPing(data.type) end
end)

RegisterNUICallback('sq_wheelCancel', function(_, cb)
    cb(1)
    holding = false
    closeWheel()
end)

AddEventHandler('nz_squads:client:changed', function(_, now)
    if not now then clearPings() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearPings()
    if wheelOpen then SetNuiFocusKeepInput(false) end
end)
