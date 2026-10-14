# Module: splint — field splinting, crutches, wheelchair

Files

| File | What |
|---|---|
| `config/modules/splint.lua` | `Config.Splint` (Splint, Props, Effects, Crutches, Wheelchair, Interact, Radial, Billing) |
| `locales/en/splint.lua` | every `splint.*` string (Lua + NUI) |
| `server/modules/splint.lua` | procedure `splint`, treatments `splint_remove` / `crutches_give`, crutches state, healed-splint removal |
| `server/modules/splint_chair.lua` | wheelchair objects (server-created, networked), sit / push / fold / seat patients, cleanup |
| `client/modules/splint.lua` | procedure runner (camera, anchors, NUI), patient options, exam route, radial, worn splint props, splinted-leg walk, patient pose |
| `client/modules/splint_crutch.lua` | crutch walk, crutch props on every player, keybind / command, "Give crutches" |
| `client/modules/splint_chair.lua` | unfold, sit + drive (W A S D), push, fold, seat / help out patients, chair target options |
| `html/apps/splint/app.js` · `app.css` | NUI app `splint`: the minigame (3D splint over the game) and the mobility card |

## 1. Splinting (NZA.Proc `splint`)

Who / what: permission `Config.Splint.Splint.perm` (`splint`), one `Config.Items.splint` (taken on finish),
patient `alive` or `wounded`, a limb fracture (`Config.Splint.Splint.regions`) without splint or cast.
Open fractures can be required to be covered first (`requireDressedOpen`, skipped in easy mode).
Easy mode (per department / `Config.EasyMode.default`): core progress bar for `easyTime` s, no room or
supply requirement beyond the splint item.

Camera: straight down over the broken segment (`NZA.Cam.TopDown`, heading turned so the limb runs
up the screen, height so the segment fills `camera.fill` of the screen); a side camera
(`NZA.Cam.Close`) when the limb is upright. A standing player patient is asked to sit on the ground
(`patientPose`, server event `nza:splint:pose`).

The splint is a real-time 3D model (three.js) drawn over the game with the game camera's lens
(`camera.fov`), at true scale (`device.width/depth/wall`, metres) between the joint anchors, so it
keeps its place and perspective while you turn / zoom the view. Where it passes under the limb the
limb shows through (it lies in the channel). Device faces / props carry generic labels only
(`Contour leg splint · CS-76`, `Contour arm splint · CS-40`).

Steps (all keys in `Config.Splint.Splint.keys`, KeyboardEvent codes):

| Step | What you do | Controls |
|---|---|---|
| 1 Lay the splint | Drag the splint under the limb until both ends reach past the joint above and below (diamond targets on the joints turn teal "Seated", mm-off readout in the chips, fit dial). It sets after `lockHold` s steady (or Space). | Drag · Q / E turn · arrows nudge · Shift fine · X start over · Space set · right-drag rotate view · wheel zoom |
| 2 Pad & shape | **2 Padding**: click the bony points (knee/ankle, elbow/wrist …) — foam pads appear between limb and wall. **3 Shape**: press & hold each point until the walls close on the limb; release inside the band (`shapeZone`) — over-squeezing leaves a pressure point. Shaping next to an unpadded bony point is refused. | Click / hold · 2 / 3 switch tool · Shift gentle |
| 3 Strap & check | **4 Straps**: click a strap → it flips over the limb; click (or Space) when the tension needle is in the band (`strapZone`); above `strapTight` = too tight. **5 Distal check**: click the toes / fingers → circulation (live pleth trace + capillary refill ring), movement and feeling (patient answers when responsive). A tight strap cuts the pulse off → click it to loosen, cinch again, re-check. | Click · Space cinch · 5 check |

Readouts: left column dial (fit → contact / pressure → tension / straps) + instrument list; top-left
fracture card (bone illustration with the break and displacement angle, pulse below, pain, device);
top-right distal-check card; top-right splint record after the finish (grade ring, alignment /
shaping / straps bars, pressure points, time).

Score (client, clamped by the server): `0.4 × alignment + 0.3 × shaping + 0.3 × straps`.
Result payload: `{ score, align, mould, straps, cms, checks, pressure, padded, tight, loose, resets, time }`.

