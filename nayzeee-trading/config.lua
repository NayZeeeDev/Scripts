Config = {}

-- ═══════════════════════════════════════════════════════════════
-- GENERAL
-- ═══════════════════════════════════════════════════════════════

Config.Framework = 'auto'   -- 'auto' | 'esx' | 'qb' | 'qbx' | 'standalone'
Config.Debug = false

Config.UI = {
    brand    = 'NZ Trader',
    company  = 'Nayzeee Securities',
    sub      = 'Brokerage · Los Santos',
    version  = '4.0.0',
    notify   = 'nui',        -- 'nui' (styled toasts) or 'ox' (ox_lib notify)
}

-- Open the tablet without an item (admin / testing). Set to false to disable.
Config.Command = 'trading'
Config.CommandRequiresItem = true

-- ═══════════════════════════════════════════════════════════════
-- DEVICES
-- ═══════════════════════════════════════════════════════════════

Config.Laptop = {
    item           = 'trading_laptop',
    model          = 'prop_laptop_01a',
    maxPerPlayer   = 2,
    placeDistance  = 3.0,     -- max distance from the player while placing
    rotateStep     = 7.5,     -- degrees per scroll notch (hold SHIFT for fine rotation)
    streamDistance = 60.0,    -- placed laptops spawn within this range
    interactRange  = 1.6,
    anyoneCanPickup = false,  -- false = only the owner can pick it up
    anyoneCanUse    = true,   -- false = only the owner can log in

    -- Camera zoom into the screen. Offsets are relative to the laptop model.
    -- Tweak these if you swap the model for one with a different screen position.
    camera = {
        offset = vec3(0.0, -0.52, 0.30),
        target = vec3(0.0, 0.06, 0.13),
        fov    = 42.0,
        ease   = 1100,        -- ms
    },

    walkToLaptop = true,
    standOffset  = vec3(0.0, -0.72, 0.0),
    anim = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle' },
}

Config.Tablet = {
    item  = 'trading_tablet',
    model = 'prop_cs_tablet',
    bone  = 28422,
    pos   = vec3(0.0, -0.03, 0.0),
    rot   = vec3(20.0, -90.0, 0.0),
    anim  = { dict = 'amb@world_human_tourist_map@male@base', clip = 'base' },
}

-- Fixed desk terminals (no item needed). Uses ox_target / qb-target when available.
Config.Terminals = {
    {
        coords = vec3(-1298.67, -835.32, 16.95),
        radius = 1.2,
        label  = 'Trading Terminal',
        blip   = { sprite = 431, color = 2, scale = 0.8, label = 'Stock Exchange' },
    },
}

-- ═══════════════════════════════════════════════════════════════
-- ACCOUNTS
-- ═══════════════════════════════════════════════════════════════

Config.Practice = {
    startingCash  = 100000,
    resetCooldown = 30,       -- minutes between practice resets
}

Config.Live = {
    enabled      = true,      -- forced off in standalone mode
    moneyAccount = 'bank',
    minDeposit   = 100,
    maxDeposit   = 2500000,
}

Config.Trading = {
    leverage       = 2.0,     -- buying power = equity × leverage
    maintenance    = 0.25,    -- auto-liquidate when equity < 25% of gross exposure
    allowShort     = true,
    shortCrypto    = true,
    maxWorking     = 25,      -- working orders per account
    maxNotional    = 5000000, -- largest single order value
    cryptoDecimals = 4,
    slippage       = true,    -- large market orders walk the book
}

Config.Fees = {
    stock  = { perShare = 0.005, min = 1.00, maxPct = 0.005 },
    crypto = { pct = 0.0015 },
}

Config.MaxAlerts = 15

-- ═══════════════════════════════════════════════════════════════
-- MARKET SIMULATION
-- ═══════════════════════════════════════════════════════════════

Config.Market = {
    tickMs         = 1000,
    horizonMinutes = 90,      -- a symbol's daily volatility plays out over this many real minutes
    keep5s         = 720,     -- 1 hour of 5-second candles
    keep1m         = 600,     -- 10 hours of 1-minute candles
    saveInterval   = 60,      -- seconds between price snapshots to the database

    hours = {
        enabled   = false,    -- false = 24/7 market (recommended for RP)
        utcOffset = -5,       -- server timezone offset used for the session clock
        pre       = 7,
        open      = 9.5,
        close     = 16,
        post      = 20,
        weekends  = false,
    },
    rolloverHour = 4,         -- new trading day starts at this hour (prev close, day P&L reset)

    halts = { enabled = true, percent = 0.10, window = 300, duration = 60 },
}

Config.Exchanges = { stock = 'BAWSAQ', crypto = 'CRYPTO', index = 'INDEX' }

