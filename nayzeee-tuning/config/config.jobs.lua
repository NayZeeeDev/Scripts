-- ██████╗  ██████╗ ██╗     ██╗ ██████╗███████╗
-- ██╔══██╗██╔═══██╗██║     ██║██╔════╝██╔════╝
-- ██████╔╝██║   ██║██║     ██║██║     █████╗
-- ██╔═══╝ ██║   ██║██║     ██║██║     ██╔══╝
-- ██║     ╚██████╔╝███████╗██║╚██████╗███████╗
-- ╚═╝      ╚═════╝ ╚══════╝╚═╝ ╚═════╝╚══════╝

Config.Police = {
    Enabled       = true,
    Jobs          = { 'police', 'sheriff', 'state' },
    InspectTime   = 6000,
    AllowStrip    = true,           -- officers can remove illegal parts on the spot
    StripTime     = 12000,
    Illegal = {                     -- what counts as illegal (true = flagged)
        nitrous    = true,
        antilag    = true,
        launch     = false,
        engineSwap = false,
        airride    = false,
        neon       = true,
        neonPattern= true,          -- flashing / emergency patterns
        tint       = { [1] = true, [5] = true },     -- pure black + limo
        xenonColor = { [8] = true, [1] = true, [2] = true, [12] = true }, -- red / blue / blacklight headlights
        customXenonRGB = true,
        camberAbove = 8.0,          -- degrees
        heightBelow = 0.09,         -- lowered more than this
        bulletproof = true,
    },
}

-- ██████╗ ██╗ █████╗  ██████╗ ███╗   ██╗ ██████╗ ███████╗████████╗██╗ ██████╗███████╗
-- ██╔══██╗██║██╔══██╗██╔════╝ ████╗  ██║██╔═══██╗██╔════╝╚══██╔══╝██║██╔════╝██╔════╝
-- ██║  ██║██║███████║██║  ███╗██╔██╗ ██║██║   ██║███████╗   ██║   ██║██║     ███████╗
-- ██║  ██║██║██╔══██║██║   ██║██║╚██╗██║██║   ██║╚════██║   ██║   ██║██║     ╚════██║
-- ██████╔╝██║██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝███████║   ██║   ██║╚██████╗███████║
-- ╚═════╝ ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═╝ ╚═════╝╚══════╝

Config.Diagnostics = {
    Enabled   = true,
    Item      = 'obd_scanner',      -- usable item (false = mechanics only via target)
    Jobs      = nil,                -- nil = anyone with the item, or { 'mechanic' }
    ScanTime  = 4500,
    TargetForMechanics = true,      -- mechanics on duty get a 'Run Diagnostics' target on every car
}

-- ██╗      ██████╗  ██████╗ █████╗ ████████╗ ██████╗ ██████╗
-- ██║     ██╔═══██╗██╔════╝██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗
-- ██║     ██║   ██║██║     ███████║   ██║   ██║   ██║██████╔╝
-- ██║     ██║   ██║██║     ██╔══██║   ██║   ██║   ██║██╔══██╗
-- ███████╗╚██████╔╝╚██████╗██║  ██║   ██║   ╚██████╔╝██║  ██║
-- ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝

Config.Locator = {
    Enabled   = true,
    Command   = 'findcar',
    BlipTime  = 60,                 -- seconds the ping stays on the map
    Cooldown  = 30,
}

