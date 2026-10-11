# 🏁 nayzeee-racing

Street racing tablet for FiveM: lobbies, ranked ELO with seasons, crews, crew battles, wagers, pink slips, betting, practice runs, spectating, sector splits, elimination, drift and time trials, daily / weekly challenges, track builder, leaderboards and racer profiles.

Client resmon is **0.00 ms** when you are not racing: no thread runs until a race, the track builder, the tablet or the spectator camera is active.

## 📦 Dependencies

| Resource | Required | Notes |
|---|---|---|
| ox_lib | Yes | Callbacks, notify |
| oxmysql | Yes | Database |
| es_extended / qb-core / qbx_core | Optional | Auto detected. Standalone works with license identifiers |
| Inventory | Optional | ox, qb, ps, lj, qs, codem, core, origen, tgiann, mf, tprp |

## 🛠️ Installation

1. Drop the folder in your resources. The folder **must** be named `nayzeee-racing`.
2. Add the `racing_tablet` item from `install/` (ox_inventory, qb-core or the ESX `items` SQL). Keep your existing `racing_tablet.png` image.
3. `ensure nayzeee-racing` after ox_lib, oxmysql, your framework and inventory.
4. Start the server. Tables are created automatically and the 10 default tracks are seeded.
5. Coming from bablo-racing? Leave `Config.Env.ImportFromBablo = true` and the first start copies profiles, crews, tracks and history.

{% hint style="info" %}
Tracks are admin only by default (`Config.Trackbuilder.AdminOnly`). Admins are ESX `admin/superadmin/god`, QB `admin/god` or anyone with the `command` ACE.
{% endhint %}

## ⚙️ Main settings

| Setting | Default | Description |
|---|---|---|
| `Config.General.Item` | `racing_tablet` | Usable item that opens the tablet |
| `Config.General.OpenByCommand` | `false` | Also allow `/racing` + keybind |
| `Config.Races.Respawn.Enabled` | `true` | Hold **X** to reset to your last checkpoint |
| `Config.Races.Respawn.Penalty` | `3000` | ms added per respawn |
| `Config.Races.RequiredParticipantsForRankedLobby` | `4` | Ready racers needed for ranked |
| `Config.Races.WagerCurrencies` | `{ 'money' }` | Empty table disables wagers |
| `Config.Races.MaxCheckpointSpeed` | `150.0` | Anti-cheat speed between gates (m/s) |
| `Config.Notifications.NewLobby` | `profiles` | `all`, `profiles` or `false` |
| `Config.Env.Accounts` | `money / bank` | Wager and payout accounts |
| `Config.Logs.Webhook` | `''` | Discord webhook for results, wagers, tracks, crews |

## 🆕 1.1 features

| Feature | Where | Config |
|---|---|---|
| **Practice** | Tracks → a track → *Practice*. Solo run in the car you drive, sets PBs and world records. Press **E** on the results card to go again | `Config.Practice` |
| **Spectate** | Lobby → *Watch live*, or automatically after you finish / DNF. ← → switch racer, Backspace leaves | `Config.Spectate` |
| **Host only** | Create lobby → *Host only*. Run an event without racing and watch it | `Config.Spectate.HostOnly` |
| **Sector splits** | Race HUD: +/- vs your PB and the WR at every checkpoint. New WRs are announced | `Config.Splits` |
| **Elimination** | Race mode (circuits). Last place is out at the end of every lap | `Config.Races.Elimination` |
| **Quick race** | Sidebar / Lobbies → *Quick race*. Joins the best open lobby for your car's class or creates one | `Config.QuickRace` |
| **Auto-accept** | Create lobby toggle. Joiners skip the host's approval | — |
| **Pink slips** | Create lobby toggle. Winner takes every other car's title. Needs owned cars | `Config.PinkSlips` + `Bridge.OwnsVehicle / TransferVehicle / OnPinkSlip` |
| **Seasons** | ELO resets every `LengthDays`, top racers get paid + a badge on their profile. `racingseason end` in the console ends one now | `Config.Seasons` |
| **Challenges** | Home → Challenges. Same daily / weekly picks for everyone, rewards in the inbox | `Config.Challenges` |
| **Direct invites** | Lobby → *Invite*, or a racer's profile → *Invite to my lobby*. Invites skip the password and the queue | — |
| **Betting** | Waiting lobby → *Place a bet*. Parimutuel pool, house cut, refunds when the racer leaves | `Config.Betting` |
| **Crew tracks / records** | Track visibility *Crew*; Crew → Records; track Top 10 → *Crew* | `Config.Trackbuilder.CrewTracks / CrewCanBuild` |
| **Auto vehicle class** | `Config.Vehicles.GetClass` returns `'auto'` → class from handling. Return your own class to override. `/racingclass` shows a car's index | `Config.Vehicles.AutoClass` |
| **Modded vehicle check** | Power / top speed vs base handling at the start and every 5 s | `Config.AntiCheat` |
| **Vehicle swap detection** | Model or plate change mid-race = DNF | `Config.AntiCheat.SwapDetection` |

