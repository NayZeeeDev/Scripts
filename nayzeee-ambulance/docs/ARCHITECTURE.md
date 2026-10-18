# nayzeee-ambulance — Architecture & Contracts

This file is the single source of truth for every part of the resource. Every module
codes against the contracts here. If something you need is not here, add the smallest
possible thing to YOUR OWN files and document it in your module's header comment.
Never edit files you do not own (see §14 Ownership).

Resource folder name: `nayzeee-ambulance` (locked by `lock.lua`).
Short prefix: `nza` → events `nza:*`, NUI callbacks `<app>:<event>`, DB tables `nza_*`,
Lua global namespace `NZA`, bridge global `Bridge`.

Requires: OneSync, `ox_lib`, `oxmysql`. Optional: everything else is behind `Bridge`.

---------------------------------------------------------------------------------------

## 1. Load order (fxmanifest)

```
shared:  @ox_lib/init.lua → lock.lua → shared/init.lua → shared/const.lua → shared/util.lua
         → config/config.lua → config/items.lua → config/props.lua → config/modules/*.lua
         → locales/*/*.lua → bridge/shared.lua
client:  bridge/client/*.lua → client/core/*.lua → client/modules/*.lua
server:  @oxmysql/lib/MySQL.lua → bridge/server/*.lua → server/core/*.lua → server/modules/*.lua
```

Rules:
- Every Lua file starts with `if not NAYZEEE_LOCK_OK then return end` (right after its header
  comment). Exceptions: `lock.lua` (it sets the flag) and `install/*.lua` (paste-in snippets for
  other resources and the offline generator; none of them is in the fxmanifest).
- At file top level you may only (a) declare `NZA.X = NZA.X or {}`, (b) define functions,
  (c) call APIs that are defined by an EARLIER folder in the order above
  (e.g. a module may call `NZA.Treat.Register(...)` at top level because server/core loads
  before server/modules). Never call another file of the SAME folder at top level.
- Lua 5.4 standard syntax only. Do NOT use CfxLua extensions (backtick hashes, `+=`,
  `?.`, `<const>`). Use `joaat('name')` or `GetHashKey('name')`. Code must pass `luac5.4 -p`.
- `local` everything. Globals only under `NZA`, `Bridge`, `Config`.
- Never block the main thread. Loops use `CreateThread` + `Wait`. Per-frame loops only while
  a feature is active, otherwise sleep ≥ 500 ms.

## 2. Shared basics (shared/init.lua, shared/const.lua, shared/util.lua) — written by lead

- `NZA.Debug(...)` prints when `Config.Debug`.
- `NZA.L(key, ...)` → localized string (`string.format` args). Locale files add keys with
  `NZA.AddLocale('en', { ['exam.title'] = 'Head-to-toe check', ... })`. Key = `<module>.<name>`.
  Each module owns `locales/en/<module>.lua`.
- `NZA.Const.Regions` (ordered array) and `NZA.Const.Region[name]` (lookup) — 15 regions:
  `head, face, neck, chest, back, abdomen, pelvis, l_upper_arm, l_lower_arm, r_upper_arm,
  r_lower_arm, l_upper_leg, l_lower_leg, r_upper_leg, r_lower_leg`.
  Fields: `name, label, group, side, limb, bones, xray, tourniquet, splint, lethal`.
  `group` ∈ `head neck chest abdomen l_arm r_arm l_leg r_leg` (the 8 exam-map groups).
  `xray` ∈ `head neck chest abdomen l_arm r_arm l_leg r_leg` (the 8 X-ray views).
- `NZA.Const.InjuryTypes` — 9 types: `gunshot, shrapnel, stab, laceration, abrasion,
  contusion, fracture, burn, internal` with defaults (`bleed`, `pain`, `label`, `icon`).
- `NZA.Const.Conditions` — `haemothorax, pneumothorax, tamponade, concussion, hypoxia,
  airway, overdose, arrest, hypothermia, infection, spinal`.
- `NZA.Const.BloodTypes` = `O-, O+, A-, A+, B-, B+, AB-, AB+` with `canReceive[recipient][donor]`.
- `NZA.Const.Rhythms` = `sinus, stach, sbrady, afib, vf, vt, pea, asystole`
  and `NZA.Const.Shockable = { vf = true, vt = true }`.
- `NZA.Const.Perms` — permission keys (see §7).
- `NZA.Const.BoneToRegion[boneId]` — GTA ped bone id → region.
- `NZA.Util`: `round, clamp, lerp, deepcopy, uid(prefix), tableCount, vec(x)`, `dist(a,b)`,
  `formatTime(sec) → "02:00"`, `weightedPick(list)`, `shuffle(t)`.

## 3. Config

- `config/config.lua` (lead): `Config.Debug, Config.Locale, Config.Framework, Config.Jobs,
  Config.UI, Config.Keys, Config.Physiology, Config.Wounded, Config.Death, Config.Damage,
  Config.EasyMode, Config.Persistence, Config.Billing (defaults), Config.Commands`.
- `config/items.lua` (lead): `Config.Items[key] = 'item_name'` (canonical item keys — ALWAYS
  reference items as `Config.Items.bandage`, never hard-code names) and `Config.ItemDefs`
  (label, weight, description, category, stack, image) used to generate install files.
- `config/props.lua` (lead): `Config.Props[key] = 'model_name'` (custom streamed models,
  prefix `nz_amb_`) and native fallbacks.
- Each module owns `config/modules/<module>.lua` and writes ONLY `Config.<ModuleName> = {...}`
  (PascalCase, e.g. `Config.Suture`, `Config.Dispatch`). Config files are escrow-ignored and
  are what server owners edit: write them with the NAYZEEE ASCII header style used in
  `config/config.lua`, short comments on every option, sane defaults.

## 4. The patient model (server authoritative) — server/core

A patient is a player OR an NPC. Same data, same treatment code.

