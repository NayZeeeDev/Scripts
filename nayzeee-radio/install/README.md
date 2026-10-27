# NAYZEEE Radio - item install

nayzeee-radio uses 7 items (`config/items.lua`): three radios, an earpiece and three
jammers. This folder holds them in the format each inventory expects, and
`html/img/items/` holds a 512x512 picture for every item (`<item_name>.png`).

| File | For |
|---|---|
| `ox_inventory_items.lua` | ox_inventory (ESX, Qbox, QBCore, standalone) |
| `qb_shared_items.lua` | qb-core shared items: qb-inventory, ps-inventory, lj-inventory, qs-inventory, codem-inventory, tgiann-inventory |
| `esx_items.sql` | ESX `items` table: default ESX inventory, and inventories that read the ESX items table |

| Item | What it does when used |
|---|---|
| `radio` | PX-740 patrol handheld: makes it your active radio and raises it |
| `radio_fieldpro` | FX-280 field set (waterproof): same |
| `radio_military` | MX-905 tactical set (waterproof, hardest to jam): same |
| `radio_earpiece` | Puts the earpiece in or takes it out |
| `jammer_pocket` | JX-10: starts placing the jammer |
| `jammer_case` | JX-40: same |
| `jammer_heavy` | JX-90: same |

You only need one radio item to use the radio. When a player carries more than one, the
one they used last is active; before that, `Config.Radios.Priority` decides.

**Already have a `radio` item?** Most servers do: qb-core's shared items and the item
list that comes with ox_inventory both ship one, and so do other radio scripts. Replace
that entry with ours, or keep yours and rename ours (see Renaming items below). Either way,
stop the old radio script, because it registers the same item as usable.

---

## ox_inventory

1. Open `ox_inventory/data/items.lua`.
2. Copy every entry from `install/ox_inventory_items.lua` into the returned table.
3. Restart the server.

You do not need to copy any pictures. Each entry points at
`nui://nayzeee-radio/html/img/items/<name>.png`. If you prefer your own
pictures, put them in `ox_inventory/web/images/` and delete the `client.image`
lines.

Every item has `consume = 0`. A radio or an earpiece is never used up, and
nayzeee-radio takes a jammer out of the inventory itself once it is set down, so
ox_inventory must never take one when it is used. Do not change it. The radios
have `stack = false` so each one stays its own item.

No `client.export` is needed: the radio picks up the use on the server
(an ox_inventory `usingItem` hook).

## QBCore: qb-inventory, ps-inventory, lj-inventory

1. Paste the entries from `install/qb_shared_items.lua` into
   `qb-core/shared/items.lua`, inside `QBShared.Items`. If it already has a
   `['radio']` line, replace it.
2. Copy `html/img/items/*.png` into the inventory's picture folder:
   - qb-inventory: `qb-inventory/html/images/`
   - ps-inventory: `ps-inventory/html/images/`
   - lj-inventory: `lj-inventory/html/images/`
3. Restart the server.

Both qb-inventory versions work: 2.x (exports) and older (Player.Functions).

## Qbox (qbx_core)

Qbox uses ox_inventory. Follow the ox_inventory steps.

## qs-inventory

1. Paste the entries from `qb_shared_items.lua` into
   `qs-inventory/shared/items.lua`. It uses the same format.
2. Copy the pictures into `qs-inventory/html/images/`.

## codem-inventory

1. Add the entries from `qb_shared_items.lua` to codem-inventory's item list.
   On ESX, also run `esx_items.sql`.
2. Copy the pictures into `codem-inventory/html/itemimages/`.

## tgiann-inventory

1. Add the entries from `qb_shared_items.lua` to tgiann-inventory's item list.
2. Copy the pictures into `inventory_images/images/`. tgiann-inventory loads its
   pictures from that resource.

## origen_inventory / core_inventory

Register the items the way the inventory's documentation describes. On QBCore,
use the `qb_shared_items.lua` entries. On ESX, run `esx_items.sql`.

Then copy the pictures:
- origen_inventory: `origen_inventory/html/images/`
- core_inventory: `core_inventory/html/img/`

## ESX default inventory

Run `install/esx_items.sql` on your database. Weights are in kg, with a minimum of
1. If your server uses grams, take the weights from `ox_inventory_items.lua`
(those are in grams).

The JX-90 weighs 28 kg. ESX's default carry limit is 24 kg, so on a stock ESX
server nobody can pick one up. Lower its weight in `esx_items.sql` (and in
`config/items.lua`, so the other install files match) or raise your carry limit.

## Standalone (no framework)

Use ox_inventory and follow the ox_inventory steps. Without any inventory,
items cannot exist and nobody owns a radio. For a quick test server, set
`Config.Bridge.standaloneFreeItems = true` in `config/modules/bridge.lua`.
Everyone then owns all three radios and the earpiece, and has endless jammers.

---

## Renaming items

If your server already has an item with another name, for example `walkie`
instead of `radio`:

1. In `config/items.lua`, change only the value:
   `handheld = 'walkie'`. Never change the key.
2. Rename it the same way in the install file you used (`ox_inventory_items.lua`,
   `qb_shared_items.lua` or `esx_items.sql`).
3. Rename the picture in `html/img/items/` to match, e.g. `walkie.png`. You can
   also set `image = 'radio.png'` on that item in `Config.ItemDefs`.

## Pictures

The pictures are only for your inventory: the radio's own windows do not show
item pictures. ox_inventory loads them from this resource
(`nui://nayzeee-radio/html/img/items/<name>.png`); every other inventory needs
`html/img/items/*.png` copied into its own picture folder, as listed above.
`html/img/items/nzr_unknown.png` is a plain fallback tile.
