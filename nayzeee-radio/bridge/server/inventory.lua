--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE RADIO - Bridge: inventory (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Adapters for ox_inventory, qb-inventory (old and
    new exports), qs-inventory, codem-inventory, origen_inventory,
    tgiann-inventory, core_inventory, ps-inventory, lj-inventory and the
    framework's own inventory (ESX xPlayer / QB Player.Functions).

    API
      Bridge.Inv.HasItem(src, name, count?)            → bool
      Bridge.Inv.Count(src, name, metaMatch?)          → number   metaMatch = { serial = 'X' } (subset match)
      Bridge.Inv.Counts(src, names)                    → { [name] = number }   several items, one
                                                         inventory read where a single count would
                                                         read the whole inventory anyway (adapter
                                                         flag bulk = true: QB style, ESX)
      Bridge.Inv.AddItem(src, name, count, metadata?)  → bool
      Bridge.Inv.RemoveItem(src, name, count, metadata?, slot?) → bool
      Bridge.Inv.CanCarry(src, name, count)            → bool
      Bridge.Inv.GetItems(src)   → { { name, label, count, slot, metadata, weight } }
      Bridge.Inv.GetSlot(src, slot) → item | nil
      Bridge.Inv.SetMetadata(src, slot, metadata)      → bool
      Bridge.Inv.Search(src, name) → every stack of that item with its metadata
      Bridge.Inv.RegisterUsable(name, fn(src, item))
      Bridge.Inv.Label(name) → label        Bridge.Inv.Image(name) → 'nui://...png'
      Bridge.Inv.Resource() → adapter name
      Bridge.Inv.OnChanged(fn(src, name|nil)) → fn
          Called after an item of a player changed. Sources: every Add/Remove made
          through this bridge, and with ox_inventory also items of Config.Items moved
          in or out of a player's inventory by anyone (drop, give, stash, other
          scripts; ox 'swapItems' hook). Other inventories do not announce item
          moves, so a module that must notice a lost item still re-checks it on its
          own timer (the radio does: every 5 s while powered, SPEC §4).
          name is nil when the change could be any item.

    METADATA
      Inventories without item metadata (plain ESX) ignore the metadata
      arguments: Count with metaMatch then counts every unit of the item.

    CALLBACK
      lib.callback 'nzr:bridge:inv:counts' (names[]) → { [name] = count }   (client Bridge.Inv cache)

    EVENTS SENT
      nzr:bridge:inv:dirty (S→C) { name } | nil   after every change made here (client cache refresh)

    ADDING YOUR OWN
      Bridge.InventoryAdapters['my_inv'] = { add = fn, remove = fn, items = fn, ... }
      Bridge.Resources.inventory['my_inv'] = 'my_inv' and add it to Bridge.Priority.inventory.
      Every adapter function is optional except add, remove and items. Set bulk = true when
      items(src) is the cheap way to count several items (count reads the whole list anyway).
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Inv = Bridge.Inv or {}

local I = {}
Bridge.InventoryAdapters = I

local RESOURCE = GetCurrentResourceName()

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- ox_inventory
-- ════════════════════════════════════════════════════════════════════════

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
}

-- ════════════════════════════════════════════════════════════════════════
-- QB-style inventories: qb-inventory (v1 = Player.Functions, v2 = exports),
-- ps-inventory, lj-inventory and the QBCore framework fallback
-- ════════════════════════════════════════════════════════════════════════

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
    -- every count fetches the QB player object: several items come from one items() read
    local A = { metadata = true, bulk = true }
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
            ok = exports[resource]:AddItem(src, name, count, false, meta, RESOURCE)
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
            ok = exports[resource]:RemoveItem(src, name, count, slot or false, RESOURCE)
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

    A.usable = frameworkUsable
    return A
end

