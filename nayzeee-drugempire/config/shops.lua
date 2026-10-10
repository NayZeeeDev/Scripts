--[[
    Deliveries: order supplies from the Empire app. Orders are dropped at a dead drop
    (or inside your RV for a fee) after a short wait.

    Also the master item list. install/ has ready-made item files built from it.
]]

Config.Deliveries = {
    minutes = { 2, 4 },        -- wait before a dead-drop order is ready
    rvFee = 150,               -- deliver straight into the RV instead
    rvMinutes = { 4, 6 },
    maxOpen = 3,
    collectDistance = 2.0,
    model = 'prop_cs_cardbox_01',
    blip = { sprite = 478, color = 5, scale = 0.8 },
}

Config.DeadDrops = {
    { id = 'sandy_bins',   label = 'Bins behind the Sandy 24/7',  region = 'sandy',     coords = vec4(1965.4, 3747.6, 32.3, 210.0) },
    { id = 'sandy_shed',   label = 'Shed by the airfield',         region = 'sandy',     coords = vec4(1716.9, 3292.3, 41.2, 105.0) },
    { id = 'harmony_tire', label = 'Tyre stack, Harmony',          region = 'harmony',   coords = vec4(548.7, 2655.2, 42.2, 15.0) },
    { id = 'grape_barn',   label = 'Old barn, Grapeseed',          region = 'grapeseed', coords = vec4(1902.6, 4924.0, 48.8, 155.0) },
    { id = 'paleto_dock',  label = 'Paleto pier crates',           region = 'paleto',    coords = vec4(-275.6, 6635.4, 7.4, 45.0) },
    { id = 'south_alley',  label = 'Alley off Grove Street',       region = 'southls',   coords = vec4(84.1, -1972.5, 20.8, 320.0) },
    { id = 'mirror_rail',  label = 'Mirror Park rail bridge',      region = 'mirror',    coords = vec4(1198.6, -655.4, 62.9, 100.0) },
}

