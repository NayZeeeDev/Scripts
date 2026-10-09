# nayzeee-sneakers: How To Use It

Everything the script does: shoe items and boxes, wearing, crafting real and fake pairs, dirt and
cleaning, and selling to NPC buyers through a phone app with a handover cinematic.

---

## 1. Install

1. Put these folders in your `resources`:
   | Folder | What it is |
   |---|---|
   | `nayzeee-sneakers` | the script |
   | `nayzeee-sneakers-shoes` | the props of the ten shoes that come with it |
   | `nayzeee-sneakers-boxes` | the shoe, heel and boot boxes (every colour) and the display cases |
   | `nayzeee-sneakers-clothing` | the shoes you wear (section 3) |

   **You don't make `nayzeee-sneakers-props`.** The script creates it by itself, next to `nayzeee-sneakers`, the first
   time it turns your server's own clothing shoes into props (section 9).
2. In `server.cfg`, start them **after** ox_lib, your framework, your inventory, your target and your phone:
   ```
   ensure ox_lib
   ensure ox_target
   ensure lb-phone
   ensure nayzeee-sneakers-shoes
   ensure nayzeee-sneakers-boxes
   ensure nayzeee-sneakers-clothing
   ensure nayzeee-sneakers
   ```
   If one of the prop resources isn't running, the server console says so when the script starts.
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
6. **Wearing:** set up **nayzeee-sneakers-clothing** (section 3) and start it before this script.
7. **Crafting tables:** install the **Dragons Lab Shoe Table Pack** (see section 5).
8. **Your server's own shoes and the studio** (section 9). In `server.cfg`:
   ```
   add_ace group.admin command.sneakerstudio allow
   add_filesystem_permission nayzeee-sneakers write ox_inventory
   add_unsafe_child_process_permission nayzeee-sneakers
   add_ace resource.nayzeee-sneakers command.refresh allow
   add_ace resource.nayzeee-sneakers command.ensure allow
   add_ace resource.nayzeee-sneakers command.restart allow
   ensure screenshot-basic
   ```
9. Restart the server, then **close FiveM and clear your cache**.

### The config files
| File | What's in it |
|---|---|
| `config/config.lua` | Framework, inventory, notifications, target, **phone**, **dispatch**, admin commands, boxes, wearing, **dirt**, **cleaning**, **studio**, Discord logs |
| `config/shoes.lua` | The shoe models, colourways, prices and where each one sits in the clothing pack. Shoes from your own clothing packs are added in game (section 9) |
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

The shoes come as their own addon clothing resource, **nayzeee-sneakers-clothing**. It's already set up: you only drop the shoe files in.

1. Put the `nayzeee-sneakers-clothing` folder in your `resources`.
2. Drop each shoe's files into its folder in `stream/`, exactly as they came:

   | Folder | Shoe | Use these files |
   |---|---|---|
   | `[male]/cup_runner` | Cup Runner | debranded clothing pack: `cup_runner` |
   | `[male]/fang_5` | Fang 5 | debranded clothing pack: `fang_5` |
   | `[male]/backcourt_low` | Backcourt Low | debranded clothing pack: `backcourt_low` |
   | `[male]/stack_trainer` | Stack Trainer | debranded clothing pack: `stack_trainer` |
   | `[male]/crevis_95` | Crevis 95 | crevis sneaker by jazlyn13 |
   | `[female]/alice` | Alice Western Boot | STRUT Alice Shoes |
   | `[female]/bianca` | Bianca Heel | STRUT Bianca Shoes (the *Optimised* folder) |
   | `[female]/maisie` | Maisie Slingback | STRUT Maisie Shoes |
   | `[female]/omnia` | Omnia Ankle Boot | STRUT Omnia Shoes |
   | `[female]/mia` | Mia Knee Boot | [WM] Mia Colucci Boots |

   One `.ydd` and all of its `.ytd` files per folder. Only the `.ydd` and `.ytd` files, nothing else.
