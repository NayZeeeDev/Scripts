# House garages — housing script integrations

nayzeee-garages gives each house of a supported housing script its own garage. The owner and
the key holders can use it. Every house garage has the garage key `H<prefix>:<id>`, for example
`Hps:12` or `Hvms:7`. A vehicle stored there stays there when the housing script restarts or
the house is sold. Each player sees only their own vehicles and the vehicles shared with them.

`Config.Integrations.housing` (config/config.lua) chooses which scripts are read:

```lua
housing = 'auto',                           -- every supported script below that is started (default)
housing = 'none',                           -- no housing integration (the exports still work)
housing = 'ps-housing',                     -- one script (resource name or prefix, e.g. 'ps')
housing = { 'loaf_housing', 'vms_housing' } -- several
```

In `'auto'` mode qb-houses is skipped while qs-housing runs, because both use the same tables.

## Supported scripts

| Script (resource) | House id | Support | What you have to do | Confidence |
|---|---|---|---|---|
| qb-houses | `qb:<house name>` | Automatic | nothing | high (open source) |
| ps-housing | `ps:<property id>` | Automatic | nothing | high (open source) |
| esx_property | `esx:<property number>` | Automatic, optional edit (both) | nothing; optional edit + convar to use esx_property's own marker | high (open source) |
| qs-housing | `qs:<house name>` | Automatic, optional bridge files (both) | nothing; optional: 2 files + `Config.Garage` | medium |
| loaf_housing | `loaf:<property id>` | Automatic, optional edit (both) | `Garage = false` in loaf_housing's config | medium |
| rtx_housing | `rtx:<houseid>` | Automatic, optional edits (both) | nothing; optional: `Config.GarageSystem` + 2 edits | medium |
| bcs_housing | `bcs:<home id>` | Automatic, optional edit (both) | nothing; optional: GaragePrompt edit + convar | low |
| RxHousing | `rx:<property id>` | Automatic access + fmLib adapter (both) | copy 1 file into fmLib | medium |
| vms_housing | `vms:<property id>` | Hook file (required) | copy 1 file, add to `DetectActiveGarage` | medium |
| tk_housing | `tk:<property id>` | Hook edit (required) | edit `OpenGarageMenu`, enable the custom garage menu | medium-low |
| nolag_properties | `nolag:<property id>` | Hook file (required) | copy 1 file, `Garage = "nayzeee-garages"` | medium |

Any other script can use the exports at the end of this page.

### Automatic

nayzeee-garages reads the script's own data through its exports or database tables: the garage
position, the owners and the key holders. It then draws its own marker, prompt or target at the
garage. The data is read again every 5 minutes, and sooner when the script signals a change:
an event, a key change or a resource restart. Key-change events that a player's client sends
reload that script at most once every 30 seconds, however many players send them. If a read
fails, the houses loaded before are kept; an empty read is only trusted when the next read (at
least a minute later) confirms it. Long lists are read in steps, so thousands of properties do
not stall the server.

Where the script has a live key check (HasKey and similar), it is asked first. For vms_housing,
tk_housing, nolag_properties and RxHousing its "no" is final, so a revoked key stops working
within about 10 seconds (live answers are cached that long) instead of at the next read. When a
live check fails (renamed export, player offline), the owners and key holders read before
decide. A house that disappears from a read is only removed when a read at least a minute later
confirms it, so a partial read (script still loading) never deletes a garage.

### Hook

Some housing scripts draw the garage interaction themselves and call a garage script. The file
or edit for that script makes it call the client exports `OpenHouseGarage` / `StoreHouseGarage`.
The server then:

- checks access live with the housing script, for example through its HasKey export, and falls
  back to the owners and key holders it has read;
- places the garage the first time it is used, at the player's **server-side** position
  (coordinates sent by a client are ignored). The garage is moved when it is used more than
  6 m away (at most half of the `garages.maxDistance` setting), but only within 200 m of the
  property's entrance. When the entrance cannot be read, an existing garage is never moved:
  it stays where it was first used and the usual distance check of the garage menu applies.
  The position is kept in the resource KVP across restarts;
