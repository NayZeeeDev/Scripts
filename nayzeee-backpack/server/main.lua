local ox = exports.ox_inventory

-----------------------------------------------------------------
-- helpers
-----------------------------------------------------------------

local function debug(...)
    if Config.Debug then print('[nayzeee-backpack]', ...) end
end

local function isBackpack(name)
    return Config.Backpacks[name] ~= nil
end

--- Does this player actually hold this backpack? Never trust the client.
local function playerHasBag(src, bagKey)
    if not bagKey then return false end
    local count = ox:Search(src, 'count', bagKey)
    return type(count) == 'number' and count > 0
end

--- Every bag carries a unique id in metadata so its stash follows the item.
local function bagStashId(bagId)
    return ('backpack_%s'):format(bagId)
end

-----------------------------------------------------------------
-- give every backpack a unique id and its own stash
-----------------------------------------------------------------

for name in pairs(Config.Backpacks) do
    ox:registerHook('createItem', function(payload)
        local meta = payload.metadata or {}

        if not meta.bagid then
            meta.bagid = ('%s%s'):format(
                os.time(),
                math.random(100000, 999999)
            )
        end

        local storage = Config.GetStorage(payload.item and payload.item.name)
        meta.description = meta.description or
            ('%d slots · %.1fkg'):format(storage.slots, storage.weight / 1000)
        return meta
    end, {
        itemFilter = { [name] = true }
    })
end

-----------------------------------------------------------------
-- one bag only
-----------------------------------------------------------------

if Config.OneBagOnly then
    ox:registerHook('swapItems', function(payload)
        local moved = payload.fromSlot
        if not moved or not isBackpack(moved.name) then return true end

        -- moving into another player's inventory or a stash is fine
        if payload.toInventory ~= payload.fromInventory and
           type(payload.toInventory) == 'number' then

            local existing = ox:Search(payload.toInventory, 'count', moved.name)
            if existing and existing > 0 then
                TriggerClientEvent('nayzeee-backpack:notify', payload.toInventory, Strings.one_bag_only, 'error')
                return false
            end
        end

        return true
    end, {
        print = Config.Debug
    })
end

-----------------------------------------------------------------
-- no bag inside a bag
-----------------------------------------------------------------

if Config.BlockBagInBag then
    ox:registerHook('swapItems', function(payload)
        local moved = payload.fromSlot
        if not moved or not isBackpack(moved.name) then return true end

        local dest = payload.toInventory
        if type(dest) == 'string' and dest:find('^backpack_') then
            return false
        end

        return true
    end, {
        print = Config.Debug
    })
end

-----------------------------------------------------------------
-- opening a backpack
-----------------------------------------------------------------

--- Called by ox_inventory when the item is used.
local function openBackpack(source, item)
    local meta = item and item.metadata
    if not meta or not meta.bagid then
        TriggerClientEvent('nayzeee-backpack:notify', source, Strings.cannot_open, 'error')
        return
    end

    local stashId = bagStashId(meta.bagid)
    local bag = Config.Backpacks[item.name]
    local storage = Config.GetStorage(item.name)

    ox:RegisterStash(
        stashId,
        bag and bag.label or 'Backpack',
        storage.slots,
        storage.weight,
        false -- not owner-locked; the stash belongs to the item, not the player
    )

    TriggerClientEvent('nayzeee-backpack:open', source, stashId)
    if Logs then Logs.simple('open', 'Backpack opened', source, item.name) end
    debug('opened', stashId, 'for', source)
end

for name in pairs(Config.Backpacks) do
    exports('use' .. name, function(event, item, inventory, slot, data)
        if event ~= 'usingItem' then return end
        TriggerClientEvent('nayzeee-backpack:menu', inventory.id, item.name)
        return false -- don't consume the item
    end)
end

-----------------------------------------------------------------
-- prop state
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:sync', function(bagKey, variant)
    local src = source

    if bagKey and not isBackpack(bagKey) then
        debug('rejected unknown bag from', src, bagKey)
        return
    end

    if bagKey and not playerHasBag(src, bagKey) then
        debug('rejected sync from', src, '- does not hold', bagKey)
        Player(src).state:set('nayzeee_backpack', nil, true)
        return
    end

    -- a job bag can't be worn off the job, however it was obtained
    if bagKey and ServerCanUseBag and not ServerCanUseBag(src, bagKey) then
        Player(src).state:set('nayzeee_backpack', nil, true)
        TriggerClientEvent('nayzeee-backpack:notify', src, Strings.job_only, 'error')
        return
    end

    if bagKey then
        Player(src).state:set('nayzeee_backpack', {
            bag = bagKey,
            variant = variant
        }, true)
    else
        Player(src).state:set('nayzeee_backpack', nil, true)
    end

    debug('state ->', src, bagKey or 'none')
end)

AddEventHandler('playerDropped', function()
    local src = source
    TriggerClientEvent('nayzeee-backpack:clear', -1, src)
end)

-----------------------------------------------------------------
-- open the bag you're wearing
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:openWorn', function()
    local src = source
    local state = Player(src).state.nayzeee_backpack
    local bagKey = state and state.bag

    if not bagKey or not Config.Backpacks[bagKey] then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.no_bag, 'error')
    end

    local slots = ox:Search(src, 'slots', bagKey)
    local item = slots and slots[1]

    if not item then
        Player(src).state:set('nayzeee_backpack', nil, true)
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.no_bag, 'error')
    end

    openBackpack(src, item)
end)

-----------------------------------------------------------------
-- take off / put on
--
-- A stowed bag stays in the inventory and stays usable, it just
-- isn't on the player's back.
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:setStowed', function(stowed)
    local src = source
    local state = Player(src).state.nayzeee_backpack

    if not state or not state.bag then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.no_bag, 'error')
    end

    if not playerHasBag(src, state.bag) then
        Player(src).state:set('nayzeee_backpack', nil, true)
        return
    end

    Player(src).state:set('nayzeee_backpack', {
        bag = state.bag,
        variant = state.variant,
        stowed = stowed and true or nil,
    }, true)

    if Logs then
        Logs.simple('stow', stowed and 'Backpack taken off' or 'Backpack put on', src, state.bag)
    end

    TriggerClientEvent('nayzeee-backpack:notify', src,
        stowed and Strings.stowed or Strings.worn, 'inform')
end)
