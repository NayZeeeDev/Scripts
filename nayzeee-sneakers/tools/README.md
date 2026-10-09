# Build tools

These tools built the props in `stream/`. You don't need them to run the script.

| Tool | What it does |
|---|---|
| `propkit/propkit.py` | Writes CodeWalker XML (`.ydr.xml` + texture folder, `.ytyp.xml`) from Python meshes |
| `propkit/clothing.py` | Reads the high-detail mesh out of a clothing `.ydd.xml` export |
| `propkit/decimate_blender.py` | Reduces a mesh's triangle count in Blender, with UV seams locked so textures don't smear |
| `propkit/arrange.py` | Splits a worn pair into left and right shoes and packs them heel-to-toe for a box |
| `propkit/render_blender.py` | Renders previews and inventory icons |
| `codewalker/export` | Reads `.ydd` / `.ytd` files with CodeWalker.Core and exports XML / DDS |
| `codewalker/import` | Runs CodeWalker's own XML importer, turning `.ydr.xml` / `.ytyp.xml` into game files |

The two CodeWalker tools are .NET 8 console apps. To build one: create a console project, reference
`CodeWalker.Core/CodeWalker.Core.csproj` from https://github.com/dexyfex/CodeWalker, and drop in the
`Program.cs`. CodeWalker.Core targets .NET Standard 2.0, so it builds and runs on Linux too.

The Blender scripts need Blender 4.2 or newer, or the `bpy` Python module.
