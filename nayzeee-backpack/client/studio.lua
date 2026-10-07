-----------------------------------------------------------------
-- Backpack studio  (/bagtune, admin only)
--
-- FIT    character-relative move + rotate pads, carry presets, the
--        right bone list, raw values, live pose preview, Save.
-- LOOK   variants, live storage / price editing, carry style, anims.
-- ICON   see client/icons.lua
--
-- Why rotation used to feel broken: these props are converted from
-- clothing, so their pivot sits at the old skeleton origin, often
-- 30-50cm from the mesh. Rotating around that pivot swings the bag
-- in a big arc. Everything here rotates around the MESH centre and
-- writes the matching pivot offset back, so the bag turns in place.
--
-- On open the studio probes how GTA applies attach rotations (one
-- two-frame test). With that it can turn the bag around the
-- character's own axes and swap bones without the bag jumping.
-- If the probe ever fails it falls back to measuring in-game, which
-- needs no maths assumptions at all.
-----------------------------------------------------------------

Studio = { open = false }

if not Config.Studio or not Config.Studio.enabled then return end

local open = false
local preview, previewHash = nil, nil
local centre, mn, mx = vector3(0, 0, 0), vector3(0, 0, 0), vector3(0, 0, 0)
local helper = nil
local currentKey, variantId = nil, nil
local poseKey = nil
local calib = nil          -- { order, sign, swap } or false when the probe failed
local queue = {}

local tune = { bone = 24818, pos = { x = 0, y = 0, z = 0 }, rot = { x = 0, y = 0, z = 0 } }

-- camera, orbit is relative to the ped so "behind" stays behind
local cam = nil
local camWant = { yaw = 180.0, elev = 8.0, dist = 1.9, focus = 1.0 }
local camNow  = { yaw = 180.0, elev = 8.0, dist = 1.9, focus = 1.0 }
local camHold = nil        -- saved camWant while an anim test swings round

local BONES = {
    { id = 24818, label = 'Spine 3 · upper back',      group = 'Back' },
    { id = 24817, label = 'Spine 2 · mid back',        group = 'Back' },
    { id = 24816, label = 'Spine 1 · lower back',      group = 'Back' },
    { id = 23553, label = 'Spine 0 · waist',           group = 'Back' },
    { id = 57597, label = 'Spine root',                group = 'Back' },
    { id = 11816, label = 'Pelvis · hips',             group = 'Body' },
    { id = 0,     label = 'Ped root',                  group = 'Body' },
    { id = 39317, label = 'Neck',                      group = 'Body' },
    { id = 31086, label = 'Head',                      group = 'Body' },
    { id = 10706, label = 'Right clavicle · shoulder', group = 'Right arm' },
    { id = 40269, label = 'Right upper arm',           group = 'Right arm' },
    { id = 28252, label = 'Right forearm',             group = 'Right arm' },
    { id = 57005, label = 'Right hand',                group = 'Right arm' },
    { id = 28422, label = 'Right hand (prop point)',   group = 'Right arm' },
    { id = 64729, label = 'Left clavicle · shoulder',  group = 'Left arm' },
    { id = 45509, label = 'Left upper arm',            group = 'Left arm' },
    { id = 61163, label = 'Left forearm',              group = 'Left arm' },
    { id = 18905, label = 'Left hand',                 group = 'Left arm' },
    { id = 60309, label = 'Left hand (prop point)',    group = 'Left arm' },
    { id = 51826, label = 'Right thigh',               group = 'Legs' },
    { id = 58271, label = 'Left thigh',                group = 'Legs' },
}

