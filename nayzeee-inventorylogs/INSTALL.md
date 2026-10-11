# 📦 Inventory Manager · Install

Logs every item and money movement, manages player inventories online and offline, gives or removes items server-wide, rolls back after an attack, and edits your inventory's data files (items, weapons, shops, stashes) from the panel with changes going live without a restart.

Works with **ox_inventory**, **qb-inventory**, or **your own inventory** through one integration file. The panel changes to match whichever one you run: its sidebar, editor pages, stashes and item images all follow it.

## 🧩 Requirements

| Resource | Version | Notes |
|---|---|---|
| Inventory | ox_inventory 2.40+, qb-inventory 2.x, or your own | Picked automatically, see below |
| ox_lib | 3.30+ | Needed on qb servers too |
| oxmysql | 2.7+ | |
| Framework | ESX Legacy, QBCore or Qbox | Detected automatically |

## 🚀 Install

1. Drop `nayzeee-inventorylogs` into your resources folder. Keep the folder name as it is.
2. Start it **after** your inventory in `server.cfg`:

   ```cfg
   ensure oxmysql
   ensure ox_lib
   ensure ox_inventory        # or qb-core, qb-inventory, qb-shops
   ensure nayzeee-inventorylogs
   ```

3. Give your staff groups access in `config.lua` → `Config.Permissions`, or with ACE:

   ```cfg
   add_ace group.admin nayzeee.inventory.view allow
   add_ace group.admin nayzeee.inventory.manage allow
   add_ace group.superadmin nayzeee.inventory.global allow
   add_ace group.god nayzeee.inventory.editor allow
   add_ace group.god nayzeee.inventory.rollback allow
   add_ace group.god nayzeee.inventory.wipe allow
   ```

