--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - ASSESSMENT
    Discord: discord.gg/nayzeeedev

    Examine Patient (top-down body map + injuries to treat), Check Pulse,
    Check Breathing (look, listen with a stethoscope, call it) and Ask to Walk.

    Keys use JavaScript KeyboardEvent.code names: 'Space', 'Enter', 'KeyN',
    'Digit1' ... ('KeyX' = the X key, 'Digit3' = the 3 key above the letters).
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Assess = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- PATIENT MENU (third-eye / target options)
    -- ═══════════════════════════════════════════════════════════════════════

    Interact = {
        perm      = 'assess',   -- permission needed for Examine / Pulse / Breathing
        distance  = 2.2,        -- metres from the patient for the options to show
        examine   = true,       -- show 'Examine Patient'
        pulse     = true,       -- show 'Check Pulse'
        breathing = true,       -- show 'Check breathing'
        icons = {               -- NAYZEEE icon names (target scripts get the matching Font Awesome icon)
            examine = 'stetho', pulse = 'pulse', breathing = 'lungs', walk = 'walk', wait = 'hand',
        },
    },

    Radial = {
        enabled = true,         -- add Examine / Pulse / Breathing / Ask to walk to the EMS radial menu (Patient)
        range   = 3.0,          -- the radial acts on the nearest patient within this many metres
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- EXAMINATION (top-down body map)
    -- ═══════════════════════════════════════════════════════════════════════

    Exam = {
        camera     = 'topdown', -- 'topdown' (straight above the patient) or 'orbit' (right-click to orbit)
        height     = 2.6,       -- camera height above the patient (topdown) / distance (orbit)
        maxDistance = 4.0,      -- the exam closes when you are further than this from the patient
        anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base' },            -- medic kneels
        idle = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },  -- played when you touch a region
        reopenAfterTreat = true, -- come back to the examination after a treatment finished
        reopenWait = 600,       -- seconds a treatment may take before we stop waiting to reopen
        notifyPatient = true,   -- tell a player patient that a medic is examining them
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PATIENT SPEECH (subtitles while you examine)
    -- Lines are picked by pain level and the patient's sex. Translate freely.
    -- ═══════════════════════════════════════════════════════════════════════

    Speech = {
        enabled  = true,
        players  = false,      -- also show lines for PLAYER patients (they usually speak for themselves)
        onOpen   = true,       -- say something when the examination opens
        onTouch  = true,       -- say something when you touch a painful region
        cooldown = 4,          -- seconds between two lines
        duration = 3800,       -- ms a subtitle stays on screen
        -- pain thresholds (0-100) for the line groups below
        levels = { mild = 20, moderate = 45, severe = 70 },
        lines = {
            m = {
                none     = { "I'm okay... I think.", "Is it bad? Tell me straight.", "I can't feel anything there." },
                mild     = { "Ow. Easy, easy.", "That's a bit sore.", "Careful there, doc." },
                moderate = { "Argh! That hurts!", "Don't press there, please!", "Okay... okay, that one's bad." },
                severe   = { "It hurts... it hurts so bad.", "Stop, stop! Please!", "I can't... I can't breathe through it!" },
                groan    = { "Nngh...", "Mmh... hhh...", "...uhh..." },
            },
            f = {
                none     = { "I'm fine... am I fine?", "Is it bad? Tell me the truth.", "I don't feel anything there." },
                mild     = { "Ow! Gently, please.", "That's sore.", "Careful, that stings." },
                moderate = { "Ah! That really hurts!", "Please don't press there!", "Oh god, that one's bad." },
                severe   = { "It hurts so much...", "Stop! Please, stop!", "I can't take it... please help me." },
                groan    = { "Nngh...", "Mmh... hhh...", "...ahh..." },
            },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CHECK PULSE (3 steps: find it, count 15 s, judge rhythm & strength)
    -- ═══════════════════════════════════════════════════════════════════════

    Pulse = {
        minTime        = 8,      -- seconds; finishing faster is rejected (anti-cheat)
        maxTime        = 240,    -- seconds before the check times out
        easyTime       = 6,      -- progress bar length in easy mode
        countSeconds   = 15,     -- length of the count (bpm = beats x 60 / countSeconds)
        absentAfter    = 5,      -- seconds you must palpate a site before you may call "no pulse"
        radialMinSys   = 80,     -- systolic BP (mmHg) under this = no radial pulse
        carotidMinSys  = 60,     -- systolic BP under this = no carotid pulse
        weakSys        = 90,     -- systolic BP under this = weak pulse
        boundingSys    = 160,    -- systolic BP over this = bounding pulse
        tapWindow      = 0.25,   -- seconds a tap may be off a beat and still count
        startSite      = 'radial', -- site the check starts on: 'radial' | 'carotid'
        camera = { mode = 'close', dist = 0.95, pitch = 50.0, fov = 42.0 },  -- 'close' = close-up on the site, 'orbit', false = no camera
        anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },  -- kneeling, hands on the patient
        keys = { count = 'Space', none = 'KeyN', carotid = 'Digit1', radial = 'Digit2', submit = 'Enter' },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CHECK BREATHING (3 steps: look & count, listen with a stethoscope, call it)
    -- ═══════════════════════════════════════════════════════════════════════

    Breathing = {
        minTime        = 10,     -- seconds; finishing faster is rejected (anti-cheat)
        maxTime        = 300,
        easyTime       = 7,
        countSeconds   = 15,     -- length of the breath count (rate = breaths x 60 / countSeconds)
        listenSeconds  = 1.8,    -- seconds you must hold the stethoscope on a zone to "hear" it
        requireStethoscope = true, -- step 2 (listen) needs Config.Items.stethoscope (it is never used up)
        noBreathAfter  = 6,      -- seconds you must watch before you may call "no chest rise"
        drowningCrackles = 150,  -- mL of water in the lungs (hypoxia.water) that makes crackles
        haemoAbsent    = 1000,   -- haemothorax mL from which that side is silent (less = reduced)
        pneumoAbsent   = 30,     -- pneumothorax size % from which that side is silent (tension = always)
        camera = { mode = 'close', dist = 1.3, pitch = 72.0, fov = 46.0 },  -- close-up on the chest; 'topdown' | 'orbit' | false
        anim = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },  -- kneeling, hands on the patient
        listenAnim = false,      -- optional { dict, clip } played while listening (step 2)
        -- the stethoscope the medic holds while listening (Config.Props.stethoscope)
        prop = { bone = 57005, pos = vec3(0.12, 0.03, -0.02), rot = vec3(-80.0, 0.0, 0.0) },
        keys = { count = 'Space', none = 'KeyN', submit = 'Enter' },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ASK TO WALK (NPC patients follow you; players get a prompt)
    -- ═══════════════════════════════════════════════════════════════════════

    Walk = {
        enabled       = true,
        perm          = 'assess',  -- nil = anyone may ask
        allowSplinted = false,     -- true: a splinted leg fracture may walk (slowly, limping)
        maxDistance   = 40.0,      -- the NPC stops following when you get further away than this
        offset        = vec3(0.7, -1.1, 0.0), -- where the NPC walks relative to you (right, behind)
        stopRange     = 1.4,       -- metres from the offset point the NPC is happy to stop
        jogDistance   = 6.0,       -- the NPC jogs to catch up when further than this
        getUpAnim     = { dict = 'get_up@directional@movement@from_knees@action', clip = 'getup_r_0' },
        limpClipset   = 'move_m@injured', -- walk style for a patient with leg injuries
        playerPrompt  = 6000,      -- ms the "walk with the medic" prompt stays up for player patients
        cooldown      = 5,         -- seconds between two requests to the same patient
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BILLING & RECORDS
    -- ═══════════════════════════════════════════════════════════════════════

    Billing = {
        exam      = 0,      -- charge for an examination (0 = free)
        pulse     = 0,      -- charge for a pulse check
        breathing = 0,      -- charge for a breathing check
        npc       = false,  -- also "charge" NPC patients (pays the medic cut from society)
    },

    Records = true,         -- write pulse / breathing results to the patient record (nza_records)
}