-- Placement presets, in CHARACTER terms (right / forward / up from the bone),
-- so they land in the same spot whatever the bag's pivot is.
--   yaw   turns the bag about the character's up axis (90 = face out to the right)
--   hang  the top of the bag hangs from that point instead of its centre
--   along metres along the bone itself (forearm: elbow -> wrist)
local PRESETS = {
    { key = 'back',       label = 'Back',          bone = 24818, at = { r = 0.0,   f = -0.16, u = -0.14 }, yaw = 0 },
    { key = 'back_low',   label = 'Low back',      bone = 24816, at = { r = 0.0,   f = -0.15, u = 0.00 },  yaw = 0 },
    { key = 'front',      label = 'Chest',         bone = 24818, at = { r = 0.0,   f = 0.17,  u = -0.12 }, yaw = 180 },
    { key = 'hip_r',      label = 'Right hip',     bone = 11816, at = { r = 0.21,  f = 0.02,  u = 0.02 },  yaw = 90 },
    { key = 'hip_l',      label = 'Left hip',      bone = 11816, at = { r = -0.21, f = 0.02,  u = 0.02 },  yaw = -90 },
    { key = 'shoulder_r', label = 'R shoulder',    bone = 10706, at = { r = 0.14,  f = 0.0,   u = -0.42 }, yaw = 90 },
    { key = 'shoulder_l', label = 'L shoulder',    bone = 64729, at = { r = -0.14, f = 0.0,   u = -0.42 }, yaw = -90 },
    { key = 'hand_r',     label = 'Right hand',    bone = 57005, at = { r = 0.0,   f = 0.02,  u = -0.03 }, yaw = 90,  hang = true },
    { key = 'hand_l',     label = 'Left hand',     bone = 18905, at = { r = 0.0,   f = 0.02,  u = -0.03 }, yaw = -90, hang = true },
    { key = 'forearm_r',  label = 'R forearm',     bone = 28252, at = { r = 0.0,   f = 0.0,   u = 0.0 },   yaw = 90,  hang = true, along = 0.10 },
    { key = 'forearm_l',  label = 'L forearm',     bone = 61163, at = { r = 0.0,   f = 0.0,   u = 0.0 },   yaw = -90, hang = true, along = 0.10 },
}

local CAMS = {
    back  = { yaw = 180.0, elev = 8.0 },
    left  = { yaw = 90.0,  elev = 6.0 },
    right = { yaw = -90.0, elev = 6.0 },
    front = { yaw = 0.0,   elev = 6.0 },
    top   = { yaw = 160.0, elev = 55.0 },
}

-----------------------------------------------------------------
-- euler maths (only used once calibrated)
-----------------------------------------------------------------

local AXFN = { x = M3.rx, y = M3.ry, z = M3.rz }
local PERMS = {
    { 'x', 'y', 'z' }, { 'x', 'z', 'y' }, { 'y', 'x', 'z' },
    { 'y', 'z', 'x' }, { 'z', 'x', 'y' }, { 'z', 'y', 'x' },
}

local function eulerM(rot, conv)
    local o, s = conv.order, conv.sign
    local m = AXFN[o[1]](rot[o[1]] * s[o[1]])
    m = M3.mul(m, AXFN[o[2]](rot[o[2]] * s[o[2]]))
    return M3.mul(m, AXFN[o[3]](rot[o[3]] * s[o[3]]))
end

local I3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

--- Full attach rotation: optional constant pre/post terms around the euler part.
local function attachM(rot)
    return M3.mul(M3.mul(calib.L or I3, eulerM(rot, calib)), calib.R or I3)
end

local function solve3(A, b)
    local det = A[1] * (A[5] * A[9] - A[6] * A[8]) - A[2] * (A[4] * A[9] - A[6] * A[7]) + A[3] * (A[4] * A[8] - A[5] * A[7])
    if math.abs(det) < 1e-18 then return nil end
    local function d(c1, c2, c3)
        return c1[1] * (c2[2] * c3[3] - c3[2] * c2[3]) - c2[1] * (c1[2] * c3[3] - c3[2] * c1[3]) + c3[1] * (c1[2] * c2[3] - c2[2] * c1[3])
    end
    local col1, col2, col3 = { A[1], A[4], A[7] }, { A[2], A[5], A[8] }, { A[3], A[6], A[9] }
    return d(b, col2, col3) / det, d(col1, b, col3) / det, d(col1, col2, b) / det
end

