Bridge = {}

local function started(res) return GetResourceState(res) == 'started' end

local fw = Config.Framework
if fw == 'auto' then
    fw = started('qbx_core') and 'qbx'
        or started('es_extended') and 'esx'
        or started('qb-core') and 'qb'
        or 'standalone'
end
Bridge.framework = fw

local ESX, QB
if fw == 'esx' then
    ESX = exports.es_extended:getSharedObject()
elseif fw == 'qb' then
    QB = exports['qb-core']:GetCoreObject()
end

local oxInv = started('ox_inventory')

local function player(src)
    if fw == 'esx' then return ESX.GetPlayerFromId(src) end
    if fw == 'qb' then return QB.Functions.GetPlayer(src) end
    if fw == 'qbx' then return exports.qbx_core:GetPlayer(src) end
end

function Bridge.GetIdentifier(src)
    local p = player(src)
    if fw == 'esx' then return p and p.identifier end
    if fw == 'qb' or fw == 'qbx' then return p and p.PlayerData.citizenid end
    return GetPlayerIdentifierByType(src, 'license')
end

function Bridge.GetName(src)
    local p = player(src)
    if fw == 'esx' and p then return p.getName() end
    if (fw == 'qb' or fw == 'qbx') and p then
        local c = p.PlayerData.charinfo
        return ('%s %s'):format(c.firstname, c.lastname)
    end
    return GetPlayerName(src)
end

-- ── money ───────────────────────────────────────────────────────

function Bridge.GetMoney(src, account)
    local p = player(src)
    if not p then return 0 end
    if fw == 'esx' then
        local acc = p.getAccount(account == 'cash' and 'money' or account)
        return acc and acc.money or 0
    end
    if fw == 'qb' or fw == 'qbx' then return p.PlayerData.money[account] or 0 end
    return 0
end

function Bridge.RemoveMoney(src, account, amount, reason)
    local p = player(src)
    if not p or Bridge.GetMoney(src, account) < amount then return false end
    if fw == 'esx' then
        p.removeAccountMoney(account == 'cash' and 'money' or account, amount, reason)
        return true
    end
    if fw == 'qb' or fw == 'qbx' then return p.Functions.RemoveMoney(account, amount, reason) ~= false end
    return false
end

function Bridge.AddMoney(src, account, amount, reason)
    local p = player(src)
    if not p then return false end
    if fw == 'esx' then
        p.addAccountMoney(account == 'cash' and 'money' or account, amount, reason)
        return true
    end
    if fw == 'qb' or fw == 'qbx' then return p.Functions.AddMoney(account, amount, reason) ~= false end
    return false
end

-- ── items ───────────────────────────────────────────────────────

function Bridge.HasItem(src, item)
    if oxInv then return (exports.ox_inventory:Search(src, 'count', item) or 0) > 0 end
    local p = player(src)
    if not p then return false end
    if fw == 'esx' then
        local i = p.getInventoryItem(item)
        return i ~= nil and i.count > 0
    end
    if fw == 'qb' then return p.Functions.GetItemByName(item) ~= nil end
    return fw == 'standalone'
end

function Bridge.RemoveItem(src, item)
    if oxInv then return exports.ox_inventory:RemoveItem(src, item, 1) == true end
    local p = player(src)
    if not p then return false end
    if fw == 'esx' then p.removeInventoryItem(item, 1) return true end
    if fw == 'qb' then return p.Functions.RemoveItem(item, 1) ~= false end
    return fw == 'standalone'
end

function Bridge.AddItem(src, item)
    if oxInv then return exports.ox_inventory:AddItem(src, item, 1) == true end
    local p = player(src)
    if not p then return false end
    if fw == 'esx' then p.addInventoryItem(item, 1) return true end
    if fw == 'qb' then return p.Functions.AddItem(item, 1) ~= false end
    return fw == 'standalone'
end

function Bridge.RegisterUsable(item, cb)
    if fw == 'esx' then
        ESX.RegisterUsableItem(item, function(src) cb(src) end)
    elseif fw == 'qb' then
        QB.Functions.CreateUseableItem(item, function(src) cb(src) end)
    elseif fw == 'qbx' then
        exports.qbx_core:CreateUseableItem(item, function(src) cb(src) end)
    end
end

if fw == 'standalone' then Config.Live.enabled = false end
