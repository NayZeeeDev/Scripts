# Built-in car lock, crime tools, contracts, fake plates and impound tow

nayzeee-garages ships its own car lock: physical or virtual keys, key fobs with remote
locking, a key-required ignition, security profiles, crime tools (lockpicks, hotwiring,
vehicle search, NPC hold-ups), police alerts, locksmiths, a key ring with a vehicle tracker,
and an admin command to grant a key. Next to it: an NPC flatbed tow truck for police
impounds, car sale contracts, and fake plates with a flathead screwdriver.

Everything is original work and open Lua (no escrow). Every user-facing string goes through
`L()` (Lua) / `t()` (NUI). The integration files (framework, inventory, interaction,
listeners, dispatch, keys) are described in `docs/INTEGRATIONS.md`; the item definitions to
install are in `install/items/`.

The section numbers below are referenced from the code headers (`docs/CARLOCK.md §N`).

---------------------------------------------------------------------------------------

## 1. Configuration and when the car lock runs

`config/carlock.lua` (shared, nothing secret): `Config.CarLock` (switch, key mode, items,
keybinds, commands, ranges, animation, sounds, ignition, security profiles, search loot, NPC
behaviour, locksmiths, share picker, tracker, dispatch, alarms), `Config.Tow`,
`Config.Contracts`, `Config.FakePlates`. Read the comments in that file: they are the
reference for every value.

**When it runs.** `Config.CarLock.enabled = true` and `Config.Integrations.keys` is
`'nayzeee'`, or `'auto'` while no other key resource runs. The built-in car lock is off when
another key resource (qbx_vehiclekeys, qb-vehiclekeys, wasabi_carlock, MrNewbVehicleKeys,
qs-vehiclekeys, Renewed-Vehiclekeys, vehicles_keys) is started when nayzeee-garages starts, or
starts after it while the server boots (no player connected yet; the start order inside a
`[category]` of server.cfg is not guaranteed). Keys then go to that resource and the
compatibility listeners go quiet. A key resource started later, with players online, only
prints a warning: start it before nayzeee-garages in server.cfg or set
`Config.Integrations.keys` to its name. The decision is published in
`GlobalState.nzCarLockOther` so every client agrees with the server.

While the car lock is off, its commands, keybinds, items, crime tools, locksmiths and key ring
do nothing. The tow truck, contracts and fake plates have their own switches
(`Config.Tow.enabled`, `Config.Contracts.enabled`, `Config.FakePlates.enabled`) and work with an
external key resource too.

**Key mode** (`Config.CarLock.keyMode`):
- `'auto'` (default): physical keys when the inventory supports item metadata, else virtual.
- `'physical'`: plate-specific `vehicle_key` / `vehicle_fob` items. Falls back to virtual keys
  (with a console message) when the inventory has no metadata or the key items are missing
  from it.
- `'virtual'`: no items; keys live on the server and are given and managed from the key ring.

`ownerHasKey` (nil = true in virtual mode, false in physical mode): owners, players a vehicle
is shared with, and job / gang fleet members always have a key. In physical mode they need the
key item; `giveKeyOnRetrieve = true` cuts one on garage retrieval when they have no valid key.
Servers that want scarce keys set `giveKeyOnRetrieve = false` and use locksmiths.

## 2. Module layout and namespaces

Namespaces are declared in `shared/init.lua`. `NZ.CarLock`, `NZ.Inventory`, `NZ.Dispatch`,
`NZ.Contracts`, `NZ.FakePlates` and `NZ.Tow` exist on both sides (separate tables).

| File | Namespace | Purpose |
|---|---|---|
| `config/carlock.lua` | `Config.CarLock`, `Config.Tow`, `Config.Contracts`, `Config.FakePlates` | configuration |
| `shared/carlock.lua` | `NZ.CarLock` (both) | who is in charge (§1), security profiles (`profileOf(model, class)`), item names, ranges, key mode, ignition bypass |
| `bridge/server/inventory.lua`, `bridge/client/inventory.lua` | `NZ.Inventory` | open inventory integration (§4) |
| `bridge/server/dispatch.lua`, `bridge/client/dispatch.lua` | `NZ.Dispatch` | open police alert integration (§6) |
| `bridge/server/listeners.lua`, `bridge/client/listeners.lua` | (local) | open listener files: usable items, other key scripts' events and exports (§5) |
| `bridge/server/keys.lua`, `bridge/client/keys.lua` | `NZ.KeysServer`, `NZ.Keys` | garage key hand-out: built-in car lock or an external key script |
| `server/carlock/keys.lua` | `NZ.CarLock` (server) | key store and rules, key versions, signed key items, locks, alarms (§3) |
| `server/carlock/main.lua` | `NZ.CarLock` | callbacks: lock, engine, key checks, keys list, share / revoke, compat requests, key item use, `/givekey` |
| `server/carlock/crime.lua` | `NZ.CarLock` | lockpick, hotwire, search, NPC robbery / assist / dead driver, alarms and alerts (§8) |
| `server/carlock/locksmith.lua` | `NZ.CarLock` | locksmith services (§9) |
| `server/carlock/tracker.lua` | `NZ.CarLock` | key ring status, tracker, remote alarm, share picker, key holders (§10) |
| `server/carlock/exports.lua` | — | server exports (§7) |
| `client/carlock/lock.lua` | `NZ.CarLock` (client) | key cache, lock keybind / command, fob animation, lock feedback, alarms, client exports |
| `client/carlock/ignition.lua` | `NZ.CarLock` | key-required engine, engine keybind / command, bypass rules |
| `client/carlock/crime.lua` | `NZ.CarLock` | no-key driver hint (Hotwire / Search), lockpicking, NPC hold-ups, assist, dead driver |
| `client/carlock/locksmith.lua`, `client/carlock/tracker.lua`, `client/carlock/keysapp.lua` | `NZ.CarLock` | locksmith points, tracker blip / waypoint, the key ring app |
| `server/contracts.lua`, `client/contracts.lua` | `NZ.Contracts` | car sale contracts (§12) |
| `server/fakeplates.lua`, `client/fakeplates.lua` | `NZ.FakePlates` | fake plates and screwdriver (§13) |
| `server/towtruck.lua`, `client/towtruck.lua` | `NZ.Tow` | impound flatbed tow (§11) |
| `web/src/apps/keys/**` | — | "Key ring" app |
| `web/src/apps/locksmith/**` | — | locksmith services window |
| `web/src/apps/contract/**` | — | contract draft / review / view |

