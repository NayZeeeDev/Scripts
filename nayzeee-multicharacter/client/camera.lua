if not NAYZEEE_LOCK_OK then return end

--[[
    Scripted cameras.
      Cam.Go(def, ms)      eased move to { coords, lookAt | rot | entity, fov, dof, focus, shake }. Blocks until done.
                           Returns false when a newer move started meanwhile (sequence guard).
      Cam.Mode(mode, ms)   lobby framing: squad | duo | body | face (theme override or automatic)
      Cam.Aerial(coords)   spawn selector preview definition
      Cam.Stop()           back to the gameplay camera, every cam destroyed
    Idle motion: ShakeCam sway + a slow dolly drift that alternates between two close points
    (thread only while the lobby is open and nothing else is happening).
]]

Cam = { current = nil, old = {}, seq = 0, dofOn = false, frame = nil, driftOn = false }

local C = Config.Camera

local function idleFx()
    return Settings.Get('sway') and not Settings.Get('perf')
end

local function dofAllowed(def)
    return def.dof and Settings.Get('dof') and not Settings.Get('perf')
end

-- SetUseHiDof must be called every frame for shallow DoF to render
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

local function build(def)
    local c = def.coords
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.x, c.y, c.z, 0.0, 0.0, 0.0, (def.fov or 45.0) + 0.0, false, 2)
    if def.entity and DoesEntityExist(def.entity) then
        local o = def.entityOffset or vec3(0.0, 0.0, 0.0)
        PointCamAtEntity(cam, def.entity, o.x, o.y, o.z, true)
    elseif def.lookAt then
        PointCamAtCoord(cam, def.lookAt.x, def.lookAt.y, def.lookAt.z)
    elseif def.rot then
        SetCamRot(cam, def.rot.x, def.rot.y, def.rot.z, 2)
    end
    if dofAllowed(def) then
        local d = C.dof
        local focus = def.focus or 3.0
        SetCamUseShallowDofMode(cam, true)
        SetCamNearDof(cam, d.near or 0.2)
        SetCamFarDof(cam, focus + (d.bias or 1.25))
        SetCamDofStrength(cam, d.strength or 0.85)
        SetCamDofMaxNearInFocusDistance(cam, math.max(focus - 0.6, 0.3))
        SetCamDofFocusDistanceBias(cam, 0.0)
    end
    if def.shake ~= false and idleFx() and C.sway and C.sway.shake then
        ShakeCam(cam, C.sway.shake, (C.sway.amplitude or 0.14) + 0.0)
    end
    return cam
end

-- A camera at the exact rendered position: interpolating from it never jumps,
-- even when the previous move (or drift leg) is still half way.
local function snapshot()
    local p, r = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x, p.y, p.z, r.x, r.y, r.z, GetFinalRenderedCamFov(), false, 2)
    SetCamActive(cam, true)
    return cam
end

local function cleanup()
    for i = #Cam.old, 1, -1 do
        local c = Cam.old[i]
        if c ~= Cam.current and DoesCamExist(c) then DestroyCam(c, false) end
        Cam.old[i] = nil
    end
end

