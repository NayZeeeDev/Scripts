# 🌍 NAYZEEE WorldControl

> Weather, Time, Traffic & Population Control for FiveM
>
> discord.gg/nayzeeedev

Formerly **nayzeee-traffic**. It now does everything that script did, plus a full weather and time system. You no longer need a separate weathersync (cd_easytime, qb-weathersync, vSync).

---

## ✨ Features

### 🌦️ Weather
- **17 weather types**, including the Halloween variants on game build 3258+
- **Dynamic weather cycle** that moves through weighted groups in a natural order (clouds → overcast → rain → thunder → clearing)
- **Live forecast** of the next weathers with a countdown, plus **Skip** and **Reroll** buttons
- **Smooth or instant** transitions
- **Real-world weather** from any city through OpenWeatherMap, including real wind
- **Atmosphere controls**: blackout, snow on the ground (with tyre and footstep tracks), wind speed and direction, and rain intensity
- Wind and rain are synced, so every player sees the same storm

### 🕐 Time
- The server owns the clock and GTA runs it natively, so there are **no per-frame time loops**
- **Quick time** buttons (Dawn, Morning, Noon, Sunset, Night, Midnight)
- **Smooth sky roll** to a new time, with easing and midnight wrap
- **Freeze time**
- **Day length** slider from 6 minutes to 8 hours per in-game day
- **Real-world time** from a UTC offset, or from the real-weather city's timezone
- Drift correction: clients only snap their clock if they wander off

### 🚦 Traffic & Population
- 5 density sliders: pedestrians, vehicles, parked cars, random traffic and scenario peds
- 6 presets: Empty City, Minimal, Light, Normal, Rush Hour and Walkers
- **Ambient services** you can toggle live: dispatch, garbage trucks, boats, trains, cop patrols, wanted level and distant sirens
- **Instant purge** clears existing NPCs and cars when density goes down, and there's a "Clear Area Now" button

### 🎬 Events
- **Scenes**: one click sets weather, time, atmosphere and traffic together (Christmas, Halloween, Storm Front, Ghost Town and more)
- **Lightning strike** for every player
- **Restart warning (tsunami)**: storm, then blackout, then a siren with an on-screen countdown banner. It **starts automatically on txAdmin scheduled restarts**.

### 🛠️ Admin
- Tabbed NAYZEEE panel in the same style as the other NAYZEEE scripts
- **Live multi-admin sync**: every open panel updates instantly
- **Activity log** of who changed what, with optional Discord webhook
- Quick chat commands: `/weather`, `/time`, `/freezetime`, `/blackout`, `/restartwarning`
- Permissions: ACE, ESX groups, QBCore permissions, Qbox / vanilla `group.*` ACE and identifiers. **Every change is validated on the server.**
- **Interior compatibility**: listens for the `qb-weathersync`, `vSync` and `cd_easytime` pause events, so housing and apartments keep working

### ⚡ Performance
- **0.00ms when idle.** Only two background checks run, every 5s and every 15s.
- Density natives must run every frame by GTA's design. They only run while a slider is set away from 100% (about 0.01ms). The optional `'zero'` mode avoids per-frame natives completely.

---

## 📁 File Structure

```
nayzeee-worldcontrol/
├── client/
│   ├── main.lua        # Sync, panel, commands, exports
│   ├── world.lua       # Weather, time, atmosphere, restart warning, pause compat
│   └── traffic.lua     # Density, services, purge
├── server/
│   ├── main.lua        # State, persistence, permissions, sync, log
│   ├── weather.lua     # Dynamic cycle, forecast, real weather
│   ├── time.lua        # Server clock
│   └── actions.lua     # Panel actions, scenes, restart warning, commands, exports
├── shared/
│   ├── config.lua      # Configuration
│   └── utils.lua
├── html/
│   ├── index.html
│   ├── css/style.css
│   └── js/app.js
└── docs/
```

---

## 🎮 Commands

| Command | Description |
|---------|-------------|
| `/worldcontrol` | Open the panel. `/traffic`, `/easytime` and `/weathermenu` also work. |
| `/weather [type] [instant]` | Set the weather, e.g. `/weather thunder` |
| `/time [hour] [minute]` | Set the time, e.g. `/time 22 30` |
| `/freezetime` | Freeze or unfreeze time |
| `/blackout` | Toggle the city blackout |
| `/restartwarning [minutes]` | Start the restart warning. Use `/restartwarning cancel` to stop it. |

All commands also work from the server console.

---

## 📞 Exports

### Server

```lua
local wc = exports['nayzeee-worldcontrol']

wc:SetWeather('RAIN', false)          -- weather, instant?
wc:GetWeather()                       -- 'RAIN'
wc:SetTime(22, 30, false)             -- hour, minute, instant?
local h, m, s = wc:GetTime()
wc:FreezeTime(true)
wc:SetTimeSpeed(4000)                 -- ms per game minute (2000 = GTA default)
wc:SetBlackout(true)
wc:SetWorld({ wind = 8.0, rain = 0.5, snowOnGround = true })
wc:SetDensity({ pedestrians = 0.5, vehicles = 0.5 })
wc:GetDensity()
wc:ApplyTrafficPreset('empty')
wc:SetService('dispatch', false)
wc:ApplyScene('christmas')
wc:StartRestartWarning(5)             -- minutes
wc:CancelRestartWarning()
wc:GetState()                         -- everything

-- Legacy nayzeee-traffic exports still work
wc:GetServerSettings()
wc:SetServerSettings({ pedestrians = 0.5, ... })
```

### Client

```lua
local wc = exports['nayzeee-worldcontrol']

wc:OpenMenu()
wc:CloseMenu()
wc:GetWeather()
wc:GetTime()
wc:GetDensity()
wc:GetState()
wc:PauseSync(true, 12)    -- freeze weather/time locally (e.g. inside an interior), optional hour
wc:PauseSync(false)       -- resume the live world
wc:IsSyncPaused()
```

### Pause events (for housing/interior scripts)

```lua
TriggerEvent('qb-weathersync:client:DisableSync')  -- pause
TriggerEvent('qb-weathersync:client:EnableSync')   -- resume
TriggerEvent('vSync:toggle', true / false)
TriggerEvent('cd_easytime:PauseSync', true / false, hour)
TriggerEvent('nayzeee-worldcontrol:PauseSync', true / false, hour)
```

---

## 🔗 Support

- Discord: [discord.gg/nayzeeedev](https://discord.gg/nayzeeedev)