3. Double-click **`RENAME-CLOTHING.bat`**. It renames everything to the names the pack needs and tells you if a folder is missing a texture. Every line should say `[ok]`.
4. In `server.cfg`, start it **before** nayzeee-sneakers:
   ```
   ensure nayzeee-sneakers-clothing
   ensure nayzeee-sneakers
   ```
5. Restart, then **close FiveM and clear your cache**.

That's it. The script finds the shoes in the pack by itself, so you don't look up or type any drawable numbers. Each shoe's place in the pack is its `slot` in `config/shoes.lua`. Leave those as they are.

The heels already have their heel height and footstep sounds set, using the creators' recommended settings.

**Using your own clothing pack instead?** Put the drawable number from your clothing menu in `drawable = …` for that model in `config/shoes.lua`. A `drawable` always wins over `slot`.

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
Use **Boxed shoes** or an **empty box** from your inventory. With an empty box (or **Box them up**) you first pick a
**colour**: orange, black, white, red, blue, green, pink, purple or teal (your last pick is at the top). A boxed pair keeps
its colour when you pick it up and put it down again. Change the list in `Config.BoxColours`, or turn the menu off with
`Config.Box.colourPicker = false`.

A see-through box follows where you look: scroll turns it,
**E** puts it down, Backspace (or right-click) cancels. It goes on the floor or on a table. **Box them up** works the same way.
Then target the box (with **interact** just walk up to it; the prompt sits on top of the box):

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

**Using a table:** use the table item, aim where you want it (scroll turns it), press **E** to place, Backspace (or right-click) to cancel.
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
4. **Make this pair.** You step up to the front and centre of the table and work while a ghost of the pair in the middle of the table top fills in, stage by stage.
   Which side counts as the front is `Config.Tables.side` (`'nearest'`, `'front'` or `'back'`).
   Some stages have a skill check. Press **X** to stop; you keep your materials, since they're only used up when the pair is done.

**Camera views.** Pick one under **Camera** in the table menu, or press **V** while you work to switch. Your pick is remembered,
and cleaning uses it too:

| View | What you see |
|---|---|
| **3/4 view** (default) | High over your shoulder and off to the side, looking down on you and the whole table |
| **First person** | The game's own first-person camera, through your eyes |
| **Close-up** | Low across the table from the far side: the shoes up front, your hands working behind them |

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

The app's icon is the **Sneaker Co.** logo. Each player picks its colour in the app (**Profile > App colour**, the same
nine colours as the boxes); the logo in the app changes at once and the home screen icon when they close the phone.
`Config.Phone.AppColour` sets the colour everyone starts with.

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

## 9. Use the shoes already on your server (Sneaker Studio)

You don't have to stick to the ten shoes that come with the script. Any shoe your clothing packs stream can be made,
worn, boxed and sold, with its own prop and icon. It's built like the wig snatch and backpack studios.

| | What it does |
|---|---|
| **3D props** (the server does it) | When the server starts, sneakerkit (`tools/sneakerkit`) looks through every started resource for shoes, and turns each new or changed one into props: one per colourway, packed to sit in its box, with icons. They go into **nayzeee-sneakers-props**, made next to this resource and restarted for you. Shoes that are gone are removed. |
| **/sneakerstudio** (in game, admins) | Every shoe on the server in one list. Name, price, level and box, switch them on sale, and take their inventory photos: the shoe floats in a chroma box, you frame it, and each photo is keyed into a transparent PNG that goes straight into ox_inventory. |

