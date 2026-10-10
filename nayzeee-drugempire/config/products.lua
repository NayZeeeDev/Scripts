--[[
    Drugs, effects and mixing.

    Sell value = base price x (1 + sum of effect multipliers), like the game.
    A product holds at most Config.Mixing.maxEffects effects.

    Mixing an ingredient into a product:
      1. every existing effect that the ingredient has a rule for is replaced
         (unless the result is already on the product)
      2. the ingredient's own effect is added if there's room
    The rules below follow the game closely; edit them freely.
]]

--[[ Base drugs. `kind` groups products for customers (what they buy) and stations. ]]
Config.Drugs = {
    ogkush      = { kind = 'weed',  label = 'OG Kush',           price = 38,  effects = { 'calming' },    addictive = 0.05, color = '#3fb950', item = 'nz_weed', seed = 'nz_seed_ogkush', unlock = 1 },
    sourdiesel  = { kind = 'weed',  label = 'Sour Diesel',       price = 40,  effects = { 'refreshing' }, addictive = 0.08, color = '#a3d900', item = 'nz_weed', seed = 'nz_seed_sourdiesel', unlock = 3 },
    greencrack  = { kind = 'weed',  label = 'Green Crack',       price = 43,  effects = { 'energizing' }, addictive = 0.12, color = '#2fd47f', item = 'nz_weed', seed = 'nz_seed_greencrack', unlock = 5 },
    gdp         = { kind = 'weed',  label = 'Granddaddy Purple', price = 44,  effects = { 'sedating' },   addictive = 0.08, color = '#a371f7', item = 'nz_weed', seed = 'nz_seed_gdp', unlock = 7 },
    meth        = { kind = 'meth',  label = 'Meth',              price = 70,  effects = {},               addictive = 0.60, color = '#58a6ff', item = 'nz_meth', unlock = 8 },
    shrooms     = { kind = 'shroom', label = 'Shrooms',          price = 65,  effects = {},               addictive = 0.20, color = '#e3b341', item = 'nz_shroom', unlock = 13 },
    cocaine     = { kind = 'coke',  label = 'Cocaine',           price = 150, effects = {},               addictive = 0.40, color = '#f0f6fc', item = 'nz_cocaine', unlock = 18 },
}

-- drug kinds, in the order the app lists them
Config.Kinds = {
    { id = 'weed',   label = 'Weed',    icon = 'leaf' },
    { id = 'meth',   label = 'Meth',    icon = 'crystal' },
    { id = 'shroom', label = 'Shrooms', icon = 'shroom' },
    { id = 'coke',   label = 'Cocaine', icon = 'powder' },
}

--[[ Quality (set by soil / additives / drying). Customers have minimum standards. ]]
Config.Quality = {
    { id = 0, label = 'Trash',    color = '#e5484d' },
    { id = 1, label = 'Poor',     color = '#e5a50a' },
    { id = 2, label = 'Standard', color = '#9ea5aa' },
    { id = 3, label = 'Premium',  color = '#58a6ff' },
    { id = 4, label = 'Heavenly', color = '#e3b341' },
}

