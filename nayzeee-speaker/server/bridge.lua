-- Framework / inventory bridge (server). Edit freely.
Bridge = {}

local FW, Core = nil, nil
local function detect()
    local want = Config.Framework
    if (want == 'auto' or want == 'esx') and GetResourceState('es_extended') == 'started' then
        FW, Core = 'esx', exports['es_extended']:getSharedObject()
    elseif (want == 'auto' or want == 'qbox') and GetResourceState('qbx_core') == 'started' then
        FW, Core = 'qbox', nil
    elseif (want == 'auto' or want == 'qbcore') and GetResourceState('qb-core') == 'started' then
        FW, Core = 'qb', exports['qb-core']:GetCoreObject()
    else
        FW = 'standalone'
    end
end
detect()

local useOx = Config.Inventory == 'ox_inventory'
    or (Config.Inventory == 'auto' and GetResourceState('ox_inventory') == 'started')

Bridge.Framework = FW

local function qbPlayer(src)
    if FW == 'qbox' then return exports.qbx_core:GetPlayer(src) end
    return Core.Functions.GetPlayer(src)
end

function Bridge.GetIdentifier(src)
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if x then return x.identifier end
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        if p then return p.PlayerData.citizenid end
    end
    return GetPlayerIdentifierByType(src, 'license') or ('src:' .. src)
end

function Bridge.GetName(src)
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if x then return x.getName() end
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        if p then return ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname) end
    end
    return GetPlayerName(src)
end

function Bridge.HasItem(src, item)
    if useOx then return (exports.ox_inventory:Search(src, 'count', item) or 0) > 0 end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        local it = x and x.getInventoryItem(item)
        return it and (it.count or 0) > 0
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        return p and p.Functions.GetItemByName(item) ~= nil
    end
    return true
end

-- count is optional (1 when left out)
function Bridge.RemoveItem(src, item, count)
    count = count or 1
    if useOx then return exports.ox_inventory:RemoveItem(src, item, count) end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if not x then return false end
        x.removeInventoryItem(item, count) return true
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        return p and p.Functions.RemoveItem(item, count)
    end
    return true
end

function Bridge.AddItem(src, item, count)
    count = count or 1
    if useOx then return exports.ox_inventory:AddItem(src, item, count) end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if not x then return false end
        x.addInventoryItem(item, count) return true
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        return p and p.Functions.AddItem(item, count)
    end
    return true
end

function Bridge.RegisterUsable(item, cb)
    if FW == 'esx' then
        Core.RegisterUsableItem(item, function(src) cb(src) end)
    elseif FW == 'qbox' then
        exports.qbx_core:CreateUseableItem(item, function(src) cb(src) end)
    elseif FW == 'qb' then
        Core.Functions.CreateUseableItem(item, function(src) cb(src) end)
    end
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.Admin.ace) then return true end
    local group
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        group = x and x.getGroup()
    elseif FW == 'qb' then
        for _, g in ipairs(Config.Admin.groups) do
            if Core.Functions.HasPermission(src, g) then return true end
        end
    end
    if group then
        for _, g in ipairs(Config.Admin.groups) do if g == group then return true end end
    end
    return false
end

