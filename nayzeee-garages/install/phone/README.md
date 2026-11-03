# Phone garage apps × nayzeee-garages

Ready-to-copy files that let phone garage apps show nayzeee-garages vehicles and, where the
phone has a valet ("bring my car"), take a vehicle out under nayzeee's rules.

Every file here is **editable code of the phone** (lb-phone's escrow-ignored files, or the
open-source NPWD apps) rewritten to call nayzeee-garages. **Back up the original first.** To
undo, put the original back.

## Support

| Phone / app | Frameworks | Vehicle list | Valet | Map button | Files | Checked against |
|---|---|---|---|---|---|---|
| **lb-phone** (Garage app) | QBCore, Qbox, ESX | ✅ | ✅ | ✅ (with patch B) | `lb-phone/server/custom/frameworks/<qb\|qbox\|esx>/vehicles.lua` + optional `lb-phone/patches/*` | lb-phone 2.9.0 open files (github.com/lbphone/files) |
| **npwd_qbx_garages** | Qbox | ✅ | — (the app has none) | ✅ | `npwd_qbx_garages/server/server.lua`, optional `client/client.lua` | v1.1.0 (Qbox-project) |
| **npwd_qb_garage** | QBCore | ✅ | — | ✅ | `npwd_qb_garage/server/server.lua`, `client/client.lua`, `fxmanifest.lua` | 3.0.3 (npwd-community) |
| **npwd_esx_garage** | ESX | ✅ | — | ✅ | `npwd_esx_garage/server/server.lua`, `client/client.lua` | main (itschip) |
| qs-smartphone, qs-smartphone-pro, yseries, gksphone, okokPhone, high-phone | QBCore, Qbox, ESX | ⚠️ see below | ⚠️ turn off, or wire `generic/` | — | `generic/nayzeee_phone.lua` | **unconfirmed** (escrowed, docs not checked) |

lb-phone on `ox` / `vrp2` / `standalone` is not supported (nayzeee-garages runs on QBCore,
Qbox and ESX).

## What nayzeee-garages provides

Server exports (`exports['nayzeee-garages']:X`):

| Export | Returns | Notes |
|---|---|---|
| `GetPhoneVehicles(source)` | `PhoneVehicle[]` or `nil, error` | The player's vehicles plus vehicles shared with them. Rate limited (1 s; a repeat inside 3 s gets the previous answer). |
| `ClaimVehicleForValet(source, plate)` | `ValetData` or `nil, error` | Same rules as taking the vehicle out of its garage: owner or shared access, not blocked / impounded / out, finance not overdue, access to the garage it is parked in (house access, private-garage membership, job/gang restrictions, garage not closed or deleted). Fleet vehicles, vehicles with a saved trailer and categories outside `valetTypes` are refused. Marks it **out** and starts a delivery claim. Rate limited (2 s), at most `maxPending` undelivered claims per player. |
| `MarkValetSpawned(source, plate, netId)` | `true` or `false, error` | The phone created the vehicle: it is tracked like a normal retrieve (keys from server-side key systems, duplicate protection, mileage, storing it later). Plate and model must match; waits up to 10 s for a server-created vehicle's plate. |
| `ReleaseValetClaim(source, plate)` | `true` or `false, error` | The phone could not deliver: the vehicle goes back to its garage. Refused while any copy exists in the world. |

Net events for phone **client** files (the reporting player must be the claimant):
`TriggerServerEvent('nz:phone:spawned', plate, netId)` and `TriggerServerEvent('nz:phone:failed', plate)`.

Without any report, a watchdog finds the delivered vehicle by plate and model within ~2 s,
and puts a claimed vehicle that never appears back in its garage after `claimTimeout`
(also when the player leaves or switches character). The player gets a notification.
A car of another model that happens to show the same plate is never taken for the valet
vehicle (nor deleted as a duplicate).

Undelivered claims survive a restart of nayzeee-garages (resource KVP `nz_phone_claim:<plate>`):
after the restart the claim resumes, so a vehicle the phone still delivers is adopted (keys
for the claimant if online), and one that never comes goes back to its garage when the
original `claimTimeout` is over (at once when the claimant is offline). A full server start
leaves them to `garages.outOnRestart`; with `keep` they go back to their garage (they were
never delivered).

nayzeee re-applies its saved damage, fuel and mileage to the delivered vehicle (the phone's
own props are applied first). The phone's valet price is charged by the phone; nayzeee
charges nothing for a valet.

### Options (`Config.Phone` in config/config.lua, all optional)

```lua
Config.Phone = {
  valet = true,                 -- allow phone valet claims at all
  valetTypes = { car = true },  -- categories a valet may deliver: car | sea | air
  claimTimeout = 60,            -- seconds (15-300) to deliver before the vehicle goes back
  applyData = true,             -- re-apply saved damage / fuel / mileage to the delivered vehicle
  maxPending = 2,               -- undelivered valet claims per player
  listShared = true,            -- list vehicles shared with the player
  hints = true,                 -- console hint at start for a phone that never called the exports
}
```

The start-up hint (`<phone> found: optional garage app adapter in ...`) is printed for an
installed phone that has never called the exports. It is only a hint: a server that keeps a
phone's stock garage code (see "Other phones") can set `hints = false`.

### `PhoneVehicle`

