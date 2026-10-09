if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  ACCOUNTS · TRANSFERS · HISTORY
-- ═══════════════════════════════════════════════════════════

local function serialiseAccount(acc)
    return {
        id       = acc.id,
        number   = acc.account_number,
        type     = acc.type,
        label    = acc.label,
        balance  = acc.balance,
        frozen   = acc.frozen == 1,
        owner    = acc.owner,
        role     = acc.role or 'owner',
        can      = {
            deposit  = (acc.can_deposit  or 1) == 1,
            withdraw = (acc.can_withdraw or 1) == 1,
            transfer = (acc.can_transfer or 1) == 1
        },
        meta     = acc.meta and json.decode(acc.meta) or {}
    }
end

--- Monthly in/out for the cashflow chart (last 12 months).
local function cashflow(accountId)
    local rows = MySQL.query.await([[
        SELECT DATE_FORMAT(created_at, '%Y-%m') AS ym,
               direction,
               SUM(amount) AS total
        FROM nz_bank_transactions
        WHERE account_id = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
        GROUP BY ym, direction
    ]], { accountId }) or {}

    local months, order = {}, {}
    for i = 11, 0, -1 do
        local key = os.date('%Y-%m', os.time() - (i * 2592000))
        months[key] = { label = os.date('%b', os.time() - (i * 2592000)), income = 0, spending = 0 }
        order[#order + 1] = key
    end
    for _, r in ipairs(rows) do
        if months[r.ym] then
            if r.direction == 'in' then months[r.ym].income = tonumber(r.total) or 0
            else months[r.ym].spending = tonumber(r.total) or 0 end
        end
    end

    local out = {}
    for _, key in ipairs(order) do out[#out + 1] = months[key] end
    return out
end

local function monthTotals(accountId)
    local row = MySQL.single.await([[
        SELECT
          COALESCE(SUM(CASE WHEN direction = 'in'  THEN amount END), 0) AS income,
          COALESCE(SUM(CASE WHEN direction = 'out' THEN amount END), 0) AS spending
        FROM nz_bank_transactions
        WHERE account_id = ? AND created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')
    ]], { accountId })
    return tonumber(row and row.income) or 0, tonumber(row and row.spending) or 0
end

-- ═══════════════════════════════════════════════════════════
--  MAIN PAYLOAD
-- ═══════════════════════════════════════════════════════════
--- Read an optional part of the payload without letting it take the
--- whole thing down. A feature that errors comes back nil, which the
--- UI already treats as "not available", instead of leaving the
--- player looking at "your account is still being set up".
local function optional(name, fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end

    print(('^1[nayzeee-banking]^7 %s failed and was left out of the payload: %s')
        :format(name, tostring(result)))
    return nil
end

function Bank.buildPayload(src, context)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return nil end

    local identifier = xPlayer.identifier
    Bank.ensurePlayer(xPlayer)

    local societies = Bank.societyJobs(xPlayer)
    local accounts = Bank.getAccessible(identifier, societies)
    local personal = Bank.getPersonal(identifier)
    local savings  = Bank.getSavings(identifier)

    local list = {}
    for _, a in ipairs(accounts) do list[#list + 1] = serialiseAccount(a) end

    local income, spending = monthTotals(personal.id)

    local settings = MySQL.single.await('SELECT * FROM nz_bank_settings WHERE identifier = ?', { identifier }) or {}
    local credit   = MySQL.single.await('SELECT * FROM nz_bank_credit WHERE identifier = ?', { identifier }) or {}

    return {
        context   = context or 'bank',
        player    = {
            name  = Bank.fullName(xPlayer),
            jobs  = Bank.jobsFor(xPlayer),
            job   = xPlayer.job.label or xPlayer.job.name,
            grade = xPlayer.job.grade_label or '',
            cash  = Bank.getCash(xPlayer)
        },
        accounts  = list,
        primary   = personal and personal.id or nil,
        savingsId = savings and savings.id or nil,
        summary   = {
            balance  = personal and personal.balance or 0,
            savings  = savings and savings.balance or 0,
            income   = income,
            spending = spending
        },
        cashflow  = cashflow(personal.id),
        cards     = Bank.getCardsForPlayer(identifier, societies),
        loans     = optional('loans', Bank.getLoanState, identifier)
                    or { active = {}, defaulted = 0, defaultedOwed = 0 },
        credit    = {
            score = credit.score or Config.Credit.starting,
            band  = Bank.creditBand(credit.score or Config.Credit.starting),
            onTime = credit.on_time or 0,
            late   = credit.late or 0
        },
        savings   = Bank.getSavingsState(identifier),
        overdraft = optional('overdraft', Bank.getOverdraftState, identifier, personal),
        bills     = Bank.getBills(identifier),
        scheduled = optional('scheduled transfers', Bank.getScheduled, identifier),
        market    = optional('the market', Bank.getMarketState, identifier),
        payroll   = societies[1] and optional('payroll', Bank.getPayroll, societies[1]) or nil,
        settings  = {
            directDeposit = (settings.direct_deposit or 1) == 1,
            autoPayBills  = (settings.auto_pay_bills or 0) == 1,
            autoPayLoans  = (settings.auto_pay_loans or 1) == 1,
            notifications = (settings.notifications or 1) == 1
        },
        config    = {
            serverName      = Config.ServerName,
            ui              = Bank.uiConfig(),
            intro           = Config.Intro,
            features        = {
                cards   = Config.Cards.enabled,
                savings = Config.Savings.enabled,
                loans   = Config.Loans.enabled,
                bills   = Config.Bills.enabled,
                market  = Config.Market.enabled,
                overdraft  = Config.Overdraft and Config.Overdraft.enabled or false,
                statements = Config.Statements and Config.Statements.enabled or false,
            },
            currency        = Config.Currency,
            currencyRight   = Config.CurrencyRight or false,
            numberChangeCost= Config.Accounts.numberChangeCost or 0,
            payrollMode     = Config.Payroll.mode,
            hours           = Config.WorkingHours.enabled and {
                open = Config.WorkingHours.openHour, close = Config.WorkingHours.closeHour } or nil,
            transferFee     = Config.Accounts.transferFee,
            maxSharedMembers= Config.Accounts.maxSharedMembers,
            sharedCost      = Config.Accounts.sharedCreationCost,
            cardPrice       = Config.Cards.price,
            cardLimits      = Config.Cards.limitOptions,
            cardSkins       = Config.Cards.skins,
            maxCards        = Config.Cards.maxPerAccount,
            loanTiers       = Config.Loans.tiers,
            savingsRate     = Config.Savings.interestRate,
            intervals       = Bank.scheduleIntervals,
            statementPeriods= Bank.periodList and Bank.periodList() or {},
            atmMax          = Config.ATM.maxWithdraw,
            jointCardLimit  = Config.Cards.member.limit,
            cardTypes       = Config.CardTypes,
            creditCards     = {
                minPaymentPct = Config.CreditCards.minPaymentPct,
                dueMinutes    = Config.CreditCards.dueMinutes,
                lateFee       = Config.CreditCards.lateFee
            },
            version         = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
        }
    }
end

--- At a machine only the card's own account is on screen, the way a real ATM
--- works. That is also what lets someone else's card (and its PIN) work there.
local function atmView(src, payload)
    local atm = Bank.atmSession(src)
    if not atm or not atm.accountId then return payload end

    local acc = Bank.getAccountById(atm.accountId)
    if not acc then return payload end
    local view = serialiseAccount(acc)
    if atm.foreign then view.owner, view.role = nil, 'card' end

    -- the overdraft line belongs to the player's personal account; show it only for that one
    if atm.foreign or acc.id ~= payload.primary then payload.overdraft = nil end
    payload.accounts = { view }
    payload.primary = acc.id
    payload.summary.balance = acc.balance
    if atm.foreign then payload.cards, payload.payees = {}, {} end
    return payload
end

Bank.callback('nz_bank:getData', function(src, context)
    local payload = Bank.buildPayload(src, context)
    if not payload then return nil end
    payload.payees = Bank.getPayees(Bank.getPlayer(src).identifier)
    if context == 'atm' then payload = atmView(src, payload) end
    return payload
end)

--- Who may move this account's money from where the player is standing:
--- their own access, or the card in the ATM they are at.
local function moneyAccess(src, accountId, point)
    local atm = point == 'atm' and Bank.atmSession(src) or nil
    -- a machine with a card in it only works on that card's account
    if atm and atm.accountId and Bank.id(accountId) ~= atm.accountId then
        return nil, nil, 'This machine only works on the card\'s account.'
    end
    local acc, perms = Bank.access(src, accountId)
    if not acc then acc, perms = Bank.cardAccess(src, accountId) end
    if not acc then return nil, nil, 'You cannot use this account.' end
    return acc, perms, nil, atm
end

-- ═══════════════════════════════════════════════════════════
--  DEPOSIT / WITHDRAW
-- ═══════════════════════════════════════════════════════════
Bank.callback('nz_bank:deposit', function(src, accountId, amount)
    local xPlayer = Bank.getPlayer(src)
    amount = Bank.round(amount)
    if not xPlayer or amount <= 0 then return { ok = false, msg = 'Enter a valid amount.' } end

    local point, why = Bank.cashPoint(src)
    if not point then return { ok = false, msg = why } end

    local acc, perms, err = moneyAccess(src, accountId, point)
    if not acc then return { ok = false, msg = err } end
    if not perms.deposit then return { ok = false, msg = 'You do not have deposit rights here.' } end
    if acc.frozen == 1 then return { ok = false, msg = 'This account is frozen.' } end

    if acc.type == 'savings' and (acc.balance + amount) > Config.Savings.maxBalance then
        return { ok = false, msg = 'That exceeds the savings limit.' }
    end

    if Bank.getCash(xPlayer) < amount then
        return { ok = false, msg = 'You are not carrying that much cash.' }
    end
    if not Bank.removeCash(xPlayer, amount) then
        return { ok = false, msg = 'Could not take the cash.' }
    end

    local ok = Bank.credit(accountId, amount, {
        category = 'deposit',
        label    = acc.type == 'savings' and 'Savings deposit' or 'Account deposit',
        actor    = xPlayer.identifier,
        actorName= Bank.fullName(xPlayer)
    })
    if not ok then
        Bank.addCash(xPlayer, amount)
        return { ok = false, msg = 'Deposit failed. Cash returned.' }
    end

    if acc.type == 'savings' then Bank.trackSavings(acc.id, amount, 0) end

    Bank.log('deposit', 'Deposit',
        ('**%s** deposited **%s%s** into %s'):format(Bank.fullName(xPlayer), Config.Currency, amount, acc.label))

    return { ok = true, msg = ('Deposited %s%s.'):format(Config.Currency, amount) }
end)

Bank.callback('nz_bank:withdraw', function(src, accountId, amount)
    local xPlayer = Bank.getPlayer(src)
    amount = Bank.round(amount)
    if not xPlayer or amount <= 0 then return { ok = false, msg = 'Enter a valid amount.' } end

    -- the ATM fee and cap follow where the player really is, not what the client says
    local point, why = Bank.cashPoint(src)
    if not point then return { ok = false, msg = why } end
    local fromATM = point == 'atm'

    local acc, perms, err, atm = moneyAccess(src, accountId, point)
    if not acc then return { ok = false, msg = err } end
    if not perms.withdraw then return { ok = false, msg = 'You do not have withdrawal rights here.' } end
    if acc.frozen == 1 then return { ok = false, msg = 'This account is frozen.' } end

    local cap = Config.Accounts.withdrawLimits[acc.type] or 0
    if cap > 0 and amount > cap then
        return { ok = false, msg = ('Single withdrawals here are capped at %s%s.'):format(Config.Currency, cap) }
    end

    local fee = 0
    if fromATM then
        if amount > Config.ATM.maxWithdraw then
            return { ok = false, msg = ('ATMs release up to %s%s at a time.'):format(Config.Currency, Config.ATM.maxWithdraw) }
        end
        fee = Bank.round(amount * Config.ATM.withdrawFee)
    end
    if acc.type == 'savings' then
        fee = fee + Bank.round(amount * Config.Savings.withdrawFee)
    end

    -- someone else's card spends inside that card's daily limit
    if atm and atm.foreign and atm.cardId then
        local within, limitWhy = Bank.serial(Bank.cardKey(atm.cardId), Bank.spendOnCard, atm.cardId, amount)
        if not within then
            return { ok = false, msg = limitWhy == 'limit' and 'That would break the daily limit on this card.'
                or 'This card was declined.' }
        end
    end

    local ok, res = Bank.debit(accountId, amount + fee, {
        category = 'withdraw',
        label    = fromATM and 'ATM withdrawal' or 'Account withdrawal',
        actor    = xPlayer.identifier,
        actorName= Bank.fullName(xPlayer)
    })
    if not ok then
        return { ok = false, msg = res == 'insufficient' and 'Not enough in the account.' or 'Withdrawal failed.' }
    end

    -- no room for the cash (a full inventory): the money goes back in the account
    if not Bank.addCash(xPlayer, amount) then
        Bank.credit(accountId, amount + fee, { category = 'withdraw', label = 'Withdrawal reversed' })
        return { ok = false, msg = 'You have no room for the cash. Nothing was taken.' }
    end

    if fee > 0 then
        Bank.logTx(accountId, 'out', fee, res, { category = 'fee', label = 'Withdrawal fee' })
    end

    Bank.log('withdraw', 'Withdrawal',
        ('**%s** withdrew **%s%s** from %s%s'):format(
            Bank.fullName(xPlayer), Config.Currency, amount, acc.label, fromATM and ' (ATM)' or ''))

    return { ok = true, msg = ('Withdrew %s%s.'):format(Config.Currency, amount), fee = fee }
end)

-- ═══════════════════════════════════════════════════════════
--  TRANSFER
-- ═══════════════════════════════════════════════════════════
function Bank.doTransfer(fromId, toNumber, amount, actorId, actorName, label)
    amount = Bank.round(amount)
    if amount < Config.Accounts.minTransfer then return false, 'Amount is too small.' end
    if amount > Config.Accounts.maxTransfer then return false, 'Amount is too large.' end

    local target = Bank.getAccountByNumber(toNumber)
    if not target then return false, 'No account with that number.' end
    if target.id == fromId then return false, 'That is the same account.' end
    if target.frozen == 1 then return false, 'The receiving account is frozen.' end

    -- savings has a ceiling however the money arrives, not just as cash
    if target.type == 'savings' and (target.balance + amount) > Config.Savings.maxBalance then
        return false, 'That would take the savings account over its limit.'
    end

    local fee = Bank.round(amount * Config.Accounts.transferFee)

    -- the number and name go on the row too, so "pay them again"
    -- has something to work from later
    local ok, res = Bank.debit(fromId, amount + fee, {
        category = 'transfer',
        label    = label or ('Transfer to %s'):format(target.label),
        actor    = actorId,
        actorName= actorName,
        counterparty     = target.account_number,
        counterpartyName = target.label
    })
    if not ok then
        return false, res == 'insufficient' and 'Not enough in the account.' or 'Transfer failed.'
    end

    local credited = Bank.credit(target.id, amount, {
        category = 'transfer',
        label    = ('Transfer from %s'):format(actorName or 'account'),
        actor    = actorId,
        actorName= actorName
    })
    if not credited then
        -- roll the money back to the sender
        Bank.credit(fromId, amount + fee, { category = 'transfer', label = 'Transfer reversed' })
        return false, 'The receiving account rejected the transfer.'
    end

    if fee > 0 then
        Bank.logTx(fromId, 'out', fee, res, { category = 'fee', label = 'Transfer fee' })
    end

    -- ping the receiver if they are online
    if target.type == 'personal' or target.type == 'savings' then
        local rx = ESX.GetPlayerFromIdentifier(target.owner)
        if rx then
            Bank.notify(rx.source, 'Money received',
                ('%s%s from %s'):format(Config.Currency, amount, actorName or 'a transfer'), 'success')
        end
    end

    Bank.log('transfer', 'Transfer',
        ('**%s** sent **%s%s** to `%s` (%s)'):format(actorName or 'System', Config.Currency, amount, toNumber, target.label))

    return true, ('Sent %s%s to %s.'):format(Config.Currency, amount, target.label)
end

Bank.callback('nz_bank:transfer', function(src, accountId, toNumber, amount, note)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    local acc, perms = Bank.access(src, accountId)
    if not acc then acc, perms = Bank.cardAccess(src, accountId) end   -- a card and PIN at an ATM
    if not acc then return { ok = false, msg = 'You cannot use this account.' } end
    if not perms.transfer then return { ok = false, msg = 'You do not have transfer rights here.' } end

    local label = note and note ~= '' and ('Transfer · %s'):format(tostring(note):sub(1, 48)) or nil
    local ok, msg = Bank.doTransfer(acc.id, toNumber, amount, xPlayer.identifier, Bank.fullName(xPlayer), label)
    if ok then Bank.touchPayee(xPlayer.identifier, tostring(toNumber or ''):upper()) end
    return { ok = ok, msg = msg }
end)

-- ═══════════════════════════════════════════════════════════
--  SHARED ACCOUNTS
-- ═══════════════════════════════════════════════════════════
Bank.callback('nz_bank:createShared', function(src, label)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    label = (label or ''):gsub('[^%w%s%-&\'.]', ''):sub(1, 32)
    if #label < 3 then return { ok = false, msg = 'Pick a name of at least 3 characters.' } end

    local owned = MySQL.scalar.await(
        'SELECT COUNT(*) FROM nz_bank_accounts WHERE owner = ? AND type = "shared"', { xPlayer.identifier })
    if owned >= Config.Accounts.maxShared then
        return { ok = false, msg = ('You already own %s shared accounts.'):format(Config.Accounts.maxShared) }
    end

    local personal = Bank.getPersonal(xPlayer.identifier)
    local cost = Config.Accounts.sharedCreationCost
    if cost > 0 then
        local ok = Bank.debit(personal.id, cost, {
            category = 'fee', label = 'Shared account opened',
            actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
        })
        if not ok then
            return { ok = false, msg = ('Opening one costs %s%s.'):format(Config.Currency, cost) }
        end
    end

    local number = Bank.newAccountNumber('SHR')
    local id = MySQL.insert.await(
        'INSERT INTO nz_bank_accounts (account_number, type, owner, label, balance) VALUES (?, "shared", ?, ?, 0)',
        { number, xPlayer.identifier, label })

    MySQL.insert.await(
        'INSERT INTO nz_bank_members (account_id, identifier, name, role, can_deposit, can_withdraw, can_transfer) VALUES (?, ?, ?, "owner", 1, 1, 1)',
        { id, xPlayer.identifier, Bank.fullName(xPlayer) })

    return { ok = true, msg = ('%s is open.'):format(label), id = id }
end)

Bank.callback('nz_bank:getMembers', function(src, accountId)
    local acc = Bank.access(src, accountId)
    if not acc then return {} end
    return MySQL.query.await(
        'SELECT identifier, name, role, can_deposit, can_withdraw, can_transfer FROM nz_bank_members WHERE account_id = ? ORDER BY FIELD(role, "owner","manager","member"), name',
        { accountId }) or {}
end)

Bank.callback('nz_bank:addMember', function(src, accountId, targetSrc)
    local xPlayer = Bank.getPlayer(src)
    local acc, perms = Bank.access(src, accountId)
    if not acc or acc.type ~= 'shared' then return { ok = false, msg = 'Not a shared account.' } end
    if perms.role ~= 'owner' and perms.role ~= 'manager' then
        return { ok = false, msg = 'Only the owner can add members.' }
    end

    local target = ESX.GetPlayerFromId(tonumber(targetSrc))
    if not target then return { ok = false, msg = 'No player online with that ID.' } end
    if target.identifier == xPlayer.identifier then return { ok = false, msg = 'You are already on it.' } end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM nz_bank_members WHERE account_id = ?', { accountId })
    if count >= Config.Accounts.maxSharedMembers then
        return { ok = false, msg = 'This account is full.' }
    end

    local exists = MySQL.scalar.await(
        'SELECT id FROM nz_bank_members WHERE account_id = ? AND identifier = ?', { accountId, target.identifier })
    if exists then return { ok = false, msg = 'They are already a member.' } end

    MySQL.insert.await(
        'INSERT INTO nz_bank_members (account_id, identifier, name, role) VALUES (?, ?, ?, "member")',
        { accountId, target.identifier, Bank.fullName(target) })

    Bank.notify(target.source, 'Added to an account',
        ('%s added you to %s.'):format(Bank.fullName(xPlayer), acc.label), 'success')
    TriggerClientEvent('nz_bank:refresh', target.source)

    return { ok = true, msg = ('%s can now use this account.'):format(Bank.fullName(target)) }
end)

Bank.callback('nz_bank:removeMember', function(src, accountId, identifier)
    local acc, perms = Bank.access(src, accountId)
    if not acc or acc.type ~= 'shared' then return { ok = false, msg = 'Not a shared account.' } end
    if perms.role ~= 'owner' then return { ok = false, msg = 'Only the owner can remove members.' } end
    if type(identifier) ~= 'string' then return { ok = false, msg = 'Member not found.' } end
    if identifier == acc.owner then return { ok = false, msg = 'The owner cannot be removed.' } end

    MySQL.update.await('DELETE FROM nz_bank_members WHERE account_id = ? AND identifier = ?', { acc.id, identifier })

    -- their joint card stops working with them, and so do any standing
    -- orders they set up from this account
    MySQL.update.await(
        'UPDATE nz_bank_cards SET status = "blocked" WHERE account_id = ? AND holder_identifier = ? AND status = "active"',
        { acc.id, identifier })
    MySQL.update.await('DELETE FROM nz_bank_scheduled WHERE from_id = ? AND identifier = ?', { acc.id, identifier })

    local target = ESX.GetPlayerFromIdentifier(identifier)
    if target then TriggerClientEvent('nz_bank:refresh', target.source) end

    return { ok = true, msg = 'Member removed.' }
end)

Bank.callback('nz_bank:setMemberPerms', function(src, accountId, identifier, perms)
    local acc, mine = Bank.access(src, accountId)
    if not acc or acc.type ~= 'shared' then return { ok = false, msg = 'Not a shared account.' } end
    if mine.role ~= 'owner' then return { ok = false, msg = 'Only the owner can change permissions.' } end

    MySQL.update.await([[
        UPDATE nz_bank_members SET can_deposit = ?, can_withdraw = ?, can_transfer = ?
        WHERE account_id = ? AND identifier = ?
    ]], {
        perms.deposit and 1 or 0,
        perms.withdraw and 1 or 0,
        perms.transfer and 1 or 0,
        accountId, identifier
    })
    return { ok = true, msg = 'Permissions saved.' }
end)

Bank.callback('nz_bank:renameAccount', function(src, accountId, label)
    local acc, perms = Bank.access(src, accountId)
    if not acc then return { ok = false, msg = 'You cannot use this account.' } end
    if acc.type == 'personal' or acc.type == 'society' then
        return { ok = false, msg = 'This account cannot be renamed.' }
    end
    if perms.role ~= 'owner' then return { ok = false, msg = 'Only the owner can rename it.' } end

    label = (label or ''):gsub('[^%w%s%-&\'.]', ''):sub(1, 32)
    if #label < 3 then return { ok = false, msg = 'Pick a name of at least 3 characters.' } end

    MySQL.update.await('UPDATE nz_bank_accounts SET label = ? WHERE id = ?', { label, accountId })
    return { ok = true, msg = 'Renamed.' }
end)

local function closeShared(src, accountId)
    local xPlayer = Bank.getPlayer(src)
    local acc, perms = Bank.access(src, accountId)
    if not acc or acc.type ~= 'shared' then return { ok = false, msg = 'Not a shared account.' } end
    if perms.role ~= 'owner' then return { ok = false, msg = 'Only the owner can close it.' } end
    if acc.frozen == 1 then return { ok = false, msg = 'This account is frozen.' } end
    if acc.balance < 0 then return { ok = false, msg = 'Clear the negative balance first.' } end

    if acc.balance > 0 then
        local personal = Bank.getPersonal(xPlayer.identifier)
        local moved = Bank.debit(acc.id, acc.balance, { category = 'transfer', label = 'Account closed' })
        if not moved then return { ok = false, msg = 'The balance changed. Try again.' } end
        Bank.credit(personal.id, acc.balance, { category = 'transfer', label = ('Closed %s'):format(acc.label) })
    end

    -- money that landed while closing keeps the account open
    local gone = MySQL.update.await('DELETE FROM nz_bank_accounts WHERE id = ? AND balance = 0', { acc.id })
    if gone == 0 then return { ok = false, msg = 'Money arrived while closing. Try again.' } end
    return { ok = true, msg = 'Account closed and the balance moved to your personal account.' }
end

Bank.callback('nz_bank:closeShared', function(src, accountId)
    local res, busy = Bank.serial('close:' .. tostring(Bank.id(accountId)), closeShared, src, accountId)
    if res == false then return { ok = false, msg = busy } end
    return res
end)

-- ═══════════════════════════════════════════════════════════
--  HISTORY
-- ═══════════════════════════════════════════════════════════
Bank.callback('nz_bank:getTransactions', function(src, accountId, page, search, category)
    local acc = Bank.access(src, accountId)
    if not acc then return { rows = {}, pages = 0, total = 0 } end

    page = math.max(1, tonumber(page) or 1)
    local perPage = 8
    local offset = (page - 1) * perPage

    local where, args = 'account_id = ?', { accountId }
    if search and search ~= '' then
        where = where .. ' AND label LIKE ?'
        args[#args + 1] = '%' .. search:sub(1, 32) .. '%'
    end
    if category and category ~= 'all' then
        where = where .. ' AND category = ?'
        args[#args + 1] = category
    end

    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM nz_bank_transactions WHERE %s'):format(where), args) or 0

    local qArgs = { table.unpack(args) }
    qArgs[#qArgs + 1] = perPage
    qArgs[#qArgs + 1] = offset

    local rows = MySQL.query.await(([[
        SELECT id, category, direction, amount, label, actor_name,
               DATE_FORMAT(created_at, '%%d %%b - %%H:%%i') AS stamp
        FROM nz_bank_transactions WHERE %s ORDER BY id DESC LIMIT ? OFFSET ?
    ]]):format(where), qArgs) or {}

    local totals = MySQL.single.await(([[
        SELECT
          COALESCE(SUM(CASE WHEN direction = 'in'  THEN amount END), 0) AS income,
          COALESCE(SUM(CASE WHEN direction = 'out' THEN amount END), 0) AS spending
        FROM nz_bank_transactions WHERE %s
    ]]):format(where), args) or {}

    return {
        rows     = rows,
        page     = page,
        pages    = math.max(1, math.ceil(total / perPage)),
        total    = total,
        income   = tonumber(totals.income) or 0,
        spending = tonumber(totals.spending) or 0
    }
end)

--- Reissue your own account number. Useful after handing it out too widely.
Bank.callback('nz_bank:changeNumber', function(src, accountId)
    local xPlayer = Bank.getPlayer(src)
    local acc, perms = Bank.access(src, accountId)
    if not acc then return { ok = false, msg = 'You cannot use this account.' } end
    if acc.type == 'society' then return { ok = false, msg = 'Society numbers are fixed.' } end
    if perms.role ~= 'owner' then return { ok = false, msg = 'Only the owner can do this.' } end

    local cost = Config.Accounts.numberChangeCost or 0
    if cost > 0 then
        local paid = Bank.debit(accountId, cost, {
            category = 'fee', label = 'Account number reissued',
            actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
        })
        if not paid then
            return { ok = false, msg = ('A new number costs %s%s.'):format(Config.Currency, cost) }
        end
    end

    local kind = acc.type == 'savings' and 'SAV' or acc.type == 'shared' and 'SHR' or 'PSL'
    local number = Bank.newAccountNumber(kind)
    MySQL.update.await('UPDATE nz_bank_accounts SET account_number = ? WHERE id = ?', { number, accountId })

    -- scheduled transfers pointing at the old number would silently fail
    MySQL.update.await('UPDATE nz_bank_scheduled SET to_number = ? WHERE to_number = ?',
        { number, acc.account_number })

    return { ok = true, msg = ('Your new number is %s.'):format(number), number = number }
end)

-- ═══════════════════════════════════════════════════════════
--  SETTINGS
-- ═══════════════════════════════════════════════════════════
Bank.callback('nz_bank:saveSettings', function(src, settings)
    local identifier = Bank.identifier(src)
    if not identifier then return { ok = false } end

    MySQL.update.await([[
        UPDATE nz_bank_settings
        SET direct_deposit = ?, auto_pay_bills = ?, auto_pay_loans = ?, notifications = ?
        WHERE identifier = ?
    ]], {
        settings.directDeposit and 1 or 0,
        settings.autoPayBills and 1 or 0,
        settings.autoPayLoans and 1 or 0,
        settings.notifications and 1 or 0,
        identifier
    })
    return { ok = true, msg = 'Settings saved.' }
end)

-- ═══════════════════════════════════════════════════════════
--  PAYCHECK ROUTING
-- ═══════════════════════════════════════════════════════════
-- Hand a paycheck to this resource: TriggerEvent('nz_bank:paycheck', src, amount, jobLabel)
-- Server-side only. It is deliberately not a net event, or any client could pay itself.
-- With direct deposit off, wages always land in the bank.
AddEventHandler('nz_bank:paycheck', function(src, amount, jobLabel)
    local xPlayer = Bank.getPlayer(src)
    amount = Bank.round(amount)
    if not xPlayer or amount <= 0 then return end

    local toBank = true
    if Config.DirectDeposit.enabled then
        local s = MySQL.single.await('SELECT direct_deposit FROM nz_bank_settings WHERE identifier = ?',
            { xPlayer.identifier })
        if s then toBank = s.direct_deposit == 1 else toBank = Config.DirectDeposit.defaultToBank end
    end

    if toBank then
        local bonus = Config.DirectDeposit.enabled and Bank.round(amount * Config.DirectDeposit.bonus) or 0
        local acc = Bank.getPersonal(xPlayer.identifier)
        Bank.credit(acc.id, amount + bonus, {
            category = 'payroll',
            label    = ('Paycheck · %s'):format(jobLabel or xPlayer.job.label or 'Work')
        })
        Bank.notify(src, 'Paycheck', ('%s%s went into your account.'):format(Config.Currency, amount + bonus), 'success')
    else
        Bank.addCash(xPlayer, amount)
        Bank.notify(src, 'Paycheck', ('%s%s in cash.'):format(Config.Currency, amount), 'success')
    end
end)
