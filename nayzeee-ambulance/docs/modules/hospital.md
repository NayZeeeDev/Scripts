# Module: hospital

Hospitals are built in game. A **department** is one hospital / EMS organisation: it has
grades (salary + permissions), outfits, garage vehicles, an HQ with a map blip, staff and
placed **sites** (points; "positions" in code). The module owns the data, the staff resolver
behind every permission check, the Department Console window, the site survey (placement) HUD
and what each of its own sites does at runtime.

## Files

| File | What it does |
|---|---|
| `server/modules/hospital.lua` | database, caches, sanitizing, `NZA.Hospitals` API, staff provider, point sync, beds, paychecks |
| `server/modules/hospital_manager.lua` | Department Console callbacks (admins + command desk), `/nzadmin` |
| `server/modules/hospital_runtime.lua` | duty, locker, stash (incl. built-in storage), supply cabinet, garage / helipad, beds |
| `client/modules/hospital.lua` | position types, blips, runtime menus (locker, stash, cabinet, garage, elevator), beds, store-vehicle prompt, radial items |
| `client/modules/hospital_builder.lua` | site survey mode (ghost prop / vehicle, survey pin, floor brackets, raycast, controls) |
| `client/modules/hospital_manager.lua` | opens the manager, relays its actions, placement round-trip, go to, outfit capture / try-on |
| `html/apps/manager/` | Department Console window + compact menus |
| `html/apps/builder/` | site survey HUD |
| `config/modules/hospital.lua` | `Config.Hospital` |
| `locales/en/hospital.lua` | `hospital.*` strings (also every NUI string) |

## Features

### Department Console (`manager` app, v5 window)
Originality: this window must not look like a folder explorer (see `docs/design/ORIGINAL.md`).
It is built from the NAYZEEE language: corner brackets, status rings, instrument lists, a
spine, rolling counters and an edge dock.
- **Title bar readouts**: Departments / Sites / On shift (ring) as mono readouts. For admins
  they are also the way into the whole-server views (overview cards, every site, on shift now).
- **Department rail** (sidebar): "On file" kicker with a rolling department count, search with
  two inline filter toggles (job-linked only / own roster only), one **unit card** per
  department (status ring in the blip colour = share of staff on shift, three-letter code, job
  link, on-shift / staff), a dashed "Register department" card, and a **Live now** card
  (on-shift faces, opens "On shift now"). Command desk users see their own card instead.
  Unsaved departments get an amber dot.
- **Section dock**: a vertical icon dock between rail and content with count badges and a lit
  edge bar: Profile, Staff, Ranks, Uniforms, Sites, Fleet (command desk: Staff, Ranks,
  Uniforms, Fleet, Account). It switches to Overview / Sites / On shift on server views.
- **Profile**: hero card (big badge ring with code + map-pin sprite, code chip, job link chip,
  simple-care chip, instrument list: staff, on shift, sites, fleet); settings rows in the HUD
  settings style (Name & code, Links: job link, Discord role ID, paying account, **Simple care**
  toggle + per-permission chips); **Base point** card with a radar preview (pin, you, distance,
  sweep), X / Y / Z / facing / distance instrument list, Travel there, Move it; **Map pin**
  (show, 12 colour swatches, icon presets + any id, size slider, pin text, only-when-close).
- **Staff**: people list sorted on shift → online → rank (avatar status ring, status dot,
  identifier, job-link tag, rank select, since, let go), side gauge (on-shift ring + members /
  online / on shift) and the Hire panel (online player or any server id / citizen id, rank).
- **Ranks**: a ladder on a vertical spine, top rank first (level node, title, code, pay, move
  up / down, remove, permission chips with All / None / Same as the rank below). Staff keep
  their place: the server remaps stored grades when ranks move or disappear.
- **Uniforms**: "Save what I wear as a uniform", per uniform a name, male + female fits
  (status ring, component read-out, Save, Try on), rank chips (none = all), "Back to my own clothes".
