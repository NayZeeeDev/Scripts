--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗  
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝  
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
                                                                
    ██████╗ ███████╗██╗   ██╗███████╗██╗      ██████╗ ██████╗ ███╗   ███╗███████╗███╗   ██╗████████╗
    ██╔══██╗██╔════╝██║   ██║██╔════╝██║     ██╔═══██╗██╔══██╗████╗ ████║██╔════╝████╗  ██║╚══██╔══╝
    ██║  ██║█████╗  ██║   ██║█████╗  ██║     ██║   ██║██████╔╝██╔████╔██║█████╗  ██╔██╗ ██║   ██║   
    ██║  ██║██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║     ██║   ██║██╔═══╝ ██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║   
    ██████╔╝███████╗ ╚████╔╝ ███████╗███████╗╚██████╔╝██║     ██║ ╚═╝ ██║███████╗██║ ╚████║   ██║   
    ╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝   
                                                                                                      
    WIG SNATCH SCRIPT - 2.0.0
    Discord: discord.gg/nayzeeedev
    
]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Debug     = false        -- Prints extra info to the F8 / server console
Config.Locale    = 'en'         -- File in /locales (en ships by default)
Config.Framework = 'auto'       -- 'auto' | 'esx' | 'qb' | 'qbx'
Config.Inventory = 'auto'       -- 'auto' | 'ox_inventory' | 'qb-inventory' | 'qs-inventory' | 'framework'
Config.Target    = 'auto'       -- 'auto' | 'ox_target' | 'qb-target' | 'none' (none = command / keybind only)

-- Notifications: 'nui' (built-in v5 toasts), 'ox_lib', 'framework' or 'custom'
-- With 'custom', edit Config.CustomNotify at the bottom of this file.
Config.Notify = 'nui'
Config.NotifyPosition = 'top-right' -- nui only: top-right | top-left | top-center | bottom-right | bottom-left

-- Which character models can lose their hair. Drawable IDs differ between the two
-- freemode models, so wigs only fit the model they were snatched from.
Config.Models = {
    female = { model = `mp_f_freemode_01`, enabled = true },
    male   = { model = `mp_m_freemode_01`, enabled = true },
}

-- Hair drawables that count as "already bald" (nothing to snatch)
Config.BaldDrawables = {
    female = { [0] = true },
    male   = { [0] = true },
}

-- ███████╗███╗   ██╗ █████╗ ████████╗ ██████╗██╗  ██╗
-- ██╔════╝████╗  ██║██╔══██╗╚══██╔══╝██╔════╝██║  ██║
-- ███████╗██╔██╗ ██║███████║   ██║   ██║     ███████║
-- ╚════██║██║╚██╗██║██╔══██║   ██║   ██║     ██╔══██║
-- ███████║██║ ╚████║██║  ██║   ██║   ╚██████╗██║  ██║
-- ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝

Config.Snatch = {
    Distance     = 2.0,        -- Max distance (m) to start a snatch
    Cooldown     = 90,         -- Seconds between attempts (win or lose). Level perks shorten it.
    Command      = 'snatch',   -- Snatch the closest player in front of you. false to disable.
    Keybind      = false,      -- e.g. 'G' to add a rebindable key (Settings > Key Bindings > FiveM). false to disable.
    AllowInVehicle = false,    -- Can either player be in a vehicle?
    AllowDowned  = false,      -- Can downed / dead players be snatched? (no clash, it just happens)
    TargetLabel  = 'Snatch Wig',
    TargetIcon   = 'fa-solid fa-hand',

    -- What a snatched wig reveals underneath
    -- 'natural' = snatching a WORN wig item shows the victim's real hair again (the wig was a decoy)
    -- 'bald'    = victims always end up bald
    WornWigReveals = 'natural',

    -- Hair left behind after a snatch. Base-game IDs only so everyone sees the same thing.
    BaldStyle = {
        female = { drawables = { 0 }, textures = { 0 } },
        male   = { drawables = { 0 }, textures = { 0 } },
    },

    RegrowMinutes = 45,        -- Hair grows back on its own after this long (survives relogs). 0 = never, barber only.
}

