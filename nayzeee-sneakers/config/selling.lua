--[[
    nayzeee-sneakers · selling: the Plug app, buyers, legit checks, meetups and the handover cinematic
]]

-- ███████╗███████╗██╗     ██╗     ██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔════╝██║     ██║     ██║████╗  ██║██╔════╝
-- ███████╗█████╗  ██║     ██║     ██║██╔██╗ ██║██║  ███╗
-- ╚════██║██╔══╝  ██║     ██║     ██║██║╚██╗██║██║   ██║
-- ███████║███████╗███████╗███████╗██║██║ ╚████║╚██████╔╝
-- ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

-- How it plays:
--   1. Open the Plug app, pick a pair from your Stash and hit "Find buyers".
--   2. Buyers DM you offers. Accept one and they send a meet spot (GPS set).
--   3. They walk up or pull up in a car. Target them: "Make the deal".
--   4. Handover cinematic. They look the pair over and pay up, or catch a fake and walk.
Config.Selling = {
    Account      = 'cash',          -- 'cash' | 'bank' (ESX 'cash' = money)
    MaxOffers    = 4,               -- offers waiting in the app at once
    OfferLife    = 10 * 60,         -- seconds before an offer expires
    FindDelay    = { 6, 20 },       -- seconds before buyers answer a "Find buyers"
    FindCooldown = 60,              -- seconds between "Find buyers" on the same pair
    FindCount    = { 1, 3 },        -- how many buyers answer
    Passive      = { Enabled = true, Every = 12 * 60, Chance = 0.4 },  -- random DMs for pairs in your pockets

    DealTime     = 12 * 60,         -- seconds to make the meet after accepting
    MeetDistance = { 250.0, 2200.0 },   -- meet spots this far from you are picked
    CancelRep    = 2,               -- rep lost for backing out of a deal
    Blip         = { sprite = 280, colour = 27 },   -- the meet spot on the map
    Cooldown     = 45,              -- seconds after a deal before you can accept the next one

    -- What a pair is worth: retail x hype x condition x dirt x box x size x buyer x rep
    Condition    = { DS = 1.00, VNDS = 0.82, USED = 0.58, BEAT = 0.32 },
    DirtPenalty  = 0.50,            -- 100% dirt takes this much off
    NoBox        = 0.86,            -- loose pairs sell for this share of boxed
    PopularSizes = {                -- these sizes sell a little higher, the rest a little lower
        male   = { '9', '9.5', '10', '10.5', '11' },
        female = { '6.5', '7', '7.5', '8' },
    },
    SizeBonus    = 1.06,
    SizeMalus    = 0.96,

    XP           = { Base = 15, Per100 = 2, Max = 120 },   -- 15 XP + 2 per $100, capped
}

-- ██████╗ ██╗   ██╗██╗   ██╗███████╗██████╗ ███████╗
-- ██╔══██╗██║   ██║╚██╗ ██╔╝██╔════╝██╔══██╗██╔════╝
-- ██████╔╝██║   ██║ ╚████╔╝ █████╗  ██████╔╝███████╗
-- ██╔══██╗██║   ██║  ╚██╔╝  ██╔══╝  ██╔══██╗╚════██║
-- ██████╔╝╚██████╔╝   ██║   ███████╗██║  ██║███████║
-- ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝

-- check   = chance they look the pair over at all
-- eye     = how good they are at spotting a fake by eye (vs. its quality)
-- serial  = chance they also run the serial (a fake's serial never passes)
-- offer   = share of the pair's value they pay
-- drive   = chance they pull up in a car instead of walking up
-- boxed / ds = only want boxed / deadstock pairs
Config.Buyers = {
    Types = {
        { id = 'casual',    label = 'Casual',    check = 0.20, eye = 0.55, serial = 0.00, offer = { 0.85, 1.00 }, drive = 0.30, weight = 40 },
        { id = 'hypebeast', label = 'Hypebeast', check = 0.65, eye = 0.80, serial = 0.10, offer = { 1.00, 1.18 }, drive = 0.50, weight = 30 },
        { id = 'reseller',  label = 'Reseller',  check = 1.00, eye = 0.90, serial = 0.45, offer = { 0.72, 0.88 }, drive = 0.75, weight = 20 },
        { id = 'collector', label = 'Collector', check = 0.95, eye = 1.00, serial = 0.80, offer = { 1.20, 1.45 }, drive = 0.90, weight = 10, boxed = true, ds = true },
    },
    Names = {
        'Jaylen', 'Marcus', 'Tyrese', 'Deshawn', 'Kenji', 'Mateo', 'Andre', 'Rico', 'Malik', 'Nico',
        'Aaliyah', 'Jade', 'Imani', 'Sofia', 'Kiara', 'Tasha', 'Mia', 'Zoe', 'Lena', 'Priya',
    },
    Models = {
        male   = { 'a_m_y_hipster_01', 'a_m_y_hipster_02', 'a_m_y_stbla_02', 'a_m_y_stwhi_01', 'a_m_y_vinewood_01', 'a_m_y_bevhills_02', 'a_m_y_skater_01', 'g_m_y_famca_01' },
        female = { 'a_f_y_hipster_01', 'a_f_y_hipster_02', 'a_f_y_vinewood_04', 'a_f_y_bevhills_02', 'a_f_y_genhot_01', 'a_f_y_scdressy_01' },
    },
    Cars = { 'sultan', 'kuruma', 'buffalo', 'baller', 'felon', 'tailgater', 'oracle', 'schafter2', 'dominator', 'jackal' },
    -- what they're doing while they wait (GTA scenarios, one at random)
    Idle = { 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_HANG_OUT_STREET', 'WORLD_HUMAN_LEANING', 'WORLD_HUMAN_AA_COFFEE' },
}

-- ██╗     ███████╗ ██████╗ ██╗████████╗
-- ██║     ██╔════╝██╔════╝ ██║╚══██╔══╝
-- ██║     █████╗  ██║  ███╗██║   ██║
-- ██║     ██╔══╝  ██║   ██║██║   ██║
-- ███████╗███████╗╚██████╔╝██║   ██║
-- ╚══════╝╚══════╝ ╚═════╝ ╚═╝   ╚═╝

-- When a buyer checks a pair:
--   serial check  -> a fake is always caught
--   eye check     -> caught with chance  eye x (100 - quality)% + Floor
Config.LegitCheck = {
    Floor = 0.03,                   -- even a 97% fake has this small chance to get spotted

    -- What happens when they catch a fake. The player keeps the pair.
    Caught = {
        Police     = 0.35,          -- chance they call it in (Config.Dispatch)
        Aggressive = 0.12,          -- chance they swing on you after
        Rep        = 8,             -- rep lost
    },
    -- A fake that gets through still counts as a sale (and the buyer never knows)
    FakeSoldRep = 1,
}

-- ███╗   ███╗███████╗███████╗████████╗██╗   ██╗██████╗ ███████╗
-- ████╗ ████║██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗██╔════╝
-- ██╔████╔██║█████╗  █████╗     ██║   ██║   ██║██████╔╝███████╗
-- ██║╚██╔╝██║██╔══╝  ██╔══╝     ██║   ██║   ██║██╔═══╝ ╚════██║
-- ██║ ╚═╝ ██║███████╗███████╗   ██║   ╚██████╔╝██║     ███████║
-- ╚═╝     ╚═╝╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ╚══════╝

-- Where buyers meet you. Add as many as you like; the z snaps to the ground.
Config.Meets = {
    { label = 'Legion Square garage',  coords = vector4(215.80, -810.10, 30.70, 157.0) },
    { label = 'Pillbox parking',       coords = vector4(-330.00, -780.30, 33.96, 41.0) },
    { label = 'Spanish Ave lot',       coords = vector4(-1160.90, -741.40, 19.60, 41.0) },
    { label = 'Vinewood lot',          coords = vector4(69.80, 12.60, 69.00, 160.0) },
    { label = 'Little Seoul lot',      coords = vector4(-453.70, -786.80, 30.60, 270.0) },
    { label = 'Vinewood Hills lot',    coords = vector4(364.40, 297.80, 103.50, 340.0) },
    { label = 'Airport parking',       coords = vector4(-796.90, -2024.90, 8.90, 50.0) },
    { label = 'Del Perro beach lot',   coords = vector4(-1183.10, -1511.10, 4.40, 300.0) },
    { label = 'Pink Cage motel',       coords = vector4(273.40, -343.60, 44.90, 160.0) },
    { label = 'Grove Street',          coords = vector4(105.00, -1940.00, 20.80, 50.0) },
}

--  ██████╗██╗███╗   ██╗███████╗███╗   ███╗ █████╗ ████████╗██╗ ██████╗
-- ██╔════╝██║████╗  ██║██╔════╝████╗ ████║██╔══██╗╚══██╔══╝██║██╔════╝
-- ██║     ██║██╔██╗ ██║█████╗  ██╔████╔██║███████║   ██║   ██║██║
-- ██║     ██║██║╚██╗██║██╔══╝  ██║╚██╔╝██║██╔══██║   ██║   ██║██║
-- ╚██████╗██║██║ ╚████║███████╗██║ ╚═╝ ██║██║  ██║   ██║   ██║╚██████╗
--  ╚═════╝╚═╝╚═╝  ╚═══╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝

-- The handover, shot like a movie: wide shot as you walk up, a close two-shot for the
-- swap, a close-up while they check the pair, then they walk or drive off.
Config.Cinematic = {
    Enabled   = true,
    Skip      = true,               -- ENTER / BACKSPACE skips it
    Subtitles = true,               -- buyer lines along the bottom
    Lines = {
        greet  = { 'You got them?', 'Let\'s see them.', 'Yo. These the ones?', 'Show me what you got.' },
        check  = { 'Hold up, let me look these over...', 'Give me a sec.', 'Stitching, glue, tongue tag...' },
        serial = { 'Running the serial real quick.', 'Let me check this tag.' },
        pass   = { 'Clean. Pleasure doing business.', 'These are legit. Here.', 'Fire. Cash is all there.' },
        fake   = { 'Nah. These are fake.', 'You tried it. These are reps.', 'Get these trash fakes out of my face.' },
    },
}

-- ██╗  ██╗██╗   ██╗██████╗ ███████╗
-- ██║  ██║╚██╗ ██╔╝██╔══██╗██╔════╝
-- ███████║ ╚████╔╝ ██████╔╝█████╗
-- ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══╝
-- ██║  ██║   ██║   ██║     ███████╗
-- ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚══════╝

-- Every model gets a demand multiplier that rerolls. The Plug app shows what's hot.
Config.Hype = {
    Enabled  = true,
    Range    = { 0.80, 1.55 },
    Hours    = 24,                  -- how often it rerolls (real hours)
    Trending = 3,                   -- how many "hot" models the app shows
}

-- ██████╗ ███████╗██████╗ ██╗   ██╗████████╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔══██╗██╔════╝██╔══██╗██║   ██║╚══██╔══╝██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██████╔╝█████╗  ██████╔╝██║   ██║   ██║   ███████║   ██║   ██║██║   ██║██╔██╗ ██║
-- ██╔══██╗██╔══╝  ██╔═══╝ ██║   ██║   ██║   ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
-- ██║  ██║███████╗██║     ╚██████╔╝   ██║   ██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
-- ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝    ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

Config.Rep = {
    Max        = 100,
    PerSale    = 2,                 -- clean sale
    PriceBonus = 0.20,              -- at max rep buyers pay 20% more
    MoreOffers = true,              -- more rep, more buyers answer
}

-- ██████╗  ██████╗ ██╗     ██╗ ██████╗███████╗
-- ██╔══██╗██╔═══██╗██║     ██║██╔════╝██╔════╝
-- ██████╔╝██║   ██║██║     ██║██║     █████╗
-- ██╔═══╝ ██║   ██║██║     ██║██║     ██╔══╝
-- ██║     ╚██████╔╝███████╗██║╚██████╗███████╗
-- ╚═╝      ╚═════╝ ╚══════╝╚═╝ ╚═════╝╚══════╝

Config.SellPolice = {
    TipOff = 0.04,                  -- chance any deal gets called in by a passer-by (real or fake)
    Code   = '10-66',
    Blip   = { sprite = 51, colour = 1 },
}

-- ██████╗ ██████╗  ██████╗ ██████╗ ███████╗
-- ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔════╝
-- ██║  ██║██████╔╝██║   ██║██████╔╝███████╗
-- ██║  ██║██╔══██╗██║   ██║██╔═══╝ ╚════██║
-- ██████╔╝██║  ██║╚██████╔╝██║     ███████║
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝

-- Limited drops: every so often one colourway drops in a handful of pairs. Everyone gets a text, the
-- raffle opens (enter in the Plug app or at the drop store), winners are drawn and have a while to
-- collect and pay at the store; pairs nobody claims go to whoever walks in first. Drop pairs are marked
-- Limited and sell for more. Admins: /sneakerdrop [shoe_colour] [pairs] starts one now, /sneakerdrop stop ends it.
Config.Drops = {
    Enabled    = true,
    Every      = { 90, 180 },     -- minutes between drops (picked at random in this range)
    MinPlayers = 4,               -- no drops while fewer players are on
    Raffle     = 10,              -- minutes the raffle is open after the announcement
    Claim      = 15,              -- minutes winners have to collect their pair
    Stock      = { 4, 10 },       -- pairs per drop
    PriceMult  = 1.0,             -- drop price = the shoe's retail price x this
    ValueBoost = 1.5,             -- buyers pay this much more for a Limited pair
    HypeBoost  = 0.25,            -- the dropped model gets this much extra hype until the board rerolls
    BoxColour  = 'black',         -- drop pairs come in this box colour (Config.BoxColours)
    Pool       = nil,             -- nil = any shoe on sale, or a list like { 'fang5_c', 'cup_a', 'mia_b' }
    Account    = 'bank',          -- 'cash' | 'bank'
    Command    = 'sneakerdrop',   -- admins (Config.AdminAce)
    Store = {
        label  = 'Sneaker drop',
        ped    = `a_m_y_hipster_01`,
        coords = vector4(127.8, -223.5, 54.56, 70.0),   -- Suburban, Hawick Ave; move it anywhere
        blip   = { sprite = 617, colour = 27, scale = 0.85 },   -- shown while a drop is on
    },
}
