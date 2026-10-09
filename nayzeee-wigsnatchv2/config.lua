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
Config.Target    = 'auto'       -- 'auto' | 'ox_target' | 'qb-target' | 'none' (none = commands / keybinds only)

-- Which character models can lose their hair. Drawable IDs differ between the two
-- freemode models, so wigs only fit the model they were snatched from.
Config.Models = {
    female = { model = `mp_f_freemode_01`, enabled = true },
    male   = { model = `mp_m_freemode_01`, enabled = true },
}

-- Hair drawables that count as "already bald" (nothing to snatch or cut)
Config.BaldDrawables = {
    female = { [0] = true },
    male   = { [0] = true },
}

-- ██╗███╗   ██╗████████╗███████╗██████╗ ███████╗ █████╗  ██████╗███████╗
-- ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝
-- ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝█████╗  ███████║██║     █████╗
-- ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██╔══╝  ██╔══██║██║     ██╔══╝
-- ██║██║ ╚████║   ██║   ███████╗██║  ██║██║     ██║  ██║╚██████╗███████╗
-- ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚══════╝

-- Server defaults for the look of every menu. With PlayerPrefs on, each player can
-- change their own colours, size and sounds from Vault > Settings or /wigsettings.
-- Their choices are saved on their own PC and never touch the database.
Config.UI = {
    Accent        = '#08afa2',   -- Main colour (buttons, bars, highlights)
    Alert         = '#e5484d',   -- Danger colour (errors, close buttons, the other side of the rope)
    Scale         = 1.0,         -- 0.8 - 1.25
    ToastPosition = 'top-right', -- top-right | top-left | top-center | bottom-right | bottom-left
    Sounds        = true,
    Volume        = 0.7,         -- 0.0 - 1.0
    ReduceMotion  = false,

    PlayerPrefs     = true,          -- Let players pick their own colours / size / sounds / keys
    SettingsCommand = 'wigsettings', -- Opens the settings page. false to disable

    -- Swatches shown in the colour picker (players can still type any hex)
    Presets = { '#08afa2', '#3d9bff', '#a873ff', '#ff6fb5', '#e5a50a', '#46c08a', '#e5484d', '#f2f4f5' },
}

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

-- 'auto' picks the first one that is running, in this order:
--   okokNotify, brutal_notify, wasabi_notify, lation_ui, t-notify, pNotify, mythic_notify, ox_lib, then the built-in toasts.
-- Or force one: 'nui' (built-in toasts) | 'ox_lib' | 'esx' | 'qb' | 'qbx' | 'okok' | 'mythic' | 'pnotify'
--               'tnotify' | 'brutal' | 'wasabi' | 'lation' | 'custom'
-- Every adapter lives in bridge/notify.lua if your version needs a tweak.
Config.Notify = 'nui'

-- Only used when Config.Notify = 'custom'. Runs on the client.
-- kind: 'success' | 'error' | 'info' | 'warning'
Config.CustomNotify = function(title, message, kind, duration)
    -- exports['my-notify']:Notify(title, message, kind, duration)
    print(('[%s] %s'):format(title, message))
end

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
    AllowDowned  = false,      -- Can downed / dead players be snatched? (no minigame, it just happens)
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

    -- Hair grows back on its own after this long (survives relogs). Regrowth Oil speeds it up.
    -- 0 = never on its own (Regrowth Oil or an admin only).
    RegrowMinutes = 45,
}

-- ███╗   ███╗██╗███╗   ██╗██╗ ██████╗  █████╗ ███╗   ███╗███████╗███████╗
-- ████╗ ████║██║████╗  ██║██║██╔════╝ ██╔══██╗████╗ ████║██╔════╝██╔════╝
-- ██╔████╔██║██║██╔██╗ ██║██║██║  ███╗███████║██╔████╔██║█████╗  ███████╗
-- ██║╚██╔╝██║██║██║╚██╗██║██║██║   ██║██╔══██║██║╚██╔╝██║██╔══╝  ╚════██║
-- ██║ ╚═╝ ██║██║██║ ╚████║██║╚██████╔╝██║  ██║██║ ╚═╝ ██║███████╗███████║
-- ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝

-- Every snatch is a live fight between both players. Both of them play the SAME minigame,
-- the server moves the rope, and the first to the end wins (or whoever is ahead at the buzzer).
Config.Clash = {
    Enabled   = true,          -- false = snatches always succeed instantly

    -- Which minigame runs:
    --   'random' = a random one from Games every snatch
    --   'rotate' = goes through Games in order
    --   'clash' | 'mash' | 'sequence' | 'circle' | 'balance' = always that one
    Mode  = 'random',
    Games = { 'clash', 'mash', 'sequence', 'circle', 'balance' }, -- The pool for random / rotate. Remove any you don't want.

    Duration  = 6500,          -- ms
    WinAt     = 100,           -- Rope position needed to win outright (-WinAt for the victim)
    TieGoesTo = 'victim',      -- Who wins if the rope is dead centre at the buzzer: 'victim' | 'snatcher'
    MissLockout = 380,         -- ms a player is locked out after a miss / wrong key

    Blindside = {              -- Grab them from behind = head start
        Enabled = true,
        Angle   = 70,          -- Degrees either side of directly behind the victim
        Start   = 25,          -- Rope starts this far toward the snatcher
    },

    SkipIfRestrained = true,   -- Cuffed / tied / held / hands up / tackled victims can't fight back
    FailRagdoll      = 1500,   -- ms the snatcher hits the floor after losing. 0 = off
}

