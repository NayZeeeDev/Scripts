--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - BLOOD SERVICES
    Discord: discord.gg/nayzeeedev

    Blood donation chairs, the hospital blood bank (fridge), labelled blood
    bags with serials / type / expiry, Type & screen, and the IV stand used in
    the ambulance treatment bay, on hospital beds, in surgery and in the field
    (saline, blood, roller clamp, pressure infuser, TXA push). Hanging the
    wrong blood group causes a transfusion reaction.

    Hospital positions (built in game with /nzadmin → Positions):
        'donation'   donation chair + collection mixer (Config.Props.donation_chair / blood_mixer)
        'bloodbank'  blood fridge (staff deposit / withdraw / fill bags)

    Items are named in config/items.lua (Config.Items.*). Here they are referred
    to by their KEY ('blood_bag', 'empty_blood_bag', ...), never by the inventory name.
    Keys use JavaScript KeyboardEvent.code names: 'Space', 'KeyE', 'Digit1', 'F1' ...
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Blood = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- BLOOD BAGS (item Config.Items.blood_bag, metadata = the bag label)
    -- ═══════════════════════════════════════════════════════════════════════

    Bags = {
        item         = 'blood_bag',        -- labelled unit KEY
        empty        = 'empty_blood_bag',  -- empty collection bag KEY
        ml           = 450,                -- mL of blood in one unit (donated or from the bank)
        bagSize      = 500,                -- bag size shown on the label and the donation counter ("mL of 500")
        serialPrefix = 'BB-',              -- serials look like BB-482913
        shelfDays    = 35,                 -- real days a unit keeps before it expires
        warnDays     = 3,                  -- "expires soon" warning this many days before
        useExpired   = false,              -- true = expired units may still be hung
        product      = 'Red cells in SAG-M', -- product line printed on the label
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- TYPE & SCREEN (patient option: reveals the blood group to the medic)
    -- ═══════════════════════════════════════════════════════════════════════

    TypeScreen = {
        enabled  = true,
        perm     = 'blood',                -- permission needed
        seconds  = 6,                      -- bedside test card time (progress bar)
        distance = 2.2,                    -- metres from the patient for the option
        order    = 27,                     -- patient menu order (assessment band 20-29)
        icon     = 'bloodbag',
        anim     = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },  -- kneeling (patient on the ground)
        animStand = { dict = 'mini@repair', clip = 'fixing_a_ped' },                     -- standing (patient on a bed / chair)
        fee      = 40,                     -- billed to the patient (0 = free)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BLOOD BANK (point type 'bloodbank')
    -- ═══════════════════════════════════════════════════════════════════════

    Bank = {
        perm          = 'blood',           -- deposit / withdraw / fill
        prop          = false,             -- Config.Props key for the fridge model, false = target sphere only
        distance      = 2.5,               -- metres from the point to use it
        shared        = false,             -- true = every blood bank shares one stock; false = stock per department
        needEmptyBag  = true,              -- issuing a unit decants it into an empty bag (Bags.empty); false = withdraw the unit straight
        maxWithdraw   = 6,                 -- units one medic may take out per window (anti-hoarding)
        withdrawWindow = 15,               -- minutes of that window
        maxStock      = 60,                -- units one bank holds at most (deposits are refused above)
        discardExpired = true,             -- expired units leave the stock automatically (logged)
        seed = { ['O-'] = 4, ['O+'] = 4, ['A+'] = 2, ['A-'] = 1, ['B+'] = 1 },  -- units a NEW bank starts with (once)
        npcDonors = {                      -- the city donates too: random units arrive over time
            enabled  = true,
            interval = 40,                 -- minutes between NPC donations per bank
            maxPerType = 6,                -- never above this many units of one type from NPCs
        },
        logSize       = 30,                -- bank events shown in the window
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- DONATION (point type 'donation': chair + mixer, pump with the donor's pulse)
    -- ═══════════════════════════════════════════════════════════════════════

    Donation = {
        enabled       = true,
        mode          = 'both',            -- 'self' (donor runs it alone) | 'medic' (a medic draws it) | 'both'
        perm          = 'blood',           -- medic mode permission
        cooldownDays  = 3,                 -- real days between two donations of the same player
        minBloodPct   = 0.95,              -- donor needs at least this much of their blood volume
        maxPain       = 25,                -- donors in more pain than this are turned away
        noInjuries    = true,              -- open / bleeding injuries make you ineligible
        minTime       = 30,                -- seconds a donation takes at least (anti-cheat)
        maxTime       = 600,               -- seconds before the session times out
        easyTime      = 10,                -- easy mode progress bar
        minUsable     = 300,               -- mL below which the bag is not a usable unit (discarded)
        bagTo         = 'bank',            -- where the unit goes: 'bank' (the chair's hospital) | 'donor' | 'collector'
        items         = { empty_blood_bag = 1 },  -- medic mode supplies (KEY = count), taken on finish
        selfItems     = {},                -- self-service supplies ({} = the chair provides the bag)
        reward = {
            money   = 250,                 -- paid to the donor for a usable unit (0 = none)
            account = 'bank',              -- 'bank' | 'cash'
            items   = {},                  -- extra items for the donor { KEY = count } e.g. { painkillers = 1 }
            medicPay = 75,                 -- paid to the medic who drew it (medic mode, 0 = none)
        },
        weakness = {
            minutes   = 8,                 -- how long the donor feels weak afterwards
            clipset   = 'move_m@drunk@slightlydrunk',  -- walk style while weak (false = none)
            noSprint  = true,              -- no sprinting while weak
            fx        = 'MenuMGIn',        -- short screen effect when standing up (false = none)
            fxSeconds = 6,
        },
        flow = {                           -- minigame tuning (squeeze as each pulse peak crosses the window)
            perfect   = 0.06,              -- beat phase error counted as perfect (0..0.5 of a beat)
            good      = 0.15,              -- ... as good (the band shown on the timing bar)
            maxFlow   = 12,                -- mL/s with a perfect rhythm (also the server's speed cap)
            trickle   = 1.6,               -- mL/s that always runs (gravity) - a bad rhythm still finishes, slowly
            ease      = 0.35,              -- how fast the flow follows your rhythm (0..1 per second)
            cuffBand  = { 40, 60 },        -- mmHg window for the arm cuff (step 1)
            cuffRate  = 38,                -- mmHg per second while pumping the cuff
            sealHold  = 1.5,               -- seconds to hold for removing the needle (step 3)
        },
        sit = {                            -- donor pose in the chair (chair-local offset, tune per sit clip)
            dict    = 'timetable@ron@ig_3_couch',
            clip    = 'base',
            offset  = vec3(0.0, -0.12, 0.58),
            heading = 0.0,                 -- added to the chair heading (180 if the clip faces backwards)
        },
        medicAnim = { scenario = 'WORLD_HUMAN_CLIPBOARD' },          -- medic beside the chair
        medicSpot = vec4(0.95, 0.35, 0.0, 90.0),                     -- where the medic stands (chair-local, heading added)
        selfAnim  = { dict = 'mp_suicide', clip = 'pill_fp' },       -- unused when the sit clip is kept (fallback)
        mixer     = { pos = vec3(0.62, 0.15, 0.0), heading = 0.0 },  -- collection mixer beside the chair (chair-local)
        bagOnMixer = { pos = vec3(-0.15, 0.0, 0.326), rot = vec3(90.0, 0.0, -90.0) },  -- bag lying on the mixer tray
        stand     = { pos = vec3(-0.55, 0.0, 0.0), heading = 0.0, bag = true },        -- decorative IV stand with a saline bag (false = none)
        camera    = { dist = 2.6, height = 0.55, pitch = 26.0, fov = 44.0, yaw = 35.0 },
        lcd       = { enabled = true, width = 256, height = 128, range = 12.0 },        -- live counter on the mixer screen (DUI)
        standKey  = 'X',                   -- key to stand up while waiting for a medic (FiveM key mapping, rebindable)
        keys = { squeeze = 'Space', clamp = 'KeyC', needle = 'KeyE' },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- IV STAND (NUI app 'ivstand' — bay, beds, surgery, field)
    -- ═══════════════════════════════════════════════════════════════════════

    Stand = {
        perm         = 'iv',               -- open the stand, hang saline, set the rate, unhang bags
        bloodPerm    = 'blood',            -- hang blood units
        maxBags      = 2,                  -- hooks on the stand
        salineMl     = 500,                -- one saline bag
        gravity      = 32,                 -- mL/min through a fully open roller clamp, no pressure
        pressureGain = 1.15,               -- flow x (1 + gain * pressure / maxPressure) while the infuser is pumped
        maxPressure  = 300,                -- mmHg on the infuser gauge
        pump         = 24,                 -- mmHg per squeeze
        leak         = 5,                  -- mmHg the infuser loses per second
        maxRate      = 160,                -- mL/min the server ever accepts
        warmInBay    = true,               -- fluids hung in the ambulance bay / a hospital bed count as warmed
        allowIncompatible = true,          -- true = a known mismatch can still be hung after the warning (reaction follows)
        requireAccess = true,              -- an IV / IO / port is needed (else "Place an IV first")
        placeIv = {                        -- how "Place an IV first" starts the cannulation
            interact = 'nza_field_iv',     -- patient option of the field module that is called when present
            fallback = true,               -- no field module: a quick IV placement (progress bar) right here
            item     = 'iv_kit',           -- ...its supplies (KEY)
            seconds  = 8,
            site     = 'l_lower_arm',
        },
        txa = { item = 'txa', perm = 'iv', push = 10 },  -- 1 g TXA slow push over `push` seconds
        interact = { enabled = true, order = 45, distance = 2.4, icon = 'iv' },  -- patient option 'IV stand'
        radial   = true,                   -- 'IV stand' in the EMS radial (Patient)
        examRoute = { enabled = true, belowPct = 88 },   -- 'Transfuse' in the examination when blood volume is below %
        placement = { side = 0.62, along = 0.55 },       -- where the stand appears beside a patient (metres, ped-local)
        camera   = { enabled = true, dist = 2.3, height = 0.35, pitch = 14.0, fov = 46.0 },  -- view of the stand (not in the bay)
        bayStock = { ['O-'] = 2 },         -- units every ambulance fridge holds ('Bag a unit' in the treatment bay)
        bayRefill = 30,                    -- minutes until a used onboard unit is replaced
        keys = { squeeze = 'Space', clampDown = 'KeyQ', clampUp = 'KeyE', txa = 'KeyT', hookA = 'Digit1', hookB = 'Digit2' },
        range    = 6.0,                    -- the panel closes when you walk further from the patient
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- TRANSFUSION REACTION (incompatible blood)
    -- ═══════════════════════════════════════════════════════════════════════

    Reaction = {
        enabled    = true,
        stages     = { 40, 140, 280 },     -- mL of incompatible blood for mild / moderate / severe
        haemolysis = { 0, 5, 14 },         -- mL/min of blood destroyed per stage (on top of the core reaction)
        feverMinutes = 10,                 -- symptoms last this long after the unit is stopped
        speech     = true,                 -- the patient complains (back pain, burning, chills)
        alertMedic = true,                 -- the medic who hung it gets a warning toast
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BILLING (charged to the patient through NZA.Billing when it exists)
    -- ═══════════════════════════════════════════════════════════════════════

    Billing = {
        unit   = 350,                      -- per blood unit hung
        saline = 60,                       -- per saline bag hung
        txa    = 80,                       -- per TXA push
    },
}
