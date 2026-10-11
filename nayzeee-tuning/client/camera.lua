--[[ Orbit camera around the vehicle. Only runs while the tuning menu is open. ]]

Cam = { active = false }

local cam, veh
local cur, goal = {}, {}
local turntable = false
local scale = 1.0

local PRESETS = {
    full     = { h = 38,  p = 12, d = 6.4, off = vec3(0.0, 0.0, 0.25) },
    front    = { h = 24,  p = 10, d = 5.2, off = vec3(0.0, 1.2, 0.25) },
    rear     = { h = 204, p = 12, d = 5.4, off = vec3(0.0, -1.2, 0.35) },
    side     = { h = 90,  p = 8,  d = 6.0, off = vec3(0.0, 0.0, 0.15) },
    wheel    = { h = 64,  p = 8,  d = 3.6, off = 'wheel_lf' },
    engine   = { h = 10,  p = 36, d = 4.2, off = vec3(0.0, 1.4, 0.5) },
    interior = { h = 195, p = 14, d = 1.25, off = vec3(0.0, 0.05, 0.62) },
    top      = { h = 35,  p = 60, d = 7.2, off = vec3(0.0, 0.0, 0.3) },
    plate    = { h = 190, p = 8,  d = 3.6, off = vec3(0.0, -2.0, 0.1) },
    exhaust  = { h = 212, p = 8,  d = 3.8, off = 'exhaust' },
}

local function resolveOffset(o)
    if type(o) == 'string' then
        local idx = GetEntityBoneIndexByName(veh, o)
        if idx ~= -1 then
            local world = GetWorldPositionOfEntityBone(veh, idx)
            return GetOffsetFromEntityGivenWorldCoords(veh, world.x, world.y, world.z)
        end
        return vec3(0.0, 0.0, 0.2)
    end
    return vec3(o.x, o.y * scale, o.z)
end

function Cam.Focus(name)
    local p = PRESETS[name] or PRESETS.full
    goal.h = p.h
    goal.p = p.p
    goal.d = p.d * (name == 'interior' and 1.0 or scale)
    goal.off = resolveOffset(p.off)
end

-- frame one spot on the car (a hotspot): the camera moves round to that side and backs off far
-- enough to show the whole area around it, not just the bone
function Cam.FocusSpot(bone, kind)
    if not veh then return end
    local idx = type(bone) == 'number' and bone or GetEntityBoneIndexByName(veh, bone)
    if not idx or idx == -1 then return end
    local w = GetWorldPositionOfEntityBone(veh, idx)
    local rel = GetOffsetFromEntityGivenWorldCoords(veh, w.x, w.y, w.z)
    local flat = math.sqrt(rel.x * rel.x + rel.y * rel.y)
    if kind == 'interior' then return Cam.Focus('interior') end
    if kind == 'top' or flat < 0.4 then
        -- centre of the car (roof, engine on mid-engine cars): look down from above the near side
        goal.h, goal.p, goal.d = goal.h or 38, 42, 5.4 * scale
    else
        goal.h = math.deg(math.atan(rel.x, rel.y))
        goal.p = kind == 'wheel' and 10 or 18
        goal.d = (kind == 'wheel' and 3.4 or 3.9) * math.max(0.85, scale)
    end
    goal.off = vec3(rel.x * 0.55, rel.y * 0.7, math.max(0.1, rel.z * 0.6))
end

-- dragging moves the car with the mouse: drag right and the car turns right
function Cam.Rotate(dx, dy)
    goal.h = (goal.h or 0) + dx * 0.28
    goal.p = NZ.Clamp((goal.p or 10) + dy * 0.18, -8.0, 78.0)
end

function Cam.Zoom(delta)
    goal.d = NZ.Clamp((goal.d or 5) + delta * 0.0045, 0.9, 13.0)
end

function Cam.Turntable(state) turntable = state end

local function lerp(a, b, t) return a + (b - a) * t end
local function lerpAngle(a, b, t)
    local d = ((b - a + 180) % 360) - 180
    return a + d * t
end

local function place()
    local h, p = math.rad(cur.h), math.rad(cur.p)
    local local_ = vec3(math.sin(h) * math.cos(p) * cur.d, math.cos(h) * math.cos(p) * cur.d, math.sin(p) * cur.d) + cur.off
    local pos = GetOffsetFromEntityInWorldCoords(veh, local_.x, local_.y, local_.z)
    local at = GetOffsetFromEntityInWorldCoords(veh, cur.off.x, cur.off.y, cur.off.z)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    PointCamAtCoord(cam, at.x, at.y, at.z)
end

function Cam.Start(vehicle)
    if Cam.active then Cam.Stop(true) end
    veh = vehicle
    local mn, mx = GetModelDimensions(GetEntityModel(veh))
    scale = NZ.Clamp((mx.y - mn.y) / 4.6, 0.55, 2.2)
    Cam.Focus('full')
    cur = { h = goal.h + 40, p = goal.p, d = goal.d + 2.0, off = goal.off }
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 50.0, false, 0)
    place()
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 700, true, true)
    Cam.active = true
    turntable = false

    CreateThread(function()
        while Cam.active and DoesEntityExist(veh) do
            if turntable then goal.h = goal.h + 0.12 end
            local t = 0.09
            cur.h = lerpAngle(cur.h, goal.h, t)
            cur.p = lerp(cur.p, goal.p, t)
            cur.d = lerp(cur.d, goal.d, t)
            cur.off = vec3(lerp(cur.off.x, goal.off.x, t), lerp(cur.off.y, goal.off.y, t), lerp(cur.off.z, goal.off.z, t))
            place()
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
end

function Cam.Stop(instant)
    if not Cam.active then return end
    Cam.active = false
    RenderScriptCams(false, not instant, instant and 0 or 600, true, true)
    if cam then DestroyCam(cam, false) cam = nil end
    veh = nil
end
