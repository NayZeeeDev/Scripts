# Change requests from the intubation module

## lead — `html/core/nza.css` (ProcPanel)

1. **Single-step panels squeeze the text into the spine column.** `.pp-main` is a fixed
   `grid-template-columns: 22px 1fr`; with `total = 1` the spine is `display:none` and `.pp-body`
   lands in the 22 px column (one word per line). Suggested fix: in `renderStep()` toggle a class
   (`root.classList.toggle('pp--flat', total <= 1)`) and `.pp--flat .pp-main{grid-template-columns:1fr}`.
   The intubation app works around it with
   `#app-intubation .pp-spine[style*="none"] + .pp-body{grid-column:1 / -1}` — remove once fixed.
2. **Dial label overlaps the arc** for labels longer than ~10 characters (`.pp-gauge .gv .l`).
   A `max-width` with ellipsis or a smaller letter-spacing would keep labels inside the dial.

## core-server — `server/core/physiology.lua`

3. **Mask ventilation.** A BVM round on a patient without a tube sets `p.meta.bagUntil = os.time() + s`.
   Please treat it like assisted ventilation where `ventilated` is computed (line ~480):
   `local ventilated = (p.devices.intubated and p.meta.ventilated) or (p.meta.bagUntil and p.meta.bagUntil > os.time())`
   (rate `p.meta.ventRate or 10`). Until then the round only relieves the hypoxia condition.

## assess module — `server/modules/assess_breathing.lua`

4. **Oesophageal / mainstem tubes.** `p.meta.tube = { placed = 'trachea'|'oesophagus', mainstem = bool, … }`.
   With `placed == 'oesophagus'` both lungs should be silent on ventilation and the epigastrium gurgle;
   with `mainstem == true` the left side should be reduced / absent. (`devices.intubated` stays `true`
   in both cases so the rest of the resource sees a tube.)

   Status: done. `describe()` in `server/modules/assess_breathing.lua` reads `meta.tube`: oesophageal →
   every zone absent, both side calls correct, an epigastric line on sight and a `tube_oesophageal`
   finding on a correct call; mainstem → the left side absent / reduced (call `absent_l`).

## cpr module

5. Breaths through a tube with `meta.tube.placed == 'oesophagus'` should not count as ventilation.

   Status: done. `nza:cpr:breath` (`server/modules/cpr.lua`) scores such a breath 0, so it neither
   ventilates nor clears water / smoke hypoxia.
