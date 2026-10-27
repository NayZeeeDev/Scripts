# nayzeee-speaker-assets: the optional Record Console upgrade

The speakers in `nayzeee-speaker/stream` (the pack: `nayzeee_audio_a` .. `_h`, `nayzeee_audio_texture.ytd`,
`nayzeee_audio.ytyp` and the `.ycd` files) stay exactly as they are. Their new colours, designs, NAYZEEE logo and
animated RGB lights are applied while the server runs (`Config.Looks`, the images in `nayzeee-speaker/html/looks/`).
There is nothing to convert for that.

This folder builds one **optional** upgrade on top of the pack:

| model | what it adds in game |
|---|---|
| `nayzeee_console` | a walnut record console on splayed legs: the turntable item's new model |
| `nayzeee_tt_platter`, `nayzeee_tt_arm`, `nayzeee_vinyl` | the **watchable turntable**: the record goes from the player's hand onto the platter, the platter spins up, the tonearm swings in, drops the needle and creeps inward while the album plays |
| `nayzeee_sleeve_a`, `_b`, `_c` | **3D record sleeves** on the record shop counter, showing the album covers (without them the shop is 2D) |

Everything is generated from Python code (geometry, textures, collision, LODs) and exported as CodeWalker XML that
you convert once on Windows. **Nothing from the pack is removed or replaced**: the upgrade has its own texture
dictionary (`nayzeee_console_texture`) and its own `.ytyp` (`nayzeee_console.ytyp`), and none of its file names
exist in the pack, so converting only ADDS files to `stream/`. Until you convert it, the script keeps using the
pack's turntable (`nayzeee_audio_g`, with its own baked record and animation) and the 2D shop. This folder is
not shipped to the server.

