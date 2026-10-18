# xray — X-ray room, films, lightbox reading, setting bones & casts

The radiology department: lay the patient on the **X-ray table**, expose an **AP + lateral film**
of one body part, read it on a **lightbox** by pinning every break and fragment (the diagnosis is
then confirmed in the examination), **set displaced bones** under live fluoroscopy and **apply a
cast**. Every film is built from the patient's real injuries and drawn procedurally in the NUI.

| Side | Files |
|---|---|
| client | `client/modules/xray.lua` (points, patient options, capture, reading, help off the table, radial) · `client/modules/xray_ortho.lua` (set the bone, cast, exam routes) |
| server | `server/modules/xray.lua` (films, capture proc, reading sessions & scoring, off table, usable film) · `server/modules/xray_ortho.lua` (`xray_reduce`, `xray_cast` procs) |
| NUI | `html/apps/xray/app.js` + `app.css` — one app, modes `choose expose read view reduce cast` |
| config / locale | `config/modules/xray.lua` (`Config.Xray`) · `locales/en/xray.lua` (`xray.*`) |

---

## Features

### X-ray room
- Hospital point types **`xray`** (`Config.Props.xray_table`) and **`lightbox`**
  (`Config.Props.lightbox`), placed with the builder (listed automatically).
- The transport module lays patients on the table (`patient.meta.bed = { point, type = 'xray' }`,
  state bag `nzaTr = { m = 'bed', bt = 'xray', b = pointId }`). Without a transport placement the
  client falls back to "patient within `Take.tableRadius` of an xray point".
- Patient options on a patient lying on the table: one **Radiograph this patient** option (order 60,
  perm `Take.perm`; the console picks the body part — no per-view list in the target menu) and
  **Help them down from the table** (order 10). The transport module owns help-off when loaded
  (`NZA.Transport.OwnsHelpOff / HelpOff`); otherwise this module clears `meta.bed`, releases the bed
  point and stands the patient up beside the table (NPC by the medic, players on their own client).
- Table target **Take X-ray**, the patient option and radial **Take X-ray** open the **X-ray
  console** (device face `RX-10 · Radiographic console`, generic model plate + radiation sticker, no
  brand): holographic body figure with a scan sweep and the 8 views, injured views tagged (from the
  medic snapshot), kVp / mAs as 240° dials per view, 1–8 / click, Enter to take.
- Easy mode (`Take.easyAnywhere`): a single **X-ray…** option on any patient opens the console.

### Taking a film (`NZA.Proc 'xray'`)
- The radiographer **steps back** (`Take.stepBack`), an orbit camera frames the table, the
  console HUD shows the collimator light field on the body figure, SID / focus / grid, *door closed
  · room clear*.
- Chest and abdomen: press **B** so the patient holds their breath (`Take.breathWindow` s, only
  for conscious patients) — exposing without it gives a **motion-blurred film**.
- **Hold Space** to expose: prep beeps (rotor up), **X-RAY ON**, full-screen flash + in-world light
  flash (`Take.flash`), then the film runs through the processor and comes out on the console.
- Server: the film item `Config.Items.xray_film` gets the metadata below (film id `A2034`,
  `A2035`, … stored in the server KVP). Player patients get a toast and are billed
  (`Billing.take`).

```lua
metadata = { id, pid, name, sex, age, view, viewLabel, taken, by, hospital, quality = 'sharp'|'motion',
  seed, sev, label, description,
  findings = {
    { id = 'f1', k = 'fx',   inj, region, bone, kind, disp, ang, phi, shift, short, sev, reduced, cast, splint, heal,
      level? rib? site? axis? t?, ap = { x, y }, lat = { x, y }, r, label },
    { id = 'f2', k = 'frag', inj, region, n, depth, shape = 'bullet'|'shard', rot, ap, lat, r, label },
    { id = 'f3', k = 'hemo', side, ml, top, ap, lat, r, label },      -- haemothorax ≥ 150 mL
    { id = 'f4', k = 'ptx',  side, size, tension, ap, lat, r, label }, -- pneumothorax ≥ 5 % or tension
  },
  read = { by, score, grade, at, confirmed } }  -- after a reading
```
Film space: `x 0..1` left → right as the film hangs, `y 0..1` top → bottom; AP films show the
patient's right on the viewer's left, lateral films show anterior on the left. The limb axes in
`server/modules/xray.lua` (`LIMB`) and `app.js` (`LIMB`) are the same numbers.

