# nayzeee-garages — items

Items used by the built-in car lock (keys, fobs, tools), fake plates and sale contracts.
The names below are the defaults of `Config.CarLock.items` (`config/carlock.lua`); if you
rename an item there, rename it in your inventory too.

| Item | Config key | Usable | Stack | What it does |
|---|---|---|---|---|
| `vehicle_key` | `key` | yes | no (metadata) | Physical key of one vehicle (standard profile). Use = lock / unlock it when it is within `ranges.key`. |
| `vehicle_fob` | `fob` | yes | no (metadata) | Remote key of one vehicle (high-end profile). Use = lock / unlock within `ranges.fob`. |
| `key_blank` | `blank` | no | yes | Locksmith material ("Program a key"). |
| `lockpick` | `lockpick` | yes | yes | Opens locked doors of standard vehicles (skill check, may break). |
| `advancedlockpick` | `advancedLockpick` | yes | yes | Better lockpick, also for high-end vehicles. |
| `screwdriver` | `screwdriver` | yes | yes | Forces old locks; needed to fit / remove fake plates. |
| `hacking_device` | `hackingDevice` | yes | yes | Opens / hotwires electronic (high-end) vehicles. |
| `fake_plate` | `fakePlate` | yes | no | Fit a fake plate on a vehicle. |
| `vehicle_contract` | `contract` | yes | yes | Blank sale contract: opens the contract draft. |
| `signed_contract` | `signedContract` | yes | no (metadata) | Signed copy of a sale. |

Lockpicking, hotwiring, fake plates and contracts are only active once their features are
installed; an item whose feature is missing is simply not usable.

## Install

| Inventory | Item definitions | Images go to |
|---|---|---|
| ox_inventory (Qbox, ESX, ox) | `ox_inventory.lua` → `ox_inventory/data/items.lua` | `ox_inventory/web/images/` |
| qb-inventory, ps-inventory, lj-inventory (QBCore) | `qb-core.lua` → `qb-core/shared/items.lua` | `<inventory>/html/images/` |
| qs-inventory / qs-inventory-pro | same fields as `qb-core.lua`, in `qs-inventory/shared/items.lua` | `qs-inventory/html/images/` |
| codem-inventory | its item list (same names / labels; `unique = true` where the table says "no") | `codem-inventory/html/itemimages/` |
| tgiann-inventory | its item list | `inventory_images/images/` |
| origen_inventory | its item list | `origen_inventory/html/images/` |
| core_inventory | its item list | `core_inventory/html/img/` |
| ESX default inventory | `esx_items.sql` (run it once) | — |

Then restart the inventory and nayzeee-garages. `Config.Integrations.inventory = 'auto'`
detects the inventory (`config/config.lua`).

### ox_inventory: `consume = 0`

ox_inventory consumes ONE item on every use of an item whose definition has a
`server.export` unless `consume = 0`. The definitions in `ox_inventory.lua` use
`consume = 0` and `server = { export = 'nayzeee-garages.useNzItem' }`: nayzeee-garages removes
an item only when it should (a lockpick that breaks). Definitions without the export also
work on Qbox / ESX (framework usable items) as long as they have no `consume`.

### Items you already have (lockpick, advancedlockpick, screwdriver)

Most servers already define `lockpick`, `advancedlockpick` and often `screwdriver` (other
scripts use them for houses, stores, ATMs). Do not paste a second definition: in a Lua table
the later entry silently wins and the other script stops working.

- **ox_inventory**: keep your existing entry and only add `consume = 0` and
  `server = { export = 'nayzeee-garages.useNzItem' }` to it. If another script already sets a
  `server.export` / `client.export` on that item, only one of them can run: keep theirs and
  leave the item to them, or route their export to ours yourself.
  Only add the export while the built-in car lock is in use (no other key resource running,
  or `Config.Integrations.keys = "nayzeee"`). Otherwise leave your lockpick entries unchanged:
  with the export, ox hands every use to nayzeee-garages, which then has nothing to do with
  it, and the other key script's lockpick never runs.
