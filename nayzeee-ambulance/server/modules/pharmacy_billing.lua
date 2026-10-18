--[[
    NAYZEEE AMBULANCE - Server: health insurance & billing (pharmacy module)

    NZA.Insurance (ARCHITECTURE §9)
      Get(identifierOrSrc)            → { plan, label, cover, pharmacy, expires, started, serial, active = true, left } | nil
                                        (nil when the player has no plan or it expired)
      Raw(identifierOrSrc)            → stored row { identifier, plan, expires, started, serial } (also expired) | nil
      Plans()                         → { plan def, ... } (Config.Pharmacy.insurance.plans with labels)
      Quote(identifier, planId)       → { action = 'buy'|'renew'|'switch', price, credit, pay, expires, allowed, reason }
      Set(identifier, planId, days, opts?) → row | nil   (admin / other scripts; opts.src gives the card)
      Remove(identifier)              → bool
      Buy(src, planId, method, ctx)   → ok, result | err      (pharmacy window; ctx = shop context)

    NZA.Billing (ARCHITECTURE §9)
      Charge(target, amount, reason, opts) → true, info | false, err
          target = server id | identifier | 'p:<identifier>' | { kind = 'player', sid } | Patient table
          opts   = { medic = src, kind = 'treatment'|'respawn'|..., pid, society, account = 'bank'|'cash',
                     insurance = false (skip cover), external = false (never send to an external script),
                     silent = true (no toasts), noBill = true (don't store an unpaid bill) }
          info   = { amount, covered, pay, paid, method, plan, planLabel, unpaid, bill, invoiced, society, cut }
          Insurance pays its cover share, the rest is taken from Config.Billing.account (then the other
          account), the society gets the money minus the medic cut (Config.Billing.medicCut). If the
          patient can't pay an unpaid bill is stored (nza_bills) to be paid later in a pharmacy.
      Bills(identifier, status?)      → rows (awaits)        Unpaid(identifier) → total, count (awaits)
      CreateBill(identifier, amount, reason, opts) → id      PayBill(src, id | 'all', method, ctx) → ok, result
      Society(opts)                   → society account for a bill

    Callbacks: nza:pharmacy:insurance:buy (pointId, planId, method)
               nza:pharmacy:bills:pay (pointId, billId | 'all', method)
               nza:pharmacy:bills:count () → { ok, count, total }   (own open bills, for prompts)
    Net event (S→C): nza:pharmacy:bills (count, total) - pushed when a bill is created or paid
               nza:pharmacy:invoice:info (targetSid) · nza:pharmacy:invoice:send (targetSid, amount, reason)
    Usable item: Config.Items.insurance_card (shows the card to you and the nearest player)
    Commands: Config.Pharmacy.commands.insurance / .bills (ace nza.admin)
    Exports: Charge(target, amount, reason, opts) · GetInsurance(identifierOrSrc) · SetInsurance(identifier, plan, days)
             GetBills(identifier) · PayBills(src, method)
    Bus: billing:charged (identifier, info) · billing:bill (identifier, bill) · billing:paid (identifier, bills)
         insurance:changed (identifier, row | nil)
    Tables: nza_insurance, nza_bills
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Insurance = NZA.Insurance or {}
NZA.Billing = NZA.Billing or {}
NZA.Pharmacy = NZA.Pharmacy or {}

local Ins = NZA.Insurance
local Bill = NZA.Billing
local P = NZA.Pharmacy
local Core = NZA.Core

local cache = {}          -- identifier → insurance row
local invoiceCooldown = {} -- 'medic:target' → os.time()

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function L(key, ...) return NZA.L('pharmacy.' .. key, ...) end

local function cfg(section)
    local c = Config.Pharmacy or {}
    if section then return c[section] or {} end
    return c
end

local function billingCfg() return Config.Billing or {} end

local function money(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if out:sub(1, 1) == ',' then out = out:sub(2) end
    return (n < 0 and '-$' or '$') .. out
end
P.Money = money

local function hasDB() return MySQL ~= nil and MySQL.query ~= nil end

local function dbQuery(sql, params)
    if not hasDB() then return nil end
    local ok, res = pcall(MySQL.query.await, sql, params or {})
    if not ok then
        NZA.Warn('pharmacy SQL failed: ' .. tostring(res))
        return nil
    end
    return res
end

local function dbInsert(sql, params)
    if not hasDB() then return nil end
    local ok, res = pcall(MySQL.insert.await, sql, params or {})
    if not ok then
        NZA.Warn('pharmacy SQL failed: ' .. tostring(res))
        return nil
    end
    return res
end

local function notify(src, msg, kind, title)
    if not src or cfg('billing').notify == false then return end
    Core.Notify(src, { title = title or L('title_billing'), message = msg, type = kind or 'info', duration = 6500 })
end

local function cleanText(s, max)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    return s:sub(1, max or 120)
end
P.CleanText = cleanText

local function otherAccount(acc) return acc == 'cash' and 'bank' or 'cash' end

local function bridge(path, ...) return Core.B(path, ...) end

-- target → src (online or nil), identifier, display name
local function resolveTarget(target)
    local src, identifier
    local tt = type(target)
    if tt == 'number' then
        src = target
    elseif tt == 'string' then
        if #target <= 5 and target:match('^%d+$') then
            src = tonumber(target)
        elseif target:sub(1, 2) == 'n:' then
            return nil
        elseif target:sub(1, 2) == 'p:' then
            identifier = target:sub(3)
        else
            identifier = target
        end
    elseif tt == 'table' then
        if target.kind == 'npc' then return nil end
        src = tonumber(target.sid) or tonumber(target.src)
        identifier = type(target.identifier) == 'string' and target.identifier or nil
        if not src and not identifier and type(target.pid) == 'string' and target.pid:sub(1, 2) == 'p:' then
            identifier = target.pid:sub(3)
        end
    end
    if src and not Core.Online(src) then src = nil end
    if src and not identifier then identifier = Core.Identifier(src) end
    if identifier and not src then
        local s = bridge('GetSourceFromIdentifier', identifier)
        if s and Core.Online(s) then src = tonumber(s) end
    end
    if not identifier then return nil end
    local name
    if src then
        name = Core.Name(src)
    else
        local p = NZA.Patients and NZA.Patients.Get and NZA.Patients.Get('p:' .. identifier)
        name = p and p.name or identifier
    end
    return src, identifier, name
end
P.ResolveTarget = resolveTarget

-- ════════════════════════════════════════════════════════════════════════
-- INSURANCE
-- ════════════════════════════════════════════════════════════════════════

local function planDef(id)
    for _, p in ipairs(cfg('insurance').plans or {}) do
        if p.id == id then return p end
    end
    return nil
end

local function planLabel(p)
    if not p then return '' end
    return p.label or L('plan_' .. p.id)
end

function Ins.Plans()
    local out = {}
    for i, p in ipairs(cfg('insurance').plans or {}) do
        out[#out + 1] = {
            id = p.id, order = i, label = planLabel(p), desc = p.desc or L('plan_' .. p.id .. '_desc'),
            price = math.max(0, math.floor(tonumber(p.price) or 0)), days = math.max(1, math.floor(tonumber(p.days) or 7)),
            cover = NZA.Util.clamp(tonumber(p.cover) or 0, 0, 1), pharmacy = NZA.Util.clamp(tonumber(p.pharmacy) or 0, 0, 1),
            icon = p.icon or 'shield', popular = p.popular == true,
        }
    end
    return out
end

local function identOf(x)
    if type(x) == 'number' or (type(x) == 'string' and #x <= 5 and x:match('^%d+$')) then
        return Core.Identifier(tonumber(x))
    end
    if type(x) == 'string' then
        if x:sub(1, 2) == 'p:' then return x:sub(3) end
        return x
    end
    if type(x) == 'table' then
        local _, id = resolveTarget(x)
        return id
    end
    return nil
end

function Ins.Raw(x)
    local id = identOf(x)
    return id and cache[id] or nil
end

function Ins.Get(x)
    if cfg('insurance').enabled == false then return nil end
    local row = Ins.Raw(x)
    if not row then return nil end
    local now = os.time()
    if (row.expires or 0) <= now then return nil end
    local p = planDef(row.plan)
    if not p then return nil end
    return {
        plan = p.id, label = planLabel(p), icon = p.icon or 'shield',
        cover = NZA.Util.clamp(tonumber(p.cover) or 0, 0, 1), pharmacy = NZA.Util.clamp(tonumber(p.pharmacy) or 0, 0, 1),
        expires = row.expires, started = row.started, serial = row.serial, active = true, left = row.expires - now,
    }
end

-- member number printed on the cover card and the insurance_card item, e.g. HC-7KQ4-H2MX
-- (Config.Pharmacy.insurance.memberPrefix; existing serials keep their old prefix)
local function serialPrefix()
    local p = cfg('insurance').memberPrefix
    if type(p) ~= 'string' then p = 'HC-' end
    p = p:upper():gsub('[^A-Z0-9%-]', ''):sub(1, 8)
    return p
end

local function newSerial()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local out = {}
    for i = 1, 8 do
        local n = math.random(#chars)
        out[i] = chars:sub(n, n)
    end
    return serialPrefix() .. table.concat(out, '', 1, 4) .. '-' .. table.concat(out, '', 5, 8)
end

local function saveRow(row)
    dbQuery('INSERT INTO `nza_insurance` (`identifier`, `plan`, `expires`, `started`, `serial`) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE `plan` = VALUES(`plan`), `expires` = VALUES(`expires`), `started` = VALUES(`started`), `serial` = VALUES(`serial`)',
        { row.identifier, row.plan, row.expires, row.started, row.serial })
end

function Ins.Quote(identifier, planId)
    local p = planDef(planId)
    if not p then return { allowed = false, reason = 'bad_plan' } end
    local ic = cfg('insurance')
    local now = os.time()
    local price = math.max(0, math.floor(tonumber(p.price) or 0))
    local days = math.max(1, math.floor(tonumber(p.days) or 7))
    local cur = identifier and Ins.Get(identifier) or nil
    local q = { plan = p.id, price = price, credit = 0, pay = price, days = days, action = 'buy', allowed = true }
    if cur and cur.plan == p.id then
        q.action = 'renew'
        q.expires = cur.expires + days * 86400
        local maxDays = tonumber(ic.maxDays) or 90
        if (q.expires - now) > maxDays * 86400 then
            q.allowed = false
            q.reason = 'max_days'
            q.waitDays = math.ceil(((q.expires - now) - maxDays * 86400) / 86400)
        end
    elseif cur then
        q.action = 'switch'
        q.expires = now + days * 86400
        if ic.prorate ~= false then
            local old = planDef(cur.plan)
            local oldDays = old and math.max(1, tonumber(old.days) or 7) or 1
            local oldPrice = old and math.max(0, tonumber(old.price) or 0) or 0
            local credit = math.floor(oldPrice * math.min(1, cur.left / (oldDays * 86400)))
            q.credit = math.max(0, math.min(credit, price))
            q.pay = price - q.credit
        end
    else
        q.expires = now + days * 86400
    end
    return q
end

-- Give or update the insurance card item
local function cardMeta(row, name)
    local p = planDef(row.plan)
    local date = os.date('%d %b %Y', row.expires)
    return {
        plan = row.plan, planLabel = planLabel(p), holder = name, identifier = row.identifier,
        serial = row.serial, expires = row.expires, expiresText = date,
        label = L('card_label', planLabel(p)),
        description = L('card_desc', name or '?', planLabel(p), date, row.serial or ''),
    }
end

local function giveCard(src, row)
    local item = Config.Items and Config.Items.insurance_card
    if not item or not src or cfg('insurance').giveCard == false then return end
    local meta = cardMeta(row, Core.Name(src))
    local found = bridge('Inv.Search', src, item)
    local updated = false
    if type(found) == 'table' then
        for _, it in ipairs(found) do
            local m = type(it.metadata) == 'table' and it.metadata or {}
            if (m.identifier == nil or m.identifier == row.identifier) and it.slot then
                bridge('Inv.SetMetadata', src, it.slot, meta)
                updated = true
            end
        end
    end
    if updated then return end
    if bridge('Inv.CanCarry', src, item, 1) == false then
        notify(src, L('card_no_space'), 'warning', L('title_insurance'))
        return
    end
    bridge('Inv.AddItem', src, item, 1, meta)
end

function Ins.Set(identifier, planId, days, opts)
    opts = opts or {}
    identifier = identOf(identifier)
    if not identifier then return nil end
    if planId == nil or planId == false or planId == 'none' then
        return Ins.Remove(identifier) and nil
    end
    local p = planDef(planId)
    if not p then return nil end
    local now = os.time()
    days = tonumber(days) or tonumber(p.days) or 7
    local cur = cache[identifier]
    local row = {
        identifier = identifier, plan = p.id,
        started = (opts.extend and cur and cur.plan == p.id and cur.expires > now) and cur.started or now,
        expires = ((opts.extend and cur and cur.plan == p.id and cur.expires > now) and cur.expires or now) + math.floor(days * 86400),
        serial = (cur and cur.serial) or newSerial(),
    }
    cache[identifier] = row
    saveRow(row)
    local src = opts.src or select(1, resolveTarget(identifier))
    if src then giveCard(src, row) end
    NZA.Bus.Emit('insurance:changed', identifier, row)
    return row
end

function Ins.Remove(identifier)
    identifier = identOf(identifier)
    if not identifier then return false end
    cache[identifier] = nil
    dbQuery('DELETE FROM `nza_insurance` WHERE `identifier` = ?', { identifier })
    NZA.Bus.Emit('insurance:changed', identifier, nil)
    return true
end

-- Buy / renew / switch from the pharmacy window. ctx = { society, point, src }
function Ins.Buy(src, planId, method, ctx)
    local ic = cfg('insurance')
    if ic.enabled == false then return false, 'disabled' end
    local identifier = Core.Identifier(src)
    if not identifier then return false, 'no_identifier' end
    local q = Ins.Quote(identifier, planId)
    if not q.allowed then return false, q.reason or 'not_allowed', q end
    local pm = cfg('payment')
    if method ~= 'cash' and method ~= 'bank' then return false, 'bad_method' end
    if pm[method] == false then return false, 'bad_method' end
    local p = planDef(planId)
    if q.pay > 0 then
        if (tonumber(bridge('GetMoney', src, method)) or 0) < q.pay then return false, 'no_money' end
        if not bridge('RemoveMoney', src, method, q.pay, L('reason_insurance', planLabel(p))) then return false, 'no_money' end
        if ic.toSociety ~= false and ctx and ctx.society then bridge('Society.Add', ctx.society, q.pay) end
    end
    local now = os.time()
    local cur = cache[identifier]
    local row = {
        identifier = identifier, plan = p.id,
        started = (q.action == 'renew' and cur) and cur.started or now,
        expires = q.expires,
        serial = (cur and cur.serial) or newSerial(),
    }
    cache[identifier] = row
    saveRow(row)
    giveCard(src, row)
    NZA.Bus.Emit('insurance:changed', identifier, row)
    return true, { action = q.action, plan = p.id, label = planLabel(p), paid = q.pay, credit = q.credit, expires = row.expires, method = method }
end

-- ════════════════════════════════════════════════════════════════════════
-- BILLS (nza_bills)
-- ════════════════════════════════════════════════════════════════════════

local function rowToBill(r)
    return {
        id = tonumber(r.id), amount = tonumber(r.amount) or 0, covered = tonumber(r.covered) or 0,
        reason = r.reason, kind = r.kind, medicName = r.medic_name, status = r.status,
        created = tonumber(r.created) or 0, paidAt = tonumber(r.paid_at),
    }
end

function Bill.Bills(identifier, status)
    if not identifier then return {} end
    local rows
    if status then
        rows = dbQuery('SELECT * FROM `nza_bills` WHERE `identifier` = ? AND `status` = ? ORDER BY `id` DESC LIMIT 60', { identifier, status })
    else
        rows = dbQuery('SELECT * FROM `nza_bills` WHERE `identifier` = ? ORDER BY `id` DESC LIMIT 60', { identifier })
    end
    local out = {}
    for _, r in ipairs(rows or {}) do out[#out + 1] = rowToBill(r) end
    return out
end

function Bill.Unpaid(identifier)
    local list = Bill.Bills(identifier, 'unpaid')
    local total = 0
    for _, b in ipairs(list) do total = total + b.amount end
    return total, #list, list
end

function Bill.Society(opts)
    opts = opts or {}
    if type(opts.society) == 'string' and opts.society ~= '' then return opts.society end
    local medic = tonumber(opts.medic)
    if medic and NZA.Staff and NZA.Staff.Get and NZA.Hospitals and NZA.Hospitals.Society then
        local rec = NZA.Staff.Get(medic)
        if rec and rec.dept then
            local s = NZA.Hospitals.Society(rec.dept)
            if s then return s end
        end
    end
    return billingCfg().society or 'ambulance'
end

-- tell an online player how many open bills they have (prompts, sidebar)
local function pushBills(identifier, src)
    if not identifier then return end
    src = src or select(1, resolveTarget(identifier))
    if not src then return end
    CreateThread(function()
        local total, count = Bill.Unpaid(identifier)
        TriggerClientEvent('nza:pharmacy:bills', src, count, total)
    end)
end
Bill.Push = pushBills

function Bill.CreateBill(identifier, amount, reason, opts)
    opts = opts or {}
    amount = math.floor(tonumber(amount) or 0)
    if not identifier or amount <= 0 or not hasDB() then return nil end
    local bc = cfg('billing')
    local medicId = opts.medic and Core.Identifier(opts.medic) or nil
    local medicName = opts.medic and Core.Name(opts.medic) or nil
    local now = os.time()
    local max = tonumber(bc.maxUnpaid) or 25
    local open = dbQuery('SELECT `id` FROM `nza_bills` WHERE `identifier` = ? AND `status` = ? ORDER BY `id` DESC', { identifier, 'unpaid' }) or {}
    if max > 0 and #open >= max then
        -- merge into the newest bill so a player can't pile up thousands of rows
        local id = tonumber(open[1].id)
        dbQuery('UPDATE `nza_bills` SET `amount` = `amount` + ?, `covered` = `covered` + ?, `reason` = ?, `created` = ? WHERE `id` = ?',
            { amount, math.floor(tonumber(opts.covered) or 0), L('reason_merged'), now, id })
        pushBills(identifier)
        return id
    end
    local id = dbInsert('INSERT INTO `nza_bills` (`identifier`, `name`, `amount`, `covered`, `reason`, `kind`, `medic`, `medic_name`, `society`, `status`, `created`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { identifier, cleanText(opts.name, 80), amount, math.floor(tonumber(opts.covered) or 0), cleanText(reason, 120) or L('reason_default'),
          cleanText(opts.kind, 32), medicId, cleanText(medicName, 80), Bill.Society(opts), 'unpaid', now })
    if id then
        NZA.Bus.Emit('billing:bill', identifier, { id = id, amount = amount, reason = reason, kind = opts.kind })
        pushBills(identifier)
    end
    return id
end

-- society share + medic cut for money that was actually paid
local function settle(paid, society, medic, payerSrc, reason, patientName)
    if paid <= 0 then return 0 end
    local cut = 0
    local rate = tonumber(billingCfg().medicCut) or 0
    medic = tonumber(medic)
    if medic and rate > 0 and medic ~= payerSrc and Core.Online(medic) then
        cut = math.floor(paid * NZA.Util.clamp(rate, 0, 1))
        if cut > 0 then
            if bridge('AddMoney', medic, 'bank', cut, reason) then
                notify(medic, L('medic_cut', money(cut), patientName or '?'), 'success', L('title_billing'))
            else
                cut = 0
            end
        end
    end
    local toSociety = paid - cut
    if toSociety > 0 and society then bridge('Society.Add', society, toSociety) end
    return cut
end

-- ════════════════════════════════════════════════════════════════════════
-- EXTERNAL BILLING ADAPTERS
-- ════════════════════════════════════════════════════════════════════════

local External = {}

local function senderName(opts)
    local bc = cfg('billing')
    if bc.externalSender then return bc.externalSender end
    if opts.medic and Core.Online(opts.medic) then return Core.Name(opts.medic) end
    return L('sender_default')
end

External['okokBilling'] = function(src, identifier, amount, reason, opts, society)
    if not src or GetResourceState('okokBilling') ~= 'started' then return false end
    -- documented server event: (target, amount, invoiceSource, invoiceReason, society, societyName)
    TriggerEvent('okokBilling:CreateCustomInvoice', src, amount, senderName(opts), reason, society, L('sender_default'))
    return true
end

External['esx_billing'] = function(src, identifier, amount, reason, opts, society)
    if GetResourceState('esx_billing') ~= 'started' then return false end
    local target = society:sub(1, 8) == 'society_' and society or ('society_' .. society)
    local sender = (opts.medic and Core.Identifier(opts.medic)) or target
    local id = dbInsert('INSERT INTO `billing` (`identifier`, `sender`, `target_type`, `target`, `label`, `amount`) VALUES (?, ?, ?, ?, ?, ?)',
        { identifier, sender, 'society', target, reason, amount })
    return id ~= nil
end

local function phoneInvoice(src, identifier, amount, reason, opts, society)
    local senderId = (opts.medic and Core.Identifier(opts.medic)) or identifier
    local id = dbInsert('INSERT INTO `phone_invoices` (`citizenid`, `amount`, `society`, `sender`, `sendercitizenid`) VALUES (?, ?, ?, ?, ?)',
        { identifier, amount, society, senderName(opts), senderId })
    if id and src then
        TriggerClientEvent('qb-phone:RefreshPhone', src)
    end
    return id ~= nil
end
External['qb-phone'] = phoneInvoice
External['jim-payments'] = phoneInvoice

External['custom'] = function(src, identifier, amount, reason, opts, society)
    local fn = cfg('billing').custom
    if type(fn) ~= 'function' then return false end
    local ok, res = pcall(fn, src, identifier, amount, reason, opts, society)
    return ok and res ~= false
end

local function externalFor(opts)
    local bc = cfg('billing')
    if not bc.external or opts.external == false then return nil end
    if type(bc.externalKinds) == 'table' then
        local hit = false
        for _, k in ipairs(bc.externalKinds) do
            if k == opts.kind then hit = true break end
        end
        if not hit then return nil end
    end
    return External[bc.external]
end

-- ════════════════════════════════════════════════════════════════════════
-- CHARGE
-- ════════════════════════════════════════════════════════════════════════

function Bill.Charge(target, amount, reason, opts)
    opts = type(opts) == 'table' and opts or {}
    amount = math.floor((tonumber(amount) or 0) + 0.5)
    if billingCfg().enabled == false then return true, { amount = 0, disabled = true } end
    if amount <= 0 then return true, { amount = 0 } end
    local src, identifier, name = resolveTarget(target)
    if not identifier then return false, 'no_target' end
    local bc = cfg('billing')
    reason = cleanText(reason, 120) or L('reason_default')
    local silent = opts.silent == true

    local info = { amount = amount, covered = 0, pay = amount, paid = 0, reason = reason, kind = opts.kind, society = Bill.Society(opts) }

    -- insurance share
    if bc.useInsurance ~= false and opts.insurance ~= false then
        local ins = Ins.Get(identifier)
        if ins and ins.cover > 0 then
            info.covered = math.min(amount, math.floor(amount * ins.cover + 0.5))
            info.pay = amount - info.covered
            info.plan = ins.plan
            info.planLabel = ins.label
            if bc.insurerPays ~= false and info.covered > 0 then bridge('Society.Add', info.society, info.covered) end
        end
    end

    if info.pay <= 0 then
        if src and not silent then notify(src, L('bill_all_covered', money(amount), reason, info.planLabel or ''), 'success') end
        NZA.Bus.Emit('billing:charged', identifier, info)
        return true, info
    end

    -- external invoice script
    local ext = externalFor(opts)
    if ext then
        local ok, sent = pcall(ext, src, identifier, info.pay, reason, opts, info.society)
        if ok and sent then
            info.invoiced = true
            if src and not silent then notify(src, L('bill_invoiced', money(info.pay), reason), 'info') end
            NZA.Bus.Emit('billing:charged', identifier, info)
            return true, info
        end
        if bc.externalFallback == false then return false, 'external_failed' end
    end

    -- direct payment
    if src then
        local acc = (opts.account == 'cash' or opts.account == 'bank') and opts.account or (billingCfg().account == 'cash' and 'cash' or 'bank')
        local paid = bridge('RemoveMoney', src, acc, info.pay, reason) == true
        if not paid and bc.otherAccount ~= false then
            acc = otherAccount(acc)
            paid = bridge('RemoveMoney', src, acc, info.pay, reason) == true
        end
        if paid then
            info.paid = info.pay
            info.method = acc
            info.cut = settle(info.pay, info.society, opts.medic, src, reason, name)
            if not silent then
                if info.covered > 0 then
                    notify(src, L('bill_covered', money(amount), reason, money(info.covered), money(info.pay)), 'info')
                else
                    notify(src, L('bill_paid', money(info.pay), reason, L('method_' .. acc)), 'info')
                end
            end
            NZA.Bus.Emit('billing:charged', identifier, info)
            return true, info
        end
    end

    -- could not pay → unpaid bill
    if bc.unpaidBills ~= false and opts.noBill ~= true then
        local id = Bill.CreateBill(identifier, info.pay, reason, {
            name = name, covered = info.covered, kind = opts.kind, medic = opts.medic, society = info.society,
        })
        if id then
            info.unpaid = true
            info.bill = id
            if src and not silent then notify(src, L('bill_unpaid', money(info.pay), reason), 'warning') end
            if opts.medic and Core.Online(opts.medic) and not silent then
                notify(opts.medic, L('bill_unpaid_medic', name or '?', money(info.pay)), 'warning')
            end
            NZA.Bus.Emit('billing:charged', identifier, info)
            return true, info
        end
    end
    return false, 'cannot_pay'
end

-- Pay one bill or all of them. ctx = { society } (the pharmacy's department, used when a bill has none)
function Bill.PayBill(src, which, method, ctx)
    local identifier = Core.Identifier(src)
    if not identifier then return false, 'no_identifier' end
    if method ~= 'cash' and method ~= 'bank' then return false, 'bad_method' end
    if cfg('payment')[method] == false then return false, 'bad_method' end
    local list = Bill.Bills(identifier, 'unpaid')
    local pick = {}
    if which == 'all' then
        pick = list
    else
        local id = tonumber(which)
        for _, b in ipairs(list) do
            if b.id == id then pick[1] = b end
        end
    end
    if #pick == 0 then return false, 'no_bill' end
    local total = 0
    for _, b in ipairs(pick) do total = total + b.amount end
    if (tonumber(bridge('GetMoney', src, method)) or 0) < total then return false, 'no_money' end
    if not bridge('RemoveMoney', src, method, total, L('reason_bills')) then return false, 'no_money' end

    local now = os.time()
    local ids = {}
    for _, b in ipairs(pick) do ids[#ids + 1] = b.id end
    local placeholders = string.rep('?,', #ids):sub(1, -2)
    local params = { 'paid', now, identifier }
    for _, id in ipairs(ids) do params[#params + 1] = id end
    dbQuery('UPDATE `nza_bills` SET `status` = ?, `paid_at` = ? WHERE `identifier` = ? AND `id` IN (' .. placeholders .. ')', params)

    -- money goes to the society on the bill; the medic who treated gets the cut when online
    local rows = dbQuery('SELECT `id`, `amount`, `society`, `medic` FROM `nza_bills` WHERE `id` IN (' .. placeholders .. ')', ids) or {}
    local name = Core.Name(src)
    for _, r in ipairs(rows) do
        local society = (type(r.society) == 'string' and r.society ~= '') and r.society or (ctx and ctx.society) or Bill.Society({})
        local medic = nil
        if cfg('billing').lateMedicCut ~= false and type(r.medic) == 'string' and r.medic ~= '' then
            local s = bridge('GetSourceFromIdentifier', r.medic)
            if s and Core.Online(s) then medic = tonumber(s) end
        end
        settle(tonumber(r.amount) or 0, society, medic, src, L('reason_bills'), name)
    end
    NZA.Bus.Emit('billing:paid', identifier, pick)
    pushBills(identifier, src)
    return true, { paid = total, count = #pick, method = method }
end

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS (pharmacy window: insurance & bills)
-- ════════════════════════════════════════════════════════════════════════

local function rate(src, kind)
    local r = cfg('rates')[kind] or { 8, 5000 }
    return Core.Rate('pharmacy:' .. kind, src, r[1] or 8, r[2] or 5000)
end

local function fail(err, extra)
    local out = { ok = false, err = err, msg = L('err_' .. tostring(err)) }
    if type(extra) == 'table' then for k, v in pairs(extra) do out[k] = v end end
    return out
end

lib.callback.register('nza:pharmacy:insurance:buy', function(src, pointId, planId, method)
    if not rate(src, 'buy') then return fail('rate') end
    if type(planId) ~= 'string' then return fail('bad_plan') end
    local ctx, err = P.Session(src, pointId)
    if not ctx then return fail(err) end
    if not ctx.allowInsurance then return fail('disabled') end
    local ok, res = Ins.Buy(src, planId, method, ctx)
    if not ok then return fail(res) end
    P.LogSale(ctx, src, { { id = 'insurance:' .. res.plan, label = L('insurance_line', res.label), qty = 1, unit = res.paid, total = res.paid } },
        { subtotal = res.paid, discount = 0, tax = 0, total = res.paid, method = method, kind = 'insurance' })
    Core.Notify(src, { title = L('title_insurance'), message = L('insurance_done_' .. res.action, res.label, os.date('%d %b %Y', res.expires)), type = 'success' })
    return { ok = true, result = res, data = P.OpenData(src, ctx) }
end)

lib.callback.register('nza:pharmacy:bills:pay', function(src, pointId, which, method)
    if not rate(src, 'buy') then return fail('rate') end
    local ctx, err = P.Session(src, pointId)
    if not ctx then return fail(err) end
    if not ctx.allowBills then return fail('disabled') end
    if which ~= 'all' and not tonumber(which) then return fail('no_bill') end
    local ok, res = Bill.PayBill(src, which, method, ctx)
    if not ok then return fail(res) end
    Core.Notify(src, { title = L('title_billing'), message = L('bills_paid', res.count, money(res.paid)), type = 'success' })
    return { ok = true, result = res, data = P.OpenData(src, ctx) }
end)

lib.callback.register('nza:pharmacy:bills:count', function(src)
    if not rate(src, 'action') then return { ok = false, err = 'rate' } end
    local identifier = Core.Identifier(src)
    if not identifier then return { ok = false, err = 'no_identifier' } end
    local total, count = Bill.Unpaid(identifier)
    return { ok = true, count = count, total = total }
end)

-- ── medic → patient bill ─────────────────────────────────────────────────

local function invoiceCheck(src, targetSid)
    local ic = cfg('invoice')
    if ic.enabled == false then return nil, 'disabled' end
    targetSid = tonumber(targetSid)
    if not targetSid or targetSid == src or not Core.Online(targetSid) then return nil, 'no_target' end
    if not NZA.Staff.Can(src, ic.perm or 'assess') then return nil, 'no_perm' end
    local rec = NZA.Staff.Get(src) or {}
    if not rec.medic and not Core.IsAdmin(src) then return nil, 'no_perm' end
    local a, b = Core.SrcCoords(src), Core.SrcCoords(targetSid)
    if not a or not b or #(a - b) > (tonumber(ic.distance) or 4.0) + 1.0 then return nil, 'too_far' end
    return targetSid
end

lib.callback.register('nza:pharmacy:invoice:info', function(src, targetSid)
    if not rate(src, 'action') then return fail('rate') end
    local t, err = invoiceCheck(src, targetSid)
    if not t then return fail(err) end
    local ic = cfg('invoice')
    local ins = Ins.Get(t)
    local presets = {}
    for _, pr in ipairs(ic.presets or {}) do
        presets[#presets + 1] = { key = pr.key, amount = math.floor(tonumber(pr.amount) or 0), label = L('reason_' .. tostring(pr.key)) }
    end
    local last = invoiceCooldown[src .. ':' .. t]
    local wait = last and math.max(0, (tonumber(ic.cooldown) or 20) - (os.time() - last)) or 0
    return {
        ok = true, name = Core.Name(t), sid = t, max = tonumber(ic.max) or 15000, presets = presets, wait = wait,
        insurance = ins and { label = ins.label, cover = ins.cover } or nil,
        cut = tonumber(billingCfg().medicCut) or 0, locale = NZA.LocaleTable('pharmacy'),
    }
end)

lib.callback.register('nza:pharmacy:invoice:send', function(src, targetSid, amount, reason)
    if not rate(src, 'buy') then return fail('rate') end
    local t, err = invoiceCheck(src, targetSid)
    if not t then return fail(err) end
    local ic = cfg('invoice')
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > (tonumber(ic.max) or 15000) then return fail('bad_amount') end
    local key = src .. ':' .. t
    local last = invoiceCooldown[key]
    if last and os.time() - last < (tonumber(ic.cooldown) or 20) then return fail('cooldown') end
    reason = cleanText(reason, 80) or L('reason_treatment')
    invoiceCooldown[key] = os.time()
    local ok, info = Bill.Charge(t, amount, reason, { medic = src, kind = 'invoice' })
    if not ok then return fail(info or 'cannot_pay') end
    local msg
    if info.unpaid then
        msg = L('invoice_sent_unpaid', Core.Name(t), money(info.pay))
    elseif (info.covered or 0) > 0 then
        msg = L('invoice_sent_covered', money(amount), Core.Name(t), money(info.covered))
    else
        msg = L('invoice_sent', money(amount), Core.Name(t))
    end
    Core.Notify(src, { title = L('title_billing'), message = msg, type = 'success' })
    return { ok = true, info = info }
end)

-- ════════════════════════════════════════════════════════════════════════
-- INSURANCE CARD (usable)
-- ════════════════════════════════════════════════════════════════════════

local function useCard(src, item)
    local meta = type(item) == 'table' and type(item.metadata) == 'table' and item.metadata or {}
    local holder = meta.holder or Core.Name(src)
    local ident = meta.identifier or Core.Identifier(src)
    local ins = ident and Ins.Get(ident) or nil
    local valid = ins ~= nil and (meta.plan == nil or ins.plan == meta.plan)
    local planText = (ins and ins.label) or meta.planLabel or L('plan_none')
    local msg
    if valid then
        msg = L('card_show_valid', holder, planText, os.date('%d %b %Y', ins.expires), math.floor(ins.cover * 100 + 0.5))
    else
        msg = L('card_show_invalid', holder, planText)
    end
    local data = { title = L('card_title'), message = msg, type = valid and 'success' or 'error', duration = 7000, icon = 'shield' }
    Core.Notify(src, data)
    -- show it to the nearest player
    local me = Core.SrcCoords(src)
    if not me then return end
    local best, bestD = nil, tonumber(cfg('insurance').cardShowDistance) or 3.0
    for _, id in ipairs(GetPlayers()) do
        local o = tonumber(id)
        if o and o ~= src then
            local c = Core.SrcCoords(o)
            if c and #(c - me) <= bestD then best, bestD = o, #(c - me) end
        end
    end
    if best then Core.Notify(best, data) end
end

-- ════════════════════════════════════════════════════════════════════════
-- AUTO COLLECT
-- ════════════════════════════════════════════════════════════════════════

local function collect(src)
    local identifier = Core.Identifier(src)
    if not identifier then return end
    local total, count, list = Bill.Unpaid(identifier)
    if count == 0 then return end
    local bank = tonumber(bridge('GetMoney', src, 'bank')) or 0
    if bank < total then return end
    local ok = Bill.PayBill(src, 'all', 'bank', nil)
    if ok then
        notify(src, L('bills_collected', count, money(total)), 'info')
    end
    return list
end

-- ════════════════════════════════════════════════════════════════════════
-- COMMANDS
-- ════════════════════════════════════════════════════════════════════════

local function reply(src, msg, kind)
    if src == 0 then print('[nayzeee-ambulance] ' .. msg) return end
    Core.Notify(src, { title = L('title_admin'), message = msg, type = kind or 'info' })
end

local function registerCommands()
    local cmds = cfg('commands')
    if type(cmds.insurance) == 'string' and cmds.insurance ~= '' then
        RegisterCommand(cmds.insurance, function(src, args)
            if src ~= 0 and not Core.IsAdmin(src) then return reply(src, L('err_no_perm'), 'error') end
            local target = tonumber(args[1]) or src
            if not Core.Online(target) then return reply(src, L('err_no_target'), 'error') end
            local plan = args[2]
            if not plan then
                local ins = Ins.Get(target)
                if ins then
                    return reply(src, L('cmd_ins_show', Core.Name(target), ins.label, os.date('%d %b %Y %H:%M', ins.expires)))
                end
                return reply(src, L('cmd_ins_none', Core.Name(target)))
            end
            if plan == 'none' then
                Ins.Remove(Core.Identifier(target))
                return reply(src, L('cmd_ins_removed', Core.Name(target)), 'success')
            end
            if not planDef(plan) then return reply(src, L('err_bad_plan'), 'error') end
            local row = Ins.Set(Core.Identifier(target), plan, tonumber(args[3]), { src = target })
            if row then
                reply(src, L('cmd_ins_set', Core.Name(target), planLabel(planDef(plan)), os.date('%d %b %Y', row.expires)), 'success')
            end
        end, false)
    end
    if type(cmds.bills) == 'string' and cmds.bills ~= '' then
        RegisterCommand(cmds.bills, function(src, args)
            if src ~= 0 and not Core.IsAdmin(src) then return reply(src, L('err_no_perm'), 'error') end
            local target = tonumber(args[1]) or src
            if not Core.Online(target) then return reply(src, L('err_no_target'), 'error') end
            local identifier = Core.Identifier(target)
            CreateThread(function()
                if args[2] == 'clear' then
                    dbQuery('UPDATE `nza_bills` SET `status` = ? WHERE `identifier` = ? AND `status` = ?', { 'void', identifier, 'unpaid' })
                    return reply(src, L('cmd_bills_cleared', Core.Name(target)), 'success')
                end
                local total, count = Bill.Unpaid(identifier)
                reply(src, L('cmd_bills', Core.Name(target), count, money(total)))
            end)
        end, false)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════════════════════════════════════════

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `nza_insurance` (
        `identifier` VARCHAR(80) NOT NULL,
        `plan` VARCHAR(32) NOT NULL,
        `expires` INT UNSIGNED NOT NULL DEFAULT 0,
        `started` INT UNSIGNED NOT NULL DEFAULT 0,
        `serial` VARCHAR(24) NULL DEFAULT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`)
    ) DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nza_bills` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(80) NOT NULL,
        `name` VARCHAR(80) NULL DEFAULT NULL,
        `amount` INT UNSIGNED NOT NULL DEFAULT 0,
        `covered` INT UNSIGNED NOT NULL DEFAULT 0,
        `reason` VARCHAR(120) NULL DEFAULT NULL,
        `kind` VARCHAR(32) NULL DEFAULT NULL,
        `medic` VARCHAR(80) NULL DEFAULT NULL,
        `medic_name` VARCHAR(80) NULL DEFAULT NULL,
        `society` VARCHAR(64) NULL DEFAULT NULL,
        `status` VARCHAR(12) NOT NULL DEFAULT 'unpaid',
        `created` INT UNSIGNED NOT NULL DEFAULT 0,
        `paid_at` INT UNSIGNED NULL DEFAULT NULL,
        PRIMARY KEY (`id`),
        KEY `identifier_status` (`identifier`, `status`)
    ) DEFAULT CHARSET=utf8mb4]],
}

CreateThread(function()
    if cfg().enabled == false then return end
    if hasDB() then
        for _, q in ipairs(SCHEMA) do dbQuery(q) end
        local rows = dbQuery('SELECT * FROM `nza_insurance` WHERE `expires` > ?', { os.time() - 86400 * 30 }) or {}
        for _, r in ipairs(rows) do
            cache[r.identifier] = {
                identifier = r.identifier, plan = r.plan, expires = tonumber(r.expires) or 0,
                started = tonumber(r.started) or 0, serial = r.serial,
            }
        end
        NZA.Debug('pharmacy: loaded insurance rows', #rows)
    else
        NZA.Warn('pharmacy: oxmysql is not available - insurance and bills are kept in memory only')
    end
    registerCommands()

    local item = Config.Items and Config.Items.insurance_card
    if item and Bridge and Bridge.Inv and Bridge.Inv.RegisterUsable then
        local ok, err = pcall(Bridge.Inv.RegisterUsable, item, function(src, it) useCard(src, it) end)
        if not ok then NZA.Warn('pharmacy: insurance card usable failed: ' .. tostring(err)) end
    end

    local ac = cfg('billing').autoCollect or {}
    if ac.enabled then
        if ac.onLoad ~= false then
            NZA.Bus.On('player:loaded', function(src)
                SetTimeout(15000, function() collect(src) end)
            end)
        end
        local interval = math.max(5, tonumber(ac.interval) or 30) * 60000
        while true do
            Wait(interval)
            for _, id in ipairs(GetPlayers()) do
                local s = tonumber(id)
                if s then
                    pcall(collect, s)
                    Wait(50)
                end
            end
        end
    end
end)

-- in-memory insurance rows of players that go away stay cached (tiny); invoice cooldowns are pruned
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    for k in pairs(invoiceCooldown) do
        if k:sub(1, #tostring(src) + 1) == src .. ':' or k:sub(-(#tostring(src) + 1)) == ':' .. src then
            invoiceCooldown[k] = nil
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════

exports('Charge', function(target, amount, reason, opts) return Bill.Charge(target, amount, reason, opts) end)
exports('GetInsurance', function(x) return Ins.Get(x) end)
exports('SetInsurance', function(identifier, plan, days) return Ins.Set(identifier, plan, days) ~= nil end)
exports('GetBills', function(identifier, status) return Bill.Bills(identOf(identifier), status) end)
exports('PayBills', function(src, method) return Bill.PayBill(src, 'all', method or 'bank', nil) end)