-- type: 'stock' | 'crypto' | 'index'
-- vol  = daily volatility, beta = sensitivity to the market factor
-- Indices with `members` track their constituents; others are simulated.
Config.Symbols = {
    { symbol = 'GLBL',  name = 'Global 500',           type = 'index', price = 6581.00,  members = 'all' },
    { symbol = 'TECH',  name = 'Tech Composite',       type = 'index', price = 24015.36, members = { 'tech' } },
    { symbol = 'INDX',  name = 'Industrial Average',   type = 'index', price = 46416.03, members = { 'finance', 'transport', 'energy', 'consumer', 'retail' } },
    { symbol = 'FEAR',  name = 'Fear & Volatility',    type = 'index', price = 16.50,    vol = 0.09, beta = -4.0 },

    { symbol = 'FRUT',  name = 'Fruit Computers',      sector = 'tech',      price = 251.49, vol = 0.024, beta = 1.15 },
    { symbol = 'WHIZ',  name = 'Whiz Wireless',        sector = 'tech',      price = 341.82, vol = 0.035, beta = 1.30 },
    { symbol = 'BNKU',  name = 'BetterNet Corp',       sector = 'tech',      price = 425.50, vol = 0.026, beta = 1.10 },
    { symbol = 'FACI',  name = 'Facade Social',        sector = 'tech',      price = 580.20, vol = 0.032, beta = 1.25 },
    { symbol = 'SEAR',  name = 'Sear Search',          sector = 'tech',      price = 175.30, vol = 0.022, beta = 1.05 },
    { symbol = 'TNK',   name = 'Tinkle Mobile',        sector = 'tech',      price = 48.20,  vol = 0.045, beta = 1.40 },

    { symbol = 'MAZE',  name = 'Maze Bank',            sector = 'finance',   price = 245.00, vol = 0.020, beta = 1.00 },
    { symbol = 'FLEE',  name = 'Fleeca',               sector = 'finance',   price = 112.50, vol = 0.022, beta = 1.05 },
    { symbol = 'BOL',   name = 'Bank of Liberty',      sector = 'finance',   price = 89.30,  vol = 0.019, beta = 0.95 },

    { symbol = 'LIFE',  name = 'LifeInvader',          sector = 'media',     price = 12.75,  vol = 0.070, beta = 1.60 },
    { symbol = 'CNT',   name = 'CNT Network',          sector = 'media',     price = 45.60,  vol = 0.030, beta = 0.90 },
    { symbol = 'WZL',   name = 'Weazel Media',         sector = 'media',     price = 67.80,  vol = 0.034, beta = 0.95 },

    { symbol = 'FLY',   name = 'FlyUS Airlines',       sector = 'transport', price = 28.50,  vol = 0.040, beta = 1.30 },
    { symbol = 'VAPD',  name = 'Vapid Motors',         sector = 'transport', price = 89.30,  vol = 0.030, beta = 1.10 },
    { symbol = 'DNKA',  name = 'Dinka Automotive',     sector = 'transport', price = 156.00, vol = 0.026, beta = 1.00 },
    { symbol = 'PFST',  name = 'Pfister AG',           sector = 'transport', price = 320.00, vol = 0.028, beta = 1.05 },

    { symbol = 'RON',   name = 'RON Oil',              sector = 'energy',    price = 78.90,  vol = 0.030, beta = 0.80 },
    { symbol = 'GLBO',  name = 'Globe Oil',            sector = 'energy',    price = 64.10,  vol = 0.032, beta = 0.85 },

    { symbol = 'LOGR',  name = 'Logger Beer',          sector = 'consumer',  price = 34.50,  vol = 0.020, beta = 0.70 },
    { symbol = 'ECLA',  name = 'eCola',                sector = 'consumer',  price = 52.30,  vol = 0.017, beta = 0.60 },
    { symbol = 'BURG',  name = 'Burger Shot',          sector = 'consumer',  price = 41.20,  vol = 0.024, beta = 0.75 },
    { symbol = 'CLCK',  name = 'Cluckin\' Bell',       sector = 'consumer',  price = 38.90,  vol = 0.026, beta = 0.80 },

    { symbol = 'AMMU',  name = 'Ammu-Nation',          sector = 'retail',    price = 156.00, vol = 0.030, beta = 0.90 },
    { symbol = 'BNCO',  name = 'Binco',                sector = 'retail',    price = 23.40,  vol = 0.036, beta = 1.10 },
    { symbol = 'PONS',  name = 'Ponsonbys',            sector = 'retail',    price = 118.40, vol = 0.025, beta = 1.00 },

    { symbol = 'SHRK',  name = 'Shark Cards Ltd',      sector = 'speculative', price = 42.69, vol = 0.090, beta = 1.80 },
    { symbol = 'MNDO',  name = 'Mundo Dinero',         sector = 'speculative', price = 18.88, vol = 0.080, beta = 1.70 },

    { symbol = 'BKC',   name = 'BlockCoin',            type = 'crypto', price = 68421.50, vol = 0.035, beta = 1.00 },
    { symbol = 'ETRM',  name = 'Ethereum Max',         type = 'crypto', price = 3845.20,  vol = 0.045, beta = 1.20 },
    { symbol = 'LSC',   name = 'LS Chain',             type = 'crypto', price = 142.80,   vol = 0.060, beta = 1.40 },
    { symbol = 'VNTR',  name = 'VentureCoin',          type = 'crypto', price = 12.35,    vol = 0.075, beta = 1.50 },
    { symbol = 'DGEN',  name = 'DegenCoin',            type = 'crypto', price = 0.4200,   vol = 0.120, beta = 2.00 },
    { symbol = 'NFTX',  name = 'NFT Exchange',         type = 'crypto', price = 5.6700,   vol = 0.100, beta = 1.80 },
}

