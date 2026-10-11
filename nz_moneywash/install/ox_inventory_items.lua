-- Paste into ox_inventory/data/items.lua
-- Copy install/images/*.png into ox_inventory/web/images/

['nzmw_wet_cash'] = {
    label = 'Wet Cash', weight = 1500, stack = false, close = true,
    description = 'Freshly washed bills. Still damp, still traceable.',
},
['nzmw_cash_sheets'] = {
    label = 'Uncut Sheets', weight = 1200, stack = false, close = true,
    description = 'Re-serialised notes, not cut yet.',
},
['nzmw_cash_stacks'] = {
    label = 'Clean Stacks', weight = 1000, stack = false, close = true,
    description = 'Banded and ready for the books.',
},
['nzmw_paper_roll'] = { label = 'Press Paper Roll', weight = 800, stack = true },
['nzmw_solvent']    = { label = 'Dye Solvent', weight = 300, stack = true, description = 'Lifts dye-pack ink in the wash.' },
['nzmw_repair_kit'] = { label = 'Machine Repair Kit', weight = 1200, stack = true },
['nzmw_uv_scanner'] = { label = 'UV Serial Scanner', weight = 400, stack = false, description = 'LSPD financial crimes.' },

-- Placement kits. consume = 0: the kit is only removed once the machine is bolted down.
-- If using the item does nothing on your setup, add:  server = { export = 'nz_moneywash.nzmw_washer_kit' }
['nzmw_washer_kit']  = { label = 'Industrial Washer (crate)', weight = 25000, stack = false, consume = 0 },
['nzmw_printer_kit'] = { label = 'Print Press (crate)',       weight = 40000, stack = false, consume = 0 },
['nzmw_cutter_kit']  = { label = 'Guillotine (crate)',        weight = 18000, stack = false, consume = 0 },
