# Props pipeline (`tools/props`)

Every generated model in `stream/` (`nz_amb_*.ydr` + the single `nz_amb_props.ytyp`) is built
from code in this folder - no Blender, no OpenIV, no binary sources in the repo. A prop is a
Python function that builds geometry from primitives, assigns materials and paints labels; the
pipeline unwraps it, bakes the textures, writes CodeWalker XML and converts it to the real GTA V
formats with a tiny CodeWalker-based CLI.

The one exception is the **imported medic bag** (`nz_amb_medbag_red / _green / _orange / _magenta`):
an artist-made model supplied by the customer (~4.8k tris, 2048 diffuse + normal + spec). It was
brought in with `import_model.py` (below); its metadata lives in `external/*.json` and build.py keeps
it in the ytyp and never deletes it. Do not edit or regenerate those files.

**Labelling policy:** props carry no maker name, wordmark or logo - neither ours nor a real
company's. Labels name the device type and an invented model code (`PM-8`, `MD-2`, `SU-2`, `IO-3`,
`TK-62` ...), plus believable fine print: rating plates (MODEL / SN / REF / LOT, electrical rating,
regulatory symbols, barcode + data-matrix), caution / danger stickers, calibration and asset tags,
the star of life or a plain cross. Keep it that way when you add props.

```
props/*.py  ──►  geometry (charts) ──► atlas packing ──► texel bake (colour, height→normal, spec,
                                                         AO, edge wear, decals) ──► DDS (DXT1/5)
            ──►  CodeWalker XML (.ydr.xml + embedded textures + composite collision)
            ──►  cwtool: XML → .ydr, one .ytyp with every archetype, re-load + validate every binary
            ──►  stream/  +  .glb previews  ──►  headless three.js renders  ──►  contact sheets
```

## Requirements

| Tool | Used for |
|---|---|
| python3 ≥ 3.10 with `numpy` + `Pillow` | geometry, baking, DDS, XML |
| .NET 8 SDK (`dotnet`) + `git` | builds `cwtool` against a CodeWalker clone (cloned automatically) |
| node ≥ 18 + chromium (`/opt/pw-browsers/chromium` or `--chromium` / `NZA_CHROMIUM`) | preview renders (optional, `--no-preview`) |

Nothing is downloaded into the repository: CodeWalker, the cwtool build, node modules and all build
output live in the work folder (`--work`, default `/tmp/nza-work/props`).

## Rebuild everything

```bash
python3 tools/props/build.py \
    --out    /tmp/nza-work/props/out \
    --stream nayzeee-ambulance/stream \
    --docs   nayzeee-ambulance/docs/modules/props.md
```

* builds every registered prop in parallel (`--jobs`, default 4),
* converts + validates with cwtool (`### n end rc=0` for every line of `<out>/cwtool_log.txt`); any
  error aborts **before** `stream/` is touched,
* checks the memory budget of every drawable (virtual + physical pages decoded from the RSC7 header):
  anything above **16 MiB** aborts before `stream/` is touched - FiveM warns that such assets "can and WILL"
  fail to stream,
* copies the binaries into `stream/` and deletes stale `nz_amb_*.ydr` that are no longer registered,
* renders 3 views per prop (+ any extra cameras a prop declares) and writes `<out>/sheets/contact_NN.png`,
* writes `<out>/props_manifest.json`, `props_table.md`, `props_catalog.md` and refreshes the generated
  sections of `docs/modules/props.md` (between `<!-- props:table:* -->` / `<!-- props:catalog:* -->`).

A full build takes ~15-20 minutes on 4 cores (2048 atlases + ambient occlusion; the treatment bay,
the stretcher and the 2048 devices take 2-4 minutes each). Useful flags:

| Flag | Effect |
|---|---|
| `--only nz_amb_us_cart,nz_amb_bvm` | rebuild only these (globs ok); the ytyp still gets every archetype from earlier manifests |
| `--quick` | skip ambient occlusion (fast iteration, not for shipping) |
| `--no-convert` | stop after XML / DDS / glb (no dotnet needed) |
| `--no-preview` | skip the three.js renders |
| `--size 512` | preview render size |
| `--docs-only` | only rewrite tables / docs from an existing `<out>` |
| `--list` | print the registered props |

Previews: `<out>/renders/<name>_<view>.png` (front / back / top + any extra cameras a prop declares),
contact sheets in `<out>/sheets/`. LOOK at them after every change.

## Adding a prop

1. Add the model name to `config/props.lua` (lead-owned: file a request in `docs/requests/props.md`
   if you are not the lead) - names are `nz_amb_<thing>`.
2. Write the prop in a module under `tools/props/props/` (every module there is imported
   automatically):

