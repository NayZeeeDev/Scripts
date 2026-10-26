--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    RADIO SYSTEM - SIGNAL & AUDIO
    Discord: discord.gg/nayzeeedev

    SIGNAL   Each link between two radios has a quality from 0 to 1. It falls with distance
             (past falloffStart of the range), rises with height, and drops inside jammers
             and dead zones. Below 'poor' you only hear the signal breaking up.
    AUDIO    Incoming voice runs through GTA's radio effect, harsher as the signal weakens.
             The hiss, squelch tails and mic clicks are generated in the browser - there are
             no sound files to replace.
    LEAK     A receiving radio is audible to people standing beside it: the outside speaker of
             a car with its head unit on, or a handheld worn without an earpiece.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Signal = {
    falloffStart = 0.55,   -- signal starts fading at this share of the range
    refresh      = 1000,   -- ms between quality updates while someone talks

    -- Higher up reaches further: +1 % range per 4 m above 40 m, up to +75 %
    height = { from = 40.0, per = 400.0, max = 0.75 },

    tiers = { clear = 0.75, weak = 0.45, poor = 0.15 },   -- quality bands

    txBlockJam = 0.92,     -- jammed this hard, a radio cannot transmit at all

    -- Places radios struggle (tunnels, deep interiors). factor multiplies the range.
    DeadZones = {
        -- { coords = vec3(-1035.0, -2733.0, 13.0), radius = 120.0, factor = 0.35 },
    },
}

Config.Audio = {
    clicks   = true,       -- mic clicks ("de-doot") when someone keys up or down
    hiss     = 0.35,       -- how loud the hiss gets on a weak signal (0..1)
    squelch  = true,       -- squelch tail at the end of a transmission
    pan      = 'center',   -- 'left' | 'center' | 'right' ear for radio voice
    nearSkip = 4.0,        -- metres: closer than this you hear the talker in person, not on the radio
    sfx      = 0.8,        -- volume of the radio's own beeps and clicks (0..1)

    -- GTA's radio effect for each signal band
    Submix = {
        clear   = { freq_low = 389.0, freq_hi = 3248.0, fudge = 0.0, rm_mod_freq = 0.0,  rm_mix = 0.16, o_freq_lo = 348.0, o_freq_hi = 4900.0 },
        weak    = { freq_low = 450.0, freq_hi = 3000.0, fudge = 0.6, rm_mod_freq = 30.0, rm_mix = 0.26, o_freq_lo = 400.0, o_freq_hi = 4200.0 },
        poor    = { freq_low = 600.0, freq_hi = 2600.0, fudge = 2.0, rm_mod_freq = 60.0, rm_mix = 0.42, o_freq_lo = 500.0, o_freq_hi = 3200.0 },
        speaker = { freq_low = 300.0, freq_hi = 3500.0, fudge = 0.3, rm_mod_freq = 0.0,  rm_mix = 0.10, o_freq_lo = 250.0, o_freq_hi = 3800.0 },
    },
}

Config.Leak = {
    handheld  = 2.2,    -- metres around someone whose radio is receiving (0 = off). An earpiece stops it.
    vehicle   = 12.0,   -- metres around a car whose head unit is on (the external speaker)
    volume    = 0.55,   -- how loud the leak is right next to the source (0..1)
    doorsShut = 0.55,   -- multiplier when every door of the car is closed
}
