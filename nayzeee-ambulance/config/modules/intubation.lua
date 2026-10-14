--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - AIRWAY (bag-valve mask, suction, video laryngoscope intubation)

    Medics with the 'airway' permission can ventilate a patient with a bag-valve mask
    and intubate them with a video laryngoscope (8-step minigame, or a progress bar in
    easy mode). A correctly placed tube secures the airway; a tube in the oesophagus
    that nobody notices slowly suffocates the patient.
    Items are in config/items.lua (intubation_kit, bvm), props in config/props.lua.
]]

Config = Config or {}

Config.Intubation = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- WHO & WHAT
    -- ═══════════════════════════════════════════════════════════════════════

    perm          = 'airway',     -- permission needed for BVM, intubation, tube checks
    maxDistance   = 3.0,          -- metres between medic and patient (checked server side)
    requireBvm    = true,         -- the medic must carry a bag-valve mask (never consumed)
    consumeKit    = 'finish',     -- 'finish' = the kit is used up when the attempt ends, 'start' = on start
    requireDown   = true,         -- only patients that are wounded / in arrest can be intubated
    downAvpu      = { P = true, U = true },  -- ...and only when they respond to pain or less (wounded)
    allowSelf     = false,        -- you cannot intubate yourself

    -- ═══════════════════════════════════════════════════════════════════════
    -- INTUBATION MINIGAME
    -- ═══════════════════════════════════════════════════════════════════════

    minTime       = 25,           -- seconds; a finish faster than this is rejected (anti-cheat)
    maxTime       = 900,          -- seconds before the session expires
    easyTime      = 14,           -- seconds of progress bar in easy mode
    attempts      = 3,            -- laryngoscopy attempts before it counts as a failed airway

    tube   = { m = 7.5, f = 7.0 },  -- endotracheal tube size (mm inner diameter) by sex
    depth  = { m = 23, f = 21 },    -- correct tube depth at the teeth (cm) by sex

    cadence       = 5.0,          -- seconds between bag squeezes (pre-oxygenation)
    squeeze       = 1.0,          -- ideal squeeze length in seconds
    preoxBreaths  = 6,            -- good breaths that count as full pre-oxygenation
    abortSpo2     = 90,           -- under this during an attempt the medic must abort and re-oxygenate
    crashSpo2     = 75,           -- under this the attempt is aborted for them (and it hurts the score)
    cuffBand      = { 20, 30 },   -- correct cuff pressure (cmH2O)
    cuffMl        = { 7.5, 10.0 },-- air needed for a 25 cmH2O seal varies per patient in this range (ml)

    -- How hard the airway is. Each patient gets an anatomy grade 1-4 (best possible view):
    difficulty = {
        weights      = { 55, 28, 12, 5 },  -- chance weights for grade 1..4 on a normal patient
        faceTrauma   = 1,         -- face / neck wounds of severity 3+ add this many grades
        swelling     = 1,         -- an 'airway swelling' condition adds this many grades
        cspine       = 1,         -- a collar or cervical spine injury adds this (no head tilt allowed)
    },

    -- Blood / vomit in the airway (suction step)
    soil = {
        faceBleed    = 0.55,      -- airway soiling from bleeding face / neck wounds (0..1 at severity 4)
        overdose     = 0.45,      -- chance an overdosed patient has vomited
        drowning     = 0.8,       -- chance of water / froth after drowning
        gastricLimit = 60,        -- gastric air (from bad bagging) above this → the patient regurgitates
        base         = 0.12,      -- chance any patient has some secretions
    },

    -- Apnoea: how fast SpO2 falls once the mask comes off (seconds of safe apnoea at full pre-oxygenation)
    safeApnoea = { healthy = 75, sick = 35 },

    -- ═══════════════════════════════════════════════════════════════════════
    -- OUTCOME
    -- ═══════════════════════════════════════════════════════════════════════

    hypoxiaRelief     = 18,       -- hypoxia level removed per minute while a tube is correctly in place
    clearAirway       = true,     -- a correct tube removes the 'airway' condition (obstruction / swelling bypassed)
    misplacedRate     = 22,       -- hypoxia level added per minute while a tube sits in the oesophagus
    misplacedStart    = 35,       -- hypoxia level right after an unnoticed oesophageal tube
    mainstemRate      = 6,        -- hypoxia added per minute by a tube that is too deep (one lung only)
    attemptInsult     = 0.8,      -- hypoxia level added per % of SpO2 below 90 reached during the attempt
    extubateOnWake    = true,     -- remove the tube automatically when the patient is back to 'alive'
    tick              = 5,        -- seconds between airway effect updates

    -- ═══════════════════════════════════════════════════════════════════════
    -- BAG-VALVE MASK (standalone ventilation for apnoeic / overdosed patients)
    -- ═══════════════════════════════════════════════════════════════════════

    bvm = {
        enabled     = true,
        breaths     = 8,          -- breaths in one ventilation round
        minTime     = 14,         -- seconds; anti-cheat
        maxTime     = 600,
        easyTime    = 8,
        ventilate   = 120,        -- seconds the patient counts as ventilated after a round
        relief      = 30,         -- hypoxia level removed by a perfect round
        states      = { wounded = true, arrest = true },  -- patient states it shows for
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PRICES (charged to the patient; insurance applies - see Config.Billing)
    -- ═══════════════════════════════════════════════════════════════════════

    price = {
        intubate = 850,
        bvm      = 120,
        check    = 0,
        extubate = 0,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ITEMS FROM THE INVENTORY
    -- ═══════════════════════════════════════════════════════════════════════

    usable = {
        intubation_kit = true,    -- using the kit starts an intubation on the nearest downed patient
        bvm            = true,    -- using the BVM starts a ventilation round on the nearest downed patient
    },
    useRange = 2.5,               -- metres to look for a patient when an item is used

    -- ═══════════════════════════════════════════════════════════════════════
    -- WORLD (props, camera, animation)
    -- ═══════════════════════════════════════════════════════════════════════

    worldTube   = true,           -- every client shows the tube prop at the mouth of intubated patients
    worldRange  = 45.0,           -- metres within which tube props are shown
    networkProps= false,          -- spawn the procedure props networked so bystanders see them
    externalMonitor = false,      -- true: open the field module's 'monitor' app instead of the built-in one

    -- Attach offsets on the PATIENT (bone = ped bone id; 31086 = SKEL_Head)
    props = {
        bvm    = { bone = 31086, pos = vector3(0.10, 0.10, 0.0),  rot = vector3(0.0, 0.0, -90.0) },  -- mask on the face
        bvmEtt = { bone = 31086, pos = vector3(0.10, 0.20, 0.0),  rot = vector3(0.0, 0.0, -90.0) },  -- bag on the tube
        ett    = { bone = 31086, pos = vector3(0.04, 0.11, 0.0),  rot = vector3(0.0, 0.0, -90.0) },  -- tube at the mouth
        -- on the MEDIC (57005 = right hand, 18905 = left hand)
        laryngoscope = { bone = 18905, pos = vector3(0.10, 0.02, -0.03), rot = vector3(-70.0, 0.0, 10.0) },
        tubeHand     = { bone = 57005, pos = vector3(0.12, 0.03, 0.02),  rot = vector3(-80.0, 10.0, 0.0) },
        syringe      = { bone = 57005, pos = vector3(0.10, 0.03, -0.02), rot = vector3(-90.0, 0.0, 0.0) },
        -- on the ground next to the head (metres: side = patient's right, forward = towards the feet)
        suction      = { side = 0.62, forward = -0.15 },
        monitor      = { side = -0.70, forward = 0.20, enabled = true },
    },

    -- Medic animations (kneeling at the head on the ground, standing at a bed / stretcher)
    anim = {
        kneel = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
        stand = { dict = 'mini@repair', clip = 'fixing_a_ped' },
        headOffset = 0.62,        -- metres behind the patient's head where the medic kneels
    },

    -- Cameras per phase (offsets from the patient's head: side, forward = towards the feet, up)
    camera = {
        enabled = true,
        preox   = { side = 0.55, forward = 0.55, up = 0.95, fov = 46.0, look = { side = 0.0, forward = -0.15, up = 0.0 } },
        scope   = { side = 0.10, forward = -0.55, up = 0.62, fov = 38.0, look = { side = 0.0, forward = 0.10, up = 0.02 } },
        confirm = { side = 0.95, forward = 0.35, up = 1.10, fov = 50.0, look = { side = 0.0, forward = 0.30, up = 0.0 } },
        ease    = 650,            -- ms camera blend
    },
}
