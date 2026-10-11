**Resource:** nayzeee-inventorylogs (Inventory Manager)
**Version:** 3.2.0
**Changes:**

🟢 **New**
- **Import a new script's items & pictures**: on the Items page, drop a script's pictures, its item list (`.lua` / `.txt`) or its whole folder onto one window. It shows what will be added or skipped, adds the items to `items.lua` with a backup, uploads every picture, and it's all live without a restart
- **Edits made outside the game go live**: save `items.lua` (or any data file) over FTP, txAdmin or VS Code, or drop pictures into `ox_inventory/web/images`, and the panel applies it within a few seconds. Broken files are never applied (staff get the error and line), the old version is kept as a backup, and open panels refresh by themselves
- `Config.Editor.watchFiles`, `watchImages` and `watchSeconds`
- Rollbacks report stacks that couldn't be given back (item no longer exists or no room) instead of saying everything was restored

🟠 **Fixed**
- Scrolling down a list (Items, Weapons, Shops, Stashes, Crafting, Other data, Code & backups) and clicking an entry jumped back to the top of the list. Lists, the editor form and the code view now stay where you left them, also after adding a row, capturing a location or saving
- Small blurry black corners showed at the top-left and bottom-left of the panel (and pop-ups): the panel's drop shadow leaked out around the rounded corners
- qb-core money bridge never switched on for online players, so money always showed as coming from `qb-core`
- Money snapshots could save a character's items instead of their money on servers without ESX/QBCore/Qbox, and a money rollback could stop halfway on one bad account
- Giving a weapon to an offline character several times gave every copy the same serial, which then showed up as a duplicate in anti-dupe
- One log with an over-long value (a long item label, name or resource from another script) made the database drop every log written in the same second
- Logs written while the database was still being set up waited for the next log, and could pile up forever if the database never came up
- Server-wide remove accepted 0, negative or fractional amounts
- Server-wide give could hand out items and then fail before writing the log, audit entry and webhook
- Picture size limit in the panel now follows `Config.Editor.imageMaxKB` everywhere (it only did after opening Code & backups)

---

**Version:** 3.1.1
**Changes:**

