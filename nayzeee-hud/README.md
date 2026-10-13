# nayzeee-hud

A fully customizable FiveM HUD built for performance: 16 player status styles, 13 speedometers plus two bicycle watches, aircraft and boat displays, a vehicle control panel, 11 seasonal themes and the full **squads** system built in. Every player can change it in game, and their choices are saved on their own PC.

It replaces **qb-hud**, **esx_hud** and **nayzeee-squads**. Remove those from `server.cfg` when you add it.

## Features

- **Player status (17 styles):** Ring, Ring + Value, Segmented, Squircle, Hexagon, Diamond, Arc Gauge, Liquid Fill, Hex Fill, Circle Fill, Square Fill, Icon + Bar, Pill, Vertical, Minimal, Dots and Tile. Colours: Vibrant, Accent, Mono or **Custom** (players pick their own colour for every stat). Every colour setting (accent, stats, crosshair, team HUD bars) has a colour picker: a colour square, hue slider, hex box, recent colours and a reset to default, with a live preview while you drag.
  - Stats: health, armor, hunger, thirst, stamina, stress, oxygen (underwater) and voice (pma-voice range, talking glow and radio dot).
  - Vibrant, accent or mono colours, row or column layout, smart hide, and a low-value pulse.
- **Speedometers (13 + 2 bicycle):** Modern Pro, Radial, Arc Digital, Tach Ladder, Cluster Bar, Pod Cluster, Classic Dual, Digital Linear, Sport Arc, Tesla Style, Minimal, Retro LCD and Twin Bars. Bicycles get a Smart Watch (speed, heart, cadence) or a Fitness Watch.
- **Aircraft:** Flight PFD (attitude, speed and altitude tapes, vertical speed, heading, gear), Info Cards, or Modern (pitch, altitude, heading and airspeed cards with a fuel and systems strip, in place of the speedometer).
- **Boats:** Heading & trim cards (BOW UP / LEVEL / BOW DOWN with degrees) above the speedometer, or Modern (speed and heading cards with a fuel and systems strip, in place of the speedometer). Knots or the same units as cars.
- **Squads** (`/squads`): the whole nayzeee-squads system: temporary and permanent squads, ranks, ELO and K/D/A, alliances, leaderboards, team HUD, nametags, blips, pings, rally points, ready checks and revives. See [`squads/README.md`](squads/README.md). Its compass is dropped in favour of the HUD compass. The squads menu is for browsing, creating and running your squad (squad, chat, allies, stats, ranks); each player's squad settings live in `/hud` → **Squads**: 10 team HUD styles (Classic, Slim, Frost, Loadout, Tactical, Arena, Rings, Heads, Tiles, Minimal) with live previews, plus nametags, map blips, alerts and squad radio. The team HUD moves and resizes in `/hud` → **Edit layout** together with the rest of the HUD.
  - **Weapon in hand**: while a squadmate has a weapon out, their card shows it (nothing at all when unarmed) (picture from `Config.WeaponImages`, turned into a white silhouette; a built-in silhouette per weapon class is used when no picture loads). The weapon comes from the server's view of the ped, in the existing vitals sync.
  - **Shot flashes**: every shot a squadmate fires flashes their card, in the same rhythm as the gunfire. The shooter's client times each shot and sends small batches (`SquadsConfig.TeamHudShots`); the HUD keeps a matching 120 ms buffer so bursts play back evenly. Flash size and length follow the weapon class (a sniper crack is bigger than an SMG rattle). Idle cost is one native every 250 ms; per-frame checks only run while you aim or fire.
  - **Talking**: bouncing voice bars on whoever is talking, in yellow with a radio icon when it's over pma-voice radio (radio works at any distance; proximity talk needs the player in range).
  - **Ammo**: clip / reserve under the gun, amber when the clip is low, `RELOAD` or `EMPTY` in red. Each player's client sends it only when it changes (at most every 600 ms) and it rides the vitals sync.
  - **Damage flashes**: a card jolts and flashes red the moment that squadmate gets hurt (bigger hits shake harder).
  - **Vehicle**: what they're in, with a car, truck, bike, bicycle, boat, plane, helicopter or train icon, the vehicle's name and Driver / Passenger. Picture styles (Heads, Tiles, Rings, Arena, Slim) show the icon as a badge on the picture.
  - **Downed**: a bleed-out countdown on the card (`SquadsConfig.Revive.BleedOut`, 0 counts up instead), red for the last 30 s. When someone starts reviving, the picture gets a ring that fills as the revive progresses and the tag reads `REVIVING · name`.
  - **Revives** use the HUD's progress bar. With `SquadsConfig.Revive.Hold = true` you hold `G`; letting go stops the revive.