- uses one garage per property: numeric ids are normalised (`tk:1.0`, `nolag:021` and
  `nolag:21` are the same garage), and scripts with integer ids refuse anything else;
- keeps the player's access for up to 30 minutes when it only came from the live check (item
  keys, a renter the script does not list), so the garage stays in their list; when the owners
  and key holders read from the script already include the player, they alone decide;
- draws no marker or target of its own, because the housing script already shows one;
- opens the normal nayzeee-garages menu. When the player is driving, the vehicle is stored.

## server.cfg

```cfg
ensure nayzeee-garages          # before vms_housing, nolag_properties, tk_housing (and qs-housing with auto-detect)

# Scripts whose own garage interaction you routed to nayzeee-garages with an optional edit
# below. nayzeee-garages then stops drawing its own point at their garages (comma separated:
# resource names or prefixes):
# set nayzeee_housing_hooked "esx_property,bcs_housing,rtx_housing,loaf_housing,RxHousing"

# Maximum distance in metres between a hook garage and its property (0 = no check). Default 200:
# set nayzeee_housing_hook_range 200

# loaf_housing with AllowGarageKey = false (only owners get the garage):
# set nayzeee_housing_loaf_keys 0

# nolag_properties with Config.PoliceLockdown.DisableGarage = false (the garage stays usable
# during a police lockdown):
# set nayzeee_housing_nolag_lockdown 0

# nolag_properties society (job) properties: let every member of the owning job use the garage,
# not only key holders (off by default; nolag's own garage point requires keys):
# set nayzeee_housing_nolag_society 1
```

The first time a script uses the hook without being listed in `nayzeee_housing_hooked`, the
server console prints a reminder.

## Per script

### qb-houses — automatic
Reads `houselocations.garage` and `player_houses` (owner citizenid plus the `keyholders` JSON).
qb-houses' own `qb-garages:client:*` house events ask for a refresh.

### ps-housing — automatic
Reads `properties`: houses with a garage (`garage_data`), the owner (`owner_citizenid`) and the
key holders (`has_access`). Apartments have no garage in ps-housing. Changes made through
ps-realtor and key changes trigger a reload. The resource restarting also triggers one. Online
players are checked live with `IsOwner`. ps-housing is CC BY-NC-SA and archived: nothing in it
needs to be edited.

### esx_property — automatic, optional edit
Reads `exports.esx_property:GetProperties()`. If that fails, it reads the `esx_properties`
table (1.16.2+), then `properties.json` (1.16.0 and older). It uses garages that are enabled
and have a position, the Owner and the Keys. The data is read again every 2 minutes, and
whenever esx_property syncs a garage or key change to the players.
esx_property always draws its own garage marker. To get a single garage per property, either:
- apply `esx_property/EDIT_client_main.lua` (StoreVehicle / AccessGarage) and add
  `set nayzeee_housing_hooked "esx_property"`; or
- delete esx_property's garage marker block and keep the nayzeee-garages point.

### qs-housing — automatic, optional bridge files
Reads the same tables as qb-houses: `houselocations` (`garage`, including its `coords` and
`slots` form) and `player_houses` (owner and key holders). Online players are checked live
with `CheckHasKey` / `hasKey`.
Optional: copy `qs-housing/client/custom/garages/nayzeee-garages.lua` and
`qs-housing/server/custom/garages/nayzeee-garages.lua`, and set `Config.Garage = 'nayzeee-garages'`
in qs-housing's config. Then garage changes show up at once, and qs-housing's own
OpenGarage / StoreVehicle calls use nayzeee-garages. These files draw nothing; the point is
nayzeee-garages'.

