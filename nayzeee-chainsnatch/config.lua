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

    CHAIN SNATCH - 1.0.0
    Discord: discord.gg/nayzeeedev

]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Debug      = false        -- Prints extra info to the F8 / server console
Config.Framework  = 'auto'       -- 'auto' | 'esx' | 'qb' | 'qbx' | 'none'
Config.Inventory  = 'auto'       -- 'auto' | 'ox_inventory' | 'qb-inventory' | 'qs-inventory' | 'framework'
Config.Target     = 'auto'       -- 'auto' | 'ox_target' | 'qb-target' | 'none' (none = [E] prompts + commands)

-- Every chain is ONE inventory item. Which chain it is (and its texture) lives in the item's metadata,
-- so converting new chains never needs new items. See install/ox_inventory.lua.
Config.Item = 'nz_chain'

-- The resource chainkit writes the converted props into (it's created for you).
Config.PropsResource = 'nayzeee-chainprops'

Config.UI = {
    Scale    = 1.0,              -- Zoom for the whole NUI
    Toasts   = 'top-right',      -- 'top-right' | 'top-left' | 'top-center' | 'bottom-right'
}

-- Notifications go to the NUI toasts. Swap this for your own if you want.
Config.Notify = function(msg, kind, duration)
    SendNUIMessage({ action = 'toast', data = { message = msg, kind = kind or 'info', duration = duration or 4500 } })
end

--  ██████╗██╗  ██╗ █████╗ ██╗███╗   ██╗███████╗
-- ██╔════╝██║  ██║██╔══██╗██║████╗  ██║██╔════╝
-- ██║     ███████║███████║██║██╔██╗ ██║███████╗
-- ██║     ██╔══██║██╔══██║██║██║╚██╗██║╚════██║
-- ╚██████╗██║  ██║██║  ██║██║██║ ╚████║███████║
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝

-- Chains come from two places:
--   1. chainkit (the studio's Convert tab). Put downloaded chain clothing in this resource's chains/ folder
--      (one folder per chain, its name becomes the label) and press Build. Done, nothing to add here.
--   2. This table, for chain PROPS you already have. Only the model is required.
--
-- Fit them in the studio (/chainstudio). Saved fits go to data/overrides.json and win over these values.
Config.Chains = {
    -- ['my_gold_rope'] = {
    --     label    = 'Gold Rope Chain',
    --     variants = {                               -- one entry per model (texture)
    --         { prop = 'my_gold_rope_prop',   label = 'Gold' },
    --         { prop = 'my_silver_rope_prop', label = 'Silver' },
    --     },
    --     worn = { bone = 39317, pos = { x = 0.0, y = 0.0, z = 0.0 }, rot = { x = 0.0, y = 0.0, z = 0.0 } },
    --     hold = { bone = 57005, pos = { x = 0.12, y = 0.0, z = -0.1 }, rot = { x = 0.0, y = 0.0, z = 0.0 } },
    --     value = 2500,
    -- },
}

-- Where a chain goes before anyone fits it in the studio.
Config.DefaultFit = {
    worn = { bone = 39317, pos = { x = 0.03, y = 0.06, z = 0.0 }, rot = { x = 0.0, y = 90.0, z = 180.0 } },
    hold = { bone = 57005, pos = { x = 0.10, y = 0.02, z = -0.08 }, rot = { x = 0.0, y = 0.0, z = 0.0 } },
}

-- Rough value used in the item description and logs ('$2,500'). Studio can set it per chain.
Config.DefaultValue = 1500

-- ██╗    ██╗███████╗ █████╗ ██████╗ ██╗███╗   ██╗ ██████╗
-- ██║    ██║██╔════╝██╔══██╗██╔══██╗██║████╗  ██║██╔════╝
-- ██║ █╗ ██║█████╗  ███████║██████╔╝██║██╔██╗ ██║██║  ███╗
-- ██║███╗██║██╔══╝  ██╔══██║██╔══██╗██║██║╚██╗██║██║   ██║
-- ╚███╔███╔╝███████╗██║  ██║██║  ██║██║██║ ╚████║╚██████╔╝
--  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Wear = {
    Command      = 'chain',        -- Opens the chain menu (take off, hold up, throw, set down ...)
    Keybind      = 'K',            -- Rebindable in Settings > Key Bindings > FiveM. false = command only
    RenderDistance = 120.0,        -- Other players' chains are only drawn within this range
    Anim         = { dict = 'clothingtie', clip = 'try_tie_positive_a', duration = 1600 },  -- putting on / taking off
    KeepOnRelog  = true,           -- A worn chain stays on through relogs and restarts
}

-- ██╗  ██╗ ██████╗ ██╗     ██████╗ ██╗███╗   ██╗ ██████╗
-- ██║  ██║██╔═══██╗██║     ██╔══██╗██║████╗  ██║██╔════╝
-- ███████║██║   ██║██║     ██║  ██║██║██╔██╗ ██║██║  ███╗
-- ██╔══██║██║   ██║██║     ██║  ██║██║██║╚██╗██║██║   ██║
-- ██║  ██║╚██████╔╝███████╗██████╔╝██║██║ ╚████║╚██████╔╝
-- ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Hold your chain up for everyone to see. While holding: [G] throw it, [E] set it down, [BACKSPACE] put it back on.
Config.Hold = {
    Command = 'chainhold',         -- Toggle holding your chain up. false to disable the command
    Keybind = false,               -- e.g. 'J'
    -- The pose while holding. The studio's Hold tab previews them; pick the one that suits your fits.
    Anim    = 'show',
    Anims   = {
        show   = { label = 'Show off',    dict = 'anim@heists@humane_labs@finale@keycards', clip = 'ped_a_enter_loop', flag = 49 },
        dangle = { label = 'Dangle',      dict = 'amb@world_human_tourist_map@male@base',   clip = 'base',             flag = 49 },
        peace  = { label = 'Peace',       dict = 'mp_player_int_upperpeace_sign',           clip = 'mp_player_int_peace_sign', flag = 49 },
    },
}

-- ████████╗██╗  ██╗██████╗  ██████╗ ██╗    ██╗██╗███╗   ██╗ ██████╗
-- ╚══██╔══╝██║  ██║██╔══██╗██╔═══██╗██║    ██║██║████╗  ██║██╔════╝
--    ██║   ███████║██████╔╝██║   ██║██║ █╗ ██║██║██╔██╗ ██║██║  ███╗
--    ██║   ██╔══██║██╔══██╗██║   ██║██║███╗██║██║██║╚██╗██║██║   ██║
--    ██║   ██║  ██║██║  ██║╚██████╔╝╚███╔███╔╝██║██║ ╚████║╚██████╔╝
--    ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝  ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Throw = {
    Enabled     = true,
    Speed       = 11.0,            -- m/s out of the hand
    Lift        = 2.2,             -- extra upward speed, gives the arc
    MaxDistance = 30.0,            -- server refuses throws that land further than this
    Anim        = { dict = 'weapons@projectile@', clip = 'throw_m_fb_stand', release = 380 },  -- release = ms into the anim
    Catch       = true,            -- a player standing where it lands catches it
    CatchRadius = 1.6,
}

-- ██████╗ ██╗      █████╗  ██████╗██╗███╗   ██╗ ██████╗
-- ██╔══██╗██║     ██╔══██╗██╔════╝██║████╗  ██║██╔════╝
-- ██████╔╝██║     ███████║██║     ██║██╔██╗ ██║██║  ███╗
-- ██╔═══╝ ██║     ██╔══██║██║     ██║██║╚██╗██║██║   ██║
-- ██║     ███████╗██║  ██║╚██████╗██║██║ ╚████║╚██████╔╝
-- ╚═╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Set a chain down anywhere you look: a table, the bar, the floor.
-- [E] place  [SCROLL] turn (hold SHIFT for fine)  [ARROW UP/DOWN] tilt  [BACKSPACE] cancel
Config.Place = {
    Enabled     = true,
    MaxDistance = 3.5,             -- reach from the player
    MaxSlope    = 0.55,            -- surface normal z; lower lets you place on steeper surfaces (walls are refused)
    RotateStep  = 10.0,
    TiltStep    = 10.0,
}

-- ██████╗ ██████╗  ██████╗ ██████╗ ███████╗
-- ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔════╝
-- ██║  ██║██████╔╝██║   ██║██████╔╝███████╗
-- ██║  ██║██╔══██╗██║   ██║██╔═══╝ ╚════██║
-- ██████╔╝██║  ██║╚██████╔╝██║     ███████║
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝

-- Chains on the ground (thrown, set down, or dropped in a snatch). Anyone can pick them up.
Config.Drops = {
    Persist        = true,         -- survive restarts (data/drops.json)
    ExpireMinutes  = 0,            -- 0 = never. After this long a chain on the ground is gone for good
    RenderDistance = 60.0,
    PickupDistance = 2.0,
    PickupAnim     = { dict = 'random@domestic', clip = 'pickup_low', duration = 1100 },
    OwnerOnly      = false,        -- true = only the person who put it down can pick it up (thrown chains are always free)
}

-- ███████╗███╗   ██╗ █████╗ ████████╗ ██████╗██╗  ██╗██╗███╗   ██╗ ██████╗
-- ██╔════╝████╗  ██║██╔══██╗╚══██╔══╝██╔════╝██║  ██║██║████╗  ██║██╔════╝
-- ███████╗██╔██╗ ██║███████║   ██║   ██║     ███████║██║██╔██╗ ██║██║  ███╗
-- ╚════██║██║╚██╗██║██╔══██║   ██║   ██║     ██╔══██║██║██║╚██╗██║██║   ██║
-- ███████║██║ ╚████║██║  ██║   ██║   ╚██████╗██║  ██║██║██║ ╚████║╚██████╔╝
-- ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.Snatch = {
    Enabled      = true,
    Distance     = 1.8,            -- metres
    Cooldown     = 60,             -- seconds between attempts (win or lose)
    Command      = 'snatch',       -- snatch the closest player in front of you. false = target / keybind only
    Keybind      = false,          -- e.g. 'H'
    TargetLabel  = 'Snatch Chain',
    AllowInVehicle = false,
    Clothing     = true,           -- chains worn as CLOTHING (from a clothing store) can be snatched too, if chainkit
                                   -- converted that clothing (it has to be in a server resource, not the chains/ folder)
    ClothingNone = 0,              -- what's left in the accessory slot after a clothing chain is ripped off
    SnapChance   = 0.15,           -- chance the chain snaps and lands on the ground instead of in the snatcher's hand
    FailRagdoll  = 1200,           -- ms the snatcher hits the floor after losing the tug of war. 0 = off
    ProtectedJobs = { 'police', 'ambulance' },  -- on duty, these can't be snatched
    Anim         = { dict = 'melee@unarmed@streamed_variations', clip = 'plyr_takedown_front_slap', duration = 900 },
    Reaction     = { dict = 'anim@mp_player_intcelebrationfemale@face_palm', clip = 'face_palm', duration = 2400 },
    Dispatch     = 0.35,           -- chance police get an alert (see Config.Dispatch). 0 = never
}

-- ████████╗██╗   ██╗ ██████╗      ██████╗ ███████╗    ██╗    ██╗ █████╗ ██████╗
-- ╚══██╔══╝██║   ██║██╔════╝     ██╔═══██╗██╔════╝    ██║    ██║██╔══██╗██╔══██╗
--    ██║   ██║   ██║██║  ███╗    ██║   ██║█████╗      ██║ █╗ ██║███████║██████╔╝
--    ██║   ██║   ██║██║   ██║    ██║   ██║██╔══╝      ██║███╗██║██╔══██║██╔══██╗
--    ██║   ╚██████╔╝╚██████╔╝    ╚██████╔╝██║         ╚███╔███╔╝██║  ██║██║  ██║
--    ╚═╝    ╚═════╝  ╚═════╝      ╚═════╝ ╚═╝          ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝

-- A snatch is a fight: both players mash the same key, the server moves the rope.
-- Restrained, hands up and downed players can't fight back, the chain just comes off.
Config.Tug = {
    Enabled    = true,
    Duration   = 5000,             -- ms
    Key        = 22,               -- control id (22 = SPACE). Shown on screen as Config.Tug.KeyLabel
    KeyLabel   = 'SPACE',
    Push       = { snatcher = 7.0, victim = 7.5 },   -- rope per press
    MinHitInterval = 85,           -- ms. Server-side rate limit, macros do nothing
    WinAt      = 100,
    Blindside  = { Enabled = true, Angle = 70, Start = 25 },  -- grab from behind = head start
    TieGoesTo  = 'victim',
}

-- Statebag keys checked on the victim (covers most police / ambulance scripts)
Config.RestrainedStates = { 'isCuffed', 'cuffed', 'handcuffed', 'isHandcuffed', 'ziptied', 'isTied' }
Config.DownedStates     = { 'isDead', 'dead', 'down', 'isDown', 'inLastStand', 'laststand' }
Config.HandsUpAnim      = { dict = 'random@mugging3', clip = 'handsup_standing_base' }

-- ███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗
-- ██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗
-- ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║
-- ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║
-- ███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝
-- ╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝

-- /chainstudio  - fit chains on the neck and in the hand, name them, take their icons, convert new ones.
-- Who can open it: anyone with the ace below, or an admin in your framework.
--   add_ace group.admin nayzeee.chains allow
Config.Studio = {
    Command = 'chainstudio',
    Ace     = 'nayzeee.chains',
}

Config.Icons = {
    Size            = 512,
    Padding         = 0.08,
    Chroma          = 'green',     -- 'green' | 'magenta' | 'blue'  (pick one the chain doesn't use)
    Coords          = vector3(0.0, 0.0, -150.0),  -- under the map, nothing else renders there
    Fov             = 30.0,
    TextureWait     = 700,         -- ms to let textures stream in before a shot
    SaveToInventory = true,        -- also write into ox_inventory/web/images (see INSTALL)
    Lights = {
        { offset = vector3(-1.2, -1.6, 1.6), intensity = 3.0, range = 6.0 },
        { offset = vector3(1.4, -1.2, 0.8),  intensity = 1.6, range = 6.0 },
        { offset = vector3(0.0, 1.5, 1.2),   intensity = 1.2, range = 5.0 },
    },
}

--  ██████╗ ██████╗ ███╗   ██╗██╗   ██╗███████╗██████╗ ████████╗███████╗██████╗
-- ██╔════╝██╔═══██╗████╗  ██║██║   ██║██╔════╝██╔══██╗╚══██╔══╝██╔════╝██╔══██╗
-- ██║     ██║   ██║██╔██╗ ██║██║   ██║█████╗  ██████╔╝   ██║   █████╗  ██████╔╝
-- ██║     ██║   ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██╔══██╗   ██║   ██╔══╝  ██╔══██╗
-- ╚██████╗╚██████╔╝██║ ╚████║ ╚████╔╝ ███████╗██║  ██║   ██║   ███████╗██║  ██║
--  ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

-- chainkit turns chain CLOTHING into PROPS. It runs on the server (tools/chainkit), you never call it yourself.
Config.Convert = {
    Enabled      = true,
    DropFolder   = 'chains',       -- inside this resource: chains/<Chain Name>/teef_000_u.ydd + teef_diff_000_a_*.ytd ...
    -- Also convert chains that your server streams as CLOTHING (mp_m_freemode_01_pack^teef_###_u.ydd).
    -- The accessory slot (teef) also holds ties and scarves, so list the clothing resources that are chains:
    --   ScanResources = { 'my_chain_pack' }       or     ScanResources = 'all'
    ScanResources = {},
    AutoScan     = true,           -- check what's new on start (shows in the studio)
    AutoBuild    = true,           -- and build it right away
    TextureSize  = 1024,           -- max texture size of the props
    IconSize     = 256,            -- chainkit draws an icon for every chain (the studio can take nicer ones). 0 = off
    LodDistance  = 60,
    Kit = {
        linux   = 'tools/chainkit/linux-x64/chainkit',
        windows = 'tools/chainkit/win-x64/chainkit.exe',
    },
}

-- ████████╗███████╗██╗  ██╗████████╗
-- ╚══██╔══╝██╔════╝╚██╗██╔╝╚══██╔══╝
--    ██║   █████╗   ╚███╔╝    ██║
--    ██║   ██╔══╝   ██╔██╗    ██║
--    ██║   ███████╗██╔╝ ██╗   ██║
--    ╚═╝   ╚══════╝╚═╝  ╚═╝   ╚═╝

Config.Text = {
    menu_title      = 'Chain',
    no_chain        = 'You\'re not wearing a chain.',
    put_on          = 'Put on',
    take_off        = 'Take off',
    hold_up         = 'Hold up',
    stop_holding    = 'Put it back on',
    throw           = 'Throw',
    set_down        = 'Set down',
    in_pockets      = 'In your pockets',
    pick_up         = 'Pick up',
    pick_up_wear    = 'Pick up & wear',
    wearing         = 'You put on your %s.',
    took_off        = 'You took off your %s.',
    no_room         = 'No room in your pockets.',
    already_wearing = 'Take your chain off first.',
    too_far         = 'Too far away.',
    bad_spot        = 'You can\'t put it there.',
    cooldown        = 'Wait %ss before trying again.',
    no_target       = 'No one close enough.',
    nothing_to_take = 'They aren\'t wearing a chain.',
    protected       = 'You can\'t snatch from them.',
    snatched        = 'You snatched a %s!',
    got_snatched    = '%s snatched your %s!',
    held_on         = 'You held on to your chain.',
    lost_tug        = 'They held on to it.',
    snapped         = 'The chain snapped and hit the floor!',
    caught          = 'You caught a %s!',
    thrown          = 'You threw your %s.',
    no_admin        = 'You can\'t use the chain studio.',
    busy            = 'You\'re busy.',
    hint_hold       = '<kc>G</kc> Throw  <kc>E</kc> Set down  <kc>BACKSPACE</kc> Put it back on',
    hint_place      = '<kc>E</kc> Place  <kc>SCROLL</kc> Turn  <kc>↑ ↓</kc> Tilt  <kc>BACKSPACE</kc> Cancel',
    hint_pickup     = '<kc>E</kc> Pick up %s',
    tug_you         = 'Snatching',
    tug_them        = 'Holding on',
}

-- Police alert when a snatch happens (runs on the VICTIM's client, Config.Snatch.Dispatch = chance). Examples below.
Config.Dispatch = function(coords, snatcherSrc)
    -- ps-dispatch:
    -- exports['ps-dispatch']:CustomAlert({ coords = coords, message = 'Chain Snatching', dispatchCode = '10-31',
    --     description = 'Someone had their chain snatched', radius = 0, sprite = 156, color = 1, scale = 1.0, length = 3 })
    -- cd_dispatch / qs-dispatch / core_dispatch: send your own alert here.
end

-- Return true to block snatching at a spot (client side, for UX). Safezones, hospitals, your own zones ...
Config.IsInNoSnatchZone = function(coords)
    return false
end

-- A clothing chain was ripped off this player (runs on the VICTIM's client). Save their outfit here so it
-- doesn't come back on relog. Examples:
Config.OnClothingChainRemoved = function(ped)
    -- illenium-appearance:
    -- if GetResourceState('illenium-appearance') == 'started' then
    --     TriggerServerEvent('illenium-appearance:server:saveAppearance', exports['illenium-appearance']:getPedAppearance(ped))
    -- end
end
