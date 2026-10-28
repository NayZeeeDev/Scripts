# Props pipeline (`tools/props`) - NAYZEEE Radio

Every model in `nayzeee-radio-props/stream/` (`nzr_*.ydr` + the single `nzr_props.ytyp`) is built from
code in this folder - no Blender, no OpenIV, no binary sources. A prop is a Python function that builds
geometry from primitives, assigns materials and paints labels; the pipeline unwraps it, bakes the
textures, writes CodeWalker XML and (on a machine with .NET 8) converts it to the real GTA V formats.

The three radios are written once each with the **radio kit** (`props/radio_kit.py`): one design function
produces the complete radio, the body without its pressable parts, one model per key / knob / button and
every anchor the client needs (`shared/props_layout.lua`, generated).

**Labelling policy (Rule B - binding):** props and screen textures carry **no NAYZEEE name or mark** and no
real maker's name or logo. Labels name the device type and our model codes only (`PX-740`, `FX-280`,
`MX-905`, `JX-10`, `JX-40`, `JX-90`, function words `PATROL` / `FIELD` / `TACTICAL` / `MOBILE`), plus
believable fine print: rating plates (MODEL / SN / fictitious ID / Li-ion rating), battery labels, caution
stickers, generic symbols. Never print an identifier that could read as ours (no `NZR` in an ID either).

```
props/*.py ──► geometry (charts) ──► atlas packing ──► texel bake (colour, height→normal, spec, AO,
  (@prop,       + part ids, LOD flags                   edge wear, decals per part) ──► DDS (DXT1/5)
   @radio)  ──► CodeWalker XML (.ydr.xml: high + medium LOD, embedded textures, composite collision)
            ──► manifests (bounds, archetype, anchors, memory estimate) ──► nzr_props.ytyp.xml, tables,
                tools/props/xml/ (committed), shared/props_layout.lua (luac-checked)
            ──► .glb previews ──► headless three.js renders (+ assembled body+parts, alignment diffs)
                ──► contact sheets / radio review sheets ──► icons.py ──► html/img/items/*.png
            ──► [.NET 8 only] cwtool: XML → .ydr + nzr_props.ytyp, reload + validate, exact memory check
                ──► nayzeee-radio-props/stream/
```

## Requirements

| Tool | Used for |
|---|---|
| python3 ≥ 3.10 with `numpy`, `Pillow`, `fonttools` | geometry, baking, DDS, XML, layout, icons |
| node ≥ 18 + chromium (`/opt/pw-browsers/chromium`, `--chromium` or `NZR_CHROMIUM`) | review renders + icons (`--no-preview` skips them); `three` + `playwright-core` are npm-installed into the work folder once |
| `luac5.4` (optional) | checks the generated `shared/props_layout.lua` |
| .NET 8 SDK + git (**optional**) | conversion only: clones CodeWalker and builds `cwtool` in the work folder |

Nothing is downloaded into the repository: CodeWalker, the cwtool build, node modules and all build output
live in the work folder (`--work`, default `/tmp/nzr-work/props`, outputs in `/tmp/nzr-work/props/out`).

## Everyday commands (run from `nayzeee-radio/`)

```bash
# one radio while you work on it (no AO, no .NET): ~25 s build + ~60 s renders per radio
python3 tools/props/build.py --only 'nzr_handheld*' --no-convert --quick
# the same at full quality (also refreshes tools/props/xml + the layout): ~45 s + renders
python3 tools/props/build.py --only 'nzr_handheld*' --no-convert
# everything, full quality, no binaries (what a machine without .NET does): 5-10 min
python3 tools/props/build.py --no-convert
# pipeline self-test (builds the example radio, checks parts / anchors / layout / budget / renders): ~25 s
python3 tools/props/selftest.py
# item icons for html/img/items (after the models are built): ~5 s per icon
python3 tools/props/icons.py
# binaries (needs .NET 8) - see "Conversion"
tools/props/convert.sh
```

Measured on the 4-core build box: example radio (5 models, 512 atlas) 4 s build + 13 s renders; a 1024
radio's complete model 12 s, body 11 s, each 256 part 0.3 s (full quality; `--quick` saves ~25 %).

