--[[
    NAYZEEE BILLING - Banking Bridge (server)

    Adapters for society / company accounts and transaction history.
    Supported: nayzeee-banking, Renewed-Banking, okokBanking, fd_banking,
               qb-banking (v2), qb-management, esx_addonaccount, custom

    Every adapter implements:
        add(account, amount, reason)    -> bool
        remove(account, amount, reason) -> bool
        balance(account)                -> number | nil
        log(data)                       -> nil   (optional, personal/company statements)

    Adding another banking script = one more table in `Adapters` + its name in `DetectOrder`.
]]

Banking = { name = 'none' }

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        print(('^1[NAYZEEE-BILLING]^7 Banking (%s) error: %s'):format(Banking.name, tostring(result)))
        return nil
    end
    return result
end

local Adapters = {}

-- ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
-- ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
-- ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
-- ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
-- ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
-- ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

-- Every movement is written to nayzeee-banking's own ledger with our label, so no separate log call
local function nz() return exports[Config.Banking.Nayzeee.Resource or 'nayzeee-banking'] end

Adapters['nayzeee-banking'] = {
    resource = function() return Config.Banking.Nayzeee.Resource or 'nayzeee-banking' end,
    add = function(account, amount, reason)
        return nz():addSocietyMoney(account, amount, reason) == true
    end,
    remove = function(account, amount, reason)
        return nz():removeSocietyMoney(account, amount, reason) == true
    end,
    balance = function(account)
        return tonumber(nz():getSocietyBalance(account))
    end,
    -- Personal accounts (keyed by identifier, work for offline players too)
    personal = {
        enabled = function() return Config.Banking.Nayzeee.UsePersonalAccounts ~= false end,
        balance = function(identifier) return tonumber(nz():getBalance(identifier)) or 0 end,
        add = function(identifier, amount, reason)
            return nz():addMoney(identifier, amount, reason, 'deposit') == true
        end,
        remove = function(identifier, amount, reason)
            return nz():removeMoney(identifier, amount, reason, Config.Banking.Nayzeee.BillCategory or 'bill') == true
        end,
    },
}

-- ██████╗ ███████╗███╗   ██╗███████╗██╗    ██╗███████╗██████╗
-- ██╔══██╗██╔════╝████╗  ██║██╔════╝██║    ██║██╔════╝██╔══██╗
-- ██████╔╝█████╗  ██╔██╗ ██║█████╗  ██║ █╗ ██║█████╗  ██║  ██║
-- ██╔══██╗██╔══╝  ██║╚██╗██║██╔══╝  ██║███╗██║██╔══╝  ██║  ██║
-- ██║  ██║███████╗██║ ╚████║███████╗╚███╔███╔╝███████╗██████╔╝
-- ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚══════╝ ╚══╝╚══╝ ╚══════╝╚═════╝

Adapters['Renewed-Banking'] = {
    add = function(account, amount)
        return exports['Renewed-Banking']:addAccountMoney(account, amount) ~= false
    end,
    remove = function(account, amount)
        return exports['Renewed-Banking']:removeAccountMoney(account, amount) == true
    end,
    balance = function(account)
        return tonumber(exports['Renewed-Banking']:getAccountMoney(account))
    end,
    log = function(data)
        -- handleTransaction(account, title, amount, message, issuer, receiver, transType)
        exports['Renewed-Banking']:handleTransaction(
            data.account or data.identifier, data.title, data.amount, data.description,
            data.issuer or 'Billing', data.receiver or data.name or 'Billing',
            data.type == 'deposit' and 'deposit' or 'withdraw')
    end,
}

--  ██████╗ ██╗  ██╗ ██████╗ ██╗  ██╗
-- ██╔═══██╗██║ ██╔╝██╔═══██╗██║ ██╔╝
-- ██║   ██║█████╔╝ ██║   ██║█████╔╝
-- ██║   ██║██╔═██╗ ██║   ██║██╔═██╗
-- ╚██████╔╝██║  ██╗╚██████╔╝██║  ██╗
--  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝

Adapters['okokBanking'] = {
    add = function(account, amount)
        exports['okokBanking']:AddMoney(account, amount)
        return true
    end,
    remove = function(account, amount)
        local bal = tonumber(exports['okokBanking']:GetAccount(account)) or 0
        if bal < amount then return false end
        exports['okokBanking']:RemoveMoney(account, amount)
        return true
    end,
    balance = function(account)
        return tonumber(exports['okokBanking']:GetAccount(account))
    end,
}

