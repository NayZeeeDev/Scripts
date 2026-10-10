if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  CARDS
-- ═══════════════════════════════════════════════════════════

local DEFAULT_CARD_LIMIT = 5000

local function newCardNumber()
    for _ = 1, 12 do
        local n = ('%04d %04d %04d %04d'):format(
            math.random(1000, 9999), math.random(1000, 9999),
            math.random(1000, 9999), math.random(1000, 9999))
        if not MySQL.scalar.await('SELECT id FROM nz_bank_cards WHERE card_number = ?', { n }) then
            return n
        end
    end
    return tostring(os.time())
end

local function expiryString()
    local t = os.time() + (Config.Cards.expiryMonths * 2592000)
    return os.date('%m/%Y', t)
end

local function serialiseCard(c, includePin)
    return {
        id       = c.id,
        account  = c.account_id,
        holderId = c.holder_identifier,
        joint    = c.holder_identifier ~= nil,
        type     = c.card_type,
        typeLabel= Bank.cardType(c.card_type).label,
        kind     = c.kind,
        credit   = c.credit_limit,
        balance  = c.balance,
        available= c.kind ~= 'debit' and math.max(0, c.credit_limit - c.balance) or nil,
        deposit  = c.deposit,
        apr      = tonumber(c.apr),
        minPay   = c.min_payment,
        dueIn    = c.due_at > 0 and math.max(0, math.floor((c.due_at - os.time()) / 60)) or 0,
        missed   = c.missed,
        number   = c.card_number,
        masked   = ('•••• •••• •••• %s'):format(c.card_number:sub(-4)),
        holder   = c.holder,
        status   = c.status,
        limit    = c.daily_limit,
        spent    = (tonumber(c.spent_reset) or 0) > os.time() and c.spent_today or 0,
        spentIn  = math.max(0, math.floor(((tonumber(c.spent_reset) or 0) - os.time()) / 60)),
        express  = c.express == 1,
        isDefault= c.is_default == 1,
        skin     = c.skin,
        expires  = c.expires,
        pin      = includePin and c.pin or nil
    }
end

-- ═══════════════════════════════════════════════════════════
--  PHYSICAL CARD ITEMS
--  On ox_inventory every card carries its own picture
--  (metadata.image = card_<type>_<skin>, from install/images)
--  so the item looks like the card in the app. Other inventories
--  show the item's default picture for that card type.
-- ═══════════════════════════════════════════════════════════
local CardItems = {}

function CardItems.meta(card, accountNumber)
    local t = Bank.cardType(card.card_type)
    local last4 = tostring(card.card_number or ''):sub(-4)
    return {
        cardId      = card.id,
        serial      = card.card_number,   -- a replaced card gets a new number, the old plastic stops matching
        account     = accountNumber,
        holder      = card.holder,
        last4       = last4,
        type        = t.label,
        label       = ('%s •%s'):format(t.label, last4),
        description = ('%s · ending %s'):format(card.holder or 'Unknown holder', last4),
        image       = (Config.Cards.skinImages and t.item and card.skin)
                      and ('%s_%s'):format(t.item, card.skin) or nil,
    }
end

function CardItems.give(src, card, accountNumber, extra)
    local t = Bank.cardType(card.card_type)
    if not (Config.Cards.physicalItem and t.item and src) then return false end

    local meta = CardItems.meta(card, accountNumber)
    for k, v in pairs(extra or {}) do meta[k] = v end
    local inv = Bank.inventory()
    if inv == 'ox_inventory' then
        return exports.ox_inventory:AddItem(src, t.item, 1, meta)
    elseif inv == 'qs-inventory' then
        return exports['qs-inventory']:AddItem(src, t.item, 1, nil, meta)
    elseif inv == 'qb-inventory' then
        return exports['qb-inventory']:AddItem(src, t.item, 1, false, meta, 'nayzeee-banking')
    end
    return false
end

