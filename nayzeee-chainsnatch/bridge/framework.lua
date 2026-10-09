-- Server framework bridge: ESX Legacy, QBCore, Qbox, or none.
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

local function getPlayer(src)
    if FW == 'esx' then return Core.GetPlayerFromId(src) end
    if FW == 'qb' then return Core.Functions.GetPlayer(src) end
    if FW == 'qbx' then return exports.qbx_core:GetPlayer(src) end
end
Bridge.GetPlayer = getPlayer

local function license(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return 'src:' .. tostring(src)
end

--- The player's game license (license:xxxx). Exclusive chains are tied to this.
function Bridge.GetLicense(src)
    local l = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license')
    if l and l ~= '' then return l end
    return license(src)
end

--- Character id (so a worn chain belongs to the character, not the account)
function Bridge.GetIdentifier(src)
    local p = getPlayer(src)
    if not p then return FW == 'none' and license(src) or nil end
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
        if duty == nil then duty = true end
        return j.name, duty
    end
    local j = p.PlayerData.job or {}
    return j.name, j.onduty ~= false
end

local function qbAccount(acc) return (acc == 'money' or acc == 'cash') and 'cash' or acc end
local function esxAccount(acc) return acc == 'cash' and 'money' or acc end

function Bridge.GetMoney(src, acc)
    local p = getPlayer(src)
    if FW == 'none' or not p then
        if GetResourceState('ox_inventory') == 'started' and acc ~= 'bank' then return exports.ox_inventory:GetItemCount(src, 'money') or 0 end
        return 0
    end
    if FW == 'esx' then
        local a = p.getAccount(esxAccount(acc))
        return a and a.money or 0
    end
    return p.PlayerData.money[qbAccount(acc)] or 0
end

function Bridge.RemoveMoney(src, amount, acc, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    if Bridge.GetMoney(src, acc) < amount then return false end
    local p = getPlayer(src)
    if FW == 'none' or not p then
        return GetResourceState('ox_inventory') == 'started' and exports.ox_inventory:RemoveItem(src, 'money', amount) == true
    end
    if FW == 'esx' then
        p.removeAccountMoney(esxAccount(acc), amount, reason)
        return true
    end
    return p.Functions.RemoveMoney(qbAccount(acc), amount, reason) ~= false
end

function Bridge.AddMoney(src, amount, acc, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if FW == 'none' or not p then
        return GetResourceState('ox_inventory') == 'started' and exports.ox_inventory:AddItem(src, 'money', amount) == true
    end
    if FW == 'esx' then
        p.addAccountMoney(esxAccount(acc), amount, reason)
        return true
    end
    return p.Functions.AddMoney(qbAccount(acc), amount, reason) ~= false
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.Studio.Ace or 'nayzeee.chains') then return true end
    if IsPlayerAceAllowed(src, 'command') then return true end
    local p = getPlayer(src)
    if not p then return false end
    local groups = ServerConfig.AdminGroups or {}
    if FW == 'esx' then
        local g = p.getGroup and p.getGroup()
        for _, a in ipairs(groups) do if g == a then return true end end
        return false
    end
    if FW == 'qb' then
        for _, a in ipairs(groups) do
            if Core.Functions.HasPermission(src, a) then return true end
        end
        return false
    end
    for _, a in ipairs(groups) do
        if IsPlayerAceAllowed(src, 'group.' .. a) then return true end
    end
    return false
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
    elseif FW == 'qb' or FW == 'qbx' then
        AddEventHandler('QBCore:Server:PlayerLoaded', function(p)
            local src = type(p) == 'table' and p.PlayerData and p.PlayerData.source or source
            cb(src)
        end)
    end
end

function Bridge.OnUnloaded(cb)
    if FW == 'esx' then
        AddEventHandler('esx:playerLogout', function(src) cb(src) end)
    elseif FW == 'qb' or FW == 'qbx' then
        AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) cb(src) end)
    end
end

function Bridge.IsLoaded(src)
    if FW == 'none' then return GetPlayerName(src) ~= nil end
    return getPlayer(src) ~= nil
end
