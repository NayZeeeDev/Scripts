-- ███████╗████████╗ █████╗ ███╗   ██╗ ██████╗███████╗
-- ██╔════╝╚══██╔══╝██╔══██╗████╗  ██║██╔════╝██╔════╝
-- ███████╗   ██║   ███████║██╔██╗ ██║██║     █████╗
-- ╚════██║   ██║   ██╔══██║██║╚██╗██║██║     ██╔══╝
-- ███████║   ██║   ██║  ██║██║ ╚████║╚██████╗███████╗
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝

Config.Stance = {
    Enabled       = true,
    Offset        = { min = -0.06, max = 0.16, step = 0.005 },  -- metres added to each wheel's track (per axle)
    Camber        = { min = 0.0,   max = 14.0, step = 0.5 },    -- degrees of negative camber (per axle)
    StreamRange   = 45.0,           -- other players' stanced cars are only processed inside this range
    OnScreenOnly  = true,           -- skip cars you can't see
    BlockedClasses= { [8] = true, [13] = true, [10] = true, [11] = true, [17] = true, [18] = true, [19] = true, [20] = true, [22] = true },
    ModelLimits   = {               -- per-model overrides
        -- zr350 = { Offset = { min = -0.04, max = 0.22 }, Camber = { min = 0, max = 20 } },
        -- adder = false,           -- no stance at all
    },
}

Config.WheelDimensions = {
    Size  = { min = 0.55, max = 1.25, step = 0.01 },     -- absolute wheel size (needs custom rims fitted)
    Width = { min = 0.45, max = 1.30, step = 0.01 },
}

Config.RideHeight = {
    Enabled = true,
    min = -0.10,                    -- negative raises the car
    max = 0.12,                     -- positive lowers the car
    step = 0.005,
}

--  █████╗ ██╗██████╗     ██████╗ ██╗██████╗ ███████╗
-- ██╔══██╗██║██╔══██╗    ██╔══██╗██║██╔══██╗██╔════╝
-- ███████║██║██████╔╝    ██████╔╝██║██║  ██║█████╗
-- ██╔══██║██║██╔══██╗    ██╔══██╗██║██║  ██║██╔══╝
-- ██║  ██║██║██║  ██║    ██║  ██║██║██████╔╝███████╗
-- ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝╚═════╝ ╚══════╝

Config.AirRide = {
    Enabled   = true,
    Presets   = {                   -- cycled with the air ride keys, height = suspension offset
        { label = 'Lifted',  height = -0.06 },
        { label = 'Street',  height = 0.0 },
        { label = 'Low',     height = 0.06 },
        { label = 'Slammed', height = 0.115 },
    },
    DefaultPreset = 2,
    MaxSpeedToChange = 60.0,        -- km/h; can't drop the bags at speed
    TransitionMs  = 1400,
    SlammedSpeedCap = 45.0,         -- km/h cap while on the lowest preset (0 = none)
    HissSound     = true,           -- synthesized air hiss (NUI, heard nearby)
}

-- ███╗   ██╗██╗████████╗██████╗  ██████╗ ██╗   ██╗███████╗
-- ████╗  ██║██║╚══██╔══╝██╔══██╗██╔═══██╗██║   ██║██╔════╝
-- ██╔██╗ ██║██║   ██║   ██████╔╝██║   ██║██║   ██║███████╗
-- ██║╚██╗██║██║   ██║   ██╔══██╗██║   ██║██║   ██║╚════██║
-- ██║ ╚████║██║   ██║   ██║  ██║╚██████╔╝╚██████╔╝███████║
-- ╚═╝  ╚═══╝╚═╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝

Config.Nitrous = {
    Enabled   = true,
    Levels    = {                   -- bought in the tuning menu
        { label = 'Single Shot', capacity = 100, power = 1.55, price = 25000 },
        { label = 'Dual Shot',   capacity = 180, power = 1.75, price = 42000 },
        { label = 'Race Kit',    capacity = 260, power = 2.00, price = 68000 },
    },
    DrainPerSecond = 14.0,          -- units per second while boosting
    PurgeDrainPerSecond = 6.0,
    MinSpeed       = 8.0,           -- km/h before the boost can fire
    Flames         = true,          -- exhaust flames while boosting (networked particles)
    ScreenEffect   = true,          -- motion blur + FOV kick for the driver
    RefillPrice    = 3500,          -- refill at any bay (menu shows a refill item when installed)
    RefillItem     = 'nitrous_bottle', -- usable item that refills the installed kit (false = off)
    RefillItemAmount = 100,
    Hud            = true,          -- small gauge while driving a car with nitrous
}

