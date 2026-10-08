# nz_sneakers: How To Use It (Phase 1)

Phase 1 covers the shoes themselves: shoe items, shoe boxes, inspecting a pair and wearing it.
Crafting, XP, dirt and cleaning, and selling come in the next phases.

---

## 1. Install

1. Put the `nz_sneakers` folder in your `resources`.
2. In `server.cfg`, start it **after** ox_lib, your framework, your inventory and ox_target:
   ```
   ensure ox_lib
   ensure ox_target
   ensure nz_sneakers
   ```
3. **Add the items** to your inventory:
   - **ox_inventory** (Qbox, ESX, or QB with ox): paste `install/ox_items.lua` into `ox_inventory/data/items.lua`.
   - **qb-inventory** (also ps-inventory and lj-inventory): paste `install/qb_items.lua` into `qb-core/shared/items.lua`.
4. **Add the icons**: copy everything in `install/images/` into
   - `ox_inventory/web/images/` for ox, or
   - `qb-inventory/html/images/` for qb.
5. **Let admins use the test commands.** In `server.cfg`:
   ```
   add_ace group.admin nz_sneakers.admin allow
   ```
6. Restart the server, then **close FiveM and clear your cache**.

> **ESX:** you need ox_inventory. ESX's default inventory can't store the per-pair details (size, serial, real/fake).

---

## 2. Make the shoes wearable

The Prada Cups props are already built and streamed, so you can box them and inspect them straight away.

To **wear** them, the script needs to know where the shoe sits in your clothing pack:

1. Make sure the Prada Cups clothing (`feet_000_u.ydd` + the 5 `.ytd` files) is streamed on your server as addon clothing.
2. In-game, open your clothing menu, go to **Shoes** and find the Prada Cups. Note the **drawable number**.
3. Open `config/shoes.lua` and put that number in `drawable = ...` for all 5 colourways:
   ```lua
   clothing = { drawable = 87, texture = 0 },   -- 87 = whatever number your clothing menu shows
   ```
   The `texture` numbers (0 to 4) are already set: Black, Mint, Lime, Pink, Blue.
4. If these are **female** shoes, change `gender = 'male'` to `gender = 'female'` on each one.

Until a drawable is set, the server console tells you which shoes can't be worn yet.

---

## 3. Try it in game

Give yourself some shoes and an empty box:

| Command | What it does |
|---|---|
| `/givesneakers` | Lists the shoe ids |
| `/givesneakers [your id] cups_black 10` | A real pair of Black Prada Cups, US 10 |
| `/givesneakers [your id] cups_pink 9 1` | A **fake** pair (the `1` at the end makes it fake) |
| `/givesneakers [your id] cups_blue 11 0 1` | A real pair **already in its box** |
| `/giveshoebox [your id] 3` | 3 empty shoe boxes |

### Using a pair of shoes (from your inventory)
Use the **Shoes** item and pick from the menu:
- **Inspect**: the pair appears in front of your eyes. Hold left mouse and drag to turn it, scroll to zoom, and press Backspace to put it away. A card shows the size, condition, serial and dirt.
- **Put them on**: you kneel and the camera looks at your feet while the shoes go on. To take them off, type `/shoesoff` and you get the same pair back.
- **Box them up** (needs an empty box): you put a box down, the lid opens, the shoes float down into it and the lid closes.

### Using a box
Use **Boxed shoes** or an **Empty shoe box** from your inventory to put it on the ground in front of you. Then target it with ox_target:

| Option | What happens |
|---|---|
| **Open lid / Close lid** | The lid swings open or shut |
| **Take shoes out** | You kneel, the lid opens if needed, and the shoes float up into your hands |
| **Put shoes in** | Pick a pair (if you have more than one), then the shoes float down and the lid closes |
| **Pick up box** | You get the box back as an item, with the shoes still inside if there are any |

Everyone nearby sees the lid and the floating shoes.

---

## Good to know

- **Fakes look identical.** The difference is hidden in the item's data and its serial number. The legit check and the NPC buyers who inspect shoes come in the selling phase.
- **Nothing gets lost.** If a player leaves or the script restarts while shoes are sitting in a placed box, the box goes back to their inventory, or the next time they log in.
- **Wearing persists.** Shoes you have on are saved to your character, and they're put back on when you log in.
- **The close-up camera** can be turned off with `Config.FirstPerson = false` in `config/config.lua`.

## When it goes wrong

| Problem | Fix |
|---|---|
| Console says *Shoe box model is not streamed* | Make sure `stream/nzs_box/` and `stream/nzs_cups/` are in the resource, then clear your client cache. |
| Using an item does nothing | The item isn't set up in your inventory (step 3 of Install), or for ox the `server = { export = 'nz_sneakers.useItem' }` line is missing. |
| *This shoe has no clothing set up yet* | Set the `drawable` in `config/shoes.lua` (section 2). |
| *These are not made for your character* | The shoe's `gender` doesn't match your ped. Fix `gender`, or set `Config.GenderLock = false`. |
| No target options on the box | ox_target isn't running, or nz_sneakers started before it. |
| Shoes or box show up invisible or inside-out | Screenshot it and send it to Claude. That's a model-file fix. |
