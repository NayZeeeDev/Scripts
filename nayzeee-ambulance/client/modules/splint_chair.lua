--[[
    NAYZEEE AMBULANCE - Wheelchair (client)

    The wheelchair item unfolds a networked Config.Props.wheelchair in front of you (server creates it,
    see server/modules/splint_chair.lua). Target options on the chair model (Bridge.Target.Model):
        nza_chair_sit   'Sit down'            sit in it and drive with W A S D (F stands up)
        nza_chair_push  'Take the handles'    push it (G lets go) - with or without someone in it
        nza_chair_fold  'Fold the chair'      back into the item
        nza_chair_out   'Help out of the chair' (medics, Wheelchair.seatPerm)
    Patient options (NZA.Interact): nza_chair_seat 'Seat in wheelchair' (nearest free chair within
        Interact.chairRange of the patient), nza_chair_unseat 'Help out of the chair'.
    Radial (NZA.RadialItems, parent 'patient'): 'splint_chair' seats the nearest patient.
    Driving: smooth acceleration / braking / friction, turning slower at speed, ground following with
        pitch on slopes (gravity pulls you downhill), curbs higher than drive.maxStep and drops deeper than
        drive.maxDrop block you, walls / vehicles / peds stop you (capsule shape tests). The driver owns the
        chair entity (network control) while driving; the pusher owns it while pushing.
    HUD: NZA.Splint.HudSet('chair' | 'push', { speed, slope, turn, dist, blocked, ... }) → 'splint' app in 'hud' mode.
    Net events handled: nza:splint:chair:place · nza:splint:chair:seated (net, on)
    Callbacks used: nza:splint:chair:spawn / sit / push / fold / seat / unseat · event nza:splint:chair:leave
    Lua API: NZA.Splint.InChair() · NZA.Splint.Pushing() · NZA.Splint.ChairSit(ent) · NZA.Splint.ChairPush(ent)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Splint = NZA.Splint or {}
local SP = NZA.Splint
local U = NZA.Util

local function C(section)
    local c = Config.Splint or {}
    return c[section] or {}
end

local function W() return C('Wheelchair') end

local function L(key, ...)
    return NZA.L('splint.' .. key, ...)
end

local function toast(key, kind, ...)
    NZA.UI.Toast({ title = L('chair'), message = L(key, ...), type = kind or 'info' })
end

local function toastMsg(r, fallback)
    local msg = type(r) == 'table' and r.msg or nil
    NZA.UI.Toast({ title = L('chair'), message = msg or L(fallback or 'err_generic'), type = 'error' })
end

local MODEL_NAME = (Config.Props and Config.Props[W().prop or 'wheelchair']) or (Config.PropFallbacks and Config.PropFallbacks[W().prop or 'wheelchair']) or Config.Props.wheelchair
local MODEL = joaat(MODEL_NAME)

local my = { mode = nil, ent = 0, net = nil, gen = 0, speed = 0.0, heading = 0.0, baseOff = nil }
local placing = false
local npcSeated = {}      -- [ped] = chair entity (NPCs this client seated)

function SP.InChair() return my.mode == 'sit' end
function SP.Pushing() return my.mode == 'push' end

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function chairState(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) or GetEntityModel(ent) ~= MODEL then return nil end
    if not NetworkGetEntityIsNetworked(ent) then return nil end
    local e = Entity(ent)
    return e and e.state and e.state.nzaChair or nil
end

local function netOf(ent)
    if not ent or ent == 0 or not NetworkGetEntityIsNetworked(ent) then return nil end
    return NetworkGetNetworkIdFromEntity(ent)
end

local function entOf(net, wait)
    net = tonumber(net)
    if not net then return 0 end
    local deadline = GetGameTimer() + (wait or 0)
    repeat
        if NetworkDoesNetIdExist(net) then
            local ent = NetworkGetEntityFromNetworkId(net)
            if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
        end
        if wait then Wait(50) end
    until GetGameTimer() >= deadline
    return 0
end

local function requestControl(ent, ms)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    NetworkRequestControlOfEntity(ent)
    local deadline = GetGameTimer() + (ms or 1500)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        Wait(25)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

local function myId() return GetPlayerServerId(PlayerId()) end

local function alive()
    return NZA.Self.State() == 'alive'
end

local function groundAt(x, y, z, ignore)
    local h = StartExpensiveSynchronousShapeTestLosProbe(x, y, z + 0.7, x, y, z - 1.8, 1 + 16, ignore or 0, 7)
    local _, hit, pos = GetShapeTestResult(h)
    if hit == 1 and pos then return pos.z end
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 0.7, false)
    if ok then return gz end
    return nil
end

local function playLoop(ped, a)
    if type(a) ~= 'table' or not a.dict then return end
    if not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
        NZA.Anim.Play(ped, a.dict, a.clip, { flag = a.flag or 1 })
    end
end

local function stopAnim(ped, a)
    if type(a) == 'table' and a.dict and IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
        StopAnimTask(ped, a.dict, a.clip, 2.0)
    end
end

local function playerName(src)
    local pl = GetPlayerFromServerId(tonumber(src) or -1)
    if pl and pl ~= -1 then return GetPlayerName(pl) end
    return ''
end

local hudNext = 0
local function hudPush(kind, data)
    if not SP.HudSet or W().hud == false then return end
    local now = GetGameTimer()
    if data and now < hudNext then return end
    hudNext = now + 120
    SP.HudSet(kind, data)
end

-- ════════════════════════════════════════════════════════════════════════
-- UNFOLD / FOLD
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:splint:chair:place', function()
    if placing or my.mode then return end
    placing = true
    local ped = PlayerPedId()
    local pa = W().place or {}
    if pa.dict then NZA.Anim.Play(ped, pa.dict, pa.clip, { flag = 0 }) end
    Wait(tonumber(pa.ms) or 900)
    local fwd = GetEntityForwardVector(ped)
    local c = GetEntityCoords(ped) + fwd * (tonumber(W().placeDistance) or 1.1)
    local gz = groundAt(c.x, c.y, c.z, ped) or (c.z - 0.95)
    local r = lib.callback.await('nza:splint:chair:spawn', false, vector3(c.x, c.y, gz), GetEntityHeading(ped))
    if pa.dict then StopAnimTask(ped, pa.dict, pa.clip, 2.0) end
    if type(r) ~= 'table' or not r.ok then
        toastMsg(r)
        placing = false
        return
    end
    local ent = entOf(r.net, 3000)
    if ent ~= 0 and requestControl(ent, 1500) then
        PlaceObjectOnGroundProperly(ent)
        FreezeEntityPosition(ent, true)
    end
    toast('chair_ready', 'success')
    placing = false
end)

