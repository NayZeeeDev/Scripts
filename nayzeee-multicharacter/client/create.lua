if not NAYZEEE_LOCK_OK then return end

Create = { slot = nil, gender = 'm', result = nil }

function Create.Start(slot)
    slot = tonumber(slot)
    if not slot or Main.bySlot[slot] or slot > Main.total or Main.mode == 'busy' then return false end
    Main.Select(slot, false)
    Main.mode = 'create'
    Create.slot, Create.gender = slot, Config.Registration.genders[1] or 'm'
    U.Send('plates', { items = {} })
    local ped, pos = Scene.CreatorPed(slot, Create.gender), select(2, Scene.PedOf(slot))
    if ped then CreateThread(function() Cam.Go(Cam.Focus(ped, pos and pos.camera), Config.Scene.focusTime) end) end
    return true
end

function Create.Gender(g)
    if Main.mode ~= 'create' or (g ~= 'm' and g ~= 'f') or g == Create.gender then return end
    Create.gender = g
    Scene.CreatorPed(Create.slot, g)
end

function Create.Cancel()
    if Main.mode ~= 'create' then return end
    local slot = Create.slot
    Create.slot = nil
    Main.mode = 'overview'
    Scene.page = 0
    Main.Select(slot, false)
    Main.Overview()
end

-- Returns { ok, errors } to the NUI. On success the rest of the flow runs in its own thread.
function Create.Submit(form)
    if Main.mode ~= 'create' then return { ok = false } end
    form.gender = Create.gender
    Main.mode = 'busy'
    local res = lib.callback.await('nzm:create', false, Create.slot, form)
    if not res or not res.ok then
        Main.mode = 'create'
        return { ok = false, errors = res and res.errors, msg = res and res.msg }
    end
    Create.result = res
    CreateThread(Create.Continue)
    return { ok = true }
end

-- New character: appearance editor -> starter shop -> spawn
function Create.Continue()
    local res = Create.result
    SetNuiFocus(false, false)
    U.Send('hide', {})
    U.FadeOut(500)
    Cam.Stop(false)
    Scene.Teardown()

    Appearance.ApplyPlayer(nil, nil, res.gender)
    local c = Config.Creation.appearanceCoords
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, c.w or 0.0)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(50) end
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    U.FadeIn(600)

    if (Config.Creation.countdown or 0) > 0 then
        U.Send('countdown', { seconds = Config.Creation.countdown })
        Wait(Config.Creation.countdown * 1000)
    end

    local p = promise.new()
    Appearance.OpenEditor(true, res.gender, function() p:resolve(true) end)
    Citizen.Await(p)

    if res.shop then
        FreezeEntityPosition(PlayerPedId(), true)
        Main.mode = 'shop'
        SetNuiFocus(true, true)
        U.Send('shop', {})
        return  -- continues from the shop callbacks
    end
    Create.ToSpawn()
end

function Create.ToSpawn()
    local res = Create.result
    Create.result = nil
    FreezeEntityPosition(PlayerPedId(), true)
    Spawn.Begin(res.charId, res.spawn, res.mode, true)
end

function Create.Shop(cart)
    if Main.mode ~= 'shop' then return { ok = false } end
    local r = lib.callback.await('nzm:shop', false, cart)
    if not r or not r.ok then return { ok = false, msg = r and r.msg or NZ.T('t_error') } end
    Main.mode = 'busy'
    CreateThread(Create.ToSpawn)
    return { ok = true }
end

function Create.ShopSkip()
    if Main.mode ~= 'shop' then return false end
    lib.callback.await('nzm:shopSkip', false)
    Main.mode = 'busy'
    CreateThread(Create.ToSpawn)
    return true
end
