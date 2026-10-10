--[[
    NAYZEEE BILLING - Admin
    Every handler checks Bridge.IsAdmin on the server (ACE or framework group).
]]

local function AdminRPC(name, handler)
    RPC('admin:' .. name, function(source, payload)
        if not Bridge.IsAdmin(source) then
            Log(source, 'admin_denied', { action = name })
            return Err('No admin access')
        end
        return handler(source, payload)
    end)
end

lib.callback.register('nayzeee-billing:isAdmin', function(source)
    return Bridge.IsAdmin(source)
end)

local function CompanyList()
    local list = {}
    for _, c in pairs(Companies) do list[#list + 1] = PublicCompany(c, true) end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

--  ██████╗ ██╗   ██╗███████╗██████╗ ██╗   ██╗██╗███████╗██╗    ██╗
-- ██╔═══██╗██║   ██║██╔════╝██╔══██╗██║   ██║██║██╔════╝██║    ██║
-- ██║   ██║██║   ██║█████╗  ██████╔╝██║   ██║██║█████╗  ██║ █╗ ██║
-- ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗╚██╗ ██╔╝██║██╔══╝  ██║███╗██║
-- ╚██████╔╝ ╚████╔╝ ███████╗██║  ██║ ╚████╔╝ ██║███████╗╚███╔███╔╝
--  ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝

AdminRPC('getData', function()
    local stats = MySQL.single.await([[
        SELECT
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE created_at >= CURDATE()) AS invoicesToday,
            (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_payments WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)) AS revenueWeek,
            (SELECT COALESCE(SUM(total + late_fee - amount_paid), 0) FROM nayzeee_billing_invoices WHERE status IN ('pending', 'partial', 'overdue')) AS outstanding,
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE status IN ('pending', 'partial', 'overdue')) AS openCount,
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE status = 'disputed') AS disputedCount,
            (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_pending_payouts) AS pendingPayouts
    ]]) or {}

    local byCompany = MySQL.query.await([[
        SELECT company_id AS id, COALESCE(SUM(amount), 0) AS revenue, COUNT(*) AS payments
        FROM nayzeee_billing_payments
        WHERE company_id IS NOT NULL AND created_at >= DATE_SUB(CURDATE(), INTERVAL 29 DAY)
        GROUP BY company_id ORDER BY revenue DESC LIMIT 8
    ]]) or {}
    for _, row in ipairs(byCompany) do
        row.label = Companies[row.id] and Companies[row.id].label or row.id
        row.revenue = tonumber(row.revenue) or 0
    end

    return {
        companies = CompanyList(),
        registers = GetRegisterList(),
        stats = {
            invoicesToday = tonumber(stats.invoicesToday) or 0,
            revenueWeek = tonumber(stats.revenueWeek) or 0,
            outstanding = tonumber(stats.outstanding) or 0,
            openCount = tonumber(stats.openCount) or 0,
            disputedCount = tonumber(stats.disputedCount) or 0,
            pendingPayouts = tonumber(stats.pendingPayouts) or 0,
            byCompany = byCompany,
        },
        system = {
            framework = Shared.GetFramework(),
            banking = Banking.name,
            inventory = Inventory.Name(),
            version = Shared.Version,
            imagePath = Inventory.ImagePath(),
        },
        defaultCategories = Config.DefaultCategories,
    }
end)

--  ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ███╗   ██╗██╗███████╗███████╗
-- ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗████╗  ██║██║██╔════╝██╔════╝
-- ██║     ██║   ██║██╔████╔██║██████╔╝███████║██╔██╗ ██║██║█████╗  ███████╗
-- ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║╚██╗██║██║██╔══╝  ╚════██║
-- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║██║ ╚████║██║███████╗███████║
--  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝

AdminRPC('saveCompany', function(source, payload)
    local data = type(payload.company) == 'table' and payload.company or {}
    local id = Shared.Slug(data.id or '')
    if id == '' then return Err('Company ID is required') end
    local label = Shared.Sanitize(data.label, 100)
    if label == '' then return Err('Company name is required') end

    local isNew = Companies[id] == nil
    if payload.isNew and not isNew then return Err('A company with that ID already exists') end

    local c = Companies[id] or { id = id, categories = {}, products = {}, quickBills = {} }
    c.label = label
    c.shortName = Shared.Sanitize(data.shortName, 10)
    if c.shortName == '' then c.shortName = label:sub(1, 4):upper() end
    c.job = Shared.Sanitize(data.job, 50)
    if c.job == '' then c.job = nil end

    local jobs = {}
    for job in tostring(data.jobs or ''):gmatch('[^,%s]+') do
        jobs[#jobs + 1] = Shared.Sanitize(job, 50)
    end
    c.jobs = #jobs > 0 and jobs or nil

    c.account = Shared.Sanitize(data.account, 60)
    if c.account == '' then c.account = nil end
    c.taxRate = Shared.Round(Shared.Clamp(data.taxRate, 0, 100) / 100, 4)
    c.allowDiscounts = data.allowDiscounts == true
    c.maxDiscount = Shared.Clamp(data.maxDiscount or 100, 0, 100)
    c.allowCustomItems = data.allowCustomItems == true
    c.allowTips = data.allowTips == true
    c.minGrade = math.floor(Shared.Clamp(data.minGrade or 0, 0, 100))
    c.bossGrade = (data.bossGrade ~= nil and data.bossGrade ~= '') and math.floor(Shared.Clamp(data.bossGrade, 0, 100)) or nil
    c.commission = (data.commission ~= nil and data.commission ~= '') and Shared.Round(Shared.Clamp(data.commission, 0, 100) / 100, 4) or nil
    c.dueDays = (data.dueDays ~= nil and data.dueDays ~= '') and math.floor(Shared.Clamp(data.dueDays, 0, 365)) or nil

    local refPrefix = tostring(data.refPrefix or ''):upper():gsub('[^%w]', ''):sub(1, 6)
    c.refPrefix = refPrefix ~= '' and refPrefix or nil

    local webhook = Shared.Sanitize(data.webhook, 255)
    c.webhook = webhook:match('^https://') and webhook or nil

    Companies[id] = c
    SaveCompany(id)
    LoadCompanies() -- normalize + rebuild indexes
    BroadcastRegisters()
    Log(source, isNew and 'company_created' or 'company_updated', { company = id, label = label }, id)
    return CompanyList()
end)

AdminRPC('deleteCompany', function(source, payload)
    local c = Companies[payload.id]
    if not c then return Err('Company not found') end
    ResetCompany(payload.id)
    BroadcastRegisters()
    Log(source, c.isConfig and 'company_reset' or 'company_deleted', { company = payload.id }, payload.id)
    return CompanyList()
end)

-- ██████╗ ███████╗ ██████╗ ██╗███████╗████████╗███████╗██████╗ ███████╗
-- ██╔══██╗██╔════╝██╔════╝ ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝
-- ██████╔╝█████╗  ██║  ███╗██║███████╗   ██║   █████╗  ██████╔╝███████╗
-- ██╔══██╗██╔══╝  ██║   ██║██║╚════██║   ██║   ██╔══╝  ██╔══██╗╚════██║
-- ██║  ██║███████╗╚██████╔╝██║███████║   ██║   ███████╗██║  ██║███████║
-- ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝

AdminRPC('saveRegister', function(source, payload)
    local label = Shared.Sanitize(payload.label, 100)
    if label == '' then return Err('Register label is required') end
    if not Companies[payload.company] then return Err('Select a company') end

    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local register = AddRegister({
        label = label,
        company = payload.company,
        coords = { x = Shared.Round(coords.x), y = Shared.Round(coords.y), z = Shared.Round(coords.z) },
        heading = Shared.Round(GetEntityHeading(ped), 1),
        radius = Shared.Clamp(payload.radius or 2.0, 0.5, 10.0),
    })
    Log(source, 'register_created', { register = register.id, company = payload.company }, payload.company)
    return GetRegisterList()
end)

AdminRPC('deleteRegister', function(source, payload)
    local ok, err = DeleteRegister(payload.id)
    if not ok then return Err(err) end
    Log(source, 'register_deleted', { register = payload.id })
    return GetRegisterList()
end)

AdminRPC('teleport', function(source, payload)
    local r = Registers[payload.id]
    if not r then return Err('Register not found') end
    SetEntityCoords(GetPlayerPed(source), r.coords.x, r.coords.y, r.coords.z, false, false, false, false)
    return true
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

AdminRPC('getInvoices', function(source, payload)
    local where, params = { '1 = 1' }, {}
    if StatusFilters[payload.status] then where[#where + 1] = StatusFilters[payload.status] end
    if payload.companyId and Companies[payload.companyId] then
        where[#where + 1] = 'company_id = @company'
        params.company = payload.companyId
    end
    local search = Shared.Sanitize(payload.search, 40)
    if search ~= '' then
        where[#where + 1] = '(invoice_id LIKE @q OR sender_name LIKE @q OR target_name LIKE @q OR company_name LIKE @q)'
        params.q = '%' .. search .. '%'
    end
    local page = math.floor(Shared.Clamp(payload.page, 0, 10000))
    params.limit, params.offset = 31, page * 30

    local rows = MySQL.query.await(('SELECT * FROM nayzeee_billing_invoices WHERE %s ORDER BY created_at DESC LIMIT @limit OFFSET @offset')
        :format(table.concat(where, ' AND ')), params) or {}
    local out = {}
    for i = 1, math.min(#rows, 30) do out[i] = FormatInvoice(rows[i]) end
    return { rows = out, hasMore = #rows > 30, page = page }
end)

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

AdminRPC('getLogs', function(source, payload)
    local where, params = { '1 = 1' }, {}
    local search = Shared.Sanitize(payload.search, 40)
    if search ~= '' then
        where[#where + 1] = '(player LIKE @q OR action LIKE @q OR data LIKE @q)'
        params.q = '%' .. search .. '%'
    end
    local page = math.floor(Shared.Clamp(payload.page, 0, 10000))
    params.limit, params.offset = 41, page * 40

    local rows = MySQL.query.await(('SELECT id, player, company_id AS companyId, action, data, timestamp FROM nayzeee_billing_logs WHERE %s ORDER BY id DESC LIMIT @limit OFFSET @offset')
        :format(table.concat(where, ' AND ')), params) or {}
    local out = {}
    for i = 1, math.min(#rows, 40) do
        local row = rows[i]
        local ok, data = pcall(json.decode, row.data or '{}')
        row.data = ok and data or {}
        out[i] = row
    end
    return { rows = out, hasMore = #rows > 40, page = page }
end)
