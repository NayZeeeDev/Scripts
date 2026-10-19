# Module: intubation — airway care (BVM, suction, video laryngoscope intubation)

Medics with the `airway` permission ventilate apnoeic / overdosed patients with a bag-valve
mask and secure the airway with a video laryngoscope and a cuffed tube. The whole procedure is
an 8-step minigame on the NAYZEEE procedure HUD with a live, shader-rendered airway on the
laryngoscope screen; easy mode is a progress bar with the same props and camera phases.

| File | What |
|---|---|
| `config/modules/intubation.lua` | `Config.Intubation` (permission, menus, minigame tuning, difficulty, soiling, outcome rates, BVM round, prices, usable items, props, animation, camera) |
| `server/modules/intubation.lua` | procedures `intubate` / `bvm`, treatments `tube_check` / `tube_adjust` / `extubate`, airway tick, usable items, exports |
| `client/modules/intubation.lua` | `NZA.Intubation` runner, NUI glue, patient options, exam routes, radial items, usable-item event |
| `client/modules/intubation_scene.lua` | world scene (medic pose, props on the face / in the hands / on the ground, camera per phase, anchors), world tubes |
| `locales/en/intubation.lua` | every string (`intubation.*`), the NUI part generated from the app's fallbacks |
| `html/apps/intubation/` | NUI app `intubation` |

## Gameplay

**Ventilate (BVM)** — a round of `bvm.breaths` breaths. Squeeze with `Space` for about a second,
one breath every `cadence` seconds. The cadence ring shows the breath window, a hold arc shows the
squeeze length, the bag illustration compresses and the reservoir refills. Too long / too early
squeezes push air into the stomach (remembered on the patient → vomit in the airway on a later
intubation). Through an existing tube the card switches to *Bag on the tube* and the capnograph
shows whether air goes where it should.

**Intubate** — 8 steps, apnoea timer and SpO₂ falling as soon as the mask comes off:

1. **Pre-oxygenate** — rhythm-judged breaths fill the oxygen reserve (dial) and raise SpO₂.
2. **Position the head** — drag forehead / chin on the sagittal cut-away (or `W/S`, `A/D`), towel `T`;
   align the oral / pharyngeal / laryngeal axes. A neck injury (collar, cervical spine) forbids tilt:
   in-line stabilisation and jaw thrust only.
3. **Suction** — when the airway is soiled (blood from face / neck wounds, vomit after an overdose
   or a full stomach, water and froth after drowning) hold the click and sweep the suction tip on the
   laryngoscope screen; blood keeps running back from active bleeding. Clear airways skip it.
4. **Insert the blade** — drag to advance the video laryngoscope over the tongue and steer midline;
   stop with the tip in the vallecula (depth gauge + blade cut-away card top-left).
5. **Lift** — lift along the handle (up and away). Rocking back levers on the teeth (penalty, flash).
   Cormack–Lehane grade live on the screen and on the dial; hold `E` for BURP.
6. **Pass the tube** — aim between the cords and hold the click to push, right click pulls back; hitting
   the epiglottis / arytenoids / cords gives resistance. Misaimed tubes can slide into the oesophagus.
   Stop at the depth mark (23 cm men / 21 cm women by default).
7. **Inflate the cuff** — 10 ml syringe and pilot balloon, manometer with the 20–30 cmH₂O band; each
   patient needs a different volume (`cuffMl`).
8. **Confirm & secure** — squeeze through the tube and watch the capnograph (waveform only when the
   tube is tracheal), listen right / left / over the stomach, adjust depth `W/S`, `F` secures,
   `X` pulls a tube you do not trust (correct call for an oesophageal tube).

Attempts: SpO₂ under `abortSpo2` during an attempt → abort `B` and re-oxygenate; under `crashSpo2`
the attempt is abandoned for you. After `attempts` attempts it is a failed airway. Every result is
scored (pre-oxygenation, position, suction, view vs. best view, teeth, passes, depth, cuff,
confirmation, desaturation) into a 0–100 score and a grade card.

**Outcome** (server): tracheal tube → `devices.intubated = true`, `meta.tube = { placed = 'trachea',
size, depth, expected, mainstem, cuff, leak, capno, at, by, ventUntil }`, airway condition cleared,
ventilated for `ventilateAfter` s (core: rr = `ventRate`, SpO₂ +4, breathing normal), hypoxia relieved
every tick. A tube in the oesophagus is also "intubated" (the medic believes it is in) but the
hypoxia condition grows by `misplacedRate`/min until somebody checks the tube (*Check tube position*
finds it and records the finding `tube_oesophageal`, cond `hypoxia`) and pulls it. Too deep
(mainstem) adds `mainstemRate`/min until *Correct tube depth*. Patients back to `alive` are
extubated (`extubateOnWake`). The ETT prop is shown at the mouth of every intubated patient for
everyone within `worldRange`.

## NUI app `intubation`

