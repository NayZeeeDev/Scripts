-- Discord logs (ServerConfig.Webhook) + console

Logs = {}

local RES = GetCurrentResourceName()
local COLORS = { snatch = 15026509, throw = 569250, admin = 15050250, info = 10395294 }

function Logs.send(kind, title, text)
    if Config.Debug then print(('^5[%s]^7 %s: %s'):format(RES, title, text)) end
    local hook = ServerConfig.Webhook
    if not hook or hook == '' then return end
    PerformHttpRequest(hook, function() end, 'POST', json.encode({
        username = 'Chain Snatch',
        embeds = { {
            title = title, description = text, color = COLORS[kind] or COLORS.info,
            footer = { text = RES }, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

function Logs.who(src)
    return ('%s (%s)'):format(Bridge.GetCharName(src), src)
end
