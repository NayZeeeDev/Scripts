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

function Bridge.Notify(src, text, kind)
    TriggerClientEvent('nayzeee-sneakers:notify', src, text, kind or 'inform')
end

print(('^5[nayzeee-sneakers]^7 framework: %s'):format(fw))
