--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗  
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝  
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
██████╗  █████╗  ██████╗██╗  ██╗██████╗  █████╗  ██████╗██╗  ██╗
██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝
██████╔╝███████║██║     █████╔╝ ██████╔╝███████║██║     █████╔╝ 
██╔══██╗██╔══██║██║     ██╔═██╗ ██╔═══╝ ██╔══██║██║     ██╔═██╗ 
██████╔╝██║  ██║╚██████╗██║  ██╗██║     ██║  ██║╚██████╗██║  ██╗
╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝

    BACKPACK SCRIPT - 1.0.0
    Discord: discord.gg/nayzeeedev

]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Debug = true -- Enable debug prints + the in-game backpack studio (/bagtune)

Config.OneBagOnly    = true  -- Only one backpack in a player's inventory at a time
Config.BlockBagInBag = true  -- Stop a backpack being stuffed inside another backpack
Config.ShowInVehicle = false -- Keep the prop visible on the player's back while driving

-- ███████╗████████╗ ██████╗ ██████╗  █████╗  ██████╗ ███████╗
-- ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝ ██╔════╝
-- ███████╗   ██║   ██║   ██║██████╔╝███████║██║  ███╗█████╗
-- ╚════██║   ██║   ██║   ██║██╔══██╗██╔══██║██║   ██║██╔══╝
-- ███████║   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╔╝███████╗
-- ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝

-- Fallback storage for any bag that doesn't set its own slots/weight
Config.Storage = {
    slots  = 8,     -- Number of inventory slots
    weight = 10000, -- Total weight in grams (10000 = 10kg)
}

--  █████╗ ████████╗████████╗ █████╗  ██████╗██╗  ██╗
-- ██╔══██╗╚══██╔══╝╚══██╔══╝██╔══██╗██╔════╝██║  ██║
-- ███████║   ██║      ██║   ███████║██║     ███████║
-- ██╔══██║   ██║      ██║   ██╔══██║██║     ██╔══██║
-- ██║  ██║   ██║      ██║   ██║  ██║╚██████╗██║  ██║
-- ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝

-- Where the prop sits on the player's back.
-- Bags built from the same clothing base share this pivot, so most need nothing here.
-- Use the studio (Config.Debug = true, then /bagtune) to tune a bag and copy the values.
Config.DefaultOffset = {
    bone = 24818, -- SKEL_Spine_Root
    pos  = { x = -0.270, y = 0.010, z = -0.020 }, -- Position offset from the bone
    rot  = { x = 0.0,    y = 90.0,  z = 175.0  }, -- Rotation in degrees
}

-- ██████╗ ██████╗  ██████╗ ██████╗
-- ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗
-- ██║  ██║██████╔╝██║   ██║██████╔╝
-- ██║  ██║██╔══██╗██║   ██║██╔═══╝
-- ██████╔╝██║  ██║╚██████╔╝██║
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝

-- The bag hits the ground as its OWN model, not a generic loot bag
Config.Drop = {
    enabled      = true, -- Master switch for physical drops
    onDeath      = true, -- Drop the bag when the player dies
    onRob        = true, -- Robbery drops it instead of handing it straight over
    despawn      = 900,  -- Seconds before an untouched drop is cleaned up (0 = never)
    keepContents = true, -- false wipes the stash when it drops
}

-- ██╗    ██╗███████╗██╗ ██████╗ ██╗  ██╗████████╗
-- ██║    ██║██╔════╝██║██╔════╝ ██║  ██║╚══██╔══╝
-- ██║ █╗ ██║█████╗  ██║██║  ███╗███████║   ██║
-- ██║███╗██║██╔══╝  ██║██║   ██║██╔══██║   ██║
-- ╚███╔███╔╝███████╗██║╚██████╔╝██║  ██║   ██║
--  ╚══╝╚══╝ ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝

-- Penalties scale off how FULL the bag is, not its capacity,
-- so an empty duffel costs nothing and a stuffed one hurts
Config.WeightEffects = {
    enabled = false, -- Off by default, opt in

    threshold      = 0.5,  -- Nothing happens below this fill fraction (0.5 = 50% full)
    minMoveRate    = 0.88, -- Movement multiplier at 100% full (1.0 = no change)
    staminaDrain   = 2.0,  -- Stamina drains this many times faster at full load
    noSprintAbove  = 0.0,  -- Block sprinting past this fill fraction (0 = never)
    updateInterval = 1000, -- ms between checks when no penalty is active
}

