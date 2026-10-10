RES = GetCurrentResourceName()
IS_SERVER = IsDuplicityVersion()

Utils = {}

function Utils.debug(...)
    if not Config.Debug then return end
    print(('^5[%s]^7'):format(RES), ...)
end

--- unix time on both sides (the client's cloud clock matches the server's os.time)
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

--- rotate a local (x, y) offset by a heading in degrees
function Utils.rotate(x, y, heading)
    local r = math.rad(heading or 0.0)
    return x * math.cos(r) - y * math.sin(r), x * math.sin(r) + y * math.cos(r)
end

--[[ ─────────────── levels ─────────────── ]]

--- xp needed to go from `level` to `level + 1`
function Utils.levelCost(level)
    return Config.Levels.base + level * Config.Levels.step
end

--- level, xp into the level, xp needed for the next one (nil at max)
function Utils.levelFromXp(xp)
    xp = xp or 0
    local level, max = 0, Config.Levels.max
    while level < max do
        local cost = Utils.levelCost(level)
        if xp < cost then return level, xp, cost end
        xp = xp - cost
        level = level + 1
    end
    return max, xp, nil
end

function Utils.title(level)
    local t = Config.Levels.titles[1][2]
    for _, row in ipairs(Config.Levels.titles) do
        if level >= row[1] then t = row[2] end
    end
    return t
end

function Utils.levelLabel(level)
    return ('Level %d · %s'):format(level, Utils.title(level))
end

--- the level an item unlocks at (equipment, lights, seeds, soils, additives, ingredients, store overrides)
local itemLevels
function Utils.itemLevel(item)
    if not itemLevels then
        itemLevels = {}
        for _, e in pairs(Config.Equipment) do itemLevels[e.item] = e.level or 0 end
        for _, l in pairs(Config.Lights) do itemLevels[l.item] = l.level or 0 end
        for _, s in pairs(Config.Strains) do itemLevels[s.seed] = s.level or 0 end
        for item2, s in pairs(Config.Grow.soils) do itemLevels[item2] = s.level or 0 end
        for item2, a in pairs(Config.Grow.additives) do itemLevels[item2] = a.level or 0 end
        for item2, i in pairs(Config.Ingredients) do itemLevels[item2] = i.level or 0 end
        for _, row in ipairs(Config.Store.items) do
            if row.level then itemLevels[row.item] = row.level end
        end
    end
    return itemLevels[item] or 0
end

--- labels of everything that unlocks exactly at `level` (level-up screen + tablet)
function Utils.unlocksAt(level)
    local out = {}
    for _, row in ipairs(Config.Store.items) do
        if Utils.itemLevel(row.item) == level then out[#out + 1] = Utils.itemLabel(row.item) end
    end
    for _, id in ipairs(Config.LabOrder) do
        local lab = Config.Labs[id]
        if (lab.level or 0) == level and id ~= 'rv' then out[#out + 1] = lab.label end
    end
    return out
end

function Utils.quality(id)
    return Config.Quality[Utils.clamp(id or 2, 0, 4) + 1]
end

function Utils.itemLabel(name)
    local row = Config.Items[name]
    return row and row[1] or name
end

--- which equipment kind an item places (pot, tent, rack...) or which light it is
function Utils.equipmentOf(item)
    for kind, e in pairs(Config.Equipment) do
        if e.item == item then return kind, e end
    end
end

function Utils.lightOf(item)
    for kind, l in pairs(Config.Lights) do
        if l.item == item then return kind, l end
    end
end

function Utils.strainOfSeed(item)
    for id, s in pairs(Config.Strains) do
        if s.seed == item then return id, s end
    end
end

--- interior config for a lab (the RV has two: shell / ipl)
function Utils.labInterior(lab, mode)
    local L = Config.Labs[lab]
    if not L then return nil end
    if lab == 'rv' then return mode == 'ipl' and L.ipl or L.shell end
    return L.interior
end

--- is a relative point inside an interior's placement box
function Utils.inBounds(cfg, x, y, z)
    local b = cfg.bounds
    return x >= b.min.x and x <= b.max.x and y >= b.min.y and y <= b.max.y and z >= b.min.z and z <= b.max.z
end
