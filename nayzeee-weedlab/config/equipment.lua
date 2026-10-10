--[[
    Placeable equipment, growing, lights, processing and the first person steps.

    Every model can be swapped. A model that isn't streamed falls back to `fallback`
    (or a cardboard box) and prints a warning, so nothing breaks.
    Offsets are relative to the station (x = right, y = forward / away from the player, z = up).
    The anchors match the custom props in stream/ (see tools/props/build_props.py).
]]

--[[ ─────────────────────── placeables ─────────────────────── ]]
Config.Equipment = {
    pot = {
        item = 'nzw_pot', label = 'Plastic Pot', model = 'nzw_pot', fallback = 'bkr_prop_weed_bucket_01a', level = 0, icon = 'pot',
        grow = true, footprint = 0.36,
        soilZ = 0.26, plantZ = 0.285, plantScale = 0.82, top = 0.32,
        cam = { offset = vec3(0.0, -0.95, 1.05), look = vec3(0.0, 0.0, 0.45), fov = 48 },
    },
    tent = {
        -- small grow tent with a built-in light and pot: faster but smaller plants
        item = 'nzw_growtent', label = 'Grow Tent', model = 'nzw_growtent', fallback = 'prop_cs_cardbox_01', level = 3, icon = 'tent',
        grow = true, footprint = 0.9, boost = 1.35, yieldMult = 0.75,
        soilZ = 0.23, plantZ = 0.255, plantScale = 0.62, top = 0.3,
        light = { offset = vec3(0.0, 0.0, 1.42), color = { 255, 238, 214 }, range = 2.2, intensity = 4.0 },
        cam = { offset = vec3(0.0, -0.98, 1.05), look = vec3(0.0, 0.0, 0.5), fov = 50 },
    },
    rack = {
        -- grow lights hang from this. Pots under it get the light's growth boost
        item = 'nzw_rack', label = 'Suspension Rack', model = 'nzw_suspension_rack', fallback = 'prop_worklight_03b', level = 1, icon = 'rack',
        overlap = true, footprint = 0.3,
        hang = vec3(0.0, 0.0, 1.86),
        area = { x = 0.85, y = 0.62 },        -- light covers this half-size box under the rack
        top = 2.3,
    },
    dryrack = {
        item = 'nzw_dryrack', label = 'Drying Rack', model = 'nzw_dryrack', fallback = 'bkr_prop_weed_drying_02a', level = 4, icon = 'rack',
        footprint = 0.7, top = 1.8,
        -- one unit hangs from each clip (front line, top to bottom, left to right)
        slots = {
            vec3(-0.5, -0.235, 1.63), vec3(-0.25, -0.235, 1.63), vec3(0.0, -0.235, 1.63), vec3(0.25, -0.235, 1.63), vec3(0.5, -0.235, 1.63),
            vec3(-0.5, -0.235, 1.31), vec3(-0.25, -0.235, 1.31), vec3(0.0, -0.235, 1.31), vec3(0.25, -0.235, 1.31), vec3(0.5, -0.235, 1.31),
            vec3(-0.5, -0.235, 0.99), vec3(-0.25, -0.235, 0.99), vec3(0.0, -0.235, 0.99), vec3(0.25, -0.235, 0.99), vec3(0.5, -0.235, 0.99),
        },
        cam = { offset = vec3(0.0, -1.55, 1.35), look = vec3(0.0, 0.0, 1.3), fov = 50 },
    },
    packstation = {
        -- tray on the left, packaging in the middle, the hatch on the right
        item = 'nzw_packstation', label = 'Packaging Station', model = 'nzw_packstation', fallback = 'bkr_prop_weed_table_01a', level = 0, icon = 'box',
        footprint = 0.8, top = 0.92,
        hatch = { model = 'nzw_packstation_hatch', offset = vec3(0.5, 0.17, 1.086), open = -100.0 },  -- origin on the back hinge
        anchors = {
            tray = vec3(-0.52, -0.02, 0.926),       -- centre of the product tray
            work = vec3(-0.04, -0.12, 0.925),       -- where the open baggie / jar stands while you fill it
            lineup = vec3(-0.25, 0.11, 0.925),      -- first container of the row along the back of the mat
            lid = vec3(0.14, -0.12, 0.925),         -- jar lids wait here
            hatch = vec3(0.5, -0.03, 1.09),         -- drop point above the hatch opening
            chute = vec3(0.5, -0.03, 0.8),          -- where a dropped package falls to
        },
        tray = { cols = 6, rows = 4, size = vec2(0.33, 0.24) },  -- bud grid on the tray
        lineupStep = { baggie = 0.08, jar = 0.105 },
        cam = { offset = vec3(-0.02, -0.72, 1.62), look = vec3(-0.02, 0.0, 0.93), fov = 58 },
    },
    mixstation = {
        item = 'nzw_mixstation', label = 'Mixing Station', model = 'nzw_mixstation', fallback = 'bkr_prop_coke_table01a', level = 8, icon = 'flask',
        footprint = 0.7, top = 0.9,
        bowl = { model = 'nzw_mixstation_bowl', offset = vec3(0.28, 0.0, 1.12) },
        anchors = {
            bowl = vec3(0.28, 0.0, 1.16),           -- drop point inside the bowl
            product = vec3(-0.4, -0.05, 0.905),
            ingredient = vec3(-0.18, -0.05, 0.905),
            start = vec3(0.33, -0.24, 1.035),       -- the green button
        },
        cam = { offset = vec3(0.0, -0.95, 1.65), look = vec3(0.0, 0.0, 1.0), fov = 55 },
    },
    brickpress = {
        item = 'nzw_brickpress', label = 'Brick Press', model = 'nzw_brickpress', fallback = 'prop_tool_bench02', level = 12, icon = 'press',
        footprint = 0.6, top = 0.94,
        plate = { model = 'nzw_brickpress_plate', offset = vec3(0.0, 0.0, 1.5), travel = 0.31 },
        lever = { model = 'nzw_brickpress_lever', offset = vec3(0.36, -0.05, 0.98), pump = 65.0 },
        anchors = {
            mould = vec3(0.0, 0.0, 0.84),
            pile = vec3(-0.25, -0.18, 0.83),        -- the product waits on the cabinet top, left of the mould
            lever = vec3(0.36, -0.1, 1.55),         -- grip at rest
        },
        cam = { offset = vec3(0.1, -1.25, 1.55), look = vec3(0.08, 0.0, 1.1), fov = 55 },
    },
}
Config.FallbackModel = 'prop_cs_cardbox_01'

