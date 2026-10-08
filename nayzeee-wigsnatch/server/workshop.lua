-- Workshop: turn hair bundles into wigs, dye wigs, dye your own hair

Workshop = {}

local CW, CD = Config.Workshop, Config.Dye
local acting = {}

local function maxHair(v) return Clamp(math.floor(tonumber(v) or 0), 0, 63) end

lib.callback.register('nz-wig:workshop', function(src)
    local P = GetP(src)
    if not P then return nil end
    local bundles = {}
    for _, s in ipairs(Wigs.BundleStacks(src)) do
        local pub = Wigs.Public(s.meta, Wigs.Value(s.meta, 0))
        pub.key = s.key
        bundles[#bundles + 1] = pub
    end
    return {
        bundles = bundles,
        wigs = Wigs.List(src, 0),
        caps = Inv.Count(src, Config.Items.Cap),
        dyes = Inv.Count(src, Config.Items.Dye),
        need = CW.BundlesPerWig,
        needCap = CW.NeedCap,
        craft = CW.Enabled,
        dye = CD.Enabled,
        ownHair = CD.OwnHair,
        dyeBonus = CD.ValueBonus,
        hair = Hair.State(P),
        model = Hair.PedModelKey(src),
    }
end)

local function lowestGrade(list)
    local best
    for _, s in ipairs(list) do
        local i = GradeIndex[s.meta.grade] or 1
        if not best or i < best then best = i end
    end
    return Config.Bundles.Grades[best or 1]
end

RegisterNetEvent('nz-wig:s:craft', function(keys)
    local src = source
    local P = GetP(src)
    if not CW.Enabled or not P or acting[src] or P.busy or type(keys) ~= 'table' then return end
    if #keys ~= CW.BundlesPerWig then return Notify(src, L('craft_need', CW.BundlesPerWig), 'error') end

    local byKey = {}
    for _, s in ipairs(Wigs.BundleStacks(src)) do byKey[s.key] = s end
    local picked, seen, model = {}, {}, nil
    for _, k in ipairs(keys) do
        local s = type(k) == 'string' and not seen[k] and byKey[k]
        if not s or s.generic or not s.meta.hair then return Notify(src, L('craft_bad_bundle'), 'error') end
        seen[k] = true
        model = model or s.meta.hair.m
        if s.meta.hair.m ~= model then return Notify(src, L('craft_mixed'), 'error') end
        picked[#picked + 1] = s
    end
    if CW.NeedCap and Inv.Count(src, Config.Items.Cap) < 1 then return Notify(src, L('craft_need_cap'), 'error') end

    acting[src] = true
    SetBusy(P, true)
    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'craft', duration = CW.CraftTime, label = L('crafting') })
    SetTimeout(CW.CraftTime + 100, function()
        acting[src] = nil
        if Players[src] ~= P then return end
        SetBusy(P, false)

        -- everything still there?
        local still = {}
        for _, s in ipairs(Wigs.BundleStacks(src)) do still[s.key] = s end
        for _, s in ipairs(picked) do
            if not still[s.key] then return Notify(src, L('craft_bad_bundle'), 'error') end
        end

        local grade = lowestGrade(picked)
        local tier = grade.tier
        if math.random() < CW.UpgradeChance and TierIndex[tier] < #Config.Tiers then
            tier = Config.Tiers[TierIndex[tier] + 1].id
        end
        local len, from = 0, {}
        for _, s in ipairs(picked) do
            len = len + (s.meta.length or 14)
            if s.meta.from and #from < Config.Wig.ProvenanceSize then from[#from + 1] = s.meta.from end
        end
        len = math.floor(len / #picked)
        len = len - (len % 2)

        local first = picked[1].meta
        local meta = Wigs.Create(tier, first.hair, first.from or P.name, P.name, {
            crafted = P.name, grade = grade.id, length = len, owners = from,
        })
        if not Wigs.CanCarry(src, meta) then return Notify(src, L('pockets_full'), 'error') end

        for _, s in ipairs(picked) do
            if not Wigs.Remove(src, still[s.key]) then return Notify(src, L('invalid'), 'error') end
        end
        if CW.NeedCap then Inv.Remove(src, Config.Items.Cap, 1) end
        Wigs.Give(src, meta)

        P.row.crafted = (P.row.crafted or 0) + 1
        local xp = AddXP(P, Config.XP.Craft)
        SaveP(P)
        Clash.CatalogCheck(P, meta)
        Notify(src, L('crafted', meta.label), 'success', 6000)
        TriggerClientEvent('nz-wig:c:crafted', src, { wig = Wigs.Public(meta, Wigs.Value(meta, 0)), xp = xp })
        TriggerClientEvent('nz-wig:c:refresh', src)
        Log('workshop', 'Wig crafted', ('**%s** made %s `%s` from %d bundles'):format(P.name, meta.label, meta.serial, #picked))
    end)
end)

-- dye a wig
RegisterNetEvent('nz-wig:s:dye', function(key, c, h)
    local src = source
    local P = GetP(src)
    if not CD.Enabled or not P or acting[src] or P.busy or type(key) ~= 'string' then return end
    local stack = Wigs.Find(src, key)
    if not stack or stack.generic or not stack.meta.hair or not Inv.HasMeta then return Notify(src, L('invalid'), 'error') end
    if Inv.Count(src, Config.Items.Dye) < 1 then return Notify(src, L('need_item', Config.Items.Dye), 'error') end
    c, h = maxHair(c), maxHair(h)

    acting[src] = true
    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'dye', duration = CD.DyeTime, label = L('dyeing') })
    SetTimeout(CD.DyeTime + 100, function()
        acting[src] = nil
        if Players[src] ~= P then return end
        local s = Wigs.Find(src, key)
        if not s then return Notify(src, L('invalid'), 'error') end
        if not Inv.Remove(src, Config.Items.Dye, 1) then return end
        s.meta.hair.c, s.meta.hair.h = c, h
        s.meta.dyed = true
        Wigs.Update(src, s)
        Notify(src, L('dyed_wig'), 'success')
        TriggerClientEvent('nz-wig:c:refresh', src)
        Log('workshop', 'Wig dyed', ('**%s** dyed `%s` to %d / %d'):format(P.name, s.meta.serial or '-', c, h))
    end)
end)

-- dye your own hair
RegisterNetEvent('nz-wig:s:dyeSelf', function(c, h)
    local src = source
    local P = GetP(src)
    if not CD.Enabled or not CD.OwnHair or not P or acting[src] or P.busy then return end
    if P.hair.bald then return Notify(src, L('dye_bald'), 'error') end
    if Inv.Count(src, Config.Items.Dye) < 1 then return Notify(src, L('need_item', Config.Items.Dye), 'error') end
    c, h = maxHair(c), maxHair(h)

    acting[src] = true
    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'dye', duration = CD.DyeTime, label = L('dyeing') })
    SetTimeout(CD.DyeTime + 100, function()
        acting[src] = nil
        if Players[src] ~= P or P.hair.bald then return end
        if not Inv.Remove(src, Config.Items.Dye, 1) then return end
        P.hair.dye = { c = c, h = h }
        SaveP(P)
        Hair.Push(P, 'dye')
        Notify(src, L('dyed_self'), 'success')
        TriggerClientEvent('nz-wig:c:refresh', src)
    end)
end)

RegisterNetEvent('nz-wig:s:rinse', function()
    local P = GetP(source)
    if not P or not P.hair.dye then return end
    P.hair.dye = nil
    SaveP(P)
    Hair.Push(P, 'dye')
    Notify(P.src, L('rinsed'), 'info')
    TriggerClientEvent('nz-wig:c:refresh', P.src)
end)

OnPlayerDrop(function(src) acting[src] = nil end)
