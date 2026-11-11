-- Salon geometry: where on the head each step happens.
-- Everything is in head-local unit coordinates: the head is an ellipsoid of radius 1, x = the
-- client's right, y = forward (their face), z = up. The client turns these into world points around
-- the client's head bone and projects them onto the screen every frame (client/salon.lua).
--
-- Steps in salon.lua name their geometry with a short string, 'kind:arg:arg', for example:
--   part:center            a part from the front hairline over the top to the nape
--   part:ear2ear           ear to ear over the top
--   part:side_l / side_r   a deep side part
--   part:grid:3:3          box braid parting: 3 rows x 3 columns of squares over the head
--   part:horseshoe         the leave-out section at the top of the head
--   rows:all:5             5 cornrows straight back (all | left | right | back | front)
--   rows:left:4:up         4 feed-in rows on the left half running up to the bun
--   rows:all:5:curve_l     curved rows sweeping from a left side part to the right ear (lemonade)
--   rows:all:1:halo        one braid circling the head like a crown
--   strand:back:3:1.6      3 hanging braids at the back, 1.6 head-heights long
--   point:crown / points:grid:3:3 / points:perimeter:10
--   zone:all / zone:top / zone:ends ...   sample points for sweeping (spray, mousse, heat)
--   track:6                6 weft tracks at the back, nape upwards, ear to ear
--   drag:gather / drag:puff / drag:cap / drag:lace / drag:bun_l ...

Salon = Salon or {}
local G = {}
Salon.Geo = G

local rad, sin, cos, sqrt, abs = math.rad, math.sin, math.cos, math.sqrt, math.abs

local function v(x, y, z) return { x = x, y = y, z = z } end
local function norm(p)
    local l = sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
    if l < 1e-6 then return v(0, 0, 1) end
    return v(p.x / l, p.y / l, p.z / l)
end
local function lerp(a, b, t) return v(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t) end

-- a point on the head from azimuth (0 = face, 90 = right ear, 180 = back, 270 = left ear) and elevation
local function sph(az, el)
    az, el = rad(az), rad(el)
    return v(cos(el) * sin(az), cos(el) * cos(az), sin(el))
end
G.Sph = sph

