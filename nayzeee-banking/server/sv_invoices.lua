if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  OTHER BILLING SCRIPTS
--
--  Some servers keep a billing script that holds its own invoices
--  (okokBilling, esx_billing, Quasar, Wasabi, BCS, RX, TGG, Bablo).
--  While one is running, its unpaid invoices show in the Bills tab
--  beside this bank's own, and can be paid from here.
--
--  Each adapter checks on start that the tables, columns or exports it
--  reads are really there. Anything missing turns that adapter off with
--  one console line saying what it looked for. A version that changed
--  its layout is left alone instead of guessed at.
--
--  Paying goes one of two ways:
--    export  the billing script's own pay export is called, so its
--            commission, VAT and society payout all happen as usual.
--            The money leaves the framework's bank figure, which is
--            this bank's personal account.
--    bank    this bank moves the money itself, from any account the
--            player can spend from, to the company's account here, and
--            marks the invoice paid in that script's table.
--
--  Open to edit (escrow_ignore). Config: Config.Bridge.external.
-- ═══════════════════════════════════════════════════════════
local CFG = (Config.Bridge and Config.Bridge.external) or {}

local ADAPTERS = {}   -- [key] = adapter
local live     = {}   -- [key] = true once its checks passed
local warned   = {}

local function note(key, msg)
    if warned[key .. msg] then return end
    warned[key .. msg] = true
    print(('^3[nayzeee-banking]^7 %s: %s'):format(key, msg))
end

local function opts(key)
    local o = CFG[key]
    if o == nil or o == false then return nil end
    return type(o) == 'table' and o or {}
end

local function running(res)
    return GetResourceState(res) == 'started'
end

--- Columns present on a table, as a set. Empty when the table is missing.
local function columns(tbl)
    local rows = MySQL.query.await([[
        SELECT COLUMN_NAME AS c FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
    ]], { tbl }) or {}
    local set = {}
    for _, r in ipairs(rows) do set[r.c] = true end
    return set
end

