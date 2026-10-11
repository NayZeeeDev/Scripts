# 🔧 nayzeee-tuning

Tuning shops, mechanic work orders, stance, ECU maps, nitrous, air ride, part wear, diagnostics, police inspections, a performance lab and full workshop management. ESX Legacy, QBCore and Qbox.

---

## 📦 Dependencies

| Resource | Required | Notes |
|---|---|---|
| `ox_lib` | ✅ | callbacks, points, keybinds, progress, skill checks |
| `oxmysql` | ✅ | tables are created automatically |
| `es_extended` / `qb-core` / `qbx_core` | ✅ | auto-detected (`Config.Framework = 'auto'`) |
| `ox_target` / `qb-target` | optional | boss desk, diagnostics, police and scrapyard targets. Without one, `[E]` prompts are used |
| `ox_inventory` | optional | used for items when running |
| `wasabi_carlock` / `qb-vehiclekeys` / `qbx_vehiclekeys` | optional | keys for new custom plates |

---

## 🚀 Installation

1. Drop `nayzeee-tuning` into your resources folder.
2. Ensure it **after** your framework, `ox_lib`, `oxmysql` and your target / inventory:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure es_extended
   ensure ox_target
   ensure ox_inventory
   ensure nayzeee-tuning
   ```
3. Add the items from `install/ox_inventory_items.lua` (or `install/qb_items.lua`). Every part, kit and the `mechanic_tablet` is in there.
4. Start the server. Tables are created on first boot (`sql/install.sql` if you prefer to run it yourself).
5. Set your shops in `config/config.shops.lua` and prices in `config/config.lua` → `Config.VehiclePrices`.
6. *(optional)* Discord profile pictures on the tablet: create a bot at discord.com/developers, copy its token and add this to `server.cfg` (never into a config file, those are sent to players):
   ```cfg
   set nayzeee_tuning_discord_token "YOUR_BOT_TOKEN"
   ```
   The bot doesn't need to join any server. Animated avatars play as they are. Players without Discord linked get their initials.

> 💡 **Hint:** `Config.Economy.PriceSource = 'both'` reads prices from your ESX `vehicles` table / QB shared vehicles and lets `Config.VehiclePrices` override them.

---

## ⚙️ Config files

| File | What's inside |
|---|---|
| `config/config.lua` | framework, keys, economy, ownership, plates, discount codes, business rules, shop equipment, orders, test drive, builds, webhooks, admin |
| `config/config.shops.lua` | every shop: mode, job, grades, bays, boss desk, paint booths, parts racks; install animations |
| `config/config.parts.lua` | every purchasable item, price multipliers, camera, install spot; menu categories |
| `config/config.colors.lua` | paints, chameleon, finishes, xenon, tints, plates, wheel types, underglow modes |
| `config/config.performance.lua` | stance, wheel size, ride height, air ride, nitrous, ECU, anti-lag, launch control, engine swaps, wear, perf lab |
| `config/config.jobs.lua` | police inspections, diagnostics, GPS tracker, roadside callouts, tow jobs, supply runs, scrapyard |
| `config/config.install.lua` | how each part is fitted: props, hand placement, animations, jacks, engine hoist, install sounds |
| `config/config.items.lua` | which inventory item every part uses, the parts supplier, usable items (tablet, remotes, kits) |

### Shop modes

| Mode | Behaviour |
|---|---|
| `self` | Classic LS Customs. Pay and the parts go on instantly. |
| `mechanic` | Customer places an order and pays; money is held until a mechanic finishes the job. |
| `hybrid` | `mechanic` while someone is on duty, `self` when nobody is. |

With `Config.Business.CustomerChoosesMode = true`, a staffed shop shows a **Self-Service / Order** toggle at the top of the menu. Self-service while mechanics are on duty costs `SelfServiceSurcharge` % more.

---

## 🛠️ Features

**Tuning menu** · the workshop's name top left, a parts catalog with a category rail (`Q` / `E`) and part list (`↑` / `↓`), an option dock at the bottom with the option name, price, state and a tick strip (`←` / `→` to browse, `Enter` or click to add). Search (`F`) finds parts *and* options. Diamond markers on the car jump to a part, the toolbar has the cart total, bank and vehicle, a Self-Service / Order switch, stock compare (hold `H`), turntable, lights, doors, rev, undo/redo, Max Performance and Surprise Me, discount codes, live power / 0-60 / top speed with deltas.

**Parts** · every GTA mod slot, performance levels with per-model caps, indexed / RGB / chameleon paint with finishes, rims by type, custom / drift / run-flat tyres, rim diameter and tyre width, liveries, extras, tint, horns with preview, xenon + RGB headlights, underglow + modes, custom plates, repair, wash, major service.

**Chassis (new)** · tyre compounds (road, semi slick, slick, all-terrain), drivetrain swaps (AWD / RWD / FWD), ceramic brakes, drift kit, manual H-pattern gearbox (`↑` / `↓`, `K` toggles, money shifts hurt the engine), engine sound packs per car.

**Performance** · stance, ride height, air ride (`PageUp` / `PageDown`), nitrous (hold `Shift`, purge `X`), ECU presets plus a cell-by-cell ignition map in the tablet, engine swaps (I4 → V12 and EV conversions), anti-lag, launch control, TCS / ESC driver assists (`/tcs`, `/esc`).

**Real parts** · every job uses parts (`engine_oil`, `turbocharger`, `v8_engine`, `slick_tyres`, `respray_kit`...). `Config.PartItems.Mode = 'orders'` puts them on work orders, `'all'` makes self-service customers bring them too.

**Supply storage** · every job shop has its own parts stock, filled by deliveries and supply runs. `Config.Storage.PartSource` decides where work-order parts come from (a shop can override it, also from `/mechaniceditor`):
- `'supply'` · mechanics walk to the racks in the shop and the part comes straight out of supply storage. Nothing in their pockets, the storage just has to have it.
- `'inventory'` · mechanics take the parts out of supply storage first (`E` at the storage point, tablet **Supply Storage** app), then fit them from their inventory. The job sets a waypoint to the storage when something is missing.
- `'both'` · pockets first, the rest from storage.

The **Supply Storage** app shows what's on the shelf, what's on the way (with a countdown) and lets you take parts out or put spares back while standing at the storage.

**Mechanic jobs (VMS-style)** · walk around while carrying (heavy parts walk only, light ones like tools, boxes and plates can be run with: `run = true / false` per part), grab the jacks and jack the car up on four stands, push the engine hoist to the bay for engine work, carry each wheel to its corner, take bumpers, spoilers, exhausts, hoods and plates from their own racks with the right prop in the right hand, spray paint in the booth, crawl under the car for brakes and gearbox. Each part has its own prop, animation, timing and sound. The checklist scrolls itself to the next step and explains what to do.

**Install sounds** · jacks, socket and ratchet wrenches, air wrench, engine crane, painting, cleaning and final tighten. Everyone within 22 m hears them, quieter with distance.

**Tuning tablet** (`mechanic_tablet` item or `/tablet`) · every player has their own: accent colour and wallpaper are saved per character. Apps depend on job and rank:
- **Everyone** · My Cars (wear, mods, GPS locate, TCS / ESC), My Orders, Messages, Settings
- **Mechanics** · Overview, Job Board (New → Claimed → In the bay → Finished, each job opens a job card with Begin work / Claim / Hand back / Chat / Refund), My Bay, Roadside, Parts Store (paid by the shop), Health Check (OBD scan with a health score), **ECU Studio**, My Work
- **Managers** · Crew, Promo Codes, refunds
- **Owner** · Vault (deposits, withdrawals, margin, commission, **labour rate**), Equipment

The workshop app is called **PITWALL** by default (`Config.Tablet.Brand`).

**ECU Studio (tablet only)** · the tuning menu only sells the programmable ECU (hardware). All calibration happens on the tablet, by an employee standing at the car: ignition timing per rev band (drag the columns, the red line is the knock limit), mixture richness, the calibration sliders and presets (power, final drive, brakes, bias, grip, anti-roll, springs, damping, steering), a live dyno curve against factory and a predicted power gauge. *Write to ECU* saves it to the car, *Factory reset* wipes it.

**Discord avatars** · players' Discord pictures (animated ones too) show on the tablet home screen and sidebar, in message threads and chat bubbles, on job cards, the crew list and the leaderboard.

Order messages are a real chat between the customer and the workshop, with notifications when the tablet is closed.

**Usable items** · lighting controller (underglow colour, sides and modes from the driver seat), stancer kit (camber, track and height on the fly once Fitment is fitted), repair kit, duct tape (limps a dead engine home, twice), cleaning kit.

**Workshop office** · lives in the tablet now: KPIs, revenue chart, announcements, leaderboard, hiring, grades, bonuses, codes, account, rates, transactions, equipment.

**Tow jobs** · some roadside callouts are wrecks. Take a flatbed (handed to you at the shop's truck spawn) or a tow truck, back up to the wreck, winch or hook it, drive it to the shop's drop point and unload it. Everyone sees the wreck on your truck. They show up in the tablet's Roadside app as *Tow · flatbed*.

**Deliveries** · *Deliver* in the Parts Store pays from the shop account and the parts land in supply storage after `Config.Supplier.DeliveryMinutes` (6 by default). The order shows under *On the way* with a countdown in the Parts Store and Supply Storage apps, and everyone at the shop is told when it arrives.

**Supply runs** · *Fetch it yourself* buys the same parts **35 % cheaper**, with an objective tracker on screen and a timer: get in the work van → drive to the warehouse → carry the packages into the van → drive back to the shop → carry every package into supply storage. Run out of time or `/cancelsupply` and the supplier keeps 15 %. Tow jobs use the same tracker.

**Bay claiming** · mechanics claim a bay as their own from the tablet's **My Bay** app or with `G` at a free bay. On by default for `mechanic` and `hybrid` shops with 2+ bays (`Config.Bays`, or `claimBays` per shop). A claimed bay shows the owner's name, only opens for them (managers can use and free any bay), and is freed when they leave or lose the job.

**Shop editor** (`/mechaniceditor`, admins) · pick a shop or make a new one. Press `F2` (or *Walk*) to blur the editor and walk around, stand where a point should go facing the right way, press `F2` again and hit the target button to set it there (bays and the work truck use your car if you sit in one). Set the centre / blip, bays, boss desk, supply storage, paint booths, every part rack, the drop point and the work-truck spawn; ✕ removes a point. Bay claiming and where work-order parts come from can be set per shop. Everything you placed is drawn in the world while the editor is open. Save and it's live for everyone, no restart. *Back to config* undoes your edits, editor-made shops can be deleted and config shops hidden.

**Extras** · saved builds with share codes, test drive, service history, performance lab with leaderboards, OBD scanner, police inspection with part removal, GPS tracker (`/findcar`), scrapyard dismantling.

---

## ⌨️ Commands & keys

| Command / key | Who | Does |
|---|---|---|
| `[E]` in a bay | everyone | open the tuning menu (driver) / work on the car (mechanic on foot) |
| `/tablet` | item holders | open your tablet (needs the `mechanic_tablet` item unless `CommandNeedsItem = false`) |
| `/workorders` | employees | open the tablet on the job board |
| `/cancelsupply` | employees | cancel your supply run |
| `/mechaniceditor` | admin ace | place and edit tuning shops in game |
| `/testsound [audio]` | admin ace | hear an engine sound on your car before adding it |
| `/carryadjust [part]` | admin ace | line up a carried prop: arrows / PgUp / PgDn move, hold `Shift` to rotate, `G` next object, `Enter` copies the `attach` line (`hoist` and `jacks` work too) |
| `F2` | editor | hide the shop editor to walk around / bring it back |
| `G` at a bay | employees | claim / release the bay |
| `/tcs` / `/esc` | drivers | traction / stability control on or off |
| `↑` / `↓`, `K` | manual gearbox | shift up / down, switch manual / auto |
| `Q` / `E`, `↑` / `↓`, `←` / `→`, `Enter`, `F`, `C` | tuning menu | category, part, option, add to cart, search, cart |
| `/myorders` | everyone | see / cancel your open orders |
| `/perftest [test]` | everyone | start a timed run |
| `/findcar` | owners | ping a car with a GPS tracker |
| `/cancelcallout` | mechanics | abandon a roadside callout |
| `/admintune` | admin ace | free menu on the car you're in |
| `/tunecode [code|0] [shop|all] [%] [uses]` | admin ace | create a discount code |
| `/deltunecode [code]` | admin ace | delete a code |
| `/resettune` | admin ace | clear custom tuning data on your car |
| `Shift` / `X` | drivers | nitrous boost / purge |
| `PageUp` / `PageDown` | drivers | air ride up / down |
| `Backspace` | mechanics | pause the current install |

All keys are ox_lib keybinds and can be rebound in the FiveM settings.

---

## 🅿️ Garages

Tuning (engine sound, nitrous, stance, ECU...) is stored per plate and lands on the car the moment a garage hands it over. Garages set the plate on the client first and the server sees it a sync later; the script follows the car until both agree, so it works with any garage (ESX, QBCore, Qbox, JG, cd, okok...) out of the box.

For an instant hand-over:
- **JG Advanced Garages** is hooked automatically (`jg-advancedgarages:client:TakeOutVehicle:config`).
- **Any garage with a "vehicle taken out" client event**: add its name to `Config.Garages.Events` in `config/config.lua` (the event's first argument must be the vehicle).
- **Any other garage**: one line in its client code, right after it sets the vehicle properties / plate:
  ```lua
  exports['nayzeee-tuning']:VehicleSpawned(vehicle)
  ```
  (server side: `exports['nayzeee-tuning']:RefreshVehicle(vehicle)`)

---

## 🔌 Exports

```lua
-- server
exports['nayzeee-tuning']:GetVehicleData(plate)            -- custom data table
exports['nayzeee-tuning']:SetVehicleData(plate, data)
exports['nayzeee-tuning']:RefreshVehicle(vehicle)          -- re-attach data after a garage spawn

