# Requests from transport (lead / props owned files)

Nothing here blocks the module; it works as written. These make it better.

## 1. config/props.lua — folded stretcher (lead + props module)

Add a lowered / folded cot model and its fallback:

```lua
stretcher_low = 'nz_amb_stretcher_low',   -- the cot with the scissor lift folded (loaded / lowered)
```
(`Config.PropFallbacks.stretcher_low = 'v_med_emptybed'` optional.) Same origin and axes as
`nz_amb_stretcher` (origin on the ground under the cot, head end +Y), mattress top ≈ 0.46 m.
`Config.Transport.Stretcher.lowModel` already points at the key; while it does not exist the
cot keeps its model and raise / lower only changes the state (speed, loading). With it, lowering
swaps the networked entity and the patient offset gets `patient.lowZ`.

## 2. ARCHITECTURE.md §8 / §17 — transport additions (documentation only)

- Point type `stretcher` (owner transport): a rack where cots are taken and returned.
- Bed-like point types: every type in `Config.Transport.Beds.types` plus any point / type with
  `data.bed = true` (other modules can mark their own point types as beds this way; optional
  `point.data.lie = { x, y, z }` nudges where the body lies).
- Server bus `transport:loaded (src, p, vehNet, strNet)`, `transport:unloaded`, `transport:bed (src, p, point)`,
  `transport:carry`, `transport:bay`; client bus `bay:entered`, `bay:left`, `bay:ivstand (target, info)`,
  `bay:monitor (target, info)`.
- State bags `nzaTr` (patient), `nzaStr` (stretcher entity), `nzaAmb` (ambulance) — server-set.

## 3. Blood / field modules (integration notes, no lead change)

- In the treatment bay F3 calls `NZA.Blood.OpenStand(target, info)` when it exists, otherwise emits
  client bus `bay:ivstand (target, info)`; F4 emits `bay:monitor (target, info)` when something listens,
  otherwise the bay shows its own monitor. `info.hooks` are the world positions of the bay's IV
  hooks (from the bay shell layout), `info.origin` the bay floor centre, `info.cot` the cot spot.
- Props spawned in the bay should be local (`network = false`) like the interior.