### The radiographs (NUI renderer)
Drawn on canvas from the film data: soft tissue (fat stripe, lungs carved as air, bowel gas),
bones as unions of parts per bone (cortex, medullary canal, trabecular texture; separate bones add
up like real density), metal fragments pure white with a halo, grain, heel effect, vignette,
burned-in annotation in our own arrangement: a rotated series strip along the left edge (film id,
view, projection, series / image), the lead **R / L** side marker with the projection tag under it,
a calibration ruler bottom-left and a pale photographic **ID flash card** bottom-right (hospital,
patient, id, date, kV / mAs, motion). No brand on the film.
- **Views**: skull & face & C1–C2 (AP / lateral), C-spine C2–T1 with clavicles and trachea, chest
  (ribs, clavicles, scapulae, humeral heads, T-spine, heart & mediastinum, diaphragm, gastric
  bubble / lateral with sternum and kyphotic spine), abdomen (T12–L5 with pedicles and transverse
  processes, bowel gas, psoas, kidneys, pelvis with obturator rings, sacrum, hips / lateral),
  arm (shoulder, humerus, elbow, radius & ulna, 8 carpals, metacarpals, phalanges), leg (hip,
  femur, condyles, patella, tibial plateau, tibia & fibula, ankle, foot).
- **Pathology**: long-bone fractures split at the real position with a jagged fracture line
  (oblique / comminuted fragments), the distal piece angulated by the projected angle
  (`ang × |cos φ|` on AP, `× |sin φ|` on lateral), shifted and overlapped (shortening); open
  fractures with gas in the soft tissue; rib / clavicle / sternum / pubic ramus breaks split their
  band; vertebral compression / wedge fractures with step-off; skull fracture lines; facial and
  pelvic cracks; callus while healing; a plaster sleeve with weave once cast; haemothorax white-out
  with a meniscus; pneumothorax with the visceral pleural line and no lung markings, mediastinal
  shift for tension; bullets / shrapnel with spatter; motion blur.

### Reading on the lightbox (mode `read`)
- Use the film item (`Bridge.Inv.RegisterUsable`) or the lightbox target / radial **Read X-ray
  film** (context menu when you carry several films). Needs a lightbox nearby
  (`Read.requireLightbox`, server-checked against the hospital points) — skipped in easy mode.
- Camera on the lightbox prop (`Read.cameraOffset / cameraDist`), clipboard pose.
- Layout (1080p; 720p scales with the kit zoom): **film jacket** top-left (patient, study,
  radiographer, quality, AP + lateral thumbnails with pin counts) · **lightbox** `LB-2 · Film
  illuminator` left of centre (x 440, light panel, clip, corner-bracket hanging frame) · **report
  window** right of it, kept ≥ 300 px from the right edge so the tool belt never covers it ·
  procedure HUD bottom-left (readout: a *Review* dial that fills until the report opens + an
  instrument list *Lamp* / *Clipped*; step card; a **film pair** widget in `pp.slot` with both
  film thumbnails, their pins and a check once pinned) · tool belt on the right edge.
