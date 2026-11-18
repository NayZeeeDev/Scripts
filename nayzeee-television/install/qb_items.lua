-- QBCore: paste into qb-core/shared/items.lua  (Qbox uses ox_inventory, see ox_inventory_items.lua)
tv_remote    = { name = 'tv_remote',    label = 'TV Remote',        weight = 120,   type = 'item', image = 'tv_remote.png',    unique = true,  useable = true, shouldClose = true, description = 'Paired to a TV' },
tv_flat_32   = { name = 'tv_flat_32',   label = 'Flat TV 32"',      weight = 6000,  type = 'item', image = 'tv_flat_32.png',   unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_flat_42   = { name = 'tv_flat_42',   label = 'Flat TV 42"',      weight = 9000,  type = 'item', image = 'tv_flat_42.png',   unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_flat_55   = { name = 'tv_flat_55',   label = 'Flat TV 55"',      weight = 14000, type = 'item', image = 'tv_flat_55.png',   unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_flat_65   = { name = 'tv_flat_65',   label = 'Flat TV 65"',      weight = 19000, type = 'item', image = 'tv_flat_65.png',   unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_flat_wall = { name = 'tv_flat_wall', label = 'Wall Mount TV',    weight = 12000, type = 'item', image = 'tv_flat_wall.png', unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_crt       = { name = 'tv_crt',       label = 'CRT TV',           weight = 16000, type = 'item', image = 'tv_crt.png',       unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_retro     = { name = 'tv_retro',     label = 'Retro TV',         weight = 11000, type = 'item', image = 'tv_retro.png',     unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_monitor   = { name = 'tv_monitor',   label = 'Desktop Monitor',  weight = 4000,  type = 'item', image = 'tv_monitor.png',   unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_laptop    = { name = 'tv_laptop',    label = 'Laptop',           weight = 2000,  type = 'item', image = 'tv_laptop.png',    unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },
tv_projector = { name = 'tv_projector', label = 'Projector Screen', weight = 25000, type = 'item', image = 'tv_projector.png', unique = true,  useable = true, shouldClose = true, description = 'Place it anywhere' },

-- ESX (no ox_inventory): run once
-- INSERT INTO items (name, label, weight) VALUES
--   ('tv_remote','TV Remote',1),('tv_flat_32','Flat TV 32"',6),('tv_flat_42','Flat TV 42"',9),('tv_flat_55','Flat TV 55"',14),
--   ('tv_flat_65','Flat TV 65"',19),('tv_flat_wall','Wall Mount TV',12),('tv_crt','CRT TV',16),('tv_retro','Retro TV',11),
--   ('tv_monitor','Desktop Monitor',4),('tv_laptop','Laptop',2),('tv_projector','Projector Screen',25);