```lua
{
  plate, plateText,            -- trimmed uppercase plate / plate as stored
  model, hash, label, brand,   -- spawn name (if known), signed model hash, framework label / brand (QB / Qbox)
  nickname, vehicleType,       -- 'car' | 'sea' | 'air'
  ownerType,                   -- 'player' | 'job' | 'gang'
  state,                       -- 'garaged' | 'out' | 'impounded'
  garageKey, garageName, garageCoords,
  impound = { reason, fee, by, at, releaseAt, retrievable, locationId, location, coords } | nil,
  fuel, engine, body,          -- 0-100
  mileage,                     -- km
  financed, finance = { balance, payment, paymentsLeft, nextPaymentHours, overdue } | nil,
  blocked, isOwner, shared, ownerName,
  inWorld, coords,             -- live position when out, else garage / impound position
  valetPending, canValet, valetReason,
}
```

`releaseAt` / `at` are unix seconds (lb-phone wants JS milliseconds: the adapter multiplies by 1000).

### `ValetData`

```lua
{
  plate, plateText, hash, model, label, brand, nickname, vehicleType,
  props,                       -- ox_lib vehicle properties, props.plate / props.model / props.fuelLevel set
  damage,                      -- nayzeee damage format (nil when damage saving is off)
  fuel, engine, body, mileage,
  garageKey, garageName, claimedAt, expiresAt,
}
```

## lb-phone

1. Copy `lb-phone/server/custom/frameworks/<qb|qbox|esx>/vehicles.lua` over the same file in
   lb-phone (only the folder of your framework is used; copying all three is fine).
2. Recommended: apply `lb-phone/patches/client-garage.lua` to
   `lb-phone/client/apps/framework/garage.lua` (two or three lines in `BringCar`) so the valet
   vehicle is reported at once and a failed delivery goes back at once.
3. Optional: apply `lb-phone/patches/server-garage.lua` to
   `lb-phone/server/apps/framework/garage.lua` (puts the vehicle back when lb-phone fails
   after the claim, e.g. not enough money or the server could not create the vehicle; and
   the map button finds vehicles parked in a garage or impound).
4. Restart lb-phone.

Keep lb-phone's `Config.Valet` as you like (price, driver ped, `Config.ServerSideSpawn`).

Keys for a valet vehicle: lb-phone's client `GiveVehicleKey`
(client/custom/functions/functions.lua) still runs (`vehiclekeys:client:SetOwner` =
qb-vehiclekeys), and with qbx_vehiclekeys nayzeee gives the keys on the server. Other
client-side key scripts (wasabi_carlock, MrNewbVehicleKeys, qs-vehiclekeys,
Renewed-Vehiclekeys, ...) are **not** reached by a phone delivery the way a normal garage
retrieve reaches them: edit lb-phone's `GiveVehicleKey` for them, as you would without
nayzeee-garages.

Impounded vehicles show the impound, reason, fee and officer; the release time is only sent
when the owner may get the vehicle out (none for a police hold).

Unconfirmed: how lb-phone's escrowed UI uses `Config.Valet.VehicleTypes`. Boats and aircraft
are sent as type `boat` / `aircraft`; nayzeee refuses them anyway unless `valetTypes` allows them.

## NPWD garage apps

Keep the resource folder names (`npwd_qb_garage`, `npwd_qbx_garages`, `npwd_esx_garage`): the
prebuilt UIs call `https://<folder>/...`. Only Lua files are replaced, nothing is rebuilt.

- **npwd_qbx_garages**: replace `server/server.lua` (and optionally `client/client.lua` for the
  map button). qbx_garages no longer has to be started.
- **npwd_qb_garage**: replace `server/server.lua`, `client/client.lua` and `fxmanifest.lua`
  (drops `@qb-garages/config.lua` and oxmysql). Fixes the app hanging for a player with no
  vehicles.
- **npwd_esx_garage**: replace `server/server.lua` and `client/client.lua` (both; the original
  client asks esx_garage / esx_boat for positions). Impounded vehicles show
  "<impound> (impounded)" and the map button points at the impound. The app's map button only
  sends the place name, so two different places with the same name get a suffix
  ("House garage (Hgrove_1)").

As before: ensure the app before `npwd`, and list it in npwd's `config.json` `"apps"`.

## Other phones (unconfirmed)

qs-smartphone(-pro), yseries, gksphone, okokPhone and high-phone keep their garage code in
escrowed files whose names could not be checked. Two options:

1. **No edits**: in the phone's config pick its stock framework garage option
   (`qb-garages` / `qbx_garages` / `esx_garage` / default). The list then reads the framework
   columns nayzeee keeps in sync (QBCore/Qbox `player_vehicles.state / garage / fuel / engine /
   body / depotprice`, ESX `owned_vehicles.stored / parking / pound`). **Turn the phone's valet
   off**: a valet that writes `state = 0` itself is ignored by nayzeee (the vehicle still counts
   as parked) and skips its checks. ESX phones may not read `parking` / `pound`. Set
   `Config.Phone.hints = false` to silence the start-up hint.
2. **Wire the helper**: copy `generic/nayzeee_phone.lua` into the phone, add it to the phone's
   `fxmanifest.lua` server scripts, and in the phone's editable garage file replace the
   vehicle query with `NayzeeePhone.qbRows(source)` / `NayzeeePhone.esxRows(source)` and the
   valet's take-out query with `NayzeeePhone.claim(source, plate)`. See the file header.

## Limits

- A valet delivery gets keys only from server-side key systems and from the phone's own key
  code (see lb-phone above); nayzeee's client key bridge is not involved.

- No lock / unlock, engine or door control from the phone (lb-phone's `toggleLocked` is still
  its own stub).
- Vehicles of a job / gang fleet are listed but never delivered; vehicles with a saved
  trailer must be taken out at their garage.
- The vehicle list is per character and limited to owned and shared vehicles.
