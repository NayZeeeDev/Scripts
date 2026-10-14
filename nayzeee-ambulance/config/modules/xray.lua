--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - RADIOLOGY (X-ray room, films, lightbox, fracture care)
    Discord: discord.gg/nayzeeedev

    Build the room in game (/nzadmin → Hospitals → Points):
      "X-ray table"  the patient is laid on it (stretcher / carry → place on table)
      "Lightbox"     film viewer: use an X-ray film item near it to read the film

    Flow: X-ray the patient on the table → you get an X-ray film item (AP + lateral
    film of that body part, built from the patient's real injuries) → read it on a
    lightbox and pin every break / fragment → the diagnosis is confirmed in the
    examination → set displaced bones ("Set the bone") → apply a cast.

    Easy mode (per department, or Config.EasyMode.default) turns every step into a
    progress bar and skips the room / lightbox requirements - only the supplies of
    the treatment are needed.

    Items:  Config.Items.xray_film, Config.Items.cast, Config.Items.crutches (+ optional lidocaine)
    Props:  Config.Props.xray_table, Config.Props.lightbox
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Xray = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- TAKING AN X-RAY
    -- ═══════════════════════════════════════════════════════════════════════

    Take = {
        perm        = 'xray',      -- permission needed to take X-rays
        minTime     = 5,           -- seconds the exposure takes at least (anti-cheat)
        maxTime     = 90,          -- seconds before the session times out
        easyTime    = 6,           -- seconds of progress bar in easy mode
        maxDist     = 7.0,         -- metres the radiographer may stand from the patient (steps back to expose)
        states      = { alive = true, wounded = true },   -- patient states you may X-ray
        requireTable = true,       -- the patient must lie on an X-ray table (skipped in easy mode)
        tableRadius = 1.6,         -- metres from the X-ray table point that count as "on the table"
        easyAnywhere = true,       -- easy mode: X-ray options also show on patients that are not on a table
        stepBack    = 2.6,         -- metres the radiographer walks back before exposing (0 = stay)
        breathHold  = true,        -- chest / abdomen films: ask the patient to hold their breath first (else motion blur)
        breathWindow = 5.0,        -- seconds the patient can hold the breath
        camera      = true,        -- orbit camera on the table while exposing
        maxFilms    = 30,          -- most films one player may carry (0 = no limit)
        cooldown    = 4,           -- seconds between two X-rays by the same radiographer
        notifyPatient = true,      -- player patients get a toast "radiology took an X-ray of your chest"
        settings = {               -- console values shown per view (cosmetic, kVp / mAs)
            head = { 75, 20 }, neck = { 70, 16 }, chest = { 110, 4 }, abdomen = { 80, 32 },
            l_arm = { 60, 6 }, r_arm = { 60, 6 }, l_leg = { 65, 10 }, r_leg = { 65, 10 },
        },
        flash = { range = 4.0, intensity = 12.0, ms = 140 },   -- in-world light flash on exposure
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- READING FILMS (lightbox)
    -- ═══════════════════════════════════════════════════════════════════════

    Read = {
        perm        = 'xray',      -- permission needed to read (mark) a film
        viewWithoutPerm = true,    -- anyone else may still look at a film (no marking, no diagnosis)
        requireLightbox = true,    -- reading needs a lightbox point nearby (skipped in easy mode)
        lightboxDistance = 3.0,    -- metres from the lightbox point
        minTime     = 8,           -- seconds a reading takes at least (anti-cheat)
        maxTime     = 600,         -- seconds before the reading session expires
        easyTime    = 8,           -- seconds of progress bar in easy mode
        tolerance   = 0.06,        -- how close a pin must be to a break (fraction of the film width)
        falsePin    = 12,          -- score lost per pin that marks nothing
        confirmScore = 50,         -- a finding needs a pin on BOTH films (AP + lateral) to confirm the diagnosis;
                                   -- the whole reading must also score at least this
        measureBonus = 8,          -- extra score for measuring a displaced fracture's angle within measureTolerance
        measureTolerance = 5,      -- degrees
        cooldown    = 6,           -- seconds between two readings
        camera      = true,        -- look at the lightbox prop while reading
        cameraOffset = vector3(0.0, 0.15, 1.47), -- point the camera looks at, relative to the lightbox prop (centre of the light panel)
        cameraDist  = 0.95,        -- metres in front of the lightbox
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- HELP OFF THE TABLE
    -- ═══════════════════════════════════════════════════════════════════════

    OffTable = {
        enabled     = true,        -- 'Help patient off the table' option (the transport module's own option is used when it has one)
        perm        = nil,         -- nil = any medic who may X-ray or transport ('xray' or 'transport')
        getUpAnim   = { dict = 'get_up@directional@movement@from_knees@action', clip = 'getup_r_0' },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- SET THE BONE (closed reduction of a displaced fracture)
    -- ═══════════════════════════════════════════════════════════════════════

    Reduce = {
        perm        = 'splint',    -- permission needed
        minTime     = 14,          -- seconds (anti-cheat)
        maxTime     = 300,
        easyTime    = 10,
        maxDist     = 3.0,
        requireXray = true,        -- the fracture must be on a read film first (skipped in easy mode)
        requireHospital = true,    -- patient on a hospital point (bed, X-ray table, surgery...) - skipped in easy mode
        tolerance   = 3,           -- degrees left after setting that still count as reduced
        regions     = { l_upper_arm = true, l_lower_arm = true, r_upper_arm = true, r_lower_arm = true,
                        l_upper_leg = true, l_lower_leg = true, r_upper_leg = true, r_lower_leg = true },
        items       = {},          -- Config.Items key → count taken when the bone is set, e.g. { lidocaine = 1 }
        analgesia   = { morphine = 0.45, lidocaine = 0.35, painkillers = 0.15 },  -- active med → pain reduction while pulling
        painSpike   = 25,          -- pain added to the injury for a while when the medic pulls far too hard
        fluoroBudget = 12,         -- seconds of live fluoro before the dose starts costing score
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CAST
    -- ═══════════════════════════════════════════════════════════════════════

    Cast = {
        perm        = 'splint',
        minTime     = 14,
        maxTime     = 300,
        easyTime    = 10,
        maxDist     = 3.0,
        requireHospital = true,    -- patient on a hospital point (skipped in easy mode)
        regions     = { l_upper_arm = true, l_lower_arm = true, r_upper_arm = true, r_lower_arm = true,
                        l_upper_leg = true, l_lower_leg = true, r_upper_leg = true, r_lower_leg = true },
        openNeedsWoundCare = true, -- open fractures must be cleaned / closed first (irrigated, sutured, dressed or bandaged)
        layers      = { 3, 6 },    -- plaster layers that make a good cast (min, max)
        healBoost   = 15,          -- heal points added at once (× score/100)
        removeSplint = true,       -- the cast replaces a splint on that limb
        crutches    = 'recommend', -- leg casts: 'recommend' (toast), 'give' (player patients get Config.Items.crutches) or false
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BILLING (player patients; Config.Billing applies; 0 = free)
    -- ═══════════════════════════════════════════════════════════════════════

    Billing = {
        take   = 250,              -- per film
        read   = 0,                -- per reading
        reduce = 450,              -- setting a bone
        cast   = 300,              -- applying a cast
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RADIAL MENU (EMS job menu)
    -- ═══════════════════════════════════════════════════════════════════════

    Radial = {
        enabled = true,            -- 'Take X-ray' (patient on a table nearby) and 'Read X-ray film' (near a lightbox)
        range   = 3.0,             -- metres to the patient / lightbox
    },

    -- Film id prefix (A2034, A2035, ...). The counter is stored in the server KVP.
    filmPrefix = 'A',
    filmStart  = 2034,

    -- Keys inside the NUI minigames (KeyboardEvent.code names)
    keys = {
        move = 'Digit1', mark = 'Digit2', measure = 'Digit3', switch = 'KeyF', contrast = 'KeyC',
        reset = 'KeyR', light = 'KeyL', normal = 'KeyN', submit = 'Enter',
        expose = 'Space', breath = 'KeyB', fluoro = 'KeyF', mould = 'Space',
    },
}
