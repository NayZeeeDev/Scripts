if not NAYZEEE_LOCK_OK then return end

--[[
    Spawn flow (contract §6.1 steps 6-8).
      Spawn.Begin(charId, options, mode, isNew)   selector (NUI `spawn` + aerial previews) / direct / custom hand-off
      Spawn.Hover(id)                             aerial preview of an option
      Spawn.Confirm(id)                           nzm:spawn -> departure cutscene -> Spawn.Enter
      Spawn.Enter(coords)                         teardown everything, ground-safe teleport, fade in
]]

Spawn = { options = nil, byId = {}, charId = nil, isNew = false, aerial = false, arrival = nil, busy = false }

function Spawn.Clear()
    Spawn.options, Spawn.byId, Spawn.charId, Spawn.aerial, Spawn.busy, Spawn.list = nil, {}, nil, false, false, nil
end

-- Lobby fully released: entities, cams, lights, timecycle, audio, threads (0.00 resmon from here on)
local function releaseLobby()
    Main.open, Main.mode, Main.busy = false, 'closed', false
    Plates.Stop()
    Cutscene.Stop()
    Scene.Teardown()
    Cam.Stop()
    Lights.Stop()
    Audio.Stop()
    World.Restore()
    World.PauseSync(false)
    SetNuiFocus(false, false)
end

-- Ground-safe teleport: stream, wait for collision, stand the root footHeight above the floor
function Spawn.Teleport(c)
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, c.w or 0.0)
    SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)
    NewLoadSceneStartSphere(c.x, c.y, c.z, 50.0, 0)
    local deadline = GetGameTimer() + 6000
    while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do Wait(50) end
    NewLoadSceneStop()
    ClearFocus()
    U.Collision(c.x, c.y, c.z, 6000)
    local interior = GetInteriorAtCoords(c.x, c.y, c.z)
    if interior ~= 0 then
        deadline = GetGameTimer() + 4000
        while not IsInteriorReady(interior) and GetGameTimer() < deadline do Wait(50) end
    end
    local floor = U.Floor(c.x, c.y, c.z)
    if floor and math.abs(floor - c.z) < 5.0 then
        SetEntityCoordsNoOffset(ped, c.x, c.y, floor + (Config.Scene.footHeight or 1.0), false, false, false)
    end
end

-- departure.arrival = { anim = { dict, clip, flag }, time } on the player, before the fade-in (§10)
local function arrival(def)
    if not def or not def.anim or not def.anim.dict then return end
    local a = def.anim
    if not DoesAnimDictExist(a.dict) or not pcall(lib.requestAnimDict, a.dict, 2000) then return end
    local ped = PlayerPedId()
    TaskPlayAnim(ped, a.dict, a.clip, 8.0, -4.0, def.time or -1, a.flag or 0, 0.0, false, false, false)
    CreateThread(function()
        Wait(def.time or 1500)
        if IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then StopAnimTask(ped, a.dict, a.clip, 2.0) end
        RemoveAnimDict(a.dict)
    end)
end

function Spawn.Enter(coords)
    local isNew = Spawn.isNew
    local arr = Spawn.arrival
    Spawn.arrival = nil
    U.FadeOut(300)
    U.Send('hide', {})
    releaseLobby()
    TriggerServerEvent('nzm:server:spawned')
    Spawn.Teleport(coords)
    U.ShowPlayer()
    ClientBridge.Hud(true)
    ClientBridge.PlayerSpawned(isNew)
    U.Send('close', {})
    Spawn.Clear()
    Main.Reset()
    arrival(arr)
    Wait(250)
    DoScreenFadeIn(Config.Spawn.fadeIn or 1200)
end

-- Plays the theme departure (unless new / disabled) then enters the world
local function depart(coords)
    Main.mode, Main.busy = 'cutscene', true
    SetNuiFocus(false, false)
    local theme = Scene.theme
    local cut = Config.Spawn.cutscene and not Spawn.isNew and theme and theme.departure and Actors.list[1] and Actors.list[1].kind == 'self'
    if cut then
        U.Send('cutscene', { on = true })
        if Spawn.aerial then
            -- The selector camera was far away: back to the lobby (heli or mark) and let it stream
            U.FadeOut(400)
            Scene.Refocus()
            Spawn.aerial = false
        end
        Spawn.arrival = theme.departure.arrival
        Cutscene.Run(theme)
    else
        U.Send('hide', {})
        U.FadeOut(500)
    end
    Spawn.Enter(coords)
end

-- Custom spawn resource: cutscene still plays, then the other resource takes over (selector skipped)
local function handoff(charId, isNew)
    Main.mode, Main.busy = 'cutscene', true
    SetNuiFocus(false, false)
    local theme = Scene.theme
    if Config.Spawn.cutscene and not isNew and theme and theme.departure and Actors.list[1] then
        U.Send('cutscene', { on = true })
        Cutscene.Run(theme)
    else
        U.Send('hide', {})
        U.FadeOut(400)
    end
    local airborne = Scene.flying
    releaseLobby()
    lib.callback.await('nzm:handoff', false)
    -- in-flight lobby: the player was riding the helicopter ~380 m up; put them on the ground first
    if airborne then Spawn.Teleport(Config.Creation.coords) end
    U.ShowPlayer()
    ClientBridge.Hud(true)
    U.Send('close', {})
    Spawn.Clear()
    Main.Reset()
    TriggerEvent(Config.Spawn.custom.event, charId, isNew)
end

function Spawn.Begin(charId, options, mode, isNew)
    Spawn.Clear()
    Spawn.charId, Spawn.isNew = charId, isNew == true
    if mode == 'custom' then return handoff(charId, Spawn.isNew) end

    if mode ~= 'selector' or not options or #options == 0 then
        local res = lib.callback.await('nzm:spawn', false, mode == 'first' and 'first' or 'last')
        if res and res.isNew ~= nil then Spawn.isNew = res.isNew == true end
        -- The character is already loaded server-side: never strand the player, fall back to the arrival point
        return depart((res and res.coords) or Config.Spawn.firstSpawn)
    end

    Spawn.options = options
    local list = {}
    Spawn.list = list
    for i, o in ipairs(options) do
        Spawn.byId[o.id] = o
        list[i] = { id = o.id, kind = o.kind, label = o.label, desc = o.desc, icon = o.icon }
    end
    Main.mode, Main.busy = 'spawn', false
    SetNuiFocus(true, true)
    U.Send('spawn', { options = list, selected = list[1].id })
    Spawn.Hover(list[1].id)
    if IsScreenFadedOut() then U.FadeIn(500) end
end

function Spawn.Hover(id)
    local o = Spawn.byId[id]
    if not o or not o.coords or Main.mode ~= 'spawn' or Spawn.busy then return end
    local c = o.coords
    Spawn.aerial = true
    SetFocusPosAndVel(c.x, c.y, c.z + 60.0, 0.0, 0.0, 0.0)   -- stream the preview area, not the lobby
    Cam.Go(Cam.Aerial(c), Config.Camera.aerial.time or 1500)
end

function Spawn.Confirm(id)
    if Main.mode ~= 'spawn' or Spawn.busy or not Spawn.byId[id] then return false end
    Spawn.busy = true
    local res = lib.callback.await('nzm:spawn', false, id)
    if not res or not res.coords then
        Spawn.busy = false
        return false
    end
    if res.isNew ~= nil then Spawn.isNew = res.isNew == true end
    CreateThread(function() depart(res.coords) end)
    return true
end
