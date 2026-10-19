--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - BULLET / FRAGMENT EXTRACTION (surgery)
    Discord: discord.gg/nayzeeedev

    Remove a retained bullet or shrapnel in a draped surgical field (full-screen 3D):
    locate (probe or X-ray film) → disinfect → incise → expose → extract → control the
    bleeding → suture → dressing. The patient loses blood while the wound is open.

    Items:  Config.Items.iodine (always used), .surgical_kit, .gauze, .suture_kit,
            .dressing (must be carried; taken when they are used), .xray_film (optional:
            a film of this patient's region shows where the fragments are)
    Where:  on an operating table (hospital point 'surgery') or in an ambulance treatment
            bay - easy mode skips the location rule and only needs the supplies.
    Opened from: the examination screen, the patient interaction menu, the
            'Operate' option on the operating table, or by using the surgical kit item.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Bullet = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- PROCEDURE
    -- ═══════════════════════════════════════════════════════════════════════

    perm      = 'surgery',   -- permission needed (department grades grant it)
    minTime   = 45,          -- seconds; finishing faster is rejected (anti-cheat)
    maxTime   = 1500,        -- seconds before the session times out
    easyTime  = 15,          -- seconds of progress bar in easy mode
    maxDist   = 3.0,         -- metres the medic may be from the patient
    allowSelf = false,       -- may a surgeon operate on themselves

    -- Taken on finish every time (Config.Items key → count)
    items = {
        iodine = 1,          -- antiseptic swab (opened as soon as the site is prepped)
    },
    -- Must be carried to start; each one is only taken when it was really used
    supplies = {
        surgical_kit = 1,    -- probe, scalpel, forceps, suction (kept unless consumeKit = true)
        gauze        = 1,    -- at least one swab; more are used when the medic opens them
        suture_kit   = 1,    -- taken when the incision was stitched
        dressing     = 1,    -- taken when the dressing went on
    },
    consumeKit = false,      -- true = the surgical kit is single-use and taken on finish
    gauzeMax   = 6,          -- most gauze swabs the medic can open in one operation

    -- Wound types this procedure treats (must still hold a retained fragment)
    types = {
        gunshot  = true,
        shrapnel = true,
    },

    -- Where the patient must be (skipped in easy mode: then only the supplies are needed)
    requireLocation = true,  -- false = can be done anywhere (field surgery)
    locations = { surgery = true, bay = true },   -- operating table point / ambulance treatment bay

    -- ═══════════════════════════════════════════════════════════════════════
    -- PATIENT
    -- ═══════════════════════════════════════════════════════════════════════

    Blood = {
        warnBelow   = 85,    -- % blood volume under which the surgeon is warned to start blood before cutting
        base        = 45,    -- mL a clean operation costs
        perFragment = 20,    -- extra mL for every fragment taken out
        poorWork    = 220,   -- extra mL at a score of 0 (scaled by how bad the work was)
        min         = 15,    -- the client's live estimate is clamped to min .. max mL
        max         = 900,
        easy        = 110,   -- mL lost in easy mode
        perMinute   = 160,   -- most mL a stopped operation can have cost per minute it ran
    },
    Bleed = {
        controlled = 0.3,    -- injury base bleed × this when the bleeding was controlled before closing
        open       = 0.7,    -- × this when the wound was closed while still bleeding
    },
    Infection = {
        prepKeeps  = 0.15,   -- contamination × this after a full iodine prep (scaled by coverage)
        noPrep     = 30,     -- contamination added when the site was cut without a prep
        leftPieces = 15,     -- contamination added per fragment left inside
    },
    numbed = { 'lidocaine', 'morphine' },   -- active medications that count as "numbed" (fewer flinches)

    -- Fragments are generated from the wound (the same every time for the same wound)
    Fragments = {
        bulletSize = { 8.5, 11.5 },  -- mm, a deformed bullet
        shardSize  = { 3.0, 6.5 },   -- mm, a shrapnel piece
        spread     = 11,     -- mm a piece may sit away from the entry wound
        lodge      = 0.3,    -- chance a piece is lodged (must be rocked free with A / D)
        maxPieces  = 5,      -- most pieces shown in one operation (the rest stay retained)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- INTERACTION
    -- ═══════════════════════════════════════════════════════════════════════

    interact   = true,       -- "Remove projectile" in the patient interaction menu
    radial     = true,       -- EMS radial → Patient → "Remove projectile" (patient on a nearby operating table)
    usableItem = true,       -- using the surgical kit item starts it on the nearest patient
    useRange   = 3.0,        -- metres to look for a patient when the item is used
    order      = 63,         -- position in the interaction menu (60s = procedures)

    -- Skin tones for the close-up (0 light .. 1 dark), picked per patient from their id
    skinTones  = { 0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88 },

    -- ═══════════════════════════════════════════════════════════════════════
    -- OPERATING TABLE (hospital point type 'surgery', placed with the builder)
    -- ═══════════════════════════════════════════════════════════════════════

    Table = {
        model     = 'v_med_emptybed',   -- table model spawned at the point (false = use the map's own table:
                                        -- then place the point on the table top)
        lie       = vec3(0.0, 0.0, 0.62), -- where the patient lies, from the point (point space, metres)
        tray      = 'surgery_tray',     -- Config.Props key of the instrument tray (false = none)
        trayPos   = vec3(1.05, 0.15, 0.0), -- tray offset from the point (+X right of the table, +Y head end)
        trayHeading = 90.0,             -- tray heading relative to the point
        lamp      = true,               -- warm operating light over the table (a local light)
        lampPos   = vec3(0.0, 0.1, 2.1),
        lampColor = { 255, 244, 226 },
        lampRange = 3.2,
        lampIntensity = 3.0,
        range     = 1.8,                -- metres from the table top a lying patient counts as "on the table"
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- MINIGAME (sent to the NUI - every value has a sane default in the app)
    -- ═══════════════════════════════════════════════════════════════════════

    Game = {
        quality      = 'high',   -- 3D detail: 'high' | 'medium' | 'low'; capped by Config.UI.quality3d ('auto' = medium in game)

        -- 1 · locate
        probeSpeed   = 8,        -- mm per second the probe slides down a clean track
        probeSlow    = 0.3,      -- speed factor at the edge of the track
        trackRadius  = 4.5,      -- mm from the entry hole that counts as "in the wound"
        steerTol     = 1.8,      -- mm off the track before it resists
        steerFail    = 4.4,      -- mm off the track = false passage (blood, pain)
        palpateDepth = 12,       -- pieces this shallow can be felt through intact skin
        palpateTol   = 3,        -- mm around a piece where pressing still feels it

        -- 2 · disinfect
        prepRadius   = 24,       -- mm radius of the area to prep
        swabRadius   = 4.4,      -- mm the swab paints around the cursor
        swabReach    = 320,      -- mm of scrubbing per swab before it is dry
        redipTime    = 0.6,      -- seconds to take a fresh swab
        prepDone     = 0.97,     -- coverage that completes the step

        -- 3 · incise
        bladeMin     = 2,        -- mm blade depth range (Q / E)
        bladeMax     = 16,
        bladeStart   = 5,
        minCut       = 8,        -- mm shortest incision accepted
        coverTol     = 4,        -- mm a fragment may sit beside the cut and still be under it
        cutFast      = 75,       -- mm/s above which the cut turns ragged

        -- 4 · expose
        spreadTime   = 1.5,      -- seconds of Space to open the edges fully
        tearAt       = 1.15,     -- spread above this tears the tissue
        exposeSpread = 0.7,      -- spread needed to see the fragment
        exposeBlood  = 0.42,     -- blood film over the fragment that still counts as "seen"

        -- 5 · extract
        grabTol      = 2.4,      -- mm around a fragment where the jaws still catch it
        pullSafe     = 0.16,     -- traction speed (screen heights / s) that is safe
        pullSlip     = 0.36,     -- traction speed that makes it slip and tear
        pullDist     = 0.24,     -- screen heights of mouse travel to draw a piece out
        gripLoss     = 5,        -- how fast the grip weakens while pulling too fast
        rocks        = 3,        -- A / D alternations to free a lodged piece

        -- 6 · control bleeding
        bleedDone    = 1.5,      -- mL/min that counts as controlled
        pressRate    = 0.24,     -- how fast pressure on the bleeding point slows it
        pressRadius  = 10,       -- mm from the bleeding point where pressure works
        gauzeRadius  = 13,       -- mm blotted around the cursor
        gauzeCapacity = 140,     -- blood one swab soaks up before a fresh one is opened
        suctionRadius = 3.6,     -- mm the suction tip clears

        -- 7 · suture (same mechanics as the suture app)
        mmPerStitch  = 8,
        minStitches  = 2,
        maxStitches  = 7,
        extraStitches = 2,
        bite         = 4,
        biteMin      = 1.2,
        biteMax      = 9.5,
        minDrag      = 0.3,

        -- 8 · dressing
        stuckDone    = 0.92,
        coverMin     = 0.85,
        layTime      = 0.45,     -- seconds the held edge takes to come down to the skin after letting go

        -- pain
        flinchPain   = 40,       -- pain % above which painful moves can make the patient flinch
        flinchChance = 0.5,

        -- score weights (total 100)
        weights = { locate = 10, disinfect = 10, incise = 15, expose = 10, extract = 25, haemostasis = 10, suture = 12, dressing = 8 },

        fallbackTime = 18,       -- seconds of the simple progress bar on clients without WebGL2
    },
}
