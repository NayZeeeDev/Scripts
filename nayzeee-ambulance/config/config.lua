--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
 █████╗ ███╗   ███╗██████╗ ██╗   ██╗██╗      █████╗ ███╗   ██╗ ██████╗███████╗
██╔══██╗████╗ ████║██╔══██╗██║   ██║██║     ██╔══██╗████╗  ██║██╔════╝██╔════╝
███████║██╔████╔██║██████╔╝██║   ██║██║     ███████║██╔██╗ ██║██║     █████╗
██╔══██║██║╚██╔╝██║██╔══██╗██║   ██║██║     ██╔══██║██║╚██╗██║██║     ██╔══╝
██║  ██║██║ ╚═╝ ██║██████╔╝╚██████╔╝███████╗██║  ██║██║ ╚████║╚██████╗███████╗
╚═╝  ╚═╝╚═╝     ╚═╝╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝

    AMBULANCE SYSTEM - 1.0.0
    Discord: discord.gg/nayzeeedev

    This file holds the core settings. Every feature has its own file in
    config/modules/ (dispatch.lua, pharmacy.lua, suture.lua, ...).
    Items are in config/items.lua, prop models in config/props.lua.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- GENERAL
-- ═══════════════════════════════════════════════════════════════════════════

Config.Debug     = false
Config.Locale    = 'en'
Config.Framework = 'auto'      -- 'auto' | 'esx' | 'qbcore' | 'qbox' | 'ox' (ox_core) | 'standalone'

-- ═══════════════════════════════════════════════════════════════════════════
-- JOBS
-- ═══════════════════════════════════════════════════════════════════════════

Config.Jobs = {
    medic  = { 'ambulance', 'ems' },          -- framework jobs that count as medics
    police = { 'police', 'sheriff', 'state' }, -- get Config.PolicePerms (first aid, CPR)
    requireDuty = true,                         -- medics must be on duty to use medic actions
}

-- Everyone (no job) may use these perms. 'basic' lets players bandage
-- themselves and others with their own items.
Config.PublicPerms = { 'basic' }
Config.PolicePerms = { 'basic', 'cpr', 'assess' }

