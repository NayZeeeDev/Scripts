# 🚗 Vehicle Cargo

Private vehicle warehouses bought from a broker, sourcing contracts with trackers and attack crews, an office laptop to run the business, a design bay in the back that raises rarity, a lower level for illegal cars, and export sales where every hit costs you money.

{% hint style="info" %}
Every warehouse is its own routing bucket. Ten players can own the same building and each one only ever sees their own floor.
{% endhint %}

---

## 📦 Dependencies

| Resource | Required | Notes |
| --- | --- | --- |
| `ox_lib` | Yes | Callbacks, points, skill checks, progress, dialogs |
| `oxmysql` | Yes | Tables and new columns are created automatically |
| `es_extended` / `qb-core` / `qbx_core` | One of them | Detected automatically |
| Target | No | `ox_target`, `qb-target` or `interact`. Falls back to a text UI prompt |
| Notifications | No | `nayzeee-notify`, ox_lib, ESX, QB or okok |
| Phone | No | `lb-phone`, `npwd`, `yseries`, `qs-smartphone`, `gksphone`. Falls back to an on-screen text |
| Key / fuel resource | No | wasabi_carlock, qs-vehiclekeys, MrNewbVehicleKeys, Renewed, qb/qbx keys · ox_fuel, LegacyFuel, cdn-fuel |

---

## 🛠️ Installation

1. Drop `nayzeee-vehiclecargo` into your resources folder.
2. Add `ensure nayzeee-vehiclecargo` **after** your framework, `ox_lib` and `oxmysql`.
3. Give admins access: `add_ace group.admin nayzeee.vehiclecargo.admin allow`
4. Start the server. Tables, four seed warehouses and one broker are created on first start.
5. Run `/cargoadmin` → **Brokers** → **Place broker** and aim where you want people to buy warehouses.
6. `/cargoadmin` → **Interior** → **Open setup copy**. Place the arrival point, exit, laptop, design bay, stairs and car spots, then leave through the exit door.

{% hint style="warning" %}
Seed coordinates, the lower level points and the default parking grid are starting points. Run the Interior setup once on your server so every car sits perfectly on the floor.
{% endhint %}

---

## 🏢 Adding Warehouses

`/cargoadmin` → **Locations** → **Add a warehouse**. Give it a name and price, then place its four points (one at a time, or **Place all in order**). It shows at every broker the moment you save.

| Point | What it is |
| --- | --- |
| Front door | Walk up here to Enter or Knock. Face the door. |
| Garage entrance | Drive a sourced car here to store it. |
| Garage exit | Where you come out with "Leave through the garage" (optional, falls back to the entrance). |
| Sale car spawn | The car you sell waits here. Face the road. |

Positions show x, y, z and heading. Changed `Config.SeedWarehouses` after the first start? Press **Import from config**: same name = updated, new name = added.

---

## 🎯 Placement Tool

Every point and car spot (admin setup, broker, locations, owner layouts, tracker spot) is placed by aiming with your camera.

| What | You see | Controls |
| --- | --- | --- |
| Points | A cylinder on the spot and a line from you to it, with an arrow for the facing | `E` place · `SCROLL` rotate · `SHIFT` + `SCROLL` fine · `BACKSPACE` cancel |
| Laptop / broker | A see-through ghost laptop or broker that follows where you look | `E` place · `SCROLL` rotate · `BACKSPACE` cancel |
| Car spots | A see-through ghost car, plus outlines and numbers for spots already placed | `E` place · `SCROLL` rotate · `Z` undo · `R` clear · `ENTER` save |
| Illegal spots | The 4 spots downstairs, the one being moved is red | `E` move it · `Z` step back · `ENTER` save |

The keys for whatever you are placing show in a small card on the right of the screen.

{% hint style="info" %}
The lower level always has exactly 4 illegal spots. Admins can move them but never remove them, and **Reset** puts the config defaults back.
{% endhint %}

Updating from an older version? Just restart. Missing columns (`floor`, `layout`, `preset`, `tracker_spot`, `heat`, `claims`, `insured`, `hot`, `prestige`, `contract_cd`) are added on boot.

### 🧱 Floor Area & Props

Presets are generated **inside** the open floor and skip anything marked as an obstacle, so cars never clip the walls or the props that dress the warehouse.

