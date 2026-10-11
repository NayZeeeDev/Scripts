--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
    ████████╗██╗   ██╗███╗   ██╗██╗███╗   ██╗ ██████╗
    ╚══██╔══╝██║   ██║████╗  ██║██║████╗  ██║██╔════╝
       ██║   ██║   ██║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
       ██║   ██║   ██║██║╚██╗██║██║██║╚██╗██║██║   ██║
       ██║   ╚██████╔╝██║ ╚████║██║██║ ╚████║╚██████╔╝
       ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝

    nayzeee-tuning  v1.0.0  |  NayZeee Development
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
Config.Debug     = false            -- prints extra info to the F8 / server console
Config.Locale    = 'en'             -- file in locales/ to use

Config.Framework = 'auto'           -- 'auto' | 'esx' | 'qb' | 'qbx'
Config.Target    = 'auto'           -- 'auto' | 'ox_target' | 'qb-target' | 'none' (none = [E] prompts)
Config.Notify    = 'ox_lib'         -- 'ox_lib' | 'framework' | 'custom' (edit Bridge.Notify in bridge/client.lua)
Config.TextUI    = 'ox_lib'         -- 'ox_lib' | 'custom' (edit Bridge.TextUI in bridge/client.lua)

Config.Keys = {
    Interact      = 38,             -- E  (bays, stockpiles, install spots)
    Nitrous       = 'LSHIFT',       -- hold to boost (keybind, players can rebind in settings)
    Purge         = 'X',            -- hold to purge nitrous while slow / stopped
    AirRideUp     = 'PAGEUP',       -- raise air ride one preset
    AirRideDown   = 'PAGEDOWN',     -- lower air ride one preset
    CancelInstall = 'BACK',         -- abandon the current installation step
}

-- ███████╗ ██████╗ ██████╗ ███╗   ██╗ ██████╗ ███╗   ███╗██╗   ██╗
-- ██╔════╝██╔════╝██╔═══██╗████╗  ██║██╔═══██╗████╗ ████║╚██╗ ██╔╝
-- █████╗  ██║     ██║   ██║██╔██╗ ██║██║   ██║██╔████╔██║ ╚████╔╝
-- ██╔══╝  ██║     ██║   ██║██║╚██╗██║██║   ██║██║╚██╔╝██║  ╚██╔╝
-- ███████╗╚██████╗╚██████╔╝██║ ╚████║╚██████╔╝██║ ╚═╝ ██║   ██║
-- ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝   ╚═╝

Config.Economy = {
    PriceSource         = 'config',     -- 'config' (Config.VehiclePrices) | 'database' (ESX vehicles / QB shared) | 'both'
    DefaultVehiclePrice = 60000,        -- used when a model has no price anywhere
    MinVehiclePrice     = 15000,        -- floor so cheap cars still pay sensible prices
    MaxVehiclePrice     = 2500000,      -- ceiling so hypercars don't cost millions per spoiler
    TaxPercent          = 0,            -- added on top of the subtotal (0 = off)
    LaborPerItem        = 150,          -- flat labour fee per installed item (0 = off)
    RemovalFee          = 250,          -- price to return a part to stock
    PaymentMethods      = { 'bank', 'cash' },   -- order shown at checkout; first is default
    ShowPricesToCustomers = true,       -- false hides prices from non-employees in mechanic shops

    Components = {
        Enabled   = false,              -- allow paying with the component item (scrapyard economy)
        Item      = 'tuning_component', -- item name
        Value     = 450,                -- $ covered by one component
    },
}

-- ██╗   ██╗███████╗██╗  ██╗██╗ ██████╗██╗     ███████╗███████╗
-- ██║   ██║██╔════╝██║  ██║██║██╔════╝██║     ██╔════╝██╔════╝
-- ██║   ██║█████╗  ███████║██║██║     ██║     █████╗  ███████╗
-- ╚██╗ ██╔╝██╔══╝  ██╔══██║██║██║     ██║     ██╔══╝  ╚════██║
--  ╚████╔╝ ███████╗██║  ██║██║╚██████╗███████╗███████╗███████║
--   ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝╚══════╝╚══════╝╚══════╝

Config.Ownership = {
    OnlyOwnerCanTune   = true,          -- self-service & orders require the vehicle to be owned by the payer
    AllowUnownedPreview= true,          -- non-owners may still browse / preview
    BlacklistedPlates  = { 'ADMINCAR' },
    BlacklistedModels  = { },           -- e.g. 'rhino'
    BlockedClasses     = { [14] = true, [15] = true, [16] = true, [21] = true }, -- boats, helis, planes, trains
    MotorcycleWheelsOnly = true,        -- bikes may only pick from the motorcycle rim set
}

