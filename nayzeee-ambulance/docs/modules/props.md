# Module: props — streamed models

Owner files: `tools/props/**` (code-only model pipeline, see `tools/props/README.md`) and
`stream/**` (the built binaries). Lead-owned references: `config/props.lua` (`Config.Props`,
`Config.PropScreens`, `Config.PropFallbacks`), `fxmanifest.lua`.

Every generated prop is built from code - geometry, UV atlas, baked PBR-style textures (colour,
normal, specular/gloss, ambient occlusion, chipped edge wear, scratches, smudges, crevice grime, dust,
printed labels with fine print), collision and the archetype - then converted to real GTA V binaries
with CodeWalker and re-loaded/validated before it is copied to `stream/`. Nothing in `stream/` is hand
edited: rebuild with `python3 tools/props/build.py` (below).

The **medic bag** is the exception: `nz_amb_medbag_red / _green / _orange / _magenta` are the
customer's artist-made model (~4.8k tris, 2048 diffuse + 1024 normal + 1024 spec), brought in with
`tools/props/import_model.py` (renamed drawable + textures, DXT re-encode with mips, validated). Their
metadata lives in `tools/props/external/*.json`; the build keeps them in the ytyp and never deletes or
regenerates them. They are not in the generated table / catalog below.

## 1. What ships

| | |
|---|---|
| `stream/nz_amb_*.ydr` | 46 drawables (one per model: 42 generated + 4 imported medic bag colours). Textures are **embedded** in each drawable's own dictionary (txd name = model name), collision is **embedded** (composite bound of boxes / cylinders). No separate `.ytd` / `.ybn`. |
| `stream/nz_amb_props.ytyp` | one archetype file with all 46 `CBaseArchetypeDef`s (bounds, `lodDist`, `hdTextureDist`, static flag) |
| manifest | `files { 'stream/*.ytyp' }` + `data_file 'DLC_ITYP_REQUEST' 'stream/*.ytyp'` (already in `fxmanifest.lua`, see `docs/requests/props.md`) |

Total stream size and per-model numbers are in the generated table (section 8).

## 2. Conventions (all models)