| Step | How |
| --- | --- |
| Floor area | `/cargoslots` → Open setup copy → **Floor area**. Stand on one corner, `E`, then the opposite corner, `E` |
| Obstacles | **Add obstacle** the same way for shelving, pillars, the office, parked props |
| Clear | The bin button removes every obstacle |

{% hint style="warning" %}
The default `Config.Interior.Floor` box is a starting point. Fit it to your interior once and every preset refits for every warehouse.
{% endhint %}

---

## 🔁 Gameplay Loop

| Step | What happens |
| --- | --- |
| Buy | Talk to a broker NPC and pick a warehouse. Admin-added locations show up at every broker. |
| Enter | Third-eye the door: **Enter**, or **Knock** if it is not yours (someone inside lets you in). |
| Laptop | Third-eye the laptop in the office. The camera glides into the screen and the laptop boots. |
| Source | Take a contract by rarity, a special contract, or a crew job. Your contact texts you the brief. Higher tiers bring trackers, armed crews and police. |
| Tracker | Lose it at a tracker shop, let your garage strip it, or use your own removal spot. Leave it on and police, crews and other players find you. |
| Store | Drive into the garage. Illegal cars go to the lower level. Condition is read from the car's real health. |
| Design | Customize in the back with a GTA-style mod menu. Build points push the rarity up. |
| Sell | Pick a buyer and drive. Every hit, ram and bullet drops the offer. At the drop you hand over the keys, take an envelope of cash and watch the buyer drive off. |
| Move / sell the warehouse | At any broker: **Move here** buys another building and takes everything along (cars, upgrades, layout, crew), with a trade-in off the price. **Sell** gives the warehouse back for good. Set the shares in `Config.WarehouseSale`. |

---

## 🗝️ How Cars Are Taken

| Scenario | What you do |
| --- | --- |
| Parked | Locked on the street. Break in (skill check). |
| Moving | Someone is driving it. Stop them and pull them out. |
| Impound | Guarded lot. Break in and get out. |
| Party | Aim at a guest and they put their hands up (some run, some pull a gun). Third-eye **Search for keys** on each one until you find them. |
| Pickpocket | The owner strolls around the car. Sneak up **behind** him (no running, no gun out) and third-eye **Lift the keys**. Get noticed and he runs and calls the cops, or fights. |
| Hostile owner | He and his friends shoot first. Take him down and **Search the body**. |
| Guarded | Shootout. The guard holding the keys drops them when he goes down. Grab them off the ground. |
| Tow truck | The car won't start. Steal the flatbed from a guarded depot (hotwire), back up to the car, **Load the car**, tow it home. |
| Cargobob | The car is stranded. Steal the Cargobob from a guarded helipad, hover over the car, **Hook the car**, fly home and **Release** it over your garage. |

Key scenarios can't be lockpicked (`Config.Sourcing.KeysOnly`). Illegal contracts only roll the hard ones and get extra, better armed guards (`Config.Sourcing.Guards.Illegal`).

---

## 👥 Crew Roles & Crew Jobs

Every associate gets a role in the **Associates** app. The owner can always do everything.

| Role | Can |
| --- | --- |
| Manager | Everything except changing roles and owner settings |
| Driver | Contracts, crew jobs, selling |
| Mechanic | Design, repair, wash, insurance, crew jobs |
| Crew | Contracts, crew jobs |

Roles and their permissions are in `Config.Roles`.

**Crew jobs** (`Config.CrewJobs`) send everyone inside the warehouse to the same guarded lot. Each person gets their own car. Every car home = everyone gets the bonus.

### 🚚 Crew Sales

Sell several cars in one deal (`Config.CrewSale`). Inventory → **Crew sale**, tick 2 to 4 cars, **Find buyers**, pick a deal and give every car a driver from the crew inside. You drive one.

| Deal | How it works |
| --- | --- |
| Bulk Buyer / Export Broker | One buyer, every car to the same drop. Pays more per car the bigger the deal (`VolumeBonus`) |
| Split Run | Every car goes to its own drop |

| Rule | |
| --- | --- |
| Damage | Only lowers the price of the car that took the hit |
| Dropping a car | Its price locks and the driver waits for the rest of the crew |
| A lost car | The deal carries on without it (insurance pays out if it was insured) |
| Payout | Once no car is left on the road. Each crew member gets `Cut` of the whole deal, whoever set it up keeps the rest |
| Handover | Single drop: the whole crew watches one handover, the buyer's drivers take every car. Split run: everyone's handover plays at the same moment at their own drop |
| Attackers | Every car in the convoy can get its own crew on its tail (`AttackChance`) |

