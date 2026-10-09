# nayzeee-sneakers: How To Use It

This covers the shoes themselves (shoe items, shoe boxes, inspecting a pair and wearing it) and
crafting (tables, materials, the supplier, fakes and XP). Dirt and cleaning, and selling, come next.

---

## 1. Install

1. Put the `nayzeee-sneakers` folder in your `resources`.
2. In `server.cfg`, start it **after** ox_lib, your framework, your inventory and ox_target:
   ```
   ensure ox_lib
   ensure ox_target
   ensure nayzeee-sneakers
   ```
3. **Add the items** to your inventory:
   - **ox_inventory** (Qbox, ESX, or QB with ox): paste `install/ox_items.lua` into `ox_inventory/data/items.lua`.
   - **qb-inventory** (also ps-inventory and lj-inventory): paste `install/qb_items.lua` into `qb-core/shared/items.lua`.
4. **Add the icons**: copy everything in `install/images/` into
   - `ox_inventory/web/images/` for ox, or
   - `qb-inventory/html/images/` for qb.

   With ox, every colourway shows its own icon. qb uses one icon per item.
   The table icons (`blueshoetable.png` and the others) come with the Dragons Lab pack, in its `install-images` folder.
5. **Let admins use the test commands.** In `server.cfg`:
   ```
   add_ace group.admin nayzeee-sneakers.admin allow
   ```
6. **Crafting tables:** install the **Dragons Lab Shoe Table Pack** (see section 5).
7. Restart the server, then **close FiveM and clear your cache**.

> **ESX:** you need ox_inventory. ESX's default inventory can't store the per-pair details (size, serial, real/fake).

---

## 2. The shoes

All the shoes are already built as props, so you can box and inspect every pair straight away.
Every name is generic, with no real brands. Rename anything in `config/shoes.lua`.

| Model | Shoe ids | Box | For |
|---|---|---|---|
| Cup Runner | `cup_a` … `cup_e` | shoe box | male |
| Fang 5 | `fang5_a` … `fang5_o` | shoe box | male |
| Backcourt Low | `court_a` … `court_c` | shoe box | male |
| Stack Trainer | `stack_a`, `stack_b` | shoe box | male |
| Crevis 95 | `crevis_a` … `crevis_i` | shoe box | male |
| Alice Western Boot | `alice_a` … `alice_z` | boot box | female |
| Bianca Heel | `bianca_a` … `bianca_r` | heel box | female |
| Maisie Slingback | `maisie_a` … `maisie_p` | heel box | female |
| Omnia Ankle Boot | `omnia_a` … `omnia_i` | heel box | female |
| Mia Knee Boot | `mia_a` … `mia_d` | boot box | female |

The letter is the colourway: the same letter as the clothing texture it came from (`_a_`, `_b_` …).
Each colourway's name (for example "Fang 5 'Navy'") is in `config/shoes.lua`.

### Three box sizes
Sneakers go in a **shoe box**, heels and ankle boots in a **heel box**, and tall boots in a **boot box**.
Each has its own empty-box item: `nz_shoebox_empty`, `nz_heelbox_empty` and `nz_bootbox_empty`.
A pair only fits the size it's made for.

---

## 3. Make the shoes wearable

For each model, the script needs to know where that shoe sits in your clothing pack:

1. **Use the debranded clothing files.** For the four branded packs (Cup Runner, Fang 5, Backcourt Low, Stack Trainer), stream the files from the **debranded clothing pack** instead of the originals. They have the logos removed and keep the same file names, so they replace the originals one for one.
2. In game, open your clothing menu, go to **Shoes**, find the shoe and note its **drawable number**.
3. Put that number in `drawable = …` for that model in `config/shoes.lua`:
   ```lua
   fang5 = {
       label = 'Fang 5', gender = 'male', box = 'shoe', retail = 420,
       drawable = 87,   -- whatever number your clothing menu shows
   ```
   One number per model is enough. The colourway letters map to the textures automatically.
4. Check `gender`. The sneakers are set to male and the heels and boots to female. Change any that don't match your pack.

Until a drawable is set, the server console lists which models can't be worn yet.

---

## 4. Try it in game

| Command | What it does |
|---|---|
| `/givesneakers` | Lists the shoe ids |
| `/givesneakers [your id] fang5_c 10` | A real pair of Fang 5 'Navy', US 10 |
| `/givesneakers [your id] bianca_a 7 1` | A **fake** pair (the `1` makes it fake) |
| `/givesneakers [your id] alice_b 8 0 1` | A real pair **already in its box** |
| `/giveshoebox [your id] 3` | 3 empty shoe boxes |
| `/giveshoebox [your id] 2 heel` | 2 empty heel boxes (`shoe`, `heel` or `boot`) |

