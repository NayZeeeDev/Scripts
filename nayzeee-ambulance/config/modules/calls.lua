--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - NPC 911 CALLS, SCENES, NPC PATIENTS & AI MEDIC
    Discord: discord.gg/nayzeeedev

    While enough medics are on duty with "NPC calls" switched on (EMS job menu →
    Dispatch → NPC calls, the pager menu or the dispatch board), the city phones in
    emergencies. Each call is built from a template below:

        template  → title, 10-code, priority, where it can happen, who is hurt and how,
                    crashed cars / props / smoke & fire, the 911 caller's voice line
        scene     → built when the first medic gets close (networked peds, cars, props)
        patients  → real NPC patients: every injury and condition can be examined and
                    treated with the full toolset, then brought to a hospital bed
        hand-over → placing the patient on a hospital BED pays the crew (and the society)

    The AI medic (Config.AIMedic at the bottom) answers downed PLAYERS when no medic
    is on duty: an AI ambulance drives in with lights and siren, treats, loads and
    brings the patient to the nearest hospital bed.

    Locations are vector4(x, y, z, heading) and only need to be close: the scene snaps
    to the nearest road (snap = 'road') or walkable ground (snap = 'ped') when it is built.
    Text and voice-line wording is in locales/en/calls.lua, voice files in html/audio/calls/.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Calls = {

    enabled = true,

    -- ═══════════════════════════════════════════════════════════════════════
    -- GENERATION
    -- ═══════════════════════════════════════════════════════════════════════

    generation = {
        enabled          = true,
        minMedics        = 1,              -- opted-in medics on duty needed before NPC calls are generated
        optInDefault     = true,           -- a medic who never toggled "NPC calls" counts as opted in
        tick             = 5,              -- seconds between generator checks
        firstDelay       = { 45, 120 },    -- seconds before the first call after enough medics came on duty
        interval         = { 240, 540 },   -- seconds between calls (random in this range)
        perMedicSpeedup  = 0.15,           -- each extra opted-in medic shortens the interval by 15 % (max 60 %)
        maxActive        = 3,              -- NPC calls open at the same time (hard cap)
        maxPerMedic      = 2,              -- ...and at most this many per opted-in medic
        minDistance      = 350.0,          -- a new call is at least this far from every opted-in medic
        maxDistance      = 3500.0,         -- ...and within this distance of at least one (relaxed when nothing fits)
        sceneSpacing     = 250.0,          -- minimum distance between two open NPC scenes
        locationCooldown = 1800,           -- seconds before the same location can be used again
        repeatType       = 0.25,           -- chance-weight multiplier for the same type as the last call
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- SCENES (networked peds / vehicles / props, built near the first medic)
    -- ═══════════════════════════════════════════════════════════════════════

    scene = {
        spawnRadius      = 220.0,          -- a medic within this distance of a waiting call builds the scene
        buildTimeout     = 20,             -- seconds the chosen client has to build it before another one is asked
        maxBuildAttempts = 3,              -- failed builds before the call is cancelled
        buildRadius      = 70.0,           -- built entities must be within this distance of the call (anti-cheat)
        modelTimeout     = 8000,           -- ms to wait for a model to load before skipping it
        sceneTimeout     = 2700,           -- seconds a built scene may exist in total
        cleanupDelay     = 45,             -- seconds after the call closed before the scene is cleaned up...
        playerRadius     = 90.0,           -- ...once no player is within this distance (keeps it from vanishing in view)
        maxCleanupWait   = 600,            -- ...or after this many seconds whatever happens
        orphanTimeout    = 300,            -- patients taken away from the scene (stretcher, vehicle, bed) and then
                                           -- left with nobody within playerRadius are removed after this many seconds
        noMedicTimeout   = 300,            -- no opted-in medic on duty for this long → waiting calls are cancelled
        bystanders       = true,           -- spawn the 911 caller / bystanders at the scene
        hazardLights     = true,           -- crashed vehicles flash their hazard lights
        crashLights      = true,           -- crashed vehicles keep their headlights / interior light on
        maxProps         = 10,             -- props spawned per scene (limits network entities)
        onlookers = {
            enabled   = true,              -- passers-by keep their distance and film the scene
            count     = { 0, 2 },          -- per scene (a template can override: onlookers = { 1, 3 } or false)
            max       = 3,
            distance  = { 7.0, 12.0 },     -- metres from the scene
            scenarios = { 'WORLD_HUMAN_MOBILE_FILM_SHOCKING', 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_STAND_IMPATIENT' },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- GROUND DETAIL (decals drawn by every client near a scene, nothing networked)
    -- ═══════════════════════════════════════════════════════════════════════

    decals = {
        enabled  = true,
        radius   = 120.0,                  -- decals exist while you are this close to the scene
        lifetime = 2400.0,                 -- seconds (they are removed with the scene anyway)
        -- type = GTA decal id, size = metres, tint = r g b 0..1, opacity 0..1
        blood    = { type = 9015, size = { 0.55, 0.95, 1.45 }, tint = { 0.48, 0.03, 0.03 }, opacity = 0.92, max = 4 },  -- pool under a bleeding patient, grows with the bleeding (1..3)
        splatter = { type = 1010, size = 0.8, tint = { 0.45, 0.02, 0.02 }, opacity = 0.85,                              -- spray around the patient for these call types
                     types = { gunshot = true, stab = true, mva = true, assault = true, crush = true } },
        oil      = { type = 9016, size = 1.7, tint = { 0.10, 0.08, 0.06 }, opacity = 0.9 },   -- leaking fluids under a smoking / burning car
        water    = { type = 9010, size = 1.8, tint = { 0.70, 0.72, 0.75 }, opacity = 0.75 },  -- puddle under soaked patients (wet templates)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- THE CALL (dispatch card, pager, voice)
    -- ═══════════════════════════════════════════════════════════════════════

    call = {
        voice       = true,                -- attach the recorded 911 call to the dispatch card
        voiceMode   = 'full',              -- 'full' = dispatcher radio + caller | 'caller' | 'dispatcher'
        voiceFolder = 'audio/calls/',      -- under html/ (files: <line>.ogg, <dispatcher>.ogg, <line>_full.ogg)
        phonePrefix = '555-',              -- caller phone numbers look like 555-0142
        showCaller  = true,                -- show the caller's name and number on the card
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- NPC PATIENT BEHAVIOUR (every NPC patient, not only the ones from calls)
    -- ═══════════════════════════════════════════════════════════════════════

    npc = {
        enabled      = true,
        radius       = 120.0,              -- NPC patients within this distance are animated by their owner
        tick         = 600,                -- ms between behaviour checks
        invincible   = true,               -- GTA damage can't kill an NPC patient (the injury system decides)
        keepBodies   = true,               -- dead NPC patients stay as bodies until the scene is cleaned up
        speech = {
            enabled     = true,
            medicOnly   = true,            -- only talk while an on-duty medic is close
            radius      = 6.0,             -- a medic this close makes the patient talk / groan
            subtitles   = 10.0,            -- players within this distance see the subtitle
            interval    = { 9, 18 },       -- seconds between lines of one patient
            sounds      = true,            -- GTA pain / ambient speech sounds with the lines
            ms          = 3800,            -- subtitle time
            -- GTA sounds per kind of line: pain = PlayPain ids, speech = ambient speech name
            sounds_map  = {
                pain     = { pain = { 6, 7, 8 } },
                groan    = { pain = { 6 } },
                thanks   = { speech = 'GENERIC_THANKS' },
                confused = { speech = 'GENERIC_WHATEVER' },
                scared   = { speech = 'GENERIC_FRIGHTENED_MED' },
                shout    = { speech = 'GENERIC_SHOCKED_HIGH' },
            },
        },
        flee = {
            enabled  = true,               -- walking NPC patients run from gunfire, then come back
            radius   = 30.0,               -- shots within this distance
            time     = 8,                  -- seconds they run
        },
        release = {
            enabled  = true,               -- "Release on scene" for walking patients who need no hospital
            perm     = 'assess',
            walkTime = 25,                 -- seconds they walk away before they are removed
        },
        -- Animations per pose. The first entry that exists is used (dict + clip, or a scenario).
        poses = {
            writhe      = { { dict = 'combat@damage@writhe', clip = 'writhe_loop' }, { dict = 'combat@damage@rb_writhe', clip = 'rb_writhe_loop' } },
            unconscious = { { dict = 'missarmenian2', clip = 'drunk_loop' }, { dict = 'dead', clip = 'dead_a' } },
            overdose    = { { dict = 'missarmenian2', clip = 'drunk_loop' }, { dict = 'dead', clip = 'dead_c' } },
            arrest      = { { dict = 'mini@cpr@char_b@cpr_def', clip = 'cpr_pumpchest_idle' }, { dict = 'dead', clip = 'dead_a' } },
            dead        = { { dict = 'dead', clip = 'dead_a' }, { dict = 'dead', clip = 'dead_b' } },
            sit         = { { dict = 'amb@world_human_picnic@male@base', clip = 'base' }, { dict = 'anim@heists@fleeca_bank@ig_7_jetski_owner', clip = 'owner_idle' } },
            sit_f       = { { dict = 'amb@world_human_picnic@female@base', clip = 'base' }, { dict = 'amb@world_human_picnic@male@base', clip = 'base' } },
            cold        = { { dict = 'amb@world_human_bum_slumped@male@laying_on_left_side@base', clip = 'base' }, { dict = 'missarmenian2', clip = 'drunk_loop' } },
            hurt        = { { dict = 'amb@world_human_bum_standing@depressed@idle_a', clip = 'idle_a' }, { scenario = 'WORLD_HUMAN_STAND_IMPATIENT' } },
            stand       = { { scenario = 'WORLD_HUMAN_STAND_IMPATIENT' } },
            trapped     = { { dict = 'random@crash_rescue@car_death@std_car', clip = 'loop' }, { dict = 'veh@std@ds@base', clip = 'sit' } },
        },
        getUp = { dict = 'get_up@directional@movement@from_knees@action', clip = 'getup_r_0', ms = 1800 },
        -- injured walk for patients standing with leg / pelvis injuries
        limpClipset = 'move_m@injured',
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- SCENE EFFECTS (smoking / burning vehicles, fires)
    -- ═══════════════════════════════════════════════════════════════════════

    fx = {
        radius   = 180.0,                  -- particles are drawn within this distance
        duration = { 420, 720 },           -- seconds smoke / fire keeps going by itself
        smoke = { asset = 'scr_agencyheistb', name = 'scr_env_agency3b_smoke', scale = 0.55, bone = 'engine', offset = vector3(0.0, 0.4, 0.4) },
        fire  = { asset = 'core', name = 'fire_wrecked_plane_cockpit', scale = 0.45, bone = 'engine', offset = vector3(0.0, 0.2, 0.3) },
        groundFire  = { asset = 'core', name = 'ent_ray_heli_aprtmnt_l_fire', scale = 0.55 },
        groundSmoke = { asset = 'core', name = 'ent_amb_smoke_foundry', scale = 0.35 },
        engineSmoke = true,                -- also lower the engine health so GTA draws its own engine smoke
        -- putting it out
        cutEngine = { time = 4, distance = 3.2, anim = { dict = 'mini@repair', clip = 'fixing_a_ped' } },  -- [E] hold: smoke
        spray     = { weapon = 'WEAPON_FIREEXTINGUISHER', time = 3.5, distance = 9.0 },                  -- spray the extinguisher at a fire
        fireNeedsExtinguisher = true,      -- false = fires can also be smothered with [E] hold (blanket)
        smother   = { time = 6, distance = 2.6, anim = { dict = 'missheistdockssetup1clipboard@base', clip = 'base' } },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- TRAPPED VICTIMS (crashed cars, crush accidents)
    -- ═══════════════════════════════════════════════════════════════════════

    extricate = {
        enabled   = true,
        perm      = 'transport',           -- permission needed to cut someone free
        time      = 12,                    -- seconds of work (hold the interaction)
        distance  = 2.6,
        anim      = { dict = 'mini@repair', clip = 'fixing_a_ped' },
        prop      = 'prop_ing_crowbar',    -- native prop in the medic's hand while cutting (false = none)
        breakDoor = true,                  -- the door comes off the car
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- HAND-OVER & REWARDS
    -- ═══════════════════════════════════════════════════════════════════════

    handover = {
        types        = { bed = true },     -- hospital point types that count as "handed over" (ward bed)
        despawnDelay = 90,                 -- seconds the patient stays in the bed before being admitted (removed)
        notify       = true,               -- toast the crew with the reward
    },

    rewards = {
        enabled  = true,
        account  = 'bank',                 -- 'bank' | 'cash'
        -- base pay per patient by triage when the call came in (1 critical, 2 urgent, 3 standard)
        base     = { [1] = 1200, [2] = 800, [3] = 500 },
        -- multiplier by the patient's state at the hand-over
        outcome  = { alive = 1.0, wounded = 0.8, arrest = 0.35, dead = 0.15 },
        released = 0.55,                   -- multiplier for patients released on scene (no transport needed)
        perProcedure     = 60,             -- bonus per treatment / procedure done on the patient
        maxProcedureBonus = 600,
        fastResponse = { within = 300, amount = 150 },  -- bonus when the first unit reached the scene within N seconds
        split    = 'share',                -- 'share' = the amount is split across the crew | 'each' = everyone gets it
        minShare = 100,                    -- nobody in the crew gets less than this
        crewTimeout = 1800,                -- treatments older than this (s) don't count someone as crew
        society  = { enabled = true, cut = 0.30, name = nil },  -- society gets this share on top; nil = department / Config.Billing.society
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ADMIN / TESTING
    -- ═══════════════════════════════════════════════════════════════════════

    admin = {
        command      = 'nzacall',          -- /nzacall [type] [here]  create an NPC call (admins) - 'here' builds it next to you
        clearCommand = 'nzacallclear',     -- /nzacallclear  remove every NPC scene
        listCommand  = 'nzacalls',         -- /nzacalls  print the open scenes in the server console / chat
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PED MODEL POOLS (used by the templates below)
    -- ═══════════════════════════════════════════════════════════════════════

    pools = {
        civ_m    = { 'a_m_y_downtown_01', 'a_m_y_genstreet_01', 'a_m_y_genstreet_02', 'a_m_y_hipster_01', 'a_m_y_hipster_02', 'a_m_m_business_01',
                     'a_m_y_business_01', 'a_m_m_eastsa_01', 'a_m_y_eastsa_02', 'a_m_m_soucent_01', 'a_m_y_stwhi_01', 'a_m_y_stbla_01',
                     'a_m_m_genfat_01', 'a_m_y_vinewood_01', 'a_m_m_bevhills_01', 'a_m_y_latino_01', 'a_m_m_skater_01', 'a_m_m_ktown_01' },
        civ_f    = { 'a_f_y_hipster_01', 'a_f_y_hipster_02', 'a_f_y_genhot_01', 'a_f_y_business_01', 'a_f_m_business_02', 'a_f_y_eastsa_01',
                     'a_f_m_eastsa_01', 'a_f_y_soucent_01', 'a_f_m_soucent_01', 'a_f_y_vinewood_01', 'a_f_m_bevhills_01', 'a_f_y_tourist_01',
                     'a_f_m_downtown_01', 'a_f_y_scdressy_01', 'a_f_m_ktown_01' },
        drug_m   = { 'a_m_m_tramp_01', 'a_m_o_tramp_01', 'a_m_y_methhead_01', 'a_m_m_hillbilly_01', 'a_m_y_hippy_01', 'a_m_m_trampbeac_01', 'a_m_m_salton_02' },
        drug_f   = { 'a_f_m_tramp_01', 'a_f_m_trampbeac_01', 'a_f_y_rurmeth_01', 'a_f_y_hippie_01' },
        work_m   = { 's_m_y_construct_01', 's_m_y_construct_02', 's_m_m_dockwork_01', 's_m_y_dockwork_01', 's_m_m_gaffer_01', 's_m_m_lathandy_01' },
        gang_m   = { 'g_m_y_ballaeast_01', 'g_m_y_ballasout_01', 'g_m_y_famca_01', 'g_m_y_famdnf_01', 'g_m_y_mexgoon_01', 'g_m_y_mexgoon_02',
                     'g_m_y_salvagoon_01', 'a_m_y_stbla_02', 'a_m_y_soucent_01' },
        gang_f   = { 'g_f_y_ballas_01', 'g_f_y_families_01', 'a_f_y_soucent_02' },
        beach_m  = { 'a_m_y_beach_01', 'a_m_y_beach_02', 'a_m_m_beach_01', 'a_m_y_musclbeac_01', 'a_m_y_surfer_01' },
        beach_f  = { 'a_f_y_beach_01', 'a_f_m_beach_01' },
        sport_m  = { 'a_m_y_runner_01', 'a_m_y_runner_02', 'a_m_m_golfer_01', 'a_m_m_tennis_01', 'a_m_y_motox_01' },
        sport_f  = { 'a_f_y_runner_01', 'a_f_y_fitness_01', 'a_f_y_fitness_02', 'a_f_y_tennis_01' },
        old_m    = { 'a_m_o_genstreet_01', 'a_m_o_soucent_01', 'a_m_o_soucent_02', 'a_m_o_soucent_03', 'a_m_o_beach_01', 'a_m_o_ktown_01' },
        old_f    = { 'a_f_o_genstreet_01', 'a_f_o_soucent_01', 'a_f_o_soucent_02', 'a_f_o_ktown_01', 'a_f_o_indian_01' },
        rural_m  = { 'a_m_m_hillbilly_01', 'a_m_m_hillbilly_02', 'a_m_m_salton_01', 'a_m_m_salton_02', 'a_m_m_farmer_01', 'a_m_y_hippy_01' },
        rural_f  = { 'a_f_m_salton_01', 'a_f_y_rurmeth_01', 'a_f_m_fatcult_01' },
    },

    -- vehicle model pools for crashes
    vehiclePools = {
        cars  = { 'asea', 'asterope', 'emperor', 'fugitive', 'ingot', 'intruder', 'premier', 'primo', 'regina', 'stanier', 'stratum',
                  'tailgater', 'washington', 'glendale', 'blista', 'issi2', 'panto', 'prairie', 'buffalo', 'felon', 'oracle', 'sultan' },
        suv   = { 'baller', 'granger', 'rancherxl', 'sadler', 'bison', 'minivan', 'speedo', 'dubsta', 'cavalcade', 'landstalker', 'seminole' },
        rural = { 'sadler', 'bodhi2', 'rebel', 'emperor2', 'bison', 'rancherxl', 'tornado3', 'dloader' },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- SCENARIO TEMPLATES
    --   weight    how often it is picked          priority 1 critical | 2 urgent | 3 routine
    --   code      10-code on the card              type     dispatch icon / blip
    --   title     locale key                       snap     'road' | 'ped' | 'none'
    --   victims   roles: count {min,max}, chance, peds (pool names), offset (x right, y forward, z),
    --             state weights, pose hint, loss {min,max}, age, conditions, injuries, vehicle + seat,
    --             trapped chance, damage packs (blood / burns on the model)
    --   injuries  { type, regions = {...}, sev = {min,max}, chance, count = {min,max}, + core fields
    --             (fracture = { kind, bone }, internal = { organ }, burn = { degree, area }) }
    --   vehicles  { pool, offset, heading (relative), damage = { front, rear, left, right } 0..1,
    --             windows, doors, tyres, smoke chance, fire chance, flip }
    --   props     { models = {...}, offset, rot, chance }         fx { kind = 'smoke'|'fire'|'groundFire'|'groundSmoke', offset, chance }
    --   callers   voice lines (locale 'calls.line.<id>', file html/audio/calls/<id>.ogg), sex of the caller
    --   dispatcher  line id read by dispatch before the caller in voiceMode 'full'
    --   reward    multiplier on the hand-over pay
    --   onlookers {min,max} passers-by filming the scene (false = none; default scene.onlookers.count)
    --   wet       victims are soaked (water puddle decal, wet clothes)
    -- ═══════════════════════════════════════════════════════════════════════

    templates = {

        -- ─── Opioid overdose ────────────────────────────────────────────────
        overdose = {
            enabled = true, weight = 12, priority = 2, code = '10-56', type = 'overdose', title = 'calls.t_overdose', snap = 'ped', reward = 1.0,
            onlookers = { 0, 1 },                 -- passers-by filming (overrides scene.onlookers.count)
            locations = {
                vector4(486.4, -1774.8, 28.6, 90.0),      -- Rancho, alley off Jamestown St
                vector4(230.6, -1515.0, 29.3, 140.0),     -- Strawberry, behind the shops
                vector4(400.9, -1029.0, 29.3, 0.0),       -- Mission Row, back street
                vector4(197.4, -933.6, 30.7, 145.0),      -- Legion Square
                vector4(1100.3, -645.0, 56.8, 270.0),     -- Mirror Park lake
                vector4(-1172.9, -1572.6, 4.7, 125.0),    -- Vespucci Beach, Muscle Sands
                vector4(705.1, -1255.4, 25.8, 90.0),      -- LS River underpass
                vector4(-584.8, -1006.6, 22.2, 90.0),     -- Little Seoul
                vector4(1958.0, 3797.8, 32.2, 30.0),      -- Sandy Shores trailers
                vector4(60.6, 3705.6, 39.8, 120.0),       -- Stab City
                vector4(-275.2, 6239.8, 31.5, 315.0),     -- Paleto Bay alley
                vector4(1696.6, 4785.1, 41.9, 90.0),      -- Grapeseed
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'drug_m', f = 'drug_f' }, female = 0.35, age = { 19, 52 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { wounded = 1 }, pose = 'overdose', loss = { 0.0, 0.03 },
                  conditions = {
                      overdose = { drug = 'opioid', amount = { 60, 95 } },
                      hypoxia  = { cause = 'airway', chance = 0.55 },
                      airway   = { kind = 'unconscious', chance = 0.45 },
                  },
                  injuries = {
                      { type = 'abrasion', regions = { 'face', 'l_lower_arm', 'r_lower_arm' }, sev = { 1, 1 }, chance = 0.4 },
                      { type = 'contusion', regions = { 'head' }, sev = { 1, 2 }, chance = 0.25 },
                  },
                },
                { count = { 1, 1 }, chance = 0.15, peds = { m = 'drug_m', f = 'drug_f' }, female = 0.4, age = { 19, 45 }, offset = vector3(1.6, 0.8, 0.0),
                  state = { alive = 1 }, pose = 'sit', conditions = { overdose = { drug = 'opioid', amount = { 25, 45 } } } },
            },
            props = {
                { models = { 'prop_syringe_01' }, offset = vector3(0.55, 0.35, 0.0), chance = 0.9 },
                { models = { 'prop_cs_pills', 'prop_ld_flow_bottle' }, offset = vector3(-0.6, 0.4, 0.0), chance = 0.6 },
                { models = { 'prop_rub_binbag_01', 'prop_ld_binbag_01' }, offset = vector3(-1.2, -0.8, 0.0), chance = 0.5 },
            },
            callers = { { line = 'overdose_c1', sex = 'f' }, { line = 'overdose_c2', sex = 'm' }, { line = 'overdose_c3', sex = 'f' } },
            dispatcher = 'overdose_d',
            bystander = { offset = vector3(2.5, 2.0, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },

        -- ─── Motor vehicle accident ─────────────────────────────────────────
        mva = {
            enabled = true, weight = 16, priority = 1, code = '10-50', type = 'mva', title = 'calls.t_mva', snap = 'road', reward = 1.2,
            onlookers = { 1, 3 },                 -- passers-by filming (overrides scene.onlookers.count)
            roadside = 3.6,                       -- metres from the road node towards the kerb
            locations = {
                vector4(140.5, -1062.5, 29.2, 70.0),      -- Vespucci Blvd, downtown
                vector4(-536.4, -680.5, 33.2, 0.0),       -- Ginger St, Little Seoul
                vector4(-689.5, -945.6, 20.1, 90.0),      -- Palomino Ave
                vector4(279.6, -1453.2, 29.3, 230.0),     -- Strawberry Ave
                vector4(-1250.3, -1171.6, 7.5, 280.0),    -- Vespucci
                vector4(-1409.2, -538.5, 30.9, 300.0),    -- Del Perro Blvd
                vector4(404.7, 101.1, 101.0, 70.0),       -- Downtown Vinewood
                vector4(1170.7, -489.1, 65.3, 350.0),     -- Mirror Park Blvd
                vector4(-656.7, -114.4, 37.8, 300.0),     -- Rockford Hills
                vector4(805.1, -1290.9, 26.3, 180.0),     -- La Mesa
                vector4(1964.7, 3750.6, 32.2, 300.0),     -- Sandy Shores
                vector4(1692.8, 4798.8, 41.9, 90.0),      -- Grapeseed Main St
                vector4(-196.5, 6319.0, 31.4, 45.0),      -- Paleto Blvd
                vector4(530.0, 2690.0, 42.2, 5.0),        -- Route 68, Harmony
                vector4(-3091.4, 1196.3, 20.4, 180.0),    -- Great Ocean Hwy, Chumash
            },
            vehicles = {
                { pool = 'cars', offset = vector3(0.0, 0.0, 0.0), heading = 18.0,
                  damage = { front = 1.0, left = 0.35 }, windows = { 0, 1, 6 }, doors = { 4 }, tyres = 0.4, smoke = 0.85, fire = 0.15 },
                { pool = 'suv', chance = 0.55, offset = vector3(-2.6, 6.2, 0.0), heading = 150.0,
                  damage = { front = 0.7, right = 0.5 }, windows = { 1 }, doors = {}, tyres = 0.2, smoke = 0.3, fire = 0.0 },
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'civ_m', f = 'civ_f' }, female = 0.4, age = { 18, 70 }, vehicle = 1, seat = -1, trapped = 0.4,
                  state = { wounded = 0.75, alive = 0.25 }, loss = { 0.06, 0.22 }, damagePacks = { 'Car_Crash_Heavy', 'BigHitByVehicle' },
                  conditions = { concussion = { grade = { 1, 3 }, chance = 0.45 }, spinal = { level = 'cervical', chance = 0.12 } },
                  injuries = {
                      { type = 'fracture', regions = { 'l_lower_leg', 'r_lower_leg', 'l_upper_leg', 'r_upper_leg' }, sev = { 2, 4 }, chance = 0.75 },
                      { type = 'internal', regions = { 'abdomen', 'pelvis' }, sev = { 2, 3 }, chance = 0.45 },
                      { type = 'laceration', regions = { 'head', 'face', 'l_lower_arm', 'r_lower_arm' }, sev = { 1, 3 }, chance = 0.8, count = { 1, 2 } },
                      { type = 'fracture', regions = { 'pelvis' }, sev = { 3, 4 }, chance = 0.2 },
                      { type = 'contusion', regions = { 'chest' }, sev = { 2, 3 }, chance = 0.5 },
                  },
                },
                { count = { 0, 1 }, peds = { m = 'civ_m', f = 'civ_f' }, female = 0.5, age = { 16, 75 }, vehicle = 1, seat = 0, trapped = 0.15,
                  state = { wounded = 0.6, alive = 0.4 }, loss = { 0.03, 0.15 }, damagePacks = { 'Car_Crash_Light' },
                  injuries = {
                      { type = 'fracture', regions = { 'l_lower_arm', 'r_lower_arm', 'chest' }, sev = { 1, 3 }, chance = 0.6 },
                      { type = 'laceration', regions = { 'face', 'l_upper_arm', 'r_upper_arm' }, sev = { 1, 2 }, chance = 0.7 },
                      { type = 'contusion', regions = { 'abdomen', 'chest' }, sev = { 1, 2 }, chance = 0.6 },
                  },
                },
                { count = { 0, 1 }, peds = { m = 'civ_m', f = 'civ_f' }, female = 0.45, age = { 17, 65 }, offset = vector3(3.2, 3.5, 0.0),
                  state = { wounded = 0.8, alive = 0.2 }, pose = 'writhe', loss = { 0.08, 0.2 }, damagePacks = { 'HitByVehicle', 'Car_Crash_Heavy' },
                  injuries = {
                      { type = 'fracture', regions = { 'l_lower_leg', 'r_lower_leg', 'pelvis' }, sev = { 2, 4 }, chance = 0.8 },
                      { type = 'abrasion', regions = { 'l_upper_arm', 'r_upper_arm', 'l_upper_leg', 'face' }, sev = { 1, 3 }, chance = 0.9, count = { 1, 2 } },
                      { type = 'internal', regions = { 'abdomen' }, sev = { 2, 3 }, chance = 0.35 },
                  },
                },
            },
            maxVictims = 3,
            props = {
                { models = { 'prop_rub_carpart_02', 'prop_rub_carpart_03', 'prop_rub_carpart_04', 'prop_rub_carpart_05' }, offset = vector3(1.2, 3.4, 0.0), chance = 0.9 },
                { models = { 'prop_rub_tyre_01', 'prop_rub_wheel_01' }, offset = vector3(-1.8, 4.2, 0.0), chance = 0.5 },
                { models = { 'prop_rub_carpart_02', 'prop_rub_carpart_05' }, offset = vector3(2.4, -1.0, 0.0), chance = 0.6 },
            },
            callers = { { line = 'mva_c1', sex = 'm' }, { line = 'mva_c2', sex = 'f' }, { line = 'mva_c3', sex = 'm' } },
            dispatcher = 'mva_d',
            bystander = { offset = vector3(5.5, -2.0, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },

        -- ─── Fall from height (construction) ────────────────────────────────
        fall = {
            enabled = true, weight = 9, priority = 1, code = '10-52', type = 'fall', title = 'calls.t_fall', snap = 'ped', reward = 1.1,
            locations = {
                vector4(-147.4, -977.5, 27.3, 160.0),     -- Pillbox Hill high-rise construction
                vector4(-509.9, -1001.6, 23.6, 90.0),     -- Little Seoul construction site
                vector4(1196.9, -3105.4, 5.9, 0.0),       -- Port of Los Santos
                vector4(857.9, -2928.0, 5.9, 90.0),       -- Port of Los Santos, container yard
                vector4(-117.6, -2414.5, 6.0, 180.0),     -- Elysian Island docks
                vector4(-573.0, 5268.5, 70.5, 60.0),      -- Paleto Forest sawmill
                vector4(2942.3, 2786.4, 40.4, 300.0),     -- Davis Quartz quarry
                vector4(1735.0, 3290.0, 41.2, 195.0),     -- Sandy Shores airfield hangar
                vector4(2441.0, 4970.0, 46.8, 45.0),      -- O'Neil ranch barn
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'work_m', f = 'civ_f' }, female = 0.05, age = { 20, 60 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { wounded = 0.85, alive = 0.15 }, pose = 'writhe', loss = { 0.05, 0.18 }, damagePacks = { 'Fall', 'Fall_Low' },
                  conditions = { concussion = { grade = { 1, 3 }, chance = 0.5 }, spinal = { level = 'thoracic', chance = 0.15 } },
                  injuries = {
                      { type = 'fracture', regions = { 'l_lower_leg', 'r_lower_leg', 'l_upper_leg', 'r_upper_leg' }, sev = { 2, 4 }, chance = 0.9 },
                      { type = 'fracture', regions = { 'l_lower_arm', 'r_lower_arm' }, sev = { 1, 3 }, chance = 0.45 },
                      { type = 'fracture', regions = { 'pelvis' }, sev = { 2, 4 }, chance = 0.25 },
                      { type = 'contusion', regions = { 'head', 'back' }, sev = { 1, 3 }, chance = 0.7 },
                      { type = 'abrasion', regions = { 'l_upper_arm', 'r_upper_arm', 'face' }, sev = { 1, 2 }, chance = 0.6 },
                  },
                },
            },
            props = {
                { models = { 'prop_barrier_work05', 'prop_barrier_work06a' }, offset = vector3(-2.2, 2.0, 0.0), rot = vector3(0.0, 0.0, 30.0), chance = 0.8 },
                { models = { 'prop_tool_box_04', 'prop_toolchest_01' }, offset = vector3(1.4, -0.9, 0.0), chance = 0.7 },
                { models = { 'prop_cementbags01', 'prop_pallet_02a' }, offset = vector3(-1.6, -2.4, 0.0), chance = 0.6 },
                { models = { 'prop_roadcone02a' }, offset = vector3(2.6, 2.4, 0.0), chance = 0.6 },
            },
            callers = { { line = 'fall_c1', sex = 'm' }, { line = 'fall_c2', sex = 'm' }, { line = 'fall_c3', sex = 'f' } },
            dispatcher = 'fall_d',
            bystander = { pool = 'work_m', offset = vector3(2.2, 1.6, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },

        -- ─── Street shooting ────────────────────────────────────────────────
        gunshot = {
            enabled = true, weight = 11, priority = 1, code = '10-52', type = 'gunshot', title = 'calls.t_gunshot', snap = 'ped', reward = 1.25,
            onlookers = { 1, 3 },                 -- passers-by filming (overrides scene.onlookers.count)
            locations = {
                vector4(105.9, -1940.6, 20.8, 45.0),      -- Grove Street
                vector4(-133.6, -1596.2, 34.6, 140.0),    -- Forum Drive
                vector4(85.5, -1684.2, 29.2, 230.0),      -- Davis
                vector4(453.0, -1730.0, 29.0, 320.0),     -- Rancho
                vector4(-180.0, -1565.0, 35.0, 50.0),     -- Chamberlain Hills
                vector4(167.3, -1350.9, 29.3, 140.0),     -- Strawberry
                vector4(1260.0, -1720.0, 54.0, 20.0),     -- El Burro Heights
                vector4(330.2, 178.9, 103.1, 70.0),       -- Vinewood Blvd
                vector4(-1066.5, -1010.0, 2.2, 120.0),    -- Vespucci Canals
                vector4(830.0, -2160.0, 29.6, 0.0),       -- Cypress Flats
                vector4(1912.0, 3732.0, 32.6, 210.0),     -- Sandy Shores
                vector4(-121.6, 6309.6, 31.4, 135.0),     -- Paleto Bay
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'gang_m', f = 'gang_f' }, female = 0.15, age = { 17, 40 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { wounded = 0.9, arrest = 0.1 }, pose = 'writhe', loss = { 0.1, 0.25 }, damagePacks = { 'TD_PISTOL_FRONT', 'TD_PISTOL_REAR' },
                  conditions = { arrest = { rhythm = 'pea', onlyIfState = 'arrest' } },
                  injuries = {
                      { type = 'gunshot', regions = { 'chest', 'abdomen', 'l_upper_leg', 'r_upper_leg', 'l_upper_arm', 'r_upper_arm', 'back' }, sev = { 2, 4 }, chance = 1.0, count = { 1, 3 } },
                      { type = 'abrasion', regions = { 'face', 'l_lower_arm', 'r_lower_arm' }, sev = { 1, 1 }, chance = 0.5 },
                  },
                },
                { count = { 1, 1 }, chance = 0.35, peds = { m = 'gang_m', f = 'gang_f' }, female = 0.2, age = { 17, 40 }, offset = vector3(-3.5, 4.0, 0.0),
                  state = { wounded = 0.5, alive = 0.5 }, pose = 'sit', loss = { 0.04, 0.12 }, damagePacks = { 'TD_PISTOL_FRONT' },
                  injuries = {
                      { type = 'gunshot', regions = { 'l_upper_arm', 'r_upper_arm', 'l_lower_leg', 'r_lower_leg', 'l_upper_leg' }, sev = { 1, 3 }, chance = 1.0 },
                  },
                },
            },
            props = {
                { models = { 'w_pi_pistol_mag1', 'prop_ld_flow_bottle' }, offset = vector3(1.4, 1.1, 0.0), chance = 0.4 },
                { models = { 'prop_amb_phone', 'prop_cs_phone_01' }, offset = vector3(-0.9, 0.7, 0.0), chance = 0.5 },
            },
            callers = { { line = 'gunshot_c1', sex = 'm' }, { line = 'gunshot_c2', sex = 'f' }, { line = 'gunshot_c3', sex = 'm' } },
            dispatcher = 'gunshot_d',
            bystander = { offset = vector3(7.0, -4.0, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },

        -- ─── Stabbing ───────────────────────────────────────────────────────
        stabbing = {
            enabled = true, weight = 9, priority = 1, code = '10-52', type = 'stab', title = 'calls.t_stabbing', snap = 'ped', reward = 1.15,
            onlookers = { 1, 2 },                 -- passers-by filming (overrides scene.onlookers.count)
            locations = {
                vector4(128.0, -1298.0, 29.2, 210.0),     -- outside the Vanilla Unicorn
                vector4(-1388.0, -586.0, 30.2, 30.0),     -- Bahama Mamas, Del Perro
                vector4(-565.0, 275.0, 83.0, 175.0),      -- Tequi-la-la, West Vinewood
                vector4(360.0, 280.0, 103.0, 250.0),      -- Downtown Vinewood
                vector4(-1640.0, -1060.0, 13.1, 50.0),    -- Del Perro Pier
                vector4(1985.0, 3050.0, 47.2, 240.0),     -- Yellow Jack Inn
                vector4(-2190.0, 4290.0, 49.2, 60.0),     -- Hookies, North Chumash
                vector4(-708.0, -880.0, 23.8, 90.0),      -- Little Seoul
                vector4(390.0, -1080.0, 29.4, 180.0),     -- Mission Row
                vector4(-300.0, 6260.0, 31.5, 45.0),      -- Paleto Bay
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'civ_m', f = 'civ_f' }, female = 0.3, age = { 18, 50 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { wounded = 0.7, alive = 0.3 }, pose = 'sit', loss = { 0.08, 0.24 }, damagePacks = { 'TD_KNIFE_FRONT', 'TD_KNIFE_FRONT_VA' },
                  injuries = {
                      { type = 'stab', regions = { 'abdomen', 'chest', 'back', 'l_upper_leg', 'r_upper_leg' }, sev = { 2, 4 }, chance = 1.0, count = { 1, 2 } },
                      { type = 'laceration', regions = { 'l_lower_arm', 'r_lower_arm', 'face' }, sev = { 1, 3 }, chance = 0.7 },
                  },
                },
            },
            props = {
                { models = { 'prop_amb_beer_bottle', 'prop_ld_flow_bottle' }, offset = vector3(0.9, 0.6, 0.0), chance = 0.6 },
                { models = { 'prop_cs_wallet', 'prop_ld_wallet_01' }, offset = vector3(-0.8, 1.2, 0.0), chance = 0.4 },
            },
            callers = { { line = 'stabbing_c1', sex = 'f' }, { line = 'stabbing_c2', sex = 'm' }, { line = 'stabbing_c3', sex = 'f' } },
            dispatcher = 'stabbing_d',
            bystander = { offset = vector3(2.4, 2.2, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },

        -- ─── Drowning ───────────────────────────────────────────────────────
        drowning = {
            enabled = true, weight = 7, priority = 1, code = '10-52', type = 'drowning', title = 'calls.t_drowning', snap = 'ped', reward = 1.15,
            onlookers = { 1, 3 },                 -- passers-by filming (overrides scene.onlookers.count)
            wet = true,                           -- victims are soaked
            locations = {
                vector4(-1435.0, -1480.0, 2.4, 230.0),    -- Vespucci Beach
                vector4(-1520.0, -1190.0, 2.0, 250.0),    -- Vespucci Beach, north
                vector4(-1820.0, -860.0, 2.0, 230.0),     -- Del Perro Beach
                vector4(-3240.0, 1000.0, 2.5, 260.0),     -- Chumash beach
                vector4(-210.0, 6680.0, 1.2, 315.0),      -- Paleto Cove
                vector4(1520.0, 3860.0, 30.5, 45.0),      -- Alamo Sea, Sandy Shores
                vector4(1084.0, -670.0, 56.6, 180.0),     -- Mirror Park lake
                vector4(-807.0, 175.0, 72.0, 110.0),      -- Rockford Hills pool
                vector4(11.0, 525.0, 170.6, 120.0),       -- Vinewood Hills pool
                vector4(-1470.0, 180.0, 54.8, 90.0),      -- Richman mansion pool
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'beach_m', f = 'beach_f' }, female = 0.45, age = { 8, 70 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { wounded = 0.75, arrest = 0.25 }, pose = 'unconscious', loss = { 0.0, 0.02 },
                  conditions = {
                      hypoxia     = { cause = 'drowning', water = { 250, 900 } },
                      hypothermia = { temp = { 33.5, 35.2 }, chance = 0.5 },
                      arrest      = { rhythm = 'asystole', onlyIfState = 'arrest' },
                  },
                  injuries = { { type = 'contusion', regions = { 'head' }, sev = { 1, 2 }, chance = 0.3 } },
                },
            },
            props = {
                { models = { 'prop_beach_towel_01', 'prop_beach_towel_02', 'prop_beach_towel_03' }, offset = vector3(1.6, -0.6, 0.0), chance = 0.8 },
                { models = { 'prop_beach_lilo_01', 'prop_beach_ring_01' }, offset = vector3(-1.8, 1.2, 0.0), chance = 0.6 },
                { models = { 'prop_beach_bag_01a', 'prop_beachbag_01' }, offset = vector3(2.0, 0.6, 0.0), chance = 0.5 },
            },
            callers = { { line = 'drowning_c1', sex = 'f' }, { line = 'drowning_c2', sex = 'm' }, { line = 'drowning_c3', sex = 'm' } },
            dispatcher = 'drowning_d',
            bystander = { pool = 'beach_m', poolF = 'beach_f', offset = vector3(1.0, 1.1, 0.0), role = 'cpr', onlyIfState = 'arrest', scenario = 'CODE_HUMAN_MEDIC_KNEEL' },
        },

        -- ─── Burns (BBQ / house / vehicle fire) ─────────────────────────────
        burn = {
            enabled = true, weight = 8, priority = 1, code = '10-52', type = 'burn', title = 'calls.t_burn', snap = 'ped', reward = 1.15,
            locations = {
                vector4(115.0, -1960.0, 20.7, 30.0),      -- Grove Street yard
                vector4(1260.0, -570.0, 69.0, 90.0),      -- Mirror Park houses
                vector4(1910.0, 3820.0, 32.4, 120.0),     -- Sandy Shores trailer
                vector4(-360.0, 6230.0, 31.5, 45.0),      -- Paleto Bay houses
                vector4(1290.0, -1610.0, 54.2, 30.0),     -- El Burro Heights
                vector4(-50.0, -1570.0, 29.6, 140.0),     -- Chamberlain Hills
                vector4(600.0, 2770.0, 42.0, 0.0),        -- Harmony
                vector4(1660.0, 4840.0, 42.0, 280.0),     -- Grapeseed
                vector4(40.0, 3680.0, 39.7, 200.0),       -- Stab City
                vector4(-1260.0, -1520.0, 4.3, 120.0),    -- Vespucci Beach BBQ area
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'civ_m', f = 'civ_f' }, female = 0.35, age = { 18, 70 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { wounded = 0.65, alive = 0.35 }, pose = 'sit', loss = { 0.0, 0.05 }, damagePacks = { 'Burnt_Ped_0', 'Burnt_Ped_Left_Arm', 'Burnt_Ped_Right_Arm' },
                  conditions = {
                      hypoxia = { cause = 'smoke', chance = 0.7 },
                      airway  = { kind = 'swelling', chance = 0.35 },
                  },
                  injuries = {
                      { type = 'burn', regions = { 'l_lower_arm', 'r_lower_arm', 'l_upper_arm', 'r_upper_arm' }, sev = { 2, 4 }, chance = 1.0, count = { 1, 2 } },
                      { type = 'burn', regions = { 'face', 'chest', 'neck' }, sev = { 1, 3 }, chance = 0.6 },
                      { type = 'burn', regions = { 'l_lower_leg', 'r_lower_leg' }, sev = { 1, 3 }, chance = 0.35 },
                  },
                },
            },
            props = {
                { models = { 'prop_bbq_1', 'prop_bbq_5' }, offset = vector3(1.8, 1.6, 0.0), chance = 0.85, fx = 'groundFire' },
                { models = { 'prop_gascyl_01a' }, offset = vector3(2.6, 1.0, 0.0), chance = 0.6 },
                { models = { 'prop_fire_exting_1a' }, offset = vector3(-1.0, 1.4, 0.0), chance = 0.5 },
            },
            fx = { { kind = 'groundSmoke', offset = vector3(2.0, 2.4, 0.0), chance = 0.9 } },
            callers = { { line = 'burn_c1', sex = 'm' }, { line = 'burn_c2', sex = 'f' }, { line = 'burn_c3', sex = 'm' } },
            dispatcher = 'burn_d',
            bystander = { offset = vector3(-2.2, 2.6, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },

        -- ─── Cardiac arrest (collapsed jogger) ──────────────────────────────
        cardiac = {
            enabled = true, weight = 8, priority = 1, code = '10-52', type = 'arrest', title = 'calls.t_cardiac', snap = 'ped', reward = 1.3,
            onlookers = { 1, 2 },                 -- passers-by filming (overrides scene.onlookers.count)
            locations = {
                vector4(-1340.0, -1560.0, 4.3, 30.0),     -- Vespucci beach path
                vector4(-1610.0, -980.0, 13.0, 140.0),    -- Del Perro boardwalk
                vector4(1140.0, -640.0, 56.7, 0.0),       -- Mirror Park
                vector4(165.0, -960.0, 30.1, 250.0),      -- Legion Square
                vector4(-1330.0, 40.0, 53.5, 90.0),       -- Los Santos Golf Club
                vector4(-430.0, 1110.0, 326.0, 340.0),    -- Galileo Observatory
                vector4(-1700.0, -1110.0, 13.2, 50.0),    -- Del Perro Pier
                vector4(-590.0, -130.0, 39.0, 120.0),     -- Burton
                vector4(1830.0, 3690.0, 34.2, 210.0),     -- Sandy Shores
                vector4(-130.0, 6420.0, 31.4, 45.0),      -- Paleto Bay
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'sport_m', f = 'sport_f' }, female = 0.3, age = { 38, 74 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { arrest = 1 }, pose = 'arrest', loss = { 0.0, 0.0 },
                  conditions = { arrest = { rhythm = 'vf' } },
                  injuries = { { type = 'abrasion', regions = { 'face', 'l_lower_arm', 'r_lower_arm' }, sev = { 1, 1 }, chance = 0.6 } },
                },
            },
            props = {
                { models = { 'prop_ld_flow_bottle', 'prop_energy_drink' }, offset = vector3(0.8, -0.6, 0.0), chance = 0.6 },
            },
            callers = { { line = 'cardiac_c1', sex = 'm' }, { line = 'cardiac_c2', sex = 'f' }, { line = 'cardiac_c3', sex = 'm' } },
            dispatcher = 'cardiac_d',
            bystander = { offset = vector3(0.75, 0.15, 0.0), role = 'cpr', heading = 90.0 },
        },

        -- ─── Elderly fall ───────────────────────────────────────────────────
        elderly = {
            enabled = true, weight = 8, priority = 3, code = '10-52', type = 'fall', title = 'calls.t_elderly', snap = 'ped', reward = 0.9,
            onlookers = { 0, 1 },                 -- passers-by filming (overrides scene.onlookers.count)
            locations = {
                vector4(-710.0, -180.0, 37.3, 120.0),     -- Rockford Hills
                vector4(-1530.0, 420.0, 109.0, 30.0),     -- Richman
                vector4(-120.0, 420.0, 113.0, 160.0),     -- Vinewood Hills
                vector4(1220.0, -640.0, 63.5, 280.0),     -- Mirror Park
                vector4(1760.0, 3730.0, 34.0, 120.0),     -- Sandy Shores
                vector4(-240.0, 6170.0, 31.4, 45.0),      -- Paleto Bay
                vector4(1680.0, 4880.0, 42.0, 190.0),     -- Grapeseed
                vector4(-3170.0, 1070.0, 20.8, 250.0),    -- Chumash
                vector4(-1360.0, -650.0, 26.8, 120.0),    -- Del Perro
                vector4(-760.0, -920.0, 18.9, 0.0),       -- Little Seoul
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'old_m', f = 'old_f' }, female = 0.6, age = { 72, 94 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { alive = 0.65, wounded = 0.35 }, pose = 'sit', loss = { 0.0, 0.06 },
                  conditions = { hypothermia = { temp = { 35.0, 35.8 }, chance = 0.2 }, concussion = { grade = { 1, 1 }, chance = 0.2 } },
                  injuries = {
                      { type = 'fracture', regions = { 'l_upper_leg', 'r_upper_leg' }, sev = { 2, 3 }, chance = 0.9, fracture = { bone = 'femur', displaced = true } },
                      { type = 'fracture', regions = { 'l_lower_arm', 'r_lower_arm' }, sev = { 1, 2 }, chance = 0.35 },
                      { type = 'laceration', regions = { 'head', 'face' }, sev = { 1, 2 }, chance = 0.4 },
                      { type = 'contusion', regions = { 'pelvis' }, sev = { 1, 2 }, chance = 0.5 },
                  },
                },
            },
            props = {
                { models = { 'prop_cs_walking_stick' }, offset = vector3(0.7, 0.5, 0.0), rot = vector3(90.0, 0.0, 40.0), chance = 0.7 },
                { models = { 'prop_cs_shopping_bag', 'prop_paper_bag_small' }, offset = vector3(-0.9, 0.6, 0.0), chance = 0.6 },
            },
            callers = { { line = 'elderly_c1', sex = 'f' }, { line = 'elderly_c2', sex = 'm' }, { line = 'elderly_c3', sex = 'f' } },
            dispatcher = 'elderly_d',
            bystander = { offset = vector3(1.4, 1.4, 0.0), scenario = 'CODE_HUMAN_MEDIC_KNEEL' },
        },

        -- ─── Assault ────────────────────────────────────────────────────────
        assault = {
            enabled = true, weight = 9, priority = 2, code = '10-52', type = 'assault', title = 'calls.t_assault', snap = 'ped', reward = 1.0,
            locations = {
                vector4(100.0, -1300.0, 29.3, 30.0),      -- Strawberry, near the Unicorn
                vector4(220.0, -1560.0, 29.3, 140.0),     -- Davis
                vector4(-1300.0, -1170.0, 4.5, 90.0),     -- Vespucci
                vector4(-660.0, -1010.0, 19.8, 0.0),      -- Little Seoul
                vector4(370.0, -950.0, 29.3, 270.0),      -- Mission Row
                vector4(260.0, 230.0, 105.0, 70.0),       -- Vinewood
                vector4(150.0, -1750.0, 29.2, 50.0),      -- Davis Ave
                vector4(1950.0, 3770.0, 32.2, 300.0),     -- Sandy Shores
                vector4(-220.0, 6290.0, 31.5, 225.0),     -- Paleto Bay
                vector4(930.0, -1820.0, 31.0, 170.0),     -- Cypress Flats
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'civ_m', f = 'civ_f' }, female = 0.35, age = { 17, 60 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { alive = 0.55, wounded = 0.45 }, pose = 'sit', loss = { 0.02, 0.1 }, damagePacks = { 'Skin_Melee_0', 'SCR_Torture' },
                  conditions = { concussion = { grade = { 1, 3 }, chance = 0.8 } },
                  injuries = {
                      { type = 'contusion', regions = { 'head', 'face', 'chest', 'abdomen' }, sev = { 1, 3 }, chance = 1.0, count = { 1, 3 } },
                      { type = 'laceration', regions = { 'face', 'head' }, sev = { 1, 3 }, chance = 0.7 },
                      { type = 'fracture', regions = { 'face', 'chest', 'l_lower_arm', 'r_lower_arm' }, sev = { 1, 2 }, chance = 0.4 },
                  },
                },
            },
            props = {
                { models = { 'prop_amb_beer_bottle', 'prop_cs_beer_bot_01' }, offset = vector3(0.8, 0.9, 0.0), chance = 0.6 },
                { models = { 'prop_amb_phone', 'prop_cs_phone_01' }, offset = vector3(-1.2, 0.5, 0.0), chance = 0.5 },
            },
            callers = { { line = 'assault_c1', sex = 'm' }, { line = 'assault_c2', sex = 'f' }, { line = 'assault_c3', sex = 'm' } },
            dispatcher = 'assault_d',
            bystander = { offset = vector3(2.8, 1.8, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },

        -- ─── Industrial crush ───────────────────────────────────────────────
        crush = {
            enabled = true, weight = 6, priority = 1, code = '10-52', type = 'crush', title = 'calls.t_crush', snap = 'ped', reward = 1.25,
            locations = {
                vector4(1000.0, -3060.0, 5.9, 90.0),      -- Port of Los Santos
                vector4(1240.0, -2970.0, 9.3, 0.0),       -- Terminal
                vector4(-117.6, -2414.5, 6.0, 0.0),       -- Elysian Island
                vector4(850.0, -2250.0, 30.5, 90.0),      -- Cypress Flats warehouses
                vector4(880.0, -1250.0, 26.0, 0.0),       -- La Mesa industrial
                vector4(1520.0, -2140.0, 77.0, 0.0),      -- Murrieta oil fields
                vector4(-560.0, 5290.0, 70.2, 70.0),      -- Paleto sawmill
                vector4(2950.0, 2760.0, 42.0, 300.0),     -- Davis Quartz
                vector4(1730.0, 3300.0, 41.2, 195.0),     -- Sandy Shores airfield
                vector4(2700.0, 1520.0, 24.5, 270.0),     -- Palmer-Taylor power station
            },
            vehicles = {
                { models = { 'forklift' }, offset = vector3(0.4, 2.6, 0.0), heading = 180.0, damage = {}, windows = {}, doors = {}, tyres = 0.0, smoke = 0.0, fire = 0.0 },
            },
            victims = {
                { count = { 1, 1 }, peds = { m = 'work_m', f = 'civ_f' }, female = 0.05, age = { 20, 62 }, offset = vector3(0.0, 0.0, 0.0),
                  state = { wounded = 1 }, pose = 'writhe', trapped = 0.6, loss = { 0.1, 0.25 }, damagePacks = { 'BigRunOverByVehicle', 'Car_Crash_Heavy' },
                  injuries = {
                      { type = 'fracture', regions = { 'pelvis' }, sev = { 2, 4 }, chance = 0.7 },
                      { type = 'fracture', regions = { 'l_lower_leg', 'r_lower_leg', 'l_upper_leg', 'r_upper_leg' }, sev = { 2, 4 }, chance = 0.8, count = { 1, 2 } },
                      { type = 'internal', regions = { 'abdomen', 'pelvis' }, sev = { 2, 4 }, chance = 0.6 },
                      { type = 'contusion', regions = { 'chest', 'abdomen' }, sev = { 2, 3 }, chance = 0.6 },
                  },
                },
            },
            props = {
                { models = { 'prop_pallet_02a' }, offset = vector3(0.0, 0.5, 0.0), chance = 0.9 },
                { models = { 'prop_boxpile_06b', 'prop_boxpile_07d' }, offset = vector3(0.8, 0.9, 0.0), rot = vector3(0.0, 15.0, 20.0), chance = 0.85 },
                { models = { 'prop_cementbags01', 'prop_barrel_02a' }, offset = vector3(-1.6, 1.2, 0.0), chance = 0.6 },
            },
            callers = { { line = 'crush_c1', sex = 'm' }, { line = 'crush_c2', sex = 'm' }, { line = 'crush_c3', sex = 'f' } },
            dispatcher = 'crush_d',
            bystander = { pool = 'work_m', offset = vector3(2.6, -1.2, 0.0), scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- AI MEDIC (answers downed players while no medic is on duty)
-- ═══════════════════════════════════════════════════════════════════════════

Config.AIMedic = {
    enabled        = true,
    onlyNoMedics   = true,              -- only while no medic is on duty
    maxActive      = 4,                 -- AI units on the road at the same time
    cooldown       = 120,               -- seconds before the same patient can get another AI unit
    states         = { wounded = true, arrest = true },   -- patient states the AI answers

    vehicle        = 'ambulance',       -- native model
    livery         = nil,               -- livery index (nil = default)
    crew           = { 's_m_m_paramedic_01', 's_m_m_paramedic_01' },  -- driver + partner (1 or 2 entries)
    plate          = 'EMS 911',         -- plate text (max 8)

    spawnDistance  = { 150.0, 300.0 },  -- the unit starts on a road this far away
    speed          = 28.0,              -- m/s while responding (≈ 100 km/h)
    drivingStyle   = 787004,            -- GTA driving flags (rushed, avoids traffic, ignores lights)
    stopRange      = 14.0,              -- metres from the patient where it parks
    siren          = true,
    etaUpdate      = 4,                 -- seconds between ETA updates on the patient's HUD

    stuckTime      = 10,                -- seconds without progress before it tries to unstuck (reverse)
    stuckTeleport  = 22,                -- seconds stuck before it fades and moves closer
    driveTimeout   = 120,               -- seconds of driving before it is moved next to the patient anyway
    walkTimeout    = 25,                -- seconds the crew may need to walk to the patient

    treatTime      = 14,                -- seconds the crew treats on scene
    cprAnim        = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' },
    treatAnim      = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
    kneelAnim      = { dict = 'amb@medic@standing@kneel@base', clip = 'base' },

    transport      = 'drive',           -- 'drive' = the patient rides along to the hospital | 'teleport' = fade straight to the bed
    transportTimeout = 150,             -- seconds of driving to the hospital before it fades there
    hospitalRadius = 60.0,              -- metres from the hospital that count as arrived

    revive         = 'full',            -- 'full' = healed in the bed | 'stabilize' = bleeding stopped, back on their feet, injuries stay
    price          = 1500,              -- bill (insurance applies through the billing module)
    billReason     = 'calls.ai_bill',   -- locale key of the bill reason
    closeCall      = true,              -- close the patient's dispatch call when the AI is done
    cancelOnMedic  = true,              -- a real medic responding to the call sends the AI unit away (while it is still driving)
    maxTime        = 480,               -- seconds after which the job completes anyway (fade to the hospital)

    -- Used when no hospital bed was built (or all are taken): Pillbox, Mount Zonah, Sandy Shores, Paleto
    hospitals = {
        vector4(298.6, -584.5, 43.3, 70.0),
        vector4(-449.5, -340.6, 34.5, 80.0),
        vector4(1839.4, 3672.9, 34.3, 210.0),
        vector4(-247.8, 6331.5, 32.4, 225.0),
    },
}
