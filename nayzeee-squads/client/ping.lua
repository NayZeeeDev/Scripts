-- Squad pings: tap to ping where you look, hold to open the wheel.
local Types = Config.Ping.Types
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

local function clearPings() for k in pairs(Pings) do removePing(k) end end

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
    local hit, entity, coords = lib.raycast.cam(511, 4, Config.Ping.MaxDistance)
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

    local ttl = Config.Ping.TTL
    if data.type == 'waypoint' then ttl = Config.Ping.WaypointTTL
    elseif data.type == 'downed' then ttl = 45
    elseif data.net then ttl = Config.Ping.FollowTTL end

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

    Pings[key] = { coords = coords, net = data.net, blip = blip, color = def.color, label = def.label, expires = GetGameTimer() + ttl * 1000 }
    startDraw()

    if data.from ~= Me() then
        local isDown = data.type == 'downed'
        if isDown then
            if not Settings.reviveAlerts then return end
            Notify(('%s is down'):format(data.name), 'warning', 'downed', true)
            PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', true)
            return
        end
        if Settings.pingNotify then Notify(('%s: %s'):format(data.name, def.label), 'inform', 'ping') end
        if Settings.pingSound and not Settings.quiet then PlaySoundFrontend(-1, Config.Ping.Sound.name, Config.Ping.Sound.set, true) end
    end
end)

-- ─── input ─────────────────────────────────────────────────
-- The wheel takes the mouse for aiming the selection while the game keeps keyboard input.
local BLOCKED = {
    1, 2, 24, 25, 257, 263, 264, 140, 141, 142, 37,
    68, 69, 70, 91, 92, 114, 106, 199, 200, 322, 177,
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
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    NUI('wheel', true)
    blockWhileOpen()
end

local function closeWheel()
    wheelOpen = false
    SetNuiFocusKeepInput(false)
    if not MenuOpen then SetNuiFocus(false, false) end
    NUI('wheel', false)
end

if Config.Features.Pings then
    lib.addKeybind({
        name = 'nz_squads_ping',
        description = 'Squads: ping (tap) / ping wheel (hold)',
        defaultMapper = Config.Ping.Mapper,
        defaultKey = Config.Ping.Key,
        onPressed = function()
            if not Squad or MenuOpen or wheelOpen or IsPauseMenuActive() or IsNuiFocused() then return end
            holding, pressAt = true, GetGameTimer()
            SetTimeout(Config.Ping.HoldMs, function()
                if holding and not wheelOpen and Squad then openWheel() end
            end)
        end,
        onReleased = function()
            if not holding then return end
            holding = false
            if wheelOpen then
                NUI('wheelRelease')
            elseif GetGameTimer() - pressAt < Config.Ping.HoldMs then
                sendPing('go')
            end
        end,
    })
end

RegisterNUICallback('wheelSelect', function(data, cb)
    cb(1)
    holding = false
    closeWheel()
    if data and data.type then sendPing(data.type) end
end)

RegisterNUICallback('wheelCancel', function(_, cb)
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