-- `unlock` = level. `stock` items are bought in packs of `pack`
Config.Shops = {
    {
        id = 'hardware', label = "Dan's Hardware", icon = 'tool', desc = 'Soil, pots and growing gear',
        items = {
            { item = 'nz_soil',         price = 10,  unlock = 1 },
            { item = 'nz_soil_ll',      price = 30,  unlock = 4 },
            { item = 'nz_soil_ell',     price = 60,  unlock = 9 },
            { item = 'nz_pot',          price = 20,  unlock = 1 },
            { item = 'nz_wateringcan',  price = 15,  unlock = 1 },
            { item = 'nz_trimmers',     price = 10,  unlock = 1 },
            { item = 'nz_fertilizer',   price = 30,  unlock = 3 },
            { item = 'nz_pgr',          price = 30,  unlock = 6 },
            { item = 'nz_speedgrow',    price = 30,  unlock = 10 },
            { item = 'nz_light',        price = 80,  unlock = 2 },
            { item = 'nz_tent',         price = 150, unlock = 2 },
            { item = 'nz_rack',         price = 120, unlock = 4 },
            { item = 'nz_baggie_empty', price = 1,   unlock = 1 },
            { item = 'nz_jar_empty',    price = 3,   unlock = 5 },
            { item = 'nz_packer',       price = 100, unlock = 1 },
        },
    },
    {
        id = 'gasmart', label = 'Gas-Mart', icon = 'cart', desc = 'Mixing ingredients',
        items = {
            { item = 'nz_cuke',        price = 2, unlock = 3 },
            { item = 'nz_banana',      price = 2, unlock = 3 },
            { item = 'nz_paracetamol', price = 3, unlock = 3 },
            { item = 'nz_donut',       price = 3, unlock = 3 },
            { item = 'nz_viagra',      price = 4, unlock = 5 },
            { item = 'nz_mouthwash',   price = 4, unlock = 5 },
            { item = 'nz_flumedicine', price = 5, unlock = 6 },
            { item = 'nz_gasoline',    price = 5, unlock = 6 },
            { item = 'nz_energydrink', price = 6, unlock = 8 },
            { item = 'nz_motoroil',    price = 6, unlock = 8 },
            { item = 'nz_megabean',    price = 7, unlock = 10 },
            { item = 'nz_chili',       price = 7, unlock = 10 },
            { item = 'nz_battery',     price = 8, unlock = 12 },
            { item = 'nz_iodine',      price = 8, unlock = 12 },
            { item = 'nz_addy',        price = 9, unlock = 15 },
            { item = 'nz_horsesemen',  price = 9, unlock = 15 },
        },
    },
    {
        id = 'oscar', label = "Oscar's Equipment", icon = 'flask', desc = 'Lab equipment',
        items = {
            { item = 'nz_mixer',        price = 500,  unlock = 3 },
            { item = 'nz_chem',         price = 1000, unlock = 8 },
            { item = 'nz_oven',         price = 1000, unlock = 8 },
            { item = 'nz_spawnstation', price = 800,  unlock = 13 },
            { item = 'nz_bed',          price = 400,  unlock = 13 },
            { item = 'nz_cauldron',     price = 3000, unlock = 18 },
        },
    },
    {
        id = 'benson', label = "Benson's Supply", icon = 'wheel', desc = 'Seeds and precursors. No questions.',
        items = {
            { item = 'nz_seed_ogkush',     price = 30,  unlock = 1 },
            { item = 'nz_seed_sourdiesel', price = 35,  unlock = 3 },
            { item = 'nz_seed_greencrack', price = 40,  unlock = 5 },
            { item = 'nz_seed_gdp',        price = 45,  unlock = 7 },
            { item = 'nz_acid',            price = 40,  unlock = 8 },
            { item = 'nz_phosphorus',      price = 40,  unlock = 8 },
            { item = 'nz_pseudo',          price = 60,  unlock = 8 },
            { item = 'nz_spores',          price = 50,  unlock = 13 },
            { item = 'nz_grainbag',        price = 15,  unlock = 13 },
            { item = 'nz_substrate',       price = 25,  unlock = 13 },
            { item = 'nz_seed_coca',       price = 120, unlock = 18 },
        },
    },
}