* **Units / axes**: metres, GTA prop space **+X right, +Y forward (the prop's front / screen side),
  +Z up**. Heading 0 of an entity = its +Y points north.
* **Origin** is where the prop is placed or held: floor centre for furniture, bottom centre for things
  standing on surfaces, the grip for hand tools, the hanging slot for bags, the limb / neck axis for
  worn props, the back face for the wall screen, the mask rim for the BVM, the lip line for the ETT.
* **Static vs dynamic**: furniture and the bay shell are archetype-static (flag 32, cheapest, never
  pushed by physics); everything that is carried, attached or dropped is dynamic. Freeze / attach
  them anyway (`NZA.Props.Spawn` freezes by default).
* **LOD**: one high-detail LOD per model, culled by the archetype `lodDist` (30-40 m hand tools,
  50-90 m equipment, 100-150 m furniture / stretcher / bay); `hdTextureDist` per model.
* **Spawning**: always through the Config key, e.g.
  `NZA.Props.Spawn('xray_table', coords, { heading = h, fallbackKey = 'xray_table' })` or
  `NZA.Props.Spawn(Config.Props.pager, { attach = { entity = ped, bone = 28422, pos = vec3(0, 0, 0), rot = vec3(-90, 0, 0) } })`.
* **Attach rotations** in this document are `AttachEntityToEntity` rotations (degrees, rotation order
  2, the default used by `NZA.Props.Spawn`). Bone axes differ between bones and anim poses: values
  marked *start* are measured starting points to fine-tune per animation.
* **Labelling**: no maker name, wordmark or logo on any prop (ours or a real company's). Devices carry
  generic labelling: device type + invented model code (`PM-8` monitor, `MD-2` defibrillator, `SU-2`
  suction, `IO-3` IO driver, `TK-62` trauma case, `PC-2` cot, `US-9` ultrasound ...), rating plates
  (MODEL / SN / REF / LOT, electrical rating, regulatory symbols, barcode + data-matrix), caution /
  danger stickers, calibration and asset tags, the star of life or a plain cross.
* **Detail / budgets**: bevelled shells with split lines, screws, rubber feet and bumpers, strain
  reliefs, legends on buttons, knurled knobs, stitched straps, vents and grilles. Hand-held tools
  <= 12k tris with 1024 textures (full-size normal + spec), devices / field kit / furniture 2048
  (normal + spec 1024), the bay shell 2048 + 2048 + 2 x 1024 sets.

## 3. Screens (DUI targets)

Every screen is an emissive quad whose texture keeps a fixed 0..1 UV layout (top-left of the image =
top-left of the screen as seen by a viewer in front of it). The texture is called `nz_amb_screen`
and lives in the model's own dictionary, so the runtime replacement is:

```lua
local dui = CreateDui(url, w, h)
local rtxd = CreateRuntimeTxd('nza_' .. key)
CreateRuntimeTextureFromDuiHandle(rtxd, 'screen', GetDuiHandle(dui))
AddReplaceTexture(Config.PropScreens[key].txd, Config.PropScreens[key].tex, 'nza_' .. key, 'screen')
-- cleanup: RemoveReplaceTexture(txd, tex); DestroyDui(dui)
```

A replacement affects every instance of that model on the client (do it while the player uses it).

| Model | Quad (m) | Aspect | Embedded default (px) | Centre / facing (prop space) |
|---|---|---|---|---|
| `nz_amb_monitor` | 0.180 x 0.112 | 1.61 | 512 x 256 vitals (bed / alarm / battery header) | front (+Y) panel, controls to its +X |
| `nz_amb_defib` | 0.170 x 0.096 | 1.77 | 512 x 256 manual defib | front (+Y) |
| `nz_amb_pager` | 0.056 x 0.022 | 2.55 | 256 x 128 LCD | front (+Y) |
| `nz_amb_us_cart` | 0.40 x 0.25 | 1.60 | 512 x 320 eFAST B-mode (RUQ free fluid) | (0, -0.114, 1.278) +Y |
| `nz_amb_angio_monitor` | 0.94 x 0.53 | 1.77 | 1024 x 512 live fluoro | (0, 0.6585, 1.55) +Y |
| `nz_amb_lightbox` | 0.60 x 0.75 | 0.80 | 512 x 512 white diffuser | (0, 0.1465, 1.47) +Y |
| `nz_amb_blood_mixer` | 0.110 x 0.055 | 2.00 | 256 x 128 collection LCD | (0.035, 0.1185, 0.1875) +Y |
| `nz_amb_tv_board` | 1.568 x 0.882 | 16:9 | **1024 x 576** waiting-room board (now serving / queue / clock) | (0, 0.0343, 0.008) +Y |
| `nz_amb_bay_shell` | 0.84 x 0.40 | 2.10 | 512 x 256 dark standby (clock, cabin temp, O2 main) | (-0.20, 2.1045, 1.68) -Y |

`Config.PropScreens` currently lists tv_board, monitor, angio_monitor and us_cart; the others are
requested in `docs/requests/props.md` (all use tex `nz_amb_screen`, txd = model name).

## 4. Worn and hand-held props - attach recipes

Bones: `SKEL_R_Hand` 57005, `PH_R_Hand` 28422 (right hand grip helper), `SKEL_L_Hand` 18905,
`PH_L_Hand` 60309, `SKEL_Pelvis` 11816, `SKEL_Neck_1` 39317, `SKEL_Head` 31086, upper arms
45509 (L) / 40269 (R), forearms 61163 (L) / 28252 (R), thighs 58271 (L) / 51826 (R), calves 63931 (L) /
36864 (R). Limb bones run their **+X along the bone** (towards the hand / foot).

| Prop | Bone | pos | rot | Notes |
|---|---|---|---|---|
| `binder_worn` | SKEL_Pelvis 11816 | (0, 0, 0) | (0, 90, 0) or (90, 0, 90) *start* | loop around the pelvis, buckle at the front (+Y); collision off |
| `tourniquet_worn` | limb bone (see list) | (0.12, 0, 0) | (0, 0, 0) | loop axis = X = bone axis; windlass on top; upper arm / thigh above the wound |
| `collar` | SKEL_Neck_1 39317 | (0, 0, 0) | (0, 90, 0) or (0, -90, 180) *start* | chin support +Y; collision off |
| `splint_leg` | calf 63931 / 36864 | (0.10, 0, 0) | (90, 0, 0) or (-90, 0, 0) | channel open side must face the shin; foot plate at +X (foot) |
| `splint_arm` | forearm 61163 / 28252 | (0.12, 0, 0) | rotate about X until the open side faces the forearm | palm roll at +X (hand) |
| `crutch` | PH_R_Hand 28422 / SKEL_R_Hand 57005 | (0, 0, 0) / (0.08, 0.02, 0) | (0, 0, 0) / (90, 0, 90) | origin = hand grip; second crutch PH_L_Hand 60309 |
| `pager` | PH_R_Hand 28422 | (0, 0, 0) | (-90, 0, 0) | belt: SKEL_Pelvis pos (0, 0.14, 0.1) rot (0, 0, 180) |
| `syringe` | PH_R_Hand 28422 / SKEL_R_Hand 57005 | (0, 0, 0) / (0.09, 0.03, -0.01) | (0, 0, -90) / (-80, 0, 0) | origin = finger flange, needle +Y |
| `stethoscope` | SKEL_R_Hand 57005 | (0.12, 0.03, -0.02) | (-80, 0, 0) | what the assess module uses (`Config.Assess` breathing prop); coiled model lying on XY, chest piece at +X |
| `laryngoscope` | PH_L_Hand 60309 / SKEL_L_Hand 18905 | (0, 0, 0) / (0.08, 0.02, 0) | (0, 0, 0) / (0, 90, 0) | handle along Z, blade +Y (left hand, as used clinically) |
| `us_probe` | PH_R_Hand 28422 / SKEL_R_Hand 57005 | (0, 0, 0) / (0.08, 0.03, -0.02) | (180, 0, 0) / (90, 0, 0) | lens -Z |
| `iodrill` | PH_R_Hand 28422 / SKEL_R_Hand 57005 | (0, 0, 0) / (0.10, 0.02, -0.02) | (0, 0, -90) / (-90, 0, 0) | origin = pistol grip, needle +Y |
| `bvm` | SKEL_Head 31086 (on the patient) | (0.06, 0.11, 0) | (0, -90, -90) *start* | mask rim at the origin, face side -Z; medic's left hand holds the mask, right hand squeezes the bag at (0, 0.21, 0.095) prop space |
| `ett` | SKEL_Head 31086 (on the patient) | (-0.04, 0.12, 0) | (0, 90, 0) *start* | origin = lip line; only the connector + holder show outside the mouth |
| `kitcase_closed` | PH_R_Hand 28422 | (0, -0.245, -0.06) | (0, 0, 0) | carried by the handle |
| `medbag` (imported, `_red/_green/_orange/_magenta`) | PH_R_Hand 28422 | (0, 0, -0.36) | (0, 0, 0) *start* | carried by the top straps; origin = bottom centre like the native bag it replaces, so its attach values carry over |
| `monitor` | PH_R_Hand 28422 | (0, -0.03, -0.24) | (0, 0, 90) | carried by the top handle |
| `defib` | PH_R_Hand 28422 | (0, -0.06, -0.26) | (0, 0, 90) | carried by the top handle |
| `suction` | PH_R_Hand 28422 | (0.03, 0, -0.26) | (0, 0, 0) | carried by the top handle |
| `ivbag_saline`, `bloodbag_*` | IV stand entity | (0.073, 0, 1.766) / (-0.073, 0, 1.766) | (0, 0, 0) | bag origin = hanging slot; bay: IV hooks of the bay shell |

## 5. Ambulance treatment bay - `nz_amb_bay_shell`

A complete walk-in patient compartment built as ONE closed static prop (not an MLO). Spawn it at a
hidden location (the transport module uses a grid under Mount Chiliad), keep it frozen, light it with
script lights and teleport the crew + patient in.

**Interior**: 2.30 m wide (X -1.15 .. 1.15) x 4.30 m long (Y -2.15 .. 2.15) x 2.05 m high (Z 0 .. 2.05).
Origin = floor centre. +Y = cab bulkhead, -Y = rear doors. All room surfaces face inwards; a thin
outer skin (6 cm) closes the box from outside. Collision: floor, ceiling, four walls (the rear doors
are closed - leave through the exit marker), both cabinet runs, bench + backrest, counter, attendant
seat, O2 cylinder, monitor shelf and the stretcher mount.

```
                        +Y  cab bulkhead (y = 2.15)
     ┌──────────────────────────────────────────────────┐
     │ O2   [attendant seat]  [ wall monitor ]  clock  ▓▓│  counter: kit + sharps
     │cyl                                             ▓▓▓│  + glove dispenser
 L6  │            ▄ mount (y 1.30)                   ▓▓▓│ R6
     │  O2/suction panel                              ▓▓▓│
 L5  │     ┌───────────┐                             ─────│ R5
     │ ▭   │ stretcher │  IV rail (x -0.18)        bench │
 L4  │shelf│ (-0.42,   │                           seat 3│ R4
     │     │  0.10)    │  ── grab rail (x 0.30) ── seat 2│ R3
 L3  │     │  head +Y  │                           seat 1│ R2
     │     └───────────┘                                 │
 L2  │                        medic spawn (0.30, -1.62)  │ R1
 L1  │                        EXIT marker (0, -1.90)  ext│
     └──────────────────[ rear doors ]───────────────────┘
       -X (patient side)    -Y (y = -2.15)       +X (bench side)
     upper glass-front supply cabinets on both long walls (z 1.34 .. 2.05, 0.34 deep)
```

| Point (prop space, metres) | Value | Notes |
|---|---|---|
| Stretcher (`nz_amb_stretcher` origin) | (-0.42, 0.10, 0.0), heading +0 | head end towards the cab; floor tracks + mount block at y 1.22 .. 1.38 |
| Patient on the stretcher | stretcher entity + (0.0, 0.05, 1.33) rot (0, 0, 180) | the stretcher's own recipe; mattress top z 0.885 |
| Medic spawn (enter) | (0.30, -1.62, 0.0), heading +0 | just inside the rear doors, facing the cab |
| Medic work spots | (0.15, 0.35, 0.0) h +90 (beside the chest, facing the cot) · (-0.42, 1.42, 0.0) h +180 (head end) · (0.10, -0.85, 0.0) h +60 (legs) | walkway between cot and bench is 0.79 m |
| Bench seats | (0.93, -1.317 / -0.450 / 0.417, 0.50), heading +90 | seated peds face -X (the patient); seat top z 0.50 |
| Attendant (captain's) seat | (-0.42, 1.86, 0.48), heading +180 | faces the rear / patient's head |
| IV hooks (bag origin) | (-0.18, 0.95, 1.86) head end · (-0.18, -0.30, 1.86) | two hooks each (±0.04 in X); ceiling IV rail x -0.18, y -1.5 .. 1.7 |
| Patient monitor shelf | top (-1.02, 0.30, 1.10) | place `nz_amb_monitor` there with rot (0, 0, -90) (screen faces +X) |
| Bulkhead wall monitor | screen centre (-0.20, 2.1045, 1.68), faces -Y, 0.84 x 0.40 | DUI target, txd `nz_amb_bay_shell` / `nz_amb_screen`; camera: (-0.20, 1.30, 1.62) looking +Y |
| O2 / suction wall panel | (-1.14, 0.80 .. 1.46, 1.06 .. 1.30) | O2 flowmeter y 0.80, suction gauge y 1.06, outlets y 1.28 / 1.36 / 1.46 |
| Counter top | x 0.72 .. 1.15, y 0.95 .. 2.15, z 0.95 | red kit case (0.93, 1.20) · sharps bin (0.98, 1.99) · glove dispenser on the wall (1.08, 1.62, 1.15) |
| Exit marker | (0.0, -1.90, 0.0), radius ~0.8 | in front of the closed rear doors (door handles at x ±0.12, z 1.06) |
| Interior lights (script) | (0.0, -1.0, 1.95) and (0.0, 0.95, 1.95): `DrawLightWithRange` colour 245/248/255, range 4.5, intensity 3-4; optional over the cot (-0.42, 0.10, 1.75) range 2.2 intensity 1.5 | the four ceiling panels (x ±0.55, y -1.70 .. -0.30 / 0.20 .. 1.60) and the under-cabinet strips are emissive but do not light the room by themselves |
| Overview cameras | from the doors (0.52, -2.05, 1.70) → (-0.45, 0.9, 0.95) fov 75 · from the cab (0.25, 1.95, 1.70) → (-0.10, -1.6, 0.9) | the renders in `/tmp/nza-work/props/out/renders/nz_amb_bay_shell_*.png` use these |

**Supply cabinets** - six bays per long wall, two rows each, sliding glass doors, a printed label strip
on the rail under every row (category name + colour chip + slot code) and stock that matches the
category (labelled cartons, bandage / tape rolls, IV bags, O2 mask pouches, BVMs, collars, head
blocks, tourniquets...). Use the slot centres as interaction / camera targets (front plane of the
cabinets: x = -0.81 left, x = +0.81 right):

| Code | Wall | Row | Category | Slot centre (front plane) | Width |
|---|---|---|---|---|---|
| L1-U | left (-X) | upper | BANDAGES | (-0.81, -1.533, 1.860) | 0.633 |
| L1-L | left (-X) | lower | GAUZE & DRESSINGS | (-0.81, -1.533, 1.535) | 0.633 |
| L2-U | left (-X) | upper | MEDICAL TAPE & WRAP | (-0.81, -0.900, 1.860) | 0.633 |
| L2-L | left (-X) | lower | BURN CARE | (-0.81, -0.900, 1.535) | 0.633 |
| L3-U | left (-X) | upper | TRAUMA SUPPLIES | (-0.81, -0.267, 1.860) | 0.633 |
| L3-L | left (-X) | lower | TRAUMA SUPPLIES | (-0.81, -0.267, 1.535) | 0.633 |
| L4-U | left (-X) | upper | IV FLUIDS | (-0.81, 0.367, 1.860) | 0.633 |
| L4-L | left (-X) | lower | IV ACCESS & EXTENSION SETS | (-0.81, 0.367, 1.535) | 0.633 |
| L5-U | left (-X) | upper | SYRINGES & NEEDLES | (-0.81, 1.000, 1.860) | 0.633 |
| L5-L | left (-X) | lower | IV FLUIDS | (-0.81, 1.000, 1.535) | 0.633 |
| L6-U | left (-X) | upper | AIRWAY & RESUSCITATION | (-0.81, 1.633, 1.860) | 0.633 |
| L6-L | left (-X) | lower | OXYGEN MASKS & NASAL CANNULA | (-0.81, 1.633, 1.535) | 0.633 |
| R1-U | right (+X) | upper | SPINAL IMMOBILIZATION | (0.81, -1.517, 1.860) | 0.667 |
| R1-L | right (+X) | lower | SPINAL IMMOBILIZATION | (0.81, -1.517, 1.535) | 0.667 |
| R2-U | right (+X) | upper | CERVICAL COLLARS | (0.81, -0.850, 1.860) | 0.667 |
| R2-L | right (+X) | lower | CERVICAL COLLARS | (0.81, -0.850, 1.535) | 0.667 |
| R3-U | right (+X) | upper | CPAP / BVM | (0.81, -0.183, 1.860) | 0.667 |
| R3-L | right (+X) | lower | OXYGEN MASKS & NASAL CANNULA | (0.81, -0.183, 1.535) | 0.667 |
| R4-U | right (+X) | upper | GAUZE & DRESSINGS | (0.81, 0.483, 1.860) | 0.667 |
| R4-L | right (+X) | lower | BANDAGES | (0.81, 0.483, 1.535) | 0.667 |
| R5-U | right (+X) | upper | SYRINGES & NEEDLES | (0.81, 1.150, 1.860) | 0.667 |
| R5-L | right (+X) | lower | IV ACCESS & EXTENSION SETS | (0.81, 1.150, 1.535) | 0.667 |
| R6-U | right (+X) | upper | AIRWAY & RESUSCITATION | (0.81, 1.817, 1.860) | 0.667 |
| R6-L | right (+X) | lower | MEDICAL TAPE & WRAP | (0.81, 1.817, 1.535) | 0.667 |

A good "Supplies" interaction target is a sphere at (0.85, -0.45, 1.65) (right wall over the bench) or
one per wall at (±0.85, 0.0, 1.65), radius 1.0.

**Texture sets** (all embedded, ≤ 1024): `_shell_*` walls / floor / ceiling, `_d/_n/_s` furniture,
`_supl_*` / `_supr_*` the two cabinet runs with their printed stock, `_a*` cabinet glass, `_g` light
panels, `nz_amb_screen` the wall monitor.

**Runtime notes**: it is a prop, not an MLO interior, so (a) script lights are required, (b) rain /
snow particles can show inside while the weather is wet - call `SetRainLevel(0.0)` (+ `SetSnowLevel`
for snow weathers) locally while inside and `SetRainLevel(-1.0)` on exit, (c) spawn it with
`network = false` per client (every client builds its own copy at the same hidden slot).

## 6. Hospital equipment - placement notes

All furniture is static with its origin on the floor; place the point at floor level with the heading
the prop's +Y should face (the operator side). Key offsets (full details in the catalog, section 9):

| Prop | Use |
|---|---|
| `xray_table` | patient surface z 0.825 (head end +Y); tube focal spot (0, 0.35, 1.66), collimator light field bottom z 1.42 (point a camera straight down from there for a film view); medic at (+0.75, 0) facing -X; column + floor rail on -X need 0.8 m of free floor on that side |
| `lightbox` | panel (0, 0.1465, 1.47) 0.60 x 0.75, film plane y 0.1505; reading camera from (0, 1.05, 1.47) |
| `us_cart` | operator at (0, 0.75) facing -Y; screen camera (0, 0.55, 1.30) → (0, -0.114, 1.278); 3 probes parked in holders (+X x2, -X x1) + gel bottle |
| `injector` + `injector_plunger` | spawn both; plunger attached at (0.03, 0.05, 1.04) and slid 0 .. 0.20 m along -X; syringe tip (-0.235, 0.05, 1.04); delivery line end (-0.47, 0.30, 0.66); tray camera (0, 0.55, 1.45) → (0, 0, 1.0) |
| `contrast_button` | button top (0, 0, 1.012); hand target (0, 0.02, 1.032); ped at (0, 0.45) facing -Y |
| `angio_monitor` | boom column at the origin, monitor hangs 0.62 m towards +Y, screen centre (0, 0.6585, 1.55); camera (0, 1.72, 1.55) fov 40 |
| `donation_chair` | seat top z 0.53, donor at (0, -0.08, 0.53) facing +Y, back reclined 32°; donor arm on the +X armrest, venepuncture site ≈ (0.36, 0.06, 0.70); mixer on the floor at (0.62, 0.15, 0), IV stand at (-0.55, 0, 0) |
| `blood_mixer` | tray top z 0.318 (tilted 6° to the front); blood bag lying on it: pos (-0.15, 0, 0.326) extending +X label up; line through the clamp at (0.155, 0.04, 0.24) |
| `tv_board` | origin = back centre; put the point ON the wall surface at the screen-centre height (2.0 - 2.3 m), heading = the room side |
| `surgery_tray` | drape surface z 0.909; instruments along X at y -0.12 (tips +Y), bowl (0.24, -0.12), kidney dish (0.24, 0.10), gauze (0.03, 0.12), syringe (-0.18, 0.12) |

## 7. Previews

`/tmp/nza-work/props/out/sheets/contact_01..07.png` (3 views per generated prop) and
`/tmp/nza-work/props/out/renders/<model>_<view>.png` (+ `detail` close-ups for the devices / carts that
declare them); the bay shell renders interior cameras (`int_rear`, `int_front`, `plan` cut-away,
`cab_left`, `cab_right`, `head_end`). The imported medic bag is not rendered by the pipeline.

## 8. Summary table (generated)

<!-- props:table:begin -->
| Model | Size X x Y x Z (m) | bbMin | bbMax | Tris | lodDist | Type | Screens | Collision |
|---|---|---|---|---|---|---|---|---|
| `nz_amb_angio_monitor` | 1.000 x 1.068 x 2.135 | (-0.5, -0.35, 0.0) | (0.5, 0.718, 2.135) | 12076 | 100 | static | nz_amb_screen | METAL_HOLLOW_MEDIUM, METAL_SOLID_MEDIUM, PLASTIC_HIGH_DENSITY |
| `nz_amb_bay_shell` | 2.420 x 4.420 x 2.210 | (-1.21, -2.21, -0.1) | (1.21, 2.21, 2.15) | 78416 | 120 | static | nz_amb_screen | FIBREGLASS, LEATHER, METAL_HOLLOW_MEDIUM, METAL_SOLID_MEDIUM, METAL_SOLID_SMALL, PLASTIC_HIGH_DENSITY |
| `nz_amb_binder_flat` | 1.020 x 0.230 x 0.018 | (-0.56, -0.12, -0.0) | (0.46, 0.12, 0.02) | 1104 | 60 | dynamic | - | CLOTH |
| `nz_amb_binder_worn` | 0.359 x 0.274 x 0.200 | (-0.18, -0.13, -0.11) | (0.18, 0.144, 0.11) | 1560 | 60 | dynamic | - | CLOTH |
| `nz_amb_blood_mixer` | 0.348 x 0.236 x 0.339 | (-0.173, -0.115, 0.0) | (0.175, 0.121, 0.339) | 4198 | 50 | dynamic | nz_amb_screen | PLASTIC_HIGH_DENSITY |
| `nz_amb_bloodbag_0` | 0.134 x 0.021 x 0.343 | (-0.068, -0.007, -0.35) | (0.068, 0.015, 0.0) | 3228 | 50 | dynamic | - | PLASTIC_HOLLOW_CLEAR |
| `nz_amb_bloodbag_100` | 0.134 x 0.037 x 0.343 | (-0.068, -0.021, -0.35) | (0.068, 0.021, 0.0) | 5136 | 50 | dynamic | - | PLASTIC_HOLLOW_CLEAR |
| `nz_amb_bloodbag_25` | 0.134 x 0.022 x 0.343 | (-0.068, -0.009, -0.35) | (0.068, 0.015, 0.0) | 4388 | 50 | dynamic | - | PLASTIC_HOLLOW_CLEAR |
| `nz_amb_bloodbag_50` | 0.134 x 0.026 x 0.343 | (-0.068, -0.013, -0.35) | (0.068, 0.015, 0.0) | 4592 | 50 | dynamic | - | PLASTIC_HOLLOW_CLEAR |
| `nz_amb_bloodbag_75` | 0.134 x 0.030 x 0.343 | (-0.068, -0.017, -0.35) | (0.068, 0.017, 0.0) | 4864 | 50 | dynamic | - | PLASTIC_HOLLOW_CLEAR |
| `nz_amb_bvm` | 0.266 x 0.520 x 0.160 | (-0.065, -0.065, -0.002) | (0.202, 0.457, 0.161) | 8808 | 35 | dynamic | - | PLASTIC, RUBBER_HOLLOW |
| `nz_amb_collar` | 0.137 x 0.170 x 0.126 | (-0.075, -0.08, -0.04) | (0.075, 0.093, 0.088) | 1928 | 40 | dynamic | - | PLASTIC |
| `nz_amb_contrast_button` | 0.336 x 0.336 x 1.014 | (-0.168, -0.168, -0.002) | (0.168, 0.168, 1.012) | 10116 | 60 | static | - | METAL_HOLLOW_SMALL, METAL_SOLID_MEDIUM, PLASTIC_HIGH_DENSITY |
| `nz_amb_crutch` | 0.100 x 0.190 x 1.206 | (-0.055, -0.128, -0.86) | (0.055, 0.08, 0.346) | 4076 | 70 | dynamic | - | METAL_HOLLOW_SMALL, PLASTIC, RUBBER |
| `nz_amb_defib` | 0.382 x 0.146 x 0.268 | (-0.195, -0.064, 0.0) | (0.188, 0.082, 0.268) | 12132 | 70 | dynamic | nz_amb_screen | PLASTIC_HIGH_DENSITY, RUBBER |
| `nz_amb_donation_chair` | 0.907 x 1.601 x 1.299 | (-0.449, -0.826, 0.0) | (0.458, 0.775, 1.299) | 12338 | 90 | static | - | LEATHER, PLASTIC_HIGH_DENSITY |
| `nz_amb_ett` | 0.159 x 0.273 x 0.171 | (-0.08, -0.15, -0.147) | (0.08, 0.123, 0.024) | 5364 | 30 | dynamic | - | PLASTIC |
| `nz_amb_infuser` | 0.218 x 0.050 x 0.581 | (-0.14, -0.03, -0.58) | (0.085, 0.03, 0.002) | 8492 | 50 | dynamic | - | CLOTH, RUBBER |
| `nz_amb_injector` | 0.926 x 0.739 x 1.160 | (-0.476, -0.433, 0.0) | (0.45, 0.306, 1.16) | 16646 | 70 | static | - | METAL_HOLLOW_SMALL, PLASTIC_HIGH_DENSITY |
| `nz_amb_injector_plunger` | 0.304 x 0.064 x 0.064 | (-0.0, -0.032, -0.032) | (0.304, 0.032, 0.032) | 1144 | 30 | dynamic | - | PLASTIC |
| `nz_amb_iodrill` | 0.046 x 0.191 x 0.141 | (-0.024, -0.084, -0.07) | (0.024, 0.108, 0.072) | 5672 | 45 | dynamic | - | PLASTIC_HIGH_DENSITY |
| `nz_amb_ivbag_saline` | 0.127 x 0.035 x 0.627 | (-0.064, -0.018, -0.627) | (0.064, 0.019, 0.0) | 5026 | 50 | dynamic | - | PLASTIC_HOLLOW_CLEAR |
| `nz_amb_ivstand` | 0.582 x 0.508 x 1.801 | (-0.3, -0.3, 0.0) | (0.3, 0.333, 1.801) | 3888 | 140 | static | - | METAL_HOLLOW_SMALL |
| `nz_amb_kitcase_closed` | 0.618 x 0.487 x 0.200 | (-0.31, -0.232, 0.0) | (0.31, 0.257, 0.205) | 12288 | 90 | dynamic | - | PLASTIC_HIGH_DENSITY |
| `nz_amb_kitcase_open` | 0.618 x 0.626 x 0.561 | (-0.31, -0.364, 0.0) | (0.31, 0.262, 0.561) | 29526 | 90 | static | - | PLASTIC_HIGH_DENSITY |
| `nz_amb_laryngoscope` | 0.029 x 0.146 x 0.165 | (-0.015, -0.015, -0.072) | (0.015, 0.132, 0.092) | 5252 | 35 | dynamic | - | METAL_SOLID_SMALL |
| `nz_amb_lightbox` | 0.680 x 0.635 x 1.895 | (-0.34, -0.3, 0.0) | (0.34, 0.35, 1.895) | 11276 | 80 | static | nz_amb_screen | METAL_HOLLOW_SMALL, PLASTIC_HIGH_DENSITY |
| `nz_amb_monitor` | 0.302 x 0.092 x 0.238 | (-0.15, -0.051, -0.001) | (0.152, 0.041, 0.238) | 11030 | 70 | dynamic | nz_amb_screen | PLASTIC_HIGH_DENSITY, RUBBER |
| `nz_amb_pager` | 0.099 x 0.033 x 0.062 | (-0.049, -0.019, -0.03) | (0.05, 0.013, 0.032) | 3312 | 40 | dynamic | nz_amb_screen | PLASTIC |
| `nz_amb_sharps` | 0.212 x 0.156 x 0.234 | (-0.106, -0.08, 0.0) | (0.106, 0.076, 0.245) | 2372 | 60 | dynamic | - | PLASTIC_HOLLOW |
| `nz_amb_splint_arm` | 0.400 x 0.124 x 0.120 | (-0.205, -0.065, -0.06) | (0.205, 0.06, 0.06) | 2528 | 50 | dynamic | - | PLASTIC |
| `nz_amb_splint_leg` | 0.758 x 0.165 x 0.240 | (-0.38, -0.083, -0.09) | (0.39, 0.083, 0.15) | 4000 | 60 | dynamic | - | PLASTIC |
| `nz_amb_stethoscope` | 0.247 x 0.182 x 0.020 | (-0.14, -0.07, -0.003) | (0.11, 0.12, 0.017) | 7552 | 35 | dynamic | - | RUBBER |
| `nz_amb_stretcher` | 0.663 x 2.046 x 0.952 | (-0.332, -1.03, 0.0) | (0.332, 1.03, 0.952) | 27314 | 150 | dynamic | - | LEATHER, METAL_HOLLOW_MEDIUM, METAL_HOLLOW_SMALL |
| `nz_amb_suction` | 0.487 x 0.366 x 0.267 | (-0.217, -0.08, -0.001) | (0.27, 0.286, 0.266) | 10120 | 50 | dynamic | - | PLASTIC_HIGH_DENSITY |
| `nz_amb_surgery_tray` | 0.866 x 0.532 x 0.951 | (-0.466, -0.264, 0.0) | (0.4, 0.268, 0.951) | 18430 | 60 | static | - | METAL_HOLLOW_SMALL, METAL_SOLID_SMALL |
| `nz_amb_syringe` | 0.034 x 0.132 x 0.018 | (-0.017, -0.04, -0.009) | (0.017, 0.123, 0.009) | 2556 | 30 | dynamic | - | PLASTIC |
| `nz_amb_tourniquet` | 0.104 x 0.125 x 0.149 | (-0.055, -0.065, -0.065) | (0.055, 0.065, 0.09) | 2388 | 40 | dynamic | - | CLOTH |
| `nz_amb_tv_board` | 1.600 x 0.034 x 0.920 | (-0.8, 0.0, -0.46) | (0.8, 0.034, 0.46) | 424 | 80 | static | nz_amb_screen | PLASTIC_HIGH_DENSITY |
| `nz_amb_us_cart` | 0.781 x 0.592 x 1.435 | (-0.39, -0.302, 0.0) | (0.39, 0.29, 1.435) | 28842 | 90 | static | nz_amb_screen | PLASTIC_HIGH_DENSITY |
| `nz_amb_us_probe` | 0.098 x 0.028 x 0.215 | (-0.034, -0.016, -0.063) | (0.071, 0.016, 0.152) | 4704 | 35 | dynamic | - | PLASTIC |
| `nz_amb_xray_table` | 1.310 x 2.340 x 2.480 | (-0.855, -1.17, 0.0) | (0.455, 1.17, 2.48) | 14308 | 120 | static | - | METAL_SOLID_MEDIUM, PLASTIC_HIGH_DENSITY |
<!-- props:table:end -->

## 9. Catalog - every model (generated from the prop definitions)

<!-- props:catalog:begin -->
### Cases & bags

#### `nz_amb_kitcase_closed` - Trauma kit hard case (closed)

| | |
|---|---|
| Config | `Config.Props.kitcase_closed` |
| Size X x Y x Z | 0.618 x 0.487 x 0.200 m (bbMin (-0.31, -0.232, 0.0), bbMax (0.31, 0.257, 0.205)) |
| Origin / pivot | bottom centre (on the ground) |
| Axes | +Y = front (latches + handle), +Z up, length along X |
| Attach / use | carry: PH_R_Hand (28422) pos (0.0, -0.245, -0.06) rot (0, 0, 0) -> handle in the hand, case hanging; SKEL_R_Hand (57005) pos (0.06, 0.0, -0.06) rot (90, 0, 90) as a starting point |
| LOD / type | lodDist 90 m, hdTextureDist 15 m, dynamic (physics, can be attached / carried) |
| Collision | 2 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_kitcase_closed`) | nz_amb_kitcase_closed_d 2048 |
| Mesh | 12288 tris, 10642 verts, shaders: normal_spec, .ydr 2562 KB |

#### `nz_amb_kitcase_open` - Trauma kit hard case (open, foam inserts with IO driver, syringes, blood tubes)

| | |
|---|---|
| Config | `Config.Props.kitcase_open` |
| Size X x Y x Z | 0.618 x 0.626 x 0.561 m (bbMin (-0.31, -0.364, 0.0), bbMax (0.31, 0.262, 0.561)) |
| Origin / pivot | bottom centre (on the ground) |
| Axes | +Y = front (latches), lid hinged at -Y and open ~100 deg (leans back), +Z up |
| Attach / use | placed on the ground next to the patient (static archetype); use nz_amb_kitcase_closed while carrying |
| LOD / type | lodDist 90 m, hdTextureDist 15 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 2 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_kitcase_open`) | nz_amb_kitcase_open_d 2048, nz_amb_kitcase_open_ad 256 |
| Mesh | 29526 tris, 26415 verts, shaders: normal_spec, normal_spec_alpha, .ydr 2659 KB |

#### `nz_amb_sharps` - Sharps bin (5 L), yellow with orange lid

| | |
|---|---|
| Config | `Config.Props.sharps` |
| Size X x Y x Z | 0.212 x 0.156 x 0.234 m (bbMin (-0.106, -0.08, 0.0), bbMax (0.106, 0.076, 0.245)) |
| Origin / pivot | bottom centre |
| Axes | +Y = front (biohazard label), aperture on top, +Z up |
| Attach / use | placed on the ground / ambulance shelf; carry: PH_R_Hand (28422) pos (0.0, 0.0, -0.27) by the lid handle |
| LOD / type | lodDist 60 m, hdTextureDist 10 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HOLLOW (embedded composite) |
| Textures (txd = `nz_amb_sharps`) | nz_amb_sharps_d 1024 |
| Mesh | 2372 tris, 1680 verts, shaders: normal_spec, .ydr 1003 KB |

### Electronic devices

#### `nz_amb_defib` - Monitor / defibrillator (orange + black handle)

| | |
|---|---|
| Config | `Config.Props.defib` |
| Size X x Y x Z | 0.382 x 0.146 x 0.268 m (bbMin (-0.195, -0.064, 0.0), bbMax (0.188, 0.082, 0.268)) |
| Origin / pivot | bottom centre |
| Axes | +Y = screen side (front), +Z up; handle on top, pads pouch on the +X side, printer on the -X side |
| Attach / use | carry: PH_R_Hand (28422) pos (0.0, -0.06, -0.26) rot (0, 0, 90); placed next to the patient on the ground |
| Screen | nz_amb_screen - quad 0.170 x 0.096 m (aspect 1.77), UV 0..1 = visible screen, top-left = (0,0) |
| LOD / type | lodDist 70 m, hdTextureDist 12 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HIGH_DENSITY, 1 box RUBBER (embedded composite) |
| Textures (txd = `nz_amb_defib`) | nz_amb_defib_d 2048, nz_amb_defib_g 64, nz_amb_screen 512x256 |
| Mesh | 12132 tris, 8930 verts, shaders: emissive, normal_spec, .ydr 2247 KB |

#### `nz_amb_monitor` - Portable patient monitor

| | |
|---|---|
| Config | `Config.Props.monitor` |
| Size X x Y x Z | 0.302 x 0.092 x 0.238 m (bbMin (-0.15, -0.051, -0.001), bbMax (0.152, 0.041, 0.238)) |
| Origin / pivot | bottom centre (sits on surfaces) |
| Axes | +Y = screen side (front), +Z up; control column beside the screen on +X (the viewer's left when facing the screen), connector panel on the +X side face |
| Attach / use | carry: PH_R_Hand (28422) pos (0.0, -0.03, -0.24) rot (0, 0, 90) holding the top handle; on stretcher/bed: place on the mattress or attach to the stretcher entity at its foot end |
| Screen | nz_amb_screen - quad 0.180 x 0.112 m (aspect 1.61), UV 0..1 = full visible screen, top-left = (0,0) |
| LOD / type | lodDist 70 m, hdTextureDist 12 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HIGH_DENSITY, 1 box RUBBER (embedded composite) |
| Textures (txd = `nz_amb_monitor`) | nz_amb_monitor_d 2048, nz_amb_monitor_g 64, nz_amb_screen 512x256 |
| Mesh | 11030 tris, 8922 verts, shaders: emissive, normal_spec, .ydr 1910 KB |

#### `nz_amb_pager` - EMS pager

| | |
|---|---|
| Config | `Config.Props.pager` |
| Size X x Y x Z | 0.099 x 0.033 x 0.062 m (bbMin (-0.049, -0.019, -0.03), bbMax (0.05, 0.013, 0.032)) |
| Origin / pivot | centre of the body (the grip) |
| Axes | +Y = LCD side (front), +Z up, belt clip on -Y |
| Attach / use | hand: PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (-90, 0, 0) -> adjust per animation; belt: SKEL_Pelvis (11816) pos (0.0, 0.14, 0.1) rot (0, 0, 180) |
| Screen | nz_amb_screen - LCD quad 0.056 x 0.022 m (aspect 2.55), UV 0..1 = LCD, top-left = (0,0) |
| LOD / type | lodDist 40 m, hdTextureDist 6 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC (embedded composite) |
| Textures (txd = `nz_amb_pager`) | nz_amb_pager_d 1024, nz_amb_pager_g 64, nz_amb_screen 256x128 |
| Mesh | 3312 tris, 2739 verts, shaders: emissive, normal_spec, .ydr 1108 KB |

### Fluids & IV

#### `nz_amb_bloodbag_0` - Blood bag, 0% full (red cells, O NEG label)

| | |
|---|---|
| Config | `Config.Props.bloodbag_0` |
| Size X x Y x Z | 0.134 x 0.021 x 0.343 m (bbMin (-0.068, -0.007, -0.35), bbMax (0.068, 0.015, 0.0)) |
| Origin / pivot | hanging slot at the top of the bag |
| Axes | bag hangs along -Z (blood settles at the bottom), label faces +Y |
| Attach / use | IV stand hook: stand entity pos (0.073, 0, 1.766) rot (0, 0, 0); lying flat label-up on nz_amb_blood_mixer: see the mixer's attach note (rot (90, 0, 0) lays it along +Y label-up, add a Z turn to run it along X); in the bay: IV hooks of nz_amb_bay_shell |
| Variants | swap between _0/_25/_50/_75/_100 as the bag fills (donation) or empties (transfusion) |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HOLLOW_CLEAR (embedded composite) |
| Textures (txd = `nz_amb_bloodbag_0`) | nz_amb_bloodbag_0_d 256, nz_amb_bloodbag_0_ad 1024 |
| Mesh | 3228 tris, 2540 verts, shaders: normal_spec, normal_spec_alpha, .ydr 544 KB |

#### `nz_amb_bloodbag_100` - Blood bag, 100% full (red cells, O NEG label)

| | |
|---|---|
| Config | `Config.Props.bloodbag_100` |
| Size X x Y x Z | 0.134 x 0.037 x 0.343 m (bbMin (-0.068, -0.021, -0.35), bbMax (0.068, 0.021, 0.0)) |
| Origin / pivot | hanging slot at the top of the bag |
| Axes | bag hangs along -Z (blood settles at the bottom), label faces +Y |
| Attach / use | IV stand hook: stand entity pos (0.073, 0, 1.766) rot (0, 0, 0); lying flat label-up on nz_amb_blood_mixer: see the mixer's attach note (rot (90, 0, 0) lays it along +Y label-up, add a Z turn to run it along X); in the bay: IV hooks of nz_amb_bay_shell |
| Variants | swap between _0/_25/_50/_75/_100 as the bag fills (donation) or empties (transfusion) |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HOLLOW_CLEAR (embedded composite) |
| Textures (txd = `nz_amb_bloodbag_100`) | nz_amb_bloodbag_100_d 256, nz_amb_bloodbag_100_ad 1024 |
| Mesh | 5136 tris, 3654 verts, shaders: normal_spec, normal_spec_alpha, .ydr 640 KB |

#### `nz_amb_bloodbag_25` - Blood bag, 25% full (red cells, O NEG label)

| | |
|---|---|
| Config | `Config.Props.bloodbag_25` |
| Size X x Y x Z | 0.134 x 0.022 x 0.343 m (bbMin (-0.068, -0.009, -0.35), bbMax (0.068, 0.015, 0.0)) |
| Origin / pivot | hanging slot at the top of the bag |
| Axes | bag hangs along -Z (blood settles at the bottom), label faces +Y |
| Attach / use | IV stand hook: stand entity pos (0.073, 0, 1.766) rot (0, 0, 0); lying flat label-up on nz_amb_blood_mixer: see the mixer's attach note (rot (90, 0, 0) lays it along +Y label-up, add a Z turn to run it along X); in the bay: IV hooks of nz_amb_bay_shell |
| Variants | swap between _0/_25/_50/_75/_100 as the bag fills (donation) or empties (transfusion) |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HOLLOW_CLEAR (embedded composite) |
| Textures (txd = `nz_amb_bloodbag_25`) | nz_amb_bloodbag_25_d 256, nz_amb_bloodbag_25_ad 1024 |
| Mesh | 4388 tris, 3258 verts, shaders: normal_spec, normal_spec_alpha, .ydr 600 KB |

#### `nz_amb_bloodbag_50` - Blood bag, 50% full (red cells, O NEG label)

| | |
|---|---|
| Config | `Config.Props.bloodbag_50` |
| Size X x Y x Z | 0.134 x 0.026 x 0.343 m (bbMin (-0.068, -0.013, -0.35), bbMax (0.068, 0.015, 0.0)) |
| Origin / pivot | hanging slot at the top of the bag |
| Axes | bag hangs along -Z (blood settles at the bottom), label faces +Y |
| Attach / use | IV stand hook: stand entity pos (0.073, 0, 1.766) rot (0, 0, 0); lying flat label-up on nz_amb_blood_mixer: see the mixer's attach note (rot (90, 0, 0) lays it along +Y label-up, add a Z turn to run it along X); in the bay: IV hooks of nz_amb_bay_shell |
| Variants | swap between _0/_25/_50/_75/_100 as the bag fills (donation) or empties (transfusion) |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HOLLOW_CLEAR (embedded composite) |
| Textures (txd = `nz_amb_bloodbag_50`) | nz_amb_bloodbag_50_d 256, nz_amb_bloodbag_50_ad 1024 |
| Mesh | 4592 tris, 3366 verts, shaders: normal_spec, normal_spec_alpha, .ydr 628 KB |

#### `nz_amb_bloodbag_75` - Blood bag, 75% full (red cells, O NEG label)

| | |
|---|---|
| Config | `Config.Props.bloodbag_75` |
| Size X x Y x Z | 0.134 x 0.030 x 0.343 m (bbMin (-0.068, -0.017, -0.35), bbMax (0.068, 0.017, 0.0)) |
| Origin / pivot | hanging slot at the top of the bag |
| Axes | bag hangs along -Z (blood settles at the bottom), label faces +Y |
| Attach / use | IV stand hook: stand entity pos (0.073, 0, 1.766) rot (0, 0, 0); lying flat label-up on nz_amb_blood_mixer: see the mixer's attach note (rot (90, 0, 0) lays it along +Y label-up, add a Z turn to run it along X); in the bay: IV hooks of nz_amb_bay_shell |
| Variants | swap between _0/_25/_50/_75/_100 as the bag fills (donation) or empties (transfusion) |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HOLLOW_CLEAR (embedded composite) |
| Textures (txd = `nz_amb_bloodbag_75`) | nz_amb_bloodbag_75_d 256, nz_amb_bloodbag_75_ad 1024 |
| Mesh | 4864 tris, 3510 verts, shaders: normal_spec, normal_spec_alpha, .ydr 637 KB |

#### `nz_amb_infuser` - Pressure infuser bag with gauge and hand bulb (holds a 500 mL bag)

| | |
|---|---|
| Config | `Config.Props.pressure_infuser` |
| Size X x Y x Z | 0.218 x 0.050 x 0.581 m (bbMin (-0.14, -0.03, -0.58), bbMax (0.085, 0.03, 0.002)) |
| Origin / pivot | top hook |
| Axes | hangs along -Z, clear window + gauge face +Y |
| Attach / use | IV stand hook: stand entity pos (0.073, 0, 1.766) rot (0, 0, 0) |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box CLOTH, 1 box RUBBER (embedded composite) |
| Textures (txd = `nz_amb_infuser`) | nz_amb_infuser_d 1024, nz_amb_infuser_ad 512 |
| Mesh | 8492 tris, 5545 verts, shaders: normal_spec, normal_spec_alpha, .ydr 1072 KB |

#### `nz_amb_ivbag_saline` - Saline 0.9% 500 mL bag with giving set

| | |
|---|---|
| Config | `Config.Props.ivbag_saline` |
| Size X x Y x Z | 0.127 x 0.035 x 0.627 m (bbMin (-0.064, -0.018, -0.627), bbMax (0.064, 0.019, 0.0)) |
| Origin / pivot | hanging slot at the top of the bag |
| Axes | bag hangs along -Z, printed front faces +Y |
| Attach / use | IV stand hook: stand entity pos (0.073, 0, 1.766) rot (0, 0, 0); hand: PH_R_Hand (28422) pos (0.0, 0.0, 0.1) rot (0, 0, 0) |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HOLLOW_CLEAR (embedded composite) |
| Textures (txd = `nz_amb_ivbag_saline`) | nz_amb_ivbag_saline_d 256, nz_amb_ivbag_saline_ad 1024 |
| Mesh | 5026 tris, 3530 verts, shaders: normal_spec, normal_spec_alpha, .ydr 739 KB |

#### `nz_amb_ivstand` - Tripod IV stand, 1.8 m, two hooks

| | |
|---|---|
| Config | `Config.Props.ivstand` |
| Size X x Y x Z | 0.582 x 0.508 x 1.801 m (bbMin (-0.3, -0.3, 0.0), bbMax (0.3, 0.333, 1.801)) |
| Origin / pivot | ground centre (pole axis) |
| Axes | pole along +Z, hooks on +X and -X, one leg points +Y |
| Attach / use | bags: attach the bag (origin = its hanging slot) to the stand entity at (0.073, 0, 1.766) or (-0.073, 0, 1.766) rot (0, 0, 0); the stand itself can be attached to the stretcher entity at its head end |
| LOD / type | lodDist 140 m, hdTextureDist 20 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 2 cylinder METAL_HOLLOW_SMALL (embedded composite) |
| Textures (txd = `nz_amb_ivstand`) | nz_amb_ivstand_d 512 |
| Mesh | 3888 tris, 3113 verts, shaders: normal_spec, .ydr 349 KB |

### Hand-held tools

#### `nz_amb_iodrill` - Intraosseous (IO) driver

| | |
|---|---|
| Config | `Config.Props.iodrill` |
| Size X x Y x Z | 0.046 x 0.191 x 0.141 m (bbMin (-0.024, -0.084, -0.07), bbMax (0.024, 0.108, 0.072)) |
| Origin / pivot | centre of the pistol grip (where the palm wraps) |
| Axes | +Y = needle direction, +Z = up over the grip, body on top |
| Attach / use | PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (0, 0, -90) needle forward; SKEL_R_Hand (57005) pos (0.10, 0.02, -0.02) rot (-90, 0, 0) |
| LOD / type | lodDist 45 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_iodrill`) | nz_amb_iodrill_d 1024, nz_amb_iodrill_g 64 |
| Mesh | 5672 tris, 4776 verts, shaders: emissive, normal_spec, .ydr 1181 KB |

#### `nz_amb_laryngoscope` - Laryngoscope (Macintosh blade, open / light on)

| | |
|---|---|
| Config | `Config.Props.laryngoscope` |
| Size X x Y x Z | 0.029 x 0.146 x 0.165 m (bbMin (-0.015, -0.015, -0.072), bbMax (0.015, 0.132, 0.092)) |
| Origin / pivot | centre of the handle |
| Axes | handle along Z (top = +Z), blade points +Y and curves down |
| Attach / use | PH_L_Hand (60309) pos (0.0, 0.0, 0.0) rot (0, 0, 0); SKEL_L_Hand (18905) pos (0.08, 0.02, 0.0) rot (0, 90, 0) |
| LOD / type | lodDist 35 m, hdTextureDist 6 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box METAL_SOLID_SMALL, 1 cylinder METAL_SOLID_SMALL (embedded composite) |
| Textures (txd = `nz_amb_laryngoscope`) | nz_amb_laryngoscope_d 1024, nz_amb_laryngoscope_g 64 |
| Mesh | 5252 tris, 4034 verts, shaders: emissive, normal_spec, .ydr 940 KB |

#### `nz_amb_stethoscope` - Stethoscope, coiled

| | |
|---|---|
| Config | `Config.Props.stethoscope` |
| Size X x Y x Z | 0.247 x 0.182 x 0.020 m (bbMin (-0.14, -0.07, -0.003), bbMax (0.11, 0.12, 0.017)) |
| Origin / pivot | bottom centre (lying flat) |
| Axes | flat on the XY plane, chest piece at +X, ear pieces at -X |
| Attach / use | neck: SKEL_Neck_1 (39317) needs a draped variant - use this model on surfaces / in hand: PH_R_Hand (28422) pos (0.0, 0.0, 0.0) |
| LOD / type | lodDist 35 m, hdTextureDist 6 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box RUBBER (embedded composite) |
| Textures (txd = `nz_amb_stethoscope`) | nz_amb_stethoscope_d 1024 |
| Mesh | 7552 tris, 5239 verts, shaders: normal_spec, .ydr 1093 KB |

#### `nz_amb_syringe` - 10 mL syringe with needle

| | |
|---|---|
| Config | `Config.Props.syringe` |
| Size X x Y x Z | 0.034 x 0.132 x 0.018 m (bbMin (-0.017, -0.04, -0.009), bbMax (0.017, 0.123, 0.009)) |
| Origin / pivot | finger flange (barrel back end) |
| Axes | +Y = needle direction; flange wings along X |
| Attach / use | PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (0, 0, -90) or SKEL_R_Hand (57005) pos (0.09, 0.03, -0.01) rot (-80, 0, 0) |
| LOD / type | lodDist 30 m, hdTextureDist 5 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC (embedded composite) |
| Textures (txd = `nz_amb_syringe`) | nz_amb_syringe_d 512, nz_amb_syringe_ad 512 |
| Mesh | 2556 tris, 2677 verts, shaders: normal_spec, normal_spec_alpha, .ydr 428 KB |

#### `nz_amb_us_probe` - Ultrasound probe (convex) with cable stub

| | |
|---|---|
| Config | `Config.Props.us_probe` |
| Size X x Y x Z | 0.098 x 0.028 x 0.215 m (bbMin (-0.034, -0.016, -0.063), bbMax (0.071, 0.016, 0.152)) |
| Origin / pivot | centre of the grip |
| Axes | lens points -Z, cable exits +Z; orientation marker on +X |
| Attach / use | PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (180, 0, 0) lens down; SKEL_R_Hand (57005) pos (0.08, 0.03, -0.02) rot (90, 0, 0) |
| LOD / type | lodDist 35 m, hdTextureDist 6 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC (embedded composite) |
| Textures (txd = `nz_amb_us_probe`) | nz_amb_us_probe_d 1024 |
| Mesh | 4704 tris, 2960 verts, shaders: normal_spec, .ydr 679 KB |

### Orthopaedic & worn

#### `nz_amb_binder_flat` - Pelvic binder laid flat (ready to slide under the patient)

| | |
|---|---|
| Config | `Config.Props.binder_flat` |
| Size X x Y x Z | 1.020 x 0.230 x 0.018 m (bbMin (-0.56, -0.12, -0.0), bbMax (0.46, 0.12, 0.02)) |
| Origin / pivot | ground, centre of the belt |
| Axes | belt length along X (buckle at +X), width along Y, printed face up (+Z) |
| Attach / use | placed on the ground beside / under the patient; swap to nz_amb_binder_worn once applied |
| LOD / type | lodDist 60 m, hdTextureDist 10 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box CLOTH (embedded composite) |
| Textures (txd = `nz_amb_binder_flat`) | nz_amb_binder_flat_d 512 |
| Mesh | 1104 tris, 1030 verts, shaders: normal_spec, .ydr 288 KB |

#### `nz_amb_binder_worn` - Pelvic binder applied (closed loop)

| | |
|---|---|
| Config | `Config.Props.binder_worn` |
| Size X x Y x Z | 0.359 x 0.274 x 0.200 m (bbMin (-0.18, -0.13, -0.11), bbMax (0.18, 0.144, 0.11)) |
| Origin / pivot | centre of the loop (pelvis centre) |
| Axes | loop around Z (band height along Z), buckle at the front (+Y), 0.36 wide (X) x 0.26 deep (Y) x 0.22 tall |
| Attach / use | SKEL_Pelvis (11816) pos (0.0, 0.0, 0.0) rot (0, 0, 0) as a starting point - the pelvis bone's axes are not world aligned, typical fix rot (0, 90, 0) or (90, 0, 90); disable collision on the attached object |
| LOD / type | lodDist 60 m, hdTextureDist 10 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box CLOTH (embedded composite) |
| Textures (txd = `nz_amb_binder_worn`) | nz_amb_binder_worn_d 512 |
| Mesh | 1560 tris, 1536 verts, shaders: normal_spec, .ydr 280 KB |

#### `nz_amb_collar` - Rigid cervical collar (applied loop)

| | |
|---|---|
| Config | `Config.Props.collar` |
| Size X x Y x Z | 0.137 x 0.170 x 0.126 m (bbMin (-0.075, -0.08, -0.04), bbMax (0.075, 0.093, 0.088)) |
| Origin / pivot | neck axis at the collar's mid height |
| Axes | loop around Z, chin support and trachea opening at the front (+Y) |
| Attach / use | SKEL_Neck_1 (39317) pos (0.0, 0.0, 0.0) rot (0, 0, 0) as a start - the neck bone's X runs up the neck, so the usual fix is rot (0, 90, 0) or (0, -90, 180); disable collision on the attached object |
| LOD / type | lodDist 40 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC (embedded composite) |
| Textures (txd = `nz_amb_collar`) | nz_amb_collar_d 1024 |
| Mesh | 1928 tris, 1860 verts, shaders: normal_spec, .ydr 744 KB |

#### `nz_amb_crutch` - Forearm crutch, 1.2 m

| | |
|---|---|
| Config | `Config.Props.crutch` |
| Size X x Y x Z | 0.100 x 0.190 x 1.206 m (bbMin (-0.055, -0.128, -0.86), bbMax (0.055, 0.08, 0.346)) |
| Origin / pivot | centre of the hand grip |
| Axes | lower tube along -Z (ferrule at z = -0.86), grip points +Y (forward), cuff on top at the back |
| Attach / use | PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (0, 0, 0) or SKEL_R_Hand (57005) pos (0.08, 0.02, 0.0) rot (90, 0, 90); second crutch in the left hand: PH_L_Hand (60309) |
| LOD / type | lodDist 70 m, hdTextureDist 10 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC, 1 box RUBBER, 1 cylinder METAL_HOLLOW_SMALL (embedded composite) |
| Textures (txd = `nz_amb_crutch`) | nz_amb_crutch_d 1024 |
| Mesh | 4076 tris, 2939 verts, shaders: normal_spec, .ydr 1062 KB |

#### `nz_amb_splint_arm` - Posterior arm splint (U channel, 0.40 m, palm roll)

| | |
|---|---|
| Config | `Config.Props.splint_arm` |
| Size X x Y x Z | 0.400 x 0.124 x 0.120 m (bbMin (-0.205, -0.065, -0.06), bbMax (0.205, 0.06, 0.06)) |
| Origin / pivot | on the limb axis at mid length |
| Axes | length along X (palm roll at +X), open side +Z |
| Attach / use | SKEL_L_Forearm (61163) / SKEL_R_Forearm (28252) pos (0.12, 0.0, 0.0) rot (0, 0, 0); rotate around X so the open side faces the forearm |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC (embedded composite) |
| Textures (txd = `nz_amb_splint_arm`) | nz_amb_splint_arm_d 1024 |
| Mesh | 2528 tris, 2226 verts, shaders: normal_spec, .ydr 872 KB |

#### `nz_amb_splint_leg` - Posterior leg splint (U channel, 0.75 m, foot plate)

| | |
|---|---|
| Config | `Config.Props.splint_leg` |
| Size X x Y x Z | 0.758 x 0.165 x 0.240 m (bbMin (-0.38, -0.083, -0.09), bbMax (0.39, 0.083, 0.15)) |
| Origin / pivot | on the limb axis at mid length (the channel wraps around it) |
| Axes | length along X, foot plate at +X pointing +Z, open side of the channel +Z (anterior) |
| Attach / use | SKEL_L_Calf (63931) / SKEL_R_Calf (36864) pos (0.10, 0.0, 0.0) rot (0, 0, 0) - the calf bone's X runs knee -> foot; rotate around X until the open side faces the shin (try rot (90, 0, 0) / (-90, 0, 0)) |
| LOD / type | lodDist 60 m, hdTextureDist 10 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC (embedded composite) |
| Textures (txd = `nz_amb_splint_leg`) | nz_amb_splint_leg_d 1024 |
| Mesh | 4000 tris, 3448 verts, shaders: normal_spec, .ydr 1047 KB |

#### `nz_amb_tourniquet` - Windlass tourniquet, applied loop (inner diameter ~0.11 m)

| | |
|---|---|
| Config | `Config.Props.tourniquet_worn` |
| Size X x Y x Z | 0.104 x 0.125 x 0.149 m (bbMin (-0.055, -0.065, -0.065), bbMax (0.055, 0.065, 0.09)) |
| Origin / pivot | centre of the loop (limb axis) |
| Axes | limb / bone axis = X, windlass rod on top (+Z) lying along X, time strap on the rod |
| Attach / use | limb bones (X runs along the bone): SKEL_L_UpperArm 45509, SKEL_R_UpperArm 40269, SKEL_L_Forearm 61163, SKEL_R_Forearm 28252, SKEL_L_Thigh 58271, SKEL_R_Thigh 51826, SKEL_L_Calf 63931, SKEL_R_Calf 36864 - pos (0.12, 0, 0) along the bone, rot (0, 0, 0); scale by choosing the bone (thigh loops look tight on big peds) |
| LOD / type | lodDist 40 m, hdTextureDist 6 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box CLOTH (embedded composite) |
| Textures (txd = `nz_amb_tourniquet`) | nz_amb_tourniquet_d 1024 |
| Mesh | 2388 tris, 2058 verts, shaders: normal_spec, .ydr 881 KB |

### Transport

#### `nz_amb_stretcher` - Ambulance stretcher / powered cot

| | |
|---|---|
| Config | `Config.Props.stretcher` |
| Size X x Y x Z | 0.663 x 2.046 x 0.952 m (bbMin (-0.332, -1.03, 0.0), bbMax (0.332, 1.03, 0.952)) |
| Origin / pivot | on the ground under the centre of the cot |
| Axes | length along Y (head end +Y, foot-end handle and controls -Y), width along X, mattress top at z = 0.885 |
| Attach / use | patient: attach the ped to the stretcher entity pos (0.0, 0.05, 1.33) rot (0, 0, 180) with a lying anim (or use the mattress top z = 0.885 + ped root offset); push: attach the stretcher to the medic SKEL_Pelvis (11816) / PH_R_Hand with the foot-end handle (y = -1.02, z = 0.80) in the hands, e.g. stretcher pos (0.0, 1.45, -0.85) relative to the medic ped; into the ambulance: attach to the vehicle with an offset per model |
| LOD / type | lodDist 150 m, hdTextureDist 20 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box LEATHER, 2 box METAL_HOLLOW_MEDIUM, 2 box METAL_HOLLOW_SMALL (embedded composite) |
| Textures (txd = `nz_amb_stretcher`) | nz_amb_stretcher_d 2048, nz_amb_stretcher_g 64 |
| Mesh | 27314 tris, 21439 verts, shaders: emissive, normal_spec, .ydr 2811 KB |

### Airway

#### `nz_amb_bvm` - Bag-valve mask (adult): clear face mask, elbow, patient valve, squeeze bag, O2 inlet + tubing

| | |
|---|---|
| Config | `Config.Props.bvm` |
| Size X x Y x Z | 0.266 x 0.520 x 0.160 m (bbMin (-0.065, -0.065, -0.002), bbMax (0.202, 0.457, 0.161)) |
| Origin / pivot | centre of the mask rim (the face contact plane) |
| Axes | mask rim on the XY plane, face side -Z (the mask dome rises +Z), nose end of the mask +Y; the elbow turns the valve + bag towards +Y (over the patient's forehead / the medic at the head end) |
| Attach / use | face: SKEL_Head (31086) - the head bone's +X runs up through the crown and +Y out of the face, so the rim's -Z must face the bone's -Y and the mask's +Y the bone's +X: start from pos (0.06, 0.11, 0.0) rot (0, -90, -90) and tune per ped; hand: the medic's PH_L_Hand (60309) holds the mask (C-E grip) at pos (0.0, 0.0, 0.0) and the PH_R_Hand (28422) squeezes the bag at (0, 0.21, 0.095) in prop space |
| LOD / type | lodDist 35 m, hdTextureDist 6 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC, 1 box RUBBER_HOLLOW (embedded composite) |
| Textures (txd = `nz_amb_bvm`) | nz_amb_bvm_d 1024, nz_amb_bvm_ad 512 |
| Mesh | 8808 tris, 6648 verts, shaders: normal_spec, normal_spec_alpha, .ydr 1069 KB |

#### `nz_amb_ett` - Endotracheal tube 7.5 (cuffed, Magill curve) secured in a tube holder

| | |
|---|---|
| Config | `Config.Props.ett` |
| Size X x Y x Z | 0.159 x 0.273 x 0.171 m (bbMin (-0.08, -0.15, -0.147), bbMax (0.08, 0.123, 0.024)) |
| Origin / pivot | centre of the tube holder = the lip line |
| Axes | the tube leaves the mouth along +Y (15 mm connector at +Y), enters along -Y and curves towards -Z (down the airway); holder bar across the lips along X, straps run back along -Y around the cheeks |
| Attach / use | SKEL_Head (31086): rim of the lips is about (0.0, 0.12, -0.04) in bone space for the freemode heads; the prop's +Y must point out of the mouth (bone +Y) and its -Z towards the neck (bone -X): start from pos (-0.04, 0.12, 0.0) rot (0, 90, 0) and tune; the BVM / ventilator connects at the connector end (0, 0.075, 0) |
| LOD / type | lodDist 30 m, hdTextureDist 5 m, dynamic (physics, can be attached / carried) |
| Collision | 1 box PLASTIC (embedded composite) |
| Textures (txd = `nz_amb_ett`) | nz_amb_ett_d 512, nz_amb_ett_ad 512 |
| Mesh | 5364 tris, 4350 verts, shaders: normal_spec, normal_spec_alpha, .ydr 523 KB |

#### `nz_amb_suction` - Portable suction unit with 1 L canister, patient tubing and Yankauer tip

| | |
|---|---|
| Config | `Config.Props.suction` |
| Size X x Y x Z | 0.487 x 0.366 x 0.267 m (bbMin (-0.217, -0.08, -0.001), bbMax (0.27, 0.286, 0.266)) |
| Origin / pivot | bottom centre of the unit (stands on the ground) |
| Axes | +Y = front (gauge + controls), +Z up; canister on the +X side, the patient tube runs out to the Yankauer lying on the ground in front (+Y) |
| Attach / use | carry: PH_R_Hand (28422) by the top handle pos (0.03, 0.0, -0.26) rot (0, 0, 0); in-hand Yankauer: hide is not possible per part - spawn a second suction prop or a native tube when the medic picks the tip up; the tip lies at (-0.21, 0.27, 0.012) pointing -X |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 2 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_suction`) | nz_amb_suction_d 1024, nz_amb_suction_ad 512, nz_amb_suction_g 64 |
| Mesh | 10120 tris, 7925 verts, shaders: emissive, normal_spec, normal_spec_alpha, .ydr 1403 KB |

### Imaging & angiography suite

#### `nz_amb_angio_monitor` - Fluoroscopy monitor on a boom stand

| | |
|---|---|
| Config | `Config.Props.angio_monitor` |
| Size X x Y x Z | 1.000 x 1.068 x 2.135 m (bbMin (-0.5, -0.35, 0.0), bbMax (0.5, 0.718, 2.135)) |
| Origin / pivot | floor, on the boom column axis |
| Axes | boom reaches +Y over the table side; screen faces +Y; +Z up |
| Attach / use | viewing camera: from (0, 1.72, 1.55) looking -Y fills the screen with a 40 deg FOV; place it beside the head end of the angio table so the boom hangs over the patient's legs |
| Screen | nz_amb_screen - quad 0.94 x 0.53 m (aspect 1.77) centred at (0, 0.6585, 1.55), UV 0..1 = visible screen, top-left = (0,0); default = live fluoroscopy frame |
| LOD / type | lodDist 100 m, hdTextureDist 15 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 1 box METAL_HOLLOW_MEDIUM, 1 box METAL_SOLID_MEDIUM, 1 box PLASTIC_HIGH_DENSITY, 1 cylinder METAL_HOLLOW_MEDIUM (embedded composite) |
| Textures (txd = `nz_amb_angio_monitor`) | nz_amb_angio_monitor_d 2048, nz_amb_angio_monitor_g 64, nz_amb_screen 1024x512 |
| Mesh | 12076 tris, 9711 verts, shaders: emissive, normal_spec, .ydr 2194 KB |

#### `nz_amb_contrast_button` - Contrast-run pedestal: big red mushroom button on a teal housing

| | |
|---|---|
| Config | `Config.Props.contrast_button` |
| Size X x Y x Z | 0.336 x 0.336 x 1.014 m (bbMin (-0.168, -0.168, -0.002), bbMax (0.168, 0.168, 1.012)) |
| Origin / pivot | floor, on the pedestal axis |
| Axes | +Y = front (labels), +Z up; key switch and ARMED LED on the top plate behind the button |
| Attach / use | button top centre at (0, 0.0, 1.012) - press anim target; hand IK point (0, 0.02, 1.032); ped stands at (0, 0.45, 0) facing -Y |
| LOD / type | lodDist 60 m, hdTextureDist 10 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 1 box PLASTIC_HIGH_DENSITY, 1 cylinder METAL_HOLLOW_SMALL, 1 cylinder METAL_SOLID_MEDIUM (embedded composite) |
| Textures (txd = `nz_amb_contrast_button`) | nz_amb_contrast_button_d 1024, nz_amb_contrast_button_g 64 |
| Mesh | 10116 tris, 7749 verts, shaders: emissive, normal_spec, .ydr 1244 KB |

#### `nz_amb_injector` - Contrast power injector on a mobile pole tray

| | |
|---|---|
| Config | `Config.Props.injector` |
| Size X x Y x Z | 0.926 x 0.739 x 1.160 m (bbMin (-0.476, -0.433, 0.0), bbMax (0.45, 0.306, 1.16)) |
| Origin / pivot | floor, under the centre of the tray |
| Axes | tray 0.90 (X) x 0.50 (Y); syringe along X with its tip at -X, motor head at +X; delivery line drapes over the front edge (+Y); +Z up |
| Attach / use | syringe tip at (-0.235, 0.05, 1.040); the syringe plunger + ram is the separate model nz_amb_injector_plunger - ALWAYS spawn it with the injector, attached at (0.03, 0.05, 1.04) rot (0, 0, 0) and slide it 0 .. 0.2 m along -X while dye goes in (the contrast column stays drawn); delivery line ends at (-0.47, 0.30, 0.66) - attach a line prop / rope from there to the patient's IV port; camera over the tray: (0.0, 0.55, 1.45) looking at (0, 0, 1.0) |
| LOD / type | lodDist 70 m, hdTextureDist 12 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 1 box METAL_HOLLOW_SMALL, 3 box PLASTIC_HIGH_DENSITY, 1 cylinder METAL_HOLLOW_SMALL (embedded composite) |
| Textures (txd = `nz_amb_injector`) | nz_amb_injector_d 2048, nz_amb_injector_ad 512, nz_amb_injector_g 64 |
| Mesh | 16646 tris, 13097 verts, shaders: emissive, normal_spec, normal_spec_alpha, .ydr 2346 KB |

#### `nz_amb_injector_plunger` - Power-injector syringe plunger + ram (moving part of nz_amb_injector)

| | |
|---|---|
| Config | `Config.Props.injector_plunger` |
| Size X x Y x Z | 0.304 x 0.064 x 0.064 m (bbMin (-0.0, -0.032, -0.032), bbMax (0.304, 0.032, 0.032)) |
| Origin / pivot | the plunger face (front of the rubber stopper) on the syringe axis |
| Axes | ram runs along +X back into the injector head; the plunger pushes towards -X |
| Attach / use | attach to the nz_amb_injector entity at (0.03, 0.05, 1.04) rot (0, 0, 0) (collision off); full syringe = offset 0, empty = 0.2 m along -X (x = -0.17) |
| LOD / type | lodDist 30 m, hdTextureDist 5 m, dynamic (physics, can be attached / carried) |
| Collision | 1 cylinder PLASTIC (embedded composite) |
| Textures (txd = `nz_amb_injector_plunger`) | nz_amb_injector_plunger_d 256 |
| Mesh | 1144 tris, 1129 verts, shaders: normal_spec, .ydr 85 KB |

#### `nz_amb_lightbox` - X-ray film viewer (lightbox) on a rolling stand

| | |
|---|---|
| Config | `Config.Props.lightbox` |
| Size X x Y x Z | 0.680 x 0.635 x 1.895 m (bbMin (-0.34, -0.3, 0.0), bbMax (0.34, 0.35, 1.895)) |
| Origin / pivot | floor, on the stand's pole axis |
| Axes | +Y = light panel side (front), +Z up |
| Attach / use | film clipped on the panel: a flat film plane at y = 0.1505 in front of the panel; the reading camera looks at (0, 0.1465, 1.47) from (0, 1.05, 1.47) |
| Screen | nz_amb_screen - emissive light panel 0.6 x 0.75 m centred at (0, 0.1465, 1.47), UV 0..1 = whole panel, top-left = (0,0); default = white diffuser. Replace it with a DUI to show the film being read |
| LOD / type | lodDist 80 m, hdTextureDist 12 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 1 box METAL_HOLLOW_SMALL, 1 box PLASTIC_HIGH_DENSITY, 1 cylinder METAL_HOLLOW_SMALL (embedded composite) |
| Textures (txd = `nz_amb_lightbox`) | nz_amb_lightbox_d 1024, nz_amb_lightbox_g 64, nz_amb_screen 512x512 |
| Mesh | 11276 tris, 9444 verts, shaders: emissive, normal_spec, .ydr 1259 KB |

#### `nz_amb_xray_table` - Radiography table + floor-rail X-ray tube stand

| | |
|---|---|
| Config | `Config.Props.xray_table` |
| Size X x Y x Z | 1.310 x 2.340 x 2.480 m (bbMin (-0.855, -1.17, 0.0), bbMax (0.455, 1.17, 2.48)) |
| Origin / pivot | floor, under the centre of the table top |
| Axes | table length along Y (patient head end +Y), operator side +X; tube stand column at -X on a floor rail, swivel arm reaching over the table |
| Attach / use | patient lies on the pad (surface z = 0.825) head towards +Y: attach the ped to the table entity at (0.0, 0.0, 0.825) + the lying clip's root height, rot (0, 0, 180) for a clip whose ped faces up with feet along its +Y; tube focal spot at (0.0, 0.35, 1.66), collimator light field bottom at z 1.42 (point a camera from there straight down for a 'film' view); medic stands at (+0.75, 0.0) facing -X |
| LOD / type | lodDist 120 m, hdTextureDist 18 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 2 box METAL_SOLID_MEDIUM, 5 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_xray_table`) | nz_amb_xray_table_d 2048, nz_amb_xray_table_g 64 |
| Mesh | 14308 tris, 10957 verts, shaders: emissive, normal_spec, .ydr 2141 KB |

### Hospital equipment

#### `nz_amb_blood_mixer` - Blood collection mixer / scale with a rocking tray

| | |
|---|---|
| Config | `Config.Props.blood_mixer` |
| Size X x Y x Z | 0.348 x 0.236 x 0.339 m (bbMin (-0.173, -0.115, 0.0), bbMax (0.175, 0.121, 0.339)) |
| Origin / pivot | bottom centre (stands on the floor or a table) |
| Axes | +Y = front (display + buttons), +Z up; the rocking tray on top tilts 6 deg towards the front, tube clamp on +X |
| Attach / use | blood bag (nz_amb_bloodbag_*; origin = its hanging slot) lying on the tray: pos (-0.15, 0.0, 0.326) with the bag extending +X and its label up (rot (90, 0, -90) for rotation order 2 - verify in game); the line runs through the clamp at (0.155, 0.04, 0.24) |
| Screen | nz_amb_screen - LCD quad 0.110 x 0.055 m (aspect 2.0) on the front panel, UV 0..1 = LCD, top-left = (0,0); default = '312 mL / 450' collection screen |
| LOD / type | lodDist 50 m, hdTextureDist 8 m, dynamic (physics, can be attached / carried) |
| Collision | 2 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_blood_mixer`) | nz_amb_blood_mixer_d 1024, nz_amb_blood_mixer_g 64, nz_amb_screen 256x128 |
| Mesh | 4198 tris, 3348 verts, shaders: emissive, normal_spec, .ydr 1049 KB |

#### `nz_amb_donation_chair` - Reclining blood donation chair with padded armrests

| | |
|---|---|
| Config | `Config.Props.donation_chair` |
| Size X x Y x Z | 0.907 x 1.601 x 1.299 m (bbMin (-0.449, -0.826, 0.0), bbMax (0.458, 0.775, 1.299)) |
| Origin / pivot | floor, under the centre of the seat |
| Axes | the occupant faces +Y (leg rest towards +Y, backrest towards -Y reclined 32 deg), +Z up; the donor arm rests on the +X armrest (the seated ped's right arm) |
| Attach / use | seat top z = 0.53; attach / place the donor at (0.0, -0.08, 0.53) + the sit clip's root height, rot (0, 0, 0) (ped faces +Y) - a reclined sit clip (e.g. the dentist / beach chair clips) matches the back; venepuncture site (right antecubital) rests at about (0.36, 0.06, 0.70); place nz_amb_blood_mixer on the floor at (0.62, 0.15, 0) and the IV stand at (-0.55, 0.0, 0) |
| LOD / type | lodDist 90 m, hdTextureDist 14 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 8 box LEATHER, 2 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_donation_chair`) | nz_amb_donation_chair_d 2048 |
| Mesh | 12338 tris, 8604 verts, shaders: normal_spec, .ydr 2772 KB |

#### `nz_amb_surgery_tray` - Instrument tray table (stainless, two shelves) with a draped instrument set

| | |
|---|---|
| Config | `Config.Props.surgery_tray` |
| Size X x Y x Z | 0.866 x 0.532 x 0.951 m (bbMin (-0.466, -0.264, 0.0), bbMax (0.4, 0.268, 0.951)) |
| Origin / pivot | floor, under the centre of the top |
| Axes | top 0.80 (X) x 0.50 (Y); push handle at -X, drape overhangs the front (+Y); +Z up |
| Attach / use | drape surface z = 0.909; instruments lie in a row along X from (-0.30, -0.12) to (0.05, -0.12) with the tips towards +Y (scalpel first at x = -0.30); kidney dish (0.24, 0.10), saline bowl (0.24, -0.12), gauze (0.03, 0.12), syringe (-0.18, 0.12); place it beside the bed / X-ray table head end |
| LOD / type | lodDist 60 m, hdTextureDist 10 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 1 box METAL_HOLLOW_SMALL, 2 box METAL_SOLID_SMALL, 4 cylinder METAL_HOLLOW_SMALL (embedded composite) |
| Textures (txd = `nz_amb_surgery_tray`) | nz_amb_surgery_tray_d 2048, nz_amb_surgery_tray_ad 256 |
| Mesh | 18430 tris, 16895 verts, shaders: normal_spec, normal_spec_alpha, .ydr 2502 KB |

#### `nz_amb_tv_board` - Waiting-room wall screen 1.6 x 0.9 m (thin bezel)

| | |
|---|---|
| Config | `Config.Props.tv_board` |
| Size X x Y x Z | 1.600 x 0.034 x 0.920 m (bbMin (-0.8, 0.0, -0.46), bbMax (0.8, 0.034, 0.46)) |
| Origin / pivot | centre of the BACK face - the prop sits flat on a wall when placed at the wall surface |
| Axes | screen faces +Y (into the room), +Z up, everything at y >= 0 (depth 0.033) |
| Attach / use | place against a wall: position = wall surface point at the desired screen-centre height (about 2.0 - 2.3 m), heading = the wall normal's heading (screen +Y points into the room) |
| Screen | nz_amb_screen - 1024 x 576 texture embedded in the drawable's own dictionary (txd 'nz_amb_tv_board'), quad 1.568 x 0.882 m (16:9) centred at (0, 0.0343, 0.008), UV 0..1 = visible screen, top-left = (0,0); default = waiting-room information board (now serving / queue / clock). Replace it with a DUI (AddReplaceTexture('nz_amb_tv_board', 'nz_amb_screen', duiTxd, duiTex)) |
| LOD / type | lodDist 80 m, hdTextureDist 15 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 1 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_tv_board`) | nz_amb_tv_board_d 512, nz_amb_tv_board_g 64, nz_amb_screen 1024x576 |
| Mesh | 424 tris, 348 verts, shaders: emissive, normal_spec, .ydr 303 KB |

#### `nz_amb_us_cart` - Point-of-care ultrasound cart (eFAST) with monitor, console and probe holders

| | |
|---|---|
| Config | `Config.Props.us_cart` |
| Size X x Y x Z | 0.781 x 0.592 x 1.435 m (bbMin (-0.39, -0.302, 0.0), bbMax (0.39, 0.29, 1.435)) |
| Origin / pivot | floor, centre of the base |
| Axes | +Y = operator side (console front, screen faces +Y), +Z up; probe holders on +X / -X |
| Attach / use | operator stands at (0, 0.75, 0) facing -Y; the in-hand probe is nz_amb_us_probe (hide/show the parked one is not needed - the holders keep 3 probes); screen camera: from (0, 0.55, 1.30) looking at (0.0, -0.114, 1.278) |
| Screen | nz_amb_screen - quad 0.4 x 0.25 m (aspect 1.6) centred at (0.0, -0.114, 1.278), UV 0..1 = visible screen, top-left = (0,0); default = eFAST B-mode frame |
| LOD / type | lodDist 90 m, hdTextureDist 14 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 5 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_us_cart`) | nz_amb_us_cart_d 2048, nz_amb_us_cart_g 64, nz_amb_screen 512x320 |
| Mesh | 28842 tris, 22954 verts, shaders: emissive, normal_spec, .ydr 2314 KB |

### Ambulance treatment bay

#### `nz_amb_bay_shell` - Ambulance treatment bay interior (walk-in patient compartment)

| | |
|---|---|
| Config | `Config.Props.bay_shell` |
| Size X x Y x Z | 2.420 x 4.420 x 2.210 m (bbMin (-1.21, -2.21, -0.1), bbMax (1.21, 2.21, 2.15)) |
| Origin / pivot | floor centre of the room |
| Axes | +Y = towards the cab bulkhead, -Y = the rear doors, patient side (stretcher, O2 panel) -X, bench + counter +X, +Z up; inside 2.30 W x 4.30 L x 2.05 H, walls / floor / ceiling face inwards (a thin outer skin closes it from outside) |
| Attach / use | stretcher: nz_amb_stretcher at (-0.42, 0.1, 0.0) heading +0 (head end towards the cab); IV hooks (bag origin = hanging slot) at (-0.18, 0.95, 1.86) and (-0.18, -0.3, 1.86); patient monitor shelf top at (-1.02, 0.3, 1.1) - place nz_amb_monitor there with rot (0, 0, -90) (screen faces +X); medic spawn (0.3, -1.62, 0.0) heading +0; exit marker (0.0, -1.9, 0.0); bench seats (0.93, -1.317 / -0.450 / 0.417, 0.5) heading +90; attendant seat (-0.42, 1.86, 0.48) heading +180; supply cabinet slots: see docs/modules/props.md section 5 |
| Screen | nz_amb_screen - bulkhead monitor quad 0.84 x 0.4 m centred at (-0.2, 2.1045, 1.68) facing -Y, UV 0..1 = visible screen, top-left = (0,0); default = dark standby screen with clock, cabin temperature and O2 supply (txd 'nz_amb_bay_shell') |
| LOD / type | lodDist 120 m, hdTextureDist 25 m, static (archetype flag 32 - never moves, cheapest) |
| Collision | 4 box FIBREGLASS, 4 box LEATHER, 1 box METAL_HOLLOW_MEDIUM, 2 box METAL_SOLID_MEDIUM, 1 box METAL_SOLID_SMALL, 4 box PLASTIC_HIGH_DENSITY (embedded composite) |
| Textures (txd = `nz_amb_bay_shell`) | nz_amb_bay_shell_d 2048, nz_amb_bay_shell_shell_d 2048, nz_amb_bay_shell_supl_d 1024, nz_amb_bay_shell_supr_d 1024, nz_amb_bay_shell_ad 256, nz_amb_bay_shell_g 128, nz_amb_screen 512x256 |
| Mesh | 78416 tris, 65851 verts, shaders: emissive, normal_spec, normal_spec_alpha, .ydr 7086 KB |

<!-- props:catalog:end -->

## 10. Rebuilding / adding props

See `tools/props/README.md`. Short version:

```bash
python3 tools/props/build.py --stream nayzeee-ambulance/stream --docs nayzeee-ambulance/docs/modules/props.md
python3 tools/props/build.py --only nz_amb_us_cart --stream nayzeee-ambulance/stream   # one prop
```

The build aborts before touching `stream/` if CodeWalker fails to convert or re-load any binary.

## 11. Known limits

* Attach offsets for worn props and the face props (BVM, ETT) depend on the ped model and the playing
  animation - the values here are starting points, tune them in game (the bone axes are documented).
* Single LOD per model (no low-poly LOD meshes / no `.ydd` LOD chain); distance culling via `lodDist`.
* Collision is an approximation built from boxes and cylinders (no mesh collision); fine for walking,
  placing and raycasts, not for precise physics.
* The bay shell needs script lights and local rain suppression (section 5); the emissive panels only
  glow. Its collision closes the rear doors - exits are scripted.
* The injector's contrast column is static: when the plunger slides in, the barrel behind it keeps a
  faint contrast tint.
* Screens with a non power-of-two default (`tv_board` 1024 x 576, `us_cart` 512 x 320) are DXT
  compressed with full mip chains; DUIs replace them at any resolution.
* Bags (IV, blood) are separate fill-state models (`bloodbag_0/25/50/75/100`), not morph targets.
