# Requests from the dispatch module

## Lead (integration)

1. **`sql/install.sql`**: add the `nza_calls` table. The exact statement is in
   `docs/modules/dispatch.md` → Database. It is the same one `server/modules/dispatch_log.lua`
   runs on start.
2. No change is needed in `html/index.html`. The `callcard`, `pager`, `dispatch` and `radial`
   apps are already listed. `html/apps/callcard/app.js` defines `window.NZD`, small helpers the
   other three dispatch apps use. That only works because `callcard` loads before them, which the
   current order already does.

## Check-in module

The board's "Hospital queue" tab and the "Hospital queue" stat read
`NZA.Checkin.Queue()` (server, guarded with pcall). Please return an array of tickets:
```lua
{ { ticket = 'A-014', name = 'Rosa Diaz', priority = 1..3, created = os.time() (or wait = seconds),
    status = 'waiting' | 'called' | 'treatment', hospitalLabel = 'Pillbox' }, ... }
```
The board also reads `number`/`code`/`id` for the ticket, `patient` for the name, `tri`/`triage`
for the priority, and `at`/`time`/`issued` for the time, so another shape works too.

## Hospital module

- The EMS radial job menu already has "Go on / off duty". For medics who belong to a department
  it calls `NZA.Hospitals.ToggleDuty(on)`, so membership, `duty.requirePoint` and own-duty
  overrides still apply. To avoid two duty entries on the wheel, the radial hides the root entry
  with id `hospital_duty` while `Config.Dispatch.radial.dutyToggle` is on. Nothing to change. If
  you rename that id, please tell dispatch.
- Optional: a `callsign` field in the staff record is used as the unit callsign when the medic
  did not set one with `/callsign`.

## NPC calls module

- `Player(src).state.nzaNpcCalls` (set by the server, replicated) is `true` while a medic wants
  NPC calls. Players toggle it in the radial → Dispatch → NPC calls, on the pager and on the
  board. The value is saved per character and defaults to `Config.Dispatch.npcCalls.defaultOn`.
- `NZA.Dispatch.Create{ ... voice = 'audio/calls/xyz.ogg' }`: the path is relative to `html/`.
  Only `[%w_-/.]` characters and `.ogg`/`.mp3`/`.wav` are accepted. `patients = { pid }` links the
  NPC patients. Dispatch writes `patient.meta.callId` itself. Patients created later with
  `meta.callId` set join the call automatically.

## Transport module

Already integrated: `transport:loaded (src, p, vehNet, strNet)` → TRN, and
`transport:bed (src, p, point)` → HSP. Please keep those bus signatures.