-- Vehicle owner check for CarPlay unit removal
function Bridge.OwnsVehicle(src, plate)
    local id = Bridge.GetIdentifier(src)
    plate = plate and plate:gsub('^%s+', ''):gsub('%s+$', '')
    if FW == 'esx' then
        local r = MySQL.scalar.await('SELECT owner FROM owned_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
        return r == id
    elseif FW == 'qb' or FW == 'qbox' then
        local r = MySQL.scalar.await('SELECT citizenid FROM player_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
        return r == id
    end
    return true
end

---------------------------------------------------------------- shop helpers (record shop)
-- How many of an item the player has (0 when none).
function Bridge.CountItem(src, item)
    if useOx then return tonumber(exports.ox_inventory:Search(src, 'count', item)) or 0 end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        local it = x and x.getInventoryItem(item)
        return it and (it.count or it.amount) or 0
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        local n = 0
        for _, it in pairs(p and p.PlayerData.items or {}) do
            if it and it.name == item then n = n + (it.amount or it.count or 0) end
        end
        return n
    end
    return 0
end

-- Counts for a list of items in one go: { [item] = count }, items the player doesn't have are left out.
function Bridge.CountItems(src, items)
    local out = {}
    if #items == 0 then return out end
    if useOx and #items > 1 then
        local ok, res = pcall(function() return exports.ox_inventory:Search(src, 'count', items) end)
        if ok and type(res) == 'table' then
            for _, item in ipairs(items) do
                local n = tonumber(res[item] or res[item:lower()]) or 0
                if n > 0 then out[item] = n end
            end
            return out
        end
    end
    for _, item in ipairs(items) do
        local ok, n = pcall(Bridge.CountItem, src, item)
        if ok and (tonumber(n) or 0) > 0 then out[item] = tonumber(n) end
    end
    return out
end

-- Is the item registered in the inventory at all? (unknown = true, so nothing is hidden by mistake)
function Bridge.ItemExists(item)
    if useOx then
        local ok, data = pcall(function() return exports.ox_inventory:Items(item) end)
        return not ok or data ~= nil
    end
    if FW == 'qb' and Core.Shared and Core.Shared.Items then return Core.Shared.Items[item] ~= nil end
    return true
end

-- Room for `count` more of the item? (inventories that can't tell say yes; AddItem failing is refunded)
function Bridge.CanCarry(src, item, count)
    count = count or 1
    if useOx then
        local ok, res = pcall(function() return exports.ox_inventory:CanCarryItem(src, item, count) end)
        return not ok or res and true or false
    end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if x and x.canCarryItem then return x.canCarryItem(item, count) and true or false end
    elseif FW == 'qb' or FW == 'qbox' then
        if GetResourceState('qb-inventory') == 'started' then
            local ok, res = pcall(function() return exports['qb-inventory']:CanAddItem(src, item, count) end)
            if ok and res ~= nil then return res and true or false end
        end
    end
    return true
end

--[[
    Money. account = 'cash' | 'bank' | 'item' (paid with an inventory item, `moneyItem`, e.g. 'money').
    GetMoney returns nil when the server has no money system for that account (standalone without ox_inventory).
]]
local function esxAccount(account) return account == 'bank' and 'bank' or 'money' end

function Bridge.GetMoney(src, account, moneyItem)
    if account == 'item' then return Bridge.CountItem(src, moneyItem or 'money') end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if not x then return 0 end
        local acc = x.getAccount(esxAccount(account))
        return acc and acc.money or 0
    elseif FW == 'qbox' then
        local ok, n = pcall(function() return exports.qbx_core:GetMoney(src, account) end)
        if ok and tonumber(n) then return tonumber(n) end
        local p = qbPlayer(src)
        return p and p.PlayerData.money and p.PlayerData.money[account] or 0
    elseif FW == 'qb' then
        local p = qbPlayer(src)
        return p and p.Functions.GetMoney(account) or 0
    end
    if useOx and account == 'cash' then return Bridge.CountItem(src, 'money') end
    return nil
end

function Bridge.RemoveMoney(src, account, amount, moneyItem, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local have = Bridge.GetMoney(src, account, moneyItem)
    if not have or have < amount then return false end
    reason = reason or 'nayzeee-speaker'
    if account == 'item' then return Bridge.RemoveItem(src, moneyItem or 'money', amount) and true or false end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if not x then return false end
        x.removeAccountMoney(esxAccount(account), amount, reason)
        return true
    elseif FW == 'qbox' then
        local ok, res = pcall(function() return exports.qbx_core:RemoveMoney(src, account, amount, reason) end)
        if ok then return res ~= false end
        local p = qbPlayer(src)
        return p and p.Functions.RemoveMoney(account, amount, reason) ~= false or false
    elseif FW == 'qb' then
        local p = qbPlayer(src)
        return p and p.Functions.RemoveMoney(account, amount, reason) ~= false or false
    end
    if useOx and account == 'cash' then return exports.ox_inventory:RemoveItem(src, 'money', amount) and true or false end
    return false
end

function Bridge.AddMoney(src, account, amount, moneyItem, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    reason = reason or 'nayzeee-speaker'
    if account == 'item' then return Bridge.AddItem(src, moneyItem or 'money', amount) and true or false end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if not x then return false end
        x.addAccountMoney(esxAccount(account), amount, reason)
        return true
    elseif FW == 'qbox' then
        local ok, res = pcall(function() return exports.qbx_core:AddMoney(src, account, amount, reason) end)
        if ok then return res ~= false end
        local p = qbPlayer(src)
        return p and p.Functions.AddMoney(account, amount, reason) ~= false or false
    elseif FW == 'qb' then
        local p = qbPlayer(src)
        return p and p.Functions.AddMoney(account, amount, reason) ~= false or false
    end
    if useOx and account == 'cash' then return exports.ox_inventory:AddItem(src, 'money', amount) and true or false end
    return false
end

-- ox_inventory: player used the item from the inventory
if useOx then
    exports('useItem', function(event, item, inventory)
        if event == 'usingItem' then
            local src = inventory.id
            local name = item.name
            if Bridge.OnUse and Bridge.OnUse[name] then
                SetTimeout(0, function() Bridge.OnUse[name](src) end)
            end
            return false -- item is only removed when actually placed / installed
        end
    end)
end
Bridge.UsingOx = useOx
Bridge.OnUse = {}
