# Core API cheat sheet (as implemented)

The exact API of `server/core/*.lua` and `client/core/*.lua` after integration review.
Where this file and `core-server.md` / `core-client.md` disagree, this file is right.
All of it is callable from `server/modules/*` / `client/modules/*` at file top level
(registrations) or later. `p` / `pid` arguments accept a pid string, a Patient table or a
target table everywhere on the server.

Targets (client → server): `{ kind = 'player', sid = serverId }` | `{ kind = 'npc', net = netId }`.
The server also resolves `'p:…' / 'n:…'` pid strings, a server id number, or a Patient table.

---------------------------------------------------------------------------------------

## SERVER

### NZA.Patients (patients.lua)

| Call | Returns | Notes |
|---|---|---|
| `Get(pid)` | Patient \| nil | live table, mutate only via the API |
| `GetBySource(src)` / `GetByNet(net)` | Patient \| nil | |
| `Resolve(target)` | Patient \| nil | target table, pid string, src number, Patient |
| `All()` | `{ [pid] = Patient }` | live store, do not modify |
| `CreateNPC(opts)` | Patient \| nil, `'no_net'` | see opts below; existing pid returned unless `opts.replace` |
| `Remove(pid, reason?)` | bool | NPC: clears bag, ends watches; player: unloads |
| `AddInjury(pid, def, silent?)` | Injury \| nil, err | err `no_patient dead bad_def bad_region bad_type`; `def.force` allows dead |
| `UpdateInjury(pid, id, patch)` | Injury \| nil, err | shallow merge; `treat quality fracture burn internal spot` merge one level; non-table `treat`/`quality` ignored |
| `RemoveInjury(pid, id)` | bool | |
| `SetCondition(pid, name, value)` | stored value | `true` → `{}`, `false/nil` clears; `'arrest'` on a living patient → `SetState('arrest')`; clearing arrest while in arrest is ignored (use `Revive{rosc}`) |
| `SetDevice(pid, name, value)` | stored value | `binder collar intubated oxygen foil monitor iv port …` |
| `SetDevice(pid, map, key, value)` | stored value | map devices `tourniquet splints chestDrain`: table merges, `false` removes key, `nil` clears map; tourniquet `true` → `os.time()` |
| `AddInfusion(pid, inf)` | infusion | `inf = { kind = 'saline'|'blood'|'txa'|'plasma', ml = 500, rate (mL/min), bag, warm, by, id?, left? }` → `{ id, kind, ml, left, rate, bag, warm, started, by, incompatible?, paused? }`; flows at once (callers check IV/IO access themselves); pauses (`paused = 'access'`) when the last `devices.iv`/`port` is removed and resumes when one is set again |
| `StopInfusion(pid, id)` | bool, infusion | |
| `GiveMed(pid, name, opts?)` | ok, info | names `adrenaline naloxone morphine painkillers txa antibiotics lidocaine` (+ registered); `opts.dose`, lidocaine `opts.region / opts.injury`; info `{ msg }` or `{ err }` (`no_patient unknown_med dead`) |
| `RegisterMed(name, fn(p, opts) → ok, info)` | | adds a medication |
| `MedActive(p, name)` | bool | |
| `AddBlood(pid, ml)` | new blood mL | negative removes (donation); capped 110 % |
| `SetState(pid, state, reason)` | bool | `reason` string or table `{ reason, weapon, attacker, region, at }` (stored as `p.cause`); arrest → dead keeps what stopped the heart in `p.cause.arrestCause` and `conditions.arrest.cause` (e.g. reason `'arrest'`, arrestCause `'hypovolemia'`) |
| `Revive(pid, opts)` | bool, err | `{ full = true }` heal all; `{}` patch & stand up; `{ rosc = true }` arrest → wounded (err `not_arrest`); sends `nza:revived` only when the player ends up `alive`; `opts.reason` |
| `Heal(pid, amount = 100)` | bool | heal points to every injury; ≥100 also clears conditions/devices/infusions |
| `CanStand(pid)` | ok, reason | `state bleeding avpu blood condition` |
| `Cpr(pid, src, quality 0..100)` | bool | call on every compression set; pauses the arrest → death timer for 4 s |
| `SetMeta(pid, key, value)` | value | `carried stretcher bodybag bay bed inBed recovery ventilated ventRate bagUntil wet keep …` (state bag resync) |
| `Snapshot(pid, level)` | table \| nil | `'summary' | 'medic' | 'self'` (fields below) |
| `Sync(pid)` | bool | push state bag + self snapshot now |
| `Watch(pid, src, on)` | bool | `on` pushes a medic snapshot at once, then every `watchRate` |
| `Triage(pid)` | level 1–3, label, colour | |
| `Save(pid)` | bool | players only |
| `Loss(p)` | 0..1 | `1 − (blood + 0.35·fluid)/bloodMax` |
| `Ped(p)` / `Coords(p)` | entity \| 0 / vector3 \| nil | server-side |
| `Touch(p, deep?)` | | mark dirty (bag, self push, save); `deep` recomputes bleeding now |
| `LoadPlayer(src)` / `UnloadPlayer(src, reason?)` | Patient \| nil / – | LoadPlayer may await the DB (call from a thread/handler) |
| `Flush(force?)`, `RT(p)`, `Meds` | | internals |

