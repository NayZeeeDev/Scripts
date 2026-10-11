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
    for _ = 1, 12 do
        local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore, 4)
        local _, hit, coords, normal, ent = GetShapeTestResult(h)
        hit = hit == 1 or hit == true
        if not hit or not (skip and skip[ent]) then return hit, ent, coords, normal end
        from = coords + dir * 0.08   -- carry on past it
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
        local from = GetFinalRenderedCamCoord()
        local rot = GetFinalRenderedCamRot(2)
        local rx, rz = math.rad(rot.x), math.rad(rot.z)
        local c = math.abs(math.cos(rx))
        aim = { frame = f, hit = hit, ent = ent, coords = coords,
            from = from, dir = vector3(-math.sin(rz) * c, math.cos(rz) * c, math.sin(rx)) }
    end
    return aim.hit, aim.ent, aim.coords
end

--- How far along the camera's line of sight it enters an entity's box (local min/max corners), or nil
local function rayIntoBox(e, mn, mx, from, dir, maxT)
    local o = GetOffsetFromEntityGivenWorldCoords(e, from.x, from.y, from.z)
    local tip = from + dir
    local q = GetOffsetFromEntityGivenWorldCoords(e, tip.x, tip.y, tip.z)
    local d = { x = q.x - o.x, y = q.y - o.y, z = q.z - o.z }
    local lo, hi = 0.0, maxT
    for _, k in ipairs({ 'x', 'y', 'z' }) do
        local ok, dk, a, b = o[k], d[k], mn[k], mx[k]
        if math.abs(dk) < 1e-6 then
            if ok < a or ok > b then return nil end
        else
            local t1, t2 = (a - ok) / dk, (b - ok) / dk
            if t1 > t2 then t1, t2 = t2, t1 end
            if t1 > lo then lo = t1 end
            if t2 < hi then hi = t2 end
            if lo > hi then return nil end
        end
    end
    return lo
end

--- Does the third eye aim (ox_target, qb-target)? interact and the key prompt go by distance instead,
--- so there's no "the one you look at" to pick.
function Place.Aims()
    local sys = Target and Target.System and Target.System()
    return sys == 'ox_target' or sys == 'qb-target'
end

--- Of a set of props, the one you're looking at: the first one the camera's line of sight passes
--- into, worked out from where the props are and how big (sizeOf(entity, entry) -> local min, max
--- corners), so it doesn't matter whether a ray can hit them (see-through glass cases let it through).
--- If the line of sight misses them all, the one a ray hit, or whose box the hit point is right at.
--- Used so that props side by side or stacked, whose third-eye zones overlap, only ever show the
--- options of the one you look at.
function Place.Aimed(list, sizeOf, partOf)
    local hit, ent, coords = Place.Aim()
    local from, dir = aim.from, aim.dir
    local best, bestT
    for e, entry in pairs(list) do
        if DoesEntityExist(e) and #(GetEntityCoords(e) - from) < 15.0 then
            local mn, mx = sizeOf(e, entry)
            local t = rayIntoBox(e, mn, mx, from, dir, 15.0)
            if t and (not bestT or t < bestT) then best, bestT = e, t end
        end
    end
    if best then return best end
    if not hit then return nil end
    if ent and ent ~= 0 then
        if list[ent] then return ent end
        local owner = partOf and partOf(ent)
        if owner then return owner end
    end
    for e, entry in pairs(list) do
        if DoesEntityExist(e) then
            local mn, mx = sizeOf(e, entry)
            local l = GetOffsetFromEntityGivenWorldCoords(e, coords.x, coords.y, coords.z)
            local dx = math.max(mn.x - l.x, l.x - mx.x, 0.0)
            local dy = math.max(mn.y - l.y, l.y - mx.y, 0.0)
            local dz = math.max(mn.z - l.z, l.z - mx.z, 0.0)
            if dx * dx + dy * dy + dz * dz < 0.0025 then return e end
        end
    end
    return nil
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

