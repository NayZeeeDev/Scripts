-- Server framework bridge: ESX Legacy, QBCore, Qbox
-- Open source so you can adapt it to a custom framework.

Bridge = {}

local FW, Core = Config.Framework, nil

if FW == 'auto' then
    if GetResourceState('qbx_core') == 'started' then FW = 'qbx'
    elseif GetResourceState('es_extended') == 'started' then FW = 'esx'
    elseif GetResourceState('qb-core') == 'started' then FW = 'qb'
    else FW = 'none' end
end

if FW == 'esx' then
    Core = exports.es_extended:getSharedObject()
elseif FW == 'qb' then
    Core = exports['qb-core']:GetCoreObject()
end

Bridge.Name = FW
if FW == 'none' then
    print(('^1[%s] No supported framework found (ESX / QBCore / Qbox)^7'):format(GetCurrentResourceName()))
end

local function getPlayer(src)
    if FW == 'esx' then return Core.GetPlayerFromId(src) end
    if FW == 'qb' then return Core.Functions.GetPlayer(src) end
    if FW == 'qbx' then return exports.qbx_core:GetPlayer(src) end
end
Bridge.GetPlayer = getPlayer

function Bridge.GetIdentifier(src)
    local p = getPlayer(src)
    if not p then return nil end
    if FW == 'esx' then return p.identifier end
    return p.PlayerData.citizenid
end

function Bridge.GetCharName(src)
    local p = getPlayer(src)
    if not p then return GetPlayerName(src) or ('#' .. src) end
    if FW == 'esx' then
        local n = p.getName and p.getName()
        if n and n ~= '' then return n end
        return GetPlayerName(src)
    end
    local ci = p.PlayerData.charinfo
    if ci and ci.firstname then return ('%s %s'):format(ci.firstname, ci.lastname or '') end
    return GetPlayerName(src)
end

-- returns jobName, onDuty
function Bridge.GetJob(src)
    local p = getPlayer(src)
    if not p then return nil, false end
    if FW == 'esx' then
        local j = p.job or {}
        local duty = j.onDuty
        if duty == nil then duty = true end -- older ESX has no duty, treat as on duty
        return j.name, duty
    end
    local j = p.PlayerData.job or {}
    return j.name, j.onduty ~= false
end

local function qbAccount(acc)
    if acc == 'money' or acc == 'cash' or acc == 'black_money' then return 'cash' end
    return acc
end

local function esxAccount(acc)
    if acc == 'cash' then return 'money' end
    return acc
end

function Bridge.GetMoney(src, acc)
    local p = getPlayer(src)
    if not p then return 0 end
    if FW == 'esx' then
        local a = p.getAccount(esxAccount(acc))
        return a and a.money or 0
    end
    return p.PlayerData.money[qbAccount(acc)] or 0
end

function Bridge.AddMoney(src, amount, acc, reason)
    if type(amount) ~= 'number' or amount ~= amount or amount == math.huge or amount == -math.huge then return false end
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if not p then return false end
    if FW == 'esx' then
        p.addAccountMoney(esxAccount(acc), amount, reason)
        return true
    end
    return p.Functions.AddMoney(qbAccount(acc), amount, reason) ~= false
end

function Bridge.RemoveMoney(src, amount, acc, reason)
    if type(amount) ~= 'number' or amount ~= amount or amount == math.huge or amount == -math.huge then return false end
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if not p then return false end
    if Bridge.GetMoney(src, acc) < amount then return false end
    if FW == 'esx' then
        p.removeAccountMoney(esxAccount(acc), amount, reason)
        return true
    end
    return p.Functions.RemoveMoney(qbAccount(acc), amount, reason) ~= false
end

function Bridge.RegisterUsable(item, cb)
    if FW == 'esx' then
        Core.RegisterUsableItem(item, function(src, a, b) cb(src, type(a) == 'table' and a or b) end)
    elseif FW == 'qb' then
        Core.Functions.CreateUseableItem(item, function(src, data) cb(src, data) end)
    elseif FW == 'qbx' then
        exports.qbx_core:CreateUseableItem(item, function(src, data) cb(src, data) end)
    end
end

function Bridge.OnLoaded(cb)
    if FW == 'esx' then
        AddEventHandler('esx:playerLoaded', function(src) cb(src) end)
    else
        AddEventHandler('QBCore:Server:PlayerLoaded', function(p)
            local src = type(p) == 'table' and p.PlayerData and p.PlayerData.source or source
            cb(src)
        end)
    end
end

function Bridge.OnUnloaded(cb)
    if FW == 'esx' then
        AddEventHandler('esx:playerLogout', function(src) cb(src) end)
    else
        AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) cb(src) end)
    end
    AddEventHandler('playerDropped', function() cb(source) end)
end

function Bridge.IsLoaded(src)
    return getPlayer(src) ~= nil
end
