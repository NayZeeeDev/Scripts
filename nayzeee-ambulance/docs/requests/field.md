# Requests from the field module (lead-owned files)

## 1. `html/core/nza.js` — ProcPanel hides the stats when there is no `wide` readout

`renderStats()` always sets `g.className = 'pp-gauge flat'` when `w.meter` is missing — also when
there is no `wide` at all (the gauge is then `display:none`). The CSS rule
`.pp-read .pp-gauge.flat + .pp-stats{display:none}` still matches the hidden gauge, so a panel that
only passes `stats` shows an empty 2 px readout card.

Fix (nza.js, `renderStats`):
```js
g.className = `pp-gauge${w && !dial ? ' flat' : ''}`;
```
The field module always passes a `wide` dial (MAP / needle angle), so it is not affected; other
modules that only pass `stats` are.

## 2. `server/core/physiology.lua` — a short-lived vitals modifier hook (optional, nice to have)

The resuscitate step runs its own pressure model on the server (real MAP + the response to the
fluids actually running, see `server/modules/field_procs.lua`). The field module shows that pressure
on its own monitor (`NZA.Monitor.Override`) but other medics' monitors show the plain physiology MAP.

Proposal: `NZA.Physiology.SetModifier(pid, key, { sys = +n, dia = +n, hr = +n, ttl = seconds })`
applied at the end of `computeVitals` (before smoothing) and dropped after `ttl`. The field module
would then call it every model tick (`key = 'field_resus'`, `ttl = 3`) and the override path could go.

Status: done. The core added `SetModifier`; `server/modules/field_procs.lua` sets `'field_resus'` every
model tick (cleared on finish / abort) and reads the pressure back from the vitals; the client no
longer calls `NZA.Monitor.Override`.

## 3. Notes for other modules (no change needed)

- `NZA.UI.Open('monitor', { target = t, compact = true }, { focus = false })` works from any module;
  the field module binds the live data (see `docs/modules/field.md` → Patient monitor). The bay's
  F4 (`bay:monitor` bus event) is already handled by the field module.
- `devices.iv = { site = region, kind = 'iv'|'io', gauge?, bone? (IO site id), at, by }` is what the
  field module writes; `devices.binder = true` plus `meta.binderQ = { q, tension, by, at }`;
  `meta.fieldClot = { firm, q, pops, at, by }` after a successful resuscitate step.
