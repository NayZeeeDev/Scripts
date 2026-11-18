if not NAYZEEE_LOCK_OK then return end

--[[
    Admin scene tools (server gates the commands).
      nzm:client:coords (themeId?)   copies a placement + camera, absolute AND rel space of a theme main
                                     (vehicle-local too for in-flight themes) to the clipboard + F8
      nzm:client:editor (themeId)    loads a theme with dummy actors in a free-cam preview. Fire again,
                                     Backspace or ESC to leave. Enter = copy (aim at a spot: the placement
                                     is where the camera looks, the camera is where it stands).
    Freecam: mouse look, W/A/S/D move, Q/E down/up, Shift fast, Ctrl slow, wheel = FOV.
]]

Editor = { active = false, theme = nil, cam = nil, saved = nil }

local function relOffset(base, p)
    local dx, dy = p.x - base.x, p.y - base.y
    local f, r = NZ.Fwd(base.w), NZ.Right(base.w)
    return vec3(dx * r.x + dy * r.y, dx * f.x + dy * f.y, p.z - base.z)
end

local function nearestTheme(p)
    local best, bestD
    for id, t in pairs(Config.LobbyThemes) do
        local d = #(vec3(t.main.x, t.main.y, t.main.z) - p)
        if not bestD or d < bestD then best, bestD = id, d end
    end
    return best
end

local function camDir(rot)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    return vec3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
end

local function v3(v) return ('vec3(%.2f, %.2f, %.2f)'):format(v.x, v.y, v.z) end

local function copyCoords(themeId)
    local camPos, camRot, fov
    if Editor.cam and DoesCamExist(Editor.cam) then
        camPos, camRot, fov = GetCamCoord(Editor.cam), GetCamRot(Editor.cam, 2), GetCamFov(Editor.cam)
    else
        camPos, camRot, fov = GetGameplayCamCoord(), GetGameplayCamRot(2), GetGameplayCamFov()
    end
    local dir = camDir(camRot)
    local look = camPos + dir * 3.0

    -- Placement point: where the free-cam aims (editor), else the player ped
    local pos, heading
    if Editor.active then
        local to = camPos + dir * 60.0
        local h = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z, to.x, to.y, to.z, 1 | 16, 0, 7)
        local _, hit, at = GetShapeTestResult(h)
        pos = (hit == 1 or hit == true) and at or look
        heading = (camRot.z + 180.0) % 360.0     -- facing the camera
    else
        pos, heading = GetEntityCoords(PlayerPedId()), GetEntityHeading(PlayerPedId())
    end

    local id = (themeId and NZ.Theme(themeId) and themeId) or Editor.theme or nearestTheme(pos)
    local theme = NZ.Theme(id)
    local base = (Editor.active and Scene.id == id and Scene.main) or theme.main
    local lines = {
        ('-- theme "%s"  main = vec4(%.2f, %.2f, %.2f, %.1f)'):format(id, base.x, base.y, base.z, base.w),
        ('coords = vec4(%.4f, %.4f, %.4f, %.2f),'):format(pos.x, pos.y, pos.z, heading),
        ('{ offset = %s, heading = %.1f },'):format(v3(relOffset(base, pos)), ((heading - base.w + 180.0) % 360.0) - 180.0),
        ('camera = { offset = %s, lookAt = %s, fov = %.1f },'):format(v3(relOffset(base, camPos)), v3(relOffset(base, look)), fov),
    }
    if Scene.flying and DoesEntityExist(Scene.flying) then
        local veh = Scene.flying
        local lp = GetOffsetFromEntityGivenWorldCoords(veh, pos.x, pos.y, pos.z)
        local lc = GetOffsetFromEntityGivenWorldCoords(veh, camPos.x, camPos.y, camPos.z)
        local ll = GetOffsetFromEntityGivenWorldCoords(veh, look.x, look.y, look.z)
        lines[#lines + 1] = ('-- vehicle-local: seat offset = %s, camera = { offset = %s, lookAt = %s, fov = %.1f }'):format(v3(lp), v3(lc), v3(ll), fov)
    end
    local text = table.concat(lines, '\n')
    lib.setClipboard(text)
    print(text)
    ClientBridge.Notify(NZ.T('done'), 'success')
end

RegisterNetEvent('nzm:client:coords', function(themeId) copyCoords(themeId) end)

-- ── preview ──────────────────────────────────────────────────────────────
local function dummies()
    local pet = Config.Pets.list and Config.Pets.list[1]
    local char = {
        id = '__editor', slot = 1, name = 'Slot 1', firstname = 'Slot', lastname = '1', gender = 'm',
        job = { label = 'Main' }, prefs = {},
        pet = pet and { id = pet.id, model = pet.model, name = pet.label } or nil,
    }
    local links = {}
    for slot = 2, 4 do
        links[#links + 1] = { id = -slot, type = slot == 2 and 'couple' or 'squad', slot = slot, visible = true,
            other = { id = '__editor' .. slot, name = 'Slot ' .. slot, gender = slot == 2 and 'f' or 'm', prefs = {}, online = true } }
    end
    return char, { links = links, incoming = {}, outgoing = {} }
end

local function help()
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName('~INPUT_FRONTEND_ACCEPT~ copy  ~INPUT_FRONTEND_CANCEL~ exit  ~INPUT_SPRINT~ fast  ~INPUT_DUCK~ slow  Q/E down/up')
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function freecam(def)
    local pos = def and (def.coords or (def.attach and GetOffsetFromEntityInWorldCoords(def.attach, def.offset.x, def.offset.y, def.offset.z)))
        or (Scene.main and NZ.Rel(Scene.main, vec3(0.0, 5.0, 0.6))) or GetEntityCoords(PlayerPedId())
    local look = (def and def.lookAt) or (Scene.main and vec3(Scene.main.x, Scene.main.y, Scene.main.z)) or pos
    local d = look - pos
    local rot = vec3(math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y))), 0.0, NZ.HeadingTo(pos, look))
    local fov = (def and def.fov) or 50.0
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, rot.x, 0.0, rot.z, fov, true, 2)
    Editor.cam = cam
    RenderScriptCams(true, false, 0, true, true)
    CreateThread(function()
        local focusAt = 0
        while Editor.active and DoesCamExist(cam) do
            DisableAllControlActions(0)
            DisableControlAction(2, 200, true)
            SetPauseMenuActive(false)
            EnableControlAction(0, 245, true)        -- chat
            EnableControlAction(0, 249, true)        -- push to talk
            local rx = math.max(-89.0, math.min(89.0, rot.x - GetDisabledControlNormal(0, 2) * 6.0))
            rot = vec3(rx, 0.0, rot.z - GetDisabledControlNormal(0, 1) * 6.0)
            local speed = IsDisabledControlPressed(0, 21) and 0.6 or (IsDisabledControlPressed(0, 36) and 0.02 or 0.12)
            local fwd = camDir(rot)
            local right = vec3(math.cos(math.rad(rot.z)), math.sin(math.rad(rot.z)), 0.0)
            local move = vec3(0.0, 0.0, 0.0)
            if IsDisabledControlPressed(0, 32) then move = move + fwd end      -- W
            if IsDisabledControlPressed(0, 33) then move = move - fwd end      -- S
            if IsDisabledControlPressed(0, 34) then move = move - right end    -- A
            if IsDisabledControlPressed(0, 35) then move = move + right end    -- D
            if IsDisabledControlPressed(0, 38) then move = move + vec3(0.0, 0.0, 1.0) end   -- E
            if IsDisabledControlPressed(0, 44) then move = move - vec3(0.0, 0.0, 1.0) end   -- Q
            pos = pos + move * speed
            if IsDisabledControlJustPressed(0, 241) then fov = math.max(10.0, fov - 2.0) end
            if IsDisabledControlJustPressed(0, 242) then fov = math.min(100.0, fov + 2.0) end
            SetCamCoord(cam, pos.x, pos.y, pos.z)
            SetCamRot(cam, rot.x, 0.0, rot.z, 2)
            SetCamFov(cam, fov)
            if not Scene.flying and GetGameTimer() > focusAt then
                SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
                focusAt = GetGameTimer() + 500
            end
            help()
            if IsDisabledControlJustPressed(0, 201) or IsDisabledControlJustPressed(0, 191) then copyCoords(Editor.theme) end
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) then
                CreateThread(Editor.Stop)
                break
            end
            Wait(0)
        end
    end)