## 3. Keys (server authority)

A player has a key for a plate when one of these holds (checked in this order, the first hit
wins and gives the kind):

1. **Temporary key** (`temp`, server memory per character): hotwire, robbery, NPC assist,
   dead driver, search, admin command, exports, other scripts (compat), job / rental spawners,
   garage hand-out in virtual mode, contract and sale buyers, illegal locksmiths, new locks.
   Expires after `Config.CarLock.tempKeyHours`; kept across a resource restart (KVP snapshot),
   dropped on a server restart.
2. **Key item** (`item`, physical mode): a `vehicle_key` / `vehicle_fob` whose metadata plate
   matches, whose version is the plate's current key version and whose signature is valid.
3. **Virtual key** (`virtual`, virtual mode, table `nz_keys`): given by the owner from the key
   ring; the owner revokes it there (`Config.CarLock.maxVirtualKeys` per vehicle).
4. **Owner access** (`owner`, with `ownerHasKey`): owner, garage share, job / gang fleet member.

**Key versions and owners.** Next to `nz_key_version` the vehicle row keeps `nz_key_owner`, a
hash of owner|job|gang the keys were cut for. A row whose owner differs, or that was never
keyed, gets a new version on the next key check: random for a first version, +1 otherwise.
Old key items then stop working and other players' virtual and temporary keys are removed.
This covers sales, transfers, admin edits, other scripts writing the owner column, and plates
reused by a new vehicle. Scripts that change an owner should still call
`exports['nayzeee-garages']:Rekey(plate, newOwnerIdentifier)` for an immediate effect.
Vehicles nobody owns (NPC, spawned) keep their version in memory. "Change locks" (§9) raises
the version on purpose.

The first key version of a vehicle row is claimed before any key is stored, so keys given to a
vehicle that was never key-checked (fresh install / upgrade) are kept.

**Plates.** The server keeps the real plate of every garage vehicle in memory
(`NZ.CarLock.realPlate` / `setRealPlate`, recorded on garage hand-out and kept across a
resource restart). The `nzPlate` state bag is for clients only: clients can write it, so the
server never trusts it. A plate text copied onto another entity than the tracked garage
vehicle has no real plate.

**Key item metadata.** `{ plate, version, kind = 'key'|'fob', model, id, sig, label,
description, origin?, display = false }`. `sig` = HMAC-SHA256 (24 hex characters kept) of
plate / version / kind / id with a server secret: the convar `nz_carlock_secret` (at least 16
characters; set the same value on servers sharing one database), else the value stored in
`nz_settings` (`carlock_secret`, created on the first start). Edited or forged metadata never
opens anything; `Config.CarLock.trustUnsignedKeys = true` also accepts unsigned keys (not
recommended). `origin` (`'locksmith'`, `'search'`) marks a crime's key item (§10); it is written
by the server and not part of the signature.

**Garage integration.** On retrieve the keys bridge (`NZ.KeysServer.give`) routes to the
built-in car lock while it runs (§1). The vehicle starts unlocked. Physical mode gives a key
item only when the player has no valid key for that plate (`giveKeyOnRetrieve`); virtual mode
grants a temporary key unless the player already has a key. Job / public spawner vehicles and
players who are not the owner get a temporary key.

Temporary keys handed out because of a share or a fleet access (garage retrieval, or other
scripts' key events through `NZ.CarLock.canAcquire`) end as soon as that access ends (unshare,
leaving the job). A player who took a vehicle out through such an access gets no further key
from other scripts once the access is gone.

**Locks.** The server sets `SetVehicleDoorsLocked(entity, 2|1)` and the replicated state bag
`nzLocked` (bool); every client applies it. The server keeps its own lock record and puts back
an `nzLocked` / `nzAlarm` value a client changed. The lock feedback (sound, horn chirp, lights)
is the server event `nz:client:carlock:fx` to players near the vehicle. Ranges are measured from
the server ped: key `ranges.key` (5 m), fob `ranges.fob` (30 m, profiles with `remote = true`),
always inside the vehicle. A vehicle on the impound tow truck cannot be locked or unlocked.
`set sv_stateBagStrictMode true` in server.cfg stops clients writing state bags at all; it is
not required, and it breaks other scripts that write entity bags from clients.

