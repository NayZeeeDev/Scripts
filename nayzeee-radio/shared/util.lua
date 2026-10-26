--[[
    NAYZEEE RADIO - Shared helpers

    Loaded on both sides after shared/init.lua. Frequencies are the one value every
    part of the script passes around, so they get a single way in (Parse), a single
    way to compare (Key) and a single rule for what is allowed (Valid). '155.5' typed
    on a keypad and 155.50 set by an export end up on the same channel because both
    go through here.

      NZR.Freq.Parse(v)         '155.5' | '155,5' | 155.5 → 155.5 (2 decimals) or nil
      NZR.Freq.Key(f)           155.5 → '155.50' (nil for nonsense)
      NZR.Freq.Valid(f)         inside Config.Channels.min..max
      NZR.Util.Clamp(v, lo, hi) NZR.Util.Lerp(a, b, t) NZR.Util.Smoothstep(e0, e1, x)
      NZR.Util.Copy(t)          deep copy
      NZR.Util.Count(t)         entries in a table with holes
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Freq = NZR.Freq or {}
NZR.Util = NZR.Util or {}

local F, U = NZR.Freq, NZR.Util
local floor = math.floor

-- Round to two decimals without the float drift that turns 155.5 into 155.49999
-- once it is multiplied back out.
local function round2(n)
    return floor(n * 100 + 0.5) / 100
end

function F.Parse(v)
    if type(v) == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return round2(v)
    end
    if type(v) ~= 'string' then return nil end
    v = v:gsub(',', '.'):gsub('%s', '')
    if v == '' or #v > 8 or not v:match('^%d*%.?%d*$') then return nil end
    local n = tonumber(v)
    if not n then return nil end
    return round2(n)
end

function F.Key(f)
    f = F.Parse(f)
    if not f then return nil end
    return ('%.2f'):format(f)
end

function F.Valid(f)
    f = F.Parse(f)
    if not f then return false end
    local band = Config.Channels or {}
    return f >= (band.min or 1.0) and f <= (band.max or 999.99)
end

function U.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.Lerp(a, b, t)
    return a + (b - a) * t
end

function U.Smoothstep(e0, e1, x)
    if e0 == e1 then return x < e0 and 0.0 or 1.0 end
    local t = U.Clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
end

function U.Copy(t, seen)
    if type(t) ~= 'table' then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do
        out[U.Copy(k, seen)] = U.Copy(v, seen)
    end
    return out
end

function U.Count(t)
    local n = 0
    if type(t) ~= 'table' then return 0 end
    for _ in pairs(t) do n = n + 1 end
    return n
end
