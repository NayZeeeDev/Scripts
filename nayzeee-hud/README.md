# nayzeee-hud

A fully customizable FiveM HUD built for performance: 16 player status styles, 13 speedometers plus a bicycle watch, aircraft displays, a vehicle control panel and 11 seasonal themes. Every player can change it in game, and their choices are saved on their own PC.

## Features

- **Player status (16 styles):** Ring, Ring + Value, Segmented, Squircle, Hexagon, Diamond, Arc Gauge, Liquid Fill, Hex Fill, Circle Fill, Square Fill, Icon + Bar, Pill, Vertical, Minimal and Dots.
  - Stats: health, armor, hunger, thirst, stamina, stress, oxygen (underwater) and voice (pma-voice range, talking glow and radio dot).
  - Vibrant, accent or mono colours, row or column layout, smart hide, and a low-value pulse.
- **Speedometers (13 + bicycle):** Modern Pro, Radial, Arc Digital, Tach Ladder, Cluster Bar, Pod Cluster, Classic Dual, Digital Linear, Sport Arc, Tesla Style, Minimal, Retro LCD, Twin Bars, and a Fitness Watch for bicycles.
- **Aircraft:** Flight PFD (attitude, speed and altitude tapes, vertical speed, heading, gear) or Info Cards.
- **Boats:** knots, or the same units as cars.
- **Dashboard lights:** seatbelt, headlights (low and high), cruise, lock, engine warning and indicators.
- **Vehicle control panel** (`F7`): engine, lock, hood, trunk, indicators, hazards, lights, cruise, neon, each door, each window and seat switching.
- **Built-in seatbelt** (`B`) with windscreen-ejection protection, a buckle sound and a chime when driving unbuckled.
- **Cruise / speed limiter** (`Y`) and **indicators** (`←` / `→`).
- **Map and location:** minimap frame, street bar (direction, street, zone, postal), live speed-limit sign (US or EU) that blinks when speeding, and a compass (tape or ribbon).
- **Player info:** job and grade, cash, bank, server ID, ped headshot and a talking indicator. Pills, Stacked or Compact styles.
- **Weapon display:** image, name and clip/reserve ammo. Card, Minimal or Pill styles.
- **Weather and time:** game or real time, 12h or 24h, day, and a weather icon that changes for night.
- **Server watermark:** Stack, Badge or Minimal styles, with None, Pulse, Gloss or Float effects.
- **Seasonal styles:** Auto by date, Winter, Christmas, New Year, Valentine, St. Patrick's, Spring, Summer, Independence, Autumn and Halloween. Each season sets theme colours, CSS-only particles (snow, leaves, hearts, confetti, bats and more) and little decorations on HUD elements.
- **Edit layout:** drag any element, scroll to resize, right-click to reset it.
- **Import / Export:** share a whole HUD setup as a code.

## Install

1. Drop `nayzeee-hud` in your resources folder.
2. Add `ensure nayzeee-hud` to `server.cfg`. Start it after your framework.
3. Edit `config.lua` if you need to (framework, keys, watermark text, fuel script, lock function).

Framework is auto-detected: **qbx_core**, **qb-core**, **es_extended** or standalone.

| Data | Source |
|---|---|
| Hunger / thirst / stress | QB `hud:client:UpdateNeeds` / `hud:client:UpdateStress`, qbx state bags, `esx_status:onTick` |
| Money / job | QB `QBCore:Player:SetPlayerData`, ESX `esx:setAccountMoney` / `esx:setJob` |
| Voice | pma-voice `proximity` / `radioChannel` state bags + talking state |
| Fuel | auto: LegacyFuel, cdn-fuel, ps-fuel, lj-fuel, ox_fuel, lc_fuel, qs-fuelstations, okokGasStation, Renewed-Fuel, else native |

## Commands and keys

| | Default |
|---|---|
| Settings | `/hud` |
| Toggle HUD | `/togglehud` |
| Seatbelt | `B` |
| Cruise / limiter | `Y` |
| Vehicle control panel | `F7` (`/vehmenu`) |
| Indicators | `←` / `→` |
| Hazards | unbound |

Keys are FiveM key mappings, so players can rebind them in **GTA Settings → Key Bindings → FiveM**.

## Exports (client)

```lua
exports['nayzeee-hud']:ToggleHud(state)        -- nil toggles
exports['nayzeee-hud']:IsHudVisible()
exports['nayzeee-hud']:OpenSettings()
exports['nayzeee-hud']:SetSeatbelt(true)       -- for other seatbelt scripts
exports['nayzeee-hud']:IsSeatbeltOn()
exports['nayzeee-hud']:IsCruiseOn()
exports['nayzeee-hud']:SetStatus('hunger', 80) -- standalone: hunger | thirst | stress
exports['nayzeee-hud']:SetMoney('cash', 500)   -- standalone: cash | bank
exports['nayzeee-hud']:SetJob('Mechanic', 'Boss')
```

Event fired on belt change: `nayzeee-hud:seatbelt` (bool).

## Performance

The target is **0.00–0.01 ms** in resmon.

- **One loop thread.** It wakes every 250 ms on foot and every 125 ms in a vehicle. Slower data runs on its own timers inside that loop: status every 500 ms, location every 1 s, misc every 2.5 s.
- **No per-frame code at idle.** The only per-frame code runs:
  - for a few seconds when GTA would show its own street or vehicle name (`Config.HideNativeHud = 'smart'`)
  - while the vehicle control panel is open.
- **Diff-only UI updates.** Values are cached and only *changed* keys are sent to the UI, batched into one message per tick.
- **Event driven.** Framework data, pma-voice and the seatbelt use events and state bags, not polling.
- **Natives are localized.** Street and zone lookups are skipped unless you moved more than 2 m, and speed limits are cached per street.
- **Lightweight UI.** Animations are CSS-only (transforms, masks, registered custom properties), and seasonal particles are at most 14 elements.

If you want even less, raise `Config.Ticks.vehicle` (e.g. 150–200). Always check on your own server with `resmon 1`.

## Preview in a browser

Open `html/index.html` directly. It runs a demo with fake data when it's not inside FiveM. Query params:

```
index.html?veh=car                     car HUD (also moto, air, boat, cycle)
index.html?settings&tab=status         settings menu on a tab
index.html?veh=car&edit                edit layout mode
index.html?veh=car&panel               vehicle control panel
index.html?veh=car&season=halloween    force a season
index.html?veh=car&speedo=lcd&status=liquid&units=kmh
```

## Notes

- Speed limits are a built-in table of major LS roads plus street-suffix rules (`shared/data.lua`). Edit or extend it freely. Values are in MPH and converted for km/h players.
- Postal codes: `Config.GetPostal` calls `nearest-postal` if it's running. Point it at your postal resource.
- Lock button: replace `Config.ToggleLock` with your keys script's export or event.
- The HUD uses Google Fonts (Inter, Unbounded, Share Tech Mono) and falls back to Segoe UI if they can't load.
