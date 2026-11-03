# nayzeee-garages — Architecture & Contracts

This file is the **single source of truth** for how the resource fits together. Every Lua
module and every NUI app is written against the contracts below. If you need something
that is not here, add the smallest possible helper inside the files you own and keep
the public surface exactly as written.

Companion docs:
- `docs/UI_KIT.md` — the NUI design system + React component API (web agents).
- `web/src/lib/types.ts` — TypeScript mirror of every data shape in this file.
  **Lua tables use exactly the same camelCase keys as these TS types.**
- `install/nayzeee-garages.sql` — database schema (also auto-migrated at start).

---------------------------------------------------------------------------------------

## 1. Product scope (what we are building)

An original, all-in-one garage system for FiveM (QBCore, Qbox, ESX Legacy):

- Public, job, gang, private (purchasable / assigned), house garages and impounds.
- Every type supports `car`, `sea` and `air` vehicles.
- Garage menu (grid + list): thumbnails, search, filters (All / Favourites / Parked here /
  Impounded / Shared), sort, capacity meter, rename, favourites, transfer (garage or player),
  share (without changing ownership), sell to player, finance payments, track (waypoint),
  recover lost vehicles, "Go inside".
- Multiplayer garage interiors (routing buckets): walk around your vehicles, sit in them
  (stats HUD), drive straight out, invite friends, members visit together, control panel.
- In-game admin panel: create/edit/disable/delete every location without touching code,
  in-world placement tools for spawn points and interaction points, interior creator
  (entry, cinematic camera path, vehicle slots with fine-tune placement, exit),
  settings editor, player vehicle manager (assign, edit props visually or as JSON, change
  owner/plate, impound, finance, service + ownership history, block, delete), import from
  other garage scripts.
- Impound system: per-impound job access, reason, fee, wait time, "retrievable by owner",
  society fund, staff release.
- Job & gang garages: persistent job-owned fleets or on-demand spawner vehicles with
  grade filters, plate templates, liveries/extras setup menu, max-mods.
- Trailer storage (trailer saved + re-attached with mods and damage).
- Security: duplication protection, spawn pile-up protection, server-side validation of
  every action, proximity checks, rate limiting, logging (Discord + console).
- Performance: no per-frame loops when idle; `lib.points` for proximity; caches on server.

We do NOT copy any other product's code, names, art or assets.

---------------------------------------------------------------------------------------

## 2. Resource layout & file ownership

```
nayzeee-garages/
  fxmanifest.lua                (foundation)
  config/config.lua             (foundation)  shared static config + Config.DefaultSettings
  config/server.lua             (foundation)  server-only: webhooks, admin groups
  config/interiors.lua          (server-interiors agent) IPL profiles (Config.IplProfiles)
  shared/init.lua               (foundation)  NZ namespace, L(), Locales
  shared/utils.lua              (foundation)  NZ.Utils
  bridge/shared.lua             (foundation)  NZ.Framework detection
  locales/en.lua                (foundation)
  bridge/server/{qb,qbx,esx,common}.lua (bridge agent)      NZ.Bridge (server)
  bridge/client/{qb,qbx,esx,common}.lua (bridge agent)      NZ.Bridge (client)
  bridge/client/{keys,fuel,target}.lua (integrations agent) NZ.Keys / NZ.Fuel / NZ.Target
  bridge/server/{keys,housing}.lua    (integrations agent)  NZ.KeysServer / NZ.Housing
  bridge/client/housing.lua           (integrations agent)  compat events
  server/logs.lua                     (integrations agent)  NZ.Logs
  server/db.lua, server/migrations.lua (db agent)           NZ.DB
  server/settings.lua, server/locations.lua, server/access.lua,
  server/exports.lua, server/main.lua  (server-core agent)
  server/vehicles.lua, server/actions.lua (server-vehicles agent)
  server/impound.lua, server/jobs.lua, server/private.lua (server-features agent)
  server/interiors.lua, server/admin.lua, server/import.lua (server-interiors agent)
  client/nui.lua, client/points.lua, client/garage.lua, client/impound.lua,
  client/jobs.lua, client/private.lua, client/main.lua (client-core agent)
  client/vehicle.lua, client/damage.lua (client-vehicle agent)
  client/placement.lua, client/camera.lua, client/interior.lua, client/creator.lua,
  client/admin.lua (client-world agent)
  web/                           (see docs/UI_KIT.md for web ownership)
```

Load order is fixed in `fxmanifest.lua`. Every file **only defines functions/tables** on
the `NZ` namespace at load time. Nothing runs work at load time except:
- `server/main.lua` (last server file) — boots the server (migrate → load → sync).
- `client/main.lua` (last client file) — boots the client.
Use `CreateThread` for anything that must wait.

Never create new global variables except the ones listed here: `NZ`, `Config`,
`ServerConfig` (server only), `Locales`, `L`. Locals everywhere else.

---------------------------------------------------------------------------------------

## 3. Conventions

### 3.1 Namespaces (declared in shared/init.lua — just add functions to them)

```
Shared : NZ.Utils, NZ.Framework (string), NZ.ResourceName
Server : NZ.Bridge, NZ.KeysServer, NZ.Housing, NZ.Logs, NZ.DB, NZ.Settings, NZ.Locations,
         NZ.Access, NZ.Vehicles, NZ.Actions, NZ.Impound, NZ.Jobs, NZ.Private,
         NZ.Interiors, NZ.Admin, NZ.Import
Client : NZ.Bridge, NZ.Keys, NZ.Fuel, NZ.Target, NZ.NUI, NZ.Points, NZ.Garage,
         NZ.ImpoundClient, NZ.JobsClient, NZ.PrivateClient, NZ.Veh, NZ.Damage,
         NZ.Placement, NZ.Camera, NZ.Interior, NZ.Creator, NZ.AdminClient,
         NZ.State (client runtime state: locations, settings, groups, houses)
```

### 3.2 Server callbacks (ox_lib)

- Registered with `lib.callback.register(name, function(source, payload) ... end)`.
- Names: `nz:<area>:<action>` (e.g. `nz:garage:rename`).
- **Every callback returns a result table:** `{ ok = true, data = <any|nil> }` or
  `{ ok = false, error = 'Human readable, already translated message' }`.
  Helpers: `NZ.Utils.ok(data)` / `NZ.Utils.fail(msg)`.
- Every callback must: validate `payload` types (`type(x) == 'string'` etc.), clamp
  numbers, rate-limit (`NZ.Access.rateLimit`), check permissions, never trust client
  coordinates for authorization (use `GetEntityCoords(GetPlayerPed(source))`).
