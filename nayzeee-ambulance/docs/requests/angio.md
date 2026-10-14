# Requests from the angio module

## props — separate injector plunger (optional, nice to have)

`client/modules/angio_proc.lua` animates the power injector's plunger while dye goes in (and
leaves it where the bottle level is). `nz_amb_injector` documents "plunger face at x = 0.03
(animate a separate plunger by moving along -X)", but there is no separate model yet.

- Please add `nz_amb_injector_plunger` (plunger rod + thumb disc, origin at the plunger face,
  rod along +X) and `Config.Props.injector_plunger = 'nz_amb_injector_plunger'` in
  `config/props.lua` (lead).
- The angio config already expects it at `Config.Angio.suite.plunger = { prop = 'injector_plunger',
  pos = vector3(0.03, 0.05, 1.04), axis = vector3(-1, 0, 0), travel = 0.20 }` (injector model
  space). Without the key the injector simply stays still; nothing breaks.

## transport / bed module — lying on the angiography table

- Point type `angio` (registered by `client/modules/angio.lua`) is the TABLE. Its type def carries
  `lie = { pos = vector3(0.0, 0.0, 0.825), heading = 0.0 }` (table space, head end +Y), from
  `Config.Angio.suite.lie`; it matches `nz_amb_xray_table` ("patient surface z = 0.825").
- When a patient is placed on it please set `patient.meta.bed = { point = <point id>, type = 'angio' }`
  (ARCHITECTURE "clinical locations"). The angio server checks exactly that (unless easy mode).

## hospital builder — ghost of the whole suite

- The `angio` type def has `parts = { { key, model, pos (table space vector3), h (heading relative
  to the table) }, ... }` for the monitor, the injector tray and the red button. Showing these
  as extra ghosts next to the table ghost while placing (offset = rotate(pos, heading)) lets the
  builder see the whole set, like the reference "placement mode" shot.
- Optional per-point overrides read by angio: `point.data.layout = { monitor = { pos = {x, y, z},
  h = 270 } | false, injector = ..., button = ... }` (e.g. for MLO rooms). A builder field for
  it is welcome but not required.

## dispatch (radial owner)

- `NZA.RadialItems` entry `angio_start` (parent `'patient'`, icon `'scan'`, order 60, perm `angio`)
  is appended by `client/modules/angio.lua`; `canShow` is true only near an angio table with a
  patient lying on it.
