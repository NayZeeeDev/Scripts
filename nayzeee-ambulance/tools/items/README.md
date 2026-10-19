# Item and tool-belt pictures (`tools/items`)

Generates the inventory pictures in `html/img/items/<item>.png` (512 x 512) and the minigame
tool-belt pictures in `html/img/tools/<icon>.png` (256 x 256, plus `html/img/tools/index.json`).
Every picture is a three.js product render made in headless Chromium. The models are procedural JS,
and a few reuse the `.glb` exports of the props pipeline so they match the in-game props.
This is a dev folder and is never shipped.

| File | What |
|---|---|
| `render.mjs` | Node runner: serves the page, drives Chromium, writes raw 1024² frames, then runs `post.py` |
| `index.html`, `studio.js` | Studio: ACES tone mapping, sRGB output, RoomEnvironment/PMREM reflections, key + fill + rim lights, soft self-shadows, blurred contact shadow (depth-from-below), auto-framing (object about 80 % of the frame, 3/4 view from about 30° above) |
| `lib.js` | Materials (plastic, rubber, steel, glass with reflection-driven alpha, film, fabric …), procedural normal maps (weave, crepe, gauze, crinkled foil, knurl …), geometry helpers (lathe, strap/ribbon sweep, pillow bags, extrusions, wrapped labels, decals) |
| `labels.js` | Label and packaging artwork painted on canvases |
| `parts.js` | Shared parts: vial, ampoule, syringe, needles, IV cannula, rolls, hard case, fluid bag, sachet, peel pouch, instruments (hemostat, scalpel, forceps, scissors, suture needle) |
| `models/common.js` | Products used by both sets (bandage roll, gauze, saline bottle, contrast bottle, IV/blood bags, foil blanket, x-ray film, coil, ETT, Yankauer, dermatome, mesher, stapler, drain unit, defib pads) |
| `models/items.js` | One entry per `Config.Items` value in `config/items.lua`, plus `nza_unknown` |
| `models/tools.js` | One entry per physical ProcPanel tool icon (`tl.icon` in `html/apps/*`) |
| `post.py` | Premultiplied-alpha Lanczos downsample, PNG optimisation, contact sheets, `html/img/tools/index.json` |

## Re-render

Requirements: node 18 or newer, python3 with numpy and Pillow, and Chromium
(`/opt/pw-browsers/chromium`, or pass `--chromium` / set `NZA_CHROMIUM`).

```bash
# one-time: install three + playwright-core OUTSIDE the repo (the props pipeline's folder works too)
mkdir -p /tmp/nza-work/items && cp tools/items/package.json /tmp/nza-work/items/ && (cd /tmp/nza-work/items && npm install)

# everything: 49 items + 50 tools, 3-5 s each (5-10 minutes on 4 idle cores)
node tools/items/render.mjs

# only some pictures / one set
node tools/items/render.mjs --set items --only bandage,medikit
node tools/items/render.mjs --set tools --only syringe

# try changes without touching html/img: write to a scratch root instead
node tools/items/render.mjs --dest /tmp/nza-work/items/try --sheets /tmp/nza-work/items/sheets
```

`render.mjs` finds the node modules in `--modules`, `$NZA_MODULES`, `tools/items/node_modules`,
`/tmp/nza-work/items/node_modules` or `/tmp/nza-work/props/preview_node/node_modules`. Contact sheets
are written to `--sheets` (default `/tmp/nza-work/items/sheets`): `contact_items.png` and
`contact_tools.png`. Each cell has a 64 px inset, so you can check what the picture looks like at
inventory-slot size. Look at the sheets after every change.

### Props-pipeline models (glb)

These entries load `<glb dir>/<name>/<name>.glb` (default `--glb /tmp/nza-work/props/out`):
items `defibrillator, trauma_kit, ems_pager, tourniquet, pelvic_binder, splint, cervical_collar,
stethoscope, bvm, crutches, intubation_kit` (laryngoscope), and tools `drill, monitor, gauge, cuff,
tq-strap, collar, splint, stetho, us-probe, itb-bvm, itb-scope`. If that folder is missing, export the
glbs to a temp folder. **Leave out `--stream` and `--docs`, so `stream/` and the docs are not touched:**

```bash
python3 tools/props/build.py --no-convert --no-preview --out /tmp/nza-work/props/out \
    --only nz_amb_defib,nz_amb_kitcase_closed,nz_amb_pager,nz_amb_tourniquet,nz_amb_binder_worn,nz_amb_splint_arm,nz_amb_collar,nz_amb_stethoscope,nz_amb_bvm,nz_amb_crutch,nz_amb_laryngoscope,nz_amb_iodrill,nz_amb_monitor,nz_amb_infuser,nz_amb_us_probe
```

## Adding or changing a picture

* Items: add an entry under the item's inventory name (the `Config.Items` value) in
  `models/items.js`. The PNG name must equal the item name.
* Tools: add an entry under the `tl.icon` name in `models/tools.js`. `index.json` is rebuilt from
  the PNGs in `html/img/tools`.
* An entry is `{ view: { az, elev, fill, … }, build: async ({ loadGLB }) => Object3D }`. Model in
  centimetres, +Y up, front facing +Z. The studio sets the object on the floor and frames it.
  `az`/`elev` are the camera angles in degrees (default 3/4 from 30° above), `fill` is the share of
  the frame the object fills, and `shadow*`, `key`, `rim`, `env`, `exposure` tune a single shot.
* Labels: generic medical wording only. No brand names, no wordmarks or logos (ours included), and
  no copies of real packaging. A plain cross or the star of life is fine.

## Tool icons without a picture

These `tl.icon` names are UI glyphs or abstract actions, not physical tools, so they keep their
line icons: `check, x, plus, minus, arrow-l, arrow-r, arrow-up, arrow-down, rot-l, swap, sliders,
target, hand, walk, pulse, ecg, heart, lungs, bolt, battery, snow, br-rise, br-ban, as-neck,
as-wrist, as-ban`.

Extra pictures not used by any app yet: `cannula`, `needle-driver`, `scissors`, `us-probe`. They are
there for tools that now share `needle` / `forceps`.
