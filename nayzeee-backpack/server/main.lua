-----------------------------------------------------------------
-- Worn bags (server)
--
-- The statebag on each player is the single source of truth every
-- client renders from. It's always rebuilt from the real inventory
-- item, and "taken off" / chosen pose live in the ITEM metadata, so
-- a stowed bag stays stowed through relogs and server restarts.
-----------------------------------------------------------------

local ox = exports.ox_inventory

local function stashId(bagid) return ('backpack_%s'):format(bagid) end

--- First backpack item in a player's inventory, or nil.
function FindBagItem(src)
    local items = ox:GetInventoryItems(src)
    if not items then return nil end
    local best
    for _, item in pairs(items) do
        if item and item.name and Config.Backpacks[item.name] then
            if not best or (item.slot or 99) < (best.slot or 99) then best = item end
        end
    end
    return best
end

--- Can this player use a bag with a `job` restriction right now?
function ServerCanUseBag(src, bagKey)
    if not Config.Backpacks[bagKey] then return false end
    if Bags.isJobBag(bagKey) then
        local job = Framework.getJob(src)
        if not Bags.jobAllows(bagKey, job) then return false, Strings.job_only end
        if Config.Jobs and Config.Jobs.requireDuty then
            local duty = Integrations.first('isOnDuty', src, job and job.name)
            if duty == nil then duty = job and job.onDuty end
            if not duty then return false, Strings.job_duty end
        end
    end
    if not Integrations.allow('canWear', src, bagKey) then return false end
    return true
end

local denied = {} -- [src] = bagKey we already told them about

--- Rebuild a player's statebag from their inventory.
function RefreshBagState(src)
    local item = FindBagItem(src)
    local current = Player(src).state.nayzeee_backpack

    if not item then
        if current then Player(src).state:set('nayzeee_backpack', nil, true) end
        denied[src] = nil
        return nil
    end

    local ok, why = ServerCanUseBag(src, item.name)
    if not ok then
        if current then Player(src).state:set('nayzeee_backpack', nil, true) end
        if denied[src] ~= item.name then
            denied[src] = item.name
            TriggerClientEvent('nayzeee-backpack:notify', src, why or Strings.job_only, 'error')
        end
        return nil
    end
    denied[src] = nil

    local m = item.metadata or {}
    local variant = tonumber(m.variant)
    if variant and not Bags.variant(item.name, variant) then variant = nil end

    local state = {
        bag = item.name,
        variant = variant or Bags.defaultVariant(item.name),
        stowed = m.stowed and true or nil,
        pose = m.pose,
        slot = item.slot,
        locked = m.lock and true or nil,
        tag = m.tag,
    }

    -- only write when something changed; statebag writes go to everyone
    if not current or current.bag ~= state.bag or current.variant ~= state.variant
       or current.stowed ~= state.stowed or current.pose ~= state.pose or current.slot ~= state.slot
       or current.locked ~= state.locked or TagSig(current.tag) ~= TagSig(state.tag) then
        Player(src).state:set('nayzeee_backpack', state, true)
        if Logs and (not current or current.bag ~= state.bag) then
            Logs.simple('equip', 'Backpack equipped', src, state.bag)
        end
    end
    return state
end

-----------------------------------------------------------------
-- give every backpack a unique id and its own stash
-----------------------------------------------------------------

local itemFilter = {}
for name in pairs(Config.Backpacks) do itemFilter[name] = true end

--- Item tooltip: storage, plus whether it's padlocked.
function BagDescription(bagKey, meta)
    local storage = Bags.storage(bagKey)
    local text = ('%d slots · %.1fkg'):format(storage.slots, storage.weight / 1000)
    if meta and meta.lock then text = text .. ' · Padlocked' end
    return text
end

ox:registerHook('createItem', function(payload)
    local meta = payload.metadata or {}
    local name = payload.item and payload.item.name

    if not meta.bagid then
        meta.bagid = ('%s%s'):format(os.time(), math.random(100000, 999999))
    end
    meta.description = meta.description or BagDescription(name, meta)
    return meta
end, { itemFilter = itemFilter })

-----------------------------------------------------------------
-- one bag only / no bag inside a bag
-----------------------------------------------------------------

if Config.OneBagOnly then
    ox:registerHook('swapItems', function(payload)
        local moved = payload.fromSlot
        if not moved or not Config.Backpacks[moved.name] then return true end

        local dest = payload.toInventory
        if dest ~= payload.fromInventory and type(dest) == 'number' then
            local item = FindBagItem(dest)
            if item then
                TriggerClientEvent('nayzeee-backpack:notify', payload.source, Strings.one_bag_only, 'error')
                return false
            end
        end
        return true
    end, { itemFilter = itemFilter, print = Config.Debug })
end

