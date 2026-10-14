# core-server

The authoritative patient engine: patient store and API, physiology tick, damage → injuries,
treatments and procedure sessions, staff permissions, callbacks, treatment records, admin
commands, exports and drop-in compatibility. Implements ARCHITECTURE §4–§7, §12, §13, §17.

## Files

| File | What it does |
|---|---|
| `server/core/base.lua` | `NZA.Core` helpers: pcall-guarded bridge calls, identifiers, admin check, server-side coords, rate limits, toasts, item checks. Installs the single bridge player hook and fans it out on the bus (`player:loaded`, `player:unloaded`, `player:job`). |
| `server/core/injury.lua` | `NZA.Injury` factory: builds complete injuries (size, retained fragments, fracture / burn / internal detail) and derives complications. |
| `server/core/patients.lua` | `NZA.Patients` store + full §4.1 API, snapshots, state bags, self pushes, watchers, persistence (`nza_patients`), NPC lifecycle. |
| `server/core/physiology.lua` | `NZA.Physiology` 1 s tick (§6). |
| `server/core/damage.lua` | `nza:damage` / `nza:down` handlers, `NZA.Damage`. |
| `server/core/treat.lua` | `NZA.Treat` registry + `nza:treat` callback. |
| `server/core/proc.lua` | `NZA.Proc` registry + procedure sessions. |
| `server/core/staff.lua` | `NZA.Staff` permissions, `nza:staff:update`. |
| `server/core/callbacks.lua` | `nza:patient:get`, `nza:patient:watch`, `nza:self:get`, `nza:records:get`, `NZA.Core.CanView`. |
| `server/core/records.lua` | `NZA.Records` → `nza_records`. |
| `server/core/admin.lua` | `/revive`, `/heal`, `/injure`, `/kill` (names from `Config.Commands`). |
| `server/core/exports.lua` | Server exports + compatibility events. |
| `locales/en/core.lua` | `core.*`, `region.*`, `injury.*`, `cond.*` strings (+ bone/organ/vessel/rhythm/AVPU labels, NPC name lists). |

No file calls another core file at load time; every cross-file call happens at runtime, so the
folder works in any glob order (the smoke test loads it forwards and backwards).

## Features

### Patients (players and NPCs, identical data)
- Players load from `nza_patients` on `Bridge.OnPlayerLoaded`; a fresh record gets a weighted
  random blood type, sex / name / age from `Bridge.GetCharInfo`, blood volume by sex.
- Saved when changed (every `Config.Persistence.saveInterval` s), on leave / character switch,
  on resource stop and txAdmin shutdown. Injuries, conditions, devices, infusions, meds and the
  `wounded` / `arrest` / `dead` state survive relogs and restarts (combat-logging does not heal you).
  Transient meta (`carried, stretcher, bay, bed, inBed, bodybag, vehicle, seat, escort, recovery,
  ventilated`) is dropped on load.
- Resource restart with players online: every online player with a loaded character is reloaded.
- `Config.Persistence.offlineHeal`: treated injuries keep healing for the time spent offline.
- NPC patients: `CreateNPC(opts)` with injuries / conditions / devices / meds / state / loss; removed
  automatically when the ped is deleted (`entityRemoved`) or missing for 60 s (`meta.keep = true` prevents it).

### Injuries
- Defaults from `NZA.Const.InjuryTypes`: `bleedBase = bleed[sev] × region lethal × Config.Physiology.timeScale`
  (±10 %), pain, contamination; internal organs and femur/pelvis fractures have their own multipliers.
- Wound length/depth (mm) by type and severity, `spot` on the region, gunshot `exit` flag.
- Retained bullets / fragments by the type's chance (`retained`, `retainedDepth`); a wound with a
  retained projectile cannot heal past 60 % until `treat.extracted`.