-- client
exports['nayzeee-tuning']:VehicleSpawned(vehicle)          -- a garage just handed this car over
exports['nayzeee-tuning']:GetIllegalParts(plate, props)
exports['nayzeee-tuning']:GetWear(plate)  /  SetWear(plate, wear)
exports['nayzeee-tuning']:GetMileage(plate)
exports['nayzeee-tuning']:GetShopBalance(shopId)
exports['nayzeee-tuning']:AddShopMoney(shopId, amount, note)
exports['nayzeee-tuning']:CreateDiscountCode(shopId, percent, uses, code)
exports['nayzeee-tuning']:IsInTestDrive(vehicle)           -- let your garage refuse to store it
```

Custom data rides on the `nzTune` state bag, so any script can read `Entity(vehicle).state.nzTune`.

---

## 🔊 Custom engine sounds (your sound pack)

Every car can have its own sound, even two cars of the same model, and it changes live with no respawn (`ForceUseAudioGameObject` per car, saved on the car, everyone hears the same thing). You don't edit any `vehicles.meta`.

### Ship them inside nayzeee-tuning (no extra download for server owners)

85 packs are already listed in `ENGINE_SOUNDS` (bottom of `fxmanifest.lua`). Copy your `audioconfig` and `sfx` folders into `nayzeee-tuning/audio/` **before** starting the server, then restart the server. Together they're about 340 MB, which every player downloads once on first join (FiveM caches it).

**1. Copy the pack's files into the script.** A pack is made of `.rel` files and an `sfx` folder of `.awc` files:
```
nayzeee-tuning/audio/audioconfig/lambov10_game.dat151.rel
nayzeee-tuning/audio/audioconfig/lambov10_sounds.dat54.rel
nayzeee-tuning/audio/audioconfig/lambov10_amp.dat10.rel     (only some packs have this)
nayzeee-tuning/audio/sfx/dlc_lambov10/lambov10.awc
nayzeee-tuning/audio/sfx/dlc_lambov10/lambov10_npc.awc      (only some packs have this)
```

**2. Add one line per pack** to `ENGINE_SOUNDS` at the bottom of `fxmanifest.lua`:
```lua
local ENGINE_SOUNDS = {
    { name = 'lambov10', label = 'Lambo V10', synth = true },   -- synth = true only if there's an _amp.dat10.rel
    { name = 's55b30',   label = 'Ubermacht S55' },
}
```
That's all. The manifest writes the `data_file` lines for you and the sound shows up under **Performance › Engine Note** on its own (no `Config.SoundPacks.List` edit). If a pack names its files differently, point at them: `files = { game = 'x_game', sounds = 'x_sounds', synth = 'x_amp', wavepack = 'dlc_x' }`.

**3. Restart the whole server** (not `restart nayzeee-tuning`) the first time and whenever you add sounds. Audio is loaded when a player joins, so restarting a resource with audio in it while people are online can break sounds or crash them. Check it with `/testsound lambov10` in any car.

Players download the sound files once with the script and FiveM caches them.

### Or keep a pack in its own resource
Copy `install/soundpack_template`, drop the files in, `ensure` it before nayzeee-tuning and add `{ audio = 'lambov10', label = 'Lambo V10' }` to `Config.SoundPacks.List` in `config/config.performance.lua`.

---

## ⚡ Performance

Idle cost is one 1-second vehicle scan on the client. Stance is only applied per frame while a stanced car is on screen within 45 m, underglow modes tick at 10 Hz only when one is visible, and every driver feature starts when you take the wheel and stops when you leave it. Shops, bays and desks are ox_lib points.

---

## 🧯 Troubleshooting

| Issue | Solution |
|---|---|
| A carried part sits wrong in the hands | `/carryadjust <part id>` (e.g. `mod_1`, `wheels`, `hoist`), line it up, `Enter`, paste the line into `config/config.install.lua` |
| Job says *Out of stock* | The shop's supply storage is missing that part: order it in the Parts Store or do a supply run (`PartSource = 'supply'`) |
| Job says *Take from supply storage* | `PartSource = 'inventory'`: go to the storage point (waypoint set), `E`, take the parts |
| No supply storage point | Set one with `/mechaniceditor` (Workshop › Supply storage) or `storage = vec3(...)` in `config.shops.lua` |
| Menu says you don't own the car | `Config.Ownership.OnlyOwnerCanTune = true` checks `owned_vehicles` / `player_vehicles`. Buy a car properly or turn it off. |
| Stance / sound / nitrous late after garage | See **🅿️ Garages** above: add your garage's take-out event to `Config.Garages.Events`, or call `exports['nayzeee-tuning']:VehicleSpawned(vehicle)` after it sets the plate. |
| Rim diameter does nothing | GTA only resizes custom rims. Fit any non-stock rim first. |
| Chameleon paints show as black | Your server doesn't stream the gen9 paint ramps. Keep `Config.ChameleonPaints.Enabled = false`. |
| No prices on vehicles | Add the model to `Config.VehiclePrices` or set `PriceSource = 'both'`. |
| Keys not given on plate change | Edit `Bridge.GiveKeys` in `bridge/server.lua` for your key script. |
| Mechanic stuck on "Missing parts" | They need the inventory items listed in the checklist. Buy them in the tablet (Stock) or set `Config.PartItems.Mode = 'off'`. |
| No Discord pictures | Set `nayzeee_tuning_discord_token` in `server.cfg` (server console warns when it's missing) and make sure players have Discord linked to FiveM. |
| ECU option in the menu has no sliders | By design: buy the programmable ECU in the menu, then a mechanic calibrates it in the tablet's ECU Studio. |
| Tablet won't open with `/tablet` | The command needs the `mechanic_tablet` item. Set `Config.Tablet.CommandNeedsItem = false` to allow it without. |
| Tow job says "no drop point" | Set the shop's drop point with `/mechaniceditor` (or `drop = vec3(...)` in config.shops.lua). |
| `/testsound` is silent | The pack isn't streamed or isn't started before nayzeee-tuning, or the audio name is wrong. |
| Install sounds silent | Keep the `.ogg` files in `web/sounds/` and the `web/sounds/*.ogg` line in `fxmanifest.lua`. |
