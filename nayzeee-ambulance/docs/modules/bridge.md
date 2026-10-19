# Module: bridge

Every call nayzeee-ambulance makes to another resource goes through `Bridge`. That
covers the framework, inventory, target, notifications, phone, external dispatch,
vehicle keys, fuel, clothing and society money. All bridge files are open source
(`escrow_ignore`), so server owners can fix or add an adapter without touching
the rest of the resource.

## Files

| File | What it does |
|---|---|
| `bridge/shared.lua` | `Bridge` global, config access, detection (`Bridge.Pick`), priority lists and resource maps, framework detection, job helpers (including the ox_core group → job normalisation `Bridge.OxJob`, used by both sides), item helpers, icon map (NAYZEEE icon → Font Awesome), throttle |
| `bridge/server/framework.lua` | ESX / QBCore / Qbox / ox_core / standalone adapters, player lifecycle hooks, job, duty, money, admin, `nzaJob` state bag |
| `bridge/server/inventory.lua` | 10 inventory adapters, metadata emulation (KVP), usable items, labels, images, client count callback |
| `bridge/server/society.lua` | society/business accounts (8 adapters, including ox_core group accounts) |
| `bridge/server/notify.lua` | `Bridge.Notify(src, data)`: our NUI toast, or a notify resource |
| `bridge/server/phone.lua` | 11 phone adapters, 911/EMS forwarding, `CallEMS` export |
| `bridge/server/dispatch.lua` | `Bridge.Dispatch.External(call)`: mirror to an external dispatch/MDT |
| `bridge/server/vehicle.lua` | plates, server-side keys (qb/qbx), keys net event |
| `bridge/client/framework.lua` | player data, job, lifecycle hooks (ESX / QBCore / Qbox / ox_core / standalone) |
| `bridge/client/notify.lua` | notify adapters (nza toast, nayzeee-notify, ox_lib, okok, codem, mythic, brutal, t-notify, qb, esx, native) |
| `bridge/client/target.lua` | ox_target, qb-target, qtarget, interact, sleepless_interact, built-in [E] fallback, and a registry |
| `bridge/client/inventory.lua` | non-blocking `Has`/`Count`, labels, images |
| `bridge/client/vehicle.lua` | vehicle keys (10 scripts), fuel (7 scripts + native) |
| `bridge/client/clothing.lua` | outfit save/restore (illenium, fivem-appearance, qb-clothing, esx_skin, rcore_clothing, native) |
| `bridge/client/phone.lua` | `IsOpen`, client half of npwd/qs/roadphone adapters |
| `bridge/client/dispatch.lua` | client half of external dispatch adapters |
| `config/modules/bridge.lua` | `Config.Bridge` |
| `locales/en/bridge.lua` | strings (`bridge.*`) |
| `install/*` | item install files, the generator and README |
| `html/img/items/*.png` | 48 item pictures plus `nza_unknown.png` (128x128, transparent) |

## Detection

Every kind of integration has a priority list (`Bridge.Priority.<kind>`) and an
adapter → resource map (`Bridge.Resources.<kind>`) in `bridge/shared.lua`.
`Config.Bridge.<kind>` can be `'auto'`, an adapter name, or a resource name.
Aliases such as `'okokNotify'`, `'qb'` and `'qbx'` are accepted. If a forced
adapter is not running, the bridge warns and falls back to auto-detection.

- Framework: qbx_core, then ox_core, then es_extended, then qb-core, else
  standalone. Qbox goes first because it provides `qb-core`.
  `Config.Bridge.framework` overrides `Config.Framework` when it is not
  `'auto'`; it accepts `'ox'` (or `'ox_core'`) besides `'esx'`, `'qbcore'`,
  `'qbox'` and `'standalone'`. `Bridge.Framework` is set when
  `bridge/shared.lua` loads, so every later file can read it at top level.
- Phone: renewed-phone is checked before qb-phone because it provides
  `qb-phone`.
- Optional kinds are resolved lazily and resolved again when a matching resource
  starts or stops.
- sleepless_interact is checked before ox_target because it provides
  `ox_target` and `qtarget`. qbx_vehiclekeys is checked before qb-vehiclekeys
  for the same reason.