-- ███████╗██████╗     ██████╗  █████╗ ███╗   ██╗██╗  ██╗██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔══██╗    ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██║████╗  ██║██╔════╝
-- █████╗  ██║  ██║    ██████╔╝███████║██╔██╗ ██║█████╔╝ ██║██╔██╗ ██║██║  ███╗
-- ██╔══╝  ██║  ██║    ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ██║██║╚██╗██║██║   ██║
-- ██║     ██████╔╝    ██████╔╝██║  ██║██║ ╚████║██║  ██╗██║██║ ╚████║╚██████╔╝
-- ╚═╝     ╚═════╝     ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Adapters['fd_banking'] = {
    add = function(account, amount, reason)
        return exports['fd_banking']:AddMoney(account, amount, reason) ~= false
    end,
    remove = function(account, amount, reason)
        local bal = tonumber(exports['fd_banking']:GetAccount(account)) or 0
        if bal < amount then return false end
        return exports['fd_banking']:RemoveMoney(account, amount, reason) ~= false
    end,
    balance = function(account)
        return tonumber(exports['fd_banking']:GetAccount(account))
    end,
}

--  ██████╗ ██████╗     ██████╗  █████╗ ███╗   ██╗██╗  ██╗██╗███╗   ██╗ ██████╗
-- ██╔═══██╗██╔══██╗    ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██║████╗  ██║██╔════╝
-- ██║   ██║██████╔╝    ██████╔╝███████║██╔██╗ ██║█████╔╝ ██║██╔██╗ ██║██║  ███╗
-- ██║▄▄ ██║██╔══██╗    ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ██║██║╚██╗██║██║   ██║
-- ╚██████╔╝██████╔╝    ██████╔╝██║  ██║██║ ╚████║██║  ██╗██║██║ ╚████║╚██████╔╝
--  ╚══▀▀═╝ ╚═════╝     ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Adapters['qb-banking'] = {
    add = function(account, amount, reason)
        return exports['qb-banking']:AddMoney(account, amount, reason) ~= false
    end,
    remove = function(account, amount, reason)
        return exports['qb-banking']:RemoveMoney(account, amount, reason) == true
    end,
    balance = function(account)
        return tonumber(exports['qb-banking']:GetAccountBalance(account))
    end,
    log = function(data)
        if not data.identifier then return end
        -- CreateBankStatement(citizenid, accountName, amount, reason, statementType, accountType)
        exports['qb-banking']:CreateBankStatement(data.identifier, data.account or 'checking', data.amount,
            data.title, data.type == 'deposit' and 'deposit' or 'withdraw', data.account and 'shared' or 'checking')
    end,
}

Adapters['qb-management'] = {
    add = function(account, amount)
        exports['qb-management']:AddMoney(account, amount)
        return true
    end,
    remove = function(account, amount)
        return exports['qb-management']:RemoveMoney(account, amount) == true
    end,
    balance = function(account)
        return tonumber(exports['qb-management']:GetAccount(account))
    end,
}

-- ███████╗███████╗██╗  ██╗
-- ██╔════╝██╔════╝╚██╗██╔╝
-- █████╗  ███████╗ ╚███╔╝
-- ██╔══╝  ╚════██║ ██╔██╗
-- ███████╗███████║██╔╝ ██╗
-- ╚══════╝╚══════╝╚═╝  ╚═╝

