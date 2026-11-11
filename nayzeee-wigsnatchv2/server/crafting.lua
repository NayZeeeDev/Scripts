-- Wig making from materials, and the supplier who sells them.
-- The making itself runs as a job at a wig table (server/workshop.lua, kind 'make');
-- this file holds the recipe checks and the shop.

Crafting = {}

local CC, SU = Config.Crafting, Config.Supplier

local function natural(c)
    for _, n in ipairs(CC.NaturalColours) do if n == c then return true end end
    return false
end

local function itemLabel(name)
    local s = SU.Items[name]
    return s and s.label or name
end
Crafting.ItemLabel = itemLabel

-- what the table window needs to show the recipe and what you have
function Crafting.Info(src)
    local P = GetP(src)
    if not CC.Enabled or not P then return false end
    local level = GetLevel(P.row.xp)
    local names = {}
    for item in pairs(CC.Base) do names[item] = true end
    names[CC.WeftItem], names[Config.Items.Dye] = true, true
    local laces = {}
    for i, l in ipairs(CC.Laces) do
        for item in pairs(l.items) do names[item] = true end
        local t = GetTier(l.tier)
        laces[i] = { id = l.id, label = l.label, tier = l.tier, level = l.level, locked = level < l.level, items = l.items,
                     price = { t.price[1], t.price[2] } }
    end
    local have, labels = {}, {}
    for item in pairs(names) do have[item], labels[item] = Inv.Count(src, item), itemLabel(item) end
    return {
        level = level, have = have, labels = labels, laces = laces, base = CC.Base,
        weft = CC.WeftItem, weftInches = CC.WeftInches, lengths = CC.Lengths, dye = Config.Items.Dye,
        natural = CC.NaturalColours, shortStyles = CC.ShortStyles, supplier = SU.Enabled and SU.Label or nil,
        skipTextures = { f = (CC.SkipTextures or {}).f or {}, m = (CC.SkipTextures or {}).m or {} },
    }
end


-- validate a make request; returns job or nil, why
function Crafting.Check(src, P, req)
    if not CC.Enabled or type(req) ~= 'table' then return nil end
    local m = req.m == 'm' and 'm' or req.m == 'f' and 'f' or nil
    local d, t = math.floor(SafeNumber(req.d) or -1), math.floor(SafeNumber(req.t) or 0)
    local c, h = Clamp(math.floor(SafeNumber(req.c) or 0), 0, 63), Clamp(math.floor(SafeNumber(req.h) or 0), 0, 63)
    if not m or d < 0 or d > 999 or t < 0 or t > 63 then return nil, L('invalid') end
    if not CC.ShortStyles and IsShortDrawable(m, d) then return nil, L('craft_short') end
    for _, skip in ipairs((CC.SkipTextures or {})[m] or {}) do
        if skip == t then return nil, L('invalid') end
    end
    local recipe, lace = CraftRecipe(req.length, req.lace, c)
    if not recipe then return nil, L('invalid') end
    if GetLevel(P.row.xp) < lace.level then return nil, L('level_needed', lace.level) end
    for item, n in pairs(recipe) do
        if Inv.Count(src, item) < n then return nil, L('craft_missing', itemLabel(item)) end
    end
    return { m = m, d = d, t = t, c = c, h = h, length = math.floor(SafeNumber(req.length) or 0), lace = lace, recipe = recipe }
end

-- takes every material or none
local function take(src, recipe)
    local taken = {}
    for item, n in pairs(recipe) do
        if not Inv.Remove(src, item, n) then
            for i, c in pairs(taken) do Inv.Add(src, i, c) end
            return false
        end
        taken[item] = n
    end
    return true
end

