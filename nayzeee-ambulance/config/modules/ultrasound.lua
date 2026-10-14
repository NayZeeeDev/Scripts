--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - ULTRASOUND (eFAST scan, treatment plan, chest drain,
                                   needle decompression, pericardiocentesis)
    Discord: discord.gg/nayzeeedev

    The ultrasound cart is placed in game (builder → Points → "Ultrasound cart").
    A patient lying within `Scan.cartRange` metres of a cart (on a bed, a table,
    a stretcher or the cart's own spot) can be scanned. The portable scanner works
    inside the ambulance treatment bay, and anywhere in easy mode.

    Items:  Config.Items.chest_drain_kit, Config.Items.decomp_needle, Config.Items.iv_kit,
            Config.Items.lidocaine (optional numbing step of the chest drain)
    Props:  Config.Props.us_cart, Config.Props.us_probe, Config.Props.syringe
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Ultrasound = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- eFAST SCAN (6 windows: RUQ, LUQ, PELVIS, CARDIAC, LUNG R, LUNG L)
    -- ═══════════════════════════════════════════════════════════════════════

    Scan = {
        perm      = 'ultrasound', -- permission needed (department grades grant it)
        items     = {},          -- Config.Items key → count needed to scan (the scanner is equipment: none)
        minTime   = 10,          -- seconds; finishing faster is rejected (anti-cheat)
        maxTime   = 900,         -- seconds before the session times out
        easyTime  = 8,           -- seconds of progress bar in easy mode
        maxDist   = 3.0,         -- metres the medic may be from the patient
        cartRange = 2.6,         -- metres between the patient and an ultrasound cart point
        bay       = true,        -- the portable scanner works inside the ambulance treatment bay
        field     = false,       -- true = the portable scanner works anywhere (not only in easy mode)
        minSeen   = 1.2,         -- seconds of a clear image a window needs before its mark counts in full
        labels    = true,        -- anatomy labels on the image (LIVER, KIDNEY ...). false = harder reads
        findings  = true,        -- record what was found (the examination shows it as a suspected problem)
        fee       = 350,         -- billed to player patients per scan (0 = free; insurance applies)

        -- Smallest amounts that show on the screen
        visible = {
            freeFluid   = 120,   -- mL of blood in the abdomen
            haemothorax = 80,    -- mL of blood in one side of the chest
            tamponade   = 25,    -- mL of blood around the heart
            pneumothorax = 5,    -- % collapse
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CHEST DRAIN (haemothorax / pneumothorax) - 3D close-up of the side of the chest
    -- ═══════════════════════════════════════════════════════════════════════

    ChestDrain = {
        perm      = 'chestdrain',
        items     = { chest_drain_kit = 1 },   -- Config.Items key → count
        consume   = 'finish',    -- 'start' | 'finish' - when the items are taken
        minTime   = 30,          -- seconds
        maxTime   = 900,
        easyTime  = 10,
        maxDist   = 3.0,
        -- Where the patient must lie (skipped in easy mode)
        rooms     = { bed = true, surgery = true, ultrasound = true, xray = false, angio = false, donation = false },
        bay       = true,        -- allowed inside the ambulance treatment bay
        field     = false,       -- allowed anywhere else
        minScore  = 30,          -- a score below this means the tube is misplaced: no effect, kit used
        drainNow  = 0.85,        -- share of the blood in the chest drained while you watch (the tube drains the rest)
        price     = 900,         -- billed to player patients (0 = free)
        numbing   = true,        -- offer the lidocaine step when the medic carries Config.Items.lidocaine
        quality   = 'high',      -- 3D quality: 'high' | 'medium' | 'low'
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- NEEDLE DECOMPRESSION (tension pneumothorax) - quick, works in the field
    -- ═══════════════════════════════════════════════════════════════════════

    Decompress = {
        perm      = 'chestdrain',
        items     = { decomp_needle = 1 },
        consume   = 'finish',
        minTime   = 4,
        maxTime   = 300,
        easyTime  = 5,
        maxDist   = 3.0,
        minScore  = 25,          -- below this the needle missed the air
        price     = 250,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PERICARDIOCENTESIS (cardiac tamponade) - ultrasound guided needle
    -- ═══════════════════════════════════════════════════════════════════════

    Pericardio = {
        perm      = 'pericardio',
        items     = { iv_kit = 1 },
        consume   = 'finish',
        minTime   = 18,
        maxTime   = 900,
        easyTime  = 10,
        maxDist   = 3.0,
        rooms     = { bed = true, surgery = true, ultrasound = true, xray = false, angio = true, donation = false },
        bay       = true,
        field     = false,       -- true = allowed anywhere (the portable scanner guides the needle)
        syringe   = 60,          -- mL one syringe holds before it must be emptied
        drawRate  = 7,           -- mL per second while drawing back
        maxDrawRate = 12,        -- server cap (mL/s) on what a client may claim it drew
        leftOver  = 20,          -- mL left around the heart that counts as drained
        slowBleed = 0.45,        -- after a good drain the bleed into the sac is multiplied by this
        touchVf   = 0.18,        -- chance per heart-muscle touch that the heart goes into VF
        maxVf     = 0.6,         -- cap on that chance
        price     = 1200,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- WORLD
    -- ═══════════════════════════════════════════════════════════════════════

    Cart = {
        -- Where a patient lies when someone puts them "on" the cart point (point space metres:
        -- +X right of the cart, +Y the operator side, +Z up). Change it per point in the builder data.
        lie = { x = 0.0, y = 1.05, z = 0.0 },
        dui = true,              -- mirror the live image on the cart's screen while scanning
        duiSize = { 512, 320 },  -- pixels of the screen texture
    },

    Probe = {
        networked = true,        -- other players see the probe move on the patient
        rate      = 66,          -- ms between probe position updates
        lift      = 0.012,       -- metres the probe floats above the skin when not pressed
    },

    Camera = {
        scan       = { dist = 1.05, pitch = 72, fov = 46 },  -- looking down at the torso
        pericardio = { dist = 0.62, pitch = 58, fov = 42 },
        decompress = { dist = 0.7, pitch = 60, fov = 44 },
    },

    Anim = {
        stand = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 },
        kneel = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1 },
        lowPatient = 0.55,       -- patient pelvis lower than this (m above your feet) → kneel
    },

    usable    = true,            -- using a chest drain kit / decompression needle starts it on the nearest patient
    useRange  = 3.0,             -- metres for that nearest patient
    keys = {
        freeze   = 'Space',      -- freeze / unfreeze the image (calipers on a frozen image)
        mode     = 'M',          -- B-mode / M-mode
        positive = 'P',          -- mark the current window positive
        negative = 'N',          -- mark the current window negative
        needle   = 'F',          -- pericardiocentesis: start / draw back
    },
}
