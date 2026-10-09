if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  BILLING BRIDGE
--  Invoices raised by other creators' resources land in this
--  bank's bills table instead of their own. Handlers are always
--  registered; they simply never fire if that resource is not
--  installed. Event names differ between forks — adjust them in
--  Config.Bridge if yours uses something else.
-- ═══════════════════════════════════════════════════════════

local function resolveIdentifier(target)
    if type(target) == 'string' and target:find(':') then return target end

    local xTarget = ESX.GetPlayerFromId(tonumber(target))
    if xTarget then return xTarget.identifier end
    return nil
end

local function senderName(src)
    local xPlayer = src and src > 0 and Bank.getPlayer(src)
    return xPlayer and Bank.fullName(xPlayer) or nil
end

--- Generic entry point. Anyone can call this:
---   TriggerEvent('nz_bank:bridgeBill', identifier, issuerJob, amount, reason, senderName)
local function raise(target, issuerJob, amount, reason, sender)
    local identifier = resolveIdentifier(target)
    if not identifier then
        Bank.debug('bridge: could not resolve target', tostring(target))
        return false
    end

    amount = Bank.round(amount)
    if amount <= 0 then return false end

    local ok = Bank.createBill(identifier, issuerJob or Config.Bridge.fallbackJob,
        amount, reason or 'Invoice', sender)

    if ok then
        Bank.debug(('bridge: billed %s %s%s for %s'):format(identifier, Config.Currency, amount, reason or 'Invoice'))
    end
    return ok
end

Bank.bridgeBill = raise

RegisterNetEvent('nz_bank:bridgeBill', function(target, issuerJob, amount, reason, sender)
    raise(target, issuerJob, amount, reason, sender or senderName(source))
end)

-- ── every configured billing event, one handler shape ──────
--  esx_billing  : (playerId, societyAccount, label, amount)
--  okokBilling  : (playerId, society, amount, reason)
--  qb / lb-phone: (table)
for _, eventName in ipairs(Config.Bridge.events or {}) do
    RegisterNetEvent(eventName, function(a, b, c, d)
        local src = source

        -- table payload (okokBilling, qb, lb-phone and most modern forks)
        if type(a) == 'table' then
            -- okokBilling: { authorPlayer = { source }, receiverPlayer = { source }, item, price, note }
            if a.receiverPlayer or a.authorPlayer then
                local receiver = a.receiverPlayer and a.receiverPlayer.source
                local author   = a.authorPlayer and a.authorPlayer.source
                local xAuthor  = author and ESX.GetPlayerFromId(tonumber(author))

                return raise(
                    receiver,
                    a.society or (xAuthor and xAuthor.job.name),
                    a.price or a.amount,
                    a.item or a.note or 'Invoice',
                    xAuthor and Bank.fullName(xAuthor) or senderName(src))
            end

            return raise(
                a.citizenid or a.identifier or a.playerId or a.target or a.to,
                a.society or a.job,
                a.amount or a.price,
                a.label or a.reason or a.message or a.item,
                a.sender or a.from or senderName(src))
        end

        -- positional payload, amount sits in different slots per resource
        local job = tostring(b or ''):gsub('^society_', '')
        local amount = tonumber(d) or tonumber(c)
        local reason = type(c) == 'string' and c or (type(d) == 'string' and d or 'Invoice')

        raise(a, job ~= '' and job or nil, amount, reason, senderName(src))
    end)
end

-- ═══════════════════════════════════════════════════════════
--  EXPORTS for other creators
--  exports['nayzeee-banking']:sendBill(playerId, job, amount, reason, sender)
-- ═══════════════════════════════════════════════════════════
exports('sendBill', function(target, issuerJob, amount, reason, sender)
    return raise(target, issuerJob, amount, reason, sender)
end)

exports('getAccountByNumber', function(number)
    local acc = Bank.getAccountByNumber(number)
    if not acc then return nil end
    return { id = acc.id, number = acc.account_number, type = acc.type,
             label = acc.label, balance = acc.balance, frozen = acc.frozen == 1 }
end)

--- Move money between any two accounts by number. Useful for shops,
--- rentals and anything that needs a paper trail on both sides.
exports('transferBetween', function(fromNumber, toNumber, amount, label)
    local from = Bank.getAccountByNumber(fromNumber)
    if not from then return false, 'Unknown source account.' end
    return Bank.doTransfer(from.id, toNumber, amount, nil, label or 'Transfer', label)
end)

--- Read-only summary another resource can render (phones, MDTs).
exports('getSummary', function(identifier)
    local personal = Bank.getPersonal(identifier)
    local savings  = Bank.getSavings(identifier)
    local credit   = Bank.getCredit(identifier)
    local bills    = Bank.getBills(identifier)

    return {
        account = personal and personal.account_number or nil,
        balance = personal and personal.balance or 0,
        savings = savings and savings.balance or 0,
        credit  = credit.score,
        band    = Bank.creditBand(credit.score),
        billsDue= bills.count,
        billsTotal = bills.total
    }
end)
