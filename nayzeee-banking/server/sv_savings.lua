if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  SAVINGS
-- ═══════════════════════════════════════════════════════════

local function readMeta(acc)
    if not acc or not acc.meta then return {} end
    local ok, decoded = pcall(json.decode, acc.meta)
    return ok and decoded or {}
end

local function writeMeta(accountId, meta)
    MySQL.update.await('UPDATE nz_bank_accounts SET meta = ? WHERE id = ?', { json.encode(meta), accountId })
end

function Bank.trackSavings(accountId, deposited, earned)
    local acc = Bank.getAccountById(accountId)
    local meta = readMeta(acc)
    meta.deposited = (meta.deposited or 0) + (deposited or 0)
    meta.earned    = (meta.earned or 0) + (earned or 0)
    meta.lastInterest = meta.lastInterest or os.time()
    writeMeta(accountId, meta)
end

function Bank.getSavingsState(identifier)
    local acc = Bank.getSavings(identifier)
    if not acc then
        return { open = false, rate = Config.Savings.interestRate }
    end
    local meta = readMeta(acc)
    local nextIn = 0
    if meta.lastInterest then
        nextIn = math.max(0, math.floor(((meta.lastInterest + Config.Savings.payoutMinutes * 60) - os.time()) / 60))
    end
    return {
        open      = true,
        id        = acc.id,
        number    = acc.account_number,
        balance   = acc.balance,
        deposited = meta.deposited or 0,
        earned    = meta.earned or 0,
        rate      = Config.Savings.interestRate,
        nextIn    = nextIn,
        goal      = meta.goal
    }
end

Bank.callback('nz_bank:openSavings', function(src)
    if not Config.Savings.enabled then return { ok = false, msg = 'Savings accounts are disabled.' } end

    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    if Bank.getSavings(xPlayer.identifier) then
        return { ok = false, msg = 'You already hold a savings account.' }
    end

    if Config.Accounts.savingsCreationCost > 0 then
        local personal = Bank.getPersonal(xPlayer.identifier)
        local ok = Bank.debit(personal.id, Config.Accounts.savingsCreationCost, {
            category = 'fee', label = 'Savings account opened',
            actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
        })
        if not ok then
            return { ok = false, msg = ('Opening one costs %s%s.'):format(Config.Currency, Config.Accounts.savingsCreationCost) }
        end
    end

    local number = Bank.newAccountNumber('SAV')
    local id = MySQL.insert.await([[
        INSERT INTO nz_bank_accounts (account_number, type, owner, label, balance, meta)
        VALUES (?, "savings", ?, ?, 0, ?)
    ]], { number, xPlayer.identifier, 'Savings', json.encode({ deposited = 0, earned = 0, lastInterest = os.time() }) })

    return { ok = true, msg = 'Savings account open.', id = id }
end)

Bank.callback('nz_bank:setSavingsGoal', function(src, amount)
    local xPlayer = Bank.getPlayer(src)
    local acc = Bank.getSavings(xPlayer.identifier)
    if not acc then return { ok = false, msg = 'Open a savings account first.' } end

    amount = Bank.round(amount)
    if amount < 0 or amount > Config.Savings.maxBalance then
        return { ok = false, msg = 'Pick a goal inside the account limit.' }
    end

    local meta = readMeta(acc)
    meta.goal = amount > 0 and amount or nil
    writeMeta(acc.id, meta)

    return { ok = true, msg = amount > 0
        and ('Goal set to %s%s.'):format(Config.Currency, amount)
        or 'Goal cleared.' }
end)

-- ═══════════════════════════════════════════════════════════
--  INTEREST LOOP
-- ═══════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        Wait(300000) -- check every 5 minutes
        if Config.Savings.enabled then
            local accounts = MySQL.query.await(
                'SELECT * FROM nz_bank_accounts WHERE type = "savings" AND balance > 0 AND frozen = 0') or {}

            for _, acc in ipairs(accounts) do
                local meta = readMeta(acc)
                local last = meta.lastInterest or 0
                local dueAt = last + (Config.Savings.payoutMinutes * 60)

                if os.time() >= dueAt then
                    local xPlayer = ESX.GetPlayerFromIdentifier(acc.owner)
                    if not Config.Savings.requireOnline or xPlayer then
                        local interest = Bank.round(acc.balance * Config.Savings.interestRate)
                        if interest > 0 then
                            Bank.credit(acc.id, interest, {
                                category = 'interest', label = 'Savings interest'
                            })
                            meta.earned = (meta.earned or 0) + interest
                            if xPlayer then
                                Bank.notify(xPlayer.source, 'Interest paid',
                                    ('%s%s added to your savings.'):format(Config.Currency, interest), 'success')
                            end
                        end
                    end
                    meta.lastInterest = os.time()
                    writeMeta(acc.id, meta)
                end
            end
        end
    end
end)
