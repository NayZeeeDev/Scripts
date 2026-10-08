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
| **Wigs + bundles** | Snipping long hair drops hair bundles. Three bundles and a wig cap make a wig of that hairstyle in the Workshop. |
| **Dye** | Dye any wig (or your own hair) with the full game palette. Dyed wigs sell for more. |
| **Hair pricing** | Tier base, condition, provenance, dye, burns, market demand and your title. The phone shows the full breakdown. |
| **Hair Plug phone app** | Quick sell, meet-ups with a buyer who runs to you, a player marketplace (offline sellers get paid on login), and rotating NPC orders that pay extra. lb-phone, YSeries, qs-smartphone, or on screen with `/hairplug`. |
| **Wig Studio** | uz_AutoShot-style studio built in. Photographs every hairstyle on a plain head with the background keyed out, so every wig shows its exact hairstyle in the inventory, the vault and the phone. Name hairstyles there and every wig of that style uses the name. |
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
| screenshot-basic or screencapture | For the studio | Only needed to take wig photos |
| A phone | Optional | lb-phone, YSeries or qs-smartphone. Without one, `/hairplug` opens the app on screen |

## 🚀 Installation

1. Drop `nayzeee-wigsnatch` into your resources (remove V2 first, the database carries over).
2. Add the items from `INSTALL/` (`ox_inventory.txt`, `qb-core.txt` or `esx_items.sql`) and copy `INSTALL/images/*.png` into your inventory's image folder.
3. Start it after your framework, inventory, target and phone:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure ox_target
   ensure screenshot-basic
   ensure lb-phone
   ensure nayzeee-wigsnatch
   ```
4. Give admins the commands:
   ```cfg
   add_ace group.admin command.wigadmin allow
   add_ace group.admin command.wigstudio allow
   ```
5. Restart. New tables and columns are added on their own (`sql/install.sql` is there if you prefer to run it by hand).
6. Optional but recommended: `/wigstudio` > **Shoot all** for each model, then restart the resource so the photos are served.

## 🎒 Items

| Item | Use |
| --- | --- |
| `wig` | Use it to wear it |
| `hair_bundle` | Raw hair from cuts. Opens the Workshop |
| `wig_cap` | Needed to make a wig |
| `hair_dye` | Dye a wig or your own hair (Workshop) |
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
| `/hairplug` | Everyone | The phone app on screen |
| `/wigpassive` | Everyone | Passive mode (if enabled) |
| `/wigstudio` | Ace `command.wigstudio` | Photograph and name hairstyles |
| `/wigadmin restore\|givewig\|givebundle\|resetcd\|protect\|xp\|glue\|status\|free <id> [value]` | Ace | Admin tools |

**First person cutting:** move the mouse over the head, `1` `2` `3` switch tools, `A` `D` walk around the head, `W` `S` height, scroll to zoom, `Enter` to finish, `Esc` to stop.
**Tied or held:** alternate `A` / `D` to struggle.

## 🔌 Exports

**Server**

```lua
exports['nayzeee-wigsnatch']:IsBald(source)
exports['nayzeee-wigsnatch']:GetHairState(source)        -- { bald, wig, cut, face, dye, status }
exports['nayzeee-wigsnatch']:RestoreHair(source)
exports['nayzeee-wigsnatch']:SetProtected(source, true)  -- safezones
exports['nayzeee-wigsnatch']:GiveWig(source, 'legendary')
exports['nayzeee-wigsnatch']:GiveBundle(source, 'virgin')
exports['nayzeee-wigsnatch']:SetHairStatus(source, 'lice', 10)
exports['nayzeee-wigsnatch']:GetStats(source)
exports['nayzeee-wigsnatch']:IsInClash(source)
exports['nayzeee-wigsnatch']:IsTied(source)
exports['nayzeee-wigsnatch']:Untie(source)
exports['nayzeee-wigsnatch']:IsBeingCut(source)
exports['nayzeee-wigsnatch']:GetWigImage('f', 12, 0)     -- studio photo URL or nil
```

**Client**

```lua
exports['nayzeee-wigsnatch']:ReapplyHair()   -- call after your appearance script reloads the skin
exports['nayzeee-wigsnatch']:GetHairState()
exports['nayzeee-wigsnatch']:IsBusy()
exports['nayzeee-wigsnatch']:OpenVault('wigs')
exports['nayzeee-wigsnatch']:OpenHairPlug()
```

**Statebags** other scripts can read: `nzTied`, `nzHeld`, `nzHolding`, `nzDown`, `nzHairFx`, `nzWigOn`, `nzWigBusy`.

## 📱 Phone

| Phone | Status |
| --- | --- |
| lb-phone | Built in (`AddCustomApp`, push updates, phone notifications) |
| YSeries | Adapter in `bridge/phone.lua` |
| qs-smartphone / qs-smartphone-pro | Adapter in `bridge/phone.lua` |
| Anything else / none | `/hairplug` opens the same app on screen |

The app talks to this resource through NUI callbacks, so it works the same everywhere. If your YSeries or qs version names its custom-app export differently, edit its `register` function in `bridge/phone.lua` (it's open source). The app also polls every few seconds, so phones without push messages still update.

## 📸 Wig Studio

`/wigstudio` opens a browser of every photographed hairstyle. **Shoot missing**, **Shoot all** or tick a few and **Re-shoot**. Your character goes to a hidden stage in its own routing bucket, every hairstyle is put on a plain head in front of a magenta screen, photographed, keyed out and saved to `shots/<m|f>/<drawable>_<texture>.png`. Your look is put back afterwards. `Backspace` stops a run.

Type a name under any photo and **Save names**: every wig made from that hairstyle uses that name and it joins the catalog. Names live in `data/style_names.json`.

With `Config.Wig.Images = 'studio'`, every wig item gets its photo through ox_inventory's `imageurl` metadata. FiveM only serves files that existed when the resource started, so **restart the resource after a studio run**.

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
| `Config.Studio` | | Photo size, chroma colour, camera, lights |

Discord webhooks and the admin / studio aces live in `config_server.lua`, which never reaches players.

## 🛠️ Troubleshooting

| Issue | Solution |
| --- | --- |
| Hair, brows or beard reset after a clothing store | Your appearance script reapplied the skin. Call `exports['nayzeee-wigsnatch']:ReapplyHair()` after it loads, or add its event to the list in `client/hair.lua`. |
| Wig pictures are missing | Run the studio, then restart the resource. Pictures need ox_inventory (or an inventory that reads `imageurl`). |
| Studio photos come out black / empty | Start `screenshot-basic` (or screencapture) before this resource. |
| The app isn't on my phone | Check the F8 console for "Could not add the Hair Plug app". Use `/hairplug`, and adjust `bridge/phone.lua` for your phone version. |
| Clippers / razor don't show in the barber's hand | Base GTA has no clipper or razor prop. Stream your own and set it in `Config.Cutting.Props`. |
| No third-eye options | Start ox_target / qb-target before this resource, or use the commands and usable items. |
| Wigs have no tier in the inventory | You're on the plain ESX inventory, which has no metadata. Use ox_inventory. |
| A minigame key doesn't respond | Another resource is holding NUI focus. Players can also rebind keys in `/wigsettings`. |
| Police can't be targeted | Intended. Edit `Config.Protection.Jobs`. |
