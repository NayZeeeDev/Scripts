--[[
    Customers, regions, meeting spots and dealers.

    Customers live in regions. A region opens at a level. Locked customers next to an
    unlocked one show up in the Contacts app: give them a free sample to win them over.
    Customers then text you deal requests (product, amount, place, price).

    Positions are snapped to the ground in game, so only x / y need to be right.
    Stand somewhere and run /nzdecoords to copy a vec4 to your clipboard.
]]

Config.Standards = {
    { id = 0, label = 'Very Low',  minQuality = 0, spend = 0.85 },
    { id = 1, label = 'Low',       minQuality = 1, spend = 0.95 },
    { id = 2, label = 'Moderate',  minQuality = 2, spend = 1.05 },
    { id = 3, label = 'High',      minQuality = 3, spend = 1.20 },
    { id = 4, label = 'Very High', minQuality = 4, spend = 1.40 },
}

-- relationship 0..5, like the game
Config.Relationship = {
    labels = { { 0, 'Hostile' }, { 1, 'Unfriendly' }, { 2, 'Neutral' }, { 3, 'Friendly' }, { 4, 'Loyal' } },
    start = 2.0,
    unlockConnections = 3.0,   -- at Friendly a customer introduces their connections
    perDeal = 0.25,            -- good deal
    perFavorite = 0.1,         -- per matching favourite effect
    badDeal = -0.4,            -- below standards / late
    missed = -0.5,             -- accepted and never showed
}

Config.Regions = {
    { id = 'sandy',     label = 'Sandy Shores',       unlock = 1,  center = vec2(1850.0, 3700.0) },
    { id = 'harmony',   label = 'Harmony / Route 68', unlock = 4,  center = vec2(700.0, 2680.0) },
    { id = 'grapeseed', label = 'Grapeseed',          unlock = 8,  center = vec2(1700.0, 4850.0) },
    { id = 'paleto',    label = 'Paleto Bay',         unlock = 12, center = vec2(-100.0, 6400.0) },
    { id = 'southls',   label = 'South Los Santos',   unlock = 16, center = vec2(50.0, -1800.0) },
    { id = 'mirror',    label = 'Mirror Park',        unlock = 20, center = vec2(1150.0, -500.0) },
    { id = 'vinewood',  label = 'Vinewood',           unlock = 24, center = vec2(300.0, 300.0) },
}

-- meeting spots (deals happen here)
Config.Spots = {
    sandy_gas       = { region = 'sandy',     label = 'Behind the gas station',      coords = vec4(2008.2, 3790.1, 32.2, 120.0) },
    sandy_blue      = { region = 'sandy',     label = 'Blue house',                  coords = vec4(1897.3, 3859.4, 32.3, 210.0) },
    sandy_liquor    = { region = 'sandy',     label = 'Behind the liquor store',     coords = vec4(1398.6, 3617.4, 34.9, 20.0) },
    sandy_doctor    = { region = 'sandy',     label = "Near the doctor's office",    coords = vec4(1828.0, 3660.0, 34.3, 300.0) },
    sandy_barber    = { region = 'sandy',     label = 'By the barber',               coords = vec4(1936.5, 3722.0, 32.6, 30.0) },
    sandy_trailers  = { region = 'sandy',     label = 'Trailer park',                coords = vec4(1687.0, 3754.0, 34.6, 140.0) },
    harmony_store   = { region = 'harmony',   label = 'Behind the Harmony 24/7',     coords = vec4(557.3, 2680.6, 42.2, 190.0) },
    harmony_motel   = { region = 'harmony',   label = 'Eastern Motel',               coords = vec4(317.9, 2623.1, 44.5, 300.0) },
    harmony_route68 = { region = 'harmony',   label = 'Route 68 discount store',     coords = vec4(1203.0, 2700.3, 38.0, 90.0) },
    grape_ltd       = { region = 'grapeseed', label = 'Behind the LTD',              coords = vec4(1710.0, 4930.0, 42.0, 60.0) },
    grape_main      = { region = 'grapeseed', label = 'Grapeseed Main Street',       coords = vec4(1678.0, 4820.0, 42.0, 270.0) },
    grape_air       = { region = 'grapeseed', label = 'Grapeseed airstrip',          coords = vec4(2128.0, 4790.0, 41.1, 30.0) },
    paleto_store    = { region = 'paleto',    label = 'Behind the Paleto 24/7',      coords = vec4(1737.0, 6420.0, 35.0, 150.0) },
    paleto_gas      = { region = 'paleto',    label = 'Paleto gas station',          coords = vec4(170.0, 6610.0, 31.9, 220.0) },
    paleto_bank     = { region = 'paleto',    label = 'Alley by the bank',           coords = vec4(-120.0, 6470.0, 31.4, 45.0) },
    south_grove     = { region = 'southls',   label = 'Grove Street cul-de-sac',     coords = vec4(104.1, -1938.6, 20.8, 50.0) },
    south_davis     = { region = 'southls',   label = 'Behind the Davis gas station', coords = vec4(-40.0, -1748.0, 29.4, 140.0) },
    mirror_ltd      = { region = 'mirror',    label = 'Mirror Park LTD',             coords = vec4(1166.0, -323.0, 69.2, 100.0) },
    mirror_lake     = { region = 'mirror',    label = 'Mirror Park lake',            coords = vec4(1080.0, -690.0, 57.6, 0.0) },
    vine_clinton    = { region = 'vinewood',  label = 'Clinton Ave 24/7',            coords = vec4(381.0, 337.0, 102.6, 250.0) },
    vine_hills      = { region = 'vinewood',  label = 'Vinewood side street',        coords = vec4(230.0, 300.0, 105.5, 160.0) },
}

