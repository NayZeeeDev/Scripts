if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  OVERDRAFT PROTECTION
--
--  When a payment would take a personal account below zero, two
--  things can save it, in this order:
--
--    1. A sweep from savings, covering only the shortfall. Free or
--       nearly so, because the money is the player's own.
--    2. The overdraft line — the account goes negative up to a
--       limit, for a fee, with interest once the grace period is up.
--
--  Both are opt-in per player, because an account silently going
--  negative is the kind of surprise people quit over.
--
--  None of this runs inside an account lock. Each step completes on
--  its own before the next begins, so two accounts are never held
--  at once and a savings sweep can never deadlock against a
--  transfer going the other way.
-- ═══════════════════════════════════════════════════════════

--- On only when it is configured on AND the database can carry it.
local function cfg()
    if not Bank.schema.overdraft then return {} end
    return Config.Overdraft or {}
end

--- Is this account eligible at all, and has its owner switched it on?
local function eligible(acc)
    local c = cfg()
    if not c.enabled then return false end
    if not acc or acc.type ~= 'personal' then return false end

    if not c.optIn then return true end

    local s = MySQL.single.await(
        'SELECT overdraft FROM nz_bank_settings WHERE identifier = ?', { acc.owner })
    return s and s.overdraft == 1
end

--- How far below zero this account is allowed to go.
function Bank.overdraftLimit(identifier)
    local c = cfg()
    if not c.enabled then return 0 end

    local limit = c.limit or 0
    if not c.scaleWithCredit then return limit end

    -- better credit earns a wider line, within the configured ceiling
    local row = MySQL.single.await('SELECT score FROM nz_bank_credit WHERE identifier = ?', { identifier })
    local score = (row and row.score) or Config.Credit.starting
    local span = math.max(1, (Config.Credit.max or 850) - (Config.Credit.min or 300))
    local ratio = math.min(1.0, math.max(0.0, (score - (Config.Credit.min or 300)) / span))

    local floor = c.minLimit or 0
    return math.floor(floor + (limit - floor) * ratio)
end

-- ═══════════════════════════════════════════════════════════
--  THE SWEEP
-- ═══════════════════════════════════════════════════════════
--- Move the shortfall out of savings and into the account. Returns
--- how much was actually moved.
local function sweepSavings(acc, shortfall)
    local c = cfg()
    if not c.savingsFirst then return 0 end

    local savings = Bank.getSavings(acc.owner)
    if not savings or savings.balance <= 0 then return 0 end

    local fee = Bank.round(shortfall * (c.savingsFee or 0))
    local need = shortfall + fee
    local move = math.min(savings.balance, need)
    if move <= 0 then return 0 end

    local ok = Bank.debit(savings.id, move, {
        category  = 'transfer',
        label     = 'Overdraft cover from savings',
        actor     = acc.owner,
        actorName = 'Overdraft protection',
        noOverdraft = true
    })
    if not ok then return 0 end

    local landed = move - math.min(fee, move)
    Bank.credit(acc.id, landed, {
        category  = 'transfer',
        label     = 'Overdraft cover',
        actor     = acc.owner,
        actorName = 'Overdraft protection',
    })

    if fee > 0 and landed < move then
        Bank.log('overdraft', 'Savings sweep fee',
            ('%s%s taken covering an overdraft'):format(Config.Currency, move - landed))
    end

    local xPlayer = ESX.GetPlayerFromIdentifier(acc.owner)
    if xPlayer then
        Bank.notify(xPlayer.source, 'Overdraft protection',
            ('%s%s moved from savings to cover the payment.'):format(Config.Currency, landed), 'inform')
    end

    return landed
end

-- ═══════════════════════════════════════════════════════════
--  THE DECISION
--
--  Called from Bank.debit when a payment would go below zero.
--  Returns how far below zero this debit may take the account.
--  Zero means no cover, and the payment is refused.
-- ═══════════════════════════════════════════════════════════
function Bank.overdraftCover(acc, amount)
    if not eligible(acc) then return 0 end

    local c = cfg()

    -- savings first, because it is the player's own money
    local swept = sweepSavings(acc, amount - acc.balance)
    if swept > 0 then
        local topped = Bank.getAccountById(acc.id)
        -- covered outright: no line drawn on, and no fee
        if topped and topped.balance >= amount then return 0 end
    end

    if not c.limit or c.limit <= 0 then return 0 end

    -- the line itself, measured against how far below zero this ends up
    local fresh = Bank.getAccountById(acc.id) or acc
    local ending = fresh.balance - amount
    local limit = Bank.overdraftLimit(acc.owner)

    if -ending > limit and c.blockAtLimit ~= false then return 0 end

    -- a fee for going overdrawn. Once per episode by default, so a
    -- run of small payments while already negative is not punished
    -- over and over.
    local already = (fresh.od_since or 0) > 0
    local charge = (not already) or c.feePerUse

    if charge and (c.fee or 0) > 0 then
        MySQL.update.await(
            'UPDATE nz_bank_accounts SET od_fees = od_fees + ? WHERE id = ?', { c.fee, acc.id })
    end

    if not already then
        MySQL.update.await(
            'UPDATE nz_bank_accounts SET od_since = ? WHERE id = ?', { os.time(), acc.id })

        if c.creditPenalty and c.creditPenalty ~= 0 then
            Bank.moveCredit(acc.owner, c.creditPenalty)
        end
    end

    local xPlayer = ESX.GetPlayerFromIdentifier(acc.owner)
    if xPlayer then
        Bank.notify(xPlayer.source, 'Overdrawn',
            charge and (c.fee or 0) > 0
                and ('You are into your overdraft. A %s%s fee was added.'):format(Config.Currency, c.fee)
                or 'You are into your overdraft.',
            'error')
    end

    Bank.log('overdraft', 'Overdraft used',
        ('Account `%s` went to %s%s'):format(acc.account_number, Config.Currency, ending))

    return limit
