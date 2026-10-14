# core-client

Client half of the core: NUI bridge, the local player as a patient, damage and GTA death,
patient targets and interactions, live patient data, treatments and procedure sessions,
cameras, world anchors, props and animations, hospital points, staff permissions and
compatibility with other scripts.

Files: `client/core/*.lua`, `locales/en/core_client.lua`.
All files load before `client/modules/*.lua`, so modules may call every API below at their
own top level (registrations) or later (everything else).

---

## Files at a glance

| File | Namespace | What it does |
|---|---|---|
| `ui.lua` | `NZA.UI` | NUI messages, focus stack, NUI callbacks, toasts, speech, prompts, hold helper, config push |
| `self.lua` | `NZA.Self` | own state bag + self snapshot, GTA health sync, injury effects, walk overrides |
| `damage.lua` | `NZA.Damage` | damage → `nza:damage`, falls, crashes, fire, drowning, GTA death → resurrect + `nza:down` |
| `target.lua` | `NZA.Target`, `NZA.Interact` | patient targets, the one global target registration, interact context menu |
| `patient.lua` | `NZA.Patient` | medic snapshots, live watches with auto-unwatch |
| `proc.lua` | `NZA.Treat`, `NZA.Proc`, `NZA.Anim.Kneel` | instant treatments, procedure sessions, easy mode |
| `cam.lua` | `NZA.Cam` | orbit / close-up / top-down cameras, cursor raycasts |
| `anchors.lua` | `NZA.Anchors` | world → screen anchors streamed to an app at ~30 Hz |
| `props.lua` | `NZA.Props`, `NZA.Anim` | prop spawning with fallbacks, animation helpers, cleanup |
| `points.lua` | `NZA.Points` | hospital points: types, streaming props and targets |
| `staff.lua` | `NZA.Perm`, `NZA.Easy`, `NZA.IsMedic`, `NZA.OnDuty`, `NZA.Staff` | own staff record cache |
| `compat.lua` | exports | death-state exports and state bags for HUDs/inventories, ESX events |

---

## NZA.UI (ui.lua)

```lua
NZA.UI.Open(app, data, { focus = true, cursor = true, keepInput = false, look = false, controls = {} })
NZA.UI.Close(app)                 NZA.UI.SetFocus(app, opts)        NZA.UI.CloseAll()
NZA.UI.Send(app, action, data)    -- SendNUIMessage({ app, action, data })
NZA.UI.On(app, event, fn)         -- RegisterNUICallback('<app>:<event>') → fn(data, cb)
NZA.UI.Off(app, event, fn)        NZA.UI.IsOpen(app)  NZA.UI.Top()  NZA.UI.OpenApps()  NZA.UI.Ready()
NZA.UI.Toast({ title, message, type = 'success'|'error'|'warning'|'info', duration })
NZA.UI.Speech(name, text, ms, extra)
NZA.UI.Prompt(id, { key = 'E', label, hold = seconds, progress = 0..1, danger })
NZA.UI.PromptProgress(id, 0..1)   NZA.UI.HidePrompt(id)
NZA.UI.Hold(id, { key, control = 38, seconds = 2, label, cancel = fn, timeout }) → bool  -- blocking
NZA.UI.PushConfig()
```

- **Focus stack**: several apps can be open. `SetNuiFocus(anyFocus, anyCursor)`;
  `SetNuiFocusKeepInput(true)` while any focused app asked for `keepInput`. While keep-input
  is active, attack / aim / weapon wheel / pause / camera look controls are disabled every
  frame (`look = true` keeps camera look, `controls = { ... }` blocks extra ones).
- After each focus change `_core` receives action `focus` `{ top, apps }`.
- `<app>:close` is registered automatically for every opened app. When the JS router posts
  it, focus is released, module handlers for `close` run, then bus `ui:closed (app)` fires.
  `NZA.UI.Close()` from Lua does **not** emit `ui:closed`.
- NUI callback handlers must call `cb(...)` before returning (waiting inside is fine). A
  safety net replies `{ ok = false, error = 'timeout' }` after 10 s.
- Messages sent before the page is up are queued until `_core:ready` (or 8 s).
- Toasts go to the NUI; before it is ready they fall back to `Bridge.Notify` / `lib.notify`.
- `_core` config: `{ font, shape, scale, sounds, signature, locale = NZA.LocaleTable('ui'), lang, resource }`
  sent on ready, on start and on player loaded.

