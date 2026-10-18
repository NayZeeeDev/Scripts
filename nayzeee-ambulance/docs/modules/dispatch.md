# Module: dispatch

Calls, the incoming-call strip, the RX-10 pager, unit statuses, the ops board, player 911,
phone linking and the EMS radial job menu.

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
| `html/apps/callcard/` | incoming-call strip + on-call strip; also defines `window.NZD` (helpers shared by the four apps: stage words, `stageRing`, priority words, formatting) and the global `.nzd-ring` styles |
| `html/apps/pager/` | RX-10 receiver with the OLED glass |
| `html/apps/dispatch/` | ops board window |
| `html/apps/radial/` | radial job menu (orbit of nodes, unit badge centre) |

## Features

### Calls and the status chain

Every call moves through six stages (server codes `DSP ENR SCN CARE TRN HSP`; on screen:
Paged, Rolling, On scene, Treating, Transporting, Handover, drawn as the 6-arc stage ring). Each unit on a call has its
own stage, and the call shows the furthest one. The server moves units along by itself,
using server-side positions every `Config.Dispatch.status.tick` ms. The pass only does work
while calls are open.

| Stage | Reached when |
|---|---|
| DSP | the call is created, or the last unit leaves before reaching the scene (the call is paged again) |
| ENR | the unit takes the call (strip E, pager TAKE, radial Take next call, board), or dispatch assigns it. GPS route and blip route are set. The downed patient gets `nza:wounded:help { eta, unit, status = 'enroute' }`, and the ETA is refreshed every `etaUpdate` s |
| SCN | the unit is within `sceneRadius` of the call. Toast: "On scene. Find your patient." The patient gets `status = 'onscene'` |
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

### Incoming-call strip (`callcard`, top right, no focus)
Our own layout (see `docs/design/ORIGINAL.md`): three columns, corner bracket in the priority
colour, slides in from the right edge.
- **Range scope** (left): a dial with compass ticks and a "camera forward" caret. A blip points
  at the call relative to the camera (live at 5 Hz) with a sweep wedge; the distance and the
  compass word (`SW`) sit in the centre. The outer ring is the **answer window**: it drains over
  `card.timeout` s, with an "Answer in 21s" chip under the dial (red under 8 s). Once you take the
  call the ring fills teal and the chip reads "Route set".
- **Call** (middle): `P1` chip + priority word (P1 Life threat red, P2 Serious amber, P3 Minor
  teal), code · id, type icon tile + title (two lines max), zone and street on a coloured spine,
  then an **instrument list**: drive time, casualties (count + worst triage), crews on it, and
  "Holding" (call age as a rolling counter, `NZA.ui.FlipClock`).
- **Key rail** (right, full height): `E` Take call (teal, light sheen) over `X` Pass. Both are game
  keybinds and need no NUI focus; players can rebind them in the FiveM key bindings.
- Under the columns: the caller (name, phone, quoted message, live-audio waveform while
  `call.voice` plays from `audio/...`) and chips for injury types and "Street call".
- Several calls queue up: a ghost edge under the strip and a chip "2 more in the queue · X skips
  ahead". P1 calls jump the queue. An alert tone per priority (3, 2 or 1 bursts) and a red pulse
  on P1.
- **On call** strip (above it): while you are on a call (and the pager is not showing it) — the
  6-stage ring (`NZD.stageRing`: done arcs teal, current arc white and pulsing, stage icon in the
  centre), "On call · C-0409 · P2", the title, the current stage word → the next one, and a range
  readout (arrow relative to the camera, distance, drive time).
- Police get the same strip as an "EMS notice" in blue for violent calls
  (`Config.Dispatch.police`): `E` Mark map sets the GPS and `X` passes. They also get a flashing
  blip for `blipTime`.
- Stage words on screen (the server keeps the codes): DSP Paged · ENR Rolling · SCN On scene ·
  CARE Treating · TRN Transporting · HSP Handover (`dispatch.unit_*`, short forms `st_*_s`).

