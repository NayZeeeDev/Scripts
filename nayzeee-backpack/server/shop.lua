-----------------------------------------------------------------
-- Bag store (server)
--
-- Price, funds and inventory space are all checked here. The UI
-- only ever asks.
-----------------------------------------------------------------

if not Config.Shop or not Config.Shop.enabled then return end

local ox = exports.ox_inventory
local cfg = Config.Shop
local account = cfg.currency == 'bank' and 'bank' or 'cash'

lib.callback.register('nayzeee-backpack:shop:wallet', function(src)
    return Framework.getMoney(src, account)
end)

local function result(src, ok, msg)
    TriggerClientEvent('nayzeee-backpack:shopResult', src, ok, msg, Framework.getMoney(src, account))
end

local imageCache = {}

--- ox_inventory image for a variant, if the icon studio made one.
local function variantImage(bagKey, variant)
    if not (Config.IconCapture and Config.IconCapture.variantIcons) then return nil end
    local list = Bags.variants(bagKey)
    if not variant or #list == 0 or variant == list[1].id then return nil end

    local name = ('%s_%s'):format(bagKey, variant)
    if imageCache[name] == nil then
        imageCache[name] = LoadResourceFile('ox_inventory', ('web/images/%s.png'):format(name)) ~= nil
    end
    return imageCache[name] and name or nil
end

AddEventHandler('nayzeee-backpack:iconWritten', function(name) imageCache[name] = nil end)

-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:buy', function(bagKey, variant)
    local src = source
    local price = Bags.price(bagKey)

    -- a bag with no price isn't for sale, whatever the client claims
    if not Config.Backpacks[bagKey] or not price then
        return result(src, false, Strings.shop_broke)
    end

    variant = tonumber(variant)
    if variant and not Bags.variant(bagKey, variant) then variant = nil end

    -- job bags: the client already hides them, but never trust that
    if Bags.isJobBag(bagKey) then
        local job = Framework.getJob(src)
        if not Bags.jobAllows(bagKey, job) then return result(src, false, Strings.shop_job) end
    end

    if Config.OneBagOnly and FindBagItem(src) then
        return result(src, false, Strings.one_bag_only)
    end

    if not ox:CanCarryItem(src, bagKey, 1) then
        return result(src, false, Strings.shop_full)
    end

    -- free job kit goes through the issue path, so it's the same bag every time
    if Bags.isJobBag(bagKey) and price == 0 then
        if not IssueJobBag(src, bagKey, variant) then return result(src, false, Strings.shop_full) end
        if Logs then Logs.simple('buy', 'Job bag collected', src, bagKey) end
        return result(src, true, Strings.job_issued)
    end

    if not Framework.removeMoney(src, account, price) then
        return result(src, false, Strings.shop_broke)
    end

    local metadata = {}
    if variant then metadata.variant = variant end
    metadata.image = variantImage(bagKey, variant)

    if not ox:AddItem(src, bagKey, 1, metadata) then
        Framework.addMoney(src, account, price) -- refund rather than eat their money
        return result(src, false, Strings.shop_full)
    end

    if Logs then Logs.simple('buy', 'Backpack purchased', src, bagKey) end
    result(src, true, Strings.shop_bought)
end)

RegisterNetEvent('nayzeee-backpack:sell', function(bagKey)
    local src = source
    if not cfg.canSell then return end

    local price = Bags.price(bagKey)
    if not Config.Backpacks[bagKey] or not price or price <= 0 then return end
    if Bags.isJobBag(bagKey) then return result(src, false, Strings.shop_job) end

    local item = FindBagItem(src)
    if not item or item.name ~= bagKey then
        return result(src, false, Strings.shop_nothing)
    end

    -- selling a full bag would destroy the contents, so block it
    local bagid = item.metadata and item.metadata.bagid
    if bagid then
        local inv = ox:GetInventory(PrepareStash(bagKey, bagid), false)
        if inv and inv.items and next(inv.items) then
            return result(src, false, Strings.shop_empty)
        end
    end

    if not ox:RemoveItem(src, bagKey, 1, item.metadata, item.slot) then
        return result(src, false, Strings.shop_nothing)
    end

    local refund = math.floor(price * (cfg.sellRate or 0.5))
    Framework.addMoney(src, account, refund)
    RefreshBagState(src)

    if Logs then Logs.simple('sell', 'Backpack sold', src, bagKey) end
    result(src, true, ('%s $%d'):format(Strings.shop_sold, refund))
end)
