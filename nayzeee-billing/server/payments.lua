--[[
    NAYZEEE BILLING - Payments
    Pay (full / partial / tips), money distribution, refunds, payouts, cash collection.
]]

local PaymentLocks = {}

-- ██████╗  █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗████████╗███████╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗██║   ██║╚══██╔══╝██╔════╝
-- ██████╔╝███████║ ╚████╔╝ ██║   ██║██║   ██║   ██║   ███████╗
-- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║   ██║██║   ██║   ██║   ╚════██║
-- ██║     ██║  ██║   ██║   ╚██████╔╝╚██████╔╝   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝

-- Bank deposit to a player, or queued until they log in
function PayIdentifier(identifier, amount, reason, invoiceId, requiresCollection)
    amount = Shared.Round(amount)
    if not identifier or amount <= 0 then return end

    local src = (not requiresCollection) and Bridge.GetSourceFromIdentifier(identifier) or nil
    if src and Bridge.AddMoney(src, 'bank', amount, reason) then
        return src
    end

    MySQL.insert.await([[
        INSERT INTO nayzeee_billing_pending_payouts (identifier, amount, invoice_id, payment_method, requires_collection, reason)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { identifier, amount, invoiceId, requiresCollection and 'cash' or 'bank', requiresCollection and 1 or 0, reason })
    return nil
end

local function DeliverPendingPayouts(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return end

    local rows = MySQL.query.await([[
        SELECT id, amount FROM nayzeee_billing_pending_payouts
        WHERE identifier = ? AND (requires_collection = 0 OR requires_collection IS NULL)
    ]], { identifier }) or {}

    if #rows > 0 then
        local total, ids = 0, {}
        for _, row in ipairs(rows) do
            total = total + (tonumber(row.amount) or 0)
            ids[#ids + 1] = row.id
        end
        -- Delete first so a crash can't double-pay
        local deleted = MySQL.update.await(('DELETE FROM nayzeee_billing_pending_payouts WHERE id IN (%s)')
            :format(table.concat(ids, ',')))
        if (deleted or 0) > 0 then
            Bridge.AddMoney(source, 'bank', total, 'Billing payouts')
            Notify(source, 'Pending payments', 'Received ' .. Shared.FormatCurrency(total) .. ' from paid invoices', 'success')
        end
    end

    local cash = MySQL.scalar.await([[
        SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND requires_collection = 1
    ]], { identifier })
    if (tonumber(cash) or 0) > 0 then
        Notify(source, 'Cash awaiting collection', Shared.FormatCurrency(cash) .. ' is waiting for you at a bank teller', 'info')
    end
end

Bridge.OnPlayerLoaded(function(source)
    SetTimeout(4000, function()
        if not BillingReady then return end
        DeliverPendingPayouts(source)
        if ProcessAutoCollectFor then ProcessAutoCollectFor(source) end

        local identifier = Bridge.GetIdentifier(source)
        local open = identifier and MySQL.single.await([[
            SELECT COUNT(*) AS c, COALESCE(SUM(total + late_fee - amount_paid), 0) AS owed
            FROM nayzeee_billing_invoices WHERE target_identifier = ? AND status IN ('pending', 'partial', 'overdue')
        ]], { identifier })
        if open and (tonumber(open.c) or 0) > 0 then
            Notify(source, 'Unpaid invoices', ('You have %d unpaid invoice(s) totalling %s'):format(open.c, Shared.FormatCurrency(open.owed)), 'warning')
        end
    end)
end)

-- ██████╗ ██╗███████╗████████╗██████╗ ██╗██████╗ ██╗   ██╗████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║██╔══██╗██║   ██║╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██║  ██║██║███████╗   ██║   ██████╔╝██║██████╔╝██║   ██║   ██║   ██║██║   ██║██╔██╗ ██║
-- ██║  ██║██║╚════██║   ██║   ██╔══██╗██║██╔══██╗██║   ██║   ██║   ██║██║   ██║██║╚██╗██║
-- ██████╔╝██║███████║   ██║   ██║  ██║██║██████╔╝╚██████╔╝   ██║   ██║╚██████╔╝██║ ╚████║
-- ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝    ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

local function ResolveCompany(row)
    if row.company_id and Companies[row.company_id] then return Companies[row.company_id] end
    -- 1.x invoices: match by job / label
    if row.company_name and row.company_name ~= 'Personal' then
        if row.sender_job then
            local byJob = GetCompanyByJob(row.sender_job)
            if byJob then return byJob end
        end
        for _, c in pairs(Companies) do
            if c.label == row.company_name then return c end
        end
    end
    return nil
end

local function NotifySender(row, payerName, amount, extra)
    local src = Bridge.GetSourceFromIdentifier(row.sender_identifier)
    if not src then return end
    TriggerClientEvent('nayzeee-billing:client:invoicePaid', src, {
        invoiceId = row.invoice_id,
        playerName = payerName,
        amount = amount,
        commission = extra and extra.commission or 0,
        tip = extra and extra.tip or 0,
        destination = extra and extra.destination,
    })
end

-- Business invoice: tax -> treasury (optional), commission -> employee, rest -> company account
local function DistributeBusiness(row, company, amount, tip, payerName)
    local totalOwed = (tonumber(row.total) or 0) + (tonumber(row.late_fee) or 0)
    local taxPortion = totalOwed > 0 and Shared.Round(amount * (tonumber(row.tax) or 0) / totalOwed) or 0

    local rate = 0
    local cfg = Config.Payment.EmployeeCommission
    if cfg and cfg.Enabled then rate = tonumber(company.commission) or tonumber(cfg.Percentage) or 0 end
    local base = (cfg and cfg.ExcludeTax) and (amount - taxPortion) or amount
    local commission = Shared.Round(math.max(0, base * rate))

    -- Invoices created by other scripts (exports) have no employee to pay
    local isSystem = tostring(row.sender_identifier):sub(1, 7) == 'system:'
    if isSystem then commission = 0 end

    local taxRouted = false
    if Config.Tax.Account and taxPortion > 0 then
        taxRouted = Banking.AddSociety(Config.Tax.Account, taxPortion, 'Sales tax · ' .. row.invoice_id)
    end

    local companyAmount = Shared.Round(amount - commission - (taxRouted and taxPortion or 0))
    local account = Banking.AccountFor(company)
    local destination = 'employee'

    if Config.Payment.BusinessPaymentDestination == 'society' and Banking.IsAvailable() then
        if Banking.AddSociety(account, companyAmount, 'Invoice ' .. row.invoice_id .. ' · ' .. payerName) then
            destination = 'society'
            Banking.Log({
                account = account, amount = companyAmount, type = 'deposit',
                title = 'Invoice payment', description = row.invoice_id .. ' paid by ' .. payerName, issuer = payerName,
            })
        end
    end
    if destination == 'employee' and not isSystem then
        commission = commission + companyAmount
    end

    if commission > 0 then
        PayIdentifier(row.sender_identifier, commission, 'Commission · ' .. row.invoice_id, row.invoice_id)
    end

    if tip > 0 then
        if (Config.Tips.Recipient == 'society' or isSystem) and Banking.IsAvailable()
            and Banking.AddSociety(account, tip, 'Tip · ' .. row.invoice_id) then
            -- tip kept by company
        else
            PayIdentifier(row.sender_identifier, tip, 'Tip · ' .. row.invoice_id, row.invoice_id)
        end
    end

    NotifySender(row, payerName, amount, { commission = commission, tip = tip, destination = destination })
end

-- Personal invoice: straight to the sender (cash may need collecting at a bank teller)
local function DistributePersonal(row, amount, tip, method, payerName)
    local total = amount + tip
    if tostring(row.sender_identifier):sub(1, 7) == 'system:' then return end
    local cfg = Config.Payment.PersonalInvoice or {}
    local needsCollection = cfg.CashRequiresCollection and method == 'cash'
    local src = PayIdentifier(row.sender_identifier, total, 'Invoice ' .. row.invoice_id, row.invoice_id, needsCollection)

    local senderSrc = src or Bridge.GetSourceFromIdentifier(row.sender_identifier)
    if senderSrc then
        NotifySender(row, payerName, total, { destination = needsCollection and 'bank_collection' or 'bank', tip = tip })
        if needsCollection then
            Notify(senderSrc, 'Cash payment received', 'Collect ' .. Shared.FormatCurrency(total) .. ' from a bank teller', 'info')
        end
    end
end

-- ██████╗  █████╗ ██╗   ██╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝
-- ██████╔╝███████║ ╚████╔╝
-- ██╔═══╝ ██╔══██║  ╚██╔╝
-- ██║     ██║  ██║   ██║
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝

--[[
    opts = { source, invoiceId, method = 'bank'|'cash', amount? (partial), tip?, kind? = 'payment'|'autocollect', allowNegative? }
    returns result table or nil, error
]]
function ProcessPayment(opts)
    local invoiceId = opts.invoiceId
    if type(invoiceId) ~= 'string' then return nil, 'Invalid invoice' end
    if PaymentLocks[invoiceId] then return nil, 'A payment for this invoice is already processing' end
    PaymentLocks[invoiceId] = true

    local ok, result, err = pcall(function()
        local source = opts.source
        local identifier = Bridge.GetIdentifier(source)
        local row = GetInvoiceRow(invoiceId)
        if not row or row.target_identifier ~= identifier then return nil, 'Invoice not found' end
        if row.status == 'disputed' then return nil, 'This invoice is under dispute' end
        if not (row.status == 'pending' or row.status == 'partial' or row.status == 'overdue') then
            return nil, 'This invoice is already ' .. row.status
        end

        local method = opts.method == 'cash' and 'cash' or 'bank'
        if not Config.Payment.Methods[method] then return nil, 'That payment method is disabled' end

        local remaining = Remaining(row)
        if remaining <= 0 then return nil, 'Nothing left to pay' end

        local amount = remaining
        if opts.amount and Config.Payment.AllowPartial then
            local minimum = math.min(tonumber(Config.Payment.MinPartialAmount) or 0, remaining)
            amount = Shared.Round(Shared.Clamp(opts.amount, minimum, remaining))
        end

        local company = ResolveCompany(row)
        local tip = 0
        if (opts.kind or 'payment') == 'payment' and Config.Tips.Enabled and company and company.allowTips and opts.tip then
            tip = Shared.Round(Shared.Clamp(opts.tip, 0, (tonumber(row.total) or 0) * (Config.Tips.MaxPercent or 50) / 100))
        end

        local charge = Shared.Round(amount + tip)
        if not opts.allowNegative and Bridge.GetMoney(source, method) < charge then
            return nil, ('Insufficient %s (%s needed)'):format(method == 'cash' and 'cash' or 'funds', Shared.FormatCurrency(charge))
        end
        if not Bridge.RemoveMoney(source, method, charge, 'Invoice ' .. invoiceId) then
            return nil, 'Payment declined'
        end

        -- Optimistic lock on amount_paid: nobody else touched this invoice in between
        local paidBefore = tonumber(row.amount_paid) or 0
        local affected = MySQL.update.await([[
            UPDATE nayzeee_billing_invoices SET
                status = IF(amount_paid + ? >= total + late_fee - 0.005, 'paid', 'partial'),
                paid_at = IF(amount_paid + ? >= total + late_fee - 0.005, NOW(), paid_at),
                amount_paid = amount_paid + ?,
                tip = tip + ?,
                payment_method = ?
            WHERE invoice_id = ? AND amount_paid = ? AND status IN ('pending', 'partial', 'overdue')
        ]], { amount, amount, amount, tip, method, invoiceId, paidBefore })

        if (affected or 0) == 0 then
            Bridge.AddMoney(source, method, charge, 'Invoice payment reverted')
            return nil, 'Invoice changed while paying - you were not charged'
        end

        local payerName = Bridge.GetName(source)
        MySQL.insert.await([[
            INSERT INTO nayzeee_billing_payments (invoice_id, company_id, sender_identifier, payer_identifier, payer_name, amount, tip, method, kind)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], { invoiceId, company and company.id or nil, row.sender_identifier, identifier, payerName, amount, tip, method, opts.kind or 'payment' })

        if company then
            DistributeBusiness(row, company, amount, tip, payerName)
        else
            DistributePersonal(row, amount, tip, method, payerName)
        end

        if method == 'bank' then
            Banking.Log({
                identifier = identifier, name = payerName, amount = charge, type = 'withdraw',
                title = 'Invoice ' .. invoiceId, description = 'Paid to ' .. (row.company_name or row.sender_name),
                receiver = row.company_name,
            })
        end

        local updated = GetInvoiceRow(invoiceId)
        local fullyPaid = updated.status == 'paid'

        if fullyPaid and Config.Receipts.GiveReceiptItem then
            Inventory.AddItem(source, Config.Receipts.ReceiptItemName, 1, {
                invoiceId = invoiceId,
                description = ('%s · %s · %s'):format(invoiceId, row.company_name, Shared.FormatCurrency(updated.amount_paid)),
            })
        end

        Log(source, opts.kind == 'autocollect' and 'invoice_autocollected' or 'invoice_paid', {
            invoice = invoiceId, amount = amount, tip = tip, method = method, status = updated.status,
        }, company and company.id)

        local formatted = FormatInvoice(updated, identifier)
        TriggerEvent('nayzeee-billing:server:invoicePaid', formatted, { amount = amount, tip = tip, method = method, payer = source })

        return {
            amount = amount, tip = tip, charged = charge, method = method,
            status = updated.status, remaining = formatted.remaining,
            receipt = (fullyPaid and Config.Receipts.ShowOnPayment) and formatted or nil,
            invoice = formatted,
        }
    end)

    PaymentLocks[invoiceId] = nil
    if not ok then
        print(('^1[NAYZEEE-BILLING]^7 Payment error (%s): %s'):format(invoiceId, tostring(result)))
        return nil, 'Payment failed'
    end
    return result, err
end

RPC('payInvoice', function(source, payload)
    if Throttle(source, 'pay', 1) then return Err('Slow down a little') end
    local result, err = ProcessPayment({
        source = source,
        invoiceId = payload.invoiceId,
        method = payload.method,
        amount = payload.amount,
        tip = payload.tip,
    })
    if not result then return Err(err) end
    return result
end)

-- ██████╗ ███████╗███████╗██╗   ██╗███╗   ██╗██████╗ ███████╗
-- ██╔══██╗██╔════╝██╔════╝██║   ██║████╗  ██║██╔══██╗██╔════╝
-- ██████╔╝█████╗  █████╗  ██║   ██║██╔██╗ ██║██║  ██║███████╗
-- ██╔══██╗██╔══╝  ██╔══╝  ██║   ██║██║╚██╗██║██║  ██║╚════██║
-- ██║  ██║███████╗██║     ╚██████╔╝██║ ╚████║██████╔╝███████║
-- ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚══════╝

function RefundInvoice(row, actorSource, reason)
    local company = ResolveCompany(row)
    if not company then return nil, 'Only company invoices can be refunded' end
    if not (row.status == 'paid' or row.status == 'partial') then return nil, 'Only paid invoices can be refunded' end

    local amount = Shared.Round(tonumber(row.amount_paid) or 0)
    if amount <= 0 then return nil, 'Nothing to refund' end

    if not Banking.IsAvailable() then return nil, 'No company bank account configured' end
    local account = Banking.AccountFor(company)
    if not Banking.RemoveSociety(account, amount, 'Refund · ' .. row.invoice_id) then
        return nil, 'The company account cannot cover this refund'
    end

    local affected = MySQL.update.await([[
        UPDATE nayzeee_billing_invoices SET status = 'refunded', cancel_reason = ?
        WHERE invoice_id = ? AND status IN ('paid', 'partial') AND amount_paid = ?
    ]], { reason, row.invoice_id, row.amount_paid })
    if (affected or 0) == 0 then
        Banking.AddSociety(account, amount, 'Refund reverted · ' .. row.invoice_id)
        return nil, 'Invoice changed - refund aborted'
    end

    PayIdentifier(row.target_identifier, amount, 'Refund · ' .. row.invoice_id, row.invoice_id)
    MySQL.insert.await([[
        INSERT INTO nayzeee_billing_payments (invoice_id, company_id, sender_identifier, payer_identifier, payer_name, amount, tip, method, kind)
        VALUES (?, ?, ?, ?, ?, ?, 0, 'bank', 'refund')
    ]], { row.invoice_id, company.id, row.sender_identifier, row.target_identifier, row.target_name, -amount })

    local targetSrc = Bridge.GetSourceFromIdentifier(row.target_identifier)
    if targetSrc then
        Notify(targetSrc, 'Refund issued', ('%s refunded %s for %s'):format(company.label, Shared.FormatCurrency(amount), row.invoice_id), 'success')
        TriggerClientEvent('nayzeee-billing:client:invoiceChanged', targetSrc, row.invoice_id)
    end
    Banking.Log({
        account = account, amount = amount, type = 'withdraw',
        title = 'Invoice refund', description = row.invoice_id .. ' refunded to ' .. row.target_name,
    })
    Log(actorSource, 'invoice_refunded', { invoice = row.invoice_id, amount = amount, reason = reason }, company.id)
    TriggerEvent('nayzeee-billing:server:invoiceRefunded', row.invoice_id, amount)
    return amount
end

-- ████████╗███████╗██╗     ██╗     ███████╗██████╗
-- ╚══██╔══╝██╔════╝██║     ██║     ██╔════╝██╔══██╗
--    ██║   █████╗  ██║     ██║     █████╗  ██████╔╝
--    ██║   ██╔══╝  ██║     ██║     ██╔══╝  ██╔══██╗
--    ██║   ███████╗███████╗███████╗███████╗██║  ██║
--    ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝

RPC('collectCash', function(source)
    if Throttle(source, 'collect', 2) then return Err('Slow down a little') end

    local nearTeller = false
    for _, teller in ipairs(Config.Payment.BankTellers or {}) do
        if GetDistanceTo(source, teller.coords) <= 4.0 then nearTeller = true break end
    end
    if not nearTeller then return Err('You need to be at a bank teller') end

    local identifier = Bridge.GetIdentifier(source)
    local rows = MySQL.query.await('SELECT id, amount FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND requires_collection = 1',
        { identifier }) or {}
    if #rows == 0 then return { amount = 0 } end

    local total, ids = 0, {}
    for _, row in ipairs(rows) do
        total = total + (tonumber(row.amount) or 0)
        ids[#ids + 1] = row.id
    end

    local deleted = MySQL.update.await(('DELETE FROM nayzeee_billing_pending_payouts WHERE id IN (%s)'):format(table.concat(ids, ',')))
    if (deleted or 0) == 0 then return { amount = 0 } end

    Bridge.AddMoney(source, 'cash', total, 'Collected invoice cash')
    Log(source, 'cash_collected', { amount = total })
    return { amount = Shared.Round(total) }
end)