| Flag | Effect |
|---|---|
| `--only 'nzr_handheld*,nzr_led_*'` | rebuild only these (globs); everything else keeps its outputs and still goes into the ytyp / layout |
| `--quick` | skip ambient occlusion (iteration); quick builds never refresh `tools/props/xml` |
| `--no-convert` | never convert (also the default when neither `--stream` nor `--convert` is given) |
| `--stream DIR` / `--convert` | convert with cwtool (.NET 8) and install into DIR / the default `../nayzeee-radio-props/stream` |
| `--convert-only` | convert the committed `tools/props/xml` without rebuilding (what `convert.sh` runs) |
| `--no-preview`, `--size 640`, `--views front,back,top` | renders off / render size / default views of props that declare none |
| `--examples` | also load `props/_*.py` (the example radio, the building-blocks demo) |
| `--no-xml` / `--xml DIR` | do not refresh / use another committed XML folder |
| `--layout PATH` / `--layout none`, `--layout-radios handheld,fieldpro,military` | where / whether to write `props_layout.lua`, which radios |
| `--docs FILE.md` / `--docs-only` | refresh `<!-- props:table:* -->` / `<!-- props:catalog:* -->` sections; only rewrite tables + layout |
| `--list` | registered props (and modules that failed to import) |
| `--jobs 4`, `--out`, `--work`, `--chromium`, `--codewalker` | parallel builds, folders, tools |

### Outputs

| Where | What |
|---|---|
| `<out>/<name>/source/<name>.ydr.xml` + `<name>/*.dds` | CodeWalker XML + textures of every prop |
| `<out>/<name>/<name>.glb` (`_med.glb`) | preview of the high (and medium) model |
| `<out>/<name>/preview/*.png` | baked maps (diffuse, normal, spec, AO, screen) |
| `<out>/<name>/manifest.json` | bounds, tris, LOD, textures, memory estimate, collisions, anchors, warnings |
| `<out>/renders/<name>_<view>.png` | review renders (**LOOK at them after every change**) |
| `<out>/renders/nzr_<m>_assembled_*.png`, `*_diff.png`, `*_alignment.json` | body + parts at their anchors vs the complete radio |
| `<out>/sheets/contact_NN.png`, `<m>_overview.png`, `<m>_parts.png`, `<m>_align.png` | contact sheets / per-radio review sheets |
| `<out>/props_manifest.json`, `props_table.md`, `props_catalog.md`, `nzr_props.ytyp.xml` | aggregates of everything built so far |
| `tools/props/xml/` (**committed**) | XML + DDS + manifest of every exported prop's last full-quality build - the user converts these |
| `shared/props_layout.lua` (**committed, generated**) | SPEC §9.2 layout from the manifests (placeholders for radios not built yet) |

### Several builds at the same time

Model engineers build their own props in parallel against the same out folder; the pipeline is built for it:

* every file is written to a temp name and moved into place (`os.replace`) - readers never see half a file;
  each prop's `manifest.json` is written last;
* `--only` never deletes anything that belongs to other props; stale outputs are pruned only by a full build
  with no failures;