### Setting it up
1. The `server.cfg` lines in Install, step 8. `screenshot-basic` is only needed for the photos.
2. Restart the server. The console says what it found, e.g. *3D props: 12 new, 0 changed, 0 removed shoe(s)*, builds them
   and starts **nayzeee-sneakers-props**. (If it can't start it, it tells you the line to add.)
3. In game type **/sneakerstudio**.

### The studio
- **Left:** every shoe. **All / Male / Female**, and **On sale / Off / New / Gone**. A green dot means it has a photo, **3D** that it has its own prop.
- **Middle:** the shoe in the chroma box. Drag to orbit, scroll to zoom. The corner marks are what the photo crops to.
- **Right:**
  - **Shoe:** on sale, name, price, level, box size. **Save** (or Enter). It's live for everyone straight away: craftable, wearable, boxable and sellable.
  - **Colourway:** pick one to see it, and rename it.
  - **Backdrop:** green, magenta or blue. Pick one the shoe doesn't use (green shoes: magenta).
  - **Framing:** **The pair** or **In its box**, angle presets, zoom and height.
  - **Capture:** **This photo**, or **Every shoe** (every colourway too, the pair and/or the box, skipping ones that already have a photo).
    Backspace stops a batch.
  - **3D props:** how many shoes have props and what's new, changed or gone. **Build**, **Check again**, or **Rebuild every shoe**.
- Keys: **↑ ↓** shoe, **← →** colourway, **Esc** close.

Photos are saved as `shots/nzs_<shoe>_<colour>.png` (the pair) and `..._box.png` (in its box) in this resource and copied
into `ox_inventory/web/images`. Restart ox_inventory to see new ones in the inventory. A rebuild never replaces a photo you took.

### The custom shoes
The ten shoes that come with the script are in the list too (*comes with the script*). Change their name, price, level and
colour names, switch one off, or take new photos of them, the same way. Their props and box size stay as they are.

### New and removed shoes
- Every time an admin opens the studio (and when an admin joins, with `Config.Studio.AlertAdmins`), their game checks every
  shoe drawable on the server. **New** lists shoes the studio doesn't know yet; **Gone** lists shoes whose clothing was removed.
- New shoes get their props by themselves on the next server start (or press **Build** in **3D props**). To sell one before
  that, open it and **Add it as a shoe**: it uses a stand-in prop (`Config.Studio.StandIn`) until its own is built.
- Gone shoes go off sale by themselves. Pairs players already own stay in their inventory, and if the pack comes back the shoe does too.

Shoes are worn by **pack and drawable number inside the pack**, so adding or reordering other clothing packs never mixes them up.

### Converting on your PC instead
`nayzeee-sneakers-studio` (NayZeee Sneaker Studio.exe) is the same converter with a window: point it at a server folder on your PC,
convert, upload the **nayzeee-sneakers-props** it makes. Shoes it finds as plain downloads (just `feet_000_u.ydd`) can be linked to
their drawable in /sneakerstudio (**Drawable**).

### Settings
`Config.Studio` (photos and the studio) and `Config.ShoeProps` (3D props) in `config/config.lua`:

| Setting | What it does |
|---|---|
| `Studio.AutoEnable` | `true` = new shoes go on sale as soon as they have a prop, without an admin switching them on |
| `Studio.BaseGame` | Also list GTA's own shoes |
| `Studio.AlertAdmins` | Tell admins when they join if shoes were added or removed |
| `Studio.StandIn` / `Price` | The prop shown for a shoe without its own, and a new shoe's starting price, per box size |
| `Studio.Size` / `Padding` / `Chroma` | Photo size, empty border, starting backdrop |
| `Studio.SaveToInventory` | Copy every photo into ox_inventory/web/images |
| `ShoeProps.AutoScan` / `AutoBuild` | Look for new / changed / removed shoes when the server starts, and build them straight away |
| `ShoeProps.TextureSize` | Max texture size of each prop (512 is a good default) |
| `ShoeProps.CopyIcons` | Put the icons it renders into the inventory (photos you take always win) |
| `ShoeProps.Skip` | Resources to leave out of the scan |

Admin settings are saved in the server's KVP, so they survive updates to the script.

---

## 10. Display cases (shoe collections)

Clear acrylic cases for showing pairs off: in a house, a shop, anywhere. Each holds one pair behind a
side door, and they stack: on top of each other and side by side, as high and wide as you like.

| Item | Holds |
|---|---|
| `nz_display` (Shoe display) | sneakers |
| `nz_display_heel` (Heel display) | heels and ankle boots |
| `nz_display_boot` (Boot display) | anything, tall boots too |

The supplier sells them. Add the three items (install files, step 3) and copy the new icons
(`nz_display*.png`) into your inventory's images.

**Placing:** use the item. The see-through case follows where you look; **scroll** turns it, **E** places it.
Aim at a case you already placed and the new one lines up on top of it (aim at its top) or right next to it
(aim at a side), fronts flush, so collections stack into neat walls.

**Third eye on a case:**
- **Open door / Close door**: the side door swings open.
- **Put a pair in**: pick a pair that fits; the door opens, the pair goes in, the door shuts.
- **Look at the pair**: the inspect view (turn it, see size, condition and serial).
- **Take the pair out**, **Pick up case** (only when it's empty, and nothing is stacked on it).

Cases stay where they are after restarts, with the pairs inside, in the same routing bucket they were placed in,
so instanced houses keep their own. Only the owner (or an admin) can put pairs in, take them out or pick the case
up; anyone can open the door and look (`Config.Displays.anyoneCanTake` / `anyoneCanOpen`).

For housing scripts that delete houses: `exports['nayzeee-sneakers']:RemovePlayerDisplays(identifier, true)` removes
a player's cases (`true` gives the pairs inside back to them on their next login).

Settings: `Config.Displays` in `config/config.lua` (sizes, which pairs fit which case, door speed, snapping,
max per player).

---

## 11. Limited drops

Every so often (`Config.Drops.Every`, 90 to 180 minutes by default, only with at least `MinPlayers` on) one colourway drops
in a handful of pairs:

1. **Announced.** Everyone gets a text and a notification: the shoe, how many pairs, the price. The drop store's blip
   starts flashing on the map.
2. **Raffle** (10 minutes). Enter in the Plug app (**Drops** tab) or at the drop store (third eye the clerk).
3. **Draw.** Winners get a text and have 15 minutes to collect and pay at the store (pick your size there). Pairs nobody
   won, and pairs winners don't come for, go to whoever walks in first.
4. **Done** when it sells out or the time is up.

Drop pairs are real, deadstock, in a black box, marked **Limited drop**, and buyers pay more for them
(`ValueBoost`, 1.5x). The dropped model also gets a hype boost. One pair per person per drop.

Admins: `/sneakerdrop` starts one now (a random shoe), `/sneakerdrop fang5_c 6` a chosen one with 6 pairs,
`/sneakerdrop stop` ends it. Everything else is in `Config.Drops` (`config/selling.lua`): timings, pairs, price,
which shoes can drop, the store's spot and ped.

---

## Performance

At rest the script costs next to nothing (resmon around 0.00 to 0.02 ms): nothing runs every frame unless something is
animating or a menu is open. One shared scan looks for placed boxes and display cases every 0.75 s, and it doesn't run at
all when none are out (the server keeps the counts). Peds (supplier, drop store) only exist while you're near them.
The heavier moments are short and only for the player doing them: crafting, the cinematic, placing, the studio.

---

## Notifications and escrow

Every notification goes through **ox_lib** (`lib.notify`), buyers' texts too when no phone takes them.
`Config.Notify = 'auto'` uses nayzeee-notify or okokNotify instead when one is running.

The script is escrow ready: `config/`, `locales/`, `bridge/` and `install/*.lua` stay open for owners, everything else is
locked when uploaded through Keymaster, and so are the two prop resources (`nayzeee-sneakers-shoes`, `nayzeee-sneakers-boxes`). Props made in
**3D props** come from each server's own clothing, so those stay with that server.

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
| Can't third eye a placed box | Type **/nzsboxes** in F8 next to the box and send the output: it shows which target script is used, the boxes that are set up and what you're aiming at. |
| Using an item does nothing | The item isn't set up in your inventory (Install, step 3), or for ox the `server = { export = 'nayzeee-sneakers.useItem' }` line is missing. |
| *These need a heel box* (or similar) | That pair fits a different box size. Use the matching empty box. |
| *This shoe has no clothing set up yet* | That model has no `slot` (or `drawable`) in `config/shoes.lua`. |
| *The sneaker clothing pack is not running* | `ensure nayzeee-sneakers-clothing` before this script, then clear your cache. If it still says it, your FiveM build is too old for the pack lookup: put `drawable` numbers in `config/shoes.lua` instead (section 3). |
| Shoes are invisible or the wrong colour | `RENAME-CLOTHING.bat` didn't say `[ok]` for that shoe. Fix what it says, run it again, clear your cache. |
| Feet sink into the floor in heels (or float) | The heel heights live in `stream/mp_f_freemode_01_nayzeee_sneakers.ymt`. Open it in YMTEditor or grzyClothTool and adjust that shoe's high-heels value. |
| *These are not made for your character* | The model's `gender` doesn't match your ped. Fix `gender`, or set `Config.GenderLock = false`. |
| Tables are plain workbenches | The Dragons Lab pack isn't running, or that player's cache is old. `ensure` it and clear the cache. |
| The close-up camera ends up inside something on the table | Her props sit at the back of the table: work further along it, or switch view with **V**. |
| The shoes float above / sink into the table while crafting | Change `Config.Tables.surface` (the table-top height) in `config/crafting.lua`. |
| No Plug app on the phone | Start lb-phone **before** this script (or restart this script). The F8 console says *could not add the Plug app* with lb-phone's reason if it refused. With `DefaultApp = false` it's in the App Store. |
| Buyers never text | The player needs a phone with a number equipped. Offers still show in the app either way. |
| The buyer never shows up | They spawn when you're within 150 m of the meet. If a driver gets stuck they're moved to the meet after a minute. |
| Police never get alerts | Check `Config.Dispatch.PoliceJobs` matches your police job names, and that officers are on duty. |
| Shoes or box show up invisible or inside-out | Screenshot it and send it to Claude. That's a model-file fix. |
| /sneakerstudio does nothing | You need `command.sneakerstudio` (or the admin ace). Install, step 8. |
| *could not start sneakerkit: Access to this API has been restricted* | Add `add_unsafe_child_process_permission nayzeee-sneakers` to server.cfg and restart the server (not just the resource). Newer FXServer builds block resources from starting programs without it. |
| **3D props** says *sneakerkit isn't installed* | `tools/sneakerkit/linux-x64` (Linux servers) or `win-x64` (Windows) is missing from the resource. On Linux it also has to be executable: `chmod +x tools/sneakerkit/linux-x64/sneakerkit`. |
| Props are built but nayzeee-sneakers-props doesn't start | Add the three `add_ace resource.nayzeee-sneakers command...` lines (Install, step 8), or `ensure nayzeee-sneakers-props` after this script. |
| Photos only go to `shots/` | Add `add_filesystem_permission nayzeee-sneakers write ox_inventory` and restart. You can copy `shots/*.png` into ox_inventory/web/images by hand meanwhile. |
| **This photo** is greyed out | screenshot-basic isn't running, or the shoe has no 3D prop yet (build it in **3D props**). |
| The photo has green edges | Pick a backdrop the shoe doesn't use (magenta for green shoes). |
| *Your FiveM build can't list clothing packs* | Update FiveM (the drawable check needs the clothing collection natives). 3D props still work. |
| A studio shoe can't be worn | Its drawable isn't on the server (check **Gone**), or it's a plain download that hasn't been linked to its drawable yet. |
| A studio shoe shows as a different shoe on tables and in boxes | That's the stand-in: it was added before its prop was built. Press **Build** in **3D props**. |
