if not NAYZEEE_LOCK_OK then return end

--[[
    "PRESS ENTER TO CONTINUE" title screen over the lobby (contract §6.1 step 2).
    Camera = theme.cameras.start (or the squad shot pulled back), with a slow arc around the lobby
    while the title is up (Config.StartScreen.orbit). Skipped on /relog.
]]

Start = { orbiting = false, token = 0 }

-- Start camera definition (rel space, or vehicle-local for in-flight themes)
local function startDef()
    local cams = Scene.theme and Scene.theme.cameras
    if cams and cams.start then
        local d = Cam.Point(cams.start, cams.attach, false)
        if d then return d end
    end
    local d = Cam.Frame('squad')
    if not d then return nil end
    if d.attach or not d.coords then return d end
    local fwd = NZ.Fwd(Scene.main.w)
    d.coords = d.coords + fwd * 3.5 + vec3(0.0, 0.0, 1.4)
    d.fov, d.dof = (d.fov or 44.0) + 6.0, false
    return d
end

-- Slow ±20° arc around the look-at point (period ~40 s); one cam, moved every frame while the title is up
local function orbit(def)
    if not Config.StartScreen.orbit or Settings.Get('perf') then return end
    Start.orbiting = true
    Start.token = Start.token + 1
    local my = Start.token
    CreateThread(function()
        local cam = Cam.current
        local t0 = GetGameTimer()
        local center = def.attach and def.look or def.lookAt
        local from = def.attach and def.offset or def.coords
        if not center or not from then return end
        local dx, dy = from.x - center.x, from.y - center.y
        local r, base = math.sqrt(dx * dx + dy * dy), math.atan(dy, dx)
        while Start.orbiting and Start.token == my and Main.open and Main.mode == 'start' and Cam.current == cam do
            local a = base + math.rad(20.0) * math.sin((GetGameTimer() - t0) / 40000.0 * 2.0 * math.pi)
            local x, y = center.x + math.cos(a) * r, center.y + math.sin(a) * r
            if def.attach then
                if not DoesEntityExist(def.attach) then break end
                AttachCamToEntity(cam, def.attach, x, y, from.z, true)
            else
                SetCamCoord(cam, x, y, from.z)
                PointCamAtCoord(cam, center.x, center.y, center.z)
            end
            Wait(0)
        end
    end)
end

-- Same shot pulled back, higher and wider: the title opens on this and slowly pushes in
local function introDef(def)
    local d = {}
    for k, v in pairs(def) do d[k] = v end
    local S = Config.StartScreen
    local back, up = S.pushBack or 0.45, S.pushUp or 1.1
    if def.attach then
        if not def.offset or not def.look then return nil end
        d.offset = def.offset + (def.offset - def.look) * back + vec3(0.0, 0.0, up)
    else
        if not def.coords or not def.lookAt then return nil end
        d.coords = def.coords + (def.coords - def.lookAt) * back + vec3(0.0, 0.0, up)
    end
    d.fov = (def.fov or 45.0) + 8.0
    return d
end

function Start.Show()
    Main.mode = 'start'
    local S = Config.StartScreen
    local def = startDef()
    local name = GetPlayerName(PlayerId())
    Main.WaitNui()
    -- The title mounts under the veil and plays its entrance the moment the veil starts lifting
    Start.payload = {
        serverName = Config.UI.serverName,
        tagline    = Config.UI.tagline,
        playerName = name,
        subtitle   = S.subtitle and S.subtitle:format(name) or nil,
        logo       = Config.UI.logo,
        prompt     = S.prompt,
        socials    = Config.UI.socials,
    }
    U.Send('start', Start.payload)
    SetNuiFocus(true, true)
    local intro = def and introDef(def)
    if intro then Cam.Go(intro, 0) elseif def then Cam.Go(def, 0) end
    Audio.Theme(Scene.id, S.music)          -- the UI fades the ambience up with the picture
    Main.Reveal(S.revealTime or 1800)
    if def and intro then
        -- Push in to the title shot, then settle into the slow orbit
        CreateThread(function()
            if Cam.Go(def, S.pushInTime or 4800) and Main.mode == 'start' then orbit(def) end
        end)
    elseif def then
        orbit(def)
    end
end

function Start.Continue()
    if Main.mode ~= 'start' then return end
    Start.orbiting = false
    Start.token = Start.token + 1
    Main.OpenLobby(true)
end
