-- ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗      █████╗ ████████╗██╗
-- ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔══██╗╚══██╔══╝██║
-- ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     ███████║   ██║   ██║
-- ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ██╔══██║   ██║   ██║
-- ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗██║  ██║   ██║   ██║
-- ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝
--  ██████╗ ███╗   ██╗
-- ██╔═══██╗████╗  ██║
-- ██║   ██║██╔██╗ ██║
-- ██║   ██║██║╚██╗██║
-- ╚██████╔╝██║ ╚████║
--  ╚═════╝ ╚═╝  ╚═══╝

--[[
    How mechanics physically fit each part on a work order.

    type
      'carry'  pick the part up at the rack, carry it to the car, fit it
      'tool'   pick up a tool (wrench, sponge, laptop...) and work at the car
      'spray'  spray can; the car must be inside a paint booth when the shop has booths
      'jacks'  the car goes up on axle stands first, then the mechanic works under it
      'wheels' car on stands, then each wheel is carried and bolted on separately
      'hoist'  the engine is pushed over on an engine hoist and lowered in (front or rear engine detected)

    point      'front' | 'front-left' | 'front-right' | 'rear' | 'rear-left' | 'rear-right' | 'left' | 'right'
    offset     extra offset from that point in vehicle space (x = right, y = forward, z = up)
    prop       model held while carrying, attach = { bone, x, y, z, rx, ry, rz }
    carryAnim  animation while carrying (nil = hold in hand only). Always played upper-body only, so you can walk.
    run        true = you can sprint while carrying it (light parts), false = walk only (heavy parts)

    Prop sitting wrong in the hands? Run /carryadjust <part id> (admins) in game: it hands you the part,
    arrows / PageUp / PageDown move it, hold Shift to rotate, G switches object, Enter copies the attach line.
    work       animation while fitting, time in ms
    sound      Config.Install.Sounds key played to everyone nearby while fitting
    pile       which rack on the shop the part comes from (config.shops.lua stockpiles)
]]

