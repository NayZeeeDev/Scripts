--[[
    NAYZEEE AMBULANCE - Ultrasound (client): the world side of a scan       NZA.Ultrasound.World

    Everything the medic and the people around them see in the world while the 'ultrasound' app
    runs: a torso frame computed every frame from the patient's bones, the 5 × 5 anchor grid the
    NUI maps the mouse onto (ids g<i>_<j>, torso coords GX × GY, same numbers as app.js), the
    scripted camera over the torso, the medic's working pose (stand / kneel by the patient's
    height) with the right arm reaching for the probe (arm IK), the probe prop sliding over the
    skin (Config.Props.us_probe, networked by default so others see it move), the syringe on its
    way under the breastbone (pericardiocentesis) and the cart screen (a DUI page that mirrors the
    live image onto Config.PropScreens.us_cart while the scan runs next to a cart).

    Torso space (shared with app.js):  x -1 = patient's right flank … +1 left flank (around the
    body, a = x · 1.2 rad from the front), y 0 = pubis … 1 = collarbones.

    API (runtime only):
      W.Begin(kind 'scan'|'pericardio'|'chestdrain'|'decompress', entity, opts) → scene
          opts = { side, cart = point | nil, data = server start data }
      W.Probe(scene, p)        p = { x, y, rot, tilt, contact, win, q, shift, vis, depth, gain, focus, frozen, mm }
      W.Needle(scene, n)       n = { phase = 'in' | nil, depth (cm), ang (rad), draw, touch }
      W.Flinch(scene)          a short pain reaction (camera nudge)      W.Vitals(scene, v)  → cart screen
      W.Hold(scene)            the scan is graded: lift the probe, keep the view while the result is read
      W.End(scene)             removes everything (props, camera, anchors, DUI, anim, IK)
      W.Frame(ped) → frame     W.Surface(frame, x, y, lift) → pos, normal
      W.NearestCart(coords, range) → point, dist
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Ultrasound = NZA.Ultrasound or {}
NZA.Ultrasound.World = NZA.Ultrasound.World or {}
local W = NZA.Ultrasound.World

local APP = 'ultrasound'
local GROUP = 'nza_ultrasound'
local GX = { -1.15, -0.58, 0.0, 0.58, 1.15 }
local GY = { -0.06, 0.26, 0.52, 0.78, 1.04 }

local BONE_PELVIS, BONE_NECK = 11816, 39317
local BONE_L_CLAV, BONE_R_CLAV = 64729, 10706
local BONE_L_THIGH, BONE_R_THIGH = 58271, 51826
local BONE_SPINE3 = 24818
local BONE_PH_R_HAND = 28422

local function cfg(section)
    local c = Config.Ultrasound or {}
    if section then return type(c[section]) == 'table' and c[section] or {} end
    return c
end

local function num(v, d)
    v = tonumber(v)
    if not v or v ~= v then return d end
    return v
end

-- ════════════════════════════════════════════════════════════════════════
-- VECTOR HELPERS
-- ════════════════════════════════════════════════════════════════════════

local ZERO = vector3(0.0, 0.0, 0.0)

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end
local function norm(v)
    local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if l < 1e-6 then return ZERO end
    return v / l
end
local function lerp(a, b, t) return a + (b - a) * t end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function smoothK(dt, rate) return 1.0 - math.exp(-dt * rate) end

