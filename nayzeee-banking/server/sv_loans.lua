if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  LOANS · CREDIT
-- ═══════════════════════════════════════════════════════════

-- One loan operation at a time. Without this, two fast clicks both read the
-- loan as active, both debit, and the player pays twice — or clears the same
-- loan twice and banks the credit gain for each.
local pending = {}

local function claim(key)
    if pending[key] then return false end
    pending[key] = true
    return true
end

local function release(key)
    pending[key] = nil
end

function Bank.creditBand(score)
    for _, b in ipairs(Config.Credit.bands) do
        if score >= b.min then return b.label end
    end
    return 'Poor'
end

function Bank.getCredit(identifier)
    local row = MySQL.single.await('SELECT * FROM nz_bank_credit WHERE identifier = ?', { identifier })
    if not row then
        MySQL.insert.await('INSERT IGNORE INTO nz_bank_credit (identifier, score) VALUES (?, ?)',
            { identifier, Config.Credit.starting })
        return { identifier = identifier, score = Config.Credit.starting, on_time = 0, late = 0, defaults = 0 }
    end
    return row
end

function Bank.moveCredit(identifier, delta, column)
    local row = Bank.getCredit(identifier)
    local score = math.max(Config.Credit.min, math.min(Config.Credit.max, row.score + delta))

    if column then
        MySQL.update.await(
            ('UPDATE nz_bank_credit SET score = ?, %s = %s + 1 WHERE identifier = ?'):format(column, column),
            { score, identifier })
    else
        MySQL.update.await('UPDATE nz_bank_credit SET score = ? WHERE identifier = ?', { score, identifier })
    end

    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if xPlayer then TriggerClientEvent('nz_bank:refresh', xPlayer.source) end
    return score
end

function Bank.getLoanState(identifier)
    local loans = MySQL.query.await(
        'SELECT * FROM nz_bank_loans WHERE identifier = ? AND status = "active"', { identifier }) or {}

    local out = {}
    for _, l in ipairs(loans) do
        local secondsLeft = math.max(0, l.next_payment - os.time())
        out[#out + 1] = {
            id         = l.id,
            tier       = l.tier,
            principal  = l.principal,
            totalOwed  = l.total_owed,
            remaining  = l.remaining,
            payment    = l.payment,
            interest   = l.interest,
            termDays   = l.term_days,
            missed     = l.missed,
            nextIn     = math.floor(secondsLeft / 60),
            daysLeft   = math.max(0, math.ceil(l.remaining / math.max(1, l.payment)))
        }
    end

    local bad = MySQL.single.await(
        'SELECT id, remaining FROM nz_bank_loans WHERE identifier = ? AND status = "defaulted" ORDER BY id ASC LIMIT 1',
        { identifier })

    return {
        active        = out,
        defaulted     = bad and 1 or 0,
        defaultedId   = bad and bad.id or nil,
        defaultedOwed = bad and bad.remaining or 0
    }
end