4. Restart the server. The database tables are created automatically (`sql/install.sql` is there if you'd rather run it yourself).
5. In game, type `/inventorymanager`.

> 💡 **Upgrading from 2.x:** replace the whole folder. Your old logs stay, the new `resource` column and index are added on first start. `Config` changed a lot, so start from the new `config.lua` and copy your webhooks across.

## 🎒 Choosing your inventory

`config.lua`:

```lua
Config.Inventory = 'auto'   -- 'auto' | 'ox_inventory' | 'qb-inventory' | 'custom'
```

`auto` uses ox_inventory if it's installed, otherwise qb-inventory. The server console prints `Inventory: <name>` on start so you can see which one it picked. Renamed a resource? Change `Config.OxInventory` or `Config.QBInventory`.

| | ox_inventory | qb-inventory 2.x |
|---|---|---|
| Item logs (moves, drops, shops, crafting, script-created items) | ✅ | ✅ needs 2.2+ (the version with `AddHook` / `AddListener`) |
| Players online and offline, give, remove, wipe | ✅ | ✅ |
| Find item, server-wide give and remove, anti-dupe, rollbacks | ✅ | ✅ weapon serials are read from `serie` |
| Stashes & trunks browser | ✅ | ✅ everything in the `inventories` table |
| Editor pages | Items, Weapons, Shops, Stashes, Crafting, Evidence, Licenses, Animations | Items, Weapons, Shops (locations and product lists) |
| Edits go live | Items, weapons, shops, stashes, crafting with the bridge below | Items instantly through qb-core. Shops restart qb-shops for you. Weapons after a server restart |

### qb-inventory setup

The panel edits three files that live outside its own folder: `qb-core/shared/items.lua`, `qb-core/shared/weapons.lua` and `qb-shops/config.lua` (item images go into `qb-inventory/html/images`). FiveM blocks a resource from writing into another one, so allow it once in `server.cfg`:

```cfg
add_filesystem_permission nayzeee-inventorylogs write qb-core
add_filesystem_permission nayzeee-inventorylogs write qb-shops
add_filesystem_permission nayzeee-inventorylogs write qb-inventory
```

Can't use that command? Copy `bridge/nz_writer.lua` into each of those resources and add `server_script 'nz_writer.lua'` to their `fxmanifest.lua`. Either way works, you only need one.

Restarting qb-shops after a shop edit uses the `restart` command. If your server limits commands, allow it:

```cfg
add_ace resource.nayzeee-inventorylogs command.restart allow
```

> 💡 qb-core loads `weapons.lua` once at start, so weapon edits save straight away but apply on the next server restart. Item edits go live through qb-core's `UpdateItem` / `AddItem` exports.

### 🧩 Your own inventory

Open `inventories/custom.lua`, set `Config.Inventory = 'custom'`, and fill in the functions. Four are required (item list, read an inventory, add, remove). Every other one switches on a feature, and the comments say which. The file stays open when the script is escrowed, so developers can ship their own integration too: drop a new file in `inventories/` and it's picked up automatically.

No events to hook into? Your inventory, or any script, can report instead:

```lua
exports['nayzeee-inventorylogs']:LogMove({ source = src, item = 'water', count = 1, fromType = 'player', toType = 'stash', from = src, to = 'police_locker' })
exports['nayzeee-inventorylogs']:LogShop({ source = src, item = 'water', count = 1, shop = '24/7', price = 5, currency = 'cash' })
exports['nayzeee-inventorylogs']:LogCraft({ source = src, item = 'lockpick', count = 1, bench = 'mechanic' })
exports['nayzeee-inventorylogs']:LogCreated({ source = src, item = 'weed_bag', count = 5 })
```

## ⚡ Live ox_inventory editing (bridge)

The bridge does two jobs. FiveM only lets a resource write files inside its own folder, so the bridge saves your edits from inside ox_inventory. It then applies them live for the server and every player.

Without the bridge, add this to `server.cfg` so the editor can save at all (changes then show after ox_inventory restarts):

```cfg
add_filesystem_permission nayzeee-inventorylogs write ox_inventory
```

**If you use the ox_inventory that ships with this update**, it's already installed. Skip to step 4.

1. Copy the folder `nayzeee-inventorylogs/ox_bridge/nayzeee` into `ox_inventory/`, so you end up with:

   ```
   ox_inventory/nayzeee/server.lua
   ox_inventory/nayzeee/client.lua
   ```

2. Open `ox_inventory/fxmanifest.lua` and add these two lines right under `client_script 'init.lua'`:

   ```lua
   server_script 'nayzeee/server.lua'
   client_script 'nayzeee/client.lua'
   ```

3. For fully live crafting, open `ox_inventory/modules/crafting/server.lua`, find this line (around line 46):

   ```lua
   for id, data in pairs(lib.load('data.crafting') or {}) do createCraftingBench(data.name or id, data) end
   ```

   and paste this directly below it:

   ```lua
   -- NAYZEEE Inventory Manager: live crafting edits
   NZ_CRAFTING_EXPORT = true
   exports('RegisterCraftingBench', function(id, data) createCraftingBench(id, data) end)
   exports('RemoveCraftingBench', function(id) CraftingBenches[id] = nil end)
   ```

4. Restart ox_inventory once (or the server). The panel's top bar shows **Live editing** when the bridge is working.

> 💡 If you renamed this resource, tell the bridge with `setr inventory:nzmanager "your-folder-name"` in `server.cfg`. Only that resource can call it.

> ⚠️ Re-do steps 2 and 3 after updating ox_inventory, since an update overwrites those two files. The `nayzeee` folder survives unless you delete the whole resource.

### What goes live

| File | Live | Notes |
|---|---|---|
| items.lua | ✅ | Server, every player, and the inventory UI. Lua functions inside an item (button actions, add/remove handlers) start working after the next ox_inventory restart. |
| weapons.lua | ✅ | Weapons, components, ammo, tints |
| shops.lua | ✅ | Markers, blips and targets rebuild for everyone |
| stashes.lua | ✅ | |
| crafting.lua | ✅ | Needs step 3, otherwise the server keeps old recipes until restart |
| evidence.lua | ✅ | |
| vehicles.lua | ✅ | Trunk and glovebox sizes |
| animations.lua | ✅ | |
| licenses.lua | ⏳ | Saves, applies after ox_inventory restarts |
| Item images | ✅ | PNG upload is saved to `ox_inventory/web/images` and shown right away |

Players who join after an edit get the latest version automatically. Everything resets to the files on disk the next time ox_inventory starts, which are the same edits anyway.

## 📥 Installing a new script without a restart

Most scripts (drugs, jobs, heists...) come with a folder of item pictures and a list of items to paste into `items.lua`. There are two ways to add them, and neither needs a restart once the bridge above is installed.

**From the panel**

1. Open **Items** and press **Import a new script's items & pictures**.
2. Drop the script's files onto the window: its pictures, its item list (`.lua` or `.txt`), or the whole folder at once. You can also paste the item list into the box.
3. The window tells you what will happen ("Adds 12 new items, skips 2 that already exist"). Tick **Replace items that already exist** to overwrite those instead.
4. Press **Import**. The items are added to `items.lua` (a backup is made first), the pictures are saved to `ox_inventory/web/images`, and both are live for every player.

Pictures are matched to items by file name (`weed_bag.png` → `weed_bag`). Any picture type works; they're converted to PNG and sized to fit.

**Straight into the files (FTP, txAdmin, VS Code...)**

Edit `items.lua` (or any other data file) and save it, or drop new pictures into `ox_inventory/web/images`. Within a few seconds the panel picks it up and applies it, the same as a save from the panel:

- the file is checked first, and a file with an error is **never applied**: staff with editor access get the error and the line, and the old version keeps running
- the old version is kept under **Code & backups → Backups** (marked "Edited outside the game")
- staff with the panel open see the change straight away, and get a notice if they have unsaved edits in that file

Settings live in `Config.Editor` (`watchFiles`, `watchImages`, `watchSeconds`).

> 💡 New pictures dropped on disk show live on ox_inventory with the bridge. On qb-inventory, new items in `qb-core/shared/items.lua` go live through qb-core, but pictures added on disk show after qb-inventory restarts (qb-inventory has no way to swap pictures live). Pictures uploaded from the panel are written for you either way.

## 💰 Money sources (framework bridge)

ESX, QBCore and Qbox move money inside their own resource, so without this every dollar shows as coming from the framework. The bridge notes which script called the framework, so the **Economy** page and every money log show the real source (for example `nayzeee-drugs` paid $2.8M, `nayzeee-garages` took $1.8M).

1. Copy `nayzeee-inventorylogs/framework_bridge/nayzeee.lua` into the root of your framework resource:

   | Framework | Folder |
   |---|---|
   | ESX Legacy | `es_extended/nayzeee.lua` |
   | QBCore | `qb-core/nayzeee.lua` |
   | Qbox | `qbx_core/nayzeee.lua` |

2. Open that resource's `fxmanifest.lua` and add this as the **very last line**:

   ```lua
   server_script 'nayzeee.lua'
   ```

3. Restart the server. The console prints `money source tracking active` when it's working.

> 💡 The same file works for all three frameworks. It only wraps the money functions (and `addInventoryItem` on ESX) and passes the calling script's name on. It changes nothing about how money works.

> ⚠️ A framework update replaces its `fxmanifest.lua`, so re-add the line after updating.

Without the bridge everything still logs, and the Economy page groups money **By reason** instead (the reason text scripts pass to the framework).

## 🧬 Anti-dupe

Nothing to install. Every 30 minutes (and whenever you press **Scan now**) it reads every inventory: online players, offline characters, stashes, trunks and gloveboxes.

| Check | What it catches |
|---|---|
| Duplicate serials | The same weapon serial (or any key in `Config.AntiDupe.keys`) in two places. Each copy has a **Remove this copy** button. |
| Supply watch | An item whose server-wide total grows more than `percent` and `minimum` between scans, e.g. gold bars going from 410 to 1,620. Click an item for its 7-day chart. |
| Dupe attempts | The same item bounced between the same two inventories 15 times in 10 seconds, the usual pattern of dupe glitch attempts. |

> 💡 ox_inventory's police armoury gives weapons the shared serial `POL`, which is why `POL` is in `Config.AntiDupe.ignoreValues`. Add any other shared serials your scripts use.

> ⚠️ On servers with tens of thousands of characters, raise `scanMinutes` or set `includeOffline = false`. The scan pauses between batches so it doesn't hitch the server.

## 🔫 Using items with a weapon out

ox_inventory blocks every item while a weapon is in the player's hands. To let an item through (a drug, a painkiller, a snack mid-fight), open **Items**, pick the item, and tick **Players can use this while holding a weapon** under *With a weapon out*.

| Setting | Written to items.lua | Needs the bridge |
|---|---|---|
| Any weapon | `allowArmed = true` | No, it's built into ox_inventory |
| Only certain weapons | `allowArmed = true` + `allowArmedWith = { 'WEAPON_PISTOL' }` | Yes. Without the bridge, any weapon is allowed |

Items with a client `export` already run with a weapon out, so this only matters for items that use ox_inventory's own `status`, `anim` and `usetime`.

## 📍 Capturing locations

Every coordinate field in the editor (stashes, shop and crafting locations) has a **Capture** button. The panel hides, you aim at a spot in the world and press **E** to place it (**Scroll** rotates when the field has a heading, **Backspace** cancels), and the panel comes back with the point filled in.

## 💬 Discord logs

Webhooks live in `Config.Webhooks` in `config.lua`. Pick the setup that suits you:

| You want | Fill in |
|---|---|
| One channel for everything | `everything` |
| A channel per kind of log (most servers) | `groups` (leave `types` empty) |
| One specific log in its own channel | `types.<name>` as well, e.g. `types.stash_take` |

Each log uses the first URL it finds: its own `types` entry → `groups.weapons` (weapons only) → its group → `everything`. Empty URLs are skipped, and a log with no URL isn't sent.

| Group | What lands there |
|---|---|
| `players` | give, take (robbing/searching), drop, pickup |
| `storage` | stashes, backpacks, containers, evidence (put in / take out) |
| `vehicles` | trunks and gloveboxes |
| `weapons` | any weapon moving anywhere |
| `shops` | shop purchases and crafting |
| `created` | items a script put into a player's inventory |
| `money` | money in and out (above `Config.MoneyLogs.webhookMinimum`) |
| `security` | flagged items, money spikes, duplicate items, dupe attempts, supply spikes |
| `staff` | staff gives/removes, server-wide actions, rollbacks, editor saves |

`Config.DiscordLogs` sets how they look: the webhook's name and picture, footer, whether to show identifiers, coords and item details, a link for item pictures (`https://your-cdn/items/%s.png`), role pings (`mentions = { security = '<@&ROLE_ID>' }`) and colours. For player pictures on the logs, fill in `Config.Discord` (bot token + guild id).

Logs for the same channel are sent together every `batchSeconds` (up to 10 per message), so busy servers don't hit Discord's rate limit.

## 🔐 Permissions

| Tier | Default groups | Lets staff |
|---|---|---|
| view | admin, superadmin, god, owner | Open the panel, read logs, economy, anti-dupe results, staff leaderboard, look at inventories, search items, change their own alert settings |
| manage | admin, superadmin, god, owner | Give, remove, set amounts, wipe one player, run dupe scans, remove duplicate copies |
| global | superadmin, god, owner | Give to everyone, remove an item from the whole server |
| editor | god, owner | Edit ox_inventory data files, upload images, restart ox_inventory |
| rollback | god, owner | Snapshots and rollbacks |
| wipe | god, owner | Delete logs |

Any tier also grants `view`. There is no fallback: a group that isn't listed and has no ACE gets nothing.

## ⌨️ Commands

| Command | Tier | What it does |
|---|---|---|
| `/inventorymanager` | view | Opens the panel |
| `/igive [id] [item] [amount]` | manage | Gives an item, logged |
| `/iremove [id] [item] [amount]` | manage | Removes an item, leave the amount empty for all |
| `/igiveall [item] [amount]` | global | Gives to every player online |
| `/iremoveall [item]` | global | Removes it from every player online |

Rename or turn any of them off in `Config.Commands`. They don't clash with ox_inventory's own `/giveitem` and `/removeitem`.

## 🔌 Exports

```lua
-- log a give/remove from your own admin script
exports['nayzeee-inventorylogs']:LogAdminGive(adminSource, targetSource, 'goldbar', 'Gold Bar', 5, 'my admin menu')
exports['nayzeee-inventorylogs']:LogAdminRemove(adminSource, targetSource, 'goldbar', 'Gold Bar', 5, 'my admin menu')

-- stop a legit add from being flagged (call right before AddItem)
exports['nayzeee-inventorylogs']:MarkKnownTransfer(playerId, 'goldbar', 5, 'casino payout')

-- log money your script moves outside the framework
exports['nayzeee-inventorylogs']:LogMoneyEvent(source, 'bank', 5000, 'add', 'business payout')

-- write any log row
exports['nayzeee-inventorylogs']:InsertLog({ type = 'created', source_id = src, item_name = 'goldbar', item_count = 1, details = 'Mined gold' })

-- where is this item right now?
local found = exports['nayzeee-inventorylogs']:ScanItem('goldbar', { online = true, offline = true, stashes = true, vehicles = true })

-- permission check for your own tools
exports['nayzeee-inventorylogs']:HasPermission(source, 'manage')
```

## 🛠️ Troubleshooting

| Issue | Solution |
|---|---|
| Top bar says **Bridge missing** | Follow the bridge steps above and restart ox_inventory once. Check the server console for errors from `ox_inventory/nayzeee/server.lua`. |
| Editor says "FiveM blocks scripts from writing into other resources" | FiveM's sandbox only lets a resource write inside its own folder. Make sure `ox_inventory/nayzeee/server.lua` is the latest one from this download (bridge v3 does the save from inside ox_inventory). Without the bridge, add `add_filesystem_permission nayzeee-inventorylogs write ox_inventory` to `server.cfg` instead. |
| Editor says the file has an error and won't open the form | Something in that data file doesn't load. Open **Code & backups**, press **Check**, fix the line it names, or restore a backup. |
| "This file changed since you opened it" | Another admin saved first, or the file was edited on disk. Press reload and redo your change. |
| A file I saved over FTP didn't apply | Check the console: a file with an error is never applied, and the message names the line. Fix it and save again. The watcher can be turned off with `Config.Editor.watchFiles = false`. |
| A picture I dropped into `web/images` doesn't show | The file name has to match the item (`weed_bag.png`), or the item's `client.image`. It has to be a real PNG under `Config.Editor.imageMaxKB`; bigger ones show after ox_inventory restarts. Live pictures need the bridge. |
| Import says "No items found" | Each item needs its name in front of it, like `['weed_bag'] = { label = 'Weed bag', weight = 100 },`. Paste the part of the script's guide that goes inside `items.lua`. |
| Crafting edits show for players but crafting still uses old recipes | Add the crafting export (bridge step 3) and restart ox_inventory once. |
| Picture upload says it didn't save | FiveM blocked the write. On ox_inventory, update the bridge (`ox_inventory/nayzeee/server.lua`). Otherwise add `add_filesystem_permission nayzeee-inventorylogs write <resource>` to `server.cfg`, using the resource named in the message. |
| Uploaded image doesn't show after an ox_inventory restart | The PNG is saved as `ox_inventory/web/images/<item>.png`. If you use a custom `inventory:imagepath` (CDN), upload the file there too. |
| Offline give/remove says the character is online | Offline edits are refused while that character is loaded, so the save can't be overwritten. Use the online view instead. |
| Discord logs don't arrive | Check the URL is in the right place in `Config.Webhooks` (a URL under `types` or `groups` only gets those logs). Set `Config.Debug = true`: a bad or deleted webhook prints `Discord webhook returned 404`. Logs are sent every couple of seconds, not instantly. |
| Money shows as `es_extended` / `qb-core` / `qbx_core` | Install the framework bridge (Money sources above). |
| Money shows as "unattributed" | On ESX, cash that changes inside ox_inventory without going through ESX (a script calling ox `RemoveItem('money')` directly) can't be traced. Shops, drops, gives and stash moves are already handled. Use the `LogMoneyEvent` export in your own scripts. |
| Duplicate alerts for police weapons | Add the shared serial to `Config.AntiDupe.ignoreValues`. |
| Too many in-game alerts | Each staff member can mute alerts with the bell in the panel's top bar, or pick which kinds they get under **My settings**. `Config.NotifyStaff = false` turns them off for everyone. |
| "All characters" list is empty | The character table (`users` on ESX, `players` on Qbox) is read directly. Check the console for "Character search failed" and the error under it. |
| Too many "Item created" rows | Add chatty resources to `Config.CreationLogs.ignoreResources`, or turn creation logs off. |
| Nothing is flagged | Flags only fire for watchlisted items, amounts over a threshold, weapons, or anything from `alwaysCheckResources`, and never for `trustedResources`. |
| Console says "No supported inventory found" | Neither ox_inventory nor qb-inventory is in your resources folder. Set `Config.Inventory = 'custom'` and fill in `inventories/custom.lua`, or check `Config.OxInventory` / `Config.QBInventory` if you renamed the folder. |
| qb-inventory: no item logs, console says "no AddHook/AddListener exports" | Update qb-inventory to 2.2 or newer. Everything else (players, scans, rollbacks, editor) works without it. |
| qb-inventory: saving an item says "FiveM blocks scripts from writing into other resources" | Add the three `add_filesystem_permission` lines from **qb-inventory setup**, or the `nz_writer.lua` file to qb-core, qb-shops and qb-inventory. |
| qb-shops didn't change after saving a shop | The panel restarts qb-shops for you. If your server blocks commands from resources, add `add_ace resource.nayzeee-inventorylogs command.restart allow`. |
| qb-core weapon changes don't show | qb-core reads `weapons.lua` when the server starts. They apply after the next restart. |
