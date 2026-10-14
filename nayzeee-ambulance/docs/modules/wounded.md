# wounded — downed stage, death & respawn

Everything the local player goes through between "GTA health hit 0" and "back on their feet":
the downed pose and crawl, the bleed-out clock HUD, calling EMS, giving up, cardiac arrest,
the death screen, the respawn at a hospital and the get-up afterwards. The core owns the
physiology (clock, state machine); this module reacts to it and is the only place that
draws it for the patient.

## Files

| File | What it does |
|---|---|
| `client/modules/wounded.lua` | State machine on `self:state`, HUD app `wounded`, control loop (blocked controls, crawl input), keybinds (call / give up / respawn), hold-to-confirm, call EMS, live status / help events, fallback medic alert, radar, health top-up while down |
| `client/modules/wounded_pose.lua` | Ragdoll → downed pose by injury, still pose when unconscious / arrest / dead, re-apply after resurrects and carries, crawl (root motion or own movement with an obstacle probe), crawl strength, get-up sequence |
| `client/modules/wounded_fx.lua` | Timecycle desaturation + vignette by blood loss, black & white in arrest / death, screen blur while unconscious, sway, the death orbit camera |
| `client/modules/wounded_death.lua` | Death screen app `death`, respawn hold, fade / teleport / bed / stand-up sequence |
| `server/modules/wounded.lua` | `nza:wounded:callEms`, `nza:wounded:giveUp`, `nza:wounded:info` callback, live status loop (CPR, medic examining, medic on scene), cause of death in plain words, `NZA.Wounded.Help` |
| `server/modules/wounded_respawn.lua` | `nza:respawn`, respawn point (hospital or fallback), beds, fee + insurance, item / cash loss, revive, `NZA.Wounded.ForceRespawn` |
| `config/modules/wounded.lua` | `Config.WoundedUI` (HUD, keys, effects, poses, crawl, death camera), `Config.Respawn` (fallback spots, beds, fade) |
| `locales/en/wounded.lua` | `wounded.*` strings (Lua + both NUI apps) |
| `html/apps/wounded/` | Downed HUD (HUD design) |
| `html/apps/death/` | Death screen (full-screen HUD) |

## Features

### Going down
- `alive → wounded/arrest`: short ragdoll (`Config.WoundedUI.ragdollMs`), then a pose that fits the
  worst injury (`Config.WoundedUI.poseRules`): clutching/writhing for torso wounds, on the back for
  leg/pelvis/head injuries, curled on the side for arm injuries. AVPU P/U, arrest and death use a
  completely still pose. The first animation of each list that exists in the game is used.
- Relog / restart re-entry: same path (core re-applies the saved state bag), without the ragdoll.
- The pose is re-applied after a core resurrect and whenever it was lost, but **never** while the
  player is attached to something, carried / on a stretcher / in a body bag (state bag), in a
  vehicle, swimming, or while a module suspended it (`NZA.Wounded.SuspendPose`). Dropped from a
  shoulder above the ground → falls naturally first. Ragdoll from other players bumping into you
  is off while down, so the body stays where it was put.
- GTA can't kill a downed player again: health is topped up (and the damage baseline re-synced),
  so further hits still become injuries (`Config.Wounded.invincible`).
- Blocked while down: `Config.Wounded.disableControls` + movement, sprint/jump/cover, enter vehicle,
  melee, weapon wheel, context keys; in a vehicle also exit / drive. Chat, voice, the phone and
  the pause menu stay usable. Our own keys are ignored while the phone or any focused NUI is open.

### Crawl (`Config.Wounded.crawl`, `crawlSpeed`, `Config.WoundedUI.crawl`)
- W starts crawling, S stops (`toggle = false` → crawl while W is held), A / D turn.
- Only while `wounded`, conscious (AVPU A/V) and not held/moved by anyone.
- Uses the crawl clip's root motion, speed scaled with `SetEntityAnimSpeed`; if the clip has none,
  the module moves the ped itself with a forward obstacle probe and ground following (no walking
  through walls, no stepping off ledges).
- Strength meter: `stamina` seconds of crawling, drains faster with heavy blood loss
  (`lossPenalty`), slower crawl with an unsplinted broken arm (`armPenalty`); at 0 you stop
  ("Too weak — rest a moment") and recover in `recover` seconds.

