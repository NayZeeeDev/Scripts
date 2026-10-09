# nayzeee-sneakers: How To Use It

Everything the script does: shoe items and boxes, wearing, crafting real and fake pairs, dirt and
cleaning, and selling to NPC buyers through a phone app with a handover cinematic.

---

## 1. Install

1. Put the `nayzeee-sneakers` folder in your `resources`.
2. In `server.cfg`, start it **after** ox_lib, your framework, your inventory, your target and your phone:
   ```
   ensure ox_lib
   ensure ox_target
   ensure lb-phone
   ensure nayzeee-sneakers
   ```
   Target can be ox_target, qb-target or interact (or none: you get a key prompt).
   **Selling needs lb-phone.** Everything else works without it.
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

### The config files
| File | What's in it |
|---|---|
| `config/config.lua` | Framework, inventory, notifications, target, **phone**, **dispatch**, admin commands, boxes, wearing, **dirt**, **cleaning**, Discord logs |
| `config/shoes.lua` | The shoe models, colourways, prices and clothing drawables |
| `config/crafting.lua` | Tables, materials, recipes, crafting stages, levels, the supplier |
| `config/selling.lua` | Selling, buyer types, legit checks, meet spots, the cinematic, hype, rep, police |
| `locales/en.lua` | Every bit of text players see. Copy it to translate |

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
- **Clean them** (needs a cleaning kit, shows when they're dirty): see section 6.

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
leather, mesh fabric, rubber soles, heel blocks, thread, glue, laces and **authentic tags**, plus empty boxes,
and cleaning kits. Move him with `Config.Supplier.coords`.
Prices are in `Config.Materials` and `Config.Supplier.Extra`.

### Making a pair
1. Target your table and pick **Use shoe table**.
2. At the top choose **Fake** or **Real**. Real pairs need an authentic tag and level 4.
3. Pick a shoe, a colourway and a size. The panel shows what you have and what you're missing.
4. **Make this pair.** You walk up to the table and work while the pair builds up in front of you, stage by stage.
   Some stages have a skill check. Press **X** to stop; you keep your materials, since they're only used up when the pair is done.

**Camera views.** Pick one under **Camera** in the table menu, or press **V** while you work to switch. Your pick is remembered,
and cleaning uses it too:

| View | What you see |
|---|---|
| **3/4 view** (default) | Over your shoulder, a step back and to the side: you, the whole table and the pair |
| **First person** | Your own eyes, looking down at the work |
| **Close-up** | Low across the table from the far side: the shoes up front, you working behind them |

Set the default in `Config.Camera.Default`, or `Config.Camera.Switch = false` to lock everyone to it.

The finished pair goes in your inventory, brand new (Deadstock). Its card shows how it came out.

### Fakes and quality
Every fake has a **quality** (10–97%): how convincing it is. Higher level, and clean skill checks, make better fakes; a failed check costs quality.
Real pairs are always 100%. Buyers use quality when they check a pair (section 7).

### XP and levels
Every pair gives XP (more for real pairs, a bonus for no failed checks). Levels unlock more shoes, real pairs at level 4,
and make you work faster (4% per level). Tune it all in `config/crafting.lua`.

| Command | What it does |
|---|---|
| `/givematerials [your id] 3` | Enough of every material for 3 pairs of anything (real or fake) |
| `/sneakerxp [your id] 600` | Give 600 XP (level 4). No amount shows their XP |

---

## 6. Dirt and cleaning

### Shoes wear out
The pair on your feet gets dirty and wears down as you walk around:
- **Distance:** dirt builds up per km walked. Running counts more.
- **Ground:** mud, sand, dirt tracks, grass and gravel are dirtier than pavement.
- **Rain and water:** walking in the rain is dirtier, and going into water adds a lot at once.
- **Condition:** any wear at all ends **Deadstock**. After 12 km a pair is **Used**, after 45 km it's **Beat**. A pair never gets better.

You get a heads-up as the dirt passes 25%, 50% and 75%, and when the condition drops. Inspect a pair to see its dirt.
Boxed and loose pairs don't change; only the pair you're wearing does. Tune it in `Config.Dirt` and `Config.WearOut`.

### Cleaning a pair
Buy a **Cleaning kit** from the supplier (it cleans 5 pairs). Then either use the kit and pick a pair,
or use a dirty pair and choose **Clean them**. You kneel down, the pair goes on the ground in front of you and you work through
the stages with a brush. Missed skill checks leave a little dirt behind. Cleaning takes off dirt, not wear: a Used pair stays Used.

| Command | What it does |
|---|---|
| `/sneakerdirt 60` | Set the dirt on the pair you're wearing to 60% (testing) |

---

## 7. Selling

### The Plug app (lb-phone)
Selling goes through the **Plug** app on **lb-phone**. The script adds it to lb-phone by itself when it starts:
it's on every phone already (`Config.Phone.DefaultApp = true`), or set that to `false` so players download it from the App Store.
Start lb-phone **before** this script.

| Tab | What's there |
|---|---|
| **Offers** | Buyers DM you a price for one of your pairs. Accept or pass. Each one shows how hard they check (●●●) and whether they walk or drive up |
| **Stash** | Every pair in your pockets, loose or boxed, with what it's worth. **Find buyers** posts it |
| **Hype** | Which models are hot today (prices go up) and which are cold |
| **Profile** | Level, XP, reputation, and how much you've sold, earned and made |

### A deal, start to finish
1. In **Stash**, hit **Find buyers** on a pair. A few seconds later buyers text you and their offers land in **Offers**.
2. **Accept** one. They text you a meet spot and the GPS is set. You have 12 minutes.
3. They're waiting when you get there, or they **pull up in a car**. Target them: **Make the deal**.
4. **The handover cinematic:** you walk up and hand the pair over. They look it over (some run the serial), then either:
   - **pay you**: an envelope of cash, and they walk or drive off, or
   - **catch a fake**: they hand it back and storm off. Some call the cops, and some come at you.
5. A banner shows how it went: offer, paid, rep and XP. Press **ENTER** to skip the cinematic.

### Real or fake
| Buyer | Checks | Pays |
|---|---|---|
| Casual | Rarely looks | 85–100% |
| Hypebeast | Usually looks, sometimes runs the serial | 100–118% |
| Reseller | Always looks, often runs the serial | 72–88% |
| Collector | Almost always runs the serial; only buys boxed Deadstock | 120–145% |

A serial check always catches a fake. A look by eye catches it more often the lower its quality.
A fake that gets past them is a full sale. Sell fakes to casual buyers and hypebeasts; real pairs to anyone.

### What a pair is worth
Retail price × today's hype × condition × dirt × box (loose sells for less) × size (popular sizes sell a little higher)
× the buyer × your rep (up to +20% at max rep). Everything is in `config/selling.lua`.

### Reputation
Clean sales raise it, getting caught with a fake drops it (−8), and backing out of a deal or missing the meet costs a little.
More rep means better prices and more buyers.

| Command | What it does |
|---|---|
| `/sneakerrep [your id] 50` | Give 50 rep. No amount shows their rep |

### Meet spots
Ten spots around Los Santos are set up in `Config.Meets`. Add your own: any open spot works, the height snaps to the ground.

---

## 8. Phones, police and logs

**Phone texts** (`Config.Phone.Messages`): buyers text you through lb-phone's Messages app, from `Config.Phone.Number`,
with a phone notification so it pops even with the phone closed. (The bridge also has npwd, and marked spots for yseries,
qs-smartphone and gksphone texts in `bridge/server/phone.lua`.)

**Police** (`Config.Dispatch`): caught fakes (and the odd tip-off) go to **ps-dispatch**, **cd_dispatch**, **qs-dispatch** or
**rcore_dispatch**, whichever is running, or a built-in blip and alert for the jobs in `PoliceJobs`.
Use `'custom'` and fill in `Bridge.CustomDispatch` in `bridge/server/dispatch.lua` for anything else.

**Discord logs:** paste a webhook into `Config.Logs.Webhook` to log sales and caught fakes.

---

## Good to know

- **Fakes look identical.** The difference is in the item data and the serial number, which is what buyers check.
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
| The close-up camera ends up inside something on the table | Her props sit at the back of the table: work further along it, or switch view with **V**. |
| The shoes float above / sink into the table while crafting | Change `Config.Tables.surface` (the table-top height) in `config/crafting.lua`. |
| No Plug app on the phone | Start lb-phone **before** this script (or restart this script). The F8 console says *could not add the Plug app* with lb-phone's reason if it refused. With `DefaultApp = false` it's in the App Store. |
| Buyers never text | The player needs a phone with a number equipped. Offers still show in the app either way. |
| The buyer never shows up | They spawn when you're within 150 m of the meet. If a driver gets stuck they're moved to the meet after a minute. |
| Police never get alerts | Check `Config.Dispatch.PoliceJobs` matches your police job names, and that officers are on duty. |
| Shoes or box show up invisible or inside-out | Screenshot it and send it to Claude. That's a model-file fix. |