local function fold(ent)
    local net = netOf(ent)
    if not net then return end
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, ent, 500)
    Wait(400)
    local pa = W().place or {}
    if pa.dict then NZA.Anim.Play(ped, pa.dict, pa.clip, { flag = 0 }) end
    Wait(math.floor((tonumber(pa.ms) or 900) * 0.7))
    local r = lib.callback.await('nza:splint:chair:fold', false, net)
    if pa.dict then StopAnimTask(ped, pa.dict, pa.clip, 2.0) end
    if type(r) ~= 'table' or not r.ok then toastMsg(r) return end
    toast('chair_folded', 'success')
end

-- ════════════════════════════════════════════════════════════════════════
-- SITTING & DRIVING
-- ════════════════════════════════════════════════════════════════════════

local DRIVE_BLOCK = { 21, 22, 23, 24, 25, 36, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264, 30, 31, 32, 33, 34, 35 }

local function leaveSeat(tellServer)
    if my.mode ~= 'sit' then return end
    local ped = PlayerPedId()
    local ent, net = my.ent, my.net
    my.mode = nil
    my.gen = my.gen + 1
    DetachEntity(ped, true, true)
    stopAnim(ped, (W().seat or {}).anim)
    if ent ~= 0 and DoesEntityExist(ent) then
        local out = GetOffsetFromEntityInWorldCoords(ent, 0.0, -0.8, 0.0)
        local gz = groundAt(out.x, out.y, out.z + 0.3, ent) or out.z
        SetEntityCoords(ped, out.x, out.y, gz + 0.95, false, false, false, false)
        SetEntityHeading(ped, (GetEntityHeading(ent) + 180.0) % 360.0)
        if NetworkHasControlOfEntity(ent) then FreezeEntityPosition(ent, true) end
    end
    NZA.Self.SetMoveOverride('wheelchair', nil)
    if tellServer and net then TriggerServerEvent('nza:splint:chair:leave', net) end
    hudPush('chair', nil)
    my.ent, my.net, my.speed = 0, nil, 0.0
