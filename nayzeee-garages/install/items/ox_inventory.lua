--[[
  nayzeee-garages — items for ox_inventory. Paste the entries between the braces of `return { ... }` below into
  ox_inventory/data/items.lua (inside the table it returns) and copy install/items/images/*.png
  to ox_inventory/web/images/. Restart ox_inventory, then nayzeee-garages.

  Why these fields:
  - consume = 0 + server.export: ox calls exports['nayzeee-garages']:useNzItem on use and never
    removes the item itself (without consume = 0, any server.export makes ox consume ONE item
    per use). nayzeee-garages removes an item only when it should (a lockpick that breaks).
  - stack = false on keys / fobs / contracts / fake plates: every one carries its own metadata
    (plate, version, signature...). Never give these items through ox admin commands with
    hand-written metadata: use /givekey or exports['nayzeee-garages']:GiveKeyItem(src, plate).
  - key_blank is a locksmith material: not usable.
  - lockpick / advancedlockpick / screwdriver: most servers already have them. Do NOT paste a
    second entry (the later one silently wins): add `consume = 0` and the `server.export` below
    to your existing entry instead (see README.md, "Items you already have"). Only while the
    built-in car lock is in use (no other key resource running, or Config.Integrations.keys =
    'nayzeee'): otherwise leave your lockpick entries unchanged, or the other key script's
    lockpick never runs.
  Item names must match Config.CarLock.items (config/carlock.lua).
]]

return {
  ['vehicle_key'] = {
    label = 'Vehicle key',
    weight = 50,
    stack = false,
    close = true,
    consume = 0,
    description = 'A key cut for one vehicle',
    client = { image = 'vehicle_key.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },

  ['vehicle_fob'] = {
    label = 'Key fob',
    weight = 80,
    stack = false,
    close = true,
    consume = 0,
    description = 'Remote key of one vehicle',
    client = { image = 'vehicle_fob.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },

  ['key_blank'] = {
    label = 'Key blank',
    weight = 40,
    stack = true,
    close = true,
    description = 'An uncut key, ready for a locksmith',
    client = { image = 'key_blank.png' },
  },

  ['lockpick'] = {
    label = 'Lockpick',
    weight = 100,
    stack = true,
    close = true,
    consume = 0,
    description = 'Opens simple vehicle locks with some skill',
    client = { image = 'lockpick.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },

  ['advancedlockpick'] = {
    label = 'Advanced lockpick',
    weight = 150,
    stack = true,
    close = true,
    consume = 0,
    description = 'A professional pick set',
    client = { image = 'advancedlockpick.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },

  ['screwdriver'] = {
    label = 'Flathead screwdriver',
    weight = 200,
    stack = true,
    close = true,
    consume = 0,
    description = 'Forces old locks and swaps license plates',
    client = { image = 'screwdriver.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },

  ['hacking_device'] = {
    label = 'Hacking device',
    weight = 400,
    stack = true,
    close = true,
    consume = 0,
    description = 'Talks to electronic car locks',
    client = { image = 'hacking_device.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },

  ['fake_plate'] = {
    label = 'Fake plate',
    weight = 500,
    stack = false,
    close = true,
    consume = 0,
    description = 'A license plate that is not yours',
    client = { image = 'fake_plate.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },

  ['vehicle_contract'] = {
    label = 'Vehicle sale contract',
    weight = 10,
    stack = true,
    close = true,
    consume = 0,
    description = 'A blank contract to sell a vehicle',
    client = { image = 'vehicle_contract.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },

  ['signed_contract'] = {
    label = 'Signed sale contract',
    weight = 10,
    stack = false,
    close = true,
    consume = 0,
    description = 'Proof of a vehicle sale',
    client = { image = 'signed_contract.png' },
    server = { export = 'nayzeee-garages.useNzItem' },
  },
}
