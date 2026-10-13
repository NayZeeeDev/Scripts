# Custom minimap (recolour tool)

Changes GTA's radar map into a clean style: dark, teal, midnight, light, mono, or your own colours.
These are the same kind of maps you see on big servers (dark land, bright roads, flat water).

The game's map pictures are stored in `.ytd` texture files. The steps are:
**export them → recolour them with this tool → import them back → stream them.**
You need a Windows PC with **OpenIV** or **CodeWalker** for the export and import.

## 1. Export the map tiles

1. Open OpenIV (or CodeWalker's RPF Explorer).
2. Search the game files for `minimap_sea`. You'll find files like
   `minimap_sea_0_0.ytd`, `minimap_sea_0_1.ytd` … `minimap_sea_2_1.ytd`.
   These are the radar map tiles, and postal map resources replace the same files.
   Search the whole game folder, `update.rpf` included, and use the newest copy you find.
3. Copy **every** `minimap_sea_*.ytd` into a working folder, e.g. `C:\minimap\ytd\`.
4. Open each `.ytd` and export its texture as **PNG** (or DDS) into `C:\minimap\in\`.
   **Keep the exact texture names**. You need them again in step 3.

> Already have a postal map resource? Its `stream/` folder has the same `minimap_sea_*.ytd` files.
> Export from those instead and your recoloured map keeps the postal numbers.

## 2. Recolour

```bash
pip install pillow
python recolor.py C:\minimap\in C:\minimap\out --style teal --preview
```

Open `out\_preview.png` to see the result, try other styles, then pick one.

| style      | look                                         |
|------------|----------------------------------------------|
| `dark`     | near-black land, grey roads, white highways  |
| `teal`     | NayZeee teal roads on dark green-black       |
| `midnight` | navy land, blue-grey roads                   |
| `light`    | light grey land, white roads, soft blue water|
| `mono`     | pure greyscale                               |
| `custom`   | your own colours (see below)                 |

Your own colours:

```bash
python recolor.py in out --style custom --bg "#0b0d0f" --block "#1a1e22" --road "#08afa2" --highway "#e6fffc" --water "#06201e"
```

You can also change one colour of a built-in style, e.g. `--style dark --road "#08afa2"`.

Tuning:
- `--water-sens 12`: more of the map counts as water (raise it if some land turns into water).
- `--contrast 1.3`: more of the map becomes empty land, so roads stand out more.

## 3. Import back

1. Open each `.ytd` copy from step 1 in OpenIV / CodeWalker (edit mode).
2. Replace each texture with the recoloured PNG **of the same name**.
   Keep the format and mipmaps the tool suggests (DXT5 / BC3 is fine).
3. Save the `.ytd` files.

## 4. Stream it

Put the edited `minimap_sea_*.ytd` files in `nayzeee-hud/stream/`, or in a separate small resource.
Then **restart the server fully** and reconnect. A resource restart is not enough for map textures.

- Running a postal map resource too? Use only one set of `minimap_sea_*.ytd` files,
  or the last resource to start overwrites the other.
- The square / circle shape (`squaremap.ytd`, `circlemap.ytd`) is separate.
  Every shape works with your custom map.
- Map wrong or unchanged? Clear your FiveM cache (`FiveM Application Data/data/cache`).

The textures are Rockstar's. Recolour them for your own server; don't sell them.