- **Stress** (qb-hud compatible): gains from shooting and speeding, screen blur and, at 100, a stumble. Other scripts keep using `hud:server:GainStress` / `hud:server:RelieveStress`.
- **Money:** `+$` / `-$` popups when cash or bank changes, `/cash` and `/bank`, and ESX dirty money.
- **Dashboard lights:** seatbelt, headlights (low and high), cruise, lock, engine warning and indicators.
- **Vehicle control panel** (`F7`): engine, lock, hood, trunk, indicators, hazards, lights, cruise, neon, each door, each window and seat switching.
- **Built-in seatbelt** (`B`) with windscreen-ejection protection, a buckle sound and a chime when driving unbuckled.
- **Cruise / speed limiter** (`Y`) and **indicators** (`←` / `→`).
- **Minimap:** player status sits **under** the minimap (the radar is lifted to make room) or beside it. Seven frame styles: Glass, Inset, Accent, Panel, Corners, Shadow and None, each with a bezel that covers the radar's square corners. If the frame doesn't sit exactly on the radar on your screen, nudge it in `/hud` → Map & Compass → **Frame fit** (or for everyone with `Config.Minimap.frameFit`); the street bar and speed sign move with it. Default, Square, Rounded and Circle shapes; the frame follows the shape. The square and circle masks (`stream/squaremap.ytd`, `stream/circlemap.ytd`) and `stream/minimap.gfx` (removes GTA's health / armour bars under the radar) come from qb-hud (GPL-3.0, credit to its authors). `stream/roundedmap.ytd` is that square mask with rounded corners. Without the masks the shapes still work with GTA's own mask; delete `minimap.gfx` if you want GTA's bars back. Want a custom dark / teal map like the big servers? `tools/minimap-recolor/` recolours GTA's radar tiles: see its README.
- **Map and location:** minimap frame, street bar (direction, street, zone, postal; above the map or as a small label inside it), live speed-limit sign (US or EU) that blinks when speeding, and a compass (tape or ribbon).
- **Player info (9 styles):** Chips, Pills, Stacked, Compact, List, Sections, Grid, Tiles and Profile Card. Shows job, gang, character name, cash, dirty money, bank, server ID, players online, date and time, and a profile picture with a talking ring. Every element can be switched off.
- **Discord profile pictures:** the player's Discord avatar (server avatar first), animated GIFs included, falling back to the character headshot. Needs `set nhud_discord_token "..."` in `server.cfg` (or the squads `nz_squads_bot_token`) and `Config.Discord.guildId`.
- **NayZeee teal (`#08afa2`)** is the accent across the HUD, settings and squads. Seasons keep their particles and decorations without changing it, unless a player turns on "Use season colours".
- **Weapon display:** image, name and clip/reserve ammo. Card, Minimal or Pill styles. Pictures come from ox_inventory automatically (`nui://ox_inventory/web/images`), then qb / ps / lj inventory, otherwise the FiveM docs; `Config.WeaponImages` takes your own template (`%s` = WEAPON_PISTOL, `%l` = weapon_pistol). The squads team HUD uses the same pictures, all drawn at the same size.
- **Crosshair (8 styles):** Dot, Cross, Cross + Dot, T, Plus, Circle, Circle + Dot and Chevron, with colour, length, thickness, gap, opacity and an outline. It replaces GTA's aim dot only while you aim a gun (sniper scopes keep their own), or whenever you hold one. `Config.Crosshair.enabled = false` leaves GTA's reticle alone.
- **Voice & radio (4 styles):** Pill, Bars, Card and Minimal. Shows your voice range (pma-voice's own names such as Whisper / Normal / Shouting and the distance, or SaltyChat's range), a bouncing mic while you talk, your radio channel and a yellow glow while you transmit. Show it always, only while talking, or only when you're on a radio. It sits next to the player status by default.
- **Notifications, progress bars and prompts** in the HUD's style, each with a player-picked style: notifications (Card, Glass, Pill, Stripe, Minimal; right, left, top or bottom; repeated messages stack as ×2, ×3), progress bars (Bar, Clean, Percent, Ring card, Ring, Line, Pill) and interaction prompts (Key, Card, Minimal). See **Notifications** below.
- **Weather and time (6 styles):** Pill, Text and icon, Weather Card, Line, Big Clock and Split Pills. Game or real time, 12h or 24h, day and date, a weather icon that changes for night, and the weather name.
- **Server watermark:** Stack, Badge or Minimal styles, with None, Pulse, Gloss or Float effects. For the logo, drop `logo.png` (or `.webp`, `.gif`, `.svg`) into `nayzeee-hud/html/logo/` and restart; no link needed. `Config.Watermark.logo` can also name another file in that folder or still be a link, and `showText = false` shows the logo on its own.
- **Seasonal styles:** Auto by date, Winter, Christmas, New Year, Valentine, St. Patrick's, Spring, Summer, Independence, Autumn and Halloween. Each season sets theme colours, CSS-only particles (snow, leaves, hearts, confetti, bats and more) and little decorations on HUD elements.
- **Edit layout:** drag any element, scroll to resize, right-click to reset it.
- **Import / Export:** share a whole HUD setup as a code. The tab shows what a code contains (styles, season, accent, layout) and checks a pasted code before you load it.

## Install

1. Drop `nayzeee-hud` in your resources folder and remove `qb-hud`, `esx_hud` and `nayzeee-squads` if you had them (squads are built in now; if the old `nayzeee-squads` is still started, the built-in squads switch off and the console tells you).
2. In `server.cfg`, start it after `ox_lib`, `oxmysql` and your framework:

   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core        # or qb-core / es_extended
   ensure nayzeee-hud
   set nhud_discord_token "YOUR_BOT_TOKEN"      # optional, Discord pictures (HUD + squads can share one bot)
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
| Revive squadmate | hold `G` |
| Show balance | `/cash`, `/bank` |
| Test notifications / progress / prompt | `/hudtest notify`, `/hudtest progress`, `/hudtest text` |

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

Server: `exports['nayzeee-hud']:GainStress(src, 5)` / `RelieveStress(src, 5)` / `Notify(src, { ... })`.

## Notifications

```lua
-- client
exports['nayzeee-hud']:Notify({ title = 'Garage', message = 'Your car is ready', type = 'success', duration = 5000 })
exports['nayzeee-hud']:Notify('Not enough cash', 'error')                -- text, type, duration, title
local done = exports['nayzeee-hud']:Progress({                          -- blocks; true when finished, false when cancelled
    label = 'Picking the lock', duration = 5000, canCancel = true,
    disable = { move = true, car = true, combat = true },
    anim = { dict = 'mp_arresting', clip = 'a_uncuff' },               -- or { scenario = 'PROP_HUMAN_BUM_BIN' }
    prop = { model = 'prop_tool_screwdriver', bone = 60309, pos = vec3(0, 0, 0), rot = vec3(0, 0, 0) },
})
exports['nayzeee-hud']:ShowTextUI('Open the stash', { key = 'E' })      -- '[E] Open the stash' works too
exports['nayzeee-hud']:HideTextUI()

-- server
exports['nayzeee-hud']:Notify(source, { message = 'Paid $500', type = 'success' })
TriggerClientEvent('nhud:notify', source, 'Paid $500', 'success')
```

Types: `success`, `error`, `warning`, `info` (also `inform`, `primary`). GTA colour codes like `~r~` are stripped. `Progress` also accepts qb-core progressbar tables with a callback: `exports['nayzeee-hud']:Progress(data, function(cancelled) end)`. qb-core's `qb-core:client:DrawText` / `HideText` / `ChangeText` / `KeyPressed` events show the prompt automatically (`Config.UI.TextUI.QBEvents`); qb-core still draws its own prompt too, so either point `exports['qb-core']:DrawText` at `ShowTextUI` or turn `QBEvents` off. Try it with `/hudtest notify`, `/hudtest progress` or `/hudtest text`.

To send **every** framework notification through the HUD, point the framework's notify function at it (one line each):

```lua
-- qb-core: client/functions.lua, at the top of QBCore.Functions.Notify
return exports['nayzeee-hud']:Notify({ message = type(text) == 'table' and text.text or text, title = type(text) == 'table' and text.caption or nil, type = texttype, duration = length })

-- es_extended: client/functions.lua, at the top of ESX.ShowNotification
return exports['nayzeee-hud']:Notify({ message = message, type = notifyType, duration = length })

-- ox_lib: in any resource, before it calls lib.notify
lib.notify = function(d) exports['nayzeee-hud']:Notify({ title = d.title, message = d.description, type = d.type, duration = d.duration }) end
```

Squads exports work under both names (`exports['nayzeee-squads']` and `exports['nayzeee-hud']`). See [`squads/README.md`](squads/README.md).

Event fired on belt change: `nayzeee-hud:seatbelt` (bool).

## Performance

The target is **0.00–0.01 ms** in resmon.

- **One loop thread.** It wakes every 250 ms on foot and every 125 ms in a vehicle. Slower data runs on its own timers inside that loop: status every 500 ms, location every 1 s, misc every 2.5 s.
- **No per-frame code at idle.** The only per-frame code runs:
  - for a few seconds when GTA would show its own street or vehicle name (`Config.HideNativeHud = 'smart'`)
  - while the vehicle control panel is open
  - while you aim a gun (the crosshair hides GTA's reticle for those frames)
  - while a progress bar is running (control blocking and cancel key).
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
