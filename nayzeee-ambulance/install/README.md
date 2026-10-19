# NAYZEEE Ambulance - item install

nayzeee-ambulance uses 48 items (`config/items.lua`). This folder holds them in the
format each inventory expects, and `html/img/items/` holds a 128x128 picture for
every item (`<item_name>.png`).

| File | For |
|---|---|
| `ox_inventory_items.lua` | ox_inventory (ESX, Qbox, QBCore, standalone) |
| `qb_shared_items.lua` | qb-core shared items: qb-inventory, ps-inventory, lj-inventory, qs-inventory, codem-inventory, tgiann-inventory |
| `esx_items.sql` | ESX `items` table: default ESX inventory, and inventories that read the ESX items table |

Item metadata (blood bag type and volume, X-ray film findings) is stored in the
inventory itself when it supports metadata. The plain ESX inventory has no
metadata, so the bridge keeps that data per character in the resource KVP store.
You do not need to set anything up for this.

---

## ox_inventory

1. Open `ox_inventory/data/items.lua`.
2. Copy every entry from `install/ox_inventory_items.lua` into the returned table.
3. Restart the server.

You do not need to copy any pictures. Each entry points at
`nui://nayzeee-ambulance/html/img/items/<name>.png`. If you prefer your own
pictures, put them in `ox_inventory/web/images/` and delete the `client.image`
lines.

Every item has `consume = 0`. nayzeee-ambulance removes the item itself when a
treatment succeeds, so ox_inventory must never take one when it is used. Do not
change it.

## QBCore: qb-inventory, ps-inventory, lj-inventory

1. Paste the entries from `install/qb_shared_items.lua` into
   `qb-core/shared/items.lua`, inside `QBShared.Items`.
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

## Standalone (no framework)

Use ox_inventory and follow the ox_inventory steps. Without any inventory,
items cannot exist. For a quick test server, set
`Config.Bridge.standaloneFreeItems = true`. Every medical item then counts as
always available.

---

## Renaming items

If your server already has an item with another name, for example `firstaid`
instead of `bandage`:

1. In `config/items.lua`, change only the value:
   `bandage = 'firstaid'`. Never change the key.
2. Rename it the same way in the install file you used (`ox_inventory_items.lua`,
   `qb_shared_items.lua` or `esx_items.sql`).
3. Rename the picture in `html/img/items/` to match, e.g. `firstaid.png`. You can
   also set `image = 'bandage.png'` on that item in `Config.ItemDefs`.

## Pictures

The bridge picks the picture for menus in this order:
1. the inventory's own picture, if a file with the item name exists in the
   inventory's picture folder (`Config.Bridge.preferInventoryImages = true`)
2. `html/img/items/<name>.png` from this resource
3. `html/img/items/nza_unknown.png`