`CreateNPC(opts)`: `net` (required), `name sex age bloodType bloodMax blood loss (0..0.6) temp
meta`, `injuries = { def, … }`, `complications` (default true), `conditions = { name = value }`
(`arrest` → state), `devices = { name = value }`, `meds = { name = seconds }`, `state`, `reason`,
`clock`, `replace`.

Injury `def`: `region type severity(=2)` + optional `id spot created weapon attacker cause
fracture{kind,bone,displaced,angle} burn{degree,area,temp,soot,full,exposure}
internal{organ,vessel} length depth retained retainedDepth exit pain contamination bleedBase
treat quality heal status complications(=true) force`.

### Snapshots

**State bag `nza`** (`Player(src).state.nza` / `Entity(ped).state.nza`, ≤ 250 ms):
`pid st avpu bleed(0–3) stab clock inj tri tags[] tq{region=true} splints{region=true} binder
collar iv intub bag carried stretcher(netId|nil) name('M. Garcia') npc(true|nil)`.
`clock` = bleed-out seconds while wounded, seconds to death in arrest, else 0.
`stab` = stabilized: total bleed < `Config.Wounded.stableBleed` (1 mL/min), or < `controlledBleed`
(default 5 mL/min) while no wound is still `open` and no haemothorax is still filling. The bleed-out
clock is paused while stabilized and `CanStand` allows a pick-up.

**medic** (`nza:patient:get`, watch pushes): every Patient field except `watchers` (`pid kind src
net identifier name sex age bloodType blood bloodMax fluid state stabilized clock clockRate
conditions devices infusions given meds pain temp base vitals bleedTotal arrestAt arrestLeft lastCpr
downAt deadAt cause meta seq created updated stateAt`) + `injuries` (ARRAY, severity desc, then
bleed) + `triage { level, code, label, colour }`, `bloodPct`, `lossPct`, `clockText`.
`vitals = { hr sys dia map spo2 rr temp etco2 rhythm avpu pupils breathing airway ecgRate }`
(`hr` = palpable pulse, 0 in arrest; `ecgRate` = monitor rate).
Rounded in the snapshot only (the live Patient keeps full precision): `blood fluid clock` 0.1, `temp`
0.001, `infusions[].left` 0.1, condition fields `ml output size pressure water smoke level amount` 0.1,
injury `heal` 0.01 and `contamination` 0.1. `cause.arrestCause` is set after an arrest ended in death.

**self** (`nza:self:get`, `nza:self:update` ≤ 500 ms when changed): `pid state clock clockRate
arrestLeft downAt deadAt stabilized bleeding(0–3) pain avpu loss(0..1) health(0–100) syncHealth
injuries[{ id region type severity status bleeding label regionLabel }] conditions[names]
meds[names] devices{ tourniquet[] splints[] collar binder iv oxygen foil intubated }
fx{ limp shake blur tunnel cold breathless drunk } bloodType name` (`fx` numbers rounded to 0.01).

### NZA.Treat (treat.lua) — §5.1

