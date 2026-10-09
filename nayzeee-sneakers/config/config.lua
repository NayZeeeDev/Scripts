--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
    ███████╗███╗   ██╗███████╗ █████╗ ██╗  ██╗███████╗██████╗ ███████╗
    ██╔════╝████╗  ██║██╔════╝██╔══██╗██║ ██╔╝██╔════╝██╔══██╗██╔════╝
    ███████╗██╔██╗ ██║█████╗  ███████║█████╔╝ █████╗  ██████╔╝███████╗
    ╚════██║██║╚██╗██║██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██╔══██╗╚════██║
    ███████║██║ ╚████║███████╗██║  ██║██║  ██╗███████╗██║  ██║███████║
    ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝

    nayzeee-sneakers  v1.0.0  |  NayZeee Development
    Docs: nayzeee-dev.gitbook.io/docs  |  Store: www.nayzeeedev.com  |  Discord: discord.gg/nayzeeedev
]]

Config = {}

-- ███████╗██████╗  █████╗ ███╗   ███╗███████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
-- ██╔════╝██╔══██╗██╔══██╗████╗ ████║██╔════╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
-- █████╗  ██████╔╝███████║██╔████╔██║█████╗  ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
-- ██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝  ██║███╗██║██║   ██║██╔══██╗██╔═██╗
-- ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║███████╗╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
-- ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝

Config.Version   = '1.0.0'
Config.Debug     = false        -- prints extra info to the F8 / server console
Config.Framework = 'auto'       -- 'auto' | 'qbx' | 'qb' | 'esx'
Config.Locale    = 'en'         -- text lives in locales/<name>.lua

-- ██╗███╗   ██╗██╗   ██╗███████╗███╗   ██╗████████╗ ██████╗ ██████╗ ██╗   ██╗
-- ██║████╗  ██║██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
-- ██║██╔██╗ ██║██║   ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝ ╚████╔╝
-- ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝
-- ██║██║ ╚████║ ╚████╔╝ ███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║   ██║
-- ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

-- 'auto' picks the first one running: ox_inventory, then qb-inventory (also ps / lj-inventory).
-- 'custom' uses bridge/custom/inventory.lua for anything else. The inventory must keep item metadata.
Config.Inventory = 'auto'       -- 'auto' | 'ox' | 'qb' | 'custom'

Config.Items = {
    shoes       = 'nz_shoes',          -- a loose pair
    boxed       = 'nz_shoebox',        -- a pair in its box (any box size)
    cleaningKit = 'nz_cleaning_kit',   -- cleans a pair (has uses, see Config.Cleaning)
}

-- ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗███████╗
-- ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║███████╗
-- ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

-- 'nui' uses this script's own notifications. 'auto' picks the first that is running.
Config.Notify = 'nui'           -- 'nui' | 'auto' | 'nayzeee' | 'ox' | 'okok' | 'esx' | 'qb' | 'custom' (bridge/client/framework.lua)
Config.Target = 'auto'          -- 'auto' | 'ox_target' | 'qb-target' | 'interact' | 'textui'

