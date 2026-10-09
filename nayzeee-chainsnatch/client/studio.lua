-----------------------------------------------------------------
-- Chain studio  (/chainstudio, admin only)
--
-- FIT      on the neck ('worn') and in the hand ('hold'): presets,
--          bones, move / rotate pads, exact values, Save. Fits are
--          saved per body: a male ped saves the male fit, a female
--          ped the female one (each falls back to the other).
-- LOOK     name, value, a name per texture, give yourself one.
-- ICON     see client/icons.lua
-- CONVERT  run chainkit: what's new / changed, build, rebuild.
--
-- The fitting maths is the backpack studio's: on open it probes how
-- GTA applies attach rotations, then turns the chain around its own
-- centre and swaps bones without the chain jumping. If the probe
-- fails it falls back to measuring in-game.
--
-- "From clothing" puts a converted chain exactly where it sat as
-- clothing (chainkit remembers that spot), so most chains only need
-- a nudge after it. "Fit every chain" does that for all unfitted ones.
-----------------------------------------------------------------

Studio = { open = false }

local open = false
local preview, previewHash = nil, nil
local centre, mn, mx = vector3(0, 0, 0), vector3(0, 0, 0), vector3(0, 0, 0)
local helper = nil
local currentKey, variantId = nil, nil
local mode = 'worn'          -- 'worn' | 'hold'
local calib = nil            -- { order, sign, swap } or false when the probe failed
local queue = {}

local tune = { bone = 39317, pos = { x = 0, y = 0, z = 0 }, rot = { x = 0, y = 0, z = 0 } }

local cam = nil
local camWant = { yaw = 0.0, elev = 6.0, dist = 1.1, focus = 1.0 }
local camNow  = { yaw = 0.0, elev = 6.0, dist = 1.1, focus = 1.0 }

local BONES = {
    { id = 39317, label = 'Neck',                     group = 'Body' },
    { id = 24818, label = 'Spine 3 · chest',          group = 'Body' },
    { id = 24817, label = 'Spine 2',                  group = 'Body' },
    { id = 31086, label = 'Head',                     group = 'Body' },
    { id = 57005, label = 'Right hand',               group = 'Right' },
    { id = 28422, label = 'Right hand (prop point)',  group = 'Right' },
    { id = 28252, label = 'Right forearm',            group = 'Right' },
    { id = 18905, label = 'Left hand',                group = 'Left' },
    { id = 60309, label = 'Left hand (prop point)',   group = 'Left' },
    { id = 61163, label = 'Left forearm',             group = 'Left' },
}

-- presets in CHARACTER terms (right / forward / up from the bone)
--   from   'clothing' = where chainkit says the chain sat on the body
--   pitch  turns the chain about the character's right axis (90 = hangs flat against the chest)
--   hang   the top of the chain hangs from the point instead of its centre
local PRESETS = {
    worn = {
        { key = 'clothing', label = 'From clothing', bone = 39317, from = 'clothing' },
        { key = 'neck',     label = 'Neck',          bone = 39317, at = { r = 0.0, f = 0.05, u = -0.06 } },
        { key = 'low',      label = 'Long chain',    bone = 24818, at = { r = 0.0, f = 0.13, u = -0.02 }, pitch = 35 },
    },
    hold = {
        { key = 'hang_r', label = 'Dangle · right', bone = 57005, at = { r = 0.0, f = 0.06, u = 0.0 }, pitch = 90, hang = true },
        { key = 'hang_l', label = 'Dangle · left',  bone = 18905, at = { r = 0.0, f = 0.06, u = 0.0 }, pitch = 90, hang = true },
        { key = 'fist_r', label = 'In the fist',    bone = 28422, at = { r = 0.0, f = 0.0,  u = 0.0 }, pitch = 0 },
    },
}

local CAMS = {
    front = { yaw = 0.0,   elev = 6.0 },
    left  = { yaw = 90.0,  elev = 6.0 },
    right = { yaw = -90.0, elev = 6.0 },
    back  = { yaw = 180.0, elev = 8.0 },
    top   = { yaw = 20.0,  elev = 55.0 },
}

-----------------------------------------------------------------
-- euler maths (only used once calibrated)
-----------------------------------------------------------------

