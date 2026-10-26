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
```

Credits: shader parameter names come from CodeWalker by dexyfex (MIT); parameter order,
defaults and vertex layouts follow the game's shader definitions as documented by
CodeWalker and Sollumz (MIT).  Lexend font: SIL Open Font License.
