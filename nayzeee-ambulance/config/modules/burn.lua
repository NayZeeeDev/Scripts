--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - BURN CARE & SKIN GRAFT
    Discord: discord.gg/nayzeeedev

    Burn care (all burns): cool the burn with saline under a thermal camera, test the depth
    with a diascope, debride blisters and dead skin, then dress it.
    Skin graft (full-thickness burns): excise the eschar, harvest a graft from the thigh with
    a dermatome, mesh it, staple it over the bed and dress it.

    Items:  burn care  Config.Items.saline + .burn_dressing (needed)
                       Config.Items.dressing (optional - secures the dressing on large burns)
            graft      Config.Items.graft_kit (+ .burn_dressing when the graft is not done
                       straight after burn care)
    Opened from: the Examination screen ("Injuries to treat"), the patient interaction menu,
    the EMS radial menu (Patient), or by using the burn dressing / graft kit item.
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

    -- Items checked when burn care starts (Config.Items key → count), taken on finish
    items = {
        saline        = 1,   -- cooling / irrigation saline (two 250 mL bottles of the minigame)
        burn_dressing = 1,   -- hydrogel burn dressing
    },
    -- Optional supplies: taken on finish only when they were used (and the medic still has them)
    optional = {
        dressing = 1,        -- sterile dressing that secures the burn dressing on large burns
    },
    secureAbove = 60,        -- cm²: burns this large are secured with a sterile dressing when the medic has one

    -- ═══════════════════════════════════════════════════════════════════════
    -- SKIN GRAFT (procedure 'graft')
    -- ═══════════════════════════════════════════════════════════════════════

    Graft = {
        perm      = 'graft',     -- permission needed
        minTime   = 30,          -- seconds; finishing faster is rejected
        maxTime   = 1200,        -- seconds before the session times out
        easyTime  = 12,          -- seconds of progress bar in easy mode
        maxDist   = 3.0,         -- metres the surgeon may be from the patient

        -- Items checked when the graft starts, taken on finish
        items = {
            graft_kit     = 1,   -- dermatome, mesher and skin stapler
            burn_dressing = 1,   -- final dressing (not needed when continuing straight from burn care)
        },

        -- Where the patient must be (skipped in easy mode: then only the supplies are needed)
        requireLocation = true,
        locations = { surgery = true, bay = true, bed = false },   -- hospital point types / ambulance bay

        needCare       = true,   -- the burn must have been cooled and debrided first
        continueWindow = 180,    -- seconds after burn care in which "continue to graft" counts as the same treatment

        donorRegions  = { 'l_upper_leg', 'r_upper_leg' },  -- donor thigh (the side away from the burn is preferred)
        donorInjury   = true,    -- record the donor site as a dressed graze that heals by itself

        bloodPerCm2      = 0.9,  -- mL of blood lost per cm² of excised eschar
        donorBloodPerCm2 = 0.3,  -- mL of blood lost per cm² of donor site
        maxBlood         = 600,  -- mL at most taken from the patient by one graft

        minCoverage = 0.7,       -- part of the excised bed the graft must cover to count as grafted
        minStaples  = 0.6,       -- part of the staple points that must be stapled
        minExcised  = 0.7,       -- part of the full-thickness eschar that must be excised
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

    interact   = true,       -- "Burn care" in the patient interaction menu
    radial     = true,       -- "Burn care" under Patient in the EMS radial menu
    usableItem = true,       -- using the burn dressing / graft kit item starts it on the nearest patient
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

        -- 2 · assess
        assessCover = 0.6,       -- part of the burn that must be tested with the diascope
        pressTime   = 0.55,      -- seconds of pressing per test

        -- 3 · debride
        pullMm      = 7,         -- mm a blister roof / dead skin must be pulled away to come off

        -- 4 · excise
        traceTol    = 3.0,       -- mm the knife may stray from the marked line
        traceDone   = 0.92,      -- part of each outline that must be cut

        -- 5 · harvest
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