Config.Install = {
    UseJacks         = true,         -- brakes / gearbox / suspension / wheels lift the car on stands
    LiftHeight       = 0.32,         -- metres the car rises on the stands
    LiftTime         = 1800,
    AllowRunCarrying = false,        -- default for parts without their own run = true / false
    SoundRange       = 22.0,         -- metres other players hear install sounds
    HelpText         = true,         -- show "what to do next" in the job tracker
    AdvancedClasses  = {             -- classes that use jacks / hoist / per-wheel installs (others use simple installs)
        [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
        [9] = true, [12] = true, [18] = true, [20] = true,
    },

    Sounds = {
        jacks    = { file = 'nayzeee-tuning-jacks',          volume = 0.35 },
        socket   = { file = 'nayzeee-tuning-socket_wrench',  volume = 0.40 },
        ratchet  = { file = 'nayzeee-tuning-ratchet_wrench', volume = 0.30 },
        air      = { file = 'nayzeee-tuning-air_wrench',     volume = 0.18 },
        crane    = { file = 'nayzeee-tuning-engine_crane',   volume = 0.35 },
        paint    = { file = 'nayzeee-tuning-painting',       volume = 0.35 },
        clean    = { file = 'nayzeee-tuning-cleaning',       volume = 0.30 },
        tighten  = { file = 'nayzeee-tuning-wrench_tighten', volume = 0.40 },
    },

    -- axle stands
    Jacks = {
        prop      = 'xs_prop_x18_axel_stand_01a',
        attach    = { 28422, 0.07, -0.44, -0.1, -80.0, 20.0, 0.0 },
        attach2   = { 60309, 0.0, -0.44, 0.275, -120.0, -20.0, 0.0 },
        carryAnim = { 'anim@heists@box_carry@', 'idle' },
        run       = false,
        placeAt   = 'front-left',
        placeOffset = vec3(0.1, -0.6, 0.0),
        placeAnim = { 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer' },
        placeTime = 3000,
        pile      = 'jacks',
    },

    -- engine hoist
    Hoist = {
        prop      = 'prop_engine_hoist',
        attach    = { 0, 0.0, 1.05, -0.98, 0.0, 0.0, 180.0 },   -- bone 0 = the ped's root: the hoist rolls in front of you
        part      = 'prop_car_engine_01',
        partOffset = { -0.1, -1.6, 1.4, 0.0, 0.0, 0.0 },        -- engine hanging from the boom (relative to the hoist)
        pushAnim  = { 'missfinale_c2ig_11', 'pushcar_offcliff_m' }, -- arms only, the legs walk
        work      = { 'mini@repair', 'fixing_a_ped' },
        time      = 7000,
        pile      = 'engine',
        sound     = 'crane',
    },

    -- under-car work position used by 'jacks' installs
    UnderCar = { anim = { 'amb@world_human_vehicle_mechanic@male@base', 'base' } },
}

-- reusable part definitions (fix one here and every part using it follows)
local BOX_CARRY = { 'anim@heists@box_carry@', 'idle' }
local inArms   = { 60309, 0.025, 0.08, 0.255, -145.0, 290.0, 0.0 }          -- held in front with both hands
local box      = { prop = 'prop_cs_cardbox_01', attach = inArms, carryAnim = BOX_CARRY, run = true }
local panel    = { prop = 'prop_car_door_01', attach = { 60309, 0.0, 0.22, 0.25, -150.0, 290.0, 0.0 }, carryAnim = BOX_CARRY, run = false }
local bumper   = { attach = { 60309, 0.0, 0.18, 0.28, -145.0, 290.0, 0.0 }, carryAnim = BOX_CARRY, run = false }
local wheel    = { attach = { 60309, -0.05, 0.16, 0.32, -130.0, -55.0, 150.0 }, carryAnim = BOX_CARRY, run = false }
local wrench   = { prop = 'prop_tool_wrench', attach = { 57005, 0.119, -0.072, -0.05, -90.0, 120.0, 12.0 }, run = true }
local laptop   = { prop = 'prop_cs_tablet', attach = { 60309, 0.03, 0.002, 0.0, 10.0, 160.0, 0.0 }, run = true }
local spray    = { prop = 'prop_cs_spray_can', attach = { 57005, 0.119, -0.072, -0.05, -90.0, 120.0, 12.0 }, run = true }
local plate    = { prop = 'p_num_plate_01', attach = { 57005, 0.119, -0.072, -0.05, -90.0, 120.0, 12.0 }, run = true }
local mechWork = { 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer' }
local hoodWork = { 'mini@repair', 'fixing_a_ped' }
local tablet   = { 'amb@world_human_seat_wall_tablet@female@base', 'base' }

local function carry(def, extra)
    local out = { type = 'carry', prop = def.prop, attach = def.attach, carryAnim = def.carryAnim, run = def.run }
    for k, v in pairs(extra) do out[k] = v end
    return out
end

local function tool(def, extra)
    local out = { type = 'tool', prop = def.prop, attach = def.attach, run = def.run }
    for k, v in pairs(extra) do out[k] = v end
    return out
end

local underFront = { point = 'front', offset = vec3(0.0, -0.1, 0.0), face = 'rear' }
local underRear  = { point = 'rear',  offset = vec3(0.4, 0.1, 0.0),  face = 'front' }

Config.InstallParts = {
    ------------------------------------------------------------------ body
    mod_0  = carry({ prop = 'imp_prop_impexp_spoiler_02a', attach = bumper.attach, carryAnim = BOX_CARRY, run = false },
                   { point = 'rear', offset = vec3(0.0, -0.1, 0.0), work = hoodWork, time = 5000, sound = 'socket', pile = 'body' }),
    mod_1  = carry({ prop = 'imp_prop_impexp_front_bumper_01a', attach = bumper.attach, carryAnim = BOX_CARRY, run = false },
                   { point = 'front', offset = vec3(0.0, 0.1, 0.0), work = mechWork, time = 5000, sound = 'socket', pile = 'body' }),
    mod_2  = carry({ prop = 'imp_prop_impexp_rear_bumper_02a', attach = bumper.attach, carryAnim = BOX_CARRY, run = false },
                   { point = 'rear', offset = vec3(0.0, -0.1, 0.0), work = mechWork, time = 5000, sound = 'socket', pile = 'body' }),
    mod_3  = carry(panel, { point = 'left', work = mechWork, time = 5000, sound = 'socket', pile = 'body' }),
    mod_4  = carry({ prop = 'imp_prop_impexp_exhaust_06', attach = { 60309, 0.0, 0.15, 0.25, -145.0, 290.0, 0.0 }, carryAnim = BOX_CARRY, run = false },
                   { point = 'rear', offset = vec3(0.0, -0.1, 0.0), work = mechWork, time = 5000, sound = 'socket', pile = 'exhaust' }),
    mod_5  = carry(box,   { point = 'left', work = hoodWork, time = 6000, sound = 'socket', pile = 'interior', doors = { 0 } }),
    mod_6  = carry(box,   { point = 'front', work = mechWork, time = 4000, sound = 'socket', pile = 'body' }),
    mod_7  = carry({ prop = 'prop_car_bonnet_02', attach = inArms, carryAnim = BOX_CARRY, run = false },
                   { point = 'front', offset = vec3(0.0, 0.1, 0.0), work = hoodWork, time = 5000, sound = 'socket', pile = 'body' }),
    mod_8  = carry(panel, { point = 'front-left', work = mechWork, time = 4500, sound = 'socket', pile = 'body' }),
    mod_9  = carry(panel, { point = 'front-right', work = mechWork, time = 4500, sound = 'socket', pile = 'body' }),
    mod_10 = carry(panel, { point = 'left', work = hoodWork, time = 5000, sound = 'socket', pile = 'body' }),
    mod_27 = carry(box,   { point = 'left', work = mechWork, time = 3500, sound = 'socket', pile = 'body' }),
    mod_42 = carry(panel, { point = 'rear-left', work = mechWork, time = 4000, sound = 'socket', pile = 'body' }),
    mod_43 = carry(box,   { point = 'rear-right', work = mechWork, time = 3000, sound = 'socket', pile = 'body' }),
    mod_44 = carry(box,   { point = 'right', work = mechWork, time = 3500, sound = 'socket', pile = 'body' }),
    mod_45 = carry(box,   { point = 'rear-left', work = mechWork, time = 4000, sound = 'socket', pile = 'body' }),
    mod_46 = carry(panel, { point = 'right', work = mechWork, time = 4000, sound = 'socket', pile = 'body' }),
    mod_37 = carry(box,   { point = 'rear', work = hoodWork, time = 4000, sound = 'socket', pile = 'body', doors = { 5 } }),
    mod_36 = tool(laptop, { point = 'rear', work = hoodWork, time = 4000, sound = 'socket', pile = 'electronics', doors = { 5 } }),
    mod_38 = { type = 'jacks', work = { underFront, underRear }, time = 6000, sound = 'ratchet', pile = 'jacks' },
    mod_39 = tool(wrench, { point = 'front', work = hoodWork, time = 5000, sound = 'ratchet', pile = 'engine', doors = { 4 }, engineBay = true }),
    mod_40 = carry(box,   { point = 'front', work = hoodWork, time = 4000, sound = 'socket', pile = 'engine', doors = { 4 }, engineBay = true }),
    mod_41 = tool(wrench, { point = 'front', work = hoodWork, time = 4000, sound = 'ratchet', pile = 'engine', doors = { 4 }, engineBay = true }),
    mod_35 = carry(box,   { point = 'left', work = hoodWork, time = 3000, sound = 'socket', pile = 'interior', doors = { 0 } }),

    ------------------------------------------------------------------ interior
    mod_28 = carry(box,   { point = 'left', work = hoodWork, time = 3000, sound = 'socket', pile = 'interior', doors = { 0 } }),
    mod_29 = carry(box,   { point = 'left', work = hoodWork, time = 5000, sound = 'socket', pile = 'interior', doors = { 0 } }),
    mod_30 = carry(box,   { point = 'left', work = hoodWork, time = 3500, sound = 'socket', pile = 'interior', doors = { 0 } }),
    mod_31 = tool(laptop, { point = 'left', work = hoodWork, time = 3500, sound = 'socket', pile = 'electronics', doors = { 0 } }),
    mod_32 = carry(box,   { point = 'left', work = hoodWork, time = 5000, sound = 'socket', pile = 'interior', doors = { 0 } }),
    mod_33 = carry(box,   { point = 'left', work = hoodWork, time = 3500, sound = 'socket', pile = 'interior', doors = { 0 } }),
    mod_34 = carry(box,   { point = 'left', work = hoodWork, time = 3000, sound = 'socket', pile = 'interior', doors = { 0 } }),
    interiorColor  = tool(spray, { point = 'left', work = { 'amb@world_human_maid_clean@', 'base' }, time = 4000, sound = 'paint', pile = 'paint', doors = { 0 } }),
    dashboardColor = tool(spray, { point = 'left', work = { 'amb@world_human_maid_clean@', 'base' }, time = 4000, sound = 'paint', pile = 'paint', doors = { 0 } }),

    ------------------------------------------------------------------ paint (sprayed from both sides, inside the booth)
    color1     = { type = 'spray', prop = spray.prop, attach = spray.attach, points = { 'front-left', 'rear-right' }, time = 4500, sound = 'paint', pile = 'paint',
                   work = { 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_spraybottle_stand_spraying_01_inspector' } },
    color2     = { type = 'spray', prop = spray.prop, attach = spray.attach, points = { 'front-right', 'rear-left' }, time = 4000, sound = 'paint', pile = 'paint',
                   work = { 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_spraybottle_stand_spraying_01_inspector' } },
    pearl      = { type = 'spray', prop = spray.prop, attach = spray.attach, points = { 'front-left' }, time = 4000, sound = 'paint', pile = 'paint',
                   work = { 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_spraybottle_stand_spraying_01_inspector' } },
    livery     = { type = 'spray', prop = spray.prop, attach = spray.attach, points = { 'left', 'right' }, time = 5000, sound = 'paint', pile = 'paint',
                   work = { 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_spraybottle_stand_spraying_01_inspector' } },
    roofLivery = { type = 'spray', prop = spray.prop, attach = spray.attach, points = { 'left' }, time = 4000, sound = 'paint', pile = 'paint',
                   work = { 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_spraybottle_stand_spraying_01_inspector' } },
    wheelColor = { type = 'spray', prop = spray.prop, attach = spray.attach, points = { 'front-left', 'rear-right' }, time = 3500, sound = 'paint', pile = 'paint', booth = false,
                   work = { 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_spraybottle_stand_spraying_01_inspector' } },

    ------------------------------------------------------------------ wheels (each wheel carried separately, car on stands)
    wheels      = { type = 'wheels', prop = 'prop_wheel_rim_01', attach = wheel.attach, carryAnim = BOX_CARRY, run = false, time = 5000, sound = 'air', pile = 'wheels' },
    rearWheels  = { type = 'wheels', prop = 'prop_wheel_rim_01', attach = wheel.attach, carryAnim = BOX_CARRY, run = false, time = 5000, sound = 'air', pile = 'wheels', only = { 'wheel_lr' } },
    customTires = { type = 'wheels', prop = 'prop_wheel_tyre', attach = wheel.attach, carryAnim = BOX_CARRY, run = false, time = 4500, sound = 'air', pile = 'wheels' },
    tyres       = { type = 'wheels', prop = 'prop_wheel_tyre', attach = wheel.attach, carryAnim = BOX_CARRY, run = false, time = 4500, sound = 'air', pile = 'wheels' },
    bulletproof = { type = 'wheels', prop = 'prop_wheel_tyre', attach = wheel.attach, carryAnim = BOX_CARRY, run = false, time = 4500, sound = 'air', pile = 'wheels' },
    driftTyres  = { type = 'wheels', prop = 'prop_wheel_tyre', attach = wheel.attach, carryAnim = BOX_CARRY, run = false, time = 4500, sound = 'air', pile = 'wheels' },
    wheelSize   = { type = 'jacks', work = { { point = 'front-left' }, { point = 'rear-right' } }, time = 4000, sound = 'air', pile = 'jacks' },
    wheelWidth  = { type = 'jacks', work = { { point = 'front-left' }, { point = 'rear-right' } }, time = 4000, sound = 'air', pile = 'jacks' },
    smoke       = tool(wrench, { point = 'rear-left', work = mechWork, time = 3500, sound = 'tighten', pile = 'wheels' }),

    ------------------------------------------------------------------ chassis (on stands)
    mod_12     = { type = 'jacks', work = { underRear, underFront }, time = 6000, sound = 'ratchet', pile = 'jacks' },
    mod_13     = { type = 'jacks', work = { underFront }, time = 7000, sound = 'ratchet', pile = 'jacks' },
    mod_15     = { type = 'jacks', work = { underRear, underFront }, time = 6000, sound = 'ratchet', pile = 'jacks' },
    stance     = { type = 'jacks', work = { { point = 'front-left' }, { point = 'rear-right' } }, time = 5000, sound = 'ratchet', pile = 'jacks' },
    height     = { type = 'jacks', work = { underRear, underFront }, time = 5000, sound = 'ratchet', pile = 'jacks' },
    airride    = { type = 'jacks', work = { underRear, underFront }, time = 7000, sound = 'ratchet', pile = 'jacks' },
    ceramic    = { type = 'jacks', work = { { point = 'front-left' }, { point = 'rear-right' } }, time = 6000, sound = 'ratchet', pile = 'jacks' },
    drivetrain = { type = 'jacks', work = { underFront, underRear }, time = 8000, sound = 'ratchet', pile = 'jacks' },
    gearbox    = { type = 'jacks', work = { underFront }, time = 8000, sound = 'ratchet', pile = 'jacks' },
    driftKit   = { type = 'jacks', work = { underFront }, time = 6000, sound = 'ratchet', pile = 'jacks' },

    ------------------------------------------------------------------ engine bay
    mod_11     = { type = 'hoist' },
    engineSwap = { type = 'hoist' },
    mod_18     = carry(box, { point = 'front', work = hoodWork, time = 6000, sound = 'ratchet', pile = 'engine', doors = { 4 }, engineBay = true }),
    mod_16     = carry(panel, { point = 'left', work = mechWork, time = 6000, sound = 'socket', pile = 'body' }),
    nitrous    = carry({ prop = 'prop_gascyl_01a', attach = { 60309, 0.025, 0.1, 0.255, -145.0, 290.0, 0.0 }, carryAnim = BOX_CARRY, run = false },
                   { point = 'rear', work = hoodWork, time = 6000, sound = 'ratchet', pile = 'engine', doors = { 5 } }),
    sound      = tool(wrench, { point = 'rear', work = mechWork, time = 4500, sound = 'socket', pile = 'exhaust' }),
    service    = tool(wrench, { point = 'front', work = hoodWork, time = 7000, sound = 'ratchet', pile = 'engine', doors = { 4 }, engineBay = true }),
    repair     = tool(wrench, { point = 'front', work = hoodWork, time = 5000, sound = 'socket', pile = 'repair', doors = { 4 }, engineBay = true }),
    clean      = tool({ prop = 'prop_sponge_01', attach = { 28422, 0.0, 0.0, -0.01, 90.0, 0.0, 0.0 }, run = true },
                   { point = 'front-left', offset = vec3(0.1, -0.75, 0.0), work = { 'amb@world_human_maid_clean@', 'base' }, time = 4500, sound = 'clean', pile = 'repair' }),

    ------------------------------------------------------------------ electronics
    ecu        = tool(laptop, { point = 'left', work = tablet, time = 6000, sound = 'tighten', pile = 'electronics', doors = { 0 } }),
    antilag    = tool(laptop, { point = 'front', work = hoodWork, time = 5000, sound = 'socket', pile = 'electronics', doors = { 4 }, engineBay = true }),
    launch     = tool(laptop, { point = 'left', work = tablet, time = 4000, sound = 'tighten', pile = 'electronics', doors = { 0 } }),
    locator    = tool(laptop, { point = 'left', work = hoodWork, time = 4000, sound = 'tighten', pile = 'electronics', doors = { 0 } }),
    mod_22     = carry(box, { point = 'front', work = mechWork, time = 4000, sound = 'socket', pile = 'electronics' }),
    xenonColor = carry(box, { point = 'front', work = mechWork, time = 3500, sound = 'socket', pile = 'electronics' }),
    neon       = carry({ prop = 'xs_prop_arena_lights_tube_l_a', attach = { 57005, 0.12, 0.0, -0.02, 0.0, 90.0, 0.0 }, run = true },
                   { point = 'left', offset = vec3(0.2, 0.0, 0.0), work = mechWork, time = 5000, sound = 'socket', pile = 'electronics' }),
    neonPattern= tool(laptop, { point = 'left', work = tablet, time = 3000, sound = 'tighten', pile = 'electronics', doors = { 0 } }),
    mod_14     = tool(wrench, { point = 'front', work = hoodWork, time = 3500, sound = 'socket', pile = 'electronics', doors = { 4 }, engineBay = true }),

    ------------------------------------------------------------------ plate / glass / misc
    plateText  = carry(plate, { point = 'rear', offset = vec3(0.0, -0.15, 0.0), work = mechWork, time = 3500, sound = 'tighten', pile = 'body' }),
    plateIndex = carry(plate, { point = 'rear', offset = vec3(0.0, -0.15, 0.0), work = mechWork, time = 3500, sound = 'tighten', pile = 'body' }),
    mod_25     = carry(plate, { point = 'rear', offset = vec3(0.0, -0.15, 0.0), work = mechWork, time = 3500, sound = 'tighten', pile = 'body' }),
    mod_26     = carry(plate, { point = 'front', offset = vec3(0.0, 0.15, 0.0), work = mechWork, time = 3500, sound = 'tighten', pile = 'body' }),
    tint       = tool(spray, { point = 'left', work = { 'amb@world_human_maid_clean@', 'base' }, time = 5000, sound = 'clean', pile = 'interior' }),
    extras     = tool(wrench, { point = 'left', work = mechWork, time = 3500, sound = 'socket', pile = 'body' }),
}

-- anything not listed above
Config.InstallFallback = tool(wrench, { point = 'left', work = mechWork, time = 4000, sound = 'socket', pile = 'body' })