🟢 **New**
- Works with **ox_inventory**, **qb-inventory** or **your own inventory**. Pick one with `Config.Inventory` (or leave it on `auto`), and the whole panel follows it: sidebar name, editor pages, stashes, item images, weapon serials and item logs
- qb-inventory support: item logs through its hooks and listeners (2.2+), online and offline players, find item, server-wide give and remove, anti-dupe on `serie`, rollbacks
- qb-inventory editor: Items (`qb-core/shared/items.lua`, live through qb-core), Weapons (`qb-core/shared/weapons.lua`), and Shops with Locations and Product lists (`qb-shops/config.lua`, restarts qb-shops so it applies)
- Integration file for other inventories (`inventories/custom.lua`): four required functions, every other one switches a feature on. Stays open under escrow, and new files dropped in `inventories/` load automatically
- Exports for inventories without events: `LogMove`, `LogShop`, `LogCraft`, `LogCreated`
- **Stashes & trunks** page: every saved stash, trunk and glovebox, searchable, opens straight into the inventory
- `bridge/nz_writer.lua`: lets the panel save into another resource on servers that can't use `add_filesystem_permission`
- Remove an item from a stash or trunk that isn't loaded (edits its saved copy)
- Picture editor for item images: any picture works (PNG, JPG, WEBP, GIF, BMP, any size). Pick a file, drag it onto the item's picture, or paste it with Ctrl+V, then choose the size (64 to 256px), show the whole picture or fill the square, zoom, drag to frame it, and remove a plain background. It's saved as a PNG
- New items can get a picture before they're created; it uploads when you press Create
- Cleaner Discord logs: every log is one tidy card with who did it (name, ID and Discord picture), a player card for each person (character name, job and grade, Discord mention, character id, license), the item with its picture, **from → to** in plain words (Player 3 (Name), Trunk `ABC123`, Stash `police_locker`), the script that caused it, where it happened, and item details (serial, registered owner, durability, ammo, attachments)
- Staff logs show the target, whether they were online, and the method; server-wide give/remove show the full breakdown (online, offline, stashes, vehicles, who couldn't carry it); rollbacks show the snapshot, how many were restored and skipped; editor saves show the file, entry, category and whether it applied live
- Duplicate item logs list every place the copy was found; supply spikes show before, now and the change
- Money logs show the amount, account, reason and script, green for money in and red for money out
- Webhooks are grouped: paste one URL into `everything`, or one per group (players, storage, vehicles, weapons, shops, created, money, security, staff), or split out a single type. Old flat configs still work
- `Config.DiscordLogs`: webhook name and picture, footer, show or hide identifiers, coords and item details, item picture link, role pings per group or type, and colours
- Logs for the same channel are sent together (up to 10 per message), and Discord rate limits are waited out and retried instead of lost

🟠 **Fixed**
- **Choose picture** only worked once; after picking a picture the button did nothing until the panel was reopened
- Player profile header showed initials instead of the player's Discord picture (the list beside it already showed it)
- Item pictures only accepted PNG files under 256 KB, so most pictures from a desktop were turned away
- Checkboxes inside pop-up windows (such as "Ignore their weight limit" when giving an item) couldn't be ticked
- A picture upload that FiveM silently didn't write now says so instead of reporting it saved
- qb-inventory: uploading a picture for an item that used a shared file (like placeholder.png) replaced it for every item; each item now gets its own `<item>.png`

**Modified files:**
```diff
+ server/inventory.lua
+ server/logging.lua
+ inventories/ox_inventory.lua
+ inventories/qb-inventory.lua
+ inventories/custom.lua
+ bridge/nz_writer.lua
- server/hooks.lua
~ server/core.lua
~ server/luadoc.lua
~ server/editor.lua
~ server/webhooks.lua
~ server/global.lua
~ server/snapshots.lua
~ server/money.lua
~ server/dupe.lua
~ server/players.lua
~ server/commands.lua
~ web/js/core.js
~ web/js/editor.js
~ web/js/pages.js
~ web/css/style.css
~ config.lua
~ fxmanifest.lua
~ INSTALL.md
```

---

**Resource:** nayzeee-inventorylogs (Inventory Manager)
**Version:** 3.1.0
**Changes:**

🟢 **New**
- Economy page: money in, out and net over 24h/7d/30d, an in-vs-out chart, and **Sources** vs **Sinks** by script or by reason, each clickable for reasons, accounts and the players involved
- Items view on the Economy page: which scripts create items, how many, and who received them
- Income tab on every player: where their money came from, what they spent it on, and which scripts gave them items
- Framework bridge (`framework_bridge/nayzeee.lua`, one file for ESX, QBCore and Qbox) so money and item logs name the script that caused them instead of the framework
- ESX shop purchases in ox_inventory are logged as money leaving, and cash moved between inventories no longer counts as income or spending
- Anti-dupe: scheduled scan of every inventory for duplicate serials, with Remove this copy for each one
- Supply watch: flags items whose total on the server jumps between scans, with a 7-day chart per item
- Dupe attempt detection for items bounced between the same two inventories many times in seconds
- Staff leaderboard: actions, gives, removals, wipes, edits, rollbacks and server-wide actions per staff member, with items and money handed out and a "high" marker from `Config.StaffBoard`
- New log types: Duplicate found, Dupe attempt, Supply spike, plus a combined "Dupe alerts" filter
- Use items with a weapon out: a per-item switch in the Items editor (`allowArmed`), optionally limited to certain weapons (`allowArmedWith`, needs the ox_inventory bridge)
- Capture button on every location field: the panel hides, you aim at a spot and press E to place it (Scroll rotates, Backspace cancels)
- Per-staff alert settings: a bell in the top bar mutes in-game alerts, and **My settings** picks which kinds you get (flags, dupe alerts, other staff actions) and turns panel sounds on or off
- Staff no longer get an in-game alert for their own actions

🟠 **Fixed**
- Money spike alerts fired when players moved money between their own accounts (e.g. a bank withdrawal); spikes now use the net change across all accounts and wait for both halves of a transfer
- Amounts in alerts are formatted with commas
- ESX money is now read from ESX's own money events with the reason text, and the balance check only catches what those events miss
- Players tab: **All characters** showed nothing until an exact search, and fast typing plus Enter searched for the old text. It now lists recently seen characters straight away, searches as you type, and works with any column layout in `users` / `players`

**Modified files:**
```diff
+ server/attribution.lua
+ server/dupe.lua
+ server/economy.lua
+ web/js/insights.js
+ framework_bridge/nayzeee.lua
~ client/main.lua
~ server/players.lua
~ server/editor.lua
~ server/boot.lua
~ web/js/pages.js
~ web/js/editor.js
~ ox_bridge/nayzeee/client.lua
~ server/money.lua
~ server/hooks.lua
~ server/database.lua
~ server/core.lua
~ config.lua
~ fxmanifest.lua
~ web/index.html
~ web/css/style.css
~ web/js/core.js
~ INSTALL.md
```

---

**Resource:** nayzeee-inventorylogs (Inventory Manager)
**Version:** 3.0.1
**Changes:**

🟢 **New**
- Rebuilt panel in the v5 design: sidebar navigation, dashboard, filterable logs with live mode, CSV copy, and a detail view per log
- ox_inventory editor for items, weapons, shops, stashes, crafting, evidence, licenses and animations, with a form view and a Lua code view
- Edits keep everything you didn't touch exactly as written (comments, backtick hashes, `shared.police`, item functions)
- Live apply through a small ox_inventory bridge: items, weapons, shops, stashes, crafting, vehicle storage and animations update for the server and every player without a restart
- Item image upload (PNG), shown to players immediately
- Automatic backups on every save (25 per file), view and one-click restore, plus a raw editor for every data file
- Server-wide give with job filter, skip list, player message, metadata and weight override
- Find item: counts every copy across online players, offline characters, stashes and vehicle trunks and gloveboxes, then removes them in one action
- Delete an item from items.lua and purge every copy in the same step
- "Item created" logs record which resource created every item a player receives
- "Taken from player" log type for robbing and searching
- Staff audit trail page
- Snapshots saved to the database, keyed by character, with a "then vs now" compare before rolling back
- Rollback works for offline characters too (inventories)
- Money spike alerts (configurable window and amount)
- Permission tiers: view, manage, global, editor, rollback, wipe, with ACE `nayzeee.inventory.<tier>`
- New commands `/igive`, `/iremove`, `/igiveall`, `/iremoveall`, plus exports `ScanItem`, `InsertLog`, `HasPermission`
- Local fonts and icons, so nothing loads from a CDN

🟠 **Fixed**
- Player names were inserted into the panel unescaped, so a crafted name could run script in an admin's panel
- Suspicious detection never ran (it read a field ox_inventory doesn't send)
- Transfer logs recorded the stack size instead of the amount actually moved
- Swaps only logged one side of the trade
- QBCore money hook used `RegisterNetEvent`, so any client could forge money logs
- ESX money logs were always empty (ESX Legacy fires no money events); balances are now polled
- Offline edits read and wrote a table ox_inventory never uses for players
- QBCore + ox offline edits wrote qb-inventory item format and broke the item
- ESX offline give and remove were missing
- Offline edits could run while the character was online and get overwritten
- `/giveitem` and `/removeitem` overrode ox_inventory's own commands and dropped metadata
- Admin webhooks lost the admin and method fields
- Snapshots were keyed by license, so a rollback could hit another character on the same account
- Snapshots were lost on restart or crash
- ACE `group.*` checks granted access on every framework
- Two client loops ran while the panel was closed; the client now runs nothing while idle
- Logs are batched into one insert per second instead of one query per event
- Log retention only ran at start, now every 6 hours
- Hooks re-register when ox_inventory restarts

🟠 **Removed**
- qb-inventory support (ox_inventory is required for hooks and the editor)
- The weapon log type; weapon moves are logged under their normal type and still use the `weapon` webhook

**Modified files:**
```diff
+ server/inventory.lua
+ server/logging.lua
+ inventories/ox_inventory.lua
+ inventories/qb-inventory.lua
+ inventories/custom.lua
+ bridge/nz_writer.lua
- server/hooks.lua
~ server/core.lua
~ server/luadoc.lua
~ server/global.lua
~ server/snapshots.lua
~ server/money.lua
~ web/js/core.js
~ config.lua
~ fxmanifest.lua
+ server/core.lua
+ server/database.lua
+ server/webhooks.lua
+ server/discord.lua
+ server/hooks.lua
+ server/money.lua
+ server/players.lua
+ server/global.lua
+ server/snapshots.lua
+ server/editor.lua
+ server/luadoc.lua
+ server/commands.lua
+ server/boot.lua
+ web/index.html
+ web/css/style.css
+ web/js/core.js
+ web/js/pages.js
+ web/js/editor.js
+ ox_bridge/nayzeee/server.lua
+ ox_bridge/nayzeee/client.lua
+ sql/install.sql
+ INSTALL.md
~ config.lua
~ fxmanifest.lua
~ client/main.lua  (was client/cl_main.lua)
- server/sv_*.lua
- html/index.html
```

**ox_inventory changes (already applied in the included copy):**
```diff
+ ox_inventory/nayzeee/server.lua
+ ox_inventory/nayzeee/client.lua
~ ox_inventory/fxmanifest.lua                 (+2 lines)
~ ox_inventory/modules/crafting/server.lua    (+4 lines)
```
