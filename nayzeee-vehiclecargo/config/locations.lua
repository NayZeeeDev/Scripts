-- ██╗    ██╗ █████╗ ██████╗ ███████╗██╗  ██╗ ██████╗ ██╗   ██╗███████╗███████╗███████╗
-- ██║    ██║██╔══██╗██╔══██╗██╔════╝██║  ██║██╔═══██╗██║   ██║██╔════╝██╔════╝██╔════╝
-- ██║ █╗ ██║███████║██████╔╝█████╗  ███████║██║   ██║██║   ██║███████╗█████╗  ███████╗
-- ██║███╗██║██╔══██║██╔══██╗██╔══╝  ██╔══██║██║   ██║██║   ██║╚════██║██╔══╝  ╚════██║
-- ╚███╔███╔╝██║  ██║██║  ██║███████╗██║  ██║╚██████╔╝╚██████╔╝███████║███████╗███████║
--  ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝╚══════╝╚══════╝

-- The warehouses players can buy from the broker.
--
-- On the FIRST start these are copied into the database. After that you
-- manage them in game: /cargoadmin → Locations (add, move, delete). If
-- you change coords here later, press "Import from config" in that tab
-- (same name = updated, new name = added).
--
-- Every warehouse has four points, all vec4(x, y, z, heading):
--
--   frontDoor  Where players walk up on foot to Enter or Knock.
--              Heading = the way you face when looking AT the door.
--   garageIn   Drive a sourced car here to store it.
--   garageOut  Where you come out when you pick "Leave through the garage".
--              Heading = the way you face when you come out.
--   saleSpawn  Where the car you are selling is waiting for you.
--              Heading = the way the car points (face the road).
Config.SeedWarehouses = {
    {
        name      = 'Elysian Island',
        price     = 1250000,
        frontDoor = vec4(-338.57, -2444.65, 7.30, 232.5),
        garageIn  = vec4(-336.29, -2438.27, 5.50, 231.2),
        garageOut = vec4(-336.09, -2438.41, 6.00, 50.0),
        saleSpawn = vec4(-334.00, -2433.19, 5.50, 316.4),
    },
    {
        name      = 'Terminal',
        price     = 1100000,
        frontDoor = vec4(1240.10, -3322.06, 6.03, 81.7),
        garageIn  = vec4(1233.88, -3329.46, 5.11, 359.3),
        garageOut = vec4(1233.33, -3326.01, 5.53, 188.2),
        saleSpawn = vec4(1226.57, -3330.61, 5.53, 175.7),
    },
    {
        name      = 'LSIA Hangar',
        price     = 1450000,
        frontDoor = vec4(-1454.33, -3257.49, 14.06, 153.9),
        garageIn  = vec4(-1461.18, -3250.49, 13.44, 149.6),
        garageOut = vec4(-1462.74, -3252.13, 13.94, 145.79),
        saleSpawn = vec4(-1470.46, -3245.39, 13.44, 330.8),
    },
    {
        name      = 'Sandy Airfield',
        price     = 850000,
        frontDoor = vec4(1776.11, 3327.27, 41.43, 122.4),
        garageIn  = vec4(1758.78, 3327.18, 40.85, 294.2),
        garageOut = vec4(1764.55, 3320.40, 41.42, 296.7),
        saleSpawn = vec4(1781.85, 3328.28, 40.76, 210.5),
    },
}

-- ██╗███╗   ██╗████████╗███████╗██████╗ ██╗ ██████╗ ██████╗
-- ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██║██╔═══██╗██╔══██╗
-- ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝██║██║   ██║██████╔╝
-- ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██║██║   ██║██╔══██╗
-- ██║██║ ╚████║   ██║   ███████╗██║  ██║██║╚██████╔╝██║  ██║
-- ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═╝