- Wrap bodies with `NZ.Utils.safe(fn)` (pcall + log) when convenient so a Lua error
  returns `fail('Something went wrong')` instead of hanging the client.

### 3.3 NUI ↔ Lua

- Lua → NUI: `NZ.NUI.send(action, data)` → `SendNUIMessage({ action = action, data = data })`.
- NUI → Lua: `fetch('https://nayzeee-garages/<name>', JSON body)`. Every NUI callback
  responds with the same `{ ok, data, error }` shape.
- **Forwarding rule:** a NUI callback named `X` that only needs the server is forwarded
  1:1 to the server callback `nz:X` by `NZ.NUI.forward('X')` (client-core agent). Its
  response is passed through `NZ.Veh.enrichDeep(result)` (adds `label`, `make`, `image`
  to every table that has a numeric `hash`) and then returned to the NUI unchanged.
  Example: NUI `garage:rename` → server `nz:garage:rename`.
- Client-handled NUI callbacks (marked **[client]** in §8) are implemented by the
  owning client agent with `NZ.NUI.register(name, function(data) return result end)`.

### 3.4 Events

- Server → client: `nz:client:<name>` (listed in §9). Client → server events are avoided;
  use callbacks. The few exceptions are listed in §9.
- Local client events fired by the bridge: `nz:client:playerLoaded`,
  `nz:client:playerUnloaded`, `nz:client:jobUpdated` (job), `nz:client:gangUpdated`.
- Local server events fired by the bridge: `nz:server:playerLoaded` (src),
  `nz:server:playerUnloaded` (src). `playerDropped` is handled directly.

### 3.5 Translation

- `L(text, vars)` — gettext style. The **English text is the key**:
  `L('You do not have enough money')`, `L('Parked at {garage}', { garage = name })`.
- `locales/<lang>.lua` set `Locales['<lang>'] = { ['English'] = 'Translated', ... }`.
  `Config.Locale` selects the language. The same table is sent to the NUI (`init`), and
  the NUI uses `t('English text', vars)` the same way. Never invent key ids.

### 3.6 Identity, plates and garage keys

- `identifier`: qb/qbx `citizenid`, esx `xPlayer.identifier`.
- Plates are compared **trimmed + uppercased**: `NZ.Utils.plate(p)`. Entities return
  8-char padded plates; the DB stores whatever the dealership wrote. The DB layer handles
  matching both forms.
- **Garage key** (string) identifies a concrete storage place:
  - `L<id>`  — a location from `nz_locations` (public/job/impound) e.g. `L12`
  - `G<id>`  — a private garage instance (group) e.g. `G3` (group knows its location)
  - `H<id>`  — a housing garage e.g. `Hgrove_1`
  Helpers: `NZ.Utils.key.location(id)`, `NZ.Utils.key.group(id)`, `NZ.Utils.key.house(id)`,
  `NZ.Utils.key.parse(key) -> kind ('L'|'G'|'H'), id (number|string)`.
- Vehicle categories: `car` | `sea` | `air` (`NZ.Utils.vehicleTypeFromClass(class)`).

### 3.7 Units

- Fuel / engine / body are **percent 0–100** everywhere above the DB layer.
- Mileage is stored and passed in **kilometres**; the NUI formats per
  `settings.interface.distanceUnit`.
- Times are **unix seconds** (`os.time()`), durations in hours unless noted.
- Money is an integer.

---------------------------------------------------------------------------------------

## 4. Data model (Lua tables == TS types in web/src/lib/types.ts)

### 4.1 Normalized vehicle row (server, from NZ.DB)

```lua
---@class NZVehicleRow
{
  plate = 'ABC123',            -- trimmed, uppercase
  dbPlate = 'ABC123  ',        -- exact plate string as stored (use for UPDATE ... WHERE)
  owner = 'CITIZENID' | nil,   -- identifier of owning player
  model = 'sultan3' | nil,     -- spawn name if known (qb/qbx `vehicle` column)
  hash = 123456789,            -- model hash (signed 32-bit int as GTA returns)
  props = { ... },             -- ox_lib vehicle properties (lib.getVehicleProperties)
  garageKey = 'L12' | nil,     -- where it is / was last stored
  state = 'garaged' | 'out' | 'impounded',
  nickname = 'My car' | nil,
  vehicleType = 'car'|'sea'|'air',
  ownerType = 'player'|'job'|'gang',
  job = 'police' | nil,        -- job-owned fleet vehicle
  gang = 'ballas' | nil,       -- gang-owned fleet vehicle
  mileage = 1234.5,            -- km
  fuel = 0-100, engine = 0-100, body = 0-100,
  damage = { ... } | nil,      -- NZ.Damage format (§7.3), never sent to NUI
  trailer = { hash, model, props, damage } | nil,
  impound = ImpoundInfo | nil, -- §4.4
  blocked = false,
  finance = Finance | nil,     -- §4.5 (qb/qbx only)
  lastOut = unix | nil,
}
```

### 4.2 Location (table `nz_locations`, JSON `data` + columns id/kind/name/enabled)

All kinds share `LocationBase`. Defaults come from `NZ.Locations.normalize`.

```lua
LocationBase = {
  id = 12, kind = 'garage'|'job'|'private'|'impound', name = 'Legion Square',
  vehicleType = 'car'|'sea'|'air', enabled = true,
  spawnPoints = { {x,y,z,w}, ... },              -- vehicle spawn spots (Vec4)
  openPoints = { { coords = {x,y,z}, radius = 2.0 }, ... },  -- "Open garage" points
  useOpenForStore = true,                         -- store at open points
  storePoints = { { coords = {x,y,z}, radius = 4.0 }, ... }, -- used when ^ is false
  returnToEntrance = false,                      -- after storing, teleport to openPoints[1]
  blip = { enabled = true, sprite = 357, color = 3, scale = 0.7 },
}
GarageLocation (kind 'garage', public) = LocationBase + {
  source = 'personal'|'spawner',   -- personal vehicles, or a public spawner (rentals/free)
  spawner = { SpawnerVehicle... },
  capacity = { mode = 'unlimited'|'limited', appliesTo = 'player'|'total', spaces = 8 },
  access = { mode = 'quick'|'interior'|'both', interiorId = 3 | nil },
  restriction = { type = 'everyone'|'job'|'gang'|'identifier', rules = { JobRule... }, identifiers = { 'CID1', ... } },
}
JobLocation (kind 'job') = LocationBase + {
  source = 'owned'|'spawner', owner = 'job'|'gang', jobs = { JobRule... },
  spawner = { SpawnerVehicle... }, infiniteSpawns = false, setupMenu = true,
  capacity = {...}, access = {...},
}
PrivateLocation (kind 'private') = LocationBase + {
  purchasable = true, price = 50000, maxCopies = 1 (0 = unlimited),
  storage = 'shared'|'personal', sellRefund = 50 (percent),
  capacity = {...}, access = {...},
}
ImpoundLocation (kind 'impound') = LocationBase + {
  jobs = { JobRule... },            -- who may impound / release here
  society = 'police',               -- society account that receives fees ('' = none)
  defaultFee = 500, defaultHours = 0,
}
JobRule = { name = 'police', minGrade = 0 }
SpawnerVehicle = {
  model = 'police', label = '' (display name override), plate = '' ('' = random,
  else template: '#' digit, '@' letter, '*' either, other chars literal, max 8),
  grades = { } (empty = all grades), livery = -1 (-1 = default), extras = { ['1'] = true },
  maxMods = false, price = 0,
}
```

