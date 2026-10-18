--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - HOSPITALS, DEPARTMENTS & STAFF
    Discord: discord.gg/nayzeeedev

    Hospitals are built in game, never in this file:
      /nzadmin (Config.Commands.admin) opens the EMS Manager. Create a department
      (= one hospital / organisation), link it to a framework job or keep it
      standalone, set its grades and permissions, then place its positions
      (duty, lockers, stash, garage, beds, X-ray table...) where you stand.
    Department bosses (permission 'manage') open the same manager from their
    boss menu, limited to their own roster, grades, outfits, garage and funds.

    What lives here: the defaults a NEW department starts with, the placement
    controls, duty / paycheck rules, the supply cabinet, garages, beds and blips.
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Hospital = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- NEW DEPARTMENTS (what the "New department" button starts with)
    -- ═══════════════════════════════════════════════════════════════════════

    newDepartment = {
        job         = nil,        -- framework job to link (nil = standalone; members are hired in the manager)
        easy        = nil,        -- easy mode; nil = Config.EasyMode.default
        blip        = { enabled = true, sprite = 61, colour = 1, scale = 0.85, shortRange = true },
        -- perms = nil copies Config.DefaultPerms for that level (config/config.lua)
        grades = {
            { level = 0, name = 'trainee',   label = 'Trainee',           salary = 50,  perms = nil },
            { level = 1, name = 'emt',       label = 'EMT',               salary = 75,  perms = nil },
            { level = 2, name = 'paramedic', label = 'Paramedic',         salary = 100, perms = nil },
            { level = 3, name = 'doctor',    label = 'Doctor',            salary = 150, perms = nil },
            { level = 4, name = 'chief',     label = 'Chief of Medicine', salary = 200, perms = nil },
        },
        vehicles = {
            -- type 'car' spawns at Vehicle Garage points, 'heli' at Helipad points
            { model = 'ambulance', label = 'Ambulance',     type = 'car',  minGrade = 0, livery = 0 },
            { model = 'polmav',    label = 'Air Ambulance', type = 'heli', minGrade = 3, livery = 1 },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- LIMITS (sanity caps the server enforces on what the manager saves)
    -- ═══════════════════════════════════════════════════════════════════════

    limits = {
        departments = 20,         -- departments on the server
        grades      = 20,         -- grades per department
        outfits     = 40,         -- outfits per department
        vehicles    = 40,         -- garage vehicles per department
        points      = 400,        -- placed positions per department
        staff       = 500,        -- hired members per department
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PLACEMENT MODE (EMS Manager → Positions → Add / Re-place)
    -- ═══════════════════════════════════════════════════════════════════════

    builder = {
        maxDistance  = 25.0,      -- metres from you a position may be placed
        rotateSpeed  = 90.0,      -- degrees per second while holding ← / →
        fastFactor   = 3.0,       -- Shift multiplies rotate / height speed
        fineFactor   = 0.2,       -- Alt multiplies rotate / height speed
        scrollStep   = 7.5,       -- degrees per mouse-wheel notch
        snapAngle    = 15.0,      -- G toggles snapping the heading to this step
        heightSpeed  = 0.5,       -- metres per second with Page Up / Page Down
        maxHeight    = 3.0,       -- how far a position may be lifted / lowered from the surface
        ghostAlpha   = 165,       -- 0-255 transparency of the ghost prop / vehicle
        markerColour = { 8, 175, 162 },   -- glowing sphere + beam for marker positions (teal)
        badColour    = { 229, 72, 77 },   -- the same marker while the spot is invalid (red)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- STAFF
    -- ═══════════════════════════════════════════════════════════════════════

    staff = {
        bossOutranks     = true,  -- bosses may only hire / promote / fire below their own grade
        syncFrameworkJob = true,  -- hiring into a linked department also sets the framework job (needs Bridge.SetJob)
        fireJob          = { name = 'unemployed', grade = 0 },  -- framework job set when firing from a linked department
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- DUTY
    -- ═══════════════════════════════════════════════════════════════════════

    duty = {
        radial       = false,     -- own "Toggle duty" entry in the EMS radial (the dispatch radial already has one)
        requirePoint = false,     -- true: the radial toggle only works near one of your department's duty points
        range        = 30.0,      -- metres for requirePoint
        offDutyCivvies = false,   -- going off duty puts your civilian clothes back on
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PAYCHECKS (frameworks pay their own jobs; this pays standalone departments)
    -- ═══════════════════════════════════════════════════════════════════════

    paycheck = {
        enabled        = true,
        interval       = 15,      -- minutes between payments to on-duty members
        standaloneOnly = true,    -- false = also pay members of departments linked to a framework job
        fromSociety    = false,   -- take the money out of the department's society account
        account        = 'bank',  -- 'bank' | 'cash'
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- LOCKERS (department outfits, saved in the manager from your current clothes)
    -- ═══════════════════════════════════════════════════════════════════════

    locker = {
        components = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 },  -- ped components an outfit stores (face 0 and hair 2 stay yours)
        props      = { 0, 1, 2, 6, 7 },                    -- hats, glasses, ears, watches, bracelets
        anim       = { dict = 'clothingtie', clip = 'try_tie_neutral_a', time = 1800 },  -- changing animation (false = none)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- STASH (shared department storage)
    -- ox_inventory, qb-inventory, qs, ps and lj stashes are used when running;
    -- every other inventory uses the built-in NAYZEEE storage window.
    -- ═══════════════════════════════════════════════════════════════════════

    stash = {
        slots      = 80,          -- default slots (per stash point; editable in the manager)
        weight     = 250000,      -- default max weight in grams
        ownStorage = true,        -- false: no stash at all when the inventory has no stash support
        maxStacks  = 150,         -- built-in storage: different stacks one stash may hold
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- SUPPLY CABINET (free supplies for on-duty staff, limited per shift)
    -- key = item key in config/items.lua · limit = how many one medic may take per shift
    -- ═══════════════════════════════════════════════════════════════════════

    storage = {
        shiftReset = true,        -- going off duty resets your taken counts
        shiftHours = 4,           -- ...and so does this many hours on duty
        items = {
            { key = 'bandage',         limit = 20 },
            { key = 'gauze',           limit = 20 },
            { key = 'tourniquet',      limit = 4 },
            { key = 'painkillers',     limit = 10 },
            { key = 'dressing',        limit = 10 },
            { key = 'burn_dressing',   limit = 6 },
            { key = 'suture_kit',      limit = 6 },
            { key = 'saline',          limit = 8 },
            { key = 'lidocaine',       limit = 6 },
            { key = 'iv_kit',          limit = 6 },
            { key = 'saline_bag',      limit = 6 },
            { key = 'splint',          limit = 4 },
            { key = 'cervical_collar', limit = 2 },
            { key = 'oxygen_mask',     limit = 2 },
            { key = 'morphine',        limit = 4, perm = 'meds' },   -- perm: only shown to grades with it
            { key = 'adrenaline',      limit = 4, perm = 'meds' },
            { key = 'txa',             limit = 4, perm = 'meds' },
            -- procedure kits (no other source in the resource; remove a line to hand them out elsewhere)
            { key = 'empty_blood_bag', limit = 4, perm = 'blood' },      -- blood donation (medic mode)
            { key = 'trauma_kit',      limit = 1, perm = 'iv' },         -- field resuscitation case (+ defib)
            { key = 'intubation_kit',  limit = 2, perm = 'airway' },
            { key = 'chest_drain_kit', limit = 2, perm = 'chestdrain' },
            { key = 'angio_kit',       limit = 2, perm = 'angio' },
            { key = 'contrast',        limit = 4, perm = 'angio' },
            { key = 'coil',            limit = 6, perm = 'angio' },
            { key = 'surgical_kit',    limit = 1, perm = 'surgery' },    -- bullet / fragment removal
            { key = 'graft_kit',       limit = 1, perm = 'graft' },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- GARAGES & HELIPADS
    -- ═══════════════════════════════════════════════════════════════════════

    garage = {
        platePrefix   = 'EMS',    -- plate = prefix + random digits (8 characters max)
        fuel          = 100.0,    -- fuel level of a fresh vehicle
        warp          = true,     -- put you in the driver seat
        clearRadius   = 3.5,      -- refuse to spawn when another vehicle is this close to the spawn point
        maxPerPlayer  = 2,        -- department vehicles one medic may have out (0 = unlimited)
        storeRadius   = 12.0,     -- how close to a garage / helipad point a vehicle must be to store it
        deleteOnDrop  = true,     -- remove a medic's vehicles when they leave the server
        heliModel     = 'polmav', -- ghost helicopter while placing a helipad with no heli in the garage yet
        carModel      = 'ambulance',
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- ELEVATORS (positions with the same "group" are linked floors)
    -- ═══════════════════════════════════════════════════════════════════════

    elevator = {
        fade = 450,               -- ms screen fade out / in
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BEDS (lie down to heal ×4, see Config.Physiology.healRate)
    -- ═══════════════════════════════════════════════════════════════════════

    bed = {
        dict      = 'anim@gangops@morgue@table@',   -- lying on the back
        clip      = 'body_search',
        zOffset   = 0.0,          -- lift the body above the placed point
        getUpKey  = 'X',          -- shown in the prompt; control 73 (INPUT_VEH_DUCK)
        exitSide  = 1.1,          -- metres to the side you stand up to
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- MAP BLIPS (per department in the manager; the swatches the manager offers)
    -- ═══════════════════════════════════════════════════════════════════════

    blips = {
        colours = {
            { id = 1,  hex = '#e03232' }, { id = 6,  hex = '#b82020' }, { id = 17, hex = '#f0a050' },
            { id = 5,  hex = '#eec64e' }, { id = 2,  hex = '#71cb71' }, { id = 25, hex = '#3c8c3c' },
            { id = 3,  hex = '#5db6e5' }, { id = 38, hex = '#2f5ed4' }, { id = 7,  hex = '#9a72cc' },
            { id = 8,  hex = '#f17fbd' }, { id = 0,  hex = '#f0f0f0' }, { id = 40, hex = '#4c4c4c' },
        },
        sprites = {
            { id = 61,  label = 'Hospital' },
            { id = 153, label = 'Medical' },
            { id = 43,  label = 'Helipad' },
            { id = 50,  label = 'Garage' },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- RATE LIMITS (per player)
    -- ═══════════════════════════════════════════════════════════════════════

    rates = {
        manager = 8,              -- manager actions per 4 s
        runtime = 6,              -- duty / locker / garage / storage actions per 4 s
    },
}