```lua
Patient = {
  pid       = 'p:ABC123' | 'n:4512',     -- 'p:'..identifier for players, 'n:'..netId for NPCs
  kind      = 'player' | 'npc',
  src       = 12,                         -- players only (nil while offline)
  net       = 4512,                       -- NPC ped netId (nil for players)
  identifier= 'ABC123',                   -- players only
  name      = 'Michael Garcia',
  sex       = 'm' | 'f',
  age       = 34,
  bloodType = 'O-',
  blood     = 5000,       -- mL whole blood in the body now
  bloodMax  = 5000,
  fluid     = 0,          -- mL crystalloid (saline) in circulation (decays over time)
  state     = 'alive' | 'wounded' | 'arrest' | 'dead',
  stabilized= false,      -- true when total bleed < Config.Wounded.stableBleed and no arrest, or < controlledBleed
                          -- with every bleeding wound under control (not 'open') and no filling haemothorax
  clock     = 120,        -- seconds left on the wounded bleed-out clock (players & NPC)
  injuries  = { [id] = Injury },
  conditions= { [name] = table },          -- e.g. haemothorax = { side = 'right', ml = 900 }
  devices   = {
     tourniquet = { [region] = os.time() }, binder = false, collar = false,
     splints = { [region] = 'leg' | 'arm' }, iv = nil | { site = 'l_lower_arm', kind = 'iv'|'io' },
     port = nil | { site }, intubated = false, chestDrain = { left = false, right = false },
     oxygen = false, foil = false, monitor = false,
  },
  infusions = { { id, kind = 'saline'|'blood'|'txa', ml, left, rate, bag = meta } },
  given     = { saline = 0, blood = 0, txa = 0, adrenaline = 0, naloxone = 0, morphine = 0 },
  meds      = { [name] = expiresAt },     -- active drug effects (painkillers, morphine, ...)
  pain      = 0..100,
  vitals    = { hr, sys, dia, map, spo2, rr, temp, etco2, rhythm, avpu, pupils,
                breathing = 'normal'|'labored'|'shallow'|'agonal'|'absent',
                airway = 'clear'|'snoring'|'gurgling'|'obstructed'|'secured' },
  arrestAt  = nil | os.time(), lastCpr = nil | os.time(),
  watchers  = { [src] = true },           -- medics with a live monitor/exam open
  meta      = { scenario = 'mva', callId = 'C-0012', insured = true, ... },
  updated   = os.time(),
}

Injury = {
  id = 'i7', region = 'chest', type = 'gunshot', severity = 1..4,
  bleed = 6.1,            -- mL/min current (after treatment modifiers)
  bleedBase = 6.1,        -- mL/min before treatment
  pain = 0..100, contamination = 0..100,
  length = 56, depth = 18,                       -- mm (cuts, stabs)
  retained = 0..n, retainedDepth = 0..80, spot = { x = 0..1, y = 0..1 }, -- bullets/fragments, position on region
  fracture = nil | { kind = 'closed'|'open'|'comminuted', bone = 'tibia', displaced = true, angle = 18 },
  burn = nil | { degree = 1..3, area = 99, temp = 41.0, soot = 100, full = 51 },
  internal = nil | { organ = 'spleen'|'liver'|'kidney'|'bowel'|'mesenteric'|'pelvic'|'femoral', vessel = 'jejunal' },
  treat = { packed, bandaged, tourniquet, irrigated, anesthetized, sutured, dressed, extracted,
            splinted, reduced, cast, cooled, debrided, grafted, coiled, drained, xray, xrayMarked },  -- booleans
                          -- treat.xray = seen on a film, treat.xrayMarked = confirmed on both films (lightbox read)
  xrayMap = nil | { film, view, ap = { x, y }, lat = { x, y }, depth (mm), n, at },
                          -- set by xray when a retained fragment is pinned on both films (used by bullet)
  quality = { [treatKey] = 0..100 },
  status = 'open' | 'controlled' | 'treated' | 'healing',
  heal = 0..100, created = os.time(), weapon = hash,
}
```

### 4.1 Server API (server/core) — `NZA.Patients`

```lua
NZA.Patients.Get(pid)                    -- → Patient | nil  (live table — mutate ONLY via API below)
NZA.Patients.GetBySource(src)            -- → Patient | nil
NZA.Patients.GetByNet(netId)             -- → Patient | nil
NZA.Patients.Resolve(target)             -- target = { kind='player', sid=12 } | { kind='npc', net=4512 } | 'pid'
NZA.Patients.All()                       -- → { [pid] = Patient }
NZA.Patients.CreateNPC(opts)             -- opts = { net, name?, sex?, age?, bloodType?, injuries = { {region,type,severity,...} },
                                         --          conditions = {}, state?, blood?, meta = {} } → Patient
NZA.Patients.Remove(pid)                 -- NPC cleanup
NZA.Patients.AddInjury(pid, def)         -- def = { region, type, severity?, ... } → Injury (fills defaults from Const)
NZA.Patients.UpdateInjury(pid, id, patch)-- shallow merge; patch.treat / patch.quality merged too
NZA.Patients.RemoveInjury(pid, id)
NZA.Patients.SetCondition(pid, name, value)   -- value table or nil to clear
NZA.Patients.SetDevice(pid, name, value)      -- e.g. ('binder', true), ('splints', { r_lower_leg = 'leg' })
NZA.Patients.AddInfusion(pid, inf)            -- { kind, ml, rate, bag } ; rate mL/min
NZA.Patients.StopInfusion(pid, id)
NZA.Patients.GiveMed(pid, name, opts)         -- adrenaline/naloxone/morphine/painkillers/txa/antibiotics → applies effects
NZA.Patients.AddBlood(pid, ml)                -- negative to remove (donation)
NZA.Patients.SetState(pid, state, reason)     -- 'alive'|'wounded'|'arrest'|'dead'
NZA.Patients.Revive(pid, opts)                -- opts = { full = true } heals everything; { rosc = true } arrest → wounded
NZA.Patients.Heal(pid, amount)                -- generic healing (bed rest etc.)
NZA.Patients.Snapshot(pid, level)             -- level 'summary' | 'medic' | 'self' → plain serializable table (§4.3)
NZA.Patients.Sync(pid)                        -- push statebag summary now (API calls auto-schedule a sync; rarely needed)
NZA.Patients.Watch(pid, src, on)              -- watchers receive 'nza:patient:update' every Config.Physiology.watchRate
NZA.Patients.Triage(pid)                      -- → 1 (critical) | 2 (urgent) | 3 (standard), label, colour
NZA.Patients.Save(pid)                        -- persist now (players)
```

Mutations auto-mark the patient dirty → state bag sync within 250 ms and DB save
(throttled, Config.Persistence.saveInterval). Physiology tick (1 s) recomputes vitals,
bleeding, clock, state transitions (§6).

### 4.2 Event bus (server & client): `NZA.Bus`

```lua
NZA.Bus.On(name, fn)      NZA.Bus.Emit(name, ...)
```
Server events emitted by core: `patient:created (p)`, `patient:removed (pid)`,
`injury:added (p, inj)`, `injury:updated (p, inj)`, `injury:removed (p, id)`,
`state:changed (p, old, new, reason)`, `patient:arrest (p)`, `patient:death (p)`,
`patient:revived (p)`, `treat:done (src, p, action, result)`, `proc:done (src, p, name, outcome)`.
Client events emitted by core: `self:state (state, old)`, `self:update (snapshot)`,
`ui:closed (app)`.

### 4.3 Snapshots & sync