House garages are runtime-only (from housing integrations, §6.2):
`{ id = 'H<houseId>', kind = 'house', name, vehicleType = 'car', spawnPoints = {vec4},
openPoints = {{coords, radius}}, useOpenForStore = true, storePoints = {}, ... }`.

### 4.3 Interior (table `nz_interiors`)

```lua
Interior = {
  id = 3, name = 'Executive Collection', enabled = true,
  profile = 'vinewood_car_club' | nil,     -- key in Config.IplProfiles, nil = manual coords
  options = { style = 'club', stairs = 'enabled' }, -- profile option values
  entry = {x,y,z,w},                       -- where players appear
  gtaInteriorId = 291841 | nil,            -- informational
  cutscene = { enabled = false, transition = 3000, returnTime = 1000,
               points = { { coords = {x,y,z}, rot = {x,y,z}, fov = 50.0 }, ... } },
  slots = { {x,y,z,w}, ... },              -- display vehicle positions
  exit = {x,y,z,w} | nil,                  -- walk-out marker (defaults to entry)
}
IplProfile (Config.IplProfiles[key]) = {
  label = 'Vinewood Car Club', coords = vec4|nil, slots = 10,
  ipls = { ... }, entitySets = { ... }, interiorCoords = vec3|nil,
  options = { { key = 'style', label = 'Style', default = 'club',
                choices = { { value = 'club', label = 'Club', entitySets = {...} }, ... } } },
}
```

### 4.4 ImpoundInfo

```lua
{ locationId = 5, locationName = 'Davis Impound', reason = 'Obstructing a driveway',
  fee = 500, by = 'CID' | nil, byName = 'Officer Hayes', at = unix, releaseAt = unix,
  retrievable = true }
```

### 4.5 Finance (qb `player_vehicles` columns / qbx `vehicle_financing`)

```lua
{ balance = 960000, payment = 60000, paymentsLeft = 16, paymentsTotal = 24 | nil,
  intervalHours = 168 | nil, nextPaymentHours = 71 | nil, overdue = false }
```

### 4.6 Groups (private garage instances)

`nz_groups(id, location_id, label, owner, price, created_at)` +
`nz_group_members(group_id, identifier, name, role 'owner'|'member')`.
A purchasable private location can have `maxCopies` groups. Each group is its own garage
(`G<id>`) with its own members and vehicles. `storage = 'shared'`: every member sees and
may drive every vehicle stored in the group garage (ownership never changes).
`storage = 'personal'`: members only see their own vehicles there.

### 4.7 Settings (table `nz_settings`, key `settings`, JSON) — edited in admin panel

Exact shape and defaults: `Config.DefaultSettings` in `config/config.lua` (mirrored by
the `Settings` TS type). `NZ.Settings.get('vehicles.saveDamage')` reads a path.

---------------------------------------------------------------------------------------

## 5. Server module APIs

### 5.1 NZ.Bridge (server) — bridge agent, one file per framework, guarded by
`if NZ.Framework ~= 'qb' then return end` etc.

```
NZ.Bridge.getPlayer(src) -> framework player object | nil
NZ.Bridge.getIdentifier(src) -> string | nil
NZ.Bridge.getName(src) -> string                      -- character "First Last"
NZ.Bridge.getJob(src) -> { name, label, grade:number, gradeLabel, onDuty:boolean, isBoss:boolean } | nil
NZ.Bridge.getGang(src) -> same shape | nil            -- nil on ESX
NZ.Bridge.hasGangs -> boolean
NZ.Bridge.getMoney(src, account 'cash'|'bank') -> number
NZ.Bridge.removeMoney(src, account, amount, reason) -> boolean
NZ.Bridge.addMoney(src, account, amount, reason) -> boolean
NZ.Bridge.pay(src, amount, reason) -> boolean, accountUsed  -- uses settings.economy.account
                                                       -- ('cash'|'bank'|'both' = cash then bank)
NZ.Bridge.addSocietyMoney(society, amount) -> boolean   -- qb-banking/Renewed-Banking/qb-management/esx_addonaccount
NZ.Bridge.getSourceByIdentifier(identifier) -> src | nil
NZ.Bridge.getOnlinePlayers() -> { { source, identifier, name }, ... }
NZ.Bridge.getCharacterName(identifier) -> string        -- online or DB lookup, cached
NZ.Bridge.searchCharacters(query, limit, offset) -> rows {identifier,name}, total
NZ.Bridge.isAdmin(src) -> boolean   -- ace 'nayzeee-garages.admin' OR ServerConfig.AdminGroups
NZ.Bridge.getJobs() -> { { name, label, grades = { { grade, label, isBoss } } } }
NZ.Bridge.getGangs() -> same | {}
NZ.Bridge.notify(src, message, type)  -- framework fallback notify (we normally use NUI toasts)
-- fires TriggerEvent('nz:server:playerLoaded', src) / ('nz:server:playerUnloaded', src)
```

### 5.2 NZ.DB — db agent (`server/db.lua`, `server/migrations.lua`)

Uses oxmysql (`MySQL.query.await`, `MySQL.single.await`, `MySQL.scalar.await`,
`MySQL.update.await`, `MySQL.insert.await`, `MySQL.transaction.await`).
Framework vehicle table: qb/qbx `player_vehicles`, esx `owned_vehicles`. Extension
columns (`nz_*`, see SQL file) are added by `NZ.DB.migrate()` after checking
`INFORMATION_SCHEMA.COLUMNS` (works on MySQL and MariaDB). Framework columns are kept in
sync for 3rd-party compatibility (qb `state`/`garage`/`fuel`/`engine`/`body`/`mods`,
esx `stored`/`parking`/`vehicle`).

