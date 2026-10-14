--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - FIRST AID
    Discord: discord.gg/nayzeeedev

    Stop bleeding (pressure, packing, wrap / pressure dressing), tourniquets,
    cervical collar, oxygen mask, foil blanket, medic medication (dose panel) and
    the self-use first aid items (bandage, medkit, painkillers, ice pack, burn
    dressing, foil blanket).

    Items are named in config/items.lua (Config.Items.*). Here they are referred
    to by their KEY ('bandage', 'gauze', ...), never by the inventory name.
    Keys use JavaScript KeyboardEvent.code names: 'Space', 'Enter', 'KeyE',
    'Digit1' ... ('KeyE' = the E key).
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Firstaid = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- MINIGAME KEYS (KeyboardEvent.code names)
    -- ═══════════════════════════════════════════════════════════════════════

    Keys = {
        confirm = 'Space',     -- confirm a placement / hold to fasten the collar
        lock    = 'KeyE',      -- lock the tourniquet clip / secure the bandage end
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PATIENT MENU (third-eye / target options, order band 40 = treatment)
    -- ═══════════════════════════════════════════════════════════════════════

    Interact = {
        distance   = 2.2,      -- metres from the patient for the options to show
        stopBleed  = true,     -- 'Stop bleeding'
        tourniquet = true,     -- 'Apply tourniquet' / 'Remove tourniquet'
        meds       = true,     -- 'Give medication' (medics with the 'meds' permission)
        collar     = true,     -- 'Apply cervical collar' / 'Remove collar'
        oxygen     = true,     -- 'Oxygen mask' on / off
        foil       = true,     -- 'Foil blanket' on / off
        kit        = true,     -- 'First aid…' (use your bandage, ice pack, medkit... on someone else)
        minBleed   = 1,        -- state bag bleed level (0 none, 1 minor, 2 heavy, 3 massive) for 'Stop bleeding'
        tqBleed    = 2,        -- bleed level at which 'Apply tourniquet' shows
        icons = {              -- NAYZEEE icon names (target scripts get the matching Font Awesome icon)
            stopBleed = 'drop', tourniquet = 'clamp', tqOff = 'clamp', meds = 'syringe', collar = 'collar',
            collarOff = 'collar', oxygen = 'wind', foil = 'blanket', kit = 'medkit',
        },
    },

    Radial = {
        enabled = true,        -- add Stop bleeding / Tourniquet / Medication / First aid to the EMS radial (Patient)
        range   = 3.0,         -- the radial acts on the nearest patient within this many metres
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- STOP BLEEDING (NZA.Proc 'stopbleed')
    -- 1. direct pressure → 2. pack the wound (deep wounds) → 3. wrap (limbs) or pressure dressing (torso)
    -- ═══════════════════════════════════════════════════════════════════════

    StopBleed = {
        perm      = 'basic',   -- permission (Config.PublicPerms gives 'basic' to everyone by default)
        types     = { 'gunshot', 'shrapnel', 'stab', 'laceration', 'abrasion' },  -- injuries this treats
        minBleed  = 0.5,       -- mL/min: wounds bleeding less than this are not worth it
        abrasionMin = 2.0,     -- abrasions only show the route when they bleed at least this much
        pack = {               -- wounds that must be packed: type = minimum severity (1..4)
            gunshot = 2, stab = 2, shrapnel = 2, laceration = 4,
        },
        packDepth = 15,        -- ...or any wound deeper than this (mm)
        items = {              -- item KEY = amount, per step that is performed
            pack     = { gauze = 1 },
            wrap     = { bandage = 1 },
            dressing = { bandage = 1 },
        },
        minTime   = 8,         -- seconds; faster finishes are rejected (anti-cheat)
        maxTime   = 300,
        easyTime  = 8,         -- progress bar length in easy mode
        failScore = 30,        -- a step scored below this does not count (the dressing leaks / the packing falls out)
        qualityBonus = 0.4,    -- a perfect job lowers the wound's base bleed by up to 40 % on top of the dressing
        -- minigame tuning
        pressureTarget = 0.30, -- direct pressure: bleed must fall below this fraction...
        pressureHold   = 2.5,  -- ...and stay there this many seconds
        packStrips     = 4,    -- gauze feeds needed to fill a deep wound (a sloppy feed counts half)
        wrapTurns      = 4,    -- turns of bandage around a limb
        tensionBand    = { 0.38, 0.72 },  -- even-tension band of the wrap gauge (0..1)
        anim = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },  -- medic loop during the minigame
        camera = { dist = 0.95, pitch = 58.0, fov = 42.0 },  -- close-up on the wound
        -- a plain bandage on a heavy bleed (no packing) may soak through later
        soak = {
            enabled = true,
            minBleed = 40,     -- base bleed (mL/min) from which an unpacked dressing can soak through
            quality  = 70,     -- dressings applied at or above this quality never soak
            after    = 240,    -- seconds until it soaks through
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- TOURNIQUET (NZA.Proc 'tourniquet') - place high & tight, twist the windlass, lock the clip
    -- ═══════════════════════════════════════════════════════════════════════

    Tourniquet = {
        perm      = 'basic',
        item      = 'tourniquet', -- item KEY
        minTime   = 6,
        maxTime   = 240,
        easyTime  = 7,
        minBleed  = 15,        -- mL/min: the exam only suggests a tourniquet from this bleed on
        jointZone = 0.10,      -- fraction of a segment next to the elbow / knee that counts as "on the joint"
        idealAbove = { 5, 8 }, -- cm above the wound that count as perfect ("high and tight" is also fine)
        armLength  = 62,       -- cm shoulder → wrist used for the distance readout
        legLength  = 88,       -- cm hip → ankle
        occlusion = {          -- pressure (mmHg) that stops arterial flow = systolic + this, clamped
            arm = 60, leg = 100, min = 140, max = 330,
        },
        turnGain   = { arm = 62, leg = 68 },  -- mmHg added by one full turn of the windlass
        overMargin = 110,      -- mmHg above occlusion that counts as over-tightened (nerve damage risk)
        unwind     = 22,       -- mmHg per second the windlass springs back while you are not turning
        clipWindow = 14,       -- degrees: the rod must be this close to the clip to lock it
        overPain   = 15,       -- extra pain on the wound when it was badly over-tightened
        clock      = 'game',   -- time written on the strap: 'game' (in-game clock) or 'real' (server time)
        -- time limits (seconds of real time with the tourniquet on)
        warnAfter   = 1200,    -- warn the patient / the medic who applied it
        damageAfter = 2400,    -- then the limb below is damaged (injury added once)
        damage = { type = 'contusion', severity = 3 },  -- what the damage looks like
        checkEvery  = 15,      -- seconds between server checks
        removeReturns = true,  -- taking a tourniquet off gives the item back
        removePerm  = 'basic', -- permission to remove one
        camera = { dist = 1.35, pitch = 62.0, fov = 46.0 },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CERVICAL COLLAR (NZA.Proc 'collar') - measure & size, then fasten while holding the head in line
    -- ═══════════════════════════════════════════════════════════════════════

    Collar = {
        perm      = 'splint',
        item      = 'cervical_collar',
        minTime   = 6,
        maxTime   = 240,
        easyTime  = 7,
        fastenSeconds = 4.0,   -- seconds of fastening (only counts while the head is kept in line)
        drift     = 1.0,       -- how hard the head drifts while you fasten (0.5 calm .. 2 restless)
        removeReturns = true,  -- taking a collar off gives the item back
        camera = { dist = 0.85, pitch = 52.0, fov = 42.0 },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- OXYGEN MASK
    -- ═══════════════════════════════════════════════════════════════════════

    Oxygen = {
        perm    = 'airway',
        item    = 'oxygen_mask',
        consume = true,        -- the mask is used up when applied
        removeReturns = false, -- taking it off gives the mask back
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped', duration = 2500 },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- FOIL BLANKET (hypothermia) - anyone, on yourself or others
    -- ═══════════════════════════════════════════════════════════════════════

    Foil = {
        perm = nil,            -- nil = everyone ('basic' if you want only first aiders)
        item = 'foil_blanket',
        removeReturns = false,
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- SELF-USE ITEMS (use them from the inventory, or on others with 'First aid…')
    -- ═══════════════════════════════════════════════════════════════════════

    Items = {
        bandage = {
            enabled = true, self = true, duration = 5000,
            maxBleed = 25,     -- mL/min: a quick bandage only handles minor bleeding (heavier → Stop bleeding)
            quality = 55,      -- quality of a quick bandage (soak rules above apply)
            anim = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 },
        },
        medkit = {
            enabled = true, self = true, duration = 8000,
            maxSeverity = 2,   -- abrasions / contusions up to this severity, lacerations of severity 1
            heal = 8,          -- heal points added to every injury (also gives back a little blood)
            anim = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 },
        },
        painkillers = {
            enabled = true, self = true, duration = 2500,
            stack = false,     -- false: can't take more while they still work
            anim = { dict = 'mp_suicide', clip = 'pill', flag = 49 },
        },
        ice_pack = {
            enabled = true, self = true, duration = 4500,
            fracturePain = 0.8,  -- fracture pain × this (swelling down)
            anim = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 },
        },
        burn_dressing = {
            enabled = true, self = true, duration = 5500,
            maxDegree = 2,     -- burns up to this degree...
            maxSeverity = 2,   -- ...and this severity (worse burns need the burn care procedure)
            anim = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 },
        },
        foil_blanket = {
            enabled = true, self = true, duration = 3000,
            anim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d', flag = 49 },
        },
        othersAnim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },  -- treating someone standing
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- MEDICATION (dose panel, medics with the 'meds' permission)
    -- dose = multiplier passed to the core (1 = standard dose)
    -- route 'iv' needs an IV / IO / port (the iv module places them)
    -- ═══════════════════════════════════════════════════════════════════════

    Meds = {
        perm = 'meds',
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1, duration = 2600 },
        prop = 'syringe',      -- Config.Props key held during the injection
        keepOpen = false,      -- keep the panel open after giving a drug
        morphineRR = 10,       -- warn (and depress breathing further) below this respiratory rate
        morphineSys = 90,      -- warn below this systolic pressure
        lowRRDepression = 18,  -- opioid load added per dose when morphine is pushed with RR under morphineRR
        naloxoneWake = true,   -- a reversed opioid overdose wakes the patient up (agitated)
        agitated = { dict = 'misscarsteal4@actor', clip = 'actor_berating_loop', duration = 6000 },  -- NPC reaction
        camera = { dist = 2.2, pitch = 28.0, fov = 45.0 },  -- view on the patient while the panel is open
        drugs = {
            { id = 'morphine', item = 'morphine', icon = 'syringe', routes = { 'iv', 'im' },
              doses = { { dose = 0.5, mg = '2.5 mg' }, { dose = 1, mg = '5 mg' }, { dose = 2, mg = '10 mg' } }, default = 2 },
            { id = 'adrenaline', item = 'adrenaline', icon = 'bolt', routes = { 'im', 'iv' },
              doses = { { dose = 0.5, mg = '0.5 mg' }, { dose = 1, mg = '1 mg' } }, default = 1 },
            { id = 'naloxone', item = 'naloxone', icon = 'syringe', routes = { 'in', 'im', 'iv' },
              doses = { { dose = 0.5, mg = '0.4 mg' }, { dose = 1, mg = '0.8 mg' }, { dose = 2, mg = '2 mg' } }, default = 2 },
            { id = 'txa', item = 'txa', icon = 'drop', routes = { 'iv' }, access = true,
              doses = { { dose = 1, mg = '1 g' } }, default = 1 },
            { id = 'antibiotics', item = 'antibiotics', icon = 'pill', routes = { 'iv', 'im' },
              doses = { { dose = 1, mg = '1 g' }, { dose = 2, mg = '2 g' } }, default = 1 },
            { id = 'painkillers', item = 'painkillers', icon = 'pill', routes = { 'po' },
              doses = { { dose = 1, mg = '1 g' } }, default = 1 },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- WORN PROPS (rendered on every client from the patient's state bags)
    -- prop = Config.Props key or model name; false = no prop
    -- ═══════════════════════════════════════════════════════════════════════

    Props = {
        range = 45.0,          -- only peds closer than this get props
        tourniquet = { prop = 'tourniquet_worn', default = { upper = 0.22, lower = 0.30 } },  -- fraction along the bone
        collar = { prop = 'collar', bone = 39317, pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 90.0, 0.0) },
        oxygen = { prop = 'oxygen_mask', bone = 31086, pos = vector3(0.04, 0.12, 0.0), rot = vector3(0.0, 90.0, 180.0) },
        foil   = { prop = 'foil_blanket', bone = 24818, pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 90.0, 0.0) },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BILLING (player patients, only when the one treating is an on-duty medic; 0 = free)
    -- ═══════════════════════════════════════════════════════════════════════

    Billing = {
        stopbleed = 0,
        tourniquet = 0,
        collar = 0,
        oxygen = 0,
        meds = 0,
    },
}