-- Per-minigame tuning. Push = rope movement per successful input (snatcher / victim).
-- MinHitInterval is the server-side rate limit per player, so macros do nothing.
Config.Minigames = {
    -- Tug of War: a cursor sweeps a track, hit the key while it's inside the zone
    clash = {
        Label = 'Tug of War', Icon = 'fa-solid fa-grip-lines-vertical',
        Push  = { snatcher = 14,  victim = 15 },
        Zone  = { snatcher = 0.16, victim = 0.18 },   -- Zone width as a fraction of the track
        Speed = { snatcher = 1.10, victim = 1.00 },   -- Cursor sweeps per second
        MinHitInterval = 220,
    },
    -- Button Mash: alternate two keys as fast as you can (A / D by default)
    mash = {
        Label = 'Button Mash', Icon = 'fa-solid fa-hand-fist',
        Push  = { snatcher = 4.2, victim = 4.6 },
        MinHitInterval = 85,                           -- ~11 alternations a second max
    },
    -- Combo: type the arrows / WASD shown on screen in order. The server checks every key.
    sequence = {
        Label = 'Combo', Icon = 'fa-solid fa-keyboard',
        Length = 5,                                    -- Keys per combo
        Push   = { snatcher = 3.0, victim = 3.4 },     -- Per correct key
        Bonus  = { snatcher = 12,  victim = 13 },      -- Extra pull for finishing a combo
        MinHitInterval = 90,
    },
    -- Skill Check: a needle spins around a ring, hit the key when it's in the arc
    circle = {
        Label = 'Skill Check', Icon = 'fa-solid fa-circle-notch',
        Push  = { snatcher = 17, victim = 18 },
        Arc   = { snatcher = 0.13, victim = 0.15 },    -- Arc size as a fraction of the ring
        Speed = { snatcher = 0.95, victim = 0.85 },    -- Spins per second
        MinHitInterval = 240,
    },
    -- Grip: hold the key to lift the marker, let go to drop it. Stay inside the moving zone.
    balance = {
        Label = 'Grip', Icon = 'fa-solid fa-hand-holding',
        Push  = { snatcher = 6.5, victim = 7.0 },
        Zone  = { snatcher = 0.22, victim = 0.25 },    -- Zone height as a fraction of the bar
        Tick  = 420,                                    -- ms inside the zone per pull
        MinHitInterval = 360,
    },
}

-- Default keys (players can rebind these in their settings). JavaScript KeyboardEvent.code names.
Config.Keys = {
    Pull = 'Space',            -- Tug of War / Skill Check / Grip / struggling
    MashLeft  = 'KeyA',
    MashRight = 'KeyD',
}

-- Statebag keys checked on the VICTIM to decide if they're restrained.
-- Covers most police / ambulance scripts. This script's own tie / hold / tackle states are added automatically.
Config.RestrainedStates = { 'isCuffed', 'cuffed', 'handcuffed', 'isHandcuffed', 'ziptied', 'isTied' }
Config.DownedStates     = { 'isDead', 'dead', 'down', 'isDown', 'inLastStand', 'laststand' }
Config.HandsUpAnim      = { dict = 'random@mugging3', clip = 'handsup_standing_base' }

-- ███████╗████████╗███████╗ █████╗ ██╗         ██████╗  █████╗  ██████╗██╗  ██╗
-- ██╔════╝╚══██╔══╝██╔════╝██╔══██╗██║         ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝
-- ███████╗   ██║   █████╗  ███████║██║         ██████╔╝███████║██║     █████╔╝
-- ╚════██║   ██║   ██╔══╝  ██╔══██║██║         ██╔══██╗██╔══██║██║     ██╔═██╗
-- ███████║   ██║   ███████╗██║  ██║███████╗    ██████╔╝██║  ██║╚██████╗██║  ██╗
-- ╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝    ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝

-- Got snatched? For a while you can take back the EXACT wig. Snatch the person who has it
-- (in their pockets or on their head) and it comes back to you instead of their hair.
Config.StealBack = {
    Enabled  = true,
    Window   = 900,            -- Seconds after losing it
    XP       = 30,             -- Bonus reputation for getting it back
    Label    = 'Steal It Back',
    Icon     = 'fa-solid fa-rotate-left',
}

-- ██████╗ ██████╗  ██████╗ ████████╗███████╗ ██████╗████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██████╔╝██████╔╝██║   ██║   ██║   █████╗  ██║        ██║   ██║██║   ██║██╔██╗ ██║
-- ██╔═══╝ ██╔══██╗██║   ██║   ██║   ██╔══╝  ██║        ██║   ██║██║   ██║██║╚██╗██║
-- ██║     ██║  ██║╚██████╔╝   ██║   ███████╗╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

Config.Protection = {
    VictimImmunity  = 600,      -- Seconds a victim can't be snatched / cut / pranked again after losing their hair
    NewPlayerHours  = 2,        -- Fresh characters are protected for this many hours. 0 = off
    NewPlayerEndsOnAttack = true, -- Protection ends early if the new player snatches / tackles someone

    Jobs = {                    -- Jobs that can't be targeted (and can't target others)
        police    = true,
        ambulance = true,
    },
    JobsOnDutyOnly = true,      -- Only protect them while on duty

    -- Statebag keys on the player that mean "in a safezone". Safezone scripts can also
    -- call exports['nayzeee-wigsnatchv2']:SetProtected(source, true/false)
    SafezoneStates = { 'inSafezone', 'safezone', 'inSafeZone' },

    Passive = {                 -- Players can opt out with /wigpassive (they can't target anyone either)
        Enabled  = false,
        Command  = 'wigpassive',
        Cooldown = 1800,        -- Seconds before they can toggle again
    },
}

-- ██████╗ ███████╗███████╗████████╗██████╗  █████╗ ██╗███╗   ██╗
-- ██╔══██╗██╔════╝██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██║████╗  ██║
-- ██████╔╝█████╗  ███████╗   ██║   ██████╔╝███████║██║██╔██╗ ██║
-- ██╔══██╗██╔══╝  ╚════██║   ██║   ██╔══██╗██╔══██║██║██║╚██╗██║
-- ██║  ██║███████╗███████║   ██║   ██║  ██║██║  ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

-- Sprint at someone and press the key to take them down. While they're on the floor
-- they count as restrained, so you can tie them, hold them, snatch or shave them.
Config.Tackle = {
    Enabled       = true,
    Command       = 'wigtackle',
    Key           = 'G',        -- Rebindable in Settings > Key Bindings > FiveM. false = command only
    RequireSprint = true,
    Range         = 2.6,
    Cooldown      = 25,         -- Seconds
    TargetRagdoll = 4500,       -- ms the target stays down
    SelfRagdoll   = 1100,       -- ms the tackler stumbles (0 = stays up)
    DownedWindow  = 8,          -- Seconds the target counts as restrained after a tackle
    Anim = { dict = 'missmic2ig_11', tackler = 'mic_2_ig_11_intro_goon', target = 'mic_2_ig_11_intro_p_one' },
}

