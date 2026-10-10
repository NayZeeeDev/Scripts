--[[
    First person interactions (Schedule I style): a fixed camera on the station and the
    mouse. The page only shows the instruction pill + key hints; the mouse is read here
    (GetNuiCursorPosition + disabled controls), so nothing round-trips through NUI.

    Interact.run({ entity, cfg, steps, ctx }) -> true when every step was completed
      cfg  = station config (cam, top, anchors, lid)
      ctx  = { count = targets for click steps, lid = entity, point = world pos (hold),
               scene = { bag = entity, jar = entity }, after = function(S) (auto part) }

    Runs a Wait(0) loop only while an interaction is open.
]]

Interact = { active = false }

local cancelFlag = false
function Interact.cancel() cancelFlag = true end

local KEYS = {
    { key = 'Mouse', label = 'Move' },
    { key = 'LMB', label = 'Use' },
    { key = 'A D', label = 'Rotate view' },
    { key = 'Esc', label = 'Exit' },
}

local FX_COLOR = {
    soil = { 92, 62, 44 }, water = { 120, 180, 255 }, liquid = { 200, 230, 255 }, powder = { 240, 240, 240 },
}

local function W(ent, v) return GetOffsetFromEntityInWorldCoords(ent, v.x, v.y, v.z) end

local function dirW(S, v)
    return W(S.ent, v) - S.origin
end

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

local function placeCam(S)
    local o = S.cfg.cam.offset
    local r = math.rad(S.yaw)
    local x = o.x * math.cos(r) - o.y * math.sin(r)
    local y = o.x * math.sin(r) + o.y * math.cos(r)
    local p = W(S.ent, vec3(x, y, o.z))
    local l = W(S.ent, S.cfg.cam.look)
    local d = l - p
    SetCamCoord(S.cam, p.x, p.y, p.z)
    SetCamRot(S.cam, math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y))), 0.0, math.deg(math.atan(-d.x, d.y)), 2)
end

