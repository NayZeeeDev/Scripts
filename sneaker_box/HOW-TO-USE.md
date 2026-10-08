# Sneaker Box: How To Use It

There are two ways to get a shoe box into your server:

| | Who builds the box | What you do |
|---|---|---|
| **Path A** | Claude builds it and sends you a zip | Unzip it and drop it into your server. **No tool needed.** |
| **Path B** | You build it with the prop tool | Style it in the tool, import it in CodeWalker, drop it into your server. |

The lid animation is part of the script (`client.lua`). It's not a separate file, so it always comes with the resource. You never have to make or install an animation.

---

## Path A: Claude builds it for you

### 1. Ask for the box you want
Tell Claude:
- the **colours**: box, lid, inside and print (the colour of the text and logo)
- the **brand text** on the lid, plus the small print under it if you want any
- the **size**: Kids, Men's, Boot, or your own size in cm
- a **name**: lowercase and underscores only, e.g. `nz_shoebox_red`
- a **logo**, if you want one: upload the PNG in the chat

### 2. Drop it in
You get `sneaker_box.zip`.

1. Unzip it into your server's `resources` folder, so you have `resources/sneaker_box/`.
2. In `server.cfg`, add:
   ```
   ensure sneaker_box
   ```
3. Restart the server.
4. **Close FiveM completely and clear your cache.** FiveM keeps old models and will show you the old box if you skip this.

### 3. Try it in game
| Command / key | What it does |
|---|---|
| `/shoebox` | Puts a box on the ground in front of you |
| **E** (or ox_target) | Opens / closes the closest box |
| `/shoebox_delete` | Removes the closest box you placed |

That's it for Path A. You can skip the rest of this file.

---

## Path B: Build it yourself with the tool

Use this when you want to make a new colourway or size without waiting on anyone.

### 1. Open the tool
Open `tools/shoebox-prop-tool.html` in **Chrome or Edge** by double-clicking it. You need an internet connection because the page loads its 3D viewer from the web.

### 2. Set it up (right-hand panel, top to bottom)

| Section | What to do |
|---|---|
| **Prop name** | Type a unique name, e.g. `nz_shoebox_red`. The tool makes two models from it: `nz_shoebox_red` (the box) and `nz_shoebox_red_lid` (the lid). |
| **Colourway** | Click a preset, or set **Box**, **Lid**, **Inside** and **Print** yourself. |
| **Print** | The brand text and small print on the lid. **Use file…** adds a logo PNG. With no logo you get a round monogram. **End label size** and **Style code** go on the white sticker on the end of the box. |
| **Size** | Kids / Men's / Boot, or type your own length, width and height in cm. |
| **Textures & collision** | Leave it on **1024** and keep **box collision** ticked unless you have a reason to change them. |

The big 3D view on the left is exactly what you'll get in game:
- **Drag** to spin it, **scroll** to zoom.
- **Open** (bottom middle) swings the lid. The loop button next to it keeps it opening and closing.
- **Textured / Shaded / UV check** (top right) just change how the preview looks. They don't change what gets built.
- The **Guide** button (top left) has the full walkthrough and a fix-it table.
- **Reset** (red, bottom of the panel) puts everything back to the default orange box.

### 3. Build
Click **Build package**. You get `<name>.zip`. Unzip it and you'll see:

```
<name>\
    <name>.ydr.xml         the box
    <name>\                its texture  (leave this folder where it is)
    <name>_lid.ydr.xml     the lid
    <name>_lid\            its texture  (leave this folder where it is)
    <name>.ytyp.xml        tells the game both models exist
README.txt
fxmanifest-snippet.lua     one line for fxmanifest.lua
config-snippet.lua         three lines for config.lua
atlas-preview.png          what the texture looks like (just for you)
```

### 4. Turn the XML into game files (CodeWalker)
The game can't read `.xml` files, so CodeWalker converts them.

1. Open **CodeWalker → RPF Explorer**.
2. Browse to the unzipped `<name>` folder.
3. Right-click inside it → **Import XML**.
4. Select **all three** `.xml` files at once and import.
5. You now have `<name>.ydr`, `<name>_lid.ydr` and `<name>.ytyp`.

> **Don't move or rename the texture folders.** CodeWalker looks for a folder with the same name sitting right next to each XML. If you move it, you'll get `Texture file not found`.

### 5. Put them in the resource
Make a folder for the box in `sneaker_box/stream/` and put the three built files in it:

```
sneaker_box\stream\<name>\
    <name>.ydr
    <name>_lid.ydr
    <name>.ytyp
```
No `.ytd` is needed, because the texture is inside the `.ydr` files.

### 6. Point the script at the new box
**config.lua**: open `config-snippet.lua` from the zip and paste its three lines over the matching lines at the top of `sneaker_box/config.lua`:
```lua
Config.BaseModel = `<name>`
Config.LidModel = `<name>_lid`
Config.HingeOffset = vector3(...)   -- where the lid hinges; it changes with the size
```

**fxmanifest.lua**: replace the `data_file` line at the bottom with the one from `fxmanifest-snippet.lua`:
```lua
data_file 'DLC_ITYP_REQUEST' 'stream/<name>/<name>.ytyp'
```

### 7. Restart and test
Restart the server, **close FiveM and clear your cache**, then use `/shoebox` in game.

---

## Good to know

- **One box design at a time.** The script uses the models set in `config.lua`. To switch designs, change those lines and the `data_file` line. You can leave old box folders in `stream/`. They just won't be used.
- **The default box** is already in `stream/nz_shoebox/`. If you're happy with the orange box, you don't need the tool at all.
- **Only use logos you're allowed to use.**

## When it goes wrong

| Problem | Fix |
|---|---|
| `/shoebox` says the model isn't streamed | Check the `data_file` line in fxmanifest has the right path, the `.ytyp` is in that folder, and the names in `config.lua` match the `.ydr` filenames exactly. |
| `Texture file not found` in CodeWalker | A texture folder was moved or renamed. Unzip again and import from inside the `<name>` folder. |
| Lid floats above or sinks into the box | `Config.HingeOffset` doesn't match the size you built. Paste the config snippet from that build. |
| Box is invisible or looks inside-out | Screenshot it and send it to Claude. That's a model-file fix, not something you did wrong. |
| Still seeing the old box | FiveM cache. Close FiveM completely, delete the cache folder, relaunch. |