### loaf_housing — automatic
Set `Garage = false` in loaf_housing's config table. It is in `shared/config.lua` on v2 builds,
or `config/config.lua` if your build has that folder. loaf_housing then draws no garage of its
own. nayzeee-garages reads:
- owners from `loaf_properties`;
- key holders from loaf_keysystem's `loaf_keys`;
- the garage from `GetHouses()` (one call per read; `GetHouse(id)` per owned property only when
  that fails), field `garage`: the walk-up point (browse vehicles) at the entrance; vehicles
  appear at the exit and are stored there, like loaf's own garage. If loaf_realtor is installed,
  its `loaf_houses` table is the fallback.

Every owner of the same property shares one garage, and each sees only their own vehicles.
Purchases and key changes trigger a refresh.
Optional: to keep loaf's own interaction instead, see `loaf_housing/EDIT_client_main.lua`.

### rtx_housing — automatic, optional edits
Reads `GetAllProperties()`, or the `houses` table if that fails. It uses:
- `garage { enabled, coords, heading }`;
- the owner;
- players whose rtx permissions include `garage`.

Permission changes and rtx's log events trigger a reload. Online players are checked live with
`GetPropertyPermission(src, id, 'garage')`, which also covers tenants (see Known limits).
Optional (`EDIT_config.lua`, `EDIT_client_other.lua`, `EDIT_server_other.lua`): set
`Config.GarageSystem = "nayzeee-garages"`, which makes rtx push garage changes at once. You
then choose whether nayzeee-garages or rtx draws the interaction. Zero-edit alternative: set
Config.GarageSystem to a garage script you do not run, so rtx draws no garage interaction.

### bcs_housing — automatic, optional edit
Reads `GetHomes()`: the owner and the garage point `data.garage`. A home whose garage is turned
off in `configuration` is skipped. Key holders of owned homes come from `GetKeyHolders(id)` and
only count when `HasKey(id, identifier, 'Garage')` answers true. If that call fails (its
argument order is unconfirmed) they are left out of the list read; online key holders still get
access through the live `HasKey` check.
Optional: `bcs_housing/EDIT_client_garage.lua` makes bcs's own garage prompt open
nayzeee-garages. Add `set nayzeee_housing_hooked "bcs_housing"` with it. If the garage point
cannot be read, the hook places it where the prompt is used, near the home's entrance.

### RxHousing — automatic access, fmLib adapter
Reads `GetAllProperties()`: the owner, the renter (when the entry has one), the key holders,
and `coords.garage` when a property has one. RxHousing events (bought, rented, transferred, key
holder added or removed) trigger a reload. Access is checked live with `HasKey` and the owner.
Copy `RxHousing/fmLib/adapters/client/garage/nayzeee.lua` to
`fmLib/adapters/client/garage/nayzeee.lua`. Note: it routes `FM.garage` for every RX script to
nayzeee-garages while it runs. When the property has no garage point, the garage is placed
where RxHousing's garage marker is used.

### vms_housing — hook file (required)
1. Copy `vms_housing/integration/[garages]/nayzeee-garages/client.lua` to the same path in
   vms_housing.
2. Search vms_housing for `DetectActiveGarage` and add `'nayzeee-garages'` to its list.
3. `ensure nayzeee-garages` before `vms_housing`.

Access comes from `GetAllProperties()`: the owner, the renter and the `keys` map (buildings
are skipped). It is checked live through `GetProperty` (owner / renter / keys),
`HasAnyPermission` and, for online players, `HasKeys`. Key events trigger a reload (rate
limited, see Automatic).

### tk_housing — hook edit (required)
1. Turn on tk_housing's custom garage menu option (reported as `Config.UseCustomGarageMenu`).
2. Replace the body of `OpenGarageMenu` in `client/main_editable.lua` with
   `tk_housing/EDIT_client_main_editable.lua`.

Access comes from `getProperties()`: the owner plus the keys of `permissions`
(`getPropertyKeyholders(id)` only for builds without that field). Unowned properties give
nobody access, job keys (`job:...`) are ignored. It is checked live through `getPropertyData(id)`.
The garage must be within 200 m of the property door.