- **qb-inventory 2.2+**: keep your entry. nayzeee-garages does not take the item over: an
  `ItemUsed` hook sees every use first, and a use it does not handle (no locked vehicle in
  range) goes on to the script that registered the item (qb-smallresources: houses, stores).
- **QBCore / Qbox with another inventory** (ps-inventory, lj-inventory, older qb-inventory,
  Qbox framework items): keep your entry. QBCore keeps one use handler per item;
  nayzeee-garages remembers the handler registered before its own, passes every use it does
  not handle on to it, and registers it again when nayzeee-garages stops. qb-core may delete
  that handler right after (it drops the items of a stopping resource, in no fixed order):
  if lockpicks stop working for houses / stores after you stopped or restarted
  nayzeee-garages, restart the script that owns the item (`ensure qb-smallresources`).
  If the other script starts after nayzeee-garages it takes the item back; its
  `lockpicks:UseLockpick` client event is then forwarded to the car lock while
  qb-vehiclekeys is not running.

### QBCore inventories: `unique = true`

qb-inventory / ps-inventory / lj-inventory stack items that are not `unique` by name and
throw the metadata of the added item away, so every item with metadata must be `unique`.

### qb-inventory: keys cannot be given from the inventory

qb-inventory's "give" adds the item to the other player with the metadata the giver's client
sends, so a modified client could turn any key into a copy of another one. nayzeee-garages
blocks giving `vehicle_key` / `vehicle_fob` there (a qb-inventory 2.2+ hook; older versions
print a warning: update them). Players hand keys over with the key ring (`/keys` → share),
which moves the real item.

## Images

`images/` holds simple original 100×100 PNG icons, named after the items
(`vehicle_key.png`, `vehicle_fob.png`, `key_blank.png`, `lockpick.png`,
`advancedlockpick.png`, `screwdriver.png`, `hacking_device.png`, `fake_plate.png`,
`vehicle_contract.png`, `signed_contract.png`). Replace them with your own art freely; keep
the file names (or change `image` / `client.image` in the definitions).

## Key metadata

Key and fob items are written by the server only (garage retrieval in physical mode,
locksmiths, `/givekey` gives a temporary key instead, or
`exports['nayzeee-garages']:GiveKeyItem(source, plate)`):

| Field | Meaning |
|---|---|
| `plate` | real plate of the vehicle (trimmed, upper case) |
| `version` | key version of the vehicle when the key was cut; "Change locks" raises the vehicle's version and older keys stop working |
| `kind` | `key` or `fob` |
| `model` | vehicle spawn name (when known) |
| `id` | serial of this key |
| `sig` | server signature of plate / version / kind / id |
| `label` | item label shown by ox_inventory ("Vehicle key · ABC123") |
| `description` | "Sultan · Plate ABC123" (shown by ox_inventory and qb-inventory) |
| `origin` | only on a crime's key: `locksmith` (cut by a back-alley locksmith, or copied from such a key) or `search` (spare key found in a vehicle). It opens the vehicle but gives no tracker access and no owner's nickname. Written by the server, not part of the signature |
| `display = false` | qb-inventory: show only the description, not every field |

A key opens the vehicle when its `plate` matches, its `version` is the vehicle's current
version and its signature is valid. Metadata edited by hand, written by another script, or
copied onto another plate never opens anything (set `Config.CarLock.trustUnsignedKeys = true`
to accept keys without a signature — not recommended). The signing secret is created on the
first start and stored in `nz_settings` (`carlock_secret`); servers sharing one database can
set the same value with the convar `set nz_carlock_secret "<at least 16 characters>"`.

The default ESX inventory has no metadata: the car lock then uses virtual keys (keys live on
the server, given and managed in the Keys app) and never hands out key items. The same
happens when `vehicle_key` / `vehicle_fob` are missing from ox_inventory or the QBCore item
list (the server console says so): add them and restart.

When a vehicle changes owner (garage sale / transfer, admin edit, or any script that writes
the owner column) its key version changes on the next key check: the old owner's key items
stop working and the virtual / temporary keys of other players are removed. Scripts that
transfer vehicles should still call `exports['nayzeee-garages']:Rekey(plate, newOwnerIdentifier)`
right away.
