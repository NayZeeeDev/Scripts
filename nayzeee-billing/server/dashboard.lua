--[[
    NAYZEEE BILLING - Dashboard & activity
]]

local function lastDays(todayStr, count)
    local y, m, d = todayStr:match('(%d+)-(%d+)-(%d+)')
    local days = {}
    for i = count - 1, 0, -1 do
        local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) - i, hour = 12 })
        days[#days + 1] = { key = os.date('%Y-%m-%d', t), dow = tonumber(os.date('%w', t)), paid = 0, received = 0 }
    end
    return days
end

local DAY = "DATE_FORMAT(created_at, '%Y-%m-%d')"
local WEEK = 'created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)'
local PREV = 'created_at >= DATE_SUB(CURDATE(), INTERVAL 13 DAY) AND created_at < DATE_SUB(CURDATE(), INTERVAL 6 DAY)'
local WEEKS = 2

--[[
    Weekly summary chart (last 7 days) plus this week / last week totals for the overview cards
    (rolling 7-day buckets, the last one = the 7 days ending today).
    paid = { sum, where } money out, received = { sum, where } money in
]]
local function cashflow(paid, received, params)
    local today = MySQL.scalar.await("SELECT DATE_FORMAT(CURDATE(), '%Y-%m-%d')") or os.date('%Y-%m-%d')
    local days = lastDays(today, 7)
    local idx = {}
    for i, d in ipairs(days) do idx[d.key] = i end

    local y, m, d = today:match('(%d+)-(%d+)-(%d+)')
    local weeks = {}
    for i = WEEKS - 1, 0, -1 do
        local start = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) - (i * 7 + 6), hour = 12 })
        weeks[#weeks + 1] = { key = os.date('%Y-%m-%d', start), paid = 0, received = 0 }
    end

    for _, part in ipairs({ { 'paid', paid }, { 'received', received } }) do
        local key, q = part[1], part[2]
        local daily = ('SELECT %s AS day, %s AS total FROM nayzeee_billing_payments WHERE %s AND %s GROUP BY day'):format(DAY, q.sum, q.where, WEEK)
        for _, r in ipairs(MySQL.query.await(daily, params) or {}) do
            local i = idx[r.day]; if i then days[i][key] = Shared.Round(tonumber(r.total) or 0) end
        end
        local weekly = ([[SELECT FLOOR(DATEDIFF(CURDATE(), DATE(created_at)) / 7) AS w, %s AS total FROM nayzeee_billing_payments
            WHERE %s AND created_at >= DATE_SUB(CURDATE(), INTERVAL %d DAY) GROUP BY w]]):format(q.sum, q.where, WEEKS * 7 - 1)
        for _, r in ipairs(MySQL.query.await(weekly, params) or {}) do
            local i = WEEKS - (tonumber(r.w) or WEEKS)
            if weeks[i] then weeks[i][key] = Shared.Round(tonumber(r.total) or 0) end
        end
    end
    return days, weeks
end

local function delta(now, before)
    now, before = tonumber(now) or 0, tonumber(before) or 0
    if before <= 0 then return now > 0 and 100 or 0 end
    return math.floor(((now - before) / before) * 100 + 0.5)
end

-- Recent activity entries built from invoices + payments involving the account
local function recent(where, params, viewer)
    local rows = MySQL.query.await(('SELECT * FROM nayzeee_billing_invoices WHERE %s ORDER BY COALESCE(paid_at, created_at) DESC LIMIT 6'):format(where), params) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local inv = FormatInvoice(r, viewer)
        local kind
        if inv.direction == 'sent' then
            kind = (r.status == 'paid' or r.status == 'partial') and 'payment_in' or (r.status == 'cancelled' and 'cancelled' or 'created')
        else
            kind = (r.status == 'paid' or r.status == 'partial') and 'payment_out' or (r.status == 'cancelled' and 'cancelled' or 'invoice_in')
        end
        out[#out + 1] = { kind = kind, id = inv.id, ref = inv.ref, name = inv.direction == 'sent' and inv.recipient or inv.sender,
            amount = inv.total, at = r.paid_at or r.created_at }
    end
    return out
end

RPC('dashboard:get', function(source, payload)
    local ctx = GetCtx(source)
    if not ctx then return Err(L('error.not_loaded', 'Character not loaded')) end
    local account = payload.account == 'society' and 'society' or 'personal'

    if account == 'personal' then
        local p = { me = ctx.identifier }
        local s = MySQL.single.await(([[SELECT
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE COALESCE(recipient_type,'citizen') = 'citizen' AND target_identifier = @me AND status IN ('pending','partial','overdue')) AS due,
            (SELECT COALESCE(SUM(total + late_fee - amount_paid), 0) FROM nayzeee_billing_invoices WHERE COALESCE(recipient_type,'citizen') = 'citizen' AND target_identifier = @me AND status IN ('pending','partial','overdue')) AS unpaid,
            (SELECT COALESCE(SUM(amount + tip), 0) FROM nayzeee_billing_payments WHERE payer_identifier = @me AND method <> 'society' AND kind <> 'refund' AND %s) AS paidWeek,
            (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE sender_identifier = @me AND company_id IS NULL AND kind <> 'refund' AND %s) AS receivedWeek,
            (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE sender_identifier = @me AND company_id IS NULL AND kind <> 'refund' AND %s) AS receivedPrev
        ]]):format(WEEK, WEEK, PREV), p) or {}

        local alerts = MySQL.query.await([[SELECT * FROM nayzeee_billing_invoices
            WHERE COALESCE(recipient_type,'citizen') = 'citizen' AND target_identifier = @me AND status IN ('pending','partial','overdue')
            ORDER BY (status = 'overdue') DESC, due_date ASC LIMIT 5]], p) or {}
        for i, r in ipairs(alerts) do alerts[i] = FormatInvoice(r, { identifier = ctx.identifier }) end

        local days, weeks = cashflow(
            { sum = 'SUM(amount + tip)', where = "payer_identifier = @me AND method <> 'society' AND kind <> 'refund'" },
            { sum = 'SUM(amount)', where = "sender_identifier = @me AND company_id IS NULL AND kind <> 'refund'" }, p)

        return {
            account = 'personal',
            due = tonumber(s.due) or 0, unpaid = tonumber(s.unpaid) or 0,
            paidWeek = tonumber(s.paidWeek) or 0, receivedWeek = tonumber(s.receivedWeek) or 0,
            delta = delta(s.receivedWeek, s.receivedPrev),
            series = days, weeks = weeks,
            alerts = alerts,
            recent = recent("(COALESCE(recipient_type,'citizen') = 'citizen' AND target_identifier = @me) OR (company_id IS NULL AND sender_identifier = @me)", p, { identifier = ctx.identifier }),
            balance = Money.Get(source, 'bank'),
        }
    end

    if not ctx.society then return Err(L('error.no_society', 'You are not in a billing society')) end
    if not Can(ctx, 'overview') then return Err(L('error.no_permission', 'You do not have permission')) end
    local p = { soc = ctx.society }
    local s = MySQL.single.await(([[SELECT
        (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE recipient_type = 'society' AND target_society = @soc AND status IN ('pending','partial','overdue')) AS due,
        (SELECT COALESCE(SUM(total + late_fee - amount_paid), 0) FROM nayzeee_billing_invoices WHERE recipient_type = 'society' AND target_society = @soc AND status IN ('pending','partial','overdue')) AS unpaid,
        (SELECT COALESCE(SUM(amount + tip), 0) FROM nayzeee_billing_payments WHERE target_society = @soc AND method = 'society' AND kind <> 'refund' AND %s) AS paidWeek,
        (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE company_id = @soc AND kind <> 'refund' AND %s) AS receivedWeek,
        (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE company_id = @soc AND kind <> 'refund' AND %s) AS receivedPrev,
        (SELECT COALESCE(SUM(total + late_fee - amount_paid), 0) FROM nayzeee_billing_invoices WHERE company_id = @soc AND status IN ('pending','partial','overdue')) AS receivable
    ]]):format(WEEK, WEEK, PREV), p) or {}

    local alerts = MySQL.query.await([[SELECT * FROM nayzeee_billing_invoices
        WHERE ((recipient_type = 'society' AND target_society = @soc) OR company_id = @soc) AND status IN ('pending','partial','overdue')
        ORDER BY (status = 'overdue') DESC, due_date ASC LIMIT 5]], p) or {}
    for i, r in ipairs(alerts) do alerts[i] = FormatInvoice(r, { identifier = ctx.identifier, society = ctx.society }) end

    local days, weeks = cashflow(
        { sum = 'SUM(amount + tip)', where = "target_society = @soc AND method = 'society' AND kind <> 'refund'" },
        { sum = 'SUM(amount)', where = "company_id = @soc AND kind <> 'refund'" }, p)

    return {
        account = 'society',
        due = tonumber(s.due) or 0, unpaid = tonumber(s.unpaid) or 0,
        paidWeek = tonumber(s.paidWeek) or 0, receivedWeek = tonumber(s.receivedWeek) or 0,
        receivable = tonumber(s.receivable) or 0,
        delta = delta(s.receivedWeek, s.receivedPrev),
        series = days, weeks = weeks,
        alerts = alerts,
        recent = recent("(recipient_type = 'society' AND target_society = @soc) OR company_id = @soc", p, { identifier = ctx.identifier, society = ctx.society }),
        balance = Banking.SocietyBalance(ctx.society),
    }
end)

