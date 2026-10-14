# Module: calls

NPC 911 calls, the scenes they happen in, NPC patient behaviour, recorded caller voices and
the AI medic.

## Files

| File | What it does |
|---|---|
| `server/modules/calls.lua` | `NZA.Calls` API: generator, scene lifecycle (pending → building → active → closing), builder choice, follow-up calls, admin commands |
| `server/modules/calls_scene.lua` | Plans a scene from a template (vehicles, victims, props, effects, caller, onlookers). Checks the entities the builder reports and turns the victims into NPC patients |
| `server/modules/calls_npc.lua` | `nzaNpc` / `nzaBy` state bags, patient speech, bystanders, crew tracking, hand-over and rewards, release on scene, extrication, putting out fires |
| `server/modules/calls_aimedic.lua` | `NZA.AIMedic` server: jobs, care, hospital bed, billing, watchdog |
| `client/modules/calls.lua` | Scene builder, particle effects, ground decals, cut-engine / smother / extinguisher, cut free, bystanders, patient options, fallback page |
| `client/modules/calls_npc.lua` | `NZA.CallsNpc`: poses and behaviour of **every** NPC patient, cosmetic damage, speech playback |
| `client/modules/calls_aimedic.lua` | Drives the AI ambulance and its crew on the controller client |
| `config/modules/calls.lua` | `Config.Calls` and `Config.AIMedic` |
| `locales/en/calls.lua` | `calls.*` strings (titles, caller lines, patient and bystander lines, prompts) |
| `html/audio/calls/*.ogg` | 77 recorded voice files (Opus, mono, 48 kHz, 15–45 kB each, 2.3 MB in total) |

## Features

### Call generation
- A server timer runs while at least `generation.minMedics` medics are on duty with NPC calls on.
  The switch is `Player(src).state.nzaNpcCalls`, owned by the dispatch module (radial → Dispatch
  → NPC calls, pager menu, dispatch board). A medic who never used the switch counts as opted in
  (`optInDefault`).
- The first call comes `firstDelay` seconds after enough medics are on duty. After that, one comes
  every `interval` seconds. Each extra medic makes the wait 15 % shorter, up to 60 % (`perMedicSpeedup`).
- Caps: `maxActive` calls at once, and at most `maxPerMedic` per opted-in medic.
- The template is a weighted pick. The type of the last call gets its weight multiplied by
  `repeatType`.
- The location comes from the template's pool:
  - at least `minDistance` from every medic;
  - within `maxDistance` of one medic, relaxed when nothing fits;
  - `sceneSpacing` from other open scenes;
  - not used in the last `locationCooldown` seconds.
- The call goes through `NZA.Dispatch.Create` with:
  - code, priority, title and type;
  - caller name and 555 number;
  - the caller's words as the card message;
  - `voice = 'audio/calls/<line>_full.ogg'`, relative to `html/`, as the call card expects;
  - `npc = true`, `source = 'npc'`, `meta = { scene, scenario }`.
- Without the dispatch module, opted-in medics get a fallback page: a toast, a route blip and
  `Bridge.Dispatch.External`.

### Scenario templates (11, all data-driven)