--  ██████╗██╗      █████╗ ███████╗██╗  ██╗
-- ██╔════╝██║     ██╔══██╗██╔════╝██║  ██║
-- ██║     ██║     ███████║███████╗███████║
-- ██║     ██║     ██╔══██║╚════██║██╔══██║
-- ╚██████╗███████╗██║  ██║███████║██║  ██║
--  ╚═════╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

-- The Clash: a live tug-of-war between the snatcher and the victim.
-- A cursor sweeps across a track. Press the key while it's inside the zone to pull.
-- First to the end wins, otherwise whoever is ahead when time runs out.
Config.Clash = {
    Enabled        = true,     -- false = snatches always succeed instantly
    Key            = 'Space',  -- 'Space' | 'KeyE' | 'KeyF' ... (JavaScript KeyboardEvent.code)
    Duration       = 6500,     -- ms
    WinAt          = 100,      -- Rope position needed to win outright (-WinAt for the victim)
    TieGoesTo      = 'victim', -- Who wins if the rope is dead centre at the buzzer: 'victim' | 'snatcher'
    MinHitInterval = 220,      -- ms, server-side rate limit per player (anti-macro)
    MissLockout    = 380,      -- ms a player is locked out after pressing outside the zone

    Push  = { snatcher = 14,  victim = 15 },   -- Rope movement per clean pull
    Zone  = { snatcher = 0.16, victim = 0.18 }, -- Zone width as a fraction of the track
    Speed = { snatcher = 1.10, victim = 1.00 }, -- Cursor sweeps per second

    Blindside = {               -- Grab them from behind = head start
        Enabled = true,
        Angle   = 70,           -- Degrees either side of directly behind the victim
        Start   = 25,           -- Rope starts this far toward the snatcher
    },

    SkipIfRestrained = true,    -- Cuffed / hands up / downed victims can't fight back
    FailRagdoll      = 1500,    -- ms the snatcher hits the floor after losing. 0 = off
}

-- Statebag keys checked on the VICTIM to decide if they're restrained.
-- Covers most police / ambulance scripts. Add your own if needed.
Config.RestrainedStates = { 'isCuffed', 'cuffed', 'handcuffed', 'isHandcuffed', 'ziptied', 'isTied' }
Config.DownedStates     = { 'isDead', 'dead', 'down', 'isDown', 'inLastStand', 'laststand' }
Config.HandsUpAnim      = { dict = 'random@mugging3', clip = 'handsup_standing_base' }

-- ██████╗ ██████╗  ██████╗ ████████╗███████╗ ██████╗████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██████╔╝██████╔╝██║   ██║   ██║   █████╗  ██║        ██║   ██║██║   ██║██╔██╗ ██║
-- ██╔═══╝ ██╔══██╗██║   ██║   ██║   ██╔══╝  ██║        ██║   ██║██║   ██║██║╚██╗██║
-- ██║     ██║  ██║╚██████╔╝   ██║   ███████╗╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

Config.Protection = {
    VictimImmunity  = 600,      -- Seconds a victim can't be snatched again after losing their hair
    NewPlayerHours  = 2,        -- Fresh characters are protected for this many hours. 0 = off
    NewPlayerEndsOnAttack = true, -- Protection ends early if the new player snatches someone

    Jobs = {                    -- Jobs that can't be snatched (and can't snatch)
        police    = true,
        ambulance = true,
    },
    JobsOnDutyOnly = true,      -- Only protect them while on duty

    -- Statebag keys on the player that mean "in a safezone". Safezone scripts can also
    -- call exports['nayzeee-wigsnatch']:SetProtected(source, true/false)
    SafezoneStates = { 'inSafezone', 'safezone', 'inSafeZone' },

    Passive = {                 -- Players can opt out with /wigpassive (they can't snatch either)
        Enabled  = false,
        Command  = 'wigpassive',
        Cooldown = 1800,        -- Seconds before they can toggle again
    },
}