## Config (`Config.Bridge`)

| Key | Default | Meaning |
|---|---|---|
| `framework inventory target notify phone dispatch keys fuel clothing society` | `'auto'` | force an adapter; `false` disables phone, keys, clothing or society |
| `externalDispatch` | `false` | also send every EMS call to the external dispatch |
| `dispatchJobs` | `nil` | jobs alerted externally; `nil` uses `Config.Jobs.medic` |
| `standaloneMedicAce` / `standalonePoliceAce` | `nza.medic` / `nza.police` | standalone jobs; `<ace>.<n>` sets the grade, `<ace>.boss` marks a boss |
| `standaloneGrade` / `standaloneMaxGrade` / `standaloneOnDuty` | `1` / `10` / `true` | standalone defaults |
| `standaloneMoneyItem` | `'money'` | cash item when standalone runs ox_inventory |
| `standaloneFreeBills` / `standaloneFreeItems` | `true` / `false` | standalone without a money or inventory system |
| `offDutyPrefix` | `'off'` | ESX `offambulance` = ambulance, off duty |
| `oxOnDuty` | `true` (not in the shipped file; add it to `Config.Bridge` to change it) | ox_core: duty state of a character after login |
| `phoneEmergency` | see file | 911 numbers, EMS company names, cooldown, reply, extra events |
| `phoneApp` | per phone | app id used for EMS phone notifications |
| `builtinTarget` | E, 2.0 m, 250 ms | built-in target key, reach, scan rate, optional markers |
| `keysDistance` | `8.0` | server check for keys requests |
| `emulateMetadata` | `true` | KVP metadata for inventories without metadata |
| `preferInventoryImages` | `true` | use the inventory's own picture when the file exists |
| `debug` | `false` | print detection results and adapter errors |

## Server API

Everything in ARCHITECTURE §16, plus a few extras:

```lua
Bridge.Framework
Bridge.Ready                                     -- true once players already online were registered
Bridge.OnPlayerLoaded(fn(src), replay?)          -- replay = true also calls fn for players already loaded
Bridge.OnPlayerUnloaded(fn(src))  Bridge.OnJobChanged(fn(src, job))   -- job hook fires only on real changes
Bridge.IsLoaded(src)  Bridge.GetPlayer(src)  Bridge.RefreshJob(src)
Bridge.GetIdentifier(src)  Bridge.GetSourceFromIdentifier(id)
Bridge.GetName(src)  Bridge.GetCharInfo(src) → { firstname, lastname, dob, sex = 'm'|'f', phone }
Bridge.GetJob(src) → { name, label, grade, gradeLabel, onDuty, isBoss }
Bridge.IsMedic(src) Bridge.IsPolice(src) Bridge.IsOnDuty(src) Bridge.SetDuty(src, bool)
Bridge.SetJob(src, job, grade) → bool              -- framework job (ox_core: group); false on standalone
Bridge.HasLicense(src, name) → bool                -- framework licence, else ace nza.license.<name>
Bridge.OxGroup(name)  Bridge.OxJob(groups, activeGroup, onDuty)   -- ox_core helpers (shared, also on the client)
Bridge.IsAdmin(src)            -- ace Config.Admin.ace, or a framework group in Config.Admin.groups
Bridge.GetPlayers()  Bridge.GetMedics(onDutyOnly)
Bridge.GetMoney(src, 'cash'|'bank')  Bridge.RemoveMoney(src, account, amount, reason) → bool  Bridge.AddMoney(...)
Bridge.Society.Get(name) / Add(name, amount) / Remove(name, amount) / Resource()
Bridge.Inv.HasItem / Count(src, name, metaMatch?) / AddItem / RemoveItem(src, name, count, metadata?, slot?)
Bridge.Inv.CanCarry / GetItems / GetSlot / SetMetadata / Search / RegisterUsable / Label / Image / Clear / Resource
Bridge.Inv.OpenStash(src, id, { label, slots, weight, owner? }) → bool   -- false = no stash support here
Bridge.Notify(src, { title, message, type, duration })      -- src = -1 for everyone
Bridge.Phone.Notify(src, { title, message, app?, icon?, fallback? })  Bridge.Phone.Mail(src, { sender, subject, message })
Bridge.Phone.Number(src)  Bridge.Phone.Resource
Bridge.CallEMS(src, message, coords?, meta?) → ok, callId
Bridge.Dispatch.External(call) → bool   Bridge.Dispatch.Resource()
Bridge.Vehicle.SetPlate(vehicle, plate)  Bridge.Vehicle.GiveKeys(src, vehicle, plate?)
```

