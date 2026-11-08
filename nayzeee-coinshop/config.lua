--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
     ██████╗ ██████╗ ██╗███╗   ██╗███████╗██╗  ██╗ ██████╗ ██████╗
    ██╔════╝██╔═══██╗██║████╗  ██║██╔════╝██║  ██║██╔═══██╗██╔══██╗
    ██║     ██║   ██║██║██╔██╗ ██║███████╗███████║██║   ██║██████╔╝
    ██║     ██║   ██║██║██║╚██╗██║╚════██║██╔══██║██║   ██║██╔═══╝
    ╚██████╗╚██████╔╝██║██║ ╚████║███████║██║  ██║╚██████╔╝██║
     ╚═════╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝
    nayzeee-coinshop · v1.0.0
    Discord: discord.gg/nayzeeedev  ·  Docs: nayzeee-dev.gitbook.io/docs

    Server-only settings (admins, webhooks, Discord bot token) live in server_config.lua
]]

Config = {}

Config.Debug  = false        -- Extra console output
Config.Locale = 'en'         -- File in locales/ (en.json)

-- ======================================================================
--   ___ ___ _  _ ___ ___    _   _
--  / __| __| \| | __| _ \  /_\ | |
-- | (_ | _|| .` | _||   / / _ \| |__
--  \___|___|_|\_|___|_|_\/_/ \_\____|
-- ======================================================================
Config.General = {
    Command        = 'coinshop',                             -- Command that opens the shop (false = off)
    Key            = 'F5',                                   -- Default keybind for the command (players can rebind)
    KeyDescription = 'Open Coin Shop',                       -- Label in FiveM keybind settings
    Item           = false,                                  -- Usable item that opens the shop, e.g. 'coinshop_tablet' (false = off)
    Blur           = true,                                   -- Blur the game behind the shop
    CoinName       = 'Coins',                                -- Currency name shown everywhere
    StoreUrl       = 'https://your-store.tebex.io',          -- Where players buy coin packages (shown on Tutorial + Redeem)
}

-- ======================================================================
--  _____ ___ ___ _____ ___  ___ _____   _____
-- |_   _| __/ __|_   _|   \| _ \_ _\ \ / / __|
--   | | | _|\__ \ | | | |) |   /| | \ V /| _|
--   |_| |___|___/ |_| |___/|_|_\___| \_/ |___|
-- ======================================================================
Config.TestDrive = {
    Enabled       = true,                                    -- Allow test driving vehicles before buying
    Duration      = 60,                                      -- Seconds
    Location      = vector4(-1639.68, -2647.89, 13.82, 330.0), -- Where the test drive happens
    SpawnDistance = 5.0,                                     -- Metres in front of the location
    Plate         = 'TESTDRV',                               -- Plate on test drive vehicles
    Isolate       = true,                                    -- Own routing bucket (nobody else sees you, no traffic)
    Cooldown      = 30,                                      -- Seconds between test drives
}

-- ======================================================================
-- __   _____ _  _ ___ ___ _    ___ ___
-- \ \ / / __| || |_ _/ __| |  | __/ __|
--  \ V /| _|| __ || | (__| |__| _|\__ \
--   \_/ |___|_||_|___\___|____|___|___/
-- ======================================================================
Config.Vehicles = {
    SpawnOnPurchase = true,                                  -- Spawn the vehicle next to the player after buying (false = straight to garage)
    SpawnDistance   = 5.0,                                   -- Metres in front of the player
    PlatePrefix     = 'NZ',                                  -- Generated plates: prefix + numbers (8 chars max)
    Garage          = 'pillboxgarage',                       -- Garage the vehicle is stored in (QBCore / Qbox)
    Type            = 'car',                                 -- ESX owned_vehicles.type
}

-- ======================================================================
-- __      _____   _   ___  ___  _  _ ___
-- \ \    / / __| /_\ | _ \/ _ \| \| / __|
--  \ \/\/ /| _| / _ \|  _/ (_) | .` \__ \
--   \_/\_/ |___/_/ \_\_|  \___/|_|\_|___/
-- ======================================================================
Config.Weapons = {
    Ammo = 250,                                              -- Ammo given with weapons (framework weapons, not inventory items)
}

-- ======================================================================
--   ___ ___ ___ _____ ___ _  _  ___
--  / __|_ _| __|_   _|_ _| \| |/ __|
-- | (_ || || _|  | |  | || .` | (_ |
--  \___|___|_|   |_| |___|_|\_|\___|
-- ======================================================================
Config.Gifting = {
    Items         = true,                                    -- Buy items / vehicles / deals for another online player
    CoinTransfer  = false,                                   -- Let players send coins to each other
    TransferFee   = 0,                                       -- % fee taken on coin transfers (0-50)
    TransferMin   = 10,                                      -- Smallest transfer
}

-- ======================================================================
--  ___ _      ___   _______ ___ __  __ ___
-- | _ \ |    /_\ \ / /_   _|_ _|  \/  | __|
-- |  _/ |__ / _ \ V /  | |  | || |\/| | _|
-- |_| |____/_/ \_\_|   |_| |___|_|  |_|___|
-- ======================================================================
Config.Playtime = {
    Enabled  = false,                                        -- Reward coins for time played (server side timer)
    Minutes  = 60,                                           -- Every X minutes online
    Coins    = 5,                                            -- Coins per reward
    DailyCap = 50,                                           -- Max playtime coins per player per day (0 = no cap)
}

-- ======================================================================
--  ___ _  _  ___  ___
-- / __| || |/ _ \| _ \
-- \__ \ __ | (_) |  _/
-- |___/_||_|\___/|_|
-- ======================================================================
Config.Shop = {
    MaxQuantity    = 25,                                     -- Highest amount of one item a player can buy at once (also the max per package in a bundle)
    DealMaxItems   = 10,                                     -- Max packages in one bundle
    HistorySize    = 50,                                     -- Rows in "My purchases"
    PurchaseDelay  = 750,                                    -- ms between purchases per player
}

-- ======================================================================
--  ___ _   _ _  _ ___  _    ___ ___
-- | _ ) | | | \| |   \| |  | __/ __|
-- | _ \ |_| | .` | |) | |__| _|\__ \
-- |___/\___/|_|\_|___/|____|___|___/
-- ======================================================================
-- Admins build bundles in the shop: Admin panel -> Bundles -> New bundle.
Config.Bundles = {
    CashAccount = 'bank',                                    -- Account the optional cash bonus goes to (ESX / QBCore / Qbox: 'bank' or 'money' / 'cash')
    MaxCash     = 10000000,                                  -- Highest cash bonus an admin can put in one bundle (0 = turn cash bonuses off)
    HeroSeconds = 7,                                         -- Seconds between featured bundles on the home page (0 = no auto rotate)
}

-- ======================================================================
--   ___ ___ ___ _  _   ___ _   ___ _  __  _   ___ ___ ___
--  / __/ _ \_ _| \| | | _ \ /_\ / __| |/ / /_\ / __| __/ __|
-- | (_| (_) | || .` | |  _// _ \ (__| ' < / _ \ (_ | _|\__ \
--  \___\___/___|_|\_| |_| /_/ \_\___|_|\_\/_/ \_\___|___|___/
-- ======================================================================
-- Shown on the "Get coins" page. Each tile opens your Tebex store:
--   id  = Tebex package ID (opens StoreUrl/package/<id>)   url = any full link instead   (neither = StoreUrl)
--   bonus = extra % already included in coins (just a label)   tag = 'popular' | 'best' | nil
Config.CoinPackages = {
    { coins = 500,   price = '$4.99',  id = 0, bonus = 0 },
    { coins = 1100,  price = '$9.99',  id = 0, bonus = 10 },
    { coins = 2400,  price = '$19.99', id = 0, bonus = 20, tag = 'popular' },
    { coins = 6500,  price = '$49.99', id = 0, bonus = 30, tag = 'best' },
}

-- ======================================================================
--  ___  _   _    ___ ___
-- / __|/_\ | |  | __/ __|
-- \__ \/ _ \| |__| _|\__ \
-- |___/_/ \_\____|___|___/
-- ======================================================================
-- Scheduled sales are created in the shop: Admin panel -> Sales.
Config.Sales = {
    MaxPercent = 90,                                         -- Highest % off an admin can set
}

-- ======================================================================
--  ___    _   _  _ _  _____
-- | _ \  /_\ | \| | |/ / __|
-- |   / / _ \| .` | ' <\__ \
-- |_|_\/_/ \_\_|\_|_|\_\___/
-- ======================================================================
-- Ranks come from the total coins a player has spent. Bonus = extra % coins on every Tebex order they redeem.
Config.Ranks = {
    Enabled = true,
    List = {
        { name = 'Bronze',  spent = 0,     bonus = 0,  color = '#c8834a', icon = 'fa-medal' },
        { name = 'Silver',  spent = 5000,  bonus = 5,  color = '#b9c3cc', icon = 'fa-medal' },
        { name = 'Gold',    spent = 20000, bonus = 10, color = '#e5b53a', icon = 'fa-crown' },
        { name = 'Diamond', spent = 50000, bonus = 15, color = '#5cd6f2', icon = 'fa-gem' },
    },
}

-- ======================================================================
--  ___   _   ___ _ __   __
-- |   \ /_\ |_ _| |\ \ / /
-- | |) / _ \ | || |_\ V /
-- |___/_/ \_\___|____|_|
-- ======================================================================
Config.Daily = {
    Enabled      = true,                                     -- Daily login reward (claimed in the shop under Rewards)
    Rewards      = { 5, 5, 10, 10, 15, 20, 50 },             -- Coins for day 1..7 of a streak, then it starts again at day 1
    ResetOnMiss  = true,                                     -- Missing a day starts the streak again at day 1
    NotifyOnJoin = true,                                     -- Tell players when their reward is ready after they load in
}

-- ======================================================================
--  __  __ ___ __  __ ___ ___ ___  ___ _  _ ___ ___  ___
-- |  \/  | __|  \/  | _ ) __| _ \/ __| || |_ _| _ \/ __|
-- | |\/| | _|| |\/| | _ \ _||   /\__ \ __ || ||  _/\__ \
-- |_|  |_|___|_|  |_|___/___|_|_\|___/_||_|___|_|  |___/
-- ======================================================================
-- Membership packages grant an ACE group for X days (e.g. group.vip). Buying again extends the time.
-- Needs these two lines in server.cfg so the shop may add / remove the group:
--   add_ace resource.nayzeee-coinshop command.add_principal allow
--   add_ace resource.nayzeee-coinshop command.remove_principal allow
Config.Memberships = {
    CheckEvery = 60,                                         -- Seconds between expiry checks
}

