--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

██████╗  ██████╗ ██████╗ ██╗   ██╗██████╗  █████╗  ██████╗
██╔══██╗██╔═══██╗██╔══██╗╚██╗ ██╔╝██╔══██╗██╔══██╗██╔════╝
██████╔╝██║   ██║██║  ██║ ╚████╔╝ ██████╔╝███████║██║  ███╗
██╔══██╗██║   ██║██║  ██║  ╚██╔╝  ██╔══██╗██╔══██║██║   ██║
██████╔╝╚██████╔╝██████╔╝   ██║   ██████╔╝██║  ██║╚██████╔╝
╚═════╝  ╚═════╝ ╚═════╝    ╚═╝   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝


    BODY BAG SCRIPT - 1.2.0
    Discord: discord.gg/nayzeeedev

    HOW TO READ THIS FILE
    - Every section has a big banner. Each setting has a comment saying what it does.
    - Times are in MILLISECONDS (1000 = 1 second) unless the comment says otherwise.
    - Chances are PERCENT (0 - 100).
    - Anything under HOOKS (bottom of the file) is where you plug in YOUR other scripts.

]]

Config = {}

--  ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ██╗
-- ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗██║
-- ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║██║
-- ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║██║
-- ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║███████╗
--  ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

Config.Debug = false            -- Extra prints in the server/client console

-- Must the body be DEAD before it can be bagged / loaded / chopped?
-- "Dead" = ped is dead OR your ambulance script marks them dead (wasabi 'dead', ESX 'isDead', esx:onPlayerDeath)
Config.OnlyDeadBodies = true

-- The SERVER double-checks every action (distance, death, items) so a modded client
-- can't bag / CK people from across the map. Only turn this off if your ambulance
-- script isn't detected and bagging always says "They're still breathing".
Config.ServerDeathCheck = true

-- Let players bag / load dead LOCALS (NPC peds). NPC bodies never trigger a CK.
Config.AllowNPCBodies = true

-- A bagged victim who gets revived (admin /revive, medic, bleed-out respawn) climbs
-- out of the bag instead of staying stuck inside it.
Config.ReleaseOnRevive = true

-- ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗
-- ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝
-- ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝
-- ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝
-- ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║
-- ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝

-- Max distance (meters) the SERVER allows between a player and what they're interacting with.
-- Slightly bigger than the target distance to allow for lag.
Config.MaxInteractDistance = 6.0

-- ██╗   ██╗██╗    ███████╗████████╗██╗   ██╗██╗     ███████╗
-- ██║   ██║██║    ██╔════╝╚══██╔══╝╚██╗ ██╔╝██║     ██╔════╝
-- ██║   ██║██║    ███████╗   ██║    ╚████╔╝ ██║     █████╗
-- ██║   ██║██║    ╚════██║   ██║     ╚██╔╝  ██║     ██╔══╝
-- ╚██████╔╝██║    ███████║   ██║      ██║   ███████╗███████╗
--  ╚═════╝ ╚═╝    ╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚══════╝

-- One place for the NAYZEEE look. Every notify, text hint and obituary uses this.
Config.UI = {
    Title      = 'NAYZEEE',
    Position   = 'top',
    Background = '#0f1419',
    Text       = '#ffffff',
    Accent     = '#08afa2',
    Radius     = 6,
}

-- ██╗████████╗███████╗███╗   ███╗███████╗
-- ██║╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ██║   ██║   █████╗  ██╔████╔██║███████╗
-- ██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ██║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

-- Item names as they exist in your inventory (ox_inventory)
-- Images are in the images/ folder - copy to ox_inventory/web/images/
Config.Items = {
    bodybag      = 'bodybag',        -- Zip a dead body inside
    bodyCrate    = 'body_crate',     -- Military crate - deployable, sinks in water
    coffin       = 'coffin',         -- Deployable coffin for proper burials
    shovel       = 'shovel',         -- Required to dig graves / exhume
    powersaw     = 'powersaw',       -- Fast dismemberment tool
    woodsaw      = 'woodsaw',        -- Slow/budget dismemberment tool
    gasmask      = 'gasmask',        -- Protects from acid fumes
    acid         = 'acid',           -- Hydrochloric acid - total dissolve
    matches      = 'matches',        -- Needed to light the burn barrel
    burnBarrel   = 'burn_barrel',    -- Deployable cremation barrel
    -- Yield items (given to the killer)
    severedHead  = 'severed_head',
    severedHands = 'severed_hands',
    severedFeet  = 'severed_feet',
    skull        = 'skull',          -- Cremation trophy (chance-based)
    ashes        = 'ashes',          -- Cremation leftover
}

