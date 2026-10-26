--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    RADIO SYSTEM - THE RADIOS
    Discord: discord.gg/nayzeeedev

    THREE MODELS  They all do the same things. They differ in how far they reach, how many
                  channels they hold at once, and how well they cope with water and jammers.
    RAISE IT      The raise key (or using the item) brings the radio up to eye level. Every key,
                  knob and the side button on the model works with a mouse click, and the
                  keyboard works too while it is up: 0-9, Backspace, Enter and the arrow keys.
    SLOTS         A radio listens to every channel in its slots at once. You talk on one of
                  them (the TX slot). Up/Down on the radio picks it.

    Vectors: vec3(x, y, z) in metres / degrees.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Radios = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- MODELS
    --   range      metres at which a link between two radios of this kind fades out on
    --              flat ground (a link uses the average of both radios)
    --   slots      channels it listens to at once (max 5)
    --   jamResist  0..1, how much of a jammer's effect it shrugs off
    --   waterproof keeps working under water
    --   grip       where it sits in the right hand (bone PH_R_Hand). Tune it live with
    --              /radiogrip when Config.Debug is on, then paste the line it prints.
    -- ═══════════════════════════════════════════════════════════════════════

    Models = {
        handheld = {
            label      = 'PX-740 Patrol',
            range      = 2600.0,
            slots      = 3,
            jamResist  = 0.0,
            waterproof = false,
            grip       = { pos = vec3(0.045, 0.015, -0.025), rot = vec3(-75.0, 0.0, 165.0) },
        },
        fieldpro = {
            label      = 'FX-280 Field',
            range      = 4200.0,
            slots      = 4,
            jamResist  = 0.15,
            waterproof = true,
            grip       = { pos = vec3(0.045, 0.012, -0.020), rot = vec3(-75.0, 0.0, 165.0) },
        },
        military = {
            label      = 'MX-905 Tactical',
            range      = 6500.0,
            slots      = 5,
            jamResist  = 0.40,
            waterproof = true,
            grip       = { pos = vec3(0.050, 0.018, -0.030), rot = vec3(-75.0, 0.0, 165.0) },
        },
    },

    -- Which radio a player uses when they own more than one and haven't picked one by
    -- using its item: the first one they own in this list.
    Priority = { 'military', 'fieldpro', 'handheld' },

    presets   = 6,        -- memory presets per character (saved in the database)
    callsign  = 8,        -- max callsign length, false = no /callsign
    volume    = 60,       -- default volume (0-100), players change it on the radio

    -- ═══════════════════════════════════════════════════════════════════════
    -- TALKING
    -- ═══════════════════════════════════════════════════════════════════════

    Talk = {
        anim      = { dict = 'random@arrests', clip = 'generic_radio_chatter' },  -- while you hold PTT without the radio up
        showProp  = false,    -- also put the radio in your hand while talking
        whileDead = false,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RAISED (the first person view)
    -- ═══════════════════════════════════════════════════════════════════════

    Interact = {
        anim        = { dict = 'cellphone@', clip = 'cellphone_text_read_base' },
        fov         = 34.0,     -- camera field of view while the radio is up
        fovMin      = 22.0,     -- mouse wheel zoom limits
        fovMax      = 46.0,
        parallax    = true,     -- the view follows the cursor a little
        highlight   = true,     -- faint outline around the button under the cursor
        repeatDelay = 450,      -- ms: hold an arrow or a knob this long and it starts repeating
        repeatRate  = 120,      -- ms between repeats
        hideRadar   = true,     -- hide the minimap while the radio is up
    },
}
