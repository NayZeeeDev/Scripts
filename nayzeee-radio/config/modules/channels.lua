--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    RADIO SYSTEM - CHANNELS
    Discord: discord.gg/nayzeeedev

    Every frequency between min and max is open to everyone unless it is locked here or
    in game. Admins lock single frequencies with /radioadmin (a 4-digit code, or jobs),
    and those entries win over the ranges below.

    jobs = { jobname = minimum grade }
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Channels = {
    min = 1.00,
    max = 999.99,

    -- Ranges locked to jobs out of the box.
    Restricted = {
        { from = 1.00, to = 10.99, label = 'Emergency', jobs = { police = 0, sheriff = 0, ambulance = 0 } },
    },

    requireDuty  = false,   -- job channels also need the player to be on duty
    codeAttempts = 3,       -- wrong codes before a lockout on that frequency
    codeLockout  = 30,      -- seconds
}