-- ██████╗  ██████╗ ██████╗ ██████╗ ███████╗██████╗ ██╗   ██╗
-- ██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗╚██╗ ██╔╝
-- ██████╔╝██║   ██║██████╔╝██████╔╝█████╗  ██████╔╝ ╚████╔╝
-- ██╔══██╗██║   ██║██╔══██╗██╔══██╗██╔══╝  ██╔══██╗  ╚██╔╝
-- ██║  ██║╚██████╔╝██████╔╝██████╔╝███████╗██║  ██║   ██║
-- ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝

-- Taking a bag off someone's back. The prop is already visible on the ped,
-- which is what makes bags matter socially instead of being a free upgrade.
Config.Robbery = {
    enabled = true,

    requireHandsUp = true,  -- Victim must have their hands up
    requireCuffed  = false, -- Or be cuffed
    allowDead      = true,  -- Dead players can always be looted
    requireWeapon  = true,  -- Robber needs a weapon out (ignored if the victim is dead)

    -- Can a stowed (taken off) bag still be robbed?
    -- false means players just walk around with their bag off to dodge robberies
    -- entirely, which makes this whole system opt-out. true keeps it honest.
    allowStowed = true,

    distance = 2.0,   -- Max meters between robber and victim
    duration = 5000,  -- ms on the progress bar
    cooldown = 30,    -- Seconds before the same victim can be robbed again

    notifyVictim = true, -- Tell the victim their bag was taken
    policeEvent  = nil,  -- Event name to fire for a PD alert, nil = disabled
}

-- ██████╗ ██╗      █████╗  ██████╗██╗███╗   ██╗ ██████╗
-- ██╔══██╗██║     ██╔══██╗██╔════╝██║████╗  ██║██╔════╝
-- ██████╔╝██║     ███████║██║     ██║██╔██╗ ██║██║  ███╗
-- ██╔═══╝ ██║     ██╔══██║██║     ██║██║╚██╗██║██║   ██║
-- ██║     ███████╗██║  ██║╚██████╗██║██║ ╚████║╚██████╔╝
-- ╚═╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Set a bag down as a world prop that stays put and stays lootable.
-- Dead drops, stash points, chop shops.
Config.Placement = {
    enabled = true,

    maxDistance = 3.0,  -- How far ahead a bag can be set down
    rotateStep  = 15.0, -- Degrees per scroll notch while positioning

    ownerOnly    = false, -- true = only the placer can ever pick it back up
    pickupAnyone = true,  -- false = contents lootable but the bag stays put

    -- Players pick private or public when setting a bag down
    askAccess     = true,      -- Show the private/public choice
    defaultAccess = 'private', -- Used when askAccess is false
    allowRetoggle = true,      -- Owner can flip it later via third-eye

    persist        = true, -- Placed bags survive a restart (needs oxmysql + install.sql)
    despawn        = 0,    -- Seconds before untouched bags are cleared (0 = never)
    blockInVehicle = true, -- Can't place while sat in a vehicle
    maxPerPlayer   = 3,    -- Cap on placed bags per player
}

-- ███████╗██╗  ██╗ ██████╗ ██████╗
-- ██╔════╝██║  ██║██╔═══██╗██╔══██╗
-- ███████╗███████║██║   ██║██████╔╝
-- ╚════██║██╔══██║██║   ██║██╔═══╝
-- ███████║██║  ██║╚██████╔╝██║
-- ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝

-- The store players buy bags from. Themes and categories are pulled straight
-- from the entries in Config.Backpacks, so adding a bag adds it to the shop.
Config.Shop = {
    enabled = true,

    currency = 'cash',   -- 'cash' or 'bank'
    canSell  = true,     -- Players can sell a bag back
    sellRate = 0.5,      -- Fraction of the price returned when selling

    -- PREVIEW
    -- The bag is attached to the player's own character, exactly as it would
    -- be worn, so what they see is what they get.
    previewDistance = 1.55,  -- How far the camera sits from the character
    previewFov      = 34.0,  -- Lower = tighter framing
    previewShift    = 0.62,  -- Pushes the character left, clear of the panel

    blurBackground    = true,  -- Blur the world behind the character
    timecycle         = nil,   -- Optional timecycle, e.g. 'hud_def_blur'
    timecycleStrength = 0.7,

    showSearch = true,   -- Search box. Leave on if you run a big catalogue.

    -- HOW PLAYERS OPEN THE STORE
    -- 'ped'     = walk up to a shop keeper / marker at the coords below
    -- 'command' = a chat command from anywhere, no physical store
    -- 'both'    = both at once
    openMode = 'ped',

    command = 'bagstore', -- Used when openMode is 'command' or 'both'
    keybind = false,      -- true also registers it as a rebindable key

    -- THEME FILTER
    -- Turn this off for a plain catalogue with no theme tabs, or trim the list
    -- to only the themes your server actually uses.
    useThemes = true,

    Themes = {
        { key = 'all',       label = 'All'       },
        { key = 'realistic', label = 'Realistic' },
        { key = 'cartoon',   label = 'Cartoon'   },
        { key = 'animal',    label = 'Animal'    },
        { key = 'halloween', label = 'Halloween' },
    },

    -- JOB BAGS
    -- Bags with a `job` field only appear for players on that job, in their own
    -- tab. A mechanic never sees police bags and vice versa.
    useJobTab = true,
    jobTabLabel = 'Issued',  -- Label on the tab holding the player's job bags

    -- CATEGORY FILTER
    useCategories = true,

    Categories = {
        { key = 'all',        label = 'All'         },
        { key = 'backpack',   label = 'Backpacks'   },
        { key = 'pocketbook', label = 'Pocketbooks' },
        { key = 'duffel',     label = 'Duffels'     },
    },

    -- Physical store locations. Ignored entirely when openMode is 'command'.
    Locations = {
        {
            label   = 'Bag Store',
            coords  = vector3(72.19, 6.63, 68.88),
            heading = 240.0,

            ped = `s_f_y_shop_low`, -- Shop keeper model, nil for a marker instead

            marker = { -- Drawn when there's no ped
                type  = 21,
                scale = 0.6,
                r = 8, g = 175, b = 162, a = 140,
            },

            blip = {
                sprite = 52,
                color  = 26,
                scale  = 0.7,
                label  = 'Bag Store',
            },

            previewOffset = { x = 0.0, y = 1.2, z = 0.65 }, -- Where the bag floats while previewing
        },
    },
}

-- ██████╗ ██████╗  ██████╗ ███╗   ███╗██████╗ ████████╗███████╗
-- ██╔══██╗██╔══██╗██╔═══██╗████╗ ████║██╔══██╗╚══██╔══╝██╔════╝
-- ██████╔╝██████╔╝██║   ██║██╔████╔██║██████╔╝   ██║   ███████╗
-- ██╔═══╝ ██╔══██╗██║   ██║██║╚██╔╝██║██╔═══╝    ██║   ╚════██║
-- ██║     ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║        ██║   ███████║
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝        ╚═╝   ╚══════╝

