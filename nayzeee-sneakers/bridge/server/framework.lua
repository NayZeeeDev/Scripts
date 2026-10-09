Bridge = {}

local fw = Config.Framework
if fw == 'auto' then
    if GetResourceState('qbx_core') == 'started' then fw = 'qbx'
    elseif GetResourceState('qb-core') == 'started' then fw = 'qb'
    elseif GetResourceState('es_extended') == 'started' then fw = 'esx'
    else fw = 'none' end
end
Bridge.Framework = fw

local QBCore, ESX
if fw == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif fw == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

--- QB-style player object (qb and qbx), used by the qb inventory bridge
function Bridge.GetQBPlayer(src)
    if fw == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if fw == 'qb' then return QBCore.Functions.GetPlayer(src) end
end

function Bridge.QBSharedItem(name)
    if fw == 'qbx' then return exports.qbx_core:GetItems()[name] end
    if fw == 'qb' then return QBCore.Shared.Items[name] end
end

--- Stable character id: citizenid (qb/qbx), identifier (esx), else license
function Bridge.GetIdentifier(src)
    if fw == 'qbx' or fw == 'qb' then
        local p = Bridge.GetQBPlayer(src)
        return p and p.PlayerData.citizenid
    elseif fw == 'esx' then
        local p = ESX.GetPlayerFromId(src)
        return p and p.identifier
    end
    return GetPlayerIdentifierByType(src, 'license')
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.AdminAce) then return true end
    if fw == 'qb' then return QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god') end
    if fw == 'esx' then
        local p = ESX.GetPlayerFromId(src)
        local g = p and p.getGroup()
        return g == 'admin' or g == 'superadmin'
    end
    return false
end

--- Register a usable item for frameworks whose inventory routes use through them (qb-inventory).
--- ox_inventory items use the export in install/ox_items.lua instead.
function Bridge.RegisterUsable(name, cb)
    if fw == 'qb' then
        QBCore.Functions.CreateUseableItem(name, function(source, item)
            cb(source, { name = item.name, slot = item.slot, metadata = item.info or {} })
        end)
    elseif fw == 'qbx' then
        exports.qbx_core:CreateUseableItem(name, function(source, item)
            cb(source, { name = item.name, slot = item.slot, metadata = item.metadata or item.info or {} })
        end)
    elseif fw == 'esx' then
        ESX.RegisterUsableItem(name, function(source, _, item)
            cb(source, { name = name, slot = item and item.slot, metadata = item and (item.metadata or item.info) or {} })
        end)
    end
end

--- account: 'cash' | 'bank'
local function esxAccount(account) return account == 'cash' and 'money' or account end

function Bridge.GetMoney(src, account)
    if fw == 'qbx' or fw == 'qb' then
        local p = Bridge.GetQBPlayer(src)
        return p and p.PlayerData.money[account] or 0
    elseif fw == 'esx' then
        local p = ESX.GetPlayerFromId(src)
        local a = p and p.getAccount(esxAccount(account))
        return a and a.money or 0
    end
    return 0
end

--- Takes money. Returns true only if the player had enough and it was taken.
function Bridge.RemoveMoney(src, account, amount, reason)
    if amount <= 0 then return true end
    if Bridge.GetMoney(src, account) < amount then return false end
    if fw == 'qbx' or fw == 'qb' then
        local p = Bridge.GetQBPlayer(src)
        return p and p.Functions.RemoveMoney(account, amount, reason) and true or false
    elseif fw == 'esx' then
        local p = ESX.GetPlayerFromId(src)
        if not p then return false end
        p.removeAccountMoney(esxAccount(account), amount, reason)
        return true
    end
    return false
end

function Bridge.AddMoney(src, account, amount, reason)
    if amount <= 0 then return end
    if fw == 'qbx' or fw == 'qb' then
        local p = Bridge.GetQBPlayer(src)
        if p then p.Functions.AddMoney(account, amount, reason) end
    elseif fw == 'esx' then
        local p = ESX.GetPlayerFromId(src)
        if p then p.addAccountMoney(esxAccount(account), amount, reason) end
    end
end

function Bridge.GetName(src)
    if fw == 'qbx' or fw == 'qb' then
        local p = Bridge.GetQBPlayer(src)
        local c = p and p.PlayerData.charinfo
        if c then return ('%s %s'):format(c.firstname or '', c.lastname or '') end
    elseif fw == 'esx' then
        local p = ESX.GetPlayerFromId(src)
        if p and p.getName then return p.getName() end
    end
    return GetPlayerName(src) or 'Unknown'
end

--- job name, on duty
function Bridge.GetJob(src)
    if fw == 'qbx' or fw == 'qb' then
        local p = Bridge.GetQBPlayer(src)
        local j = p and p.PlayerData.job
        return j and j.name, j and j.onduty
    elseif fw == 'esx' then
        local p = ESX.GetPlayerFromId(src)
        return p and p.job and p.job.name, true
    end
    return nil, false
end

function Bridge.Notify(src, text, kind)
    TriggerClientEvent('nayzeee-sneakers:notify', src, text, kind or 'inform')
end

print(('^5[nayzeee-sneakers]^7 framework: %s'):format(fw))
