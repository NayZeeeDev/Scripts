if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  ESX BRIDGE
--
--  Our tables are the source of truth. ESX's own `bank` account and
--  the esx_addonaccount society balances are kept equal to them, in
--  both directions:
--
--    · our balance is pushed out the moment it changes
--    · anything that moves ESX's figure behind our back is picked up
--      on the next sync and folded into our ledger
--
--  That means ESX keeps paying wages exactly as it always has — out
--  of society_<job> every Config.PaycheckInterval — and the money
--  simply lands in this bank. Nothing needs patching.
--
--  Set Config.Payroll.mode = 'bank' to take wages over instead.
-- ═══════════════════════════════════════════════════════════

local SYNC_SECONDS = 15   -- how often the mirror reconciles

local lastBank    = {}   -- [identifier] = balance we last wrote into ESX
local lastSociety = {}   -- [job]        = balance we last wrote into esx_addonaccount

-- ═══════════════════════════════════════════════════════════
--  PLAYER BANK ACCOUNT
-- ═══════════════════════════════════════════════════════════
local function syncPlayer(xPlayer)
    local acc = Bank.getPersonal(xPlayer.identifier)
    if not acc then return end

    local esxAccount = xPlayer.getAccount('bank')
    if not esxAccount then return end

    local esxMoney = esxAccount.money or 0
    local expected = lastBank[xPlayer.identifier]

    -- something outside this resource moved the ESX balance
    if expected and esxMoney ~= expected then
        local delta = esxMoney - expected

        if delta > 0 then
            Bank.credit(acc.id, delta, {
                category = 'deposit', label = 'Deposit', actorName = 'External'
            })
        else
            Bank.debit(acc.id, -delta, {
                category = 'withdraw', label = 'Payment', actorName = 'External'
            })
        end

        acc = Bank.getPersonal(xPlayer.identifier)
    end

    if esxMoney ~= acc.balance then
        xPlayer.setAccountMoney('bank', acc.balance, 'nayzeee-banking')
    end
    lastBank[xPlayer.identifier] = acc.balance
end

-- push our balance out the moment it changes rather than waiting on the loop
AddEventHandler('nz_bank:balanceChanged', function(identifier, balance)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if not xPlayer then return end

    xPlayer.setAccountMoney('bank', balance, 'nayzeee-banking')
    lastBank[identifier] = balance
end)

-- ═══════════════════════════════════════════════════════════
--  SOCIETY ACCOUNTS
--  Two-way as well. ESX takes wages out of society_<job>, so a
--  one-way push would put that money straight back and end up
--  paying wages out of thin air.
-- ═══════════════════════════════════════════════════════════
--- Read the framework's society balance, whichever table it lives in.
local DETECT = {
    { table = 'addon_account_data', jobColumn = 'account_name', amountColumn = 'money' },
    { table = 'management_funds',   jobColumn = 'job_name',     amountColumn = 'amount' },
    { table = 'bank_accounts',      jobColumn = 'job_name',     amountColumn = 'account_balance' }
}
local societyTable = nil

local function resolveTable()
    if societyTable then return societyTable end

    if not Config.Society.autoDetect then
        societyTable = Config.Society
        return societyTable
    end

    for _, candidate in ipairs(DETECT) do
        local ok = pcall(function()
            MySQL.scalar.await(('SELECT `%s` FROM `%s` LIMIT 1'):format(
                candidate.amountColumn, candidate.table))
        end)
        if ok then
            candidate.prefix = Config.Society.prefix
            societyTable = candidate
            Bank.debug('society table detected: ' .. candidate.table)
            return societyTable
        end
    end

    societyTable = Config.Society
    return societyTable
end

local function frameworkSociety(job)
    -- bcs_companymanager keeps company money in its own accounts
    if GetResourceState('bcs_companymanager') == 'started' then
        local ok, money = pcall(function()
            return exports.bcs_companymanager:GetCompanyMoney(job, 'money')
        end)
        if ok and tonumber(money) then
            return tonumber(money), function(value)
                local delta = value - tonumber(money)
                if delta > 0 then
                    exports.bcs_companymanager:AddCompanyMoney(job, 'money', delta, nil, 'Bank sync')
                elseif delta < 0 then
                    exports.bcs_companymanager:RemoveCompanyMoney(job, 'money', -delta, nil, 'Bank sync')
                end
            end
        end
    end

    -- esx_addonaccount gives us a live object, which is cheaper than a query
    if GetResourceState('esx_addonaccount') == 'started' then
        local ok, addon = pcall(function()
            return exports.esx_addonaccount:GetSharedAccount(Config.Society.prefix .. job)
        end)
        if ok and addon then
            return addon.money or 0, function(value) addon.setMoney(value) end
        end
    end

    local t = resolveTable()
    local name = t.prefix .. job

    local money = MySQL.scalar.await(('SELECT `%s` FROM `%s` WHERE `%s` = ?'):format(
        t.amountColumn, t.table, t.jobColumn), { name })
    if money == nil then return nil end

    return money, function(value)
        MySQL.update(('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(
            t.amountColumn, t.table, t.jobColumn), { value, name })
    end
end

local function syncSociety(job)
    local ours = Bank.getSociety(job)
    if not ours then return end

    local addonMoney, setMoney = frameworkSociety(job)
    if not addonMoney then return end
    local expected = lastSociety[job]

    if expected and addonMoney ~= expected then
        local delta = addonMoney - expected

        if delta > 0 then
            Bank.credit(ours.id, delta, {
                category = 'deposit', label = 'Society income', actorName = 'External'
            })
        else
            Bank.debit(ours.id, -delta, {
                category = 'payroll', label = 'Wages paid', actorName = 'ESX paycheck'
            })
        end

        ours = Bank.getSociety(job)
    end

    if addonMoney ~= ours.balance then
        setMoney(ours.balance)
    end
    lastSociety[job] = ours.balance
end

-- ═══════════════════════════════════════════════════════════
--  LOOP
-- ═══════════════════════════════════════════════════════════
CreateThread(function()
    Wait(6000)

    while true do
        Wait(SYNC_SECONDS * 1000)

        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
            local ok, err = pcall(syncPlayer, xPlayer)
            if not ok then Bank.debug('bank sync failed', err) end
        end

        for job in pairs(Config.Accounts.societyAccess) do
            local ok, err = pcall(syncSociety, job)
            if not ok then Bank.debug('society sync failed', err) end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local xPlayer = Bank.getPlayer(source)
    if xPlayer then lastBank[xPlayer.identifier] = nil end
end)

-- ═══════════════════════════════════════════════════════════
--  WAGES PAID HERE  (Config.Payroll.mode = 'bank')
--  ESX's own paycheck is switched off per player so nobody is paid
--  twice. sv_payroll handles it from there.
-- ═══════════════════════════════════════════════════════════
AddEventHandler('esx:playerLoaded', function(src, xPlayer)
    if Config.Payroll.mode ~= 'bank' then return end

    CreateThread(function()
        Wait(2000)
        if xPlayer.togglePaycheck then
            xPlayer.togglePaycheck(false)
        else
            print('^3[nayzeee-banking]^7 xPlayer.togglePaycheck is missing on this ESX build. ' ..
                  'Set Config.Payroll.mode = "esx" or patch paycheck.lua (see README).')
        end
    end)
end)

-- nz_bank:paycheck is handled in sv_accounts.lua (server-side only, never a net event)
