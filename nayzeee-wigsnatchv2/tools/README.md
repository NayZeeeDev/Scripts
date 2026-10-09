# tools/

| Path | What it does |
| --- | --- |
| `hairkit/` | **3D wigs.** Turns every hairstyle your server streams into a prop for the foam head on the wig tables. The Wig Studio runs it for you (server/hairkit.js); you never have to touch it. |
| `hairkit/linux-x64/hairkit`, `hairkit/win-x64/hairkit.exe` | The ready-to-run programs (in the release zip). No .NET install needed |
| `props/icons.py` | Renders every item icon in `INSTALL/images` from 3D models (256 px, three-quarter view, studio light): `python3 props/icons.py out` |
| `props/build.py` + `props/mesh.py` | Builds this script's own props (clippers, razor, dye bottle, foam head, generic wig, hair bundle) as CodeWalker XML + DDS |
| `cwtool/` | A small CodeWalker.Core tool for prop work: `ydr2xml`, `xml2ydr`, `ydd2xml`, `ytd2dds`, `ytyp2xml`, `xml2ytyp` |

## hairkit

```text
hairkit scan  --out <nzw_hairprops> [--roots-file f] [root ...]   what's new / changed / gone
hairkit build --out <nzw_hairprops> [--all] [--tex 256] [--roots-file f] [root ...]
hairkit game  --out <nzw_hairprops> --gta "<GTA V folder>"        base game + DLC hair (on a PC with GTA)
```

- Finds every `mp_[m|f]_freemode_01_<pack>^hair_###_u.ydd` (and its `^hair_diff_###_a_*.ytd`) in the given folders.
- Strips the ped rigging, centres the hair on the `SKEL_Head` bone (where the foam head's `point` is), keeps
  its texture (grey freemode textures get a natural dark brown, since a prop can't take the hair colour),
  uses a cut-out shader and both faces for see-through hair cards, and compiles a `.ydr` per hairstyle with
  CodeWalker, plus one `nzw_hair.ytyp`. Every file is loaded back to check it.
- `hairmap.json` records which prop belongs to which hairstyle (`m|mp_m_mypack|3`) and what it was made from,
  so the next run only rebuilds what changed and removes props whose hair is gone.

Build the programs from source with the .NET 8 SDK:

```bash
cd tools/hairkit
FLAGS="--self-contained -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:PublishTrimmed=true -p:TrimMode=partial -p:DebugType=none"
dotnet publish -c Release -r linux-x64 $FLAGS -o linux-x64
dotnet publish -c Release -r win-x64   $FLAGS -o win-x64
```