Outcome (server `onFinish`): `devices.splints[region] = 'leg' | 'arm'`, `treat.splinted = true`,
`quality.splinted = score`, extra pain relief (`painRelief × score/100`), bill `Billing.splint`,
bus `splint:applied (src, p, injury, score)`. Physiology already halves fracture bleeding and pain for
splinted fractures. A score under `minScore` fails and hands the splint back.

Worn splints: every client attaches `Config.Splint.Props.attach[region]` pieces (`splint_leg` /
`splint_arm`, bone + pos + rot, configurable per region) to every ped in `Props.range` whose `nza`
state bag lists splints (players and NPC patients), local props.

Splinted leg (local player): walk only (`Effects.maxMoveBlend`), slower walk (`Effects.moveRate`),
optional clipset (`Effects.legClipset`); optional no-aim for a splinted arm (`Effects.armNoAim`).

Taking it off: patient option "Take the splint off" → `NZA.Treat 'splint_remove' { region }`
(`removePerm`, item back with `removeReturns`). Splints come off by themselves when no fracture is
left in the region (`autoRemoveHealed`); the X-ray cast removes the splint of that limb.

## 2. Crutches

Anyone with `Config.Items.crutches`: use the item, the keybind `nza_crutches` (default
`Crutches.key`, unbound) or `/crutches` (`Crutches.command`). Server owns the state (player state bag
`nzaCrutch`, replicated); the local player walks with `Crutches.clipset` (default the planted cane
step `move_lester_CaneUp`), walk only, no sprint / jump / weapons (`blockControls`), optional
upper-body loop (`Crutches.upper`). Two `Config.Props.crutch` props in the hands (PH_R_Hand /
PH_L_Hand, offsets `Crutches.right/left`) on every player that uses them, hidden in vehicles. The
server checks every `checkEvery` s that the item is still there; crutches drop when the player goes
down. Medics: "Give crutches" (`crutches_give`, `givePerm`) moves one crutches item from the medic to
the player patient and equips it (`autoEquip`), bill `Billing.crutches`.

## 3. Wheelchair

Use `Config.Items.wheelchair` → unfold animation → the server creates a networked
`Config.Props.wheelchair` (`prop_wheelchair_01`) `placeDistance` m in front of you (one per player,
`maxPerPlayer`). Entity state bag `nzaChair = { owner, occ, occNpc, push }`.

Target options on the chair: **Sit down** (drive yourself: W/S drive, A/D turn, F stand up),
**Take the handles** (push it; G lets go — chair attached to your hands, box-carry upper-body anim,
walk speed), **Fold the chair** (back into the item; `foldOwnerOnly`), **Help out of the chair**
(medics, `seatPerm`). Patient options: **Seat in wheelchair** (nearest free chair within
`chairRange`, players and NPC patients, bill `Billing.chair`), **Help out of the chair**. Radial:
`splint_chair` seats / un-seats the nearest patient.

Driving (`Wheelchair.drive`): acceleration / braking / rolling friction, turn rate easing off with
speed, ground following with pitch on slopes, gravity rolls you downhill (`slopeFactor`,
`downhillMax`), curbs higher than `maxStep`, drops deeper than `maxDrop` and slopes steeper than
`maxSlope` block you, capsule shape tests stop you at walls / vehicles / peds. The driver holds network
control of the chair; the pusher holds it while pushing. Mobility card (bottom-right): speed dial,
direction, grade, blocked reason, keys.

Cleanup: players leaving free their seat / handles; an empty chair whose owner left is deleted after
`abandonMinutes`; all chairs are deleted on resource stop; going down detaches you.

## 4. Registries

- `NZA.Proc.Register('splint')` · `NZA.Treat.Register('splint_remove')` · `NZA.Treat.Register('crutches_give')`
- `NZA.Interact`: `nza_splint` (44), `nza_splint_remove` (45), `nza_crutches_give` (52),
  `nza_chair_seat` (55), `nza_chair_unseat` (56)
