--[[
    NAYZEEE BILLING - Server Core
    Companies, player context, permissions, RPC plumbing, logging.
    Discord: discord.gg/nayzeeedev
]]

Companies = {}
BillingReady = false
local JobToCompany = {}

-- ██████╗ ██████╗  ██████╗
-- ██╔══██╗██╔══██╗██╔════╝
-- ██████╔╝██████╔╝██║
-- ██╔══██╗██╔═══╝ ██║
-- ██║  ██║██║     ╚██████╗
-- ╚═╝  ╚═╝╚═╝      ╚═════╝

-- Every NUI action goes through lib.callback 'nayzeee-billing:<name>'.
-- Handlers return data, or Err('message'). Permissions are ALWAYS checked here on the server.
function Err(message)
    return { __err = message }
end

function RPC(name, handler)
    lib.callback.register('nayzeee-billing:' .. name, function(source, payload)
        if not BillingReady then return { ok = false, error = 'Billing is still starting up' } end
        local ok, result = pcall(handler, source, type(payload) == 'table' and payload or {})
        if not ok then
            print(('^1[NAYZEEE-BILLING]^7 RPC %s failed: %s'):format(name, tostring(result)))
            return { ok = false, error = 'Something went wrong' }
        end
        if type(result) == 'table' and result.__err then
            return { ok = false, error = result.__err }
        end
        return { ok = true, data = result }
    end)
end

local throttles = {}
function Throttle(source, key, seconds)
    local id = source .. ':' .. key
    local now = GetGameTimer()
    if throttles[id] and now < throttles[id] then return true end
    throttles[id] = now + math.floor(seconds * 1000)
    return false
end

AddEventHandler('playerDropped', function()
    local src = tostring(source)
    for k in pairs(throttles) do
        if k:sub(1, #src + 1) == src .. ':' then throttles[k] = nil end
    end
end)

--  ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ███╗   ██╗██╗███████╗███████╗
-- ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗████╗  ██║██║██╔════╝██╔════╝
-- ██║     ██║   ██║██╔████╔██║██████╔╝███████║██╔██╗ ██║██║█████╗  ███████╗
-- ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║╚██╗██║██║██╔══╝  ╚════██║
-- ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║██║ ╚████║██║███████╗███████║
--  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝

local function decode(str, fallback)
    if type(str) ~= 'string' or str == '' then return fallback end
    local ok, value = pcall(json.decode, str)
    if ok and value ~= nil then return value end
    return fallback
end

local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

local SettingKeys = {
    'jobs', 'account', 'minGrade', 'bossGrade', 'maxDiscount', 'allowCustomItems',
    'allowTips', 'commission', 'dueDays', 'webhook', 'refPrefix',
}

BoolSettings = { allowCustomItems = true, allowTips = true }

local function NormalizeCompany(id, c)
    c.id = id
    c.label = c.label or id
    c.shortName = c.shortName or c.label:sub(1, 4):upper()
    c.taxRate = tonumber(c.taxRate) or Config.DefaultTaxRate
    c.allowDiscounts = c.allowDiscounts == true
    c.maxDiscount = Shared.Clamp(c.maxDiscount or 100, 0, 100)
    c.allowCustomItems = c.allowCustomItems == true
    c.allowTips = c.allowTips ~= false
    c.minGrade = tonumber(c.minGrade) or 0
    c.bossGrade = tonumber(c.bossGrade)
    c.categories = c.categories or copy(Config.DefaultCategories)
    c.products = c.products or {}
    c.quickBills = c.quickBills or {}
    return c
end

local function RebuildJobIndex()
    JobToCompany = {}
    for id, c in pairs(Companies) do
        if c.job and c.job ~= '' then JobToCompany[c.job] = id end
        for _, job in ipairs(type(c.jobs) == 'table' and c.jobs or {}) do
            JobToCompany[job] = id
        end
    end
end

function LoadCompanies()
    Companies = {}
    for id, c in pairs(Config.Companies or {}) do
        Companies[id] = NormalizeCompany(id, copy(c))
        Companies[id].isConfig = true
    end

    -- Database rows (admin-created companies and edits to config companies) override config
    for _, row in ipairs(MySQL.query.await('SELECT * FROM nayzeee_billing_companies') or {}) do
        local base = Companies[row.id] or {}
        local c = copy(base)
        c.label = row.label
        c.shortName = row.short_name
        c.job = row.job
        c.taxRate = tonumber(row.tax_rate)
        c.allowDiscounts = row.allow_discounts == true or tonumber(row.allow_discounts) == 1
        c.categories = decode(row.categories, base.categories)
        c.products = decode(row.products, base.products)
        c.quickBills = decode(row.quick_bills, base.quickBills)
        local settings = decode(row.settings, {})
        for _, key in ipairs(SettingKeys) do
            local value = settings[key]
            if value ~= nil then
                -- false = explicitly cleared in-game (except real boolean settings)
                if value == false and not BoolSettings[key] then value = nil end
                c[key] = value
            end
        end
        Companies[row.id] = NormalizeCompany(row.id, c)
        Companies[row.id].isConfig = base.isConfig == true
        Companies[row.id].hasOverride = true
    end

    RebuildJobIndex()
    Shared.Debug('Loaded', Shared.Count(Companies), 'companies')
end

function SaveCompany(id)
    local c = Companies[id]
    if not c then return false end
    local settings = {}
    for _, key in ipairs(SettingKeys) do
        local value = c[key]
        if value == nil then value = false end -- json can't store nil; false marks "cleared"
        settings[key] = value
    end

    MySQL.query.await([[
        INSERT INTO nayzeee_billing_companies (id, label, short_name, job, tax_rate, allow_discounts, categories, products, quick_bills, settings)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label), short_name = VALUES(short_name), job = VALUES(job),
            tax_rate = VALUES(tax_rate), allow_discounts = VALUES(allow_discounts), categories = VALUES(categories),
            products = VALUES(products), quick_bills = VALUES(quick_bills), settings = VALUES(settings)
    ]], {
        id, c.label, c.shortName, c.job, c.taxRate, c.allowDiscounts and 1 or 0,
        json.encode(c.categories or {}), json.encode(c.products or {}), json.encode(c.quickBills or {}),
        json.encode(settings),
    })
    c.hasOverride = true
    RebuildJobIndex()
    TriggerClientEvent('nayzeee-billing:client:companiesChanged', -1)
    return true