--[[ grow lights: hung on a suspension rack. boost = growth speed multiplier ]]
Config.Lights = {
    halogen  = { item = 'nzw_light_halogen',  label = 'Halogen Grow Light',       model = 'nzw_light_halogen',  level = 1,  boost = 1.25,
                 color = { 255, 196, 120 }, range = 3.2, intensity = 7.0, glow = vec3(0.0, 0.0, -0.46) },
    led      = { item = 'nzw_light_led',      label = 'LED Grow Light',           model = 'nzw_light_led',      level = 5,  boost = 1.25 * 1.15,
                 color = { 196, 70, 255 }, range = 3.2, intensity = 8.0, glow = vec3(0.0, 0.0, -0.42) },
    fullspec = { item = 'nzw_light_fullspec', label = 'Full Spectrum Grow Light', model = 'nzw_light_fullspec', level = 11, boost = 1.25 * 1.30,
                 color = { 255, 246, 232 }, range = 3.4, intensity = 9.0, glow = vec3(0.0, 0.0, -0.36) },
}

--[[ props used while things grow / get packed ]]
Config.Props = {
    soil = 'nzw_soil',                                        -- soil surface spawned into pots
    bud = { green = 'nzw_bud_green', purple = 'nzw_bud_purple', lime = 'nzw_bud_lime', golden = 'nzw_bud_golden' },
    budFallback = 'bkr_prop_weed_bud_02b',
    baggie = 'nzw_baggie', baggieSealed = 'nzw_baggie_sealed', baggieFallback = 'prop_meth_bag_01',
    jar = 'nzw_jar', jarLid = 'nzw_jar_lid', jarFallback = 'prop_cs_script_bottle_01',
    brick = 'nzw_brick', brickFallback = 'prop_weed_block_01',
    trimmers = 'nzw_trimmers', wateringcan = 'nzw_wateringcan', soilbag = 'nzw_soilbag', seedvial = 'nzw_seedvial',
    fertilizer = 'nzw_fertilizer', pgr = 'nzw_pgr', speedgrow = 'nzw_speedgrow',
}

--[[ ─────────────────────── growing ───────────────────────
    minutes = real minutes from seed to harvest while watered (x strain grow multiplier,
    / light boost). water = how many minutes one watering lasts. Nothing ticks on a timer:
    growth is worked out from timestamps whenever someone looks.
]]
Config.Grow = {
    minutes = 26,
    water = 14,
    soils = {
        nzw_soil         = { label = 'Potting Soil',         uses = 1, quality = 1, level = 0 },
        nzw_soil_premium = { label = 'Premium Potting Soil', uses = 2, quality = 2, level = 6 },
    },
    -- once per plant each
    additives = {
        nzw_fertilizer = { label = 'Fertilizer',               quality = 1,  action = 'pot_fertilizer', level = 0 },
        nzw_pgr        = { label = 'Plant Growth Regulator',   yield = 0.5, quality = -1, action = 'pot_pgr', level = 4 },
        nzw_speedgrow  = { label = 'Speed Growth',             growth = 0.5, quality = -1, action = 'pot_speedgrow', level = 2 },
    },
}

