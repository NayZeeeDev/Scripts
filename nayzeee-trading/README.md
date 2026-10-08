# nayzeee-trading

Day trading for FiveM, played on a laptop you place in the world or on a handheld tablet.

- **Laptop:** place it with a raycast (it follows your aim, **E** places it, **scroll** rotates it, hold **Shift** for fine rotation, **Backspace** or right-click cancels). When you use it, your character walks up and the camera zooms into the screen. Then the laptop boots and you log in.
- **Tablet:** you hold it in hand, with a home screen, widgets and the same apps.
- **Desk terminals:** optional fixed locations, set in `Config.Terminals`.

## Features

| | |
|---|---|
| **Accounts** | Practice (paper money, free resets) and Live (deposit and withdraw from your bank) |
| **Orders** | Market, limit, stop and trailing stop. Bracket TP/SL with OCO, Day/GTC, shorting, 2× margin, maintenance-margin liquidation |
| **Execution** | Fills at bid/ask, slippage on large orders, per-share/percentage commissions, price improvement on limits |
| **Market** | 37 symbols: stocks, crypto (24/7) and indices that track their members. Correlated market factor, intraday trends, volatility halts, optional session hours (pre/regular/after) and daily rollover |
| **News** | Company, macro and crypto headlines that gap prices and keep them drifting. Scheduled earnings with countdowns and beat/miss reactions |
| **Tools** | Canvas candlestick chart (5s–15m, EMA 9/21, VWAP, volume, position/order/alert lines, zoom and pan, right-click to trade). Level 2 book, time & sales, screener with sector heatmap, position size calculator, price alerts, leaderboard |
| **Sound** | Synthesized in the UI, no audio files: order filled, placed, cancelled, rejected, alerts, news, margin call, keyboard clicks, boot and shutdown |
| **Hotkeys** | `B` buy at market · `S` sell at market · `F` flatten · `C` cancel orders · `↑↓` switch symbol · `1–5` timeframe · `Esc` close |

## Performance

- **Client:** idle at **0.00 ms**. There are no per-frame loops unless you are actively placing a laptop, or standing next to one without a target resource. Placed laptops stream in on a 1 s distance check. Quotes are only sent to players who have the app open.
- **Server:** one tick per second. All accounts, orders and alerts are evaluated in memory, and database writes are async.

## Install

1. Requires `ox_lib`, `oxmysql` and OneSync. Supports ESX, QBCore, Qbox and standalone (auto-detected). Standalone has practice trading only.
2. Drop the `nayzeee-trading` folder into your resources and `ensure nayzeee-trading` after its dependencies.
3. Tables are created automatically. `sql/install.sql` is there if you prefer to import them manually.
4. Add the items:

**ox_inventory** (`data/items.lua`)
```lua
['trading_laptop'] = { label = 'Trading Laptop', weight = 2000, stack = false, close = true, client = { export = 'nayzeee-trading.placeLaptop' } },
['trading_tablet'] = { label = 'Trading Tablet', weight = 800,  stack = false, close = true, client = { export = 'nayzeee-trading.useTablet' } },
```

**qb-core** (`shared/items.lua`)
```lua
trading_laptop = { name = 'trading_laptop', label = 'Trading Laptop', weight = 2000, type = 'item', image = 'laptop.png', unique = true, useable = true, shouldClose = true },
trading_tablet = { name = 'trading_tablet', label = 'Trading Tablet', weight = 800,  type = 'item', image = 'tablet.png', unique = true, useable = true, shouldClose = true },
```

**ESX:** add both items to your `items` table. They are registered as usable automatically.

## Config highlights (`config.lua`)

- `Config.Laptop.camera`: where the zoom camera sits relative to the laptop model. If you swap `model`, tune `offset` (camera position) and `target` (point it looks at) until the screen fills the view.
- `Config.Market.horizonMinutes`: how fast a symbol plays out its daily volatility. Lower values make the market more active.
- `Config.Market.hours`: enable real session hours (pre-market, regular, after hours, closed). Off by default, so the market runs 24/7.
- `Config.Symbols`, `Config.News.templates`, `Config.Earnings`: add companies, headlines and earnings pacing.
- `Config.Trading`, `Config.Fees`, `Config.Practice`, `Config.Live`: leverage, shorting, commissions, starting balance and deposit limits.

## Designing the UI in a browser

Open `html/index.html` directly in a browser. It runs a built-in market simulator, so every screen works without the game.
- `?device=tablet` shows the tablet.
- `?onboard=1` shows first-time account setup.
- `?hint=1` shows the placement prompt.

## Exports

```lua
exports['nayzeee-trading']:placeLaptop()
exports['nayzeee-trading']:useTablet()
```