-- opts.drift = internal drift leg (keeps the drift running)
function Cam.Go(def, ms, opts)
    if not def or not def.coords then return false end
    Cam.seq = Cam.seq + 1
    local my = Cam.seq
    if not (opts and opts.drift) then Cam.driftOn = false end

    local cam = build(def)
    local prev = Cam.current
    if prev and ms and ms > 0 and IsCamRendering(prev) then
        if IsCamInterpolating(prev) or (opts and opts.snapshot) then
            Cam.old[#Cam.old + 1] = prev
            prev = snapshot()
        end
        Cam.old[#Cam.old + 1] = prev
        Cam.current = cam
        -- SetCamActiveWithInterp(camTo, camFrom, duration, easeLocation, easeRotation)
        SetCamActiveWithInterp(cam, prev, ms, C.ease or 1, C.ease or 1)
        RenderScriptCams(true, false, 0, true, true)
    else
        if prev then Cam.old[#Cam.old + 1] = prev end
        Cam.current = cam
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
    end
    if dofAllowed(def) then dofLoop() else Cam.dofOn = false end

    if ms and ms > 0 then
        local deadline = GetGameTimer() + ms + 50
        while GetGameTimer() < deadline and Cam.seq == my do Wait(0) end
    end
    if Cam.seq ~= my then return false end
    cleanup()
    return true
end

-- ── lobby framing ────────────────────────────────────────────────────────
local function override(mode)
    local theme, base = Scene.theme, Scene.main
    local o = theme and theme.cameras and theme.cameras[mode]
    if not o or not base then return nil end
    local m = C.modes[mode] or {}
    local coords = NZ.Rel(base, o.offset)
    local look = NZ.Rel(base, o.lookAt or vec3(0.0, 0.0, 0.0))
    return { coords = coords, lookAt = look, fov = o.fov or m.fov, dof = m.dof, focus = #(coords - look) }
end

-- Which marks a mode frames
local function targets(mode)
    local list = {}
    if mode == 'squad' then
        for _, a in pairs(Actors.list) do list[#list + 1] = a.mark end
        if Actors.pet then list[#list + 1] = Actors.pet.mark end
    elseif mode == 'duo' then
        if Actors.list[1] then list[#list + 1] = Actors.list[1].mark end
        if Actors.list[2] then list[#list + 1] = Actors.list[2].mark end
    else
        if Actors.list[1] then list[#list + 1] = Actors.list[1].mark end
    end
    if #list == 0 and Scene.main then list[1] = Scene.main end
    return list
end

-- Camera definition for a lobby mode
function Cam.Frame(mode)
    if mode == 'duo' and not Actors.list[2] then mode = 'body' end
    local base = Scene.main
    if not base then return nil end
    local ov = override(mode)
    if ov then return ov end

    local m = C.modes[mode] or C.modes.squad
    local pts = targets(mode)
    local cx, cy, cz = 0.0, 0.0, 0.0
    for _, p in ipairs(pts) do cx, cy, cz = cx + p.x, cy + p.y, cz + p.z end
    local n = #pts
    local center = vec3(cx / n, cy / n, cz / n)
    local fwd, right = NZ.Fwd(base.w), NZ.Right(base.w)

    -- Pull back when the squad is spread wide
    local dist = m.distance
    if mode == 'squad' or mode == 'duo' then
        local spread = 0.0
        for _, p in ipairs(pts) do
            local d = math.abs((p.x - center.x) * right.x + (p.y - center.y) * right.y)
            if d > spread then spread = d end
        end
        dist = dist + math.max(0.0, spread * 2.0 - 2.4) * 0.9
    end

    local coords = center + fwd * dist + right * (m.side or 0.0) + vec3(0.0, 0.0, m.height or 0.0)
    local look = center + vec3(0.0, 0.0, m.lookHeight or 0.0)
    return { coords = coords, lookAt = look, fov = m.fov, dof = m.dof, focus = dist }
end

-- Slow dolly back and forth between the framed point and a point `distance` to the side
local function drift(def)
    local d = C.drift
    if not d or not d.enabled or not idleFx() then return end
    Cam.driftOn = true
    CreateThread(function()
        local right = Scene.main and NZ.Right(Scene.main.w) or vec3(1.0, 0.0, 0.0)
        local a = def
        local b = NZ.Copy(def)
        b.coords = def.coords + right * (d.distance or 0.22) + vec3(0.0, 0.0, (d.distance or 0.22) * 0.25)
        local toB = true
        while Cam.driftOn and Main.open do
            if Main.busy or (Main.mode ~= 'lobby' and Main.mode ~= 'create') then
                Wait(250)
            else
                if not Cam.Go(toB and b or a, d.time or 9000, { drift = true }) then break end
                toB = not toB
            end
        end
    end)
end

function Cam.Mode(mode, ms)
    local def = Cam.Frame(mode or C.defaultMode)
    if not def then return false end
    Cam.frame = def
    local ok = Cam.Go(def, ms or C.transition)
    if ok then drift(def) end
    return ok
end

-- Spawn selector: high oblique shot over a world point
function Cam.Aerial(coords)
    local a = C.aerial
    local h = coords.w or 0.0
    local back = NZ.Fwd(h) * -(a.back or 90.0)
    return {
        coords = vec3(coords.x + back.x, coords.y + back.y, coords.z + (a.height or 140.0)),
        lookAt = vec3(coords.x, coords.y, coords.z),
        fov    = a.fov or 42.0,
        shake  = false,
    }
end

function Cam.Stop()
    Cam.seq = Cam.seq + 1
    Cam.driftOn, Cam.dofOn, Cam.frame = false, false, nil
    RenderScriptCams(false, false, 0, true, true)
    if Cam.current and DoesCamExist(Cam.current) then DestroyCam(Cam.current, false) end
    for i = 1, #Cam.old do
        if DoesCamExist(Cam.old[i]) then DestroyCam(Cam.old[i], false) end
    end
    Cam.current, Cam.old = nil, {}
end
