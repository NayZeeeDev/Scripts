--[[
    NAYZEEE AMBULANCE - Client core: scripted cameras (NZA.Cam)

    One camera rig at a time; starting a new one blends from the old one.

      NZA.Cam.Orbit(target, opts)          orbit around an entity / coords
          target = entity | vector3 | { entity, bone, offset, coords }
          opts   = { dist = 2.2, height = 0.0, fov = 45, pitch = 20 (deg), yaw (deg, world),
                     front = false (start in front of the entity instead of from the current
                     view side), minDist, maxDist, minPitch, maxPitch, orbit = true,
                     pan = true, zoom = true, panLimit = 1.5, ease = 600, hideHud = true }
      NZA.Cam.Close(entity, boneOrOffset, opts)
          close-up on a bone id, a region name ('l_lower_leg') or an entity offset (vector3).
          Defaults: dist 0.75, pitch 55, fov 40, orbit off (opts.orbit = true enables it),
          zoom on, camera on the medic's side.
      NZA.Cam.TopDown(entity, height, opts)  straight down, rotated with the entity
      NZA.Cam.Stop(ease)                   blend back to the gameplay camera (default 500 ms)
      NZA.Cam.Update(opts)                 change dist / pitch / yaw / fov / height targets
      NZA.Cam.Recenter()  NZA.Cam.Active() → mode|nil  NZA.Cam.Handle() → cam|nil
      NZA.Cam.Focus() → vector3            current focus point

    Controls while a rig is active (all player controls are disabled except push-to-talk):
      right mouse drag = orbit, Shift + right mouse drag = pan, wheel = zoom, R = recentre.
    Mouse input is read from the game (works when no NUI has focus, or the focused app uses
    keepInput = true). Apps that keep the mouse in the NUI can forward drags through the
    '_core:camInput' NUI callback { dx, dy (screen fractions), wheel (-1|1), pan, recenter }.

      NZA.Cam.CursorPosition() → sx, sy (0..1)   NUI cursor when focused, else game cursor
      NZA.Cam.ScreenToWorld(sx, sy) → origin, direction   (rendered camera matrix + fov)
      NZA.Cam.Raycast(opts) → { hit, coords, entity, normal, origin, dir, x, y }
          opts = { x, y (screen 0..1, default cursor), dist = 15, flags = -1, ignore = own ped }
      NZA.Cam.WorldToScreen(coords) → x, y, visible
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Cam = NZA.Cam or {}
local Cam = NZA.Cam
local U = NZA.Util

local DEG = math.pi / 180
local ZERO = vector3(0.0, 0.0, 0.0)
local ORBIT_SENS = 6.0
local PITCH_SENS = 4.0

local rig = nil
local loopRunning = false
local ext = { dx = 0.0, dy = 0.0, wheel = 0, pan = false, recenter = false }

-- ════════════════════════════════════════════════════════════════════════
-- MATH
-- ════════════════════════════════════════════════════════════════════════

local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function normalize(v)
    local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if l < 1e-6 then return ZERO end
    return v / l
end

local function camOffset(yaw, pitch, dist)
    local cp = math.cos(pitch)
    return vector3(math.cos(yaw) * cp * dist, math.sin(yaw) * cp * dist, math.sin(pitch) * dist)
end

local function rotToDir(rot)
    local x, z = rot.x * DEG, rot.z * DEG
    local cx = math.abs(math.cos(x))
    return vector3(-math.sin(z) * cx, math.cos(z) * cx, math.sin(x))
end

local function smooth(cur, target, k)
    return cur + (target - cur) * k
end

local function clampPan(p, limit)
    local l = #p
    if l > limit then return p / l * limit end
    return p
end

-- ════════════════════════════════════════════════════════════════════════
-- RIG
-- ════════════════════════════════════════════════════════════════════════

local function focusBase(r)
    local ent = r.entity
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        local off = r.offset or ZERO
        if r.bone and IsEntityAPed(ent) then
            return GetPedBoneCoords(ent, r.bone, off.x, off.y, off.z)
        end
        if r.boneName then
            local idx = GetEntityBoneIndexByName(ent, r.boneName)
            if idx ~= -1 then return GetWorldPositionOfEntityBone(ent, idx) + off end
        end
        return GetOffsetFromEntityInWorldCoords(ent, off.x, off.y, off.z)
    end
    return r.coords or r.focus or GetEntityCoords(PlayerPedId())
end

local function parseTarget(r, target)
    if type(target) == 'number' then
        r.entity = target
    elseif type(target) == 'vector3' or type(target) == 'vector4' then
        r.coords = U.vec(target)
    elseif type(target) == 'table' then
        r.entity = target.entity
        r.bone = target.bone
        r.boneName = target.boneName
        r.offset = target.offset and U.vec(target.offset) or nil
        r.coords = target.coords and U.vec(target.coords) or nil
    end
end

-- yaw (radians) that puts the camera on the side of `from` as seen from `focus`
local function yawToward(focus, from)
    local d = from - focus
    if math.abs(d.x) < 1e-4 and math.abs(d.y) < 1e-4 then return 0.0 end
    return math.atan(d.y, d.x)
end

local function frontYaw(ent)
    local f = GetEntityForwardVector(ent)
    return math.atan(f.y, f.x)
end

local function camPosition(r)
    if r.mode == 'top' then
        return r.focus + vector3(0.0, 0.0, r.height)
    end
    return r.focus + camOffset(r.yaw, r.pitch, r.dist)
end

local function applyCam(r)
    local pos = camPosition(r)
    SetCamCoord(r.cam, pos.x, pos.y, pos.z)
    if r.mode == 'top' then
        SetCamRot(r.cam, -89.5, 0.0, r.heading, 2)
    else
        PointCamAtCoord(r.cam, r.focus.x, r.focus.y, r.focus.z)
    end
    SetCamFov(r.cam, r.fov)
end

local function readInput(r)
    local dx, dy, wheel, rmb, shift, recenter = 0.0, 0.0, 0, false, false, false
    local nuiHasMouse = IsNuiFocused() and not (IsNuiFocusKeepingInput and IsNuiFocusKeepingInput())
    if not nuiHasMouse then
        rmb = IsDisabledControlPressed(0, 25)
        shift = IsDisabledControlPressed(0, 21)
        if rmb then
            dx = GetDisabledControlNormal(0, 1)
            dy = GetDisabledControlNormal(0, 2)
        end
        if IsDisabledControlJustPressed(0, 241) or IsDisabledControlJustPressed(0, 15) then wheel = wheel - 1 end
        if IsDisabledControlJustPressed(0, 242) or IsDisabledControlJustPressed(0, 14) then wheel = wheel + 1 end
        if IsDisabledControlJustPressed(0, 45) then recenter = true end
    end
    -- forwarded from the NUI (already only while dragging)
    if ext.dx ~= 0 or ext.dy ~= 0 then
        dx, dy = dx + ext.dx, dy + ext.dy
        rmb = true
        shift = shift or ext.pan
    end
    wheel = wheel + ext.wheel
    recenter = recenter or ext.recenter
    ext.dx, ext.dy, ext.wheel, ext.recenter = 0.0, 0.0, 0, false

    if recenter then Cam.Recenter() end
    if rmb and (dx ~= 0 or dy ~= 0) then
        if shift and r.allowPan then
            if r.mode == 'top' then
                local h = r.heading * DEG
                local right = vector3(math.cos(h), math.sin(h), 0.0)
                local upScreen = vector3(-math.sin(h), math.cos(h), 0.0)
                r.tPan = clampPan(r.tPan - right * (dx * r.tHeight) + upScreen * (dy * r.tHeight), r.panLimit)
            else
                local right = vector3(-math.sin(r.yaw), math.cos(r.yaw), 0.0)
                r.tPan = clampPan(r.tPan - right * (dx * r.tDist * 2.0) + vector3(0.0, 0.0, dy * r.tDist * 2.0), r.panLimit)
            end
        elseif r.allowOrbit then
            if r.mode == 'top' then
                r.tHeading = r.tHeading - dx * 180.0
            else
                r.tYaw = r.tYaw - dx * ORBIT_SENS
                r.tPitch = U.clamp(r.tPitch + dy * PITCH_SENS, r.minPitch, r.maxPitch)
            end
        end
    end
    if wheel ~= 0 and r.allowZoom then
        if r.mode == 'top' then
            r.tHeight = U.clamp(r.tHeight * (1 + 0.12 * wheel), r.minDist, r.maxDist)
        else
            r.tDist = U.clamp(r.tDist * (1 + 0.12 * wheel), r.minDist, r.maxDist)
        end
    end
end

local function runLoop()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        while rig do
            local r = rig
            DisableAllControlActions(0)
            EnableControlAction(0, 249, true)     -- push to talk
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            if r.hideHud then HideHudAndRadarThisFrame() end

            readInput(r)

            local k = 1.0 - math.exp(-GetFrameTime() * 10.0)
            r.yaw = smooth(r.yaw, r.tYaw, k)
            r.pitch = smooth(r.pitch, r.tPitch, k)
            r.dist = smooth(r.dist, r.tDist, k)
            r.fov = smooth(r.fov, r.tFov, k)
            r.height = smooth(r.height, r.tHeight, k)
            r.heading = smooth(r.heading, r.tHeading, k)
            r.pan = r.pan + (r.tPan - r.pan) * k
            local base = focusBase(r)
            r.focus = r.focus + ((base + r.pan) - r.focus) * math.min(1.0, k * 1.5)
            applyCam(r)
            Wait(0)
        end
        loopRunning = false
    end)
end

local function start(r, ease)
    ease = ease or 600
    -- start exactly on target so the blend goes to the final framing
    r.focus = focusBase(r)
    r.yaw, r.pitch, r.dist, r.fov = r.tYaw, r.tPitch, r.tDist, r.tFov
    r.height, r.heading = r.tHeight, r.tHeading
    r.pan, r.tPan = ZERO, ZERO
    r.home = { yaw = r.tYaw, pitch = r.tPitch, dist = r.tDist, height = r.tHeight, heading = r.tHeading, fov = r.tFov }

    r.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    applyCam(r)

    local old = rig
    rig = r
    if old and old.cam and DoesCamExist(old.cam) then
        SetCamActiveWithInterp(r.cam, old.cam, ease, 1, 1)
        local oldCam = old.cam
        SetTimeout(ease + 100, function()
            if DoesCamExist(oldCam) and (not rig or rig.cam ~= oldCam) then DestroyCam(oldCam, false) end
        end)
    else
        SetCamActive(r.cam, true)
        RenderScriptCams(true, ease > 0, ease, true, true)
    end
    runLoop()
    return r.cam
end

local function newRig(mode, opts)
    return {
        mode = mode,
        hideHud = opts.hideHud ~= false,
        allowOrbit = opts.orbit ~= false,
        allowPan = opts.pan ~= false,
        allowZoom = opts.zoom ~= false,
        panLimit = tonumber(opts.panLimit) or 1.5,
        tFov = tonumber(opts.fov) or 45.0,
        tYaw = 0.0, tPitch = 0.0, tDist = 2.0, tHeight = 3.0, tHeading = 0.0,
        minPitch = (tonumber(opts.minPitch) or -5.0) * DEG,
        maxPitch = (tonumber(opts.maxPitch) or 85.0) * DEG,
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC RIGS
-- ════════════════════════════════════════════════════════════════════════

function Cam.Orbit(target, opts)
    opts = opts or {}
    local r = newRig('orbit', opts)
    parseTarget(r, target)
    if opts.height and not r.offset and not r.bone then r.offset = vector3(0.0, 0.0, tonumber(opts.height) or 0.0) end
    r.tDist = tonumber(opts.dist) or 2.2
    r.minDist = tonumber(opts.minDist) or 0.6
    r.maxDist = tonumber(opts.maxDist) or 6.0
    r.tPitch = U.clamp((tonumber(opts.pitch) or 20.0) * DEG, r.minPitch, r.maxPitch)
    local focus = focusBase(r)
    if opts.yaw then
        r.tYaw = opts.yaw * DEG
    elseif opts.front and r.entity and DoesEntityExist(r.entity) then
        r.tYaw = frontYaw(r.entity)
    else
        r.tYaw = yawToward(focus, GetFinalRenderedCamCoord())
    end
    return start(r, opts.ease)
end

function Cam.Close(entity, boneOrOffset, opts)
    opts = opts or {}
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    if o.orbit == nil then o.orbit = false end
    if o.pan == nil then o.pan = false end
    if o.fov == nil then o.fov = 40.0 end
    if o.panLimit == nil then o.panLimit = 0.4 end
    local r = newRig('close', o)
    r.entity = entity
    if type(boneOrOffset) == 'string' then
        r.bone = NZA.Const.RegionBone[boneOrOffset]
        if not r.bone then r.boneName = boneOrOffset end
    elseif type(boneOrOffset) == 'number' then
        r.bone = boneOrOffset
    elseif boneOrOffset ~= nil then
        r.offset = U.vec(boneOrOffset)
    end
    if opts.offset and (r.bone or r.boneName) then r.offset = U.vec(opts.offset) end
    r.tDist = tonumber(opts.dist) or 0.75
    r.minDist = tonumber(opts.minDist) or 0.25
    r.maxDist = tonumber(opts.maxDist) or 2.0
    r.tPitch = U.clamp((tonumber(opts.pitch) or 55.0) * DEG, r.minPitch, r.maxPitch)
    local focus = focusBase(r)
    if opts.yaw then
        r.tYaw = opts.yaw * DEG
    else
        -- the medic looks at the wound from where they kneel
        r.tYaw = yawToward(focus, GetEntityCoords(PlayerPedId()))
    end
    return start(r, opts.ease)
end

function Cam.TopDown(entity, height, opts)
    opts = opts or {}
    local r = newRig('top', opts)
    parseTarget(r, entity)
    r.tHeight = tonumber(height) or 3.0
    r.minDist = tonumber(opts.minHeight) or 1.0
    r.maxDist = tonumber(opts.maxHeight) or 8.0
    if opts.heading then
        r.tHeading = opts.heading
    elseif r.entity and DoesEntityExist(r.entity) then
        r.tHeading = GetEntityHeading(r.entity)
    else
        r.tHeading = GetGameplayCamRot(2).z
    end
    return start(r, opts.ease)
end

function Cam.Stop(ease)
    if not rig then return end
    ease = tonumber(ease) or 500
    local cam = rig.cam
    rig = nil
    RenderScriptCams(false, ease > 0, ease, true, true)
    SetTimeout(ease + 100, function()
        if cam and DoesCamExist(cam) and (not rig or rig.cam ~= cam) then
            SetCamActive(cam, false)
            DestroyCam(cam, false)
        end
    end)
end

function Cam.Update(opts)
    local r = rig
    if not r or type(opts) ~= 'table' then return end
    if opts.dist then r.tDist = U.clamp(opts.dist, r.minDist, r.maxDist) end
    if opts.pitch then r.tPitch = U.clamp(opts.pitch * DEG, r.minPitch, r.maxPitch) end
    if opts.yaw then r.tYaw = opts.yaw * DEG end
    if opts.fov then r.tFov = opts.fov end
    if opts.height then r.tHeight = U.clamp(opts.height, r.minDist, r.maxDist) end
    if opts.heading then r.tHeading = opts.heading end
    if opts.orbit ~= nil then r.allowOrbit = opts.orbit end
    if opts.pan ~= nil then r.allowPan = opts.pan end
    if opts.zoom ~= nil then r.allowZoom = opts.zoom end
end

function Cam.Recenter()
    local r = rig
    if not r or not r.home then return end
    r.tYaw, r.tPitch, r.tDist = r.home.yaw, r.home.pitch, r.home.dist
    r.tHeight, r.tHeading, r.tFov = r.home.height, r.home.heading, r.home.fov
    r.tPan = ZERO
end

function Cam.Active()
    return rig and rig.mode or nil
end

function Cam.Handle()
    return rig and rig.cam or nil
end

function Cam.Focus()
    return rig and rig.focus or nil
end

-- NUI-forwarded mouse input (see header)
function Cam.Input(data)
    if type(data) ~= 'table' then return end
    ext.dx = ext.dx + U.clamp(tonumber(data.dx) or 0, -0.5, 0.5)
    ext.dy = ext.dy + U.clamp(tonumber(data.dy) or 0, -0.5, 0.5)
    local w = tonumber(data.wheel) or 0
    if w > 0 then ext.wheel = ext.wheel + 1 elseif w < 0 then ext.wheel = ext.wheel - 1 end
    ext.pan = data.pan == true
    if data.recenter then ext.recenter = true end
end

-- ════════════════════════════════════════════════════════════════════════
-- SCREEN ↔ WORLD
-- ════════════════════════════════════════════════════════════════════════

function Cam.CursorPosition()
    if IsNuiFocused() then
        local x, y = GetNuiCursorPosition()
        local w, h = GetActiveScreenResolution()
        if w and h and w > 0 and h > 0 then return x / w, y / h end
    end
    return GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
end

function Cam.ScreenToWorld(sx, sy)
    local origin = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local fov = GetFinalRenderedCamFov()
    local fwd = rotToDir(rot)
    local z = rot.z * DEG
    local right = vector3(math.cos(z), math.sin(z), 0.0)
    local up = cross(right, fwd)
    local t = math.tan(fov * DEG / 2.0)
    local aspect = GetAspectRatio(false)
    local nx, ny = (sx - 0.5) * 2.0, (0.5 - sy) * 2.0
    local dir = normalize(fwd + right * (nx * t * aspect) + up * (ny * t))
    return origin, dir
end

function Cam.Raycast(opts)
    opts = opts or {}
    local sx, sy = opts.x, opts.y
    if not sx or not sy then sx, sy = Cam.CursorPosition() end
    local origin, dir = Cam.ScreenToWorld(sx, sy)
    local to = origin + dir * (tonumber(opts.dist) or 15.0)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, to.x, to.y, to.z,
        opts.flags or -1, opts.ignore or PlayerPedId(), 7)
    local _, hit, coords, normal, entity = GetShapeTestResult(handle)
    return {
        hit = hit == true or hit == 1,
        coords = coords, normal = normal, entity = entity or 0,
        origin = origin, dir = dir, x = sx, y = sy,
    }
end

function Cam.WorldToScreen(coords)
    coords = U.vec(coords)
    if not coords then return 0.0, 0.0, false end
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    return x, y, onScreen == true or onScreen == 1
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource or not rig then return end
    local cam = rig.cam
    rig = nil
    RenderScriptCams(false, false, 0, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, false) end
end)
