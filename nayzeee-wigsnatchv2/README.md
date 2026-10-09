# Wig Snatch V3

Player-vs-player wig snatching. Every snatch is a live minigame between both players, every wig is a unique item with a tier, a style, a picture and a history. V3 adds first person haircuts and shaves, tackles, zip ties, holding people still, hair products, a wig workshop with dye, a phone app for selling, and a built-in studio that photographs every hairstyle on your server.

## ✨ Features

| Feature | What it does |
| --- | --- |
| **5 minigames** | Tug of War, Button Mash, Combo, Skill Check and Grip. Both players play the same one, the server moves the rope. Pick one, rotate them or randomize them (`Config.Clash`). |
| **Steal it back** | Lose a wig and you have 15 minutes to snatch that exact wig back from whoever has it, in their pockets or on their head. |
| **First person cuts** | Scissors, clippers and a straight razor. The camera moves in, your cursor becomes the tool, and you work the top, sides, back, eyebrows and beard. What you do decides the result: trim, fade, buzz, bald, thinned or shaved brows, beard trim or clean shave. Sounds and hair clippings for everyone nearby. |
| **Tackle** | Sprint at someone and press `G`. They hit the floor and count as restrained for a few seconds. |
| **Zip ties** | Tie up anyone who is tackled, cuffed, held, downed or has their hands up. They can't move until they struggle free or someone unties them. |
| **Hold still** | Grab someone from behind and pin them while a friend snatches, shaves or pranks them. They can struggle out. |
| **Hair products** | Hair remover (hair falls out), lye relaxer (burns), a lice jar (itching, flies, spreads), mud (washes out in water), shampoo and regrowth oil. Everyone nearby sees smoke, flies and mud. |
| **Reactions** | Facepalms, crying, shaking it off, celebrating. Every event has its own list in `Config.Reactions`. |
| **Wigs + bundles** | Snipping long hair drops hair bundles. Three bundles and a wig cap make a wig of that hairstyle at a wig table. |
| **Make any wig** | Pick any in-game hairstyle, texture, length, lace and colour in the Workshop and make it from materials at a wig table. The lace sets the tier (closure, frontal, full lace), longer wigs take more wefts, unnatural colours take a dye. |
| **Hair supplier** | An NPC (on your map) sells wig caps, wefts, thread, lace, dye, glue and kits, with level-gated lace. |
| **Wig tables** | Dragons Lab's Wig Crafting Tables by SasDragon (sold separately, see below). Place one from your inventory, pick it back up, saved between restarts. Make and dye wigs at it in stages with skill checks, the wig taking shape on a foam head in front of you and a camera you switch with `V` (over the shoulder, first person, close up). Same system as nayzeee-sneakers. |
| **Dye** | Dye any wig at a wig table (or your own hair anywhere) with the full game palette. Dyed wigs sell for more. |
| **Props** | Clippers, a straight razor, a hair dye bottle, a foam wig head and a hair bundle, streamed with the script (`stream/`). |
| **Hair pricing** | Tier base, condition, provenance, dye, burns, market demand and your title. The phone shows the full breakdown. |
| **Hair Plug phone app** | Quick sell, meet-ups with a buyer who runs to you, a player marketplace (offline sellers get paid on login), and rotating NPC orders that pay extra. Lives inside lb-phone, YSeries or qs-smartphone. There is no built-in phone. |
| **Wig Studio** | Built like the nayzeee-backpack icon studio. A head floats in a lit chroma box, you frame it with the orbit camera, and each shot is keyed in the browser into a small transparent PNG that's copied straight into ox_inventory. Shoot one hairstyle or every hairstyle, and name them there: every wig of that style uses the name and the photo. |
| **Wear / put on / take off** | Wear any wig that fits, put your wig on someone else, or take a wig off them. Both ask first. |
| **Notifications** | Built-in toasts, ox_lib, ESX, QBCore, Qbox, okokNotify, mythic_notify, pNotify, t-notify, brutal_notify, wasabi_notify, lation_ui or your own. |
| **Player preferences** | Every player picks their own accent and alert colours, UI size, toast position, sounds, banners and minigame keys (Vault > Settings or `/wigsettings`). Saved on their PC. |
| **Wig Vault** | Profile, wigs, workshop, catalog, bounties, leaderboards, city feed and settings. |
| **Revenge, bounties, tiers, titles, catalog, trades** | Everything from V2 is still here. |
| **0.00 resmon** | No loops while idle. Loops only run while something is happening (a cut, a tie, a status). |

