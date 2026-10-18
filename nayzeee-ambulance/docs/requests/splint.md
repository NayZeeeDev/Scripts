# Requests from the splint module

## 1. Props: generic labelling on the splint / crutch props — DONE

The props pass replaced the old print on `nz_amb_splint_leg` with generic labelling (`LEG SPLINT` +
star of life, see `/tmp/nza-work/props/out/renders/nz_amb_splint_leg_front.png`). Nothing left to do.
The NUI splint (three.js) carries its own generic print only: model code (`CS-76` / `CS-40`), device
type, centimetre rule, joint lines and a "check pulse below" warning sticker. No brand anywhere.

## 2. Props: native fallbacks for the worn splints (optional)

`Config.PropFallbacks` has no entry for `splint_leg` / `splint_arm`. If the streamed models fail to
load, worn splints simply do not show (nothing breaks). If a native stand-in is wanted, add e.g.
`splint_leg = 'prop_cs_walking_stick'` — not recommended visually, so this is optional.
Owner: lead (`config/props.lua`).

## 3. Locale: `core.bone_*` keys used by the splint fracture card

The splint card shows `NZA.L('core.bone_' .. fracture.bone)` (e.g. `tibia_fibula`, `radius_ulna`) and
falls back to the raw key name when a bone has no label. All bones produced by `server/core/injury.lua`
should have a `core.bone_*` label (they do today). No change needed unless new bones are added.
Owner: core-server.

## 4. Kit (optional, lead): `.dev` class name

`html/core/nza.css` defines a global `.dev` (device bezel). Any app that uses a plain `.dev` class for
something else inherits the bezel look (the splint record card hit this; it now uses `.dv`). A
prefixed name (`.nza-dev`) in the kit would avoid such clashes for other modules. Owner: lead.

## 5. Integration notes (no change needed)

- The splint procedure uses the anchors `prox / dist / cms / core` and `NZA.Cam.TopDown(coords, height,
  { heading, fov, minHeight, maxHeight })`; the NUI renders the splint with the same `fov`, so keep
  `Config.Splint.Splint.camera.fov` and the TopDown fov identical (the module does this itself).
- `NZA.Self.SetMoveOverride` names used: `crutch`, `wheelchair`, `splint_leg`.
- Player state bag written by the server: `nzaCrutch` (replicated). Entity state bag on wheelchairs:
  `nzaChair` (replicated).
- The mobility card (wheelchair / pushing / crutches) is the `splint` app opened without focus in
  `hud` mode; a splint procedure on the same client hides it and it comes back afterwards.
