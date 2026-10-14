--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - BURN CARE & SKIN GRAFT
    Discord: discord.gg/nayzeeedev

    Burn care (every burn): cool the burn with saline while a wound imager shows the surface
    temperature, test the depth with a diascope, debride blisters and dead skin, then dress it.
    Skin graft (full-thickness burns): cut the eschar away, harvest a graft from the thigh with a
    dermatome, run it through the mesher, staple it over the bed and dress it.

    Supplies
      burn care   Config.Items.saline (taken) + Config.Items.burn_dressing (taken when the burn is
                  dressed here; when you go straight on to the graft the graft takes it instead)
                  Config.Items.dressing (optional: secures the burn dressing on large burns)
      graft       Config.Items.graft_kit (taken) + Config.Items.burn_dressing (taken when dressed)
    Opened from: the patient examination (treatment list), the patient interaction menu,
    the EMS radial menu (Patient), or by using the graft kit item (the burn dressing item stays
    a first-aid item: using it applies a quick dressing, see config/modules/firstaid.lua).
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Burn = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- BURN CARE (procedure 'burn')
    -- ═══════════════════════════════════════════════════════════════════════

    perm      = 'burn',      -- permission needed (department grades grant it)
    minTime   = 18,          -- seconds; finishing faster is rejected (anti-cheat)
    maxTime   = 900,         -- seconds before the session times out
    easyTime  = 10,          -- seconds of progress bar in easy mode
    maxDist   = 3.0,         -- metres the medic may be from the patient
    allowSelf = false,       -- may a medic treat their own burn

    -- Supplies (Config.Items key → count). All are checked when burn care starts.
    items = {
        saline        = 1,   -- cooling saline (the bottles of the minigame) — always taken
        burn_dressing = 1,   -- hydrogel burn dressing — taken when the burn is dressed
    },
    -- Optional supply: taken only when it was used and the medic still has it
    optional = {
        dressing = 1,        -- sterile dressing that secures the burn dressing on large burns
    },
    secureAbove = 60,        -- cm²: burns this large get the sterile dressing on top (when carried)

    -- ═══════════════════════════════════════════════════════════════════════
    -- SKIN GRAFT (procedure 'graft')
    -- ═══════════════════════════════════════════════════════════════════════

    Graft = {
        perm      = 'graft',     -- permission needed
        minTime   = 30,          -- seconds; finishing faster is rejected
        maxTime   = 1200,        -- seconds before the session times out
        easyTime  = 12,          -- seconds of progress bar in easy mode
        maxDist   = 3.0,         -- metres the surgeon may be from the patient

        -- Supplies (Config.Items key → count), checked when the graft starts
        items = {
            graft_kit     = 1,   -- dermatome blade, mesher carrier, skin stapler — always taken
            burn_dressing = 1,   -- final dressing — taken when the graft is dressed
        },

        -- Where the patient must be (ignored in easy mode: easy mode only needs the supplies)
        requireLocation = true,
        locations = { surgery = true, bay = true, bed = false },   -- hospital point types / ambulance bay

        needCare       = true,   -- the burn must be cooled and debrided first (burn care)
        continueWindow = 180,    -- seconds after burn care in which "go on to the graft" needs no new check-in

        donorRegions  = { 'l_upper_leg', 'r_upper_leg' },  -- donor thigh (the side away from the burn is used)
        donorInjury   = true,    -- record the donor site as a dressed graze that heals by itself

        bloodPerCm2      = 0.9,  -- mL of blood lost per cm² of excised eschar
        donorBloodPerCm2 = 0.3,  -- mL of blood lost per cm² of donor site
        maxBlood         = 600,  -- mL at most taken from the patient by one graft

        minCoverage = 0.7,       -- part of the excised bed the graft must cover to count as grafted
        minStaples  = 0.6,       -- part of the staple points that must be stapled
        minExcised  = 0.7,       -- part of the full-thickness eschar that must be cut away
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RESULT
    -- ═══════════════════════════════════════════════════════════════════════

    cooledBelow  = 31.0,     -- °C: the burn counts as cooled when the surface ends below this
    sootLeftMax  = 25,       -- % soot that may be left for the burn to count as cleaned
    debridedMin  = 0.75,     -- part of the blisters / dead skin that must be removed to count as debrided
    healBonus    = 12,       -- heal points (0-100) given at once by a perfect treatment (scaled by score)
    painRelief   = 0.2,      -- part of the burn's pain removed by a perfect cooling
    overcoolWet  = 8,        -- seconds of body cooling per second of over-cooling (hypothermia risk)
    overcoolMax  = 420,      -- most seconds of body cooling one treatment can cause

    -- ═══════════════════════════════════════════════════════════════════════
    -- INTERACTION
    -- ═══════════════════════════════════════════════════════════════════════

    interact   = true,       -- "Burn care" / "Skin graft" in the patient interaction menu
    radial     = true,       -- the same under Patient in the EMS radial menu
    usableItem = true,       -- using the graft kit item starts the graft (or burn care first) on the nearest patient
    useRange   = 3.0,        -- metres to look for a patient when the item is used / from the radial menu
    order      = 63,         -- position in the interaction menu (60s = procedures)

    -- Skin tones for the close-up (0 light .. 1 dark), picked from the patient id
    skinTones  = { 0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88 },

    -- ═══════════════════════════════════════════════════════════════════════
    -- MINIGAME (sent to the NUI)
    -- ═══════════════════════════════════════════════════════════════════════

    Game = {
        quality     = 'high',    -- 3D quality: 'high' | 'medium' | 'low' (lower = faster on weak PCs)

        -- 1 · cool
        bottleMl    = 250,       -- mL per saline bottle
        bottles     = 2,         -- bottles in one saline item
        salineFlow  = 14,        -- mL per second while pouring
        refillTime  = 0.9,       -- seconds to open the next bottle
        salineTemp  = 19,        -- °C of the saline
        jetRadius   = 9,         -- mm of skin the stream cools and washes around the point it hits
        target      = 31,        -- °C: bring the surface under this
        holdTime    = 1.4,       -- seconds the surface must stay under target after you stop pouring
        coolFrac    = 0.88,      -- part of the burn that must be under target
        overcool    = 24,        -- °C average: colder than this while pouring = over-cooling (hypothermia risk)
        sootDone    = 10,        -- % soot left that counts as washed off
        rebound     = 1.0,       -- how strongly the deep tissue heat warms the surface back up (0 = never)

        -- 2 · assess
        assessCover = 0.6,       -- part of the burn that must be tested with the diascope
        pressTime   = 0.55,      -- seconds of pressing per test
        diascopeMm  = 22,        -- mm: diameter of the diascope glass

        -- 3 · debride
        pullMm      = 7,         -- mm a blister roof / dead skin must be pulled away to come off

        -- 4 · excise
        traceTol    = 3.0,       -- mm the knife may stray from the marked line
        traceDone   = 0.92,      -- part of each outline that must be cut

        -- 5 · harvest
        graftWidth  = 40,        -- mm: width of the dermatome blade (the graft strip)
        speedMin    = 10,        -- mm/s: slower stalls the dermatome (uneven graft)
        speedMax    = 32,        -- mm/s: faster chatters (ragged graft)
        pressureBand = { 0.42, 0.68 },  -- good dermatome pressure (0..1); below skips, above cuts too deep
        pressureDrift = 0.32,    -- how fast the pressure drifts (your hand tires)

        -- 6 · mesh
        feedPerTurn = 14,        -- mm of graft fed through per crank turn
        crankMax    = 2.4,       -- turns per second before the graft starts to tear

        -- 7 · staple
        stapleSpacing = 11,      -- mm between staples around the graft
        stapleTol   = 3.5,       -- mm from a staple point that still counts

        -- 8 · dressing
        stuckDone   = 0.9,       -- how firmly the dressing must be pressed down
        coverMin    = 0.85,      -- part of the burn the dressing must cover

        -- score weights (each procedure totals 100)
        weights      = { cool = 35, assess = 15, debride = 25, dressing = 25 },
        graftWeights = { excise = 25, harvest = 20, mesh = 15, graft = 25, dressing = 15 },

        fallbackTime = 14,       -- seconds of the simple progress bar on clients without WebGL2
    },
}