end

-- Remove the DB row. Config companies revert to companies.lua, custom companies are deleted.
function ResetCompany(id)
    MySQL.query.await('DELETE FROM nayzeee_billing_companies WHERE id = ?', { id })
    LoadCompanies()
    TriggerClientEvent('nayzeee-billing:client:companiesChanged', -1)
end

function GetCompanyByJob(job)
    local id = job and JobToCompany[job]
    return id and Companies[id] or nil
end

-- Safe for the client (no webhooks)
function PublicCompany(c, full)
    if not c then return nil end
    local out = {
        id = c.id, label = c.label, shortName = c.shortName, job = c.job, jobs = c.jobs,
        taxRate = c.taxRate, allowDiscounts = c.allowDiscounts, maxDiscount = c.maxDiscount,
        allowCustomItems = c.allowCustomItems, allowTips = c.allowTips,
        dueDays = c.dueDays or Config.Invoices.DueDays,
        categories = c.categories, products = c.products, quickBills = c.quickBills,
    }
    if full then
        out.account = c.account
        out.minGrade = c.minGrade
        out.bossGrade = c.bossGrade
        out.commission = c.commission
        out.webhook = c.webhook
        out.refPrefix = c.refPrefix
        out.isConfig = c.isConfig
        out.hasOverride = c.hasOverride
    end
    return out
end

--  ██████╗ ██████╗ ███╗   ██╗████████╗███████╗██╗  ██╗████████╗
-- ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔════╝╚██╗██╔╝╚══██╔══╝
-- ██║     ██║   ██║██╔██╗ ██║   ██║   █████╗   ╚███╔╝    ██║
-- ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══╝   ██╔██╗    ██║
-- ╚██████╗╚██████╔╝██║ ╚████║   ██║   ███████╗██╔╝ ██╗   ██║
--  ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝   ╚═╝

-- Everything permission-related about a player in one place
function GetCtx(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return nil end

    local job = Bridge.GetJob(source) or { name = 'unemployed', grade = 0 }
    local company = GetCompanyByJob(job.name)
    local ctx = {
        source = source,
        identifier = identifier,
        name = Bridge.GetName(source),
        job = job,
        company = company,
        canBill = false,
        isBoss = false,
        canRemote = false,
        isAdmin = Bridge.IsAdmin(source),
    }

    if company then
        local onDuty = not Config.Billing.RequireOnDuty or job.onDuty
        ctx.canBill = onDuty and job.grade >= (company.minGrade or 0)
        if company.bossGrade then
            ctx.isBoss = job.grade >= company.bossGrade
        else
            ctx.isBoss = job.isBoss == true
        end
        ctx.canRemote = ctx.canBill and Shared.TableContains(Config.Billing.RemoteBillingJobs, job.name)
    end
    ctx.canPersonal = Config.Billing.AllowPersonalBilling == true
    return ctx
end

function IsBossOf(ctx, companyId)
    if not ctx then return false end
    if ctx.isAdmin then return true end
    return ctx.isBoss and ctx.company and ctx.company.id == companyId
end

-- ██╗  ██╗███████╗██╗     ██████╗ ███████╗██████╗ ███████╗
-- ██║  ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗██╔════╝
-- ███████║█████╗  ██║     ██████╔╝█████╗  ██████╔╝███████╗
-- ██╔══██║██╔══╝  ██║     ██╔═══╝ ██╔══╝  ██╔══██╗╚════██║
-- ██║  ██║███████╗███████╗██║     ███████╗██║  ██║███████║
-- ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝

function GetDistanceBetween(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return 9999.0 end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

function GetDistanceTo(source, coords)
    local ped = GetPlayerPed(source)
    if ped == 0 then return 9999.0 end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z))
end

function Notify(source, title, message, notifType)
    if not source or source <= 0 then return end
    TriggerClientEvent('nayzeee-billing:client:notify', source, {
        title = title, message = message, type = notifType or 'info',
    })
end

function NotifyCompanyBosses(companyId, title, message, notifType)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ctx = GetCtx(src)
        if ctx and ctx.company and ctx.company.id == companyId and ctx.isBoss then
            Notify(src, title, message, notifType)
        end
    end
end

function Remaining(inv)
    return Shared.Round((tonumber(inv.total) or 0) + (tonumber(inv.late_fee) or 0) - (tonumber(inv.amount_paid) or 0))
end

function FormatInvoice(inv, viewer)
    local items = inv.items
    if type(items) == 'string' then
        local ok, decoded = pcall(json.decode, items)
        items = ok and decoded or {}
    end
    return {
        id = inv.invoice_id,
        companyId = inv.company_id,
        company = inv.company_name,
        senderName = inv.sender_name,
        senderJob = inv.sender_job,
        targetName = inv.target_name,
        direction = viewer and (inv.sender_identifier == viewer and 'sent' or (inv.target_identifier == viewer and 'received' or nil)) or nil,
        items = items or {},
        notes = inv.notes,
        subtotal = tonumber(inv.subtotal) or 0,
        tax = tonumber(inv.tax) or 0,
        discount = tonumber(inv.discount) or 0,
        total = tonumber(inv.total) or 0,
        lateFee = tonumber(inv.late_fee) or 0,
        amountPaid = tonumber(inv.amount_paid) or 0,
        tip = tonumber(inv.tip) or 0,
        tipsAllowed = Config.Tips.Enabled and inv.company_id ~= nil and Companies[inv.company_id] ~= nil
            and Companies[inv.company_id].allowTips == true,
        remaining = math.max(0, Remaining(inv)),
        status = inv.status,
        method = inv.payment_method,
        registerId = inv.register_id,
        cancelReason = inv.cancel_reason,
        disputeReason = inv.dispute_reason,
        createdAt = inv.created_at,
        dueDate = inv.due_date,
        paidAt = inv.paid_at,
    }
end

function GetInvoiceRow(invoiceId)
    if type(invoiceId) ~= 'string' or #invoiceId > 20 then return nil end
    return MySQL.single.await('SELECT *, TIMESTAMPDIFF(MINUTE, created_at, NOW()) AS age_minutes FROM nayzeee_billing_invoices WHERE invoice_id = ?', { invoiceId })
end

