--[[
    NAYZEEE BILLING - Payments
    Pay (full / installment / tip / society account / by reference), bulk pay, distribution
    (VAT routing + revenue share), refunds, payouts, cash collection.
]]

RefundableStatuses = { paid = true, partial = true, overdue = true, disputed = true }

local Locks = {}

-- ██████╗ ██╗███████╗████████╗██████╗ ██╗██████╗ ██╗   ██╗████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔══██╗██║██╔════╝╚══██╔══╝██╔══██╗██║██╔══██╗██║   ██║╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██║  ██║██║███████╗   ██║   ██████╔╝██║██████╔╝██║   ██║   ██║   ██║██║   ██║██╔██╗ ██║
-- ██║  ██║██║╚════██║   ██║   ██╔══██╗██║██╔══██╗██║   ██║   ██║   ██║██║   ██║██║╚██╗██║
-- ██████╔╝██║███████║   ██║   ██║  ██║██║██████╔╝╚██████╔╝   ██║   ██║╚██████╔╝██║ ╚████║
-- ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝    ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

local function isSystem(identifier) return tostring(identifier):sub(1, 7) == 'system:' end

-- Society invoice: VAT -> VAT society (optional), revenue share -> issuer, rest -> society account
local function distributeSociety(row, amount, tip, payerName)
    local society = row.company_id
    local s = Config.Societies[society] or {}
    local owed = (tonumber(row.total) or 0) + (tonumber(row.late_fee) or 0)
    local vatPart = owed > 0 and Shared.Round(amount * (tonumber(row.tax) or 0) / owed) or 0

    local share = 0
    if Config.RevenueShare.Enabled and s.revenueShare ~= false and not isSystem(row.sender_identifier) then
        local rate = tonumber(s.revenueShare) or tonumber(Config.RevenueShare.Percent) or 0
        share = Shared.Round(math.max(0, (amount - vatPart) * rate))
    end

    local vatRouted = false
    if Config.VAT.Society and vatPart > 0 then
        vatRouted = Banking.AddSociety(Config.VAT.Society, vatPart, ('VAT · %s'):format(row.invoice_id))
    end

    local societyPart = Shared.Round(amount - share - (vatRouted and vatPart or 0))
    local toSociety = Config.Payment.SocietyDestination == 'society' and Banking.IsAvailable()
        and Banking.AddSociety(society, societyPart, ('Invoice %s · %s'):format(row.invoice_id, payerName))
    if not toSociety and not isSystem(row.sender_identifier) then share = share + societyPart end

    if share > 0 then Payout(row.sender_identifier, share, ('Revenue share · %s'):format(row.invoice_id), row.invoice_id) end
    if tip > 0 then
        local keepInSociety = Config.Tips.Recipient == 'society' or isSystem(row.sender_identifier)
        if not (keepInSociety and Banking.AddSociety(society, tip, ('Tip · %s'):format(row.invoice_id))) then
            Payout(row.sender_identifier, tip, ('Tip · %s'):format(row.invoice_id), row.invoice_id)
        end
    end
    return share
end

local function distributePersonal(row, amount, tip, method)
    if isSystem(row.sender_identifier) then return end
    local needsCollection = Config.Personal.CashRequiresCollection and method == 'cash'
    Payout(row.sender_identifier, amount + tip, ('Invoice %s'):format(row.invoice_id), row.invoice_id, needsCollection)
end

-- ██████╗  █████╗ ██╗   ██╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝
-- ██████╔╝███████║ ╚████╔╝
-- ██╔═══╝ ██╔══██║  ╚██╔╝
-- ██║     ██║  ██║   ██║
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝

