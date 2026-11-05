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

    local vatRouted = 0
    if Config.VAT.Society and vatPart > 0 and Banking.AddSociety(Config.VAT.Society, vatPart, ('VAT · %s'):format(row.invoice_id)) then
        vatRouted = vatPart
    end

    local societyPart = Shared.Round(amount - share - vatRouted)
    local societyLabel = ('Invoice %s · %s'):format(row.invoice_id, payerName)
    local toSociety = Config.Payment.SocietyDestination == 'society' and Banking.IsAvailable()
        and Banking.AddSociety(society, societyPart, societyLabel)
    if not toSociety then
        -- System invoices have no employee to fall back on: hold the money for the society instead of losing it
        if isSystem(row.sender_identifier) then QueueSociety(society, societyPart, societyLabel, row.invoice_id)
        else share = share + societyPart end
    end

    if share > 0 then Payout(row.sender_identifier, share, ('Revenue share · %s'):format(row.invoice_id), row.invoice_id) end
    if tip > 0 then
        local tipLabel = ('Tip · %s'):format(row.invoice_id)
        local keepInSociety = Config.Tips.Recipient == 'society' or isSystem(row.sender_identifier)
        if not (keepInSociety and Banking.AddSociety(society, tip, tipLabel)) then
            if isSystem(row.sender_identifier) then QueueSociety(society, tip, tipLabel, row.invoice_id)
            else Payout(row.sender_identifier, tip, tipLabel, row.invoice_id) end
        end
    end
    -- share = what the issuer was paid from this payment, vatRouted = what went to the VAT society (both clawed back on refund)
    return share, vatRouted
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
        if opts.charged then
            -- The caller took exactly opts.amount: book that or nothing (an installment may have landed meanwhile)
            if math.abs(remaining - (tonumber(opts.amount) or -1)) > 0.005 then
                return nil, L('error.changed', 'The invoice changed while paying - you were not charged')
            end
        elseif opts.amount and Config.Payment.AllowPartial and kind == 'payment' then
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

        local share, vatRouted = 0, 0
        if row.company_id then share, vatRouted = distributeSociety(row, amount, tip, payer.name)
        else distributePersonal(row, amount, tip, method) end

        MySQL.insert.await([[INSERT INTO nayzeee_billing_payments (invoice_id, company_id, target_society, sender_identifier, payer_identifier, payer_name, amount, tip, method, kind, share, vat_routed)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            row.invoice_id, row.company_id, method == 'society' and row.target_society or nil, row.sender_identifier,
            payer.identifier, payer.name, amount, tip, method, kind, share, vatRouted })

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
        Console.log('error', 'Payment error (invoice %s): %s', key, tostring(result))
        return nil, L('error.payment_failed', 'Payment failed')
    end
    return result, err
end

-- Invoices the caller isn't part of can only be reached with their reference (pay by reference),
-- so sequential ids can't be used to probe or pay strangers' invoices
local function payableRow(source, ctx, id, ref)
    local row = GetInvoiceRow(tonumber(id) or NormalizeReference(ref) or '')
    if not row or not ctx then return nil end
    if CanViewInvoice(source, ctx, row) then return row end
    if Config.Payment.PayByReference and NormalizeReference(ref) == row.invoice_id then return row end
    return nil
end

RPC('invoices:pay', function(source, payload)
    if Throttle(source, 'pay', 0.8) then return Err(L('error.slow_down', 'Slow down a little')) end
    local ctx = GetCtx(source)
    local row = payableRow(source, ctx, payload.id, payload.ref)
    if not row then return Err(L('error.not_found', 'Invoice not found')) end
    local result, err = ProcessPayment({ source = source, id = row.id, method = payload.method, amount = payload.amount, tip = payload.tip })
    if not result then return Err(err) end
    return result
end)

-- Pay selected / pay all: full remaining of each, one method. Stops at the first "not enough money"
RPC('invoices:payMany', function(source, payload)
    if Throttle(source, 'paymany', 2) then return Err(L('error.slow_down', 'Slow down a little')) end
    if type(payload.ids) ~= 'table' or #payload.ids == 0 then return Err(L('error.none_selected', 'Select at least one invoice')) end
    local ctx = GetCtx(source)
    local paid, failed, total = 0, {}, 0
    for i, id in ipairs(payload.ids) do
        if i > 50 then break end
        local row = payableRow(source, ctx, id)
        local result, err
        if row then result, err = ProcessPayment({ source = source, id = row.id, method = payload.method, kind = 'bulk' })
        else err = L('error.not_found', 'Invoice not found') end
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

local function requeue(rows)
    for _, r in ipairs(rows or {}) do
        MySQL.insert.await([[INSERT INTO nayzeee_billing_pending_payouts (identifier, amount, invoice_id, payment_method, requires_collection, reason)
            VALUES (?, ?, ?, ?, ?, ?)]], { r.identifier, r.amount, r.invoice_id or '', r.payment_method or 'bank', (r.requires_collection == true or tonumber(r.requires_collection) == 1) and 1 or 0, r.reason })
    end
end

-- Takes back money a character earned from an invoice: unclaimed payouts first, then their bank (offline too).
-- Returns the amount recovered and a function that undoes it.
local function clawBack(identifier, amount, ref, reason)
    amount = Shared.Round(amount)
    if amount <= 0 or not identifier or isSystem(identifier) then return 0, function() end end
    local taken, removed = 0, {}
    local rows = MySQL.query.await('SELECT * FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND invoice_id = ? ORDER BY amount DESC',
        { identifier, ref }) or {}
    for _, r in ipairs(rows) do
        local a = tonumber(r.amount) or 0
        if taken + a <= amount + 0.005 and (MySQL.update.await('DELETE FROM nayzeee_billing_pending_payouts WHERE id = ?', { r.id }) or 0) == 1 then
            taken = taken + a
            removed[#removed + 1] = r
        end
    end
    local rest, charged = Shared.Round(amount - taken), 0
    if rest > 0 and Money.ChargeBank(identifier, rest, reason, true, true) then charged = rest end
    return Shared.Round(taken + charged), function()
        requeue(removed)
        if charged > 0 then Money.DepositTo(identifier, charged, reason .. ' (reverted)') end
    end
end

--[[
    Returns every payment to whoever made it (personal bank or society account).
    Society invoices: the revenue share is taken back from the issuer and routed VAT from the VAT society;
    the society account covers the rest. Personal invoices: the sender pays it back.
]]
function RefundInvoice(row, actorSource, reason, actorIdentifier)
    if not RefundableStatuses[row.status] then return nil, L('error.cannot_refund', 'This invoice cannot be refunded') end
    local amount = Shared.Round(tonumber(row.amount_paid) or 0)
    if amount <= 0 then return nil, L('error.nothing_to_refund', 'Nothing to refund') end
    local ref, label = row.invoice_id, 'Refund · ' .. row.invoice_id

    local payments = MySQL.query.await([[SELECT payer_identifier, target_society, method, SUM(amount) AS amount,
        COALESCE(SUM(share), 0) AS share, COALESCE(SUM(vat_routed), 0) AS vat
        FROM nayzeee_billing_payments WHERE invoice_id = ? AND kind <> 'refund' GROUP BY payer_identifier, target_society, method]], { ref }) or {}
    local shareTotal, vatTotal, payers = 0, 0, {}
    for _, p in ipairs(payments) do
        shareTotal = shareTotal + (tonumber(p.share) or 0)
        vatTotal = vatTotal + (tonumber(p.vat) or 0)
        payers[p.payer_identifier] = true
    end
    shareTotal, vatTotal = Shared.Round(math.min(shareTotal, amount)), Shared.Round(vatTotal)

    local reverts = {}
    local function undo() for i = #reverts, 1, -1 do reverts[i]() end end

    if row.company_id then
        if not Banking.IsAvailable() then return nil, L('error.no_banking', 'No society bank account is configured') end
        local recovered = 0
        if vatTotal > 0 and Config.VAT.Society and Banking.RemoveSociety(Config.VAT.Society, vatTotal, label) then
            recovered = recovered + vatTotal
            reverts[#reverts + 1] = function() Banking.AddSociety(Config.VAT.Society, vatTotal, label .. ' (reverted)') end
        end
        if shareTotal > 0 then
            local got, revert = clawBack(row.sender_identifier, shareTotal, ref, label)
            reverts[#reverts + 1] = revert
            -- The society only covers a missing share when the refund isn't self-dealing
            if got < shareTotal - 0.005 and actorIdentifier and (actorIdentifier == row.sender_identifier or payers[actorIdentifier]) then
                undo()
                return nil, L('error.refund_share', 'The revenue share paid on this invoice could not be recovered')
            end
            recovered = recovered + got
        end
        local fromSociety = Shared.Round(amount - recovered)
        if fromSociety > 0 then
            if not Banking.RemoveSociety(row.company_id, fromSociety, label) then
                undo()
                return nil, L('error.society_funds', 'The society account cannot cover {amount}', { amount = Shared.Money(fromSociety) })
            end
            reverts[#reverts + 1] = function() Banking.AddSociety(row.company_id, fromSociety, label .. ' (reverted)') end
        end
    else
        local got, revert = clawBack(row.sender_identifier, amount, ref, label)
        reverts[#reverts + 1] = revert
        if got < amount - 0.005 then
            undo()
            return nil, L('error.refund_funds', '{name} cannot cover the refund of {amount}', { name = row.sender_name or '?', amount = Shared.Money(amount) })
        end
    end

    local affected = MySQL.update.await([[UPDATE nayzeee_billing_invoices SET status = 'refunded', cancel_reason = ?
        WHERE id = ? AND amount_paid = ? AND status IN ('paid','partial','overdue','disputed')]], { reason, row.id, row.amount_paid })
    if (affected or 0) == 0 then
        undo()
        return nil, L('error.changed_refund', 'The invoice changed - nothing was refunded')
    end

    local returned = 0
    for _, p in ipairs(payments) do
        local part = math.min(Shared.Round(tonumber(p.amount) or 0), amount - returned)
        if part > 0 then
            if p.method == 'society' and p.target_society then
                if not Banking.AddSociety(p.target_society, part, label) then QueueSociety(p.target_society, part, label, ref) end
            else
                Payout(p.payer_identifier, part, label, ref)
            end
            returned = returned + part
        end
    end
    if returned < amount and (row.recipient_type or 'citizen') == 'citizen' then
        Payout(row.target_identifier, amount - returned, label, ref)
    end

    MySQL.insert.await([[INSERT INTO nayzeee_billing_payments (invoice_id, company_id, sender_identifier, payer_identifier, payer_name, amount, method, kind)
        VALUES (?, ?, ?, ?, ?, ?, 'bank', 'refund')]], { ref, row.company_id, row.sender_identifier, row.target_identifier, row.target_name, -amount })

    local from = row.company_id and SocietyLabel(row.company_id) or row.sender_name
    local src = (row.recipient_type or 'citizen') == 'citizen' and Framework.GetSource(row.target_identifier)
    if src then
        Notify(src, L('notify.refunded', 'Refund issued'), L('notify.refunded_body', '{society} refunded {amount} for {ref}',
            { society = from, amount = Shared.Money(amount), ref = ref }), 'success')
        Refresh(src)
    end
    Log(actorSource, 'invoice_refunded', { ref = ref, amount = amount, reason = reason, target = row.target_name }, row.company_id)
    TriggerEvent('nayzeee-billing:server:invoiceRefunded', ref, amount)
    return amount
end

RPC('invoices:refund', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(tonumber(payload.id))
    if not row then return Err(L('error.not_found', 'Invoice not found')) end
    local allowed = ctx.isAdmin or (row.company_id and Can(ctx, 'refund', row.company_id))
        or (not row.company_id and row.sender_identifier == ctx.identifier)
    if not allowed then return Err(L('error.no_permission', 'You do not have permission')) end
    local reason = Shared.Sanitize(payload.reason, 200)
    if reason == '' then reason = L('label.refunded_by', 'Refunded by {name}', { name = ctx.name }) end
    local amount, err = RefundInvoice(row, source, reason, ctx.identifier)
    if not amount then return Err(err) end
    return { amount = amount }
end)

-- ██████╗  █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗████████╗███████╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗██║   ██║╚══██╔══╝██╔════╝
-- ██████╔╝███████║ ╚████╔╝ ██║   ██║██║   ██║   ██║   ███████╗
-- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║   ██║██║   ██║   ██║   ╚════██║
-- ██║     ██║  ██║   ██║   ╚██████╔╝╚██████╔╝   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝

-- Deletes the rows it can claim and hands them to deposit(total); puts them back if the deposit fails
local function claim(rows, deposit)
    local total, taken = 0, {}
    for _, r in ipairs(rows) do
        if (MySQL.update.await('DELETE FROM nayzeee_billing_pending_payouts WHERE id = ?', { r.id }) or 0) == 1 then
            total = total + (tonumber(r.amount) or 0)
            taken[#taken + 1] = r
        end
    end
    total = Shared.Round(total)
    if total > 0 and not deposit(total) then
        requeue(taken)
        return 0
    end
    return total
end

-- Society money held back because the society account couldn't be credited at the time
local function flushSocietyQueue()
    if not Banking.IsAvailable() then return end
    local rows = MySQL.query.await("SELECT * FROM nayzeee_billing_pending_payouts WHERE identifier LIKE 'society:%' LIMIT 200") or {}
    for _, r in ipairs(rows) do
        if (MySQL.update.await('DELETE FROM nayzeee_billing_pending_payouts WHERE id = ?', { r.id }) or 0) == 1 then
            if not Banking.AddSociety(r.identifier:sub(9), tonumber(r.amount) or 0, r.reason or 'Billing') then requeue({ r }) end
        end
    end
end

CreateThread(function()
    while not BillingReady do Wait(1000) end
    while true do
        local ok, err = pcall(flushSocietyQueue)
        if not ok then Console.log('error', 'Society payment queue: %s', tostring(err)) end
        Wait(5 * 60000)
    end
end)

AddEventHandler('nayzeee-billing:server:ready', function()
    Framework.OnPlayerLoaded(function(source)
        SetTimeout(4000, function()
            local identifier = Framework.GetIdentifier(source)
            if not identifier then return end

            local total = claim(MySQL.query.await('SELECT * FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND requires_collection = 0', { identifier }) or {},
                function(amount) return Money.Add(source, 'bank', amount, 'Billing payouts') end)
            if total > 0 then
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
    local total = claim(MySQL.query.await('SELECT * FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND requires_collection = 1', { identifier }) or {},
        function(amount) return Money.Add(source, 'cash', amount, 'Collected invoice cash') end)
    if total > 0 then
        Log(source, 'cash_collected', { amount = total })
    end
    return { amount = total }
end)