Layout (NAYZEEE HUD, nothing in the bottom-centre): procedure column bottom-left (core ProcPanel
with an `Airway` eyebrow tag, `Airway · attempt n of N` during an attempt: apnoea clock, O₂ reserve
(good breaths during pre-oxygenation), attempts n/N, a dial per step; SpO₂ with its trend arrow is
added to the panel only when the monitor is off), tool belt on the right edge (the active tool shows
its action: SQUEEZE / LOOK / SWEEP / PASS / FILL / SECURE),
airway monitor device top-right (generic `AM-7` face: SpO₂ dial with the alarm limit, ECG / pleth /
CO₂ sweep traces, HR / NIBP / EtCO₂ / RR list, apnoea ring timer, attempt pips, lowest SpO₂, status
pill VENTILATING / APNOEIC / SAT FALLING / LOW SpO₂), blade cut-away top-left (steps 4–6), video
laryngoscope device in the centre (`VL-3`, see below), cards right-middle (ventilation ring with an
animated bag / reservoir / valve / mask, head position cut-away, cuff panel, capnograph + auscultation,
result). A diamond marker with a cadence chip floats on the bag in the world (anchor `bvm`). Compact
rules for screens ≤ 820 px high (checked at 1280×720).

**Video laryngoscope render** (one full-screen WebGL fragment shader, 2D fallback without WebGL):
- every layer carries a distance from the lens; the only light is the LED beside the lens, so
  brightness falls off with the square of the distance (the larynx is a dark hole at the start of the
  insertion and lights up as the blade closes in), with camera auto-exposure (gain drops while the
  tongue and palate fill the frame), a soft sensor shoulder, vignette, barrel distortion and noise;
- wet mucosa: blotchy perfusion, two-scale capillary networks, subsurface red where tissue faces
  away from the light, height-field normals with sharp wet highlights;
- anatomy: tongue (papillae), soft palate + uvula, lingual tonsil / tongue base arch, two vallecula
  pockets either side of the median fold, a rounded epiglottis leaf with a rolled translucent free
  edge that casts a shadow on the inlet, aryepiglottic folds, piriform fossae, false folds, ventricle,
  pearly true cords with a capillary along the edge, tracheal rings in the dark, arytenoid complex,
  postcricoid mucosa and the oesophageal inlet;
- fluid (blood / vomit / water by patient): a mask texture whose alpha is coverage and red channel
  thickness — a wet film creeping up the walls, rivulets that run down into the posterior pool and
  drops still hanging, a dark glossy pool with a moving meniscus; water and secretions are
  see-through; froth for drowning; saliva bubbles cluster at the posterior commissure and ride the
  pool margin; active bleeding keeps adding rivulets; the suction tip clears the mask;
- the tube is a translucent PVC cylinder shaded across its width, radio-opaque blue line, printed
  depth marks, balloon cuff (wrinkled / taut), pilot line, bevel with the dark lumen and the Murphy
  eye; the part past the cords (or into the oesophageal inlet) fades into the dark.

**Cuff panel**: a physical 10 ml syringe (cylindrical barrel, printed scale, rubber stopper, rod and
flange that travel with the volume) on the pilot valve and balloon (grows with pressure), the
manometer with the 20–30 cmH₂O band, and a live tracheal cross-section (cartilage horseshoe,
membranous wall, mucosa, tube, cuff): the balloon grows until it meets the wall, air bubbles leak
past it while it is under-filled, and above the band the mucosa blanches (flow *reduced*), with a
three-line readout (cuff to wall, mucosal flow, air past the cuff).

| Lua → JS | data |
|---|---|
| `open` | `{ mode = 'intubate'|'bvm', patient{name,sex,age}, vitals{hr,sys,dia,map,spo2,rr,temp,rhythm}, anat{grade, soil, soilKind, bleed, cspine, tube, depth, cuffMl, open, gx, gy, aryt, tongue, ant, desat, safe, apnoeic, gastric, intubated, misplaced}, cfg{attempts, cadence, squeeze, preoxBreaths, abortSpo2, crashSpo2, cuffBand, breaths}, locale, monitor = bool }` |
| `vitals` | live `{ hr, sys, dia, map, temp, rhythm }` from `NZA.Patient.Watch` |
| `anchors` (core) | `bvm`, `mouth` |

| JS → Lua callback | data |
|---|---|
| `intubation:step` | `{ step, phase = preox|position|suction|insert|lift|tube|cuff|confirm|reox|bvm|done, placed? }` → scene |
| `intubation:finish` | `{ result }` — intubate: `score placed failed depth cuff cuffMl leak capno ventilated listened attempts cl teeth firstPass hits lowSpo2 endSpo2 suction positioned preox gastric detected elapsed`; bvm: `score breaths good quality gastric lowSpo2 endSpo2 capno intubated ineffective elapsed` |
| `intubation:abort` | `{}` (ESC hold; after the result card it submits the result instead) |

Preview: `html/index.html?app=intubation` (`&step=1..8`, `&mode=bvm`); `NZA.apps.intubation.dev`
has `goto(step)`, `breaths(n, opts)`, `set(fn)`, `state()`.