---

## 🛡️ Insurance, Heat & Raids

| System | How it works |
| --- | --- |
| Insurance | Insure a stored car from the Inventory. If it's lost on a sale or seized, the payout lands in your claims balance (Dashboard → Collect). Hot and illegal cars can't be insured by default. |
| Heat | Every stored car adds heat. Tracked, stolen and illegal cars add the most. It cools off every hour. |
| Warning | At `Warn` your contact texts you. Pay a contact off from the Dashboard to drop it. |
| Raid | At `Threshold`, on-duty police get a warrant: a blip on the door, third-eye **Raid warehouse**, then **Seize vehicle** on each car. With too few police on duty the cars are taken automatically, hot ones first. |

---

## 👑 Prestige

At max level, prestige from the Dashboard. Your level goes back to 1, contracts stay unlocked (`KeepUnlocks`) and you get a permanent bonus on sale money and XP for every prestige. Settings in `Config.Prestige`.

---

## 💻 The Laptop

| App | What it does |
| --- | --- |
| Dashboard | Level, XP, police heat, insurance claims, prestige, stock by rarity, recent activity |
| Contracts | Every tier, the special contracts (Classic Collector, Two-Wheel Run), Illegal once the lower level is open, and crew jobs. With `CooldownMode = 'contract'` each card has its own cooldown |
| Inventory | Main floor and lower level, design, repair, buyers, quick export, scrap |
| Upgrades | Storage, Design Bay, Lower Level, Intel, Tracker Workshop, Contacts, Repair, Style |
| Floor Plan | Pick a preset, drag spots around the floor, scroll on a spot to turn it, add or remove spots, or place them in game. Red spots clip a wall or prop |
| Scanner | Tracked cars other players are moving (Intel level 3) |
| Tracker Tools | Tracker risks, removal options, your own removal spot |
| Ledger · Leaderboard | Money and rankings |
| Associates | Your crew and their roles |
| Settings | Accent colour, laptop finish, wallpaper, clock, sounds, glass, crew radio, move the HUD |

Walk up to any parked car and its spec card (rarity, plate, condition, build score, worth) floats above it. GTA's own laptop on the office desk is hidden automatically so only the business laptop shows (`Config.Laptop.HideModels`).

Windows can be dragged, minimized, maximized and stacked. `ESC` shuts the laptop. Admin tools are not on the laptop; they are command only.

### 🎨 Owner Preferences

The owner picks an accent colour, laptop finish, wallpaper, 12/24-hour clock, sounds, see-through windows and crew radio. It is saved on the warehouse, so associates see the owner's laptop. The owner's accent also colours their HUD, design bay menu and placement markers everywhere. Add colours, finishes or wallpapers in `Config.Prefs`.

---

