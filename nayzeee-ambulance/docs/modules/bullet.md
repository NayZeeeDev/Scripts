# Module: bullet (projectile / fragment removal surgery)

Owner files

| File | What |
|---|---|
| `client/modules/bullet.lua` | entry points (exam route, interaction, operating table, radial, item), runs `NZA.Proc.Run('bullet')`, opens the NUI, live vitals watch, point type `surgery` (table, tray, theatre light), cleanup |
| `server/modules/bullet.lua` | `NZA.Proc.Register('bullet')`, eligibility, room rule, fragment layout, X-ray film lookup, result validation, blood loss, usable item |
| `config/modules/bullet.lua` | `Config.Bullet` (server owners edit this) |
| `locales/en/bullet.lua` | every string, keys `bullet.*` (sent to the app with `NZA.LocaleTable('bullet')`) |
| `html/apps/bullet/app.js / app.css` | NUI app `bullet`: full-screen 3D surgical field on `NZA3D` + procedure HUD |

## Features

A gunshot or shrapnel wound that still holds metal is opened, cleared and closed in a full-screen,
real-time 3D close-up (shared engine `html/core/nza3d.js`) of the draped patient.

- **Surgical field**: blue drape with a round window over the wound, adhesive film rim, four towel
  clamps at the rim, a stainless kidney dish on the drape (every piece you take out lands in it and
  stays there, the camera glances at it after each extraction), a tight theatre-lamp pool with the
  room falling off into the dark. The entry wound has an abrasion collar, bruising, a short dried
  trickle, powder stippling on close-range gunshots, peppering and satellite holes for shrapnel and
  grime from the wound's contamination.
- **Metal**: a mushroomed jacketed bullet (copper jacket, torn petals, lead core) or jagged steel
  shards, generated per wound on the server (size, depth, offset from the entry hole, angle, and
  whether a piece is lodged). Several pieces for shrapnel.