- Step 1 **Hang a film**: drag a film from the jacket onto the lamp (or **F** clips the AP film).
  Step 2 **Pin every finding**: **2** Pin — click to pin (click a pin to remove it, 8 per film),
  **F** Other film (AP ↔ lateral), **1** Hand (move the film), **3** Angle (draw a line along each
  piece of a displaced break → angle), **L** Lamp on/off (the film is unreadable in the dark),
  **C** Window (soft / bone / bright), scroll zoom (1–4×), **R** recentre, right-drag orbit,
  **N** normal film, **Enter** files the report (after `Read.minTime`), hold **ESC** to cancel.
  Step 3 **File the report**.
- Result: score as a status ring (no letter grade) in the report and on the HUD dial, every
  finding confirmed / seen on one film / missed, stray pins, your measured angle vs the film's, the
  true positions drawn as rings on both films (F still flips).
- Mode `view` (no `Read.perm`, `Read.viewWithoutPerm`): look only, no marking, no lightbox needed.

**Scoring (server)** — pins are matched greedily to findings per film within
`max(finding.r, Read.tolerance)` (film widths; y scaled by 1.25 for the 4:5 film). Each finding:
½ for the AP pin + ½ for the lateral pin, minus up to 35 % for distance. Score =
100 × credit / findings − `Read.falsePin` per unmatched pin (+ `Read.measureBonus` for an angle
within `measureTolerance`); calling **Normal** on an abnormal film scores 0; a normal film scores
100 − 2 × falsePin per pin.

**Diagnosis (server)** — when the score ≥ `Read.confirmScore` (or easy mode), every finding pinned
on BOTH films is confirmed:
- injury: `treat.xray = true`, `treat.xrayMarked = true`, `quality.xray = score`; findings seen on
  one film only get `treat.xray`.
- retained fragments: `injury.xrayMap = { film, view, ap = {x,y}, lat = {x,y}, depth, n, at }`
  (for the bullet module: where the fragment is and how deep).
- `NZA.Findings.Add(pid, 'xray_<injury>', { injury, region, group, source = 'xray', text })`,
  chest: `NZA.Findings.Add(pid, 'haemothorax_suspected_<side>' | 'pneumothorax_suspected_<side>',
  { cond, side, group = 'chest', source = 'xray', text })` → shown in the examination.
- the film remembers the reading (`metadata.read`), a record line is written for player patients.

### Set the bone (`NZA.Proc 'xray_reduce'`, mode `reduce`)
- For displaced limb fractures (`fracture.displaced`, angle > `Reduce.tolerance`) that were read
  on a film (`Reduce.requireXray`) with the patient on a hospital point (`Reduce.requireHospital`)
  — both skipped in easy mode. Optional items `Reduce.items` (e.g. lidocaine).
- **`CA-9 · Mobile C-arm`** monitor (generic device face) with the real fracture (static image + live distal fragment),
  last-image-hold, LIVE indicator, dose timer, angle and shortening read-outs; traction panel with
  a force trace (pain line, out-to-length band), force and pain meters, patient mood.
- 1/3 **Pull it out to length**: grab the lower piece on the screen and pull along the bone; the
  overlap closes once the force is in the band. 2/3 **Correct the angle**: keep traction, move
  sideways (ends grind and hurt if you rotate before they are out to length). 3/3 **Release and
  check**: ease off slowly — letting go fast makes the bone slip back; take a check image, Enter.
  **Hold F** = live fluoro (counts against `Reduce.fluoroBudget`). Too much force → the patient
  screams and pulls away (angle lost, `painOver`); pain relief (`Reduce.analgesia`: morphine,
  lidocaine, painkillers, anaesthetised wound) raises the pain threshold.
- Server: the angle left is clamped to 0..before and floored by the score; `fracture.angle` =
  what is left, `treat.reduced` when ≤ tolerance, `quality.reduced`, pain spike (`Reduce.painSpike`,
  removed after 90 s), bill, record.

### Apply cast (`NZA.Proc 'xray_cast'`, mode `cast`, consumes `Config.Items.cast`)
- Limb fractures that are aligned (not displaced or reduced); open fractures need wound care first
  (`Cast.openNeedsWoundCare`: irrigated / sutured / dressed / bandaged); hospital point unless easy.
