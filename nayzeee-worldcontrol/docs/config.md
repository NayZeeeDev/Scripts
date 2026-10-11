# ⚙️ Configuration

> Configuration reference for NAYZEEE WorldControl. Every option is also commented in `shared/config.lua`.

---

## 🎮 Commands

| Setting | Default | Description |
|---------|---------|-------------|
| `Config.Command` | `'worldcontrol'` | Opens the panel |
| `Config.CommandAliases` | `{ 'traffic', 'easytime', 'weathermenu' }` | Extra commands that also open the panel |
| `Config.Keybind` | `nil` | Optional keybind (e.g. `'F7'`) |
| `Config.QuickCommands` | see file | Names for `/weather`, `/time`, `/freezetime`, `/blackout` and `/restartwarning`. Set one to `false` to disable it. |

## 🔔 Notifications

`Config.Notify = 'auto'`: uses ox_lib if it's started, otherwise the built-in NAYZEEE toasts. Other options are `'nui'`, `'ox_lib'`, `'qb'`, `'esx'` and `'chat'`.

## 🔒 Permissions

```lua
Config.Permissions = {
    enabled = true,
    acePermissions = { 'worldcontrol.admin', 'traffic.control' },
    allowedGroups = { 'admin', 'superadmin', 'mod', 'god' }, -- ESX group / QB permission / ACE group.<name>
    identifiers = { 'license:xxxx' },
}
```

## ⚡ Performance

| Setting | Default | Description |
|---------|---------|-------------|
| `densityMode` | `'frame'` | `'frame'`: exact control. 0.00ms at 100% density, about 0.01ms while a slider is changed. `'zero'`: always 0.00ms. It uses population budgets plus a map-wide multiplier area and is less granular. |
| `watchdogInterval` | `5000` | How often (ms) the client checks that the weather is still correct |

## 🌦️ Weather

| Setting | Default | Description |
|---------|---------|-------------|
| `default` | `'EXTRASUNNY'` | Weather on first start. After that, the last state is restored. |
| `method` | `'game'` | `'game'` or `'real'` |
| `instant` | `false` | Default for instant changes |
| `transitionTime` | `45.0` | Seconds a smooth weather change takes |
| `dynamic` | `true` | Cycle the weather automatically |
| `interval` | `15` | Minutes between changes |
| `forecastLength` | `4` | Number of upcoming weathers shown |
| `groups` | see file | Weighted weather groups. Entries can be `{ 'THUNDER', chance = 40 }`. |
| `real.apiKey` / `real.city` | | OpenWeatherMap key and city |
| `real.checkInterval` | `15` | Minutes between real-weather checks |
| `real.syncWind` | `true` | Copy the real wind too |

`Config.WeatherTypes` controls which weathers the panel shows, their labels and icons ([Font Awesome](https://fontawesome.com/search?o=r&m=free) names), and their order.

## 🕐 Time

| Setting | Default | Description |
|---------|---------|-------------|
| `default` | `08:00` | Time on first start |
| `method` | `'game'` | `'game'` or `'real'` |
| `transitionTime` | `6000` | Milliseconds a smooth sky roll takes |
| `msPerGameMinute` | `2000` | 2000 is the GTA default (a 48 minute day) |
| `syncInterval` | `30` | Seconds between drift-correction heartbeats |
| `real.utcOffset` | `-7` | Hours from UTC for real time |
| `quick` | see file | Quick time buttons |

## 🌫️ World

`blackout`, `blackoutAffectsVehicles`, `snowOnGround`, `wind` (0-12, `-1` = auto), `windDirection`, `rain` (0-1, `-1` = auto).

## 🚦 Traffic

```lua
Config.Traffic = {
    maxDensity = 1.5,
    defaults = { pedestrians = 1.0, vehicles = 1.0, parkedCars = 1.0, randomVehicles = 1.0, scenarioPeds = 1.0 },
    services = { dispatch = false, garbageTrucks = false, randomBoats = false, randomTrains = true,
                 randomCops = true, wantedLevel = true, distantSirens = true },
    purge = { enabled = true, radius = 150.0, duration = 3000, interval = 500 },
}
```

`Config.TrafficPresets` is an ordered list of presets.

## 🎬 Scenes

Each scene can set `weather`, `hour`, `minute`, `blackout`, `snowOnGround`, `wind`, `rain` and `traffic` (a preset id). Fields you leave out keep their current value.

## 🌊 Restart Warning

| Setting | Default | Description |
|---------|---------|-------------|
| `minutes` | `5` | Default countdown length |
| `txAdmin` | `true` | Start automatically on txAdmin scheduled restarts |
| `weather` | `'THUNDER'` | Storm weather. Build 3258+ uses `RAIN_HALLOWEEN`. |
| `blackoutAt` | `0.5` | How far through the countdown (0-1) the blackout and siren start |
| `siren` / `sirenVolume` | `true` / `0.25` | Synthesised siren |
| `title` / `message` | | Banner text |

## 🏠 Compat

`pauseEvents`, `pausedWeather` and `pausedHour` control what players see while another script has paused sync, for example inside a house.

## 📜 Log

`size` (number of entries kept), `console` (also print to the server console) and `webhook` (Discord webhook URL).