end

function Editor.Start(themeId)
    if Editor.active then return Editor.Stop() end
    if Main.open then return ClientBridge.Notify(NZ.T('t_relog_busy'), 'error') end
    local theme = NZ.Theme(themeId)
    if not theme then return ClientBridge.Notify(NZ.T('not_found'), 'error') end
    local ped = PlayerPedId()
    Editor.saved = { coords = GetEntityCoords(ped), heading = GetEntityHeading(ped) }
    Editor.active, Editor.theme = true, themeId
    U.FadeOut(400)
    ClientBridge.Hud(false)
    World.PauseSync(true)
    Scene.Load(themeId, theme.mood)
    local char, squad = dummies()
    Actors.Show(char, squad)
    Lights.Start()
    Cam.Stop()
    local cams = theme.cameras
    freecam(cams and cams.squad and Cam.Point(cams.squad, cams.attach, false) or Cam.Frame('squad'))
    U.FadeIn(500)
end

function Editor.Stop()
    if not Editor.active then return end
    Editor.active = false
    U.FadeOut(300)
    if Editor.cam and DoesCamExist(Editor.cam) then DestroyCam(Editor.cam, false) end
    Editor.cam = nil
    RenderScriptCams(false, false, 0, true, true)
    Scene.Teardown()
    Lights.Stop()
    World.Restore()
    World.PauseSync(false)
    local s = Editor.saved
    local ped = PlayerPedId()
    if s then
        SetEntityCoordsNoOffset(ped, s.coords.x, s.coords.y, s.coords.z, false, false, false)
        SetEntityHeading(ped, s.heading)
    end
    U.ShowPlayer()
    ClientBridge.Hud(true)
    Editor.saved, Editor.theme = nil, nil
    Wait(200)
    U.FadeIn(400)
end

RegisterNetEvent('nzm:client:editor', function(themeId)
    CreateThread(function() Editor.Start(themeId) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZ.Resource or not Editor.active then return end
    Editor.active = false
    if Editor.cam and DoesCamExist(Editor.cam) then DestroyCam(Editor.cam, false) end
    RenderScriptCams(false, false, 0, true, true)
    Scene.Teardown()
    World.Restore()
    World.PauseSync(false)
    U.ShowPlayer()
    ClientBridge.Hud(true)
    DoScreenFadeIn(0)
end)
