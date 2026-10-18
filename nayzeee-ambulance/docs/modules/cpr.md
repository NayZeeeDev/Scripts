# CPR & defibrillator (`cpr`)

Resuscitation for cardiac arrest: chest compressions as a rhythm game, rescue breaths (bag-valve
mask or mouth to mouth), an unbranded **DF-7** portrait monitor / defibrillator (pads, analysis,
charge, stand clear, shock), adrenaline, reversible causes, two-rescuer codes with role swaps,
ROSC and a scored debrief. The server owns every clinical decision.

| File | What |
|---|---|
| `server/modules/cpr.lua` | the code (one per patient): phase machine, validation, callbacks, net events, tick, records, billing, exports |
| `server/modules/cpr_logic.lua` | pure maths `NZA.Cpr.Logic`: compression / breath quality, ROSC chance, rhythm evolution, Hs & Ts, score |
| `client/modules/cpr.lua` | interact options, exam route, radial item, start / join, NUI ⇄ server relay, cleanup |
| `client/modules/cpr_scene.lua` | world side `NZA.Cpr.Scene`: synced anims, NPC patient control, bed mode, BVM / defib case props, camera, pad anchors, player-patient pose |
| `config/modules/cpr.lua` | `Config.Cpr` |
| `locales/en/cpr.lua` | `cpr.*` strings (server, client and every NUI string) |
| `html/apps/cpr/app.js · app.css` | NUI app `cpr` |

## Features

- **Start CPR** (patient option, order 30, perm `cpr`) on a patient in `arrest`, or `wounded` +
  AVPU **U** + not breathing (the server checks breathing; a breathing patient gets "recovery
  position"). Also from the **Examination** screen (`NZA.ExamRoutes` id `cpr`, first button on every
  injury card while the patient is in arrest), the EMS radial (**Patient ▸ Start CPR** on the nearest
  patient in arrest) and by **using the defibrillator item** next to the patient.
- **Synced animation**: medic `mini@cpr@char_a@cpr_str cpr_pumpchest` and patient
  `mini@cpr@char_b` at one origin (intro, pump, idle, kiss-of-life, success). The pump clip runs at
  the medic's real compression rate. NPC patients are animated by the compressor (network control);
  player patients lay themselves flat from the server event `nza:cpr:pose` (the wounded downed pose
  is suspended with `NZA.Wounded.SuspendPose('cpr')`). Patients on a **bed / stretcher / in the
  ambulance bay** are never moved: the medic stands beside them (`Anim.bed`).
- **State bag** `nzaCpr` = server id of the compressor on the patient (player or NPC ped) while a code
  runs; `NZA.Patients.Cpr(pid, src, quality)` is called every second while compressions (or a
  planned pause: breaths, analysis, charging, ≤ 10 s charged) are going on, so the core pauses the
  arrest → death timer and the wounded HUD shows **CPR IN PROGRESS** with the medic's name.
- **Metronome ring** (procedure column, `pp.slot`): a click at 100–120/min (default 110) and a hand
  that sweeps the inner ring once per push; press as it crosses the window at the top. The outer
  ring holds the 30 pushes of the set, each segment coloured by its quality; your presses land as
  dots at their timing error. Short calls under the count (SPOT ON, GOOD, EARLY, LATE, MISSED,
  DEEPER, LIFT OFF), a depth tube with the 5–6 cm band (hold Space too short = shallow, too long =
  leaning / no recoil), early / in time / late bars for the set and recoil %. The rate dial in the
  readout card and a vertical rate gauge on the device show 100–120 as the target band. Idle > 1.6 s
  = "Keep going!". Compressor fatigue (server) lowers depth after 2 minutes; swap to recover.
- **Breaths** after 30 compressions: hold Space ~1 s per breath and watch the chest-rise meter
  (too short = chest barely rose, too long = air into the stomach). Without a BVM item it is mouth to
  mouth: longer hold, 60 % effect. Intubated + ventilated patients get continuous compressions.
  Good breaths clear water / smoke hypoxia. The BVM prop sits on the patient's face during breaths.
