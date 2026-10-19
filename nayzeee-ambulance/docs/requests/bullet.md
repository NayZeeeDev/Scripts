# Requests from the bullet module (projectile removal)

## 1. ARCHITECTURE §17 — module bus event (docs only)
Add the bullet row to the "Module bus events" table:

| Owner | Server bus | Client bus |
|---|---|---|
| bullet | `bullet:done (src, p, inj, outcome)` | `bullet:flinch (entity, pain)` |

`outcome = { score, grade, easy, msg, extracted, left, sutured, dressed, disinfected, haemostasis, bloodLoss, quality, used, record }`.

## 2. Props (optional, props module / lead) — a dedicated operating table + theatre light
The `surgery` point currently spawns the native `v_med_emptybed` (set in `Config.Bullet.Table.model`,
owner-editable) with `Config.Props.surgery_tray` beside it and a local `DrawLightWithRange` lamp.
A purpose-built model would look better in hospitals that have no mapped theatre:

- `Config.Props.op_table = 'nz_amb_op_table'` — articulated operating table (tabletop at z ≈ 0.85 m,
  origin on the floor under the centre of the top, +Y = head end), arm boards, no branding.
- `Config.Props.op_light = 'nz_amb_op_light'` — ceiling or mobile twin-head theatre light (heads at
  z ≈ 2.0 m), emissive lens texture, no branding.

When they exist, set `Config.Bullet.Table.model = 'op_table'` (Config.Props key — `NZA.Props.Spawn`
resolves keys) and the client spawns the light the same way as the tray. No code change in other
modules is needed.

## 3. ExamRoutes / suture hand-off (FYI, no change needed)
After a successful operation the injury has `retained = 0`, `treat.extracted = true` (and usually
`treat.sutured` / `treat.dressed`). When the surgeon skipped the closure, the suture module's
`'controlled'` rule for gunshot / shrapnel wounds now lets the wound be stitched normally.
