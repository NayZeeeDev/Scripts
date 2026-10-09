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


-- Crafting tables: these icons come with the Dragons Lab Shoe Table Pack (install-images)

['blueshoetable'] = {
    label = 'Blue shoe table',
    weight = 15000,
    stack = false,
    close = true,
    consume = 0,
    description = 'A crafting table for shoes. Use it to set it up',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['pinkshoetable'] = {
    label = 'Pink shoe table',
    weight = 15000,
    stack = false,
    close = true,
    consume = 0,
    description = 'A crafting table for shoes. Use it to set it up',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['purpleshoetable'] = {
    label = 'Purple shoe table',
    weight = 15000,
    stack = false,
    close = true,
    consume = 0,
    description = 'A crafting table for shoes. Use it to set it up',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['redshoetable'] = {
    label = 'Red shoe table',
    weight = 15000,
    stack = false,
    close = true,
    consume = 0,
    description = 'A crafting table for shoes. Use it to set it up',
    server = { export = 'nayzeee-sneakers.useItem' },
},

-- Crafting materials

['nz_leather'] = {
    label = 'Leather hide',
    weight = 400,
    stack = true,
    close = true,
    description = 'For uppers and boots',
},

['nz_fabric'] = {
    label = 'Mesh fabric',
    weight = 150,
    stack = true,
    close = true,
    description = 'For sneaker uppers',
},

['nz_sole'] = {
    label = 'Rubber sole',
    weight = 350,
    stack = true,
    close = true,
    description = 'One pair of soles',
},

['nz_heel'] = {
    label = 'Heel block',
    weight = 300,
    stack = true,
    close = true,
    description = 'For heels',
},

['nz_thread'] = {
    label = 'Waxed thread',
    weight = 50,
    stack = true,
    close = true,
    description = 'Strong stitching thread',
},

['nz_glue'] = {
    label = 'Shoe glue',
    weight = 200,
    stack = true,
    close = true,
    description = 'Holds a sole on for good',
},

['nz_laces'] = {
    label = 'Laces',
    weight = 20,
    stack = true,
    close = true,
    description = 'One pair of laces',
},

['nz_authtag'] = {
    label = 'Authentic tag',
    weight = 10,
    stack = true,
    close = true,
    description = 'Makes a pair the real thing',
},

-- Cleaning

['nz_cleaning_kit'] = {
    label = 'Cleaning kit',
    weight = 600,
    stack = false,
    close = true,
    consume = 0,
    description = 'Brush, cleaner and a cloth. Good for a few pairs',
    server = { export = 'nayzeee-sneakers.useItem' },
},


-- Display cases (stackable, for a shoe collection)

['nz_display'] = {
    label = 'Shoe display',
    weight = 1500,
    stack = true,
    close = true,
    consume = 0,
    description = 'A clear case for one pair of sneakers. Stacks',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['nz_display_heel'] = {
    label = 'Heel display',
    weight = 1500,
    stack = true,
    close = true,
    consume = 0,
    description = 'A clear case for one pair of heels or ankle boots. Stacks',
    server = { export = 'nayzeee-sneakers.useItem' },
},

['nz_display_boot'] = {
    label = 'Boot display',
    weight = 2200,
    stack = true,
    close = true,
    consume = 0,
    description = 'A big clear case: tall boots, or any pair. Stacks',
    server = { export = 'nayzeee-sneakers.useItem' },
},