--[[ Effects: mult = value multiplier, addictive = extra addictiveness, color = UI chip ]]
Config.Effects = {
    ['anti_gravity']     = { label = 'Anti-Gravity',      mult = 0.54, color = '#235bcd' },
    ['athletic']         = { label = 'Athletic',          mult = 0.32, color = '#75c8fd', addictive = 0.6 },
    ['balding']          = { label = 'Balding',           mult = 0.30, color = '#c79232' },
    ['bright_eyed']      = { label = 'Bright-Eyed',       mult = 0.40, color = '#bef7fd', addictive = 0.2 },
    ['calming']          = { label = 'Calming',           mult = 0.10, color = '#fed09b' },
    ['calorie_dense']    = { label = 'Calorie-Dense',     mult = 0.28, color = '#fe84f4', addictive = 0.1 },
    ['cyclopean']        = { label = 'Cyclopean',         mult = 0.56, color = '#fec174', addictive = 0.1 },
    ['disorienting']     = { label = 'Disorienting',      mult = 0.00, color = '#fe7551' },
    ['electrifying']     = { label = 'Electrifying',      mult = 0.50, color = '#55c8fd', addictive = 0.24 },
    ['energizing']       = { label = 'Energizing',        mult = 0.22, color = '#9aef6e', addictive = 0.34 },
    ['euphoric']         = { label = 'Euphoric',          mult = 0.18, color = '#feea74', addictive = 0.24 },
    ['explosive']        = { label = 'Explosive',         mult = 0.00, color = '#fe4b40' },
    ['focused']          = { label = 'Focused',           mult = 0.16, color = '#75f1fd', addictive = 0.1 },
    ['foggy']            = { label = 'Foggy',             mult = 0.36, color = '#b0b0af', addictive = 0.1 },
    ['gingeritis']       = { label = 'Gingeritis',        mult = 0.20, color = '#fe8829' },
    ['glowing']          = { label = 'Glowing',           mult = 0.48, color = '#85e459' },
    ['jennerising']      = { label = 'Jennerising',       mult = 0.42, color = '#fe8df9' },
    ['laxative']         = { label = 'Laxative',          mult = 0.00, color = '#763c25', addictive = 0.1 },
    ['long_faced']       = { label = 'Long Faced',        mult = 0.52, color = '#fed961', addictive = 0.6 },
    ['munchies']         = { label = 'Munchies',          mult = 0.12, color = '#c96e57', addictive = 0.1 },
    ['paranoia']         = { label = 'Paranoia',          mult = 0.00, color = '#c46762' },
    ['refreshing']       = { label = 'Refreshing',        mult = 0.14, color = '#b2fe98', addictive = 0.1 },
    ['schizophrenia']    = { label = 'Schizophrenia',     mult = 0.00, color = '#645ab7' },
    ['sedating']         = { label = 'Sedating',          mult = 0.26, color = '#6b5fd8' },
    ['seizure_inducing'] = { label = 'Seizure-Inducing',  mult = 0.00, color = '#fee900' },
    ['shrinking']        = { label = 'Shrinking',         mult = 0.60, color = '#b6fea9', addictive = 0.6 },
    ['slippery']         = { label = 'Slippery',          mult = 0.34, color = '#a2e0fe', addictive = 0.3 },
    ['smelly']           = { label = 'Smelly',            mult = 0.00, color = '#7dbc31' },
    ['sneaky']           = { label = 'Sneaky',            mult = 0.24, color = '#7b7b7b', addictive = 0.3 },
    ['spicy']            = { label = 'Spicy',             mult = 0.38, color = '#fe6b4c' },
    ['thought_provoking']= { label = 'Thought-Provoking', mult = 0.44, color = '#fea0cb', addictive = 0.3 },
    ['toxic']            = { label = 'Toxic',             mult = 0.00, color = '#5f9a31' },
    ['tropic_thunder']   = { label = 'Tropic Thunder',    mult = 0.46, color = '#fe9f47' },
    ['zombifying']       = { label = 'Zombifying',        mult = 0.58, color = '#71ab5d', addictive = 0.6 },
}

--[[ Mixing ingredients: item, buy price (shops.lua), the effect it adds and its replacement rules ]]
Config.Ingredients = {
    nz_cuke         = { label = 'Cuke',         effect = 'energizing',        rules = { euphoric = 'laxative', foggy = 'cyclopean', gingeritis = 'thought_provoking', munchies = 'athletic', slippery = 'munchies', sneaky = 'paranoia', toxic = 'euphoric' } },
    nz_banana       = { label = 'Banana',       effect = 'gingeritis',        rules = { calming = 'sneaky', cyclopean = 'energizing', disorienting = 'focused', energizing = 'thought_provoking', focused = 'seizure_inducing', long_faced = 'refreshing', paranoia = 'jennerising', smelly = 'anti_gravity', toxic = 'smelly' } },
    nz_paracetamol  = { label = 'Paracetamol',  effect = 'sneaky',            rules = { calming = 'slippery', electrifying = 'athletic', energizing = 'paranoia', focused = 'gingeritis', foggy = 'calming', glowing = 'toxic', munchies = 'anti_gravity', paranoia = 'balding', spicy = 'bright_eyed', toxic = 'tropic_thunder' } },
    nz_donut        = { label = 'Donut',        effect = 'calorie_dense',     rules = { anti_gravity = 'slippery', balding = 'sneaky', calorie_dense = 'explosive', focused = 'euphoric', jennerising = 'gingeritis', munchies = 'calming', shrinking = 'energizing' } },
    nz_viagra       = { label = 'Viagor',       effect = 'tropic_thunder',    rules = { athletic = 'sneaky', disorienting = 'toxic', euphoric = 'bright_eyed', laxative = 'calming', shrinking = 'gingeritis' } },
    nz_mouthwash    = { label = 'Mouth Wash',   effect = 'balding',           rules = { calming = 'anti_gravity', calorie_dense = 'sneaky', explosive = 'sedating', focused = 'jennerising' } },
    nz_flumedicine  = { label = 'Flu Medicine', effect = 'sedating',          rules = { athletic = 'munchies', calming = 'bright_eyed', cyclopean = 'foggy', electrifying = 'refreshing', euphoric = 'toxic', focused = 'calming', laxative = 'euphoric', munchies = 'slippery', shrinking = 'paranoia', thought_provoking = 'gingeritis' } },
    nz_gasoline     = { label = 'Gasoline',     effect = 'toxic',             rules = { disorienting = 'glowing', electrifying = 'disorienting', energizing = 'euphoric', euphoric = 'spicy', gingeritis = 'smelly', jennerising = 'sneaky', laxative = 'foggy', munchies = 'sedating', paranoia = 'calming', shrinking = 'focused', sneaky = 'tropic_thunder' } },
    nz_energydrink  = { label = 'Energy Drink', effect = 'athletic',          rules = { disorienting = 'electrifying', euphoric = 'energizing', focused = 'shrinking', foggy = 'laxative', glowing = 'disorienting', schizophrenia = 'balding', sedating = 'munchies', spicy = 'euphoric', tropic_thunder = 'sneaky' } },
    nz_motoroil     = { label = 'Motor Oil',    effect = 'slippery',          rules = { energizing = 'munchies', euphoric = 'sedating', foggy = 'toxic', munchies = 'schizophrenia', paranoia = 'anti_gravity' } },
    nz_megabean     = { label = 'Mega Bean',    effect = 'foggy',             rules = { athletic = 'laxative', calming = 'glowing', energizing = 'cyclopean', focused = 'disorienting', jennerising = 'paranoia', seizure_inducing = 'focused', shrinking = 'electrifying', slippery = 'toxic', sneaky = 'calming', thought_provoking = 'energizing' } },
    nz_chili        = { label = 'Chili',        effect = 'spicy',             rules = { anti_gravity = 'tropic_thunder', athletic = 'euphoric', laxative = 'long_faced', munchies = 'toxic', shrinking = 'refreshing', sneaky = 'bright_eyed' } },
    nz_battery      = { label = 'Battery',      effect = 'bright_eyed',       rules = { cyclopean = 'glowing', electrifying = 'euphoric', euphoric = 'zombifying', laxative = 'calorie_dense', munchies = 'tropic_thunder', shrinking = 'munchies' } },
    nz_iodine       = { label = 'Iodine',       effect = 'jennerising',       rules = { calming = 'balding', calorie_dense = 'gingeritis', euphoric = 'seizure_inducing', foggy = 'paranoia', refreshing = 'thought_provoking', toxic = 'sneaky' } },
    nz_addy         = { label = 'Addy',         effect = 'thought_provoking', rules = { explosive = 'euphoric', foggy = 'energizing', glowing = 'refreshing', long_faced = 'electrifying', sedating = 'gingeritis' } },
    nz_horsesemen   = { label = 'Horse Semen',  effect = 'long_faced',        rules = { anti_gravity = 'calming', gingeritis = 'refreshing', seizure_inducing = 'energizing', thought_provoking = 'electrifying' } },
}

