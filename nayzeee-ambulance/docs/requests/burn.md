# Requests from the burn module

## 1. nza3d.js (suture module) — the NAYZEEE name on in-world props · RESOLVED (engine labels are generic now)

ORIGINAL.md forbids the NAYZEEE name / mark on props and device faces. Still present in
`html/core/nza3d.js`:

- `makeLabel('saline')` — `drawMark(...)` + `NAYZEEE MEDICAL` on the irrigation bottle.
- `makeLabel('syringe')` — `5 mL · NAYZEEE` on the lidocaine syringe.
- `makeDressingTex(...)` — `NAYZEEE · STERILE` + `drawMark` printed in the corner of every dressing.

The burn app does not use the first two (it builds its own unbranded bottle, diascope, dermatome,
stapler) and replaces the dressing's map with its own hydrogel burn-dressing print, so burn is clean
either way. Suture / bullet / chest drain still show them. Suggested: a generic maker line
(`STERILE · SINGLE USE`, a lot number) and no mark.

## 2. nza.js ProcPanel — dial label overlaps the 240° arc · RESOLVED (`.gv` moved to top:56px)

`.pp-gauge .gv` sits at `top:44px`; a label longer than ~9 uppercase characters is drawn across the
ends of the arc. The burn app now uses one-word labels (Surface, Tested, Debrided, Excised, Graft,
Meshing, Staples, Covered, Adhered), so this is no longer visible in burn. Suggested for everyone:
`.pp-gauge .gv{top:50px}` and `.pp-gauge .gv .l{padding:0 30px;font-size:8px}`.

## 3. nza.js ProcPanel — skipped steps on the spine

The burn app marks skipped steps itself (`.pp-segs i.skip`, styled in `apps/burn/app.css`) after
every `pp.set({ step })`. A built-in `skipped: [n…]` option on ProcPanel would let every app do it.
Not blocking.

## 4. nza3d.js — partial-thickness burn colouring (FYI for the suture module)

The engine colours partial-thickness burns with `smoothstep(0.52, 0.72, nzaN2.b)` — worley cells —
which reads as round pink/white polka dots. The burn app patches its own scene's skin material at
compile time (it replaces the block from `vec3 nzaPart =` to
`nzaCol = mix(nzaCol, nzaFull, smoothstep(0.66, 0.86, nzaBs));` and appends after
`nzaWet = clamp(...)`, `roughnessFactor = mix(roughnessFactor, 0.92, nzaGrit);` and
`vec2 nzaCoatXY = ...`). If you change those lines, please keep them (or tell burn); otherwise the
patch is skipped silently and burn falls back to the engine look. Other apps using `type: 'burn'`
wounds would also benefit from non-round noise there.

## 5. nza3d.js — `fluids.drops(point, count, color)` always lands as blood

`updateFluids` paints `layers.paint('blood', …)` for every kind-2 particle that lands, whatever its
colour, so clear / serous droplets leave red dots. Burn no longer calls it for blister serum.
Suggested: only paint blood when the colour is blood-red, or paint `'wet'` otherwise.

## 6. Exam route `items`

The burn routes list `Config.Items.saline` + `burn_dressing` (care) and `graft_kit` + `burn_dressing`
(graft). The exam's "have / need" counts read the bag; nothing else needed.

## 7. nza3d.js dressing — a placed sheet creeps down a curved limb

`S.dressing` has no tangential friction: a placed, un-rubbed dressing slides under gravity along the
curve of a limb (on the thigh a 17 × 12 cm burn dressing left alone for ~6 s slid off the patch;
`D.covers()` went from 1 to 0). Burn works around it by tacking the sheet where it lands
(`tackDressing`: nine `D.rub(...)` presses round the centre ≈ 13 % stuck, the rest still has to be
rubbed on). Suggested engine fix for every app: when a free vertex is in contact, remove the
tangential part of its velocity (or scale it by ~0.1) — i.e. static friction for contact vertices.
