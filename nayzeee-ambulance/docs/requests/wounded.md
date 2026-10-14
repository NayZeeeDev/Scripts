# Requests from wounded

Nothing here blocks the wounded module; it works without these changes.

## 1. core-server (please forward)

- **State bag `nza`: add `cpr = true`** while `lastCpr` is within 4 s (the window physiology already
  uses). The wounded module computes this itself for the downed player (`nza:wounded:status`), but
  having it in the replicated summary lets every client (bystanders, HUDs, the call card) show
  "CPR in progress" without a server round trip. The client already reads `nza.cpr` if present.
- **Keep the arrest cause on death**: `SetState(p, 'dead', 'arrest')` overwrites `p.cause.reason`
  and `conditions.arrest.cause` with `'arrest'`, so the original cause (`hypovolemia`, `tension`,
  `drowning`, ...) is lost. Keeping it as `p.cause.arrestCause` (or not overwriting
  `conditions.arrest.cause`) would let the death screen say "Heart stopped after blood loss".
- **Self snapshot `loss`** (0..1) — same request as core-client; wounded uses `fx.tunnel` meanwhile.

## 2. config/config.lua (lead) — comment only, optional

`Config.Wounded.giveUp.hold` and `Config.Death.respawnHold` are used as hold times; the E keys
for them live in `Config.WoundedUI.keys` (config/modules/wounded.lua). A short note next to
`giveUp` / `respawnHold` pointing there would help server owners:
`-- the key is Config.WoundedUI.keys.giveUp / .respawn (config/modules/wounded.lua)`

## 3. hospital module (please forward)

- `NZA.Hospitals.RespawnPoint(coords)` → a point `{ id, hospital, coords = vector4, label? }` (or a
  vector4) — the wounded module reads `coords`, `hospital`, `label`, and `NZA.Hospitals.Get(id).label`.
- `NZA.Hospitals.FreeBed(hospitalId)` → `{ id, coords = vector4 }` with `coords` = where a patient lies
  (feet → head along the heading); `OccupyBed(id, pid)` / `ReleaseBed(id)` are called around a respawn.

## 4. dispatch / AI medic / bodybag (please forward)

- Dispatch and AI medic: `NZA.Wounded.Help(pid, { eta, unit, ai, status })` puts "medic on the way ·
  ETA" on the downed player's HUD (`status = 'onscene'` on arrival, `'cancelled'` to clear it).
- Bodybag / morgue: `NZA.Wounded.ForceRespawn(src, { coords, label, fee })` runs the respawn flow
  (fade, teleport, revive, losses, bill) without the timer, e.g. when the morgue processes a body.
- Modules that animate a downed player without attaching him: `NZA.Wounded.SuspendPose(name, true)`
  while your animation runs, `false` afterwards.
