--[[
    Hardware store catalogue and the master item list.

    Store rows: { item, price, cat } - the level comes from the equipment / strain /
    additive / ingredient config, so an item unlocks in one place only.
    Config.Items = { label, weight in grams, description } is what the install/ files
    are generated from (lua5.4 tests/gen_install.lua .).
]]

Config.Store = {
    categories = {
        { id = 'grow',  label = 'Growing',   icon = 'pot' },
        { id = 'light', label = 'Lights',    icon = 'bulb' },
        { id = 'seed',  label = 'Seeds',     icon = 'seed' },
        { id = 'proc',  label = 'Processing', icon = 'box' },
        { id = 'mix',   label = 'Mixing',    icon = 'flask' },
    },
    items = {
        { item = 'nzw_pot',            price = 60,   cat = 'grow' },
        { item = 'nzw_soil',           price = 25,   cat = 'grow' },
        { item = 'nzw_wateringcan',    price = 40,   cat = 'grow' },
        { item = 'nzw_trimmers',       price = 30,   cat = 'grow' },
        { item = 'nzw_fertilizer',     price = 45,   cat = 'grow' },
        { item = 'nzw_speedgrow',      price = 70,   cat = 'grow' },
        { item = 'nzw_growtent',       price = 1500, cat = 'grow' },
        { item = 'nzw_pgr',            price = 80,   cat = 'grow' },
        { item = 'nzw_soil_premium',   price = 90,   cat = 'grow' },

        { item = 'nzw_rack',           price = 450,  cat = 'light' },
        { item = 'nzw_light_halogen',  price = 350,  cat = 'light' },
        { item = 'nzw_light_led',      price = 1200, cat = 'light' },
        { item = 'nzw_light_fullspec', price = 4200, cat = 'light' },

        { item = 'nzw_seed_ogkush',      price = 30,  cat = 'seed' },
        { item = 'nzw_seed_sourdiesel',  price = 45,  cat = 'seed' },
        { item = 'nzw_seed_greencrack',  price = 70,  cat = 'seed' },
        { item = 'nzw_seed_gdp',         price = 95,  cat = 'seed' },
        { item = 'nzw_seed_lemonhaze',   price = 130, cat = 'seed' },
        { item = 'nzw_seed_purplepunch', price = 170, cat = 'seed' },
        { item = 'nzw_seed_goldleaf',    price = 240, cat = 'seed' },

        { item = 'nzw_packstation',    price = 300,  cat = 'proc' },
        { item = 'nzw_baggie_empty',   price = 2,    cat = 'proc' },
        { item = 'nzw_jar_empty',      price = 6,    cat = 'proc', level = 3 },
        { item = 'nzw_dryrack',        price = 900,  cat = 'proc' },
        { item = 'nzw_brickpress',     price = 9000, cat = 'proc' },

        { item = 'nzw_mixstation',      price = 3500, cat = 'mix' },
        { item = 'nzw_ing_cuke',        price = 6,  cat = 'mix' },
        { item = 'nzw_ing_banana',      price = 4,  cat = 'mix' },
        { item = 'nzw_ing_paracetamol', price = 8,  cat = 'mix' },
        { item = 'nzw_ing_donut',       price = 5,  cat = 'mix' },
        { item = 'nzw_ing_energydrink', price = 8,  cat = 'mix' },
        { item = 'nzw_ing_mouthwash',   price = 9,  cat = 'mix' },
        { item = 'nzw_ing_flumedicine', price = 12, cat = 'mix' },
        { item = 'nzw_ing_gasoline',    price = 10, cat = 'mix' },
        { item = 'nzw_ing_viagra',      price = 18, cat = 'mix' },
        { item = 'nzw_ing_motoroil',    price = 14, cat = 'mix' },
        { item = 'nzw_ing_megabean',    price = 16, cat = 'mix' },
        { item = 'nzw_ing_chili',       price = 12, cat = 'mix' },
        { item = 'nzw_ing_battery',     price = 20, cat = 'mix' },
        { item = 'nzw_ing_iodine',      price = 22, cat = 'mix' },
        { item = 'nzw_ing_addy',        price = 26, cat = 'mix' },
        { item = 'nzw_ing_horsesemen',  price = 34, cat = 'mix' },
    },
    maxQuantity = 50,   -- per purchase
}

