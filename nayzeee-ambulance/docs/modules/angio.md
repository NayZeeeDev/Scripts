# angio — angiography: find and coil internal bleeding

Interventional radiology in a hospital suite: get into an artery, steer a catheter through a
procedurally generated vessel tree under fluoroscopy, find the bleed with contrast runs, plug it
with a coil, confirm it is sealed and close the access site. The X-ray image is drawn **on the
in-world boom monitor** (DUI), with a NUI fallback.

| File | What |
|---|---|
| `server/modules/angio.lua` | `NZA.Proc 'angio'` (start / finish / abort), callback `nza:angio:act`, usable kit, records, billing |
| `client/modules/angio.lua` | point type `angio` (the suite), patient option, exam route, radial entry, usable item, `NZA.Angio.Start` |
| `client/modules/angio_proc.lua` | the runner: NUI, DUI monitor, cameras, room mode + red button, injector, needle prop, speech |
| `config/modules/angio.lua` | `Config.Angio` |
| `locales/en/angio.lua` | `angio.*` (Lua + every NUI string, `angio.screen.*` for the monitor) |
| `html/apps/angio/app.js` `app.css` | `window.NZAAngio` (anatomy, contrast physics, fluoroscopy renderer) + the NUI app `angio` |
| `html/apps/angio/screen.html` `screen.js` | the DUI page on the monitor (`screen.html?demo=1` shows a demo run) |

## The procedure (6 steps)

1. **Access** — a planning card shows the suspected source (from the injury) on a body map and
   recommends a way in (right femoral as standard, the other groin for a pelvic bleed so you cross
   over the iliac fork, same-side antegrade for a thigh bleed). Pick `1` right femoral, `2` left
   femoral or `3` right radial (also clickable). Ultrasound-guided puncture: transverse and
   longitudinal views, aim over the pulsing artery (`A`/`D`, only near the skin), set the angle
   (`Q`/`E` or wheel) to **45°**, hold `W` (`Shift` faster, `S` back) until flashback. The vein gives
   dark venous blood, too deep goes through the back wall (attempt counted, patient says "Ow!").
   Hold still → feed the wire (`W`, it fights you when the needle is too steep), slide the sheath
   (`E`), then **"Remove the needle — the port stays in"**: tap `R` until 100 %.
2. **Navigate** — fluoroscopy of the abdomen / pelvis (spine with levels, pelvis, bowel gas, colon).
   The vessel tree (aorta → coeliac / SMA / IMA → jejunal & ileal arcades, colic branches, renal
   segments, lumbar, common / external / internal iliac with gluteal, obturator, pudendal branches,
   femoral, profunda, perforators) is invisible until contrast. `W`/`S` (or wheel) advance /
   withdraw, `A`/`D` rotate the shaped tip; at a bifurcation the branch the tip points at is taken.
   The tip compass shows the next branch, its distance and which way the tip points. `X` = test puff
   (3 mL, local), `C` = contrast run. The last run stays as a faint **road-map**. `Q`/`E` or the
   console slider / segmented control rotate the C-arm (AP, LAO, RAO), `M` magnifies (field 30 → 19 cm).
   Narrow vessels block the catheter, forcing it causes spasm.