```
NZ.DB.migrate()                                   -- idempotent, called once at boot
NZ.DB.vehicleTable -> 'player_vehicles' | 'owned_vehicles'
NZ.DB.getVehicle(plate) -> NZVehicleRow | nil
NZ.DB.getVehiclesByOwner(identifier) -> { NZVehicleRow }
NZ.DB.getVehiclesByPlates(plates) -> { NZVehicleRow }
NZ.DB.getVehiclesInGarage(garageKey) -> { NZVehicleRow }   -- any state, nz_garage = key
NZ.DB.getVehiclesByJob(job) / NZ.DB.getVehiclesByGang(gang) -> { NZVehicleRow }
NZ.DB.getImpounded(locationId|nil) -> { NZVehicleRow }     -- state impounded (at that impound)
NZ.DB.getOutVehicles() -> { NZVehicleRow }
NZ.DB.countInGarage(garageKey, ownerIdentifier|nil) -> number  -- state 'garaged' only
NZ.DB.updateVehicle(plate, fields) -> boolean
   -- fields (all optional, normalized names): owner, model, hash, props, garageKey,
   -- garageName (mirrored to qb `garage` / esx `parking`), state, nickname (false = clear),
   -- vehicleType, ownerType, job (false = clear), gang (false = clear), mileage, damage
   -- (false = clear), trailer (false = clear), impound (false = clear), blocked, fuel,
   -- engine, body, finance (false = clear), lastOut
NZ.DB.insertVehicle({ owner, model, hash, plate, props, garageKey, garageName, state,
                      vehicleType, ownerType, job, gang }) -> boolean
NZ.DB.deleteVehicle(plate) -> boolean             -- also removes favourites/shares/events
NZ.DB.plateExists(plate) -> boolean
NZ.DB.changePlate(oldPlate, newPlate) -> boolean  -- framework table + props.plate + nz tables
NZ.DB.resetOutVehicles(mode 'garage'|'impound', impoundInfo|nil) -> number

NZ.DB.locations.all() -> { {id, kind, name, enabled, data(table)} }
NZ.DB.locations.insert(kind, name, enabled, data) -> id
NZ.DB.locations.update(id, kind, name, enabled, data) -> boolean
NZ.DB.locations.delete(id) -> boolean
NZ.DB.interiors.all() / insert(name, enabled, data) -> id / update(id, name, enabled, data) / delete(id)
NZ.DB.settings.load() -> table|nil ; NZ.DB.settings.save(tbl) -> boolean
NZ.DB.groups.all() -> { {id, locationId, label, owner, price, createdAt} }
NZ.DB.groups.create(locationId, label, owner, price) -> id
NZ.DB.groups.update(id, fields{label?, owner?}) ; NZ.DB.groups.delete(id)
NZ.DB.groups.members(groupId) -> { {identifier, name, role} }
NZ.DB.groups.allMembers() -> { {groupId, identifier, name, role} }
NZ.DB.groups.setMember(groupId, identifier, name, role) ; NZ.DB.groups.removeMember(groupId, identifier)
NZ.DB.favourites.get(identifier) -> { [plate] = true }
NZ.DB.favourites.set(identifier, plate, value:boolean)
NZ.DB.shares.forPlate(plate) -> { {identifier, name, sharedBy} }
NZ.DB.shares.forIdentifier(identifier) -> { plate, ... }
NZ.DB.shares.add(plate, identifier, name, sharedBy) ; NZ.DB.shares.remove(plate, identifier)
NZ.DB.shares.clear(plate)
NZ.DB.events.add(plate, kind 'owner'|'service', data) ; NZ.DB.events.list(plate, kind, limit) -> { {id, data, at} }
NZ.DB.events.replace(plate, kind, list)
NZ.DB.searchPlates(query, limit) -> { {plate, owner} }   -- LIKE match on plate (admin search)
NZ.DB.logs.add(event, identifier|nil, plate|nil, data)   -- nz_logs insert (fire and forget)
```

### 5.3 Core — server-core agent

```
NZ.Settings.load() ; NZ.Settings.all() -> table ; NZ.Settings.get(path, default)
NZ.Settings.save(newSettings) -> table (validated/merged against Config.DefaultSettings,
   persisted, synced to all clients via 'nz:client:settings')
NZ.Settings.interface() -> settings.interface table (sent to NUI)

NZ.Locations.load()
NZ.Locations.all(kind|nil) -> { Location }
NZ.Locations.get(id) -> Location|nil              -- id number, or 'H..' house id string
NZ.Locations.normalize(raw) -> Location            -- fills every default, sanitizes
NZ.Locations.save(location) -> Location            -- insert when id == nil, else update
NZ.Locations.delete(id) ; NZ.Locations.setEnabled(id, enabled)
NZ.Locations.sync(target|-1)                       -- 'nz:client:locations' (client views)
NZ.Locations.clientView(location) -> table         -- what clients receive (no secrets)
NZ.Locations.resolveKey(garageKey) -> { kind='L'|'G'|'H', location, group|nil, houseId|nil } | nil
NZ.Locations.keyName(garageKey) -> string|nil      -- "Legion Square", group label, house label
NZ.Locations.capacity(location, garageKey, identifier) -> CapacityInfo|nil
   -- { mode, appliesTo, used, total } (nil when unlimited)
NZ.Locations.registerHouse(houseId, { name, coords=vec4, spawn=vec4|nil }) ; removeHouse(houseId)

NZ.Access.jobAllowed(src, rules, kind 'job'|'gang') -> boolean
NZ.Access.canUse(src, location) -> boolean, reason  -- restriction / job / gang / house / group
NZ.Access.isNear(src, points, maxDist) -> boolean   -- points: list of {coords} or vec
NZ.Access.openSession(src, garageKey, location, extra) -> session
NZ.Access.getSession(src) -> session|nil            -- { garageKey, location, groupId, openedAt, ... }
NZ.Access.closeSession(src)
NZ.Access.requireSession(src, maxDist) -> session|nil, errorMsg  -- also re-checks distance
NZ.Access.rateLimit(src, bucket, ms) -> boolean (true = allowed)
NZ.Access.isAdmin(src) -> boolean
```
Integrations (integrations agent):
```
NZ.Housing.boot()                          -- load qb-houses / ps-housing garages, start refresh
NZ.Housing.hasAccess(identifier, houseId) -> boolean
NZ.Housing.viewsFor(identifier) -> { clientView }   -- house garages this player may use
NZ.Housing.register(houseId, data) ; NZ.Housing.remove(houseId) ; NZ.Housing.setAccess(houseId, identifiers)
NZ.KeysServer.give(src, netId, plate)     -- server-side key systems (e.g. qbx_vehiclekeys)
NZ.Logs.add(event, src|nil, data)          -- event names: 'vehicle.retrieve', 'vehicle.store',
   -- 'vehicle.transfer', 'vehicle.share', 'vehicle.sell', 'vehicle.recover', 'impound.add',
   -- 'impound.release', 'impound.retrieve', 'garage.purchase', 'garage.members',
   -- 'admin.<action>', 'security.<what>' (prefix picks the webhook channel)
```
Callbacks: `nz:keys:give { netId, plate }` / `nz:keys:remove { netId, plate }` (client asks the server to give or remove keys when the key
resource is server-side), `nz:housing:refresh {}` → client views of the player's houses.