local function esxAccount(account)
    local name = account
    local prefix = Config.Banking.EsxSocietyPrefix or 'society_'
    if prefix ~= '' and name:sub(1, #prefix) ~= prefix then
        name = prefix .. name
    end
    local result
    TriggerEvent('esx_addonaccount:getSharedAccount', name, function(acc) result = acc end)
    return result
end

Adapters['esx_addonaccount'] = {
    add = function(account, amount)
        local acc = esxAccount(account)
        if not acc then return false end
        acc.addMoney(amount)
        return true
    end,
    remove = function(account, amount)
        local acc = esxAccount(account)
        if not acc or (tonumber(acc.money) or 0) < amount then return false end
        acc.removeMoney(amount)
        return true
    end,
    balance = function(account)
        local acc = esxAccount(account)
        return acc and tonumber(acc.money) or nil
    end,
}

--  ██████╗██╗   ██╗███████╗████████╗ ██████╗ ███╗   ███╗
-- ██╔════╝██║   ██║██╔════╝╚══██╔══╝██╔═══██╗████╗ ████║
-- ██║     ██║   ██║███████╗   ██║   ██║   ██║██╔████╔██║
-- ██║     ██║   ██║╚════██║   ██║   ██║   ██║██║╚██╔╝██║
-- ╚██████╗╚██████╔╝███████║   ██║   ╚██████╔╝██║ ╚═╝ ██║
--  ╚═════╝ ╚═════╝ ╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝

Adapters['custom'] = {
    add = function(account, amount, reason) return Config.Banking.Custom.AddMoney(account, amount, reason) == true end,
    remove = function(account, amount, reason) return Config.Banking.Custom.RemoveMoney(account, amount, reason) == true end,
    balance = function(account) return tonumber(Config.Banking.Custom.GetBalance(account)) end,
}

-- ██████╗ ███████╗████████╗███████╗ ██████╗████████╗
-- ██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝
-- ██║  ██║█████╗     ██║   █████╗  ██║        ██║
-- ██║  ██║██╔══╝     ██║   ██╔══╝  ██║        ██║
-- ██████╔╝███████╗   ██║   ███████╗╚██████╗   ██║
-- ╚═════╝ ╚══════╝   ╚═╝   ╚══════╝ ╚═════╝   ╚═╝

local DetectOrder = {
    'nayzeee-banking', 'Renewed-Banking', 'okokBanking', 'fd_banking',
    'qb-banking', 'qb-management', 'esx_addonaccount',
}

local function resourceFor(name)
    local adapter = Adapters[name]
    if adapter and adapter.resource then return adapter.resource() end
    return name
end

local function Detect()
    local system = Config.Banking.System or 'auto'
    if system == 'none' then return 'none' end
    if system ~= 'auto' then
        if not Adapters[system] then
            print(('^1[NAYZEEE-BILLING]^7 Unknown banking system "%s", falling back to auto-detect'):format(system))
        else
            return system
        end
    end
    for _, name in ipairs(DetectOrder) do
        if GetResourceState(resourceFor(name)) == 'started' then
            return name
        end
    end
    return 'none'
end

local function adapter()
    return Adapters[Banking.name]
end

--  █████╗ ██████╗ ██╗
-- ██╔══██╗██╔══██╗██║
-- ███████║██████╔╝██║
-- ██╔══██║██╔═══╝ ██║
-- ██║  ██║██║     ██║
-- ╚═╝  ╚═╝╚═╝     ╚═╝

function Banking.IsAvailable()
    return adapter() ~= nil
end

-- Company account name for a company id (account override > first job > id)
function Banking.AccountFor(company)
    if not company then return nil end
    return company.account or company.job or (type(company.jobs) == 'table' and company.jobs[1]) or company.id
end

function Banking.AddSociety(account, amount, reason)
    local a = adapter()
    if not a or not account or amount <= 0 then return false end
    return safe(a.add, account, Shared.Round(amount), reason or 'Invoice payment') == true
end

function Banking.RemoveSociety(account, amount, reason)
    local a = adapter()
    if not a or not account or amount <= 0 then return false end
    return safe(a.remove, account, Shared.Round(amount), reason or 'Invoice refund') == true
end

function Banking.GetSocietyBalance(account)
    local a = adapter()
    if not a or not account then return nil end
    return safe(a.balance, account)
end

--@@ PERSONAL

-- Banking scripts that own personal balances (nayzeee-banking). nil = use the framework's bank account
local function personal()
    local a = adapter()
    if a and a.personal and a.personal.enabled() then return a.personal end
    return nil
end

function Banking.HasPersonal()
    return personal() ~= nil
end

function Banking.PersonalBalance(identifier)
    local p = personal()
    if not p or not identifier then return nil end
    return safe(p.balance, identifier)
end

function Banking.AddPersonal(identifier, amount, reason)
    local p = personal()
    if not p or not identifier or amount <= 0 then return false end
    return safe(p.add, identifier, Shared.Round(amount), reason or 'Billing') == true
end

function Banking.RemovePersonal(identifier, amount, reason)
    local p = personal()
    if not p or not identifier or amount <= 0 then return false end
    return safe(p.remove, identifier, Shared.Round(amount), reason or 'Billing') == true
end

-- data = { identifier, name, account?, amount, type = 'deposit'|'withdraw', title, description }
function Banking.Log(data)
    if not Config.Banking.LogTransactions then return end
    local a = adapter()
    if a and a.log then safe(a.log, data) end
end

CreateThread(function()
    Wait(500)
    Banking.name = Detect()
    if Banking.name == 'none' then
        print('^3[NAYZEEE-BILLING]^7 No banking system detected - company payments will go to the employee')
    else
        print(('^2[NAYZEEE-BILLING]^7 Banking: ^5%s^7'):format(Banking.name))
    end
end)
