--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - CPR & DEFIBRILLATOR
    Discord: discord.gg/nayzeeedev

    Chest compressions in time with the metronome (30:2), rescue breaths (bag-valve mask or mouth to
    mouth), pads, rhythm analysis, charge / stand clear / shock, adrenaline and ROSC.
    Two medics can run a code together: one compresses, the other does airway, defib and
    drugs, and they swap at the 2-minute rhythm check (compressors get tired).

    Keys use JavaScript KeyboardEvent.code names: 'Space', 'KeyA' (= the A key), 'Digit1' ...
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Cpr = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- WHO / WHERE
    -- ═══════════════════════════════════════════════════════════════════════

    perm          = 'cpr',      -- permission to start / join CPR (police get it via Config.PolicePerms)
    distance      = 2.0,        -- metres from the patient for the 'Start CPR' option
    maxDist       = 3.0,        -- the server ends your part in the code when you are further than this (+2 m slack)
    wounded       = true,       -- also allow CPR on a 'wounded' patient who is unresponsive (U) and not breathing
    maxTeam       = 2,          -- people in one code: 1 = solo only, 2 = compressor + airway/defib partner
    icon          = 'heart',    -- NAYZEEE icon for the menu entries
    order         = 30,         -- patient menu order (30 = resuscitation band)
    radial        = true,       -- 'Start CPR' in the EMS radial menu (Patient)
    radialRange   = 3.0,        -- the radial acts on the nearest patient in arrest within this many metres
    examRoute     = true,       -- 'Start CPR' button in the head-to-toe check
    usableDefib   = true,       -- using the defibrillator item starts CPR on the nearest patient in arrest

    -- ═══════════════════════════════════════════════════════════════════════
    -- KEYS (in the CPR screen)
    -- ═══════════════════════════════════════════════════════════════════════

    Keys = {
        compress   = 'Space',    -- compress in time with the metronome / hold for a breath
        pads       = 'KeyP',     -- attach the pads (drag them, or press this to place them)
        analyse    = 'KeyA',     -- analyse the rhythm (hands off!)
        charge     = 'KeyC',     -- charge the defibrillator
        shock      = 'KeyS',     -- deliver the shock
        energyUp   = 'KeyE',     -- energy knob + (manual mode); the mouse wheel over the knob works too
        energyDown = 'KeyQ',     -- energy knob -
        adrenaline = 'KeyD',     -- give adrenaline
        swap       = 'KeyX',     -- swap compressor / airway roles with your partner
        pulse      = 'KeyF',     -- check the carotid pulse after an organised rhythm
        causes     = 'KeyH',     -- show / hide the reversible causes card
        mode       = 'KeyM',     -- AED <-> manual mode (manual needs the 'defib' permission)
        disarm     = 'KeyZ',     -- dump the charge without shocking
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- COMPRESSIONS (the rhythm game)
    -- ═══════════════════════════════════════════════════════════════════════

    Compressions = {
        target     = 110,       -- metronome rate (compressions per minute)
        rateMin    = 100,       -- the guideline window (PERFECT inside it)
        rateMax    = 120,
        perSet     = 30,        -- compressions before the breaths (30:2)
        perfect    = 0.085,     -- seconds off the beat that still count as PERFECT
        good       = 0.17,      -- ...as GOOD (anything later / earlier is EARLY / LATE)
        pressMin   = 0.07,      -- holding Space shorter than this = too shallow
        pressMax   = 0.30,      -- holding longer than this (or through the next beat) = leaning, no recoil
        metronome  = true,      -- audible click that paces the compressions
        idleWarn   = 1.6,       -- seconds without a compression before "Keep going!"
        fatigue = {
            enabled   = true,
            after     = 120,    -- seconds of continuous compressions before the depth starts to drop
            perMinute = 14,     -- depth % lost per minute after that
            max       = 40,     -- never worse than -40 %
            recover   = 3,      -- % recovered per second while someone else compresses
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RESCUE BREATHS
    -- ═══════════════════════════════════════════════════════════════════════

    Breaths = {
        perSet        = 2,      -- breaths after every set of compressions
        hold          = 1.0,    -- seconds of Space for a perfect breath (watch the chest rise)
        tooShort      = 0.55,   -- shorter = the chest barely rises
        tooLong       = 1.7,    -- longer = over-inflation (air into the stomach)
        timeout       = 10,     -- seconds before compressions resume without (all) breaths
        mouthToMouth  = true,   -- allow breaths without a bag-valve mask (Config.Items.bvm)
        mouthQuality  = 60,     -- % a mouth-to-mouth breath is worth compared with the BVM
        mouthSlower   = 1.25,   -- mouth-to-mouth needs this much longer to fill the chest
        bvmProp       = true,   -- show the BVM on the patient's face while ventilating
        bvmAttach     = {       -- BVM on the patient's face (SKEL_Head), see docs/modules/props.md
            bone = 31086, pos = { x = 0.06, y = 0.11, z = 0.0 }, rot = { x = 0.0, y = -90.0, z = -90.0 },
        },
        continuousIfVentilated = true, -- intubated + on a ventilator → continuous compressions, no pauses
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CYCLES & ADRENALINE
    -- ═══════════════════════════════════════════════════════════════════════

    Cycle = {
        length     = 120,       -- seconds per CPR cycle; the device asks for a rhythm check after it
        checkGrace = 20,        -- an analysis this many seconds early still counts as the rhythm check
    },

    Adrenaline = {
        enabled    = true,
        perm       = 'meds',    -- permission to give it
        minGap     = 150,       -- seconds between doses (guideline: every 3-5 minutes)
        due        = 240,       -- seconds after a dose (or after the 2nd shock / non-shockable start) the device says DUE
        needAccess = false,     -- true = needs an IV / IO / port first (realistic: your partner places an IO)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- EASY MODE (departments with easy mode for 'cpr', see Config.EasyMode)
    -- ═══════════════════════════════════════════════════════════════════════

    easyTimed = true,           -- easy medics do CPR as a timed action (ox_lib progress per 2-min cycle, no
                                -- device screen); false = they get the device screen with automatic help
    Easy = {
        autoDefib   = true,     -- a team of timed medics: pads, analysis, charge / shock and adrenaline run by themselves
        breathGap   = 1.3,      -- seconds between the automatic rescue breaths
        chargeAfter = 1.2,      -- seconds after "shock advised" before the automatic charge
        shockAfter  = 1.5,      -- seconds of "stand clear" before the automatic shock
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- DEFIBRILLATOR
    -- ═══════════════════════════════════════════════════════════════════════

    Defib = {
        perm        = 'defib',  -- manual mode: free energy choice, charge any time
        aedPerm     = 'cpr',    -- AED mode (shock only when advised): everyone who may do CPR
        items       = { 'defibrillator', 'trauma_kit' }, -- Config.Items keys; carrying any one gives you a defib
        bay         = true,     -- a patient in the ambulance treatment bay always has a defib
        hospital    = true,     -- ...and so does a patient on a hospital bed / point or near a hospital
        hospitalRadius = 60.0,  -- metres from a hospital (department HQ / point) that count as "in the hospital"
        energies    = { 120, 150, 200, 250, 300, 360 }, -- knob positions (joules, biphasic)
        energy      = 200,      -- starting energy
        aedEnergies = { 200, 300, 360 }, -- AED protocol: 1st, 2nd, 3rd+ shock
        analyseTime = 4,        -- seconds the analysis needs (no compressions!)
        chargeTime  = 2.5,      -- seconds to charge at 200 J (scales with the energy)
        chargedFor  = 25,       -- seconds a charge is held before the device disarms itself
        clearWindow = 0.9,      -- a compression this close before the shock = you shocked the rescuer
        rescuerShock = {
            ragdoll = 1800,     -- ms the rescuer who was touching the patient falls over
            health  = 8,        -- GTA health removed from that rescuer (0 = none)
            efficacy = 0.4,     -- the shock is this much as effective (energy went into the rescuer)
        },
        prop        = true,     -- put the defibrillator case (Config.Props.defib) on the ground next to the patient
        propOffset  = 0.75,     -- metres from the chest, on the medic's side
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PADS (drag them onto the chest)
    -- ═══════════════════════════════════════════════════════════════════════

    Pads = {
        snap      = 70,         -- pixels: how close to the chest target a pad must be dropped
        sternum   = 0.42,       -- right pad: share of the way from the upper chest to the right shoulder
        apex      = 0.85,       -- left pad: share of the way out to the left side (mid-axillary line)
        lift      = 0.09,       -- metres above the spine bones (the chest surface)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ROSC CHANCES (all multiplied together, the server decides)
    -- ═══════════════════════════════════════════════════════════════════════

    Rosc = {
        shockBase   = 0.42,     -- chance a shock on VF / VT restores a pulse with perfect everything
        peaBase     = 0.22,     -- chance per rhythm check that CPR + adrenaline bring PEA back
        asystoleBase = 0.06,    -- ...asystole (the worst rhythm)
        max         = 0.88,     -- cap per attempt
        energy = {              -- energy (J) → factor, interpolated in between
            { 120, 0.72 }, { 150, 0.84 }, { 200, 1.0 }, { 250, 1.06 }, { 300, 1.10 }, { 360, 1.14 },
        },
        adrenaline  = 1.30,     -- adrenaline acting (within its 4 minutes)
        noAdrenaline = 0.80,    -- 3 or more shocks / checks and still no adrenaline given
        lowFlowDecay = 0.035,   -- lost per minute of arrest WITH CPR
        noFlowDecay  = 0.11,    -- lost per minute of arrest WITHOUT CPR (before the code started)
        minTime     = 0.15,     -- the time factor never drops below this
        ventilation = 0.40,     -- weight of ventilation quality (0 = breaths never matter)
        asystoleToVf = 0.14,    -- chance asystole turns into (fine) VF at a check after adrenaline
        peaToVf     = 0.08,     -- chance PEA turns into VF at a check
        degrade     = 0.12,     -- chance a shockable rhythm decays to asystole after a failed shock with poor CPR
        causes = {              -- untreated reversible causes (Hs & Ts) multiply the chance by this
            hypovolemia  = { loss = 0.38, factor = 0.25, soft = 0.32, softFactor = 0.6 }, -- blood loss fraction
            tension      = 0.08, -- tension pneumothorax not decompressed
            tamponade    = { ml = 100, factor = 0.08 }, -- blood around the heart not drained
            haemothorax  = { ml = 1500, factor = 0.5 },
            hypothermia  = { temp = 30.0, factor = 0.30, soft = 32.0, softFactor = 0.7 },
            hypoxia      = { level = 40, factor = 0.45, ventilated = 0.85 }, -- water / smoke in the lungs
            airway       = 0.30, -- obstructed airway, not intubated
            toxins       = { amount = 50, factor = 0.5 }, -- opioid overdose without naloxone
        },
        rearrestWatch = 45,     -- seconds the code stays open after ROSC (re-arrest = CPR resumes)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ANIMATIONS (synced medic + patient pair, played at the same origin)
    -- ═══════════════════════════════════════════════════════════════════════

    Anim = {
        medic = {
            intro    = { 'mini@cpr@char_a@cpr_def', 'cpr_intro' },
            compress = { 'mini@cpr@char_a@cpr_str', 'cpr_pumpchest' },
            idle     = { 'mini@cpr@char_a@cpr_def', 'cpr_pumpchest_idle' },
            breath   = { 'mini@cpr@char_a@cpr_str', 'cpr_kol_idle' },
            success  = { 'mini@cpr@char_a@cpr_str', 'cpr_success' },
        },
        bed = {                  -- patient on a bed / stretcher / in the bay: the medic stands, the patient stays put
            compress = { 'missheistfbi3b_ig8_2', 'cpr_loop_paramedic' },
            idle     = { 'amb@medic@standing@timeofdeath@base', 'base' },
            side     = 0.65,     -- metres beside the chest
        },
        patient = {
            intro    = { 'mini@cpr@char_b@cpr_def', 'cpr_intro' },
            compress = { 'mini@cpr@char_b@cpr_str', 'cpr_pumpchest' },
            idle     = { 'mini@cpr@char_b@cpr_def', 'cpr_pumpchest_idle' },
            breath   = { 'mini@cpr@char_b@cpr_str', 'cpr_kol_idle' },
            success  = { 'mini@cpr@char_b@cpr_str', 'cpr_success' },
        },
        helper   = { 'amb@medic@standing@kneel@base', 'base' }, -- the partner kneels at the head
        helperBed = { 'amb@medic@standing@timeofdeath@base', 'base' }, -- ...or stands at the head of a bed
        helperDist = 0.55,       -- metres beyond the patient's head
        npcRest  = { 'dead', 'dead_a' },   -- an NPC patient lies like this after CPR
        placement = 'side',      -- 'side': the medic kneels beside the patient's chest (spot from the patient's bones),
                                 -- both clips play in place; 'synced': both clips at one shared origin (below)
        kneel    = {             -- 'side' placement
            side  = 0.55,        -- metres from the chest out to where the medic kneels (more = further away)
            along = 0.0,         -- metres towards the head (negative = towards the hips)
            drift = 0.35,        -- the medic re-kneels when the body moved this far away from them
        },
        origin   = { x = 0.0, y = 0.0, z = 1.0, h = 0.0 }, -- 'synced': scene origin from the patient's ground spot (raise z if peds sink)
        baseRate = 105,          -- compressions per minute the pump clip plays at normal speed
        introMs  = 1800,         -- ms of the kneel-down intro before the first compression
        patientPose = true,      -- lay a player patient flat in the CPR pose (off: their downed pose stays)
    },

    Camera = {
        enabled = true,
        dist    = 2.7,          -- metres from the chest
        pitch   = 58,           -- degrees above the patient (top-down-ish, like a code team sees it)
        fov     = 48,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RECORDS & BILLING
    -- ═══════════════════════════════════════════════════════════════════════

    record  = true,             -- write the code summary to the patient's medical record
    Billing = {
        rosc  = 350,            -- charged to a player patient after a successful resuscitation (0 = free)
        shock = 0,              -- per shock
    },
}
