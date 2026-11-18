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

function Start.Show()
    Main.mode = 'start'
    local def = startDef()
    if def then
        Cam.Go(def, 0)
        orbit(def)
    end
    local name = GetPlayerName(PlayerId())
    local S = Config.StartScreen
    Main.WaitNui()
    Audio.Theme(Scene.id, S.music)          -- start screen music, else the theme ambience
    U.Send('start', {
        serverName = Config.UI.serverName,
        tagline    = Config.UI.tagline,
        playerName = name,
        subtitle   = S.subtitle and S.subtitle:format(name) or nil,
        logo       = Config.UI.logo,
        prompt     = S.prompt,
        socials    = Config.UI.socials,
    })
    SetNuiFocus(true, true)
    U.FadeIn(900)
end

function Start.Continue()
    if Main.mode ~= 'start' then return end
    Start.orbiting = false
    Start.token = Start.token + 1
    Main.OpenLobby(true)
end