| Key | Code / P | What you find |
|---|---|---|
| `overdose` | 10-56 · P2 | Opioid overdose in an alley or park, with a syringe, pills and bin bags. Unconscious, snoring or obstructed airway, hypoxia. Sometimes a second, drowsy user sits nearby. Treat with naloxone. |
| `mva` | 10-50 · P1 | A crashed, smoking car (sometimes burning) and often a second car. Up to 3 victims: the driver (trapped 40 %), the passenger, and a pedestrian or thrown occupant. Fractures, internal bleeding, lacerations, pelvis injuries, concussion, possible spinal injury. Debris and tyres on the road. |
| `fall` | 10-52 · P1 | Construction site, docks, quarry or barn, with work barriers, tools and cement bags. Leg, arm and pelvis fractures, head and back contusions, concussion, spinal injury. |
| `gunshot` | 10-52 · P1 | Street shooting with 1–2 victims and 1–3 gunshot wounds each. 10 % arrive in PEA arrest. |
| `stabbing` | 10-52 · P1 | Outside a bar or club. Stab wounds to the abdomen, chest, back or thigh, plus defence cuts. |
| `drowning` | 10-52 · P1 | Beach, lake or pool, with towels, a lilo or a ring. The patient is soaked, with hypoxia (water in the lungs → crackles) and often hypothermia. 25 % are in asystole with a bystander doing CPR. |
| `burn` | 10-52 · P1 | BBQ, house or trailer fire, with a burning grill, a gas bottle and smoke. Arm, face, chest and leg burns, smoke-inhalation hypoxia, airway swelling. |
| `cardiac` | 10-52 · P1 | A jogger collapsed in VF. A bystander does CPR until a medic is close. |
| `elderly` | 10-52 · P3 | Elderly fall, with a walking stick and shopping. A displaced femoral neck fracture, wrist fracture and head cut. Sometimes cold. |
| `assault` | 10-52 · P2 | Beaten up: contusions, lacerations, facial and rib fractures, concussion (80 %). |
| `crush` | 10-52 · P1 | Industrial accident under a forklift and a pallet load. Pinned (60 %). Pelvis and leg fractures, internal bleeding. |

Each template has:
- `weight priority code type title snap reward`;
- 9–15 `locations` across the whole map (city, Sandy Shores, Grapeseed, Paleto, the coast);
- `victims` roles: count, chance, ped pools by sex, age, offset or vehicle seat, state weights,
  pose hint, blood loss, injuries and conditions with ranges and chances, trapped chance, GTA
  damage packs;
- `vehicles`: pool, damage per side, smashed windows, open doors, burst tyres, smoke and fire
  chances, flip;
- `props`, optionally with a fire or smoke effect on the prop;
- free `fx`;
- `bystander`: the 911 caller, or a CPR bystander;
- `onlookers`;
- `callers`: voice line ids and the caller's sex;
- `dispatcher`.

### The scene
- Nothing exists in the world until a medic is within `scene.spawnRadius`. The nearest medic's
  client then gets the plan: models, offsets and poses only, never injuries.
- The builder client:
  - snaps the place to the kerb (`snap = 'road'`) or to walkable ground (`'ped'`);
  - spawns networked entities;
  - reports the net ids.
- The server checks every entity: it must exist, have the planned model and be within
  `buildRadius`. Anything else is deleted. If the build fails or times out, the server asks
  another medic, up to `maxBuildAttempts` times.
- Each victim becomes `NZA.Patients.CreateNPC{ net, injuries, conditions, loss, state,
  meta = { scenario, callId, scene, trapped } }`. Dispatch adds them to the call through
  `meta.callId`.
- Entities get `SetEntityOrphanMode(KeepEntity)`, so a scene survives its builder leaving.
- **Wrecks**:
  - real deformation from several `SetVehicleDamage` hits per side;
  - smashed windows, hood or doors open, burst tyres, dirt;
  - hazard lights, headlights and dome light on;
  - low engine health, so GTA draws its own engine smoke.
- **Effects**:
  - engine smoke plume on the engine bone, engine fire, grill fire, ground smoke;
  - every client within `fx.radius` draws them;
  - they stop when put out, or by themselves after `fx.duration`, counted from the build.
- **Putting it out**:
  - smoke on a car that is no longer burning → hold **E** at the engine to *Cut the engine*;
  - fire → spray it with the fire extinguisher for `spray.time` seconds;
  - ground smoke (or fire, when `fireNeedsExtinguisher = false`) → hold **E** to *Smother the fire*.
  - The server checks the distance, the weapon in hand and that the engine is not still burning.
- **Ground detail** (decals, local to each client, nothing networked):
  - a blood pool under each bleeding patient. It grows with the bleeding (state bag `bleed`
    1–3) and stays where they lay when they are moved;
  - blood spray for violent and road calls;
  - leaking fluids under every smoking or burning wreck;
  - a puddle under soaked patients.
  - All of it goes when the scene is cleaned up.
- **People**:
  - the 911 caller stands on the phone, waves the first medic over and says a scene line;
  - the CPR bystander does compressions on the arrest patient until a medic is within 4 m,
    then steps back and watches;
  - 0–3 onlookers keep 7–12 m away and film with their phones.
