--[[
    NAYZEEE BILLING - Server Exports & Integrations

    exports['nayzeee-billing']:CreateInvoice({ target = 12, company = 'police', items = {{ name = 'Speeding', price = 500 }} })
    exports['nayzeee-billing']:GetPlayerInvoices(source)
    exports['nayzeee-billing']:GetUnpaidTotal(sourceOrIdentifier)
    exports['nayzeee-billing']:HasUnpaidInvoices(sourceOrIdentifier)
    exports['nayzeee-billing']:PayInvoice(source, invoiceId, method)
    exports['nayzeee-billing']:CancelInvoice(invoiceId, reason)
    exports['nayzeee-billing']:GetInvoice(invoiceId)
    exports['nayzeee-billing']:GetCompany(companyId)
    exports['nayzeee-billing']:GetCompanyStats(companyId)

    Server events (AddEventHandler) for banking / phone / MDT scripts:
    nayzeee-billing:server:invoiceCreated   (invoice)
    nayzeee-billing:server:invoicePaid      (invoice, { amount, tip, method, payer })
    nayzeee-billing:server:invoiceCancelled (invoiceId, reason)
    nayzeee-billing:server:invoiceRefunded  (invoiceId, amount)
]]

local function identifierOf(target)
    if type(target) == 'number' or tonumber(target) then
        return Bridge.GetIdentifier(tonumber(target)), tonumber(target)
    end
    return target, Bridge.GetSourceFromIdentifier(target)
end

--[[
    data = {
        target   = source | identifier (required)
        sender   = source (optional - system invoice if omitted)
        senderName = 'Los Santos DMV' (optional, for system invoices)
        company  = companyId (optional)
        items    = { { name, price, quantity? } | { productId, quantity? } }
        discount = percent, notes = string, dueDays = number
    }
    returns invoiceId | nil, error
]]
local function ExportCreateInvoice(data, legacyTarget, legacyItems, legacyCompany)
    -- 1.x signature: CreateInvoice(sender, target, items, companyLabel)
    if type(data) ~= 'table' then
        local companyId
        for id, c in pairs(Companies) do
            if c.label == legacyCompany or id == legacyCompany then companyId = id break end
        end
        data = { sender = data, target = legacyTarget, items = legacyItems, company = companyId }
    end

    local targetIdentifier, targetSource = identifierOf(data.target)
    if not targetIdentifier then return nil, 'Invalid target' end
    local targetName = Bridge.GetCharacterName(targetIdentifier)
    if not targetName then return nil, 'Target not found' end

    local company = data.company and Companies[data.company] or nil
    if data.company and not company then return nil, 'Unknown company' end

    -- Trusted server call: custom items are allowed regardless of company settings
    local items = {}
    for _, raw in ipairs(type(data.items) == 'table' and data.items or {}) do
        if company and raw.productId then
            local built, err = BuildItems(company, { raw })
            if not built then return nil, err end
            items[#items + 1] = built[1]
        else
            local name = Shared.Sanitize(raw.name or raw.label, 60)
            local price = Shared.Round(raw.price or raw.amount)
            if name ~= '' and price > 0 then
                items[#items + 1] = { name = name, price = price, quantity = math.floor(Shared.Clamp(raw.quantity or 1, 1, 1000)), custom = true }
            end
        end
    end
    if #items == 0 then return nil, 'No valid items' end

    local sender = tonumber(data.sender)
    local senderIdentifier = sender and Bridge.GetIdentifier(sender) or ('system:' .. (company and company.id or 'billing'))
    local senderName = sender and Bridge.GetName(sender) or Shared.Sanitize(data.senderName, 100)
    if senderName == '' then senderName = company and company.label or 'System' end

    local row, err = CreateInvoice({
        senderSource = sender,
        senderIdentifier = senderIdentifier,
        senderName = senderName,
        senderJob = company and company.job or nil,
        company = company,
        targetSource = targetSource,
        targetIdentifier = targetIdentifier,
        targetName = targetName,
        items = items,
        discount = Shared.Clamp(data.discount or 0, 0, 100),
        notes = data.notes,
        dueDays = data.dueDays,
    })
    if not row then return nil, err end
    return row.invoice_id
end

exports('CreateInvoice', ExportCreateInvoice)

exports('GetPlayerInvoices', function(target, includeClosed)
    local identifier = identifierOf(target)
    if not identifier then return {} end
    local sql = includeClosed
        and 'SELECT * FROM nayzeee_billing_invoices WHERE target_identifier = ? ORDER BY created_at DESC LIMIT 100'
        or "SELECT * FROM nayzeee_billing_invoices WHERE target_identifier = ? AND status IN ('pending', 'partial', 'overdue', 'disputed') ORDER BY created_at DESC"
    local rows = MySQL.query.await(sql, { identifier }) or {}
    for i, row in ipairs(rows) do rows[i] = FormatInvoice(row, identifier) end
    return rows
end)

local function unpaidTotal(target)
    local identifier = identifierOf(target)
    if not identifier then return 0 end
    return tonumber(MySQL.scalar.await([[
        SELECT COALESCE(SUM(total + late_fee - amount_paid), 0) FROM nayzeee_billing_invoices
        WHERE target_identifier = ? AND status IN ('pending', 'partial', 'overdue')
    ]], { identifier })) or 0
end

exports('GetUnpaidTotal', unpaidTotal)
exports('HasUnpaidInvoices', function(target) return unpaidTotal(target) > 0 end)

exports('PayInvoice', function(source, invoiceId, method, amount)
    return ProcessPayment({ source = tonumber(source), invoiceId = invoiceId, method = method or 'bank', amount = amount })
end)

exports('CancelInvoice', function(invoiceId, reason)
    local row = GetInvoiceRow(invoiceId)
    if not row then return false end
    return CancelInvoice(row, Shared.Sanitize(reason or 'Cancelled', 200), nil)
end)

exports('GetInvoice', function(invoiceId)
    local row = GetInvoiceRow(invoiceId)
    return row and FormatInvoice(row) or nil
end)

exports('GetCompany', function(companyId)
    return PublicCompany(Companies[companyId], true)
end)

exports('GetCompanyStats', function(companyId)
    if not Companies[companyId] then return nil end
    return GetCompanyStats(companyId)
end)

-- ██████╗ ███████╗ ██████╗███████╗██╗██████╗ ████████╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██╔════╝██║██╔══██╗╚══██╔══╝██╔════╝
-- ██████╔╝█████╗  ██║     █████╗  ██║██████╔╝   ██║   ███████╗
-- ██╔══██╗██╔══╝  ██║     ██╔══╝  ██║██╔═══╝    ██║   ╚════██║
-- ██║  ██║███████╗╚██████╗███████╗██║██║        ██║   ███████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝╚══════╝╚═╝╚═╝        ╚═╝   ╚══════╝

-- ox_inventory uses the client export (see README). Other inventories use a framework usable item.
AddEventHandler('nayzeee-billing:server:ready', function()
    if not Config.Receipts.GiveReceiptItem or Inventory.Name() == 'ox_inventory' then return end
    Bridge.RegisterUsableItem(Config.Receipts.ReceiptItemName, function(source, metadata)
        local row = metadata and metadata.invoiceId and GetInvoiceRow(metadata.invoiceId)
        if not row then
            Notify(source, 'Receipt', 'This receipt is unreadable', 'error')
            return
        end
        local invoice = FormatInvoice(row, Bridge.GetIdentifier(source))
        invoice.footer = Config.Receipts.FooterText
        TriggerClientEvent('nayzeee-billing:client:showReceipt', source, invoice)
    end)
end)
