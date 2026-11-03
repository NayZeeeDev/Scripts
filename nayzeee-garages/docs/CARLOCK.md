# Built-in car lock, crime tools, contracts, fake plates and impound tow

Owner request (verbatim intent): a car lock system inside the garage script with physical and
virtual keys, remote locking and ignition, security profiles, locksmith services, key sharing,
a vehicle tracker, NPC interactions (rob drivers at gunpoint, recover keys from the dead
original driver, assistance for authorized jobs), vehicle searching, police alerts (Wasabi MDT
V2, ps-dispatch, cd_dispatch, rcore_dispatch, internal) with native or custom alarms, and an
admin command to grant a key. Plus open integration files (framework, inventory, interaction,
listener, bridges, client/server exports), an NPC flatbed tow truck for police impounds, car
sale contracts, fake plates and a flathead screwdriver.

Everything is original work. Everything is open Lua (no escrow). All user-facing strings go
through `L()` (Lua) / `t()` (NUI). NUI screens use the owner's UI style (docs/UI_KIT.md).

---------------------------------------------------------------------------------------

## 1. Configuration (`config/carlock.lua`, shared; already written — read it)

`Config.CarLock` (enabled, key mode, items, keybinds, commands, ranges, animations, sounds,
ignition rules, security profiles, hotwire, lockpicking, search loot, NPC behaviour,
locksmiths, tracker, dispatch, alarms, admin command), `Config.Tow` (impound tow truck),
`Config.Contracts`, `Config.FakePlates`. Server-only values (loot money ranges are fine to
share) — nothing secret lives there.

Key mode (`Config.CarLock.keyMode`): `'auto'` = physical when an inventory bridge with
metadata support is detected, else virtual · `'physical'` · `'virtual'`.

## 2. Module layout and namespaces

Namespaces are declared in `shared/init.lua` (server and client have separate tables with the
same names where marked "both").

| File | Namespace | Purpose |
|---|---|---|
| `shared/carlock.lua` | `NZ.CarLock` (both) | profile resolution: `NZ.CarLock.profileOf(model, class)` → profile name + table; helpers shared by both sides |
| `bridge/server/inventory.lua`, `bridge/client/inventory.lua` | `NZ.Inventory` (both) | open inventory integration (§4) |
| `bridge/server/dispatch.lua`, `bridge/client/dispatch.lua` | `NZ.Dispatch` (both) | open police alert integration (§6) |
| `bridge/server/listeners.lua`, `bridge/client/listeners.lua` | (local) | open listener file: compatibility events of other key scripts, item use hooks (§5) |
| `server/carlock/keys.lua` | `NZ.CarLock` (server) | key store and rules (§3) |
| `server/carlock/main.lua` | `NZ.CarLock` | callbacks: lock, engine, give / revoke / manage keys, admin command |
| `server/carlock/crime.lua` | `NZ.CarLock` | lockpick, hotwire, search loot, NPC robbery / assist / dead-driver keys, alarms + alerts |
| `server/carlock/locksmith.lua` | `NZ.CarLock` | locksmith services |
| `server/carlock/tracker.lua` | `NZ.CarLock` | tracker list, remote alarm |
| `server/carlock/exports.lua` | — | server exports (§7) |
| `client/carlock/lock.lua` | `NZ.CarLock` (client) | lock keybind / command / item, animation, sound, lights, fob remote |
| `client/carlock/ignition.lua` | `NZ.CarLock` | key-required engine, engine keybind / command, bypass rules |
| `client/carlock/crime.lua` | `NZ.CarLock` | no-key driver flow (hotwire / search prompts), lockpicking doors, NPC aim / assist / dead driver |
| `client/carlock/locksmith.lua`, `client/carlock/tracker.lua`, `client/carlock/keysapp.lua` | `NZ.CarLock` | locksmith points, tracker, the Keys NUI app glue |
| `server/contracts.lua`, `client/contracts.lua` | `NZ.Contracts` | car sale contracts |
| `server/fakeplates.lua`, `client/fakeplates.lua` | `NZ.FakePlates` | fake plates + screwdriver |
| `server/towtruck.lua`, `client/towtruck.lua` | `NZ.Tow` | impound flatbed tow |
| `web/src/apps/keys/**` | — | "Key ring" app: keys, lock / unlock, locate, alarm, share, manage |
| `web/src/apps/locksmith/**` | — | locksmith services menu |
| `web/src/apps/contract/**` | — | contract draft / review / sign |

