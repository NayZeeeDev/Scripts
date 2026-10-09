--[[
    Raycast placement: a see-through copy of the object follows where you look.
    Scroll or Q / E turns it, LMB (or Enter) places it, RMB (or Backspace) cancels.
    Used for tables and shoe boxes.
]]

Place = {}

local NO_ATTACK = { 24, 25, 37, 38, 44, 140, 141, 142, 257, 263, 14, 15, 16, 17, 199, 200 }

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
--- }
--- Returns coords, heading, or nil if cancelled.
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
        if IsDisabledControlPressed(0, 44) then heading = heading + 1.5 end   -- Q
        if IsDisabledControlPressed(0, 38) then heading = heading - 1.5 end   -- E
        heading = heading % 360.0
        if IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 191) then
            if valid then placed = true break end
            UI.Notify(Config.Text.cantPlace, 'error')
        end
        if IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 177) then break end
    end

    if extra then DeleteEntity(extra) end
    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(model)
    UI.Hint(nil)
    if not placed then return nil end
    TaskTurnPedToFaceCoord(ped, pos.x, pos.y, pos.z, 600)
    Wait(600)
    return pos, heading
end
