--[[
    NAYZEEE AMBULANCE - Shared helpers (client + server)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Util = NZA.Util or {}
local U = NZA.Util

function U.round(n, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(n * m + 0.5) / m
end

function U.clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

function U.lerp(a, b, t)
    return a + (b - a) * t
end

function U.deepcopy(t, seen)
    if type(t) ~= 'table' then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[U.deepcopy(k, seen)] = U.deepcopy(v, seen) end
    return out
end

-- Shallow merge b into a (returns a)
function U.merge(a, b)
    if type(b) ~= 'table' then return a end
    for k, v in pairs(b) do a[k] = v end
    return a
end

local uidCounter = 0
function U.uid(prefix)
    uidCounter = uidCounter + 1
    return ('%s%d%03d'):format(prefix or '', os.time() % 100000, uidCounter % 1000)
end

function U.tableCount(t)
    local n = 0
    if t then for _ in pairs(t) do n = n + 1 end end
    return n
end

function U.keys(t)
    local out = {}
    if t then for k in pairs(t) do out[#out + 1] = k end end
    return out
end

-- Accepts vector3/vector4/table {x,y,z} → vector3
function U.vec(v)
    if not v then return nil end
    if type(v) == 'vector3' then return v end
    if type(v) == 'vector4' then return vector3(v.x, v.y, v.z) end
    if type(v) == 'table' then return vector3(v.x or v[1] or 0.0, v.y or v[2] or 0.0, v.z or v[3] or 0.0) end
    return nil
end

function U.dist(a, b)
    a, b = U.vec(a), U.vec(b)
    if not a or not b then return math.huge end
    return #(a - b)
end

-- 125 → "02:05"
function U.formatTime(sec)
    sec = math.max(0, math.floor(sec or 0))
    return ('%02d:%02d'):format(math.floor(sec / 60), sec % 60)
end

-- list = { { item, weight }, ... } or { [item] = weight }
function U.weightedPick(list)
    local total, entries = 0, {}
    if list[1] then
        for _, e in ipairs(list) do entries[#entries + 1] = e; total = total + (e[2] or 1) end
    else
        for k, w in pairs(list) do entries[#entries + 1] = { k, w }; total = total + w end
    end
    if total <= 0 then return nil end
    local r = math.random() * total
    for _, e in ipairs(entries) do
        r = r - (e[2] or 1)
        if r <= 0 then return e[1] end
    end
    return entries[#entries][1]
end

function U.shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- 0..100 score → letter grade
function U.Grade(score)
    score = score or 0
    if score >= 95 then return 'S' end
    if score >= 85 then return 'A' end
    if score >= 72 then return 'B' end
    if score >= 58 then return 'C' end
    if score >= 40 then return 'D' end
    return 'F'
end

function U.RandomBloodType()
    return U.weightedPick(NZA.Const.BloodFrequency) or 'O+'
end

-- 'r_lower_leg' → 'Right lower leg'
function U.RegionLabel(region)
    local r = NZA.Const.Region[region]
    return r and NZA.L('region.' .. region) ~= ('region.' .. region) and NZA.L('region.' .. region) or (r and r.label) or region
end

function U.InjuryLabel(kind)
    local t = NZA.Const.InjuryTypes[kind]
    local key = 'injury.' .. kind
    local loc = NZA.L(key)
    if loc ~= key then return loc end
    return t and t.label or kind
end
