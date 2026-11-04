# nayzeee-garages

An all-in-one garage system for FiveM: public, job, gang, private (purchasable), house
garages and impounds, multiplayer garage interiors, an in-game garage/interior creator, a
full player-vehicle manager, and a built-in car lock with keys, fobs, crime tools,
locksmiths and a vehicle tracker. Works with **QBCore**, **Qbox** and **ESX Legacy**.

Everything about locations, interiors and rules is created and edited **in game** from the
admin panel. No config files to touch for day-to-day changes. Every integration lives in an
open Lua file you can read and change (`docs/INTEGRATIONS.md`).

---

## Requirements

| Resource | Notes |
|----------|-------|
| [ox_lib](https://github.com/overextended/ox_lib) | required |
| [oxmysql](https://github.com/overextended/oxmysql) | required |
| OneSync | required (`set onesync on`): server-side entity checks, routing buckets, state bags |
| qb-core / qbx_core / es_extended | one of them, started **before** this resource |
| An inventory with item metadata | optional: physical keys, key fobs, signed contracts (ox_inventory, qb-inventory, qs-inventory(-pro), codem, tgiann, origen, core, ps, lj). Without one the car lock uses virtual keys |
| ox_target or qb-target | optional (target interaction, garage NPCs, crime and fake plate options) |
| A notify, dispatch, fuel, housing, phone or banking resource | optional, auto-detected (see *Integrations*) |

## Installation

1. Put the `nayzeee-garages` folder in your resources.
2. `server.cfg` (after your framework, ox_lib, oxmysql and your inventory):
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure qb-core          # or qbx_core / es_extended
   ensure ox_inventory     # your inventory
   # a key script you want to KEEP (qb-vehiclekeys, qbx_vehiclekeys, wasabi_carlock...) goes here,
   # before nayzeee-garages: the built-in car lock then stays off
   ensure nayzeee-garages
   # housing scripts that need a hook file (vms_housing, nolag_properties, tk_housing) after it
   add_ace group.admin nayzeee-garages.admin allow
   ```
3. Add the items: copy the definitions from `install/items/` into your inventory
   (`ox_inventory.lua`, `qb-core.lua`, or `esx_items.sql`) and the images from
   `install/items/images/`. Read `install/items/README.md` first if you already have
   `lockpick`, `advancedlockpick` or `screwdriver` items.
4. Housing: most scripts are read automatically. vms_housing, tk_housing and nolag_properties
   need a small file copied into them, others have optional edits: `install/housing/README.md`.
5. Phone apps (optional): copy the files for your phone from `install/phone/`
   (`install/phone/README.md`).
6. Start the server. Tables and columns are created automatically
   (`install/nayzeee-garages.sql` is only a reference).
7. In game, run `/garageadmin` and create your garages, impounds and interiors.
   Coming from qb-garages / qbx_garages? On the first start their locations are imported
   automatically (even if that resource is stopped); you can also use **Garages → Import**.
   Their job and gang garages are imported as job / gang restricted *personal* garages
   (members keep storing their own vehicles there, as before). Job / gang fleet garages
   (job-owned vehicles) and spawner garages have to be built in `/garageadmin`. The
   qbx_garages `shared` option (every member sees every car parked there) is not carried over.
8. Stop your old garage resource. If a housing script relied on `qb-garages` events,
   nayzeee-garages already listens to them (see *Integrations*).

Optional server.cfg lines:
```cfg
set nz_carlock_secret "a long random string"   # key item signing secret; same value on servers sharing one database
setr sv_stateBagStrictMode true                # only the server writes state bags (breaks scripts that write entity bags from clients)
```
The housing convars (`nayzeee_housing_*`) are listed in `install/housing/README.md`.

The interface is pre-built in `web/dist`. To change it: `cd web && npm install && npm run build`.

## Features

**Garages**
- **Garage menu ("Showroom")**: two panes. Left: your collection grouped and searchable, with
  filters (all, favourites, parked here, shared, impounded, out), sorting and a capacity
  meter. Right: the vehicle stage, a status strip, condition with a damage diagram,
  performance, upgrades, finance / impound / trailer, and an action dock. Rename, favourites,
  transfer to a garage or player, sharing without changing ownership, selling to a nearby
  player, finance payments, track a vehicle (waypoint), recover lost vehicles. Keyboard: ↑/↓
  select, Enter runs the main action, F favourite, R rename, / search, Esc close.
- **Car, boat and air** garages and impounds.
- **Multiplayer interiors**: walk around your collection, sit in a car to see its stats,
  drive straight out, invite friends, members visit together, control panel (`F6`).
- **Interior creator**: pick an IPL profile or any position, cinematic entry camera path,
  place every vehicle slot with a fine-tune gizmo (`W A S D`, scroll, `R`/`F`).
- **Private garages**: purchasable copies with their own members and vehicles, interior
  tours before buying, member roles, selling back when empty, admin-assigned garages.
- **Job & gang garages**: persistent job fleets or on-demand spawner vehicles with grade
  filters, plate templates (`LSPD####`), liveries/extras setup menu and max mods.
- **House garages** for 11 housing scripts: qb-houses, ps-housing, qs-housing, esx_property,
  loaf_housing, rtx_housing, bcs_housing, RxHousing (automatic), vms_housing, tk_housing and
  nolag_properties (a small file to copy). Owners and key holders share the garage, each sees
  their own vehicles. Any other script can use the house exports.
- **Impounds**: per-impound job access, reason, fee, hold time, *retrievable by owner*,
  staff release, society fund deposits. An **NPC flatbed tow truck** drives up and collects
  vehicles impounded with the impound form (the database impound happens at once).
- **Trailers** are stored with their towing vehicle (mods + damage) and re-attached.
- **Damage**: engine/body/tank health, doors, windows, tyres and body deformation.
- **Parking capacity** in total or per player, with directions to the nearest garage with room.
- **Phone garage apps**: lb-phone (vehicle list, valet, map button) and the NPWD garage apps
  for QBCore, Qbox and ESX (list, map button) show nayzeee-garages vehicles; the valet follows
  the garage rules and the delivered vehicle is tracked like a normal retrieve.

**Interaction and notifications**
- **Press E, target or both**, globally or per location, with an optional **NPC** per location
  (model + scenario) that carries the target options. Without ox_target / qb-target everything
  falls back to prompts.
- **Notifications** through ox_lib, the framework's own, okokNotify, mythic_notify, pNotify,
  wasabi_notify, brutal_notify, lation_ui, t-notify or your own function. While a garage window
  has focus they are drawn inside it, so they are never hidden behind the window.

**Built-in car lock** (`docs/CARLOCK.md`; off automatically while another key script runs)
- **Physical or virtual keys**: plate-specific `vehicle_key` / `vehicle_fob` items signed by the
  server (forged metadata never opens anything), or server-side keys given from the key ring.
- **Security profiles** per class or model: key or fob, remote locking range, which tools open
  the doors, hotwire method, tracker, native or custom alarm.
- **Ignition**: no key, no engine (bypass classes, models, on-duty job vehicles); engine
  keybind; the engine keeps running when you get out.
- **Crime tools**: lockpick / advanced lockpick / screwdriver / hacking device on locked doors
  (skill checks, break / alarm / alert chances); in the driver seat without a key, **hotwire**
  (skill check, progress or hack) and **search** the vehicle once for money, items or a spare
  key. A lockpick used away from a locked car is passed on to your house / store robbery
  script (per inventory: `install/items/README.md`).
- **NPC drivers**: rob a driver at gunpoint (they comply, flee or fight), take the key from the
  dead original driver, and authorized jobs can **request the vehicle** without an alert.
- **Police alerts** through wasabi_mdt, rcore_dispatch, cd_dispatch, qs-dispatch,
  core_dispatch, ps-dispatch, a built-in notification + blip, or your own adapter.
- **Locksmiths** (legal and back-alley): duplicate a key, program a key, change the locks. Every
  service is confirmed first; back-alley keys never reach the tracker.
- **Key ring** (`/keys`, `F7`): every key you hold with lock state and distance, lock / unlock,
  give or hand over a key, revoke virtual keys, and a **tracker** (locate with a waypoint and a
  following blip, remote alarm) for vehicles whose profile has one.
- **Admin `/givekey [id]`**: a temporary key for the vehicle that player sits in.
- **Compatibility**: other scripts' qb-vehiclekeys / qbx_vehiclekeys / wasabi_carlock /
  MrNewbVehicleKeys / qs-vehiclekeys / Renewed-Vehiclekeys / vehicles_keys events and exports are
  answered while those scripts are not running.

**Sales and plates**
- **Sale contracts**: use a blank `vehicle_contract` next to your vehicle, pick a nearby buyer,
  price and terms, sign; the buyer reviews, signs and pays. Ownership, keys and money move only
  when the server agrees; both keep a signed copy that shows whether it is genuine.
- **Fake plates + flathead screwdriver**: fit or remove a `fake_plate` at the rear of a
  vehicle. Keys, locks and garages keep using the real plate; everyone else, police plate
  checks included, sees the fake one.

**Administration**
- **Admin panel**: every location type on a **Map command** page (KPIs, directory, satellite /
  dark / atlas map, inspector with points and quick edits; `/` search, ↑/↓ select, Enter edit,
  Del delete, `F` fit all), in-world placement for spawn and interaction points, interiors,
  settings, and a **player vehicle manager** with a vehicle **Dossier** (overview, condition
  map, upgrades & paint, finance, history, activity log, raw data; keys 1–7 switch tabs).
  Assign vehicles, edit mods visually or as JSON, change owner/plate, impound, finance,
  service and ownership history, block, delete.
- **Security**: server-side validation of every action, proximity checks, rate limits,
  duplication protection, spawn pile-up protection, Discord + database logs.

## Configuration

- `config/config.lua`: framework override, language, integrations (`Config.Integrations`),
  notification look (`Config.Notify`), commands, keys, garage NPC defaults (`Config.Peds`),
  interaction ranges, phone apps (`Config.Phone`) and the **default settings** written on first
  start.
- `config/carlock.lua`: the built-in car lock (`Config.CarLock`: key mode, items, keybinds,
  commands, ranges, ignition, security profiles, search loot, NPC behaviour, locksmiths,
  tracker, dispatch, alarms), the tow truck (`Config.Tow`), contracts (`Config.Contracts`) and
  fake plates (`Config.FakePlates`).
- `config/server.lua`: admin groups, Discord webhooks, database logging (retention days, events to skip).
- `config/interiors.lua`: IPL interior profiles available in the creator.
- Everything else lives in **Admin panel → Settings** (vehicles, garages, transfers,
  impound, economy, interface: accent colour, image URL, units, currency, interaction mode...).

### Commands & keys

| Command / key | Keybind name | Who | What |
|---|---|---|---|
| `/garageadmin [page]` | — | admins | open the admin panel |
| `/impound` | — | impound jobs | impound form for the closest vehicle |
| `E` | `nz_interact` | everyone | open garage / store vehicle (prompt mode) |
| `F6` | `nz_interior_panel` | inside an interior | interior control panel |
| `E` | `nz_interior_exit` | inside an interior | leave at the exit marker |
| `E` | `nz_creator_focus` | interior creator | back to the editor while walking around |
| `E` | `nz_locksmith` | at a locksmith (prompt mode) | open the locksmith |
| `L` · `/lock` | `nz_carlock_lock` | everyone (car lock) | lock / unlock your vehicle or the nearest one you have a key for |
| `G` · `/engine` | `nz_carlock_engine` | drivers (car lock) | engine on / off |
| `F7` · `/keys` | `nz_carlock_keyring` | everyone (car lock) | open / close the key ring |
| `H` | `nz_carlock_hotwire` | driver without a key | hotwire |
| `Z` | `nz_carlock_search` | driver without a key | search the vehicle (once) |
| `/givekey [id]` | — | admins (car lock) | temporary key for the vehicle that player (or you) sits in |

Keys can be rebound in *Settings → Key Bindings → FiveM*. Commands and default keys are set in
`Config.Commands` / `Config.Keys` (`config/config.lua`) and `Config.CarLock.commands` /
`Config.CarLock.keys` (`config/carlock.lua`); an empty value turns the lock, engine and key
ring command / key off. The car lock commands and keys only exist while the built-in car lock
runs; the search key only with `Config.CarLock.search.enabled`.

Inside windows: garage ↑/↓, Enter, F, R, /, Esc · key ring ↑/↓, Enter (lock), L (locate), /,
Esc · admin location pages /, ↑/↓, Enter, Del, Esc, and on the map +/−, arrows, F, 0 · Dossier
1–7 · placement tool W A S D, scroll, R / F, Shift, Enter, Esc / Backspace.

## Notifications

`Config.Integrations.notify` (default `ox_lib`): `ox_lib` | `auto` (the first running of
okokNotify, wasabi_notify, brutal_notify, lation_ui, t-notify, mythic_notify, pNotify, else
ox_lib) | `framework` (QBCore / Qbox / ESX built-in) | `qb` | `qbx` | `esx` (esx_notify, ESX
Legacy 1.9+) | `okokNotify` | `mythic_notify` | `pNotify` | `wasabi_notify` | `brutal_notify` |
`lation_ui` | `t-notify` | `custom`. When the configured resource is not started or its call
fails, ox_lib shows the notification.

`Config.Notify`: `title` (`''` = none), `position` (ox_lib position names; `nil` = each
player's own ox_lib setting), `duration` (ms) and `inInterface`. While a garage window has
mouse focus FiveM draws it above every other resource's interface, so a notification from your
notify resource would be hidden behind it: with `inInterface = true` (default) it is drawn
inside the open window instead. `custom`: edit `NZ.Notify.custom` at the top of
`bridge/client/notify.lua`.

## Integrations (auto-detected)

Each one is an open file with its own adapter list and a custom slot. Files, detection order,
config keys and how to add your own: **`docs/INTEGRATIONS.md`**.

- **Framework**: QBCore, Qbox, ESX Legacy.
- **Inventory**: ox_inventory, qs-inventory(-pro), codem-inventory, tgiann-inventory,
  origen_inventory, core_inventory, ps-inventory, lj-inventory, qb-inventory, framework items.
- **Interaction**: ox_target, qb-target, or press-E prompts; garage NPCs.
- **Notifications**: see above.
- **Vehicle keys**: the built-in car lock, or qbx_vehiclekeys, qb-vehiclekeys, wasabi_carlock,
  MrNewbVehicleKeys, qs-vehiclekeys, Renewed-Vehiclekeys, jaksam vehicles_keys.
- **Police dispatch**: wasabi_mdt, rcore_dispatch, cd_dispatch, qs-dispatch, core_dispatch,
  ps-dispatch, built-in.
- **Fuel**: ox_fuel, LegacyFuel, cdn-fuel, ps-fuel, lj-fuel, okokGasStation,
  qs-fuelstations, Renewed-Fuel, ti_fuel (native fallback).
- **Housing**: 11 scripts (`install/housing/README.md`); the `qb-garages:client:*HouseGarage*`
  events are understood.
- **Phones**: lb-phone, npwd_qbx_garages, npwd_qb_garage, npwd_esx_garage
  (`install/phone/README.md`).
- **Banking (society fees)**: qb-banking, Renewed-Banking, qb-management, esx_addonaccount.

## Exports

Full reference with arguments, return values and examples: `docs/INTEGRATIONS.md` §12.

Server:
```lua
local garages = exports['nayzeee-garages']
garages:GetVehicle(plate)
garages:GetPlayerVehicles(identifier)
garages:AddVehicle(identifier, model, plate?, props?, garageKey?, vehicleType?)  -- returns plate
garages:SetVehicleGarage(plate, garageKey)          -- 'L<locationId>' | 'G<groupId>' | 'H<houseId>'
garages:ImpoundVehicle(plate, { locationId, reason, fee, hours, retrievable })
garages:AddServiceRecord(plate, { item, mileage, shop, at })
garages:AddOwnershipRecord(plate, { identifier, name, via, at, price })
garages:IsVehicleOut(plate)
garages:GetLocations(kind?)                        -- 'garage' | 'job' | 'private' | 'impound'
garages:RegisterHouseGarage(houseId, { name, coords = vec4, spawn = vec4?, store = vec4?, hidden = bool? })
garages:RemoveHouseGarage(houseId)
garages:SetHouseAccess(houseId, { 'identifier1', 'identifier2' })   -- or { identifier = true, ... }
garages:RefreshHousing(resource?)                  -- re-read one supported housing script (nil = all)
garages:GetPhoneVehicles(source) / ClaimVehicleForValet(source, plate) / MarkValetSpawned(source, plate, netId) / ReleaseValetClaim(source, plate)
garages:HasKey(source, vehicle) / GiveKey(source, vehicle, hours?) / RemoveKey(source, vehicle) / GiveKeyItem(source, vehicle)
garages:GetKeyVersion(plate) / Rekey(plate, newOwnerIdentifier?)    -- call Rekey after your own ownership changes
garages:SetVehicleLocked(netId, locked) / IsVehicleLocked(netId)
garages:SendDispatch(source, alert)
garages:StartTow(netId, officerSource?)
```

Client:
```lua
exports['nayzeee-garages']:OpenGarage(locationId?)
exports['nayzeee-garages']:StoreVehicle(locationId?)
exports['nayzeee-garages']:OpenImpound(locationId?)
exports['nayzeee-garages']:OpenImpoundForm()
exports['nayzeee-garages']:OpenAdmin(page?)
exports['nayzeee-garages']:IsInsideInterior()
exports['nayzeee-garages']:OpenHouseGarage(houseId, { name? })   -- housing scripts that draw their own garage point
exports['nayzeee-garages']:StoreHouseGarage(houseId)
exports['nayzeee-garages']:RefreshHouseGarages()
exports['nayzeee-garages']:HasKey(plateOrVehicle)
exports['nayzeee-garages']:ToggleLock(vehicle?)
exports['nayzeee-garages']:ToggleEngine()
exports['nayzeee-garages']:GiveKey(vehicle)        -- temporary key, validated by the server
exports['nayzeee-garages']:OpenKeys(plate?)
```

Dealerships should call `AddVehicle` (or keep inserting into the framework vehicle table:
vehicles without a garage can be taken out from any garage of the right type). With physical
keys, give the buyer a key with `GiveKeyItem`.

## Translations

English text is the translation key. Copy `locales/en.lua` to `locales/<lang>.lua`, fill
`Locales['<lang>'] = { ['Open garage'] = '...' }` and set `Config.Locale`. The same table
translates the interface.

## Development

- `docs/ARCHITECTURE.md`: module contracts, data model, NUI protocol, events, state bags.
- `docs/CARLOCK.md`: the built-in car lock, crime tools, locksmiths, key ring, tow truck,
  contracts and fake plates.
- `docs/INTEGRATIONS.md`: open integration files and the export reference.
- `docs/UI_KIT.md`: the NayZeee UI design system and component API.
- `tools/check-lua.sh`: syntax, accidental globals, luacheck.
- `tools/contract_check.py`: cross-module consistency (functions, callbacks, events, NUI).
- `lua5.4 tools/smoke/smoke.lua server|client qb|qbx|esx`: headless boot + callback smoke test.
- Standalone headless tests, run from the resource root with `lua5.4 tools/smoke/<name>.lua`:
  `carlock`, `carlock_client`, `crime`, `crime_client`, `keyring`, `keyring_client`, `tow`
  (`-v` for details), `contracts`, `notify`, `phone`, and `housing.lua server|client`.
- `cd web && npx tsc --noEmit`: type check of the interface.
- `cd web && npm run dev`: browser preview of every screen with mock data (`?mock=<id>`).
