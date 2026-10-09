# nz_cpuchip – CPU chip prop for FiveM

A small streamed prop, `nz_prop_cpu_chip`, that looks like a desktop CPU (green
PCB substrate, nickel heat spreader with laser-etched markings, SMD capacitors,
gold LGA pads underneath). Made for PC-building / crafting scripts: use it as the
"CPU" component that goes inside a PC case, as a dropped item, or hold it in the
player's hand.

```
nz_cpuchip/
├─ fxmanifest.lua
├─ config.lua               item name, debug commands, hand offset, notify hook
├─ client/main.lua          spawn / hold / inspect exports + /cpuchip debug command
├─ server/main.lua          usable-item registration for qb-core / esx
├─ images/cpu_chip.png      inventory icon
└─ stream/
   ├─ nz_prop_cpu_chip.ydr  model (textures embedded, collision embedded)
   └─ nz_prop_cpu_chip.ytyp archetype definition
```

## Install

1. Drop the `nz_cpuchip` folder into your server's `resources/` directory.
2. Add `ensure nz_cpuchip` to `server.cfg`.
3. (Optional) add the inventory item, see below.
4. In game (while `Config.Debug = true`): `/cpuchip spawn` drops a chip in front of
   you, `/cpuchip hold` puts it in your hand, `/cpuchip drop` releases it,
   `/cpuchip clear` removes everything you spawned.

## Prop facts

| | |
|---|---|
| archetype / model name | `nz_prop_cpu_chip` (hash `0x658BCCC4`) |
| size | 5.0 cm × 5.0 cm × 0.52 cm, origin at the bottom centre |
| geometry | 256 triangles, 1 material (`normal_spec`) |
| textures | embedded: diffuse 1024² DXT1, normal 512² DXT5, specular 512² DXT1, full mip chains |
| collision | embedded composite with one box bound (PLASTIC material), dynamic |
| ytyp flags | `0` (dynamic prop – it falls / can be pushed). Use `32` if you want it static |

## Using it from your own scripts

```lua
-- client side
local obj = exports.nz_cpuchip:SpawnChip()                  -- in front of the player, with physics
local obj = exports.nz_cpuchip:SpawnChip(vector3(x, y, z), heading)
exports.nz_cpuchip:HoldChip()                               -- attach to right hand + inspect anim (loops)
exports.nz_cpuchip:ReleaseChip()                            -- detach / delete the held chip
exports.nz_cpuchip:InspectChip(3000)                        -- hold for 3 s, then put away
exports.nz_cpuchip:ClearChips()
```

Or just use the model name directly:

```lua
local model = `nz_prop_cpu_chip`
RequestModel(model) while not HasModelLoaded(model) do Wait(0) end
local chip = CreateObject(model, x, y, z, true, true, true)
```

Hand placement is tuned in `Config.Hold` (bone 28422 = right-hand prop bone). If
the chip sits oddly in a particular ped's hand, nudge `offset` / `rotation` there.

## Inventory item

### ox_inventory (`data/items.lua`)

```lua
['cpu_chip'] = {
    label = 'CPU Chip',
    weight = 50,
    stack = true,
    close = true,
    description = 'NAYZEE Core X9 desktop processor. Goes inside a PC.',
    client = {
        export = 'nz_cpuchip.cpu_chip',   -- plays the inspect animation, does not consume the item
    },
},
```

Copy `images/cpu_chip.png` to `ox_inventory/web/images/cpu_chip.png`.

### qb-core (`qb-core/shared/items.lua`)

```lua
['cpu_chip'] = { name = 'cpu_chip', label = 'CPU Chip', weight = 50, type = 'item', image = 'cpu_chip.png',
                 unique = false, useable = true, shouldClose = true,
                 description = 'NAYZEE Core X9 desktop processor. Goes inside a PC.' },
```

Copy `images/cpu_chip.png` to `qb-inventory/html/images/` (or your inventory's image folder).
`server/main.lua` registers the item as usable automatically when `qb-core` is running.

### ESX (SQL)

```sql
INSERT INTO items (name, label, weight) VALUES ('cpu_chip', 'CPU Chip', 1);
```

`server/main.lua` registers the item with `ESX.RegisterUsableItem` when `es_extended` is running.

## Editing the model

The model is fully generated from source in `tools/nz_cpuchip_builder/` (see the
README there). You get the CodeWalker XML + DDS textures and a `.glb` you can open
in Blender, so brand text, colours, size and shape can be changed and rebuilt.

## Notes

* Only `stream/` and the `data_file` line are needed for the prop itself; the Lua
  files are optional helpers and can be deleted if you only want the asset.
* The markings use a fictional brand ("NAYZEE Core X9") – no real trademarks.