Bootstrap callback (server-core): `nz:state:bootstrap {}` →
`{ settings, locations = { clientView... (incl. houses for this player) }, groups = { [locationId]=true }, isAdmin }`.
The client calls it when the player is loaded (and on resource start if already loaded).

`server/main.lua` boots: `NZ.DB.migrate()` → `NZ.Settings.load()` → `NZ.Locations.load()` →
`NZ.Interiors.load()` → `NZ.Private.load()` → `NZ.Vehicles.boot()` → `NZ.Housing.boot()` →
sync to online players. Handles `playerDropped` (close session, interior leave, cancel
offers), `nz:server:playerLoaded` (sync locations/settings/groups/houses to that player),
registers commands (`Config.Commands`). `server/exports.lua` registers server exports (§10).

### 5.4 Vehicles — server-vehicles agent

```
NZ.Vehicles.boot()                    -- restart handling (§7.5), adopt existing entities
NZ.Vehicles.out[plate] = { netId, src, identifier, garageKey, at, spawner=bool, job=string|nil }
NZ.Vehicles.isOut(plate) -> boolean, entity|nil      -- entity exists check via netId
NZ.Vehicles.buildGarageData(src, session) -> GarageOpenData   -- §8 garage payload
NZ.Vehicles.toGarageVehicle(row, ctx) -> GarageVehicle       -- per-viewer view
NZ.Vehicles.canDrive(src, row, session) -> boolean, reason
NZ.Vehicles.retrieve(src, plate, session, opts) -> result     -- §7.1
   opts = { spawnIndex, entityType, fromInterior=false, fromImpound=false, fee=0 }
NZ.Vehicles.store(src, session, payload) -> result            -- §7.2
NZ.Vehicles.markSpawned(src, plate, netId)
NZ.Vehicles.spawnServer(hash, entityType, coords, init, bucket) -> entity, netId  -- server spawn + 'nzInit' state bag
NZ.Vehicles.vehicleTypeOf(row) -> 'car'|'sea'|'air'   -- falls back to NZ.Bridge.getSharedVehicleType for legacy rows
-- added during integration:
NZ.Vehicles.withLock(plate, fn, ...)          -- one operation per plate at a time
NZ.Vehicles.setOut(plate, entry) / clearOut(plate)
NZ.Vehicles.accessOf(src, row, session, cache) -> 'owner'|'shared'|'group'|'fleet'|'staff'|nil
NZ.Vehicles.resolveGarage(src, payload) -> { location, garageKey, groupId, houseId, identifier }
NZ.Vehicles.newContext(src, session, identifier) / ensureContext(ctx)
NZ.Vehicles.spawnFailed(src, plate)           -- client could not create a retrieved vehicle: roll back
NZ.Vehicles.resolveEntityType(hash, hint, category) -- server-trusted CreateVehicleServerSetter type
NZ.Vehicles.removeTrailerOf(plate, row)        -- delete the tracked trailer of an out vehicle
NZ.Jobs.release(plate) / NZ.Jobs.spawnFailed(src, plate)
NZ.DB.financeIntervalHours() -> hours           -- ServerConfig.FinanceIntervalHours / vehicle shop config / 24
NZ.Bridge.getSharedVehicleType(model, hash) -> 'car'|'sea'|'air'|nil   -- qb/qbx shared vehicles
NZ.Impound.impound(plate, opts, src) -> ok, err, impoundUsed   -- may redirect by vehicle category
```
Callbacks: `nz:garage:open`, `nz:garage:refresh`, `nz:garage:retrieve`, `nz:garage:spawned`,
`nz:garage:store`, `nz:garage:track`, `nz:garage:recover`, `nz:garage:nearestWithSpace`.
`server/actions.lua` (`NZ.Actions`): `nz:garage:favourite`, `nz:garage:rename`,
`nz:garage:transferOptions`, `nz:garage:transfer`, `nz:garage:shares`, `nz:garage:share`,
`nz:garage:unshare`, `nz:garage:sell`, `nz:garage:sellRespond`, `nz:garage:payFinance`.

### 5.5 Features — server-features agent

```
NZ.Impound.impound(plate, opts, src|nil) -> boolean, err
   opts = { locationId, reason, fee, hours, retrievable, netId|nil }  -- export too
NZ.Impound.canImpound(src) -> boolean, { locationIds }
NZ.Impound.isStaff(src, location) -> boolean
NZ.Jobs.spawnerList(src, location) -> { SpawnerVehicleView }
NZ.Jobs.isSpawnerVehicle(plate) -> boolean, info
NZ.Jobs.ownedVehicles(src, location) -> { NZVehicleRow }
NZ.Private.load()
NZ.Private.groupsFor(identifier, locationId|nil) -> { group }
NZ.Private.getGroup(id) -> group|nil   -- { id, locationId, label, owner, price, createdAt, members = { identifier = {name, role} } }
NZ.Private.role(groupId, identifier) -> 'owner'|'member'|nil
NZ.Private.copiesUsed(locationId) -> number
NZ.Private.memberLocations(identifier) -> { [locationId] = true }  -- for client prompts
NZ.Private.syncMember(src)            -- 'nz:client:groups'
```
Callbacks: `nz:impound:open`, `nz:impound:refresh`, `nz:impound:retrieve`,
`nz:impound:release`, `nz:impound:formData`, `nz:impoundForm:submit`,
`nz:garage:spawner` (validates + returns spawn data), `nz:forSale:info`, `nz:forSale:buy`,
`nz:garage:members`, `nz:garage:memberAdd`, `nz:garage:memberRole`,
`nz:garage:memberRemove`, `nz:garage:sellGarage`, `nz:garage:switchGroup`.

### 5.6 Interiors & admin — server-interiors agent

