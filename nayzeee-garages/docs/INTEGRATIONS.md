# nayzeee-garages — integrations and exports

Everything that talks to another resource lives in an **open file**: plain Lua, no escrow,
one adapter per resource. You can read what each call does, fix it when a vendor renames an
export, or add your own adapter. This page lists, per area, the file to open, what it does,
the resources supported out of the box, the config key, how `'auto'` picks a resource and how
to add your own. The second half is the complete export reference.

General rules for every adapter file:

- Every third-party call is wrapped in `pcall`. A missing or broken resource never throws into
  the garage code; the file prints one warning (more with `Config.Debug = true`) and falls back.
- `'auto'` only looks at resources that are **started**. Start the integrated resources before
  `nayzeee-garages` in `server.cfg` (or at least in the same boot) so detection sees them.
- Objects read from another resource (`QBCore.Functions.*`, `ESX.*`) are function references
  (callable tables), not Lua functions. Never test them with `type(x) == 'function'`; test
  `x ~= nil` and call them inside `pcall`.
- Restart `nayzeee-garages` after editing a file (`ensure nayzeee-garages`).

| Area | Open file(s) | Config key | Section |
|---|---|---|---|
| Framework | `bridge/shared.lua`, `bridge/server/{qb,qbx,esx,common}.lua`, `bridge/client/{qb,qbx,esx,common}.lua` | `Config.Framework` | [1](#1-framework) |
| Inventory | `bridge/server/inventory.lua`, `bridge/client/inventory.lua` | `Config.Integrations.inventory` | [2](#2-inventory) |
| Interaction (target, prompts, NPCs) | `bridge/client/target.lua`, `client/points.lua`, `client/peds.lua` | `Config.Integrations.target`, `settings.interface.interaction`, `Config.Peds` | [3](#3-interaction-target-prompts-npcs) |
| Notifications | `bridge/client/notify.lua` | `Config.Integrations.notify`, `Config.Notify` | [4](#4-notifications) |
| Vehicle keys | `config/carlock.lua`, `shared/carlock.lua`, `bridge/client/keys.lua`, `bridge/server/keys.lua` | `Config.Integrations.keys`, `Config.CarLock.enabled` | [5](#5-vehicle-keys-built-in-car-lock-or-an-external-key-script) |
| Listener files | `bridge/server/listeners.lua`, `bridge/client/listeners.lua` | `Config.CarLock.compat`, `.compatExports`, `.compatAmbient` | [6](#6-listener-files-compatibility-events-and-usable-items) |
| Police dispatch | `bridge/server/dispatch.lua`, `bridge/client/dispatch.lua` | `Config.CarLock.dispatch.system` | [7](#7-police-dispatch) |
| Fuel | `bridge/client/fuel.lua` | `Config.Integrations.fuel` | [8](#8-fuel) |
| Housing | `bridge/server/housing.lua` + `bridge/server/housing/<script>.lua`, `bridge/client/housing.lua`, `install/housing/` | `Config.Integrations.housing` | [9](#9-housing) |
| Phone apps | `server/phone.lua`, `install/phone/` | `Config.Phone` (optional) | [10](#10-phone-garage-apps) |
| Banking / society | `bridge/server/common.lua` (`NZ.Bridge.pay`, `NZ.Bridge.addSocietyMoney`) | `settings.economy.account` (admin panel) | [11](#11-banking-and-society-accounts) |

---------------------------------------------------------------------------------------

## 1. Framework

**Files.** `bridge/shared.lua` detects the framework. One adapter per framework on each side:
`bridge/server/qb.lua`, `qbx.lua`, `esx.lua` and `bridge/client/qb.lua`, `qbx.lua`, `esx.lua`.
Each starts with `if NZ.Framework ~= '<name>' then return end`, so only one of them runs.
`bridge/server/common.lua` and `bridge/client/common.lua` load after them: they build the
framework-free functions (pay, admin check, character name cache, notifications), fill in a
safe fallback for every function an adapter does not define, and wrap every function so an
error logs once (every 30 s) and returns a safe value instead of throwing.

**Supported.** QBCore (`qb-core`), Qbox (`qbx_core`), ESX Legacy (`es_extended`). Without any
of them the resource runs in `standalone` mode (no money, no jobs) and warns in the console.

**Config.** `Config.Framework = 'auto' | 'qbx' | 'qb' | 'esx'` (`config/config.lua`).

**Auto detection.** At load: `qbx_core` first (it also provides `qb-core`), then `qb-core`,
then `es_extended` (state `started` or `starting`). The framework must be ensured before
`nayzeee-garages`. The database layer follows the framework: `player_vehicles` for qb / qbx,
`owned_vehicles` for ESX (`server/db.lua`, `server/migrations.lua`).

**What an adapter provides** (the contract other modules use, `NZ.Bridge`):

```
-- server (bridge/server/<framework>.lua)
NZ.Bridge.getPlayer(src) -> framework player | nil
NZ.Bridge.getIdentifier(src) -> citizenid / ESX identifier | nil
NZ.Bridge.getName(src) -> 'First Last'
NZ.Bridge.getJob(src) / getGang(src) -> { name, label, grade, gradeLabel, onDuty, isBoss } | nil
NZ.Bridge.hasGangs -> boolean
NZ.Bridge.getMoney(src, 'cash'|'bank') -> number
NZ.Bridge.removeMoney(src, account, amount, reason) / addMoney(...) -> boolean
NZ.Bridge.getSourceByIdentifier(identifier) -> src | nil
NZ.Bridge.getOnlinePlayers() -> { { source, identifier, name } }
NZ.Bridge.getJobs() / getGangs() -> { { name, label, grades = { { grade, label, isBoss } } } }
NZ.Bridge.getSharedVehicleType(model, hash) -> 'car'|'sea'|'air'|nil   -- qb / qbx shared vehicles
NZ.Bridge._fw.hasAnyGroup(src, groups) / fetchName(identifier) / searchCharacters(pattern, limit, offset)
-- the adapter calls NZ.Bridge._playerLoaded(src, identifier, name) / _playerUnloaded(src) on
-- character load / logout; common.lua de-duplicates them and fires
-- 'nz:server:playerLoaded' / 'nz:server:playerUnloaded' (src)

-- built by bridge/server/common.lua on top of the above
NZ.Bridge.pay(src, amount, reason) -> boolean, 'cash'|'bank'|nil
NZ.Bridge.addSocietyMoney(society, amount) -> boolean                 -- section 11
NZ.Bridge.isAdmin(src) -> boolean     -- console, ace nayzeee-garages.admin, ServerConfig.AdminGroups
NZ.Bridge.getCharacterName(identifier) -> string                     -- cached, online, then database
NZ.Bridge.searchCharacters(query, limit, offset) -> rows, total
NZ.Bridge.notify(src, message, kind?, title?)                        -- section 4

-- client (bridge/client/<framework>.lua)
NZ.Bridge.isLoggedIn() -> boolean ; getIdentifier() ; getJob() ; getGang()
-- keeps NZ.State.job / NZ.State.gang current and fires the local events
-- 'nz:client:playerLoaded', 'nz:client:playerUnloaded', 'nz:client:jobUpdated', 'nz:client:gangUpdated'
NZ.Bridge.notify(message, kind?, title?)                              -- common.lua: NZ.Notify.show
```

**Your own framework.** A fork that keeps the QBCore or ESX API and tables works by forcing
`Config.Framework = 'qb'` or `'esx'`. For anything else:

1. Copy `bridge/server/qb.lua` and `bridge/client/qb.lua` to `bridge/server/myfw.lua` /
   `bridge/client/myfw.lua`, change the guard to `if NZ.Framework ~= 'myfw' then return end` and
   implement the functions above with your framework's calls.
2. Add both files to `fxmanifest.lua` next to the other adapters (before `common.lua`).
3. Set `Config.Framework = 'myfw'` (a forced value is used as is).
4. Your vehicle table must look like `player_vehicles` (QBCore columns) — the database layer
   uses `owned_vehicles` only for `'esx'`. Columns `nz_*` are added automatically.

---------------------------------------------------------------------------------------

## 2. Inventory

**Files.** `bridge/server/inventory.lua` (`NZ.Inventory`, server: items, metadata, usable items)
and `bridge/client/inventory.lua` (best-effort `hasItem` / `count` for hints; the server always
checks again). Item definitions and images to copy are in `install/items/` (see its README).

**Used by.** Car lock key and fob items (with metadata), crime tools, locksmith materials,
search loot, contracts, signed copies and fake plates.

**Supported.** ox_inventory, qs-inventory-pro, qs-inventory, codem-inventory,
tgiann-inventory, origen_inventory, core_inventory, ps-inventory, lj-inventory, qb-inventory
(all with item metadata), and the framework's own items (ESX / QBCore / Qbox, no metadata).

**Config.** `Config.Integrations.inventory`: `'auto'` | one of the names above | `'framework'`
| `'custom'` | `'none'`.

**Auto detection.** The first **started** resource in the order above, else the framework
items. qb-inventory is checked last because ps / lj / qs may `provide` it. A forced name that
is not started falls back to the framework items with a warning. The choice is made again
when an inventory or the framework (re)starts.

**Metadata.** Without item metadata (ESX default inventory, `'framework'`), the car lock runs in
virtual key mode (`Config.CarLock.keyMode = 'auto'`), and signed contract copies are skipped.

**API** (server):

```
NZ.Inventory.name() -> resource | 'framework' | 'custom' | nil
NZ.Inventory.supportsMetadata() -> boolean
NZ.Inventory.itemDefined(item) -> boolean | nil (cannot tell)
NZ.Inventory.items(src) -> { { slot, name, count, metadata } }
NZ.Inventory.find(src, item, matchFn?) -> { { slot, count, metadata, name } }
NZ.Inventory.count(src, item, metadata?) -> number
NZ.Inventory.hasItem(src, item, count?, metadata?) -> boolean
NZ.Inventory.getSlot(src, slot) -> entry | nil
NZ.Inventory.canCarry(src, item, count, metadata?) -> boolean
NZ.Inventory.addItem(src, item, count, metadata?) -> boolean
NZ.Inventory.removeItem(src, item, count, metadata?, slot?) -> boolean
NZ.Inventory.setMetadata(src, slot, metadata, replace?) -> boolean
NZ.Inventory.registerUsable(item, fn(src, item, slot, metadata), { fallthrough = boolean }?) -> boolean
NZ.Inventory.usableItems() -> { item names }
NZ.Inventory.protect(item) -> boolean     -- metadata only ever comes from the server (key items)
-- client
NZ.Inventory.name() ; NZ.Inventory.count(item) ; NZ.Inventory.hasItem(item, count?)
```

Metadata is compared key by key in this file, never with an inventory's own metadata filter.

**Usable items.** `registerUsable` registers through the inventory's own path: ox_inventory
uses the export named in the item definition (`server = { export = 'nayzeee-garages.useNzItem' }`,
`consume = 0`) plus the framework path; qs / origen use `CreateUsableItem`; the others use the
framework's usable items. Several paths may fire for one use: they are de-duplicated.
`fallthrough = true` is for items other scripts use too (lockpick): on qb-inventory 2.2+ an
`ItemUsed` hook looks first and hands every use it does not handle to the script that
registered the item, which is never taken over. Elsewhere (ps / lj / older qb-inventory, Qbox
framework items) the previous QBCore handler is remembered, called for unhandled uses and
registered again when nayzeee-garages stops (qb-core may delete it right after: restart the
owner script then, see `install/items/README.md`).

**Protected items.** `vehicle_key` / `vehicle_fob` are protected: on qb-inventory 2.2+ an
`ItemMoved` hook refuses giving them from the inventory (the give copies metadata the giver's
client sends). Players hand keys over with the key ring.

**Your own inventory.** Fill the `CUSTOM` table at the top of `bridge/server/inventory.lua`
(`resource`, `metadata`, `items(src)`, `add`, `removeSlot`, `removeName`, `setMeta`, `canCarry`,
optional `usable(name, handler)`) and set `Config.Integrations.inventory = 'custom'`.
`items(src)` returns `{ { slot, name, count, metadata } }`; the write functions return true /
false. On the client, fill `counters.custom(item)` in `bridge/client/inventory.lua` (how many
of `item` the local player carries; only hints depend on it, the server always checks again).

---------------------------------------------------------------------------------------

## 3. Interaction (target, prompts, NPCs)

**Files.**
- `bridge/client/target.lua` (`NZ.Target`): one neutral API over ox_target and qb-target.
- `client/points.lua` (`NZ.Points`): builds the interaction of every location (lib.points,
  prompts, target zones, markers, blips) and the single interaction keybind.
- `client/peds.lua` (`NZ.Peds`): garage NPCs carrying the target options.

**Supported.** ox_target, qb-target. Without a running target resource every location falls
back to prompts.

**Config.**
- `Config.Integrations.target = 'auto' | 'ox_target' | 'qb-target' | 'none'`.
- Admin panel → Settings → Interface → interaction: `'prompt'` (press E), `'target'` or
  `'both'` (`settings.interface.interaction`). Each location can override it in the location
  editor (Interaction section: mode + optional NPC with model and scenario).
- `Config.Peds = { defaultModel, defaultScenario, spawnDistance }` (an empty model in a location
  means `defaultModel`).
- `Config.Keys.interact` (default `E`), `Config.Interaction` (point radii, markers).

**Auto detection.** ox_target first, then qb-target. A configured resource that is not running
falls back to the other one. Target zones, entity options and vehicle options are re-created
when the target resource restarts and removed when nayzeee-garages stops.

**What players get.**
- Prompt mode: `[E] Open garage` / `Store vehicle` while inside a point.
- Target mode: third-eye on the open point or on the location NPC — Open garage / hangar /
  marina, Enter interior, View garage for sale, Open impound, Store vehicle. Drivers still park
  with the `E` prompt; choose `both` to get prompts everywhere.
- A global "Store vehicle" vehicle option in target-mode store zones (only for the vehicle the
  player drove there), and "Impound vehicle" for impound staff.
- Car lock options: "Pick the lock" on locked vehicles, "Search the driver" on dead original
  drivers, "Request the vehicle" for assist jobs, Install / Remove fake plate at the rear of a
  vehicle. Without a target resource the body search and the vehicle request use `[E]`
  prompts, and the fake plate item works on its own.
- Locksmiths follow the same interaction setting (target option or `[E]`, keybind
  `nz_locksmith`).
- NPCs are created locally (not networked) while a player is within `Config.Peds.spawnDistance`.
  A model that does not exist or does not stream in time falls back to a sphere zone with the
  same options.

**API** (client):

```
NZ.Target.resource() -> 'ox_target' | 'qb-target' | nil ; NZ.Target.available() -> boolean
NZ.Target.addSphere(id, coords, radius, options)
NZ.Target.addLocalEntity(id, entity, options)       -- options on one local entity (NPC)
NZ.Target.addVehicleOption(id, option)              -- option on every vehicle
NZ.Target.remove(id)
--   option = { label, icon, distance?, onSelect = function(data) end,
--              canInteract = function(entity, distance, coords) end }
--   onSelect gets { entity, coords, distance } whatever the target resource is
NZ.Peds.sync(specs) ; NZ.Peds.clear() ; NZ.Peds.entity(id) -> ped | nil
NZ.Points.rebuild() ; NZ.Points.clear() ; NZ.Points.canStoreVehicle(vehicle) ; NZ.Points.storeVehicle(vehicle)
```

**Your own target resource.** Add its name to `TARGET_RESOURCES` in `bridge/client/target.lua`
and add a branch for it in the six per-resource functions (`createZone` / `deleteZone`,
`createEntity` / `deleteEntity`, `createVehicleOption` / `deleteVehicleOption`). Convert the
neutral option with a function like `toOx` / `toQb`. Resources that emulate the ox_target or
qb-target exports work without changes.

---------------------------------------------------------------------------------------

## 4. Notifications

**File.** `bridge/client/notify.lua` (`NZ.Notify`). Every notification of the resource ends in
`NZ.Notify.show(kind, message, title?, duration?)`: client code (`NZ.NUI.notify`,
`NZ.Bridge.notify`), the server (`NZ.Bridge.notify(src, ...)` → event `nz:client:notify`) and
the interface (NUI callback `notify`).

**Supported.** ox_lib, the framework's own (QBCore `QBCore:Notify`, Qbox `exports.qbx_core:Notify`,
ESX `esx_notify` on ESX Legacy 1.9+), okokNotify, mythic_notify, pNotify, wasabi_notify,
brutal_notify, lation_ui, t-notify, and a custom function.

> okokNotify, wasabi_notify, brutal_notify and lation_ui are closed source. Their calls follow
> how open-source bridges call them; send one notification of each kind once on a server that
> runs them before you rely on them.

**Config.**
- `Config.Integrations.notify = 'ox_lib' | 'auto' | 'framework' | 'qb' | 'qbx' | 'esx' |
  'okokNotify' | 'mythic_notify' | 'pNotify' | 'wasabi_notify' | 'brutal_notify' | 'lation_ui' |
  't-notify' | 'custom'` (default `ox_lib`).
- `Config.Notify.title` (`''` = none), `.position` (ox_lib position names; `nil` = each player's
  own ox_lib setting; also used for the pNotify layout), `.duration` (ms).
- `Config.Notify.inInterface = true`: while a garage window has mouse focus FiveM draws it above
  every other resource's interface, so the notification would be hidden behind it. With `true`
  it is drawn inside the open window instead (top centre); `false` always uses the integration.

**Auto detection.** `'auto'` = the first running of okokNotify, wasabi_notify, brutal_notify,
lation_ui, t-notify, mythic_notify, pNotify, otherwise ox_lib. `'framework'` = the adapter of
`NZ.Framework`. Whenever the configured resource is not started or its call fails, ox_lib
shows the notification (one console warning).

**Text handling.** Kinds `success | error | info | warning` (aliases `inform`, `primary`, `warn`,
`danger`; anything else shows as info). The message is made plain (control characters removed,
`<` `>` replaced, image syntax broken), at most 300 characters; titles at most 60; duration
clamped to 1–30 s. The same notification twice within 1.5 s is shown once.

**API.**
```
NZ.Notify.show(kind, message, title?, duration?) -> boolean   -- never throws
NZ.Notify.current() -> adapter name used for the next notification
NZ.Notify.custom(kind, message, title, duration)            -- edit for 'custom'
-- server: NZ.Bridge.notify(src, message, kind?, title?)   src 0 = console, -1 = everyone
-- event:  TriggerClientEvent('nz:client:notify', src, { type, message, title?, duration? })
--         also (type, message, title?) or a lone string (info)
```

**Your own notification resource.** Set `Config.Integrations.notify = 'custom'` and fill
`NZ.Notify.custom` at the top of `bridge/client/notify.lua`:

```lua
function Notify.custom(kind, message, title, duration)
  exports['my_notify']:Send({ type = kind, title = title, text = message, time = duration })
  return true   -- false (or an error) = show it with ox_lib instead
end
```

---------------------------------------------------------------------------------------

## 5. Vehicle keys (built-in car lock or an external key script)

**Files.** `config/carlock.lua` (built-in car lock), `shared/carlock.lua` (who is in charge),
`bridge/client/keys.lua` (`NZ.Keys`: give / remove after a garage spawn), `bridge/server/keys.lua`
(`NZ.KeysServer`: server-side key systems and the built-in hand-out). The built-in car lock
itself is documented in `docs/CARLOCK.md`.

**Supported external key scripts.** qbx_vehiclekeys (server side), qb-vehiclekeys,
wasabi_carlock, MrNewbVehicleKeys, qs-vehiclekeys, Renewed-Vehiclekeys, vehicles_keys (jaksam).

**Config.**
- `Config.CarLock.enabled` (master switch of the built-in car lock).
- `Config.Integrations.keys = 'auto' | 'nayzeee' | 'none' | <one of the names above>`.
- Admin panel → Settings → Vehicles → give keys (`settings.vehicles.giveKeys`).

**Who is in charge (`'auto'`).** The built-in car lock runs when `Config.CarLock.enabled` is
true and no other key resource of the list is started when nayzeee-garages starts. A key
resource that starts after nayzeee-garages while the server boots (no player connected yet)
also takes over: the start order inside a `[category]` of `server.cfg` is not guaranteed. The
decision is published in `GlobalState.nzCarLockOther` so every client agrees, and the
compatibility listeners go quiet. A key resource started later, with players online, only
prints a warning: start it before nayzeee-garages, or set `Config.Integrations.keys` to its
name. `'nayzeee'` forces the built-in car lock (not recommended while another key script
runs); any other value turns the built-in car lock off.

**What happens on a garage retrieve.**
- Built-in car lock: the server hands the key out once it validated the spawned entity
  (`NZ.KeysServer.give` → `NZ.CarLock.onVehicleOut`): a key item in physical mode when the
  player has no valid one, a temporary key otherwise; spawner vehicles get a temporary key.
- qbx_vehiclekeys: the server calls `exports.qbx_vehiclekeys:GiveKeys(src, entity)`.
- Client-side key scripts: `bridge/client/keys.lua` calls the script's own give / remove. For
  a vehicle another script delivered (phone valet) the server sends `nz:client:giveKeys
  (netId, plate)` to the player, which runs the same give.
- `'none'`, an unknown name, a resource that is not started, or Admin panel → Settings →
  Vehicles → give keys turned off: no keys.

**Your own key script.**
1. Add an adapter to `adapters` in `bridge/client/keys.lua`:
   ```lua
   adapters['my_keys'] = {
     give = function(vehicle, plate) exports.my_keys:GiveKey(plate) return true end,
     remove = function(vehicle, plate) exports.my_keys:RemoveKey(plate) return true end,
   }
   ```
2. Add `'my_keys'` to `KEY_RESOURCES` in `bridge/client/keys.lua` **and**
   `bridge/server/keys.lua` (the server also needs it in `SERVER_SIDE` and a branch in
   `KeysServer.give` / `remove` when the script only has server exports).
3. Set `Config.Integrations.keys = 'my_keys'` (or add it to `OTHER_KEY_RESOURCES` in
   `shared/carlock.lua` so `'auto'` hands over to it when it runs).

**Other scripts' key calls while the built-in car lock runs.** The listener files (section 6)
answer the events and exports of the scripts above while they are not running. Calls that can
never be intercepted:
- scripts that check `GetResourceState('<key script>') == 'started'` before calling (most bridge
  libraries) — they never reach the shims;
- scripts that looked an export up before nayzeee-garages started and cached the failure, and
  scripts that keep a reference after nayzeee-garages restarts: restart them after
  nayzeee-garages;
- item-based key systems (a `vehiclekeys` item).

For those, start nayzeee-garages first, point the script's key option at nayzeee-garages, or
change its calls to `exports['nayzeee-garages']:GiveKey(src, plate|netId)` / `RemoveKey` /
`HasKey` (server) or `GiveKey(vehicle)` / `HasKey(plate|vehicle)` (client), and
`Rekey(plate, newOwner)` after an ownership change. On Qbox without qbx_vehiclekeys keep
`compat` and `compatExports` on: qbx_core (`/car`, persistence), qbx_vehicleshop and qbx_police
call `exports.qbx_vehiclekeys` unconditionally. Advanced: `provide 'qb-vehiclekeys'` in
`fxmanifest.lua` makes state-checking scripts see a running qb-vehiclekeys; `ensure` /
`restart qb-vehiclekeys` then act on nayzeee-garages, and it must never be added while
qb-vehiclekeys or qbx_vehiclekeys is installed. Never provide `qbx_vehiclekeys`.

---------------------------------------------------------------------------------------

## 6. Listener files (compatibility events and usable items)

**Files.** `bridge/server/listeners.lua` and `bridge/client/listeners.lua`. Open your own
mappings at the bottom of each file.

**Usable items** (server file, table `USABLE`): `vehicle_key` / `vehicle_fob` (toggle the lock;
a fob far from its vehicle opens the key ring), `lockpick`, `advancedlockpick`, `screwdriver`,
`hacking_device` (crime tools, `fallthrough`: other scripts keep their use), `fake_plate`,
`vehicle_contract`, `signed_contract`. Each item is registered through
`NZ.Inventory.registerUsable` only when its handler exists; car lock items only while the
built-in car lock runs. Items are never consumed here. Names come from `Config.CarLock.items`.

**Compatibility** (only with the built-in car lock, `Config.CarLock.compat = true`, and only
for key scripts that are **not** running; a script that starts later takes its names back):

| Script | Server net events (sent by clients) | Client events | Export shims (server / client) |
|---|---|---|---|
| qb-vehiclekeys | `qb-vehiclekeys:server:AcquireVehicleKeys`, `GiveVehicleKeys`, `RemoveVehicleKeys`, `removeKeys`, `setVehLockState`, `breakLockpick`; QBCore callbacks `GetVehicleKeys`, `checkPlayerOwned` | `vehiclekeys:client:SetOwner`, `qb-vehiclekeys:client:AddKeys`, `RemoveKeys`, `GiveKeys`, `ToggleEngine`, `lockpicks:UseLockpick` | `GiveKeys`, `RemoveKeys`, `HasKeys` / `HasKeys`, `addNoLockVehicles`, `removeNoLockVehicles` |
| qbx_vehiclekeys | — | — | `GiveKeys`, `RemoveKeys`, `HasKeys`, `SetLockState`, `IsPlayerNearVehicle` / `HasKeys` |
| wasabi_carlock | — | — | `GiveKey`, `RemoveKey`, `HasKey` / + `GetAllKeys` |
| MrNewbVehicleKeys | — | — | `GiveKeysByPlate`, `RemoveKeysByPlate`, `HasKeysByPlate`, `GiveKeys`, `RemoveKeys`, `HaveKeys` / + `GetPlayerKeyList` |
| qs-vehiclekeys | — | — | `GiveServerKeys`, `RemoveServerKeys` / `GiveKeys`, `RemoveKeys`, `GetKey`, `RemoveKeysAuto` |
| Renewed-Vehiclekeys | — | — | `addKey`, `removeKey`, `hasKey` (both sides) |
| vehicles_keys (jaksam) | `vehicles_keys:selfGiveVehicleKeys`, `selfGiveCurrentVehicleKeys`, `selfRemoveKeys` | — | `giveVehicleKeysToPlayerId`, `removeKeysFromPlayerId`, `giveVehicleKeysToIdentifier`, `removeKeysFromIdentifier`, `isPlayerOwnerOfVehiclePlate`, `refreshPlayerOwnedVehicles`, `getIdentifierKeys`, `getPlayerIdKeys` / `doesPlayerOwnPlate`, `getOwnedVehiclePlates`, `toggleClosestVehicleLock` |
| cd_garage | — | `cd_garage:AddKeys`, `cd_garage:RemoveKeys` | — |

Rules:
- Server exports are trusted server code: they map straight to temporary keys
  (`NZ.CarLock.grantTemp` reason `compat`), `revokeTemp`, `hasKey`, `setLocked`.
- Everything a **client** sends goes through `NZ.CarLock.compatRequest`: a temporary key only,
  for a vehicle the player sits in or stands next to (`ranges.compat`), never another player's
  owned vehicle, NPC traffic only with `Config.CarLock.compatAmbient = true`, rate limited. A
  key allowed through a garage share or fleet access ends with that access. Lending
  (`GiveVehicleKeys` / `GiveKeys`) needs a key that is not temporary; in physical mode a key
  item is handed over (owners may lend a temporary key).
- Synchronous client "has key" exports answer from the local key cache.
- `lockpicks:UseLockpick` (qb-smallresources) is forwarded to the car lock's lockpick while
  qb-vehiclekeys is not running.
- `Config.CarLock.compatExports = false` turns the export shims off (events stay).

**Your own mappings.** At the bottom of each file:

```lua
-- server: a client-sent event of a key script that is not running
onEvent('qb-vehiclekeys', 'my_shop:server:giveKeys', function(src, plate)
  clientRequest(src, { action = 'acquire', plate = plate })
end)
-- server: exports answered for a resource name of ALIASES
provideExports('wasabi_carlock', { GiveKey = function(src, plate) return give(src, plateArg(src, plate)) end })
-- client: an event another script triggers locally
onEvent('qb-vehiclekeys', 'my_job:client:keys', function(plate) acquire(plate) end)
```

A new alias (a resource name that is not in `ALIASES`) must be added to `ALIASES` in that file.

---------------------------------------------------------------------------------------

## 7. Police dispatch

**Files.** `bridge/server/dispatch.lua` (`NZ.Dispatch.alert`, picks the system, builds the
alert) and `bridge/client/dispatch.lua` (client-side systems and the `internal` alert).

**Used by.** Crime actions (lockpick, hotwire, search, robbery, car alarms), illegal locksmith
services, fake plate installs, and other resources through the `SendDispatch` export.

**Supported.** wasabi_mdt, rcore_dispatch, cd_dispatch (cd_dispatch3d too), qs-dispatch,
core_dispatch, ps-dispatch (2.x and 3.x), `internal`, `custom`, `none`.

**Config.** `Config.CarLock.dispatch`: `system`, `jobs`, `blip` + per-kind `blips`, `codes`,
`wasabiTypes`, `cooldown` (one alert per player and vehicle), `sound`.

**Auto detection.** At send time (cached 5 s, reset when one of them starts or stops):
wasabi_mdt, rcore_dispatch, cd_dispatch3d / cd_dispatch, qs-dispatch, core_dispatch,
ps-dispatch (last, other systems emulate it), else `internal`. A forced system that is not
running uses `internal`.

**Delivery.**
- From the server: wasabi_mdt, rcore_dispatch, core_dispatch, qs-dispatch, ps-dispatch 3.x
  (`SendTargetedAlert` to the on-duty receivers).
- From the offender's client (their alert API is client side; the payload is built by the
  server): ps-dispatch 2.x and cd_dispatch. Without an offender they use their server path
  (ps-dispatch 2.x `ps-dispatch:server:notify`, cd_dispatch's event). A client that reports a
  failure gets the alert sent through `internal` instead.
- `internal`: on-duty players of `jobs` get a notification and a timed blip (radius, flash,
  sound).
- Coordinates come from the server (the offender's server ped or the vehicle). Street and model
  text from the client is display text only and stripped of markup before any system sees it;
  officers' clients replace it with their own lookup for `internal` alerts
  (`streetFromClient` / `modelFromClient`).

**Alert table** (`NZ.Dispatch.alert(src|nil, alert)` / export `SendDispatch`):

```lua
{ kind = 'theft'|'lockpick'|'hotwire'|'search'|'robbery'|'alarm'|'locksmith'|'fakeplate'|<any>,
  code?, title?, message?, coords? (required without an offender), plate?, model?, modelHash?,
  color?, street?, streetFromClient?, modelFromClient?, priority? (1 high .. 3 low), jobs?,
  blip? = { sprite, color, scale, seconds, radius, flash } }
```

Missing fields come from the config and the kind (translated title, a message built from
colour, model and plate).

**Your own dispatch.** Set `Config.CarLock.dispatch.system = 'custom'` and fill `CUSTOM.server`
in `bridge/server/dispatch.lua` (return true when sent). If your system's API is client side,
set `CUSTOM.client = true` there and fill `CUSTOM.client` in `bridge/client/dispatch.lua`: it
then runs on the offender's client whenever there is one.

---------------------------------------------------------------------------------------

## 8. Fuel

**File.** `bridge/client/fuel.lua` (`NZ.Fuel.get(vehicle) -> 0-100`, `NZ.Fuel.set(vehicle, value)`,
`NZ.Fuel.resource()`). Used when a vehicle is stored and spawned.

**Supported.** ox_fuel and Renewed-Fuel (state bag `fuel`), LegacyFuel, cdn-fuel, ps-fuel,
lj-fuel, okokGasStation, qs-fuelstations, ti_fuel (exports `GetFuel` / `SetFuel`), GTA natives.

**Config.** `Config.Integrations.fuel = 'auto' | <name> | 'native'`.

**Auto detection.** The first started of ox_fuel, LegacyFuel, cdn-fuel, ps-fuel, lj-fuel,
okokGasStation, qs-fuelstations, Renewed-Fuel, ti_fuel, else the natives. A failed call falls back to the natives; the native fuel level is always set as well.

**Your own fuel script.** Add its name to `FUEL_RESOURCES` and to `KIND` with `'statebag'` (it
reads `Entity(vehicle).state.fuel`) or `'export'` (it has `GetFuel(vehicle)` / `SetFuel(vehicle,
value)`). Another API: add a branch in `Fuel.get` / `Fuel.set`.

---------------------------------------------------------------------------------------

## 9. Housing

**Files.** `bridge/server/housing.lua` (`NZ.Housing` core), one loader per script in
`bridge/server/housing/` (qb, ps, qs, esx, loaf, vms, bcs, tk, rtx, rx, nolag),
`bridge/client/housing.lua` (refresh hints, client exports), files to copy into housing
scripts in `install/housing/`.

**Supported.** qb-houses, ps-housing, qs-housing, esx_property, loaf_housing, rtx_housing,
bcs_housing, RxHousing (automatic); vms_housing, tk_housing, nolag_properties (need a small file
or edit). Steps, convars and limits per script: **`install/housing/README.md`**.

**Config.** `Config.Integrations.housing = 'auto' | 'none' | <resource or prefix> | { list }`.
Server convars: `nayzeee_housing_hooked`, `nayzeee_housing_hook_range`,
`nayzeee_housing_loaf_keys`, `nayzeee_housing_nolag_lockdown`, `nayzeee_housing_nolag_society`.

**Auto detection.** Every supported script that is started (qb-houses is skipped while
qs-housing runs: same tables). Data is read again every 5 minutes, on the scripts' own events,
on resource restarts and through `RefreshHousing`.

**Your own housing script.** Without code: call the server exports `RegisterHouseGarage`,
`SetHouseAccess`, `RemoveHouseGarage` (use your own id prefix, e.g. `myhousing:12`), and the
client exports `OpenHouseGarage` / `StoreHouseGarage` if your script draws its own garage
interaction (`hidden = true`). As a loader: add `bridge/server/housing/myhousing.lua` with
`NZ.Housing.addLoader({ prefix, resources, load, check?, authoritative?, blocked?, anchors?,
hook?, create?, trustCoords?, numericIds?, interval?, autoSkip?, startDelay? })` (the full
definition is documented above `Housing.addLoader`; `bridge/server/housing/qb.lua` is a short
example) and list the file in `fxmanifest.lua` after `bridge/server/housing.lua`.

---------------------------------------------------------------------------------------

## 10. Phone garage apps

**Files.** `server/phone.lua` (`NZ.Phone`, server exports and net events) and the files to copy
into the phones in `install/phone/`. Steps and data shapes: **`install/phone/README.md`**.

**Supported.** lb-phone (Garage app, QBCore / Qbox / ESX: vehicle list, valet, map button),
npwd_qbx_garages, npwd_qb_garage, npwd_esx_garage (list and map button). qs-smartphone(-pro),
yseries, gksphone, okokPhone and high-phone are unconfirmed: use their stock framework garage
option with the valet off, or wire `install/phone/generic/nayzeee_phone.lua`.

**Config.** `Config.Phone = { valet, valetTypes, claimTimeout, applyData, maxPending,
listShared, hints }` in `config/config.lua` (`server/phone.lua` uses the same defaults for a
missing value).

**How it works.** The phone calls `GetPhoneVehicles`, `ClaimVehicleForValet`,
`MarkValetSpawned`, `ReleaseValetClaim` (export reference below). A valet claim follows the
rules of a garage retrieve and the delivered vehicle is tracked like one (keys from the
built-in car lock or the key script in use, duplicate protection, mileage). The phone does not need a
config key: there is nothing to detect. At start the console prints a hint for an installed
phone that never called the exports (`Config.Phone.hints`).

**Your own phone.** Call the four exports from the phone's server garage code (see
`install/phone/generic/nayzeee_phone.lua` for a helper that returns QBCore / ESX shaped rows).
Phone client files report with `TriggerServerEvent('nz:phone:spawned', plate, netId)` /
`('nz:phone:failed', plate)`.

---------------------------------------------------------------------------------------

## 11. Banking and society accounts

**File.** `bridge/server/common.lua`.

- **Player money**: `NZ.Bridge.pay(src, amount, reason)` charges through the framework adapter
  with `settings.economy.account` (admin panel: `bank`, `cash`, or `both` = cash when it covers
  the whole amount, else bank). Contracts use `Config.Contracts.account`, locksmiths
  `Config.CarLock.locksmithAccount`, search loot `Config.CarLock.search.money.account`.
- **Society accounts**: `NZ.Bridge.addSocietyMoney(society, amount)` deposits impound fees into
  the impound's `society` (location editor). It tries, among the started resources, in order:
  qb-banking (`AddMoney`), Renewed-Banking (`addAccountMoney`), qb-management (`AddMoney`),
  esx_addonaccount (`society_<name>` shared account), and stops at the first success. A
  `society_` prefix is accepted. No config key: the first one that accepts the deposit wins;
  when none does, the console says so.

**Your own banking script.** Add a block in `NZ.Bridge.addSocietyMoney` before the final
warning:

```lua
if started('my_banking') and tryBank('my_banking', function()
  return exports['my_banking']:AddSocietyMoney(account, amount, reason)
end) then
  return true
end
```

`tryBank` counts `nil` / `true` as success and `false` or an error as failure.

---------------------------------------------------------------------------------------

## 12. Export reference

`exports['nayzeee-garages']:Name(...)`. Every export validates its arguments: a bad argument
returns `false` / `nil` (often with an error message as the second value), never an error.
Plates are compared trimmed and upper case. "vehicle" in the car lock exports means a plate,
a server entity handle or a network id.

### 12.1 Server exports

**Vehicles and garages** (`server/exports.lua`; a runtime error returns `nil, 'Something went
wrong'`):

| Export | Arguments | Returns |
|---|---|---|
| `GetVehicle` | `plate` | vehicle row (without damage data) or `nil` |
| `GetPlayerVehicles` | `identifier` | list of vehicle rows (empty when invalid) |
| `AddVehicle` | `identifier, model (name or hash), plate?, props?, garageKey?, vehicleType?` (`'car'\|'sea'\|'air'`) | `plate` or `nil, error`. Generates a unique plate when none is given; default garage = the first enabled public personal garage of that type |
| `SetVehicleGarage` | `plate, garageKey` (`'L<id>'`, `'G<id>'`, `'H<houseId>'`) | `true` or `false, error`. Parks it there (clears an impound); refused while it is out |
| `ImpoundVehicle` | `plate, { locationId?, reason?, fee?, hours?, retrievable?, netId?, byName? }` | `ok, error`. With `netId` the entity is deleted at once (no tow truck) |
| `AddServiceRecord` | `plate, { item, mileage?, shop?, at? }` | `true` or `false, error` |
| `AddOwnershipRecord` | `plate, { identifier?, name?, via?, at?, price? }` | `true` or `false, error` |
| `IsVehicleOut` | `plate` | `boolean` (out and its entity exists) |
| `GetLocations` | `kind?` (`'garage'\|'job'\|'private'\|'impound'`) | copy of the database locations (houses excluded) |

```lua
local garages = exports['nayzeee-garages']
local plate = garages:AddVehicle(xPlayer.identifier, 'sultan3', nil, nil, 'L12')
garages:SetVehicleGarage('ABC123', 'L4')
garages:ImpoundVehicle('ABC123', { locationId = 5, reason = 'Parking', fee = 750, hours = 2, retrievable = true })
garages:AddServiceRecord('ABC123', { item = 'Oil change', mileage = 1520.4, shop = 'Benny\'s' })
garages:AddOwnershipRecord('ABC123', { identifier = 'CID42', via = 'dealership', price = 85000 })
if garages:IsVehicleOut('ABC123') then ... end
local impounds = garages:GetLocations('impound')
```

**House garages** (`server/exports.lua`, details in `install/housing/README.md`):

| Export | Arguments | Returns |
|---|---|---|
| `RegisterHouseGarage` | `houseId, { name, coords = vec4, spawn = vec4?, store = vec4?, hidden = bool? }` | `ok, error` |
| `RemoveHouseGarage` | `houseId` | `ok` |
| `SetHouseAccess` | `houseId, identifiers` (list, `{ [identifier] = true }` map, or JSON) | `ok, error` |
| `RefreshHousing` | `resource?` (resource name or prefix; `nil` = all) | `ok, error` |

```lua
garages:RegisterHouseGarage('myhousing:12', { name = 'Grove St 1', coords = vec4(-14.2, -1441.1, 31.1, 0.0) })
garages:SetHouseAccess('myhousing:12', { 'CID1', 'CID2' })
garages:RefreshHousing('qs-housing')
```

**Phone garage apps** (`server/phone.lua`, shapes in `install/phone/README.md`):

| Export | Arguments | Returns |
|---|---|---|
| `GetPhoneVehicles` | `source` | `PhoneVehicle[]` or `nil, error` |
| `ClaimVehicleForValet` | `source, plate` | `ValetData` or `nil, error` (marks it out, starts a delivery claim) |
| `MarkValetSpawned` | `source, plate, netId` | `true` or `false, error` (plate and model must match) |
| `ReleaseValetClaim` | `source, plate` | `true` or `false, error` (puts it back; refused while a copy exists) |

```lua
local data, err = exports['nayzeee-garages']:ClaimVehicleForValet(source, plate)
```

**Built-in car lock** (`server/carlock/exports.lua`; server code is trusted, so there are no
distance checks; a fake plate text near the player maps to the real plate; an error returns
`false`). These work on the built-in key store: while another key script is in charge
(section 5), use that script's exports instead.

| Export | Arguments | Returns |
|---|---|---|
| `HasKey` | `src, vehicle` | `boolean, kind` (`'temp'\|'item'\|'virtual'\|'owner'`) |
| `GiveKey` | `src, vehicle, hours?` | `boolean` — temporary key (reason `export`, default `Config.CarLock.tempKeyHours`) |
| `RemoveKey` | `src, vehicle` | `boolean` — removes that player's temporary key |
| `GiveKeyItem` | `src, vehicle` | `boolean, error?` — physical mode: a signed key / fob item for the current key version |
| `GetKeyVersion` | `plate` | `integer` or `nil` (invalid plate or the database cannot be read) |
| `Rekey` | `plate, keepIdentifier?` | new version or `nil` — older key items stop working; virtual and temporary keys of everyone but `keepIdentifier` are removed. Call it after your script changes an owner |
| `SetVehicleLocked` | `netId\|entity, locked` | `boolean` (with lock feedback) |
| `IsVehicleLocked` | `netId\|entity` | `boolean` |
| `SendDispatch` | `src\|nil, alert` (or `SendDispatch(alert)`) | `boolean` — police alert through the configured system (section 7); `alert.coords` required without an offender |

```lua
local nz = exports['nayzeee-garages']
nz:GiveKey(source, NetworkGetNetworkIdFromEntity(vehicle))      -- job / rental vehicle
nz:GiveKeyItem(source, 'ABC123')                                -- dealership, physical keys
nz:Rekey('ABC123', newOwnerCitizenId)                           -- after your own transfer
nz:SetVehicleLocked(netId, true)
nz:SendDispatch(source, { kind = 'theft', coords = GetEntityCoords(vehicle), plate = 'ABC123' })
```

**Impound tow truck** (`server/towtruck.lua`):

| Export | Arguments | Returns |
|---|---|---|
| `StartTow` | `netId, officerSrc?` | `started, reason` — an NPC flatbed collects the vehicle, which is deleted afterwards or on any failure. On `false` (`'disabled'\|'entity'\|'type'\|'occupied'\|'busy'\|'runner'\|'config'\|'state'\|'error'`) nothing happened: delete the vehicle yourself if it must go |

```lua
local started, why = exports['nayzeee-garages']:StartTow(netId, source)
if not started then DeleteEntity(NetworkGetEntityFromNetworkId(netId)) end
```

**Inventory hook** (`bridge/server/inventory.lua`): `useNzItem(event, item, inventory, slot)` is
not meant to be called by scripts. ox_inventory calls it for item definitions with
`server = { export = 'nayzeee-garages.useNzItem' }` (see `install/items/ox_inventory.lua`).

### 12.2 Client exports

| Export | File | Arguments | Returns |
|---|---|---|---|
| `OpenGarage` | `client/garage.lua` | `locationId?` (location id or house garage) | `true` (opens asynchronously; nearest garage when nil) |
| `StoreVehicle` | `client/garage.lua` | `locationId?` | `true` (nearest store point when nil) |
| `OpenImpound` | `client/impound.lua` | `locationId?` | `true` (nearest impound when nil) |
| `OpenImpoundForm` | `client/impound.lua` | — | `true` (impound form for the closest vehicle; impound staff) |
| `OpenAdmin` | `client/admin.lua` | `page?` | — (admins only; the server checks) |
| `IsInsideInterior` | `client/interior.lua` | — | `boolean` |
| `OpenHouseGarage` | `bridge/client/housing.lua` | `houseId, { name? }?` | `boolean` (request accepted; stores instead when driving) |
| `StoreHouseGarage` | `bridge/client/housing.lua` | `houseId, data?` | `boolean` |
| `RefreshHouseGarages` | `bridge/client/housing.lua` | — | `true` |
| `HasKey` | `client/carlock/lock.lua` | `plate\|vehicle` | `boolean` (cached answer; asks the server when the caller can wait) |
| `ToggleLock` | `client/carlock/lock.lua` | `vehicle?` | `true` (the server picks the vehicle and checks the key and range) |
| `ToggleEngine` | `client/carlock/lock.lua` | — | `boolean` (driver seat; the server checks the key) |
| `GiveKey` | `client/carlock/lock.lua` | `vehicle` | `boolean` (request sent) — temporary key for a vehicle the player sits in / stands next to, same rules as compat events; off with `Config.CarLock.clientGiveKeyExport = false` |
| `OpenKeys` | `client/carlock/keysapp.lua` | `plate?` | `true` (opens the key ring, on that key when given) |

```lua
exports['nayzeee-garages']:OpenGarage()
exports['nayzeee-garages']:OpenHouseGarage('myhousing:12', { name = 'Grove St 1' })
if exports['nayzeee-garages']:HasKey(GetVehiclePedIsIn(PlayerPedId(), false)) then ... end
exports['nayzeee-garages']:GiveKey(vehicle)
exports['nayzeee-garages']:OpenKeys('ABC123')
```

The `HasKey`, `ToggleLock`, `ToggleEngine`, `GiveKey` and `OpenKeys` client exports, and the car
lock commands and keybinds, only do something while the built-in car lock runs.

### 12.3 Exports answered for other resource names

While the built-in car lock runs and a key script is **not** running, nayzeee-garages also
answers that script's exports (`exports['qb-vehiclekeys']:GiveKeys(...)` and the others listed
in section 6), with the limits described in section 5. Turn this off with
`Config.CarLock.compatExports = false`.
