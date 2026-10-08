-- Shared helpers used by server, client and (mirrored) the UI.
Cargo = {}
Cargo.Version  = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '1.0.0'
Cargo.Resource = GetCurrentResourceName()

---------------------------------------------------------------------
-- Rarities
---------------------------------------------------------------------
Cargo.Rarity = {}
for i, r in ipairs(Config.Rarities) do
    r.index = i
    Cargo.Rarity[r.id] = r
end
-- Illegal sits outside the ladder: it never climbs or drops.
Config.Illegal.index = 99
Config.Illegal.illegal = true
Cargo.Rarity[Config.Illegal.id] = Config.Illegal

function Cargo.IsIllegal(id) return id == Config.Illegal.id end

function Cargo.RarityAt(index)
    index = math.max(1, math.min(#Config.Rarities, index))
    return Config.Rarities[index]
end

---------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------
function Cargo.XpForLevel(level)
    if level <= 1 then return 0 end
    return math.floor(Config.Levels.Base * (level - 1) ^ Config.Levels.Curve)
end

-- returns level, xp into this level, xp needed for next level (0 at max)
function Cargo.LevelFromXp(xp)
    local level = 1
    while level < Config.Levels.Max and xp >= Cargo.XpForLevel(level + 1) do
        level = level + 1
    end
    local floor = Cargo.XpForLevel(level)
    local nextAt = level < Config.Levels.Max and Cargo.XpForLevel(level + 1) or floor
    return level, xp - floor, nextAt - floor
end

---------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------
function Cargo.PickWeighted(weights)
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    if total <= 0 then return nil end
    local roll = math.random() * total
    -- iterate in a stable order so results are reproducible
    local keys = {}
    for k in pairs(weights) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        roll = roll - weights[k]
        if roll <= 0 then return k end
    end
    return keys[#keys]
end

function Cargo.Round(n) return math.floor(n + 0.5) end

function Cargo.Clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

function Cargo.Upgrade(track, level)
    local t = Config.Upgrades[track]
    if not t or not t.levels then return nil end
    return t.levels[(level or 0) + 1] or t.levels[1]
end

---------------------------------------------------------------------
-- Design bay
---------------------------------------------------------------------
Cargo.Part = {}
for _, p in ipairs(Config.Workshop.Parts) do Cargo.Part[p.id] = p end

local finishById = {}
for _, f in ipairs(Config.Workshop.Finishes) do finishById[f.id] = f end
Cargo.Finish = finishById

function Cargo.AllowedGroups(workshopLevel)
    local lvl = Cargo.Upgrade('workshop', workshopLevel)
    local set = {}
    for _, g in ipairs(lvl and lvl.categories or {}) do set[g] = true end
    return set
end

-- Normalised build: missing keys mean stock.
-- Returns score (0-100), perf points, style points
function Cargo.ScoreBuild(build, workshopLevel)
    build = build or {}
    local perf, style = 0, 0
    local function add(part, pts)
        if part.kind == 'perf' then perf = perf + pts else style = style + pts end
    end

    for _, p in ipairs(Config.Workshop.Parts) do
        local v = build[p.id]
        if v ~= nil then
            if p.type == 'level' then
                local lvl = Cargo.Clamp(tonumber(v) or 0, 0, p.max)
                add(p, lvl * p.points)
            elseif p.type == 'toggle' then
                if v == true then add(p, p.points) end
            elseif p.type == 'part' or p.type == 'livery' then
                if (tonumber(v) or -1) >= 0 then add(p, p.points) end
            elseif p.type == 'paint' and type(v) == 'table' then
                local f = finishById[tonumber(v.finish) or 0]
                local pts = f and f.points or 0
                if v.p and v.s and v.p ~= v.s then pts = pts + Config.Workshop.TwoTonePoints end
                if (tonumber(v.pearl) or 0) > 0 then pts = pts + 1 end
                add(p, pts)
            elseif p.type == 'wheels' and type(v) == 'table' then
                local pts = 0
                if v.type ~= nil then
                    pts = p.points
                    if v.type == 7 or v.type == 12 then pts = pts + Config.Workshop.HighEndWheelBonus end
                    if v.custom then pts = pts + Config.Workshop.CustomTyres.points end
                end
                if v.color ~= nil then pts = pts + Config.Workshop.RimColor.points end
                add(p, pts)
            elseif p.type == 'tint' then
                if (tonumber(v) or 0) ~= 0 then add(p, p.points) end
            elseif p.type == 'plate' then
                if (tonumber(v) or 0) ~= 0 then add(p, p.points) end
            elseif p.type == 'xenon' or p.type == 'neon' then
                add(p, p.points)
            end
        end
    end

    local b = Config.Workshop.Balance
    local total = perf + style
    if perf >= b.perf and style >= b.style then total = total + b.points end

    local lvl = Cargo.Upgrade('workshop', workshopLevel or 0)
    total = total * (lvl and lvl.scoreMult or 1.0)
    return math.min(100, math.floor(total)), perf, style
end

function Cargo.RarityFromScore(baseRarity, score, maxGain)
    if Cargo.IsIllegal(baseRarity) then return baseRarity end
    local base = Cargo.Rarity[baseRarity] or Config.Rarities[1]
    local gain = 0
    for i, need in ipairs(Config.Workshop.ScoreToRarity) do
        if score >= need then gain = i end
    end
    gain = math.min(gain, maxGain or 0)
    return Cargo.RarityAt(base.index + gain).id
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

-- Cost to go from old build to new build. Downgrades and removals are free.
-- Returns total, { { id, label, cost } }
function Cargo.BuildCost(old, new, baseRarity)
    old, new = old or {}, new or {}
    local mult = Config.Workshop.CostMult[baseRarity] or 1.0
    local total, lines = 0, {}
    local function charge(p, amount, label)
        if amount <= 0 then return end
        amount = math.floor(amount * mult)
        total = total + amount
        lines[#lines + 1] = { id = p.id, label = label or p.label, cost = amount }
    end

    for _, p in ipairs(Config.Workshop.Parts) do
        local o, n = old[p.id], new[p.id]
        if p.type == 'level' then
            o, n = tonumber(o) or 0, tonumber(n) or 0
            if n > o then
                local sum = 0
                for stage = o + 1, n do sum = sum + p.price * stage end
                charge(p, sum, ('%s stage %d'):format(p.label, n))
            end
        elseif p.type == 'toggle' then
            if n == true and o ~= true then charge(p, p.price) end
        elseif p.type == 'part' or p.type == 'livery' then
            n = tonumber(n) or -1
            if n >= 0 and n ~= (tonumber(o) or -1) then charge(p, p.price) end
        elseif p.type == 'wheels' then
            if type(n) == 'table' then
                local ot = type(o) == 'table' and o or {}
                if n.type ~= nil and (n.type ~= ot.type or n.index ~= ot.index) then charge(p, p.price) end
                if n.custom and not ot.custom then charge(p, Config.Workshop.CustomTyres.price, 'Custom Tyres') end
                if n.color ~= nil and n.color ~= ot.color then charge(p, Config.Workshop.RimColor.price, 'Rim Colour') end
            end
        elseif p.type == 'paint' then
            if type(n) == 'table' and not same(o, n) then charge(p, p.price) end
        else -- tint, plate, xenon, neon
            if n ~= nil and n ~= o and not (p.type ~= 'xenon' and p.type ~= 'neon' and tonumber(n) == 0) then
                charge(p, p.price)
            end
        end
    end
    return total, lines
end

-- Which of a buyer's wants the car meets.
function Cargo.MatchWants(build, condition, score, wants)
    build = build or {}
    local paint = type(build.paint) == 'table' and build.paint or {}
    local tests = {
        matte  = function() return paint.finish == 3 end,
        chrome = function() return paint.finish == 5 end,
        pearl  = function() return paint.finish == 2 or (tonumber(paint.pearl) or 0) > 0 end,
        turbo  = function() return build.turbo == true end,
        engine = function() return (tonumber(build.engine) or 0) >= Cargo.Part.engine.max end,
        neon   = function() return build.neon ~= nil end,
        tint   = function() return tonumber(build.tint) == 1 end,
        wheels = function() return type(build.wheels) == 'table' end,
        armor  = function() return (tonumber(build.armor) or 0) >= 3 end,
        mint   = function() return (condition or 0) >= 95 end,
        stock  = function() return (score or 0) == 0 end,
    }
    local met, bonus = {}, 0.0
    for _, id in ipairs(wants or {}) do
        local def
        for _, w in ipairs(Config.Selling.Wants) do if w.id == id then def = w break end end
        if def and tests[id] and tests[id]() then
            met[#met + 1] = id
            bonus = bonus + def.bonus
        end
    end
    return met, bonus
end

-- Value of a stored car before buyer and damage modifiers.
function Cargo.BaseValue(stock, contactsLevel)
    local base = Cargo.Rarity[stock.base_rarity] or Config.Rarities[1]
    local cur  = Cargo.Rarity[stock.rarity] or base
    local value = stock.value * (cur.valueMult / base.valueMult)
    local cond = Cargo.Clamp(stock.condition or 100, 0, 100)
    value = value * (1 - (1 - cond / 100) * Config.Selling.ConditionWeight)
    value = value * (1 + (stock.score or 0) * Config.Workshop.ValuePerPoint)
    local c = Cargo.Upgrade('contacts', contactsLevel or 0)
    value = value * (1 + (c and c.saleBonus or 0))
    return math.floor(value)
end

function Cargo.FormatTime(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 60 then return ('%dm %02ds'):format(sec // 60, sec % 60) end
    return ('%ds'):format(sec)
end

function Cargo.Debug(...)
    if Config.Debug then print('^5[vehiclecargo]^7', ...) end
end

---------------------------------------------------------------------
-- Floor presets: turn a preset definition into up to MaxSlots spots
---------------------------------------------------------------------
-- Does a parked car (2.3 x 5.0, rotated) stay inside the floor and clear of every obstacle?
local CAR_W, CAR_L = 1.15, 2.5
local function carFits(x, y, h, area)
    if not area then return true end
    local r = math.rad(h)
    local c, s = math.cos(r), math.sin(r)
    for _, o in ipairs({ { -CAR_W, -CAR_L }, { CAR_W, -CAR_L }, { CAR_W, CAR_L }, { -CAR_W, CAR_L }, { 0, 0 } }) do
        local px, py = x + o[1] * c - o[2] * s, y + o[1] * s + o[2] * c
        if px < area.min.x or px > area.max.x or py < area.min.y or py > area.max.y then return false end
        for _, ob in ipairs(area.obstacles or {}) do
            if px > ob.min.x - 0.3 and px < ob.max.x + 0.3 and py > ob.min.y - 0.3 and py < ob.max.y + 0.3 then return false end
        end
    end
    return true
end
Cargo.CarFits = carFits

-- area = { min = {x,y}, max = {x,y}, z, obstacles = { { min, max } } }
function Cargo.PresetSlots(p, area)
    local out = {}
    local max = math.min(p.max or Config.Layout.MaxSlots, Config.Layout.MaxSlots)
    local function add(x, y, z, w)
        w = (w or 0.0) % 360
        if #out < max and carFits(x, y, w, area) then out[#out + 1] = { x = x, y = y, z = z, w = w } end
    end
    if p.slots then
        for _, s in ipairs(p.slots) do if #out < max then out[#out + 1] = { x = s.x, y = s.y, z = s.z, w = (s.w or 0.0) % 360 } end end
        return out
    end
    if not area then return out end
    local x0, x1, y0, y1, z = area.min.x, area.max.x, area.min.y, area.max.y, area.z
    local W, H = x1 - x0, y1 - y0
    -- spots along one row, centred, never more than the row can hold
    local function row(y, h, spacing, perRow)
        local n = math.max(1, math.min(perRow, math.floor((W - 2.6) / spacing) + 1))
        local start = x0 + (W - (n - 1) * spacing) / 2
        for i = 0, n - 1 do add(start + i * spacing, y, z, h) end
    end
    if p.pattern == 'rows' or p.pattern == 'angled' then
        local tilt = p.pattern == 'angled' and (p.angle or 35.0) or 0.0
        local rows = { { y0 + 3.0, 0.0 + tilt }, { y1 - 3.0, 180.0 + tilt } }
        if H >= 26.0 then   -- room for a back-to-back middle pair
            local m = (y0 + y1) / 2
            rows[#rows + 1] = { m - 2.75, 180.0 - tilt }
            rows[#rows + 1] = { m + 2.75, 0.0 - tilt }
        end
        local perRow = math.ceil(max / #rows)
        for _, r in ipairs(rows) do row(r[1], r[2], p.spacing or 3.8, perRow) end
    elseif p.pattern == 'packed' then
        -- side-on columns of cars with aisles between them
        local aisle, spacing = p.aisle or 6.5, p.spacing or 3.0
        local cols = math.max(1, math.floor((W - 5.0) / aisle) + 1)
        local per = math.max(1, math.floor((H - 2.6) / spacing) + 1)
        local sx = x0 + (W - (cols - 1) * aisle) / 2
        local sy = y0 + (H - (per - 1) * spacing) / 2
        for c = 0, cols - 1 do
            for i = 0, per - 1 do add(sx + c * aisle, sy + i * spacing, z, (c % 2 == 0) and 90.0 or 270.0) end
        end
    elseif p.pattern == 'island' then
        local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        local outer = math.min(W, H) / 2 - 3.0
        local inner = outer * 0.45
        local function ring(r, face)
            if r < 2.5 then return end
            local n = math.max(3, math.floor(2 * math.pi * r / 3.6))
            for i = 0, n - 1 do
                local a = (i / n) * math.pi * 2
                add(cx + math.cos(a) * r, cy + math.sin(a) * r, z, math.deg(a) + face)
            end
        end
        ring(inner, -90.0)
        ring(outer, 90.0)
    end
    return out
end

---------------------------------------------------------------------
-- External mechanic scripts: read a build back out of vehicle props
-- so the score and rarity still work when another resource did the work.
---------------------------------------------------------------------
local function nearest(list, r, g, b, offset)
    local best, bestD = 1, math.huge
    for i, c in ipairs(list) do
        local d = (c[offset] - r) ^ 2 + (c[offset + 1] - g) ^ 2 + (c[offset + 2] - b) ^ 2
        if d < bestD then best, bestD = i, d end
    end
    return best
end

function Cargo.PropsToBuild(props)
    props = props or {}
    local W = Config.Workshop
    local b = {}
    local function lvl(v, max) v = tonumber(v) or -1 if v >= 0 then return math.min(v + 1, max) end end
    b.engine       = lvl(props.modEngine, 4)
    b.brakes       = lvl(props.modBrakes, 3)
    b.transmission = lvl(props.modTransmission, 3)
    b.suspension   = lvl(props.modSuspension, 4)
    b.armor        = lvl(props.modArmor, 5)
    if props.modTurbo == true or props.modTurbo == 1 then b.turbo = true end
    local parts = { spoiler = 'modSpoilers', fbumper = 'modFrontBumper', rbumper = 'modRearBumper', skirts = 'modSideSkirt',
                    exhaust = 'modExhaust', grille = 'modGrille', hood = 'modHood', roof = 'modRoof' }
    for id, key in pairs(parts) do
        local v = tonumber(props[key]) or -1
        if v >= 0 then b[id] = v end
    end
    local function rgb(c)
        if type(c) == 'table' then return c[1] or c.r or 0, c[2] or c.g or 0, c[3] or c.b or 0 end
    end
    local r1, g1, b1 = rgb(props.color1)
    local r2, g2, b2 = rgb(props.color2)
    local finish = tonumber(props.paintType1)
    if r1 or (finish and finish > 0) then
        local pearl = tonumber(props.pearlescentColor) or 0
        local okPearl = false
        for _, p in ipairs(W.Pearls) do if p[1] == pearl then okPearl = true end end
        b.paint = {
            p = r1 and nearest(W.Colors, r1, g1, b1, 2) or 1,
            s = r2 and nearest(W.Colors, r2, g2, b2, 2) or (r1 and nearest(W.Colors, r1, g1, b1, 2) or 1),
            finish = (finish and finish >= 0 and finish <= 5) and finish or 0,
            pearl = okPearl and pearl or 0,
        }
    end
    local wheel = tonumber(props.modFrontWheels) or -1
    if wheel >= 0 then b.wheels = { type = tonumber(props.wheels) or 0, index = wheel, custom = props.modCustomTiresF == true } end
    local tint = tonumber(props.windowTint) or 0
    if tint > 0 then b.tint = tint end
    local livery = tonumber(props.modLivery) or tonumber(props.livery) or -1
    if livery >= 0 then b.livery = livery end
    local plate = tonumber(props.plateIndex) or 0
    if plate > 0 then b.plate = plate end
    if props.modXenon == true or props.modXenon == 1 then
        local xc = tonumber(props.xenonColor) or 255
        b.xenon = (xc == 255 or xc < 0) and -1 or xc
    end
    local neonOn = false
    for _, v in pairs(type(props.neonEnabled) == 'table' and props.neonEnabled or {}) do if v == true or v == 1 then neonOn = true end end
    if neonOn then
        local nr, ng, nb = rgb(props.neonColor)
        b.neon = nr and nearest(W.NeonColors, nr, ng, nb, 2) or 1
    end
    return b
end
