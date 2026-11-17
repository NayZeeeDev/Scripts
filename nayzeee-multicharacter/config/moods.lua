-- ███╗   ███╗ ██████╗  ██████╗ ██████╗ ███████╗
-- ████╗ ████║██╔═══██╗██╔═══██╗██╔══██╗██╔════╝
-- ██╔████╔██║██║   ██║██║   ██║██║  ██║███████╗
-- ██║╚██╔╝██║██║   ██║██║   ██║██║  ██║╚════██║
-- ██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██████╔╝███████║
-- ╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═════╝ ╚══════╝

--[[
    Lighting / mood presets — the Mood toggle in the lobby. Saved per character.

    hour / minute   clock override (nil = keep the theme's)
    weather         weather override (nil = keep the theme's)
    timecycle       { name, strength } — replaces the theme timecycle (nil = keep theme's)
    tint            colour multiplied into every rig light (0-255)
    scale           intensity multiplier for the rig + extra lights
    swatch          two hex colours for the chip in the UI
]]

Config.Moods = {
    { id = 'golden_hour',   label = 'Golden Hour',   icon = 'sunset',
      hour = 19, minute = 30, timecycle = { name = 'NG_filmic02', strength = 0.55 },
      tint = { 255, 214, 170 }, scale = 1.0, swatch = { '#ffb36b', '#e0576b' } },

    { id = 'midnight_neon', label = 'Midnight Neon', icon = 'moon',
      hour = 0, minute = 15, timecycle = { name = 'MP_Arena_theme_night', strength = 0.6 },
      tint = { 210, 170, 255 }, scale = 1.25, swatch = { '#ff5fa2', '#7b5cff' } },

    { id = 'clean_studio',  label = 'Clean Studio',  icon = 'aperture',
      timecycle = { name = 'MP_corona_heist_DOF', strength = 0.25 },
      tint = { 255, 255, 255 }, scale = 1.4, swatch = { '#ffffff', '#9aa6b2' } },

    { id = 'moody_dusk',    label = 'Moody Dusk',    icon = 'cloud-moon',
      hour = 20, minute = 40, timecycle = { name = 'hud_def_desat_Neutral', strength = 0.35 },
      tint = { 190, 205, 255 }, scale = 0.9, swatch = { '#5b6b8c', '#1d2233' } },
}
