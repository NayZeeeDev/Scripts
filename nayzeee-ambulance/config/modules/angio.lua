--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - ANGIOGRAPHY (find and coil internal bleeding)
    Discord: discord.gg/nayzeeedev

    The angiography suite is built in game (/nzadmin → Hospitals → Points →
    "Angiography suite"). You place the TABLE; the injector tray, the red
    contrast button and the boom monitor are placed around it automatically
    using the layout below (offsets are metres in the table's own space:
    +X = right side of the table, +Y = head end, +Z = up).

    Items:  Config.Items.angio_kit, Config.Items.contrast, Config.Items.coil
    Props:  Config.Props.injector, .contrast_button, .angio_monitor (+ optional table)
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Angio = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- PROCEDURE
    -- ═══════════════════════════════════════════════════════════════════════

    perm      = 'angio',     -- permission needed (department grades grant it)
    minTime   = 45,          -- seconds; finishing faster is rejected (anti-cheat)
    maxTime   = 1200,        -- seconds before the session times out
    easyTime  = 20,          -- seconds of progress bar in easy mode
    maxDist   = 6.0,         -- metres the medic may walk away from the patient (the button is a few metres away)

    -- Items checked when the procedure starts. Extra coils / contrast bottles are
    -- taken the moment you use them during the procedure.
    items = {
        angio_kit = 1,       -- Config.Items key → count (sheath, wire, catheter)
        contrast  = 1,       -- first bottle of dye
        coil      = 1,       -- first coil
    },
    consume   = 'finish',    -- 'start' | 'finish' - when the items above are taken

    -- Injuries this procedure treats
    organs    = { spleen = true, liver = true, kidney = true, bowel = true, mesenteric = true, pelvic = true, femoral = true },
    fractures = { pelvis = true, l_upper_leg = true, r_upper_leg = true },   -- bleeding fractures of these regions
    minFractureBleed = 1.0,  -- mL/min a fracture must bleed to be worth coiling

    -- Where the patient must be (skipped in easy mode: then only the supplies are needed)
    requireSuite = true,     -- patient must lie on an angiography table (placed by the transport module)

    -- ═══════════════════════════════════════════════════════════════════════
    -- GAMEPLAY
    -- ═══════════════════════════════════════════════════════════════════════

    contrastPerItem = 100,   -- mL of dye in one contrast bottle
    runMl     = 18,          -- mL used by a full contrast run
    selectiveMl = 8,         -- mL used by a run from a small branch
    puffMl    = 3,           -- mL used by a test puff
    coilDist  = 2.0,         -- cm: the coil must be released this close to the bleed
    maxCoils  = 6,           -- coils allowed in one procedure
    holdTime  = { femoral = 12, radial = 6 },  -- seconds of manual pressure to close the access site
    catheterSpeed = 4.0,     -- cm per second while holding advance (Shift = ×2)
    parContrast = 45,        -- mL of dye a clean case should need (less = no penalty)
    parFluoro   = 150,       -- seconds of fluoroscopy a clean case should need

    -- ═══════════════════════════════════════════════════════════════════════
    -- RESULT
    -- ═══════════════════════════════════════════════════════════════════════

    price     = 2500,        -- billed to a player patient (insurance applies); 0 = free
    healBoost = 10,          -- heal points added to the coiled injury straight away

    -- ═══════════════════════════════════════════════════════════════════════
    -- THE SUITE (point type 'angio')
    -- ═══════════════════════════════════════════════════════════════════════

    suite = {
        -- Config.Props key of the table model spawned at the point, or false when the
        -- map (MLO) already has a table and you only want the equipment around it
        table = 'xray_table',

        -- Equipment placed around the table. pos = vector3 in table space, h = heading
        -- relative to the table. Set an entry to false to leave that piece out.
        -- Per point you can override any entry in the builder data: data.layout.monitor = { pos, h }
        layout = {
            monitor  = { prop = 'angio_monitor',   pos = vector3(-1.05, 0.35, 0.0), h = 270.0 },  -- across the table, facing the operator
            injector = { prop = 'injector',        pos = vector3(0.95, -0.85, 0.0), h = 90.0 },   -- tray beside the legs
            button   = { prop = 'contrast_button', pos = vector3(1.05, 0.30, 0.0), h = 90.0 },    -- red button pedestal
        },
        operator = vector3(0.70, -0.20, 0.0),   -- where the medic stands (table space)
        lie      = vector3(0.0, 0.0, 1.0),      -- patient position on the table (used for the camera when no ped bone)

        -- Screen of the monitor model (model space). The screen faces +Y of the model.
        screen   = { pos = vector3(0.0, 0.06, 1.62), dist = 1.05, lookZ = -0.14, fov = 44.0 },

        -- Optional moving plunger for the power injector (a separate prop). nil = no plunger
        -- animation (the injector still shows the dose counter in the world).
        plunger  = { prop = 'injector_plunger', pos = vector3(0.0, 0.10, 0.98), travel = 0.12 },

        -- Camera framing the injector during a contrast run (injector model space)
        injectorCam = { pos = vector3(-0.55, -0.55, 1.45), look = vector3(0.0, 0.0, 1.0), fov = 40.0 },
        overviewCam = { pos = vector3(1.6, -1.6, 2.1), look = vector3(0.0, 0.2, 0.9), fov = 52.0 },   -- table space
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- FLUOROSCOPY SCREEN (DUI on the boom monitor)
    -- ═══════════════════════════════════════════════════════════════════════

    dui = {
        enabled = true,      -- false = always draw the fluoroscopy in the overlay instead
        width   = 1280,
        height  = 720,
        rate    = 50,        -- ms between screen updates sent to the monitor
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ACCESS SITES (camera + needle prop), ped bone ids
    -- ═══════════════════════════════════════════════════════════════════════

    access = {
        femoral_r = { bone = 51826, offset = vector3(0.04, 0.10, 0.0), radial = false },   -- right groin
        femoral_l = { bone = 58271, offset = vector3(0.04, 0.10, 0.0), radial = false },   -- left groin
        radial    = { bone = 28252, offset = vector3(0.20, 0.0, 0.0),  radial = true },    -- right wrist
    },
    accessCam = { dist = 0.55, height = 0.42, fov = 38.0 },
    needleProp = 'syringe',  -- Config.Props key shown in the access site while the needle is in

    -- ═══════════════════════════════════════════════════════════════════════
    -- ANIMATIONS
    -- ═══════════════════════════════════════════════════════════════════════

    anims = {
        work  = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 },
        press = { dict = 'anim@mp_player_intmenu@key_fob@', clip = 'fob_click', flag = 48 },
        hold  = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- KEYS (only used while the NUI is not focused: room mode)
    -- ═══════════════════════════════════════════════════════════════════════

    keys = {
        roomBack = 20,       -- Z  - back to the monitor
        press    = 38,       -- E  - press the contrast button
    },
    buttonDistance = 1.3,    -- metres from the button to press it
}
