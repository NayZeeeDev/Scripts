function Webhook(kind, title, fields)
    local hook = Config.Webhook
    if not hook.enabled or hook.url == '' then return end

    local payload = {
        username = hook.botName,
        avatar_url = hook.avatarUrl ~= '' and hook.avatarUrl or nil,
        embeds = { {
            title = title,
            color = hook.colors[kind] or hook.colors.jail,
            fields = fields or {},
            footer = { text = 'NAYZEEE Admin Jail  ·  discord.gg/nayzeeedev' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }

    PerformHttpRequest(hook.url, function(status)
        if status >= 300 then AJ.Debug('webhook failed', status) end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

function WebhookField(name, value, inline)
    return { name = name, value = tostring(value or '-'):sub(1, 1000), inline = inline ~= false }
end
