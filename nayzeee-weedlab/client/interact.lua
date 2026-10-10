--[[
    First person interactions (Schedule I style): a fixed camera on the station and the
    mouse. The page only shows the instruction pill + key hints; the mouse is read here
    (GetNuiCursorPosition + disabled controls), so nothing round-trips through NUI.

    Interact.run({ entity, cfg, steps, ctx, spin })    -> true when every step was completed
    Interact.scene({ entity, cfg, ctx, spin }, fn)     -> runs fn(S) with the camera up (custom scenes)

      cfg  = { cam = { offset, look, fov }, top, anchors }
      spin = { center = vec3, items = { { ent, pos, heading, scale } } }  A / D rotate these (the plant)
             without spin, A / D orbit the camera instead
      ctx  = { count, bud, rs, plant, point, after }

    Runs a Wait(0) loop only while an interaction is open.
]]

Interact = { active = false }

local cancelFlag = false
function Interact.cancel() cancelFlag = true end

local FX = {
    soil = { 92, 62, 44 }, water = { 120, 180, 255 }, liquid = { 210, 235, 255 }, seed = { 150, 120, 90 },
    speed = { 255, 210, 60 }, mist = { 190, 255, 200 }, dust = { 170, 200, 120 },
}

local function W(ent, v) return GetOffsetFromEntityInWorldCoords(ent, v.x, v.y, v.z) end
local function lerp(a, b, t) return a + (b - a) * t end
local function dist2(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

--[[ ─────────────── session helpers ─────────────── ]]

local function anchor(S, name)
    local a = name and S.cfg.anchors and S.cfg.anchors[name]
    if a then return W(S.ent, a) end
    return W(S.ent, vec3(0.0, 0.0, S.cfg.top or 0.5))
end

local function dirW(S, v)
    return W(S.ent, v) - S.origin
end

local function placeCam(S)
    local o = S.cfg.cam.offset
    local x, y = Utils.rotate(o.x, o.y, S.yaw)
    local p = W(S.ent, vec3(x, y, o.z))
    local l = W(S.ent, S.cfg.cam.look)
    local d = l - p
    SetCamCoord(S.cam, p.x, p.y, p.z)
    SetCamRot(S.cam, math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y))), 0.0, math.deg(math.atan(-d.x, d.y)), 2)
end

local function spawn(S, model, pos, heading, fallback, scale)
    if not model then return nil end
    local e = Util.prop(model, pos, heading or GetEntityHeading(S.ent), { noCollision = true, fallback = fallback, scale = scale })
    if e then S.spawned[#S.spawned + 1] = e end
    return e
end

local function topOf(ent)
    local mn, mx = GetModelDimensions(GetEntityModel(ent))
    return mx.z, mn.z
end

local function keys(S)
    return {
        { key = 'Mouse', label = 'Move' },
        { key = 'LMB', label = 'Use' },
        { key = 'A D', label = S.spin and 'Rotate plant' or 'Rotate view' },
        { key = 'Esc', label = 'Exit' },
    }
end

local function hint(S, text, pct, count)
    local key = text .. tostring(pct) .. tostring(count)
    if key == S.lastHint then return end
    S.lastHint = key
    UI.send('ix', { text = text, pct = pct, count = count, keys = S.keys })
end

local function marker(kind, p, size, c, a)
    DrawMarker(kind, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, size, c[1], c[2], c[3], a or 200, false, false, 2, false, nil, nil, false)
end

-- spin the plant (pot, soil, plant) around its centre
local function applySpin(S)
    for _, it in ipairs(S.spin.items) do
        if it.ent and DoesEntityExist(it.ent) then
            if it.scale and it.scale ~= 1.0 then
                Util.transform(it.ent, it.pos, it.heading + S.spinAngle, it.scale)
            else
                SetEntityHeading(it.ent, it.heading + S.spinAngle)
            end
        end
    end
    if S.onSpin then S.onSpin(S) end
end

-- common per-frame work. false = the player left
local function frame(S)
    DisableAllControlActions(0)
    EnableControlAction(0, 249, true) -- push to talk
    HideHudAndRadarThisFrame()
    local dt = GetFrameTime()
    local turn = (IsDisabledControlPressed(0, 34) and -1 or 0) + (IsDisabledControlPressed(0, 35) and 1 or 0)
    if turn ~= 0 then
        if S.spin then
            S.spinAngle = (S.spinAngle + turn * 90.0 * dt) % 360.0
            applySpin(S)
        else
            S.yaw = Utils.clamp(S.yaw + turn * 60.0 * dt, -70.0, 70.0)
            placeCam(S)
        end
    end
    if cancelFlag or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) or IsEntityDead(cache.ped) then return false end
    S.dt = dt
    S.sx, S.sy, S.w, S.h = Util.cursor()
    S.down = IsDisabledControlPressed(0, 24)
    S.pressed = IsDisabledControlJustPressed(0, 24)
    S.released = IsDisabledControlJustReleased(0, 24)
    S.rpos, S.rdir = Util.screenRay(S.cam, S.sx, S.sy)
    return true