```
NZ.Interiors.load() ; NZ.Interiors.all() ; NZ.Interiors.get(id) ; NZ.Interiors.save(i) ; NZ.Interiors.delete(id)
NZ.Interiors.instances[instanceKey] = { bucket, garageKey, ownerIdentifier|nil, groupId|nil,
   interiorId, page, members = { [src] = 'owner'|'member'|'guest' } }
NZ.Interiors.enter(src, session, opts) -> InteriorEnterData   -- sets routing bucket
NZ.Interiors.leave(src) ; NZ.Interiors.playerInstance(src) -> instanceKey|nil
NZ.Admin.*   (callbacks only, all require NZ.Access.isAdmin)
NZ.Import.run(source, json) -> { imported, skipped }
```
Callbacks: `nz:garage:goInside`, `nz:forSale:tour`, `nz:interior:page`, `nz:interior:driveOut`,
`nz:interior:leave`, `nz:interior:invite`, `nz:interior:inviteRespond`, `nz:interior:kick`,
`nz:interior:players`, `nz:admin:*` (§8 admin list), `nz:creator:save`.

---------------------------------------------------------------------------------------

## 6. Client module APIs

```
NZ.Bridge (client): isLoggedIn(), getIdentifier(), getJob() -> {name,label,grade,gradeLabel,onDuty,isBoss}|nil,
   getGang() -> same|nil, notify(msg, type)
NZ.Keys.give(vehicle, plate) ; NZ.Keys.remove(vehicle, plate)          -- integrations agent
NZ.Fuel.get(vehicle) -> 0-100 ; NZ.Fuel.set(vehicle, value)            -- integrations agent
NZ.Target.addSphere(id, coords, radius, options) ; NZ.Target.remove(id)
NZ.Target.addVehicleOption(id, option) ; NZ.Target.available() -> boolean
   options = { { label, icon, onSelect=function() end, canInteract=function() return true end } }

NZ.State = { locations = { [id] = clientView }, settings = table, groups = { [locationId]=true },
             houses = { [houseId] = view }, job = {...}, gang = {...}, ready = false }

NZ.NUI.send(action, data)
NZ.NUI.open(app, data, focus=true)  -- sends 'open', sets focus, remembers open app
NZ.NUI.close(app|nil)               -- sends 'close', releases focus if no app needs it
NZ.NUI.isOpen(app|nil) -> boolean
NZ.NUI.register(name, handler)      -- RegisterNUICallback; handler(data) -> result table
NZ.NUI.forward(name)                -- 1:1 forward to server 'nz:'..name (+ enrichDeep)
NZ.NUI.notify(type, message, title) -- toast (also exported as event 'nz:client:notify')
NZ.NUI.prompt(label|nil, key='E')   -- show/hide interaction prompt
NZ.NUI.hint(data|nil)               -- show/hide key hint bar
NZ.NUI.hud(vehicle|nil)             -- interior stats HUD

NZ.Points.rebuild()   -- (re)create lib.points / target zones / blips for NZ.State.locations
NZ.Garage.open(locationId, extra) ; NZ.Garage.store(location) ; NZ.Garage.retrieve(plate, opts)
NZ.ImpoundClient.open(locationId) ; NZ.ImpoundClient.openForm(vehicle|nil)
NZ.JobsClient.spawn(index) ; NZ.JobsClient.openSetup(vehicle)
NZ.PrivateClient.openForSale(locationId)

NZ.Veh.spawn(opts) -> vehicle|nil   -- client-vehicle agent, §7.1
   opts = { hash, model, coords={x,y,z,w}, plate, props, damage, fuel, mileage, trailer,
            netId (server-spawned: just wait for it and apply), networked=true, warp=true,
            freeze=false, keys=true, locked=false }
NZ.Veh.collect(vehicle) -> { netId, plate, hash, model, props, damage, fuel, engine, body,
                             mileage, entityType, trailer = {netId, hash, props, damage}|nil }
NZ.Veh.findFreeSpawn(points, radius=2.5) -> index, point | nil
NZ.Veh.label(hash|model) -> label ('Make Name'), make, name, imageModel
NZ.Veh.categoryOf(hash) -> 'car'|'sea'|'air' ; NZ.Veh.entityTypeOf(hash) -> 'automobile'|'bike'|'boat'|'heli'|'plane'|'submarine'|'trailer'|'train'
NZ.Veh.enrichDeep(tbl) -> tbl      -- adds label/make/image to every table with numeric `hash`
NZ.Veh.requestModel(hash, timeout) -> boolean
NZ.Veh.delete(vehicle)
NZ.Damage.get(vehicle) -> table ; NZ.Damage.apply(vehicle, data)

NZ.Placement.vehicle({ hash|model, start=vec4|nil, title }) -> {x,y,z,w}|nil   -- §7.6
NZ.Placement.point({ title, start }) -> {x,y,z,w}|nil
NZ.Placement.manage({ kind='spawn'|'open'|'store', points, vehicleType, model }) -> points|nil
NZ.Camera.playPath(points, transitionMs) ; NZ.Camera.stop()
NZ.Interior.enter(data) ; NZ.Interior.leave(exitCoords) ; NZ.Interior.isInside() -> boolean
NZ.Creator.start(creatorData) ; NZ.Creator.stop()
NZ.AdminClient.open(page|nil) ; NZ.AdminClient.setCache(data)
NZ.NUI.setFocus(app, focus) / NUI.syncFocus() / NUI.await(name, payload)
```

---------------------------------------------------------------------------------------

## 7. Core flows

