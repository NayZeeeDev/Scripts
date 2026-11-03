# nayzeee-garages

An all-in-one garage system for FiveM: public, job, gang, private (purchasable), house
garages and impounds, multiplayer garage interiors, an in-game garage/interior creator and
a full player-vehicle manager. Works with **QBCore**, **Qbox** and **ESX Legacy**.

Everything about locations, interiors and rules is created and edited **in game** from the
admin panel. No config files to touch for day-to-day changes.

---

## Requirements

| Resource | Notes |
|----------|-------|
| [ox_lib](https://github.com/overextended/ox_lib) | required |
| [oxmysql](https://github.com/overextended/oxmysql) | required |
| qb-core / qbx_core / es_extended | one of them, started **before** this resource |
| ox_target or qb-target | optional (target interaction mode + "Impound vehicle" option) |

## Installation

1. Put the `nayzeee-garages` folder in your resources.
2. `server.cfg` (after your framework, ox_lib and oxmysql):
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure qb-core          # or qbx_core / es_extended
   ensure nayzeee-garages
   add_ace group.admin nayzeee-garages.admin allow
   ```
3. Start the server. Tables and columns are created automatically
   (`install/nayzeee-garages.sql` is only a reference).
4. In game, run `/garageadmin` and create your garages, impounds and interiors.
   Coming from qb-garages / qbx_garages? On the first start their locations are imported
   automatically (even if that resource is stopped); you can also use **Garages → Import**.
5. Stop your old garage resource. If a housing script relied on `qb-garages` events,
   nayzeee-garages already listens to them (see *Housing*).

The interface is pre-built in `web/dist`. To change it: `cd web && npm install && npm run build`.

## Features

- **Garage menu**: grid and list views with vehicle images, search, filters (all, favourites,
  parked here, shared, impounded, out), sorting, capacity meter, rename, favourites,
  transfer to a garage or player, sharing without changing ownership, selling to a nearby
  player, finance payments, track a vehicle (waypoint), recover lost vehicles.
- **Car, boat and air** garages and impounds.
- **Multiplayer interiors**: walk around your collection, sit in a car to see its stats,
  drive straight out, invite friends, members visit together, control panel (`F6`).
- **Interior creator**: pick an IPL profile or any position, cinematic entry camera path,
  place every vehicle slot with a fine-tune gizmo (`W A S D`, scroll, `R`/`F`).
- **Private garages**: purchasable copies with their own members and vehicles, interior
  tours before buying, member roles, selling back when empty, admin-assigned garages.
- **Job & gang garages**: persistent job fleets or on-demand spawner vehicles with grade
  filters, plate templates (`LSPD####`), liveries/extras setup menu and max mods.
- **Impounds**: per-impound job access, reason, fee, hold time, *retrievable by owner*,
  staff release, society fund deposits.
- **Trailers** are stored with their towing vehicle (mods + damage) and re-attached.
- **Damage**: engine/body/tank health, doors, windows, tyres and body deformation.
- **Parking capacity** in total or per player, with directions to the nearest garage with room.
- **Admin panel**: every location type with a live map, in-world placement for spawn and
  interaction points, interiors, settings, and a **player vehicle manager** (assign vehicles,
  edit mods visually or as JSON, change owner/plate, impound, finance, service and
  ownership history, block, delete).
- **Security**: server-side validation of every action, proximity checks, rate limits,
  duplication protection, spawn pile-up protection, Discord + database logs.

## Configuration

- `config/config.lua`: framework override, language, integrations, commands, keys,
  interaction ranges and the **default settings** written on first start.
- `config/server.lua`: admin groups, Discord webhooks, database logging.
- `config/interiors.lua`: IPL interior profiles available in the creator.
- Everything else lives in **Admin panel → Settings** (vehicles, garages, transfers,
  impound, economy, interface: accent colour, image URL, units, currency...).

### Commands & keys

| Command / key | Who | What |
|---|---|---|
| `/garageadmin [page]` | admins | open the admin panel |
| `/impound` | impound jobs | impound the closest vehicle |
| `E` | everyone | open garage / store vehicle (prompt mode) |
| `F6` | inside an interior | interior control panel |

Keys can be rebound in *Settings → Key Bindings → FiveM*.

## Integrations (auto-detected)

- **Vehicle keys**: qbx_vehiclekeys, qb-vehiclekeys, wasabi_carlock, MrNewbVehicleKeys,
  qs-vehiclekeys, Renewed-Vehiclekeys, jaksam vehicles_keys.
- **Fuel**: ox_fuel, LegacyFuel, cdn-fuel, ps-fuel, lj-fuel, okokGasStation,
  qs-fuelstations, Renewed-Fuel, ti_fuel (native fallback).
- **Target**: ox_target, qb-target.
- **Housing**: qb-houses and ps-housing are loaded automatically; any other script can use
  the house exports below. The `qb-garages:client:*HouseGarage*` events are understood.
- **Banking (society fees)**: qb-banking, Renewed-Banking, qb-management, esx_addonaccount.

## Exports

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
garages:RegisterHouseGarage(houseId, { name, coords = vec4, spawn = vec4? })
garages:RemoveHouseGarage(houseId)
garages:SetHouseAccess(houseId, { 'identifier1', 'identifier2' })
```

Client:
```lua
exports['nayzeee-garages']:OpenGarage(locationId?)
exports['nayzeee-garages']:StoreVehicle(locationId?)
exports['nayzeee-garages']:OpenImpound(locationId?)
exports['nayzeee-garages']:OpenImpoundForm()
exports['nayzeee-garages']:OpenAdmin(page?)
exports['nayzeee-garages']:IsInsideInterior()
```

Dealerships should call `AddVehicle` (or keep inserting into the framework vehicle table:
vehicles without a garage can be taken out from any garage of the right type).

## Translations

English text is the translation key. Copy `locales/en.lua` to `locales/<lang>.lua`, fill
`Locales['<lang>'] = { ['Open garage'] = '...' }` and set `Config.Locale`. The same table
translates the interface.

## Development

- `docs/ARCHITECTURE.md`: module contracts, data model, NUI protocol.
- `docs/UI_KIT.md`: the NayZeee UI design system and component API.
- `tools/check-lua.sh`: syntax, accidental globals, luacheck.
- `tools/contract_check.py`: cross-module consistency (functions, callbacks, events, NUI).
- `lua5.4 tools/smoke/smoke.lua server|client qb|qbx|esx`: headless boot + callback smoke test.
- `cd web && npm run dev`: browser preview of every screen with mock data (`?mock=<id>`).
