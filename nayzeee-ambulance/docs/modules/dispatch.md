# Module: dispatch

Calls, the call card, the pager, unit statuses, the dispatch board, player 911,
phone pairing and the EMS radial job menu.

## Files

| File | What it does |
|---|---|
| `server/modules/dispatch.lua` | `NZA.Dispatch` API (§9): calls, units, status chain, automatic status pass, alerts (card / pager / phone / police / external), board data, bus listeners |
| `server/modules/dispatch_log.lua` | `nza_calls` table and `NZA.DispatchLog` |
| `server/modules/dispatch_net.lua` | net events from clients, callbacks, `/911`, `/callsign`, the pager item |
| `client/modules/dispatch.lua` | client call store, call card (`callcard`), "your call" strip, blips, GPS, status toasts, police notices, keybinds, client `NZA.Dispatch` API |
| `client/modules/dispatch_pager.lua` | the pager device (`pager`), popup on calls, focus mode, history, phone pairing, mute |
| `client/modules/dispatch_board.lua` | the dispatch board window (`dispatch`) |
| `client/modules/dispatch_radial.lua` | the EMS radial job menu (`radial`) and `NZA.RadialItems` |
| `config/modules/dispatch.lua` | `Config.Dispatch` |
| `locales/en/dispatch.lua` | `dispatch.*` strings (also sent to the four apps) |
| `html/apps/callcard/` | call card + strip; also defines `window.NZD` (helpers shared by the four apps) |
| `html/apps/pager/` | pager device with LCD |
| `html/apps/dispatch/` | board window |
| `html/apps/radial/` | radial menu (UI pack "Orbit" wheel) |

## Features

### Calls and the status chain

Every call has the chain `DSP > ENR > SCN > CARE > TRN > HSP`. Each unit on a call has its
own stage, and the call shows the furthest one. The server moves units along by itself,
using server-side positions every `Config.Dispatch.status.tick` ms. The pass only does work
while calls are open.

| Stage | Reached when |
|---|---|
| DSP | the call is created, or the last unit leaves before reaching the scene (the call is paged again) |
| ENR | the unit responds (card E, pager ACK, radial Respond, board), or dispatch assigns it. GPS route and blip route are set. The downed patient gets `nza:wounded:help { eta, unit, status = 'enroute' }`, and the ETA is refreshed every `etaUpdate` s |
| SCN | the unit is within `sceneRadius` of the call. Toast: "You have arrived at the scene". The patient gets `status = 'onscene'` |
| CARE | the first `treat:done` or `proc:done` on a call patient. A medic who treats a call patient without responding joins the call (`autoAttach`) |
| TRN | bus `transport:loaded (src, p, vehNet, strNet)` from the transport module. The fallback: the patient is in a vehicle, ambulance bay or on a stretcher, `transportDistance` m from the scene, or in the same vehicle as the unit. GPS goes to the nearest hospital |
| HSP | the unit is within `hospitalRadius` of a hospital, or bus `transport:bed` / `patient.meta.bed` (patient placed on a hospital point). The call closes `closeAfterHospital` s later |

Other behaviour:
- **Merging:** a new call for a patient who already has an open call updates that call (higher
  priority, new message, "Called again" in the timeline) instead of paging twice.
- **Arrest upgrade:** a call patient going into cardiac arrest raises the call to P1.
- **Auto close:**
  - calls with no units close after `unassignedTimeout`;
  - calls with units close when nothing has changed for `staleTimeout`;
  - calls close when every patient recovered (`closeWhenRecovered`) or the NPC patients are gone;
  - the oldest unassigned call closes once more than `maxActive` calls are open.
- **Leaving a call:** the last unit to clear a call that was reached closes it ("cleared"). If it
  was never reached, it goes back to DSP and is paged again (`realertOnDrop`).
- **Unit statuses:** `10-8` available, `10-7` out of service (no call cards unless
  `outOfServiceAlerts`), and while on a call `ENR SCN CARE TRN HSP`.
- **Callsigns:** `Unit %02d` (server id) by default. `/callsign 4-ADAM` stores one per character
  (resource KVP). A `callsign` field in the hospital staff record is used when present.
