--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
    ██╗   ██╗███████╗██╗  ██╗██╗ ██████╗██╗     ███████╗
    ██║   ██║██╔════╝██║  ██║██║██╔════╝██║     ██╔════╝
    ██║   ██║█████╗  ███████║██║██║     ██║     █████╗
    ╚██╗ ██╔╝██╔══╝  ██╔══██║██║██║     ██║     ██╔══╝
     ╚████╔╝ ███████╗██║  ██║██║╚██████╗███████╗███████╗
      ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝╚══════╝
     ██████╗ █████╗ ██████╗  ██████╗  ██████╗
    ██╔════╝██╔══██╗██╔══██╗██╔════╝ ██╔═══██╗
    ██║     ███████║██████╔╝██║  ███╗██║   ██║
    ██║     ██╔══██║██╔══██╗██║   ██║██║   ██║
    ╚██████╗██║  ██║██║  ██║╚██████╔╝╚██████╔╝
     ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝

    nayzeee-vehiclecargo  v1.0.0  |  NayZeee Development
    Docs: nayzeee-dev.gitbook.io/docs  |  Store: www.nayzeeedev.com
]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Version   = '1.0.0'
Config.Debug     = false        -- prints extra info to the F8 / server console
Config.Framework = 'auto'       -- 'auto' | 'esx' | 'qb' | 'qbx'

-- Who can open /cargoadmin, /cargoslots and /cargocoords.
Config.Admin = {
    Ace    = 'nayzeee.vehiclecargo.admin',    -- add_ace group.admin nayzeee.vehiclecargo.admin allow
    Groups = { 'admin', 'superadmin', 'god' }, -- framework groups / permissions
}

-- Money accounts. ESX: 'money' | 'bank' | 'black_money'. QB/Qbox: 'cash' | 'bank' (cash/money are mapped for you).
Config.Accounts = {
    Purchase = 'bank',   -- warehouses, upgrades, sourcing fees, workshop, repairs
    Payout   = 'bank',   -- vehicle sale money
}

-- Every warehouse gets its own routing bucket: Bucket = Base + warehouse id.
Config.BucketBase = 7400

Config.MaxWarehousesPerPlayer = 1

-- Selling or moving a warehouse at the broker (owner only, nobody inside, no job running).
--   Sell = the warehouse is gone for good: building, upgrades, cars and crew access.
--   Move = buy another building and take everything with you: cars, upgrades, layout, crew.
Config.WarehouseSale = {
    Enabled       = true,
    Refund        = 0.50,   -- sell: share of the building price that comes back
    UpgradeRefund = 0.25,   -- sell: share of the money spent on upgrades and styles that comes back
    StockRefund   = 0.10,   -- sell: share of each stored car's value paid out (0.10 = scrap price, 0 = cars are lost)
    TradeIn       = 0.50,   -- move: share of the old building price taken off the new one
}

-- ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗███████╗
-- ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║███████╗
-- ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

-- 'auto' picks the first one that is running.
Config.Notify = 'auto'   -- 'auto' | 'nayzeee' | 'ox' | 'esx' | 'qb' | 'okok' | 'custom' (edit bridge/client.lua)
Config.TextUI = 'auto'   -- 'auto' | 'nayzeee' | 'ox' | 'esx' | 'qb' | 'okok'
Config.Target = 'auto'   -- 'auto' | 'ox_target' | 'qb-target' | 'interact' | 'textui'
Config.Phone  = {
    System   = 'lb-phone',   -- 'auto' | 'lb-phone' | 'yseries' | 'npwd' | 'qs-smartphone' | 'gksphone' | 'none'
    Sender   = 'Unknown',    -- contact name shown on notifications
    Number   = '5550199',    -- the number texts come from (phones need a real number, not a name)
    Notify   = true,         -- also push a phone notification (lb-phone) so it pops even with the phone closed
    Fallback = false,        -- show a phone-style message on screen when no phone resource takes it
    -- Texts your contact sends during the job (attacker texts live in Config.Attackers.Messages).
    Contact  = {
        start   = { 'Got a buyer lined up for a %s. Location is on your GPS.', 'Client wants a %s. Spot\'s marked. Don\'t scratch it.' },
        party   = { 'Owner of the %s is at a party. Pull a piece, make them talk, one of them has the keys.' },
        pickpocket = { 'Owner of the %s is out on foot. Sneak up behind him and lift the keys.' },
        hostile = { 'Owner of the %s is ex-military and carries. Keys are on him. Dead or alive.' },
        guarded = { 'The %s is under guard. One of them is holding the keys.' },
        tow     = { 'The %s is dead in a guarded lot. Steal their flatbed and tow it out.' },
        cargobob = { 'The %s is somewhere only a chopper can lift it from. There\'s a Cargobob on a guarded pad.' },
        sale    = { 'Buyer is waiting at %s. Don\'t keep them long.' },
        raid    = { 'Heads up. Cops have been asking about your warehouse. Move or pay someone off.', 'Word is there\'s a warrant coming for your place.' },
    },
}

-- ██████╗ ██╗███████╗██████╗  █████╗ ████████╗ ██████╗██╗  ██╗
-- ██╔══██╗██║██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║
-- ██║  ██║██║███████╗██████╔╝███████║   ██║   ██║     ███████║
-- ██║  ██║██║╚════██║██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║
-- ██████╔╝██║███████║██║     ██║  ██║   ██║   ╚██████╗██║  ██║
-- ╚═════╝ ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝

-- Police alerts (break-ins, live trackers, raids).
-- 'auto' picks the first dispatch resource that is running, otherwise the built-in alert.
-- 'custom' calls Bridge.CustomDispatch in bridge/server.lua.
Config.Dispatch = {
    System = 'auto',     -- 'auto' | 'builtin' | 'ps-dispatch' | 'cd_dispatch' | 'rcore_dispatch' | 'qs-dispatch' | 'custom'
    -- Who gets the alerts: Config.Sourcing.PoliceJobs
    BlipTime = 60,       -- seconds the alert blip stays on the map
}

-- ██╗     ███████╗██╗   ██╗███████╗██╗     ███████╗
-- ██║     ██╔════╝██║   ██║██╔════╝██║     ██╔════╝
-- ██║     █████╗  ██║   ██║█████╗  ██║     ███████╗
-- ██║     ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║     ╚════██║
-- ███████╗███████╗ ╚████╔╝ ███████╗███████╗███████║
-- ╚══════╝╚══════╝  ╚═══╝  ╚══════╝╚══════╝╚══════╝

Config.Levels = {
    Max   = 50,
    Base  = 250,    -- XP needed for level 2
    Curve = 1.55,   -- total XP for level n = Base * (n-1)^Curve
}

