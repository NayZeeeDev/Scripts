--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    ██████╗ ███████╗██╗   ██╗███████╗██╗      ██████╗ ██████╗ ███╗   ███╗███████╗███╗   ██╗████████╗
    ██╔══██╗██╔════╝██║   ██║██╔════╝██║     ██╔═══██╗██╔══██╗████╗ ████║██╔════╝████╗  ██║╚══██╔══╝
    ██║  ██║█████╗  ██║   ██║█████╗  ██║     ██║   ██║██████╔╝██╔████╔██║█████╗  ██╔██╗ ██║   ██║
    ██║  ██║██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║     ██║   ██║██╔═══╝ ██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║
    ██████╔╝███████╗ ╚████╔╝ ███████╗███████╗╚██████╔╝██║     ██║ ╚═╝ ██║███████╗██║ ╚████║   ██║
    ╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝

    CUT UP SCRIPT - 1.0.0
    No Hesi style highway cut-up: dense traffic, near-miss scoring, crews, ghosting,
    leaderboards, cockpit FOV and full race wheel support.
    Discord: discord.gg/nayzeeedev

]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Debug        = false        -- Prints extra info to the F8 / server console
Config.Locale       = 'en'         -- File in /locales (en ships by default)
Config.ServerName   = 'NZ|cutup'   -- Shown in the leaderboard "Server Played On" column
Config.Storage      = 'auto'       -- 'auto' (oxmysql if started, else data/db.json) | 'mysql' | 'json'
Config.AutoEnable   = false        -- true = every driver is in CUT UP mode on spawn (no F6 needed)
Config.DisablePolice = true        -- No wanted level while in CUT UP mode
Config.AdminAce     = 'cutup.admin' -- Ace for /cutupadmin (add_ace group.admin cutup.admin allow)

-- These also work outside CUT UP mode, in any car the player drives
Config.Everywhere = {
    Camera       = false,       -- Custom cameras / cockpit FOV
    Wheel        = true,        -- Race wheel input
    Transmission = true,        -- Sequential / H-pattern gearbox
}

-- ██╗███╗   ██╗████████╗███████╗██████╗ ███████╗ █████╗  ██████╗███████╗
-- ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝
-- ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝█████╗  ███████║██║     █████╗
-- ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██╔══╝  ██╔══██║██║     ██╔══╝
-- ██║██║ ╚████║   ██║   ███████╗██║  ██║██║     ██║  ██║╚██████╗███████╗
-- ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚══════╝

-- Server defaults for the look of every menu and the HUD. With PlayerPrefs on, each player can
-- change their own colours, size and sounds from F5 > Interface.
-- Their choices are saved on their own PC and never touch the database.
Config.UI = {
    Accent        = '#a873ff',   -- Main colour (bars, highlights, score fill, flow state)
    Accent2       = '#ff6fb5',   -- Second colour the accent fades into (gradients, combo bar)
    Alert         = '#e5484d',   -- Danger colour (crashes, threat arrows, hearts)
    Scale         = 1.0,         -- 0.8 - 1.25
    ToastPosition = 'top-right', -- top-right | top-left | top-center | bottom-right | bottom-left
    Sounds        = true,
    Volume        = 0.7,         -- 0.0 - 1.0
    ReduceMotion  = false,       -- Turns off the scanlines, glows and popup animations

    PlayerPrefs     = true,      -- Let players pick their own colours / size / sounds
    SettingsCommand = 'cutupsettings', -- Opens the settings page. false to disable

    -- Swatches shown in the colour picker (players can still type any hex)
    Presets = { '#a873ff', '#ff6fb5', '#08afa2', '#3d9bff', '#e5a50a', '#46c08a', '#e5484d', '#f2f4f5' },
}

-- ██╗  ██╗███████╗██╗   ██╗███████╗
-- ██║ ██╔╝██╔════╝╚██╗ ██╔╝██╔════╝
-- █████╔╝ █████╗   ╚████╔╝ ███████╗
-- ██╔═██╗ ██╔══╝    ╚██╔╝  ╚════██║
-- ██║  ██╗███████╗   ██║   ███████║
-- ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝

-- Default keys. Players rebind all of these in Settings > Key Bindings > FiveM.
Config.Keys = {
    ToggleMode   = 'F6',          -- Enter / leave CUT UP mode           (/cutup)
    Menu         = 'F5',          -- Settings / wheel / crew menu        (/cutupmenu)
    Leaderboard  = 'F10',         --                                     (/leaderboard)
    Camera       = 'V',           -- Cycle camera (takes over the native V while in CUT UP)
    FovUp        = 'PAGEUP',
    FovDown      = 'PAGEDOWN',
    ShiftUp      = 'LSHIFT',      -- Sequential / H-pattern
    ShiftDown    = 'LCONTROL',
    Clutch       = 'X',           -- Hold for the H-pattern keyboard clutch
    Flash        = 'G',           -- Hold to flash your high beams at traffic
    ToggleHud    = 'F7',
}

--  ██████╗ █████╗ ███╗   ███╗███████╗██████╗  █████╗
-- ██╔════╝██╔══██╗████╗ ████║██╔════╝██╔══██╗██╔══██╗
-- ██║     ███████║██╔████╔██║█████╗  ██████╔╝███████║
-- ██║     ██╔══██║██║╚██╔╝██║██╔══╝  ██╔══██╗██╔══██║
-- ╚██████╗██║  ██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║
--  ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝

-- Every player can change these in F5 > Camera (saved on their own PC).
--   native      = GTA's own camera
--   cockpit     = in-car with your own FOV / seat position (gives the FPV bonus)
--   hood | bumper | chase_near | chase_far | cinematic
Config.Camera = {
    Default        = 'cockpit',
    CockpitFov     = 72.0,        -- 40 - 110
    HoodFov        = 70.0,
    ChaseFov       = 62.0,
    Pitch          = -4.0,        -- Cockpit default tilt (degrees)
    LookSpeed      = 6.0,         -- Mouse / stick free look
    SpeedFov       = true,        -- FOV opens up the faster you go
    SpeedFovAmount = 12.0,        -- Degrees added at top speed
    Shake          = true,        -- Road vibration + impact shake
    ChaseDistance  = 6.2,
    ChaseHeight    = 1.65,
    ChaseLag       = 0.18,        -- 0 = rigid, 0.5 = very floaty
    ChaseTilt      = 4.0,
    HideHead       = true,        -- Switch the ped to first person so the head doesn't clip the cockpit cam
}

-- ████████╗██████╗  █████╗ ███████╗███████╗██╗ ██████╗
-- ╚══██╔══╝██╔══██╗██╔══██╗██╔════╝██╔════╝██║██╔════╝
--    ██║   ██████╔╝███████║█████╗  █████╗  ██║██║
--    ██║   ██╔══██╗██╔══██║██╔══╝  ██╔══╝  ██║██║
--    ██║   ██║  ██║██║  ██║██║     ██║     ██║╚██████╗
--    ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚═╝ ╚═════╝