- **Defibrillator** (needs `Config.Items.defibrillator` or `trauma_kit`, or the patient in the
  ambulance treatment bay (`meta.bay`) or on a hospital bed / near a hospital): drag the **sternum**
  and **apex** pads onto glowing targets on the chest (world anchors) or onto the torso card
  (P places both). The monitor then shows the real rhythm (VF / VT / PEA / ASYSTOLE / sinus …) with
  a live ECG (`NZA.vitals.Trace`), a CPR-depth trace and capnography (EtCO₂).
  **Analyse** (hands off 4 s: any compression = "motion detected") → VF/VT **shock advised** →
  **charge** (the AED charges by itself; manual mode = any time, energy knob 120–360 J) →
  **stand clear** (any compression while charged = the compressor gets shocked: ragdoll, health,
  shock 40 % as effective) → **SHOCK** → resume CPR. Non-shockable → "no shock advised, resume CPR".
  The charge is dumped after 25 s or with Disarm. AED energies 200 / 300 / 360 J.
- **ROSC** is decided by the server: VF/VT + good CPR + energy + adrenaline + time since arrest
  (low-flow / no-flow) + ventilation + **reversible causes** (hypovolaemia / blood volume, tension
  pneumothorax, tamponade, big haemothorax, hypothermia, hypoxia, obstructed airway, opioid toxins)
  → chance. Asystole / PEA are never shockable; they can return at a 2-minute rhythm check (better
  with adrenaline) or turn into VF. Shocking a patient with a pulse can induce VF.
  ROSC → `NZA.Patients.Revive(pid, { rosc = true })` (patient becomes `wounded` with a perfusing
  rhythm), monitor shows the new rhythm and EtCO₂ jump, ROSC banner, success animation. The code
  stays open 45 s for a re-arrest, then ends.
- **Adrenaline** (perm `meds`, item `Config.Items.adrenaline`, `NZA.Treat 'cpr_adrenaline'`):
  minimum 150 s between doses, the device says DUE every 4 min (or after the 2nd shock /
  non-shockable start). Optional IV/IO requirement.
- **Two rescuers**: a second medic uses **Join CPR** and takes the airway, pads, analysis, charge,
  shock and drugs; **Swap** (X) exchanges roles (the compressor's fatigue shows on the team card). If
  the compressor leaves, the partner is promoted. Both see the same device; each gets role-specific
  instructions.
- **Code-team HUD** (top left): arrest type, patient, downtime, CCF (hands-on %), shocks, adrenaline,
  roles with fatigue, Hs & Ts card (suspect / treating / ok / unknown from findings), code log.
- **AED voice prompts** on the device's message line (speaker + level bars), phase banners (ANALYSING, SHOCK ADVISED, STAND CLEAR, SHOCK
  DELIVERED, NO SHOCK ADVISED, ROSC, RE-ARREST, MOTION DETECTED, YOU WERE SHOCKED), sounds
  (metronome, compression thump, BVM breath, charge whine, ready beeps, shock, QRS beeps).
- **Debrief** (score ring 0–100 with a one-word verdict: STRONG / SOLID / FAIR / WEAK / POOR, from the
  server grade): duration, compressions, shocks, adrenaline, quality, hands-on, breaths, protocol
  (bad shocks, rescuer shocks, long pauses, motion aborts, missing adrenaline) and notes.
  A medical record entry (players) and optional billing for ROSC / shocks.
- **Easy mode** (per department `easy.cpr` or `Config.EasyMode.default`): Space toggles automatic
  compressions in time with the metronome, breaths finish by themselves, P places both pads; the server scores easy
  compressions / breaths with `Config.EasyMode.score`.

## Screen layout

Follows the shared HUD contract (docs/ARCHITECTURE.md §10.2, docs/design/ORIGINAL.md): nothing sits
bottom-centre, the scene keeps the centre.

