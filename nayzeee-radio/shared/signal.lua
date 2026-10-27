--[[
    NAYZEEE RADIO - Shared: signal model (NZR.Signal)

    How good the link between two radios is, as one number from 0 (nothing) to 1 (clear).
    The server is the authority (it decides who hears whom and how well); the client runs
    the same functions for its own estimates (NO SIGNAL badge, jammer noise, /radiorange),
    so both sides always agree on the maths.

    Pure functions: no natives, no state. Positions may be vector3s or plain { x, y, z }
    tables; distances are worked out from the components so both work.

      NZR.Signal.Range(kind, pos, rangeMult?)  → metres
          kind = model key ('handheld' | 'fieldpro' | 'military') or 'vehicle'
          base = Config.Radios.Models[kind].range   (vehicle: Config.Vehicles.range)
                 * rangeMult (per vehicle, from the radio vehicle list; 1 when missing)
                 * (1 + clamp((pos.z - height.from) / height.per, 0, height.max))
                 * factor of every Config.Signal.DeadZones entry that contains pos
      NZR.Signal.Jam(pos, jammers?, resist?)   → 0..1, the strongest jammer at pos
          jammers = the GlobalState 'nzr_jammers' map { [id] = { t, x, y, z, h, o, e } }
                    (nil = read GlobalState.nzr_jammers when it exists)
          f = strength * (1 - smoothstep(R * core, R, dist)) inside R, result * (1 - resist)
      NZR.Signal.Quality(a, b, jammers?)       → q (0..1), jamA, jamB
          a / b = { pos, kind, resist, underwater, waterproof, rangeMult }  (see Side)
          R = (Range(a) + Range(b)) / 2, d = horizontal distance + 0.5 * vertical distance
          q = 1 - smoothstep(R * falloffStart, R, d)
          q = 0 when either side is under water without a waterproof radio
          q = q * (1 - max(jam at a, jam at b))
      NZR.Signal.Side(kind, pos, opts?)        → side table for Quality from the config
          opts = { underwater, rangeMult, resist, waterproof }  (resist/waterproof override the model)
      NZR.Signal.Tier(q)                       → 'clear' | 'weak' | 'poor' | 'lost'   (Config.Signal.tiers)
      NZR.Signal.Bars(q)                       → 0..4
      NZR.Signal.Distance(a, b)                → straight-line metres between two positions
      NZR.Signal.LinkDistance(a, b)            → horizontal + 0.5 * vertical (what Quality uses)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Signal = NZR.Signal or {}
local S = NZR.Signal

local sqrt, abs = math.sqrt, math.abs

-- Fallbacks keep the maths sane if a server owner deletes a key from the config.
local DEFAULT_RANGE = 2500.0
local DEFAULT_TIERS = { clear = 0.75, weak = 0.45, poor = 0.15 }

-- ════════════════════════════════════════════════════════════════════════
-- SMALL MATHS
-- ════════════════════════════════════════════════════════════════════════

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function smoothstep(e0, e1, x)
    if e0 == e1 then return x < e0 and 0.0 or 1.0 end
    local t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
end

local function coords(p)
    if type(p) ~= 'table' and type(p) ~= 'vector3' and type(p) ~= 'userdata' then return nil end
    local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
    if not x or not y then return nil end
    return x, y, z or 0.0
end

function S.Distance(a, b)
    local ax, ay, az = coords(a)
    local bx, by, bz = coords(b)
    if not ax or not bx then return math.huge end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return sqrt(dx * dx + dy * dy + dz * dz)
end

-- Radio waves care far more about the ground distance than about height: a rooftop
-- 40 m up should not count as 40 m further away, so the vertical part is halved.
function S.LinkDistance(a, b)
    local ax, ay, az = coords(a)
    local bx, by, bz = coords(b)
    if not ax or not bx then return math.huge end
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy) + 0.5 * abs(az - bz)
end

local function signalCfg()
    return (Config and Config.Signal) or {}
end

local function tiers()
    local t = signalCfg().tiers
    if type(t) ~= 'table' then return DEFAULT_TIERS end
    return t
end

-- ════════════════════════════════════════════════════════════════════════
-- RANGE
-- ════════════════════════════════════════════════════════════════════════

local function baseRange(kind)
    if kind == 'vehicle' then
        local v = Config and Config.Vehicles
        return tonumber(v and v.range) or DEFAULT_RANGE
    end
    local models = Config and Config.Radios and Config.Radios.Models
    local m = models and models[kind]
    return tonumber(m and m.range) or DEFAULT_RANGE
end

function S.Range(kind, pos, rangeMult)
    local range = baseRange(kind) * (tonumber(rangeMult) or 1.0)
    local x, y, z = coords(pos)
    if not x then return range end

    local h = signalCfg().height
    if type(h) == 'table' and tonumber(h.per) and tonumber(h.per) > 0 then
        local boost = clamp((z - (tonumber(h.from) or 0.0)) / h.per, 0.0, tonumber(h.max) or 0.0)
        range = range * (1.0 + boost)
    end

    local zones = signalCfg().DeadZones
    if type(zones) == 'table' then
        for i = 1, #zones do
            local zone = zones[i]
            local radius = type(zone) == 'table' and tonumber(zone.radius)
            if radius and zone.coords and S.Distance(pos, zone.coords) <= radius then
                range = range * clamp(tonumber(zone.factor) or 1.0, 0.0, 1.0)
            end
        end
    end
    return range
end

-- ════════════════════════════════════════════════════════════════════════
-- JAMMERS
-- ════════════════════════════════════════════════════════════════════════

local function jammerList(jammers)
    if type(jammers) == 'table' then return jammers end
    if GlobalState then
        local ok, list = pcall(function() return GlobalState.nzr_jammers end)
        if ok and type(list) == 'table' then return list end
    end
    return nil
end

function S.Jam(pos, jammers, resist)
    local cfg = Config and Config.Jammers
    if type(cfg) ~= 'table' or cfg.enabled == false then return 0.0 end
    local list = jammerList(jammers)
    if not list or not coords(pos) then return 0.0 end
    local types = cfg.Types or {}

    local worst = 0.0
    for _, j in pairs(list) do
        local def = type(j) == 'table' and types[j.t]
        if def then
            local radius = tonumber(def.radius) or 0.0
            local d = S.Distance(pos, j)
            if radius > 0.0 and d < radius then
                local core = clamp(tonumber(def.core) or 0.0, 0.0, 1.0)
                local f = clamp(tonumber(def.strength) or 1.0, 0.0, 1.0) * (1.0 - smoothstep(radius * core, radius, d))
                if f > worst then worst = f end
            end
        end
    end
    return worst * (1.0 - clamp(tonumber(resist) or 0.0, 0.0, 1.0))
end

-- ════════════════════════════════════════════════════════════════════════
-- QUALITY
-- ════════════════════════════════════════════════════════════════════════

function S.Side(kind, pos, opts)
    opts = opts or {}
    local m
    if kind ~= 'vehicle' then
        local models = Config and Config.Radios and Config.Radios.Models
        m = models and models[kind]
    end
    local resist = opts.resist
    if resist == nil then resist = m and m.jamResist or 0.0 end
    local waterproof = opts.waterproof
    if waterproof == nil then waterproof = (m and m.waterproof) == true end
    return {
        pos = pos,
        kind = kind,
        resist = tonumber(resist) or 0.0,
        underwater = opts.underwater == true,
        waterproof = waterproof == true,
        rangeMult = tonumber(opts.rangeMult) or 1.0,
    }
end

function S.Quality(a, b, jammers)
    if type(a) ~= 'table' or type(b) ~= 'table' then return 0.0, 0.0, 0.0 end
    if (a.underwater and not a.waterproof) or (b.underwater and not b.waterproof) then
        return 0.0, 0.0, 0.0
    end

    local R = (S.Range(a.kind, a.pos, a.rangeMult) + S.Range(b.kind, b.pos, b.rangeMult)) / 2.0
    local d = S.LinkDistance(a.pos, b.pos)
    if d == math.huge or R <= 0.0 then return 0.0, 0.0, 0.0 end

    local start = clamp(tonumber(signalCfg().falloffStart) or 0.55, 0.0, 0.99)
    local q = 1.0 - smoothstep(R * start, R, d)

    local list = jammerList(jammers)
    local jamA, jamB = 0.0, 0.0
    if list then
        jamA = S.Jam(a.pos, list, a.resist)
        jamB = S.Jam(b.pos, list, b.resist)
    end
    q = q * (1.0 - math.max(jamA, jamB))
    return clamp(q, 0.0, 1.0), jamA, jamB
end

-- ════════════════════════════════════════════════════════════════════════
-- TIERS & BARS
-- ════════════════════════════════════════════════════════════════════════

function S.Tier(q)
    q = tonumber(q) or 0.0
    local t = tiers()
    if q >= (t.clear or DEFAULT_TIERS.clear) then return 'clear' end
    if q >= (t.weak or DEFAULT_TIERS.weak) then return 'weak' end
    if q >= (t.poor or DEFAULT_TIERS.poor) then return 'poor' end
    return 'lost'
end

-- 4 clear · 3 weak · 2 poor · 1 a trace of carrier below poor · 0 nothing at all
function S.Bars(q)
    q = tonumber(q) or 0.0
    local t = tiers()
    if q >= (t.clear or DEFAULT_TIERS.clear) then return 4 end
    if q >= (t.weak or DEFAULT_TIERS.weak) then return 3 end
    if q >= (t.poor or DEFAULT_TIERS.poor) then return 2 end
    if q > 0.02 then return 1 end
    return 0
end