--[[ every item this resource uses: name = { label, weight (grams), desc } ]]
Config.Items = {
    -- equipment (placeable)
    nz_pot          = { 'Plastic Pot', 800, 'Place it in your lab and grow something.' },
    nz_light        = { 'Grow Light', 2500, 'Plants near it grow faster.' },
    nz_tent         = { 'Grow Tent', 6000, 'A pot in a tent with its own light. Grows faster.' },
    nz_packer       = { 'Packaging Station', 8000, 'Bag and jar your product.' },
    nz_rack         = { 'Drying Rack', 6000, 'Dry weed (better quality) and coca leaves.' },
    nz_mixer        = { 'Mixing Station', 9000, 'Mix ingredients into your product for new effects.' },
    nz_chem         = { 'Chemistry Station', 12000, 'Cook liquid meth.' },
    nz_oven         = { 'Lab Oven', 12000, 'Bake liquid meth and coca base.' },
    nz_cauldron     = { 'Cauldron', 15000, 'Turn dried coca leaves into coca base.' },
    nz_spawnstation = { 'Spawn Station', 7000, 'Inject spores into grain bags.' },
    nz_bed          = { 'Mushroom Bed', 6000, 'Grow mushrooms.' },
    -- growing
    nz_soil         = { 'Soil', 3000, 'Basic soil. Good for one harvest.' },
    nz_soil_ll      = { 'Long-Life Soil', 3000, 'Good for two harvests, better quality.' },
    nz_soil_ell     = { 'Extra Long-Life Soil', 3000, 'Good for three harvests, best quality.' },
    nz_wateringcan  = { 'Watering Can', 600, 'Fill it at a tap.' },
    nz_trimmers     = { 'Plant Trimmers', 300, 'For harvesting.' },
    nz_fertilizer   = { 'Fertilizer', 1000, '+1 quality on the next harvest.' },
    nz_pgr          = { 'PGR', 1000, '+50% yield on the next harvest.' },
    nz_speedgrow    = { 'Speed Grow', 1000, 'Instantly grows a plant by half.' },
    nz_seed_ogkush     = { 'OG Kush Seed', 10, 'Plant it in a pot with soil.' },
    nz_seed_sourdiesel = { 'Sour Diesel Seed', 10, 'Plant it in a pot with soil.' },
    nz_seed_greencrack = { 'Green Crack Seed', 10, 'Plant it in a pot with soil.' },
    nz_seed_gdp        = { 'Granddaddy Purple Seed', 10, 'Plant it in a pot with soil.' },
    nz_seed_coca       = { 'Coca Seed', 10, 'Plant it in a pot with soil.' },
    -- packaging
    nz_baggie_empty = { 'Empty Baggie', 5, 'Holds 1 unit.' },
    nz_jar_empty    = { 'Empty Jar', 60, 'Holds 5 units.' },
    nz_baggie       = { 'Baggie', 10, 'A bagged product.' },
    nz_jar          = { 'Jar', 120, 'A jar of product.' },
    -- product + intermediates
    nz_weed         = { 'Weed', 10, 'Loose weed.' },
    nz_meth         = { 'Meth', 10, 'Loose meth.' },
    nz_shroom       = { 'Shrooms', 10, 'Loose mushrooms.' },
    nz_cocaine      = { 'Cocaine', 10, 'Loose cocaine.' },
    nz_coca_leaf    = { 'Coca Leaf', 15, 'Dry it on a drying rack.' },
    nz_coca_dry     = { 'Dried Coca Leaf', 10, 'Cauldron food.' },
    nz_coca_base    = { 'Coca Base', 50, 'Bake it in a lab oven.' },
    nz_meth_liquid  = { 'Liquid Meth', 500, 'Bake it in a lab oven.' },
    nz_shroom_spawn = { 'Mushroom Spawn', 400, 'Mix it into a mushroom bed.' },
    -- precursors
    nz_acid         = { 'Acid', 600, 'Chemistry station ingredient.' },
    nz_phosphorus   = { 'Phosphorus', 400, 'Chemistry station ingredient.' },
    nz_pseudo       = { 'Pseudo', 200, 'Chemistry station ingredient.' },
    nz_spores       = { 'Spore Syringe', 50, 'Spawn station ingredient.' },
    nz_grainbag     = { 'Grain Bag', 800, 'Spawn station ingredient.' },
    nz_substrate    = { 'Mushroom Substrate', 2000, 'Fills a mushroom bed.' },
    -- mixing ingredients
    nz_cuke         = { 'Cuke', 330, 'Mixing ingredient.' },
    nz_banana       = { 'Banana', 120, 'Mixing ingredient.' },
    nz_paracetamol  = { 'Paracetamol', 50, 'Mixing ingredient.' },
    nz_donut        = { 'Donut', 100, 'Mixing ingredient.' },
    nz_viagra       = { 'Viagor', 30, 'Mixing ingredient.' },
    nz_mouthwash    = { 'Mouth Wash', 400, 'Mixing ingredient.' },
    nz_flumedicine  = { 'Flu Medicine', 200, 'Mixing ingredient.' },
    nz_gasoline     = { 'Gasoline', 1000, 'Mixing ingredient. Also feeds the cauldron.' },
    nz_energydrink  = { 'Energy Drink', 330, 'Mixing ingredient.' },
    nz_motoroil     = { 'Motor Oil', 1000, 'Mixing ingredient.' },
    nz_megabean     = { 'Mega Bean', 100, 'Mixing ingredient.' },
    nz_chili        = { 'Chili', 50, 'Mixing ingredient.' },
    nz_battery      = { 'Battery', 150, 'Mixing ingredient.' },
    nz_iodine       = { 'Iodine', 100, 'Mixing ingredient.' },
    nz_addy         = { 'Addy', 30, 'Mixing ingredient.' },
    nz_horsesemen   = { 'Horse Semen', 200, 'Mixing ingredient.' },
}
