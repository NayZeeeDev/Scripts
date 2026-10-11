# 🚔 NAYZEEE MDT & Dispatch

A complete Mobile Data Terminal and dispatch system for **ESX Legacy**, built as a **police tablet**: lock screen, home screen, app windows and a taskbar, in the NAYZEEE terminal style. Live call board with an in-UI map, granular per-rank permissions, ALPR, chain-of-custody evidence, a server-authoritative penal code, and a compact in-game dispatch widget.

**v2.0.0** — new tablet UI, quick actions, backup requests, a sentence calculator, notepad, 10-codes, per-officer settings, live unit blips, and a full bug-fix and performance pass. **0.00 ms resmon at idle**. See [Performance](#-performance).

---

## 📦 Dependencies

| Resource | Required | Notes |
| --- | --- | --- |
| `es_extended` | ✅ Yes | ESX Legacy 1.9+ |
| `oxmysql` | ✅ Yes | Database layer |
| `ox_lib` | ✅ Yes | Callbacks, notifications, TextUI |
| `ox_target` | ⬜ Optional | For terminal interaction points |
| `screenshot-basic` | ⬜ Optional | Required only for in-game photo capture |

---

## 🛠 Installation

1. Drop `nayzeee-mdt` into your `resources` folder.
2. Import `sql/nayzeee-mdt.sql` into your database. It creates 20 tables, all `IF NOT EXISTS` — safe to re-run.
3. Add to `server.cfg`, **after** `es_extended`:

```cfg
ensure ox_lib
ensure oxmysql
ensure es_extended
ensure nayzeee-mdt
```

4. Open `config.lua` and match `Config.Departments` keys to your ESX job names.
5. Match `Config.Ranks` keys to your `job_grades.name` values.
6. Restart the server.

{% hint style="warning" %}
Step 4 and 5 are not optional. If the job name or grade name does not match, the MDT will tell the officer they are not on a department roster.
{% endhint %}

---

## ⚙️ Core Settings

| Setting | Default | Description |
| --- | --- | --- |
| `Config.OpenCommand` | `'mdt'` | Chat command that opens the terminal |
| `Config.OpenKey` | `'F6'` | Default keybind (players can rebind) |
| `Config.PanicCommand` | `'panic'` | Panic button command |
| `Config.PanicKey` | `false` | Panic button keybind (e.g. `'F9'`), `false` for none |
| `Config.DispatchKey` | `'F10'` | Toggles the compact dispatch widget |
| `Config.Currency` | `'$'` | Symbol shown on fines |
| `Config.Access.anywhere` | `true` | Allow opening away from a terminal |
| `Config.Access.inVehicleOnly` | `false` | Force the MDT to be used from a unit |
| `Config.Duty.requireForMDT` | `false` | Require clocking on before opening |

---

## 📱 The Tablet

The MDT comes out as a tablet in the officer's hand. It boots to a lock screen, then a home screen with a clock, the officer card, quick actions, every app they are allowed to use, and a live feed of calls, units and recent reports. Apps open in windows; minimise one and it sits on the taskbar.

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Tablet.prop` | `true` | Hold a tablet prop with an idle animation |
| `Config.Tablet.model` | `prop_cs_tablet` | Prop model |
| `Config.Tablet.dict` / `anim` | bus passenger tablet idle | Animation |
| `Config.Tablet.bone` / `offset` / `rotation` | left hand | Where the prop sits |
| `Config.Tablet.propInVehicle` | `false` | Skip the prop while seated in a vehicle |
| `Config.Tablet.lockScreen` | `'first'` | `'first'` (once per session), `'always'`, `'never'` |
| `Config.Tablet.blockWhenDown` | `true` | Can't open while dead, cuffed or ragdolling |
| `Config.Tablet.wallpaper` | `'nayzeee'` | Wallpaper officers start with |
| `Config.Tablet.wallpapers` | 3 | Choices in Settings — a path in `web/` or a full https link |

### Apps

| Group | Apps |
| --- | --- |
| Active operations | Dashboard, Dispatch, BOLOs, Warrants |
| Records | Incidents, Penal Code, Evidence |
| Registry | Citizens, Vehicles, Weapons, Properties |
| Department | Roster, Cameras, Bulletins, Audit Log |
| Tools | 10-Codes, Notepad, Settings |

An app only shows if the officer's rank has its `view.*` permission. Badges on the icons count open calls, live BOLOs and active warrants.

### Quick actions

| Action | What it does |
| --- | --- |
| **Panic** | Same as `/panic` — blip that follows the officer for everyone on duty |
| **Backup** | Pick an urgency, add a note; creates a call at your position for your department |
| **Run plate** | Looks up the closest vehicle's plate |
| **New call** | Opens the create call form, pinned to where you stand |
| **Report** | Starts a new incident report |
| **Notes** | Opens the notepad |

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Backup.enabled` | `true` | Show the Backup quick action |
| `Config.Backup.requirePerm` | `false` | `true` needs `dispatch.create`, `false` lets anyone on the roster ask |
| `Config.Backup.cooldown` | `20` | Seconds between requests per officer |

### Per-officer settings

Saved on the player's own client (KVP), so they never touch the database: wallpaper, UI size, lock animation, boot console, notifications, alert sounds, and whether the dispatch card pops up by itself. The **Notepad** is stored the same way — up to 40 notes, autosaved.

### More features

- **Sentence calculator** in the Penal Code app — add charges and counts, see total fine and time, then turn it straight into a report.
- **10-Codes** reference, from `Config.TenCodes`.
- **Spotlight search** (`/`) across apps, citizens, plates, reports and evidence.
- **Status popover** on the taskbar — change unit status or clock in/out without opening an app.
- **Distance** to each call on the board and on the dispatch card.
- **Session resume** — close the tablet and reopen it, and your windows are where you left them.
- **Browser preview** — open `web/index.html` in a browser and it runs on sample data (`?lock=0&boot=0&app=dispatch&widget=1`), so you can restyle it without a server.

---

## 🏢 Departments

Each key is an **ESX job name**.

```lua
Config.Departments = {
    police = {
        label = 'Los Santos Police Department',
        short = 'LSPD',
        sub   = 'Mobile Data Terminal',
        blipColour = 38,
        callsignPrefix = 'L'
    }
}
```

| Field | Description |
| --- | --- |
| `label` | Full name, shown on the officer card |
| `short` | Shown in the title bar |
| `sub` | Subtitle under the department short name |
| `blipColour` | Colour of this department's unit blips on the game map |
| `callsignPrefix` | Suggested prefix when an officer sets a callsign |

---

## 🔐 Permissions

Permissions are granted **per grade**, keyed by the grade name from `job_grades`.

```lua
Config.Ranks = {
    police = {
        recruit = { 'view.dispatch', 'view.citizen', 'view.vehicle' },
        officer = { 'view.*', 'dispatch.assign', 'incident.create', 'bolo.create' },
        chief   = { '*' }
    },
    default = { 'view.dispatch', 'view.citizen' }
}
```

| Value | Meaning |
| --- | --- |
| `'*'` | Grants every permission |
| `'view.*'` | Wildcards work for any group — grants every `view.` permission |
| `Config.Ranks[job].default` | Fallback for grades not listed |
| `Config.Ranks.default` | Fallback for jobs not listed |

Grades can be keyed by **name** or by **number**, whichever matches your setup. Numbers win if both are present:

```lua
Config.Ranks = {
    police = {
        [0] = { 'view.dispatch', 'view.citizen' },   -- by grade number
        sergeant = { 'view.*', 'incident.close' },   -- by grade name
        [5] = { '*' }
    }
}
```

Permission groups: `view.*`, `dispatch.*`, `bolo.*`, `warrant.*`, `incident.*`, `evidence.*`, `citizen.*`, `vehicle.*`, `weapon.*`, `property.*`, `officer.*`, `announcement.*`, `photo.*`, `link.*`, `camera.*`.

{% hint style="info" %}
Anything the officer's rank does not allow is hidden from the sidebar entirely, and re-checked server side on every write. The UI is a convenience, not the security boundary.
{% endhint %}

---

## 📻 Dispatch

24 call types are configured out of the box, each with a group, priority, ten-code, blip and colour.

```lua
{ id = 'store_robbery', label = 'Store Robbery', group = 'police',
  priority = 1, code = '10-90', icon = 'cash', blip = 500, colour = 1 }
```

| Priority | Meaning | Behaviour |
| --- | --- | --- |
| `1` | Critical | Red spine, flashing blip, panic-style alert tone |
| `2` | Priority | Amber spine, standard blip |
| `3` | Routine | Teal spine, standard blip |

Calls route to departments by the call `group`, so an ambulance call never lands on a police board.

---

## 🔗 Hooking Your Existing Scripts

Fire an alert from any other resource:

```lua
exports['nayzeee-mdt']:alert({
    type   = 'store_robbery',
    title  = 'Robbery in progress',
    street = 'Rockford Hills',
    detail = 'Two suspects, one armed',
    coords = GetEntityCoords(ped),
    plate  = 'ABC 123'
})
```

Drop-in replacement for wasabi dispatch — the legacy signature works unchanged:

```lua
exports['nayzeee-mdt']:CustomAlert(coords, 'Store Robbery', 'police', 500, 1)
```

Other exports:

| Export | Purpose |
| --- | --- |
| `alert(data)` | Create a dispatch call |
| `CustomAlert(...)` | wasabi-compatible alert |
| `closeCall(id)` | Close a call from another script |
| `activeCalls()` | Table of everything on the board |
| `premade(name, data)` | Fire a premade dispatch (see below) |
| `isOnDuty(src)` | Is this player clocked on |
| `getOfficer(src)` | `{ identifier, name, department, rank, callsign, onDuty, status }` or `nil` |
| `onDutyCount(job?)` | Officers on duty, optionally for one department |
| `link(...)` / `linksFor(...)` | Record links (see below) |
| `cameras()` | Every placed camera |

`CustomAlert`'s third argument can be a job name, a dispatch group or a call type, and the fifth sets the priority.

Client exports:

| Export | Purpose |
| --- | --- |
| `openMDT(app?)` | Open the tablet, optionally straight into an app (`'dispatch'`, `'citizens'`…) |
| `closeMDT()` | Put it away |
| `isOpen()` | Is the tablet out |
| `isOnDuty()` | Is the local player clocked on |
| `panic()` | Press the panic button |

---

## 💰 Fines & Sentences

When a supervisor closes a report, the totals are handed off:

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Incident.autoFine` | `true` | Total the fine from the attached charges |
| `Config.Incident.autoJail` | `true` | Total the sentence from the attached charges |
| `Config.Incident.billOnClose` | `false` | Bill the fine when the report closes |
| `Config.Incident.billMode` | `esx_billing` | `esx_billing` (unpaid bill to `society_<job>`), `bank` (taken from bank, citizen must be online), `export` |
| `Config.Incident.billExport` | `nayzeee-banking` | Resource and method used by `billMode = 'export'` |
| `Config.Incident.jailOnClose` | `false` | Send the primary citizen to jail |
| `Config.Incident.jailEvent` | `esx_jail:sendToJail` | Event fired with the sentence |

{% hint style="danger" %}
Charges are always resolved from `Config.Charges` on the server. The client only sends charge IDs and counts — it can never dictate a fine amount.
{% endhint %}

---

## 📸 ALPR

| Setting | Default | Description |
| --- | --- | --- |
| `Config.ALPR.enabled` | `true` | Master switch |
| `Config.ALPR.scanRadius` | `25.0` | Metres |
| `Config.ALPR.scanSeconds` | `3` | Seconds between sweeps |
| `Config.ALPR.cooldown` | `45` | Seconds before re-alerting on the same plate |
| `Config.ALPR.onlyOnDuty` | `true` | Only scan while clocked on |
| `Config.ALPR.onlyInVehicle` | `true` | Only scan from inside a vehicle |
| `Config.ALPR.checkBolo` | `true` | Cross-check live BOLOs |
| `Config.ALPR.checkStolen` | `true` | Cross-check the stolen flag |
| `Config.ALPR.checkWarrants` | `true` | Cross-check the owner's warrants |

Registration and insurance state are always checked when a registry entry exists. Each sweep sends every nearby plate in **one** request (up to 15), so a busy street costs one round trip, not one per car.

---

## 🗺 Live Map

The dispatch board draws call pins and unit positions over a real map of the island. Three map images plus a plain grid ship with the resource, and officers switch between them from the board itself — the choice is remembered per player.

| Style | Looks like |
| --- | --- |
| `atlas` | The printed paper map — pale green land, tan beaches, blue surf |
| `midnight` | Black landmass with white roads and a pale glow (default) |
| `satellite` | Aerial imagery |
| `grid` | No art, just the teal grid — the lightest option |

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Map.enabled` | `true` | Master switch |
| `Config.Map.style` | `midnight` | Which style the board opens with |
| `Config.Map.allowStyleSwitch` | `true` | Let officers change it themselves |
| `Config.Map.updateSeconds` | `4` | How often unit positions are pushed |
| `Config.Map.showOffDuty` | `false` | Draw officers who are clocked off |
| `Config.Map.unitBlips` | `true` | Show other on-duty units as blips on the **game** map, tablet open or not |
| `Config.Map.blipSeconds` | `6` | How often those unit blips move |

Drag to pan, scroll to zoom up to 6×, or use the buttons top right. Click a pin to open the call. Your zoom and position are kept when units move.

### Calibration

All three images are framed identically and calibrated against these bounds, so pins land in the same spot whichever style is on:

```lua
Config.Map.bounds = { minX = -6235.0, maxX = 6435.0, minY = -4510.0, maxY = 8810.0 }
```

{% hint style="info" %}
If pins sit slightly off for you, adjust the **bounds**, not the images. Widening `minX`/`maxX` pulls pins toward the centre horizontally; widening `minY`/`maxY` pulls them toward the centre vertically.
{% endhint %}

To add your own art, drop a **square PNG or WebP with a transparent background** into `web/img/`, add it to `files{}` in `fxmanifest.lua`, and add an entry to `Config.Map.styles`. Frame the island the way the shipped art does — centred, filling about 83% of the height — and the existing bounds will fit it.

---

## 📟 On-Screen Dispatch Card

What players see without opening the MDT. It shows one call at a time and pages with the keyboard, so nobody has to stop driving to read it. It never takes cursor focus.

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Widget.enabled` | `true` | Master switch |
| `Config.Widget.position` | `top-left` | `top-left`, `top-right`, `bottom-left`, `bottom-right` |
| `Config.Widget.autoShow` | `true` | Pop up on a new call |
| `Config.Widget.autoHide` | `25` | Seconds idle before it fades (`0` keeps it up) |
| `Config.Widget.maxCalls` | `10` | How many calls it pages through |
| `Config.Widget.routeOnAccept` | `true` | Set a waypoint when you respond |

| Key | Default | Action |
| --- | --- | --- |
| Previous | `LEFT` | Back one call |
| Next | `RIGHT` | Forward one call |
| Respond | `U` | Attach yourself and take the route |
| Toggle | `F10` | Show or hide the card |

All four go through `RegisterKeyMapping`, so players rebind them in **Settings → Key Bindings → FiveM**.

A panic button jumps to the front of the queue, and a new call takes the card immediately so it is the first thing on screen.

---

## 📸 Photos

Officers can capture a screenshot from inside the terminal and pin it to any record. The MDT hides itself for the shot, so the photo is of the world, not the UI.

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Photos.enabled` | `false` | Turn on once a host is configured |
| `Config.Photos.host` | `discord` | `discord`, `fivemanage` or `custom` |
| `Config.Photos.maxPer` | `8` | Photos per record |
| `Config.Photos.quality` | `0.85` | JPEG quality |
| `Config.Photos.subjects` | 8 types | Which records accept photos |

Pick one host:

```lua
-- Simplest: a plain Discord webhook, free, no account
Config.Photos.host = 'discord'
Config.Photos.discord.webhook = 'https://discord.com/api/webhooks/...'

-- Or Fivemanage
Config.Photos.host = 'fivemanage'
Config.Photos.fivemanage.apiKey = 'your-key'

-- Or your own endpoint
Config.Photos.host = 'custom'
Config.Photos.custom.url = 'https://your-host/upload'
Config.Photos.custom.field = 'url'
```

{% hint style="info" %}
One photo per record can be marked as the **record picture** — a mugshot on a citizen, a plate shot on a vehicle. It then shows on the record card and on search results. Officers without `screenshot-basic` can still paste an image link instead.
{% endhint %}

---

## 🔗 Record Links

Any record can be tied to any other, and the link reads from both ends — link a plate to a case and the case shows the plate too.

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Links.enabled` | `true` | Master switch |
| `Config.Links.maxPer` | `30` | Links per record |
| `Config.Links.types` | 8 types | citizen, vehicle, weapon, property, incident, evidence, warrant, bolo |

From another resource:

```lua
exports['nayzeee-mdt']:link('vehicle', 'ABC123', 'incident', 'INC-000007', 'Getaway vehicle')
exports['nayzeee-mdt']:linksFor('citizen', 'CZ4K9A2M1P')
```

---

## 📹 Cameras

Officers with `camera.place` can drop CCTV cameras anywhere in the world and watch the feed from the terminal. Cameras can be shot out and need repairing.

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Cameras.placeable` | `true` | Let officers place new cameras |
| `Config.Cameras.spawnDistance` | `40.0` | Metres before the prop spawns |
| `Config.Cameras.maxPerDept` | `40` | Cap on placed cameras |
| `Config.Cameras.destructible` | `true` | Cameras can be shot out |
| `Config.Cameras.models` | 10 props | Available camera models |
| `Config.Cameras.points` | 6 points | Fixed cameras seeded on first start |

**Placing one:** pick a name and model in the MDT, the terminal closes, then left click to drop it, right click to back out. Scroll changes the distance, `Q`/`E` turn it, arrow keys tilt it.

**Watching one:** click a feed. Arrow keys pan and tilt, scroll zooms, `ESC` goes back to the terminal.

{% hint style="warning" %}
A camera only records what the game streams around it. Placing one somewhere nobody ever goes means you will mostly see empty streets.
{% endhint %}

---

## 🚨 Automatic Alerts

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Alerts.shotsFired.enabled` | `true` | Fire a call when a civilian shoots |
| `Config.Alerts.shotsFired.cooldown` | `900` | Seconds before the same player alerts again |
| `Config.Alerts.shotsFired.areaCooldown` | `90` | Seconds before the same block of the map alerts again |
| `Config.Alerts.shotsFired.ignoreJobs` | `true` | Never alert on department members |
| `Config.Alerts.shotsFired.requireWitness` | `true` | Only report when a ped actually heard it |
| `Config.Alerts.shotsFired.ignoredWeapons` | list | Weapons that never report (stun gun, flare gun…) |

Detection is event driven (`CEventGunShot`), not a loop, and only the shooter's own client reports. Silenced weapons never trigger it, on-duty department members are filtered server side, and the reported position is sanity-checked against the player.

---

## 📋 Premade Dispatches

Sixteen ready-made templates, fired with one line from any resource:

```lua
exports['nayzeee-mdt']:premade('store_robbery', {
    street = 'Innocence Blvd',
    coords = GetEntityCoords(ped)
})
```

| Template | Priority | Template | Priority |
| --- | --- | --- | --- |
| `store_robbery` | 1 | `shots_fired` | 1 |
| `bank_robbery` | 1 | `officer_down` | 1 |
| `jewellery` | 1 | `hostage` | 1 |
| `carjacking` | 1 | `house_alarm` | 2 |
| `vehicle_theft` | 2 | `street_race` | 2 |
| `assault_report` | 2 | `drug_deal` | 3 |
| `vandalism` | 3 | `atm_tamper` | 3 |
| `medical` | 1 | `fire` | 1 |

Anything you pass in the second table overrides the template — `title`, `detail`, `priority`, `street`, `plate`, `caller`.

---

## 🎒 Opening With An Item

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Access.item.enabled` | `false` | Require an item to open |
| `Config.Access.item.name` | `mdt_tablet` | Item name |
| `Config.Access.item.consume` | `false` | Use the item up on each open |

Works with `ox_inventory`, `qs-inventory` and plain ESX item counts. With `ox_inventory` the item itself opens the terminal when used.

---

## 🎮 Commands

| Command | Who | Description |
| --- | --- | --- |
| `/mdt` | Officers | Open the terminal |
| `/panic` | Officers | Panic button |
| `/duty` | Officers | Toggle duty |
| `/plate [plate]` | Officers | Look up a plate, or the closest vehicle with no argument |
| `/dispatchwidget` | Officers | Toggle the dispatch card |
| `/mdtadmin duty <id>` | Admin | Force a player off duty |
| `/mdtadmin callsign <id> <sign>` | Admin | Set a callsign |
| `/mdtadmin clear` | Admin | Close every open call |
| `/mdtadmin import` | Admin | Bulk import ESX users as citizens |
| `/mdtadmin perms [id]` | Admin | List a player's resolved permissions |
| `/mdtadmin stats` | Admin | Record counts |

Admin access is `nayzeee.mdt` ace, or the `admin` / `superadmin` ESX group.

---

## ⌨️ Keyboard Shortcuts

| Key | Action |
| --- | --- |
| `ESC` | Steps back: lightbox → search → popover → dialog → minimise the window → put the tablet away |
| `/` | Spotlight search |
| `H` | Home screen |
| `D` | Dispatch |
| `B` | BOLOs |
| `W` | Warrants |
| `I` | Incidents |
| `P` | Penal Code |
| `E` | Evidence |
| `C` | Citizens |
| `V` | Vehicles |
| `R` | Roster |
| `N` | Notepad |

Letter keys do nothing while typing in a field.

---

## 🔍 Troubleshooting

| Issue | Solution |
| --- | --- |
| "You are not on a department roster" | The job name is not a key in `Config.Departments` |
| Officer sees almost nothing in the sidebar | The grade name is not in `Config.Ranks[job]` — check `job_grades.name`, not `label` |
| No vehicles show on a citizen record | Set `Config.Registry.vehiclesTable` to your owned-vehicles table name |
| Plates never match | Set `Config.Registry.trimPlates = true` if your server stores padded plates |
| Blips never appear | `Config.Dispatch.blipDuration` is `0`, or the call had no coords |
| Fines are not charged on close | `Config.Incident.billOnClose` is `false`, or the billing resource is not started |
| Card will not show | It is hidden while the full MDT is open — close the MDT first |
| Card keys do nothing | Another resource has the same binding — rebind in Settings → Key Bindings → FiveM |
| Map art does not load | The file is missing from `files{}` in `fxmanifest.lua` |
| Map pins sit slightly off | Nudge `Config.Map.bounds` — see the calibration note under Live Map |
| Photo button is greyed out | `Config.Photos.enabled` is off, `screenshot-basic` is not running, or no host is configured — hover the button for the reason |
| Photos upload but show as broken | The host returned a link the MDT could not read — check `Config.Photos.custom.field` |
| Camera feed shows empty streets | The game only streams what is near a player; the area has nobody in it |
| Placed camera does not appear | Check the officer has `camera.place` and `Config.Cameras.placeable` is on |
| Shots fired never alerts | The shooter was silenced, was a department member, or the cooldown is still running |
| An officer sees the MDT they should not | Add their job to `Config.IgnoredJobs` |
| Tablet won't open | They are dead, cuffed or ragdolling (`Config.Tablet.blockWhenDown`), or `Config.Duty.requireForMDT` is on and they are clocked off |
| Fonts or icons missing | The UI loads Google Fonts and Font Awesome from cdnjs — the client needs internet access |
| Unit blips never show | `Config.Map.unitBlips` is off, or the officer is clocked off |
| Wallpaper is blank | The `file` in `Config.Tablet.wallpapers` is wrong, or a local file is missing from `files{}` |

---

## 🗄 Database

20 tables, all prefixed `nz_mdt_`:

`officers` · `citizens` · `vehicles` · `weapons` · `properties` · `dispatch` · `dispatch_units` · `bolos` · `warrants` · `incidents` · `incident_people` · `incident_charges` · `evidence` · `evidence_chain` · `notes` · `announcements` · `audit` · `photos` · `links` · `cameras`

Foreign keys cascade, so deleting a report removes its people, charges and evidence chain with it.

---

## ⚡ Performance

The resource idles at **0.00 ms** on both client and server.

- No `Wait(0)` loops while idle. The only per-frame loops run while you are watching a camera feed or placing a camera, and stop the moment you leave.
- Shots fired uses the `CEventGunShot` game event instead of polling the ped.
- Housekeeping (blip expiry, panic expiry, card auto-hide) is one thread ticking every 2 s; the tablet animation check runs once a second, and only while the tablet is out.
- Your position is only sent when you have moved more than 6 m, or every 20 s as a heartbeat.
- ALPR reads plates from the vehicle pool and checks them all in one request per sweep.
- Duty, status and the roster live in server memory, so dashboards and blips don't hit the database. Live updates only go to officers who are on duty or have the tablet open.
- Camera props only spawn near players, and only the ones that changed respawn on an update.

---

## 📊 Logs

| Setting | Description |
| --- | --- |
| `Config.Logs.enabled` | Master switch for Discord webhooks |
| `Config.Logs.webhooks` | Per-category webhook URLs |
| `Config.Audit.enabled` | Write every action to the in-game audit log |
| `Config.Audit.retentionDays` | How long audit rows are kept |

---

**NAYZEEE Development** — v2.0.0
