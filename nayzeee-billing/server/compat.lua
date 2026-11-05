--[[
    NAYZEEE BILLING - Compatibility & imports

    esx_billing:  scripts that trigger 'esx_billing:sendBill' or call the esx_billing:getBills / payBill
                  callbacks keep working (only when esx_billing itself isn't running).
    Imports:      `billingimport esx_billing | okokBilling | qb-phone` in the server console (or as an admin).
]]

-- ███████╗███████╗██╗  ██╗    ██████╗ ██╗██╗     ██╗     ██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔════╝╚██╗██╔╝    ██╔══██╗██║██║     ██║     ██║████╗  ██║██╔════╝
-- █████╗  ███████╗ ╚███╔╝     ██████╔╝██║██║     ██║     ██║██╔██╗ ██║██║  ███╗
-- ██╔══╝  ╚════██║ ██╔██╗     ██╔══██╗██║██║     ██║     ██║██║╚██╗██║██║   ██║
-- ███████╗███████║██╔╝ ██╗    ██████╔╝██║███████╗███████╗██║██║ ╚████║╚██████╔╝
-- ╚══════╝╚══════╝╚═╝  ╚═╝    ╚═════╝ ╚═╝╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

local function stripSociety(name)
    if type(name) ~= 'string' then return nil end
    local prefix = Config.Banking.EsxSocietyPrefix or 'society_'
    if name:sub(1, #prefix) == prefix then name = name:sub(#prefix + 1) end
    return SocietyOfJob(name)
end

AddEventHandler('nayzeee-billing:server:ready', function()
    if not Config.Compat.EsxBilling or GetResourceState('esx_billing') == 'started' then return end

    RegisterNetEvent('esx_billing:sendBill', function(playerId, sharedAccountName, label, amount)
        local source = source
        local ctx = GetCtx(source)
        local target = tonumber(playerId)
        if not ctx or not target or not Framework.GetIdentifier(target) or target == source then return end
        if Throttle(source, 'create', Config.Invoices.Cooldown) then return end
        local max = tonumber(Config.Invoices.MaxDistance)
        if max and Distance(source, target) > max then return end

        local society = stripSociety(sharedAccountName)
        if society and not Can(ctx, 'create', society) then return end
        if not society and not (Config.Personal.Enabled and Config.Personal.AllowCustomItems) then return end

        local value = Shared.Round(amount)
        local text = Shared.Sanitize(label, 60)
        if value <= 0 or value > Config.Invoices.MaxAmount or text == '' then return end

        CreateInvoice({
            source = source, senderIdentifier = ctx.identifier, senderName = ctx.name, senderJob = society and ctx.job.name or nil,
            society = society, recipientType = 'citizen', targetIdentifier = Framework.GetIdentifier(target), targetSource = target,
            targetName = Framework.GetName(target), items = { { label = text, amount = value, quantity = 1, custom = true } },
        })
    end)

    if Framework.Name == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        ESX.RegisterServerCallback('esx_billing:getBills', function(source, cb)
            local identifier = Framework.GetIdentifier(source)
            local rows = MySQL.query.await([[SELECT id, reason, total, late_fee, amount_paid FROM nayzeee_billing_invoices
                WHERE target_identifier = ? AND status IN ('pending','partial','overdue') ORDER BY created_at DESC]], { identifier }) or {}
            local bills = {}
            for _, r in ipairs(rows) do bills[#bills + 1] = { id = r.id, label = r.reason, amount = Remaining(r) } end
            cb(bills)
        end)
        ESX.RegisterServerCallback('esx_billing:payBill', function(source, cb, billId)
            -- esx_billing only ever paid your own bills
            local row = GetInvoiceRow(tonumber(billId) or 0)
            if not row or row.target_identifier ~= Framework.GetIdentifier(source) then return cb(false) end
            local result = ProcessPayment({ source = source, id = row.id, method = 'bank' })
            cb(result ~= nil)
        end)
    end
end)

-- ██╗███╗   ███╗██████╗  ██████╗ ██████╗ ████████╗
-- ██║████╗ ████║██╔══██╗██╔═══██╗██╔══██╗╚══██╔══╝
-- ██║██╔████╔██║██████╔╝██║   ██║██████╔╝   ██║
-- ██║██║╚██╔╝██║██╔═══╝ ██║   ██║██╔══██╗   ██║
-- ██║██║ ╚═╝ ██║██║     ╚██████╔╝██║  ██║   ██║
-- ╚═╝╚═╝     ╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝

local function imported(sourceName, id)
    return MySQL.scalar.await('SELECT 1 FROM nayzeee_billing_invoices WHERE import_source = ? AND import_id = ?', { sourceName, tostring(id) }) ~= nil
end

local function insert(sourceName, d)
    if imported(sourceName, d.importId) then return false end
    local total = Shared.Round(d.amount)
    if total <= 0 then return false end
    local status = d.status or 'pending'
    MySQL.insert.await([[INSERT INTO nayzeee_billing_invoices
        (invoice_id, company_id, sender_identifier, sender_name, sender_job, recipient_type, target_identifier, target_name, company_name,
         reason, items, notes, subtotal, vat_rate, tax, total, amount_paid, status, created_at, paid_at, due_date, import_source, import_id)
        VALUES (?, ?, ?, ?, ?, 'citizen', ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, COALESCE(?, NOW()), ?, COALESCE(?, DATE_ADD(NOW(), INTERVAL ? DAY)), ?, ?)]], {
        NewReference(d.society), d.society, d.senderIdentifier or ('import:' .. sourceName), d.senderName or 'Imported', d.society,
        d.targetIdentifier, d.targetName or d.targetIdentifier, d.society and SocietyLabel(d.society) or 'Personal',
        Shared.Sanitize(d.reason, 120), json.encode({ { label = Shared.Sanitize(d.reason, 60), amount = total, quantity = 1 } }),
        d.notes, total, total, status == 'paid' and total or 0, status, d.createdAt, d.paidAt, d.dueAt, Config.Invoices.DueDays,
        sourceName, tostring(d.importId),
    })
    return true
end

local Importers = {}

Importers['esx_billing'] = function()
    if not DB.TableExists('billing') then return nil, 'Table `billing` not found' end
    local n = 0
    for _, r in ipairs(MySQL.query.await('SELECT * FROM billing') or {}) do
        local society = r.target_type == 'society' and stripSociety(r.target) or nil
        if insert('esx_billing', {
            importId = r.id, society = society, senderIdentifier = r.sender, senderName = Framework.GetCharacterName(r.sender) or r.sender,
            targetIdentifier = r.identifier, targetName = Framework.GetCharacterName(r.identifier), reason = r.label, amount = r.amount,
        }) then n = n + 1 end
    end
    return n
end

Importers['okokBilling'] = function()
    local tbl = DB.TableExists('okokbilling') and 'okokbilling' or (DB.TableExists('okokBilling') and 'okokBilling' or nil)
    if not tbl then return nil, 'Table `okokbilling` not found' end
    local cols = DB.Columns(tbl)
    local function pick(r, ...) for _, c in ipairs({ ... }) do if cols[c] and r[c] ~= nil then return r[c] end end end
    local n = 0
    for _, r in ipairs(MySQL.query.await(('SELECT * FROM `%s`'):format(tbl)) or {}) do
        local raw = tostring(pick(r, 'status') or 'unpaid'):lower()
        local status = (raw == 'paid' or raw == 'autopaid') and 'paid' or (raw:find('cancel') and 'cancelled' or 'pending')
        local society = stripSociety(pick(r, 'society'))
        if insert('okokBilling', {
            importId = pick(r, 'id', 'ref_id'), society = society,
            senderIdentifier = pick(r, 'author_identifier'), senderName = pick(r, 'author_name'),
            targetIdentifier = pick(r, 'receiver_identifier'), targetName = pick(r, 'receiver_name'),
            reason = pick(r, 'item', 'notes') or 'Invoice', notes = pick(r, 'notes'),
            amount = pick(r, 'invoice_value', 'amount'), status = status,
            createdAt = pick(r, 'sent_date'), paidAt = status == 'paid' and pick(r, 'paid_date') or nil, dueAt = pick(r, 'limit_pay_date'),
        }) then n = n + 1 end
    end
    return n
end

Importers['qb-phone'] = function()
    if not DB.TableExists('phone_invoices') then return nil, 'Table `phone_invoices` not found' end
    local n = 0
    for _, r in ipairs(MySQL.query.await('SELECT * FROM phone_invoices') or {}) do
        local society = SocietyOfJob(r.society)
        if insert('qb-phone', {
            importId = r.id, society = society, senderIdentifier = r.sendercitizenid, senderName = r.sender,
            targetIdentifier = r.citizenid, targetName = Framework.GetCharacterName(r.citizenid),
            reason = society and SocietyLabel(society) or (r.society or 'Invoice'), amount = r.amount,
        }) then n = n + 1 end
    end
    return n
end

RegisterCommand('billingimport', function(source, args)
    if source > 0 and not IsAdmin(source) then return end
    local function reply(msg)
        if source > 0 then Notify(source, 'Billing import', msg, 'info') else Console.log('info', 'Import: %s', msg) end
    end
    if not Config.Import.Enabled then return reply('Imports are disabled (Config.Import.Enabled)') end
    if not BillingReady then return reply('Billing is still starting up') end
    local system = args[1]
    local importer = Importers[system]
    if not importer then return reply('Usage: billingimport esx_billing | okokBilling | qb-phone') end
    CreateThread(function()
        local ok, n, err = pcall(importer)
        if not ok then return reply('Import failed: ' .. tostring(n)) end
        if not n then return reply('Import failed: ' .. tostring(err)) end
        reply(('Imported %d invoice(s) from %s'):format(n, system))
        Log(source > 0 and source or nil, 'admin_import', { system = system, imported = n })
    end)
end, false)
