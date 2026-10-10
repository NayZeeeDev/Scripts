--[[
    Placeable equipment, production timings and the first person interaction steps.

    Every model can be changed. If a model isn't streamed on your server the script
    falls back to a cardboard box and prints a warning, so nothing breaks.

    Offsets are relative to the station (x = right, y = forward, z = up).
]]

--[[ ─────────────────────── placeables ─────────────────────── ]]
Config.Stations = {
    pot       = { item = 'nz_pot',          label = 'Plastic Pot',        model = 'bkr_prop_weed_bucket_01a', top = 0.38, unlock = 1,  icon = 'pot',
                  cam = { offset = vec3(0.0, -0.85, 1.05), look = vec3(0.0, 0.0, 0.32), fov = 46 } },
    -- grow tent: a pot inside a tent with its own light (custom prop, see stream/)
    tent      = { item = 'nz_tent',         label = 'Grow Tent',          model = 'nz_growtent',              top = 0.38, unlock = 2,  icon = 'tent', pot = true, boost = 1.5,
                  potOffset = vec3(0.0, 0.02, 0.0), fallback = 'bkr_prop_weed_bucket_01a',
                  cam = { offset = vec3(0.0, -0.95, 1.1), look = vec3(0.0, 0.02, 0.32), fov = 46 } },
    light     = { item = 'nz_light',        label = 'Grow Light',         model = 'prop_worklight_03b',       top = 1.6,  unlock = 2,  icon = 'bulb', noUse = true },
    -- packaging bench (custom prop): the right end of the table top is a lid that lifts,
    -- the zipped bag / closed jar goes in the drawer underneath
    packer    = { item = 'nz_packer',       label = 'Packaging Station',  model = 'nz_packbench',             top = 0.92, unlock = 1,  icon = 'box',
                  fallback = 'bkr_prop_weed_table_01a',
                  lid = { model = 'nz_packbench_lid', offset = vec3(0.565, 0.375, 0.9), open = -78.0 },   -- origin on the back hinge
                  anchors = { bag = vec3(-0.12, -0.08, 0.9), drawer = vec3(0.565, 0.0, 0.69), product = vec3(-0.45, 0.02, 0.9) },
                  cam = { offset = vec3(0.05, -1.0, 1.62), look = vec3(0.12, 0.0, 0.9), fov = 52 } },
    rack      = { item = 'nz_rack',         label = 'Drying Rack',        model = 'bkr_prop_weed_drying_02a', top = 1.2,  unlock = 4,  icon = 'rack',
                  cam = { offset = vec3(0.0, -1.4, 1.5), look = vec3(0.0, 0.0, 1.0), fov = 50 } },
    mixer     = { item = 'nz_mixer',        label = 'Mixing Station',     model = 'bkr_prop_coke_table01a',   top = 0.85, unlock = 3,  icon = 'flask',
                  cam = { offset = vec3(0.0, -1.0, 1.6), look = vec3(0.0, 0.0, 0.85), fov = 50 } },
    chem      = { item = 'nz_chem',         label = 'Chemistry Station',  model = 'bkr_prop_meth_table01a',   top = 0.88, unlock = 8,  icon = 'beaker',
                  cam = { offset = vec3(0.0, -0.95, 1.65), look = vec3(0.0, 0.0, 0.9), fov = 48 } },
    oven      = { item = 'nz_oven',         label = 'Lab Oven',           model = 'prop_cooker_03',           top = 0.92, unlock = 8,  icon = 'oven',
                  cam = { offset = vec3(0.0, -0.9, 1.5), look = vec3(0.0, 0.0, 0.9), fov = 48 } },
    cauldron  = { item = 'nz_cauldron',     label = 'Cauldron',           model = 'prop_barrel_02a',          top = 0.95, unlock = 18, icon = 'cauldron',
                  cam = { offset = vec3(0.0, -0.85, 1.75), look = vec3(0.0, 0.0, 0.9), fov = 46 } },
    spawn     = { item = 'nz_spawnstation', label = 'Spawn Station',      model = 'prop_tool_bench02',        top = 0.92, unlock = 13, icon = 'syringe',
                  cam = { offset = vec3(0.0, -0.9, 1.6), look = vec3(0.0, 0.0, 0.92), fov = 48 } },
    bed       = { item = 'nz_bed',          label = 'Mushroom Bed',       model = 'prop_box_wood02a',         top = 0.55, unlock = 13, icon = 'shroom',
                  cam = { offset = vec3(0.0, -0.95, 1.35), look = vec3(0.0, 0.0, 0.5), fov = 48 } },
}