3. **Contrast run** — once in the right first-order vessel, press the big red button in the room
   (`Z` → walk to the pedestal → `E`) or `C`. The injector plunger moves ("Dye going in. Watch the
   screen."), the camera shows the injector for `injectorShot` s, then the monitor: DSA subtraction,
   vessels fill in flow order, organ blush, and a **BLEED** blush at the injury's vessel.
   A run that does not reach the bleed costs points; flush runs from the aorta map everything.
4. **Coil it** — bring the tip within `coilDist` cm of the bleed (`TO BLEED` stat), hold `F` to push
   the coil out (visible spring on the image), `F` to release, `R` to pull back. A coil too far or off
   the bleeding branch lets collaterals refill it.
5. **Confirm run** — run again: no blush = sealed, otherwise another coil (extra coils come out of
   the inventory).
6. **Close the access** — tap `R` to pull the sheath (it bleeds), hold `Space` to press on the
   puncture keeping the pressure in the band (too hard stops the pulse) for `holdTime` s.

Result card: grade S–F + six part scores (access angle / attempts, navigation, contrast used,
dose, coil placement, haemostasis). `Enter` saves. Outcome (server): `injury.treat.coiled = true`,
bleed 0, `quality.coiled = score`, internal injuries → `treated` + `healBoost`; bleeding fractures
keep the fracture (`bleedBase = 0`, still needs splint / binder). Record line + bill (`price`).

Easy mode (department flag): the standard proc progress bar, only the supplies are needed — no
suite / table check (ARCHITECTURE easy rule).

## The suite — point type `angio`

Place ONE point with the builder: the **table** (`Config.Angio.suite.table`, default
`Config.Props.xray_table`; `false` for MLO tables → a sphere target at the point). On spawn the
module puts the boom **monitor**, the **injector tray** and the **red button pedestal** around it
with `Config.Angio.suite.layout` (table space: +X operator side, +Y head end, metres; heading
relative to the table), matching the props' documented origins (`tools/props/props/radiology.py`).
Per point: `point.data.layout = { monitor = { pos = {x,y,z}, h = 270 } | false, ... }`.
The type def exposes `parts` (for builder ghosts) and `lie`; `data.lie = { x, y, z }` (table top,
0.825 m) is what the transport module uses to lay the patient on the table, which then sets
`patient.meta.bed = { point, type = 'angio' }`. Target on the table: "Start angiography".
Native fallbacks are used when a custom model is missing (then no DUI: the overlay draws the image).

## Entry points

- Patient option `nza_angio` "Angiography" (order 60, perm `angio`, alive / wounded) when the
  patient has an internal or fracture tag and lies on an angio table (or easy mode / `requireSuite = false`).
- Examination → Injuries to treat: `NZA.ExamRoutes` id `angio` for `internal` (organs in
  `Config.Angio.organs`) and bleeding fractures of `Config.Angio.fractures`; greyed with
  "Needs the angiography suite" until `snap.meta.bed.type == 'angio'` (not in easy mode). Items shown:
  angio kit, contrast, coil.
- Radial (EMS job menu → Patient): `angio_start`, near a table with a patient on it.
- Using `Config.Items.angio_kit` (server checks the permission) → nearest patient (table first).

## Controls

| Step | Keys |
|---|---|
| 1 choose | `1` `2` `3` (or click) · right-drag look around (in game) |
| 1 needle | `A`/`D` aim · `Q`/`E` / wheel angle · `W`/`S` needle (`Shift` faster) · `W` wire · `E` sheath · `R` tap needle out |
| 2–5 | `W`/`S` / wheel advance · `A`/`D` turn tip · `Q`/`E` C-arm · `M` magnify · `X` puff · `C` run · `F` coil (hold) / release · `R` pull back · `B` new bottle · `V` monitor / screen (DUI) · `Z` room |
| room | walk · `E` red button (within `buttonDistance`) · `Z` back to the monitor |
| 6 | `R` tap sheath out · hold `Space` pressure |
| any | hold `ESC` abort · `Enter` finish |

## Config (`Config.Angio`)

`perm minTime maxTime easyTime maxDist items consume organs fractures minFractureBleed requireSuite`
· gameplay `contrastPerItem runMl selectiveMl puffMl coilDist maxCoils holdTime catheterSpeed
parContrast parFluoro` · result `price healBoost` · entry points `interact radial usable tableRange
speech` · `suite { table ground layout operator lie screen plunger injectorCam overviewCam }` ·
`injectorShot injectorShotOnKey` · `dui { enabled width height linger }` · `access { femoral_r
femoral_l radial = { bone, offset, needle { pos, rot } } } accessCam needleProp` · `anims { work
press hold }` · `keys { roomBack press pressLabel } buttonDistance`.

## Server

```lua
NZA.Proc.Register('angio', { perm, items = fn, maxDist, minTime, maxTime, consume, easyTime, onStart, onFinish, onAbort })
-- onStart: picks payload.injury (or the worst eligible bleed), checks meta.bed (not in easy), returns
--   { injury, bleed = { key, side }, seed, caseId, point, patient, budget, bottles, coils, maxCoils, coilDist,
--     holdTime, runMl, selectiveMl, puffMl, catheterSpeed, parContrast, parFluoro, easy }
-- onFinish: verifies the session log (≥ 2 full runs, a coil within coilDist on the bleeding path, the last
--   run after the last coil without blush), clamps / caps the score, applies the outcome, bills, records.
lib.callback 'nza:angio:act' (act, info) → { ok, left, bottles?, err?, msg? }
--   'run' | 'puff' (uses dye from the session budget), 'refill' (takes a contrast bottle now),
--   'coil' { dist, onPath } (coils after the first are taken now). Rate limited, distance checked.
NZA.Angio.Eligible(injury) → bool      NZA.Angio.Target(patient, injury) → bleedKey, side
```
Bus: `angio:done (src, patient, injury, outcome)`. Net event S→C `nza:angio:use`.

## Client / NUI

`NZA.Angio.Start(entity?, target?, injuryId?)` (blocking), `Suite(id)`, `SuiteNear(coords, r)`,
`PatientOnTable(suite)`, `ToWorld(suite, vec3)`, `Eligible(inj)`, `Runner(ctx)`.
NUI app `angio` — open data `{ data = proc data, locale = NZA.LocaleTable('angio'), dui, hasButton }`;
actions in: `vitals`, `room { on }`, `pressed`, `flash { type, text }`, `anchors` (`button`, `injector`);
callbacks out: `angio:step { phase, step, cam, access, view }`, `angio:screen { state }` (~20 Hz → DUI),
`angio:run { kind, selective, blush, fromButton }` → `{ ok, left, delay }`, `angio:refill`, `angio:coil
{ dist, onPath }`, `angio:room { on }`, `angio:view { mode }`, `angio:say { line }`, `angio:finish
{ result }`, `angio:abort`. DUI page messages: `{ type = 'state' | 'standby' | 'locale' }`.
Preview: `html/index.html?app=angio&step=choose|aim|needle|nav|run|coil|confirm|pull|press|done`.

## Known limits

- The scene is deterministic from the server seed, so client and DUI draw the same anatomy; the
  server checks the run / coil log and timing, but the catheter simulation itself runs on the client.
- One DUI browser per client (all angio monitors in view show the same live image while you work;
  it falls back to the model's own screen `linger` s after the procedure).
- The plunger animates only when `Config.Props.injector_plunger` exists (request in
  `docs/requests/angio.md`); otherwise an "Injecting N mL" world label shows on the injector.
- Bone offsets for the access close-up / needle prop are tuned for the freemode peds' bone axes and
  may need small config tweaks for unusual ped models.
