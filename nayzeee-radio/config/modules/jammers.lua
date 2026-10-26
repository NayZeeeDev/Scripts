--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    RADIO SYSTEM - SIGNAL JAMMERS
    Discord: discord.gg/nayzeeedev

    Use a jammer item to place it: aim, scroll to turn it, [E] to put it down. Radios near it
    fill with static; close in they can't transmit at all. It runs until its battery dies
    (life, minutes), its owner picks it up, or someone hacks it: match the jammer's waveform
    band by band (A/D wavelength, W/S amplitude) before the timer runs out.

    core      share of the radius where the jam is at full strength
    strength  0..1 at the core
    bands     waveforms to match in the hack (1-3)
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Jammers = {
    enabled       = true,
    placeDistance = 3.0,      -- metres in front of you a jammer can go
    maxPerPlayer  = 1,
    hackJobs      = false,    -- false = anyone can try the hack, or { police = 0 }
    seizeJobs     = { police = 0, sheriff = 0 },   -- these can also pick up anyone's jammer
    failLockout   = 20,       -- seconds before the same player can try again after failing
    drawDistance  = 150.0,    -- metres at which jammer props are spawned

    Types = {
        pocket = { label = 'Pocket Jammer', model = 'nzr_jammer_pocket', radius = 45.0,  core = 0.35, strength = 0.85, life = 15, bands = 1, time = 25 },
        case   = { label = 'Field Jammer',  model = 'nzr_jammer_case',   radius = 110.0, core = 0.35, strength = 0.95, life = 30, bands = 2, time = 40 },
        heavy  = { label = 'Heavy Jammer',  model = 'nzr_jammer_heavy',  radius = 220.0, core = 0.30, strength = 1.00, life = 45, bands = 3, time = 55 },
    },
}
