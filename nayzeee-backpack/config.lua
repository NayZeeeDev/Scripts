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

    BACKPACK SCRIPT - 2.0.0
    Discord: discord.gg/nayzeeedev

]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Debug = false -- Console debug prints

-- 'auto' picks whichever is running: es_extended, qbx_core, qb-core, or none
Config.Framework = 'auto'

Config.OneBagOnly    = true  -- Only one backpack in a player's inventory at a time
Config.BlockBagInBag = true  -- Stop a backpack being stuffed inside another backpack
Config.ShowInVehicle = false -- Keep the prop visible on the player's back while driving

-- Who counts as an admin for the studio (/bagtune), live storage edits and /bagitems.
-- Either the ACE below, or one of the framework groups.
Config.Admin = {
    ace    = 'nayzeee.backpack', -- add_ace group.admin nayzeee.backpack allow
    groups = { 'admin', 'superadmin', 'god' },
}

-- ███████╗████████╗ ██████╗ ██████╗  █████╗  ██████╗ ███████╗
-- ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝ ██╔════╝
-- ███████╗   ██║   ██║   ██║██████╔╝███████║██║  ███╗█████╗
-- ╚════██║   ██║   ██║   ██║██╔══██╗██╔══██║██║   ██║██╔══╝
-- ███████║   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╔╝███████╗
-- ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝

-- Fallback storage for any bag that doesn't set its own slots/weight.
-- Admins can also change slots/weight per bag live from /bagtune > Look;
-- those edits are saved to data/overrides.json and win over this file.
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
-- Use the studio (/bagtune) to fit a bag, then hit Save (or Copy).
Config.DefaultOffset = {
    bone = 24818, -- SKEL_Spine3 (upper back)
    pos  = { x = -0.270, y = 0.010, z = -0.020 }, -- Position offset from the bone
    rot  = { x = 0.0,    y = 90.0,  z = 175.0  }, -- Rotation in degrees
}

--  ██████╗ █████╗ ██████╗ ██████╗ ██╗   ██╗
-- ██╔════╝██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝
-- ██║     ███████║██████╔╝██████╔╝ ╚████╔╝
-- ██║     ██╔══██║██╔══██╗██╔══██╗  ╚██╔╝
-- ╚██████╗██║  ██║██║  ██║██║  ██║   ██║
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝

