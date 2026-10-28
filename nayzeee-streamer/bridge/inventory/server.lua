-- Inventory bridge (server): ox_inventory, qb-inventory 2.x, framework items (ESX / QBCore) and custom.
-- Open under escrow. Bridge.GetItemCount / AddItem / RemoveItem / CanCarry / RegisterUsableItem use this.

Bridge = Bridge or {}

local REASON = 'nayzeee-streamer'

local function started(name)
    return GetResourceState(name) == 'started'
end

local function present(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local function call(resource, fnName, ...)
    if not started(resource) then return false, nil end
    local args = table.pack(...)
    return pcall(function()
        return exports[resource][fnName](exports[resource], table.unpack(args, 1, args.n))
    end)
end

local function sharedItems()
    local core = Bridge.GetCore and Bridge.GetCore()
    return core and core.Shared and core.Shared.Items or nil
end

local function itemBox(src, item, action, count)
    local items = sharedItems()
    if items and items[item] then
        TriggerClientEvent('qb-inventory:client:ItemBox', src, items[item], action, count)
    end
end

--- Framework usable item (ESX / QBCore). Qbox runs ox_inventory, which uses client.export instead.
local function frameworkUsable(item, fn)
    local fw = Bridge.Framework
    local core = Bridge.GetCore and Bridge.GetCore()
    if fw == 'esx' and core and core.RegisterUsableItem then
        local ok = pcall(core.RegisterUsableItem, item, function(source) fn(source) end)
        return ok
    elseif fw == 'qbcore' and core and core.Functions and core.Functions.CreateUseableItem then
        local ok = pcall(core.Functions.CreateUseableItem, item, function(source) fn(source) end)
        return ok
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- ox_inventory

local oxAdapter = {
    GetItemCount = function(src, item)
        local ok, count = call('ox_inventory', 'GetItemCount', src, item)
        return ok and tonumber(count) or 0
    end,
    AddItem = function(src, item, count, meta)
        local ok, success = call('ox_inventory', 'AddItem', src, item, count, meta)
        return ok and success == true
    end,
    RemoveItem = function(src, item, count)
        local ok, success = call('ox_inventory', 'RemoveItem', src, item, count)
        return ok and success == true
    end,
    CanCarry = function(src, item, count)
        local ok, can = call('ox_inventory', 'CanCarryItem', src, item, count)
        return ok and can == true
    end,
    RegisterUsableItem = function(item)
        -- ox_inventory: items/ox_inventory.lua sets client.export = 'nayzeee-streamer.useItem'
        DebugPrint('ox_inventory uses client.export for', item)
        return true
    end,
    GetItemLabel = function(item)
        local ok, data = call('ox_inventory', 'Items', item)
        return ok and type(data) == 'table' and data.label or nil
    end,
    HasItemDefinition = function(item)
        if not started('ox_inventory') then return nil end
        local ok, data = call('ox_inventory', 'Items', item)
        if not ok then return nil end
        return type(data) == 'table'
    end,
}

---------------------------------------------------------------------------------------------------
-- Framework items: ESX xPlayer methods / QBCore Player.Functions

local function esxCount(xPlayer, item)
    local ok, data = pcall(xPlayer.getInventoryItem, item)
    if not ok or type(data) ~= 'table' then return 0 end
    return tonumber(data.count or data.amount) or 0
end

local function qbCount(player, item)
    local fns = player.Functions or {}
    if fns.GetItemsByName then
        local ok, list = pcall(fns.GetItemsByName, item)
        if ok and type(list) == 'table' then
            local total = 0
            for _, slot in pairs(list) do
                total = total + (tonumber(slot.amount or slot.count) or 0)
            end
            return total
        end
    end
    if fns.GetItemByName then
        local ok, slot = pcall(fns.GetItemByName, item)
        if ok and type(slot) == 'table' then return tonumber(slot.amount or slot.count) or 0 end
    end
    return 0
end

local frameworkAdapter = {
    GetItemCount = function(src, item)
        local player = Bridge.GetPlayerObject(src)
        if not player then return 0 end
        if Bridge.Framework == 'esx' then return esxCount(player, item) end
        return qbCount(player, item)
    end,
    AddItem = function(src, item, count, meta)
        local player = Bridge.GetPlayerObject(src)
        if not player then return false end
        if Bridge.Framework == 'esx' then
            if player.canCarryItem then
                local okCarry, can = pcall(player.canCarryItem, item, count)
                if okCarry and can == false then return false end
            end
            local before = esxCount(player, item)
            local ok = pcall(player.addInventoryItem, item, count, meta)
            return ok and esxCount(player, item) >= before + count
        end
        if not (player.Functions and player.Functions.AddItem) then return false end
        local ok, added = pcall(player.Functions.AddItem, item, count, false, meta or {})
        if ok and added then itemBox(src, item, 'add', count) return true end
        return false
    end,
    RemoveItem = function(src, item, count)
        local player = Bridge.GetPlayerObject(src)
        if not player then return false end
        if Bridge.Framework == 'esx' then
            local before = esxCount(player, item)
            if before < count then return false end
            local ok = pcall(player.removeInventoryItem, item, count)
            return ok and esxCount(player, item) <= before - count
        end
        if not (player.Functions and player.Functions.RemoveItem) then return false end
        local ok, removed = pcall(player.Functions.RemoveItem, item, count)
        if ok and removed then itemBox(src, item, 'remove', count) return true end
        return false
    end,
    CanCarry = function(src, item, count)
        local player = Bridge.GetPlayerObject(src)
        if not player then return false end
        if Bridge.Framework == 'esx' then
            if not player.canCarryItem then return true end
            local ok, can = pcall(player.canCarryItem, item, count)
            return not ok or can ~= false
        end
        return true
    end,
    RegisterUsableItem = frameworkUsable,
    GetItemLabel = function(item)
        if Bridge.Framework == 'esx' then
            local core = Bridge.GetCore()
            if core and type(core.Items) == 'table' and core.Items[item] then return core.Items[item].label end
            return nil
        end
        local items = sharedItems()
        return items and items[item] and items[item].label or nil
    end,
    HasItemDefinition = function(item)
        if Bridge.Framework == 'esx' then
            local core = Bridge.GetCore()
            if core and type(core.Items) == 'table' and next(core.Items) then return core.Items[item] ~= nil end
            return nil
        end
        local items = sharedItems()
        if not items then return nil end
        return items[item] ~= nil
    end,
}

---------------------------------------------------------------------------------------------------
-- qb-inventory 2.x (falls back to Player.Functions when an export is missing)

local qbAdapter = {
    GetItemCount = function(src, item)
        local ok, count = call('qb-inventory', 'GetItemCount', src, item)
        if ok and tonumber(count) then return tonumber(count) end
        return frameworkAdapter.GetItemCount(src, item)
    end,
    AddItem = function(src, item, count, meta)
        local ok, added = call('qb-inventory', 'AddItem', src, item, count, false, meta or {}, REASON)
        if not ok then return frameworkAdapter.AddItem(src, item, count, meta) end
        if added then itemBox(src, item, 'add', count) return true end
        return false
    end,
    RemoveItem = function(src, item, count)
        local ok, removed = call('qb-inventory', 'RemoveItem', src, item, count, false, REASON)
        if not ok then return frameworkAdapter.RemoveItem(src, item, count) end
        if removed then itemBox(src, item, 'remove', count) return true end
        return false
    end,
    CanCarry = function(src, item, count)
        local ok, can = call('qb-inventory', 'CanAddItem', src, item, count)
        if not ok then return true end
        return can ~= false
    end,
    RegisterUsableItem = frameworkUsable,
    GetItemLabel = frameworkAdapter.GetItemLabel,
    HasItemDefinition = frameworkAdapter.HasItemDefinition,
}

---------------------------------------------------------------------------------------------------
-- custom (bridge/inventory/custom.lua)

local warned = {}

local function custom(fnName, fallback, ...)
    local impl = Bridge.CustomInventory and Bridge.CustomInventory[fnName]
    if type(impl) ~= 'function' then
        if not warned[fnName] then
            warned[fnName] = true
            Utils.Print('warn', L('console.custom_inventory', fnName))
        end
        return fallback
    end
    local ok, result = pcall(impl, ...)
    if not ok then
        Utils.Print('error', ('custom inventory %s failed: %s'):format(fnName, result))
        return fallback
    end
    return result
end

local customAdapter = {
    GetItemCount = function(src, item)
        return tonumber(custom('GetItemCount', 0, src, item)) or 0
    end,
    AddItem = function(src, item, count, meta)
        return custom('AddItem', false, src, item, count, meta) == true
    end,
    RemoveItem = function(src, item, count)
        return custom('RemoveItem', false, src, item, count) == true
    end,
    CanCarry = function(src, item, count)
        local impl = Bridge.CustomInventory and Bridge.CustomInventory.CanCarry
        if type(impl) ~= 'function' then return true end
        return custom('CanCarry', true, src, item, count) ~= false
    end,
    RegisterUsableItem = function(item, fn)
        local impl = Bridge.CustomInventory and Bridge.CustomInventory.RegisterUsableItem
        if type(impl) ~= 'function' then return frameworkUsable(item, fn) end
        return custom('RegisterUsableItem', false, item, fn) ~= false
    end,
    GetItemLabel = function(item)
        local impl = Bridge.CustomInventory and Bridge.CustomInventory.GetItemLabel
        if type(impl) ~= 'function' then return nil end
        local label = custom('GetItemLabel', nil, item)
        return type(label) == 'string' and label or nil
    end,
    HasItemDefinition = function(item)
        local impl = Bridge.CustomInventory and Bridge.CustomInventory.HasItemDefinition
        if type(impl) ~= 'function' then return nil end
        local exists = custom('HasItemDefinition', nil, item)
        if exists == nil then return nil end
        return exists == true
    end,
}

---------------------------------------------------------------------------------------------------
-- Detection

local adapters = {
    ox_inventory = oxAdapter,
    ['qb-inventory'] = qbAdapter,
    framework = frameworkAdapter,
    custom = customAdapter,
}

local function detectInventory()
    local wanted = Config.Inventory
    if wanted == 'ox' then wanted = 'ox_inventory' end
    if wanted == 'qb' or wanted == 'qb_inventory' then wanted = 'qb-inventory' end
    if wanted == 'esx' then wanted = 'framework' end
    if adapters[wanted] then return wanted end

    if present('ox_inventory') or Bridge.Framework == 'qbox' then return 'ox_inventory' end
    if Bridge.Framework == 'qbcore' and present('qb-inventory') then return 'qb-inventory' end
    return 'framework'
end

local name = detectInventory()
local adapter = adapters[name]

Bridge.InventoryName = name
Bridge.Inventory = {
    Name = name,
    GetItemCount = adapter.GetItemCount,
    AddItem = adapter.AddItem,
    RemoveItem = adapter.RemoveItem,
    CanCarry = adapter.CanCarry,
    RegisterUsableItem = adapter.RegisterUsableItem,
    GetItemLabel = adapter.GetItemLabel,
    HasItemDefinition = adapter.HasItemDefinition,
}

-- Warn about items that are missing from the inventory's item list.
CreateThread(function()
    Wait(3000)
    DebugPrint(L('console.inventory', name))
    local where = name
    if name == 'framework' then
        where = Bridge.Framework == 'esx' and 'the ESX items table' or 'qb-core/shared/items.lua'
    elseif name == 'ox_inventory' then
        where = 'ox_inventory/data/items.lua'
    elseif name == 'qb-inventory' then
        where = 'qb-core/shared/items.lua'
    end
    for _, item in ipairs(Utils.AllItems()) do
        if adapter.HasItemDefinition(item) == false then
            Utils.Print('warn', L('console.missing_item', item, where))
        end
    end
end)
