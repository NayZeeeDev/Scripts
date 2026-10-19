# Module: checkin

Reception desk with an NPC receptionist, triage queue numbers (dark glass queue pass + inventory
item), a per-department queue, the waiting-area board (DUI), staff calls to open beds, the
AI doctor (cinematic treatment in a bed) and the bed rest card for every hospital bed.

UI originality (customer requirement, `docs/design/ORIGINAL.md`): no paper receipt, no barcode, no
"your number / patients ahead / please keep this ticket" layout, no "now serving / waiting list /
incoming" board arrangement, no bottom-centre subtitle strip; no product name or logo on the
board, the bedside monitor or any device face.

## Files

| File | What it does |
|---|---|
| `server/modules/checkin.lua` | tickets, numbering, triage, queue order, beds/reservations, staff calls, board + desk payloads, notifications, item, DB (`nza_tickets`), restore after restart, `NZA.Checkin` API |
| `server/modules/checkin_ai.lua` | AI doctor: plan, bill (insurance), server-run treatment session, hand-over rules, `nza:checkin:lie`, `nza:checkin:rest` |
| `client/modules/checkin.lua` | `checkin` point type (receptionist ped, [E]/[G] prompts, targets), queue pass / queue dock / receptionist voice (NZA.speech) / reception window, called-to-bed guide (waypoint + marker + [E] Lie down), staff toasts, radial items |
| `client/modules/checkin_bed.lua` | lying in a called bed, get up (hold while the AI works), AI doctor HUD, doctor ped, cinematic camera, bed rest HUD |
| `client/modules/checkin_tv.lua` | `tv` point type, DUI board (replace texture on the board screen model, render target on native TVs), chime |
| `html/apps/checkin/` | NUI app `checkin` (queue pass, queue dock, reception window; receptionist lines go to `NZA.speech`) |
| `html/apps/bed/` | NUI app `bed` (AI doctor cinematic HUD, bed rest bar) |
| `html/dui/tv.html` `tv.css` `tv.js` | waiting-area board (DUI page, 16:9, vw-based, generic cross glyph only) |
| `config/modules/checkin.lua` | `Config.Checkin` |
| `locales/en/checkin.lua` | every `checkin.*` string (Lua, both apps and the board) |

## Features

### Check-in desk (`checkin` position)
- Placed in the EMS Manager → Positions. Data: `prefix` (ticket letter, A/B/…), `ped` (receptionist
  on/off), `pose` (`sit` / `stand`), `model` (custom ped), `name` (receptionist name), `z` (height offset).
- Local receptionist ped (scenario `PROP_HUMAN_SEAT_COMPUTER` / `WORLD_HUMAN_CLIPBOARD`) spawned with
  the point, invincible, removed with the point / resource.
- Prompt (context tag beside the crosshair, `NZA.prompt`): `[E]` kicker = the point label (or
  "Front desk"), label `Take a queue number`; with a number it shows `Queue pass B-024 · 2 ahead of
  you` / `Go to Bed 3` / `In treatment`. Staff also get `[G] Reception queue`; while you wait, a red
  hold prompt `[X] Leave the queue` (`desk.leaveControl`, hold `leaveHold` s) works with every target
  system, also the built-in one. Target options: Take a
  queue number, Show my queue pass, Leave the queue, Reception queue,
  Call next patient (staff) — skipped when the bridge target is the built-in prompt.
- Server: ticket per department per desk letter per day (`A-001`, `A-002`…; counters survive
  restarts), triage from `NZA.Patients.Triage` (P1 Critical / P2 Urgent / P3 Standard), patients
  ahead, estimated wait (`queue.estimate` minutes per ticket ahead ÷ staff on duty), issued time.
  Refuses when nothing needs treatment (`desk.requireInjury`), carried / on a stretcher / already in
  a bed, in arrest, a cooldown, too far.
- `Config.Items.triage_ticket` with metadata (`ticket`, `ticketId`, `hospital`, `triage`, `issued`,
  label + description). Using the item shows the queue pass again (an old number shows a red
  "Not valid" status). The item is taken back when the visit ends (`desk.takeBack`).
- Receptionist answers through the top-centre voice card (`NZA.speech`: initials ring, name +
  role, quoted line): P1 "you go first", next, N ahead, already have a number, nothing to treat.

### Queue pass (NUI `checkin`, mode `ticket`, top-left)
Dark glass card that slides in from the left edge with a scan sweep: teal corner bracket, "Queue
pass" kicker, department + desk + `#0014`, status chip (In queue / Called / In treatment / Not
valid), a queue ring (ticked bezel, arc = progress from the first count of people ahead, centre =
people ahead / "Go" / icon), rolling queue number `B-024` (odometer digits), triage chip, an
instrument list (name, time in queue live, expected call / bed), the journey spine (Registered →
In the queue → Called to a bed → Treatment, current node pulses) and a footer "Pass saved to your
pockets" + short id. Stays `desk.receiptTime` seconds (0 = until you walk away from the desk).

