# nayzeee-sneakers

Sneaker reselling for FiveM: make pairs (real or fake), wear them, keep them clean, and sell them to NPC buyers through a phone app, with a handover cinematic.

> **Setting it up?** Read [HOW-TO-USE.md](HOW-TO-USE.md) first.

| Phase | Status |
|---|---|
| 1. Core: shoe items, boxes with the float-in sequence, inspect, wear | **done** |
| 2. Shoe props: converting clothing YDDs into props | **done**: 10 models, 107 colourways, 3 box sizes, logos removed |
| 3. Crafting tables (Dragons Lab), materials, supplier, fake quality, XP | **done** |
| 4. Dirt, wear and cleaning | **done** |
| 5. Selling: Plug app on lb-phone, NPC meetups on foot or by car, legit checks, handover cinematic, dispatch, hype, rep | **done** |

## Supported

- **Frameworks:** Qbox, QBCore and ESX, picked automatically (`Config.Framework`).
- **Inventories:** ox_inventory and qb-inventory (plus ps-inventory and lj-inventory). Anything else goes through `bridge/custom/inventory.lua`.
- **Target:** ox_target, qb-target or interact (or a key prompt without one).
- **Phone:** selling runs on **lb-phone**: the Plug app is a custom app (`AddCustomApp`), buyers text through its Messages app.
- **Clothing:** the shoes you wear come from **[nayzeee-sneakers-clothing](../nayzeee-sneakers-clothing/)**, an addon pack
  (no base-game slots replaced). The script looks up each shoe's real drawable number from the pack at runtime,
  so nobody has to type drawable numbers in.
