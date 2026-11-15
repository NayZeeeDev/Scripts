-- Custom vehicle cameras: cockpit FOV, hood, bumper, smoothed chase cams, cinematic.
Camera = {
    Modes = {
        { id = 'cockpit',    label = 'Cockpit' },
        { id = 'hood',       label = 'Hood' },
        { id = 'bumper',     label = 'Bumper' },
        { id = 'chase_near', label = 'Chase Near' },
        { id = 'chase_far',  label = 'Chase Far' },
        { id = 'cinematic',  label = 'Cinematic Low' },
        { id = 'native',     label = 'GTA Native' },
    },
}

local cam            = nil
local rendering      = false
local prevViewMode   = nil
local attachedTo     = 0
local seatCache      = { veh = 0, off = nil, at = 0, first = 0, final = false }
local look           = { yaw = 0.0, pitch = 0.0, tYaw = 0.0, tPitch = 0.0, last = 0 }
local chase          = { pos = nil, heading = nil }
local curFov         = 70.0
local shakeUntil     = 0
local roadShakeOn    = false

local function modeLabel(id)
    for _, m in ipairs(Camera.Modes) do if m.id == id then return m.label end end
    return id
end
Camera.Label = function() return modeLabel(CU.Settings.camera.mode) end

local function ensureCam()
    if cam and DoesCamExist(cam) then return end
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamNearClip(cam, 0.05)
    roadShakeOn = false
end

function Camera.Stop()
    if not rendering then return end
    rendering = false
    RenderScriptCams(false, false, 0, true, true)
    if cam and DoesCamExist(cam) then
        StopCamShaking(cam, true)
        DetachCam(cam)
        SetCamActive(cam, false)
        DestroyCam(cam, false)
    end
    cam, attachedTo, roadShakeOn = nil, 0, false
    chase.pos, chase.heading = nil, nil
    if prevViewMode then
        SetFollowVehicleCamViewMode(prevViewMode)
        prevViewMode = nil
    end
end

function Camera.SettingsChanged()
    seatCache.off, seatCache.final = nil, false   -- recompute seat offsets with the new nudges
    attachedTo = 0
    if CU.Settings.camera.mode == 'native' then Camera.Stop() end
end

function Camera.Cycle()
    local cur = CU.Settings.camera.mode
    local idx = 1
    for i, m in ipairs(Camera.Modes) do if m.id == cur then idx = i end end
    idx = idx % #Camera.Modes + 1
    CU.Settings.camera.mode = Camera.Modes[idx].id
    CU.SaveSettings()
    Camera.SettingsChanged()
    UI.Hint(L('camera_mode', Camera.Modes[idx].label))
end

function Camera.AdjustFov(delta)
    local c = CU.Settings.camera
    local key = (c.mode == 'cockpit' and 'cockpitFov') or ((c.mode == 'hood' or c.mode == 'bumper') and 'hoodFov') or 'chaseFov'
    if c.mode == 'native' then return end
    c[key] = Util.Clamp(c[key] + delta, 40.0, 110.0)
    CU.SaveSettings()
    UI.Hint(L('fov', math.floor(c[key])))
end

function Camera.Impact(severity)
    if not (cam and rendering and CU.Settings.camera.shake) then
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', math.min(severity * 0.08, 0.6))
        return
    end
    ShakeCam(cam, 'SMALL_EXPLOSION_SHAKE', math.min(severity * 0.08, 0.6))
    shakeUntil = GetGameTimer() + 600
    roadShakeOn = false
end