**Ignition.** `Config.CarLock.ignition`: without a key the engine stays off in the driver
seat (one server check per entry). No key is needed for `bypassClasses` (13 = cycles),
`bypassModels`, and on-duty job / gang members in their fleet vehicles (`bypassJobVehicles`).
`allowRunningEngine = true` lets a running engine run. `keepEngineRunning`: the engine keeps
running when the driver gets out; holding the exit key turns it off. The engine keybind (G) /
command (`/engine`) toggles it.

### Server API (`NZ.CarLock`, server)
```
NZ.CarLock.enabled() -> boolean ; NZ.CarLock.mode() -> 'physical'|'virtual'
NZ.CarLock.realPlate(entity) -> plate|nil ; NZ.CarLock.setRealPlate(entity, plate|nil)
NZ.CarLock.plateFromText(text, src) -> real plate (a fake plate near the player maps to the real one)
NZ.CarLock.findVehicle(plate, src) -> entity|nil, distance
NZ.CarLock.vehicleFromNet(src, netId) -> entity|nil, distance (server ped), inside
NZ.CarLock.hasKey(src, plate) -> boolean, kind 'temp'|'item'|'virtual'|'owner'|nil
NZ.CarLock.grantTemp(src, plate, reason, hours?, access?) -> boolean   -- access = true: the key ends when the player loses the garage share / job or gang fleet access it was given for
NZ.CarLock.revokeTemp(src|identifier, plate) -> boolean
NZ.CarLock.keyVersion(plate, fresh?) -> integer|nil                     -- nil: database unreadable
NZ.CarLock.rekey(plate, keepIdentifier?) -> newVersion|nil
NZ.CarLock.keyMetadata(plate, { kind, model, label, origin? }) -> metadata|nil
NZ.CarLock.verifyKeyItem(metadata, plate?) -> boolean, 'invalid'|'plate'|'version'|'error'|nil
NZ.CarLock.keyItemsOf(src, plate) -> { { item, slot, metadata } }
NZ.CarLock.giveKeyItem(src, plate, { kind?, model?, label?, reason?, origin? }) -> boolean, err
NZ.CarLock.handOverKeyItem(src, target, plate) -> boolean, err
NZ.CarLock.shareVirtual(ownerSrc, targetSrc, plate) ; NZ.CarLock.revokeVirtual(ownerSrc, identifier, plate)
NZ.CarLock.holders(plate) -> list (server only: identifiers) ; NZ.CarLock.keysOf(src) -> { { plate, kind, keyKind, label?, model?, netId?, expires?, shared? } }
NZ.CarLock.isOwner(src, plate) ; NZ.CarLock.vehicleRow(plate) ; NZ.CarLock.invalidate(plate|nil)
NZ.CarLock.setLocked(entity, locked, fx?) -> boolean ; NZ.CarLock.isLocked(entity) -> boolean
NZ.CarLock.alarm(entity, seconds?, 'native'|'custom'?) -> boolean ; NZ.CarLock.stopAlarm(entity)
NZ.CarLock.profileOfEntity(entity) / profileOfPlate(plate) -> name, profile ; classOf(entity) ; learnClass(src, entity, class)
NZ.CarLock.lockRangeOf(entity, fob?) -> metres ; NZ.CarLock.jobBypass(src, plate) -> boolean
NZ.CarLock.canAcquire(src, entity, dist, inside) -> allowed, plate, err, viaAccess
NZ.CarLock.compatRequest(src, payload, opts?) -> callback result      -- §5
NZ.CarLock.onVehicleOut(src, entity, plate, { spawner? })             -- garage hand-out
NZ.CarLock.useKeyItem(src, item, slot, metadata) -> boolean           -- key / fob item use
NZ.CarLock.useAccessTool(src, item, slot, metadata, key) -> boolean   -- §8
NZ.CarLock.crimeAlert(src, kind, entity, session)                     -- §8
NZ.CarLock.isAdmin(src) -> boolean                                    -- NZ.Access.isAdmin or adminGroups
NZ.CarLock.keyStatus(src, plate, entity?, opts?) -> KeyStatus         -- §10
NZ.CarLock.trackerEnabled() ; NZ.CarLock.openKeyRing(src, plate?)
NZ.CarLock.keyHolderList(src, plate) -> masked holders
NZ.CarLock.keyItemSummary(src, plate?) -> { [plate] = { count, real, kind, origin? } }
NZ.CarLock.isServiceKey(reason) -> boolean
```
Temporary key reasons in use: `hotwire`, `robbery` (hold-up and dead driver), `assist`,
`search`, `admin`, `export`, `compat`, `spawner`, `garage`, `contract`, `sale`, `locksmith`,
`rekey`.

### Callbacks (`lib.callback`, `{ ok, data, error }`)
- `nz:carlock:toggleLock { netId } | { netIds }` → `{ netId, plate, locked, kind }`: the vehicle
  you sit in, else the nearest candidate you have a key for within its range.
- `nz:carlock:engine { netId, on, class? }` → `{ on, kind? }` (driver seat only).
- `nz:carlock:hasKey { netId, class? }` → `{ plate, has, kind, ignition, locked }`;
  `{ plate }` → `{ plate, has, kind }`.
