# Requests from the ultrasound module

1. **`html/core/nza.js` · `NZA.ui.ProcPanel.complete()`** — after `complete()` the right-edge hold-to-abort
   ring stays on screen next to the result (seen in every procedure that shows its result in the panel).
   Suggest hiding the abort ring (or turning it into a plain `Esc close` key cap) when `pp--done` is set,
   e.g. in nza.css: `.pp--done .pp-abort{display:none}`. Purely cosmetic; the ultrasound modes already end on Enter / Done.

Nothing else is needed from lead-owned files: `Config.PropScreens.us_cart`, the `html/apps/**/*` file glob
(covers `html/apps/ultrasound/screen.html|js|css`, the cart DUI) and `Config.Items` keys
`chest_drain_kit`, `decomp_needle`, `iv_kit`, `lidocaine` are already present.
