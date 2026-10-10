--[[
    NAYZEEE BILLING - Invoices
    Creation (server-authoritative pricing), history, cancel, dispute.
]]

-- ██╗████████╗███████╗███╗   ███╗███████╗
-- ██║╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ██║   ██║   █████╗  ██╔████╔██║███████╗
-- ██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ██║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

local function findById(list, key, id)
    for _, entry in ipairs(list or {}) do
        if entry[key] == id then return entry end
    end
    return nil
end

-- Rebuilds line items from the company catalog. Client prices are never trusted for catalog items.
function BuildItems(company, rawItems)
    if type(rawItems) ~= 'table' or #rawItems == 0 then return nil, 'Add at least one item' end
    if #rawItems > (Config.Billing.MaxItems or 30) then return nil, 'Too many items on one invoice' end

    local allowCustom = (company == nil) or company.allowCustomItems
    local items = {}

    for _, raw in ipairs(rawItems) do
        if type(raw) ~= 'table' then return nil, 'Invalid item' end
        local qty = math.floor(Shared.Clamp(raw.quantity, 1, Config.Billing.MaxQuantity or 100))
        local item

        if company and raw.productId then
            local product = findById(company.products, 'id', raw.productId)
            if not product then return nil, 'A product on this order no longer exists' end
            item = { productId = product.id, name = product.name, price = Shared.Round(product.price), image = product.image }
        elseif company and raw.quickBillId then
            local quick = findById(company.quickBills, 'id', raw.quickBillId)
            if not quick then return nil, 'A quick bill on this order no longer exists' end
            item = { quickBillId = quick.id, name = quick.label, price = Shared.Round(quick.amount), description = quick.description }
        else
            if not allowCustom then return nil, 'Custom items are not allowed for your company' end
            local name = Shared.Sanitize(raw.name, 60)
            local price = Shared.Round(raw.price)
            if name == '' then return nil, 'Custom items need a name' end
            if price <= 0 or price > Config.MaxInvoiceAmount then return nil, 'Invalid price for ' .. name end
            item = { name = name, price = price, custom = true }
        end

        item.quantity = qty
        items[#items + 1] = item
    end

    return items
end

--  ██████╗██████╗ ███████╗ █████╗ ████████╗███████╗
-- ██╔════╝██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██╔════╝
-- ██║     ██████╔╝█████╗  ███████║   ██║   █████╗
-- ██║     ██╔══██╗██╔══╝  ██╔══██║   ██║   ██╔══╝
-- ╚██████╗██║  ██║███████╗██║  ██║   ██║   ███████╗
--  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝

-- Reference numbers ─────────────────────────────────────────────
-- Counters live in memory (one server process, so incrementing is race-free once loaded)
-- and are persisted with GREATEST() so a restart never reuses a number.
local Sequences = {}

function ReferencePrefix(company)
    local raw = company and (company.refPrefix or company.shortName or company.id) or Config.Invoices.PersonalPrefix or 'INV'
    local prefix = tostring(raw):upper():gsub('[^%w]', ''):sub(1, 6)
    return prefix ~= '' and prefix or 'INV'
end

local function nextSequence(prefix)
    if Sequences[prefix] == nil then
        local stored = tonumber(MySQL.scalar.await('SELECT value FROM nayzeee_billing_sequences WHERE prefix = ?', { prefix })) or 0
        Sequences[prefix] = math.max(Sequences[prefix] or 0, stored) -- another call may have loaded it while we waited
    end
    Sequences[prefix] = Sequences[prefix] + 1
    local n = Sequences[prefix]
    MySQL.insert('INSERT INTO nayzeee_billing_sequences (prefix, value) VALUES (?, ?) ON DUPLICATE KEY UPDATE value = GREATEST(value, VALUES(value))',
        { prefix, n })
    return n
end

local function invoiceExists(id)
    return MySQL.scalar.await('SELECT 1 FROM nayzeee_billing_invoices WHERE invoice_id = ?', { id }) ~= nil
end

local function referenceDigits()
    return math.floor(Shared.Clamp(Config.Invoices.ReferenceDigits or 6, 3, 10))
end

local function newInvoiceId(company)
    if Config.Invoices.ReferenceFormat == 'company' then
        local prefix = ReferencePrefix(company)
        for _ = 1, 25 do
            local id = ('%s-%0' .. referenceDigits() .. 'd'):format(prefix, nextSequence(prefix))
            if #id <= 20 and not invoiceExists(id) then return id end
        end
    end
    for _ = 1, 5 do
        local id = Shared.GenerateInvoiceId()
        if not invoiceExists(id) then return id end
    end
    return Shared.GenerateInvoiceId() .. tostring(math.random(0, 9))
end

-- Accepts "bs-142", " BS-000142 ", "inv-7kq2mz4p" and returns the stored reference if it exists
function NormalizeReference(input)
    if type(input) ~= 'string' then return nil end
    local ref = input:upper():gsub('%s+', '')
    if ref == '' or #ref > 20 or ref:find('[^%w%-]') then return nil end
    if invoiceExists(ref) then return ref end
    local prefix, num = ref:match('^(%w+)%-(%d+)$')
    if prefix and num then
        local padded = ('%s-%0' .. referenceDigits() .. 'd'):format(prefix, tonumber(num))
        if #padded <= 20 and invoiceExists(padded) then return padded end
    end
    return nil
end

--[[
    opts = {
        senderSource?, senderIdentifier, senderName, senderJob?,
        company? (company table), targetSource?, targetIdentifier, targetName,
        items (already validated), discount (percent), notes?, dueDays?, registerId?, silent?
    }
]]
function CreateInvoice(opts)
    local company = opts.company
    local taxRate = company and company.taxRate or Config.DefaultTaxRate
    local totals = Shared.CalculateTotals(opts.items, opts.discount or 0, taxRate)

    if totals.total <= 0 then return nil, 'Invoice total must be greater than 0' end
    if totals.total > Config.MaxInvoiceAmount then
        return nil, 'Invoice exceeds the maximum of ' .. Shared.FormatCurrency(Config.MaxInvoiceAmount)
    end

    local dueDays = math.floor(Shared.Clamp(opts.dueDays or (company and company.dueDays) or Config.Invoices.DueDays, 0, 365))
    local invoiceId = newInvoiceId(company)
    local notes = opts.notes and Shared.Sanitize(opts.notes, Config.Billing.MaxNoteLength or 250) or nil
    if notes == '' then notes = nil end
    local companyName = company and company.label or 'Personal'

    MySQL.insert.await([[
        INSERT INTO nayzeee_billing_invoices
        (invoice_id, company_id, sender_identifier, sender_name, sender_job, target_identifier, target_name, company_name,
         items, notes, subtotal, tax, discount, total, status, register_id, created_at, due_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NOW(), DATE_ADD(NOW(), INTERVAL ? DAY))
    ]], {
        invoiceId, company and company.id or nil, opts.senderIdentifier, opts.senderName, opts.senderJob,
        opts.targetIdentifier, opts.targetName, companyName, json.encode(opts.items), notes,
        totals.subtotal, totals.tax, totals.discount, totals.total, opts.registerId, dueDays,
    })

    local row = GetInvoiceRow(invoiceId)
    if not row then return nil, 'Failed to save invoice' end

    local targetSource = opts.targetSource or Bridge.GetSourceFromIdentifier(opts.targetIdentifier)
    if targetSource and not opts.silent then
        TriggerClientEvent('nayzeee-billing:client:newInvoice', targetSource, FormatInvoice(row, opts.targetIdentifier))
    end

    Log(opts.senderSource, 'invoice_created', {
        invoice = invoiceId, total = totals.total, target = opts.targetName, company = companyName,
        items = #opts.items,
    }, company and company.id)

    TriggerEvent('nayzeee-billing:server:invoiceCreated', FormatInvoice(row))
    return row
end

RPC('createInvoice', function(source, payload)
    local ctx = GetCtx(source)
    if not ctx then return Err('Character not loaded') end
    if Throttle(source, 'create', Config.Billing.Cooldown or 3) then return Err('Slow down a little') end

    -- Billing mode
    local company = nil
    if ctx.canBill and not payload.personal then
        company = ctx.company
    elseif not ctx.canPersonal then
        return Err('You cannot create invoices')
    end

    -- Target
    local target = type(payload.target) == 'table' and payload.target or {}
    local targetSource, targetIdentifier, targetName

    if target.type == 'offline' then
        if not (company and ctx.canRemote and Config.Billing.OfflineBilling) then
            return Err('You cannot bill offline players')
        end
        targetIdentifier = Shared.Sanitize(target.identifier, 60)
        targetSource = Bridge.GetSourceFromIdentifier(targetIdentifier)
        targetName = Bridge.GetCharacterName(targetIdentifier)
        if not targetName then return Err('Citizen not found') end
    else
        targetSource = tonumber(target.id)
        targetIdentifier = targetSource and Bridge.GetIdentifier(targetSource)
        if not targetIdentifier then return Err('That player is not available') end
        targetName = Bridge.GetName(targetSource)

        local maxDist = tonumber(Config.Billing.MaxDistance)
        local remote = company and ctx.canRemote
        if maxDist and not remote and GetDistanceBetween(source, targetSource) > maxDist then
            return Err('The recipient is too far away')
        end
    end

    if targetIdentifier == ctx.identifier and not Config.Billing.AllowSelfBilling then
        return Err('You cannot bill yourself')
    end

    -- Spam guard per recipient
    if company and Config.Billing.MaxPendingPerTarget then
        local pending = MySQL.scalar.await([[
            SELECT COUNT(*) FROM nayzeee_billing_invoices
            WHERE target_identifier = ? AND company_id = ? AND status IN ('pending', 'partial', 'overdue', 'disputed')
        ]], { targetIdentifier, company.id })
        if (tonumber(pending) or 0) >= Config.Billing.MaxPendingPerTarget then
            return Err(targetName .. ' already has too many unpaid invoices from ' .. company.label)
        end
    end

    local items, itemErr = BuildItems(company, payload.items)
    if not items then return Err(itemErr) end

    local discount = 0
    if company and company.allowDiscounts then
        discount = Shared.Clamp(payload.discount, 0, company.maxDiscount or 100)
    end

    local dueDays = nil
    if Config.Invoices.AllowCustomDueDays and payload.dueDays then
        dueDays = Shared.Clamp(payload.dueDays, 1, Config.Invoices.MaxDueDays or 14)
    end

    local row, err = CreateInvoice({
        senderSource = source,
        senderIdentifier = ctx.identifier,
        senderName = ctx.name,
        senderJob = company and ctx.job.name or nil,
        company = company,
        targetSource = targetSource,
        targetIdentifier = targetIdentifier,
        targetName = targetName,
        items = items,
        discount = discount,
        notes = payload.notes,
        dueDays = dueDays,
    })
    if not row then return Err(err) end

    return { invoiceId = row.invoice_id, total = tonumber(row.total), targetName = targetName }
end)

-- ██╗  ██╗██╗███████╗████████╗ ██████╗ ██████╗ ██╗   ██╗
-- ██║  ██║██║██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
-- ███████║██║███████╗   ██║   ██║   ██║██████╔╝ ╚████╔╝
-- ██╔══██║██║╚════██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝
-- ██║  ██║██║███████║   ██║   ╚██████╔╝██║  ██║   ██║
-- ╚═╝  ╚═╝╚═╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

local HistoryFilters = {
    sent = 'sender_identifier = @me',
    received = 'target_identifier = @me',
    open = "status IN ('pending', 'partial', 'overdue', 'disputed')",
    paid = "status = 'paid'",
    cancelled = "status IN ('cancelled', 'refunded')",
}

local PAGE_SIZE = 25

RPC('getHistory', function(source, payload)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return { rows = {}, hasMore = false } end

    local where = { '(sender_identifier = @me OR target_identifier = @me)' }
    local params = { me = identifier }

    if HistoryFilters[payload.filter] then where[#where + 1] = HistoryFilters[payload.filter] end

    local search = Shared.Sanitize(payload.search, 40)
    if search ~= '' then
        where[#where + 1] = '(invoice_id LIKE @q OR sender_name LIKE @q OR target_name LIKE @q OR company_name LIKE @q)'
        params.q = '%' .. search .. '%'
    end

    local page = math.floor(Shared.Clamp(payload.page, 0, 1000))
    params.limit = PAGE_SIZE + 1
    params.offset = page * PAGE_SIZE

    local rows = MySQL.query.await(('SELECT * FROM nayzeee_billing_invoices WHERE %s ORDER BY created_at DESC LIMIT @limit OFFSET @offset')
        :format(table.concat(where, ' AND ')), params) or {}

    local result = {}
    for i = 1, math.min(#rows, PAGE_SIZE) do
        result[i] = FormatInvoice(rows[i], identifier)
    end
    return { rows = result, hasMore = #rows > PAGE_SIZE, page = page }
end)

-- ██████╗ ███████╗████████╗ █████╗ ██╗██╗     ███████╗
-- ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██║██║     ██╔════╝
-- ██║  ██║█████╗     ██║   ███████║██║██║     ███████╗
-- ██║  ██║██╔══╝     ██║   ██╔══██║██║██║     ╚════██║
-- ██████╔╝███████╗   ██║   ██║  ██║██║███████╗███████║
-- ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝

function CanViewInvoice(source, ctx, row)
    if not row or not ctx then return false end
    if row.sender_identifier == ctx.identifier or row.target_identifier == ctx.identifier then return true end
    if ctx.isAdmin then return true end
    if row.company_id and IsBossOf(ctx, row.company_id) then return true end
    return Inventory.HasReceipt(source, row.invoice_id)
end

RPC('findInvoice', function(source, payload)
    if Throttle(source, 'find', 0.5) then return Err('Slow down a little') end
    local ref = NormalizeReference(payload.reference)
    local ctx = GetCtx(source)
    local row = ref and GetInvoiceRow(ref)
    -- Same answer whether it doesn't exist or you can't see it, so references can't be probed
    if not row or not CanViewInvoice(source, ctx, row) then return Err('No invoice found with that reference') end
    return { invoiceId = row.invoice_id }
end)

RPC('getInvoice', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(payload.invoiceId)
    if not row or not CanViewInvoice(source, ctx, row) then return Err('Invoice not found') end

    local invoice = FormatInvoice(row, ctx.identifier)
    invoice.payments = MySQL.query.await([[
        SELECT payer_name AS payer, amount, tip, method, kind, created_at AS createdAt
        FROM nayzeee_billing_payments WHERE invoice_id = ? ORDER BY created_at ASC
    ]], { row.invoice_id }) or {}
    invoice.footer = Config.Receipts.FooterText
    invoice.canCancel = CanCancel(ctx, row)
    invoice.canRefund = RefundableStatuses[row.status] and (tonumber(row.amount_paid) or 0) > 0 and row.company_id ~= nil
        and (ctx.isAdmin or (Config.Boss.CanRefund and IsBossOf(ctx, row.company_id)))
    invoice.canResolve = row.status == 'disputed' and row.company_id ~= nil
        and (ctx.isAdmin or (Config.Boss.CanResolveDisputes and IsBossOf(ctx, row.company_id)))
    return invoice
end)

--  ██████╗ █████╗ ███╗   ██╗ ██████╗███████╗██╗
-- ██╔════╝██╔══██╗████╗  ██║██╔════╝██╔════╝██║
-- ██║     ███████║██╔██╗ ██║██║     █████╗  ██║
-- ██║     ██╔══██║██║╚██╗██║██║     ██╔══╝  ██║
-- ╚██████╗██║  ██║██║ ╚████║╚██████╗███████╗███████╗
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚══════╝

local CancellableStatuses = { pending = true, partial = true, overdue = true, disputed = true }

function CanCancel(ctx, row)
    if not ctx or not row or not CancellableStatuses[row.status] then return false end
    if (tonumber(row.amount_paid) or 0) > 0 then return false end
    if ctx.isAdmin then return true end
    if row.company_id and IsBossOf(ctx, row.company_id) then return true end
    if Config.Invoices.SenderCanCancel and row.sender_identifier == ctx.identifier then
        local window = tonumber(Config.Invoices.CancelWindowMinutes) or 0
        if window <= 0 then return true end
        return (tonumber(row.age_minutes) or 0) <= window
    end
    return false
end

function CancelInvoice(row, reason, actorSource)
    local affected = MySQL.update.await([[
        UPDATE nayzeee_billing_invoices SET status = 'cancelled', cancel_reason = ?
        WHERE invoice_id = ? AND status IN ('pending', 'partial', 'overdue', 'disputed') AND amount_paid = 0
    ]], { reason, row.invoice_id })
    if (affected or 0) == 0 then return false end

    local targetSrc = Bridge.GetSourceFromIdentifier(row.target_identifier)
    if targetSrc then
        Notify(targetSrc, 'Invoice cancelled', ('%s cancelled invoice %s'):format(row.company_name, row.invoice_id), 'info')
        TriggerClientEvent('nayzeee-billing:client:invoiceChanged', targetSrc, row.invoice_id)
    end
    Log(actorSource, 'invoice_cancelled', { invoice = row.invoice_id, total = tonumber(row.total), reason = reason }, row.company_id)
    TriggerEvent('nayzeee-billing:server:invoiceCancelled', row.invoice_id, reason)
    return true
end

RPC('cancelInvoice', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(payload.invoiceId)
    if not row then return Err('Invoice not found') end
    if not CanCancel(ctx, row) then
        if (tonumber(row.amount_paid) or 0) > 0 then return Err('This invoice has payments - refund it instead') end
        return Err('You cannot cancel this invoice')
    end
    local reason = Shared.Sanitize(payload.reason, 200)
    if reason == '' then reason = 'Cancelled by ' .. ctx.name end
    if not CancelInvoice(row, reason, source) then return Err('Invoice could not be cancelled') end
    return true
end)

-- ██████╗ ██╗███████╗██████╗ ██╗   ██╗████████╗███████╗███████╗
-- ██╔══██╗██║██╔════╝██╔══██╗██║   ██║╚══██╔══╝██╔════╝██╔════╝
-- ██║  ██║██║███████╗██████╔╝██║   ██║   ██║   █████╗  ███████╗
-- ██║  ██║██║╚════██║██╔═══╝ ██║   ██║   ██║   ██╔══╝  ╚════██║
-- ██████╔╝██║███████║██║     ╚██████╔╝   ██║   ███████╗███████║
-- ╚═════╝ ╚═╝╚══════╝╚═╝      ╚═════╝    ╚═╝   ╚══════╝╚══════╝

RPC('disputeInvoice', function(source, payload)
    if not Config.Invoices.AllowDisputes then return Err('Disputes are disabled') end
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(payload.invoiceId)
    if not row or row.target_identifier ~= ctx.identifier then return Err('Invoice not found') end
    if not (row.status == 'pending' or row.status == 'overdue' or row.status == 'partial') then
        return Err('This invoice cannot be disputed')
    end

    if row.dispute_reason and row.dispute_reason ~= '' then
        return Err('This invoice was already disputed and reviewed')
    end

    local reason = Shared.Sanitize(payload.reason, 250)
    if #reason < 5 then return Err('Tell them why you are disputing this invoice') end

    local affected = MySQL.update.await([[
        UPDATE nayzeee_billing_invoices SET status = 'disputed', dispute_reason = ?
        WHERE invoice_id = ? AND status IN ('pending', 'partial', 'overdue')
    ]], { reason, row.invoice_id })
    if (affected or 0) == 0 then return Err('This invoice cannot be disputed') end

    local msg = ('%s disputed %s (%s)'):format(ctx.name, row.invoice_id, Shared.FormatCurrency(row.total))
    local senderSrc = Bridge.GetSourceFromIdentifier(row.sender_identifier)
    if senderSrc then Notify(senderSrc, 'Invoice disputed', msg, 'warning') end
    if row.company_id then NotifyCompanyBosses(row.company_id, 'Invoice disputed', msg, 'warning') end

    Log(source, 'invoice_disputed', { invoice = row.invoice_id, reason = reason }, row.company_id)
    return true
end)