```python
from nzprops import DecalCanvas, box, cylinder, prop, quad
from .common import align, label_canvas, m_teal, rating_plate, screws
from .parts import m_hosp_white, m_teal_led

@prop("nz_amb_example", atlas=512, lod=60, hd=10, static=True, doc={
    "title": "Example device",
    "origin": "floor centre",
    "axes": "+Y = front, +Z up",
    "attach": "how other modules attach / place it",
    "screen": "only if it has an nz_amb_screen quad",
})
def example(b):
    white = m_hosp_white(b)                       # materials register by name on the builder
    b.add(box((0.30, 0.20, 0.40), white, r=0.02, seg=3, center=(0, 0, 0.20)))
    b.add(cylinder(0.02, 0.01, m_teal(b), z0=0.40))
    b.decal(label_canvas(0.20, 0.03, "INFUSION PUMP", "IP-3"), center=(0, 0.1001, 0.30), normal=(0, 1, 0),
            up=(0, 0, 1), mats=["hosp_white"], depth=0.01)        # projected print / label
    b.decal(rating_plate(0.07, 0.025, "INFUSION PUMP", "IP-3", "SN 26-00001"), center=(0, -0.1001, 0.10),
            normal=(0, -1, 0), mats=["hosp_white"], depth=0.01)   # fine-print plate on the back
    b.add(screws(b, [(-0.12, -0.10, 0.36), (0.12, -0.10, 0.36)], (0, -1, 0), d=0.005))
    b.col_box((-0.15, -0.10, 0.0), (0.15, 0.10, 0.40), "PLASTIC_HIGH_DENSITY")   # collision is mandatory
```

3. `python3 tools/props/build.py --only nz_amb_example --stream ...` then look at
   `<out>/renders/nz_amb_example_*.png`, iterate, and finish with a full build.

### Conventions