Config.Traffic = {
    AmbientDensity   = 1.0,       -- Native GTA traffic while in CUT UP (1.0 is the game's max)
    ParkedDensity    = 0.15,
    ExtraCars        = 26,        -- Traffic cars kept ahead of each CUT UP driver at density 1.0 (GTA's own cars count)
    MaxCars          = 40,        -- Hard cap, whatever the player's density slider says
    SpawnMin         = 140.0,     -- Spawn window ahead of the player (m)
    SpawnMax         = 320.0,
    DespawnBehind    = 180.0,
    DespawnRadius    = 420.0,
    SameDirection    = 0.85,      -- Chance a spawned car drives your way
    Networked        = true,      -- true = everyone sees the same traffic (needs OneSync)
    CruiseMin        = 22.0,      -- m/s (~80 km/h)
    CruiseMax        = 34.0,      -- m/s (~122 km/h)
    TruckChance      = 0.18,
    DriveStyle       = 786475,    -- Normal traffic that ignores lights (highway feel)

    -- Traffic changes lanes on its own (with blinkers) so lines open and close in front of you
    LaneChange = {
        Enabled      = true,
        Interval     = 1.2,       -- Seconds between rolls
        Chance       = 0.35,
        LaneWidth    = 3.6,
        Lookahead    = 32.0,
        Duration     = 3.2,
    },

    Models = {
        cars = {
            'asea','asterope','premier','primo','stanier','washington','tailgater','fugitive',
            'intruder','emperor','granger','baller','cavalcade2','serrano','rocoto','landstalker',
            'blista','issi2','prairie','felon','oracle','schafter2','sultan','buffalo','dilettante',
            'surge','minivan','speedo','burrito3','rumpo','bison','sadler','bobcatxl','youga',
        },
        trucks  = { 'mule','mule3','benson','pounder','biff','packer','boxville2','flatbed','tiptruck' },
        drivers = {
            'a_m_y_business_01','a_m_m_business_01','a_f_y_business_01','a_m_y_genstreet_01',
            'a_f_y_tourist_01','a_m_m_skater_01','a_m_y_hipster_01','a_f_m_bevhills_01',
            's_m_m_trucker_01','a_m_m_farmer_01',
        },
    },
}

--  █████╗ ██╗    ██╗ █████╗ ██████╗ ███████╗███╗   ██╗███████╗███████╗███████╗
-- ██╔══██╗██║    ██║██╔══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██╔════╝██╔════╝
-- ███████║██║ █╗ ██║███████║██████╔╝█████╗  ██╔██╗ ██║█████╗  ███████╗███████╗
-- ██╔══██║██║███╗██║██╔══██║██╔══██╗██╔══╝  ██║╚██╗██║██╔══╝  ╚════██║╚════██║
-- ██║  ██║╚███╔███╔╝██║  ██║██║  ██║███████╗██║ ╚████║███████╗███████║███████║
-- ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝

-- Traffic notices you. Drivers check their mirrors, react to your high beams, get spooked by near misses.
Config.Awareness = {
    Enabled          = true,
    NoticeDistance   = 45.0,      -- Metres behind an NPC where they can see you in the mirror
    ClosingSpeed     = 7.0,       -- m/s faster than them before they care
    ReactionMin      = 0.35,      -- Seconds
    ReactionMax      = 1.30,
    Personalities = {             -- Weights
        yielder  = 60,            -- Moves over for you
        stubborn = 25,            -- Holds the lane, might speed up
        nervous  = 15,            -- Brake taps, swerves, honks
    },
    FlashRange       = 85.0,      -- How far your high beams reach
    FlashCone        = 18.0,      -- Degrees either side
    FlashYieldChance = 0.85,
    HornChance       = 0.35,      -- After a near miss
    SwerveChance     = 0.18,
}

-- ██████╗  █████╗ ███╗   ███╗ █████╗  ██████╗ ███████╗
-- ██╔══██╗██╔══██╗████╗ ████║██╔══██╗██╔════╝ ██╔════╝
-- ██║  ██║███████║██╔████╔██║███████║██║  ███╗█████╗
-- ██║  ██║██╔══██║██║╚██╔╝██║██╔══██║██║   ██║██╔══╝
-- ██████╔╝██║  ██║██║ ╚═╝ ██║██║  ██║╚██████╔╝███████╗
-- ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝

Config.Damage = {
    Enabled            = true,
    CrashSpeedLoss     = 6.5,     -- m/s lost in one frame that counts as a crash (~23 km/h)
    ScrapeSpeedLoss    = 2.0,     -- Smaller hits = scrape (no heart lost, combo -25%)
    DeformationMult    = 1.6,     -- Handling fDeformationDamageMult (bigger = more crumple)
    ExtraDeform        = 260.0,   -- Extra visual deformation per unit of impact
    EngineDamage       = 55.0,    -- Engine health lost per unit of impact
    BodyDamage         = 70.0,
    TyreBurstChance    = 0.12,    -- Per heavy side impact
    WindowSmashChance  = 0.25,
    HoodPopChance      = 0.20,
    SteeringPull       = true,    -- Bent alignment after heavy front hits
    LimpMode           = true,    -- Low engine health = less power
    RepairCommand      = 'cutuprepair', -- Fix your car while stopped with no run going. false to disable
}

--  ██████╗ ███████╗ █████╗ ██████╗ ██████╗  ██████╗ ██╗  ██╗
-- ██╔════╝ ██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝
-- ██║  ███╗█████╗  ███████║██████╔╝██████╔╝██║   ██║ ╚███╔╝
-- ██║   ██║██╔══╝  ██╔══██║██╔══██╗██╔══██╗██║   ██║ ██╔██╗
-- ╚██████╔╝███████╗██║  ██║██║  ██║██████╔╝╚██████╔╝██╔╝ ██╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝

Config.Transmission = {
    Default               = 'auto', -- 'auto' | 'sequential' | 'hpattern' (players pick their own in F5)
    RequireClutchHPattern = true,   -- H-pattern needs the clutch (key or pedal) to change gear
    RevLimiterCut         = true,   -- Bounce off the limiter in manual
    Redline               = 7500,   -- RPM shown on the tacho at full revs
}

-- ██╗    ██╗██╗  ██╗███████╗███████╗██╗
-- ██║    ██║██║  ██║██╔════╝██╔════╝██║
-- ██║ █╗ ██║███████║█████╗  █████╗  ██║
-- ██║███╗██║██╔══██║██╔══╝  ██╔══╝  ██║
-- ╚███╔███╔╝██║  ██║███████╗███████╗███████╗
--  ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝

-- Any wheel Windows can see (DirectInput or XInput) is read by the browser Gamepad API and fed
-- into the car. Players map and calibrate their wheel in F5 > Wheel, profiles are saved per device.
-- Built-in presets cover wheels most games refuse, like the Thrustmaster Ferrari 458 Spider.
-- No force feedback (FiveM can't drive FFB motors), but rumble works on wheels that support it.
Config.Wheel = {
    Enabled      = true,
    SendRate     = 16,            -- ms between wheel updates (16 = 60 Hz)
    IdleRelease  = 2.0,           -- Seconds without wheel input before keyboard / pad takes over again
    Rumble       = true,          -- Crash / near miss rumble on wheels and pads that support it
}

-- ███████╗ ██████╗ ██████╗ ██████╗ ██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔════╝██╔═══██╗██╔══██╗██║████╗  ██║██╔════╝
-- ███████╗██║     ██║   ██║██████╔╝██║██╔██╗ ██║██║  ███╗
-- ╚════██║██║     ██║   ██║██╔══██╗██║██║╚██╗██║██║   ██║
-- ███████║╚██████╗╚██████╔╝██║  ██║██║██║ ╚████║╚██████╔╝
-- ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Scoring = {
    MinSpeed        = 22.0,       -- m/s (~80 km/h) to earn points
    PassMinRelative = 2.5,        -- m/s faster than the car you pass
    PassBase        = 260,
    DrivePerSecond  = 0.55,       -- Points per km/h per second (before multipliers)
    MaxLateralGap   = 2.6,        -- Side gap (m) that still counts as a pass
    Tiers = {                     -- Gap in metres, body to body
        { gap = 0.35, label = 'INSANE',     mult = 3.0, combo = 3, color = '#e5484d' },
        { gap = 0.80, label = 'VERY CLOSE', mult = 2.0, combo = 2, color = '#ff6fb5' },
        { gap = 1.50, label = 'CLOSE',      mult = 1.5, combo = 1, color = '#a873ff' },
        { gap = 99.0, label = 'PASS',       mult = 1.0, combo = 1, color = '#f2f4f5' },
    },
    OncomingMult    = 2.0,        -- Passing traffic coming the other way
    ComboStep       = 0.05,       -- comboMult = 1 + combo * ComboStep
    ComboHold       = 8.0,        -- Seconds before the combo starts bleeding
    ComboBleed      = 0.12,       -- Share of the combo lost per second after that
    SpeedMultMin    = 80.0,       -- km/h where the speed multiplier starts
    SpeedMultStep   = 25.0,       -- +1x every N km/h
    SpeedMultMax    = 9.9,
    AggroWindow     = 5.0,        -- Close passes inside this many seconds fill the Aggro bar
    AggroPerSegment = 0.15,       -- 4 segments
    PhysicsBonus    = 0.10,       -- Manual / H-pattern / wheel
    FpvBonus        = 0.15,       -- Cockpit cam
    SyncBonus       = 0.25,       -- Flow state with any player
    CrewSyncBonus   = 0.50,       -- Flow state with your crew...
    CrewSyncPerMate = 0.10,       -- ...plus this per extra crewmate in the train
}

-- ██████╗ ██╗   ██╗███╗   ██╗███████╗
-- ██╔══██╗██║   ██║████╗  ██║██╔════╝
-- ██████╔╝██║   ██║██╔██╗ ██║███████╗
-- ██╔══██╗██║   ██║██║╚██╗██║╚════██║
-- ██║  ██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

Config.Run = {
    Duration       = 900,         -- 15:00 run timer (seconds)
    StartSpeed     = 22.0,        -- m/s to start a run on its own
    Hearts         = 3,           -- Crashes allowed per run
    CrashPenalty   = 0.10,        -- Share of the run's points lost on every crash (0 = none)
    IdleTimeout    = 20,          -- Seconds under 20 km/h before the run ends
    MinSubmit      = 10000,       -- Runs below this aren't saved
    CrewRunShare   = 0.45,        -- Share of the run spent in crew flow to count as a CREW run
}

-- ███████╗██╗   ██╗███╗   ██╗ ██████╗
-- ██╔════╝╚██╗ ██╔╝████╗  ██║██╔════╝
-- ███████╗ ╚████╔╝ ██╔██╗ ██║██║
-- ╚════██║  ╚██╔╝  ██║╚██╗██║██║
-- ███████║   ██║   ██║ ╚████║╚██████╗
-- ╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝

-- Flow state: match another driver's speed and line to build the sync meter.
Config.Sync = {
    MinSpeed       = 25.0,        -- m/s
    MaxHeading     = 25.0,        -- Degrees
    MaxSpeedDiff   = 8.0,         -- m/s
    SoloGap        = 35.0,        -- Metres for flow with a player outside your crew
    BuildTime      = 4.0,         -- Seconds to reach FLOW STATE
    BreakGrace     = 3.0,         -- Seconds outside the gap before flow breaks
}

--  ██████╗██████╗ ███████╗██╗    ██╗███████╗
-- ██╔════╝██╔══██╗██╔════╝██║    ██║██╔════╝
-- ██║     ██████╔╝█████╗  ██║ █╗ ██║███████╗
-- ██║     ██╔══██╗██╔══╝  ██║███╗██║╚════██║
-- ╚██████╗██║  ██║███████╗╚███╔███╔╝███████║
--  ╚═════╝╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚══════╝

Config.Crew = {
    MaxMembers     = 8,
    BaseGap        = 40.0,        -- Crew gap with 2 of you on the road
    GapPerMember   = 15.0,        -- Extra gap for every crewmate after that
    MaxGap         = 130.0,
    GhostNonCrew   = true,        -- Players outside your crew drive straight through you
    GhostAlpha     = 175,         -- How see-through they are (255 = solid)
    InviteTimeout  = 60,          -- Seconds
    NameLength     = { 3, 20 },
    TagLength      = { 2, 4 },
    Colors = { '#a873ff', '#ff6fb5', '#3d9bff', '#e5a50a', '#46c08a', '#e5484d', '#08afa2', '#f2f4f5' },
}

-- ██████╗  █████╗ ██████╗  █████╗ ██████╗
-- ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔══██╗
-- ██████╔╝███████║██║  ██║███████║██████╔╝
-- ██╔══██╗██╔══██║██║  ██║██╔══██║██╔══██╗
-- ██║  ██║██║  ██║██████╔╝██║  ██║██║  ██║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝

-- Red threat arrows orbit your car while a player outside your crew is closing in,
-- and drop off once they're past you.
Config.Radar = {
    Enabled        = true,
    Range          = 70.0,
    AheadClear     = 6.0,         -- Arrow goes away once they're this far in front
}

-- ██████╗  █████╗ ███╗   ██╗██╗  ██╗███████╗
-- ██╔══██╗██╔══██╗████╗  ██║██║ ██╔╝██╔════╝
-- ██████╔╝███████║██╔██╗ ██║█████╔╝ ███████╗
-- ██╔══██╗██╔══██║██║╚██╗██║██╔═██╗ ╚════██║
-- ██║  ██║██║  ██║██║ ╚████║██║  ██╗███████║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝

-- Ranks by personal best (solo or crew, whichever is higher)
Config.Ranks = {
    { name = 'Rookie 1',  min = 0,          color = '#a7aeb3' },
    { name = 'Rookie 2',  min = 500000,     color = '#a7aeb3' },
    { name = 'Rookie 3',  min = 1500000,    color = '#a7aeb3' },
    { name = 'Street 1',  min = 3000000,    color = '#46c08a' },
    { name = 'Street 2',  min = 6000000,    color = '#46c08a' },
    { name = 'Street 3',  min = 10000000,   color = '#46c08a' },
    { name = 'Marked 1',  min = 15000000,   color = '#3d9bff' },
    { name = 'Marked 2',  min = 25000000,   color = '#3d9bff' },
    { name = 'Marked 3',  min = 35000000,   color = '#3d9bff' },
    { name = 'Pro 1',     min = 50000000,   color = '#a873ff' },
    { name = 'Pro 2',     min = 70000000,   color = '#a873ff' },
    { name = 'Pro 3',     min = 95000000,   color = '#a873ff' },
    { name = 'Elite 1',   min = 125000000,  color = '#ff6fb5' },
    { name = 'Elite 2',   min = 165000000,  color = '#ff6fb5' },
    { name = 'Elite 3',   min = 215000000,  color = '#ff6fb5' },
    { name = 'Legend',    min = 300000000,  color = '#e5484d' },
}

-- ██████╗  ██████╗  █████╗ ██████╗ ██████╗ ███████╗
-- ██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝
-- ██████╔╝██║   ██║███████║██████╔╝██║  ██║███████╗
-- ██╔══██╗██║   ██║██╔══██║██╔══██╗██║  ██║╚════██║
-- ██████╔╝╚██████╔╝██║  ██║██║  ██║██████╔╝███████║
-- ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝

Config.Leaderboard = {
    Size           = 100,         -- Rows per board
    Cache          = 15,          -- Seconds a board is cached on the server
    AnnounceTop    = 10,          -- Tell the whole server when someone breaks into the top N. false = never
}

--  █████╗ ███╗   ██╗████████╗██╗ ██████╗██╗  ██╗███████╗ █████╗ ████████╗
-- ██╔══██╗████╗  ██║╚══██╔══╝██║██╔════╝██║  ██║██╔════╝██╔══██╗╚══██╔══╝
-- ███████║██╔██╗ ██║   ██║   ██║██║     ███████║█████╗  ███████║   ██║
-- ██╔══██║██║╚██╗██║   ██║   ██║██║     ██╔══██║██╔══╝  ██╔══██║   ██║
-- ██║  ██║██║ ╚████║   ██║   ██║╚██████╗██║  ██║███████╗██║  ██║   ██║
-- ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝

-- Every run is checked on the server before it hits the leaderboard.
Config.Validation = {
    MaxPointsPerSecond = 600000,
    MaxAvgSpeed        = 140.0,   -- m/s
    SubmitCooldown     = 15,      -- Seconds between submissions
    MaxCombo           = 5000,
}

--  ██████╗██╗   ██╗███████╗████████╗ ██████╗ ███╗   ███╗
-- ██╔════╝██║   ██║██╔════╝╚══██╔══╝██╔═══██╗████╗ ████║
-- ██║     ██║   ██║███████╗   ██║   ██║   ██║██╔████╔██║
-- ██║     ██║   ██║╚════██║   ██║   ██║   ██║██║╚██╔╝██║
-- ╚██████╗╚██████╔╝███████║   ██║   ╚██████╔╝██║ ╚═╝ ██║
--  ╚═════╝ ╚═════╝ ╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝

-- Return false to stop CUT UP mode at the player's current spot (client-side, e.g. a safezone or city centre).
Config.CanCutUpHere = function(coords)
    return true
end
