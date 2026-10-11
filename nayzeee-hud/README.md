# nayzeee-hud

A fully customizable FiveM HUD built for performance: 16 player status styles, 13 speedometers plus two bicycle watches, aircraft and boat displays, a vehicle control panel, 11 seasonal themes and the full **squads** system built in. Every player can change it in game, and their choices are saved on their own PC.

It replaces **qb-hud**, **esx_hud** and **nayzeee-squads**. Remove those from `server.cfg` when you add it.

## Features

- **Player status (16 styles):** Ring, Ring + Value, Segmented, Squircle, Hexagon, Diamond, Arc Gauge, Liquid Fill, Hex Fill, Circle Fill, Square Fill, Icon + Bar, Pill, Vertical, Minimal and Dots.
  - Stats: health, armor, hunger, thirst, stamina, stress, oxygen (underwater) and voice (pma-voice range, talking glow and radio dot).
  - Vibrant, accent or mono colours, row or column layout, smart hide, and a low-value pulse.
- **Speedometers (13 + 2 bicycle):** Modern Pro, Radial, Arc Digital, Tach Ladder, Cluster Bar, Pod Cluster, Classic Dual, Digital Linear, Sport Arc, Tesla Style, Minimal, Retro LCD and Twin Bars. Bicycles get a Smart Watch (speed, heart, cadence) or a Fitness Watch.
- **Aircraft:** Flight PFD (attitude, speed and altitude tapes, vertical speed, heading, gear) or Info Cards.
- **Boats:** heading card and a trim card (BOW UP / LEVEL / BOW DOWN with degrees), knots or the same units as cars.
- **Squads** (`/squads`): the whole nayzeee-squads system: temporary and permanent squads, ranks, ELO and K/D/A, alliances, leaderboards, team HUD, nametags, blips, pings, rally points, ready checks and revives. See [`squads/README.md`](squads/README.md). Its compass is dropped in favour of the HUD compass.
- **Stress** (qb-hud compatible): gains from shooting and speeding, screen blur and, at 100, a stumble. Other scripts keep using `hud:server:GainStress` / `hud:server:RelieveStress`.
- **Money:** `+$` / `-$` popups when cash or bank changes, `/cash` and `/bank`, and ESX dirty money.
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

1. Drop `nayzeee-hud` in your resources folder and remove `qb-hud`, `esx_hud` and `nayzeee-squads` if you had them.
2. In `server.cfg`, start it after `ox_lib`, `oxmysql` and your framework:

   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core        # or qb-core / es_extended
   ensure nayzeee-hud
   set nz_squads_bot_token "YOUR_BOT_TOKEN"     # optional, Discord avatars for squads
   add_ace group.admin nz_squads.admin allow    # squads admin menu
   ```
3. Edit `config.lua` (HUD) and `squads/config.lua` (squads) if you need to. Set `SquadsConfig.Enabled = false` to run the HUD without squads.

**Requirements:** `ox_lib` (squads keybinds and callbacks) and `oxmysql` (permanent squads). Squad tables are created automatically.

Framework is auto-detected: **qbx_core**, **qb-core**, **es_extended** or standalone.

| Data | Source |
|---|---|
| Hunger / thirst / stress | QB `hud:client:UpdateNeeds` / `hud:client:UpdateStress`, qbx state bags, `esx_status:onTick` |
| Money / job | QB `QBCore:Player:SetPlayerData`, ESX `esx:setAccountMoney` / `esx:setJob` |
| Voice | pma-voice `proximity` / `radioChannel` state bags, talking and radio talking; SaltyChat range, radio and channel events |
| Login | HUD hides on character select / logout (`QBCore:Client:OnPlayerUnload`, `esx:onPlayerLogout`) and returns on load |
| Seatbelt | built-in, or qb-smallresources through `seatbelt:client:ToggleSeatbelt` (auto-detected) |
| Extras | `hud:client:UpdateHarness`, `hud:client:UpdateNitrous`, `hud:client:ShowAccounts`, `seatbelt:client:ToggleCruise`, `esx_hud:HudToggle` |
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
| Squads menu | `/squads` |
| Ping / ping wheel (squads) | middle mouse tap / hold |
| Revive squadmate | `G` |
| Show balance | `/cash`, `/bank` |

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
exports['nayzeee-hud']:SetNitrous(80, true)    -- level 0-100, active
exports['nayzeee-hud']:HudToggle(false)        -- esx_hud name
```

Server: `exports['nayzeee-hud']:GainStress(src, 5)` / `RelieveStress(src, 5)`.

Squads exports work under both names (`exports['nayzeee-squads']` and `exports['nayzeee-hud']`). See [`squads/README.md`](squads/README.md).

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

Stress adds no per-frame loop: shots are counted from the ammo the main loop already reads, and speeding is checked every 10 s. Squads costs nothing while you're not in a squad (see its README).

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
index.html?veh=boat                    boat display
index.html?squads                      squads menu preview
```

## Notes

- Settings buttons use the NayZeee UI palette: teal **Save changes**, red **Close** pill, line and red buttons.
- The squads menu runs in its own frame inside the HUD page and wears the HUD settings look in the NayZeee teal (`html/squads/hud-skin.css` on top of its original `style.css`). Its NUI callbacks are prefixed `sq_` internally.

- Speed limits are a built-in table of major LS roads plus street-suffix rules (`shared/data.lua`). Edit or extend it freely. Values are in MPH and converted for km/h players.
- Postal codes: `Config.GetPostal` calls `nearest-postal` if it's running. Point it at your postal resource.
- Lock button: replace `Config.ToggleLock` with your keys script's export or event.
- The HUD uses Google Fonts (Inter, Unbounded, Share Tech Mono) and falls back to Segoe UI if they can't load.
