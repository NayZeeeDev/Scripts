# Module: splint — field splinting, crutches, wheelchair

## Files

| File | What |
|---|---|
| `config/modules/splint.lua` | `Config.Splint` (Splint, Props, Effects, Crutches, Wheelchair, Interact, Radial, Billing) |
| `locales/en/splint.lua` | every `splint.*` string (Lua + NUI, incl. the device print on the splint liner) |
| `server/modules/splint.lua` | procedure `splint`, treatments `splint_remove` / `crutches_give`, crutches state, healed-splint removal |
| `server/modules/splint_chair.lua` | wheelchair objects (server-created, networked), sit / push / fold / seat patients, cleanup |
| `client/modules/splint.lua` | procedure runner (camera, anchors, NUI), patient options, exam route, radial, worn splint props, splinted-leg walk, patient pose, mobility card host |
| `client/modules/splint_crutch.lua` | crutch walk, crutch props on every player, keybind / command, "Give crutches", crutch card data |
| `client/modules/splint_chair.lua` | unfold, sit + drive (W A S D), push, fold, seat / help out patients, chair target options, chair card data |
| `html/apps/splint/app.js` · `app.css` | NUI app `splint`: the minigame (3D splint over the game) and the mobility card |

## 1. Splinting (NZA.Proc `splint`)

Who / what: permission `Config.Splint.Splint.perm` (`splint`), one `Config.Items.splint` (taken on finish),
patient `alive` or `wounded`, a limb fracture (`Config.Splint.Splint.regions`) without splint or cast.
Open fractures can be required to be covered first (`requireDressedOpen`, skipped in easy mode).
No special room is needed. Easy mode (per department easy flag / `Config.EasyMode.default`): core
progress bar for `easyTime` s, only the splint item is needed.

Camera: straight down over the broken segment (`NZA.Cam.TopDown`, heading turned so the limb runs up the
screen, height so the segment fills `camera.fill` of the screen); a side camera (`NZA.Cam.Close`) when
the limb is upright. A standing player patient sits on the ground for it (`patientPose`, event
`nza:splint:pose`).

### The 3D splint

A real-time three.js model drawn over the game with the game camera's lens (`camera.fov`), at true scale
(`device.width/depth/wall`, metres) between the joint anchors, so it keeps its place and perspective while
the view turns / zooms. Detail:

- **Printed foam liner** (one texture over the inner surface): closed-cell dimples, a centimetre rule along
  one wall, teal **joint lines** across the floor at the knee / ankle (elbow / wrist …) positions with
  their names (line the joints up with them), the device print (`CS-76 · POSTERIOR LEG SPLINT · SINGLE
  PATIENT USE · LATEX FREE`) and an amber **warning sticker** ("CHECK PULSE BELOW · after every strap").
  Generic device labelling only — no brand or logo anywhere.
- Moulded teal shell (clearcoat), **stitched woven edge binding** round both rims, end caps, the leg's foot
  plate (screws, strap slot ribs, lightening slot, foam pad) or the arm's palm roll.
- Straps: nylon webbing with bound, stitched edges and a box-stitched hook-and-loop patch at the free end;
  riveted anchor tab on the near rim, metal **D-ring** on the far rim, **numbered pull tab** (1 · 2 · 3)
  hanging off the folded tail.
- The limb lies on it: the splint is hidden where the limb is (screen-space capsule from the joint anchors),
  the foam right next to the limb is darkened (contact shadow), the splint's ground shadow is cut out under
  the limb, wrapped straps throw a soft shadow on the limb. Open straps lying under the limb are hidden too.
- It starts beside the limb on the free side (away from the body) unless that side would run into the HUD
  columns / off screen, then on the other side.

### Steps

All keys in `Config.Splint.Splint.keys` (KeyboardEvent codes).

| Step | What you do | Controls |
|---|---|---|
| 1 Lay the splint | Drag the splint under the limb until both ends reach past the joint above and below (diamond targets on the joints turn teal "Seated", mm-off readout in the tags and the readout column, fit dial). It sets after `lockHold` s steady (or Space). | Drag · Q / E turn · arrows nudge · Shift fine · X start over · Space set · right-drag rotate view · wheel zoom |
| 2 Pad & shape | **2 Padding**: click the bony points (knee / ankle, elbow / wrist …) — foam pads appear between limb and wall. **3 Shape**: press & hold each point until the walls close on the limb; release while the pressure dial sits on the teal arc (`shapeZone`) — over-squeezing leaves a pressure point. Shaping next to an unpadded bony point is refused. Amber gap bands show where the wall still stands off the limb. | Click / hold · 2 / 3 switch tool · Shift gentle |
| 3 Strap & check | **4 Straps**: click a strap → it flips over the limb and through its D-ring; click (or Space) when the needle of the tension gauge is on the teal arc (`strapZone`); above `strapTight` = too tight. **5 Distal check**: click the toes / fingers → circulation (live pleth trace + capillary refill ring), movement and feeling (the patient answers in the voice card when responsive). A tight strap cuts the pulse off → the step turns into "Loosen the tight strap", the strap is outlined red → click it to loosen, cinch again, re-check. | Click · Space cinch · 5 check |

HUD (NZA.ui.ProcPanel: left column + right tool belt; screen centre and bottom-centre stay clear):
readout dial + instrument list (fit → contact / pressure → tension / straps → score), step card with the
step spine, tool belt (Splint · Padding · Shape · Straps · Distal check) with the hold ring. Top-left:
fracture card (bone illustration with the break and displacement angle, pulse below, pain, device).
Top-right: distal-check card while checking; **splint record** after the finish — grade ring, region and
device, a **top-view map of the splint** (joint lines, pads, shaping points coloured by how well they sit,
strap bands with their tension, distal check), alignment / shaping / straps bars and the outcome line.
The readout column then shows score, time, pressure points and the distal check; Enter finishes.

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