-- How purses and pocketbooks are carried. A bag opts in with `carry = 'purse'`.
--
-- While a carry-style bag is worn the player loops an UPPER BODY pose, so they
-- keep walking, running and turning normally, but hold the purse like they
-- mean it instead of swinging it around with the default walk.
--
-- The pose pauses by itself in vehicles, while swimming/climbing/ragdolling,
-- with a weapon out, and whenever another script (emotes, progress bars) is
-- playing its own animation. It comes back on its own afterwards.
--
-- Pose files (.ycd) go in stream/anims/ — see stream/README.md.
Config.Carry = {
    enabled = true,

    checkInterval = 600,   -- ms between "is the pose still playing" checks (0.00 resmon)
    blendIn       = 4.0,   -- Higher = snappier transition into the pose

    -- Optional walk style while carrying. nil keeps the player's own walk.
    -- Cute options: 'move_f@femme@', 'move_f@sexy@a', 'move_f@heels@c', 'move_f@chichi'
    walkStyle = nil,

    -- Players can pick their own pose from the bag menu (saved on the item)
    letPlayersPick = true,

    -- 'carry' is GTA's own one-handed carry (the jerrycan / briefcase hold):
    -- the arm hangs naturally and the walk stays clean. The others are the
    -- custom photo poses; they look great standing still but stiffen the
    -- upper body while walking, so they're opt-in from the pose menu.
    Poses = {
        { key = 'carry',    label = 'Carry',                dict = 'move_weapon@jerrycan@generic',     clip = 'idle' },
        { key = 'withbag1', label = 'Classic (custom)',     dict = 'clementine@withyourbag01',         clip = 'withyourbag01_clip' },
        { key = 'withbag2', label = 'Arm crook (custom)',   dict = 'clementine@withyourbag02',         clip = 'withyourbag02_clip' },
        { key = 'withbag3', label = 'Hip hold (custom)',    dict = 'clementine@withyourbag03',         clip = 'withyourbag03_clip' },
        { key = 'withbag4', label = 'Shoulder (custom)',    dict = 'clementine@withyourbag04',         clip = 'withyourbag04_clip' },
        { key = 'withbag5', label = 'Clutch (custom)',      dict = 'clementine@withyourbag05',         clip = 'withyourbag05_clip' },
        { key = 'model1',   label = 'Runway (custom)',      dict = 'f_modelpose_withbag_1@avenelanim', clip = 'f_modelpose_withbag_1_clip' },
    },

    -- A style = which pose plays + a starting offset.
    -- Every purse model has its own pivot, so fit each one once:
    -- /bagtune > pick the purse (its pose starts by itself) > Carry preset
    -- "Right hand" > nudge / rotate > Save fit. That saved fit is what everyone sees.
    Styles = {
        purse = {
            label = 'Purse in hand',
            pose  = 'carry',
            offset = {
                bone = 28422, -- PH_R_Hand (the grip point the carry pose holds)
                pos  = { x = 0.000, y = 0.000, z = 0.000 },
                rot  = { x = 0.0,   y = 0.0,   z = 0.0 },
            },
        },
        purse_left = {
            label = 'Purse in left hand',
            pose  = 'carry',
            offset = {
                bone = 60309, -- PH_L_Hand
                pos  = { x = 0.000, y = 0.000, z = 0.000 },
                rot  = { x = 0.0,   y = 0.0,   z = 0.0 },
            },
        },
        forearm = {
            label = 'On the forearm',
            pose  = 'withbag2',
            offset = {
                bone = 28252, -- SKEL_R_Forearm
                pos  = { x = 0.000, y = 0.000, z = 0.000 },
                rot  = { x = 0.0,   y = 0.0,   z = 0.0 },
            },
        },
    },
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
    keepJobBags  = true, -- Job-issued bags never drop on death
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
    requireCuffed  = false, -- Or be cuffed (wasabi_police / qb / esx cuffs all detected)
    allowDead      = true,  -- Dead players can always be looted
    requireWeapon  = true,  -- Robber needs a weapon out (ignored if the victim is dead)

    -- Can a stowed (taken off) bag still be robbed?
    -- false means players just walk around with their bag off to dodge robberies
    -- entirely, which makes this whole system opt-out. true keeps it honest.
    allowStowed = true,

    protectJobBags = true, -- Job-issued bags can't be robbed

    distance = 2.0,   -- Max meters between robber and victim
    duration = 5000,  -- ms on the progress bar
    cooldown = 30,    -- Seconds before the same victim can be robbed again

    notifyVictim = true, -- Tell the victim their bag was taken

    -- Police alert. 'auto' uses ps-dispatch / cd_dispatch / qs-dispatch /
    -- wasabi_police if one is running. false = off. A string = your own
    -- server event, fired as TriggerEvent(name, robberId, victimId, coords).
    dispatch = 'auto',
    dispatchChance = 100, -- % chance an alert goes out
}

-- ██████╗ ██╗      █████╗  ██████╗██╗███╗   ██╗ ██████╗
-- ██╔══██╗██║     ██╔══██╗██╔════╝██║████╗  ██║██╔════╝
-- ██████╔╝██║     ███████║██║     ██║██╔██╗ ██║██║  ███╗
-- ██╔═══╝ ██║     ██╔══██║██║     ██║██║╚██╗██║██║   ██║
-- ██║     ███████╗██║  ██║╚██████╗██║██║ ╚████║╚██████╔╝
-- ╚═╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Set a bag down as a world prop that stays put and stays lootable.
-- The ghost follows where you look: [E] place, [SCROLL] rotate, [BACKSPACE] cancel.
Config.Placement = {
    enabled = true,

    maxDistance = 4.0,  -- How far from the player the bag can be set down
    rotateStep  = 10.0, -- Degrees per scroll notch (hold SHIFT for 1/5 of that)
    maxSlope    = 0.55, -- Surface must face at least this much upward (blocks walls)

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
    renderDistance = 60.0, -- Placed bags only spawn as props within this range
}

