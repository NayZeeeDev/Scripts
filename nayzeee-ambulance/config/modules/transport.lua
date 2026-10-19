--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - TRANSPORT
    Discord: discord.gg/nayzeeedev

    Carry patients, stretchers (push, raise / lower, load into the ambulance),
    hospital beds & tables, and the walk-in ambulance TREATMENT BAY.

    Controls in this file use GTA control ids (https://docs.fivem.net/docs/game-references/controls/)
    together with the key label shown on screen. The treatment bay keys are
    FiveM key mappings (players can rebind them in Settings → Key Bindings → FiveM).
    Vectors: vec3(x, y, z) = right, forward, up of the entity they belong to.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Transport = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- GENERAL
    -- ═══════════════════════════════════════════════════════════════════════

    perm       = 'transport',  -- permission for stretchers, beds and the treatment bay (Config.DefaultPerms / departments)
    radial     = true,         -- add Carry / Stretcher / Bay entries to the EMS radial menu
    radialRange = 3.0,         -- the radial acts on the nearest patient / stretcher / ambulance within this many metres

    -- ═══════════════════════════════════════════════════════════════════════
    -- CARRY (fireman carry - works on player and NPC patients)
    -- ═══════════════════════════════════════════════════════════════════════

    Carry = {
        enabled  = true,
        perm     = 'transport',  -- false = anyone may carry a downed patient (police, civilians)
        states   = { wounded = true, arrest = true, dead = true, alive = false },  -- patient states that can be carried
        distance = 2.0,          -- metres from the patient for the option to show
        maxSpeed = 1.0,          -- 1.0 = walk, 2.0 = jog, 3.0 = sprint while carrying
        carrier  = { dict = 'missfinale_c2mcs_1', clip = 'fin_c2_mcs_1_camman', flag = 49 },   -- the one carrying
        carried  = { dict = 'nm', clip = 'firemans_carry', flag = 33 },                         -- over the shoulder
        attach   = { bone = 0, pos = vec3(0.27, 0.15, 0.63), rot = vec3(0.5, 0.5, 180.0) },    -- carried ped on the carrier
        pickup   = { dict = 'anim@heists@narcotics@trash', clip = 'pickup', ms = 900 },         -- bend down before lifting (false = none)
        keys = {
            drop    = { control = 47, label = 'G' },   -- put the patient down
            context = { control = 38, label = 'E' },   -- put on a stretcher / bed / into a vehicle seat (when one is near)
        },
        seats = { 1, 2, 0 },     -- vehicle seats a carried patient can be put in (1 / 2 = rear left / right, 0 = front passenger)
        seatRange = 3.2,         -- metres from a vehicle door
        dropAhead = 0.9,         -- the patient is put down this far in front of you
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- HELP UP (a stabilised, conscious wounded patient back on their feet)
    -- ═══════════════════════════════════════════════════════════════════════

    HelpUp = {
        enabled  = true,
        perm     = 'basic',       -- false = anyone
        distance = 2.0,
        anim     = { dict = 'anim@heists@narcotics@trash', clip = 'pickup', ms = 1100 },  -- the helper reaches down
        npcGetUp = { dict = 'get_up@directional@movement@from_knees@action', clip = 'getup_r_0', ms = 1500 },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- STRETCHER
    -- ═══════════════════════════════════════════════════════════════════════

    Stretcher = {
        enabled   = true,
        model     = 'stretcher',     -- Config.Props key (config/props.lua). Native fallback: Config.PropFallbacks.stretcher
        lowModel  = 'stretcher_low', -- Config.Props key of a folded / lowered cot; when it does not exist the cot keeps its model
        distance  = 2.4,             -- metres for the stretcher target options
        findRange = 6.0,             -- 'Lift onto the stretcher' looks for a free stretcher this close to the patient
        maxPerVehicle = 1,           -- stretchers one ambulance can have out at the same time
        abandon   = 1200,            -- an EMPTY stretcher nobody touched for this many seconds is put away (0 = never)

        push = {
            bone     = 0,                         -- ped bone id the cot is attached to (0 = ped root)
            pos      = vec3(0.0, 1.42, -0.97),    -- cot origin relative to the pusher (the foot-end handle in the hands)
            rot      = vec3(0.0, 0.0, 0.0),
            anim     = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 51 },   -- arms forward on the handle
            maxSpeed = 1.0,                       -- 1.0 = walk, 2.0 = jog
            lowSpeed = 0.55,                      -- move speed while the cot is lowered
            grabMs   = 450,                       -- short grab animation before the cot moves with you
        },

        patient = {
            surface = 0.885,                      -- top of the mattress above the cot's origin (nz_amb_stretcher)
            pos  = vec3(0.0, 0.05, 0.0),          -- nudge on the mattress (stretcher entity space); the height above
                                                  -- the mattress comes from Beds.lift / the measured lying height
            rot  = vec3(0.0, 0.0, 180.0),
            lowZ = -0.42,                         -- added to pos.z while the cot is lowered (only with a low model)
            anim = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 },
        },

        lever = { dict = 'anim@mp_player_intmenu@key_fob@', clip = 'fob_click', ms = 700 },   -- raise / lower

        keys = {
            release = { control = 47, label = 'G' },   -- let go of the cot
            context = { control = 38, label = 'E' },   -- load / return / move the patient to a bed
            height  = { control = 74, label = 'H' },   -- raise / lower
        },

        load = {
            slideMs    = 1400,   -- how long the cot rolls into / out of the ambulance
            openDoors  = true,   -- open the rear doors for loading / unloading
            closeDoors = true,   -- and close them again
            autoLower  = true,   -- the legs fold (lowered) when the cot goes in, unfold when it comes out
        },

        -- Vehicles that carry a stretcher. Key = spawn name.
        --   pos / rot  where the cot sits inside (vehicle space)
        --   rear       how far behind the vehicle centre the back doors are (nil = from the model size)
        --   doors      rear door indexes (2 = back left, 3 = back right)
        --   bay        the walk-in treatment bay can be used in this vehicle
        vehicles = {
            ambulance = { pos = vec3(-0.18, -1.62, -0.36), rot = vec3(0.0, 0.0, 0.0), rear = nil, doors = { 2, 3 }, bay = true },
            -- emsvan = { pos = vec3(0.0, -1.4, -0.30), rot = vec3(0.0, 0.0, 0.0), doors = { 2, 3 }, bay = true },
        },
        rearReach = 2.3,         -- metres from the back doors for the ambulance options
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- HOSPITAL BEDS & TABLES (points placed with the builder)
    -- ═══════════════════════════════════════════════════════════════════════

    Beds = {
        enabled = true,
        range   = 3.0,           -- metres between the stretcher / you and a bed for 'Transfer to ...'
        -- How high a lying patient sits. A lying animation keeps the body some way under the ped; the
        -- first time an animation plays, the pelvis bone is measured and the ped is lifted so the back
        -- rests 'back' metres above the mattress / table top / stretcher (remembered per animation).
        -- 'lift' is only the first guess before that measurement. 'probe' = look for the real surface
        -- with a ray from this many metres above the expected top (false = trust pos / lie).
        lift  = 0.95,
        back  = 0.11,
        probe = 0.5,
        -- Point types a patient can lie on. Any other point type whose data has bed = true works too.
        --   pos / heading  where the mattress / table top is from the point (point space; a point's
        --                  own data.lie wins) - the ray then finds the exact top
        --   lift / probe   per type overrides of the two values above
        --   anim           lying (or sitting) animation
        --   heal           counts as a hospital bed (faster healing, rewarming)
        types = {
            bed        = { pos = vec3(0.0, 0.0, 0.0), heading = 0.0, heal = true, probe = 1.4 },    -- marker on the bed or the floor beside it
            surgery    = { pos = vec3(0.0, 0.0, 0.0), heading = 0.0, heal = false },                -- table top from Config.Bullet.Table.lie
            xray       = { pos = vec3(0.0, 0.0, 0.825), heading = 0.0, heal = false },              -- nz_amb_xray_table pad top
            angio      = { pos = vec3(0.0, 0.0, 0.825), heading = 0.0, heal = false },              -- (Config.Angio.Suite.lie)
            ultrasound = { pos = vec3(0.0, 0.0, 0.0), heading = 0.0, heal = false, probe = 1.4 },   -- a bed beside the cart, or the floor
            donation   = { pos = vec3(0.0, 0.0, 0.0), heading = 0.0, heal = false, lift = 0.0, probe = false,
                           anim = { dict = 'timetable@ron@ig_3_couch', clip = 'base', flag = 1 } },
        },
        anim = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 },   -- default lying animation
        leaveSide = 1.0,         -- a patient helped off the table stands this far beside it
        selfLeave = { enabled = true, control = 73, label = 'X', hold = 1.5 },  -- an ALIVE patient may get up by themselves
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- AMBULANCE TREATMENT BAY (walk-in interior)
    -- ═══════════════════════════════════════════════════════════════════════

    Bay = {
        enabled = true,
        shell   = 'bay_shell',   -- Config.Props key of the interior model
        -- When the interior model is missing this native block is used as a floor so nobody falls
        fallbackFloor = 'stt_prop_stunt_bblock_mdm3',

        -- Hidden location under Mount Chiliad. Every ambulance gets its own slot on a grid.
        base     = vec3(480.0, 5580.0, 360.0),
        spacing  = 32.0,         -- metres between slots
        columns  = 6,            -- slots per grid row
        maxSlots = 36,           -- ambulances with an open bay at the same time

        -- Positions inside the bay (shell space: origin = the floor centre, +Y = towards the cab, -Y = the
        -- rear doors, patient side -X, bench + counter +X; room 2.30 x 4.30 x 2.05 m)
        stretcher = vec4(-0.42, 0.10, 0.0, 0.0),        -- where the cot stands (head end towards the cab)
        medics = {                                       -- where medics appear (one spot per medic, in order)
            vec4(0.25, -0.30, 0.0, 90.0),                --   beside the patient's hips, facing the cot
            vec4(0.25, 0.75, 0.0, 90.0),                 --   beside the chest
            vec4(-0.42, 1.55, 0.0, 180.0),               --   at the head end (airway)
            vec4(0.30, -1.62, 0.0, 0.0),                 --   by the rear doors
        },
        shelves = {                                      -- target spheres 'Supplies' on the cabinets
            vec3(0.95, 0.20, 1.65),
            vec3(-0.95, -1.00, 1.65),
        },
        ivHooks = { vec3(-0.18, 0.95, 1.86), vec3(-0.18, -0.30, 1.86) },   -- handed to the IV stand module (bay:ivstand)
        props = {                                        -- small local props that dress the bay (Config.Props keys)
            { model = 'monitor', pos = vec4(-1.02, 0.30, 1.10, 270.0) },   -- patient monitor on the wall shelf
            { model = 'sharps',  pos = vec4(0.92, 1.30, 0.95, 90.0) },     -- sharps bin on the counter
            { model = 'kitcase_closed', pos = vec4(0.93, -1.30, 0.50, 90.0) }, -- trauma case on the bench
        },
        lights = {                                       -- interior lights (DrawLightWithRange every frame)
            { pos = vec3(0.0, -1.0, 1.95), color = { 255, 248, 235 }, range = 4.5, intensity = 3.0 },
            { pos = vec3(0.0, 0.95, 1.95), color = { 255, 248, 235 }, range = 4.5, intensity = 3.0 },
            { pos = vec3(-0.42, 0.10, 1.75), color = { 214, 238, 255 }, range = 2.4, intensity = 1.6 },  -- over the cot
        },

        perm          = 'transport',
        rearReach     = 2.3,     -- metres from the back doors for 'Enter treatment bay'
        maxEnterSpeed = 1.5,     -- m/s - the ambulance must be (almost) standing still to climb in
        fadeMs        = 550,
        hideRadar     = true,    -- hide the minimap inside (it would show where the bay really is)
        exitBehind    = 1.2,     -- metres behind the back doors you step out

        keys = {                 -- FiveM key mappings (defaults, players can rebind)
            exit     = 'BACK',   -- Backspace: leave the bay
            examine  = 'F1',     -- examine the patient
            supplies = 'F2',     -- supplies shelves
            ivstand  = 'F3',     -- IV stand (blood module)
            monitor  = 'F4',     -- big patient monitor
        },

        -- Warnings shown on the bay HUD
        warnings = {
            surgeryBlood = true,  -- retained bullets / internal bleeding and no blood running
            bleeding     = 25,    -- total bleed (mL/min) above this
            noAccess     = true,  -- no IV / IO access while the patient is losing blood
            arrest       = true,  -- cardiac arrest
            cold         = 35.0,  -- body temperature below this
            moving       = 45,    -- km/h above which 'hold on' is shown
        },

        -- Free supplies on the shelves (limits per medic per shift).
        -- A shift starts when you go on duty, or after 'shiftLength' seconds.
        supplies = {
            enabled     = true,
            shiftLength = 14400,
            categories = {
                { id = 'wound',   icon = 'bandage' },
                { id = 'fluids',  icon = 'iv' },
                { id = 'airway',  icon = 'lungs' },
                { id = 'ortho',   icon = 'splint' },
                { id = 'meds',    icon = 'pill' },
            },
            items = {   -- item = Config.Items key, max = how many one medic may take per shift
                { item = 'bandage',         category = 'wound',  max = 12 },
                { item = 'gauze',           category = 'wound',  max = 12 },
                { item = 'dressing',        category = 'wound',  max = 8 },
                { item = 'burn_dressing',   category = 'wound',  max = 6 },
                { item = 'tourniquet',      category = 'wound',  max = 4 },
                { item = 'iodine',          category = 'wound',  max = 8 },
                { item = 'ice_pack',        category = 'wound',  max = 4 },
                { item = 'foil_blanket',    category = 'wound',  max = 4 },
                { item = 'saline_bag',      category = 'fluids', max = 6 },
                { item = 'iv_kit',          category = 'fluids', max = 6 },
                { item = 'saline',          category = 'fluids', max = 6 },
                { item = 'txa',             category = 'fluids', max = 3 },
                { item = 'empty_blood_bag', category = 'fluids', max = 2 },   -- blood: 'Bag a unit' needs one (Config.Blood.Bank.needEmptyBag)
                { item = 'oxygen_mask',     category = 'airway', max = 3 },
                { item = 'bvm',             category = 'airway', max = 1 },
                { item = 'decomp_needle',   category = 'airway', max = 2 },
                { item = 'splint',          category = 'ortho',  max = 4 },
                { item = 'cervical_collar', category = 'ortho',  max = 3 },
                { item = 'pelvic_binder',   category = 'ortho',  max = 2 },
                { item = 'painkillers',     category = 'meds',   max = 6 },
                { item = 'naloxone',        category = 'meds',   max = 2 },
            },
            maxPerTake = 10,     -- most items one click can take
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BILLING (optional)
    -- ═══════════════════════════════════════════════════════════════════════

    Billing = {
        enabled   = false,
        transport = 250,         -- charged to a PLAYER patient taken by ambulance and placed in a hospital bed / on a table
        reason    = 'Ambulance transport',
    },
}
