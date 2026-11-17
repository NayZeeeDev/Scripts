# nayzeee-multicharacter v2 — build contract

Single source of truth for the client Lua, server Lua and the React NUI. Every name below is
exact: keep function names, callback names, message actions and field names identical.

---------------------------------------------------------------------------------------------
## 0. Hard rules

* Every Lua file starts with `if not NAYZEEE_LOCK_OK then return end` (see `lock.lua`).
* Lua 5.4 (`lua54 'yes'`), ox_lib (`lib.callback`, `lib.requestModel`, ...), oxmysql (`MySQL.*.await`).
* **0.00 resmon while playing.** Every loop/thread must end when the lobby closes. No
  `lib.points` `nearby`, no per-frame threads outside the lobby/cutscene. Use `Wait(0)` loops
  only while `Main.open` (lobby) or a cutscene runs.
* All lobby entities are **local** (`CreatePed/CreateObject/CreateVehicle` with network = false)
  and tracked so `Scene.Teardown()` deletes every one of them. Player sits in a private routing
  bucket while in the lobby (server).
* Peds are placed with ground snapping (see §6.3) – never trust a config z blindly.
* Anim dicts stay loaded while the lobby is open (`U.Anim` keeps a refcount set and
  `U.ReleaseAnims()` unloads them on teardown). Never `RemoveAnimDict` right after `TaskPlayAnim`.
* NUI: **never use `backdrop-filter`** (renders as black boxes in FiveM CEF). Glass is faked with
  gradients, 1px inner highlights and a noise layer.
* Server never trusts the client: ownership of every charid is checked against the session.

---------------------------------------------------------------------------------------------
## 1. Folder layout & load order (fxmanifest)

```
shared:  lock.lua, @ox_lib/init.lua, config/config.lua, config/themes.lua, config/moods.lua,
         config/poses.lua, config/weapons.lua, config/pets.lua, config/spawns.lua,
         config/nationalities.lua, locales/*.lua, shared/utils.lua, shared/framework.lua,
         shared/math.lua
server:  @oxmysql/lib/MySQL.lua, config/server.lua,
         bridge/server/common.lua, bridge/server/esx.lua, bridge/server/qb.lua,
         bridge/server/housing.lua, bridge/server/inventory.lua, bridge/server/pets.lua,
         server/db.lua, server/logs.lua, server/slots.lua, server/validate.lua,
         server/buckets.lua, server/characters.lua, server/weapons.lua, server/squads.lua,
         server/main.lua, server/commands.lua, server/exports.lua
client:  bridge/client/framework.lua, bridge/client/appearance.lua, bridge/client/world.lua,
         bridge/client/pets.lua,
         client/utils.lua, client/settings.lua, client/audio.lua, client/camera.lua,
         client/lights.lua, client/scene.lua, client/actors.lua, client/couple.lua,
         client/plates.lua, client/cutscene.lua, client/spawn.lua, client/create.lua,
         client/start.lua, client/main.lua, client/nui.lua, client/relog.lua, client/editor.lua
ui_page: web/dist/index.html   (Vite build output, committed)
files:   web/dist/index.html, web/dist/assets/*.*, web/dist/sounds/*.*
```

Client module tables (globals): `U, Settings, Audio, Cam, Lights, Scene, Actors, Couple,
Plates, Cutscene, Spawn, Create, Start, Main, Editor, ClientBridge, Appearance, World, PetBridge`.
Server: `Bridge, DB, Logs, Slots, Validate, Buckets, Characters, Weapons, Squads, Sessions`.
Shared: `NZ` (utils), `NZ.Rel(base, offset)` math helpers in shared/math.lua.

---------------------------------------------------------------------------------------------
## 2. Shared math — "rel space" (shared/math.lua)

Theme layouts are authored relative to the **main slot** `vec4` (x, y, z, heading).
`offset = vec3(right, forward, up)` where *forward* is the direction the main ped faces.

