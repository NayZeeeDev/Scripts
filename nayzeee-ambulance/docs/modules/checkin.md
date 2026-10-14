# Module: checkin

Check-in desk with an NPC receptionist, triage tickets (thermal-paper receipt + inventory
item), a per-department queue, the waiting-room TV board (DUI), staff calls to free beds, the
AI doctor (cinematic treatment in a bed) and the bed rest HUD for every hospital bed.

## Files

| File | What it does |
|---|---|
| `server/modules/checkin.lua` | tickets, numbering, triage, queue order, beds/reservations, staff calls, board + desk payloads, notifications, item, DB (`nza_tickets`), restore after restart, `NZA.Checkin` API |
| `server/modules/checkin_ai.lua` | AI doctor: plan, bill (insurance), server-run treatment session, hand-over rules, `nza:checkin:lie`, `nza:checkin:rest` |
| `client/modules/checkin.lua` | `checkin` point type (receptionist ped, [E]/[G] prompts, targets), receipt / chip / subtitles / reception window, called-to-bed guide (waypoint + marker + [E] Lie down), staff toasts, radial items |
| `client/modules/checkin_bed.lua` | lying in a called bed, get up (hold while the AI works), AI doctor HUD, doctor ped, cinematic camera, bed rest HUD |
| `client/modules/checkin_tv.lua` | `tv` point type, DUI board (replace texture on the NAYZEEE screen, render target on native TVs), chime |
| `html/apps/checkin/` | NUI app `checkin` (receipt, ticket chip, receptionist subtitle, reception window) |
| `html/apps/bed/` | NUI app `bed` (AI doctor cinematic HUD, bed rest bar) |
| `html/dui/tv.html` `tv.css` `tv.js` | waiting room board (DUI page, 16:9, vw-based) |
| `config/modules/checkin.lua` | `Config.Checkin` |
| `locales/en/checkin.lua` | every `checkin.*` string (Lua, both apps and the board) |

## Features

### Check-in desk (`checkin` position)
- Placed in the EMS Manager → Positions. Data: `prefix` (ticket letter, A/B/…), `ped` (receptionist
  on/off), `pose` (`sit` / `stand`), `model` (custom ped), `name` (receptionist name), `z` (height offset).
- Local receptionist ped (scenario `PROP_HUMAN_SEAT_COMPUTER` / `WORLD_HUMAN_CLIPBOARD`) spawned with
  the point, invincible, removed with the point / resource.
- Prompt `[E] Check in — treat injuries · Check-in Desk` (no target needed); with a ticket it shows
  `Your ticket A-014 · 2 ahead of you` / `Go to Bed 3` / `In treatment`. Staff also get
  `[G] Reception queue`. Target options: Check in, Show my ticket, Leave the queue, Reception queue,
  Call next patient (staff) — skipped when the bridge target is the built-in prompt.
- Server: ticket per department per desk letter per day (`A-001`, `A-002`…; counters survive
  restarts), triage from `NZA.Patients.Triage` (P1 Critical / P2 Urgent / P3 Standard), patients
  ahead, estimated wait (`queue.estimate` minutes per ticket ahead ÷ staff on duty), issued time.
  Refuses when nothing needs treatment (`desk.requireInjury`), carried / on a stretcher / already in
  a bed, in arrest, a cooldown, too far.
- `Config.Items.triage_ticket` with metadata (`ticket`, `ticketId`, `hospital`, `triage`, `issued`,
  label + description). Using the item shows the receipt again (an old ticket shows a red
  "Not valid" stamp). The item is taken back when the visit ends (`desk.takeBack`).
- Receptionist answers with a subtitle (P1 "you need a doctor right now", next, N ahead, already
  have a ticket, nothing to treat).

### Receipt (NUI `checkin`, mode `ticket`)
Thermal paper coming out of a NAYZEEE printer slot (stepped feed animation, printer buzz + tear
sound): teal NAYZEEE mark, department + desk, `#0014`, YOUR NUMBER `A-014`, triage chip, patient,
patients ahead, waiting mm:ss (live), estimated wait, issued (game or real clock), barcode +
id, "Please keep this ticket. Watch the screen for your number.", torn bottom edge, stamps
(Called · Bed 3 / In treatment / Treated / Closed / Not valid). Stays `desk.receiptTime` seconds
(0 = until you walk away from the desk).

### Ticket chip (top centre while you wait)
`A-014 · P2 · Ahead 2 · Waiting 06:12 · Est. ~8m`; when called it turns teal and glows:
`Your number is called — A-014 → Bed 3 · Go now 00:13`; in treatment: `AI doctor / In treatment · Bed 3`.

### Waiting room board (`tv` position, DUI)
- `Config.Props.tv_board` (NAYZEEE screen; `Config.PropScreens.tv_board` texture replaced by the DUI)
  or `existing = true` to take over the nearest map TV of `tv.existingModels` (drawn into its render
  target, `tv.renderTargets`; the placed screen is hidden). The fallback native TV model also uses
  the render target. Data: `existing`, `title` (overrides the department name).
- Only the nearest board within `tv.drawDistance` runs; leaving unsubscribes at once and destroys the
  browser after `tv.linger` s.
- Board (readable from across the room): department + "Waiting room", big clock (game or real),
  NOW SERVING (up to `queue.maxServing` cards: ticket → bed, "Please go now" / "In treatment", triage
  colour bar; or "Please take a seat. Your ticket number will appear here when a bed is ready."),
  WAITING list (P1/P2/P3 chip, ticket, live wait time, amber after 15 min, "+ N more"), INCOMING
  ambulances (unit, priority, ETA min / blinking "Arriving" — units in `TRN` whose nearest hospital is
  this department, via `NZA.Dispatch.Units/NearestHospital`), footer counts (Waiting, In treatment,
  Beds free x/y with bar, Medical staff on duty n / "AI doctor on call"), teal info ticker.