-- the job finished at the table: build the wig
function Crafting.Make(src, P, job, checks)
    local again = Crafting.Check(src, P, { m = job.m, d = job.d, t = job.t, c = job.c, h = job.h, length = job.length, lace = job.lace.id })
    if not again then return Notify(src, L('materials_gone'), 'error') end
    local passed, failed = checks.passed, checks.failed
    local tier = job.lace.tier
    if math.random() < passed * Config.Tables.CheckUpgrade and TierIndex[tier] < TierIndex['epic'] then
        tier = Config.Tiers[TierIndex[tier] + 1].id
    end
    local meta = Wigs.Create(tier, { m = job.m, d = job.d, t = job.t, c = job.c, h = job.h }, P.name, P.name, {
        crafted = P.name, length = job.length, lace = job.lace.label, owners = { P.name },
        dyed = not natural(job.c) or nil,
    })
    if failed > 0 then meta.cond = math.max(20, 100 - failed * Config.Tables.FailCondition) end
    Wigs.Decorate(meta)
    if not Wigs.CanCarry(src, meta) then return Notify(src, L('pockets_full'), 'error') end
    if not take(src, job.recipe) then return Notify(src, L('materials_gone'), 'error') end
    Wigs.Give(src, meta)

    P.row.crafted = (P.row.crafted or 0) + 1
    local xp = AddXP(P, CC.XP + ((failed == 0 and passed > 0) and Config.Tables.PerfectXP or 0))
    SaveP(P)
    Clash.CatalogCheck(P, meta)
    Notify(src, L('crafted', meta.label), 'success', 6000)
    TriggerClientEvent('nz-wig:c:crafted', src, { wig = Wigs.Public(meta, Wigs.Value(meta, 0)), xp = xp })
    TriggerClientEvent('nz-wig:c:refresh', src)
    Log('workshop', 'Wig made', ('**%s** made %s `%s` from materials (%d/%d checks)'):format(P.name, meta.label, meta.serial, passed, passed + failed))
    return meta
end

-- wig tables off (or not required): make it on the spot, no stages or checks
local making = {}
RegisterNetEvent('nz-wig:s:make', function(req)
    local src = source
    local P = GetP(src)
    if not P or P.busy or making[src] then return end
    if Config.Tables.Enabled then return Notify(src, L('table_needed'), 'error') end
    local job, why = Crafting.Check(src, P, req)
    if not job then return Notify(src, why or L('invalid'), 'error') end
    making[src] = true
    SetBusy(P, true)
    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'craft', duration = Config.Workshop.CraftTime, label = L('crafting') })
    SetTimeout(Config.Workshop.CraftTime + 100, function()
        making[src] = nil
        if Players[src] ~= P then return end
        SetBusy(P, false)
        Crafting.Make(src, P, job, { passed = 0, failed = 0 })
    end)
end)

OnPlayerDrop(function(src) making[src] = nil end)

-- suppliers: the Hair Supply (wig making) and the Beauty Supply (the salon) -----------------------

local SHOPS = { hair = Config.Supplier, beauty = Config.BeautySupply }
local function shopOf(id)
    local sh = SHOPS[id or 'hair']
    return sh and sh.Enabled and sh or nil
end

local function nearSupplier(src, sh)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - sh.Coords.xyz) < 6.0
end

-- what the player can pay with (Accounts, or the older single Account)
local function accounts(sh)
    local list = sh.Accounts or { sh.Account or 'cash' }
    return #list > 0 and list or { 'cash' }
end

local function payWith(sh, acc)
    for _, a in ipairs(accounts(sh)) do if a == acc then return a end end
    return accounts(sh)[1]
end

local function wallets(src, sh)
    local out = {}
    for i, a in ipairs(accounts(sh)) do out[i] = { id = a, money = Bridge.GetMoney(src, a) } end
    return out
end

-- extension hair comes in shades, lengths and textures; a longer pack costs more
local function variantsOf(name, it)
    local h = Config.Salon and Config.Salon.Hair[name]
    if not h or not it.variants then return nil end
    local shades = {}
    if h.shades then
        for i, sh in ipairs(Config.Salon.Shades) do shades[i] = { id = sh.id, label = sh.label, rgb = sh.rgb, tip = sh.tip } end
    end
    return { shades = shades, lengths = h.lengths, textures = h.textures, perInch = it.perInch or 0, base = h.lengths and h.lengths[1] or nil }
end