Also here: the item images of the records and the CarPlay unit, the phone app icon (see [Images](#images)) and
the tools that read the pack and write the looks (`tools/legacy_*.py`, see [Layout](#layout)).

## Build

Requirements: Python 3.10+ with `numpy` and `Pillow`, plus `fonttools` and `brotli` (only to read the Lexend
`.woff2` UI font): `pip install numpy pillow fonttools brotli`.

```
python3 build.py                        # everything (about 20 s)
python3 build.py --only nayzeee_vinyl   # rewrite only these ydr/glb (the ytd, ytyp and layout.json always cover all)
python3 build.py --no-dds               # skip DDS encoding while iterating on geometry
python3 build.py --png                  # also dump every texture as PNG (out/textures)
python3 tools/selftest.py               # pipeline self-test: geometry, DDS, determinism, validator (ALL OK)
python3 models/_check_turntable.py      # every turntable contract number + arm clearances (ALL OK)
```

| output | what |
|---|---|
| `out/xml/nayzeee_console_texture.ytd.xml` + folder `out/xml/nayzeee_console_texture/` (51 `.dds`) | the upgrade's texture dictionary (about 6.7 MB) |
| `out/xml/<model>.ydr.xml` (7 files) | drawables: High + Medium LOD, shaders, embedded collision |
| `out/xml/nayzeee_console.ytyp.xml` | one archetype per model (txd `nayzeee_console_texture`) |
| `out/glb/<model>.glb` | glTF 2.0 PBR previews (Blender / Sollumz, the renderer) |
| `out/layout.json` | anchors, bounds, triangle counts per LOD, LOD distances, meta per model |

The build is deterministic and ends with `lib/validate.py`, which re-reads every file the way CodeWalker's importers
do (shader and parameter names against CodeWalker's `ShadersGen9Conversion.xml`, vertex layouts, index ranges, NaNs,
enum names, DDS headers, archetype bounds ...) and exits non-zero if anything is wrong. Outputs of models that no
longer exist are removed from `out/`. DDS encodes are cached in `cache/dds` (safe to delete).

## Install the upgrade (CodeWalker on Windows)

You need the files from `out/xml` on the Windows PC (copy the whole `out\xml` folder; the `.dds` files must stay in
`nayzeee_console_texture\` next to `nayzeee_console_texture.ytd.xml`).

1. Get CodeWalker (latest release from the CodeWalker GitHub / gta5-mods page) and run `CodeWalker.exe`. On first
   start it asks **"Please select your GTAV folder"**: pick your game folder and select **GTAV Legacy**. FiveM runs the
   legacy game; with "GTAV Enhanced" CodeWalker writes Gen9 files FiveM cannot load (the window titles then end in
   "(GTAV Enhanced)").
2. Make an empty folder for the converted files, for example `C:\nayzeee_console`.
3. Open **Tools > RPF Explorer...** (or run `CodeWalker RPF Explorer.exe`).
4. **File > Open Folder...** and choose `C:\nayzeee_console`. Click that folder in the tree on the left so it is the
   current folder.
5. Click **Edit mode** in the toolbar.
6. **Edit > Import XML...** and pick `out\xml\nayzeee_console_texture.ytd.xml` **first** (CodeWalker loads the `.dds`
   files from the `nayzeee_console_texture` folder next to it). `nayzeee_console_texture.ytd` appears.
7. **Edit > Import XML...** again and select all seven `out\xml\*.ydr.xml` at once: `nayzeee_console.ydr`,
   `nayzeee_tt_platter.ydr`, `nayzeee_tt_arm.ydr`, `nayzeee_vinyl.ydr`, `nayzeee_sleeve_a.ydr`, `_b`, `_c` appear.
8. **Edit > Import XML...** with `out\xml\nayzeee_console.ytyp.xml`: `nayzeee_console.ytyp` appears.
   `C:\nayzeee_console` now holds 9 files.
9. Copy those 9 files into `nayzeee-speaker\stream`, next to the `nayzeee_audio_*` files (which stay; nothing
   there has the same name).
10. In `nayzeee-speaker/fxmanifest.lua` uncomment the two upgrade lines (remove the leading `-- `):
    ```lua
        'stream/nayzeee_console.ytyp',                                   -- inside files { ... }
    data_file 'DLC_ITYP_REQUEST' 'stream/nayzeee_console.ytyp'
    ```
11. In `nayzeee-speaker/config.lua`, switch the turntable item to the console and drop the old prop's animation
    (the console has no `.ycd` clip):
    ```lua
        ['nayzeee_audio_g'] = {
            label = 'Turntable', model = 'nayzeee_console', portable = false, vinyl = true, -- plays records only
            -- anim = { dict = 'nayzeee_audio_g', clip = 'nayzeee_audio_g' },   -- old turntable prop only
    ```
12. Restart the resource (or the server) and reconnect. If the old turntable still shows, clear the FiveM cache
    (`%localappdata%\FiveM\FiveM.app\data\cache`).

Check: place the turntable item: the walnut console appears; put a record on: it lands on the platter, the platter
spins and the arm moves in. The record shop shows 3D sleeves on its counter. To go back, set the model to
`'nayzeee_audio_g'` again; the upgrade files can stay in `stream/`.

Import XML overwrites a file of the same name in the open folder without asking, which is why step 4 uses an empty
folder. Sollumz users can import the `.ydr.xml` files with Sollumz' CodeWalker XML importer or the `.glb` files
(axes match GTA: +Z up, +Y front) instead.

## Models

`models/<name>.py` defines one prop; the file name is the GTA model name. Registering a model = adding the file
(names starting with `_` are ignored).

| model | export | High / Medium tris | notes |
|---|---|---|---|
| `nayzeee_console` | yes | 21.0k / 6.5k | walnut cabinet with waterfall edges, woven grille in a face frame with a brass inlay, four splayed lacquer legs with brass ferrules; deck plinth (arm board + collar, cue lever, arm rest, 45 adapter) on the viewer's left, control panel (knurled knobs, back-lit amber VU meter, start/stop, 33/45 keys with LEDs, toggles, engraved plate) on the right |
| `nayzeee_tt_platter` | yes | 3.1k / 0.8k | spun aluminium, strobe-dot rim, printed felt slipmat, chrome spindle |
| `nayzeee_tt_arm` | yes | 10.3k / 3.4k | gimbal pivot, chrome tube, counterweight, offset headshell, cartridge |
| `nayzeee_vinyl` | yes | 3.9k / 0.9k | 12" record, groove normal map; centre label `nayzeee_vinyl_label` (runtime-replaceable) |
| `nayzeee_sleeve_a/_b/_c` | yes | 156 each | a real pocket open on the -X edge; front `nayzeee_cover_a/_b/_c` (runtime-replaceable) |
| `nayzeee_carplay_unit` | image only | 2.9k | double-DIN head unit for the CarPlay item image (no ydr / ytyp) |

The turntable parts sit at the console's anchors (`out/layout.json`, the same numbers are in `meta.turntable` and
in `models/_tt_common.py`): platter `(0.300, 0, 0.785)`, record `(0.300, 0, 0.811)`, tonearm pivot
`(0.075, -0.125, 0.835)` with rotation 0 = parked on the rest, lead-in -27.5 deg, run-out -47.0 deg, 200 deg/s at
33 1/3. `python3 models/_check_turntable.py` asserts every contract number, the arm angles (law of cosines) and the
clearances of the arm parked, swinging (level and lifted 3 deg) and playing. `models/_example_speaker.py` is a
commented tour of the modelling API (the self-test builds and validates it).

```python
from lib import mesh as M, textures as tx, fonts
from lib.spec import ModelSpec, Anchor, LodSettings, Box, Cylinder

def build(detail):                      # 1.0 = High LOD, ~0.35 = Medium LOD
    body = M.rounded_box((0.30, 0.18, 0.42), 0.025, 6, center=(0, 0, 0.21), material="satin_graphite")
    label = M.plane(0.05, 0.012, center=(0, 0.0905, 0.12), facing="+y",
                    rect=tx.atlas_rect("volume"), material="print_decal")
    return ModelSpec(
        name="nayzeee_example",
        parts=[body, label],
        collision=[Box((0, 0, 0.21), (0.30, 0.18, 0.42), "PLASTIC")],
        anchors={"grip": Anchor((0, 0, 0.47), note="handle centre")},
        lod=LodSettings(high_dist=15, archetype_lod_dist=100),
    )
```

Conventions (all code and outputs): metres, **+Z up, +Y = front, +X = viewer's left** (viewer's right = -X),
counter-clockwise triangles, UV v = 0 at the top of the image, tangent w = handedness so `cross(N, T) * w` points to
image-up, normal maps in DirectX convention (green = down) as GTA expects. Origin = floor centre under the prop unless
the contract says otherwise (platter and record: centre of their bottom face; tonearm: the pivot; sleeves: centre of
the bottom edge).

Tips
* Pass `material=` to primitives (or use `.with_material()`): UVs from primitives and `uv_box/uv_planar/uv_cylindrical`
  are in real-world texel density and are rescaled when the material changes; `uv_fit/uv_radial/plane` map an exact
  0..1 rectangle.
* Primitives take nominal segment counts that are multiplied by the detail factor; use `M.seg(n)` for your own loops
  so the Medium LOD gets lighter too.
* Decals (`print_decal`): a quad 0.3-0.5 mm above the surface, UVs from `textures.atlas_rect(name)`, width/height ratio
  `textures.atlas_aspect(name)`; `textures.atlas_entries()` lists the prints, labels, icons, knob scales and logos.
* 3D lettering: `fonts.text_polygons("nayzeee", height, weight)` -> `M.extrude(...)`.
* `M.extrude` with two or more holes in a plate with long straight edges can overlap triangles; split the outline's
  edges to about 12 mm first (or cut one hole per plate).
* `ModelSpec(export=False)` = image-only model (GLB + layout, no ydr/ytyp entry).
* Model-specific materials/textures: `materials.register(Material(...))` and `@textures.register(name, size, fmt, kind)`
  in the model file. Texture names must be unique in the txd; textures of image-only models never reach it.

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
| felt_black | normal_spec | felt |
| vinyl_black, vinyl_label | normal_spec | record body (grooves) / centre label `nayzeee_vinyl_label` |
| sleeve_cover_a/b/c, sleeve_card | normal_spec | shop sleeves: covers `nayzeee_cover_a/b/c` |
| led_teal, led_amber, led_red, led_white, vu_meter_amber | emissive | lights, back-lit VU face |
| screen_glass_dark | spec | opaque smoked glass |
| print_decal | decal (bucket 2) | silkscreen prints / logos from `nz_print_atlas` |
| tt_lacquer_black, tt_brass, tt_alu_knurl, tt_platter_strobe, tt_slipmat, tt_plate, tt_sleeve_back | normal_spec | turntable materials (`models/_tt_common.py`, `models/_sleeve.py`, textures `nz_tt_*`) |

Runtime-replaceable textures (always in `nayzeee_console_texture`): `nayzeee_vinyl_label` (the record label the
turntable and the shop draw the album cover on) and `nayzeee_cover_a`, `nayzeee_cover_b`, `nayzeee_cover_c` (one per
shop carousel slot).

## Images

The record, CarPlay and phone images are made by one tool:

```
python3 tools/item_images.py                                   # all of them (about 35 min on a 4-core CPU)
python3 tools/item_images.py --only vinyl_21 record carplay icon
python3 tools/item_images.py --covers out/previews/covers.png  # just a sheet of the cover + label art (seconds)
```

| file in `nayzeee-speaker/` | what |
|---|---|
| `install/images/vinyl_record.png` | generic record half out of a plain nayzeee sleeve |
| `install/images/vinyl_<key>.png` | one per record in `vinyls.lua`: the record half out of its sleeve, sleeve + label colourway derived from the key, album title and artist in Lexend (abstract art, no real album covers) |
| `install/images/nayzeee_carplay.png` | the `nayzeee_carplay_unit` model: double-DIN unit, glossy screen with a dark music player |
| `html/phone/icon.png` | 256 px phone app icon: dark tile, teal glow, a record with the nayzeee mark as its label |

The 512 px images are rendered at 1024 px with one camera and light rig (3/4 view from the front right, like the
speaker images; the prop about 80 % of the frame; soft contact shadow; transparent background) and downsampled with
premultiplied alpha. Records are read straight from `vinyls.lua`: add a record there and rerun the tool to get its
image. The cover and label art only exist inside the tool; they never go into the game texture dictionary.

The speaker images (`install/images/nayzeee_audio_a.png` .. `_h.png`) show the pack's props in their default look
and come from `python3 tools/legacy_preview.py inventory` (it reads the pack in `stream/` and the looks in
`html/looks/`).

## Rendering

`render.py` makes transparent product-shot PNGs (inventory images, shop art, review sheets) from the build's GLB
files. The renderer is our own WebGL2 code (`render/renderer.js`, `render/shaders.js`, no 3D library) running in the
preinstalled headless Chromium through Playwright (`render/run.js`, CPU SwiftShader, so it needs no GPU and gives the
same image every run). Needs `node` with the global `playwright` package (`NODE_PATH` is found with `npm root -g`)
and Chromium at `/opt/pw-browsers/chromium` (or `NZ_CHROMIUM`).

```
python3 render.py --model nayzeee_vinyl                     # -> out/previews/nayzeee_vinyl.png, 512 px
python3 render.py --model nayzeee_console --quick           # fast draft (~10 s) while modelling
python3 render.py --model nayzeee_vinyl --size 1024 --quality high --out shot.png
python3 render.py --model nayzeee_vinyl --yaw 35 --pitch 18 --fov 30 --bg "#15181a" --exposure 1.2
python3 render.py --model nayzeee_vinyl --yaws 0,45,90 --out strip.png       # angles side by side
python3 render.py --model nayzeee_tt_arm --turntable 12 --out tt/arm.png     # tt/arm_000..011.png, arm_grid.png, arm.webp
python3 render.py --sheet out/previews/contact_sheet.png                    # every exported model, labelled grid
python3 render.py --parts nayzeee_console nayzeee_tt_platter:0.3,0,0.785 nayzeee_vinyl:0.3,0,0.811 \
                  "nayzeee_tt_arm:0.075,-0.125,0.835:0,0,-33.6" --out console.png
python3 render.py --scene render/scenes/console_playing.json
```

**Quick check for model authors:** save `models/<name>.py`, then `python3 render.py --model <name> --quick` and open
`out/previews/<name>.png`. You do not need to run `build.py` first: when `out/glb/<name>.glb` is missing or older than
the model / `lib` sources, the model is built in-process into `cache/render/glb` (never touching `out/`).
`--debug base|normal|ao|spec|diffuse|emission --tonemap linear` shows one shading term (wrong UVs, flipped normals,
missing tangents and AO problems stand out immediately). `-v` prints the browser log and per-phase timings.

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
| `--bloom` | 1.0 | glow of emissive parts only (LEDs, VU meters, screens), 0 = off |
| `--materials FILE` | | extra material hints merged over `render/materials.json` |
| `--glb auto/out/fresh` | auto | GLB source: up-to-date `out/glb` else in-process build / only `out/glb` / always rebuild |
| `--skip-missing` | | leave out parts whose model does not exist yet |

Rotations are degrees applied X, then Y, then Z about the parent axes (R = Rz*Ry*Rx), positions metres in GTA model
space; `parent=I` makes a part relative to an earlier part (index or model name). `render/scenes/` holds ready scenes
at the contract offsets: `console_playing.json` (console + platter + record + tonearm at groove radius 0.12, arm
-33.6 deg), `console_deck.json` (deck parts only) and `record_sleeve.json` (record half out of sleeve A). Typical
times on a 4-core box: 512 px normal 25-35 s, 1024 px normal 60-140 s, `--quick` 384 px about 10 s per model.

**Per-model camera:** `render/cameras.json` sets a model's preferred yaw/pitch/fov/margin/exposure for `--model`,
`--sheet`, `--yaws` and `--turntable`. A model can also carry it in its spec: `ModelSpec(..., meta={"render": {"pitch":
30}})`. Explicit CLI flags always win.

**Material hints (`render/materials.json`):** renderer-only extras keyed by GLB material name; they never reach the
game files. `anisotropy` gives grooved/brushed surfaces their streaked highlights: `mode` `uv-radial` (circles around
uv `center`, for anything mapped with `uv_radial`: records, spun-metal knobs and platters), `tangent` (grooves along U,
brushed metal and brass), `model-radial` (circles around the model's Z axis); `roughness_across` / `roughness_along`
the perceptual roughness across / along the grooves; `mask_roughness: [lo, hi]` fades the effect in where the
roughness map lies between lo and hi (the record's smooth track gaps stay glossy). Also `roughness`, `metallic`,
`base_color` (multiplies the base map), `emissive_scale`, `normal_scale`, and `base_texture` / `mr_texture` /
`normal_texture: false` to drop a map, so `--materials my_test.json` can try a finish without touching the model.

How it works, briefly:
* GLBs are read as written by `lib/glb.py` (glTF Y-up converted back to GTA Z-up), metallic-roughness PBR, normal
  maps (Toksvig-filtered), vertex colours, emissive (+ `KHR_materials_emissive_strength`), alpha mask/blend
  (prints/decals), `KHR_materials_anisotropy`.
* Studio: a procedural camera-relative soft-box environment (key front-left, fill right, rim strip back-right, strip
  back-left, overhead box, low back sweep, low front bounce card, small kicker) on a dark gradient, GGX pre-filtered
  into a cube map (split sum + DFG table) for reflections and projected to SH9 for diffuse light. The rig moves with
  the camera, so every yaw is lit the same way.
* Phase 1, visibility: hundreds of orthographic depth maps from a Fibonacci sphere of directions give noise-free
  ambient occlusion, a reflection-cone occlusion and the floor's sky visibility (contact shadow).
* Phase 2, light: jittered frames (tent filter, 32-64 samples per pixel of anti-aliasing) accumulate in float.
  Environment frames add SH x AO diffuse, occluded reflections, emission and coverage. Soft-box frames light the three
  shadow-casting boxes from a new point of their area each frame (shadow maps + analytic GGX): true soft shadows and
  reflections. Anisotropic materials use the anisotropic GGX (stochastic VNDF sampling for the environment).
* The floor is a shadow catcher: black with alpha = the fraction of light the props take away from an empty floor, so
  it composites onto any background.
* Bloom comes from one extra emission-only frame, so only emitters glow (LEDs, VU faces, screens), never specular
  highlights. On a transparent background the glow only brightens pixels that are already covered and never adds
  alpha: glow spilled into empty space used to be stored as near-transparent pixels with bright straight colour,
  which showed as a white haze around chrome parts (and as halos when the image is scaled or previewed without
  exact alpha). On a solid `--bg` it is still added over the background.
* ACES / AgX / neutral tone mapping, sRGB and a 1-LSB dither give straight-alpha RGBA8.

## Layout

```
build.py               build entry point (ytd / ydr / ytyp XML + DDS, GLB, layout.json, validation)
render.py              product-shot renderer CLI (see Rendering)
lib/mesh.py            geometry toolkit (primitives, transforms, UVs, normals, tangents)
lib/materials.py       GTA shaders + material registry (+ PBR equivalents)
lib/textures.py        procedural textures, print atlas, texture registry (TXD_NAME = nayzeee_console_texture)
lib/fonts.py           Lexend for textures and 3D lettering
lib/spec.py            ModelSpec, Anchor, LodSettings, collision shapes
lib/dds.py             BC1/BC3 codec, mip chains, DDS read/write
lib/cwxml.py           CodeWalker XML writers (ydr/ytd/ytyp)
lib/glb.py             glTF 2.0 writer
lib/validate.py        output validator (python3 -m lib.validate out/xml)
models/                one file per prop; _tt_common.py (turntable contract, helpers, materials),
                       _sleeve.py (sleeve model + default covers), _check_turntable.py, _example_speaker.py
render/                WebGL2 renderer: run.js (Playwright driver), renderer.js, shaders.js,
                       materials.json (material hints), cameras.json (per-model camera), scenes/
tools/selftest.py      pipeline self-test
tools/item_images.py   record / CarPlay item images + phone icon (see Images)
tools/legacy_reader.py reads the pack's .ydr/.ytd in nayzeee-speaker/stream (-> legacy/*.json, GLB previews)
tools/legacy_looks.py  writes nayzeee-speaker/html/looks (the speaker looks: fabrics, drivers, logo, record)
tools/legacy_preview.py renders the pack's props in their looks (+ the speaker inventory images)
tools/extract_shader_names.py  refreshes data/shaders_gen9.json from CodeWalker's shader list
```

Credits: shader parameter names come from CodeWalker by dexyfex (MIT); parameter order, defaults and vertex layouts
follow the game's shader definitions as documented by CodeWalker and Sollumz (MIT). Lexend font: SIL Open Font
License.