end

local function driveStep(ent, dt, d, input)
    local pos = GetEntityCoords(ent)
    local H = my.heading
    -- the person faces the chair's -Y
    local rad = math.rad(H)
    local dir = vector3(math.sin(rad), -math.cos(rad), 0.0)

    -- ground / slope under the wheels
    local gz = groundAt(pos.x, pos.y, pos.z, ent) or (pos.z - (my.baseOff or 0.0))
    local fz = groundAt(pos.x + dir.x * 0.32, pos.y + dir.y * 0.32, gz, ent) or gz
    local bz = groundAt(pos.x - dir.x * 0.32, pos.y - dir.y * 0.32, gz, ent) or gz
    local pitch = math.atan(fz - bz, 0.64)
    local pitchDeg = math.deg(pitch)

    -- speed
    local v = my.speed
    local accel, brake = tonumber(d.accel) or 1.3, tonumber(d.brake) or 3.4
    if input.fwd > 0 then
        v = v + (v < 0 and brake or accel) * dt
    elseif input.fwd < 0 then
        v = v - (v > 0 and brake or accel) * dt
    else
        local f = (tonumber(d.friction) or 0.9) * dt
        if math.abs(v) <= f then v = 0.0 elseif v > 0 then v = v - f else v = v + f end
    end
    -- gravity along the slope (positive pitch = nose up = rolls back)
    local slopeF = tonumber(d.slopeFactor) or 0.6
    if math.abs(pitchDeg) > 1.5 then v = v - 9.81 * math.sin(pitch) * slopeF * dt end
    local maxF = tonumber(d.maxSpeed) or 1.9
    local maxR = tonumber(d.reverseSpeed) or 0.8
    local downMax = tonumber(d.downhillMax) or 3.2
    local hiCap = (pitch < -0.03) and downMax or maxF
    local loCap = (pitch > 0.03) and -downMax or -maxR
    if v > hiCap then v = math.max(hiCap, v - brake * dt) end
    if v < loCap then v = math.min(loCap, v + brake * dt) end

    -- steering
    local frac = U.clamp(math.abs(v) / maxF, 0.0, 1.0)
    local rate = (tonumber(d.turnRate) or 78.0) * (1.0 + ((tonumber(d.turnAtSpeed) or 0.65) - 1.0) * frac)
    H = (H + input.turn * rate * dt) % 360.0

    -- move with collision checks
    local blocked = nil
    local step = v * dt
    if math.abs(step) > 0.0005 then
        local sdir = step > 0 and dir or -dir
        local radius = tonumber(d.radius) or 0.45
        local np = pos + dir * step
        local ngz = groundAt(np.x, np.y, gz, ent)
        if not ngz then
            blocked = 'drop'
        elseif ngz - gz > (tonumber(d.maxStep) or 0.16) then
            blocked = 'curb'
        elseif gz - ngz > (tonumber(d.maxDrop) or 0.42) then
            blocked = 'drop'
        elseif step > 0 and pitchDeg > (tonumber(d.maxSlope) or 24.0) or step < 0 and -pitchDeg > (tonumber(d.maxSlope) or 24.0) then
            blocked = 'steep'
        else
            local from = pos + sdir * 0.15 + vector3(0.0, 0.0, 0.45)
            local to = np + sdir * radius + vector3(0.0, 0.0, 0.45)
            local h1 = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, 0.22, 1 + 2 + 16, ent, 7)
            local _, hit1 = GetShapeTestResult(h1)
            local h2 = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, 0.22, 4 + 8, PlayerPedId(), 7)
            local _, hit2 = GetShapeTestResult(h2)
            if hit1 == 1 or hit2 == 1 then blocked = 'wall' end
        end
        if blocked then
            v = -v * 0.15
            if math.abs(v) < 0.05 then v = 0.0 end
        else
            pos = vector3(np.x, np.y, ngz + (my.baseOff or 0.0))
            gz = ngz
            my.dist = (my.dist or 0.0) + math.abs(step)
        end
    end
    my.speed = v
    my.heading = H
    SetEntityCoordsNoOffset(ent, pos.x, pos.y, gz + (my.baseOff or 0.0), false, false, false)
    SetEntityRotation(ent, -pitchDeg, 0.0, H, 2, true)
    return blocked, pitchDeg
