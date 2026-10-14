# NAYZEEE props pipeline (`tools/props`)

Every custom model in `stream/` (`nz_amb_*.ydr` + the single `nz_amb_props.ytyp`) is generated
from code in this folder - no Blender, no OpenIV, no binary sources in the repo. A prop is a
Python function that builds geometry from primitives, assigns materials and paints labels; the
pipeline unwraps it, bakes the textures, writes CodeWalker XML and converts it to the real GTA V
formats with a tiny CodeWalker-based CLI.

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
* copies the binaries into `stream/` and deletes stale `nz_amb_*.ydr` that are no longer registered,
* renders 3 views per prop and writes `<out>/sheets/contact_NN.png`,
* writes `<out>/props_manifest.json`, `props_table.md`, `props_catalog.md` and refreshes the generated
  sections of `docs/modules/props.md` (between `<!-- props:table:* -->` / `<!-- props:catalog:* -->`).

A full build takes ~6-8 minutes (the treatment bay alone ~2 minutes). Useful flags:

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
from .common import align, brand_canvas, m_teal
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
    b.decal(brand_canvas(0.20, 0.03), center=(0, 0.1001, 0.30), normal=(0, 1, 0), up=(0, 0, 1),
            mats=["hosp_white"], depth=0.01)        # projected print / label
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
* Texture budgets: hand-held / small props `atlas=256..512`, furniture `1024`, the bay shell several
  1024 sets (`layers={...}`). Normal + spec maps are written at half size above 512.

### Library cheat sheet (`nzprops`)

| Module | What |
|---|---|
| `mesh` | `box` (rounded / chamfered, per-face material + texel density), `lathe`, `cylinder`, `sphere`, `capsule`, `torus`, `sweep` (profile along a path, per-point scale, twist), `tube`, `extrude` (bevelled polygons), `plane`, `quad` (oriented, `fixed_uv` for screens), `pillow` (soft bags), `slab_with_holes`, `pocket`; path helpers `catmull`, `bezier`, `polyline_fillet`, `rrect`, `arc_points`. `Geo` has `translate / rotate / rotate_axis / scale / mirror / transform / deform / taper / flip / set_density / set_tag` |
| `paint` | `Mat(color, spec, gloss, metal, grain, bump, edge, ao, alpha, layer, dirt)`; bumps: `stipple orange_peel rubber brushed fabric webbing foam eggcrate pluck knurl ribs ribs_u leather`; `DecalCanvas` (metres; `rect circle line polygon text mark lockup`) with per-ink height / spec / gloss; `font()` bundled Lexend / JetBrains Mono / VT323 |
| `prop` | `@prop(name, atlas, alpha_atlas, glow_atlas, layers, lod, hd, static, falloff, spec_mult, glow_mult, doc, preview)`, `Builder.mat / add / screen / decal / chart_decal / col_box / col_cyl` |
| `bake`, `atlas`, `dds`, `cwxml`, `gltf` | internals: texel baker + AO, chart packer, DXT writer, CodeWalker XML, glb preview |

Material layers: `main` → `normal_spec` (`<name>_d/_n/_s`), `alpha` → `normal_spec_alpha`
(`<name>_ad/_an/_as`, translucent plastics / glass), `glow` → `emissive` (`<name>_g`, LEDs, light
panels), any name declared in `layers={"sup": 1024}` → an extra `normal_spec` set
(`<name>_sup_d/...`) for big props that need more texels. `b.screen(quad(..., fixed_uv=True),
texname="nz_amb_screen", image=..., size=(w, h))` adds an emissive screen whose texture keeps a fixed
0..1 UV layout so a DUI can replace it at runtime (`AddReplaceTexture(model, 'nz_amb_screen', ...)`).

Shared parts: `props/common.py` (materials, `align`, buttons, knobs, brand / serial labels,
biohazard), `props/parts.py` (hospital plastics, casters, star bases, poles, vents, radiation
label, rulers), `props/screens.py` (default screen images).

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
