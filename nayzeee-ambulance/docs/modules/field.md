# Module: field — field resuscitation, IO / IV access, patient monitor

The trauma kit at the roadside. A medic kneels by a bleeding patient, the camera rises over them,
the open NAYZEEE trauma case, a sharps bin and the patient monitor appear beside the body, and the
scene walks through seven server-validated steps. The same module owns the standard IV cannulation
(usable anywhere) and the NAYZEEE patient monitor that every other module can open.

## Files

| File | What |
|---|---|
| `config/modules/field.lua` | `Config.Field` (keys, menus, binder, IO, IV, infusion, TXA, foil, monitor, billing) |
| `locales/en/field.lua` | every string (`field.*`, NUI keys use `{name}` placeholders) |
| `server/modules/field.lua` | helpers, callbacks `nza:field:plan` / `nza:field:bags`, treats `infuse` `infuse_rate` `infuse_stop` `txa` `field_foil` `io_needle` `binder_off` `iv_off` `monitor` `monitor_off` `field_report`, usable items |
| `server/modules/field_procs.lua` | procedures `binder` `io` `iv` `resus` + the server pressure / clot model |
| `client/modules/field.lua` | helpers, worn binder, patient options, exam routes, radial items, item use |
| `client/modules/field_scene.lua` | the 7-step scene (`NZA.Field.Start`) and IV cannulation (`NZA.Field.StartIV`) |
| `client/modules/field_monitor.lua` | `NZA.Monitor` (overlay, live data, prop + DUI screen) |
| `html/apps/field/` | NUI app `field` (resus + IV modes) |
| `html/apps/monitor/` | NUI app `monitor` + `screen.html` / `screen.js` (prop screen DUI) |

## Field resuscitation (patient option *Field resuscitation*, order 31)

Shown to medics with any perm of `Config.Field.Resus.perms` (`iv`, `binder`) who carry
`Config.Items.trauma_kit`, for patients alive/wounded with state-bag bleed ≥ `Interact.resusBleed`
(or any bleed and no line). Also an exam route (`field_resus`: heavy, internal or pelvic injuries),
a radial entry (Patient → Field resuscitation) and using the trauma kit item.

Scene: kneel animation, orbit camera over the pelvis (`NZA.Cam.Orbit`, right-drag orbit,
Shift + right-drag pan, wheel zoom), focus keys **F1 patient · F2 site · F3 IV stand · F4 kit**
(`Config.Field.Keys.focus`), props via `NZA.Props` (open kit case, sharps bin, monitor; IV stand,
bags and pressure infuser in step 6), monitor overlay top-left, NAYZEEE device top-right,
the kit ProcPanel (MAP dial with the 60–70 target zone + bleed / injury / step metric).

