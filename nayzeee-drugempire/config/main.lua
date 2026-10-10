--[[
    nayzeee-drugempire | main configuration (shared: client + server)

    Everything in this file is visible to clients. The webhook and other
    secrets belong in config/server.lua, which never leaves the server.

    Other config files:
      config/products.lua   drugs, strains, effects, mixing ingredients
      config/stations.lua   placeable equipment, models, timings, first person steps
      config/customers.lua  customers, regions, deal spots, dealers
      config/shops.lua      delivery shops and dead drops
]]

Config = {}

Config.Locale = 'en'
Config.Debug = false

--[[ Integrations ('auto' detects the running resource) ]]
Config.Framework   = 'auto' -- 'auto' | 'qbx' | 'qb' | 'esx'
Config.Inventory   = 'auto' -- 'auto' | 'ox' | 'qb' | 'qs' | 'codem' | 'framework'
Config.Target      = 'auto' -- 'auto' | 'ox' | 'qb' | 'none'  ('none' = built-in [E] prompts)
Config.Dispatch    = 'auto' -- 'auto' | 'ps' | 'cd' | 'qs' | 'rcore' | 'lb' | 'builtin' | 'none'
Config.VehicleKeys = 'auto' -- 'auto' | 'qbx' | 'qb' | 'wasabi' | 'mk' | 'renewed' | 'none'
Config.Notify      = 'nui'  -- 'nui' | 'ox' | 'framework'

--[[ Money ]]
Config.Money = {
    sales = 'cash',       -- what customers / dealers pay with: 'cash' | 'bank' | 'black_money' | 'markedbills' | 'item'
    item = 'cash',        -- used when sales = 'item'
    markedbillsItem = 'markedbills',
    shopAccounts = { 'bank', 'cash' }, -- what players can pay delivery orders with (first = default)
}

--[[ Police ]]
Config.Police = {
    jobs = { 'police', 'sheriff', 'state', 'bcso', 'sasp' },
    onDutyOnly = true,
    forbidden = true,   -- police can't start the story or sell
    alertBlip = { sprite = 51, color = 1, scale = 1.0, radius = 80.0, duration = 90 }, -- builtin dispatch only
}