local function needColumns(key, tbl, list)
    if type(tbl) ~= 'string' or not tbl:match('^[%w_]+$') then
        note(key, ('table name %q is not usable'):format(tostring(tbl)))
        return nil
    end
    local have = columns(tbl)
    if not next(have) then note(key, ('table `%s` not found, adapter off'):format(tbl)) return nil end
    local missing = {}
    for _, c in ipairs(list) do if not have[c] then missing[#missing + 1] = c end end
    if #missing > 0 then
        note(key, ('table `%s` has no %s; this version is not supported yet, adapter off')
            :format(tbl, table.concat(missing, ', ')))
        return nil
    end
    return have
end

--- 'society_police' and 'police' are the same company.
local function bareJob(job)
    if type(job) ~= 'string' or job == '' then return nil end
    return (job:gsub('^society_', ''))
end

local function companyLabel(job, fallback)
    job = bareJob(job)
    if not job then return fallback or 'Invoice' end
    local soc = Bank.getSociety(job)
    if soc then return soc.label end
    local jobs = ESX.GetJobs and ESX.GetJobs() or {}
    return (jobs[job] and jobs[job].label) or fallback or job
end

--- '2026-04-24 18:00:00' → time, or nil
local function parseDate(s)
    local y, m, d, h, mi = tostring(s or ''):match('^(%d+)-(%d+)-(%d+)[ T](%d+):(%d+)')
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
end

--- The first of these fields that is set, or nil (never nothing: tonumber() refuses that).
local function pick(t, ...)
    for _, k in ipairs({ ... }) do
        if t[k] ~= nil and t[k] ~= '' then return t[k] end
    end
    return nil
end

--- Call an export without letting a missing or renamed one throw.
local function call(key, res, name, ...)
    local args = table.pack(...)
    local ok, a, b = pcall(function() return exports[res][name](exports[res], table.unpack(args, 1, args.n)) end)
    if not ok then
        note(key, ('export %s:%s failed (%s)'):format(res, name, tostring(a):sub(1, 120)))
        return nil, nil, false
    end
    return a, b, true
end

-- ═══════════════════════════════════════════════════════════
--  MOVING THE MONEY OURSELVES ('bank' mode)
-- ═══════════════════════════════════════════════════════════

--- Take the bill from the player's account and hand it to whoever it is owed.
--- `claim()` marks the invoice paid in its own table and returns true only for
--- the one payment that got it; `unclaim()` puts it back. Same order as this
--- bank's own bills: claim, then debit, then credit, unwinding on any failure.
local function settle(src, accountId, bill, claim, unclaim)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return false, 'Player not found.' end

    local acc, perms = Bank.access(src, accountId)
    if not acc then return false, 'You cannot use that account.' end
    if not perms.withdraw then return false, 'You cannot spend from that account.' end

    -- where the money goes: the company's account here, or the person who sent it
    local to
    if bill.job then
        local soc = Bank.getSociety(bill.job)
        if not soc then return false, ('%s has no account at this bank.'):format(bill.issuer) end
        to = soc.id
    elseif bill.payee then
        local p = Bank.getPersonal(bill.payee)
        to = p and p.id
    end

    if not claim() then return false, 'This invoice was just paid or changed.' end

    local label = ('%s · %s'):format(bill.issuer, bill.reason):sub(1, 90)
    local ok = Bank.debit(accountId, bill.amount, {
        category = 'bill', label = label, actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
    })
    if not ok then unclaim() return false, 'Not enough in that account.' end

    if to then
        local paid = Bank.credit(to, bill.amount, {
            category = 'bill', label = ('Bill paid · %s'):format(bill.reason):sub(1, 90),
            actor = xPlayer.identifier, actorName = Bank.fullName(xPlayer)
        })
        if not paid then
            Bank.credit(accountId, bill.amount, { category = 'bill', label = 'Bill payment returned' })
            unclaim()
            return false, 'The company is not taking payments right now.'
        end
    end

    Bank.log('bills', 'Invoice paid', ('**%s%s** to %s · %s (%s)')
        :format(Config.Currency, bill.amount, bill.issuer, bill.reason, bill.source))
    return true, ('Paid %s%s.'):format(Config.Currency, bill.amount)
end

--- Pay through the billing script's own export. The money comes out of the
--- framework's bank figure, which mirrors the personal account, so the ledger
--- line is labelled before the call and the mirror picks it up straight away.
local function viaExport(src, bill, fn)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return false, 'Player not found.' end
    local acc = Bank.getPersonal(xPlayer.identifier)
    if not acc or acc.balance < bill.amount then return false, 'Not enough in your personal account.' end

    if Bank.expectExternal then
        Bank.expectExternal(xPlayer.identifier, bill.amount, ('%s · %s'):format(bill.issuer, bill.reason):sub(1, 90))
    end
    local ok = fn(xPlayer)
    if Bank.syncNow then Bank.syncNow(xPlayer.identifier) end
    if not ok then return false, ('%s did not take the payment.'):format(bill.source) end

    Bank.log('bills', 'Invoice paid', ('**%s%s** to %s · %s (%s)')
        :format(Config.Currency, bill.amount, bill.issuer, bill.reason, bill.source))
    return true, ('Paid %s%s.'):format(Config.Currency, bill.amount)
end

-- ═══════════════════════════════════════════════════════════
--  esx_billing
--  Paid bills are deleted from `billing`; society bills go to
--  society_<job>, the rest to the player who sent them.
-- ═══════════════════════════════════════════════════════════
ADAPTERS.esx_billing = {
    resource = 'esx_billing', label = 'ESX Billing', mode = 'bank',

    check = function(self, o)
        self.tbl = o.table or 'billing'
        return needColumns('esx_billing', self.tbl, { 'id', 'identifier', 'sender', 'target_type', 'target', 'label', 'amount' })
    end,

    list = function(self, identifier)
        local rows = MySQL.query.await(('SELECT id, sender, target_type, target, label, amount FROM `%s` WHERE identifier = ? ORDER BY id DESC LIMIT 25')
            :format(self.tbl), { identifier }) or {}
        local out = {}
        for _, r in ipairs(rows) do
            local society = r.target_type == 'society'
            out[#out + 1] = {
                ref = r.id, amount = tonumber(r.amount) or 0, reason = r.label,
                issuer = society and companyLabel(r.target) or 'Private invoice',
                job = society and bareJob(r.target) or nil,
                payee = not society and r.target or nil,
            }
        end
        return out
    end,

    pay = function(self, src, bill, accountId)
        local row = MySQL.single.await(('SELECT * FROM `%s` WHERE id = ?'):format(self.tbl), { bill.ref })
        local ok, msg = settle(src, accountId, bill,
            function()
                return (MySQL.update.await(('DELETE FROM `%s` WHERE id = ? AND identifier = ? AND amount = ?'):format(self.tbl),
                    { bill.ref, bill.identifier, bill.amount }) or 0) == 1
            end,
            function()
                if not row then return end
                MySQL.insert.await(('INSERT INTO `%s` (id, identifier, sender, target_type, target, label, amount) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(self.tbl),
                    { row.id, row.identifier, row.sender, row.target_type, row.target, row.label, row.amount })
            end)
        if ok then
            -- what esx_billing itself fires, for anything listening
            TriggerEvent('esx_billing:paidBill', src, bill.ref)
            TriggerClientEvent('esx_billing:paidBill', src, bill.ref)
        end
        return ok, msg
    end,
}

-- ═══════════════════════════════════════════════════════════
--  okokBilling / Quasar Billing
--  The same invoice table shape: receiver_identifier, society,
--  invoice_value, fees_amount, status 'unpaid' / 'paid'.
-- ═══════════════════════════════════════════════════════════
local UNPAID = { unpaid = true, overdue = true, pending = true }

local function invoiceTable(key, resource, label, defaultTable)
    return {
        resource = resource, label = label, mode = 'bank',

        check = function(self, o)
            self.tbl = o.table or defaultTable
            self.cols = needColumns(key, self.tbl, { 'id', 'receiver_identifier', 'society', 'item', 'invoice_value', 'status' })
            return self.cols
        end,

        list = function(self, identifier)
            local c = self.cols
            local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE receiver_identifier = ? ORDER BY id DESC LIMIT 40')
                :format(self.tbl), { identifier }) or {}
            local out = {}
            for _, r in ipairs(rows) do
                if UNPAID[tostring(r.status):lower()] then
                    local fees = c.fees_amount and tonumber(r.fees_amount) or 0
                    local job = bareJob(r.society)
                    out[#out + 1] = {
                        ref = r.id, status = r.status,
                        amount = (tonumber(r.invoice_value) or 0) + fees,
                        reason = fees > 0 and ('%s (incl. %s%s fees)'):format(r.item, Config.Currency, fees) or r.item,
                        issuer = job and companyLabel(job, r.society_name) or (r.author_name or 'Private invoice'),
                        sender = r.author_name,
                        job = job,
                        payee = not job and r.author_identifier or nil,
                        overdue = tostring(r.status):lower() == 'overdue',
                    }
                end
            end
            return out
        end,

        pay = function(self, src, bill, accountId)
            local paidDate = self.cols.paid_date and ', paid_date = ?' or ''
            return settle(src, accountId, bill,
                function()
                    local args = { 'paid' }
                    if paidDate ~= '' then args[#args + 1] = os.date('%Y-%m-%d %H:%M:%S') end
                    args[#args + 1] = bill.ref
                    args[#args + 1] = bill.identifier
                    args[#args + 1] = bill.status
                    return (MySQL.update.await(('UPDATE `%s` SET status = ?%s WHERE id = ? AND receiver_identifier = ? AND status = ?')
                        :format(self.tbl, paidDate), args) or 0) == 1
                end,
                function()
                    MySQL.update.await(('UPDATE `%s` SET status = ? WHERE id = ?'):format(self.tbl), { bill.status, bill.ref })
                end)
        end,
    }
end

local qsTable = invoiceTable('qs-billing', 'qs-billing', 'Quasar Billing', 'qs_billing')

-- ═══════════════════════════════════════════════════════════
--  okokBilling
--  V3: getInvoices(serverId) and payReference(serverId, ref), so
--  okok's own VAT, commission and society payout all apply.
--  Older versions have no such exports; their table is read instead
--  and this bank moves the money, as for Quasar above.
-- ═══════════════════════════════════════════════════════════
local okokTable = invoiceTable('okokBilling', 'okokBilling', 'okokBilling', 'okokbilling')

local OKOK_OPEN = { pending = true, unpaid = true, overdue = true, late = true }

ADAPTERS.okokBilling = {
    resource = 'okokBilling', label = 'okokBilling', mode = 'export',

    check = function(self, o)
        self.o, self.legacy, self.mode = o, nil, 'export'
        return true
    end,

    --- No getInvoices export: an okokBilling from before V3.
    fallBack = function(self)
        note('okokBilling', 'no getInvoices export (a version before V3?), reading its table instead')
        self.legacy = okokTable.check(okokTable, self.o) and true or false
        self.mode = self.legacy and 'bank' or 'export'
    end,

    fetch = function(self, src)
        local ok, res = pcall(function() return exports.okokBilling:getInvoices(src) end)
        if not ok then
            if tostring(res):find('No such export') then self:fallBack() end
            if self.legacy == nil then note('okokBilling', 'getInvoices failed (' .. tostring(res):sub(1, 120) .. ')') end
            return nil
        end
        if type(res) ~= 'table' then return {} end
        if res.id or res.ref_id then res = { res } end   -- a single invoice
        return res
    end,

    list = function(self, identifier)
        if self.legacy then return okokTable.list(okokTable, identifier) end
        if self.legacy == false then return {} end

        -- the export takes a server id, so only players in the city
        local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
        if not xPlayer then return {} end
        local res = self:fetch(xPlayer.source)
        if not res then return self.legacy and okokTable.list(okokTable, identifier) or {} end

        local out = {}
        for _, inv in ipairs(res) do
            if type(inv) == 'table' and inv.ref_id and OKOK_OPEN[tostring(inv.status):lower()] then
                local fees = tonumber(inv.fees) or 0
                local due = parseDate(inv.dueDate)
                out[#out + 1] = {
                    ref = inv.ref_id,
                    amount = (tonumber(inv.amount) or 0) + fees,
                    reason = fees > 0 and ('%s (incl. %s%s fees)'):format(inv.reason or 'Invoice', Config.Currency, fees) or inv.reason,
                    issuer = inv.sender or 'Invoice',
                    due = due and os.date('%d %b %H:%M', due) or nil,
                    overdue = tostring(inv.status):lower() == 'overdue' or (due ~= nil and due < os.time()),
                }
            end
        end
        return out
    end,

    pay = function(self, src, bill, accountId)
        if self.legacy then return okokTable.pay(okokTable, src, bill, accountId) end
        return viaExport(src, bill, function()
            local _, _, ran = call('okokBilling', 'okokBilling', 'payReference', src, bill.ref)
            if not ran then return false end
            -- payReference returns nothing documented: it worked if the invoice is no longer owed
            for _, inv in ipairs(self:fetch(src) or {}) do
                if type(inv) == 'table' and inv.ref_id == bill.ref and OKOK_OPEN[tostring(inv.status):lower()] then
                    return false
                end
            end
            return true
        end)
    end,
}

-- ═══════════════════════════════════════════════════════════
--  BCS Company Manager
--  Invoices in `billings`; paid through its PayBill export so the
--  company's own balance and the employee cut are kept.
-- ═══════════════════════════════════════════════════════════
ADAPTERS.bcs_companymanager = {
    resource = 'bcs_companymanager', label = 'Company Manager', mode = 'export',

    check = function(self, o)
        self.tbl = o.table or 'billings'
        return needColumns('bcs_companymanager', self.tbl, { 'id', 'identifier', 'company', 'description', 'price', 'status' })
    end,

    list = function(self, identifier)
        local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE identifier = ? AND status = ? ORDER BY id DESC LIMIT 25')
            :format(self.tbl), { identifier, 'unpaid' }) or {}
        local out = {}
        for _, r in ipairs(rows) do
            out[#out + 1] = {
                ref = r.id, amount = tonumber(r.price) or 0, reason = r.description,
                issuer = companyLabel(r.company), sender = r.biller,
            }
        end
        return out
    end,

    pay = function(self, src, bill)
        local row = MySQL.single.await(('SELECT company FROM `%s` WHERE id = ?'):format(self.tbl), { bill.ref })
        if not row then return false, 'That invoice is gone.' end
        return viaExport(src, bill, function(xPlayer)
            local res, _, ran = call('bcs_companymanager', 'bcs_companymanager', 'PayBill',
                bill.ref, bill.amount, row.company, src, xPlayer.raw or xPlayer)
            return ran and res ~= false
        end)
    end,
}

-- ═══════════════════════════════════════════════════════════
--  Export-driven scripts: RX, Wasabi, TGG, Bablo
--  Their invoices are read and paid through their own exports.
--  Field names are read loosely, since few of them document the
--  invoice object.
-- ═══════════════════════════════════════════════════════════
local function fromObject(inv)
    local status = tostring(pick(inv, 'status', 'state') or 'unpaid'):lower()
    if status == 'paid' or status == 'cancelled' or status == 'canceled' or status == 'refused' or status == 'rejected' then return nil end
    local job = bareJob(pick(inv, 'job', 'society', 'company', 'sender_job', 'senderJob'))
    return {
        ref = pick(inv, 'id', 'invoiceId', 'invoice_id', 'uuid', 'reference'),
        amount = tonumber(pick(inv, 'total', 'amount', 'price', 'invoice_value')) or 0,
        reason = pick(inv, 'reason', 'title', 'description', 'label', 'notes', 'item') or 'Invoice',
        issuer = job and companyLabel(job, pick(inv, 'senderCompanyName', 'society_name', 'company_label'))
            or pick(inv, 'senderName', 'sender_name', 'author_name') or 'Private invoice',
        sender = pick(inv, 'senderName', 'sender_name', 'author_name'),
        overdue = status == 'overdue',
    }
end

local function exportAdapter(key, resource, label, o)
    return {
        resource = resource, label = label, mode = 'export',
        check = function(self, cfg)
            self.listExport = cfg.listExport or o.listExport
            self.payExport  = cfg.payExport or o.payExport
            if not self.listExport then
                note(key, 'its docs name no export that lists a player\'s invoices; set Config.Bridge.external["' ..
                    key .. '"].listExport to turn it on')
                return nil
            end
            return true
        end,
        list = function(self, identifier)
            local res, _, ran = call(key, resource, self.listExport, o.listArgs(identifier))
            if not ran then return {} end
            local out = {}
            for _, inv in ipairs(type(res) == 'table' and res or {}) do
                local b = type(inv) == 'table' and fromObject(inv)
                if b and b.ref and b.amount > 0 then
                    b.payable = self.payExport ~= nil
                    out[#out + 1] = b
                end
            end
            return out
        end,
        pay = function(self, src, bill)
            if not self.payExport then
                return false, ('Pay this one in %s.'):format(label)
            end
            return viaExport(src, bill, function(xPlayer)
                local res, _, ran = call(key, resource, self.payExport, o.payArgs(src, xPlayer, bill.ref))
                return ran and res ~= false and res ~= nil
            end)
        end,
    }
end

ADAPTERS.RxBilling = exportAdapter('RxBilling', 'RxBilling', 'RX Billing', {
    listExport = 'GetPlayerInvoices', payExport = 'PayInvoice',
    listArgs = function(identifier) return identifier, 'incoming' end,
    payArgs  = function(src, _, ref) return src, ref end,
})

-- ═══════════════════════════════════════════════════════════
--  Quasar Billing
--  Current versions: GetPlayerInvoices(identifier, { scope = 'received' }),
--  PayInvoice(src, reference, 'bank') and GetInvoice(reference), so
--  Quasar's VAT, society payout and partial payments apply. Invoices
--  can be part paid, so what is left is what is shown. Older versions
--  with no exports are read from the qs_billing table instead.
-- ═══════════════════════════════════════════════════════════
local QS_OPEN = { pending = true, partial = true, overdue = true, unpaid = true }

--- What is still owed on a Quasar invoice, whichever fields this version uses.
local function qsOwed(inv)
    local left = tonumber(pick(inv, 'outstanding', 'remaining', 'balance', 'amountDue', 'amount_due', 'due'))
    if left then return left end
    local total = tonumber(pick(inv, 'total', 'totalAmount', 'total_amount', 'amount')) or 0
    local paid = tonumber(pick(inv, 'paid', 'amountPaid', 'amount_paid', 'paidAmount', 'paid_amount')) or 0
    return total - paid
end

local function qsStatus(inv) return tostring(pick(inv, 'status', 'state') or ''):lower() end

ADAPTERS['qs-billing'] = {
    resource = 'qs-billing', label = 'Quasar Billing', mode = 'export',

    check = function(self, o)
        self.o, self.legacy, self.mode = o, nil, 'export'
        return true
    end,

    fetch = function(self, identifier)
        local ok, res = pcall(function()
            return exports['qs-billing']:GetPlayerInvoices(identifier, { scope = 'received' })
        end)
        if not ok then
            if tostring(res):find('No such export') then
                note('qs-billing', 'no GetPlayerInvoices export (an older version?), reading its table instead')
                self.legacy = qsTable.check(qsTable, self.o) and true or false
                self.mode = self.legacy and 'bank' or 'export'
            else
                note('qs-billing', 'GetPlayerInvoices failed (' .. tostring(res):sub(1, 120) .. ')')
            end
            return nil
        end
        return type(res) == 'table' and res or {}
    end,

    list = function(self, identifier)
        if self.legacy then return qsTable.list(qsTable, identifier) end
        if self.legacy == false then return {} end
        local res = self:fetch(identifier)
        if not res then return self.legacy and qsTable.list(qsTable, identifier) or {} end

        local out = {}
        for _, inv in ipairs(res) do
            local ref = type(inv) == 'table' and pick(inv, 'reference', 'ref', 'reference_id')
            local owed = ref and qsOwed(inv) or 0
            if ref and owed > 0 and QS_OPEN[qsStatus(inv)] then
                local job = bareJob(pick(inv, 'society', 'company', 'job'))
                local due = parseDate(pick(inv, 'dueAt', 'due_at', 'dueDate', 'due_date'))
                local lines = type(inv.lines) == 'table' and inv.lines or nil
                out[#out + 1] = {
                    ref = ref, amount = owed,
                    reason = pick(inv, 'title', 'label', 'reason', 'notes')
                        or (lines and lines[1] and lines[1].label) or pick(inv, 'category') or 'Invoice',
                    issuer = job and companyLabel(job, pick(inv, 'societyLabel', 'society_label', 'companyLabel'))
                        or pick(inv, 'issuerName', 'issuer_name', 'senderName', 'sender_name', 'author_name') or 'Private invoice',
                    due = due and os.date('%d %b %H:%M', due) or nil,
                    overdue = qsStatus(inv) == 'overdue',
                    partial = qsStatus(inv) == 'partial',
                }
            end
        end
        return out
    end,

    pay = function(self, src, bill, accountId)
        if self.legacy then return qsTable.pay(qsTable, src, bill, accountId) end
        return viaExport(src, bill, function()
            local res, _, ran = call('qs-billing', 'qs-billing', 'PayInvoice', src, bill.ref, 'bank')
            if not ran or res == false then return false end
            -- the return value is not documented: it worked if nothing is left on it
            local inv = call('qs-billing', 'qs-billing', 'GetInvoice', bill.ref)
            if type(inv) ~= 'table' then return res ~= nil end
            return not QS_OPEN[qsStatus(inv)] or qsOwed(inv) <= 0
        end)
    end,
}

-- ═══════════════════════════════════════════════════════════
--  Wasabi Billing
--  GetInvoicesByIdentifier(identifier) returns what the player sent
--  as well as what they owe, so only rows addressed to them as a
--  person are kept. Paid with PayInvoiceByReference(src, ref, 'bank'):
--  Wasabi's VAT and society payout apply.
-- ═══════════════════════════════════════════════════════════
local WASABI_OPEN = { unpaid = true, overdue = true }

ADAPTERS.wasabi_billing = {
    resource = 'wasabi_billing', label = 'Wasabi Billing', mode = 'export',

    check = function() return true end,

    list = function(_, identifier)
        local res, _, ran = call('wasabi_billing', 'wasabi_billing', 'GetInvoicesByIdentifier', identifier)
        if not ran or type(res) ~= 'table' then return {} end
        local out = {}
        for _, inv in ipairs(res) do
            if type(inv) == 'table' and inv.reference_id
                and inv.receiver_identifier == identifier
                and (inv.receiver_type or 'personal') == 'personal'
                and WASABI_OPEN[tostring(inv.status):lower()] then
                local due = parseDate(inv.limit_pay_date)
                out[#out + 1] = {
                    ref = inv.reference_id,
                    -- what is owed includes VAT; amount alone is before it
                    amount = tonumber(inv.total_amount) or ((tonumber(inv.amount) or 0) + (tonumber(inv.vat_amount) or 0)),
                    reason = inv.reason or 'Invoice',
                    issuer = inv.author_name or 'Invoice',
                    due = due and os.date('%d %b %H:%M', due) or nil,
                    overdue = tostring(inv.status):lower() == 'overdue',
                }
            end
        end
        return out
    end,

    pay = function(_, src, bill)
        return viaExport(src, bill, function()
            local res, _, ran = call('wasabi_billing', 'wasabi_billing', 'PayInvoiceByReference', src, bill.ref, 'bank')
            return ran and res == true
        end)
    end,
}

ADAPTERS['tgg-billing'] = exportAdapter('tgg-billing', 'tgg-billing', 'TGG Billing', {
    payExport = 'PayInvoice',
    listArgs = function(identifier) return identifier end,
    payArgs  = function(src, _, ref) return src, ref end,
})

-- ═══════════════════════════════════════════════════════════
--  Bablo Billing
--  Pays through payInvoice(uuid, identifier). It has no export that
--  lists a player's invoices (only getInvoice by id), so its invoice
--  table is found in the database and read; nothing is written to it.
-- ═══════════════════════════════════════════════════════════
local BABLO_COLS = {
    ref    = { 'uuid', 'invoice_id', 'id' },
    to     = { 'to', 'to_identifier', 'recipient', 'recipient_identifier', 'receiver', 'receiver_identifier', 'target' },
    amount = { 'amount', 'total', 'price' },
}

local function firstOf(have, list)
    for _, c in ipairs(list) do if have[c] then return c end end
end

ADAPTERS['bablo-billing'] = {
    resource = 'bablo-billing', label = 'Bablo Billing', mode = 'export',

    check = function(self, o)
        -- an export named in config wins over reading the table
        if o.listExport then
            self.viaExport = exportAdapter('bablo-billing', 'bablo-billing', 'Bablo Billing', {
                payExport = 'payInvoice',
                listArgs = function(identifier) return identifier end,
                payArgs  = function(_, xPlayer, ref) return ref, xPlayer.identifier end,
            })
            return self.viaExport.check(self.viaExport, o)
        end

        -- the table: named in config, or the bablo table that holds invoices
        local names = {}
        if o.table then names[1] = o.table else
            for _, r in ipairs(MySQL.query.await([[
                SELECT DISTINCT TABLE_NAME AS t FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME LIKE 'bablo%' AND TABLE_NAME LIKE '%invoice%'
            ]]) or {}) do names[#names + 1] = r.t end
        end

        for _, t in ipairs(names) do
            local have = t:match('^[%w_]+$') and columns(t) or {}
            local ref, to, amount = firstOf(have, BABLO_COLS.ref), firstOf(have, BABLO_COLS.to), firstOf(have, BABLO_COLS.amount)
            if ref and to and amount then
                self.tbl, self.ref, self.to, self.cols = t, ref, to, have
                print(('^2[nayzeee-banking]^7 Bablo Billing: reading invoices from `%s` (%s, %s, %s)'):format(t, ref, to, amount))
                return true
            end
        end
        note('bablo-billing', 'could not find its invoice table; set Config.Bridge.external["bablo-billing"].table')
        return nil
    end,

    list = function(self, identifier)
        if self.viaExport then return self.viaExport.list(self.viaExport, identifier) end
        local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE `%s` = ? LIMIT 40'):format(self.tbl, self.to), { identifier }) or {}
        local out = {}
        for _, r in ipairs(rows) do
            -- a paid flag column, where there is one instead of a status
            local paid = r.paid == true or r.paid == 1 or r.is_paid == true or r.is_paid == 1
            local b = not paid and fromObject(r)
            if b then
                b.ref = r[self.ref]
                if b.ref and b.amount > 0 then out[#out + 1] = b end
            end
        end
        return out
    end,

    pay = function(self, src, bill)
        return viaExport(src, bill, function(xPlayer)
            local res, _, ran = call('bablo-billing', 'bablo-billing', 'payInvoice', bill.ref, xPlayer.identifier)
            return ran and res ~= false and res ~= nil
        end)
    end,
}

-- ═══════════════════════════════════════════════════════════
--  WIRING
-- ═══════════════════════════════════════════════════════════
local function arm(key)
    local a, o = ADAPTERS[key], opts(key)
    if not a or not o or not running(a.resource) then live[key] = nil return end
    local ok, res = pcall(a.check, a, o)
    live[key] = (ok and res) and true or nil
    if not ok then note(key, 'check failed: ' .. tostring(res)) end
    if live[key] then print(('^2[nayzeee-banking]^7 %s invoices show in the Bills tab'):format(a.label)) end
end

MySQL.ready(function()
    for key in pairs(ADAPTERS) do arm(key) end
end)

-- billing scripts started or restarted after this one
AddEventHandler('onResourceStart', function(res)
    for key, a in pairs(ADAPTERS) do
        if a.resource == res then SetTimeout(2000, function() arm(key) end) end
    end
end)
AddEventHandler('onResourceStop', function(res)
    for key, a in pairs(ADAPTERS) do
        if a.resource == res then live[key] = nil end
    end
end)

--- Every unpaid invoice the running billing scripts hold for this player,
--- in the shape of this bank's own bill rows. Ids look like 'x:okokBilling:12'.
function Bank.externalBills(identifier)
    local out = {}
    for key, a in pairs(ADAPTERS) do
        if live[key] and running(a.resource) then
            local ok, rows = pcall(a.list, a, identifier)
            if not ok then
                note(key, 'reading invoices failed: ' .. tostring(rows))
            else
                for _, b in ipairs(rows or {}) do
                    out[#out + 1] = {
                        id = ('x:%s:%s'):format(key, tostring(b.ref)),
                        issuer_label = b.issuer, sender_name = b.sender,
                        amount = Bank.round(b.amount),
                        reason = (tostring(b.reason or 'Invoice') .. (b.partial and ' (part paid)' or '')):sub(1, 120),
                        status = b.overdue and 'overdue' or 'pending',
                        stamp = b.due and ('%s · due %s'):format(a.label, b.due) or a.label, dueIn = 0,
                        ext = a.label,
                        payable = b.payable ~= false,
                        anyAccount = a.mode == 'bank',
                    }
                end
            end
        end
    end
    return out
end

--- Pay one of them. `id` is the 'x:<script>:<ref>' from the list.
function Bank.payExternalBill(src, id, accountId)
    local key, ref = tostring(id):match('^x:([^:]+):(.+)$')
    local a = key and ADAPTERS[key]
    if not a or not live[key] or not running(a.resource) then return false, 'That billing service is not available.' end

    local identifier = Bank.identifier(src)
    if not identifier then return false, 'Player not found.' end

    return Bank.serial('xbill:' .. key .. ':' .. ref, function()
        -- read it fresh; the list the player is looking at may be old
        local bill
        for _, b in ipairs(a.list(a, identifier) or {}) do
            if tostring(b.ref) == ref then bill = b break end
        end
        if not bill then return false, 'That invoice is already settled.' end
        if bill.payable == false then return false, ('Pay this one in %s.'):format(a.label) end
        bill.amount = Bank.round(bill.amount)
        if bill.amount <= 0 then return false, 'That invoice has nothing to pay.' end

        bill.identifier, bill.source = identifier, a.label
        if a.mode ~= 'bank' then
            -- the script takes it from the bank figure, i.e. the personal account
            local personal = Bank.getPersonal(identifier)
            accountId = personal and personal.id
        end
        return a.pay(a, src, bill, accountId)
    end)
end
