--[[
    NAYZEEE RADIO - QBCore shared items
    Built from config/items.lua. If you rename an item there, rename it here too.

    qb-core:   paste the entries into qb-core/shared/items.lua (QBShared.Items)
    qs-inventory / codem-inventory / tgiann-inventory / ps-inventory /
    lj-inventory use the same item format: paste into their item list.
    Copy html/img/items/*.png into the inventory image folder
    (qb-inventory/html/images, see install/README.md for the others).
]]

return {

    -- RADIOS
    ['radio'] = { name = 'radio', label = 'Patrol Radio', weight = 350, type = 'item', image = 'radio.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'PX-740 patrol handheld. Three channels, covers most of a city.' },
    ['radio_fieldpro'] = { name = 'radio_fieldpro', label = 'Field Pro Radio', weight = 300, type = 'item', image = 'radio_fieldpro.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'FX-280 compact field set. Four channels, waterproof, reaches further.' },
    ['radio_military'] = { name = 'radio_military', label = 'Tactical Radio', weight = 650, type = 'item', image = 'radio_military.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'MX-905 rugged tactical set. Five channels, the longest reach, hard to jam.' },

    -- ACCESSORIES
    ['radio_earpiece'] = { name = 'radio_earpiece', label = 'Radio Earpiece', weight = 30, type = 'item', image = 'radio_earpiece.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'Coiled earpiece. Keeps your radio traffic to yourself.' },

    -- JAMMERS
    ['jammer_pocket'] = { name = 'jammer_pocket', label = 'Pocket Jammer', weight = 600, type = 'item', image = 'jammer_pocket.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'JX-10. Fills radios close by with noise.' },
    ['jammer_case'] = { name = 'jammer_case', label = 'Field Jammer', weight = 6500, type = 'item', image = 'jammer_case.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'JX-40 in a hard case. Reaches about a city block.' },
    ['jammer_heavy'] = { name = 'jammer_heavy', label = 'Cabinet Jammer', weight = 28000, type = 'item', image = 'jammer_heavy.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'JX-90 cabinet with an aerial mast. Shuts down radios across a whole area.' },
}