- **Trapped patients** (in the car or pinned under the load):
  - shown slumped in the seat;
  - *Cut free* (patient option, or **E** at the car, perm `extricate.perm`) is a server-timed
    `extricate.time` second job with a crowbar;
  - the door comes off, the patient is laid next to the car, and the work counts as a procedure
    for the reward.
- **Cleanup**: once the call closes (or every patient is handed over or released), the scene fades
  out `cleanupDelay` seconds later when nobody is within `playerRadius`, or after `maxCleanupWait`
  at the latest.
  - Patients taken away on a stretcher, in a vehicle or in a bed stay until the hand-over, or
    until they are left alone for `orphanTimeout`.
  - `sceneTimeout` caps a scene's life.
  - Scenes nobody responded to are removed after `noMedicTimeout` without opted-in medics.
- **Follow-up calls**: if the unit leaves for the hospital (or clears) while other patients are
  still lying there, the scene is paged again as a new call with the remaining patients and their
  worst triage.

### NPC patient behaviour (every NPC patient, from any module)
- Every networked ped with an `nza` state bag is animated by the client that owns it, from its
  state:
  - dead → body on the ground;
  - arrest → flat on the back, ready for CPR;
  - wounded and P/U → unconscious (overdose and cold variants);
  - wounded and A/V → writhing, or sitting up holding the limb (drowsy overdose, near-drowning
    and cold patients sit up once they wake);
  - alive → sitting (fractures, drowsy), standing hurt with a limp clipset, or standing;
  - trapped → slumped in the seat.
- Lying to standing goes through a get-up animation.
- It never fights other modules. The patient is left alone while:
  - carried, on a stretcher, in a bed, in a bay or on a seat (`nzaTr`);
  - attached, escorted (*Ask to walk*) or in a body bag;
  - the local medic runs a procedure on them;
  - a module calls `NZA.CallsNpc.Suspend`.
- Walking patients run from gunfire (`npc.flee`) and come back.
- GTA cannot kill them (`invincible`). A dead patient stays as a body (`keepBodies`).
- Speech: while a medic is within `speech.radius`, the server picks a line from the patient's
  real condition. The groups are trapped, overdose, breathing, cold, head, heavy bleeding, burn,
  hip (elderly), leg, arm, chest, belly, scared and pain, plus thanks and calm lines right after
  treatment. Unconscious patients only groan.
- Every player within `speech.subtitles` m sees the line in the top-centre voice card
  (`NZA.UI.Speech`) and hears GTA pain sounds or ambient speech from the ped.

### Hand-over and rewards
- A call patient placed on a hospital point whose type is in `handover.types` (default `bed`) is
  handed over. This is detected by the bus `transport:bed` / `hospital:bed`, and as a safety net
  by `patient.meta.bed` in the lifecycle.
- Pay = `rewards.base[triage at the call]` × `outcome[state at the hand-over]` × the template's
  `reward`
  - plus `perProcedure` for each treatment or procedure, up to `maxProcedureBonus`;
  - plus the `fastResponse` bonus.
- The pay is split across the crew (`split = 'share'`, with `minShare`) or paid to each of them
  (`'each'`). The crew is everyone who responded, treated or placed the patient within
  `crewTimeout`.
- The society gets `society.cut` on top, through `Bridge.Society.Add`. The account is the
  department's own society (`NZA.Hospitals.Society`), otherwise `Config.Billing.society`.
- The patient stays in the bed for `handover.despawnDelay` seconds and is then admitted
  (removed).
- **Release on scene**: walking patients with nothing open (fractures splinted, mild concussion
  only) can be released (patient option, perm `npc.release.perm`). They pay `rewards.released`,
  say thanks and walk away.

### Voices (`html/audio/calls/`)
- For each of the 11 templates, three caller lines (`<type>_c1..3.ogg`), one dispatcher line
  (`<type>_d.ogg`) and three full calls (`<type>_cN_full.ogg`). The full call is the dispatcher
  over the radio, then the caller on the phone.
