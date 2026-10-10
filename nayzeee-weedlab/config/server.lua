--[[ Server-only configuration (never sent to clients) ]]

ServerConfig = {}

ServerConfig.Webhook = ''                 -- Discord webhook for exploit / purchase logs ('' = off)
ServerConfig.WebhookName = 'Weed Lab'

ServerConfig.Exploit = {
    action = 'log',          -- 'log' | 'kick' when a request is clearly forged
    maxCallsPerSecond = 15,  -- per player, across every callback
}

ServerConfig.SaveSeconds = 60              -- dirty profiles are written this often (and on disconnect)
