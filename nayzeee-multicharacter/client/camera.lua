if not NAYZEEE_LOCK_OK then return end

Cam = { current = nil, old = {}, seq = 0, dofOn = false }

local function build(def)
    local c = def.coords
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.x, c.y, c.z, 0.0, 0.0, 0.0, def.fov or 45.0, false, 2)
    if def.pointAt then
        PointCamAtCoord(cam, def.pointAt.x, def.pointAt.y, def.pointAt.z)
    elseif def.rot then
        SetCamRot(cam, def.rot.x, def.rot.y, def.rot.z, 2)
    end
    return cam
end

local function dofLoop()
    if Cam.dofOn then return end
    Cam.dofOn = true
    CreateThread(function()
        while Cam.dofOn and Cam.current do
            SetUseHiDof()
            Wait(0)
        end
        Cam.dofOn = false
    end)
end

local function applyLook(cam, def)
    local fps = Settings.Get('fps')
    if def.dof and Config.Scene.dof and not fps then
        SetCamUseShallowDofMode(cam, true)
        SetCamNearDof(cam, 0.3)
        SetCamFarDof(cam, (def.dofFar or 4.0) + 0.0)
        SetCamDofStrength(cam, 1.0)
        SetCamDofMaxNearInFocusDistance(cam, 1.0)
        SetCamDofFocusDistanceBias(cam, 1.5)
        dofLoop()
    end
    local sh = Config.Scene.shake
    if sh.enabled and not fps then ShakeCam(cam, sh.type, sh.amplitude + 0.0) end
end

-- Move to a camera definition. ms = 0 cuts instantly. Returns false if a newer move started.
function Cam.Go(def, ms)
    Cam.seq = Cam.seq + 1
    local my = Cam.seq
    local cam = build(def)
    applyLook(cam, def)
    local prev = Cam.current
    Cam.current = cam
    if prev and ms and ms > 0 then
        Cam.old[#Cam.old + 1] = prev
        SetCamActiveWithInterp(cam, prev, ms, 1, 1)
        local deadline = GetGameTimer() + ms + 100
        while GetGameTimer() < deadline and Cam.seq == my do Wait(0) end
    else
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        if prev then Cam.old[#Cam.old + 1] = prev end
    end
    if Cam.seq ~= my then return false end
    for i = #Cam.old, 1, -1 do
        if Cam.old[i] ~= Cam.current then DestroyCam(Cam.old[i], false) end
        Cam.old[i] = nil
    end
    return true
end

function Cam.Stop(ease, ms)
    Cam.seq = Cam.seq + 1
    Cam.dofOn = false
    RenderScriptCams(false, ease == true, ms or 0, true, true)
    if Cam.current then DestroyCam(Cam.current, false) end
    for i = 1, #Cam.old do DestroyCam(Cam.old[i], false) end
    Cam.current, Cam.old = nil, {}
end

-- Focus shot on a ped. Frames the ped right of centre so the dossier (left) never covers it.
function Cam.Focus(ped, override)
    if override then
        return { coords = override.coords, pointAt = override.pointAt, rot = override.rot, fov = override.fov or 30.0, dof = true, dofFar = 3.5 }
    end
    local key = Settings.Get('distance') or 'normal'
    local d = Config.Scene.distance[key] or Config.Scene.distance.normal
    local head = U.Head(ped)
    local k = d / 2.1
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.28 * k, d, 0.0)
    local look = GetOffsetFromEntityInWorldCoords(ped, 0.42 * k, 0.0, 0.0)
    local zCam = head.z - (key == 'far' and 0.2 or (key == 'close' and 0.02 or 0.1))
    return {
        coords  = vec3(pos.x, pos.y, zCam),
        pointAt = vec3(look.x, look.y, head.z - (key == 'close' and 0.22 or 0.38)),
        fov     = key == 'close' and 38.0 or 42.0,
        dof     = true,
        dofFar  = d + 1.3,
    }
end

-- Aerial preview over a world point (spawn selector)
function Cam.Aerial(coords)
    local p = Config.Spawn.preview
    local h = coords.w or 0.0
    local rad = math.rad(h)
    local bx, by = math.sin(rad) * p.back, -math.cos(rad) * p.back
    return {
        coords  = vec3(coords.x + bx, coords.y + by, coords.z + p.height),
        pointAt = vec3(coords.x, coords.y, coords.z),
        fov     = p.fov,
    }
end

-- Normalised screen positions (0..1) for a list of world points
function Cam.Project(points)
    local out = {}
    for i = 1, #points do
        local w = points[i]
        local on, x, y = GetScreenCoordFromWorldCoord(w.pos.x, w.pos.y, w.pos.z)
        out[#out + 1] = { slot = w.slot, x = x, y = y, visible = on }
    end
    return out
end
