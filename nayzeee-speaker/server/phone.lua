-- Phone app: control speakers you have access to without standing next to them.
local RES = GetCurrentResourceName()

local function reachable(src, e)
    if not e then return false end
    if e.kind == 'vehicle' then
        -- only while you're actually in that car
        local veh = NetworkGetEntityFromNetworkId(e.vehNet)
        return veh ~= 0 and GetVehiclePedIsIn(GetPlayerPed(src), false) == veh
    end
    local id = Bridge.GetIdentifier(src)
    local mine = e.owner == id
    local admin = Bridge.IsAdmin(src)
    if not mine and not admin and e.access == 'owner' then return false end

    local range = Config.Phone.range or 0
    if range > 0 then
        local pos = EmitterPosition(e)
        local ped = GetPlayerPed(src)
        if not pos or ped == 0 or #(GetEntityCoords(ped) - pos) > range then return false end
    elseif not mine and not admin then
        -- with no range limit, non-owners still have to be near it
        local pos = EmitterPosition(e)
        local ped = GetPlayerPed(src)
        if not pos or ped == 0 or #(GetEntityCoords(ped) - pos) > 25.0 then return false end
    end
    return true
end
PhoneReachable = reachable

local function allowed(src)
    if not Config.Phone.enabled then return false end
    local item = Config.Phone.needItem or ''
    if item ~= '' and not Bridge.HasItem(src, item) then return false end
    return true
end

-- Speakers this player can control right now
NZ.RegisterCallback('phone:list', function(src)
    if not allowed(src) then return {} end
    local id = Bridge.GetIdentifier(src)
    local ped = GetPlayerPed(src)
    local me = ped ~= 0 and GetEntityCoords(ped) or nil
    local out = {}
    for eid, e in pairs(Emitters) do
        if reachable(src, e) then
            local pos = EmitterPosition(e)
            out[#out + 1] = {
                id = eid, kind = e.kind, label = e.kind == 'vehicle' and 'CarPlay' or (e.label or 'Speaker'),
                mine = e.owner == id,
                distance = (me and pos) and math.floor(#(me - pos)) or 0,
                playing = e.playing, turntable = IsTurntable(e),
                group = e.group, groupSize = e.group and Groups[e.group] and #Groups[e.group].members or 0,
                track = e.track and {
                    src = e.track.src, id = e.track.id, url = e.track.src == 'url' and e.track.url or nil,
                    title = e.track.title, author = e.track.author, duration = e.track.duration, thumb = e.track.thumb,
                } or nil,
                volume = e.volume, queue = #(e.queue or {}),
                health = e.health, maxHealth = Config.Damage.health,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.playing ~= b.playing then return a.playing end
        return a.distance < b.distance
    end)
    return out
end)

-- Song search from the phone (and from the player's own search box)
local lastSearch = {}
local function searchCooldown(src)
    local t = GetGameTimer()
    if lastSearch[src] and t - lastSearch[src] < 700 then return false end
    lastSearch[src] = t
    return true
end

NZ.RegisterCallback('search', function(src, query)
    if not Config.Search.enabled then return {} end
    if not searchCooldown(src) then return {} end
    return Search.Query(query, Config.Search.results)
end)

AddEventHandler('playerDropped', function() lastSearch[source] = nil end)

-- Play / queue a searched song from the phone
RegisterNetEvent(RES .. ':phone:play', function(emitterId, videoId, mode)
    local src = source
    if not allowed(src) then return end
    local e = Emitters[emitterId]
    if not e or not reachable(src, e) then return Notify(src, 'no_access') end
    if e.access == 'owner' and e.owner ~= Bridge.GetIdentifier(src) and not Bridge.IsAdmin(src) then
        return Notify(src, 'no_access')
    end
    PlayFor(src, emitterId, videoId, mode)
end)

RegisterNetEvent(RES .. ':phone:playSaved', function(emitterId, saved, mode)
    local src = source
    if not allowed(src) then return end
    local e = Emitters[emitterId]
    if not e or not reachable(src, e) then return Notify(src, 'no_access') end
    PlaySavedFor(src, emitterId, saved, mode)
end)

-- Simple remote actions
RegisterNetEvent(RES .. ':phone:action', function(emitterId, what, value)
    local src = source
    if not allowed(src) then return end
    local e = Emitters[emitterId]
    if not e or not reachable(src, e) then return Notify(src, 'no_access') end
    local allow = { toggle = true, next = true, prev = true, stop = true, volume = true, loop = true, shuffle = true, pause = true }
    if not allow[what] then return end
    ActionFor(src, what, emitterId, value)
end)

exports('PhoneCanUse', function(src) return allowed(src) end)