Config.FallbackModel = 'prop_cs_cardbox_01'

--[[ packaging props (custom, fall back to base game props) ]]
Config.PackProps = {
    bag = 'nz_zipbag', bagFallback = 'prop_meth_bag_01',
    jar = 'nz_jar', jarFallback = 'prop_cs_script_bottle_01',
    jarLid = 'nz_jar_lid',
    bud = 'bkr_prop_weed_bud_02b',
}

--[[ props used while a pot / bed grows ]]
Config.GrowProps = {
    soil = 'bkr_prop_weed_bucket_01b',            -- pot with soil (swapped in when the pot is full)
    weed = { 'bkr_prop_weed_01_small_01b', 'bkr_prop_weed_med_01b', 'bkr_prop_weed_lrg_01b' },
    coca = { 'bkr_prop_weed_01_small_01a', 'bkr_prop_weed_med_01a', 'bkr_prop_weed_lrg_01a' },
    shroom = { 'prop_stoneshroom1', 'prop_stoneshroom2', 'prop_stoneshroom2' },
    bud = 'bkr_prop_weed_bud_02b',               -- clickable buds on a grown plant
    cap = 'prop_stoneshroom1',                   -- clickable mushrooms in a grown bed
}

--[[ ─────────────────────── growing ─────────────────────── ]]
Config.Grow = {
    -- minutes = real minutes from seed to harvest while watered. water = how long a full watering lasts
    weed   = { minutes = 30, water = 12, yield = { 8, 12 }, item = 'nz_weed' },
    coca   = { minutes = 36, water = 12, yield = { 8, 10 }, item = 'nz_coca_leaf' },
    shroom = { minutes = 28, water = 10, yield = { 6, 10 }, item = 'nz_shroom' },
    lightBoost = 1.6,      -- growth speed next to a grow light
    lightRadius = 2.2,
    seeds = {
        nz_seed_ogkush     = { crop = 'weed', product = 'ogkush' },
        nz_seed_sourdiesel = { crop = 'weed', product = 'sourdiesel' },
        nz_seed_greencrack = { crop = 'weed', product = 'greencrack' },
        nz_seed_gdp        = { crop = 'weed', product = 'gdp' },
        nz_seed_coca       = { crop = 'coca', product = 'cocaine', unlock = 18 },
    },
    soils = {
        nz_soil     = { label = 'Soil',                 uses = 1, quality = 1 },
        nz_soil_ll  = { label = 'Long-Life Soil',       uses = 2, quality = 2 },
        nz_soil_ell = { label = 'Extra Long-Life Soil', uses = 3, quality = 3 },
    },
    additives = {
        nz_fertilizer = { label = 'Fertilizer',  quality = 1 },
        nz_pgr        = { label = 'PGR',         yield = 0.5 },
        nz_speedgrow  = { label = 'Speed Grow',  growth = 0.5 },
    },
}

--[[ ─────────────────────── processing ─────────────────────── ]]
Config.Processing = {
    pack   = { seconds = 1.2, max = 20 },                          -- extra bags / jars in one batch go faster
    rack   = { minutes = 8, capacity = 20 },                       -- weed: +1 quality, coca leaf -> dried leaf
    chem   = { minutes = 5, needs = { nz_acid = 1, nz_phosphorus = 1, nz_pseudo = 1 }, output = 'nz_meth_liquid' },
    oven   = { minutes = 4, meth = { input = 'nz_meth_liquid', output = 10 }, coke = { input = 'nz_coca_base', max = 10 } },
    cauldron = { minutes = 8, leaves = 20, gasoline = 1, output = 10 },  -- dried coca leaves + gasoline -> coca base
    spawn  = { minutes = 6, needs = { nz_spores = 1, nz_grainbag = 1 }, output = 'nz_shroom_spawn' },
    bed    = { needs = { nz_substrate = 1, nz_shroom_spawn = 1 } },
}