-- Uses GTA's Import/Export vehicle warehouse. Every owner gets their
-- own copy through routing buckets, so nobody sees anyone else.
-- The interior has its own stairs down to the lower level, so there are
-- no teleport points: players just walk down. Every point below can be
-- placed in game with /cargoslots (saved to the database, overrides these).
-- Run it once on your server.
Config.Interior = {
    Ipl      = 'imp_impexp_interior_placement_interior_1_impexp_intwaremed_milo_',
    Coords   = vec3(994.5925, -3002.594, -39.64699),
    Entry    = vec4(970.88, -2987.89, -39.65, 23.5),   -- where you appear on foot
    Exit     = vec4(970.88, -2987.89, -39.65, 337.9),    -- front door (inside), third-eye here to leave
    Laptop   = vec4(965.69, -3005.48, -39.81,  89.9),   -- laptop on the office desk (prop position)
    Design   = vec4(955.90, -2995.55, -39.65, 355.4),   -- design bay car spot in the back
    DesignCam = { distance = 6.2, height = 1.4, fov = 42.0 },

    -- The open floor cars can park on (two opposite corners) and the props to keep clear of.
    -- These are a starting point: fit them to your interior with /cargoslots → Floor area / Add obstacle.
    Floor = {
        Min = vec2(969.0, -3017.0),
        Max = vec2(1019.0, -2992.0),
        Z   = -39.65,
        Obstacles = {
            { Min = vec2(962.0, -3011.0), Max = vec2(969.5, -2998.0) },   -- office desk / laptop
            { Min = vec2(965.0, -2993.5), Max = vec2(977.0, -2984.0) },   -- front door walkway
        },
    },
    ExtraSets = { 'car_floor_hatch' },

    -- Downstairs floor for illegal vehicles (Lower Level upgrade).
    Lower = {
        Ipl     = 'imp_impexp_interior_placement_interior_3_impexp_int_02_milo_',
        Coords  = vec3(969.5376, -3000.411, -48.64689),
        SplitZ  = -44.0,   -- anything below this height counts as downstairs (locked until the upgrade)
        Slots   = {
            vec4(972.0, -3006.0, -48.65, 0.0),
            vec4(976.0, -3006.0, -48.65, 0.0),
            vec4(972.0, -2995.0, -48.65, 180.0),
            vec4(976.0, -2995.0, -48.65, 180.0),
        },
    },
}

-- ██████╗ ██████╗ ███████╗███████╗███████╗████████╗███████╗
-- ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
-- ██████╔╝██████╔╝█████╗  ███████╗█████╗     ██║   ███████╗
-- ██╔═══╝ ██╔══██╗██╔══╝  ╚════██║██╔══╝     ██║   ╚════██║
-- ██║     ██║  ██║███████╗███████║███████╗   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚══════╝

-- Main floor layouts. Presets are generated INSIDE the floor area below and
-- skip anything listed in Obstacles, so cars never clip walls or the props
-- that dress the warehouse. Set both in game with /cargoslots (Interior tab:
-- Floor area / Add obstacle): walk to two opposite corners and press E.
--
-- pattern  rows    = rows facing each other across an aisle
--          angled  = the same rows, parked at an angle
--          packed  = side-on storage, tight
--          island  = rings around the middle of the floor
-- spacing  = gap between cars in a row (m)    max = most spots it may make
Config.LayoutPresets = {
    { id = 'rows',   label = 'Showroom Rows',  pattern = 'rows',   spacing = 3.8, max = 24 },
    { id = 'angled', label = 'Angled Bays',    pattern = 'angled', spacing = 4.4, angle = 35.0, max = 20 },
    { id = 'packed', label = 'Packed Storage', pattern = 'packed', spacing = 3.0, aisle = 6.5, max = 32 },
    { id = 'island', label = 'Center Island',  pattern = 'island', max = 18 },
}
Config.DefaultPreset = 'rows'

