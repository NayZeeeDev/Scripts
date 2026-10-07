-- Bounties, city feed, player-to-player trades, passive mode, Discord logs

Social = {}

local function now() return os.time() end
local fee = function(amount) return math.floor(amount * (1 - Config.Bounty.Fee)) end

-- logs ---------------------------------------------------------------------------------

local function hexColor(c)
    if type(c) == 'number' then return c end
    if type(c) == 'string' then return tonumber(c:gsub('#', ''), 16) or 562082 end
    return 569250 -- #08afa2
end

function Log(kind, title, desc, color)
    local cfg = ServerConfig.Logs
    if not cfg.Enabled then return end
    local hook = cfg.Webhooks[kind]
    if not hook or hook == '' then return end
    PerformHttpRequest(hook, function() end, 'POST', json.encode({
        username = cfg.Name,
        avatar_url = cfg.Avatar ~= '' and cfg.Avatar or nil,
        embeds = { {
            title = title,
            description = desc,
            color = hexColor(color),
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- feed -----------------------------------------------------------------------------------

local Feed = {}

function Social.PushFeed(entry)
    table.insert(Feed, 1, entry)
    while #Feed > Config.Vault.FeedSize do table.remove(Feed) end
end

function Social.Feed() return Feed end

-- bounties ---------------------------------------------------------------------------------

local Open = {} -- [id] = bounty row

local function refundExpired(placerId)
    local where, params = "status = 'expired'", {}
    if placerId then where = where .. ' AND placer = ?' params[1] = placerId end
    local rows = MySQL.query.await('SELECT * FROM nz_wig_bounties WHERE ' .. where, params)
    for _, b in ipairs(rows or {}) do
        local src = ById[b.placer]
        if src and Players[src] then
            local back = fee(b.amount)
            local changed = MySQL.update.await("UPDATE nz_wig_bounties SET status = 'refunded' WHERE id = ? AND status = 'expired'", { b.id })
            if changed and changed > 0 then
                Bridge.AddMoney(src, back, Config.Bounty.Account, 'wig-bounty-refund')
                Notify(src, L('bounty_refund', b.target_name, back), 'info', 7000)
                Log('bounty', 'Bounty refunded', ('%s got $%s back for the bounty on %s'):format(b.placer_name, back, b.target_name))
            end
        end
    end
end

function Social.ExpireBounties()
    local cutoff = now() - Config.Bounty.ExpireHours * 3600
    for id, b in pairs(Open) do
        if b.created < cutoff then Open[id] = nil end
    end
    MySQL.update.await("UPDATE nz_wig_bounties SET status = 'expired', closed = ? WHERE status = 'open' AND created < ?", { now(), cutoff })
    refundExpired()
end

function Social.LoadBounties()
    Open = {}
    for _, b in ipairs(MySQL.query.await("SELECT * FROM nz_wig_bounties WHERE status = 'open'") or {}) do
        Open[b.id] = b
    end
    Social.ExpireBounties()
end

function Social.HasBounty(identifier)
    for _, b in pairs(Open) do
        if b.target == identifier then return true end
    end
    return false
end

function Social.BountyOn(identifier)
    local total = 0
    for _, b in pairs(Open) do
        if b.target == identifier then total = total + fee(b.amount) end
    end
    return total
end

function Social.Board()
    local byTarget = {}
    for _, b in pairs(Open) do
        local e = byTarget[b.target]
        if not e then
            e = { identifier = b.target, name = b.target_name, total = 0, count = 0, placers = {} }
            byTarget[b.target] = e
        end
        e.total = e.total + fee(b.amount)
        e.count = e.count + 1
        e.online = ById[b.target] ~= nil
        if #e.placers < 3 then e.placers[#e.placers + 1] = b.placer_name end
        e.created = math.max(e.created or 0, b.created)
    end
    local list = {}
    for _, e in pairs(byTarget) do list[#list + 1] = e end
    table.sort(list, function(a, b) return a.total > b.total end)
    return list
end

function Social.ClaimBounties(A, V)
    if not Config.Bounty.Enabled then return 0 end
    local ids, total, n = {}, 0, 0
    for id, b in pairs(Open) do
        if b.target == V.id then
            ids[#ids + 1] = id
            total = total + fee(b.amount)
            n = n + 1
        end
    end
    if n == 0 then return 0 end
    for _, id in ipairs(ids) do Open[id] = nil end
    MySQL.update.await("UPDATE nz_wig_bounties SET status = 'claimed', claimed_by = ?, claimed_name = ?, closed = ? WHERE target = ? AND status = 'open'",
        { A.id, A.name, now(), V.id })
    Bridge.AddMoney(A.src, total, Config.Bounty.Account, 'wig-bounty')
    A.row.bounties_claimed = A.row.bounties_claimed + n
    A.row.bounty_earned = A.row.bounty_earned + total
    DB.AddFeed('claim', A.id, A.name, V.id, V.name, nil, nil, total)
    Social.PushFeed({ kind = 'claim', actor_name = A.name, target_name = V.name, amount = total, created = now() })
    Log('bounty', 'Bounty claimed', ('**%s** claimed **$%s** for snatching **%s** (%s bounties)'):format(A.name, total, V.name, n))
    return total
end

lib.callback.register('nz-wig:placeBounty', function(src, targetId, amount)
    local P = GetP(src)
    if not P or not Config.Bounty.Enabled or type(targetId) ~= 'string' then return false, L('invalid') end
    amount = math.floor(tonumber(amount) or 0)
    if amount < Config.Bounty.Min or amount > Config.Bounty.Max then
        return false, L('bounty_bad_amount', Config.Bounty.Min, Config.Bounty.Max)
    end
    if targetId == P.id then return false, L('bounty_self') end

    local name
    local since = now() - Config.Bounty.RevengeHours * 3600
    if Config.Bounty.OnlyRevenge then
        for _, r in ipairs(DB.RecentSnatchers(P.id, since) or {}) do
            if r.identifier == targetId then name = r.name break end
        end
        if not name then return false, L('bounty_not_allowed') end
    else
        local tsrc = ById[targetId]
        name = tsrc and Players[tsrc] and Players[tsrc].name
            or MySQL.scalar.await('SELECT name FROM nz_wig_players WHERE identifier = ?', { targetId })
        if not name then return false, L('invalid') end
    end

    if not Bridge.RemoveMoney(src, amount, Config.Bounty.Account, 'wig-bounty') then return false, L('no_money') end

    local id = MySQL.insert.await('INSERT INTO nz_wig_bounties (target, target_name, placer, placer_name, amount, created) VALUES (?, ?, ?, ?, ?, ?)',
        { targetId, name, P.id, P.name, amount, now() })
    Open[id] = { id = id, target = targetId, target_name = name, placer = P.id, placer_name = P.name, amount = amount, created = now() }

    DB.AddFeed('bounty', P.id, P.name, targetId, name, nil, nil, fee(amount))
    Social.PushFeed({ kind = 'bounty', actor_name = P.name, target_name = name, amount = fee(amount), created = now() })
    Log('bounty', 'Bounty placed', ('**%s** put **$%s** on **%s**'):format(P.name, amount, name))

    local tsrc = ById[targetId]
    if tsrc then TriggerClientEvent('nz-wig:c:bountyOnYou', tsrc, Social.BountyOn(targetId)) end
    if Config.Bounty.BroadcastAt and Social.BountyOn(targetId) >= Config.Bounty.BroadcastAt then
        TriggerClientEvent('nz-wig:c:banner', -1, { kind = 'bounty', target = name, amount = Social.BountyOn(targetId), city = true })
    end
    return true, L('bounty_placed', amount, name)
end)

-- trades -------------------------------------------------------------------------------------

local Offers, oseq = {}, 0 -- [targetSrc] = offer

lib.callback.register('nz-wig:nearby', function(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return {} end
    local out = {}
    for _, s in ipairs(PlayersNear(GetEntityCoords(ped), Config.Trading.Range, src)) do
        local P = Players[s]
        if P then out[#out + 1] = { src = s, name = P.name, dist = math.floor(PedDistance(src, s) * 10) / 10 } end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end)

lib.callback.register('nz-wig:offer', function(src, target, key, price)
    local P = GetP(src)
    target = tonumber(target)
    local T = target and GetP(target)
    if not P or not T or T == P or not Config.Trading.Enabled then return false, L('invalid') end
    if P.busy then return false, L('busy') end
    price = math.floor(tonumber(price) or 0)
    if price < 0 or price > Config.Trading.MaxPrice then return false, L('invalid') end
    if PedDistance(src, target) > Config.Trading.Range then return false, L('trade_too_far') end
    if Offers[target] then return false, L('trade_pending') end
    local stack = type(key) == 'string' and Wigs.Find(src, key)
    if not stack then return false, L('invalid') end

    oseq = oseq + 1
    local offer = { id = oseq, from = src, fromId = P.id, to = target, key = key, price = price, exp = now() + Config.Trading.Timeout }
    Offers[target] = offer
    local pub = Wigs.Public(stack.meta, Wigs.Value(stack.meta, 0))
    TriggerClientEvent('nz-wig:c:prompt', target, {
        kind = 'trade', id = offer.id, timeout = Config.Trading.Timeout,
        title = L('trade_prompt_title'),
        body = price > 0 and L('trade_prompt_sell', P.name, price) or L('trade_prompt_gift', P.name),
        wig = pub, price = price,
    })
    SetTimeout(Config.Trading.Timeout * 1000 + 500, function()
        if Offers[target] == offer then
            Offers[target] = nil
            TriggerClientEvent('nz-wig:c:promptClose', target, offer.id)
            if Players[src] then Notify(src, L('trade_expired'), 'warning') end
        end
    end)
    return true, L('trade_sent', T.name)
end)

local function offerReply(src, id, accept)
    local offer = Offers[src]
    if not offer or offer.id ~= id then return end
    Offers[src] = nil
    local S, B = GetP(offer.from), GetP(src)
    if not B then return end
    if not S or S.id ~= offer.fromId then return Notify(src, L('trade_failed'), 'error') end
    if not accept then return Notify(offer.from, L('trade_declined', B.name), 'warning') end

    if PedDistance(offer.from, src) > Config.Trading.Range + 2.0 then
        Notify(src, L('trade_too_far'), 'error')
        return Notify(offer.from, L('trade_failed'), 'error')
    end
    local stack = Wigs.Find(offer.from, offer.key)
    if not stack or not Wigs.CanCarry(src, stack.meta) then
        Notify(src, stack and L('pockets_full') or L('trade_failed'), 'error')
        return Notify(offer.from, L('trade_failed'), 'error')
    end
    if offer.price > 0 and not Bridge.RemoveMoney(src, offer.price, Config.Trading.Account, 'wig-trade') then
        Notify(src, L('no_money'), 'error')
        return Notify(offer.from, L('trade_failed'), 'error')
    end
    if not Wigs.Remove(offer.from, stack) then
        if offer.price > 0 then Bridge.AddMoney(src, offer.price, Config.Trading.Account, 'wig-trade-refund') end
        return Notify(src, L('trade_failed'), 'error')
    end
    if not Wigs.Give(src, stack.meta) then
        Wigs.Give(offer.from, stack.meta)
        if offer.price > 0 then Bridge.AddMoney(src, offer.price, Config.Trading.Account, 'wig-trade-refund') end
        return Notify(src, L('trade_failed'), 'error')
    end
    if offer.price > 0 then Bridge.AddMoney(offer.from, offer.price, Config.Trading.Account, 'wig-trade') end

    Notify(src, L('trade_done_buyer'), 'success')
    Notify(offer.from, L('trade_accepted', B.name), 'success')
    TriggerClientEvent('nz-wig:c:refresh', offer.from)
    Log('trade', 'Wig traded', ('**%s** → **%s** · %s `%s` · $%s'):format(S.name, B.name, stack.meta.label or 'Wig', stack.meta.serial or '-', offer.price))
end

RegisterNetEvent('nz-wig:s:promptReply', function(kind, id, accept)
    local src = source
    id = tonumber(id)
    accept = accept == true
    if kind == 'trade' then offerReply(src, id, accept)
    elseif kind == 'haircut' then Tools.Reply(src, id, accept) end
end)

-- revenge / bounty targets for the vault
function Social.RevengeList(P)
    local since = now() - Config.Bounty.RevengeHours * 3600
    local out = {}
    for _, r in ipairs(DB.RecentSnatchers(P.id, since) or {}) do
        out[#out + 1] = { identifier = r.identifier, name = r.name, last = r.last, times = r.times,
            online = ById[r.identifier] ~= nil, bounty = Social.BountyOn(r.identifier) }
    end
    return out
end

-- passive ---------------------------------------------------------------------------------------

if Config.Protection.Passive.Enabled then
    RegisterCommand(Config.Protection.Passive.Command, function(src)
        local P = GetP(src)
        if not P or P.busy then return end
        local left = (P.row.passive_at or 0) + Config.Protection.Passive.Cooldown - now()
        if left > 0 then return Notify(src, L('passive_cooldown', math.ceil(left / 60)), 'error') end
        local on = not IsPassive(P)
        P.row.passive = on and 1 or 0
        P.row.passive_at = now()
        SaveP(P)
        SyncP(P)
        Notify(src, on and L('passive_on') or L('passive_off'), on and 'success' or 'info')
    end, false)
end

-- lifecycle -------------------------------------------------------------------------------------

function Social.OnLoad(P)
    if Config.Bounty.Enabled then
        refundExpired(P.id)
        local on = Social.BountyOn(P.id)
        if on > 0 then TriggerClientEvent('nz-wig:c:bountyOnYou', P.src, on) end
    end
end

function Social.OnDrop(src)
    if Offers[src] then Offers[src] = nil end
    for t, o in pairs(Offers) do
        if o.from == src then
            Offers[t] = nil
            TriggerClientEvent('nz-wig:c:promptClose', t, o.id)
        end
    end
end

function Social.LoadFeed()
    Feed = {}
    for _, r in ipairs(DB.RecentFeed(Config.Vault.FeedSize) or {}) do Feed[#Feed + 1] = r end
end
