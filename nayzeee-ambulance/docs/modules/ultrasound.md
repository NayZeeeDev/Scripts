# Ultrasound module — eFAST scan, treatment plan, chest drain, needle decompression, pericardiocentesis

Owner files

| File | What |
|---|---|
| `server/modules/ultrasound.lua` | truth per eFAST window, grading, treatment plan, the four procedures, usable items, billing, findings |
| `client/modules/ultrasound.lua` | runners, NUI bridge, point type, patient options, examination routes, radial entries, usable-item event |
| `client/modules/ultrasound_world.lua` | in-world side: torso frame from bones, anchor grid, camera, medic pose + arm IK, probe / syringe props, cart DUI |
| `config/modules/ultrasound.lua` | `Config.Ultrasound` |
| `locales/en/ultrasound.lua` | every string (Lua + NUI), keys `ultrasound.*` |
| `html/apps/ultrasound/app.js` · `app.css` | NUI app `ultrasound` (imaging engine, device face, plan, 4 modes, preview) |
| `html/apps/ultrasound/screen.html` · `screen.js` · `screen.css` | cart monitor DUI page (mirrors the live picture on the cart prop) |

## Features

### eFAST scan (`mode = 'scan'`)
- **Live B-mode imaging engine** (`window.NZUS`, app.js part 1): 136 scan lines × 240 samples per frame,
  Rayleigh speckle from a coherent complex field with an anisotropic PSF, ray-marched attenuation (rib /
  bowel-gas acoustic shadows, posterior enhancement behind fluid), TGC, log compression, focal zone,
  frame persistence, lateral beam blur, depth / gain / focus. All in centimetres on a curved-array sector.
- **Six windows with real anatomy**, each reacting to probe position, marker rotation and tilt:
  RUQ (liver, kidney, diaphragm, Morison's pouch; haemoperitoneum as a black stripe; haemothorax as black
  above the diaphragm with the spine sign), LUQ (spleen, kidney, splenorenal recess), PELVIS (bladder,
  prostate / uterus, free fluid in the corners), CARDIAC subxiphoid (four beating chambers through the liver
  window, pericardial effusion ring, RV diastolic collapse in tamponade, standstill in arrest), LUNG R / L
  (rib shadows, pleural line sliding, A-lines; M-mode seashore vs barcode for pneumothorax). Off-window
  probe positions show bowel gas, probe in the air shows lens reverberation.
- **Probe control in the world**: the mouse slides the probe over a 5×5 anchor grid projected from the
  patient's torso (`NZA.Anchors`), wheel turns the marker, Q/E tilt; the in-world probe prop follows on the
  skin (networked), the medic's right arm reaches for it (IK). Image quality depends on distance to the
  window, marker angle and tilt; hints tell the medic what to fix.
- **Device face** (our own industrial design, generic `POCUS-7` / `C1-6` labels, no brand): sector image,
  depth scale + focus marker, TGC curve, anatomy labels (configurable), 3D probe orientation view,
  holographic torso map with the six window nodes (click to call), ECG trace + HR, acquisition readouts,
  hardware keys with rocker switches, FREEZE, M-mode sweep, calipers on a frozen image (`D1 4.5 cm`).
- **Calls & grading**: P / N call the current window positive / clear. The server keeps the truth and grades
  at the finish: correct (full credit needs `minSeen` seconds of a clear image), guess, missed, false call;
  a caliper measurement within 25 % (min 4 mm) of the true thickness gives a bonus.
- **Treatment plan** (top-left card, vertical spine): built live from the medic's own calls, in order —
  control bleeding → release trapped air → chest drain right / left → drain around the heart → find and seal
  the bleeding vessel (angiography) → remove retained fragments — each with item chips (have / need) and a
  `Do it now` button that hands straight over to the chest drain / decompression / pericardiocentesis
  procedure. After grading it is rebuilt from the server's full read and steps the medic missed are flagged.
  "Scan again after each step: problems you fixed drop off the screen."
- **Findings** (`NZA.Findings.Add`, guarded): `haemothorax_suspected_<side>`, `pneumothorax_suspected_<side>`,
  `tamponade_suspected`, `us_internal_<injuryId>` — the examination then shows them and offers the routes below.
- **Cart monitor DUI**: while scanning next to a cart, `screen.html` runs the same engine on the cart's screen
  texture (`Config.PropScreens.us_cart`) so people around the bed watch the scan (window, quality bars, HR,
  rhythm, ECG, SpO₂, NIBP, depth / gain / focus, M-mode strip, needle depth during pericardiocentesis).

