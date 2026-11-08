# nayzeee-coinshop

Coin shop for ESX Legacy, QBCore and Qbox. Vehicles, items, weapons and tools, bundles, Tebex order redeem, gifting, promo codes and a full in-game admin panel.

## Install
1. Drop `nayzeee-coinshop` in your resources (the folder name must stay exactly `nayzeee-coinshop`).
2. `ensure ox_lib`, `ensure oxmysql`, your framework, then `ensure nayzeee-coinshop`.
3. Tables are created on first start. Coming from FearX-Coinshop? Wallets, packages, categories, deals, Tebex codes and purchase history are imported automatically once.
4. Add your admins in `server_config.lua` (identifier list, the `nayzeee.coinshop.admin` ACE, or framework admin groups).
5. Tebex: see **Connecting Tebex packages** below. No Tebex secret key is needed.

## Bundles
Admins (anyone with admin panel access) build bundles in game: **Admin panel → Bundles → New bundle**.

- Pick up to `Config.Shop.DealMaxItems` packages and set an amount for each (vehicles and framework weapons are always x1).
- Optional extras: an in-game **cash bonus** (paid to `Config.Bundles.CashAccount`), **stock** (total sold), **per player** limit and a **limited time** in hours.
- The editor shows the value if bought separately and quick "Set 10/20/30/40% off" price buttons, with a live preview card.
- **Featured** bundles rotate in the home page banner every `Config.Bundles.HeroSeconds`. **Visible** off hides a bundle without deleting it.
- Reorder with the arrows. Expired bundles stay in the list for 7 days so you can extend them.

Delivery: if a package cannot be delivered (inventory full), that package's share of the price is refunded automatically. If nothing can be delivered, the whole price is refunded and the stock is put back. When a bundle has more than one vehicle, the first one spawns next to the player and the rest go to the garage.

Updating from v1.0.0: just replace the files. The new bundle columns are added to the database on start, existing deals become bundles, and an old `config.lua` without `Config.Bundles` keeps working with default values.

## Connecting Tebex packages
The shop does not poll the Tebex API and does not need `TEBEX_SECRET` or a package-ID list. Each coin package on your store runs one server command on purchase, which stores the order as a code. The player then redeems the order number in the shop.

1. Install the official Tebex FiveM resource (`tebex`) on your server and link it to your store (`sv_tebexSecret` is only needed by that resource, not by this shop).
2. Tebex control panel → **Packages** → open your coin package (for example "1000 Coins") → **Game Server Commands** → **Add command**.
3. Command to add, with the real coin amount at the end:
   ```
   coinshop_addcode {transaction} 1000
   ```
   `{transaction}` is a Tebex variable and must be typed exactly like that; Tebex replaces it with the order number (`tbx-xxxxxxxxxxxxx-xxxxxx`).
4. In the command settings turn **Require player to be online** off, so the command runs right after payment even if the player is not in the city. Leave the delay at 0.
5. Repeat for every coin package, changing only the number (`coinshop_addcode {transaction} 2500`, …).
6. Set `Config.General.StoreUrl` in `config.lua` to your store link so the **Buy coins** buttons open it.

How a purchase flows: payment → Tebex runs `coinshop_addcode tbx-… 1000` in your server console → the order is saved as a pending code → the player opens the shop, presses **Redeem code**, pastes the `tbx-` order number from the receipt email or the store → coins are added. Each order can only be redeemed once, and admins can see or delete pending codes under **Admin → Codes**.

Testing without spending money: run `coinshop_addcode tbx-test-1 500` in the server console (or txAdmin console), then redeem `tbx-test-1` in game. Tebex also lets you resend a payment's commands from the payment page if one was missed.

Coming from wasabi_vipshop? Its `Config.TebexPackageIDs = { [packageId] = coins }` table is not needed here: the coin amount lives in the command on each package instead.

## Files you can edit
- `config.lua` – command/key, test drive, vehicles, gifting, playtime rewards, limits, bundles (cash account, banner speed), UI scale.
- `server_config.lua` – admins, Discord bot token (profile pictures), webhooks.
- `bridge/server.lua` – framework, inventory, garage, vehicle keys, notifications, bundle cash (`Bridge.AddMoney`).
- `bridge/client.lua` – vehicle keys, fuel, notifications on the client.
- `locales/en.json` – every text in the UI and messages.

## Commands
- `/coinshop` (F5) – open the shop
- `/givecoins [id] [amount]`, `/setcoins [id] [amount]`, `/removecoins [id] [amount]` – admins / console
- `coinshop_addcode <order> <coins>` – console / Tebex (creates a redeemable code)

## Exports
Server:
```lua
exports['nayzeee-coinshop']:GetCoins(source)
exports['nayzeee-coinshop']:AddCoins(source, amount, note)
exports['nayzeee-coinshop']:RemoveCoins(source, amount, note)   -- returns false if the balance is too low
exports['nayzeee-coinshop']:SetCoins(source, amount, note)
exports['nayzeee-coinshop']:GetCoinsByIdentifier(identifier)
exports['nayzeee-coinshop']:AddCoinsByIdentifier(identifier, amount, note)
```
Client: `exports['nayzeee-coinshop']:openShop()`, `closeShop()`, `isOpen()`

## Events (server)
- `nayzeee-coinshop:purchased` (src, identifier, itemId, qty, coins, giftTargetSrc) – also fired for bundles (itemId = bundle id)
- `nayzeee-coinshop:redeemed` (src, identifier, order, coins, giftTargetSrc)
- `nayzeee-coinshop:coinsChanged` (src, identifier, oldBalance, newBalance, reason)

Client: `nayzeee-coinshop:vehicleSpawned`, `nayzeee-coinshop:testDriveStarted`, `nayzeee-coinshop:testDriveEnded`

Docs: nayzeee-dev.gitbook.io/docs · Discord: discord.gg/nayzeeedev