-- Used when Config.Target is 'textui' (or no target resource is running)
Config.Interact = {
    Key      = 38,              -- E
    KeyLabel = 'E',
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

-- Who can use the admin commands:
--   add_ace group.admin nayzeee-sneakers.admin allow
Config.AdminAce = 'nayzeee-sneakers.admin'

Config.Commands = {
    give      = 'givesneakers',     -- /givesneakers [id] [shoe] [size] [fake 0/1] [boxed 0/1]
    giveBox   = 'giveshoebox',      -- /giveshoebox [id] [amount] [shoe|heel|boot]
    materials = 'givematerials',    -- /givematerials [id] [pairs]   enough materials for that many pairs of anything
    xp        = 'sneakerxp',        -- /sneakerxp [id] [amount]      no amount = show their XP
    rep       = 'sneakerrep',       -- /sneakerrep [id] [amount]     no amount = show their rep
    dirt      = 'sneakerdirt',      -- /sneakerdirt [amount]         set the dirt on the pair you're wearing (testing)
}

-- ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗███████╗
-- ██╔══██╗██║  ██║██╔═══██╗████╗  ██║██╔════╝
-- ██████╔╝███████║██║   ██║██╔██╗ ██║█████╗
-- ██╔═══╝ ██╔══██║██║   ██║██║╚██╗██║██╔══╝
-- ██║     ██║  ██║╚██████╔╝██║ ╚████║███████╗
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

-- Selling runs on lb-phone: the Plug app is added to every phone (or the App Store) automatically.
Config.Phone = {
    DefaultApp = true,          -- true = already on every phone, false = players download it from the App Store

    -- Buyers text the player. 'auto' picks the first phone resource that is running.
    Messages = 'auto',          -- 'auto' | 'lb-phone' | 'npwd' | 'yseries' | 'qs-smartphone' | 'gksphone' | 'none'
    Number   = '5550147',       -- the number texts come from (phones need a real number, not a name)
    Notify   = true,            -- also push an lb-phone notification so it pops with the phone closed
    Fallback = true,            -- show a phone-style text on screen when no phone resource takes it
}

-- ██████╗ ██╗███████╗██████╗  █████╗ ████████╗ ██████╗██╗  ██╗
-- ██╔══██╗██║██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║
-- ██║  ██║██║███████╗██████╔╝███████║   ██║   ██║     ███████║
-- ██║  ██║██║╚════██║██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║
-- ██████╔╝██║███████║██║     ██║  ██║   ██║   ╚██████╗██║  ██║
-- ╚═════╝ ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝

-- Police alerts for fake sales gone wrong (and the odd tip-off).
-- 'auto' picks the first dispatch resource that is running, otherwise the built-in alert.
-- 'custom' calls Bridge.CustomDispatch in bridge/server/dispatch.lua.
Config.Dispatch = {
    System     = 'auto',        -- 'auto' | 'builtin' | 'ps-dispatch' | 'cd_dispatch' | 'rcore_dispatch' | 'qs-dispatch' | 'custom'
    PoliceJobs = { 'police', 'sheriff', 'bcso', 'sasp', 'lspd' },
    BlipTime   = 60,            -- seconds the alert blip stays on the map
}

-- ██████╗  ██████╗ ██╗  ██╗███████╗███████╗
-- ██╔══██╗██╔═══██╗╚██╗██╔╝██╔════╝██╔════╝
-- ██████╔╝██║   ██║ ╚███╔╝ █████╗  ███████╗
-- ██╔══██╗██║   ██║ ██╔██╗ ██╔══╝  ╚════██║
-- ██████╔╝╚██████╔╝██╔╝ ██╗███████╗███████║
-- ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝

-- Three box sizes. Each shoe model says which one it goes in (config/shoes.lua).
-- hinge must match the size the box was built at (the prop tool prints it).
Config.BoxTypes = {
    shoe = {   -- sneakers, 34 x 29 x 20 cm
        label = 'Shoe box', item = 'nz_shoebox_empty',
        base = `nzs_box`, lid = `nzs_box_lid`, hinge = vector3(0.0, -0.145, 0.2),
    },
    heel = {   -- heels and ankle boots, 41 x 30 x 12 cm
        label = 'Heel box', item = 'nz_heelbox_empty',
        base = `nzs_box_heel`, lid = `nzs_box_heel_lid`, hinge = vector3(0.0, -0.15, 0.12),
    },
    boot = {   -- tall boots, 52 x 51 x 16 cm
        label = 'Boot box', item = 'nz_bootbox_empty',
        base = `nzs_box_boot`, lid = `nzs_box_boot_lid`, hinge = vector3(0.0, -0.255, 0.16),
    },
}

Config.Box = {
    floor            = 0.0045,  -- where the shoes rest inside
    openAngle        = 105.0,
    openTime         = 550,
    closeTime        = 500,
    streamDistance   = 40.0,
    interactDistance = 1.6,
    maxPerPlayer     = 4,
    anyoneCanPickUp  = false,   -- false = only the player who placed it (or admins)
    cleanupOnDrop    = true,    -- remove a player's placed boxes when they leave
}

-- The shoes floating in and out of the box
Config.Float = {
    height  = 0.42,             -- how far above the box they start / finish
    inTime  = 1500,
    outTime = 1200,
}

-- ██╗    ██╗███████╗ █████╗ ██████╗ ██╗███╗   ██╗ ██████╗
-- ██║    ██║██╔════╝██╔══██╗██╔══██╗██║████╗  ██║██╔════╝
-- ██║ █╗ ██║█████╗  ███████║██████╔╝██║██╔██╗ ██║██║  ███╗
-- ██║███╗██║██╔══╝  ██╔══██║██╔══██╗██║██║╚██╗██║██║   ██║
-- ╚███╔███╔╝███████╗██║  ██║██║  ██║██║██║ ╚████║╚██████╔╝
--  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.FirstPerson = true       -- close-up camera + animations while packing, unboxing, cleaning and putting shoes on
Config.GenderLock  = true       -- players can only wear shoes made for their ped (male / female freemode)
Config.ClothingPack = 'nayzeee_sneakers'   -- dlc name of the nayzeee-sneakers-clothing pack (leave it unless you renamed the pack)

-- How crafting and cleaning are shot. Players can switch while they work (V) and their pick is remembered.
Config.Camera = {
    Default = 'three',          -- 'three' = 3/4 view of you and the table | 'first' = first person | 'close' = close-up on the shoes
    Switch  = true,             -- false = everyone gets Default, no switching
}

Config.Wear = {
    takeOffCommand = 'shoesoff',
    reapplyDelay   = 3000,      -- ms after spawning before worn shoes go back on (lets your clothing script load first)
    -- what players wear after taking shoes off if nothing was recorded
    barefoot = {
        male   = { drawable = 34, texture = 0 },
        female = { drawable = 35, texture = 0 },
    },
}

-- ██████╗ ██╗██████╗ ████████╗
-- ██╔══██╗██║██╔══██╗╚══██╔══╝
-- ██║  ██║██║██████╔╝   ██║
-- ██║  ██║██║██╔══██╗   ██║
-- ██████╔╝██║██║  ██║   ██║
-- ╚═════╝ ╚═╝╚═╝  ╚═╝   ╚═╝

-- Worn shoes get dirty and wear out. Boxed and loose pairs don't change.
Config.Dirt = {
    Enabled = true,
    PerKm   = 14.0,             -- dirt % per km walked on clean ground
    Sprint  = 1.5,              -- running counts this much more
    Rain    = 1.8,              -- out in the rain
    Swim    = 35.0,             -- dirt added the moment you go into water
    -- the ground under your feet (material groups GTA reports)
    Ground  = { mud = 3.5, sand = 2.2, dirt = 2.4, grass = 1.4, gravel = 1.3 },
    Sync    = 20,               -- seconds between saves to the server
}

-- How far a pair is worn (km) before it drops to that condition. Any wear at all
-- ends Deadstock: a worn pair is never DS again.
Config.WearOut = {
    VNDS = 0.0,
    USED = 12.0,
    BEAT = 45.0,
}

--  ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
-- ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
-- ██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
-- ██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
-- ╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
--  ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Cleaning = {
    Uses   = 5,                 -- a cleaning kit cleans this many pairs
    Power  = 100,               -- dirt removed per clean (100 = spotless)
    Stages = {
        { label = 'Dry brushing',      time = 3500, check = false },
        { label = 'Scrubbing the sole', time = 4500, check = 'easy' },
        { label = 'Wiping the upper',  time = 4000, check = 'medium' },
        { label = 'Letting them dry',  time = 2500, check = false },
    },
    -- a failed check leaves a bit of dirt behind
    MissedSpot = 15,
    Brush = `prop_sponge_01`,  -- held while cleaning (any model works; missing = no prop)
    XP    = 5,
}

-- ███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗
-- ██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗
-- ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║
-- ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║
-- ███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝
-- ╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝

-- Use the shoes already on your server. NayZeee Sneaker Studio (the app) turns your clothing packs
-- into props and icons; /sneakerstudio in game spots new and removed shoes and lets admins price
-- them and switch them on. No config editing, no restarts.
Config.Studio = {
    Enabled       = true,
    Command       = 'sneakerstudio',
    PropsResource = 'nayzeee-sneakers-props',   -- the resource the app makes
    AutoEnable    = false,      -- true = shoes the app converts go on sale straight away (false = an admin switches them on)
    BaseGame      = false,      -- also list base-game shoes in the studio (they show as a stand-in prop)
    AlertAdmins   = true,       -- tell admins when they join if shoes were added to or removed from the server
    -- the prop shown for a shoe that has no prop of its own yet
    StandIn = { shoe = 'nzs_cup_a', heel = 'nzs_bianca_a', boot = 'nzs_alice_a' },
    -- starting price of a new shoe; change it per shoe in the studio
    Price   = { shoe = 350, heel = 400, boot = 450 },
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

Config.Logs = {
    Webhook = '',               -- Discord webhook URL for sales, fakes caught and admin gives ('' = off)
    Color   = 569250,           -- #08afa2
    Name    = 'Sneakers',
}
