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
    }
end

lib.callback.register('nz-wig:craftInfo', function(src) return Crafting.Info(src) end)

-- validate a make request; returns job or nil, why
function Crafting.Check(src, P, req)
    if not CC.Enabled or type(req) ~= 'table' then return nil end
    local m = req.m == 'm' and 'm' or req.m == 'f' and 'f' or nil
    local d, t = math.floor(tonumber(req.d) or -1), math.floor(tonumber(req.t) or 0)
    local c, h = Clamp(math.floor(tonumber(req.c) or 0), 0, 63), Clamp(math.floor(tonumber(req.h) or 0), 0, 63)
    if not m or d < 0 or d > 999 or t < 0 or t > 63 then return nil, L('invalid') end
    if not CC.ShortStyles and IsShortDrawable(m, d) then return nil, L('craft_short') end
    local recipe, lace = CraftRecipe(req.length, req.lace, c)
    if not recipe then return nil, L('invalid') end
    if GetLevel(P.row.xp) < lace.level then return nil, L('level_needed', lace.level) end
    for item, n in pairs(recipe) do
        if Inv.Count(src, item) < n then return nil, L('craft_missing', itemLabel(item)) end
    end
    return { m = m, d = d, t = t, c = c, h = h, length = math.floor(tonumber(req.length)), lace = lace, recipe = recipe }
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

-- supplier ---------------------------------------------------------------------------------------

local function nearSupplier(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - SU.Coords.xyz) < 6.0
end

lib.callback.register('nz-wig:supplier', function(src)
    local P = GetP(src)
    if not SU.Enabled or not P or not nearSupplier(src) then return false end
    local level = GetLevel(P.row.xp)
    local items = {}
    for name, it in pairs(SU.Items) do
        items[#items + 1] = { name = name, label = it.label, price = it.price, level = it.level or 1, locked = level < (it.level or 1), have = Inv.Count(src, name) }
    end
    table.sort(items, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.price < b.price
    end)
    return { title = SU.Label, level = level, money = Bridge.GetMoney(src, SU.Account), account = SU.Account, max = SU.MaxPerItem, items = items }
end)

lib.callback.register('nz-wig:supplierBuy', function(src, cart)
    local P = GetP(src)
    if not SU.Enabled or not P or type(cart) ~= 'table' or not nearSupplier(src) then return false end
    local level = GetLevel(P.row.xp)
    local total, lines = 0, {}
    for name, qty in pairs(cart) do
        local it = SU.Items[name]
        qty = math.floor(tonumber(qty) or 0)
        if it and qty > 0 then
            if qty > SU.MaxPerItem then return false end
            if level < (it.level or 1) then return false, L('level_needed', it.level) end
            if not Inv.CanCarry(src, name, qty) then return false, L('pockets_full') end
            total = total + it.price * qty
            lines[#lines + 1] = { name = name, qty = qty }
        end
    end
    if #lines == 0 then return false end
    if Bridge.GetMoney(src, SU.Account) < total or not Bridge.RemoveMoney(src, total, SU.Account, 'wig supplies') then
        return false, L('no_money')
    end
    local refund = 0
    for _, l in ipairs(lines) do
        if not Inv.Add(src, l.name, l.qty) then refund = refund + SU.Items[l.name].price * l.qty end
    end
    if refund > 0 then Bridge.AddMoney(src, refund, SU.Account, 'wig supplies refund') end
    Log('workshop', 'Supplies bought', ('**%s** spent $%d at %s'):format(P.name, total - refund, SU.Label))
    return true, L('bought', total - refund), Bridge.GetMoney(src, SU.Account)
end)