- `nz:carlock:keys {}` → `{ mode, keys }`.
- `nz:carlock:share { plate, target }` → null: virtual key (owner only) or, in physical mode,
  one key item handed over (server copy of the metadata). Target within `ranges.give`.
- `nz:carlock:revoke { plate, identifier }` → null: admins only (staff tools). Owners revoke
  through `nz:carlock:keyRevoke` with the key ring's opaque holder ids.
- `nz:carlock:holders { plate }` → the masked holder list of `keyHolderList` (owner / admin;
  same list as `nz:carlock:keyHolders`).
- `nz:carlock:compat { action = 'acquire'|'remove'|'lend', netId?, plate?, target?, export? }`:
  other scripts' client side (§5).
- `nz:carlock:tracker { plate? }`, `trackerAlarm { plate, on? }`, `nearbyPlayers {}`,
  `keyHolders { plate }`, `keyRevoke { plate, id }` (§10).
- `nz:carlock:lockpick`, `hotwire`, `search`, `npcRob`, `npcAssist`, `deadDriver` (§8).
- `nz:carlock:locksmith:open { id }`, `nz:carlock:locksmith:service { id, service, plate }` (§9).

Every callback is rate limited, works on server-side entities, positions and plates (OneSync),
and never trusts client coordinates.

Server → client events: `nz:client:carlock:keys { plate? }` (key cache flush),
`nz:client:carlock:used { netId, plate, locked, kind }` (fob animation),
`nz:client:carlock:fx { netId, locked }` (lock feedback), `nz:client:carlock:keyRing { plate? }`
(open the key ring), `nz:client:carlock:crime` (item use → lockpick / hack hotwire),
`nz:client:carlock:npc` (NPC step for the ped's owner). State bags: `nzLocked` (bool),
`nzAlarm` (`{ id, mode, seconds }` | false), `nzSearched` (bool), `nzPlate` (real plate, clients
only). Local client events: `nz:client:carlock:keysChanged (plate|nil)`,
`nz:client:carlock:driver ({ vehicle, netId, plate, allowed } | nil)`.

**Admin command** `/givekey [playerId]` (`Config.CarLock.commands.giveKey`): a temporary key of
the vehicle that player (default: you) sits in. Allowed for `NZ.Access.isAdmin` and the
framework groups in `Config.CarLock.adminGroups`; usable from the server console with an id.

## 4. Inventory integration (`NZ.Inventory`, open file)

Detection, adapters, the API and how to add your own inventory: `docs/INTEGRATIONS.md` §2.
Item definitions and images: `install/items/` (`vehicle_key`, `vehicle_fob`, `key_blank`,
`lockpick`, `advancedlockpick`, `screwdriver`, `hacking_device`, `fake_plate`,
`vehicle_contract`, `signed_contract`).

`NZ.Inventory.registerUsable(item, fn, { fallthrough = true })` is for items other scripts use
too (lockpick). On qb-inventory 2.2+ an ItemUsed hook looks first and hands every use it does
not handle to the script that registered the item, which is never taken over. Elsewhere (ps /
lj / older qb-inventory, Qbox framework items) the previous QBCore handler is remembered,
called for unhandled uses and registered again on stop. qb-core may delete it right after (stop
order not fixed): restart the owner script then. ESX has no way to read the previous handler;
on ox_inventory one item definition has one export (see `install/items/README.md`).

Key items are protected: qb-inventory's give copies metadata the giver's client sends, so
`vehicle_key` / `vehicle_fob` cannot be given from the inventory there (qb-inventory 2.2+
hook). Players hand keys over with the key ring.

## 5. Listener file (open)

`bridge/server/listeners.lua` / `bridge/client/listeners.lua`: the usable items (key / fob,
crime tools, fake plate, contracts) and the events / exports other scripts use to give or
remove keys with other key resources. The full list, the rules and how to add your own
mappings: `docs/INTEGRATIONS.md` §6. Compatibility runs only while the built-in car lock runs,
with `Config.CarLock.compat = true`, and only for key resources that are not running.

- Client-originated requests only ever give a **temporary** key to a vehicle the player sits in
  or stands next to (`ranges.compat`), never another player's owned vehicle; NPC traffic only
  with `Config.CarLock.compatAmbient = true`. Server exports are trusted.
- **Lending** (qb-vehiclekeys `GiveVehicleKeys` / `GiveKeys` from a client): only with a key that
  is not temporary. A hotwired, robbed, compat or garage temporary key never makes more keys. In
  physical mode a key item is handed over, and an owner may lend a temporary key.
- `lockpicks:UseLockpick` (qb-smallresources, client) is forwarded to the car lock's lockpick
  (§8) while qb-vehiclekeys is not running.
- The client export `GiveKey(vehicle)` follows the same rules; `clientGiveKeyExport = false`
  closes it (with `compat = false` as well, client code can no longer ask for keys).
- Qbox without qbx_vehiclekeys: keep `compat` and `compatExports` on; qbx_core (`/car`, vehicle
  persistence), qbx_vehicleshop and qbx_police call `exports.qbx_vehiclekeys` unconditionally.

**Calls that cannot be intercepted:** scripts that check
`GetResourceState('<key resource>') == 'started'` before calling (most bridge libraries) never
call our shims; scripts that cached a failed export lookup because they started before
nayzeee-garages (restart them after it); item-based key systems. Server owners should start
nayzeee-garages before those scripts, set their bridge's key option to nayzeee-garages / our
exports (`HasKey`, `GiveKey`, `RemoveKey`, `SetVehicleLocked`), or edit their bridge to call
`exports['nayzeee-garages']`.

## 6. Dispatch integration (`NZ.Dispatch`, open file)

`Config.CarLock.dispatch.system = 'auto' | 'wasabi_mdt' | 'rcore_dispatch' | 'cd_dispatch' |
'qs-dispatch' | 'core_dispatch' | 'ps-dispatch' | 'internal' | 'none' | 'custom'`. Detection,
the alert table and the custom adapters: `docs/INTEGRATIONS.md` §7.

```
-- server
NZ.Dispatch.alert(src|nil, alert) -> boolean      -- export: SendDispatch(src|nil, alert)
NZ.Dispatch.system() -> name ; NZ.Dispatch.build(src, alert) -> full alert ; NZ.Dispatch.receivers(jobs) -> srcs
-- client
NZ.Dispatch.streetAt(coords) -> string|nil ; NZ.Dispatch.modelLabel(hash) -> string|nil
```

`internal`: on-duty players of the configured jobs get a notification and a temporary blip
(`nz:client:dispatch:alert`).

wasabi_mdt, rcore_dispatch, core_dispatch, qs-dispatch and ps-dispatch 3.x
(`SendTargetedAlert` to the on-duty receivers) are sent from the server. Only ps-dispatch 2.x
and cd_dispatch, whose alert APIs are client side, run on the offender's client
(`nz:client:dispatch`, with the server-built payload; a failure there falls back to
`internal`). Without an offender those two use their server paths. Coordinates always come from
the server. Street / model text is stripped of markup before it reaches any system; for
`internal` alerts the officers' clients replace street and model text the offender's client
sent with their own lookup (`streetFromClient` / `modelFromClient`). One alert per player and
vehicle within `dispatch.cooldown` seconds.

## 7. Exports (open; reference in docs/INTEGRATIONS.md §12)

Server: `HasKey(src, vehicle)`, `GiveKey(src, vehicle, hours?)`, `RemoveKey(src, vehicle)`,
`GiveKeyItem(src, vehicle)` (vehicle = plate | entity | netId), `GetKeyVersion(plate)`
(nil: invalid plate or the database cannot be read), `Rekey(plate, keepIdentifier?)`,
`SetVehicleLocked(netId|entity, bool)`, `IsVehicleLocked(netId|entity)`,
`SendDispatch(src|nil, alert)`, `StartTow(netId, officerSrc?)`.

Client: `HasKey(plate|vehicle)`, `ToggleLock(vehicle?)`, `ToggleEngine()`, `OpenKeys(plate?)`,
`GiveKey(vehicle)` (asks the server for a temporary key; validated like other scripts' events:
near or inside, never someone else's owned car, script-spawned vehicles unless
`compatAmbient`).

## 8. Crime tools

Every crime action is a two-step server session: `start` validates everything on the server
(entities, distances from the server ped, routing bucket, locks, keys, items, jobs, cooldowns,
not on the tow truck) and `finish { id, success }` closes it once. A finish faster than
possible or too late counts as a failure. Callbacks `nz:carlock:lockpick`, `hotwire`, `search`,
`npcRob`, `npcAssist`, `deadDriver`, payload `{ step = 'start'|'finish', ... }`.

- **Lockpicking doors** (item use or the "Pick the lock" target option on a locked vehicle):
  tools come from the vehicle's profile `accessTools` (lockpick / advancedlockpick /
  screwdriver / hacking device). Each tool has a skill-check difficulty, break chance, alarm
  chance and alert chance. Using the item picks the locked vehicle the player faces: within
  2.5 m of its centre (buses, coaches and trucks, classes 10/17/20, except the car-sized
  service models taxi and vivanite2: 7 m), nobody alive at the wheel, its
  profile takes that tool, and the player has no key for it. In every other case the item goes
  to its owner script (house / store robberies), for example a car behind a player standing at
  a door or register, or while another crime action is running. The server refuses a reported
  success faster than ox_lib's earliest possible pass: a third of an indicator turn per check
  (ox_lib 3.32.3+ (communityox) / 3.33+ (overextended): 2000 ms per turn at speed 1; older or
  unknown versions: 1440 ms; read again when ox_lib restarts), plus the 800 ms turn to the door.
  When the player's client is busy (another script's progress bar) as the item use arrives, it
  waits up to 1.5 s, then says "You are busy".
