--[[
    NAYZEEE AMBULANCE - Transport (client): shared helpers, patient positioning, menus

    The server writes a replicated 'nzaTr' state bag on the patient (player or NPC ped):
        { m = 'carry'|'str'|'bed'|'bay'|'seat'|'free', n, c, s, b, bt, at, v, seat, slot, stand, from }
    Whoever owns the patient ped follows it: a player patient's own client, an NPC's network
    owner (the medic who acted requests control first). NPCs whose owner changed are kept in
    place by a 1 s scanner on every client.

    Helpers for the other transport files (runtime only):
        NZA.Transport.Cfg(section)  L(key, ...)  Toast(msg, type)  Err(res)  Call(name, ...) → ok, data
        Control(ent, ms) → bool     Ent(net, ms) → entity|0       Net(ent) → net|nil
        Play(ped, anim) / Playing(ped, anim) / StopAnim(ped, anim)
        Bag(ped) → nzaTr            StrBag(ent) → nzaStr          VehBag(veh) → nzaAmb
        VehCfg(veh) → config        Rear(veh, extra) → vector3    NearRear(veh, reach) → bool, dist
        Ground(v) → z               Busy() → reason|nil           Held(bag) → bool
        Apply(ped, cmd, isSelf)     position a patient ped for a command (attach, lie down, seat, free)
        NearestPatient(range, filter) → entity, target, bag
    Patient options (NZA.Interact, order band 10): Carry, Help up, Lift onto the stretcher, Take off the
    stretcher, Move to the bed / table, Help them down, Take out of the vehicle.
    Radial (NZA.RadialItems): parent 'patient' (carry, put down, help up) and 'stretcher' (see
    transport_stretcher.lua / transport_bay.lua).
    Bus (client) emitted: transport:mine (mode, cmd) when the local player is moved.
    Net events handled: nza:wounded:respawn (let go before the respawn teleport → nza:transport:selfRelease)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Transport = NZA.Transport or {}
local Tr = NZA.Transport
Tr.S = Tr.S or { carrying = nil, pushing = nil, bay = nil, mine = nil }
local S = Tr.S

local applied = {}          -- [ped] = last applied seq (n)
local heldModes = { carry = true, str = true, bed = true, bay = true, seat = true }
local mineLoop = false

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

function Tr.Cfg(section)
    local c = Config.Transport or {}
    if not section then return c end
    return c[section] or {}
end

function Tr.L(key, ...)
    return NZA.L('transport.' .. key, ...)
end

function Tr.Toast(msg, kind, title)
    if not msg or msg == '' then return end
    NZA.UI.Toast({ title = title or Tr.L('title'), message = msg, type = kind or 'info' })
end

function Tr.Err(res)
    local msg = type(res) == 'table' and (res.msg or (res.err and Tr.L('err_' .. res.err))) or nil
    Tr.Toast(msg or Tr.L('err_failed'), 'error')
end

function Tr.Call(name, ...)
    local ok, a, b = pcall(lib.callback.await, 'nza:transport:' .. name, false, ...)
    if not ok then return false, { err = 'failed' } end
    if a == true then return true, b or {} end
    return false, type(b) == 'table' and b or { err = 'failed' }
end

function Tr.Control(ent, ms)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    local t = GetGameTimer() + (ms or 1500)
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        Wait(50)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

function Tr.Ent(net, ms)
    net = tonumber(net)
    if not net then return 0 end
    local t = GetGameTimer() + (ms or 0)
    repeat
        if NetworkDoesNetworkIdExist(net) then
            local e = NetworkGetEntityFromNetworkId(net)
            if e and e ~= 0 and DoesEntityExist(e) then return e end
        end
        if (ms or 0) > 0 then Wait(50) end
    until GetGameTimer() >= t
    return 0
end

function Tr.Net(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    if not NetworkGetEntityIsNetworked(ent) then return nil end
    return NetworkGetNetworkIdFromEntity(ent)
end

local function loadDict(dict)
    if not dict then return false end
    if HasAnimDictLoaded(dict) then return true end
    local ok = pcall(lib.requestAnimDict, dict, 3000)
    return ok and HasAnimDictLoaded(dict)
end
Tr.LoadDict = loadDict

function Tr.Play(ped, anim, opts)
    if type(anim) ~= 'table' or not anim.dict then return false end
    if not loadDict(anim.dict) then return false end
    opts = opts or {}
    TaskPlayAnim(ped, anim.dict, anim.clip, opts.blendIn or 4.0, opts.blendOut or -4.0, opts.duration or anim.ms or -1,
        opts.flag or anim.flag or 1, 0.0, false, false, false)
    return true
end

function Tr.Playing(ped, anim)
    return type(anim) == 'table' and anim.dict and IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) or false
end

function Tr.StopAnim(ped, anim)
    if type(anim) == 'table' and anim.dict and IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
        StopAnimTask(ped, anim.dict, anim.clip, 2.0)
    end
end

function Tr.Bag(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    if IsPedAPlayer(ped) then
        if ped == PlayerPedId() then return LocalPlayer.state.nzaTr end
        local idx = NetworkGetPlayerIndexFromPed(ped)
        if not idx or idx == -1 then return nil end
        return Player(GetPlayerServerId(idx)).state.nzaTr
    end
    if not NetworkGetEntityIsNetworked(ped) then return nil end
    return Entity(ped).state.nzaTr
end

function Tr.StrBag(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) or not NetworkGetEntityIsNetworked(ent) then return nil end
    return Entity(ent).state.nzaStr
end

function Tr.VehBag(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) or not NetworkGetEntityIsNetworked(veh) then return nil end
    return Entity(veh).state.nzaAmb
end

function Tr.Held(bag)
    return type(bag) == 'table' and heldModes[bag.m] == true
end

local vehModels = nil
function Tr.VehCfg(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if not vehModels then
        vehModels = {}
        for name, c in pairs(Tr.Cfg('Stretcher').vehicles or {}) do vehModels[GetHashKey(name)] = c end
    end
    return vehModels[GetEntityModel(veh)]
end

function Tr.Rear(veh, extra)
    local c = Tr.VehCfg(veh) or {}
    local back = tonumber(c.rear)
    if not back then
        local mn = GetModelDimensions(GetEntityModel(veh))
        back = -mn.y
    end
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, -(back + (extra or 0.0)), 0.0)
end

function Tr.NearRear(veh, reach)
    local d = #(GetEntityCoords(PlayerPedId()) - Tr.Rear(veh, 0.35))
    return d <= (reach or Tr.Cfg('Stretcher').rearReach or 2.3), d
end

function Tr.Ground(v, fallback)
    local ok, gz = GetGroundZFor_3dCoord(v.x, v.y, v.z + 1.2, false)
    if ok and gz and math.abs(gz - v.z) < 4.0 then return gz end
    return fallback or v.z
end

function Tr.Busy()
    if S.carrying then return 'carry' end
    if S.pushing then return 'push' end
    if S.bay then return 'bay' end
    if NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then return 'down' end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return 'vehicle' end
    return nil
end

function Tr.V4(t)
    if type(t) ~= 'table' and type(t) ~= 'vector4' then return nil end
    local x, y, z = tonumber(t.x), tonumber(t.y), tonumber(t.z)
    if not x or not y or not z then return nil end
    return vector4(x, y, z, tonumber(t.w) or 0.0)
end

-- nearest patient ped within range (players + NPC patients), optional filter(ent, target, bag)
function Tr.NearestPatient(range, filter)
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local best, bestT, bestD = nil, nil, range or 3.0
    local function consider(ped)
        if ped == me or not DoesEntityExist(ped) then return end
        local d = #(pos - GetEntityCoords(ped))
        if d > bestD then return end
        local target = NZA.Target.FromEntity(ped)
        if not target then return end
        if filter and not filter(ped, target, NZA.Target.State(ped), Tr.Bag(ped)) then return end
        best, bestT, bestD = ped, target, d
    end
    for _, pl in ipairs(GetActivePlayers()) do consider(GetPlayerPed(pl)) end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) then consider(ped) end
    end
    return best, bestT
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT POSITIONING
-- ════════════════════════════════════════════════════════════════════════

local function carrierPed(sid)
    sid = tonumber(sid)
    if not sid then return 0 end
    if sid == GetPlayerServerId(PlayerId()) then return PlayerPedId() end
    local idx = GetPlayerFromServerId(sid)
    if not idx or idx == -1 then return 0 end
    local ped = GetPlayerPed(idx)
    return (ped ~= 0 and DoesEntityExist(ped)) and ped or 0
end

local function lyingAnim()
    return Tr.Cfg('Stretcher').patient and Tr.Cfg('Stretcher').patient.anim or Tr.Cfg('Beds').anim
end

local function stretcherOffset(strEnt)
    local pc = Tr.Cfg('Stretcher').patient or {}
    local pos = pc.pos or vector3(0.0, 0.05, 1.33)
    local rot = pc.rot or vector3(0.0, 0.0, 180.0)
    local bag = Tr.StrBag(strEnt)
    if bag and bag.low and Tr.LowModelActive and Tr.LowModelActive(strEnt) then
        pos = vector3(pos.x, pos.y, pos.z + (pc.lowZ or 0.0))
    end
    return pos, rot
end
Tr.StretcherOffset = stretcherOffset

local function detach(ped)
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
end

local function placeAt(ped, at, snap)
    if not at then return end
    local z = at.z
    if snap ~= false then z = Tr.Ground(at, at.z) end
    SetEntityCoordsNoOffset(ped, at.x, at.y, z, false, false, false)
    SetEntityHeading(ped, at.w or 0.0)
end

local function attachToCarrier(ped, carrier)
    local a = Tr.Cfg('Carry').attach or {}
    local pos = a.pos or vector3(0.27, 0.15, 0.63)
    local rot = a.rot or vector3(0.5, 0.5, 180.0)
    local bone = (a.bone and a.bone ~= 0) and GetPedBoneIndex(carrier, a.bone) or 0
    AttachEntityToEntity(ped, carrier, bone, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, false, false, false, false, 2, false)
end

local function attachToStretcher(ped, strEnt)
    local pos, rot = stretcherOffset(strEnt)
    AttachEntityToEntity(ped, strEnt, 0, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
end
Tr.AttachToStretcher = attachToStretcher

function Tr.BedAnim(bt)
    local tc = (Tr.Cfg('Beds').types or {})[bt or ''] or {}
    return tc.anim or Tr.Cfg('Beds').anim or lyingAnim()
end

-- where a patient lies on a bed point (vector4)
function Tr.BedSpot(at, bt)
    local tc = (Tr.Cfg('Beds').types or {})[bt or ''] or {}
    local off = tc.pos or vector3(0.0, 0.0, 0.0)
    local pt = Tr.Bed and Tr.Bed.PointFromSpot and Tr.Bed.PointFromSpot(at) or nil
    if pt and type(pt.data) == 'table' and type(pt.data.lie) == 'table' then
        off = vector3(tonumber(pt.data.lie.x) or off.x, tonumber(pt.data.lie.y) or off.y, tonumber(pt.data.lie.z) or off.z)
    end
    local h = (at.w or 0.0) + (tc.heading or 0.0)
    local r = math.rad(at.w or 0.0)
    local cs, sn = math.cos(r), math.sin(r)
    local x = at.x + off.x * cs - off.y * sn
    local y = at.y + off.x * sn + off.y * cs
    return vector4(x, y, at.z + off.z, h % 360.0)
end

-- Apply a command to a patient ped we control. isSelf = our own player ped.
function Tr.Apply(ped, cmd, isSelf, prevMode)
    if not ped or ped == 0 or not DoesEntityExist(ped) or type(cmd) ~= 'table' then return false end
    local m = cmd.m
    if m == 'carry' then
        local carrier = carrierPed(cmd.c)
        local t = GetGameTimer() + 2500
        while carrier == 0 and GetGameTimer() < t do
            Wait(100)
            carrier = carrierPed(cmd.c)
        end
        if carrier == 0 then return false end
        FreezeEntityPosition(ped, false)
        detach(ped)
        if IsPedInAnyVehicle(ped, false) then SetEntityCoordsNoOffset(ped, GetEntityCoords(carrier), false, false, false) end
        attachToCarrier(ped, carrier)
        Tr.Play(ped, Tr.Cfg('Carry').carried, { blendIn = 8.0 })
        return true
    elseif m == 'str' then
        if cmd.from == 'bay' and Tr.Bay and Tr.Bay.ReturnFromBay then
            return Tr.Bay.ReturnFromBay(ped, cmd, isSelf)
        end
        local strEnt = Tr.Ent(cmd.s, 3000)
        if strEnt == 0 then return false end
        FreezeEntityPosition(ped, false)
        detach(ped)
        if IsPedInAnyVehicle(ped, false) then SetEntityCoordsNoOffset(ped, GetEntityCoords(strEnt), false, false, false) end
        attachToStretcher(ped, strEnt)
        Tr.Play(ped, lyingAnim(), { blendIn = 8.0 })
        return true
    elseif m == 'bed' then
        local at = Tr.V4(cmd.at)
        if not at then return false end
        detach(ped)
        local spot = Tr.BedSpot(at, cmd.bt)
        SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
        SetEntityHeading(ped, spot.w)
        FreezeEntityPosition(ped, true)
        Tr.Play(ped, Tr.BedAnim(cmd.bt), { blendIn = 8.0 })
        return true
    elseif m == 'bay' then
        if Tr.Bay and Tr.Bay.PlacePatient then return Tr.Bay.PlacePatient(ped, cmd, isSelf) end
        return false
    elseif m == 'seat' then
        local veh = Tr.Ent(cmd.v, 2000)
        if veh == 0 then return false end
        FreezeEntityPosition(ped, false)
        detach(ped)
        ClearPedTasksImmediately(ped)
        SetPedIntoVehicle(ped, veh, tonumber(cmd.seat) or 1)
        return true
    elseif m == 'free' then
        if cmd.from == 'bay' and Tr.Bay and Tr.Bay.ReturnFromBay then
            return Tr.Bay.ReturnFromBay(ped, cmd, isSelf)
        end
        local wasHeld = heldModes[prevMode or ''] or IsEntityAttached(ped) or IsEntityPositionFrozen(ped)
            or IsPedInAnyVehicle(ped, false)
        FreezeEntityPosition(ped, false)
        local at = Tr.V4(cmd.at)
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            TaskLeaveVehicle(ped, veh, 16)
            Wait(250)
        end
        detach(ped)
        if wasHeld then
            Tr.StopAnim(ped, Tr.Cfg('Carry').carried)
            Tr.StopAnim(ped, lyingAnim())
            Tr.StopAnim(ped, Tr.Cfg('Beds').anim)
            if at then placeAt(ped, at) end
            if not isSelf and cmd.stand then
                ClearPedTasks(ped)
                local gu = Tr.Cfg('HelpUp').npcGetUp
                if gu then Tr.Play(ped, gu, { flag = 0 }) end
            elseif not isSelf then
                -- downed NPC: let it settle on the ground
                ClearPedTasksImmediately(ped)
                SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false)
            end
        elseif not isSelf and cmd.stand then
            ClearPedTasks(ped)
            local gu = Tr.Cfg('HelpUp').npcGetUp
            if gu then Tr.Play(ped, gu, { flag = 0 }) end
        end
        return true
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- OWN PLAYER (patient side)
-- ════════════════════════════════════════════════════════════════════════

local MINE_BLOCK = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264 }

local function selfLeaveTick(cmd)
    local sl = Tr.Cfg('Beds').selfLeave or {}
    if sl.enabled == false or cmd.m ~= 'bed' then return end
    if not NZA.Self or NZA.Self.State() ~= 'alive' then return end
    NZA.UI.Prompt('nza_tr_getup', { key = sl.label or 'X', label = Tr.L('p_getup'), sub = Tr.L('sub_bed') })
    if IsControlPressed(0, sl.control or 73) or IsDisabledControlPressed(0, sl.control or 73) then
        local ok = NZA.UI.Hold('nza_tr_getup', {
            key = sl.label or 'X', control = sl.control or 73, seconds = sl.hold or 1.5, label = Tr.L('p_getup'),
            cancel = function() return not S.mine or S.mine.m ~= 'bed' end,
        })
        if ok then
            local okCall, res = Tr.Call('bed:self')
            if not okCall then Tr.Err(res) end
        end
    end
end

local function ensureMine()
    local cmd = S.mine
    if not cmd then return end
    local ped = PlayerPedId()
    local m = cmd.m
    if m == 'carry' then
        local carrier = carrierPed(cmd.c)
        if carrier ~= 0 and not IsEntityAttachedToEntity(ped, carrier) then attachToCarrier(ped, carrier) end
        if not Tr.Playing(ped, Tr.Cfg('Carry').carried) then Tr.Play(ped, Tr.Cfg('Carry').carried) end
    elseif m == 'str' then
        local strEnt = Tr.Ent(cmd.s)
        if strEnt ~= 0 and not IsEntityAttachedToEntity(ped, strEnt) then attachToStretcher(ped, strEnt) end
        if not Tr.Playing(ped, lyingAnim()) then Tr.Play(ped, lyingAnim()) end
    elseif m == 'bed' then
        if not IsEntityPositionFrozen(ped) then FreezeEntityPosition(ped, true) end
        local a = Tr.BedAnim(cmd.bt)
        if not Tr.Playing(ped, a) then Tr.Play(ped, a) end
    elseif m == 'bay' then
        if Tr.Bay and Tr.Bay.EnsurePatient then Tr.Bay.EnsurePatient(ped, cmd) end
    elseif m == 'seat' then
        local veh = Tr.Ent(cmd.v)
        if veh ~= 0 and not IsPedInVehicle(ped, veh, false) then SetPedIntoVehicle(ped, veh, tonumber(cmd.seat) or 1) end
    end
end

local function startMineLoop()
    if mineLoop then return end
    mineLoop = true
    CreateThread(function()
        local nextEnsure = 0
        while S.mine and heldModes[S.mine.m] do
            local now = GetGameTimer()
            for i = 1, #MINE_BLOCK do DisableControlAction(0, MINE_BLOCK[i], true) end
            if now >= nextEnsure then
                nextEnsure = now + 500
                ensureMine()
            end
            if S.mine and S.mine.m == 'bed' then selfLeaveTick(S.mine) end
            Wait(0)
        end
        NZA.UI.HidePrompt('nza_tr_getup')
        mineLoop = false
    end)
end

local function suspendPose(on)
    if NZA.Wounded and NZA.Wounded.SuspendPose then NZA.Wounded.SuspendPose('transport', on) end
end

-- the server cleared the bag (respawn, admin): let go of everything without moving the ped
local function releaseMine(prev)
    S.mine = nil
    suspendPose(false)
    local ped = PlayerPedId()
    if heldModes[prev or ''] then
        if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
        FreezeEntityPosition(ped, false)
        Tr.StopAnim(ped, Tr.Cfg('Carry').carried)
        Tr.StopAnim(ped, lyingAnim())
        Tr.StopAnim(ped, Tr.Cfg('Beds').anim)
    end
    if Tr.Bay and Tr.Bay.ClearPatientShell then Tr.Bay.ClearPatientShell() end
end
Tr.ReleaseMine = function() releaseMine(S.mine and S.mine.m or nil) end

local function applyMine(cmd)
    local prev = S.mine and S.mine.m or nil
    if type(cmd) ~= 'table' then
        releaseMine(prev)
        return
    end
    -- still in the bay but sent somewhere else: leave the interior first
    if cmd.m ~= 'bay' and S.patientBay and cmd.from ~= 'bay' and (cmd.m == 'free' or cmd.m == 'str') then
        cmd.from = 'bay'
    end
    S.mine = cmd
    -- beds and the bay are not attachments: stop the downed pose from fighting the lying anim
    suspendPose(cmd.m == 'bed' or cmd.m == 'bay')
    CreateThread(function()
        Tr.Apply(PlayerPedId(), cmd, true, prev)
        if heldModes[cmd.m] then startMineLoop() end
        local msgKey = ({ carry = 'you_carried', str = 'you_stretcher', bay = 'you_bay' })[cmd.m]
        if cmd.m == 'str' and prev == 'bay' then msgKey = nil end
        if msgKey then Tr.Toast(Tr.L(msgKey), 'info') end
        NZA.Bus.Emit('transport:mine', cmd.m, cmd)
    end)
end

AddStateBagChangeHandler('nzaTr', nil, function(bagName, _, value)
    if bagName:find('^player:') then
        local sid = tonumber(bagName:sub(8))
        if sid ~= GetPlayerServerId(PlayerId()) then return end
        local n = type(value) == 'table' and value.n or nil
        if n and S.mine and S.mine.n == n then return end
        applyMine(value)
        return
    end
    -- NPC patient: only the network owner moves it
    local ent = GetEntityFromStateBagName(bagName)
    if not ent or ent == 0 or not DoesEntityExist(ent) or not IsEntityAPed(ent) then return end
    if not NetworkHasControlOfEntity(ent) or type(value) ~= 'table' then return end
    if applied[ent] == value.n then return end
    local prev = applied[ent .. ':m']
    applied[ent] = value.n
    applied[ent .. ':m'] = value.m
    CreateThread(function() Tr.Apply(ent, value, false, prev) end)
end)

-- the acting medic applies the server's command to an NPC straight from the reply
function Tr.ApplyNpc(target, cmd)
    if type(target) ~= 'table' or target.kind ~= 'npc' or type(cmd) ~= 'table' then return end
    local ent = NZA.Target.Entity(target)
    if ent == 0 then return end
    if not Tr.Control(ent, 1500) then return end
    local prev = applied[ent .. ':m']
    applied[ent] = cmd.n
    applied[ent .. ':m'] = cmd.m
    Tr.Apply(ent, cmd, false, prev)
end

-- NPC patients whose network owner changed: whoever owns them now keeps them in place
CreateThread(function()
    while true do
        Wait(1000)
        local pos = GetEntityCoords(PlayerPedId())
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) and NetworkHasControlOfEntity(ped)
                and #(pos - GetEntityCoords(ped)) < 80.0 then
                local bag = Entity(ped).state.nzaTr
                if type(bag) == 'table' and heldModes[bag.m] then
                    if applied[ped] ~= bag.n then
                        applied[ped] = bag.n
                        applied[ped .. ':m'] = bag.m
                        Tr.Apply(ped, bag, false, nil)
                    else
                        local ok = true
                        if bag.m == 'carry' then
                            ok = IsEntityAttached(ped) and Tr.Playing(ped, Tr.Cfg('Carry').carried)
                        elseif bag.m == 'str' then
                            local se = Tr.Ent(bag.s)
                            ok = se == 0 or (IsEntityAttachedToEntity(ped, se) and Tr.Playing(ped, lyingAnim()))
                        elseif bag.m == 'bed' then
                            ok = IsEntityPositionFrozen(ped) and Tr.Playing(ped, Tr.BedAnim(bag.bt))
                        elseif bag.m == 'bay' then
                            ok = not Tr.Bay or not Tr.Bay.NpcNeedsFix or not Tr.Bay.NpcNeedsFix(ped, bag)
                        end
                        if not ok then Tr.Apply(ped, bag, false, bag.m) end
                    end
                end
            end
        end
        for k in pairs(applied) do
            if type(k) == 'number' and not DoesEntityExist(k) then
                applied[k] = nil
                applied[k .. ':m'] = nil
            end
        end
    end
end)