if Config.BlockBagInBag then
    ox:registerHook('swapItems', function(payload)
        local moved = payload.fromSlot
        if not moved or not Config.Backpacks[moved.name] then return true end

        local dest = payload.toInventory
        if type(dest) == 'string' and dest:find('^backpack_') then
            TriggerClientEvent('nayzeee-backpack:notify', payload.source, Strings.bag_in_bag, 'error')
            return false
        end
        return true
    end, { itemFilter = itemFilter, print = Config.Debug })
end

-----------------------------------------------------------------
-- opening a backpack
-----------------------------------------------------------------

--- Register (or resize) a bag's stash so studio storage edits apply
--- to bags that already exist, not just new ones.
function PrepareStash(bagKey, bagid)
    local id = stashId(bagid)
    local storage = Bags.storage(bagKey)
    ox:RegisterStash(id, Bags.label(bagKey), storage.slots, storage.weight, false)

    local inv = ox:GetInventory(id, false)
    if inv then
        if inv.slots ~= storage.slots then pcall(function() ox:SetSlotCount(id, storage.slots) end) end
        if inv.maxWeight ~= storage.weight then pcall(function() ox:SetMaxWeight(id, storage.weight) end) end
    end
    return id
end

-----------------------------------------------------------------
-- Bag stashes only open when the server opened them. Without this,
-- anyone who once saw a bag's id could open it from anywhere with
-- ox_inventory's client export and walk straight past padlocks.
-----------------------------------------------------------------

local allowed = {} -- [src] = { [stashId] = expires (game timer) }

--- Let `src` open stash `id` once, within the next 15 seconds.
function AllowStash(src, id)
    allowed[src] = allowed[src] or {}
    allowed[src][id] = GetGameTimer() + 15000
end

ox:registerHook('openInventory', function(payload)
    local id = payload.inventoryId
    if type(id) ~= 'string' or not id:find('^backpack_') then return true end
    local mine = allowed[payload.source]
    local expires = mine and mine[id]
    if expires and GetGameTimer() <= expires then
        mine[id] = nil
        return true
    end
    return false
end, { inventoryFilter = { '^backpack_' } })

--- Does a stash hold any of these items?
local function hasAny(stashId, names)
    local inv = ox:GetInventory(stashId, false)
    if not inv or not inv.items then return false end
    local want = {}
    for _, n in ipairs(names) do want[n] = true end
    for _, it in pairs(inv.items) do
        if it and want[it.name] and (it.count or 0) > 0 then return true end
    end
    return false
end

local watching = {} -- [stashId] = { bag, src } while a bag with a cash model / grab anim is open

local openUnlocked -- forward

--- Open a bag in your own inventory (asks for the code if it's padlocked).
local function openBackpack(src, item)
    local meta = item and item.metadata
    if not meta or not meta.bagid then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.cannot_open, 'error')
    end
    if Player(src).state.nb_open then return end
    if HandoffBusy and HandoffBusy(src) then return end

    local slot, bagid = item.slot, meta.bagid
    Locks.gate(src, meta, {
        bag = item.name,
        open = function()
            local now = ox:GetSlot(src, slot)
            if now and now.metadata and now.metadata.bagid == bagid then openUnlocked(src, now) end
        end,
        getMeta = function()
            local now = ox:GetSlot(src, slot)
            return now and now.metadata
        end,
        save = function(m) ox:SetMetadata(src, slot, m) RefreshBagState(src) end,
    })
end

openUnlocked = function(src, item)
    local meta = item.metadata

    local id = PrepareStash(item.name, meta.bagid)
    local info = Bags.openInfo(item.name)
    if info.cashModel or info.grabAnim then
        info.cash = hasAny(id, info.cashItems)
        watching[id] = { bag = item.name, src = src }
    end

    -- keep the item tooltip honest after a storage edit
    local desc = BagDescription(item.name, meta)
    if meta.description ~= desc then
        meta.description = desc
        ox:SetMetadata(src, item.slot, meta)
    end

    AllowStash(src, id)
    TriggerClientEvent('nayzeee-backpack:open', src, id, info)
    -- kneeling down takes a moment before the zip
    if Sounds then Sounds.play('zip_open', src, info.style == 'kneel' and 900 or 250) end
    if Logs then Logs.simple('open', 'Backpack opened', src, item.name) end
end

