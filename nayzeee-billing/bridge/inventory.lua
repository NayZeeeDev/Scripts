--[[
    NAYZEEE BILLING - Inventory bridge (server)
    Editable. ox_inventory / qs-inventory / ps-inventory / qb-inventory / framework default.
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

function Inventory.HasMetadata()
    return Inventory.Name() ~= 'framework' or Shared.GetFramework() ~= 'esx'
end

function Inventory.ImagePath()
    local inv = Inventory.Name()
    if inv == 'ox_inventory' then return 'nui://ox_inventory/web/images/%s.png' end
    if inv == 'framework' then return 'nui://ox_inventory/web/images/%s.png' end
    return ('nui://%s/html/images/%%s.png'):format(inv)
end

function Inventory.AddItem(source, item, count, metadata)
    local inv = Inventory.Name()
    local ok, result = pcall(function()
        if inv == 'ox_inventory' then
            if not exports.ox_inventory:CanCarryItem(source, item, count, metadata) then return false end
            return exports.ox_inventory:AddItem(source, item, count, metadata)
        elseif inv == 'qs-inventory' then
            return exports['qs-inventory']:AddItem(source, item, count, nil, metadata)
        else
            local p = Framework.GetPlayer(source)
            if p and p.Functions and p.Functions.AddItem then
                local added = p.Functions.AddItem(item, count, nil, metadata)
                if added then TriggerClientEvent('inventory:client:ItemBox', source, item, 'add') end
                return added
            elseif p and p.addInventoryItem then
                p.addInventoryItem(item, count)
                return true
            end
        end
        return false
    end)
    return ok and result and true or false
end

-- Removes one item carrying this reference (ox_inventory metadata match). Best effort elsewhere.
function Inventory.RemoveByReference(source, item, reference)
    local inv = Inventory.Name()
    pcall(function()
        if inv == 'ox_inventory' then
            exports.ox_inventory:RemoveItem(source, item, 1, { reference = reference })
        end
    end)
end

function Inventory.HasReference(source, item, reference)
    if Inventory.Name() ~= 'ox_inventory' then return false end
    local ok, count = pcall(function()
        return exports.ox_inventory:Search(source, 'count', item, { reference = reference })
    end)
    return ok and (tonumber(count) or 0) > 0
end
