--[[
    NAYZEEE MULTIJOB - Server Config

    Loaded on the server only. Anything secret goes here - this file is never
    sent to players, unlike config.lua.
]]

ServerConfig = {}

-- ██████╗ ██╗███████╗ ██████╗ ██████╗ ██████╗ ██████╗
-- ██╔══██╗██║██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔══██╗
-- ██║  ██║██║███████╗██║     ██║   ██║██████╔╝██║  ██║
-- ██║  ██║██║╚════██║██║     ██║   ██║██╔══██╗██║  ██║
-- ██████╔╝██║███████║╚██████╗╚██████╔╝██║  ██║██████╔╝
-- ╚═════╝ ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝
-- Optional Discord logging

ServerConfig.Discord = {
    enabled = false,

    -- Leave empty to read the convar instead:
    --   set nayzeee_multijob_webhook "https://discord.com/api/webhooks/..."
    webhook = '',

    username = 'Job Center',
    avatar = '', -- image URL, optional

    logEvents = {
        jobSwitch = true,   -- switch, quit, remove, job added
        clockIn = true,
        clockOut = true,
        adminAction = true, -- every staff action from /jobadmin
        bossAction = true,  -- hires, promotions and firings from the Team tab
    }
}