## ⚙️ Main Settings

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Framework` | `'auto'` | `esx`, `qb`, `qbx` or `auto` |
| `Config.Notify` | `'auto'` | `nayzeee`, `ox`, `esx`, `qb`, `okok` or `custom` |
| `Config.Target` | `'auto'` | `ox_target`, `qb-target`, `interact` or `textui` |
| `Config.Phone.System` | `'auto'` | Phone used for attacker texts, `none` for on-screen only |
| `Config.MaxWarehousesPerPlayer` | `1` | Ownership limit |
| `Config.BucketBase` | `7400` | Warehouse bucket = base + warehouse id |
| `Config.Layout.MaxSlots` | `32` | Most spots a floor can have |
| `Config.Sourcing.TrackerChance` | see config | Tracker chance per tier (illegal `0.60`) |
| `Config.Attackers` | see config | Crew vehicles, peds, weapons, chance and size per tier |
| `Config.Hijack.Enabled` | `true` | Players can steal tracked cars into their own warehouse or chop them |
| `Config.Hijack.ChopPayout` | `0.35` | Share of value a chop shop pays |
| `Config.Selling.Cutscene.Enabled` | `true` | Key handover scene at the buyer |
| `Config.Selling.Damage` | see config | % lost per hit, ram, shot and explosion |
| `Config.Selling.MinOffer` | `0.25` | The offer never drops below this share |
| `Config.Workshop.Mode` | `'builtin'` | `builtin`, `external` (your mechanic script) or `both` |
| `Config.Laptop.SpawnProp` | `true` | Spawn the laptop prop at the laptop point |
| `Config.Doors.Knock` | `true` | Visitors can knock to be let in |
| `Config.Prefs.Default` | see config | Starting look for every new warehouse |
| `Config.Radio.Enabled` | `true` | Crew radio during jobs |
| `Config.Radio.Base` | `750` | Channel = base + warehouse id |
| `Config.Radio.Who` | `'crew'` | `crew`, `nearby` or `runner` |
| `Config.Placer.Step` | `10.0` | Degrees per scroll notch |
| `Config.Music.Mode` | `'native'` | GTA's own Import/Export score, `custom` or `off` |

---

## 💎 Rarities

| Rarity | Level | Fee | Value multiplier |
| --- | --- | --- | --- |
| Common | 1 | $2,500 | 1.00 |
| Uncommon | 3 | $5,000 | 1.22 |
| Rare | 6 | $9,000 | 1.50 |
| Epic | 11 | $16,000 | 1.85 |
| Legendary | 18 | $26,000 | 2.30 |
| Mythic | 28 | $42,000 | 2.90 |
| Illegal | 22 | $75,000 | Own vehicle list |

Build score 40 gives +1 rarity and 75 gives +2. The Design Bay level caps how far a car can climb. Illegal cars keep their tier, but builds still raise their value.

{% hint style="info" %}
Illegal contracts need the **Lower Level** upgrade. The lower floor holds 4 cars. Add or change illegal models in `Config.IllegalVehicles`.
{% endhint %}

---

## 🔧 Mechanic Integration

Set `Config.Workshop.Mode` to `external` or `both`, then open `bridge/client.lua` → `Bridge.OpenMechanic(vehicle, done)`. Open your tuning menu on `vehicle` and call `done()` when the player finishes. The script reads the vehicle props and scores the build itself, so any mechanic script works.

| Mode | Behaviour |
| --- | --- |
| `builtin` | GTA-style menu in the design bay |
| `external` | Your mechanic script on the car in the design bay |
| `both` | The player picks each time |

---

## 🔪 Chop Shop Integration

Stolen cars you can't store go to a chop shop. Keep ours, or send players to another creator's: set `Config.ChopShop.System` to `bablo`, `lation`, `custom` or `auto`, and list that script's shop positions in `Config.ChopShop.External`.

| How we know it was chopped | Setup |
| --- | --- |
| Automatic | The job car disappears within `DetectRadius` of one of their shops. Works with any script. |
| Exact (recommended) | Add one line where their script pays for a chop: `exports['nayzeee-vehiclecargo']:VehicleChopped(source, plate)` |

Their script pays. Set `PayOnExternal = true` to pay ours as well. See `integrations/chopshop.lua` for the hook.

---

## 📍 Drop-offs

Buyers wait at `Config.Dropoffs`. Every entry has a `name` (shown on the GPS and HUD), an `area` (to help you find it) and `coords`. The closest third from the selling warehouse are near drops, the middle third mid, the farthest third far.

---

## 📻 Crew Radio

When a contract or sale starts, the owner and associates who are online join a private voice channel (`Config.Radio.Base` + warehouse id). When the last job from that warehouse ends, everyone goes back to the channel they were on. The HUD shows the channel while it is live. Owners can turn it off in laptop Settings.

| System | Supported |
| --- | --- |
| `pma-voice` (and radios built on it, like mm_radio) | Yes |
| `saltychat` | Yes (server side) |
| `tokovoip_script` | Yes |
| Anything else | Set `System = 'custom'` and fill in `Bridge.JoinRadio` / `Bridge.LeaveRadio` in `bridge/client.lua` |

---

## 📱 Phone Texts

Your contact texts you the job brief (`Config.Phone.Contact`), attack crews text before they hit, and you get a heads-up before a raid.

| Setting | What it does |
| --- | --- |
| `System` | `lb-phone`, `npwd` out of the box. `yseries`, `qs-smartphone`, `gksphone` have stubs in `Bridge.PhoneMessage` |
| `Sender` | The contact name on the notification |
| `Number` | The number texts come from. **lb-phone needs a real number here**, a name does not work |
| `Notify` | Also pushes an lb-phone notification so it pops with the phone closed |
| `Fallback` | Shows a phone-style popup on screen when no phone takes the text |

{% hint style="info" %}
Test it with `/cargotext [id]` (admin). Turn on `Config.Debug` to see why a text didn't go through (no phone equipped, resource not running).
{% endhint %}

---

## ⌨️ Commands

| Command | Who | Description |
| --- | --- | --- |
| `/cargolayout` | Owner | Place your own parking spots on the main floor with the ghost car |
| `/cargotrackerspot` | Owner | Aim and set your own tracker removal spot (Tracker Workshop level 3) |
| `/cargohud` | Everyone | Drag the mission HUD anywhere. `ENTER` save · `R` reset · `ESC` cancel |
| `/cargocancel` | Everyone | Cancels your active contract or sale |
| `/cargoadmin` | Admin | Vehicles, locations, interior, brokers, presets, warehouses and players |
| `/cargoslots` | Admin | Opens the admin panel straight on the Interior setup |
| `/cargocoords` | Admin | Copies your position as `vec4(...)` |
| `/cargotext [id]` | Admin | Sends a test text to check your phone setup |

---

## 🔌 Exports

```lua
-- server
exports['nayzeee-vehiclecargo']:GetLevel(source)        -- number
exports['nayzeee-vehiclecargo']:AddXp(source, amount)   -- true if they levelled up
exports['nayzeee-vehiclecargo']:IsInWarehouse(source)   -- warehouse id or false
```

---

## 🚓 Police & Dispatch

Police on duty see tracked cars move on their map while the tracker is on. Break-ins, failed hotwires, spooked pickpocket targets, tracker pings and raids send an alert through `Config.Dispatch.System`.

| System | Notes |
| --- | --- |
| `auto` | First one running of ps-dispatch, cd_dispatch, rcore_dispatch, qs-dispatch, else the built-in alert |
| `ps-dispatch` · `cd_dispatch` · `qs-dispatch` | Raised from the player's client, like those resources expect |
| `rcore_dispatch` | Server event |
| `builtin` | Notification + timed blip for every on-duty job in `Config.Sourcing.PoliceJobs` |
| `custom` | Fill in `Bridge.CustomDispatch(data)` in `bridge/server.lua` and return `true` |

`data` holds `title`, `message`, `coords`, `code`, `blip`, `plate`, `model` and `src`.

---

## 🧯 Troubleshooting

| Issue | Solution |
| --- | --- |
| Cars sit in walls or float | `/cargoslots` → Open setup copy → Place spots, aim at the floor for each one |
| The lower level is black or in the wrong place | `/cargoslots` → Move the 4 spots, and check `Config.Interior.Lower.SplitZ` sits between the two floors |
| No broker on the map | `/cargoadmin` → Brokers → Place broker (outside a warehouse) |
| The laptop is in the wrong place | `/cargoslots` → Laptop → Place, aim at the desk and scroll until the ghost laptop's screen faces you |
| The laptop camera ends up behind the screen | Set `Config.Laptop.FlipSide = true` |
| A second laptop still shows on the desk | Add its model name to `Config.Laptop.HideModels` |
| Attackers spawn too close or too far | `Config.Attackers.Spawn` (Min / Max distance, always out of sight) |
| Chops at another script do nothing | Add the `VehicleChopped` line, or put its shop coords in `Config.ChopShop.External` |
| Crew radio does nothing | Check `Config.Radio.System` matches your voice resource, or use `custom` |
| Texts don't reach the phone | Give `Config.Phone.Number` a real number (lb-phone ignores names), check the player has a phone equipped, then `/cargotext` |
| Presets clip walls or props | `/cargoslots` → Floor area, then Add obstacle for each prop |
| A dispatch alert doesn't show | Set `Config.Dispatch.System` to your resource instead of `auto`, or use `custom` |
| No keys after taking a car | Add your key resource to `Bridge.GiveKeys` in `bridge/client.lua` |
| Players can't take contracts | Check `Config.Sourcing.MinPolice`, cooldowns and floor capacity |
| After a restart or relog players stand in an empty warehouse | Handled for you: they go back into their own warehouse, or out the front door (`Config.Resume`). No multicharacter changes needed. Turn `Config.Resume.Enabled` off only if another script uses the same interior. |