Anyone with `Config.Items.crutches`: use the item, the keybind `nza_crutches` (default `Crutches.key`,
unbound) or `/crutches` (`Crutches.command`). Server owns the state (player state bag `nzaCrutch`,
replicated); the local player walks with `Crutches.clipset` (default the planted cane step
`move_lester_CaneUp`), walk only, no sprint / jump / weapons (`blockControls`), optional upper-body loop
(`Crutches.upper`). Two `Config.Props.crutch` props in the hands (PH_R_Hand / PH_L_Hand, offsets
`Crutches.right/left`) on every player that uses them, hidden in vehicles. The server checks every
`checkEvery` s that the item is still there; crutches drop when the player goes down. Medics: "Give
crutches" (`crutches_give`, `givePerm`) moves one crutches item from the medic to the player patient and
equips it (`autoEquip`), bill `Billing.crutches`.

Crutch card (bottom-right, `Crutches.hud`): top-view gait drawing — both forearm crutches (rubber tip,
shaft, grip, cuff) planting ahead, the good foot swinging through, the splinted / broken foot dashed amber,
lifted off the ground with its shadow and an `NWB` (non-weight-bearing) tag (side taken from the self
snapshot), the prints already left behind and crutch lanes that scroll while walking; a three-phase gait
strip (1 Tips ahead · 2 Swing · 3 Plant) that follows the step rhythm; rolling step counter
(`Crutches.stride` m per step), cadence (steps / min, worked out in the app from the step count over the
last ~8 s, or `cadence` when the client sends it), weight on, pace, key to put them away.

## 3. Wheelchair

Use `Config.Items.wheelchair` → unfold animation → the server creates a networked
`Config.Props.wheelchair` (`prop_wheelchair_01`) `placeDistance` m in front of you (one per player,
`maxPerPlayer`). Entity state bag `nzaChair = { owner, occ, occNpc, push }`.

Target options on the chair: **Sit down** (drive yourself: W/S drive, A/D turn, F stand up),
**Take the handles** (push it; G lets go — chair attached to your hands, box-carry upper-body anim,
walk speed), **Fold the chair** (back into the item; `foldOwnerOnly`), **Help out of the chair**
(medics, `seatPerm`). Patient options: **Seat in wheelchair** (nearest free chair within `chairRange`,
players and NPC patients, bill `Billing.chair`), **Help out of the chair**. Radial: `splint_chair`
seats / un-seats the nearest patient.

Driving (`Wheelchair.drive`): acceleration / braking / rolling friction, turn rate easing off with speed,
ground following with pitch on slopes, gravity rolls you downhill (`slopeFactor`, `downhillMax`), curbs
higher than `maxStep`, drops deeper than `maxDrop` and slopes steeper than `maxSlope` block you, capsule
shape tests stop you at walls / vehicles / peds. The driver holds network control of the chair; the
pusher holds it while pushing.

Chair card (bottom-right, `Wheelchair.hud`): top view of the chair with tread that scrolls with each
wheel's rim speed and per-wheel drive bars (turning on the spot drives them against each other), heading
arrow, turn arcs, the occupant / the person pushing; state chip (Rolling · Reversing · Parked · Blocked ·
Being pushed); rolling speed counter (km/h) with a speed bar, inclinometer + grade, rolling distance
counter; an amber note with the reason when blocked (curb, drop, too steep, something in the way); keys.

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
actions `result`, `hud` (the mobility card closes with the app); anchors `prox dist cms core`; callbacks `splint:finish`,
`splint:abort`, `splint:done`, `splint:close`.
Card data: chair / push `{ kind, title, sub, state, speed, max, slope, turn, dist, blocked, keys }`,
crutch `{ kind, title, sub, state, moving, steps, cadence?, side, keys }`.

Browser preview (renders a 3D street scene with a patient so the overlay can be judged in context; stages
are set up synchronously): `index.html?app=splint&stage=place|aligned|pad|shape|strap|cmsready|cms|cmsbad|done`,
the forearm with an `arm-` prefix (`arm`, `arm-pad`, `arm-done` …), cards `hud-chair|hud-push|hud-blocked|hud-crutch`.

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
hideInVehicle checkEvery give givePerm autoEquip hud stride · `Wheelchair`: enabled item prop maxPerPlayer
placeDistance seatPerm foldOwnerOnly abandonMinutes states seat push place drive keys hud ·
`Interact`: distance splint remove crutches chair chairRange icons · `Radial`: enabled range ·
`Billing`: splint crutches chair.

## 7. Known limits

- GTA has no crutch animation set; the default walk is the planted cane step with a crutch in each
  hand. Owners can switch `Crutches.clipset` / add `Crutches.upper` to taste. Attach offsets follow
  `docs/modules/props.md` and are configurable.
- Worn-splint rotations (`Props.attach[*].rot`) follow props.md; if the channel's open side faces
  the wrong way on your ped models, flip `rot.x` (-90 ↔ 90).
- The NUI splint hides itself under the limb with a capsule of `limbRadius` between the joint anchors
  (it cannot read the game's depth buffer); very baggy clothing can stick out of that capsule a little.
- Wheelchair objects move by network control; very high latency shows the chair stepping for
  observers. Native `prop_wheelchair_01` origins vary per map edit — the drive keeps the measured
  ground offset of each chair.
- NPC patients can be seated only when the medic's client gets network control of the ped.