-- ═══════════════════════════════════════════════════════════
--  TAKE A LOAN
-- ═══════════════════════════════════════════════════════════
local function requestLoan(xPlayer, tierId)
    local identifier = xPlayer.identifier

    local tier
    for _, t in ipairs(Config.Loans.tiers) do if t.id == tierId then tier = t break end end
    if not tier then return { ok = false, msg = 'Unknown loan type.' } end

    local active = MySQL.scalar.await(
        'SELECT COUNT(*) FROM nz_bank_loans WHERE identifier = ? AND status = "active"', { identifier }) or 0
    if active >= Config.Loans.maxActive then
        return { ok = false, msg = 'Clear your current loan before taking another.' }
    end

    -- cooling-off period after the last one was settled
    local cooldown = (Config.Loans.cooldownMinutes or 0) * 60
    if cooldown > 0 and Bank.schema.loanChurn then
        -- pcall so an un-patched database degrades instead of hanging the UI
        local ok, lastClosed = pcall(function()
            return MySQL.scalar.await([[
                SELECT closed_at FROM nz_bank_loans
                WHERE identifier = ? AND status = 'paid' ORDER BY closed_at DESC LIMIT 1
            ]], { identifier })
        end)

        if not ok then
            print('^3[nayzeee-banking]^7 nz_bank_loans is missing the anti-churn columns — run install/update.sql')
            lastClosed = 0
        end
        lastClosed = lastClosed or 0

        local waited = os.time() - lastClosed
        if lastClosed > 0 and waited < cooldown then
            local left = math.ceil((cooldown - waited) / 60)
            return { ok = false, msg = ('The bank will not lend again for another %s minutes.'):format(left) }
        end
    end

    if Config.Loans.blacklistOnDefault then
        local bad = MySQL.scalar.await(
            'SELECT COUNT(*) FROM nz_bank_loans WHERE identifier = ? AND status = "defaulted"', { identifier }) or 0
        if bad > 0 then
            return { ok = false, msg = 'You have a defaulted loan on file. Settle it first.' }
        end
    end

    local credit = Bank.getCredit(identifier)
    if credit.score < tier.minCredit then
        return { ok = false, msg = ('Your credit score needs to be %s or higher for this one.'):format(tier.minCredit) }
    end

    local acc = Bank.getPersonal(identifier)
    if not acc then return { ok = false, msg = 'Your account is still being set up.' } end
    local totalOwed = Bank.round(tier.amount * (1 + tier.interest))

    -- started_at only exists on a patched database. Writing to a
    -- column that is not there fails the insert, which would take
    -- the money and leave the player with no loan.
    local loanId
    if Bank.schema.loanChurn then
        loanId = MySQL.insert.await([[
            INSERT INTO nz_bank_loans
              (identifier, account_id, tier, principal, total_owed, remaining, payment, interest,
               term_days, next_payment, started_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            identifier, acc.id, tier.id, tier.amount, totalOwed, totalOwed,
            tier.payment, tier.interest, tier.termDays,
            os.time() + (Config.Loans.paymentIntervalMin * 60),
            os.time()
        })
    else
        loanId = MySQL.insert.await([[
            INSERT INTO nz_bank_loans
              (identifier, account_id, tier, principal, total_owed, remaining, payment, interest,
               term_days, next_payment)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            identifier, acc.id, tier.id, tier.amount, totalOwed, totalOwed,
            tier.payment, tier.interest, tier.termDays,
            os.time() + (Config.Loans.paymentIntervalMin * 60)
        })
    end

    if not loanId then return { ok = false, msg = 'The bank could not open the loan. Try again.' } end

    -- the fee comes off what actually lands, so churning costs money
    local fee = Bank.round(tier.amount * (Config.Loans.originationFee or 0))
    local paid, newBal = Bank.credit(acc.id, tier.amount - fee, {
        category = 'loan', label = ('%s loan'):format(tier.label),
        actor = identifier, actorName = Bank.fullName(xPlayer)
    })
    if not paid then
        -- no payout, no debt: a frozen or busy account must not be left owing
        MySQL.update.await('DELETE FROM nz_bank_loans WHERE id = ?', { loanId })
        return { ok = false, msg = newBal == 'frozen'
            and 'Your account is frozen.'
            or 'The bank could not pay the loan out. Try again.' }
    end
    if fee > 0 then
        Bank.logTx(acc.id, 'out', fee, newBal, { category = 'fee', label = 'Loan arrangement fee' })
    end

    Bank.log('loans', 'Loan approved',
        ('**%s** took a %s loan of **%s%s** (owes %s%s)'):format(
            Bank.fullName(xPlayer), tier.label, Config.Currency, tier.amount, Config.Currency, totalOwed))

    return { ok = true, msg = ('%s approved. %s%s is in your account.'):format(
        tier.label, Config.Currency, tier.amount - fee) }
end

Bank.callback('nz_bank:requestLoan', function(src, tierId)
    if not Config.Loans.enabled then return { ok = false, msg = 'Loans are closed right now.' } end

    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    local key = 'req:' .. xPlayer.identifier
    if not claim(key) then
        return { ok = false, msg = 'That request is already going through.' }
    end

    -- released on every way out, errors included, or the player is
    -- locked out of borrowing until a restart
    local ok, res = pcall(requestLoan, xPlayer, tierId)
    release(key)
    if not ok then error(res, 0) end
    return res
end)

-- ═══════════════════════════════════════════════════════════
--  PAY
-- ═══════════════════════════════════════════════════════════
--- Close a loan, whatever state the database schema is in. The
--- conditional WHERE is what stops a second click settling it twice,
--- so this must succeed even without the anti-churn columns.
local function closeLoan(loanId, fromStatus)
    if Bank.schema.loanChurn then
        return MySQL.update.await(
            'UPDATE nz_bank_loans SET status = "paid", remaining = 0, closed_at = ? WHERE id = ? AND status = ?',
            { os.time(), loanId, fromStatus })
    end
    return MySQL.update.await(
        'UPDATE nz_bank_loans SET status = "paid", remaining = 0 WHERE id = ? AND status = ?',
        { loanId, fromStatus })
end

local function settleLoan(loan, xPlayer)
    -- conditional, so a second call finds nothing left to settle
    local changed = closeLoan(loan.id, 'active')

    if not changed or changed == 0 then return false end

    local held = os.time() - (loan.started_at or os.time())
    local longEnough = held >= ((Config.Loans.minHoldMinutes or 0) * 60)
    local paidEnough = (loan.paid_count or 0) >= (Config.Loans.minPaymentsForCredit or 0)
    local earned = longEnough and paidEnough

    if earned then
        Bank.moveCredit(loan.identifier, Config.Credit.loanCleared)
    end

    if xPlayer then
        Bank.notify(xPlayer.source, 'Loan cleared',
            earned and 'The balance is settled and your credit improved.'
                   or 'The balance is settled. Carrying it longer would have built your credit.',
            'success')
    end
    Bank.log('loans', 'Loan cleared',
        ('Loan #%s settled%s'):format(loan.id, earned and '' or ' (no credit gain — closed early)'))
    return true
end

--- Pay a chunk toward a loan. amount = nil pays the scheduled instalment.
--- Caller holds the loan's lock; Bank.payLoan below takes it for you.
local function payLoanNow(identifier, loanId, amount, auto)
    local loan = MySQL.single.await('SELECT * FROM nz_bank_loans WHERE id = ? AND status = "active"', { loanId })
    if not loan then return false, 'No active loan.' end
    if loan.identifier ~= identifier then return false, 'That loan is not yours.' end

    amount = Bank.round(amount or loan.payment)
    if amount <= 0 then return false, 'Enter a valid amount.' end
    if amount > loan.remaining then amount = loan.remaining end

    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    local ok = Bank.debit(loan.account_id, amount, {
        category = 'loan', label = 'Loan payment',
        actor = identifier, actorName = xPlayer and Bank.fullName(xPlayer) or 'Auto-pay'
    })
    if not ok then return false, 'Not enough in your account.' end

    local remaining = loan.remaining - amount
    local cycle = Config.Loans.paymentIntervalMin * 60

    -- a payment only counts toward credit once per cycle, and only if it
    -- actually covers the instalment. Otherwise a player spams small
    -- payments and farms score.
    local sinceCredit = os.time() - (loan.last_credit or 0)
    local counts = amount >= loan.payment and sinceCredit >= (cycle * 0.8)

    -- conditional on it still being open, and on nothing else having
    -- paid since the read, so a payment can never land on a settled loan
    local changed
    if Bank.schema.loanChurn then
        changed = MySQL.update.await([[
            UPDATE nz_bank_loans
            SET remaining = ?, next_payment = ?, missed = 0,
                last_credit = ?, paid_count = paid_count + ?
            WHERE id = ? AND status = 'active' AND remaining = ?
        ]], {
            remaining,
            os.time() + cycle,
            counts and os.time() or (loan.last_credit or 0),
            counts and 1 or 0,
            loan.id, loan.remaining
        })
    else
        changed = MySQL.update.await(
            'UPDATE nz_bank_loans SET remaining = ?, next_payment = ?, missed = 0 WHERE id = ? AND status = "active" AND remaining = ?',
            { remaining, os.time() + cycle, loan.id, loan.remaining })
    end

    if not changed or changed == 0 then
        Bank.credit(loan.account_id, amount, { category = 'loan', label = 'Duplicate payment refunded' })
        return false, 'That loan changed while paying. Nothing was taken.'
    end

    if counts then
        Bank.moveCredit(identifier, Config.Credit.loanOnTime, 'on_time')
    end

    if remaining <= 0 then
        loan.paid_count = (loan.paid_count or 0) + (counts and 1 or 0)
        settleLoan(loan, xPlayer)
        return true, 'Loan cleared.'
    end

    return true, ('Paid %s%s. %s%s to go.'):format(Config.Currency, amount, Config.Currency, remaining)
end

--- Lock key for one loan. '05' and 5 are the same loan.
local function loanKey(loanId)
    return 'loan:' .. tostring(loanId)
end

function Bank.payLoan(identifier, loanId, amount, auto)
    loanId = Bank.id(loanId)
    if not loanId then return false, 'No active loan.' end
    return Bank.serial(loanKey(loanId), payLoanNow, identifier, loanId, amount, auto)
end

--- Run one player action on one loan. A second click while the first is
--- still going is turned away; auto-pay or an export touching the same
--- loan waits its turn on the loan's lock instead.
local function withLoan(loanId, busyMsg, fn)
    loanId = Bank.id(loanId)
    if not loanId then return { ok = false, msg = 'No active loan.' } end
    if not claim(loanId) then return { ok = false, msg = busyMsg } end

    local ok, res, why = pcall(Bank.serial, loanKey(loanId), fn, loanId)
    release(loanId)

    if not ok then error(res, 0) end
    if res == false then return { ok = false, msg = why } end
    return res
end

Bank.callback('nz_bank:payLoan', function(src, loanId, amount)
    local identifier = Bank.identifier(src)
    if not identifier then return { ok = false, msg = 'Player not found.' } end

    return withLoan(loanId, 'That payment is already going through.', function(id)
        local ok, msg = payLoanNow(identifier, id, amount, false)
        return { ok = ok, msg = msg }
    end)
end)

Bank.callback('nz_bank:payOffLoan', function(src, loanId)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    return withLoan(loanId, 'That is already going through.', function(id)
        local loan = MySQL.single.await('SELECT * FROM nz_bank_loans WHERE id = ? AND status = "active"', { id })
        if not loan or loan.identifier ~= xPlayer.identifier then
            return { ok = false, msg = 'No active loan.' }
        end

        -- discount the untouched interest portion
        local interestPart = loan.total_owed - loan.principal
        local discount = Bank.round(math.min(loan.remaining, interestPart) * Config.Loans.earlyPayoffDiscount)
        local due = math.max(0, loan.remaining - discount)

        local ok = Bank.debit(loan.account_id, due, {
            category = 'loan', label = 'Loan paid off',
            actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
        })
        if not ok then
            return { ok = false, msg = ('You need %s%s to close this loan.'):format(Config.Currency, due) }
        end

        if not settleLoan(loan, xPlayer) then
            -- somebody else closed it first, so give the money back
            Bank.credit(loan.account_id, due, { category = 'loan', label = 'Duplicate payment refunded' })
            return { ok = false, msg = 'That loan was already settled.' }
        end

        return { ok = true, msg = discount > 0
            and ('Loan closed. You saved %s%s in interest.'):format(Config.Currency, discount)
            or 'Loan closed.' }
    end)
end)

Bank.callback('nz_bank:cancelLoan', function(src, loanId)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    return withLoan(loanId, 'That is already going through.', function(id)
        local loan = MySQL.single.await('SELECT * FROM nz_bank_loans WHERE id = ? AND status = "active"', { id })
        if not loan or loan.identifier ~= xPlayer.identifier then
            return { ok = false, msg = 'No active loan.' }
        end

        -- cancelling early means paying the remaining balance in full
        local ok = Bank.debit(loan.account_id, loan.remaining, {
            category = 'loan', label = 'Loan cancelled',
            actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
        })
        if not ok then
            return { ok = false, msg = ('Cancelling costs the full %s%s balance.'):format(Config.Currency, loan.remaining) }
        end

        if not settleLoan(loan, xPlayer) then
            Bank.credit(loan.account_id, loan.remaining, { category = 'loan', label = 'Duplicate payment refunded' })
            return { ok = false, msg = 'That loan was already settled.' }
        end
        return { ok = true, msg = 'Loan cancelled and settled.' }
    end)
end)

-- ═══════════════════════════════════════════════════════════
--  REPAYMENT LOOP
-- ═══════════════════════════════════════════════════════════
--- One instalment falling due. Runs under the loan's lock and re-reads
--- it, so a payment the player made since the loop's query is counted.
local function collectDue(loanId)
    local loan = MySQL.single.await(
        'SELECT * FROM nz_bank_loans WHERE id = ? AND status = "active" AND next_payment <= ?', { loanId, os.time() })
    if not loan then return end

    local xPlayer = ESX.GetPlayerFromIdentifier(loan.identifier)

    -- skip offline borrowers entirely when configured that way
    if not xPlayer and not Config.Loans.chargeOffline then
        MySQL.update.await('UPDATE nz_bank_loans SET next_payment = ? WHERE id = ?',
            { os.time() + (Config.Loans.paymentIntervalMin * 60), loan.id })
        return
    end
    local settings = MySQL.single.await(
        'SELECT auto_pay_loans FROM nz_bank_settings WHERE identifier = ?', { loan.identifier })
    local autoPay = Config.Loans.autoPay and (not settings or settings.auto_pay_loans == 1)

    local paid = false
    if autoPay then
        local acc = Bank.getAccountById(loan.account_id)
        local amount = math.min(loan.payment, loan.remaining)
        if acc and acc.balance >= amount then
            paid = select(1, payLoanNow(loan.identifier, loan.id, amount, true))
            if paid and xPlayer then
                Bank.notify(xPlayer.source, 'Loan payment',
                    ('%s%s was taken for your loan.'):format(Config.Currency, amount), 'inform')
            end
        end
    end

    if not paid then
        local missed = loan.missed + 1
        MySQL.update.await('UPDATE nz_bank_loans SET missed = ?, next_payment = ? WHERE id = ? AND status = "active"', {
            missed, os.time() + (Config.Loans.paymentIntervalMin * 60), loan.id
        })
        Bank.moveCredit(loan.identifier, Config.Credit.loanLate, 'late')

        if xPlayer then
            Bank.notify(xPlayer.source, 'Missed loan payment',
                ('Payment %s of %s missed. Your credit took a hit.'):format(missed, Config.Loans.missedBeforeDefault),
                'error')
        end

        if missed >= Config.Loans.missedBeforeDefault then
            local penalty = Bank.round(loan.remaining * Config.Loans.defaultPenalty)
            MySQL.update.await(
                'UPDATE nz_bank_loans SET status = "defaulted", remaining = ? WHERE id = ? AND status = "active"',
                { loan.remaining + penalty, loan.id })
            Bank.moveCredit(loan.identifier, Config.Credit.loanDefault, 'defaults')

            if xPlayer then
                Bank.notify(xPlayer.source, 'Loan defaulted',
                    'Your loan is in default and a penalty has been added.', 'error')
            end
            Bank.log('loans', 'Loan defaulted',
                ('Loan #%s defaulted · penalty %s%s'):format(loan.id, Config.Currency, penalty))
        end
    end
end

CreateThread(function()
    while true do
        Wait(60000)
        if Config.Loans.enabled then
            local ok, due = pcall(MySQL.query.await,
                'SELECT id FROM nz_bank_loans WHERE status = "active" AND next_payment <= ?', { os.time() })
            if not ok then
                print('^1[nayzeee-banking]^7 loan repayments failed: ' .. tostring(due))
                due = {}
            end

            for _, row in ipairs(due or {}) do
                local ran, err = pcall(Bank.serial, loanKey(row.id), collectDue, row.id)
                if not ran then print('^1[nayzeee-banking]^7 loan repayment failed: ' .. tostring(err)) end
            end
        end
    end
end)

--- Settle a defaulted loan (unblocks new borrowing).
Bank.callback('nz_bank:settleDefault', function(src, loanId)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    return withLoan(loanId, 'That is already going through.', function(id)
        local loan = MySQL.single.await('SELECT * FROM nz_bank_loans WHERE id = ? AND status = "defaulted"', { id })
        if not loan or loan.identifier ~= xPlayer.identifier then
            return { ok = false, msg = 'No defaulted loan.' }
        end

        local acc = Bank.getPersonal(xPlayer.identifier)
        local ok = acc and Bank.debit(acc.id, loan.remaining, {
            category = 'loan', label = 'Default settled',
            actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
        })
        if not ok then
            return { ok = false, msg = ('Settling costs %s%s.'):format(Config.Currency, loan.remaining) }
        end

        -- conditional, so a second click cannot charge again
        local changed = closeLoan(loan.id, 'defaulted')
        if not changed or changed == 0 then
            Bank.credit(acc.id, loan.remaining, { category = 'loan', label = 'Duplicate payment refunded' })
            return { ok = false, msg = 'That debt was already settled.' }
        end

        Bank.moveCredit(xPlayer.identifier, 40)
        return { ok = true, msg = 'Debt settled. You can borrow again once the cooling-off period is up.' }
    end)
end)
