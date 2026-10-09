-- qb-inventory / ps-inventory / lj-inventory: paste into qb-core/shared/items.lua
-- and copy install/images/*.png into qb-inventory/html/images/

nz_shoes = { name = 'nz_shoes', label = 'Shoes', weight = 900, type = 'item', image = 'nz_shoes.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A pair of sneakers' },
nz_shoebox = { name = 'nz_shoebox', label = 'Boxed shoes', weight = 1200, type = 'item', image = 'nz_shoebox.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'A pair of sneakers in their box' },
nz_shoebox_empty = { name = 'nz_shoebox_empty', label = 'Empty shoe box', weight = 300, type = 'item', image = 'nz_shoebox_empty.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'For sneakers' },
nz_heelbox_empty = { name = 'nz_heelbox_empty', label = 'Empty heel box', weight = 300, type = 'item', image = 'nz_heelbox_empty.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'For heels and ankle boots' },
nz_bootbox_empty = { name = 'nz_bootbox_empty', label = 'Empty boot box', weight = 500, type = 'item', image = 'nz_bootbox_empty.png', unique = false, useable = true, shouldClose = true, combinable = nil, description = 'For tall boots' },