--- Every copy of a card in an online player's ox_inventory.
--- Only ox_inventory can be searched by metadata; elsewhere this is empty.
function CardItems.find(cardId, onlySrc)
    local found = {}
    if not Config.Cards.physicalItem or Bank.inventory() ~= 'ox_inventory' then return found end

    local list = onlySrc and { onlySrc } or GetPlayers()
    for _, id in ipairs(list) do
        local src = tonumber(id)
        for _, item in pairs(exports.ox_inventory:GetInventoryItems(src) or {}) do
            if item.metadata and item.metadata.cardId == cardId then
                found[#found + 1] = { src = src, slot = item.slot, name = item.name, metadata = item.metadata }
            end
        end
    end
    return found
end

--- Repaint the card's items after its style or number changed.
--- Old plastic from before a replacement is left as it is.
function CardItems.refresh(card, accountNumber)
    for _, it in ipairs(CardItems.find(card.id)) do
        if CardItems.current(it.metadata, card) then
            local meta = CardItems.meta(card, accountNumber)
            meta.stolen = it.metadata.stolen
            exports.ox_inventory:SetMetadata(it.src, it.slot, meta)
        end
    end
end

--- Is this item the card as it is now? Items from before serials existed count as current.
function CardItems.current(meta, card)
    return meta.serial == nil or meta.serial == card.card_number
end

function CardItems.take(it)
    return exports.ox_inventory:RemoveItem(it.src, it.name, 1, nil, it.slot)
end

local function holderSource(card, fallback)
    if card.holder_identifier then
        local x = ESX.GetPlayerFromIdentifier(card.holder_identifier)
        return x and x.source or nil
    end
    return fallback
end

--- Every card on every account this player can see.
--- Joint cards (tied to one member) are visible to that member and,
--- when true is on, to the account owner.
function Bank.getCardsForPlayer(identifier, jobs, grade)
    local accounts = Bank.getAccessible(identifier, jobs, grade)
    local ids, owned = {}, {}
    for _, a in ipairs(accounts) do
        ids[#ids + 1] = a.id
        if a.owner == identifier or a.type == 'society' or a.role == 'owner' or a.role == 'manager' then
            owned[a.id] = true
        end
    end
    if #ids == 0 then return {} end

    local placeholders = string.rep('?,', #ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT * FROM nz_bank_cards WHERE account_id IN (%s) ORDER BY is_default DESC, id ASC'):format(placeholders),
        ids) or {}

    local out = {}
    for _, c in ipairs(rows) do
        local mine = (c.holder_identifier == nil) or (c.holder_identifier == identifier)
        local asOwner = true and owned[c.account_id]
        if mine or asOwner then out[#out + 1] = serialiseCard(c) end
    end
    return out
end

function Bank.getActiveCard(accountId)
    return MySQL.single.await(
        'SELECT * FROM nz_bank_cards WHERE account_id = ? AND status = "active" ORDER BY is_default DESC LIMIT 1',
        { accountId })
end

--- Track daily spend, resetting on a new day. Returns false when the limit is hit.
--- Daily spend on a rolling window rather than a calendar day, so a card
--- maxed at 23:55 is not free again five minutes later.
function Bank.spendOnCard(cardId, amount)
    local c = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not c then return false, 'no_card' end
    if c.status ~= 'active' then return false, 'blocked' end

    local window = (Config.Cards.limitResetHours or 24) * 3600
    local reset = tonumber(c.spent_reset) or 0
    local spent = c.spent_today or 0

    if os.time() >= reset then
        spent = 0
        reset = os.time() + window
    end

    if c.daily_limit > 0 and (spent + amount) > c.daily_limit then
        return false, 'limit'
    end

    MySQL.update.await(
        'UPDATE nz_bank_cards SET spent_today = ?, spent_reset = ?, spent_day = CURDATE() WHERE id = ?',
        { spent + amount, reset, cardId })
    return true
end

-- ═══════════════════════════════════════════════════════════
--  CALLBACKS
-- ═══════════════════════════════════════════════════════════
Bank.callback('nz_bank:createCard', function(src, accountId, pin, skin, memberIdentifier, typeId, depositAmount)
    if not Config.Cards.enabled then return { ok = false, msg = 'Cards are disabled.' } end

    local xPlayer = Bank.getPlayer(src)
    local acc, perms = Bank.access(src, accountId)
    if not acc then return { ok = false, msg = 'You cannot use this account.' } end
    if acc.type == 'savings' then return { ok = false, msg = 'Savings accounts do not take cards.' } end
    if perms.role == 'member' then return { ok = false, msg = 'Only owners and managers can issue cards.' } end

    pin = tostring(pin or ''):gsub('%D', '')
    if #pin ~= 4 then return { ok = false, msg = 'The PIN must be 4 digits.' } end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM nz_bank_cards WHERE account_id = ?', { accountId })
    if count >= Config.Cards.maxPerAccount then
        return { ok = false, msg = ('This account already holds %s cards.'):format(Config.Cards.maxPerAccount) }
    end

    -- ── joint card: tied to one member of a shared account ──
    local holderName, holderId = acc.label, nil
    if memberIdentifier and memberIdentifier ~= '' then
        if acc.type ~= 'shared' then
            return { ok = false, msg = 'Member cards only exist on shared accounts.' }
        end
        if perms.role ~= 'owner' then
            return { ok = false, msg = 'Only the owner can issue a card to a member.' }
        end

        local member = MySQL.single.await(
            'SELECT * FROM nz_bank_members WHERE account_id = ? AND identifier = ?',
            { accountId, memberIdentifier })
        if not member then return { ok = false, msg = 'They are not on this account.' } end

        local held = MySQL.scalar.await(
            'SELECT COUNT(*) FROM nz_bank_cards WHERE account_id = ? AND holder_identifier = ?',
            { accountId, memberIdentifier }) or 0
        if held >= Config.Cards.member.maxPerMember then
            return { ok = false, msg = ('%s already holds a card on this account.'):format(member.name) }
        end

        holderName, holderId = member.name, memberIdentifier
    end

    -- ── card type ──────────────────────────────────────────
    local cardType = Bank.cardType(typeId or 'debit')
    local creditLimit, deposit = 0, 0

    if cardType.kind ~= 'debit' then
        if acc.type ~= 'personal' then
            return { ok = false, msg = 'Credit lines are only issued on personal accounts.' }
        end

        local credit = Bank.getCredit(xPlayer.identifier)
        if credit.score < (cardType.minCredit or 0) then
            return { ok = false, msg = ('A %s needs a credit score of %s.'):format(cardType.label, cardType.minCredit) }
        end

        local bad = MySQL.scalar.await(
            'SELECT COUNT(*) FROM nz_bank_loans WHERE identifier = ? AND status = "defaulted"',
            { xPlayer.identifier }) or 0
        if bad > 0 then
            return { ok = false, msg = 'Settle your defaulted debt before opening a credit line.' }
        end
    end

    if cardType.kind == 'secured' then
        local rules = cardType.deposit or { min = 1000, max = 50000, multiplier = 1.0 }
        deposit = Bank.round(depositAmount or rules.min)
        if deposit < rules.min or deposit > rules.max then
            return { ok = false, msg = ('The deposit must be between %s%s and %s%s.'):format(
                Config.Currency, rules.min, Config.Currency, rules.max) }
        end
        creditLimit = Bank.round(deposit * (rules.multiplier or 1.0))
    elseif cardType.kind == 'credit' then
        creditLimit = cardType.creditLimit or 0
    end

    local upfront = (cardType.price or 0) + deposit
    if upfront > 0 then
        local ok = Bank.debit(accountId, upfront, {
            category = 'fee',
            label    = deposit > 0 and ('%s · fee and deposit'):format(cardType.label) or ('%s issued'):format(cardType.label),
            actor    = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
        })
        if not ok then
            return { ok = false, msg = ('You need %s%s in the account for this card.'):format(Config.Currency, upfront) }
        end
    end

    local valid = false
    for _, s in ipairs(Config.Cards.skins) do if s == skin then valid = true break end end
    if not valid then skin = Config.Cards.skins[1] end

    local dailyLimit = holderId and Config.Cards.member.limit
        or cardType.dailyLimit or DEFAULT_CARD_LIMIT

    local id = MySQL.insert.await([[
        INSERT INTO nz_bank_cards
          (account_id, card_number, card_type, kind, holder, holder_identifier, pin, daily_limit,
           credit_limit, deposit, apr, express, is_default, skin, expires, statement_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        accountId, newCardNumber(), cardType.id, cardType.kind, holderName, holderId, pin, dailyLimit,
        creditLimit, deposit, cardType.apr or 0, 0,
        (count == 0 and not holderId) and 1 or 0, skin, expiryString(),
        cardType.kind == 'debit' and 0 or (os.time() + (Config.CreditCards.statementMinutes * 60))
    })

    if holderId then
        local xMember = ESX.GetPlayerFromIdentifier(holderId)
        if xMember then
            Bank.notify(xMember.source, 'Card issued',
                ('%s issued you a card on %s.'):format(Bank.fullName(xPlayer), acc.label), 'success')
            TriggerClientEvent('nz_bank:refresh', xMember.source)
        end
    end

    if Config.Cards.physicalItem and cardType.item then
        local target = holderId and ESX.GetPlayerFromIdentifier(holderId) or xPlayer
        local card = target and MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { id })
        if card then CardItems.give(target.source, card, acc.account_number) end
    end

    Bank.log('cards', 'Card issued',
        ('**%s** issued a %s on %s%s'):format(Bank.fullName(xPlayer), cardType.label, acc.label,
            deposit > 0 and (' · deposit %s%s'):format(Config.Currency, deposit) or ''))

    return { ok = true, id = id, msg = creditLimit > 0
        and ('%s issued with a %s%s line.'):format(cardType.label, Config.Currency, creditLimit)
        or ('%s issued.'):format(cardType.label) }
end)

local updateCard

-- one change at a time per card, so a double-clicked close can't refund the deposit twice
Bank.callback('nz_bank:updateCard', function(src, cardId, ...)
    if not Bank.id(cardId) then return { ok = false, msg = 'Card not found.' } end
    local res, busy = Bank.serial(Bank.cardKey(cardId), updateCard, src, Bank.id(cardId), ...)
    if res == false then return { ok = false, msg = busy } end
    return res
end)

function updateCard(src, cardId, action, value)
    local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card then return { ok = false, msg = 'Card not found.' } end

    local acc, perms = Bank.access(src, card.account_id)
    if not acc then return { ok = false, msg = 'You cannot use this account.' } end

    local xPlayer = Bank.getPlayer(src)
    local ownCard = card.holder_identifier == xPlayer.identifier

    if perms.role == 'member' and not ownCard then
        return { ok = false, msg = 'Only owners and managers can manage cards.' }
    end
    -- a member may change the PIN on their own card, nothing else
    if ownCard and perms.role == 'member' and action ~= 'pin' then
        return { ok = false, msg = 'The account owner controls this card.' }
    end

    if action == 'block' then
        MySQL.update.await('UPDATE nz_bank_cards SET status = "blocked" WHERE id = ?', { cardId })
        Bank.log('cards', 'Card blocked', ('**%s** blocked a card on %s'):format(Bank.fullName(xPlayer), acc.label))
        return { ok = true, msg = 'Card blocked.' }

    elseif action == 'unblock' then
        if card.status == 'stolen' then
            return { ok = false, msg = 'That card was reported stolen. Order a replacement.' }
        end
        if card.kind ~= 'debit' and card.missed >= Config.CreditCards.missedBeforeFreeze and card.balance > 0 then
            return { ok = false, msg = 'Clear the outstanding balance to unfreeze this card.' }
        end
        -- blocking and unblocking must not wipe the late-payment count while money is owed
        if card.balance <= 0 then
            MySQL.update.await('UPDATE nz_bank_cards SET missed = 0 WHERE id = ?', { cardId })
        end
        MySQL.update.await('UPDATE nz_bank_cards SET status = "active" WHERE id = ?', { cardId })
        return { ok = true, msg = 'Card unblocked.' }

    elseif action == 'pin' then
        local pin = tostring(value or ''):gsub('%D', '')
        if #pin ~= 4 then return { ok = false, msg = 'The PIN must be 4 digits.' } end

        if (Config.Cards.pinChangePrice or 0) > 0 then
            local paid = Bank.debit(card.account_id, Config.Cards.pinChangePrice, {
                category = 'fee', label = 'PIN change',
                actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
            })
            if not paid then
                return { ok = false, msg = ('Changing the PIN costs %s%s.'):format(
                    Config.Currency, Config.Cards.pinChangePrice) }
            end
        end
        MySQL.update.await('UPDATE nz_bank_cards SET pin = ? WHERE id = ?', { pin, cardId })
        Bank.session[src] = Bank.session[src] or { pinOk = {} }
        Bank.session[src].pinOk = {}
        return { ok = true, msg = 'PIN changed.' }

    elseif action == 'limit' then
        local limit = tonumber(value) or DEFAULT_CARD_LIMIT
        local allowed = false
        for _, l in ipairs(Config.Cards.limitOptions) do if l == limit then allowed = true break end end
        if not allowed then return { ok = false, msg = 'That limit is not available.' } end
        MySQL.update.await('UPDATE nz_bank_cards SET daily_limit = ? WHERE id = ?', { limit, cardId })
        return { ok = true, msg = ('Daily limit set to %s%s.'):format(Config.Currency, limit) }

    elseif action == 'express' then
        if not Config.Cards.express.enabled then return { ok = false, msg = 'Express pay is disabled.' } end
        MySQL.update.await('UPDATE nz_bank_cards SET express = ? WHERE id = ?', { value and 1 or 0, cardId })
        return { ok = true, msg = value and 'Express pay on.' or 'Express pay off.' }

    elseif action == 'default' then
        MySQL.update.await('UPDATE nz_bank_cards SET is_default = 0 WHERE account_id = ?', { card.account_id })
        MySQL.update.await('UPDATE nz_bank_cards SET is_default = 1 WHERE id = ?', { cardId })
        return { ok = true, msg = 'Set as the default card.' }

    elseif action == 'skin' then
        local valid = false
        for _, s in ipairs(Config.Cards.skins) do if s == value then valid = true break end end
        if not valid then return { ok = false, msg = 'Unknown card style.' } end
        MySQL.update.await('UPDATE nz_bank_cards SET skin = ? WHERE id = ?', { value, cardId })
        card.skin = value
        CardItems.refresh(card, acc.account_number)
        return { ok = true, msg = 'Card style updated.' }

    elseif action == 'delete' then
        if perms.role ~= 'owner' and acc.type ~= 'society' then
            return { ok = false, msg = 'Only the owner can destroy a card.' }
        end
        if card.kind ~= 'debit' and card.balance > 0 and Config.CreditCards.closeRequiresZero then
            return { ok = false, msg = ('Clear the %s%s balance before closing this card.'):format(
                Config.Currency, card.balance) }
        end

        if card.deposit and card.deposit > 0 then
            Bank.credit(card.account_id, card.deposit, {
                category = 'deposit', label = 'Secured card deposit returned'
            })
        end

        MySQL.update.await('DELETE FROM nz_bank_cards WHERE id = ?', { cardId })
        for _, it in ipairs(CardItems.find(cardId)) do CardItems.take(it) end
        Bank.log('cards', 'Card closed', ('**%s** closed a card on %s'):format(Bank.fullName(xPlayer), acc.label))

        return { ok = true, msg = card.deposit > 0
            and ('Card closed. %s%s deposit returned.'):format(Config.Currency, card.deposit)
            or 'Card closed.' }

    elseif action == 'replace' then
        if card.kind ~= 'debit' and card.missed >= Config.CreditCards.missedBeforeFreeze and card.balance > 0 then
            return { ok = false, msg = 'Clear the outstanding balance before replacing this card.' }
        end
        if Config.Cards.replacementPrice > 0 then
            local ok = Bank.debit(card.account_id, Config.Cards.replacementPrice, {
                category = 'fee', label = 'Card replaced',
                actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
            })
            if not ok then return { ok = false, msg = 'Not enough in the account for a replacement.' } end
        end
        card.card_number, card.expires = newCardNumber(), expiryString()
        MySQL.update.await(
            'UPDATE nz_bank_cards SET card_number = ?, status = "active", expires = ?, spent_today = 0 WHERE id = ?',
            { card.card_number, card.expires, cardId })

        -- new plastic for the holder; the old card they still carry is swapped out,
        -- one that is somewhere else keeps the old number and no longer matches
        local to = holderSource(card, src)
        if to then
            for _, it in ipairs(CardItems.find(cardId, to)) do CardItems.take(it) end
            CardItems.give(to, card, acc.account_number)
        end
        return { ok = true, msg = 'A replacement card has been issued.' }
    end

    return { ok = false, msg = 'Unknown action.' }
end

--- Verify a PIN. Wrong entries eat an attempt and eventually block the card.
Bank.callback('nz_bank:verifyPin', function(src, cardId, pin)
    cardId = Bank.id(cardId)
    local card = cardId and MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card then return { ok = false, msg = 'Card not found.' } end
    -- only someone who can see the card, or has it in the machine in front of them,
    -- may guess at it, or anyone could lock everyone out
    local atm = Bank.atmSession(src)
    if not Bank.access(src, card.account_id) and not (atm and atm.cardId == cardId) then
        return { ok = false, msg = 'Card not found.' }
    end
    if card.status ~= 'active' then return { ok = false, msg = 'This card is not active.' } end

    Bank.session[src] = Bank.session[src] or { pinOk = {}, attempts = {} }
    local sess = Bank.session[src]
    sess.attempts = sess.attempts or {}

    if tostring(card.pin) == tostring(pin) then
        sess.pinOk[cardId] = true
        sess.attempts[cardId] = nil
        return { ok = true }
    end

    sess.attempts[cardId] = (sess.attempts[cardId] or 0) + 1
    local left = Config.ATM.pinAttempts - sess.attempts[cardId]

    if left <= 0 then
        MySQL.update.await('UPDATE nz_bank_cards SET status = "blocked" WHERE id = ?', { cardId })
        Bank.log('cards', 'Card auto-blocked', ('Card on account #%s blocked after failed PIN entries'):format(card.account_id))
        return { ok = false, msg = 'Too many wrong PINs. The card is now blocked.' }
    end

    return { ok = false, msg = ('Wrong PIN. %s attempt%s left.'):format(left, left == 1 and '' or 's') }
end)

Bank.callback('nz_bank:pinRequired', function(src, cardId, amount)
    if not Config.ATM.requirePin then return false end
    cardId = Bank.id(cardId)

    -- with pinEveryUse on, a previous success never counts
    if not Config.ATM.pinEveryUse then
        local sess = Bank.session[src]
        if sess and sess.pinOk and sess.pinOk[cardId] then return false end
    end

    if Config.Cards.express.enabled and amount and amount <= Config.Cards.express.threshold then
        local card = MySQL.single.await('SELECT express FROM nz_bank_cards WHERE id = ?', { cardId })
        if card and card.express == 1 then return false end
    end
    return true
end)

-- ═══════════════════════════════════════════════════════════
--  STOLEN CARDS
-- ═══════════════════════════════════════════════════════════
--- Called by whatever pickpocket / robbery resource you use.
--- exports['nayzeee-banking']:markCardStolen(cardId, thiefSource)
exports('markCardStolen', function(cardId, thiefSrc)
    if not Config.Cards.stealable then return false end
    local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card or card.status ~= 'active' then return false end

    local acc = Bank.getAccountById(card.account_id)

    -- the thief ends up with the card itself: tagged if their script already moved it,
    -- taken off whoever carries it otherwise, a fresh copy when it can't be found
    if Config.Cards.physicalItem and thiefSrc then
        local copies, mine = CardItems.find(card.id), nil
        for _, it in ipairs(copies) do
            if it.src == thiefSrc and CardItems.current(it.metadata, card) then mine = it break end
        end
        if mine then
            mine.metadata.stolen = true
            exports.ox_inventory:SetMetadata(mine.src, mine.slot, mine.metadata)
        else
            for _, it in ipairs(copies) do
                if CardItems.current(it.metadata, card) then CardItems.take(it) break end
            end
            CardItems.give(thiefSrc, card, acc and acc.account_number, { stolen = true })
        end
    end

    if acc and (acc.type == 'personal' or acc.type == 'shared') then
        local owner = ESX.GetPlayerFromIdentifier(acc.owner)
        if owner then
            Bank.notify(owner.source, 'Card missing',
                'One of your cards is no longer in your possession. Block it from the bank.', 'error')
        end
    end
    return true
end)

--- A player reports a card and freezes it permanently.
Bank.callback('nz_bank:reportCard', function(src, cardId)
    local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { cardId })
    if not card then return { ok = false, msg = 'Card not found.' } end

    local acc = Bank.access(src, card.account_id)
    if not acc then return { ok = false, msg = 'You cannot use this account.' } end

    MySQL.update.await('UPDATE nz_bank_cards SET status = "stolen" WHERE id = ?', { cardId })
    Bank.log('cards', 'Card reported stolen', ('Card on %s reported'):format(acc.label))
    return { ok = true, msg = 'Card reported. It can no longer be used.' }
end)


-- ═══════════════════════════════════════════════════════════
--  ATM CARD HANDLING
--  The card physically sits in the machine while it is in use,
--  so it cannot be handed off or stolen mid-transaction.
-- ═══════════════════════════════════════════════════════════
local inMachine = {}   -- [src] = { cardId, item, slot, meta, identifier }

-- ── card items in any inventory ───────────────────────────
--- Every card item the player carries: { name, slot, meta }.
function CardItems.held(src)
    local out, names = {}, {}
    for _, t in ipairs(Config.CardTypes) do if t.item then names[t.item] = true end end

    local inv = Bank.inventory()
    local ok, items = pcall(function()
        if inv == 'ox_inventory' then return exports.ox_inventory:GetInventoryItems(src) end
        if inv == 'qs-inventory' then return exports['qs-inventory']:GetInventory(src) end
        if inv == 'qb-inventory' then
            local list = {}
            for name in pairs(names) do
                for _, it in ipairs(exports['qb-inventory']:GetItemsByName(src, name) or {}) do list[#list + 1] = it end
            end
            return list
        end
    end)
    if not ok or type(items) ~= 'table' then return out end

    for _, it in pairs(items) do
        local meta = it.metadata or it.info
        if it.name and names[it.name] and type(meta) == 'table' and meta.cardId then
            out[#out + 1] = { name = it.name, slot = it.slot, meta = meta }
        end
    end
    return out
end

function CardItems.removeSlot(src, it)
    local inv = Bank.inventory()
    if inv == 'ox_inventory' then return exports.ox_inventory:RemoveItem(src, it.name, 1, it.meta, it.slot) end
    if inv == 'qs-inventory' then return exports['qs-inventory']:RemoveItem(src, it.name, 1, it.slot) end
    if inv == 'qb-inventory' then return exports['qb-inventory']:RemoveItem(src, it.name, 1, it.slot, 'nayzeee-banking') end
    return false
end

function CardItems.giveRaw(src, name, meta)
    local inv = Bank.inventory()
    if inv == 'ox_inventory' then return exports.ox_inventory:AddItem(src, name, 1, meta) end
    if inv == 'qs-inventory' then return exports['qs-inventory']:AddItem(src, name, 1, nil, meta) end
    if inv == 'qb-inventory' then return exports['qb-inventory']:AddItem(src, name, 1, false, meta, 'nayzeee-banking') end
    return false
end

-- ── which cards can go in the machine ─────────────────────
--- With physical cards on, the cards you can use are the ones in your pockets,
--- whoever they belong to. Without, it is the cards on your own accounts.
--- `foreign` marks a card that isn't the player's: it works, with its PIN,
--- on its own account only, and inside the card's daily limit.
local function usableCards(src)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return {}, nil end
    local out, declined = {}, nil

    local function add(card, item)
        if card.status ~= 'active' then
            declined = card.status == 'stolen' and 'That card was reported stolen.' or 'That card is blocked.'
            return
        end
        local acc = Bank.access(src, card.account_id)
        local mine = acc ~= nil and (card.holder_identifier == nil or card.holder_identifier == xPlayer.identifier)
        out[#out + 1] = { row = card, item = item, foreign = not mine }
    end

    -- the default ESX inventory keeps no metadata, so there is no card to carry there
    if Config.Cards.physicalItem and Bank.inventory() ~= 'esx' then
        local seen = {}
        for _, it in ipairs(CardItems.held(src)) do
            local id = Bank.id(it.meta.cardId)
            if id and not seen[id] then
                seen[id] = true
                local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { id })
                if card and CardItems.current(it.meta, card) then add(card, it)
                elseif card then declined = 'That card was replaced. Use the new one.' end
            end
        end
        return out, declined
    end

    local personal = Bank.getPersonal(xPlayer.identifier)
    local list = Bank.getCardsForPlayer(xPlayer.identifier, Bank.societyJobs(xPlayer))
    table.sort(list, function(a, b)
        local pa, pb = personal and a.account == personal.id, personal and b.account == personal.id
        if pa ~= pb then return pa end
        return (a.isDefault and 1 or 0) > (b.isDefault and 1 or 0)
    end)
    for _, c in ipairs(list) do
        if c.holderId == nil or c.holderId == xPlayer.identifier then
            local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { c.id })
            if card then add(card) end
        end
    end
    return out, declined
end

local function cardInfo(u)
    local c = u.row
    local t = Bank.cardType(c.card_type)
    return {
        id        = c.id,
        account   = c.account_id,
        kind      = c.kind,
        typeLabel = t.label,
        number    = c.card_number,
        last4     = c.card_number:sub(-4),
        holder    = c.holder,
        skin      = c.skin,
        -- which rendered card the ATM screen shows (web/images/cards)
        art       = t.item or ({ debit = 'card_debit', secured = 'card_secured', credit = 'card_credit' })[c.kind],
        foreign   = u.foreign or nil,
        label     = ('%s •%s'):format(t.label, c.card_number:sub(-4)),
    }
end

-- ox_inventory calls the client export straight from the item (install/items.md).
-- qs-inventory and the ESX route need the item registered as usable here.
CreateThread(function()
    if not Config.Cards.physicalItem then return end
    Wait(1000)
    local inv = Bank.inventory()
    if inv == 'ox_inventory' then return end

    for _, t in ipairs(Config.CardTypes) do
        if t.item then
            local use = function(source, item)
                local meta = type(item) == 'table' and (item.info or item.metadata) or nil
                TriggerClientEvent('nz_bank:useCardItem', source, meta or {})
            end
            if inv == 'qs-inventory' and GetResourceState('qs-inventory') == 'started' then
                pcall(function() exports['qs-inventory']:CreateUsableItem(t.item, use) end)
            elseif ESX and ESX.RegisterUsableItem then
                ESX.RegisterUsableItem(t.item, use)
            end
        end
    end
end)

Bank.callback('nz_bank:atmCards', function(src)
    local list, declined = usableCards(src)
    local out = {}
    for _, u in ipairs(list) do out[#out + 1] = cardInfo(u) end
    return { cards = out, declined = declined }
end)

--- Hand the card back. Called when the ATM closes, and on disconnect so a
--- card is never swallowed by a crash.
--- A player who drops mid-session may already be gone from their inventory, so
--- their card waits in KVP until they next load in. `quick` skips the database
--- (resource stop and disconnects can't wait on a query).
local function returnCard(src, dropped, quick)
    local held = inMachine[src]
    if not held then return end
    inMachine[src] = nil

    -- the style or number may have changed while it sat in the machine
    if not quick then
        local card = MySQL.single.await('SELECT * FROM nz_bank_cards WHERE id = ?', { held.cardId })
        if card and CardItems.current(held.meta, card) then
            local acc = Bank.getAccountById(card.account_id)
            local meta = CardItems.meta(card, acc and acc.account_number or held.meta.account)
            meta.stolen = held.meta.stolen
            held.meta = meta
        end
    end

    local given = not dropped and CardItems.giveRaw(src, held.item, held.meta)
    if not given and held.identifier then
        SetResourceKvp('nzb_card_return:' .. held.identifier, json.encode({ item = held.item, meta = held.meta }))
    end
end

Framework.onPlayerLoaded(function(src, xPlayer)
    local key = 'nzb_card_return:' .. xPlayer.identifier
    local saved = GetResourceKvpString(key)
    if not saved then return end
    local held = json.decode(saved)
    SetTimeout(5000, function()   -- let the inventory load them first
        if held and GetPlayerName(src) and CardItems.giveRaw(src, held.item, held.meta) then
            DeleteResourceKvp(key)
        end
    end)
end)

--- The player stood at a machine and put a card in. The server checks they
--- are really there and really hold that card, then keeps the card until
--- they walk away.
Bank.callback('nz_bank:atmStart', function(src, cardId, coords)
    returnCard(src)   -- a card left in from a session that never ended

    local chosen
    if Config.ATM.requireCard then
        local list, declined = usableCards(src)
        for _, u in ipairs(list) do
            if u.row.id == Bank.id(cardId) then chosen = u break end
        end
        if not chosen then
            return { ok = false, msg = declined or (Config.Cards.physicalItem
                and 'You don\'t have a bank card on you.'
                or 'You need an active bank card. Order one at any branch.') }
        end
    end

    local session = chosen and { id = chosen.row.id, account_id = chosen.row.account_id, foreign = chosen.foreign }
    if not Bank.startATM(src, coords, session) then
        return { ok = false, msg = 'Stand at the machine to use it.' }
    end

    -- a fresh PIN every visit; wrong attempts are kept
    Bank.session[src] = Bank.session[src] or { pinOk = {}, attempts = {} }
    if Config.ATM.pinEveryUse then Bank.session[src].pinOk = {} end

    local held = false
    if chosen and chosen.item and Config.ATM.holdCard and Config.Cards.physicalItem then
        if CardItems.removeSlot(src, chosen.item) then
            local xPlayer = Bank.getPlayer(src)
            inMachine[src] = { cardId = chosen.row.id, item = chosen.item.name, meta = chosen.item.meta,
                               identifier = xPlayer and xPlayer.identifier }
            held = true
        end
    end

    return { ok = true, held = held, card = chosen and cardInfo(chosen) or nil }
end)

Bank.callback('nz_bank:atmEnd', function(src)
    returnCard(src)
    Bank.endATM(src)

    -- forget the PIN so the next visit asks again
    if Config.ATM.pinEveryUse and Bank.session[src] then
        Bank.session[src].pinOk = {}   -- wrong-PIN attempts are kept, or walking away would reset them
    end
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    returnCard(source, true, true)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(inMachine) do returnCard(src, false, true) end
end)