### Using a pair of shoes (from your inventory)
Use the **Shoes** item and pick from the menu:
- **Inspect**: the pair appears in front of your eyes. Hold left mouse and drag to turn it, scroll to zoom, and press Backspace to put it away.
- **Put them on**: you kneel, the camera looks at your feet, and the shoes go on. To take them off, type `/shoesoff`.
- **Box them up** (needs the right empty box): the box goes down, the lid opens, the shoes float in and the lid closes.

### Using a box
Use **Boxed shoes** or an **empty box** from your inventory to put it on the ground in front of you. Then target it:

| Option | What happens |
|---|---|
| **Open lid / Close lid** | The lid swings open or shut |
| **Take shoes out** | The shoes float up into your hands |
| **Put shoes in** | You get a list of the pairs that fit this box. They float down and the lid closes |
| **Pick up box** | You get the box back, with the shoes still inside if there are any |

---

## 5. Crafting

### The tables (Dragons Lab Shoe Table Pack)
The crafting tables are made by **SasDragon (Dragons Lab)**. They are **not included** in this script:
every server buys the **Shoe Table Pack** from her ([her Discord](https://discord.com/invite/KEhZqcuv6m)) and installs it.

1. Put her `DragonsLab_ShoeTablePack` folder in your `resources` and `ensure` it.
2. Copy the PNGs from her `install-images` folder into your inventory's images folder.
3. The four table items (`blueshoetable`, `pinkshoetable`, `purpleshoetable`, `redshoetable`) are already in `install/ox_items.lua` and `install/qb_items.lua`.
   If you already added her table items from her own guide, keep yours and just add
   `server = { export = 'nayzeee-sneakers.useItem' }` to each one (ox).

Without her pack the tables show up as a plain GTA workbench, and the console says where to buy hers.
Set `Config.Tables.fallback = false` to turn tables off completely without her pack.

**Using a table:** use the table item, aim where you want it (scroll or Q / E turns it), left-click to place, right-click to cancel.
Target it to **Use shoe table** or **Pick up table**. Placed tables stay after a restart.
Want a table that's always there, like in a shop? Add it to `Config.Tables.fixed` in `config/crafting.lua`.

### Materials and the supplier
The **Shoe supplies** guy (clipboard icon on the map, Legion Square by default) sells everything:
leather, mesh fabric, rubber soles, heel blocks, thread, glue, laces and **authentic tags**.
Move him with `Config.Supplier.coords`. Prices are in `Config.Materials`.

### Making a pair
1. Target your table and pick **Use shoe table**.
2. At the top choose **Fake** or **Real**. Real pairs need an authentic tag and level 4.
3. Pick a shoe, a colourway and a size. The panel shows what you have and what you're missing.
4. **Make this pair.** You walk up to the table and work in first person while the pair builds up in front of you, stage by stage.
   Some stages have a skill check. Press **X** to stop; you keep your materials, since they're only used up when the pair is done.

The finished pair goes in your inventory, brand new (Deadstock). Its card shows how it came out.

### Fakes and quality
Every fake has a **quality** (10–97%): how convincing it is. Higher level, and clean skill checks, make better fakes; a failed check costs quality.
Real pairs are always 100%. Selling (next phase) uses quality for the NPC legit checks.

### XP and levels
Every pair gives XP (more for real pairs, a bonus for no failed checks). Levels unlock more shoes, real pairs at level 4,
and make you work faster (4% per level). Tune it all in `config/crafting.lua`.

| Command | What it does |
|---|---|
| `/givematerials [your id] 3` | Enough of every material for 3 pairs of anything (real or fake) |
| `/sneakerxp [your id] 600` | Give 600 XP (level 4). No amount shows their XP |

---

## Good to know

- **Fakes look identical.** The difference is in the item data and the serial number. Legit checks come with selling.
- **Nothing gets lost.** If a player leaves or the script restarts while shoes are sitting in a placed box, the box goes back to them, now or the next time they log in.
- **Wearing persists** across logins.
- **The close-up camera** can be turned off with `Config.FirstPerson = false`.

## When it goes wrong

| Problem | Fix |
|---|---|
| Console says *Shoe box model is not streamed* | Make sure the `stream/` folders are in the resource, then clear your client cache. |
| Using an item does nothing | The item isn't set up in your inventory (Install, step 3), or for ox the `server = { export = 'nayzeee-sneakers.useItem' }` line is missing. |
| *These need a heel box* (or similar) | That pair fits a different box size. Use the matching empty box. |
| *This shoe has no clothing set up yet* | Set the model's `drawable` in `config/shoes.lua` (section 3). |
| *These are not made for your character* | The model's `gender` doesn't match your ped. Fix `gender`, or set `Config.GenderLock = false`. |
| Tables are plain workbenches | The Dragons Lab pack isn't running, or that player's cache is old. `ensure` it and clear the cache. |
| The shoes float above / sink into the table while crafting | Change `Config.Tables.surface` (the table-top height) in `config/crafting.lua`. |
| Shoes or box show up invisible or inside-out | Screenshot it and send it to Claude. That's a model-file fix. |
