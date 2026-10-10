-- Top-of-screen compass with squadmate, ally, rally, waypoint and ping markers.
-- Heading is only sent when it moves; markers and the street name refresh twice a second.
if not Config.Features.Compass then return end

local C = Config.Compass
local running = false
local deg, atan2 = math.deg, math.atan

local function bearingTo(from, to)
    local b = deg(atan2(to.x - from.x, to.y - from.y))
    return (b + 360.0) % 360.0
end

local function camBearing()
    local rot = GetGameplayCamRot(2)
    return (360.0 - rot.z) % 360.0
end

local function wanted()
    if not Settings.compass then return false end
    if C.OnlyInSquad and not Squad then return false end
    return true
end

local function hexOf(r, g, b) return ('#%02x%02x%02x'):format(r, g, b) end
local function blipHex(id, fallback) return Config.BlipHex[id or -1] or fallback end

local function memberPos(id)
    local player = GetPlayerFromServerId(id)
    if player ~= -1 then
        local ped = GetPlayerPed(player)
        if ped ~= 0 and DoesEntityExist(ped) then return GetEntityCoords(ped) end
    end
    local v = Squad and Squad.vitals and Squad.vitals[tostring(id)]
    if v and v.x then return vec3(v.x + 0.0, v.y + 0.0, v.z + 0.0) end
    return nil
end

local function collectMarkers(me)
    local out = {}
    if not Settings.compassMarkers then return out end
    local range = C.MarkerRange

    local function add(pos, colour, kind, label)
        if not pos then return end
        local d = #(pos - me)
        if d < 2.0 or d > range then return end
        out[#out + 1] = { b = math.floor(bearingTo(me, pos) * 10 + 0.5) / 10, d = math.floor(d), c = colour, k = kind, n = label }
    end

    if Squad then
        local squadHex = blipHex(Squad.blipColor, '#08afa2')
        if C.ShowSquad then
            for i = 1, #Squad.members do
                local m = Squad.members[i]
                if m.online and m.id and m.id ~= Me() then
                    local v = Squad.vitals and Squad.vitals[tostring(m.id)]
                    local down = m.downed or (v and v.h == 0)
                    add(memberPos(m.id), down and '#e5484d' or squadHex, down and 'down' or 'mate', m.name)
                end
            end
        end
        if C.ShowAllies and Settings.blipAllies and Squad.allyMembers then
            for sid, a in pairs(Squad.allyMembers) do
                local id = tonumber(sid)
                local player = id and GetPlayerFromServerId(id) or -1
                if player ~= -1 then
                    local ped = GetPlayerPed(player)
                    if ped ~= 0 then add(GetEntityCoords(ped), blipHex(a.blipColor, '#58a6ff'), 'ally', a.name) end
                end
            end
        end
        if C.ShowRally and Squad.rally then
            add(vec3(Squad.rally.x, Squad.rally.y, Squad.rally.z), squadHex, 'rally', 'Rally')
        end
    end

    if C.ShowWaypoint then
        local wp = GetFirstBlipInfoId(8)
        if DoesBlipExist(wp) then add(GetBlipInfoIdCoord(wp), '#e5a50a', 'waypoint', 'Waypoint') end
    end

    if C.ShowPings and CompassPings then
        local pings = CompassPings()
        for i = 1, #pings do
            local p = pings[i]
            add(p.coords, hexOf(p.color[1], p.color[2], p.color[3]), 'ping', p.label)
        end
    end
    return out
end

local function streetAt(pos)
    local s1, s2 = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
    local street = GetStreetNameFromHashKey(s1)
    local cross = s2 ~= 0 and GetStreetNameFromHashKey(s2) or nil
    local zone = GetLabelText(GetNameOfZone(pos.x, pos.y, pos.z))
    if zone == 'NULL' then zone = nil end
    return street, cross, zone
end

local function start()
    if running or not wanted() then return end
    running = true
    NUI('compass', { show = true })

    CreateThread(function()
        local lastH, lastSlow = -1000.0, 0
        local lastMarkers, lastStreet = '', ''
        local hidden = false

        while wanted() do
            local hide = IsPauseMenuActive() or IsHudHidden() or (C.HideInVehicle and cache.vehicle)
            if hide ~= hidden then
                hidden = hide
                NUI('compass', { show = not hide })
            end

            if not hide then
                local h = camBearing()
                local diff = math.abs(h - lastH)
                if diff > 180 then diff = 360 - diff end
                if diff >= 0.4 then
                    lastH = h
                    NUI('compass', { h = math.floor(h * 10 + 0.5) / 10 })
                end

                local now = GetGameTimer()
                if now - lastSlow >= 500 then
                    lastSlow = now
                    local me = GetEntityCoords(cache.ped)

                    local markers = collectMarkers(me)
                    local sig = json.encode(markers)
                    if sig ~= lastMarkers then
                        lastMarkers = sig
                        NUI('compass', { markers = markers })
                    end

                    if C.ShowStreet and Settings.compassStreet then
                        local street, cross, zone = streetAt(me)
                        local key = (street or '') .. '|' .. (cross or '') .. '|' .. (zone or '')
                        if key ~= lastStreet then
                            lastStreet = key
                            NUI('compass', { street = street, cross = cross, zone = zone })
                        end
                    elseif lastStreet ~= '' then
                        lastStreet = ''
                        NUI('compass', { street = false })
                    end
                end
            end
            Wait(C.UpdateMs)
        end

        NUI('compass', { show = false })
        running = false
    end)
end

AddEventHandler('nz_squads:client:changed', function() start() end)
AddEventHandler('nz_squads:client:settings', function(prev, now)
    if now.compass and not prev.compass then start() end
end)

CreateThread(function()
    Wait(2500)
    start()
end)
