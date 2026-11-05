--[[
    NAYZEEE BILLING - Logger bridge (server)
    Editable. Discord webhooks, ox_lib logger (lib.logger) or your own function.
    Every log is also written to the nayzeee_billing_logs table (Activity page).
]]

Logger = {}

local function discord(url, title, fields)
    if not url or url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = Config.Logs.Name,
        embeds = { {
            title = title, color = Config.Logs.Color, fields = fields,
            footer = { text = 'nayzeee-billing v' .. Shared.Version },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- event: invoice_created / invoice_paid / ... ; data: flat table ; webhookKey: Config.Logs.Webhooks key
function Logger.Send(event, source, data, extraWebhook)
    if not Config.Logs.Enabled then return end
    local system = Config.Logs.System
    local name = (source and source > 0) and Framework.GetName(source) or 'System'

    if system == 'discord' then
        local fields = { { name = 'Player', value = ('%s%s'):format(name, (source and source > 0) and (' (' .. source .. ')') or ''), inline = true } }
        for k, v in pairs(data or {}) do
            if type(v) ~= 'table' then fields[#fields + 1] = { name = k, value = tostring(v), inline = true } end
        end
        local key = event:match('^admin') and 'admin' or event
        local url = (Config.Logs.Webhooks or {})[key]
        if not url or url == '' then url = Config.Logs.Webhook end
        local title = Config.Logs.Name .. ' · ' .. event:gsub('_', ' '):upper()
        discord(url, title, fields)
        if extraWebhook and extraWebhook ~= url then discord(extraWebhook, title, fields) end
    elseif system == 'ox_lib' and lib.logger then
        lib.logger(source or 0, event, json.encode(data or {}))
    elseif system == 'custom' and Config.Logs.Custom then
        pcall(Config.Logs.Custom, event, source, data)
    end
end