```lua
NZ.Fwd(h)            -> vec3 forward unit vector for heading h  ( -sin(h), cos(h), 0 )
NZ.Right(h)          -> vec3 right unit vector                  (  cos(h), sin(h), 0 )
NZ.Rel(base, off)    -> vec3 world position of rel offset `off` from vec4 `base`
NZ.RelH(base, off, dh) -> vec4 (world pos, base.w + (dh or 0))   -- for peds/props/vehicles
NZ.HeadingTo(from, to) -> heading (deg) looking from vec3 `from` to vec3 `to`
```
Config values that may be either absolute or relative use this convention:
`{ coords = vec3/vec4 }` = absolute world, `{ offset = vec3, heading = dh }` = relative.

---------------------------------------------------------------------------------------------
## 3. Database (server/db.lua auto-creates; sql/install.sql mirrors it)

```sql
CREATE TABLE IF NOT EXISTS `multichar_characters` (
  `charid`      VARCHAR(64)  NOT NULL,
  `owner`       VARCHAR(64)  NOT NULL,
  `theme`       VARCHAR(32)  NULL,
  `mood`        VARCHAR(32)  NULL,
  `pose`        VARCHAR(32)  NULL,
  `couple_pose` VARCHAR(32)  NULL,
  `weapon`      VARCHAR(64)  NULL,      -- 'auto' | 'none' | 'WEAPON_X'
  `pet`         VARCHAR(32)  NULL,      -- Config.Pets.list id or NULL
  `pet_name`    VARCHAR(24)  NULL,
  `nationality` VARCHAR(48)  NULL,
  `backstory`   VARCHAR(600) NULL,
  `favorite`    TINYINT(1)   NOT NULL DEFAULT 0,
  `disabled`    TINYINT(1)   NOT NULL DEFAULT 0,
  `created_at`  INT UNSIGNED NULL,
  `last_played` INT UNSIGNED NULL,
  `playtime`    INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`charid`), KEY `owner` (`owner`)
);
CREATE TABLE IF NOT EXISTS `multichar_slots` (
  `owner` VARCHAR(64) NOT NULL, `extra` INT NOT NULL DEFAULT 0, PRIMARY KEY (`owner`)
);
CREATE TABLE IF NOT EXISTS `multichar_squads` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sender`         VARCHAR(64) NOT NULL,             -- charid
  `target`         VARCHAR(64) NOT NULL,             -- charid
  `type`           ENUM('squad','couple') NOT NULL DEFAULT 'squad',
  `status`         ENUM('pending','accepted') NOT NULL DEFAULT 'pending',
  `pending_type`   ENUM('squad','couple') NULL,     -- requested switch, waiting on the other side
  `pending_by`     VARCHAR(64) NULL,                 -- charid that asked for the switch
  `sender_slot`    TINYINT UNSIGNED NULL,            -- where TARGET stands in SENDER's lobby (2..4)
  `target_slot`    TINYINT UNSIGNED NULL,            -- where SENDER stands in TARGET's lobby (2..4)
  `sender_visible` TINYINT(1) NOT NULL DEFAULT 1,
  `target_visible` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at`     INT UNSIGNED NOT NULL,
  `updated_at`     INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`), UNIQUE KEY `pair` (`sender`,`target`), KEY `target` (`target`)
);
CREATE TABLE IF NOT EXISTS `multichar_codes` (       -- redeem codes / tebex (kept from v1)
  `code` VARCHAR(64) NOT NULL, `slots` INT NOT NULL DEFAULT 1, `uses` INT NOT NULL DEFAULT 1,
  `used` INT NOT NULL DEFAULT 0, `created_at` INT UNSIGNED NULL, PRIMARY KEY (`code`)
);
```
Rules: a character has at most **one accepted couple** link; at most `Config.Squad.maxLinks`
(default 3) accepted links total (couple included). Couple partner always stands in slot 2.

---------------------------------------------------------------------------------------------
## 4. Data shapes

### 4.1 Character (server → client, `nzm:boot` / `nzm:refresh`)
```lua
{
  id, slot, firstname, lastname, name, dob ('YYYY-MM-DD'), age, gender ('m'|'f'),
  nationality, height, backstory, phone,
  job = { name, label, grade, gradeLabel }, cash, bank,
  lastPlayed, playtime, createdAt, favorite, disabled, locked,
  model, skin,                                     -- client only, stripped before NUI
  prefs  = { theme, mood, pose, couplePose, weapon, pet, petName },   -- raw saved values (may be nil)
  weapon = { name, label, class, components = { hash... }, tint } | nil,  -- RESOLVED showcase weapon
  weapons = { { name, label, class } ... },        -- what this char may pick (per WeaponShowcase.mode)
  pet    = { id, model, name } | nil,              -- RESOLVED pet
  pets   = { 'pug', 'husky' ... },                 -- pet ids this char may pick
}
```
### 4.2 Squad (server → client, `nzm:squad:get`)
```lua
{
  links = { {
    id, type = 'squad'|'couple', slot = 2..4, visible = bool,       -- my side of the link
    pendingType = nil|'squad'|'couple', pendingByMe = bool,
    other = { id, name, job = { label }, online = bool,
              model, skin, gender,                                  -- client only
              prefs = { pose, couplePose, weapon }, weapon = <resolved weapon|nil> },
  } ... },
  incoming = { { id, type, from = { id, name }, at } ... },          -- pending, I am target
  outgoing = { { id, type, to   = { id, name }, at } ... },          -- pending, I am sender
}
```
### 4.3 Boot data (`nzm:boot`)
```lua
{ loaded = bool, error = string|nil,
  characters = { Character... },
  slots = { total, used, max, base, extra },
  canDelete = bool, online = n, maxPlayers = n,
  selected = charid|nil,              -- last played
  relog = bool }