-- ██████╗ ██████╗ ███████╗███████╗████████╗██╗ ██████╗ ███████╗
-- ██╔══██╗██╔══██╗██╔════╝██╔════╝╚══██╔══╝██║██╔════╝ ██╔════╝
-- ██████╔╝██████╔╝█████╗  ███████╗   ██║   ██║██║  ███╗█████╗
-- ██╔═══╝ ██╔══██╗██╔══╝  ╚════██║   ██║   ██║██║   ██║██╔══╝
-- ██║     ██║  ██║███████╗███████║   ██║   ██║╚██████╔╝███████╗
-- ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝   ╚═╝ ╚═════╝ ╚══════╝

-- At max level you can prestige from the laptop (Profile app):
-- your level goes back to 1 and you get a badge plus a permanent bonus.
Config.Prestige = {
    Enabled     = true,
    Max         = 10,         -- highest prestige
    Cost        = 250000,     -- price to prestige (0 = free)
    KeepUnlocks = true,       -- contracts stay unlocked after the reset
    SaleBonus   = 0.04,       -- +4% sale money per prestige
    XpBonus     = 0.05,       -- +5% XP per prestige
}

-- ██████╗  █████╗ ██████╗ ██╗████████╗██╗███████╗███████╗
-- ██╔══██╗██╔══██╗██╔══██╗██║╚══██╔══╝██║██╔════╝██╔════╝
-- ██████╔╝███████║██████╔╝██║   ██║   ██║█████╗  ███████╗
-- ██╔══██╗██╔══██║██╔══██╗██║   ██║   ██║██╔══╝  ╚════██║
-- ██║  ██║██║  ██║██║  ██║██║   ██║   ██║███████╗███████║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝   ╚═╝   ╚═╝╚══════╝╚══════╝

-- The ladder the design bay can climb.
-- level      = player level needed to take contracts for this rarity
-- fee        = sourcing contract cost
-- valueMult  = applied when the design bay raises a car INTO this rarity
-- xp         = XP for a successful source (sales give SaleXpMult of this)
Config.Rarities = {
    { id = 'common',    label = 'Common',    color = '#9ea5aa', level = 1,  fee = 2500,  valueMult = 1.00, xp = 60  },
    { id = 'uncommon',  label = 'Uncommon',  color = '#e8ecee', level = 3,  fee = 5000,  valueMult = 1.22, xp = 90  },
    { id = 'rare',      label = 'Rare',      color = '#08afa2', level = 6,  fee = 9000,  valueMult = 1.50, xp = 140 },
    { id = 'epic',      label = 'Epic',      color = '#8b7cf6', level = 11, fee = 16000, valueMult = 1.85, xp = 220 },
    { id = 'legendary', label = 'Legendary', color = '#e5a50a', level = 18, fee = 26000, valueMult = 2.30, xp = 340 },
    { id = 'mythic',    label = 'Mythic',    color = '#e5484d', level = 28, fee = 42000, valueMult = 2.90, xp = 520 },
}

-- Illegal vehicles: their own tier, stored downstairs (4 slots), never climb or drop rarity.
-- Needs the Lower Level upgrade. Pool lives in config/vehicles.lua (Config.IllegalVehicles).
Config.Illegal = {
    id = 'illegal', label = 'Illegal', color = '#ff3b5c',
    level = 22, fee = 75000, valueMult = 1.0, xp = 760,
}

-- ███████╗██████╗ ███████╗ ██████╗██╗ █████╗ ██╗     ███████╗
-- ██╔════╝██╔══██╗██╔════╝██╔════╝██║██╔══██╗██║     ██╔════╝
-- ███████╗██████╔╝█████╗  ██║     ██║███████║██║     ███████╗
-- ╚════██║██╔═══╝ ██╔══╝  ██║     ██║██╔══██║██║     ╚════██║
-- ███████║██║     ███████╗╚██████╗██║██║  ██║███████╗███████║
-- ╚══════╝╚═╝     ╚══════╝ ╚═════╝╚═╝╚═╝  ╚═╝╚══════╝╚══════╝

-- Extra contract cards next to the rarity ladder. Each one draws from its own
-- pool in config/vehicles.lua (Config.SpecialVehicles[id]) and stores on the main floor.
-- scenarios = how the car is found (same keys as Config.Sourcing.Scenarios)
-- valueMult = multiplies the car's base value when it is stored
Config.SpecialContracts = {
    {
        id = 'classic', label = 'Classic Collector', icon = 'fa-solid fa-car-side', color = '#c9a46b',
        desc = 'Vintage cars for a private collector. Owners keep them close.',
        level = 8, fee = 14000, xp = 210, valueMult = 1.10,
        scenarios = { party = 30, pickpocket = 30, hostile = 20, tow = 20 },
    },
    {
        id = 'bike', label = 'Two-Wheel Run', icon = 'fa-solid fa-motorcycle', color = '#4fb3ff',
        desc = 'Fast bikes. Quick to grab, hard to keep upright with a crew behind you.',
        level = 4, fee = 6000, xp = 110, valueMult = 1.0,
        scenarios = { parked = 35, moving = 35, pickpocket = 30 },
    },
}

-- ██╗   ██╗██████╗  ██████╗ ██████╗  █████╗ ██████╗ ███████╗███████╗
-- ██║   ██║██╔══██╗██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝
-- ██║   ██║██████╔╝██║  ███╗██████╔╝███████║██║  ██║█████╗  ███████╗
-- ██║   ██║██╔═══╝ ██║   ██║██╔══██╗██╔══██║██║  ██║██╔══╝  ╚════██║
-- ╚██████╔╝██║     ╚██████╔╝██║  ██║██║  ██║██████╔╝███████╗███████║
--  ╚═════╝ ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝

Config.Upgrades = {
    capacity = {
        label = 'Storage', icon = 'fa-solid fa-warehouse',
        desc  = 'How many vehicles the main floor can hold (32 max).',
        levels = {
            { price = 0,      slots = 8 },
            { price = 150000, slots = 16 },
            { price = 325000, slots = 24 },
            { price = 550000, slots = 32 },
        },
    },
    lower = {
        label = 'Lower Level', icon = 'fa-solid fa-stairs',
        desc  = 'Opens the downstairs floor: 4 slots for illegal vehicles and Illegal contracts.',
        levels = {
            { price = 0,      open = false },
            { price = 650000, open = true },
        },
    },
    workshop = {
        label = 'Design Bay', icon = 'fa-solid fa-spray-can-sparkles',
        desc  = 'Unlocks the design bay in the back. Higher bays unlock more parts and bigger rarity jumps.',
        levels = {
            { price = 0,      name = 'None',             categories = {},                                    maxRarityGain = 0, scoreMult = 1.00 },
            { price = 95000,  name = 'Cosmetic Bay',     categories = { 'cosmetic' },                         maxRarityGain = 1, scoreMult = 1.00 },
            { price = 240000, name = 'Performance Bay',  categories = { 'cosmetic', 'performance', 'light' }, maxRarityGain = 1, scoreMult = 1.00 },
            { price = 480000, name = 'Master Bay',       categories = { 'cosmetic', 'performance', 'light' }, maxRarityGain = 2, scoreMult = 1.10 },
        },
    },
    intel = {
        label = 'Intel Network', icon = 'fa-solid fa-satellite-dish',
        desc  = 'Hot tips, shorter cooldowns, and from level 3 a scanner that shows tracked cars other players are moving.',
        levels = {
            { price = 0,      rollUp = 0.05, cooldownCut = 0.00, scanner = false },
            { price = 120000, rollUp = 0.10, cooldownCut = 0.10, scanner = false },
            { price = 260000, rollUp = 0.16, cooldownCut = 0.20, scanner = true },
            { price = 450000, rollUp = 0.24, cooldownCut = 0.30, scanner = true },
        },
    },
    contacts = {
        label = 'Buyer Contacts', icon = 'fa-solid fa-handshake',
        desc  = 'More buyers bidding on your cars and a better cut on every sale.',
        levels = {
            { price = 0,      saleBonus = 0.00, buyers = 2 },
            { price = 110000, saleBonus = 0.05, buyers = 3 },
            { price = 250000, saleBonus = 0.10, buyers = 3 },
            { price = 420000, saleBonus = 0.15, buyers = 4 },
        },
    },
    tracker = {
        label = 'Tracker Workshop', icon = 'fa-solid fa-tower-broadcast',
        desc  = 'Strip trackers yourself. Level 2: your garage pulls them for a fee. Level 3: place your own removal spot anywhere.',
        levels = {
            { price = 0,      garage = false, custom = false },
            { price = 180000, garage = true,  custom = false, garageFee = 4000 },
            { price = 340000, garage = true,  custom = true,  garageFee = 0 },
        },
    },
    repair = {
        label = 'Repair Bay', icon = 'fa-solid fa-screwdriver-wrench',
        desc  = 'Cheaper repairs on vehicles damaged while sourcing.',
        levels = {
            { price = 0,      costMult = 1.00 },
            { price = 75000,  costMult = 0.70 },
            { price = 160000, costMult = 0.40 },
        },
    },
    style = {
        label = 'Interior Style', icon = 'fa-solid fa-paint-roller',
        desc  = 'The look of your warehouse floor.',
        styles = {
            { id = 'basic',   label = 'Basic',   price = 0,      set = 'basic_style_set' },
            { id = 'branded', label = 'Branded', price = 120000, set = 'branded_style_set' },
            { id = 'urban',   label = 'Urban',   price = 210000, set = 'urban_style_set' },
        },
    },
}

-- ██╗      █████╗ ██╗   ██╗ ██████╗ ██╗   ██╗████████╗
-- ██║     ██╔══██╗╚██╗ ██╔╝██╔═══██╗██║   ██║╚══██╔══╝
-- ██║     ███████║ ╚████╔╝ ██║   ██║██║   ██║   ██║
-- ██║     ██╔══██║  ╚██╔╝  ██║   ██║██║   ██║   ██║
-- ███████╗██║  ██║   ██║   ╚██████╔╝╚██████╔╝   ██║
-- ╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝  ╚═════╝    ╚═╝

-- Owners pick a preset or place their own spots (up to MaxSlots)
-- from the laptop or with the command.
Config.Layout = {
    MaxSlots = 32,
    Command  = 'cargolayout',
}

-- ███████╗ ██████╗ ██╗   ██╗██████╗  ██████╗██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔════╝██║████╗  ██║██╔════╝
-- ███████╗██║   ██║██║   ██║██████╔╝██║     ██║██╔██╗ ██║██║  ███╗
-- ╚════██║██║   ██║██║   ██║██╔══██╗██║     ██║██║╚██╗██║██║   ██║
-- ███████║╚██████╔╝╚██████╔╝██║  ██║╚██████╗██║██║ ╚████║╚██████╔╝
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Sourcing = {
    Cooldown        = 8 * 60,     -- seconds between contracts (Intel cuts this)
    -- 'global'   = one cooldown after any contract (Cooldown above)
    -- 'contract' = each card has its own cooldown (ContractCooldowns), the others stay open
    CooldownMode    = 'global',
    ContractCooldowns = {
        common = 4 * 60, uncommon = 6 * 60, rare = 9 * 60, epic = 12 * 60, legendary = 16 * 60, mythic = 22 * 60,
        illegal = 35 * 60, classic = 14 * 60, bike = 6 * 60,
    },
    TimeLimit       = 25 * 60,    -- seconds to get the car home
    MinPolice       = 0,          -- police on duty needed to start a contract
    PoliceJobs      = { 'police', 'sheriff', 'state' },
    WantedLevel     = 0,          -- GTA wanted level on break in (0 = off, use dispatch instead)
    DispatchChance  = 0.55,       -- chance police get an alert on break in (impound always alerts)
    DeliverRadius   = 6.0,
    LockpickItem    = false,      -- item name to require for parked cars, or false
    SkillCheck      = { 'easy', 'easy', 'medium' },   -- ox_lib skill check on locked cars

    -- How the car is found (weights per tier). Spots for each live in config/locations.lua.
    --   parked     locked on the street, break in
    --   moving     someone is driving it, stop them
    --   impound    locked in a guarded lot, break in
    --   party      aim at the guests so they give up, then search each one for the keys
    --   pickpocket the owner is out on foot, sneak up behind and lift the keys
    --   hostile    the armed owner fights back, take the keys off his body
    --   guarded    a shootout, the guard holding the keys drops them when he goes down
    --   tow        the car is dead, steal a flatbed from a guarded depot and tow it home
    --   cargobob   the car is stranded, steal a Cargobob from a guarded pad and lift it out
    Scenarios = {
        common    = { parked = 45, party = 20, moving = 15, pickpocket = 20 },
        uncommon  = { parked = 25, party = 20, moving = 15, pickpocket = 20, guarded = 10, hostile = 10 },
        rare      = { parked = 10, party = 15, moving = 15, pickpocket = 15, guarded = 15, hostile = 15, impound = 5, tow = 10 },
        epic      = { party = 10, moving = 15, pickpocket = 10, guarded = 20, hostile = 15, impound = 10, tow = 10, cargobob = 10 },
        legendary = { moving = 10, guarded = 25, hostile = 20, impound = 15, tow = 15, cargobob = 15 },
        mythic    = { moving = 10, guarded = 25, hostile = 20, impound = 10, tow = 15, cargobob = 20 },
        illegal   = { guarded = 30, hostile = 20, tow = 25, cargobob = 25 },
    },
    -- Key scenarios (party, pickpocket, hostile, guarded) can't be lockpicked: you need the keys.
    KeysOnly = true,
    -- Chance the car has a tracker on it.
    TrackerChance = { common = 0.15, uncommon = 0.22, rare = 0.28, epic = 0.33, legendary = 0.38, mythic = 0.42, illegal = 0.60 },
    Tracker = {
        PingEvery   = 30,   -- seconds between dispatch pings while the tracker is live
        PoliceLive  = 5,    -- seconds between live position updates for on-duty police
    },
    Guards = {
        Models  = { 'g_m_y_lost_01', 'g_m_y_mexgoon_02', 'g_m_y_salvagoon_01', 'g_m_m_armgoon_01' },
        Weapons = { 'WEAPON_PISTOL', 'WEAPON_MICROSMG', 'WEAPON_PISTOL50', 'WEAPON_SAWNOFFSHOTGUN' },
        -- { min, max } per scenario. hostile = the owner's buddies.
        Count   = { guarded = { 3, 5 }, impound = { 2, 4 }, hostile = { 0, 2 }, tow = { 3, 5 }, cargobob = { 3, 5 } },
        Accuracy = 28,
        Armour   = 40,
        -- Illegal contracts: extra guards and tougher ones
        Illegal  = { Extra = 2, Accuracy = 45, Armour = 100, Weapons = { 'WEAPON_CARBINERIFLE', 'WEAPON_ASSAULTRIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_SMG' } },
    },
    ImpoundGuardModels = { 's_m_m_security_01', 's_m_m_armoured_01' },
    PartyModels = { 'a_m_y_hipster_01', 'a_f_y_hipster_02', 'a_m_y_vinewood_01', 'a_f_y_vinewood_02', 'a_m_y_beach_01', 'a_f_y_beach_01' },
    PartyGuests = { 4, 6 },
    Party = {
        FleeChance  = 0.15,   -- a guest you aim at runs instead of giving up (chase them down)
        FightChance = 0.12,   -- a guest you aim at pulls a gun
        SearchTime  = 3500,   -- ms to search one guest
    },
    Pickpocket = {
        OwnerModels = { 'a_m_y_business_02', 'a_m_m_bevhills_01', 'a_m_y_bevhills_02', 'a_f_y_business_01' },
        Time        = 3000,   -- ms to lift the keys
        SkillCheck  = { 'easy', 'medium' },
        Notice      = 5.0,    -- he notices you running or aiming at him inside this range
        FightChance = 0.35,   -- when he notices you: fight, otherwise run and call the cops
    },
    Hostile = {
        OwnerModels = { 's_m_y_blackops_01', 'g_m_m_chicold_01', 'u_m_y_smugmech_01', 'g_m_y_ballasout_01' },
        Weapons     = { 'WEAPON_PISTOL50', 'WEAPON_HEAVYPISTOL', 'WEAPON_ASSAULTSMG' },
        Aggro       = 28.0,   -- range he opens fire from
        Armour      = 100,
    },
    -- Recovery jobs: the car can't be driven, you bring your own lift.
    Recovery = {
        Hotwire   = { 'easy', 'medium', 'medium' },   -- skill check to steal the flatbed / Cargobob
        Tow       = { Model = 'flatbed',  Offset = { x = 0.0, y = -2.35, z = 1.15 }, LoadRange = 9.0 },
        Cargobob  = { Model = 'cargobob2', HookRange = 9.0 },
    },
}

