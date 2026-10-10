if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  ADMIN
-- ═══════════════════════════════════════════════════════════

local function isAdmin(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, Config.Admin.ace) then return true end

    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return false end
    for _, group in ipairs(Config.Admin.allowGroups) do
        if xPlayer.getGroup() == group then return true end
    end
    return false
end

local function resolveTarget(arg)
    local asId = tonumber(arg)
    if asId then
        local xPlayer = ESX.GetPlayerFromId(asId)
        if xPlayer then return xPlayer.identifier, Bank.fullName(xPlayer) end
    end
    local acc = MySQL.single.await(
        'SELECT owner, label FROM nz_bank_accounts WHERE account_number = ?', { arg })
    if acc then return acc.owner, acc.label end
    return nil
end

RegisterCommand(Config.Admin.command, function(src, args)
    if not isAdmin(src) then
        if src > 0 then Bank.notify(src, 'Banking', 'You do not have access to that.', 'error') end
        return
    end

    local action = (args[1] or ''):lower()

    -- /bankadmin give <playerId|accountNumber> <amount>
    -- /bankadmin take <playerId|accountNumber> <amount>
    if action == 'give' or action == 'take' then
        local identifier, name = resolveTarget(args[2])
        local amount = Bank.round(tonumber(args[3]) or 0)
        if not identifier or amount <= 0 then
            return Bank.notify(src, 'Banking', ('Usage: /%s %s <id|account> <amount>'):format(Config.Admin.command, action), 'error')
        end

        local acc = Bank.getPersonal(identifier)
        if not acc then return Bank.notify(src, 'Banking', 'No account found.', 'error') end

        local actor = src > 0 and Bank.fullName(Bank.getPlayer(src)) or 'Console'
        local ok
        if action == 'give' then
            ok = Bank.credit(acc.id, amount, { category = 'admin', label = 'Adjustment', actorName = actor })
        else
            ok = Bank.debit(acc.id, amount, { category = 'admin', label = 'Adjustment', actorName = actor })
        end

        Bank.notify(src, 'Banking', ok
            and ('%s %s%s %s %s.'):format(action == 'give' and 'Added' or 'Removed', Config.Currency, amount,
                 action == 'give' and 'to' or 'from', name)
            or 'That did not go through.', ok and 'success' or 'error')

        Bank.log('admin', 'Balance adjusted',
            ('**%s** %s **%s%s** %s %s'):format(actor, action == 'give' and 'added' or 'removed',
             Config.Currency, amount, action == 'give' and 'to' or 'from', name))

    -- /bankadmin freeze <playerId|accountNumber>
    elseif action == 'freeze' or action == 'unfreeze' then
        local identifier = resolveTarget(args[2])
        if not identifier then return Bank.notify(src, 'Banking', 'Target not found.', 'error') end

        local frozen = action == 'freeze' and 1 or 0
        MySQL.update.await('UPDATE nz_bank_accounts SET frozen = ? WHERE owner = ?', { frozen, identifier })
        Bank.notify(src, 'Banking', ('Accounts %s.'):format(frozen == 1 and 'frozen' or 'unfrozen'), 'success')
        Bank.log('admin', 'Accounts ' .. action, ('Target: `%s`'):format(identifier))

    -- /bankadmin check <playerId|accountNumber>
    elseif action == 'check' then
        local identifier, name = resolveTarget(args[2])
        if not identifier then return Bank.notify(src, 'Banking', 'Target not found.', 'error') end

        local rows = MySQL.query.await(
            'SELECT account_number, type, label, balance, frozen FROM nz_bank_accounts WHERE owner = ?',
            { identifier }) or {}
        local credit = Bank.getCredit(identifier)

        local lines = { ('^5%s^7 · credit %s (%s)'):format(name or identifier, credit.score, Bank.creditBand(credit.score)) }
        for _, a in ipairs(rows) do
            lines[#lines + 1] = ('  %s  %s  %s%s%s'):format(
                a.account_number, a.type, Config.Currency, a.balance, a.frozen == 1 and '  [FROZEN]' or '')
        end
        local text = table.concat(lines, '\n')

        if src > 0 then
            TriggerClientEvent('chat:addMessage', src, { args = { 'BANK', text } })
        else
            print(text)
        end

    -- /bankadmin credit <playerId> <score>
    elseif action == 'credit' then
        local identifier = resolveTarget(args[2])
        local score = tonumber(args[3])
        if not identifier or not score then
            return Bank.notify(src, 'Banking', ('Usage: /%s credit <id> <score>'):format(Config.Admin.command), 'error')
        end
        score = math.max(Config.Credit.min, math.min(Config.Credit.max, math.floor(score)))
        MySQL.update.await('UPDATE nz_bank_credit SET score = ? WHERE identifier = ?', { score, identifier })
        Bank.notify(src, 'Banking', ('Credit score set to %s.'):format(score), 'success')

    -- /bankadmin wipeloans <playerId>
    elseif action == 'wipeloans' then
        local identifier = resolveTarget(args[2])
        if not identifier then return Bank.notify(src, 'Banking', 'Target not found.', 'error') end
        MySQL.update.await('UPDATE nz_bank_loans SET status = "paid", remaining = 0 WHERE identifier = ?', { identifier })
        Bank.notify(src, 'Banking', 'Loans cleared.', 'success')
        Bank.log('admin', 'Loans wiped', ('Target: `%s`'):format(identifier))

    else
        local help = ('Commands: /%s give|take <id|account> <amount> · freeze|unfreeze <id> · check <id> · credit <id> <score> · wipeloans <id>')
            :format(Config.Admin.command)
        if src > 0 then
            Bank.notify(src, 'Banking admin', help, 'inform')
        else
            print(help)
        end
    end
end, false)

-- society payout helper: /paysociety <amount> (boss-only, moves society -> personal)
RegisterCommand('paysociety', function(src, args)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return end
    if not Bank.canUseSociety(xPlayer.job.name, xPlayer.job.grade_name, xPlayer.job.isboss) then
        return Bank.notify(src, 'Banking', 'You cannot move society funds.', 'error')
    end

    local amount = Bank.round(tonumber(args[1]) or 0)
    if amount <= 0 then return Bank.notify(src, 'Banking', 'Usage: /paysociety <amount>', 'error') end

    local soc = Bank.getSociety(xPlayer.job.name)
    local personal = Bank.getPersonal(xPlayer.identifier)
    if not soc or not personal then return end

    local ok = Bank.debit(soc.id, amount, {
        category = 'transfer', label = ('Payout · %s'):format(Bank.fullName(xPlayer)),
        actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
    })
    if not ok then return Bank.notify(src, 'Banking', 'Not enough in the society account.', 'error') end

    Bank.credit(personal.id, amount, {
        category = 'payroll', label = ('Payout · %s'):format(soc.label)
    })
    Bank.notify(src, 'Banking', ('Moved %s%s to your account.'):format(Config.Currency, amount), 'success')
end, false)