```

---------------------------------------------------------------------------------------------
## 5. Server API

### 5.1 lib.callback (client → server)
| name | args | returns |
|---|---|---|
| `nzm:boot` | – | BootData (puts player in lobby bucket) |
| `nzm:refresh` | – | BootData (no bucket change) |
| `nzm:squad:get` | charId | Squad |
| `nzm:squad:search` | charId, query | `{ { id, name, online } ... }` (max 10; excludes own chars & linked) |
| `nzm:squad:request` | charId, targetId, type | `{ ok, msg }` |
| `nzm:squad:respond` | charId, linkId, accept(bool) | `{ ok, msg }` (handles new requests AND type switches) |
| `nzm:squad:remove` | charId, linkId | `{ ok }` (cancel outgoing / remove accepted / decline) |
| `nzm:squad:switch` | charId, linkId, type | `{ ok, msg }` (asks the other side) |
| `nzm:squad:slot` | charId, linkId, slot(2..4) | `{ ok }` (swaps with whoever held that slot) |
| `nzm:squad:visible` | charId, linkId, bool | `{ ok }` |
| `nzm:pref` | charId, key, value | `{ ok, msg, character = Character }` key ∈ theme, mood, pose, couplePose, weapon, pet, petName, favorite, backstory |
| `nzm:play` | charId | `{ ok, msg, skin, model, gender, spawn = SpawnOption[]|nil, mode = 'selector'|'last'|'first'|'custom' }` |
| `nzm:spawn` | optionId or 'first'/'last' | `{ coords = vec4 }` or nil |
| `nzm:create` | slot, form | `{ ok, errors = { field = msg }, msg, charId, gender }` |
| `nzm:delete` | charId, typedName | `{ ok, msg }` |
| `nzm:redeem` | code | `{ ok, msg }` |
| `nzm:handoff` | – | true (custom spawn resource) |

SpawnOption: `{ id, kind = 'last'|'house'|'city'|'first', label, desc, icon, coords = vec4 }`
(coords stays client-side; NUI gets id/kind/label/desc/icon only).

### 5.2 Server events (net)
* `nzm:server:spawned` (client → server) — player is in the world: bucket 0, stage 'playing'.
* `nzm:server:relog` / `nzm:server:quit` (kept from v1).
* `nzm:client:open` (server → client) relog into the lobby.
* `nzm:client:squadInvite` (server → client) `(fromName, type, linkId)` while the target is
  PLAYING: client shows `lib.alertDialog`, answers with `nzm:server:squadAnswer (linkId, accept)`.
* `nzm:client:squadChanged` (server → client) `(charId)` — any link of a char this player owns
  changed; if that char is selected in the lobby, client refetches `nzm:squad:get`.
* `nzm:client:notify` `(msg, type)`.

---------------------------------------------------------------------------------------------
## 6. Client behaviour

### 6.1 Flow
1. `Main.Boot(relog)`: fade out, HUD off, `nzm:boot`, choose initial character
   (`selected` → favorite → first), `Scene.Load(themeFor(char))`, `Actors.Show(char, squad)`.
2. If `Config.StartScreen.enabled and not relog`: `Start.Show()` — camera `theme.cameras.start`
   (slow orbit), NUI `start`. NUI posts `startContinue` → `Start.Continue()`.
3. `Main.OpenLobby()`: NUI `lobby` payload, NUI focus, camera → `Config.Camera.defaultMode`.
4. Selecting another character (`select`): theme differs → fade + `Scene.Load` (rebuild),
   else `Actors.SwapMain(char)` with the walk-in entrance. Squad refetched for that char.
   Empty unlocked slot → creation silhouette (`Create.Start`).
5. Prefs: `previewPref` (live, not saved) / `setPref` (saved; server returns updated Character).
   theme → rebuild scene; mood → `Lights.SetMood`; pose/couplePose/weapon/pet → re-render actors.
6. `play` → `nzm:play` → `Appearance.ApplyPlayer` (player ped still hidden) →
   spawn selector (NUI `spawn`, aerial preview camera `Cam.Aerial`) or direct.
7. `spawnConfirm` → `nzm:spawn` → NUI `cutscene {on=true}` → camera back to lobby (refocus +
   stream) → `Cutscene.Run(theme)` → at `fadeAt` fade to black → `Spawn.Enter(coords)`.
8. `Spawn.Enter`: teardown everything (entities, pets, weapons, props, cams, lights, timecycle,
   audio), `TriggerServerEvent('nzm:server:spawned')`, teleport (ground-safe), visible, unfreeze,
   HUD on, framework spawned events, fade in. NUI `close`.
9. New character: `createSubmit` → `nzm:create` → appearance editor in the world
   (`Config.Creation.coords`) → spawn (selector or first spawn), **no departure cutscene**.

### 6.2 Actors (client/actors.lua)
Slot 1 = selected character. Slots 2..4 = accepted, visible squad links (couple in slot 2).
`pet` slot = character's pet. Each actor: `{ ped, slot, kind = 'self'|'couple'|'squad'|'ghost',
char|other, prop = {entity...}, weapon = name|nil }`.
Pose resolution per actor: couple pose active (slot 1 + slot 2 couple) → `Couple.Play` (both
unarmed, props cleared) → weapon set → weapon class hold anim → pose (with props) → theme
slot default pose.

### 6.3 Ground snapping (U.Ground)
Shape-test down from z+1.2 then z+4.0 (flags 1|16, ignore player), fallback
`GetGroundZFor_3dCoord`; root = floor + `Config.Scene.footHeight` (1.0). Interiors are pinned
(`PinInteriorInMemory` + `IsInteriorReady`) and collision requested before placing.

### 6.4 Camera modes
`squad` (whole lobby), `duo` (slot 1 + 2 when couple pose), `body` (full-body outfit of
selected actor), `face` (upper body). Theme may override any mode with
`cameras[mode] = { offset, lookAt, fov }` (rel space). Idle: subtle sway (`ShakeCam`
'HAND_SHAKE') + slow dolly drift between two close points. DoF on body/face/duo.

---------------------------------------------------------------------------------------------
## 7. NUI protocol

### 7.1 Lua → NUI: `SendNUIMessage({ action = <name>, data = <table> })`
| action | data |
|---|---|
| `start` | `{ serverName, playerName, logo, prompt, socials = { {icon, label} } }` show start screen |
| `lobby` | LobbyPayload — show lobby |
| `data` | LobbyPayload — refresh without changing view |
| `select` | `{ slot }` |
| `squad` | SquadNui (Squad without skins; `other.prefs` dropped) |
| `plates` | `{ items = { { key, x, y, visible, name, sub, badge = 'self'|'partner'|'squad'|'pet', online = true|false|nil } } }` x/y are 0..1 screen |
| `camera` | `{ mode }` |
| `busy` | `{ on, text }` |
| `toast` | `{ type = 'success'|'error'|'info'|'warning', text }` |
| `create` | `{ slot }` creation panel open (camera already moved) |
| `spawn` | `{ options = { {id, kind, label, desc, icon} }, selected }` |
| `cutscene` | `{ on }` — hide everything (letterbox bars allowed) |
| `hide` | `{}` hide all UI (appearance editor etc.) |
| `close` | `{}` lobby finished |
| `audio` | `{ ambience = themeId|nil, muted }` start/stop procedural ambience |
| `settings` | Settings table |

LobbyPayload:
```ts
{ characters: CharacterNui[], slots: { total, used, max, shown }, selected: number,
  canDelete: boolean, theme: string, mood: string, camera: string,
  squad: SquadNui, online: number, maxPlayers: number }