Net events handled: `nza:ui:toast`, `nza:ui:speech`.

## NZA.Self (self.lua)

```lua
NZA.Self.State()      -- 'alive'|'wounded'|'arrest'|'dead' (own state bag 'nza')
NZA.Self.Summary()    -- own state bag table
NZA.Self.Get()        -- last self snapshot
NZA.Self.IsDown()     NZA.Self.Refresh()   NZA.Self.Effects()
NZA.Self.SetMoveOverride(name, clipset | false | nil)   -- crutches, wheelchair, beds
NZA.Self.Suspend(name, bool)                             -- pause injury effects
```

Bus: `self:state (new, old)`, `self:update (snapshot)`, `self:revived (opts)`.

Injury effects while `alive` (all cleared before `self:state` is emitted, and on revive):

| Cause | Effect |
|---|---|
| leg / pelvis injury | `move_m@injured` / `move_f@injured`; unsplinted fracture → heavy limp `move_injured_generic` |
| any leg / pelvis fracture | sprint and jump disabled (per frame only while needed) |
| arm fracture | `HAND_SHAKE` while aiming, scaled (splint halves it) |
| head injury / concussion | short `Dont_tazeme_bro` spells, stumbles while sprinting (grade ≥ 2) |
| blood loss | `rply_saturation_neg` from 12 % loss, `rply_vignette` from 18 % |
| pain ≥ 35 | `DRUNK_SHAKE` sway scaled by pain |
| hypoxia / breathless | out-of-breath anim when still, hurt face, `DrugsDrivingIn` blur pulses, vignette |
| server `fx.blur` / `fx.drunk` / `fx.cold` | blur pulses / drunk walk + sway / shiver sway |

`SetMoveOverride` beats the injury walk; `false` suppresses the injury walk, `nil` removes
the override. Latest override wins.

