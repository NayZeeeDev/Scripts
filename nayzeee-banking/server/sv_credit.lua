if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  CREDIT LINES
--  Credit and secured cards spend against a limit rather than an
--  account. Statements are cut on a cycle, a minimum payment is
--  due, and interest is charged on whatever is carried.
-- ═══════════════════════════════════════════════════════════

function Bank.cardType(id)
    for _, t in ipairs(Config.CardTypes) do
        if t.id == id then return t end
    end
    return Config.CardTypes[1]
end

function Bank.logCharge(cardId, direction, amount, balanceAfter, label)
    MySQL.insert('INSERT INTO nz_bank_card_charges (card_id, direction, amount, balance_after, label) VALUES (?, ?, ?, ?, ?)',
        { cardId, direction, Bank.round(amount), Bank.round(balanceAfter), (label or 'Charge'):sub(1, 90) })
end

function Bank.availableCredit(card)
    if card.kind == 'debit' then return nil end
    return math.max(0, card.credit_limit - card.balance)
end

--- Put a charge on a credit or secured card.
--- Returns ok, message.
local function chargeCardNow(cardId, amount, label)
    local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card then return false, 'Card not found.' end
    if card.status ~= 'active' then return false, 'This card is not active.' end

    amount = Bank.round(amount)
    if amount <= 0 then return false, 'Invalid amount.' end

    -- daily limit applies to every kind of card
    local okDaily, why = Bank.spendOnCard(cardId, amount)
    if not okDaily then
        return false, why == 'limit' and 'That would break the daily limit on this card.' or 'This card is not active.'
    end

    if card.kind == 'debit' then
        local ok = Bank.debit(card.account_id, amount, {
            category = 'card', label = label or 'Card payment', actorName = card.holder
        })
        return ok, ok and 'Paid.' or 'Not enough in the linked account.'
    end

    local available = Bank.availableCredit(card)
    if amount > available then
        return false, ('Only %s%s of credit left on this card.'):format(Config.Currency, available)
    end

    local balance = card.balance + amount
    MySQL.update.await('UPDATE nz_bank_cards SET balance = ? WHERE id = ?', { balance, cardId })
    Bank.logCharge(cardId, 'charge', amount, balance, label or 'Card purchase')

    Bank.log('cards', 'Card charge',
        ('**%s%s** on %s ending %s'):format(Config.Currency, amount, card.holder, card.card_number:sub(-4)))

    return true, ('Charged %s%s.'):format(Config.Currency, amount)
end

--- Pay a card balance down from an account.
local function payCardNow(src, cardId, amount, accountId, auto)
    local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card then return false, 'Card not found.' end
    if card.kind == 'debit' then return false, 'Debit cards carry no balance.' end
    if card.balance <= 0 then return false, 'Nothing owed on this card.' end

    amount = Bank.round(amount)
    if amount <= 0 then return false, 'Enter a valid amount.' end
    if amount > card.balance then amount = card.balance end

    local xPlayer = src and Bank.getPlayer(src) or nil
    local ok = Bank.debit(accountId, amount, {
        category = 'card',
        label    = ('Card payment · %s'):format(card.card_number:sub(-4)),
        actor    = xPlayer and xPlayer.identifier or nil,
        actorName= xPlayer and Bank.fullName(xPlayer) or 'Auto-pay'
    })
    if not ok then return false, 'Not enough in that account.' end

    local balance = card.balance - amount
    local minLeft = math.max(0, card.min_payment - amount)

    MySQL.update.await('UPDATE nz_bank_cards SET balance = ?, min_payment = ? WHERE id = ?',
        { balance, minLeft, cardId })
    Bank.logCharge(cardId, 'payment', amount, balance, auto and 'Automatic payment' or 'Card payment')

    -- clearing the minimum before the due date is what builds the score
    if minLeft == 0 and card.min_payment > 0 then
        MySQL.update.await('UPDATE nz_bank_cards SET missed = 0 WHERE id = ?', { cardId })
        local acc = Bank.getAccountById(card.account_id)
        local owner = card.holder_identifier or (acc and acc.owner)
        if Bank.isCharacterId(owner) then
            Bank.moveCredit(owner, Config.Credit.cardOnTime, 'on_time')
        end
    end

    return true, balance > 0
        and ('Paid %s%s. %s%s still owed.'):format(Config.Currency, amount, Config.Currency, balance)
        or 'Card paid off.'