-- Seat position: taken from the ped's head bone once seated, falls back to the seat bone
local function cockpitOffset(veh)
    local now = GetGameTimer()
    if seatCache.veh == veh and seatCache.off and (seatCache.final or now - seatCache.at < 1200) then
        return seatCache.off
    end
    local s = CU.Settings.camera
    local off
    local seated = seatCache.veh == veh and now - seatCache.first > 1200
    if seatCache.veh ~= veh then seatCache.first = now end
    if seated then
        local head = GetPedBoneCoords(CU.Ped, 31086, 0.0, 0.0, 0.0)
        local lo = GetOffsetFromEntityGivenWorldCoords(veh, head.x, head.y, head.z)
        off = vector3(lo.x, lo.y + 0.11, lo.z + 0.04)
    else
        local bone = GetEntityBoneIndexByName(veh, 'seat_dside_f')
        if bone ~= -1 then
            local wp = GetWorldPositionOfEntityBone(veh, bone)
            local lo = GetOffsetFromEntityGivenWorldCoords(veh, wp.x, wp.y, wp.z)
            off = vector3(lo.x, lo.y + 0.08, lo.z + 0.66)
        else
            local d = CU.Dimensions(GetEntityModel(veh))
            off = vector3(-0.36, 0.0, d.max.z - 0.42)
        end
    end
    off = off + vector3(s.seatX, s.seatY, s.seatZ)
    seatCache.veh, seatCache.off, seatCache.at, seatCache.final = veh, off, now, seated
    return off
end

local function hoodOffset(veh, bumper)
    local d = CU.Dimensions(GetEntityModel(veh))
    if bumper then return vector3(0.0, d.max.y + 0.05, d.min.z + 0.48) end
    return vector3(0.0, d.max.y * 0.18, d.max.z * 0.82)
end

local function speedFov(base)
    local s = CU.Settings.camera
    if not s.speedFov then return base end
    local k = Util.Clamp((CU.Kmh(CU.Speed) - 60.0) / 240.0, 0.0, 1.0)
    return base + s.speedFovAmount * k * k
end

local function updateLook(dt, maxYaw, maxPitch)
    local s = CU.Settings.camera
    DisableControlAction(0, 1, true)
    DisableControlAction(0, 2, true)
    local lx, ly = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
    local kb = IsUsingKeyboard(2)
    local scale = kb and (s.lookSpeed * 1.6) or (s.lookSpeed * 60.0 * dt)
    if math.abs(lx) > 0.002 or math.abs(ly) > 0.002 then
        look.tYaw   = Util.Clamp(look.tYaw - lx * scale * (kb and 1.0 or 1.0), -maxYaw, maxYaw)
        look.tPitch = Util.Clamp(look.tPitch - ly * scale, -maxPitch, maxPitch)
        look.last = GetGameTimer()
    elseif GetGameTimer() - look.last > 1300 then
        look.tYaw = Util.Lerp(look.tYaw, 0.0, Util.Clamp(dt * 3.0, 0, 1))
        look.tPitch = Util.Lerp(look.tPitch, 0.0, Util.Clamp(dt * 3.0, 0, 1))
    end
    local lookBack = IsControlPressed(0, 79) or CU.Wheel.lookBack
    local ty = lookBack and 180.0 or look.tYaw
    local t = Util.Clamp(dt * 12.0, 0, 1)
    look.yaw = Util.Lerp(look.yaw, ty, t)
    look.pitch = Util.Lerp(look.pitch, lookBack and 0.0 or look.tPitch, t)
end

local function roadShake()
    if not CU.Settings.camera.shake then
        if roadShakeOn then StopCamShaking(cam, true) roadShakeOn = false end
        return
    end
    if GetGameTimer() < shakeUntil then return end
    if not roadShakeOn then
        ShakeCam(cam, 'ROAD_VIBRATION_SHAKE', 0.0)
        roadShakeOn = true
    end
    local k = Util.Clamp(CU.Kmh(CU.Speed) / 300.0, 0.0, 1.0)
    SetCamShakeAmplitude(cam, 0.05 + k * 0.55)
end

local function rayClamp(from, to, veh)
    local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 + 16, veh, 7)
    local _, hit, endPos = GetShapeTestResult(h)
    if hit == 1 then
        local dir = to - from
        local len = #dir
        if len > 0.01 then return endPos - (dir / len) * 0.25 end
    end
    return to
end

local function attached(veh, off, fov, pitchBase, dt)
    if attachedTo ~= veh then
        DetachCam(cam)
        attachedTo = veh
    end
    AttachCamToEntity(cam, veh, off.x, off.y, off.z, true)
    updateLook(dt, 150.0, 65.0)
    local r = GetEntityRotation(veh, 2)
    SetCamRot(cam, r.x + pitchBase + look.pitch, r.y, r.z + look.yaw, 2)
    curFov = Util.Lerp(curFov, speedFov(fov), Util.Clamp(dt * 4.0, 0, 1))
    SetCamFov(cam, curFov)
