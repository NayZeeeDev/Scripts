if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  BANK STATEMENTS
--
--  A statement for a period: what the account opened at, what came
--  in and went out broken down by where it went, and every line
--  behind it. The opening figure is read off the balance_after
--  column of the last transaction before the period rather than
--  being worked backwards from today, so a statement of an old
--  month stays correct no matter what has happened since.
--
--  The same call serves the bank UI, the ATM's receipt slot and the
--  phone, so there is one definition of what a statement is.
-- ═══════════════════════════════════════════════════════════

local PERIODS = {
    day   = { label = 'Last 24 hours', seconds = 86400 },
    week  = { label = 'Last 7 days',   seconds = 604800 },
    month = { label = 'Last 30 days',  seconds = 2592000 },
    all   = { label = 'Everything',    seconds = nil },
}

local CATEGORY_LABEL = {
    deposit  = 'Deposits',
    withdraw = 'Withdrawals',
    transfer = 'Transfers',
    card     = 'Card spending',
    bill     = 'Bills',
    loan     = 'Loan payments',
    payroll  = 'Wages',
    interest = 'Interest',
    fee      = 'Fees',
    admin    = 'Adjustments',
}

function Bank.periodList()
    local out = {}
    for id, p in pairs(PERIODS) do
        out[#out + 1] = { id = id, label = p.label }
    end
    table.sort(out, function(a, b) return (PERIODS[a.id].seconds or math.huge) < (PERIODS[b.id].seconds or math.huge) end)
    return out
end

--- Build a statement. Returns nil when the account is not readable.
function Bank.buildStatement(accountId, periodId, limit)
    local period = PERIODS[periodId] or PERIODS.week
    local acc = Bank.getAccountById(accountId)
    if not acc then return nil end

    local from = period.seconds and (os.time() - period.seconds) or nil
    local fromSql = from and os.date('!%Y-%m-%d %H:%M:%S', from) or nil

    -- The balance the account carried into the period: the running
    -- balance after the last movement before it started. No rows
    -- before it means the account opened at zero.
    local opening = 0
    if fromSql then
        local prior = MySQL.single.await([[
            SELECT balance_after FROM nz_bank_transactions
            WHERE account_id = ? AND created_at < ?
            ORDER BY id DESC LIMIT 1
        ]], { accountId, fromSql })
        opening = prior and tonumber(prior.balance_after) or 0
    end

    -- Totals by category, both directions
    local sums = MySQL.query.await(([[
        SELECT category, direction, SUM(amount) AS total, COUNT(*) AS count
        FROM nz_bank_transactions
        WHERE account_id = ? %s
        GROUP BY category, direction
    ]]):format(fromSql and 'AND created_at >= ?' or ''),
        fromSql and { accountId, fromSql } or { accountId }) or {}

    local income, spending, breakdown = 0, 0, {}
    for _, row in ipairs(sums) do
        local total = tonumber(row.total) or 0
        if row.direction == 'in' then income = income + total else spending = spending + total end

        local key = row.category .. ':' .. row.direction
        breakdown[#breakdown + 1] = {
            key       = key,
            category  = row.category,
            label     = CATEGORY_LABEL[row.category] or row.category,
            direction = row.direction,
            amount    = total,
            count     = tonumber(row.count) or 0
        }
    end

    table.sort(breakdown, function(a, b) return a.amount > b.amount end)

    -- The lines themselves, oldest first so the running balance reads
    -- down the page the way a real statement does.
    local rows = MySQL.query.await(([[
        SELECT direction, amount, balance_after, label, category, %s
               DATE_FORMAT(created_at, '%%d %%b - %%H:%%i') AS stamp
        FROM nz_bank_transactions
        WHERE account_id = ? %s
        ORDER BY id ASC
        LIMIT ?
    ]]):format(
        Bank.schema.counterparty and 'counterparty_name,' or '',
        fromSql and 'AND created_at >= ?' or ''),
        fromSql and { accountId, fromSql, limit or 250 } or { accountId, limit or 250 }) or {}

    return {
        account   = {
            id     = acc.id,
            number = acc.account_number,
            label  = acc.label,
            type   = acc.type
        },
        period    = { id = periodId or 'week', label = period.label },
        issued    = os.date('%d %b %Y - %H:%M'),
        opening   = opening,
        closing   = acc.balance,
        income    = income,
        spending  = spending,
        net       = income - spending,
        breakdown = breakdown,
        rows      = rows,
        count     = #rows,
        truncated = #rows >= (limit or 250),
        server    = Config.ServerName
    }
end

Bank.callback('nz_bank:accountStatement', function(src, accountId, periodId)
    if not Config.Statements or not Config.Statements.enabled then
        return { ok = false, msg = 'Statements are not offered here.' }
    end

    -- A nil id builds an empty parameter table in Lua, which does not
    -- match the placeholder and makes oxmysql throw. Cheaper to say no.
    accountId = tonumber(accountId)
    if not accountId then return { ok = false, msg = 'No account to read.' } end

    local acc = Bank.access(src, accountId)
    if not acc then return { ok = false, msg = 'You cannot read that account.' } end

    local statement = Bank.buildStatement(accountId, periodId,
        Config.Statements.maxRows or 250)
    if not statement then return { ok = false, msg = 'No statement available.' } end

    local fee = Config.Statements.fee or 0
    if fee > 0 then
        local paid = Bank.debit(accountId, fee, {
            category  = 'fee',
            label     = 'Statement fee',
            actor     = Bank.identifier(src),
            actorName = 'Statement'
        })
        if not paid then return { ok = false, msg = 'Not enough to cover the statement fee.' } end
        statement.fee = fee
    end

    return { ok = true, statement = statement }
end)

exports('getStatement', function(accountId, periodId)
    return Bank.buildStatement(accountId, periodId, Config.Statements and Config.Statements.maxRows or 250)
end)