- How they were made:
  - Piper TTS neural voices: 33 caller lines, each in its own voice (19 male and 14 female
    voices), spoken a little fast because the callers are panicking. The dispatcher has a calm
    voice of its own;
  - callers: a 911 phone line (300–3400 Hz band-pass, compression, soft clipping, light codec
    grit, 8 kHz line, pink line hiss, a pickup click);
  - dispatcher: a radio (420–3000 Hz, hard compression, squelch burst, roger beep and squelch
    tail);
  - loudness-normalised (−17 LUFS), then Opus 24 kbps VoIP.
- `call.voiceMode`: `'full'` (default), `'caller'` or `'dispatcher'`. Missing files are skipped,
  so the card simply has no voice.
- The text of every line is in the locale (`calls.line.*`). A translation changes the card text,
  not the recordings.

### AI medic (`Config.AIMedic`)
- `NZA.AIMedic.Request(pid)` is called by the wounded module when a player calls for help and no
  medic is on duty. A job starts on the controller client: the patient's own client, or the
  nearest player for NPC patients.
- **Response**:
  - A networked ambulance with two paramedics spawns on a road node `spawnDistance` (150–300 m)
    away.
  - It drives in with lights and siren (`TaskVehicleDriveToCoordLongrange`, `drivingStyle`,
    `speed`). There is a flashing map blip for the patient.
  - The ETA is pushed to the patient's HUD every `etaUpdate` s
    (`NZA.Wounded.Help { eta, unit, ai = true, status }`).
  - If it is stuck, it reverses and retries. After `stuckTeleport` s, or `driveTimeout` s in
    total, it fades closer.
- **On scene**:
  - The crew walks over (and is placed after `walkTimeout`).
  - The driver kneels and treats, or does CPR in arrest. The partner kneels opposite. Their lines
    show in the voice card.
  - The treatment is server-timed (`treatTime`): bleeding is controlled (bandaged / packed),
    ROSC in arrest, naloxone for an overdose, oxygen for hypoxia or airway problems.
- **Transport** (`transport = 'drive'`):
  - fade, then the patient goes in the back and the exit key is locked;
  - the unit drives to the hospital (`transportTimeout`, then a fade);
  - at the hospital: fade, then the patient goes into a free bed (`NZA.Hospitals.FreeBed`,
    placed like the transport module does) or to the nearest fallback `hospitals` spot.
- `transport = 'teleport'` skips the drive.
- **After the care**:
  - `revive = 'full'` heals the patient. `'stabilize'` stops the bleeding and lets them stand,
    but the injuries stay.
  - The patient is billed `price` through `NZA.Billing.Charge` (insurance applies; falls back
    to `Bridge.RemoveMoney` and the society).
  - The patient's call is closed (`closeCall`).
  - The unit drives off and is deleted.
- **Cancelled** when:
  - a real medic responds to the call while the unit is still driving (`cancelOnMedic`);
  - the patient recovers, dies or leaves;
  - the controller leaves (the job finishes without the vehicle).
- `maxTime` guarantees the job ends. A client that fails to spawn the unit gets a virtual unit
  that still treats and transports.
- NPC patients get the same response and are admitted when they reach the hospital.

## Controls

| Where | Key | Action |
|---|---|---|
| at a smoking wreck (not burning) | hold **E** | Cut the engine |
| at ground smoke / a fire (no extinguisher needed) | hold **E** | Smother the fire |
| fire extinguisher in hand | **LMB** at the fire | spray it out (progress tag beside the crosshair) |
| trapped patient | **E** or the patient option *Cut free* | cut the patient free (crowbar) |
| walking patient | patient option *Release on scene* | release, no transport |

The *NPC calls* switch lives in the dispatch module (radial, pager menu, board).

## Config (`Config.Calls`)

