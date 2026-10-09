if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  BILLS · SCHEDULED TRANSFERS
-- ═══════════════════════════════════════════════════════════

function Bank.getBills(identifier)
    local rows = MySQL.query.await([[
        SELECT id, issuer_label, sender_name, amount, reason, status, due_at,
               DATE_FORMAT(created_at, '%d %b - %H:%i') AS stamp
        FROM nz_bank_bills
        WHERE identifier = ? AND status IN ('pending','overdue')
        ORDER BY id DESC LIMIT 25
    ]], { identifier }) or {}

    local total = 0
    for _, b in ipairs(rows) do
        total = total + b.amount
        b.dueIn = math.max(0, math.floor((b.due_at - os.time()) / 60))
    end
    return { rows = rows, total = total, count = #rows }
end

function Bank.createBill(identifier, issuerJob, amount, reason, senderName)
    if not Config.Bills.enabled then return false, 'Billing is disabled.' end
    amount = Bank.round(amount)
    if amount <= 0 or amount > Config.Bills.maxAmount then return false, 'Invalid amount.' end

    local issuer = Bank.getSociety(issuerJob)
    MySQL.insert.await([[
        INSERT INTO nz_bank_bills (identifier, issuer_id, issuer_label, sender_name, amount, reason, due_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        identifier,
        issuer and issuer.id or nil,
        issuer and issuer.label or (issuerJob or 'City'),
        senderName,
        amount,
        (reason or 'Invoice'):sub(1, 120),
        os.time() + (Config.Bills.overdueMinutes * 60)
    })

    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if xPlayer then
        -- auto-pay if the player opted in and can cover it
        local s = MySQL.single.await('SELECT auto_pay_bills FROM nz_bank_settings WHERE identifier = ?', { identifier })
        if Config.Bills.autoPay and s and s.auto_pay_bills == 1 then
            local bill = MySQL.single.await(
                'SELECT * FROM nz_bank_bills WHERE identifier = ? ORDER BY id DESC LIMIT 1', { identifier })
            local acc = Bank.getPersonal(identifier)
            if acc and acc.balance >= amount then
                Bank.settleBill(identifier, bill.id, acc.id, true)
                return true
            end
        end

        Bank.notify(xPlayer.source, 'New bill',
            ('%s%s from %s'):format(Config.Currency, amount, issuer and issuer.label or issuerJob or 'the city'), 'inform')
        TriggerClientEvent('nz_bank:refresh', xPlayer.source)
    end
    return true
end

function Bank.settleBill(identifier, billId, accountId, auto)
    local bill = MySQL.single.await('SELECT * FROM nz_bank_bills WHERE id = ?', { billId })
    if not bill or bill.identifier ~= identifier then return false, 'Bill not found.' end
    if bill.status ~= 'pending' and bill.status ~= 'overdue' then return false, 'This bill is already settled.' end

    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    local ok = Bank.debit(accountId, bill.amount, {
        category = 'bill',
        label    = ('%s · %s'):format(bill.issuer_label, bill.reason):sub(1, 90),
        actor    = identifier,
        actorName= xPlayer and Bank.fullName(xPlayer) or 'Auto-pay'
    })
    if not ok then return false, 'Not enough in that account.' end

    if bill.issuer_id then
        Bank.credit(bill.issuer_id, bill.amount, {
            category = 'bill',
            label    = ('Bill paid · %s'):format(bill.reason):sub(1, 90),
            actor    = identifier,
            actorName= xPlayer and Bank.fullName(xPlayer) or 'Payer'
        })
    end

    MySQL.update.await('UPDATE nz_bank_bills SET status = "paid" WHERE id = ?', { billId })

    if xPlayer and auto then
        Bank.notify(xPlayer.source, 'Bill paid automatically',
            ('%s%s to %s'):format(Config.Currency, bill.amount, bill.issuer_label), 'inform')
    end

    Bank.log('bills', 'Bill paid',
        ('**%s%s** paid to %s · %s'):format(Config.Currency, bill.amount, bill.issuer_label, bill.reason))

    return true, ('Paid %s%s.'):format(Config.Currency, bill.amount)
end

Bank.callback('nz_bank:payBill', function(src, billId, accountId)
    local identifier = Bank.identifier(src)
    if not identifier then return { ok = false, msg = 'Player not found.' } end

    local acc, perms = Bank.access(src, accountId)
    if not acc then return { ok = false, msg = 'You cannot use that account.' } end
    if not perms.withdraw then return { ok = false, msg = 'You cannot spend from that account.' } end

    local ok, msg = Bank.settleBill(identifier, billId, accountId, false)
    return { ok = ok, msg = msg }
end)

--- Issue a bill from a society account (job-gated).
Bank.callback('nz_bank:issueBill', function(src, targetSrc, amount, reason)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    local issuerJob
    for _, job in ipairs(Config.Bills.issuers) do
        if job == xPlayer.job.name then issuerJob = job break end
    end
    if not issuerJob then return { ok = false, msg = 'Your job cannot issue bills.' } end

    local target = ESX.GetPlayerFromId(tonumber(targetSrc))
    if not target then return { ok = false, msg = 'No player online with that ID.' } end

    local ok = Bank.createBill(target.identifier, issuerJob, amount, reason, Bank.fullName(xPlayer))
    if not ok then return { ok = false, msg = 'Could not create that bill.' } end

    return { ok = true, msg = ('Billed %s for %s%s.'):format(Bank.fullName(target), Config.Currency, Bank.round(amount)) }
end)

-- overdue sweep
CreateThread(function()
    while true do
        Wait(120000)
        do
            local due = MySQL.query.await(
                'SELECT * FROM nz_bank_bills WHERE status = "pending" AND due_at <= ?', { os.time() }) or {}
            for _, bill in ipairs(due) do
                local penalty = Bank.round(bill.amount * Config.Bills.latePenalty)
                MySQL.update.await('UPDATE nz_bank_bills SET status = "overdue", amount = ? WHERE id = ?',
                    { bill.amount + penalty, bill.id })

                local xPlayer = ESX.GetPlayerFromIdentifier(bill.identifier)
                if xPlayer then
                    Bank.notify(xPlayer.source, 'Bill overdue',
                        ('A late fee of %s%s was added to your %s bill.'):format(Config.Currency, penalty, bill.issuer_label),
                        'error')
                    TriggerClientEvent('nz_bank:refresh', xPlayer.source)
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  SCHEDULED TRANSFERS
-- ═══════════════════════════════════════════════════════════
Bank.scheduleIntervals = {
    { id = 'hourly', label = 'Every hour',     minutes = 60 },
    { id = 'daily',  label = 'Every 24 hours', minutes = 1440 },
    { id = 'weekly', label = 'Every 7 days',   minutes = 10080 },
}

local SCHEDULE_FAILURES = 3   -- failed runs before a standing order pauses
function Bank.getScheduled(identifier)
    local rows = MySQL.query.await([[
        SELECT s.*, a.label AS from_label
        FROM nz_bank_scheduled s
        JOIN nz_bank_accounts a ON a.id = s.from_id
        WHERE s.identifier = ? ORDER BY s.id DESC
    ]], { identifier }) or {}

    for _, r in ipairs(rows) do
        r.nextIn = math.max(0, math.floor((r.next_run - os.time()) / 60))
        r.enabled = r.enabled == 1
    end
    return rows
end

Bank.callback('nz_bank:createScheduled', function(src, accountId, toNumber, amount, label, intervalId)
    local xPlayer = Bank.getPlayer(src)
    local acc, perms = Bank.access(src, accountId)
    if not acc then return { ok = false, msg = 'You cannot use that account.' } end
    if not perms.transfer then return { ok = false, msg = 'You do not have transfer rights here.' } end

    amount = Bank.round(amount)
    if amount < Config.Accounts.minTransfer then return { ok = false, msg = 'Amount is too small.' } end

    local target = Bank.getAccountByNumber(toNumber)
    if not target then return { ok = false, msg = 'No account with that number.' } end
    if target.id == accountId then return { ok = false, msg = 'That is the same account.' } end

    local interval
    for _, i in ipairs(Bank.scheduleIntervals) do if i.id == intervalId then interval = i break end end
    if not interval then return { ok = false, msg = 'Pick a valid schedule.' } end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM nz_bank_scheduled WHERE identifier = ?',
        { xPlayer.identifier }) or 0
    if count >= Config.Accounts.maxScheduled then
        return { ok = false, msg = ('You can only run %s scheduled transfers.'):format(Config.Accounts.maxScheduled) }
    end

    MySQL.insert.await([[
        INSERT INTO nz_bank_scheduled (identifier, from_id, to_number, label, amount, interval_min, next_run)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        xPlayer.identifier, accountId, toNumber,
        ((label or target.label):gsub('[^%w%s%-&\'.]', '')):sub(1, 32),
        amount, interval.minutes, os.time() + (interval.minutes * 60)
    })

    return { ok = true, msg = ('Scheduled: %s%s %s.'):format(Config.Currency, amount, interval.label:lower()) }
end)

Bank.callback('nz_bank:updateScheduled', function(src, id, action)
    local identifier = Bank.identifier(src)
    local row = MySQL.single.await('SELECT * FROM nz_bank_scheduled WHERE id = ?', { id })
    if not row or row.identifier ~= identifier then return { ok = false, msg = 'Not found.' } end

    if action == 'delete' then
        MySQL.update.await('DELETE FROM nz_bank_scheduled WHERE id = ?', { id })
        return { ok = true, msg = 'Scheduled transfer removed.' }
    elseif action == 'toggle' then
        local enabled = row.enabled == 1 and 0 or 1
        MySQL.update.await('UPDATE nz_bank_scheduled SET enabled = ?, failures = 0 WHERE id = ?', { enabled, id })
        return { ok = true, msg = enabled == 1 and 'Resumed.' or 'Paused.' }
    end
    return { ok = false, msg = 'Unknown action.' }
end)

CreateThread(function()
    while true do
        Wait(60000)
        do
            local due = MySQL.query.await(
                'SELECT * FROM nz_bank_scheduled WHERE enabled = 1 AND next_run <= ?', { os.time() }) or {}

            for _, s in ipairs(due) do
                local xPlayer = ESX.GetPlayerFromIdentifier(s.identifier)
                local name = xPlayer and Bank.fullName(xPlayer) or 'Scheduled transfer'

                local ok = Bank.doTransfer(s.from_id, s.to_number, s.amount, s.identifier, name,
                    ('Scheduled · %s'):format(s.label))

                if ok then
                    MySQL.update.await('UPDATE nz_bank_scheduled SET next_run = ?, failures = 0 WHERE id = ?',
                        { os.time() + (s.interval_min * 60), s.id })
                    if xPlayer then
                        Bank.notify(xPlayer.source, 'Scheduled transfer sent',
                            ('%s%s to %s'):format(Config.Currency, s.amount, s.label), 'inform')
                    end
                else
                    local failures = s.failures + 1
                    local disable = failures >= SCHEDULE_FAILURES
                    MySQL.update.await('UPDATE nz_bank_scheduled SET failures = ?, enabled = ?, next_run = ? WHERE id = ?',
                        { failures, disable and 0 or 1, os.time() + (s.interval_min * 60), s.id })
                    if xPlayer then
                        Bank.notify(xPlayer.source, 'Scheduled transfer failed',
                            disable and ('%s was paused after repeated failures.'):format(s.label)
                                     or ('Not enough funds for %s.'):format(s.label), 'error')
                    end
                end
            end
        end
    end
end)