-- ██╗      ██████╗  ██████╗  ██████╗ ██╗███╗   ██╗ ██████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝ ██║████╗  ██║██╔════╝
-- ██║     ██║   ██║██║  ███╗██║  ███╗██║██╔██╗ ██║██║  ███╗
-- ██║     ██║   ██║██║   ██║██║   ██║██║██║╚██╗██║██║   ██║
-- ███████╗╚██████╔╝╚██████╔╝╚██████╔╝██║██║ ╚████║╚██████╔╝
-- ╚══════╝ ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝

local function sendWebhook(url, title, fields)
    if not url or url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = Config.Logging.DiscordTitle,
        embeds = { {
            title = title,
            color = Config.Logging.DiscordColor,
            fields = fields,
            footer = { text = 'nayzeee-billing v' .. Shared.Version },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

function Log(source, action, data, companyId)
    if not Config.Logging.Enabled then return end
    data = data or {}
    local name = (source and source > 0) and Bridge.GetName(source) or 'System'
    local identifier = (source and source > 0) and Bridge.GetIdentifier(source) or nil

    MySQL.insert('INSERT INTO nayzeee_billing_logs (player, identifier, company_id, action, data) VALUES (?, ?, ?, ?, ?)',
        { name, identifier, companyId, action, json.encode(data) })

    local fields = { { name = 'Player', value = name, inline = true } }
    if source and source > 0 then
        fields[#fields + 1] = { name = 'Server ID', value = tostring(source), inline = true }
    end
    for k, v in pairs(data) do
        if type(v) ~= 'table' then
            local value = type(v) == 'number' and (k:find('amount') or k:find('total')) and Shared.FormatCurrency(v) or tostring(v)
            fields[#fields + 1] = { name = k, value = value, inline = true }
        end
    end
    local title = Config.Logging.DiscordTitle .. ' · ' .. action:gsub('_', ' '):upper()
    sendWebhook(Config.Logging.DiscordWebhook, title, fields)
    local company = companyId and Companies[companyId]
    if company and company.webhook then
        sendWebhook(company.webhook, title, fields)
    end
end

--  ██████╗ ██████╗ ███╗   ██╗████████╗███████╗██╗  ██╗████████╗
-- ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔════╝╚██╗██╔╝╚══██╔══╝
-- ██║     ██║   ██║██╔██╗ ██║   ██║   █████╗   ╚███╔╝    ██║
-- ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══╝   ██╔██╗    ██║
-- ╚██████╗╚██████╔╝██║ ╚████║   ██║   ███████╗██╔╝ ██╗   ██║
--  ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝   ╚═╝

RPC('getContext', function(source)
    local ctx = GetCtx(source)
    if not ctx then return Err('Character not loaded') end

    local received = MySQL.query.await([[
        SELECT * FROM nayzeee_billing_invoices
        WHERE target_identifier = ? AND status IN ('pending', 'partial', 'overdue', 'disputed')
        ORDER BY created_at DESC LIMIT 100
    ]], { ctx.identifier }) or {}

    local invoices = {}
    local owed = 0
    for _, row in ipairs(received) do
        invoices[#invoices + 1] = FormatInvoice(row, ctx.identifier)
        if row.status ~= 'disputed' then owed = owed + Remaining(row) end
    end

    local stats = MySQL.single.await([[
        SELECT
            (SELECT COALESCE(SUM(amount + tip), 0) FROM nayzeee_billing_payments WHERE payer_identifier = ? AND kind <> 'refund' AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)) AS paid30,
            (SELECT COUNT(*) FROM nayzeee_billing_invoices WHERE sender_identifier = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)) AS sent30,
            (SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND requires_collection = 1) AS toCollect
    ]], { ctx.identifier, ctx.identifier, ctx.identifier }) or {}

    local recent = MySQL.query.await([[
        SELECT * FROM nayzeee_billing_invoices
        WHERE sender_identifier = ? OR target_identifier = ?
        ORDER BY created_at DESC LIMIT 6
    ]], { ctx.identifier, ctx.identifier }) or {}
    for i, row in ipairs(recent) do recent[i] = FormatInvoice(row, ctx.identifier) end

    local company = ctx.company
    return {
        player = {
            name = ctx.name,
            job = ctx.job.label,
            jobName = ctx.job.name,
            grade = ctx.job.gradeLabel,
            cash = Bridge.GetMoney(source, 'cash'),
            bank = Bridge.GetMoney(source, 'bank'),
        },
        company = (ctx.canBill or ctx.isBoss) and PublicCompany(company) or nil,
        perms = {
            canBill = ctx.canBill,
            canPersonal = ctx.canPersonal,
            canRemote = ctx.canRemote,
            canOffline = ctx.canRemote and Config.Billing.OfflineBilling,
            isBoss = ctx.isBoss and company ~= nil,
            isAdmin = ctx.isAdmin,
            canManageCatalog = ctx.isBoss and Config.Boss.CanManageCatalog,
            canRefund = ctx.isBoss and Config.Boss.CanRefund,
            canDispute = Config.Invoices.AllowDisputes,
        },
        settings = {
            currency = Config.Currency,
            version = Shared.Version,
            defaultTaxRate = Config.DefaultTaxRate,
            maxItems = Config.Billing.MaxItems,
            maxQuantity = Config.Billing.MaxQuantity,
            maxNote = Config.Billing.MaxNoteLength,
            dueDays = company and company.dueDays or Config.Invoices.DueDays,
            customDue = Config.Invoices.AllowCustomDueDays,
            maxDueDays = Config.Invoices.MaxDueDays,
            allowPartial = Config.Payment.AllowPartial,
            minPartial = Config.Payment.MinPartialAmount,
            methods = Config.Payment.Methods,
            tips = Config.Tips.Enabled and Config.Tips.Presets or false,
            maxTip = Config.Tips.MaxPercent,
            imagePath = Inventory.ImagePath(),
            maxDistance = Config.Billing.MaxDistance,
        },
        invoices = invoices,
        recent = recent,
        stats = {
            owed = Shared.Round(owed),
            open = #invoices,
            paid30 = tonumber(stats.paid30) or 0,
            sent30 = tonumber(stats.sent30) or 0,
            toCollect = tonumber(stats.toCollect) or 0,
        },
    }
end)

-- Players near the caller (server-side coords, OneSync)
RPC('getNearby', function(source)
    local maxDist = tonumber(Config.Billing.MaxDistance) or 10.0
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target ~= source or Config.Billing.AllowSelfBilling then
            local dist = GetDistanceBetween(source, target)
            if dist <= maxDist and Bridge.GetIdentifier(target) then
                list[#list + 1] = { id = target, name = Bridge.GetName(target), distance = Shared.Round(dist, 1) }
            end
        end
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end)

RPC('searchPlayers', function(source, payload)
    if Throttle(source, 'search', 0.5) then return {} end
    local query = Shared.Sanitize(payload.query, 40)
    if query == '' then return {} end
    local ctx = GetCtx(source)
    if not ctx then return {} end

    local lower = query:lower()
    local idQuery = tonumber(query)
    local maxDist = tonumber(Config.Billing.MaxDistance)
    local results, seen = {}, {}

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        local name = Bridge.GetName(target)
        local identifier = Bridge.GetIdentifier(target)
        if identifier and (target ~= source or Config.Billing.AllowSelfBilling)
            and (target == idQuery or name:lower():find(lower, 1, true)) then
            local dist = GetDistanceBetween(source, target)
            -- Non-remote billers only see players in range
            if ctx.canRemote or not maxDist or dist <= maxDist then
                seen[identifier] = true
                results[#results + 1] = { type = 'online', id = target, name = name, distance = Shared.Round(dist, 1) }
            end
        end
    end

    if ctx.canRemote and Config.Billing.OfflineBilling and #query >= 3 then
        for _, row in ipairs(Bridge.SearchCharacters(query, 8)) do
            if not seen[row.identifier] and row.identifier ~= ctx.identifier then
                results[#results + 1] = { type = 'offline', identifier = row.identifier, name = row.name }
            end
        end
    end

    return results
end)

RPC('getItems', function(source)
    local ctx = GetCtx(source)
    if not ctx or not (ctx.isAdmin or ctx.isBoss) then return {} end
    return Inventory.GetItems()
end)

CreateThread(function()
    DB.Await()
    LoadCompanies()
    BillingReady = true
    TriggerEvent('nayzeee-billing:server:ready')
    print(('^2[NAYZEEE-BILLING]^7 v%s loaded · %d companies'):format(Shared.Version, Shared.Count(Companies)))
end)