Config.WateringCan = { item = 'nzw_wateringcan', capacity = 4 }   -- one watering uses 1
Config.Trimmers = 'nzw_trimmers'

--[[ ─────────────────────── processing ─────────────────────── ]]
Config.Processing = {
    pack = { secondsPer = 2.5, max = { baggie = 6, jar = 4 } }, -- max = how many line up on the station per batch
    dry = { minutes = 10, quality = 1, max = 4 },-- +1 quality, up to max
    press = { minSeconds = 6 },                 -- Config.Product.unitsPerBrick loose units -> 1 brick
    mix = { minSeconds = 8 },
}

--[[ ─────────────────────── first person steps ───────────────────────
    A fixed camera on the station and the mouse. A / D rotate the plant (pots) or the view.
      cut    drag across a line on the held item           { text, prop, at, width }
      pour   hold the mouse button over the target         { text, prop, height, radius, seconds, tilt, fx }
      spray  hold the mouse button, aim at the plant       { text, prop, seconds, radius }
      click  click every target                            { text, prop?, targets = 'cap'|'ring', count, radius }
      trim   click the buds on the plant with the trimmers { text, prop }
      hold   hold the mouse button on a point              { text, prop, seconds }
    `minSeconds` is checked by the server; a finish that comes faster is rejected.
]]
Config.Actions = {
    pot_soil = { minSeconds = 3, steps = {
        { type = 'cut',  text = 'Click and drag to cut the soil bag', prop = 'nzw_soilbag', at = vec3(0.0, 0.0, 0.9), width = 0.36 },
        { type = 'pour', text = 'Pour the soil into the pot', prop = 'nzw_soilbag', height = 0.95, radius = 0.15, seconds = 4.0, tilt = 120.0, fx = 'soil' },
    } },
    pot_seed = { minSeconds = 3, steps = {
        { type = 'click', text = 'Click the cap to open the vial', prop = 'nzw_seedvial', targets = 'cap', count = 1, radius = 0.05 },
        { type = 'pour',  text = 'Tip a seed into the soil', prop = 'nzw_seedvial', height = 0.62, radius = 0.06, seconds = 1.2, tilt = 140.0, fx = 'seed' },
        { type = 'click', text = 'Click the soil to bury the seed', targets = 'ring', count = 6, radius = 0.1, marker = { 88, 58, 44 } },
    } },
    pot_water = { minSeconds = 2, steps = {
        { type = 'pour', text = 'Pour water over the soil', prop = 'nzw_wateringcan', height = 0.85, radius = 0.1, seconds = 3.0, tilt = 50.0, fx = 'water', target = 'random' },
    } },
    pot_fertilizer = { minSeconds = 2, steps = {
        { type = 'spray', text = 'Hold to spray the plant', prop = 'nzw_fertilizer', seconds = 3.0, radius = 0.16 },
    } },
    pot_pgr = { minSeconds = 2, steps = {
        { type = 'click', text = 'Click the cap to open', prop = 'nzw_pgr', targets = 'cap', count = 1, radius = 0.05 },
        { type = 'pour',  text = 'Pour the PGR over the soil', prop = 'nzw_pgr', height = 0.8, radius = 0.12, seconds = 2.2, tilt = 120.0, fx = 'liquid' },
    } },
    pot_speedgrow = { minSeconds = 2, steps = {
        { type = 'click', text = 'Click the cap to open', prop = 'nzw_speedgrow', targets = 'cap', count = 1, radius = 0.05 },
        { type = 'pour',  text = 'Pour Speed Growth over the soil', prop = 'nzw_speedgrow', height = 0.8, radius = 0.12, seconds = 2.2, tilt = 125.0, fx = 'speed' },
    } },
    pot_harvest = { minSeconds = 3, steps = {
        { type = 'trim', text = 'Rotate the plant and trim every bud', prop = 'nzw_trimmers' },
    } },
    tap_fill = { minSeconds = 2, steps = {
        { type = 'hold', text = 'Hold on the tap to fill the watering can', prop = 'nzw_wateringcan', seconds = 3.0 },
    } },
    -- these run their own scenes (client/packaging.lua, client/processing.lua), only timing lives here
    pack = { minSeconds = 3 },
    dry_hang = { minSeconds = 2 },
    mix = { minSeconds = 8 },
    press = { minSeconds = 6 },
}