### Wounded HUD (`html/apps/wounded`, opened without focus)
- Flip clock: the bleed-out clock from the state bag, interpolated locally each second (with the
  core's `clockRate` for slow oozes), red under `criticalClock`, teal + paused when stabilized.
  In arrest it counts the time until death (`Config.Death.arrestToDeath`) and turns teal "held by
  CPR" while compressions are running.
- Title `WOUNDED / UNCONSCIOUS / CARDIAC ARREST`, a live heartbeat line next to it (fast and weak
  with blood loss, flat with agonal blips in arrest, compressions during CPR).
- Status line: `BLEEDING SLOWLY / BLEEDING / BLEEDING HEAVILY · STABILIZED — CLOCK PAUSED ·
  NO PULSE — CPR NEEDED · CPR IN PROGRESS · BEING CARRIED / ON A STRETCHER / IN TRANSPORT /
  IN A BODY BAG · A MEDIC IS TREATING YOU · MEDIC ON SCENE · MEDIC ON THE WAY · ETA m:ss ·
  AI PARAMEDIC RESPONDING · EMS NOTIFIED · NO MEDICS ON DUTY`.
- Help card above the panel (glowing-bar note): medic on the way with unit and ETA countdown +
  progress, AI paramedic, medic on scene, medic examining you, CPR in progress (with the medic's
  name), EMS notified (medics on duty), no medics on duty.
- Injury chips (region + type, worst first, as many as fit on one line, rest as `+N`): red with a
  pulsing dot while bleeding, teal `TQ` with a tourniquet, teal splint / check when treated.
  No exact vitals are ever shown to the patient.
- Key hints: `W Crawl · S Stop · A D Turn` (live strength meter while crawling, or "You can't move"
  / "Someone is moving you"), `G Call EMS` (spinner while calling, ✓ EMS called + cooldown),
  `E Give up` with a red hold ring, locked with a countdown until `Config.Wounded.giveUp.minTime`.
  Key caps show the player's own bindings.
- Screen: NUI vignette scaling with blood loss, red edge pulse on every heartbeat, slow eyelid
  fades while unconscious, deep fades in arrest; heartbeat sound (WebAudio, `NZA.audio`);
  game-side desaturation + vignette, blur while unconscious, black & white in arrest, slight sway.

### Call EMS (G)
- Server cooldown `Config.Wounded.callEms.cooldown`; refused while unconscious when
  `callWhileUnconscious = false`.
- `NZA.Dispatch.Create({ code, priority = NZA.Patients.Triage(pid), title (from the worst injury,
  arrest, unconscious or deceased), type, coords (server), caller, message, patients = { pid },
  npc = false, source = 'player' })`, call id stored in `meta.callId`.
- No medic on duty and `NZA.AIMedic` installed → `NZA.AIMedic.Request(pid, { callId })`.
- Without the dispatch module: `Bridge.Dispatch.External(call)` (if enabled in the bridge) and every
  on-duty medic gets a toast + flashing blip for `fallbackBlip.time` seconds.
- Dead players: "Request body recovery" (P3 deceased call, `bodyRecoveryCall`).
- The reply shows on the HUD (flash + help card); `nza:wounded:help` from dispatch / AI medic
  turns it into "medic on the way · ETA".

### Give up (hold E)
- After `Config.Wounded.giveUp.minTime` seconds down (server clock), held for
  `Config.Wounded.giveUp.hold` seconds → `NZA.Patients.SetState(pid, 'dead', 'gave_up')`.
- Also in arrest (`giveUpInArrest`). Blocked while a medic is examining you or doing CPR
  unless `giveUpWhileTreated = true`.

### Death screen (`html/apps/death`)
- `DECEASED` over a flatline, time of death (server time), time dead, name.
- Cause of death in plain words: the reason (gave up, bled out, heart stopped, catastrophic head
  wound, drowned, collapsed lung, ...), the three worst injuries ("Critical gunshot wound · Chest"),
  blood lost (% and litres), up to two conditions, time without a pulse, "+N more injuries".
- Respawn card: hospital name, `Config.Death.respawnTimer` countdown (flip clock + progress), then
  "Hold E to respawn at <hospital>" with a teal hold fill; bill (fee, insurance plan and cover from
  `NZA.Insurance.Get`, you pay), chips for healed / items kept-lost / cash kept-lost.
- Note: EMS can still recover the body (or "You are in a body bag"), G requests body recovery.
- Slow orbit camera over the body (keeps under ceilings, follows the body if it is moved).
- Re-entry after relog shows the remaining timer (server `deadAt`).

### Respawn
- `nza:respawn` → validated (dead, timer, rate limit, one at a time) → `NZA.Hospitals.RespawnPoint(coords)`
  or the nearest `Config.Respawn.points` entry → free bed (`NZA.Hospitals.FreeBed` + `OccupyBed`,
  or a fallback bed) → client fades out, teleports, waits for collision → ack → server checks the
  position (moves the ped itself if needed; also after `ackTimeout`) → `NZA.Patients.Revive(pid,
  { full = Config.Death.clearInjuries })` → `Bridge.Inv.Clear(src, Config.Death.keepItems)` when
  `loseItems`, all cash when `loseCash` → `NZA.Billing.Charge` (applies insurance) or
  `Bridge.RemoveMoney` (bank, then cash) with `NZA.Insurance` cover, paid into `Config.Billing.society`.
- In a bed: lie there `Config.Respawn.bedTime` seconds, fade, stand up beside it. Bed released
  10 s later (`NZA.Hospitals.ReleaseBed`).

### Revive
- `self:revived` / state back to `alive`: HUD and effects go at once, then the get-up sequence
  (`poses.getUp`) plays once even when the state bag and `nza:revived` arrive in either order.
  ROSC (arrest → wounded) keeps the downed stage.

## Controls

| Key (default) | Where | Action |
|---|---|---|
| W / S / A / D (movement keys) | wounded, conscious | crawl / stop / turn |
| G (`Config.Wounded.callEms.key`) | wounded, arrest, dead | call EMS / request body recovery |
| E hold (`Config.WoundedUI.keys.giveUp`) | wounded, arrest | give up (after minTime) |
| E hold (`Config.WoundedUI.keys.respawn`) | dead | respawn at a hospital (after the timer) |

G and E are ox_lib keybinds (`nza_wounded_call`, `nza_wounded_giveup`, `nza_wounded_respawn`) —
players can rebind them in Settings → Key Bindings → FiveM; the HUD shows the bound key.

## Config

`Config.Wounded` (core config): `enabled, lossDown, maxClock, minClock, stableBleed, noBleedClock,
crawl, crawlSpeed, giveUp { enabled, hold, minTime }, callEms { key, cooldown }, invincible,
disableControls`.
`Config.Death` (core config): `arrestToDeath, respawnTimer, respawnHold, respawnFee, loseItems,
keepItems, loseCash, clearInjuries`.
`Config.Billing.account / society` for the fallback fee.

`Config.WoundedUI` (this module): `criticalClock, showInjuries, maxInjuryChips, pulseLine,
timeFormat, hideRadar { wounded, dead }, keys { giveUp, respawn }, callWhileUnconscious,
bodyRecoveryCall, aiMedic, codes { injured, arrest, dead }, fallbackBlip { sprite, colour, scale,
time }, giveUpInArrest, giveUpWhileTreated, onSceneDistance, cprWindow, effects { overlay,
timecycle, bloodModifier, vignetteModifier, unconsciousBlur, arrestMono, heartbeat,
heartbeatVolume, cameraShake }, deathCam { enabled, height, radius, fov, speed }, ragdollMs,
poses { writhe, back, side, still, crawl, bed, getUp }, poseRules, defaultPose, crawl { toggle,
turnSpeed, speed, armPenalty, stamina, recover, lossPenalty }`.

`Config.Respawn`: `fadeMs, useBed, bedTime, bedOffset, ackTimeout, points { { label, coords, beds } }`
(Pillbox Hill, Sandy Shores and Paleto Bay defaults; only used while no hospital has a respawn
point built in game).

## Events, callbacks, APIs

| Name | Dir | Payload |
|---|---|---|
| `nza:wounded:callEms` | C→S | — |
| `nza:wounded:giveUp` | C→S | — |
| `nza:respawn` | C→S | — (§17) |
| `nza:wounded:arrived` | C→S | `token` |
| `nza:wounded:called` | S→C | `{ ok, kind = sent/recovery/cooldown/unconscious/failed, medics, ai, callId, cooldown, left, text }` |
| `nza:wounded:status` | S→C | `{ cpr, cprBy, treating, onScene, called, callId }` (only on change) |
| `nza:wounded:help` | S→C | `{ eta = seconds, unit = 'Unit 04 · J. Doe', ai = bool, status = 'enroute'/'onscene'/'cancelled' }` |
| `nza:wounded:respawn` | S→C | `{ token, coords, bed, label, fadeMs, bedTime }` |
| `nza:wounded:alert` | S→C | `{ title, code, priority, name, coords }` on-duty medics, only without the dispatch module |
| `nza:wounded:info` | callback | `→ { state, downFor, giveUp, giveUpIn, giveUpHold, callLeft, cooldown, called, medics, dead = { deadFor, respawnIn, hold, tod, name, cause = { { icon, text, tone, lead } }, bagged, respawn = { hospital, fee, cover, plan, pay, loseItems, loseCash, heal } } }` |

Server API (`NZA.Wounded`):
- `Help(srcOrPid, { eta, unit, ai, status })` — show help on the downed player's HUD (dispatch, AI medic).
- `ForceRespawn(src, { coords = vec4?, label?, fee = false?, bed = false? })` — run the respawn flow now
  (morgue processing, admin tools).
- `RespawnPoint(src, p)`, `RespawnPreview(src, p)`, `CauseLines(p)`, `OnDuty()`.
- Bus (server): `wounded:called (src, p, callId)`, `wounded:gaveUp (src, p)`, `wounded:respawned (src, p, spot)`.

Client API (`NZA.Wounded`):
- `Active()` → `'wounded' | 'arrest' | 'dead' | nil`.
- `SuspendPose(name, on)` — modules that animate a downed player **without attaching** (beds, the
  ambulance bay, body bag) call this so the downed pose is not re-applied over their animation.
  Attached / carried / stretcher / bag / in-vehicle are detected automatically.

NUI apps: `wounded` (actions `open state injuries fx hold flash`), `death` (actions
`open info state hold flash`). Neither takes NUI focus; neither posts callbacks.
Previews: `index.html?app=wounded&demo=bleeding|stable|unconscious|arrest|cpr|crawl|help|nomedic|carried`
and `index.html?app=death&demo=wait|ready|bagged|gaveup` (G / hold E work in the preview).

## Integration notes for other modules
- **dispatch / AI medic**: call `NZA.Wounded.Help(pid, { eta, unit, ai, status })` when a unit is
  assigned / arrives (`status = 'onscene'`) / the call is cancelled (`'cancelled'`). Calls made here
  carry `source = 'player'` and `patients = { pid }`.
- **cpr**: `NZA.Patients.Cpr(pid, src, quality)` is all that is needed — the HUD shows CPR in progress
  within a second (`lastCpr` ≤ `cprWindow` s) and the medic's name from `meta.cprBy`.
- **transport / bodybag**: keep setting `meta.carried / stretcher / bodybag` through `SetMeta`; play
  your own animations on the downed player while attached; use `SuspendPose` for unattached anims.
- **hospital**: `RespawnPoint(coords)` may return a point `{ id, hospital, coords = vector4, label? }`
  or a vector4; `FreeBed(hospitalId)` a bed point `{ id, coords = vector4 }` whose coords are where
  the patient lies; `Get(id).label` is the name shown on the death screen.
- **billing**: `NZA.Billing.Charge(src, fee, reason, { kind = 'respawn', pid })`; return `false` on
  failure so the bank/cash fallback runs.

## Known limits
- Animations are configurable lists; servers with custom anim packs can swap them. If none of a
  list exists the still pose (`dead / dead_a`) is used.
- Fallback respawn beds are empty by default (MLO-specific); hospital beds come from the hospital
  module.
- Time of death uses the server clock (`os.date`), not the in-game clock.
- The heartbeat sound is synthesized in the NUI (no audio files) and follows `Config.UI.sounds`.
- Verified with stubbed-native smoke tests (client state machine, crawl, respawn; server call /
  give up / respawn / billing) and headless browser previews — not on a live server here.