### Pericardiocentesis (`mode = 'pericardio'`)
Probe under the breastbone until the effusion ring is clear (hold-quality meter) → F puts the needle in beside
it → mouse aims toward the left shoulder (dotted guide on the image), LMB advances, the needle echo, bevel
and reverberation tail show on the live image and a NEEDLE PATH gauge shows tip vs sac vs heart wall →
blood flash in the hub → hold F to draw (syringe widget, 60 mL, T empties it into the bowl) → the sac shrinks,
the heart comes closer, RMB eases back → touching the myocardium triggers ectopics on the ECG, a voice line
and a server-side VF chance → pull out. Vitals recover on screen while the sac empties.

### Chest drain (`mode = 'chestdrain'`, full-screen 3D close-up on `NZA3D`)
1. **Find the spot** — palpate with a nitrile-gloved hand (ribs and spaces light up in a palpation lens and
   are counted under the fingers), mark the 5th space in the mid-axillary line with a skin marker; the safe
   triangle is shown after the mark.
2. **Clean the skin** — scrub iodine until the area is covered; a fenestrated spun-bond drape (fibre texture,
   bond points, adhesive window film) drops over the field.
3. **Numb** (when the medic carries `Config.Items.lidocaine`) — bleb of lidocaine rises under the needle; N skips it (pain, flinches, lower score).
4. **Cut along the rib** — scalpel drag on the upper border of the rib below the mark, 2–3 cm, deviation scored.
5. **Through the chest wall** — curved artery clamp (Roberts pattern: curved serrated jaws, box joint,
   ratchet, rings) pushed into the cut until it pops; Space spreads the jaws ×3; dark blood wells up (haemothorax) or air hisses.
6. **Finger sweep** — gloved finger in the hole, circle to clear the track.
7. **Feed the tube** — 28 Fr clear PVC tube with blue radio-opaque line and depth marks; drag toward the head,
   clamp at 10–14 cm (side holes inside); the tube runs over the drape and off the bed with the drain tubing.
8. **Connect the drain** — 3-chamber drain unit widget: collection chamber fills (rolling counter), water seal
   bubbles while air leaks, suction column, lung-open ring; blood runs through the tube into the drain line.

### Needle decompression (`mode = 'decompress'`)
Palpate the collarbone, count down to the 2nd space in the mid-clavicular line, mark it, push the 14 G orange
cannula over the top of the 3rd rib until the hiss; the needle comes out and the catheter stays in place.

### Easy mode
`NZA.Easy(perm)` / `NZA.Staff.Easy`: no room / location requirement, only the supplies; procedures run as the
core progress bar. The easy scan then opens the device in review mode with the server's full read and plan.

## Where it works (server-checked, `NZA.Ultrasound.Location`)

| Procedure | Allowed when |
|---|---|
| scan | patient on an `ultrasound` point bed, within `Scan.cartRange` of a cart point, in the ambulance bay (`patient.meta.bay`, `Scan.bay`), `Scan.field`, or easy mode |
| chest drain / pericardiocentesis | `patient.meta.bed.type` in the section's `rooms`, near a cart (`rooms.ultrasound`), in the bay (`bay`), `field`, or easy mode |
| decompression | anywhere |

## Controls

| Mode | Input |
|---|---|
| scan | Mouse slide probe · Wheel turn marker · Q / E tilt · ↑ / ↓ depth · ← / → gain · Space freeze · C calipers (click two edges) · M B / M-mode · P positive · N clear · Enter finish · RMB look around · Esc (hold) put the probe down |
| pericardio | Mouse probe / needle angle · F needle in / hold to draw · LMB advance · RMB pull back · T empty syringe · Esc (hold) stop |
| chest drain | 1–9 tools · LMB use · Space spread clamp · Enter clamp the tube · N skip numbing · RMB look · Wheel zoom · R recentre · Esc (hold) stop |
| decompress | 1 palpate · 2 marker · LMB push · RMB look · Wheel zoom |

## Config keys (`Config.Ultrasound`)

`Scan` { perm, items, minTime, maxTime, easyTime, maxDist, cartRange, bay, field, minSeen, labels, findings, fee,
visible { freeFluid, haemothorax, tamponade, pneumothorax } } ·
`ChestDrain` { perm, items, consume, minTime, maxTime, easyTime, maxDist, rooms, bay, field, minScore, drainNow, price, numbing, quality } ·
`Decompress` { perm, items, consume, minTime, maxTime, easyTime, maxDist, minScore, price } ·
`Pericardio` { perm, items, consume, minTime, maxTime, easyTime, maxDist, rooms, bay, field, syringe, drawRate, maxDrawRate, leftOver, slowBleed, touchVf, maxVf, price } ·
`Cart` { lie, dui, duiSize } · `Probe` { networked, rate, lift } · `Camera` { scan, pericardio, drain, decompress } ·
`Torso` { width, depth, pubis, collar, front, frontTop } · `Anim` { stand, kneel, lowPatient, ik } ·
`Interact` { enabled, distance, needItems, orderScan, orderDrain, orderPeri, orderDecomp } ·
`examRoutes`, `radial`, `speech`, `askSide`, `maxDist`, `usable`, `useRange`, `keys`.
Items are `Config.Items` keys (`chest_drain_kit`, `decomp_needle`, `iv_kit`, `lidocaine`); props `Config.Props.us_cart`, `us_probe`, `syringe`.