- **Instruments built for this app** (on top of the engine's probe, scalpel, gauze, needle driver):
  foam prep sponge on a ribbed stick (stains from fresh brown to spent tan), Yankauer suction with
  ringed tubing that runs red while it works, ring-handled bullet forceps with serrated jaws and a
  box lock, a small self-retaining retractor (two 4-prong rakes, crossing arms, box hinge, finger
  rings, ratchet bar) that sits in the incision and opens with the spread.
- **Eight steps** (the kit's procedure column bottom-left, tool belt right edge):
  1. **Find the metal** — tool 1 probe: hold LMB in the entry hole, the probe slides down the track;
     drift off the track and it resists (steer arrow), push on and you make a false passage (blood,
     pain). It clicks on metal (sound) and the piece is marked on the skin with its depth. Shallow
     pieces can be felt by pressing on intact skin. **X** reads an X-ray film of this patient you
     carry (taken and read with the xray module): the film hangs on a backlit viewer (AP + lateral,
     depth scale) and every piece is marked at once (motion-blurred films: rough marks).
  2. **Prep the skin** — tool 2 sponge: scrub outward from the mark until the ring is covered; the
     amber stain builds up translucent; going back over the centre is penalised; the sponge runs dry
     and is swapped.
  3. **Open over it** — tool 3 scalpel: **Q / E** set the blade depth (tissue column shows skin, fat,
     muscle, bone and the target band), hold LMB and draw the line over the mark. Too short = the
     metal is not under the cut (extend from an end); too long or into the muscle = more blood.
  4. **Get eyes on it** — hold **Space** to open the retractor (past the band it tears), clear the
     pool with suction (4) or gauze (6) until the metal shows.
  5. **Lift it out** — tool 5 forceps: click the metal to close the jaws (grip strength depends on
     aim), then move the mouse toward you slowly. The **traction dial** (half ring: teal safe band,
     amber, red slip zone) shows the pull speed; too fast loses the grip and it slips and tears
     (bleed spike). Lodged pieces must be rocked free with **A / D** first. **L** (twice) leaves the
     remaining pieces in.
  6. **Stop the ooze** — gauze pressure on the bleeding point (suction first to see it) until the
     bleed is under `Game.bleedDone`.
  7. **Close the cut** — the suture mechanics of the suture app (near edge → far edge, bite, angle,
     spacing judged per stitch).
  8. **Cover it** — pick the dressing up by its edge, lay it over the incision and the entry hole,
     rub it down.
- **Pain**: an awake patient who is not numbed (lidocaine / morphine active) flinches on painful
  moves (camera shake, voice line top-centre, the hand jumps); flinches cost score.
- **Blood**: the cut, the bleeding and every mistake add to a live **estimated loss** shown on the
  monitor card (ring) and taken off the blood volume bar; the server applies it on finish.
- **HUD (our own layout)**: monitor card top-left (ECG + pleth traces, HR / SpO₂ numbers, NIBP with
  MAP, respiration, estimated-loss ring, blood volume bar with 85 / 70 % ticks, IV line state, and in
  the ambulance bay a hold-Backspace key to step out), notes under it (low blood with no line
  running, awake and not numbed), **operative plan** top-right (2 × 4 step matrix with spine nodes,
  live values, case clock, location, chips), instrument card right-middle (probe depth + tissue
  column, prep soak / technique, blade depth + band, retractor spread / field, traction dial + grip
  + rock pips, bleed rate), film viewer in the same spot, fragment tags (diamond markers with dark
  chips) in the scene, a cursor ring for hold progress, coaching tip and stitch row in the kit's
  `pp.slot`.
- **Debrief card** bottom-left: grade, score, blood lost, eight scored parts (value, detail, meter)
  and plain-language notes; Enter closes once the server confirmed.
- **No WebGL2**: a manual fallback (progress bar, standard technique, score 60).
- **Easy mode** (per department or `Config.EasyMode.default`): no minigame, `NZA.Proc` progress
  bar; no room rule — only the supplies are needed. Everything comes out, is closed and dressed;
  `Blood.easy` mL are lost.

## Controls

| Input | Action |
|---|---|
| 1 – 8 | probe · prep sponge · scalpel · suction · forceps · gauze · needle driver · dressing |
| X | X-ray film on / off (when you carry a film of this patient) |
| LMB (hold) | use the active tool |
| Q / E | blade shallower / deeper (scalpel) |
| Space (hold) | open the retractor (steps 4–6) |
| A / D | rock a lodged piece (forceps, step 5) |
| L (twice) | leave the remaining pieces in (step 5) |
| Right-drag · Shift+right-drag · wheel · R | look around · pan · zoom · recentre (engine camera) |
| Backspace (hold) | in the ambulance bay: stop and step out of the ambulance |
| Esc (hold) | stop the operation |
| Enter | close the debrief |
| Pressing a later tool twice | skip ahead (confirm) — skipped steps score 0 |

## Rules (server)

- Wound types `Config.Bullet.types` (gunshot, shrapnel) with `retained > 0` and not `treat.extracted`.
- Room: `patient.meta.bed.type` in `Config.Bullet.locations` (operating table point `surgery`) or
  `patient.meta.bay` (ambulance treatment bay) — skipped in easy mode or with `requireLocation = false`.
- Supplies: `Config.Bullet.items` (iodine — taken on finish) checked by the core; every
  `Config.Bullet.supplies` item (surgical kit, gauze, suture kit, dressing) must be carried — also in
  easy mode. On finish: suture kit only if the cut was stitched, dressing only if it went on, gauze
  as opened (≤ `gauzeMax`), the surgical kit only with `consumeKit = true`.
- Result validation: extracted ids must be fragments of this session (each once), score clamped and
  capped by the weighted step scores (`Game.weights`), ≤ 30 when nothing came out, ≤ 80 without a
  prep, ≤ 70 without a closure, ≤ 60 for the no-WebGL fallback; `minTime` / `maxTime` by the core.
- Effects: `retained` → pieces left (`retainedDepth` 0 when clear), `treat.extracted` (all out),
  `treat.sutured`, `treat.dressed`, `quality.extracted / sutured / dressed`, `bleedBase` ×
  `Bleed.controlled` (haemostasis) or × `Bleed.open`, contamination × `Infection.prepKeeps` (by
  coverage) or + `Infection.noPrep`, + `Infection.leftPieces` per piece left, blood loss = the
  client's estimate clamped to `Blood.min..max` and to 0.5–2.5 × the expected loss
  (`base + perFragment × out + poorWork × (1 − score)`), applied with `NZA.Patients.AddBlood`.
- Fragments are deterministic per wound (`pid:injury`), use `injury.xrayMap.depth` /
  `retainedDepth` and `spot`; at most `Fragments.maxPieces` are shown.

## Config keys (`Config.Bullet`)

| Key | Meaning |
|---|---|
| `perm minTime maxTime easyTime maxDist allowSelf` | procedure basics |
| `items` | taken on finish every time (Config.Items keys) |
| `supplies` | must be carried; taken only when used |
| `consumeKit gauzeMax` | surgical kit single-use? · most gauze swabs per operation |
| `types` | wound types that qualify |
| `requireLocation locations` | room rule (`surgery`, `bay`) |
| `Blood.*` | warning threshold, expected loss model, clamps, easy loss |
| `Bleed.controlled / open` | bleed base factor after the operation |
| `Infection.*` | contamination after prep / no prep / pieces left |
| `numbed` | medications that count as numbed |
| `Fragments.*` | bullet / shard size, spread, lodge chance, max pieces |
| `interact usableItem useRange order radial` | menus and item |
| `skinTones` | close-up skin tones |
| `Table.*` | operating table model (false = map table), patient lie offset, tray prop + offset + heading, theatre light (pos, colour, range, intensity), range for "on the table" |
| `Game.*` | minigame tuning sent to the NUI (probe, prep, blade, spread, traction, bleeding, suture, dressing, pain, weights, fallback) |

Items: `Config.Items.iodine`, `.surgical_kit`, `.gauze`, `.suture_kit`, `.dressing`, optional `.xray_film`.
Props: `Config.Props.surgery_tray` (+ `Config.Bullet.Table.model`).

## Events, callbacks, exports

| Name | Kind | Notes |
|---|---|---|
| `bullet` | `NZA.Proc` | payload `{ injury }`; data = the case below |
| `nza:bullet:use` | S→C | the surgical kit item was used → nearest patient (table first) |
| `bullet:done (src, p, inj, outcome)` | server bus | after a finished operation |
| `bullet:flinch (entity, pain)` | client bus | the patient flinched in the minigame |
| `bullet:finish` | NUI → Lua | `result` → `{ ok, pending }`, then action `result` (outcome) |
| `bullet:abort` · `bullet:flinch` · `bullet:exitBay` · `bullet:close` | NUI → Lua | stop · flinch · stop and leave the bay · closed |
| `open` · `vitals` · `result` · `abort` | Lua → NUI | case · live monitor (from `NZA.Patient.Watch`) · server outcome · server ended the session |

Case (`open`): `{ locale, cfg, patient { name, sex, bloodType, conscious, numb }, injury { id, type,
region, regionLabel, label, severity, bleed, retained, depth, contamination, pain }, fragments [{ id,
x, y, depth, size, shape, rot, lodge }], tone, seed, film { id, view, viewLabel, taken, quality,
marked } | nil, items { gauze }, location { kind, label }, bay, bloodWarn, vitals { hr, ecgRate,
rhythm, spo2, sys, dia, map, rr, bloodPct, drip, infusing } }`.

Result (`bullet:finish`): `{ score, parts { locate, disinfect, incise, expose, extract, haemostasis,
suture, dressing }, located, method, falses, film, disinfected, coverage, backtracks, incision {
length, ideal, depth, covered, extensions, muscle }, extracted [ids], left [ids], slips, misses,
tears, haemostasis, bleedEnd, sutured, stitches, sections, closed, stitchQ, evenQ, sutMisses,
dressed, stuck, cover, bloodLoss, gauze, suctionMl, flinches, seconds, skipped [steps], fallback? }`.

Lua API: server `NZA.Bullet.Eligible(inj)`, `.Location(p)`, `.Fragments(p, inj)`, `.Film(src, p, inj)`,
`.Case(src, p, inj, kind)`; client `NZA.Bullet.Start(target, injuryId)`, `.Pick(entity, target)`,
`.Eligible(inj, snap)`, `.OnTable(point)`.

Registries: `NZA.ExamRoutes` `bullet` (gunshot / shrapnel holding metal; greyed with the reason when
not on a table / in the bay), `NZA.Interact` `nza_bullet`, `NZA.Points.RegisterType('surgery')`
(target *Operate*), `NZA.RadialItems` `bullet_start` (parent `patient`), usable item
`Config.Items.surgical_kit`.

Preview: `html/index.html?app=bullet` (gunshot, ambulance bay, low blood, film in the pocket) and
`?app=bullet&demo=shrapnel` (three shards, one lodged, operating table, numbed). Browser helper
`NZA.apps.bullet.demoTo('probe' | 'located' | 'film' | 'disinfect' | 'incise' | 'cut' | 'expose' |
'extract' | 'pull' | 'control' | 'suture' | 'dressing' | 'done')`.

## Known limits

- The table model is a native bed until a dedicated operating table prop exists (see
  `docs/requests/bullet.md`); with `Table.model = false` the point uses the map's own table.
- The X-ray film overlay is drawn from the session's fragment layout (the same truth the server
  used), not by re-reading the xray module's film image.
- The live blood estimate is only applied on finish (an aborted operation costs no blood).