end

--- screen distance in pixels from the cursor to a world point
local function pxTo(S, p)
    local x, y = Util.toScreen(p)
    if not x then return 1e9 end
    local dx, dy = (x - S.sx) * S.w, (y - S.sy) * S.h
    return math.sqrt(dx * dx + dy * dy)
end

--- point under the cursor on the plane at height z, kept near `center`
local function cursorOn(S, z, center, maxR)
    local p = Util.rayPlane(S.rpos, S.rdir, z)
    if not p then return nil end
    if center and maxR then
        local d = p - vec3(center.x, center.y, z)
        local len = math.sqrt(d.x * d.x + d.y * d.y)
        if len > maxR then p = vec3(center.x, center.y, z) + vec3(d.x, d.y, 0.0) / len * maxR end
    end
    return p
end

local function moveEnt(S, ent, p, pitch, roll, yaw)
    if not ent or not p then return end
    SetEntityCoordsNoOffset(ent, p.x, p.y, p.z, false, false, false)
    SetEntityRotation(ent, pitch or 0.0, roll or 0.0, yaw or (S.heading + S.yaw), 2, true)
end

local function moveHeld(S, p, pitch, roll)
    moveEnt(S, S.held, p, pitch, roll)
end

local function setHeld(S, model, at)
    if S.heldModel == model and S.held then return end
    if S.held then Util.delete(S.held) end
    S.heldModel = model
    S.held = nil
    if not model then return end
    S.held = spawn(S, model, at or anchor(S), S.heading)
end

