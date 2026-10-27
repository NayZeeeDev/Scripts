--[[
    Phone app, server side.

    The app controls speakers from a distance, so main.lua's Guard() (which wants the player standing
    at the speaker) would turn every phone command down. Phone requests are checked here instead:
        allowed(src)        the app is enabled and the player has the item it needs (if any)
        reachable(me, e)    the player may control this speaker from where they are right now
    and only then handed to the normal playback code, with a pass for exactly that one call (PhonePass).
]]
local P = Config.Phone
local OTHERS_RANGE = 25.0      -- with range = 0, other people's speakers still have to be this close
local MAX_LISTED = 40          -- speakers one phone lists at most (admins can reach every speaker)

---------------------------------------------------------------- who may do what
local function allowed(src)
    if not P.enabled then return false end
    local item = P.needItem or ''
    return item == '' or (Bridge.HasItem(src, item) and true or false)
end

-- everything about the player a check needs, looked up once per request
local function who(src)
    local ped = GetPlayerPed(src)
    return { src = src, ped = ped, id = Bridge.GetIdentifier(src), coords = ped ~= 0 and GetEntityCoords(ped) or nil }
end

local function isAdmin(me)
    if me.admin == nil then me.admin = Bridge.IsAdmin(me.src) and true or false end
    return me.admin
end

-- true, or false + the locale key that says why not
local function reachable(me, e)
    if not e then return false, 'no_access' end
    if e.kind == 'jam' then
        -- a jam has no place in the world: its members control it from anywhere
        if Social and Social.CanUseJam(me.src, e) then return true end
        return false, 'no_access'
    end
    if me.ped == 0 then return false, 'too_far' end
    if e.kind == 'vehicle' then
        -- only while you're sitting in that car
        local veh = NetworkGetEntityFromNetworkId(e.vehNet or 0)
        if veh == 0 or GetVehiclePedIsIn(me.ped, false) ~= veh then return false, 'too_far' end
        if Config.Carplay.controlBy == 'driver' and GetPedInVehicleSeat(veh, -1) ~= me.ped and not isAdmin(me) then
            return false, 'not_driver'
        end
        return true
    end
    local mine = e.owner == me.id
    if e.access == 'owner' and not mine and not isAdmin(me) then return false, 'no_access' end
    local range = tonumber(P.range) or 0
    if range <= 0 then
        if mine or isAdmin(me) then return true end
        range = OTHERS_RANGE
    end
    local pos = EmitterPosition(e)
    if not pos or not me.coords or not (#(me.coords - pos) <= range) then return false, 'too_far' end
    return true
end

-- the speaker a phone request is for, or nil (after telling the player why)
local function target(src, id)
    if type(id) ~= 'string' or not allowed(src) then return nil end
    local e = Emitters[id]
    local ok, why = reachable(who(src), e)
    if not ok then
        if e then Notify(src, why or 'no_access') end
        return nil
    end
    return e
end

---------------------------------------------------------------- remote control
--[[
    Guard() asks PhonePass first. One checked phone call may pass it for the same player and speaker,
    music control only (never pick up / pack up). Guard() runs before anything in those calls can
    yield, so the pass is used up (or cleared by remote()) within the same tick and can't leak into
    another request.
]]
local pass

function PhonePass(src, id, control)
    local p = pass
    if not p or not control or p.src ~= src or p.id ~= id then return false end
    pass = nil
    return true
end

local function remote(src, id, fn, ...)
    local p = { src = src, id = id }
    pass = p
    local ok, err = pcall(fn, ...)
    if pass == p then pass = nil end
    if not ok then print(('^1[%s] phone command failed: %s^7'):format(RES, err)) end
end

---------------------------------------------------------------- callbacks
-- Which speakers this player can control from the phone right now. The client adds the live
-- state (track, position, volume...) from its own copy of every speaker, so this stays small.
NZ.RegisterCallback('phone:list', function(src)
    if not allowed(src) then return {} end
    local me = who(src)
    local out = {}
    for id, e in pairs(Emitters) do
        if reachable(me, e) then
            local pos = e.kind ~= 'jam' and me.coords and EmitterPosition(e) or nil
            out[#out + 1] = { id = id, mine = e.owner == me.id, d = pos and math.floor(#(me.coords - pos) + 0.5) or 0 }
        end
    end
    table.sort(out, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        return a.d < b.d
    end)
    for i = #out, MAX_LISTED + 1, -1 do out[i] = nil end
    return out
end)

---------------------------------------------------------------- music commands
local ACTIONS = {
    toggle = true, pause = true, next = true, prev = true, stop = true, seek = true,
    volume = true, loop = true, shuffle = true, queuePlay = true, queueRemove = true,
}

RegisterNetEvent(RES .. ':phone:action', function(id, what, value)
    local src = source
    if not ACTIONS[what] or not target(src, id) then return end
    remote(src, id, ActionFor, src, what, id, value)
end)

-- play or queue one song (a search result, a liked song, a playlist entry)
RegisterNetEvent(RES .. ':phone:play', function(id, saved, mode)
    local src = source
    if type(saved) ~= 'table' or not target(src, id) then return end
    remote(src, id, PlaySavedFor, src, id, saved, mode == 'queue' and 'queue' or 'now')
end)

-- a whole list (Liked Songs or a playlist), from song `start`, optionally shuffled
RegisterNetEvent(RES .. ':phone:playList', function(id, which, start, shuffle)
    local src = source
    local e = target(src, id)
    if e then Playlists.Play(src, e, which, { start = start, shuffle = shuffle == true }) end
end)

exports('PhoneCanUse', function(src) return allowed(src) end)
