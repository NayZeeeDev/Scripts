--[[
    NAYZEEE AMBULANCE - Site survey (placement) mode (client) for the Department Console

    NZA.HospitalC.Place(opts) → coords { x, y, z, w }, nil, extra | nil, reason   (blocking, call from a thread)
      opts = { type, label, icon, kind = 'prop'|'marker'|'npc'|'bed'|'car'|'heli', prop (model), model (vehicle),
               ghostModel (npc), radius (marker: the third-eye sphere), lie (bed: current data.lie),
               dept, deptLabel, heading, from = coords (re-place: start there),
               parts = { { model, pos = vector3 (type space: +X right, +Y forward), h }, ... } }
      extra = { lie = { exact = true, pose } } for beds (saved in the point's data)
      parts (a type def's `parts`, e.g. the angio suite's monitor / injector / button) are shown
      as extra ghosts around the main one, rotated with it and standing on the same floor.

    Aim with the camera: a ray from the screen centre finds the floor / furniture under it.
      prop types    translucent ghost of the type's prop, bottom resting on the surface, floor
                    corner brackets around its footprint
      npc types     a ghost of the NPC that will stand there (receptionist, pharmacist, supply officer)
      marker types  the third-eye sphere the position will have, over a small floor ring
      bed types     two steps: aim at the bed (it lights up) and press E, then a lying patient shows on
                    it: turn it, slide it along the bed, lift it, R changes how they lie, G turns them
                    round, Backspace picks another bed. E on the floor instead of a bed sets a free spot.
      vehicle types ghost car / helicopter (first garage vehicle of that kind) + brackets
      every kind    a facing arrow
    Controls (game input stays free to walk / look):
      E confirm · Q / X / Backspace / ESC cancel · ← → (hold) or mouse wheel rotate
      Shift faster · Alt fine · Page Up / Page Down raise / lower · G snap heading
    The ghost never collides. Too far (Config.Hospital.builder.maxDistance) or no surface
    under the crosshair = invalid, E is refused.

    NUI app 'builder' (opened without focus): actions open, state, flash
      state carries keys = { fast, fine, turn, wheel, lift, slide } so the HUD can light the held keys;
      beds also send phase = 'pick'|'pose' and pose = label
]]

if not NAYZEEE_LOCK_OK then return end

NZA.HospitalC = NZA.HospitalC or {}
local C = NZA.HospitalC

local APP = 'builder'
local active = nil

local CTRL = {
    confirm = 38, cancelQ = 44, cancelX = 73, back = 177, esc = 200,
    left = 174, right = 175, up = 10, down = 11, wheelUp = 15, wheelDown = 14, snap = 47,
    shift = 21, alt = 19, slideF = 172, slideB = 173, pose = 45,
}
local DISABLE = { 24, 25, 37, 38, 44, 45, 47, 73, 10, 11, 14, 15, 16, 17, 140, 141, 142, 143, 172, 173, 174, 175, 177, 199, 200, 257, 263, 264, 81, 82, 99, 100 }

local function bcfg()
    return (Config.Hospital and Config.Hospital.builder) or {}
end

local function L(key, ...) return NZA.L('hospital.' .. key, ...) end

local function setOutline(ent, valid)
    if not ent or ent == 0 or not SetEntityDrawOutline then return end
    pcall(SetEntityDrawOutline, ent, true)
    if SetEntityDrawOutlineColor then
        local c = valid and (bcfg().markerColour or { 8, 175, 162 }) or (bcfg().badColour or { 229, 72, 77 })
        pcall(SetEntityDrawOutlineColor, c[1], c[2], c[3], 255)
    end
end

local function makeVehicleGhost(model, at, heading)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return 0 end
    local ok = pcall(lib.requestModel, hash, 6000)
    if not ok or not HasModelLoaded(hash) then return 0 end
    local veh = CreateVehicle(hash, at.x, at.y, at.z, heading, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 then return 0 end
    SetEntityAsMissionEntity(veh, true, true)
    SetEntityCollision(veh, false, false)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    SetEntityAlpha(veh, bcfg().ghostAlpha or 165, false)
    SetVehicleLights(veh, 1)
    return veh
end

local function makePropGhost(model, at, heading)
    local ent = NZA.Props.Spawn(model, at, {
        group = 'nza:builder', heading = heading, freeze = true, collision = false,
        alpha = bcfg().ghostAlpha or 165, invincible = true,
    })
    return ent or 0
end

local function makePedGhost(model, at, heading)
    local hash = type(model) == 'number' and model or joaat(model or '')
    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then return 0 end
    local ok = pcall(lib.requestModel, hash, 6000)
    if not ok or not HasModelLoaded(hash) then return 0 end
    local ped = CreatePed(4, hash, at.x, at.y, at.z, heading, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return 0 end
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetEntityAlpha(ped, bcfg().ghostAlpha or 165, false)
    return ped
end

local function deleteGhost(ent)
    if not ent or ent == 0 then return end
    if IsEntityAPed(ent) then
        if DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
    elseif IsEntityAVehicle(ent) then
        if DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
    else
        NZA.Props.Delete(ent)
    end
end

local function baseOffset(ent)
    if not ent or ent == 0 then return 0.0 end
    local mn = GetModelDimensions(GetEntityModel(ent))
    return -(mn and mn.z or 0.0)
end

-- half extents + centre offset of the footprint in the entity's own axes (x = right, y = forward)
local function footprintOf(ent, kind)
    if ent and ent ~= 0 then
        local mn, mx = GetModelDimensions(GetEntityModel(ent))
        if mn and mx then
            return {
                hx = math.max(0.35, (mx.x - mn.x) * 0.5), hy = math.max(0.35, (mx.y - mn.y) * 0.5),
                cx = (mx.x + mn.x) * 0.5, cy = (mx.y + mn.y) * 0.5,
            }
        end
    end
    local r = (kind == 'marker' or kind == 'npc') and 0.4 or 1.0
    return { hx = r, hy = r, cx = 0.0, cy = 0.0 }
end

-- type-space offset (x = right, y = forward) → world offset for a heading (GTA: 0 = north, CCW)
local function rotateOffset(v, heading)
    local h = math.rad(heading or 0.0)
    local c, s = math.cos(h), math.sin(h)
    return vector3(v.x * c - v.y * s, v.x * s + v.y * c, 0.0)
end

-- extra ghosts of a type's parts (angio suite equipment), placed next to the main ghost
local function makePartGhosts(parts, at, heading)
    local out = {}
    if type(parts) ~= 'table' then return out end
    for _, part in ipairs(parts) do
        local model = type(part) == 'table' and part.model
        local pos = type(part) == 'table' and part.pos
        if model and pos and tonumber(pos.x) and tonumber(pos.y) then
            local ent = makePropGhost(model, at, heading + (tonumber(part.h) or 0.0))
            if ent ~= 0 then
                out[#out + 1] = {
                    ent = ent, h = tonumber(part.h) or 0.0, z = tonumber(pos.z) or 0.0, base = baseOffset(ent),
                    off = vector3(tonumber(pos.x) + 0.0, tonumber(pos.y) + 0.0, 0.0),
                }
            end
        end
    end
    return out
end

local function snapHeading(h, step)
    if not step or step <= 0 then return h end
    return (math.floor(h / step + 0.5) * step) % 360.0
end

local function line(a, b, r, g, bl, al)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, r, g, bl, al)
end

local function draw(state, colour)
    local p = state.pos
    if not p then return end
    local r, g, b = colour[1], colour[2], colour[3]
    local base = state.surface
    local h = math.rad(state.shownHeading)
    local fwd = vector3(-math.sin(h), math.cos(h), 0.0)
    local right = vector3(math.cos(h), math.sin(h), 0.0)
    local fp = state.foot
    local lift = vector3(0.0, 0.0, 0.035)
    local centre = base + right * fp.cx + fwd * fp.cy + lift

    -- floor corner brackets around the footprint (props and vehicles only)
    if state.kind == 'prop' or state.kind == 'car' or state.kind == 'heli' then
        local arm = math.min(0.45, math.min(fp.hx, fp.hy) * 0.6)
        for sx = -1, 1, 2 do
            for sy = -1, 1, 2 do
                local c = centre + right * (fp.hx * sx) + fwd * (fp.hy * sy)
                line(c, c - right * (arm * sx), r, g, b, 235)
                line(c, c - fwd * (arm * sy), r, g, b, 235)
            end
        end
    end

    -- facing arrow from the centre past the front edge
    local tip = centre + fwd * (fp.hy + 0.55)
    line(centre + fwd * (fp.hy * 0.35), tip, r, g, b, 235)
    line(tip, tip - fwd * 0.2 + right * 0.13, r, g, b, 235)
    line(tip, tip - fwd * 0.2 - right * 0.13, r, g, b, 235)

    -- centre cross on the floor
    line(centre - right * 0.12, centre + right * 0.12, r, g, b, 170)
    line(centre - fwd * 0.12, centre + fwd * 0.12, r, g, b, 170)

    if state.kind == 'marker' then
        -- the third-eye sphere this position gets, centred where the target zone will be
        local rad = state.radius or 1.2
        DrawMarker(28, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, rad, rad, rad, r, g, b, 70, false, false, 2, false, nil, nil, false)
        DrawMarker(25, p.x, p.y, base.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, rad * 2.0, rad * 2.0, 1.0, r, g, b, 120, false, false, 2, false, nil, nil, false)
    elseif state.kind == 'npc' then
        DrawMarker(25, p.x, p.y, base.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.9, 1.0, r, g, b, 140, false, false, 2, false, nil, nil, false)
    end
end

local function sendState(state, force)
    local now = GetGameTimer()
    local k = state.keys or {}
    local snapshot = ('%.1f|%.2f|%.1f|%s|%s|%s|%s%s%s%s%s%s|%s|%s'):format(state.shownHeading, state.height, state.dist or -1, tostring(state.valid), tostring(state.reason), tostring(state.snap),
        k.fast and 1 or 0, k.fine and 1 or 0, k.turn and 1 or 0, k.wheel and 1 or 0, k.lift and 1 or 0, k.slide and 1 or 0, tostring(state.phase), tostring(state.poseLabel) .. tostring(state.target))
    if not force and (snapshot == state.lastSent or now - (state.lastAt or 0) < 90) then return end
    state.lastSent, state.lastAt = snapshot, now
    NZA.UI.Send(APP, 'state', {
        heading = state.shownHeading, height = state.height, dist = state.dist, max = state.max,
        valid = state.valid, reason = state.reason, snap = state.snap, snapStep = bcfg().snapAngle or 15.0,
        coords = state.pos and { x = state.pos.x, y = state.pos.y, z = state.pos.z } or nil,
        keys = k, phase = state.phase, pose = state.poseLabel, target = state.target,
    })
end

-- close the HUD and swallow the key that ended placement so it doesn't open the pause menu / fire anything
local function finish()
    NZA.UI.Close(APP)
    active = nil
    local t = GetGameTimer()
    while GetGameTimer() - t < 250 do
        DisableControlAction(0, 200, true)
        DisableControlAction(0, 38, true)
        DisableControlAction(0, 44, true)
        DisableControlAction(0, 177, true)
        Wait(0)
    end
end

function C.Place(opts)
    if active then return nil, 'busy' end
    opts = opts or {}
    local bc = bcfg()
    local ped = PlayerPedId()
    local kind = opts.kind or 'marker'
    local start = opts.from and vector3(opts.from.x, opts.from.y, opts.from.z) or GetEntityCoords(ped)
    local state = {
        kind = kind, heading = tonumber(opts.heading) or (opts.from and tonumber(opts.from.w)) or GetEntityHeading(ped),
        height = 0.0, snap = false, valid = false, max = bc.maxDistance or 25.0,
    }
    state.shownHeading = state.heading

    if kind == 'bed' then return C.PlaceBed(opts) end
    state.radius = tonumber(opts.radius) or 1.2

    local ghost = 0
    if kind == 'npc' and opts.ghostModel then
        ghost = makePedGhost(opts.ghostModel, start, state.heading)
        if ghost == 0 then kind = 'marker' end
    elseif kind == 'prop' and opts.prop then
        ghost = makePropGhost(opts.prop, start, state.heading)
        if ghost == 0 then kind = 'marker' end
    elseif (kind == 'car' or kind == 'heli') and opts.model then
        ghost = makeVehicleGhost(opts.model, start, state.heading)
        if ghost == 0 then kind = 'marker' end
    elseif kind ~= 'marker' then
        kind = 'marker'
    end
    state.kind = kind
    local zBase = baseOffset(ghost)
    state.foot = footprintOf(ghost, kind)
    state.keys = {}
    local parts = (kind == 'prop' or kind == 'marker' or kind == 'npc') and makePartGhosts(opts.parts, start, state.heading) or {}
    active = { ghost = ghost, parts = parts }

    NZA.UI.Open(APP, {
        type = opts.type, label = opts.label, icon = opts.icon, kind = kind, dept = opts.deptLabel,
        replace = opts.from ~= nil, locale = NZA.LocaleTable('hospital'),
        snapStep = bc.snapAngle or 15.0, max = state.max,
    }, { focus = false })

    local result, reason = nil, 'cancel'
    local fast, fine = bc.fastFactor or 3.0, bc.fineFactor or 0.2
    while true do
        local dt = GetFrameTime()
        for i = 1, #DISABLE do DisableControlAction(0, DISABLE[i], true) end

        ped = PlayerPedId()
        if NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then reason = 'down'; break end
        if IsPedInAnyVehicle(ped, false) then reason = 'vehicle'; break end

        -- input
        local fastHeld, fineHeld = IsControlPressed(0, CTRL.shift), IsControlPressed(0, CTRL.alt)
        local mult = fastHeld and fast or (fineHeld and fine or 1.0)
        local rot = 0.0
        local turning = IsDisabledControlPressed(0, CTRL.left) or IsDisabledControlPressed(0, CTRL.right)
        local wheeled = IsDisabledControlJustPressed(0, CTRL.wheelUp) or IsDisabledControlJustPressed(0, CTRL.wheelDown)
        if IsDisabledControlPressed(0, CTRL.left) then rot = rot + (bc.rotateSpeed or 90.0) * dt * mult end
        if IsDisabledControlPressed(0, CTRL.right) then rot = rot - (bc.rotateSpeed or 90.0) * dt * mult end
        if IsDisabledControlJustPressed(0, CTRL.wheelUp) then rot = rot + (bc.scrollStep or 7.5) * mult end
        if IsDisabledControlJustPressed(0, CTRL.wheelDown) then rot = rot - (bc.scrollStep or 7.5) * mult end
        if wheeled then state.wheelUntil = GetGameTimer() + 220 end
        state.keys = {
            fast = fastHeld, fine = fineHeld and not fastHeld, turn = turning,
            wheel = (state.wheelUntil or 0) > GetGameTimer(),
            lift = IsDisabledControlPressed(0, CTRL.up) or IsDisabledControlPressed(0, CTRL.down),
        }
        state.heading = (state.heading + rot) % 360.0
        if IsDisabledControlJustPressed(0, CTRL.snap) then state.snap = not state.snap end
        state.shownHeading = state.snap and snapHeading(state.heading, bc.snapAngle or 15.0) or state.heading
        local maxH = bc.maxHeight or 3.0
        if IsDisabledControlPressed(0, CTRL.up) then state.height = math.min(maxH, state.height + (bc.heightSpeed or 0.5) * dt * mult) end
        if IsDisabledControlPressed(0, CTRL.down) then state.height = math.max(-maxH, state.height - (bc.heightSpeed or 0.5) * dt * mult) end

        -- aim
        local hit = NZA.Cam.Raycast({ x = 0.5, y = 0.5, dist = state.max + 25.0, flags = 1 + 16, ignore = ped })
        local surface
        if hit.hit and hit.coords then
            surface = hit.coords
            state.reason = nil
        else
            surface = hit.origin + hit.dir * math.min(state.max, 8.0)
            state.reason = 'nosurface'
        end
        state.surface = surface
        if kind == 'marker' then
            state.pos = surface + vector3(0.0, 0.0, state.height)
        else
            state.pos = surface + vector3(0.0, 0.0, state.height + zBase)
        end
        state.dist = #(GetEntityCoords(ped) - surface)
        if not state.reason and state.dist > state.max then state.reason = 'far' end
        state.valid = state.reason == nil

        -- ghost + markers
        if ghost ~= 0 and DoesEntityExist(ghost) then
            SetEntityCoordsNoOffset(ghost, state.pos.x, state.pos.y, state.pos.z, false, false, false)
            SetEntityHeading(ghost, state.shownHeading)
            SetEntityAlpha(ghost, state.valid and (bc.ghostAlpha or 165) or 95, false)
            setOutline(ghost, state.valid)
        end
        for _, part in ipairs(parts) do
            if DoesEntityExist(part.ent) then
                local at = state.pos + rotateOffset(part.off, state.shownHeading)
                SetEntityCoordsNoOffset(part.ent, at.x, at.y, state.surface.z + state.height + part.base + part.z, false, false, false)
                SetEntityHeading(part.ent, (state.shownHeading + part.h) % 360.0)
                SetEntityAlpha(part.ent, state.valid and (bc.ghostAlpha or 165) or 95, false)
                setOutline(part.ent, state.valid)
            end
        end
        draw(state, state.valid and (bc.markerColour or { 8, 175, 162 }) or (bc.badColour or { 229, 72, 77 }))
        sendState(state)

        -- confirm / cancel
        if IsDisabledControlJustPressed(0, CTRL.confirm) then
            if state.valid then
                -- vehicles and NPCs stand on the floor: their points keep the floor height
                local saveZ = (kind == 'car' or kind == 'heli' or kind == 'npc') and (surface.z + state.height) or state.pos.z
                result = { x = state.pos.x, y = state.pos.y, z = saveZ, w = state.shownHeading }
                reason = nil
                break
            end
            NZA.UI.Send(APP, 'flash', { reason = state.reason })
            PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
        if IsDisabledControlJustPressed(0, CTRL.cancelQ) or IsDisabledControlJustPressed(0, CTRL.cancelX)
            or IsDisabledControlJustPressed(0, CTRL.back) or IsDisabledControlJustPressed(0, CTRL.esc) then
            reason = 'cancel'
            break
        end
        Wait(0)
    end

    if result then PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
    deleteGhost(ghost)
    for _, part in ipairs(parts) do deleteGhost(part.ent) end
    finish()
    return result, reason
end

-- ════════════════════════════════════════════════════════════════════════
-- BEDS: pick the bed, then pose a lying patient on it
-- ════════════════════════════════════════════════════════════════════════

-- lying poses a bed can use (Config.Transport.Beds.poses)
local function bedPoses()
    local list = {}
    local beds = Config.Transport and Config.Transport.Beds or {}
    for _, p in ipairs(beds.poses or {}) do
        if type(p) == 'table' and p.key and p.dict and p.clip then list[#list + 1] = p end
    end
    if #list == 0 then list[1] = { key = 'flat', label = 'Flat', dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 } end
    return list
end

-- top centre of a bed entity and the heading along its long side
local function bedAnchor(ent)
    local mn, mx = GetModelDimensions(GetEntityModel(ent))
    local top = GetOffsetFromEntityInWorldCoords(ent, (mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mx.z)
    local h = GetEntityHeading(ent)
    if (mx.x - mn.x) > (mx.y - mn.y) then h = h + 90.0 end
    return top, h % 360.0
end

local function clearOutline(ent)
    if ent and ent ~= 0 and DoesEntityExist(ent) and SetEntityDrawOutline then pcall(SetEntityDrawOutline, ent, false) end
end

local function cancelPressed()
    return IsDisabledControlJustPressed(0, CTRL.cancelQ) or IsDisabledControlJustPressed(0, CTRL.cancelX)
        or IsDisabledControlJustPressed(0, CTRL.esc)
end

-- → coords, nil, { lie = { exact = true, pose } } | nil, reason
function C.PlaceBed(opts)
    local bc = bcfg()
    local Tr = NZA.Transport
    local poses = bedPoses()
    local poseIx = 1
    local current = type(opts.lie) == 'table' and opts.lie.pose or nil
    for i, p in ipairs(poses) do if p.key == current then poseIx = i end end
    local state = {
        kind = 'bed', phase = 'pick', heading = 0.0, shownHeading = 0.0, height = 0.0, slide = 0.0,
        valid = false, max = bc.maxDistance or 25.0, keys = {}, foot = { hx = 0.4, hy = 1.0, cx = 0.0, cy = 0.0 },
    }
    local model = opts.ghostModel or bc.patientModel or 'a_m_y_genstreet_01'
    local ghost, picked, lit = 0, nil, 0
    active = { ghost = 0, parts = {} }

    NZA.UI.Open(APP, {
        type = opts.type, label = opts.label, icon = opts.icon, kind = 'bed', dept = opts.deptLabel,
        replace = opts.from ~= nil, locale = NZA.LocaleTable('hospital'),
        snapStep = bc.snapAngle or 15.0, max = state.max,
    }, { focus = false })

    local function pose() return poses[poseIx] end
    local function lift() return (Tr and Tr.LieLift) and Tr.LieLift(pose()) or 0.95 end
    local function playPose()
        state.poseLabel = pose().label or pose().key
        if ghost == 0 or not (Tr and Tr.Play) then return end
        Tr.Play(ghost, pose(), { blendIn = 1000.0 })
        -- measures how high this pose lies above its root (the patients use the same value)
        if Tr.SettleLying then Tr.SettleLying(ghost, pose(), lift(), function() end) end
    end

    local result, extra, reason = nil, nil, 'cancel'
    local fast, fine = bc.fastFactor or 3.0, bc.fineFactor or 0.2
    while true do
        local dt = GetFrameTime()
        for i = 1, #DISABLE do DisableControlAction(0, DISABLE[i], true) end
        local ped = PlayerPedId()
        if NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then reason = 'down'; break end
        if IsPedInAnyVehicle(ped, false) then reason = 'vehicle'; break end
        local fastHeld, fineHeld = IsControlPressed(0, CTRL.shift), IsControlPressed(0, CTRL.alt)
        local mult = fastHeld and fast or (fineHeld and fine or 1.0)
        local colour = state.valid and (bc.markerColour or { 8, 175, 162 }) or (bc.badColour or { 229, 72, 77 })

        if state.phase == 'pick' then
            -- the bed under the reticle lights up; the floor / a mattress without an entity = a free spot
            local hit = NZA.Cam.Raycast({ x = 0.5, y = 0.5, dist = state.max + 25.0, flags = 1 + 16, ignore = ped })
            local ent = hit.hit and hit.entity or 0
            if ent ~= 0 and (not DoesEntityExist(ent) or GetEntityType(ent) ~= 3) then ent = 0 end
            if ent ~= lit then clearOutline(lit); lit = ent end
            state.reason = nil
            if hit.hit and hit.coords then
                state.surface, state.pos = hit.coords, hit.coords
                state.dist = #(GetEntityCoords(ped) - hit.coords)
                if state.dist > state.max then state.reason = 'far' end
            else
                state.pos, state.dist, state.reason = nil, nil, 'nosurface'
            end
            state.valid = state.reason == nil
            state.target = lit ~= 0
            if lit ~= 0 then setOutline(lit, state.valid) end
            if state.pos and lit == 0 then
                DrawMarker(25, state.pos.x, state.pos.y, state.pos.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 1.0,
                    colour[1], colour[2], colour[3], 130, false, false, 2, false, nil, nil, false)
            end
            if IsDisabledControlJustPressed(0, CTRL.confirm) then
                if state.valid then
                    local top, h
                    if lit ~= 0 then top, h = bedAnchor(lit) else top, h = state.pos, GetEntityHeading(ped) end
                    picked = { ent = lit, top = top }
                    state.heading, state.height, state.slide = h, 0.0, 0.0
                    state.phase = 'pose'
                    ghost = makePedGhost(model, top, h)
                    if ghost ~= 0 then SetEntityAlpha(ghost, 215, false) end
                    active.ghost = ghost
                    playPose()
                    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                else
                    NZA.UI.Send(APP, 'flash', { reason = state.reason })
                    PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                end
            elseif cancelPressed() or IsDisabledControlJustPressed(0, CTRL.back) then
                reason = 'cancel'
                break
            end
        else
            -- pose: turn, slide along the bed, lift, change the pose
            local rot = 0.0
            if IsDisabledControlPressed(0, CTRL.left) then rot = rot + (bc.rotateSpeed or 90.0) * dt * mult end
            if IsDisabledControlPressed(0, CTRL.right) then rot = rot - (bc.rotateSpeed or 90.0) * dt * mult end
            if IsDisabledControlJustPressed(0, CTRL.wheelUp) then rot = rot + (bc.scrollStep or 7.5) * mult end
            if IsDisabledControlJustPressed(0, CTRL.wheelDown) then rot = rot - (bc.scrollStep or 7.5) * mult end
            if IsDisabledControlJustPressed(0, CTRL.snap) then rot = rot + 180.0 end
            state.heading = (state.heading + rot) % 360.0
            local slideSpeed = 0.6 * dt * mult
            if IsDisabledControlPressed(0, CTRL.slideF) then state.slide = math.min(1.5, state.slide + slideSpeed) end
            if IsDisabledControlPressed(0, CTRL.slideB) then state.slide = math.max(-1.5, state.slide - slideSpeed) end
            local hs = (bc.heightSpeed or 0.5) * 0.5 * dt * mult
            if IsDisabledControlPressed(0, CTRL.up) then state.height = math.min(0.8, state.height + hs) end
            if IsDisabledControlPressed(0, CTRL.down) then state.height = math.max(-0.8, state.height - hs) end
            if IsDisabledControlJustPressed(0, CTRL.pose) then
                poseIx = poseIx % #poses + 1
                playPose()
                PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            end
            local h = math.rad(state.heading)
            local fwd = vector3(-math.sin(h), math.cos(h), 0.0)
            local at = picked.top + fwd * state.slide + vector3(0.0, 0.0, lift() + state.height)
            state.pos = at
            state.dist = #(GetEntityCoords(ped) - at)
            state.reason = state.dist > state.max + 2.0 and 'far' or nil
            state.valid = state.reason == nil
            if ghost ~= 0 and DoesEntityExist(ghost) then
                SetEntityCoordsNoOffset(ghost, at.x, at.y, at.z, false, false, false)
                SetEntityHeading(ghost, state.heading)
                if Tr and Tr.Playing and not Tr.Playing(ghost, pose()) then playPose() end
            end
            if picked.ent ~= 0 then setOutline(picked.ent, state.valid) end
            if IsDisabledControlJustPressed(0, CTRL.confirm) then
                if state.valid then
                    result = { x = at.x, y = at.y, z = at.z, w = state.heading }
                    extra = { lie = { exact = true, pose = pose().key } }
                    reason = nil
                    break
                end
                NZA.UI.Send(APP, 'flash', { reason = state.reason })
                PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            elseif IsDisabledControlJustPressed(0, CTRL.back) then
                -- pick another bed
                deleteGhost(ghost)
                ghost, active.ghost = 0, 0
                clearOutline(picked.ent)
                picked = nil
                state.phase, state.poseLabel = 'pick', nil
            elseif cancelPressed() then
                reason = 'cancel'
                break
            end
        end

        state.shownHeading = state.heading
        state.keys = {
            fast = fastHeld, fine = fineHeld and not fastHeld,
            turn = IsDisabledControlPressed(0, CTRL.left) or IsDisabledControlPressed(0, CTRL.right),
            lift = IsDisabledControlPressed(0, CTRL.up) or IsDisabledControlPressed(0, CTRL.down),
            slide = IsDisabledControlPressed(0, CTRL.slideF) or IsDisabledControlPressed(0, CTRL.slideB),
        }
        sendState(state)
        Wait(0)
    end

    if result then PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
    clearOutline(lit)
    if picked then clearOutline(picked.ent) end
    deleteGhost(ghost)
    finish()
    return result, reason, extra
end

function C.Placing()
    return active ~= nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource or not active then return end
    deleteGhost(active.ghost)
    for _, part in ipairs(active.parts or {}) do deleteGhost(part.ent) end
    NZA.Props.Clear('nza:builder')
    active = nil
end)