> **Removed in V3:** the barber locations and the haircut picker menu. Cuts are first person now, hair grows back on its timer or with Regrowth Oil, and wig repairs use Wig Kits. The `/sellwigs` buyer moved into the phone app (Meet-up).

## 🧩 Requirements

| Resource | Required | Notes |
| --- | --- | --- |
| OneSync | Yes | Server checks distances and positions |
| ox_lib | Yes | Callbacks, commands |
| oxmysql | Yes | Tables are created and upgraded automatically |
| Framework | Yes | ESX Legacy, QBCore or Qbox (auto-detected) |
| Inventory | Yes | ox_inventory (recommended), qb-inventory and forks, qs-inventory. Plain ESX inventory works without metadata (no tiers, pictures or listings). |
| ox_target / qb-target | Recommended | Without one, use the commands and usable items |
| screenshot-basic | For the studio | Only needed to take wig photos |
| A phone | For selling | lb-phone, YSeries or qs-smartphone. The Hair Plug app is added to it. There is no built-in phone |
| [Dragons Lab Wig Crafting Tables](https://discord.com/invite/KEhZqcuv6m) | Recommended | SasDragon's table models, bought from her. Without them the tables fall back to a GTA workbench |

## 🚀 Installation

1. Drop `nayzeee-wigsnatchv2` into your resources, replacing your old copy (the database carries over).
2. Add the items from `INSTALL/` (`ox_inventory.txt`, `qb-core.txt` or `esx_items.sql`) and copy `INSTALL/images/*.png` into your inventory's image folder. The wig table items use the icons in SasDragon's `install-images` folder.
3. Start it after your framework, inventory, target and phone:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure ox_target
   ensure screenshot-basic
   ensure lb-phone
   ensure DragonsLab_WigTables
   ensure nayzeee-wigsnatchv2
   ```
4. Give admins the commands:
   ```cfg
   add_ace group.admin command.wigadmin allow
   add_ace group.admin command.wigstudio allow
   # lets the studio copy photos into ox_inventory/web/images (newer FXServer builds)
   add_filesystem_permission nayzeee-wigsnatchv2 write ox_inventory
   # lets 3D wigs refresh and restart nzw_hairprops after building
   add_ace resource.nayzeee-wigsnatchv2 command.refresh allow
   add_ace resource.nayzeee-wigsnatchv2 command.ensure allow
   add_ace resource.nayzeee-wigsnatchv2 command.restart allow
   ```
5. Restart. New tables and columns are added on their own (`sql/install.sql` is there if you prefer to run it by hand).
6. Optional but recommended: `/wigstudio` > **Every hairstyle** for each model, then restart this resource and ox_inventory so the photos are served.

## 🎒 Items

| Item | Use |
| --- | --- |
| `wig` | Use it to wear it |
| `hair_bundle` | Raw hair from cuts. Opens the Workshop |
| `wig_cap` | Needed to make a wig |
| `hair_dye` | Dye a wig (at a wig table) or your own hair (Workshop) |
| `wigtableblue` / `wigtablepink` / `wigtablepurp` / `wigtablered` | Place a wig table |
| `hair_weft` / `wig_thread` / `lace_closure` / `lace_frontal` / `lace_full` | Wig making materials (the supplier sells them) |
| `wig_glue` | Glue your lace down for 20 minutes |
| `wig_kit` | Repair a wig's condition (Vault) |
| `scissors` / `hair_clippers` / `straight_razor` | First person cutting tools. Use one to cut whoever is in front of you |
| `zip_ties` | Tie up whoever is in front of you (they must be restrained) |
| `hair_remover` / `relaxer` / `lice_jar` / `mud_bag` | Pranks for other people's hair |
| `shampoo` / `regrowth_oil` | Wash out mud and lice / grow everything back |

## ⌨️ Commands & keys

| Command | Who | What |
| --- | --- | --- |
| `/snatch` | Everyone | Snatch the closest player in front of you |
| `/wigtackle` (`G` while sprinting) | Everyone | Tackle |
| `/wighold` · `/wigrelease` (`X`) | Everyone | Grab someone from behind · let go |
| `/wiguntie` · `/wigcut` | Everyone | Untie / cut whoever is in front of you |
| `/wigs` | Everyone | Wig Vault |
| `/wigsettings` | Everyone | Your colours, size, sounds and keys |
| `/wigpassive` | Everyone | Passive mode (if enabled) |
| `/wigstudio` | Ace `command.wigstudio` | Photograph and name hairstyles |
| `/wigadmin restore\|givewig\|givebundle\|resetcd\|protect\|xp\|glue\|status\|free <id> [value]` | Ace | Admin tools |

**First person cutting:** move the mouse over the head, `1` `2` `3` switch tools, `A` `D` walk around the head, `W` `S` height, scroll to zoom, `Enter` to finish, `Esc` to stop.
**Tied or held:** alternate `A` / `D` to struggle.

## 🔌 Exports

**Server**

```lua
exports['nayzeee-wigsnatchv2']:IsBald(source)
exports['nayzeee-wigsnatchv2']:GetHairState(source)        -- { bald, wig, cut, face, dye, status }
exports['nayzeee-wigsnatchv2']:RestoreHair(source)
exports['nayzeee-wigsnatchv2']:SetProtected(source, true)  -- safezones
exports['nayzeee-wigsnatchv2']:GiveWig(source, 'legendary')
exports['nayzeee-wigsnatchv2']:GiveBundle(source, 'virgin')
exports['nayzeee-wigsnatchv2']:SetHairStatus(source, 'lice', 10)
exports['nayzeee-wigsnatchv2']:GetStats(source)
exports['nayzeee-wigsnatchv2']:IsInClash(source)
exports['nayzeee-wigsnatchv2']:IsTied(source)
exports['nayzeee-wigsnatchv2']:Untie(source)
exports['nayzeee-wigsnatchv2']:IsBeingCut(source)
exports['nayzeee-wigsnatchv2']:GetWigImage('f', 12, 0)     -- studio photo URL or nil
```

**Client**

```lua
exports['nayzeee-wigsnatchv2']:ReapplyHair()   -- call after your appearance script reloads the skin
exports['nayzeee-wigsnatchv2']:GetHairState()
exports['nayzeee-wigsnatchv2']:IsBusy()
exports['nayzeee-wigsnatchv2']:OpenVault('wigs')
exports['nayzeee-wigsnatchv2']:HasPhoneApp()   -- client: the Hair Plug app was added to a phone
exports['nayzeee-wigsnatchv2']:OpenWigStudio() -- client, admins
```

**Statebags** other scripts can read: `nzTied`, `nzHeld`, `nzHolding`, `nzDown`, `nzHairFx`, `nzWigOn`, `nzWigBusy`.

## 📱 Phone

| Phone | Status |
| --- | --- |
| lb-phone | Built in (`AddCustomApp`, push updates, phone notifications) |
| YSeries | Adapter in `bridge/phone.lua` |
| qs-smartphone / qs-smartphone-pro | Adapter in `bridge/phone.lua` |
| Anything else | Copy one of the adapters in `bridge/phone.lua` |

There is no built-in or on-screen phone: selling happens in the app on the player's own phone. The app talks to this resource through NUI callbacks, so it works the same everywhere. If your YSeries or qs version names its custom-app export differently, edit its `register` function in `bridge/phone.lua` (it's open source). The app also polls every few seconds, so phones without push messages still update.

## 📸 Wig Studio

Built the same way as the nayzeee-backpack icon studio. `/wigstudio` puts a plain freemode head in a lit chroma box under the map (your own character never changes, it just goes invisible and waits in its own routing bucket). The hairstyle list is on the left, the controls on the right, and the head is in between:

- **Drag** the middle of the screen to orbit, **scroll** to zoom, or use the angle chips (Three quarter, Front, Side, Back, High) and the Height slider for long hair.
- **Backdrop**: green, magenta or blue. Pick one the hair doesn't use.
- **This hairstyle** shoots what's on screen. **Every hairstyle** runs the whole list (tick *every texture too* for all textures, *skip* to only shoot missing ones). `Backspace` stops a batch.
- **Name** a hairstyle and save: every wig made from it uses that name and it joins the catalog (`data/style_names.json`).

Each shot is keyed **in the browser** (the same keyer as the backpack studio): the centre square inside the white corners is cut out, the backdrop removed with soft edges, the hair trimmed and centred on a transparent 256 px square. Only that small PNG (around 10 KB) goes to the server, so nothing lags. It's saved as `shots/wig_<f|m>_<hairstyle>_<texture>.png` and copied into `ox_inventory/web/images/` with the same name.

With `Config.Wig.Images = 'studio'`, every wig gets its photo: on ox_inventory through `metadata.image` (the copied file), on other inventories through `imageurl`. FiveM only serves files that existed when a resource started, so **restart this resource and ox_inventory after shooting**.

## 🪑 Wig tables

The tables are **Dragons Lab's Wig Crafting Tables by SasDragon**. They are not included and not made by NayZeee: every server buys them from her ([discord.gg/KEhZqcuv6m](https://discord.com/invite/KEhZqcuv6m)) and starts her resource next to this one. The script finds her models by name (`sasdragonslab_blue_wigtable`, `_pink_`, `_purple_`, `_red_`). Without her pack, tables fall back to a GTA workbench (`Config.Tables.Fallback`) and the console says where to get hers.

- **Place**: use a table item. A ghost follows your aim: scroll or Q / E rotates, left click places, right click cancels.
- **Pick up**: third eye on your own table (or the button in the workshop). Tables are saved between restarts, `MaxPerPlayer` each, and you can add fixed ones for a salon in `Config.Tables.Fixed`.
- **Use wig table** opens the Workshop at the table. Making a wig (3 bundles + a cap) or dyeing one plays out in stages: you walk up to the table, the bundles are laid out and get used up as the wig takes shape on a foam head, the right tool is in your hand for each stage, and fiddly stages have an ox_lib skill check. `V` switches the camera, `X` stops (nothing is used up if you stop).
- **Skill checks matter**: every clean check raises the chance of a higher tier wig, every sloppy one costs condition, and a perfect run gives bonus XP. Higher levels work faster.
- `Config.Tables.RequireTable = false` lets the Workshop make and dye wigs anywhere again.
- **The wig on the foam head**: every job puts the bald foam head on the table wearing the wig being made or dyed, in its exact hairstyle (see **3D wigs**). A hairstyle without a prop yet shows the generic wig.

## 🧊 3D wigs

GTA can only draw a hairstyle on a ped, so every hairstyle on your server is turned into a prop for the foam head, automatically, by **hairkit** (`tools/hairkit`, ready-to-run for Windows and Linux servers):

- **On server start** it looks through every started resource for hair files, converts new and changed ones into props in `nzw_hairprops` (created next to this resource), removes props whose hair is gone, and restarts `nzw_hairprops`. Your existing hair packs are all it needs: nothing to install.
- **`/wigstudio` > 3D wigs** shows how many hairstyles have a prop and what's new, changed or gone, with Build, Check again and Rebuild every hairstyle. Hairstyles with a prop get a **3D** tag in the list.
- Props are matched to hairstyles by pack and slot (the game's collection natives), so they stay right when packs change order.
- **Base game hair** lives in GTA's own files, which servers don't have: run `hairkit game` once on a PC with GTA and upload `nzw_hairprops`. See `INSTALL/HAIR_PROPS.md`.

## 💇 Making wigs

**Workshop > Make a wig** (at a wig table): pick any hairstyle in the game (it shows its studio photo and name), the texture, a length from 10" to 30", the lace and the colour. The materials list updates as you go and shows what you're missing.

| Part | Recipe (defaults) |
| --- | --- |
| Every wig | 1 wig cap + 1 weaving thread |
| Length | 1 hair weft per 6 inches (10" = 2, 18" = 3, 30" = 5) |
| 5x5 HD Closure | 1 closure · Uncommon wig · level 1 |
| 13x4 HD Frontal | 1 frontal · Rare wig · level 3 |
| Full Lace | 1 full lace unit · Epic wig · level 5 |
| Colour | Natural shades are free, anything else uses 1 hair dye |

The wig comes out with exactly that hairstyle, texture, colour and length, your name as the maker, and a tier from the lace: clean skill checks can bump it one tier higher, sloppy ones cost condition. Legendary and mythic wigs still only come from snatching. **From bundles & dye** is the old workshop: three bundles from cuts and a cap, and dyeing wigs.

**Hair Supply** (`Config.Supplier`) sells the materials next to Hair on Hawick by default; move her anywhere. Prices are set so a wig is worth more than its materials when sold through a meet-up, less through quick sell.

## 🧰 Props

Six props ship in `stream/` with `nz_wigsnatch_props.ytyp`:

| Model | Used for |
| --- | --- |
| `nz_wig_clippers` | Clippers in the barber's hand |
| `nz_wig_razor` | Straight razor in the barber's hand (and the shaping stage at a table) |
| `nz_wig_dye` | Dye bottle in your hand while dyeing, and on the table |
| `nz_wig_head` | The bald foam head on the table. The wig being made or dyed sits on it |
| `nz_wig_shell` | A generic long wig for the foam head, used for hairstyles that don't have their own prop yet |
| `nz_hair_bundle` | The bundles laid out on the table |

They were built for this script and compiled to YDR / YTYP with CodeWalker. The source XML and textures are in `INSTALL/props-source/` if you want to open them in CodeWalker or Sollumz, and the generator is in `tools/props/`.

See **3D wigs** above for the hairstyles themselves.

## ⚙️ Config highlights

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Clash.Mode` | `random` | `random`, `rotate` or one minigame id |
| `Config.Clash.Games` | all 5 | The pool for random / rotate |
| `Config.Minigames.<id>` | | Push, zone / arc sizes, speeds and rate limits per game |
| `Config.StealBack.Window` | `900` | Seconds you have to take your wig back |
| `Config.Notify` | `nui` | Notification system, or `auto` |
| `Config.UI` | | Default colours / size / sounds, and whether players can change them |
| `Config.Tackle` / `Tie` / `Hold` | | Ranges, timers, struggle strength |
| `Config.Cutting.Results` | | Which drawables trim / fade / buzz / bald turn into |
| `Config.Cutting.MaxWorkPerSecond` | `42` | Server-side speed limit for cuts |
| `Config.Products.List` | 6 products | Item, effect, who it works on, how long it lasts |
| `Config.Bundles` / `Workshop` / `Dye` | | Grades, prices, recipe, dye bonus |
| `Config.Phone` | | App name, which phone, quick sell rate, meet-up, listings, orders |
| `Config.Tables` | | Her table models, fallback, limits, fixed tables, camera, stages and skill checks |
| `Config.TableProps` | | The props in your hand and on the table during table work, and the hairstyle prop naming |
| `Config.Crafting` | | Base items, wefts per inch, lengths, laces (tier, level, items), natural colours, XP |
| `Config.Supplier` | | Ped, location, blip, account, items, prices and levels |
| `Config.HairProps` | on | 3D wigs: auto scan / auto build on start, texture size, resources to skip, hairkit paths |
| `Config.Studio` | `256` px | Photo size, starting backdrop, framing, lights, ox_inventory copy |

Discord webhooks and the admin / studio aces live in `config_server.lua`, which never reaches players.

## 🛠️ Troubleshooting

| Issue | Solution |
| --- | --- |
| Hair, brows or beard reset after a clothing store | Your appearance script reapplied the skin. Call `exports['nayzeee-wigsnatchv2']:ReapplyHair()` after it loads, or add its event to the list in `client/hair.lua`. |
| Wig pictures are missing | Run the studio, then restart this resource and ox_inventory. If the console says it couldn't write into ox_inventory, add the `add_filesystem_permission` line from Installation (or copy `shots/*.png` into `ox_inventory/web/images` by hand). |
| Studio photos come out black / empty | Start `screenshot-basic` before this resource. If the hair keys out too, switch the backdrop to one the hair doesn't use. |
| The app isn't on my phone | Check the F8 console for "Could not add the Hair Plug app" or "No supported phone found", and adjust `bridge/phone.lua` for your phone version. |
| A prop sits oddly in the hand | Different animations hold things differently. Tweak `pos` / `rot` in `Config.Cutting.Props` and `Config.TableProps`. |
| The foam head shows the generic wig | That hairstyle has no prop yet: `/wigstudio` > 3D wigs > Build. Base game hair needs `hairkit game` on a PC with GTA. If the console says it couldn't start `nzw_hairprops`, add the `add_ace` lines from Installation. |
| Tables are plain workbenches | SasDragon's pack isn't started. Buy it from her and `ensure` it before this resource. |
| No third-eye options | Start ox_target / qb-target before this resource, or use the commands and usable items. |
| Wigs have no tier in the inventory | You're on the plain ESX inventory, which has no metadata. Use ox_inventory. |
| A minigame key doesn't respond | Another resource is holding NUI focus. Players can also rebind keys in `/wigsettings`. |
| Police can't be targeted | Intended. Edit `Config.Protection.Jobs`. |