-- cash going in or out of an open duffel: swap its model, play the grab
ox:registerHook('swapItems', function(payload)
    local from, to = payload.fromInventory, payload.toInventory
    local stash = (type(from) == 'string' and watching[from] and from)
               or (type(to) == 'string' and watching[to] and to)
    if not stash then return true end

    local w = watching[stash]
    local moved = payload.fromSlot and payload.fromSlot.name
    local info = Bags.openInfo(w.bag)
    local isCash = false
    for _, n in ipairs(info.cashItems) do if n == moved then isCash = true end end
    if not isCash then return true end

    local withdrew = from == stash and to ~= stash
    local src = payload.source
    SetTimeout(150, function()
        if GetPlayerPing(src) == 0 then return end
        TriggerClientEvent('nayzeee-backpack:openCash', src, hasAny(stash, info.cashItems), withdrew)
    end)
    return true
end, { inventoryFilter = { '^backpack_' } })

AddEventHandler('ox_inventory:closedInventory', function(playerId, inventoryId)
    if Sounds and type(inventoryId) == 'string' and inventoryId:find('^backpack_') then
        Sounds.play('zip_close', playerId)
    end
    local w = inventoryId and watching[inventoryId]
    if w and w.src == playerId then watching[inventoryId] = nil end
end)

for name in pairs(Config.Backpacks) do
    exports('use' .. name, function(event, item, inventory)
        if event ~= 'usingItem' then return end
        TriggerClientEvent('nayzeee-backpack:menu', inventory.id, item.name)
        return false -- don't consume the item
    end)
end

-----------------------------------------------------------------
-- client requests
-----------------------------------------------------------------

RegisterNetEvent('nayzeee-backpack:sync', function()
    RefreshBagState(source)
end)

RegisterNetEvent('nayzeee-backpack:openWorn', function()
    local src = source
    local item = FindBagItem(src)
    if not item then
        RefreshBagState(src)
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.no_bag, 'error')
    end
    if not ServerCanUseBag(src, item.name) then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.job_only, 'error')
    end
    openBackpack(src, item)
end)

--- Take off / put on. Saved on the item so it survives a relog or restart.
RegisterNetEvent('nayzeee-backpack:setStowed', function(stowed)
    local src = source
    local item = FindBagItem(src)
    if not item then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.no_bag, 'error')
    end

    local meta = item.metadata or {}
    meta.stowed = stowed and true or nil
    ox:SetMetadata(src, item.slot, meta)
    RefreshBagState(src)
    if Sounds then Sounds.play('strap', src, 500) end

    if Logs then
        Logs.simple('stow', stowed and 'Backpack taken off' or 'Backpack put on', src, item.name)
    end
    TriggerClientEvent('nayzeee-backpack:notify', src, stowed and Strings.stowed or Strings.worn, 'inform')
end)

RegisterNetEvent('nayzeee-backpack:setPose', function(poseKey)
    local src = source
    if not Bags.pose(poseKey) then return end
    local item = FindBagItem(src)
    if not item or not Bags.carryStyle(item.name) then return end

    local meta = item.metadata or {}
    meta.pose = poseKey
    ox:SetMetadata(src, item.slot, meta)
    RefreshBagState(src)
    TriggerClientEvent('nayzeee-backpack:notify', src, Strings.pose_set, 'success')
end)

-----------------------------------------------------------------
-- lifecycle
-----------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    denied[src] = nil
    allowed[src] = nil
    for id, w in pairs(watching) do if w.src == src then watching[id] = nil end end
    TriggerClientEvent('nayzeee-backpack:clear', -1, src)
end)

Framework.onPlayerLoaded(function(src)
    SetTimeout(1500, function() RefreshBagState(src) end)
end)

-- resource restart: everyone online gets their state back
CreateThread(function()
    local props = Config.PropsResource
    if props and GetResourceState(props) ~= 'started' then
        print(('^3[nayzeee-backpack] %s is not running: bags will be invisible. ' ..
            'ensure it BEFORE nayzeee-backpack (or set Config.PropsResource = false).^0'):format(props))
    end

    Wait(2000)
    for _, id in ipairs(GetPlayers()) do
        RefreshBagState(tonumber(id))
    end
end)

-----------------------------------------------------------------
-- exports for other resources
-----------------------------------------------------------------

exports('GetWornBag', function(src)
    local st = Player(src).state.nayzeee_backpack
    return st and st.bag or nil, st
end)

--- Stash id of the worn bag. The player may open it once in the next
--- 15s (other resources usually open it right after asking).
exports('GetBagStash', function(src)
    local item = FindBagItem(src)
    if not item or not item.metadata or not item.metadata.bagid then return nil end
    local id = PrepareStash(item.name, item.metadata.bagid)
    AllowStash(src, id)
    return id
end)

exports('OpenBag', function(src)
    local item = FindBagItem(src)
    if item then openBackpack(src, item) end
end)

exports('GiveBag', function(src, bagKey, variant)
    if not Config.Backpacks[bagKey] then return false end
    local meta = {}
    if variant and Bags.variant(bagKey, variant) then meta.variant = tonumber(variant) end
    return ox:AddItem(src, bagKey, 1, meta) and true or false
end)
