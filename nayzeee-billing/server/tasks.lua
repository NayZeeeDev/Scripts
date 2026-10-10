--[[
    NAYZEEE BILLING - Scheduled Tasks
    Overdue detection, late fees, automatic collection.
]]

local function MarkOverdue()
    local rows = MySQL.query.await([[
        SELECT invoice_id, target_identifier, company_name, total, late_fee FROM nayzeee_billing_invoices
        WHERE status IN ('pending', 'partial') AND due_date IS NOT NULL AND due_date < NOW()
        LIMIT 500
    ]]) or {}
    if #rows == 0 then return end

    local feeRate = tonumber(Config.Overdue.LateFee) or 0
    local maxFee = tonumber(Config.Overdue.MaxLateFee) or Config.MaxInvoiceAmount

    for _, row in ipairs(rows) do
        local fee = tonumber(row.late_fee) or 0
        if fee <= 0 and feeRate > 0 then
            fee = math.min(Shared.Round((tonumber(row.total) or 0) * feeRate), maxFee)
        end
        local affected = MySQL.update.await([[
            UPDATE nayzeee_billing_invoices SET status = 'overdue', late_fee = ?
            WHERE invoice_id = ? AND status IN ('pending', 'partial')
        ]], { fee, row.invoice_id })

        if (affected or 0) > 0 then
            local src = Bridge.GetSourceFromIdentifier(row.target_identifier)
            if src then
                local msg = ('%s from %s is overdue'):format(row.invoice_id, row.company_name)
                if fee > 0 then msg = msg .. (' · late fee %s added'):format(Shared.FormatCurrency(fee)) end
                Notify(src, 'Invoice overdue', msg, 'error')
                TriggerClientEvent('nayzeee-billing:client:invoiceChanged', src, row.invoice_id)
            end
        end
    end
    Shared.Debug('Marked', #rows, 'invoices overdue')
end

local function AutoCollect(rows)
    for _, row in ipairs(rows) do
        local src = Bridge.GetSourceFromIdentifier(row.target_identifier)
        if src then
            local result = ProcessPayment({
                source = src,
                invoiceId = row.invoice_id,
                method = 'bank',
                kind = 'autocollect',
                allowNegative = Config.Overdue.AutoCollectAllowNegative,
            })
            if result then
                Notify(src, 'Overdue invoice collected',
                    ('%s was automatically charged %s for %s'):format(row.company_name, Shared.FormatCurrency(result.amount), row.invoice_id), 'warning')
                TriggerClientEvent('nayzeee-billing:client:invoiceChanged', src, row.invoice_id)
            end
        end
    end
end

local function CollectSql(extra)
    return ([[
        SELECT invoice_id, target_identifier, company_name FROM nayzeee_billing_invoices
        WHERE status = 'overdue' AND due_date < DATE_SUB(NOW(), INTERVAL ? DAY) %s
        LIMIT 200
    ]]):format(extra or '')
end

-- Called when a player loads in
function ProcessAutoCollectFor(source)
    if not (Config.Overdue.Enabled and Config.Overdue.AutoCollect) then return end
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return end
    AutoCollect(MySQL.query.await(CollectSql('AND target_identifier = ?'),
        { Config.Overdue.AutoCollectAfterDays or 2, identifier }) or {})
end

CreateThread(function()
    while not BillingReady do Wait(500) end
    if not Config.Overdue.Enabled then return end

    local interval = math.max(1, tonumber(Config.Overdue.CheckInterval) or 5) * 60000
    while true do
        local ok, err = pcall(function()
            MarkOverdue()
            if Config.Overdue.AutoCollect then
                AutoCollect(MySQL.query.await(CollectSql(), { Config.Overdue.AutoCollectAfterDays or 2 }) or {})
            end
        end)
        if not ok then print('^1[NAYZEEE-BILLING]^7 Overdue task error: ' .. tostring(err)) end
        Wait(interval)
    end
end)
