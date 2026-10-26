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

-- every score change and why, for the history chart and the credit report
MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nz_bank_credit_history` (
          `id`         INT(11) NOT NULL AUTO_INCREMENT,
          `identifier` VARCHAR(64) NOT NULL,
          `score`      INT(11) NOT NULL,
          `delta`      INT(11) NOT NULL,
          `reason`     VARCHAR(64) NOT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `identifier` (`identifier`, `id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

--- `reason`: a short line for the history ("Loan instalment on time").
function Bank.moveCredit(identifier, delta, column, reason)
    local row = Bank.getCredit(identifier)
    local score = math.max(Config.Credit.min, math.min(Config.Credit.max, row.score + delta))

    if score ~= row.score then
        MySQL.insert('INSERT INTO nz_bank_credit_history (identifier, score, delta, reason) VALUES (?, ?, ?, ?)',
            { identifier, score, score - row.score, tostring(reason or (delta > 0 and 'Score went up' or 'Score went down')):sub(1, 64) })
    end

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

-- ═══════════════════════════════════════════════════════════
--  CREDIT REPORT
--  The score, how it got there, and what is pushing it up or down,
--  in words a player can act on.
-- ═══════════════════════════════════════════════════════════
local function factor(key, label, value, note, impact)
    return { key = key, label = label, value = value, note = note, impact = impact }
end

function Bank.creditReport(identifier)
    local c = Bank.getCredit(identifier)
    local cur = Config.Currency
    local factors = {}

    -- 1. paying on time
    local onTime, late = c.on_time or 0, c.late or 0
    local paid = onTime + late
    local rate = paid > 0 and math.floor(onTime / paid * 100) or nil
    factors[#factors + 1] = factor('payments', 'Payment history',
        rate and ('%d%% on time'):format(rate) or 'No payments yet',
        rate and ('%d on time · %d late'):format(onTime, late) or 'Repaying a loan or a card on time builds this.',
        not rate and 'none' or rate >= 90 and 'good' or rate >= 75 and 'ok' or 'bad')

    -- 2. how much of the credit you have is in use
    local cards = MySQL.query.await([[
        SELECT c.balance, c.credit_limit FROM nz_bank_cards c
        JOIN nz_bank_accounts a ON a.id = c.account_id
        WHERE c.kind != 'debit' AND (c.holder_identifier = ? OR (c.holder_identifier IS NULL AND a.owner = ?))
    ]], { identifier, identifier }) or {}
    local owed, limit = 0, 0
    for _, r in ipairs(cards) do owed = owed + (r.balance or 0); limit = limit + (r.credit_limit or 0) end
    local use = limit > 0 and math.floor(owed / limit * 100) or nil
    factors[#factors + 1] = factor('use', 'Credit use',
        use and ('%d%% used'):format(use) or 'No credit cards',
        use and ('%s%s of %s%s across your cards. Under 30%% is best.'):format(cur, owed, cur, limit)
            or 'A credit card paid off each month helps your score.',
        not use and 'none' or use < 30 and 'good' or use < 60 and 'ok' or 'bad')

    -- 3. defaults
    local defaults = c.defaults or 0
    local open = MySQL.scalar.await('SELECT COUNT(*) FROM nz_bank_loans WHERE identifier = ? AND status = "defaulted"', { identifier }) or 0
    factors[#factors + 1] = factor('defaults', 'Defaults',
        defaults == 0 and 'None' or ('%d on record'):format(defaults),
        open > 0 and 'A defaulted loan is still unpaid. Settling it lifts the block on borrowing.'
            or defaults > 0 and 'Settled, but they still count against you.' or 'You have never defaulted.',
        open > 0 and 'bad' or defaults > 0 and 'ok' or 'good')

    -- 4. borrowing right now
    local loan = MySQL.single.await('SELECT COUNT(*) AS n, COALESCE(SUM(remaining), 0) AS left_ FROM nz_bank_loans WHERE identifier = ? AND status = "active"', { identifier }) or {}
    local n = tonumber(loan.n) or 0
    factors[#factors + 1] = factor('loans', 'Borrowing',
        n == 0 and 'No loans' or ('%d active'):format(n),
        n == 0 and 'Nothing owed on loans.' or ('%s%s still to repay. Paying on time raises your score.'):format(cur, tonumber(loan.left_) or 0),
        n == 0 and 'none' or 'ok')

    -- 5. overdraft
    local personal = Bank.getPersonal(identifier)
    local overdrawn = personal and personal.balance < 0
    factors[#factors + 1] = factor('overdraft', 'Overdraft',
        overdrawn and ('%s%s overdrawn'):format(cur, -personal.balance) or 'In credit',
        overdrawn and 'Getting back above zero ends the overdraft.' or 'Your account is not overdrawn.',
        overdrawn and 'bad' or 'good')

    -- 6. how long they have been building it
    local first = MySQL.single.await([[
        SELECT UNIX_TIMESTAMP(MIN(created_at)) AS since, COUNT(*) AS n FROM nz_bank_credit_history WHERE identifier = ?
    ]], { identifier }) or {}
    local days = first.since and math.floor((os.time() - tonumber(first.since)) / 86400) or 0
    factors[#factors + 1] = factor('age', 'Credit history',
        (tonumber(first.n) or 0) == 0 and 'New' or days < 1 and 'Under a day' or ('%d day%s'):format(days, days == 1 and '' or 's'),
        ('%d change%s on record.'):format(tonumber(first.n) or 0, (tonumber(first.n) or 0) == 1 and '' or 's'),
        days >= 14 and 'good' or (tonumber(first.n) or 0) > 0 and 'ok' or 'none')

    -- the history, oldest first, for the chart
    local rows = MySQL.query.await([[
        SELECT score, delta, reason, DATE_FORMAT(created_at, '%d %b %H:%i') AS stamp FROM nz_bank_credit_history
        WHERE identifier = ? ORDER BY id DESC LIMIT 40
    ]], { identifier }) or {}
    local history = {}
    for i = #rows, 1, -1 do history[#history + 1] = rows[i] end

    return {
        score   = c.score,
        band    = Bank.creditBand(c.score),
        min     = Config.Credit.min,
        max     = Config.Credit.max,
        bands   = Config.Credit.bands,
        factors = factors,
        history = history,
        issued  = os.date('%d %b %Y - %H:%M'),
    }
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
        Bank.moveCredit(loan.identifier, Config.Credit.loanCleared, nil, 'Loan paid off')
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
        Bank.moveCredit(identifier, Config.Credit.loanOnTime, 'on_time', 'Loan instalment on time')
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
        Bank.moveCredit(loan.identifier, Config.Credit.loanLate, 'late', 'Loan instalment missed')

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
            Bank.moveCredit(loan.identifier, Config.Credit.loanDefault, 'defaults', 'Loan defaulted')

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

        Bank.moveCredit(xPlayer.identifier, 40, nil, 'Defaulted debt settled')
        return { ok = true, msg = 'Debt settled. You can borrow again once the cooling-off period is up.' }
    end)
end)
