# tools/props/xml - CodeWalker sources of every streamed prop (committed)

Written by `build.py` after every **full-quality** build (not `--quick`) of an exported prop:

| File | What |
|---|---|
| `<name>.ydr.xml` | CodeWalker drawable XML (high + medium LOD, embedded textures, composite collision) |
| `<name>/` | its DDS textures (`<name>_d/_n/_s`, `_ad/_an/_as`, `_g`, `nzr_scr`), next to the XML as CodeWalker expects |
| `<name>.json` | the build manifest (bounds, archetype, anchors) - `nzr_props.ytyp.xml` and `shared/props_layout.lua` are rebuilt from these |
| `nzr_props.ytyp.xml` | one archetype per exported prop |

Convert them without rebuilding: `tools/props/convert.sh` (needs .NET 8), or the CodeWalker GUI route
described in `tools/props/convert.sh` / `tools/props/README.md`. The binaries go to
`nayzeee-radio-props/stream/`. Never edit these files by hand - change the prop module and rebuild.