-- ███╗   ███╗██╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ████╗ ████║██║██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
-- ██╔████╔██║██║███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
-- ██║╚██╔╝██║██║╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
-- ██║ ╚═╝ ██║██║███████║███████║██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Roadside callouts for mechanic shops (boss menu > Callouts)
Config.Missions = {
    Enabled   = true,
    Refresh   = 6,                  -- minutes between new callouts per shop
    MaxActive = 5,
    ShopCut   = 30,                 -- % of the reward that goes to the shop
    Reward    = { 450, 1100 },
    RepairTime = 9000,
    Vehicles  = { 'sentinel', 'sultan', 'tailgater', 'asea', 'emperor', 'blista', 'minivan', 'rebel' },
    Peds      = { 'a_m_y_business_02', 'a_f_y_hipster_02', 'a_m_m_farmer_01', 'a_f_m_tourist_01', 'a_m_y_stbla_02', 'a_f_y_business_04' },
    Faults    = {
        { id = 'battery',  label = 'Dead battery',       icon = 'fa-car-battery' },
        { id = 'tyre',     label = 'Flat tyre',          icon = 'fa-life-ring' },
        { id = 'overheat', label = 'Engine overheating', icon = 'fa-temperature-high' },
        { id = 'fuel',     label = 'Out of fuel',        icon = 'fa-gas-pump' },
        { id = 'starter',  label = 'Starter motor',      icon = 'fa-key' },
    },
    Locations = {
        vec4(2549.57, 1528.85, 29.62, 359.88), vec4(667.61, 3202.42, 38.3, 82.73), vec4(1509.74, -1487.85, 68.23, 315.25),
        vec4(642.2, -2667.51, 4.48, 25.51),    vec4(1656.48, -2527.38, 74.3, 317.36), vec4(-301.01, 2903.7, 44.05, 93.54),
        vec4(-668.53, 5904.92, 15.0, 359.47),  vec4(1446.27, 6442.89, 19.64, 249.03), vec4(2349.22, 4680.06, 34.39, 210.6),
        vec4(-1636.2, -907.4, 8.1, 140.0),     vec4(-2089.3, -330.2, 12.9, 350.0),    vec4(-518.6, -1745.0, 18.9, 320.0),
    },
}

-- ████████╗ ██████╗ ██╗    ██╗         ██╗ ██████╗ ██████╗ ███████╗
-- ╚══██╔══╝██╔═══██╗██║    ██║         ██║██╔═══██╗██╔══██╗██╔════╝
--    ██║   ██║   ██║██║ █╗ ██║         ██║██║   ██║██████╔╝███████╗
--    ██║   ██║   ██║██║███╗██║    ██   ██║██║   ██║██╔══██╗╚════██║
--    ██║   ╚██████╔╝╚███╔███╔╝    ╚█████╔╝╚██████╔╝██████╔╝███████║
--    ╚═╝    ╚═════╝  ╚══╝╚══╝      ╚════╝  ╚═════╝ ╚═════╝ ╚══════╝

-- Some roadside callouts are wrecks that can't be fixed on the spot: winch them onto a flatbed
-- (or hook them to a tow truck) and bring them back to the shop's drop point.
Config.Towing = {
    Enabled      = true,
    Chance       = 40,              -- % of new callouts that are tow jobs
    Reward       = { 1100, 2200 },
    ShopCut      = 30,              -- % of the reward that goes to the shop
    Trucks       = {                -- what can carry a wreck: 'bed' = winched onto the back, 'hook' = hooked behind
        flatbed   = { type = 'bed', offset = vec3(0.0, -2.2, 0.95) },
        towtruck  = { type = 'hook' },
        towtruck2 = { type = 'hook' },
    },
    WinchTime    = 9000,            -- ms to winch / hook the wreck
    UnloadTime   = 6000,
    LoadDistance = 9.0,             -- wreck must be this close to the back of the truck
    SpawnTruck   = true,            -- hand the mechanic a flatbed at the shop (shop.truckSpawn) when they take a tow job
    TruckModel   = 'flatbed',
    DropRadius   = 14.0,            -- around shop.drop (set it with /mechaniceditor), falls back to the shop centre
    WreckDespawn = 90,              -- seconds the delivered wreck stays at the shop
    Wrecks       = { 'sultan', 'tailgater', 'asea', 'emperor', 'blista', 'minivan', 'premier', 'fugitive', 'oracle', 'buffalo' },
}

