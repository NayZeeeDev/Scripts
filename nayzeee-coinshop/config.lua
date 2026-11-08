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
