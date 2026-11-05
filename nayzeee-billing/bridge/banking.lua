--[[
    NAYZEEE BILLING - Banking bridge (server)
    Editable. Society accounts + optional personal accounts, and the Money layer every payment uses.

    Adapter shape:
        add(society, amount, reason) -> bool
        remove(society, amount, reason) -> bool   (false if it can't cover it)
        balance(society) -> number|nil
        log(data)                                 optional statements
        personal = { balance(id), add(id, amount, reason), remove(id, amount, reason) }   optional
]]

Banking = { name = 'none' }

Console.wait('banking')

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        Console.log('error', 'Banking (%s): %s', Banking.name, tostring(result))
        return nil
    end
    return result
end

local Adapters = {}

-- nayzeee-banking (ESX / QBCore / Qbox) - its ledger records every movement with our label
local function nz() return exports['nayzeee-banking'] end
Adapters['nayzeee-banking'] = {
    add = function(s, a, r) return nz():addSocietyMoney(s, a, r) == true end,
    remove = function(s, a, r) return nz():removeSocietyMoney(s, a, r) == true end,
    balance = function(s) return tonumber(nz():getSocietyBalance(s)) end,
    personal = {
        enabled = function() return Config.Banking.NayzeeePersonalAccounts ~= false end,
        balance = function(id) return tonumber(nz():getBalance(id)) or 0 end,
        add = function(id, a, r) return nz():addMoney(id, a, r, 'deposit') == true end,
        remove = function(id, a, r) return nz():removeMoney(id, a, r, 'bill') == true end,
    },
}

-- qb-banking (current QBCore)
Adapters['qb-banking'] = {
    add = function(s, a, r) return exports['qb-banking']:AddMoney(s, a, r) ~= false end,
    remove = function(s, a, r) return exports['qb-banking']:RemoveMoney(s, a, r) == true end,
    balance = function(s) return tonumber(exports['qb-banking']:GetAccountBalance(s)) end,
    log = function(d)
        -- qb-banking statements are created for an online player (server id)
        local src = d.identifier and Framework.GetSource(d.identifier)
        if not src then return end
        exports['qb-banking']:CreateBankStatement(src, 'checking', d.amount, d.title, d.type == 'deposit' and 'deposit' or 'withdraw', 'checking')
    end,
}

Adapters['okokBanking'] = {
    add = function(s, a) exports['okokBanking']:AddMoney(s, a) return true end,
    remove = function(s, a)
        if (tonumber(exports['okokBanking']:GetAccount(s)) or 0) < a then return false end
        exports['okokBanking']:RemoveMoney(s, a)
        return true
    end,
    balance = function(s) return tonumber(exports['okokBanking']:GetAccount(s)) end,
}

Adapters['Renewed-Banking'] = {
    add = function(s, a) return exports['Renewed-Banking']:addAccountMoney(s, a) ~= false end,
    remove = function(s, a) return exports['Renewed-Banking']:removeAccountMoney(s, a) == true end,
    balance = function(s) return tonumber(exports['Renewed-Banking']:getAccountMoney(s)) end,
    log = function(d)
        exports['Renewed-Banking']:handleTransaction(d.account or d.identifier, d.title, d.amount, d.description,
            d.issuer or 'Billing', d.receiver or 'Billing', d.type == 'deposit' and 'deposit' or 'withdraw')
    end,
}

-- Older QBCore: qb-management exposes the same calls as the qb-banking adapter expects
Adapters['qb-management'] = {
    add = function(s, a) exports['qb-management']:AddMoney(s, a) return true end,
    remove = function(s, a) return exports['qb-management']:RemoveMoney(s, a) == true end,
    balance = function(s) return tonumber(exports['qb-management']:GetAccount(s)) end,
}

-- ESX shared accounts (esx_addonaccount: society_<job>)
local function esxAccount(society)
    local prefix = Config.Banking.EsxSocietyPrefix or 'society_'
    local name = society:sub(1, #prefix) == prefix and society or prefix .. society
    if GetResourceState('esx_addonaccount') ~= 'started' then return nil end
    local ok, acc = pcall(function() return exports.esx_addonaccount:GetSharedAccount(name) end)
    if ok and acc then return acc end
    local result
    TriggerEvent('esx_addonaccount:getSharedAccount', name, function(a) result = a end)
    return result
end
Adapters['framework'] = {
    add = function(s, a) local acc = esxAccount(s) if not acc then return false end acc.addMoney(a) return true end,
    remove = function(s, a)
        local acc = esxAccount(s)
        if not acc or (tonumber(acc.money) or 0) < a then return false end
        acc.removeMoney(a)
        return true
    end,
    balance = function(s) local acc = esxAccount(s) return acc and tonumber(acc.money) or nil end,
}

-- wasabi_banking (verify these export names against your version)
Adapters['wasabi_banking'] = {
    add = function(s, a) return exports.wasabi_banking:AddMoney('society', s, a) ~= false end,
    remove = function(s, a)
        if (tonumber(exports.wasabi_banking:GetAccountBalance(s, 'society')) or 0) < a then return false end
        return exports.wasabi_banking:RemoveMoney('society', s, a) ~= false
    end,
    balance = function(s) return tonumber(exports.wasabi_banking:GetAccountBalance(s, 'society')) end,
}

Adapters['fd_banking'] = {
    add = function(s, a, r) return exports['fd_banking']:AddMoney(s, a, r) ~= false end,
    remove = function(s, a, r)
        if (tonumber(exports['fd_banking']:GetAccount(s)) or 0) < a then return false end
        return exports['fd_banking']:RemoveMoney(s, a, r) ~= false
    end,
    balance = function(s) return tonumber(exports['fd_banking']:GetAccount(s)) end,
}

Adapters['custom'] = {
    add = function(s, a, r) return Config.Banking.Custom.AddMoney(s, a, r) == true end,
    remove = function(s, a, r) return Config.Banking.Custom.RemoveMoney(s, a, r) == true end,
    balance = function(s) return tonumber(Config.Banking.Custom.GetBalance(s)) end,
}

local DetectOrder = {
    { 'nayzeee-banking', 'nayzeee-banking' },
    { 'qb-banking', 'qb-banking' },
    { 'okokBanking', 'okokBanking' },
    { 'Renewed-Banking', 'Renewed-Banking' },
    { 'qb-management', 'qb-management' },
    { 'framework', 'es_extended' },
    { 'wasabi_banking', 'wasabi_banking' },
}

local function detect()
    local wanted = Config.BankingIntegration or 'auto'
    if wanted == 'none' then return 'none' end
    if wanted ~= 'auto' then
        if Adapters[wanted] then return wanted end
        Console.log('warn', 'Config.BankingIntegration "%s" is not a known backend, auto-detecting instead', tostring(wanted))
    end
    for _, pair in ipairs(DetectOrder) do
        if GetResourceState(pair[2]) == 'started' then return pair[1] end
    end
    return 'none'
end

local function adapter() return Adapters[Banking.name] end

-- ███████╗ ██████╗  ██████╗██╗███████╗████████╗██╗   ██╗
-- ██╔════╝██╔═══██╗██╔════╝██║██╔════╝╚══██╔══╝╚██╗ ██╔╝
-- ███████╗██║   ██║██║     ██║█████╗     ██║    ╚████╔╝
-- ╚════██║██║   ██║██║     ██║██╔══╝     ██║     ╚██╔╝
-- ███████║╚██████╔╝╚██████╗██║███████╗   ██║      ██║
-- ╚══════╝ ╚═════╝  ╚═════╝╚═╝╚══════╝   ╚═╝      ╚═╝

function Banking.IsAvailable() return adapter() ~= nil end

function Banking.Account(societyId)
    local s = Shared.Society(societyId)
    return (s and s.account) or societyId
end

function Banking.AddSociety(societyId, amount, reason)
    local a = adapter()
    if not a or not societyId or amount <= 0 then return false end
    return safe(a.add, Banking.Account(societyId), Shared.Round(amount), reason or 'Invoice') == true
end

function Banking.RemoveSociety(societyId, amount, reason)
    local a = adapter()
    if not a or not societyId or amount <= 0 then return false end
    return safe(a.remove, Banking.Account(societyId), Shared.Round(amount), reason or 'Invoice') == true
end

function Banking.SocietyBalance(societyId)
    local a = adapter()
    if not a or not societyId then return nil end
    return safe(a.balance, Banking.Account(societyId))
end

function Banking.Log(data)
    if not Config.Banking.LogTransactions then return end
    local a = adapter()
    if a and a.log then safe(a.log, data) end
end

-- ██████╗ ███████╗██████╗ ███████╗ ██████╗ ███╗   ██╗ █████╗ ██╗
-- ██╔══██╗██╔════╝██╔══██╗██╔════╝██╔═══██╗████╗  ██║██╔══██╗██║
-- ██████╔╝█████╗  ██████╔╝███████╗██║   ██║██╔██╗ ██║███████║██║
-- ██╔═══╝ ██╔══╝  ██╔══██╗╚════██║██║   ██║██║╚██╗██║██╔══██║██║
-- ██║     ███████╗██║  ██║███████║╚██████╔╝██║ ╚████║██║  ██║███████╗
-- ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝

local function personal()
    local a = adapter()
    if a and a.personal and a.personal.enabled() then return a.personal end
    return nil
end

function Banking.HasPersonal() return personal() ~= nil end

-- ███╗   ███╗ ██████╗ ███╗   ██╗███████╗██╗   ██╗
-- ████╗ ████║██╔═══██╗████╗  ██║██╔════╝╚██╗ ██╔╝
-- ██╔████╔██║██║   ██║██╔██╗ ██║█████╗   ╚████╔╝
-- ██║╚██╔╝██║██║   ██║██║╚██╗██║██╔══╝    ╚██╔╝
-- ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████╗   ██║
-- ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚═╝

-- Every player money movement in billing goes through Money.*
Money = {}

function Money.Get(source, account)
    if account == 'bank' and personal() then
        return safe(personal().balance, Framework.GetIdentifier(source)) or 0
    end
    return Framework.GetMoney(source, account)
end

function Money.Remove(source, account, amount, reason)
    amount = Shared.Round(amount)
    if amount <= 0 then return true end
    if account == 'bank' and personal() then
        return safe(personal().remove, Framework.GetIdentifier(source), amount, reason) == true
    end
    return Framework.RemoveMoney(source, account, amount, reason) == true
end

function Money.Add(source, account, amount, reason)
    amount = Shared.Round(amount)
    if amount <= 0 then return true end
    if account == 'bank' and personal() then
        return safe(personal().add, Framework.GetIdentifier(source), amount, reason) == true
    end
    return Framework.AddMoney(source, account, amount, reason) ~= false
end

-- Bank deposit to a character, online or offline. Returns true when the money landed
function Money.DepositTo(identifier, amount, reason)
    amount = Shared.Round(amount)
    if not identifier or amount <= 0 then return amount <= 0 end
    if personal() then return safe(personal().add, identifier, amount, reason) == true end
    local src = Framework.GetSource(identifier)
    if src then return Money.Add(src, 'bank', amount, reason) end
    return Framework.AddOfflineBank(identifier, amount) == true
end

-- Bank charge on a character, online or offline (overdue collection)
function Money.ChargeBank(identifier, amount, reason, allowNegative, includeOffline)
    amount = Shared.Round(amount)
    if not identifier or amount <= 0 then return false end
    local src = Framework.GetSource(identifier)
    if personal() then
        if not src and not includeOffline then return false end
        return safe(personal().remove, identifier, amount, reason) == true
    end
    if src then return Money.Remove(src, 'bank', amount, reason) end
    if not includeOffline then return false end
    return Framework.RemoveOfflineBank(identifier, amount, allowNegative) == true
end

CreateThread(function()
    Wait(500)
    Banking.name = detect()
    if Banking.name == 'none' then
        Console.check('banking', 'warn', 'Banking', 'no society banking found: society invoices pay the issuing employee (set Config.BankingIntegration)')
    else
        Console.check('banking', 'ok', 'Banking', Banking.name .. (Banking.HasPersonal() and ', personal accounts' or ', society accounts'))
    end
    Console.done('banking')
end)