-- Price of a vehicle is the base every multiplier in config.parts.lua is applied to.
-- Anything not listed falls back to the database (if PriceSource allows) and then DefaultVehiclePrice.
Config.VehiclePrices = {
    adder = 1000000, zentorno = 725000, t20 = 1100000, turismor = 500000, entityxf = 795000,
    italigtb = 1189000, krieger = 2200000, emerus = 2750000, sultan = 12000, sultanrs = 795000,
    kuruma = 95000, elegy = 95000, elegy2 = 95000, jester = 240000, comet2 = 100000,
    futo = 9000, futo2 = 110000, zr350 = 1615000, euros = 1800000, calico = 1995000,
    dominator = 35000, gauntlet = 32000, buffalo = 35000, buffalo2 = 96000, banshee = 105000,
    blista = 16000, panto = 85000, faggio = 5000, bati = 15000, akuma = 9000,
}

-- ██████╗ ██╗      █████╗ ████████╗███████╗███████╗
-- ██╔══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔════╝
-- ██████╔╝██║     ███████║   ██║   █████╗  ███████╗
-- ██╔═══╝ ██║     ██╔══██║   ██║   ██╔══╝  ╚════██║
-- ██║     ███████╗██║  ██║   ██║   ███████╗███████║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝

Config.Plates = {
    Enabled          = true,
    MinLength        = 2,
    MaxLength        = 8,
    AllowedPattern   = '^[A-Z0-9 ]+$',  -- Lua pattern checked after upper-casing
    BlockedWords     = { 'ADMIN', 'POLICE', 'LSPD', 'BCSO', 'STAFF' },
    UpdateOwnedTable = true,            -- rewrite the plate in owned_vehicles / player_vehicles
    ExtraTables      = {                -- other tables with a plate column to keep in sync
        -- { table = 'trunk_inventory', column = 'plate' },
    },
    GiveKeys         = true,            -- hand out keys for the new plate (see bridge/server.lua)
}

-- Garages: tuning (engine sound, nitrous, stance...) is applied as soon as a garage hands the car over.
-- Works with any garage on its own; the events below make it instant for the ones that announce a take-out.
-- Your garage not listed? Add its client "vehicle taken out" event (first argument = the vehicle),
-- or call exports['nayzeee-tuning']:VehicleSpawned(vehicle) on the client right after it sets the plate.
Config.Garages = {
    Events = {
        'jg-advancedgarages:client:TakeOutVehicle:config',  -- JG Advanced Garages
    },
}

-- ██████╗ ██╗███████╗ ██████╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗     ██████╗ ██████╗ ██████╗ ███████╗███████╗
-- ██╔══██╗██║██╔════╝██╔════╝██╔═══██╗██║   ██║████╗  ██║╚══██╔══╝    ██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔════╝
-- ██║  ██║██║███████╗██║     ██║   ██║██║   ██║██╔██╗ ██║   ██║       ██║     ██║   ██║██║  ██║█████╗  ███████╗
-- ██║  ██║██║╚════██║██║     ██║   ██║██║   ██║██║╚██╗██║   ██║       ██║     ██║   ██║██║  ██║██╔══╝  ╚════██║
-- ██████╔╝██║███████║╚██████╗╚██████╔╝╚██████╔╝██║ ╚████║   ██║       ╚██████╗╚██████╔╝██████╔╝███████╗███████║
-- ╚═════╝ ╚═╝╚══════╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝        ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝

Config.Discounts = {
    Enabled        = true,
    CodeLength     = 8,
    Percentages    = { 5, 10, 15, 20, 25 },   -- choices in the boss menu
    Uses           = { 1, 3, 5, 10, 25 },     -- choices in the boss menu
    MaxActivePerShop = 25,
}

-- ██████╗ ██╗   ██╗███████╗██╗███╗   ██╗███████╗███████╗███████╗
-- ██╔══██╗██║   ██║██╔════╝██║████╗  ██║██╔════╝██╔════╝██╔════╝
-- ██████╔╝██║   ██║███████╗██║██╔██╗ ██║█████╗  ███████╗███████╗
-- ██╔══██╗██║   ██║╚════██║██║██║╚██╗██║██╔══╝  ╚════██║╚════██║
-- ██████╔╝╚██████╔╝███████║██║██║ ╚████║███████╗███████║███████║
-- ╚═════╝  ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝

Config.Business = {
    UseBuiltInBalance   = true,         -- keep the shop account inside nayzeee-tuning (false = society, see bridge)
    ShopCutSelfService  = 60,           -- % of a self-service sale that lands in the owning shop's account
    MechanicCommission  = 15,           -- default % of an order the installing mechanic receives
    CommissionRange     = { 0, 40 },    -- boss may move the commission within this range
    MarginRange         = { -15, 35 },  -- boss may move prices by this % for their shop
    MaxBonus            = 25000,        -- largest single employee bonus
    AnnouncementLength  = 280,
    OrderExpireHours    = 48,           -- unfinished orders are refunded after this
    NotifyMechanicsOnOrder = true,
    CustomerChoosesMode = true,     -- hybrid shops: customers pick Self-Service or Order while mechanics are on duty
    SelfServiceSurcharge = 15,      -- % added to self-service while mechanics are on duty (0 = off)
    LabourRateRange = { 0, 1500 },  -- boss can set the labour fee per part for their shop
}

-- Unlockable workshop equipment. When Enabled = false every shop has everything.
Config.ShopUpgrades = {
    Enabled = false,
    List = {
        performance_bench = { label = 'Performance Bench', icon = 'fa-gauge-high',   price = 150000, categories = { 'performance' } },
        paint_booth       = { label = 'Paint Booth',       icon = 'fa-spray-can',    price = 120000, categories = { 'paint' } },
        wheel_machine     = { label = 'Wheel Machine',     icon = 'fa-circle-dot',   price = 90000,  categories = { 'wheels', 'stance' } },
        ecu_bench         = { label = 'ECU Bench',         icon = 'fa-microchip',    price = 175000, items = { 'ecu', 'antilag', 'launch' } },
        nitrous_cert      = { label = 'Nitrous Licence',   icon = 'fa-fire-flame-simple', price = 110000, items = { 'nitrous' } },
        engine_hoist      = { label = 'Engine Hoist',      icon = 'fa-gears',        price = 200000, items = { 'engineSwap' } },
        airride_kit       = { label = 'Air Ride Station',  icon = 'fa-wind',         price = 85000,  items = { 'airride' } },
        two_post_lift     = { label = 'Two-Post Lift',     icon = 'fa-car-burst',    price = 130000, items = { 'drivetrain', 'gearbox', 'ceramic', 'driftKit', 'tyres' } },
    },
}

-- ████████╗ █████╗ ██████╗ ██╗     ███████╗████████╗
-- ╚══██╔══╝██╔══██╗██╔══██╗██║     ██╔════╝╚══██╔══╝
--    ██║   ███████║██████╔╝██║     █████╗     ██║
--    ██║   ██╔══██║██╔══██╗██║     ██╔══╝     ██║
--    ██║   ██║  ██║██████╔╝███████╗███████╗   ██║
--    ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝   ╚═╝

Config.Tablet = {
    Enabled   = true,
    Item      = 'mechanic_tablet',  -- usable item that opens it (false = command only)
    Command   = 'tablet',           -- false = item only
    CommandNeedsItem = true,
    Prop      = 'prop_cs_tablet',
    Anim      = { 'amb@code_human_in_bus_passenger_idles@female@tablet@base', 'base' },
    Accents   = { '#08afa2', '#e5484d', '#f59e0b', '#facc15', '#22c55e', '#3b82f6', '#8b5cf6', '#ec4899', '#f2f4f5' },
    AllowCustomWallpaper = false,   -- let players paste an image URL as wallpaper
    WallpaperHosts = { 'i.imgur.com', 'cdn.discordapp.com', 'media.discordapp.net', 'r2.fivemanage.com' },
    DiagnosticsNeedsScanner = false,-- employees scan without an obd_scanner item
    Brand     = 'PITWALL',          -- workshop app name in the tablet sidebar
    OSName    = 'NZ-OS',            -- shown in the status bar when you don't work at a shop
}

-- In-game shop editor: /mechaniceditor (place bays, desks, booths, racks, drop and truck points)
Config.Editor = {
    Enabled = true,
    Command = 'mechaniceditor',
    Ace     = nil,                  -- nil = Config.Admin.Ace
    WalkKey = 'F2',                 -- blur the editor to walk around, press again to edit (players can rebind it)
}