-- ███████╗██╗  ██╗ ██████╗ ██████╗
-- ██╔════╝██║  ██║██╔═══██╗██╔══██╗
-- ███████╗███████║██║   ██║██████╔╝
-- ╚════██║██╔══██║██║   ██║██╔═══╝
-- ███████║██║  ██║╚██████╔╝██║
-- ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝

-- The store. Walking up to the counter moves the camera over it and the bags
-- float above the counter in a carousel. A/D or the mouse wheel swaps bags,
-- drag spins them, ENTER buys, T tries the bag on your character.
-- Themes and types come straight from Config.Backpacks.
Config.Shop = {
    enabled = true,

    currency = 'cash',   -- 'cash' or 'bank'
    canSell  = true,     -- Players can sell a bag back
    sellRate = 0.5,      -- Fraction of the price returned when selling

    -- COUNTER DISPLAY
    spinSpeed      = 14.0,  -- Degrees per second the featured bag turns
    transitionTime = 420,   -- ms for the slide between bags
    sideBags       = true,  -- Show the previous / next bag either side
    depthOfField   = true,  -- Soft-focus the store behind the counter

    -- Try-on view (T): the old character preview
    previewDistance = 1.55,
    previewFov      = 34.0,

    -- HOW PLAYERS OPEN THE STORE
    -- 'ped'     = walk up to a shop keeper / marker at the coords below
    -- 'command' = a chat command from anywhere, no physical store
    -- 'both'    = both at once
    openMode = 'ped',

    command = 'bagstore', -- Used when openMode is 'command' or 'both'
    keybind = false,      -- true also registers it as a rebindable key

    useThemes = true,
    Themes = {
        { key = 'all',       label = 'All'       },
        { key = 'realistic', label = 'Realistic' },
        { key = 'cartoon',   label = 'Cartoon'   },
        { key = 'animal',    label = 'Animal'    },
        { key = 'halloween', label = 'Halloween' },
    },

    useCategories = true,
    Categories = {
        { key = 'all',        label = 'All'         },
        { key = 'backpack',   label = 'Backpacks'   },
        { key = 'pocketbook', label = 'Pocketbooks' },
        { key = 'shoulder',   label = 'Shoulder bags' },
        { key = 'duffel',     label = 'Duffels'     },
    },

    -- Job bags only appear for players on that job, in their own tab
    useJobTab   = true,
    jobTabLabel = 'Issued',

    Locations = {
        {
            label   = 'Bag Store',
            coords  = vector3(-1187.5038, -1187.8784, 6.7681), -- Shop keeper / interaction point
            heading = 101.4926,

            ped = `s_f_y_shop_low`, -- Shop keeper model, nil for a marker instead

            marker = { type = 21, scale = 0.6, r = 8, g = 175, b = 162, a = 140 },
            blip   = { sprite = 52, color = 26, scale = 0.7, label = 'Bag Store' },

            -- Where the bags float.
            --   bag     exact spot the featured bag floats at
            --   heading the way the shop keeper faces; the camera stands
            --           `camDistance` back from the bag on the customer's side
            --   cam     optional exact camera spot instead
            -- Leave `bag` out and it's worked out from the shop keeper:
            -- `forward` metres in front of them, `height` above their waist.
            display = {
                bag         = vector3(-1188.8307, -1187.9458, 7.9648),
                heading     = 101.4926,
                camDistance = 1.25,
                camHeight   = 0.22,
                fov         = 42.0,
                forward     = 0.70,
                height      = 0.30,
                -- cam = vector3(-1190.06, -1188.20, 8.18),
            },
        },
    },
}

--      ██╗ ██████╗ ██████╗ ███████╗
--      ██║██╔═══██╗██╔══██╗██╔════╝
--      ██║██║   ██║██████╔╝███████╗
-- ██   ██║██║   ██║██╔══██╗╚════██║
-- ╚█████╔╝╚██████╔╝██████╔╝███████║
--  ╚════╝  ╚═════╝ ╚═════╝ ╚══════╝