### Pager (`pager`, bottom right) — "RX-10" two-way receiver
A generic device (no NAYZEEE name or logo): rubber band around a brushed graphite faceplate
with a chamfered top-right corner, four screws, a belt clip peeking out on top, LED light pipes on
the top edge (PWR, MSG, LNK), a teal OLED glass on the left, a round jog pad (▲ ▼ ◀ ▶ around a lit
select key) and a separate ✕ key on the right, speaker slots, an "IP54 · KEEP DRY" sticker and a
serial plate along the bottom.
- Needs `Config.Items.pager` unless `requireItem = false`. It pops up without focus when a call
  comes in: beep pattern (`NZA.audio.pager`), MSG LED blinking red, a glass flash and a vibration
  shake. MSG is amber while calls wait and teal while you are on a call; LNK is lit while paired.
  It stays on screen while you are on a call (`showWhileOnCall`).
- The pager key (`F7`), `/pager` or using the item takes it in your hand. This gives focus with
  the cursor and keeps game input, so you can still walk. Phone and arrow controls are blocked.
- Glass status row: callsign, the phone-link and silent icons, signal, game clock, battery.
- CALL page: a pixel **ring** on the left (seconds left to take the call; on your own call the
  route progress with the drive time, then the time on the call once on scene), the priority box
  + short type (`P2 OD`, P1 blinks) and `1/3`, the street, the range line (arrow relative to the
  camera, distance, compass word, `DRV 0:34`), and **stage pips** (six cells + the stage word +
  `2/6`). A legend column on the right edge of the glass labels the keys: `● TAKE` / `✕ PASS` /
  `◀ SETUP` (on your own call `● NAV` / `✕ END`).
- Keys: ◀ opens Setup or goes back, ▲ ▼ scroll calls and Setup, ● / ▶ take or open, ✕ pass or go
  back. Keyboard: arrows, `Y`/Enter/→, Backspace, ESC or the pager key to put it away. Mouse
  clicks work on every key.
- SETUP: call list, link phone, silent, street calls, availability (10-8 / 10-7), page log, stand
  down — dotted leaders to the values, page dots in the header.
- PAGE LOG lists the last `history` pages, each marked open or done (lines paged through
  `NZA.Dispatch.Page`, e.g. a new hospital check-in, are marked PAGE). Such a line also shows on
  the glass for 10 s over the call / standby screen (title, text, hospital; Y or ✕ clears it)
  with the beep and the MSG LED. STANDBY shows a large clock,
  your status and "No open calls" beside a status ring.
- Phone linking: LINK PHONE sends every call to `Bridge.Phone.Notify`, and to `Bridge.Phone.Mail`
  when `phoneMail` is on. The link is kept per character.

### Ops board (`dispatch`, UI v5 window)
- The sidebar shows who you are (name, callsign, grade). Below that:
  - a status chip (dot + word);
  - an Available / Unavailable segmented control (10-8 / 10-7), locked while on a call;
  - a Street calls toggle;
  - the nav, with counts: Ops board, Open calls, Crews, Live map · Logbook, ER intake.
- Ops board: city clock and four stat tiles (open calls with the P1 count, free crews, average
  response today, ER intake with inbound crews). Below them the open calls and the crews list.
- Every call card has a left rail with its **stage ring** and P chip, a corner bracket in the
  priority colour, the type, code · id and live age, title, location, then the stage word, the
  crews on it (status dots) or "No crew yet", patients and declines.
