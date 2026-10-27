--[[
    NAYZEEE RADIO - ox_inventory items
    Built from config/items.lua. If you rename an item there, rename it here too.

    Copy every entry below into ox_inventory/data/items.lua (inside its
    "return { ... }" table). Images load straight from this resource, no
    copying needed.

    consume = 0: nayzeee-radio takes a jammer out of the inventory itself when
    it is set down, and a radio or earpiece is never used up, so ox must never
    take one on use.
    stack = false on the radios: every radio is its own item.
]]

return {

    -- RADIOS
    ['radio'] = {
        label = 'Patrol Radio',
        weight = 350,
        stack = false,
        close = true,
        consume = 0,
        description = 'PX-740 patrol handheld. Three channels, covers most of a city.',
        client = {
            image = 'nui://nayzeee-radio/html/img/items/radio.png',
        },
    },
    ['radio_fieldpro'] = {
        label = 'Field Pro Radio',
        weight = 300,
        stack = false,
        close = true,
        consume = 0,
        description = 'FX-280 compact field set. Four channels, waterproof, reaches further.',
        client = {
            image = 'nui://nayzeee-radio/html/img/items/radio_fieldpro.png',
        },
    },
    ['radio_military'] = {
        label = 'Tactical Radio',
        weight = 650,
        stack = false,
        close = true,
        consume = 0,
        description = 'MX-905 rugged tactical set. Five channels, the longest reach, hard to jam.',
        client = {
            image = 'nui://nayzeee-radio/html/img/items/radio_military.png',
        },
    },

    -- ACCESSORIES
    ['radio_earpiece'] = {
        label = 'Radio Earpiece',
        weight = 30,
        stack = true,
        close = true,
        consume = 0,
        description = 'Coiled earpiece. Keeps your radio traffic to yourself.',
        client = {
            image = 'nui://nayzeee-radio/html/img/items/radio_earpiece.png',
        },
    },

    -- JAMMERS
    ['jammer_pocket'] = {
        label = 'Pocket Jammer',
        weight = 600,
        stack = true,
        close = true,
        consume = 0,
        description = 'JX-10. Fills radios close by with noise.',
        client = {
            image = 'nui://nayzeee-radio/html/img/items/jammer_pocket.png',
        },
    },
    ['jammer_case'] = {
        label = 'Field Jammer',
        weight = 6500,
        stack = true,
        close = true,
        consume = 0,
        description = 'JX-40 in a hard case. Reaches about a city block.',
        client = {
            image = 'nui://nayzeee-radio/html/img/items/jammer_case.png',
        },
    },
    ['jammer_heavy'] = {
        label = 'Heavy Jammer',
        weight = 28000,
        stack = true,
        close = true,
        consume = 0,
        description = 'JX-90 cabinet with an aerial mast. Shuts down radios across a whole area.',
        client = {
            image = 'nui://nayzeee-radio/html/img/items/jammer_heavy.png',
        },
    },
}
