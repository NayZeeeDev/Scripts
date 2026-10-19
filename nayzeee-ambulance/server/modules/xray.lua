--[[
    NAYZEEE AMBULANCE - Radiology (server): X-ray films, lightbox reading, help off the table

    Taking an X-ray (ARCHITECTURE §5.2)
      NZA.Proc.Register('xray', { perm = Config.Xray.Take.perm, minTime, maxTime, easyTime, maxDist, states,
                                  onStart, onFinish })
        payload { view = 'head'|'neck'|'chest'|'abdomen'|'l_arm'|'r_arm'|'l_leg'|'r_leg' }
        onStart  → view, cooldown, film capacity, patient on an X-ray table (patient.meta.bed.type == 'xray',
                   or lying within Take.tableRadius of an 'xray' point; skipped in easy mode)
        onFinish → builds the film from the patient's REAL injuries (fractures with displacement / angle /
                   position on the image, retained fragments with depth, haemo/pneumothorax side & size)
                   and gives Config.Items.xray_film with that metadata (Bridge.Inv.AddItem)
    Reading a film (lightbox)
      Bridge.Inv.RegisterUsable(Config.Items.xray_film) → event nza:xray:read (payload) to the client
      Callbacks:
        nza:xray:films ()                 → { { slot, id, view, viewLabel, name, taken, read } }  films you carry
        nza:xray:open (slot)              → payload | { ok = false, err, msg }   same as using the item
        nza:xray:read:finish (token, res) → { ok, outcome } | { ok = false, err, msg }
            res = { marks = { ap = { {x,y} }, lat = { {x,y} } }, normal = bool, measure = { film, angle } }
            outcome = { score, grade, rows = { { id, k, label, ap, lat, confirmed } }, falsePins, msg, applied,
                        offline, normalCall, measure = { yours, truth } }
        nza:xray:offTable (target)        → { ok, player, net } | { ok = false, err, msg }
      Net events: nza:xray:read:cancel (token) C→S · nza:xray:read (payload) S→C · nza:xray:standUp (info) S→C
    Diagnosis: confirmed findings set injury.treat.xray + treat.xrayMarked (+ quality.xray), retained
      fragments get injury.xrayMap = { film, view, ap = {x,y}, lat = {x,y}, depth, n, at } (bullet module),
      NZA.Findings.Add(pid, 'xray_<injury>' | '<cond>_suspected_<side>', { source = 'xray', ... }).
    Bus events emitted: xray:taken (src, p, film), xray:read (src, p|nil, film, outcome), xray:offTable (src, p)
    Lua API (runtime): NZA.Xray.Film(p, view, quality, src) → metadata, NZA.Xray.Findings(p, view) → list,
      NZA.Xray.OnTable(p) → bool, pointId, NZA.Xray.NearLightbox(src) → bool, NZA.Xray.Easy(src, perm) → bool,
      NZA.Xray.Bill(src, p, key, reason), NZA.Xray.Notify(src, msg, kind), NZA.Xray.Views
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Xray = NZA.Xray or {}
local X = NZA.Xray
local U = NZA.Util

local reads = {}        -- [src] = reading session
local lastTake = {}     -- [src] = GetGameTimer() of the last film
local films = {}        -- [film id] = metadata (cache of films made since start)

local HEMO_MIN = 150    -- mL of blood in the chest before it shows on a film
local PTX_MIN = 5       -- % collapse before a pneumothorax shows

X.Views = { head = true, neck = true, chest = true, abdomen = true, l_arm = true, r_arm = true, l_leg = true, r_leg = true }
local BREATH_VIEWS = { chest = true, abdomen = true }

-- ════════════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section)
    local c = Config.Xray or {}
    if section then return c[section] or {} end
    return c
end

local function L(key, ...)
    return NZA.L('xray.' .. key, ...)
end

local function core()
    return NZA.Core or {}
end

local function itemName(key)
    return Config.Items and Config.Items[key] or nil
end

local function r3(n)
    return math.floor(n * 1000 + 0.5) / 1000
end

local function clamp01(n)
    return U.clamp(tonumber(n) or 0, 0, 1)
end

local function hashSeed(str)
    local h = 2166136261
    for i = 1, #str do
        h = (h ~ str:byte(i)) * 16777619 % 4294967296
    end
    return math.floor(h % 2147483646) + 1
end

-- deterministic 0..1 from a seed string and a channel number
local function hrand(seed, ch)
    local s = hashSeed(seed .. '#' .. tostring(ch or 0))
    s = (s * 48271) % 2147483647
    return (s % 100000) / 100000
end

function X.Notify(src, msg, kind, title)
    if core().Notify then
        core().Notify(src, { title = title or L('title'), message = msg, type = kind or 'info' })
    else
        TriggerClientEvent('nza:ui:toast', src, { title = title or L('title'), message = msg, type = kind or 'info' })
    end
end

local function fail(err, msg)
    return { ok = false, err = err, msg = msg or L('err_' .. err) }
end

function X.Easy(src, perm)
    if NZA.Staff and type(NZA.Staff.Easy) == 'function' then
        local ok, res = pcall(NZA.Staff.Easy, src, perm)
        if ok then return res == true end
    end
    return Config.EasyMode ~= nil and Config.EasyMode.default == true
end

local function can(src, perm)
    if not perm then return true end
    return NZA.Staff and NZA.Staff.Can and NZA.Staff.Can(src, perm) == true
end

function X.Bill(src, p, key, reason)
    local amount = tonumber(cfg('Billing')[key]) or 0
    if amount <= 0 or type(p) ~= 'table' or p.kind ~= 'player' then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local target = p.src or p.identifier
    if not target then return end
    local ok, err = pcall(NZA.Billing.Charge, target, amount, reason or L('bill_' .. key), { medic = src, kind = 'xray_' .. tostring(key) })
    if not ok then NZA.Warn('xray billing failed: ' .. tostring(err)) end
