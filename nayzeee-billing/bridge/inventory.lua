--[[
    NAYZEEE BILLING - Inventory Bridge (server)
    ox_inventory / qb-inventory / qs-inventory / ps-inventory / ESX default
]]

Inventory = {}

local function detect()
    for _, name in ipairs({ 'ox_inventory', 'qs-inventory', 'ps-inventory', 'qb-inventory' }) do
        if GetResourceState(name) == 'started' then return name end
    end
    return 'framework'
end

function Inventory.Name()
    Inventory.name = Inventory.name or detect()
    return Inventory.name
end

function Inventory.ImagePath()
    if Config.ImagePath and Config.ImagePath ~= 'auto' then return Config.ImagePath end
    local inv = Inventory.Name()
    if inv == 'ox_inventory' then return 'nui://ox_inventory/web/images/%s.png' end
    if inv == 'qs-inventory' then return 'nui://qs-inventory/html/images/%s.png' end
    if inv == 'ps-inventory' then return 'nui://ps-inventory/html/images/%s.png' end
    if inv == 'qb-inventory' then return 'nui://qb-inventory/html/images/%s.png' end
    return 'nui://ox_inventory/web/images/%s.png'
end

function Inventory.AddItem(source, item, count, metadata)
    local inv = Inventory.Name()
    local ok, result = pcall(function()
        if inv == 'ox_inventory' then
            return exports.ox_inventory:AddItem(source, item, count, metadata)
        elseif inv == 'qs-inventory' then
            return exports['qs-inventory']:AddItem(source, item, count, nil, metadata)
        elseif inv == 'qb-inventory' or inv == 'ps-inventory' then
            local player = Bridge.GetPlayer(source)
            if player and player.Functions and player.Functions.AddItem then
                return player.Functions.AddItem(item, count, nil, metadata)
            end
            return exports[inv]:AddItem(source, item, count, nil, metadata)
        else
            local player = Bridge.GetPlayer(source)
            if player and player.addInventoryItem then
                player.addInventoryItem(item, count)
                return true
            end
        end
        return false
    end)
    return ok and result
end

-- Does the player hold a receipt for this invoice? (ox_inventory metadata search)
function Inventory.HasReceipt(source, invoiceId)
    if Inventory.Name() ~= 'ox_inventory' then return false end
    local ok, count = pcall(function()
        return exports.ox_inventory:Search(source, 'count', Config.Receipts.ReceiptItemName, { invoiceId = invoiceId })
    end)
    return ok and (tonumber(count) or 0) > 0
end

-- Item list for the product image picker
function Inventory.GetItems()
    local items = {}
    local inv = Inventory.Name()
    local ok = pcall(function()
        if inv == 'ox_inventory' then
            for name, item in pairs(exports.ox_inventory:Items() or {}) do
                items[#items + 1] = { name = name, label = item.label or name }
            end
        elseif Shared.GetFramework() == 'qbcore' then
            local core = exports['qb-core']:GetCoreObject()
            for name, item in pairs(core.Shared.Items or {}) do
                items[#items + 1] = { name = name, label = item.label or name }
            end
        elseif Shared.GetFramework() == 'esx' then
            for _, row in ipairs(MySQL.query.await('SELECT name, label FROM items') or {}) do
                items[#items + 1] = { name = row.name, label = row.label or row.name }
            end
        end
    end)
    if not ok then return {} end
    table.sort(items, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return items
end
