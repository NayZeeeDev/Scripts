# Requests from the splint module

## 1. Props: no NAYZEEE name on the splint prop (customer requirement)

`nz_amb_splint_leg` still prints **"NAYZEEE …"** on the outer shell (front render,
`/tmp/nza-work/props/out/renders/nz_amb_splint_leg_front.png`). The customer asked for no name or logo
on any prop. Please replace that print with generic device labelling, e.g. `LEG SPLINT · CS-76` +
a small size ruler (the NUI calls the devices "Contour leg splint CS-76" / "Contour arm splint CS-40").
Please check `nz_amb_splint_arm` and `nz_amb_crutch` for the same.
Owner: props module (`tools/props/**`, `stream/**`).

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

## 4. Integration notes (no change needed)

- The splint procedure uses the anchors `prox / dist / cms / core` and `NZA.Cam.TopDown(coords, height,
  { heading, fov, minHeight, maxHeight })`; the NUI renders the splint with the same `fov`, so keep
  `Config.Splint.Splint.camera.fov` and the TopDown fov identical (the module does this itself).
- `NZA.Self.SetMoveOverride` names used: `crutch`, `wheelchair`, `splint_leg`.
- Player state bag written by the server: `nzaCrutch` (replicated). Entity state bag on wheelchairs:
  `nzaChair` (replicated).