end

local function viewLabel(view)
    return L('view_' .. tostring(view))
end

local function boneLabel(bone)
    local key = 'core.bone_' .. tostring(bone)
    local s = NZA.L(key)
    if s == key then return tostring(bone) end
    return s
end

local function fractureLabel(kind)
    local key = 'core.fracture_' .. tostring(kind)
    local s = NZA.L(key)
    if s == key then return L('fracture') end
    return s
end

local function sideOfSpot(inj)
    local R = NZA.Const.Region[inj.region]
    if R and R.side == 'l' then return 'left' end
    if R and R.side == 'r' then return 'right' end
    -- front view: low x is the patient's right
    return ((inj.spot and tonumber(inj.spot.x)) or 0.5) < 0.5 and 'right' or 'left'
end

-- the patient's right is on the viewer's left on an AP film
local function apSideX(side, dx)
    if side == 'right' then return 0.5 - dx end
    return 0.5 + dx
end

-- ════════════════════════════════════════════════════════════════════════
-- FILM LAYOUT
-- Image space: x 0..1 left → right as the film hangs on the viewer, y 0..1 top → bottom.
-- AP films: the patient's right is on the viewer's left. Lateral films: anterior on the left.
-- The NUI (html/apps/xray/app.js, ANAT) draws the anatomy with the same numbers.
-- ════════════════════════════════════════════════════════════════════════

local LIMB = {
    leg = {
        ap  = { femur = { 0.535, 0.075, 0.505, 0.465 }, tibia = { 0.505, 0.515, 0.500, 0.855 }, fibula = { 0.448, 0.530, 0.452, 0.850 } },
        lat = { femur = { 0.520, 0.075, 0.500, 0.465 }, tibia = { 0.500, 0.515, 0.520, 0.840 }, fibula = { 0.535, 0.530, 0.548, 0.835 } },
        width = 0.20, thick = 140, upper = 'femur', lower = 'tibia',
    },
    arm = {
        ap  = { humerus = { 0.500, 0.070, 0.505, 0.430 }, radius = { 0.468, 0.480, 0.452, 0.790 }, ulna = { 0.542, 0.470, 0.535, 0.790 } },
        lat = { humerus = { 0.500, 0.070, 0.500, 0.430 }, radius = { 0.488, 0.480, 0.470, 0.790 }, ulna = { 0.515, 0.470, 0.522, 0.790 } },
        width = 0.16, thick = 90, upper = 'humerus', lower = 'radius',
    },
}

local BONE_AXIS = {
    femur = 'femur', tibia = 'tibia', tibia_fibula = 'tibia', fibula = 'fibula',
    humerus = 'humerus', radius = 'radius', radius_ulna = 'radius', ulna = 'ulna',
}

local function along(seg, t, mirror)
    local x = seg[1] + (seg[3] - seg[1]) * t
    local y = seg[2] + (seg[4] - seg[2]) * t
    if mirror then x = 1 - x end
    return { x = r3(x), y = r3(y) }
end

-- vertebra centres
local function cLevel(level)       -- neck view, C2..C7 (+ T1 = 8)
    local y = 0.20 + (level - 2) * 0.095
    local latX = ({ [2] = 0.50, [3] = 0.47, [4] = 0.455, [5] = 0.45, [6] = 0.455, [7] = 0.47, [8] = 0.49 })[level] or 0.47
    return { x = 0.5, y = r3(y) }, { x = latX, y = r3(y) }
end

local function tLevel(level)       -- chest view, T1..T12
    local y = 0.13 + (level - 1) * 0.055
    local latX = 0.70 + 0.03 * math.sin(math.pi * (level - 1) / 11)
    return { x = 0.5, y = r3(y) }, { x = r3(latX), y = r3(y) }
end

local function lLevel(level)       -- abdomen view, L1..L5
    local y = 0.14 + (level - 1) * 0.085
    local latX = 0.64 - 0.03 * math.sin(math.pi * (level - 1) / 4)
    return { x = 0.5, y = r3(y) }, { x = r3(latX), y = r3(y) }
end

