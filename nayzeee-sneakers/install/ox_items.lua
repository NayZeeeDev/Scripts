-- ox_inventory (QBX, ESX or QB with ox): paste into ox_inventory/data/items.lua
-- and copy install/images/*.png into ox_inventory/web/images/

['nz_shoes'] = {
    label = 'Shoes',
    weight = 900,
    stack = false,
    close = true,
    consume = 0,
    description = 'A pair of sneakers',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['nz_shoebox'] = {
    label = 'Boxed shoes',
    weight = 1200,
    stack = false,
    close = true,
    consume = 0,
    description = 'A pair of sneakers in their box',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['nz_shoebox_empty'] = {
    label = 'Empty shoe box',
    weight = 300,
    stack = true,
    close = true,
    consume = 0,
    description = 'For sneakers',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['nz_heelbox_empty'] = {
    label = 'Empty heel box',
    weight = 300,
    stack = true,
    close = true,
    consume = 0,
    description = 'For heels and ankle boots',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['nz_bootbox_empty'] = {
    label = 'Empty boot box',
    weight = 500,
    stack = true,
    close = true,
    consume = 0,
    description = 'For tall boots',
    server = { export = 'nayzeee-sneakers.useItem' },
},
