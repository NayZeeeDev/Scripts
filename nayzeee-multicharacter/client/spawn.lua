if not NAYZEEE_LOCK_OK then return end

Spawn = { options = nil, byId = {}, charId = nil, isNew = false }

function Spawn.Clear()
    Spawn.options, Spawn.byId, Spawn.charId = nil, {}, nil
end

local function groundAt(c)
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, c.w or 0.0)
    NewLoadSceneStartSphere(c.x, c.y, c.z, 40.0, 0)
    local deadline = GetGameTimer() + 6000
    while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do Wait(50) end
    NewLoadSceneStop()
    deadline = GetGameTimer() + 6000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(c.x, c.y, c.z)
        Wait(50)
    end
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 2.0, false)
    if found and math.abs(z - c.z) < 5.0 then
        SetEntityCoordsNoOffset(ped, c.x, c.y, z + (Config.Scene.footHeight or 1.0), false, false, false)
    end
end

local function release()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    ResetEntityAlpha(ped)
    SetPedAoBlobRendering(ped, true)
    NetworkSetEntityInvisibleToNetwork(ped, false)
end

local function finish(isNew)
    Main.Close()
    World.Restore()
    World.PauseSync(false)
    ClientBridge.Hud(true)
    ClientBridge.PlayerSpawned(isNew)
end

-- Put the player in the world at server-approved coords
function Spawn.Execute(coords, isNew)
    SetNuiFocus(false, false)
    U.Send('hide', {})
    local useSwitch = Config.Spawn.transition == 'switch' and not Settings.Get('fps')

    U.FadeOut(450)
    Cam.Stop(false)
    Scene.Teardown()
    groundAt(coords)
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, true)

    if useSwitch then
        SwitchOutPlayer(ped, 0, 1)
        local deadline = GetGameTimer() + 8000
        while GetPlayerSwitchState() ~= 5 and GetGameTimer() < deadline do Wait(0) end
        U.FadeIn(500)
        Wait(400)
        release()
        SwitchInPlayer(PlayerPedId())
        deadline = GetGameTimer() + 12000
        while IsPlayerSwitchInProgress() and GetGameTimer() < deadline do Wait(0) end
    else
        release()
        Wait(300)
        U.FadeIn(700)
    end
    finish(isNew)
end

-- After a character is loaded: selector, direct spawn or hand-off
function Spawn.Begin(charId, options, mode, isNew)
    Spawn.charId, Spawn.isNew = charId, isNew
    if mode == 'custom' then
        U.FadeOut(400)
        SetNuiFocus(false, false)
        Cam.Stop(false)
        Scene.Teardown()
        lib.callback.await('nzm:handoff', false)
        release()
        Main.Close()
        World.Restore()
        World.PauseSync(false)
        TriggerEvent(Config.Spawn.custom.event, charId, isNew)
        return
    end

    if not options or #options == 0 then
        local res = lib.callback.await('nzm:spawn', false, mode == 'first' and 'first' or nil)
        if not res then return U.Send('toast', { type = 'error', text = NZ.T('t_error') }) end
        return Spawn.Execute(res.coords, isNew)
    end

    Spawn.options, Spawn.byId = options, {}
    local list = {}
    for i, o in ipairs(options) do
        Spawn.byId[o.id] = o
        list[i] = { id = o.id, kind = o.kind, label = o.label, desc = o.desc, icon = o.icon }
    end

    -- Lineup is no longer needed; free it while the player browses spawns
    U.FadeOut(300)
    Scene.Teardown()
    SetNuiFocus(true, true)
    U.Send('spawn', { options = list, selected = list[1].id })
    Main.mode = 'spawn'
    Spawn.Hover(list[1].id, 0)
    U.FadeIn(500)
end

function Spawn.Hover(id, ms)
    local o = Spawn.byId[id]
    if not o then return end
    local c = o.coords
    SetFocusPosAndVel(c.x, c.y, c.z + 60.0, 0.0, 0.0, 0.0)
    Cam.Go(Cam.Aerial(c), ms or Config.Spawn.preview.time)
end

function Spawn.Confirm(id)
    if not Spawn.byId[id] then return false end
    local res = lib.callback.await('nzm:spawn', false, id)
    if not res then return false end
    ClearFocus()
    CreateThread(function() Spawn.Execute(res.coords, Spawn.isNew) end)
    return true
end