-- ███████╗██╗   ██╗██████╗ ██████╗ ██╗  ██╗   ██╗
-- ██╔════╝██║   ██║██╔══██╗██╔══██╗██║  ╚██╗ ██╔╝
-- ███████╗██║   ██║██████╔╝██████╔╝██║   ╚████╔╝
-- ╚════██║██║   ██║██╔═══╝ ██╔═══╝ ██║    ╚██╔╝
-- ███████║╚██████╔╝██║     ██║     ███████╗██║
-- ╚══════╝ ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝
-- ██████╗ ██╗   ██╗███╗   ██╗███████╗
-- ██╔══██╗██║   ██║████╗  ██║██╔════╝
-- ██████╔╝██║   ██║██╔██╗ ██║███████╗
-- ██╔══██╗██║   ██║██║╚██╗██║╚════██║
-- ██║  ██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Restock parts cheaper than the tablet's Parts Store by fetching them yourself. Objectives:
-- get in the van, drive to the warehouse, carry the packages into the van, drive back to the shop,
-- carry every package into supply storage (shop.storage). The parts land in supply storage, not your pockets.
Config.SupplyRuns = {
    Enabled       = true,
    Discount      = 35,             -- % cheaper than the Parts Store price
    MinRank       = 'access',       -- 'access' | 'manager' | 'boss'
    CancelFee     = 15,             -- % of the paid price kept when a run is cancelled or runs out of time
    TimeLimit     = 25,             -- minutes
    TruckModel    = 'boxville2',
    SpawnTruck    = true,           -- false = bring any truck from TruckModels
    TruckModels   = { 'boxville2', 'boxville4', 'mule', 'mule3', 'benson', 'pounder' },
    ItemsPerCrate = 6,
    MaxCrates     = 6,
    CrateProp     = 'prop_cs_cardbox_01',
    LoadTime      = 1500,           -- ms to set a package down (van or storage)
    DropRadius    = 14.0,           -- around shop.drop
    Warehouses    = {
        { label = 'Elysian Island Freight', crates = vec3(1209.47, -3122.03, 5.54), truck = vec3(1195.66, -3110.12, 5.7) },
        { label = 'Cypress Flats Depot',     crates = vec3(890.42, -2167.6, 30.52),  truck = vec3(877.38, -2181.92, 30.52) },
        { label = 'La Puerta Parts Yard',    crates = vec3(-341.56, -2444.02, 6.0),  truck = vec3(-325.42, -2428.12, 6.0) },
        { label = 'Murrieta Industrial',     crates = vec3(978.34, -1702.53, 29.9),  truck = vec3(990.24, -1696.81, 29.9) },
    },
}

-- ███████╗ ██████╗██████╗  █████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗ ██████╗
-- ██╔════╝██╔════╝██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝██╔══██╗██╔══██╗██╔══██╗
-- ███████╗██║     ██████╔╝███████║██████╔╝ ╚████╔╝ ███████║██████╔╝██║  ██║
-- ╚════██║██║     ██╔══██╗██╔══██║██╔═══╝   ╚██╔╝  ██╔══██║██╔══██╗██║  ██║
-- ███████║╚██████╗██║  ██║██║  ██║██║        ██║   ██║  ██║██║  ██║██████╔╝
-- ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝

Config.Scrapyard = {
    Enabled   = false,              -- needs Config.Economy.Components.Enabled to be useful
    Label     = 'Scrapyard',
    Zone      = { coords = vec3(-468.2, -1715.4, 18.7), radius = 22.0 },
    Blip      = { sprite = 527, color = 44, scale = 0.8 },
    MinPolice = 0,
    BlockedJobs = { police = true },
    Parts = {                       -- bone, label, time, components (min, max)
        { bone = 'door_dside_f', label = 'Driver Door',    time = 6000, give = { 1, 3 }, door = 0 },
        { bone = 'door_pside_f', label = 'Passenger Door', time = 6000, give = { 1, 3 }, door = 1 },
        { bone = 'bonnet',       label = 'Hood',           time = 7000, give = { 1, 3 }, door = 4 },
        { bone = 'boot',         label = 'Trunk Lid',      time = 7000, give = { 1, 3 }, door = 5 },
        { bone = 'wheel_lf',     label = 'Front Left Wheel', time = 5000, give = { 1, 2 }, wheel = 0 },
        { bone = 'wheel_rf',     label = 'Front Right Wheel',time = 5000, give = { 1, 2 }, wheel = 1 },
        { bone = 'engine',       label = 'Engine',         time = 12000, give = { 3, 6 }, last = true },
    },
}