### Queue dock (top-left while you wait)
Compact card in the same corner: mini ring + `B-024` + triage chip + time in queue + expected call;
called → teal ring with a bed icon, `B-024 → Bed 3`, blinking "Go now" + countdown; in treatment
(AI doctor) → `B-024 · Bed 3 / Stay on the bed`.

### Waiting-area board (`tv` position, DUI)
- `Config.Props.tv_board` (board screen model; `Config.PropScreens.tv_board` texture replaced by the DUI)
  or `existing = true` to take over the nearest map TV of `tv.existingModels` (drawn into its render
  target, `tv.renderTargets`; the placed screen is hidden). The fallback native TV model also uses
  the render target. Data: `existing`, `title` (overrides the department name).
- Only the nearest board within `tv.drawDistance` runs; leaving unsubscribes at once and destroys the
  browser after `tv.linger` s.
- Board (readable from across the room, sizes in vw): left info rail — department (wraps to two
  lines, smaller for long names) + "Emergency · waiting area", rolling clock (game or real) with
  date, three status rings (beds open x/y, staff on shift / "AI doctor on call" / "No staff on
  shift", people in the queue + in treatment), "En route" unit cards at the bottom (unit, priority,
  ETA min / blinking "At the door"; one card per ambulance whose nearest hospital is this
  department: dispatch units in `TRN` (`NZA.Dispatch.Units/NearestHospital`), ambulances that loaded
  a patient without a 911 call (`NZA.Transport.trips` while the patient is still in the vehicle;
  driver's callsign, else the plate) and the AI ambulance in its transport stage
  (`NZA.AIMedic.Jobs`, "AI Ambulance", heading for its booked bed)). Right: the BEDS bay map (one
  tile per bed, called tiles glow teal with "Go to your bed", treatment tiles show the number with
  "In treatment", open tiles are dashed "Open · Ready for the next patient", other occupied beds "In
  use"; 3–4 columns, balanced rows, up to 8 tiles) and the QUEUE as three triage lanes (P1 / P2 / P3
  head with count, number tokens in call order with live wait time, amber after 15 min, "+N",
  "Nobody in this lane"). Info ticker at the bottom.
- A newly called number takes over the screen for 7 s (ring sweep, "Number called", `B-024 → Bed 3`,
  "That is you" when it is yours) with a two-tone chime (volume by distance, `tv.chime`,
  `tv.chimeDistance`). Your own number is outlined white with a "You" mark.

### Staff flow (reception window, NUI `checkin` mode `desk`, v5 window)
- Open with `[G]` at the desk, the desk target, or radial Dispatch → Reception queue.
- Queue page: stat tiles (waiting + P1 count, in treatment + called, beds free, average wait + served),
  ticket list (triage bar, code, chip, name, offline tag, injury chips, live state/timer), detail panel
  (code, triage, name, status, waiting, issued, blood %, reported injuries with severity bars) and
  actions: Call to a chosen free bed, Hand to the AI doctor, Cancel; for called tickets Call again,
  Arrived, Back to queue, No-show; in treatment Mark as treated, Back to queue.
- Beds page: every bed (free / reserved / occupied with ticket + name). Today page: closed tickets
  (outcome, waited, handled by, closed time).
- `Call next patient` (button, `N`, desk target, radial, net event from the dispatch board) → the
  next number (P1 first, then by arrival) is called to a reserved open bed; the patient
  gets a toast + sound, a waypoint, a bobbing marker on the bed and `[E] Lie down · Bed 3`.
- Lying on the assigned bed turns the ticket "In treatment" (`queue.autoTreatment`); a medic who
  treats a waiting patient or puts them on a bed (transport) takes the ticket over; a staff ticket
  closes as treated when the patient leaves the bed healed (`queue.doneOnLeave`). Called patients
  who never come are closed as no-show after `queue.noShow` s. Offline patients keep their place for
  `queue.offlineGrace` s; tickets expire after `queue.expire` s; triage is re-checked while waiting
  (worse → staff toast).
- Staff notification on every check-in: toast "New patient B-024 · P2 Urgent" (P1 red with pager
  beep), phone notification (`queue.notify.phone`: always / only paired pagers) and a pager line
  through `NZA.Dispatch.Page` (page log + a few seconds on the pager glass + beep; `queue.notify.pager`).
- A patient who dies while waiting or called gives the ticket up (closed as `left`, bed released).
- The desk also offers "Pay medical bills" as a target option when the pharmacy module runs
  (`NZA.Pharmacy.Open(point, 'bills')`, desk mode). The dispatch board's ER intake page has
  "Call next" (key N) for staff with `desk.perm` (`nza:checkin:callNext`).

### AI doctor
- Takes waiting tickets when no staff of the department (with `ai.staffPerm`) is on duty after
  `ai.noStaffDelay` s, or when nobody called them within `ai.waitTimeout` s (P1 tickets after
  `ai.criticalTimeout` s when that is set); staff can hand a ticket over. Optional `ai.requirePayment`.
  Patients in cardiac arrest or dead are never taken.
- Travel: `walk` (waypoint, lie down yourself) or `teleport` (fade into the bed); downed patients are
  always moved into the bed (`ai.downedTeleport`).
- Plan: Assessment → Resuscitation (downed) → Transfusion (blood < `ai.transfuseBelow`) → one step
  per injury (severity first; time `ai.times[type] + perSeverity`) → Discharge, scaled into
  `ai.minTime..ai.maxTime`. Each step applies its treatment flags when it ends (real vitals improve);
  the end heals (`ai.heal`), revives and closes the ticket as treated.
- HUD (NUI `bed`, mode `ai`): cinematic letterbox with captions (cross glyph + department, live
  dot, number · bed). Care-plan card top-left: progress ring (ticked bezel) around a rolling
  time-left counter, doctor + number/bed tags, instrument list (progress %, stage 03/06) and a
  vertical step spine (done = teal node + check, current = pulsing node inside a ring that fills
  with the step, description card, countdown; pending = duration). Top-right: generic patient
  monitor (model plate "PM-7", "Patient monitor", amber "Adult" sticker, grille + buttons; live
  ECG/pleth/resp + HR/SpO₂/MAP/NIBP/RR/Temp from the server every 2 s) and the care-costs card
  (cover ring, lines, subtotal, insurance plan + %, your share). Doctor lines per step go to the
  top-centre voice card (`NZA.speech`). Keys in the bottom letterbox: `[C] Camera`, hold `[X]` to
  leave the bed (ring). Discharge card (centre, two columns): ticked ring with a check, "You are
  patched up", the finished steps on a spine with their times, final costs, paid / billed to you,
  "Getting up…" countdown ring.
- Local doctor ped beside the bed (clipboard scenario for assessment/discharge, working anim for
  procedures), slow cinematic camera shots around the bed (wall-safe ray test), radar hidden;
  `[C]` toggles back to your own camera.
- Bill: `ai.prices` (+`perSeverity`), insurance from `NZA.Insurance.Get`, charged through
  `NZA.Billing.Charge` (society, unpaid bills) or directly from bank/cash with `Bridge`. Getting up
  early bills only the finished steps.

### Bed rest card (NUI `bed`, mode `rest`, right edge)
Every bed you lie in (hospital module bed, called bed, or a medic's transport placement): card that
slides in from the right edge — bed + department, ×4 healing badge (`meta.inBed`), a recovery ring
(amber while a wound needs treatment first), instrument list (resting time as a rolling counter,
healed in ~N min, blood, pain), a note when something still needs treatment, up to 5 injuries each
with its own heal ring, and the get-up key that applies (or "A medic will help you off the bed"). Hides the hospital module's small
get-up prompt (`rest.hideBedPrompt`).

## Controls
| Key | Where | Action |
|---|---|---|
| `E` (`desk.control`) | desk | take a queue number / show your queue pass |
| `G` (`desk.staffControl`) | desk, staff | reception window |
| hold `X` (`desk.leaveControl`, `leaveHold` s) | desk, while waiting | leave the queue (also a target option) |
| `E` | at your called bed | lie down |
| `X` (`rest.getUpControl`) | in a called bed | get up (hold `ai.getUpHold` s while the AI works) |
| `C` (`ai.cameraControl`) | AI treatment | cinematic / own camera |
| `N`, `↑↓`, `Enter`, `Esc` | reception window | call next, select, call selected, close |

## Config (`Config.Checkin`)
`desk` (promptDistance, key/control, staffKey/staffControl, leaveKey/leaveControl/leaveHold, target, perm, requireInjury, allowDowned,
cooldown, prefix, digits, giveItem, takeBack, receiptTime, ticketHud, printSound) ·
`receptionist` (enabled, models, sitScenario, standScenario, spawnDistance, talk) ·
`queue` (expire, offlineGrace, noShow, estimate, maxServing, keepServing, autoTreatment, doneOnLeave,
restore, history, notify { toast, sound, pager, phone, scope }) ·
`ai` (enabled, noStaff, noStaffDelay, waitTimeout, criticalTimeout, staffPerm, travel, downedTeleport, doctorPed,
doctorModels, doctorScenario, doctorWork, cinematic, shotTime, cameraKey/cameraControl, getUpHold,
summaryTime, times, scale, minTime, maxTime, transfuseBelow, heal, revive, billing, prices,
requirePayment, account, fallbackCash) ·
`rest` (enabled, getUpKey/getUpControl, poll, hideBedPrompt, zOffset, exitSide, dict, clip — the
hospital module's `Config.Hospital.bed` wins) ·
`tv` (enabled, width, height, drawDistance, linger, refresh, chime, chimeDistance, arriving, etaSpeed,
maxWaiting, maxIncoming, existingModels, renderTargets, existingRadius) · `clock` ('game'|'real') ·
`radial` · `rates`.

## API

Server (`NZA.Checkin`):
```lua
Queue(hospital?) → { { id, ticket, number, code, name, priority, tri, created, wait, status, bed, hospital, hospitalLabel } }
Get(id) ForPid(pid) ForSource(src) → open ticket | nil
CallNext(hospital, bySrc?) → ok, ticket | err        Call(id, bedPointId?, bySrc?, ai?) → ok, err
Close(id, 'done'|'noshow'|'left'|'cancelled', bySrc?) → bool    SetTreatment(id, bySrc?) → bool   Requeue(t)
Board(hospital) → board payload        Beds(hospital) → { { id, label, state, ticket?, name? } }
BedLabel(point) StaffCount(hospital) Public(ticket, full?)
NZA.Checkin.AI.Plan(p) → steps, total   AI.Bill(p, ticket, steps, onlyDone?) → bill   AI.Start(t) AI.Stop(t, reason) AI.Session(id)
```
Export: `GetCheckinQueue(hospital?)`.
Client: `NZA.Checkin.Mine()`, `OpenDesk(hospital?, pointId?)`, `CallNext(hospital?, pointId?)`,
`ShowReceipt(ticket?, opts?)`; internals `NZA.CheckinC.Lying() LieDown(ticket, teleport) GetUp(reason) AIActive() Clock()`.

Callbacks: `nza:checkin:checkin (pointId)`, `:mine ()`, `:leave ()`, `:desk ({ point?, hospital?, watch })`,
`:action (action, data)` (callNext call ai recall treatment treated noshow requeue cancel), `:tv (hospital, on)`,
`:lie ({ point, on, teleport })`, `:rest ()`.
Net events: C→S `nza:checkin:callNext (hospital?)`; S→C `nza:checkin:mine (ticket|false, event, closed?)`,
`:receipt (ticket)`, `:staff (note)`, `:desk (desk)`, `:board (hospital, board)`, `:bed ({ point, on })`,
`:ai (action, data)` (start step vitals done abort).
Server bus: listens `hospital:bed transport:bed treat:done proc:done patient:death player:loaded player:unloaded`;
emits `checkin:issued (t)`, `checkin:called (t)`, `checkin:treatment (t)`, `checkin:closed (t, status)`, `checkin:ai (t, outcome)`.
NUI: `checkin:action deskClose refresh hospital hidden` (the bed app posts nothing; Lua closes it).
Radial (`NZA.RadialItems`, parent `dispatch`): `checkin_next`, `checkin_queue`.

## Data
`nza_tickets` (created on start with the same statement as `sql/install.sql`: InnoDB, utf8mb4). Open tickets of the last
`queue.expire` seconds are restored as waiting after a restart (`queue.restore`).

## Security
Everything is decided on the server: desk distance from the server ped, point type/department,
patient state, cooldown and rate limits; staff actions need `desk.perm` in the ticket's department
(admins any); bed lying only on the bed your ticket was called to, within 3.5 m (teleport only for AI
calls); board subscription only near one of that department's boards; the ticket item is matched by
identifier; bills and heals come only from the server session (timers on the server, getting up
aborts it).

## Verification
- `luac5.4 -p` on all Lua files, `node --check` on `html/apps/checkin/app.js`, `html/apps/bed/app.js`, `html/dui/tv.js`.
- Server flow run under plain Lua 5.4 with FiveM mocks: check in → AI picks the ticket → lie down →
  AI session steps/vitals → done (healed, ticket closed); staff check in → desk → call next → no-show;
  TV subscription.
- Browser previews without console errors: `index.html?app=checkin` (`&view=desk|beds|today|chip|called|treat|p1|expired`, `&print=1`),
  `index.html?app=bed` (`&view=ai|done|rest|hold|nocam`), `dui/tv.html` (`?state=full|empty|flash|mine|standby`) at 1920×1080 / 1280×720.

## Known limits
- The DUI replaces the screen texture of every `nz_amb_tv_board` (and draws into the shared `tvscreen`
  render target of native TVs): two boards of different departments in view at the same time show the
  nearest one's data.
- The board chime plays from the board browser (not positional, volume by distance).
- The cinematic camera only avoids walls between the bed and the camera, not props in the room.