local function spawn(S, model, pos, heading, fallback)
    if not model then return nil end
    local e = Util.prop(model, pos, heading or GetEntityHeading(S.ent), { noCollision = true, fallback = fallback })
    if e then S.spawned[#S.spawned + 1] = e end
    return e
end

local function topOf(ent)
    local mn, mx = GetModelDimensions(GetEntityModel(ent))
    return mx.z, mn.z
end

local function hint(S, text, pct, count)
    local key = text .. tostring(pct) .. tostring(count)
    if key == S.lastHint then return end
    S.lastHint = key
    UI.send('ix', { text = text, pct = pct, count = count, keys = KEYS })
end

local function marker(kind, p, size, c, a)
    DrawMarker(kind, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, kind == 25 and size or size, c[1], c[2], c[3], a or 200, false, false, 2, false, nil, nil, false)
end

-- common per-frame work. false = the player left
local function frame(S)
    DisableAllControlActions(0)
    EnableControlAction(0, 249, true) -- push to talk
    HideHudAndRadarThisFrame()
    local dt = GetFrameTime()
    if IsDisabledControlPressed(0, 34) then S.yaw = S.yaw - 70.0 * dt placeCam(S) end
    if IsDisabledControlPressed(0, 35) then S.yaw = S.yaw + 70.0 * dt placeCam(S) end
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

local function moveHeld(S, p, pitch, roll)
    if not S.held or not p then return end
    SetEntityCoordsNoOffset(S.held, p.x, p.y, p.z, false, false, false)
    SetEntityRotation(S.held, pitch or 0.0, roll or 0.0, S.heading + S.yaw, 2, true)
end

local function setHeld(S, model, at)
    if S.heldModel == model and S.held then return end
    if S.held and not S.heldScene then Util.delete(S.held) end
    S.heldScene = false
    S.heldModel = model
    S.held = nil
    if not model then return end
    if model:sub(1, 5) == 'held:' then
        S.held = S.ctx.scene and S.ctx.scene[model:sub(6)]
        S.heldScene = true
        if S.held then SetEntityCollision(S.held, false, false) end
        return
    end
    S.held = spawn(S, model, at or anchor(S), S.heading)
end

-- particles drawn with markers (no asset streaming, always visible)
local function particles(S, emitAt, kind, floorZ)
    S.parts = S.parts or {}
    if emitAt then
        for _ = 1, 2 do
            S.parts[#S.parts + 1] = { p = emitAt + vec3((math.random() - 0.5) * 0.03, (math.random() - 0.5) * 0.03, 0.0), v = 0.0 }
        end
    end
    local c = FX_COLOR[kind] or FX_COLOR.soil
    for i = #S.parts, 1, -1 do
        local pt = S.parts[i]
        pt.v = pt.v + 9.8 * S.dt
        pt.p = pt.p - vec3(0.0, 0.0, pt.v * S.dt)
        if pt.p.z < floorZ then
            table.remove(S.parts, i)
        else
            marker(28, pt.p, kind == 'soil' and 0.022 or 0.012, c, 230)
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
            local o = vec3(0.0, 0.0, k * 0.0015)
            DrawLine(A.x + o.x, A.y + o.y, A.z + o.z, B.x + o.x, B.y + o.y, B.z + o.z, c[1], c[2], c[3], 255)
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
    setHeld(S, st.prop, vec3(target.x, target.y, planeZ))
    if S.stepProp and S.stepProp ~= S.held then Util.delete(S.stepProp) end
    -- the bag that was just cut becomes the held item
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

local function genTargets(S, st)
    local list, top = {}, anchor(S, st.anchor)
    local kind = st.targets
    if kind == 'cap' then
        local at = top + vec3(0.0, 0.0, 0.3)
        setHeld(S, st.prop, at)
        if S.held then
            moveHeld(S, at, 0.0, 0.0)
            local t = topOf(S.held)
            list[1] = { p = at + vec3(0.0, 0.0, t) }
        else
            list[1] = { p = at }
        end
    elseif kind == 'ring' then
        local n = st.count or 6
        for i = 1, n do
            local a = (i / n) * math.pi * 2
            list[i] = { p = top + dirW(S, vec3(math.cos(a) * 0.075, math.sin(a) * 0.075, 0.02)), m = st.marker or { 88, 58, 44 }, size = 0.05 }
        end
    elseif kind == 'buds' or kind == 'caps' then
        local n = math.max(1, S.ctx.count or 8)
        for i = 1, n do
            local p
            if kind == 'buds' then
                local a, h, r = i * 2.39996, 0.32 + (i / n) * 0.78, 0.1 + 0.07 * ((i % 3) / 2)
                p = top + dirW(S, vec3(math.cos(a) * r, math.sin(a) * r, h))
            else
                p = top + dirW(S, vec3((math.random() - 0.5) * 0.45, (math.random() - 0.5) * 0.3, 0.03))
            end
            local model = kind == 'buds' and Config.GrowProps.bud or Config.GrowProps.cap
            local e = spawn(S, model, p, math.random() * 360.0, false)
            if e and kind == 'caps' then
                local mn, mx = GetModelDimensions(GetEntityModel(e))
                if (mx.z - mn.z) > 0.35 then Util.delete(e) e = nil end
            end
            list[i] = { p = p, e = e, m = (kind == 'buds') and { 120, 200, 90 } or { 230, 200, 150 }, size = 0.05 }
        end
    elseif kind == 'shards' then
        for i = 1, st.count or 8 do
            list[i] = { p = top + dirW(S, vec3((math.random() - 0.5) * 0.28, (math.random() - 0.5) * 0.18, 0.02)), m = st.marker or { 140, 200, 255 }, size = 0.045 }
        end
    elseif kind == 'jarlid' then
        local jarTop = anchor(S, 'bag') + vec3(0.0, 0.0, 0.093)
        local hover = jarTop + vec3(0.0, 0.0, 0.1)
        local lid = spawn(S, Config.PackProps.jarLid, hover, S.heading, false)
        list[1] = { p = hover + vec3(0.0, 0.0, 0.008), e = lid, lidTo = jarTop }
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
        if tool and S.held then
            local p = S.rpos + S.rdir * 0.55
            moveHeld(S, p, -20.0, 0.0)
        end
        for _, t in ipairs(list) do
            if not t.done and not t.e and t.m then marker(28, t.p, t.size, t.m, 230) end
        end
        if S.pressed then
            local best, bd
            for _, t in ipairs(list) do
                if not t.done then
                    local d = pxTo(S, t.p)
                    if d < 30 and (not bd or d < bd) then best, bd = t, d end
                end
            end
            if best then
                best.done = true
                hits = hits + 1
                PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
                if best.lidTo and best.e then
                    SetEntityCoordsNoOffset(best.e, best.lidTo.x, best.lidTo.y, best.lidTo.z, false, false, false)
                    S.scene_lid = best.e
                elseif best.e then
                    Util.delete(best.e)
                end
            end
        end
        hint(S, st.text, nil, ('%d/%d'):format(hits, need))
        if hits >= need then return true end
        Wait(0)
    end
end

function STEP.drop(S, st)
    local target = anchor(S, st.target)
    local planeZ = S.origin.z + st.height
    local start = st.from and anchor(S, st.from) or vec3(target.x, target.y, planeZ)
    setHeld(S, st.prop, start)
    if S.held and S.heldScene then
        -- bring the bag / jar (and its lid) with us
        S.carryLid = S.scene_lid
    end
    while true do
        if not frame(S) then return false end
        local p = cursorOn(S, planeZ, target, 0.9)
        moveHeld(S, p, 0.0, 0.0)
        if S.carryLid and p then
            SetEntityCoordsNoOffset(S.carryLid, p.x, p.y, p.z + 0.093, false, false, false)
        end
        local over = p and dist2(p, target) <= st.radius * 1.6
        marker(25, vec3(target.x, target.y, target.z + 0.01), st.radius * 2.0, over and { 63, 185, 80 } or { 8, 175, 162 }, 170)
        hint(S, st.text)
        if over and (S.pressed or S.released) then
            local from = p
            local t0 = GetGameTimer()
            while GetGameTimer() - t0 < 260 do
                frame(S)
                local k = (GetGameTimer() - t0) / 260.0
                local q = vec3(lerp(from.x, target.x, k), lerp(from.y, target.y, k), lerp(from.z, target.z, k * k))
                moveHeld(S, q, 0.0, 0.0)
                if S.carryLid then SetEntityCoordsNoOffset(S.carryLid, q.x, q.y, q.z + 0.093, false, false, false) end
                Wait(0)
            end
            PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
            -- the dropped item stays where it landed; a fresh held item is spawned by the next step
            if not S.heldScene then S.dropped[#S.dropped + 1] = S.held end
            S.held, S.heldModel, S.heldScene, S.carryLid = nil, nil, false, nil
            return true
        end
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

function STEP.stir(S, st)
    local center = anchor(S, st.anchor)
    if st.prop then setHeld(S, st.prop, center) end
    local acc, last = 0.0, nil
    local need = (st.turns or 3) * math.pi * 2
    while true do
        if not frame(S) then return false end
        local cx, cy = Util.toScreen(center)
        if st.prop then moveHeld(S, cursorOn(S, center.z + 0.12, center, st.radius * 1.5), 0.0, 0.0) end
        marker(25, vec3(center.x, center.y, center.z + 0.01), st.radius * 2.0, { 8, 175, 162 }, 150)
        if cx and S.down then
            local dx, dy = (S.sx - cx) * S.w, (S.sy - cy) * S.h
            local r = math.sqrt(dx * dx + dy * dy)
            if r > 14 and r < 320 then
                local a = math.atan(dy, dx)
                if last then
                    local d = a - last
                    if d > math.pi then d = d - math.pi * 2 elseif d < -math.pi then d = d + math.pi * 2 end
                    acc = acc + math.abs(d)
                end
                last = a
            end
        else
            last = nil
        end
        hint(S, st.text, math.floor(math.min(1.0, acc / need) * 100))
        if acc >= need then return true end
        Wait(0)
    end
end

local function lidTo(S, open)
    local lid = S.ctx.lid
    if not lid or not DoesEntityExist(lid) then return end
    local cfg = S.cfg.lid
    local from = S.lidPitch or 0.0
    local to = open and cfg.open or 0.0
    local t0 = GetGameTimer()
    while true do
        local k = math.min(1.0, (GetGameTimer() - t0) / 450.0)
        S.lidPitch = lerp(from, to, 1.0 - (1.0 - k) * (1.0 - k))
        SetEntityRotation(lid, S.lidPitch, 0.0, S.heading, 2, true)
        frame(S)
        if k >= 1.0 then break end
        Wait(0)
    end
end
Interact.lidTo = lidTo

function STEP.anim(S, st)
    hint(S, st.text)
    if st.lid then lidTo(S, st.lid == 'open') end
    return true
end

--[[ ─────────────── run ─────────────── ]]
function Interact.run(def)
    if Interact.active then return false end
    Interact.active = true
    cancelFlag = false
    LocalPlayer.state:set('nzdeBusy', true, false)

    local S = {
        ent = def.entity, cfg = def.cfg, ctx = def.ctx or {}, spawned = {}, dropped = {}, yaw = 0.0,
        origin = GetEntityCoords(def.entity), heading = GetEntityHeading(def.entity),
    }
    FreezeEntityPosition(cache.ped, true)
    S.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(S.cam, def.cfg.cam.fov or 50.0)
    placeCam(S)
    RenderScriptCams(true, true, 350, true, false)
    UI.hud(false)
    UI.setFocus(true, true, true)
    Wait(350)

    local ok = true
    for i, st in ipairs(def.steps) do
        S.lastHint = nil
        local fn = STEP[st.type]
        if not fn or not fn(S, st) then ok = false break end
        if S.stepProp and st.type ~= 'cut' then Util.delete(S.stepProp) S.stepProp = nil end
        if def.ctx and def.ctx.onStep then def.ctx.onStep(i, S) end
    end
    if ok and def.ctx and def.ctx.after then ok = def.ctx.after(S, STEP) ~= false end

    UI.send('ix', false)
    UI.setFocus(false)
    if S.ctx.lid and S.lidPitch and S.lidPitch ~= 0.0 then SetEntityRotation(S.ctx.lid, 0.0, 0.0, S.heading, 2, true) end
    for _, e in ipairs(S.spawned) do Util.delete(e) end
    if S.held and not S.heldScene then Util.delete(S.held) end
    RenderScriptCams(false, true, 350, true, false)
    DestroyCam(S.cam, false)
    FreezeEntityPosition(cache.ped, false)
    LocalPlayer.state:set('nzdeBusy', false, false)
    Interact.active = false
    Main.refreshHud()
    return ok
end

--- helper for `after` callbacks: slide an entity between two points
function Interact.slide(S, ent, from, to, ms)
    local t0 = GetGameTimer()
    while true do
        local k = math.min(1.0, (GetGameTimer() - t0) / ms)
        local q = vec3(lerp(from.x, to.x, k), lerp(from.y, to.y, k), lerp(from.z, to.z, k))
        SetEntityCoordsNoOffset(ent, q.x, q.y, q.z, false, false, false)
        if not frame(S) then return false end
        if k >= 1.0 then return true end
        Wait(0)
    end
end

Interact.anchor = anchor
Interact.spawn = spawn
Interact.hint = hint