-- ███████╗ ██████╗ ██╗   ██╗██████╗  ██████╗██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔════╝██║████╗  ██║██╔════╝
-- ███████╗██║   ██║██║   ██║██████╔╝██║     ██║██╔██╗ ██║██║  ███╗
-- ╚════██║██║   ██║██║   ██║██╔══██╗██║     ██║██║╚██╗██║██║   ██║
-- ███████║╚██████╔╝╚██████╔╝██║  ██║╚██████╗██║██║ ╚████║╚██████╔╝
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Each scenario rolls a spot from its list. Use /cargocoords in game
-- to copy your current position as a vec4 and paste it in here.
Config.SourceSpots = {

    -- Locked on the street. Break in.
    parked = {
        vec4(269.7161, -322.4464, 44.9198, 160.0),
        vec4(-341.7936, -756.7662, 33.9693, 91.7174),
        vec4(-1187.0695, -743.3262, 19.7007, 309.0180),
        vec4(60.7660, 17.7658, 68.8323, 158.7327),
        vec4(-457.6603, -770.0623, 30.1506, 88.8409),
        vec4(374.9304, 282.9839, 102.7657, 337.8876),
        vec4(-760.5837, -2059.8071, 8.4850, 314.2055),
        vec4(-1190.0081, -1485.3090, 3.9676, 123.7720),
        vec4(1111.5582, 2654.2161, 37.5846, 269.0361),
        vec4(1703.9255, 3764.5459, 33.9457, 315.2863),
        vec4(17.5948, 6508.2632, 31.0799, 222.0852),
        vec4(-610.1690, 201.3154, 70.9098, 182.4454),
    },

    -- Guests around the car. Aim at them, then search each one for the keys.
    party = {
        vec4(-1550.5348, 131.1414, 56.3731, 137.9446),
        vec4(438.1130, 221.8374, 102.7534, 249.0576),
        vec4(-872.5173, -55.0522, 37.8413, 297.8922),
        vec4(-1662.5521, -887.5636, 8.2799, 320.0066),
        vec4(-3249.5435, 987.6332, 12.0736, 2.1557),
        vec4(-3019.0693, 739.3127, 27.1141, 110.2077),
        vec4(-2978.2043, 81.6708, 11.1005, 150.3819),
    },

    -- Guards around the car. The one holding the keys drops them.
    guarded = {
        vec4(1737.6685, -1537.0938, 112.2723, 245.8903),
        vec4(2434.7571, -371.4621, 92.5807, 268.5216),
        vec4(59.3767, 3717.8340, 39.3387, 148.5693),
        vec4(-2422.1179, 3297.5151, 32.4179, 240.7655),
        vec4(-1750.4471, 2878.5923, 32.3951, 329.6003),
        vec4(983.0790, -1238.7473, 24.9318, 302.5575),
    },

    -- Someone is driving it. Stop them.
    moving = {
        vec4(975.4044, -453.0501, 62.0887, 214.5558),
        vec4(916.2023, -627.8360, 57.6368, 320.8639),
        vec4(1254.5938, -625.2199, 68.9394, 298.0315),
        vec4(-60.6272, 332.9229, 110.7498, 155.2477),
        vec4(-72.9822, 147.1562, 80.9414, 123.8685),
        vec4(474.0122, -1571.4637, 28.7117, 228.1870),
    },

    -- Locked in a guarded lot. Break in.
    impound = {
        vec4(401.76, -1632.57, 29.29, 228.0),
        vec4(409.25, -1623.08, 29.29, 230.0),
        vec4(452.50, -1018.00, 28.40, 90.0),
    },

    -- Car parked on the street, the owner walks around it. Sneak up behind him.
    pickpocket = {
        vec4(222.02, -804.19, 30.60, 248.0),
        vec4(-1183.10, -1511.11, 4.36, 304.0),
        vec4(364.37, 297.83, 103.49, 340.0),
        vec4(1737.03, 3718.88, 34.05, 21.2),
        vec4(-796.86, -2024.85, 8.88, 50.5),
    },

    -- Somewhere quiet. The armed owner (and maybe friends) wait by the car.
    hostile = {
        vec4(2436.50, 4966.00, 46.80, 45.0),
        vec4(1182.00, -3105.00, 5.90, 90.0),
        vec4(1120.00, 2650.00, 38.00, 0.0),
        vec4(-570.00, 5250.00, 70.50, 150.0),
        vec4(-411.60, 1173.30, 325.60, 165.0),
    },

    -- car   = where the dead car sits
    -- depot = where the flatbed is parked (guarded)
    tow = {
        { car = vec4(-330.01, -780.33, 33.96, 37.6),  depot = vec4(408.40, -1638.30, 29.30, 228.0) },
        { car = vec4(1137.77, 2663.54, 37.90, 0.0),   depot = vec4(1730.00, 3310.00, 41.20, 195.0) },
        { car = vec4(78.34, 6418.74, 31.28, 225.0),   depot = vec4(110.00, 6626.00, 31.80, 225.0) },
    },

    -- car = where the stranded car sits
    -- pad = where the Cargobob is parked (guarded)
    cargobob = {
        { car = vec4(501.80, 5604.30, 797.90, 175.0), pad = vec4(1770.24, 3239.85, 42.12, 105.0) },
        { car = vec4(711.36, 1198.13, 348.52, 180.0), pad = vec4(-1145.95, -2864.39, 13.95, 150.0) },
        { car = vec4(-411.60, 1173.30, 325.60, 165.0), pad = vec4(-1112.43, -2883.88, 13.95, 150.0) },
    },

    -- Crew jobs: one guarded lot, the cars park side by side across it (4.2m apart).
    -- Pick wide open spots; the heading is the way the cars face.
    crew = {
        vec4(1737.6685, -1537.0938, 112.2723, 245.8903),
        vec4(2434.7571, -371.4621, 92.5807, 268.5216),
        vec4(983.0790, -1238.7473, 24.9318, 302.5575),
        vec4(-1750.4471, 2878.5923, 32.3951, 329.6003),
    },

}