| # | Step | Server | Interaction |
|---|---|---|---|
| 1 | Pelvic binder | `NZA.Proc 'binder'` (item `pelvic_binder`) | drag the binder from the kit onto *Drop the binder here* (pelvis) → `binder_flat` under the patient; pull the strap tab across the body, release inside 60–80 % (too loose / too tight retries). → `devices.binder`, pelvic base bleed × (1 − 0.25 × quality), over-tight = pain; every client attaches `binder_worn` to SKEL_Pelvis from the state bag |
| 2 | Choose IO site | `NZA.Proc 'io'` (item `io_kit`) | four anchored markers (L/R proximal tibia, L/R humeral head); fractured bones, a tourniquet above, deep burns or wounds are contraindicated (red) and refused by the server |
| 3 | Drill | (same session) | the IO driver prop follows the mouse; off-axis angle = cursor offset from the site (< 15°); hold Click to press onto the skin, hold Space to drill; device shows soft tissue / cortex / marrow / far cortex, depth, tip layer, resistance trace; hand drift in the cortex; > 26° in the cortex bends the needle, past the far cortex = through-and-through → *R* new needle (`io_needle` treat, max `IO.attempts`) |
| 4 | Confirm | | drag the syringe plunger back; marrow blood flashes in the barrel |
| 5 | Flush | | 1 extension set → 2 lidocaine 2 % (2 ml, push in the 0.08–0.45 ml/s band) → 3 saline flush (10 ml, 1.5–6 ml/s); too fast / no lidocaine on an awake patient = pain speech + score. → `devices.iv = { kind = 'io', site }`, lidocaine item used when carried |
| 6 | Resuscitate | `NZA.Proc 'resus'` + treats | IV stand + pressure infuser: 1 hang saline 500 ml (`infuse`), 2 hang blood (`NZA.Blood.TakeBag`, compatibility shown, untyped/incompatible need a second press; locked without the blood module), roller clamp (Q/E, −/+), squeeze the infuser (Space, gauge 0–300 mmHg, leaks), the flow is sent with `infuse_rate`, 3 TXA 1 g slow push (syringe ≥ 10 s, `txa`), 4 foil blanket (`field_foil` → first aid's `fa_foil`), 5 squeeze, 6 cycle NIBP. Keep the MAP in the band while the clot firms (device: clot firmness, TEG-style curve, MAP strip, pop warning) |
| 7 | Reassess | `NZA.Treat 'field_report'` | before / now (bleed, MAP, HR, SpO₂), grades of every step, devices; Enter writes the record and ends the scene |

Steps that are done (binder on, line in) or not allowed are skipped with a note; a step that can't
start (missing item) shows why and waits for *N Continue*. **Easy mode** (per department / perm):
every step is the core progress bar; the resuscitate step then hangs one saline bag (item reserved)
and forms the clot at `Config.EasyMode.score`.

### The pressure / clot model (server, authoritative)

Every second while a `resus` session runs: `response += (Σ rate × Resus.response[kind] − response)
× (1 − e^(−dt/tau))`, field MAP = real MAP + response (sys/dia scaled). Clot firmness rises at
`100 / Resus.hold` %/s × speed: band 1, below band 0.35, under `lowMap` 0, above the band because of
your fluids 0.25 (above the band on the patient's own pressure 0.8 — no fluids needed), × TXA 1.3,
cold without foil 0.6 (with foil 0.85), dilution 0.7. MAP more than `popMargin` above the band from
your fluids for `popAfter` s pops the clot: firmness 0, target injuries' base bleed × `popFactor`
(capped at `maxPop` × the start). Finishing needs 100 %: target injuries' base bleed ×
(1 − `clotFactor` × quality); `meta.fieldClot` is set. The client gets `nza:field:resus` each second
and the monitor shows that pressure (`NZA.Monitor.Override`).

## IV cannulation (patient option *IV cannulation*, order 44)

`NZA.Proc 'iv'` (perm `iv`, item `iv_kit`), close-up on the forearm (the server picks a free arm).
1 tourniquet (prop on the upper arm, veins fill) → 2 palpate the forearm on the vein viewer (hold
Click, bounce meter; the straight, springy vein is best) → 3 set the angle 15–30° (wheel / ↑↓) and
hold Space: flashback in the chamber when the tip is in the lumen; too flat / too steep misses,
keep pushing = through the back wall (blown vein, new attempt up to `IV.attempts`) → 4 hold E to
slide the cannula off the needle → 5 release the tourniquet (1) and drag the needle out → 6 dressing
(3) + flush (4). → `devices.iv = { kind = 'iv', site, gauge }`. Used by the blood module's
*Place an IV first* (it calls the `nza_field_iv` option).

## Patient monitor (`NZA.Monitor`, NUI app `monitor`)

A rugged NAYZEEE monitor (top-left by default): ECG / PLETH / CO₂ traces (`NZA.vitals.Monitor`),
HR, SpO₂, NIBP sys/dia + MAP, RR, EtCO₂, temperature; alarm banner (ARREST · rhythm,
DESATURATING, HYPOTENSION, APNOEA, TACHY-/BRADYCARDIA, TACHYPNOEA, LOW EtCO₂, HYPOTHERMIA) with
tones; side buttons power (standby), alarm silence (`Monitor.silence` s), cycle NIBP, display size.
NIBP is intermittent (auto every `Monitor.nibpAuto` s, cuff animation), the rest is live.

```lua
-- any module (bay, bed, CPR, intubation …)
NZA.Monitor.Open(target, { compact = true, position = 'tl'|'tr'|'bl'|'br', label = 'Bay 2' })
NZA.Monitor.Close()
-- or directly, without focus:
NZA.UI.Open('monitor', { target = target, compact = true }, { focus = false })
NZA.UI.Send('monitor', 'nibp', {})                  -- cycle the cuff
NZA.UI.Send('monitor', 'override', { map, sys, dia }) -- or false
NZA.Monitor.Attach(entity, target)  /  NZA.Monitor.Detach()   -- device on the patient (+ prop, DUI screen)
NZA.Monitor.Focus(true|false)       -- mouse on the monitor buttons (command Monitor.command / key Monitor.focusKey)
```
Patient options *Attach patient monitor* (25) / *Remove patient monitor* (26), radial *Patient
monitor*. The prop gets a live DUI screen (`html/apps/monitor/screen.html`, texture
`Config.PropScreens.monitor`). The overlay hides beyond `Monitor.range` and comes back; the prop
stays with the patient until they are moved. The bay's F4 (`bay:monitor`) toggles this monitor.

## Other patient options

*Remove pelvic binder* (48, perm binder; gives the binder back, restores the pelvic bleed reduction,
warns while the pelvis still bleeds) · *Remove IV / IO line* (49, running bags pause).

## Config keys (`Config.Field`)

`Keys` (drill, advance, clampDown, clampUp, squeeze, insert, focus{}), `Interact` (distance, toggles,
resusBleed, icons), `Radial` (enabled, range), `Exam` (enabled, heavyBleed), `Resus` (perms, kit, band,
hold, minTime/maxTime/easyTime, clotFactor, popFactor, maxPop, popMargin, popAfter, lowMap,
response{saline, blood, plasma, tau, own}, speed{below, high, own, txa, cold, foil, dilution,
dilutionAt}, keepMonitor, standKeep, autoContinue, camera, siteCamera, anim, props{kit, sharps,
stand}), `Binder` (perm, item, band, times, bleedBonus, tightPain, removeReturns, attach, worn.range),
`IO` (perm, item, lidocaine, saline, times, maxAngle, bendAngle, attempts, layers, speed, sites,
pxPerDeg, tremor, aspirateMl, lidoMl, lidoRate, flushMl, flushRate), `IV` (perm, item, times, angle,
attempts, gauge, tourniquetFill, sites, flash, camera, anim, tourniquetProp, removeReturns),
`Infusion` (perm, saline, salineMl, blood, bloodMl, gravity, ioFactor, pressureGain, maxPressure,
leak, pump, maxRate, maxBags, warm, dilution), `TXA` (item, perm, push), `Foil` (item), `Monitor`
(perm, requireItem, range, nibpAuto, nibpTime, alarms, silence, prop, place, screen, focusKey,
command, position), `Billing` (binder, io, iv, resus).

## Events, callbacks, exports

| Name | Kind | Payload |
|---|---|---|
| `nza:field:plan` | callback | `(target)` → plan `{ pid, name, injury, bleed, loss, binder{on,indicated,why,perm}, access, ioPerm, resusPerm, band, hold, ioSites, ivSites, maxRate, blood, vitals, counts, easy{binder,io,resus} }` \| `nil, err` |
| `nza:field:bags` | callback | `(target)` → `{ saline, txa, foil, io, iv, bags[], blood, infusions[], txaActive, foilOn }` |
| `nza:field:resus` | S→C | resus model state `{ token, map, sys, dia, response, firm, state, pops, warn, eta, flow, bleed, mods, bags, maxRate, txa, foil }` |
| `nza:field:popped` | S→C | the clot popped |
| `nza:field:use` | S→C | `'resus' \| 'iv'` from the usable trauma kit / IV kit |
| NUI `field:*` | callbacks | result skip abort done close focus binderDrop phase drill needle hang rate takedown txa foil nibp bags ivTq |
| NUI `monitor:*` | callbacks | bind unbind nibp |

Server API: `NZA.Field.*` helpers (`Access`, `BinderIndicated`, `TargetInjuries`, `SiteContra`,
`MaxRate`, `BloodBags`, `Counts`), `NZA.Field.Resus[token]` (live model). Client: `NZA.Field.Start`,
`NZA.Field.StartIV`, `NZA.Monitor.*`.

## Security

Every action is server-side: perms (`NZA.Staff.Can` through Treat/Proc), distance, items, states,
`minTime`, one session per medic. Client scores are clamped and re-derived (binder tension band,
needles counted on the server, attempts, aspiration); flow rates are clamped to what the line can
run (`MaxRate`: gravity × IO factor × infuser); clot firmness is computed only on the server; blood
bags are taken by serial through the blood module; plan/bags callbacks are rate limited and need
view rights (`Core.CanView`).

## Known limits

- The pressure response during step 6 lives in the field module (other medics' monitors show the
  plain physiology MAP) — see `docs/requests/field.md` §2.
- The IO driver pose is approximate (bone position + camera-relative tilt); the needle stays put
  after drilling only as data (no needle prop after the syringe step).
- The IV stand, bags and infuser are local props of the medic who ran the scene (they stay
  `Resus.standKeep` s or until the patient is moved).
