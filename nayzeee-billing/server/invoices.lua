--[[
    NAYZEEE BILLING - Invoices
    Create, list (filters + pagination), details, lookup by reference, cancel, disputes, print.
]]

-- ██████╗ ███████╗███████╗███████╗██████╗ ███████╗███╗   ██╗ ██████╗███████╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗██╔════╝████╗  ██║██╔════╝██╔════╝██╔════╝
-- ██████╔╝█████╗  █████╗  █████╗  ██████╔╝█████╗  ██╔██╗ ██║██║     █████╗  ███████╗
-- ██╔══██╗██╔══╝  ██╔══╝  ██╔══╝  ██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══╝  ╚════██║
-- ██║  ██║███████╗██║     ███████╗██║  ██║███████╗██║ ╚████║╚██████╗███████╗███████║
-- ╚═╝  ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚══════╝

local function invoiceExists(ref)
    return MySQL.scalar.await('SELECT 1 FROM nayzeee_billing_invoices WHERE invoice_id = ?', { ref }) ~= nil
end

-- PREFIX-XXXXXXXX: readable prefix + 8 random characters (32^8 combinations, not guessable)
function NewReference(society)
    local prefix = SocietyPrefix(society)
    for _ = 1, 10 do
        local ref = prefix .. '-' .. Shared.RandomCode(8)
        if not invoiceExists(ref) then return ref end
    end
    return prefix .. '-' .. Shared.RandomCode(10)
end

function NormalizeReference(input)
    if type(input) ~= 'string' then return nil end
    local ref = input:upper():gsub('%s+', '')
    if ref == '' or #ref > 24 or ref:find('[^%w%-]') then return nil end
    return ref
end

--  █████╗  ██████╗ ██████╗███████╗███████╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝
-- ███████║██║     ██║     █████╗  ███████╗███████╗
-- ██╔══██║██║     ██║     ██╔══╝  ╚════██║╚════██║
-- ██║  ██║╚██████╗╚██████╗███████╗███████║███████║
-- ╚═╝  ╚═╝ ╚═════╝ ╚═════╝╚══════╝╚══════╝╚══════╝

function InvolvesSociety(row, society)
    return society ~= nil and (row.company_id == society or (row.recipient_type == 'society' and row.target_society == society))
end

function CanViewInvoice(source, ctx, row)
    if not row or not ctx then return false end
    local me = ctx.identifier
    if row.sender_identifier == me or row.paid_by_identifier == me then return true end
    if (row.recipient_type or 'citizen') == 'citizen' and row.target_identifier == me then return true end
    if ctx.isAdmin then return true end
    if ctx.society then
        if row.company_id == ctx.society and Can(ctx, 'view_sent') then return true end
        if row.recipient_type == 'society' and row.target_society == ctx.society and Can(ctx, 'view_received') then return true end
        if InvolvesSociety(row, ctx.society) and Can(ctx, 'inspect') then return true end
    end
    return Config.Items.Invoice.Enabled and Inventory.HasReference(source, Config.Items.Invoice.Name, row.invoice_id)
end

function CanCancel(ctx, row)
    if not ctx or not row or not Shared.OpenStatuses[row.status] and row.status ~= 'disputed' then return false end
    if (tonumber(row.amount_paid) or 0) > 0 then return false end
    if ctx.isAdmin then return true end
    if row.company_id then
        if Can(ctx, 'cancel', row.company_id) then return true end
    end
    if row.sender_identifier == ctx.identifier then
        local window = tonumber(Config.Invoices.SenderCancelMinutes) or 0
        return window <= 0 or (tonumber(row.age_minutes) or 0) <= window
    end
    return false
end

-- Can this player pay the invoice, and with which methods?
function PayOptions(ctx, row)
    if not ctx or not row or not Shared.OpenStatuses[row.status] then return nil end
    local opts = {}
    local isRecipient = (row.recipient_type or 'citizen') == 'citizen' and row.target_identifier == ctx.identifier
    if isRecipient or Config.Payment.PayByReference then
        for m, on in pairs(Config.Payment.Methods) do if on then opts[m] = true end end
    end
    if row.recipient_type == 'society' and row.target_society == ctx.society and Can(ctx, 'pay') then
        opts.society = true
    end
    return next(opts) and opts or nil
end

