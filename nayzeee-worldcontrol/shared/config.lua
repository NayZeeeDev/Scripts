--[[
    NAYZEEE WorldControl - Configuration
    Weather • Time • Traffic • World Events
    discord.gg/nayzeeedev
]]

Config = {}

-- Enable debug messages in F8 / server console
Config.Debug = false

-- ══════════════════════════════════════════════════════════════
-- COMMANDS
-- ══════════════════════════════════════════════════════════════

Config.Command = 'worldcontrol'         -- Opens the control panel
Config.CommandAliases = { 'traffic', 'easytime', 'weathermenu' } -- Extra commands that also open the panel
Config.Keybind = nil                    -- e.g. 'F7' to add a rebindable keybind, nil to disable

-- Quick admin chat commands (server-side, permission checked). Set any to false to disable.
Config.QuickCommands = {
    weather = 'weather',        -- /weather [type] [instant]
    time = 'time',              -- /time [hour] [minute]
    freeze = 'freezetime',      -- /freezetime
    blackout = 'blackout',      -- /blackout
    restart = 'restartwarning', -- /restartwarning [minutes] | /restartwarning cancel
}

-- ══════════════════════════════════════════════════════════════
-- NOTIFICATIONS
-- 'auto' = ox_lib if started, otherwise the built-in NAYZEEE toasts
-- 'nui' | 'ox_lib' | 'qb' | 'esx' | 'chat'
-- ══════════════════════════════════════════════════════════════

Config.Notify = 'auto'

-- ══════════════════════════════════════════════════════════════
-- PERMISSIONS (checked server-side for every change)
-- ══════════════════════════════════════════════════════════════

Config.Permissions = {
    enabled = true,                         -- Set false to allow anyone
    acePermissions = {                      -- Any of these ACEs grants access
        'worldcontrol.admin',
        'traffic.control',                  -- Legacy nayzeee-traffic ACE still works
    },
    allowedGroups = {                       -- ESX groups / QBCore permissions / ACE 'group.<name>' (Qbox, vanilla)
        'admin',
        'superadmin',
        'mod',
        'god',
    },
    identifiers = {                         -- Optional: specific players (license:xxx, discord:xxx, fivem:xxx, steam:xxx)
        -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    },
}

-- ══════════════════════════════════════════════════════════════
-- PERFORMANCE
-- ══════════════════════════════════════════════════════════════

Config.Performance = {
    -- Density mode:
    --   'frame' = exact density control. 0.00ms while densities are all 100%,
    --             ~0.01ms while any slider is changed (GTA requires these natives every frame).
    --   'zero'  = 0.00ms always. Uses persistent population budgets + a map-wide population
    --             multiplier area instead of per-frame natives. Slightly less granular.
    densityMode = 'frame',

    watchdogInterval = 5000,    -- (ms) How often the client verifies weather/rain is still correct
}

-- ══════════════════════════════════════════════════════════════
-- WEATHER
-- ══════════════════════════════════════════════════════════════

