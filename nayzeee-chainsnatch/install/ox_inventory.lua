-- ox_inventory/data/items.lua
-- One item for every chain. Which chain it is, its texture, name and picture live in the metadata.

['nz_chain'] = {
    label = 'Chain',
    weight = 150,
    stack = false,          -- required: every chain is its own item
    close = true,
    consume = 0,
    description = 'Jewellery',
    server = { export = 'nayzeee-chainsnatch.nz_chain' },
},