-- ██╗████████╗███████╗███╗   ███╗███████╗
-- ██║╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ██║   ██║   █████╗  ██╔████╔██║███████╗
-- ██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ██║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

-- raw = { template, item, quantity } or { label, amount, quantity }
function BuildInvoiceItems(ctx, account, rawItems, allowCustom)
    if type(rawItems) ~= 'table' or #rawItems == 0 then return nil, L('error.no_items', 'Add at least one item') end
    if #rawItems > Config.Invoices.MaxItems then return nil, L('error.too_many_items', 'Too many items') end
    local out = {}
    for _, raw in ipairs(rawItems) do
        if type(raw) ~= 'table' then return nil, L('error.bad_item', 'Invalid item') end
        local qty = math.floor(Shared.Clamp(raw.quantity or 1, 1, Config.Invoices.MaxQuantity))
        if raw.template and raw.item then
            local it, tpl = Templates.FindItem(ctx, account, raw.template, raw.item)
            if not it then return nil, L('error.item_gone', 'An item on this invoice no longer exists') end
            out[#out + 1] = { label = it.label, amount = it.amount, quantity = qty, template = tpl.name }
        else
            if not allowCustom then return nil, L('error.no_custom', 'Custom items are not allowed') end
            local label = Shared.Sanitize(raw.label, 60)
            local amount = Shared.Round(raw.amount)
            if label == '' then return nil, L('error.item_name', 'Give the item a name') end
            if amount <= 0 or amount > Config.Invoices.MaxAmount then return nil, L('error.amount', 'Enter a valid amount') end
            out[#out + 1] = { label = label, amount = amount, quantity = qty, custom = true }
        end
    end
    return out
end

function GiveInvoiceItem(source, row)
    if not Config.Items.Invoice.Enabled or not source then return false end
    return Inventory.AddItem(source, Config.Items.Invoice.Name, 1, {
        reference = row.invoice_id,
        description = ('%s · %s · %s'):format(row.invoice_id, row.company_id and SocietyLabel(row.company_id) or row.sender_name, Shared.Money(row.total)),
    })
end

--  ██████╗██████╗ ███████╗ █████╗ ████████╗███████╗
-- ██╔════╝██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██╔════╝
-- ██║     ██████╔╝█████╗  ███████║   ██║   █████╗
-- ██║     ██╔══██╗██╔══╝  ██╔══██║   ██║   ██╔══╝
-- ╚██████╗██║  ██║███████╗██║  ██║   ██║   ███████╗
--  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝

--[[
    opts = {
        source?, senderIdentifier, senderName, senderJob?, society? (sender society id),
        recipientType = 'citizen'|'society', targetIdentifier?, targetSource?, targetSociety?, targetName,
        items, notes?, dueDays?, reason?, registerId?, silent?, vatRate?
    }
]]
function CreateInvoice(opts)
    local vatRate = opts.vatRate or Shared.VatRate(opts.society, opts.society == nil)
    local totals = Shared.Totals(opts.items, vatRate)
    if totals.total <= 0 then return nil, L('error.amount', 'Enter a valid amount') end
    if totals.total > Config.Invoices.MaxAmount then
        return nil, L('error.max_amount', 'Invoices are limited to {amount}', { amount = Shared.Money(Config.Invoices.MaxAmount) })
    end

    local s = opts.society and Config.Societies[opts.society] or {}
    local dueDays = math.floor(Shared.Clamp(opts.dueDays or s.dueDays or Config.Invoices.DueDays, 0, 365))
    local ref = NewReference(opts.society)
    local reason = Shared.Sanitize(opts.reason, 120)
    if reason == '' then
        reason = opts.items[1].label .. (#opts.items > 1 and (' +' .. (#opts.items - 1)) or '')
    end
    local notes = opts.notes and Shared.Sanitize(opts.notes, Config.Invoices.MaxNoteLength) or nil
    if notes == '' then notes = nil end
    local recipientType = opts.recipientType or 'citizen'
    local targetIdentifier = recipientType == 'society' and ('society:' .. opts.targetSociety) or opts.targetIdentifier

    MySQL.insert.await([[
        INSERT INTO nayzeee_billing_invoices
        (invoice_id, company_id, sender_identifier, sender_name, sender_job, recipient_type, target_identifier, target_society, target_name,
         company_name, reason, items, notes, subtotal, vat_rate, tax, total, status, register_id, created_at, due_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NOW(), DATE_ADD(NOW(), INTERVAL ? DAY))
    ]], {
        ref, opts.society, opts.senderIdentifier, opts.senderName, opts.senderJob, recipientType, targetIdentifier,
        recipientType == 'society' and opts.targetSociety or nil, opts.targetName,
        opts.society and SocietyLabel(opts.society) or 'Personal', reason, json.encode(opts.items), notes,
        totals.subtotal, vatRate, totals.vat, totals.total, opts.registerId, dueDays,
    })

    local row = GetInvoiceRow(ref)
    if not row then return nil, L('error.generic', 'Something went wrong') end

    if not opts.silent then
        if recipientType == 'citizen' then
            local src = opts.targetSource or Framework.GetSource(opts.targetIdentifier)
            if src then
                TriggerClientEvent('nayzeee-billing:client:newInvoice', src, FormatInvoice(row, { identifier = opts.targetIdentifier }))
                GiveInvoiceItem(src, row)
            end
        else
            NotifySociety(opts.targetSociety, 'view_received', L('notify.new_invoice', 'New invoice'),
                L('notify.new_society_invoice', '{sender} billed {society} {amount}', {
                    sender = opts.society and SocietyLabel(opts.society) or opts.senderName,
                    society = SocietyLabel(opts.targetSociety), amount = Shared.Money(row.total) }), 'info')
        end
    end

    Log(opts.source, 'invoice_created', {
        ref = ref, amount = tonumber(row.total), target = opts.targetName, reason = reason,
        by = opts.senderName, byIdentifier = opts.senderIdentifier,
    }, opts.society)
    if opts.recipientType == 'society' then
        Log(nil, 'invoice_received', { ref = ref, amount = tonumber(row.total), from = row.company_name ~= 'Personal' and row.company_name or opts.senderName, by = 'System' }, opts.targetSociety)
    end
    TriggerEvent('nayzeee-billing:server:invoiceCreated', FormatInvoice(row))
    return row
end

RPC('invoices:create', function(source, payload)
    local ctx = GetCtx(source)
    if not ctx then return Err(L('error.not_loaded', 'Character not loaded')) end
    if Throttle(source, 'create', Config.Invoices.Cooldown) then return Err(L('error.slow_down', 'Slow down a little')) end

    local account = payload.account == 'society' and 'society' or 'personal'
    local society = nil
    if account == 'society' then
        if not Can(ctx, 'create') then return Err(L('error.no_permission', 'You do not have permission')) end
        local job = Framework.GetJob(source)
        if job and not job.onDuty then return Err(L('error.off_duty', 'You need to be on duty')) end
        society = ctx.society
    elseif not Config.Personal.Enabled then
        return Err(L('error.personal_disabled', 'Personal invoices are disabled'))
    end

    -- Recipient
    local r = type(payload.recipient) == 'table' and payload.recipient or {}
    local recipient = { type = r.type == 'society' and 'society' or 'citizen' }
    if recipient.type == 'society' then
        local target = Config.Societies[r.id]
        if not target or target.billable == false then return Err(L('error.society_not_billable', 'That society cannot be billed')) end
        if account == 'personal' and not Config.Personal.AllowSocietyRecipients then return Err(L('error.no_permission', 'You do not have permission')) end
        if r.id == society then return Err(L('error.bill_self', 'You cannot bill yourself')) end
        recipient.society, recipient.name, recipient.identifier = r.id, target.label, 'society:' .. r.id
    else
        local target = tonumber(r.id)
        local identifier = target and Framework.GetIdentifier(target)
        if not identifier then return Err(L('error.recipient_gone', 'That person is not available')) end
        if identifier == ctx.identifier then return Err(L('error.bill_self', 'You cannot bill yourself')) end
        local max = tonumber(Config.Invoices.MaxDistance)
        if max and Distance(source, target) > max then return Err(L('error.too_far', 'The recipient is too far away')) end
        recipient.source, recipient.identifier, recipient.name = target, identifier, Framework.GetName(target)
    end

    -- Spam guard
    local open = MySQL.scalar.await([[SELECT COUNT(*) FROM nayzeee_billing_invoices
        WHERE target_identifier = ? AND status IN ('pending','partial','overdue','disputed') AND ]]
        .. (society and 'company_id = ?' or 'company_id IS NULL AND sender_identifier = ?'),
        { recipient.identifier, society or ctx.identifier })
    if (tonumber(open) or 0) >= Config.Invoices.MaxOpenPerRecipient then
        return Err(L('error.too_many_open', '{name} already has too many open invoices from you', { name = recipient.name }))
    end

    local allowCustom = society and (Config.Societies[society].allowCustom ~= false) or Config.Personal.AllowCustomItems
    local items, itemErr = BuildInvoiceItems(ctx, account, payload.items, allowCustom)
    if not items then return Err(itemErr) end

    local dueDays
    if Config.Invoices.AllowCustomDueDays and payload.dueDays then
        dueDays = Shared.Clamp(payload.dueDays, 1, Config.Invoices.MaxDueDays)
    end

    local row, err = CreateInvoice({
        source = source, senderIdentifier = ctx.identifier, senderName = ctx.name, senderJob = society and ctx.job.name or nil,
        society = society, recipientType = recipient.type, targetIdentifier = recipient.identifier, targetSource = recipient.source,
        targetSociety = recipient.society, targetName = recipient.name, items = items, notes = payload.notes,
        reason = payload.reason, dueDays = dueDays,
    })
    if not row then return Err(err) end
    return { ref = row.invoice_id, total = tonumber(row.total), recipient = recipient.name }
end)

-- ██╗     ██╗███████╗████████╗███████╗
-- ██║     ██║██╔════╝╚══██╔══╝██╔════╝
-- ██║     ██║███████╗   ██║   ███████╗
-- ██║     ██║╚════██║   ██║   ╚════██║
-- ███████╗██║███████║   ██║   ███████║
-- ╚══════╝╚═╝╚══════╝   ╚═╝   ╚══════╝

local StatusGroups = {
    pending = { 'pending' }, partial = { 'partial' }, overdue = { 'overdue' }, disputed = { 'disputed' },
    paid = { 'paid' }, cancelled = { 'cancelled', 'refunded' },
}

-- Base WHERE for an account/box. Returns sql, params or nil, error
function BoxWhere(ctx, account, box)
    local p = { me = ctx.identifier, soc = ctx.society }
    if account == 'society' then
        if not ctx.society then return nil end
        if box == 'received' then
            if not Can(ctx, 'view_received') then return nil end
            return "recipient_type = 'society' AND target_society = @soc", p
        end
        if Can(ctx, 'view_sent') then return 'company_id = @soc', p end
        if Can(ctx, 'create') then return 'company_id = @soc AND sender_identifier = @me', p end
        return nil
    end
    if box == 'received' then return "COALESCE(recipient_type, 'citizen') = 'citizen' AND target_identifier = @me", p end
    return 'company_id IS NULL AND sender_identifier = @me', p
end

-- Applies search / status / due filters, returns paginated rows + per-status counts
function QueryInvoices(baseWhere, params, payload, viewer)
    local where = { '(' .. baseWhere .. ')' }
    local search = Shared.Sanitize(payload.search, 40)
    if search ~= '' then
        where[#where + 1] = '(invoice_id LIKE @q OR reason LIKE @q OR sender_name LIKE @q OR target_name LIKE @q OR company_name LIKE @q)'
        params.q = '%' .. search .. '%'
    end
    local filterWhere = { table.unpack(where) }

    if type(payload.statuses) == 'table' and #payload.statuses > 0 then
        local list = {}
        for _, s in ipairs(payload.statuses) do
            for _, st in ipairs(StatusGroups[s] or {}) do list[#list + 1] = ("'%s'"):format(st) end
        end
        if #list > 0 then filterWhere[#filterWhere + 1] = 'status IN (' .. table.concat(list, ',') .. ')' end
    end
    local dueDays = ({ today = 0, ['3d'] = 3, ['7d'] = 7 })[payload.due]
    if dueDays then
        filterWhere[#filterWhere + 1] = ("status IN ('pending','partial','overdue') AND due_date < DATE_ADD(CURDATE(), INTERVAL %d DAY)"):format(dueDays + 1)
    end

    local size = math.floor(Shared.Clamp(payload.pageSize or Config.UI.PageSize, 5, 50))
    local page = math.floor(Shared.Clamp(payload.page, 1, 100000))
    params.limit, params.offset = size, (page - 1) * size

    local filtered = table.concat(filterWhere, ' AND ')
    local total = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE ' .. filtered, params)) or 0
    local rows = MySQL.query.await('SELECT * FROM nayzeee_billing_invoices WHERE ' .. filtered ..
        " ORDER BY FIELD(status, 'pending', 'partial', 'disputed', 'overdue') DESC, created_at DESC LIMIT @limit OFFSET @offset", params) or {}

    local counts = { pending = 0, partial = 0, overdue = 0, disputed = 0, paid = 0, cancelled = 0 }
    for _, r in ipairs(MySQL.query.await('SELECT status, COUNT(*) AS c FROM nayzeee_billing_invoices WHERE ' .. table.concat(where, ' AND ') .. ' GROUP BY status', params) or {}) do
        local key = r.status == 'refunded' and 'cancelled' or r.status
        if counts[key] then counts[key] = counts[key] + (tonumber(r.c) or 0) end
    end

    for i, r in ipairs(rows) do rows[i] = FormatInvoice(r, viewer) end
    return { rows = rows, total = total, page = page, pageSize = size, counts = counts }
end

RPC('invoices:list', function(source, payload)
    local ctx = GetCtx(source)
    local account = payload.account == 'society' and 'society' or 'personal'
    local box = payload.box == 'sent' and 'sent' or 'received'
    local where, params = BoxWhere(ctx, account, box)
    if not where then return Err(L('error.no_permission', 'You do not have permission')) end
    return QueryInvoices(where, params, payload, { identifier = ctx.identifier, society = account == 'society' and ctx.society or nil })
end)

-- ██████╗ ███████╗████████╗ █████╗ ██╗██╗     ███████╗
-- ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██║██║     ██╔════╝
-- ██║  ██║█████╗     ██║   ███████║██║██║     ███████╗
-- ██║  ██║██╔══╝     ██║   ██╔══██║██║██║     ╚════██║
-- ██████╔╝███████╗   ██║   ██║  ██║██║███████╗███████║
-- ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝

local function detail(source, ctx, row, viewerSociety)
    local inv = FormatInvoice(row, { identifier = ctx.identifier, society = viewerSociety })
    inv.payments = MySQL.query.await([[SELECT payer_name AS payer, amount, tip, method, kind, created_at AS createdAt
        FROM nayzeee_billing_payments WHERE invoice_id = ? ORDER BY id ASC]], { row.invoice_id }) or {}
    inv.payOptions = PayOptions(ctx, row)
    inv.canCancel = CanCancel(ctx, row)
    inv.canDispute = Config.Invoices.AllowDisputes and Shared.OpenStatuses[row.status] and not row.dispute_reason
        and (((row.recipient_type or 'citizen') == 'citizen' and row.target_identifier == ctx.identifier)
            or (row.recipient_type == 'society' and row.target_society == ctx.society and Can(ctx, 'pay')))
    inv.canResolve = row.status == 'disputed' and (ctx.isAdmin or (row.company_id and Can(ctx, 'disputes', row.company_id))
        or (not row.company_id and row.sender_identifier == ctx.identifier))
    inv.canRefund = RefundableStatuses[row.status] and (tonumber(row.amount_paid) or 0) > 0 and row.company_id ~= nil
        and (ctx.isAdmin or Can(ctx, 'refund', row.company_id))
    inv.canPrint = Config.Items.AllowPrint and Config.Items.Invoice.Enabled
        and (not InvolvesSociety(row, ctx.society) or Can(ctx, 'print') or row.sender_identifier == ctx.identifier or row.target_identifier == ctx.identifier)
    inv.canDelete = ctx.isAdmin and Config.Admin.AllowDelete
    return inv
end

RPC('invoices:get', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(tonumber(payload.id) or payload.ref)
    if not row or not CanViewInvoice(source, ctx, row) then return Err(L('error.not_found', 'Invoice not found')) end
    return detail(source, ctx, row, payload.account == 'society' and ctx.society or nil)
end)

-- Pay by reference: anyone with the reference sees the invoice before paying
RPC('invoices:lookup', function(source, payload)
    if not Config.Payment.PayByReference then return Err(L('error.no_permission', 'You do not have permission')) end
    if Throttle(source, 'lookup', 1) then return Err(L('error.slow_down', 'Slow down a little')) end
    local ctx = GetCtx(source)
    local ref = NormalizeReference(payload.ref)
    local row = ref and GetInvoiceRow(ref)
    if not row then return Err(L('error.ref_not_found', 'No invoice found with that reference')) end
    local inv = detail(source, ctx, row, nil)
    inv.payments = nil
    if not CanViewInvoice(source, ctx, row) then
        inv.canCancel, inv.canRefund, inv.canResolve, inv.canDispute, inv.canPrint, inv.canDelete = false, false, false, false, false, false
        inv.notes = nil
    end
    return inv
end)

--  ██████╗ █████╗ ███╗   ██╗ ██████╗███████╗██╗
-- ██╔════╝██╔══██╗████╗  ██║██╔════╝██╔════╝██║
-- ██║     ███████║██╔██╗ ██║██║     █████╗  ██║
-- ██║     ██╔══██║██║╚██╗██║██║     ██╔══╝  ██║
-- ╚██████╗██║  ██║██║ ╚████║╚██████╗███████╗███████╗
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚══════╝

function CancelInvoice(row, reason, actorSource)
    local affected = MySQL.update.await([[UPDATE nayzeee_billing_invoices SET status = 'cancelled', cancel_reason = ?
        WHERE id = ? AND status IN ('pending','partial','overdue','disputed') AND amount_paid = 0]], { reason, row.id })
    if (affected or 0) == 0 then return false end

    if (row.recipient_type or 'citizen') == 'citizen' then
        local src = Framework.GetSource(row.target_identifier)
        if src then
            Notify(src, L('notify.cancelled', 'Invoice cancelled'), L('notify.cancelled_body', '{ref} from {sender} was cancelled',
                { ref = row.invoice_id, sender = row.company_id and SocietyLabel(row.company_id) or row.sender_name }), 'info')
            Refresh(src)
            if Config.Items.Invoice.RemoveWhenPaid then Inventory.RemoveByReference(src, Config.Items.Invoice.Name, row.invoice_id) end
        end
    end
    Log(actorSource, 'invoice_cancelled', { ref = row.invoice_id, amount = tonumber(row.total), target = row.target_name, reason = reason }, row.company_id)
    TriggerEvent('nayzeee-billing:server:invoiceCancelled', row.invoice_id, reason)
    return true
end

RPC('invoices:cancel', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(tonumber(payload.id))
    if not row then return Err(L('error.not_found', 'Invoice not found')) end
    if not CanCancel(ctx, row) then
        if (tonumber(row.amount_paid) or 0) > 0 then return Err(L('error.refund_instead', 'This invoice has payments - refund it instead')) end
        return Err(L('error.cannot_cancel', 'You cannot cancel this invoice'))
    end
    local reason = Shared.Sanitize(payload.reason, 200)
    if reason == '' then reason = L('label.cancelled_by', 'Cancelled by {name}', { name = ctx.name }) end
    if not CancelInvoice(row, reason, source) then return Err(L('error.cannot_cancel', 'You cannot cancel this invoice')) end
    return true
end)

-- ██████╗ ██╗███████╗██████╗ ██╗   ██╗████████╗███████╗███████╗
-- ██╔══██╗██║██╔════╝██╔══██╗██║   ██║╚══██╔══╝██╔════╝██╔════╝
-- ██║  ██║██║███████╗██████╔╝██║   ██║   ██║   █████╗  ███████╗
-- ██║  ██║██║╚════██║██╔═══╝ ██║   ██║   ██║   ██╔══╝  ╚════██║
-- ██████╔╝██║███████║██║     ╚██████╔╝   ██║   ███████╗███████║
-- ╚═════╝ ╚═╝╚══════╝╚═╝      ╚═════╝    ╚═╝   ╚══════╝╚══════╝

RPC('invoices:dispute', function(source, payload)
    if not Config.Invoices.AllowDisputes then return Err(L('error.no_permission', 'You do not have permission')) end
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(tonumber(payload.id))
    if not row then return Err(L('error.not_found', 'Invoice not found')) end
    local mine = ((row.recipient_type or 'citizen') == 'citizen' and row.target_identifier == ctx.identifier)
        or (row.recipient_type == 'society' and row.target_society == ctx.society and Can(ctx, 'pay'))
    if not mine then return Err(L('error.not_found', 'Invoice not found')) end
    if row.dispute_reason and row.dispute_reason ~= '' then return Err(L('error.disputed_before', 'This invoice was already disputed')) end
    local reason = Shared.Sanitize(payload.reason, 250)
    if #reason < 5 then return Err(L('error.dispute_reason', 'Tell them why you are disputing this invoice')) end

    local affected = MySQL.update.await([[UPDATE nayzeee_billing_invoices SET status = 'disputed', dispute_reason = ?
        WHERE id = ? AND status IN ('pending','partial','overdue')]], { reason, row.id })
    if (affected or 0) == 0 then return Err(L('error.cannot_dispute', 'This invoice cannot be disputed')) end

    local msg = L('notify.disputed_body', '{name} disputed {ref}', { name = ctx.name, ref = row.invoice_id })
    local senderSrc = Framework.GetSource(row.sender_identifier)
    if senderSrc then Notify(senderSrc, L('notify.disputed', 'Invoice disputed'), msg, 'warning') end
    if row.company_id then NotifySociety(row.company_id, 'disputes', L('notify.disputed', 'Invoice disputed'), msg, 'warning') end
    Log(source, 'invoice_disputed', { ref = row.invoice_id, reason = reason }, row.company_id)
    return true
end)

RPC('invoices:resolve', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(tonumber(payload.id))
    if not row or row.status ~= 'disputed' then return Err(L('error.not_found', 'Invoice not found')) end
    local allowed = ctx.isAdmin or (row.company_id and Can(ctx, 'disputes', row.company_id))
        or (not row.company_id and row.sender_identifier == ctx.identifier)
    if not allowed then return Err(L('error.no_permission', 'You do not have permission')) end

    if payload.action == 'accept' then
        local reason = L('label.dispute_accepted', 'Dispute accepted: {reason}', { reason = row.dispute_reason or '' })
        if (tonumber(row.amount_paid) or 0) > 0 then
            local ok, err = RefundInvoice(row, source, reason)
            if not ok then return Err(err) end
        elseif not CancelInvoice(row, reason, source) then
            return Err(L('error.cannot_cancel', 'You cannot cancel this invoice'))
        end
    else
        MySQL.update.await([[UPDATE nayzeee_billing_invoices
            SET status = IF(amount_paid > 0, 'partial', IF(due_date IS NOT NULL AND due_date < NOW(), 'overdue', 'pending'))
            WHERE id = ? AND status = 'disputed']], { row.id })
        local src = (row.recipient_type or 'citizen') == 'citizen' and Framework.GetSource(row.target_identifier)
        if src then
            Notify(src, L('notify.dispute_rejected', 'Dispute rejected'), L('notify.dispute_rejected_body', '{ref} is payable again', { ref = row.invoice_id }), 'warning')
            Refresh(src)
        end
        Log(source, 'dispute_rejected', { ref = row.invoice_id }, row.company_id)
    end
    return true
end)

-- ██████╗ ██████╗ ██╗███╗   ██╗████████╗
-- ██╔══██╗██╔══██╗██║████╗  ██║╚══██╔══╝
-- ██████╔╝██████╔╝██║██╔██╗ ██║   ██║
-- ██╔═══╝ ██╔══██╗██║██║╚██╗██║   ██║
-- ██║     ██║  ██║██║██║ ╚████║   ██║
-- ╚═╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝   ╚═╝

RPC('invoices:print', function(source, payload)
    if not (Config.Items.AllowPrint and Config.Items.Invoice.Enabled) then return Err(L('error.no_permission', 'You do not have permission')) end
    if Throttle(source, 'print', 2) then return Err(L('error.slow_down', 'Slow down a little')) end
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(tonumber(payload.id))
    if not row or not CanViewInvoice(source, ctx, row) then return Err(L('error.not_found', 'Invoice not found')) end
    if InvolvesSociety(row, ctx.society) and not Can(ctx, 'print') and row.sender_identifier ~= ctx.identifier then
        return Err(L('error.no_permission', 'You do not have permission'))
    end
    if not GiveInvoiceItem(source, row) then return Err(L('error.inventory_full', 'Your pockets are full')) end
    Log(source, 'invoice_printed', { ref = row.invoice_id }, InvolvesSociety(row, ctx.society) and ctx.society or nil)
    return true
end)
