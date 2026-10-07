-----------------------------------------------------------------
-- Admin helpers
--
-- /bagitems   prints an ox_inventory items.lua entry for every bag
--             that isn't registered yet, ready to paste.
-- /givebag    /givebag [id] [bag] [variant]
-----------------------------------------------------------------

local ox = exports.ox_inventory

local function entryFor(key)
    local bag = Config.Backpacks[key]
    local storage = Bags.storage(key)
    return ([[
['%s'] = {
    label = '%s',
    weight = %d,
    stack = false,
    close = true,
    description = '%d slots · %.1fkg',
    client = { image = '%s.png' },
    server = { export = '%s.use%s' },
},]]):format(key, (Bags.label(key):gsub("'", "\\'")), bag.category == 'pocketbook' and 500 or 1000,
        storage.slots, storage.weight / 1000, key, GetCurrentResourceName(), key)
end

lib.addCommand('bagitems', {
    help = 'Print ox_inventory item entries for bags that are missing (admin)',
    restricted = false,
}, function(src)
    if src ~= 0 and not Framework.isAdmin(src) then return end
    local missing, out = 0, {}
    for _, key in ipairs(Bags.keys()) do
        if not ox:Items(key) then
            missing = missing + 1
            out[#out + 1] = entryFor(key)
        end
    end
    if missing == 0 then
        print('^2[nayzeee-backpack] every bag already has an ox_inventory item.^0')
    else
        print(('^3[nayzeee-backpack] %d bag(s) have no item yet. Paste into ox_inventory/data/items.lua:^0\n'):format(missing))
        print(table.concat(out, '\n'))
    end
    if src ~= 0 then
        TriggerClientEvent('nayzeee-backpack:notify', src,
            missing == 0 and 'All bags have items.' or ('%d missing, printed to the server console.'):format(missing),
            missing == 0 and 'success' or 'inform')
    end
end)

lib.addCommand('givebag', {
    help = 'Give a backpack (admin)',
    params = {
        { name = 'target', type = 'playerId', help = 'Player id' },
        { name = 'bag', type = 'string', help = 'Bag key from Config.Backpacks' },
        { name = 'variant', type = 'number', help = 'Variant id', optional = true },
    },
    restricted = false,
}, function(src, args)
    if src ~= 0 and not Framework.isAdmin(src) then return end
    if not Config.Backpacks[args.bag] then
        if src ~= 0 then TriggerClientEvent('nayzeee-backpack:notify', src, 'Unknown bag.', 'error') end
        return
    end
    local ok
    if Bags.isJobBag(args.bag) then
        ok = IssueJobBag(args.target, args.bag, args.variant)
    else
        ok = exports[GetCurrentResourceName()]:GiveBag(args.target, args.bag, args.variant)
    end
    if src ~= 0 then
        TriggerClientEvent('nayzeee-backpack:notify', src, ok and 'Bag given.' or 'Could not give the bag.', ok and 'success' or 'error')
    end
end)

-- warn once on start about bags with no item
CreateThread(function()
    Wait(3000)
    local missing = {}
    for _, key in ipairs(Bags.keys()) do
        if not ox:Items(key) then missing[#missing + 1] = key end
    end
    if #missing > 0 then
        print(('^3[nayzeee-backpack] no ox_inventory item for: %s — run /bagitems for paste-ready entries^0'):format(table.concat(missing, ', ')))
    end
end)
