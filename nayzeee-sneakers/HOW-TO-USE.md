# nayzeee-sneakers: How To Use It (Phase 1)

Phase 1 covers the shoes themselves: shoe items, shoe boxes, inspecting a pair and wearing it.
Crafting, XP, dirt and cleaning, and selling come in the next phases.

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
5. **Let admins use the test commands.** In `server.cfg`:
   ```
   add_ace group.admin nayzeee-sneakers.admin allow
   ```
6. Restart the server, then **close FiveM and clear your cache**.

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
| Shoes or box show up invisible or inside-out | Screenshot it and send it to Claude. That's a model-file fix. |