--- Euler angles (degrees) that produce matrix T under the calibrated convention.
local function solveEuler(T, seed)
    T = M3.mul(M3.mul(M3.t(calib.L or I3), T), M3.t(calib.R or I3))
    local KEYS = { 'x', 'y', 'z' }
    local seeds = {
        seed, { x = 0, y = 0, z = 0 }, { x = 90, y = 0, z = 0 }, { x = -90, y = 0, z = 0 },
        { x = 0, y = 90, z = 0 }, { x = 0, y = -90, z = 0 }, { x = 0, y = 0, z = 90 },
        { x = 0, y = 0, z = -90 }, { x = 180, y = 0, z = 0 }, { x = 0, y = 0, z = 180 },
    }

    local best, bestErr = nil, math.huge
    for _, s0 in ipairs(seeds) do
        local th = { x = s0.x, y = s0.y, z = s0.z }
        local cost = M3.err(eulerM(th, calib), T)
        local lambda = 1e-3

        for _ = 1, 60 do
            if cost < 1e-12 then break end
            local E = eulerM(th, calib)
            local J = {}
            for k, key in ipairs(KEYS) do
                local t2 = { x = th.x, y = th.y, z = th.z }
                t2[key] = t2[key] + 0.05
                local Ek = eulerM(t2, calib)
                J[k] = {}
                for i = 1, 9 do J[k][i] = (Ek[i] - E[i]) / 0.05 end
            end
            local JTJ, JTr = {}, {}
            for a = 1, 3 do
                local acc = 0.0
                for i = 1, 9 do acc = acc + J[a][i] * (E[i] - T[i]) end
                JTr[a] = -acc
                for b = 1, 3 do
                    local v = 0.0
                    for i = 1, 9 do v = v + J[a][i] * J[b][i] end
                    JTJ[(a - 1) * 3 + b] = v
                end
            end
            for a = 1, 3 do JTJ[(a - 1) * 3 + a] = JTJ[(a - 1) * 3 + a] * (1 + lambda) + 1e-12 end
            local dx, dy, dz = solve3(JTJ, JTr)
            if not dx then break end
            local cand = { x = th.x + dx, y = th.y + dy, z = th.z + dz }
            local c2 = M3.err(eulerM(cand, calib), T)
            if c2 < cost then th, cost, lambda = cand, c2, lambda * 0.3 else lambda = lambda * 10 end
            if lambda > 1e8 then break end
        end

        if cost < bestErr then best, bestErr = th, cost end
        if bestErr < 1e-10 then break end
    end

    if not best then return nil end
    return { x = Util.wrap180(best.x), y = Util.wrap180(best.y), z = Util.wrap180(best.z) }, bestErr
end

-----------------------------------------------------------------
-- reading the game
-----------------------------------------------------------------

--- right, forward, up, pos of an entity, honouring the probed return order.
local function axes(entity)
    local a, b, u, p = GetEntityMatrix(entity)
    if calib and calib.swap then return a, b, u, p end
    return b, a, u, p -- GetEntityMatrix returns forward, right, up, pos
end

local function boneFrame()
    local r, f, u, p = axes(helper)
    return M3.fromAxes(r, f, u), p, r, f, u
end

local function propFrame()
    local r, f, u, p = axes(preview)
    return M3.fromAxes(r, f, u), p
end

local function toBone(B, v) return M3.apply(M3.t(B), v) end

--- World position of the mesh centre right now.
local function centreWorld()
    local P, p = propFrame()
    return p + M3.apply(P, centre)
end

local function vec(t) return vector3(t.x, t.y, t.z) end
local function tbl(v, dec)
    return { x = Util.round(v.x, dec or 4), y = Util.round(v.y, dec or 4), z = Util.round(v.z, dec or 4) }
end

local function attachPreview()
    if not preview or not DoesEntityExist(preview) then return end
    Util.attach(preview, PlayerPedId(), tune.bone, tune.pos, tune.rot)
end

