# nayzeee-heistpack

Heist pack for FiveM: 21 heists, crews, levels and perks, a black market with drone delivery, a fence, a recon drone, 8 minigames and a transparent task HUD. ESX, QBCore and QBox are all supported.

## Highlights

- **21 heists** (15 classics plus 6 new ones), all defined as data in `config/heists/*.lua`.
- **Server-authoritative engine.** Clients never decide a payout. Every interaction is *claimed* (crew membership, stage, distance, items and busy state are checked) and then *finished* (same player, minimum time, distance again). Only after that are doors opened, flags set or loot rolled. Instant finishes and out-of-range calls are logged or kicked.
- **0.00ms idle.** The resource runs no `while true` loops at idle. Interaction points are ox_lib points, so props and targets exist only within about 35m. Special loops (drone, carry, intimidation, noise, gas, lift) start only when needed and exit on their own. The server watcher thread only lives while a heist is running.
- **Transparent task HUD.** There's no panel behind it, just readable text with shadows. It shows objectives with counters, a timer, escape distance, hostiles left, a GPS tracker warning, the noise meter and the crew. Press `B` to expand or collapse. Set `Config.UI.hud.background` to `'glass'` or `'solid'` if you want a panel.
- **Crews.** Invite by server ID with a popup (Y/N), ready check, kick, promote and leave. Running heists survive disconnects: members are restored when they reconnect within `reconnectWindow`.
- **Progression.** XP, 12 levels, level perks (loot bonus and faster actions), stats, history, a leaderboard, nicknames and 12 avatars.
- **Daily featured heist** with an XP and cash bonus.
- **Market** with server-validated prices and level locks. Orders are delivered by drone and kept if you disconnect.
- **Fence.** Sell loot at employers, with prices that vary daily.
- **Underground chat** between tablet users. It is rate-limited and only sent to players who have the tablet open.
- **8 NUI minigames:** keypad, circuit, typing, safecrack, lockpick, memory (thermite), drill and data crack.
- **Recon drone item.** Free flight with a camera. It also drops payloads in the heists that need it.
- **Integrations, auto-detected:**
  - Frameworks: qbx / qb / esx
  - Inventories: ox / qb / ps / lj / qs / codem
  - Targets: ox_target, qb-target, or the built-in `[E]` prompts
  - Dispatch: ps / cd / qs / rcore / tk / lb-tablet, or a built-in police blip
  - Vehicle keys: qbx / qb / wasabi / mk / renewed
  - Fuel: ox / Legacy / cdn / ps
- **Staff tools:** `/heistadmin list | stop <uid|all> | cooldowns | xp <id> <n> | setxp <id> <n> | featured <heistId>`
- **Discord logging** (the webhook lives in the server-only `config/server.lua`).

## Heists

| Tier | Heist | Gameplay |
|---|---|---|
| Small | Store Robbery | Pick any of 19 stores, aim at the clerk, smash registers, crack the safe |
| Small | ATM Spree | Rob any 3 ATMs in the city: hack, drill, C4, or rip them out with a tow rope |
| Small | House Burglary | Lockpick, enter a private interior, carry TVs and electronics to your trunk, noise meter |
| Small | **Car Boosting** (new) | Steal a tracked supercar, optionally jam the GPS, deliver it to the chop shop |
| Small | **Phone Network Hack** (new) | Hack 4 public payphones anywhere before the trace completes |
| Medium | Fleeca Bank | All 6 branches: SafePad the vault, hack the gate, trolleys and lockboxes |
| Medium | Armored Truck | Intercept a moving truck, kill the crew, C4 the rear doors, grab the bags |
| Medium | Yacht Raid | Take a boat out, clear security, grab the stash, crack the captain's safe |
| Medium | Vehicle Theft | Car hauler, guarded lot, deliver 3 cars |
| Medium | **Barn Raid** (new) | Lost MC stash at the O'Neil ranch, cut the padlock |
| Medium | Ammu-Nation Shipment | 4 dock yards, only one is real, kill the guards, cut the containers |
| Major | Vangelico | Drone gas drops, C4 the doors, 20 cases, 2 paintings, office safe, gas-mask hazard |
| Major | Blaine County Savings (Paleto) | Power box, thermite doors, security, vault, trolleys |
| Major | Bobcat Security | Thermite in, response team, vault, C4 the cash cage |
| Major | Container Heist | Rig plus flatbed, clear the yard, load the container with the handler, haul it out |
| Major | Freight Train | Kill the guards, thermite 2 cargo containers |
| Major | **Airfield Cargo** (new) | Smugglers at Sandy Shores, carry crates to your trunk, hack the manifest |
| Major | **Military Convoy** (new) | Ambush a moving convoy plus escorts, cut open the cargo truck |
| Major | **Cartel Compound** (new) | Assault the Madrazo ranch, laptop-crack the cartel safe |
| Major | Cargo Ship | Boat, ladder, captain's key, fly 2 containers to shore with the Skylift |
| Major | Pacific Standard | Drone-bomb the substation, thermite, security, stairwell, vault, inner gate, trolleys |

