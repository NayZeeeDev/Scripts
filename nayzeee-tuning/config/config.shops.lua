-- ███████╗██╗  ██╗ ██████╗ ██████╗ ███████╗
-- ██╔════╝██║  ██║██╔═══██╗██╔══██╗██╔════╝
-- ███████╗███████║██║   ██║██████╔╝███████╗
-- ╚════██║██╔══██║██║   ██║██╔═══╝ ╚════██║
-- ███████║██║  ██║╚██████╔╝██║     ███████║
-- ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝

--[[
    mode
      'self'      customer pays and parts are fitted instantly (classic LS Customs)
      'mechanic'  customer places an order, mechanics fit the parts (money held until done)
      'hybrid'    works like 'mechanic', but falls back to 'self' when no mechanic is on duty

    grades        job grade numbers: access = can tune / take orders, manager = codes + missions + orders,
                  boss = finances, employees, upgrades
    bays          where a car must be parked to open the menu (vec4 = marker heading)
    bayRadius     default size of a bay in metres; one bay can have its own: { coords = vec4(...), radius = 2.2 }
    stockpiles    where mechanics pick parts up for physical installation (only used by mechanic shops)
    storage       supply storage point (config.items.lua Config.Storage)
    booths        paint jobs must be done with the car inside one of these (optional, leave empty to skip)
    allow / block restrict categories, items or vehicle classes for this shop only
]]

Config.Shops = {
    bennys = {
        label   = "Benny's Motor Works",
        mode    = 'hybrid',
        job     = 'mechanic',
        grades  = { access = 0, manager = 2, boss = 3 },
        society = 'society_mechanic',
        blip    = { enabled = true, sprite = 446, color = 5, scale = 0.8 },
        center  = vec3(-211.5, -1323.9, 30.9),
        radius  = 45.0,
        bays    = {                          -- vec4 uses bayRadius, or give a bay its own: { coords = vec4(...), radius = 2.2 }
            { coords = vec4(-222.41, -1329.52, 29.89, 270.0), radius = 2.4 },
            { coords = vec4(-223.26, -1323.21, 29.89, 270.0), radius = 2.4 },
        },
        bayRadius = 2.4,
        boss    = vec3(-200.50, -1306.64, 31.30),
        booths  = {
            { coords = vec3(-200.73, -1324.29, 29.71), radius = 4.5 },
        },
        stockpiles = {                       -- racks parts are collected from (keys = 'pile' in config.install.lua)
            body        = vec3(-195.90, -1315.47, 31.09),
            exhaust     = vec3(-198.43, -1315.29, 31.09),
            engine      = vec3(-196.37, -1317.22, 31.09),
            jacks       = vec3(-196.42, -1315.07, 31.09),
            wheels      = vec3(-206.03, -1331.13, 30.91),
            paint       = vec3(-200.83, -1318.38, 31.09),
            interior    = vec3(-198.43, -1315.29, 31.09),
            electronics = vec3(-196.42, -1315.07, 31.09),
            repair      = vec3(-227.83, -1327.94, 30.89),
        },
        truckSpawn = vec4(-185.62, -1293.21, 31.3, 270.0),   -- work trucks for tow jobs and supply runs
        drop       = vec3(-195.04, -1288.52, 31.3),          -- where tow jobs and supply runs are delivered
        storage    = vec3(-197.62, -1311.05, 31.09),         -- supply storage (take parts out, supply runs unload here)
        -- partSource = 'inventory',                         -- override Config.Storage.PartSource for this shop
        -- claimBays  = true,                                -- override Config.Bays for this shop
        parts = {                            -- optional per-part pickup points (override the rack)
            -- mod_0 = vec3(-195.90, -1315.47, 31.09),
        },
        allow = { },            -- e.g. { categories = { 'paint' } }
        block = { },            -- e.g. { items = { 'engineSwap' }, classes = { [8] = true } }
    },

    lsc_burton = {
        label   = 'Los Santos Customs Burton',
        mode    = 'self',
        blip    = { enabled = true, sprite = 72, color = 0, scale = 0.75 },
        center  = vec3(-338.74, -137.13, 39.0),
        radius  = 25.0,
        bays    = { vec4(-338.74, -137.13, 38.0, 90.0) },
        bayRadius = 2.4,
        block   = { items = { 'antilag', 'launch' } },
    },

    lsc_airport = {
        label   = 'Los Santos Customs LSIA',
        mode    = 'self',
        blip    = { enabled = true, sprite = 72, color = 0, scale = 0.75 },
        center  = vec3(-1155.1, -2006.39, 13.15),
        radius  = 25.0,
        bays    = { vec4(-1155.1, -2006.39, 12.15, 315.0) },
        bayRadius = 2.4,
    },

    lsc_lamesa = {
        label   = 'Los Santos Customs La Mesa',
        mode    = 'self',
        blip    = { enabled = true, sprite = 72, color = 0, scale = 0.75 },
        center  = vec3(731.63, -1088.84, 22.1),
        radius  = 25.0,
        bays    = { vec4(731.63, -1088.84, 21.1, 90.0) },
        bayRadius = 2.4,
    },

    sandy_repairs = {
        label   = 'Sandy Shores Auto Repairs',
        mode    = 'self',
        blip    = { enabled = true, sprite = 72, color = 0, scale = 0.75 },
        center  = vec3(1175.03, 2640.15, 37.8),
        radius  = 25.0,
        bays    = { vec4(1175.03, 2640.15, 36.8, 0.0) },
        bayRadius = 2.4,
        block   = { categories = { 'stance', 'chassis' }, items = { 'engineSwap', 'nitrous', 'ecu', 'antilag', 'launch', 'sound' } },
    },

    beekers = {
        label   = "Beeker's Garage",
        mode    = 'self',
        blip    = { enabled = true, sprite = 72, color = 0, scale = 0.75 },
        center  = vec3(110.45, 6626.54, 31.8),
        radius  = 25.0,
        bays    = { vec4(110.45, 6626.54, 30.8, 225.0) },
        bayRadius = 2.4,
        block   = { categories = { 'stance', 'chassis' }, items = { 'engineSwap', 'nitrous', 'ecu', 'antilag', 'launch', 'sound' } },
    },
}