Config.Weather = {
    default = 'EXTRASUNNY',     -- Weather on first start (afterwards the last state is restored)
    method = 'game',            -- 'game' (dynamic GTA cycle) or 'real' (real-world weather, needs API key)
    instant = false,            -- Default for instant vs smooth weather changes
    transitionTime = 45.0,      -- (seconds) Smooth weather transition length

    -- Dynamic weather (method = 'game')
    dynamic = true,             -- Cycle weather automatically
    interval = 15,              -- (minutes) Time between weather changes
    forecastLength = 4,         -- How many upcoming weathers to show in the forecast

    -- Groups are picked by weight, then played through in order for a natural progression.
    -- Entries can be a weather name, or { 'WEATHER', chance = 0-100 } to sometimes skip it.
    groups = {
        { name = 'Clear', weight = 55, sequence = { 'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'CLEAR' } },
        { name = 'Rain',  weight = 22, sequence = { 'CLOUDS', 'OVERCAST', 'RAIN', { 'THUNDER', chance = 40 }, 'CLEARING' } },
        { name = 'Fog',   weight = 15, sequence = { 'OVERCAST', 'FOGGY', { 'SMOG', chance = 50 }, 'CLEARING' } },
        { name = 'Snow',  weight = 0,  sequence = { 'OVERCAST', 'SNOWLIGHT', 'SNOW', { 'BLIZZARD', chance = 25 }, 'SNOWLIGHT' } },
    },

    -- Real-world weather (method = 'real')
    real = {
        apiKey = 'CHANGE_ME',   -- Free key: https://openweathermap.org/api
        city = 'Los Angeles',
        checkInterval = 15,     -- (minutes)
        syncWind = true,        -- Also copy real wind speed/direction
    },
}

-- Weather types shown in the panel (order = display order).
-- Halloween variants with 'build' only show on that game build or newer.
Config.WeatherTypes = {
    { id = 'EXTRASUNNY',     label = 'Extra Sunny', icon = 'sun' },
    { id = 'CLEAR',          label = 'Clear',       icon = 'cloud-sun' },
    { id = 'CLOUDS',         label = 'Clouds',      icon = 'cloud' },
    { id = 'OVERCAST',       label = 'Overcast',    icon = 'cloud-meatball' },
    { id = 'CLEARING',       label = 'Clearing',    icon = 'cloud-sun-rain' },
    { id = 'RAIN',           label = 'Rain',        icon = 'cloud-rain' },
    { id = 'THUNDER',        label = 'Thunder',     icon = 'cloud-bolt' },
    { id = 'SMOG',           label = 'Smog',        icon = 'smog' },
    { id = 'FOGGY',          label = 'Foggy',       icon = 'water' },
    { id = 'SNOWLIGHT',      label = 'Light Snow',  icon = 'snowflake' },
    { id = 'SNOW',           label = 'Snow',        icon = 'snowman' },
    { id = 'BLIZZARD',       label = 'Blizzard',    icon = 'wind' },
    { id = 'XMAS',           label = 'Christmas',   icon = 'tree' },
    { id = 'HALLOWEEN',      label = 'Halloween',   icon = 'ghost' },
    { id = 'NEUTRAL',        label = 'Neutral',     icon = 'circle-half-stroke' },
    { id = 'RAIN_HALLOWEEN', label = 'Spooky Rain', icon = 'skull',  build = 3258 },
    { id = 'SNOW_HALLOWEEN', label = 'Spooky Snow', icon = 'spider', build = 3258 },
}

-- ══════════════════════════════════════════════════════════════
-- TIME
-- ══════════════════════════════════════════════════════════════

Config.Time = {
    default = { hour = 8, minute = 0 },  -- Time on first start
    method = 'game',            -- 'game' (server-synced GTA clock) or 'real' (real-world clock)
    instant = false,            -- Default for instant vs smooth time changes
    transitionTime = 6000,      -- (ms) Smooth time transition length
    msPerGameMinute = 2000,     -- 2000 = GTA default (48 minute day). Changeable live in the panel.
    syncInterval = 30,          -- (seconds) Drift-correction heartbeat. Clients only snap if they drift.

    real = {
        utcOffset = -7,         -- Hours from UTC, e.g. -7 Los Angeles (summer), 0 London, 1 Paris
        useWeatherApiZone = true, -- When real weather is on, use the API city timezone instead
    },

    quick = {                   -- Quick time buttons in the panel
        { label = 'Dawn',     hour = 5,  minute = 30, icon = 'mountain-sun' },
        { label = 'Morning',  hour = 8,  minute = 0,  icon = 'mug-hot' },
        { label = 'Noon',     hour = 12, minute = 0,  icon = 'sun' },
        { label = 'Sunset',   hour = 19, minute = 30, icon = 'cloud-sun' },
        { label = 'Night',    hour = 22, minute = 0,  icon = 'moon' },
        { label = 'Midnight', hour = 0,  minute = 0,  icon = 'star' },
    },
}

-- ══════════════════════════════════════════════════════════════
-- WORLD (atmosphere)
-- ══════════════════════════════════════════════════════════════

Config.World = {
    blackout = false,               -- Default blackout state
    blackoutAffectsVehicles = false,-- Turn vehicle lights off during blackouts too
    snowOnGround = false,           -- Force snow on the ground / tyre & footstep tracks
    wind = -1.0,                    -- Default wind speed 0-12 (-1 = let the weather decide)
    windDirection = 0,              -- Degrees 0-359
    rain = -1.0,                    -- Rain intensity 0.0-1.0 (-1 = let the weather decide)
}

-- ══════════════════════════════════════════════════════════════
-- TRAFFIC & POPULATION (0.0 = none, 1.0 = normal GTA default)
-- ══════════════════════════════════════════════════════════════

Config.Traffic = {
    maxDensity = 1.5,       -- Max slider value (1.5 = 150%)
    defaults = {
        pedestrians = 1.0,      -- Pedestrian density
        vehicles = 1.0,         -- Vehicle density
        parkedCars = 1.0,       -- Parked car density
        randomVehicles = 1.0,   -- Random vehicles on roads
        scenarioPeds = 1.0,     -- Scenario peds (people doing activities)
    },

    -- Ambient services (toggleable live in the panel)
    services = {
        dispatch = false,       -- Police / EMS / fire dispatch responding to crimes
        garbageTrucks = false,  -- Random garbage trucks
        randomBoats = false,    -- Random boats on water
        randomTrains = true,    -- Ambient trains
        randomCops = true,      -- Ambient police patrols
        wantedLevel = true,     -- Players can receive a wanted level
        distantSirens = true,   -- Distant police siren audio
    },

    -- Purge: density multipliers only stop NEW spawns. This clears existing
    -- peds/vehicles near each player so lowering density takes effect instantly.
    purge = {
        enabled = true,
        radius = 150.0,
        duration = 3000,    -- (ms) keep clearing to catch stragglers
        interval = 500,     -- (ms)
    },
}

Config.TrafficPresets = {
    { id = 'empty',   label = 'Empty City', icon = 'ghost',     pedestrians = 0.0, vehicles = 0.0, parkedCars = 0.0, randomVehicles = 0.0, scenarioPeds = 0.0 },
    { id = 'minimal', label = 'Minimal',    icon = 'moon',      pedestrians = 0.2, vehicles = 0.2, parkedCars = 0.3, randomVehicles = 0.2, scenarioPeds = 0.2 },
    { id = 'light',   label = 'Light',      icon = 'cloud-sun', pedestrians = 0.4, vehicles = 0.4, parkedCars = 0.5, randomVehicles = 0.4, scenarioPeds = 0.4 },
    { id = 'normal',  label = 'Normal',     icon = 'sun',       pedestrians = 1.0, vehicles = 1.0, parkedCars = 1.0, randomVehicles = 1.0, scenarioPeds = 1.0 },
    { id = 'busy',    label = 'Rush Hour',  icon = 'car-burst', pedestrians = 1.5, vehicles = 1.5, parkedCars = 1.0, randomVehicles = 1.5, scenarioPeds = 1.0 },
    { id = 'peds',    label = 'Walkers',    icon = 'person-walking', pedestrians = 1.2, vehicles = 0.2, parkedCars = 0.6, randomVehicles = 0.2, scenarioPeds = 1.2 },
}

-- ══════════════════════════════════════════════════════════════
-- SCENES (one-click world presets: weather + time + world + traffic)
-- Any field can be left out to keep its current value.
-- ══════════════════════════════════════════════════════════════

Config.Scenes = {
    { id = 'sunny_day',  label = 'Sunny Day',      icon = 'sun',             weather = 'EXTRASUNNY', hour = 13, minute = 0,  blackout = false, snowOnGround = false, traffic = 'normal' },
    { id = 'golden',     label = 'Golden Hour',    icon = 'camera',          weather = 'CLEAR',      hour = 19, minute = 15, blackout = false },
    { id = 'storm',      label = 'Storm Front',    icon = 'cloud-bolt',      weather = 'THUNDER',    hour = 17, minute = 0,  wind = 12.0, traffic = 'light' },
    { id = 'fog_morning',label = 'Foggy Morning',  icon = 'water',           weather = 'FOGGY',      hour = 6,  minute = 0 },
    { id = 'christmas',  label = 'Christmas',      icon = 'gifts',           weather = 'XMAS',       hour = 20, minute = 0,  snowOnGround = true },
    { id = 'halloween',  label = 'Halloween',      icon = 'ghost',           weather = 'HALLOWEEN',  hour = 23, minute = 30, blackout = false },
    { id = 'blackout',   label = 'City Blackout',  icon = 'plug-circle-xmark', weather = 'OVERCAST', hour = 23, minute = 0,  blackout = true, traffic = 'minimal' },
    { id = 'ghost_town', label = 'Ghost Town',     icon = 'city',            weather = 'SMOG',       hour = 3,  minute = 0,  traffic = 'empty' },
}

-- ══════════════════════════════════════════════════════════════
-- RESTART WARNING (storm + blackout + siren countdown before a restart)
-- ══════════════════════════════════════════════════════════════

Config.RestartWarning = {
    enabled = true,
    minutes = 5,                -- Default countdown length
    txAdmin = true,             -- Auto-start when txAdmin announces a scheduled restart
    weather = 'THUNDER',        -- Storm weather (RAIN_HALLOWEEN is used instead on build 3258+ if available)
    blackoutAt = 0.5,           -- Fraction of the countdown elapsed before the blackout hits
    siren = true,               -- Play a siren for every player
    sirenVolume = 0.25,         -- 0.0-1.0
    title = 'Tsunami Warning',
    message = 'A storm is approaching. The city will restart soon - find a safe place to log off.',
}

-- ══════════════════════════════════════════════════════════════
-- INTERIOR / SCRIPT COMPATIBILITY
-- Listens for qb-weathersync / vSync / cd_easytime pause events so housing,
-- apartments and other scripts can freeze weather/time while inside.
-- ══════════════════════════════════════════════════════════════

Config.Compat = {
    pauseEvents = true,
    pausedWeather = 'EXTRASUNNY',
    pausedHour = 12,
}

-- ══════════════════════════════════════════════════════════════
-- ACTIVITY LOG
-- ══════════════════════════════════════════════════════════════

Config.Log = {
    size = 30,                  -- Changes kept in the panel's activity log
    console = true,             -- Also print changes to the server console
    webhook = '',               -- Optional Discord webhook URL for change logs
}

-- ══════════════════════════════════════════════════════════════
-- STORAGE KEY (Don't change unless you know what you're doing)
-- ══════════════════════════════════════════════════════════════

Config.StorageKey = 'nayzeee_worldcontrol:state'