--[[
    opts = {
        source?            payer (online) - nil for auto-collection
        payer = { identifier, name }       defaults to source
        id                 invoice id
        method             'bank' | 'cash' | 'society'
        amount?            installment
        tip?
        kind?              'payment' | 'bulk' | 'register' | 'autocollect'
        charged?           true when the caller already took the money (auto-collection)
    }
]]
function ProcessPayment(opts)
    local key = tostring(opts.id)
    if Locks[key] then return nil, L('error.processing', 'A payment for this invoice is already processing') end
    Locks[key] = true

    local ok, result, err = pcall(function()
        local row = GetInvoiceRow(tonumber(opts.id))
        if not row then return nil, L('error.not_found', 'Invoice not found') end
        if row.status == 'disputed' then return nil, L('error.under_dispute', 'This invoice is under dispute') end
        if not Shared.OpenStatuses[row.status] then return nil, L('error.already', 'This invoice is already {status}', { status = row.status }) end

        local source = opts.source
        local ctx = source and GetCtx(source) or nil
        local payer = opts.payer or { identifier = ctx and ctx.identifier, name = ctx and ctx.name }
        local method = opts.method
        local kind = opts.kind or 'payment'

        if not opts.charged then
            local options = PayOptions(ctx, row)
            if not options or not options[method] then return nil, L('error.cannot_pay_method', 'You cannot pay this invoice that way') end
        end

        local remaining = Remaining(row)
        if remaining <= 0 then return nil, L('error.nothing_left', 'Nothing left to pay') end
        local amount = remaining
        if opts.amount and Config.Payment.AllowPartial and kind == 'payment' then
            amount = Shared.Round(Shared.Clamp(opts.amount, math.min(Config.Payment.MinPartialAmount or 0, remaining), remaining))
        end

        local tip = 0
        if opts.tip and Config.Tips.Enabled and row.company_id and (Config.Societies[row.company_id] or {}).allowTips ~= false and kind ~= 'autocollect' then
            tip = Shared.Round(Shared.Clamp(opts.tip, 0, (tonumber(row.total) or 0) * (Config.Tips.MaxPercent or 50) / 100))
        end
        local charge = Shared.Round(amount + tip)
        local label = ('Invoice %s · %s'):format(row.invoice_id, row.company_id and SocietyLabel(row.company_id) or row.sender_name)

        local refundFn
        if not opts.charged then
            if method == 'society' then
                if not Banking.RemoveSociety(row.target_society, charge, label) then
                    return nil, L('error.society_funds', 'The society account cannot cover {amount}', { amount = Shared.Money(charge) })
                end
                refundFn = function() Banking.AddSociety(row.target_society, charge, 'Payment reverted · ' .. row.invoice_id) end
            else
                if Money.Get(source, method) < charge then
                    return nil, L('error.insufficient', 'Not enough {method} ({amount} needed)', {
                        method = method == 'cash' and L('label.cash', 'cash') or L('label.bank', 'bank'), amount = Shared.Money(charge) })
                end
                if not Money.Remove(source, method, charge, label) then return nil, L('error.declined', 'Payment declined') end
                refundFn = function() Money.Add(source, method, charge, 'Payment reverted') end
            end
        end

        local before = tonumber(row.amount_paid) or 0
        local affected = MySQL.update.await([[
            UPDATE nayzeee_billing_invoices SET
                status = IF(amount_paid + ? >= total + late_fee - 0.005, 'paid', 'partial'),
                paid_at = IF(amount_paid + ? >= total + late_fee - 0.005, NOW(), paid_at),
                amount_paid = amount_paid + ?, tip = tip + ?, payment_method = ?,
                paid_by_identifier = ?, paid_by_name = ?
            WHERE id = ? AND amount_paid = ? AND status IN ('pending','partial','overdue')
        ]], { amount, amount, amount, tip, method, payer.identifier, payer.name, row.id, before })
        if (affected or 0) == 0 then
            if refundFn then refundFn() end
            return nil, L('error.changed', 'The invoice changed while paying - you were not charged')
        end

        MySQL.insert.await([[INSERT INTO nayzeee_billing_payments (invoice_id, company_id, target_society, sender_identifier, payer_identifier, payer_name, amount, tip, method, kind)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            row.invoice_id, row.company_id, method == 'society' and row.target_society or nil, row.sender_identifier,
            payer.identifier, payer.name, amount, tip, method, kind })

        local share = 0
        if row.company_id then share = distributeSociety(row, amount, tip, payer.name)
        else distributePersonal(row, amount, tip, method) end

        local updated = GetInvoiceRow(row.id)
        local paid = updated.status == 'paid'

        if paid and source and Config.Items.Receipt.Enabled then
            Inventory.AddItem(source, Config.Items.Receipt.Name, 1, {
                reference = row.invoice_id,
                description = ('%s · %s · %s'):format(row.invoice_id, updated.company_name ~= 'Personal' and updated.company_name or row.sender_name, Shared.Money(updated.amount_paid)),
            })
        end
        local recipientSrc = (row.recipient_type or 'citizen') == 'citizen' and Framework.GetSource(row.target_identifier) or nil
        if paid and recipientSrc and Config.Items.Invoice.Enabled and Config.Items.Invoice.RemoveWhenPaid then
            Inventory.RemoveByReference(recipientSrc, Config.Items.Invoice.Name, row.invoice_id)
        end

        local senderSrc = Framework.GetSource(row.sender_identifier)
        if senderSrc then
            TriggerClientEvent('nayzeee-billing:client:invoicePaid', senderSrc, {
                ref = row.invoice_id, payer = payer.name, amount = amount, tip = tip, share = share, status = updated.status,
            })
        end
        if recipientSrc and recipientSrc ~= source then
            Notify(recipientSrc, L('notify.paid_for_you', 'Invoice paid'), L('notify.paid_for_you_body', '{name} paid {amount} on {ref}',
                { name = payer.name, amount = Shared.Money(amount), ref = row.invoice_id }), 'success')
            Refresh(recipientSrc)
        end

        if method == 'bank' and not Banking.HasPersonal() and payer.identifier then
            Banking.Log({ identifier = payer.identifier, amount = charge, type = 'withdraw', title = label, receiver = row.company_name })
        end

        local logData = { ref = row.invoice_id, amount = amount, tip = tip, method = method, target = row.target_name,
            status = updated.status, by = payer.name, byIdentifier = payer.identifier }
        Log(source, kind == 'autocollect' and 'invoice_collected' or 'invoice_paid', logData, method == 'society' and row.target_society or nil)
        if row.company_id then
            Log(nil, 'payment_received', { ref = row.invoice_id, amount = amount, from = payer.name, by = payer.name }, row.company_id)
        end

        local formatted = FormatInvoice(updated, ctx and { identifier = ctx.identifier, society = method == 'society' and ctx.society or nil } or nil)
        TriggerEvent('nayzeee-billing:server:invoicePaid', formatted, { amount = amount, tip = tip, method = method, payer = source })
        return { amount = amount, tip = tip, charged = charge, method = method, status = updated.status, remaining = formatted.remaining, invoice = formatted }
    end)

    Locks[key] = nil
    if not ok then
        print(('^1[NAYZEEE-BILLING]^7 Payment error (%s): %s'):format(key, tostring(result)))
        return nil, L('error.payment_failed', 'Payment failed')
    end
    return result, err
end

RPC('invoices:pay', function(source, payload)
    if Throttle(source, 'pay', 0.8) then return Err(L('error.slow_down', 'Slow down a little')) end
    local id = tonumber(payload.id)
    if not id and payload.ref then
        local row = GetInvoiceRow(NormalizeReference(payload.ref) or '')
        id = row and row.id
    end
    if not id then return Err(L('error.not_found', 'Invoice not found')) end
    local result, err = ProcessPayment({ source = source, id = id, method = payload.method, amount = payload.amount, tip = payload.tip })
    if not result then return Err(err) end
    return result
end)

-- Pay selected / pay all: full remaining of each, one method. Stops at the first "not enough money"
RPC('invoices:payMany', function(source, payload)
    if Throttle(source, 'paymany', 2) then return Err(L('error.slow_down', 'Slow down a little')) end
    if type(payload.ids) ~= 'table' or #payload.ids == 0 then return Err(L('error.none_selected', 'Select at least one invoice')) end
    local paid, failed, total = 0, {}, 0
    for i, id in ipairs(payload.ids) do
        if i > 50 then break end
        local result, err = ProcessPayment({ source = source, id = tonumber(id), method = payload.method, kind = 'bulk' })
        if result then
            paid = paid + 1
            total = total + result.charged
        else
            failed[#failed + 1] = { id = id, error = err }
            if payload.method ~= 'society' and Money.Get(source, payload.method) <= 0 then break end
        end
    end
    return { paid = paid, failed = failed, total = Shared.Round(total) }
end)

-- ██████╗ ███████╗███████╗██╗   ██╗███╗   ██╗██████╗ ███████╗
-- ██╔══██╗██╔════╝██╔════╝██║   ██║████╗  ██║██╔══██╗██╔════╝
-- ██████╔╝█████╗  █████╗  ██║   ██║██╔██╗ ██║██║  ██║███████╗
-- ██╔══██╗██╔══╝  ██╔══╝  ██║   ██║██║╚██╗██║██║  ██║╚════██║
-- ██║  ██║███████╗██║     ╚██████╔╝██║ ╚████║██████╔╝███████║
-- ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚══════╝

-- Returns every payment to whoever made it (personal bank or society account), out of the sender society account
function RefundInvoice(row, actorSource, reason)
    if not row.company_id then return nil, L('error.refund_society_only', 'Only society invoices can be refunded') end
    if not RefundableStatuses[row.status] then return nil, L('error.cannot_refund', 'This invoice cannot be refunded') end
    local amount = Shared.Round(tonumber(row.amount_paid) or 0)
    if amount <= 0 then return nil, L('error.nothing_to_refund', 'Nothing to refund') end
    if not Banking.IsAvailable() then return nil, L('error.no_banking', 'No society bank account is configured') end
    if not Banking.RemoveSociety(row.company_id, amount, 'Refund · ' .. row.invoice_id) then
        return nil, L('error.society_funds', 'The society account cannot cover {amount}', { amount = Shared.Money(amount) })
    end

    local affected = MySQL.update.await([[UPDATE nayzeee_billing_invoices SET status = 'refunded', cancel_reason = ?
        WHERE id = ? AND amount_paid = ? AND status IN ('paid','partial','overdue','disputed')]], { reason, row.id, row.amount_paid })
    if (affected or 0) == 0 then
        Banking.AddSociety(row.company_id, amount, 'Refund reverted · ' .. row.invoice_id)
        return nil, L('error.changed_refund', 'The invoice changed - nothing was refunded')
    end

    local payments = MySQL.query.await([[SELECT payer_identifier, target_society, method, SUM(amount) AS amount FROM nayzeee_billing_payments
        WHERE invoice_id = ? AND kind <> 'refund' GROUP BY payer_identifier, target_society, method]], { row.invoice_id }) or {}
    local returned = 0
    for _, p in ipairs(payments) do
        local part = math.min(Shared.Round(tonumber(p.amount) or 0), amount - returned)
        if part > 0 then
            if p.method == 'society' and p.target_society then
                Banking.AddSociety(p.target_society, part, 'Refund · ' .. row.invoice_id)
            else
                Payout(p.payer_identifier, part, 'Refund · ' .. row.invoice_id, row.invoice_id)
            end
            returned = returned + part
        end
    end
    if returned < amount and (row.recipient_type or 'citizen') == 'citizen' then
        Payout(row.target_identifier, amount - returned, 'Refund · ' .. row.invoice_id, row.invoice_id)
    end

    MySQL.insert.await([[INSERT INTO nayzeee_billing_payments (invoice_id, company_id, sender_identifier, payer_identifier, payer_name, amount, method, kind)
        VALUES (?, ?, ?, ?, ?, ?, 'bank', 'refund')]], { row.invoice_id, row.company_id, row.sender_identifier, row.target_identifier, row.target_name, -amount })

    local src = (row.recipient_type or 'citizen') == 'citizen' and Framework.GetSource(row.target_identifier)
    if src then
        Notify(src, L('notify.refunded', 'Refund issued'), L('notify.refunded_body', '{society} refunded {amount} for {ref}',
            { society = SocietyLabel(row.company_id), amount = Shared.Money(amount), ref = row.invoice_id }), 'success')
        Refresh(src)
    end
    Log(actorSource, 'invoice_refunded', { ref = row.invoice_id, amount = amount, reason = reason, target = row.target_name }, row.company_id)
    TriggerEvent('nayzeee-billing:server:invoiceRefunded', row.invoice_id, amount)
    return amount
end

RPC('invoices:refund', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(tonumber(payload.id))
    if not row or not row.company_id then return Err(L('error.not_found', 'Invoice not found')) end
    if not ctx.isAdmin and not Can(ctx, 'refund', row.company_id) then return Err(L('error.no_permission', 'You do not have permission')) end
    local reason = Shared.Sanitize(payload.reason, 200)
    if reason == '' then reason = L('label.refunded_by', 'Refunded by {name}', { name = ctx.name }) end
    local amount, err = RefundInvoice(row, source, reason)
    if not amount then return Err(err) end
    return { amount = amount }
end)

-- ██████╗  █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗████████╗███████╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗██║   ██║╚══██╔══╝██╔════╝
-- ██████╔╝███████║ ╚████╔╝ ██║   ██║██║   ██║   ██║   ███████╗
-- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║   ██║██║   ██║   ██║   ╚════██║
-- ██║     ██║  ██║   ██║   ╚██████╔╝╚██████╔╝   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝

local function claim(rows)
    local total = 0
    for _, r in ipairs(rows) do
        if (MySQL.update.await('DELETE FROM nayzeee_billing_pending_payouts WHERE id = ?', { r.id }) or 0) == 1 then
            total = total + (tonumber(r.amount) or 0)
        end
    end
    return Shared.Round(total)
end

AddEventHandler('nayzeee-billing:server:ready', function()
    Framework.OnPlayerLoaded(function(source)
        SetTimeout(4000, function()
            local identifier = Framework.GetIdentifier(source)
            if not identifier then return end

            local total = claim(MySQL.query.await('SELECT id, amount FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND requires_collection = 0', { identifier }) or {})
            if total > 0 then
                Money.Add(source, 'bank', total, 'Billing payouts')
                Notify(source, L('notify.payouts', 'Payments received'), L('notify.payouts_body', '{amount} from paid invoices', { amount = Shared.Money(total) }), 'success')
            end

            local open = MySQL.single.await([[SELECT COUNT(*) AS c, COALESCE(SUM(total + late_fee - amount_paid), 0) AS owed FROM nayzeee_billing_invoices
                WHERE COALESCE(recipient_type, 'citizen') = 'citizen' AND target_identifier = ? AND status IN ('pending','partial','overdue')]], { identifier })
            if open and (tonumber(open.c) or 0) > 0 then
                Notify(source, L('notify.unpaid', 'Unpaid invoices'), L('notify.unpaid_body', '{count} unpaid invoice(s) · {amount}',
                    { count = open.c, amount = Shared.Money(open.owed) }), 'warning')
            end
        end)
    end)
end)

RPC('collectCash', function(source)
    if Throttle(source, 'collect', 2) then return Err(L('error.slow_down', 'Slow down a little')) end
    local near = false
    for _, c in ipairs(Config.Payment.BankTellers or {}) do
        if DistanceTo(source, c) <= 4.0 then near = true break end
    end
    if not near then return Err(L('error.not_at_teller', 'You need to be at a bank teller')) end
    local identifier = Framework.GetIdentifier(source)
    local total = claim(MySQL.query.await('SELECT id, amount FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND requires_collection = 1', { identifier }) or {})
    if total > 0 then
        Money.Add(source, 'cash', total, 'Collected invoice cash')
        Log(source, 'cash_collected', { amount = total })
    end
    return { amount = total }
end)
