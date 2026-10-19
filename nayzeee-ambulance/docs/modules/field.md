# Module: field — field resuscitation, IO / IV access, patient monitor

The trauma kit at the roadside. A medic kneels by a bleeding patient, the camera rises over them,
the open trauma case, a sharps bin and the patient monitor appear beside the body, and the
scene walks through seven server-validated steps. The same module owns the standard IV cannulation
(usable anywhere) and the PM-4 patient monitor that every other module can open.

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

Scene: kneel animation, orbit camera over the pelvis (`NZA.Cam.Orbit`, right-drag turn,
Shift + right-drag slide, wheel zoom), camera views **Body → Access → Drip → Kit**,
cycled with one key (`Config.Field.Keys.focus`, default **Tab**, Shift+Tab back) or clicked in the view strip, props via `NZA.Props` (open kit case, sharps bin, monitor; IV stand,
bags and pressure infuser in step 6).

### Screen layout (NAYZEEE look, see `docs/design/ORIGINAL.md`)

| Zone | What |
|---|---|
| top-left | PM-4 field monitor (monitor app): four status rings + full-width sweeps |
| bottom-left | core procedure column: MAP dial (target arc) + instrument list (bleed / injury / step metric), step card with the 7-node spine and named steps (`opts.steps`), then the VIEW dock (camera keys, in `pp.slot`) and the key legend |
| right-middle, left of the belt | the instrument rack: one unbranded device per step (BT-3 binder tensioner, IO-7 driver with bubble level + bone cross-section + torque trace, SX-10 syringe with draw-back / rate dials, CA-2 clot analyser + PI-3 pressure infuser in step 6, VF-2 vein finder / NC-1 needle cam for IV, handover card in step 7). Model codes, serials and warning stickers only — no brand |
| right edge | core tool belt with an explicit `tool.icon` per tool (cuff, drill, needle, syringe, tube, drop, iv, bloodbag, blanket, gauge) + the hold-to-cancel ring |
| scene | diamond markers with dark chips (*Under the hips*, IO sites, *IO needle*), the strap track with the tension ring, the IO aim reticle; nothing bottom-centre |

Devices slide in from the right edge, values roll (odometer counters), rings fill and the current
step node pulses. Everything fits at 1920×1080 and 1280×720 (the rack scales with `--nza-zoom`).

