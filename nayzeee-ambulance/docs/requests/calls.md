# Requests from the calls module

## 1. Dispatch: the arrival toast copies the reference wording (originality)
- **Where:** `locales/en/dispatch.lua`, the toast shown when a unit reaches SCN. Per
  `docs/modules/dispatch.md` it reads "You have arrived at the scene".
- **Why:** this is word for word the toast in the competitor screenshot `6a5eff93-image.png`
  ("You have arrived at the scene."). `docs/design/ORIGINAL.md` §1 (Copy) forbids reusing their
  phrases.
- **Suggestion:** our own short line, for example "On scene · C-0412" or "Unit on scene — patient
  is close by". The calls module does not send this toast. It only listens to `dispatch:status`.

## 2. ARCHITECTURE §9: the voice path format (docs only)
- **What:** `NZA.Dispatch.Create{ voice = ... }` takes a path relative to `html/`
  (`'audio/calls/mva_c1_full.ogg'`). The call card only plays `^audio/…\.(ogg|mp3|wav)$`.
- **Why:** the module brief's example used `nui://nayzeee-ambulance/html/audio/...`, which the call
  card rejects. The calls module uses the relative form (`Config.Calls.call.voiceFolder =
  'audio/calls/'`). §9 could say so, to stop other callers using the `nui://` form.

## 3. Nothing else is needed
- `fxmanifest.lua` already ships `html/audio/*/*`, so the 77 voice files are included.
- `config/modules/calls.lua` defines `Config.Calls` and `Config.AIMedic`, as the brief asked
  (`Config.AIMedic` is named in the AI medic spec).