## Registrations

- `NZA.Proc.Register`: `ultrasound` (perm `Scan.perm`), `chestdrain` (perm `ChestDrain.perm`, payload `{ side }`),
  `decompress` (perm `Decompress.perm`, payload `{ side }`), `pericardio` (perm `Pericardio.perm`).
- `NZA.Points.RegisterType('ultrasound', …)` — `Config.Props.us_cart`, target "Scan the patient (eFAST)" on the patient lying next to the cart.
- `NZA.Interact.Add`: `nza_us_scan` (60), `nza_us_drain` (62), `nza_us_peri` (63), `nza_us_decomp` (34).
- `NZA.ExamRoutes`: `us_drain` (haemothorax / pneumothorax), `us_decomp` (pneumothorax), `us_peri` (tamponade), `us_scan` (penetrating / severe blunt torso wounds, internal bleeds).
- `NZA.RadialItems` (parent `patient`): `us_scan`, `us_decomp`.
- `Bridge.Inv.RegisterUsable`: `Config.Items.chest_drain_kit`, `Config.Items.decomp_needle` → client event `nza:us:use`.

## Events, callbacks, API

- Server Lua API: `NZA.Ultrasound.Truth(p) → truth, render` · `NZA.Ultrasound.Location(src, p, section, easy) → ok, where | false, err` · `NZA.Ultrasound.BasePlan(p) → steps` · `NZA.Ultrasound.Windows`.
- Server bus: `ultrasound:scan (src, p, outcome)`, `ultrasound:drain`, `ultrasound:decompress`, `ultrasound:pericardio`.
- Patient meta written: `efast = { at, by, pos = { [window] = true }, score }`. Conditions changed: `haemothorax` (drained), `pneumothorax` (cleared / tension released), `tamponade` (drawn off), `arrest` (VF on heart puncture). Devices: `chestDrain[side] = true`.
- Net event S→C `nza:us:use (kind)`.
- Client API: `NZA.Ultrasound.Scan(entity, target)`, `.Pericardio(entity, target)`, `.ChestDrain(entity, target, side?)`, `.Decompress(entity, target, side?)` (all block — call from a thread), `.Busy()`, `.CanHere(section, ped, perm)`, `.Nearest(range?, filter?)`; `NZA.Ultrasound.World.*` (see the header of `ultrasound_world.lua`).
- NUI callbacks: `ultrasound:probe`, `ultrasound:needle`, `ultrasound:finish`, `ultrasound:launch`, `ultrasound:flinch`, `ultrasound:abort`, `ultrasound:close` (core). NUI actions: `open`, `vitals`, `result`, `abort`, `anchors` (core). A refused launch comes back in the `ultrasound:launch` reply `{ ok = false, msg }`.
- DUI messages (`screen.html`): `init`, `probe`, `needle`, `vitals`, `freeze`.

## Security

Server authoritative: permission, distance and location per procedure; scores clamped by the core; `minTime`
per procedure; the scan truth never leaves the server before the finish (the client only gets image
parameters); claimed pericardial draw is capped by `elapsed × maxDrawRate` and by what is really there;
heart touches clamped; billing and item use on the server; usable items rate-limited and perm-checked.

## Preview

`html/index.html?app=ultrasound&mode=scan|pericardio|chestdrain|decompress` (stand-in WebGL torso for the
imaging modes), `html/apps/ultrasound/screen.html?demo=1[&win=ruq|cardiac|lung_l|pelvis]` for the cart screen.

## Known limits

- The image parameters for each window are sent at the start of a scan (they are needed to draw it); a
  modified client could read them, but grading and every effect stay on the server.
- The cart DUI needs the streamed `nz_amb_us_cart` model (its screen texture); with the native fallback model
  there is no screen to replace and the DUI is skipped.
- The 3D close-ups need WebGL in the NUI; without it a hold-to-progress fallback runs (lower score).
- Arm IK only nudges the right hand toward the probe; it is not a full reach animation.