-- Zip-tie someone who is tackled, cuffed, downed, held or has their hands up.
-- Tied players can't move. They can struggle free, or anyone can untie them.
Config.Tie = {
    Enabled    = true,
    Item       = 'zip_ties',
    Consume    = true,
    Duration   = 3500,          -- ms to tie
    UntieTime  = 2500,          -- ms to untie
    MaxMinutes = 10,            -- Auto-untie after this long. 0 = never
    Label      = 'Zip Tie',
    UntieLabel = 'Untie',
    Struggle = {
        Enabled  = true,
        Strength = 100,         -- How tight the ties start
        PerPull  = 5,           -- Taken off per mash (alternate keys)
        MinHitInterval = 110,
    },
    Anims = {
        tier   = { dict = 'mp_arresting', clip = 'a_uncuff' },
        tied   = { dict = 'mp_arresting', clip = 'idle' },
    },
}

-- Grab someone from behind and pin them still while a friend snatches, shaves or pranks them.
-- They can struggle out of it.
Config.Hold = {
    Enabled      = true,
    Label        = 'Hold Still',
    RequireBehind = true,       -- Must grab from behind, unless they're already restrained
    MaxSeconds   = 60,
    Grip         = 100,
    StruggleDrain = 6,          -- Grip lost per mash from the person being held
    MinHitInterval = 110,
    ReleaseCommand = 'wigrelease',
    ReleaseKey   = 'X',         -- false = command only
    Anims = {
        holder = { dict = 'anim@gangops@hostage@', clip = 'perp_idle' },
        held   = { dict = 'anim@gangops@hostage@', clip = 'victim_idle' },
    },
    Offset = { x = -0.24, y = 0.11, z = 0.0 },  -- Where the held player sits relative to the holder
}

--  ██████╗██╗   ██╗████████╗████████╗██╗███╗   ██╗ ██████╗
-- ██╔════╝██║   ██║╚══██╔══╝╚══██╔══╝██║████╗  ██║██╔════╝
-- ██║     ██║   ██║   ██║      ██║   ██║██╔██╗ ██║██║  ███╗
-- ██║     ██║   ██║   ██║      ██║   ██║██║╚██╗██║██║   ██║
-- ╚██████╗╚██████╔╝   ██║      ██║   ██║██║ ╚████║╚██████╔╝
--  ╚═════╝ ╚═════╝    ╚═╝      ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝

-- First person haircuts. Pick up your tools, the camera moves in close and the cursor
-- becomes the tool. Work each part of the head; the result depends on what you did.
--   Scissors  - Section and snip (click on the hair)     - top, sides, back, eyebrows, beard
--   Clippers  - Fade (hold and move around)              - top, sides, back, beard
--   Razor     - Sharpen the lines (hold and stroke)      - top (after clippers), eyebrows, beard
-- Clients have to agree unless they're restrained (tied, held, tackled, cuffed, hands up, downed).
Config.Cutting = {
    Enabled        = true,
    Range          = 1.8,
    RequestTimeout = 20,
    Label          = 'Cut Hair',
    Icon           = 'fa-solid fa-scissors',
    ForceLabel     = 'Force Cut',
    MaxSeconds     = 120,       -- Session ends on its own after this long

    Tools = {
        scissors = { Item = 'scissors',       Label = 'Scissors', Icon = 'scissors', Mode = 'click',  Work = 11,  Sound = 'snip',     Key = '1',
                     Regions = { top = true, back = true, left = true, right = true, brows = true, beard = true } },
        clippers = { Item = 'hair_clippers',  Label = 'Clippers', Icon = 'clippers', Mode = 'hold',   Work = 34,  Sound = 'clippers', Key = '2',
                     Regions = { top = true, back = true, left = true, right = true, beard = true } },
        razor    = { Item = 'straight_razor', Label = 'Razor',    Icon = 'razor',    Mode = 'stroke', Work = 13,  Sound = 'razor',    Key = '3',
                     Regions = { top = true, brows = true, beard = true, left = true, right = true } },
    },
    -- Work per second the server accepts per player (anti-cheat). 100 work finishes a region.
    MaxWorkPerSecond = 42,

    -- What the client ends up with (base-game drawables, one is picked at random)
    Results = {
        trim = { male = { 4, 5, 10, 12 }, female = { 1, 7, 12, 15 } },  -- Scissors only
        fade = { male = { 1, 12 },        female = { 8, 13 } },          -- Clippers on the sides / back
        buzz = { male = { 1 },            female = { 0 } },              -- Clippers on the top
        bald = { male = { 0 },            female = { 0 } },              -- Clippers then razor on the top
    },
    BuzzMinutes = 0,            -- Buzzed / bald from a cut regrows after this long. 0 = use Config.Snatch.RegrowMinutes
    FaceRegrowMinutes = 30,     -- Shaved eyebrows / beard come back after this long

    -- Eyebrows (head overlay 2) and facial hair (head overlay 1)
    Face = {
        ThinOpacity = 0.35,     -- Scissors on the eyebrows / beard thins them to this
    },

    -- Snipping long hair with scissors drops hair bundles you can turn into wigs
    Bundles = {
        Enabled   = true,
        PerRegion = 1,          -- Bundles per finished region (top / back / left / right)
        Max       = 3,
    },

    Camera = { Fov = 38.0, Dist = 0.78, MinDist = 0.45, MaxDist = 1.2, Height = 0.06 },
    Particles = { asset = 'scr_barbers', name = 'scr_barbers_haircut', scale = 0.8 }, -- false = off
    Anim = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle' }, -- What others see the barber doing
    Props = {                   -- Held in the barber's hand for everyone to see. false = none
        scissors = { model = `prop_cs_scissors`, bone = 57005, pos = vec3(0.12, 0.04, 0.01), rot = vec3(-80.0, 0.0, 0.0) },
        -- nz_wig_clippers / nz_wig_razor ship in stream/. Tweak pos / rot if your animations hold them differently
        clippers = { model = `nz_wig_clippers`, bone = 28422, pos = vec3(0.0, 0.0, 0.02), rot = vec3(90.0, 0.0, 0.0) },
        razor    = { model = `nz_wig_razor`,    bone = 28422, pos = vec3(0.0, 0.0, 0.0),  rot = vec3(90.0, 0.0, 0.0) },
    },
    SoundRange = 12.0,          -- Nearby players hear the tools
    XP = { Cut = 8, Forced = 14, Face = 4 },
}

