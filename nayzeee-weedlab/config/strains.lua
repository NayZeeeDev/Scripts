--[[
    Strains, quality, effects and mixing.

    Strains
      bud    = colour of the bud props (green | lime | golden | purple | red), see stream/nzw_bud_*.ydr
      ng     = the strain's name in the nextgen_weedprops pack (ng_prop_weed_<size>_<ng>_<variant>).
               Those plants come in 7 growth steps and carry their own pot + gravel.
      plant  = optional: your own model list instead (any number of growth steps, small to big)
      grow   = growth time multiplier (1.0 = Config.Grow.minutes), yield = bud range at harvest
      price  = base value of one unit (mixing multiplies this)
      level  = level needed to plant it (the store only sells unlocked seeds)

    Mixing (like the game): a mixed product = base strain + effects.
      value = price x (1 + sum of effect multipliers)
      Mixing an ingredient in: every effect the ingredient has a rule for is replaced
      (unless the result is already there), then the ingredient's own effect is added.
]]

Config.Plants = {
    -- the nextgen_weedprops pack: 3 small, 2 medium, 2 big steps per strain. The last one is "ready to harvest"
    steps = { 's_%s_a', 's_%s_b', 's_%s_c', 'm_%s_a', 'm_%s_b', 'b_%s_a', 'b_%s_b' },
    prefix = 'ng_prop_weed_',
    includesPot = true,     -- these plants bring their own pot + gravel: the script hides its pot / soil under them
    -- when the pack isn't streamed: base-game plants (no pot of their own)
    fallback = { 'bkr_prop_weed_01_small_01b', 'bkr_prop_weed_med_01b', 'bkr_prop_weed_lrg_01b' },
    fallbackScale = 0.7,
}

Config.Strains = {
    ogkush     = { label = 'OG Kush',          ng = 'ogkush',    seed = 'nzw_seed_ogkush',     level = 0,  price = 40, effects = { 'calming' },    color = '#3fb950', bud = 'green',  grow = 1.0,  yield = { 6, 9 } },
    acagold    = { label = 'Acapulco Gold',    ng = 'acagold',   seed = 'nzw_seed_acagold',    level = 2,  price = 46, effects = { 'refreshing' }, color = '#b5e61d', bud = 'lime',   grow = 1.05, yield = { 6, 9 } },
    lemonskunk = { label = 'Lemon Skunk',      ng = 'lgreen',    seed = 'nzw_seed_lemonskunk', level = 5,  price = 52, effects = { 'focused' },    color = '#e3d341', bud = 'lime',   grow = 1.1,  yield = { 7, 10 } },
    colomgold  = { label = 'Colombian Gold',   ng = 'colomgold', seed = 'nzw_seed_colomgold',  level = 7,  price = 58, effects = { 'energizing' }, color = '#e0902a', bud = 'golden', grow = 1.15, yield = { 7, 10 } },
    nlights    = { label = 'Northern Lights',  ng = 'nlights',   seed = 'nzw_seed_nlights',    level = 10, price = 66, effects = { 'sedating' },   color = '#a371f7', bud = 'purple', grow = 1.2,  yield = { 8, 11 } },
    dosidos    = { label = 'Do-Si-Dos',        ng = 'dosidos',   seed = 'nzw_seed_dosidos',    level = 13, price = 74, effects = { 'euphoric' },   color = '#a8763e', bud = 'golden', grow = 1.25, yield = { 8, 12 } },
    rainbowb   = { label = 'Rainbow Belts',    ng = 'rainbowb',  seed = 'nzw_seed_rainbowb',   level = 17, price = 88, effects = { 'glowing' },    color = '#d23c5a', bud = 'red',    grow = 1.35, yield = { 9, 13 } },
}
Config.StrainOrder = { 'ogkush', 'acagold', 'lemonskunk', 'colomgold', 'nlights', 'dosidos', 'rainbowb' }