-- ██████╗ ██████╗  ██████╗ ██████╗ ███████╗
-- ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔════╝
-- ██████╔╝██████╔╝██║   ██║██████╔╝███████╗
-- ██╔═══╝ ██╔══██╗██║   ██║██╔═══╝ ╚════██║
-- ██║     ██║  ██║╚██████╔╝██║     ███████║
-- ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚══════╝

-- ALL prop names verified against the GTA V object list - swap freely
-- To use custom streamed props: add the stream folder + change the name here
Config.Props = {
    bodybag      = `xm_prop_body_bag`,      -- Black LosSantos Coroner Bag (custom model streamed from stream/)
    crate        = `prop_mil_crate_01`,     -- Military crate
    coffin       = `prop_coffin_02b`,       -- Coffin
    barrel       = `prop_barrel_02a`,       -- Burn barrel
    shallowGrave = `prop_ld_shovel_dirt`,   -- Shallow grave marker (dirt pile w/ shovel sticking out)
    tombstone    = `prop_gravestones_09a`,  -- Cemetery/coffin burial marker (01a-10a all exist, pick your style)
    -- Held tool props (spawned LOCALLY so anti-cheat never touches them)
    shovelProp   = `prop_tool_shovel`,
    powersawProp = `prop_tool_consaw`,      -- Concrete saw
    woodsawProp  = `prop_bonesaw`,          -- Actual bone saw prop
    acidProp     = `prop_jerrycan_01a`,     -- Jug used while pouring acid
}

-- ██████╗  █████╗  ██████╗  ██████╗ ██╗███╗   ██╗ ██████╗
-- ██╔══██╗██╔══██╗██╔════╝ ██╔════╝ ██║████╗  ██║██╔════╝
-- ██████╔╝███████║██║  ███╗██║  ███╗██║██╔██╗ ██║██║  ███╗
-- ██╔══██╗██╔══██║██║   ██║██║   ██║██║██║╚██╗██║██║   ██║
-- ██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║██║ ╚████║╚██████╔╝
-- ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝

Config.BagTime  = 8000 -- Time in ms to zip a body into a bag
Config.LoadTime = 6000 -- Time in ms to load a bag/body into crate/coffin/barrel

-- Put a body STRAIGHT into a placed crate/coffin - no body bag needed
Config.DirectLoad = {
    Enabled = true,  -- Allow loading a dead body directly into a nearby empty crate/coffin
    Radius  = 3.0,   -- Empty container must be within this many meters of the body
}

-- Taking a body back OUT of a bag/crate/coffin/barrel
Config.RemoveBody = {
    Enabled         = true,  -- Show the "Remove Body" option on containers
    Time            = 5000,  -- ms
    RefundContainer = true,  -- Give the crate/coffin item back when the body is removed
    RefundBag       = false, -- Give the body bag item back (false = bag is single-use once zipped)
}

--  ██████╗ █████╗ ██████╗ ██████╗ ██╗   ██╗██╗███╗   ██╗ ██████╗
-- ██╔════╝██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝██║████╗  ██║██╔════╝
-- ██║     ███████║██████╔╝██████╔╝ ╚████╔╝ ██║██╔██╗ ██║██║  ███╗
-- ██║     ██╔══██║██╔══██╗██╔══██╗  ╚██╔╝  ██║██║╚██╗██║██║   ██║
-- ╚██████╗██║  ██║██║  ██║██║  ██║   ██║   ██║██║ ╚████║╚██████╔╝
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝

-- Drop key is a REAL keybind (players can rebind: ESC > Settings > Key Bindings > FiveM)
Config.DropKey = 'G'

Config.Carry = {
    DropOnDeath   = true, -- You drop what you're carrying if you go down
    DropOnRagdoll = true, -- ...or get knocked over / tackled
}