* the aggregates (`props_manifest.json`, `nzr_props.ytyp.xml`, `tools/props/xml/nzr_props.ytyp.xml`,
  `props_layout.lua`) are rebuilt under a file lock from **every manifest that built cleanly so far** (this
  machine's out folder + the committed `tools/props/xml/*.json`, newest build wins);
* a props module that does not import (someone's half-written file) is skipped with a warning - unless your
  `--only` asks for its props (pattern contains the module name, or matches nothing), then you get its
  traceback and exit code 1;
* renders go to a private temp folder per invocation and are moved into `renders/` when done; the node
  modules / cwtool installs are locked.

## Conversion

`tools/props/convert.sh` documents both routes (also printed at the top of the script):

1. **A machine with the .NET 8 SDK + git**: `tools/props/convert.sh` converts the committed
   `tools/props/xml` (no rebuild); `tools/props/convert.sh --rebuild` is the full
   `python3 tools/props/build.py --stream ../nayzeee-radio-props/stream` (run from `nayzeee-radio/`). cwtool
   converts, reloads and validates every binary, the exact memory pages are checked (≤ 16 MiB virtual and
   physical, FiveM's streaming limit), and only then `stream/` is touched.
2. **Windows, CodeWalker GUI** (no .NET SDK): pick the **GTA V Legacy** folder when CodeWalker asks (not
   Enhanced - FiveM streams legacy resources) → Tools → RPF Explorer → Edit mode → Import XML → select every
   `tools/props/xml/nzr_*.ydr.xml` and `nzr_props.ytyp.xml` (each XML keeps its texture folder next to it) →
   select the resulting `.ydr` / `.ytyp` → right-click → Extract Raw… into `nayzeee-radio-props/stream/`
   (the full file list is in `nayzeee-radio-props/stream/README.md`).

Without .NET the build stops after XML / DDS / GLB / renders / layout (the default). The memory budget is then
**estimated** from the written textures and buffers with a port of CodeWalker's page packer
(`nzprops/budget.py`) and a drawable above 16 MiB fails the build already; the exact check runs after
conversion.

## Adding a prop

1. Write a module under `tools/props/props/` (every module there is imported automatically; names starting
   with `_` only with `--examples`). Model names are `nzr_<thing>`.
2. A plain prop (jammers, earpiece, LED inserts):

```python
from nzprops import DecalCanvas, box, cylinder, prop
from .common import rating_plate, screws
from .radio_common import ink, m_anodised_black, m_led_lens

@prop("nzr_jammer_pocket", atlas=1024, lod=150, hd=20, lod_high=20, med_drop=0.003, budget=12000, doc={
    "title": "JX-10 pocket jammer", "origin": "bottom centre", "axes": "+Y = front, +Z up",
    "attach": "placed on the ground (client/modules/jammers.lua)"})
def jammer_pocket(b):
    alu = m_anodised_black(b)
    b.add(box((0.12, 0.07, 0.028), alu, r=0.003, seg=3, center=(0, 0, 0.014)))
    b.hi_only(screws(b, [(-0.05, 0.035, 0.02), (0.05, 0.035, 0.02)], (0, 1, 0), d=0.003, kind="torx"))
    dc = DecalCanvas(0.03, 0.008, ppm=9000); dc.text(0.015, 0.004, "JX-10", 0.004, **ink("white"))
    b.decal(dc, center=(0, 0.0351, 0.014), normal=(0, 1, 0))
    b.anchor(jammer="pocket", interact=(0.0, 0.0, 0.05))       # -> PropsLayout.jammers.pocket
    b.col_box((-0.06, -0.035, 0.0), (0.06, 0.035, 0.028), "METAL_SOLID_SMALL")   # collision is mandatory
```

   `export=False` builds and renders a model that is never streamed (the earpiece icon model).
3. `python3 tools/props/build.py --only nzr_jammer_pocket --no-convert --quick`, look at
   `<out>/renders/nzr_jammer_pocket_*.png`, iterate, finish with a full-quality build.

### Conventions

* GTA axes: metres, **+X right of the prop = the viewer's left when facing its front, +Y = front, +Z up**.
  Radio origin = grip point (body cross-section centre at 40 % of the body height from its bottom); jammer
  origin = bottom centre.
* `doc` dict on every prop (`title`, `origin`, `axes`, `attach`, `screen`) - published in `props_catalog.md`.
* Collision: `b.col_box(min, max, material)` / `b.col_cyl(center, r, length, axis, material)`; materials in
  `nzprops/cwxml.py: COL_MATERIALS`. The radio kit adds housing box + antenna cylinder itself.
* LOD: charts are flagged `'hm'` (default), `'h'` (`b.hi_only(geo)` / `b.add(geo, lod="h")`: fine detail) or
  `'m'` (a cheap stand-in only in the medium model); `@prop(med_drop=0.003)` also drops every chart smaller
  than 3 mm from the medium model. A prop with any flagged chart gets a medium model used from `lod_high`
  metres to the archetype `lod` (lodDist); otherwise one model is used throughout (AMB behaviour). Radios:
  high 6 m → medium → lodDist 40; jammers: `lod_high=20`, `lod=150`.
* Budgets (PROPS_BRIEF): full radio ≤ 24k tris, body ≤ 20k, part ≤ 1.2k (the kit warns), jammers heavy
  ≤ 40k / case ≤ 30k / pocket ≤ 12k (`@prop(budget=...)` warns). Fine detail (grip, knurl, grooves,
  screws, legends) goes into the baked maps; triangles go to silhouettes and to what the camera sees up close.
* Textures: radios `atlas=1024` (complete + body), parts 256, jammers 1024-2048, screens = layout
  `screen.w x screen.h`. Normal + spec maps full size up to 1024, half above; `maps={...}` shrinks them;
  `layers={"face": 1024}` + `Mat(layer="face")` adds an atlas for print-heavy surfaces; `densify(b, k, tags=...)`
  gives a chart (e.g. `housing:side:+y`, the printed front) more texels of the same atlas.
* Detail checklist: bevels everywhere (`box(r=...)`, `extrude(bevel=...)`, `rr_lathe`), split lines
  (`split_groove_y/z`, `DecalCanvas.groove`), real seams (`battery_pack` gap), screws (`common.screw(s)`
  phillips / hex / torx), rubber vs plastic vs metal materials, legends as decals (never baked into a
  low-res diffuse), wells under every pressable part, normal-map micro texture. The baker adds AO, chipped
  edge wear, scratches, smudges, crevice grime and dust from the material parameters.

## The radio kit (`props/radio_kit.py`)

```python
from .radio_kit import radio
from .radio_common import *

@radio("handheld", title="PX-740 patrol handheld")   # parts default to SPEC §9.2's list for the key
def handheld(r):
    ...   # build the WHOLE radio: body geometry outside part blocks, each pressable part inside one
```

`radio(key, parts=None, skin=None, title='', code=None, screen_px=None, atlas=1024, alpha_atlas=256,
glow_atlas=64, part_atlas=256, lod=40.0, lod_high=6.0, body_lod=20.0, part_lod=20.0, hd=8.0, med_drop=0.0025,
export=True, doc=None, budgets=None, maps=None, layers=None, part_boost=2.5)` registers

| model | content |
|---|---|
| `nzr_<key>` | everything, idle screen image (`nzr_scr`), medium LOD, part charts at `part_boost` texel density |
| `nzr_<key>_body` | everything added outside part blocks (wells, bosses, the screen with a near-black placeholder `nzr_scr`) |
| `nzr_<key>_<pid>` | one per part id: its charts moved so the anchor is the origin, its own `part_atlas`, its decals, a 2 mm collision box |

Defaults per key: `skin` handheld → `px740` (512×384), fieldpro → `fx280` (512×256), military → `mx905`
(512×384). The part ids default to SPEC §9.2; the design must create geometry for every one of them (and no
others) or the build fails with the list.

**Parts.** Everything added inside `with r.part(pid, ...)` (geometry *and* decals) belongs to that part;
decals print only on their own part (body prints never land on a key cap, key legends never on the body).
Metadata (all in body space):

| field | meaning |
|---|---|
| `origin` | the part model's origin = layout `pos`: centre of the clickable face at rest (keys / buttons), point on the rotation axis at half height (knobs) |
| `press`, `depth` | unit vector into the body, travel in metres (0.2-5 mm; keys 1.2-1.6, knobs 0.8) |
| `u`, `v`, `shape` | half-extent vectors of the clickable face (`pos ± u ± v`), `'rect'` / `'round'` (ellipse) |
| `action`, `value` | firmware vocabulary (SPEC §6); inferred from the id when omitted: `k0..k9` → digit, `kstar` star, `khash` hash, `kok`/`kset` ok, `kback`/`kband` back, `kp1`/`kp2`, `kup`/`kdown`, `kmenu`, `kpower` power, `dpad`, `knob_ch` knob/channel, `knob_vol` knob/volume, `emerg`, `ptt`, `side1`, `side2`. Override for SPEC's arrows, e.g. military `kup` → `action="menu"` |
| `axis`, `detents` | knobs: rotation axis + steps per turn |
| `tilt` | d-pad rocker tilt in degrees |

The helpers `key`, `keypad`, `dpad`, `knob`, `knob_pair`, `ptt`, `round_button` create the part block and
all metadata for you. Raw form: `with r.part("kmenu", origin=..., press=(0, -1, 0), depth=0.0014,
u=(-0.004, 0, 0), v=(0, 0, 0.003), shape="rect", action="menu"): r.add(...); r.decal(...)`; metadata can
be added later with `r.part_meta(pid, ...)`.

**Screen.** `screen_window(...)` (or `r.screen(quad(center, right, up, w, h, "x", fixed_uv=True))`) - texture
`nzr_scr`, UV 0..1 over the visible area, v = 0 at the top; the kit records `screen.center / size / w / h`.

**Anchors.** `r.anchor(focus=(x, y, z), camDist=0.34, leds={"tx": p, "rx": p}, grip="notes")` - required
(the build fails without focus / camDist / leds). Extra keys are kept in the manifest.

**What the kit adds:** validation (part set, metadata ranges, origin inside its geometry, screen, anchors),
default collision (housing box + antenna cylinder over charts tagged `antenna*`), body AO with the parts
as occluders (and the parts with the body as occluder) so the raised view matches the complete model,
review cameras (`face front left right back top` + close-ups `keypad`, `topdeck`, `screen`, `ptt`), and the
assembled render `nzr_<key>_assembled` (body + every part glb placed at its `pos`) with per-view difference
images - misplaced parts light up; the `screen` view differs by design (idle image vs placeholder).

## Building blocks (`props/radio_common.py`)

All take the builder first (`b` / `r`); geometry helpers return a `Geo` to `r.add` / `r.hi_only`; part helpers
add themselves and return the origin. Surface helpers take `at` (point on the surface), `normal`, `up` and
align a part built around +Z (viewer sees local +X right, +Y up).

| Group | Functions |
|---|---|
| materials | `m_soft_black m_keypad_rubber(tone=black/grey) m_ranger_green m_bumper_rubber m_grip_rubber(pattern=knurl/diamond/dimple/ribs) m_gunmetal m_sma(finish=nickel/brass/black) m_spring_steel m_smoked_glass(alpha) m_led_lens(color) m_led_off(color) m_anodised_black m_olive_steel m_eggcrate_foam m_hardcase(color) m_coax m_sticker_vinyl(color) m_mesh m_contact_gold m_print_dark` |
| inks | `INK` (white orange teal red yellow grey green black), `ink("orange")` → kwargs for any DecalCanvas call, `PRINT` |
| housing | `housing(b, mat, w, d, h, z0, center, chamfer, fillet, rim, dome)` (faces split: tags `housing:side:+y` ...), `housing_frame`, `densify(b, k, tags, mats, part)`, `split_groove_z(r, mats, w, d, z)`, `split_groove_y(r, mats, w, h, zc, y, d)`, `overmould_panel(b, mat, at, normal, up, w, h, t)`, `battery_pack(b, mat, w, d, h, y_front, z0, gap)`, `latch_tab`, `boss(b, mat, at, d, h, shaft_d, shaft_h)` (knob boss + D-shaft), `guard_ring`, `wells(r, mat, center, normal, up, size, t, holes)`, `well_for(r, mat, at, normal, up, size, gap, margin, t)` → floor offset |
| parts | `key(r, pid, at, normal, up, size, t, mat, legend, sub, glyph, color, depth, action, value, shape)`, `keypad(r, layout, center, pitch, size, ...)` (plate with wells + keys), `key_cap`, `legend_canvas`, `dpad(r, pid, at, size, kind=diamond/round/square, arrows=print/ridge, tilt)`, `knob(r, pid, base, axis, front, d, h, style=ribbed/knurled/smooth, ribs, skirt, index=line/dot, value, detents)`, `knob_pair(r, outer_id, inner_id, base, ...)`, `ptt(r, pid, at, normal, up, length, width, ridges, emboss)`, `ptt_guard`, `round_button(r, pid, at, normal, up, d)` |
| antennas | `whip_antenna(b, base, length, d0, d1, collar_h, cap=round/ball)`, `rubber_duck(b, base, length, d, band=(from_tip, width, colour))`, `sma_nut(b, at, across, h, finish)`, `gooseneck(b, base, length, coil_r, wire_r)` - tagged `antenna*` |
| details | `speaker_bars`, `grille_holes` (real holes, ~40 tris each) / `perforation_decal`, `slots_decal`, `light_pipe(b, at, normal, up, d, color)` → (geo, insert point for `leds`), `led_dome(b, color, d)` (the `nzr_led_*` insert models), `belt_clip`, `lanyard_eye`, `charging_contacts`, `thumbscrew`, `round_connector`, `screen_window(r, center, normal, up, view, bezel, recess, ...)` |
| labels | `model_print(code, word, w, h, rule_color)`, `rating_label(w, h, model, serial, ident, rating)`, `battery_label(w, h, pack, chem, volts, cap, serial)`, `knob_scale(d, n, ...)`, `volume_dots`, `print_decal(r, canvas, center, normal, up)`; from `common`: `caution_label`, `rating_plate`, `cal_sticker`, `asset_tag`, `label_canvas`, `screw(s)` |

`DecalCanvas.text` falls back to DejaVu for characters Lexend / JetBrains Mono / VT323 lack (↩ ✓ ⇧ ▲▼◀▶ ⇥ ‹)
and draws ⏻ as a vector; `DecalCanvas.glyph(kind, cx, cy, s, **ink(...))` draws crisp vector glyphs:
`power up down left right chev_* check x back shift tab grid menu lock speaker mic bolt dot ring signal scan`.
`DecalCanvas.icon(kind, ...)`: `book factory date bin warn drop temp ip(label=) recycle liion rf dc double`.

Screens (`props/radio_screens.py`): `idle_screen(skin, px, code)` - static standby image per skin (model code +
dim `-- --.--` readout, no NAYZEEE mark), `placeholder_screen(px)` - the body's near-black panel, `SKINS`.
Generic helpers in `props/screens.py` (`lcd_base`, `pixel_grid`, `seg_text` seven-segment with ghost segments,
`vignette`, `glass_glare` ...).

References: `props/_example_radio.py` (smallest complete radio: 2 keys, a knob, a screen) and
`props/_blocks_demo.py` (most building blocks on one radio) - build them with `--examples` and look.

## Layout (`gen_layout.py`)

`shared/props_layout.lua` is regenerated at the end of every build (and by `python3 tools/props/gen_layout.py
--check`) exactly in SPEC §9.2 format: `-- GENERATED ...` header, lock guard, `PropsLayout = { handheld =
{ full, body, skin, screen = { tex = 'nzr_scr', txd = 'nzr_<m>_body', w, h, center = vec3, size = vec2 },
focus, camDist, leds = { tx, rx }, keys = { {id, model, pos, press, depth, u, v, shape, action, value
[, tilt | axis, detents]} ... } }, fieldpro, military, jammers = { pocket|case|heavy = { model, size,
interact } } }`. Keys come in the radio's declared part order; radios / jammers never built keep placeholder
values with `keys = {}`. Jammer size = model bounds, `interact` from `b.anchor(jammer=..., interact=...)`.

## Review renders

Every prop: the views of `preview["views"]` (or `--views`) + its `cams`. Built-in views: `front` (3/4),
`front34`, `face` (straight on), `left` (+X side), `right`, `side`, `back`, `back34`, `top`, `frontlow`,
`iso`. Extra cameras / lights for anything else (interiors, close-ups):

```python
@prop("nzr_jammer_case", ..., preview={"views": ["front", "back", "top"],
      "cams": [{"name": "panel", "pos": [0.0, 0.35, 0.45], "target": [0.0, 0.0, 0.12], "fov": 40}]})
# or at build time: b.preview_cam("panel", pos, target, fov) / b.closeup("panel", target, direction, extent)
```

Radios get theirs from the kit. Read the PNGs: `<out>/renders/`, `<out>/sheets/<m>_overview.png`,
`<m>_parts.png`, `<m>_align.png`.

## Icons (`icons.py`)

`python3 tools/props/icons.py` renders 512×512 transparent PNGs (3/4 front, framed tightly, soft contact
shadow) into `html/img/items/<item>.png` for every `Config.Items` entry whose model was built (`radio`,
`radio_fieldpro`, `radio_military`, `radio_earpiece`, `jammer_pocket`, `jammer_case`, `jammer_heavy`); it writes
a fallback `nzr_unknown.png` only when the folder has none (the NUI ships a styled one). `--only handheld,heavy` (Config.Items keys), `--map item=model` for extra ones.

## Library cheat sheet (`nzprops`)

| Module | What |
|---|---|
| `mesh` | `box` (rounded / chamfered), `lathe`, `rr_lathe` (rounded-rect lathe: key caps, rockers; `top_fn` dome, `close`), `cylinder`, `sphere`, `capsule`, `torus`, `sweep`, `tube`, `extrude` (bevels, `mid_rings` / `max_seg` for deforming), `well_plate` (plate with rounded openings falling into wells), `loft`, `plane`, `quad` (`fixed_uv` for screens), `pillow`, `slab_with_holes`, `pocket`; outlines `rrect`, `chamfer_poly`, `chamfer_fillet_rect`, `fillet_poly`, `circle`, `ellipse`; paths `catmull`, `bezier`, `polyline_fillet`, `helix`, `arc_points`, `resample`; `split_by_normal`. `Geo`: `translate rotate rotate_axis scale mirror transform deform taper flip set_density set_tag set_part set_lod` |
| `paint` | `Mat(color, spec, gloss, metal, grain, bump, edge, ao, alpha, layer, dirt, wear, wear_color, scratch, smudge, cavity)`; bumps `stipple orange_peel rubber brushed fabric webbing foam eggcrate pluck knurl ribs ribs_u leather phillips hexsocket torx diamond dimple perf twill cordura velcro crinkle`; `DecalCanvas` (metres: `rect circle line polygon text glyph icon groove groove_rect stitch stitch_rect screw rivet perforate slots barcode datamatrix`); `font()` |
| `prop` | `@prop(name, atlas, alpha_atlas, glow_atlas, layers, maps, lod, lod_high, hd, med_drop, static, export, budget, falloff, spec_mult, glow_mult, doc, preview)`; `Builder.mat / add(geo, lod) / hi_only / part(pid, ...) / anchor / screen / decal(..., part) / chart_decal / col_box / col_cyl / preview_cam / closeup / warn` |
| `budget` | memory estimate (port of CodeWalker's page packer) |
| `fsutil` | atomic writes, file locks |
| `bake`, `atlas`, `dds`, `cwxml`, `gltf` | texel baker (AO, edge wear, scratches, smudges, grime, dust, part-aware decals), chart packer, DXT writer, CodeWalker XML (high + medium LOD), glb preview |

Material layers: `main` → `normal_spec` (`<name>_d/_n/_s`), `alpha` → `normal_spec_alpha` (`<name>_ad/_an/_as`:
glass, clear lenses), `glow` → `emissive` (`<name>_g`: LEDs), custom (`layers={"face": 1024}`) → extra
`normal_spec` set, screens → `emissive` with a fixed-UV texture (`nzr_scr`) the client replaces with a DUI
(`AddReplaceTexture('nzr_<m>_body', 'nzr_scr', 'nzr_rt', ...)`).

## cwtool

`tools/props/cwtool` is a ~300 line C# CLI on top of CodeWalker.Core (legacy / gen8 resources, what FiveM
streams): `ydr`, `ytd`, `ytyp`, `inspect` (loads a binary back, prints models / geometries / textures /
bounds and validates it) and `batch`. `build.py` clones CodeWalker (`--codewalker` to use an existing
checkout) and builds cwtool into the work folder (`NZR_CWTOOL_OUT`) - only when converting.

```bash
dotnet /tmp/nzr-work/props/cwtool/bin/Release/net8.0/cwtool.dll inspect ../nayzeee-radio-props/stream/nzr_handheld.ydr
```

## Licences

Bundled fonts: Lexend, JetBrains Mono, VT323 (SIL OFL 1.1, see `fonts/OFL-*.txt`), DejaVu (free licence,
`fonts/LICENSE`). CodeWalker (MIT) is cloned at conversion time, never vendored. three.js (MIT) and
playwright-core (Apache-2.0) are npm-installed into the work folder for the renders.
