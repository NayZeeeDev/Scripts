# Requests from core-client

Nothing here blocks core-client; everything works without these changes. They make the
integration cleaner.

## 1. html/core/nza.js (lead)

- **`_core` action `focus`** — core-client sends `{ top = 'appName' | nil, apps = { ... } }`
  after every focus change (Lua focus stack: which open app has NUI focus on top). The router
  currently ignores it (no `default` in `core()`), which is harmless. If the JS keyboard
  routing should follow the Lua focus stack instead of its own open order, use `top`.
- **`_core:camInput` (optional)** — when an app keeps the mouse in the NUI without
  `keepInput`, the game cannot read right-drag/scroll for `NZA.Cam.Orbit`. A small helper
  that forwards drags would make every 3D close-up orbitable:
  `NZA.post('_core:camInput', { dx: movementX / innerWidth, dy: movementY / innerHeight,
  wheel: Math.sign(deltaY), pan: e.shiftKey, recenter: key === 'r' })` while the right mouse
  button is held. Lua side is already registered (`client/core/ui.lua` → `NZA.Cam.Input`).
- `prompt` payload also carries `hold` (seconds) — unused by the JS today, safe to ignore.
- `toast` payload may carry `grade` and `score` (procedure results). The JS could show the
  `NZA.ui.Grade` badge when `grade` is present; the grade is also already in the message text.
- `anchors` with an empty set arrives as `[]` (JSON of an empty Lua table) — the router's
  `a.anchors.map = data || {}` handles it, `get(id)` just returns `undefined`.

## 2. config/config.lua (lead) — optional key

```lua
Config.Commands = {
    ...
    interact = 'nzainteract',   -- opens the patient/self interaction menu; false = no command
}
```

core-client reads `Config.Commands.interact` and defaults to `'nzainteract'` when the key is
missing. The keybind `nza_interact` is registered unbound regardless (players bind it in
Settings → Key Bindings → FiveM).

## 3. core-server (please forward)

- **Self snapshot**: add `loss = P.Loss(p)` (0..1). core-client currently derives it from
  `health` (`lossDown × (1 − health/100)`, exact until ~28 % loss) and `fx.tunnel`.
- **`nza:proc:start` response**: add `maxDist = def.maxDist` and optionally `label`. The client
  cancels the minigame at `maxDist + 2 m` (default 3.0 + 2) — the server aborts at `+ 4 m`.
- `nza:damage` reports carry both `belted` (architecture name) and `seatbelt` (the field
  core-server's sanitize reads), plus `armour`, `hits`, `weaponName`, `fatal` which the server
  may ignore.
- After `nza:down` while the player is already down, core-server calls `P.Sync`; core-client
  never sends `nza:down` in that case anyway (only while `alive`, max once per 5 s).

## 4. bodybag module (please forward)

To get `NZA.Interact` options with `bag = true` on body bag props, set on the networked bag
prop: `Entity(bag).state:set('nzaBag', { kind = 'player', sid = src } | { kind = 'npc', net = netId }, true)`.
core-client then resolves the patient from the bag (`NZA.Target.FromEntity(bag)`).