- **Street names:** the first medic client works out the street and zone and reports them back
  once.

### Call card (`callcard`, top right, no focus)
- Shows the priority dot and word (P1 CRITICAL red, P2 URGENT amber, P3 ROUTINE teal), the
  10-code chip, the call id and a live elapsed timer.
- Shows a type icon, the title, and the zone · street.
- Shows the caller line: name, phone number, and their message in quotes.
- Voiced calls play `call.voice` (`audio/...` under `html/`) with an animated waveform.
- Shows chips for patients, injury types, units already on the call, and NPC.
- Shows the distance and a compass direction (`SW`) with an arrow relative to the camera. Both
  update live at 5 Hz. The ETA is shown too.
- `E` responds and `X` dismisses (declines). Both are game keybinds and need no NUI focus. Players
  can rebind them in the FiveM key bindings.
- Several calls queue up: stacked ghost cards and "+2 more calls · X next". P1 calls jump the
  queue.
- An alert tone per priority (3, 2 or 1 bursts), a red pulse on P1, and a bar that counts down
  the auto-dismiss time.
- "Your call" strip: while you are on a call (and the pager is not showing it), a compact strip
  shows the call, a live distance and arrow, and the status chain with the current stage lit.
- Police get the same card as an "EMS NOTICE" for violent calls (`Config.Dispatch.police`):
  `E` sets the GPS and `X` dismisses. They also get a flashing blip for `blipTime`.

### Pager (`pager`, bottom right)
- Needs `Config.Items.pager` unless `requireItem = false`. It pops up without focus when a call
  comes in: beep pattern (`NZA.audio.pager`), red blinking LED, LCD flash and a vibration shake.
  It stays on screen while you are on a call (`showWhileOnCall`).
- The pager key (`F7`), `/pager` or using the item takes it in your hand. This gives focus with
  the cursor and keeps game input, so you can still walk. Phone and arrow controls are blocked.
- LCD: signal, the phone-paired and mute icons, callsign, game clock and battery.
- CALL screen:
  - `P2 OVERDOSE  1/3`, then the street;
  - `310M SW   ETA 0:19`;
  - a progress bar: the time left to acknowledge, or the route progress once en route;
  - the chain `DSP>ENR>SCN>CARE>TRN>HSP`. Done stages are solid, the current one is inverted and
    blinking, and future ones are dotted.
- Soft keys: `BACK DECL` / `Y ACK`. On your own call they become `BACK CLR` / `Y GPS`.
- Hardware buttons: ◀ opens the menu or goes back, ▲ ▼ scroll calls and the menu. Keyboard:
  arrows, `Y`/Enter, Backspace, ESC or the pager key to put it away. Mouse clicks work on every
  button.
- MENU: calls, pair phone, mute, NPC calls, status 10-8 / 10-7, history, clear call.
- HISTORY lists the last `history` pages, each marked open or closed. IDLE shows a large clock,
  "NO ACTIVE CALLS" and your status.
- Phone pairing: PAIR sends every call to `Bridge.Phone.Notify`, and to `Bridge.Phone.Mail` when
  `phoneMail` is on. The pairing is kept per character.

### Dispatch board (`dispatch`, UI v5 window)
- The sidebar shows who you are (name, callsign, grade). Below that:
  - a status chip;
  - a 10-8 / 10-7 segmented control, locked while on a call;
  - an NPC calls toggle;
  - the nav, with counts.
- Overview: city clock and four stat tiles (open calls with the P1 count, free units, average
  response today, hospital queue with incoming). Below them, the active calls as incident cards
  (status chain, units with stages, unassigned warning, patients, declines) and the units list.
- Active calls: a list and a detail pane.
  - Detail header: priority, code, id and live age, plus the P1/P2/P3 control (dispatchers).
  - Title, location and distance, then the large status chain.
  - Actions: Respond (R), Clear, Set GPS (G), Assign unit (popover), Close call (confirm modal).
  - Body: caller box, patients with triage and state, units on the call (take off), timeline.
- Units: a table with callsign, name, grade, status, call link and distance (with an "in vehicle"
  icon). Each row has a GPS button, and dispatchers get "Send to C-xxxx" for the selected or first
  unassigned call.