- 1/3 **Stockinette and padding** (sweep along the limb), 2/3 **Wrap the plaster** (circle the
  cursor: every full circle lays a turn where you are along the limb; the coverage strip shows
  thin / good / too thick per section, `Cast.layers`), 3/3 **Mould and let it set** (hold Space on
  the break, release in the green band, keep still while it sets — moving cracks the plaster).
- Server: `treat.cast`, `quality.cast`, heal boost `Cast.healBoost × score/100`, removes the
  splint on that limb, leg casts recommend crutches (`Cast.crutches = 'recommend' | 'give'`), bill.
  The core physiology then counts the fracture as treated (held + aligned + closed) and heals it at
  full speed.

### Examination routes (`NZA.ExamRoutes`)
| id | label | shows for | available |
|---|---|---|---|
| `xray_take` | X-ray needed | fracture, gunshot/shrapnel with retained fragments, not yet `xrayMarked` | patient on an X-ray table (or easy mode) — else greyed: *Lay the patient on an X-ray table* / *Read the film again on a lightbox* |
| `xray_reduce` | Set the bone | displaced limb fracture | after X-ray (or easy) — else *X-ray and read the fracture first* |
| `xray_cast` | Apply a cast (`Config.Items.cast`) | limb fracture without cast | aligned — else *Set the bone first* / *Clean and close the open wound first* |

Patient options `nza_xray_reduce` (Set the bone, order 68) and `nza_xray_cast` (Apply cast, order
69) show for patients with a fracture tag; they pick the fracture (context menu if several).

### Radial (`NZA.RadialItems`)
`xray_take` (parent `patient`, a patient on a table within `Radial.range`), `xray_read` (root, near
a lightbox).

---

## Controls

| Where | Keys |
|---|---|
| Console | 1–8 / click the body · Enter take · ESC cancel |
| Expose | B breath hold · hold Space expose · Enter done · hold ESC abort |
| Lightbox | drag film from the jacket · 1 move · 2 mark (click pin / click pin again to remove) · 3 measure · F switch film · L viewer light · C contrast · scroll zoom · R reset · right-drag look · N normal film · Enter submit / done · hold ESC abort |
| Set the bone | LMB drag on the fluoro screen (pull along the bone / sideways) · hold F live fluoro · Enter finish · hold ESC abort |
| Cast | LMB sweep (padding) / circle (plaster) · hold Space mould · Enter next step / finish · hold ESC abort |

NUI keys are configurable in `Config.Xray.keys` (KeyboardEvent.code names).

---

## Config (`Config.Xray`)

| Key | Meaning |
|---|---|
| `Take.perm minTime maxTime easyTime maxDist states` | X-ray procedure |
| `Take.requireTable tableRadius easyAnywhere` | where the patient must lie |
| `Take.stepBack breathHold breathWindow camera flash settings` | exposure scene, console values per view |
| `Take.maxFilms cooldown notifyPatient` | limits, patient toast |
| `Read.perm viewWithoutPerm requireLightbox lightboxDistance` | who reads where |
| `Read.minTime maxTime easyTime cooldown` | reading session |
| `Read.tolerance falsePin confirmScore measureBonus measureTolerance` | scoring & diagnosis |
| `Read.camera cameraOffset cameraDist` | lightbox camera (prop panel centre (0, 0.15, 1.47)) |
| `OffTable.enabled perm getUpAnim` | help off the table fallback |
| `Reduce.perm minTime maxTime easyTime maxDist requireXray requireHospital tolerance regions items analgesia painSpike fluoroBudget` | set the bone |
| `Cast.perm minTime maxTime easyTime maxDist requireHospital regions openNeedsWoundCare layers healBoost removeSplint crutches` | cast |
| `Billing.take read reduce cast` | prices for player patients (0 = free) |
| `Radial.enabled range` | radial entries |
| `filmPrefix filmStart` | film ids |
| `keys` | NUI keys |

