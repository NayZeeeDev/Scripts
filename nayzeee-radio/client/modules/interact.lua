--[[
    NAYZEEE RADIO - Raised radio (client): raise / lower, camera, cursor, clicking the real parts

    Raise brings the radio up in front of the face: an upper-body pose, the body model with
    its separate parts in the hand (held.lua), a scripted camera on the line from the eyes to
    the radio, and the live screen (screen.lua + firmware.lua). There is NO NUI focus: the
    game's own cursor is shown, game controls that would fight it are disabled each frame,
    and every part of the prop is hit-tested by projecting its face (rect = quad, round =
    ellipse) to the screen. The nearest projected centre under the cursor wins.

      NZR.Interact.Raise() → bool       (raise key, /radio, using the item). In an operating seat
                                        of a radio car NZR.Vehicle.Open() gets the key instead -
                                        it must return true when it opened the head unit.
      NZR.Interact.Lower() → bool       (raise key again, right mouse, Esc, and automatically on
                                        death, ragdoll, water (not waterproof), cuffs, vehicles)
      NZR.Interact.IsRaised() → bool    NZR.Interact.Session() → session table | nil
      NZR.Interact.Key(action, value, down)   keyboard route (the key mappings below)

    Mouse: left = press the part under the cursor (arrows / d-pad / knobs repeat after
    Config.Radios.Interact.repeatDelay), knobs turn -1 / +1 from their left / right half or
    with the wheel over them, the wheel elsewhere zooms, the PTT part is hold to talk.
    The d-pad direction comes from where on it the cursor is.

    KEY MAPPINGS (RegisterKeyMapping, hold-style +/- like the user's ATM keypad; inert unless raised)
      +nzr_k0 .. +nzr_k9 ('0'..'9'), +nzr_back (BACK), +nzr_ok (RETURN), +nzr_up / down / left /
      right (arrows), +nzr_star (MULTIPLY)
    NUI SENT     overlay open { hints = { { keys = { 'LMB' }, label } } }, overlay hover { id, action, value, poly = { { x, y } } }
                 (normalised 0..1 screen points, hover {} = nothing under the cursor), overlay close
    STATE        NZR.Radio.SetRaised (nzr_hold.r); the inventory hotbar is off while raised
                 (Bridge.Inv.BlockHotbar: ox_inventory invHotkeys, qb / ps / lj inv_busy)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Interact = NZR.Interact or {}
local I = NZR.Interact

local HEAD_BONE = 31086
local CAM_EASE = 350
local CHECK_MS = 250
local ANIM_CHECK_MS = 600
local HOVER_RESEND_MS = 66
local HOVER_EPS = 0.002
local ZOOM_STEP = 2.0
local PARALLAX_DEG = 2.0
local HIT_PAD = 0.08              -- a little forgiveness around the edge of a key

-- controls disabled every frame while raised: looking, shooting, the weapon wheel and
-- slots (the number row), walking, phone / frontend keys the keypad mappings also use
local BLOCK = {
    0, 1, 2, 3, 4, 5, 6, 14, 15, 16, 17, 18, 21, 22, 23, 24, 25, 26, 30, 31, 32, 33, 34, 35, 36,
    37, 44, 45, 47, 58, 75, 99, 100, 106, 115, 116, 140, 141, 142, 143, 157, 158, 159, 160, 161,
    162, 163, 164, 165, 172, 173, 174, 175, 176, 177, 191, 194, 199, 200, 201, 202, 241, 242,
    257, 261, 262, 263, 264,
}
local REPEATS = { up = true, down = true, left = true, right = true, knob = true }

local session = nil
local raising = false

local function L(key, ...) return NZR.L('client.' .. key, ...) end
local function toast(key, kind) NZR.UI.Toast({ title = L('title'), message = L(key), type = kind or 'info' }) end
local function cfg() return Config.Radios.Interact or {} end

-- ════════════════════════════════════════════════════════════════════════
-- MATHS
-- ════════════════════════════════════════════════════════════════════════

local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function norm(v)
    local l = #v
    if l < 1e-6 then return vector3(0.0, 0.0, 0.0) end
    return v / l
end

-- The body's axes once per frame (4 natives) instead of one native per projected point.
-- Built from offsets so there is no doubt about which axis is which.
local function matrixOf(ent)
    local p = GetOffsetFromEntityInWorldCoords(ent, 0.0, 0.0, 0.0)
    return {
        p = p,
        r = GetOffsetFromEntityInWorldCoords(ent, 1.0, 0.0, 0.0) - p,
        f = GetOffsetFromEntityInWorldCoords(ent, 0.0, 1.0, 0.0) - p,
        u = GetOffsetFromEntityInWorldCoords(ent, 0.0, 0.0, 1.0) - p,
    }
end

local function toWorld(m, o)
    return m.p + m.r * o.x + m.f * o.y + m.u * o.z
end

local function project(p)
    local ok, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
    if not ok then return nil end
    return x, y
end

-- point inside a convex quad (any winding)
local function inQuad(px, py, q)
    local sign = 0
    for i = 1, 4 do
        local a, b = q[i], q[i % 4 + 1]
        local c = (b[1] - a[1]) * (py - a[2]) - (b[2] - a[2]) * (px - a[1])
        if c ~= 0 then
            local s = c > 0 and 1 or -1
            if sign == 0 then sign = s elseif s ~= sign then return false end
        end
    end
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- HIT TESTING
-- ════════════════════════════════════════════════════════════════════════

local function quadOf(m, k, scale)
    local q = {}
    local u, v = k.u * (scale or 1.0), k.v * (scale or 1.0)
    local corners = { k.pos + u + v, k.pos - u + v, k.pos - u - v, k.pos + u - v }
    for i = 1, 4 do
        local x, y = project(toWorld(m, corners[i]))
        if not x then return nil end
        q[i] = { x, y }
    end
    return q
end

-- → { key, s, t, cx, cy } | nil    s / t = the cursor in the part's own u / v frame (-1..1)
local function hitTest(s, mx, my, m)
    local aspect = GetAspectRatio(false)
    local best, bestD = nil, math.huge
    for i = 1, #s.keys do
        local k = s.keys[i]
        local cx, cy = project(toWorld(m, k.pos))
        if cx then
            local ux, uy = project(toWorld(m, k.pos + k.u))
            local vx, vy = project(toWorld(m, k.pos + k.v))
            if ux and vx then
                local ax, ay, bx, by = ux - cx, uy - cy, vx - cx, vy - cy
                local det = ax * by - ay * bx
                if math.abs(det) > 1e-10 then
                    local dx, dy = mx - cx, my - cy
                    local sp = (dx * by - dy * bx) / det
                    local tp = (ax * dy - ay * dx) / det
                    local inside
                    if k.shape == 'round' then
                        inside = sp * sp + tp * tp <= (1.0 + HIT_PAD) ^ 2
                    else
                        -- cheap reject in the part's own frame, then the projected quad decides
                        inside = math.abs(sp) <= 1.3 and math.abs(tp) <= 1.3
                        if inside then
                            local q = quadOf(m, k, 1.0 + HIT_PAD)
                            inside = q ~= nil and inQuad(mx, my, q)
                        end
                    end
                    if inside then
                        local ddx, ddy = dx * aspect, dy
                        local d = ddx * ddx + ddy * ddy
                        if d < bestD then
                            bestD = d
                            best = { key = k, s = sp, t = tp, cx = cx, cy = cy }
                        end
                    end
                end
            end
        end
    end
    return best
end

local function polyOf(m, k)
    local pts = {}
    if k.shape == 'round' then
        for i = 0, 17 do
            local a = i / 18 * math.pi * 2.0
            local x, y = project(toWorld(m, k.pos + k.u * math.cos(a) + k.v * math.sin(a)))
            if not x then return nil end
            pts[#pts + 1] = { x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000 }
        end
    else
        local q = quadOf(m, k, 1.0)
        if not q then return nil end
        for i = 1, 4 do
            pts[i] = { x = math.floor(q[i][1] * 10000 + 0.5) / 10000, y = math.floor(q[i][2] * 10000 + 0.5) / 10000 }
        end
    end
    return pts
end

-- d-pad: where on the part the cursor is, back in the body frame (+X = the viewer's left,
-- +Z = up, SPEC §9.1), whichever way the layout's u / v happen to point
local function quadrant(k, sp, tp)
    local off = k.u * sp + k.v * tp
    if math.abs(off.x) > math.abs(off.z) then return off.x > 0 and 'left' or 'right' end
    return off.z > 0 and 'up' or 'down'
end

-- ════════════════════════════════════════════════════════════════════════
-- CAMERA
-- ════════════════════════════════════════════════════════════════════════

local function updateCamera(s, m, mx, my, snap)
    local lay = s.layout
    local focus = toWorld(m, lay.focus or vector3(0.0, 0.0, 0.0))
    local head = GetPedBoneCoords(s.ped, HEAD_BONE, 0.0, 0.0, 0.0)
    local d = focus - head
    local dir = #d > 0.02 and norm(d) or norm(GetEntityForwardVector(s.ped))
    local camDist = tonumber(lay.camDist) or 0.34
    local pos = focus - dir * camDist
    if cfg().parallax ~= false then
        local right = norm(cross(dir, vector3(0.0, 0.0, 1.0)))
        local up = cross(right, dir)
        local k = math.tan(math.rad(PARALLAX_DEG)) * camDist
        pos = pos + right * ((mx - 0.5) * 2.0 * k) + up * ((0.5 - my) * 2.0 * k)
    end
    if snap or not s.camPos then
        s.camPos, s.camFocus = pos, focus
    else
        -- light smoothing: the idle pose sways the hand, the view should not shake with it
        local kf = 1.0 - math.exp(-GetFrameTime() * 16.0)
        s.camPos = s.camPos + (pos - s.camPos) * kf
        s.camFocus = s.camFocus + (focus - s.camFocus) * kf
    end
    SetCamCoord(s.cam, s.camPos.x, s.camPos.y, s.camPos.z)
    PointCamAtCoord(s.cam, s.camFocus.x, s.camFocus.y, s.camFocus.z)
    SetCamFov(s.cam, s.fov)
end

-- ════════════════════════════════════════════════════════════════════════
-- GUARDS
-- ════════════════════════════════════════════════════════════════════════

local function cuffed(ped)
    if IsPedCuffed(ped) then return true end
    local st = LocalPlayer.state
    if st.handcuffed or st.isCuffed or st.cuffed then return true end
    local pd = Bridge and Bridge.PlayerData and Bridge.PlayerData()
    local md = type(pd) == 'table' and pd.metadata or nil
    return type(md) == 'table' and md.ishandcuffed == true
end

local function inWater(ped, model)
    local m = Config.Radios.Models[model]
    if m and m.waterproof then return false end
    return IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped)
end

local function blockReason(ped, model)
    if NZR.Radio.API.IsDead() then return 'dead' end
    if IsPedRagdoll(ped) then return 'busy' end
    if IsPedInAnyVehicle(ped, true) or GetVehiclePedIsTryingToEnter(ped) ~= 0 then return 'vehicle' end
    if inWater(ped, model) then return 'water' end
    if cuffed(ped) then return 'cuffed' end
    return nil
end

-- the inventory's number-row hotbar would use items with the keypad keys
local function hotbar(block)
    if Bridge and Bridge.Inv and Bridge.Inv.BlockHotbar then pcall(Bridge.Inv.BlockHotbar, 'raised', block) end
end

-- ════════════════════════════════════════════════════════════════════════
-- PRESSING
-- ════════════════════════════════════════════════════════════════════════

local function pressStart(s, hit, now)
    local k = hit.key
    local action, value, step = k.action, k.value, nil
    if action == 'dpad' then
        value = quadrant(k, hit.s, hit.t)
        NZR.Held.Press(k.id, true, value)
    elseif action == 'knob' then
        step = s.mx < hit.cx and -1 or 1
        NZR.Held.Turn(k.id, step)
    else
        NZR.Held.Press(k.id, true)
    end
    if action == 'digit' then value = tostring(value) end
    s.pressed = { key = k, action = action, value = value, step = step, nextRep = now + (tonumber(cfg().repeatDelay) or 450) }
    s.fw:Press(action, value, true, step)
end

local function pressEnd(s)
    local p = s.pressed
    if not p then return end
    s.pressed = nil
    if p.action ~= 'knob' then NZR.Held.Press(p.key.id, false) end
    s.fw:Press(p.action, p.value, false, p.step)
end

local function repeatHeld(s, now)
    local rate = tonumber(cfg().repeatRate) or 120
    local p = s.pressed
    if p and now >= p.nextRep then
        local logical = p.action == 'dpad' and p.value or p.action
        if REPEATS[logical] or REPEATS[p.action] then
            p.nextRep = now + rate
            if p.action == 'knob' then NZR.Held.Turn(p.key.id, p.step) end
            s.fw:Repeat(p.action, p.value, p.step)
        else
            p.nextRep = math.huge
        end
    end
    -- only the newest key repeats, like a keyboard
    local h = s.keyLast and s.keysHeld[s.keyLast]
    if h and REPEATS[h.action] and now >= h.nextRep then
        h.nextRep = now + rate
        s.fw:Repeat(h.action, h.value)
    end
end

local function wheel(s, dir)
    local hit = s.hover
    if hit and hit.key.action == 'knob' then
        NZR.Held.Turn(hit.key.id, dir)
        s.fw:Press('knob', hit.key.value, true, dir)
        s.fw:Press('knob', hit.key.value, false, dir)
        return
    end
    local c = cfg()
    s.fov = math.max(tonumber(c.fovMin) or 22.0, math.min(tonumber(c.fovMax) or 46.0, s.fov - dir * ZOOM_STEP))
end

-- keyboard: which part moves for a logical key (the d-pad stands in for missing arrows)
local function partFor(s, action, value)
    for i = 1, #s.keys do
        local k = s.keys[i]
        if k.action == action and (value == nil or tostring(k.value) == value) then return k, nil end
    end
    if action == 'up' or action == 'down' or action == 'left' or action == 'right' then
        for i = 1, #s.keys do
            if s.keys[i].action == 'dpad' then return s.keys[i], action end
        end
    end
    return nil, nil
end

-- Every key that is down counts (typing fast, the next digit goes down before the last one
-- is up), each one is released on its own.
local function keyUp(s, id)
    local h = s.keysHeld[id]
    if not h then return end
    s.keysHeld[id] = nil
    if s.keyLast == id then s.keyLast = nil end
    if h.key then
        -- a part two held keys move (the d-pad standing in for arrows) comes back with the last
        local still = false
        for _, o in pairs(s.keysHeld) do
            if o.key == h.key then still = true break end
        end
        if not still then NZR.Held.Press(h.key.id, false) end
    end
    s.fw:Press(h.action, h.value, false)
end

local function releaseKeys(s)
    for id in pairs(s.keysHeld) do keyUp(s, id) end
end

function I.Key(action, value, down)
    local s = session
    if not s then return end
    local id = value and (action .. ':' .. value) or action
    if not down then
        keyUp(s, id)
        return
    end
    if IsNuiFocused() or s.keysHeld[id] then return end
    local k, dir = partFor(s, action, value)
    if k then NZR.Held.Press(k.id, true, dir) end
    s.keysHeld[id] = { action = action, value = value, key = k, nextRep = GetGameTimer() + (tonumber(cfg().repeatDelay) or 450) }
    s.keyLast = id
    s.fw:Press(action, value, true)
end

local KEYMAP = {
    { 'k0', '0', 'digit', '0' }, { 'k1', '1', 'digit', '1' }, { 'k2', '2', 'digit', '2' },
    { 'k3', '3', 'digit', '3' }, { 'k4', '4', 'digit', '4' }, { 'k5', '5', 'digit', '5' },
    { 'k6', '6', 'digit', '6' }, { 'k7', '7', 'digit', '7' }, { 'k8', '8', 'digit', '8' },
    { 'k9', '9', 'digit', '9' }, { 'back', 'BACK', 'back' }, { 'ok', 'RETURN', 'ok' },
    { 'up', 'UP', 'up' }, { 'down', 'DOWN', 'down' }, { 'left', 'LEFT', 'left' },
    { 'right', 'RIGHT', 'right' }, { 'star', 'MULTIPLY', 'star' },
}

-- RegisterKeyMapping binds by the key's real name, so '0' is the 0 key on every build
-- (the number row's control ids are not); players can rebind them in the FiveM settings.
for _, km in ipairs(KEYMAP) do
    local id, key, action, value = km[1], km[2], km[3], km[4]
    RegisterCommand('+nzr_' .. id, function() I.Key(action, value, true) end, false)
    RegisterCommand('-nzr_' .. id, function() I.Key(action, value, false) end, false)
    RegisterKeyMapping('+nzr_' .. id, L('key_pad_' .. id), 'keyboard', key)
end

CreateThread(function()
    Wait(1000)
    for _, km in ipairs(KEYMAP) do
        TriggerEvent('chat:removeSuggestion', '/+nzr_' .. km[1])
        TriggerEvent('chat:removeSuggestion', '/-nzr_' .. km[1])
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- HOVER OUTLINE
-- ════════════════════════════════════════════════════════════════════════

local function sendHover(s, m, now)
    if cfg().highlight == false then return end
    local hit = s.hover
    local id = hit and hit.key.id or nil
    if id ~= s.hoverId then
        s.hoverId, s.hoverAt, s.hoverPoly = id, 0, nil
        if not id then
            NZR.UI.Send('overlay', 'hover', {})
            return
        end
    end
    if not id or now - s.hoverAt < HOVER_RESEND_MS then return end
    s.hoverAt = now
    local poly = polyOf(m, hit.key)
    if not poly then return end
    local old = s.hoverPoly
    if old and #old == #poly and math.abs(old[1].x - poly[1].x) < HOVER_EPS and math.abs(old[1].y - poly[1].y) < HOVER_EPS then
        return
    end
    s.hoverPoly = poly
    -- action/value let the overlay name the part by what it does (the MX-905's kup is Menu)
    NZR.UI.Send('overlay', 'hover', { id = id, action = hit.key.action, value = hit.key.value, poly = poly })
end

local function hints()
    return {
        { keys = { 'LMB' }, label = L('hint_press') },
        { keys = { 'RMB', 'ESC' }, label = L('hint_lower') },
        { keys = { NZR.Radio.KeyName('ptt') or 'CAPITAL' }, label = L('hint_talk') },
        { keys = { 'WHEEL' }, label = L('hint_zoom') },
        { keys = { '0-9' }, label = L('hint_keypad') },
        { keys = { 'ARROWS' }, label = L('hint_arrows') },
        { keys = { L('hint_knob_key') }, label = L('hint_power') },
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- SESSION
-- ════════════════════════════════════════════════════════════════════════

local function shouldLower(s, ped)
    local S = NZR.Radio.State
    if S.model ~= s.model then return true end
    if ped ~= s.ped or not DoesEntityExist(s.body) then return true end
    return blockReason(ped, s.model) ~= nil
end

local function loop()
    CreateThread(function()
        local nextCheck, nextAnim = 0, 0
        while session do
            local s = session
            local ped = PlayerPedId()
            local now = GetGameTimer()
            if now >= nextCheck then
                nextCheck = now + CHECK_MS
                if shouldLower(s, ped) then
                    I.Lower()
                    break
                end
            end
            if IsPauseMenuActive() then
                -- Esc reaches the pause menu above the control system: close it, take it as "lower"
                SetPauseMenuActive(false)
                I.Lower()
                break
            end

            for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end
            SetMouseCursorActiveThisFrame()

            local m = matrixOf(s.body)
            s.mx = GetDisabledControlNormal(2, 239)
            s.my = GetDisabledControlNormal(2, 240)
            updateCamera(s, m, s.mx, s.my, false)

            -- A press ends when its button is up, or when another resource's window (an inventory ...)
            -- takes the mouse and keyboard: their releases go to that window and never reach us.
            local focused = IsNuiFocused()
            if s.pressed and (focused or not IsDisabledControlPressed(0, 24)) then pressEnd(s) end
            if focused and next(s.keysHeld) then releaseKeys(s) end

            -- while that window is open: keep the view, ignore clicks
            if not focused then
                if not s.pressed then s.hover = hitTest(s, s.mx, s.my, m) end
                sendHover(s, m, now)

                if IsDisabledControlJustPressed(0, 24) and s.hover then pressStart(s, s.hover, now) end
                repeatHeld(s, now)
                if IsDisabledControlJustPressed(0, 241) then wheel(s, 1) end
                if IsDisabledControlJustPressed(0, 242) then wheel(s, -1) end
                if IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 200) then
                    I.Lower()
                    break
                end
            end
            SetMouseCursorSprite(s.pressed and 4 or (s.hover and 3 or 1))

            if now >= nextAnim then
                nextAnim = now + ANIM_CHECK_MS
                local a = cfg().anim
                if a and a.dict and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
                    local ok, token = NZR.Anim.Play(ped, a.dict, a.clip, { flag = 49 })
                    if ok then s.animToken = token end
                end
            end
            Wait(0)
        end
    end)
end

local function start(model)
    local lay = PropsLayout and PropsLayout[model]
    if type(lay) ~= 'table' then return end
    local body = NZR.Held.Raise(model)
    if not body then
        toast('raise_unavailable', 'error')
        return
    end
    local ped = PlayerPedId()
    local c = cfg()
    local keys = {}
    for _, k in ipairs(lay.keys or {}) do
        if k.id and k.pos and k.u and k.v and k.action then keys[#keys + 1] = k end
    end
    local s = {
        model = model, layout = lay, body = body, ped = ped, keys = keys,
        fov = tonumber(c.fov) or 34.0, mx = 0.5, my = 0.5, keysHeld = {}, keyLast = nil,
        radarHidden = IsRadarHidden(), fw = NZR.Firmware.Handheld(),
    }
    local a = c.anim
    if a and a.dict then
        local ok, token = NZR.Anim.Play(ped, a.dict, a.clip, { flag = 49 })
        if ok then s.animToken = token end
    end
    session = s
    NZR.Radio.SetRaised(true)

    s.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamNearClip(s.cam, 0.01)
    SetCamFov(s.cam, s.fov)
    updateCamera(s, matrixOf(body), 0.5, 0.5, true)
    SetCamActive(s.cam, true)
    RenderScriptCams(true, true, CAM_EASE, true, true)
    if c.hideRadar ~= false then DisplayRadar(false) end

    NZR.Screen.Attach(model)
    s.fw:SetActive(true)
    NZR.UI.Open('overlay', { hints = hints() }, { focus = false })
    hotbar(true)
    loop()
end

function I.Raise()
    if session or raising then return true end
    local S = NZR.Radio.State
    if not S.ready then return false end
    if NZR.UI.IsOpen('headunit') then return false end
    -- placing or hacking a jammer owns the camera, the pose and the keys
    if NZR.Jammers and NZR.Jammers.IsBusy and NZR.Jammers.IsBusy() then return false end
    if NZR.Vehicle and NZR.Vehicle.Open then
        local ok, opened = pcall(NZR.Vehicle.Open)
        if ok and opened then return true end
    end
    if not S.model then
        toast('no_radio', 'error')
        return false
    end
    local why = blockReason(PlayerPedId(), S.model)
    if why then
        if why == 'vehicle' then toast('not_in_vehicle', 'error')
        elseif why == 'water' then toast('raise_water', 'error')
        elseif why == 'cuffed' then toast('raise_cuffed', 'error') end
        return false
    end
    if not NZR.Held.Available(S.model) then
        toast('raise_unavailable', 'error')
        return false
    end
    raising = true
    CreateThread(function()
        local ok, err = pcall(start, S.model)
        raising = false
        if not ok then
            NZR.Warn('raising the radio failed: ' .. tostring(err))
            I.Lower()
        end
    end)
    return true
end

function I.Lower()
    local s = session
    if not s then
        NZR.Held.Lower()
        return false
    end
    session = nil
    if s.pressed then pressEnd(s) end
    releaseKeys(s)
    s.fw:SetActive(false)
    NZR.Screen.Detach(s.model)
    NZR.UI.Send('overlay', 'hover', {})
    NZR.UI.Close('overlay')
    if s.cam then
        local cam = s.cam
        RenderScriptCams(false, true, CAM_EASE, true, true)
        SetTimeout(CAM_EASE + 100, function()
            if DoesCamExist(cam) then DestroyCam(cam, false) end
        end)
    end
    if cfg().hideRadar ~= false then DisplayRadar(not s.radarHidden) end
    if s.animToken then NZR.Anim.Stop(PlayerPedId(), { token = s.animToken }) end
    NZR.Held.Lower()
    hotbar(false)
    SetMouseCursorSprite(1)
    NZR.Radio.SetRaised(false)
    return true
end

function I.IsRaised()
    return session ~= nil
end

function I.Session()
    return session
end

NZR.Bus.On('radio:changed', function(what)
    if (what == 'dropped' or what == 'reset') and session then I.Lower() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    local s = session
    session = nil
    if not s then return end
    if s.cam then
        RenderScriptCams(false, false, 0, true, true)
        if DoesCamExist(s.cam) then DestroyCam(s.cam, false) end
    end
    if cfg().hideRadar ~= false then DisplayRadar(not s.radarHidden) end
    hotbar(false)
    if s.animToken then NZR.Anim.Stop(PlayerPedId(), { token = s.animToken, immediate = false }) end
end)