Notes:
- `metaMatch` is a subset match: `{ type = 'O-' }` matches any bag with that type.
- Money amounts must be numbers ≥ 0. Negative or NaN amounts are rejected.
  `RemoveMoney` returns false when the player is short.
- `Bridge.CallEMS` checks the cooldown, takes coordinates from the server-side
  ped, names the caller, and lists the caller as a patient when they are wounded.
  It then calls `NZA.Dispatch.Create`. If no dispatch module is running, it
  mirrors the call externally and notifies on-duty medics directly. The dispatch
  module itself should call `Bridge.Dispatch.External(call)` for every call; the
  function returns false unless `externalDispatch` is on.
- `Bridge.SetJob` (used by the hospital for hire, grade change and fire):
  - ESX: `xPlayer.setJob`. Refused when `ESX.DoesJobExist` says no. Old ESX
    returns nothing from `setJob`, so the job is read back to decide.
  - QBCore: `Player.Functions.SetJob`. Refused when the grade is missing from
    `QBCore.Shared.Jobs`, because qb-core would otherwise give "No Grades" level 0.
  - Qbox: `exports.qbx_core:SetJob`, which checks job and grade itself. The
    `qbx:setjob_replaces` convar decides whether the old job stays in the
    player's job list.
  - ox_core: `setGroup(job, grade + 1)` through `CallPlayer`. Refused when the
    group does not exist or has no such grade, or when ox_core refuses it (the
    character already has another group of the same type). `'unemployed'` (the
    hospital's `fireJob`) is no ox group: it removes the character's EMS group
    (grade 0): the active group if it is a medic job, else the first
    `Config.Jobs.medic` group, then a police group. Unrelated groups are kept.
  - A grade change on the same job keeps the current duty state, including ESX
    `off<job>`. A new job uses the framework's default duty.
  - Standalone returns false (jobs are aces), so the hospital keeps its
    "excluded" staff row.
- `Bridge.HasLicense` checks QBCore / Qbox `metadata.licences[name]`, ESX
  `esx_license:checkLicense` (2 s timeout; it yields, so call it from a thread)
  and ox_core `getLicense(name)`. Standalone, and ESX without esx_license, use
  the ace `nza.license.<name>`.
- `Bridge.Inv.OpenStash` opens the stash itself; the caller checks access first.
  - ox_inventory: `RegisterStash(id, label, slots, weight, owner and true)`,
    then `forceOpenInventory(src, 'stash', id)`.
  - qb-inventory 2.x: `OpenInventory(src, id, { label, maxweight, slots })`.
  - ps-inventory: `OpenInventory('stash', id, { maxweight, slots }, src)`. ps
    renamed its stash net events, so the classic qb flow does not reach it.
  - qb-inventory 1.x, lj-inventory, qs-inventory: the client fires
    `inventory:server:OpenInventory` + `inventory:client:SetCurrentStash`
    (event `nza:bridge:inv:openStash`).
  - codem, origen, tgiann, core_inventory and plain ESX/QB return false, and the
    caller falls back to its own storage. Add `openStash = fn(src, id, opts)` to
    the adapter to support one.

## ox_core

Checked against the ox_core 1.x source (overextended and CommunityOx). The
adapter uses the raw exports, so `@ox_core/lib/init.lua` is not needed in the
fxmanifest: `GetPlayer` / `GetPlayers` / `GetPlayerFromCharId` return plain
data (`source`, `userId`, `charId`, `stateId`, ...), and player and account
methods go through `CallPlayer(src, method, ...)` and
`CallAccount(accountId, method, ...)`.

| | ox_core |
|---|---|
| Loaded | server `ox:playerLoaded` (src, userId, charId); a character switch is `ox:playerLogout` then `ox:playerLoaded`, so the patient is saved and reloaded |
| Identifier | `char:<charId>`, one per character. `GetSourceFromIdentifier` uses `GetPlayerFromCharId`. At character selection there is no identifier and the player is not in `Bridge.GetPlayers()` |
| Character | `get('firstName' / 'lastName' / 'dateOfBirth' / 'gender' / 'phoneNumber')` |
| Job | `Bridge.OxJob(getGroups(), get('activeGroup'), duty)`: the active group if it is an EMS or police group, else the first `Config.Jobs.medic` group, then the first police group, then the active group. Label and grade labels come from `GlobalState['group.<name>']`. `isBoss` = highest grade, or the grade's account role is `owner` |
| Grades | ox grade 1 (the lowest) is bridge grade 0, so `Config.DefaultPerms` and hospital grade levels mean the same on every framework. `rawGrade` keeps the ox grade |
| Duty | ox_core has no duty: the bridge keeps it per character. `Config.Bridge.oxOnDuty` (default `true`) is the state after login; logout resets it |
| Job changes | server `ox:setGroup` and `ox:setActiveGroup` refresh the `nzaJob` state bag. The job is cached for 1 s per player (3 exports per read); these events, duty changes and `SetJob` clear the cache |
| Cash / bank | cash is the ox_inventory money item (`standaloneMoneyItem`); bank is the character's default account (`GetCharacterAccount(charId)`, then `get 'balance'`, `addBalance`, `removeBalance` without overdraw) |
| Society | adapter `ox_core`: `GetGroupAccount(job)`. The group needs `hasAccount` |
| Admin | the ace `Config.Admin.ace`, or an ox group named in `Config.Admin.groups` |
| Usable items | the ox_inventory `usingItem` hook (ox_core has no usable-item API of its own) |
| Client | the job comes from the server through the `nzaJob` state bag (it carries the duty). Until the first bag arrives it is built from the groups with the same `Bridge.OxJob`. Groups follow `ox:setActiveCharacter`, `ox:setGroup` and `ox:setPlayerData` (activeGroup); `ox:playerLoaded` / `ox:playerLogout` (local) drive loaded / unloaded |

ox_core account exports answer asynchronously. Like the ESX society calls,
`GetMoney` / `AddMoney` / `RemoveMoney` and `Bridge.Society.*` must run in a
thread or an event handler. In the ox_core harness runs (pharmacy, billing,
respawn, hospital) no call came from outside a thread.

## Client API

```lua
Bridge.Framework  Bridge.PlayerData()  Bridge.IsLoaded()
Bridge.OnPlayerLoaded(fn, replay?)  Bridge.OnPlayerUnloaded(fn)  Bridge.OnJobChanged(fn(job))
Bridge.GetJob() → { name, label, grade, gradeLabel, onDuty, isBoss }  Bridge.IsMedic()  Bridge.IsPolice()  Bridge.IsOnDuty()
Bridge.Notify(data)  Bridge.NotifyExternal(data)          -- External skips our NUI toast
Bridge.Target.Player/Ped/Entity/Model/Sphere/Box/Remove/RemovePlayer/RemovePed/RemoveEntity/RemoveModel  Bridge.Target.Resource()
Bridge.Inv.Has(name, count?)  Bridge.Inv.Count(name)  Bridge.Inv.CountAwait(name)  Bridge.Inv.Label(name)  Bridge.Inv.Image(name)
Bridge.Vehicle.GiveKeys(vehicle, plate?)  Bridge.Vehicle.RemoveKeys(vehicle, plate?)  Bridge.Vehicle.SetFuel(vehicle, level)  Bridge.Vehicle.GetFuel(vehicle)
Bridge.Clothing.Save()  Bridge.Clothing.Restore()  Bridge.Clothing.HasSaved()
Bridge.Phone.IsOpen()  Bridge.Phone.Resource
```

Target option format (§16):
`{ name, label, icon, distance, order?, canInteract = fn(entity, distance, coords), onSelect = fn(entity, data) }`.
- `icon` can be a NAYZEEE icon name, which is mapped to Font Awesome for
  third-party menus, or a full `fa-...` class.
- An option without a name gets a generated one.
- `canInteract` must return a truthy value for the option to show.
- Everything registered is kept in `Bridge.Target.Registry` and re-applied when
  the target resource restarts, or when the bridge switches to another target
  script. If a target script stops, the built-in fallback takes over.
- interact (darktrc) has no global ped target. Peds within 12 m get a local
  interaction from a 1 s tracker.

`Bridge.Inv.Has` and `Count` never block, so they are safe inside `canInteract`.
- ox_inventory, qb-style inventories and plain ESX are read locally.
- Other inventories use the `nza:bridge:inv:counts` callback with a 1.5 s cache.
  The first read returns the cached value (0 at first) while it refreshes.
- Requests are at least 220 ms apart, so the server's 200 ms throttle never
  answers nil. One request carries every name still being read, up to the
  server's 40. A nil answer is retried 3 times, then the gap grows to 2 s until
  an answer comes back.
- The server invalidates the cache after every add, remove or clear.

## Notifications

`Config.Bridge.notify = 'auto'` uses our own NUI toast:
- Server: `TriggerClientEvent('nza:ui:toast', src, data)`.
- Client: local `TriggerEvent('nza:ui:toast', data)`.

client/core renders the toast. If client/core calls `Bridge.Notify` again while
handling the event (for example as a fallback), a guard sends it to
`NotifyExternal` instead of looping. Any other `notify` value sends
`nza:bridge:notify` to the client, which renders it with that resource.

## Inventory details

- **Usable items with ox_inventory:** `RegisterUsable` installs a `usingItem`
  hook filtered to the item. The hook returns false, so ox never consumes the
  item or plays its own use, and our function runs in a new thread. The
  framework usable (ESX / QBCore / Qbox) is registered as well, because ox
  routes items without `consume` to the framework. The install file sets
  `consume = 0`, so the hook path is used. Only one path ever fires.
- **Other inventories:** usables go through the framework
  (`ESX.RegisterUsableItem`, `QBCore.Functions.CreateUseableItem`,
  `qbx_core:CreateUseableItem`). qs-inventory's own `CreateUsableItem` is tried
  first. Registrations are applied again when the inventory restarts.
- **Callback item:** every usable callback receives
  `item = { name, label, count, slot, metadata, weight }`, normalized from the
  inventory's own shape (`amount`/`info` → `count`/`metadata`).
- **Metadata emulation (plain ESX):**
  - Units added with metadata are stored per character and item in the KVP key
    `nza_meta:<identifier>:<item>`, each with a `serial`.
  - `Search` and `GetItems` return them as single units on virtual slots 10001+.
  - When the real count drops outside our control (dropped, sold), the oldest
    entries are dropped.
  - `RemoveItem` with metadata or a virtual slot removes the right unit.
- **qb-inventory:** 2.x uses its exports (`AddItem`, `RemoveItem`,
  `CanAddItem`, `SetItemData`, `GetItemCount`). Older versions use
  `Player.Functions`. The version is read from the resource metadata.
- **Images (server and client):** the inventory's picture is used if that file
  exists (`LoadResourceFile`). Otherwise `nui://nayzeee-ambulance/html/img/items/<name>.png`,
  then `ItemDefs[key].image`, then `nza_unknown.png`.

## Phones: what was verified

| Phone | Notify | Mail | Number | 911 → NZA dispatch |
|---|---|---|---|---|
| lb-phone | `SendNotification` (docs) | `GetEquippedPhoneNumber` + `GetEmailAddress` + `SendMail` (docs) | `GetEquippedPhoneNumber` | server events `lb-phone:newCompanyMessage`, `lb-phone:newCall` (documented names; payload read defensively) |
| npwd | client `createNotification` (source) | becomes a notification | `getPhoneNumber` (source) | `onCall` + `onMessage` for `phoneEmergency.numbers` (source) |
| yseries | `SendNotification(data, 'source', src)` (TeamsGG docs) | `SendMail(data, 'source', src)` (docs) | `GetPhoneNumberBySourceId` | no public services hook: add its event to `phoneEmergency.events` or call `CallEMS` |
| qs-smartphone(-pro) | `<res>:client:notification` (NAYZEEE multijob) | client `<res>:server:sendNewMail` (community bridges) | `qs-base:GetPlayerPhone` → framework | net event `<res>:server:sendJobAlert` (community-documented, unverified) |
| gksphone | `gksphone:NotificationShow` (multijob) | `SendNewMail(src, data)` (community) | `GetPhoneBySource` | none known |
| okokPhone | `pushNotifyViaPhoneNumber` (okok docs) | `sendEmail` (community) | `getPhoneNumberFromSource` | none known |
| roadphone | `roadphone:notify` (multijob) | client `sendMail` (community) | framework | none known |
| high-phone | `high_phone:notification` (multijob) | becomes a notification | framework | none known |
| renewed-phone | `qb-phone:client:CustomNotification` | `sendNewMailToOffline` (qb-phone API, unverified on renewed) | framework | none known |
| qb-phone | `qb-phone:client:CustomNotification` (qb-phone 1.5 source) | export `sendNewMailToOffline(citizenid, mail)` (source); older releases: the server event of the same name | framework (`charinfo.phone`) | none |

The undocumented lb-phone payloads are read defensively: the reader looks for
job, message, number, source and coordinates under any common key name.
- If the sender is a net client, only that client's source is trusted, and the
  coordinates come from the server-side ped.
- Messages from on-duty medics, such as replies in the company chat, are
  ignored.
- Everything goes through `Bridge.CallEMS`, so the cooldown applies.

`Bridge.Phone.IsOpen()` uses lb-phone `IsOpen` and npwd `isPhoneVisible`, both
verified. Other phones try the common export names once through pcall and
remember the one that answers. The last resort is `LocalPlayer.state.phoneOpen`.
Stock qb-phone exports no open state, so it always ends on that last resort.

## External dispatch: what was verified

- lb-tablet: server `AddDispatch` (community bridge).
- ps-dispatch: client `CustomAlert`, checked against its source.
- cd_dispatch, qs-dispatch, tk_dispatch, origen_police: client calls from
  community bridges.
- rcore_dispatch (`rcore_dispatch:server:sendAlert`) and core_dispatch
  (`addCall`): from the vendors' docs, which could not be reached from here.
  Both are wrapped in pcall.

Client-only dispatch scripts run on one player's client: the caller, else an
on-duty medic, else any player.

## Events

| Event | Dir | Payload | Notes |
|---|---|---|---|
| `nza:ui:toast` | S→C / local | `{ title, message, type, duration }` | sent by Notify; handled by client/core |
| `nza:bridge:notify` | S→C | data | rendered by the configured notify resource |
| `nza:bridge:phone` | S→C | action, payload | client half of phone adapters |
| `nza:bridge:dispatch` | S→C | adapter, call, jobs | client half of external dispatch |
| `nza:bridge:inv:dirty` | S→C | names \| nil | clears the client item cache |
| `nza:bridge:inv:openStash` | S→C | id, { label, slots, weight } | classic qb stash flow for `Bridge.Inv.OpenStash` |
| `nza:bridge:vehicle:keys` | C→S | netId, plate | checked: on-duty medic/police, vehicle exists, within `keysDistance`, plate matches, 1 per second |
| `nza:bridge:vehicle:keys` | S→C | netId, plate | client-side key scripts |
| `nza:callEMS` | server-local | src, message, coords? | other server scripts only (not net) |
| callback `nza:bridge:inv:counts` | C→S | names[] (max 40) → counts | 1 per 200 ms per player |

Export: `exports['nayzeee-ambulance']:CallEMS(src, message, coords?) → ok, callId`.
State bag: `Player(src).state.nzaJob = { name, label, grade, gradeLabel, onDuty, isBoss, medic, police }`.
Bus (NZA.Bus): `bridge:playerLoaded`, `bridge:playerUnloaded`, `bridge:jobChanged`.

## Install files

`lua5.4 install/generate.lua` rebuilds `ox_inventory_items.lua`,
`qb_shared_items.lua` and `esx_items.sql` from `config/items.lua`. Use
`--esx-grams` to write ESX weights in grams. `install/README.md` explains each
inventory.

The generated `.lua` files are snippets to paste into other resources, so they
do not start with the lock guard. They are not in the fxmanifest. The generator
also skips the guard: it stubs `NAYZEEE_LOCK_OK` itself, and it returns at once
if FiveM ever loads it.

## Item pictures

48 hand-drawn SVG illustrations: 3/4 product view, soft shading, NAYZEEE teal
accents, red crosses on first-aid products. They were rendered with Playwright
(Chromium) to 128x128 transparent PNGs and checked on a contact sheet on dark
and light backgrounds. Sources and renderer are in `/tmp/nza-work/bridge/icons/`
(not shipped). `nza_unknown.png` is the fallback picture.

## Testing

All 21 Lua files pass `luac5.4 -p`: 16 bridge files, the config, the locale, the
generator and the 2 generated item files. Only `Bridge` is written as a global.

A mock FiveM runtime in `/tmp/nza-work/bridge/test/` runs the real bridge files
under plain Lua 5.4. Every scenario passes:
- QBCore + ox_inventory + lb-phone + qb-banking + lb-tablet + qb-vehiclekeys
- ESX default inventory with emulated metadata + esx_addonaccount + npwd
- standalone
- QBCore client with ox_target and the built-in fallback, ox_fuel, illenium,
  ps-dispatch
- every target adapter

The integration harnesses in `/tmp/nza-work/integrate/` also cover the later
additions:
- `SetJob` / `HasLicense` on ESX, QBCore and standalone.
- `OpenStash` on ox_inventory and the classic client flow.
- The hospital hire, fire and stash paths that call them.
- The client count cache. A medic idling 60 s next to a patient on standalone
  sends 36 requests per minute, none throttled. Before the fix it was 87, with
  28 answered nil.
- ox_core: a copy of the server harness with an ox_core stub that mirrors the
  1.x exports (plain data from `GetPlayer`, methods through `CallPlayer` /
  `CallAccount`, events with the source first, `GlobalState['group.*']`). 60
  checks pass: identifier and reverse lookup, character info, job and grade
  shift, active group, duty, hire / promote / bad grade / unknown group / fire
  (also with police active, and with only an unrelated group),
  licences, admin, bank and cash, society, logout, character switch with duty
  reset. With the SQL emulator, a downed character A, a switch to character B
  (a new, alive patient) and back to A (down again) keep one patient record per
  character. The integration flows server_flow, flow3, flow6, flow10 and flow11
  (wounded, treatment, respawn, hospital, money) run on it; their only error,
  the flow10 check-in `no_desk`, happens on the standalone baseline too. The
  client harness copy passes 14 loaded / job / group / logout / relog checks.
  116/116 server and 127/127 client files load in every mode.
- qb-phone on QBCore: detection, notification event, mail through the export
  and through the old event, number from `charinfo`, and renewed-phone winning
  when both run.

## Known limits

- yseries, gksphone, okokPhone, roadphone, high-phone, renewed-phone and
  qb-phone expose no public 911/services hook. Server owners add their phone's event to
  `Config.Bridge.phoneEmergency.events`, or call the `CallEMS` export from the
  phone's open config.
- npwd `onMessage` keeps one handler per number. If another script also handles
  `911` messages, change `phoneEmergency.numbers`.
- `Bridge.Society.Get/Add/Remove` on esx_addonaccount wait for its callback.
  Call them from a thread or event handler, never from file top level.
- ESX weights in `esx_items.sql` are rounded to whole kg (minimum 1), because
  ESX's `items.weight` column is an integer.
- Clothing restore needs the same ped model as when it was saved; the native
  snapshot refuses otherwise.
- ox_core pays no salaries. Hospital paychecks only pay departments that are not
  linked to a framework job by default (`Config.Hospital.paycheck.standaloneOnly`);
  on ox_core set it to `false` to pay EMS groups.
- ox_core grades start at 1 and the bridge shifts them to start at 0 (see the
  ox_core section). Hospital grade levels linked to an ox group therefore map
  level 0 to ox grade 1.