- **No-key driver flow**: in the driver seat without a key, the hint shows *Hotwire* (H) and
  *Search* (Z). The hotwire method is set per profile (`skillcheck`, `progress`, `hack` = harder
  checks + a required item that may break). Success gives a temporary key and starts the
  engine. Search works once per vehicle (`nzSearched`), only on traffic / parked GTA vehicles
  (`search.ambientOnly`), never on the player's own job vehicles, never on players' vehicles
  unless `search.ownedVehicles`, and one successful search per player every `search.cooldown`
  seconds. It rolls loot on the server: money, items, spare key (a key item with
  `origin = 'search'` in physical mode with `spareKeyItem`, else a temporary key).
- **NPC drivers**: aiming a weapon at an NPC driver (stopped or slower than `npc.maxSpeed`,
  within `npc.range`) makes them stop and raise their hands. After `npc.robTime` they hand over
  the key (temporary key) and flee, unless they resist (`npc.resistChance`): then they flee with
  the car or fight (`fightChance`, `fightWeapon`). If that original driver dies, the player can
  search the body for the key (target option, or an [E] prompt without a target resource, also
  while the body sits at the wheel). This works for traffic drivers only (`npc.ambientOnly`),
  unless the server recorded that driver at a hold-up or request; an unrecorded driver only
  counts in a traffic vehicle (never a random parked car or a script vehicle), and a vehicle's
  last driver counts only within 15 m of it. Authorized jobs (`npc.assistJobs`, on duty) get a "Request the
  vehicle" target option: the driver pulls over, steps out and hands over the key, with no
  alert. If the player never finishes a hold-up or request, the server releases the driver when
  the session runs out. Players' vehicles are skipped unless `npc.ownedVehicles`.
