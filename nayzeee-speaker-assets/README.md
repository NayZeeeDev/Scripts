# nayzeee-speaker-assets

Source + build pipeline for the props of **nayzeee-speaker** (speakers, record console,
turntable parts, records and shop sleeves).  Everything is generated from Python code:
geometry, textures, collision, LODs.  Nothing here is shipped to the server; the build
produces CodeWalker XML + DDS that you convert into the GTA V binaries
(`.ydr`, `.ytd`, `.ytyp`) that go into `nayzeee-speaker/stream`.

Requirements: Python 3.10+ with `numpy` and `Pillow`, plus `fonttools` and `brotli`
(only to read the Lexend `.woff2` UI font): `pip install numpy pillow fonttools brotli`.

## Build

```
python3 build.py                       # every model
python3 build.py --only nayzeee_vinyl  # write ydr/glb for these models only (ytd/ytyp/layout still cover all)
python3 build.py --no-dds              # skip DDS encoding while iterating on geometry
python3 build.py --png                 # also dump every texture as PNG (out/textures)
python3 tools/selftest.py              # pipeline self-test (geometry, DDS, determinism, validator)
```

| output | what |
|---|---|
| `out/xml/<model>.ydr.xml` | drawable: High + Medium LOD, shaders, embedded collision |
| `out/xml/nayzeee_audio_texture.ytd.xml` + `out/xml/nayzeee_audio_texture/*.dds` | the one shared texture dictionary |
| `out/xml/nayzeee_audio.ytyp.xml` | one archetype per exported model |
| `out/glb/<model>.glb` | glTF 2.0 PBR preview (Blender/Sollumz, item images) |
| `out/layout.json` | anchors, bounds, triangle counts per LOD, LOD distances, meta per model |

The build is deterministic and ends with `lib/validate.py`, which re-reads every file the
way CodeWalker's importers do (shader/parameter names against CodeWalker's
`ShadersGen9Conversion.xml`, vertex layouts, index ranges, NaNs, enum names, DDS headers,
archetype bounds ...).  The exit code is non-zero if anything is wrong.  DDS encodes are
cached in `cache/dds` (safe to delete).

## Convert to game files with CodeWalker (Windows)

1. Get CodeWalker (the latest release from the CodeWalker GitHub / gta5-mods page) and run
   `CodeWalker.exe`.  On first start it asks **"Please select your GTAV folder"**: pick your
   game folder and select **GTAV Legacy** (FiveM runs the legacy game; with "GTAV Enhanced"
   CodeWalker writes Gen9 resources that FiveM cannot load - the window titles then end in
   "(GTAV Enhanced)").
2. Open **Tools > RPF Explorer...** (or run `CodeWalker RPF Explorer.exe`).
3. **File > Open Folder...** and choose `nayzeee-speaker\stream`.  Click that folder in the
   tree on the left so it is the current folder.
4. Click **Edit mode** in the toolbar.
5. **Edit > Import XML...** and pick `out\xml\nayzeee_audio_texture.ytd.xml` **first**
   (leave the `nayzeee_audio_texture` folder with the `.dds` files next to it - CodeWalker
   loads them from there).  `nayzeee_audio_texture.ytd` appears in `stream`.
6. **Edit > Import XML...** again, select all `out\xml\*.ydr.xml` at once -> the `.ydr` files.
7. **Edit > Import XML...** with `out\xml\nayzeee_audio.ytyp.xml` -> `nayzeee_audio.ytyp`.
8. Delete the old `nayzeee_audio_*.ycd` files from `stream` (prop animations of the old
   models; the new models have none and the scripts guard animations with `DoesAnimDictExist`).
9. Restart the resource / reconnect.  If the old models still show, clear the FiveM cache
   (`%localappdata%\FiveM\FiveM.app\data\cache`).

Import XML overwrites files of the same name without asking.  `fxmanifest.lua` already
loads `stream/nayzeee_audio.ytyp` (`data_file 'DLC_ITYP_REQUEST'`).

Sollumz users can import the `.glb` files into Blender instead (axes match GTA: +Z up,
+Y front) or the `.ydr.xml` directly with Sollumz' CodeWalker XML importer.

## Models

`models/<name>.py` defines one prop; the file name is the GTA model name.  Registering a
model = adding the file (names starting with `_` are ignored; `models/_example_speaker.py`
is a commented tour of the API).

