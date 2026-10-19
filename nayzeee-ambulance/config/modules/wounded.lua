--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - WOUNDED, DEATH & RESPAWN
    Discord: discord.gg/nayzeeedev

    The gameplay numbers of the downed stage (bleed-out clock, crawl on/off, give up
    time, call cooldown) and of death (arrest → death time, respawn timer, fee, item
    loss) are in config/config.lua → Config.Wounded and Config.Death.

    This file holds the look & feel of being downed (HUD, screen effects, poses,
    crawl, death camera) and the FALLBACK respawn spots. Respawn spots are normally
    built in game (/nzadmin → Hospitals → Respawn point); the list below is only used
    while no hospital has one.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.WoundedUI = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- HUD
    -- ═══════════════════════════════════════════════════════════════════════

    criticalClock   = 30,      -- the bleed-out clock turns red under this many seconds
    showInjuries    = true,    -- region + type chips on the HUD (no exact vitals are ever shown)
    maxInjuryChips  = 5,       -- more injuries collapse into a "+2" chip
    pulseLine       = true,    -- small heartbeat line next to the title
    timeFormat      = '%H:%M', -- time of death on the death screen (server time, os.date format)
    hideRadar       = { wounded = false, dead = true },  -- hide the minimap while downed / dead

    -- ═══════════════════════════════════════════════════════════════════════
    -- KEYS  (players can rebind these in Settings → Key Bindings → FiveM)
    -- Crawl uses the normal movement keys (W / S / A / D by default).
    -- The call key is Config.Wounded.callEms.key in config/config.lua.
    -- ═══════════════════════════════════════════════════════════════════════

    keys = {
        giveUp  = 'E',         -- hold to give up (after Config.Wounded.giveUp.minTime)
        respawn = 'E',         -- hold on the death screen once the respawn timer ended
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CALL EMS
    -- ═══════════════════════════════════════════════════════════════════════

    callWhileUnconscious = true,   -- false = you cannot call while AVPU is P or U (someone else has to)
    bodyRecoveryCall     = true,   -- dead players may press the call key to request body recovery
    aiMedic              = true,   -- no medic on duty → ask the AI medic module (if installed)
    codes = {                      -- dispatch codes per kind of call
        injured = '10-52',
        arrest  = '10-52',
        dead    = '10-79',
    },
    -- Used only when the dispatch module is not running: on-duty medics get a toast
    -- and a temporary map blip.
    fallbackBlip = { sprite = 153, colour = 1, scale = 1.0, time = 180 },

    -- ═══════════════════════════════════════════════════════════════════════
    -- GIVE UP
    -- ═══════════════════════════════════════════════════════════════════════

    giveUpInArrest      = true,    -- also allow giving up during cardiac arrest
    giveUpWhileTreated  = false,   -- false = blocked while a medic examines you or does CPR

    -- ═══════════════════════════════════════════════════════════════════════
    -- STATUS (what the HUD tells you about help arriving)
    -- ═══════════════════════════════════════════════════════════════════════

    onSceneDistance = 15.0,        -- an on-duty medic this close shows "MEDIC ON SCENE"
    cprWindow       = 4,           -- seconds since the last compression that still count as "CPR in progress"

    -- ═══════════════════════════════════════════════════════════════════════
    -- SCREEN EFFECTS
    -- ═══════════════════════════════════════════════════════════════════════

    effects = {
        overlay        = true,     -- NUI vignette / red edge pulse / eyelid fades
        timecycle      = true,     -- colour drains with blood loss (game timecycle)
        bloodModifier  = 'rply_saturation_neg',
        vignetteModifier = 'rply_vignette',
        unconsciousBlur = true,    -- blurred vision while AVPU is P or U
        arrestMono     = true,     -- black & white while in cardiac arrest / dead
        heartbeat      = true,     -- heartbeat sound (gets fast and weak with blood loss)
        heartbeatVolume = 0.6,     -- 0.0 - 1.0
        cameraShake    = true,     -- slight sway while wounded
    },

    -- Slow overhead camera over your body while dead (the gameplay camera returns on respawn)
    deathCam = {
        enabled = true,
        height  = 4.2,             -- metres above the body
        radius  = 2.6,             -- metres to the side
        fov     = 50.0,
        speed   = 2.5,             -- orbit speed, degrees per second
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- POSES (dict / clip; the first one that exists in the game is used)
    -- ═══════════════════════════════════════════════════════════════════════

    ragdollMs = 1800,              -- you fall over for this long before settling into a pose

    -- Every lying pose is face up, so medics can see the patient.
    poses = {
        -- conscious, torso wounds (gunshot / stab in chest, abdomen) - on the back, clutching and writhing
        writhe = {
            { dict = 'combat@damage@writhe', clip = 'writhe_loop' },
            { dict = 'combat@damage@writheidle_a', clip = 'writhe_idle_a' },
        },
        -- conscious, leg / pelvis / head injuries - on the back, in pain
        back = {
            { dict = 'combat@damage@writhe', clip = 'writhe_loop' },
            { dict = 'combat@damage@writheidle_a', clip = 'writhe_idle_a' },
        },
        -- conscious, arm or minor injuries - lying on the back, quiet
        side = {
            { dict = 'amb@world_human_bum_slumped@male@laying_on_back@base', clip = 'base' },
            { dict = 'combat@damage@writhe', clip = 'writhe_loop' },
        },
        -- unconscious (AVPU P / U), cardiac arrest and dead - flat on the back, completely still
        still = {
            { dict = 'mini@cpr@char_b@cpr_def', clip = 'cpr_pumpchest_idle' },
            { dict = 'missarmenian2', clip = 'corpse_search_exit_ped' },
        },
        -- crawling on the front
        crawl = {
            { dict = 'move_injured_ground', clip = 'front_loop' },
            { dict = 'move_crawl', clip = 'onfront_fwd' },
        },
        -- lying in a hospital bed after a respawn
        bed = {
            { dict = 'anim@gangops@morgue@table@', clip = 'body_search' },
            { dict = 'mini@cpr@char_b@cpr_def', clip = 'cpr_pumpchest_idle' },
        },
        -- getting up after a revive (played in order)
        getUp = {
            { dict = 'get_up@directional@transition@prone_to_knees@crawl', clip = 'front', ms = 1300 },
            { dict = 'get_up@directional@movement@from_knees@action', clip = 'getup_r_0', ms = 1500 },
        },
    },

    -- Which conscious pose fits the worst injury (first rule that matches wins)
    poseRules = {
        { types = { 'gunshot', 'stab', 'shrapnel', 'internal', 'burn' }, regions = { 'chest', 'back', 'abdomen' }, pose = 'writhe' },
        { types = { 'fracture' }, regions = { 'l_upper_leg', 'l_lower_leg', 'r_upper_leg', 'r_lower_leg', 'pelvis' }, pose = 'back' },
        { regions = { 'head', 'face', 'neck', 'pelvis' }, pose = 'back' },
        { regions = { 'l_upper_arm', 'l_lower_arm', 'r_upper_arm', 'r_lower_arm' }, pose = 'side' },
    },
    defaultPose = 'writhe',

    -- ═══════════════════════════════════════════════════════════════════════
    -- CRAWL  (on/off and speed: Config.Wounded.crawl / crawlSpeed)
    -- ═══════════════════════════════════════════════════════════════════════

    crawl = {
        toggle      = true,        -- true: W starts crawling, S stops. false: crawl only while W is held
        turnSpeed   = 70.0,        -- degrees per second with A / D
        speed       = 0.32,        -- metres per second when the animation has no root motion (× crawlSpeed)
        armPenalty  = 0.6,         -- speed multiplier with an unsplinted broken arm
        stamina     = 22,          -- seconds of crawling before you have to rest
        recover     = 6,           -- seconds of rest to recover fully
        lossPenalty = 0.6,         -- stamina multiplier at heavy blood loss
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- RESPAWN
-- ═══════════════════════════════════════════════════════════════════════════

Config.Respawn = {
    fadeMs     = 900,          -- screen fade when you respawn
    useBed     = true,         -- wake up in a free hospital bed (when one is built / listed below)
    bedTime    = 8,            -- seconds you lie in the bed before you get up
    bedOffset  = vec3(0.0, 0.0, 0.0),  -- nudge the body if it floats above / sinks into your beds
    ackTimeout = 20,           -- seconds the server waits for your client before moving you itself

    -- Fallback spots: only used while no hospital has a respawn point built in game.
    -- coords = where you stand up; beds = optional beds to wake up in (vec4).
    -- The nearest spot to where you died is used.
    points = {
        {
            label  = 'Pillbox Hill Medical Center',
            coords = vec4(298.63, -584.55, 43.26, 68.0),
            beds   = {},   -- e.g. { vec4(x, y, z, heading), ... } for your hospital MLO
        },
        {
            label  = 'Sandy Shores Medical Center',
            coords = vec4(1839.39, 3672.93, 34.28, 210.0),
            beds   = {},
        },
        {
            label  = 'Paleto Bay Care Center',
            coords = vec4(-247.76, 6331.23, 32.43, 225.0),
            beds   = {},
        },
    },
}
