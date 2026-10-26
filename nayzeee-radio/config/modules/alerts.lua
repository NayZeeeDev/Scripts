--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    RADIO SYSTEM - EMERGENCY, GUNFIRE & ROSTER
    Discord: discord.gg/nayzeeedev

    EMERGENCY  Hold the orange button (or press EMERG on a head unit). Everyone on that
               frequency gets an alert tone and your position on the map, and your mic stays
               open for a few seconds. Hook your dispatch script in config_server.lua.
    GUNFIRE    A transmitting mic picks up gunshots around the talker, and listeners hear each
               shot through their radio with the same spacing as it was fired.
    ROSTER     Who is tuned to your TX channel, with their signal and who is speaking now.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Emergency = {
    enabled  = true,
    holdTime = 1500,     -- ms to hold the orange button
    cooldown = 30,       -- seconds between alerts per player
    blipTime = 60,       -- seconds the caller's position stays on everyone's map
    hotMic   = 8,        -- seconds the caller's mic stays open after the alert
    jobs     = false,    -- false = everyone, or { police = 0, ambulance = 0 }
}

Config.Gunfire = {
    enabled      = true,
    radius       = 60.0,   -- metres around the talker
    maxPerSecond = 20,
    npcs         = true,   -- count NPCs shooting, not only players
}

Config.Roster = {
    enabled    = true,
    nameFormat = '{name} {callsign}',   -- {name} {callsign} {id}
    maxRows    = 10,
    refresh    = 5000,     -- ms between signal bar updates while the roster is open
    popOnRx    = true,     -- pop up for 3 s when someone talks
}
