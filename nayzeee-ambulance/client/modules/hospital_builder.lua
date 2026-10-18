--[[
    NAYZEEE AMBULANCE - Site survey (placement) mode (client) for the Department Console

    NZA.HospitalC.Place(opts) → coords { x, y, z, w } | nil, reason        (blocking, call from a thread)
      opts = { type, label, icon, kind = 'prop'|'marker'|'car'|'heli', prop (model), model (vehicle),
               dept, deptLabel, heading, from = coords (re-place: start there) }

    Aim with the camera: a ray from the screen centre finds the floor / furniture under it.
      prop types    translucent ghost of the type's prop, bottom resting on the surface
      marker types  survey pin: a bobbing inverted cone over a dashed plumb line, a small floor ring
                    and a soft light pool (teal; red while the spot is invalid)
      vehicle types ghost car / helicopter (first garage vehicle of that kind)
      every kind    floor corner brackets around the footprint + a facing arrow
    Controls (game input stays free to walk / look):
      E confirm · Q / X / Backspace / ESC cancel · ← → (hold) or mouse wheel rotate
      Shift faster · Alt fine · Page Up / Page Down raise / lower · G snap heading
    The ghost never collides. Too far (Config.Hospital.builder.maxDistance) or no surface
    under the crosshair = invalid, E is refused.

    NUI app 'builder' (opened without focus): actions open, state, flash
      state carries keys = { fast, fine, turn, wheel, lift } so the HUD can light the held keys
]]

if not NAYZEEE_LOCK_OK then return end

NZA.HospitalC = NZA.HospitalC or {}
local C = NZA.HospitalC

local APP = 'builder'
local active = nil

local CTRL = {
    confirm = 38, cancelQ = 44, cancelX = 73, back = 177, esc = 200,
    left = 174, right = 175, up = 10, down = 11, wheelUp = 15, wheelDown = 14, snap = 47,
    shift = 21, alt = 19,
}
local DISABLE = { 24, 25, 37, 38, 44, 45, 47, 73, 10, 11, 14, 15, 16, 17, 140, 141, 142, 143, 174, 175, 177, 199, 200, 257, 263, 264, 81, 82, 99, 100 }

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

local function deleteGhost(ent)
    if not ent or ent == 0 then return end
    if IsEntityAVehicle(ent) then
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
    local r = kind == 'marker' and 0.55 or 1.0
    return { hx = r, hy = r, cx = 0.0, cy = 0.0 }
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

    -- floor corner brackets around the footprint (the NAYZEEE bracket, laid on the ground)
    local arm = math.min(0.45, math.min(fp.hx, fp.hy) * 0.6)
    for sx = -1, 1, 2 do
        for sy = -1, 1, 2 do
            local c = centre + right * (fp.hx * sx) + fwd * (fp.hy * sy)
            line(c, c - right * (arm * sx), r, g, b, 235)
            line(c, c - fwd * (arm * sy), r, g, b, 235)
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
        -- survey pin: bobbing inverted cone over a dashed plumb line + a thin floor ring
        local top = p.z + 1.05
        DrawMarker(0, p.x, p.y, top, 0.0, 0.0, 0.0, 0.0, 0.0, state.shownHeading, 0.26, 0.26, 0.34, r, g, b, 215, true, false, 2, false, nil, nil, false)
        DrawMarker(25, p.x, p.y, base.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 1.0, r, g, b, 120, false, false, 2, false, nil, nil, false)
        local z0, z1 = base.z + 0.05, top - 0.22
        local seg, gap = 0.09, 0.06
        local z = z0
        while z < z1 do
            local z2 = math.min(z1, z + seg)
            DrawLine(p.x, p.y, z, p.x, p.y, z2, r, g, b, 190)
            z = z2 + gap
        end
        if DrawLightWithRange then DrawLightWithRange(p.x, p.y, base.z + 0.6, r, g, b, 2.2, 1.6) end
    end
end

local function sendState(state, force)
    local now = GetGameTimer()
    local k = state.keys or {}
    local snapshot = ('%.1f|%.2f|%.1f|%s|%s|%s|%s%s%s%s%s'):format(state.shownHeading, state.height, state.dist or -1, tostring(state.valid), tostring(state.reason), tostring(state.snap),
        k.fast and 1 or 0, k.fine and 1 or 0, k.turn and 1 or 0, k.wheel and 1 or 0, k.lift and 1 or 0)
    if not force and (snapshot == state.lastSent or now - (state.lastAt or 0) < 90) then return end
    state.lastSent, state.lastAt = snapshot, now
    NZA.UI.Send(APP, 'state', {
        heading = state.shownHeading, height = state.height, dist = state.dist, max = state.max,
        valid = state.valid, reason = state.reason, snap = state.snap, snapStep = bcfg().snapAngle or 15.0,
        coords = state.pos and { x = state.pos.x, y = state.pos.y, z = state.pos.z } or nil,
        keys = k,
    })
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

    local ghost = 0
    if kind == 'prop' and opts.prop then
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
    active = { ghost = ghost }

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
        draw(state, state.valid and (bc.markerColour or { 8, 175, 162 }) or (bc.badColour or { 229, 72, 77 }))
        sendState(state)

        -- confirm / cancel
        if IsDisabledControlJustPressed(0, CTRL.confirm) then
            if state.valid then
                local saveZ = (kind == 'car' or kind == 'heli') and (surface.z + state.height) or state.pos.z
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
    NZA.UI.Close(APP)
    active = nil
    -- swallow the key that ended placement so it doesn't open the pause menu / fire anything
    local t = GetGameTimer()
    while GetGameTimer() - t < 250 do
        DisableControlAction(0, 200, true)
        DisableControlAction(0, 38, true)
        DisableControlAction(0, 44, true)
        Wait(0)
    end
    return result, reason
end

function C.Placing()
    return active ~= nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource or not active then return end
    deleteGhost(active.ghost)
    NZA.Props.Clear('nza:builder')
    active = nil
end)