local function attachHelper(bone)
    if not helper or not DoesEntityExist(helper) then return end
    Util.attach(helper, PlayerPedId(), bone, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
end

-----------------------------------------------------------------
-- calibration
-----------------------------------------------------------------

local function calibrate()
    local probes = {
        { pos = { x = 0.11, y = 0.23, z = -0.17 }, rot = { x = 17, y = 41, z = 73 } },
        { pos = { x = -0.07, y = 0.05, z = 0.19 }, rot = { x = -63, y = 22, z = 128 } },
        { pos = { x = 0.02, y = -0.09, z = 0.06 }, rot = { x = 0, y = 0, z = 0 } },
    }
    local ped = PlayerPedId()
    local samples = {}

    attachHelper(tune.bone)
    for i, pr in ipairs(probes) do
        Util.attach(preview, ped, tune.bone, pr.pos, pr.rot)
        Wait(0); Wait(0)
        local f1, r1, u1, p1 = GetEntityMatrix(preview)
        local f2, r2, u2, p2 = GetEntityMatrix(helper)
        samples[i] = { f1 = f1, r1 = r1, u1 = u1, p1 = p1, f2 = f2, r2 = r2, u2 = u2, p2 = p2 }
    end

    -- which way round does GetEntityMatrix hand back forward/right?
    local function relFor(s, swap)
        local pr, pf = s.f1, s.r1
        local br, bf = s.f2, s.r2
        if not swap then pr, pf, br, bf = s.r1, s.f1, s.r2, s.f2 end
        local P = M3.fromAxes(pr, pf, s.u1)
        local B = M3.fromAxes(br, bf, s.u2)
        return M3.mul(M3.t(B), P), M3.apply(M3.t(B), s.p1 - s.p2)
    end

    local chosen, posErr = nil, math.huge
    for _, swap in ipairs({ false, true }) do
        local e = 0.0
        for i, s in ipairs(samples) do
            local _, o = relFor(s, swap)
            e = e + #(o - vec(probes[i].pos))
        end
        if e < posErr then chosen, posErr = swap, e end
    end

    if posErr > 0.03 then
        print(('^3[nayzeee-backpack] studio: position probe off by %.3f, using measured mode^0'):format(posErr))
        return false
    end

    local mats = {}
    for i, s in ipairs(samples) do mats[i] = relFor(s, chosen) end

    -- the zero-rotation probe tells us about any constant twist the game
    -- adds; try it as nothing, as a pre-rotation, and as a post-rotation
    local zero = mats[3]
    local wraps = { { L = nil, R = nil }, { L = zero, R = nil }, { L = nil, R = zero } }

    local best, bestErr = nil, math.huge
    for _, w in ipairs(wraps) do
        for _, order in ipairs(PERMS) do
            for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
                local conv = { order = order, sign = { x = sx, y = sy, z = sz }, L = w.L, R = w.R }
                local e = 0.0
                for i = 1, 2 do
                    local m = M3.mul(M3.mul(w.L or I3, eulerM(probes[i].rot, conv)), w.R or I3)
                    e = e + M3.err(m, mats[i])
                end
                if e < bestErr then best, bestErr = conv, e end
            end end end
        end
    end

    if bestErr > 0.02 then
        print(('^3[nayzeee-backpack] studio: rotation probe error %.4f, using measured mode^0'):format(bestErr))
        return false
    end

    best.swap = chosen
    Bags.debug(('studio calibrated: order %s%s%s, err %.6f'):format(best.order[1], best.order[2], best.order[3], bestErr))
    return best
end

-----------------------------------------------------------------
-- operations (all run on the studio thread, in order)
-----------------------------------------------------------------

local function run(fn) queue[#queue + 1] = fn end

local push -- forward

--- Change rotation, keeping the mesh centre exactly where it is.
local function setRotation(newRot)
    if calib then
        local cb = vec(tune.pos) + M3.apply(attachM(tune.rot), centre)
        tune.rot = newRot
        tune.pos = tbl(cb - M3.apply(attachM(newRot), centre))
        attachPreview()
    else
        local before = centreWorld()
        tune.rot = newRot
        attachPreview()
        Wait(0)
        local B = boneFrame()
        tune.pos = tbl(vec(tune.pos) + toBone(B, before - centreWorld()))
        attachPreview()
    end
end

local PED_AXIS = { yaw = 'u', pitch = 'r', roll = 'f' }
local RAW_AXIS = { yaw = 'z', pitch = 'x', roll = 'y' }

local function rotateBy(which, deg)
    if calib then
        local ped = PlayerPedId()
        local pf, pr, pu = GetEntityMatrix(ped)
        if calib.swap then pf, pr = pr, pf end
        local axis = ({ r = pr, f = pf, u = pu })[PED_AXIS[which]]

        local B, bp = boneFrame()
        local P = propFrame()
        local cw = centreWorld()
        local Pn = M3.mul(M3.axis(axis, deg), P)
        local Mn = M3.mul(M3.t(B), Pn)
        local rot = solveEuler(Mn, tune.rot)
        if not rot then return end

        tune.rot = tbl(rot, 3)
        tune.pos = tbl(toBone(B, cw - bp) - M3.apply(attachM(tune.rot), centre))
        attachPreview()
    else
        local r = { x = tune.rot.x, y = tune.rot.y, z = tune.rot.z }
        local k = RAW_AXIS[which]
        r[k] = Util.wrap180(r[k] + deg)
        setRotation(r)
    end
end

--- Move along the character's right / forward / up.
local function moveBy(which, amount)
    local ped = PlayerPedId()
    local pf, pr, pu = GetEntityMatrix(ped)
    if calib and calib.swap then pf, pr = pr, pf end
    local axis = ({ r = pr, f = pf, u = pu })[which]
    local B = boneFrame()
    tune.pos = tbl(vec(tune.pos) + toBone(B, axis * amount))
    attachPreview()
end

--- Switch bone without the bag moving in the world.
local function setBone(bone)
    if bone == tune.bone then return end
    local cw = centreWorld()
    local P = propFrame()

    attachHelper(bone)
    Wait(0); Wait(0)
    local B, bp = boneFrame()
    tune.bone = bone

    if calib then
        local rot = solveEuler(M3.mul(M3.t(B), P), tune.rot)
        if rot then tune.rot = tbl(rot, 3) end
        tune.pos = tbl(toBone(B, cw - bp) - M3.apply(attachM(tune.rot), centre))
        attachPreview()
    else
        tune.pos = { x = 0, y = 0, z = 0 }
        attachPreview()
        Wait(0); Wait(0)
        local u = toBone(B, centreWorld() - bp)
        tune.pos = tbl(toBone(B, cw - bp) - u)
        attachPreview()
    end
end

local function applyPreset(key)
    local pre
    for _, p in ipairs(PRESETS) do if p.key == key then pre = p end end
    if not pre then return end

    local ped = PlayerPedId()
    attachHelper(pre.bone)
    Wait(0); Wait(0)
    tune.bone = pre.bone

    local B, bp, br = boneFrame()
    local pf, pr, pu = GetEntityMatrix(ped)
    if calib and calib.swap then pf, pr = pr, pf end

    local at = pre.at or {}
    local point = bp + pr * (at.r or 0.0) + pf * (at.f or 0.0) + pu * (at.u or 0.0)
    if pre.along then point = point + br * pre.along end
    if pre.hang then point = point - vector3(0.0, 0.0, mx.z - centre.z) end

    if calib then
        local pedM = M3.fromAxes(pr, pf, pu)
        local want = M3.mul(M3.axis(pu, pre.yaw or 0.0), pedM)
        local rot = solveEuler(M3.mul(M3.t(B), want), tune.rot)
        if rot then tune.rot = tbl(rot, 3) end
        tune.pos = tbl(toBone(B, point - bp) - M3.apply(attachM(tune.rot), centre))
        attachPreview()
    else
        tune.pos = { x = 0, y = 0, z = 0 }
        attachPreview()
        Wait(0); Wait(0)
        local u = toBone(B, centreWorld() - bp)
        tune.pos = tbl(toBone(B, point - bp) - u)
        attachPreview()
    end
end

local function loadTune(bone, pos, rot)
    tune.bone = bone
    tune.pos = tbl(pos)
    tune.rot = tbl(rot, 3)
    attachHelper(bone)
    attachPreview()
end

-----------------------------------------------------------------
-- preview prop
-----------------------------------------------------------------

local function destroyPreview()
    Util.delete(preview)
    preview, previewHash = nil, nil
end

local function spawnPreview(key, variant, keepTune)
    destroyPreview()
    if not Bags.exists(key) then return false end

    local ped = PlayerPedId()
    local entity, hash = Util.spawnBag(key, variant, GetEntityCoords(ped))
    if not entity then return false end

    preview, previewHash = entity, hash
    centre, mn, mx = Util.modelCentre(hash)
    currentKey, variantId = key, variant

    if not keepTune then
        local bone, pos, rot = Bags.offset(key)
        tune.bone, tune.pos, tune.rot = bone, tbl(pos), tbl(rot, 3)
    end
    attachHelper(tune.bone)
    attachPreview()
    return true
end

--- Purses get fitted in the pose they're carried in, so start it by itself.
local function autoPose(key)
    Carry.stopPreview()
    poseKey = nil
    local pose = Bags.poseFor(key)
    if pose and Carry.preview(pose.key) then poseKey = pose.key end
end

local function ensureHelper()
    if helper and DoesEntityExist(helper) then return true end
    local hash = Util.loadModel(`prop_golf_ball`, true)
    if not hash then return false end
    local c = GetEntityCoords(PlayerPedId())
    helper = CreateObject(hash, c.x, c.y, c.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(helper, false, false)
    SetEntityVisible(helper, false, false)
    SetEntityAlpha(helper, 0, false)
    return true
end

-----------------------------------------------------------------
-- camera
-----------------------------------------------------------------

local function camTarget()
    local ped = PlayerPedId()
    local chest = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.35)
    if not preview or not DoesEntityExist(preview) then return chest end
    local bag = centreWorld()
    return chest + (bag - chest) * camNow.focus
end

local function updateCam(dt)
    if not cam then return end
    local k = math.min(1.0, (dt or 0.016) * 9.0)
    local dyaw = Util.wrap180(camWant.yaw - camNow.yaw)
    camNow.yaw = camNow.yaw + dyaw * k
    camNow.elev = camNow.elev + (camWant.elev - camNow.elev) * k
    camNow.dist = camNow.dist + (camWant.dist - camNow.dist) * k
    camNow.focus = camNow.focus + (camWant.focus - camNow.focus) * k

    local target = camTarget()
    local yaw = math.rad(GetEntityHeading(PlayerPedId()) + camNow.yaw)
    local el = math.rad(camNow.elev)
    local d = camNow.dist
    SetCamCoord(cam,
        target.x - math.sin(yaw) * math.cos(el) * d,
        target.y + math.cos(yaw) * math.cos(el) * d,
        target.z + math.sin(el) * d)
    PointCamAtCoord(cam, target.x, target.y, target.z)
end

local function startCam()
    if cam then return end
    local c = GetEntityCoords(PlayerPedId())
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.x, c.y + 2.0, c.z, 0.0, 0.0, 0.0, 40.0, false, 0)
    camNow = { yaw = camWant.yaw, elev = camWant.elev, dist = camWant.dist, focus = camWant.focus }
    updateCam(1.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
end

local function stopCam()
    if not cam then return end
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(cam, false)
    cam = nil
end

function Studio.pauseCam(paused)
    if not cam then return end
    if paused then SetCamActive(cam, false) else SetCamActive(cam, true); RenderScriptCams(true, false, 0, true, true) end
end

-- swing round to watch an anim test, then go back
AddEventHandler('nayzeee-backpack:client:animStart', function()
    if not open then return end
    camHold = { yaw = camWant.yaw, elev = camWant.elev, dist = camWant.dist, focus = camWant.focus }
    camWant.yaw, camWant.elev, camWant.focus = 25.0, 6.0, 0.0
    camWant.dist = math.max(camWant.dist, 2.2)
end)

AddEventHandler('nayzeee-backpack:client:animEnd', function()
    if not open or not camHold then return end
    camWant = camHold
    camHold = nil
end)

-----------------------------------------------------------------
-- NUI payload
-----------------------------------------------------------------

local isAdmin = false

local function payload()
    local bags = {}
    for _, key in ipairs(Bags.keys()) do
        local bag = Bags.def(key)
        local storage = Bags.storage(key)
        local vars = {}
        for _, v in ipairs(Bags.variants(key)) do
            vars[#vars + 1] = { id = v.id, label = v.label, model = v.model, texture = v.texture }
        end
        local _, styleKey = Bags.carryStyle(key)
        local ov = Bags.getOverrides()[key]
        bags[#bags + 1] = {
            key = key, label = Bags.label(key), model = bag.model,
            category = bag.category or 'backpack', theme = bag.theme,
            slots = storage.slots, weight = storage.weight, price = Bags.price(key),
            variants = vars, carry = styleKey,
            pose = (ov and ov.pose) or bag.pose,
            tuned = (bag.offset ~= nil) or (ov and ov.offset ~= nil) or false,
            saved = ov ~= nil,
            job = Bags.jobs(key) and table.concat(Bags.jobs(key), ', ') or nil,
        }
    end

    local styles = { { key = 'none', label = 'Worn (no pose)' } }
    for k, s in pairs(Config.Carry and Config.Carry.Styles or {}) do
        styles[#styles + 1] = { key = k, label = s.label or k }
    end

    local poses = {}
    for _, p in ipairs(Config.Carry and Config.Carry.Poses or {}) do
        poses[#poses + 1] = { key = p.key, label = p.label }
    end

    return {
        bags = bags, bones = BONES, presets = PRESETS, styles = styles, poses = poses,
        current = currentKey, variant = variantId, pose = poseKey,
        tune = tune, calibrated = calib and true or false,
        cam = camWant, admin = isAdmin,
        icon = Icons and Icons.state() or nil,
    }
end

push = function(action)
    SendNUIMessage({ action = action or 'studioRefresh', data = payload() })
end

local function pushTune()
    SendNUIMessage({ action = 'studioTune', data = { tune = tune } })
end

-----------------------------------------------------------------
-- open / close + the studio thread
-----------------------------------------------------------------

local function studioLoop()
    local last = GetGameTimer()
    while open do
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        last = now

        if #queue > 0 then
            local job = table.remove(queue, 1)
            local ok, err = pcall(job)
            if not ok then print('^1[nayzeee-backpack] studio: ' .. tostring(err) .. '^0') end
        end

        if not (Icons and Icons.active()) then
            HideHudAndRadarThisFrame()
            updateCam(dt)
        end

        Wait(0)
    end
end

local function close()
    if not open then return end
    open = false
    Studio.open = false
    queue = {}

    if Icons then Icons.stop() end
    Carry.stopPreview()
    poseKey = nil
    stopCam()
    destroyPreview()
    Util.delete(helper)
    helper = nil

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    if SetWornPropVisible then SetWornPropVisible(true) end
    Carry.suspended = false

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'studioClose' })
end

local function openStudio()
    if open then return close() end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        return Config.Notify('Get out of the vehicle first.', 'error')
    end

    isAdmin = lib.callback.await('nayzeee-backpack:isAdmin', false)
    if not isAdmin then return Config.Notify(Strings.no_admin, 'error') end

    local keys = Bags.keys()
    if #keys == 0 then return Config.Notify('No backpacks defined in Config.Backpacks.', 'error') end

    if not ensureHelper() then
        return Config.Notify('Could not create the studio helper prop.', 'error')
    end

    local st = LocalPlayer.state.nayzeee_backpack
    local first = (st and st.bag and Bags.exists(st.bag)) and st.bag or currentKey or keys[1]
    local firstVariant = (st and st.bag == first and st.variant) or Bags.defaultVariant(first)

    if not spawnPreview(first, firstVariant) then
        Util.delete(helper); helper = nil
        return
    end

    open = true
    Studio.open = true
    Carry.suspended = true
    if SetWornPropVisible then SetWornPropVisible(false) end
    FreezeEntityPosition(PlayerPedId(), true)

    if calib == nil then
        calib = calibrate()
        attachHelper(tune.bone)
        attachPreview()
    end

    autoPose(currentKey)
    startCam()
    CreateThread(studioLoop)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'studioOpen', data = payload() })
end

RegisterCommand(Config.Studio.command or 'bagtune', function() openStudio() end, false)
RegisterKeyMapping(Config.Studio.command or 'bagtune', 'Open backpack studio (admin)', 'keyboard', '')

AddEventHandler('nayzeee-backpack:overridesChanged', function()
    if open then push() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if open then close() end
end)

function Studio.current() return currentKey, variantId end
function Studio.isOpen() return open end
function Studio.push() if open then push() end end

-----------------------------------------------------------------
-- NUI callbacks
-----------------------------------------------------------------

local function on(name, fn, refresh)
    RegisterNUICallback(name, function(data, cb)
        cb('ok')
        if not open then return end
        run(function()
            fn(data or {})
            if refresh == 'full' then push() elseif refresh ~= false then pushTune() end
        end)
    end)
end

RegisterNUICallback('studio:close', function(_, cb) cb('ok'); close() end)

on('studio:select', function(d)
    if not Bags.exists(d.key) then return end
    spawnPreview(d.key, Bags.defaultVariant(d.key))
    autoPose(d.key)
    if Icons and Icons.active() then Icons.refreshProp() end
end, 'full')

on('studio:variant', function(d)
    local v = tonumber(d.id)
    if not currentKey then return end
    local oldModel = Bags.resolve(currentKey, variantId)
    local newModel, texture = Bags.resolve(currentKey, v)
    if newModel == oldModel and preview then
        SetObjectTextureVariation(preview, texture or 0)
        variantId = v
    else
        spawnPreview(currentKey, v, true)
    end
    if Icons and Icons.active() then Icons.refreshProp() end
end, 'full')

on('studio:move', function(d)
    local amount = tonumber(d.amount) or 0.0
    if d.axis == 'r' or d.axis == 'f' or d.axis == 'u' then moveBy(d.axis, amount) end
end)

on('studio:rotate', function(d)
    if PED_AXIS[d.axis] then rotateBy(d.axis, tonumber(d.deg) or 0.0) end
end)

on('studio:pos', function(d)
    if type(d.pos) ~= 'table' then return end
    tune.pos = {
        x = tonumber(d.pos.x) or tune.pos.x,
        y = tonumber(d.pos.y) or tune.pos.y,
        z = tonumber(d.pos.z) or tune.pos.z,
    }
    attachPreview()
end)

on('studio:rot', function(d)
    if type(d.rot) ~= 'table' then return end
    setRotation({
        x = Util.wrap180(tonumber(d.rot.x) or tune.rot.x),
        y = Util.wrap180(tonumber(d.rot.y) or tune.rot.y),
        z = Util.wrap180(tonumber(d.rot.z) or tune.rot.z),
    })
end)

on('studio:bone', function(d)
    local bone = tonumber(d.bone)
    if bone then setBone(bone) end
end)

on('studio:preset', function(d) applyPreset(d.key) end)

on('studio:revert', function()
    local bone, pos, rot = Bags.offset(currentKey)
    loadTune(bone, pos, rot)
end)

on('studio:factory', function()
    local bone, pos, rot = Bags.configOffset(currentKey)
    loadTune(bone, pos, rot)
end)

on('studio:paste', function(d)
    local t = d.tune
    if type(t) ~= 'table' or not t.pos or not t.rot then return end
    loadTune(tonumber(t.bone) or tune.bone,
        { x = tonumber(t.pos.x) or 0, y = tonumber(t.pos.y) or 0, z = tonumber(t.pos.z) or 0 },
        { x = tonumber(t.rot.x) or 0, y = tonumber(t.rot.y) or 0, z = tonumber(t.rot.z) or 0 })
end)

on('studio:pose', function(d)
    if d.key and Bags.pose(d.key) then
        if Carry.preview(d.key) then poseKey = d.key end
    else
        Carry.stopPreview()
        poseKey = nil
    end
end, 'full')

on('studio:anim', function(d)
    if d.name then CreateThread(function() Anim.play(d.name, true) end) end
end, false)

on('studio:cam', function(d)
    if d.preset and CAMS[d.preset] then
        camWant.yaw, camWant.elev = CAMS[d.preset].yaw, CAMS[d.preset].elev
    end
    if d.dx then camWant.yaw = camWant.yaw - (tonumber(d.dx) or 0) * 0.35 end
    if d.dy then camWant.elev = math.max(-60.0, math.min(80.0, camWant.elev + (tonumber(d.dy) or 0) * 0.25)) end
    if d.zoom then camWant.dist = math.max(0.5, math.min(5.0, camWant.dist + (tonumber(d.zoom) or 0))) end
    if d.focus ~= nil then camWant.focus = d.focus and 1.0 or 0.0 end
end, false)

on('studio:save', function(d)
    if not currentKey then return end
    local patch = {}
    if d.offset then
        patch.offset = { bone = tune.bone, pos = tune.pos, rot = tune.rot }
    end
    if d.storage then
        patch.slots = tonumber(d.storage.slots)
        patch.weight = tonumber(d.storage.weight)
        patch.price = d.storage.price ~= nil and tonumber(d.storage.price) or nil
        patch.label = type(d.storage.label) == 'string' and d.storage.label or nil
    end
    if d.carry then
        patch.carry = d.carry.style
        patch.pose = d.carry.pose
    end
    TriggerServerEvent('nayzeee-backpack:admin:save', currentKey, patch)
end, false)

on('studio:clearSaved', function()
    if currentKey then TriggerServerEvent('nayzeee-backpack:admin:clear', currentKey) end
end, false)

RegisterNUICallback('studio:copied', function(_, cb)
    Config.Notify('Copied to clipboard.', 'success')
    cb('ok')
end)

RegisterNetEvent('nayzeee-backpack:admin:result', function(ok, msg)
    Config.Notify(msg, ok and 'success' or 'error')
end)

-- shared helpers for icons.lua
Studio.run = run
Studio.preview = function() return preview, previewHash end