-- Tracker removal points (LS Customs style garages).
Config.TrackerShops = {
    vec3(-337.39, -136.92, 39.00),
    vec3(731.81, -1088.82, 22.17),
    vec3(-1155.54, -2007.18, 13.18),
    vec3(1175.04, 2640.22, 37.75),
    vec3(110.99, 6626.39, 31.79),
}

-- ██████╗ ██████╗  ██████╗ ██████╗  ██████╗ ███████╗███████╗███████╗
-- ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔═══██╗██╔════╝██╔════╝██╔════╝
-- ██║  ██║██████╔╝██║   ██║██████╔╝██║   ██║█████╗  █████╗  ███████╗
-- ██║  ██║██╔══██╗██║   ██║██╔═══╝ ██║   ██║██╔══╝  ██╔══╝  ╚════██║
-- ██████╔╝██║  ██║╚██████╔╝██║     ╚██████╔╝██║     ██║     ███████║
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝      ╚═════╝ ╚═╝     ╚═╝     ╚══════╝

-- Where buyers wait when you deliver a car you are selling.
-- Every drop has:
--   name   = shown on the GPS and in the HUD ("Galileo Observatory")
--   area   = the part of the map it is in, only to help you find it
--   coords = vec4(x, y, z, heading) where the buyer stands / the car is parked
--
-- Distance decides which buyer goes where: from the warehouse you sell
-- from, the closest third are 'near' drops (Private Collector), the
-- middle third 'mid' (Showroom), the farthest third 'far' (Specialist).
-- Drops closer than Config.Selling.MinDropDistance are skipped.
-- Add or remove as many as you like.
Config.Dropoffs = {

    -- ── City ──────────────────────────────────────────────────
    { name = 'Pillbox',              area = 'Pillbox Hill',          coords = vec4(-315.9627, -754.0381, 52.8355, 158.4967) },
    { name = 'Vinewood Blvd',        area = 'Vinewood',              coords = vec4(121.2678, 287.8327, 109.5618, 67.5479) },
    { name = 'Prosperity Street',    area = 'Prosperity Street',     coords = vec4(-1536.2242, -411.4684, 41.5790, 51.6474) },
    { name = 'Little Seoul',         area = 'Little Seoul',          coords = vec4(-1241.9648, -651.4003, 39.9455, 309.8896) },
    { name = 'Vespucci Beach',       area = 'Vespucci Beach',        coords = vec4(-1153.0031, -1523.4938, 3.8845, 217.5233) },
    { name = 'La Puerta',            area = 'La Puerta',             coords = vec4(-907.7451, -2045.2261, 8.8870, 222.1337) },
    { name = 'Galileo Observatory',  area = 'Vinewood Hills',        coords = vec4(-385.1608, 1206.7343, 325.2299, 96.2236) },


    -- ── Mansion Drops ─────────────────────────────────────────
    { name = 'Kimble Hill Drive',        area = 'Kimble Hill',        coords = vec4(-144.5112, 596.3845, 203.3488, 188.3122) },
    { name = 'Kimble Hill Drive 2',      area = 'Kimble Hill',        coords = vec4(-464.0255, 643.4723, 143.7767, 224.6566) },
    { name = 'Milton Road',              area = 'Milton Road',        coords = vec4(-485.6258, 597.5713, 125.8613, 268.5306) },
    { name = 'Didion Drive',             area = 'Didion Drive',       coords = vec4(-410.4890, 557.2405, 123.6050, 332.7062) },
    { name = 'Didion Drive 2',           area = 'Didion Drive',       coords = vec4(-352.3310, 475.5225, 112.3673, 109.0619) },
    { name = 'Cox Way',                  area = 'Cox Way',            coords = vec4(-394.9613, 431.4686, 111.9296, 66.1641) },
    { name = 'Picture Perfect Drive',    area = 'Picture Perfect',   coords = vec4(-585.1451, 526.7811, 107.1177, 37.7854) },
    { name = 'Picture Perfect Drive 2',  area = 'Picture Perfect',   coords = vec4(-736.4638, 444.3224, 106.4630, 202.8679) },
    { name = 'South Mo Milton Drive',    area = 'South Mo Milton',   coords = vec4(-908.9360, 555.1242, 96.0553, 138.5718) },
    { name = 'South Mo Milton Drive 2',  area = 'South Mo Milton',   coords = vec4(-913.1284, 585.6471, 100.3754, 326.4801) },
    { name = 'Ace Jones Drive',          area = 'Ace Jones Drive',    coords = vec4(-1471.5425, 512.0820, 117.3427, 188.2943) },
    { name = 'Ace Jones Drive 2',        area = 'Ace Jones Drive',    coords = vec4(-1806.4036, 456.7248, 127.8717, 267.1769) },
    { name = 'North Rockford Drive',     area = 'North Rockford',     coords = vec4(-1954.2197, 448.2976, 100.5998, 189.0427) },
    { name = 'North Rockford Drive 2',   area = 'North Rockford',     coords = vec4(-2001.6289, 368.5290, 94.0715, 184.0640) },
    { name = 'North Rockford Drive 3',   area = 'North Rockford',     coords = vec4(-1992.2056, 293.7635, 91.3543, 15.9716) },
    { name = 'North Rockford Drive 4',   area = 'North Rockford',     coords = vec4(-1905.7600, 241.9786, 85.8412, 209.1760) },
    { name = 'Americana Way',            area = 'Americana Way',       coords = vec4(-1569.1647, 31.9947, 58.7076, 256.9080) },
    { name = 'Lake Vinewood Estates',    area = 'Lake Vinewood',       coords = vec4(-123.6041, 997.5523, 235.3342, 19.0503) },


    -- ── Hotel Drops ────────────────────────────────────────────
    { name = 'Hotel Drop 1', area = 'Los Santos Hotel District', coords = vec4(-1219.0876, -188.8829, 38.7638, 353.7164) },
    { name = 'Hotel Drop 2', area = 'Los Santos Hotel District', coords = vec4(-1286.1243, -427.7830, 34.3593, 212.0852) },
    { name = 'Hotel Drop 3', area = 'Los Santos Hotel District', coords = vec4(322.8345, -87.8499, 68.4493, 67.7787) },
    { name = 'Hotel Drop 4', area = 'Los Santos Hotel District', coords = vec4(438.2042, 222.3584, 102.7533, 250.1384) },
    { name = 'Hotel Drop 5', area = 'Los Santos Hotel District', coords = vec4(-1286.1267, 292.2704, 64.4057, 57.9470) },
    { name = 'Hotel Drop 6', area = 'Los Santos Hotel District', coords = vec4(-1627.6895, -522.2086, 34.1822, 49.8502) },

    -- ── County ────────────────────────────────────────────────
    { name = 'Harmony Gas Station',    area = 'Harmony',         coords = vec4(1137.77, 2663.54, 37.90, 0.0) },
    { name = 'Alamo Sea Shack',        area = 'Alamo Sea',       coords = vec4(883.96, 3649.67, 32.87, 92.0) },
    { name = 'Sandy Shores Yard',      area = 'Sandy Shores',    coords = vec4(1737.03, 3718.88, 34.05, 21.2) },
    { name = 'Grapeseed Farm Road',    area = 'Grapeseed',       coords = vec4(2552.68, 4671.80, 33.95, 15.0) },
    { name = 'Paleto Bay Back Lot',    area = 'Paleto Bay',      coords = vec4(129.5193, 6663.2915, 31.3279, 135.1398) },
}

