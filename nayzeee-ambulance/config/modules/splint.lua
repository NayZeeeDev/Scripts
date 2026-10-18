--[[
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝

    AMBULANCE SYSTEM - SPLINTS, CRUTCHES & WHEELCHAIR
    Discord: discord.gg/nayzeeedev

    Field splinting of broken arms and legs (lay the splint along the limb, pad
    the bony points and shape it to the limb, strap it and check circulation /
    motor / sensation), crutches anyone can walk with, and a folding wheelchair
    you drive with W A S D, that others can push and medics can seat patients in.

    Items are named in config/items.lua (Config.Items.*). Here they are referred
    to by their KEY ('splint', 'crutches', 'wheelchair'), never by the inventory
    name. Props are Config.Props keys (config/props.lua).
    Minigame keys use JavaScript KeyboardEvent.code names ('KeyQ', 'Space'...).
    In-world keys use GTA control ids (https://docs.fivem.net/docs/game-references/controls/).
]]

if not NAYZEEE_LOCK_OK then return end

Config = Config or {}

Config.Splint = {

    -- ═══════════════════════════════════════════════════════════════════════
    -- SPLINTING (NZA.Proc 'splint') - 1 lay it, 2 pad & shape, 3 strap + CMS check
    -- ═══════════════════════════════════════════════════════════════════════

    Splint = {
        enabled   = true,
        perm      = 'splint',      -- permission needed (department grades grant it)
        item      = 'splint',      -- item key used up on success
        minTime   = 14,            -- seconds; a finish faster than this is rejected (anti-cheat)
        maxTime   = 480,           -- seconds before the session expires
        easyTime  = 8,             -- progress bar length in easy mode
        maxDist   = 3.0,           -- metres between the medic and the patient
        states    = { 'alive', 'wounded' },  -- patient states that can be splinted
        regions   = {              -- regions that take a splint, and which device
            l_upper_arm = 'arm', l_lower_arm = 'arm', r_upper_arm = 'arm', r_lower_arm = 'arm',
            l_upper_leg = 'leg', l_lower_leg = 'leg', r_upper_leg = 'leg', r_lower_leg = 'leg',
        },

        -- Device sizes (metres) - the splint is drawn to scale over the limb
        device = {
            leg = { width = 0.150, depth = 0.070, wall = 0.010, model = 'CS-76' },   -- padded leg trough with foot plate
            arm = { width = 0.105, depth = 0.050, wall = 0.008, model = 'CS-40' },   -- padded arm trough with palm roll
        },
        limbRadius = { leg = 0.055, thigh = 0.075, arm = 0.040, upperArm = 0.048 },  -- used to show the limb lying in the splint

        tolerance      = 0.035,    -- metres: how close each splint end must sit to its joint
        angleTolerance = 8.0,      -- degrees the splint may be turned off the limb axis and still set
        lockHold       = 0.7,      -- seconds both ends must stay on their joints before the splint sets (Space does it at once)
        rotateSpeed    = 55,       -- degrees per second while Q / E is held
        nudgeSpeed     = 0.20,     -- metres per second while an arrow key is held
        fine           = 0.22,     -- Shift multiplier for rotate / nudge / drag
        shapePoints    = { leg = 6, arm = 5 },  -- points along the splint you shape by hand
        shapeSeconds   = 1.15,     -- seconds of holding a point from loose to fully shaped
        shapeClick     = 0.18,     -- share added by a single click
        shapeZone      = { 0.72, 1.0 },  -- a point counts as shaped inside this band; above 1.0 = pressure point
        strapZone      = { 0.55, 0.82 }, -- good strap tension band (0..1)
        strapTight     = 0.88,     -- above this a strap cuts off circulation (the CMS check finds it)
        strapPeriod    = 1.7,      -- seconds for the tension needle to sweep up and back
        requireDressedOpen = false, -- true: open fractures must be dressed (suture / dressing) before splinting
        painRelief     = 12,       -- extra pain points taken off the fracture at a perfect score
        minScore       = 0,        -- a score below this fails the splint (item kept, nothing applied)

        -- Camera: straight down over the limb when it lies flat, from the side when the limb is upright
        camera = {
            fov       = 50.0,      -- field of view (degrees) - the NUI draws the splint with the same lens
            fill      = 0.38,      -- share of the screen height the limb takes
            minHeight = 0.6, maxHeight = 3.2,     -- mouse wheel zoom limits
            upright   = { dist = 1.35, pitch = 8.0, fov = 44.0 },   -- used for an upright limb
        },
        -- medic pose while splinting (nil = the core kneel)
        anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        -- a standing player patient sits down on the ground for the splint (false = stay as they are)
        patientPose = {
            m = { dict = 'amb@world_human_picnic@male@base', clip = 'base' },
            f = { dict = 'amb@world_human_picnic@female@base', clip = 'base' },
        },

        keys = {
            rotateLeft  = 'KeyQ',
            rotateRight = 'KeyE',
            reset       = 'KeyX',
            set         = 'Space',  -- set the splint when both ends sit on their joints / cinch a strap
        },

        -- Distal circulation / motor / sensation check (step 3): the bone clicked for the check
        cmsBones = {
            l_upper_leg = 2108,  l_lower_leg = 2108,  r_upper_leg = 20781, r_lower_leg = 20781,
            l_upper_arm = 18905, l_lower_arm = 18905, r_upper_arm = 57005, r_lower_arm = 57005,
        },
        shockSys = 85,             -- systolic BP below this = weak distal pulse (the patient is in shock)

        removePerm    = 'splint',  -- permission to take a splint off
        removeReturns = false,     -- taking a splint off gives the item back
        autoRemoveHealed = true,   -- the splint comes off by itself once no fracture is left under it
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- WORN SPLINT PROPS (every client draws them from the patient state bag)
    -- One or more pieces per region: { prop = Config.Props key, bone = ped bone id,
    -- pos = offset along the bone (X runs down the limb), rot = rotation }.
    -- If the open side of the channel faces the wrong way, flip rot X (-90 ↔ 90).
    -- ═══════════════════════════════════════════════════════════════════════

    Props = {
        enabled = true,
        range   = 45.0,            -- metres within which worn splints / crutches are drawn
        attach  = {
            l_lower_leg = { { prop = 'splint_leg', bone = 63931, pos = vec3(0.10, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) } },
            r_lower_leg = { { prop = 'splint_leg', bone = 36864, pos = vec3(0.10, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) } },
            l_upper_leg = { { prop = 'splint_leg', bone = 63931, pos = vec3(0.10, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) },   -- long leg: lower splint +
                            { prop = 'splint_arm', bone = 58271, pos = vec3(0.22, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) } }, -- thigh trough
            r_upper_leg = { { prop = 'splint_leg', bone = 36864, pos = vec3(0.10, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) },
                            { prop = 'splint_arm', bone = 51826, pos = vec3(0.22, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) } },
            l_lower_arm = { { prop = 'splint_arm', bone = 61163, pos = vec3(0.12, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) } },
            r_lower_arm = { { prop = 'splint_arm', bone = 28252, pos = vec3(0.12, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) } },
            l_upper_arm = { { prop = 'splint_arm', bone = 45509, pos = vec3(0.14, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) } },
            r_upper_arm = { { prop = 'splint_arm', bone = 40269, pos = vec3(0.14, 0.0, 0.0), rot = vec3(-90.0, 0.0, 0.0) } },
        },
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- WALKING WITH A SPLINTED LEG (local player; the core already blocks sprint / jump
    -- with any leg fracture and plays the injured walk)
    -- ═══════════════════════════════════════════════════════════════════════

    Effects = {
        enabled      = true,
        maxMoveBlend = 1.0,        -- 1.0 = walk only, 2.0 = jog, 3.0 = sprint
        moveRate     = 0.88,       -- walk animation speed (1.0 = normal)
        legClipset   = false,      -- a walk clipset for a splinted leg, false = keep the core injured walk
        armNoAim     = false,      -- true: no aiming with a splinted arm
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- CRUTCHES (anyone with the item)
    -- ═══════════════════════════════════════════════════════════════════════

    Crutches = {
        enabled   = true,
        item      = 'crutches',
        prop      = 'crutch',      -- Config.Props key (fallback: Config.PropFallbacks.crutch)
        clipset   = 'move_lester_CaneUp',   -- walk style on crutches (a planted, weight-bearing step)
        upper     = false,         -- optional upper-body loop { dict, clip } played while walking (false = none)
        moveRate  = 0.86,          -- walk animation speed
        maxMoveBlend = 1.0,        -- 1.0 = no jogging / sprinting on crutches
        key       = '',            -- default key to pick up / put away (players can rebind; '' = unbound)
        command   = 'crutches',    -- chat command that does the same (false = none)
        right = { bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },   -- PH_R_Hand
        left  = { bone = 60309, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },   -- PH_L_Hand
        blockControls = { 21, 22, 24, 25, 36, 37, 44, 140, 141, 142, 143, 257, 263, 264 }, -- sprint, jump, attack, aim, duck, weapon wheel, cover, melee
        hideInVehicle = true,      -- crutches disappear while seated in a vehicle
        checkEvery    = 15,        -- seconds between server checks that you still carry the item
        give          = true,      -- medics get 'Give crutches' on player patients
        givePerm      = 'splint',  -- permission for that option
        autoEquip     = true,      -- the patient starts walking with them straight away
        hud           = true,      -- status card while on crutches (gait, steps, which leg stays off the ground)
        stride        = 0.62,      -- metres per crutch step (step counter on the card)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- WHEELCHAIR
    -- ═══════════════════════════════════════════════════════════════════════

    Wheelchair = {
        enabled      = true,
        item         = 'wheelchair',
        prop         = 'wheelchair',  -- Config.Props key (native prop_wheelchair_01)
        maxPerPlayer = 1,             -- unfolded chairs one player may have out at once
        placeDistance = 1.1,          -- metres in front of you the chair unfolds
        seatPerm     = 'transport',   -- permission to seat / take out patients
        foldOwnerOnly = false,        -- true: only the player who unfolded it can fold it
        abandonMinutes = 20,          -- an empty chair whose owner left the server is removed after this
        states       = { 'alive' },   -- patient states that can sit in a chair

        -- the person sitting (offsets on the chair)
        seat = {
            pos  = vec3(0.0, 0.0, 0.4),
            rot  = vec3(0.0, 0.0, 180.0),
            anim = { dict = 'missfinale_c2leadinoutfin_c_int', clip = '_leadin_loop2_lester', flag = 1 },
        },
        -- the person pushing (the chair is held at the right hand)
        push = {
            bone = 28422,
            pos  = vec3(0.0, -0.3, -0.73),
            rot  = vec3(195.0, 180.0, 180.0),
            anim = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 51 },
            maxMoveBlend = 1.0,       -- walk while pushing
        },
        place = { dict = 'pickup_object', clip = 'putdown_low', ms = 900 },  -- unfold / fold animation

        -- driving yourself
        drive = {
            maxSpeed     = 1.9,       -- m/s forward on flat ground
            reverseSpeed = 0.8,       -- m/s backwards
            accel        = 1.3,       -- m/s² when pushing the rims
            brake        = 3.4,       -- m/s² when pulling the other way
            friction     = 0.9,       -- m/s² rolling resistance with no input
            turnRate     = 78.0,      -- degrees per second (on the spot)
            turnAtSpeed  = 0.65,      -- turn rate multiplier at full speed
            slopeFactor  = 0.6,       -- how much slopes speed you up / slow you down (0 = flat world)
            downhillMax  = 3.2,       -- m/s cap when rolling downhill
            maxStep      = 0.16,      -- metres up the chair can roll (curbs higher than this block you)
            maxDrop      = 0.42,      -- metres down it can roll off (higher drops block you)
            maxSlope     = 24.0,      -- degrees; steeper ground blocks you going up
            radius       = 0.45,      -- collision radius around the chair
        },

        keys = {
            stand = { control = 23, label = 'F' },  -- stand up / get out
            letGo = { control = 47, label = 'G' },  -- stop pushing
        },
        hud = true,                   -- card while driving or pushing (speed, wheel drive, grade, distance)
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- PATIENT MENU (third-eye / target options)
    -- ═══════════════════════════════════════════════════════════════════════

    Interact = {
        distance = 2.2,               -- metres from the patient for the options to show
        splint   = true,              -- 'Splint the fracture' (order 44)
        remove   = true,              -- 'Take the splint off'
        crutches = true,              -- 'Give crutches'
        chair    = true,              -- 'Seat in wheelchair' / 'Help out of the chair'
        chairRange = 6.0,             -- how far the nearest free wheelchair may be from the patient
        icons = {                     -- NAYZEEE icon names (target scripts get the matching Font Awesome icon)
            splint = 'splint', remove = 'splint', crutches = 'crutch', chair = 'wheelchair',
            sit = 'seat', push = 'hand', fold = 'box', out = 'walk',
        },
    },

    Radial = {
        enabled = true,               -- 'Splint the fracture' and 'Wheelchair' under Patient in the EMS radial
        range   = 3.0,                -- nearest patient within this many metres
    },

    -- ═══════════════════════════════════════════════════════════════════════
    -- BILLING (charged to player patients by the medic who did it; 0 = free)
    -- ═══════════════════════════════════════════════════════════════════════

    Billing = {
        splint   = 180,
        crutches = 60,                -- 'Give crutches'
        chair    = 0,                 -- seating a patient in a wheelchair
    },
}
