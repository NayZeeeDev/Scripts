--[[
    nayzeee-heistpack | main configuration (shared: client + server)

    Everything in this file is visible to clients. Webhooks and other secrets
    belong in config/server.lua, which never leaves the server.

    Heist definitions live in config/heists/<id>.lua. Each is self-contained.
    Turn one off with `enabled = false` or remove it from Config.Heists.
]]

Config = {}

Config.Locale = 'en'
Config.Debug = false -- prints engine traces + draws node debug spheres

--[[ Integrations ('auto' detects the running resource) ]]
Config.Framework   = 'auto' -- 'auto' | 'qbx' | 'qb' | 'esx'
Config.Inventory   = 'auto' -- 'auto' | 'ox' | 'qb' | 'qs' | 'codem' | 'framework'
Config.Target      = 'auto' -- 'auto' | 'ox' | 'qb' | 'none'  ('none' = built-in [E] prompts)
Config.Dispatch    = 'auto' -- 'auto' | 'ps' | 'cd' | 'qs' | 'rcore' | 'tk' | 'lb' | 'builtin' | 'custom'
Config.VehicleKeys = 'auto' -- 'auto' | 'qbx' | 'qb' | 'wasabi' | 'mk' | 'renewed' | 'none'
Config.Notify      = 'nui'  -- 'nui' | 'ox' | 'framework'
Config.Progress    = 'nui'  -- 'nui' | 'ox'

--[[ Heist order in the tablet (ids = file names in config/heists) ]]
Config.Heists = {
    -- small
    'store', 'atm', 'house', 'boosting', 'gridhack',
    -- medium
    'fleeca', 'moneytruck', 'yacht', 'vehicletheft', 'barnraid', 'ammunation',
    -- major
    'vangelico', 'paleto', 'bobcat', 'truck', 'train', 'airfield', 'convoy',
    'cartel', 'cargoship', 'pacific',
}

--[[ Tablet access ]]
Config.Menu = {
    command = 'heist',         -- false to disable
    key = 'F10',               -- false to disable (players can rebind in GTA settings)
    item = 'heist_tablet',     -- false to disable
    requireNearEmployer = 0.0, -- 0 = open anywhere, otherwise max distance (m) to an employer
    allowedJobs = {},          -- empty = everyone. e.g. { 'ballas', 'vagos' }
    forbiddenJobs = { 'police', 'sheriff', 'ambulance' },
}

--[[ Employer / fence NPCs ]]
Config.Employers = {
    {
        model = 's_m_m_movprem_01',
        coords = vec4(736.07, -1332.72, 25.34, 237.2),
        scenario = 'WORLD_HUMAN_SMOKING',
        blip = { sprite = 429, color = 1, scale = 0.75, label = 'Heist Contact' },
        fence = true, -- this NPC also buys loot (config/fence.lua)
        vehicleSpawn = vec4(742.42, -1354.21, 25.68, 0.0),
    },
}

--[[ Police ]]
Config.Police = {
    jobs = { 'police', 'sheriff', 'state', 'bcso', 'sasp' },
    onDutyOnly = true,
    alertBlip = { sprite = 161, color = 1, scale = 1.2, radius = 60.0, duration = 90 }, -- builtin dispatch only
}

--[[ Progression ]]
-- XP needed to reach each level (index = level)
Config.Levels = { 0, 800, 2000, 3800, 6200, 9500, 13500, 18500, 25000, 33000, 43000, 55000 }

-- Perks by level (highest matching row wins). loot = payout multiplier, speed = action speed multiplier
Config.LevelPerks = {
    { level = 1,  loot = 1.00, speed = 1.00 },
    { level = 4,  loot = 1.05, speed = 1.05 },
    { level = 7,  loot = 1.10, speed = 1.10 },
    { level = 10, loot = 1.20, speed = 1.15 },
}

