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

local function pick(t, ...)
    for _, k in ipairs({ ... }) do
        if t[k] ~= nil and t[k] ~= '' then return t[k] end
    end
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

ADAPTERS.okokBilling   = invoiceTable('okokBilling', 'okokBilling', 'okokBilling', 'okokbilling')
ADAPTERS['qs-billing'] = invoiceTable('qs-billing', 'qs-billing', 'Quasar Billing', 'qs_billing')

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

-- no pay export is documented: its invoices show, paid from its own menu
ADAPTERS.wasabi_billing = exportAdapter('wasabi_billing', 'wasabi_billing', 'Wasabi Billing', {
    listExport = 'GetInvoicesByIdentifier',
    listArgs = function(identifier) return identifier end,
    payArgs  = function(src, _, ref) return src, ref end,
})

ADAPTERS['tgg-billing'] = exportAdapter('tgg-billing', 'tgg-billing', 'TGG Billing', {
    payExport = 'PayInvoice',
    listArgs = function(identifier) return identifier end,
    payArgs  = function(src, _, ref) return src, ref end,
})

ADAPTERS['bablo-billing'] = exportAdapter('bablo-billing', 'bablo-billing', 'Bablo Billing', {
    payExport = 'payInvoice',
    listArgs = function(identifier) return identifier end,
    payArgs  = function(_, xPlayer, ref) return ref, xPlayer.identifier end,
})

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
                        amount = Bank.round(b.amount), reason = tostring(b.reason or 'Invoice'):sub(1, 120),
                        status = b.overdue and 'overdue' or 'pending',
                        stamp = a.label, dueIn = 0,
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