-- respawning at a hospital: let go of the stretcher / bed / bay before the teleport
RegisterNetEvent('nza:wounded:respawn', function()
    if S.mine and heldModes[S.mine.m] then
        releaseMine(S.mine.m)
        TriggerServerEvent('nza:transport:selfRelease')
    end
end)

-- pick up a bag that was set before this file listened (resource restart, late join)
CreateThread(function()
    Wait(1500)
    local bag = LocalPlayer.state.nzaTr
    if type(bag) == 'table' and heldModes[bag.m] then applyMine(bag) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT OPTIONS (ARCHITECTURE §11, order band 10)
-- ════════════════════════════════════════════════════════════════════════

local function permOf(p)
    if p == false then return nil end
    return p
end

local function freeToMove(bag, trBag)
    if type(bag) == 'table' and (bag.carried or bag.stretcher or bag.bag) then return false end
    if Tr.Held(trBag) then return false end
    return true
end

local function asStates(t)
    local out = {}
    for k, v in pairs(t or {}) do if v then out[k] = true end end
    return out
end

NZA.Interact.Add({
    name = 'nza_tr_carry', label = Tr.L('carry'), icon = 'person', order = 10,
    perm = permOf((Config.Transport and Config.Transport.Carry or {}).perm),
    states = asStates((Config.Transport and Config.Transport.Carry or {}).states or { wounded = true, arrest = true, dead = true }),
    distance = (Config.Transport and Config.Transport.Carry or {}).distance or 2.0,
    canInteract = function(entity, _, bag)
        if Tr.Cfg('Carry').enabled == false or Tr.Busy() then return false end
        local tb = Tr.Bag(entity)
        if type(tb) == 'table' and (tb.m == 'bay' or tb.m == 'seat') then return false end
        if type(bag) == 'table' and (bag.carried or bag.stretcher or bag.bag) then return false end
        return true
    end,
    onSelect = function(entity, target)
        if Tr.Carry and Tr.Carry.Start then Tr.Carry.Start(entity, target) end
    end,
})

NZA.Interact.Add({
    name = 'nza_tr_helpup', label = Tr.L('help_up'), icon = 'hand', order = 11,
    perm = permOf((Config.Transport and Config.Transport.HelpUp or {}).perm),
    states = { wounded = true },
    distance = (Config.Transport and Config.Transport.HelpUp or {}).distance or 2.0,
    canInteract = function(entity, _, bag)
        if Tr.Cfg('HelpUp').enabled == false or Tr.Busy() then return false end
        if type(bag) ~= 'table' or not bag.stab or (bag.avpu and bag.avpu ~= 'A') then return false end
        return freeToMove(bag, Tr.Bag(entity))
    end,
    onSelect = function(entity, target)
        if Tr.HelpUp then Tr.HelpUp(entity, target) end
    end,
})

NZA.Interact.Add({
    name = 'nza_tr_onstretcher', label = Tr.L('place_stretcher'), icon = 'bed', order = 12,
    perm = (Config.Transport and Config.Transport.perm) or 'transport',
    states = { alive = true, wounded = true, arrest = true, dead = true },
    distance = 2.5,
    canInteract = function(entity, _, bag)
        if Tr.Cfg('Stretcher').enabled == false or (Tr.Busy() and Tr.Busy() ~= 'push') then return false end
        if not freeToMove(bag, Tr.Bag(entity)) then return false end
        if not Tr.Str or not Tr.Str.FreeNear then return false end
        return Tr.Str.FreeNear(GetEntityCoords(entity)) ~= nil
    end,
    onSelect = function(entity, target)
        if Tr.Str and Tr.Str.PlacePatient then Tr.Str.PlacePatient(nil, entity, target) end
    end,
})

NZA.Interact.Add({
    name = 'nza_tr_offstretcher', label = Tr.L('take_off'), icon = 'bed', order = 12,
    perm = (Config.Transport and Config.Transport.perm) or 'transport',
    states = { alive = true, wounded = true, arrest = true, dead = true },
    distance = 2.5,
    canInteract = function(entity)
        if Tr.Busy() then return false end
        local tb = Tr.Bag(entity)
        if type(tb) ~= 'table' or tb.m ~= 'str' then return false end
        local se = Tr.Ent(tb.s)
        local sb = se ~= 0 and Tr.StrBag(se) or nil
        return sb == nil or (not sb.veh and (not sb.pusher or sb.pusher == GetPlayerServerId(PlayerId())))
    end,
    onSelect = function(entity)
        local tb = Tr.Bag(entity)
        if tb and Tr.Str and Tr.Str.TakeOff then Tr.Str.TakeOff(Tr.Ent(tb.s)) end
    end,
})

NZA.Interact.Add({
    name = 'nza_tr_tobed', label = Tr.L('str_tobed'), icon = 'bed', order = 13,
    perm = (Config.Transport and Config.Transport.perm) or 'transport',
    states = { alive = true, wounded = true, arrest = true, dead = true },
    distance = 2.5,
    canInteract = function(entity)
        if Tr.Busy() or not Tr.Bed or not Tr.Bed.Nearest then return false end
        local tb = Tr.Bag(entity)
        if type(tb) ~= 'table' or tb.m ~= 'str' then return false end
        local se = Tr.Ent(tb.s)
        if se == 0 then return false end
        local sb = Tr.StrBag(se)
        if sb and (sb.veh or sb.pusher) then return false end
        return Tr.Bed.Nearest(GetEntityCoords(se), Tr.Cfg('Beds').range or 3.0, true) ~= nil
    end,
    onSelect = function(entity)
        local tb = Tr.Bag(entity)
        local se = tb and Tr.Ent(tb.s) or 0
        if se == 0 then return end
        local pt = Tr.Bed.Nearest(GetEntityCoords(se), Tr.Cfg('Beds').range or 3.0, true)
        if pt then Tr.Bed.Transfer(pt, se) end
    end,
})

NZA.Interact.Add({
    name = 'nza_tr_bedleave', label = Tr.L('bed_leave'), icon = 'walk', order = 13,
    perm = (Config.Transport and Config.Transport.perm) or 'transport',
    states = { alive = true, wounded = true },
    distance = 2.8,
    canInteract = function(entity, _, bag)
        if Tr.Busy() then return false end
        local tb = Tr.Bag(entity)
        if type(tb) ~= 'table' or tb.m ~= 'bed' then return false end
        if type(bag) == 'table' and bag.st == 'wounded' and (not bag.stab or (bag.avpu and bag.avpu ~= 'A')) then return false end
        return true
    end,
    onSelect = function(entity, target)
        if Tr.Bed and Tr.Bed.HelpOff then Tr.Bed.HelpOff(entity, target) end
    end,
})

NZA.Interact.Add({
    name = 'nza_tr_outveh', label = Tr.L('out_vehicle'), icon = 'car', order = 14,
    perm = permOf((Config.Transport and Config.Transport.Carry or {}).perm),
    states = { alive = true, wounded = true, arrest = true, dead = true },
    distance = 3.5,
    canInteract = function(entity)
        if Tr.Busy() then return false end
        local tb = Tr.Bag(entity)
        return type(tb) == 'table' and tb.m == 'seat'
    end,
    onSelect = function(entity, target)
        if Tr.OutOfVehicle then Tr.OutOfVehicle(entity, target) end
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- HELP UP / OUT OF A VEHICLE
-- ════════════════════════════════════════════════════════════════════════

function Tr.HelpUp(entity, target)
    if target.kind == 'npc' then Tr.Control(entity, 1500) end
    local ped = PlayerPedId()
    local anim = Tr.Cfg('HelpUp').anim
    TaskTurnPedToFaceEntity(ped, entity, 600)
    Wait(500)
    if anim then
        Tr.Play(ped, anim, { flag = 0 })
        Wait(math.floor((anim.ms or 1000) * 0.6))
    end
    local ok, res = Tr.Call('helpUp', target)
    if anim then Tr.StopAnim(ped, anim) end
    if not ok then return Tr.Err(res) end
    if res.npc then Tr.ApplyNpc(target, res.cmd) end
    Tr.Toast(res.msg, 'success')
end

function Tr.OutOfVehicle(entity, target)
    if target.kind == 'npc' then Tr.Control(entity, 1500) end
    local ok, res = Tr.Call('outVehicle', target)
    if not ok then return Tr.Err(res) end
    if res.npc then Tr.ApplyNpc(target, res.cmd) end
end

-- ════════════════════════════════════════════════════════════════════════
-- RADIAL (dispatch module's EMS radial menu)
-- ════════════════════════════════════════════════════════════════════════

NZA.RadialItems = NZA.RadialItems or {}

local function radialOn()
    return Tr.Cfg().radial ~= false
end

local function radialPatient(filter)
    return Tr.NearestPatient(Tr.Cfg().radialRange or 3.0, filter)
end

table.insert(NZA.RadialItems, {
    id = 'tr_carry', parent = 'patient', label = Tr.L('carry'), icon = 'person', order = 50,
    perm = permOf((Config.Transport and Config.Transport.Carry or {}).perm),
    canShow = function()
        if not radialOn() or Tr.Busy() then return false end
        return radialPatient(function(_, _, bag, tb)
            local st = type(bag) == 'table' and bag.st or 'alive'
            return (Tr.Cfg('Carry').states or {})[st] and freeToMove(bag, tb)
        end) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local ent, target = radialPatient(function(_, _, bag, tb)
                local st = type(bag) == 'table' and bag.st or 'alive'
                return (Tr.Cfg('Carry').states or {})[st] and freeToMove(bag, tb)
            end)
            if ent and Tr.Carry then Tr.Carry.Start(ent, target) end
        end)
    end,
})

table.insert(NZA.RadialItems, {
    id = 'tr_drop', parent = 'patient', label = Tr.L('drop'), icon = 'arrow-down', order = 51,
    canShow = function() return radialOn() and S.carrying ~= nil end,
    onSelect = function()
        CreateThread(function() if Tr.Carry then Tr.Carry.Drop() end end)
    end,
})

table.insert(NZA.RadialItems, {
    id = 'tr_helpup', parent = 'patient', label = Tr.L('help_up'), icon = 'hand', order = 52,
    perm = permOf((Config.Transport and Config.Transport.HelpUp or {}).perm),
    canShow = function()
        if not radialOn() or Tr.Busy() then return false end
        return radialPatient(function(_, _, bag, tb)
            return type(bag) == 'table' and bag.st == 'wounded' and bag.stab and (not bag.avpu or bag.avpu == 'A') and freeToMove(bag, tb)
        end) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local ent, target = radialPatient(function(_, _, bag, tb)
                return type(bag) == 'table' and bag.st == 'wounded' and bag.stab and freeToMove(bag, tb)
            end)
            if ent then Tr.HelpUp(ent, target) end
        end)
    end,
})

table.insert(NZA.RadialItems, {
    id = 'tr_outveh', parent = 'patient', label = Tr.L('out_vehicle'), icon = 'car', order = 53,
    canShow = function()
        if not radialOn() or Tr.Busy() then return false end
        return radialPatient(function(_, _, _, tb) return type(tb) == 'table' and tb.m == 'seat' end) ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local ent, target = radialPatient(function(_, _, _, tb) return type(tb) == 'table' and tb.m == 'seat' end)
            if ent then Tr.OutOfVehicle(ent, target) end
        end)
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    if S.mine and heldModes[S.mine.m] then
        if S.mine.m ~= 'bay' then
            DetachEntity(ped, true, false)
            FreezeEntityPosition(ped, false)
        end
        ClearPedTasks(ped)
    end
    NZA.UI.HidePrompt('nza_tr_getup')
end)

-- other modules (X-ray table) hand their 'help off the table' option over to this module ('Help them down')
Tr.OwnsHelpOff = true
function Tr.HelpOff(entity, target)
    if Tr.Bed and Tr.Bed.HelpOff then return Tr.Bed.HelpOff(entity, target) end
end