-- ████████╗██╗███████╗██████╗ ███████╗
-- ╚══██╔══╝██║██╔════╝██╔══██╗██╔════╝
--    ██║   ██║█████╗  ██████╔╝███████╗
--    ██║   ██║██╔══╝  ██╔══██╗╚════██║
--    ██║   ██║███████╗██║  ██║███████║
--    ╚═╝   ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝

-- Every snatch rolls a tier. Luck (glue, streaks, bounties, level) pushes the roll upward.
-- price = sell range at 100% condition. xp = reputation earned.
Config.Tiers = {
    { id = 'common',    label = 'Common',    color = '#a7aeb3', weight = 50,  price = { 60,   110 },  xp = 10,  lace = 'Synthetic',          length = { 10, 14 } },
    { id = 'uncommon',  label = 'Uncommon',  color = '#46c08a', weight = 27,  price = { 120,  200 },  xp = 18,  lace = '4x4 Closure',        length = { 12, 18 } },
    { id = 'rare',      label = 'Rare',      color = '#3d9bff', weight = 14,  price = { 220,  380 },  xp = 30,  lace = '5x5 HD Closure',     length = { 16, 22 } },
    { id = 'epic',      label = 'Epic',      color = '#a873ff', weight = 6,   price = { 420,  700 },  xp = 50,  lace = '13x4 HD Frontal',    length = { 20, 26 } },
    { id = 'legendary', label = 'Legendary', color = '#e5a50a', weight = 2.5, price = { 800,  1300 }, xp = 90,  lace = '13x6 Glueless HD',   length = { 24, 32 }, broadcast = true },
    { id = 'mythic',    label = 'Mythic',    color = '#08afa2', weight = 0.5, price = { 1800, 3000 }, xp = 180, lace = 'Full Lace Raw',      length = { 30, 40 }, broadcast = true },
}

-- Style names. A victim's hairstyle always maps to the same name, so players can
-- hunt specific people to finish their catalog.
Config.Styles = {
    'Body Wave', 'Bone Straight', 'Deep Wave', 'Water Wave', 'Kinky Curly', 'Kinky Straight',
    'Loose Deep', 'Jerry Curl', 'Yaki Straight', 'Silk Press', 'Pixie Cut', 'Blunt Bob',
    'Layered Bob', 'Finger Waves', 'Frontal Ponytail', 'Half Up Half Down', 'Knotless Braids', 'Butterfly Locs',
    'Goddess Locs', 'Passion Twists', 'Bantu Knots', 'Afro Puff', 'Curtain Bangs', 'Wolf Cut',
}

-- Catalog milestones: collect this many different styles to earn the reward once
Config.CatalogRewards = {
    { count = 6,  money = 1500,  xp = 100 },
    { count = 12, money = 4000,  xp = 250 },
    { count = 18, money = 9000,  xp = 500 },
    { count = 24, money = 20000, xp = 1200 },
}
Config.CatalogRewardAccount = 'bank'

-- ██╗     ███████╗██╗   ██╗███████╗██╗     ███████╗
-- ██║     ██╔════╝██║   ██║██╔════╝██║     ██╔════╝
-- ██║     █████╗  ██║   ██║█████╗  ██║     ███████╗
-- ██║     ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║     ╚════██║
-- ███████╗███████╗ ╚████╔╝ ███████╗███████╗███████║
-- ╚══════╝╚══════╝  ╚═══╝  ╚══════╝╚══════╝╚══════╝

