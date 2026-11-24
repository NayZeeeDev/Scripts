if not NAYZEEE_LOCK_OK then return end

--[[
    New character (contract §6.1 step 9).
      Create.Start(slot)    silhouette on the main mark + body camera, then NUI `create`
      Create.Gender(g)      opaque default ped of that gender
      Create.Cancel()       back to the previously selected character
      Create.Submit(form)   nzm:create -> appearance editor in the world -> spawn (no departure cutscene)
]]

Create = { slot = nil, gender = 'm', prev = nil }

local function genders() return Config.Registration.genders or { 'm', 'f' } end

function Create.Start(slot)
    slot = tonumber(slot)
    if not slot or not Main.open or Main.busy then return { ok = false } end
    if Main.mode ~= 'lobby' and Main.mode ~= 'create' then return { ok = false } end
    if Main.bySlot[slot] then return { ok = false, msg = NZ.T('t_slot_taken') } end
    if slot > Main.TotalSlots() then return { ok = false, msg = NZ.T('t_slot_locked') } end

    if Main.mode == 'lobby' then Create.prev = Main.selected end
    Main.selected, Main.mode, Main.busy = slot, 'create', true
    Create.slot, Create.gender = slot, genders()[1] or 'm'
    U.Send('select', { slot = slot })
    CreateThread(function()
        Main.squad = nil
        Actors.Ghost(Create.gender, false)
        U.Send('squad', Main.SquadNui(nil))
        Cam.Mode('body', Config.Camera.transition)
        Main.busy = false
        if Main.mode == 'create' and Create.slot == slot then U.Send('create', { slot = slot }) end
    end)
    return { ok = true }
end

function Create.Gender(g)
    if Main.mode ~= 'create' then return end
    local ok = false
    for _, v in ipairs(genders()) do if v == g then ok = true end end
    if not ok then return end
    Create.gender = g
    Actors.Ghost(g, true)
end

function Create.Cancel()
    if Main.mode ~= 'create' then return end
    local prev = Create.prev
    Create.slot, Create.prev = nil, nil
    Main.mode = 'lobby'
    if prev and Main.bySlot[prev] then
        Main.busy = true
        U.Send('select', { slot = prev })
        Main.Present(prev, false)
        Main.busy = false
    else
        Actors.Ghost(Create.gender, false)
        Cam.Mode(Main.camera, Config.Camera.transition)
    end
    U.Send('lobby', Main.Payload())
    U.Send('squad', Main.SquadNui(Main.squad))
end

-- Returns { ok, errors, msg } to the NUI; on success the rest of the flow runs in a thread
function Create.Submit(form)
    if Main.mode ~= 'create' or Main.busy or not Create.slot then return { ok = false, msg = NZ.T('t_error') } end
    form = type(form) == 'table' and form or {}
    form.gender = form.gender or Create.gender
    Main.busy = true
    local res = lib.callback.await('nzm:create', false, Create.slot, form)
    if not res or not res.ok then
        Main.busy = false
        return { ok = false, errors = res and res.errors, msg = res and res.msg or (not res and NZ.T('t_error')) or nil }
    end
    CreateThread(function() Create.Continue(res, form.gender) end)
    return { ok = true, msg = res.msg }
end

-- Appearance editor in the world, then spawn (selector if the server says so, else the first spawn)
function Create.Continue(res, gender)
    Main.mode = 'busy'
    gender = res.gender or gender or 'm'
    SetNuiFocus(false, false)
    U.Send('hide', {})
    U.FadeOut(500)
    Scene.Teardown()
    Lights.Stop()
    Audio.Stop()

    Appearance.ApplyPlayer(nil, nil, gender)
    Spawn.Teleport(Config.Creation.coords)
    U.ShowPlayer()
    Wait(200)
    U.FadeIn(600)

    local p = promise.new()
    Appearance.OpenEditor(true, gender, function() p:resolve(true) end)
    Citizen.Await(p)

    U.FadeOut(400)
    U.HidePlayer()
    local spawn, mode = res.spawn, res.mode
    if not mode then
        local r = lib.callback.await('nzm:play', false, res.charId)
        if r and r.ok then spawn, mode = r.spawn, r.mode end
    end
    Create.slot, Create.prev = nil, nil
    Spawn.Begin(res.charId, spawn, mode or 'first', true)
end