-- where a fracture of this bone shows on the AP and the lateral film
local function fracturePos(inj, view, seed)
    local f = inj.fracture or {}
    local bone = f.bone or 'bone'
    local spot = inj.spot or {}
    local sy = clamp01(spot.y or hrand(seed, 1))
    local side = sideOfSpot(inj)
    local h = hrand(seed, 2)

    if view == 'l_leg' or view == 'r_leg' or view == 'l_arm' or view == 'r_arm' then
        local lay = (view == 'l_leg' or view == 'r_leg') and LIMB.leg or LIMB.arm
        local axis = BONE_AXIS[bone]
        if not axis or not lay.ap[axis] then
            local upper = inj.region:find('upper') ~= nil
            axis = upper and lay.upper or lay.lower
        end
        local t = 0.14 + sy * 0.72
        local mirror = view:sub(1, 1) == 'l'
        return along(lay.ap[axis], t, mirror), along(lay.lat[axis], t, false), { axis = axis, t = r3(t) }
    end

    if view == 'neck' or bone == 'c_spine' then
        local level = 2 + math.floor(sy * 5.99)
        local ap, lat = cLevel(level)
        return ap, lat, { level = level }
    end

    if view == 'chest' then
        if bone == 't_spine' then
            local level = 1 + math.floor(sy * 11.99)
            local ap, lat = tLevel(level)
            return ap, lat, { level = level }
        elseif bone == 'sternum' then
            return { x = 0.5, y = r3(0.2 + sy * 0.25) }, { x = r3(0.2 - 0.04 * sy), y = r3(0.17 + 0.35 * sy) }, {}
        elseif bone == 'clavicle' then
            local u = 0.3 + 0.5 * h
            return { x = r3(apSideX(side, 0.04 + 0.26 * u)), y = r3(0.165 - 0.045 * u) }, { x = 0.3, y = 0.13 }, {}
        elseif bone == 'scapula' then
            return { x = r3(apSideX(side, 0.31)), y = 0.27 }, { x = 0.62, y = 0.30 }, {}
        end
        -- ribs: rib 3..9, lateral arc
        local rib = 3 + math.floor(sy * 6.99)
        local y = 0.12 + rib * 0.055
        return { x = r3(apSideX(side, 0.25 + 0.05 * h)), y = r3(y) }, { x = r3(0.30 + 0.35 * h), y = r3(y + 0.03) }, { rib = rib }
    end

    if view == 'abdomen' then
        if bone == 'l_spine' then
            local level = 1 + math.floor(sy * 4.99)
            local ap, lat = lLevel(level)
            return ap, lat, { level = level }
        elseif bone == 'acetabulum' then
            return { x = r3(apSideX(side, 0.19)), y = 0.74 }, { x = 0.45, y = 0.75 }, {}
        elseif bone == 'sacrum' then
            return { x = r3(apSideX(side, 0.035)), y = 0.66 }, { x = 0.74, y = 0.66 }, {}
        end
        -- pelvic ring: pubic ramus or iliac wing
        if h < 0.55 then
            return { x = r3(apSideX(side, 0.11)), y = 0.84 }, { x = 0.30, y = 0.84 }, { site = 'ramus' }
        end
        return { x = r3(apSideX(side, 0.26)), y = 0.60 }, { x = 0.60, y = 0.58 }, { site = 'wing' }
    end

    if view == 'head' then
        if bone == 'mandible' then return { x = r3(apSideX(side, 0.19)), y = 0.76 }, { x = 0.30, y = 0.78 }, {} end
        if bone == 'orbit' then return { x = r3(apSideX(side, 0.14)), y = 0.47 }, { x = 0.24, y = 0.46 }, {} end
        if bone == 'nasal' then return { x = 0.5, y = 0.56 }, { x = 0.13, y = 0.52 }, {} end
        if bone == 'zygoma' then return { x = r3(apSideX(side, 0.26)), y = 0.55 }, { x = 0.32, y = 0.55 }, {} end
        -- skull vault
        local sx = clamp01(spot.x or h)
        local x = 0.5 + (sx - 0.5) * 0.6
        local k = (x - 0.5) / 0.37
        local y = 0.42 - 0.36 * math.sqrt(math.max(0, 1 - k * k)) + 0.025
        local a = math.rad(200 + 140 * hrand(seed, 3))
        local lx = 0.53 + 0.39 * math.cos(a) * 0.94
        local ly = 0.40 + 0.32 * math.sin(a) * 0.94
        return { x = r3(x), y = r3(y) }, { x = r3(lx), y = r3(ly) }, {}
    end

    return { x = 0.5, y = 0.5 }, { x = 0.5, y = 0.5 }, {}
end

-- where retained fragments show (spot = entry point seen from the front, depth = mm)
local function fragmentPos(inj, view, seed)
    local spot = inj.spot or {}
    local sx, sy = clamp01(spot.x or 0.5), clamp01(spot.y or 0.5)
    local depth = tonumber(inj.retainedDepth) or 30
    local region = inj.region

    if view == 'l_leg' or view == 'r_leg' or view == 'l_arm' or view == 'r_arm' then
        local lay = (view == 'l_leg' or view == 'r_leg') and LIMB.leg or LIMB.arm
        local axis = region:find('upper') and lay.upper or lay.lower
        local t = 0.1 + sy * 0.8
        local mirror = view:sub(1, 1) == 'l'
        local ap = along(lay.ap[axis], t, false)
        local lat = along(lay.lat[axis], t, false)
        ap.x = ap.x + (sx - 0.5) * lay.width * 0.8
        if mirror then ap.x = 1 - ap.x end
        local f = U.clamp(depth / lay.thick, 0.05, 0.95)
        lat.x = lat.x - lay.width / 2 + f * lay.width
        return { x = r3(ap.x), y = ap.y }, { x = r3(lat.x), y = lat.y }
    end

    local thick, apY0, apH, apW, latX0, latW = 230, 0.16, 0.56, 0.62, 0.14, 0.66
    if view == 'abdomen' then
        thick, apW, latX0, latW = 250, 0.6, 0.14, 0.64
        if region == 'pelvis' then apY0, apH = 0.55, 0.35 else apY0, apH = 0.12, 0.42 end
    elseif view == 'head' then
        thick, apW, latX0, latW = 190, 0.55, 0.15, 0.72
        if region == 'face' then apY0, apH = 0.45, 0.33 else apY0, apH = 0.16, 0.36 end
    elseif view == 'neck' then
        thick, apY0, apH, apW, latX0, latW = 120, 0.2, 0.6, 0.4, 0.25, 0.5
    end
    local f = U.clamp(depth / thick, 0.04, 0.96)
    local fromBack = region == 'back' or (region == 'head' and hrand(seed, 4) < 0.35)
    local latX = fromBack and (latX0 + latW - f * latW) or (latX0 + f * latW)
    local y = apY0 + sy * apH
    return { x = r3(0.5 + (sx - 0.5) * apW), y = r3(y) }, { x = r3(latX), y = r3(y + (hrand(seed, 5) - 0.5) * 0.02) }
end