## 3. Keys (server authority)

A player (src) **has a key** for a plate when any of these hold (checked in this order, first
hit wins; result also says which kind):
1. **Temporary key** (memory): granted by hotwire success, robbery, assistance, admin command,
   compatibility events, job / rental spawners, garage retrieval in virtual mode. Keyed by
   identifier + normalized plate, expires after `Config.CarLock.tempKeyHours` or on restart.
2. **Physical key item** (physical mode): an item named by the vehicle's security profile
   (`vehicle_key` / `vehicle_fob`) whose metadata `plate` matches and `version` equals the
   plate's current key version.
3. **Virtual shared key** (virtual mode, persistent, table `nz_keys`): given with the Keys
   app; owners can revoke.
4. **Owner / share / fleet access** (`Config.CarLock.ownerHasKey`, default true in virtual
   mode, false in physical mode): owner identifier, a garage share (nz_shares), job / gang
   fleet member.

Key versions: owned vehicles keep `nz_key_version` (INT, default 0) in the framework vehicle
table; unowned (NPC / spawned) vehicles keep versions in memory. "Change locks" increments the
version: older physical keys stop working and virtual shared + temporary keys of other
players are removed.

Plates: always the **real** plate — `Entity(veh).state.nzPlate` when present (garage
vehicles, fake plates), else the trimmed upper-case plate text.

Physical key item metadata: `{ plate, version, label = "Vehicle key · <plate>",
description = "<model label>", model, kind = 'key'|'fob' }`.

Garage integration: on retrieve the existing keys bridge (`NZ.KeysServer.give` /
`NZ.Keys.give`) routes to the built-in system when `Config.CarLock.enabled` and
`Config.Integrations.keys` is `'auto'` (built-in wins) or `'nayzeee'`. Physical mode gives a
key item only when the player has no valid key for that plate (`giveKeyOnRetrieve`); virtual
mode grants a temporary key. Job / public spawner vehicles get a temporary key.

Locks: the server sets `SetVehicleDoorsLocked(entity, 2|1)` and the replicated state bag
`nzLocked` (bool); clients apply visuals. Range check uses the server ped position:
key `ranges.key` (default 5 m), fob `ranges.fob` (default 30 m), inside the vehicle always.

### Server API (`NZ.CarLock`, server)
```
NZ.CarLock.realPlate(entity) -> plate|nil
NZ.CarLock.hasKey(src, plate) -> boolean, kind 'temp'|'item'|'virtual'|'owner'|nil
NZ.CarLock.grantTemp(src, plate, reason, hours?) -> boolean          -- reason: 'hotwire'|'robbery'|'assist'|'admin'|'compat'|'spawner'|'garage'|'search'|'contract'
NZ.CarLock.revokeTemp(src|identifier, plate)
NZ.CarLock.giveKeyItem(src, plate, opts?) -> boolean, err           -- physical: adds a key / fob item for the current version (opts.kind, opts.model)
NZ.CarLock.keyVersion(plate) -> integer ; NZ.CarLock.rekey(plate) -> newVersion
NZ.CarLock.shareVirtual(ownerSrc, targetSrc, plate) / NZ.CarLock.revokeVirtual(ownerSrc, identifier, plate) / NZ.CarLock.holders(plate) -> list
NZ.CarLock.keysOf(src) -> { { plate, label?, kind, model?, netId? } }   -- for the Keys app
NZ.CarLock.setLocked(entity, locked:boolean) ; NZ.CarLock.isLocked(entity) -> boolean
NZ.CarLock.mode() -> 'physical'|'virtual'
NZ.CarLock.alarm(entity, seconds)                                     -- native or custom alarm via the entity owner
```
Callbacks (`nz:carlock:<action>`): `toggleLock {netId}`, `engine {netId, on}`, `hasKey {plate|netId}`,
`keys {}`, `share {plate, target}`, `revoke {plate, identifier}`, `holders {plate}`,
`lockpick {netId, tool}`, `hotwire {netId, success}`, `search {netId}`, `npcRob {netId, pedNetId}`,
`npcAssist {netId, pedNetId}`, `deadDriver {netId, pedNetId}`, `locksmith:* {...}`,
`tracker {}`, `trackerAlarm {netId}`. Every callback: rate limit, OneSync entity checks,
distance from the server ped position, no client-supplied coordinates trusted.