end

local function seatLoop(gen)
    CreateThread(function()
        local d = W().drive or {}
        local stand = (W().keys or {}).stand or { control = 23, label = 'F' }
        local seat = W().seat or {}
        local lastCtrl = 0
        while my.mode == 'sit' and my.gen == gen do
            local ped = PlayerPedId()
            local ent = my.ent
            if ent == 0 or not DoesEntityExist(ent) then
                leaveSeat(false)
                break
            end
            if not alive() or IsPedInAnyVehicle(ped, false) then
                leaveSeat(true)
                break
            end
            for i = 1, #DRIVE_BLOCK do DisableControlAction(0, DRIVE_BLOCK[i], true) end
            if not IsEntityAttachedToEntity(ped, ent) then
                local s = seat
                AttachEntityToEntity(ped, ent, 0, s.pos.x, s.pos.y, s.pos.z, s.rot.x, s.rot.y, s.rot.z, false, false, false, false, 2, true)
            end
            playLoop(ped, seat.anim)
            if IsDisabledControlJustPressed(0, stand.control or 23) then
                leaveSeat(true)
                break
            end
            local st = chairState(ent) or {}
            local pushedBy = st.push and st.push ~= myId() and st.push or nil
            local blocked, pitchDeg = nil, 0.0
            if pushedBy then
                my.speed = 0.0
                local sp = GetEntitySpeed(ent)
                my.dist = (my.dist or 0.0) + sp * GetFrameTime()
                hudPush('chair', {
                    kind = 'chair', title = L('hud_chair'), sub = L('hud_pushed_by', playerName(pushedBy)), state = 'pushed',
                    speed = sp, max = tonumber(d.maxSpeed) or 1.9, slope = 0, turn = 0, dist = my.dist,
                    keys = { { keys = { stand.label or 'F' }, label = L('k_stand') } },
                })
            else
                local now = GetGameTimer()
                if not NetworkHasControlOfEntity(ent) then
                    if now > lastCtrl then lastCtrl = now + 300 NetworkRequestControlOfEntity(ent) end
                else
                    if not my.baseOff then
                        local pos = GetEntityCoords(ent)
                        local gz = groundAt(pos.x, pos.y, pos.z, ent)
                        my.baseOff = gz and U.clamp(pos.z - gz, -0.1, 0.6) or 0.0
                        my.heading = GetEntityHeading(ent)
                        FreezeEntityPosition(ent, true)
                    end
                    local fwd = (IsDisabledControlPressed(0, 32) and 1 or 0) - (IsDisabledControlPressed(0, 33) and 1 or 0)
                    local turn = (IsDisabledControlPressed(0, 34) and 1 or 0) - (IsDisabledControlPressed(0, 35) and 1 or 0)
                    my.turn = turn
                    blocked, pitchDeg = driveStep(ent, math.min(0.05, GetFrameTime()), d, { fwd = fwd, turn = turn })
                end
                local blockedText = blocked and L('blocked_' .. blocked) or nil
                hudPush('chair', {
                    kind = 'chair', title = L('hud_chair'),
                    sub = blocked and L('hud_sub_blocked') or L('hud_sub_drive'),
                    state = blocked and 'blocked' or 'drive', blocked = blockedText,
                    speed = my.speed, max = tonumber(d.maxSpeed) or 1.9, slope = pitchDeg or 0, turn = my.turn or 0, dist = my.dist or 0,
                    keys = {
                        { keys = { 'W', 'S' }, label = L('k_drive') },
                        { keys = { 'A', 'D' }, label = L('k_turn') },
                        { keys = { stand.label or 'F' }, label = L('k_stand') },
                    },
                })
            end
            Wait(0)
        end
    end)
end

