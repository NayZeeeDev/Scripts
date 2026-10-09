--[[
    Raycast placement: a see-through copy of the object follows where you look.
    Scroll turns it, E places it, Backspace, Esc or right-click cancels.
    Used for tables and shoe boxes.
]]

Place = {}

local NO_ATTACK = { 24, 25, 37, 38, 44, 140, 141, 142, 257, 263, 14, 15, 16, 17, 177, 194, 199, 200, 202, 322 }
local CANCEL = { 25, 177, 194, 200, 202, 322 }   -- right-click, Backspace, Esc (read while disabled, so the pause menu stays shut)

local function ghostOf(model, pos)
    local obj = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    return obj
end

--- opts = {
---   range     = max distance from the player (default 2.8),
---   flags     = raycast flags (default 17: world and objects, so boxes can go on tables),
---   minNormal = how flat the surface must be (default 0.8),
---   heading   = start heading (default: facing the player),
---   extra     = { model = hash, offset = vector3, rot = vector3 }  -- e.g. the box lid
---   keep      = true: leave the ghost standing, solid, where it was placed, until the caller's done()
---               (the real object takes a moment to arrive from the server; this hides the wait)
--- }
--- Returns coords, heading, done (call it to remove a kept ghost), or nil if cancelled.
function Place.Ghost(model, opts)
    opts = opts or {}
    local ped = PlayerPedId()
    if not LoadModel(model) then return nil end
    local range = opts.range or 2.8
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)
    local heading = opts.heading or (GetEntityHeading(ped) + 180.0) % 360.0
    local ghost = ghostOf(model, pos)
    local extra
    if opts.extra and LoadModel(opts.extra.model) then
        local o, r = opts.extra.offset or vector3(0.0, 0.0, 0.0), opts.extra.rot or vector3(0.0, 0.0, 0.0)
        extra = ghostOf(opts.extra.model, pos)
        AttachEntityToEntity(extra, ghost, 0, o.x, o.y, o.z, r.x, r.y, r.z, false, false, false, false, 2, true)
        SetModelAsNoLongerNeeded(opts.extra.model)
    end
    UI.Hint(Config.Text.placeHint)

    local placed, valid = false, false
    while true do
        Wait(0)
        for _, c in ipairs(NO_ATTACK) do DisableControlAction(0, c, true) end
        local hit, _, coords, normal = lib.raycast.cam(opts.flags or 17, 4, range + 4.0)
        if hit then pos = coords end
        valid = hit and normal.z > (opts.minNormal or 0.8) and #(pos - GetEntityCoords(ped)) < range
        SetEntityCoords(ghost, pos.x, pos.y, pos.z, false, false, false, false)
        SetEntityHeading(ghost, heading)
        local a = valid and 200 or 90
        SetEntityAlpha(ghost, a, false)
        if extra then SetEntityAlpha(extra, a, false) end

        if IsDisabledControlPressed(0, 15) then heading = heading + 7.5 end   -- scroll up
        if IsDisabledControlPressed(0, 14) then heading = heading - 7.5 end   -- scroll down
        heading = heading % 360.0
        if IsDisabledControlJustPressed(0, 38) then                         -- E
            if valid then placed = true break end
            UI.Notify(Config.Text.cantPlace, 'error')
        end
        local cancel = false
        for _, c in ipairs(CANCEL) do if IsDisabledControlJustPressed(0, c) then cancel = true break end end
        if cancel then break end
    end

    UI.Hint(nil)
    local function done()
        if extra and DoesEntityExist(extra) then DeleteEntity(extra) end
        if DoesEntityExist(ghost) then DeleteEntity(ghost) end
        SetModelAsNoLongerNeeded(model)
    end
    -- keep Esc from opening the pause menu on the frame after cancelling
    CreateThread(function()
        local untilT = GetGameTimer() + 300
        while GetGameTimer() < untilT do DisableControlAction(0, 200, true) DisableControlAction(0, 199, true) Wait(0) end
    end)
    if not placed then done() return nil end
    -- face it straight away (no waiting for a turn)
    local me = GetEntityCoords(ped)
    SetEntityHeading(ped, GetHeadingFromVector_2d(pos.x - me.x, pos.y - me.y))
    if opts.keep then
        ResetEntityAlpha(ghost)
        if extra then ResetEntityAlpha(extra) end
        SetTimeout(5000, done)   -- never leave one behind
        return pos, heading, done
    end
    done()
    return pos, heading, function() end
end