**GTA health sync** (`Config.Physiology.syncHealth` and the snapshot's `syncHealth`): the
health bar follows the self snapshot `health` (0..100, ~0 at `Config.Wounded.lossDown`) by
deltas: rises with transfusions/healing, is capped by blood, GTA damage stays visible, fully
healed → max. The sync never lowers health below 12 % of the bar, so it can never kill.

## NZA.Damage (damage.lua)

Reports `nza:damage` (§17) for the local ped only:
`{ weapon (signed hash), weaponName?, group ('GROUP_PISTOL'), bone, region, damage, armour,
hits, attacker (server id | 0), attackerNet?, melee, fatal?, fall?, speedDrop?, belted?,
seatbelt?, fire?, drown? }`.

- **Hits**: `CEventNetworkEntityDamage` with victim = own ped. Damage = health delta
  (100..200 player range), armour delta separately. Region from `GetPedLastDamageBone`,
  `chest` becomes `back` when the attacker stands behind. Bursts within 200 ms with the same
  weapon + region + attacker are merged (`hits = n`). Max 15 reports / s.
- **Falls**: height tracked while falling or ragdolling in the air (parachute canopy resets
  it), sent on landing when ≥ `Config.Damage.fall.minHeight` (water landings × 0.3, ignored
  under 20 m). Merged into GTA's `WEAPON_FALL` report, or sent alone after 450 ms.
- **Crashes**: speed drop per 100 ms ≥ `Config.Damage.vehicle.minSpeedDrop` with a real
  collision (collided flag or body/engine damage). Belt detection order:
  `Config.Damage.vehicle.seatbeltExport` (`{ resource, fn }` or a function) → state bags
  `seatbelt / seatbeltOn / isSeatbeltOn / harness / belt` → qb-smallresources harness →
  `seatbelt:client:ToggleSeatbelt` event → ped config flag 32 (windscreen ejection off).
  Motorcycles and bicycles are never belted.
- **Fire**: one report every `Config.Damage.fire.tick` ms while on fire (`fire = true`).
- **Drowning**: underwater (swimming or in a submerged vehicle) with no air left → every 2 s
  `drown = true`.
- **GTA death**: resurrected in place at once (next to the vehicle door when in a vehicle,
  on the water surface when in water, after a falling body lands), health 50 %, blood decals
  kept, death post-effects stopped. `nza:down { weapon, weaponName, group, attacker,
  attackerNet, region, bone, drown?, vehicle?, fall?, fire? }` is sent once — only while the
  patient is `alive` and not within 5 s of the previous one; pending damage is flushed first.
  While already down the ped is still resurrected (wounded anims need a living ped) but
  nothing is reported; 4+ deaths in 15 s add a growing back-off. spawnmanager auto-spawn,
  `PauseDeathArrestRestart`, fade-out after death are disabled.
- Bus: `self:down (info)` after `nza:down`, `self:resurrected (wasAlive)` after every resurrect
  (the wounded module re-applies its pose on it).

```lua
NZA.Damage.SyncBaseline()   NZA.Damage.IsBelted(ped?, veh?)   NZA.Damage.WeaponName(hash)
```

## NZA.Target & NZA.Interact (target.lua)

```lua
NZA.Target.FromEntity(ent, any)   -- { kind='player', sid } | { kind='npc', net } | nil
NZA.Target.Entity(target)         NZA.Target.State(entOrTarget)
NZA.Target.Self()  NZA.Target.IsSelf(t)  NZA.Target.Same(a, b)  NZA.Target.Key(t)  NZA.Target.Distance(t)

NZA.Interact.Add({ name, label, icon, faIcon?, description?, order = 50, perm,
                   states = { alive = true, ... } | { 'alive', ... },
                   self = false, npc = true, player = true, bag = false, whileDown = false,
                   distance = 2.0,
                   canInteract = function(entity, target, stateBag) return true end,
                   onSelect = function(entity, target) end })
NZA.Interact.Remove(name)  NZA.Interact.Get(name)  NZA.Interact.All()
NZA.Interact.Options(entity)  NZA.Interact.Open(entity?)  NZA.Interact.OpenNearby()
```

- NPC patients are networked peds whose `Entity(ped).state.nza` exists.
- **Body bags**: options with `bag = true` show on props of model `Config.Props.bodybag`
  near the player. The bodybag module sets `Entity(bagProp).state.nzaBag = target` on the
  networked prop; `FromEntity(bag)` then returns that patient and `State(bag)` its state bag.
- Options are rebuilt into `Bridge.Target.Player` / `Bridge.Target.Ped` 300 ms after the
  last `Add` / `Remove` (first build 1 s after start). Each option is filtered at runtime:
  downed medic (unless `whileDown`), self/player/npc/bag flags, `NZA.Perm(perm)`, patient
  state (`alive` when the player has no bag yet), distance, `canInteract`. Lookups are cached
  250 ms per entity (target scripts poll every frame).
- `distance` defaults to 2.0 m (same value is handed to the target script).
- `onSelect` always runs in a fresh thread (safe to await, e.g. `NZA.Proc.Run`).
- Context menu icons: `faIcon` if given, else the NAYZEEE `icon` mapped through
  `Bridge.FaIcon` (ox_lib wants Font Awesome names).
- Self-treatment and keyboard users: `NZA.Interact.Open(entity)` shows the same options in an
  ox_lib context menu. Keybind `nza_interact` (unbound by default, Settings → Key Bindings →
  FiveM) and command `/nzainteract` (`Config.Commands.interact` if the lead adds it,
  `false` disables) open it for the patient in front of you, otherwise for yourself.

## NZA.Patient (patient.lua)

```lua
local snap, err = NZA.Patient.Get(target)          -- callback 'nza:patient:get'
local stop = NZA.Patient.Watch(target, function(snap, reason) end, { maxDist, keep, initial })
NZA.Patient.Last(pid)
```

`fn(snapshot)` for the initial snapshot and every `nza:patient:update` push; `fn(nil, reason)`
once when the watch ends by itself (`far`, `gone`, `denied`, `removed`). Default `maxDist` is
`Config.Physiology.examDistance + 2`; `keep = true` never auto-stops on distance. Watches on
the same patient share one server subscription.

## NZA.Treat & NZA.Proc (proc.lua)

```lua
local ok, result = NZA.Treat.Do('bandage', target, payload, { silent = false })

local ok, outcome = NZA.Proc.Run('suture', target, payload, function(ctx)
    NZA.UI.Open('suture', ctx.data)
    ctx.onEnd(function() NZA.UI.Close('suture') end)
    NZA.UI.On('suture', 'result', function(d, cb) cb({}) ctx.finish({ score = d.score }) end)
end, { label = 'Suture', anim = { dict, clip, flag } })
NZA.Proc.Active()  NZA.Proc.Abort(reason)
NZA.Anim.Kneel(ped)  -- enter → loop, NZA.Anim.Stop(ped) plays the exit clip
```

- `Proc.Run` blocks until the session ends; returns `true, outcome` or `false, reason`.
- Easy mode (`resp.easy`): ox_lib `progressBar` / `progressCircle` (`Config.EasyMode.style`)
  for `resp.easyTime` s with a fitting animation (CPR pumping for `cpr`, kneel for a lying
  patient, standing treatment for an upright one, self-treatment on yourself), then finish
  with `{ score = Config.EasyMode.score, easy = true }`.
- Auto-cancel (watchdog 250 ms): medic went down, patient entity gone, medic more than
  `maxDist + 2` m away (server aborts at +4), patient died during it, `maxTime` reached.
  Server-side aborts arrive as `nza:proc:aborted (token, reason, msg)`.
- `ctx.finish` waits out `minTime` before calling the server so a fast player is never
  rejected; the result toast shows the server message and the grade (`NZA.Util.Grade`).
- Error toasts use the server's localized `msg`, else `core_client.err.<code>`.
- Bus: `proc:started (ctx)`, `proc:ended (name, ok, outcome|reason)`.

## NZA.Cam (cam.lua)

```lua
NZA.Cam.Orbit(target, { dist = 2.2, height, fov = 45, pitch = 20, yaw, front, minDist, maxDist,
                        orbit, pan, zoom, panLimit, ease = 600, hideHud = true })
NZA.Cam.Close(entity, boneId | 'region' | vec3offset, { dist = 0.75, pitch = 55, fov = 40, orbit = false })
NZA.Cam.TopDown(entity, height = 3.0, opts)
NZA.Cam.Stop(ease)  NZA.Cam.Update(opts)  NZA.Cam.Recenter()  NZA.Cam.Active()  NZA.Cam.Focus()
NZA.Cam.Raycast({ x, y, dist, flags, ignore }) → { hit, coords, entity, normal, origin, dir, x, y }
NZA.Cam.ScreenToWorld(sx, sy) → origin, dir     NZA.Cam.WorldToScreen(coords) → x, y, visible
NZA.Cam.CursorPosition() → sx, sy
```

Controls: right-mouse drag orbit, Shift + right-mouse pan, wheel zoom, R recentre; smoothing
on everything; all player controls disabled except push-to-talk while a rig is active.
Starting a rig while another runs blends between them. Game mouse input works when no NUI has
focus or the focused app uses `keepInput = true`; otherwise the JS can forward drags through
`_core:camInput`.

## NZA.Anchors (anchors.lua)

```lua
NZA.Anchors.Track('suture', { wound = { entity = ped, bone = 24818, offset = vector3(0, 0.1, 0) },
                              tray = { coords = vector3(...) } })
NZA.Anchors.Set(app, id, def)  NZA.Anchors.Remove(app, id)  NZA.Anchors.Clear(app)
NZA.Anchors.Project(def) → x, y, visible, dist
```

Sends action `anchors` `{ [id] = { x, y, visible, d } }` every 33 ms, only when something
moved. `Clear` sends an empty table once (arrives in JS as `{}` or `[]`).

## NZA.Props & NZA.Anim (props.lua)

```lua
local obj, netId = NZA.Props.Spawn('ivstand', vector4(x, y, z, h), { group = 'field', network = false,
    freeze = true, collision = true, fallbackKey, ground, rot, alpha, timeout = 5000 })
NZA.Props.Spawn('syringe', { attach = { entity = ped, bone = 57005, pos = vec3, rot = vec3 } }, { group = 'x' })
NZA.Props.Delete(obj)  NZA.Props.Clear(group)  NZA.Props.Group(group)  NZA.Props.Resolve(model)
NZA.Anim.Play(ped, dict, clip, { flag = 1, blendIn, blendOut, duration, rate, wait, scenario, prop })
NZA.Anim.Stop(ped, { immediate, token })  NZA.Anim.Current(ped)
```

Model may be a `Config.Props` key, a model name or a hash. Missing custom models fall back to
`Config.PropFallbacks[key]`. Every prop is deleted on resource stop.

## NZA.Points (points.lua)

```lua
NZA.Points.RegisterType('xray', { label, icon, prop = Config.Props.xray_table, needsHeading = true,
    data = {}, radius = 1.2, distance = 2.0, ground = false,
    onSpawn = function(point, entity) end, onRemove = function(point) end,
    target = { { label = 'X-ray: Chest', icon = 'scan', perm = 'xray', name?, distance?,
                 canInteract = function(point, entity) end, onSelect = function(point, entity) end } } })
NZA.Points.All(type?)  NZA.Points.Get(id)  NZA.Points.Nearest(type, coords?, maxDist?)
NZA.Points.Types()  NZA.Points.Type(name)  NZA.Points.Entity(id)  NZA.Points.Refresh(id?)
```

Streams within 60 m (out at 70 m), props frozen at the point coords/heading
(`point.model` overrides the type prop), targets on the prop or on a sphere when there is no
prop, options filtered by `NZA.Perm` and own state, `onSpawn` / `onRemove` called, type
defaults filled into `point.data`. Bus `points:changed (reason, arg)`.

## Staff (staff.lua)

```lua
NZA.Perm(perm)  NZA.Easy(perm)  NZA.IsMedic()  NZA.OnDuty()  NZA.Staff.Get()  NZA.Staff.Refresh()
```

Record from `nza:staff:update` (fallback fetch `nza:staff:get` after 4 s). `Config.PublicPerms`
are always granted; off-duty medics keep only those when `Config.Jobs.requireDuty`. Before a
record arrives police get `Config.PolicePerms`. Bus `staff:changed (record)`.

## Compatibility (compat.lua)

Exports on `nayzeee-ambulance`: `isDead`, `IsDead`, `isPlayerDead`, `GetDeathStatus` (arrest or
dead), `isDowned`, `isPlayerDowned` (not alive), `isInLastStand` (wounded), `GetState`,
`GetSelfSnapshot`. Own replicated state bags: `isDead`, `dead`, `inLastStand`, `laststand`,
`isDowned`. ESX: local `esx:onPlayerDeath` when going down and `esx:onPlayerSpawn` on revive.
Third-party client revive events (`hospital:client:Revive`, `esx_ambulancejob:revive`) are
intentionally ignored — revives only come from our server (`nza:revived`).

---

## Config keys read

`Config.UI.*`, `Config.Locale`, `Config.Physiology.syncHealth / deathLoss / examDistance`,
`Config.Wounded.lossDown`, `Config.Damage.*` (enabled, groups, weapons, fall.minHeight,
fall.fractureHeight, vehicle.enabled / minSpeedDrop / seatbeltExport, fire.enabled / tick,
drowning.enabled), `Config.EasyMode.style / score / default`, `Config.Jobs.requireDuty`,
`Config.PublicPerms`, `Config.PolicePerms`, `Config.Props`, `Config.PropFallbacks`,
`Config.Commands.interact` (optional).

## Events

| Event | Dir | Handled / sent here |
|---|---|---|
| `nza:damage` | C→S | sent |
| `nza:down` | C→S | sent |
| `nza:proc:abort` | C→S | sent |
| `nza:self:update` | S→C | handled |
| `nza:patient:update` | S→C | handled |
| `nza:staff:update` | S→C | handled |
| `nza:points:sync / upsert / remove` | S→C | handled |
| `nza:ui:toast`, `nza:ui:speech` | S→C | handled |
| `nza:revived` | S→C | handled → bus `self:revived` |
| `nza:proc:aborted` | S→C | handled |

Callbacks used: `nza:self:get`, `nza:patient:get`, `nza:patient:watch`, `nza:treat`,
`nza:proc:start`, `nza:proc:finish`, `nza:staff:get`.

Client bus events emitted: `self:state`, `self:update`, `self:revived`, `self:down`,
`self:resurrected`, `ui:closed`, `points:changed`, `staff:changed`, `proc:started`, `proc:ended`.

## Known limits

- Damage attribution uses the last damaged bone; GTA reports one bone per event, so a
  shotgun blast spread over the body becomes one merged report per region.
- The seatbelt fallback (ped config flag 32) reads as "belted" on servers that disable
  windscreen ejection for everyone; set `Config.Damage.vehicle.seatbeltExport` there.
- Weapon hashes are sent signed; core-server normalises them (`u32`).
- Self-targeting through eye-target scripts is not possible (they never target your own
  ped); self options are reached through the interact menu.
- The orbit camera reads game mouse input; apps that keep the mouse in the NUI without
  `keepInput` must forward drags through `_core:camInput`.
- Body bag options require the bodybag module to put `nzaBag = target` on the bag prop's
  state bag.
