-- Server inventory bridge: ox_inventory, qb-inventory (and forks), qs-inventory, framework default
-- Wigs carry metadata (tier, style, condition...). The framework default inventory
-- (plain ESX) has no metadata, so wigs there are treated as generic Common wigs.

Inv = {}

local INV = Config.Inventory
if INV == 'auto' then
    if GetResourceState('ox_inventory') == 'started' then INV = 'ox_inventory'
    elseif GetResourceState('qs-inventory') == 'started' then INV = 'qs-inventory'
    elseif Bridge.Name == 'qb' or Bridge.Name == 'qbx' then INV = 'qb-inventory'
    else INV = 'framework' end
end
Inv.Name = INV
Inv.HasMeta = INV ~= 'framework'

local ox = INV == 'ox_inventory' and exports.ox_inventory or nil
local qs = INV == 'qs-inventory' and exports['qs-inventory'] or nil

local function qbPlayer(src) return Bridge.GetPlayer(src) end

function Inv.CanCarry(src, item, count, meta)
    count = count or 1
    if ox then return ox:CanCarryItem(src, item, count, meta) == true end
    if qs then
        local ok, res = pcall(function() return qs:CanCarryItem(src, item, count) end)
        return not ok or res ~= false
    end
    if INV == 'qb-inventory' then
        if GetResourceState('qb-inventory') == 'started' then
            local ok, res = pcall(function() return exports['qb-inventory']:CanAddItem(src, item, count) end)
            if ok and res ~= nil then return res ~= false end
        end
        return true
    end
    local p = Bridge.GetPlayer(src)
    if p and p.canCarryItem then return p.canCarryItem(item, count) end
    return true
end

function Inv.Add(src, item, count, meta)
    count = count or 1
    if ox then return (ox:AddItem(src, item, count, meta)) == true end
    if qs then return qs:AddItem(src, item, count, nil, meta) ~= false end
    if INV == 'qb-inventory' then
        local p = qbPlayer(src)
        if not p then return false end
        local ok = p.Functions.AddItem(item, count, nil, meta)
        if ok and GetResourceState('qb-core') == 'started' then
            local Core = exports['qb-core']:GetCoreObject()
            local def = Core.Shared.Items[item]
            if def then TriggerClientEvent('inventory:client:ItemBox', src, def, 'add', count) end
        end
        return ok ~= false
    end
    local p = Bridge.GetPlayer(src)
    if not p then return false end
    p.addInventoryItem(item, count)
    return true
end

function Inv.Remove(src, item, count, slot)
    count = count or 1
    if ox then return (ox:RemoveItem(src, item, count, nil, slot)) == true end
    if qs then return qs:RemoveItem(src, item, count, slot) ~= false end
    if INV == 'qb-inventory' then
        local p = qbPlayer(src)
        if not p then return false end
        local ok = p.Functions.RemoveItem(item, count, slot)
        if ok and GetResourceState('qb-core') == 'started' then
            local Core = exports['qb-core']:GetCoreObject()
            local def = Core.Shared.Items[item]
            if def then TriggerClientEvent('inventory:client:ItemBox', src, def, 'remove', count) end
        end
        return ok ~= false
    end
    local p = Bridge.GetPlayer(src)
    if not p then return false end
    local it = p.getInventoryItem(item)
    if not it or (it.count or 0) < count then return false end
    p.removeInventoryItem(item, count)
    return true
end

function Inv.Count(src, item)
    if ox then return ox:GetItemCount(src, item) or 0 end
    if qs then
        local ok, n = pcall(function() return qs:GetItemTotalAmount(src, item) end)
        return ok and (n or 0) or 0
    end
    if INV == 'qb-inventory' then
        local p = qbPlayer(src)
        if not p then return 0 end
        local n = 0
        for _, it in pairs(p.Functions.GetItemsByName(item) or {}) do n = n + (it.amount or 0) end
        return n
    end
    local p = Bridge.GetPlayer(src)
    local it = p and p.getInventoryItem(item)
    return it and it.count or 0
end

-- Returns every stack of an item as { slot = n, count = n, meta = table|nil }
function Inv.Stacks(src, item)
    local out = {}
    if ox then
        for _, it in pairs(ox:Search(src, 'slots', item) or {}) do
            out[#out + 1] = { slot = it.slot, count = it.count, meta = it.metadata }
        end
    elseif qs then
        for _, it in pairs(qs:GetInventory(src) or {}) do
            if it.name == item then out[#out + 1] = { slot = it.slot, count = it.amount, meta = it.info } end
        end
    elseif INV == 'qb-inventory' then
        local p = qbPlayer(src)
        for _, it in pairs(p and p.Functions.GetItemsByName(item) or {}) do
            out[#out + 1] = { slot = it.slot, count = it.amount, meta = it.info }
        end
    else
        local n = Inv.Count(src, item)
        for i = 1, n do out[#out + 1] = { slot = nil, count = 1, meta = nil, index = i } end
    end
    return out
end

function Inv.SetMeta(src, slot, meta)
    if ox then ox:SetMetadata(src, slot, meta) return true end
    if qs then
        local ok = pcall(function() qs:SetItemMetadata(src, slot, meta) end)
        return ok
    end
    if INV == 'qb-inventory' then
        local p = qbPlayer(src)
        if not p then return false end
        local items = p.PlayerData.items
        if not items[slot] then return false end
        items[slot].info = meta
        p.Functions.SetInventory(items, true)
        return true
    end
    return false
end
