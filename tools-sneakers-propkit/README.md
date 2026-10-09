# Build tools

These tools built the props in `nayzeee-sneakers/stream/` and the debranded clothing pack. They are not part of the
resource (nothing here ships to customers, and the props are escrow locked).

| Tool | What it does |
|---|---|
| `propkit/propkit.py` | Writes CodeWalker XML (`.ydr.xml` + texture folder, `.ytyp.xml`) from Python meshes, crops a texture to the part the UVs use |
| `propkit/clothing.py` | Reads a mesh (any drawable, any LOD) out of a clothing `.ydd.xml` export |
| `propkit/skin.py` | Strips the bare-foot skin and see-through triangles out of open-toe heels |
| `propkit/decimate_blender.py` | Reduces a mesh's triangle count in Blender, with UV seams locked so textures don't smear |
| `propkit/arrange.py` | Splits a worn pair into left and right shoes and packs them for a box: sneakers heel-to-toe, heels and boots on their side, nested |
| `propkit/debrand.py` | Removes logos from clothing textures (inpaint printed logos, flatten embossed ones, diffuse and normal map) |
| `propkit/specs/` | The debrand settings used for each branded pack, as examples for new ones |
| `propkit/render_blender.py` | Renders previews and inventory icons |
| `propkit/material_icons.py` | Models and renders the crafting material icons |
| `propkit/displays.py` | Models the clear display cases (three sizes, side door, glass_pv acrylic with frosted edges) as CodeWalker XML |
| `propkit/render_displays.py` | Renders the display case preview and the three item icons |
| `codewalker/export` | Reads `.ydd` / `.ytd` / `.ytyp` files with CodeWalker.Core: `inspect`, `ydd2xml`, `ytd2dds`, and `ytdreplace` (puts cleaned textures back into a `.ytd`, keeping names and flags) |
| `codewalker/import` | Runs CodeWalker's own XML importer, turning `.ydr.xml` / `.ytyp.xml` into game files, then loads them back to check them |

## Adding a new shoe

1. `export ydd2xml feet_XXX_u.ydd work/` and `export ytd2dds` for each colourway's `.ytd`.
2. If it has logos: write a spec like the ones in `propkit/specs/`, run `debrand.py spec.json`, then
   `export ytdreplace` to make debranded `.ytd` files for the clothing.
3. Read the mesh with `clothing.py`, strip skin with `skin.py` (heels), decimate if it's over ~25k triangles,
   arrange it with `arrange.py`, and write the props with `propkit.py`.
4. Run `import` on the output folder, render icons with `render_blender.py`, and add the model to `config/shoes.lua`.

## Building

The two CodeWalker tools are .NET 8 console apps. To build one: create a console project, reference
`CodeWalker.Core/CodeWalker.Core.csproj` from https://github.com/dexyfex/CodeWalker, and drop in the
`Program.cs`. CodeWalker.Core targets .NET Standard 2.0, so it builds and runs on Linux too.

The Python tools need `numpy`, `pillow` and (for `debrand.py`) `opencv-python-headless`.
The Blender scripts need Blender 4.2 or newer, or the `bpy` Python module.