--  ██████╗██╗  ██╗ ██████╗ ██████╗     ███████╗██╗  ██╗ ██████╗ ██████╗ ███████╗
-- ██╔════╝██║  ██║██╔═══██╗██╔══██╗    ██╔════╝██║  ██║██╔═══██╗██╔══██╗██╔════╝
-- ██║     ███████║██║   ██║██████╔╝    ███████╗███████║██║   ██║██████╔╝███████╗
-- ██║     ██╔══██║██║   ██║██╔═══╝     ╚════██║██╔══██║██║   ██║██╔═══╝ ╚════██║
-- ╚██████╗██║  ██║╚██████╔╝██║         ███████║██║  ██║╚██████╔╝██║     ███████║
--  ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝         ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝

-- Chop a car for cash instead of storing it.
Config.ChopShops = {
    vec3(-196.3274, 6270.2358, 31.0774),
    vec3(-424.5636, -1687.6467, 18.6171),
    vec3(2341.8918, 3052.2563, 47.7398),
    vec3(1564.4103, -2163.7969, 77.1262),
}

-- ██████╗ ██████╗  ██████╗ ██╗  ██╗███████╗██████╗ ███████╗
-- ██╔══██╗██╔══██╗██╔═══██╗██║ ██╔╝██╔════╝██╔══██╗██╔════╝
-- ██████╔╝██████╔╝██║   ██║█████╔╝ █████╗  ██████╔╝███████╗
-- ██╔══██╗██╔══██╗██║   ██║██╔═██╗ ██╔══╝  ██╔══██╗╚════██║
-- ██████╔╝██║  ██║╚██████╔╝██║  ██╗███████╗██║  ██║███████║
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝

-- Seed positions for the NPCs that sell warehouses.
-- Move or add more in game: /cargoadmin → Broker.
Config.SeedBrokers = {
    vec4(4.75, -706.32, 44.97, 205.7),
}
