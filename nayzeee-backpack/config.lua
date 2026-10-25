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

Config.Debug = false -- Console debug prints

-- 'auto' picks whichever is running: es_extended, qbx_core, qb-core, or none
Config.Framework = 'auto'

-- The resource your bag models stream from. Only used for a startup check
-- that warns when it isn't running. false = your props live elsewhere.
Config.PropsResource = 'nayzeee-backpack-props'

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
-- Pose files (.ycd) go in nayzeee-backpack-props/stream/anims/ (see its README).
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
        duffel = {
            label = 'Duffel in hand',
            pose  = 'carry',
            offset = {
                bone = 57005, -- SKEL_R_Hand
                pos  = { x = 0.300, y = 0.000, z = -0.020 },
                rot  = { x = -90.0, y = 0.0,   z = 90.0 },
            },
        },
    },
}

--  ██████╗ ██████╗ ███████╗███╗   ██╗
-- ██╔═══██╗██╔══██╗██╔════╝████╗  ██║
-- ██║   ██║██████╔╝█████╗  ██╔██╗ ██║
-- ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║
-- ╚██████╔╝██║     ███████╗██║ ╚████║
--  ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝

-- What opening a bag looks like. Everyone nearby sees it.
--   'kneel'  set the bag down in front, kneel and rummage while the inventory is open
--   'stand'  set it down in front and stand over it (duffels)
--   'quick'  reach back and open it where it is (purses use this)
-- A bag picks its own style with `open = { style = ... }`, otherwise
-- purses use 'quick' and everything else uses Config.OpenBag.style.
--
-- A bag can also show a different, OPEN model while it's set down:
--   open = { model = 'my_bag_open' }
-- and a third model when it holds cash:
--   open = { model = 'duffel_empty', cashModel = 'duffel_full', cashItems = { 'money' } }
Config.OpenBag = {
    enabled = true,
    style   = 'kneel',
    distance = 0.55,   -- How far in front of the player the bag is set down
    cashItems = { 'money', 'black_money', 'markedbills' }, -- what counts as cash for cashModel

    kneel = {
        enter = { dict = 'amb@medic@standing@kneel@enter', clip = 'enter', time = 900 },
        loop  = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
        exit  = { dict = 'amb@medic@standing@kneel@exit', clip = 'exit', time = 900 },
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

-- Zips, buckles, thuds and locks, heard by everyone nearby with distance
-- and left / right. Generated live, so there are no sound files to ship.
-- Prefer recordings? Put .ogg files in web/sounds/ and name them in `files`.
Config.Sounds = {
    enabled = true,
    volume  = 0.6,   -- Master volume, 0 - 1
    range   = 12.0,  -- Metres a sound carries

    -- Per sound, 0 = off
    levels = {
        zip_open = 1.0, zip_close = 1.0,  -- opening / closing a bag
        strap    = 0.8,                   -- putting it on / taking it off
        rustle   = 0.7,                   -- handing over, picking up
        drop     = 0.9,                   -- setting down, dropping
        lock = 1.0, unlock = 1.0, pick = 0.9, cut = 1.0, -- padlocks
    },

    -- Recordings instead of the generated sound, e.g. zip_open = 'sounds/zip_open.ogg'
    files = {},
}

-- Padlocks. Use the padlock item while wearing a bag and pick a code. The
-- lock stays on the bag wherever it goes: robbed, dropped, handed over or
-- set down. Whoever doesn't know the code has to pick it or cut it off.
--
-- ox_inventory items (/bagitems prints any that are missing):
--   bag_padlock  server = { export = 'nayzeee-backpack.usePadlock' }
--   lockpick, bolt_cutter   (plain items; use your own names below)
Config.Padlock = {
    enabled = true,
    item    = 'bag_padlock',
    digits  = 4,

    ownerSkipsCode = true, -- Whoever put the lock on never has to type it
    rememberCode   = true, -- Typed it right once? Not asked again until a restart or the code changes
    returnPadlock  = true, -- Taking your own lock off gives the padlock back

    maxTries = 3,   -- Wrong codes before a lockout
    lockout  = 60,  -- Seconds

    lockpick = {
        item = 'lockpick',
        difficulty = { 'easy', 'medium', 'medium', 'hard' }, -- ox_lib skill check
        keys = { 'w', 'a', 's', 'd' },
        breakChance = 35, -- % a failed attempt snaps the lockpick
        anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
    },

    cutter = {
        item = 'bolt_cutter',
        time = 6000, -- ms
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    },

    policeOpen = false, -- true: police searches open padlocked bags without cutting
}

-- Hand a bag to someone: you take it off, hold it out, they take it.
-- Everyone sees the bag go from your hand to theirs. Works for every
-- backpack, purse and duffel (contents and all) and for the outfit bag.
-- Bag menu > Hand to someone, third-eye a player, or /handbag.
Config.Handoff = {
    enabled  = true,
    distance = 2.5,   -- Max meters between the two players
    timeout  = 10,    -- Seconds they have to accept
    jobBags  = false, -- Job-issued bags can be handed over
    target   = true,  -- "Hand over bag" third-eye option on players (ox_target)

    -- Timing (ms). A bag you're wearing comes off your back first.
    takeOff = 1000,   -- Taking a worn bag off
    swap    = 1150,   -- Into the give animation, when the bag changes hands
    finish  = 2300,   -- Give animation done, the bag is theirs

    giveAnim = { dict = 'mp_common', clip = 'givetake1_a' },
    takeAnim = { dict = 'mp_common', clip = 'givetake1_b' },
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

    -- CLEAR THE COUNTER
    -- Props around the floating bags (monitors, keyboards, tills...) are
    -- hidden for the shopper only while the store is open, then come back.
    hideProps = {
        enabled = true,
        radius  = 1.8,  -- metres around the bags
        maxSize = 1.6,  -- anything bigger is left alone (counters, shelves, walls)

        -- Props baked into an MLO can only be hidden by model name.
        -- Set Config.Debug = true and open the store: the F8 console lists
        -- the props it found near the bags, so you can add their names here.
        models = {
            'prop_monitor_01a', 'prop_monitor_01b', 'prop_monitor_01c', 'prop_monitor_01d',
            'prop_monitor_02', 'prop_monitor_03b', 'prop_monitor_04a', 'prop_monitor_li',
            'prop_monitor_w_large', 'prop_ld_monitor_01', 'prop_pc_01a', 'prop_pc_02a',
            'prop_keyboard_01a', 'prop_keyboard_01b', 'prop_mouse_01', 'prop_mouse_01a', 'prop_mouse_01b',
            'prop_laptop_01a', 'prop_laptop_lester', 'prop_till_01', 'prop_till_02', 'prop_till_03',
            'prop_cash_register_01', 'v_res_monitor', 'v_ret_gc_cashreg', 'v_ret_ta_till',
        },
    },

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
            coords  = vector3(-1187.5038, -1187.8784, 7.7681), -- Shop keeper / interaction point
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
                bag         = vector3(-1188.5146, -1188.2035, 8.6000),
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
    findBags      = 'Find my bags',  -- Waypoint to a bag you set down (also /mybags)
    handoff       = 'Hand to someone', -- Give the bag to the nearest player (also /handbag)
    handoffTarget = 'Hand over bag',   -- Third-eye option on another player
}

-- Default keys. Players can still rebind them in Settings > Key Bindings > FiveM.
-- '' = unbound. These only apply the first time a player joins.
Config.Keybinds = {
    open  = '',   -- e.g. 'B'  open the bag you're wearing
    menu  = '',   -- e.g. 'K'  bag menu (open, set down, take off, pose, find)
    place = '',   -- set it down
}

-- One tip the first time someone wears a bag, then never again
Config.FirstBagHint = true

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
        handoff  = true,  -- Bag handed to another player
        lock     = true,  -- Padlocks put on, picked, cut
        search   = true,  -- Police searches
        drop     = true,  -- Death drops
        place    = true,  -- Bag set down, with coords
        pickup   = true,  -- Placed bag picked up
        access   = false, -- Private/public toggles
        admin    = true,  -- Studio saves / storage edits
        contents = true,  -- Snapshot what was inside on rob, drop and hand-off
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

--  ██████╗ ██╗   ██╗████████╗███████╗██╗████████╗
-- ██╔═══██╗██║   ██║╚══██╔══╝██╔════╝██║╚══██╔══╝
-- ██║   ██║██║   ██║   ██║   █████╗  ██║   ██║
-- ██║   ██║██║   ██║   ██║   ██╔══╝  ██║   ██║
-- ╚██████╔╝╚██████╔╝   ██║   ██║     ██║   ██║
--  ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝   ╚═╝

-- The outfit bag: a portable wardrobe. Use the item, it's set down in front
-- of you and opens. Save what you're wearing, wear a whole outfit or a single
-- piece, hover to preview, pin favourites, tag, share outfits with a code,
-- undo a change, import from illenium-appearance.
--
-- ox_inventory item (client export, NOT server):
--   ['outfit_bag'] = { label = 'Outfit Bag', weight = 500, stack = false, close = true,
--       client = { export = 'nayzeee-backpack.useOutfitBag' } },
Config.OutfitBag = {
    enabled = true,
    item    = 'outfit_bag',
    prop    = 'reh_prop_reh_bag_outfit_01a', -- Ground prop (any model works, e.g. 'prop_cs_heist_bag_02')

    maxOutfits       = 12,   -- Per bag. Keep <= 20 (they ride on a statebag while it's set down)
    maxLabelLength   = 30,
    interactDistance = 2.0,  -- Third-eye distance
    closeDistance    = 5.0,  -- The menu closes past this distance from the bag
    returnDistance   = 12.0, -- Walk further than this and the bag comes back to your pockets
    setDownDistance  = 0.75, -- How far in front of you it's set down
    openOnPlace      = true, -- Open the menu as soon as it's set down

    saveHair     = true,     -- Outfits include hair style + colour
    previewPed   = true,     -- Hover an outfit to see yourself in it
    previewSlot  = 2,        -- Pause-menu ped slot for the preview (try 1 or 3 if it overlaps)
    saveSkin     = false,    -- Persist the outfit through relogs (illenium / fivem-appearance / qb-clothing)
    sharing      = true,     -- Outfit share codes (copy a code, paste it into another bag)

    -- Colour tags players can put on outfits
    tags = {
        { key = 'casual', label = 'Casual', color = '#08afa2' },
        { key = 'work',   label = 'Work',   color = '#3b82f6' },
        { key = 'formal', label = 'Formal', color = '#a855f7' },
        { key = 'night',  label = 'Night',  color = '#ec4899' },
        { key = 'sport',  label = 'Sport',  color = '#f5a524' },
    },

    -- Someone else's bag. The owner can also lock / unlock their bag from the menu.
    access = {
        othersCanWear = true,  -- Unlocked bags can be opened by anyone nearby
        othersCanSave = false, -- Non-owners can change outfits in it
        othersCanCopy = true,  -- Non-owners can copy outfits into their own bag
        defaultLocked = true,  -- New bags start locked
    },

    -- Import saved outfits from illenium-appearance (needs oxmysql)
    wardrobe = { enabled = true, table = 'player_outfits' },

    placeAnim  = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 0, duration = 2200 },
    pickupAnim = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_b', flag = 0, duration = 2200 },

    -- What gets saved with an outfit
    components = {
        ['mask'] = 1, ['arms'] = 3, ['pants'] = 4, ['bag'] = 5, ['shoes'] = 6,
        ['neck'] = 7, ['t-shirt'] = 8, ['vest'] = 9, ['badge'] = 10, ['torso2'] = 11,
    },
    props = {
        ['hat'] = 0, ['glasses'] = 1, ['ear'] = 2, ['watch'] = 6, ['bracelet'] = 7,
    },

    wearAnims = {
        ['all']      = { dict = 'mp_safehouseshower@male@', clip = 'male_shower_towel_dry_to_get_dressed', flag = 0, duration = 3000 },
        ['hair']     = { dict = 'mp_masks@standard_car@ds@', clip = 'put_on_mask', flag = 51, duration = 800 },
        ['mask']     = { dict = 'mp_masks@standard_car@ds@', clip = 'put_on_mask', flag = 51, duration = 800 },
        ['arms']     = { dict = 'nmt_3_rcm-10', clip = 'cs_nigel_dual-10', flag = 51, duration = 1200 },
        ['pants']    = { dict = 're@construction', clip = 'out_of_breath', flag = 51, duration = 1300 },
        ['bag']      = { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'intro', flag = 51, duration = 1600 },
        ['shoes']    = { dict = 'random@domestic', clip = 'pickup_low', flag = 0, duration = 1200 },
        ['neck']     = { dict = 'clothingtie', clip = 'try_tie_positive_a', flag = 51, duration = 2100 },
        ['t-shirt']  = { dict = 'clothingtie', clip = 'try_tie_negative_a', flag = 51, duration = 1500 },
        ['vest']     = { dict = 'clothingtie', clip = 'try_tie_negative_a', flag = 51, duration = 1200 },
        ['badge']    = { dict = 'clothingtie', clip = 'try_tie_negative_a', flag = 51, duration = 1200 },
        ['torso2']   = { dict = 'clothingtie', clip = 'try_tie_negative_a', flag = 51, duration = 1500 },
        ['hat']      = { dict = 'mp_masks@standard_car@ds@', clip = 'put_on_mask', flag = 51, duration = 600 },
        ['glasses']  = { dict = 'clothingspecs', clip = 'put_on', flag = 51, duration = 2000 },
        ['ear']      = { dict = 'mp_cp_stolen_tut', clip = 'b_think', flag = 51, duration = 900 },
        ['watch']    = { dict = 'nmt_3_rcm-10', clip = 'cs_nigel_dual-10', flag = 51, duration = 1200 },
        ['bracelet'] = { dict = 'nmt_3_rcm-10', clip = 'cs_nigel_dual-10', flag = 51, duration = 1200 },
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

    -- Carried in hand. Set down to open: the bag unzips, and shows the cash
    -- inside when it holds any. Taking cash out plays the grab-cash animation.
    -- Open models by BzZz (bzzz.tebex.io), renamed so they never clash with bzzz_money.
    ['duffel_bag'] = {
        label    = 'Duffel Bag',
        model    = 'hei_p_m_bag_var22_arm_s',
        category = 'duffel',
        theme    = 'realistic',
        price    = 4500,
        slots    = 20,
        weight   = 40000,
        carry    = 'duffel',
        open = {
            style     = 'stand',
            model     = 'nayzeee_duffel_a',
            cashModel = 'nayzeee_duffel_b',
            heading   = 0.0,                -- open model faces the player as-is
            -- swapAt: ms into the grab when the hand is in the bag; taking the
            -- last of the cash swaps to the empty model right then
            grabAnim  = { dict = 'nayzeee_grab_cash_01', clip = 'nayzeee_grab_cash_01', time = 4200, swapAt = 1400 },
        },
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

    -- outfit bag
    first_hint       = 'New bag! Use it from your inventory (or /bagmenu) to open it, set it down or take it off.',
    waypoint_set     = 'Waypoint set to your bag.',
    no_placed        = "You haven't set any bags down.",

    ho_nobody        = 'Nobody close enough to hand it to.',
    ho_offered       = 'You hold out your %s.',
    ho_declined      = "They didn't want it.",
    ho_expired       = "They didn't take it.",
    ho_has_bag       = 'They already have a bag.',
    ho_cant_carry    = "They can't carry that.",
    ho_cant_use      = "They can't use that bag.",
    ho_job           = 'Job bags stay with you.',
    ho_close_first   = 'Close your bag first.',
    ho_busy          = 'Not right now.',
    ho_moved         = 'You moved too far apart.',
    ho_given         = 'You handed over your %s.',
    ho_received      = 'You took the %s.',
    ho_ask_title     = 'Bag offered',
    ho_ask_text      = 'Someone is handing you a **%s**.',
    ho_take          = 'Take it',
    ho_refuse        = 'No thanks',

    lk_title         = 'Padlocked',
    lk_code          = 'Enter the code',
    lk_pick          = 'Pick the lock',
    lk_cut           = 'Cut it off',
    lk_set_title     = 'Padlock your %s',
    lk_set_label     = 'Choose a %d digit code',
    lk_locked        = 'Padlocked. Only you, and anyone you tell the code, can open it.',
    lk_already       = 'This bag already has a padlock.',
    lk_no_padlock    = "You don't have a padlock.",
    lk_bad_code      = 'The code has to be %d digits.',
    lk_wrong         = 'Wrong code. %d tries left.',
    lk_wrong_plain   = 'Wrong code.',
    lk_lockout       = 'Too many wrong codes. Try again in %ds.',
    lk_no_pick       = 'You need a lockpick.',
    lk_no_cutter     = 'You need bolt cutters.',
    lk_picked        = 'The padlock pops open.',
    lk_pick_failed   = "The lock didn't give.",
    lk_pick_broke    = 'Your lockpick snapped.',
    lk_cut           = 'You cut the padlock off.',
    lk_cutting       = 'Cutting the padlock...',
    lk_removed       = 'Padlock removed.',
    lk_changed       = 'Code changed.',
    lk_menu_lock     = 'Padlock it',
    lk_menu_change   = 'Change padlock code',
    lk_menu_remove   = 'Take the padlock off',

    ob_title         = 'Outfit Bag',
    ob_placing       = 'Setting the outfit bag down...',
    ob_taking        = 'Picking up the outfit bag...',
    ob_pickup        = 'Pick up bag',
    ob_open          = 'Open outfit bag',
    ob_saved         = "Outfit '%s' saved.",
    ob_updated       = "Outfit '%s' updated with your current clothes.",
    ob_renamed       = 'Outfit renamed.',
    ob_deleted       = 'Outfit deleted.',
    ob_changed       = 'You changed your outfit.',
    ob_undone        = 'Back to what you had on.',
    ob_full          = 'This bag is full (%s/%s outfits).',
    ob_not_found     = 'Outfit bag not found.',
    ob_no_permission = "You can't do that with someone else's bag.",
    ob_invalid_name  = 'Invalid outfit name.',
    ob_cooldown      = 'Slow down.',
    ob_too_far       = 'You walked off - your outfit bag is back in your pockets.',
    ob_cannot_place  = "You can't set the bag down right now.",
    ob_copied        = "Outfit '%s' copied to your bag.",
    ob_your_full     = 'Your bag is full.',
    ob_need_own      = 'You need an outfit bag of your own to copy into.',
    ob_locked        = 'Bag locked - only you can open it.',
    ob_unlocked      = 'Bag unlocked - nearby players can open it.',
    ob_imported      = "Outfit '%s' imported.",
    ob_import_failed = 'Could not import that outfit.',
    ob_wrong_model   = 'That outfit was saved on a different character model.',
    ob_code_copied   = 'Share code copied to your clipboard.',
    ob_code_bad      = 'That share code is not valid.',
    ob_restored      = 'Your outfit bag was returned after a restart.',
}
