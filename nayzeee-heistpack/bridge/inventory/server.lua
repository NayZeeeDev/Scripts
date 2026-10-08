--[[ Inventory bridge (server). Falls back to framework inventory functions. ]]

Inv = {}

local function detect()
    if Config.Inventory ~= 'auto' then return Config.Inventory end
    if GetResourceState('ox_inventory') == 'started' then return 'ox' end
    if GetResourceState('qs-inventory') == 'started' then return 'qs' end
    if GetResourceState('codem-inventory') == 'started' then return 'codem' end
    if GetResourceState('qb-inventory') == 'started' or GetResourceState('ps-inventory') == 'started'
        or GetResourceState('lj-inventory') == 'started' then return 'qb' end
    return 'framework'
end

Inv.name = detect()

local qbInv = (GetResourceState('ps-inventory') == 'started' and 'ps-inventory')
    or (GetResourceState('lj-inventory') == 'started' and 'lj-inventory')
    or 'qb-inventory'

function Inv.count(src, name)
    if Inv.name == 'ox' then
        return exports.ox_inventory:GetItemCount(src, name) or 0
    elseif Inv.name == 'qs' then
        return exports['qs-inventory']:GetItemTotalAmount(src, name) or 0
    elseif Inv.name == 'codem' then
        return exports['codem-inventory']:GetItemsTotalAmount(src, name) or 0
    end
    local p = FW.getPlayer(src)
    if not p then return 0 end
    if FW.name == 'esx' then
        local it = p.getInventoryItem(name)
        return it and (it.count or it.amount) or 0
    end
    local total = 0
    for _, it in pairs(p.PlayerData.items or {}) do
        if it and it.name == name then total = total + (it.amount or it.count or 0) end
    end
    return total
end

function Inv.has(src, name, count)
    return Inv.count(src, name) >= (count or 1)
end

function Inv.remove(src, name, count, metadata)
    count = count or 1
    if Inv.count(src, name) < count then return false end
    if Inv.name == 'ox' then
        return exports.ox_inventory:RemoveItem(src, name, count, metadata) and true or false
    elseif Inv.name == 'qs' then
        return exports['qs-inventory']:RemoveItem(src, name, count)
    elseif Inv.name == 'codem' then
        return exports['codem-inventory']:RemoveItem(src, name, count)
    elseif Inv.name == 'qb' then
        local ok = exports[qbInv]:RemoveItem(src, name, count, false, 'nayzeee-heistpack')
        if ok ~= false then TriggerClientEvent('qb-inventory:client:ItemBox', src, Inv.qbItem(name), 'remove', count) end
        return ok ~= false
    end
    local p = FW.getPlayer(src)
    if not p then return false end
    if FW.name == 'esx' then p.removeInventoryItem(name, count) return true end
    return p.Functions.RemoveItem(name, count)
end

function Inv.canCarry(src, name, count)
    if Inv.name == 'ox' then
        return exports.ox_inventory:CanCarryItem(src, name, count or 1)
    elseif Inv.name == 'qb' then
        local ok, can = pcall(function() return exports[qbInv]:CanAddItem(src, name, count or 1) end)
        return not ok or can ~= false
    elseif FW.name == 'esx' and Inv.name == 'framework' then
        local p = FW.getPlayer(src)
        return p and p.canCarryItem(name, count or 1) or false
    end
    return true
end

function Inv.add(src, name, count, metadata)
    count = count or 1
    if count <= 0 then return false end
    if Inv.name == 'ox' then
        local ok = exports.ox_inventory:AddItem(src, name, count, metadata)
        return ok and true or false
    elseif Inv.name == 'qs' then
        return exports['qs-inventory']:AddItem(src, name, count, nil, metadata)
    elseif Inv.name == 'codem' then
        return exports['codem-inventory']:AddItem(src, name, count, nil, metadata)
    elseif Inv.name == 'qb' then
        local ok = exports[qbInv]:AddItem(src, name, count, false, metadata, 'nayzeee-heistpack')
        if ok ~= false then TriggerClientEvent('qb-inventory:client:ItemBox', src, Inv.qbItem(name), 'add', count) end
        return ok ~= false
    end
    local p = FW.getPlayer(src)
    if not p then return false end
    if FW.name == 'esx' then p.addInventoryItem(name, count, metadata) return true end
    return p.Functions.AddItem(name, count, false, metadata)
end

function Inv.qbItem(name)
    if FW.name == 'qbx' then return exports.ox_inventory:Items(name) end
    local QB = exports['qb-core']:GetCoreObject()
    return QB.Shared.Items[name] or { name = name, label = name }
end

local labelCache = {}
function Inv.label(name)
    if labelCache[name] then return labelCache[name] end
    local label = name
    if Inv.name == 'ox' then
        local it = exports.ox_inventory:Items(name)
        label = it and it.label or name
    elseif FW.name == 'qb' then
        local ok, it = pcall(Inv.qbItem, name)
        label = ok and it and it.label or name
    end
    labelCache[name] = label
    return label
end

--- Pays `amount` according to Config.Money (or an explicit account)
function Inv.payMoney(src, amount, account, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local mode = account or Config.Money.type
    if mode == 'item' then
        return Inv.add(src, Config.Money.item, amount)
    elseif mode == 'markedbills' then
        return Inv.add(src, Config.Money.markedbillsItem, 1, { worth = amount })
    end
    return FW.addMoney(src, mode, amount, reason or 'heist')
end

Utils.debug('inventory:', Inv.name)