-- ======================================================================
--  ___ _  _  _____      _____  ___   ___  __  __
-- / __| || |/ _ \ \    / / _ \/ _ \ / _ \|  \/  |
-- \__ \ __ | (_) \ \/\/ /|   / (_) | (_) | |\/| |
-- |___/_||_|\___/ \_/\_/ |_|_\\___/ \___/|_|  |_|
-- ======================================================================
Config.Showroom = {
    Enabled  = true,                                         -- 3D preview button on vehicles
    Location = vector4(-1639.68, -2647.89, 13.82, 330.0),    -- Where the preview vehicle is placed (only you can see it)
    Time     = 12,                                           -- Hour of day while previewing (false = keep the real time)
    Colors   = {                                             -- Paint swatches { label, r, g, b }
        { 'White', 240, 240, 240 }, { 'Black', 12, 12, 14 }, { 'Silver', 150, 155, 160 }, { 'Red', 180, 16, 22 },
        { 'Orange', 230, 110, 20 }, { 'Yellow', 235, 190, 20 }, { 'Green', 20, 140, 70 }, { 'Teal', 8, 175, 162 },
        { 'Blue', 20, 60, 170 }, { 'Purple', 100, 40, 150 },
    },
}

-- ======================================================================
--  _   _ ___
-- | | | |_ _|
-- | |_| || |
--  \___/|___|
-- ======================================================================
Config.UI = {
    Scale    = 1.0,                                          -- Shop scale
    CoinIcon = '',                                           -- Coin icon image URL ('' = built-in coin). Admins can change it in Appearance
    Tutorial = {                                             -- Optional screenshots for the 3 tutorial steps ('' = icon)
        '', '', '',
    },
}
