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
        drill      = 'Space',  -- hold to run the IO driver / hold to fasten
        advance    = 'KeyE',   -- slide the cannula off the needle
        clampDown  = 'KeyQ',   -- roller clamp - (also [ and ←)
        clampUp    = 'KeyE',   -- roller clamp + (also ] and →)
        squeeze    = 'Space',  -- pump the pressure infuser (resuscitate step)
        focus      = { patient = 'F1', site = 'F2', stand = 'F3', kit = 'F4' },  -- camera focus keys
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
        enabled = true,        -- show the treatments as buttons in the examination 'Injuries to treat' card
        heavyBleed = 25,       -- mL/min of one injury that offers 'Field resuscitation' in the exam
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- FIELD RESUSCITATION (the 7-step scene)
    -- ═══════════════════════════════════════════════════════════════════════

    Resus = {
        perms      = { 'iv', 'binder' },  -- medics with ANY of these see 'Field resuscitation'
        kit        = 'trauma_kit',        -- item KEY the medic must carry (not consumed)
        minLoss    = 0.0,                 -- blood loss fraction from which the scene may be started (0 = always)
        band       = { 60, 70 },          -- permissive hypotension: target MAP (mmHg) while the clot forms
        hold       = 24,                  -- seconds the MAP must stay in the band to firm the clot
        minTime    = 18,                  -- anti-cheat: shortest possible resuscitate step (s)
        maxTime    = 600,                 -- longest resuscitate step (s)
        easyTime   = 10,                  -- easy mode progress bar (s)
        clotFactor = 0.55,                -- a perfect firm clot removes this share of the base bleed of the target injuries
        popFactor  = 1.35,                -- a clot that pops multiplies the base bleed by this (over-resuscitation)
        popMargin  = 8,                   -- mmHg above the band that pops the clot after popAfter seconds
        popAfter   = 3.0,
        lowMap     = 52,                  -- under this MAP the clot stops forming (and the panel warns)
        nibpAuto   = 15,                  -- seconds between automatic NIBP cycles during the resuscitate step
        keepMonitor = true,               -- keep the monitor overlay open (no prop) after the scene ends
        finishMsgDelay = 900,             -- ms the result card waits before closing on Enter
        camera = { dist = 2.6, pitch = 62.0, fov = 46.0, minDist = 0.7, maxDist = 5.0 },
        anim   = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },  -- medic loop (kneeling)
        props = {
            kitSide    = 0.62,            -- metres from the patient's pelvis toward the medic side (kit case)
            kitAlong   = 0.30,            -- metres along the body toward the head
            sharpsSide = 0.72,  sharpsAlong = -0.25,
            monitorSide = 0.55, monitorAlong = 0.85,   -- monitor on the ground beside the chest
            standSide  = -0.55, standAlong = 0.95,     -- IV stand on the far side beside the head
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
        camera   = { dist = 0.62, pitch = 64.0, fov = 40.0 },
        anim     = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
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
        gravity   = 32,                   -- ml/min through a fully open roller clamp without pressure
        pressureGain = 1.15,              -- flow x (1 + gain * pressure / 300) with the infuser squeezed
        maxPressure = 300,                -- mmHg on the infuser gauge
        leak      = 6,                    -- mmHg the infuser loses per second
        pump      = 22,                   -- mmHg per squeeze (press)
        maxRate   = 160,                  -- ml/min the server ever accepts
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
        silence     = 120,                -- seconds the alarm silence button mutes the alarms
        prop        = true,               -- place the monitor prop next to the patient (standalone)
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
