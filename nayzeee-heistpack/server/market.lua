--[[ Black market with drone delivery. All prices / levels validated here. ]]

local Market = lib.load('config.market')
local orders = {} -- identifier -> { items, total, account, readyAt } (survives reconnects)
local byName = {}
for i = 1, #Market.items do byName[Market.items[i].name] = Market.items[i] end

local function giveOrder(src, order)
    for i = 1, #order.items do
        local it = order.items[i]
        Inv.add(src, it.name, it.amount)
    end
end

Guard.callback('nzh:market:data', function(src)
    local o = orders[FW.identifier(src)]
    return {
        enabled = Market.enabled,
        items = Market.items,
        categories = Market.categories,
        maxPerItem = Market.maxPerItem,
        order = o and { remaining = math.max(0, o.readyAt - os.time()), total = o.total } or nil,
    }
end)

Guard.callback('nzh:market:buy', function(src, cart, account)
    if not Market.enabled then return false, locale('market_disabled') end
    if not Guard.rate(src, 'buy', 2000) then return false, locale('slow_down') end
    local identifier = FW.identifier(src)
    if not identifier then return false end
    if orders[identifier] then return false, locale('market_has_order') end
    if account ~= 'cash' and account ~= 'bank' then return false end
    if type(cart) ~= 'table' or #cart == 0 or #cart > 20 then return false end

    local level = Profile.level(src)
    local items, total = {}, 0
    for i = 1, #cart do
        local row = cart[i]
        local def = type(row) == 'table' and byName[row.name]
        local amount = def and math.floor(tonumber(row.amount) or 0)
        if not def or amount < 1 or amount > Market.maxPerItem then return false, locale('market_invalid') end
        if level < (def.level or 1) then return false, locale('market_level', def.label, def.level) end
        items[#items + 1] = { name = def.name, amount = amount, label = def.label }
        total = total + def.price * amount
    end

    local acc = Config.Money.marketAccounts[account]
    if not FW.removeMoney(src, acc, total, 'heist-market') then
        return false, locale('not_enough_money', Utils.money(total))
    end

    local order = { items = items, total = total, account = acc, readyAt = os.time() + Market.delivery.seconds }
    if Market.delivery.seconds <= 0 then
        giveOrder(src, order)
        return true, { instant = true }
    end
    orders[identifier] = order
    Logs.send('Market order', ('%s bought %d item types for $%s'):format(GetPlayerName(src), #items, Utils.money(total)))
    return true, { seconds = Market.delivery.seconds, total = total }
end)

Guard.callback('nzh:market:collect', function(src)
    local identifier = FW.identifier(src)
    local o = identifier and orders[identifier]
    if not o then return false end
    if os.time() < o.readyAt then return false, locale('market_not_ready') end
    orders[identifier] = nil
    giveOrder(src, o)
    return true
end)
