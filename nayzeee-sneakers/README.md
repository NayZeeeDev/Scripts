# nayzeee-sneakers

Sneaker reselling for FiveM. Done so far: the shoes, the shoe boxes, wearing them, and crafting.

> **Setting it up?** Read [HOW-TO-USE.md](HOW-TO-USE.md) first.

| Phase | Status |
|---|---|
| 1. Core: shoe items, boxes with the float-in sequence, inspect, wear | **done** |
| 2. Shoe props: converting clothing YDDs into props | **done**: 10 models, 107 colourways, 3 box sizes, logos removed |
| 3. Crafting tables (Dragons Lab), materials, supplier, fake quality, XP | **this build** |
| 4. Dirt and cleaning | next |
| 5. Selling: phone apps, NPC meetups, legit checks, cinematic sell, dispatch | |

## Supported

- **Frameworks:** Qbox, QBCore and ESX, picked automatically (`Config.Framework`).
- **Inventories:** ox_inventory and qb-inventory (plus ps-inventory and lj-inventory). Anything else goes through `bridge/custom/inventory.lua`.
- **Target:** ox_target.
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

With ox_inventory each pair also gets its own `label`, `description` and `image` (the colourway icon), so a Mint pair looks like a Mint pair in the inventory.

Serials look like `NZ-7F3K2Q8M`. On real pairs the last character is a valid check digit, and on fakes it isn't. `Shared.SerialValid(serial)` checks it, and the legit-check features in the selling phase will use this.

## How crafting works

- **Tables** are saved on the server (KVP) as positions only. Each client spawns them itself, using Dragons Lab's model when it has her pack.
- **A craft** runs in two calls. `craftStart` checks the table, level, materials and room; the client then plays the stages
  (first-person camera, work animation, the pair fading in on the table, ox_lib skill checks); `craftFinish` checks the
  timing and distance again, takes the materials and gives the pair. Cancelling or leaving takes nothing.
- **Fake quality** = base + level bonus + clean checks − failed checks, ± a little luck (`Config.Crafting.fakeQuality`).
- **XP** is saved per character (KVP) with levels in `Config.XP.levels`.

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
  same cleaned textures went into the **debranded clothing pack**, shipped separately.
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
```

**Client**

```lua
exports['nayzeee-sneakers']:Inspect(meta)   -- inspect view for any pair
exports['nayzeee-sneakers']:TakeOff()
```

## Adding an inventory

Set `Config.Inventory = 'custom'` and fill in the seven functions in `bridge/custom/inventory.lua`: `Add`, `Remove`, `GetSlot`, `List`, `Count`, `CanCarry` and `RegisterUsable`. The inventory must store per-item metadata.

## Folder layout

```
config/        config.lua (settings, text), shoes.lua (catalogue), crafting.lua (tables, materials, recipes, XP, supplier)
bridge/        framework, inventory and target adapters
client/        boxes, shoes (inspect/wear), tables, crafting + supplier, camera + animations, NUI wrapper
server/        items, boxes, wear, tables, crafting + supplier, XP, admin commands
web/           NUI (NAYZEEE UI v5): menus, inspect card, workbench, supply shop, crafting progress, notifications. No icon font: icons are inline SVG
stream/        the three boxes and one folder per shoe model
install/       item definitions for ox / qb, inventory icons
tools/         propkit (Python) + CodeWalker import/export tools used to build the props (see tools/README.md)
```