--  █████╗  ██████╗████████╗██╗██╗   ██╗██╗████████╗██╗   ██╗
-- ██╔══██╗██╔════╝╚══██╔══╝██║██║   ██║██║╚══██╔══╝╚██╗ ██╔╝
-- ███████║██║        ██║   ██║██║   ██║██║   ██║    ╚████╔╝
-- ██╔══██║██║        ██║   ██║╚██╗ ██╔╝██║   ██║     ╚██╔╝
-- ██║  ██║╚██████╗   ██║   ██║ ╚████╔╝ ██║   ██║      ██║
-- ╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚═╝  ╚═══╝  ╚═╝   ╚═╝      ╚═╝

local Categories = {
    invoice = "action IN ('invoice_created','invoice_received','invoice_cancelled','invoice_disputed','dispute_rejected','invoice_printed')",
    payment = "action IN ('invoice_paid','payment_received','invoice_collected','invoice_refunded','cash_collected')",
    template = "action LIKE 'template_%'",
    item = "action LIKE 'item%'",
    permission = "action LIKE 'group_%' OR action LIKE 'member_%'",
}

RPC('activity:list', function(source, payload)
    local ctx = GetCtx(source)
    local account = payload.account == 'society' and 'society' or 'personal'
    local where, params = {}, {}
    if account == 'society' then
        if not Can(ctx, 'activity') then return Err(L('error.no_permission', 'You do not have permission')) end
        where[1], params.soc = 'company_id = @soc', ctx.society
    else
        where[1], params.me = 'identifier = @me AND company_id IS NULL', ctx.identifier
    end
    if Categories[payload.category] then where[#where + 1] = '(' .. Categories[payload.category] .. ')' end
    local search = Shared.Sanitize(payload.search, 40)
    if search ~= '' then
        where[#where + 1] = '(player LIKE @q OR action LIKE @q OR data LIKE @q)'
        params.q = '%' .. search .. '%'
    end
    local size = math.floor(Shared.Clamp(payload.pageSize or Config.UI.PageSize, 5, 50))
    local page = math.floor(Shared.Clamp(payload.page, 1, 100000))
    params.limit, params.offset = size, (page - 1) * size
    local w = table.concat(where, ' AND ')
    local total = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_billing_logs WHERE ' .. w, params)) or 0
    local rows = MySQL.query.await('SELECT id, player, action, data, timestamp FROM nayzeee_billing_logs WHERE ' .. w .. ' ORDER BY id DESC LIMIT @limit OFFSET @offset', params) or {}
    for _, r in ipairs(rows) do
        local ok, d = pcall(json.decode, r.data or '{}')
        r.data = ok and d or {}
        r.data.byIdentifier = nil
    end
    return { rows = rows, total = total, page = page, pageSize = size }
end)
