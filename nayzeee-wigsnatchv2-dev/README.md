# nayzeee-wigsnatchv2-dev (private, never ship this folder)

The sources behind Wig Snatch V2's props and tools. **None of this goes to customers.** The resource folder
(`nayzeee-wigsnatchv2/`) only carries the compiled props in `stream/` (encrypted by the Cfx escrow when
you upload it: they are not in `escrow_ignore`) and the compiled hairkit programs.

| Path | What it does |
| --- | --- |
| `props-source/` | CodeWalker XML + DDS of the props in `stream/` (clippers, razor, dye bottle, foam head, generic wig, hair bundle) and their previews |
| `props/build.py` + `props/mesh.py` | Builds those props: `python3 props/build.py props-source`, then `cwtool xml2ydr` / `xml2ytyp` into `../nayzeee-wigsnatchv2/stream/` |
| `props/icons.py` | Renders every item icon in `INSTALL/images` from 3D models (256 px, three-quarter view, studio light): `python3 props/icons.py out` |
| `cwtool/` | A small CodeWalker.Core tool for prop work: `ydr2xml`, `xml2ydr`, `ydd2xml`, `ytd2dds`, `ytyp2xml`, `xml2ytyp` |
| `hairkit/` | Source of **hairkit** (3D wigs). Publish it into `../nayzeee-wigsnatchv2/tools/hairkit/` (below) |

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

Double-clicked (no arguments) it asks for the GTA V folder and runs `game` into the `nzw_hairprops` folder
next to the resource.

Build the programs with the .NET 8 SDK, straight into the resource:

```bash
cd hairkit
FLAGS="--self-contained -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:PublishTrimmed=true -p:TrimMode=partial -p:DebugType=none"
dotnet publish -c Release -r linux-x64 $FLAGS -o ../../nayzeee-wigsnatchv2/tools/hairkit/linux-x64
dotnet publish -c Release -r win-x64   $FLAGS -o ../../nayzeee-wigsnatchv2/tools/hairkit/win-x64
```