-- ════════════════════════════════════════════════════════════════════════
-- FINDINGS (what the film shows - from the patient's real injuries)
-- ════════════════════════════════════════════════════════════════════════

function X.Findings(p, view)
    local out = {}
    if type(p) ~= 'table' or not X.Views[view] then return out end
    local tol = tonumber(cfg('Read').tolerance) or 0.06
    local list = {}
    for _, inj in pairs(p.injuries or {}) do list[#list + 1] = inj end
    table.sort(list, function(a, b)
        if (a.severity or 0) ~= (b.severity or 0) then return (a.severity or 0) > (b.severity or 0) end
        return tostring(a.id) < tostring(b.id)
    end)

    for _, inj in ipairs(list) do
        local R = NZA.Const.Region[inj.region]
        if R and R.xray == view then
            local seed = ('%s:%s:%s'):format(p.pid, tostring(inj.id), view)
            local treat = inj.treat or {}
            if inj.type == 'fracture' and type(inj.fracture) == 'table' then
                local f = inj.fracture
                local ap, lat, extra = fracturePos(inj, view, seed)
                local ang = math.floor(tonumber(f.angle) or 0)
                local item = {
                    k = 'fx', inj = inj.id, region = inj.region, bone = f.bone, kind = f.kind or 'closed',
                    disp = f.displaced == true and ang > 0, ang = ang,
                    phi = r3(0.15 + hrand(seed, 6) * 1.25),        -- plane of the angulation (AP share = |cos|)
                    shift = r3(0.2 + hrand(seed, 7) * 0.8),       -- sideways shift of the distal piece (0..1 of the bone width)
                    short = (f.displaced and ang > 0) and math.floor(4 + hrand(seed, 8) * 14) or 0, -- mm of overlap
                    sev = inj.severity, ap = ap, lat = lat, r = tol,
                    reduced = treat.reduced == true, cast = treat.cast == true, splint = treat.splinted == true,
                    heal = math.floor(tonumber(inj.heal) or 0),
                    label = L('finding_fx', fractureLabel(f.kind), string.lower(boneLabel(f.bone))),
                }
                for k, v in pairs(extra or {}) do item[k] = v end
                out[#out + 1] = item
            end
            if (inj.type == 'gunshot' or inj.type == 'shrapnel') and (tonumber(inj.retained) or 0) > 0 and not treat.extracted then
                local ap, lat = fragmentPos(inj, view, seed)
                out[#out + 1] = {
                    k = 'frag', inj = inj.id, region = inj.region, n = math.floor(tonumber(inj.retained) or 1),
                    depth = math.floor(tonumber(inj.retainedDepth) or 0), shape = inj.type == 'gunshot' and 'bullet' or 'shard',
                    sev = inj.severity, ap = ap, lat = lat, r = tol,
                    rot = r3(hrand(seed, 9) * math.pi),
                    label = L('finding_frag', math.floor(tonumber(inj.retained) or 1), math.floor(tonumber(inj.retainedDepth) or 0)),
                }
            end
        end
    end

    if view == 'chest' then
        local cond = p.conditions or {}
        local h = cond.haemothorax
        if type(h) == 'table' and (tonumber(h.ml) or 0) >= HEMO_MIN then
            local frac = U.clamp((tonumber(h.ml) or 0) / 1500, 0.1, 1)
            local top = 0.73 - 0.42 * frac
            local side = h.side == 'left' and 'left' or 'right'
            out[#out + 1] = {
                k = 'hemo', side = side, ml = math.floor(tonumber(h.ml) or 0), top = r3(top),
                ap = { x = side == 'right' and 0.27 or 0.73, y = r3((top + 0.76) / 2) },
                lat = { x = 0.62, y = r3(0.74 - 0.15 * frac) },
                r = r3(math.max(tol * 1.6, (0.76 - top) / 2 + 0.04)),
                label = L('finding_hemo', L('side_' .. side)),
            }
        end
        local px = cond.pneumothorax
        if type(px) == 'table' and ((tonumber(px.size) or 0) >= PTX_MIN or px.tension) then
            local side = px.side == 'left' and 'left' or 'right'
            out[#out + 1] = {
                k = 'ptx', side = side, size = math.floor(tonumber(px.size) or 20), tension = px.tension == true,
                ap = { x = side == 'right' and 0.2 or 0.8, y = 0.3 },
                lat = { x = 0.3, y = 0.32 },
                r = r3(tol * 1.7),
                label = L(px.tension and 'finding_ptx_tension' or 'finding_ptx', L('side_' .. side)),
            }
        end
    end

    for i, f in ipairs(out) do f.id = 'f' .. i end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- FILMS
-- ════════════════════════════════════════════════════════════════════════

local function nextFilmId()
    local start = math.floor(tonumber(cfg().filmStart) or 2034)
    local n = GetResourceKvpInt('nza_xray_film')
    if not n or n < start then n = start - 1 end
    n = n + 1
    SetResourceKvpInt('nza_xray_film', n)
    return ('%s%d'):format(cfg().filmPrefix or 'A', n), n
end

local function hospitalLabel(src)
    local rec = NZA.Staff and NZA.Staff.Get and NZA.Staff.Get(src) or nil
    local id = type(rec) == 'table' and rec.hospital or nil
    if id and NZA.Hospitals and type(NZA.Hospitals.Get) == 'function' then
        local ok, h = pcall(NZA.Hospitals.Get, id)
        if ok and type(h) == 'table' then return h.label or h.name end
    end
    return nil
end

function X.Film(p, view, quality, src)
    local id, n = nextFilmId()
    local findings = X.Findings(p, view)
    local sev = 0
    for _, f in ipairs(findings) do sev = math.max(sev, tonumber(f.sev) or 2) end
    local now = os.time()
    local meta = {
        id = id, pid = p.pid, name = p.name or '?', sex = p.sex, age = p.age,
        view = view, viewLabel = viewLabel(view), taken = now,
        by = src and core().Name and core().Name(src) or nil,
        hospital = src and hospitalLabel(src) or nil,
        quality = quality or 'sharp', seed = n, sev = sev,
        findings = findings,
        label = L('film_label', viewLabel(view)),
        description = L('film_desc', id, p.name or '?', os.date('%d/%m/%Y %H:%M', now)),
    }
    films[id] = meta
    return meta
end

-- a film of this patient that shows this injury (any injury when injId is nil) and nobody read yet:
-- the care plan's 'Read the X-ray' step
function X.PendingFilm(pid, injId)
    for _, m in pairs(films) do
        if m.pid == pid and not m.read then
            if injId == nil then return m.id end
            for _, f in ipairs(m.findings or {}) do
                if f.inj == injId then return m.id end
            end
        end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════════
-- WHERE IS EVERYONE
-- ════════════════════════════════════════════════════════════════════════

local function hospitalPoints(kind)
    local H = NZA.Hospitals
    if not (H and type(H.Points) == 'function') then return nil end
    local ok, list = pcall(H.Points, kind)
    if not ok or type(list) ~= 'table' then return nil end
    return list
end

function X.OnTable(p)
    local bed = p.meta and p.meta.bed
    if type(bed) == 'table' and bed.type == 'xray' then return true, bed.point end
    local list = hospitalPoints('xray')
    if not list then return false end
    local coords = NZA.Patients.Coords and NZA.Patients.Coords(p) or nil
    if not coords then return false end
    local radius = tonumber(cfg('Take').tableRadius) or 1.6
    for _, pt in pairs(list) do
        if type(pt) == 'table' and pt.coords and U.dist(pt.coords, coords) <= radius then return true, pt.id end
    end
    return false
end

function X.NearLightbox(src)
    local list = hospitalPoints('lightbox')
    if not list then return true end    -- no hospital module: the client checked the point
    local coords = core().SrcCoords and core().SrcCoords(src) or nil
    if not coords then return false end
    local dist = tonumber(cfg('Read').lightboxDistance) or 3.0
    for _, pt in pairs(list) do
        if type(pt) == 'table' and pt.coords and U.dist(pt.coords, coords) <= dist + 1.0 then return true end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════
-- TAKING AN X-RAY (procedure 'xray')
-- ════════════════════════════════════════════════════════════════════════

local function filmCount(src)
    local name = itemName('xray_film')
    if not name then return 0 end
    local n = core().B and core().B('Inv.Count', src, name) or 0
    return tonumber(n) or 0
end

local function conscious(p)
    local avpu = p.vitals and p.vitals.avpu or 'A'
    return p.state == 'alive' or avpu == 'A' or avpu == 'V'
end

do
    local tc = cfg('Take')
    NZA.Proc.Register('xray', {
        perm = tc.perm or 'xray',
        label = L('take_title'),
        maxDist = tonumber(tc.maxDist) or 7.0,
        minTime = tonumber(tc.minTime) or 5,
        maxTime = tonumber(tc.maxTime) or 90,
        easyTime = tonumber(tc.easyTime) or 6,
        states = tc.states or { alive = true, wounded = true },
        record = true,

        onStart = function(src, p, payload, info)
            local c = cfg('Take')
            local view = type(payload) == 'table' and payload.view or nil
            if type(view) ~= 'string' or not X.Views[view] then return false, fail('view') end
            if not itemName('xray_film') then return false, fail('inventory') end
            local cd = (tonumber(c.cooldown) or 4) * 1000
            if lastTake[src] and GetGameTimer() - lastTake[src] < cd then return false, fail('cooldown') end
            local maxFilms = tonumber(c.maxFilms) or 0
            if maxFilms > 0 and filmCount(src) >= maxFilms then return false, fail('carry') end
            if core().Has and core().Has('Inv.CanCarry') then
                local okCarry = core().B('Inv.CanCarry', src, itemName('xray_film'), 1)
                if okCarry == false then return false, fail('carry') end
            end
            local easy = type(info) == 'table' and info.easy == true
            if not easy and c.requireTable ~= false and not X.OnTable(p) then return false, fail('table') end
            local set = (c.settings or {})[view] or { 70, 10 }
            return true, {
                view = view, viewLabel = viewLabel(view), name = p.name, sex = p.sex, age = p.age,
                kv = set[1], mas = set[2],
                breath = c.breathHold ~= false and BREATH_VIEWS[view] == true and conscious(p),
                breathWindow = tonumber(c.breathWindow) or 5,
                stepBack = tonumber(c.stepBack) or 0,
            }
        end,

        onFinish = function(src, p, session, result)
            local view = session.payload and session.payload.view
            local data = session.data or {}
            lastTake[src] = GetGameTimer()
            local quality = 'sharp'
            if not result.easy and data.breath and result.breath ~= true then quality = 'motion' end
            local meta = X.Film(p, view, quality, src)
            local ok = core().B and core().B('Inv.AddItem', src, itemName('xray_film'), 1, meta)
            if not ok then
                films[meta.id] = nil
                return { msg = L('err_inventory'), failed = true, record = L('record_take_failed', viewLabel(view)) }
            end
            -- the care steps move on to 'Read the X-ray'
            if NZA.Patients.Touch then NZA.Patients.Touch(p) end
            X.Bill(src, p, 'take', L('bill_take', viewLabel(view)))
            if p.kind == 'player' and p.src and p.src ~= src and cfg('Take').notifyPatient ~= false then
                X.Notify(p.src, L('take_patient', viewLabel(view)), 'info')
            end
            NZA.Bus.Emit('xray:taken', src, p, meta)
            return {
                msg = L(quality == 'motion' and 'take_done_motion' or 'take_done', meta.id, viewLabel(view)),
                film = { id = meta.id, view = view, viewLabel = viewLabel(view), quality = quality, count = #meta.findings },
                record = L('record_take', viewLabel(view), meta.id),
            }
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- READING (lightbox)
-- ════════════════════════════════════════════════════════════════════════

local function validFilm(meta)
    return type(meta) == 'table' and type(meta.id) == 'string' and X.Views[meta.view] and type(meta.findings) == 'table'
end

-- plain copy for the NUI (no functions, no vectors)
local function clientFilm(meta)
    local out = {}
    for k, v in pairs(meta) do
        if type(v) ~= 'function' then out[k] = v end
    end
    out.dateText = meta.taken and os.date('%d/%m/%Y %H:%M', meta.taken) or ''
    out.regionLabel = viewLabel(meta.view)
    return out
end

local function findFilmSlot(src, slot, id)
    local item = core().B and core().B('Inv.GetSlot', src, slot) or nil
    if type(item) == 'table' and item.name == itemName('xray_film') and type(item.metadata) == 'table'
        and (not id or item.metadata.id == id) then
        return item
    end
    -- the slot moved (inventory sorted): search by film id
    if id then
        local list = core().B and core().B('Inv.Search', src, itemName('xray_film')) or nil
        if type(list) == 'table' then
            for _, it in pairs(list) do
                if type(it) == 'table' and type(it.metadata) == 'table' and it.metadata.id == id then return it end
            end
        end
    end
    return nil
end

function X.OpenFilm(src, slot, item)
    local rc = cfg('Read')
    item = item or findFilmSlot(src, slot)
    if type(item) ~= 'table' or not validFilm(item.metadata) then return fail('film') end
    if core().Rate and not core().Rate('nza:xray:open', src, 2, 2000) then return fail('rate') end
    local mode
    if can(src, rc.perm or 'xray') then
        mode = 'read'
    elseif rc.viewWithoutPerm ~= false then
        mode = 'view'
    else
        return fail('perm')
    end
    local easy = mode == 'read' and X.Easy(src, rc.perm or 'xray')
    local near = X.NearLightbox(src)
    if mode == 'read' and not easy and rc.requireLightbox ~= false and not near then return fail('lightbox') end
    local old = reads[src]
    local last = old and old.endedAt or reads['cd:' .. src]
    if mode == 'read' and type(last) == 'number' and GetGameTimer() - last < (tonumber(rc.cooldown) or 6) * 1000 then
        return fail('cooldown')
    end
    local token = U.uid('xr')
    reads[src] = {
        token = token, slot = item.slot, film = item.metadata, id = item.metadata.id, mode = mode,
        easy = easy, startedAt = GetGameTimer(),
    }
    return {
        ok = true, token = token, mode = mode, easy = easy,
        easyTime = tonumber(rc.easyTime) or 8, minTime = tonumber(rc.minTime) or 8,
        tolerance = tonumber(rc.tolerance) or 0.06, film = clientFilm(item.metadata),
        measureTolerance = tonumber(rc.measureTolerance) or 5,
    }
end

function X.UseFilm(src, item)
    local res = X.OpenFilm(src, item and item.slot, item)
    if not res.ok then
        X.Notify(src, res.msg, 'error', L('read_title'))
        return
    end
    TriggerClientEvent('nza:xray:read', src, res)
end

local function sanitizeMarks(list)
    local out = {}
    if type(list) ~= 'table' then return out end
    for i = 1, math.min(#list, 12) do
        local m = list[i]
        if type(m) == 'table' then
            local x, y = tonumber(m.x), tonumber(m.y)
            if x and y and x == x and y == y then out[#out + 1] = { x = U.clamp(x, 0, 1), y = U.clamp(y, 0, 1) } end
        end
    end
    return out
end

-- film units: y is 1.25× longer than x (4:5 film), distances are measured in film widths
local function dist2(a, b)
    local dx, dy = (a.x or 0) - (b.x or 0), ((a.y or 0) - (b.y or 0)) * 1.25
    return math.sqrt(dx * dx + dy * dy)
end

-- greedy nearest matching of pins to findings on one film → hits[findingIndex] = distance/tol, unmatched pins
local function match(findings, pins, key, tol)
    local pairsList = {}
    for fi, f in ipairs(findings) do
        local pos = f[key]
        local r = math.max(tonumber(f.r) or tol, tol)
        if type(pos) == 'table' then
            for pi, pin in ipairs(pins) do
                local d = dist2(pos, pin)
                if d <= r then pairsList[#pairsList + 1] = { fi = fi, pi = pi, d = d / r } end
            end
        end
    end
    table.sort(pairsList, function(a, b) return a.d < b.d end)
    local hits, usedPin = {}, {}
    for _, m in ipairs(pairsList) do
        if hits[m.fi] == nil and not usedPin[m.pi] then
            hits[m.fi] = m.d
            usedPin[m.pi] = true
        end
    end
    local unmatched = 0
    for pi = 1, #pins do if not usedPin[pi] then unmatched = unmatched + 1 end end
    return hits, unmatched
end

-- projected angulation on one film
local function projectedAngle(f, film)
    local ang = tonumber(f.ang) or 0
    local phi = tonumber(f.phi) or 0.6
    if film == 'lat' then return math.floor(ang * math.abs(math.sin(phi)) + 0.5) end
    return math.floor(ang * math.abs(math.cos(phi)) + 0.5)
end

function X.Score(film, res, easy)
    local rc = cfg('Read')
    local tol = tonumber(rc.tolerance) or 0.06
    local findings = film.findings or {}
    local rows = {}
    local out = { rows = rows, falsePins = 0 }
    res = type(res) == 'table' and res or {}

    if easy then
        for _, f in ipairs(findings) do
            rows[#rows + 1] = { id = f.id, k = f.k, label = f.label, ap = true, lat = true, confirmed = true, inj = f.inj }
        end
        out.score = (Config.EasyMode and Config.EasyMode.score) or 78
        return out
    end

    local marks = type(res.marks) == 'table' and res.marks or {}
    local ap, lat = sanitizeMarks(marks.ap), sanitizeMarks(marks.lat)
    local normal = res.normal == true

    if #findings == 0 then
        local wrong = #ap + #lat
        out.falsePins = wrong
        out.normalCall = true
        out.score = U.clamp(100 - wrong * (tonumber(rc.falsePin) or 12) * 2, 0, 100)
        return out
    end

    local hitsAp, freeAp = match(findings, ap, 'ap', tol)
    local hitsLat, freeLat = match(findings, lat, 'lat', tol)
    local credit = 0
    for i, f in ipairs(findings) do
        local a, l = hitsAp[i], hitsLat[i]
        local c = 0
        if a then c = c + 0.5 * (1 - 0.35 * a) end
        if l then c = c + 0.5 * (1 - 0.35 * l) end
        credit = credit + c
        rows[#rows + 1] = {
            id = f.id, k = f.k, label = f.label, inj = f.inj,
            ap = a ~= nil, lat = l ~= nil, confirmed = a ~= nil and l ~= nil,
        }
    end
    local score = 100 * credit / #findings
    out.falsePins = freeAp + freeLat
    score = score - out.falsePins * (tonumber(rc.falsePin) or 12)
    if normal then score = 0 end

    -- angle measurement of the worst displaced fracture
    local m = type(res.measure) == 'table' and res.measure or nil
    if m and tonumber(m.angle) then
        local best = nil
        for _, f in ipairs(findings) do
            if f.k == 'fx' and f.disp then best = f break end
        end
        if best then
            local filmKey = m.film == 'lat' and 'lat' or 'ap'
            local truth = projectedAngle(best, filmKey)
            local yours = math.floor(U.clamp(tonumber(m.angle), 0, 180) + 0.5)
            out.measure = { yours = yours, truth = truth, film = filmKey, ok = math.abs(yours - truth) <= (tonumber(rc.measureTolerance) or 5) }
            if out.measure.ok then score = score + (tonumber(rc.measureBonus) or 8) end
        end
    end
    out.score = math.floor(U.clamp(score, 0, 100) + 0.5)
    return out
end

local function groupOf(region)
    local R = NZA.Const.Region[region or '']
    return R and R.group or nil
end

local function applyReading(src, s, outcome)
    local film = s.film
    local p = NZA.Patients.Get(film.pid)
    if not p then
        outcome.offline = true
        return nil
    end
    local rc = cfg('Read')
    local confirmOk = s.easy or (outcome.score or 0) >= (tonumber(rc.confirmScore) or 50)
    local applied = 0
    local byId = {}
    for _, f in ipairs(film.findings or {}) do byId[f.id] = f end
    local F = NZA.Findings

    for _, row in ipairs(outcome.rows or {}) do
        local f = byId[row.id]
        if f and (row.ap or row.lat) then
            local confirmed = row.confirmed and confirmOk
            if f.inj and p.injuries and p.injuries[f.inj] then
                local patch = { treat = { xray = true }, quality = { xray = outcome.score } }
                if confirmed then
                    patch.treat.xrayMarked = true
                    if f.k == 'frag' then
                        patch.xrayMap = { film = film.id, view = film.view, ap = f.ap, lat = f.lat, depth = f.depth, n = f.n, at = os.time() }
                    end
                end
                NZA.Patients.UpdateInjury(p.pid, f.inj, patch)
                if confirmed then
                    applied = applied + 1
                    if F and type(F.Add) == 'function' then
                        pcall(F.Add, p.pid, 'xray_' .. tostring(f.inj), {
                            injury = f.inj, region = f.region, group = groupOf(f.region), source = 'xray',
                            text = L('finding_text', film.id, f.label), by = src,
                        })
                    end
                end
            elseif (f.k == 'hemo' or f.k == 'ptx') and confirmed then
                local cond = f.k == 'hemo' and 'haemothorax' or 'pneumothorax'
                if p.conditions and p.conditions[cond] then
                    applied = applied + 1
                    if F and type(F.Add) == 'function' then
                        pcall(F.Add, p.pid, cond .. '_suspected_' .. f.side, {
                            cond = cond, side = f.side, group = 'chest', source = 'xray',
                            text = L('finding_text', film.id, f.label), by = src,
                        })
                    end
                end
            end
        end
    end
    outcome.applied = applied
    return p
end

lib.callback.register('nza:xray:read:finish', function(src, token, res)
    local s = reads[src]
    if not s or s.token ~= token then return fail('session') end
    local rc = cfg('Read')
    local elapsed = (GetGameTimer() - s.startedAt) / 1000
    if s.mode == 'view' then
        reads[src] = nil
        return { ok = true, outcome = { view = true } }
    end
    local need = s.easy and (tonumber(rc.easyTime) or 8) or (tonumber(rc.minTime) or 8)
    if elapsed + 1.0 < need then return fail('too_fast') end
    reads[src] = nil
    reads['cd:' .. src] = GetGameTimer()
    if elapsed > (tonumber(rc.maxTime) or 600) + 5 then return fail('expired') end

    -- the film must still be in the medic's inventory
    local item = findFilmSlot(src, s.slot, s.id)
    if not item then return fail('film') end
    local film = item.metadata

    local outcome = X.Score(film, res, s.easy)
    outcome.grade = U.Grade(outcome.score)
    outcome.easy = s.easy or nil
    local p = applyReading(src, s, outcome)

    -- the film remembers its reading
    local meta = U.deepcopy(film)
    meta.read = { by = core().Name and core().Name(src) or '?', score = outcome.score, grade = outcome.grade, at = os.time(), confirmed = outcome.applied or 0 }
    if film.id and films[film.id] then films[film.id].read = meta.read end
    if core().Has and core().Has('Inv.SetMetadata') and item.slot then
        core().B('Inv.SetMetadata', src, item.slot, meta)
    end

    local confirmed, total = 0, #(film.findings or {})
    for _, r in ipairs(outcome.rows) do if r.confirmed then confirmed = confirmed + 1 end end
    if total == 0 then
        outcome.msg = (outcome.falsePins or 0) == 0 and L('read_normal_ok') or L('read_normal_wrong', outcome.falsePins)
    elseif outcome.offline then
        outcome.msg = L('read_offline')
    elseif confirmed == total then
        outcome.msg = L('read_all', confirmed)
    elseif confirmed > 0 then
        outcome.msg = L('read_some', confirmed, total)
    else
        outcome.msg = L('read_none', total)
    end
    if p then
        X.Bill(src, p, 'read', L('bill_read', viewLabel(film.view)))
        if NZA.Records and NZA.Records.Add then
            NZA.Records.Add(p, { medic = src, action = 'xray_read', summary = L('record_read', viewLabel(film.view), film.id, outcome.score, confirmed, total) })
        end
    end
    NZA.Bus.Emit('xray:read', src, p, film, outcome)
    return { ok = true, outcome = outcome }
end)

RegisterNetEvent('nza:xray:read:cancel', function(token)
    local src = source
    local s = reads[src]
    if s and s.token == token then
        reads[src] = nil
        if s.mode == 'read' then reads['cd:' .. src] = GetGameTimer() end
    end
end)

lib.callback.register('nza:xray:films', function(src)
    if core().Rate and not core().Rate('nza:xray:films', src, 3, 2000) then return {} end
    local name = itemName('xray_film')
    local list = name and core().B and core().B('Inv.Search', src, name) or nil
    local out = {}
    if type(list) ~= 'table' then return out end
    for _, it in pairs(list) do
        local m = type(it) == 'table' and it.metadata or nil
        if validFilm(m) then
            out[#out + 1] = {
                slot = it.slot, id = m.id, view = m.view, viewLabel = viewLabel(m.view), name = m.name,
                taken = m.taken and os.date('%d/%m %H:%M', m.taken) or '', read = type(m.read) == 'table' and m.read.grade or nil,
            }
        end
    end
    table.sort(out, function(a, b) return tostring(a.id) > tostring(b.id) end)
    return out
end)

lib.callback.register('nza:xray:open', function(src, slot)
    slot = tonumber(slot)
    if not slot then return fail('film') end
    return X.OpenFilm(src, slot, nil)
end)

-- ════════════════════════════════════════════════════════════════════════
-- HELP OFF THE TABLE
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:xray:offTable', function(src, target)
    if core().Rate and not core().Rate('nza:xray:off', src, 2, 2000) then return fail('rate') end
    local p = NZA.Patients.Resolve(target)
    if not p then return fail('no_patient') end
    local oc = cfg('OffTable')
    local allowed = oc.perm and can(src, oc.perm) or (can(src, 'xray') or can(src, 'transport'))
    if not allowed then return fail('perm') end
    if (core().DistanceTo and core().DistanceTo(src, p) or 0) > 4.0 then return fail('too_far') end
    if p.state ~= 'alive' then
        local okStand = NZA.Patients.CanStand and NZA.Patients.CanStand(p.pid)
        if not okStand then return fail('stand') end
    end
    local bed = p.meta and p.meta.bed
    local T = NZA.Transport
    -- stable but still down: on their feet like 'Help up' (Free only stands up alive patients)
    if p.state == 'wounded' then
        NZA.Patients.SetState(p, 'alive', 'helped_up')
        if p.kind == 'player' and p.src then
            TriggerClientEvent('nza:revived', p.src, { reason = 'helped_up' })
            NZA.Patients.Sync(p)
        end
    end
    if T and type(T.Free) == 'function' then
        pcall(T.Free, p)                      -- the transport module stands the patient up beside the table
        NZA.Bus.Emit('xray:offTable', src, p)
        return { ok = true, player = p.kind == 'player', net = p.net, transport = true }
    else
        if type(bed) == 'table' and bed.point and NZA.Hospitals and type(NZA.Hospitals.ReleaseBed) == 'function' then
            pcall(NZA.Hospitals.ReleaseBed, bed.point)
        end
        NZA.Patients.SetMeta(p.pid, 'bed', nil)
        NZA.Patients.SetMeta(p.pid, 'inBed', nil)
    end
    if p.kind == 'player' and p.src then
        TriggerClientEvent('nza:xray:standUp', p.src, { medic = core().Name and core().Name(src) or '' })
    end
    NZA.Bus.Emit('xray:offTable', src, p)
    return { ok = true, player = p.kind == 'player', net = p.net }
end)

-- ════════════════════════════════════════════════════════════════════════
-- USABLE FILM + CLEANUP
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    local name = itemName('xray_film')
    if not name then return end
    local deadline = GetGameTimer() + 30000
    while not (Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function') and GetGameTimer() < deadline do
        Wait(500)
    end
    if Bridge and Bridge.Inv and type(Bridge.Inv.RegisterUsable) == 'function' then
        local ok, err = pcall(Bridge.Inv.RegisterUsable, name, function(src, item)
            X.UseFilm(src, item)
        end)
        if not ok then NZA.Warn('xray: could not register the film item: ' .. tostring(err)) end
    else
        NZA.Warn('xray: Bridge.Inv.RegisterUsable is missing - films can only be read from the lightbox')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    reads[src] = nil
    reads['cd:' .. src] = nil
    lastTake[src] = nil
end)
