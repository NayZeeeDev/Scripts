--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: inventory (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Adapters for ox_inventory, qb-inventory (old and
    new exports), qs-inventory, codem-inventory, origen_inventory,
    tgiann-inventory, core_inventory, ps-inventory, lj-inventory and the
    framework's own inventory (ESX xPlayer / QB Player.Functions).

    API
      Bridge.Inv.HasItem(src, name, count?)            → bool
      Bridge.Inv.Count(src, name, metaMatch?)          → number   metaMatch = { type = 'O-' } (subset match)
      Bridge.Inv.AddItem(src, name, count, metadata?)  → bool
      Bridge.Inv.RemoveItem(src, name, count, metadata?, slot?) → bool
      Bridge.Inv.CanCarry(src, name, count)            → bool
      Bridge.Inv.GetItems(src)   → { { name, label, count, slot, metadata, weight } }
      Bridge.Inv.GetSlot(src, slot) → item | nil
      Bridge.Inv.SetMetadata(src, slot, metadata)      → bool
      Bridge.Inv.Search(src, name) → every stack of that item with its metadata
      Bridge.Inv.RegisterUsable(name, fn(src, item))
      Bridge.Inv.Label(name) → label        Bridge.Inv.Image(name) → 'nui://...png'
      Bridge.Inv.Clear(src, keep?)           keep = { 'item_name', ... }
      Bridge.Inv.OpenStash(src, id, { label, slots, weight, owner? }) → bool   (ox, qb, ps, lj, qs)
      Bridge.Inv.Resource() → adapter name

    METADATA
      Blood bags and X-ray films carry metadata. Inventories without metadata
      (plain ESX) get it emulated: every unit is stored with a serial in the
      resource KVP store per character (Config.Bridge.emulateMetadata). Those
      units are returned with virtual slot numbers from 10001 upwards.

    CALLBACK
      lib.callback 'nza:bridge:inv:counts' (names[]) → { [name] = count }   (client Bridge.Inv cache)

    ADDING YOUR OWN
      Bridge.InventoryAdapters['my_inv'] = { metadata = true, add = fn, remove = fn, items = fn, ... }
      Bridge.Resources.inventory['my_inv'] = 'my_inv' and add it to Bridge.Priority.inventory.
      Every adapter function is optional except add, remove and items.
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Inv = Bridge.Inv or {}

local I = {}
Bridge.InventoryAdapters = I

local VSLOT = 10000   -- virtual slots for emulated metadata start above this

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function normalize(raw, slot)
    if type(raw) ~= 'table' or not raw.name then return nil end
    local meta = raw.metadata or raw.info
    if type(meta) ~= 'table' then meta = {} end
    return {
        name = raw.name,
        label = raw.label or Bridge.ItemLabel(raw.name),
        count = tonumber(raw.count or raw.amount) or 0,
        slot = tonumber(raw.slot or raw.id or slot),
        metadata = meta,
        weight = tonumber(raw.weight) or 0,
    }
end

local function normalizeList(raw)
    local out = {}
    if type(raw) ~= 'table' then return out end
    for slot, item in pairs(raw) do
        local n = normalize(item, tonumber(slot))
        if n and n.count > 0 then out[#out + 1] = n end
    end
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return out
end

local function countFromItems(items, name, meta)
    local total = 0
    for _, item in ipairs(items) do
        if item.name == name and Bridge.MetaMatches(item.metadata, meta) then
            total = total + item.count
        end
    end
    return total
end

local function findSlot(items, name, meta)
    for _, item in ipairs(items) do
        if item.name == name and Bridge.MetaMatches(item.metadata, meta) then return item.slot, item end
    end
    return nil
end

local function keepSet(keep)
    local set = {}
    if type(keep) == 'string' then set[keep] = true end
    if type(keep) == 'table' then
        for k, v in pairs(keep) do
            if type(k) == 'number' then set[v] = true else set[k] = true end
        end
    end
    return set
end

-- Framework usable-item registration (works under ox_inventory too: items
-- without 'consume' are routed to the framework by ox).
local function frameworkUsable(name, cb)
    local fw = Bridge.Framework
    if fw == 'esx' then
        local ESX = Bridge.Core()
        if not ESX then return false end
        ESX.RegisterUsableItem(name, function(source, itemName, data)
            cb(source, type(data) == 'table' and data or { name = itemName })
        end)
        return true
    elseif fw == 'qbcore' then
        local QBCore = Bridge.Core()
        if not QBCore then return false end
        QBCore.Functions.CreateUseableItem(name, function(source, item)
            cb(source, type(item) == 'table' and item or { name = name })
        end)
        return true
    elseif fw == 'qbox' then
        exports.qbx_core:CreateUseableItem(name, function(source, item)
            cb(source, type(item) == 'table' and item or { name = name })
        end)
        return true
    end
    return false
end

local function qbShared(name)
    local QBCore = Bridge.Core()
    local items = QBCore and QBCore.Shared and QBCore.Shared.Items
    return items and items[name] or nil
end

-- Stash flow of qb-inventory 1.x, lj-inventory and qs-inventory: the client asks the
-- inventory to open it (bridge/client/inventory.lua 'nza:bridge:inv:openStash').
local function classicStash(src, id, opts)
    TriggerClientEvent('nza:bridge:inv:openStash', src, id, { label = opts.label, slots = opts.slots, weight = opts.weight })
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ox_inventory
-- ═══════════════════════════════════════════════════════════════════════════

local ox = exports.ox_inventory

I['ox_inventory'] = {
    metadata = true,
    image = { 'ox_inventory', 'web/images/%s.png' },

    count = function(src, name, meta)
        return tonumber(ox:GetItemCount(src, name, meta, false)) or 0
    end,
    add = function(src, name, count, meta)
        return ox:AddItem(src, name, count, meta) == true
    end,
    remove = function(src, name, count, meta, slot)
        return ox:RemoveItem(src, name, count, meta, slot, false, false) == true
    end,
    canCarry = function(src, name, count)
        return ox:CanCarryItem(src, name, count) == true
    end,
    items = function(src)
        return normalizeList(ox:GetInventoryItems(src))
    end,
    slot = function(src, slot)
        return normalize(ox:GetSlot(src, slot), slot)
    end,
    setMeta = function(src, slot, meta)
        ox:SetMetadata(src, slot, meta)
        return true
    end,
    label = function(name)
        local item = ox:Items(name)
        return item and item.label or nil
    end,
    clear = function(src, keep)
        local list = {}
        for name in pairs(keepSet(keep)) do list[#list + 1] = name end
        ox:ClearInventory(src, #list > 0 and list or nil)
        return true
    end,
    usable = function(name, cb)
        -- items with 'consume' (our install file uses consume = 0) reach the hook;
        -- returning false cancels ox's own use so nothing is consumed twice
        local hookId = ox:registerHook('usingItem', function(payload)
            local src, item = payload.source, payload.item
            CreateThread(function() cb(src, item) end)
            return false
        end, { itemFilter = { [name] = true } })
        -- items without 'consume' are handed to the framework by ox
        frameworkUsable(name, cb)
        return hookId ~= nil
    end,
    openStash = function(src, id, opts)
        -- owner = true: one stash per player under the same id (re-registering only updates it)
        ox:RegisterStash(id, opts.label, opts.slots, opts.weight, opts.owner and true or nil)
        return ox:forceOpenInventory(src, 'stash', id) ~= nil
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- QB-style inventories: qb-inventory (v1 = Player.Functions, v2 = exports),
-- ps-inventory, lj-inventory and the QBCore framework fallback
-- ═══════════════════════════════════════════════════════════════════════════

local function qbPlayer(src)
    local p = Bridge.GetPlayer(src)
    return (p and p.PlayerData) and p or nil
end

local function qbVersion2(resource)
    if resource ~= 'qb-inventory' then return false end
    local v = GetResourceMetadata('qb-inventory', 'version', 0) or '0'
    return (tonumber(v:match('^(%d+)')) or 0) >= 2
end

local function makeQbStyle(resource, itemBoxEvent)
    local A = { metadata = true }
    local hasExports = resource ~= nil

    local function itemBox(src, name, kind, count)
        if not itemBoxEvent then return end
        local def = qbShared(name)
        if def then TriggerClientEvent(itemBoxEvent, src, def, kind, count) end
    end

    function A.items(src)
        local p = qbPlayer(src)
        return p and normalizeList(p.PlayerData.items) or {}
    end

    function A.count(src, name, meta)
        if not meta and hasExports and qbVersion2(resource) then
            return tonumber(exports[resource]:GetItemCount(src, name)) or 0
        end
        return countFromItems(A.items(src), name, meta)
    end

    function A.add(src, name, count, meta)
        local ok
        if hasExports then
            ok = exports[resource]:AddItem(src, name, count, false, meta, 'nayzeee-ambulance')
        else
            local p = qbPlayer(src)
            ok = p and p.Functions.AddItem and p.Functions.AddItem(name, count, false, meta)
        end
        if ok then itemBox(src, name, 'add', count) end
        return ok == true
    end

    function A.remove(src, name, count, meta, slot)
        if meta and not slot then
            slot = findSlot(A.items(src), name, meta)
            if not slot then return false end
        end
        local ok
        if hasExports then
            ok = exports[resource]:RemoveItem(src, name, count, slot or false, 'nayzeee-ambulance')
        else
            local p = qbPlayer(src)
            ok = p and p.Functions.RemoveItem and p.Functions.RemoveItem(name, count, slot or false)
        end
        if ok then itemBox(src, name, 'remove', count) end
        return ok == true
    end

    function A.canCarry(src, name, count)
        if hasExports and qbVersion2(resource) then
            return exports[resource]:CanAddItem(src, name, count) == true
        end
        local def = qbShared(name)
        local p = qbPlayer(src)
        if not def or not p then return false end
        local QBCore = Bridge.Core()
        local maxWeight = (QBCore and QBCore.Config and QBCore.Config.Player and QBCore.Config.Player.MaxWeight) or 120000
        local weight = 0
        for _, item in pairs(p.PlayerData.items or {}) do
            weight = weight + (tonumber(item.weight) or 0) * (tonumber(item.amount) or 1)
        end
        return weight + (tonumber(def.weight) or 0) * count <= maxWeight
    end

    function A.slot(src, slot)
        local p = qbPlayer(src)
        local item = p and p.PlayerData.items and p.PlayerData.items[slot]
        return normalize(item, slot)
    end

    function A.setMeta(src, slot, meta)
        local p = qbPlayer(src)
        if not p then return false end
        local items = p.PlayerData.items or {}
        local item = items[slot]
        if not item then return false end
        if hasExports and qbVersion2(resource) then
            return exports[resource]:SetItemData(src, item.name, 'info', meta, slot) ~= false
        end
        item.info = meta
        items[slot] = item
        if hasExports then
            local ok = pcall(function() exports[resource]:SetInventory(src, items) end)
            if ok then return true end
        end
        p.Functions.SetPlayerData('items', items)
        return true
    end

    function A.label(name)
        local def = qbShared(name)
        return def and def.label or nil
    end

    function A.image(name)
        local def = qbShared(name)
        local file = def and def.image or (name .. '.png')
        return resource or 'qb-inventory', 'html/images/' .. file
    end

    function A.clear(src, keep)
        local list = {}
        for name in pairs(keepSet(keep)) do list[#list + 1] = name end
        if hasExports then
            exports[resource]:ClearInventory(src, #list > 0 and list or nil)
            return true
        end
        local p = qbPlayer(src)
        if not p then return false end
        if #list == 0 and p.Functions.ClearInventory then
            p.Functions.ClearInventory()
            return true
        end
        local set = keepSet(keep)
        for _, item in ipairs(A.items(src)) do
            if not set[item.name] then A.remove(src, item.name, item.count, nil, item.slot) end
        end
        return true
    end

    A.usable = frameworkUsable
    return A
end

I['qb-inventory'] = makeQbStyle('qb-inventory', 'qb-inventory:client:ItemBox')
I['ps-inventory'] = makeQbStyle('ps-inventory', 'ps-inventory:client:ItemBox')
I['lj-inventory'] = makeQbStyle('lj-inventory', 'inventory:client:ItemBox')

-- ps-inventory renamed its stash events (ps-inventory:server:OpenInventory); its
-- OpenInventory export opens the stash and sets the client's current stash itself
I['ps-inventory'].openStash = function(src, id, opts)
    exports['ps-inventory']:OpenInventory('stash', id, { maxweight = opts.weight, slots = opts.slots }, src)
    return true
end
I['lj-inventory'].openStash = classicStash

-- qb-inventory before v2 had no AddItem/RemoveItem exports: use Player.Functions
do
    local v2 = I['qb-inventory']
    local v1 = makeQbStyle(nil, 'inventory:client:ItemBox')
    local wrapped = {}
    for key, fn in pairs(v2) do
        if type(fn) == 'function' and v1[key] then
            wrapped[key] = function(...)
                if qbVersion2('qb-inventory') then return fn(...) end
                return v1[key](...)
            end
        else
            wrapped[key] = fn
        end
    end
    wrapped.image = function(name)
        local def = qbShared(name)
        return 'qb-inventory', 'html/images/' .. (def and def.image or (name .. '.png'))
    end
    -- 2.x opens stashes from the server; 1.x only through its client event
    wrapped.openStash = function(src, id, opts)
        if not qbVersion2('qb-inventory') then return classicStash(src, id, opts) end
        exports['qb-inventory']:OpenInventory(src, id, { label = opts.label, maxweight = opts.weight, slots = opts.slots })
        return true
    end
    I['qb-inventory'] = wrapped
end

-- ═══════════════════════════════════════════════════════════════════════════
-- qs-inventory
-- ═══════════════════════════════════════════════════════════════════════════

local function qsList()
    local ok, list = pcall(function() return exports['qs-inventory']:GetItemList() end)
    return ok and type(list) == 'table' and list or {}
end

I['qs-inventory'] = {
    metadata = true,
    count = function(src, name, meta)
        if meta then return countFromItems(I['qs-inventory'].items(src), name, meta) end
        return tonumber(exports['qs-inventory']:GetItemTotalAmount(src, name)) or 0
    end,
    add = function(src, name, count, meta)
        return exports['qs-inventory']:AddItem(src, name, count, nil, meta) == true
    end,
    remove = function(src, name, count, meta, slot)
        if meta and not slot then
            slot = findSlot(I['qs-inventory'].items(src), name, meta)
            if not slot then return false end
        end
        return exports['qs-inventory']:RemoveItem(src, name, count, slot, meta) == true
    end,
    canCarry = function(src, name, count)
        return exports['qs-inventory']:CanCarryItem(src, name, count) == true
    end,
    items = function(src)
        return normalizeList(exports['qs-inventory']:GetInventory(src))
    end,
    setMeta = function(src, slot, meta)
        exports['qs-inventory']:SetItemMetadata(src, slot, meta)
        return true
    end,
    label = function(name)
        local def = qsList()[name]
        return def and def.label or nil
    end,
    image = function(name)
        local def = qsList()[name]
        return 'qs-inventory', 'html/images/' .. (def and def.image or (name .. '.png'))
    end,
    usable = function(name, cb)
        local ok = pcall(function()
            exports['qs-inventory']:CreateUsableItem(name, function(source, item)
                cb(source, type(item) == 'table' and item or { name = name })
            end)
        end)
        return ok or frameworkUsable(name, cb)
    end,
    openStash = classicStash,   -- qs documents the qb 'inventory:server:OpenInventory' stash flow
}

-- ═══════════════════════════════════════════════════════════════════════════
-- codem-inventory
-- ═══════════════════════════════════════════════════════════════════════════

local function codemList()
    local ok, list = pcall(function() return exports['codem-inventory']:GetItemList() end)
    return ok and type(list) == 'table' and list or {}
end

I['codem-inventory'] = {
    metadata = true,
    count = function(src, name, meta)
        if meta then return countFromItems(I['codem-inventory'].items(src), name, meta) end
        return tonumber(exports['codem-inventory']:GetItemsTotalAmount(src, name)) or 0
    end,
    add = function(src, name, count, meta)
        return exports['codem-inventory']:AddItem(src, name, count, nil, meta) ~= false
    end,
    remove = function(src, name, count, meta, slot)
        if meta and not slot then
            slot = findSlot(I['codem-inventory'].items(src), name, meta)
            if not slot then return false end
        end
        return exports['codem-inventory']:RemoveItem(src, name, count, slot) ~= false
    end,
    canCarry = function(src, name, count)
        local ok, can = pcall(function() return exports['codem-inventory']:CanCarryItem(src, name, count) end)
        if ok and can ~= nil then return can == true end
        return true
    end,
    items = function(src)
        local identifier = Bridge.GetIdentifier(src)
        return normalizeList(exports['codem-inventory']:GetInventory(identifier, src))
    end,
    slot = function(src, slot)
        return normalize(exports['codem-inventory']:GetItemBySlot(src, slot), slot)
    end,
    setMeta = function(src, slot, meta)
        exports['codem-inventory']:SetItemMetadata(src, slot, meta)
        return true
    end,
    label = function(name)
        local def = codemList()[name]
        return def and def.label or nil
    end,
    image = function(name)
        local def = codemList()[name]
        return 'codem-inventory', 'html/itemimages/' .. (def and def.image or (name .. '.png'))
    end,
    usable = frameworkUsable,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- origen_inventory
-- ═══════════════════════════════════════════════════════════════════════════

I['origen_inventory'] = {
    metadata = true,
    image = { 'origen_inventory', 'html/images/%s.png' },
    count = function(src, name, meta)
        return tonumber(exports.origen_inventory:getItemCount(src, name, meta, false)) or 0
    end,
    add = function(src, name, count, meta)
        return exports.origen_inventory:addItem(src, name, count, meta, nil) ~= false
    end,
    remove = function(src, name, count, meta, slot)
        return exports.origen_inventory:removeItem(src, name, count, meta, slot) ~= false
    end,
    canCarry = function(src, name, count)
        return exports.origen_inventory:canCarryItem(src, name, count) == true
    end,
    items = function(src)
        local inv = exports.origen_inventory:GetInventory(src)
        return normalizeList(type(inv) == 'table' and (inv.inventory or inv) or {})
    end,
    setMeta = function(src, slot, meta)
        exports.origen_inventory:setMetadata(src, slot, meta)
        return true
    end,
    label = function(name)
        local def = exports.origen_inventory:Items(name)
        return type(def) == 'table' and def.label or nil
    end,
    usable = frameworkUsable,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- tgiann-inventory (pictures live in the 'inventory_images' resource)
-- ═══════════════════════════════════════════════════════════════════════════

I['tgiann-inventory'] = {
    metadata = true,
    image = { 'inventory_images', 'images/%s.png' },
    count = function(src, name, meta)
        return countFromItems(I['tgiann-inventory'].items(src), name, meta)
    end,
    add = function(src, name, count, meta)
        return exports['tgiann-inventory']:AddItem(src, name, count, nil, meta, false) ~= false
    end,
    remove = function(src, name, count, meta, slot)
        if meta and not slot then
            slot = findSlot(I['tgiann-inventory'].items(src), name, meta)
            if not slot then return false end
        end
        return exports['tgiann-inventory']:RemoveItem(src, name, count, slot, meta) ~= false
    end,
    canCarry = function(src, name, count)
        return exports['tgiann-inventory']:CanCarryItem(src, name, count) == true
    end,
    items = function(src)
        local out = {}
        for slot, item in pairs(exports['tgiann-inventory']:GetPlayerItems(src) or {}) do
            if tonumber(slot) then
                local n = normalize(item, tonumber(slot))
                if n and n.count > 0 then out[#out + 1] = n end
            end
        end
        return out
    end,
    slot = function(src, slot)
        return normalize(exports['tgiann-inventory']:GetItemBySlot(src, slot), slot)
    end,
    setMeta = function(src, slot, meta)
        local item = exports['tgiann-inventory']:GetItemBySlot(src, slot)
        if not item then return false end
        exports['tgiann-inventory']:UpdateItemMetadata(src, item.name, slot, meta)
        return true
    end,
    label = function(name)
        local list = exports['tgiann-inventory']:GetItemList() or {}
        return list[name] and list[name].label or nil
    end,
    usable = frameworkUsable,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- core_inventory
-- ═══════════════════════════════════════════════════════════════════════════

I['core_inventory'] = {
    metadata = true,
    image = { 'core_inventory', 'html/img/%s.png' },
    count = function(src, name, meta)
        if meta then return countFromItems(I['core_inventory'].items(src), name, meta) end
        return tonumber(exports.core_inventory:getItemCount(src, name)) or 0
    end,
    add = function(src, name, count, meta)
        return exports.core_inventory:addItem(src, name, count, meta) ~= false
    end,
    remove = function(src, name, count, meta, slot)
        if meta and not slot then
            slot = findSlot(I['core_inventory'].items(src), name, meta)
            if not slot then return false end
        end
        if slot then return exports.core_inventory:removeItemExact(src, slot, count) ~= false end
        exports.core_inventory:removeItem(src, name, count)
        return true
    end,
    canCarry = function(src, name, count)
        local ok, can = pcall(function() return exports.core_inventory:canCarry(src, name, count) end)
        if ok and can ~= nil then return can == true end
        return true
    end,
    items = function(src)
        local out = {}
        for _, stack in pairs(exports.core_inventory:getInventory(src) or {}) do
            local hasMeta = type(stack.metadata or stack.info) == 'table' and next(stack.metadata or stack.info) ~= nil
            if hasMeta and (tonumber(stack.count or stack.amount) or 0) > 1 then
                for _, item in pairs(exports.core_inventory:getItems(src, stack.name) or {}) do
                    item.name = item.name or stack.name
                    local n = normalize(item)
                    if n and n.count > 0 then out[#out + 1] = n end
                end
            else
                local n = normalize(stack)
                if n and n.count > 0 then out[#out + 1] = n end
            end
        end
        return out
    end,
    setMeta = function(src, slot, meta)
        exports.core_inventory:setMetadata(src, slot, meta)
        return true
    end,
    label = function(name)
        local list = exports.core_inventory:getItemsList() or {}
        return list[name] and list[name].label or nil
    end,
    usable = frameworkUsable,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- FRAMEWORK FALLBACK (no inventory resource)
-- ═══════════════════════════════════════════════════════════════════════════

local function esxPlayer(src)
    local ESX = Bridge.Core()
    return ESX and ESX.GetPlayerFromId(src) or nil
end

local esxInventory = {
    metadata = false,    -- emulated through the KVP store below
    count = function(src, name)
        local x = esxPlayer(src)
        local item = x and x.getInventoryItem(name)
        return item and tonumber(item.count) or 0
    end,
    add = function(src, name, count)
        local x = esxPlayer(src)
        if not x then return false end
        if x.canCarryItem and not x.canCarryItem(name, count) then return false end
        x.addInventoryItem(name, count)
        return true
    end,
    remove = function(src, name, count)
        local x = esxPlayer(src)
        if not x then return false end
        local item = x.getInventoryItem(name)
        if not item or (tonumber(item.count) or 0) < count then return false end
        x.removeInventoryItem(name, count)
        return true
    end,
    canCarry = function(src, name, count)
        local x = esxPlayer(src)
        if not x then return false end
        if x.canCarryItem then return x.canCarryItem(name, count) == true end
        return true
    end,
    items = function(src)
        local x = esxPlayer(src)
        return x and normalizeList(x.getInventory()) or {}
    end,
    label = function(name)
        local ESX = Bridge.Core()
        return ESX and ESX.GetItemLabel and ESX.GetItemLabel(name) or nil
    end,
    usable = frameworkUsable,
}

-- Standalone without an inventory: nothing can be carried, unless
-- Config.Bridge.standaloneFreeItems makes every item "always there".
local noInventory = {
    metadata = true,
    count = function() return Bridge.Cfg('standaloneFreeItems', false) and 999 or 0 end,
    add = function() return Bridge.Cfg('standaloneFreeItems', false) == true end,
    remove = function() return Bridge.Cfg('standaloneFreeItems', false) == true end,
    canCarry = function() return Bridge.Cfg('standaloneFreeItems', false) == true end,
    items = function() return {} end,
    usable = function() return false end,
}

if Bridge.Framework == 'esx' then
    I['framework'] = esxInventory
elseif Bridge.Framework == 'qbcore' then
    I['framework'] = makeQbStyle(nil, 'inventory:client:ItemBox')
else
    I['framework'] = noInventory
end

-- ═══════════════════════════════════════════════════════════════════════════
-- METADATA EMULATION (inventories with metadata = false)
-- ═══════════════════════════════════════════════════════════════════════════

local Store = {}

local function storeKey(identifier, name)
    return ('nza_meta:%s:%s'):format(identifier, name)
end

function Store.load(src, name)
    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return nil, {} end
    local raw = GetResourceKvpString(storeKey(identifier, name))
    local list = {}
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then list = decoded end
    end
    return identifier, list
end

function Store.save(identifier, name, list)
    if not identifier then return end
    if #list == 0 then
        DeleteResourceKvp(storeKey(identifier, name))
    else
        SetResourceKvp(storeKey(identifier, name), json.encode(list))
    end
end

-- Drop entries for units the player no longer has (sold, dropped, given away)
function Store.reconcile(src, name, realCount)
    local identifier, list = Store.load(src, name)
    if #list > realCount then
        while #list > realCount do table.remove(list, 1) end
        Store.save(identifier, name, list)
    end
    return identifier, list
end

local serialCounter = 0
local function newSerial()
    serialCounter = (serialCounter + 1) % 100000
    return ('NZ%X%05d'):format(os.time(), serialCounter)
end

function Store.push(src, name, count, meta)
    local identifier, list = Store.load(src, name)
    for _ = 1, count do
        local entry = {}
        for k, v in pairs(meta) do entry[k] = v end
        entry.serial = entry.serial or newSerial()
        list[#list + 1] = entry
    end
    Store.save(identifier, name, list)
end

local function emulated(adapter)
    return adapter.metadata == false and Bridge.Cfg('emulateMetadata', true) ~= false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE
-- ═══════════════════════════════════════════════════════════════════════════

local resolved, resolvedOnce = nil, false

local function resolve()
    if resolvedOnce and resolved then return resolved end
    resolvedOnce = true
    resolved = Bridge.Pick('inventory', Bridge.Cfg('inventory', 'auto'), {
        has = function(name) return I[name] ~= nil end,
    }) or 'framework'
    Bridge.Debug('inventory:', resolved)
    return resolved
end

local function adapter()
    return I[resolve()] or I['framework'], resolve()
end

local function run(method, ...)
    local A, name = adapter()
    local fn = A[method]
    if not fn then return false end
    return Bridge.Try(('inventory.%s.%s'):format(name, method), fn, ...)
end

function Bridge.Inv.Resource()
    return resolve()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

local function dirty(src, name)
    TriggerClientEvent('nza:bridge:inv:dirty', src, name and { name } or nil)
end

local function validArgs(src, name, count)
    src = tonumber(src)
    if not src or src <= 0 or type(name) ~= 'string' or name == '' then return nil end
    count = math.floor(tonumber(count) or 1)
    if count < 1 then return nil end
    return src, count
end

function Bridge.Inv.GetItems(src)
    src = tonumber(src)
    if not src then return {} end
    local A = adapter()
    local ok, items = run('items', src)
    items = ok and items or {}
    if not emulated(A) then return items end

    -- split stacks that carry emulated metadata into single units
    local out = {}
    for _, item in ipairs(items) do
        local _, list = Store.reconcile(src, item.name, item.count)
        for i, meta in ipairs(list) do
            out[#out + 1] = { name = item.name, label = item.label, count = 1, slot = VSLOT + i, metadata = meta, weight = item.weight }
        end
        local rest = item.count - #list
        if rest > 0 then
            out[#out + 1] = { name = item.name, label = item.label, count = rest, slot = item.slot, metadata = {}, weight = item.weight }
        end
    end
    return out
end

function Bridge.Inv.Count(src, name, metaMatch)
    src = tonumber(src)
    if not src or type(name) ~= 'string' then return 0 end
    local A = adapter()
    if metaMatch ~= nil and type(metaMatch) ~= 'table' then metaMatch = nil end
    if emulated(A) and metaMatch then
        local ok, real = run('count', src, name)
        local _, list = Store.reconcile(src, name, ok and tonumber(real) or 0)
        local n = 0
        for _, meta in ipairs(list) do
            if Bridge.MetaMatches(meta, metaMatch) then n = n + 1 end
        end
        return n
    end
    if A.count then
        local ok, n = run('count', src, name, metaMatch)
        return ok and (tonumber(n) or 0) or 0
    end
    return countFromItems(Bridge.Inv.GetItems(src), name, metaMatch)
end

function Bridge.Inv.HasItem(src, name, count)
    return Bridge.Inv.Count(src, name) >= (tonumber(count) or 1)
end

function Bridge.Inv.Search(src, name)
    local out = {}
    for _, item in ipairs(Bridge.Inv.GetItems(src)) do
        if item.name == name then out[#out + 1] = item end
    end
    return out
end

function Bridge.Inv.CanCarry(src, name, count)
    local s, c = validArgs(src, name, count)
    if not s then return false end
    local A = adapter()
    if not A.canCarry then return true end
    local ok, can = run('canCarry', s, name, c)
    return ok and can == true
end

function Bridge.Inv.AddItem(src, name, count, metadata)
    local s, c = validArgs(src, name, count)
    if not s then return false end
    if metadata ~= nil and type(metadata) ~= 'table' then metadata = nil end
    local A = adapter()
    if emulated(A) then
        local ok, done = run('add', s, name, c)
        if not (ok and done) then return false end
        if metadata and next(metadata) then Store.push(s, name, c, metadata) end
        dirty(s, name)
        return true
    end
    local ok, done = run('add', s, name, c, metadata)
    if ok and done == true then
        dirty(s, name)
        return true
    end
    return false
end

function Bridge.Inv.RemoveItem(src, name, count, metadata, slot)
    local s, c = validArgs(src, name, count)
    if not s then return false end
    if metadata ~= nil and type(metadata) ~= 'table' then metadata = nil end
    slot = tonumber(slot)
    local A = adapter()

    if emulated(A) then
        local okCount, real = run('count', s, name)
        real = okCount and tonumber(real) or 0
        if real < c then return false end
        local identifier, list = Store.reconcile(s, name, real)
        local remove = {}
        if slot and slot > VSLOT then
            if not list[slot - VSLOT] or c ~= 1 then return false end
            remove[slot - VSLOT] = true
        elseif metadata then
            local found = 0
            for i, meta in ipairs(list) do
                if found < c and Bridge.MetaMatches(meta, metadata) then
                    remove[i] = true
                    found = found + 1
                end
            end
            if found < c then return false end
        end
        local ok, done = run('remove', s, name, c)
        if not (ok and done) then return false end
        if next(remove) then
            local kept = {}
            for i, meta in ipairs(list) do
                if not remove[i] then kept[#kept + 1] = meta end
            end
            Store.save(identifier, name, kept)
        else
            Store.reconcile(s, name, real - c)
        end
        dirty(s, name)
        return true
    end

    local ok, done = run('remove', s, name, c, metadata, slot)
    if ok and done == true then
        dirty(s, name)
        return true
    end
    return false
end

function Bridge.Inv.GetSlot(src, slot)
    src, slot = tonumber(src), tonumber(slot)
    if not src or not slot then return nil end
    local A = adapter()
    if emulated(A) or not A.slot then
        for _, item in ipairs(Bridge.Inv.GetItems(src)) do
            if item.slot == slot then return item end
        end
        return nil
    end
    local ok, item = run('slot', src, slot)
    return ok and item or nil
end

function Bridge.Inv.SetMetadata(src, slot, metadata)
    src, slot = tonumber(src), tonumber(slot)
    if not src or not slot or type(metadata) ~= 'table' then return false end
    local A = adapter()
    if emulated(A) then
        if slot <= VSLOT then return false end
        local item = Bridge.Inv.GetSlot(src, slot)
        if not item then return false end
        local identifier, list = Store.load(src, item.name)
        local entry = list[slot - VSLOT]
        if not entry then return false end
        metadata.serial = metadata.serial or entry.serial
        list[slot - VSLOT] = metadata
        Store.save(identifier, item.name, list)
        return true
    end
    if not A.setMeta then return false end
    local ok, done = run('setMeta', src, slot, metadata)
    return ok and done ~= false
end

function Bridge.Inv.Clear(src, keep)
    src = tonumber(src)
    if not src then return false end
    local A = adapter()
    local set = keepSet(keep)
    if emulated(A) then
        local identifier = Bridge.GetIdentifier(src)
        for _, item in ipairs(Bridge.Inv.GetItems(src)) do
            if not set[item.name] and identifier then DeleteResourceKvp(storeKey(identifier, item.name)) end
        end
    end
    if A.clear then
        local ok, done = run('clear', src, keep)
        if ok and done then
            dirty(src)
            return true
        end
    end
    local ok, items = run('items', src)
    for _, item in ipairs(ok and items or {}) do
        if not set[item.name] then run('remove', src, item.name, item.count, nil, item.slot) end
    end
    dirty(src)
    return true
end

-- Open a stash of the running inventory for the player. The caller checks access first.
-- False when the inventory has no stash support here (codem, origen, tgiann, core,
-- plain ESX/QB, none): the caller then uses its own storage.
function Bridge.Inv.OpenStash(src, id, opts)
    src = tonumber(src)
    if not src or src <= 0 or type(id) ~= 'string' or id == '' then return false end
    opts = type(opts) == 'table' and opts or {}
    local o = {
        label = (type(opts.label) == 'string' and opts.label ~= '') and opts.label or id,
        slots = math.max(1, math.floor(tonumber(opts.slots) or 50)),
        weight = math.max(0, math.floor(tonumber(opts.weight) or 100000)),
        owner = opts.owner,
    }
    local ok, done = run('openStash', src, id, o)
    return ok and done == true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LABELS & IMAGES
-- ═══════════════════════════════════════════════════════════════════════════

local labelCache, imageCache = {}, {}

function Bridge.Inv.Label(name)
    if type(name) ~= 'string' then return '' end
    if labelCache[name] then return labelCache[name] end
    local ok, label = run('label', name)
    label = (ok and type(label) == 'string' and label ~= '') and label or Bridge.ItemLabel(name)
    labelCache[name] = label
    return label
end

local function fileExists(resource, path)
    if not resource or not path or not Bridge.Started(resource) then return false end
    local data = LoadResourceFile(resource, path)
    return data ~= nil and data ~= ''
end

local function inventoryImage(name)
    local A = adapter()
    local img = A.image
    local resource, path
    if type(img) == 'function' then
        local ok, r, p = pcall(img, name)
        if ok then resource, path = r, p end
    elseif type(img) == 'table' then
        resource, path = img[1], img[2]:format(name)
    end
    if fileExists(resource, path) then return ('nui://%s/%s'):format(resource, path) end
    return nil
end

function Bridge.Inv.Image(name)
    if type(name) ~= 'string' or name == '' then name = 'nza_unknown' end
    if imageCache[name] then return imageCache[name] end
    local own = NZA.Resource or GetCurrentResourceName()
    local url = Bridge.Cfg('preferInventoryImages', true) and inventoryImage(name) or nil
    if not url then
        local def = Bridge.ItemDef(name)
        local candidates = { name .. '.png' }
        if def and type(def.image) == 'string' then candidates[#candidates + 1] = def.image end
        for _, file in ipairs(candidates) do
            if fileExists(own, 'html/img/items/' .. file) then
                url = ('nui://%s/html/img/items/%s'):format(own, file)
                break
            end
        end
    end
    url = url or ('nui://%s/html/img/items/nza_unknown.png'):format(own)
    imageCache[name] = url
    return url
end

-- ═══════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS
-- ═══════════════════════════════════════════════════════════════════════════

local usable = {}   -- [name] = fn

local function wrapUsable(name, fn)
    return function(src, raw)
        src = tonumber(src)
        if not src then return end
        local item = normalize(type(raw) == 'table' and raw or { name = name }) or { name = name, count = 1, metadata = {} }
        item.name = name
        local ok, err = pcall(fn, src, item)
        if not ok then
            print(('^1[nayzeee-ambulance:bridge]^7 usable item "%s" failed: %s'):format(name, tostring(err)))
        end
    end
end

local function applyUsable(name)
    local A, adapterName = adapter()
    if not A.usable then
        Bridge.Warn(('inventory "%s" cannot register usable items - "%s" will not be usable'):format(adapterName, name))
        return
    end
    local ok, done = Bridge.Try('inventory.' .. adapterName .. '.usable', A.usable, name, wrapUsable(name, usable[name]))
    if not (ok and done) then
        Bridge.Debug(('usable "%s" not registered with %s'):format(name, adapterName))
    end
end

function Bridge.Inv.RegisterUsable(name, fn)
    if type(name) ~= 'string' or type(fn) ~= 'function' then return false end
    usable[name] = fn
    applyUsable(name)
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CLIENT CACHE CALLBACK
-- ═══════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:bridge:inv:counts', function(src, names)
    if type(names) ~= 'table' then return {} end
    if not Bridge.Throttle(src, 'inv:counts', 200) then return nil end
    local out, n = {}, 0
    for _, name in pairs(names) do
        n = n + 1
        if n > 40 then break end
        if type(name) == 'string' and #name <= 64 then
            out[name] = Bridge.Inv.Count(src, name)
        end
    end
    return out
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOURCE RESTARTS
-- ═══════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or not Bridge.IsKnownResource('inventory', resource) then return end
    resolvedOnce, resolved = false, nil
    labelCache, imageCache = {}, {}
    -- inventories drop hooks/usables of other resources when they restart
    SetTimeout(1000, function()
        for name in pairs(usable) do applyUsable(name) end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() or not Bridge.IsKnownResource('inventory', resource) then return end
    resolvedOnce, resolved = false, nil
end)

CreateThread(function()
    Wait(500)
    print(('^5[nayzeee-ambulance]^7 Bridge | inventory: ^3%s^7'):format(resolve()))
end)
