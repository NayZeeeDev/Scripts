--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - ANGIOGRAPHY (find and coil internal bleeding)
    Discord: discord.gg/nayzeeedev

    The angiography suite is built in game (builder → Points → "Angiography
    suite"). You place the TABLE; the boom monitor, the power injector tray and
    the red contrast button are placed around it automatically with the layout
    below (offsets are metres in the table's own space: +X = the table's right
    side, +Y = the head end, +Z = up from the floor).

    Items:  Config.Items.angio_kit, Config.Items.contrast, Config.Items.coil
    Props:  Config.Props.injector, .contrast_button, .angio_monitor, .xray_table
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
    maxDist   = 6.0,         -- metres the medic may be from the patient (the red button is a few metres away)

    -- Items checked when the procedure starts (Config.Items key → count).
    -- Extra coils / contrast bottles are taken the moment they are used.
    items = {
        angio_kit = 1,       -- sheath, wire and catheter
        contrast  = 1,       -- first bottle of dye
        coil      = 1,       -- first coil
    },
    consume   = 'finish',    -- 'start' | 'finish' - when the items above are taken

    -- Injuries this procedure treats
    organs    = { spleen = true, liver = true, kidney = true, bowel = true, mesenteric = true, pelvic = true, femoral = true },
    fractures = { pelvis = true, l_upper_leg = true, r_upper_leg = true },   -- bleeding fractures of these regions
    minFractureBleed = 1.0,  -- mL/min a fracture must bleed to be worth coiling

    -- Where the patient must be (skipped in easy mode: then only the supplies are needed)
    requireSuite = true,     -- patient must lie on an angiography table (patient.meta.bed.type == 'angio')

    -- ═══════════════════════════════════════════════════════════════════════
    -- GAMEPLAY
    -- ═══════════════════════════════════════════════════════════════════════

    contrastPerItem = 100,   -- mL of dye in one contrast bottle
    runMl     = 18,          -- mL used by a full contrast run (from the aorta / iliacs)
    selectiveMl = 8,         -- mL used by a run from a branch vessel
    puffMl    = 3,           -- mL used by a test puff
    coilDist  = 2.0,         -- cm: the coil must be released this close to the bleed
    maxCoils  = 6,           -- coils allowed in one procedure
    holdTime  = { femoral = 12, radial = 6 },  -- seconds of manual pressure to close the access site
    catheterSpeed = 4.0,     -- cm per second while holding advance (Shift = x2)
    parContrast = 45,        -- mL of dye a clean case should need (less = no penalty)
    parFluoro   = 150,       -- seconds of fluoroscopy a clean case should need

    -- ═══════════════════════════════════════════════════════════════════════
    -- RESULT
    -- ═══════════════════════════════════════════════════════════════════════

    price     = 2500,        -- billed to a player patient (insurance applies); 0 = free
    healBoost = 10,          -- heal points added to the coiled injury straight away

    -- ═══════════════════════════════════════════════════════════════════════
    -- WHERE IT SHOWS UP
    -- ═══════════════════════════════════════════════════════════════════════

    interact  = true,        -- "Angiography" option on patients with an internal / fracture bleed
    radial    = true,        -- "Angiography" entry in the EMS radial menu (Patient)
    usable    = true,        -- using the angio kit item starts it on the nearest patient
    tableRange = 1.8,        -- metres from the table centre a patient counts as "on the table"
    speech    = true,        -- conscious patients talk during the procedure (subtitles)

    -- ═══════════════════════════════════════════════════════════════════════
    -- THE SUITE (point type 'angio')
    -- ═══════════════════════════════════════════════════════════════════════

    suite = {
        -- Config.Props key (or model name) of the table spawned at the point.
        -- false = your map (MLO) already has a table: only the equipment is placed.
        table  = 'xray_table',
        ground = true,       -- place the table and the equipment on the floor

        -- Equipment around the table. prop = Config.Props key (or model name),
        -- fallback = native model used when the custom one is not streamed,
        -- pos = table space, h = heading relative to the table, anchor = label height.
        -- Set an entry to false to leave it out. Per point the builder can override
        -- any entry: point.data.layout = { monitor = { pos = {x,y,z}, h = 0 } | false }.
        layout = {
            -- across the table, over the thighs, screen facing the operator (boom reaches over the table)
            monitor  = { prop = 'angio_monitor',   fallback = 'prop_tv_flat_01',      pos = vector3(-1.05, -0.55, 0.0), h = 270.0, anchor = vector3(0.0, 0.66, 1.90) },
            -- tray beside the legs on the operator side, syringe tip towards the table
            injector = { prop = 'injector',        fallback = 'v_med_cor_emblmtable', pos = vector3(0.95, -1.05, 0.0), h = 0.0,   anchor = vector3(0.0, 0.0, 1.20) },
            -- red button pedestal at the head end on the operator side, labels towards the table
            button   = { prop = 'contrast_button', fallback = 'prop_parknmeter_01',   pos = vector3(1.30, 0.55, 0.0),  h = 90.0,  anchor = vector3(0.0, 0.0, 1.16) },
        },
        operator = vector3(0.75, -0.25, 0.0),   -- where the medic stands (table space, at the groin)
        lie      = vector3(0.0, 0.0, 0.825),    -- patient position on the table top (for the transport module)

        -- Screen of the monitor model (monitor model space; the screen faces +Y of the model)
        screen   = { pos = vector3(0.0, 0.6585, 1.55), dist = 1.05, drop = 0.16, pitch = 2.0, fov = 42.0 },

        -- Optional moving plunger of the power injector: a separate prop placed on the
        -- injector at pos (injector model space) that slides `travel` metres along `axis`.
        -- prop must exist in Config.Props, else the injector stays still (the world label still shows).
        plunger  = { prop = 'injector_plunger', pos = vector3(0.03, 0.05, 1.04), axis = vector3(-1.0, 0.0, 0.0), travel = 0.20 },

        -- Camera on the injector after the red button (injector model space)
        injectorCam = { pos = vector3(0.0, 0.55, 1.45), look = vector3(0.0, 0.0, 1.0), fov = 40.0 },
        overviewCam = { dist = 2.7, pitch = 34.0, fov = 50.0, height = 0.15 },   -- around the patient
    },

    -- Seconds the camera shows the injector after the red button ("dye going in"),
    -- the dye reaches the screen right after. 0 = stay on the monitor.
    injectorShot = 1.6,
    injectorShotOnKey = false,   -- true = also cut to the injector on a contrast run with the key

    -- ═══════════════════════════════════════════════════════════════════════
    -- FLUOROSCOPY SCREEN (DUI on the boom monitor)
    -- ═══════════════════════════════════════════════════════════════════════

    dui = {
        enabled = true,      -- false = always draw the fluoroscopy in the overlay instead
        width   = 1280,
        height  = 720,
        linger  = 30,        -- seconds the standby screen stays on the monitor after a procedure
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ACCESS SITES (camera + needle prop), ped bone ids
    -- ═══════════════════════════════════════════════════════════════════════

    access = {
        femoral_r = { bone = 51826, offset = vector3(0.04, 0.10, 0.0), needle = { pos = vector3(0.06, 0.12, 0.02), rot = vector3(0.0, 45.0, 90.0) } },   -- right groin
        femoral_l = { bone = 58271, offset = vector3(0.04, 0.10, 0.0), needle = { pos = vector3(0.06, 0.12, -0.02), rot = vector3(0.0, 45.0, 90.0) } },  -- left groin
        radial    = { bone = 28252, offset = vector3(0.20, 0.0, 0.0), needle = { pos = vector3(0.22, 0.02, 0.0), rot = vector3(0.0, 45.0, 0.0) } },      -- right wrist
    },
    accessCam = { dist = 0.6, pitch = 52.0, fov = 38.0 },
    needleProp = 'syringe',  -- Config.Props key shown in the access site while the needle is in (false = none)

    -- ═══════════════════════════════════════════════════════════════════════
    -- ANIMATIONS
    -- ═══════════════════════════════════════════════════════════════════════

    anims = {
        work  = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 },  -- hands on the patient / catheter
        press = { dict = 'anim@mp_player_intmenu@key_fob@', clip = 'fob_click', flag = 48 },                            -- the red button
        hold  = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },                                                -- pressure on the puncture
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- KEYS (room mode: you walk around, the overlay has no focus)
    -- ═══════════════════════════════════════════════════════════════════════

    keys = {
        roomBack = 20,       -- Z - back to the monitor
        press    = 38,       -- E - press the contrast button
        pressLabel = 'E',    -- key cap shown on the button prompt (match `press`)
    },
    buttonDistance = 1.3,    -- metres from the button to press it
}