local function attachSelf(ent, net)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return false end
    if my.mode == 'push' and SP.StopPush then SP.StopPush() end
    ClearPedTasks(ped)
    local s = W().seat or {}
    local p, r = s.pos or vector3(0.0, 0.0, 0.4), s.rot or vector3(0.0, 0.0, 180.0)
    AttachEntityToEntity(ped, ent, 0, p.x, p.y, p.z, r.x, r.y, r.z, false, false, false, false, 2, true)
    playLoop(ped, s.anim)
    NZA.Self.SetMoveOverride('wheelchair', false)
    my.gen = my.gen + 1
    my.mode, my.ent, my.net = 'sit', ent, net
    my.speed, my.baseOff, my.dist, my.turn = 0.0, nil, 0.0, 0
    my.heading = GetEntityHeading(ent)
    seatLoop(my.gen)
    return true
end

function SP.ChairSit(ent)
    if my.mode or not alive() then return end
    local net = netOf(ent)
    if not net then return end
    local r = lib.callback.await('nza:splint:chair:sit', false, net)
    if type(r) ~= 'table' or not r.ok then toastMsg(r) return end
    attachSelf(ent, net)
end

RegisterNetEvent('nza:splint:chair:seated', function(net, on)
    if on then
        if my.mode == 'sit' then return end
        local ent = entOf(net, 2500)
        if ent == 0 then
            TriggerServerEvent('nza:splint:chair:leave', net)
            return
        end
        if attachSelf(ent, net) then toast('chair_seated', 'info') end
    elseif my.mode == 'sit' and my.net == tonumber(net) then
        leaveSeat(false)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- PUSHING
-- ════════════════════════════════════════════════════════════════════════

local PUSH_BLOCK = { 21, 22, 23, 24, 25, 36, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264 }

function SP.StopPush(tellServer)
    if my.mode ~= 'push' then return end
    local ped = PlayerPedId()
    local ent, net = my.ent, my.net
    my.mode = nil
    my.gen = my.gen + 1
    stopAnim(ped, (W().push or {}).anim)
    if ent ~= 0 and DoesEntityExist(ent) then
        DetachEntity(ent, true, true)
        local front = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.75, 0.0)
        local gz = groundAt(front.x, front.y, front.z, ent)
        if gz then SetEntityCoordsNoOffset(ent, front.x, front.y, gz, false, false, false) end
        SetEntityRotation(ent, 0.0, 0.0, GetEntityHeading(ped) + 180.0, 2, true)
        PlaceObjectOnGroundProperly(ent)
        FreezeEntityPosition(ent, true)
    end
    if tellServer ~= false and net then lib.callback.await('nza:splint:chair:push', false, net, false) end
    hudPush('push', nil)
    my.ent, my.net = 0, nil
end

local function pushLoop(gen)
    CreateThread(function()
        local pc = W().push or {}
        local letGo = (W().keys or {}).letGo or { control = 47, label = 'G' }
        local blend = tonumber(pc.maxMoveBlend) or 1.0
        local slope, slopeAt = 0.0, 0
        my.dist = 0.0
        while my.mode == 'push' and my.gen == gen do
            local ped = PlayerPedId()
            local ent = my.ent
            if ent == 0 or not DoesEntityExist(ent) then
                my.mode = nil
                hudPush('push', nil)
                if my.net then lib.callback.await('nza:splint:chair:push', false, my.net, false) end
                my.ent, my.net = 0, nil
                break
            end
            if not alive() or IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) then
                SP.StopPush(true)
                break
            end
            for i = 1, #PUSH_BLOCK do DisableControlAction(0, PUSH_BLOCK[i], true) end
            SetPedMaxMoveBlendRatio(ped, blend)
            playLoop(ped, pc.anim)
            if not IsEntityAttachedToEntity(ent, ped) and NetworkHasControlOfEntity(ent) then
                local p, r = pc.pos or vector3(0.0, -0.3, -0.73), pc.rot or vector3(195.0, 180.0, 180.0)
                FreezeEntityPosition(ent, false)
                AttachEntityToEntity(ent, ped, GetPedBoneIndex(ped, pc.bone or 28422), p.x, p.y, p.z, r.x, r.y, r.z, false, false, false, false, 2, true)
            elseif not NetworkHasControlOfEntity(ent) then
                NetworkRequestControlOfEntity(ent)
            end
            if IsControlJustPressed(0, letGo.control or 47) then
                SP.StopPush(true)
                break
            end
            local st = chairState(ent) or {}
            local who = st.occ and not st.occNpc and playerName(st.occ) or nil
            local speed = GetEntitySpeed(ped)
            my.dist = (my.dist or 0.0) + speed * GetFrameTime()
            local now = GetGameTimer()
            if now > slopeAt then
                -- ground grade along the walking direction (two probes, a metre apart)
                slopeAt = now + 300
                local f = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.5, 0.0)
                local b = GetOffsetFromEntityInWorldCoords(ped, 0.0, -0.5, 0.0)
                local fz, bz = groundAt(f.x, f.y, f.z, ped), groundAt(b.x, b.y, b.z, ped)
                slope = (fz and bz) and math.deg(math.atan(fz - bz, 1.0)) or 0.0
            end
            hudPush('push', {
                kind = 'push', title = L('hud_push'), sub = who and who ~= '' and L('hud_pushing', who) or (st.occ and L('hud_pushing_patient') or L('hud_push_empty')),
                state = 'push', speed = speed, max = tonumber((W().drive or {}).maxSpeed) or 1.9, slope = slope, turn = 0, dist = my.dist,
                keys = { { keys = { letGo.label or 'G' }, label = L('k_let_go') } },
            })
            Wait(0)
        end
    end)