State bag `nza` on the player (`Player(src).state.nza`) or NPC ped entity (`Entity(ped).state.nza`),
replicated, set by core only:
```lua
{ pid, st = 'alive'|'wounded'|'arrest'|'dead', avpu = 'A'|'V'|'P'|'U', bleed = 0..3,
  stab = bool, clock = sec, inj = count, tri = 1|2|3, tags = { 'gunshot', 'fracture' },
  tq = { [region] = true }, splints = { [region] = true }, binder = bool, collar = bool,
  iv = bool, intub = bool, bag = bool (in body bag), carried = bool, stretcher = netId|nil,
  name = 'M. Garcia' }
```

Reserved module state bags (replicated, server-set unless noted). Only the owner writes them;
everyone may read them. Never trust any of them for permissions on the server.

| Bag | On | Shape | Owner |
|---|---|---|---|
| `nzaFa` | player / NPC ped | `{ o2 = true?, foil = true?, tq = { [region] = { s, f } \| false } }` (worn props) | firstaid |
| `nzaMedbag` | medical bag object | `{ id, owner, locked, name, colour }` | medbag |
| `nzaBag` | body bag object | patient target `{ kind = 'player', sid } \| { kind = 'npc', net }` (core target contract) | medbag |
| `nzaBody` | body bag object | `{ id, name, kind, mode }` | medbag |
| `nzaInBag` | player | `{ id, net (entity it is attached to), mode, off = { x, y, z }? }` | medbag |
| `nzaBodyOn` | stretcher | body bag id | medbag |
| `nzaBodies` | vehicle | `{ n, ids }` | medbag |
| `nzaTr` | player / NPC ped | `{ m = 'carry'\|'str'\|'bed'\|'bay'\|'seat'\|'free', n, c, s, b, bt, at, v, seat, slot, stand, from }` | transport |
| `nzaStr` | stretcher | `{ pid, pk, pusher, veh, low, home }` | transport |
| `nzaAmb` | ambulance | `{ str, inside, bay }` | transport |
| `nzaCrutch` | player | `true` while walking on crutches | splint |
| `nzaChair` | wheelchair | `{ owner, occ, occNpc, push }` | splint |
| `nzaCpr` | player / NPC ped | server id of the compressor while a code runs | cpr |
| `nzaNpcCalls` | player | `true` = this medic takes NPC calls | dispatch |
| `nzaNpc` | NPC patient ped | `{ s, c, tr, pose, dp, wet, esc, rel, ho, veh, seat, sex }` | calls |
| `nzaBy` | bystander ped | `{ role = 'caller'\|'cpr'\|'watch', v, scenario }` | calls |
| `nzaJob` | player | `{ name, label, grade, gradeLabel, onDuty, isBoss, medic, police }` | bridge |
| `isDead dead inLastStand laststand isDowned` | player | booleans for HUDs / other scripts (set by the player's own client) | core-client |

Snapshot 'medic' (callback `nza:patient:get`, requires medic + distance ≤ Config.Physiology.examDistance
or the patient in the same bay/bed): everything in Patient except `watchers`, plus
`vitals`, `triage`, `bleedTotal` (mL/min), `bloodPct`, injuries as an ARRAY sorted by severity.
Snapshot 'self' (callback `nza:self:get`): what the player may know about themself
(no exact vitals, injuries listed by region/type/severity).

Callbacks (ox_lib `lib.callback`), all registered in server/core:
- `nza:patient:get (target) → snapshot | nil, err`
- `nza:patient:watch (target, on) → bool`
- `nza:self:get () → snapshot`
Client push: `nza:patient:update (pid, snapshot)` to watchers; `nza:self:update (snapshot)`.

### 4.4 Client API (client/core)

```lua
NZA.Self.State()                 -- 'alive'|'wounded'|'arrest'|'dead' (from own statebag)
NZA.Self.Get()                   -- last self snapshot
NZA.Target.FromEntity(ent)       -- → target table for ped entity (player or NPC patient) or nil
NZA.Target.Entity(target)        -- → ped entity or 0
NZA.Target.State(entOrTarget)    -- → statebag summary table or nil
NZA.Patient.Get(target)          -- → medic snapshot via callback (awaits)
NZA.Patient.Watch(target, fn)    -- live updates while fn != nil; returns stop()
NZA.IsMedic() / NZA.OnDuty()     -- local job info via Bridge
NZA.Perm(perm)                   -- → bool (local cache of NZA.Staff perms pushed by server)
NZA.Easy(perm)                   -- → bool, easy mode for this player's department
```

## 5. Treatment & procedures (server/core + client/core)

### 5.1 Instant treatments
Server registry; modules register at their file top level:
```lua
NZA.Treat.Register('bandage', {
  perm = 'basic',                      -- §7 ; nil = anyone (self-treat items)
  self = true,                         -- may be used on yourself
  items = { [Config.Items.bandage] = 1 } | function(src, patient, payload) return itemsTable end,
  maxDist = 3.0,
  handler = function(src, patient, payload) ... return true, { msg = 'Bleeding slowed' } end,
})
```
Client calls `NZA.Treat.Do(action, target, payload)` →
`lib.callback.await('nza:treat', false, action, target, payload)` → `ok, result`.
Core checks: action exists, permission, distance (server-side coords), items present →
runs handler → consumes items only if handler returned true → emits `treat:done`.
Treatments and procedures aimed at one wound take `payload.injury = <injury id>` (the exam
passes the chosen wound). Without it, first-aid treatments pick the most fitting wound
themselves, while wound procedures such as `suture` refuse with `err = 'no_injury'`.

### 5.2 Procedures (minigames with a server session)
```lua
NZA.Proc.Register('suture', {
  perm = 'suture', items = {...} | fn, maxDist = 3.0,
  minTime = 20, maxTime = 900,        -- seconds; finish before minTime is rejected (anti-cheat)
  consume = 'start' | 'finish',
  easyTime = 12,                      -- seconds of progress bar in easy mode
  onStart  = function(src, patient, payload) return true, data end,   -- data → client (wound params etc.)
  onFinish = function(src, patient, session, result) return outcome end, -- apply effects, return outcome table
  onAbort  = function(src, patient, session) end,
})
```
Client:
```lua
NZA.Proc.Run('suture', target, payload, function(ctx)       -- ctx = { token, data, easy, target }
   -- run your NUI minigame; when finished call ctx.finish(result) or ctx.abort()
end)
```
`NZA.Proc.Run` handles: start callback, easy mode (progress bar `Config.EasyMode` style,
result `{ score = Config.EasyMode.score, easy = true }`), cancel when the patient moves away
or dies, finish callback, result toast. `result.score` 0..100 is mandatory;
`NZA.Util.Grade(score)` → `S A B C D F`.
Server callbacks: `nza:proc:start (name, target, payload) → { ok, token, data, easy }`,
`nza:proc:finish (token, result) → { ok, outcome }`, event `nza:proc:abort (token)`.
Only one session per medic. Session stores `startedAt`, items reserved.

## 6. Physiology (server/core/physiology.lua) — summary every module can rely on

- Total bleed = Σ injury.bleed (+ internal organs) × modifiers (tourniquet on that limb ×0,
  bandage ×0.35, packed ×0.25, sutured ×0.05, binder on pelvic/femoral ×0.4, TXA active ×0.6,
  coiled internal ×0, chest drain doesn't stop haemothorax bleeding — it drains it).
- blood -= bleed/60 per second; infusions add blood/fluid at their rate; fluid decays 1%/min.
- loss% = 1 − (blood + 0.35 × fluid)/bloodMax → HR/BP/MAP/RR/SpO2/temperature/AVPU curves
  (ATLS classes I–IV). Tamponade, tension pneumothorax, haemothorax, hypoxia, overdose,
  hypothermia and pain also modify vitals. Saline over-infusion dilutes (lowers effective
  oxygen carrying → SpO2/etco2 effects).
- State machine:
  `alive → wounded` when GTA health hits 0 (client reports) OR loss% ≥ Config.Wounded.lossDown
  OR AVPU ≤ 'P'. `wounded → arrest` when MAP < Config.Physiology.arrestMap for N s, loss% ≥ 45,
  SpO2 < 60 for N s, untreated tension/tamponade or clock reaches 0 while bleeding.
  `arrest → dead` after Config.Death.arrestToDeath seconds without ROSC (CPR in progress
  extends it). `arrest → wounded` on ROSC (cpr module calls `Revive(pid, { rosc = true })`).
  `wounded → alive` when stabilized AND AVPU = 'A' AND loss% < lossDown AND a medic used
  'pick up' / or the patient was treated to 'alive' (`SetState`).
- Clock: seconds until blood reaches the death threshold at the current bleed rate, clamped to
  `Config.Wounded.maxClock`, frozen while stabilized (the wounded HUD shows the pause in its own
  wording — see `docs/design/ORIGINAL.md`, the reference product's phrase is not allowed).
- Healing: treated injuries gain `heal` over time (faster in a hospital bed) and are removed at 100.

## 7. Staff, departments & permissions

Framework job (Config.Jobs.medic, default `{ 'ambulance' }`) = is a medic. Department/grade
are a layer on top, stored by the hospital module (`nza_staff`). Core exposes:
```lua
NZA.Staff.Get(src)        -- → { hospital, dept, grade, gradeLabel, perms = { [perm] = true }, easy = { [perm] = true } }
NZA.Staff.Can(src, perm)  -- → bool  (onDuty medic + perm granted; admins (ace 'nza.admin') always true)
NZA.Staff.OnDuty()        -- → { src, ... }
NZA.Staff.Provider(fn)    -- the hospital module installs the real resolver; default = job grade → Config.DefaultPerms
```
Client receives its own staff record via `nza:staff:update` → `NZA.Perm(perm)`, `NZA.Easy(perm)`.

Permission keys (`NZA.Const.Perms`): `assess basic cpr defib iv binder splint suture burn graft
airway ultrasound chestdrain pericardio xray surgery angio meds blood transport bodybag
checkin pharmacy manage`. Admin-only: `builder` (ace `nza.admin`).

## 8. Hospitals, points & world (server/modules/hospital*.lua owns)

Hospitals are built in game (no coordinates in config). Point = `{ id, hospital, type,
coords = vec4, data = {}, model? }`. Point types are registered by the module that handles them:
```lua
-- client (any module, top level of client/modules/*.lua)
NZA.Points.RegisterType('xray', { label = 'X-ray table', icon = 'scan', prop = Config.Props.xray_table,
   needsHeading = true, data = { ...defaults }, onSpawn = fn(point, entity), onRemove = fn(point),
   target = { { label = 'X-ray: Chest', icon = 'scan', perm = 'xray', onSelect = fn(point, entity) } } })
NZA.Points.All(type?)  NZA.Points.Nearest(type, coords, maxDist)
-- server
NZA.Hospitals.Get(id) NZA.Hospitals.All() NZA.Hospitals.Nearest(coords)
NZA.Hospitals.Points(type, hospitalId?) NZA.Hospitals.RespawnPoint(coords)
NZA.Hospitals.FreeBed(hospitalId) NZA.Hospitals.OccupyBed(pointId, pid) NZA.Hospitals.ReleaseBed(pointId)
```
Point types (owner module): `duty locker stash boss storage garage heli elevator bed respawn hq`
(hospital; `hq` is stored on the department, not as a point), `checkin tv` (checkin),
`pharmacy` (pharmacy), `bloodbank donation` (blood), `xray lightbox` (xray), `surgery` (bullet),
`ultrasound` (ultrasound), `angio` (angio), `morgue` (medbag), `stretcher` (transport, stretcher
rack). The Department Console lists every registered type automatically (`NZA.Points.Types()`).
Bed-like types (a patient can be laid on them): `Config.Transport.Beds.types` plus any type or
point whose `data.bed = true`; `point.data.lie = { x, y, z }` nudges the body on the mattress.

## 9. Dispatch, calls & billing (owned by those modules — callable by everyone)

```lua
NZA.Dispatch.Create(call)   -- server; call = { code='10-52', priority=1..3, title='Gunshot Wound', type='gunshot',
                            --   coords=vec3, street?, zone?, caller?, patients = { pid },
                            --   voice? ('audio/calls/x.ogg' - path relative to html/, [%w_-/.] only,
                            --           .ogg/.mp3/.wav; 'audio/' is prefixed when missing; nui:// URLs are rejected),
                            --   npc = bool, source = 'player'|'npc'|'system', blip = { sprite, colour } } → callId
NZA.Dispatch.Update(callId, patch)   NZA.Dispatch.Close(callId, reason)   NZA.Dispatch.Get(callId)
NZA.Dispatch.SetStatus(callId, src, status)  -- 'DSP'|'ENR'|'SCN'|'CARE'|'TRN'|'HSP' (CARE = first treatment on scene)
NZA.Billing.Charge(target, amount, reason, opts) -- target = src | identifier ; applies insurance; pays society
NZA.Insurance.Get(identifier) → { plan, expires, cover = 0..1 } | nil
NZA.Blood.CreateBag(meta) → metadata table  NZA.Blood.Compatible(recipient, donor) → bool
```

## 10. NUI — one page, many apps

`html/index.html` loads `core/nz-core.css`, `core/nz-core.js` (NAYZEEE UI pack, untouched),
`core/nza.css`, `core/nza.js` (EMS UI kit, lead), `core/nza-vitals.js` (waveforms, lead),
`vendor/three.min.js`, `core/nza3d.js` (shared WebGL close-up engine, owned by `suture` module),
then every app's `apps/<app>/app.css` + `apps/<app>/app.js`. The app list is fixed in index.html.

### 10.1 Messages
Lua → JS: `NZA.UI.Send(app, action, data)` = `SendNUIMessage({ app = app, action = action, data = data })`.
`NZA.UI.Open(app, data, { focus = true, cursor = true, keepInput = false })` sends action `open`
and manages focus with a stack (several apps may be open; focus = OR of all open apps).
`NZA.UI.Close(app)` sends `close`. `NZA.UI.On(app, event, fn)` registers NUI callback
`'<app>:<event>'` → `fn(data, cb)`; ALWAYS call `cb({...})`. When JS calls `NZA.close(app)` the
router posts `<app>:close` → core closes focus for that app automatically and emits `ui:closed`.

JS side (nza.js):
```js
NZA.app('pulse', {            // register an app; root element is <section id="app-pulse" class="nza-app">
  open(data) {},             // called on action 'open' — app becomes visible (class nza-on)
  close() {},                // called on action 'close' or NZA.close('pulse')
  msg: { tick(d) {}, ... },  // other actions
  keys: { Escape(e) {} },    // keydown handlers while this app is the top-most focused app
  preview() {},              // browser-only demo data (open it with ?app=pulse)
});
NZA.post('pulse:result', {...})  → Promise<json>   NZA.close('pulse')   NZA.toast({...})
```
Browser preview: `html/index.html?app=<name>` must show the app with demo data and no errors.
Every app MUST implement `preview()`.

### 10.2 Visual rules (the user's two designs — `docs/design/*.html` — read them)
- Palette & tokens: `nz-core.css` `:root` (black surfaces, teal `#08afa2`, red `#e5484d`, white,
  amber `#e5a50a` for warnings only). Font token `--font` (Lexend default; `Config.UI.font`
  can switch to Inter). Mono: `--mono` JetBrains Mono. LCD (pager): `--lcd` VT323.
- WINDOWS (full menus: pharmacy, manager, builder, dispatch board, lightbox side
  panel): design `nayzeee-ui-v5.html` → `.nza-win` chamfered frame, title bar with teal rail +
  `.nz-mark`, sidebar nav, stat tiles, panels, status bar with key caps, red `Close` pill on the
  right of the title bar, `.nz-sig` signature in the status bar.
- HUD OVERLAYS (wounded, call card, procedure panels, monitors, toasts, prompts, medic bag):
  design `nayzeee-ui-hud-design.html` → `.nza-hud` panels `rgba(12,13,16,.78)`, radius 12, hairline
  border, 1px top highlight; notes with a glowing left bar; segmented controls, toggles,
  sliders, chips from that file. The medic bag is built from edge docks so the bag on the floor
  stays in view: pockets dock left, the open bag right, body-bag zip card bottom-left, toe tag
  right-middle (no NUI focus for the last two).
- SETTINGS pages (department manager, easy mode, builder options): the HUD design's settings
  window (sidebar tabs, header with btn-line + btn-teal + red Close pill, uppercase section
  headings, option rows label+helper left / control right).
- NEVER: `backdrop-filter`, `color-mix()`, `:has()`, external fonts/CDNs, emojis as icons.
  Icons: `NZ.icon(name)` (UI pack set) or inline SVG in the same stroke style.
- Teal = primary/active/done. Red = danger, critical, close, abort. White = selected/current.
  Amber = warning/urgent (P2). P1 red, P2 amber, P3 teal.
- ORIGINALITY (customer requirement, overrides anything older in this file): nothing may look
  like the competitor product in the reference screenshots (layout, composition, wording, icon
  treatment). Full rules and the list of forbidden look-alikes: `docs/design/ORIGINAL.md`.
  No NAYZEEE name or logo on props or on in-world device faces (screens drawn in NUI/DUI that
  represent a physical device); windows keep the UI pack signature.
- The procedure HUD (used by EVERY minigame): `NZA.ui.ProcPanel` in nza.js. Layout: an
  instruction column anchored bottom-left (readout card with a 240° dial for `wide` + an
  instrument list / tile grid for `stats`, then the step card: procedure tag + `03/08` counter,
  a vertical step spine, title, instruction text with inline key caps, optional `steps` names
  → "Next: …", flash line, Done button), a key legend under it, and a vertical TOOL BELT on the
  right edge (icon slots with key badges, labels as dark chips, active = teal slot + light bar,
  done = check, need = red pulse) with the hold-to-abort RING under it. `side: 'right'` mirrors
  it. The screen centre and the bottom-centre stay clear. Free zones for app widgets: top-left,
  top-centre (transient), top-right, right-middle LEFT of the belt (keep `right ≥ 300px` when
  tools are shown), centre for the scene. `pp.slot` is a container in the column for small
  app widgets (above the key legend). Use it; do not build your own.
- Patient speech: `NZA.speech` → voice card top-centre (avatar ring with initials, name +
  role, quoted line). Interaction prompts: `NZA.prompt` → context tag next to the crosshair
  (key ring + teal kicker `sub` + label). Timers/counters: `NZA.ui.FlipClock` now renders a
  rolling (odometer) mono counter — do not draw split-flap digit cards anywhere.
- Motion 130 ms hovers, 200–250 ms panels. Respect `prefers-reduced-motion`.
- Text tone: short, plain, imperative ("Press the probe into the skin and feel for it").

### 10.3 Shared JS kit (core/nza.js, lead) — use these, don't re-implement
`NZA.ui.ProcPanel`, `NZA.ui.FlipClock` (rolling counter), `NZA.ui.Toasts` (`NZA.toast`), `NZA.ui.KeyHints`,
`NZA.ui.Segmented`, `NZA.ui.Toggle`, `NZA.ui.Slider`, `NZA.ui.Chips`, `NZA.ui.Modal`,
`NZA.ui.Win` (window shell builder), `NZA.ui.Anchors` (world-anchored markers fed by Lua),
`NZA.ui.Hold` (hold-to-confirm), `NZA.ui.Meter`, `NZA.ui.Grade` (A–F result badge),
`NZA.audio` (WebAudio beeps: `beep(freq, ms)`, `heartbeat()`, `charge()`, `shock()`, `click()`, `noise()`),
`NZA.vitals` (core/nza-vitals.js): `NZA.vitals.Trace(canvas, { type: 'ecg'|'pleth'|'resp'|'co2', rhythm, rate, color })`,
`NZA.vitals.Monitor(el, opts)` full bedside monitor widget (HR/SpO2/NIBP/MAP/RR/Temp + traces),
`NZA.fmt` (`time(sec)`, `num`, `pct`).

### 10.4 World anchors (in-world minigames)
Lua `NZA.Anchors.Track(app, { id = { entity=, bone=, offset=vec3 } | { coords=vec3 } })` streams
screen positions (0..1) to the app as action `anchors` at ~30 Hz while tracked;
`NZA.Anchors.Clear(app)`. JS `NZA.ui.Anchors(app)` gives `onUpdate(fn)` and `get(id)`.
`NZA.Cam` (client/core): `NZA.Cam.Orbit(target, { dist, height, fov, pitch })` (right-click orbit,
Shift+right-click pan, scroll zoom, R recentre), `NZA.Cam.Close(focusEntity, boneOrOffset, opts)`,
`NZA.Cam.TopDown(entity, height)`, `NZA.Cam.Stop()`. `NZA.Cam.Raycast()` → world hit under cursor.
`NZA.Props.Spawn(model, coords|{ attach = { entity, bone, pos, rot } }, opts)` → entity, auto-cleaned
by `NZA.Props.Clear(group)`. `NZA.Anim.Play(ped, dict, clip, opts)`, `NZA.Anim.Stop(ped)`.

## 11. Interactions (who sees which option on a patient)

client/core owns the ONE global target registration on players, NPC patient peds and body bags.
Modules add options:
```lua
NZA.Interact.Add({
  name = 'nza_pulse', label = 'Check Pulse', icon = 'heart', order = 30,
  perm = 'assess',                                  -- nil → everyone
  states = { alive = true, wounded = true, arrest = true }, -- patient states this shows for
  self = false, npc = true, player = true, distance = 2.0,
  canInteract = function(entity, target, stateBag) return true end,
  onSelect = function(entity, target) ... end,
})
```
Order bands: 10 movement (ask to walk, carry, stretcher, help off table), 20 assessment
(examine, pulse, breathing), 30 resuscitation (CPR, field resus), 40 treatment, 50 transport,
60 procedures, 90 misc (body bag).

## 12. Data (oxmysql) — each owner creates its tables with `CREATE TABLE IF NOT EXISTS` on start

16 tables, all `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4` in `sql/install.sql` (the collected copy,
column for column the same as the code; change both together). There are no ALTERs/migrations.

| Owner | Tables |
|---|---|
| core | `nza_patients (identifier PK, data LONGTEXT, state, updated_at)` · `nza_records (id PK, identifier, medic, medic_name, action, summary LONGTEXT, created)` (treatment log) |
| hospital | `nza_departments (id PK, label, job, data)` · `nza_points (id PK, department, type, x, y, z, h, label, data)` · `nza_staff (identifier PK, department, grade, name, excluded, hired_by)` · `nza_hospital_stash (id PK, items)` (built-in staff store) |
| checkin | `nza_tickets (id PK, hospital, day, prefix, number, identifier, name, triage, status, bed, handled_by, issued, called, closed, data)` |
| blood | `nza_blood (serial PK, type, ml, donor, donor_id, created, expires, used, bank, updated)` · `nza_blood_donors (identifier PK, last, count, weak_until)` · `nza_blood_log (id PK, bank, action, serial, type, actor, at)` |
| pharmacy | `nza_pharmacy_stock (pool + item PK, stock)` · `nza_pharmacy_sales (id PK, pool, point, identifier, name, items, subtotal, discount, tax, total, method, kind, created)` |
| billing (pharmacy) | `nza_insurance (identifier PK, plan, expires, started, serial)` · `nza_bills (id PK, identifier, name, amount, covered, reason, kind, medic, medic_name, society, status, created, paid_at)` |
| dispatch | `nza_calls (id PK, code, priority, title, type, x, y, z, street, zone, caller, message, source, npc, status, units, reason, created, responded, arrived, closed)` (call log) |
| medbag | `nza_bags (id PK, owner, items LONGTEXT)` |

A department IS the hospital: there is no `nza_hospitals` table (`NZA.Hospitals.*` reads
`nza_departments`). Small non-table state uses the resource KVP store (`nza_dispatch_seq`,
`nza_blood_seed:*`, bridge `nza_meta:*` metadata emulation).

## 13. Security (server is the authority)

- Every `RegisterNetEvent` handler validates `source`, rate-limits, checks distance using
  server-side `GetEntityCoords(GetPlayerPed(src))`, permissions (`NZA.Staff.Can`) and items.
- Never trust client numbers for money, item counts, injuries or vitals. Clients send intents
  and minigame scores; servers clamp scores and enforce `minTime`.
- Players can only damage-report themselves (`nza:damage`) with sanity limits.
- Admin commands use ace `nza.admin` (or framework admin groups via Bridge).

## 14. Ownership (who writes which files)

| Module | Files |
|---|---|
| lead | `fxmanifest.lua lock.lua shared/* config/config.lua config/items.lua config/props.lua html/index.html html/core/nza.* html/core/nza-vitals.js docs/* README.md sql/*` (+ regenerating `install/*` from `config/items.lua` during integration) |
| core-server | `server/core/*.lua config/modules/core.lua? (no — core uses config/config.lua) locales/en/core.lua` |
| core-client | `client/core/*.lua locales/en/core_client.lua` |
| bridge | `bridge/** install/** html/img/items/**` |
| <module> | `client/modules/<module>*.lua server/modules/<module>*.lua config/modules/<module>.lua locales/en/<module>.lua html/apps/<app>/**` (+ `html/core/nza3d.js` for suture, `html/dui/**` for checkin, `tools/props/** stream/**` for props) |

If you believe a lead-owned file needs a change, DO NOT edit it — write the request in
`docs/requests/<module>.md` (what, where, why). The lead applies it during integration.

## 15. Definition of done for every module

1. `luac5.4 -p` passes on every Lua file you wrote; `node --check` on every JS file.
2. Browser preview `html/index.html?app=<app>` renders with demo data, no console errors
   (verify with Playwright, chromium at `/opt/pw-browsers/chromium` — screenshot 1920×1080 and LOOK at it).
3. Server validates everything (§13). Easy mode works for every minigame (§5.2).
4. Config + locale complete; no hard-coded item names, prop names or user-facing strings in Lua.
5. A header comment in each file: what it does, events/callbacks it registers.
6. `docs/modules/<module>.md`: features, controls, config keys, events/exports, known limits.

---------------------------------------------------------------------------------------

## 16. Bridge API (bridge/**, owned by the bridge module) — everything external goes through here

Detection is automatic (`Config.Framework = 'auto'`, inventories/targets/phones by
`GetResourceState`), with overrides in `bridge/config.lua`? — NO: overrides live in
`config/modules/bridge.lua` as `Config.Bridge = { inventory='auto', target='auto', phone='auto',
notify='auto', dispatch='auto', keys='auto', fuel='auto', clothing='auto' }`.

### Server (`bridge/server/*.lua`)
```lua
Bridge.Framework                         -- 'esx'|'qbcore'|'qbox'|'standalone'
Bridge.OnPlayerLoaded(fn(src))           Bridge.OnPlayerUnloaded(fn(src))     Bridge.OnJobChanged(fn(src, job))
Bridge.GetIdentifier(src)  → string      Bridge.GetSourceFromIdentifier(id) → src|nil
Bridge.GetName(src)        → 'First Last'   Bridge.GetCharInfo(src) → { firstname, lastname, dob, sex = 'm'|'f', phone }
Bridge.GetJob(src)         → { name, label, grade, gradeLabel, onDuty, isBoss }
Bridge.IsMedic(src) / Bridge.IsPolice(src) / Bridge.IsOnDuty(src) / Bridge.SetDuty(src, bool)
Bridge.IsAdmin(src)        → bool (ace Config.Admin.ace or framework group)
Bridge.GetPlayers()        → { src, ... }    Bridge.GetMedics(onDutyOnly) → { src, ... }
Bridge.GetMoney(src, account) → number      Bridge.RemoveMoney(src, account, amount, reason) → bool
Bridge.AddMoney(src, account, amount, reason)
Bridge.Society.Add(name, amount) / Bridge.Society.Remove(name, amount) → bool / Bridge.Society.Get(name) → number
Bridge.Inv.HasItem(src, name, count?) → bool      Bridge.Inv.Count(src, name, metaMatch?) → number
Bridge.Inv.AddItem(src, name, count, metadata?) → bool   Bridge.Inv.RemoveItem(src, name, count, metadata?, slot?) → bool
Bridge.Inv.CanCarry(src, name, count) → bool      Bridge.Inv.GetItems(src) → { { name, label, count, slot, metadata, weight } }
Bridge.Inv.GetSlot(src, slot) → item|nil          Bridge.Inv.SetMetadata(src, slot, metadata)
Bridge.Inv.Search(src, name) → { items with metadata }   -- e.g. every blood_bag with its metadata
Bridge.Inv.RegisterUsable(name, fn(src, item))    Bridge.Inv.Label(name) → label
Bridge.Inv.Clear(src, keep?)                      Bridge.Inv.Image(name) → 'nui://...png' url for NUI
Bridge.Notify(src, { title, message, type = 'success'|'error'|'warning'|'info', duration })
Bridge.Phone.Notify(src, { title, message, app?, icon? })   Bridge.Phone.Mail(src, { sender, subject, message })
Bridge.Phone.Number(src) → string|nil             Bridge.Phone.Resource → 'lb-phone'|'qs-smartphone'|'qs-smartphone-pro'|'npwd'|'yseries'|'gksphone'|'okokPhone'|'roadphone'|'high-phone'|nil
Bridge.Dispatch.External(call) → bool            -- also send to an external dispatch (cd_dispatch, ps-dispatch, qs-dispatch, rcore_dispatch, core_dispatch, tk_dispatch, origen_police) when enabled
Bridge.Vehicle.SetPlate / (client-side keys & fuel below)
```
Phone integrations also register the phone's emergency/911 service where the phone supports it
(lb-phone services, qs-smartphone jobs, npwd, yseries...) and forward to `NZA.Dispatch.Create`.
Server export for any phone/dispatch script: `exports['nayzeee-ambulance']:CallEMS(src, message, coords?)`.

### Client (`bridge/client/*.lua`)
```lua
Bridge.Framework   Bridge.PlayerData() → table   Bridge.OnPlayerLoaded(fn) Bridge.OnPlayerUnloaded(fn) Bridge.OnJobChanged(fn(job))
Bridge.GetJob() → { name, grade, onDuty }        Bridge.IsMedic() Bridge.IsPolice()
Bridge.Notify({ title, message, type, duration })
Bridge.Target.Player(options)  Bridge.Target.Ped(options)  Bridge.Target.Entity(entity, options)  Bridge.Target.Model(models, options)
Bridge.Target.Sphere(name, coords, radius, options) → id   Bridge.Target.Box(name, coords, size, heading, options) → id
Bridge.Target.Remove(id)  Bridge.Target.RemoveEntity(entity, names)  Bridge.Target.RemovePlayer(names) Bridge.Target.RemovePed(names)
  -- options = { { name, label, icon = 'nz icon name or fa', distance, canInteract = fn(entity, distance, coords), onSelect = fn(entity) } }
  -- supports ox_target, qb-target, qtarget, interact (darktrc), sleepless_interact; fallback: built-in [E] prompt via lib.showTextUI
Bridge.Inv.Has(name, count?) → bool (client cache/search)   Bridge.Inv.Count(name)
Bridge.Vehicle.GiveKeys(vehicle, plate)   Bridge.Vehicle.SetFuel(vehicle, 100)
Bridge.Clothing.Save() / Bridge.Clothing.Restore()           -- before/after wearing a hospital gown (optional)
Bridge.Phone.IsOpen() → bool
```

## 17. Network events between core and modules (fixed names)

| Event | Dir | Payload | Owner (registers handler) |
|---|---|---|---|
| `nza:damage` | C→S | `{ weapon, bone, region, damage, attacker (server id or 0), attackerNet, melee, fall (m), speedDrop (km/h), fire, drown }` | core-server |
| `nza:down` | C→S | `{ weapon, attacker, region }` — GTA health hit 0, client already resurrected itself in place | core-server |
| `nza:self:update` | S→C | self snapshot | core-client |
| `nza:patient:update` | S→C | `pid, snapshot` (watchers only) | core-client |
| `nza:staff:update` | S→C | `{ hospital, dept, grade, gradeLabel, perms, easy, onDuty, medic }` | core-client |
| `nza:points:sync` | S→C | `points[]` full list (on join and after big changes) | core-client (NZA.Points) |
| `nza:points:upsert` | S→C | `point` | core-client |
| `nza:points:remove` | S→C | `pointId` | core-client |
| `nza:ui:toast` | S→C | `{ title, message, type, duration }` (core-client shows it in the NUI; Bridge.Notify is the fallback) | core-client |
| `nza:ui:speech` | S→C | `{ name, text, ms }` patient speech subtitle | core-client |
| `nza:revived` | S→C | `opts` — client must clear wounded/death visuals, stand up | core-client emits bus `self:revived` |
| `nza:respawn` | C→S | — | wounded module |

Client bus events from core-client: `self:state (new, old)`, `self:update (snap)`, `self:revived`,
`ui:closed (app)`, `points:changed`, `staff:changed (rec)`. The complete core lists (server and
client, incl. `condition:changed`, `device:changed`, `infusion:*`, `med:given`, `proc:started`,
`proc:aborted`, `player:loaded|unloaded|job`, `self:down`, `self:resurrected`) are in
`docs/modules/core-api.md`.

Module bus events (stable signatures — other modules may listen; `p` = Patient table):

| Owner | Server bus | Client bus |
|---|---|---|
| transport | `transport:loaded (src, p, vehNet, strNet)` · `transport:unloaded (src, p, vehNet)` · `transport:bed (src, p, point)` · `transport:carry (src, p, on)` · `transport:bay (src, vehNet, on)` | `transport:mine (mode, cmd)` · `bay:entered (vehNet, target)` · `bay:left (vehNet)` · `bay:ivstand (target, info)` · `bay:monitor (target, info)` |
| medbag | `medbag:placed (src, id)` · `medbag:picked (src, id)` · `medbag:moved (src, id, moved)` · `bodybag:bagged (src, body)` · `bodybag:morgue (src, body, point)` | — |
| xray | `xray:taken (src, p, meta)` · `xray:read (src, p, film, outcome)` · `xray:offTable (src, p)` · `xray:reduced (src, p, inj, outcome)` · `xray:cast (src, p, inj, outcome)` | — |
| assess | `assess:done (src, p, kind, data)` · `assess:exam (src, p)` · `findings:changed (p, key, finding \| nil)` | — |
| procedures | `suture:done` · `burn:done` · `graft:done` · `angio:done (src, p, inj, outcome)` · `splint:applied (src, p, inj, score)` · `splint:removed (src, p, region)` · `intubation:done (src, p, outcome)` · `intubation:extubated (p, reason)` · `ultrasound:scan` · `ultrasound:drain` · `ultrasound:decompress` · `ultrasound:pericardio (src, p, outcome)` | `suture:flinch (entity, pain)` · `burn:pain (entity, pain)` · `angio:suiteRemoved (pointId)` |
| cpr | `cpr:started (p, code)` · `cpr:rosc (p, code)` · `cpr:shock (p, src, energy, result)` · `cpr:ended (p, code, reason, summary)` | `cpr:started (action)` · `cpr:ended (summary)` |
| firstaid | `firstaid:tq_warn (p, region)` · `firstaid:tq_damage (p, region)` · `firstaid:soaked (p, inj)` | — |
| blood | `blood:typed (src, p, bloodType)` · `blood:hung (src, p, inf)` · `blood:reaction (p, stage)` · `blood:donated (src, p, ml, meta)` | `blood:typed (target, bloodType)` |
| hospital | `hospital:changed (deptId)` · `hospital:points (action, point \| id)` (`add move data remove`) · `hospital:bed (pointId, pid, on)` · `hospital:duty (src, on)` | `hospital:depts (depts)` |
| checkin | `checkin:issued (ticket)` · `checkin:called (ticket)` · `checkin:treatment (ticket)` · `checkin:closed (ticket, status)` · `checkin:ai (ticket, 'done' \| reason)` | — |
| pharmacy / billing | `pharmacy:sale (src, sale)` · `pharmacy:restock (pool, productId, qty, from)` · `billing:charged (identifier, info)` · `billing:bill (identifier, bill)` · `billing:paid (identifier, bills)` · `insurance:changed (identifier, row \| nil)` | — |
| dispatch | `dispatch:created (call)` · `dispatch:status (call, src, status)` · `dispatch:respond (call, src)` · `dispatch:closed (call, reason)` | `dispatch:sync (state)` · `dispatch:call (call, flags)` · `dispatch:update (call)` · `dispatch:close (id, reason)` · `dispatch:me (me)` · `dispatch:stage (id, stage)` |
| calls | `calls:created (scene)` · `calls:built (scene)` · `calls:removed (scene, reason)` · `calls:handover (scene, p, state, amount)` · `calls:released (scene, p)` | — |
| wounded | `wounded:called (src, p, callId)` · `wounded:gaveUp (src, p)` · `wounded:respawned (src, p, spot)` | — |
| bridge | `bridge:playerLoaded (src)` · `bridge:playerUnloaded (src)` · `bridge:jobChanged (src, job)` | the same without `src` |

Consumers today: dispatch, checkin and calls listen to `transport:loaded` / `transport:bed`
(the patient reached an ambulance / a hospital bed).

`NZA.Points` point table: `{ id, hospital, type, coords = vector4, data = {}, label? }`.
Server side (hospital module): `NZA.Hospitals.*` as in §8 and it must broadcast the three
`nza:points:*` events. Core-client streams point props within 60 m, registers targets from the
type's `target` list (each option gets `(point, entity)`), calls `onSpawn/onRemove`.

---------------------------------------------------------------------------------------

## 18. As-built amendments (core is implemented — `docs/modules/core-api.md` is authoritative)

- §5.2 procedure callbacks:
  `nza:proc:start (name, target, payload) → { ok, token, data, easy, easyTime, minTime, maxTime, maxDist, label, allowDead } | { ok = false, err, msg }`;
  `nza:proc:finish (token, result) → { ok, outcome } | { ok = false, err, msg }` (outcome has score, grade, easy);
  C→S `nza:proc:abort (token)`, S→C `nza:proc:aborted (token, reason, msg)`. `easyTime` defaults to `minTime`
  clamped to 4–10 s and is the easy-mode minimum on the server. `NZA.Proc.Run` blocks (call it from a thread)
  and returns `true, outcome` or `false, reason`; optional 5th arg `{ label, anim, maxDist, silent }`.
- §17: `nza:patient:update (pid, snapshot | nil)` — nil = the watch ended. Server helper for subtitles:
  `NZA.Core.Speech(src, name, text, ms, extra)`.
- §4.3 self snapshot: `{ pid, state, clock, clockRate, arrestLeft, downAt, deadAt, stabilized, bleeding, pain, avpu,
  loss, health, syncHealth, injuries[{ id, region, type, severity, status, bleeding, label, regionLabel }],
  conditions[], meds[], devices{}, fx{ limp, shake, blur, tunnel, cold, breathless, drunk }, bloodType, name }`.
- Bay viewing rights come ONLY from server meta: the transport module must set the medic's bay with
  `NZA.Patients.SetMeta(medicPid, 'bay', id)` (client state bags are never trusted for permissions).
- The hospital module pushes `nza:points:sync` on player load (core-client never requests points).
- NUI router (`html/core/nza.js`): `_core` action `focus { top }` gives the Lua-focused app keyboard priority;
  right-drag / wheel are forwarded to `NZA.Cam` via `_core:camInput` while an app has NUI focus — an app opts
  out with `camInput: false` (or `preventDefault()` in its own handler); `camInput: true` also forwards R (recentre).
  `NZA.toast({ grade })` shows the grade badge.
- Wounded module server API: `NZA.Wounded.Help(srcOrPid, { eta, unit, ai, status })`,
  `NZA.Wounded.ForceRespawn(src, { coords, label, fee, bed })`; client `NZA.Wounded.SuspendPose(name, on)`.
- Assess module server API: `NZA.Findings.Add(pid, key, data)` (discovered findings shown in the exam).