--[[ ─────────────────────────────── STORY ───────────────────────────────
    1. A random text from an unknown number. Go or ignore (ignored texts come back later).
    2. Meet Uncle Benson at a hidden spot. He sets you up and sends you to steal an RV.
    3. Steal the RV from a random, heavily guarded spot and drive it back to Benson.
    4. Benson gives you the starter kit, the Empire app installs on your phone,
       and the RV's interior becomes your first lab.
]]
Config.Story = {
    enabled = true,
    firstTextDelay = { 60, 180 },  -- seconds after the character loads (random between)
    retextMinutes = 20,            -- an ignored text comes back after this long
    unknownNumber = '(555) 0194',
    textTimeout = 40,              -- seconds to answer the on-screen text before it goes to the inbox

    benson = {
        name = 'Uncle Benson',
        model = 'a_m_o_genstreet_01',
        -- hidden spots: one is picked per player when the text arrives (keeps everyone off the same corner)
        spots = {
            vec4(2340.84, 3126.29, 48.21, 350.0),  -- Joshua Rd scrapyard
            vec4(2481.73, 3722.42, 43.92, 25.0),   -- Grand Senora, behind the hippie camp
            vec4(1543.71, 3592.47, 35.36, 300.0),  -- derelict motel, Route 68
        },
        wheelchair = 'prop_wheelchair_01',
        seat = { offset = vec3(0.0, 0.0, 0.45), scenario = 'PROP_HUMAN_SEAT_ARMCHAIR' },
        blip = { sprite = 280, color = 46, scale = 0.85, label = 'Unknown number' },
        talkDistance = 2.2,
    },

    rv = {
        model = 'journey',
        -- heavily guarded: one is picked at random for each player
        spots = {
            { vehicle = vec4(2477.41, 3767.13, 41.53, 105.0), label = 'Hippie camp, Grand Senora',
              guards = { vec4(2471.5, 3762.2, 41.6, 290.0), vec4(2484.6, 3771.3, 41.5, 180.0), vec4(2470.8, 3775.0, 41.5, 220.0),
                         vec4(2489.2, 3760.1, 41.8, 40.0), vec4(2463.9, 3767.0, 41.6, 260.0) } },
            { vehicle = vec4(1734.53, 3294.71, 41.22, 195.0), label = 'Sandy Shores airfield hangar',
              guards = { vec4(1728.6, 3300.2, 41.2, 200.0), vec4(1741.9, 3290.4, 41.2, 120.0), vec4(1722.0, 3287.6, 41.2, 260.0),
                         vec4(1746.8, 3302.9, 41.2, 90.0), vec4(1733.1, 3281.7, 41.2, 10.0) } },
            { vehicle = vec4(61.93, 3706.71, 39.75, 330.0), label = 'Stab City',
              guards = { vec4(55.4, 3712.6, 39.7, 300.0), vec4(70.1, 3700.4, 39.7, 140.0), vec4(48.8, 3699.0, 39.7, 210.0),
                         vec4(66.0, 3718.2, 39.7, 20.0), vec4(77.3, 3711.9, 39.7, 70.0), vec4(43.9, 3720.5, 39.9, 330.0) } },
            { vehicle = vec4(2416.03, 4993.16, 46.23, 135.0), label = "O'Neil farm, Grapeseed",
              guards = { vec4(2409.4, 4987.9, 46.2, 230.0), vec4(2423.1, 4999.2, 46.2, 45.0), vec4(2428.9, 4985.3, 46.2, 120.0),
                         vec4(2403.8, 5000.6, 46.4, 300.0), vec4(2417.5, 4977.9, 46.2, 180.0) } },
        },
        guardModels = { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03' },
        guardWeapons = { 'WEAPON_PISTOL', 'WEAPON_MICROSMG', 'WEAPON_PUMPSHOTGUN' },
        guardAccuracy = 30,
        guardArmour = 50,
        spawnDistance = 220.0,     -- guards spawn when you get this close
        wantedLevel = 0,           -- give the thief a wanted level when they take the RV (0 = off)
        alertChance = 50,          -- % chance police get a dispatch call when the RV is taken
        returnDistance = 18.0,     -- how close to Benson the RV has to be
        blip = { sprite = 67, color = 1, scale = 0.9, label = 'RV' },
    },

    -- what Benson hands over after the RV comes back
    starterKit = {
        { item = 'nz_pot', count = 2 },
        { item = 'nz_soil', count = 2 },
        { item = 'nz_seed_ogkush', count = 1 },
        { item = 'nz_baggie_empty', count = 20 },
        { item = 'nz_wateringcan', count = 1 },
        { item = 'nz_trimmers', count = 1 },
        { item = 'nz_packer', count = 1 },
    },
    starterCash = 0,
    starterCustomers = { 'andy', 'doug', 'joe' }, -- Benson's people: already your customers once the app installs
}

--[[ ─────────────────────────────── RV ─────────────────────────────── ]]
Config.RV = {
    model = 'journey',
    platePrefix = 'NZ',
    fuel = 60.0,
    entryOffset = vec3(-1.2, -3.6, 0.0),   -- where the "Enter RV" prompt sits, relative to the RV (rear side)
    entryRadius = 2.0,
    lockWhileInside = true,                 -- lock the RV while you're in the lab
    towFee = 500,                           -- phone app: tow a lost / destroyed RV back to a lot
    towLots = {
        vec4(1981.93, 3779.24, 32.18, 210.0),   -- Sandy Shores
        vec4(150.83, 6602.17, 31.85, 180.0),    -- Paleto
        vec4(1176.55, 2657.34, 37.81, 90.0),    -- Route 68
        vec4(-337.08, -1513.12, 27.53, 270.0),  -- Strawberry
    },

    --[[ The lab. 'auto' uses the K4MB1 `shell_trevor` if it is streamed, otherwise the
         base-game interior of Trevor's trailer. Every player is in their own routing bucket
         inside, so any number of players can use the same interior at once. ]]
    interior = 'auto', -- 'auto' | 'shell' | 'ipl'
    shell = {
        model = 'shell_trevor',
        origin = vec3(-1450.0, -3500.0, -60.0),          -- where the shell is spawned (out of sight)
        spawn = vec4(0.25, -3.1, 1.45, 0.0),             -- player position inside (relative to origin)
        exit = vec3(0.25, -3.48, 1.45),                  -- the "Leave RV" prompt (relative)
        radius = 6.5,                                    -- placement radius from origin
        floor = 0.05,                                    -- floor height (relative)
        sink = vec3(-2.4, 1.6, 1.0),                     -- tap for the watering can (relative). false = none
    },
    ipl = {
        origin = vec3(1973.21, 3816.68, 32.43),          -- Trevor's trailer (base game)
        spawn = vec4(0.65, -3.35, 1.0, 30.0),
        exit = vec3(0.6, -3.65, 1.0),
        radius = 5.5,
        floor = 0.0,
        sink = vec3(-1.25, 1.95, 1.0),
    },
    bucketBase = 7300,          -- routing bucket = bucketBase + server id
    maxObjects = 24,            -- placeables per RV
}

--[[ ─────────────────────────────── RANKS ───────────────────────────────
    Ranks with 5 tiers each, like the game. Level = (rank - 1) * 5 + tier.
    XP needed for a level = base + (level - 1) * step. ]]
Config.Ranks = {
    names = { 'Street Rat', 'Hoodlum', 'Peddler', 'Hustler', 'Bagman', 'Enforcer', 'Shot Caller', 'Block Boss', 'Underlord', 'Baron', 'Kingpin' },
    tiers = 5,
    base = 200,
    step = 60,
    xp = {
        deal = 30,          -- per completed deal (+1 per unit)
        sample = 40,        -- per accepted sample
        harvest = 15,
        cook = 20,          -- meth / coke / shroom batches
        mix = 10,           -- per new product discovered
        rv = 150,           -- story: RV brought back
    },
}

--[[ ─────────────────────────────── DEALS ─────────────────────────────── ]]
Config.Deals = {
    requestEvery = { 4, 9 },     -- minutes between deal requests for an online player (random)
    maxOpen = 4,                 -- open requests + accepted deals at once
    windowMinutes = 18,          -- how long a deal stays valid after the request
    spawnDistance = 70.0,        -- the customer walks up when you get this close
    handoverDistance = 3.0,
    counterSuccess = 0.55,       -- base chance a counter offer is accepted (scaled by how greedy it is)
    payWith = 'sales',           -- Config.Money.sales
    alertChance = 8,             -- % chance a nosy neighbour calls the police on a deal
    lateGrace = 2,               -- minutes after the window the customer still waits
    unitsPerBaggie = 1,
    unitsPerJar = 5,
}

--[[ ─────────────────────────────── DEALERS ─────────────────────────────── ]]
Config.Dealers = {
    tickMinutes = 3,             -- how often a dealer makes a sale run
    maxCustomers = 8,
    unitsPerRun = { 1, 4 },
    blip = { sprite = 280, color = 2, scale = 0.7 },
}

--[[ ─────────────────────────────── PHONE APP ─────────────────────────────── ]]
Config.Phone = {
    Enabled    = true,
    Phone      = 'auto',      -- 'auto' | 'lb-phone' | 'yseries' | 'qs-smartphone' | 'qs-smartphone-pro' | 'standalone'
    AppName    = 'Empire',
    Identifier = 'nz-empire',
    Command    = 'empire',    -- opens the app on screen (works with or without a phone). false to disable
    Keybind    = 'F7',        -- false to disable
}

--[[ ─────────────────────────────── INTERFACE ─────────────────────────────── ]]
Config.UI = {
    -- NAYZEEE UI: black / white / teal / red, Lexend. Change these to re-skin everything.
    theme = {
        accent = '#08afa2',  -- teal (brand)
        accent2 = '#0fd4c4', -- teal hi (glows, highlights)
        danger = '#e5484d',  -- red
        warning = '#e5a50a', -- amber
        success = '#3fb950', -- deal handshakes
        font = "'Lexend', system-ui, sans-serif",
    },
    hud = { position = 'left', scale = 1.0 },  -- the transparent objectives / deals list
    notify = { position = 'top-right', duration = 5000 },
    labels = { distance = 3.5 },               -- "NEEDS WATER" labels over pots
}

--[[ Admin ]]
Config.Admin = { ace = 'nzde.admin', command = 'empireadmin' }