-- ███████╗ ██████╗██╗   ██╗
-- ██╔════╝██╔════╝██║   ██║
-- █████╗  ██║     ██║   ██║
-- ██╔══╝  ██║     ██║   ██║
-- ███████╗╚██████╗╚██████╔╝
-- ╚══════╝ ╚═════╝ ╚═════╝

-- Every ECU value is a percent change from the car's own handling. The player sets them with sliders.
Config.ECU = {
    Enabled = true,
    Params = {
        { key = 'power',      label = 'Power Map',        min = -10, max = 12, step = 1,  unit = '%', field = 'fInitialDriveForce' },
        { key = 'gearing',    label = 'Final Drive',      min = -8,  max = 8,  step = 1,  unit = '%', field = 'fInitialDriveMaxFlatVel', hint = 'Left = quicker launch, right = more top speed' },
        { key = 'brake',      label = 'Brake Force',      min = -15, max = 20, step = 1,  unit = '%', field = 'fBrakeForce' },
        { key = 'brakeBias',  label = 'Brake Bias Front', min = -10, max = 10, step = 1,  unit = '%', field = 'fBrakeBiasFront', absolute = true },
        { key = 'grip',       label = 'Tyre Grip',        min = -10, max = 8,  step = 1,  unit = '%', field = 'fTractionCurveMax' },
        { key = 'gripBias',   label = 'Grip Bias Front',  min = -10, max = 10, step = 1,  unit = '%', field = 'fTractionBiasFront', absolute = true },
        { key = 'antiRoll',   label = 'Anti-Roll Bars',   min = -50, max = 50, step = 5,  unit = '%', field = 'fAntiRollBarForce' },
        { key = 'spring',     label = 'Spring Rate',      min = -30, max = 30, step = 2,  unit = '%', field = 'fSuspensionForce' },
        { key = 'damping',    label = 'Damping',          min = -30, max = 30, step = 2,  unit = '%', field = 'fSuspensionCompDamp' },
        { key = 'steer',      label = 'Steering Lock',    min = -10, max = 15, step = 1,  unit = '%', field = 'fSteeringLock' },
    },
    Presets = {
        { label = 'Street',   values = { } },
        { label = 'Drag',     values = { power = 10, gearing = -6, grip = 4, gripBias = -6, spring = 10, antiRoll = -20 } },
        { label = 'Track',    values = { power = 6, gearing = 2, brake = 15, grip = 6, antiRoll = 30, spring = 20, damping = 16, steer = 4 } },
        { label = 'Drift',    values = { power = 8, gearing = -4, grip = -8, gripBias = 8, steer = 15, antiRoll = 20, brakeBias = -6 } },
        { label = 'Economy',  values = { power = -8, gearing = 6 } },
    },
    -- The tuning menu only sells the programmable ECU (hardware). Every calibration - the sliders above,
    -- the presets and the ignition map below - is written by a mechanic in the tablet (ECU Studio).
    -- Ignition map editor. Mechanics flash it onto cars with an ECU fitted.
    Map = {
        Cells      = 8,                 -- columns from 1k to 8k rpm
        Base       = 50,                -- stock value of every cell
        MaxGain    = 14,                -- % extra power with every cell at 100
        Thresholds = { 85, 82, 78, 74, 70, 66, 62, 58 }, -- above this a cell knocks
        FuelRaise  = 0.30,              -- each % of fuel enrichment raises every threshold by this much
        FuelCost   = 5,                 -- % power lost at 100 % enrichment
        KnockWear  = 0.35,              -- extra engine wear per knocking cell
        KnockDamage= 5,                 -- this many knocking cells starts damaging the engine at high rpm
        Jobs       = nil,               -- nil = any workshop employee, or { 'mechanic' }
    },
}