end

function SP.ChairPush(ent)
    if my.mode or not alive() then return end
    local net = netOf(ent)
    if not net then return end
    local r = lib.callback.await('nza:splint:chair:push', false, net, true)
    if type(r) ~= 'table' or not r.ok then toastMsg(r) return end
    if not requestControl(ent, 2000) then
        lib.callback.await('nza:splint:chair:push', false, net, false)
        toast('err_control', 'error')
        return
    end
    local ped = PlayerPedId()
    -- step behind the handles
    local behind = GetOffsetFromEntityInWorldCoords(ent, 0.0, 0.65, 0.0)
    TaskGoStraightToCoord(ped, behind.x, behind.y, behind.z, 1.0, 1500, (GetEntityHeading(ent) + 180.0) % 360.0, 0.1)
    Wait(900)
    ClearPedTasks(ped)
    SetEntityHeading(ped, (GetEntityHeading(ent) + 180.0) % 360.0)
    local pc = W().push or {}
    local p, rr = pc.pos or vector3(0.0, -0.3, -0.73), pc.rot or vector3(195.0, 180.0, 180.0)
    FreezeEntityPosition(ent, false)
    AttachEntityToEntity(ent, ped, GetPedBoneIndex(ped, pc.bone or 28422), p.x, p.y, p.z, rr.x, rr.y, rr.z, false, false, false, false, 2, true)
    playLoop(ped, pc.anim)
    my.gen = my.gen + 1
    my.mode, my.ent, my.net = 'push', ent, net
    pushLoop(my.gen)
end

-- ════════════════════════════════════════════════════════════════════════
-- MEDICS: SEAT / HELP OUT A PATIENT
-- ════════════════════════════════════════════════════════════════════════

local function nearestFreeChair(coords, range)
    local best, bestD = 0, range
    for _, obj in ipairs(GetGamePool('CObject')) do
        if GetEntityModel(obj) == MODEL then
            local st = chairState(obj)
            if st and not st.occ then
                local d = #(GetEntityCoords(obj) - coords)
                if d < bestD then best, bestD = obj, d end
            end
        end
    end
    return best
end

local function chairOfPatient(ped)
    if not ped or ped == 0 then return 0 end
    local key
    if IsPedAPlayer(ped) then
        key = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
    elseif NetworkGetEntityIsNetworked(ped) then
        key = NetworkGetNetworkIdFromEntity(ped)
    end
    if not key then return 0 end
    for _, obj in ipairs(GetGamePool('CObject')) do
        if GetEntityModel(obj) == MODEL then
            local st = chairState(obj)
            if st and st.occ == key and (st.occNpc == true) == (not IsPedAPlayer(ped)) then return obj end
        end
    end
    return 0
end
SP.ChairOfPatient = chairOfPatient