| Section | Keys |
|---|---|
| root | `enabled` |
| `generation` | `enabled minMedics optInDefault tick firstDelay interval perMedicSpeedup maxActive maxPerMedic minDistance maxDistance sceneSpacing locationCooldown repeatType` |
| `scene` | `spawnRadius buildTimeout maxBuildAttempts buildRadius modelTimeout sceneTimeout cleanupDelay playerRadius maxCleanupWait orphanTimeout noMedicTimeout bystanders hazardLights crashLights maxProps onlookers{ enabled count max distance scenarios }` |
| `decals` | `enabled radius lifetime blood{ type size[3] tint opacity max } splatter{ type size tint opacity types } oil{…} water{…}` |
| `call` | `voice voiceMode voiceFolder phonePrefix showCaller` |
| `npc` | `enabled radius tick invincible keepBodies speech{ enabled medicOnly radius subtitles interval sounds ms sounds_map } flee{ enabled radius time } release{ enabled perm walkTime } poses{…} getUp limpClipset` |
| `fx` | `radius duration smoke fire groundFire groundSmoke engineSmoke cutEngine spray fireNeedsExtinguisher smother` |
| `extricate` | `enabled perm time distance anim prop breakDoor` |
| `handover` | `types despawnDelay notify` |
| `rewards` | `enabled account base[1..3] outcome released perProcedure maxProcedureBonus fastResponse split minShare crewTimeout society{ enabled cut name }` |
| `admin` | `command clearCommand listCommand` |
| `pools` / `vehiclePools` | ped and vehicle model pools used by the templates |
| `templates.<key>` | `enabled weight priority code type title snap roadside reward onlookers wet maxVictims locations victims vehicles props fx callers dispatcher bystander` |

`Config.AIMedic`: `enabled onlyNoMedics maxActive cooldown states vehicle livery crew plate
spawnDistance speed drivingStyle stopRange siren etaUpdate stuckTime stuckTeleport driveTimeout
walkTimeout treatTime cprAnim treatAnim kneelAnim transport transportTimeout hospitalRadius revive
price billReason closeCall cancelOnMedic maxTime hospitals`.

## Server API

```lua
NZA.Calls.Create(key?, { coords = vector4?, force = bool, buildBy = src? }) → sceneId, callId | nil, err
NZA.Calls.Get(sceneId)  NZA.Calls.All()  NZA.Calls.Remove(sceneId, reason) → bool
NZA.Calls.SceneOf(pid) → scene, victim | nil     NZA.Calls.OptedMedics() → { { src, coords } }
NZA.Calls.Templates() → { key, … }

NZA.AIMedic.Request(pidOrSrc, { callId?, force?, source? }) → jobId | false, err
        -- err: disabled no_patient state cooldown medics busy no_client
NZA.AIMedic.Cancel(pidOrJobId, reason?) → bool   NZA.AIMedic.Active(pid) → job | nil   NZA.AIMedic.Jobs()
```
Exports: `RequestAIMedic(pidOrSrc, opts)`, `CancelAIMedic(pidOrSrc)`.

Bus emitted: `calls:created (scene)`, `calls:built (scene)`, `calls:removed (scene, reason)`,
`calls:handover (scene, p, state, amount)`, `calls:released (scene, p)`.
Bus listened: `dispatch:closed dispatch:respond dispatch:status patient:removed player:unloaded
transport:bed hospital:bed treat:done proc:done state:changed`.

## Client API

```lua
NZA.Calls.Scenes() → { [id] = public scene }   NZA.Calls.SceneOfEntity(ped) → scene, victim
NZA.Calls.Extricate(ped, target?)               NZA.Calls.EntOf(net) → entity | 0
NZA.CallsNpc.ApplyPose(ped, pose) → bool        NZA.CallsNpc.Pose(ped) → pose | nil
NZA.CallsNpc.Suspend(ped, name, on)             -- another module animates this NPC patient
NZA.AIMedic.Runs()
```
Patient options (`NZA.Interact`):
- `nza_calls_extricate` *Cut free*: order 11, trapped NPCs only;
- `nza_calls_release` *Release on scene*: order 92.

## Network