--  █████╗ ███╗   ██╗████████╗██╗      ██╗      █████╗  ██████╗
-- ██╔══██╗████╗  ██║╚══██╔══╝██║      ██║     ██╔══██╗██╔════╝
-- ███████║██╔██╗ ██║   ██║   ██║█████╗██║     ███████║██║  ███╗
-- ██╔══██║██║╚██╗██║   ██║   ██║╚════╝██║     ██╔══██║██║   ██║
-- ██║  ██║██║ ╚████║   ██║   ██║      ███████╗██║  ██║╚██████╔╝
-- ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝      ╚══════╝╚═╝  ╚═╝ ╚═════╝

Config.AntiLag = {
    Enabled   = true,
    MinRpm    = 0.72,               -- pops fire when the throttle is lifted above this rpm
    Cooldown  = 140,                -- ms between pops
    MaxPops   = 4,                  -- per lift
    Sound     = true,               -- crackle (NUI audio, heard nearby)
}

Config.LaunchControl = {
    Enabled    = true,
    HoldRpm    = 0.62,              -- rev hold while armed
    BoostMs    = 2200,              -- traction help after release
    TractionHelp = 0.35,            -- fLowSpeedTractionLossMult while launching
}

Config.Turbo = {
    BlowOff    = true,              -- blow-off valve sound for cars with a turbo (driver + nearby)
    MinRpm     = 0.65,
}

-- ███████╗███╗   ██╗ ██████╗ ██╗███╗   ██╗███████╗    ███████╗██╗    ██╗ █████╗ ██████╗ ███████╗
-- ██╔════╝████╗  ██║██╔════╝ ██║████╗  ██║██╔════╝    ██╔════╝██║    ██║██╔══██╗██╔══██╗██╔════╝
-- █████╗  ██╔██╗ ██║██║  ███╗██║██╔██╗ ██║█████╗      ███████╗██║ █╗ ██║███████║██████╔╝███████╗
-- ██╔══╝  ██║╚██╗██║██║   ██║██║██║╚██╗██║██╔══╝      ╚════██║██║███╗██║██╔══██║██╔═══╝ ╚════██║
-- ███████╗██║ ╚████║╚██████╔╝██║██║ ╚████║███████╗    ███████║╚███╔███╔╝██║  ██║██║     ███████║
-- ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝    ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝     ╚══════╝

-- sound = any vanilla (or streamed add-on) vehicle audio name
-- power = extra drive force multiplier while swapped (1.0 = sound only)
Config.EngineSwaps = {
    Enabled = true,
    List = {                        -- family picks the engine item needed (config.items.lua Engines)
        { sound = 'blista',     label = '1.6 I4',             family = 'i4',  power = 1.00, price = 20000 },
        { sound = 'futo',       label = '2.0 I4 Twin Cam',    family = 'i4',  power = 1.02, price = 32000 },
        { sound = 'sultan',     label = '2.0 I4 Turbo',       family = 'i4',  power = 1.04, price = 38000 },
        { sound = 'elegy2',     label = '2.6 I6 Twin Turbo',  family = 'v6',  power = 1.06, price = 55000 },
        { sound = 'kuruma',     label = '3.0 V6',             family = 'v6',  power = 1.05, price = 52000 },
        { sound = 'jester',     label = '3.2 I6',             family = 'v6',  power = 1.07, price = 64000 },
        { sound = 'dominator',  label = '5.0 V8',             family = 'v8',  power = 1.08, price = 78000 },
        { sound = 'gauntlet',   label = '6.4 V8 Hemi',        family = 'v8',  power = 1.10, price = 92000 },
        { sound = 'ratloader2', label = '7.0 V8 Big Block',   family = 'v8',  power = 1.10, price = 105000 },
        { sound = 'banshee',    label = '8.4 V10',            family = 'v10', power = 1.12, price = 135000 },
        { sound = 'zentorno',   label = '6.5 V12',            family = 'v12', power = 1.14, price = 175000 },
        { sound = 'italigtb',   label = '3.9 V8 Twin Turbo',  family = 'v8',  power = 1.12, price = 160000 },
        { sound = 'openwheel1', label = '1.6 V6 Hybrid',      family = 'v6',  power = 1.15, price = 240000 },
        { sound = 'voltic',     label = 'EV Conversion',      family = 'ev',  power = 1.06, price = 90000, electric = true },
        { sound = 'cyclone',    label = 'EV Performance',     family = 'ev',  power = 1.12, price = 160000, electric = true },
    },
    ByClass = {                     -- which swaps a class may use (nil = all, false = none)
        [0] = { 'blista', 'futo', 'sultan', 'kuruma' },
        [8] = false, [13] = false, [10] = false, [11] = false, [14] = false, [15] = false, [16] = false, [21] = false,
    },
    ByModel = {                     -- overrides ByClass
        -- dubsta = { 'dominator', 'gauntlet', 'ratloader2' },
    },
}

