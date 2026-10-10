--[[ Framework bridge (server). Exposes a single `FW` table used by the rest of the resource. ]]

FW = { name = 'none' }

local function detect()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'none'
end

FW.name = detect()

local QB, ESX
if FW.name == 'qb' then
    QB = exports['qb-core']:GetCoreObject()
elseif FW.name == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

local function qbPlayer(src)
    if FW.name == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    return QB and QB.Functions.GetPlayer(src)
end

function FW.getPlayer(src)
    if FW.name == 'esx' then return ESX.GetPlayerFromId(src) end
    if FW.name == 'qb' or FW.name == 'qbx' then return qbPlayer(src) end
    return nil
end

function FW.identifier(src)
    local p = FW.getPlayer(src)
    if p then
        if FW.name == 'esx' then return p.identifier end
        return p.PlayerData.citizenid
    end
    return GetPlayerIdentifierByType(src, 'license')
end

function FW.charName(src)
    local p = FW.getPlayer(src)
    if p then
        if FW.name == 'esx' then return p.getName() end
        local ci = p.PlayerData.charinfo
        return ci and (ci.firstname .. ' ' .. ci.lastname) or GetPlayerName(src)
    end
    return GetPlayerName(src)
end

--- { name, grade, onduty, gang }
function FW.job(src)
    local p = FW.getPlayer(src)
    if not p then return { name = 'unemployed', grade = 0, onduty = false } end
    if FW.name == 'esx' then
        local job = p.getJob()
        return { name = job.name, grade = job.grade, onduty = true }
    end
    local pd = p.PlayerData
    return {
        name = pd.job and pd.job.name or 'unemployed',
        grade = pd.job and pd.job.grade and pd.job.grade.level or 0,
        onduty = pd.job and pd.job.onduty or false,
        gang = pd.gang and pd.gang.name or nil,
    }
end

function FW.isPolice(src)
    local job = FW.job(src)
    if not Utils.contains(Config.Police.jobs, job.name) then return false end
    return not Config.Police.onDutyOnly or job.onduty
end

function FW.policeCount()
    local n = 0
    for _, src in ipairs(GetPlayers()) do
        if FW.isPolice(tonumber(src)) then n = n + 1 end
    end
    return n
end

function FW.policePlayers()
    local list = {}
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        if FW.isPolice(src) then list[#list + 1] = src end
    end
    return list
end

local esxAccounts = { cash = 'money', bank = 'bank', black_money = 'black_money' }

function FW.getMoney(src, account)
    local p = FW.getPlayer(src)
    if not p then return 0 end
    if FW.name == 'esx' then
        if account == 'cash' then return p.getMoney() end
        local acc = p.getAccount(esxAccounts[account] or account)
        return acc and acc.money or 0
    end
    if FW.name == 'qbx' then return exports.qbx_core:GetMoney(src, account) or 0 end
    return p.PlayerData.money[account] or 0
end

function FW.removeMoney(src, account, amount, reason)
    local p = FW.getPlayer(src)
    if not p or amount <= 0 then return amount <= 0 end
    if FW.getMoney(src, account) < amount then return false end
    if FW.name == 'esx' then
        if account == 'cash' then p.removeMoney(amount, reason) else p.removeAccountMoney(esxAccounts[account] or account, amount, reason) end
        return true
    end
    if FW.name == 'qbx' then return exports.qbx_core:RemoveMoney(src, account, amount, reason) end
    return p.Functions.RemoveMoney(account, amount, reason)
end

function FW.addMoney(src, account, amount, reason)
    local p = FW.getPlayer(src)
    if not p or amount <= 0 then return false end
    if FW.name == 'esx' then
        if account == 'cash' then p.addMoney(amount, reason) else p.addAccountMoney(esxAccounts[account] or account, amount, reason) end
        return true
    end
    if FW.name == 'qbx' then return exports.qbx_core:AddMoney(src, account, amount, reason) end
    return p.Functions.AddMoney(account, amount, reason)
end

function FW.notify(src, msg, kind)
    TriggerClientEvent('nzwl:notify', src, msg, kind or 'info')
end

function FW.registerUsable(item, cb)
    if FW.name == 'esx' then
        ESX.RegisterUsableItem(item, function(src) cb(src) end)
    elseif FW.name == 'qbx' then
        exports.qbx_core:CreateUseableItem(item, function(src) cb(src) end)
    elseif FW.name == 'qb' then
        QB.Functions.CreateUseableItem(item, function(src) cb(src) end)
    end
end

--- Fires cb(src) when a character finishes loading; used for reconnect restore
function FW.onLoaded(cb)
    if FW.name == 'esx' then
        AddEventHandler('esx:playerLoaded', function(src) cb(src) end)
    else
        RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function() cb(source) end)
    end
end

function FW.onUnloaded(cb)
    if FW.name == 'esx' then
        AddEventHandler('esx:playerDropped', function(src) cb(src) end)
    else
        RegisterNetEvent('QBCore:Server:OnPlayerUnload', function(src) cb(src or source) end)
    end
end

Utils.debug('framework:', FW.name)
