RES = GetCurrentResourceName()
IS_SERVER = IsDuplicityVersion()

Utils = {}

function Utils.debug(...)
    if not Config.Debug then return end
    print(('^5[%s]^7'):format(RES), ...)
end

--- unix time on both sides (client uses the cloud clock, which matches the server's os.time)
function Utils.now()
    if IS_SERVER then return os.time() end
    return GetCloudTimeAsInt()
end

function Utils.vec3(v)
    if not v then return nil end
    return vec3(v.x + 0.0, v.y + 0.0, v.z + 0.0)
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
    return '$' .. (out:gsub('^,', ''))
end

function Utils.clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

function Utils.round(n, d)
    local m = 10 ^ (d or 0)
    return math.floor(n * m + 0.5) / m
end

function Utils.copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Utils.copy(v) end
    return out
end

function Utils.count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function Utils.pick(list)
    return list[math.random(1, #list)]
end

function Utils.range(r)
    if type(r) == 'table' then return math.random(r[1], r[2]) end
    return r
end

--[[ ranks ]]

--- xp needed to go from `level` to `level + 1`
function Utils.levelCost(level)
    return Config.Ranks.base + (level - 1) * Config.Ranks.step
end

function Utils.maxLevel()
    return #Config.Ranks.names * Config.Ranks.tiers
end

--- level, xp into the level, xp needed for the next one (nil at max)
function Utils.levelFromXp(xp)
    xp = xp or 0
    local level, max = 1, Utils.maxLevel()
    while level < max do
        local cost = Utils.levelCost(level)
        if xp < cost then return level, xp, cost end
        xp = xp - cost
        level = level + 1
    end
    return max, xp, nil
end

local ROMAN = { 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X' }

function Utils.rankLabel(level)
    local tiers = Config.Ranks.tiers
    local rank = math.floor((level - 1) / tiers) + 1
    local tier = (level - 1) % tiers + 1
    return ('%s %s'):format(Config.Ranks.names[rank] or Config.Ranks.names[#Config.Ranks.names], ROMAN[tier] or tier)
end

--[[ customers ]]
function Utils.relLabel(rel)
    local label = 'Hostile'
    for _, row in ipairs(Config.Relationship.labels) do
        if rel >= row[1] then label = row[2] end
    end
    return label
end

function Utils.standards(id)
    return Config.Standards[(id or 0) + 1] or Config.Standards[1]
end

function Utils.quality(id)
    return Config.Quality[Utils.clamp(id or 2, 0, 4) + 1]
end

function Utils.regionUnlocked(regionId, level)
    for _, r in ipairs(Config.Regions) do
        if r.id == regionId then return level >= r.unlock end
    end
    return false
end

function Utils.itemLabel(name)
    local row = Config.Items[name]
    return row and row[1] or name
end