--  █████╗ ████████╗████████╗ █████╗  ██████╗██╗  ██╗███████╗██████╗ ███████╗
-- ██╔══██╗╚══██╔══╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗██╔════╝
-- ███████║   ██║      ██║   ███████║██║     █████╔╝ █████╗  ██████╔╝███████╗
-- ██╔══██║   ██║      ██║   ██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗╚════██║
-- ██║  ██║   ██║      ██║   ██║  ██║╚██████╗██║  ██╗███████╗██║  ██║███████║
-- ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝

-- Crews that come after the car. Rarer cars draw more heat.
-- 'source' = after you take a car, 'sell' = on the way to a buyer.
-- A tracker left on keeps sending new waves every TrackerWave seconds.
Config.Attackers = {
    Vehicles = { 'baller', 'granger', 'cavalcade2', 'dubsta', 'kuruma', 'schafter2' },
    Peds     = { 'g_m_y_famca_01', 'g_m_y_ballaeast_01', 'g_m_y_mexgoon_01', 'g_m_y_lost_02', 'g_m_y_korean_02' },
    Weapons  = { 'WEAPON_MICROSMG', 'WEAPON_PISTOL', 'WEAPON_MACHINEPISTOL' },
    Delay    = { 20, 55 },          -- seconds after the trigger
    TrackerWave = 150,              -- seconds between waves while a tracker is live
    Spawn    = { Min = 160.0, Max = 260.0 },   -- like GTA: out of sight on a road this far away, then they drive in
    -- chance of attackers and how many cars, per tier
    source = {
        common = { 0.08, 1, 1 }, uncommon = { 0.15, 1, 1 }, rare = { 0.28, 1, 2 }, epic = { 0.42, 1, 2 },
        legendary = { 0.58, 2, 2 }, mythic = { 0.72, 2, 3 }, illegal = { 1.00, 2, 3 },
    },
    sell = {
        common = { 0.10, 1, 1 }, uncommon = { 0.16, 1, 1 }, rare = { 0.25, 1, 2 }, epic = { 0.38, 1, 2 },
        legendary = { 0.52, 2, 2 }, mythic = { 0.65, 2, 3 }, illegal = { 1.00, 2, 3 },
    },
    -- Texts from an unknown number when a crew is on its way.
    Messages = {
        source  = { 'Nice ride. Shame it isn\'t yours.', 'We know what you took. Pull over.', 'You picked the wrong car today.' },
        sell    = { 'Heard you\'re making a delivery. We\'ll take it from here.', 'That buyer isn\'t getting that car.', 'Pull over and walk away.' },
        tracker = { 'Your car is still pinging. We see you.', 'Thanks for leaving the tracker on.' },
        illegal = { 'That thing downstairs belongs to us. Coming to collect.', 'You moved the wrong merchandise.' },
    },
}

-- ██╗  ██╗██╗     ██╗ █████╗  ██████╗██╗  ██╗██╗███╗   ██╗ ██████╗
-- ██║  ██║██║     ██║██╔══██╗██╔════╝██║ ██╔╝██║████╗  ██║██╔════╝
-- ███████║██║     ██║███████║██║     █████╔╝ ██║██╔██╗ ██║██║  ███╗
-- ██╔══██║██║██   ██║██╔══██║██║     ██╔═██╗ ██║██║╚██╗██║██║   ██║
-- ██║  ██║██║╚█████╔╝██║  ██║╚██████╗██║  ██╗██║██║ ╚████║╚██████╔╝
-- ╚═╝  ╚═╝╚═╝ ╚════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

-- A car with its tracker still live can be stolen by other players.
-- Warehouse owners with the Intel scanner see tracked cars on the map.
-- The thief can store it in their own warehouse or chop it for cash.
Config.Hijack = {
    Enabled       = true,
    TrackedOnly   = true,     -- only cars with a live tracker can be hijacked
    ChopPayout    = 0.35,     -- chop shop pays this share of the car's value
    ChopXp        = 0.30,     -- share of the tier XP
    ScannerPing   = 30,       -- seconds between scanner pings to other owners
}