--[[ Customers
    standards: 0 Very Low .. 4 Very High   buys: drug kinds   budget: $ per deal at relationship 2
    home: spot where they hang out (where you give samples)   links: connections ]]
Config.Customers = {
    andy     = { name = 'Andy',      model = 'a_m_y_hippy_01',    region = 'sandy',     home = 'sandy_gas',      standards = 2, favorites = { 'sedating', 'munchies', 'smelly' },        buys = { 'weed' },                 budget = 120, links = { 'doug', 'chelsey' } },
    doug     = { name = 'Doug',      model = 'a_m_m_hillbilly_01', region = 'sandy',    home = 'sandy_blue',     standards = 1, favorites = { 'energizing', 'calming', 'refreshing' },   buys = { 'weed' },                 budget = 100, links = { 'andy', 'kyle', 'donna' } },
    joe      = { name = 'Joe',       model = 'a_m_m_salton_01',   region = 'sandy',     home = 'sandy_liquor',   standards = 0, favorites = { 'munchies', 'euphoric', 'focused' },       buys = { 'weed', 'meth' },         budget = 90,  links = { 'peter', 'meg' } },
    chelsey  = { name = 'Chelsey',   model = 'a_f_y_hippie_01',   region = 'sandy',     home = 'sandy_doctor',   standards = 2, favorites = { 'calming', 'focused', 'gingeritis' },      buys = { 'weed', 'shroom' },       budget = 130, links = { 'andy', 'austin' } },
    kyle     = { name = 'Kyle',      model = 'a_m_y_methhead_01', region = 'sandy',     home = 'sandy_trailers', standards = 1, favorites = { 'energizing', 'athletic', 'sneaky' },       buys = { 'weed', 'meth' },         budget = 140, links = { 'doug', 'meg', 'jessi' } },
    donna    = { name = 'Donna',     model = 'a_f_m_salton_01',   region = 'sandy',     home = 'sandy_barber',   standards = 1, favorites = { 'calming', 'sedating', 'munchies' },       buys = { 'weed' },                 budget = 110, links = { 'doug', 'peter' } },
    peter    = { name = 'Peter',     model = 'a_m_m_salton_02',   region = 'sandy',     home = 'sandy_barber',   standards = 2, favorites = { 'focused', 'thought_provoking', 'bright_eyed' }, buys = { 'weed', 'shroom' }, budget = 150, links = { 'joe', 'donna', 'kathy' } },
    meg      = { name = 'Meg',       model = 'a_f_y_rurmeth_01',  region = 'sandy',     home = 'sandy_trailers', standards = 0, favorites = { 'energizing', 'electrifying', 'euphoric' }, buys = { 'meth' },                budget = 160, links = { 'joe', 'kyle', 'mick' } },
    austin   = { name = 'Austin',    model = 'a_m_y_salton_01',   region = 'harmony',   home = 'harmony_store',  standards = 2, favorites = { 'spicy', 'athletic', 'slippery' },         buys = { 'weed', 'meth' },         budget = 180, links = { 'chelsey', 'jessi', 'sam' } },
    jessi    = { name = 'Jessi',     model = 'a_f_y_juggalo_01',  region = 'harmony',   home = 'harmony_motel',  standards = 1, favorites = { 'glowing', 'euphoric', 'tropic_thunder' }, buys = { 'weed', 'meth' },         budget = 170, links = { 'kyle', 'austin', 'mick' } },
    mick     = { name = 'Mick',      model = 'a_m_m_rurmeth_01',  region = 'harmony',   home = 'harmony_route68', standards = 1, favorites = { 'energizing', 'foggy', 'paranoia' },      buys = { 'meth', 'shroom' },       budget = 200, links = { 'meg', 'jessi', 'jerry' } },
    kathy    = { name = 'Kathy',     model = 'a_f_m_tourist_01',  region = 'harmony',   home = 'harmony_motel',  standards = 3, favorites = { 'calming', 'refreshing', 'anti_gravity' }, buys = { 'weed', 'shroom' },       budget = 220, links = { 'peter', 'beth' } },
    sam      = { name = 'Sam',       model = 'a_m_m_farmer_01',   region = 'grapeseed', home = 'grape_ltd',      standards = 2, favorites = { 'munchies', 'calorie_dense', 'sedating' }, buys = { 'weed', 'meth' },         budget = 210, links = { 'austin', 'beth', 'ludwig' } },
    beth     = { name = 'Beth',      model = 'a_f_m_fatcult_01',  region = 'grapeseed', home = 'grape_main',     standards = 3, favorites = { 'thought_provoking', 'glowing', 'calming' }, buys = { 'shroom', 'weed' },     budget = 260, links = { 'kathy', 'sam', 'geraldine' } },
    ludwig   = { name = 'Ludwig',    model = 'a_m_m_hillbilly_02', region = 'grapeseed', home = 'grape_air',     standards = 2, favorites = { 'electrifying', 'bright_eyed', 'jennerising' }, buys = { 'meth', 'shroom' }, budget = 280, links = { 'sam', 'jerry' } },
    geraldine= { name = 'Geraldine', model = 'a_f_o_soucent_01',  region = 'paleto',    home = 'paleto_store',   standards = 3, favorites = { 'calming', 'sedating', 'balding' },        buys = { 'shroom', 'weed' },       budget = 300, links = { 'beth', 'marco' } },
    jerry    = { name = 'Jerry',     model = 'a_m_m_tramp_01',    region = 'paleto',    home = 'paleto_gas',     standards = 0, favorites = { 'energizing', 'sneaky', 'toxic' },         buys = { 'meth' },                 budget = 260, links = { 'mick', 'ludwig', 'marco' } },
    marco    = { name = 'Marco',     model = 'a_m_y_stbla_01',    region = 'paleto',    home = 'paleto_bank',    standards = 2, favorites = { 'athletic', 'slippery', 'spicy' },         buys = { 'meth', 'coke' },         budget = 380, links = { 'geraldine', 'jerry', 'tyrell' } },
    tyrell   = { name = 'Tyrell',    model = 'a_m_y_soucent_02',  region = 'southls',   home = 'south_grove',    standards = 2, favorites = { 'energizing', 'euphoric', 'cyclopean' },   buys = { 'meth', 'coke' },         budget = 420, links = { 'marco', 'keisha' } },
    keisha   = { name = 'Keisha',    model = 'a_f_y_soucent_02',  region = 'southls',   home = 'south_davis',    standards = 3, favorites = { 'bright_eyed', 'focused', 'shrinking' },   buys = { 'coke', 'weed' },         budget = 460, links = { 'tyrell', 'chad' } },
    chad     = { name = 'Chad',      model = 'a_m_y_hipster_01',  region = 'mirror',    home = 'mirror_ltd',     standards = 4, favorites = { 'zombifying', 'anti_gravity', 'electrifying' }, buys = { 'coke', 'shroom' },  budget = 600, links = { 'keisha', 'brooke' } },
    brooke   = { name = 'Brooke',    model = 'a_f_y_hipster_02',  region = 'mirror',    home = 'mirror_lake',    standards = 3, favorites = { 'glowing', 'long_faced', 'energizing' },   buys = { 'coke' },                 budget = 560, links = { 'chad', 'lance' } },
    lance    = { name = 'Lance',     model = 'a_m_y_vinewood_01', region = 'vinewood',  home = 'vine_clinton',   standards = 4, favorites = { 'shrinking', 'cyclopean', 'tropic_thunder' }, buys = { 'coke' },              budget = 750, links = { 'brooke', 'crystal' } },
    crystal  = { name = 'Crystal',   model = 'a_f_y_vinewood_03', region = 'vinewood',  home = 'vine_hills',     standards = 4, favorites = { 'euphoric', 'glowing', 'thought_provoking' }, buys = { 'coke', 'shroom' },   budget = 700, links = { 'lance' } },
}

