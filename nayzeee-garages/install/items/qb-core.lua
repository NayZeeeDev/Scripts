--[[
  nayzeee-garages — items for QBCore (qb-core/shared/items.lua), used by qb-inventory,
  ps-inventory, lj-inventory and other inventories that read the QBCore item list.
  Paste the entries between the braces of `return { ... }` below into the QBCore.Shared.Items table and copy
  install/items/images/*.png to your inventory's image folder (qb / ps / lj: html/images/).

  - unique = true on keys / fobs / contracts / fake plates: QBCore inventories stack
    non-unique items by name and DROP the metadata of the added one.
  - useable = true: nayzeee-garages registers the use handlers (QBCore.Functions.CreateUseableItem).
  - Qbox (qbx_core) has no item list: use install/items/ox_inventory.lua instead.
  - lockpick / advancedlockpick / screwdriver: keep the entries you already have (do not paste
    them twice); qb-smallresources keeps working for houses / stores (see README.md).
  Item names must match Config.CarLock.items (config/carlock.lua).
]]

return {
  vehicle_key = { name = 'vehicle_key', label = 'Vehicle key', weight = 50, type = 'item', image = 'vehicle_key.png', unique = true, useable = true, shouldClose = true, description = 'A key cut for one vehicle' },
  vehicle_fob = { name = 'vehicle_fob', label = 'Key fob', weight = 80, type = 'item', image = 'vehicle_fob.png', unique = true, useable = true, shouldClose = true, description = 'Remote key of one vehicle' },
  key_blank = { name = 'key_blank', label = 'Key blank', weight = 40, type = 'item', image = 'key_blank.png', unique = false, useable = false, shouldClose = false, description = 'An uncut key, ready for a locksmith' },
  lockpick = { name = 'lockpick', label = 'Lockpick', weight = 100, type = 'item', image = 'lockpick.png', unique = false, useable = true, shouldClose = true, description = 'Opens simple vehicle locks with some skill' },
  advancedlockpick = { name = 'advancedlockpick', label = 'Advanced lockpick', weight = 150, type = 'item', image = 'advancedlockpick.png', unique = false, useable = true, shouldClose = true, description = 'A professional pick set' },
  screwdriver = { name = 'screwdriver', label = 'Flathead screwdriver', weight = 200, type = 'item', image = 'screwdriver.png', unique = false, useable = true, shouldClose = true, description = 'Forces old locks and swaps license plates' },
  hacking_device = { name = 'hacking_device', label = 'Hacking device', weight = 400, type = 'item', image = 'hacking_device.png', unique = false, useable = true, shouldClose = true, description = 'Talks to electronic car locks' },
  fake_plate = { name = 'fake_plate', label = 'Fake plate', weight = 500, type = 'item', image = 'fake_plate.png', unique = true, useable = true, shouldClose = true, description = 'A license plate that is not yours' },
  vehicle_contract = { name = 'vehicle_contract', label = 'Vehicle sale contract', weight = 10, type = 'item', image = 'vehicle_contract.png', unique = false, useable = true, shouldClose = true, description = 'A blank contract to sell a vehicle' },
  signed_contract = { name = 'signed_contract', label = 'Signed sale contract', weight = 10, type = 'item', image = 'signed_contract.png', unique = true, useable = true, shouldClose = true, description = 'Proof of a vehicle sale' },
  immobiliser = { name = 'immobiliser', label = 'Immobiliser', weight = 600, type = 'item', image = 'immobiliser.png', unique = false, useable = true, shouldClose = true, description = 'Fit it to your vehicle: it can no longer be hotwired' },
  ghost_immobiliser = { name = 'ghost_immobiliser', label = 'Ghost immobiliser', weight = 600, type = 'item', image = 'ghost_immobiliser.png', unique = false, useable = true, shouldClose = true, description = 'Fit it to your vehicle: a PIN before the engine starts' },
  hotwire_kit = { name = 'hotwire_kit', label = 'Hotwire kit', weight = 300, type = 'item', image = 'hotwire_kit.png', unique = false, useable = false, shouldClose = true, description = 'Wire strippers and splice clips' },
  signal_reader = { name = 'signal_reader', label = 'Signal reader', weight = 400, type = 'item', image = 'signal_reader.png', unique = false, useable = false, shouldClose = true, description = 'Tunes into the ignition signal of protected vehicles' },
}
