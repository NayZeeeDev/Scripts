--[[
    nayzeee-weedlab | main configuration (shared: client + server)

    Everything here is visible to clients. Secrets (webhook) go in config/server.lua.

    Other config files:
      config/strains.lua    strains, quality, effects, mixing ingredients
      config/equipment.lua  placeables, props, growing, lights, processing, first person steps
      config/shop.lua       hardware store catalogue + every item the script uses

    Coordinates marked "rough" are outdoor spots picked from the map. Peds and props snap
    to the ground, but check them once in game: stand where you want something and run
    /nzwlcoords to copy a vec4(...).
]]

Config = {}

Config.Debug = false

--[[ Integrations ('auto' detects the running resource) ]]
Config.Framework   = 'auto' -- 'auto' | 'qbx' | 'qb' | 'esx'
Config.Inventory   = 'auto' -- 'auto' | 'ox' | 'qb' | 'qs' | 'codem' | 'framework'
Config.Target      = 'auto' -- 'auto' | 'ox' | 'qb' | 'none'  ('none' = built-in [E] prompts)
Config.Dispatch    = 'auto' -- 'auto' | 'ps' | 'cd' | 'qs' | 'rcore' | 'lb' | 'builtin' | 'none'
Config.VehicleKeys = 'auto' -- 'auto' | 'qbx' | 'qb' | 'wasabi' | 'mk' | 'renewed' | 'none'
Config.Notify      = 'nui'  -- 'nui' | 'ox' | 'framework'

Config.Money = {
    shopAccounts = { 'cash', 'bank' }, -- what the hardware store and lab purchases take (first = default)
}

Config.Police = {
    jobs = { 'police', 'sheriff', 'state', 'bcso', 'sasp' },
    onDutyOnly = true,
    forbidden = true,   -- police can't start the story
    alertBlip = { sprite = 51, color = 1, scale = 1.0, radius = 80.0, duration = 90 }, -- builtin dispatch only
}

--[[ ─────────────────────────────── UNCLE BENSON ───────────────────────────────
    The production starts when a player finds Benson. He has no blip: players have to
    find him. With rotate = true he moves to a random spot from the list every time the
    resource (server) starts. Everybody sees him at the same spot.
]]
Config.Benson = {
    name = 'Uncle Benson',
    model = 'a_m_o_genstreet_01',
    wheelchair = 'prop_wheelchair_01',
    seat = { offset = vec3(0.0, 0.05, 0.42), scenario = 'PROP_HUMAN_SEAT_ARMCHAIR' },
    rotate = true,      -- new spot every server restart. false = always spots[fixed]
    fixed = 1,
    spots = {           -- rough
        vec4(2340.84, 3126.29, 48.21, 350.0),   -- Joshua Rd scrapyard
        vec4(1543.71, 3592.47, 35.36, 300.0),   -- derelict motel, Route 68
        vec4(724.36, -1088.00, 22.17, 90.0),    -- La Mesa, behind the warehouses
        vec4(-1149.43, -1990.16, 13.16, 135.0), -- LSIA, back of the body shop
        vec4(-427.81, 6153.35, 31.48, 315.0),   -- Paleto Bay back yard
        vec4(1531.25, 6324.95, 24.08, 60.0),    -- Paleto forest camp
    },
    talkDistance = 2.2,
    hint = false,       -- true: new players get a vague "find Uncle Benson" hint on the HUD
}