- A newly called number flashes full screen for 7 s ("NOW CALLING A-014 → Bed 3", "YOUR NUMBER" when
  it is yours) with a two-tone chime (volume by distance, `tv.chime`, `tv.chimeDistance`). Your own
  ticket is outlined on the board.

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
  next ticket (P1 first, then by arrival) becomes Now serving with a reserved free bed; the patient
  gets a toast + sound, a waypoint, a bobbing marker on the bed and `[E] Lie down · Bed 3`.
- Lying on the assigned bed turns the ticket "In treatment" (`queue.autoTreatment`); a medic who
  treats a waiting patient or puts them on a bed (transport) takes the ticket over; a staff ticket
  closes as treated when the patient leaves the bed healed (`queue.doneOnLeave`). Called patients
  who never come are closed as no-show after `queue.noShow` s. Offline patients keep their place for
  `queue.offlineGrace` s; tickets expire after `queue.expire` s; triage is re-checked while waiting
  (worse → staff toast).
- Staff notification on every check-in: toast "New patient A-014 · P2 Urgent" (P1 red with pager
  beep), phone notification (`queue.notify.phone`: always / only paired pagers), pager line when the
  dispatch module exposes `NZA.Dispatch.Page` (see requests).

### AI doctor
- Takes waiting tickets when no staff of the department (with `ai.staffPerm`) is on duty after
  `ai.noStaffDelay` s, or when nobody called them within `ai.waitTimeout` s; staff can hand a ticket
  over. Optional `ai.requirePayment`.
- Travel: `walk` (waypoint, lie down yourself) or `teleport` (fade into the bed); downed patients are
  always moved into the bed (`ai.downedTeleport`).
- Plan: Assessment → Resuscitation (downed) → Transfusion (blood < `ai.transfuseBelow`) → one step
  per injury (severity first; time `ai.times[type] + perSeverity`) → Discharge, scaled into
  `ai.minTime..ai.maxTime`. Each step applies its treatment flags when it ends (real vitals improve);
  the end heals (`ai.heal`), revives and closes the ticket as treated.
- HUD (NUI `bed`, mode `ai`): cinematic letterbox with captions, doctor card (ticket, bed), time
  left flip clock, overall % with per-step segments, timeline (done ✓ / current with description,
  progress and countdown / pending with duration), NAYZEEE bedside monitor (live ECG/pleth/resp +
  HR/SpO₂/MAP/NIBP/RR/Temp from the server every 2 s), bill card (lines, subtotal, insurance plan
  and cover %, You pay), doctor subtitles per step, `[C] Camera`, hold `[X]` to get up (ring).
  Completion card: steps done, final bill, paid / billed to you, auto stand-up countdown.
- Local doctor ped beside the bed (clipboard scenario for assessment/discharge, working anim for
  procedures), slow cinematic camera shots around the bed (wall-safe ray test), radar hidden;
  `[C]` toggles back to your own camera.
- Bill: `ai.prices` (+`perSeverity`), insurance from `NZA.Insurance.Get`, charged through
  `NZA.Billing.Charge` (society, unpaid bills) or directly from bank/cash with `Bridge`. Getting up
  early bills only the finished steps.

### Bed rest HUD (NUI `bed`, mode `rest`)
Every bed you lie in (hospital module bed, called bed, or a medic's transport placement): bed +
department, rest timer (flip clock), recovery % bar, "Fully healed in ~N min" (or what still needs
treatment), ×4 healing badge (`meta.inBed`), up to 5 injuries with heal %, blood, pain, and the
get-up key that applies (or "A medic will help you off the bed"). Hides the hospital module's small
get-up prompt (`rest.hideBedPrompt`).

## Controls
| Key | Where | Action |
|---|---|---|
| `E` (`desk.control`) | desk | check in / show your ticket |
| `G` (`desk.staffControl`) | desk, staff | reception window |
| `E` | at your called bed | lie down |
| `X` (`rest.getUpControl`) | in a called bed | get up (hold `ai.getUpHold` s while the AI works) |
| `C` (`ai.cameraControl`) | AI treatment | cinematic / own camera |
| `N`, `↑↓`, `Enter`, `Esc` | reception window | call next, select, call selected, close |

## Config (`Config.Checkin`)
`desk` (promptDistance, key/control, staffKey/staffControl, target, perm, requireInjury, allowDowned,
cooldown, prefix, digits, giveItem, takeBack, receiptTime, ticketHud, printSound) ·
`receptionist` (enabled, models, sitScenario, standScenario, spawnDistance, talk) ·
`queue` (expire, offlineGrace, noShow, estimate, maxServing, keepServing, autoTreatment, doneOnLeave,
restore, history, notify { toast, sound, pager, phone, scope }) ·
`ai` (enabled, noStaff, noStaffDelay, waitTimeout, staffPerm, travel, downedTeleport, doctorPed,
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
Server bus: listens `hospital:bed transport:bed treat:done proc:done player:loaded player:unloaded`;
emits `checkin:issued (t)`, `checkin:called (t)`, `checkin:treatment (t)`, `checkin:closed (t, status)`, `checkin:ai (t, outcome)`.
NUI: `checkin:action deskClose refresh hospital leave hidden`, `bed:hidden`.
Radial (`NZA.RadialItems`, parent `dispatch`): `checkin_next`, `checkin_queue`.

## Data
`nza_tickets` (created on start; SQL in `docs/requests/checkin.md`). Open tickets of the last
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
- Pager lines need `NZA.Dispatch.Page` (requested); the dispatch board's "Call next" button is requested too.