--[[ ─────────────────────── first person steps ───────────────────────
    Step types (all happen through a fixed camera with the mouse):
      cut    drag across a line on the held item           { text, prop, at, width }
      pour   hold the mouse button over the target         { text, prop, height, radius, seconds, tilt, fx, target }
      click  click every target                            { text, prop?, targets = 'cap'|'ring'|'buds'|'shards'|'caps', count, radius, marker }
      drop   carry the held item over the target, release  { text, prop, height, radius }
      hold   hold the mouse button on a fixed target       { text, at, seconds, fx }
      stir   move the mouse in circles around the target   { text, prop, turns, radius }
      anim   scripted beat, no input (the packer lid)      { text, lid = 'open'|'close' }
    `target` / `anchor` name a station anchor (Config.Stations.<type>.anchors); default is the station top.
    `minSeconds` is checked by the server; finishing faster is rejected as an exploit.
]]
local soilBag = 'prop_feed_sack_01'

Config.Actions = {
    pot_soil = { minSeconds = 3, steps = {
        { type = 'cut',  text = 'Click and drag to cut soil bag', prop = soilBag, at = vec3(0.0, 0.0, 0.85), width = 0.42 },
        { type = 'pour', text = 'Pour soil into pot', prop = soilBag, height = 0.78, radius = 0.17, seconds = 4.0, tilt = 115.0, fx = 'soil' },
    } },
    pot_seed = { minSeconds = 3, steps = {
        { type = 'click', text = 'Click cap to remove', prop = 'prop_cs_pills', targets = 'cap', count = 1, radius = 0.06 },
        { type = 'drop',  text = 'Drop seed into hole', prop = 'prop_golf_ball', height = 0.62, radius = 0.09 },
        { type = 'click', text = 'Click soil chunks to bury seed', targets = 'ring', count = 6, radius = 0.11, marker = { 88, 58, 44 } },
    } },
    pot_water = { minSeconds = 2, steps = {
        { type = 'pour', text = 'Pour water over target', prop = 'prop_wateringcan', height = 0.72, radius = 0.09, seconds = 3.0, tilt = 55.0, fx = 'water', target = 'random' },
    } },
    pot_additive = { minSeconds = 2, steps = {
        { type = 'click', text = 'Click cap to remove', prop = 'prop_ld_flow_bottle', targets = 'cap', count = 1, radius = 0.06 },
        { type = 'pour',  text = 'Pour over the soil', prop = 'prop_ld_flow_bottle', height = 0.7, radius = 0.14, seconds = 2.0, tilt = 120.0, fx = 'water' },
    } },
    pot_harvest = { minSeconds = 3, steps = {
        { type = 'click', text = 'Click buds to harvest', prop = 'prop_cs_scissors', targets = 'buds', radius = 0.075 },
    } },
    -- packaging: the first bag of a batch is done by hand, the rest play out automatically
    pack_baggie = { minSeconds = 3, steps = {
        { type = 'drop',  text = 'Drop the product into the bag', prop = 'bkr_prop_weed_bud_02b', from = 'product', target = 'bag', height = 1.02, radius = 0.08 },
        { type = 'cut',   text = 'Click and drag to zip the bag', anchor = 'bag', at = vec3(0.0, 0.056, 0.016), width = 0.1, zip = true },
        { type = 'anim',  text = 'Open the drawer', lid = 'open' },
        { type = 'drop',  text = 'Put the bag in the drawer', prop = 'held:bag', target = 'drawer', height = 1.04, radius = 0.12 },
        { type = 'anim',  text = 'Close the drawer', lid = 'close' },
    } },
    pack_jar = { minSeconds = 3, steps = {
        { type = 'drop',  text = 'Drop the product into the jar', prop = 'bkr_prop_weed_bud_02b', from = 'product', target = 'bag', height = 1.08, radius = 0.06 },
        { type = 'click', text = 'Click the lid to close the jar', targets = 'jarlid', count = 1, radius = 0.05 },
        { type = 'anim',  text = 'Open the drawer', lid = 'open' },
        { type = 'drop',  text = 'Put the jar in the drawer', prop = 'held:jar', target = 'drawer', height = 1.06, radius = 0.12 },
        { type = 'anim',  text = 'Close the drawer', lid = 'close' },
    } },
    sink_fill = { minSeconds = 2, steps = {
        { type = 'hold', text = 'Click and hold tap to refill watering can', prop = 'prop_wateringcan', seconds = 3.0, fx = 'water' },
    } },

    chem_start = { minSeconds = 5, steps = {
        { type = 'pour', text = 'Pour acid into the flask', prop = 'bkr_prop_meth_sacid', height = 1.12, radius = 0.12, seconds = 2.5, tilt = 120.0, fx = 'liquid' },
        { type = 'pour', text = 'Add the phosphorus', prop = 'bkr_prop_meth_phosphorus', height = 1.12, radius = 0.12, seconds = 2.0, tilt = 120.0, fx = 'soil' },
        { type = 'drop', text = 'Drop the pseudo in', prop = 'bkr_prop_meth_pseudoephedrine', height = 1.12, radius = 0.12 },
        { type = 'stir', text = 'Stir the mixture', prop = 'prop_cs_script_bottle', turns = 4, radius = 0.12 },
    } },
    oven_load = { minSeconds = 2, steps = {
        { type = 'drop', text = 'Put the tray in the oven', prop = 'bkr_prop_meth_tray_01a', height = 1.0, radius = 0.16 },
    } },
    oven_smash = { minSeconds = 3, steps = {
        { type = 'click', text = 'Smash the tray', prop = 'prop_tool_hammer', targets = 'shards', count = 8, radius = 0.08, marker = { 140, 200, 255 } },
    } },
    cauldron_start = { minSeconds = 4, steps = {
        { type = 'drop', text = 'Drop the coca leaves in', prop = 'bkr_prop_weed_bud_pruned_01a', height = 1.25, radius = 0.18 },
        { type = 'pour', text = 'Pour in the gasoline', prop = 'w_am_jerrycan', height = 1.3, radius = 0.18, seconds = 2.5, tilt = 95.0, fx = 'liquid' },
        { type = 'stir', text = 'Stir the cauldron', prop = 'prop_cs_script_bottle', turns = 3, radius = 0.18 },
    } },
    spawn_start = { minSeconds = 3, steps = {
        { type = 'click', text = 'Click cap to remove', prop = 'prop_syringe_01', targets = 'cap', count = 1, radius = 0.06 },
        { type = 'drop',  text = 'Inject spores into the grain bag', prop = 'prop_syringe_01', height = 1.05, radius = 0.12 },
        { type = 'stir',  text = 'Shake the bag', turns = 3, radius = 0.12 },
    } },
    bed_fill = { minSeconds = 4, steps = {
        { type = 'cut',  text = 'Click and drag to cut substrate bag', prop = 'prop_feed_sack_02', at = vec3(0.0, 0.0, 1.0), width = 0.42 },
        { type = 'pour', text = 'Pour substrate into the bed', prop = 'prop_feed_sack_02', height = 0.95, radius = 0.25, seconds = 3.5, tilt = 115.0, fx = 'soil' },
        { type = 'drop', text = 'Crumble the spawn in', prop = 'prop_food_bag1', height = 0.9, radius = 0.22 },
        { type = 'stir', text = 'Mix it through', turns = 3, radius = 0.2 },
    } },
    bed_mist = { minSeconds = 2, steps = {
        { type = 'pour', text = 'Mist over target', prop = 'prop_wateringcan', height = 0.9, radius = 0.12, seconds = 3.0, tilt = 55.0, fx = 'water', target = 'random' },
    } },
    bed_harvest = { minSeconds = 3, steps = {
        { type = 'click', text = 'Click mushrooms to harvest', targets = 'caps', radius = 0.08 },
    } },
}

--[[ watering can: litres. One watering uses 1. ]]
Config.WateringCan = { capacity = 4 }