--  ██████╗██╗  ██╗ ██████╗ ██████╗     ███████╗██╗  ██╗ ██████╗ ██████╗
-- ██╔════╝██║  ██║██╔═══██╗██╔══██╗    ██╔════╝██║  ██║██╔═══██╗██╔══██╗
-- ██║     ███████║██║   ██║██████╔╝    ███████╗███████║██║   ██║██████╔╝
-- ██║     ██╔══██║██║   ██║██╔═══╝     ╚════██║██╔══██║██║   ██║██╔═══╝
-- ╚██████╗██║  ██║╚██████╔╝██║         ███████║██║  ██║╚██████╔╝██║
--  ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝         ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝

-- What happens when a stolen car has to be chopped.
-- 'builtin' uses the chop shops in config/locations.lua.
-- Any other system sends players to that script's chop shops instead.
-- Hook it up in integrations/chopshop.lua (one line in their script).
Config.ChopShop = {
    System        = 'builtin',   -- 'builtin' | 'auto' | 'bablo' | 'lation' | 'custom'
    PayOnExternal = false,       -- also pay our chop payout when another script chops it (false = their script pays)
    XpOnExternal  = true,        -- still give Vehicle Cargo XP for it
    DetectRadius  = 40.0,        -- a job car that disappears this close to one of their shops counts as chopped

    Resources = {                -- resource folder names, only used by 'auto'
        bablo  = 'bablo-chopshop',
        lation = 'lation_chopshop',
    },

    -- Where the other script's chop shops are (blips + detection). Copy them from its config.
    External = {
        { label = 'Chop Shop · La Mesa',      coords = vec3(-468.00, -1712.00, 18.70) },
        { label = 'Chop Shop · Grand Senora', coords = vec3(2340.00, 3055.00, 48.15) },
    },
}

