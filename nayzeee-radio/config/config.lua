--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
██████╗  █████╗ ██████╗ ██╗ ██████╗
██╔══██╗██╔══██╗██╔══██╗██║██╔═══██╗
██████╔╝███████║██║  ██║██║██║   ██║
██╔══██╗██╔══██║██║  ██║██║██║   ██║
██║  ██║██║  ██║██████╔╝██║╚██████╔╝
╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝ ╚═════╝

    RADIO SYSTEM - 1.0.0
    Discord: discord.gg/nayzeeedev

    This file holds the core settings. Every feature has its own file in
    config/modules/ (radios.lua, channels.lua, signal.lua, vehicles.lua, jammers.lua,
    alerts.lua, bridge.lua). Items are in config/items.lua.
    Server-only settings (webhooks, the emergency dispatch hook) are in config_server.lua.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- GENERAL
-- ═══════════════════════════════════════════════════════════════════════════

Config.Debug     = false        -- console debug prints, and /radiogrip to tune how a radio sits in the hand
Config.Locale    = 'en'
Config.Framework = 'auto'       -- 'auto' | 'esx' | 'qbcore' | 'qbox' | 'standalone'

-- The resource the radio and jammer models stream from. Only used for a startup
-- check that warns when it isn't running. false = your props live elsewhere.
Config.PropsResource = 'nayzeee-radio-props'

-- ═══════════════════════════════════════════════════════════════════════════
-- WINDOWS & HUD (the NUI: admin panel, roster, head unit, hack, notifications)
-- ═══════════════════════════════════════════════════════════════════════════

Config.UI = {
    font      = 'Lexend',  -- 'Lexend' ships with the resource (works offline)
    shape     = 'cut',     -- window silhouette: cut twin mirror bevel crest flip step blade notch round
    scale     = 1.0,       -- 0.8 - 1.2, on top of the automatic scale for the screen height
    sounds    = true,      -- soft clicks on notifications (radio sounds are in config/modules/signal.lua)
    signature = true,      -- small NAYZEEE signature on windows (never on the radios themselves)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ADMIN
-- ═══════════════════════════════════════════════════════════════════════════

Config.Admin = {
    ace    = 'nzr.admin',                       -- add_ace group.admin nzr.admin allow
    groups = { 'admin', 'god', 'superadmin' },  -- framework admin groups that also count
}

Config.Commands = {
    admin    = 'radioadmin',   -- channel locks, radio vehicles, live channels and jammers (admins)
    radio    = 'radio',        -- raise the radio (same as the key)
    callsign = 'callsign',     -- /callsign 1G-12   (shown next to your name in the roster)
    range    = 'radiorange',   -- shows how far your radio reaches on the map for a few seconds
    grip     = 'radiogrip',    -- /radiogrip x y z rx ry rz  (only with Config.Debug or the admin ace)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYS
-- ═══════════════════════════════════════════════════════════════════════════

-- Default keys. Every one is a FiveM key mapping: players can rebind them in
-- Settings > Key Bindings > FiveM. '' = no default key (the binding still exists).
Config.Keys = {
    ptt       = 'CAPITAL',  -- hold to talk on your TX channel (Caps Lock; Left Alt clashes with ox_target and pma-voice)
    raise     = 'F10',      -- raise the radio in front of you (in a radio car: open the head unit)
    handsfree = '',         -- toggle an open mic
    mute      = '',         -- mute / unmute everything you receive
    nextSlot  = '',         -- talk on the next channel slot
    roster    = '',         -- show / hide the channel roster
    emergency = '',         -- hold for the emergency alert (same as the orange button)
}