| # | Step | Server | Interaction |
|---|---|---|---|
| 1 | Bind the pelvis | `NZA.Proc 'binder'` (item `pelvic_binder`) | pick the binder up at the kit and let go over the *Under the hips* marker → `binder_flat` under the patient; grab the strap handle and draw it across the hips, release when the BT-3 ring turns teal (60–80 %, too slack / over-tight retries). → `devices.binder`, pelvic base bleed × (1 − 0.25 × quality), over-tight = pain; every client attaches `binder_worn` to SKEL_Pelvis from the state bag |
| 2 | Pick the IO site | `NZA.Proc 'io'` (item `io_kit`) | four anchored markers (L/R proximal tibia, L/R humeral head); fractured bones, a tourniquet above, deep burns or wounds are contraindicated (red) and refused by the server |
| 3 | Drive the needle | (same session) | the IO driver prop follows the mouse; centre the bubble in the IO-7 level ring (off level = cursor offset from the site, < 15°); press Click to seat the needle on the skin, hold Space to drive it; the needle cam shows tissue / bone wall / marrow / back wall rings, the list shows off level, depth, tip layer, contact, the torque trace drops when it gives way; hand drift in the bone wall; > 26° there bends the needle, out the back = through-and-through → *R* fresh needle (`io_needle` treat, max `IO.attempts`) |
| 4 | Draw back | | drag the SX-10 plunger up; the return dial fills to 1 ml and turns red when marrow comes back |
| 5 | Flush the line | | 1 extension line → 2 lidocaine 2 % (2 ml, keep the needle in the 0.08–0.45 ml/s arc) → 3 flush syringe (10 ml saline, 1.5–6 ml/s); too quick / no lidocaine on an awake patient = pain speech + score. → `devices.iv = { kind = 'io', site }`, lidocaine item used when carried |
| 6 | Hold the pressure | `NZA.Proc 'resus'` + treats | IV stand + PI-3 pressure infuser: 1 hang saline 0.9 % (`infuse`), 2 hang a blood unit (`NZA.Blood.TakeBag`, match shown, untyped/no match need a second press; locked without the blood module), clamp (Q/E, −/+, vertical clamp gauge), pump the bulb (Space, cuff pressure dial 0–300 mmHg, leaks), the flow is sent with `infuse_rate`, 3 TXA 1 g slow push (compact syringe with a rate bar, ≥ 10 s, `txa`), 4 warming foil (`field_foil` → first aid's `fa_foil`), 5 pump bulb, 6 read BP. Keep the MAP on the target arc while the clot sets (CA-2: segmented clot ring, MAP / hold / TXA / warmth / dilution / breaks list, MAP trend strip, break warning) |
| 7 | Recheck | `NZA.Treat 'field_report'` | handover card: start → now (bleed, MAP, HR, SpO₂) with trend arrows, a ring per step with its score, device chips; Finish (Enter) writes the record and ends the scene |

Steps that are done (binder on, line in) or not allowed are skipped with a note; a step that can't
start (missing item) shows why and waits for *N Continue*. **Easy mode** (per department / perm):
every step is the core progress bar; the resuscitate step then hangs one saline bag (item reserved)
and forms the clot at `Config.EasyMode.score`.

### The pressure / clot model (server, authoritative)

Every second while a `resus` session runs: `response += (Σ rate × Resus.response[kind] − response)
× (1 − e^(−dt/tau))`. The response goes onto the core vitals with
`NZA.Physiology.SetModifier(pid, 'field_resus', { sys = response × 1.3, dia = response × 0.85, ttl = 3 })`
(cleared on finish / abort), so the field MAP is the patient's MAP on every monitor and HUD, and the
model reads it back from the vitals. Clot firmness rises at
`100 / Resus.hold` %/s × speed: band 1, below band 0.35, under `lowMap` 0, above the band because of
your fluids 0.25 (above the band on the patient's own pressure 0.8 — no fluids needed), × TXA 1.3,
cold without foil 0.6 (with foil 0.85), dilution 0.7. MAP more than `popMargin` above the band from
your fluids for `popAfter` s pops the clot: firmness 0, target injuries' base bleed × `popFactor`
(capped at `maxPop` × the start). Finishing needs 100 %: target injuries' base bleed ×
(1 − `clotFactor` × quality); `meta.fieldClot` is set. The client gets `nza:field:resus` each second
(clot panel); the monitors need no override.

## IV cannulation (patient option *IV cannulation*, order 44)

`NZA.Proc 'iv'` (perm `iv`, item `iv_kit`), close-up on the forearm (the server picks a free arm).
1 tourniquet on (prop on the upper arm, veins fill) → 2 feel for a vein on the VF-2 vein finder
(hold Click, rebound meter; the straight, springy vein is best) → 3 needle in: set 15–30° (wheel /
↑↓, angle dial in the column) and hold Space; the NC-1 needle cam shows the tip, the flash chamber
fills when it is in the lumen; too shallow / too steep misses, keep pushing = through the back wall
(vein gone, new attempt up to `IV.attempts`) → 4 hold E to slide the cannula home → 5 tourniquet
off (1) and drag the needle out → 6 dressing (3) + flush (4). → `devices.iv = { kind = 'iv', site, gauge }`. Used by the blood module's
*Place an IV first* (it calls the `nza_field_iv` option).

## Patient monitor (`NZA.Monitor`, NUI app `monitor`)

The PM-4 field monitor (top-left by default, unbranded: model code, carry handle, LEDs, a
*Defib-proof leads only* sticker): a row of four status rings (HR, SpO₂, NIBP with sys/dia + MAP,
RESP with EtCO₂) with limit and zone marks, full-width ECG / PLETH / CO₂ sweeps with an erase bar
(`NZA.vitals`), a footer with temperature, EtCO₂ and the NIBP age / auto timer; alarm chip
(Arrest · rhythm, SpO₂ low, Pressure low, No breathing, Heart rate high / low, Breathing fast,
EtCO₂ low, Body temp low) with tones; hardware buttons power (standby), silence alarms
(`Monitor.silence` s), measure BP now, display size. NIBP is intermittent (auto every
`Monitor.nibpAuto` s, cuff animation), the rest is live. The prop's DUI screen
(`screen.html`, 512×256) uses the same ring row and sweeps, with no brand.

```lua
-- any module (bay, bed, CPR, intubation …)
NZA.Monitor.Open(target, { compact = true, position = 'tl'|'tr'|'bl'|'br', label = 'Bay 2' })
NZA.Monitor.Close()
-- or directly, without focus:
NZA.UI.Open('monitor', { target = target, compact = true }, { focus = false })
NZA.UI.Send('monitor', 'nibp', {})                  -- cycle the cuff
NZA.UI.Send('monitor', 'override', { map, sys, dia }) -- or false (generic display override, unused by this module)
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

`Keys` (drill, advance, clampDown, clampUp, squeeze, insert, focus), `Interact` (distance, toggles,
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
| NUI `field:*` | callbacks | result skip abort done close focus binderDrop phase drill needle hang rate takedown txa foil nibp bags ivTq (`bags` is posted when the resus step starts and answers with a `bags` message: fresh saline / TXA / foil counts and blood bags) |
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
