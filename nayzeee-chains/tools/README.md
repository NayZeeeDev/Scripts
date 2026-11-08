# tools/

| Path | What it does |
| --- | --- |
| `chainkit/` | **The converter.** Turns chain clothing (`.ydd` + `_diff_` `.ytd` textures) into props for this script. The studio's Convert tab runs it for you (server/chainkit.js). |
| `chainkit/linux-x64/chainkit`, `chainkit/win-x64/chainkit.exe` | The ready-to-run programs (in the release zip). No .NET install needed |

## chainkit

```text
chainkit scan  --out <nayzeee-chainprops> [--drop folder]... [--roots-file f] [root ...]   what's new / changed / gone
chainkit build --out <nayzeee-chainprops> [--all] [--tex 1024] [--icons 256] [--lod 60] [--comps teef] [--drop folder]... [root ...]
chainkit icons --out <nayzeee-chainprops> [--icons 256]                                       draw the icons again
```

- `--drop folder`: every `.ydd` in it, its textures next to it. The folder name is the chain's name.
- `root ...`: server resources; finds `mp_[m|f]_freemode_01[_pack]^teef_###_u.ydd` and its `^teef_diff_###_x_*.ytd`.
  These keep gender / pack / number (`m|pack|3`) so a chain worn as clothing maps to its prop.
- Strips the rigging, centres the pivot on the mesh (remembers where it sat on the body), keeps the normal and
  specular maps (`normal_spec` / `spec` / `default`), DXT5 with mips, one `.ydr` per texture letter, one
  `nzc_chains.ytyp`, `chainmap.json`, and a 3/4 view PNG per prop (software rendered). Every file is loaded back
  to check it. Only new / changed chains are rebuilt; props of removed chains are deleted.

Build it with the .NET 8 SDK:

```bash
cd tools/chainkit
FLAGS="--self-contained -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:PublishTrimmed=true -p:TrimMode=partial -p:DebugType=none"
dotnet publish -c Release -r linux-x64 $FLAGS -o linux-x64
dotnet publish -c Release -r win-x64   $FLAGS -o win-x64
```