-- Used until departments are built in game (/nzadmin → Hospitals → Departments).
-- Framework job grade → permissions. Grades not listed use the highest lower grade.
Config.DefaultPerms = {
    [0] = { 'assess', 'basic', 'cpr', 'transport', 'checkin' },
    [1] = { 'assess', 'basic', 'cpr', 'transport', 'checkin', 'defib', 'iv', 'splint', 'binder', 'suture', 'burn', 'meds', 'airway', 'bodybag', 'blood' },
    [2] = { 'assess', 'basic', 'cpr', 'transport', 'checkin', 'defib', 'iv', 'splint', 'binder', 'suture', 'burn', 'meds', 'airway', 'bodybag', 'blood',
            'ultrasound', 'chestdrain', 'pericardio', 'xray', 'pharmacy' },
    [3] = { 'assess', 'basic', 'cpr', 'transport', 'checkin', 'defib', 'iv', 'splint', 'binder', 'suture', 'burn', 'meds', 'airway', 'bodybag', 'blood',
            'ultrasound', 'chestdrain', 'pericardio', 'xray', 'pharmacy', 'surgery', 'angio', 'graft' },
    [4] = { 'assess', 'basic', 'cpr', 'transport', 'checkin', 'defib', 'iv', 'splint', 'binder', 'suture', 'burn', 'meds', 'airway', 'bodybag', 'blood',
            'ultrasound', 'chestdrain', 'pericardio', 'xray', 'pharmacy', 'surgery', 'angio', 'graft', 'manage' },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ADMIN
-- ═══════════════════════════════════════════════════════════════════════════

Config.Admin = {
    ace    = 'nza.admin',                     -- add_ace group.admin nza.admin allow
    groups = { 'admin', 'god', 'superadmin' }, -- framework admin groups that also count
}

Config.Commands = {
    admin   = 'nzadmin',   -- hospital builder & department manager (admins)
    revive  = 'revive',    -- /revive [id]
    heal    = 'heal',      -- /heal [id]   (removes injuries, keeps you standing)
    injure  = 'injure',    -- /injure [id] [region] [type] [severity]  (testing)
    kill    = false,       -- set a name to enable /kill [id]
    interact = 'nzainteract', -- opens the patient interaction menu (keybind 'nza_interact' is unbound by default)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════════════════════════════════

Config.UI = {
    font      = 'Lexend',  -- 'Lexend' (UI v5 windows) or 'Inter' (HUD design)
    shape     = 'cut',     -- window silhouette: cut twin mirror bevel crest flip step blade notch round
    scale     = 1.0,       -- 0.8 - 1.2
    sounds    = true,      -- monitor beeps, defib, pager
    signature = true,      -- small NAYZEEE signature on windows
}

-- ═══════════════════════════════════════════════════════════════════════════
-- DAMAGE → INJURIES
-- ═══════════════════════════════════════════════════════════════════════════

Config.Damage = {
    enabled = true,

    -- Weapon groups → injury type. Severity comes from the damage dealt.
    groups = {
        GROUP_UNARMED    = { 'contusion' },
        GROUP_MELEE      = { 'contusion', 'fracture' },  -- bats, crowbars... (blades are below)
        GROUP_PISTOL     = { 'gunshot' },
        GROUP_SMG        = { 'gunshot' },
        GROUP_RIFLE      = { 'gunshot' },
        GROUP_MG         = { 'gunshot' },
        GROUP_SHOTGUN    = { 'gunshot', 'shrapnel' },
        GROUP_SNIPER     = { 'gunshot' },
        GROUP_HEAVY      = { 'shrapnel', 'burn' },
        GROUP_THROWN     = { 'shrapnel', 'burn' },
        GROUP_PETROLCAN  = { 'burn' },
    },

    -- Single weapons that need a different injury than their group
    weapons = {
        WEAPON_KNIFE = { 'stab', 'laceration' },   WEAPON_DAGGER = { 'stab' },
        WEAPON_SWITCHBLADE = { 'stab' },           WEAPON_MACHETE = { 'laceration' },
        WEAPON_HATCHET = { 'laceration' },         WEAPON_BATTLEAXE = { 'laceration' },
        WEAPON_STONE_HATCHET = { 'laceration' },   WEAPON_BOTTLE = { 'laceration' },
        WEAPON_FALL = { 'fracture', 'contusion' },
        WEAPON_RUN_OVER_BY_CAR = { 'fracture', 'internal', 'abrasion' },
        WEAPON_RAMMED_BY_CAR = { 'contusion', 'internal', 'fracture' },
        WEAPON_FIRE = { 'burn' },                  WEAPON_MOLOTOV = { 'burn' },
        WEAPON_EXPLOSION = { 'shrapnel', 'burn', 'contusion' },
        WEAPON_ANIMAL = { 'laceration' },          WEAPON_COUGAR = { 'laceration' },
        WEAPON_BARBED_WIRE = { 'laceration' },     WEAPON_ELECTRIC_FENCE = { 'burn' },
        WEAPON_STUNGUN = false,                    WEAPON_STUNGUN_MP = false,   -- false = no injury
        WEAPON_DROWNING = 'hypoxia',               WEAPON_DROWNING_IN_VEHICLE = 'hypoxia',
    },

    headshotArrest   = 0.35,  -- chance a severe head/neck gunshot causes instant cardiac arrest
    minDamage        = 4,     -- GTA damage below this makes no injury (scratches)
    severityByDamage = { 15, 35, 60 },  -- GTA damage thresholds for severity 2, 3, 4
    fall = { minHeight = 4.0, fractureHeight = 7.0 },
    vehicle = {
        enabled = true,
        minSpeedDrop = 45.0,     -- km/h lost in one tick that counts as a crash
        seatbeltExport = nil,    -- e.g. { resource = 'jim-mechanic', fn = 'seatbeltOn' } ; nil = auto-detect common ones
        seatbeltFactor = 0.35,   -- injuries scaled by this when buckled
    },
    drowning = { enabled = true },
    fire = { enabled = true, tick = 2000 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PHYSIOLOGY (blood, vitals, state changes)
-- ═══════════════════════════════════════════════════════════════════════════

Config.Physiology = {
    tick          = 1000,     -- ms between physiology updates
    timeScale     = 1.0,      -- >1 makes everything bleed faster
    bloodMax      = { m = 5000, f = 4500 },
    deathLoss     = 0.50,     -- fraction of blood lost at which the patient dies
    arrestLoss    = 0.45,     -- fraction lost that triggers cardiac arrest
    arrestMap     = 40,       -- MAP (mmHg) below this for arrestDelay seconds → arrest
    arrestDelay   = 20,
    hypoxiaArrest = 60,       -- SpO2 below this for arrestDelay seconds → arrest
    fluidDecay    = 0.01,     -- saline leaves circulation at 1%/min
    healRate      = 0.4,      -- heal points per minute for treated injuries (×4 in a hospital bed)
    examDistance  = 4.0,      -- metres a medic can be from the patient for live data
    watchRate     = 1000,     -- ms between monitor updates to watching medics
    syncHealth    = true,     -- keep the GTA health bar matched to blood volume
    infection     = true,     -- dirty, uncovered wounds can get infected (fever, sepsis) - antibiotics cure it
    hypothermia   = true,     -- body temperature (blood loss, water, cold fluids) - foil blanket / bed warm up
}

-- ═══════════════════════════════════════════════════════════════════════════
-- WOUNDED STAGE (downed: crawl, bleed-out clock, call EMS)
-- ═══════════════════════════════════════════════════════════════════════════

Config.Wounded = {
    enabled      = true,
    lossDown     = 0.30,    -- blood loss fraction that knocks a player down
    maxClock     = 300,     -- the bleed-out clock never shows more than this (seconds). It runs in real time for
                            -- heavy bleeding, slower for a minor ooze, and pauses when the patient is stabilized
    minClock     = 60,      -- ...and starts at least at this
    stableBleed  = 1.0,     -- total bleed (mL/min) under this = STABILIZED, clock paused
    controlledBleed = 5.0,  -- ...and under this when every bleeding wound is under control (bandaged, packed,
                            -- tourniquet, treated) and no haemothorax is still filling
    noBleedClock = 600,     -- downed without bleeding (e.g. fractures): seconds before you can only give up
    crawl        = true,
    crawlSpeed   = 1.0,
    giveUp       = { enabled = true, hold = 3, minTime = 60 },  -- hold time; only after minTime seconds down
                                                                -- (the key is Config.WoundedUI.keys.giveUp in config/modules/wounded.lua)
    callEms      = { key = 'G', cooldown = 60 },
    invincible   = true,    -- extra damage while downed doesn't re-kill, it adds injuries instead
    disableControls = { 24, 25, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264 }, -- attack, aim, weapon wheel, cover, reload, melee
}

-- ═══════════════════════════════════════════════════════════════════════════
-- DEATH & RESPAWN
-- ═══════════════════════════════════════════════════════════════════════════

Config.Death = {
    arrestToDeath = 300,      -- seconds of cardiac arrest without ROSC before death (CPR pauses this)
    respawnTimer  = 300,      -- seconds dead before you may respawn at a hospital
    respawnHold   = 3,        -- hold for this long to respawn (key: Config.WoundedUI.keys.respawn)
    respawnFee    = 500,      -- charged on respawn (insurance applies)
    loseItems     = false,    -- clear inventory on respawn
    keepItems     = { 'id_card', 'driver_license', 'phone' },
    loseCash      = false,
    clearInjuries = true,     -- respawning heals everything
    bleedOutDeath = true,     -- clock reaching 0 while still bleeding = death (false = arrest only)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- EASY MODE (minigames become progress bars) - per department in game;
-- this is the default for new departments and for medics without one.
-- ═══════════════════════════════════════════════════════════════════════════

Config.EasyMode = {
    default = false,
    score   = 78,        -- the score an easy-mode procedure counts as
    style   = 'bar',     -- 'bar' or 'circle' (ox_lib progress)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PERSISTENCE (injuries and death survive relog & restart)
-- ═══════════════════════════════════════════════════════════════════════════

Config.Persistence = {
    enabled      = true,
    saveInterval = 30,       -- seconds between saves of changed patients
    offlineHeal  = false,    -- heal treated injuries while offline
}

-- ═══════════════════════════════════════════════════════════════════════════
-- BILLING DEFAULTS (prices per treatment are in each module's config)
-- ═══════════════════════════════════════════════════════════════════════════
-- enabled / society / account / medicCut are used by NZA.Billing.Charge (every treatment,
-- transport and respawn fee). Insurance share, unpaid bills, external invoice scripts
-- (okokBilling, esx_billing, ...) and auto collect: Config.Pharmacy.billing
-- (config/modules/pharmacy.lua).

Config.Billing = {
    enabled = true,
    society = 'ambulance',   -- society account that receives payments
    account = 'bank',        -- 'bank' | 'cash'
    medicCut = 0.25,         -- share of each treatment bill paid to the medic who did it
}