- **Alerts**: each action has an alert chance and is reported as that crime, also when the
  alarm sounds. Otherwise an alarm going off alerts the police with `alarm.alertChance` as a car
  alarm. Alarms are set per profile: `native` uses GTA alarm natives on the entity owner;
  `custom` plays horn / lights / sound for `alarm.seconds`; `none`. Alerts name the plate the
  vehicle shows, its model, colour and position.

The NPC behaviour runs on the client that owns the ped (`nz:client:carlock:npc` steps: holdup,
release, flee, fight, pullover, handover, resume).

## 9. Locksmith

Locations in `Config.CarLock.locksmiths` (ped + blip + target option or [E] prompt, following
the interface's interaction setting; keybind `nz_locksmith`; `bucket` = routing bucket, default
0). The player stands at the counter (5 m, server ped). Vehicles count as nearby within the
location's `range` (default 25 m) in the player's routing bucket. Vehicles on the tow truck are
refused. Every paid service is confirmed in the NUI first. Money comes from
`Config.CarLock.locksmithAccount`, materials through `NZ.Inventory`: money and materials are
checked first, materials then money are taken, and both are given back when the service fails.

Services: **Duplicate** a physical key (must hold a valid key or own the vehicle; a copy keeps
the origin of the key it copies), **Program a key** for a nearby vehicle (legal: owner or
holder of a real key, never a temporary key, garage share / job access or an unregistered key;
illegal: any vehicle within range; virtual mode: a temporary key, at illegal shops only,
because owners give keys from the key ring), **Change locks** (owner only at every shop: rekey,
new key; physical mode takes the old key items the owner carries back). Keys from an illegal
shop are a crime's keys: key items carry `metadata.origin = 'locksmith'` (server-written, not
signed), and temporary keys have the reason `'locksmith'`. They open the vehicle but give no
tracker access and no owner's nickname unless the holder owns it.

Illegal shops (`illegal = true`) alert the police with `alertChance` % per service
(`NZ.Dispatch`), naming the plate the vehicle WEARS, and only when it is parked there.
Strangers' vehicles never show the owner's nickname.

## 10. Key ring ("Key ring", NUI app `keys`)

Opened with `/keys` (`commands.keyRing`), F7 (`keys.keyRing`; pressing it again closes the
ring), the client export `OpenKeys(plate?)`, or a fob used out of range of its vehicle.

Two panes: keys grouped Owned · Shared with you · Temporary · Key items, with Key / Fob /
Temporary (time left) / Virtual badges, lock state and distance. The selected key shows the
vehicle, a status strip, a range gauge with the server's answer, the tracker readout, key
details, and key holders with Revoke (owner, virtual mode). Dock: Lock / Unlock
(`nz:carlock:toggleLock`; range rules apply), Locate (trackable vehicles: waypoint + a blip that
follows the vehicle for `tracker.locateSeconds`), Alarm (trackable; `tracker.alarmSeconds`,
cooldown `tracker.alarmCooldown` per vehicle), Give key / Hand over (`nz:carlock:share`, players
within `ranges.give`). Keyboard: ↑ / ↓ select, Enter lock / unlock, L locate, / search, Esc or
the keybind close.

Keys and vehicles come from one call (`nz:carlock:tracker {}`). A vehicle is trackable when
`Config.CarLock.tracker.enabled`, its profile has `tracker = true`, it exists in the player's
routing bucket, it is not on the tow truck, and the key gives tracker access. Distances are
measured from the server ped; out of range and the alarm cooldown are answers
(`refused = 'range'` / `'cooldown'` with seconds left), not errors.

Tracker access and the owner's nickname come only with a real key: the owner, a garage share /
fleet, a virtual key the owner gave, a service's temporary key (garage, spawner, admin,
contract, export, assist, rekey), or a key item without a crime origin. Crime keys get
neither: a temporary key from a hotwire, a robbery, a search, a back-alley locksmith, compat or
any unknown reason, and key items with origin `'locksmith'` / `'search'`.
`Config.CarLock.tracker.tempKeys = true` gives every key tracker access, but never the nickname.

Key holders (`nz:carlock:keyHolders` / `keyRevoke`) masks every temporary key that is not a
service's ('Unknown holder', with how the key was obtained), sends opaque ids (valid 10
minutes) instead of identifiers and leaves out the owner's own keys. In physical mode there is
no holder list (nobody knows who carries a key item): change the locks instead. The share
picker sends server ids, plus character names only with
`Config.CarLock.sharePicker.names = true`.

## 11. Impound tow truck (`NZ.Tow`)