--- Clean up after a flow that broke half way: whatever it had going (busy, camera, animation, key hint)
local function recover(what, err)
    Busy = false
    pcall(UI.Hint, nil)
    if Cam and Cam.Stop then pcall(Cam.Stop, true) end
    if Anim and Anim.Stop then pcall(Anim.Stop) end
    print(('^1[nayzeee-sneakers]^7 %s failed: %s'):format(what, tostring(err)))
end

--- Runs a placing flow with Busy set, and always clears it again, even if something in the flow errors
function Place.Run(fn, ...)
    if Busy then return end
    Busy = true
    local ok, err = pcall(fn, ...)
    Busy = false
    if not ok then recover('placing', err) end
end

--- Wraps a flow that sets Busy itself (wearing, boxes, cases, crafting, cleaning ...): if it errors
--- anywhere, Busy is cleared and the camera / animation put back, instead of Busy staying on and every
--- other flow (wearing, placing) refusing to start until a restart.
function Place.Guard(what, fn)
    return function(...)
        local res = table.pack(pcall(fn, ...))
        if not res[1] then recover(what, res[2]) return nil end
        return table.unpack(res, 2, res.n)
    end
end

--- lib.callback.await that gives up after 15 s (answers nil) instead of waiting for ever, so a server
--- that never answers can't leave a flow, and Busy, hanging
function Place.Await(name, delay, ...)
    local p, done = promise.new(), false
    lib.callback(name, delay, function(...)
        if done then return end
        done = true
        p:resolve(table.pack(...))
    end, ...)
    SetTimeout(15000, function()
        if done then return end
        done = true
        print(('^3[nayzeee-sneakers]^7 no answer from the server for %s'):format(name))
        p:resolve({ n = 0 })
    end)
    local r = Citizen.Await(p)
    return table.unpack(r, 1, r.n)
end

--- /nzsreset: frees you if anything ever leaves you stuck (busy, camera, animation, cursor)
RegisterCommand('nzsreset', function()
    Busy = false
    pcall(UI.Hint, nil)
    if Cam and Cam.Stop then pcall(Cam.Stop, true) end
    if Anim and Anim.Stop then pcall(Anim.Stop) end
    pcall(UI.CloseMenu)
    SetNuiFocus(false, false)
    print('^2[nayzeee-sneakers]^7 reset')
end, false)

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
    local skipPreview = { [ghost] = true }
    if extra then skipPreview[extra] = true end

    -- nothing may be holding the view while placing: a close-up camera left on by something earlier,
    -- or a cursor no menu let go of, would freeze the aim (and the preview with it)
    if Cam and Cam.Stop then pcall(Cam.Stop, true) end
    if not (UI.MenuOpen and UI.MenuOpen()) then SetNuiFocus(false, false) end

    --- Where the preview goes this frame: the aim, else the older aim (ignoring the player instead of the
    --- preview), else the ground just in front of the player, so it always follows you somehow
    local misses = 0
    local function spot()
        local hit, ent, coords, normal = camRay(opts.flags or 17, range + 4.0, ghost, skip)
        if not hit then hit, ent, coords, normal = camRay(opts.flags or 17, range + 4.0, ped, skipPreview) end
        if hit then misses = 0 return true, ent, coords, normal end
        misses = misses + 1
        if misses == 120 then
            local cam = GetFinalRenderedCamCoord()
            print(('^3[nayzeee-sneakers]^7 placing: the aim isn\'t finding anything (camera at %.1f %.1f %.1f, script camera %s, cursor %s). The preview follows you instead; /nzsreset if your view is stuck.')
                :format(cam.x, cam.y, cam.z, tostring(GetRenderingCam() ~= -1), tostring(IsNuiFocused and IsNuiFocused() or false)))
        end
        local front = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)
        local found, z = GetGroundZFor_3dCoord(front.x, front.y, front.z + 1.0, false)
        if found then return true, 0, vector3(front.x, front.y, z), vector3(0.0, 0.0, 1.0) end
        return false
    end

    local placed, valid = false, false
    -- if anything in the loop errors, the ghost still goes and the player isn't left stuck
    local ok, err = pcall(function()
        while true do
            Wait(0)
            for _, c in ipairs(NO_ATTACK) do DisableControlAction(0, c, true) end
            local hit, ent, coords, normal = spot()
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
