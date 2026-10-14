# UI requests from the wounded group (apps `wounded`, `death`)

Nothing here blocks the wounded HUD or the death screen; both apps already work around it.

## 1. core/nza.css — namespace the short global class names (lead)

`nza.css` defines un-scoped rules on very short class names that apps also use for their own
elements:

- `.tg` (toggle switch: `width:40px;height:22px;border-radius:99px;background:…`)
- `.hold` (hold ring: `position:relative;display:inline-grid`)
- `.t-teal / .t-red / .t-amber / .t-white / .t-dim` (text colour utilities)

The wounded HUD used `.tg` for its injury tags and `.t-red`… for the vital card tone, so the tags
were squeezed to 40×22 px and the text spilled out of the box. Fixed on our side by renaming
(`.itag`, `.tn-*`, `.hld`), but other apps may hit the same trap. Suggested: rename them to
`.nza-tg`, `.nza-hold`, `.nza-t-red`… (or scope them, e.g. `.nza-toggle.tg`) and keep the old names
as aliases for one release.