- Unit map: a canvas map of San Andreas in world coordinates (stylised coastline, Alamo Sea,
  district labels, 1 km grid).
  - Shows hospitals, calls (pulsing, colour by priority, labels), units (heading arrows coloured
    by status, callsigns, dashed lines to their call) and you.
  - Wheel zooms at the cursor and dragging pans. There are zoom and fit buttons, a scale bar and
    a north arrow.
  - Hovering shows a tooltip and clicking a call selects it. A side panel holds Respond / GPS.
- Call log: the newest `nza_calls` rows. Filter by P1/P2/P3 and search the id, title, street,
  zone, caller or units. Columns: time, call, priority, location, units, response time, duration,
  final chain and reason. Without a database the log shows this session's calls.
- Hospital queue: `NZA.Checkin.Queue()` tickets (ticket, name, priority, waiting time, status),
  and ambulances transporting, with their hospital and ETA.
- Refreshes every `board.refresh` ms. Scroll positions and the selected call are kept. Keys: ↑↓
  select a call, R, G, M (map), ESC.

### EMS radial job menu (`radial`, F6)
- Based on the NAYZEEE UI pack Orbit wheel: segments with teal hover, a glowing halo arc, ticks,
  and a rotating dashed ring. It is drawn without backdrop-filter and scaled with a transform, so
  mouse angles stay exact.
- The centre shows your name and status (dot + `10-8 Available`). In a submenu it shows the
  submenu title. The hovered item's description shows underneath.
- Root: Dispatch, Patient, Go on/off duty, Stretcher, plus every root item other modules add.
  - Patient and Stretcher list the items of the assess and transport modules (`parent = 'patient'`
    / `'stretcher'`). They are greyed out with a reason when empty.
  - Dispatch needs duty.
- Dispatch submenu: Call log, Hospital queue, Unit map, NPC calls, Respond, Clear call, Out of
  service / Back in service, Pager, Back.
  - NPC calls and the service toggle stay open and highlight in solid teal when on.
  - Back sits at the bottom.
- Input: mouse hover/click, RMB or Backspace for back, 1-9 quick pick, ←/→ + Enter, ESC or the
  menu key to close. Disabled items shake.
- Go on/off duty uses `NZA.Hospitals.ToggleDuty` when the medic belongs to a department. That
  respects department membership and duty points. Otherwise it uses
  `nza:dispatch:duty → Bridge.SetDuty`. The hospital module's own `hospital_duty` root entry is
  hidden so the duty item is not shown twice.

### Player 911
`/911 <message>` (`Config.Dispatch.player911.command`) goes through `Bridge.CallEMS`. That
applies the cooldown, takes server-side coordinates, adds the caller's name and phone number,
and lists the caller as a patient when downed. The caller gets a toast with the ETA when a unit
responds. Phones and other scripts use `exports['nayzeee-ambulance']:CallEMS(src, message, coords?)`,
which is registered by the bridge and ends in `NZA.Dispatch.Create`. Every call is also mirrored
with `Bridge.Dispatch.External` (when `Config.Dispatch.external` and
`Config.Bridge.externalDispatch` are on). Violent calls go to on-duty police.

### Blips
Each call gets a blip. The sprite is chosen by type and the colour by priority
(`Config.Dispatch.blips`). New P1 blips flash. The call you respond to gets the GPS route; while
transporting, a hospital blip with its own route is used instead. All blips are removed on close,
when going off duty, and on resource stop.

## Config (`Config.Dispatch`)