-- the growth steps of a strain (model names, small to big)
function Config.PlantModels(id)
    local s = Config.Strains[id]
    if not s then return Config.Plants.fallback end
    if s.plant then return s.plant end
    local out = {}
    for i, fmt in ipairs(Config.Plants.steps) do out[i] = Config.Plants.prefix .. fmt:format(s.ng) end
    return out
end

--[[ Quality. Soil sets the start, fertilizer and the drying rack raise it, PGR and Speed Growth lower it. ]]
Config.Quality = {
    { id = 0, label = 'Trash',    color = '#e5484d' },
    { id = 1, label = 'Poor',     color = '#e5a50a' },
    { id = 2, label = 'Standard', color = '#9ea5aa' },
    { id = 3, label = 'Premium',  color = '#58a6ff' },
    { id = 4, label = 'Heavenly', color = '#e3b341' },
}

--[[ Effects: mult = value multiplier, color = UI chip ]]
Config.Effects = {
    anti_gravity      = { label = 'Anti-Gravity',      mult = 0.54, color = '#235bcd' },
    athletic          = { label = 'Athletic',          mult = 0.32, color = '#75c8fd' },
    balding           = { label = 'Balding',           mult = 0.30, color = '#c79232' },
    bright_eyed       = { label = 'Bright-Eyed',       mult = 0.40, color = '#bef7fd' },
    calming           = { label = 'Calming',           mult = 0.10, color = '#fed09b' },
    calorie_dense     = { label = 'Calorie-Dense',     mult = 0.28, color = '#fe84f4' },
    cyclopean         = { label = 'Cyclopean',         mult = 0.56, color = '#fec174' },
    disorienting      = { label = 'Disorienting',      mult = 0.00, color = '#fe7551' },
    electrifying      = { label = 'Electrifying',      mult = 0.50, color = '#55c8fd' },
    energizing        = { label = 'Energizing',        mult = 0.22, color = '#9aef6e' },
    euphoric          = { label = 'Euphoric',          mult = 0.18, color = '#feea74' },
    explosive         = { label = 'Explosive',         mult = 0.00, color = '#fe4b40' },
    focused           = { label = 'Focused',           mult = 0.16, color = '#75f1fd' },
    foggy             = { label = 'Foggy',             mult = 0.36, color = '#b0b0af' },
    gingeritis        = { label = 'Gingeritis',        mult = 0.20, color = '#fe8829' },
    glowing           = { label = 'Glowing',           mult = 0.48, color = '#85e459' },
    jennerising       = { label = 'Jennerising',       mult = 0.42, color = '#fe8df9' },
    laxative          = { label = 'Laxative',          mult = 0.00, color = '#763c25' },
    long_faced        = { label = 'Long Faced',        mult = 0.52, color = '#fed961' },
    munchies          = { label = 'Munchies',          mult = 0.12, color = '#c96e57' },
    paranoia          = { label = 'Paranoia',          mult = 0.00, color = '#c46762' },
    refreshing        = { label = 'Refreshing',        mult = 0.14, color = '#b2fe98' },
    schizophrenia     = { label = 'Schizophrenia',     mult = 0.00, color = '#645ab7' },
    sedating          = { label = 'Sedating',          mult = 0.26, color = '#6b5fd8' },
    seizure_inducing  = { label = 'Seizure-Inducing',  mult = 0.00, color = '#fee900' },
    shrinking         = { label = 'Shrinking',         mult = 0.60, color = '#b6fea9' },
    slippery          = { label = 'Slippery',          mult = 0.34, color = '#a2e0fe' },
    smelly            = { label = 'Smelly',            mult = 0.00, color = '#7dbc31' },
    sneaky            = { label = 'Sneaky',            mult = 0.24, color = '#7b7b7b' },
    spicy             = { label = 'Spicy',             mult = 0.38, color = '#fe6b4c' },
    thought_provoking = { label = 'Thought-Provoking', mult = 0.44, color = '#fea0cb' },
    toxic             = { label = 'Toxic',             mult = 0.00, color = '#5f9a31' },
    tropic_thunder    = { label = 'Tropic Thunder',    mult = 0.46, color = '#fe9f47' },
    zombifying        = { label = 'Zombifying',        mult = 0.58, color = '#71ab5d' },
}