-- Reputation levels. Perks are totals at that level (not added together).
--   cooldown = % shorter snatch cooldown   zone = extra zone width in the clash
--   sell     = % more from the buyer       luck = extra tier luck
Config.Levels = {
    { xp = 0,     title = 'Fresh Face' },
    { xp = 150,   title = 'Edge Grabber',    perks = { cooldown = 0.05 } },
    { xp = 450,   title = 'Lace Lifter',     perks = { cooldown = 0.10, zone = 0.01 } },
    { xp = 1000,  title = 'Bundle Bandit',   perks = { cooldown = 0.15, zone = 0.02, sell = 0.05 } },
    { xp = 2000,  title = 'Frontal Phantom', perks = { cooldown = 0.20, zone = 0.02, sell = 0.08, luck = 0.05 } },
    { xp = 3500,  title = 'Closure Crook',   perks = { cooldown = 0.25, zone = 0.03, sell = 0.10, luck = 0.08 } },
    { xp = 6000,  title = 'Wig Reaper',      perks = { cooldown = 0.30, zone = 0.03, sell = 0.12, luck = 0.12 } },
    { xp = 10000, title = 'Snatch Legend',   perks = { cooldown = 0.35, zone = 0.04, sell = 0.15, luck = 0.16 } },
}

Config.XP = {
    Defend      = 14,           -- Winning a clash as the victim
    FailedSnatch = 2,           -- Losing a clash as the snatcher (still learning)
    Buzz        = 12,           -- Forced buzz cut
    Haircut     = 6,            -- Giving someone a haircut they agreed to
    Revenge     = 40,           -- Snatching back the person who snatched you
    StreakBonus = 0.10,         -- +10% XP per streak step
    StreakCap   = 10,           -- Streak bonus stops growing here
}

Config.Luck = {                 -- Added together, capped at Max
    PerStreak = 0.03,
    Glued     = 0.15,           -- Victim was wearing glue
    Bounty    = 0.10,           -- Victim had a bounty on them
    Revenge   = 0.08,
    Max       = 0.60,
}

Config.StreakAnnounce = 5       -- Streaks at or above this get announced citywide. false = never

-- ██╗    ██╗██╗ ██████╗ ███████╗
-- ██║    ██║██║██╔════╝ ██╔════╝
-- ██║ █╗ ██║██║██║  ███╗███████╗
-- ██║███╗██║██║██║   ██║╚════██║
-- ╚███╔███╔╝██║╚██████╔╝███████║
--  ╚══╝╚══╝ ╚═╝ ╚═════╝ ╚══════╝

Config.Items = {
    Wig      = 'wig',
    Glue     = 'wig_glue',
    Kit      = 'wig_kit',
    Clippers = 'hair_clippers',
    Scissors = 'scissors',
}

Config.Wig = {
    ConditionLossPerSnatch = 12, -- Worn wigs take damage every time they get snatched
    MinCondition    = 15,        -- Condition can't drop below this
    InfamyPerSnatch = 0.08,      -- +8% value for every time a wig has changed hands
    InfamyCap       = 0.80,
    KitRepair       = 35,        -- Condition restored by one wig kit
    ProvenanceSize  = 6,         -- How many past owners are remembered on the item
    TieredImages    = false,     -- true = metadata image 'wig_<tier>' (add wig_common.png, wig_rare.png... to your inventory)
    WearAnim = { dict = 'mp_masks@standard_car@ds@', clip = 'put_on_mask', duration = 1200 },
}

Config.Glue = {
    Duration       = 1200,       -- Seconds of protection per bottle
    PushMultiplier = 1.30,       -- Victim pulls harder in the clash
    ZoneBonus      = 0.04,       -- Victim's zone gets wider
    SnatcherZonePenalty = 0.03,  -- Snatcher's zone gets narrower
    Anim = { dict = 'mp_masks@standard_car@ds@', clip = 'put_on_mask', duration = 2500 },
}