## 4. Inventory integration (`NZ.Inventory`, open file)

Detection order (`Config.Integrations.inventory = 'auto'`): ox_inventory, qb-inventory,
qs-inventory, codem-inventory, tgiann-inventory, origen_inventory, core_inventory,
ps-inventory, lj-inventory, then framework fallback (ESX / QB items without metadata).
`custom` adapter at the top of the file for anything else.
```
-- server
NZ.Inventory.name() -> string|nil ; NZ.Inventory.supportsMetadata() -> boolean
NZ.Inventory.hasItem(src, item, count?, metadata?) -> boolean
NZ.Inventory.count(src, item, metadata?) -> number
NZ.Inventory.find(src, item, matchFn?) -> { { slot, count, metadata } }
NZ.Inventory.addItem(src, item, count, metadata?) -> boolean
NZ.Inventory.removeItem(src, item, count, metadata?, slot?) -> boolean
NZ.Inventory.setMetadata(src, slot, metadata) -> boolean
NZ.Inventory.registerUsable(item, fn(src, item, slot, metadata))   -- one registration path per inventory / framework
NZ.Inventory.canCarry(src, item, count) -> boolean
-- client
NZ.Inventory.hasItem(item, count?) -> boolean (best effort; the server re-checks)
```
Ship item definitions in `install/items/` for ox_inventory (`data/items.lua` snippet),
qb-core / qb-inventory (`shared/items.lua` snippet), and ESX (`items` SQL), plus images in
`install/items/images/` (simple original SVG→PNG icons or none; document the names):
`vehicle_key`, `vehicle_fob`, `lockpick`, `advancedlockpick`, `screwdriver`, `fake_plate`,
`vehicle_contract`, `signed_contract`, `key_blank`.

## 5. Listener file (open)

`bridge/server/listeners.lua` / `bridge/client/listeners.lua` register handlers for the
global events other scripts use to give / remove keys with other key resources (per research)
and map them to `NZ.CarLock.grantTemp` / `revokeTemp`, only when `Config.CarLock.enabled` and
`Config.CarLock.compat = true`. Also hooks usable items (`NZ.Inventory.registerUsable`) for
keys / fobs (use = toggle lock), lockpicks, screwdriver, fake plate, contract.

## 6. Dispatch integration (`NZ.Dispatch`, open file)

`Config.CarLock.dispatch.system = 'auto' | 'wasabi_mdt' | 'ps-dispatch' | 'cd_dispatch' |
'rcore_dispatch' | 'internal' | 'none' | 'custom'`.
```
-- server
NZ.Dispatch.alert(src, alert) -> boolean
--   alert = { kind = 'theft'|'lockpick'|'hotwire'|'robbery'|'locksmith'|'alarm'|'fakeplate',
--             code, title, message, coords (server ped or vehicle), plate, model, color,
--             jobs (default Config.CarLock.dispatch.jobs), blip = { sprite, color, scale, seconds } }
-- client side adapters run on the offender's client (TriggerClientEvent 'nz:client:dispatch')
```
`internal`: notify on-duty players of the configured jobs (NZ.Bridge) + a temporary blip.

## 7. Exports (open; documented in docs/INTEGRATIONS.md)

Server: `HasKey(src, plate)`, `GiveKey(src, plate|netId, hours?)`, `RemoveKey(src, plate)`,
`GiveKeyItem(src, plate)`, `GetKeyVersion(plate)`, `Rekey(plate)`, `SetVehicleLocked(netId, bool)`,
`IsVehicleLocked(netId)`, `SendDispatch(src, alert)`, `StartTow(netId, officerSrc?)`.
Client: `HasKey(plate|vehicle)`, `ToggleLock(vehicle?)`, `ToggleEngine()`, `OpenKeys()`,
`GiveKey(vehicle)` (asks the server; validated).

