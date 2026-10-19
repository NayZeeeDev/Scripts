# Requests from the `cpr` module

Nothing blocks the module; these are improvements for lead-owned files.

1. **`html/core/nza-vitals.js` — optional CPR artefact on the ECG** (nice to have).
   Real monitors show a large compression artefact while CPR is running and a clean trace during the
   analysis pause. Proposal: `Trace(canvas, { artifact: 0..1 })` adds `artifact * 0.55 * sin(2π·t·rate/60)`
   to the `ecg` wave (rate = compression rate). The cpr app would set it from its own compressions
   and set it to 0 during `analyse`. No change needed for other apps (default 0).
   Status: done. `html/core/nza-vitals.js` takes `artifact` (0..1, default 0) and `cprRate`.

2. **Core state bag `nza.cpr`** — already requested by the wounded module (docs/requests/wounded.md).
   Until then the cpr server sets its own replicated state bag `nzaCpr` (= compressor server id) on the
   player / NPC ped; the wounded client already reads it, and `NZA.Patients.Cpr` keeps `lastCpr`
   fresh every second for the core.

3. **Reference index** (`/tmp/nza-work/reference/INDEX.md`, informational): the CPR & defibrillator
   screenshot is `063283a1-image.png`; the index lists it as the treatment bay and points the CPR row
   at `5401895d` (that file is Field resus 6/7). The first batch of rows looks shifted by one or two.
