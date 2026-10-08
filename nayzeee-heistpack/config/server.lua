--[[
    nayzeee-heistpack | server-only configuration
    This file is NOT sent to clients - keep secrets here.
]]

ServerConfig = {}

-- Discord webhook for heist logs (leave '' to disable)
ServerConfig.Webhook = ''
ServerConfig.WebhookName = 'nayzeee heistpack'

-- Who can use /heistadmin. Uses ACE permissions: add_ace group.admin nzh.admin allow
ServerConfig.AdminAce = 'nzh.admin'

-- Kick (or just log) players that trip anti-exploit checks
ServerConfig.Exploit = {
    action = 'log', -- 'log' | 'kick'
    maxCallsPerSecond = 12,
}

-- Persist global cooldowns across restarts (resource KVP)
ServerConfig.PersistCooldowns = true