--[[ Mixing ingredients: label, level, the effect it adds, replacement rules and the prop
     you drop into the mixer (base-game props, any missing one falls back to a box) ]]
Config.Ingredients = {
    nzw_ing_cuke        = { label = 'Cuke',         level = 8,  effect = 'energizing',        prop = 'prop_ld_can_01',        rules = { euphoric = 'laxative', foggy = 'cyclopean', gingeritis = 'thought_provoking', munchies = 'athletic', slippery = 'munchies', sneaky = 'paranoia', toxic = 'euphoric' } },
    nzw_ing_banana      = { label = 'Banana',       level = 8,  effect = 'gingeritis',        prop = 'ng_proc_food_nana1a',   rules = { calming = 'sneaky', cyclopean = 'energizing', disorienting = 'focused', energizing = 'thought_provoking', focused = 'seizure_inducing', long_faced = 'refreshing', paranoia = 'jennerising', smelly = 'anti_gravity', toxic = 'smelly' } },
    nzw_ing_paracetamol = { label = 'Paracetamol',  level = 8,  effect = 'sneaky',            prop = 'prop_cs_pills',         rules = { calming = 'slippery', electrifying = 'athletic', energizing = 'paranoia', focused = 'gingeritis', foggy = 'calming', glowing = 'toxic', munchies = 'anti_gravity', paranoia = 'balding', spicy = 'bright_eyed', toxic = 'tropic_thunder' } },
    nzw_ing_donut       = { label = 'Donut',        level = 8,  effect = 'calorie_dense',     prop = 'prop_donut_01',         rules = { anti_gravity = 'slippery', balding = 'sneaky', calorie_dense = 'explosive', focused = 'euphoric', jennerising = 'gingeritis', munchies = 'calming', shrinking = 'energizing' } },
    nzw_ing_energydrink = { label = 'Energy Drink', level = 9,  effect = 'athletic',          prop = 'prop_energy_drink',     rules = { disorienting = 'electrifying', euphoric = 'energizing', focused = 'shrinking', foggy = 'laxative', glowing = 'disorienting', schizophrenia = 'balding', sedating = 'munchies', spicy = 'euphoric', tropic_thunder = 'sneaky' } },
    nzw_ing_mouthwash   = { label = 'Mouth Wash',   level = 9,  effect = 'balding',           prop = 'prop_ld_flow_bottle',   rules = { calming = 'anti_gravity', calorie_dense = 'sneaky', explosive = 'sedating', focused = 'jennerising' } },
    nzw_ing_flumedicine = { label = 'Flu Medicine', level = 10, effect = 'sedating',          prop = 'prop_cs_pills',         rules = { athletic = 'munchies', calming = 'bright_eyed', cyclopean = 'foggy', electrifying = 'refreshing', euphoric = 'toxic', focused = 'calming', laxative = 'euphoric', munchies = 'slippery', shrinking = 'paranoia', thought_provoking = 'gingeritis' } },
    nzw_ing_gasoline    = { label = 'Gasoline',     level = 10, effect = 'toxic',             prop = 'w_am_jerrycan',         rules = { disorienting = 'glowing', electrifying = 'disorienting', energizing = 'euphoric', euphoric = 'spicy', gingeritis = 'smelly', jennerising = 'sneaky', laxative = 'foggy', munchies = 'sedating', paranoia = 'calming', shrinking = 'focused', sneaky = 'tropic_thunder' } },
    nzw_ing_viagra      = { label = 'Viagor',       level = 11, effect = 'tropic_thunder',    prop = 'prop_cs_pills',         rules = { athletic = 'sneaky', disorienting = 'toxic', euphoric = 'bright_eyed', laxative = 'calming', shrinking = 'gingeritis' } },
    nzw_ing_motoroil    = { label = 'Motor Oil',    level = 11, effect = 'slippery',          prop = 'prop_ld_flow_bottle',   rules = { energizing = 'munchies', euphoric = 'sedating', foggy = 'toxic', munchies = 'schizophrenia', paranoia = 'anti_gravity' } },
    nzw_ing_megabean    = { label = 'Mega Bean',    level = 12, effect = 'foggy',             prop = 'prop_ld_can_01',        rules = { athletic = 'laxative', calming = 'glowing', energizing = 'cyclopean', focused = 'disorienting', jennerising = 'paranoia', seizure_inducing = 'focused', shrinking = 'electrifying', slippery = 'toxic', sneaky = 'calming', thought_provoking = 'energizing' } },
    nzw_ing_chili       = { label = 'Chili',        level = 12, effect = 'spicy',             prop = 'prop_cs_pills',         rules = { anti_gravity = 'tropic_thunder', athletic = 'euphoric', laxative = 'long_faced', munchies = 'toxic', shrinking = 'refreshing', sneaky = 'bright_eyed' } },
    nzw_ing_battery     = { label = 'Battery',      level = 13, effect = 'bright_eyed',       prop = 'prop_ld_can_01',        rules = { cyclopean = 'glowing', electrifying = 'euphoric', euphoric = 'zombifying', laxative = 'calorie_dense', munchies = 'tropic_thunder', shrinking = 'munchies' } },
    nzw_ing_iodine      = { label = 'Iodine',       level = 14, effect = 'jennerising',       prop = 'prop_ld_flow_bottle',   rules = { calming = 'balding', calorie_dense = 'gingeritis', euphoric = 'seizure_inducing', foggy = 'paranoia', refreshing = 'thought_provoking', toxic = 'sneaky' } },
    nzw_ing_addy        = { label = 'Addy',         level = 16, effect = 'thought_provoking', prop = 'prop_cs_pills',         rules = { explosive = 'euphoric', foggy = 'energizing', glowing = 'refreshing', long_faced = 'electrifying', sedating = 'gingeritis' } },
    nzw_ing_horsesemen  = { label = 'Horse Semen',  level = 18, effect = 'long_faced',        prop = 'prop_ld_flow_bottle',   rules = { anti_gravity = 'calming', gingeritis = 'refreshing', seizure_inducing = 'energizing', thought_provoking = 'electrifying' } },
}

