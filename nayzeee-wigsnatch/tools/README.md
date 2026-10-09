# tools/

Build tools for the props. Nothing here runs on the server.

| Path | What it does |
| --- | --- |
| `props/build.py` + `props/mesh.py` | Builds the script's own props (clippers, razor, dye bottle, foam head, generic wig, hair bundle) as CodeWalker XML + DDS. `python3 props/build.py out` |
| `props/hair2prop.py` | Turns a hairstyle (`.ydd` exported to XML) into a prop for the foam head: drops the skinning, centres it on the `SKEL_Head` bone, bakes its texture |
| `cwtool/` | A small .NET 8 tool on top of CodeWalker.Core (NuGet): `ydd2xml`, `ytd2dds`, `ydr2xml`, `xml2ydr`, `ytyp2xml`, `xml2ytyp`. Every compiled file is loaded back to check it |
| `convert-hair.sh` | All of the above for one hairstyle in one command |

## Converting a hairstyle

```bash
./convert-hair.sh hair_000_u.ydd hair_diff_000_a_uni.ytd nzw_m_150 ../../nzw_hairprops/stream
```

Then put `nzw_hairprops` next to this resource with an `fxmanifest.lua` like:

```lua
fx_version 'cerulean'
game 'gta5'
this_is_a_map 'yes'
data_file 'DLC_ITYP_REQUEST' 'stream/nzw_hair.ytyp'
```

and point the hairstyle at it in `Config.TableProps.HairPropMap` (or name it `nzw_<f|m>_<number>`).
