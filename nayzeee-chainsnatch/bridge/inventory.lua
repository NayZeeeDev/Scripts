-- Server inventory bridge: ox_inventory, qb-inventory (and forks), qs-inventory.
-- Chains are one item with metadata { chain, variant, label, image, ... }. The framework default
-- inventory (plain ESX) has no metadata, so it isn't supported.

Inv = {}

local INV = Config.Inventory
if INV == 'auto' then
    if GetResourceState('ox_inventory') == 'started' then INV = 'ox_inventory'
    elseif GetResourceState('qs-inventory') == 'started' then INV = 'qs-inventory'
    elseif Bridge.Name == 'qb' or Bridge.Name == 'qbx' then INV = 'qb-inventory'
    else INV = 'framework' end
end
Inv.Name = INV

if INV == 'framework' then
    print(('^1[%s] No inventory with item metadata found. Chains need ox_inventory, qb-inventory or qs-inventory.^0'):format(GetCurrentResourceName()))
end

local ox = INV == 'ox_inventory' and exports.ox_inventory or nil
local qs = INV == 'qs-inventory' and exports['qs-inventory'] or nil

local function qbItemBox(src, item, kind, count)
    if GetResourceState('qb-core') ~= 'started' then return end
    local def = exports['qb-core']:GetCoreObject().Shared.Items[item]
    if def then TriggerClientEvent('inventory:client:ItemBox', src, def, kind, count) end
end

function Inv.CanCarry(src, meta)
    local item = Config.Item
    if ox then return ox:CanCarryItem(src, item, 1, meta) == true end
    if qs then
        local ok, res = pcall(function() return qs:CanCarryItem(src, item, 1) end)
        return not ok or res ~= false
    end
    if INV == 'qb-inventory' and GetResourceState('qb-inventory') == 'started' then
        local ok, res = pcall(function() return exports['qb-inventory']:CanAddItem(src, item, 1) end)
        if ok and res ~= nil then return res ~= false end
    end
    return true
end

function Inv.Add(src, meta)
    local item = Config.Item
    if ox then return (ox:AddItem(src, item, 1, meta)) == true end
    if qs then return qs:AddItem(src, item, 1, nil, meta) ~= false end
    if INV == 'qb-inventory' then
        local p = Bridge.GetPlayer(src)
        if not p then return false end
        local ok = p.Functions.AddItem(item, 1, nil, meta)
        if ok then qbItemBox(src, item, 'add', 1) end
        return ok ~= false
    end
    return false
end

--- Take the chain in `slot` out of the player's inventory. Returns its metadata, or nil.
function Inv.TakeSlot(src, slot)
    local item = Config.Item
    slot = tonumber(slot)
    if not slot then return nil end
    if ox then
        local it = ox:GetSlot(src, slot)
        if not it or it.name ~= item then return nil end
        local meta = it.metadata or {}
        if not ox:RemoveItem(src, item, 1, nil, slot) then return nil end
        return meta
    end
    if qs then
        local inv = qs:GetInventory(src) or {}
        local it = inv[slot] or inv[tostring(slot)]
        if not it or it.name ~= item then return nil end
        if qs:RemoveItem(src, item, 1, slot) == false then return nil end
        return it.info or {}
    end
    if INV == 'qb-inventory' then
        local p = Bridge.GetPlayer(src)
        if not p then return nil end
        local it = p.PlayerData.items[slot]
        if not it or it.name ~= item then return nil end
        local meta = it.info or {}
        if not p.Functions.RemoveItem(item, 1, slot) then return nil end
        qbItemBox(src, item, 'remove', 1)
        return meta
    end
    return nil
end

--- Every chain the player carries: { slot, meta }
function Inv.Chains(src)
    local item, out = Config.Item, {}
    if ox then
        for _, it in pairs(ox:Search(src, 'slots', item) or {}) do out[#out + 1] = { slot = it.slot, meta = it.metadata or {} } end
    elseif qs then
        for _, it in pairs(qs:GetInventory(src) or {}) do
            if it.name == item then out[#out + 1] = { slot = it.slot, meta = it.info or {} } end
        end
    elseif INV == 'qb-inventory' then
        local p = Bridge.GetPlayer(src)
        for _, it in pairs(p and p.PlayerData.items or {}) do
            if it.name == item then out[#out + 1] = { slot = it.slot, meta = it.info or {} } end
        end
    end
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return out
end

--- ox_inventory: using the item calls this export (item server = { export = 'nayzeee-chainsnatch.nz_chain' })
function Inv.HookUse(cb)
    if ox then
        exports(Config.Item, function(event, item, inventory, slot)
            if event == 'usingItem' then
                cb(inventory.id, slot)
                return false -- we take the item ourselves
            end
        end)
    end
    -- QBCore / Qbox / ESX usable items (also how qb-inventory and qs-inventory use items)
    Bridge.RegisterUsable(Config.Item, function(src, data)
        if ox then return end
        cb(src, data and data.slot)
    end)
end

--- How many of an item (materials for crafting)
function Inv.Count(src, item)
    if ox then return ox:GetItemCount(src, item) or 0 end
    if qs then
        local ok, n = pcall(function() return qs:GetItemTotalAmount(src, item) end)
        return ok and (n or 0) or 0
    end
    if INV == 'qb-inventory' then
        local p = Bridge.GetPlayer(src)
        local n = 0
        for _, it in pairs(p and p.PlayerData.items or {}) do if it.name == item then n = n + (it.amount or 0) end end
        return n
    end
    return 0
end

function Inv.RemoveItem(src, item, count)
    if ox then return ox:RemoveItem(src, item, count) == true end
    if qs then return qs:RemoveItem(src, item, count) ~= false end
    if INV == 'qb-inventory' then
        local p = Bridge.GetPlayer(src)
        if not p then return false end
        local ok = p.Functions.RemoveItem(item, count)
        if ok then qbItemBox(src, item, 'remove', count) end
        return ok ~= false
    end
    return false
end

--- Change a chain's metadata where it is (repairs). Falls back to taking it out and putting it back.
function Inv.SetMeta(src, slot, meta)
    if ox then
        local it = ox:GetSlot(src, slot)
        if not it or it.name ~= Config.Item then return false end
        ox:SetMetadata(src, slot, meta)
        return true
    end
    if Inv.TakeSlot(src, slot) then return Inv.Add(src, meta) end
    return false
end

--- The chain in a slot without taking it
function Inv.Peek(src, slot)
    slot = tonumber(slot)
    for _, it in ipairs(Inv.Chains(src)) do
        if it.slot == slot then return it.meta end
    end
    return nil
end