Config.Mixing = {
    maxEffects = 8,
    maxBatch = 10,        -- units per mix (one ingredient per unit)
    seconds = 6,          -- how long the bowl spins
    -- new products get a random name: <prefix> <suffix>, e.g. "Blue Cheese Kush"
    names = {
        pre = { 'Blue', 'Purple', 'Lemon', 'Sour', 'Cherry', 'Ghost', 'Sugar', 'Space', 'Diesel', 'Frosty', 'Golden', 'Midnight', 'Thunder', 'Jungle', 'Honey', 'Mango', 'Grape', 'Velvet' },
        suf = { 'Kush', 'Haze', 'Cheese', 'Dream', 'Skunk', 'Cookies', 'Gelato', 'Runtz', 'Widow', 'Mints', 'Glue', 'Zkittlez', 'Breath', 'Cake' },
    },
}

--[[ Items that hold product (metadata: pid, label, quality, units) ]]
Config.Product = {
    loose = 'nzw_weed',        -- 1 unit (a trimmed bud)
    baggie = 'nzw_baggie',     -- unitsPerBaggie
    jar = 'nzw_jar',           -- unitsPerJar
    brick = 'nzw_brick',       -- unitsPerBrick
    unitsPerBaggie = 1,
    unitsPerJar = 5,
    unitsPerBrick = 20,
    defaultPid = 'ogkush',     -- what loose weed counts as without metadata (plain ESX inventory)
}