--[[ ─────────────────────────────── THE RV JOB ───────────────────────────────
    Benson sends you to steal an RV from a heavily guarded Ballas crew. Lose the Ballas
    (get escapeDistance away from the spot) and the RV is yours. One spot is picked per player.
]]
Config.Story = {
    rv = {
        model = 'journey',
        spots = {       -- placeholders around Grove Street, set the real ones when testing
            { vehicle = vec4(105.86, -1939.92, 20.80, 50.0),  label = 'Grove Street' },
            { vehicle = vec4(86.40, -1966.20, 20.75, 320.0),  label = 'Grove Street, by the courts' },
            { vehicle = vec4(127.60, -1929.40, 20.65, 120.0), label = 'Grove Street, east end' },
        },
        -- guard positions relative to the RV (x right, y forward, heading relative)
        guards = {
            vec4(-3.5, 2.0, 0.0, 120.0), vec4(3.6, 1.0, 0.0, 250.0), vec4(-2.8, -4.6, 0.0, 200.0), vec4(3.0, -5.2, 0.0, 160.0),
            vec4(0.0, 7.5, 0.0, 0.0), vec4(-6.5, -1.0, 0.0, 90.0), vec4(6.8, -2.0, 0.0, 270.0), vec4(-1.0, -9.0, 0.0, 180.0),
        },
        guardModels = { 'g_m_y_ballaeast_01', 'g_m_y_ballaorig_01', 'g_m_y_ballasout_01', 'g_f_y_ballas_01' },
        guardWeapons = { 'WEAPON_PISTOL', 'WEAPON_MICROSMG', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_PISTOL50' },
        guardAccuracy = 35,
        guardArmour = 60,
        spawnDistance = 200.0,  -- guards spawn when you get this close
        escapeDistance = 350.0, -- lose the Ballas: get this far from the spot in the RV
        wantedLevel = 0,        -- wanted level when the RV is taken (0 = off)
        alertChance = 60,       -- % chance police get a dispatch call when the RV is taken
        blip = { sprite = 67, color = 27, scale = 0.9, label = 'Ballas RV' },
    },

    -- after the RV: Benson's seeds wait in a dead drop
    deadDrop = {
        seed = 'nzw_seed_ogkush',
        seeds = { 2, 3 },        -- random between
        prop = 'prop_cs_package_01',
        searchSeconds = 6,
        spots = {               -- rough
            vec4(1131.57, -989.45, 46.11, 98.0),    -- Mirror Park, behind the shops
            vec4(-1271.30, -1385.20, 4.30, 110.0),  -- Vespucci canals
            vec4(1201.92, -3114.80, 5.54, 0.0),     -- Elysian Island docks
            vec4(-55.40, -1218.20, 28.70, 270.0),   -- Strawberry, under the bridge
        },
        blip = { sprite = 501, color = 2, scale = 0.85, label = 'Dead drop' },
    },
    starterCash = 0,            -- cash Benson slips you with the seeds (0 = none)
}

--[[ ─────────────────────────────── HARDWARE STORES ─────────────────────────────── ]]
Config.Stores = {
    { label = 'You Tool',        ped = vec4(2748.29, 3472.48, 55.68, 245.0), model = 's_m_m_autoshop_02' },
    { label = 'Mega Mall Hardware', ped = vec4(46.60, -1749.60, 29.63, 50.0), model = 's_m_m_autoshop_01' },
    { label = 'Paleto Hardware', ped = vec4(-11.20, 6499.20, 31.50, 45.0),   model = 's_m_m_autoshop_02' },
}
Config.StoreBlip = { sprite = 566, color = 25, scale = 0.75, label = 'Hardware store' }

--[[ ─────────────────────────────── LABS ───────────────────────────────
    Three places to grow, unlocked by level. Inside a lab every player is in their own
    routing bucket, so nobody sees anybody else's lab even though the interior is shared.

    bounds = placement box relative to `origin` (min / max corner)
    tap    = where the watering can is filled (relative)
    maxGrow = pots + tents, maxObjects = everything placed
]]
Config.Labs = {
    rv = {
        label = 'RV', level = 0, icon = 'rv',
        maxGrow = 3, maxObjects = 10,
        interior = 'auto',     -- 'auto' (shell if streamed) | 'shell' | 'ipl'
        shell = {              -- K4MB1 shell_trevor (optional, empty inside)
            model = 'shell_trevor',
            origin = vec3(-1450.0, -3500.0, -60.0),
            spawn = vec4(0.25, -3.1, 1.45, 0.0),
            exit = vec3(0.25, -3.48, 1.45),
            bounds = { min = vec3(-2.6, -3.6, 0.0), max = vec3(2.6, 3.8, 2.6) },
            floor = 0.05,
            tap = vec3(-2.4, 1.6, 1.0),
        },
        ipl = {                -- Trevor's trailer (base game)
            origin = vec3(1973.21, 3816.68, 32.43),
            ipls = { request = { 'TrevorsTrailerTidy' }, remove = { 'TrevorsTrailerTrash', 'TrevorsTrailer' } },
            spawn = vec4(0.65, -3.35, 1.0, 30.0),
            exit = vec3(0.6, -3.65, 1.0),
            bounds = { min = vec3(-2.2, -4.2, -0.2), max = vec3(2.6, 4.2, 2.6) },
            floor = 0.0,
            tap = vec3(-1.25, 1.95, 1.0),
        },
    },

    small = {
        label = 'Small Warehouse', level = 6, price = 85000, icon = 'warehouse',
        maxGrow = 12, maxObjects = 30,
        interior = {           -- CEO small warehouse (base game)
            origin = vec3(1094.99, -3101.78, -39.00),
            spawn = vec4(1088.10, -3099.40, -39.00, 270.0),
            exit = vec3(1087.45, -3099.35, -39.00),
            bounds = { min = vec3(-8.5, -5.0, -0.5), max = vec3(10.5, 5.5, 4.0) },
            floor = 0.0,
            tap = vec3(-6.4, 4.4, 1.0),
        },
        entrances = {          -- rough: the door players walk up to
            { label = 'Del Perro',     door = vec4(-1081.06, -1262.33, 5.60, 210.0) },
            { label = 'Cypress Flats', door = vec4(924.00, -1560.60, 30.80, 90.0) },
            { label = 'Paleto Bay',    door = vec4(-424.20, 6136.40, 31.50, 45.0) },
        },
    },

    warehouse = {
        label = 'Weed Warehouse', level = 15, price = 275000, icon = 'warehouse',
        maxGrow = 40, maxObjects = 90,
        interior = {           -- biker weed farm (base game), emptied
            origin = vec3(1051.49, -3196.54, -39.15),
            spawn = vec4(1065.60, -3183.40, -39.16, 90.0),
            exit = vec3(1066.30, -3183.40, -39.16),
            bounds = { min = vec3(-19.5, -12.5, -0.5), max = vec3(17.5, 16.5, 5.0) },
            floor = 0.0,
            tap = vec3(12.8, 14.2, 1.0),
            -- every set below is switched off on entry so the farm is empty
            entitySetsOff = {
                'weed_drying', 'weed_production', 'weed_set_up', 'weed_standard_equip', 'weed_upgrade_equip',
                'weed_security_upgrade', 'weed_low_security', 'weed_chairs',
                'weed_growtha_stage1', 'weed_growtha_stage2', 'weed_growtha_stage3', 'weed_growthb_stage1', 'weed_growthb_stage2', 'weed_growthb_stage3',
                'weed_growthc_stage1', 'weed_growthc_stage2', 'weed_growthc_stage3', 'weed_growthd_stage1', 'weed_growthd_stage2', 'weed_growthd_stage3',
                'weed_growthe_stage1', 'weed_growthe_stage2', 'weed_growthe_stage3', 'weed_growthf_stage1', 'weed_growthf_stage2', 'weed_growthf_stage3',
                'weed_growthg_stage1', 'weed_growthg_stage2', 'weed_growthg_stage3', 'weed_growthh_stage1', 'weed_growthh_stage2', 'weed_growthh_stage3',
                'weed_growthi_stage1', 'weed_growthi_stage2', 'weed_growthi_stage3',
                'weed_hosea', 'weed_hoseb', 'weed_hosec', 'weed_hosed', 'weed_hosee', 'weed_hosef', 'weed_hoseg', 'weed_hoseh', 'weed_hosei',
                'light_growtha_stage23_standard', 'light_growthb_stage23_standard', 'light_growthc_stage23_standard', 'light_growthd_stage23_standard',
                'light_growthe_stage23_standard', 'light_growthf_stage23_standard', 'light_growthg_stage23_standard', 'light_growthh_stage23_standard',
                'light_growthi_stage23_standard',
                'light_growtha_stage23_upgrade', 'light_growthb_stage23_upgrade', 'light_growthc_stage23_upgrade', 'light_growthd_stage23_upgrade',
                'light_growthe_stage23_upgrade', 'light_growthf_stage23_upgrade', 'light_growthg_stage23_upgrade', 'light_growthh_stage23_upgrade',
                'light_growthi_stage23_upgrade',
            },
            entitySetsOn = {},
        },
        entrances = {          -- rough
            { label = 'Vinewood',      door = vec4(102.06, 175.60, 104.60, 160.0) },
            { label = 'Grand Senora',  door = vec4(2847.90, 4450.30, 48.50, 105.0) },
            { label = 'La Puerta',     door = vec4(-1171.00, -1381.00, 4.90, 30.0) },
        },
    },
}
Config.LabOrder = { 'rv', 'small', 'warehouse' }

Config.Buckets = { base = 7700 }   -- routing bucket = base + server id while inside a lab

--[[ the RV out in the world ]]
Config.RV = {
    model = 'journey',
    platePrefix = 'NZW',
    entryOffset = vec3(1.35, -0.9, 0.0),   -- the side door of the Journey (right side)
    entryRadius = 1.6,
    lockWhileInside = true,
    towFee = 750,
    towLots = {                             -- rough
        vec4(1981.93, 3779.24, 32.18, 210.0),
        vec4(150.83, 6602.17, 31.85, 180.0),
        vec4(1176.55, 2657.34, 37.81, 90.0),
        vec4(-337.08, -1513.12, 27.53, 270.0),
    },
    blip = { sprite = 67, color = 2, scale = 0.8, label = 'Your RV' },
}
Config.LabBlip = { sprite = 473, color = 2, scale = 0.8 }

--[[ ─────────────────────────────── LEVELS ───────────────────────────────
    Players start at level 0. XP for the next level = base + level * step.
    Unlocks (equipment, strains, labs, store items) carry their own `level`.
]]
Config.Levels = {
    max = 40,
    base = 300,
    step = 140,
    titles = {             -- { from level, title }
        { 0, 'Seedling' }, { 3, 'Sprout' }, { 6, 'Grower' }, { 10, 'Cultivator' }, { 15, 'Botanist' },
        { 20, 'Master Grower' }, { 28, 'Kingpin' }, { 35, 'Mastermind' },
    },
    xp = {
        rv = 250,              -- story: RV stolen and the Ballas lost
        deaddrop = 100,        -- story: seeds collected
        harvest = 30,          -- per plant
        perBud = 4,            -- + per bud trimmed
        pack = 3,              -- per baggie / jar
        dry = 2,               -- per unit dried
        mix = 60,              -- new product discovered
        mixUnit = 1,           -- per unit mixed
        brick = 45,            -- per brick pressed
    },
}

--[[ ─────────────────────────────── SELLING ───────────────────────────────
    Corner sales: /sellweed (or the key) turns selling on. Walk up to people on the street
    and offer them baggies or jars. Price = product value x quality x a little haggling.
    Bulk: a buyer takes pressed bricks (level gated, a few per day).
]]
Config.Selling = {
    account = 'cash',              -- 'cash' | 'bank' | 'black_money' | 'markedbills' | 'item'
    item = 'cash',                 -- when account = 'item'
    markedbillsItem = 'markedbills',
    minPolice = 0,                 -- cops on duty needed to sell
    quality = { [0] = 0.5, [1] = 0.75, [2] = 1.0, [3] = 1.3, [4] = 1.7 },  -- price multiplier per quality

    corner = {
        enabled = true,
        command = 'sellweed', key = 'G',     -- toggles selling mode (key false = command only)
        radius = 2.2,                        -- how close a person has to be
        cooldown = 7,                        -- seconds between offers
        remember = 900,                      -- seconds before the same person buys again
        wants = { nzw_baggie = { 1, 3 }, nzw_jar = { 1, 1 } }, -- how many a customer takes
        accept = { base = 0.55, perQuality = 0.1, min = 0.15, max = 0.92 },
        haggle = { 0.9, 1.15 },
        alertChance = 25,                    -- % a refusal turns into a call to the police
        xpPerUnit = 4,
    },

    bulk = {
        enabled = true,
        level = 12,
        label = 'Leon',
        model = 'g_m_m_armboss_01',
        ped = vec4(1240.50, -3168.30, 7.10, 270.0),   -- placeholder: Elysian Island docks
        blip = { sprite = 500, color = 2, scale = 0.75, label = 'Brick buyer' },
        rate = 0.85,                  -- of the bricks' street value
        perDay = 10,                  -- bricks per player per day
        xpPerBrick = 30,
    },
}

--[[ ─────────────────────────────── INTERFACE ─────────────────────────────── ]]
Config.UI = {
    -- NAYZEEE UI: black / white / teal / red, Lexend. Change these to re-skin everything.
    theme = {
        accent = '#08afa2',
        accent2 = '#0fd4c4',
        danger = '#e5484d',
        warning = '#e5a50a',
        success = '#3fb950',
        font = "'Lexend', system-ui, sans-serif",
    },
    hud = { position = 'left', scale = 1.0 },
    notify = { position = 'top-right', duration = 5000 },
    labels = { distance = 3.5 },
}

Config.Tablet = { command = 'weedlab', key = 'F6' }   -- the lab tablet (level, unlocks, labs). false = off
Config.Admin = { ace = 'nzwl.admin', command = 'weedlabadmin' }