-- Discord profile pictures (animated ones too) on the tablet, messages, orders and employees.
-- Needs a bot token in server.cfg (never in this file, config files are sent to players):
--   set nayzeee_tuning_discord_token "YOUR_BOT_TOKEN"
-- The bot doesn't need to be in any server; it only reads public avatars. Players without Discord get initials.
Config.Discord = {
    Avatars      = true,
    Size         = 128,             -- 64 / 128 / 256
    Animated     = true,            -- use the .gif for animated (Nitro) avatars
    RefreshMinutes = 30,            -- how long an avatar is cached before asking Discord again
}

--  ██████╗ ██████╗ ██████╗ ███████╗██████╗ ███████╗
-- ██╔═══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔════╝
-- ██║   ██║██████╔╝██║  ██║█████╗  ██████╔╝███████╗
-- ██║   ██║██╔══██╗██║  ██║██╔══╝  ██╔══██╗╚════██║
-- ╚██████╔╝██║  ██║██████╔╝███████╗██║  ██║███████║
--  ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝

Config.Orders = {
    PhysicalInstall = true,             -- mechanics fetch parts from stockpiles and fit them at the car
    SkillChecks     = true,             -- ox_lib skill check on every install step
    Difficulty      = { 'easy', 'easy', 'medium' },
    WheelSteps      = 4,                -- wheel jobs visit each corner
    MaxDistanceFromCar = 25.0,          -- mechanic must stay near the car while an order is active
    QuoteTimeout    = 90,               -- seconds a customer has to accept a mechanic's quote
}

-- Bay claiming: mechanics reserve a bay as their own (tablet → My Bay, or G at a free bay).
-- Used by shops whose mode is listed below and that have at least MinBays bays.
-- A shop can force it on or off with claimBays = true / false (config.shops.lua or /mechaniceditor).
Config.Bays = {
    Claims         = true,
    Modes          = { mechanic = true, hybrid = true, self = false },
    MinBays        = 2,
    MaxPerMechanic = 1,                 -- bays one mechanic can hold at once
    MinRank        = 'access',          -- who can claim
    ManagersUseAny = true,              -- managers can work in and free any bay
    LockMechanicUse = true,             -- a claimed bay only opens the mechanic menu for its owner
    ShowName       = true,              -- owner's name floats over a claimed bay
    ClaimKey       = 47,                -- G at a free bay (on foot) claims it
}

-- ████████╗███████╗███████╗████████╗    ██████╗ ██████╗ ██╗██╗   ██╗███████╗
-- ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝    ██╔══██╗██╔══██╗██║██║   ██║██╔════╝
--    ██║   █████╗  ███████╗   ██║       ██║  ██║██████╔╝██║██║   ██║█████╗
--    ██║   ██╔══╝  ╚════██║   ██║       ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝
--    ██║   ███████╗███████║   ██║       ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗
--    ╚═╝   ╚══════╝╚══════╝   ╚═╝       ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝

Config.TestDrive = {
    Enabled  = true,
    Duration = 90,                      -- seconds
    Radius   = 350.0,                   -- leave this radius from the bay and the drive ends
}

-- ██████╗ ██╗   ██╗██╗██╗     ██████╗ ███████╗
-- ██╔══██╗██║   ██║██║██║     ██╔══██╗██╔════╝
-- ██████╔╝██║   ██║██║██║     ██║  ██║███████╗
-- ██╔══██╗██║   ██║██║██║     ██║  ██║╚════██║
-- ██████╔╝╚██████╔╝██║███████╗██████╔╝███████║
-- ╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═════╝ ╚══════╝

Config.Builds = {
    Enabled        = true,
    MaxPerPlayer   = 20,
    CodePrefix     = 'NZ',
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

Config.Webhooks = {
    Enabled = false,
    Default = '',                       -- fallback URL
    Events  = {                         -- per-event URL ('' = use Default, false = disabled)
        purchase = '', order = '', order_done = '', quote = '', bonus = '', hire = '', fire = '',
        grade = '', withdraw = '', deposit = '', code = '', upgrade = '', police = '', admin = '',
    },
    Color = 569250,                     -- #08afa2
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

Config.Admin = {
    Ace         = 'group.admin',        -- ace needed for admin commands / free tuning
    FreeCommand = 'admintune',          -- opens the menu anywhere with everything free
    CodeCommand = 'tunecode',           -- /tunecode [code|0] [shop|all] [percent] [uses]
    DelCodeCommand = 'deltunecode',     -- /deltunecode [code]
    ResetCommand= 'resettune',          -- /resettune  clears custom extras on the car you're in
}
