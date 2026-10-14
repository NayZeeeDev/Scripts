--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - SUTURE (wound closure)
    Discord: discord.gg/nayzeeedev

    Irrigate, numb, stitch and dress a laceration or stab wound in a full-screen
    3D close-up. Gunshot / shrapnel wounds can be closed the same way once the
    bullet is out and the bleeding is controlled.

    Items:  Config.Items.suture_kit, .saline, .dressing (needed)
            Config.Items.lidocaine, .gauze (optional - used only when the medic uses them)
    Opened from: the Examination screen ("Injuries to treat"), the patient
    interaction menu, or by using the suture kit item next to a patient.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Suture = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- PROCEDURE
    -- ═══════════════════════════════════════════════════════════════════════

    perm      = 'suture',    -- permission needed (department grades grant it)
    minTime   = 25,          -- seconds; finishing faster is rejected (anti-cheat)
    maxTime   = 900,         -- seconds before the session times out
    easyTime  = 12,          -- seconds of progress bar in easy mode
    maxDist   = 3.0,         -- metres the medic may be from the patient
    allowSelf = false,       -- may a medic suture their own wound

    -- Items checked when the procedure starts (Config.Items key → count), taken on finish
    items = {
        suture_kit = 1,      -- needle, thread, needle driver
        saline     = 1,      -- irrigation saline (one bottle = the saline supply below)
        dressing   = 1,      -- sterile adhesive dressing
    },
    -- Optional supplies: taken on finish only if the medic actually used them (and still has them)
    optional = {
        lidocaine = 1,       -- local anaesthetic (one item = one 5 mL syringe)
        gauze     = 6,       -- most gauze swabs that can be used to blot blood
    },

    -- Wound types this procedure closes.  true = always,  'controlled' = only once the
    -- object is out (retained = 0) and the bleeding is controlled (see below)
    types = {
        laceration = true,
        stab       = true,
        gunshot    = 'controlled',
        shrapnel   = 'controlled',
    },

    -- "Bleeding controlled": the injury bleeds less than this, or has been packed / bandaged /
    -- has a tourniquet. Small wounds (severity <= smallSeverity) can always be closed.
    maxBleed      = 12.0,    -- mL/min
    smallSeverity = 2,

    -- Where the patient must be (skipped in easy mode: then only the supplies are needed)
    requireLocation = false, -- true = only on a hospital bed / surgery table or in an ambulance treatment bay
    locations = { bed = true, surgery = true, bay = true },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RESULT
    -- ═══════════════════════════════════════════════════════════════════════

    irrigatedBelow = 10,     -- % contamination left that still counts as "irrigated"
    minStitchQuality = 0,    -- lowest stitch score that still closes the wound (0 = any finished closure)
    -- (the local anaesthetic itself lasts as long as the core 'lidocaine' medication: 15 minutes)

    -- ═══════════════════════════════════════════════════════════════════════
    -- INTERACTION
    -- ═══════════════════════════════════════════════════════════════════════

    interact   = true,       -- "Suture wound" in the patient interaction menu
    usableItem = true,       -- using the suture kit item starts it on the nearest patient
    useRange   = 3.0,        -- metres to look for a patient when the item is used
    order      = 62,         -- position in the interaction menu (60s = procedures)

    -- Skin tones for the close-up (0 light .. 1 dark). Each patient gets one of these,
    -- picked from their id so it is always the same for the same patient.
    skinTones  = { 0.12, 0.22, 0.3, 0.38, 0.5, 0.62, 0.75, 0.88 },

    -- ═══════════════════════════════════════════════════════════════════════
    -- MINIGAME (sent to the NUI)
    -- ═══════════════════════════════════════════════════════════════════════

    Game = {
        quality      = 'high',   -- 3D quality: 'high' | 'medium' | 'low' (lower = faster on weak PCs)

        -- 1 · irrigation
        salineMl     = 250,      -- mL of saline in the bottle
        syringeMl    = 30,       -- the irrigation syringe is refilled from the bottle when empty
        salineFlow   = 12,       -- mL per second while the jet is on
        refillTime   = 0.75,     -- seconds to refill the syringe
        jetRadius    = 4.5,      -- mm washed around the point the jet hits
        cleanDone    = 2,        -- % contamination that counts as clean

        -- 2 · local anaesthetic
        lidoSyringe  = 5,        -- mL in the lidocaine syringe
        lidoDose     = 0.5,      -- mL per injection point
        lidoRate     = 0.7,      -- mL per second while injecting
        lidoMaxPoint = 0.9,      -- mL at most per point
        lidoSpacing  = 14,       -- mm between injection points along each edge
        lidoOffset   = 3.5,      -- mm from the cut edge

        -- 3 · stitches
        mmPerStitch  = 8,        -- one stitch per this many mm of wound
        minStitches  = 3,
        maxStitches  = 12,
        extraStitches = 3,       -- extra stitches allowed to fill gaps
        bite         = 4,        -- ideal bite (mm from the edge on each side)
        biteMin      = 1.2,      -- closer than this tears out
        biteMax      = 9.5,      -- further than this is not accepted
        minDrag      = 0.3,      -- seconds; faster pulls are judged sloppy

        -- gauze
        gauzeRadius  = 16,       -- mm blotted around the cursor
        gauzeCapacity = 160,     -- how much blood one swab soaks up before a fresh one is opened

        -- pain
        flinchPain   = 42,       -- pain % above which painful moves can make the patient flinch
        flinchChance = 0.55,     -- chance of a flinch on a painful move (scaled down by numbness)

        -- 4 · dressing
        stuckDone    = 0.92,     -- how firmly the dressing must be rubbed down
        coverMin     = 0.85,     -- part of the cut the pad must cover

        -- score weights (total 100)
        weights = { irrigate = 20, anaesthetic = 15, suture = 45, dressing = 20 },

        fallbackTime = 14,       -- seconds of the simple progress bar on clients without WebGL2
    },
}