| Name | Kind | Payload |
|---|---|---|
| `nza:calls:build` | S→C | plan `{ id, key, token, loc, snap, roadside, hazard, crashLights, modelTimeout, engineSmoke, vehicles[], victims[], props[], bystanders[] }` (no medical data) |
| `nza:calls:built` / `buildFailed` | C→S | `sceneId, token, { origin, vehicles = {{ i, n }}, victims, props, bystanders }` / `sceneId, token, reason` |
| `nza:calls:scenes` / `scene` / `sceneRemove` | S→C | public scene list / one scene `{ id, key, type, state, callId, c, vehicles, props, bystanders, victims{ n, tr, veh, seat }, fx{ id, kind, net, at, on } }` / id |
| `nza:calls:fade` | S→C | `nets[]` (fade before delete) |
| `nza:calls:fxOut` | C→S | `sceneId, fxId, 'cut' \| 'spray' \| 'smother'` (distance, weapon and burning checks) |
| `nza:calls:say` | S→C | `{ net, name, text, ms, sound, by }` |
| `nza:calls:released` | S→C | `net` |
| `nza:calls:fallback` | S→C | page without the dispatch module |
| `nza:calls:sync` | callback | `() → public scene list` |
| `nza:calls:extricate` | callback | `(target, 'start' \| 'finish' \| 'cancel', token)` |
| `nza:calls:release` | callback | `(target) → { ok, msg }` |
| `nza:aimedic:run / treated / handover / done / cancel` | S→C | job / `id, data` |
| `nza:aimedic:spawned / eta / arrived / treating / loaded / atHospital / ready / failed` | C→S | `id, token, …` (token, rate, entity model and distance checked) |

State bags (server-written): ped `nzaNpc = { s, c, tr, pose, dp, wet, esc, rel, ho, veh, seat, sex }`,
bystander `nzaBy = { role = 'caller' | 'cpr' | 'watch' | 'onlooker', v, scenario, wave }`.

## Commands (admins, ace `nza.admin`)
- `/nzacall [type] [here]`: create a call. `here` builds it 12 m in front of you, right away.
- `/nzacallclear`: remove every scene.
- `/nzacalls`: list the open scenes.

## Security
- Clients never send medical data. Plans hold no injuries.
- Built entities are checked by model, distance and existence before they become patients.
  Stale or foreign builds are deleted.
- Extrication is server-timed (token plus `time`), with permission and distance checks.
- Effects: the server checks the distance to the fire or engine, the extinguisher actually in
  hand, and that the engine is no longer burning before it can be cut.
- Release needs permission, distance and the patient's real state (no open wounds). Rewards and
  society money are computed only on the server.
- AI medic reports carry a job token, are rate-limited, and are checked against server positions
  (arrival ≤ 90 m, hospital radius) and server timers (treatment time, transport timeout).
- Every handler has a rate limit (`NZA.Core.Rate`).

## Testing
- `luac5.4 -p` passes on all 9 Lua files.
- A mock FiveM runtime ran the real server and client files:
  - every template plans (victims, injuries, vehicles, props, effects, caller and onlookers),
    and every voice file exists;
  - generator → dispatch → build → register → patients, the effects lifecycle, put-out checks
    (distance, weapon, burning engine), extrication tokens and timing, release, hand-over pay and
    split, the society cut, follow-up calls and cleanup;
  - AI medic: the full drive / treat / load / hospital / bed / bill flow, the virtual unit when
    the client fails, and refusal while medics are on duty;
  - client: building, particle start and stop, decals (pool, spray, leak, growth, no duplicates,
    removed with the scene), extrication, NPC poses (wounded, arrest, alive, held), subtitles, the
    AI drive loop with the stuck → teleport fallback, the fallback page.
- The voice was checked in the call card preview: `audio/calls/mva_c1_full.ogg` plays with the
  animated waveform.

## Known limits
- Decal ids, particle names, anims and damage packs are GTA natives. They are all in the config so
  they can be swapped, and a missing model or dictionary is skipped instead of failing the scene.
- Locations are believable public spots, not hand-checked in every interior. `snap` pulls the
  scene to the nearest road or walkable ground, so a slightly off coordinate still works.
- Onlookers and bystanders are networked peds (≤ 4 per scene). Lower `scene.onlookers.count` on
  busy servers.
- The AI unit uses the native `ambulance` and `s_m_m_paramedic_01` by default. Its driving is GTA
  AI with the stuck and timeout fallbacks above.
- The recordings are English. Translations change the subtitles and the card, not the audio.