### 7.1 Retrieve ("Drive")
1. NUI `garage:drive {plate}` **[client, garage.lua]**: find free spawn with
   `NZ.Veh.findFreeSpawn(location.spawnPoints)` (none → toast "All parking spots are
   occupied"); compute `entityType = NZ.Veh.entityTypeOf(hash)`.
2. `lib.callback.await('nz:garage:retrieve', false, { plate, spawnIndex, entityType })`.
3. Server `NZ.Vehicles.retrieve`: `requireSession` (+distance), rate limit, load row,
   `canDrive` (owner / shared / group-member / job / gang; state `garaged` at an allowed
   garage per `settings.garages.retrieveMode`; not blocked; not out; finance not overdue),
   take fees, mark `out` (`state='out'`, `lastOut`), log, then either
   - `settings.vehicles.serverSpawn`: `NZ.Vehicles.spawnServer` at the chosen spawn point,
     returns `{ netId, spawn, vehicle }`, or
   - client spawn: returns `{ spawn, vehicle = { plate, hash, model, props, damage, fuel,
     engine, body, mileage, trailer } }`.
4. Client `NZ.Veh.spawn{...}`; reports `nz:garage:spawned {plate, netId}`. Keys via
   `NZ.Keys.give`, fuel via `NZ.Fuel.set`, ped warped unless `vehicles.spawnOutside`.
5. Server keeps `NZ.Vehicles.out[plate]`. Retrieving an out vehicle whose entity still
   exists is **refused** (dupe protection). Out vehicles whose entity is gone show
   `canRecover` in the menu (fee = `garages.recoverFee`).

### 7.2 Store
1. Prompt "Store vehicle" (driver seat, at an open point when `useOpenForStore`, else at
   a store point). Client collects `NZ.Veh.collect(vehicle)` (includes attached trailer).
2. `nz:garage:store { locationId|houseId|groupId, netId, data }` — server resolves the
   garage key for this player at that location (group for private, `H..` for houses).
3. Server validates: entity exists from netId, ped is driver, distance to store/open
   points ≤ `garages.maxDistance`, plate matches a row, row is not `garaged` (else dupe:
   delete entity + log), owner/shared/group/job permission, `checkModel` (entity model ==
   row.hash), capacity, vehicle category matches location `vehicleType`.
4. Saves props (if `saveMods`), fuel/engine/body, mileage, damage (if `saveDamage`,
   deformation only if `saveDeformation`), trailer; sets `state='garaged'`, `garageKey`.
5. Deletes entity (and trailer) server-side, clears `out`, logs. If
   `returnToEntrance`, client teleports to `openPoints[1]`.
6. Spawner (job/public spawner) vehicles: stored = deleted + spawn count released.

### 7.3 Damage format (`NZ.Damage.get`)
```lua
{ v = 1, engine = 1000.0, body = 1000.0, tank = 1000.0, dirt = 0.0,
  doors = { [0]=false...}, windows = { [0]=false... }, tyres = { [0]=0|1|2 (0 ok,1 burst,2 rim) },
  deform = { { offX, offY, offZ, dmgX, dmgY, dmgZ }, ... } -- only when saveDeformation }
```

### 7.4 Impound
- Staff (job in any impound's `jobs`) use ox_target vehicle option / `/impound` →
  `nz:impound:formData` → NUI `impoundForm` → `impoundForm:submit` → server
  `NZ.Impound.impound` (owned: state `impounded` + ImpoundInfo, entity deleted; NPC
  vehicles: just deleted).
- Owner at impound: `nz:impound:open` lists their impounded vehicles at that impound.
  `impound:retrieve` → allowed when `retrievable` and `releaseAt <= now`, pays `fee` (to
  `society` when set), spawns at the impound spawn point (flow §7.1 with `fromImpound`).
- Staff at impound see all impounded vehicles there; `impound:release {plate, mode}`
  (`owner`: make retrievable now; `garage`: send back to its last garage, free).

### 7.5 Restart behaviour
- `NZ.Vehicles.boot()`: if players are online (resource restart) → re-adopt existing
  networked vehicles whose trimmed plate matches an `out` row (rebuild `out`).
- Otherwise (server start) apply `garages.outOnRestart`: `garage` → all out vehicles
  back to their last garage; `impound` → impounded at `garages.restartImpound` with
  `recoverFee`; `keep` → stay out (recoverable from the menu).

### 7.6 Placement tool (admin + creator)
Ghost entity (alpha 180, no collision, `SetEntityDrawOutline` teal), placed on the ground
under the crosshair raycast. Fine tune: `W/A/S/D` move, `Scroll` rotate, `R` up, `F` down,
`Shift` = faster, `Enter` confirm, `Esc`/`Backspace` cancel. Shows NUI `hint`.

### 7.7 Interiors
`nz:garage:goInside` → server picks the instance (`<garageKey>:<owner|group>`), assigns a
routing bucket (`Config.BucketBase + n`), returns InteriorEnterData:
```lua
{ instanceKey, interior = Interior, garageName, page, pages, slots,
  vehicles = { { slot, plate, hash, model, props, damage, fuel, engine, body, mileage, label?, ownerName, canDrive } },
  role = 'owner'|'member'|'guest', returnTo = vec4 (outside open point) }
```
Client (`NZ.Interior.enter`): fade out, optional cutscene (`NZ.Camera.playPath`), teleport
to `entry`, spawn **local (non-networked)** display vehicles at `slots` (frozen, locked
doors for non-drivable), show HUD when seated in one, control panel on `Config.Keys.interiorPanel`.
Starting to accelerate in a drivable display vehicle → `nz:interior:driveOut {plate}` →
server leaves bucket, runs retrieve with `fromInterior`, returns spawn at the garage's
first free spawn point → client fades, deletes local copies, spawns the real vehicle.
Server broadcasts `nz:client:interior:sync` to the instance whenever its vehicle list
changes (drive out, page change). Walking to `exit` → `nz:interior:leave`.

---------------------------------------------------------------------------------------

## 8. NUI protocol

### 8.1 Lua → NUI messages (`{ action, data }`)

| action   | data | notes |
|----------|------|-------|
| `init`   | `{ locale = table, settings = InterfaceSettings, resource = 'nayzeee-garages' }` | after NUI `ready` |
| `settings` | `InterfaceSettings` | when admin saves settings |
| `open`   | `{ app = AppName, data = AppData }` | opens an app (replaces its data) |
| `update` | `{ app = AppName, data = partial AppData }` | shallow merge into open app data |
| `close`  | `{ app = AppName|nil }` | nil closes every app |
| `hud`    | `HudVehicle|nil` | interior stats HUD (no focus) |
| `prompt` | `{ key = 'E', label = 'Open garage' }|nil` | interaction prompt (no focus) |
| `hint`   | `{ title?, keys = { { keys = {'W','A','S','D'}, label = 'Move' } } }|nil` | key hint bar |
| `notify` | `{ type = 'success'|'error'|'info'|'warning', title?, message, duration? }` | toast |

`AppName` = `garage | impound | impoundForm | forSale | admin | creator | setup | interior`.
Focus: every app except none needs `SetNuiFocus(true, true)`; `hud`/`prompt`/`hint`/
`notify` never take focus.

### 8.2 NUI → Lua callbacks (request → response `data`)
[client] = handled on the client; otherwise forwarded to server `nz:<name>`.

Common
- `ready {}` → null [client]
- `close { app }` → null [client] (release focus, app-specific cleanup)

Garage
- `garage:refresh {}` → GarageOpenData
- `garage:drive { plate }` → null [client]
- `garage:spawner { index }` → null [client → server `nz:garage:spawner`]
- `garage:favourite { plate, value }` → null
- `garage:rename { plate, name|null }` → null
- `garage:transferOptions { plate }` → TransferOptions
- `garage:transfer { plate, type='garage'|'player', target }` → null (target: garage key or serverId)
- `garage:shares { plate }` → ShareData
- `garage:share { plate, serverId }` → ShareData
- `garage:unshare { plate, identifier }` → ShareData
- `garage:sell { plate, serverId, price }` → null (offer sent; buyer confirms)
- `garage:track { plate }` → null [client → server `nz:garage:track` → `{coords}` → waypoint]
- `garage:recover { plate }` → null
- `garage:payFinance { plate, full }` → Finance|null
- `garage:goInside {}` → null [client → server `nz:garage:goInside`]
- `garage:directions {}` → null [client → server `nz:garage:nearestWithSpace` → waypoint]
- `garage:members {}` → MemberData
- `garage:memberAdd { serverId, role }` → MemberData
- `garage:memberRole { identifier, role }` → MemberData
- `garage:memberRemove { identifier }` → MemberData
- `garage:sellGarage {}` → null
- `garage:switchGroup { groupId }` → GarageOpenData

For sale
- `forSale:tour { locationId }` → null [client → server `nz:forSale:tour`]
- `forSale:buy { locationId }` → null (then client opens the garage menu)

Impound
- `impound:refresh {}` → ImpoundOpenData
- `impound:retrieve { plate }` → null [client → server `nz:impound:retrieve`]
- `impound:release { plate, mode='owner'|'garage' }` → ImpoundOpenData
- `impoundForm:submit { plate, netId, impoundId, reason, fee, hours, retrievable }` → null

Vehicle setup [client]
- `setup:livery { index }` → null ; `setup:extra { id, enabled }` → null ; `setup:drive {}` → null

Interior panel
- `interior:page { page }` → null ; `interior:invite { serverId }` → null
- `interior:kick { serverId }` → null ; `interior:players {}` → PlayerOption[]
- `interior:leave {}` → null [client]

Creator [client]
- `creator:pickEntry {}` → `{ entry, gtaInteriorId, gtaInteriorName }`
- `creator:applyProfile { profile, options }` → `{ entry|null }`
- `creator:addCameraPoint {}` → CameraPoint
- `creator:previewCutscene { cutscene }` → null
- `creator:placeSlot { index|null, slot|null }` → Vec4|null
- `creator:showSlots { slots }` → null
- `creator:pickExit {}` → Vec4
- `creator:teleport { coords }` → null
- `creator:walk {}` → null
- `creator:save { interior }` → Interior (server `nz:creator:save`)
- `creator:cancel {}` → null

Admin (all forwarded unless [client])
- `admin:refresh {}` → AdminOpenData
- `admin:location:save { location }` → Location
- `admin:location:delete { id }` → null ; `admin:location:toggle { id, enabled }` → null
- `admin:location:teleport { coords }` → null [client]
- `admin:location:import { source, json? }` → `{ imported, skipped }`
- `admin:points { kind='spawn'|'open'|'store', vehicleType, points, model? }` → points|null [client]
- `admin:pickPosition {}` → Vec4 [client]
- `admin:groups { locationId }` → GroupInfo[]
- `admin:group:save { group }` → GroupInfo ; `admin:group:delete { id }` → null
- `admin:group:member { groupId, identifier, role|null }` → GroupInfo
- `admin:interior:create { name, profile|null, coords|null }` → null [client]
- `admin:interior:edit { id }` → null [client]
- `admin:interior:delete { id }` → null ; `admin:interior:toggle { id, enabled }` → null
- `admin:settings:save { settings }` → Settings
- `admin:players:search { query, page }` → Paged<PlayerSearchRow>
- `admin:players:vehicles { identifier }` → `{ player, vehicles: AdminVehicleRow[] }`
- `admin:vehicle:get { plate }` → AdminVehicleDetail
- `admin:vehicle:assign { identifier, model, plate|'', garageKey }` → AdminVehicleRow
- `admin:vehicle:update { plate, patch }` → AdminVehicleDetail
- `admin:vehicle:delete { plate }` → null

Exact TypeScript request/response types: `NuiCallbacks` in `web/src/lib/types.ts`.

---------------------------------------------------------------------------------------

## 9. Events

Server → client:
- `nz:client:locations (views)` — full list of client views (+ house views for that player).
- `nz:client:settings (settings)`
- `nz:client:groups ({ [locationId] = true })` — private locations the player belongs to.
- `nz:client:houses (views)` — house garages this player can use (integrations; replaces NZ.State.houses).
- `nz:client:notify (toast)` — `{ type, message, title? }`.
- `nz:client:sellOffer ({ offerId, plate, label, price, sellerName })` → client
  `lib.alertDialog` → callback `nz:garage:sellRespond { offerId, accept }`.
- `nz:client:interior:invite ({ inviteId, fromName, garageName })` → alert → `nz:interior:inviteRespond { inviteId, accept }`.
- `nz:client:interior:enter (InteriorEnterData)` — server-initiated enter (invite accepted, tour).
- `nz:client:interior:sync ({ vehicles, page, pages, members })`
- `nz:client:interior:kicked ({ returnTo })`
- `nz:client:openGarage ({ locationId })` / `nz:client:openAdmin ({ page })` (commands)
- `nz:client:impoundForm ()` (command `/impound`)

---------------------------------------------------------------------------------------

## 10. Exports

Server (`exports['nayzeee-garages']:X`): `GetVehicle(plate)`, `GetPlayerVehicles(identifier)`,
`AddVehicle(identifier, model, plate, props, garageKey)`, `SetVehicleGarage(plate, garageKey)`,
`ImpoundVehicle(plate, opts)`, `AddServiceRecord(plate, entry)`, `AddOwnershipRecord(plate, entry)`,
`IsVehicleOut(plate)`, `GetLocations(kind)`, `RegisterHouseGarage(houseId, data)`,
`RemoveHouseGarage(houseId)`, `SetHouseAccess(houseId, identifiers)`.

Client: `OpenGarage(locationId)`, `OpenImpound(locationId)`, `OpenImpoundForm()`,
`StoreVehicle(locationId)`, `OpenAdmin(page)`, `IsInsideInterior()`.

---------------------------------------------------------------------------------------

## 11. Quality bar

- Lua 5.4 syntax only (no CfxLua extensions: no backtick hashes, no `+=`, no `?.`) so
  `luac5.4 -p` and `luacheck` pass. Use `joaat()` / `GetHashKey()` for hashes.
- Every file starts with a short header comment stating its responsibility.
- No busy loops: idle threads `Wait(500+)`; per-frame loops only while a UI/tool is active.
- Every server callback validates input and permissions; every money operation checks the
  return value; every state change is logged through `NZ.Logs.add(event, src, data)`.
- Never trust the client: plates, netIds, coordinates and prices are re-derived server-side.
- Use `lib.print.info/warn/error` for console output; `Config.Debug` gates debug prints
  (`NZ.Utils.debug(...)`).