local AXFN = { x = M3.rx, y = M3.ry, z = M3.rz }
local PERMS = {
    { 'x', 'y', 'z' }, { 'x', 'z', 'y' }, { 'y', 'x', 'z' },
    { 'y', 'z', 'x' }, { 'z', 'x', 'y' }, { 'z', 'y', 'x' },
}
local I3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function eulerM(rot, conv)
    local o, s = conv.order, conv.sign
    local m = AXFN[o[1]](rot[o[1]] * s[o[1]])
    m = M3.mul(m, AXFN[o[2]](rot[o[2]] * s[o[2]]))
    return M3.mul(m, AXFN[o[3]](rot[o[3]] * s[o[3]]))
end

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

--- Euler angles (degrees) that give matrix T under the calibrated convention.
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

local function axes(entity)
    local a, b, u, p = GetEntityMatrix(entity)
    if calib and calib.swap then return a, b, u, p end
    return b, a, u, p -- GetEntityMatrix returns forward, right, up, pos
end

local function pedAxes()
    local pf, pr, pu = GetEntityMatrix(PlayerPedId())
    if calib and calib.swap then pf, pr = pr, pf end
    return pr, pf, pu
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
        print(('^3[nayzeee-chainsnatch] studio: position probe off by %.3f, using measured mode^0'):format(posErr))
        return false
    end

    local mats = {}
    for i, s in ipairs(samples) do mats[i] = relFor(s, chosen) end
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
        print(('^3[nayzeee-chainsnatch] studio: rotation probe error %.4f, using measured mode^0'):format(bestErr))
        return false
    end
    best.swap = chosen
    Chains.debug(('studio calibrated: order %s%s%s, err %.6f'):format(best.order[1], best.order[2], best.order[3], bestErr))
    return best
end

-----------------------------------------------------------------
-- operations (all run on the studio thread, in order)
-----------------------------------------------------------------