- `NZA.ExamRoutes`: `splint` (limb fractures without splint / cast; items `Config.Items.splint`)
- `NZA.RadialItems` (parent `patient`): `splint_apply`, `splint_chair`
- Usable items (server, `Bridge.Inv.RegisterUsable`): crutches, wheelchair
- `Bridge.Target.Model(Config.Props.wheelchair)`: `nza_chair_sit / push / fold / out`

## 5. Events, callbacks, NUI

| Name | Kind | Payload |
|---|---|---|
| `nza:splint:pose` | S→C | `on` — sit down / get up while being splinted |
| `nza:splint:crutch` | S→C | `on, silent` |
| `nza:splint:crutch:toggle` | callback | `() → { ok, on } \| { ok = false, err, msg }` |
| `nza:splint:chair:place` | S→C | start unfolding |
| `nza:splint:chair:spawn` | callback | `(coords, heading) → { ok, net }` |
| `nza:splint:chair:sit` / `push` / `fold` | callback | `(net[, on]) → { ok }` |
| `nza:splint:chair:seat` / `unseat` | callback | `(net, target) → { ok, npc }` / `(net) → { ok, npc, occ }` |
| `nza:splint:chair:leave` | C→S | `net` |
| `nza:splint:chair:seated` | S→C | `net, on` |

NUI app `splint`: open `{ mode = 'proc', … }` (see the app.js header) or `{ mode = 'hud', hud }`;
actions `result`, `hud`, `hudOff`; anchors `prox dist cms core`; callbacks `splint:finish`,
`splint:abort`, `splint:done`, `splint:close`.
Browser preview: `index.html?app=splint&stage=place|aligned|pad|shape|strap|cms|cmsbad|done|arm|hud-chair|hud-push|hud-crutch|hud-blocked`
(the preview renders a 3D street scene with a patient so the overlay can be judged in context).

Lua API: client `NZA.Splint.Run(entity, target, injuryId?, region?)`, `NZA.Splint.HudSet(kind, data)`,
`NZA.Splint.CrutchesOn()`, `NZA.Splint.ToggleCrutches()`, `NZA.Splint.InChair()`, `NZA.Splint.Pushing()`,
`NZA.Splint.SeatPatient(ped, target)`, `NZA.Splint.UnseatPatient(ped)`; server `NZA.Splint.SetCrutches(src, on)`,
`NZA.Splint.HasCrutches(src)`, `NZA.Splint.Remove(p, region, src)`, `NZA.Splint.Chairs()`, `NZA.Splint.ChairOf(src)`.

## 6. Config keys (summary)

`Splint`: enabled perm item minTime maxTime easyTime maxDist states regions device{leg,arm} limbRadius
tolerance angleTolerance lockHold rotateSpeed nudgeSpeed fine shapePoints shapeSeconds shapeClick
shapeZone strapZone strapTight strapPeriod requireDressedOpen painRelief minScore camera anim
patientPose keys cmsBones shockSys removePerm removeReturns autoRemoveHealed ·
`Props`: enabled range attach · `Effects`: enabled maxMoveBlend moveRate legClipset armNoAim ·
`Crutches`: enabled item prop clipset upper moveRate maxMoveBlend key command right left blockControls
hideInVehicle checkEvery give givePerm autoEquip hud · `Wheelchair`: enabled item prop maxPerPlayer
placeDistance seatPerm foldOwnerOnly abandonMinutes states seat push place drive keys hud ·
`Interact`: distance splint remove crutches chair chairRange icons · `Radial`: enabled range ·
`Billing`: splint crutches chair.

## 7. Known limits

- GTA has no crutch animation set; the default walk is the planted cane step with a crutch in each
  hand. Owners can switch `Crutches.clipset` / add `Crutches.upper` to taste. Attach offsets follow
  `docs/modules/props.md` and are configurable.
- Worn-splint rotations (`Props.attach[*].rot`) follow props.md; if the channel's open side faces
  the wrong way on your ped models, flip `rot.x` (-90 ↔ 90).
- Wheelchair objects move by network control; very high latency shows the chair stepping for
  observers. Native `prop_wheelchair_01` origins vary per map edit — the drive keeps the measured
  ground offset of each chair.
- NPC patients can be seated only when the medic's client gets network control of the ped.
