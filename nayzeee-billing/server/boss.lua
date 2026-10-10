--[[
    NAYZEEE BILLING - Company / Boss Management
    Dashboard stats, company invoices, refunds, disputes, catalog management.
]]

-- Resolves which company a boss/admin request targets
local function BossCompany(source, payload, permKey)
    local ctx = GetCtx(source)
    if not ctx then return nil, nil, 'Character not loaded' end

    local companyId = payload.companyId
    if not ctx.isAdmin or not companyId then
        companyId = ctx.company and ctx.company.id
    end
    local company = companyId and Companies[companyId]
    if not company then return nil, nil, 'Company not found' end
    if not IsBossOf(ctx, company.id) then return nil, nil, 'You are not a manager of ' .. company.label end
    if permKey and not ctx.isAdmin and not Config.Boss[permKey] then return nil, nil, 'Not allowed on this server' end
    return company, ctx
end

-- ███████╗████████╗ █████╗ ████████╗███████╗
-- ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝
-- ███████╗   ██║   ███████║   ██║   ███████╗
-- ╚════██║   ██║   ██╔══██║   ██║   ╚════██║
-- ███████║   ██║   ██║  ██║   ██║   ███████║
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝

local function lastDays(todayStr, count)
    local y, m, d = todayStr:match('(%d+)-(%d+)-(%d+)')
    local days = {}
    for i = count - 1, 0, -1 do
        local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) - i, hour = 12 })
        days[#days + 1] = { key = os.date('%Y-%m-%d', t), label = os.date('%a', t), value = 0 }
    end
    return days
end

function GetCompanyStats(companyId)
    local totals = MySQL.single.await([[
        SELECT
            (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE company_id = @id AND created_at >= CURDATE()) AS today,
            (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE company_id = @id AND created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)) AS week,
            (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE company_id = @id AND created_at >= DATE_SUB(CURDATE(), INTERVAL 29 DAY)) AS month,
            (SELECT COALESCE(SUM(tip), 0) FROM nayzeee_billing_payments WHERE company_id = @id AND created_at >= DATE_SUB(CURDATE(), INTERVAL 29 DAY)) AS tips,
            (SELECT COALESCE(SUM(total + late_fee - amount_paid), 0) FROM nayzeee_billing_invoices WHERE company_id = @id AND status IN ('pending', 'partial', 'overdue')) AS outstanding,
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE company_id = @id AND status IN ('pending', 'partial', 'overdue')) AS openCount,
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE company_id = @id AND status = 'overdue') AS overdueCount,
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE company_id = @id AND status = 'disputed') AS disputedCount,
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE company_id = @id AND created_at >= DATE_SUB(CURDATE(), INTERVAL 29 DAY)) AS invoices30,
            (SELECT COALESCE(AVG(total), 0) FROM nayzeee_billing_invoices WHERE company_id = @id AND status = 'paid' AND created_at >= DATE_SUB(CURDATE(), INTERVAL 29 DAY)) AS avgTicket,
            DATE_FORMAT(CURDATE(), '%Y-%m-%d') AS today_key
    ]], { id = companyId }) or {}

    local days = lastDays(totals.today_key or os.date('%Y-%m-%d'), 7)
    local daily = MySQL.query.await([[
        SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS day, COALESCE(SUM(amount), 0) AS total, COUNT(*) AS count
        FROM nayzeee_billing_payments
        WHERE company_id = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
        GROUP BY day
    ]], { companyId }) or {}
    local byDay = {}
    for _, row in ipairs(daily) do byDay[row.day] = row end
    for _, day in ipairs(days) do
        local row = byDay[day.key]
        day.value = row and Shared.Round(tonumber(row.total) or 0) or 0
        day.count = row and tonumber(row.count) or 0
    end

    local leaderboard = MySQL.query.await([[
        SELECT MAX(sender_name) AS name, COUNT(*) AS invoices,
            COALESCE(SUM(CASE WHEN status IN ('paid', 'partial', 'overdue') THEN amount_paid ELSE 0 END), 0) AS collected,
            COALESCE(SUM(tip), 0) AS tips
        FROM nayzeee_billing_invoices
        WHERE company_id = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 29 DAY)
        GROUP BY sender_identifier
        ORDER BY collected DESC
        LIMIT 8
    ]], { companyId }) or {}
    for _, row in ipairs(leaderboard) do
        row.invoices = tonumber(row.invoices) or 0
        row.collected = tonumber(row.collected) or 0
        row.tips = tonumber(row.tips) or 0
    end

    return {
        today = tonumber(totals.today) or 0,
        week = tonumber(totals.week) or 0,
        month = tonumber(totals.month) or 0,
        tips = tonumber(totals.tips) or 0,
        outstanding = tonumber(totals.outstanding) or 0,
        openCount = tonumber(totals.openCount) or 0,
        overdueCount = tonumber(totals.overdueCount) or 0,
        disputedCount = tonumber(totals.disputedCount) or 0,
        invoices30 = tonumber(totals.invoices30) or 0,
        avgTicket = Shared.Round(tonumber(totals.avgTicket) or 0),
        daily = days,
        leaderboard = leaderboard,
    }