Config.Items = {
    -- equipment (usable: placing starts from the inventory too)
    nzw_pot            = { 'Plastic Pot', 900, 'A pot for one plant. Add soil, then a seed.' },
    nzw_growtent       = { 'Grow Tent', 9000, 'A small grow tent with built-in lighting and pot. Plants will grow faster but smaller.' },
    nzw_rack           = { 'Suspension Rack', 8000, 'Used to hang grow lights above pots.' },
    nzw_light_halogen  = { 'Halogen Grow Light', 3500, 'Cheap and simple halogen grow light. Must be placed on a suspension rack.' },
    nzw_light_led      = { 'LED Grow Light', 3000, 'A simple LED grow light. Emits a purple light that stimulates plant growth 15% faster than halogen. Must be placed on a suspension rack.' },
    nzw_light_fullspec = { 'Full Spectrum Grow Light', 4500, 'Very fancy full-spectrum grow light. Stimulates plant growth 30% faster than halogen. Must be placed on a suspension rack.' },
    nzw_dryrack        = { 'Drying Rack', 7000, 'Hang up organic items here to improve their quality.' },
    nzw_packstation    = { 'Packaging Station', 15000, 'Provides a clean surface to place product into packaging.' },
    nzw_mixstation     = { 'Mixing Station', 18000, 'Used to mix product with ingredients to create unique new products.' },
    nzw_brickpress     = { 'Brick Press', 40000, 'Industrial brick press used to squish stuff into bricks.' },
    -- tools + consumables
    nzw_wateringcan    = { 'Watering Can', 800, 'Fill it at the tap in your lab. Four waterings per fill.' },
    nzw_trimmers       = { 'Trimmers', 150, 'For harvesting buds.' },
    nzw_soil           = { 'Potting Soil', 6000, 'Enough soil for one plant.' },
    nzw_soil_premium   = { 'Premium Potting Soil', 6000, 'Better soil: higher quality, lasts two harvests.' },
    nzw_fertilizer     = { 'Fertilizer', 1000, 'Spray on a growing plant: +1 quality.' },
    nzw_pgr            = { 'Plant Growth Regulator', 1000, 'Plant growth regulator (PGR) will increase the yields of your plants, at the cost of quality.' },
    nzw_speedgrow      = { 'Speed Growth', 1000, 'Instantly grows the plant by 50%, but reduces plant quality.' },
    -- seeds
    nzw_seed_ogkush      = { 'OG Kush Seed', 5, 'Plant it in a pot with soil.' },
    nzw_seed_sourdiesel  = { 'Sour Diesel Seed', 5, 'Plant it in a pot with soil.' },
    nzw_seed_greencrack  = { 'Green Crack Seed', 5, 'Plant it in a pot with soil.' },
    nzw_seed_gdp         = { 'Granddaddy Purple Seed', 5, 'Plant it in a pot with soil.' },
    nzw_seed_lemonhaze   = { 'Lemon Haze Seed', 5, 'Plant it in a pot with soil.' },
    nzw_seed_purplepunch = { 'Purple Punch Seed', 5, 'Plant it in a pot with soil.' },
    nzw_seed_goldleaf    = { 'Gold Leaf Seed', 5, 'Plant it in a pot with soil.' },
    -- packaging + product (product items carry their strain / quality in metadata)
    nzw_baggie_empty   = { 'Empty Baggie', 5, 'Holds 1 unit.' },
    nzw_jar_empty      = { 'Empty Jar', 120, 'Holds 5 units.' },
    nzw_weed           = { 'Weed', 2, 'A trimmed bud. Package it, dry it or mix it.' },
    nzw_baggie         = { 'Baggie of Weed', 10, 'A sealed baggie.' },
    nzw_jar            = { 'Jar of Weed', 140, 'A sealed jar.' },
    nzw_brick          = { 'Brick of Weed', 1000, 'A pressed brick.' },
}

-- mixing ingredients get their item rows from Config.Ingredients
for item, ing in pairs(Config.Ingredients) do
    Config.Items[item] = Config.Items[item] or { ing.label, 150, ('Mixing ingredient. Adds %s.'):format(Config.Effects[ing.effect].label) }
end