-- Every label the player sees. Rewrite or translate freely.
Config.Prompts = {
    useTarget = true, -- ox_target options on bags and placed props

    menuTitle  = 'Backpack',        -- Context menu header fallback
    openWorn   = 'Open backpack',   -- Open the bag you're wearing
    openPlaced = 'Open',            -- Open a bag on the ground
    place      = 'Set down',        -- Start placement mode
    pickup     = 'Pick up',         -- Retrieve a placed bag
    stow       = 'Take off',        -- Hide the prop, keep the item
    wear       = 'Put on',          -- Show the prop again
    takeOff    = 'Take off',
    putOn      = 'Put on',
    rob        = 'Take backpack',   -- Robbery option on another player
    give       = 'Hand over',

    placeConfirm = '[E] Place    [SCROLL] Rotate    [X] Cancel',

    accessPrivate = 'Private',      -- Only the owner can use it
    accessPublic  = 'Public',       -- Anyone can use it
    makePrivate   = 'Make private',
    makePublic    = 'Make public',
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

-- Robbery and drops are what get exploited and what you'll be asked to
-- adjudicate. Console logging is always on; Discord needs a webhook.
Config.Logs = {
    enabled = true,
    webhook = '', -- Discord webhook URL. Empty = console only.

    events = {
        equip    = false, -- Very noisy, only for investigating
        open     = false, -- Very noisy, only for investigating
        stow     = false,
        rob      = true,  -- Who took what from whom
        drop     = true,  -- Death drops
        place    = true,  -- Bag set down, with coords
        pickup   = true,  -- Placed bag picked up
        access   = false, -- Private/public toggles
        contents = true,  -- Snapshot what was inside on rob and drop
    },

    maxContentLines = 12, -- Item lines to include in a contents snapshot

    botName = 'Backpack',
    colors = {
        rob    = 15548997, -- Red
        drop   = 15105570, -- Orange
        place  = 3066993,  -- Green
        pickup = 3447003,  -- Blue
        info   = 9807270,  -- Grey
    },
}

--  █████╗ ███╗   ██╗██╗███╗   ███╗███████╗
-- ██╔══██╗████╗  ██║██║████╗ ████║██╔════╝
-- ███████║██╔██╗ ██║██║██╔████╔██║███████╗
-- ██╔══██║██║╚██╗██║██║██║╚██╔╝██║╚════██║
-- ██║  ██║██║ ╚████║██║██║ ╚═╝ ██║███████║
-- ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝╚══════╝

Config.Animations = {
    enabled = true,
    freeze  = false, -- Lock the player in place during equip/unequip

    equip = { -- Putting the bag on
        dict = 'clothingtie', anim = 'try_tie_negative_a', duration = 1800, flag = 49,
    },

    unequip = { -- Taking the bag off
        dict = 'clothingtie', anim = 'try_tie_negative_a', duration = 1500, flag = 49,
    },

    open = { -- Quick reach-back when opening the bag
        dict = 'mp_common', anim = 'givetake1_a', duration = 900, flag = 49,
    },
}

-- ██████╗  █████╗  ██████╗██╗  ██╗██████╗  █████╗  ██████╗██╗  ██╗███████╗
-- ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
-- ██████╔╝███████║██║     █████╔╝ ██████╔╝███████║██║     █████╔╝ ███████╗
-- ██╔══██╗██╔══██║██║     ██╔═██╗ ██╔═══╝ ██╔══██║██║     ██╔═██╗ ╚════██║
-- ██████╔╝██║  ██║╚██████╗██║  ██╗██║     ██║  ██║╚██████╗██║  ██╗███████║
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

-- Models can live in ANY resource. This only stores the model NAME, so a bag
-- streamed from your own props resource works exactly like one in this script's
-- stream/ folder. Nothing here needs to move when you update the script.
--
-- key      = the item name in ox_inventory
-- label    = shown in the menu, notifications and the studio
-- model    = streamed .ydr model name
-- category = grouping for the shop: 'backpack', 'pocketbook', 'duffel'
-- slots    = optional, overrides Config.Storage.slots
-- weight   = optional, overrides Config.Storage.weight
-- offset   = optional, overrides Config.DefaultOffset (use /bagtune to get these)
-- variants = optional texture skins baked into the model, index starts at 0
-- theme    = shop tab: 'realistic', 'cartoon', 'animal', 'halloween'
-- price    = shop price, leave nil to keep a bag out of the store
-- job      = restrict to one job ('police') or several ({ 'police', 'sheriff' }).
--            Only that job sees it in the shop and only they can equip it.
-- grade    = optional minimum job grade

Config.Backpacks = {

    ['backpack'] = {
        label    = 'Polar Bear Backpack',
        model    = 'nayzeee_backpack_016',
        category = 'backpack',
        theme    = 'animal',
        price    = 2500,
        slots    = 8,
        weight   = 10000,
    },

    ['nayzeee_backpack_cutebear'] = {
        label    = 'Nayzeee Backpack Cutebear',
        model    = 'nayzeee_backpack_cutebear',
        category = 'backpack',
        theme    = 'animal',
        price    = 2500,
    },

    ['nayzeee_backpack_snorlax'] = {
        label    = 'Nayzeee Backpack Snorlax',
        model    = 'nayzeee_backpack_snorlax',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_alyx'] = {
        label    = 'Nayzeee Backpack Alyx',
        model    = 'nayzeee_backpack_alyx',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_lifesaver'] = {
        label    = 'Nayzeee Backpack Lifesaver',
        model    = 'nayzeee_backpack_lifesaver',
        category = 'backpack',
        theme    = 'realistic',
        price    = 2000,
    },

    ['nayzeee_backpack_shoulderbag'] = {
        label    = 'Nayzeee Backpack Shoulderbag',
        model    = 'nayzeee_backpack_shoulderbag_01',
        category = 'pocketbook',
        theme    = 'realistic',
        price    = 2000,
        variants = {
            { label = 'A', model = 'nayzeee_backpack_shoulderbag_01' },
            { label = 'B', model = 'nayzeee_backpack_shoulderbag_02' },
        },
    },

    ['nayzeee_backpack_heartpurse'] = {
        label    = 'Nayzeee Backpack Heartpurse',
        model    = 'nayzeee_backpack_heartpurse',
        category = 'pocketbook',
        theme    = 'cartoon',
        price    = 2000,
    },

    ['nayzeee_backpack_heart'] = {
        label    = 'Nayzeee Backpack Heart',
        model    = 'nayzeee_backpack_heart',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2000,
    },

    ['nayzeee_backpack_alien'] = {
        label    = 'Nayzeee Backpack Alien',
        model    = 'nayzeee_backpack_alien',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_blueshark'] = {
        label    = 'Nayzeee Backpack Blueshark',
        model    = 'nayzeee_backpack_blueshark',
        category = 'backpack',
        theme    = 'animal',
        price    = 2500,
    },

    ['nayzeee_backpack_pug'] = {
        label    = 'Nayzeee Backpack Pug',
        model    = 'nayzeee_backpack_pug',
        category = 'backpack',
        theme    = 'animal',
        price    = 2500,
    },

    ['nayzeee_backpack_puruplegoth'] = {
        label    = 'Nayzeee Backpack Puruplegoth',
        model    = 'nayzeee_backpack_puruplegoth',
        category = 'backpack',
        theme    = 'halloween',
        price    = 3000,
    },

    ['nayzeee_backpack_rick'] = {
        label    = 'Nayzeee Backpack Rick',
        model    = 'nayzeee_backpack_rick',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_space'] = {
        label    = 'Nayzeee Backpack Space',
        model    = 'nayzeee_backpack_space',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 3000,
    },

    ['nayzeee_backpack_street'] = {
        label    = 'Nayzeee Backpack Street',
        model    = 'nayzeee_backpack_street',
        category = 'backpack',
        theme    = 'realistic',
        price    = 2500,
    },

    ['nayzeee_backpack_survivor'] = {
        label    = 'Nayzeee Backpack Survivor',
        model    = 'nayzeee_backpack_survivor',
        category = 'backpack',
        theme    = 'realistic',
        price    = 3000,
    },

    ['nayzeee_backpack_usahanna'] = {
        label    = 'Nayzeee Backpack Usahanna',
        model    = 'nayzeee_backpack_usahanna',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_teddyburger'] = {
        label    = 'Nayzeee Backpack Teddyburger',
        model    = 'nayzeee_backpack_teddyburger',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_teddyskull'] = {
        label    = 'Nayzeee Backpack Teddyskull',
        model    = 'nayzeee_backpack_teddyskull',
        category = 'backpack',
        theme    = 'halloween',
        price    = 3000,
    },

    ['nayzeee_backpack_lean'] = {
        label    = 'Nayzeee Backpack Lean',
        model    = 'nayzeee_backpack_lean',
        category = 'backpack',
        theme    = 'realistic',
        price    = 2500,
    },


    -- JOB BAGS -------------------------------------------------------------
    -- Only players on the job see these in the shop, and only they can wear
    -- one. The bag on their back becomes part of the uniform.

    -- ['bag_police'] = {
    --     label    = 'Patrol Pack',
    --     model    = 'nayzeee_bag_police',
    --     category = 'backpack',
    --     theme    = 'realistic',
    --     job      = 'police',   -- or { 'police', 'sheriff', 'state' }
    --     grade    = 0,          -- Minimum job grade
    --     price    = 0,          -- 0 = free for the job
    --     slots    = 14,
    --     weight   = 20000,
    -- },

    -- ['bag_ems'] = {
    --     label    = 'Medic Bag',
    --     model    = 'nayzeee_bag_ems',
    --     category = 'backpack',
    --     theme    = 'realistic',
    --     job      = { 'ambulance', 'ems' },
    --     price    = 0,
    --     slots    = 12,
    --     weight   = 18000,
    -- },

    -- ['bag_mechanic'] = {
    --     label    = 'Tool Bag',
    --     model    = 'nayzeee_bag_mechanic',
    --     category = 'duffel',
    --     theme    = 'realistic',
    --     job      = 'mechanic',
    --     price    = 0,
    --     slots    = 18,
    --     weight   = 30000,
    -- },

    -- Pocketbooks and purses work the same way, they just sit on a different bone
    -- ['pocketbook_classic'] = {
    --     label    = 'Classic Pocketbook',
    --     model    = 'nayzeee_pocketbook_classic',
    --     category = 'pocketbook',
    --     slots    = 5,
    --     weight   = 4000,
    --     offset   = {
    --         bone = 24817, -- Spine 1, sits higher for a shoulder bag
    --         pos  = { x = -0.180, y = 0.090, z = -0.040 },
    --         rot  = { x = 0.0, y = 90.0, z = 175.0 },
    --     },
    -- },

    -- One model, several skins, switched in-script
    -- ['backpack_lean'] = {
    --     label  = 'Lean Backpack',
    --     model  = 'vonnie_backpack_lean',
    --     slots  = 12,
    --     weight = 15000,
    --     variants = {
    --         [0] = 'Default',
    --         [1] = 'Red',
    --         [2] = 'Blue',
    --     },
    -- },

    -- A bigger bag that needed its own position
    -- ['backpack_duffel'] = {
    --     label  = 'Duffel Bag',
    --     model  = 'nayzeee_backpack_duffel',
    --     slots  = 20,
    --     weight = 40000,
    --     offset = { pos = { x = -0.270, y = 0.010, z = 0.060 } },
    -- },
}

-- ██╗ ██████╗ ██████╗ ███╗   ██╗
-- ██║██╔════╝██╔═══██╗████╗  ██║
-- ██║██║     ██║   ██║██╔██╗ ██║
-- ██║██║     ██║   ██║██║╚██╗██║
-- ██║╚██████╗╚██████╔╝██║ ╚████║
-- ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝

-- Studio icon staging. Lifts the prop above the map so only sky sits behind it,
-- giving a clean edge to cut out for an inventory image. Config.Debug only.
Config.IconCapture = {
    distance = 1.15,  -- Camera distance from the prop
    heading  = 210.0, -- Angle the prop is turned to
    pitch    = -8.0,  -- Camera tilt in degrees

    -- STAGING SPOT
    -- nil lifts the prop 180m straight up, so only sky sits behind it.
    -- Point this at a green screen MLO and the prop spawns there instead,
    -- which gives a flat key colour that cuts out perfectly.
    stagingCoords = nil,  -- e.g. vector3(-1057.0, -230.0, 44.0)
    stagingHeight = 180.0, -- Used only when stagingCoords is nil
}

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

Config.Notify = function(msg, type)
    lib.notify({
        description = msg,
        type = type or 'inform',
        position = 'top',
    })
end

--- Storage settings for a bag, falling back to the defaults
function Config.GetStorage(bagKey)
    local bag = Config.Backpacks[bagKey]
    return {
        slots  = (bag and bag.slots)  or Config.Storage.slots,
        weight = (bag and bag.weight) or Config.Storage.weight,
    }
end

-- ███████╗████████╗██████╗ ██╗███╗   ██╗ ██████╗ ███████╗
-- ██╔════╝╚══██╔══╝██╔══██╗██║████╗  ██║██╔════╝ ██╔════╝
-- ███████╗   ██║   ██████╔╝██║██╔██╗ ██║██║  ███╗███████╗
-- ╚════██║   ██║   ██╔══██╗██║██║╚██╗██║██║   ██║╚════██║
-- ███████║   ██║   ██║  ██║██║██║ ╚████║╚██████╔╝███████║
-- ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

Strings = {
    one_bag_only = 'You can only carry one backpack.',
    bag_in_bag   = 'That will not fit inside another backpack.',
    cannot_open  = 'You cannot open this right now.',
    bag_dropped  = 'Your backpack dropped.',
    busy         = 'You are busy.',
    no_bag       = 'You are not carrying a bag.',
    too_heavy    = 'Your bag is weighing you down.',

    stowed       = 'Backpack taken off.',
    worn         = 'Backpack put on.',

    placed       = 'Bag set down.',
    picked_up    = 'Bag picked up.',
    place_bad    = 'You cannot place it there.',
    place_max    = 'You have too many bags placed already.',
    not_yours    = 'That is not your bag.',
    is_private   = 'That bag is locked.',
    now_private  = 'Bag set to private.',
    now_public   = 'Bag set to public.',

    rob_started  = 'Taking the bag...',
    rob_success  = 'You took the bag.',
    rob_failed   = 'You did not get it.',
    rob_victim   = 'Your bag was taken.',
    rob_cooldown = 'Not again so soon.',
    rob_moved    = 'They got away.',

    shop_bought  = 'Purchased.',
    shop_sold    = 'Sold.',
    shop_broke   = 'You cannot afford that.',
    shop_full    = 'No room for that.',
    shop_nothing = 'You have nothing to sell.',
    shop_job     = 'That bag is issued to a job you are not on.',
    job_only     = 'This bag belongs to a job you are not on.',
}
