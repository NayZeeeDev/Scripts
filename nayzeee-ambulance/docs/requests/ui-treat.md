# UI pass requests — group "treat" (apps `treat`, `bay`; modules firstaid, transport)

Nothing here blocks the apps: each item is already worked around inside the app. These are
suggestions for the lead-owned core so other apps get the same behaviour for free.

1. **ProcPanel readout: long `wide.value` / `wide.label` overflow the 240° dial.**
   `.pp-gauge .gv .v` is 24px mono with `padding:0 18px`; words such as "Occluded" spill over the
   dial ring, and labels longer than ~11 characters ("Arterial occlusion", "Velcro straps") are cut
   under the ticks. Workaround in `treat`: values are kept to numbers / four-letter words and the
   labels were shortened (`Occlusion`, `Straps`, `Neck`, `Tension`).
   Suggestion: auto-shrink the value font when `String(value).length > 5` (e.g. a `.v.long` class
   at 17px) and allow two lines for `.gv .l`.

2. **Shared holographic body glyph.** `treat` (context card) and `bay` (patient card) both draw the
   same segmented front-view body glyph (15 regions, severity colours, pulsing diamond hotspots).
   The code is duplicated in both apps (`bodyGlyph()`); a core `NZA.ui.BodyGlyph(states, focus)`
   would let exam / bed / wounded apps use the identical asset.

3. **Shared status ring.** `treat` renders vitals as small status rings (`vring()` — value inside,
   track + fill, optional heartbeat ping at the live rate). A core `NZA.ui.Ring` would keep the ring
   treatment identical across apps.
