--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - FIELD RESUSCITATION
    Discord: discord.gg/nayzeeedev

    The trauma kit at the roadside: pelvic binder, intraosseous (IO) access with
    the drill, IV cannulation, fluid / blood resuscitation with a pressure
    infuser and TXA, permissive hypotension (keep the MAP in the band while the
    clot firms) and the NAYZEEE patient monitor (also usable on its own).

    Items are named in config/items.lua (Config.Items.*). Here they are referred
    to by their KEY ('trauma_kit', 'io_kit', ...), never by the inventory name.
    Keys use JavaScript KeyboardEvent.code names: 'Space', 'KeyE', 'Digit1', 'F1' ...
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Field = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- MINIGAME KEYS (KeyboardEvent.code names, shown as key caps in the panel)
    -- ═══════════════════════════════════════════════════════════════════════

    Keys = {
        drill      = 'Space',  -- hold to run the IO driver
        advance    = 'KeyE',   -- slide the cannula off the needle
        clampDown  = 'KeyQ',   -- roller clamp - (also [ and ←)
        clampUp    = 'KeyE',   -- roller clamp + (also ] and →)
        squeeze    = 'Space',  -- pump the pressure infuser (resuscitate step)
        insert     = 'Space',  -- IV cannulation: hold to advance the needle
        focus      = 'Tab',    -- cycles the camera view Body → Access → Drip → Kit (Shift = back; the views are also clickable)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PATIENT MENU (third-eye / target options)
    -- ═══════════════════════════════════════════════════════════════════════

    Interact = {
        distance  = 2.2,       -- metres from the patient for the options to show
        resus     = true,      -- 'Field resuscitation' (order 31, band 30 = resuscitation)
        iv        = true,      -- 'IV cannulation' (order 44)
        monitor   = true,      -- 'Attach patient monitor' / 'Remove patient monitor' (order 25)
        binderOff = true,      -- 'Remove pelvic binder' (order 48)
        ivOff     = true,      -- 'Remove IV / IO line' (order 49)
        resusBleed = 2,        -- state bag bleed level (0-3) at which 'Field resuscitation' shows
                               -- (it also shows for a binder-worthy pelvis / no IV access with any bleed)
        icons = { resus = 'iv', iv = 'syringe', monitor = 'monitor', binderOff = 'shield', ivOff = 'iv' },
    },

    Radial = {
        enabled = true,        -- add Field resuscitation / IV cannulation / Patient monitor to the EMS radial (Patient)
        range   = 3.0,         -- metres to the nearest patient
    },

    Exam = {
        enabled = true,        -- show the treatments as buttons under 'Next care step' in the head-to-toe check's Findings card
        heavyBleed = 25,       -- mL/min of one injury that offers 'Field resuscitation' in the exam
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- FIELD RESUSCITATION (the 7-step scene)
    -- ═══════════════════════════════════════════════════════════════════════

    Resus = {
        perms      = { 'iv', 'binder' },  -- medics with ANY of these see 'Field resuscitation'
        kit        = 'trauma_kit',        -- item KEY the medic must carry (not consumed)
        band       = { 60, 70 },          -- permissive hypotension: target MAP (mmHg) while the clot forms
        hold       = 24,                  -- seconds of MAP inside the band that firm the clot to 100 %
        minTime    = 18,                  -- anti-cheat: shortest possible resuscitate step (s)
        maxTime    = 600,                 -- longest resuscitate step (s)
        easyTime   = 10,                  -- easy mode progress bar (s)
        clotFactor = 0.55,                -- a perfect firm clot removes this share of the base bleed of the target injuries
        popFactor  = 1.35,                -- a clot that pops multiplies the base bleed of the target injuries by this
        maxPop     = 1.8,                 -- ...but never above this multiple of the bleed the step started with
        popMargin  = 6,                   -- mmHg above the band (caused by your fluids) that pops the clot...
        popAfter   = 3.0,                 -- ...after this many seconds
        lowMap     = 52,                  -- under this MAP the clot stops forming (the panel warns)
        -- how the pressure answers the fluids during the step (server model on top of the real MAP)
        response   = {
            saline = 0.16,                -- mmHg per mL/min of crystalloid running
            blood  = 0.30,                -- mmHg per mL/min of blood running
            plasma = 0.26,
            tau    = 6.0,                 -- seconds for the pressure to follow a change of flow
            own    = 4,                   -- below this many mmHg of fluid response a high MAP is the patient's own (no pop)
        },
        speed      = {                    -- clot forming speed multipliers
            below = 0.35,                 -- MAP between lowMap and the band
            high  = 0.25,                 -- MAP above the band because of your fluids
            own   = 0.80,                 -- MAP above the band on its own (no fluids needed)
            txa   = 1.30,                 -- TXA given
            cold  = 0.60,                 -- patient under 35 C without a foil blanket
            foil  = 0.85,                 -- patient under 35 C with a foil blanket
            dilution = 0.70,              -- more than 'dilutionAt' of the circulating volume is saline
            dilutionAt = 0.20,
        },
        keepMonitor = true,               -- leave the patient monitor attached when the scene ends
        standKeep  = 240,                 -- seconds the IV stand stays after the scene (removed earlier if the patient is moved)
        autoContinue = 1.6,               -- seconds after the clot is firm before the step completes on its own
        camera = { dist = 2.6, pitch = 62.0, fov = 46.0, minDist = 0.7, maxDist = 5.0 },
        siteCamera = { dist = 1.05, pitch = 58.0, fov = 42.0 },   -- F2 / IO steps close-up
        anim   = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },  -- medic loop (kneeling)
        -- prop layout around the patient (metres): side > 0 = the side away from the medic,
        -- along > 0 = from the pelvis toward the head
        props = {
            kit     = { side = 0.68, along = 0.18 },   -- open trauma case
            sharps  = { side = 0.72, along = -0.38 },  -- sharps bin
            stand   = { side = -0.62, along = 0.95 },  -- IV stand (medic side, beside the head)
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PELVIC BINDER (step 1)
    -- ═══════════════════════════════════════════════════════════════════════

    Binder = {
        perm       = 'binder',
        item       = 'pelvic_binder',     -- item KEY consumed when applied (false = part of the trauma kit)
        band       = { 60, 80 },          -- strap tension % accepted on release
        minTime    = 5,  maxTime = 240, easyTime = 6,
        bleedBonus = 0.25,                -- a perfect strap lowers the base bleed of pelvic injuries by up to 25 %
                                          -- (on top of the physiology binder modifier x0.4)
        tightPain  = 12,                  -- pain added for an over-tightened strap
        removeReturns = true,             -- 'Remove pelvic binder' gives the binder back
        attach = { bone = 11816, pos = { 0.0, 0.0, 0.0 }, rot = { 0.0, 90.0, 0.0 } },  -- binder_worn on SKEL_Pelvis
        worn   = { range = 40.0 },        -- every client renders the binder on patients within this range
        fee    = 0,                       -- billed to the patient (0 = free; see Billing)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- INTRAOSSEOUS ACCESS (steps 2-5: site, drill, confirm, flush)
    -- ═══════════════════════════════════════════════════════════════════════

    IO = {
        perm     = 'iv',
        item     = 'io_kit',              -- IO needle set KEY (one per attempt; a failed drill needs a new one)
        lidocaine = 'lidocaine',          -- optional: used for the flush if the medic carries it (not required)
        saline    = 'saline',             -- optional: saline flush syringe (not required)
        minTime  = 14, maxTime = 420, easyTime = 10,
        maxAngle = 15,                    -- degrees off the bone axis the driver may be
        bendAngle = 26,                   -- degrees off-axis while drilling cortex that bends the needle
        attempts = 3,                     -- needles per session before the IO step fails
        -- bone layers (mm) are rolled per patient between these limits
        layers = {
            tibia   = { soft = { 4, 9 },  cortex = { 2.5, 4.0 }, marrow = { 10, 16 }, far = { 2.5, 3.5 } },
            humerus = { soft = { 8, 16 }, cortex = { 2.0, 3.0 }, marrow = { 12, 20 }, far = { 2.5, 3.5 } },
        },
        speed = { soft = 7.0, cortex = 1.3, marrow = 8.0, far = 1.1 },   -- drill speed mm/s per layer
        -- IO sites: bone + offset along the bone (m) where the needle goes in
        sites = {
            l_tibia   = { region = 'l_lower_leg', bone = 63931, offset = { 0.07, 0.0, 0.0 } },   -- proximal tibia, 2 cm below the knee
            r_tibia   = { region = 'r_lower_leg', bone = 36864, offset = { 0.07, 0.0, 0.0 } },
            l_humerus = { region = 'l_upper_arm', bone = 45509, offset = { 0.05, 0.0, 0.0 } },   -- humeral head
            r_humerus = { region = 'r_upper_arm', bone = 40269, offset = { 0.05, 0.0, 0.0 } },
        },
        pxPerDeg = 3.2,                   -- cursor pixels (1080p) per degree off-axis while aiming the driver
        tremor   = 7,                     -- degrees of hand drift while the driver fights the cortex
        aspirateMl = 1.0,                 -- ml to pull back for a marrow flash
        lidoMl = 2.0,                     -- lidocaine 2 % to push (ml)
        lidoRate = { 0.08, 0.45 },        -- ml/s accepted ("slowly")
        flushMl = 10,                     -- saline flush (ml)
        flushRate = { 1.5, 6.0 },         -- ml/s accepted
        fee = 0,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- IV CANNULATION (anywhere: forearm close-up)
    -- ═══════════════════════════════════════════════════════════════════════

    IV = {
        perm     = 'iv',
        item     = 'iv_kit',              -- cannula + line + dressing KEY
        minTime  = 12, maxTime = 360, easyTime = 8,
        angle    = { 15, 30 },            -- insertion angle band (degrees)
        attempts = 2,                     -- blown veins before the attempt fails
        gauge    = 18,                    -- cannula size written to the patient record
        tourniquetFill = 3.0,             -- seconds for the veins to fill under the tourniquet
        sites    = {                      -- forearm close-up: bone, tourniquet bone (upper arm)
            l_lower_arm = { bone = 61163, tq = 45509 },
            r_lower_arm = { bone = 28252, tq = 40269 },
        },
        flash    = 0.9,                   -- seconds of needle travel inside the vein before it goes through the back wall
        camera   = { dist = 0.62, pitch = 64.0, fov = 40.0 },
        anim     = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
        tourniquetProp = true,            -- show a tourniquet strap on the upper arm while cannulating
        removeReturns = false,            -- 'Remove IV / IO line' returns nothing (cannulas are single use)
        fee = 0,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RESUSCITATE (step 6): bags, pressure infuser, TXA, foil blanket
    -- ═══════════════════════════════════════════════════════════════════════

    Infusion = {
        perm      = 'iv',
        saline    = 'saline_bag',         -- 500 ml bag KEY
        salineMl  = 500,
        blood     = 'blood_bag',          -- blood bag KEY (needs the blood module: NZA.Blood.TakeBag)
        bloodMl   = 450,
        gravity   = 60,                   -- ml/min through an IV with the roller clamp fully open, no pressure
        ioFactor  = 0.45,                 -- an IO line runs at this share of the gravity flow (use the infuser!)
        pressureGain = 1.4,               -- flow x (1 + gain * pressure / maxPressure) with the infuser pumped up
        maxPressure = 300,                -- mmHg on the infuser gauge
        leak      = 6,                    -- mmHg the infuser loses per second
        pump      = 22,                   -- mmHg per squeeze
        maxRate   = 160,                  -- ml/min the server ever accepts (hard cap)
        maxBags   = 3,                    -- bags running at once
        warm      = false,                -- true = field fluids count as warmed (no temperature drop)
        dilution  = 1000,                 -- ml of saline after which the panel warns about dilution
    },

    TXA = {
        item    = 'txa',                  -- 1 g vial KEY
        perm    = 'iv',
        push    = 10,                     -- seconds the slow push should take (faster = BP drop)
    },

    Foil = {
        item    = 'foil_blanket',         -- used when the first aid module is not installed
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PATIENT MONITOR (NUI app 'monitor', also opened by the bay / bed / CPR modules)
    -- ═══════════════════════════════════════════════════════════════════════

    Monitor = {
        perm        = 'assess',           -- 'Attach patient monitor'
        requireItem = 'trauma_kit',       -- item KEY the medic must carry to attach one (false = none)
        range       = 12.0,               -- the overlay closes when you walk further from the patient
        nibpAuto    = 60,                 -- seconds between automatic NIBP cycles (standalone monitor)
        nibpTime    = 4.0,                -- seconds a cuff cycle takes
        alarms      = true,               -- alarm tones (also needs Config.UI.sounds)
        beep        = true,               -- beat / SpO2 tone on the overlay monitor (also needs Config.UI.sounds)
        silence     = 120,               -- seconds the alarm silence button mutes the alarms
        prop        = true,               -- place the monitor prop next to the patient
        place       = { side = 0.62, along = 0.82 },   -- beside the chest, away from the medic (m)
        screen      = true,               -- live vitals on the prop screen (DUI) for the medic who attached it
        focusKey    = false,              -- e.g. 'F9': take the mouse to press the monitor's buttons (false = no default)
        command     = 'nzamonitor',       -- same as the key (toggle mouse on the monitor)
        position    = 'tl',               -- overlay corner: 'tl' | 'tr' | 'bl'
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BILLING (charged to player patients by on-duty medics; 0 = free)
    -- ═══════════════════════════════════════════════════════════════════════

    Billing = {
        binder = 150,
        io     = 220,
        iv     = 90,
        resus  = 350,
    },
}