-- Bags with a `job` field. See integrations.lua for wasabi_ambulance,
-- wasabi_police and the rest, plus how other creators plug their own in.
Config.Jobs = {
    requireDuty = false, -- Job bags only work while on duty (ESX onDuty / QB onduty / wasabi)

    -- Going on duty hands you your job bag, going off duty takes it back.
    -- The SAME bag (and everything in it) comes back next shift.
    autoIssue  = false,
    autoReturn = false,

    -- Starter kit added to a job bag the first time it's issued.
    -- Items that don't exist in ox_inventory are skipped with a console warning.
    giveKit = true,

    -- Police can search (not take) the bag of a cuffed or hands-up player
    policeSearch = {
        enabled  = true,
        jobs     = { 'police', 'sheriff', 'state' },
        distance = 2.0,
        duration = 3500,
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
    pose       = 'Change pose',     -- Purse pose picker
    rob        = 'Take backpack',   -- Robbery option on another player
    search     = 'Search backpack', -- Police search option

    placeHelp  = '[E] Place  ·  [SCROLL] Rotate  ·  [BACKSPACE] Cancel',

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
        search   = true,  -- Police searches
        drop     = true,  -- Death drops
        place    = true,  -- Bag set down, with coords
        pickup   = true,  -- Placed bag picked up
        access   = false, -- Private/public toggles
        admin    = true,  -- Studio saves / storage edits
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
        dict = 'clothingshirt', anim = 'try_shirt_positive_d', duration = 1600, flag = 49,
    },

    unequip = { -- Taking the bag off
        dict = 'clothingtie', anim = 'try_tie_negative_a', duration = 1500, flag = 49,
    },

    open = { -- Quick reach-in when opening the bag
        dict = 'anim@heists@ornate_bank@grab_cash', anim = 'grab', duration = 900, flag = 49,
    },
}

-- ███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗
-- ██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗
-- ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║
-- ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║
-- ███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝
-- ╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝

-- The in-game backpack studio. Admin only (see Config.Admin).
Config.Studio = {
    enabled = true,
    command = 'bagtune',
}

-- Icon studio (/bagtune > Icon). Works like uz_AutoShot, built for bags:
-- the prop is lit inside a chroma box, the background is keyed out in the
-- browser, the image is trimmed + centred and saved as a transparent PNG.
-- Needs screenshot-basic. No yarn / node modules required.
Config.IconCapture = {
    coords  = vector3(0.0, 0.0, -150.0), -- Studio spot (under the map, nothing else renders)
    chroma  = 'green',  -- 'green' | 'magenta' | 'blue'. Use magenta for green bags, green for pink ones.
    size    = 512,      -- Output width/height in px
    padding = 0.08,     -- Empty border around the bag, as a fraction of the size
    fov     = 30.0,

    -- Where PNGs are written. The resource's own icons/ folder always gets a copy.
    -- true also writes straight into ox_inventory/web/images/<item>.png
    -- (restart ox_inventory, or the server, for new files to show).
    saveToInventory = true,

    -- Variants get their own image (<item>_<n>.png) and bought variants show it
    variantIcons = true,

    lights = {
        { offset = vector3(0.0, -2.0, 1.0),  range = 6.0, intensity = 3.0 },
        { offset = vector3(-2.0, 0.0, 1.0),  range = 5.0, intensity = 2.0 },
        { offset = vector3(2.0, 0.0, 1.0),   range = 5.0, intensity = 2.0 },
        { offset = vector3(0.0, 2.0, 1.0),   range = 4.0, intensity = 1.2 },
        { offset = vector3(0.0, 0.0, 2.5),   range = 5.0, intensity = 2.0 },
    },
}

-- ██████╗  █████╗  ██████╗██╗  ██╗██████╗  █████╗  ██████╗██╗  ██╗███████╗
-- ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
-- ██████╔╝███████║██║     █████╔╝ ██████╔╝███████║██║     █████╔╝ ███████╗
-- ██╔══██╗██╔══██║██║     ██╔═██╗ ██╔═══╝ ██╔══██║██║     ██╔═██╗ ╚════██║
-- ██████╔╝██║  ██║╚██████╗██║  ██╗██║     ██║  ██║╚██████╗██║  ██╗███████║
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

