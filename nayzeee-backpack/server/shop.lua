-----------------------------------------------------------------
-- Bag store (server)
--
-- Price, funds and inventory space are all checked here. The UI
-- only ever asks.
-----------------------------------------------------------------

if not Config.Shop or not Config.Shop.enabled then return end

local ox = exports.ox_inventory
local cfg = Config.Shop

local function money(src)
    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if not xPlayer then return 0 end

    if cfg.currency == 'bank' then
        return xPlayer.getAccount('bank').money
    end
    return xPlayer.getMoney()
end

local function take(src, amount)
    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if not xPlayer then return false end

    if cfg.currency == 'bank' then
        if xPlayer.getAccount('bank').money < amount then return false end
        xPlayer.removeAccountMoney('bank', amount)
    else
        if xPlayer.getMoney() < amount then return false end
        xPlayer.removeMoney(amount)
    end
    return true
end

local function give(src, amount)
    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    if cfg.currency == 'bank' then
        xPlayer.addAccountMoney('bank', amount)
    else
        xPlayer.addMoney(amount)
    end
end

-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:buy', function(bagKey, variant)
    local src = source
    local bag = Config.Backpacks[bagKey]

    -- a bag with no price isn't for sale, whatever the client claims
    if not bag or not bag.price then
        return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.shop_broke)
    end

    variant = tonumber(variant) or 0
    if variant ~= 0 and not (bag.variants and bag.variants[variant]) then
        variant = 0
    end

    -- job bags: the client already hides them, but never trust that
    if bag.job and not ServerCanUseBag(src, bagKey) then
        return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.shop_job)
    end

    if Config.OneBagOnly then
        local held = ox:Search(src, 'count', bagKey)
        if type(held) == 'number' and held > 0 then
            return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.one_bag_only)
        end
    end

    if not ox:CanCarryItem(src, bagKey, 1) then
        return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.shop_full)
    end

    if money(src) < bag.price then
        return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.shop_broke)
    end

    if not take(src, bag.price) then
        return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.shop_broke)
    end

    local metadata = variant > 0 and { variant = variant } or nil

    if not ox:AddItem(src, bagKey, 1, metadata) then
        give(src, bag.price) -- refund rather than eat their money
        return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.shop_full)
    end

    if Logs then Logs.simple('buy', 'Backpack purchased', src, bagKey) end
    TriggerClientEvent('nayzeee-backpack:shopResult', src, true, Strings.shop_bought)
end)

RegisterNetEvent('nayzeee-backpack:sell', function(bagKey)
    local src = source
    if not cfg.canSell then return end

    local bag = Config.Backpacks[bagKey]
    if not bag or not bag.price then return end

    local slots = ox:Search(src, 'slots', bagKey)
    local item = slots and slots[1]

    if not item then
        return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.shop_nothing)
    end

    -- selling a full bag would destroy the contents, so block it
    local bagid = item.metadata and item.metadata.bagid
    if bagid then
        local inv = ox:GetInventory(('backpack_%s'):format(bagid))
        if inv and inv.items and next(inv.items) then
            return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, 'Empty it first.')
        end
    end

    if not ox:RemoveItem(src, bagKey, 1, item.metadata, item.slot) then
        return TriggerClientEvent('nayzeee-backpack:shopResult', src, false, Strings.shop_nothing)
    end

    local refund = math.floor(bag.price * (cfg.sellRate or 0.5))
    give(src, refund)

    Player(src).state:set('nayzeee_backpack', nil, true)

    if Logs then Logs.simple('sell', 'Backpack sold', src, bagKey) end
    TriggerClientEvent('nayzeee-backpack:shopResult', src, true,
        ('%s $%d'):format(Strings.shop_sold, refund))
end)