end

RPC('boss:getDashboard', function(source, payload)
    local company, ctx, err = BossCompany(source, payload)
    if not company then return Err(err) end

    local stats = GetCompanyStats(company.id)
    if Config.Boss.ShowSocietyBalance then
        stats.balance = Banking.GetSocietyBalance(Banking.AccountFor(company))
    end
    stats.banking = Banking.name

    local recent = MySQL.query.await('SELECT * FROM nayzeee_billing_invoices WHERE company_id = ? ORDER BY created_at DESC LIMIT 8',
        { company.id }) or {}
    for i, row in ipairs(recent) do recent[i] = FormatInvoice(row, ctx.identifier) end
    stats.recent = recent
    stats.company = PublicCompany(company)
    return stats
end)

-- ██╗███╗   ██╗██╗   ██╗ ██████╗ ██╗ ██████╗███████╗███████╗
-- ██║████╗  ██║██║   ██║██╔═══██╗██║██╔════╝██╔════╝██╔════╝
-- ██║██╔██╗ ██║██║   ██║██║   ██║██║██║     █████╗  ███████╗
-- ██║██║╚██╗██║╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝  ╚════██║
-- ██║██║ ╚████║ ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗███████║
-- ╚═╝╚═╝  ╚═══╝  ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝╚══════╝

local StatusFilters = {
    open = "status IN ('pending', 'partial', 'overdue')",
    overdue = "status = 'overdue'",
    disputed = "status = 'disputed'",
    paid = "status = 'paid'",
    closed = "status IN ('cancelled', 'refunded')",
}