-- ██████╗ ██╗   ██╗██╗   ██╗███████╗██████╗
-- ██╔══██╗██║   ██║╚██╗ ██╔╝██╔════╝██╔══██╗
-- ██████╔╝██║   ██║ ╚████╔╝ █████╗  ██████╔╝
-- ██╔══██╗██║   ██║  ╚██╔╝  ██╔══╝  ██╔══██╗
-- ██████╔╝╚██████╔╝   ██║   ███████╗██║  ██║
-- ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝

-- Text the buyer, he runs up to you, sell from the v5 menu.
Config.Buyer = {
    Enabled      = true,
    Command      = 'sellwigs',
    Cooldown     = 300,          -- Seconds between calls
    Account      = 'money',      -- 'money' / 'cash' (clean) or 'black_money' (dirty, ESX)
    Model        = `a_m_m_business_01`,
    SpawnDistance = 35.0,        -- He spawns this far away and runs in
    RunSpeed     = 2.0,          -- 1.0 walk, 2.0 run, 3.0 sprint
    WaitTime     = 60,           -- Seconds he hangs around once he arrives
    Greeting     = 'Yo, heard you got some hair for sale?',
    PhoneAnim    = { dict = 'cellphone@', clip = 'cellphone_text_read_base', prop = `prop_npc_phone_02`, duration = 4000 },
}

-- Optional permanent fences (spawn only while someone is nearby)
Config.Fences = {
    -- { coords = vec4(-1172.36, -1572.04, 4.66, 125.0), model = `g_m_y_famca_01`, account = 'black_money', label = 'Wig Plug' },
}

-- Market demand: every sale of a tier lowers its price a little. It recovers over time.
Config.Market = {
    Enabled      = true,
    DropPerSale  = 0.04,         -- -4% per wig sold
    Floor        = 0.55,         -- Never below 55%
    RecoverPerHour = 0.10,       -- +10% per hour back toward 100%
}

-- ██████╗  █████╗ ██████╗ ██████╗ ███████╗██████╗
-- ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗
-- ██████╔╝███████║██████╔╝██████╔╝█████╗  ██████╔╝
-- ██╔══██╗██╔══██║██╔══██╗██╔══██╗██╔══╝  ██╔══██╗
-- ██████╔╝██║  ██║██║  ██║██████╔╝███████╗██║  ██║
-- ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝

Config.Barber = {
    Enabled      = true,
    RestorePrice = 750,          -- Grow your hair back instantly
    ResetCutPrice = 0,           -- Undo a haircut someone gave you
    RepairPerPoint = 8,          -- $ per condition point when repairing wigs here
    Account      = 'money',
    Blips        = true,
    Blip = { sprite = 71, color = 2, scale = 0.7, label = 'Barber' },
    Locations = {
        vec3(-814.31, -183.82, 37.57),
        vec3(136.83, -1708.37, 29.29),
        vec3(-1282.60, -1116.76, 6.99),
        vec3(1931.51, 3729.67, 32.84),
        vec3(1212.84, -472.92, 66.21),
        vec3(-32.89, -152.32, 57.08),
        vec3(-278.08, 6228.46, 31.70),
    },
    Radius = 2.0,
}

-- ██╗  ██╗ █████╗ ██╗██████╗     ████████╗ ██████╗  ██████╗ ██╗     ███████╗
-- ██║  ██║██╔══██╗██║██╔══██╗    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝
-- ███████║███████║██║██████╔╝       ██║   ██║   ██║██║   ██║██║     ███████╗
-- ██╔══██║██╔══██║██║██╔══██╗       ██║   ██║   ██║██║   ██║██║     ╚════██║
-- ██║  ██║██║  ██║██║██║  ██║       ██║   ╚██████╔╝╚██████╔╝███████╗███████║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝

-- Scissors and clippers on another player.
--   Styling: the other player has to accept, then you pick the cut from a menu.
--   Forced buzz (clippers only): only works if they're cuffed, have their hands up or are downed.
Config.Tools = {
    Duration = 4000,
    Range    = 2.0,
    RequestTimeout = 20,         -- Seconds they have to accept
    Anim = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle' },
    Prop = { model = `prop_cs_scissors`, bone = 57005, pos = vec3(0.12, 0.04, 0.01), rot = vec3(-80.0, 0.0, 0.0) },
    SoundRange = 12.0,           -- Nearby players hear the clippers / scissors

    Scissors = { Enabled = true, Label = 'Style Hair', Icon = 'fa-solid fa-scissors', Sound = 'scissors' },
    Clippers = { Enabled = true, Label = 'Buzz Cut',   Icon = 'fa-solid fa-wand-magic', Sound = 'clippers', AllowForced = true },

    -- Cuts the barber can choose from (base-game drawables). clippers = true means the cut needs clippers.
    Cuts = {
        female = {
            { label = 'Buzzed',       drawable = 0,  clippers = true },
            { label = 'Short',        drawable = 1 },
            { label = 'Layered Bob',  drawable = 2 },
            { label = 'Pigtails',     drawable = 3 },
            { label = 'Ponytail',     drawable = 4 },
            { label = 'Braided Mohawk', drawable = 5 },
            { label = 'Braids',       drawable = 6 },
            { label = 'Bob',          drawable = 7 },
            { label = 'Faux Hawk',    drawable = 8 },
            { label = 'French Twist', drawable = 9 },
            { label = 'Long Bob',     drawable = 10 },
            { label = 'Loose Tied',   drawable = 11 },
            { label = 'Pixie',        drawable = 12 },
            { label = 'Shaved Bangs', drawable = 13, clippers = true },
            { label = 'Top Knot',     drawable = 14 },
            { label = 'Wavy Bob',     drawable = 15 },
        },
        male = {
            { label = 'Shaved',       drawable = 0,  clippers = true },
            { label = 'Buzzcut',      drawable = 1,  clippers = true },
            { label = 'Faux Hawk',    drawable = 2 },
            { label = 'Hipster',      drawable = 3 },
            { label = 'Side Parting', drawable = 4 },
            { label = 'Shorter Cut',  drawable = 5 },
            { label = 'Biker',        drawable = 6 },
            { label = 'Ponytail',     drawable = 7 },
            { label = 'Cornrows',     drawable = 8 },
            { label = 'Slicked',      drawable = 9 },
            { label = 'Short Brushed', drawable = 10 },
            { label = 'Spikey',       drawable = 11 },
            { label = 'Caesar',       drawable = 12, clippers = true },
            { label = 'Chopped',      drawable = 13 },
            { label = 'Dreads',       drawable = 14 },
            { label = 'Long Hair',    drawable = 15 },
        },
    },
}

-- ██████╗  ██████╗ ██╗   ██╗███╗   ██╗████████╗██╗███████╗███████╗
-- ██╔══██╗██╔═══██╗██║   ██║████╗  ██║╚══██╔══╝██║██╔════╝██╔════╝
-- ██████╔╝██║   ██║██║   ██║██╔██╗ ██║   ██║   ██║█████╗  ███████╗
-- ██╔══██╗██║   ██║██║   ██║██║╚██╗██║   ██║   ██║██╔══╝  ╚════██║
-- ██████╔╝╚██████╔╝╚██████╔╝██║ ╚████║   ██║   ██║███████╗███████║
-- ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝╚══════╝╚══════╝

-- Got snatched? Put money on their head. Whoever snatches them next collects.
Config.Bounty = {
    Enabled     = true,
    Min         = 250,
    Max         = 25000,
    Fee         = 0.10,          -- 10% goes to the house, not the hunter
    Account     = 'bank',
    ExpireHours = 48,            -- Unclaimed bounties expire and refund the placer (minus fee)
    OnlyRevenge = true,          -- true = only on people who snatched you in the last RevengeHours
    RevengeHours = 24,
    BroadcastAt = 2500,          -- Bounties this big get announced citywide. false = never
}

