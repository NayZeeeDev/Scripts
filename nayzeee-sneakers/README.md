# nayzeee-sneakers

Sneaker reselling for FiveM. This is **Phase 1**: the shoes, the shoe boxes and wearing them.

> **Setting it up?** Read [HOW-TO-USE.md](HOW-TO-USE.md) first.

| Phase | Status |
|---|---|
| 1. Core: shoe items, boxes with the float-in sequence, inspect, wear | **this build** |
| 2. Shoe props: converting clothing YDDs into props | Prada Cups done (5 colourways) |
| 3. Crafting table, materials, fake quality, XP | next |
| 4. Dirt and cleaning | |
| 5. Selling: phone apps, NPC meetups, legit checks, cinematic sell, dispatch | |

## Supported

- **Frameworks:** Qbox, QBCore and ESX, picked automatically (`Config.Framework`).
- **Inventories:** ox_inventory and qb-inventory (plus ps-inventory and lj-inventory). Anything else goes through `bridge/custom/inventory.lua`.
- **Target:** ox_target.
- **Requires** ox_lib.

## Items

| Item | What it is |
|---|---|
| `nz_shoes` | A loose pair. It carries `shoe`, `size`, `real`, `quality`, `condition`, `dirt` and `serial` |
| `nz_shoebox` | A pair in its box (same data) |
| `nz_shoebox_empty` | An empty box (stackable) |

With ox_inventory each pair also gets its own `label`, `description` and `image` (the colourway icon), so a Mint pair looks like a Mint pair in the inventory.

Serials look like `NZ-7F3K2Q8M`. On real pairs the last character is a valid check digit, and on fakes it isn't. `Shared.SerialValid(serial)` checks it, and the legit-check features in the selling phase will use this.

## How the box works

The box base is a networked object. Its state bag holds `nzs:open`, `nzs:shoe`, `nzs:busy` and `nzs:fx`.

Each client spawns the lid and the shoes as its own local objects and animates them from that state:
- the lid opens with a small overshoot and closes with a bounce
- the shoes float down with a gentle sway and fade-in, and float up and fade out when taken

The server runs each sequence: open, float, store, close. So every player sees the same thing, and the inventory changes happen only once the animation has finished.

## Props

| Model | What it is |
|---|---|
| `nzs_box` / `nzs_box_lid` | 33 × 28 × 15 cm box. The lid's origin is on the hinge `(0, -0.14, 0.15)` |
| `nzs_cups_black` / `_mint` / `_lime` / `_pink` / `_blue` | Prada Cups, packed heel-to-toe in box layout, 24k triangles, 1024 texture embedded |

How they were made:
- The shoes were converted from `feet_000_u.ydd` with the tools in `tools/`: read with CodeWalker.Core, de-skinned, reduced from 124k to 24k triangles in Blender with the UV seams locked, then arranged for the box.
- The box was built with `sneaker_box/tools/shoebox-prop-tool.html`.
- Every `.ydr` and `.ytyp` was compiled by CodeWalker's own XML importer.

## Exports

**Server**

```lua
exports['nayzeee-sneakers']:SpawnBox(coords, heading, meta?, ownerSrc?)  -- place a box, returns the net id
exports['nayzeee-sneakers']:PackInto(netId, meta)                        -- shoes float into a placed empty box
exports['nayzeee-sneakers']:GetWorn(src)                                  -- { meta, prev } or nil
exports['nayzeee-sneakers']:SetWornMeta(src, meta)                        -- update the worn pair (e.g. dirt)
```

**Client**

```lua
exports['nayzeee-sneakers']:Inspect(meta)   -- inspect view for any pair
exports['nayzeee-sneakers']:TakeOff()
```

## Adding an inventory

Set `Config.Inventory = 'custom'` and fill in the six functions in `bridge/custom/inventory.lua`: `Add`, `Remove`, `GetSlot`, `List`, `CanCarry` and `RegisterUsable`. The inventory must store per-item metadata.

## Folder layout

```
config/        config.lua (settings, text), shoes.lua (catalogue)
bridge/        framework, inventory and target adapters
client/        boxes, shoes (inspect/wear), camera + animations, NUI wrapper
server/        items, boxes, wear, admin commands
web/           NUI: menus, inspect card, notifications
stream/        nzs_box, nzs_cups
install/       item definitions for ox / qb, inventory icons
tools/         propkit (Python) + CodeWalker import/export tools used to build the props
```