## Install

1. Dependencies: [ox_lib](https://github.com/overextended/ox_lib), [oxmysql](https://github.com/overextended/oxmysql) and OneSync.
2. Drop `nayzeee-heistpack` into `resources` and add `ensure nayzeee-heistpack` **after** your framework, inventory and target.
3. Add the items:
   - ox_inventory: `install/items_ox_inventory.lua`
   - qb-core: `install/items_qb.lua` (skip `lockpick` if you already have it)
   - ESX: `install/items_esx.sql`
   - Item images go in your inventory's image folder, using the item name, e.g. `heist_drill.png`.
4. Database tables are created automatically (`install/nayzeee-heistpack.sql` is included if you want to create them manually).
5. Staff permission: `add_ace group.admin nzh.admin allow`
6. Restart. The console prints the detected framework, inventory and dispatch.

## Configuration

- `config/main.lua`: integrations, tablet access (command / key / item / jobs), employers, police jobs, levels and perks, money type (`cash` / `bank` / `black_money` / `markedbills` / item), crew rules, featured heist, outfit, **UI theme**.
- `config/server.lua`: webhook, admin ACE, exploit action (`log` or `kick`).
- `config/market.lua`, `config/fence.lua`: shop and fence items and prices.
- `config/heists/<id>.lua`: everything about a heist (requirements, rewards, loot tables, locations, stages). Turn a heist off with `enabled = false`, or remove it from `Config.Heists`.

### Theme / UI style

All UI colours come from `Config.UI.theme` (`accent`, `accent2`, `success`, `danger`, `warning`, `font`, `radius`). Change two hex values and the tablet, HUD, minigames, toasts and prompts all follow.

### Writing a new heist

Copy any file in `config/heists/`, add its id to `Config.Heists` and describe `stages`. Each stage has `nodes`. These node types are available, and every one is validated server-side:

`interact` (actions: `hack`, `laptop`, `keypad`, `drill`, `lockpick`, `safecrack`, `cut`, `repair`, `search`, `grab`, `thermite`, `c4`), `trolley`, `smash`, `carry`, `zone`, `portal`, `scan`, `deliver`, `escape`, `eliminate`, `intimidate`, `dronedrop`, `atm`, `objects`, `tracker`, `prop`, `hazard`.

Each node can use `unlocks` (doors), `flag` / `requiresFlag`, `requires`, `reward` (loot table), `item` (`remove`, `removeOnFail`), `minigame`, `alert` (dispatch chance), `attach` (to a spawned vehicle), `ground` (snap to ground) and `keys`. Spawns per stage cover guards, vehicles (drivers, passengers, routes, trailers), peds and objects.

### Locations to check on your map

Most positions are well-established game positions (bank vaults, stores, docks). The Fleeca layout is transformed from one branch onto all six, and that transform was checked against known Legion Square panel and lockbox positions. A few of the **new** heists use rough exterior positions; their props and guards snap to the ground, but you should check their X/Y once in-game:

- `barnraid` (O'Neil ranch)
- `cartel` (Madrazo ranch)
- `airfield` (crate and guard spots)
- `convoy` (start on Route 68)
- `house` (exterior doors, apart from the first three)
- `boosting` (car spots)

Stand where you want something and run **`/nzhcoords`**. It copies a `vec4(...)` to your clipboard.

## Tests

`tests/run.sh` (needs `lua5.4` and `python3`) loads the real server code with stubbed natives and plays **every heist to completion**. It simulates spawns, claims, finishes, guard deaths, deliveries and escapes. It also covers the time limit, leader abort, out-of-range claims, instant-finish detection, outsiders, and disconnect/reconnect.
