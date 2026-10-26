--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    RADIO SYSTEM - VEHICLE HEAD UNITS
    Discord: discord.gg/nayzeeedev

    Radio cars get a head unit in the dash. Sit in the driver or front passenger seat and
    press the raise key to work it: type a frequency, PRE cycles your presets, MUT mutes the
    speaker, PWR switches it, EMERG sends the emergency alert. Everyone in the car hears it,
    people standing next to the car hear it through the external speaker, and the
    passengers get a small HUD.

    More vehicles can be added in game: /radioadmin → Vehicles.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Vehicles = {
    enabled     = true,
    classes     = { 18 },     -- vehicle classes with a head unit (18 = emergency)
    models      = { 'police', 'police2', 'police3', 'police4', 'policeb', 'policet', 'sheriff', 'sheriff2',
                    'fbi', 'fbi2', 'pranger', 'riot', 'ambulance', 'firetruk' },
    seats       = { -1, 0 },  -- who can work the head unit (-1 driver, 0 front passenger)
    range       = 7000.0,     -- metres, the car aerial reaches further than a handheld
    pttPriority = true,       -- in those seats with the head unit on, PTT talks through the car
    carVolume   = 0.75,       -- volume inside the car at full head unit volume
    hud         = true,       -- mini HUD for everyone in the car while the head unit is on
    ambient     = { enabled = true, volume = 0.25 },   -- faint hiss and squelch in the cabin
}
