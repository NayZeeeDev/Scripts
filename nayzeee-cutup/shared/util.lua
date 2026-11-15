function L(key, ...)
    local pack = Locales and (Locales[Config.Locale] or Locales['en']) or {}
    local str = pack[key] or (Locales and Locales['en'] and Locales['en'][key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, str, ...)
        return ok and out or str
    end
    return str
end

function Util_FormatNumber(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (n < 0 and '-' or '') .. out
end

Util = {}

function Util.Clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function Util.Lerp(a, b, t) return a + (b - a) * t end
function Util.Round(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end

function Util.AngleDiff(a, b)
    local d = (a - b + 180.0) % 360.0 - 180.0
    return d
end

function Util.LerpAngle(a, b, t)
    return a + Util.AngleDiff(b, a) * t
end

function Util.DeepCopy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Util.DeepCopy(v) end
    return o
end

-- fills missing keys of `t` from `defaults` (recursive), keeps user values
function Util.Merge(defaults, t)
    local out = Util.DeepCopy(defaults)
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        if type(v) == 'table' and type(out[k]) == 'table' then
            out[k] = Util.Merge(out[k], v)
        elseif out[k] == nil or type(out[k]) == type(v) then
            out[k] = v
        end
    end
    return out
end

function Util.WeightedPick(weights)
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    local r = math.random() * total
    for k, w in pairs(weights) do
        r = r - w
        if r <= 0 then return k end
    end
    return next(weights)
end

function Util.GetRank(points)
    points = points or 0
    local ranks = Config.Ranks
    local idx = 1
    for i = 1, #ranks do
        if points >= ranks[i].min then idx = i end
    end
    local cur, nxt = ranks[idx], ranks[idx + 1]
    local pct, toNext = 100, 0
    if nxt then
        pct = math.floor(((points - cur.min) / (nxt.min - cur.min)) * 100)
        toNext = nxt.min - points
    end
    return {
        index = idx, name = cur.name, color = cur.color,
        pct = Util.Clamp(pct, 0, 100), toNext = math.max(0, toNext),
        nextName = nxt and nxt.name or nil,
    }
end

function Util.DensityLabel(d)
    if d < 0.5 then return 'Light' elseif d < 0.9 then return 'Medium'
    elseif d < 1.2 then return 'Heavy' end
    return 'Insane'
end

Util.FormatNumber = Util_FormatNumber
Util_FormatNumber = nil