- **Right-middle, left of the tool belt** (`right: 300px`): the **DF-7** device, a portrait unit with
  our own industrial design and generic labelling only (model code, type, ADULT / CHILD slide switch,
  `DANGER · HIGH VOLTAGE · STAND CLEAR` sticker, reference print, screws, side grips, cable port that
  shows the pads plug). Screen: status bar (pads link, alarm bell, battery, clock), ECG pane
  (`II · ×1.0 · 25 mm/s`, HR box, rhythm tag bottom-left; during analysis the tag becomes an
  ANALYSING / HANDS OFF tag with a progress rule), CO₂ pane with EtCO₂, CPR-depth pane with the rate
  and a vertical 100–120 gauge, then the cycle ring (code time inside, countdown to the rhythm check
  beside it) and an instrument list (energy, shocks with bolt pips, adrenaline timer), and a two-line
  message line for the unit's spoken prompts. Controls: ANALYSE / CHARGE keys and the AED / MAN rocker
  on the left, the 120–360 J energy ring with the SHOCK button in its centre, PADS / DRUG / SWAP or
  PULSE keys on the right. The pad map (torso + two draggable pads) is drawn on the screen.
- **Bottom left**: the shared procedure HUD (`NZA.ui.ProcPanel`): readout dial (rate, or the cycle
  timer for the airway role) with depth / recoil / quality (airway role: ventilation / breaths /
  EtCO₂), the step card with named steps (Compressions · Breaths · Rhythm check · Charge · Shock),
  the metronome card at `pp.slot` (ring, depth tube, timing bars; breaths: hold ring + chest rise; a
  status panel replaces the bars for hands-off moments and shows the partner's rate / quality), key
  hints. The tool belt and hold-to-stop ring sit on the right edge.
- **Top left**: code-team card (status rings for downtime, hands-on %, cycle and adrenaline, roles with
  fatigue, Hs & Ts, code log); on short screens it drops the log, then the join hint and the Hs & Ts,
  so it never covers the instruction column.
- **Top centre**: phase banners (transient). On the debrief the device slides out to the right and the
  summary card takes the centre.

## Controls (in the CPR screen, `Config.Cpr.Keys`, JS `KeyboardEvent.code`)

| Key | Action |
|---|---|
| Space | compress as the metronome hand crosses the top · hold for a breath |
| P | pads (open the pad tray; again = place both) |
| A | analyse |
| C | charge (again / Z = disarm) |
| S | shock |
| Q / E · wheel on the knob | energy − / + (manual mode) |
| M | AED ↔ manual (manual needs perm `defib`) |
| D | adrenaline |
| X | swap roles with your partner |
| F | carotid pulse check |
| H | show / hide the Hs & Ts card |
| Right drag / wheel | orbit / zoom the camera |
| ESC (hold) | stop CPR / leave the code · Enter closes the debrief |

## Config (`Config.Cpr`)

`perm distance maxDist wounded maxTeam icon order radial radialRange examRoute usableDefib` ·
`Keys { compress pads analyse charge shock energyUp energyDown adrenaline swap pulse causes mode disarm }` ·
`Compressions { target rateMin rateMax perSet perfect good pressMin pressMax metronome idleWarn fatigue { enabled after perMinute max recover } }` ·
`Breaths { perSet hold tooShort tooLong timeout mouthToMouth mouthQuality mouthSlower bvmProp bvmAttach continuousIfVentilated }` ·
`Cycle { length checkGrace }` · `Adrenaline { enabled perm minGap due needAccess }` ·
`Defib { perm aedPerm items bay hospital hospitalRadius energies energy aedEnergies analyseTime chargeTime chargedFor clearWindow rescuerShock { ragdoll health efficacy } prop propOffset }` ·
`Pads { snap sternum apex lift }` ·
`Rosc { shockBase peaBase asystoleBase max energy adrenaline noAdrenaline lowFlowDecay noFlowDecay minTime ventilation asystoleToVf peaToVf degrade causes { hypovolemia tension tamponade haemothorax hypothermia hypoxia airway toxins } rearrestWatch }` ·
`Anim { medic patient bed helper helperBed helperDist npcRest origin baseRate introMs patientPose }` ·
`Camera { enabled dist pitch fov }` · `record` · `Billing { rosc shock }`.

## Server API

Callbacks (`lib.callback`, all reply `{ ok, err?, msg?, … }`):
`nza:cpr:start (target, { origin })` → `{ ok, joined, view, origin }` (start, join as partner, or resume) ·
`nza:cpr:pads` · `nza:cpr:analyse` · `nza:cpr:charge ({ energy })` · `nza:cpr:disarm` ·
`nza:cpr:shock` → `{ ok, result = 'rosc'|'none'|'changed'|'no_effect'|'induced', energy, touching }` ·
`nza:cpr:energy ({ energy })` · `nza:cpr:mode ({ mode })` · `nza:cpr:adrenaline` · `nza:cpr:swap` ·
`nza:cpr:pulse` → `{ pulse, rate, weak }`.

Net events C→S: `nza:cpr:cycle { n, timing, depth, recoil, rate, done }` (≤ 8/s, n capped by elapsed
time), `nza:cpr:breath { hold }`, `nza:cpr:hands`, `nza:cpr:leave`.
S→C: `nza:cpr:state (view)`, `nza:cpr:event ({ kind, … })` (analysing, motion, advice, charging,
charged, disarmed, shock, zapped, rosc, rearrest, arrested, breaths, breath, breaths_missed,
adrenaline, swap, joined, partner_left, promoted), `nza:cpr:ended (summary)`,
`nza:cpr:pose ({ on, origin, mode, rate })` (player patient), `nza:cpr:use` (defib item used).

Every handler checks membership, server-side distance (`maxDist + 1/2 m`), permissions
(`NZA.Staff.Can`: `cpr`, `defib` for manual mode, `cpr` for AED, `meds` for adrenaline), items
(Bridge), rate limits; client numbers are clamped and compression counts are capped by elapsed time.

`NZA.Treat 'cpr_adrenaline'`. Bus: `cpr:started (p, code)`, `cpr:shock (p, src, energy, result)`,
`cpr:rosc (p, code)`, `cpr:ended (p, code, reason, summary)`.
`NZA.Cpr.Get(pidOrSrc)`, `NZA.Cpr.End(pid, reason)`, `NZA.Cpr.Leave(src, reason)`, `NZA.Cpr.Push(code)`.
Exports: `IsInCpr(pidOrSrc) → bool`, `GetCode(pidOrSrc) → { id, pid, comp, air, phase, shocks, compressions, started, rosc } | nil`.

## Client API

`NZA.Cpr.Start(entity?, target?) → bool` (awaits; call from a thread), `NZA.Cpr.Active()`,
`NZA.Cpr.Nearest(maxDist?) → ped, target`, `NZA.Cpr.WaitEnd()`, `NZA.Cpr.Bag(ped) → compressor id | nil`.
Client bus: `cpr:started (code)`, `cpr:ended (summary)`.

NUI app `cpr`: open `{ view, keys, cfg, locale, easy }`, actions `state`, `event`, `ended`, `anchors`
(`padR`, `padL`); callbacks `cpr:press`, `cpr:report`, `cpr:hands`, `cpr:breathStart`, `cpr:breath`,
`cpr:action { name, data }`, `cpr:leave`. Preview: `html/index.html?app=cpr&demo=` `compress | breaths |
pads | analyse | charged | rosc | air | easy | nodefib | debrief` (playable: the preview has a small
stand-in for the server).

## Known limits

- The CPR / kneel animation dicts are base-game (`mini@cpr@…`, `missheistfbi3b_ig8_2`,
  `amb@medic@…`); the synced origin (`Anim.origin`, default ground + 1.0 m, medic heading) may need a
  small z tweak for some ped models. Pad target positions come from bones (`Pads.*`).
- The ECG trace is the shared `NZA.vitals.Trace`; it does not draw CPR compression artefacts.
- Client-side only medics see the device; bystanders see the animations and the props.
- Verified with the browser preview (all states, 1920×1080 and 1280×720) and stubbed-native Lua smoke
  tests of the full server flow (start → 30:2 → breaths → join → pads → analyse → manual energy →
  charge → shock → adrenaline gap → swap → ROSC → pulse → leave) and the client flow; not yet in a live
  FiveM server.