-- Models can live in ANY resource. This only stores the model NAME.
--
-- key      = the item name in ox_inventory (run /bagitems to print item entries)
-- label    = shown in the menu, notifications and the studio
-- model    = streamed .ydr model name
-- category = grouping for the shop: 'backpack', 'pocketbook', 'shoulder', 'duffel'
-- theme    = shop tab: 'realistic', 'cartoon', 'animal', 'halloween'
-- price    = shop price, leave nil to keep a bag out of the store
-- slots    = optional, overrides Config.Storage.slots
-- weight   = optional, overrides Config.Storage.weight
-- offset   = optional, overrides Config.DefaultOffset (use /bagtune to get these)
-- carry    = optional, a Config.Carry.Styles key ('purse', 'forearm' ...)
-- pose     = optional, default pose key for this bag (Config.Carry.Poses)
-- variants = optional skins, any of these formats:
--              { [0] = 'Default', [1] = 'Red' }                 -- texture variations
--              { { label = 'Red', texture = 1 }, ... }           -- same, explicit
--              { { label = 'A', model = 'bag_a' }, ... }         -- separate models
-- job      = restrict to one job ('police') or several ({ 'police', 'sheriff' })
-- grade    = optional minimum job grade
-- kit      = optional starter items for a job bag: { { 'bandage', 10 }, ... }

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
        label    = 'Cute Bear Backpack',
        model    = 'nayzeee_backpack_cutebear',
        category = 'backpack',
        theme    = 'animal',
        price    = 2500,
    },

    ['nayzeee_backpack_snorlax'] = {
        label    = 'Snorlax Backpack',
        model    = 'nayzeee_backpack_snorlax',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_alyx'] = {
        label    = 'Alyx Backpack',
        model    = 'nayzeee_backpack_alyx',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_lifesaver'] = {
        label    = 'Lifesaver Backpack',
        model    = 'nayzeee_backpack_lifesaver',
        category = 'backpack',
        theme    = 'realistic',
        price    = 2000,
    },

    ['nayzeee_backpack_shoulderbag'] = {
        label    = 'Shoulder Bag',
        model    = 'nayzeee_backpack_shoulderbag_01',
        category = 'shoulder',   -- crossbody: worn on the body like the backpacks, not hand-carried
        theme    = 'realistic',
        price    = 2000,
        slots    = 5,
        weight   = 5000,
        variants = {
            { label = 'Style A', model = 'nayzeee_backpack_shoulderbag_01' },
            { label = 'Style B', model = 'nayzeee_backpack_shoulderbag_02' },
        },
    },

    ['nayzeee_backpack_heartpurse'] = {
        label    = 'Heart Purse',
        model    = 'nayzeee_backpack_heartpurse',
        category = 'pocketbook',
        theme    = 'cartoon',
        price    = 2000,
        slots    = 5,
        weight   = 5000,
        carry    = 'purse',
    },

    ['nayzeee_backpack_heart'] = {
        label    = 'Heart Backpack',
        model    = 'nayzeee_backpack_heart',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2000,
    },

    ['nayzeee_backpack_alien'] = {
        label    = 'Alien Backpack',
        model    = 'nayzeee_backpack_alien',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_blueshark'] = {
        label    = 'Blue Shark Backpack',
        model    = 'nayzeee_backpack_blueshark',
        category = 'backpack',
        theme    = 'animal',
        price    = 2500,
    },

    ['nayzeee_backpack_pug'] = {
        label    = 'Pug Backpack',
        model    = 'nayzeee_backpack_pug',
        category = 'backpack',
        theme    = 'animal',
        price    = 2500,
    },

    ['nayzeee_backpack_puruplegoth'] = {
        label    = 'Purple Goth Backpack',
        model    = 'nayzeee_backpack_puruplegoth',
        category = 'backpack',
        theme    = 'halloween',
        price    = 3000,
    },

    ['nayzeee_backpack_rick'] = {
        label    = 'Rick Backpack',
        model    = 'nayzeee_backpack_rick',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_space'] = {
        label    = 'Space Backpack',
        model    = 'nayzeee_backpack_space',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 3000,
    },

    ['nayzeee_backpack_street'] = {
        label    = 'Street Backpack',
        model    = 'nayzeee_backpack_street',
        category = 'backpack',
        theme    = 'realistic',
        price    = 2500,
    },

    ['nayzeee_backpack_survivor'] = {
        label    = 'Survivor Backpack',
        model    = 'nayzeee_backpack_survivor',
        category = 'backpack',
        theme    = 'realistic',
        price    = 3000,
    },

    ['nayzeee_backpack_usahanna'] = {
        label    = 'Usahanna Backpack',
        model    = 'nayzeee_backpack_usahanna',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_teddyburger'] = {
        label    = 'Teddy Burger Backpack',
        model    = 'nayzeee_backpack_teddyburger',
        category = 'backpack',
        theme    = 'cartoon',
        price    = 2500,
    },

    ['nayzeee_backpack_teddyskull'] = {
        label    = 'Teddy Skull Backpack',
        model    = 'nayzeee_backpack_teddyskull',
        category = 'backpack',
        theme    = 'halloween',
        price    = 3000,
    },

    ['nayzeee_backpack_lean'] = {
        label    = 'Lean Backpack',
        model    = 'nayzeee_backpack_lean',
        category = 'backpack',
        theme    = 'realistic',
        price    = 2500,
    },

    -- JOB BAGS -------------------------------------------------------------
    -- Only players on the job see these in the shop, and only they can wear
    -- one. price = 0 shows as "Issued" with a Collect button.
    -- Swap the model for your own job bag prop once you've streamed one.

    -- ['bag_ems'] = {
    --     label    = 'Medic Bag',
    --     model    = 'nayzeee_bag_ems',
    --     category = 'duffel',
    --     theme    = 'realistic',
    --     job      = { 'ambulance', 'ems' },
    --     price    = 0,
    --     slots    = 14,
    --     weight   = 20000,
    --     -- wasabi_ambulance item names. Missing items are skipped.
    --     kit = {
    --         { 'bandage', 10 }, { 'medikit', 4 }, { 'defib', 1 },
    --         { 'tweezers', 2 }, { 'suturekit', 2 }, { 'icepack', 2 }, { 'burncream', 2 },
    --     },
    -- },

    -- ['bag_police'] = {
    --     label    = 'Patrol Pack',
    --     model    = 'nayzeee_bag_police',
    --     category = 'backpack',
    --     theme    = 'realistic',
    --     job      = { 'police', 'sheriff' },
    --     grade    = 0,
    --     price    = 0,
    --     slots    = 12,
    --     weight   = 18000,
    --     kit = { { 'handcuffs', 2 }, { 'bandage', 4 }, { 'radio', 1 } },
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
    --     kit = { { 'repairkit', 3 }, { 'cleaningkit', 2 } },
    -- },
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
    pose_set     = 'Pose changed.',

    placed       = 'Bag set down.',
    picked_up    = 'Bag picked up.',
    place_bad    = 'You cannot place it there.',
    place_far    = 'Too far away.',
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
    rob_job      = 'That is department kit, leave it.',

    search_start = 'Searching the bag...',
    search_none  = 'They are not carrying a bag.',

    shop_bought  = 'Purchased.',
    shop_sold    = 'Sold.',
    shop_broke   = 'You cannot afford that.',
    shop_full    = 'No room for that.',
    shop_nothing = 'You have nothing to sell.',
    shop_job     = 'That bag is issued to a job you are not on.',
    shop_empty   = 'Empty it first.',
    job_only     = 'This bag belongs to a job you are not on.',
    job_duty     = 'Go on duty to use this bag.',
    job_issued   = 'Your job bag was issued.',
    job_returned = 'Your job bag was handed back in.',

    no_admin     = 'You do not have permission for that.',
}