end

-- One card at a time: two charges racing on the same card would both pass the
-- credit check, and a payment racing a charge would lose one of them.
function Bank.chargeCard(cardId, ...)
    return Bank.serial(Bank.cardKey(cardId), chargeCardNow, cardId, ...)
end

function Bank.payCard(src, cardId, ...)
    return Bank.serial(Bank.cardKey(cardId), payCardNow, src, cardId, ...)
end

-- ═══════════════════════════════════════════════════════════
--  STATEMENT CYCLE
-- ═══════════════════════════════════════════════════════════
local function cutStatement(card)
    local pct = Config.CreditCards.minPaymentPct
    local minPayment = math.max(Config.CreditCards.minPaymentFloor, Bank.round(card.balance * pct))
    if minPayment > card.balance then minPayment = card.balance end

    MySQL.update.await([[
        UPDATE nz_bank_cards SET min_payment = ?, due_at = ?, statement_at = ? WHERE id = ?
    ]], {
        minPayment,
        os.time() + (Config.CreditCards.dueMinutes * 60),
        os.time() + (Config.CreditCards.statementMinutes * 60),
        card.id
    })

    -- interest on whatever is carried. apr is yearly and each statement
    -- counts as 1/statementsPerYear of it (a month, by default)
    local perYear = math.max(1, Config.CreditCards.statementsPerYear or 12)
    local periodRate = (tonumber(card.apr) or 0) / perYear
    local interest = Bank.round(card.balance * periodRate)
    if interest > 0 then
        local balance = card.balance + interest
        MySQL.update.await('UPDATE nz_bank_cards SET balance = ? WHERE id = ?', { balance, card.id })
        Bank.logCharge(card.id, 'interest', interest, balance, 'Interest on carried balance')
    end

    local acc = Bank.getAccountById(card.account_id)
    local owner = card.holder_identifier or (acc and acc.owner)

    -- running the line hot quietly costs score
    if card.credit_limit > 0 then
        local use = card.balance / card.credit_limit
        if use >= Config.Credit.highUtilisation.threshold and Bank.isCharacterId(owner) then
            Bank.moveCredit(owner, Config.Credit.highUtilisation.score)
        end
    end

    if owner then
        local xPlayer = ESX.GetPlayerFromIdentifier(owner)
        if xPlayer then
            Bank.notify(xPlayer.source, 'Card statement',
                ('%s%s due on your %s card.'):format(Config.Currency, minPayment, Bank.cardType(card.card_type).label),
                'inform')
            TriggerClientEvent('nz_bank:refresh', xPlayer.source)
        end
    end
end

local function missStatement(card)
    local missed = card.missed + 1
    local fee = Config.CreditCards.lateFee
    local balance = card.balance + fee

    local freeze = missed >= Config.CreditCards.missedBeforeFreeze

    MySQL.update.await([[
        UPDATE nz_bank_cards SET missed = ?, balance = ?, status = ?, due_at = ? WHERE id = ?
    ]], {
        missed, balance, freeze and 'blocked' or card.status,
        os.time() + (Config.CreditCards.dueMinutes * 60), card.id
    })
    Bank.logCharge(card.id, 'fee', fee, balance, 'Late payment fee')

    local acc = Bank.getAccountById(card.account_id)
    local owner = card.holder_identifier or (acc and acc.owner)
    if Bank.isCharacterId(owner) then
        Bank.moveCredit(owner, freeze and Config.Credit.cardFrozen or Config.Credit.cardLate, 'late')
    end

    if owner then
        local xPlayer = ESX.GetPlayerFromIdentifier(owner)
        if xPlayer then
            Bank.notify(xPlayer.source, freeze and 'Card frozen' or 'Payment missed',
                freeze and 'Too many missed statements. Clear the balance to unfreeze it.'
                       or ('A %s%s late fee was added.'):format(Config.Currency, fee),
                'error')
            TriggerClientEvent('nz_bank:refresh', xPlayer.source)
        end
    end