-- Carry animations + attach offsets per container type
-- TWEAK the offsets/rot in-game until it sits right on your ped
Config.CarryAnims = {
    bodybag = {
        Dict = 'missfinale_c2mcs_1', Clip = 'fin_c2_mcs_1_camman',
        Bone = 0,     Offset = vec3(0.27, 0.15, 0.63), Rot = vec3(0.0, 270.0, 0.0),
    },
    crate = {
        Dict = 'anim@heists@box_carry@', Clip = 'idle',
        Bone = 60309, Offset = vec3(0.05, 0.10, -0.30), Rot = vec3(0.0, 0.0, 0.0),
    },
    coffin = { -- carried flat across both arms in front
        Dict = 'anim@heists@box_carry@', Clip = 'idle',
        Bone = 0,     Offset = vec3(0.0, 0.62, 0.35),  Rot = vec3(0.0, 0.0, 90.0),
    },
}

-- ████████╗██████╗ ██╗   ██╗███╗   ██╗██╗  ██╗
-- ╚══██╔══╝██╔══██╗██║   ██║████╗  ██║██║ ██╔╝
--    ██║   ██████╔╝██║   ██║██╔██╗ ██║█████╔╝
--    ██║   ██╔══██╗██║   ██║██║╚██╗██║██╔═██╗
--    ██║   ██║  ██║╚██████╔╝██║ ╚████║██║  ██╗
--    ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝

-- Throw a carried body into a vehicle trunk, drive off, take it out somewhere quiet.
-- The victim rides along with the car. If the car gets deleted/impounded the body is
-- released (the victim is freed, NOT CKed).
Config.Trunk = {
    Enabled         = true,
    Time            = 4000, -- ms to load / unload
    MaxBodies       = 2,    -- Bodies per vehicle
    AllowedKinds    = { bodybag = true, crate = false, coffin = false }, -- What fits in a trunk
    Bones           = { 'boot' }, -- Third-eye the back of the car (vehicles without a 'boot' bone won't show it)
    -- Vehicle classes that have no trunk (8 motorcycles, 13 cycles, 14 boats, 15 helis, 16 planes, 21 trains)
    BlockedClasses  = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    MustBeUnlocked  = true, -- Locked cars can't be loaded/unloaded
    PoliceCanSearch = true, -- Police get a "Search Trunk For Bodies" option
}

-- ██████╗ ██╗███████╗███╗   ███╗███████╗███╗   ███╗██████╗ ███████╗██████╗
-- ██╔══██╗██║██╔════╝████╗ ████║██╔════╝████╗ ████║██╔══██╗██╔════╝██╔══██╗
-- ██║  ██║██║███████╗██╔████╔██║█████╗  ██╔████╔██║██████╔╝█████╗  ██████╔╝
-- ██║  ██║██║╚════██║██║╚██╔╝██║██╔══╝  ██║╚██╔╝██║██╔══██╗██╔══╝  ██╔══██╗
-- ██████╔╝██║███████║██║ ╚═╝ ██║███████╗██║ ╚═╝ ██║██████╔╝███████╗██║  ██║
-- ╚═════╝ ╚═╝╚══════╝╚═╝     ╚═╝╚══════╝╚═╝     ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝

Config.Dismember = {
    Enabled = true,
    HeadlessJohnDoe = true, -- Once chopped, the body can never be identified

    -- Tools (item must be in inventory, prop shows in hand, anim plays)
    Powersaw = {
        Duration = 12000, -- ms
        Anim = { Dict = 'anim@heists@fleeca_bank@drilling', Clip = 'drill_straight_idle', Flag = 1 },
        PropOffset = { Bone = 28422, Offset = vec3(0.0, 0.0, 0.0), Rot = vec3(0.0, 0.0, 0.0) },
    },
    Woodsaw = {
        Duration = 30000, -- ms
        Anim = { Dict = 'anim@amb@business@coc@coc_unpack_cut@', Clip = 'fullcut_cycle_v1_cokecutter', Flag = 1 },
        PropOffset = { Bone = 28422, Offset = vec3(0.0, 0.0, 0.0), Rot = vec3(0.0, 0.0, 0.0) },
    },

    -- What a full chop yields
    Yields = {
        { item = 'severed_head',  count = 1 },
        { item = 'severed_hands', count = 1 },
        { item = 'severed_feet',  count = 1 },
    },

    -- Blood left at the chop site (everyone nearby sees it - police evidence)
    Blood = {
        Enabled   = true,
        DecalType = 1010,  -- Decal type ID (1010 = blood splat - change if your game build differs)
        Size      = 1.8,   -- Decal size in meters
        Duration  = 600.0, -- Seconds the blood stays on the ground (600 = 10 min)
    },
}

--  ██████╗██████╗ ███████╗███╗   ███╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
-- ██╔════╝██╔══██╗██╔════╝████╗ ████║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
-- ██║     ██████╔╝█████╗  ██╔████╔██║███████║   ██║   ██║██║   ██║██╔██╗ ██║
-- ██║     ██╔══██╗██╔══╝  ██║╚██╔╝██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
-- ╚██████╗██║  ██║███████╗██║ ╚═╝ ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
--  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

Config.Cremation = {
    BurnTime        = 45000, -- ms the fire burns before the body is gone
    RequiresMatches = true,  -- Need + consume matches to light it
    Yields = {
        { item = 'ashes', count = 1, chance = 100 }, -- chance = % roll
        { item = 'skull', count = 1, chance = 35 },  -- Trophy
    },
    -- % chance EACH DNA trace is destroyed. Survivors are written on the ashes/skull item
    -- description - hand them to the cops and they can tell who handled the body.
    EvidenceDestroyed = 90,
}

--  ██████╗  █████╗ ███████╗    ███╗   ███╗ █████╗ ███████╗██╗  ██╗
-- ██╔════╝ ██╔══██╗██╔════╝    ████╗ ████║██╔══██╗██╔════╝██║ ██╔╝
-- ██║  ███╗███████║███████╗    ██╔████╔██║███████║███████╗█████╔╝
-- ██║   ██║██╔══██║╚════██║    ██║╚██╔╝██║██╔══██║╚════██║██╔═██╗
-- ╚██████╔╝██║  ██║███████║    ██║ ╚═╝ ██║██║  ██║███████║██║  ██╗
--  ╚═════╝ ╚═╝  ╚═╝╚══════╝    ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

-- The gas mask is WORN, not just carried. Use the item to put it on,
-- use it again to take it off. Acid fumes only spare you while it's ON.
Config.Gasmask = {
    -- 'prop'      = attaches a real gas mask prop to your face (works on any server, no clothing pack needed)
    -- 'component' = swaps your ped's mask component (needs the drawable IDs below to match YOUR clothing pack)
    Method = 'prop',

    -- Put-on / take-off animation
    Anim = {
        Dict     = 'mp_masks@standard_car@ds@',
        Clip     = 'put_on_mask',
        Flag     = 48,
        Duration = 1500, -- ms
    },

    -- Used when Method = 'prop'
    Prop = {
        Model      = `p_gasmask_s`, -- Verified base-game gas mask prop
        Networked  = true,          -- true = other players see the mask on your face
                                    -- set false if your anti-cheat deletes it (then only you see it)
        Bone       = 12844,         -- SKEL_Head
        Offset     = vec3(0.0, 0.0, 0.0),
        Rot        = vec3(180.0, 90.0, 0.0),
    },

    -- Used when Method = 'component' (component slot 1 = mask)
    -- Find the right IDs with a clothing menu on YOUR server
    Component = {
        Male   = { Drawable = 52, Texture = 0 },
        Female = { Drawable = 52, Texture = 0 },
    },
}

--  █████╗  ██████╗██╗██████╗
-- ██╔══██╗██╔════╝██║██╔══██╗
-- ███████║██║     ██║██║  ██║
-- ██╔══██║██║     ██║██║  ██║
-- ██║  ██║╚██████╗██║██████╔╝
-- ╚═╝  ╚═╝ ╚═════╝╚═╝╚═════╝

Config.Acid = {
    DissolveTime      = 60000, -- ms to fully dissolve the body
    RequiresGasmask   = true,  -- Without a gas mask you take fume damage
    NoMaskDamage      = 25,    -- Damage per tick without a mask
    NoMaskDamageTick  = 5000,  -- ms between damage ticks
    EvidenceDestroyed = 100,   -- Acid leaves NOTHING behind
}

-- ██████╗ ██╗   ██╗██████╗ ██╗ █████╗ ██╗
-- ██╔══██╗██║   ██║██╔══██╗██║██╔══██╗██║
-- ██████╔╝██║   ██║██████╔╝██║███████║██║
-- ██╔══██╗██║   ██║██╔══██╗██║██╔══██║██║
-- ██████╔╝╚██████╔╝██║  ██║██║██║  ██║███████╗
-- ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚══════╝

Config.Burial = {
    DigTime         = 20000, -- ms to dig a grave
    ExhumeTime      = 25000, -- ms to dig a body back up
    PoliceCanExhume = true,  -- Police can exhume ANY grave (with a shovel). Otherwise only the digger can.
    -- % chance EACH DNA trace on the body is destroyed while it's in the ground.
    -- Shallow graves are risky - most DNA survives and police see it when they exhume.
    EvidenceDestroyed = 20,

    -- Shallow graves survive server restarts (saved in the database)
    PersistShallowGraves = true,
    GraveLifetimeDays    = 7,  -- Graves older than this are cleaned up on restart (0 = keep forever)

    -- Zones where digging is blocked (concrete plazas etc)
    BlockedZones = {
        -- { coords = vec3(240.0, -860.0, 30.0), radius = 100.0 }, -- Example: Legion Square
    },

    -- How many burials are allowed per server restart (0 = unlimited)
    BurialsPerRestart = {
        Cemetery = 1, -- The body hole only fits one... until next restart
        Shallow  = 0, -- Shallow graves anywhere - unlimited by default
    },

    -- The cemetery body hole - place a coffin/bag in it via third-eye, bury it,
    -- and the tombstone spawns at the head of the grave with name + date.
    -- Cemetery tombstones are memorials: they reset every restart (shallow graves don't).
    Cemetery = {
        Enabled     = true,
        Coords      = vec3(-1763.0739, -262.6960, 47.2116), -- The open body hole @ Pacific Bluffs
        HoleHeading = 330.1008, -- Heading the container snaps to inside the hole
        Radius      = 25.0,     -- Burials within this radius count as cemetery burials
        Tombstone   = {
            Coords  = vec3(-1761.8257, -260.6307, 48.2813), -- Where the tombstone spawns
            Heading = 155.5130,
        },
    },
}

-- ██╗    ██╗ █████╗ ████████╗███████╗██████╗
-- ██║    ██║██╔══██╗╚══██╔══╝██╔════╝██╔══██╗
-- ██║ █╗ ██║███████║   ██║   █████╗  ██████╔╝
-- ██║███╗██║██╔══██║   ██║   ██╔══╝  ██╔══██╗
-- ╚███╔███╔╝██║  ██║   ██║   ███████╗██║  ██║
--  ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
-- ██████╗ ██╗   ██╗███╗   ███╗██████╗
-- ██╔══██╗██║   ██║████╗ ████║██╔══██╗
-- ██║  ██║██║   ██║██╔████╔██║██████╔╝
-- ██║  ██║██║   ██║██║╚██╔╝██║██╔═══╝
-- ██████╔╝╚██████╔╝██║ ╚═╝ ██║██║
-- ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝

Config.WaterDump = {
    RequireCrate = false, -- true = raw bags can NOT be dumped (must be crated)
    ThrowForce   = 30.0,  -- Forward force of the throw (raise if it lands short of the water)
    ThrowLift    = 6.0,   -- Upward force

    -- Third-eye dump spots (piers/docks) - adjust coords to your liking
    Zones = {
        { coords = vec3(-1850.2, -1231.6, 13.0), radius = 5.0 },  -- Del Perro Pier end
        { coords = vec3(-339.4, -2792.9, 6.0),   radius = 5.0 },  -- Elysian docks edge
        { coords = vec3(-275.6, 6635.3, 7.4),    radius = 5.0 },  -- Paleto boat launch
    },

    -- Raw (uncrated) bags resurface later -> anonymous tip + map blip for police
    BagWashAshore = {
        Enabled = true,
        MinMins = 45,   -- Earliest resurface (minutes)
        MaxMins = 120,  -- Latest resurface
        Spots = {
            vec3(-1600.55, -1050.0, 1.0),
            vec3(-1305.0, -1580.0, 1.0),
            vec3(1520.0, 3910.0, 30.0),
            vec3(3860.0, 4459.0, 1.0),
        },
    },
    -- % chance each DNA trace is washed away before the bag resurfaces
    EvidenceDestroyed = 60,
}

-- ██████╗ ███████╗ ██████╗ ██████╗ ███╗   ███╗██████╗
-- ██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗ ████║██╔══██╗
-- ██║  ██║█████╗  ██║     ██║   ██║██╔████╔██║██████╔╝
-- ██║  ██║██╔══╝  ██║     ██║   ██║██║╚██╔╝██║██╔═══╝
-- ██████╔╝███████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║██║
-- ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝

Config.Decomposition = {
    Enabled = true,
    -- Minutes after bagging (real time, tracked server-side). MUST be in ascending order.
    -- unidentifiable = true -> Inspect shows "John Doe" from this stage on
    Stages = {
        { after = 30,  label = 'bloated',  smellRadius = 15.0 },
        { after = 90,  label = 'decayed',  smellRadius = 30.0 },
        { after = 180, label = 'skeletal', smellRadius = 10.0, unidentifiable = true },
    },
    SmellNotify   = 'You smell something rotting nearby...',
    SmellCooldown = 180, -- SECONDS before the same player gets the smell message again
}

--  ██████╗██╗  ██╗    ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗
-- ██╔════╝██║ ██╔╝    ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║
-- ██║     █████╔╝     ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║
-- ██║     ██╔═██╗     ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║
-- ╚██████╗██║  ██╗    ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║
--  ╚═════╝╚═╝  ╚═╝    ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝

Config.CK = {
    Enabled = true,

    -- THE BIG ONE: what happens when a body is destroyed
    -- (burned / dissolved / dumped / buried / dismembered)
    -- 'ck'      = character is PERMANENTLY killed: logged, deleted, player kicked
    -- 'respawn' = old behavior: victim respawns at hospital with NLR (see Config.Hooks.Respawn)
    OnDisposal = 'ck',

    DeleteCharacter = true, -- true = delete ONLY that character from the DB (other chars untouched)
                            -- false = keep the rows, just set users.ck_locked = 1
    KickMessage = 'Your character has been CKed. Their story ends here. Rejoin to play another character.',

    -- Every table that stores per-character data - rows matching the CKed
    -- character identifier get deleted. ADD YOUR CUSTOM TABLES HERE.
    DeleteTables = {
        { table = 'users',              column = 'identifier' },
        { table = 'owned_vehicles',     column = 'owner' },
        { table = 'user_licenses',      column = 'owner' },
        { table = 'datastore_data',     column = 'owner' },
        { table = 'addon_account_data', column = 'owner' },
        { table = 'billing',            column = 'identifier' },
        -- { table = 'okokbanking_transactions', column = 'identifier' },
    },

    -- /ck command (player-to-player, victim must consent)
    VictimConsent  = true,
    RequestTimeout = 60,  -- SECONDS the victim has to answer before the request expires
    RequestCooldown = 30, -- SECONDS between /ck requests from the same player
    -- /forceck command (staff only)
    StaffCanForce = true,

    Obituary = true, -- Server-wide RIP announcement (name only, never the killer)
}

-- ███████╗██╗   ██╗██╗██████╗ ███████╗███╗   ██╗ ██████╗███████╗
-- ██╔════╝██║   ██║██║██╔══██╗██╔════╝████╗  ██║██╔════╝██╔════╝
-- █████╗  ██║   ██║██║██║  ██║█████╗  ██╔██╗ ██║██║     █████╗
-- ██╔══╝  ╚██╗ ██╔╝██║██║  ██║██╔══╝  ██║╚██╗██║██║     ██╔══╝
-- ███████╗ ╚████╔╝ ██║██████╔╝███████╗██║ ╚████║╚██████╗███████╗
-- ╚══════╝  ╚═══╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝

Config.Evidence = {
    Enabled      = true,
    DnaOnBagging = true, -- Everyone who bags / carries / loads a body leaves DNA on it
    PoliceSeeDna = true, -- Police see the DNA list when they Inspect a body / exhume a grave
    PoliceJobs   = { ['police'] = true, ['sheriff'] = true },
}

-- ██████╗ ██╗███████╗██████╗  █████╗ ████████╗ ██████╗██╗  ██╗
-- ██╔══██╗██║██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║
-- ██║  ██║██║███████╗██████╔╝███████║   ██║   ██║     ███████║
-- ██║  ██║██║╚════██║██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║
-- ██████╔╝██║███████║██║     ██║  ██║   ██║   ╚██████╗██║  ██║
-- ╚═════╝ ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝

-- Chance that a witness calls it in. Police get a notify + a rough-area map blip.
-- Want ps-dispatch / cd_dispatch / your own? Use Config.Hooks.PoliceAlert below.
Config.Dispatch = {
    Enabled  = true,
    Chances  = {         -- % per action
        dismember = 35,
        cremation = 25,  -- smoke is visible
        acid      = 10,
        burial    = 15,
        waterDump = 20,
    },
    BlipTime   = 120,    -- SECONDS the blip stays on the map
    BlipRadius = 80.0,   -- Size of the search area circle
    BlipSprite = 161,    -- Center icon
    BlipColour = 1,      -- 1 = red
}

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

-- /bodyadmin opens a menu of every active body (teleport to it / free the victim / clear all)
-- Also used for /forceck.
Config.Admin = {
    Command = 'bodyadmin',
    Groups  = { ['admin'] = true, ['superadmin'] = true, ['mod'] = true },
}

-- ██╗      ██████╗  ██████╗ ███████╗
-- ██║     ██╔═══██╗██╔════╝ ██╔════╝
-- ██║     ██║   ██║██║  ███╗███████╗
-- ██║     ██║   ██║██║   ██║╚════██║
-- ███████╗╚██████╔╝╚██████╔╝███████║
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝

-- Discord webhooks. Leave '' to only log to the server console.
Config.Logs = {
    Webhook   = '', -- Every action (bagged, buried, burned, dumped, ...)
    CKWebhook = '', -- Character kills only (falls back to Webhook if empty)
}

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

Config.Notify = function(msg, type, title)
    lib.notify({
        title = title or Config.UI.Title, description = msg, type = type or 'inform',
        position = Config.UI.Position,
        style = { backgroundColor = Config.UI.Background, color = Config.UI.Text, ['.description'] = { color = Config.UI.Accent } },
    })
end

-- ██╗  ██╗ ██████╗  ██████╗ ██╗  ██╗███████╗
-- ██║  ██║██╔═══██╗██╔═══██╗██║ ██╔╝██╔════╝
-- ███████║██║   ██║██║   ██║█████╔╝ ███████╗
-- ██╔══██║██║   ██║██║   ██║██╔═██╗ ╚════██║
-- ██║  ██║╚██████╔╝╚██████╔╝██║  ██╗███████║
-- ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝

-- Plug your other scripts in here. You never need to touch the client/ or server/ folders.
Config.Hooks = {}

-- [CLIENT] Called on the victim when their body is destroyed and Config.CK.OnDisposal = 'respawn'
Config.Hooks.Respawn = function()
    if GetResourceState('wasabi_ambulance') == 'started' then
        TriggerEvent('wasabi_ambulance:respawn') -- verify the event name against YOUR wasabi version
    else
        local hosp = vec3(295.83, -1446.94, 29.97) -- Pillbox
        SetEntityCoords(cache.ped, hosp.x, hosp.y, hosp.z, false, false, false, false)
        TriggerEvent('esx_ambulancejob:revive')
    end
end

-- [SERVER] Is this player dead? Return true / false to decide yourself,
-- or nil to use the built-in check (statebags dead/isDead + esx:onPlayerDeath + ped health)
Config.Hooks.IsPlayerDead = function(serverId)
    return nil
end

-- [SERVER] Send a police alert your own way. Return true if you handled it
-- (then the built-in notify + blip is skipped).
-- Example (ps-dispatch style): exports['ps-dispatch']:CustomAlert({ coords = coords, message = title, description = message })
Config.Hooks.PoliceAlert = function(coords, title, message)
    return false
end
