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

    local item = FindBagItem(src)
    if not item or item.name ~= bagKey then return nil end

    local metadata = item.metadata or {}
    metadata.stowed = nil

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

    local storage = Bags.storage(bagKey)
    local model = Bags.resolve(bagKey, metadata.variant)
    local dropId = ox:CustomDrop(
        Bags.label(bagKey),
        { { bagKey, 1, metadata } },
        coords,
        1,                      -- the drop holds the bag item itself
        storage.weight,
        nil,
        joaat(model)            -- the real model on the ground
    )

    if dropId then
        active[dropId] = { at = os.time() }
    end

    RefreshBagState(src)
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
    local lastDeath = {}

    local function handleDeath(src)
        src = tonumber(src)
        if not src then return end

        -- several death events can fire for one death; only act once
        local now = os.time()
        if lastDeath[src] and now - lastDeath[src] < 10 then return end
        lastDeath[src] = now

        local state = Player(src).state.nayzeee_backpack
        if not state or not state.bag then return end
        if Config.Drop.keepJobBags and Bags.isJobBag(state.bag) then return end

        if Drop.bag(src, state.bag) then
            TriggerClientEvent('nayzeee-backpack:notify', src, Strings.bag_dropped, 'error')
        end
    end

    RegisterNetEvent('esx:onPlayerDeath', function()
        handleDeath(source)
    end)

    -- qb-ambulancejob
    RegisterNetEvent('hospital:server:SetDeathStatus', function(isDead)
        if isDead then handleDeath(source) end
    end)

    -- ox_inventory fires this too
    AddEventHandler('ox_inventory:playerDeath', function(playerId)
        handleDeath(playerId)
    end)

    -- Everything else (wasabi_ambulance, qbx_medical, custom scripts):
    -- the player's own client publishes its death state through
    -- integrations.lua, so any medical script that integration knows works.
    AddStateBagChangeHandler('nb_status', nil, function(bagName, _, value)
        if not value or not value.dead then return end
        local src = GetPlayerFromStateBagName(bagName)
        if src and src ~= 0 then handleDeath(src) end
    end)

    AddEventHandler('playerDropped', function() lastDeath[source] = nil end)
end