| Section | Keys |
|---|---|
| `calls` | `idPrefix maxActive unassignedTimeout staleTimeout closeAfterHospital maxUnits autoAttach realertOnDrop upgradeOnArrest closeWhenRecovered mergeDuplicates defaultCode defaultType` |
| `status` | `auto sceneRadius hospitalRadius transportDistance tick etaSpeed etaUpdate fallbackHospitals` (used only while no hospital is built) |
| `units` | `callsignFormat callsignCommand callsignMax outOfServiceAlerts showOffDutyInRoster` |
| `card` | `enabled respondKey dismissKey timeout queue sound voice voiceVolume activeStrip hideWhenDown minPriority` |
| `pager` | `enabled requireItem key command popup popupTime showWhileOnCall beep phonePairing phoneMail history` |
| `board` | `enabled command key assignPerm refresh logLimit` |
| `radial` | `enabled key command dutyToggle dutyPointDistance` |
| `player911` | `enabled command minLength maxLength` |
| `npcCalls` | `defaultOn` |
| `blips` | `enabled scale flash route routeColour shortRange sprites{type} colours{priority}` |
| `police` | `enabled types all blipTime` |
| `external` | bool |
| `log` | `enabled keepDays` |

## Server API

```lua
NZA.Dispatch.Create(call) → callId | nil, err
  -- call = { code, priority 1..3, title, type, coords, street?, zone?, caller?, callerSrc?, phone?, message?,
  --          voice? ('audio/...' under html/), patients = { pid | Patient | target }, npc, source = 'player'|'npc'|'system',
  --          blip = { sprite, colour }, meta = {} }
NZA.Dispatch.Update(callId, patch) → bool      -- code priority title type coords street zone caller message voice blip npc meta(merge) patients(add)
NZA.Dispatch.Close(callId, reason) → bool
NZA.Dispatch.Get(callId) → call | nil          -- live table, read only
NZA.Dispatch.SetStatus(callId, src, status, { forward?, force? }) → ok, err   -- 'DSP' (removes the unit) | ENR | SCN | CARE | TRN | HSP
NZA.Dispatch.Respond(src, callId)  Clear(src, callId?, reason)  Assign(callId, target, by)  Decline(src, callId)
NZA.Dispatch.Advance(callId, src, stage)       -- forward only
NZA.Dispatch.Active()  CallOf(src)  CallForPatient(p)  CallPatients(call)  Recent()
NZA.Dispatch.Unit(src)  Units(withCoords)  UnitStatus(src)  SetOutOfService(src, bool)  SetCallsign(src, text)
NZA.Dispatch.Paired(src)  SetPaired(src, bool)  NpcCalls(src)  SetNpcCalls(src, bool)
NZA.Dispatch.Hospitals()  NearestHospital(coords) → h, dist   Board(src)  Public(call, full)  Me(src)  Tick()
NZA.DispatchLog.Insert(call)  Close(call)  Recent({ limit, priority, search }) → rows   Ready()
```

Server bus emitted: `dispatch:created (call)`, `dispatch:status (call, src, stage)`,
`dispatch:respond (call, src)`, `dispatch:closed (call, reason)`.
Listened: `treat:done proc:done transport:loaded transport:bed patient:created patient:removed
state:changed staff:changed player:unloaded`.

`Player(src).state.nzaNpcCalls` (replicated, set by the server) is true while the medic wants
NPC calls. The calls module reads it. It is saved per character and defaults to
`npcCalls.defaultOn`.

## Client API

```lua
NZA.Dispatch.Calls()  Get(id)  Me()  Current()  Units()  Recent()  Live(call) → dist, dir, relAngle, eta
NZA.Dispatch.Respond(id?)  Decline(id)  Clear()  SetStatus('10-8'|'10-7')  SetNpcCalls(bool)  Pair(bool)  SetDuty(bool)
NZA.Dispatch.OpenBoard(tab?)  OpenRadial()  TogglePager()  PagerVisible()  HasPager()
```
Client bus: `dispatch:sync (S)`, `dispatch:call (call, flags)`, `dispatch:update (call)`,
`dispatch:close (id, reason)`, `dispatch:me (me)`, `dispatch:stage (id, stage)`.

Radial entries from other modules:
```lua
NZA.RadialItems = NZA.RadialItems or {}
table.insert(NZA.RadialItems, { id, parent = nil | 'dispatch' | 'patient' | 'stretcher' | <id>, label, icon, order, perm,
    desc?, danger?, keepOpen?, active = fn → bool, canShow = fn → bool, onSelect = fn })
```

## Network