-- particles drawn with markers (no asset streaming, always visible)
local function particles(S, emitAt, kind, floorZ, vel)
    S.parts = S.parts or {}
    if emitAt then
        for _ = 1, 2 do
            local v = vel and vec3(vel.x + (math.random() - 0.5) * 0.2, vel.y + (math.random() - 0.5) * 0.2, vel.z) or vec3(0.0, 0.0, 0.0)
            S.parts[#S.parts + 1] = { p = emitAt + vec3((math.random() - 0.5) * 0.03, (math.random() - 0.5) * 0.03, 0.0), v = v, life = 1.2 }
        end
    end
    local c = FX[kind] or FX.soil
    for i = #S.parts, 1, -1 do
        local pt = S.parts[i]
        pt.life = pt.life - S.dt
        pt.v = vec3(pt.v.x * 0.96, pt.v.y * 0.96, pt.v.z - (kind == 'mist' and 1.5 or 9.8) * S.dt)
        pt.p = pt.p + pt.v * S.dt
        if pt.p.z < floorZ or pt.life <= 0 then
            table.remove(S.parts, i)
        else
            marker(28, pt.p, (kind == 'soil' or kind == 'seed') and 0.02 or (kind == 'mist' and 0.009 or 0.012), c, kind == 'mist' and 150 or 230)
        end
    end
end

--[[ ─────────────── steps ─────────────── ]]
local STEP = {}

function STEP.cut(S, st)
    local base = st.anchor and anchor(S, st.anchor) or S.origin
    local center = base + dirW(S, st.at)
    local xaxis = dirW(S, vec3(1.0, 0.0, 0.0))
    local A, B = center - xaxis * (st.width * 0.5), center + xaxis * (st.width * 0.5)
    if st.prop and not st.zip then
        local e = spawn(S, st.prop, center, S.heading)
        if e then
            local top = topOf(e)
            SetEntityCoordsNoOffset(e, center.x, center.y, center.z - top + 0.01, false, false, false)
            S.stepProp = e
        end
    end
    local lo, hi = nil, nil
    while true do
        if not frame(S) then return false end
        local ax, ay = Util.toScreen(A)
        local bx, by = Util.toScreen(B)
        if ax and bx and S.down then
            local vx, vy = (bx - ax) * S.w, (by - ay) * S.h
            local px, py = (S.sx - ax) * S.w, (S.sy - ay) * S.h
            local u = Utils.clamp((px * vx + py * vy) / math.max(1.0, vx * vx + vy * vy), 0.0, 1.0)
            local ex, ey = px - u * vx, py - u * vy
            if math.sqrt(ex * ex + ey * ey) < 34 then
                lo = math.min(lo or u, u)
                hi = math.max(hi or u, u)
            end
        end
        local prog = (lo and hi) and (hi - lo) or 0.0
        local c = st.zip and { 60, 140, 255 } or { 255, 214, 10 }
        for k = -1, 1 do
            DrawLine(A.x, A.y, A.z + k * 0.0015, B.x, B.y, B.z + k * 0.0015, c[1], c[2], c[3], 255)
        end
        if lo then
            local P, Q = A + (B - A) * lo, A + (B - A) * hi
            DrawLine(P.x, P.y, P.z + 0.003, Q.x, Q.y, Q.z + 0.003, 255, 255, 255, 255)
        end
        hint(S, st.text, math.floor(prog * 100))
        if prog >= 0.92 then
            PlaySoundFrontend(-1, st.zip and 'Zipper' or 'CLICK_BACK', st.zip and 'MP_Award_Sounds' or 'WEB_NAVIGATION_SOUNDS_PHONE', true)
            return true
        end
        Wait(0)
    end
end

function STEP.pour(S, st)
    local center = anchor(S, st.anchor)
    local target = center
    if st.target == 'random' then
        local a, r = math.random() * math.pi * 2, math.random() * 0.06
        target = center + dirW(S, vec3(math.cos(a) * r, math.sin(a) * r, 0.0))
    end
    local planeZ = S.origin.z + st.height
    if S.stepProp and st.prop then
        -- the bag that was just cut becomes the held item
        S.held, S.heldModel, S.stepProp = S.stepProp, st.prop, nil
    else
        setHeld(S, st.prop, vec3(target.x, target.y, planeZ))
    end
    local prog, tilt = 0.0, 0.0
    while true do
        if not frame(S) then return false end
        local p = cursorOn(S, planeZ, center, 0.6)
        tilt = lerp(tilt, S.down and st.tilt or 0.0, math.min(1.0, S.dt * 7.0))
        moveHeld(S, p, 0.0, tilt)
        local over = p and dist2(p, target) <= st.radius
        local pouring = S.down and tilt > st.tilt * 0.55
        marker(25, vec3(target.x, target.y, target.z + 0.012), st.radius * 2.0, over and { 63, 185, 80 } or { 8, 175, 162 }, 170)
        if pouring and p then
            particles(S, p - vec3(0.0, 0.0, 0.05), st.fx, target.z)
            if over then prog = prog + S.dt / st.seconds end
        else
            particles(S, nil, st.fx, target.z)
        end
        hint(S, st.text, math.floor(math.min(1.0, prog) * 100))
        if prog >= 1.0 then return true end
        Wait(0)
    end
end

--- hold to spray at the plant: mist drifts from the nozzle towards the plant
function STEP.spray(S, st)
    local base = anchor(S, st.anchor)
    local aim = base + vec3(0.0, 0.0, (S.ctx.plantHeight or 0.4) * 0.5)
    setHeld(S, st.prop, aim)
    local prog = 0.0
    while true do
        if not frame(S) then return false end
        local p = S.rpos + S.rdir * 0.5
        moveHeld(S, p + vec3(0.0, 0.0, -0.12), 0.0, 0.0)
        local on = pxTo(S, aim) < 160
        marker(28, aim, st.radius, on and { 63, 185, 80 } or { 8, 175, 162 }, 60)
        if S.down then
            local nozzle = p + vec3(0.0, 0.0, 0.1)
            local d = aim - nozzle
            particles(S, nozzle, 'mist', aim.z - 0.6, d / #d * 1.4)
            if on then prog = prog + S.dt / st.seconds end
            if not S.sprayT or GetGameTimer() - S.sprayT > 380 then
                S.sprayT = GetGameTimer()
                PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
            end
        else
            particles(S, nil, 'mist', aim.z - 0.6)
        end
        hint(S, st.text, math.floor(math.min(1.0, prog) * 100))
        if prog >= 1.0 then return true end
        Wait(0)
    end
end

local function genTargets(S, st)
    local list, top = {}, anchor(S, st.anchor)
    if st.targets == 'cap' then
        local at = top + vec3(0.0, 0.0, 0.3)
        setHeld(S, st.prop, at)
        if S.held then
            moveHeld(S, at, 0.0, 0.0)
            list[1] = { p = at + vec3(0.0, 0.0, topOf(S.held)), m = { 255, 255, 255 }, size = 0.025 }
        else
            list[1] = { p = at }
        end
    elseif st.targets == 'ring' then
        local n = st.count or 6
        for i = 1, n do
            local a = (i / n) * math.pi * 2
            list[i] = { p = top + dirW(S, vec3(math.cos(a) * 0.075, math.sin(a) * 0.075, 0.015)), m = st.marker or { 88, 58, 44 }, size = 0.05 }
        end
    end
    return list
end

function STEP.click(S, st)
    local list = genTargets(S, st)
    local need = st.count or #list
    local hits = 0
    local tool = (st.targets ~= 'cap') and st.prop
    if tool then setHeld(S, tool) end
    while true do
        if not frame(S) then return false end
        if tool and S.held then moveHeld(S, S.rpos + S.rdir * 0.55, -20.0, 0.0) end
        for _, t in ipairs(list) do
            if not t.done and t.m then marker(28, t.p, t.size or 0.04, t.m, 230) end
        end
        if S.pressed then
            local best, bd
            for _, t in ipairs(list) do
                if not t.done then
                    local d = pxTo(S, t.p)
                    if d < 32 and (not bd or d < bd) then best, bd = t, d end
                end
            end
            if best then
                best.done = true
                hits = hits + 1
                PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
            end
        end
        hint(S, st.text, nil, ('%d/%d'):format(hits, need))
        if hits >= need then return true end
        Wait(0)
    end
end

--[[ trim: buds sit on the plant. Only buds facing the camera can be cut, so rotate the plant (A / D) ]]
local function budLayout(S, n)
    local h = S.ctx.plantHeight or 0.9
    local rs = S.ctx.rs or 1
    local list = {}
    for i = 1, n do
        local t = (i - 0.5) / n
        local a = (i * 2.39996 + rs * 0.37) % (math.pi * 2)
        local z = h * (0.42 + t * 0.52)
        local r = (0.06 + 0.12 * (1.0 - t)) * (S.ctx.plantScale or 1.0) + 0.02
        list[i] = { a = a, r = r, z = z }
    end
    return list
end

function STEP.trim(S, st)
    local base = S.ctx.plantBase or anchor(S)
    local buds = budLayout(S, math.max(1, S.ctx.count or 6))
    local model = Config.Props.bud[S.ctx.bud or 'green']
    for _, b in ipairs(buds) do
        b.e = spawn(S, model, base, 0.0, Config.Props.budFallback)
    end
    local function place()
        for _, b in ipairs(buds) do
            if not b.done and b.e then
                local a = b.a + math.rad(S.spinAngle or 0.0)
                b.p = base + vec3(math.cos(a) * b.r, math.sin(a) * b.r, b.z)
                SetEntityCoordsNoOffset(b.e, b.p.x, b.p.y, b.p.z - 0.03, false, false, false)
                SetEntityRotation(b.e, 0.0, 25.0, math.deg(a), 2, true)
            end
        end
    end
    S.onSpin = place
    place()
    setHeld(S, st.prop)
    local camPos = GetCamCoord(S.cam)
    local hits, need = 0, #buds
    while true do
        if not frame(S) then S.onSpin = nil return false end
        if S.held then moveHeld(S, S.rpos + S.rdir * 0.45, -10.0, 0.0) end
        local best, bd
        for _, b in ipairs(buds) do
            if not b.done and b.p then
                local out = vec3(b.p.x - base.x, b.p.y - base.y, 0.0)
                local toCam = vec3(camPos.x - b.p.x, camPos.y - b.p.y, 0.0)
                local facing = (out.x * toCam.x + out.y * toCam.y) / math.max(1e-4, #out * #toCam)
                b.reach = facing > -0.15
                marker(28, b.p, 0.035, b.reach and { 120, 220, 90 } or { 90, 90, 90 }, b.reach and 200 or 70)
                if b.reach then
                    local d = pxTo(S, b.p)
                    if d < 34 and (not bd or d < bd) then best, bd = b, d end
                end
            end
        end
        if S.pressed and best then
            best.done = true
            hits = hits + 1
            PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
            local e, from = best.e, best.p
            CreateThread(function()
                local t0 = GetGameTimer()
                while GetGameTimer() - t0 < 350 and DoesEntityExist(e) do
                    local k = (GetGameTimer() - t0) / 350.0
                    SetEntityCoordsNoOffset(e, from.x, from.y, from.z - 0.03 - k * k * 0.5, false, false, false)
                    Wait(0)
                end
                Util.delete(e)
            end)
        end
        hint(S, st.text, nil, ('%d/%d'):format(hits, need))
        if hits >= need then S.onSpin = nil return true end
        Wait(0)
    end
end

function STEP.hold(S, st)
    local tap = S.ctx.point or anchor(S)
    setHeld(S, st.prop, tap - vec3(0.0, 0.0, 0.32))
    moveHeld(S, tap - vec3(0.0, 0.0, 0.32), 0.0, 0.0)
    local prog = 0.0
    while true do
        if not frame(S) then return false end
        local on = S.down and pxTo(S, tap) < 70
        marker(28, tap, 0.04, on and { 63, 185, 80 } or { 8, 175, 162 }, 200)
        if on then
            prog = prog + S.dt / st.seconds
            particles(S, tap - vec3(0.0, 0.0, 0.03), 'water', tap.z - 0.3)
        else
            particles(S, nil, 'water', tap.z - 0.3)
        end
        hint(S, st.text, math.floor(math.min(1.0, prog) * 100))
        if prog >= 1.0 then return true end
        Wait(0)
    end
end

--[[ ─────────────── scene helpers (packaging, mixing, drying, press) ─────────────── ]]

--- entity under the cursor from `list` = { { e, p } }, within px pixels
local function pick(S, list, px)
    local best, bd
    for _, it in ipairs(list) do
        if not it.done and it.p then
            local d = pxTo(S, it.p)
            if d < (px or 34) and (not bd or d < bd) then best, bd = it, d end
        end
    end
    return best
end

--- drag `ent` on the plane z (lifted) until released. onMove(p) per frame.
--- returns the release point (or nil if the player left)
local function drag(S, ent, z, center, maxR, onMove)
    while true do
        if not frame(S) then return nil end
        local p = cursorOn(S, z, center, maxR or 0.9)
        if p then
            moveEnt(S, ent, p, 0.0, 0.0, GetEntityHeading(ent))
            if onMove then onMove(p) end
        end
        if not S.down then return p end
        Wait(0)
    end
end

--- slide an entity between two points (ease out)
local function slide(S, ent, from, to, ms, arc)
    local t0 = GetGameTimer()
    while true do
        local k = math.min(1.0, (GetGameTimer() - t0) / ms)
        local e = 1.0 - (1.0 - k) * (1.0 - k)
        local q = vec3(lerp(from.x, to.x, e), lerp(from.y, to.y, e), lerp(from.z, to.z, e) + (arc or 0.0) * math.sin(k * math.pi))
        if ent and DoesEntityExist(ent) then SetEntityCoordsNoOffset(ent, q.x, q.y, q.z, false, false, false) end
        if not frame(S) then return false end
        if k >= 1.0 then return true end
        Wait(0)
    end
end

--- rotate an entity's pitch from -> to over ms (lids, hatches, levers)
local function swing(S, ent, from, to, ms, heading)
    local t0 = GetGameTimer()
    while true do
        local k = math.min(1.0, (GetGameTimer() - t0) / ms)
        local e = 1.0 - (1.0 - k) * (1.0 - k)
        if ent and DoesEntityExist(ent) then SetEntityRotation(ent, lerp(from, to, e), 0.0, heading or S.heading, 2, true) end
        if not frame(S) then return false end
        if k >= 1.0 then return true end
        Wait(0)
    end
end

local function open(def)
    if Interact.active then return nil end
    Interact.active = true
    cancelFlag = false
    LocalPlayer.state:set('nzwlBusy', true, false)
    local S = {
        ent = def.entity, cfg = def.cfg, ctx = def.ctx or {}, spawned = {}, yaw = 0.0,
        origin = GetEntityCoords(def.entity), heading = GetEntityHeading(def.entity),
        spin = def.spin, spinAngle = 0.0,
    }
    S.keys = keys(S)
    FreezeEntityPosition(cache.ped, true)
    S.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(S.cam, def.cfg.cam.fov or 50.0)
    placeCam(S)
    RenderScriptCams(true, true, 350, true, false)
    UI.hud(false)
    UI.setFocus(true, true, true)
    Wait(350)
    return S
end

local function close(S)
    UI.send('ix', false)
    UI.setFocus(false)
    if S.spin and S.spinAngle ~= 0.0 then
        S.spinAngle = 0.0
        S.onSpin = nil
        applySpin(S)
    end
    for _, e in ipairs(S.spawned) do Util.delete(e) end
    if S.held then Util.delete(S.held) end
    RenderScriptCams(false, true, 350, true, false)
    DestroyCam(S.cam, false)
    FreezeEntityPosition(cache.ped, false)
    LocalPlayer.state:set('nzwlBusy', false, false)
    Interact.active = false
    Main.refreshHud()
end

--[[ ─────────────── run ─────────────── ]]
function Interact.run(def)
    local S = open(def)
    if not S then return false end
    local ok = true
    for _, st in ipairs(def.steps) do
        S.lastHint = nil
        local fn = STEP[st.type]
        if not fn or not fn(S, st) then ok = false break end
        if S.stepProp and st.type ~= 'cut' then Util.delete(S.stepProp) S.stepProp = nil end
    end
    if ok and S.ctx.after then ok = S.ctx.after(S) ~= false end
    close(S)
    return ok
end

--- custom scene: fn(S) returns a value that Interact.scene passes back (nil if the player left)
function Interact.scene(def, fn)
    local S = open(def)
    if not S then return nil end
    local ok, res = pcall(fn, S)
    if not ok then print(('^1[%s] scene error: %s^7'):format(RES, tostring(res))) res = nil end
    close(S)
    return res
end

-- helpers for the scenes
Interact.anchor = anchor
Interact.spawn = spawn
Interact.hint = hint
Interact.frame = frame
Interact.marker = marker
Interact.pxTo = pxTo
Interact.cursorOn = cursorOn
Interact.moveEnt = moveEnt
Interact.pick = pick
Interact.drag = drag
Interact.slide = slide
Interact.swing = swing
Interact.particles = particles
Interact.topOf = topOf
Interact.step = STEP