-- a basket key: 'item' or 'item|shade|length|texture'. Returns item, meta, unit price
local function parseKey(sh, key)
    if type(key) ~= 'string' then return nil end
    local name, shade, len, tex = key:match('^([%w_]+)|([^|]*)|([^|]*)|([^|]*)$')
    if not name then
        local it = sh.Items[key]
        if not it or it.variants then return nil end
        return key, nil, it.price, it
    end
    local it = sh.Items[name]
    local h = Config.Salon and Config.Salon.Hair[name]
    if not it or not it.variants or not h then return nil end
    local okShade = false
    for _, s in ipairs(Config.Salon.Shades) do if s.id == shade then okShade = true end end
    if h.shades and not okShade then return nil end
    len = tonumber(len)
    local okLen = not h.lengths
    for _, l in ipairs(h.lengths or {}) do if l == len then okLen = true end end
    if not okLen then return nil end
    local okTex = not h.textures
    for _, t in ipairs(h.textures or {}) do if t == tex then okTex = true end end
    if not okTex then return nil end
    local price = it.price + (it.perInch or 0) * math.max(0, (len or 0) - ((h.lengths or {})[1] or 0))
    return name, Salon.PackMeta(name, h.shades and shade or nil, len, h.textures and tex or nil), math.floor(price + 0.5), it
end

lib.callback.register('nz-wig:supplier', function(src, shopId)
    local P = GetP(src)
    local sh = shopOf(shopId)
    if not sh or not P or not nearSupplier(src, sh) then return false end
    local level = GetLevel(P.row.xp)
    local items = {}
    for name, it in pairs(sh.Items) do
        items[#items + 1] = { name = name, label = it.label, desc = it.desc, cat = it.cat, price = it.price, level = it.level or 1, max = it.max,
                              locked = level < (it.level or 1), have = Inv.Count(src, name), variants = variantsOf(name, it) }
    end
    -- in tab order, then by level and price
    local catIndex = {}
    for i, c in ipairs(sh.Categories or {}) do catIndex[c.id] = i end
    table.sort(items, function(a, b)
        local ca, cb = catIndex[a.cat] or 99, catIndex[b.cat] or 99
        if ca ~= cb then return ca < cb end
        if a.level ~= b.level then return a.level < b.level end
        if a.price ~= b.price then return a.price < b.price end
        return a.label < b.label
    end)
    return { id = shopId or 'hair', title = sh.Label, level = level, accounts = wallets(src, sh), max = sh.MaxPerItem, items = items, categories = sh.Categories or {} }
end)

lib.callback.register('nz-wig:supplierBuy', function(src, cart, acc, shopId)
    local P = GetP(src)
    local sh = shopOf(shopId)
    if not sh or not P or type(cart) ~= 'table' or not nearSupplier(src, sh) then return false end
    acc = payWith(sh, acc)
    local level = GetLevel(P.row.xp)
    local total, lines, per = 0, {}, {}
    for key, qty in pairs(cart) do
        local name, meta, price, it = parseKey(sh, key)
        qty = math.floor(SafeNumber(qty) or 0)
        if not name and qty > 0 then return false end
        if name and qty > 0 then
            per[name] = (per[name] or 0) + qty
            if per[name] > (it.max or sh.MaxPerItem) then return false end
            if level < (it.level or 1) then return false, L('level_needed', it.level) end
            if not Inv.CanCarry(src, name, qty, meta) then return false, L('pockets_full') end
            total = total + price * qty
            lines[#lines + 1] = { name = name, qty = qty, meta = meta, price = price }
        end
    end
    if #lines == 0 then return false end
    if Bridge.GetMoney(src, acc) < total or not Bridge.RemoveMoney(src, total, acc, 'supplies') then
        return false, L('no_money')
    end
    local refund = 0
    for _, l in ipairs(lines) do
        if not Inv.Add(src, l.name, l.qty, l.meta) then refund = refund + l.price * l.qty end
    end
    if refund > 0 then Bridge.AddMoney(src, refund, acc, 'supplies refund') end
    Log('workshop', 'Supplies bought', ('**%s** spent $%d (%s) at %s'):format(P.name, total - refund, acc, sh.Label))
    return true, L('bought', total - refund), wallets(src, sh)
end)