-- ██╗    ██╗███████╗ █████╗ ██████╗
-- ██║    ██║██╔════╝██╔══██╗██╔══██╗
-- ██║ █╗ ██║█████╗  ███████║██████╔╝
-- ██║███╗██║██╔══╝  ██╔══██║██╔══██╗
-- ╚███╔███╔╝███████╗██║  ██║██║  ██║
--  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝

Config.Wear = {
    Enabled        = true,
    OwnedOnly      = true,          -- only owned cars wear
    SyncEvery      = 60,            -- seconds between saves while driving
    RatePerKm      = {              -- % condition lost per km driven
        engine = 0.10, transmission = 0.07, brakes = 0.28, suspension = 0.09, tyres = 0.34, turbo = 0.14,
    },
    HardDriving    = 1.8,           -- multiplier when the car is driven hard (high rpm / sliding)
    ServiceThreshold = 60,          -- below this a 'service due' warning shows
    Effects = {                     -- below 'at' %, performance scales down to 'floor' at 0 %
        engine = { at = 45, floor = 0.80 },
        brakes = { at = 40, floor = 0.70 },
        tyres  = { at = 35, floor = 0.82 },
        turbo  = { at = 30, floor = 0.92 },
    },
    ServicePricePerPoint = 22,      -- Major Service price scales with how much wear is restored (plus the base price)
}

-- ██████╗ ███████╗██████╗ ███████╗    ████████╗███████╗███████╗████████╗
-- ██╔══██╗██╔════╝██╔══██╗██╔════╝    ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝
-- ██████╔╝█████╗  ██████╔╝█████╗         ██║   █████╗  ███████╗   ██║
-- ██╔═══╝ ██╔══╝  ██╔══██╗██╔══╝         ██║   ██╔══╝  ╚════██║   ██║
-- ██║     ███████╗██║  ██║██║            ██║   ███████╗███████║   ██║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝            ╚═╝   ╚══════╝╚══════╝   ╚═╝

Config.PerfTest = {
    Enabled   = true,
    Command   = 'perftest',
    Units     = 'mph',              -- 'mph' | 'kmh'
    Tests = {
        { id = 'zero60',   label = '0-60 mph',    target = 60,  kind = 'speed' },
        { id = 'zero100',  label = '0-100 mph',   target = 100, kind = 'speed' },
        { id = 'quarter',  label = '1/4 Mile',    target = 402.3, kind = 'distance' },
        { id = 'half',     label = '1/2 Mile',    target = 804.7, kind = 'distance' },
        { id = 'brake60',  label = '60-0 Braking',target = 60,  kind = 'brake' },
    },
    MinTimes  = { zero60 = 1.4, zero100 = 3.2, quarter = 6.2, half = 10.0, brake60 = 1.4 }, -- anything faster is rejected
    Leaderboard = 15,
    Timeout   = 45,                 -- seconds before a run is abandoned
}

--  ██████╗██╗  ██╗ █████╗ ███████╗███████╗██╗███████╗
-- ██╔════╝██║  ██║██╔══██╗██╔════╝██╔════╝██║██╔════╝
-- ██║     ███████║███████║███████╗███████╗██║███████╗
-- ██║     ██╔══██║██╔══██║╚════██║╚════██║██║╚════██║
-- ╚██████╗██║  ██║██║  ██║███████║███████║██║███████║
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝╚══════╝