-- ██████╗ ██████╗  ██████╗ ██████╗ ██╗   ██╗ ██████╗████████╗███████╗
-- ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██║   ██║██╔════╝╚══██╔══╝██╔════╝
-- ██████╔╝██████╔╝██║   ██║██║  ██║██║   ██║██║        ██║   ███████╗
-- ██╔═══╝ ██╔══██╗██║   ██║██║  ██║██║   ██║██║        ██║   ╚════██║
-- ██║     ██║  ██║╚██████╔╝██████╔╝╚██████╔╝╚██████╗   ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝  ╚═════╝   ╚═╝   ╚══════╝

-- Put products in someone else's hair (or your own). Statuses wear off on their own,
-- and some can be washed out. Everyone nearby sees the effects.
--   Requires: 'any'        = works on anyone you can reach
--             'behind'     = sneak up from behind, or they're restrained
--             'restrained' = only if they're tied / held / tackled / cuffed / hands up / downed
Config.Products = {
    Range      = 1.8,
    ApplyTime  = 3000,          -- ms
    TargetIcon = 'fa-solid fa-pump-soap',

    List = {
        hair_remover = { Item = 'hair_remover', Label = 'Hair Remover', Effect = 'fallout', Requires = 'behind',     Self = false, Others = true },
        relaxer      = { Item = 'relaxer',      Label = 'Lye Relaxer',  Effect = 'burn',    Requires = 'behind',     Self = false, Others = true, Minutes = 20, Damage = 8 },
        lice         = { Item = 'lice_jar',     Label = 'Lice Jar',     Effect = 'lice',    Requires = 'behind',     Self = false, Others = true, Minutes = 40 },
        mud          = { Item = 'mud_bag',      Label = 'Mud',          Effect = 'dirt',    Requires = 'any',        Self = true,  Others = true, Minutes = 60 },
        shampoo      = { Item = 'shampoo',      Label = 'Shampoo',      Effect = 'clean',   Requires = 'any',        Self = true,  Others = true, Cleans = { 'dirt', 'lice' } },
        regrowth     = { Item = 'regrowth_oil', Label = 'Regrowth Oil', Effect = 'regrow',  Requires = 'any',        Self = true,  Others = true, Minutes = 0 },  -- 0 = instant, else takes this many minutes off the timer
    },

    -- How each status looks
    Status = {
        burn = { Label = 'Burnt',  Color = '#e5484d', HairColor = { 0, 0 },
                 Particle = { asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 0.08 }, DamagePack = 'Burnt_Ped_Head_Torso', ValueMult = 0.5 },
        lice = { Label = 'Lice',   Color = '#a873ff', Spread = true,  ItchEvery = 25,
                 Particle = { asset = 'core', name = 'ent_amb_fly_swarm', scale = 0.35 } },
        dirt = { Label = 'Dirty',  Color = '#a87a4f', WaterCleans = true, DamagePack = 'Dirt_Mud' },
    },
}

