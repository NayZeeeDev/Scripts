-- Wig + hair bundle items: creation, metadata, pictures, pricing, market demand

Wigs = {}
Market = {}

local WIG, BUNDLE = Config.Items.Wig, Config.Items.Bundle

-- market demand ----------------------------------------------------------------------
-- keyed by tier id, plus 'bundle' for hair bundles

local M = json.decode(GetResourceKvpString('nzwig:market') or '{}') or {}

function Market.Demand(key)
    if not Config.Market.Enabled then return 1.0 end
    local e = M[key]
    if not e then return 1.0 end
    local hours = (os.time() - (e.at or 0)) / 3600
    return math.min(1.0, (e.v or 1.0) + hours * Config.Market.RecoverPerHour)
end

function Market.Sold(key, count)
    if not Config.Market.Enabled then return end
    local d = math.max(Config.Market.Floor, Market.Demand(key) - Config.Market.DropPerSale * (count or 1))
    M[key] = { v = d, at = os.time() }
    SetResourceKvp('nzwig:market', json.encode(M))
end

function Market.Snapshot()
    local out = {}
    for _, t in ipairs(Config.Tiers) do
        out[#out + 1] = { id = t.id, demand = math.floor(Market.Demand(t.id) * 100 + 0.5) }
    end
    out[#out + 1] = { id = 'bundle', demand = math.floor(Market.Demand('bundle') * 100 + 0.5) }
    return out
end

-- studio pictures ----------------------------------------------------------------------

local shots = {} -- ['f/12_0'] = true

function Wigs.LoadShotIndex()
    local raw = LoadResourceFile(RESOURCE, 'shots/index.json')
    local ok, list = pcall(json.decode, raw or '[]')
    shots = {}
    for _, k in ipairs(ok and type(list) == 'table' and list or {}) do shots[k] = true end
end

function Wigs.MarkShot(key)
    if type(key) == 'string' then shots[key] = true end
end

function Wigs.HasShot(m, d, t)
    return shots[('%s/%d_%d'):format(m == 'm' and 'm' or 'f', d or 0, t or 0)] == true
end

-- the studio photo for a hairstyle (falling back to texture 0): file name, or nil
function Wigs.ShotName(hair)
    if not hair then return nil end
    if Wigs.HasShot(hair.m, hair.d, hair.t) then return StudioShotName(hair.m, hair.d, hair.t) end
    if Wigs.HasShot(hair.m, hair.d, 0) then return StudioShotName(hair.m, hair.d, 0) end
end

-- the same photo as a URL any NUI can load (the vault, the phone app, other inventories)
function Wigs.ShotUrl(hair)
    local name = Wigs.ShotName(hair)
    return name and ('https://cfx-nui-%s/shots/%s.png'):format(RESOURCE, name) or nil
end

-- creation -------------------------------------------------------------------------------

local charset = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'
local function serial(prefix)
    local s = {}
    for i = 1, 6 do
        local n = math.random(1, #charset)
        s[i] = charset:sub(n, n)
    end
    return (prefix or 'WS') .. '-' .. table.concat(s)
end
Wigs.Serial = serial

function Wigs.RollTier(luck, minTier)
    luck = math.max(0, math.min(Config.Luck.Max, luck or 0))
    local from = TierIndex[minTier] or 1
    local weights, total = {}, 0
    for i, t in ipairs(Config.Tiers) do
        local w = i < from and 0 or t.weight * (1 + luck) ^ (i - 1)
        weights[i] = w
        total = total + w
    end
    local r = math.random() * total
    for i, w in ipairs(weights) do
        r = r - w
        if w > 0 and r <= 0 then return Config.Tiers[i].id end
    end
    return Config.Tiers[from].id
end

local function fits(meta)
    return (meta.hair and meta.hair.m == 'm') and 'male' or 'female'
end

function Wigs.Decorate(meta)
    local t = GetTier(meta.tier)
    meta.label = ('%s %s" %s'):format(t.label, meta.length or 14, meta.style or 'Wig')
    local extra = {}
    if meta.dyed then extra[#extra + 1] = 'dyed' end
    if meta.burnt then extra[#extra + 1] = 'burnt' end
    if meta.grade then extra[#extra + 1] = GetGrade(meta.grade).label .. ' hair' end
    meta.description = ('%s · %d%% condition · fits %s · from %s%s'):format(
        meta.lace or t.lace, meta.cond or 100, fits(meta), meta.from or 'unknown',
        #extra > 0 and (' · ' .. table.concat(extra, ', ')) or '')
    meta.durability = meta.cond -- ox_inventory shows this as a bar
    meta.image, meta.imageurl = nil, nil
    local mode = Config.Wig.Images
    if mode == 'studio' then
        -- ox_inventory: the studio copies each photo into ox_inventory/web/images, so the item
        -- just names it. Other inventories get the URL.
        if Config.Studio.SaveToInventory and Inv.Name == 'ox_inventory' then
            meta.image = Wigs.ShotName(meta.hair)
        else
            meta.imageurl = Wigs.ShotUrl(meta.hair)
        end
    elseif mode == 'tier' then
        meta.image = 'wig_' .. meta.tier
    end
    return meta
end

-- hair = { m = 'f'|'m', d, t, c, h }
function Wigs.Create(tierId, hair, victimName, snatcherName, extra)
    local t = GetTier(tierId)
    local len = math.random(t.length[1], t.length[2])
    len = len - (len % 2)
    local meta = {
        serial = serial('WS'),
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
    for k, v in pairs(extra or {}) do meta[k] = v end
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

-- bundles ---------------------------------------------------------------------------------

function Wigs.RollGrade()
    local total = 0
    for _, g in ipairs(Config.Bundles.Grades) do total = total + g.weight end
    local r = math.random() * total
    for _, g in ipairs(Config.Bundles.Grades) do
        r = r - g.weight
        if r <= 0 then return g.id end
    end
    return Config.Bundles.Grades[1].id
end

function Wigs.DecorateBundle(meta)
    local g = GetGrade(meta.grade)
    meta.label = ('%s %s" Bundle · %s'):format(g.label, meta.length or 14, meta.style or 'Hair')
    meta.description = ('%s hair · from %s · makes a %s wig'):format(g.label, meta.from or 'unknown',
        (meta.hair and meta.hair.m == 'm') and 'male' or 'female')
    return meta
end

function Wigs.CreateBundle(hair, fromName, grade)
    local b = Config.Bundles
    local len = math.random(b.Length[1], b.Length[2])
    len = len - (len % 2)
    return Wigs.DecorateBundle({
        serial = serial('HB'),
        grade = grade or Wigs.RollGrade(),
        length = len,
        style = StyleNameFor(hair.m, hair.d, hair.t),
        hair = { m = hair.m, d = hair.d, t = hair.t, c = hair.c or 0, h = hair.h or 0 },
        from = fromName,
        ts = os.time(),
        bundle = true,
    })
end

-- pricing ("hair pricing") -------------------------------------------------------------------

-- Every factor that goes into the price, so the phone app can show the breakdown.
function Wigs.Pricing(meta, sellPerk)
    sellPerk = sellPerk or 0
    if meta.bundle then
        local g = GetGrade(meta.grade)
        local base = Config.Bundles.PerInch * (meta.length or 14)
        local demand = Market.Demand('bundle')
        local total = math.floor(base * g.mult * demand * (1 + sellPerk))
        return { total = total, base = base, grade = g.mult, demand = demand, perk = sellPerk }
    end
    local t = GetTier(meta.tier)
    local base = meta.base or math.floor((t.price[1] + t.price[2]) / 2)
    local cond = math.max(0.05, (meta.cond or 100) / 100) ^ 0.8
    local infamy = 1 + math.min(Config.Wig.InfamyCap, (meta.hops or 0) * Config.Wig.InfamyPerSnatch)
    local demand = Market.Demand(meta.tier)
    local dye = meta.dyed and (1 + Config.Dye.ValueBonus) or 1
    local burnt = meta.burnt and (Config.Products.Status.burn.ValueMult or 1) or 1
    local total = math.floor(base * cond * infamy * demand * dye * burnt * (1 + sellPerk))
    return { total = total, base = base, condition = cond, infamy = infamy, demand = demand, dye = dye, burnt = burnt, perk = sellPerk }
end

function Wigs.Value(meta, sellPerk)
    return Wigs.Pricing(meta, sellPerk).total
end

-- inventory helpers ------------------------------------------------------------------------

-- every wig / bundle the player carries, with a stable key for the UI
local function stacksOf(src, item, kind)
    local out = {}
    for i, s in ipairs(Inv.Stacks(src, item)) do
        if s.meta and s.meta.serial then
            out[#out + 1] = { key = s.meta.serial, slot = s.slot, meta = s.meta, kind = kind, item = item }
        else
            -- stacked / metadata-less items: one entry per unit
            for n = 1, (s.count or 1) do
                local meta = kind == 'wig' and Wigs.Generic()
                    or { serial = 'GEN', grade = Config.Bundles.Grades[1].id, length = 12, style = 'Hair', bundle = true, generic = true }
                out[#out + 1] = { key = ('GEN-%s-%d-%d'):format(kind, i, n), slot = s.slot, meta = meta, generic = true, kind = kind, item = item }
            end
        end
    end
    return out
end

function Wigs.Stacks(src) return stacksOf(src, WIG, 'wig') end
function Wigs.BundleStacks(src) return stacksOf(src, BUNDLE, 'bundle') end

-- wigs + bundles together (for selling)
function Wigs.Goods(src)
    local out = Wigs.Stacks(src)
    for _, b in ipairs(Wigs.BundleStacks(src)) do out[#out + 1] = b end
    return out
end

function Wigs.Find(src, key)
    for _, s in ipairs(Wigs.Stacks(src)) do
        if s.key == key then return s end
    end
end

function Wigs.FindGood(src, key)
    for _, s in ipairs(Wigs.Goods(src)) do
        if s.key == key then return s end
    end
end

function Wigs.Public(meta, value)
    if meta.bundle then
        local g = GetGrade(meta.grade)
        return {
            kind = 'bundle', serial = meta.serial, grade = meta.grade, gradeLabel = g.label, length = meta.length,
            style = meta.style, from = meta.from, ts = meta.ts, fits = meta.hair and meta.hair.m or nil,
            color = meta.hair and meta.hair.c or nil, generic = meta.generic or nil,
            label = meta.label or (g.label .. ' Bundle'), value = value,
            image = Wigs.ShotUrl(meta.hair),
        }
    end
    local t = GetTier(meta.tier)
    return {
        kind = 'wig', serial = meta.serial, tier = meta.tier, tierLabel = t.label, tint = t.color,
        style = meta.style, length = meta.length, lace = meta.lace, cond = meta.cond or 100,
        hops = meta.hops or 0, from = meta.from, by = meta.by, owners = meta.owners or {},
        ts = meta.ts, fits = meta.hair and meta.hair.m or nil, generic = meta.generic or nil,
        color = meta.hair and meta.hair.c or nil, highlight = meta.hair and meta.hair.h or nil,
        dyed = meta.dyed or nil, burnt = meta.burnt or nil, grade = meta.grade, crafted = meta.crafted,
        label = meta.label or (t.label .. ' Wig'), value = value,
        image = Wigs.ShotUrl(meta.hair),
    }
end

local function sortGoods(out)
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind == 'wig' end
        local ta, tb = TierIndex[a.tier] or GradeIndex[a.grade] or 1, TierIndex[b.tier] or GradeIndex[b.grade] or 1
        if ta ~= tb then return ta > tb end
        return (a.value or 0) > (b.value or 0)
    end)
    return out
end

function Wigs.List(src, sellPerk)
    local out = {}
    for _, s in ipairs(Wigs.Stacks(src)) do
        local pub = Wigs.Public(s.meta, Wigs.Value(s.meta, sellPerk))
        pub.key = s.key
        out[#out + 1] = pub
    end
    return sortGoods(out)
end

function Wigs.GoodsList(src, sellPerk)
    local out = {}
    for _, s in ipairs(Wigs.Goods(src)) do
        local pub = Wigs.Public(s.meta, Wigs.Value(s.meta, sellPerk))
        pub.key = s.key
        pub.pricing = Wigs.Pricing(s.meta, sellPerk)
        out[#out + 1] = pub
    end
    return sortGoods(out)
end

function Wigs.Remove(src, stack)
    return Inv.Remove(src, stack.item or WIG, 1, stack.slot)
end

function Wigs.Give(src, meta)
    local item = meta.bundle and BUNDLE or WIG
    if not Inv.HasMeta or meta.generic then return Inv.Add(src, item, 1) end
    return Inv.Add(src, item, 1, meta)
end

function Wigs.CanCarry(src, meta)
    local item = meta and meta.bundle and BUNDLE or WIG
    return Inv.CanCarry(src, item, 1, Inv.HasMeta and meta or nil)
end

-- write changed metadata back to the item in its slot
function Wigs.Update(src, stack)
    if stack.meta.bundle then Wigs.DecorateBundle(stack.meta) else Wigs.Decorate(stack.meta) end
    return Inv.SetMeta(src, stack.slot, stack.meta)
end