| Name | Kind | Payload |
|---|---|---|
| `nza:dispatch:respond / decline / clear / closeCall` | C→S | `callId` |
| `nza:dispatch:assign / unassign` | C→S | `callId, targetSrc` (`board.assignPerm`; unassigning yourself is always allowed) |
| `nza:dispatch:priority` | C→S | `callId, 1..3` (`assignPerm`) |
| `nza:dispatch:unitStatus` | C→S | `'10-8' \| '10-7'` |
| `nza:dispatch:pair / npc / duty` | C→S | `bool` |
| `nza:dispatch:street` | C→S | `callId, street, zone` (first report only, medics or the caller) |
| `nza:dispatch:state / me / board / log` | callbacks | sync payload / own unit / board data / `{ rows, db }` |
| `nza:dispatch:sync / call / update / close / me / units / stage / assigned / police / pager` | S→C | see the file headers |
| `nza:wounded:help` | S→C | `{ eta, unit, status }` through `NZA.Wounded.Help` |

Every net handler checks the source and rate-limits. Permissions come from `NZA.Staff`, and
positions are server-side.

NUI callbacks:
- `pager:ack decl clear gps pair mute npc status hide`
- `dispatch:respond assign unassign clear closeCall priority gps status npc refresh log`
- `radial:select`

## Database

```sql
CREATE TABLE IF NOT EXISTS `nza_calls` (
  `id` VARCHAR(16) NOT NULL, `code` VARCHAR(16) DEFAULT NULL, `priority` TINYINT NOT NULL DEFAULT 2,
  `title` VARCHAR(64) DEFAULT NULL, `type` VARCHAR(24) DEFAULT NULL,
  `x` FLOAT NOT NULL DEFAULT 0, `y` FLOAT NOT NULL DEFAULT 0, `z` FLOAT NOT NULL DEFAULT 0,
  `street` VARCHAR(80) DEFAULT NULL, `zone` VARCHAR(64) DEFAULT NULL, `caller` VARCHAR(64) DEFAULT NULL,
  `message` VARCHAR(255) DEFAULT NULL, `source` VARCHAR(12) DEFAULT NULL, `npc` TINYINT(1) NOT NULL DEFAULT 0,
  `status` VARCHAR(8) NOT NULL DEFAULT 'DSP', `units` LONGTEXT DEFAULT NULL, `reason` VARCHAR(32) DEFAULT NULL,
  `created` INT UNSIGNED NOT NULL, `responded` INT UNSIGNED DEFAULT NULL, `arrived` INT UNSIGNED DEFAULT NULL,
  `closed` INT UNSIGNED DEFAULT NULL,
  PRIMARY KEY (`id`), KEY `created` (`created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```
Call ids continue across restarts (resource KVP `nza_dispatch_seq`). On start, rows left open
are closed with reason `restart`, and rows older than `log.keepDays` are deleted.

## Testing

- `luac5.4 -p` passes on all 9 Lua files, and `node --check` on all 4 JS files.
- A mock FiveM runtime ran the real server files. It covered: create, merge a duplicate,
  respond, the help push, auto-attach, the transport bus, the board, HSP auto close, clear back
  to DSP, out of service, off duty, the arrest upgrade, closing on recovery, every automatic
  status-pass step, and expiry.
- A client mock covered: sync, card alert, the respond key, the active strip, stage toasts,
  close, the radial tree and toggles, the pager and police notices.
- The browser previews were checked with no console errors:
  - `callcard`: queue, voice, responded, police;
  - `pager`: call, menu, history, idle, passive;
  - `dispatch`: every tab;
  - `radial`: root, and the submenu with an active toggle.
- Screenshots were taken at 1920×1080 and 1280×720.

## Known limits

- The unit map is a stylised outline of San Andreas, not the GTA map texture: no image may
  ship from outside the resource.
- Hospital arrival uses `NZA.Hospitals.Nearest` (department HQ or any point). The fallback list
  is used only while no hospital is built.
- The transport fallback (no `transport:loaded` event) needs the patient's ped. NPC patients
  whose ped is not networked to the server rely on the transport event.
- Blip sprite ids are GTA defaults and can be changed in the config.
- The board's hospital queue needs the check-in module to provide `NZA.Checkin.Queue()`. Without
  it, the tab shows "No check-in queue" and the incoming ambulances only.
