--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - MEDICAL BAG, BODY BAG & MORGUE
    Discord: discord.gg/nayzeeedev

    MEDICAL BAG   Use the medical bag item to put the bag on the ground. Open it and take the
                  supplies you need: the bag never runs out (Storage.unlimited). Carry it in
                  your hand while you walk or run, or pick it up again. Medics get the bag from
                  the supply officer NPC at the hospital (Config.Hospital.storage).
    BODY BAG      Zip a deceased patient (player or NPC) into a body bag, carry it, put it on
                  a stretcher or in a vehicle, and deliver it to a MORGUE point (built in game
                  with /nzadmin). Players wake up at the hospital; NPCs pay a reward.

    Controls use GTA control ids (https://docs.fivem.net/docs/game-references/controls/)
    together with the key label shown on screen.
    Vectors: vec3(x, y, z) = right, forward, up of the entity they belong to.
    Weights are in grams.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Medbag = {

    radial = true,               -- add medical bag / body bag entries to the EMS radial menu (F6)

    -- ═══════════════════════════════════════════════════════════════════════
    -- MEDICAL BAG (the prop and what you can do with it)
    -- ═══════════════════════════════════════════════════════════════════════

    Bag = {
        enabled       = true,
        model         = nil,     -- nil = Config.Props.medbag (streamed). Set a model name to use your own
        extraModels   = { 'xm_prop_x17_bag_med_01a' },  -- other models that count as a medical bag (targets)
        -- Bag colours the owner can pick in the bag window (each one is a streamed model).
        -- false = every bag uses Config.Props.medbag / Bag.model.
        colours = {
            { id = 'red',     model = 'nz_amb_medbag_red',     hex = '#e5484d' },
            { id = 'orange',  model = 'nz_amb_medbag_orange',  hex = '#f08a24' },
            { id = 'green',   model = 'nz_amb_medbag_green',   hex = '#2fb36b' },
            { id = 'magenta', model = 'nz_amb_medbag_magenta', hex = '#d23c9a' },
        },
        defaultColour = 'red',   -- colour of a new bag
        nameLength    = 20,      -- the owner can name a bag ("Trauma", "Airway"...); max characters
        whoCanPlace   = 'anyone', -- 'anyone' | 'medic' (on-duty medics only) - who may use the item
        placeAhead    = 0.85,    -- the bag is put down this far in front of you (metres)
        distance      = 2.0,     -- reach for the bag's options (open, carry, pick up)
        openRange     = 3.5,     -- the window closes when you walk further than this from the bag
        maxOut        = 2,       -- bags one player may have on the ground at once (0 = no limit)
        persist       = true,    -- bags left on the ground come back after a restart
        putDown       = { dict = 'random@domestic', clip = 'pickup_low', ms = 900 },   -- bend down (false = none)
        pickUp        = { dict = 'random@domestic', clip = 'pickup_low', ms = 900 },

        Carry = {
            enabled  = true,
            -- held by the top handle at your side, arm down (SKEL_R_Hand; rotOrder 1 = the order these angles are in)
            bone     = 57005,
            pos      = vec3(0.39, -0.06, -0.06),
            rot      = vec3(-100.0, -180.0, -78.0),
            rotOrder = 1,
            anim     = { dict = 'move_weapon@jerrycan@generic', clip = 'idle', flag = 49 },  -- upper body only: you can walk, run and sprint (false = none)
            maxSpeed = 3.0,                         -- 1.0 walk, 2.0 jog, 3.0 sprint
            keys = {
                drop = { control = 47, label = 'G' },   -- put the bag down
                open = { control = 38, label = 'E' },   -- open it while holding it
                stow = { control = 74, label = 'H' },   -- put it back in your inventory
            },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- STORAGE (what fits in a bag)
    -- ═══════════════════════════════════════════════════════════════════════

    Storage = {
        -- UNLIMITED SUPPLIES: every bag carries the 'supplies' list below and never runs out. Click a
        -- supply to take one (Shift = up to its 'hold'); nothing is packed into the bag, so the window
        -- shows the bag only (no pockets panel). false = a real storage bag (pockets, restock, par levels).
        unlimited    = true,
        -- what an unlimited bag hands out, in slot order (main compartment 1-12, lid 13-16, pouches 17-20).
        -- hold = the most of it one player may carry; the bag stops handing it out at that count.
        supplies = {
            { item = Config.Items.bandage,         hold = 10 },
            { item = Config.Items.gauze,           hold = 10 },
            { item = Config.Items.tourniquet,      hold = 4 },
            { item = Config.Items.dressing,        hold = 6 },
            { item = Config.Items.burn_dressing,   hold = 4 },
            { item = Config.Items.painkillers,     hold = 6 },
            { item = Config.Items.iv_kit,          hold = 4 },
            { item = Config.Items.suture_kit,      hold = 3 },
            { item = Config.Items.iodine,          hold = 6 },
            { item = Config.Items.lidocaine,       hold = 4 },
            { item = Config.Items.morphine,        hold = 4 },
            { item = Config.Items.adrenaline,      hold = 4 },
            { item = Config.Items.splint,          hold = 2 },
            { item = Config.Items.cervical_collar, hold = 1 },
            { item = Config.Items.ice_pack,        hold = 2 },
            { item = Config.Items.foil_blanket,    hold = 2 },
            { item = Config.Items.saline_bag,      hold = 3 },
            { item = Config.Items.saline,          hold = 3 },
            { item = Config.Items.oxygen_mask,     hold = 1 },
            { item = Config.Items.txa,             hold = 2 },
        },

        slots        = 20,       -- slots per bag
        maxWeight    = 18000,    -- grams (18 kg)
        maxStack     = 50,       -- units per slot for stackable items
        mode         = 'medical', -- 'medical' = only this resource's items (config/items.lua) + extra ; 'all' = everything not blocked
        extra        = {},       -- extra item names allowed in 'medical' mode, e.g. { 'water', 'sandwich' }
        blocked      = { 'money', 'cash', 'black_money', 'markedbills' },  -- never allowed (the medical bag itself is always blocked)
        blockWeapons = true,     -- item names starting with WEAPON_ are never allowed
        weights      = {},       -- unit weight overrides for items that are not in config/items.lua: { water = 500 }
        defaultWeight = 100,     -- unit weight of unknown items
        personalMax  = 'auto',   -- your own capacity bar: 'auto' (ox_inventory / qb max weight) or grams, or false to hide it
        personalFallback = 30000, -- used when 'auto' can't read the inventory's limit
        moveRate     = { count = 10, window = 1000 },  -- moves per player per window (ms)

        -- How the bag window draws the open bag. Compartments take the slot numbers in this order
        -- (main = slots 1-12, lid = 13-16, ...). Keep the total equal to 'slots'; extra slots go to main.
        -- place: 'main' (grid with elastic loops) | 'lid' (mesh pocket on the lid) | 'left' / 'right' (side pouches)
        compartments = {
            { id = 'main',  place = 'main',  slots = 12, cols = 3 },   -- label: locale 'medbag.cmp_<id>'
            { id = 'lid',   place = 'lid',   slots = 4 },
            { id = 'left',  place = 'left',  slots = 2 },
            { id = 'right', place = 'right', slots = 2 },
        },

        -- (unlimited = false only) Par levels: what a stocked bag carries. "Restock" tops the bag up to these counts from
        -- your pockets; the window shows a par bar on stocked supplies and a shadow outline for
        -- missing ones (click it to pack that supply). {} = no restock button.
        kit = {
            { item = Config.Items.bandage,       count = 10 },
            { item = Config.Items.gauze,         count = 10 },
            { item = Config.Items.tourniquet,    count = 4 },
            { item = Config.Items.dressing,      count = 6 },
            { item = Config.Items.burn_dressing, count = 4 },
            { item = Config.Items.painkillers,   count = 6 },
            { item = Config.Items.ice_pack,      count = 2 },
            { item = Config.Items.splint,        count = 2 },
            { item = Config.Items.foil_blanket,  count = 2 },
            { item = Config.Items.iv_kit,        count = 2 },
            { item = Config.Items.saline_bag,    count = 2 },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ACCESS (who may open / carry / pick up a bag)
    -- ═══════════════════════════════════════════════════════════════════════

    Access = {
        owner   = true,          -- the player who first put the bag down owns it
        medics  = true,          -- any medic (Config.Jobs.medic), on duty when Config.Jobs.requireDuty
        perm    = false,         -- or a permission medics need for other people's bags, e.g. 'basic'
        police  = false,         -- police (Config.Jobs.police) may open bags too
        anyone  = false,         -- everyone may open every bag
        lock    = true,          -- the owner can lock a bag: then only the owner (and admins) can open or take it
        admins  = true,          -- admins (ace nza.admin) always have access
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BODY BAG
    -- ═══════════════════════════════════════════════════════════════════════

    Body = {
        enabled     = true,
        perm        = 'bodybag', -- permission to bag, carry and deliver bodies (the prop is Config.Props.bodybag)
        requireItem = true,     -- needs Config.Items.bodybag (used up when the bag is closed)
        distance    = 2.0,       -- reach for the options
        time        = 9,         -- seconds to bag a body (the three steps below share it)
        anyDeadPed  = true,      -- also bag dead ambient NPCs that are not patients yet
        unbag       = true,      -- 'Open body bag' on a bag with a player inside (body lies there again)
        returnItem  = false,     -- opening a bag gives the body bag item back
        groundOffset = vec3(0.0, 0.0, 0.0),   -- bag on the ground relative to where the body lay
        bagHeading  = 0.0,       -- degrees added to the body's heading for the bag on the ground
        insideOffset = vec3(0.0, 0.0, 0.20),  -- where the (hidden) player sits inside the bag
        zipCard     = true,      -- the zip-up card (steps + a closing zipper) while bagging; false = plain progress bars
        cancelKey   = { control = 73, label = 'X' },   -- stop bagging (zip-up card)
        tagSeconds  = 9,         -- how long the toe tag stays on screen after 'Read the toe tag'

        -- the zip-up sequence; 'share' = part of 'time'
        steps = {
            { label = 'step_unfold', share = 0.30, dict = 'amb@medic@standing@tendtodead@enter',  clip = 'enter',  flag = 2 },
            { label = 'step_roll',   share = 0.40, dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 },
            { label = 'step_zip',    share = 0.30, dict = 'amb@medic@standing@kneel@idle_a',      clip = 'idle_a', flag = 1 },
        },

        Carry = {
            enabled  = true,
            bone     = 0,                            -- over the right shoulder
            pos      = vec3(0.24, 0.02, 0.62),
            rot      = vec3(0.0, 0.0, 0.0),
            anim     = { dict = 'missfinale_c2mcs_1', clip = 'fin_c2_mcs_1_camman', flag = 49 },
            pickup   = { dict = 'anim@heists@narcotics@trash', clip = 'pickup', ms = 900 },
            maxSpeed = 1.0,                          -- walk only
            putAhead = 0.9,                          -- the bag is put down this far in front of you
            dropHeading = 90.0,                      -- the bag lies across your path (degrees added to your heading)
            keys = {
                drop    = { control = 47, label = 'G' },   -- put the bag down
                context = { control = 38, label = 'E' },   -- morgue / stretcher / vehicle when one is near
            },
        },

        -- on a stretcher (transport module): the bag is laid on the mattress
        Stretcher = {
            enabled = true,
            range   = 2.6,                           -- metres from the cot
            pos     = vec3(0.0, 0.0, 0.93),          -- on the cot entity
            rot     = vec3(0.0, 0.0, 0.0),
        },

        -- in a vehicle (trunk / cargo area)
        Vehicle = {
            enabled = true,
            range   = 3.0,                           -- metres from the back of the vehicle
            max     = 2,                             -- bags per vehicle
            openDoor = true,                         -- open the boot / back doors while loading
            blockedClasses = { 8, 13, 14, 15, 16, 21 },   -- motorbikes, cycles, boats, helicopters, planes, trains
            models  = {},                            -- if not empty: only these models (e.g. { 'ambulance', 'romero' })
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- MORGUE (point type 'morgue', placed with the hospital builder)
    -- ═══════════════════════════════════════════════════════════════════════

    Morgue = {
        range    = 4.0,          -- the body has to be this close to the morgue point
        respawn  = 'hospital',   -- players delivered here wake up at: 'hospital' (respawn point / bed) | 'morgue' (the point itself)
        fee      = false,        -- charge players the normal respawn fee (Config.Death.respawnFee)
        reward = {
            npc     = 150,       -- paid to the medic for an NPC body
            player  = 0,         -- paid to the medic for a player body
            account = 'bank',    -- 'bank' | 'cash'
            society = 0,         -- also paid into Config.Billing.society per body
        },
        -- Used only while no hospital has a morgue point built in game:
        -- { label = 'Pillbox morgue', coords = vec4(x, y, z, heading) }
        fallback = {},
        fallbackMarker = true,   -- draw a marker at fallback morgues while you carry a body bag
    },
}