-- elevation of the hairline at an azimuth: high at the forehead, at the ears on the sides, low at the nape
local HL = { { 0, 36 }, { 45, 24 }, { 75, 6 }, { 95, -10 }, { 135, -26 }, { 180, -36 } }
local function hairEl(az)
    local a = abs(((az + 180) % 360) - 180)
    for i = 1, #HL - 1 do
        local p, q = HL[i], HL[i + 1]
        if a <= q[1] then return p[2] + (q[2] - p[2]) * (a - p[1]) / (q[1] - p[1]) end
    end
    return HL[#HL][2]
end
G.HairEl = hairEl

-- along a great circle between two head points
local function slerp(a, b, t) return norm(lerp(a, b, t)) end
local function arcPath(a, b, n)
    local out = {}
    for i = 0, n do out[#out + 1] = slerp(a, b, i / n) end
    return out
end

local function surface(p) p.s = true return p end   -- marks a point that sits on the scalp (hidden when behind it)
local function mark(list) for _, p in ipairs(list) do surface(p) end return list end

local BUN = { l = sph(-48, 66), r = sph(48, 66), c = sph(180, 72) }
local CROWN, NAPE, TOP = sph(180, 70), sph(180, -30), sph(0, 90)

local NAMED = {
    crown = CROWN, nape = NAPE, top = TOP, bun_l = BUN.l, bun_r = BUN.r, ponytail = sph(180, 50),
    front = sph(0, 40), temple_l = sph(-55, 18), temple_r = sph(55, 18), ear_l = sph(-92, -2), ear_r = sph(92, -2),
    low = sph(180, -10), side_l = sph(-120, 10), side_r = sph(120, 10),
}
G.Named = NAMED

-- parts --------------------------------------------------------------------------------------------

local function meridian(lat, t0, t1, n)
    -- a curve front-to-back, tilted sideways by lat degrees around the front-back axis
    local out, a = {}, rad(lat)
    for i = 0, n do
        local t = rad(t0 + (t1 - t0) * i / n)
        out[#out + 1] = v(sin(t) * sin(a), cos(t), sin(t) * cos(a))
    end
    return mark(out)
end

local function sagittal(lat, t0, t1, n)
    -- a front-to-back curve at a fixed distance to the side: rows side by side stay parallel
    local c = sin(rad(lat)) * 0.86
    local r = sqrt(1 - c * c)
    local out = {}
    for i = 0, n do
        local t = rad(t0 + (t1 - t0) * i / n)
        out[#out + 1] = v(c, r * cos(t), r * sin(t))
    end
    return mark(out)
end

local function coronal(u0, u1, n, tilt)
    -- ear to ear over the top; tilt pushes it forward (+) or back (-)
    local out, k = {}, rad(tilt or 0)
    for i = 0, n do
        local u = rad(u0 + (u1 - u0) * i / n)
        out[#out + 1] = norm(v(sin(u), sin(k) * cos(u), cos(u) * cos(k)))
    end
    return mark(out)
end

local function along(az0, az1, elf, n)
    -- around the head at an elevation given per azimuth
    local out = {}
    for i = 0, n do
        local az = az0 + (az1 - az0) * i / n
        out[#out + 1] = surface(sph(az, elf(az)))
    end
    return out
end

local PARTS = {
    center    = function() return { meridian(0, 38, 214, 22) } end,
    ear2ear   = function() return { coronal(-100, 100, 20, -6) } end,
    side_l    = function() return { mark(arcPath(sph(-30, 40), sph(-40, 82), 10)) } end,
    side_r    = function() return { mark(arcPath(sph(30, 40), sph(40, 82), 10)) } end,
    halves    = function() return { meridian(0, 38, 214, 22) } end,
    horseshoe = function()
        return { along(-75, 75, function(az) return 58 + 12 * cos(rad(az * 1.2)) end, 16) }
    end,
    -- the front hairline, temple to temple (cutting the excess lace)
    lace      = function() return { along(-62, 62, function(az) return hairEl(az) + 1 end, 16) } end,
    -- baby hairs: little S swirls at both temples
    edges     = function()
        local out = {}
        for _, s in ipairs({ -1, 1 }) do
            local p = {}
            for i = 0, 10 do
                local t = i / 10
                p[#p + 1] = surface(sph(s * (38 + 26 * t), hairEl(s * (38 + 26 * t)) - 3 + 4 * sin(t * math.pi * 2)))
            end
            out[#out + 1] = p
        end
        return out
    end,
    grid = function(r, c)
        r, c = tonumber(r) or 3, tonumber(c) or 3
        local out = {}
        -- rows: rings around the back half of the head at rising elevation
        for i = 1, r do
            local el = -24 + i * (88 / (r + 1))
            out[#out + 1] = along(95, 265, function() return el end, 14)
        end
        -- columns: front-back curves
        for j = 1, c do
            local lat = -60 + j * (120 / (c + 1))
            out[#out + 1] = sagittal(lat, 70, 205, 12)
        end
        return out
    end,
}

-- rows (cornrows / feed-ins) --------------------------------------------------------------------------

local SIDES = { all = { -64, 64 }, left = { -66, -10 }, right = { 10, 66 }, front = { -40, 40 }, back = { -55, 55 } }

local function rows(side, n, shape)
    n = math.max(1, tonumber(n) or 4)
    local span = SIDES[side] or SIDES.all
    local out = {}
    for i = 1, n do
        local f = n == 1 and 0.5 or (i - 1) / (n - 1)
        local lat = span[1] + (span[2] - span[1]) * f
        if shape == 'up' then
            -- from the hairline / nape on this side up to its bun
            local bun = side == 'right' and BUN.r or BUN.l
            local az = (side == 'right' and 1 or -1) * (25 + 150 * f)
            out[#out + 1] = mark(arcPath(sph(az, hairEl(az) + 4), bun, 12))
        elseif shape == 'curve_l' or shape == 'curve_r' then
            -- lemonade: from a deep side part sweeping across the head to the other ear
            local s = shape == 'curve_l' and -1 or 1
            local start = sph(s * 32, 44 + 40 * f)
            local finish = sph(-s * (100 + 70 * f), -12 - 18 * f)
            local mid = norm(lerp(start, finish, 0.5))
            mid = norm(v(mid.x, mid.y, mid.z + 0.35))
            local a, b = arcPath(start, mid, 7), arcPath(mid, finish, 7)
            for k = 2, #b do a[#a + 1] = b[k] end
            out[#out + 1] = mark(a)
        elseif shape == 'halo' then
            -- behind one ear, along the front hairline, around the other side and back
            out[#out + 1] = along(110, -250, function(az) return hairEl(az) + 9 end, 36)
        else
            out[#out + 1] = sagittal(lat, 40 + math.abs(lat) * 0.25, 212, 16)
        end
    end
    return out
end

-- hanging strands (braids, twists, locs below the head) ------------------------------------------------

local WHERE = {
    back  = function(f) return sph(180 + (f - 0.5) * 120, -24) end,
    nape  = function(f) return sph(180 + (f - 0.5) * 60, -30) end,
    left  = function(f) return sph(-110 - f * 40, -6) end,
    right = function(f) return sph(110 + f * 40, -6) end,
    top   = function(f) return sph(180 + (f - 0.5) * 70, 40) end,
    front = function(f) return sph((f - 0.5) * 110, 26) end,
    ponytail = function() return NAMED.ponytail end,
    crown = function() return CROWN end,
    bun_l = function() return BUN.l end,
    bun_r = function() return BUN.r end,
    ears  = function(f) return f < 0.5 and sph(-88, -6) or sph(88, -6) end,
}

local function strands(where, n, len)
    n, len = math.max(1, tonumber(n) or 1), tonumber(len) or 1.4
    local at = WHERE[where] or WHERE.back
    local out = {}
    for i = 1, n do
        local f = n == 1 and 0.5 or (i - 1) / (n - 1)
        local root = at(f)
        -- fall straight down, drifting away from the head a little
        local out1 = v(root.x * 1.06, root.y * 1.06, root.z)
        local path = { surface(v(root.x, root.y, root.z)) }
        for k = 1, 10 do
            local t = k / 10
            path[#path + 1] = v(out1.x * (1 + 0.12 * t), out1.y * (1 + 0.12 * t) - 0.05 * t, root.z - len * t)
        end
        out[#out + 1] = path
    end
    return out
end

-- points ------------------------------------------------------------------------------------------------

local function points(where, a, b)
    if where == 'grid' then
        local r, c, out = tonumber(a) or 3, tonumber(b) or 3, {}
        for i = 1, r do
            for j = 1, c do
                local el = -18 + (i - 0.5) * (84 / r)
                local az = 110 + (j - 0.5) * (140 / c)
                out[#out + 1] = surface(sph(az, el))
            end
        end
        return out
    elseif where == 'perimeter' then
        local n, out = tonumber(a) or 10, {}
        for i = 0, n - 1 do
            local az = i * 360 / n
            out[#out + 1] = surface(sph(az, hairEl(az) + 3))
        end
        return out
    elseif where == 'hairline' then
        local n, out = tonumber(a) or 6, {}
        for i = 0, n - 1 do
            local az = -70 + 140 * (n == 1 and 0.5 or i / (n - 1))
            out[#out + 1] = surface(sph(az, hairEl(az) + 2))
        end
        return out
    elseif where == 'ends' then
        -- the ends of hanging hair, below the head
        local n, len, out = tonumber(a) or 5, tonumber(b) or 1.6, {}
        for i = 1, n do
            local f = n == 1 and 0.5 or (i - 1) / (n - 1)
            local r = WHERE.back(f)
            out[#out + 1] = v(r.x * 1.15, r.y * 1.15 - 0.05, r.z - len)
        end
        return out
    elseif where == 'length' then
        -- down one hanging braid / ponytail: elastics, beads
        local n, len, out = tonumber(a) or 4, tonumber(b) or 1.4, {}
        local root = NAMED.ponytail
        for i = 1, n do
            local t = i / (n + 1)
            out[#out + 1] = v(root.x, root.y * (1.05 + 0.1 * t) - 0.06 * t, root.z - len * t)
        end
        return out
    elseif where == 'buns' then
        return { surface(v(BUN.l.x, BUN.l.y, BUN.l.z)), surface(v(BUN.r.x, BUN.r.y, BUN.r.z)) }
    elseif where == 'rows' then
        -- the ends of n rows at the nape (pinning cornrow tails flat)
        local n, out = tonumber(a) or 5, {}
        for i = 1, n do
            local f = n == 1 and 0.5 or (i - 1) / (n - 1)
            out[#out + 1] = surface(sph(180 + (f - 0.5) * 90, -26))
        end
        return out
    end
    local p = NAMED[where] or CROWN
    return { surface(v(p.x, p.y, p.z)) }
end

-- zones (sweeps) -----------------------------------------------------------------------------------------

local ZONES = {
    all   = { -180, 180, nil, 86 },
    top   = { -70, 70, 50, 88 },
    back  = { 110, 250, nil, 60 },
    left  = { -150, -40, nil, 60 },
    right = { 40, 150, nil, 60 },
    front = { -60, 60, nil, 70 },
    crown = { 140, 220, 50, 84 },
    leave = { -70, 70, 54, 86 },
    hairline = { -75, 75, nil, nil },
}

local function zone(name, density)
    if name == 'ends' then
        local out = {}
        for i = 0, 4 do
            for k = 0, 3 do
                local r = WHERE.back(i / 4)
                out[#out + 1] = v(r.x * 1.12, r.y * 1.12 - 0.04, r.z - 0.35 - k * 0.38)
            end
        end
        return out
    end
    local z = ZONES[name] or ZONES.all
    local out, step = {}, density or 24
    local az = z[1]
    while az <= z[2] + 0.01 do
        local lo = z[3] or (hairEl(az) + 3)
        local hi = z[4] or (hairEl(az) + 9)
        if name == 'hairline' then
            out[#out + 1] = surface(sph(az, lo))
        else
            local el = lo
            while el <= hi + 0.01 do
                out[#out + 1] = surface(sph(az, el))
                el = el + 16
            end
        end
        az = az + step
    end
    return out
end

-- weft tracks: rows of a sew-in, nape upwards, ear to ear around the back --------------------------------

local function tracks(n)
    n = tonumber(n) or 6
    local out = {}
    for i = 1, n do
        local el = -28 + (i - 1) * (78 / math.max(1, n - 1))
        local w = 95 - (i - 1) * (35 / math.max(1, n - 1))
        out[#out + 1] = along(180 - w, 180 + w, function() return el end, 12)
    end
    return out
end

-- drags: { from, to } pairs ----------------------------------------------------------------------------

local DRAGS = {
    gather = function(target)   -- sweep the hair from around the head to one spot (ponytail / bun)
        local t = NAMED[target] or NAMED.ponytail
        local out = {}
        for _, az in ipairs({ -110, -40, 40, 110, 180 }) do
            out[#out + 1] = { surface(sph(az, hairEl(az) + 6)), surface(v(t.x, t.y, t.z)) }
        end
        return out
    end,
    puff = function()           -- pull the hair between two elastics outwards into a bubble
        local out, root = {}, NAMED.ponytail
        for i = 1, 4 do
            local t = i / 5
            local c = v(root.x, root.y * 1.1 - 0.06 * t, root.z - 1.4 * t)
            out[#out + 1] = { c, v(c.x + 0.32, c.y, c.z) }
        end
        return out
    end,
    cap = function()            -- stretch the cap from the crown down over the head
        local out = {}
        for _, az in ipairs({ 0, 90, 180, 270 }) do
            out[#out + 1] = { surface(sph(az, 84)), surface(sph(az, hairEl(az) - 2)) }
        end
        return out
    end,
    lace = function()           -- lay the closure / frontal along the front hairline
        return { { surface(sph(0, 72)), surface(sph(0, 40)) }, { surface(sph(-45, 50)), surface(sph(-50, 26)) }, { surface(sph(45, 50)), surface(sph(50, 26)) } }
    end,
    halves = function()         -- split the hair down the middle into left and right
        return { { surface(sph(0, 60)), surface(sph(-70, 30)) }, { surface(sph(0, 60)), surface(sph(70, 30)) } }
    end,
    two = function()            -- split one section into two strands (twists)
        local p = NAMED.ponytail
        local s = v(p.x, p.y * 1.1, p.z - 0.4)
        return { { s, v(s.x - 0.3, s.y, s.z - 0.2) }, { s, v(s.x + 0.3, s.y, s.z - 0.2) } }
    end,
    sections = function()       -- divide into three strands (left, middle, right)
        local p = NAMED.ponytail
        local s = v(p.x, p.y * 1.1, p.z - 0.4)
        return { { s, v(s.x - 0.3, s.y, s.z - 0.15) }, { s, v(s.x, s.y - 0.1, s.z - 0.3) }, { s, v(s.x + 0.3, s.y, s.z - 0.15) } }
    end,
}

-- the parser ------------------------------------------------------------------------------------------------

local function split(s)
    local out = {}
    for part in tostring(s):gmatch('[^:]+') do out[#out + 1] = part end
    return out
end

-- returns { kind = 'paths' | 'points' | 'pairs', list = ... }
local cache = {}
function G.Build(spec)
    if type(spec) ~= 'string' then return nil end
    if cache[spec] then return cache[spec] end
    local a = split(spec)
    local k = a[1]
    local r
    if k == 'part' then
        local f = PARTS[a[2] or 'center'] or PARTS.center
        r = { kind = 'paths', list = f(a[3], a[4]) }
    elseif k == 'rows' then
        r = { kind = 'paths', list = rows(a[2], a[3], a[4]) }
    elseif k == 'strand' then
        r = { kind = 'paths', list = strands(a[2], a[3], a[4]) }
    elseif k == 'point' or k == 'points' then
        r = { kind = 'points', list = points(a[2], a[3], a[4]) }
    elseif k == 'zone' then
        r = { kind = 'points', list = zone(a[2], tonumber(a[3])) }
    elseif k == 'track' then
        r = { kind = 'paths', list = tracks(a[2]) }
    elseif k == 'drag' then
        local f = DRAGS[a[2] or 'gather'] or DRAGS.gather
        r = { kind = 'pairs', list = f(a[3]) }
    end
    cache[spec] = r
    return r
end

-- a move can use part of its geometry: from = first item (1-based), limit = how many
function G.Slice(list, from, limit)
    from = math.max(1, tonumber(from) or 1)
    local out = {}
    for i = from, #list do
        if limit and #out >= limit then break end
        out[#out + 1] = list[i]
    end
    return out
end

-- how many things a move asks for: used by the server for the least time a move can take
function G.Count(spec, from, limit)
    local g = G.Build(spec)
    if not g then return 1 end
    return math.max(1, #G.Slice(g.list, from, limit))
end

-- styles ------------------------------------------------------------------------------------------------

local byId
function Salon.Style(id)
    if not byId then
        byId = {}
        for _, s in ipairs(Config.SalonStyles or {}) do byId[s.id] = s end
    end
    return byId[id]
end

-- does this style (with these options) use extension hair?
function Salon.UsesExt(style, opts)
    return style.hair ~= nil and (not style.hair.ext or (opts and opts.ext == true))
end

local function optOn(opt, style, opts)
    if not opt then return true end
    if opt == 'ext' then return Salon.UsesExt(style, opts) end
    return opts ~= nil and opts[opt] == true
end

-- every move of a style in order, with the step it belongs to. Server and client build the same list.
function Salon.Moves(style, opts)
    local out, steps = {}, {}
    local ext = Salon.UsesExt(style, opts)
    for si, st in ipairs(style.steps) do
        if optOn(st.opt, style, opts) then
            steps[#steps + 1] = si
            for mi, m in ipairs(st.moves) do
                if optOn(m.opt, style, opts) then
                    local mv = {}
                    for k, val in pairs(m) do mv[k] = val end
                    mv.step, mv.stepNo, mv.mi = si, #steps, mi
                    mv.feed = (m.feed and ext) and (m.feed == true and 'even' or m.feed) or nil
                    if mv.seq then
                        local seq = {}
                        for i, tok in ipairs(mv.seq) do
                            -- F (feed) only when extension hair is used
                            seq[i] = (not ext and tok:sub(1, 1) == 'F') and tok:sub(2) or tok
                        end
                        mv.seq = seq
                    end
                    out[#out + 1] = mv
                end
            end
        end
    end
    return out, steps
end

-- the braid / cornrow / sew moves carry on from the previous one on the same geometry
local function geoOf(moves, i)
    for k = i, 1, -1 do
        if moves[k].geo then return moves[k].geo, moves[k] end
    end
end
Salon.GeoOf = geoOf

-- the normal time a move takes, in seconds (the server allows Config.Salon.MinTime of it)
function Salon.MoveTime(moves, i)
    local m = moves[i]
    local geo = geoOf(moves, i)
    local n = geo and G.Count(geo, m.from, m.limit) or 1
    local a = m.a
    if a == 'trace' then return 1.0 * n end
    if a == 'cornrow' then return 0.32 * (m.stitches or 6) * n end
    if a == 'braid' then return 0.28 * (m.stitches or 6) * (m.cont and 1 or n) end
    if a == 'dab' then
        if m.every then return 0.22 * math.max(1, math.min(m.limit or 99, n * 3)) end
        return 0.22 * n
    end
    if a == 'sew' then
        local g = G.Build(geo or '')
        if g and g.kind == 'points' then return 0.45 * n end
        return 0.45 * (m.stitches or 6) * n
    end
    if a == 'sweep' then return 1.6 end
    if a == 'stroke' then return 0.45 * (m.n or 1) * n end
    if a == 'circle' then return 0.7 * (m.turns or 1) * n end
    if a == 'drag' then return 0.45 * n end
    if a == 'hold' then return 0.8 * (m.n or 1) end
    return 1.0
end

-- what a style needs: tools to own, products used up, extension hair
function Salon.Needs(style, opts)
    local tools, uses, seenT, seenU = {}, {}, {}, {}
    local function use(item)
        if item and not seenU[item] then seenU[item] = true uses[#uses + 1] = item end
    end
    for _, it in ipairs(style.uses or {}) do use(it) end
    local moves = Salon.Moves(style, opts)
    for _, m in ipairs(moves) do
        local st = style.steps[m.step]
        for _, it in ipairs(st.uses or {}) do use(it) end
        local def = Config.Salon.Tools[m.tool or 'hands']
        if def and def.item then
            if def.use then use(def.item)
            elseif not seenT[def.item] then seenT[def.item] = true tools[#tools + 1] = def.item end
        end
    end
    local hair = Salon.UsesExt(style, opts) and style.hair or nil
    return { tools = tools, uses = uses, hair = hair, extra = style.extra, moves = #moves }
end

-- roughly how long a style takes, in minutes (for the Style Book)
function Salon.Minutes(style, opts)
    local moves = Salon.Moves(style, opts)
    local t = 0
    for i = 1, #moves do t = t + Salon.MoveTime(moves, i) * 3 + 6 end
    return math.max(1, math.floor(t / 60 + 0.5))
end

-- what each move does to the head, for everyone to see (props on the client's head):
--   reveal = share of the style's slices on after it (0..1), base = a look to switch to ('cornrows'),
--   cap = true (the wig cap goes on), pieces = 'clip' | 'pin' at the move's points
function Salon.Effects(style, moves)
    local out = {}
    -- the work that builds the style: the weft tracks of a sew-in, else braids / cornrows / twists / sewing
    local work = {}
    local tracks = false
    for _, m in ipairs(moves) do
        if (Salon.GeoOf(moves, _) or ''):sub(1, 6) == 'track:' then tracks = true break end
    end
    for i, m in ipairs(moves) do
        local geo = Salon.GeoOf(moves, i) or ''
        local isWork
        if tracks then isWork = geo:sub(1, 6) == 'track:' and (m.a == 'sew' or m.a == 'trace')
        else
            -- twisting / wrapping down a strand counts, a bun or a scrunch doesn't
            local twist = m.a == 'circle' and (geo:find('length', 1, true) or geo:find('grid', 1, true)) ~= nil
            isWork = (m.a == 'braid' or m.a == 'cornrow' or m.a == 'sew' or twist) and not m.base
        end
        if isWork then work[#work + 1] = i end
    end
    -- nothing braided / sewn (a bubble braid): the hair builds up over every move after the first step
    if #work == 0 then
        for i, m in ipairs(moves) do if m.stepNo > 1 then work[#work + 1] = i end end
    end
    for j, i in ipairs(work) do
        out[i] = out[i] or {}
        out[i].reveal = j / #work
        out[i].from = (j - 1) / #work   -- where this move starts, for the reveal along the way
    end
    for i, m in ipairs(moves) do
        local e = out[i] or {}
        local geo = Salon.GeoOf(moves, i) or ''
        if m.base then e.base = m.base end
        if geo == 'drag:cap' then e.cap = true end
        if m.a == 'dab' and (m.mark == 'clip' or m.mark == 'pin') then e.pieces = m.mark end
        if next(e) then out[i] = e end
    end
    return out
end
