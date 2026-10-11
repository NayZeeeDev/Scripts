--[[
    Raycast placement: a see-through copy of the object follows where you look.
    Scroll turns it, E places it, Backspace, Esc or right-click cancels.
    Used for tables and shoe boxes.
]]

Place = {}

local NO_ATTACK = { 24, 25, 37, 38, 44, 140, 141, 142, 257, 263, 14, 15, 16, 17, 177, 194, 199, 200, 202, 322 }
local CANCEL = { 25, 177, 194, 200, 202, 322 }   -- right-click, Backspace, Esc (read while disabled, so the pause menu stays shut)

--- Where the camera looks, answered this same frame (ox_lib's raycast waits a frame for its result,
--- which made the preview lag and could miss a quick E or Backspace)
--- skip = { [entity] = true }: things the ray goes straight through (the player, the see-through preview
--- itself, which would otherwise catch the aim and climb on top of itself)
local function camRay(flags, dist, ignore, skip)
    local from = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(rx))
    local dir = vector3(-math.sin(rz) * c, math.cos(rz) * c, math.sin(rx))
    local to = from + dir * dist
    for _ = 1, 4 do
        local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore, 4)
        local _, hit, coords, normal, ent = GetShapeTestResult(h)
        hit = hit == 1 or hit == true
        if not hit or not (skip and skip[ent]) then return hit, ent, coords, normal end
        from = coords + dir * 0.02   -- carry on past it
    end
    return false
end

--- What the player is aiming at right now: hit, entity, coords. Worked out once a frame, however many
--- third-eye options ask.
local aim = { frame = -1 }
function Place.Aim()
    local f = GetFrameCount()
    if aim.frame ~= f then
        local hit, ent, coords = camRay(17, 10.0, PlayerPedId())
        aim = { frame = f, hit = hit, ent = ent, coords = coords }
    end
    return aim.hit, aim.ent, aim.coords
end

--- Does the third eye aim (ox_target, qb-target)? interact and the key prompt go by distance instead,
--- so there's no "the one you look at" to pick.
function Place.Aims()
    local sys = Target and Target.System and Target.System()
    return sys == 'ox_target' or sys == 'qb-target'
end

--- Of a set of props, the one the aim is on: the one it hit, or the one whose box the hit point is
--- in or nearest to. list = { [entity] = entry }, sizeOf(entity, entry) -> local min, max corners,
--- partOf(entity) -> the prop a hit part (lid, door, shoe) belongs to. Used so that props side by side
--- or stacked, whose third-eye zones overlap, only ever show the options of the one you look at.
function Place.Aimed(list, sizeOf, partOf)
    local hit, ent, coords = Place.Aim()
    if not hit then return nil end
    if ent and ent ~= 0 then
        if list[ent] then return ent end
        local owner = partOf and partOf(ent)
        if owner then return owner end
    end
    local best, bestD
    for e, entry in pairs(list) do
        if DoesEntityExist(e) then
            local mn, mx = sizeOf(e, entry)
            local l = GetOffsetFromEntityGivenWorldCoords(e, coords.x, coords.y, coords.z)
            local dx = math.max(mn.x - l.x, l.x - mx.x, 0.0)
            local dy = math.max(mn.y - l.y, l.y - mx.y, 0.0)
            local dz = math.max(mn.z - l.z, l.z - mx.z, 0.0)
            local d = dx * dx + dy * dy + dz * dz
            if not bestD or d < bestD then best, bestD = e, d end
        end
    end
    return best
end

--- The model of whatever a ray hit, or nil (the ground and buildings aren't entities, and asking
--- for their model crashes the native)
function Place.ModelOf(ent)
    if not ent or ent == 0 then return nil end
    local ok, exists = pcall(DoesEntityExist, ent)
    if not ok or not exists then return nil end
    local okT, kind = pcall(GetEntityType, ent)
    if not okT or kind ~= 3 then return nil end   -- objects only
    local okM, model = pcall(GetEntityModel, ent)
    return okM and model or nil
end

local function ghostOf(model, pos)
    local obj = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    return obj
end

--- Runs a placing flow with Busy set, and always clears it again, even if something in the flow errors
function Place.Run(fn, ...)
    if Busy then return end
    Busy = true
    local ok, err = pcall(fn, ...)
    Busy = false
    if not ok then
        UI.Hint(nil)
        print(('^1[nayzeee-sneakers]^7 placing failed: %s'):format(err))
    end
end

--- opts = {
---   range     = max distance from the player (default 2.8),
---   flags     = raycast flags (default 17: world and objects, so boxes can go on tables),
---   minNormal = how flat the surface must be (default 0.8),
---   heading   = start heading (default: facing the player),
---   extra     = { model = hash, offset = vector3, rot = vector3 }  -- e.g. the box lid
---   snap      = function(entityHit, coords, normal) -> coords, heading | nil: line the ghost up with
---               something it's aimed at (display cases stack and sit side by side this way)
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

    local function done()
        if extra and DoesEntityExist(extra) then DeleteEntity(extra) end
        if DoesEntityExist(ghost) then DeleteEntity(ghost) end
        SetModelAsNoLongerNeeded(model)
    end

    local skip = { [ped] = true }
    if extra then skip[extra] = true end

    local placed, valid = false, false
    -- if anything in the loop errors, the ghost still goes and the player isn't left stuck
    local ok, err = pcall(function()
        while true do
            Wait(0)
            for _, c in ipairs(NO_ATTACK) do DisableControlAction(0, c, true) end
            local hit, ent, coords, normal = camRay(opts.flags or 17, range + 4.0, ghost, skip)
            if hit then pos = coords end
            local snapped = false
            if hit and opts.snap then
                local ok, sp, sh = pcall(opts.snap, ent, coords, normal)
                if ok and sp then pos, heading, snapped = sp, sh, true end
            end
            valid = hit and (snapped or normal.z > (opts.minNormal or 0.8)) and #(pos - GetEntityCoords(ped)) < range
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
    end)

    UI.Hint(nil)
    if not ok then done() error(err, 0) end
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