- Open calls: a list and a detail pane.
  - Detail header: priority, code, id and live age, plus the P1/P2/P3 control (dispatchers).
  - Title, location and distance, then a stage readout (large stage ring, stage word, "Next ·
    …", `2/6`) next to the actions: Take call (R), Stand down, Route (G), Send a crew (popover),
    Close out (confirm modal).
  - Body: caller box, patients with triage (Immediate / Delayed / Minor) and state, crews on it
    (take off), timeline.
- Crews: a table with callsign, name, grade, status, call link and distance (with an "in vehicle"
  icon). Each row has a route button, and dispatchers get "Send to C-xxxx" for the selected or
  first call without a crew.
- Live map: a canvas map of San Andreas in world coordinates (stylised coastline, Alamo Sea,
  district labels, 1 km grid).
  - Shows hospitals, calls (pulsing, colour by priority, labels), crews (heading arrows coloured
    by status, callsigns, dashed lines to their call) and you.
  - Wheel zooms at the cursor and dragging pans. There are zoom and fit buttons, a scale bar and
    a north arrow.
  - Hovering shows a tooltip and clicking a call selects it. A side panel holds Take call / Route.
- Logbook: the newest `nza_calls` rows. Filter by P1/P2/P3 and search the id, title, street,
  zone, caller or crews. Columns: time, call, priority, location, crews, response time, duration,
  final stage (small ring + word) and reason. Without a database it shows this session's calls.
- ER intake: `NZA.Checkin.Queue()` check-ins (ticket, name, priority, time in, status), and
  inbound crews with their hospital and drive time. Staff with `Config.Checkin.desk.perm`
  (board data `canCallNext`) get **Call next** (key N) → `nza:checkin:callNext`, which calls the
  next waiting ticket of their department to a free bed and answers with a toast.
- Refreshes every `board.refresh` ms. Scroll positions and the selected call are kept. Keys: ↑↓
  pick a call, R, G, M (map), N (call next, ER intake), ESC.

### EMS radial job menu (`radial`, F6) — "orbit"
- Separate round nodes on a dashed orbit, the first one at 12 o'clock, labels as dark chips
  outside the orbit, quick-pick numbers on each node. The node under the mouse fills teal (red for
  danger), scales up, its label turns white and a beam runs from the centre to it with a short arc
  on the orbit. Group nodes carry a dashed halo, toggles an `ON` tag, disabled ones a lock.
  Submenus fly out from the centre. Drawn without backdrop-filter and scaled with a transform, so
  mouse angles stay exact. A soft dark disc behind keeps it readable over bright scenes.
- **Centre = unit badge**: "Unit" kicker, callsign, name, status chip (dot + word) and the shift
  clock. Around it the **unit ring** (6-stage ring while on a call, solid teal when available,
  amber when unavailable, dashed grey off shift) inside the **duty ring** (60 minute ticks, the
  current hour of your shift filled teal). In a submenu the centre shows "← Back", the group icon
  and title; clicking the centre (or RMB / Backspace) goes back — there is no Back node.
- A detail card under the orbit explains the hovered node (icon, label, ON tag, description or the
  reason it is locked in amber, its quick-pick key).
- Root (clockwise from 12): Calls, Care, Gurney, Start / End shift, plus every root item other
  modules add (their `order` decides the place).
  - Care and Gurney list the items of the assess and transport modules (`parent = 'patient'` /
    `'stretcher'`). They are locked with a reason when empty.
  - Calls needs an active shift.
- Calls ring (clockwise from 12): Take next call, Stand down, Live map, Logbook, ER intake, Street
  calls, Go unavailable / Go available, Pager.
  - Street calls and the availability toggle keep the menu open and show `ON` when on.
- Input: mouse hover/click, RMB or Backspace for back, 1-9 quick pick, ←/→ + Enter, ESC or the
  menu key to close. Locked items shake.
- Start / End shift uses `NZA.Hospitals.ToggleDuty` when the medic belongs to a department. That
  respects department membership and duty points. Otherwise it uses
  `nza:dispatch:duty → Bridge.SetDuty`. The hospital module's own `hospital_duty` root entry is
  hidden so the shift item is not shown twice.
- Header data sent by Lua: `name, callsign, grade, status, statusLabel, tone, onDuty, shift
  (seconds since the shift started, tracked on the client), call`.

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
NZA.Dispatch.Page(src, { kind?, priority 1..3, title, text?, hospital? }) → bool   -- one line on that medic's pager
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
| `nza:dispatch:page` | S→C | `{ id, kind, priority, title, text, hospital }` (`NZA.Dispatch.Page`) |
| `nza:wounded:help` | S→C | `{ eta, unit, status }` through `NZA.Wounded.Help` |

Every net handler checks the source and rate-limits. Permissions come from `NZA.Staff`, and
positions are server-side.

NUI callbacks:
- `pager:ack decl clear gps pair mute npc status hide`
- `dispatch:respond assign unassign clear closeCall priority gps status npc refresh log callNext`
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
