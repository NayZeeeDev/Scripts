-- ██████╗ ███████╗███████╗██╗ ██████╗ ███╗   ██╗    ██████╗  █████╗ ██╗   ██╗
-- ██╔══██╗██╔════╝██╔════╝██║██╔════╝ ████╗  ██║    ██╔══██╗██╔══██╗╚██╗ ██╔╝
-- ██║  ██║█████╗  ███████╗██║██║  ███╗██╔██╗ ██║    ██████╔╝███████║ ╚████╔╝
-- ██║  ██║██╔══╝  ╚════██║██║██║   ██║██║╚██╗██║    ██╔══██╗██╔══██║  ╚██╔╝
-- ██████╔╝███████╗███████║██║╚██████╔╝██║ ╚████║    ██████╔╝██║  ██║   ██║
-- ╚═════╝ ╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

-- Every part adds build points. Build score (0-100) raises the
-- car's rarity once it passes ScoreToRarity, and adds value on top.
-- Which groups a player can use depends on their Design Bay level.
Config.Workshop = {
    -- 'builtin'  = the design bay menu in this resource (charges per part)
    -- 'external' = your own mechanic script on the car in the bay (it charges, we only read the build)
    -- 'both'     = players choose. Hook your script in bridge/client.lua → Bridge.OpenMechanic
    Mode = 'builtin',

    -- Part prices are multiplied by the car's ORIGINAL rarity.
    CostMult = { common = 1.0, uncommon = 1.25, rare = 1.6, epic = 2.0, legendary = 2.5, mythic = 3.1 },

    -- Build score needed for +1 and +2 rarity (capped by Design Bay level).
    ScoreToRarity = { 40, 75 },

    -- Each build point adds this much to the sale value (0.004 = +0.4%).
    ValuePerPoint = 0.004,

    -- Bonus points when the build is balanced (performance AND style).
    Balance = { perf = 15, style = 15, points = 10 },

    Groups = {
        cosmetic    = { label = 'Cosmetic',    icon = 'fa-solid fa-spray-can' },
        performance = { label = 'Performance', icon = 'fa-solid fa-gauge-high' },
        light       = { label = 'Lighting',    icon = 'fa-solid fa-lightbulb' },
    },

    Parts = {
        -- Performance (level = upgrade stage, points/price are per stage)
        { id = 'engine',       group = 'performance', kind = 'perf',  type = 'level',  mod = 11, max = 4, price = 3000, points = 4, label = 'Engine',       icon = 'fa-solid fa-gears' },
        { id = 'transmission', group = 'performance', kind = 'perf',  type = 'level',  mod = 13, max = 3, price = 2200, points = 3, label = 'Transmission', icon = 'fa-solid fa-code-branch' },
        { id = 'brakes',       group = 'performance', kind = 'perf',  type = 'level',  mod = 12, max = 3, price = 1800, points = 2, label = 'Brakes',       icon = 'fa-solid fa-circle-stop' },
        { id = 'suspension',   group = 'performance', kind = 'perf',  type = 'level',  mod = 15, max = 4, price = 1200, points = 1, label = 'Suspension',   icon = 'fa-solid fa-arrows-up-down' },
        { id = 'armor',        group = 'performance', kind = 'perf',  type = 'level',  mod = 16, max = 5, price = 2400, points = 2, label = 'Armor',        icon = 'fa-solid fa-shield-halved' },
        { id = 'turbo',        group = 'performance', kind = 'perf',  type = 'toggle', mod = 18,          price = 7500, points = 6, label = 'Turbo',        icon = 'fa-solid fa-wind' },

        -- Cosmetic body parts (index = which part, points once if fitted)
        { id = 'spoiler',  group = 'cosmetic', kind = 'style', type = 'part', mod = 0,  price = 1500, points = 2, label = 'Spoiler',      icon = 'fa-solid fa-plane-up' },
        { id = 'fbumper',  group = 'cosmetic', kind = 'style', type = 'part', mod = 1,  price = 1200, points = 2, label = 'Front Bumper', icon = 'fa-solid fa-car' },
        { id = 'rbumper',  group = 'cosmetic', kind = 'style', type = 'part', mod = 2,  price = 1200, points = 2, label = 'Rear Bumper',  icon = 'fa-solid fa-car-rear' },
        { id = 'skirts',   group = 'cosmetic', kind = 'style', type = 'part', mod = 3,  price = 1000, points = 1, label = 'Side Skirts',  icon = 'fa-solid fa-minus' },
        { id = 'exhaust',  group = 'cosmetic', kind = 'style', type = 'part', mod = 4,  price = 900,  points = 1, label = 'Exhaust',      icon = 'fa-solid fa-smog' },
        { id = 'grille',   group = 'cosmetic', kind = 'style', type = 'part', mod = 6,  price = 800,  points = 1, label = 'Grille',       icon = 'fa-solid fa-grip' },
        { id = 'hood',     group = 'cosmetic', kind = 'style', type = 'part', mod = 7,  price = 1400, points = 2, label = 'Hood',         icon = 'fa-solid fa-car-side' },
        { id = 'roof',     group = 'cosmetic', kind = 'style', type = 'part', mod = 10, price = 1100, points = 1, label = 'Roof',         icon = 'fa-solid fa-caret-up' },

        -- Cosmetic specials
        { id = 'paint',  group = 'cosmetic', kind = 'style', type = 'paint',  price = 2500, label = 'Respray',      icon = 'fa-solid fa-fill-drip' },
        { id = 'wheels', group = 'cosmetic', kind = 'style', type = 'wheels', price = 3500, points = 3, label = 'Wheels', icon = 'fa-solid fa-circle-dot' },
        { id = 'tint',   group = 'cosmetic', kind = 'style', type = 'tint',   price = 900,  points = 1, label = 'Window Tint',  icon = 'fa-solid fa-window-maximize' },
        { id = 'livery', group = 'cosmetic', kind = 'style', type = 'livery', price = 2000, points = 3, label = 'Livery',       icon = 'fa-solid fa-palette' },
        { id = 'plate',  group = 'cosmetic', kind = 'style', type = 'plate',  price = 500,  points = 1, label = 'Plate Style',  icon = 'fa-solid fa-id-card' },

        -- Lighting
        { id = 'xenon', group = 'light', kind = 'style', type = 'xenon', price = 1800, points = 2, label = 'Xenon Lights', icon = 'fa-solid fa-lightbulb' },
        { id = 'neon',  group = 'light', kind = 'style', type = 'neon',  price = 3000, points = 3, label = 'Neon Kit',     icon = 'fa-solid fa-bolt' },
    },

    -- Respray finishes (GTA paint types). Points are per finish.
    Finishes = {
        { id = 0, label = 'Classic',       points = 0 },
        { id = 1, label = 'Metallic',      points = 2 },
        { id = 2, label = 'Pearlescent',   points = 4 },
        { id = 3, label = 'Matte',         points = 5 },
        { id = 4, label = 'Brushed Metal', points = 5 },
        { id = 5, label = 'Chrome',        points = 7 },
    },
    TwoTonePoints = 1,   -- different primary and secondary colour

    Colors = {
        { 'Jet Black',      10, 10, 12 },   { 'Graphite',     42, 45, 49 },   { 'Gunmetal',     70, 74, 79 },
        { 'Silver',        170, 174, 178 }, { 'Ice White',   238, 241, 243 }, { 'Race Red',    196, 22, 28 },
        { 'Candy Red',     150, 10, 22 },   { 'Sunset Orange',230, 98, 22 },  { 'Saffron',     232, 170, 20 },
        { 'Lime',          130, 200, 30 },  { 'Racing Green', 18, 74, 44 },   { 'NAYZEEE Teal', 8, 175, 162 },
        { 'Ice Blue',      120, 196, 230 }, { 'Ultra Blue',   20, 70, 190 },  { 'Midnight Blue',16, 24, 60 },
        { 'Royal Purple',   90, 40, 150 },  { 'Hot Pink',    230, 60, 150 },  { 'Champagne',   200, 178, 140 },
        { 'Bronze',        140, 92, 50 },   { 'Desert Tan',  170, 140, 100 }, { 'Olive',        88, 92, 52 },
    },

    -- Pearl tints use GTA colour indexes.
    Pearls = {
        { 0, 'None' }, { 111, 'White Pearl' }, { 70, 'Blue Pearl' }, { 89, 'Gold Pearl' },
        { 28, 'Red Pearl' }, { 145, 'Purple Pearl' }, { 92, 'Lime Pearl' }, { 74, 'Cyan Pearl' },
    },

    WheelTypes = {
        { 0, 'Sport' }, { 1, 'Muscle' }, { 2, 'Lowrider' }, { 3, 'SUV' }, { 4, 'Offroad' },
        { 5, 'Tuner' }, { 7, 'High End' }, { 11, 'Street' }, { 12, 'Track' },
    },
    HighEndWheelBonus = 1,          -- extra point for High End / Track wheels
    CustomTyres = { price = 800, points = 1 },

    -- Rim colours (GTA colour indexes). Works on stock wheels too.
    RimColor  = { price = 600, points = 1 },
    RimColors = {
        { 156, 'Default Alloy' }, { 0, 'Black' }, { 1, 'Graphite' }, { 4, 'Silver' }, { 111, 'White' },
        { 120, 'Chrome' }, { 158, 'Gold' }, { 117, 'Brushed Steel' }, { 28, 'Red' }, { 38, 'Orange' },
        { 89, 'Yellow' }, { 92, 'Lime' }, { 70, 'Blue' }, { 74, 'Cyan' }, { 145, 'Purple' }, { 135, 'Pink' },
    },

    -- Wash & clean from the Design Bay menu (dirt is saved on the car).
    WashPrice = 250,

    Tints = { { 0, 'None' }, { 3, 'Light Smoke' }, { 2, 'Dark Smoke' }, { 1, 'Limo' }, { 5, 'Black' }, { 4, 'Green' } },

    XenonColors = {
        { -1, 'Stock' }, { 0, 'White' }, { 1, 'Blue' }, { 2, 'Electric' }, { 3, 'Mint' }, { 4, 'Lime' },
        { 5, 'Yellow' }, { 6, 'Gold' }, { 7, 'Orange' }, { 8, 'Red' }, { 9, 'Pink' }, { 10, 'Hot Pink' },
        { 11, 'Purple' }, { 12, 'Blacklight' },
    },

    NeonColors = {
        { 'Teal', 8, 175, 162 }, { 'White', 222, 222, 255 }, { 'Electric Blue', 3, 83, 255 },
        { 'Mint', 0, 255, 140 }, { 'Lime', 94, 255, 1 }, { 'Yellow', 255, 255, 0 },
        { 'Orange', 255, 62, 0 }, { 'Red', 255, 1, 1 }, { 'Hot Pink', 255, 5, 190 }, { 'Purple', 35, 1, 255 },
    },

    Plates = { { 0, 'Blue on White 1' }, { 3, 'Blue on White 2' }, { 4, 'Exempt' }, { 1, 'Yellow on Black' }, { 2, 'Yellow on Blue' } },
}