```
CharacterNui = Character without `skin`, `model`, `weapon.components`.
`slots.shown` = how many slot rows the UI lists (used + 1 free + locked teaser, ≤ max).

### 7.2 NUI → Lua: `fetch('https://<resource>/<name>', POST json)` → JSON reply
| name | body | reply |
|---|---|---|
| `ready` | – | UiConfig |
| `startContinue` | – | true |
| `select` | `{ slot }` | true |
| `camera` | `{ mode }` | true |
| `previewPref` | `{ slot, key, value }` | true |
| `setPref` | `{ slot, key, value }` | `{ ok, msg }` |
| `play` | `{ slot }` | true (async; Lua sends `spawn` / toast) |
| `spawnHover` | `{ id }` | true |
| `spawnConfirm` | `{ id }` | `{ ok }` |
| `createStart` | `{ slot }` | `{ ok }` |
| `createGender` | `{ gender }` | true |
| `createCancel` | – | true |
| `createSubmit` | `{ form }` | `{ ok, errors, msg }` |
| `delete` | `{ slot, confirm }` | `{ ok, msg }` |
| `squadSearch` | `{ query }` | `{ results }` |
| `squadRequest` | `{ target, type }` | `{ ok, msg }` |
| `squadRespond` | `{ id, accept }` | `{ ok, msg }` |
| `squadRemove` | `{ id }` | `{ ok }` |
| `squadSwitch` | `{ id, type }` | `{ ok, msg }` |
| `squadSlot` | `{ id, slot }` | `{ ok }` |
| `squadVisible` | `{ id, visible }` | `{ ok }` |
| `settings` | `{ settings }` | Settings |
| `sound` | `{ name }` | true (Lua plays a frontend sound if `Config.Audio.frontend`) |
| `redeem` | `{ code }` | `{ ok, msg }` |
| `quit` | – | true |

UiConfig (reply of `ready`):
```ts
{ version, locale: Record<string,string>, ui: Config.UI subset (serverName, logo, accent,
  accents, socials, keys), start: Config.StartScreen,
  themes: { id, label, description, icon, category, palette: [string,string,string] }[],
  moods: { id, label, icon, swatch }[],
  poses: { id, label, icon, category, prop: boolean }[],
  couplePoses: { id, label, icon }[],
  pets: { id, label, icon, kind }[],
  weapon: { mode, allowNone, allowAuto },
  registration: { nameMin, nameMax, minAge, maxAge, height, nationality, backstory, genders },
  nationalities: string[], cameraModes: string[],
  squad: { enabled, maxLinks, searchMin, couples },
  audio: { ambience, uiSounds }, settings: Settings }
