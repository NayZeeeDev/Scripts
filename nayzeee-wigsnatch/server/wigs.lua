-- Wig items: creation, metadata, value, market demand

Wigs = {}
Market = {}

local WIG = Config.Items.Wig

-- market ---------------------------------------------------------------------

local M = json.decode(GetResourceKvpString('nzwig:market') or '{}') or {}

function Market.Demand(tier)
    if not Config.Market.Enabled then return 1.0 end
    local e = M[tier]
    if not e then return 1.0 end
    local hours = (os.time() - (e.at or 0)) / 3600
    return math.min(1.0, (e.v or 1.0) + hours * Config.Market.RecoverPerHour)
end

function Market.Sold(tier, count)
    if not Config.Market.Enabled then return end
    local d = math.max(Config.Market.Floor, Market.Demand(tier) - Config.Market.DropPerSale * (count or 1))
    M[tier] = { v = d, at = os.time() }
    SetResourceKvp('nzwig:market', json.encode(M))
end

function Market.Snapshot()
    local out = {}
    for _, t in ipairs(Config.Tiers) do
        out[#out + 1] = { id = t.id, demand = math.floor(Market.Demand(t.id) * 100 + 0.5) }
    end
    return out
end

-- creation -------------------------------------------------------------------

local charset = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'
local function serial()
    local s = {}
    for i = 1, 6 do
        local n = math.random(1, #charset)
        s[i] = charset:sub(n, n)
    end
    return 'WS-' .. table.concat(s)
end

function Wigs.RollTier(luck)
    luck = math.max(0, math.min(Config.Luck.Max, luck or 0))
    local weights, total = {}, 0
    for i, t in ipairs(Config.Tiers) do
        local w = t.weight * (1 + luck) ^ (i - 1)
        weights[i] = w
        total = total + w
    end
    local r = math.random() * total
    for i, w in ipairs(weights) do
        r = r - w
        if r <= 0 then return Config.Tiers[i].id end
    end
    return Config.Tiers[1].id
end

function Wigs.Decorate(meta)
    local t = GetTier(meta.tier)
    meta.label = ('%s %s" %s'):format(t.label, meta.length or 14, meta.style or 'Wig')
    meta.description = ('%s · %d%% condition · fits %s · from %s'):format(
        meta.lace or t.lace, meta.cond or 100, (meta.hair and meta.hair.m == 'm') and 'male' or 'female', meta.from or 'unknown')
    meta.durability = meta.cond -- ox_inventory shows this as a bar
    if Config.Wig.TieredImages then meta.image = 'wig_' .. meta.tier end
    return meta
end

-- hair = { m = 'f'|'m', d, t, c, h }
function Wigs.Create(tierId, hair, victimName, snatcherName)
    local t = GetTier(tierId)
    local len = math.random(t.length[1], t.length[2])
    len = len - (len % 2)
    local meta = {
        serial = serial(),
        tier = t.id,
        style = StyleNameFor(hair.m, hair.d, hair.t),
        length = len,
        lace = t.lace,
        hair = { m = hair.m, d = hair.d, t = hair.t, c = hair.c or 0, h = hair.h or 0 },
        cond = 100,
        base = math.random(t.price[1], t.price[2]),
        hops = 0,
        from = victimName,
        by = snatcherName,
        owners = { victimName },
        ts = os.time(),
    }
    return Wigs.Decorate(meta)
end

-- A worn wig changed hands through a snatch
function Wigs.Hop(meta, victimName, snatcherName)
    meta.cond = math.max(Config.Wig.MinCondition, (meta.cond or 100) - Config.Wig.ConditionLossPerSnatch)
    meta.hops = (meta.hops or 0) + 1
    meta.by = snatcherName
    meta.owners = meta.owners or {}
    if meta.owners[1] ~= victimName then table.insert(meta.owners, 1, victimName) end
    while #meta.owners > Config.Wig.ProvenanceSize do table.remove(meta.owners) end
    return Wigs.Decorate(meta)
end

function Wigs.Generic()
    local t = Config.Tiers[1]
    return { serial = 'GEN', tier = t.id, style = 'Wig', length = 12, lace = t.lace, cond = 100,
        base = math.floor((t.price[1] + t.price[2]) / 2), hops = 0, generic = true }
end

function Wigs.Value(meta, sellPerk)
    local t = GetTier(meta.tier)
    local base = meta.base or math.floor((t.price[1] + t.price[2]) / 2)
    local cond = math.max(0.05, (meta.cond or 100) / 100)
    local infamy = 1 + math.min(Config.Wig.InfamyCap, (meta.hops or 0) * Config.Wig.InfamyPerSnatch)
    return math.floor(base * cond ^ 0.8 * infamy * Market.Demand(meta.tier) * (1 + (sellPerk or 0)))
end

-- inventory helpers ------------------------------------------------------------

-- every wig the player carries, with a stable key for the UI
function Wigs.Stacks(src)
    local out = {}
    for i, s in ipairs(Inv.Stacks(src, WIG)) do
        if s.meta and s.meta.serial then
            out[#out + 1] = { key = s.meta.serial, slot = s.slot, meta = s.meta }
        else
            -- stacked / metadata-less wigs: one entry per unit
            for n = 1, (s.count or 1) do
                out[#out + 1] = { key = ('GEN-%d-%d'):format(i, n), slot = s.slot, meta = Wigs.Generic(), generic = true }
            end
        end
    end
    return out
end

function Wigs.Find(src, key)
    for _, s in ipairs(Wigs.Stacks(src)) do
        if s.key == key then return s end
    end
end

function Wigs.Public(meta, value)
    local t = GetTier(meta.tier)
    return {
        serial = meta.serial, tier = meta.tier, tierLabel = t.label, color = t.color,
        style = meta.style, length = meta.length, lace = meta.lace, cond = meta.cond or 100,
        hops = meta.hops or 0, from = meta.from, by = meta.by, owners = meta.owners or {},
        ts = meta.ts, fits = meta.hair and meta.hair.m or nil, generic = meta.generic or nil,
        label = meta.label or (t.label .. ' Wig'), value = value,
    }
end

function Wigs.List(src, sellPerk)
    local out = {}
    for _, s in ipairs(Wigs.Stacks(src)) do
        local pub = Wigs.Public(s.meta, Wigs.Value(s.meta, sellPerk))
        pub.key = s.key
        out[#out + 1] = pub
    end
    table.sort(out, function(a, b)
        local ta, tb = TierIndex[a.tier] or 1, TierIndex[b.tier] or 1
        if ta ~= tb then return ta > tb end
        return (a.value or 0) > (b.value or 0)
    end)
    return out
end

function Wigs.Remove(src, stack)
    return Inv.Remove(src, WIG, 1, stack.slot)
end

function Wigs.Give(src, meta)
    if not Inv.HasMeta or meta.generic then return Inv.Add(src, WIG, 1) end
    return Inv.Add(src, WIG, 1, meta)
end

function Wigs.CanCarry(src, meta)
    return Inv.CanCarry(src, WIG, 1, Inv.HasMeta and meta or nil)
end