-- ██████╗ ███████╗ █████╗  ██████╗████████╗██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██╔════╝██╔══██╗██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
-- ██████╔╝█████╗  ███████║██║        ██║   ██║██║   ██║██╔██╗ ██║███████╗
-- ██╔══██╗██╔══╝  ██╔══██║██║        ██║   ██║██║   ██║██║╚██╗██║╚════██║
-- ██║  ██║███████╗██║  ██║╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║███████║
-- ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Short animations that play when something happens to you. One is picked at random.
-- Any animation that fails to load is skipped, so add your own freely.
Config.Reactions = {
    Enabled = true,
    snatched = { -- you lost your hair / wig
        { dict = 'anim@mp_player_intcelebrationfemale@face_palm', clip = 'face_palm', duration = 2500 },
        { dict = 'gestures@m@standing@casual', clip = 'gesture_damn', duration = 1800 },
        { dict = 'switch@trevor@floyd_crying', clip = 'console_wasnt_fun_end_loop_floyd', duration = 3500, flag = 49 },
    },
    defended = { -- you held on
        { dict = 'gestures@m@standing@casual', clip = 'gesture_no_way', duration = 1800 },
    },
    snatcher_win = {
        { dict = 'mp_player_int_upperpeace_sign', clip = 'mp_player_int_peace_sign', duration = 2000 },
        { dict = 'rcmfanatic1celebrate', clip = 'celebrate', duration = 2600 },
    },
    snatcher_lose = {
        { dict = 'gestures@m@standing@casual', clip = 'gesture_damn', duration = 1800 },
    },
    cut_victim = { -- forced haircut / shave finished
        { dict = 'anim@mp_player_intcelebrationfemale@face_palm', clip = 'face_palm', duration = 2500 },
        { dict = 'misscarsteal4@actor', clip = 'actor_berating_loop', duration = 3000, flag = 49 },
    },
    cut_client = { -- a haircut you agreed to
        { dict = 'mp_player_int_upperpeace_sign', clip = 'mp_player_int_peace_sign', duration = 2000 },
    },
    burn = {
        { dict = 'move_m@_idles@shake_off', clip = 'shakeoff_1', duration = 2200 },
        { dict = 'misscarsteal4@actor', clip = 'actor_berating_loop', duration = 2600, flag = 49 },
    },
    lice = {
        { dict = 'move_m@_idles@shake_off', clip = 'shakeoff_1', duration = 2200 },
    },
    dirt = {
        { dict = 'move_m@_idles@shake_off', clip = 'shakeoff_1', duration = 2200 },
    },
    fallout = {
        { dict = 'anim@mp_player_intcelebrationfemale@face_palm', clip = 'face_palm', duration = 2500 },
    },
    clean = {
        { dict = 'move_m@_idles@shake_off', clip = 'shakeoff_1', duration = 2200 },
    },
    tackled = {
        { dict = 'gestures@m@standing@casual', clip = 'gesture_damn', duration = 1800 },
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

-- Style names. A hairstyle always maps to the same name, so players can hunt specific
-- people to finish their catalog. Names you give hairstyles in the Wig Studio (/wigstudio)
-- override these and join the catalog.
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
--   cooldown = % shorter snatch cooldown   zone = extra zone / arc size in the minigames
--   sell     = % more when selling         luck = extra tier luck
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
    Defend       = 14,          -- Winning a minigame as the victim
    FailedSnatch = 2,           -- Losing a minigame as the snatcher (still learning)
    Revenge      = 40,          -- Snatching back the person who snatched you
    Tackle       = 3,
    Tie          = 4,
    Product      = 5,           -- Pranking someone with a product
    Craft        = 15,          -- Making a wig from bundles
    StreakBonus  = 0.10,        -- +10% XP per streak step
    StreakCap    = 10,          -- Streak bonus stops growing here
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
    Bundle   = 'hair_bundle',
    Glue     = 'wig_glue',
    Kit      = 'wig_kit',
    Cap      = 'wig_cap',
    Dye      = 'hair_dye',
    Weft     = 'hair_weft',      -- Crafting from materials (see Config.Crafting)
    Thread   = 'wig_thread',
}

Config.Wig = {
    ConditionLossPerSnatch = 12, -- Worn wigs take damage every time they get snatched
    MinCondition    = 15,        -- Condition can't drop below this
    InfamyPerSnatch = 0.08,      -- +8% value for every time a wig has changed hands
    InfamyCap       = 0.80,
    KitRepair       = 35,        -- Condition restored by one wig kit
    ProvenanceSize  = 6,         -- How many past owners are remembered on the item

    -- Inventory picture for each wig:
    --   'studio' = the photo of that exact hairstyle from the Wig Studio (falls back to the plain wig image)
    --   'tier'   = 'wig_<tier>' images you add to your inventory (wig_common.png, wig_rare.png...)
    --   false    = the plain wig image for every wig
    Images = 'studio',
    WearAnim = { dict = 'mp_masks@standard_car@ds@', clip = 'put_on_mask', duration = 1200 },

    -- Put your wig on someone else / take a wig off someone. They get a prompt to accept.
    PutOnOthers   = true,
    TakeOffOthers = true,
    PutOnLabel    = 'Put Wig On',
    TakeOffLabel  = 'Take Wig Off',
}

Config.Glue = {
    Duration       = 1200,       -- Seconds of protection per bottle
    PushMultiplier = 1.30,       -- Victim pulls harder in every minigame
    ZoneBonus      = 0.04,       -- Victim's zone / arc gets bigger
    SnatcherZonePenalty = 0.03,  -- Snatcher's zone / arc gets smaller
    Anim = { dict = 'mp_masks@standard_car@ds@', clip = 'put_on_mask', duration = 2500 },
}

-- ██████╗ ██╗   ██╗███╗   ██╗██████╗ ██╗     ███████╗███████╗
-- ██╔══██╗██║   ██║████╗  ██║██╔══██╗██║     ██╔════╝██╔════╝
-- ██████╔╝██║   ██║██╔██╗ ██║██║  ██║██║     █████╗  ███████╗
-- ██╔══██╗██║   ██║██║╚██╗██║██║  ██║██║     ██╔══╝  ╚════██║
-- ██████╔╝╚██████╔╝██║ ╚████║██████╔╝███████╗███████╗███████║
-- ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚══════╝╚══════╝╚══════╝

-- Hair bundles come from cutting long hair with scissors. Three bundles and a wig cap make
-- a wig of that hairstyle. Bundles sell on their own too.
Config.Bundles = {
    -- grade: weight = how often it rolls, mult = price multiplier, tier = the wig it makes at minimum
    Grades = {
        { id = 'synthetic', label = 'Synthetic', weight = 30, mult = 0.6, tier = 'common'   },
        { id = 'remy',      label = 'Remy',      weight = 40, mult = 1.0, tier = 'uncommon' },
        { id = 'virgin',    label = 'Virgin',    weight = 22, mult = 1.5, tier = 'rare'     },
        { id = 'raw',       label = 'Raw',       weight = 8,  mult = 2.2, tier = 'epic'     },
    },
    Length     = { 10, 30 },    -- Inches
    PerInch    = 4,             -- $ per inch before the grade multiplier
}

-- ██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗███████╗██╗  ██╗ ██████╗ ██████╗
-- ██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝██╔════╝██║  ██║██╔═══██╗██╔══██╗
-- ██║ █╗ ██║██║   ██║██████╔╝█████╔╝ ███████╗███████║██║   ██║██████╔╝
-- ██║███╗██║██║   ██║██╔══██╗██╔═██╗ ╚════██║██╔══██║██║   ██║██╔═══╝
-- ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗███████║██║  ██║╚██████╔╝██║
--  ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝

-- Wig table > Bundles / Dye: make wigs from bundles and dye wigs (or your own hair).
-- With wig tables on (below), making and dyeing wigs happens at a table.
Config.Workshop = {
    Enabled        = true,
    BundlesPerWig  = 3,
    NeedCap        = true,       -- Uses one Config.Items.Cap per wig
    CraftTime      = 6000,       -- ms (only used when wig tables are off)
    CraftAnim      = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    UpgradeChance  = 0.25,       -- Chance the wig rolls one tier above the bundles' grade
}

Config.Dye = {
    Enabled    = true,
    OwnHair    = true,           -- Players can dye their own hair (stays until they dye it again or rinse it)
    ValueBonus = 0.10,           -- Dyed wigs sell for 10% more
    DyeTime    = 4000,           -- ms (own hair, and wigs when wig tables are off)
}

-- ████████╗ █████╗ ██████╗ ██╗     ███████╗███████╗
-- ╚══██╔══╝██╔══██╗██╔══██╗██║     ██╔════╝██╔════╝
--    ██║   ███████║██████╔╝██║     █████╗  ███████╗
--    ██║   ██╔══██║██╔══██╗██║     ██╔══╝  ╚════██║
--    ██║   ██║  ██║██████╔╝███████╗███████╗███████║
--    ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝╚══════╝

-- The wig tables are Dragons Lab's "Wig Crafting Table" pack by SasDragon. They are NOT part
-- of this script: every server buys them from her and installs her resource next to this one.
-- The script finds her models by name, so her folder can be called anything.
--
-- Players place a table from their inventory, pick it up again, and make / dye wigs at it in
-- stages (with skill checks and a camera they can switch with V). Tables are saved between restarts.
-- Without her pack the tables fall back to a plain GTA workbench (or are off, with Fallback = false).
Config.Tables = {
    Enabled = true,
    Store   = 'https://discord.com/invite/KEhZqcuv6m',  -- where to buy her tables (printed in the console)

    -- item name = table. The item names match the icons in her pack's install-images folder.
    Items = {
        wigtableblue = { label = 'Blue wig table',   model = `sasdragonslab_blue_wigtable` },
        wigtablepink = { label = 'Pink wig table',   model = `sasdragonslab_pink_wigtable` },
        wigtablepurp = { label = 'Purple wig table', model = `sasdragonslab_purple_wigtable` },
        wigtablered  = { label = 'Red wig table',    model = `sasdragonslab_red_wigtable` },
    },
    Surface = nil,                -- The table top is found with rays when you start working; this (metres) is only the fallback (nil = 0.93)

    Fallback = `prop_tool_bench02`, -- Used when her pack isn't installed. false = no tables without it
    FallbackSurface = nil,

    MaxPerPlayer     = 1,
    StreamDistance   = 60.0,
    InteractDistance = 2.0,
    AnyoneCanUse     = true,      -- false = only the owner (and admins) can work at a placed table

    -- Tables that are always there (a salon, a shop). They can't be picked up.
    -- { item = 'wigtablepink', coords = vector4(x, y, z, heading) },
    Fixed = {},

    -- How the work is shot: 'three' (over the shoulder) | 'first' (your eyes) | 'close' (across the table)
    Camera = { Default = 'three', Switch = true },  -- Switch = players can change it with V while working
    SkillChecks = true,           -- false = stages just run, every check counts as passed

    -- Each job is done in stages. time in ms; check is an ox_lib skill check ('easy' | 'medium' | 'hard' or false).
    -- prop = what's in your hand: 'scissors' | 'razor' | 'clippers' | 'dye' | false
    Stages = {
        make = {    -- a wig from materials (Config.Crafting)
            { label = 'Stretching the wig cap',  time = 3500, check = false,    prop = false },
            { label = 'Laying the lace',         time = 4000, check = 'easy',   prop = false },
            { label = 'Sewing in the wefts',     time = 5500, check = 'medium', prop = false },
            { label = 'Plucking the hairline',   time = 4000, check = 'hard',   prop = false },
            { label = 'Cutting the lace',        time = 3500, check = 'easy',   prop = 'scissors' },
            { label = 'Shaping the style',       time = 3500, check = false,    prop = 'razor' },
        },
        craft = {   -- a wig from bundles
            { label = 'Stretching the wig cap',  time = 3500, check = false,    prop = false },
            { label = 'Sewing in the wefts',     time = 5000, check = 'medium', prop = false },
            { label = 'Plucking the hairline',   time = 4000, check = 'hard',   prop = false },
            { label = 'Cutting the lace',        time = 3500, check = 'easy',   prop = 'scissors' },
            { label = 'Shaping the style',       time = 3500, check = false,    prop = 'razor' },
        },
        dye = {
            { label = 'Mixing the colour',       time = 3000, check = false,    prop = 'dye' },
            { label = 'Working it through',      time = 4500, check = 'medium', prop = 'dye' },
            { label = 'Rinsing it out',          time = 3000, check = false,    prop = false },
        },
    },
    SpeedPerLevel = 0.04,         -- Each level works 4% faster (up to 40%)

    -- Skill checks change the result
    CheckUpgrade  = 0.05,         -- Each passed check on a wig: +5% chance to roll a tier higher
    FailCondition = 8,            -- Each failed check: the wig starts with 8% less condition
    PerfectXP     = 10,           -- Extra XP for passing every check
}

-- Props for the table work and dyeing. All of these ship in stream/ (escrowed).
-- In your hand: a key used by Config.Tables.Stages[...].prop. On the table: Head, Wig, Bundle, DyeBottle (false = none).
Config.TableProps = {
    scissors = { model = `prop_cs_scissors`, bone = 28422, pos = vec3(0.04, 0.0, -0.01), rot = vec3(0.0, 90.0, 0.0) },
    razor    = { model = `nz_wig_razor`,     bone = 28422, pos = vec3(0.0, 0.0, 0.0),   rot = vec3(90.0, 0.0, 0.0) },
    clippers = { model = `nz_wig_clippers`,  bone = 28422, pos = vec3(0.0, 0.0, 0.02),  rot = vec3(90.0, 0.0, 0.0) },
    dye      = { model = `nz_wig_dye`,       bone = 28422, pos = vec3(0.0, 0.0, -0.07), rot = vec3(0.0, 0.0, 0.0) },

    -- The bald foam head on the table. The wig goes on it at `point` (where a ped's SKEL_Head bone would be).
    Head      = { model = `nz_wig_head`, point = vec3(0.0, 0.0, 0.162) },
    -- The wig on the head. Each hairstyle uses its own prop when one is streamed (see INSTALL/HAIR_PROPS.md):
    --   1. HairPropMap: ['m:150'] = 'nzw_juice_dreads'   (gender:hairstyle number = prop name)
    --   2. HairProps:   'nzw_%s_%d' -> nzw_f_12 is female hairstyle 12
    -- Anything else uses the generic wig below.
    Wig       = { model = `nz_wig_shell` },
    HairProps = 'nzw_%s_%d',      -- false = only HairPropMap
    HairPropMap = {
        -- ['m:150'] = 'nzw_juice_dreads',
    },
    Bundle    = { model = `nz_hair_bundle` },  -- One per bundle / weft going in, used up as you work
    DyeBottle = { model = `nz_wig_dye` },
}

--  ██████╗██████╗  █████╗ ███████╗████████╗██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██║████╗  ██║██╔════╝
-- ██║     ██████╔╝███████║█████╗     ██║   ██║██╔██╗ ██║██║  ███╗
-- ██║     ██╔══██╗██╔══██║██╔══╝     ██║   ██║██║╚██╗██║██║   ██║
-- ╚██████╗██║  ██║██║  ██║██║        ██║   ██║██║ ╚████║╚██████╔╝
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Make a wig of any in-game hairstyle from materials (wig table > Make).
-- Pick the hairstyle, texture, length, lace and colour; the recipe is worked out from those:
--   Base items  +  one hair weft per `WeftInches` inches (rounded up)  +  the lace's items
--   +  one hair dye if the colour isn't in NaturalColours.
-- The lace decides the wig's tier. Legendary and mythic wigs can only be snatched.
Config.Crafting = {
    Enabled    = true,
    Base       = { wig_cap = 1, wig_thread = 1 },
    WeftItem   = 'hair_weft',
    WeftInches = 6,              -- 10" = 2 wefts, 18" = 3, 24" = 4, 30" = 5
    Lengths    = { 10, 30 },     -- Inches players can pick (steps of 2)
    Laces = {
        { id = 'closure', label = '5x5 HD Closure',  tier = 'uncommon', level = 1, items = { lace_closure = 1 } },
        { id = 'frontal', label = '13x4 HD Frontal', tier = 'rare',     level = 3, items = { lace_frontal = 1 } },
        { id = 'full',    label = 'Full Lace',       tier = 'epic',     level = 5, items = { lace_full = 1 } },
    },
    NaturalColours = { 0, 1, 2, 3, 4, 5 }, -- Hair colours that don't need a dye
    ShortStyles = false,         -- true = bald / buzz / fade hairstyles can be made too
    XP = 20,                     -- + Config.Tables.PerfectXP for a clean run
}

-- ███████╗██╗   ██╗██████╗ ██████╗ ██╗     ██╗███████╗██████╗
-- ██╔════╝██║   ██║██╔══██╗██╔══██╗██║     ██║██╔════╝██╔══██╗
-- ███████╗██║   ██║██████╔╝██████╔╝██║     ██║█████╗  ██████╔╝
-- ╚════██║██║   ██║██╔═══╝ ██╔═══╝ ██║     ██║██╔══╝  ██╔══██╗
-- ███████║╚██████╔╝██║     ██║     ███████╗██║███████╗██║  ██║
-- ╚══════╝ ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝

-- An NPC who sells the wig making materials. level = player level needed to buy it.
Config.Supplier = {
    Enabled    = true,
    Label      = 'Hair Supply',
    Ped        = `a_f_y_business_02`,
    Coords     = vector4(-34.6, -155.4, 57.08, 340.0),  -- Next to Hair on Hawick; move it anywhere
    Blip       = { sprite = 71, colour = 48, scale = 0.75 },  -- false = no blip
    Account    = 'cash',         -- 'cash' | 'bank'
    MaxPerItem = 25,             -- Most of one item per purchase
    Items = {
        wig_cap      = { label = 'Wig Cap',         price = 15 },
        wig_thread   = { label = 'Weaving Thread',  price = 5 },
        hair_weft    = { label = 'Hair Weft',       price = 15 },
        lace_closure = { label = '5x5 HD Closure',  price = 25 },
        lace_frontal = { label = '13x4 HD Frontal', price = 50,  level = 3 },
        lace_full    = { label = 'Full Lace Unit',  price = 120, level = 5 },
        hair_dye     = { label = 'Hair Dye',        price = 30 },
        wig_glue     = { label = 'Lace Glue',       price = 40 },
        wig_kit      = { label = 'Wig Kit',         price = 90,  level = 2 },
    },
}


-- ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██║  ██║██╔═══██╗████╗  ██║██╔════╝
-- ██████╔╝███████║██║   ██║██╔██╗ ██║█████╗
-- ██╔═══╝ ██╔══██║██║   ██║██║╚██╗██║██╔══╝
-- ██║     ██║  ██║╚██████╔╝██║ ╚████║███████╗
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Wig selling happens on the phone. There is no built-in phone: the app is added to your phone
-- resource (lb-phone, YSeries or qs-smartphone, see bridge/phone.lua). Without one the app is off.
Config.Phone = {
    Enabled    = true,
    Phone      = 'auto',         -- 'auto' | 'lb-phone' | 'yseries' | 'qs-smartphone' | 'qs-smartphone-pro'
    AppName    = 'Hair Plug',
    Identifier = 'nz-hairplug',

    -- Instant sale from anywhere, lower price
    QuickSell = { Enabled = true, Rate = 0.65, Account = 'money' },

    -- A buyer runs to you and pays full price (+ title perk)
    Meetup = {
        Enabled      = true,
        Rate         = 1.0,
        Account      = 'money',  -- 'money' / 'cash' (clean) or 'black_money' (dirty, ESX)
        Cooldown     = 300,      -- Seconds between meet-ups
        Model        = `a_m_m_business_01`,
        SpawnDistance = 35.0,    -- He spawns this far away and runs in
        RunSpeed     = 2.0,      -- 1.0 walk, 2.0 run, 3.0 sprint
        WaitTime     = 90,       -- Seconds he hangs around once he arrives
        Greeting     = 'Yo, you got the hair?',
    },

    -- Player-to-player listings. The wig is held by the server until it sells or you cancel.
    -- Sellers who are offline get paid the next time they log in.
    Listings = {
        Enabled     = true,
        Fee         = 0.05,      -- Taken from the sale
        MaxPerPlayer = 6,
        Hours       = 72,        -- Unsold listings return to the seller after this long
        MinPrice    = 50,
        MaxPrice    = 250000,
        Account     = 'bank',
    },

    -- Rotating NPC orders that pay extra for a specific kind of hair. First come, first served.
    Orders = {
        Enabled = true,
        Count   = 4,
        Minutes = 45,            -- How long each order stays up
        Bonus   = { 1.35, 1.9 },  -- Pays the item's value times this
        Account = 'money',
    },
}

-- Market demand: every sale of a tier lowers its price a little. It recovers over time.
Config.Market = {
    Enabled      = true,
    DropPerSale  = 0.04,         -- -4% per wig sold
    Floor        = 0.55,         -- Never below 55%
    RecoverPerHour = 0.10,       -- +10% per hour back toward 100%
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

-- The Wig Vault: profile, wigs, catalog, bounties, leaderboard, city feed and settings
Config.Vault = {
    Command  = 'wigs',
    Keybind  = false,            -- e.g. 'F7'
    FeedSize = 30,
    LeaderboardSize = 10,
    LeaderboardCache = 60,       -- Seconds
}

-- ███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗
-- ██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗
-- ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║
-- ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║
-- ███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝
-- ╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝

-- Built like the nayzeee-backpack icon studio: a head floats in a lit chroma box under the map,
-- you frame it with the orbit camera, and every shot is keyed in the browser into a small
-- transparent PNG named wig_<f|m>_<hairstyle>_<texture>.png. Name hairstyles in the studio too:
-- every wig made from a hairstyle uses its name and photo in the inventory, vault and phone app.
-- /wigstudio (ace: command.wigstudio). Needs screenshot-basic.
-- New photos are served after the next restart of this resource (and ox_inventory).
Config.Studio = {
    Enabled   = true,
    Command   = 'wigstudio',     -- Admins only (ServerConfig.StudioAce). Needs screenshot-basic
    Size      = 256,             -- PNG size in pixels (square). 256 is plenty for inventories
    Padding   = 0.08,            -- Empty border around the hair, as a share of the size
    Chroma    = 'green',         -- Starting backdrop: 'green' | 'magenta' | 'blue' (switch it in the studio)
    AllTextures = false,         -- Default for the "every texture too" box
    SaveToInventory = true,      -- Also copy every photo into ox_inventory/web/images (see INSTALL)
    HairColor = { 2, 2 },        -- Colour / highlight the photos are taken in
    Face      = { 21, 0, 21, 0 },-- Head blend of the model: shape mum, shape dad, skin mum, skin dad
    Clothes = {                  -- Bare shoulders: [component] = { drawable, texture }
        male   = { [1] = { 0, 0 }, [3] = { 15, 0 }, [8] = { 15, 0 }, [11] = { 15, 0 } },
        female = { [1] = { 0, 0 }, [3] = { 15, 0 }, [8] = { 14, 0 }, [11] = { 15, 0 } },
    },
    Fov       = 30.0,
    Radius    = 0.30,            -- How much space around the head the camera fits
    HeadOffset = -0.04,          -- Camera target relative to the head bone
    Orbit     = { yaw = 200.0, elev = 8.0, zoom = 1.0, lift = 0.0 }, -- Starting framing (Three quarter)
    TextureWait = 650,           -- ms a hairstyle gets to stream in before the photo
    Coords    = vec3(0.0, 0.0, -150.0), -- Under the map, where nothing else renders
    Heading   = 180.0,
    RoutingBucket = 7177,
    LatentRate = 4000000,        -- bytes/sec for uploading the finished PNG
    Lights = {                   -- Offsets from the head
        { offset = vec3(0.0, -1.6, 0.4),  range = 5.0, intensity = 3.0 },
        { offset = vec3(-1.4, -0.6, 0.3), range = 4.0, intensity = 1.8 },
        { offset = vec3(1.4, -0.6, 0.3),  range = 4.0, intensity = 1.8 },
        { offset = vec3(0.0, 1.4, 0.6),   range = 4.0, intensity = 1.5 },
        { offset = vec3(0.0, 0.0, 1.6),   range = 4.0, intensity = 2.0 },
    },
}

-- 3D wigs: every hairstyle your server streams is turned into a prop for the foam head at the wig
-- tables, by hairkit (tools/hairkit). The Wig Studio shows what's new, changed or gone and builds them;
-- they go into their own resource (nzw_hairprops) next to this one. See README > 3D wigs.
Config.HairProps = {
    Enabled     = true,
    Resource    = 'nzw_hairprops',   -- Created next to this resource the first time
    AutoScan    = true,              -- Look for new / changed / removed hair files when the server starts
    AutoBuild   = true,              -- ...and build them straight away (restarts nzw_hairprops)
    TextureSize = 256,               -- Max texture size of each hair prop (128 / 256 / 512)
    Skip        = {},                -- Resource names to leave out of the scan, e.g. { 'my_test_pack' }
    Kit = {                          -- The hairkit program for each server OS (inside this resource)
        windows = 'tools/hairkit/win-x64/hairkit.exe',
        linux   = 'tools/hairkit/linux-x64/hairkit',
    },
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
    Apply        = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 },   -- putting a product / wig on someone
}

--  ██████╗██╗   ██╗███████╗████████╗ ██████╗ ███╗   ███╗
-- ██╔════╝██║   ██║██╔════╝╚══██╔══╝██╔═══██╗████╗ ████║
-- ██║     ██║   ██║███████╗   ██║   ██║   ██║██╔████╔██║
-- ██║     ██║   ██║╚════██║   ██║   ██║   ██║██║╚██╔╝██║
-- ╚██████╗╚██████╔╝███████║   ██║   ╚██████╔╝██║ ╚═╝ ██║
--  ╚═════╝ ╚═════╝ ╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝

-- Return true to block snatching / cutting / products at the player's current spot (client-side check, for UX).
-- The server also checks Config.Protection.SafezoneStates and the SetProtected export.
Config.IsInNoSnatchZone = function(coords)
    return false
end