-- ███████╗███████╗██╗     ██╗     ██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔════╝██║     ██║     ██║████╗  ██║██╔════╝
-- ███████╗█████╗  ██║     ██║     ██║██╔██╗ ██║██║  ███╗
-- ╚════██║██╔══╝  ██║     ██║     ██║██║╚██╗██║██║   ██║
-- ███████║███████╗███████╗███████╗██║██║ ╚████║╚██████╔╝
-- ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Selling = {
    Cooldown        = 4 * 60,
    TimeLimit       = 15 * 60,
    QuickSale       = 0.55,       -- instant export at this % of value, no drive
    SaleXpMult      = 0.75,
    CleanXpBonus    = 0.50,       -- extra XP for a delivery with zero damage
    CleanStreak     = { step = 0.02, max = 0.10 },  -- +2% per clean delivery in a row, up to +10%
    ConditionWeight = 0.60,       -- how much stored condition (sourcing damage) affects the base offer
    MinOffer        = 0.25,       -- the offer never drops below 25% of what the buyer first agreed
    OfferRefresh    = 30 * 60,    -- buyer offers on a car reshuffle after this many seconds
    ReturnOnFail    = false,      -- true = a failed sale sends the car back to the warehouse instead of losing it
    MinDropDistance = 400.0,      -- drop-offs closer than this to the warehouse are skipped
    -- Every time the car gets damaged on the way, the buyer drops the price.
    Damage = {
        hit       = { pct = 1.5,  label = 'Hit',       icon = 'fa-solid fa-car-burst' },
        rammed    = { pct = 3.0,  label = 'Rammed',    icon = 'fa-solid fa-car-side' },
        shot      = { pct = 2.0,  label = 'Shot',      icon = 'fa-solid fa-crosshairs' },
        explosion = { pct = 25.0, label = 'Explosion', icon = 'fa-solid fa-explosion' },
        severityPer100 = 1.5,     -- extra % per 100 points of body/engine health lost in one hit
        minHealthDrop  = 8.0,     -- ignore scrapes smaller than this
        debounce       = 650,     -- ms, one crash counts once
    },
    -- Handover cinematic at the buyer (camera shots, keys handed over, buyer drives off).
    Cutscene = {
        Enabled = true,
        BuyerModels = { 'a_m_y_business_03', 'a_m_m_bevhills_01', 'a_m_y_vinewood_03', 'a_f_y_business_02' },
        -- what the buyer is doing while they wait for you (GTA scenarios, one is picked at random)
        Idle = { 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_AA_COFFEE', 'WORLD_HUMAN_HANG_OUT_STREET', 'WORLD_HUMAN_GUARD_STAND', 'WORLD_HUMAN_LEANING' },
    },
    BuyerNames = {
        'Benny', 'Hao', 'Simeon', 'Martin', 'Gianni', 'Lupe', 'Dex', 'Marisol', 'Viktor', 'Kenji',
        'Darnell', 'Rocco', 'Yuri', 'Imani', 'Sol', 'Tasha', 'Andre', 'Nico', 'Ines', 'Malik',
    },
    BuyerTypes = {
        { id = 'private',    label = 'Private Collector', offer = { 1.00, 1.08 }, dist = 'near', wants = 1, hot = 0.10 },
        { id = 'showroom',   label = 'Showroom',          offer = { 1.10, 1.20 }, dist = 'mid',  wants = 2, hot = 0.25 },
        { id = 'specialist', label = 'Specialist Dealer', offer = { 1.22, 1.35 }, dist = 'far',  wants = 2, hot = 0.45 },
    },
    -- Things a buyer can ask for. Matching each one adds a bonus.
    Wants = {
        { id = 'matte',   label = 'Matte finish',     bonus = 0.06 },
        { id = 'chrome',  label = 'Chrome finish',    bonus = 0.08 },
        { id = 'pearl',   label = 'Pearlescent paint',bonus = 0.05 },
        { id = 'turbo',   label = 'Turbo installed',  bonus = 0.06 },
        { id = 'engine',  label = 'Max engine',       bonus = 0.07 },
        { id = 'neon',    label = 'Neon kit',         bonus = 0.04 },
        { id = 'tint',    label = 'Limo tint',        bonus = 0.03 },
        { id = 'wheels',  label = 'Custom wheels',    bonus = 0.04 },
        { id = 'armor',   label = 'Armor plating',    bonus = 0.05 },
        { id = 'mint',    label = 'Mint condition',   bonus = 0.07 },
        { id = 'stock',   label = 'Untouched stock',  bonus = 0.09 },
    },
}

--  ██████╗██████╗ ███████╗██╗    ██╗    ███████╗ █████╗ ██╗     ███████╗███████╗
-- ██╔════╝██╔══██╗██╔════╝██║    ██║    ██╔════╝██╔══██╗██║     ██╔════╝██╔════╝
-- ██║     ██████╔╝█████╗  ██║ █╗ ██║    ███████╗███████║██║     █████╗  ███████╗
-- ██║     ██╔══██╗██╔══╝  ██║███╗██║    ╚════██║██╔══██║██║     ██╔══╝  ╚════██║
-- ╚██████╗██║  ██║███████╗╚███╔███╔╝    ███████║██║  ██║███████╗███████╗███████║
--  ╚═════╝╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝     ╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝

-- The owner picks several cars in the Inventory and sells them in one deal.
-- Every car needs a driver from the crew inside the warehouse. Damage only
-- lowers the price of the car that took it, and a lost car doesn't kill the deal.
-- Nobody is paid until every car is dropped (or lost), then the crew watches
-- one shared handover and the money is split.
--   single = one buyer, every car to the same drop
--   split  = every car goes to its own drop, the handovers play together at the end
Config.CrewSale = {
    Enabled      = true,
    MinCars      = 2,
    MaxCars      = 4,
    Cut          = 0.10,          -- each crew member's share of the whole deal (the owner keeps the rest)
    VolumeBonus  = 0.04,          -- single buyer: +4% on every car for each car past the first
    SplitBonus   = { 1.02, 1.12 },-- split run: each car's buyer pays in this range
    AttackChance = 0.75,          -- each car in the convoy gets its own crew chasing it this often
    TimeLimit    = 20 * 60,
    DropRadius   = 14.0,          -- cars can park anywhere this close to the drop
    Cooldown     = 20 * 60,       -- owner's sale cooldown after a crew sale
    XpShare      = 0.60,          -- crew members get this share of the XP for each car that made it
}

-- ██╗███╗   ██╗███████╗██╗   ██╗██████╗  █████╗ ███╗   ██╗ ██████╗███████╗
-- ██║████╗  ██║██╔════╝██║   ██║██╔══██╗██╔══██╗████╗  ██║██╔════╝██╔════╝
-- ██║██╔██╗ ██║███████╗██║   ██║██████╔╝███████║██╔██╗ ██║██║     █████╗
-- ██║██║╚██╗██║╚════██║██║   ██║██╔══██╗██╔══██║██║╚██╗██║██║     ██╔══╝
-- ██║██║ ╚████║███████║╚██████╔╝██║  ██║██║  ██║██║ ╚████║╚██████╗███████╗
-- ╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝

-- Insure a stored car from the Inventory app. If it is lost (destroyed or
-- abandoned on a sale, or seized in a raid) the policy pays out once.
Config.Insurance = {
    Enabled = true,
    Premium = 0.06,     -- one-time cost: share of the car's current value
    Payout  = 0.60,     -- share of the car's value paid when it is lost
    Illegal = false,    -- illegal cars can't be insured
    Hot     = false,    -- cars flagged hot (tracked / stolen) can't be insured
}

-- ██████╗  █████╗ ██╗██████╗ ███████╗
-- ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝
-- ██████╔╝███████║██║██║  ██║███████╗
-- ██╔══██╗██╔══██║██║██║  ██║╚════██║
-- ██║  ██║██║  ██║██║██████╔╝███████║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═════╝ ╚══════╝

-- Storing cars builds heat on the warehouse. At the threshold a raid starts:
-- on-duty police get a warrant and can enter and seize cars, or with no
-- police online the cars are seized for you. Heat cools off every hour and
-- the owner can pay it down from the laptop (Overview app).
Config.Raids = {
    Enabled   = true,
    Heat      = { clean = 2, tracked = 8, stolen = 12, illegal = 20 },   -- heat added per car stored
    Decay     = 4,          -- heat lost per hour
    Warn      = 60,         -- your contact texts you a warning
    Threshold = 100,        -- a raid starts
    CheckEvery = 5 * 60,    -- seconds between raid checks
    Window    = 15 * 60,    -- how long the warrant is open for police
    MinPolice = 2,          -- fewer on duty = the NPC raid seizes cars on its own
    Seize     = 3,          -- most cars taken in an NPC raid (hot ones first)
    After     = 30,         -- heat left after a raid
    Bribe     = { Price = 1500, Step = 10 },   -- pay Price to drop Step heat
    PoliceReward = 0.05,    -- officer who seizes a car gets this share of its value (0 = off)
}

--  █████╗ ███████╗███████╗ ██████╗  ██████╗██╗ █████╗ ████████╗███████╗███████╗
-- ██╔══██╗██╔════╝██╔════╝██╔═══██╗██╔════╝██║██╔══██╗╚══██╔══╝██╔════╝██╔════╝
-- ███████║███████╗███████╗██║   ██║██║     ██║███████║   ██║   █████╗  ███████╗
-- ██╔══██║╚════██║╚════██║██║   ██║██║     ██║██╔══██║   ██║   ██╔══╝  ╚════██║
-- ██║  ██║███████║███████║╚██████╔╝╚██████╗██║██║  ██║   ██║   ███████╗███████║
-- ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝  ╚═════╝╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝

-- Co-op crew members.
Config.Associates = {
    Max       = 3,
    Cut       = 0.10,   -- each associate within CutRange of the drop gets this % (taken from the total)
    CutRange  = 60.0,
}

-- ██████╗  ██████╗ ██╗     ███████╗███████╗
-- ██╔══██╗██╔═══██╗██║     ██╔════╝██╔════╝
-- ██████╔╝██║   ██║██║     █████╗  ███████╗
-- ██╔══██╗██║   ██║██║     ██╔══╝  ╚════██║
-- ██║  ██║╚██████╔╝███████╗███████╗███████║
-- ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝

-- Every associate has a role the owner picks in the Associates app.
-- The owner can always do everything. Permissions:
--   contracts  take contracts          crewjob    start crew jobs
--   sell       sell / scrap cars        design     use the Design Bay
--   repair     repair cars              wash       clean cars
--   upgrades   buy upgrades             layout     change the floor plan
--   crew       invite / remove members  insurance  insure cars
--   bribe      pay off the police
Config.Roles = {
    Default = 'crew',   -- role new associates get
    List = {
        { id = 'manager',  label = 'Manager',  icon = 'fa-solid fa-user-tie', color = '#e5a50a',
          perms = { contracts = true, crewjob = true, sell = true, design = true, repair = true, wash = true, upgrades = true, layout = true, crew = true, insurance = true, bribe = true } },
        { id = 'driver',   label = 'Driver',   icon = 'fa-solid fa-car-side', color = '#08afa2',
          perms = { contracts = true, crewjob = true, sell = true } },
        { id = 'mechanic', label = 'Mechanic', icon = 'fa-solid fa-screwdriver-wrench', color = '#4fb3ff',
          perms = { crewjob = true, design = true, repair = true, wash = true, insurance = true } },
        { id = 'crew',     label = 'Crew',     icon = 'fa-solid fa-user', color = '#9ea5aa',
          perms = { contracts = true, crewjob = true } },
    },
}

--  ██████╗██████╗ ███████╗██╗    ██╗         ██╗ ██████╗ ██████╗ ███████╗
-- ██╔════╝██╔══██╗██╔════╝██║    ██║         ██║██╔═══██╗██╔══██╗██╔════╝
-- ██║     ██████╔╝█████╗  ██║ █╗ ██║         ██║██║   ██║██████╔╝███████╗
-- ██║     ██╔══██╗██╔══╝  ██║███╗██║    ██   ██║██║   ██║██╔══██╗╚════██║
-- ╚██████╗██║  ██║███████╗╚███╔███╔╝    ╚█████╔╝╚██████╔╝██████╔╝███████║
--  ╚═════╝╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝      ╚════╝  ╚═════╝ ╚═════╝ ╚══════╝

-- Multi-car contracts for the whole crew. Everyone inside the warehouse
-- (owner + associates) gets their own car from the same guarded lot.
-- All of them make it home = everyone gets the bonus.
Config.CrewJobs = {
    Enabled = true,
    MinCrew = 2,    -- people inside the warehouse to start one
    Jobs = {
        { id = 'convoy', label = 'Convoy Pull', icon = 'fa-solid fa-truck-fast', desc = 'Two cars from one lot. Each driver takes one home.',
          level = 6,  fee = 20000, cars = 2, rarity = 'rare', bonusCash = 15000, bonusXp = 180, cooldown = 30 * 60 },
        { id = 'fleet',  label = 'Fleet Heist', icon = 'fa-solid fa-people-group', desc = 'Up to four high-end cars from a heavily guarded lot.',
          level = 14, fee = 48000, cars = 4, rarity = 'epic', bonusCash = 40000, bonusXp = 360, cooldown = 60 * 60 },
    },
}

-- ██████╗ ███████╗██████╗  █████╗ ██╗██████╗ ███████╗
-- ██╔══██╗██╔════╝██╔══██╗██╔══██╗██║██╔══██╗██╔════╝
-- ██████╔╝█████╗  ██████╔╝███████║██║██████╔╝███████╗
-- ██╔══██╗██╔══╝  ██╔═══╝ ██╔══██║██║██╔══██╗╚════██║
-- ██║  ██║███████╗██║     ██║  ██║██║██║  ██║███████║
-- ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚══════╝

Config.Repair = {
    CostOfValue = 0.18,  -- a full repair (0% -> 100%) costs this share of the car's value
}

-- ██╗      █████╗ ██████╗ ████████╗ ██████╗ ██████╗
-- ██║     ██╔══██╗██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗
-- ██║     ███████║██████╔╝   ██║   ██║   ██║██████╔╝
-- ██║     ██╔══██║██╔═══╝    ██║   ██║   ██║██╔═══╝
-- ███████╗██║  ██║██║        ██║   ╚██████╔╝██║
-- ╚══════╝╚═╝  ╚═╝╚═╝        ╚═╝    ╚═════╝ ╚═╝

-- Third-eye the laptop in the office, the camera glides into the
-- screen and the business laptop opens.
Config.Laptop = {
    SpawnProp  = true,                     -- spawn a laptop prop at the laptop point (false if your interior has one)
    Model      = 'prop_laptop_01a',
    Anim       = { dict = 'anim@heists@prison_heiststation@cop_reactions', name = 'cop_b_idle' },
    CamDistance = 0.58,                    -- how close the camera ends up to the screen
    CamHeight   = 0.20,
    Transition  = 1200,                    -- ms for the camera glide
    Username    = 'player',                -- 'player' (character name) or a fixed string
    StandDistance = 0.75,                  -- you step in front of the laptop before the camera moves in
    FlipSide    = false,                   -- true if the camera ends up behind the screen with your laptop model

    -- The office desk already has a laptop in GTA's interior. These models are hidden
    -- near the laptop spots so only ours shows. Add a model here if yours still appears.
    HideRadius  = 2.5,
    HideModels  = {
        'imp_prop_impexp_lappy_01a', 'prop_laptop_01a', 'prop_laptop_02_closed', 'p_laptop_02_s', 'p_cs_laptop_02',
        'prop_laptop_lester', 'prop_laptop_lester2', 'prop_laptop_jimmy', 'hei_prop_hst_laptop', 'ex_prop_ex_laptop_01a',
        'bkr_prop_clubhouse_laptop_01a', 'xm_prop_x17_laptop_avon', 'xm_prop_x17_laptop_lester_01',
    },
}

-- ██████╗ ██████╗ ███████╗███████╗███████╗██████╗ ███████╗███╗   ██╗ ██████╗███████╗███████╗
-- ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗██╔════╝████╗  ██║██╔════╝██╔════╝██╔════╝
-- ██████╔╝██████╔╝█████╗  █████╗  █████╗  ██████╔╝█████╗  ██╔██╗ ██║██║     █████╗  ███████╗
-- ██╔═══╝ ██╔══██╗██╔══╝  ██╔══╝  ██╔══╝  ██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══╝  ╚════██║
-- ██║     ██║  ██║███████╗██║     ███████╗██║  ██║███████╗██║ ╚████║╚██████╗███████╗███████║
-- ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚══════╝

-- Each warehouse owner picks their own look from the laptop
-- Settings app. Saved on the warehouse, so associates see the
-- owner's laptop. The accent also colours that owner's HUD,
-- design bay menu and placement markers. Add your own colours.
Config.Prefs = {
    Accents = {
        { id = 'teal',   label = 'Teal',   color = '#08afa2' },
        { id = 'blue',   label = 'Blue',   color = '#3b82f6' },
        { id = 'violet', label = 'Violet', color = '#8b5cf6' },
        { id = 'pink',   label = 'Pink',   color = '#ec4899' },
        { id = 'red',    label = 'Red',    color = '#e5484d' },
        { id = 'orange', label = 'Orange', color = '#f97316' },
        { id = 'gold',   label = 'Gold',   color = '#eab308' },
        { id = 'lime',   label = 'Lime',   color = '#84cc16' },
        { id = 'mono',   label = 'Mono',   color = '#d9dde0' },
    },
    Finishes = {   -- laptop body
        { id = 'graphite', label = 'Graphite', a = '#17191b', b = '#0a0b0c' },
        { id = 'carbon',   label = 'Carbon',   a = '#0e0e0e', b = '#000000' },
        { id = 'silver',   label = 'Silver',   a = '#b9bec3', b = '#6c7277' },
        { id = 'midnight', label = 'Midnight', a = '#18203a', b = '#080b14' },
        { id = 'gold',     label = 'Gold',     a = '#b8975a', b = '#6a5428' },
        { id = 'rose',     label = 'Rose',     a = '#b98686', b = '#6c4646' },
    },
    Wallpapers = {
        { id = 'accent', label = 'Accent glow' },
        { id = 'grid',   label = 'Blueprint' },
        { id = 'night',  label = 'Night run' },
        { id = 'sunset', label = 'Sunset' },
        { id = 'carbon', label = 'Carbon' },
        { id = 'mono',   label = 'Mono' },
    },
    Default = {
        accent    = 'teal',
        finish    = 'graphite',
        wallpaper = 'accent',
        clock     = '12',      -- '12' | '24'
        fastboot  = false,     -- skip the boot + sign-in screens
        sounds    = true,      -- laptop click and notification sounds
        glass     = true,      -- see-through windows and taskbar
        radio     = true,      -- crew radio during jobs (see Config.Radio)
    },
}

-- ██████╗  █████╗ ██████╗ ██╗ ██████╗
-- ██╔══██╗██╔══██╗██╔══██╗██║██╔═══██╗
-- ██████╔╝███████║██║  ██║██║██║   ██║
-- ██╔══██╗██╔══██║██║  ██║██║██║   ██║
-- ██║  ██║██║  ██║██████╔╝██║╚██████╔╝
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝ ╚═════╝

-- When a contract or sale starts, the crew is put on a private
-- voice radio channel and moved back to their old channel after.
-- Channel = Base + warehouse id, so pick a range no job uses.
-- Owners can turn it off for their warehouse in laptop Settings.
Config.Radio = {
    Enabled = true,
    System  = 'auto',     -- 'auto' | 'pma-voice' | 'saltychat' | 'tokovoip' | 'custom' (edit bridge/client.lua)
    Base    = 750,
    Who     = 'crew',     -- 'crew' = owner + associates online · 'nearby' = crew within Range of the driver · 'runner' = driver only
    Range   = 250.0,
    Restore = true,       -- put players back on the channel they were on
}

-- ██████╗ ██╗      █████╗  ██████╗███████╗███╗   ███╗███████╗███╗   ██╗████████╗
-- ██╔══██╗██║     ██╔══██╗██╔════╝██╔════╝████╗ ████║██╔════╝████╗  ██║╚══██╔══╝
-- ██████╔╝██║     ███████║██║     █████╗  ██╔████╔██║█████╗  ██╔██╗ ██║   ██║
-- ██╔═══╝ ██║     ██╔══██║██║     ██╔══╝  ██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║
-- ██║     ███████╗██║  ██║╚██████╗███████╗██║ ╚═╝ ██║███████╗██║ ╚████║   ██║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝

-- Admin setup, owner layouts and the tracker spot.
-- Aim with your camera: points show a cylinder with a line to it,
-- car spots show a ghost car. Scroll to rotate.
Config.Placer = {
    Distance   = 30.0,    -- how far the aim reaches
    Step       = 10.0,    -- degrees per scroll notch
    FineStep   = 2.0,     -- degrees per notch while holding SHIFT
    GhostModel = 'sultan',
}

-- ██████╗ ██████╗  ██████╗ ██╗  ██╗███████╗██████╗
-- ██╔══██╗██╔══██╗██╔═══██╗██║ ██╔╝██╔════╝██╔══██╗
-- ██████╔╝██████╔╝██║   ██║█████╔╝ █████╗  ██████╔╝
-- ██╔══██╗██╔══██╗██║   ██║██╔═██╗ ██╔══╝  ██╔══██╗
-- ██████╔╝██║  ██║╚██████╔╝██║  ██╗███████╗██║  ██║
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

-- The NPC that sells warehouses.
-- Positions live in config/locations.lua and can be moved in game
-- from /cargoadmin → Broker.
Config.Broker = {
    Model    = 'a_m_y_business_02',
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    Blip     = { sprite = 474, colour = 2, scale = 0.7, label = 'Warehouse Broker' },
}

-- ██████╗  ██████╗  ██████╗ ██████╗ ███████╗
-- ██╔══██╗██╔═══██╗██╔═══██╗██╔══██╗██╔════╝
-- ██║  ██║██║   ██║██║   ██║██████╔╝███████╗
-- ██║  ██║██║   ██║██║   ██║██╔══██╗╚════██║
-- ██████╔╝╚██████╔╝╚██████╔╝██║  ██║███████║
-- ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

Config.Doors = {
    Knock        = true,     -- non-owners can knock; anyone inside can let them in
    KnockTimeout = 20,       -- seconds the owner has to answer
    GarageExit   = true,     -- "Exit through the garage" option inside
}

-- Logging back in inside the interior (server restart, relog, character switch).
-- Works with any multicharacter: the resource remembers which warehouse each
-- character was in and checks where they spawned once they load in.
Config.Resume = {
    Enabled       = true,    -- turn off if another script also uses the Import/Export warehouse interior
    PutBackInside = true,    -- true = back into their own warehouse, false = always out the front door
    -- Guests, police and anyone whose warehouse is gone are walked out the front door.
}

-- ██╗  ██╗██╗   ██╗██████╗
-- ██║  ██║██║   ██║██╔══██╗
-- ███████║██║   ██║██║  ██║
-- ██╔══██║██║   ██║██║  ██║
-- ██║  ██║╚██████╔╝██████╔╝
-- ╚═╝  ╚═╝ ╚═════╝ ╚═════╝

Config.Hud = {
    Command = 'cargohud',    -- move the HUD with the mouse, saved per player
}

-- ███╗   ███╗██╗   ██╗███████╗██╗ ██████╗
-- ████╗ ████║██║   ██║██╔════╝██║██╔════╝
-- ██╔████╔██║██║   ██║███████╗██║██║
-- ██║╚██╔╝██║██║   ██║╚════██║██║██║
-- ██║ ╚═╝ ██║╚██████╔╝███████║██║╚██████╗
-- ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝ ╚═════╝

-- 'native' plays GTA's own Import/Export score from the player's
-- game files (nothing is streamed or shipped).
-- 'custom' plays your own files from web/sounds/ through the UI.
Config.Music = {
    Enabled   = true,
    Mode      = 'native',     -- 'native' | 'custom' | 'off'
    RadioOff  = true,         -- turn the radio off in mission vehicles so the score is heard
    Native = {
        start      = 'IE_START_MUSIC',
        delivering = 'IE_DELIVERING_IDLE',
        attack     = 'IE_DELIVERING_ATTACK',
        countdown  = 'IE_COUNTDOWN_30S',
        countdownKill = 'IE_COUNTDOWN_30S_KILL',
        finish     = 'IE_END_MUSIC',
        fail       = 'IE_FAIL',
        radio      = 'IE_FADE_IN_RADIO',
    },
    Custom = {
        Volume = 0.35,
        start      = 'start.ogg',
        delivering = 'delivering.ogg',
        attack     = 'attack.ogg',
        countdown  = 'countdown.ogg',
        finish     = 'finish.ogg',
        fail       = 'fail.ogg',
    },
}

-- ██╗███╗   ██╗████████╗███████╗██████╗  █████╗  ██████╗████████╗
-- ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
-- ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝███████║██║        ██║
-- ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██╔══██║██║        ██║
-- ██║██║ ╚████║   ██║   ███████╗██║  ██║██║  ██║╚██████╗   ██║
-- ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝

-- Used when Config.Target is 'textui'.
Config.Interact = {
    Key       = 38,       -- E
    KeyLabel  = 'E',
    Distance  = 2.0,
    SpecDistance = 4.5,   -- walk this close to a parked car to see its spec card
    Blips     = true,     -- blips for warehouses you own or can enter
    BlipSprite = 524,
    BlipColour = 2,
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

Config.Logs = {
    Webhook = '',         -- Discord webhook URL, leave empty to disable
    Color   = 569250,     -- #08afa2
}