Practice runs never count as races / wins (`Config.Practice.CountsForStats`). New tables and columns are added automatically on start.

## 🗺️ Maps

Track previews (tablet, lobbies, track builder) are drawn on a real GTA map. Three styles ship in `web/maps/`: **Road**, **Satellite** and **Dark**. All three are transparent and use the same bounds. Players pick one in **Settings → General → Map style**. `Config.UI.Maps.Default` sets the default.

**Add your own map**

1. Put your image in `web/maps/` (PNG, JPG or WEBP).
2. Open `install/map-calibrator.html` in a browser and load the same image.
3. Click a spot on the reference map, then the same spot on yours. Do it 3 times, far apart (north, south-west, east). The North Side track appears on your map when it lines up. Aim for a max error under 40 m.
4. Copy the line it gives you into `Config.UI.Maps.List` and restart the resource.

```lua
mymap = { label = 'My Server', image = 'maps/mymap.png', bounds = { minX = -3621.43, maxX = 4175.99, minY = -3803.99, maxY = 7758.54 } },
```

**Use your server's streamed map (stream folder)**

Most custom maps come as a `stream` folder with `minimap_sea_0_0.ytd` to `minimap_sea_2_1.ytd`. The tablet reads those textures straight from the game, so there's nothing to convert or calibrate.

1. Keep the map in its own resource (see `install/stream-map-example/`):
   ```
   resources/
     [maps]/
       my-server-map/
         fxmanifest.lua
         stream/
           minimap_sea_0_0.ytd ... minimap_sea_2_1.ytd
   ```
   Already running a map resource? Skip this step.
2. `ensure my-server-map` before `ensure nayzeee-racing`.
3. In `config.lua`, uncomment the `server` entry in `Config.UI.Maps.List`. Make it the default if you want:
   ```lua
   Maps = {
       Default = 'server',
       List = {
           server = {
               label  = 'Server Map',
               stream = { dict = 'minimap_sea_%d_%d', texture = 'minimap_sea_%d_%d', rows = 3, cols = 2 },
               bounds = { minX = -4140.0, maxX = 4860.0, minY = -5100.0, maxY = 8400.0 },
           },
           -- road / satellite / dark ...
       },
   },
   ```
4. Restart. **Server Map** appears in Settings → Map style.

{% hint style="info" %}
The bounds are GTA's own minimap grid, so they're the same for every streamed map. Only change `dict` / `texture` if your map pack uses different file names.
{% endhint %}

## 🎮 Commands & keys

| Command / Key | Description |
|---|---|
| `/dnf` | Give up your current race |
| Hold `X` | Respawn at your last checkpoint (rebindable) |
| `/racing` | Open the tablet (only with `OpenByCommand`) |
| `/racingclass` | Performance index + class of your car (tune `Config.Vehicles.AutoClass`) |
| `racingseason [end]` | Console / admin: show the season, or end it now |
| ← → / Backspace | Spectating: switch racer / leave |

**Track builder:** ← → gate width · ↑ ↓ rotate · Shift/Ctrl + arrows move one post · Enter add gate · Delete remove last · Z circuit/sprint · Shift+Enter save · F10 help · Esc cancel.

## 🔌 Exports

```lua
exports['nayzeee-racing']:openApp()
exports['nayzeee-racing']:closeApp()
exports['nayzeee-racing']:isInRace()
```

## 🧩 Hooks (open files)

| File | What to edit |
|---|---|
| `bridge/server.lua` | Money, identifiers, owned vehicles, items, `GiveXp`, pink slip ownership / transfer / keys |
| `config.lua` → `Config.Vehicles.GetClass` | Your vehicle class system (`'auto'` = from handling) |
| `config.lua` → `Config.Hud` | Hide your HUD while racing |
| `config.lua` → `Config.Notify` | Your notification resource |

## ❓ Troubleshooting

| Issue | Solution |
|---|---|
| Resource stops on start | Folder must be named `nayzeee-racing` |
| No vehicles in the picker | `Config.Vehicles.GetClass` returned `nil`, or the garage table differs. Edit `Bridge.GetOwnedVehicles` |
| "Not in the chosen vehicle" on start | Every racer must drive the car they picked (plate is checked) |
| Checkpoints not counting | Drive through the gate between the posts. Rejected gates are logged with `Config.LogLevel = 'warn'` |
| Wager not taken | Check `Config.Env.Accounts.wager` matches your account name |
| Classes look wrong | Run `/racingclass` in a few cars and adjust `Config.Vehicles.AutoClass` thresholds, or return your own class from `GetClass` |
| Honest racers flagged as modded | A tuning / nitro script changes handling: raise `AccelTolerance` / `MaxTopSpeedModifier`, add the model to `IgnoreModels`, or set `ModdedVehicles = false` |
| Pink slip didn't move the car | Your garage table differs: edit `Bridge.OwnsVehicle` and `Bridge.TransferVehicle` |