- **Sites**: **zone board** (Staff base, Dispensary, Front desk, Blood service, Theatre, Cath lab,
  Imaging, Sonography, Wards, Lifts, Mortuary, Other — ring = share of the zone's site types
  that are set, site count), site list for the zone sorted nearest first (type filter chips
  inside a zone, coordinates, proximity ring + distance, data chips, Travel, Move, settings
  editor for label + every data field, Remove) and the **Set a new site** palette for **every
  registered point type** of the zone (read from `NZA.Points.Types()` at runtime, so other
  modules' types appear automatically) → site survey mode.
- **Fleet**: vehicle rows (name, model, Road / Air, from rank, livery, extras) and the bays
  (vehicle bay / helipad sites).
- **Account** (command desk): rolling balance, one pay round + rounds covered, pay in / take
  out (cash or bank, quick amounts), pay by rank.
- **Register a department** modal: live card preview (badge, code, name) + name / code rows
  (code auto-filled from the name). Remove / let go / drop-changes confirmations, Ctrl+S save,
  ESC asks before throwing away unsaved edits.
- Compact windows: uniform locker, staff store (two columns, move-per-click stepper + whole
  stack toggle — no 1/5/10/All row), supply cabinet (left-this-shift ring, stepper), vehicle
  bay / helipad, lift (stops on a spine, highest first).

### Site survey mode (`builder` app + `hospital_builder.lua`)
- Ray from the screen centre onto floors and furniture. The centre shows a bracket reticle
  (four corners + diamond) with a range chip under it.
- In the world (all kinds): floor corner brackets around the footprint (model bounds) and a
  facing arrow, a small centre cross. Marker kinds add the **survey pin**: a bobbing inverted
  cone over a dashed plumb line, a thin floor ring and a soft light pool. Teal when the spot is
  clear, red when it is not (`Config.Hospital.builder.markerColour / badColour`). No sphere,
  no beam. Prop types: translucent ghost resting on the surface, outline teal / red where the
  game supports it. Bays / helipads: ghost of the department's first car / helicopter
  (`Config.Hospital.garage.carModel / heliModel` when it has none). The ghost never collides.
  Types with `parts` in their def (the angio suite: monitor, injector tray, red button) show
  each part as an extra ghost at its type-space offset, turned with the main ghost.
- Keys: E set here, Backspace / Q / X / ESC back out (the pad shows ⌫), ← → turn (hold), wheel nudges, Shift
  coarse, Alt fine, Page Up / Down lift, G lock to the snap angle. Max distance check, invalid
  spots refuse E (state note shakes).
- HUD (left column, vertically centred; nothing bottom-centre or on the right edge): survey
  card with a corner bracket, type status ring (ring = share of the reach used), title,
  department + new / moving, a **bearing compass** (the rose turns, pointer fixed, rolling
  read-out, snap ticks light up when locked), instrument list (lift, range with bar, lock,
  grid), state note; under it a control pad whose tiles light up while their key is held
  (Lua sends `keys = { fast, fine, turn, wheel, lift }` with every state).
- Moving a site starts from the old spot. After setting, the console reopens where you left it.

### Runtime sites
| Type | Who | What |
|---|---|---|
| `duty` | members | Go on / off duty (framework duty through `Bridge.SetDuty` for framework medics, own duty for standalone members) |
| `locker` | members | outfits of your grade that fit your character, civilian clothes back (`Bridge.Clothing`) |
| `stash` | on-duty members, `minGrade` | `Bridge.Inv.OpenStash` first (ox, qb 1.x/2.x, ps, lj, qs); if it fails: ox_inventory / qb-inventory 2.x / classic `inventory:server:OpenInventory` (qb-inventory 1.x, lj, qs; not ps, which renamed it), else the built-in storage window (stacks, metadata items kept per unit) |
| `boss` | grades with `manage` | the manager limited to the department |
| `storage` | on-duty members | supply cabinet, items from `Config.Hospital.storage.items` with per-shift limits and optional perm (the default list also stocks the procedure kits: empty blood bag, trauma, intubation, chest drain, angio kit / contrast / coil, surgical and graft kits) |
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

Record fields: `hospital dept deptLabel grade gradeLabel gradeName salary perms easy easyDefault
onDuty medic police job jobLabel isBoss linked frameworkMedic` (+ `excluded` for fired linked members).
`easy` = the department switch, then per-permission overrides. `easyDefault` (read by
`NZA.Staff.Easy` / `NZA.Easy` for anything not in `easy`: a permission outside `NZA.Const.Perms`
or no permission) is the department switch (`dept.easy == true`), the same fallback `easy` uses for a
permission without an override, so `Config.EasyMode.default` never overrides a department. Duty: framework medics follow
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
- Stash support for inventories other than ox / qb / qs / ps / lj is the built-in storage window.
- Outfits are native component / prop snapshots of the freemode characters.
- Elevator teleports move only you.
