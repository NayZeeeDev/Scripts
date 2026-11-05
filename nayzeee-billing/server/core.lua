--[[
    NAYZEEE BILLING - Server core
    RPC plumbing, societies, permission groups, player context, shared helpers.
]]

BillingReady = false

-- ██████╗ ██████╗  ██████╗
-- ██╔══██╗██╔══██╗██╔════╝
-- ██████╔╝██████╔╝██║
-- ██╔══██╗██╔═══╝ ██║
-- ██║  ██║██║     ╚██████╗
-- ╚═╝  ╚═╝╚═╝      ╚═════╝

function Err(message) return { __err = message } end

-- Every UI action is lib.callback 'nayzeee-billing:<name>'. Permissions are always checked here.
function RPC(name, handler)
    lib.callback.register('nayzeee-billing:' .. name, function(source, payload)
        if not BillingReady then return { ok = false, error = L('error.starting', 'Billing is still starting up') } end
        local ok, result = pcall(handler, source, type(payload) == 'table' and payload or {})
        if not ok then
            print(('^1[NAYZEEE-BILLING]^7 %s: %s'):format(name, tostring(result)))
            return { ok = false, error = L('error.generic', 'Something went wrong') }
        end
        if type(result) == 'table' and result.__err then return { ok = false, error = result.__err } end
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
    local prefix = tostring(source) .. ':'
    for k in pairs(throttles) do if k:sub(1, #prefix) == prefix then throttles[k] = nil end end
end)

-- ███████╗ ██████╗  ██████╗██╗███████╗████████╗██╗███████╗███████╗
-- ██╔════╝██╔═══██╗██╔════╝██║██╔════╝╚══██╔══╝██║██╔════╝██╔════╝
-- ███████╗██║   ██║██║     ██║█████╗     ██║   ██║█████╗  ███████╗
-- ╚════██║██║   ██║██║     ██║██╔══╝     ██║   ██║██╔══╝  ╚════██║
-- ███████║╚██████╔╝╚██████╗██║███████╗   ██║   ██║███████╗███████║
-- ╚══════╝ ╚═════╝  ╚═════╝╚═╝╚══════╝   ╚═╝   ╚═╝╚══════╝╚══════╝

-- job -> society id (the key in Config.Societies, or a society listing the job in `jobs`)
function SocietyOfJob(job)
    if not job then return nil end
    if Config.Societies[job] then return job end
    for id, s in pairs(Config.Societies) do
        if type(s.jobs) == 'table' and Shared.Contains(s.jobs, job) then return id end
    end
    return nil
end

function SocietyLabel(id)
    local s = Config.Societies[id]
    return s and s.label or Framework.GetJobLabel(id) or id
end

function SocietyPrefix(id)
    local s = Config.Societies[id]
    local raw = s and (s.short or id) or Config.Invoices.PersonalPrefix or 'INV'
    local p = tostring(raw):upper():gsub('[^%w]', ''):sub(1, 6)
    return p ~= '' and p or 'INV'
end

function PublicSocieties()
    local list = {}
    for id, s in pairs(Config.Societies) do
        list[#list + 1] = { id = id, label = s.label, short = s.short or id:upper(), color = s.color, billable = s.billable ~= false }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- ██████╗ ███████╗██████╗ ███╗   ███╗██╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██╔════╝██╔══██╗████╗ ████║██║██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
-- ██████╔╝█████╗  ██████╔╝██╔████╔██║██║███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
-- ██╔═══╝ ██╔══╝  ██╔══██╗██║╚██╔╝██║██║╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
-- ██║     ███████╗██║  ██║██║ ╚═╝ ██║██║███████║███████║██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

local Groups = {}   -- [society] = { list = { group... }, byId = {} }
local Members = {}  -- [society] = { [identifier] = groupId }

local function decodePerms(raw)
    local ok, t = pcall(json.decode, raw or '{}')
    return ok and type(t) == 'table' and t or {}
end

function LoadGroups(society)
    if Groups[society] then return Groups[society] end
    local rows = MySQL.query.await('SELECT * FROM nayzeee_billing_groups WHERE society = ? ORDER BY sort ASC', { society }) or {}
    if #rows == 0 then
        for i, g in ipairs(Config.PermissionGroups) do
            MySQL.insert.await([[INSERT IGNORE INTO nayzeee_billing_groups (society, group_id, label, access, icon, color, perms, sort)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)]], { society, g.id, g.label, g.access, g.icon, g.color, json.encode(g.perms), i })
        end
        rows = MySQL.query.await('SELECT * FROM nayzeee_billing_groups WHERE society = ? ORDER BY sort ASC', { society }) or {}
    end
    local data = { list = {}, byId = {} }
    for _, r in ipairs(rows) do
        local g = { id = r.group_id, label = r.label, access = r.access, icon = r.icon, color = r.color, perms = decodePerms(r.perms), sort = r.sort }
        data.list[#data.list + 1] = g
        data.byId[g.id] = g
    end
    Groups[society] = data
    return data
end

function LoadMembers(society)
    if Members[society] then return Members[society] end
    local map = {}
    for _, r in ipairs(MySQL.query.await('SELECT identifier, group_id, grade FROM nayzeee_billing_members WHERE society = ?', { society }) or {}) do
        map[r.identifier] = { group = r.group_id, grade = tonumber(r.grade) }
    end
    Members[society] = map
    return map
end

function InvalidateGroups(society) Groups[society] = nil end
function InvalidateMembers(society) Members[society] = nil end

function DefaultGroupFor(society, grade, isBoss)
    local s = Config.Societies[society] or {}
    local d = Config.DefaultGroups
    if isBoss or grade >= (s.manageGrade or 99) then return d.manage end
    if grade >= (s.sendGrade or 0) then return d.send end
    return d.other
end

function IsManagerGrade(society, grade, isBoss)
    return isBoss == true or (tonumber(grade) or 0) >= ((Config.Societies[society] or {}).manageGrade or 99)
end

-- Assigned group id, or nil when it doesn't apply: bosses always get the manager group,
-- and an assignment lapses when the employee's grade changes (promoted, demoted, fired and rehired)
function AssignedGroup(society, identifier, grade, isBoss)
    if IsManagerGrade(society, grade, isBoss) then return nil end
    local a = LoadMembers(society)[identifier]
    if not a then return nil end
    if a.grade ~= nil and a.grade ~= (tonumber(grade) or 0) then return nil end
    return a.group
end

-- perms table + group for an identifier in a society
function MemberPerms(society, identifier, grade, isBoss)
    local groups = LoadGroups(society)
    local assigned = AssignedGroup(society, identifier, grade, isBoss)
    local group = assigned and groups.byId[assigned]
    if not group then group = groups.byId[DefaultGroupFor(society, grade or 0, isBoss)] end
    return group and group.perms or {}, group
end

--  ██████╗ ██████╗ ███╗   ██╗████████╗███████╗██╗  ██╗████████╗
-- ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔════╝╚██╗██╔╝╚══██╔══╝
-- ██║     ██║   ██║██╔██╗ ██║   ██║   █████╗   ╚███╔╝    ██║
-- ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══╝   ██╔██╗    ██║
-- ╚██████╗╚██████╔╝██║ ╚████║   ██║   ███████╗██╔╝ ██╗   ██║
--  ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝   ╚═╝

function IsAdmin(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if Config.Admin.Ace and IsPlayerAceAllowed(source, Config.Admin.Ace) then return true end
    return Framework.IsAdminGroup(source) == true
end

-- Everything about a player's access in one table
function GetCtx(source)
    local identifier = Framework.GetIdentifier(source)
    if not identifier then return nil end
    local job = Framework.GetJob(source) or { name = 'unemployed', grade = 0 }
    local society = SocietyOfJob(job.name)
    local ctx = {
        source = source, identifier = identifier, name = Framework.GetName(source),
        job = job, society = society, perms = {}, group = nil, isAdmin = IsAdmin(source),
    }
    if society then
        ctx.perms, ctx.group = MemberPerms(society, identifier, job.grade, job.isBoss)
    end
    return ctx
end

function Can(ctx, perm, society)
    if not ctx then return false end
    if society and ctx.society ~= society then return false end
    return ctx.society ~= nil and ctx.perms[perm] == true
end

-- ██╗  ██╗███████╗██╗     ██████╗ ███████╗██████╗ ███████╗
-- ██║  ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗██╔════╝
-- ███████║█████╗  ██║     ██████╔╝█████╗  ██████╔╝███████╗
-- ██╔══██║██╔══╝  ██║     ██╔═══╝ ██╔══╝  ██╔══██╗╚════██║
-- ██║  ██║███████╗███████╗██║     ███████╗██║  ██║███████║
-- ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝

function Distance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return 9999.0 end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

function DistanceTo(source, c)
    local ped = GetPlayerPed(source)
    if ped == 0 then return 9999.0 end
    return #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z))
end

function Notify(source, title, message, kind)
    if source and source > 0 then
        TriggerClientEvent('nayzeee-billing:client:notify', source, { title = title, message = message, type = kind or 'info' })
    end
end

-- Notify every online member of a society holding a permission
function NotifySociety(society, perm, title, message, kind)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ctx = GetCtx(src)
        if ctx and ctx.society == society and ctx.perms[perm] then Notify(src, title, message, kind) end
    end
end

function Refresh(source)
    if source then TriggerClientEvent('nayzeee-billing:client:refresh', source) end
end

function Remaining(row)
    return Shared.Round((tonumber(row.total) or 0) + (tonumber(row.late_fee) or 0) - (tonumber(row.amount_paid) or 0))
end

function GetInvoiceRow(ref)
    if type(ref) == 'number' then
        return MySQL.single.await('SELECT *, TIMESTAMPDIFF(MINUTE, created_at, NOW()) AS age_minutes FROM nayzeee_billing_invoices WHERE id = ?', { ref })
    end
    if type(ref) ~= 'string' or #ref > 24 then return nil end
    return MySQL.single.await('SELECT *, TIMESTAMPDIFF(MINUTE, created_at, NOW()) AS age_minutes FROM nayzeee_billing_invoices WHERE invoice_id = ?', { ref:upper() })
end

local function decodeItems(raw)
    if type(raw) ~= 'string' then return raw or {} end
    local ok, items = pcall(json.decode, raw)
    items = ok and items or {}
    -- older items used price instead of amount
    for _, it in ipairs(items) do
        if it.amount == nil and it.price ~= nil then it.amount = it.price end
        if it.label == nil and it.name ~= nil then it.label = it.name end
    end
    return items
end

-- viewer: { identifier, society } decides the direction tag
function FormatInvoice(row, viewer)
    local direction
    if viewer then
        if row.recipient_type == 'society' and viewer.society and row.target_society == viewer.society then direction = 'received'
        elseif row.company_id and viewer.society and row.company_id == viewer.society then direction = 'sent'
        elseif row.target_identifier == viewer.identifier then direction = 'received'
        elseif row.sender_identifier == viewer.identifier then direction = 'sent' end
    end
    local senderSociety = row.company_id
    return {
        id = row.id,
        ref = row.invoice_id,
        senderType = senderSociety and 'society' or 'personal',
        senderSociety = senderSociety,
        sender = senderSociety and (row.company_name or SocietyLabel(senderSociety)) or row.sender_name,
        senderName = row.sender_name,
        recipientType = row.recipient_type or 'citizen',
        recipientSociety = row.target_society,
        recipient = row.target_name,
        direction = direction,
        reason = row.reason or (decodeItems(row.items)[1] or {}).label,
        items = decodeItems(row.items),
        notes = row.notes,
        subtotal = tonumber(row.subtotal) or 0,
        vatRate = tonumber(row.vat_rate) or 0,
        vat = tonumber(row.tax) or 0,
        discount = tonumber(row.discount) or 0,
        total = tonumber(row.total) or 0,
        lateFee = tonumber(row.late_fee) or 0,
        amountPaid = tonumber(row.amount_paid) or 0,
        tip = tonumber(row.tip) or 0,
        remaining = math.max(0, Remaining(row)),
        status = row.status,
        method = row.payment_method,
        paidBy = row.paid_by_name,
        cancelReason = row.cancel_reason,
        disputeReason = row.dispute_reason,
        createdAt = row.created_at,
        dueDate = row.due_date,
        paidAt = row.paid_at,
        tipsAllowed = Config.Tips.Enabled and senderSociety ~= nil
            and (Config.Societies[senderSociety] or {}).allowTips ~= false,
    }
end

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

-- Writes the Activity log row + sends to the logger bridge
function Log(source, action, data, society)
    data = data or {}
    local name = (source and source > 0) and Framework.GetName(source) or (data.by or 'System')
    local identifier = (source and source > 0) and Framework.GetIdentifier(source) or data.byIdentifier
    MySQL.insert('INSERT INTO nayzeee_billing_logs (player, identifier, company_id, action, data) VALUES (?, ?, ?, ?, ?)',
        { name, identifier, society, action, json.encode(data) })
    Logger.Send(action, source, data, society and (Config.Societies[society] or {}).webhook or nil)
end

-- ██████╗  █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗████████╗███████╗
-- ██╔══██╗██╔══██╗╚██╗ ██╔╝██╔═══██╗██║   ██║╚══██╔══╝██╔════╝
-- ██████╔╝███████║ ╚████╔╝ ██║   ██║██║   ██║   ██║   ███████╗
-- ██╔═══╝ ██╔══██║  ╚██╔╝  ██║   ██║██║   ██║   ██║   ╚════██║
-- ██║     ██║  ██║   ██║   ╚██████╔╝╚██████╔╝   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝

-- Bank deposit to a character (online or offline). Falls back to a pending payout on failure
function Payout(identifier, amount, reason, invoiceRef, requiresCollection)
    amount = Shared.Round(amount)
    if not identifier or amount <= 0 or tostring(identifier):sub(1, 7) == 'system:' then return end
    if not requiresCollection and Money.DepositTo(identifier, amount, reason) then return true end
    MySQL.insert.await([[INSERT INTO nayzeee_billing_pending_payouts (identifier, amount, invoice_id, payment_method, requires_collection, reason)
        VALUES (?, ?, ?, ?, ?, ?)]], { identifier, amount, invoiceRef, requiresCollection and 'cash' or 'bank', requiresCollection and 1 or 0, reason })
    return false
end

-- Society money that couldn't be credited right now; payments.lua retries it every few minutes
function QueueSociety(society, amount, reason, invoiceRef)
    amount = Shared.Round(amount)
    if not society or amount <= 0 then return end
    MySQL.insert.await([[INSERT INTO nayzeee_billing_pending_payouts (identifier, amount, invoice_id, payment_method, requires_collection, reason)
        VALUES (?, ?, ?, 'society', 0, ?)]], { 'society:' .. society, amount, invoiceRef or '', reason })
end

--  ██████╗ ██████╗ ███╗   ██╗████████╗███████╗██╗  ██╗████████╗    ██████╗ ██████╗  ██████╗
-- ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔════╝╚██╗██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██╔════╝
-- ██║     ██║   ██║██╔██╗ ██║   ██║   █████╗   ╚███╔╝    ██║       ██████╔╝██████╔╝██║
-- ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══╝   ██╔██╗    ██║       ██╔══██╗██╔═══╝ ██║
-- ╚██████╗╚██████╔╝██║ ╚████║   ██║   ███████╗██╔╝ ██╗   ██║       ██║  ██║██║     ╚██████╗
--  ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝   ╚═╝       ╚═╝  ╚═╝╚═╝      ╚═════╝

RPC('getContext', function(source)
    local ctx = GetCtx(source)
    if not ctx then return Err(L('error.not_loaded', 'Character not loaded')) end

    local society
    if ctx.society then
        local s = Config.Societies[ctx.society]
        society = {
            id = ctx.society, label = s.label, short = s.short or ctx.society:upper(), color = s.color,
            perms = ctx.perms, group = ctx.group and { id = ctx.group.id, label = ctx.group.label } or nil,
            balance = ctx.perms.overview and Banking.SocietyBalance(ctx.society) or nil,
            vatRate = Shared.VatRate(ctx.society), allowCustom = s.allowCustom ~= false,
            dueDays = s.dueDays or Config.Invoices.DueDays,
        }
    end

    local toCollect = MySQL.scalar.await('SELECT COALESCE(SUM(amount), 0) FROM nayzeee_billing_pending_payouts WHERE identifier = ? AND requires_collection = 1',
        { ctx.identifier })

    return {
        player = {
            name = ctx.name, job = ctx.job.label, grade = ctx.job.gradeLabel,
            cash = Money.Get(source, 'cash'), bank = Money.Get(source, 'bank'),
            toCollect = tonumber(toCollect) or 0,
        },
        society = society,
        isAdmin = ctx.isAdmin,
        societies = PublicSocieties(),
        settings = {
            version = Shared.Version, currency = Config.Currency, currencyPosition = Config.CurrencyPosition,
            personalEnabled = Config.Personal.Enabled, personalCustom = Config.Personal.AllowCustomItems,
            personalSocietyRecipients = Config.Personal.AllowSocietyRecipients,
            personalVat = Shared.VatRate(nil, true),
            dueDays = Config.Invoices.DueDays, customDue = Config.Invoices.AllowCustomDueDays, maxDueDays = Config.Invoices.MaxDueDays,
            maxItems = Config.Invoices.MaxItems, maxQuantity = Config.Invoices.MaxQuantity, maxNote = Config.Invoices.MaxNoteLength,
            methods = Config.Payment.Methods, allowPartial = Config.Payment.AllowPartial, minPartial = Config.Payment.MinPartialAmount,
            payByReference = Config.Payment.PayByReference, disputes = Config.Invoices.AllowDisputes,
            tips = Config.Tips.Enabled and Config.Tips.Presets or false, maxTip = Config.Tips.MaxPercent,
            print = Config.Items.AllowPrint and Config.Items.Invoice.Enabled,
            pageSize = Config.UI.PageSize, banking = Banking.name,
            adminDelete = Config.Admin.AllowDelete, adminClear = Config.Admin.AllowClearIdentifier,
        },
    }
end)

-- Nearby characters (server-side coords)
RPC('getNearby', function(source)
    local max = tonumber(Config.Invoices.MaxDistance) or 10.0
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local t = tonumber(id)
        if t ~= source then
            local d = Distance(source, t)
            if d <= max and Framework.GetIdentifier(t) then
                list[#list + 1] = { id = t, name = Framework.GetName(t), distance = Shared.Round(d, 1) }
            end
        end
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end)

CreateThread(function()
    DB.Await()
    if not Framework then
        print('^1[NAYZEEE-BILLING]^7 No framework bridge loaded - check Config.Framework')
        return
    end
    BillingReady = true
    TriggerEvent('nayzeee-billing:server:ready')
    print(('^2[NAYZEEE-BILLING]^7 v%s ready · %s · %d societies'):format(Shared.Version, Framework.Name, Shared.Count(Config.Societies)))
end)