```python
from lib import mesh as M, textures as tx, fonts
from lib.spec import ModelSpec, Anchor, LodSettings, Box, Cylinder

def build(detail):                      # 1.0 = High LOD, ~0.35 = Medium LOD
    body = M.rounded_box((0.30, 0.18, 0.42), 0.025, 6, center=(0, 0, 0.21), material="satin_graphite")
    grille = M.cylinder(0.08, 0.002, 64, material="speaker_grille_metal") \
        .orient("+y", (0, 0.09, 0.30)).uv_planar("+y")           # flat design -> front face
    label = M.plane(0.05, 0.012, center=(0, 0.0905, 0.12), facing="+y",
                    rect=tx.atlas_rect("volume"), material="print_decal")
    return ModelSpec(
        name="nayzeee_audio_x",
        parts=[body, grille, label],
        collision=[Box((0, 0, 0.21), (0.30, 0.18, 0.42), "PLASTIC")],
        anchors={"grip": Anchor((0, 0, 0.47), note="handle centre")},
        lod=LodSettings(high_dist=15, archetype_lod_dist=100),
    )
```

Conventions (all code and outputs): metres, **+Z up, +Y = front, +X = viewer's left**
(viewer's right = -X), counter-clockwise triangles, UV v = 0 at the top of the image,
tangent w = handedness so `cross(N, T) * w` points to image-up, normal maps in DirectX
convention (green = down) as GTA expects.  Origin = floor centre under the prop unless
the shared contract says otherwise.

Tips
* Pass `material=` to primitives (or use `.with_material()`): UVs from primitives and
  `uv_box/uv_planar/uv_cylindrical` are in real-world texel density and are rescaled when
  the material changes; `uv_fit/uv_radial/plane` map an exact 0..1 rectangle.
* Primitives take nominal segment counts that are multiplied by the detail factor; use
  `M.seg(n)` for your own loops so the Medium LOD gets lighter too.
* Decals (`print_decal`): a quad 0.3-0.5 mm above the surface, UVs from
  `textures.atlas_rect(name)`, width/height ratio `textures.atlas_aspect(name)`;
  `textures.atlas_entries()` lists the prints, labels, icons, knob scales and logos.
* 3D lettering: `fonts.text_polygons("nayzeee", height, weight)` -> `M.extrude(...)`.
* Collision shapes may have any orientation (Box rotation, Cylinder p1/p2); keep them
  simple - a few boxes/cylinders per prop.
* `ModelSpec(export=False)` = image-only model (GLB + layout, no ydr/ytyp entry).
* Model-specific materials/textures: `materials.register(Material(...))` and
  `@textures.register("name", size, fmt, kind)` in the model file.  Texture names must be
  unique in the shared txd; keep most at 512 and only a few at 1024.

## Materials (lib/materials.py)

| material | GTA shader | notes |
|---|---|---|
| matte_black_plastic, satin_graphite, gloss_black_plastic, teal_plastic, white_plastic | normal_spec | moulded plastics (orange-peel normal) |
| rubber, rubber_grip | normal_spec | soft rubber / diamond knurl |
| speaker_grille_metal, speaker_grille_round | normal_spec | perforated steel (hex / round holes), 6.4 cm tile |
| fabric_grille_dark | normal_spec | woven acoustic cloth |
| brushed_aluminium, brushed_aluminium_radial | normal_spec | linear / spun (map discs with `uv_radial`) |
| chrome | spec | polished metal |
| gunmetal | normal_spec | bead-blasted dark metal |
| walnut | normal_spec | lacquered veneer, grain along U |
| felt_black | normal_spec | slipmat |
| vinyl_black, vinyl_label | normal_spec | record body (grooves) / centre label `nayzeee_vinyl_label` |
| sleeve_cover_a/b/c, sleeve_card | normal_spec | shop sleeves: covers `nayzeee_cover_a/b/c` |
| led_teal, led_amber, led_red, led_white, vu_meter_amber | emissive | lights, back-lit VU face |
| screen_glass_dark | spec | opaque smoked glass |
| print_decal | decal (bucket 2) | silkscreen prints / logos from `nz_print_atlas` |

Runtime-replaceable textures (always in the txd): `nayzeee_vinyl_label`,
`nayzeee_cover_a`, `nayzeee_cover_b`, `nayzeee_cover_c`.

## Layout

```
build.py              build entry point
lib/mesh.py           geometry toolkit (primitives, transforms, UVs, normals, tangents)
lib/materials.py      GTA shaders + material registry (+ PBR equivalents)
lib/textures.py       procedural textures, print atlas, texture registry
lib/fonts.py          Lexend for textures and 3D lettering
lib/spec.py           ModelSpec, Anchor, LodSettings, collision shapes
lib/dds.py            BC1/BC3 codec, mip chains, DDS read/write
lib/cwxml.py          CodeWalker XML writers (ydr/ytd/ytyp)
lib/glb.py            glTF 2.0 writer
lib/validate.py       output validator (python3 -m lib.validate out/xml)
models/               one file per prop
data/shaders_gen9.json  shader/parameter names from CodeWalker (tools/extract_shader_names.py)
tools/selftest.py     pipeline self-test
render.py             product-shot renderer CLI (see Rendering)
render/               WebGL2 renderer: run.js (Playwright driver), renderer.js, shaders.js,
                      materials.json (material hints), cameras.json (per-model camera), scenes/
```

Credits: shader parameter names come from CodeWalker by dexyfex (MIT); parameter order,
defaults and vertex layouts follow the game's shader definitions as documented by
CodeWalker and Sollumz (MIT).  Lexend font: SIL Open Font License.

## Rendering

`render.py` makes transparent product-shot PNGs (inventory images, shop art, review sheets) from the build's
GLB files.  The renderer is our own WebGL2 code (`render/renderer.js`, `render/shaders.js`, no 3D library)
running in the preinstalled headless Chromium through Playwright (`render/run.js`, CPU SwiftShader, so it
needs no GPU and gives the same image every run).  Needs `node` with the global `playwright` package
(`NODE_PATH` is found with `npm root -g`) and Chromium at `/opt/pw-browsers/chromium` (or `NZ_CHROMIUM`).

```
python3 render.py --model nayzeee_vinyl                    # -> out/previews/nayzeee_vinyl.png, 512 px
python3 render.py --model nayzeee_audio_a --quick          # fast draft (~10 s) while modelling
python3 render.py --model nayzeee_vinyl --size 1024 --quality high --out shot.png
python3 render.py --model nayzeee_vinyl --yaw 35 --pitch 18 --fov 30 --bg "#15181a" --exposure 1.2
python3 render.py --model nayzeee_vinyl --yaws 0,45,90 --out strip.png       # angles side by side
python3 render.py --model nayzeee_audio_a --turntable 12 --out tt/a.png      # tt/a_000..011.png, a_grid.png, a.webp
python3 render.py --sheet out/previews/contact_sheet.png                    # every exported model, labelled grid
python3 render.py --parts nayzeee_audio_g nayzeee_tt_platter:0.3,0,0.785 nayzeee_vinyl:0.3,0,0.811 \
                  "nayzeee_tt_arm:0.075,-0.125,0.835:0,0,-33.6" --out console.png
python3 render.py --scene render/scenes/console_playing.json --skip-missing
```

**Quick check for model authors:** save `models/<name>.py`, then `python3 render.py --model <name> --quick`
and open `out/previews/<name>.png`.  You do not need to run `build.py` first: when `out/glb/<name>.glb` is
missing or older than the model / `lib` sources, the model is built in-process into `cache/render/glb`
(never touching `out/`).  `--debug base|normal|ao|spec|diffuse --tonemap linear` shows one shading term
(wrong UVs, flipped normals, missing tangents and AO problems stand out immediately).  `-v` prints the
browser log and per-phase timings.

| option | default | meaning |
|---|---|---|
| `--model NAME` | | model name (`models/NAME.py`) or a path to any `.glb` |
| `--parts SPEC ...` | | compose models: `NAME[:x,y,z[:rx,ry,rz[:scale]]]` or `NAME:pos=x,y,z:rot=rx,ry,rz:scale=s:parent=I` |
| `--scene FILE` | | JSON `{parts:[{model,pos,rot,scale,parent}], camera:{...}, render:{...}}`; CLI flags override it |
| `--sheet PNG` | | all exported models (`--all`: also image-only ones) in a labelled grid (`--cols`, cells 384 px) |
| `--out PNG` | `out/previews/<model or scene>.png` | output path |
| `--size N` or `WxH` | 512 | pixels |
| `--yaw / --pitch / --fov` | 35 / 18 / 30 | degrees; yaw 0 looks straight at the front (+Y), positive yaw orbits to the viewer's right (shows the -X side) |
| `--margin` | 0.06 | empty border per side (fraction of the frame); the camera auto-frames the silhouette |
| `--distance-scale` | 1 | pull the auto-framed camera back (>1) or in (<1) |
| `--yaws a,b,c` | | one image per yaw, same scale, side by side in `--out` |
| `--turntable N` | | N frames around the model at a fixed distance + grid + animated WebP |
| `--bg` | transparent | `transparent` or `#rrggbb` |
| `--exposure` | 1.0 | linear exposure |
| `--tonemap` | aces | `aces`, `agx`, `neutral` (Khronos PBR Neutral), `linear` |
| `--quality` / `--quick` | normal | draft / normal / high = 24 / 96 / 192 soft-shadow frames, 16 / 32 / 64 anti-aliasing frames, 128 / 384 / 768 AO directions |
| `--samples`, `--ao-samples` | | override the frame / direction counts |
| `--shadow` | 1.0 | floor-shadow opacity, 0 = no floor |
| `--ground Z` | lowest point | floor height in metres |
| `--bloom` | 1.0 | glow of emissive parts (LEDs, VU meters), 0 = off |
| `--materials FILE` | | extra material hints merged over `render/materials.json` |
| `--glb auto/out/fresh` | auto | GLB source: up-to-date `out/glb` else in-process build / only `out/glb` / always rebuild |
| `--skip-missing` | | leave out parts whose model does not exist yet |

Rotations are degrees applied X, then Y, then Z about the parent axes (R = Rz*Ry*Rx), positions metres in
GTA model space; `parent=I` makes a part relative to an earlier part (index or model name).
`render/scenes/` holds ready scenes at the shared-contract offsets: `console_playing.json` (console +
platter + record + tonearm at groove radius 0.12, arm -33.6 deg), `console_deck.json` (deck parts only)
and `record_sleeve.json` (record half out of sleeve A).  Typical times on this 4-core box: 512 px normal
25-35 s, 1024 px normal 60-80 s, 1024 px high about 2 min, `--quick` 384 px about 10 s per model.

**Per-model camera:** `render/cameras.json` sets a model's preferred yaw/pitch/fov/margin/exposure for
`--model`, `--sheet`, `--yaws` and `--turntable` (the record uses pitch 30).  A model can also carry it in its
spec: `ModelSpec(..., meta={"render": {"pitch": 30}})`.  Explicit CLI flags always win.

**Material hints (`render/materials.json`):** renderer-only extras keyed by GLB material name; they never
reach the game files.  `anisotropy` gives grooved/brushed surfaces their streaked highlights: `mode`
`uv-radial` (circles around uv `center`, for anything mapped with `uv_radial`: records, spun-metal knobs and
platters), `tangent` (grooves along U, brushed metal), `model-radial` (circles around the model's Z axis);
`roughness_across` / `roughness_along` the perceptual roughness across / along the grooves;
`mask_roughness: [lo, hi]` fades the effect in where the roughness map lies between lo and hi (the record's
smooth track gaps stay glossy).  Also `roughness`, `metallic`, `base_color` (multiplies the base map),
`emissive_scale`, `normal_scale`, and `base_texture` / `mr_texture` / `normal_texture: false` to drop a map,
so `--materials my_test.json` can try a finish without touching the model.

How it works, briefly:
* GLBs are read as written by `lib/glb.py` (glTF Y-up converted back to GTA Z-up), metallic-roughness PBR,
  normal maps (Toksvig-filtered), vertex colours, emissive (+ `KHR_materials_emissive_strength`), alpha
  mask/blend (prints/decals), `KHR_materials_anisotropy`.
* Studio: a procedural camera-relative soft-box environment (key front-left, fill right, rim strip
  back-right, strip back-left, overhead box, low back sweep, low front bounce card, small kicker) on a dark
  gradient.  It is GGX pre-filtered into a cube map (split sum + DFG table) for reflections and projected to
  SH9 for diffuse light.  The rig moves with the camera, so every yaw is lit the same way (a turntable).
* Phase 1, visibility: hundreds of orthographic depth maps from a Fibonacci sphere of directions give
  noise-free ambient occlusion, a reflection-cone occlusion and the floor's sky visibility (contact shadow).
* Phase 2, light: jittered frames (tent filter, so 32-64 samples per pixel of anti-aliasing) accumulate in
  float.  Environment frames add SH x AO diffuse, occluded reflections, emission and coverage.  Soft-box
  frames light the three shadow-casting boxes from a new point of their area each frame (shadow maps +
  analytic GGX), which gives true soft shadows and reflections.  Anisotropic materials use the
  anisotropic GGX (stochastic VNDF sampling for the environment).
* The floor is a shadow catcher: black with alpha = the fraction of light the props take away from an empty
  floor, so it composites onto any background.  Bloom from the HDR image, ACES/AgX/neutral tone mapping,
  sRGB and a 1-LSB dither give straight-alpha RGBA8.