Config.Tyres = {                    -- tyre compounds (Performance > Tyre Compound)
    Enabled = true,
    List = {
        { id = 'stock',   label = 'Road',          grip = 1.00, offroad = 1.00, price = 2500 },
        { id = 'semi',    label = 'Semi Slick',    grip = 1.06, offroad = 1.25, price = 9000 },
        { id = 'slick',   label = 'Slick',         grip = 1.12, offroad = 1.70, price = 16000 },
        { id = 'offroad', label = 'All Terrain',   grip = 0.96, offroad = 0.45, price = 8000 },
    },
}

Config.Drivetrain = {               -- drivetrain conversions
    Enabled = true,
    List = {
        { id = 'stock', label = 'Factory',  bias = nil,  price = 6000 },
        { id = 'awd',   label = 'AWD',      bias = 0.45, price = 38000 },
        { id = 'rwd',   label = 'RWD',      bias = 0.0,  price = 26000 },
        { id = 'fwd',   label = 'FWD',      bias = 1.0,  price = 22000 },
    },
    BlockedClasses = { [8] = true, [13] = true },
}

Config.CeramicBrakes = { Enabled = true, BrakeForce = 1.22, WearRate = 0.5, Price = 26000 }

Config.DriftKit = {                 -- handling package for drifting
    Enabled = true, Price = 24000,
    Steer = 1.35, CurveMin = 0.82, CurveMax = 0.92, BiasFront = -0.08, LowSpeedLoss = 1.4,
}

--  ██████╗ ███████╗ █████╗ ██████╗ ██████╗  ██████╗ ██╗  ██╗
-- ██╔════╝ ██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝
-- ██║  ███╗█████╗  ███████║██████╔╝██████╔╝██║   ██║ ╚███╔╝
-- ██║   ██║██╔══╝  ██╔══██║██╔══██╗██╔══██╗██║   ██║ ██╔██╗
-- ╚██████╔╝███████╗██║  ██║██║  ██║██████╔╝╚██████╔╝██╔╝ ██╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝

Config.Gearbox = {
    Enabled    = true,
    Price      = 21000,
    ShiftUp    = 'UP',              -- keybinds (rebindable in settings)
    ShiftDown  = 'DOWN',
    Toggle     = 'K',               -- switch manual / auto on a car with the manual box
    OverRevDamage = 18.0,           -- engine damage for a money shift (downshift into the red)
    Hud        = true,
}

Config.DriverAssists = {            -- TCS / ESC, toggled per car with /tcs and /esc or in the tablet
    Enabled = true,
    TCS = { LowSpeedLoss = 0.55, TractionLoss = 0.85 },
    ESC = { Lateral = 1.08, BiasFront = 0.02 },
}

-- ███████╗ ██████╗ ██╗   ██╗███╗   ██╗██████╗
-- ██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔══██╗
-- ███████╗██║   ██║██║   ██║██╔██╗ ██║██║  ██║
-- ╚════██║██║   ██║██║   ██║██║╚██╗██║██║  ██║
-- ███████║╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝
-- ██████╗  █████╗  ██████╗██╗  ██╗███████╗
-- ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
-- ██████╔╝███████║██║     █████╔╝ ███████╗
-- ██╔═══╝ ██╔══██║██║     ██╔═██╗ ╚════██║
-- ██║     ██║  ██║╚██████╗██║  ██╗███████║
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

-- Exhaust / engine notes without changing the engine. Any vanilla or streamed add-on audio name works.
Config.SoundPacks = {
    Enabled = true,
    Price   = 12000,
    List = {
        { audio = 'sultanrs',  label = 'Rally Turbo' },
        { audio = 'elegy',     label = 'Twin Turbo Six' },
        { audio = 'comet2',    label = 'Flat Six' },
        { audio = 'dominator', label = 'American V8' },
        { audio = 'banshee2',  label = 'Screaming V10' },
        { audio = 'nero',      label = 'Hypercar W16' },
        { audio = 'osiris',    label = 'Italian V12' },
        { audio = 'jester3',   label = 'Rotary' },
        -- packs bundled inside this script (fxmanifest.lua ENGINE_SOUNDS) are added to this list automatically.
        -- packs streamed by another resource: list the audio name here
        -- { audio = 'n55b30t0', label = 'Ubermacht N55' },
    },
}
