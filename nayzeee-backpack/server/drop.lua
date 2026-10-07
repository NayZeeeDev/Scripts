-----------------------------------------------------------------
-- Physical drop
--
-- Uses ox_inventory's CustomDrop with the bag's own model, so what
-- hits the ground is the actual backpack, lootable by anyone.
-----------------------------------------------------------------

local ox = exports.ox_inventory

Drop = {}

local active = {}  -- [dropId] = { at = time }

--- Move a backpack out of a player's inventory and onto the floor.
--- Returns the drop id, or nil if nothing was dropped.
--- `skipLog` avoids double-logging when robbery already logged the event.
function Drop.bag(src, bagKey, coords, skipLog)
    if not Config.Drop.enabled then return nil end

    local bag = Config.Backpacks[bagKey]
    if not bag then return nil end

    local slots = ox:Search(src, 'slots', bagKey)
    local item = slots and slots[1]
    if not item then return nil end

    local metadata = item.metadata or {}

    -- snapshot before anything is wiped or moved
    if Logs and not skipLog then
        Logs.drop(src, bagKey, metadata, coords or GetEntityCoords(GetPlayerPed(src)), 'death')
    end

    -- wipe the stash first if the server doesn't want contents surviving
    if not Config.Drop.keepContents and metadata.bagid then
        local stashId = ('backpack_%s'):format(metadata.bagid)
        ox:ClearInventory(stashId)
    end

    if not ox:RemoveItem(src, bagKey, 1, metadata, item.slot) then
        return nil
    end

    coords = coords or GetEntityCoords(GetPlayerPed(src))

    local storage = Config.GetStorage(bagKey)
    local dropId = ox:CustomDrop(
        bag.label or 'Backpack',
        { { bagKey, 1, metadata } },
        coords,
        1,                      -- the drop holds the bag item itself
        storage.weight,
        nil,
        joaat(bag.model)        -- the real model on the ground
    )

    if dropId then
        active[dropId] = { at = os.time() }
    end

    Player(src).state:set('nayzeee_backpack', nil, true)
    return dropId
end

-- clear drops nobody picked up
if Config.Drop.enabled and (Config.Drop.despawn or 0) > 0 then
    CreateThread(function()
        while true do
            Wait(60000)
            local now = os.time()
            for id, info in pairs(active) do
                if now - info.at > Config.Drop.despawn then
                    -- ox removes the drop itself once empty; this just stops
                    -- the table growing forever
                    active[id] = nil
                end
            end
        end
    end)
end

-----------------------------------------------------------------
-- death
-----------------------------------------------------------------

if Config.Drop.enabled and Config.Drop.onDeath then
    local function handleDeath(src)
        local state = Player(src).state.nayzeee_backpack
        if not state or not state.bag then return end

        if Drop.bag(src, state.bag) then
            TriggerClientEvent('nayzeee-backpack:notify', src, Strings.bag_dropped, 'error')
        end
    end

    AddEventHandler('esx:onPlayerDeath', function()
        handleDeath(source)
    end)

    -- ox_inventory fires this too, so it works without ESX death events
    AddEventHandler('ox_inventory:playerDeath', function(playerId)
        handleDeath(playerId)
    end)
end