Items: `Config.Items.xray_film`, `.cast`, `.crutches` (+ `Reduce.items`). Props:
`Config.Props.xray_table`, `.lightbox`.

---

## Events, callbacks, APIs

| Name | Kind | Notes |
|---|---|---|
| `NZA.Proc 'xray'` | proc | payload `{ view }`, result `{ score, breath }` |
| `NZA.Proc 'xray_reduce'` | proc | payload `{ injury }`, result `{ score, angle, short, slips, painOver, fluoro }` |
| `NZA.Proc 'xray_cast'` | proc | payload `{ injury }`, result `{ score, coverage, layersMin, layersMax, cracks, mould }` |
| `nza:xray:films ()` | callback | films you carry `{ slot, id, view, viewLabel, name, taken, read }` |
| `nza:xray:open (slot)` | callback | reading payload `{ ok, token, mode, easy, easyTime, minTime, tolerance, measureTolerance, film }` |
| `nza:xray:read:finish (token, res)` | callback | `{ ok, outcome = { score, grade, rows, falsePins, msg, applied, offline, measure, easy } }` |
| `nza:xray:offTable (target)` | callback | `{ ok, player, net, transport }` |
| `nza:xray:read` | S→C | reading payload (film item used) |
| `nza:xray:standUp` | S→C | player patient helped off the table (fallback path) |
| `nza:xray:read:cancel (token)` | C→S | reading closed |
| bus `xray:taken (src, p, film)` `xray:read (src, p|nil, film, outcome)` `xray:offTable (src, p)` `xray:reduced (src, p, inj, outcome)` `xray:cast (src, p, inj, outcome)` | server bus | |
| NUI | `xray:choose {view}` `xray:expose {breath}` `xray:finish {...}` `xray:abort` `xray:close` | Lua → `open`, `filmReady`, `result`, `error` |

Server Lua API (`NZA.Xray`): `Findings(p, view)`, `Film(p, view, quality, src)`, `OnTable(p)`,
`NearLightbox(src)`, `OpenFilm(src, slot, item?)`, `UseFilm(src, item)`, `Score(film, res, easy)`,
`Easy(src, perm)`, `Bill(src, p, key, reason)`, `Notify(src, msg, kind)`, `Views`.
Client Lua API (`NZA.Xray`): `Take(entity, target, view)`, `Console(entity, target)`,
`Read(payload)`, `ReadAt()`, `OffTable(entity, target)`, `Reduce(entity, target, injuryId)`,
`Cast(entity, target, injuryId)`, `TablePoint(entity)`, `NearLightbox(range)`, `RunApp(o)`,
`Busy()`, `Flash(entity)`, `EntityOf(snapOrTarget)`.

Easy mode: the X-ray, the reading, setting the bone and the cast are core progress bars; the room,
table, lightbox, X-ray-first and hospital requirements are skipped (only the supplies are needed);
an easy reading confirms every finding with `Config.EasyMode.score`.

---

## Known limits
- Positions on the film are computed by the server from the injury's `spot` (front view) and
  `retainedDepth`; the lateral position of injuries without a depth (skull, ribs) is a stable
  hash of the injury. Rib breaks snap to the nearest drawn rib (within the pin tolerance).
- Without the transport module the client detects "on the table" by distance to the xray point,
  and the server accepts it when the hospital points are loaded.
- The anatomy is a stylised but anatomically laid-out radiograph, not a real image; very exotic
  ped proportions are not reflected.
- The live fluoro shows an AP projection of the right limb layout (left limbs are mirrored for the
  films, not for the C-arm image).
- `Read.requireLightbox` is only enforced server-side when the hospital module's
  `NZA.Hospitals.Points('lightbox')` is available.