local function seatNpc(ped, ent)
    if not requestControl(ped, 1500) then return false end
    ClearPedTasksImmediately(ped)
    local s = W().seat or {}
    local p, r = s.pos or vector3(0.0, 0.0, 0.4), s.rot or vector3(0.0, 0.0, 180.0)
    AttachEntityToEntity(ped, ent, 0, p.x, p.y, p.z, r.x, r.y, r.z, false, false, false, false, 2, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    playLoop(ped, s.anim)
    npcSeated[ped] = ent
    return true
end

local function unseatNpc(ped, ent)
    npcSeated[ped] = nil
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    requestControl(ped, 1200)
    DetachEntity(ped, true, true)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        local out = GetOffsetFromEntityInWorldCoords(ent, 0.0, -0.8, 0.0)
        local gz = groundAt(out.x, out.y, out.z + 0.3, ent) or out.z
        SetEntityCoords(ped, out.x, out.y, gz + 0.95, false, false, false, false)
    end
    stopAnim(ped, (W().seat or {}).anim)
    ClearPedTasks(ped)
end

function SP.SeatPatient(ped, target)
    if not ped or ped == 0 then return end
    target = target or NZA.Target.FromEntity(ped)
    if not target then return end
    local ent = nearestFreeChair(GetEntityCoords(ped), tonumber(C('Interact').chairRange) or 6.0)
    if ent == 0 then toast('err_no_chair_near', 'error') return end
    local net = netOf(ent)
    local r = lib.callback.await('nza:splint:chair:seat', false, net, target)
    if type(r) ~= 'table' or not r.ok then toastMsg(r) return end
    if r.npc then
        if not seatNpc(ped, ent) then
            lib.callback.await('nza:splint:chair:unseat', false, net)
            toast('err_control', 'error')
            return
        end
    end
    toast('chair_patient_in', 'success')
end

function SP.UnseatPatient(ped)
    local ent = chairOfPatient(ped)
    if ent == 0 then toast('err_not_in_chair', 'error') return end
    local r = lib.callback.await('nza:splint:chair:unseat', false, netOf(ent))
    if type(r) ~= 'table' or not r.ok then toastMsg(r) return end
    if r.npc then unseatNpc(ped, ent) end
    toast('chair_patient_out', 'success')
end

local function unseatFromChair(ent)
    local st = chairState(ent)
    if not st or not st.occ then return end
    local ped = 0
    if st.occNpc then
        if NetworkDoesNetIdExist(st.occ) then ped = NetworkGetEntityFromNetworkId(st.occ) end
    else
        local pl = GetPlayerFromServerId(st.occ)
        if pl and pl ~= -1 then ped = GetPlayerPed(pl) end
    end
    local r = lib.callback.await('nza:splint:chair:unseat', false, netOf(ent))
    if type(r) ~= 'table' or not r.ok then toastMsg(r) return end
    if r.npc and ped ~= 0 then unseatNpc(ped, ent) end
    toast('chair_patient_out', 'success')
end

-- keep the anims of NPCs this client seated
CreateThread(function()
    while true do
        Wait(1000)
        local seat = W().seat or {}
        for ped, ent in pairs(npcSeated) do
            if not DoesEntityExist(ped) or not DoesEntityExist(ent) or not IsEntityAttachedToEntity(ped, ent) then
                npcSeated[ped] = nil
            elseif NetworkHasControlOfEntity(ped) then
                playLoop(ped, seat.anim)
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- TARGET OPTIONS
-- ════════════════════════════════════════════════════════════════════════

local icons = C('Interact').icons or {}

local function canMedic()
    return NZA.Perm(W().seatPerm or 'transport')
end

if W().enabled ~= false then
    CreateThread(function()
        Wait(500)
        Bridge.Target.Model({ MODEL_NAME }, {
            {
                name = 'nza_chair_sit', label = L('opt_sit'), icon = icons.sit or 'seat', distance = 2.0,
                canInteract = function(ent)
                    local st = chairState(ent)
                    return st ~= nil and not st.occ and st.push ~= myId() and my.mode == nil and alive()
                end,
                onSelect = function(ent) CreateThread(function() SP.ChairSit(ent) end) end,
            },
            {
                name = 'nza_chair_push', label = L('opt_push'), icon = icons.push or 'hand', distance = 2.0,
                canInteract = function(ent)
                    local st = chairState(ent)
                    return st ~= nil and not st.push and st.occ ~= myId() and my.mode == nil and alive()
                end,
                onSelect = function(ent) CreateThread(function() SP.ChairPush(ent) end) end,
            },
            {
                name = 'nza_chair_fold', label = L('opt_fold'), icon = icons.fold or 'box', distance = 2.0,
                canInteract = function(ent)
                    local st = chairState(ent)
                    if not st or st.occ or st.push or my.mode then return false end
                    if W().foldOwnerOnly and st.owner ~= myId() and not canMedic() then return false end
                    return alive()
                end,
                onSelect = function(ent) CreateThread(function() fold(ent) end) end,
            },
            {
                name = 'nza_chair_out', label = L('opt_out'), icon = icons.out or 'walk', distance = 2.2,
                canInteract = function(ent)
                    local st = chairState(ent)
                    return st ~= nil and st.occ ~= nil and not (not st.occNpc and st.occ == myId()) and canMedic() and my.mode == nil
                end,
                onSelect = function(ent) CreateThread(function() unseatFromChair(ent) end) end,
            },
        })
    end)

    if C('Interact').chair ~= false then
        NZA.Interact.Add({
            name = 'nza_chair_seat', label = L('opt_seat'), icon = icons.chair or 'wheelchair', order = 55,
            perm = W().seatPerm or 'transport', states = { alive = true },
            distance = tonumber(C('Interact').distance) or 2.2,
            canInteract = function(entity, _, st)
                if type(st) ~= 'table' or st.carried or st.bag or st.stretcher then return false end
                if chairOfPatient(entity) ~= 0 then return false end
                return nearestFreeChair(GetEntityCoords(entity), tonumber(C('Interact').chairRange) or 6.0) ~= 0
            end,
            onSelect = function(entity, target) SP.SeatPatient(entity, target) end,
        })
        NZA.Interact.Add({
            name = 'nza_chair_unseat', label = L('opt_out'), icon = icons.out or 'walk', order = 56,
            perm = W().seatPerm or 'transport', states = { alive = true, wounded = true, arrest = true, dead = true },
            distance = tonumber(C('Interact').distance) or 2.2,
            canInteract = function(entity) return chairOfPatient(entity) ~= 0 end,
            onSelect = function(entity) SP.UnseatPatient(entity) end,
        })
    end

    NZA.RadialItems = NZA.RadialItems or {}
    if C('Radial').enabled ~= false then
        table.insert(NZA.RadialItems, {
            id = 'splint_chair', parent = 'patient', label = L('radial_chair'), icon = 'wheelchair', order = 56,
            perm = W().seatPerm or 'transport',
            canShow = function()
                if my.mode then return false end
                return SP.NearestPatient ~= nil and SP.NearestPatient(tonumber(C('Radial').range) or 3.0, function(st)
                    return st.st == 'alive' and not st.carried and not st.bag and not st.stretcher
                end) ~= nil
            end,
            onSelect = function()
                local ped = SP.NearestPatient and SP.NearestPatient(tonumber(C('Radial').range) or 3.0, function(st)
                    return st.st == 'alive' and not st.carried and not st.bag
                end)
                if not ped then toast('err_no_patient', 'error') return end
                CreateThread(function()
                    if chairOfPatient(ped) ~= 0 then SP.UnseatPatient(ped) else SP.SeatPatient(ped) end
                end)
            end,
        })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    if new == 'alive' then return end
    if my.mode == 'sit' then leaveSeat(true) end
    if my.mode == 'push' then SP.StopPush(true) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    if my.mode == 'sit' then
        DetachEntity(ped, true, true)
        stopAnim(ped, (W().seat or {}).anim)
        NZA.Self.SetMoveOverride('wheelchair', nil)
    elseif my.mode == 'push' then
        if my.ent ~= 0 and DoesEntityExist(my.ent) then DetachEntity(my.ent, true, true) end
        stopAnim(ped, (W().push or {}).anim)
    end
    my.mode = nil
    for npc in pairs(npcSeated) do
        if DoesEntityExist(npc) then DetachEntity(npc, true, true) ClearPedTasks(npc) end
    end
    npcSeated = {}
end)