On a police impound with the impound form (`/impound`, the "Impound vehicle" target option)
and `Config.Tow.enabled`, the database impound happens at once and the server hands the
entity to `NZ.Tow.start` instead of deleting it. Not towed (deleted at once, as before): boats,
aircraft and trailers, `skipClasses`, vehicles larger than `maxSize`, a vehicle somebody sits
in, more than `maxActive` tows, nobody within 150 m to run the scene. Admin-panel and
`ImpoundVehicle`-export impounds delete at once; other resources call
`StartTow(netId, officerSrc?)`, which returns true, or false + reason and leaves the vehicle
untouched.

The server locks the vehicle (`SetVehicleDoorsLocked` 2, `nzLocked`, state bag `nzTowing`) and
picks a runner client (the impounding officer when in range, else the nearest player in the
vehicle's routing bucket). The runner checks the vehicle fits on the bed (class, type, size)
and proposes a road node 80–150 m away, out of sight when possible. The SERVER creates the
flatbed + driver there (`CreateVehicleServerSetter` / `CreatePed`, bags `nzTowTruck` /
`nzTowDriver`; works with any `sv_entityLockdown` mode) and gives the job to the client that
simulates them. That client drives to a spot in line with the vehicle so the truck arrives rear
first. The driver walks to the back and works the bed controls; the vehicle's owner client
pulls it onto the bed (`nz:client:tow:attach`); the driver gets back in and drives away. Truck
and driver are removed when every player is farther than `despawnDistance`, or after
`despawnSeconds`. The steps are reported through `nz:tow:progress` (node, spawned, arrived,
load, attached, loaded, leaving, tick, done, failed). A 1 s watchdog hands the job to another
nearby player when the runner drops, leaves, changes bucket or goes silent. Any failure (no
road node, stuck, wrong way round after retries, nobody left to run it, `Config.Tow.timeout`)
falls back to removing the vehicle server-side; what a client simulates fades out for a moment
first (`nz:client:tow:fade`). On resource stop everything goes at once. Players cannot enter
towed vehicles or tow trucks, and a towed vehicle is not offered for impound again. The officer
gets a blip on the truck (`Config.Tow.blip`). When the owner takes the vehicle out of the
impound while the truck is still on its way, `NZ.Tow.release` deletes the towed copy (no
duplicate log) and the truck leaves empty.

Authority and anti-cheat: the server identifies the towed vehicle, the truck and the driver by
handle + model and the `entityRemoved` event, never by state bags (the owning client can write
entity bags unless `sv_stateBagStrictMode` is on). The bags `nzTowing` / `nzTowTruck` /
`nzTowDriver` only drive the client guard (nobody enters or drives them); the server puts them
back the moment a client clears them and logs `security.tow` (reason `bag:<key>`). A player in
the towed vehicle or in the tow truck ends the tow at once: both are deleted under them. A
node within 12 m of another tow's node or truck, or with a player on it, is refused with code
`retry` and the runner proposes its next one (3 retries, then the vehicle is deleted). The
truck loads only with the vehicle behind its bed; a truck that stops beside it drives on to its
spot.

Server API: `NZ.Tow.start(entity, officerSrc?)`, `NZ.Tow.startByNetId(netId, officerSrc?)` →
`started, reason`; `NZ.Tow.isTowing(entity)` (vehicle, truck or driver of a running tow, or
fading out); `NZ.Tow.release(entity)` (delete a vehicle still being towed; the truck leaves
empty); `NZ.Tow.stopAll(reason?)`. Client: `NZ.Tow.isTowing(entity)`, `NZ.Tow.activeCount()`.
Logs: `impound.tow`, `security.tow`.

## 12. Contracts (`NZ.Contracts`)

Using a blank `vehicle_contract` (`NZ.Contracts.useItem`) next to one of your vehicles opens
the `contract` app in draft mode. It lists the seller's own vehicles within
`Config.Contracts.maxDistance`, or the one they sit in; fleet, financed, impounded, blocked,
towed and fake-plated vehicles, and vehicles that are not out, are shown with the reason they
cannot be sold. It also lists the players in range. The seller sets the price (1 to
`maxPrice`) and terms (600 characters, 12 lines) and signs (SVG path data in a 400×140 box, M/L
commands, at most 4000 characters, rebuilt by the server).

`nz:contract:send` re-checks everything from the SERVER ped positions: a draft session from a
real item use, the blank contract carried, ownership, the block reasons, buyer and vehicle in
range, one pending contract per seller / buyer / vehicle, and the buyer able to open the
vehicle's last garage. It then opens the review for the buyer (countdown `expireSeconds`;
closing it declines). The buyer's window asks the server every 5 s whether they can pay now
(`nz:contract:balance`).

`nz:contract:sign` is one attempt per contract. Everything is validated again inside the plate
lock, then: blank contract consumed, buyer charged from `Config.Contracts.account`, owner
changed, seller paid into the same account (`NZ.Actions.sellVehicle`; each step is undone when
a later one fails; shares cleared; ownership history entry `via = 'contract'` with the
`contractId`; `NZ.CarLock.rekey(plate, buyer)`). Both parties get a `signed_contract`
(`signedCopies`, needs item metadata). Decline, withdraw, expiry or a party leaving void the
contract and tell both players. A seller who closed the window gets it back in its sent state
(withdraw) by using a blank contract again.

