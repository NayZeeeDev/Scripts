lib.locale(Config.Locale)

RES = GetCurrentResourceName()
IS_SERVER = IsDuplicityVersion()

Utils = {}

function Utils.debug(...)
    if not Config.Debug then return end
    print(('^5[%s]^7'):format(RES), ...)
end

function Utils.vec3(v)
    if not v then return nil end
    return vec3(v.x + 0.0, v.y + 0.0, v.z + 0.0)
end

function Utils.dist(a, b)
    return #(vec3(a.x, a.y, a.z) - vec3(b.x, b.y, b.z))
end

function Utils.round(n, d)
    local m = 10 ^ (d or 0)
    return math.floor(n * m + 0.5) / m
end

function Utils.copy(t, seen)
    if type(t) ~= 'table' then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[Utils.copy(k, seen)] = Utils.copy(v, seen) end
    return setmetatable(out, getmetatable(t))
end

function Utils.contains(list, value)
    if not list then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

function Utils.money(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

--- level, xp into level, xp needed for next level (nil at max)
function Utils.levelFromXp(xp)
    xp = xp or 0
    local levels = Config.Levels
    local level = 1
    for i = 1, #levels do
        if xp >= levels[i] then level = i else break end
    end
    local base = levels[level]
    local nextXp = levels[level + 1]
    return level, xp - base, nextXp and (nextXp - base) or nil
end

function Utils.perks(level)
    local best = Config.LevelPerks[1]
    for i = 1, #Config.LevelPerks do
        local row = Config.LevelPerks[i]
        if level >= row.level then best = row end
    end
    return best
end

--- Today's featured heist id (stable for the whole UTC day, same on every machine)
function Utils.featured()
    if not Config.Featured.enabled then return nil end
    local ids = {}
    for i = 1, #Config.Heists do
        local def = Heists and Heists.defs[Config.Heists[i]]
        if def and def.enabled ~= false then ids[#ids + 1] = def.id end
    end
    if #ids == 0 then return nil end
    local day = math.floor((IS_SERVER and os.time() or GlobalState['nzh:time'] or 0) / 86400)
    return ids[(day * 7919) % #ids + 1]
end
