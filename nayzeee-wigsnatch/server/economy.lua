-- Buyer (phone call NPC), permanent fences, selling

Economy = {}

local function now() return os.time() end

-- buyer call ---------------------------------------------------------------------------

lib.callback.register('nz-wig:buyerCall', function(src)
    local P = GetP(src)
    if not P or not Config.Buyer.Enabled then return false end
    if P.busy then return false, L('busy') end
    if P.buyer and now() < P.buyer.expires then return false, L('buyer_active') end
    if now() < (P.buyerCd or 0) then return false, L('buyer_cooldown', P.buyerCd - now()) end
    if Inv.Count(src, Config.Items.Wig) < 1 then return false, L('buyer_none') end

    P.buyerCd = now() + Config.Buyer.Cooldown
    local travel = 60 -- generous window for him to run over
    P.buyer = { at = now(), expires = now() + math.ceil(Config.Buyer.PhoneAnim.duration / 1000) + travel + Config.Buyer.WaitTime }
    return true
end)

RegisterNetEvent('nz-wig:s:buyerGone', function()
    local P = GetP(source)
    if P then P.buyer = nil P.fence = nil end
end)

-- sessions -------------------------------------------------------------------------------

local function fenceNear(src, idx)
    local f = Config.Fences[idx]
    if not f then return false end
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - vec3(f.coords.x, f.coords.y, f.coords.z)) <= 4.0
end

local function sessionValid(P)
    local s = P.fence
    if not s or now() > s.exp then return false end
    if s.kind == 'buyer' then return P.buyer ~= nil and now() <= P.buyer.expires end
    return fenceNear(P.src, s.idx)
end

lib.callback.register('nz-wig:fenceOpen', function(src, kind, idx)
    local P = GetP(src)
    if not P then return nil end
    local account
    if kind == 'buyer' then
        if not P.buyer or now() > P.buyer.expires then return nil, L('buyer_session') end
        account = Config.Buyer.Account
    elseif kind == 'fence' then
        idx = tonumber(idx)
        if not idx or not fenceNear(src, idx) then return nil end
        account = Config.Fences[idx].account or 'money'
    else
        return nil
    end
    P.fence = { kind = kind, idx = idx, account = account, exp = now() + 180 }
    local perks = GetPerks(P.row.xp)
    return {
        wigs = Wigs.List(src, perks.sell),
        market = Market.Snapshot(),
        sellPerk = math.floor(perks.sell * 100),
        dirty = account == 'black_money',
        label = kind == 'fence' and (Config.Fences[idx].label or 'Fence') or 'Buyer',
    }
end)

lib.callback.register('nz-wig:fenceSell', function(src, keys)
    local P = GetP(src)
    if not P or type(keys) ~= 'table' or #keys == 0 or #keys > 100 then return false end
    if P.busy then return false, L('busy') end
    if not sessionValid(P) then return false, L('buyer_session') end

    local byKey = {}
    for _, s in ipairs(Wigs.Stacks(src)) do byKey[s.key] = s end

    local perks = GetPerks(P.row.xp)
    local total, count, seen, lines = 0, 0, {}, {}
    for _, key in ipairs(keys) do
        local s = type(key) == 'string' and not seen[key] and byKey[key]
        if s then
            seen[key] = true
            local price = Wigs.Value(s.meta, perks.sell)
            if Wigs.Remove(src, s) then
                total = total + price
                count = count + 1
                Market.Sold(s.meta.tier, 1)
                lines[#lines + 1] = ('%s `%s` $%s'):format(s.meta.label or 'Wig', s.meta.serial or '-', price)
            end
        end
    end
    if count == 0 then return false, L('invalid') end

    Bridge.AddMoney(src, total, P.fence.account, 'wig-sale')
    P.row.wigs_sold = P.row.wigs_sold + count
    P.row.earned = P.row.earned + total
    SaveP(P)
    Notify(src, L('sold', count, total), 'success')
    Log('sell', 'Wigs sold', ('**%s** sold %s wig(s) for **$%s** (%s)\n%s'):format(P.name, count, total, P.fence.account, table.concat(lines, '\n')))

    local stillWigs = Wigs.List(src, perks.sell)
    return true, { sold = count, total = total, wigs = stillWigs, market = Market.Snapshot() }
end)
