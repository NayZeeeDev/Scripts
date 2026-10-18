# Module: suture (wound closure) + NZA3D close-up engine

Owner files

| File | What |
|---|---|
| `client/modules/suture.lua` | entry points (exam route, interaction, item), runs `NZA.Proc.Run('suture')`, opens the NUI, cleanup |
| `server/modules/suture.lua` | `NZA.Proc.Register('suture')`, eligibility, case data, result validation, usable item |
| `config/modules/suture.lua` | `Config.Suture` (server owners edit this) |
| `locales/en/suture.lua` | every string, keys `suture.*` (sent to the app with `NZA.LocaleTable('suture')`) |
| `html/apps/suture/app.js / app.css` | NUI app `suture`: full-screen 3D close-up + procedure HUD |
| `html/core/nza3d.js` | shared WebGL close-up engine `window.NZA3D` (used by suture, bullet, burn, ultrasound / chest drain) |

## Features

A laceration or stab wound (and a gunshot / shrapnel wound once the object is out and the
bleeding is controlled) is closed in a full-screen, real-time 3D close-up of the patient's skin.

- **Skin**: procedural, per-patient (tone from `Config.Suture.skinTones`, picked from the patient id),
  region-shaped base surface (cylinder for limbs, gentle curve for the torso), large-scale colour
  mottling, capillary redness, veins on light skin, freckles and moles, a tiling micro-relief
  (furrow network, pores, vellus and terminal hair), sebum sheen as a clear coat, subsurface wrap.
- **Wound**: a height field rendered on the GPU (groove with jagged lips, gape, depth, taper),
  tissue layered by real depth (pale epidermis lip, glistening dermis, torn fat clumps, dark pooled
  blood), erythema around the margin, clots, grime, grit and dried flecks painted into GPU masks
  with a CPU mirror for the gameplay maths.
- **Light**: a two-cell operating lamp angled from the upper left (soft double-penumbra shadows of
  every tool and the dressing), a shadowless centre cell, a cool room fill, ACES tone mapping.
- **Steps** on the shared procedure HUD (instruction column bottom-left, tool belt right edge):
  1. **Rinse** (tool 1, 30 mL irrigation syringe, refilled from the 250 mL bottle): hold LMB and walk
     the stream through the cut. The jet washes grime and clot out of the masks; *Debris* dial
     counts down to 0 %; the stream stings an un-numbed wound.
  2. **Numb** (tool 2, lidocaine 1 % 5 mL): hold LMB on each ring along both edges until the wheal
     rises (bump in the height field). Pain drops; skipping (press 4 twice) leaves the patient in
     pain → flinches (camera shake, voice line, the needle jumps out of line).
  3. **Stitch** (tool 4, needle holder + 4-0 nylon): press at the ring on the near edge, drag
     across to the dashed ring, release — the thread is drawn live while pulling, the knot ties
     itself. Each stitch is judged on bite depth on both sides, squareness to the cut, spacing and
     speed; the cut closes locally and the bleed drops per stitch. `n/N` stitch counter + per-slot
     quality bar.
  - **Gauze** (tool 3, any time before the dressing): hold LMB to blot pooled blood; each swab
     soaks up a fixed amount, stains visibly, then a fresh one is opened (limited by what you carry).
  4. **Seal** (tool 5, island dressing): grab the dressing by its border (cursor changes), it hangs
     from the fingers as cloth and casts a shadow; lay the pad over the stitch line, release, then
     rub it down until it sticks. Coverage of the cut and adhesion are measured; blood seeps into
     the pad.
- **Debrief card** (slides in bottom-left where the procedure column was, so the finished closure
  stays in view): 240° score dial with the grade, per-step instrument list (value, score, tone
  notch, meter), plain-language notes with glowing bars; Enter closes once the server confirmed.
- **Patient card** (top-left: pain meter, anaesthetic / flinch chips) and **closure plan**
  (top-right: step list with live values, timer, swabs and saline left).
- **No WebGL2**: a short manual fallback (progress bar) so the procedure still completes.
- **Easy mode** (per department, or `Config.EasyMode.default`): no minigame, `NZA.Proc` progress
  bar; only the supplies are needed (no location rule).

## Controls

| Input | Action |
|---|---|
| LMB (hold) | use the active tool (squeeze, inject, pull a stitch, blot, carry / rub the dressing) |
| 1–5 | pick a tool; picking a later step's tool asks once, the second press skips ahead |
| RMB drag | look around · Shift+RMB pan · Wheel zoom · R recentre |
| ESC (hold) | stop the procedure |
| Enter | close the result card |

## Entry points

- Examination screen: `NZA.ExamRoutes` entry `suture` for every type in `Config.Suture.types`
  (`available` → greyed with the reason when the bleeding is not controlled / object retained).
