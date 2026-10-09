-- qb-inventory / ps-inventory / lj-inventory: paste into qb-core/shared/items.lua
-- and copy install/images/*.png into qb-inventory/html/images/

nz_shoes = { name = 'nz_shoes', label = 'Shoes', weight = 900, type = 'item', image = 'nz_shoes.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A pair of sneakers' },
nz_shoebox = { name = 'nz_shoebox', label = 'Boxed shoes', weight = 1200, type = 'item', image = 'nz_shoebox.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A pair of sneakers in their box' },
nz_shoebox_empty = { name = 'nz_shoebox_empty', label = 'Empty shoe box', weight = 300, type = 'item', image = 'nz_shoebox_empty.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'For sneakers' },
nz_heelbox_empty = { name = 'nz_heelbox_empty', label = 'Empty heel box', weight = 300, type = 'item', image = 'nz_heelbox_empty.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'For heels and ankle boots' },
nz_bootbox_empty = { name = 'nz_bootbox_empty', label = 'Empty boot box', weight = 500, type = 'item', image = 'nz_bootbox_empty.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'For tall boots' },


-- Crafting tables: these icons come with the Dragons Lab Shoe Table Pack (install-images)
blueshoetable = { name = 'blueshoetable', label = 'Blue shoe table', weight = 15000, type = 'item', image = 'blueshoetable.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A crafting table for shoes. Use it to set it up' },
pinkshoetable = { name = 'pinkshoetable', label = 'Pink shoe table', weight = 15000, type = 'item', image = 'pinkshoetable.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A crafting table for shoes. Use it to set it up' },
purpleshoetable = { name = 'purpleshoetable', label = 'Purple shoe table', weight = 15000, type = 'item', image = 'purpleshoetable.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A crafting table for shoes. Use it to set it up' },
redshoetable = { name = 'redshoetable', label = 'Red shoe table', weight = 15000, type = 'item', image = 'redshoetable.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A crafting table for shoes. Use it to set it up' },

-- Crafting materials
nz_leather = { name = 'nz_leather', label = 'Leather hide', weight = 400, type = 'item', image = 'nz_leather.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'For uppers and boots' },
nz_fabric = { name = 'nz_fabric', label = 'Mesh fabric', weight = 150, type = 'item', image = 'nz_fabric.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'For sneaker uppers' },
nz_sole = { name = 'nz_sole', label = 'Rubber sole', weight = 350, type = 'item', image = 'nz_sole.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'One pair of soles' },
nz_heel = { name = 'nz_heel', label = 'Heel block', weight = 300, type = 'item', image = 'nz_heel.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'For heels' },
nz_thread = { name = 'nz_thread', label = 'Waxed thread', weight = 50, type = 'item', image = 'nz_thread.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Strong stitching thread' },
nz_glue = { name = 'nz_glue', label = 'Shoe glue', weight = 200, type = 'item', image = 'nz_glue.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Holds a sole on for good' },
nz_laces = { name = 'nz_laces', label = 'Laces', weight = 20, type = 'item', image = 'nz_laces.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'One pair of laces' },
nz_authtag = { name = 'nz_authtag', label = 'Authentic tag', weight = 10, type = 'item', image = 'nz_authtag.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Makes a pair the real thing' },

-- Cleaning
nz_cleaning_kit = { name = 'nz_cleaning_kit', label = 'Cleaning kit', weight = 600, type = 'item', image = 'nz_cleaning_kit.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Brush, cleaner and a cloth. Good for a few pairs' },

-- Display cases (stackable, for a shoe collection)
nz_display = { name = 'nz_display', label = 'Shoe display', weight = 1500, type = 'item', image = 'nz_display.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'A clear case for one pair of sneakers. Stacks' },
nz_display_heel = { name = 'nz_display_heel', label = 'Heel display', weight = 1500, type = 'item', image = 'nz_display_heel.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'A clear case for one pair of heels or ankle boots. Stacks' },
nz_display_boot = { name = 'nz_display_boot', label = 'Boot display', weight = 2200, type = 'item', image = 'nz_display_boot.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'A big clear case: tall boots, or any pair. Stacks' },