## 8. Crime tools

- **Lockpicking doors** (item use or target on a locked vehicle): tools from the vehicle's
  profile `accessTools` (lockpick / advancedlockpick / screwdriver ...), each with skill-check
  difficulty, break chance, alarm chance, alert chance.
- **No-key driver flow**: in the driver seat without a key the hint shows *Hotwire* and
  *Search*. Hotwire method per profile (`skillcheck`, `progress`, `hack` = harder checks +
  required item). Success → temporary key. Search (once per vehicle) → loot roll on the
  server: money, items, spare key (temporary key or key item).
- **NPC drivers**: aiming a weapon at an NPC driver (stopped or slow) makes them stop and
  raise hands; after `npc.robTime` they hand over the key (temporary key) and flee — unless
  they resist (`npc.resistChance`): flee with the car or fight. If that original driver dies,
  a target option on the body lets the player search it for the key. Authorized jobs
  (`npc.assistJobs`) get a target option "Request the vehicle": the driver pulls over, steps
  out and hands the key, no alert.
- **Alerts**: each action has an alert chance; alarms per profile (`native` uses GTA alarm
  natives on the entity owner, `custom` plays horn / lights / sound for `alarm.seconds`).

## 9. Locksmith

Locations in config (ped + blip + target / prompt), `illegal` flag with alert chance.
Services: **Duplicate** a physical key (must hold a valid key or own the vehicle; price and /
or materials), **Program a key** for a nearby vehicle (legal: owner or valid key holder;
illegal: any vehicle within range), **Change locks** (owner only: rekey, new key). The NUI
`locksmith` app lists services with prices / materials and the nearby vehicles.

## 10. Keys app ("Key ring", NUI app `keys`)

Opened with `/keys`, a keybind, or by using a fob. Left: your keys (owned vehicles, items,
temporary / shared keys) with kind badges; right: selected key — lock / unlock (range rules
apply), locate (tracker-eligible vehicles spawned in your routing bucket → waypoint +
distance), remote alarm, share / hand over to a nearby player, manage virtual key holders
(revoke).

## 11. Impound tow truck (`NZ.Tow`)

On a police impound of a spawned vehicle (`Config.Tow.enabled`), the server keeps the entity,
locks it (`nzTowing` state bag) and asks the impounding officer's client to run the tow: a
networked flatbed + driver spawn on a road node 80–150 m away out of sight, drive to the
vehicle, park, the driver walks to the back and works the controls, the vehicle is attached
to the bed, the driver gets back in and drives away; both are deleted when far from players
or after `Config.Tow.timeout`. Any failure (no road node, stuck, officer left, timeout) falls
back to deleting the vehicle (server). The database impound happens immediately; the tow is
visual.

## 12. Contracts (`NZ.Contracts`)

Using a blank `vehicle_contract` opens the `contract` app in draft mode: pick one of your
vehicles nearby, price, buyer (nearby players), terms; sign (signature pad). The buyer gets
the contract in review mode, signs and pays. The server re-validates everything (seller owns
it, not financed / impounded / blocked / out of range, buyer can pay), transfers ownership
(same internals as the garage "sell" flow: owner, shares cleared, ownership history entry
`via = 'contract'`), rekeys (new key for the buyer), pays the seller, consumes the blank
contract and gives both parties a `signed_contract` item with metadata.

## 13. Fake plates and screwdriver (`NZ.FakePlates`)

`fake_plate` + `screwdriver` (not consumed, break chance): "Install fake plate" on a vehicle
(target / item use, progress + animation) → the server sets a generated plate text on the
entity, keeps the real plate in `nzPlate`, records `nzFakePlate`. "Remove fake plate" (needs
the screwdriver) restores the real plate and returns the fake plate item. Storing in a garage
drops the fake plate (item returned when configured). Keys, locks and garages always use the
real plate. Police see the fake plate.
