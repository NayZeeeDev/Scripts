--[[
    Product registry. Base drugs (Config.Drugs) are products with their own id.
    Mixed products are shared server-wide: the same recipe result is the same product
    for everyone, named by whoever discovered it first.

    Product items carry metadata { pid, label, quality, description }.
]]

Products = {}

local reg = {}      -- pid -> { id, base, name, effects, key }
local byKey = {}    -- mix key -> pid

for id, d in pairs(Config.Drugs) do
    local p = { id = id, base = id, name = d.label, effects = d.effects, key = Mix.key(id, d.effects) }
    reg[id] = p
    byKey[p.key] = id
end

CreateThread(function()
    for _, row in ipairs(DB.products()) do
        local ok, effects = pcall(json.decode, row.effects)
        if ok and Config.Drugs[row.base] then
            reg[row.id] = { id = row.id, base = row.base, name = row.name, effects = effects or {}, key = row.mixkey }
            byKey[row.mixkey] = row.id
        end
    end
    Utils.debug('products loaded:', Utils.count(reg))
end)

function Products.get(pid)
    return pid and reg[pid]
end

function Products.label(pid)
    local p = reg[pid]
    return p and p.name or 'Unknown product'
end

function Products.value(pid)
    local p = reg[pid]
    return p and Mix.value(p.base, p.effects) or 0
end

function Products.kind(pid)
    local p = reg[pid]
    return p and Mix.kind(p.base)
end

local function randomName(base)
    local kind = Mix.kind(base)
    local set = Config.Mixing.names[kind] or Config.Mixing.names.weed
    for _ = 1, 20 do
        local name = Utils.pick(set.pre) .. ' ' .. Utils.pick(set.suf)
        local taken = false
        for _, p in pairs(reg) do
            if p.name == name then taken = true break end
        end
        if not taken then return name end
    end
    return ('%s #%d'):format(Config.Drugs[base].label, math.random(100, 999))
end

local function newId()
    local chars = 'abcdefghijkmnpqrstuvwxyz23456789'
    while true do
        local s = 'm'
        for _ = 1, 7 do
            local i = math.random(1, #chars)
            s = s .. chars:sub(i, i)
        end
        if not reg[s] then return s end
    end
end

--- product for `base` + `effects`, creating it if nobody has made it yet. returns pid, isNewToServer
function Products.resolve(base, effects, creator)
    local key = Mix.key(base, effects)
    if byKey[key] then return byKey[key], false end
    local p = { id = newId(), base = base, name = randomName(base), effects = effects, key = key, creator = creator }
    reg[p.id] = p
    byKey[key] = p.id
    DB.addProduct(p)
    return p.id, true
end

--- add `pid` to the player's product list (asking price starts at the market value)
function Products.discover(src, pid)
    local P = Profile.get(src)
    if not P or P.products[pid] then return false end
    P.products[pid] = { price = Products.value(pid) }
    Profile.dirty(src)
    return true
end

function Products.effectsText(p)
    local names = {}
    for i = 1, #p.effects do
        local e = Config.Effects[p.effects[i]]
        names[#names + 1] = e and e.label or p.effects[i]
    end
    return #names > 0 and table.concat(names, ', ') or 'No effects'
end

--- item metadata for `pid`
function Products.meta(pid, quality, units)
    local p = reg[pid]
    if not p then return nil end
    local q = Utils.quality(quality)
    local meta = {
        pid = pid,
        quality = q.id,
        label = ('%s (%s)'):format(p.name, q.label),
        description = ('%s · %s quality · %s'):format(Products.effectsText(p), q.label, Utils.money(Mix.value(p.base, p.effects))),
    }
    if units then meta.units = units end
    return meta
end

--- item name for a loose product
function Products.looseItem(pid)
    local kind = Products.kind(pid)
    return kind and Config.ProductItems.loose[kind]
end

--- app view of a product
function Products.view(pid, price)
    local p = reg[pid]
    if not p then return nil end
    return {
        id = pid, base = p.base, kind = Mix.kind(p.base), name = p.name,
        effects = p.effects, value = Mix.value(p.base, p.effects), price = price or Mix.value(p.base, p.effects),
        addictive = Mix.addictiveness(p.base, p.effects),
    }
end

--[[ packaged stock in a player's pockets: { [pid] = { [quality] = units } } ]]
function Products.packaged(src)
    local out = {}
    local function add(meta, units)
        if not meta or not meta.pid or not reg[meta.pid] then return end
        local q = meta.quality or 2
        out[meta.pid] = out[meta.pid] or {}
        out[meta.pid][q] = (out[meta.pid][q] or 0) + units
    end
    for _, s in ipairs(Inv.slots(src, Config.ProductItems.baggie)) do add(s.meta, s.count * Config.Deals.unitsPerBaggie) end
    for _, s in ipairs(Inv.slots(src, Config.ProductItems.jar)) do add(s.meta, s.count * Config.Deals.unitsPerJar) end
    return out
end

--- remove `units` of packaged `pid` (any quality >= minQ). jars first, then baggies.
--- returns the lowest quality handed over, or nil if the player doesn't have enough
function Products.takePackaged(src, pid, units, minQ)
    minQ = minQ or 0
    local per = { [Config.ProductItems.jar] = Config.Deals.unitsPerJar, [Config.ProductItems.baggie] = Config.Deals.unitsPerBaggie }
    local plan, have = {}, 0
    for _, item in ipairs({ Config.ProductItems.jar, Config.ProductItems.baggie }) do
        for _, s in ipairs(Inv.slots(src, item)) do
            if s.meta and s.meta.pid == pid and (s.meta.quality or 2) >= minQ then
                plan[#plan + 1] = { item = item, slot = s.slot, count = s.count, meta = s.meta, per = per[item] }
                have = have + s.count * per[item]
            end
        end
    end
    if have < units then return nil end

    -- whole jars while they fit, then baggies, then a jar for any remainder
    table.sort(plan, function(a, b) return a.per > b.per end)
    local left, lowest = units, 4
    local takes = {}
    for _, p in ipairs(plan) do
        if left <= 0 then break end
        local n = math.min(p.count, math.floor(left / p.per))
        if n > 0 then
            takes[#takes + 1] = { p = p, n = n }
            left = left - n * p.per
            p.count = p.count - n
        end
    end
    if left > 0 then
        table.sort(plan, function(a, b) return a.per < b.per end)
        for _, p in ipairs(plan) do
            if left <= 0 then break end
            if p.count > 0 then
                local n = math.min(p.count, math.ceil(left / p.per))
                takes[#takes + 1] = { p = p, n = n }
                left = left - n * p.per
            end
        end
    end
    if left > 0 then return nil end
    for _, t in ipairs(takes) do
        if not Inv.removeSlot(src, t.p.item, t.n, t.p.slot, t.p.meta) then return nil end
        lowest = math.min(lowest, t.p.meta.quality or 2)
    end
    return lowest
end