### nolag_properties — hook file (required)
1. Copy `nolag_properties/custom/garages/nayzeee-garages.lua` to the same path.
2. Set `Garage = "nayzeee-garages"` in nolag_properties' config.lua.
3. Owners place the "Garage" interaction point of their property.

Access is checked live: `GetPropertyData(id)` gives the owner / renter and the key holders,
then `HasKey`. Society (job) properties: key holders only, like nolag's own garage point
(`requireKeys`); `set nayzeee_housing_nolag_society 1` lets every member of the owning job in
(also used when `HasKey` fails). Known houses are read again on every refresh
(`GetKeyHolders`). A property nolag no longer has is dropped when a read at least a minute
later agrees (not during the first 2 minutes after nolag_properties starts). A police lockdown (`metadata.lockdown`) closes the garage on the server too, like
nolag's `Config.PoliceLockdown.DisableGarage`; if you turned that off, add
`set nayzeee_housing_nolag_lockdown 0`. The property's position (its coords, its
`GetAllProperties` entry or the entrance metadata) bounds where the garage can be.

## Exports for other scripts

Client:

```lua
exports['nayzeee-garages']:OpenHouseGarage(houseId, { name = 'Label for a new garage' }) -- stores when driving
exports['nayzeee-garages']:StoreHouseGarage(houseId)
exports['nayzeee-garages']:RefreshHouseGarages()      -- after a key / purchase change on this client
```

Server:

```lua
exports['nayzeee-garages']:RegisterHouseGarage(houseId, {
  name = 'Grove St 1',
  coords = vec4(x, y, z, h),   -- walk-up point (and store point unless `store` is given)
  spawn = vec4(x, y, z, h),    -- optional: where vehicles appear
  store = vec4(x, y, z, h),    -- optional: where vehicles are parked
  hidden = true,               -- optional: your script draws the interaction and calls the client exports
})
exports['nayzeee-garages']:SetHouseAccess(houseId, { 'CID1', 'CID2' })  -- or { CID1 = true, ... }
exports['nayzeee-garages']:RemoveHouseGarage(houseId)
exports['nayzeee-garages']:RefreshHousing('rtx_housing')  -- re-read one supported script (nil = all)
```

A house registered with `RegisterHouseGarage` takes priority over what a loader reads for the
same id. Use your own prefix, for example `myhousing:12`.

## Known limits

- **Hook garages** are placed where they are first used. The housing script decides where its
  interaction is; nayzeee-garages only follows it. Hook garages and automatic house garages
  are runtime-only, so they are not edited in the admin panel.
- **Item keys** (vms_housing with UseKeysOnItem, rtx item keys, any key stored as an inventory
  item) cannot be read for offline players. These players only get access through the
  script's live check while they are online.
- **rtx_housing tenants** are not in the owner / key holder list read from rtx
  (`TenantPropertyPermissions.garage` cannot be read from another resource). While online they
  get access through rtx's `GetPropertyPermission`, which follows that setting.
- **Unknown property position**: if a hook script's property entrance cannot be read (export
  changed, data shape unknown), its hook garages stay where they were first used and the
  console says so once.
- **esx_property** numbers properties by their position in its list. Deleting a property
  renumbers the ones after it. Vehicles stored in their garages then show as parked at another
  property, but they stay visible only to their owners.
- **Vehicles** stored by a previous garage script in its house garages are not moved. Take
  them out with the old script before switching, or move them to a garage in the admin
  panel's player vehicle manager (or with the `SetVehicleGarage` export). The admin import
  skips house garages.
- **Escrowed scripts** (everything except qb-houses, ps-housing, esx_property and loaf's
  keysystem): the names come from vendor documentation, editable files and public
  third-party integrations. Each call is wrapped so that a renamed export only disables that
  part, and the console says so once (again if it fails after working in between). Run with
  `Config.Debug = true` to see the details.
