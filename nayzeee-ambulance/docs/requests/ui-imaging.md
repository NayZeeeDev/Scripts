# UI requests from the imaging group (xray, angio)

Nothing here blocks the apps; both work with the core as it is.

## 1. ProcPanel dial label width (core, nice to have)

`.pp-gauge .gv .l` has `padding:0 26px` inside a 150 px gauge, so a dial label longer than about
nine upper-case characters is clipped by the arc (e.g. "GAP TO LEAK" lost its first letter).
The apps now use short labels (*Leak gap*, *Review*, *Angle*, *kVp*, *Developer*). If the padding
could drop to ~18 px, or the label could shrink (`font-size: 8px; letter-spacing: .1em`) when it
overflows, apps could use slightly longer words.

## 2. Interaction label (core interact menu)

The xray module now registers ONE option on a patient lying on the X-ray table
(`nza_xray_table`, label `xray.opt_take_patient` = "Radiograph this patient") instead of eight
"X-ray: <body part>" entries, so the target menu no longer lists body parts. Nothing to change in
the core; noted here so the integration pass does not re-add per-view entries.
