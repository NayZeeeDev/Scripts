-- Hair products: put them in someone else's hair (or your own).
-- fallout = hair falls out, burn / lice / dirt = statuses that wear off, clean = shampoo, regrow = regrowth oil

Products = {}

local CP = Config.Products
local acting = {}

local function now() return os.time() end

local BENIGN = { clean = true, regrow = true }

-- can `src` put product `p` on `target` right now? returns ok, err
local function canApply(P, V, p)
    if BENIGN[p.Effect] then return true end
    local ok, key, extra = CanAttack(P)
    if not ok then return false, key == 'cooldown' and L('cooldown', extra) or L(key) end
    local okT, keyT = CanBeTarget(V)
    if not okT then return false, L(keyT) end
    if p.Requires == 'any' then return true end
    local helpless = IsRestrainedSrc(V.src) or Restrain.HeldBy(V.src) ~= nil
    if not helpless then
        local q = Clash.QueryHair(V.src, 2000)
        helpless = q and (q.handsUp or q.restrained or q.downed)
    end
    if helpless then return true end
    if p.Requires == 'behind' and IsBehindSrc(P.src, V.src, Config.Clash.Blindside.Angle) then return true end
    return false, L(p.Requires == 'behind' and 'product_behind' or 'product_restrained')
end

-- does the effect do anything to V? returns ok, err
local function precheck(V, p)
    local e = p.Effect
    if e == 'fallout' or e == 'burn' then
        if V.hair.wig then return false, L('product_wig') end
        if V.hair.bald then return false, L('already_bald') end
    elseif e == 'clean' then
        local any = false
        for _, k in ipairs(p.Cleans or {}) do any = any or Hair.HasStatus(V, k) end
        if not any then return false, L('product_nothing_clean') end
    elseif e == 'regrow' then
        local h = V.hair
        if not h.bald and not h.cut and not h.face and not Hair.HasStatus(V, 'burn') then return false, L('product_nothing_regrow') end
    end
    return true
end

local function apply(V, p)
    local e = p.Effect
    if e == 'fallout' then
        local model = Hair.PedModelKey(V.src) or 'f'
        Hair.SetBald(V, model, p.Minutes)
        V.immuneUntil = now() + Config.Protection.VictimImmunity
    elseif e == 'burn' then
        Hair.SetStatus(V, 'burn', p.Minutes)
        if (p.Damage or 0) > 0 then TriggerClientEvent('nz-wig:c:hurt', V.src, p.Damage) end
    elseif e == 'lice' or e == 'dirt' then
        Hair.SetStatus(V, e, p.Minutes)
    elseif e == 'clean' then
        for _, k in ipairs(p.Cleans or {}) do Hair.ClearStatus(V, k) end
    elseif e == 'regrow' then
        Hair.Regrow(V, p.Minutes)
    end
    SaveP(V)
    Hair.Push(V, 'product')
end

RegisterNetEvent('nz-wig:s:product', function(productId, target)
    local src = source
    local P = GetP(src)
    local p = type(productId) == 'string' and CP.List[productId]
    if not P or not p or acting[src] then return end
    target = tonumber(target)
    local self = not target or target == src
    if self and not p.Self then return Notify(src, L('product_not_self'), 'error') end
    if not self and not p.Others then return Notify(src, L('product_only_self'), 'error') end
    if P.busy then return Notify(src, L('busy'), 'error') end
    if Inv.Count(src, p.Item) < 1 then return Notify(src, L('need_item', p.Label), 'error') end

    local V = self and P or GetP(target)
    if not V then return Notify(src, L('no_one_close'), 'error') end
    if not self then
        if V.busy and not BENIGN[p.Effect] then return Notify(src, L('target_busy'), 'error') end
        if PedDistance(src, V.src) > CP.Range + 1.0 then return Notify(src, L('no_one_close'), 'error') end
    end

    acting[src] = true
    local ok, err = precheck(V, p)
    if ok and not self then ok, err = canApply(P, V, p) end
    if not ok then
        acting[src] = nil
        return Notify(src, err, 'error')
    end

    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'product', other = not self and V.src or nil, duration = CP.ApplyTime, label = p.Label })
    SetTimeout(CP.ApplyTime + 100, function()
        acting[src] = nil
        if Players[src] ~= P or Players[V.src] ~= V then return end
        if not self and PedDistance(src, V.src) > CP.Range + 2.0 then return Notify(src, L('too_far_moved'), 'error') end
        local still, err2 = precheck(V, p)
        if not still then return Notify(src, err2, 'error') end
        if not Inv.Remove(src, p.Item, 1) then return Notify(src, L('need_item', p.Label), 'error') end

        apply(V, p)
        React(V.src, p.Effect, 300)
        local fx = L('product_fx_' .. p.Effect)
        if self then
            Notify(src, L('product_self', p.Label), 'success')
        else
            Notify(src, L('product_done', p.Label, V.name), 'success')
            Notify(V.src, L('product_victim', P.name, fx), BENIGN[p.Effect] and 'success' or 'error', 6000)
            if not BENIGN[p.Effect] then
                P.row.products = (P.row.products or 0) + 1
                AddXP(P, Config.XP.Product)
                SaveP(P)
                DB.AddFeed('product', P.id, P.name, V.id, V.name, nil, p.Label, 0)
                Social.PushFeed({ kind = 'product', actor_name = P.name, target_name = V.name, label = p.Label, created = now() })
                Log('product', 'Product used', ('**%s** put %s in **%s**\'s hair'):format(P.name, p.Label, V.name))
            end
        end
    end)
end)

-- lice jump to anyone who grabs your head (snatching, cutting)
function Products.Spread(from, to)
    local s = CP.Status.lice
    if not s or not s.Spread or not from or not to or from == to then return end
    if not Hair.HasStatus(from, 'lice') or Hair.HasStatus(to, 'lice') then return end
    local left = math.max(5, math.floor((from.hair.status.lice - now()) / 60))
    Hair.SetStatus(to, 'lice', left)
    SaveP(to)
    Hair.Push(to, 'lice')
    Notify(to.src, L('lice_caught', from.name), 'warning', 6000)
    React(to.src, 'lice', 1200)
end

-- the client says it went swimming while dirty
RegisterNetEvent('nz-wig:s:washed', function()
    local P = GetP(source)
    if not P or not CP.Status.dirt or not CP.Status.dirt.WaterCleans then return end
    if Hair.ClearStatus(P, 'dirt') then
        SaveP(P)
        Hair.Push(P, 'washed')
        Notify(P.src, L('washed_off'), 'success')
    end
end)

OnPlayerDrop(function(src) acting[src] = nil end)

function Products.RegisterItems()
    for id, p in pairs(CP.List) do
        Bridge.RegisterUsable(p.Item, function(src) TriggerClientEvent('nz-wig:c:useProduct', src, id) end)
    end
end

-- which products I have (for the picker on another player)
lib.callback.register('nz-wig:productCounts', function(src)
    local out = {}
    for id, p in pairs(CP.List) do
        local n = Inv.Count(src, p.Item)
        if n > 0 then out[#out + 1] = { id = id, label = p.Label, count = n, effect = p.Effect, others = p.Others, self = p.Self, requires = p.Requires } end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)
