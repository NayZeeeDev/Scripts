# Requests from core-integration (lead-owned files)

Nothing here blocks anything; the code already works this way. These bring ARCHITECTURE.md in
line with the implemented core (full detail: `docs/modules/core-api.md`).

## 1. ARCHITECTURE §5.2 — procedure callback payloads

Replace the callback line with:

```
nza:proc:start (name, target, payload) → { ok, token, data, easy, easyTime, minTime, maxTime, maxDist, label, allowDead }
                                       | { ok = false, err, msg }
nza:proc:finish (token, result)        → { ok, outcome } | { ok = false, err, msg }   (outcome has score, grade, easy)
event nza:proc:abort (token)  C→S      event nza:proc:aborted (token, reason, msg)  S→C
```
and note: `easyTime` defaults to `minTime` clamped to 4–10 s (6 s when `minTime` is 0) and is the
easy-mode minimum on the server. `NZA.Proc.Run` returns `true, outcome` or `false, reason`.

Status: done. ARCHITECTURE §18 (first bullet) carries the as-built callbacks.

## 2. ARCHITECTURE §17 — table rows

- add `nza:proc:aborted | S→C | token, reason, msg | core-client (NZA.Proc.Run)`
- `nza:patient:update`: payload `pid, snapshot | nil` (nil = the watch ended)
- `nza:ui:speech`: server helper is `NZA.Core.Speech(src, name, text, ms, extra)`

Status: done. The ARCHITECTURE §17 table has all three rows.

## 3. ARCHITECTURE §4.3 — self snapshot fields

`{ pid, state, clock, clockRate, arrestLeft, downAt, deadAt, stabilized, bleeding, pain, avpu, loss,
health, syncHealth, injuries[{ id, region, type, severity, status, bleeding, label, regionLabel }],
conditions[], meds[], devices{}, fx{ limp, shake, blur, tunnel, cold, breathless, drunk }, bloodType, name }`

Status: done. ARCHITECTURE §18 lists the snapshot fields.

## 4. Core requests repeated from the module files — all resolved

- `config/config.lua`: `Config.Physiology.infection = true`, `Config.Physiology.hypothermia = true`
  (docs/requests/core-server.md §1) and `Config.Commands.interact = 'nzainteract'`
  (docs/requests/core-client.md §2).
  Status: done. `config/config.lua` has `infection` / `hypothermia` in `Config.Physiology` and
  `interact = 'nzainteract'` in `Config.Commands`.
- `html/core/nza.js`: optional `_core` actions `focus` and the `_core:camInput` forwarder
  (docs/requests/core-client.md §1).
  Status: done. `html/core/nza.js` handles `_core` `focus` and forwards right-drag / wheel as
  `_core:camInput` (ARCHITECTURE §18, NUI router bullet).
- Hospital module: the bay feature must set the MEDIC's bay with
  `NZA.Patients.SetMeta(medicPid, 'bay', id)` (server side) — the old `nzaBay` player state bag is no
  longer trusted for `Core.CanView` because clients can write their own state bags.
  Status: done. `server/modules/transport_bay.lua` sets `P().SetMeta(p, 'bay', bay.veh)` on entry and
  clears it on exit (ARCHITECTURE §18).