end

local function chaseCam(veh, dist, height, fov, side, dt)
    if attachedTo ~= 0 then DetachCam(cam) attachedTo = 0 end
    local s = CU.Settings.camera
    local d = CU.Dimensions(GetEntityModel(veh))
    local scale = Util.Clamp(d.length / 4.6, 0.85, 1.6)
    dist, height = dist * scale, height * scale

    local pos = GetEntityCoords(veh)
    local heading = GetEntityHeading(veh)
    local vel = GetEntityVelocity(veh)
    if #vel > 4.0 then   -- lean into slides by following the velocity a little
        local vh = math.deg(math.atan(-vel.x, vel.y))
        heading = Util.LerpAngle(heading, vh, 0.25)
    end
    updateLook(dt, 180.0, 40.0)
    heading = heading + look.yaw

    local t = 1.0 - math.exp(-dt / math.max(0.01, s.chaseLag))
    chase.heading = chase.heading and Util.LerpAngle(chase.heading, heading, t) or heading
    local rad = math.rad(chase.heading)
    local fwd = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local right = vector3(fwd.y, -fwd.x, 0.0)
    local want = pos - fwd * dist + vector3(0.0, 0.0, height) + right * side
    chase.pos = chase.pos and (chase.pos + (want - chase.pos) * Util.Clamp(t * 1.6, 0, 1)) or want
    -- never fall behind more than 1.5x the distance at high speed
    local gap = chase.pos - pos
    if #gap > dist * 1.5 then chase.pos = pos + gap / #gap * dist * 1.5 end

    local final = rayClamp(pos + vector3(0, 0, height * 0.6), chase.pos, veh)
    SetCamCoord(cam, final.x, final.y, final.z)
    local tilt = math.tan(math.rad(s.chaseTilt)) * dist
    local target = pos + fwd * 2.5 + vector3(0.0, 0.0, height * 0.42 - tilt * 0.25 + look.pitch * 0.03)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    curFov = Util.Lerp(curFov, speedFov(fov), Util.Clamp(dt * 4.0, 0, 1))
    SetCamFov(cam, curFov)
end

function Camera.Tick(dt)
    local veh = CU.Veh
    local s = CU.Settings.camera
    CU.Bonus.fpv = false
    if not (CU.Active or Config.Everywhere.Camera) or veh == 0 or not CU.IsDriver or s.mode == 'native'
        or IsPauseMenuActive() or IsEntityDead(CU.Ped) then
        Camera.Stop()
        return
    end

    DisableControlAction(0, 0, true)     -- native V cycle, we own the camera key now
    ensureCam()
    if not rendering then
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        rendering = true
        look.yaw, look.tYaw, look.pitch, look.tPitch = 0.0, 0.0, 0.0, 0.0
    end

    if s.mode == 'cockpit' then
        if Config.Camera.HideHead then
            if not prevViewMode then prevViewMode = GetFollowVehicleCamViewMode() end
            SetFollowVehicleCamViewMode(4)
        end
        attached(veh, cockpitOffset(veh), s.cockpitFov, s.pitch, dt)
        CU.Bonus.fpv = true
    else
        if prevViewMode then SetFollowVehicleCamViewMode(prevViewMode) prevViewMode = nil end
        if s.mode == 'hood' then
            attached(veh, hoodOffset(veh, false), s.hoodFov, -2.0, dt)
        elseif s.mode == 'bumper' then
            attached(veh, hoodOffset(veh, true), s.hoodFov, 0.0, dt)
        elseif s.mode == 'chase_far' then
            chaseCam(veh, s.chaseDistance * 1.45, s.chaseHeight * 1.4, s.chaseFov, 0.0, dt)
        elseif s.mode == 'cinematic' then
            chaseCam(veh, s.chaseDistance * 0.72, 0.55, s.chaseFov - 4.0, 0.85, dt)
        else
            chaseCam(veh, s.chaseDistance, s.chaseHeight, s.chaseFov, 0.0, dt)
        end
    end
    roadShake()
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Camera.Stop() end
end)