-- ════════════════════════════════════════════════════════════════════════
-- TORSO FRAME (from the patient's bones, every frame)
-- ════════════════════════════════════════════════════════════════════════

-- half width / half depth of the torso along its length (y 0 pubis … 1 collarbones)
local PROFILE = {
    { 0.00, 0.168, 0.100 }, { 0.20, 0.160, 0.104 }, { 0.38, 0.150, 0.108 }, { 0.55, 0.158, 0.112 },
    { 0.72, 0.170, 0.114 }, { 0.88, 0.172, 0.108 }, { 1.05, 0.160, 0.095 },
}
local function profile(y, sx, sy)
    local a, b = PROFILE[1], PROFILE[#PROFILE]
    if y <= a[1] then return a[2] * sx, a[3] * sy end
    if y >= b[1] then return b[2] * sx, b[3] * sy end
    for i = 1, #PROFILE - 1 do
        local p, q = PROFILE[i], PROFILE[i + 1]
        if y >= p[1] and y <= q[1] then
            local t = (y - p[1]) / (q[1] - p[1])
            return lerp(p[2], q[2], t) * sx, lerp(p[3], q[3], t) * sy
        end
    end
    return a[2] * sx, a[3] * sy
end

function W.Frame(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local tc = cfg('Torso')
    local pel = GetPedBoneCoords(ped, BONE_PELVIS, 0.0, 0.0, 0.0)
    local lc = GetPedBoneCoords(ped, BONE_L_CLAV, 0.0, 0.0, 0.0)
    local rc = GetPedBoneCoords(ped, BONE_R_CLAV, 0.0, 0.0, 0.0)
    local lt = GetPedBoneCoords(ped, BONE_L_THIGH, 0.0, 0.0, 0.0)
    local rt = GetPedBoneCoords(ped, BONE_R_THIGH, 0.0, 0.0, 0.0)
    local top = (lc + rc) * 0.5
    local A = norm(top - pel)
    if A == ZERO then return nil end
    local lat = (lc - rc) + (lt - rt)
    local L = norm(lat - A * dot(lat, A))
    if L == ZERO then return nil end
    local F = norm(cross(L, A))
    local base = pel + A * num(tc.pubis, -0.05) + F * num(tc.front, 0.0)
    local tip = top + A * num(tc.collar, -0.015) + F * num(tc.frontTop, -0.01)
    local len = dot(tip - base, A)
    if len < 0.2 then len = 0.48 end
    return {
        base = base, A = A, L = L, F = F, len = len, ped = ped,
        sx = num(tc.width, 1.0), sy = num(tc.depth, 1.0), centre = base + A * (len * 0.55),
    }
end

-- torso (x, y) → world point on the skin + outward normal; lift = metres above the skin
function W.Surface(fr, x, y, lift)
    local a = clamp(x, -1.3, 1.3) * 1.2
    local rx, ry = profile(y, fr.sx, fr.sy)
    local s, c = math.sin(a), math.cos(a)
    local axis = fr.base + fr.A * (y * fr.len)
    local p = axis + fr.L * (s * rx) + fr.F * (c * ry)
    local n = norm(fr.L * (s / rx) + fr.F * (c / ry))
    if lift and lift ~= 0 then p = p + n * lift end
    return p, n
end

-- ════════════════════════════════════════════════════════════════════════
-- CART POINT
-- ════════════════════════════════════════════════════════════════════════

function W.NearestCart(coords, range)
    if not (NZA.Points and NZA.Points.All) or not coords then return nil end
    range = range or num(cfg('Scan').cartRange, 2.6)
    local best, bd = nil, nil
    for _, pt in ipairs(NZA.Points.All('ultrasound') or {}) do
        local c = pt.coords
        if c then
            local d = #(vector2(coords.x, coords.y) - vector2(c.x, c.y))
            if d <= range and math.abs(coords.z - c.z) <= 2.5 and (not bd or d < bd) then best, bd = pt, d end
        end
    end
    return best, bd
end

-- ════════════════════════════════════════════════════════════════════════
-- CART SCREEN (DUI)
-- ════════════════════════════════════════════════════════════════════════

local function stopDui(sc)
    local d = sc and sc.dui
    if not d then return end
    sc.dui = nil
    if d.txd and d.tex then pcall(RemoveReplaceTexture, d.txd, d.tex) end
    if d.obj then pcall(DestroyDui, d.obj) end
end

local function duiSend(sc, msg)
    local d = sc and sc.dui
    if not d or not d.obj or not d.ready then return end
    pcall(SendDuiMessage, d.obj, json.encode(msg))
end

local duiSerial = 0
local function startDui(sc)
    local cc = cfg('Cart')
    if cc.dui == false or not sc.cart then return end
    local scr = Config.PropScreens and Config.PropScreens.us_cart
    if not scr or not scr.txd or not scr.tex then return end
    local size = type(cc.duiSize) == 'table' and cc.duiSize or { 512, 320 }
    local w, h = math.floor(num(size[1], 512)), math.floor(num(size[2], 320))
    local url = ('nui://%s/html/apps/ultrasound/screen.html'):format(GetCurrentResourceName())
    local ok, obj = pcall(CreateDui, url, w, h)
    if not ok or not obj then return end
    duiSerial = duiSerial + 1
    local txdName = ('nza_us_cart_%d'):format(duiSerial)
    local okT = pcall(function()
        local rtxd = CreateRuntimeTxd(txdName)
        CreateRuntimeTextureFromDuiHandle(rtxd, 'screen', GetDuiHandle(obj))
        AddReplaceTexture(scr.txd, scr.tex, txdName, 'screen')
    end)
    if not okT then pcall(DestroyDui, obj) return end
    sc.dui = { obj = obj, txd = scr.txd, tex = scr.tex, ready = false }
    local d = sc.dui
    SetTimeout(900, function()
        if sc.dui ~= d then return end
        d.ready = true
        local data = sc.data or {}
        duiSend(sc, {
            type = 'init', kind = sc.kind, seed = data.seed, study = data.study, views = data.views,
            labels = data.labels ~= false, sex = data.patient and data.patient.sex, mm = data.mm,
            where = data.where, locale = NZA.LocaleTable('ultrasound'),
        })
        if sc.vit then duiSend(sc, { type = 'vitals', vitals = sc.vit }) end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- PROPS
-- ════════════════════════════════════════════════════════════════════════

local function spawnProp(key, at, network)
    if not (Config.Props and Config.Props[key]) then return 0 end
    local ok, ent = pcall(NZA.Props.Spawn, key, at, {
        group = GROUP, network = network == true, freeze = true, collision = false, invincible = true,
    })
    if not ok or not ent or ent == 0 then return 0 end
    SetEntityCollision(ent, false, false)
    return ent
end

-- place an entity with explicit axes (X right, Y forward, Z up) at pos
local function placeAxes(ent, pos, X, Y, Z)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    local ok = pcall(SetEntityMatrix, ent, Y.x, Y.y, Y.z, X.x, X.y, X.z, Z.x, Z.y, Z.z, pos.x, pos.y, pos.z)
    if not ok then
        local pitch = math.deg(math.asin(clamp(Y.z, -1.0, 1.0)))
        local yaw = math.deg(math.atan(-Y.x, Y.y))
        local roll = math.deg(math.atan(-X.z, Z.z))
        SetEntityCoordsNoOffset(ent, pos.x, pos.y, pos.z, false, false, false)
        SetEntityRotation(ent, pitch, roll, yaw, 2, false)
    end
end

local function attachToHand(ent, me)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    local bone = GetPedBoneIndex(me, BONE_PH_R_HAND)
    AttachEntityToEntity(ent, me, bone, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, true, true, false, true, 1, true)
end

-- ════════════════════════════════════════════════════════════════════════
-- MEDIC POSE
-- ════════════════════════════════════════════════════════════════════════

local function poseFor(sc)
    local an = cfg('Anim')
    local me = PlayerPedId()
    local pel = GetPedBoneCoords(sc.entity, BONE_PELVIS, 0.0, 0.0, 0.0)
    local feet = GetEntityCoords(me).z - 0.98
    local low = (pel.z - feet) < num(an.lowPatient, 0.55)
    local a = low and an.kneel or an.stand
    if type(a) ~= 'table' or not a.dict then return nil end
    return a, low
end

local function startPose(sc)
    local me = PlayerPedId()
    local a, low = poseFor(sc)
    sc.low = low
    local c = sc.frame and sc.frame.centre or GetEntityCoords(sc.entity)
    TaskTurnPedToFaceCoord(me, c.x, c.y, c.z, 700)
    Wait(450)
    if sc.ended then return end
    if low and NZA.Anim and NZA.Anim.Kneel then
        sc.animToken = NZA.Anim.Kneel(me)
    elseif a and NZA.Anim and NZA.Anim.Play then
        local ok, token = NZA.Anim.Play(me, a.dict, a.clip, { flag = a.flag or 1, blendIn = 4.0, blendOut = -4.0 })
        if ok then sc.animToken = token end
    end
end

local function stopPose(sc)
    local me = PlayerPedId()
    if NZA.Anim and NZA.Anim.Stop and sc.animToken then
        pcall(NZA.Anim.Stop, me, { token = sc.animToken })
    end
    sc.animToken = nil
end

-- ════════════════════════════════════════════════════════════════════════
-- CAMERA
-- ════════════════════════════════════════════════════════════════════════

local function startCam(sc)
    local cc = cfg('Camera')
    local o = sc.kind == 'pericardio' and cc.pericardio or cc.scan
    if type(o) ~= 'table' or o.enabled == false then return end
    local fr = sc.frame
    if not fr then return end
    -- look from the feet so the head sits at the top of the screen; the torso sits left of the
    -- device panel (focus pushed toward the patient's left = screen right)
    local yFocus = sc.kind == 'pericardio' and num(o.y, 0.64) or num(o.y, 0.52)
    local focus = fr.base + fr.A * (yFocus * fr.len) + fr.F * num(o.up, 0.08) + fr.L * num(o.side, 0.24)
    local back = fr.A * -1.0
    local yaw = math.deg(math.atan(back.y, back.x))
    local ok = pcall(NZA.Cam.Orbit, focus, {
        dist = num(o.dist, 1.05), pitch = num(o.pitch, 72), fov = num(o.fov, 46), yaw = yaw,
        minDist = num(o.minDist, 0.45), maxDist = num(o.maxDist, 1.9), minPitch = 25, maxPitch = 88,
        orbit = sc.kind == 'scan', pan = sc.kind == 'scan', zoom = true, panLimit = 0.4, ease = 700, hideHud = true,
    })
    sc.cam = ok
end

-- ════════════════════════════════════════════════════════════════════════
-- ANCHORS
-- ════════════════════════════════════════════════════════════════════════

local function trackAnchors(sc)
    sc.defs = {}
    for i = 1, #GX do
        for j = 1, #GY do
            sc.defs[('g%d_%d'):format(i - 1, j - 1)] = { coords = vector3(0.0, 0.0, 0.0), gx = GX[i], gy = GY[j] }
        end
    end
    sc.anchors = true
    -- fill the coords before the first projection
    local fr = sc.frame
    if fr then
        for _, def in pairs(sc.defs) do def.coords = W.Surface(fr, def.gx, def.gy, 0.004) end
    end
    NZA.Anchors.Track(APP, sc.defs)
end

local function updateAnchors(sc)
    local fr = sc.frame
    if not fr or not sc.defs then return end
    for _, def in pairs(sc.defs) do
        def.coords = W.Surface(fr, def.gx, def.gy, 0.004)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- PROBE + NEEDLE (per frame)
-- ════════════════════════════════════════════════════════════════════════

local function probePose(fr, p)
    local pos, N = W.Surface(fr, p.x, p.y, 0.0)
    local Ht = norm(fr.A - N * dot(fr.A, N))
    local Rt = norm(cross(N, Ht))                                   -- patient's right on the skin
    local r = math.rad(p.rot or 0.0)
    local mark = norm(Ht * math.cos(r) + Rt * math.sin(r))
    local t = math.rad(clamp(p.tilt or 0.0, -15.0, 45.0))
    local beam = norm(N * -math.cos(t) + Ht * math.sin(t))
    local Z = beam * -1.0                                           -- prop +Z = cable end, lens on -Z
    local X = norm(mark - Z * dot(mark, Z))
    if X == ZERO then X = Rt end
    local Y = cross(Z, X)
    local lift = num(cfg('Probe').lift, 0.012)
    local at = pos + Z * (0.063 + (p.press and 0.002 or lift * 0.25))
    return at, X, Y, Z
end

local function needleAxes(fr, n)
    -- entry just under the breastbone, aimed at the left shoulder, rising toward the skin plane
    local ent, N = W.Surface(fr, -0.04, 0.6, 0.0)
    local toShoulder = norm(fr.A * 0.78 + fr.L * 0.5)
    local T = norm(toShoulder - N * dot(toShoulder, N))
    local e = clamp(math.pi / 2 - num(n.ang, 0.86), 0.32, 1.05)
    local D = norm(T * math.cos(e) - N * math.sin(e))               -- needle direction (into the body)
    local X = norm(cross(D, N))
    local Z = norm(cross(X, D))
    local depth = clamp(num(n.depth, 0.0), 0.0, 14.0) / 100.0
    local tip = ent + D * depth
    return tip - D * 0.123, X, D, Z
end

local function tick(sc, dt)
    local fr = W.Frame(sc.entity)
    if fr then sc.frame = fr end
    fr = sc.frame
    if not fr then return end
    if sc.defs then updateAnchors(sc) end
    local me = PlayerPedId()

    -- probe
    if sc.probe and sc.probe ~= 0 and DoesEntityExist(sc.probe) then
        local tgt = sc.pTarget
        if tgt and tgt.contact then
            local c = sc.pCur
            if not c then
                c = { x = tgt.x, y = tgt.y, rot = tgt.rot, tilt = tgt.tilt }
                sc.pCur = c
            end
            local k = smoothK(dt, 12.0)
            c.x = lerp(c.x, tgt.x, k); c.y = lerp(c.y, tgt.y, k)
            local dr = ((tgt.rot - c.rot) % 360 + 540) % 360 - 180
            c.rot = c.rot + dr * k
            c.tilt = lerp(c.tilt, tgt.tilt, k)
            c.press = true
            if sc.inHand then
                DetachEntity(sc.probe, false, false)
                sc.inHand = false
            end
            local at, X, Y, Z = probePose(fr, c)
            placeAxes(sc.probe, at, X, Y, Z)
            sc.ikAt = at
        else
            sc.pCur = nil
            sc.ikAt = nil
            if not sc.inHand then
                attachToHand(sc.probe, me)
                sc.inHand = true
            end
        end
    end

    -- syringe (pericardiocentesis)
    if sc.needle and sc.needle.on then
        if (not sc.syringe or sc.syringe == 0) and not sc.syrTried then
            sc.syrTried = true
            local c = sc.frame.centre
            sc.syringe = spawnProp('syringe', c, cfg('Probe').networked ~= false)
        end
        if sc.syringe and sc.syringe ~= 0 and DoesEntityExist(sc.syringe) then
            local nCur = sc.nCur or { depth = 0.0, ang = sc.needle.ang or 0.86 }
            sc.nCur = nCur
            local k = smoothK(dt, 10.0)
            nCur.depth = lerp(nCur.depth, num(sc.needle.depth, 0.0), k)
            nCur.ang = lerp(nCur.ang, num(sc.needle.ang, 0.86), k)
            local at, X, Y, Z = needleAxes(fr, nCur)
            placeAxes(sc.syringe, at, X, Y, Z)
        end
    end

    -- the right arm reaches for the probe while it is on the skin (close enough to look natural)
    if sc.ikAt and cfg('Anim').ik ~= false then
        local hand = GetPedBoneCoords(me, BONE_PH_R_HAND, 0.0, 0.0, 0.0)
        if #(hand - sc.ikAt) < 0.95 then
            SetIkTarget(me, 4, 0, 0, sc.ikAt.x, sc.ikAt.y, sc.ikAt.z + 0.05, 0, 120, 120)
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- SCENE
-- ════════════════════════════════════════════════════════════════════════

function W.Begin(kind, entity, opts)
    opts = opts or {}
    local sc = { kind = kind, entity = entity, side = opts.side, data = opts.data or {}, cart = opts.cart, t0 = GetGameTimer() }
    sc.frame = W.Frame(entity)
    local imaging = kind == 'scan' or kind == 'pericardio'

    CreateThread(function() startPose(sc) end)

    if imaging then
        trackAnchors(sc)
        startCam(sc)
        local me = PlayerPedId()
        local hand = GetPedBoneCoords(me, BONE_PH_R_HAND, 0.0, 0.0, 0.0)
        sc.probe = spawnProp('us_probe', hand, cfg('Probe').networked ~= false)
        if sc.probe ~= 0 then
            attachToHand(sc.probe, me)
            sc.inHand = true
        end
        if not sc.cart and sc.frame then sc.cart = W.NearestCart(sc.frame.centre) end
        startDui(sc)
    else
        -- full-screen 3D close-up: the world camera only matters for the moment the app closes
        local cc = cfg('Camera')
        local o = kind == 'decompress' and cc.decompress or cc.drain
        if type(o) == 'table' and o.enabled ~= false and sc.frame then
            local fr = sc.frame
            local sideV = (opts.side == 'left') and fr.L or (fr.L * -1.0)
            local focus = fr.base + fr.A * (kind == 'decompress' and 0.86 or 0.68) * fr.len + sideV * (kind == 'decompress' and 0.09 or 0.15) + fr.F * 0.05
            local look = sideV * (kind == 'decompress' and 0.4 or 1.0) + fr.F * 0.9
            local yaw = math.deg(math.atan(look.y, look.x))
            sc.cam = pcall(NZA.Cam.Orbit, focus, {
                dist = num(o.dist, 0.7), pitch = num(o.pitch, 55), fov = num(o.fov, 44), yaw = yaw,
                orbit = false, pan = false, zoom = false, ease = 600, hideHud = true,
            })
        end
    end

    sc.running = true
    CreateThread(function()
        local last = GetGameTimer()
        while sc.running do
            local now = GetGameTimer()
            local dt = math.min(0.1, math.max(0.001, (now - last) / 1000.0))
            last = now
            local ok, err = pcall(tick, sc, dt)
            if not ok then
                NZA.Warn('ultrasound world tick: ' .. tostring(err))
                Wait(250)
            end
            Wait(0)
        end
    end)
    return sc
end

function W.Probe(sc, p)
    if not sc or sc.ended or type(p) ~= 'table' then return end
    sc.pTarget = {
        x = clamp(num(p.x, 0.0), -1.3, 1.3), y = clamp(num(p.y, 0.5), -0.1, 1.1),
        rot = num(p.rot, 0.0), tilt = clamp(num(p.tilt, 0.0), -15.0, 45.0), contact = p.contact == true,
    }
    if sc.dui and sc.dui.ready then
        local now = GetGameTimer()
        if not sc.duiAt or now - sc.duiAt >= num(cfg('Probe').rate, 66) then
            sc.duiAt = now
            local win = type(p.win) == 'string' and #p.win <= 12 and p.win or 'air'
            duiSend(sc, {
                type = 'probe', contact = p.contact == true, win = win, q = clamp(num(p.q, 0), 0, 1), shift = clamp(num(p.shift, 0), -3, 3),
                vis = clamp(num(p.vis, 1), 0, 1), depth = clamp(num(p.depth, 16), 4, 24), gain = clamp(num(p.gain, 55), 0, 100),
                focus = clamp(num(p.focus, 8), 1, 24), frozen = p.frozen == true, mm = p.mm == true, tilt = num(p.tilt, 0),
            })
        end
    end
end

function W.Needle(sc, n)
    if not sc or sc.ended or type(n) ~= 'table' then return end
    if n.phase == 'in' then
        sc.needle = { on = true, depth = 0.0, ang = num(n.ang, 0.86) }
        sc.nCur = nil
        return
    end
    if n.phase == 'out' then
        sc.needle = nil
        duiSend(sc, { type = 'needle', depth = 0, off = true })
        if sc.syringe and sc.syringe ~= 0 then NZA.Props.Delete(sc.syringe) end
        sc.syringe, sc.syrTried = nil, nil
        return
    end
    if sc.needle then
        if n.depth ~= nil then sc.needle.depth = num(n.depth, sc.needle.depth) end
        if n.ang ~= nil then sc.needle.ang = num(n.ang, sc.needle.ang) end
        sc.needle.draw = n.draw == true
        if sc.dui and sc.dui.ready then
            duiSend(sc, {
                type = 'needle', depth = clamp(num(sc.needle.depth, 0), 0, 14), ang = num(sc.needle.ang, 0.86),
                eff = tonumber(n.eff), q = clamp(num(n.q, 1), 0, 1), draw = sc.needle.draw,
            })
        end
    end
end

function W.Vitals(sc, v)
    if not sc or sc.ended then return end
    sc.vit = v
    duiSend(sc, { type = 'vitals', vitals = v })
end

function W.Flinch(sc)
    if not sc or sc.ended then return end
    local cam = sc.cam and NZA.Cam.Handle and NZA.Cam.Handle() or nil
    if cam and DoesCamExist(cam) then ShakeCam(cam, 'HAND_SHAKE', 0.35) SetTimeout(450, function() if DoesCamExist(cam) then StopCamShaking(cam, false) end end) end
end

-- the scan is over but the medic still reads the result: lift the probe, keep the view
function W.Hold(sc)
    if not sc or sc.ended then return end
    sc.pTarget = nil
    if sc.defs then
        sc.defs = nil
        NZA.Anchors.Clear(APP)
    end
    duiSend(sc, { type = 'freeze' })
end

function W.End(sc)
    if not sc or sc.ended then return end
    sc.ended = true
    sc.running = false
    if sc.defs or sc.anchors then NZA.Anchors.Clear(APP) end
    sc.defs = nil
    if sc.cam then pcall(NZA.Cam.Stop, 500) end
    sc.cam = nil
    stopDui(sc)
    if sc.probe and sc.probe ~= 0 then NZA.Props.Delete(sc.probe) end
    if sc.syringe and sc.syringe ~= 0 then NZA.Props.Delete(sc.syringe) end
    sc.probe, sc.syringe = nil, nil
    pcall(NZA.Props.Clear, GROUP)
    stopPose(sc)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    pcall(NZA.Props.Clear, GROUP)
end)
