--[[
    NAYZEEE BILLING - Server exports, items & events

    exports['nayzeee-billing']:CreateInvoice({
        target = source | identifier,      -- citizen recipient   (or targetSociety = 'police')
        society = 'mechanic',              -- sender society (optional; omit for a system/personal invoice)
        sender = source,                   -- optional, the employee
        senderName = 'LS DMV',             -- optional, for system invoices
        items = { { label = 'Tow', amount = 250, quantity = 1 } },
        reason = 'Towing', notes = '...', dueDays = 7, vat = 0.08 (optional override),
    }) -> ref | nil, error

    exports['nayzeee-billing']:GetInvoice(ref)
    exports['nayzeee-billing']:GetInvoices(sourceOrIdentifier, { status = 'open' | 'all', limit = 50 })
    exports['nayzeee-billing']:GetUnpaidTotal(sourceOrIdentifier)
    exports['nayzeee-billing']:HasUnpaidInvoices(sourceOrIdentifier)
    exports['nayzeee-billing']:PayInvoice(source, ref, 'bank' | 'cash')
    exports['nayzeee-billing']:CancelInvoice(ref, reason)
    exports['nayzeee-billing']:GetSocietyStats(society)

    Server events: nayzeee-billing:server:invoiceCreated (invoice), :invoicePaid (invoice, payment),
                   :invoiceCancelled (ref, reason), :invoiceRefunded (ref, amount)
]]

local function identifierOf(target)
    if tonumber(target) then return Framework.GetIdentifier(tonumber(target)), tonumber(target) end
    return target, Framework.GetSource(target)
end

exports('CreateInvoice', function(data, legacyTarget, legacyItems, legacyCompany)
    -- legacy signature: CreateInvoice(sender, target, items, company)
    if type(data) ~= 'table' then data = { sender = data, target = legacyTarget, items = legacyItems, society = legacyCompany } end

    local society = data.society or data.company
    if society and not Config.Societies[society] then return nil, 'Unknown society' end

    local recipientType, targetIdentifier, targetSource, targetName = 'citizen', nil, nil, nil
    if data.targetSociety then
        if not Config.Societies[data.targetSociety] then return nil, 'Unknown target society' end
        recipientType, targetName = 'society', SocietyLabel(data.targetSociety)
    else
        targetIdentifier, targetSource = identifierOf(data.target)
        if not targetIdentifier then return nil, 'Invalid target' end
        targetName = Framework.GetCharacterName(targetIdentifier)
        if not targetName then return nil, 'Target not found' end
    end

    local items = {}
    for _, raw in ipairs(type(data.items) == 'table' and data.items or {}) do
        local label = Shared.Sanitize(raw.label or raw.name, 60)
        local amount = Shared.Round(raw.amount or raw.price)
        if label ~= '' and amount > 0 then
            items[#items + 1] = { label = label, amount = amount, quantity = math.floor(Shared.Clamp(raw.quantity or 1, 1, 1000)), custom = true }
        end
    end
    if #items == 0 then return nil, 'No valid items' end

    local sender = tonumber(data.sender)
    local senderName = sender and Framework.GetName(sender) or Shared.Sanitize(data.senderName, 100)
    if senderName == '' then senderName = society and SocietyLabel(society) or 'System' end

    local row, err = CreateInvoice({
        source = sender, senderIdentifier = sender and Framework.GetIdentifier(sender) or ('system:' .. (society or 'billing')),
        senderName = senderName, senderJob = society, society = society, recipientType = recipientType,
        targetIdentifier = targetIdentifier, targetSource = targetSource, targetSociety = data.targetSociety, targetName = targetName,
        items = items, notes = data.notes, reason = data.reason, dueDays = data.dueDays, vatRate = tonumber(data.vat),
    })
    if not row then return nil, err end
    return row.invoice_id
end)

exports('GetInvoice', function(ref)
    local row = GetInvoiceRow(ref)
    return row and FormatInvoice(row) or nil
end)

exports('GetInvoices', function(target, opts)
    opts = opts or {}
    local identifier = identifierOf(target)
    if not identifier then return {} end
    local open = opts.status ~= 'all'
    local rows = MySQL.query.await(('SELECT * FROM nayzeee_billing_invoices WHERE target_identifier = ? %s ORDER BY created_at DESC LIMIT ?')
        :format(open and "AND status IN ('pending','partial','overdue','disputed')" or ''), { identifier, tonumber(opts.limit) or 50 }) or {}
    for i, r in ipairs(rows) do rows[i] = FormatInvoice(r, { identifier = identifier }) end
    return rows
end)
exports('GetPlayerInvoices', function(target, includeClosed)
    return exports[Shared.Resource]:GetInvoices(target, { status = includeClosed and 'all' or 'open' })
end)

local function unpaid(target)
    local identifier = identifierOf(target)
    if not identifier then return 0 end
    return tonumber(MySQL.scalar.await([[SELECT COALESCE(SUM(total + late_fee - amount_paid), 0) FROM nayzeee_billing_invoices
        WHERE target_identifier = ? AND status IN ('pending','partial','overdue')]], { identifier })) or 0
end
exports('GetUnpaidTotal', unpaid)
exports('HasUnpaidInvoices', function(target) return unpaid(target) > 0 end)

exports('PayInvoice', function(source, ref, method, amount)
    local row = GetInvoiceRow(ref)
    if not row then return nil, 'Invoice not found' end
    return ProcessPayment({ source = tonumber(source), id = row.id, method = method or 'bank', amount = amount })
end)

exports('CancelInvoice', function(ref, reason)
    local row = GetInvoiceRow(ref)
    return row and CancelInvoice(row, Shared.Sanitize(reason or 'Cancelled', 200), nil) or false
end)

exports('GetSocietyStats', function(society)
    if not Config.Societies[society] then return nil end
    return MySQL.single.await([[SELECT
        (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE company_id = ? AND kind <> 'refund' AND created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)) AS revenueWeek,
        (SELECT COALESCE(SUM(total + late_fee - amount_paid), 0) FROM nayzeee_billing_invoices WHERE company_id = ? AND status IN ('pending','partial','overdue')) AS receivable,
        (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE company_id = ?) AS invoices]], { society, society, society })
end)

-- ██╗████████╗███████╗███╗   ███╗███████╗
-- ██║╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ██║   ██║   █████╗  ██╔████╔██║███████╗
-- ██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ██║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

-- Using the invoice / receipt item opens the paper view. ox_inventory uses the client export instead (see README).
AddEventHandler('nayzeee-billing:server:ready', function()
    if Inventory.Name() == 'ox_inventory' then return end
    for _, item in ipairs({ Config.Items.Invoice, Config.Items.Receipt }) do
        if item.Enabled then
            Framework.RegisterUsableItem(item.Name, function(source, metadata)
                local row = metadata and metadata.reference and GetInvoiceRow(metadata.reference)
                if not row then
                    Notify(source, L('label.invoice', 'Invoice'), L('error.unreadable', 'This paper is unreadable'), 'error')
                    return
                end
                local ctx = GetCtx(source)
                local inv = FormatInvoice(row, ctx and { identifier = ctx.identifier } or nil)
                inv.payOptions = PayOptions(ctx, row)
                TriggerClientEvent('nayzeee-billing:client:paper', source, inv)
            end)
        end
    end
end)
