--[[
    NAYZEEE BILLING - Overdue handling
    Flags expired invoices (one-time late fee) and, in 'collect' mode, charges the recipient's bank
    (offline characters too, through the framework bridge / banking) or the recipient society's account.
]]

local function markOverdue()
    local rows = MySQL.query.await([[SELECT id, invoice_id, recipient_type, target_identifier, target_society, company_name, sender_name, total, late_fee
        FROM nayzeee_billing_invoices WHERE status IN ('pending','partial') AND due_date IS NOT NULL AND due_date < NOW() LIMIT 500]]) or {}
    local rate, cap = tonumber(Config.Overdue.LateFee) or 0, tonumber(Config.Overdue.MaxLateFee) or Config.Invoices.MaxAmount
    for _, r in ipairs(rows) do
        local fee = tonumber(r.late_fee) or 0
        if fee <= 0 and rate > 0 then fee = math.min(Shared.Round((tonumber(r.total) or 0) * rate), cap) end
        local affected = MySQL.update.await("UPDATE nayzeee_billing_invoices SET status = 'overdue', late_fee = ? WHERE id = ? AND status IN ('pending','partial')", { fee, r.id })
        if (affected or 0) > 0 then
            local msg = L('notify.overdue_body', '{ref} from {sender} is overdue', { ref = r.invoice_id, sender = r.company_name ~= 'Personal' and r.company_name or r.sender_name })
            if fee > 0 then msg = msg .. ' · ' .. L('notify.late_fee', 'late fee {amount}', { amount = Shared.Money(fee) }) end
            if r.recipient_type == 'society' then
                NotifySociety(r.target_society, 'pay', L('notify.overdue', 'Invoice overdue'), msg, 'error')
            else
                local src = Framework.GetSource(r.target_identifier)
                if src then Notify(src, L('notify.overdue', 'Invoice overdue'), msg, 'error') Refresh(src) end
            end
        end
    end
end

local function collect(row)
    local remaining = Remaining(row)
    if remaining <= 0 then return end
    local label = ('Overdue invoice %s'):format(row.invoice_id)
    local charged, method, payer
    if row.recipient_type == 'society' then
        method, payer = 'society', { identifier = row.target_identifier, name = row.target_name }
        charged = Banking.RemoveSociety(row.target_society, remaining, label)
    else
        method, payer = 'bank', { identifier = row.target_identifier, name = row.target_name }
        charged = Money.ChargeBank(row.target_identifier, remaining, label, Config.Overdue.AllowNegative, Config.Overdue.IncludeOffline)
    end
    if not charged then return end

    local result = ProcessPayment({ id = row.id, method = method, payer = payer, kind = 'autocollect', charged = true })
    if not result then
        -- Couldn't book it (invoice changed meanwhile): give the money back
        if method == 'society' then Banking.AddSociety(row.target_society, remaining, 'Collection reverted · ' .. row.invoice_id)
        else Money.DepositTo(row.target_identifier, remaining, 'Collection reverted · ' .. row.invoice_id) end
        return
    end
    local msg = L('notify.collected_body', '{amount} was collected for {ref}', { amount = Shared.Money(remaining), ref = row.invoice_id })
    if method == 'society' then
        NotifySociety(row.target_society, 'pay', L('notify.collected', 'Overdue invoice collected'), msg, 'warning')
    else
        local src = Framework.GetSource(row.target_identifier)
        if src then Notify(src, L('notify.collected', 'Overdue invoice collected'), msg, 'warning') end
    end
end

local function collectDue(extraWhere, params)
    local sql = ([[SELECT * FROM nayzeee_billing_invoices WHERE status = 'overdue'
        AND due_date < DATE_SUB(NOW(), INTERVAL ? DAY) %s LIMIT 200]]):format(extraWhere or '')
    local p = { tonumber(Config.Overdue.CollectAfterDays) or 0 }
    for _, v in ipairs(params or {}) do p[#p + 1] = v end
    for _, row in ipairs(MySQL.query.await(sql, p) or {}) do
        local ok, err = pcall(collect, row)
        if not ok then print('^1[NAYZEEE-BILLING]^7 Collection error: ' .. tostring(err)) end
    end
end

-- Run collection for one character (when they load in)
function CollectFor(identifier)
    if Config.Overdue.Enabled and Config.Overdue.Mode == 'collect' then
        collectDue("AND COALESCE(recipient_type, 'citizen') = 'citizen' AND target_identifier = ?", { identifier })
    end
end

CreateThread(function()
    while not BillingReady do Wait(500) end
    if not Config.Overdue.Enabled then return end
    local interval = math.max(1, tonumber(Config.Overdue.CheckInterval) or 5) * 60000
    while true do
        local ok, err = pcall(function()
            markOverdue()
            if Config.Overdue.Mode == 'collect' then
                if Config.Overdue.IncludeOffline then collectDue() else
                    -- Online citizens + every society
                    collectDue("AND recipient_type = 'society'")
                    for _, id in ipairs(GetPlayers()) do
                        local identifier = Framework.GetIdentifier(tonumber(id))
                        if identifier then CollectFor(identifier) end
                    end
                end
            end
        end)
        if not ok then print('^1[NAYZEEE-BILLING]^7 Overdue task: ' .. tostring(err)) end
        Wait(interval)
    end
end)

AddEventHandler('nayzeee-billing:server:ready', function()
    Framework.OnPlayerLoaded(function(source)
        SetTimeout(6000, function()
            local identifier = Framework.GetIdentifier(source)
            if identifier then CollectFor(identifier) end
        end)
    end)
end)
