# NayZeee Sneaker Studio

> **Most servers don't need to run this by hand.** The same program ships inside nayzeee-sneakers as
> `tools/sneakerkit`, and the server runs it itself when it starts (and from **/sneakerstudio > 3D props**).
> See *Server mode* below. Use the app when you'd rather convert on your PC.

Turns the shoes already on your server into props for **nayzeee-sneakers**. Point it at your server
folder and it finds every shoe in your clothing packs, then makes a prop per colourway (packed to sit
in its shoe box), two inventory icons each (loose and boxed), and a ready-to-start resource:
**nayzeee-sneakers-props**.

No CodeWalker, no Blender, no editing XML. Everything happens on your PC; nothing is uploaded.

## Using it

1. Double-click **NayZeee Sneaker Studio.exe**. A small window opens (keep it open) and the studio
   opens in your browser.
2. **Server folder:** pick your server's `resources` folder (Browse, or paste the path). Press
   **Scan for shoes**.
3. Every shoe shows up as a card with a preview. **New** and **Changed** ones are already selected.
   Give them names (or change them in game later), and change the box size if you like.
4. Press **Convert**. With **Copy icons to the inventory** on, the icons also go into
   ox_inventory / qb-inventory.
5. On the server:
   ```
   ensure nayzeee-sneakers-props
   ensure nayzeee-sneakers
   ```
   Restart, then type **/sneakerstudio** in game to price the new shoes and switch them on.

Added or removed clothing packs? Scan again. Only new and changed shoes are converted, and props
for shoes that are gone are removed. Your names and the in-game settings stay.

## What it does to each shoe

| Step | |
|---|---|
| Find | Files named like `mp_m_freemode_01_mypack^feet_007_u.ydd` with their `feet_diff_007_a_uni.ytd` colourways. Base-game replacements and plain downloads (`feet_000_u.ydd`) are found too. |
| Clean | Bare skin on open-toe heels and see-through cut-outs are removed, so the prop doesn't show a foot. |
| Lighten | Meshes over the triangle budget (24k by default) are reduced; UV seams stay put so textures don't smear. |
| Pack | The pair is split and packed for the smallest box it fits: sneakers upright heel-to-toe in a shoe box, heels and tall boots on their side, nested, in a heel or boot box. |
| Build | One prop per colourway with its texture built in (no `.ytd` needed) and box collision, plus a `.ytyp`. Built by CodeWalker's own importer and loaded back to check. |
| Icons | A loose icon and a boxed icon (open box, pair inside) per colourway, 256 × 256. |
| Names | Colourways get a name from the colours that change between them ("Black / Red", "Mint"). Rename them in game. |

## The output

```
nayzeee-sneakers-props/
├── fxmanifest.lua        rewritten every run
├── catalogue.json        what nayzeee-sneakers reads: names, colours, which drawable, box size
├── icons/                nzs_<shoe>_<letter>.png and _box.png
└── stream/<shoe>/        nzs_<shoe>_<letter>.ydr (one per colourway) and nzs_<shoe>.ytyp
```

## Good to know

- **Plain downloads** (not named for streaming) convert fine, but the studio can't tell which
  drawable they are on your server. Pick it in game: `/sneakerstudio`, open the shoe, **Drawable**.
- **Texture size** 512 is a good default. 1024 looks sharper close up and costs players more to stream.
- **Command line:** `"NayZeee Sneaker Studio.exe" convert <server folder> <output folder>` converts
  everything new or changed without the browser. `scan <server folder>` just lists what it finds.
- Settings are saved next to the exe in `studio-settings.json`.

## Server mode (sneakerkit)

nayzeee-sneakers starts it from `server/sneakerkit.js` with every started resource listed in a roots file, and reads
the `@{json}` lines it prints:

```
sneakerkit scan  --out <props resource> --roots-file <file>          what's new, changed or gone
sneakerkit build --out <props resource> --roots-file <file> [--all]  convert new + changed (or all), remove gone
   options: --tex 256|512|1024   --icons <inventory image folder>   --keep <folder of in-game photos>
```

Plain downloads are skipped in server mode (they aren't on the server as-is). Icons that have an in-game photo
of the same name in `--keep` are never overwritten in the inventory.

## Building from source

A .NET 8 console app. It needs CodeWalker.Core (https://github.com/dexyfex/CodeWalker): clone it
next to this folder, or point `CodeWalkerDir` at it.

```
dotnet build -c Release -p:CodeWalkerDir=C:\path\to\CodeWalker
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true ^
  -p:EnableCompressionInSingleFile=true -p:CodeWalkerDir=C:\path\to\CodeWalker -o publish
```

For the server builds, publish for `linux-x64` and `win-x64` the same way and rename the output to
`sneakerkit` / `sneakerkit.exe` (in `nayzeee-sneakers/tools/sneakerkit/<rid>/`).

The web page (`web/`) and the three box props (from `nayzeee-sneakers/stream`, used for the boxed
icons) are built into the exe. BC7 textures are decoded with a port of bcdec (MIT); mesh reduction
follows Fast Quadric Mesh Simplification (MIT).