- **Dispatch:** ps-dispatch, cd_dispatch, qs-dispatch, rcore_dispatch, built-in, or your own.
- **Notifications:** the script's own, or nayzeee-notify, ox_lib, okok, ESX, QB.
- **Requires** ox_lib.
- **Crafting tables:** the [Dragons Lab Shoe Table Pack](https://discord.com/invite/KEhZqcuv6m) by SasDragon, bought separately from her. Not included; without it the tables fall back to a GTA workbench.

## Items

| Item | What it is |
|---|---|
| `nz_shoes` | A loose pair. It carries `shoe`, `size`, `real`, `quality`, `condition`, `dirt` and `serial` |
| `nz_shoebox` | A pair in its box (same data) |
| `nz_shoebox_empty` | An empty shoe box, for sneakers (stackable) |
| `nz_heelbox_empty` | An empty heel box, for heels and ankle boots |
| `nz_bootbox_empty` | An empty boot box, for tall boots |
| `blueshoetable` `pinkshoetable` `purpleshoetable` `redshoetable` | Crafting tables (Dragons Lab models). Use one to place it |
| `nz_leather` `nz_fabric` `nz_sole` `nz_heel` `nz_thread` `nz_glue` `nz_laces` | Crafting materials (stackable) |
| `nz_authtag` | Authentic tag: what makes a crafted pair real |
| `nz_cleaning_kit` | Cleans a pair. Has uses (metadata `uses`) |

With ox_inventory each pair also gets its own `label`, `description` and `image` (the colourway icon), so a Mint pair looks like a Mint pair in the inventory.

Serials look like `NZ-7F3K2Q8M`. On real pairs the last character is a valid check digit, and on fakes it isn't. `Shared.SerialValid(serial)` checks it, and the legit-check features in the selling phase will use this.

## How crafting works

- **Tables** are saved on the server (KVP) as positions only. Each client spawns them itself, using Dragons Lab's model when it has her pack.
- **A craft** runs in two calls. `craftStart` checks the table, level, materials and room; the client then plays the stages
  (first-person camera, work animation, the pair fading in on the table, ox_lib skill checks); `craftFinish` checks the
  timing and distance again, takes the materials and gives the pair. Cancelling or leaving takes nothing.
- **Fake quality** = base + level bonus + clean checks − failed checks, ± a little luck (`Config.Crafting.fakeQuality`).
- **XP** is saved per character (KVP) with levels in `Config.XP.levels`.

## How selling works

- **Offers** are made on the server from the pair's value (retail × hype × condition × dirt × box × size), the buyer type and
  the seller's rep, and expire after 10 minutes.
- **The handover is settled on the server** the moment it starts: whether the buyer checks, whether they run the serial, whether
  a fake gets spotted (`eye × (100 − quality)%`), the payment, XP, rep and any police call. The client then plays the cinematic
  for that result, so skipping or disconnecting can't change the outcome.
- **The cinematic** is the same camera work as nayzeee-vehiclecargo: one scripted camera that glides between shots and keeps
  looking at a moving subject (walk-up, two-shot handover, close-up check, verdict, the buyer leaving), with letterbox bars,
  subtitles and ENTER to skip.
- **Dirt** is measured on the client (distance, running, ground material, rain, water) and every report is capped on the server
  by the time since the last one.

## How the box works

The box base is a networked object. Its state bag holds `nzs:type` (shoe, heel or boot), `nzs:open`, `nzs:shoe`, `nzs:busy` and `nzs:fx`.

Each client spawns the lid and the shoes as its own local objects and animates them from that state:
- the lid opens with a small overshoot and closes with a bounce
- the shoes float down with a gentle sway and fade-in, and float up and fade out when taken

The server runs each sequence: open, float, store, close. So every player sees the same thing, and the inventory changes happen only once the animation has finished.

## Props

| Model | What it is |
|---|---|
| `nzs_box` / `nzs_box_lid` | Shoe box, 34 × 29 × 20 cm. The lid's origin is on its hinge |
| `nzs_box_heel` / `nzs_box_heel_lid` | Heel box, 41 × 30 × 12 cm |
| `nzs_box_boot` / `nzs_box_boot_lid` | Boot box, 52 × 51 × 16 cm |
| `nzs_<model>_<letter>` | One boxed pair per colourway, e.g. `nzs_fang5_c`. Each model has its own folder in `stream/` |

The ten models are listed in [HOW-TO-USE.md](HOW-TO-USE.md#2-the-shoes). Every name is generic; the
colourway names were picked from each texture's colours and can be renamed in `config/shoes.lua`.

How they were made:
- Each shoe was converted from its clothing `.ydd` with the tools in `tools/`: read with CodeWalker.Core,
  stripped of bare-foot skin (heels), reduced in Blender with the UV seams locked where needed, then packed
  for its box: sneakers heel-to-toe, heels and boots on their side and nested.
- Brand logos were removed from the textures (`tools/propkit/debrand.py`) before the props were built. The
  same cleaned textures went into the **debranded clothing files**, which go in nayzeee-sneakers-clothing.
- The boxes were built with `sneaker_box/tools/shoebox-prop-tool.html`.
- Every `.ydr` and `.ytyp` was compiled by CodeWalker's own XML importer and loaded back to check it.

## Exports

**Server**

```lua
exports['nayzeee-sneakers']:SpawnBox(coords, heading, meta?, ownerSrc?, boxType?)  -- place a box ('shoe'|'heel'|'boot'), returns the net id
exports['nayzeee-sneakers']:PackInto(netId, meta)                                  -- shoes float into a placed empty box of the right size
exports['nayzeee-sneakers']:GetWorn(src)                                           -- { meta, prev } or nil
exports['nayzeee-sneakers']:SetWornMeta(src, meta)                                 -- update the worn pair (e.g. dirt)
exports['nayzeee-sneakers']:GetXP(src)                                             -- total XP
exports['nayzeee-sneakers']:GetLevel(src)
exports['nayzeee-sneakers']:AddXP(src, amount)                                     -- returns total, level, levelled up
exports['nayzeee-sneakers']:GetRep(src)
exports['nayzeee-sneakers']:AddRep(src, amount)
exports['nayzeee-sneakers']:GetStats(src)                                          -- { rep, sold, earned, caught, fakesSold, made, cleaned }
```

**Client**

```lua
exports['nayzeee-sneakers']:Inspect(meta)   -- inspect view for any pair
exports['nayzeee-sneakers']:TakeOff()
```

## Adding an inventory

Set `Config.Inventory = 'custom'` and fill in the seven functions in `bridge/custom/inventory.lua`: `Add`, `Remove`, `GetSlot`, `List`, `Count`, `CanCarry` and `RegisterUsable` (and optionally `SetMetadata`). The inventory must store per-item metadata.

## Folder layout

```
config/        config.lua (systems, phone, dispatch, boxes, wearing, dirt, cleaning), shoes.lua (catalogue),
               crafting.lua (tables, materials, recipes, XP, supplier), selling.lua (buyers, meets, cinematic, hype, rep)
locales/       en.lua: every line of text
bridge/        framework, inventory, target, phone texts and dispatch adapters
client/        boxes, shoes (inspect/wear), dirt, cleaning, tables, crafting + supplier, selling, cinematic, Plug app, NUI wrapper
server/        items, boxes, wear, dirt + cleaning, tables, crafting + supplier, selling, XP, stats + hype + logs, admin commands
web/           NUI (NAYZEEE UI v5): menus, inspect card, workbench, supply shop, progress, cinematic, banner, deal HUD,
               and the Plug app (plug.html, loaded inside lb-phone). Lexend is bundled, icons are inline SVG
stream/        the three boxes and one folder per shoe model
install/       item definitions for ox / qb, inventory icons
tools/         propkit (Python) + CodeWalker import/export tools used to build the props (see tools/README.md)
```