```lua
NZA.Treat.Register(name, {
  perm = 'basic' | nil, self = bool, items = { [name] = n } | fn(src, p, payload) → items,
  maxDist = 3.0, states = { wounded = true, … } (default: all but dead), npc = true, player = true,
  cooldown = 400 (ms), record = true,
  handler = function(src, p, payload, info{ self, items }) return ok, result end,
}) → bool
NZA.Treat.Get(name)  NZA.Treat.List() → { { name, perm, self } }
NZA.Treat.Run(src, action, target, payload) → ok, result      -- same checks as the callback; src 0 = server
```
Order: action → rate → patient → self/kind/state → perm → distance (`maxDist + 1`) → items → handler
(pcall) → items consumed only on `ok` → bus `treat:done` → `NZA.Records.Add`.
`result`: `{ msg?, title?, record? , … }` (a string result becomes `{ msg }`).
Failure: `false, { err, msg, item? }`, err ∈ `unknown_action rate no_patient no_self kind state
no_perm too_far missing_item failed` (+ the handler's own `err`).

### NZA.Proc (proc.lua) — §5.2

```lua
NZA.Proc.Register(name, {
  perm, items, maxDist = 3.0, minTime = 0, maxTime = 900, consume = 'finish' | 'start',
  easyTime (default clamp(minTime, 4, 10), 6 when minTime = 0), label?, self, states, npc, player, record,
  onStart  = function(src, p, payload, info{ easy }) return true, data | false, { err, msg } | msg end,
  onFinish = function(src, p, session, result) return outcome end,      -- required
  onAbort  = function(src, p_or_nil, session, reason) end,
}) → bool
NZA.Proc.Get(name)  NZA.Proc.Session(token)  NZA.Proc.Active(src)
NZA.Proc.Start(src, name, target, payload) → response   NZA.Proc.Finish(src, token, result) → response
NZA.Proc.Abort(token, reason) → bool        -- notifies the client ('nza:proc:aborted')
```
- `nza:proc:start` response: `{ ok = true, token, data, easy, easyTime, minTime, maxTime, maxDist,
  label, allowDead }` or `{ ok = false, err, msg }` (err `unknown_proc rate in_progress` + treat codes).
- `nza:proc:finish` response: `{ ok = true, outcome }` or `{ ok = false, err, msg }` (err `no_session
  too_fast expired no_patient missing_item failed` + target checks). `result.score` is clamped 0–100;
  easy sessions get `Config.EasyMode.score` and `result.easy = true`.
- `outcome` = what onFinish returned (non-table → `{ result = value }`) + `score`, `grade`
  (`NZA.Util.Grade`), `easy`. `outcome.msg` is shown in the client toast; `outcome.record`
  replaces the record summary.
- Time: finish rejected when `elapsed + 1 s < minTime` (easy: `< easyTime`) or `> maxTime + 5 s`.
- Session: `{ token, name, def, src, pid, target, payload, data, items, consumed, easy, startedAt (ms),
  started (os.time), elapsed (on finish) }`. One per medic (a new start aborts the old one with
  `replaced`), one per patient+procedure.
- Server abort reasons (`onAbort` / `nza:proc:aborted`): `cancelled replaced too_fast expired
  no_patient too_far patient_state missing_item timeout`. Watchdog (2 s): medic offline, patient
  gone, state not allowed, medic > `maxDist + 4 m`, `maxTime + 5 s`.

### NZA.Staff (staff.lua) — §7

```lua
NZA.Staff.Get(src) → { hospital, dept, grade, gradeLabel, perms = { [perm] = true }, easy = { [perm] = true },
                       onDuty, medic, police, admin, job, jobLabel, isBoss, …provider fields }
NZA.Staff.Can(src, perm) → bool        -- src 0 and admins always true, perm nil → true
NZA.Staff.Easy(src, perm) → bool       -- record.easy[perm], else record.easyDefault (optional provider
                                       -- bool), else Config.EasyMode.default
NZA.Staff.OnDuty() → { src, … }        -- medics on duty
NZA.Staff.Provider(fn(src, defaultRecord) → record | nil)   -- hospital module; refreshes everyone
NZA.Staff.Refresh(src, force?) → record     NZA.Staff.RefreshAll(force?)
```
`perms` in the record are EFFECTIVE (duty rule applied, public perms added, admin = all +
`builder`). A provider record may set `ignoreDuty = true` and `easyDefault = true|false` (easy mode for
every perm not in `easy`, so a department can switch it off under `Config.EasyMode.default = true`).
Pushed as `nza:staff:update`.

### NZA.Records (records.lua)
```lua
NZA.Records.Add(pidOrPatient, { medic = src | 'id', medicName?, action, summary = string | table }) → bool  -- players only
NZA.Records.Get(identifier, limit = 25, cb?) → rows { id, identifier, medic, medicName, action, summary, created }
```

### NZA.Damage (damage.lua)
```lua
NZA.Damage.Apply(p, report, src?, forced?)   -- report fields: weapon group bone region damage attacker attackerNet
                                             -- melee fall speedDrop seatbelt fire drown (missing numbers = 0)
NZA.Damage.Sanitize(raw) → report            NZA.Damage.AddOrMerge(p, region, type, sev, extra{ weapon, attacker, cause, fracture, internal }) → Injury
NZA.Damage.Burn(p, region, intensity, extra) → Injury    NZA.Damage.Drown(p, ml)
NZA.Damage.Fall(p, metres, weapon?)          NZA.Damage.Crash(p, speedDropKmh, belted, weapon?)
NZA.Damage.MakeRoom(p, region, sev, extra)   NZA.Damage.Rebuild()   -- re-read Config.Damage weapon tables
```

### NZA.Injury (injury.lua) / NZA.Physiology (physiology.lua)
```lua
NZA.Injury.Build(p, def) → Injury | nil, err    NZA.Injury.Complications(p, inj)
NZA.Injury.BaseBleed(type, region, sev, organ?) → mL/min    NZA.Injury.BurnSeverity(burn) → 1..4
NZA.Injury.Bones / Organs / Vessels / OrganBleed / MaxInjuries (12) / Penetrating / OpenTypes
NZA.Physiology.Refresh(p)  Recompute(p, snap?)  TimeToDeath(p, bleed?) → s  PickArrestRhythm(p, why)
NZA.Physiology.HealMultiplier(p, inj)  InjuryBleed(p, inj) → mL/min  Status(p, inj)  Update(p, dt, now)  Tick(dt)
NZA.Physiology.SetModifier(pid, key, { sys, dia, hr, ttl = 3 } | nil) → bool
    -- short-lived vitals offset (sys/dia/hr added to a living patient's targets before smoothing, all
    -- monitors see it); dropped ttl s (1..60) after the last call; nil removes it; keyed per caller
```
Ventilation counts in physiology when `devices.intubated` + `meta.ventilated` (rate `meta.ventRate`,
default 14) or while `meta.bagUntil` (timestamp, bag-valve-mask round) is in the future (RR at least
`meta.ventRate` or 10, SpO2 +4, absent / agonal / shallow breathing reads `normal`; in arrest RR 10).

### NZA.Core (base.lua, treat.lua, callbacks.lua)
```lua
NZA.Core.B('Inv.HasItem', ...)  Has(path)          -- pcall-guarded Bridge calls
NZA.Core.Identifier(src)  Name(src)  Online(src)  IsAdmin(src)  IsLocalSource(src)
NZA.Core.SrcCoords(src) → vector3|nil  PatientPed(p)  PatientCoords(p)  DistanceTo(src, p) → m (huge if unknown)
NZA.Core.Rate(bucket, key, limit, windowMs) → bool   ClearRate(key)
NZA.Core.Notify(src, msg | data, type?, title?, duration?)   -- = NZA.Notify ; 'nza:ui:toast'
NZA.Core.Speech(src, name, text, ms?, extra?)                -- 'nza:ui:speech' (src -1 = all)
NZA.Core.NormalizeItems(items) → { [name] = n }   CheckItems(src, items) → ok, missing   TakeItems(src, items) → ok
NZA.Core.TargetChecks(src, def, target, { slack = 1 }) → p, err, isSelf      ResolveItems(def, src, p, payload) → items | nil
NZA.Core.CanView(src, p, slack?) → ok, err ('no_patient'|'no_perm'|'too_far')
```

### Callbacks & net events (server side)
| Name | Kind | Args → result |
|---|---|---|
| `nza:patient:get` | callback | `(target)` → medic snapshot \| `nil, err` (`rate no_patient no_perm too_far`); 12/s |
| `nza:patient:watch` | callback | `(target, on)` → bool |
| `nza:self:get` | callback | `()` → self snapshot \| nil (4/s, then cached) |
| `nza:records:get` | callback | `(target, limit)` → rows \| `nil, err` |
| `nza:staff:get` | callback | `()` → staff record (2 forced refreshes / 5 s) |
| `nza:treat` | callback | `(action, target, payload)` → `ok, result` |
| `nza:proc:start` / `nza:proc:finish` | callback | see NZA.Proc |
| `nza:damage` / `nza:down` / `nza:proc:abort` | C→S | §17 (25 damage reports/s; 2 downs / 3 s) |
| `nza:self:update` `nza:patient:update` `nza:staff:update` `nza:revived` `nza:proc:aborted` `nza:ui:toast` `nza:ui:speech` | S→C | `nza:patient:update (pid, nil)` = watch ended |

Server bus: `player:loaded (src)` `player:unloaded (src, reason)` `player:job (src, job)`
`patient:created (p)` `patient:removed (pid, reason)` `injury:added|updated (p, inj)`
`injury:removed (p, id)` `state:changed (p, old, new, reason)` `patient:arrest (p)`
`patient:death (p)` `patient:revived (p, opts)` `condition:changed (p, name, value)`
`device:changed (p, name, value)` `infusion:started|stopped|done (p, inf)` `med:given (p, name, opts)`
`treat:done (src, p, action, result)` `proc:started (src, p, name, session)`
`proc:done (src, p, name, outcome)` `proc:aborted (src, p|nil, name, reason)`
`staff:changed (src, record, old)`.

Server exports: `GetPatient(src)` `GetPatientByPid(pid)` `IsDowned(src)` `IsDead(src)` `GetState(src)`
`Revive(src, full)` (async when the record is not loaded yet) `Heal(src)` `AddInjury(src, region, type, sev) → id`
`GetVitals(src)` `GetInjuries(src)` `CreateNPCPatient(opts) → pid` `GetTriage(src)`
`SetPatientMeta(pid, key, value)`. Commands: `Config.Commands.revive / heal / injure / kill`.

---------------------------------------------------------------------------------------

## CLIENT

### NZA.UI (ui.lua)
```lua
NZA.UI.Open(app, data, { focus = true, cursor = focus, keepInput = false, look = false, controls = {ids} }) → bool
NZA.UI.Close(app) → wasOpen       -- does NOT emit 'ui:closed' (only JS-initiated closes do)
NZA.UI.SetFocus(app, opts)  NZA.UI.CloseAll()  NZA.UI.IsOpen(app)  NZA.UI.Top()  NZA.UI.OpenApps()  NZA.UI.Ready()
NZA.UI.Send(app, action, data)    -- queued until the page is ready (anchors are dropped, not queued)
NZA.UI.On(app, event, fn(data, cb)) → fn   NZA.UI.Off(app, event, fn)   -- ALWAYS cb({...}); auto 'timeout' reply after 10 s
NZA.UI.Toast({ title, message, type = 'success'|'error'|'warning'|'info', duration = 4500, icon, grade, score })  (= NZA.UI.Notify)
NZA.UI.Speech(name, text, ms = 4000, extra)
NZA.UI.Prompt(id, { key = 'E', label, sub, hold, progress = 0..1, tone = 'red' | danger = true })
NZA.UI.PromptProgress(id, 0..1)  NZA.UI.HidePrompt(id)  NZA.UI.IsPrompt(id)
NZA.UI.Hold(id, { key, control = 38, seconds = 2, label, sub, cancel = fn → bool, timeout = ms, tone, danger }) → bool  -- blocking
NZA.UI.PushConfig()
```

### NZA.Self (self.lua)
```lua
NZA.Self.State() → 'alive'|'wounded'|'arrest'|'dead'   NZA.Self.Summary() → own state bag   NZA.Self.Get() → self snapshot
NZA.Self.IsDown()  NZA.Self.Refresh() → snapshot (awaits)  NZA.Self.Effects()
NZA.Self.SetMoveOverride(name, clipset | false | nil)   NZA.Self.Suspend(name, bool)
```

### NZA.Target & NZA.Interact (target.lua)
```lua
NZA.Target.FromEntity(ent, any?) → target | nil   NZA.Target.Entity(target) → ped | 0   NZA.Target.State(entOrTarget) → bag | nil
NZA.Target.Self()  IsSelf(t)  Same(a, b)  Key(t) → 'player:12'|'npc:4512'  Distance(t) → m
NZA.Interact.Add({ name, onSelect = fn(entity, target),            -- both required; onSelect runs in its own thread
                   label, icon, faIcon, description, order = 50, perm, states = { alive = true } | { 'alive' },
                   self = false, player = true, npc = true, bag = false, whileDown = false, distance = 2.0,
                   canInteract = fn(entity, target, stateBag) → bool }) → bool
NZA.Interact.Remove(name)  Get(name)  All()  Options(entity)  Open(entity?)  OpenNearby()
```

### NZA.Patient (patient.lua)
```lua
NZA.Patient.Get(target) → medic snapshot | nil, err                        -- awaits
NZA.Patient.Watch(target, fn(snap | nil, reason), { maxDist = examDistance + 2, keep = false, initial = true }) → stop()
NZA.Patient.Last(pid) → last pushed snapshot
```
`fn(nil, reason)` once when the watch ends by itself: `far gone denied removed`. `keep` only
disables the client distance check; the server still ends watches outside its view rules (§4.3).

### NZA.Treat / NZA.Proc / NZA.Anim.Kneel (proc.lua)
```lua
local ok, result = NZA.Treat.Do(action, targetOrEntity, payload, { silent = false })   -- toast result.msg / error
local ok, outcomeOrReason = NZA.Proc.Run(name, targetOrEntity, payload, function(ctx) … end,
                                         { label, anim = { dict, clip, flag } | { scenario }, maxDist, silent })
NZA.Proc.Active() → ctx | nil   NZA.Proc.Abort(reason = 'cancel')   NZA.Anim.Kneel(ped) → token
```
`ctx = { name, target, payload, token, data, easy, entity, startedAt, label, finish(result) → ok, outcome|reason,
abort(reason), onEnd(fn(outcome | nil, reason)), done(), elapsed() }`. Blocks until the session ends (call
from a thread). `finish` waits out `minTime` itself. Easy mode never calls the runner (ox_lib
progress for `easyTime`). Client abort reasons: `cancel far gone dead down time error silent`
(+ server reasons via `nza:proc:aborted`); start failures return the server `err` or `busy invalid error`.

### NZA.Cam / NZA.Anchors / NZA.Props / NZA.Anim
```lua
NZA.Cam.Orbit(target, { dist = 2.2, height, fov = 45, pitch = 20, yaw, front, minDist = .6, maxDist = 6, minPitch, maxPitch,
                        orbit, pan, zoom, panLimit = 1.5, ease = 600, hideHud = true }) → cam
NZA.Cam.Close(entity, boneId | 'region' | boneName | vec3, { dist = .75, pitch = 55, fov = 40, orbit = false, offset, … }) → cam
NZA.Cam.TopDown(entity | coords, height = 3, { heading, minHeight, maxHeight }) → cam
NZA.Cam.Stop(ease = 500)  Update(opts)  Recenter()  Active() → mode|nil  Handle()  Focus()  Input(data)
NZA.Cam.Raycast({ x, y, dist = 15, flags = -1, ignore }) → { hit, coords, entity, normal, origin, dir, x, y }
NZA.Cam.ScreenToWorld(sx, sy) → origin, dir   WorldToScreen(coords) → x, y, visible   CursorPosition() → sx, sy
NZA.Anchors.Track(app, { [id] = { entity, bone, offset } | { entity, boneName, offset } | { entity, offset } | { coords } })
NZA.Anchors.Set(app, id, def)  Remove(app, id)  Clear(app)  Tracked(app)  Project(def) → x, y, visible, dist
NZA.Props.Spawn(model | Config.Props key | hash, coords | { attach = { entity, bone, pos, rot, collision, fixedRot } },
                { group = 'default', network = false, freeze = true, collision = true, heading, rot, fallbackKey,
                  ground = false, alpha, timeout = 5000, invincible = true }) → entity (0 on failure), netId|nil
NZA.Props.Delete(entity)  Clear(group)  Group(group) → { entity }  Resolve(model) → name, key
NZA.Anim.Play(ped, dict, clip, { flag = 1, blendIn = 8, blendOut = -8, duration = -1, rate = 0, wait, scenario,
              prop = { model, bone = 57005, pos, rot } }) → ok, token
NZA.Anim.Stop(ped, { immediate, token }) → bool   NZA.Anim.Current(ped) → { dict, clip, scenario, token, duration }
```
Anchors message to the app: action `anchors` `{ [id] = { x, y, visible, d } }` (~30 Hz, only on change).

### NZA.Points (points.lua)
```lua
NZA.Points.RegisterType(name, { label, icon, prop, needsHeading, data = {}, radius = 1.2, distance = 2.0, ground,
  onSpawn = fn(point, entity|nil), onRemove = fn(point),
  target = { { label, icon, perm, name?, distance?, order?, whileDown?, canInteract = fn(point, entity), onSelect = fn(point, entity) } } })
NZA.Points.All(type?) → { point }  Get(id)  Nearest(type, coords?, maxDist?) → point, dist  Types()  Type(name)
NZA.Points.Entity(id) → entity | 0  Refresh(id?)
```

### Staff (staff.lua) & compat (compat.lua)
```lua
NZA.Perm(perm) → bool   NZA.Easy(perm) → bool   NZA.IsMedic()   NZA.OnDuty()   NZA.Staff.Get() → record   NZA.Staff.Refresh() → record (awaits)
NZA.Damage.SyncBaseline()   NZA.Damage.IsBelted(ped?, veh?)   NZA.Damage.WeaponName(hash)
```
Client exports: `isDead IsDead isPlayerDead GetDeathStatus` (arrest/dead), `isDowned isPlayerDowned`,
`isInLastStand` (wounded), `GetState`, `GetSelfSnapshot`. Own state bags: `isDead dead inLastStand laststand isDowned`.

Client bus: `self:state (new, old)` `self:update (snap)` `self:revived (opts)` `self:down (info)`
`self:resurrected (wasAlive)` `ui:closed (app)` `points:changed (reason, arg)` `staff:changed (rec)`
`proc:started (ctx)` `proc:ended (name, ok, outcome|reason)`.

NUI callbacks owned by core: `<app>:close` (auto for every opened app), `_core:ready`, `_core:camInput`.
Keybind `nza_interact` (unbound) + command `Config.Commands.interact` (default `nzainteract`).

---------------------------------------------------------------------------------------

## NUI KIT (html/core/nza.js · nza.css)

The full kit list is the header of `html/core/nza.js`. These are the parts apps asked for after the
first pass; use them instead of private copies.

```js
NZA.ui.BodyGlyph(states, focus) → '<svg class="nza-body">…'      // returns HTML; size it with the parent box
  // front view, 15 regions, the patient's left on the viewer's right
  // states { [region]: 'red' | 'amber' | 'teal' }   aliases: face → head, back → chest
  // focus  region → one pulsing diamond hotspot + that segment pulses ('back' adds a BACK tag, locale ui.back_tag)
  //        [region | { region, tone }, …] → several hotspots (tone defaults to the region's state, else red)
  // no <pattern> ids: any number of glyphs can share a page
NZA.ui.Ring({ value = '--', frac = 0..1, tone = '', label = '', unit = '', beat = 0 }) → '<div class="nza-ring">…'
  // value in the middle, track + fill (frac), label and unit under it
  // tone '' | teal | red | amber | white | green | cyan | yellow    beat = seconds per heartbeat ping (0 = off)
```

**ProcPanel** `NZA.ui.ProcPanel(host, opts) → pp`

| opts | |
|---|---|
| `step, total` | 1-based; `total <= 1` hides the step spine and the body takes the full width (`.pp--flat`) |
| `steps` | step names in order (plain 0-based array): the card shows `Next <steps[step]>`, i.e. the name of the step after the current one; hidden when there is none |
| `skipped` | `[n, …]` 1-based step numbers (a `Set` or `{ [n]: true }` also works): those spine nodes draw dashed; `complete()` keeps them dashed |
| `side: 'right'` | mirrors the layout (`.pp--mirror`): instruction column on the right, tool belt on the left |
| `tag title titleTone text` | `text` takes `{Key}` key caps and `**bold**` |
| `stats wide tools hints` | readouts, the dial (`wide.meter` draws a 240° gauge), the tool belt, the key legend |
| `abort onAbort onTool` | `abort` defaults to `{ label = ui.holdAbort ('Hold to cancel'), key = 'ESC', seconds = 1.2 }`; `abort: false` hides the ring |

`pp.set(patch)` re-renders only what changed (`step total tag steps skipped` → spine). Also
`pp.stat(id, patch)`, `pp.wide(patch)`, `pp.tool(key, state)`, `pp.active(key)`,
`pp.flash(type, text, ms = 2600)` (type `ok` / `bad` / anything else = alert icon; `ms = 0` keeps it),
`pp.complete({ title, text, label, onDone })` (Done button, Enter), `pp.key(e)` (a tool's `key` → `onTool`,
Enter → done; return it from the app's key handler), `pp.slot` (the column container above the key
legend, for app widgets) and `pp.destroy()`.

**FlipClock** `NZA.ui.FlipClock(host, { value = '00:00', tone, small }) → { el, set(v), tone(t), paused(p) }`:
a rolling counter (each digit rolls like an odometer). Non-digit characters are `.odo .c` and blink
once a second; `paused(true)` stops the blink and dims the digits. There is no option to keep a
running counter from blinking yet: apps that show values such as `148,250` scope
`.odo .c{animation:none}` in their own app.css.

**Class names** (`nza.css`):
- `.nza-tg` is the toggle switch that `NZA.ui.Toggle(host, { on, onChange }) → { el, set(v), get() }`
  renders (as `button.tg.nza-tg`). `button.tg` is kept as the legacy alias, so a plain `.tg` span stays
  free for app styles.
- `.nza-hold` wraps a control with a progress ring (`.nza-hold.red` for the red ring). `span.hold` is the
  legacy alias. A bare `.hold` is left free as a state class (`.prompt.hold` is the prompt with a
  progress ring, from `NZA.prompt(id, { progress })`; apps use it on their own buttons).

---------------------------------------------------------------------------------------

## BRIDGE ADDITIONS (server, used by modules through `NZA.Core.B` / `NZA.Core.Has`)

```lua
Bridge.SetJob(src, job, grade) → bool                       -- bridge/server/framework.lua
  -- false when the job or grade does not exist, the player is not loaded, or the framework has no
  -- jobs to give (standalone: jobs are aces). ESX checks ESX.DoesJobExist; QBCore refuses a grade the
  -- job does not have; Qbox lets qbx_core:SetJob check. Same job, new grade keeps the duty state
  -- (ESX 'off<job>' stays off duty). Refreshes Player(src).state.nzaJob and emits 'bridge:jobChanged'.
  -- Used by hospital_manager.lua: hire / promote / demote set the linked framework job and grade,
  -- fire sets Config.Hospital.staff.fireJob (default unemployed, grade 0); syncFrameworkJob = false turns hiring sync off.
Bridge.HasLicense(src, name) → bool                         -- bridge/server/framework.lua
  -- QBCore / Qbox: PlayerData.metadata.licences (or .licenses)[name] == true
  -- ESX: esx_license:checkLicense (awaits up to 2 s: call it from a thread or handler)
  -- framework cannot tell (standalone, ESX without esx_license): the ace 'nza.license.<name>'
  -- Used by pharmacy.lua (licence-restricted products).
Bridge.Inv.OpenStash(src, id, { label = id, slots = 50, weight = 100000, owner? }) → bool   -- bridge/server/inventory.lua
  -- opens a stash of the running inventory for the player; the caller checks access first
  -- ox_inventory: RegisterStash (owner → one stash per player) + forceOpenInventory
  -- qb-inventory 2.x: OpenInventory export   ps-inventory: its OpenInventory export
  -- qb-inventory 1.x, lj-inventory, qs-inventory: client event 'nza:bridge:inv:openStash'
  --   (bridge/client/inventory.lua) → the classic inventory:server:OpenInventory stash flow
  -- false (codem, origen, tgiann, core_inventory, plain ESX / QB, none): the caller uses its own
  --   storage (hospital_runtime.lua staff store → nza_hospital_stash)
```

---------------------------------------------------------------------------------------

## Integration review — what was changed

- `nza:proc:start` now returns `maxDist`, `label`, `allowDead`; `easyTime` is always set (default
  from `minTime`) and is the easy-mode minimum on the server, so client bar and server check agree.
- Client `NZA.Proc.Run` no longer aborts a dead patient's session when the procedure allows dead
  patients; `Treat.Do` / `Proc.Run` accept an entity as target.
- Self snapshot carries `loss` (0..1); core-client uses it for blood-loss effects.
- A player patient unloading ends every medic watch on them (`nza:patient:update (pid, nil)`).
- `Core.CanView` no longer trusts the client-writable `nzaBay` player state bag.
- Rate limits on `nza:self:get` and `nza:staff:get`; `NZA.Damage.Apply` tolerates partial reports;
  `UpdateInjury` keeps `treat` / `quality` tables; `NZA.Core.Speech` added.
- Client `NZA.Perm` / `NZA.Easy` follow the server rules exactly (`requireDuty ~= false`,
  `ignoreDuty`, easy default).
- Player- and ped-registered target options no longer both match the same entity.
- `exports:Revive` never awaits the database inside the export call.
- Final integration pass: physiology accumulators (blood, fluid, temp, heal, contamination, condition
  levels, infusion `left`, clock) keep full precision (slow bleeds, saline decay, healing, overdoses,
  infection and cooling no longer stall at 0.1-unit rounding); the snapshots round them.
- Controlled bleeding (< `controlledBleed`, nothing `open`, no filling haemothorax) counts as stabilized.
- Mask ventilation (`meta.bagUntil`) counts as ventilation; `NZA.Physiology.SetModifier` added.
- Arrest → dead keeps `p.cause.arrestCause`; `NZA.Staff.Easy` honours `record.easyDefault`;
  `cond.reaction` locale key.