-- ═══════════════════════════════════════════════════════════════
-- NEWS & EARNINGS
-- ═══════════════════════════════════════════════════════════════

Config.News = {
    interval = { 90, 240 },   -- seconds between headlines
    templates = {
        -- company news: %s = company name
        { text = '%s beats revenue expectations on strong demand',        impact =  0.05, sectors = { 'tech', 'consumer', 'retail', 'finance' } },
        { text = '%s announces multi-year partnership deal',              impact =  0.04, sectors = { 'tech', 'transport', 'energy', 'media' } },
        { text = 'Analysts upgrade %s to Strong Buy, raise price target', impact =  0.035, sectors = { 'tech', 'finance', 'transport', 'retail' } },
        { text = '%s unveils $5B share buyback program',                  impact =  0.03, sectors = { 'tech', 'finance', 'energy' } },
        { text = '%s wins state contract worth $2B',                      impact =  0.06, sectors = { 'tech', 'transport', 'energy' } },
        { text = 'Unusual call buying spotted in %s',                     impact =  0.025, sectors = { 'tech', 'speculative', 'media', 'retail' } },
        { text = 'Retail traders pile into %s, shares squeeze higher',    impact =  0.09, sectors = { 'speculative', 'media' } },
        { text = '%s launches flagship product to rave reviews',          impact =  0.045, sectors = { 'tech', 'consumer', 'retail' } },
        { text = '%s expands into Liberty City market',                   impact =  0.03, sectors = { 'retail', 'consumer', 'finance' } },
        { text = '%s misses guidance, cuts full-year outlook',            impact = -0.06, sectors = { 'tech', 'consumer', 'retail', 'finance' } },
        { text = 'SEC opens investigation into %s accounting',            impact = -0.08, sectors = { 'finance', 'tech', 'speculative' } },
        { text = '%s announces layoffs amid restructuring',               impact = -0.035, sectors = { 'tech', 'media', 'transport' } },
        { text = 'Data breach exposes millions of %s customers',          impact = -0.06, sectors = { 'tech', 'finance', 'media' } },
        { text = 'Analysts downgrade %s to Sell on valuation',            impact = -0.035, sectors = { 'tech', 'finance', 'transport', 'retail' } },
        { text = '%s CEO resigns unexpectedly',                           impact = -0.07, sectors = { 'tech', 'finance', 'media', 'speculative' } },
        { text = 'Supply chain disruption hits %s',                       impact = -0.04, sectors = { 'transport', 'consumer', 'retail', 'energy' } },
        { text = '%s recalls flagship product line',                      impact = -0.05, sectors = { 'consumer', 'transport', 'tech' } },
        { text = 'Short seller report targets %s',                        impact = -0.09, sectors = { 'speculative', 'tech', 'media' } },

        -- crypto
        { text = '%s network upgrade goes live without issues',           impact =  0.07, sectors = { 'crypto' } },
        { text = 'Major exchange lists %s',                               impact =  0.08, sectors = { 'crypto' } },
        { text = 'Whale wallet dumps %s on the open market',              impact = -0.09, sectors = { 'crypto' } },
        { text = 'Smart contract exploit drains %s liquidity pool',       impact = -0.12, sectors = { 'crypto' } },

        -- macro: moves the whole market (beta-weighted)
        { text = 'Fed signals rate cuts ahead; equities rally',           impact =  0.012, scope = 'market' },
        { text = 'Jobs report blows past estimates',                      impact =  0.008, scope = 'market' },
        { text = 'Inflation runs hotter than expected',                   impact = -0.012, scope = 'market' },
        { text = 'San Andreas unemployment ticks higher',                 impact = -0.008, scope = 'market' },
        { text = 'Crypto ETF approval rumours sweep the market',          impact =  0.03,  scope = 'crypto' },
        { text = 'Regulators announce crypto exchange crackdown',         impact = -0.035, scope = 'crypto' },
    },
}

Config.Earnings = {
    enabled    = true,
    schedule   = { 240, 540 },  -- seconds between new calendar entries
    lead       = { 240, 600 },  -- countdown before the report hits
    move       = { 0.03, 0.12 },
    beatChance = 0.55,
    maxPending = 4,
}
