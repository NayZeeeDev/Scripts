# Requests from the burn module

## 1. nza3d.js (suture module) — instrument labels carry the NAYZEEE name

`html/core/nza3d.js` → `makeLabel('saline')` prints `NAYZEEE MEDICAL` on the irrigation bottle and
`makeLabel('syringe')` prints `5 mL · NAYZEEE` on the lidocaine syringe. ORIGINAL.md forbids the
NAYZEEE name on props / in-world devices. The burn app does not use these two engine tools (it builds
its own unbranded irrigation bottle, diascope, dermatome and stapler), but suture / bullet do.
Suggested: replace with a generic maker line, e.g. `STERILE · SINGLE USE` and a lot number.

## 2. nza.js ProcPanel — dial label overlaps the 240° arc

`.pp-gauge .gv` sits at `top:44px`; with a long `wide.label` ("SURFACE TEMP", "CONTAMINATION") the
uppercase label is drawn across the top of the arc. Suggested: `.pp-gauge .gv{top:50px}` and
`.pp-gauge .gv .l{padding:0 30px}` (or shrink the label to 8px). Seen in burn and suture.

## 3. nza.js ProcPanel — skipped steps on the spine

The burn app marks skipped steps itself (`.pp-segs i.skip`, styled in `apps/burn/app.css`) after
every `pp.set({ step })`. A built-in `skipped: [n…]` option on ProcPanel would let every app do this.
Not blocking.

## 4. Exam route `items`

The burn routes list `Config.Items.saline` + `burn_dressing` (care) and `graft_kit` + `burn_dressing`
(graft). The exam's "have / need" counts read the bag; nothing else needed.