- `fracture = { kind = closed|open|comminuted, bone, displaced, angle }` (bones per region, localized as `core.bone_*`).
- `burn = { degree, area, temp, soot, full, exposure }`; burn severity derives from degree × area.
- `internal = { organ, vessel }` (organs per region, localized as `core.organ_*` / `core.vessel_*`).
- Complications (skip with `def.complications = false`):
  penetrating chest/back → haemothorax (40 % of the wound's bleeding moves into the chest),
  pneumothorax (tension chance at sev ≥ 3), tamponade (chest GSW/stab sev ≥ 3);
  penetrating abdomen/pelvis/back → separate `internal` injury (40 % of the bleeding);
  pelvic fracture → pelvic internal bleed; rib fractures → pneumo/haemothorax;
  spine fractures → `spinal`; skull fracture / head trauma → `concussion`;
  face/neck penetrating or burns → `airway` swelling.

### Physiology (1 s tick, healthy patients skipped)
- Bleed per injury × modifiers: tourniquet on that limb segment or the segment above ×0, bandaged ×0.35,
  packed ×0.25, sutured ×0.05, dressed ×0.5 (burn ×0.3), grafted ×0.1, coiled ×0, splint/cast on
  fractures ×0.5, reduced ×0.7, binder on pelvis / pelvic / femoral ×0.4, TXA ×0.6, × dilutional and
  hypothermic coagulopathy, × perfusion (MAP vs the patient's baseline; arrest ×0.15, CPR ×0.35),
  × (1 − heal %). Internal bleeds ignore bandages/tourniquets on the skin (only coil, surgical repair
  `sutured`, `packed`, binder, TXA). Haemothorax bleeding adds to the total.
- Natural clotting: wounds under a dressing and small (sev ≤ 2) abrasions / lacerations / burns /
  shrapnel slowly stop.
- Blood & saline lost in proportion; infusions flow at `rate` mL/min (pause when the last IV/IO is
  removed), saline decays `Config.Physiology.fluidDecay`/min, refrigerated blood and room-temp saline
  cool the patient (unless `warm`), incompatible blood (detected from `bag.type`) → transfusion reaction.
  Blood regenerates 6 mL/min while alive and not bleeding (×4 in bed).
- `loss% = 1 − (blood + 0.35 × fluid) / bloodMax` → ATLS curves for HR / SBP / DBP / MAP / RR.
- Chest: haemothorax `ml` (a drain on that side removes 180 mL/min, `output` accumulates), pneumothorax
  size and tension `pressure` (0.55 / s, 100 = arrest; needle decompression = set `tension = false`),
  tamponade `ml` (350 mL = PEA arrest).
- Airway: drowning water and smoke (cleared by coughing / oxygen / CPR), airway swelling closes the
  airway unless intubated, unconscious patients snore (unless `meta.recovery`), gurgling with water,
  facial bleeding or vomiting drunks.
- Drugs: opioid / stimulant / alcohol overdose; morphine stacking → opioid toxicity; naloxone reverses
  and blocks morphine; adrenaline raises HR/BP; transfusion reaction.
- Temperature: blood loss, exposure while down, water (`meta.wet` until timestamp), arrest, cold
  infusions; foil blanket (0.2 °C/min) and hospital bed (0.25 °C/min) rewarm; fever from infection.
  `hypothermia` condition below 35 °C.
- Infection: contamination of uncovered open wounds grows (faster with retained fragments / wet);
  ≥ 85 on a wound older than 10 min → `infection { region, level }` → fever, tachycardia, sepsis
  hypotension; antibiotics clear it.
- Pain from injuries (minus splint/cast, cooling, dressings, lidocaine on anesthetized wounds) + tourniquets
  + conditions, minus painkillers (−20) and morphine (−45).
- Vitals are smoothed (τ ≈ 4 s) with small jitter. Rhythm: sinus / stach / sbrady / afib (deep
  hypothermia); in arrest VF / VT / PEA / asystole chosen by cause (headshot/trauma/electrocution → VF,
  hypoxia/drowning/opioids → PEA/asystole, tension/tamponade → PEA, hypovolaemia → PEA); without CPR
  VT → VF (90 s) → asystole (240 s), PEA → asystole (300 s). `vitals.ecgRate` gives the monitor rate
  while `vitals.hr` is the palpable pulse (0 in arrest).
- AVPU, pupils (`normal sluggish pinpoint dilated unequal fixed`), breathing, airway descriptors.
- State machine (§6): `alive → wounded` at `Config.Wounded.lossDown` or AVPU ≤ P (players go straight
  to arrest when `Config.Wounded.enabled = false`); `→ arrest` at `arrestLoss`, MAP < `arrestMap` or
  SpO2 < `hypoxiaArrest` for `arrestDelay` s, tension pressure 100, tamponade 350 mL, temp < 28 °C,
  stimulant overdose; `→ dead` at `deathLoss` (any state), after `Config.Death.arrestToDeath` s of
  arrest (paused while CPR is in progress: `lastCpr` within 4 s), or when the bleed-out clock hits 0
  while bleeding (`Config.Death.bleedOutDeath`, otherwise arrest). 20 s post-ROSC grace before the
  blood-loss arrest rule applies again.
- Bleed-out clock: starts at `clamp(time-to-death, minClock, maxClock)` when going down; runs in real
  time while bleeding ≥ 10 mL/min and proportionally slower for a minor ooze (down to 0.25×,
  `clockRate` in the self snapshot); never exceeds the physiological time-to-death (after the first
  `minClock` seconds, during which blood loss is capped so the minimum is honoured); treatment that cuts
  the bleed gives part of the time back; frozen while `stabilized`.
- Healing: definitively treated injuries gain `Config.Physiology.healRate`/min (×4 with `meta.inBed`,
  ×0.25 in an infected region, fractures ×0.6 without a cast), contusions and minor abrasions heal on
  their own; removed at 100. Concussion grades settle with rest; spinal injuries resolve once no spine
  fracture remains (faster with a collar).
- GTA health: the self snapshot carries `health` (0–100 from blood loss vs `lossDown`) and
  `syncHealth` = `Config.Physiology.syncHealth`; core-client applies it.

### Damage (`nza:damage`, `nza:down`)
- Weapon hash → `Config.Damage.weapons[name]` (compared via `joaat`, signed/unsigned safe; `false` = no
  injury, `'hypoxia'` = drowning) → weapon group hash sent by the client (`group`) →
  `Config.Damage.groups[GROUP_*]`. Severity from `Config.Damage.severityByDamage`; below `minDamage` nothing.
- Melee picks one type (fractures need severity ≥ 3); guns add secondary types at 40 %; explosions /
  heavy / thrown / vehicles spread to 1–3 extra regions.
- Spine hits reported as `chest` become `back` when the attacker is behind the victim (server coords).
- Falls (`fall` metres): leg fractures from `fractureHeight`, pelvis/spine/head/internal/wrist with height.
- Crashes (`speedDrop` km/h ≥ `minSpeedDrop`, × `seatbeltFactor` when `seatbelt`): chest, face
  (unbelted), head, neck/spinal, legs, internal, ribs, pelvis.
- Fire (`fire = true` per tick): the burn on that region grows (area, degree by exposure, temperature,
  soot, full thickness) instead of stacking; smoke inhalation.
- Drowning: +60 mL water per report, `meta.wet` for 10 min.
- Head/neck gunshot severity ≥ 3 → instant arrest with `Config.Damage.headshotArrest` chance (not while
  downed with `Config.Wounded.invincible`). Without invincibility, severity-4 head/neck/chest trauma to a
  downed patient may stop the heart.
- Up to 12 injuries as separate wounds; contusions, abrasions, fractures, burns always merge per region;
  past 12 everything merges (worse severity, more bleeding capped at 1.5× the type's severity-4 bleed,
  soaked dressings removed, extra retained fragments).
- Rate limit 25 reports/s, all numbers clamped. `nza:down` sets `wounded` (or `arrest` when blood loss is
  already past `arrestLoss`), records `p.cause = { reason, weapon, attacker, region, at }`, and gives the
  patient an injury if none were reported.

### Treatments, procedures, staff
- See the headers of `treat.lua`, `proc.lua`, `staff.lua` for the full definition tables.
- Treatment checks: action → rate (400 ms) → patient → self/kind/state → permission → server distance
  (`maxDist` + 1 m) → items (table or function) → handler → consume → `treat:done` → record.
- Procedures: one session per medic, one session of the same procedure per patient, `minTime` (easy
  mode: `easyTime`) and `maxTime` on the server clock, score clamped 0–100 (easy = `Config.EasyMode.score`),
  items consumed at start or finish, aborted on patient death/removal, medic leaving, moving > `maxDist`
  + 4 m away, timeout.
- Staff: default resolver = framework job → `Config.DefaultPerms[grade]` (highest lower grade), police →
  `Config.PolicePerms`, everyone → `Config.PublicPerms`, admins → everything (+ `builder`).
  `Config.Jobs.requireDuty` strips job perms off duty. The record's `perms` are the effective perms.

## Config keys used

`Config.Debug, Locale, Jobs (medic, police, requireDuty), PublicPerms, PolicePerms, DefaultPerms,
Admin (ace), Commands (revive, heal, injure, kill), Damage (all keys), Physiology (tick, timeScale,
bloodMax, deathLoss, arrestLoss, arrestMap, arrestDelay, hypoxiaArrest, fluidDecay, healRate,
examDistance, watchRate, syncHealth), Wounded (enabled, lossDown, maxClock, minClock, stableBleed,
invincible), Death (arrestToDeath, bleedOutDeath), EasyMode (default, score), Persistence (enabled,
saveInterval, offlineHeal), Items (via modules)`.

Optional (not in config.lua yet, defaults on): `Config.Physiology.infection = false` disables wound
infections, `Config.Physiology.hypothermia = false` disables temperature simulation.

## Events

| Event | Dir | Payload | Notes |
|---|---|---|---|
| `nza:damage` | C→S | `{ weapon, group, bone, region, damage, attacker, attackerNet, melee, fall, speedDrop, seatbelt, fire, drown }` | `group` = weapon group hash (or `'GROUP_*'` string) |
| `nza:down` | C→S | `{ weapon, group?, attacker, region }` | |
| `nza:proc:abort` | C→S | `token` | |
| `nza:self:update` | S→C | self snapshot | ≤ every 500 ms, only when changed |
| `nza:patient:update` | S→C | `pid, snapshot` | `snapshot = nil` → the watch ended (moved away / lost permission / patient gone) |
| `nza:staff:update` | S→C | staff record | |
| `nza:revived` | S→C | `{ full, reason }` | only when the player ends up `alive` (ROSC → `wounded` is a state change, not a revive) |
| `nza:proc:aborted` | S→C | `token, reason, msg` | server ended a session (`timeout too_far patient_state no_patient`) |
| `nza:ui:toast` | S→C | `{ title, message, type, duration }` | via `NZA.Notify` |
| `chat:addSuggestion` | S→C | | admin commands, sent to admins |

Callbacks: `nza:patient:get (target)`, `nza:patient:watch (target, on)`, `nza:self:get ()`,
`nza:treat (action, target, payload)`, `nza:proc:start (name, target, payload)`,
`nza:proc:finish (token, result)`, `nza:staff:get ()`, `nza:records:get (target, limit)`.

Bus (server): `player:loaded (src)`, `player:unloaded (src, reason)`, `player:job (src, job)`,
`patient:created (p)` (NPC created or player loaded), `patient:removed (pid, reason)` (NPC removed or
player unloaded), `injury:added|updated (p, inj)`, `injury:removed (p, id)`,
`state:changed (p, old, new, reason)`, `patient:arrest (p)`, `patient:death (p)`,
`patient:revived (p, opts)`, `condition:changed (p, name, value)`, `device:changed (p, name, value)`,
`infusion:started|stopped|done (p, inf)`, `med:given (p, name, opts)`, `treat:done (src, p, action, result)`,
`proc:started (src, p, name, session)`, `proc:done (src, p, name, outcome)`,
`proc:aborted (src, p, name, reason)`, `staff:changed (src, record, old)`.

## State bag `nza` (§4.3)

`{ pid, st, avpu, bleed 0..3, stab, clock, inj, tri, tags, tq, splints, binder, collar, iv, intub, bag,
carried, stretcher, name, npc? }`. `clock` = bleed-out seconds while wounded, seconds left before death
while in arrest, 0 otherwise. `bag / carried / stretcher` come from `meta.bodybag / meta.carried /
meta.stretcher` — set them with `NZA.Patients.SetMeta(pid, key, value)`.

## Snapshots
- `summary` = the state bag table.
- `medic` = every Patient field except `watchers`, injuries as an array (severity desc, then bleed),
  `triage = { level, code, label, colour }`, `bleedTotal`, `bloodPct`, `lossPct`, `clockText`.
- `self` = `{ pid, state, clock, clockRate, arrestLeft, downAt, deadAt, stabilized, bleeding 0..3, pain,
  avpu, health, syncHealth, injuries = { id, region, type, severity, status, bleeding, label, regionLabel },
  conditions (perceptible names), meds (active names), devices (worn), fx = { limp, shake, blur, tunnel,
  cold, breathless, drunk }, bloodType, name }`.

## API additions beyond §4.1 (all documented in file headers)

`NZA.Patients.SetMeta, Cpr(pid, src, quality), CanStand(pid), RegisterMed(name, fn(p, opts)),
MedActive(p, name), Loss(p), Ped(p), Coords(p), LoadPlayer, UnloadPlayer, Touch(p, deep), Flush, RT`;
`SetDevice(pid, name, key, value)` single-key form for `tourniquet / splints / chestDrain` (map devices
merge; a `false` value removes the key; `nil` clears the map); `SetCondition(pid, 'arrest', {...})` on a
living patient puts them in arrest (clearing it in arrest is ignored — use `Revive(pid, { rosc = true })`).
`NZA.Physiology.*`, `NZA.Damage.*`, `NZA.Injury.*`, `NZA.Treat.Run/Get/List`,
`NZA.Proc.Start/Finish/Abort/Get/Session/Active`, `NZA.Staff.Easy/Refresh/RefreshAll`,
`NZA.Records.Add/Get`, `NZA.Notify(src, msg, type, title, duration)`, `NZA.Core.*`.

Meta keys core reads: `inBed` (×4 healing, rewarming), `bay`, `bed` (view rules), `wet` (timestamp),
`recovery` (no snoring), `ventilated` + `ventRate` (BVM / ventilator on an intubated patient),
`cprQuality` (0–100, EtCO2 / pressures during CPR), `keep` (NPC survives ped deletion),
`bodybag`, `carried`, `stretcher` (state bag).

## Exports

`GetPatient(src)`, `GetPatientByPid(pid)`, `IsDowned(src)` (wounded/arrest/dead), `IsDead(src)`
(arrest/dead), `GetState(src)`, `Revive(src, full)`, `Heal(src)`, `AddInjury(src, region, type, severity)`
→ id, `GetVitals(src)`, `GetInjuries(src)`, `CreateNPCPatient(opts)` → pid, `GetTriage(src)`,
`SetPatientMeta(pid, key, value)`.

Compatibility: `hospital:server:RevivePlayer` (admin or medic on duty within 10 m),
`esx_ambulancejob:revive` (admin only), `esx_ambulancejob:heal`, `wasabi_ambulance:revive`,
`wasabi_ambulance:revivePlayer` (admin or medic on duty); `hospital:server:SetLaststandStatus /
SetDeathStatus / SetArmor` are accepted and ignored. Server-originated triggers are trusted.

## Database

```sql
CREATE TABLE IF NOT EXISTS `nza_patients` (
  `identifier` VARCHAR(64) NOT NULL,
  `data` LONGTEXT NOT NULL,
  `state` VARCHAR(16) NOT NULL DEFAULT 'alive',
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nza_records` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL,
  `medic` VARCHAR(64) NOT NULL DEFAULT 'system',
  `medic_name` VARCHAR(64) NULL,
  `action` VARCHAR(64) NOT NULL,
  `summary` LONGTEXT NULL,
  `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## Notes for other modules
- **core-client**: handle `nza:proc:aborted (token, reason, msg)` in `NZA.Proc.Run`; treat
  `nza:patient:update (pid, nil)` as "watch ended"; request the staff record with `nza:staff:get` on
  client start (the server also pushes it on load and 3 s after a resource start); apply
  `self.health` when `self.syncHealth`; use `self.fx` for limp / shake / blur / tunnel / cold effects;
  `vitals.ecgRate` drives the ECG trace in arrest.
- **cpr**: call `NZA.Patients.Cpr(pid, src, quality)` on compressions (pauses the arrest timer, sets
  EtCO2); ROSC = `Revive(pid, { rosc = true })` (post-ROSC vitals are set; 20 s grace).
- **defib**: change rhythm with `SetCondition(pid, 'arrest', { rhythm = 'vf', since = ..., cause = ... })`
  while in arrest; `NZA.Const.Shockable`.
- **iv / blood**: set `devices.iv` / `devices.port` before or after `AddInfusion` (infusions pause with no
  access); pass the bag metadata as `bag` (`bag.type` is checked for compatibility; `warm = true` for
  warmed fluids).
- **chest drain / needle**: `SetDevice(pid, 'chestDrain', side, true)`; needle decompression =
  `SetCondition(pid, 'pneumothorax', { ...existing, tension = false })`.
- **wounded / transport**: `CanStand(pid)` before setting `alive`; `downAt` and `clockRate` are in the
  self snapshot for the give-up timer and UI.

## Known limits
- Healing and infection are game-time compressed (minutes, not days); tune with `healRate`.
- The bleed-out clock is a game timer (see above), so it can end before the blood volume reaches
  `deathLoss`; that is intended (`Config.Death.bleedOutDeath`).
- A `json.encode` failure (a module storing a function or sparse array in `meta`) skips that save with
  a warning instead of crashing.
- NPC records are not written to `nza_records`.
- Smoke-tested in plain Lua with stubbed natives (no live server in this environment).