--[[ Dealers: hire them, stock them, assign customers, collect the cash ]]
Config.DealerList = {
    benji  = { name = 'Benji', model = 'a_m_y_methhead_01', region = 'sandy',     coords = vec4(1694.8, 3760.3, 34.7, 230.0), fee = 500,  cut = 0.20, unlock = 4 },
    molly  = { name = 'Molly', model = 'a_f_y_rurmeth_01',  region = 'harmony',   coords = vec4(565.1, 2686.4, 42.1, 100.0),  fee = 1000, cut = 0.20, unlock = 9 },
    wes    = { name = 'Wes',   model = 'a_m_m_hillbilly_02', region = 'grapeseed', coords = vec4(1716.4, 4938.2, 42.1, 140.0), fee = 1500, cut = 0.18, unlock = 12 },
    brad   = { name = 'Brad',  model = 'a_m_y_stwhi_01',    region = 'paleto',    coords = vec4(-112.4, 6476.2, 31.5, 315.0),  fee = 2500, cut = 0.18, unlock = 15 },
    leo    = { name = 'Leo',   model = 'a_m_y_soucent_01',  region = 'southls',   coords = vec4(112.6, -1930.1, 20.8, 120.0),  fee = 4000, cut = 0.15, unlock = 20 },
    jane   = { name = 'Jane',  model = 'a_f_y_hipster_01',  region = 'mirror',    coords = vec4(1160.1, -330.9, 69.2, 10.0),   fee = 6000, cut = 0.15, unlock = 25 },
}