I['qb-inventory'] = makeQbStyle('qb-inventory', 'qb-inventory:client:ItemBox')
I['ps-inventory'] = makeQbStyle('ps-inventory', 'ps-inventory:client:ItemBox')
I['lj-inventory'] = makeQbStyle('lj-inventory', 'inventory:client:ItemBox')

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
    I['qb-inventory'] = wrapped
end

-- ════════════════════════════════════════════════════════════════════════
-- qs-inventory
-- ════════════════════════════════════════════════════════════════════════

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
}

-- ════════════════════════════════════════════════════════════════════════
-- codem-inventory
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- origen_inventory
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- tgiann-inventory (pictures live in the 'inventory_images' resource)
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- core_inventory
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- FRAMEWORK FALLBACK (no inventory resource)
-- ════════════════════════════════════════════════════════════════════════

local function esxPlayer(src)
    local ESX = Bridge.Core()
    return ESX and ESX.GetPlayerFromId(src) or nil
end

local esxInventory = {
    metadata = false,    -- plain ESX items carry no metadata
    bulk = true,         -- each count fetches the xPlayer: several items come from one items() read
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

-- ════════════════════════════════════════════════════════════════════════
-- RESOLVE
-- ════════════════════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════════════════════
-- CHANGE HOOKS
-- ════════════════════════════════════════════════════════════════════════

local changeHandlers = {}

function Bridge.Inv.OnChanged(fn)
    if type(fn) ~= 'function' then return nil end
    changeHandlers[#changeHandlers + 1] = fn
    return fn
end

local function changed(src, name)
    src = tonumber(src)
    if not src or src <= 0 then return end
    TriggerClientEvent('nzr:bridge:inv:dirty', src, name and { name } or nil)
    for i = 1, #changeHandlers do
        local ok, err = pcall(changeHandlers[i], src, name)
        if not ok then
            print(('^1[nayzeee-radio:bridge]^7 inventory change hook failed: %s'):format(tostring(err)))
        end
    end
end

-- ox_inventory: moves of our own items by anyone. The hook runs before the move
-- happens, so the handlers are told a moment later; returning nothing lets it go on.
local swapHookId = nil

local function ourItemFilter()
    local filter, any = {}, false
    for _, itemName in pairs((Config and Config.Items) or {}) do
        if type(itemName) == 'string' and itemName ~= '' then
            filter[itemName] = true
            any = true
        end
    end
    return any and filter or nil
end

local function hookOxSwaps()
    if resolve() ~= 'ox_inventory' then return end
    local filter = ourItemFilter()
    if not filter then return end
    local ok, id = pcall(function()
        return ox:registerHook('swapItems', function(payload)
            local from, to = tonumber(payload.fromInventory), tonumber(payload.toInventory)
            local item = type(payload.fromSlot) == 'table' and payload.fromSlot.name or nil
            if from == to then return end
            SetTimeout(150, function()
                if from then changed(from, item) end
                if to then changed(to, item) end
            end)
        end, { itemFilter = filter })
    end)
    swapHookId = ok and id or nil
    if not ok then Bridge.Debug('ox swapItems hook failed: ' .. tostring(id)) end
end

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ════════════════════════════════════════════════════════════════════════

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
    local ok, items = run('items', src)
    return ok and items or {}
end

function Bridge.Inv.Count(src, name, metaMatch)
    src = tonumber(src)
    if not src or type(name) ~= 'string' then return 0 end
    local A = adapter()
    if metaMatch ~= nil and type(metaMatch) ~= 'table' then metaMatch = nil end
    if A.metadata == false then metaMatch = nil end
    if A.count then
        local ok, n = run('count', src, name, metaMatch)
        return ok and (tonumber(n) or 0) or 0
    end
    return countFromItems(Bridge.Inv.GetItems(src), name, metaMatch)
end

function Bridge.Inv.Counts(src, names)
    local out = {}
    src = tonumber(src)
    if not src or type(names) ~= 'table' then return out end
    local A = adapter()
    if A.bulk and A.items then
        local items = Bridge.Inv.GetItems(src)
        for _, name in pairs(names) do
            if type(name) == 'string' then out[name] = countFromItems(items, name, nil) end
        end
        return out
    end
    for _, name in pairs(names) do
        if type(name) == 'string' then out[name] = Bridge.Inv.Count(src, name) end
    end
    return out
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
    local ok, done = run('add', s, name, c, metadata)
    if ok and done == true then
        changed(s, name)
        return true
    end
    return false
end

function Bridge.Inv.RemoveItem(src, name, count, metadata, slot)
    local s, c = validArgs(src, name, count)
    if not s then return false end
    if metadata ~= nil and type(metadata) ~= 'table' then metadata = nil end
    if adapter().metadata == false then metadata = nil end
    local ok, done = run('remove', s, name, c, metadata, tonumber(slot))
    if ok and done == true then
        changed(s, name)
        return true
    end
    return false
end

function Bridge.Inv.GetSlot(src, slot)
    src, slot = tonumber(src), tonumber(slot)
    if not src or not slot then return nil end
    local A = adapter()
    if not A.slot then
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
    if not A.setMeta then return false end
    local ok, done = run('setMeta', src, slot, metadata)
    return ok and done ~= false
end

-- ════════════════════════════════════════════════════════════════════════
-- LABELS & IMAGES
-- ════════════════════════════════════════════════════════════════════════

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

-- 1. the inventory's own picture (Config.Bridge.preferInventoryImages)
-- 2. html/img/items/<name>.png here (or Config.ItemDefs[key].image for a renamed item)
-- 3. html/img/items/nzr_unknown.png
function Bridge.Inv.Image(name)
    if type(name) ~= 'string' or name == '' then name = 'nzr_unknown' end
    if imageCache[name] then return imageCache[name] end
    local url = Bridge.Cfg('preferInventoryImages', true) and inventoryImage(name) or nil
    if not url then
        local def = Bridge.ItemDef(name)
        local candidates = { name .. '.png' }
        if def and type(def.image) == 'string' then candidates[#candidates + 1] = def.image end
        for _, file in ipairs(candidates) do
            if fileExists(RESOURCE, 'html/img/items/' .. file) then
                url = ('nui://%s/html/img/items/%s'):format(RESOURCE, file)
                break
            end
        end
    end
    url = url or ('nui://%s/html/img/items/nzr_unknown.png'):format(RESOURCE)
    imageCache[name] = url
    return url
end

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS
-- ════════════════════════════════════════════════════════════════════════

local usable = {}   -- [name] = fn

local function wrapUsable(name, fn)
    return function(src, raw)
        src = tonumber(src)
        if not src then return end
        local item = normalize(type(raw) == 'table' and raw or { name = name }) or { name = name, count = 1, metadata = {} }
        item.name = name
        local ok, err = pcall(fn, src, item)
        if not ok then
            print(('^1[nayzeee-radio:bridge]^7 usable item "%s" failed: %s'):format(name, tostring(err)))
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

-- ════════════════════════════════════════════════════════════════════════
-- CLIENT CACHE CALLBACK
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nzr:bridge:inv:counts', function(src, names)
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

-- ════════════════════════════════════════════════════════════════════════
-- RESOURCE RESTARTS
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStart', function(resource)
    if resource == RESOURCE or not Bridge.IsKnownResource('inventory', resource) then return end
    resolvedOnce, resolved = false, nil
    labelCache, imageCache = {}, {}
    -- inventories drop hooks/usables of other resources when they restart
    SetTimeout(1000, function()
        for name in pairs(usable) do applyUsable(name) end
        swapHookId = nil
        hookOxSwaps()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then
        if swapHookId then pcall(function() ox:removeHooks(swapHookId) end) end
        return
    end
    if not Bridge.IsKnownResource('inventory', resource) then return end
    resolvedOnce, resolved = false, nil
end)

CreateThread(function()
    Wait(500)
    hookOxSwaps()
end)