RPC('boss:getInvoices', function(source, payload)
    local company, ctx, err = BossCompany(source, payload)
    if not company then return Err(err) end

    local where, params = { 'company_id = @company' }, { company = company.id }
    if StatusFilters[payload.status] then where[#where + 1] = StatusFilters[payload.status] end
    local search = Shared.Sanitize(payload.search, 40)
    if search ~= '' then
        where[#where + 1] = '(invoice_id LIKE @q OR sender_name LIKE @q OR target_name LIKE @q)'
        params.q = '%' .. search .. '%'
    end
    local page = math.floor(Shared.Clamp(payload.page, 0, 1000))
    params.limit, params.offset = 26, page * 25

    local rows = MySQL.query.await(('SELECT * FROM nayzeee_billing_invoices WHERE %s ORDER BY created_at DESC LIMIT @limit OFFSET @offset')
        :format(table.concat(where, ' AND ')), params) or {}
    local out = {}
    for i = 1, math.min(#rows, 25) do out[i] = FormatInvoice(rows[i], ctx.identifier) end
    return { rows = out, hasMore = #rows > 25, page = page }
end)

RPC('boss:refund', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(payload.invoiceId)
    if not row or not row.company_id then return Err('Invoice not found') end
    if not ctx.isAdmin and not (Config.Boss.CanRefund and IsBossOf(ctx, row.company_id)) then
        return Err('You cannot refund this invoice')
    end
    local reason = Shared.Sanitize(payload.reason, 200)
    if reason == '' then reason = 'Refunded by ' .. ctx.name end
    local amount, err = RefundInvoice(row, source, reason)
    if not amount then return Err(err) end
    return { amount = amount }
end)

RPC('boss:resolveDispute', function(source, payload)
    local ctx = GetCtx(source)
    local row = GetInvoiceRow(payload.invoiceId)
    if not row or row.status ~= 'disputed' or not row.company_id then return Err('Invoice not found') end
    if not ctx.isAdmin and not (Config.Boss.CanResolveDisputes and IsBossOf(ctx, row.company_id)) then
        return Err('You cannot resolve this dispute')
    end

    local targetSrc = Bridge.GetSourceFromIdentifier(row.target_identifier)
    if payload.action == 'cancel' then
        local reason = 'Dispute accepted: ' .. (row.dispute_reason or '')
        if (tonumber(row.amount_paid) or 0) > 0 then
            -- Money was already paid: refund it (status becomes refunded)
            local amount, err = RefundInvoice(row, source, reason)
            if not amount then return Err(err) end
        elseif not CancelInvoice(row, reason, source) then
            return Err('Could not cancel invoice')
        end
    elseif payload.action == 'reinstate' then
        MySQL.update.await([[
            UPDATE nayzeee_billing_invoices
            SET status = IF(amount_paid > 0, 'partial', IF(due_date IS NOT NULL AND due_date < NOW(), 'overdue', 'pending'))
            WHERE invoice_id = ? AND status = 'disputed'
        ]], { row.invoice_id })
        if targetSrc then
            Notify(targetSrc, 'Dispute rejected', ('%s upheld invoice %s'):format(row.company_name, row.invoice_id), 'warning')
            TriggerClientEvent('nayzeee-billing:client:invoiceChanged', targetSrc, row.invoice_id)
        end
        Log(source, 'dispute_rejected', { invoice = row.invoice_id }, row.company_id)
    else
        return Err('Unknown action')
    end
    return true
end)

--  ██████╗ █████╗ ████████╗ █████╗ ██╗      ██████╗  ██████╗
-- ██╔════╝██╔══██╗╚══██╔══╝██╔══██╗██║     ██╔═══██╗██╔════╝
-- ██║     ███████║   ██║   ███████║██║     ██║   ██║██║  ███╗
-- ██║     ██╔══██║   ██║   ██╔══██║██║     ██║   ██║██║   ██║
-- ╚██████╗██║  ██║   ██║   ██║  ██║███████╗╚██████╔╝╚██████╔╝
--  ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝

local function CatalogCompany(source, payload)
    local ctx = GetCtx(source)
    if not ctx then return nil, 'Character not loaded' end
    local company = Companies[payload.companyId or (ctx.company and ctx.company.id) or '']
    if not company then return nil, 'Company not found' end
    if ctx.isAdmin then return company end
    if Config.Boss.CanManageCatalog and IsBossOf(ctx, company.id) then return company end
    return nil, 'You cannot manage this catalog'
end

local function uniqueId(list, key, base)
    base = Shared.Slug(base ~= '' and base or 'item')
    local id, n = base, 1
    local taken = {}
    for _, entry in ipairs(list) do taken[entry[key]] = true end
    while taken[id] do
        n = n + 1
        id = base .. '_' .. n
    end
    return id
end

local function upsert(list, entry)
    for i, existing in ipairs(list) do
        if existing.id == entry.id then
            list[i] = entry
            return
        end
    end
    list[#list + 1] = entry
end

local function remove(list, id)
    for i, existing in ipairs(list) do
        if existing.id == id then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function finish(source, company, action, data)
    SaveCompany(company.id)
    Log(source, action, data, company.id)
    -- Only admins get webhook / account details back
    return PublicCompany(company, Bridge.IsAdmin(source))
end

RPC('catalog:saveProduct', function(source, payload)
    local company, err = CatalogCompany(source, payload)
    if not company then return Err(err) end
    local p = type(payload.product) == 'table' and payload.product or {}

    local name = Shared.Sanitize(p.name, 60)
    local price = Shared.Round(p.price)
    if name == '' then return Err('Product name is required') end
    if price <= 0 or price > Config.MaxInvoiceAmount then return Err('Enter a valid price') end

    local category = Shared.Sanitize(p.category, 40)
    local image = Shared.Sanitize(p.image, 60):gsub('[^%w_%-%.]', '')
    local id = p.id and Shared.Sanitize(p.id, 60) or ''
    if id == '' then id = uniqueId(company.products, 'id', name) end

    upsert(company.products, { id = id, name = name, price = price, category = category ~= '' and category or nil, image = image ~= '' and image or nil })
    return finish(source, company, 'product_saved', { product = name, price = price })
end)

RPC('catalog:deleteProduct', function(source, payload)
    local company, err = CatalogCompany(source, payload)
    if not company then return Err(err) end
    if not remove(company.products, payload.id) then return Err('Product not found') end
    return finish(source, company, 'product_deleted', { product = payload.id })
end)

RPC('catalog:saveCategory', function(source, payload)
    local company, err = CatalogCompany(source, payload)
    if not company then return Err(err) end
    local c = type(payload.category) == 'table' and payload.category or {}
    local label = Shared.Sanitize(c.label, 40)
    if label == '' then return Err('Category name is required') end
    local icon = Shared.Sanitize(c.icon, 40):gsub('[^%w%-]', '')
    local id = c.id and Shared.Slug(c.id) or ''
    if id == '' then id = uniqueId(company.categories, 'id', label) end
    upsert(company.categories, { id = id, label = label, icon = icon ~= '' and icon or 'fa-tag' })
    return finish(source, company, 'category_saved', { category = label })
end)

RPC('catalog:deleteCategory', function(source, payload)
    local company, err = CatalogCompany(source, payload)
    if not company then return Err(err) end
    if not remove(company.categories, payload.id) then return Err('Category not found') end
    for _, product in ipairs(company.products) do
        if product.category == payload.id then product.category = nil end
    end
    return finish(source, company, 'category_deleted', { category = payload.id })
end)

RPC('catalog:saveQuickBill', function(source, payload)
    local company, err = CatalogCompany(source, payload)
    if not company then return Err(err) end
    local q = type(payload.quickBill) == 'table' and payload.quickBill or {}
    local label = Shared.Sanitize(q.label, 60)
    local amount = Shared.Round(q.amount)
    if label == '' then return Err('Quick bill name is required') end
    if amount <= 0 or amount > Config.MaxInvoiceAmount then return Err('Enter a valid amount') end
    local id = q.id and Shared.Sanitize(q.id, 60) or ''
    if id == '' then id = uniqueId(company.quickBills, 'id', label) end
    upsert(company.quickBills, { id = id, label = label, amount = amount, description = Shared.Sanitize(q.description, 120) })
    return finish(source, company, 'quickbill_saved', { quickbill = label, amount = amount })
end)

RPC('catalog:deleteQuickBill', function(source, payload)
    local company, err = CatalogCompany(source, payload)
    if not company then return Err(err) end
    if not remove(company.quickBills, payload.id) then return Err('Quick bill not found') end
    return finish(source, company, 'quickbill_deleted', { quickbill = payload.id })
end)