After a "no" (the buyer declines or lets it expire) the seller cannot send that buyer another
contract for `Config.Contracts.resendCooldown` seconds. The window counts it down, and another
buyer can get one at once. Withdrawing starts no cooldown. The buyer has one attempt per
contract; only a vehicle busy with another garage operation at that very moment leaves the
contract open for a second try. The tracked vehicle, its keys and the right to ask key
resources for keys move to the buyer: in physical mode they get a key item (a temporary key
when they cannot carry it), otherwise a temporary key; with an external key resource the keys
follow the sale (`NZ.KeysServer` for server-side systems, the clients otherwise:
`nz:client:contract:keys`). A garage sale of a vehicle standing in the world hands over the key
the same way (`NZ.Actions.handBuyerKey`, built-in car lock only). A signed copy reads Verified
only when the ownership history holds that contract and its checksum matches every field the
copy shows (vehicle, condition, price, account, parties, dates, terms, signatures). If the
seller's payout and its database rollback both fail, the buyer keeps the vehicle they paid
for, and a `security.sell` log tells staff to pay the seller.

Callbacks: `nz:contract:refresh`, `send`, `sign`, `balance`, `decline` (NUI `contract:*`
forwarded 1:1). Events: `nz:client:contract:open`, `nz:client:contract:status
{ contractId, status, copy?, resendIn? }`, `nz:client:contract:keys`. Logs: `vehicle.contract`,
`vehicle.sell` (`action = 'contract'`), `security.contract`, `security.sell`.

## 13. Fake plates and screwdriver (`NZ.FakePlates`)

`fake_plate` + `screwdriver` (`Config.FakePlates.requireScrewdriver`; not consumed;
`screwdriverBreakChance` per job). Target options "Install fake plate" / "Remove fake plate"
at the rear of vehicles, or use the `fake_plate` item at the rear of a vehicle (works without a
target resource; on a fake-plated vehicle it offers removal). Two server steps:
`nz:fakeplates:start { netId, action = 'install'|'remove' }` → `{ token, duration }` and
`nz:fakeplates:finish { token, cancel? }` → `{ plate }`, one finish per started job, only after
the job's duration has passed on the server clock.

The installer must stand behind the vehicle (server position: within 7.5 m of the centre, at
most 1.6 m off its long axis; the client uses `Config.FakePlates.distance` and a slightly
stricter rear check), on foot, nobody inside, not on the tow truck. The new plate follows
`Config.FakePlates.pattern` (1 = digit, A = letter, a space or anything else as written, for
example `'AAA 111'` on ESX) and is never in the vehicle table nor on any vehicle.
`NZ.CarLock.setRealPlate` runs before the plate text changes; state bags `nzPlate` (real plate)
and `nzFakePlate` (fake plate, for target options) are set, and a client change to
`nzFakePlate` is put back. Removing restores the real plate text and gives the item back.
`alertChance` % of installs alert the police (`kind = 'fakeplate'`).

Keys, locks and garages always use the real plate; everyone else sees the fake one. The police
impound form shows the plate the vehicle wears and finds the database row by its
registration. With an external key resource that keys on the plate text (qb-vehiclekeys,
wasabi_carlock...), the installer gets keys for the fake text only when they have access to the
real registration (owner, share, fleet), and the owner, when online, gets them too
(`nz:client:fakeplates:keys`). qbx_vehiclekeys keys follow the entity. Storing in a garage
(normal or spawner) takes the fake plate off (item returned with `returnOnStore`); recovering
from the garage menu does too. A fake plate survives a restart of the resource (KVP snapshot,
same server session only) and the garage adopts fake-plated vehicles by their real plate.

Server API: `NZ.FakePlates.realPlateOf(entity)` (real plate under a fake one, else nil),
`isFake(entity)`, `plateOf(entity)` (identity: real plate, else `NZ.CarLock.realPlate`, else
the text), `lookup(text) -> entity, { real, fake, at }` (internal; not exported: other
resources only see the fake plate), `onStore`, `useItem`. Logs: `vehicle.fakeplate` (install / remove / store), `security.fakeplate`.

## 14. Known limits

- Nothing here ran on a live FiveM server during development: the flows are covered by the
  standalone tests (`tools/smoke/carlock.lua`, `carlock_client.lua`, `crime.lua`,
  `crime_client.lua`, `keyring.lua`, `keyring_client.lua`, `tow.lua`, `contracts.lua`) and paper
  traces.
- In physical mode keys can be farmed by giving them away when `giveKeyOnRetrieve` is on (a new
  key item on every retrieve without one). Use locksmiths instead for scarce keys.
- Lent keys: a lender with an owner key through a share or fleet access, or a virtual key
  holder, can lend a temporary key; that key does not end when the lender's access ends. The
  owner sees it in key holders and can revoke it.
- ps-dispatch 2.x and cd_dispatch alerts with an offender go through the offender's client: a
  modified client can drop those. The other systems are sent from the server, and server-side
  systems keep the street / model text the offender's client sent (display text only).
- Key items that existed before `origin` was written (back-alley keys cut earlier) count as
  registered keys until the locks are changed.
- External key resources: a garage sale of an out vehicle gives the buyer no keys (the contract
  flow does).
- The impound form shows a fake-plated owned vehicle's fake plate but marks it 'Player owned'
  (its row is found by the registration), so officers can infer the plate is fake; the real
  plate is never shown.
