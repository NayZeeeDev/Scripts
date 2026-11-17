# Custom key fob props

Original nayzeee key props, one per fob design plus a plain metal key. The car lock uses them for
the key in your hand, keys dropped / thrown on the ground, catching and picking up
(`config/carlock.lua` -> `Config.CarLock.fobProps`).

| Model | Design | Body (W x L x H) | With ring | Triangles |
|---|---|---|---|---|
| `nz_keyfob_generic` | generic | 3.4 x 6.6 x 1.3 cm | 8.6 cm | 1270 |
| `nz_keyfob_sport` | sport | 3.3 x 7.0 x 1.2 cm | 9.0 cm | 1284 |
| `nz_keyfob_luxury` | luxury | 3.7 x 7.2 x 1.4 cm | 9.2 cm | 1418 |
| `nz_keyfob_classic` | classic | 3.1 x 6.0 x 1.5 cm | 8.0 cm | 964 |
| `nz_keyfob_leather` | leather | 3.6 x 6.8 x 1.6 cm | 9.8 cm | 1184 |
| `nz_keyfob_compact` | compact | 2.8 x 5.0 x 1.1 cm | 6.8 cm | 1326 |
| `nz_keyfob_slim` | slim | 2.9 x 7.4 x 0.9 cm | 9.3 cm | 1226 |
| `nz_keyfob_card` | card | 5.4 x 8.6 x 0.35 cm | (no ring) | 260 |
| `nz_keyfob_retro` | retro | 3.8 x 5.6 x 1.8 cm | 7.8 cm | 910 |
| `nz_carkey` | key | 2.4 x 2.6 cm head, 8.7 cm long | | 722 |

Axes and origin, all models: the origin is the grip point, the centre of the fob body (for the car key,
the centre of the key head). +Y points to the key ring end, -Y to the bottom / blade tip, +Z is the
button face.

## What ships in this folder

- `nz_keyfobs.blend`: the source models (Blender 4.2+), one collection and one mesh per prop,
  Principled materials. Built by `tools/fobprops/make_fobs.py`.
- `nz_*.glb`: the same models as glTF, for previews or other tools.
- `nz_keyfobs_sollumz.blend`: the models converted for GTA with Sollumz: drawables with a box
  collision bound, GTA shaders, the `nz_keyfobs` archetype file. Built by `tools/fobprops/export_gta.py`.
- `gta5/`: the GTA export in **CodeWalker XML** (`<name>.ydr.xml` + a `<name>/` folder holding the
  embedded texture `nz_keyfob_atlas.dds`, and `nz_keyfobs.ytyp.xml`). FiveM cannot stream XML:
  convert it to binary first (below).

Shaders: `default.sps` for the whole fob (colours come from one 32 x 32 swatch texture embedded in each
drawable), `emissive.sps` (multiplier 2) for the panic button and the LEDs. Archetypes: `lodDist` 60,
bounding box and sphere from the model, embedded texture dictionary.

## Installing in game

The resource falls back to GTA's `lr_prop_carkey_fob` while the models are not streamed, so nothing
breaks before you do this.

1. Get binary files, either way:
   - **CodeWalker** (Windows): in the RPF Explorer use Import XML on every `.ydr.xml` and
     `nz_keyfobs.ytyp.xml` in `gta5/` (keep each `<name>/` texture folder next to its `.ydr.xml`, the
     texture is read from there), then export / save the binaries. You get
     `nz_keyfob_<design>.ydr`, `nz_carkey.ydr` and `nz_keyfobs.ytyp`.
   - **Sollumz with PyMateria** (Windows, Sollumz preferences -> install the optional PyMateria
     dependency): open `nz_keyfobs_sollumz.blend`, Export, format **Native**, version **Gen8**: this
     writes the `.ydr` files and the `.ytyp` directly.
2. Put the `.ydr` files and `nz_keyfobs.ytyp` in `nayzeee-garages/stream/` and add to `fxmanifest.lua`:
   ```lua
   data_file 'DLC_ITYP_REQUEST' 'stream/nz_keyfobs.ytyp'
   ```
3. `config/carlock.lua` already points `fobProps.byDesign` at the `nz_*` models. Check the hand
   position in game and tune `fobProps.hand.offset` / `rotation` if needed.

## Editing and re-exporting

Edit the generator rather than the .blend where you can, so the models stay reproducible:

```sh
# 1. models: writes nz_keyfobs.blend + one .glb per prop (add --preview out.png for a Cycles render)
blender --background --python tools/fobprops/make_fobs.py -- --out install/fobprops

# 2. GTA export with Sollumz installed in that Blender: XML always, binary too when PyMateria is installed
blender --background install/fobprops/nz_keyfobs.blend --python tools/fobprops/export_gta.py -- \
  --out install/fobprops/gta5 --save-blend install/fobprops/nz_keyfobs_sollumz.blend
```

Both scripts also run with the `bpy` module from PyPI (Python 3.11, `pip install bpy==4.5.4 szio==1.4.0`)
instead of Blender; pass the folder that holds the Sollumz add-on with `--sollumz <dir>` and the model
file with `--blend <file>` to `export_gta.py`.

If you edit `nz_keyfobs.blend` by hand: keep one mesh per `nz_*` collection, the origin at the grip
point, and Principled base colours (a material with the custom property `nz_emissive = True` gets the
emissive shader). Then run step 2 again.