Config.Mixing = {
    maxEffects = 8,
    maxBatch = 10,        -- units per mix (one ingredient per unit)
    seconds = 6,          -- mixing time per batch
    unlock = 3,           -- level needed to place a mixing station
    -- new products get a random name: <prefix> <suffix>, e.g. "Blue Cheese Kush"
    names = {
        weed   = { pre = { 'Blue', 'Purple', 'Lemon', 'Sour', 'Cherry', 'Ghost', 'Sugar', 'Space', 'Diesel', 'Frosty', 'Golden', 'Midnight', 'Thunder', 'Jungle', 'Honey' },
                   suf = { 'Kush', 'Haze', 'Cheese', 'Dream', 'Skunk', 'Cookies', 'Gelato', 'Runtz', 'Widow', 'Mints', 'Glue', 'Zkittlez' } },
        meth   = { pre = { 'Blue', 'Glass', 'Ice', 'Crystal', 'Arctic', 'Diamond', 'Shard', 'Polar', 'Clear', 'Storm' },
                   suf = { 'Sky', 'Shards', 'Rocks', 'Glass', 'Frost', 'Cut', 'Blizzard', 'Spark' } },
        shroom = { pre = { 'Golden', 'Cosmic', 'Penis', 'Blue', 'Albino', 'Mystic', 'Forest', 'Moon', 'Pixie', 'Wizard' },
                   suf = { 'Teacher', 'Caps', 'Envy', 'Meanie', 'Trip', 'Stems', 'Gills', 'Spores' } },
        coke   = { pre = { 'Bolivian', 'Peruvian', 'Snow', 'White', 'Pure', 'Cartel', 'Blanca', 'Pearl', 'Angel', 'Royal' },
                   suf = { 'Flake', 'Rail', 'Dust', 'Powder', 'Line', 'Blow', 'Sugar', 'Kiss' } },
    },
}

--[[ Items that hold a product (metadata: pid, label, quality, units) ]]
Config.ProductItems = {
    loose = { weed = 'nz_weed', meth = 'nz_meth', shroom = 'nz_shroom', coke = 'nz_cocaine' },
    baggie = 'nz_baggie',   -- 1 unit
    jar = 'nz_jar',         -- 5 units
    -- product a loose item counts as when it has no metadata (inventories without metadata support)
    defaultPid = { nz_weed = 'ogkush', nz_meth = 'meth', nz_shroom = 'shrooms', nz_cocaine = 'cocaine' },
}