- Patient interaction menu: "Stitch wound" (`Config.Suture.interact`, order 62, perm `suture`).
- Using the suture kit item next to a patient (`Config.Suture.usableItem`).
  Several closable wounds → an ox_lib context menu to choose one.

## Server rules (server authoritative)

- `NZA.Proc.Register('suture', { perm, items = Config.Suture.items, consume = 'finish', minTime,
  maxTime, easyTime, maxDist, states = alive/wounded })`; payload `{ injury = id }`.
- `onStart`: the injury must exist and be eligible (`NZA.Suture.Eligible`): type allowed, not
  already sutured, nothing retained for `'controlled'` types, and (outside easy mode) bleeding
  ≤ `maxBleed` or packed / bandaged / tourniquet, or severity ≤ `smallSeverity`. Optional location
  rule (`requireLocation`: bed / surgery / ambulance bay from `patient.meta`) skipped in easy mode.
- `onFinish`: score clamped and capped by the weighted step scores (+2), stitches clamped to
  `N + extraStitches`; *sutured* needs the cut closed (or N stitches) and `minStitchQuality`;
  *irrigated* needs contamination ≤ `irrigatedBelow`; *dressed* needs ≥ 50 % stuck and covered.
  Optional lidocaine / gauze are taken only when used and still carried. Sets
  `treat.irrigated / anesthetized / sutured / dressed`, `quality.*`, contamination → 0 when
  irrigated; physiology applies the sutured bleed modifier (×0.05). Lidocaine also goes through
  `NZA.Patients.GiveMed(pid, 'lidocaine', { injury, region })`.

## Config keys (`Config.Suture`)

`perm minTime maxTime easyTime maxDist allowSelf items{suture_kit saline dressing}
optional{lidocaine gauze} types{laceration stab gunshot shrapnel} maxBleed smallSeverity
requireLocation locations{bed surgery bay} irrigatedBelow minStitchQuality interact usableItem
useRange order skinTones Game{quality salineMl syringeMl salineFlow refillTime jetRadius cleanDone
lidoSyringe lidoDose lidoRate lidoMaxPoint lidoSpacing lidoOffset lidoPick mmPerStitch minStitches
maxStitches extraStitches bite biteMin biteMax minDrag gauzeRadius gauzeCapacity flinchPain
flinchChance stuckDone coverMin weights{irrigate anaesthetic suture dressing} fallbackTime}`.

## Events, callbacks, API

| Name | Kind | Notes |
|---|---|---|
| `suture:finish` | NUI → Lua | result `{ score, parts{irrigate anaesthetic suture dressing}, irrigated, contamination, salineMl, lido, lidoPoints, lidoTotal, lidoMl, gauze, stitches, sections, closed, misses, stitchQ, evenQ, dressed, stuck, cover, flinches, seconds, skipped[] }` → `{ ok, pending }`, then action `result` (server outcome) |
| `suture:abort` / `suture:flinch` / `suture:close` | NUI → Lua | abort the session · patient flinched `{ pain }` · core close |
| `result` / `abort` | Lua → NUI | outcome card · server ended the session |
| `nza:suture:use` | S → C | suture kit used (start on the nearest patient) |
| bus `suture:flinch (entity, pain)` | client | for animations / sounds of other modules |
| bus `suture:done (src, patient, injury, outcome)` | server | after a finished closure |
| `NZA.Suture.Start(target, injuryId)` | client | blocks; `ok, outcome | reason` |
| `NZA.Suture.Pick(entity, target)` / `NZA.Suture.Eligible(inj)` | client | wound picker · menu-side rule |
| `NZA.Suture.Eligible(inj, easy)` / `Location(p)` / `Case(src, p, inj)` | server | rules + NUI case |

## NZA3D engine (for bullet / burn / ultrasound)

The full API is documented at the top of `html/core/nza3d.js` (`createScene`, controls, picking,
paint layers, wounds incl. gunshot crater and burn patch, bumps, fluids (jet / bleed / drips /
drops), tools (saline bottle, irrigator, syringe, probe, needle driver, forceps, scalpel, gauze,
stapler, dermatome), markers, stitches, cloth dressing, drape, `prewarm`, `dispose`). Notes:

- The WebGL context is pooled: `dispose()` frees every texture / geometry / target of a scene and
  hands the context to the next scene; `NZA3D.release()` drops it.
- Scene look is tunable at runtime: `S.lightRig` (lamp cell offsets), `S.uniforms`
  (`uMicroNormal`, `uSebum`, `uSSS`, …), `S.renderer.toneMappingExposure`.
- Labels on prop textures are generic (device type, model code, lot, sterile / single-use glyphs);
  never put a brand on them.

## Known limits

- The engine needs WebGL2; clients without it get the manual fallback.
- The 3D is rendered in the NUI (CEF): on very weak GPUs use `Game.quality = 'medium' | 'low'`.
- The close-up is a generic skin patch of the injured region, not the GTA ped's own texture.