local function run(fn) queue[#queue + 1] = fn end
local push

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
        local pr, pf, pu = pedAxes()
        local axis = ({ r = pr, f = pf, u = pu })[PED_AXIS[which]]
        local B, bp = boneFrame()
        local P = propFrame()
        local cw = centreWorld()
        local Mn = M3.mul(M3.t(B), M3.mul(M3.axis(axis, deg), P))
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

local function moveBy(which, amount)
    local pr, pf, pu = pedAxes()
    local axis = ({ r = pr, f = pf, u = pu })[which]
    local B = boneFrame()
    tune.pos = tbl(vec(tune.pos) + toBone(B, axis * amount))
    attachPreview()
end

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

--- Put the chain at a world point with a character-relative turn.
local function placeAt(bone, point, pitch, yaw)
    attachHelper(bone)
    Wait(0); Wait(0)
    tune.bone = bone
    local B, bp = boneFrame()
    local pr, pf, pu = pedAxes()
    if calib then
        local want = M3.fromAxes(pr, pf, pu)
        if pitch and pitch ~= 0 then want = M3.mul(M3.axis(pr, pitch), want) end
        if yaw and yaw ~= 0 then want = M3.mul(M3.axis(pu, yaw), want) end
        local rot = solveEuler(M3.mul(M3.t(B), want), tune.rot)
        if rot then tune.rot = tbl(rot, 3) end
        tune.pos = tbl(toBone(B, point - bp) - M3.apply(attachM(tune.rot), centre))
        attachPreview()
    else
        tune.rot = { x = pitch or 0, y = 0, z = yaw or 0 }
        tune.pos = { x = 0, y = 0, z = 0 }
        attachPreview()
        Wait(0); Wait(0)
        local u = toBone(B, centreWorld() - bp)
        tune.pos = tbl(toBone(B, point - bp) - u)
        attachPreview()
    end
end

local function applyPreset(key)
    local pre
    for _, p in ipairs(PRESETS[mode]) do if p.key == key then pre = p end end
    if not pre then return end
    local ped = PlayerPedId()

    if pre.from == 'clothing' then
        local d = Chains.def(currentKey)
        local c = d and d.centre
        if not c then return Config.Notify('This chain has no clothing position (it wasn\'t converted by chainkit).', 'error') end
        -- clothing is modelled in the ped's own space, so the ped matrix puts it back on the body
        placeAt(pre.bone, GetOffsetFromEntityInWorldCoords(ped, c.x, c.y, c.z), 0, 0)
        return
    end

    attachHelper(pre.bone)
    Wait(0); Wait(0)
    local _, bp = boneFrame()
    local pr, pf, pu = pedAxes()
    local at = pre.at or {}
    local point = bp + pr * (at.r or 0.0) + pf * (at.f or 0.0) + pu * (at.u or 0.0)
    if pre.hang then
        -- the top of the turned chain at the hand: half its widest side hangs below
        local half = math.max(mx.x - centre.x, mx.y - centre.y, mx.z - centre.z)
        point = point - pu * half
    end
    placeAt(pre.bone, point, pre.pitch or 0, pre.yaw or 0)
end

local function loadTune(f)
    tune.bone = f.bone
    tune.pos = tbl(f.pos)
    tune.rot = tbl(f.rot, 3)
    attachHelper(tune.bone)
    attachPreview()
end

-----------------------------------------------------------------
-- preview prop + pose
-----------------------------------------------------------------

local function destroyPreview()
    Util.delete(preview)
    preview, previewHash = nil, nil
end

local function poseFor()
    local ped = PlayerPedId()
    local a = Hold.anim()
    if mode == 'hold' and a then
        if Util.loadDict(a.dict) then TaskPlayAnim(ped, a.dict, a.clip, 3.0, -3.0, -1, (a.flag or 49) | 1, 0.0, false, false, false) end
    elseif a then
        StopAnimTask(ped, a.dict, a.clip, 2.0)
    end
end

local function spawnPreview(key, letter, keepTune)
    destroyPreview()
    if not Chains.exists(key) then return false end
    local entity, hash = Util.spawnChain(key, letter, GetEntityCoords(PlayerPedId()))
    if not entity then return false end
    preview, previewHash = entity, hash
    centre, mn, mx = Util.modelCentre(hash)
    currentKey, variantId = key, Chains.variant(key, letter).letter
    if not keepTune then loadTune(Chains.fit(key, mode, Util.isFemale())) else attachPreview() end
    return true
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
-- camera, orbit relative to the ped
-----------------------------------------------------------------

local function camTarget()
    local ped = PlayerPedId()
    local base = mode == 'hold' and GetPedBoneCoords(ped, 57005, 0.0, 0.0, 0.0) or GetPedBoneCoords(ped, 39317, 0.0, 0.0, 0.0)
    if not preview or not DoesEntityExist(preview) then return base end
    return base + (centreWorld() - base) * camNow.focus
end

local function updateCam(dt)
    if not cam then return end
    local k = math.min(1.0, (dt or 0.016) * 9.0)
    camNow.yaw = camNow.yaw + Util.wrap180(camWant.yaw - camNow.yaw) * k
    camNow.elev = camNow.elev + (camWant.elev - camNow.elev) * k
    camNow.dist = camNow.dist + (camWant.dist - camNow.dist) * k
    camNow.focus = camNow.focus + (camWant.focus - camNow.focus) * k
    local target = camTarget()
    local yaw = math.rad(GetEntityHeading(PlayerPedId()) + camNow.yaw)
    local el = math.rad(camNow.elev)
    local d = camNow.dist
    -- yaw 0 = in front of the character, looking at the chest
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

-----------------------------------------------------------------
-- NUI payload
-----------------------------------------------------------------

local function payload()
    local list = {}
    local female = Util.isFemale()
    for _, key in ipairs(Chains.keys()) do
        local d = Chains.def(key)
        local vars = {}
        for _, v in ipairs(d.variants) do vars[#vars + 1] = { letter = v.letter, prop = v.prop, label = v.label } end
        list[#list + 1] = {
            key = key, label = d.label, origin = d.origin, value = d.value, variants = vars,
            price = Chains.price(key) or d.price or Config.Store.DefaultPrice, forSale = d.forSale ~= false, craftable = d.craftable ~= false,
            exclusive = d.exclusive == true, madeFor = d.madeFor,
            hasCentre = d.centre ~= nil,
            fitted = { worn = Chains.hasFit(key, 'worn', female), hold = Chains.hasFit(key, 'hold', female) },
        }
    end
    local anims = {}
    for k, a in pairs(Config.Hold.Anims) do anims[#anims + 1] = { key = k, label = a.label or k } end
    return {
        chains = list, bones = BONES, presets = PRESETS[mode], mode = mode,
        current = currentKey, variant = variantId, tune = tune, calibrated = calib and true or false,
        female = female, cam = camWant, icon = Icons and Icons.state() or nil, holdAnim = Config.Hold.Anim, anims = anims,
    }
end

push = function(action) NUI.send(action or 'studio:refresh', payload()) end
local function pushTune() NUI.send('studio:tune', { tune = tune }) end

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
            if not ok then print('^1[nayzeee-chainsnatch] studio: ' .. tostring(err) .. '^0') end
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
    local a = Hold.anim()
    if a then StopAnimTask(PlayerPedId(), a.dict, a.clip, 2.0) end
    stopCam()
    destroyPreview()
    Util.delete(helper)
    helper = nil
    FreezeEntityPosition(PlayerPedId(), false)
    WornProps.hideSelf(false)
    SetNuiFocus(false, false)
    NUI.send('studio:close')
end

local function openStudio()
    if open then return close() end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return CB.Notify('Get out of the vehicle first.', 'error') end
    if Hold.active() then Hold.stop(false) end
    if Menu.open then Menu.close() end
    if not lib.callback.await('nzc:studio:allowed', false) then return CB.Notify(Config.Text.no_admin, 'error') end
    if not ensureHelper() then return CB.Notify('Could not create the studio helper prop.', 'error') end

    open = true
    Studio.open = true
    WornProps.hideSelf(true)
    FreezeEntityPosition(PlayerPedId(), true)

    local keys = Chains.keys()
    if #keys > 0 then
        local mine, myLetter = WornProps.mine()
        local first = (mine and Chains.exists(mine)) and mine or (currentKey and Chains.exists(currentKey) and currentKey) or keys[1]
        spawnPreview(first, first == mine and myLetter or variantId)
        if calib == nil and preview then
            calib = calibrate()
            loadTune(Chains.fit(currentKey, mode, Util.isFemale()))
        end
    end
    poseFor()
    startCam()
    CreateThread(studioLoop)
    SetNuiFocus(true, true)
    local p = payload()
    p.text = { save = 'Save' }
    NUI.send('studio:open', p)
    -- the converter's state, for the Convert tab
    CreateThread(function()
        local st = lib.callback.await('nzc:chainkit:status', false)
        if st and open then NUI.send('studio:kit', { kind = 'status', status = st }) end
    end)
end

RegisterCommand(Config.Studio.Command or 'chainstudio', function() openStudio() end, false)

AddEventHandler('nzc:registry', function()
    if not open then return end
    run(function()
        if currentKey and not Chains.exists(currentKey) then destroyPreview(); currentKey = nil end
        if not currentKey and #Chains.keys() > 0 then
            spawnPreview(Chains.keys()[1], nil)
            if calib == nil and preview then calib = calibrate(); loadTune(Chains.fit(currentKey, mode, Util.isFemale())) end
        end
        push()
    end)
end)

RegisterNetEvent('nzc:c:chainkit', function(data)
    if open then NUI.send('studio:kit', data) end
end)

RegisterNetEvent('nzc:studio:result', function(ok, msg) CB.Notify(msg, ok and 'success' or 'error') end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and open then close() end
end)

function Studio.current() return currentKey, variantId end
function Studio.isOpen() return open end

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
    if not Chains.exists(d.key) then return end
    spawnPreview(d.key, nil)
    if calib == nil and preview then calib = calibrate(); loadTune(Chains.fit(currentKey, mode, Util.isFemale())) end
    if Icons and Icons.active() then Icons.refreshProp() end
end, 'full')

on('studio:variant', function(d)
    if not currentKey then return end
    spawnPreview(currentKey, d.letter, true)
    if Icons and Icons.active() then Icons.refreshProp() end
end, 'full')

on('studio:mode', function(d)
    if d.mode ~= 'worn' and d.mode ~= 'hold' then return end
    mode = d.mode
    if currentKey then loadTune(Chains.fit(currentKey, mode, Util.isFemale())) end
    poseFor()
    camWant.dist = mode == 'hold' and 1.3 or 1.1
end, 'full')

on('studio:move', function(d)
    if d.axis == 'r' or d.axis == 'f' or d.axis == 'u' then moveBy(d.axis, tonumber(d.amount) or 0.0) end
end)

on('studio:rotate', function(d)
    if PED_AXIS[d.axis] then rotateBy(d.axis, tonumber(d.deg) or 0.0) end
end)

on('studio:pos', function(d)
    if type(d.pos) ~= 'table' then return end
    tune.pos = { x = tonumber(d.pos.x) or tune.pos.x, y = tonumber(d.pos.y) or tune.pos.y, z = tonumber(d.pos.z) or tune.pos.z }
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

on('studio:bone', function(d) local b = tonumber(d.bone); if b then setBone(b) end end)
on('studio:preset', function(d) applyPreset(d.key) end)
on('studio:revert', function() if currentKey then loadTune(Chains.fit(currentKey, mode, Util.isFemale())) end end)
on('studio:default', function() loadTune(Config.DefaultFit[mode]) end)

on('studio:paste', function(d)
    local t = d.tune
    if type(t) ~= 'table' or not t.pos or not t.rot then return end
    loadTune({
        bone = tonumber(t.bone) or tune.bone,
        pos = { x = tonumber(t.pos.x) or 0, y = tonumber(t.pos.y) or 0, z = tonumber(t.pos.z) or 0 },
        rot = { x = tonumber(t.rot.x) or 0, y = tonumber(t.rot.y) or 0, z = tonumber(t.rot.z) or 0 },
    })
end)

on('studio:cam', function(d)
    if d.preset and CAMS[d.preset] then camWant.yaw, camWant.elev = CAMS[d.preset].yaw, CAMS[d.preset].elev end
    if d.dx then camWant.yaw = camWant.yaw - (tonumber(d.dx) or 0) * 0.35 end
    if d.dy then camWant.elev = math.max(-60.0, math.min(80.0, camWant.elev + (tonumber(d.dy) or 0) * 0.25)) end
    if d.zoom then camWant.dist = math.max(0.35, math.min(4.0, camWant.dist + (tonumber(d.zoom) or 0))) end
    if d.focus ~= nil then camWant.focus = d.focus and 1.0 or 0.0 end
end, false)

on('studio:pose', function(d)
    if d.key and Config.Hold.Anims[d.key] then Config.Hold.Anim = d.key end
    poseFor()
end, 'full')

local function fitKey() return mode .. (Util.isFemale() and '_f' or '') end

on('studio:save', function()
    if not currentKey then return end
    TriggerServerEvent('nzc:studio:save', currentKey, { fit = { [fitKey()] = { bone = tune.bone, pos = tune.pos, rot = tune.rot } } })
end, false)

on('studio:look', function(d)
    if not currentKey then return end
    TriggerServerEvent('nzc:studio:save', currentKey, {
        label = d.label, vlabels = d.vlabels, price = d.price, value = d.price,
        forSale = d.forSale == true, craftable = d.craftable == true,
    })
end, false)

-- exclusive chains: who may buy it (game licenses)
on('studio:owners', function()
    if not currentKey then return end
    local data = lib.callback.await('nzc:studio:owners', false, currentKey)
    if data then data.key = currentKey; NUI.send('studio:owners', data) end
end, false)

on('studio:setOwners', function(d)
    if not currentKey or type(d.owners) ~= 'table' then return end
    TriggerServerEvent('nzc:studio:save', currentKey, { owners = d.owners })
end, false)

on('studio:clearFit', function()
    if currentKey then TriggerServerEvent('nzc:studio:clear', currentKey, fitKey()) end
end, false)

on('studio:give', function()
    if currentKey then TriggerServerEvent('nzc:studio:give', currentKey, variantId) end
end, false)

-- "From clothing" for every chain without a saved fit (this body, this mode)
on('studio:fitAll', function()
    if mode ~= 'worn' then return CB.Notify('Switch to Worn first.', 'error') end
    local female = Util.isFemale()
    local startKey, startVar = currentKey, variantId
    local patches, n = {}, 0
    for _, key in ipairs(Chains.keys()) do
        local d = Chains.def(key)
        if d.centre and not Chains.hasFit(key, 'worn', female) then
            if spawnPreview(key, nil) then
                applyPreset('clothing')
                Wait(0)
                patches[key] = { fit = { [fitKey()] = { bone = tune.bone, pos = tune.pos, rot = tune.rot } } }
                n = n + 1
            end
        end
    end
    if n > 0 then TriggerServerEvent('nzc:studio:saveMany', patches) end
    if startKey then spawnPreview(startKey, startVar) end
    CB.Notify(n > 0 and ('Fitted %d chain(s) from their clothing spot.'):format(n) or 'Every chain already has a fit.', n > 0 and 'success' or 'info')
end, 'full')

on('studio:kit', function(d)
    if d.mode == 'status' then
        local st = lib.callback.await('nzc:chainkit:status', false)
        if st then NUI.send('studio:kit', { kind = 'status', status = st }) end
    else
        TriggerServerEvent('nzc:s:chainkit', d.mode)
    end
end, false)

RegisterNUICallback('studio:copied', function(_, cb)
    CB.Notify('Copied to clipboard.', 'success')
    cb('ok')
end)

-- shared with icons.lua
Studio.run = run
Studio.preview = function() return preview, previewHash end