## Controls

`Space` squeeze / inflate · drag on the screen (advance, steer, lift, aim) · click hold push / suction ·
right click pull back / deflate · `W/S` `A/D` fine control · `T` towel · `E` BURP · `3`/`Q` suction during
laryngoscopy · `B` abort attempt · `F` secure · `X` pull tube · `Enter` next / confirm · `1–6` tool info ·
`ESC` (hold) cancel.

## Menus

- Patient options: *Ventilate (BVM)* (order 31), *Intubate* (61), *Check tube position*, *Correct tube
  depth*, *Remove the tube* (confirm dialog) — the last three only when the state bag says `intub`.
- Examination routes: `airway_intubate` (airway / hypoxia conditions, severe face / neck wounds; kit +
  BVM listed), `airway_bvm` (airway / hypoxia), `airway_retube` (the `tube_oesophageal` finding:
  pulls the tube and starts a new intubation).
- Radial (dispatch module): Patient ▸ *Ventilate*, Patient ▸ *Intubate* (nearest eligible patient).
- Usable items: `Config.Items.intubation_kit` / `Config.Items.bvm` start on the nearest patient within
  `useRange`.

## Server

```lua
NZA.Proc 'intubate'   perm Config.Intubation.perm, items { [Config.Items.intubation_kit] = 1 } (+ BVM carried, not consumed)
NZA.Proc 'bvm'        perm Config.Intubation.bvm.perm, BVM carried (not consumed)
NZA.Treat 'tube_check' | 'tube_adjust' | 'extubate'
NZA.Intubation.Tube(p) → meta.tube | nil
NZA.Intubation.Extubate(p, reason) → bool
NZA.Intubation.Ventilate(p, seconds) → bool        -- keep a tracheal tube ventilated (e.g. a ventilator)
exports: IsIntubated(src|pid) → bool, placed       VentilatePatient(src|pid, seconds) → bool
bus: intubation:done (src, p, outcome), intubation:extubated (p, reason)
```

Security: everything goes through `NZA.Proc` / `NZA.Treat` (permission, distance, state, items, rate,
`minTime`); the server builds the anatomy, keeps the start data in the session, clamps every number of
the client result (depth 0–32, cuff 0–80, attempts ≤ config, lowest SpO₂ 35–100, enums for placement
and CL grade), caps the score for oesophageal (≤ 20) and failed (≤ 15) results. Easy mode: correct
tube, 25 cmH₂O, first pass. Billing once per 5 min per medic + patient + kind (`price`).

Hypoxia model: `conditions.hypoxia.smoke` is used as the generic "oxygen debt" the core already turns
into lower SpO₂; this module tracks its own share in `hypoxia.tube` so ventilation never clears what an
oesophageal tube is still causing.

## Config keys

`perm maxDistance requireBvm consumeKit requireDown downAvpu allowSelf interact{enabled,distance,orderBvm,orderTube}
examRoute radial radialRange minTime maxTime easyTime attempts tube depth cadence squeeze preoxBreaths abortSpo2
crashSpo2 cuffBand cuffMl difficulty{weights,faceTrauma,swelling,cspine,keep} soil{faceBleed,overdose,drowning,
gastricLimit,base} safeApnoea{healthy,sick} hypoxiaRelief clearAirway misplacedRate misplacedStart mainstemRate
attemptInsult extubateOnWake ventilateAfter bedVentilator ventRate tick check{enabled,cooldown}
bvm{enabled,perm,breaths,minTime,maxTime,easyTime,ventilate,relief,gastricKeep,states} price{intubate,bvm,check,extubate}
usable{intubation_kit,bvm} useRange worldTube worldRange networkProps externalMonitor monitorProp
props{bvm,bvmEtt,ett,laryngoscope,tubeHand,syringe,suction,monitor} anim{kneel,stand,headOffset,bedHeight}
camera{enabled,preox,scope,confirm,bvm,ease}`

## Known limits

- Mask ventilation (no tube) relieves hypoxia once per round and sets `meta.bagUntil`, which the core
  counts as ventilation while it lasts.
- A misplaced tube is heard by the assess module's breathing check (`meta.tube`: oesophageal → no air
  entry on either side and an epigastric gurgle, a correct call records `tube_oesophageal`; mainstem →
  the left side quiet), and CPR rescue breaths through an oesophageal tube ventilate nothing. The
  capnography check of this module always finds it.
- Prop offsets follow `docs/modules/props.md` start values; per-ped tuning lives in `Config.Intubation.props`.
- `externalMonitor = true` uses the field module's monitor overlay (`NZA.Monitor.Open`, kept on screen
  with `NZA.Monitor.Scene(true)`), which shows server vitals, not the minigame's simulated desaturation.
  A monitor the medic already had open is reused and left open afterwards.
- The airway shader is a single full-screen pass (scene evaluated three times for normals); on very
  old GPUs it falls back to the flat 2D drawing.