end

--- One card's statement step, under the card's lock and re-read, so a payment
--- made since the loop's query is counted.
local function cycleCard(cardId)
    local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card then return end
    -- a statement falls due
    if card.due_at > 0 and os.time() >= card.due_at and card.min_payment > 0 then
        local acc = Bank.getAccountById(card.account_id)
        local owner = card.holder_identifier or (acc and acc.owner)
        local paid = false

        if true and Bank.isCharacterId(owner) then
            local s = MySQL.single.await(
                'SELECT auto_pay_loans FROM nz_bank_settings WHERE identifier = ?', { owner })
            if s and s.auto_pay_loans == 1 and acc and acc.balance >= card.min_payment then
                paid = select(1, payCardNow(nil, card.id, card.min_payment, card.account_id, true))
            end
        end

        if not paid then missStatement(card) end

    -- time to cut a fresh statement
    elseif card.balance > 0 and (card.statement_at == 0 or os.time() >= card.statement_at) then
        cutStatement(card)

    elseif card.balance <= 0 and card.min_payment > 0 then
        MySQL.update.await('UPDATE nz_bank_cards SET min_payment = 0, due_at = 0 WHERE id = ?', { card.id })
    end
end

CreateThread(function()
    while true do
        Wait(60000)

        local cards = MySQL.query.await(
            'SELECT id FROM nz_bank_cards WHERE kind != "debit"') or {}

        for _, row in ipairs(cards) do
            local ok, err = pcall(Bank.serial, Bank.cardKey(row.id), cycleCard, row.id)
            if not ok then print('^1[nayzeee-banking]^7 card statement failed: ' .. tostring(err)) end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  CALLBACKS
-- ═══════════════════════════════════════════════════════════
Bank.callback('nz_bank:payCard', function(src, cardId, amount, accountId)
    local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card then return { ok = false, msg = 'Card not found.' } end

    local acc, perms = Bank.access(src, card.account_id)
    if not acc then return { ok = false, msg = 'You cannot use this account.' } end

    local payFrom, fromPerms = Bank.access(src, accountId)
    if not payFrom then return { ok = false, msg = 'You cannot use that account.' } end
    if not fromPerms.withdraw then return { ok = false, msg = 'You cannot spend from that account.' } end

    local ok, msg = Bank.payCard(src, cardId, amount, accountId, false)
    return { ok = ok, msg = msg }
end)

Bank.callback('nz_bank:getStatement', function(src, cardId)
    local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card then return {} end
    if not Bank.access(src, card.account_id) then return {} end

    return MySQL.query.await([[
        SELECT direction, amount, label, DATE_FORMAT(created_at, '%d %b - %H:%i') AS stamp
        FROM nz_bank_card_charges WHERE card_id = ? ORDER BY id DESC LIMIT 8
    ]], { cardId }) or {}
end)

-- ═══════════════════════════════════════════════════════════
--  EXPORTS — shops, fuel, rentals, anything that takes a card
-- ═══════════════════════════════════════════════════════════
exports('chargeCard', function(cardId, amount, label)
    return Bank.chargeCard(cardId, amount, label)
end)

exports('chargeCardByNumber', function(cardNumber, amount, label)
    local card = MySQL.single.await('SELECT id FROM nz_bank_cards WHERE card_number = ?', { cardNumber })
    if not card then return false, 'Card not found.' end
    return Bank.chargeCard(card.id, amount, label)
end)

exports('getCardInfo', function(cardId)
    local c = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not c then return nil end
    return {
        id = c.id, number = c.card_number, holder = c.holder, type = c.card_type, kind = c.kind,
        status = c.status, limit = c.credit_limit, balance = c.balance,
        available = Bank.availableCredit(c), deposit = c.deposit
    }
end)