* GTA axes: metres, **+X right, +Y forward (the prop's front), +Z up**. Origin where the prop is
  placed or held: floor centre for furniture, bottom centre for things that stand on surfaces,
  the grip for hand-held tools, the hanging slot for bags, the limb / neck axis for worn props.
* Write the `doc` dict for every prop: `title`, `origin`, `axes`, `attach` (bone + offset/rotation
  or the entity offsets other modules need), `screen` when it has one. It is published in
  `docs/modules/props.md` automatically.
* Collision: `b.col_box(min, max, material)` / `b.col_cyl(center, r, length, axis, material)`;
  materials are the names in `nzprops/cwxml.py: COL_MATERIALS`.
* `static=True` for furniture that never moves (archetype flag 32); dynamic props (carried,
  attached, dropped) stay non-static.
* Texture budgets (size on screen decides): hand-held tools seen in close-ups `atlas=1024` (syringe 512
  + 512 alpha), carried devices / field kit / furniture `2048`, simple or distant props `256..1024`, the
  bay shell 2048 main + shell and 1024 supply sets (`layers={...}`). Normal + spec maps are full size up
  to 1024 and half size above (a 2048 prop gets 1024 normal / spec, like the imported bag);
  `maps={"layer": {"n": 512, "s": 512}}` shrinks them per layer.
* Memory: a drawable must stay <= 16 MiB of physical (texture) pages - the build refuses more. Pages are
  power-of-two blocks, so ~14 MiB of texture data already rounds up past 16. Lower the spec maps first
  (intensity + gloss are low frequency), then the normal maps of surfaces seen from a distance, and keep
  the diffuse atlases (labels) - the bay shell does exactly that (`maps=` in `props/bay.py`, 13 MiB).
* Triangle budgets: hand-held <= 12k, carts / devices <= 30k, furniture <= 40k, the bay shell <= 120k.
* Detail checklist: bevelled edges (`box(r=...)`), split lines (`DecalCanvas.groove`), screws
  (`common.screw/screws`), feet and bumpers, strain reliefs and coiled cords, legends on buttons,
  knurled knobs (`ribs_u` / `knurl` bumps), vents and grilles (`slots`, `perforate`), stitched straps
  (`stitch`, `stitch_rect`), labels with fine print. The baker adds AO, chipped edge wear, scratches,
  smudges, crevice grime and dust from the material parameters.

### Library cheat sheet (`nzprops`)

| Module | What |
|---|---|
| `mesh` | `box` (rounded / chamfered, per-face material + texel density), `lathe`, `cylinder`, `sphere`, `capsule`, `torus`, `sweep` (profile along a path, per-point scale, twist), `tube`, `extrude` (bevelled polygons), `plane`, `quad` (oriented, `fixed_uv` for screens), `pillow` (soft bags), `slab_with_holes`, `pocket`; path helpers `catmull`, `bezier`, `polyline_fillet`, `rrect`, `arc_points`. `Geo` has `translate / rotate / rotate_axis / scale / mirror / transform / deform / taper / flip / set_density / set_tag` |
| `paint` | `Mat(color, spec, gloss, metal, grain, bump, edge, ao, alpha, layer, dirt, wear, wear_color, scratch, smudge, cavity)`; bumps: `stipple orange_peel rubber brushed fabric webbing foam eggcrate pluck knurl ribs ribs_u leather phillips hexsocket diamond dimple perf twill cordura velcro crinkle`; `DecalCanvas` (metres; `rect circle line polygon text groove groove_rect stitch stitch_rect screw rivet perforate slots barcode datamatrix star_of_life cross icon`) with per-ink height / spec / gloss; `font()` bundled Lexend (`label*` keys) / JetBrains Mono / VT323 |
| `prop` | `@prop(name, atlas, alpha_atlas, glow_atlas, layers, maps, lod, hd, static, falloff, spec_mult, glow_mult, doc, preview)`, `Builder.mat / add / screen / decal / chart_decal / col_box / col_cyl` |
| `bake`, `atlas`, `dds`, `cwxml`, `gltf` | internals: texel baker (AO, edge wear, scratches, smudges, grime, dust), chart packer, DXT writer, CodeWalker XML, glb preview |

Material layers: `main` → `normal_spec` (`<name>_d/_n/_s`), `alpha` → `normal_spec_alpha`
(`<name>_ad/_an/_as`, translucent plastics / glass), `glow` → `emissive` (`<name>_g`, LEDs, light
panels), any name declared in `layers={"sup": 1024}` → an extra `normal_spec` set
(`<name>_sup_d/...`) for big props that need more texels. `b.screen(quad(..., fixed_uv=True),
texname="nz_amb_screen", image=..., size=(w, h))` adds an emissive screen whose texture keeps a fixed
0..1 UV layout so a DUI can replace it at runtime (`AddReplaceTexture(model, 'nz_amb_screen', ...)`).

Shared parts: `props/common.py` (materials, `align`, buttons, knobs, screws, rubber feet, strain
reliefs, coiled cords, hinges, LED lenses, grommets; labelling: `label_canvas`, `rating_plate`,
`caution_label`, `cal_sticker`, `asset_tag`, biohazard), `props/parts.py` (hospital plastics, casters,
star bases, poles, vents, radiation label, rulers), `props/screens.py` (default screen images).

### Preview cameras for interiors

A closed room cannot be judged from outside: declare cameras + point lights in the prop:

```python
@prop("nz_amb_room", ..., preview={
    "views": ["inside", "plan", "detail"],                       # what the contact sheet shows
    "cams": [{"name": "inside", "pos": [0.5, -2.0, 1.7], "target": [0, 1, 1], "fov": 75},
             {"name": "plan", "pos": [0, 0, 10], "target": [0, 0.001, 0], "fov": 30, "clipZ": 1.98}],
    "lights": [{"pos": [0, 0, 1.9], "intensity": 3.5, "distance": 7}],
})
```

`clipZ` cuts everything above that height away (plan view through the ceiling).

## Importing a third-party model (`import_model.py`)

```bash
python3 tools/props/import_model.py /path/outside/repo/source.ydr nz_amb_medbag_red \
    --stream nayzeee-ambulance/stream --title "Medic bag (red)" --max-size 2048
```

Re-exports the drawable through cwtool, renames it and its embedded textures to the new model name
(`<name>_<texture>`), re-encodes textures to DXT1/DXT5 with full mip chains, rebuilds + validates the
.ydr, writes `external/<name>.json` (bounds + archetype) and regenerates `nz_amb_props.ytyp`. The
source file is only read; keep originals outside the repository. Run Python on files you did not make
with `python3 -I` and keep them in their own folder.

## cwtool

`tools/props/cwtool` is a ~300 line C# CLI on top of CodeWalker.Core (legacy / gen8 resources,
what FiveM streams): `ydr`, `ytd`, `ytyp`, `inspect` (loads a binary back, prints models /
geometries / textures / bounds and validates it) and `batch`. `build.py` clones CodeWalker
(`--codewalker` to use an existing checkout) and builds cwtool automatically into the work folder.

Manual use:

```bash
dotnet /tmp/nza-work/props/cwtool/bin/Release/net8.0/cwtool.dll inspect stream/nz_amb_bay_shell.ydr
```

## Licences

Bundled fonts: Lexend, JetBrains Mono, VT323 (SIL OFL 1.1, see `fonts/OFL-*.txt`), DejaVu (free
licence, `fonts/LICENSE`). CodeWalker (MIT) is cloned at build time, never vendored.
