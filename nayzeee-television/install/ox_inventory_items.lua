-- Paste into ox_inventory/data/items.lua
-- consume = 0 keeps the item until the TV is actually placed (the script removes it on confirm)

['tv_remote'] = {
    label = 'TV Remote', weight = 120, stack = false, close = true, consume = 0,
    description = 'Paired to a TV. Set it down and it stays with the TV.',
    server = { export = 'nayzeee-television.useItem' },
},
['tv_flat_32'] = {
    label = 'Flat TV 32"', weight = 6000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_flat_42'] = {
    label = 'Flat TV 42"', weight = 9000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_flat_55'] = {
    label = 'Flat TV 55"', weight = 14000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_flat_65'] = {
    label = 'Flat TV 65"', weight = 19000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_flat_wall'] = {
    label = 'Wall Mount TV', weight = 12000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_crt'] = {
    label = 'CRT TV', weight = 16000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_retro'] = {
    label = 'Retro TV', weight = 11000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_monitor'] = {
    label = 'Desktop Monitor', weight = 4000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_laptop'] = {
    label = 'Laptop', weight = 2000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
['tv_projector'] = {
    label = 'Projector Screen', weight = 25000, stack = false, close = true, consume = 0,
    server = { export = 'nayzeee-television.useItem' },
},
