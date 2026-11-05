-----------------------------------------------------------------
-- Physical drop
--
-- Uses ox_inventory's CustomDrop with the bag's own model, so what
-- hits the ground is the actual backpack, lootable by anyone.
--
-- ox_inventory forgets its drops on a restart, which would take the bag
-- item (and so the way into its contents) with it. So every bag drop is
-- also written to nayzeee_dropped_bags and put back on the ground when the
-- server starts, until somebody picks the bag up.
-----------------------------------------------------------------

local ox = exports.ox_inventory

Drop = {}

local active = {}  -- [dropId] = { at = time, bag = bagKey }
local hasDb = GetResourceState('oxmysql') == 'started'

--- Remember a bag lying in an ox drop so it survives a restart.
function Drop.track(dropId, bagKey, metadata, coords)
    if not dropId then return end
    active[tostring(dropId)] = { at = os.time(), bag = bagKey }
    if not hasDb then return end
    MySQL.insert('INSERT INTO nayzeee_dropped_bags (drop_id, bag, metadata, x, y, z) VALUES (?, ?, ?, ?, ?, ?) '..
                 'ON DUPLICATE KEY UPDATE bag = VALUES(bag), metadata = VALUES(metadata)',
        { tostring(dropId), bagKey, json.encode(metadata or {}), coords.x, coords.y, coords.z })
end

local function untrack(dropId)
    active[tostring(dropId)] = nil
    if hasDb then MySQL.query('DELETE FROM nayzeee_dropped_bags WHERE drop_id = ?', { tostring(dropId) }) end
end

local function dropModel(bagKey, metadata)
    return joaat(Bags.resolve(bagKey, metadata.variant, true, BagHasCash(bagKey, metadata.bagid)))
end

--- Is the bag still lying in this drop? (false once ox has removed the drop)
local function stillThere(dropId, bagKey)
    local inv = ox:GetInventory(dropId, false)
    for _, it in pairs(inv and inv.items or {}) do
        if Bags.rawKeyOf(it) == bagKey then return true end -- registered or not (clothing bags register late)
    end
    return false
end

-- taken out of the drop (dragged out, or swapped for something): forget it
ox:registerHook('swapItems', function(payload)
    for _, inv in ipairs({ payload.fromInventory, payload.toInventory }) do
        local id = inv and tostring(inv)
        local w = id and active[id]
        if w then
            SetTimeout(500, function()
                if active[id] and not stillThere(id, w.bag) then untrack(id) end
            end)
        end
    end
    return true
end)

-- safety net for anything the hook missed: every minute, forget drops the
-- bag is no longer in (picked up, or ox cleaned the drop away)
CreateThread(function()
    while true do
        Wait(60000)
        for id, w in pairs(active) do
            if not stillThere(id, w.bag) then untrack(id) end
        end
    end
end)

local waiting = {} -- dropped clothing bags that aren't registered yet

--- Put one saved drop back on the ground. Returns true when it's back.
local function putBack(row)
    local key = Bags.fixKey(row.bag)
    if not Config.Backpacks[key] then return false end
    local metadata = json.decode(row.metadata or '{}') or {}
    local coords = vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0)
    local dropId = ox:CustomDrop(Bags.label(key), { { Bags.itemName(key), 1, Bags.stamp(key, metadata) } }, coords, 1,
        Bags.storage(key).weight, nil, dropModel(key, metadata))
    if not dropId then
        Console.log('error', 'could not put dropped %s (bag id %s) back on the ground', key, tostring(metadata.bagid))
        return false
    end
    -- only forget the old row once the bag is really back (never lose it)
    MySQL.query.await('DELETE FROM nayzeee_dropped_bags WHERE drop_id = ?', { row.drop_id })
    Drop.track(dropId, key, metadata, coords)
    return true
end

-- clothing bags are registered (again): put back the drops that were waiting
AddEventHandler('nayzeee-backpack:clothingBagsReady', function()
    CreateThread(function()
        local still, back = {}, 0
        for _, row in ipairs(waiting) do
            if putBack(row) then back = back + 1
            elseif not Config.Backpacks[Bags.fixKey(row.bag)] then still[#still + 1] = row end
        end
        waiting = still
        if back > 0 then Console.log('info', 'put %d dropped clothing bag(s) back on the ground', back) end
    end)
end)

-- put back what was lying on the ground when the server went down
Console.wait('drops')
CreateThread(function()
    if not hasDb then
        Console.check('drops', 'warn', 'Dropped bags', 'oxmysql is not running: they will not survive a restart')
        return Console.done('drops')
    end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `nayzeee_dropped_bags` (
        `drop_id`  VARCHAR(64) NOT NULL,
        `bag`      VARCHAR(64) NOT NULL,
        `metadata` LONGTEXT DEFAULT NULL,
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        PRIMARY KEY (`drop_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    while GetResourceState('ox_inventory') ~= 'started' do Wait(500) end
    Wait(3000)

    local rows = MySQL.query.await('SELECT * FROM nayzeee_dropped_bags') or {}
    local restored = 0
    for _, row in ipairs(rows) do
        local key = Bags.fixKey(row.bag)
        if ox:GetInventory(row.drop_id, false) then
            -- only this resource restarted: ox still has the drop
            active[tostring(row.drop_id)] = { at = os.time(), bag = key }
        elseif Config.Backpacks[key] then
            if putBack(row) then restored = restored + 1 end
        elseif type(key) == 'string' and key:find('^nzb_') then
            waiting[#waiting + 1] = row -- a clothing bag: back once it's registered
        end
    end
    Console.check('drops', restored > 0 and 'info' or 'ok', 'Dropped bags',
        restored > 0 and ('%d put back on the ground'):format(restored) or 'none waiting')
    Console.done('drops')
end)

--- Move a backpack out of a player's inventory and onto the floor.
--- Returns the drop id, or nil if nothing was dropped.
--- `skipLog` avoids double-logging when robbery already logged the event.
function Drop.bag(src, bagKey, coords, skipLog)
    if not Config.Drop.enabled then return nil end

    local bag = Config.Backpacks[bagKey]
    if not bag then return nil end

    local item = FindBagItem(src)
    if not item or Bags.keyOf(item) ~= bagKey then return nil end

    local metadata = item.metadata or {}
    metadata.stowed = nil

    -- snapshot before anything is wiped or moved
    if Logs and not skipLog then
        Logs.drop(src, bagKey, metadata, coords or GetEntityCoords(GetPlayerPed(src)), 'death')
    end

    if not ox:RemoveItem(src, item.name, 1, metadata, item.slot) then
        return nil
    end

    -- only wipe once the bag has really left them, never before
    if not Config.Drop.keepContents and metadata.bagid then
        ox:ClearInventory(PrepareStash(bagKey, metadata.bagid))
    end

    coords = coords or GetEntityCoords(GetPlayerPed(src))

    local storage = Bags.storage(bagKey)
    local dropId = ox:CustomDrop(
        Bags.label(bagKey),
        { { item.name, 1, metadata } },
        coords,
        1,                      -- the drop holds the bag item itself
        storage.weight,
        nil,
        dropModel(bagKey, metadata) -- the real model on the ground
    )

    if dropId then
        Drop.track(dropId, bagKey, metadata, coords)
        if Sounds then Sounds.play('drop', coords) end
    end

    RefreshBagState(src)
    return dropId
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