--[[ Money ]]
Config.Money = {
    -- what "money" rewards become: 'cash' | 'bank' | 'black_money' | 'markedbills' | 'item'
    type = 'cash',
    item = 'cash',              -- used when type = 'item'
    markedbillsItem = 'markedbills',
    marketAccounts = { cash = 'cash', bank = 'bank' }, -- framework account names used by the market
}

--[[ Crew / lobby ]]
Config.Crew = {
    inviteDistance = 0.0, -- 0 = invite from anywhere, otherwise max distance (m)
    inviteTimeout = 45,   -- seconds
    readyCheck = true,    -- every member must press "Ready" before the leader can start
    payoutSplit = 'equal', -- 'equal' (completion cash split evenly) | 'leader'
    crewBonus = 0.10,     -- +10% completion payout for each extra member
}

--[[ Daily featured heist: one random heist per day gets a bonus ]]
Config.Featured = { enabled = true, xp = 1.5, money = 1.25 }

--[[ Heist outfit (applied with natives, works with any clothing script; restored on finish) ]]
Config.Outfit = {
    enabled = true,
    male = {
        { component = 11, drawable = 50, texture = 0 }, -- top
        { component = 8,  drawable = 15, texture = 0 }, -- undershirt
        { component = 3,  drawable = 17, texture = 0 }, -- arms
        { component = 4,  drawable = 31, texture = 0 }, -- pants
        { component = 6,  drawable = 25, texture = 0 }, -- shoes
        { component = 5,  drawable = 45, texture = 0 }, -- bag
        { component = 1,  drawable = 52, texture = 0 }, -- mask
    },
    female = {
        { component = 11, drawable = 43, texture = 0 },
        { component = 8,  drawable = 14, texture = 0 },
        { component = 3,  drawable = 18, texture = 0 },
        { component = 4,  drawable = 30, texture = 0 },
        { component = 6,  drawable = 25, texture = 0 },
        { component = 5,  drawable = 45, texture = 0 },
        { component = 1,  drawable = 52, texture = 0 },
    },
}

--[[ Heist vehicle (optional getaway van the leader can request at the employer) ]]
Config.HeistVehicle = { enabled = true, model = 'burrito3', fuel = 100.0 }

--[[ General gameplay ]]
Config.Gameplay = {
    reconnectWindow = 300, -- seconds a disconnected member can rejoin their running heist
    failOnAllDead = true,  -- heist fails when every member is dead at once
    doorResetMinutes = 20, -- vault doors re-lock this long after a heist ends
    smashWeapons = {       -- weapon groups allowed to smash cases / break registers
        'GROUP_MELEE', 'GROUP_PISTOL', 'GROUP_SMG', 'GROUP_RIFLE', 'GROUP_MG', 'GROUP_SHOTGUN', 'GROUP_SNIPER',
    },
    guardAccuracy = 35,
    guardArmour = 50,
}

--[[ Interface ]]
Config.UI = {
    -- Change these to match your server's style. Everything in the UI derives from them.
    -- NAYZEEE UI: black / white / teal / red, Lexend. Change these to re-skin everything.
    theme = {
        accent = '#08afa2',  -- teal (brand)
        accent2 = '#0fd4c4', -- teal hi (glows, highlights)
        success = '#08afa2',
        danger = '#e5484d',  -- red
        warning = '#e5a50a', -- amber
        font = "'Lexend', system-ui, sans-serif",
        radius = '10px',
    },
    hud = {
        position = 'right',  -- 'left' | 'right'
        background = 'none', -- 'none' (fully transparent) | 'glass' | 'solid'
        expandKey = 'B',
        scale = 1.0,
    },
    textui = { position = 'bottom' },
    notify = { position = 'top-right', duration = 5000 },
}

--[[ Blips used by every heist ]]
Config.Blips = {
    objective = { sprite = 1,   color = 5,  scale = 0.9 },
    area      = { color = 1, alpha = 90 },
    vehicle   = { sprite = 225, color = 5,  scale = 0.8 },
    dropoff   = { sprite = 478, color = 2,  scale = 0.9 },
    guard     = { sprite = 270, color = 1,  scale = 0.5 },
}
