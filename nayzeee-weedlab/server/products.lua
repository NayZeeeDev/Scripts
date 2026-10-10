--[[
    Product registry. Every strain is a product with its own id. Mixed products are shared
    server-wide: the same recipe result is the same product for everyone, named by whoever
    discovered it first.

    Product items carry metadata { pid, label, quality, units, description }.
]]

Products = {}

local reg = {}      -- pid -> { id, base, name, effects, key }
local byKey = {}    -- mix key -> pid

for id, s in pairs(Config.Strains) do
    local p = { id = id, base = id, name = s.label, effects = s.effects, key = Mix.key(id, s.effects) }
    reg[id] = p
    byKey[p.key] = id
end

CreateThread(function()
    for _, row in ipairs(DB.products()) do
        local ok, effects = pcall(json.decode, row.effects)
        if ok and Config.Strains[row.base] then
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

--- bud colour of a product (its strain's)
function Products.bud(pid)
    local p = reg[pid]
    local s = p and Config.Strains[p.base]
    return s and s.bud or 'green'
end

local function randomName(base)
    local set = Config.Mixing.names
    for _ = 1, 25 do
        local name = Utils.pick(set.pre) .. ' ' .. Utils.pick(set.suf)
        local taken = false
        for _, p in pairs(reg) do
            if p.name == name then taken = true break end
        end
        if not taken then return name end
    end
    return ('%s #%d'):format(Config.Strains[base].label, math.random(100, 999))
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

--- add `pid` to the player's discovered products. true if it's new to them
function Products.discover(src, pid)
    local P = Profile.get(src)
    if not P or P.products[pid] then return false end
    P.products[pid] = os.time()
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
        description = ('%s · %s quality · %s / unit'):format(Products.effectsText(p), q.label, Utils.money(Mix.value(p.base, p.effects))),
    }
    if units then
        meta.units = units
        meta.label = ('%s (%s, %d)'):format(p.name, q.label, units)
    end
    return meta
end

function Products.view(pid)
    local p = reg[pid]
    if not p then return nil end
    return { id = pid, base = p.base, name = p.name, effects = p.effects, value = Mix.value(p.base, p.effects), bud = Products.bud(pid) }
end

--[[ loose product stacks in a player's pockets: { { pid, q, n, name, effects, base, bud } } ]]
function Products.loose(src)
    local item, agg, out = Config.Product.loose, {}, {}
    for _, s in ipairs(Inv.slots(src, item)) do
        local pid = s.meta and s.meta.pid or Config.Product.defaultPid
        local p = reg[pid]
        if p then
            local q = s.meta and s.meta.quality or 2
            local key = pid .. '|' .. q
            if not agg[key] then
                agg[key] = { pid = pid, q = q, n = 0, name = p.name, effects = p.effects, base = p.base, bud = Products.bud(pid), value = Mix.value(p.base, p.effects) }
                out[#out + 1] = agg[key]
            end
            agg[key].n = agg[key].n + s.count
        end
    end
    table.sort(out, function(a, b) return a.name == b.name and a.q > b.q or a.name < b.name end)
    return out
end

--- take `n` loose units of `pid` at quality `q`
function Products.takeLoose(src, pid, q, n)
    return Inv.removeMatching(src, Config.Product.loose, n, function(m)
        local mp = m.pid or Config.Product.defaultPid
        return mp == pid and (m.quality or 2) == q
    end)
end

function Products.countLoose(src, pid, q)
    local n = 0
    for _, s in ipairs(Products.loose(src)) do
        if s.pid == pid and s.q == q then n = n + s.n end
    end
    return n
end
