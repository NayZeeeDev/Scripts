# Module: hospital

Hospitals are built in game. A **department** is one hospital / EMS organisation: it has
grades (salary + permissions), outfits, garage vehicles, an HQ with a map blip, staff and
placed **positions** (points). The module owns the data, the staff resolver behind every
permission check, the EMS Manager window, placement mode and what each of its own positions
does at runtime.

## Files

| File | What it does |
|---|---|
| `server/modules/hospital.lua` | database, caches, sanitizing, `NZA.Hospitals` API, staff provider, point sync, beds, paychecks |
| `server/modules/hospital_manager.lua` | EMS Manager callbacks (admins + bosses), `/nzadmin` |
| `server/modules/hospital_runtime.lua` | duty, locker, stash (incl. built-in storage), supply cabinet, garage / helipad, beds |
| `client/modules/hospital.lua` | position types, blips, runtime menus (locker, stash, cabinet, garage, elevator), beds, store-vehicle prompt, radial items |
| `client/modules/hospital_builder.lua` | placement mode (ghost prop / vehicle, marker, raycast, controls) |
| `client/modules/hospital_manager.lua` | opens the manager, relays its actions, placement round-trip, go to, outfit capture / try-on |
| `html/apps/manager/` | EMS Manager window + compact menus |
| `html/apps/builder/` | placement HUD |
| `config/modules/hospital.lua` | `Config.Hospital` |
| `locales/en/hospital.lua` | `hospital.*` strings (also every NUI string) |

## Features

### EMS Manager (`manager` app, v5 window)
- **Explorer**: search, All / Linked / Standalone filter, one folder per department with
  Overview, Roster, Grades, Outfits, Positions, Garage and area folders (Station, Pharmacy,
  Check-in, Transfusion, Surgery, Angiography suite, X-ray, Ultrasound, Beds, Elevators,
  Morgue, Other) with live counts. Unsaved departments get an amber dot. A **Hospital** section
  (admins) shows every department, every position and who is on duty now.
- **Overview**: stat tiles (staff, on duty, positions, vehicles); Identity (display name,
  locked internal name, description); Integrations (framework job, Discord role id, society
  account); **Easy mode** toggle with the explanation text and per-permission overrides;
  **HQ location** (X/Y/Z/H chips, distance, Go to, Re-place in-world); **Map blip** (show,
  12 colour swatches, sprite presets + any id, scale slider, label, short range, live preview).
- **Roster**: stats, hire an online player or any server id / citizen id at a grade, change
  grades inline, fire with confirmation, online / on-duty dots, "via job" for members through
  the framework job link. Refresh button for live status.
- **Grades**: add / remove / reorder, label, internal name, salary, permission chips
  (all 24 `NZA.Const.Perms`) with All / None / copy from the grade below. Staff keep their
  place: the server remaps stored grades when grades move or disappear.
- **Outfits**: "New outfit from my clothes", per outfit a name, grade chips (none = all) and a
  male + female version captured from what you wear (components / props from
  `Config.Hospital.locker`), component summary, Try on, Put my own clothes back.
