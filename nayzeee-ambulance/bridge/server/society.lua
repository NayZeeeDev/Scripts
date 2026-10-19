--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: society / business accounts (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Where hospital income goes and where the boss
    menu spends from. Detection order per framework is Bridge.Priority.society
    (bridge/shared.lua); force one with Config.Bridge.society.

      Bridge.Society.Get(name)            → number
      Bridge.Society.Add(name, amount)    → bool
      Bridge.Society.Remove(name, amount) → bool   (false when the account is short)
      Bridge.Society.Resource()           → adapter name or nil

    name is the JOB name ('ambulance'). ESX adapters add the 'society_' prefix.

    ADDING YOUR OWN
      Bridge.SocietyAdapters['my_bank'] = { get = fn(name), add = fn(name, amount), remove = fn(name, amount) }
      Bridge.Resources.society['my_bank'] = 'my_bank'      (resource that must be started)
      and put 'my_bank' in Bridge.Priority.society[<framework>] or set Config.Bridge.society = 'my_bank'
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Society = Bridge.Society or {}

local S = {}
Bridge.SocietyAdapters = S

-- ═══════════════════════════════════════════════════════════════════════════
-- esx_addonaccount (esx_society)
-- ═══════════════════════════════════════════════════════════════════════════

local function esxAccount(name)
    local accountName = name:sub(1, 8) == 'society_' and name or ('society_' .. name)
    local p = promise.new()
    TriggerEvent('esx_addonaccount:getSharedAccount', accountName, function(account)
        p:resolve(account or false)
    end)
    SetTimeout(3000, function()
        if p.state == 0 then p:resolve(false) end
    end)
    return Citizen.Await(p) or nil
end

S['esx_addonaccount'] = {
    get = function(name)
        local acc = esxAccount(name)
        return acc and tonumber(acc.money) or 0
    end,
    add = function(name, amount)
        local acc = esxAccount(name)
        if not acc then return false end
        acc.addMoney(amount)
        return true
    end,
    remove = function(name, amount)
        local acc = esxAccount(name)
        if not acc or (tonumber(acc.money) or 0) < amount then return false end
        acc.removeMoney(amount)
        return true
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Renewed-Banking (verified: getAccountMoney / addAccountMoney / removeAccountMoney)
-- ═══════════════════════════════════════════════════════════════════════════

S['Renewed-Banking'] = {
    get = function(name)
        return tonumber(exports['Renewed-Banking']:getAccountMoney(name)) or 0
    end,
    add = function(name, amount)
        return exports['Renewed-Banking']:addAccountMoney(name, amount) ~= false
    end,
    remove = function(name, amount)
        return exports['Renewed-Banking']:removeAccountMoney(name, amount) == true
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- qb-banking (verified: GetAccountBalance / AddMoney / RemoveMoney / CreateJobAccount)
-- ═══════════════════════════════════════════════════════════════════════════

local function qbBankingEnsure(name)
    if exports['qb-banking']:GetAccount(name) then return true end
    local ok = pcall(function() exports['qb-banking']:CreateJobAccount(name, 0) end)
    return ok and exports['qb-banking']:GetAccount(name) ~= nil
end

S['qb-banking'] = {
    get = function(name)
        return tonumber(exports['qb-banking']:GetAccountBalance(name)) or 0
    end,
    add = function(name, amount)
        if not qbBankingEnsure(name) then return false end
        return exports['qb-banking']:AddMoney(name, amount, 'nayzeee-ambulance') ~= false
    end,
    remove = function(name, amount)
        if not qbBankingEnsure(name) then return false end
        if (tonumber(exports['qb-banking']:GetAccountBalance(name)) or 0) < amount then return false end
        return exports['qb-banking']:RemoveMoney(name, amount, 'nayzeee-ambulance') ~= false
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- qb-management (legacy versions that still hold society money)
-- Current qb-management moved money to qb-banking; it is used then instead.
-- ═══════════════════════════════════════════════════════════════════════════

local function legacyManagement()
    local ok, value = pcall(function() return exports['qb-management']:GetAccount('ambulance') end)
    return ok and value ~= nil
end

S['qb-management'] = {
    get = function(name)
        if legacyManagement() then return tonumber(exports['qb-management']:GetAccount(name)) or 0 end
        return Bridge.Started('qb-banking') and S['qb-banking'].get(name) or 0
    end,
    add = function(name, amount)
        if legacyManagement() then
            exports['qb-management']:AddMoney(name, amount)
            return true
        end
        return Bridge.Started('qb-banking') and S['qb-banking'].add(name, amount) or false
    end,
    remove = function(name, amount)
        if legacyManagement() then
            if (tonumber(exports['qb-management']:GetAccount(name)) or 0) < amount then return false end
            return exports['qb-management']:RemoveMoney(name, amount) ~= false
        end
        return Bridge.Started('qb-banking') and S['qb-banking'].remove(name, amount) or false
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- qbx_management - stores no money itself; Qbox keeps job accounts in
-- Renewed-Banking (or qb-banking). This entry routes to whichever runs.
-- ═══════════════════════════════════════════════════════════════════════════

local function qbxBank()
    if Bridge.Started('Renewed-Banking') then return S['Renewed-Banking'] end
    if Bridge.Started('qb-banking') then return S['qb-banking'] end
    return nil
end

S['qbx_management'] = {
    get = function(name)
        local bank = qbxBank()
        return bank and bank.get(name) or 0
    end,
    add = function(name, amount)
        local bank = qbxBank()
        return bank and bank.add(name, amount) or false
    end,
    remove = function(name, amount)
        local bank = qbxBank()
        return bank and bank.remove(name, amount) or false
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- okokBanking (GetAccount / AddMoney / RemoveMoney by society name)
-- On ESX okokBanking societies are named 'society_<job>'.
-- ═══════════════════════════════════════════════════════════════════════════

local function okokName(name)
    if Bridge.Framework == 'esx' and name:sub(1, 8) ~= 'society_' then return 'society_' .. name end
    return name
end

S['okokBanking'] = {
    get = function(name)
        return tonumber(exports['okokBanking']:GetAccount(okokName(name))) or 0
    end,
    add = function(name, amount)
        exports['okokBanking']:AddMoney(okokName(name), amount)
        return true
    end,
    remove = function(name, amount)
        if S['okokBanking'].get(name) < amount then return false end
        exports['okokBanking']:RemoveMoney(okokName(name), amount)
        return true
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- fd_banking (GetAccount / AddMoney / RemoveMoney)
-- ═══════════════════════════════════════════════════════════════════════════

S['fd_banking'] = {
    get = function(name)
        return tonumber(exports['fd_banking']:GetAccount(name)) or 0
    end,
    add = function(name, amount)
        return exports['fd_banking']:AddMoney(name, amount, 'nayzeee-ambulance') ~= false
    end,
    remove = function(name, amount)
        if S['fd_banking'].get(name) < amount then return false end
        return exports['fd_banking']:RemoveMoney(name, amount, 'nayzeee-ambulance') ~= false
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ox_core group accounts (GetGroupAccount + CallAccount get 'balance' /
-- addBalance / removeBalance). The group needs hasAccount; ox_core then keeps
-- its default account. Account calls are asynchronous: call from a thread.
-- ═══════════════════════════════════════════════════════════════════════════

local function oxGroupAccount(name)
    local OA = Bridge.OxAccount
    if not OA then return nil end
    return OA.id(exports.ox_core:GetGroupAccount(name)), OA
end

S['ox_core'] = {
    get = function(name)
        local id, OA = oxGroupAccount(name)
        return id and OA.balance(id) or 0
    end,
    add = function(name, amount)
        local id, OA = oxGroupAccount(name)
        return id ~= nil and OA.add(id, amount, 'nayzeee-ambulance')
    end,
    remove = function(name, amount)
        local id, OA = oxGroupAccount(name)
        return id ~= nil and OA.remove(id, amount, 'nayzeee-ambulance')
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE
-- ═══════════════════════════════════════════════════════════════════════════

local resolved, resolvedOnce = nil, false

local function resolve()
    if resolvedOnce then return resolved end
    resolvedOnce = true
    local priority = Bridge.Priority.society[Bridge.Framework] or Bridge.Priority.society.standalone
    resolved = Bridge.Pick('society', Bridge.Cfg('society', 'auto'), {
        priority = priority,
        has = function(name) return S[name] ~= nil end,
    })
    Bridge.Debug('society account:', resolved or 'none')
    return resolved
end

function Bridge.Society.Resource()
    return resolve()
end

local function valid(name, amount)
    if type(name) ~= 'string' or name == '' then return false end
    if amount == nil then return true end
    amount = tonumber(amount)
    return amount ~= nil and amount == amount and amount >= 0
end

function Bridge.Society.Get(name)
    if not valid(name) then return 0 end
    local adapter = resolve()
    if not adapter then return 0 end
    local ok, value = Bridge.Try('society.' .. adapter .. '.get', S[adapter].get, name)
    return ok and tonumber(value) or 0
end

function Bridge.Society.Add(name, amount)
    if not valid(name, amount) then return false end
    amount = math.floor(tonumber(amount) + 0.5)
    if amount == 0 then return true end
    local adapter = resolve()
    if not adapter then return false end
    local ok, done = Bridge.Try('society.' .. adapter .. '.add', S[adapter].add, name, amount)
    return ok and done == true
end

function Bridge.Society.Remove(name, amount)
    if not valid(name, amount) then return false end
    amount = math.floor(tonumber(amount) + 0.5)
    if amount == 0 then return true end
    local adapter = resolve()
    if not adapter then return false end
    local ok, done = Bridge.Try('society.' .. adapter .. '.remove', S[adapter].remove, name, amount)
    return ok and done == true
end

local function reset(resource)
    if resource == GetCurrentResourceName() then return end
    if Bridge.IsKnownResource('society', resource) then
        resolvedOnce = false
        resolved = nil
    end
end

AddEventHandler('onResourceStart', reset)
AddEventHandler('onResourceStop', reset)