-- ████████╗██████╗  █████╗ ██████╗ ██╗███╗   ██╗ ██████╗
-- ╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║██╔════╝
--    ██║   ██████╔╝███████║██║  ██║██║██╔██╗ ██║██║  ███╗
--    ██║   ██╔══██╗██╔══██║██║  ██║██║██║╚██╗██║██║   ██║
--    ██║   ██║  ██║██║  ██║██████╔╝██║██║ ╚████║╚██████╔╝
--    ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Sell or gift wigs to nearby players from the vault. The buyer gets a prompt to accept.
Config.Trading = {
    Enabled   = true,
    Range     = 6.0,
    Timeout   = 30,              -- Seconds to accept
    Account   = 'money',
    MaxPrice  = 100000,
}

-- ██╗   ██╗ █████╗ ██╗   ██╗██╗  ████████╗
-- ██║   ██║██╔══██╗██║   ██║██║  ╚══██╔══╝
-- ██║   ██║███████║██║   ██║██║     ██║
-- ╚██╗ ██╔╝██╔══██║██║   ██║██║     ██║
--  ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║
--   ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝

-- The Wig Vault: profile, wigs, catalog, bounties, leaderboard and city feed
Config.Vault = {
    Command  = 'wigs',
    Keybind  = false,            -- e.g. 'F7'
    FeedSize = 30,
    LeaderboardSize = 10,
    LeaderboardCache = 60,       -- Seconds
}

-- ███████╗███████╗███████╗██████╗
-- ██╔════╝██╔════╝██╔════╝██╔══██╗
-- █████╗  █████╗  █████╗  ██║  ██║
-- ██╔══╝  ██╔══╝  ██╔══╝  ██║  ██║
-- ██║     ███████╗███████╗██████╔╝
-- ╚═╝     ╚══════╝╚══════╝╚═════╝

Config.Announce = {
    NearbyRange = 60.0,          -- Players this close see the snatch banner
    Broadcast   = true,          -- Tiers with broadcast = true are announced to the whole city
}

Config.Effects = {
    Particles = { asset = 'core', name = 'ent_sht_feathers', scale = 0.6 }, -- puff at the victim's head. false = off
}

Config.Anims = {
    SnatcherPull = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 },
    VictimHold   = { dict = 'anim@mp_player_intuppersurrender', clip = 'idle_a', flag = 49 },
    Snatch       = { dict = 'melee@unarmed@streamed_variations', clip = 'plyr_takedown_front_slap', flag = 0, duration = 900 },
    Celebrate    = { dict = 'mp_player_int_upperpeace_sign', clip = 'mp_player_int_peace_sign', flag = 48, duration = 2000 },
    Victim       = { dict = 'anim@mp_player_intcelebrationfemale@face_palm', clip = 'face_palm', flag = 48, duration = 2500 },
}

--  ██████╗██╗   ██╗███████╗████████╗ ██████╗ ███╗   ███╗
-- ██╔════╝██║   ██║██╔════╝╚══██╔══╝██╔═══██╗████╗ ████║
-- ██║     ██║   ██║███████╗   ██║   ██║   ██║██╔████╔██║
-- ██║     ██║   ██║╚════██║   ██║   ██║   ██║██║╚██╔╝██║
-- ╚██████╗╚██████╔╝███████║   ██║   ╚██████╔╝██║ ╚═╝ ██║
--  ╚═════╝ ╚═════╝ ╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝

-- Only used when Config.Notify = 'custom'. Runs on the client.
-- kind: 'success' | 'error' | 'info' | 'warning'
Config.CustomNotify = function(title, message, kind, duration)
    -- exports['my-notify']:Notify(title, message, kind, duration)
    print(('[%s] %s'):format(title, message))
end

-- Return true to block snatching at the player's current spot (client-side check, for UX).
-- The server also checks Config.Protection.SafezoneStates and the SetProtected export.
Config.IsInNoSnatchZone = function(coords)
    return false
end