- **Positions**: an "Add a position" button for **every registered point type** (read from
  `NZA.Points.Types()` at runtime, so other modules' types appear automatically) → placement
  mode; configured list with type filter, coordinates, distance from you, data chips, Go to,
  Re-place, inline editor (label + every data field: toggles, numbers, text) and Delete.
- **Garage**: vehicles (model, label, Car / Heli, minimum grade, livery, extras) and the
  garage / helipad spawn points.
- **Funds** (boss): society balance, deposit / withdraw (cash or bank, quick amounts), payroll.
- New Department modal (display name → auto internal name), delete / fire / discard
  confirmations, Ctrl+S save, ESC asks before throwing away unsaved edits.

### Placement mode (`builder` app + `hospital_builder.lua`)
- Ray from the screen centre (crosshair shown) onto floors and furniture.
- Prop types: translucent ghost of the type's prop, resting on the surface (model bounds),
  outline teal / red where the game supports it. Marker types: glowing sphere, beam, ring and
  heading line. Garage / helipad: ghost of the department's first car / helicopter
  (`Config.Hospital.garage.carModel / heliModel` when it has none). The ghost never collides.
- E confirm, Q / X / Backspace / ESC cancel, ← → rotate (hold), mouse wheel steps, Shift
  faster, Alt fine, Page Up / Down raise / lower, G snap heading. Max distance check, invalid
  spots turn red and refuse E. HUD: icon, "Place <type>", department + kind tags, heading
  dial with snap badge, height, distance meter, status line with coordinates, key row.
- Re-place starts from the old spot. After placing, the manager reopens where you left it.

### Runtime positions
| Type | Who | What |
|---|---|---|
| `duty` | members | Go on / off duty (framework duty through `Bridge.SetDuty` for framework medics, own duty for standalone members) |
| `locker` | members | outfits of your grade that fit your character, civilian clothes back (`Bridge.Clothing`) |
| `stash` | on-duty members, `minGrade` | ox_inventory / qb-inventory / classic qb-style stash, else the built-in storage window (stacks, metadata items kept per unit) |
| `boss` | grades with `manage` | the manager limited to the department |
| `storage` | on-duty members | supply cabinet, items from `Config.Hospital.storage.items` with per-shift limits and optional perm |
| `garage` / `heli` | on-duty members | vehicles of the right kind for your grade, server-side spawn when the spot is clear, plate, keys, fuel, livery, extras, colour, warp; store back (target or [E] while driving in) |
| `elevator` | everyone / staff only | floors with the same `group`, sorted by `order`, fade teleport |
| `bed` | everyone | lie down (frozen, looped anim, [X] get up), `OccupyBed` → `patient.meta.bed` + `meta.inBed` (healing ×4) |
| `respawn` | — | `NZA.Hospitals.RespawnPoint` |
| `hq` | — | department HQ + blip (stored on the department, never a point) |

Paychecks: on-duty members of standalone departments get their grade salary every
`Config.Hospital.paycheck.interval` minutes (optionally from the society, optionally all departments).

## Staff & permissions
`NZA.Staff.Provider` is installed once the database is loaded:
1. a stored staff row (`nza_staff`) → that department and grade;
2. else a department whose `job` equals the framework job → grade = the department grade with
   the highest level ≤ the framework grade;
3. else no department → the core default (`Config.DefaultPerms`).

Record fields: `hospital dept deptLabel grade gradeLabel gradeName salary perms easy onDuty
medic police job jobLabel isBoss linked frameworkMedic` (+ `excluded` for fired linked members).
`easy` = the department switch, then per-permission overrides. Duty: framework medics follow
the framework duty, everyone else uses the module's own duty. Every manager change refreshes
the affected players (`NZA.Staff.Refresh` → `nza:staff:update`).

## Config keys (`Config.Hospital`)
`newDepartment` (job, easy, blip, grades, vehicles) · `limits` · `builder` (maxDistance,
rotateSpeed, fastFactor, fineFactor, scrollStep, snapAngle, heightSpeed, maxHeight, ghostAlpha,
markerColour, badColour) · `staff` (bossOutranks, syncFrameworkJob, fireJob) · `duty` (radial,
requirePoint, range, offDutyCivvies) · `paycheck` (enabled, interval, standaloneOnly,
fromSociety, account) · `locker` (components, props, anim) · `stash` (slots, weight,
ownStorage, maxStacks) · `storage` (shiftReset, shiftHours, items[{ key, limit, perm? }]) ·
`garage` (platePrefix, fuel, warp, clearRadius, maxPerPlayer, storeRadius, deleteOnDrop,
heliModel, carModel) · `elevator.fade` · `bed` (dict, clip, zOffset, getUpKey, exitSide) ·
`blips` (colours, sprites) · `rates` (manager, runtime). Command: `Config.Commands.admin`.

## API

Server (`NZA.Hospitals`):
```lua
Get(id) All() Nearest(coords) → dept, dist      Points(type?, hospitalId?) Point(id)
RespawnPoint(coords) → { id, hospital, coords, label, data } | nil
FreeBed(hospitalId?) → point | nil   OccupyBed(pointId, pid) → bool   ReleaseBed(pointId) → bool   BedOccupant(pointId)
Department(src) IsMember(src, id) Society(id) Ready()
```
Client: `NZA.Hospitals.Departments()`, `Department(id)`, `ToggleDuty(on?, pointId?)`, `InBed()`.

Server bus: `hospital:changed (deptId)`, `hospital:points (reason, point|id)`,
`hospital:bed (pointId, pid, occupied)`, `hospital:duty (src, onDuty)`. Client bus: `hospital:depts (depts)`.

## Events & callbacks
| Name | Kind | Payload |
|---|---|---|
| `nza:hospital:ready` | C→S | — (client booted: sends points + departments) |
| `nza:points:sync / upsert / remove` | S→C | §17 |
| `nza:hospital:depts` | S→C | public departments `{ id, label, job, hq, blip, vehicles[{ model, type, label }] }` |
| `nza:hospital:openManager` | S→C | `'admin'` (from `/nzadmin`) |
| `nza:hospital:mgr:open / create / save / delete / hire / grade / fire / point:add / point:move / point:data / point:delete / hq / funds` | callbacks | `{ ok, err?, msg?, data? }` (data = fresh manager snapshot) |
| `nza:hospital:duty / locker / stash / stash:move / storage / storage:take / garage / garage:spawn / garage:store / bed` | callbacks | see `hospital_runtime.lua` header |

NUI: `manager:create save delete hire grade fire pointData pointDelete funds place goto capture
tryOn restore refresh wear civvies take spawn floor stashMove`. Radial (`NZA.RadialItems`):
`hospital_duty` (off by default, `Config.Hospital.duty.radial`), `hospital_manager` (admins).

## Security
Admin actions check `NZA.Core.IsAdmin`. Bosses need `manage` in their department grade
(duty not required) **and** to have opened the manager at one of their department's boss points
within 6 m (session, 1 h); with `bossOutranks` they only hire / promote / fire / edit grades
below their own, can't remove `manage` from their own grade, and can't touch identity, job,
easy mode, HQ, blip or positions. Placement is checked against the server-side ped
(`builder.maxDistance + 8 m`). Runtime positions check type, department, distance, duty, grade
and rate limits; vehicles are spawned server-side and only department vehicles near the point
can be stored. Everything the NUI sends is sanitized (ids, lengths, numbers, outfits,
vehicles, point data depth / size).

## Data
`nza_departments (id, label, job, data)`, `nza_points (id, department, type, x, y, z, h, label, data)`,
`nza_staff (identifier, department, grade, name, excluded, hired_by)`,
`nza_hospital_stash (id, items)` — created on start; SQL in `docs/requests/hospital.md`.

## Verification
- `luac5.4 -p` on every Lua file, `node --check` on both apps.
- Server logic executed under plain Lua 5.4 with a FiveM mock (create, duplicate, save, job link,
  easy overrides, hire, duty, grade reorder remap, boss session + outrank rules, fire, funds,
  beds, respawn, garage spawn, supply limits, stash, delete, reload from the database): all pass.
- Browser previews (no console errors): `index.html?app=manager` (+ `&view=roster|grades|outfits|positions|garage|f:beds|h:overview`,
  `&mode=boss`, `&mode=boss&view=funds`, `&mode=locker|storage|garage|elevator|stash`) and
  `index.html?app=builder` (+ `&kind=prop|heli`, `&bad=1`), at 1920×1080 and 1280×720.

## Known limits
- Members through a framework job link follow the framework grade **number**; reordering
  grades changes what those numbers mean (stored staff rows are remapped, framework grades can't be).
- Offline members who only belong through the job link are not listed in the roster.
- Firing / hiring in a linked department changes the framework job only when the bridge offers
  `Bridge.SetJob` (request 2); otherwise a fired member keeps an "excluded" row.
- Department easy mode OFF can't override `Config.EasyMode.default = true` until core supports
  `record.easyDefault` (request 1).
- Stash support for inventories other than ox / qb / qs / ps / lj is the built-in storage window.
- Outfits are native component / prop snapshots of the freemode characters.
- Elevator teleports move only you.