end

--- Called after any credit, to close out an episode once the
--- account is back in the black.
function Bank.overdraftSettle(accountId)
    if not cfg().enabled then return end

    local acc = Bank.getAccountById(accountId)
    if not acc or acc.type ~= 'personal' then return end
    if (acc.od_since or 0) == 0 then return end
    if acc.balance < 0 then return end

    MySQL.update.await(
        'UPDATE nz_bank_accounts SET od_since = 0, od_fees = 0 WHERE id = ?', { accountId })

    local xPlayer = ESX.GetPlayerFromIdentifier(acc.owner)
    if xPlayer then
        Bank.notify(xPlayer.source, 'Back in credit', 'Your account is out of its overdraft.', 'success')
    end

    if (cfg().creditReward or 0) ~= 0 then
        Bank.moveCredit(acc.owner, cfg().creditReward)
    end
end

-- ═══════════════════════════════════════════════════════════
--  STATE FOR THE UI
-- ═══════════════════════════════════════════════════════════
function Bank.getOverdraftState(identifier, acc)
    local c = cfg()
    if not c.enabled then return nil end

    local settings = MySQL.single.await(
        'SELECT overdraft FROM nz_bank_settings WHERE identifier = ?', { identifier })

    local since = (acc and acc.od_since or 0)
    local used = acc and acc.balance < 0 and -acc.balance or 0
    local limit = Bank.overdraftLimit(identifier)

    local graceLeft
    if since > 0 and (c.graceMinutes or 0) > 0 then
        graceLeft = math.max(0, math.floor(((since + c.graceMinutes * 60) - os.time()) / 60))
    end

    return {
        enabled   = true,
        optIn     = c.optIn ~= false,
        on        = (not c.optIn) or (settings and settings.overdraft == 1) or false,
        limit     = limit,
        used      = used,
        available = math.max(0, limit - used),
        fees      = acc and acc.od_fees or 0,
        fee       = c.fee or 0,
        since     = since,
        graceLeft = graceLeft,
        rate      = c.interestRate or 0,
        rateEvery = c.interestMinutes or 60,
        savings   = c.savingsFirst == true
    }
end

Bank.callback('nz_bank:setOverdraft', function(src, on)
    local c = cfg()
    if not c.enabled then return { ok = false, msg = 'Overdrafts are not offered here.' } end
    if c.optIn == false then return { ok = false, msg = 'Overdraft protection is always on here.' } end

    local identifier = Bank.identifier(src)
    if not identifier then return { ok = false, msg = 'Player not found.' } end

    -- switching it off while overdrawn would strand the balance
    if not on then
        local acc = Bank.getPersonal(identifier)
        if acc and acc.balance < 0 then
            return { ok = false, msg = 'Clear your overdraft before turning it off.' }
        end
    end

    MySQL.query.await([[
        INSERT INTO nz_bank_settings (identifier, overdraft) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE overdraft = VALUES(overdraft)
    ]], { identifier, on and 1 or 0 })

    return {
        ok = true,
        msg = on
            and ('Overdraft protection is on, up to %s%s.'):format(Config.Currency, Bank.overdraftLimit(identifier))
            or 'Overdraft protection is off.'
    }
end)

-- ═══════════════════════════════════════════════════════════
--  INTEREST ON A NEGATIVE BALANCE
--
--  Charged on what is actually owed, only after the grace period,
--  and only while the account is still in the red.
-- ═══════════════════════════════════════════════════════════
CreateThread(function()
    -- The flags are not set until the schema check has run, so this
    -- thread waits rather than reading them at start and switching
    -- itself off on a database that was fine all along.
    Bank.awaitSchema()

    local c = cfg()
    if not c.enabled or (c.interestRate or 0) <= 0 then return end

    local every = math.max(1, c.interestMinutes or 60)

    while true do
        Wait(every * 60000)

        local cutoff = os.time() - ((c.graceMinutes or 0) * 60)
        local rows = MySQL.query.await([[
            SELECT id, owner, balance, account_number FROM nz_bank_accounts
            WHERE type = 'personal' AND balance < 0 AND od_since > 0 AND od_since <= ?
        ]], { cutoff }) or {}

        for _, acc in ipairs(rows) do
            local interest = Bank.round((-acc.balance) * c.interestRate)
            if interest > 0 then
                local newBal = acc.balance - interest
                MySQL.update.await('UPDATE nz_bank_accounts SET balance = ? WHERE id = ?',
                    { newBal, acc.id })
                Bank.logTx(acc.id, 'out', interest, newBal, {
                    category = 'fee', label = 'Overdraft interest', actorName = 'Bank'
                })

                local xPlayer = ESX.GetPlayerFromIdentifier(acc.owner)
                if xPlayer then
                    Bank.notify(xPlayer.source, 'Overdraft interest',
                        ('%s%s charged on what you owe.'):format(Config.Currency, interest), 'error')
                    TriggerClientEvent('nz_bank:refresh', xPlayer.source)
                end
            end
        end
    end
end)