```
Settings (client KVP, `client/settings.lua`):
`{ scale = 1.0, muted = false, uiVolume = 0.6, ambientVolume = 0.35, sway = true, dof = true,
   plates = true, perf = false, bars = true }`

---------------------------------------------------------------------------------------------
## 8. Departure timeline (Config.LobbyThemes[id].departure)

```lua
departure = {
  duration = 9000,     -- hard cap (ms) – runner forces the fade at this point
  fadeAt   = 7600,     -- ms when DoScreenFadeOut starts
  fadeTime = 900,
  camera = {           -- multi-point track, rel space of the main slot; time = interp ms from previous point
    { offset = vec3(...), lookAt = vec3(...), fov = 40.0, time = 0 },
    { offset = vec3(...), lookAt = vec3(...), fov = 34.0, time = 2600, follow = 'vehicle1'|'main'|nil },
  },
  steps = {            -- fired at `at` ms (sorted); unknown `do` = ignored with a debug print
    { at = 0,    ['do'] = 'goodbye' },                    -- couple/squad partners wave, couple pose released
    { at = 0,    ['do'] = 'holster' },                    -- clear weapon + handheld props on main
    { at = 300,  ['do'] = 'enterVehicle', vehicle = 1, seat = -1, speed = 1.2 },
    { at = 300,  ['do'] = 'petEnter',     vehicle = 1, seat = 0 },
    { at = 3600, ['do'] = 'lights',       vehicle = 1 },
    { at = 3800, ['do'] = 'engine',       vehicle = 1 },
    { at = 4400, ['do'] = 'drive',        vehicle = 1, to = vec3(0.0, 40.0, 0.0), speed = 9.0 },
    { at = 0,    ['do'] = 'rotors',       vehicle = 1 },
    { at = 4000, ['do'] = 'fly',          vehicle = 1, to = vec3(0.0, 60.0, 35.0), speed = 12.0 },
    { at = 4000, ['do'] = 'taxi',         vehicle = 1, to = vec3(0.0, 120.0, 0.0), speed = 14.0 },
    { at = 0,    ['do'] = 'walkTo',       to = vec3(...), speed = 1.0 },
    { at = 0,    ['do'] = 'anim',         target = 'main', pose = 'phone', time = 2000 },   -- a Config.Poses id (props included) or dict/clip/flag; time = ms then cleared
    { at = 0,    ['do'] = 'petFollow' },                    -- pet unfreezes and follows the main ped (TaskFollowToOffsetOfEntity)
    { at = 0,    ['do'] = 'ptfx',         asset = 'core', name = 'ent_dst_dust', offset = vec3(...), scale = 1.5, entity = 'vehicle1' },
    { at = 0,    ['do'] = 'sound',        name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    { at = 0,    ['do'] = 'doors',        vehicle = 1, open = { 0 } },
  },
}
```
Vehicles may define `crew = { { model = 's_m_m_pilot_02', seat = -1 }, ... }` — spawned at build,
`SetPedStayInVehicleWhenJacked`, invisible to nameplates; the crew drives/flies for `drive`/`fly`/`taxi`
when the main character is not in the driver seat. `enterVehicle` passes the exact seat and sets
`SetPedConfigFlag(ped, 184, true)` so no auto-shuffle to the driver seat.

Step targets: `target = 'main'|'partner'|'pet'` (default main). `vehicle = n` = n-th entry of the theme's
`vehicles`. `to`/`offset` are rel space of the main slot. `entity = 'vehicle1'|'main'` attaches ptfx.
Camera point `follow = 'vehicle1'|'main'`: after reaching that point the camera keeps pointing at the
entity (PointCamAtEntity) until the fade.

---------------------------------------------------------------------------------------------
## 9. Theme data (config/themes.lua) — what the client reads
`Config.LobbyThemes[id] = { order, label, description, icon, category, palette, main (vec4), interior,
weather, hour, minute, mood, moods, timecycle, slots = { [2..4] = placement }, pet = placement,
poses = { [slot] = poseId }, props = { { model, offset, heading, collision } }, vehicles = { { model,
offset, heading, color = {p,s}, livery, extras, mods, lights, doorsOpen, crew = { { model, seat } } } },
lights = { tint, scale, rig, extra }, cameras = { start|squad|duo|body|face = { offset, lookAt, fov } },
ambience = { preset, url }, departure = §8 }` — placement = `{ offset, heading }` or `{ coords }`,
resolve with `NZ.Place(main, placement)`.
Other config: `Config.Moods` (array), `Config.Poses` (array), `Config.CoupleAnimations` (array),
`Config.GoodbyeAnim`, `Config.WeaponShowcase`, `Config.Pets`, `Config.Camera`, `Config.Lighting`,
`Config.Audio`, `Config.Squad`, `Config.Spawn`, `Config.StartScreen`, `Config.Scene`, `Config.UI`.
Shared helpers in shared/utils.lua: `NZ.T, NZ.Decode, NZ.Truthy, NZ.Vec, NZ.Copy, NZ.Trim,
NZ.Capitalize, NZ.Theme, NZ.MoodById, NZ.PoseById, NZ.CoupleById, NZ.PetById, NZ.ThemeIds,
NZ.WeaponClass`; shared/math.lua: `NZ.Fwd, NZ.Right, NZ.Rel, NZ.RelH, NZ.Place, NZ.HeadingTo, NZ.Lerp`.
