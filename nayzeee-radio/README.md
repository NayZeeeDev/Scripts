```
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
██████╗  █████╗ ██████╗ ██╗ ██████╗
██╔══██╗██╔══██╗██╔══██╗██║██╔═══██╗
██████╔╝███████║██║  ██║██║██║   ██║
██╔══██╗██╔══██║██║  ██║██║██║   ██║
██║  ██║██║  ██║██████╔╝██║╚██████╔╝
╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝ ╚═════╝
```

# NAYZEEE Radio

**Version 1.0.0** · Support: [discord.gg/nayzeeedev](https://discord.gg/nayzeeedev)

A radio system for FiveM built on pma-voice. You bring the radio up in front of your face
and work it with the keys, knobs and buttons on the model while its own screen shows the
frequency. Three handheld models, a dash head unit for radio cars, a signal that depends on
distance, height and jammers, and channels you lock by code or job in game.

- **ESX · QBCore · Qbox · Standalone**, detected by itself.
- **9 inventories, 5 target scripts (or none)**, all optional and detected.
- **Server-authoritative.** The server decides who hears whom and how well, from real
  positions, and checks every item, channel lock, seat and jammer.
- **No database needed.** oxmysql is used when it runs; otherwise the radio keeps its data
  in JSON files.

---

## Contents

1. [Features](#1-features)
2. [Requirements](#2-requirements)
3. [Installation](#3-installation)
4. [Configuration](#4-configuration)
5. [Using the radio](#5-using-the-radio)
6. [Admin panel: quick start](#6-admin-panel-quick-start)
7. [Commands and keys](#7-commands-and-keys)
8. [For developers](#8-for-developers)
9. [FAQ and troubleshooting](#9-faq-and-troubleshooting)

---

## 1. Features

### Radios and models

| Model | Item | Range | Channel slots | Water | Jam resistance | On the device |
|---|---|---|---|---|---|---|
| **PX-740** patrol handheld | `radio` | 2.6 km | 3 | not waterproof | none | colour screen, d-pad, P1 / P2 keys, two side buttons |
| **FX-280** field set | `radio_fieldpro` | 4.2 km | 4 | waterproof | 15 % | segment LCD, power key, dual knob (channel ring, volume cap) |
| **MX-905** tactical set | `radio_military` | 6.5 km | 5 | waterproof | 40 % | green tactical screen, d-pad, two side buttons |
| **MV-90** head unit | radio cars | 7.0 km × the car's multiplier | 1 | — | none | dash unit with keypad, PRE, MUT, PWR, a covered EMERG switch, hand mic |

- **Range** is the distance at which a link fades out on flat ground. A link between two
  different radios uses the average of both, so a PX-740 talking to an MX-905 reaches
  about 4.5 km.
- Each model has its **own screen**, keys and layout. Every value in the table is in
  `config/modules/radios.lua` and `config/modules/vehicles.lua`.
- The **battery gauge** is for looks only: it drains slowly while the radio is on and never
  runs out.

### Raising it and the real keys
- The raise key (**F10**), `/radio` or using the item brings the radio up in front of your
  face. The camera moves close, the mouse cursor appears and the game keeps running around
  you.
- **Click any key, knob or button on the model.** Keys move in when pressed, knobs turn one
  click at a time, the d-pad tilts toward where you press it. Hold an arrow or a knob and it
  repeats.
- The **keyboard** works too while it is up: 0-9, Backspace, Enter, the arrow keys and
  Num * (decimal point).
- A faint outline shows which part is under the cursor, and a key card on the right edge
  lists what the mouse and keys do.
- **Mouse wheel** zooms; over a knob it turns the knob.
- **Other players see the radio in your hand** while you have it up. The TX lamp lights red
  while you talk, the RX lamp green while you receive, and the amber lamp blinks during an
  emergency.
- The radio lowers by itself when you die, ragdoll, get into a vehicle, get cuffed or go
  into the water with a radio that is not waterproof.

### Channels and slots
- **Frequencies from 1.00 to 999.99 MHz**, two decimals. Type them on the keypad: `*` is the
  decimal point, and a fourth digit puts the point in for you (`1555` becomes `155.5`).
- **Slots**: a radio listens to every channel in its slots at once (3, 4 or 5 by model). You
  talk on one of them, the **TX slot**. Pick it with up / down on the radio, the slots
  screen or the next-slot key.
- The home screen shows the TX frequency, the channel name, every slot with its frequency,
  who is talking with their signal bars, and small icons for mute and hands-free.
- **Hands-free** keeps your mic open on the TX channel until you switch it off.
- **Mute** silences everything you receive. Emergency alerts still come through.
- **Mic clicks**: the short key-up and key-down chirps, per player, on or off in the radio's
  menu.
- **Volume** is per player and kept between sessions.

### Memories and callsign
- **6 memories per character**, saved in the database (`Config.Radios.presets`).
- Store a frequency from the memories screen; the channel knob (or PRE on the head unit)
  steps through your memories and tunes the TX slot once you stop turning.
- **Callsign** with `/callsign 1G-12` (up to 8 characters). It shows next to your name for
  the people who hear you, in the roster and on emergency alerts. Saved per character.

### Locked channels
- **Code channels**: the radio asks for a 4-digit code before it joins. Once entered, the
  channel stays unlocked for you until you leave the server. Three wrong codes lock that
  frequency for you for 30 seconds.
- **Job channels**: only listed jobs from a minimum grade get in, optionally only on duty
  (`Config.Channels.requireDuty`).
- **Fixed ranges** in the config: 1.00-10.99 is locked to police, sheriff and EMS out of the
  box (`Config.Channels.Restricted`).
- Admins lock single frequencies in game with `/radioadmin`. Those rules win over the fixed
  ranges. Codes never leave the server, except to admins in that window.
- When a player loses access (job change, a rule saved in `/radioadmin`), their handheld
  drops that channel and they get a notification.

### Signal
- Every link between two radios has a **quality from 0 to 1**, worked out on the server from
  both positions. It starts to fade at 55 % of the range and is gone at the full range.
- **Height helps**: above 40 m the range grows by 1 % per 4 m, up to +75 % (rooftops,
  hills, helicopters).
- **Dead zones**: places you list in `Config.Signal.DeadZones` (tunnels, deep interiors)
  shrink the range.
- **What you hear** follows the quality: a clear link sounds clean; a weak one sounds
  harsher, hisses and drops out in short bursts; below the lowest band you only hear the
  carrier breaking up, not the voice. Transmissions end with a squelch tail.
- **Under water** a radio that is not waterproof loses the link.
- The radio's screen shows **signal bars**; `/radiorange` draws your reach on the map.
- The radio voice goes through GTA's radio effect, set per signal band in
  `config/modules/signal.lua`. Every beep, chirp, hiss and squelch is generated in the
  browser: there are no sound files.

### Jammers and the hack
- Three placeable jammers: **JX-10** pocket unit (45 m, 15 min), **JX-40** case (110 m,
  30 min) and **JX-90** cabinet (220 m, 45 min).
- Use the item to place it: a see-through copy follows where you look, the **mouse wheel** or
  the **arrow keys** turn it (**Shift** for slow), **E** sets it down, **Backspace** or
  **right mouse** puts it away. It must be within reach, on fairly flat, dry ground and not on
  a car or a person, and you must be on foot. One per player by default.
- Radios inside the radius **fill with static** (louder closer in, scaled by the radio's
  volume) and their links get worse. Close to a strong jammer a radio **cannot transmit at
  all** and shows NO SIGNAL. Jam resistance (FX-280, MX-905) takes part of the effect away.
- A jammer runs until its battery is empty, its owner **picks it up**, the police or
  sheriff **seize** it (they get the item), an admin takes it down, or someone **hacks** it.
- **The hack**: a window with two dials, **Phase** and **Gain**. You shape your own
  counter-signal until it cancels the jammer's carrier, then hold the match while a ring
  fills. JX-10 has 1 stage, JX-40 2 and JX-90 3, against one clock (25, 40 and 55 s). The
  carrier drifts more each stage. Fail or give up and you wait 20 s before the next try. A
  hacked jammer goes off for everyone and its owner is told.
- Pick up / Hack works through ox_target, qb-target, qtarget, interact or
  sleepless_interact, or the built-in **[E]** prompt without a target script.

### Vehicles and the head unit
- **Radio cars** get the MV-90 head unit in the dash: every emergency-class vehicle, the
  models in `Config.Vehicles.models`, and the cars admins add in `/radioadmin`.
- From the **driver or front passenger seat**, the raise key opens the head unit. You can
  keep driving while it is open.
- **One frequency per car.** Keypad, `*` and `#`, OK, CLR, **PRE** steps through your
  memories, **MUT** mutes the speaker, **PWR** switches it on and off, **EMERG** sits under a
  flip cover. A volume knob and a channel knob sit at the ends.
- In those seats, with the head unit on and tuned, your **talk key goes through the car**
  (`Config.Vehicles.pttPriority`). The car's aerial reaches further than any handheld, and
  admins can scale it per car. You do not need a handheld to use the head unit.
- Tuning a car goes through the same channel locks as a handheld.

### Outside speaker and cabin
- **Everyone inside** a car hears its head unit.
- **People standing next to the car** (12 m) hear it through the outside speaker, quieter
  when every door is shut.
- **Handhelds are audible to the people beside you** (2.2 m) when you receive, unless you
  wear the **earpiece**: use the item or switch it in the radio's menu.
- **Passengers get a small HUD** at the top of the screen while the head unit is on:
  frequency, channel name and who is talking.
- A faint **cabin hiss** with the odd squelch plays in a car whose head unit is on.

### Emergency
- Hold the **emergency button** on the radio for 1.5 s (or the emergency key, or EMERG on the
  head unit). Everyone on your TX frequency gets an alert tone, a card with your name,
  callsign, channel, street and distance, and a flashing blip on your position for 60 s. Muted
  radios and tuned cars get it too.
- Your **mic stays open for 8 s** afterwards, so they hear what is happening.
- 30 s cooldown per player. Limit it to jobs with `Config.Emergency.jobs`.
- Hook your dispatch script in `config_server.lua` (`ServerConfig.EmergencyHook`), and log
  alerts to Discord.
- The keybind "Radio: route to the last emergency" (no default key) sets a waypoint on the
  last alert.

### Gunfire over an open mic
- While you transmit, your mic picks up **gunshots within 60 m**: your own, other players' and
  NPCs'.
- Listeners hear each shot through their radio with the same timing, its sound set by the
  weapon (pistol, SMG, rifle, shotgun, sniper, heavy, silenced), quieter with distance and
  with a worse signal. At most 20 shots a second.

### Roster
- A small card at the right edge: **who is on your TX channel**, their signal bars from your
  side, and who is talking now (talkers move to the top).
- Shown while the radio is up, toggled with the roster key, the side button or the menu, and
  for a few seconds when someone starts talking (`Config.Roster.popOnRx`).

### Admin
- **`/radioadmin`** opens the Radio control window: channel locks, radio cars and a live view
  of every channel in use, who is talking and every jammer that is out. See
  [Admin panel](#6-admin-panel-quick-start).
- **Discord logs** for admin changes, emergency alerts and jammers (`config_server.lua`).

---

## 2. Requirements

| | |
|---|---|
| **FiveM server** | OneSync enabled (`set onesync on`). The server reads player positions for range, jammers and car speakers |
| **[ox_lib](https://github.com/overextended/ox_lib)** | required |
| **[pma-voice](https://github.com/AvarianKnight/pma-voice)** | required. It keeps doing proximity voice and phone calls; the radio uses its own channels and never uses pma-voice's radio |
| **Framework** | ESX, QBCore, Qbox, or none (standalone). An ox_core server runs as standalone |
| **Inventory** | ox_inventory, qb-inventory, ps-inventory, lj-inventory, qs-inventory, codem-inventory, tgiann-inventory, origen_inventory, core_inventory or the framework's own inventory (ESX default, QBCore) |
| **[oxmysql](https://github.com/overextended/oxmysql)** (optional) | stores memories, callsigns, channel locks and radio cars in MySQL / MariaDB. Without it the same data goes into JSON files |
| **Target** (optional) | ox_target, qb-target, qtarget, interact, sleepless_interact, for the jammers. Without one, a built-in **[E]** prompt is used |

Notifications use the radio's own toasts. ox_lib, okok, codem, mythic, brutal, t-notify,
QBCore, ESX, NAYZEEE or the native feed can be forced in `config/modules/bridge.lua`.

---

## 3. Installation

### Step 1 · Put the resources in place
1. Extract the download into your `resources` folder. It holds two resources:
   - `nayzeee-radio`: the script.
   - `nayzeee-radio-props`: the streamed models (radios, their keys and knobs, jammers). They
     are kept apart so that restarting the script after a config change or an update does
     not make every player load the models again.
2. The script folder **must be named exactly `nayzeee-radio`**. Any other name stops the
   resource with a red message in the console, because exports, events, the NUI and the radio
   screens use that name. Keep the props folder named `nayzeee-radio-props`: the script lists
   it as a dependency and will not start without it.
3. `nayzeee-radio-props/stream/` must hold the `.ydr` models and `nzr_props.ytyp`. If you
   have the props as source files instead (CodeWalker XML, no `.ydr` files in `stream/`),
   convert them once as described in `nayzeee-radio-props/stream/README.md`.

### Step 2 · server.cfg
Start it **after** ox_lib, pma-voice, oxmysql (if you use it), your framework, your
inventory and your target script:

```cfg
ensure ox_lib
ensure oxmysql            # optional: without it the radio saves JSON files
ensure pma-voice
ensure es_extended        # or qb-core / qbx_core (leave out for standalone)
ensure ox_inventory       # your inventory
ensure ox_target          # your target script (optional)

ensure nayzeee-radio-props
ensure nayzeee-radio

# admins: /radioadmin (channel locks, radio cars, live view, removing jammers)
add_ace group.admin nzr.admin allow
# add_principal identifier.license:xxxx group.admin   (if you are not in group.admin yet)

# optional, see FAQ "pma-voice and the raised radio"
setr voice_disableAutomaticListenerOnCamera 1
```

Framework admin groups in `Config.Admin.groups` (`admin`, `god`, `superadmin`) count as
admins too.

### Step 3 · Database
- **With oxmysql**: nothing to do. The three tables (`nzr_players`, `nzr_channels`,
  `nzr_vehicles`) are created on the first start. If your database user may not create
  tables, run `sql/install.sql` once (safe to run again).
- **Without oxmysql**: the radio writes `players.json`, `channels.json` and `vehicles.json`
  into `nayzeee-radio/data/`. Create that `data` folder once if it is not there; without it
  the files land in the resource folder itself (`nzr_*.json`) and the console says so once.

### Step 4 · Items
The resource uses 7 items: `radio`, `radio_fieldpro`, `radio_military`, `radio_earpiece`,
`jammer_pocket`, `jammer_case` and `jammer_heavy`. `install/` holds them for every inventory
and `html/img/items/` has a picture for each one. Pick your inventory:

| Inventory | What to do |
|---|---|
| **ox_inventory** (ESX, QBCore, Qbox, standalone) | Copy every entry of `install/ox_inventory_items.lua` into `ox_inventory/data/items.lua`. No pictures to copy: they load from this resource. Keep `consume = 0` on every item. |
| **qb-inventory** (QBCore) | Paste `install/qb_shared_items.lua` into `qb-core/shared/items.lua` (inside `QBShared.Items`). Copy `html/img/items/*.png` into `qb-inventory/html/images/`. |
| **ps-inventory / lj-inventory** | Same entries in `qb-core/shared/items.lua`. Pictures into `ps-inventory/html/images/` or `lj-inventory/html/images/`. |
| **Qbox** | Uses ox_inventory: follow the ox_inventory row. |
| **qs-inventory** | Paste `install/qb_shared_items.lua` into `qs-inventory/shared/items.lua`. Pictures into `qs-inventory/html/images/`. |
| **codem-inventory** | Add the `qb_shared_items.lua` entries to its item list (on ESX also run `install/esx_items.sql`). Pictures into `codem-inventory/html/itemimages/`. |
| **tgiann-inventory** | Add the `qb_shared_items.lua` entries to its item list. Pictures into `inventory_images/images/`. |
| **origen_inventory / core_inventory** | QBCore: the `qb_shared_items.lua` entries. ESX: run `install/esx_items.sql`. Pictures into `origen_inventory/html/images/` or `core_inventory/html/img/`. |
| **ESX default inventory** | Run `install/esx_items.sql`. Weights are in kg; gram-based servers can take the gram weights from `install/ox_inventory_items.lua`. |

Most servers already have a `radio` item: replace it with ours, or rename ours in
`config/items.lua`. Restart the server after adding items. More detail, item renaming and
pictures: `install/README.md`.

### Step 5 · Framework
Jobs only matter for job-locked channels, the jammer seize / hack jobs and
`Config.Emergency.jobs`.

| Framework | Setup |
|---|---|
| **ESX** | Job and grade from ESX. Duty uses `job.onDuty`; older servers with an `offpolice` job work too (`Config.Bridge.offDutyPrefix`, `offDutyJobs`). Duty only counts when `Config.Channels.requireDuty = true`. |
| **QBCore** | Job, grade and duty from QBCore. |
| **Qbox** | Detected before QBCore. Same as QBCore. |
| **Standalone** | Jobs come from aces: `add_ace identifier.license:xxxx nzr.job.police allow`, optional grade `nzr.grade.police.3`, boss `nzr.grade.police.boss`. The job list is `Config.Bridge.standaloneJobs`. Use ox_inventory for items; on a test server without any inventory, `Config.Bridge.standaloneFreeItems = true` gives everyone every item. |

You can force any integration in `config/modules/bridge.lua` (`framework`, `inventory`,
`target`, `notify`).

### Step 6 · Remove your old radio script
Stop any other radio script (qb-radio, ps-radio, mm_radio and the like). Two radio scripts
fight over the same voice target and over the `radio` item. Keep pma-voice itself: only its
own radio stays unused, so do not let another script call its `setRadioChannel` either.

### Step 7 · Start
Restart the server. The console prints one line with the version, framework and inventory,
and warns if `nayzeee-radio-props` is not running. Give yourself a `radio`, use it, turn the
volume knob up, type `155.5` and press OK. Hold **Caps Lock** to talk.

---

## 4. Configuration

Every config file is open (not escrowed) and every option has a short comment. So are
`locales/`, `bridge/`, `install/` and `sql/`.

### Core files
| File | What you set there |
|---|---|
| `config/config.lua` | Debug, language, framework, the props resource check, **UI** (font, window shape, scale, sounds, signature), **admin** ace and framework groups, **command names**, **default keys** |
| `config/items.lua` | `Config.Items`: the item name your inventory uses for each key (rename here, never the key). `Config.ItemDefs`: label, weight, stacking, description, used to build the install files |
| `config_server.lua` | Server only: **Discord webhook** (or the convar `nayzeee_radio_webhook`) and what it logs, **`ServerConfig.EmergencyHook`** for your dispatch script |
| `config/modules/bridge.lua` | Which framework / inventory / target / notify script to use (`'auto'` by default), standalone jobs and aces, ESX off-duty jobs, the built-in [E] prompt, item pictures, `standaloneFreeItems`, bridge debug |

### Feature files (`config/modules/`)
| File | Feature |
|---|---|
| `radios.lua` | The three models (range, slots, jam resistance, waterproof, grip in the hand), which radio is active when you carry several, number of memories, callsign length, default volume, talking (animation, radio in hand while talking, talking while dead), the raised view (pose, field of view, zoom limits, parallax, hover outline, key repeat, hiding the minimap) |
| `channels.lua` | Frequency band, fixed locked ranges, on-duty rule for job channels, wrong-code attempts and lockout |
| `signal.lua` | Falloff, refresh rate, height bonus, signal bands, the jam level that blocks transmitting, dead zones; **audio** (mic clicks, hiss, squelch, which ear, the in-person distance, beep volume, GTA radio effect per band); **leak** (handheld and car speaker distance, volume, doors shut) |
| `vehicles.lua` | Head units on or off, vehicle classes and models, operating seats, car range, talk through the car, cabin volume, passenger HUD, cabin hiss |
| `jammers.lua` | Jammers on or off, placing distance, jammers per player, who may hack, who may seize, lockout after a failed hack, prop draw distance, and per type: label, model, radius, full-strength core, strength, battery life, hack stages and time |
| `alerts.lua` | **Emergency** (hold time, cooldown, blip time, open-mic time, jobs), **gunfire** (radius, shots per second, NPCs), **roster** (name format, rows, refresh, pop-up on talk) |

### Language
Every text is in `locales/en/*.lua`. To translate: copy `locales/en` to `locales/de` (for
example), change `NZR.AddLocale('en'` to `NZR.AddLocale('de'` at the top of each file, translate
the values and set `Config.Locale = 'de'`. Missing keys fall back to English. The words on
the radio screens are in `locales/en/client.lua` (`client.scr_*`); keep them short, the
screens are a few centimetres wide. A few labels printed on the devices themselves (MHz, TX,
RX, model codes) are part of the hardware and stay as they are.

---

## 5. Using the radio

### First steps
1. **Use the radio item** (or press **F10**, or type `/radio`). The radio comes up in front
   of you.
2. **Switch it on**: turn the volume knob up (click its right half or scroll over it). On the
   FX-280 you can also hold the POWER key. The screen runs a short self test.
3. **Type a frequency** on the keypad (`*` = decimal point) and press **OK**. A code channel
   asks for its 4-digit code next.
4. **Hold Caps Lock to talk.** The radio does not have to be up for that.
5. **Lower it** with the right mouse button, Esc or F10. It stays on and keeps receiving.

To switch it off, turn the volume knob all the way down and keep turning for a second (or
hold POWER on the FX-280).

### Keys while the radio is up
| Key | What it does |
|---|---|
| **Left mouse** | Press the key, knob or button under the cursor (knobs: left half down, right half up) |
| **Right mouse** · **Esc** · **F10** | Lower the radio |
| **Mouse wheel** | Zoom; over a knob, turn it |
| **Caps Lock** (hold) | Talk |
| **0-9** | Keypad |
| **Num \*** | Decimal point |
| **Enter** · **Backspace** | OK · delete / back |
| **Arrow keys** | Up / down: TX slot or list cursor; left / right: volume |

### Controls on each model
| To do this | PX-740 | FX-280 | MX-905 |
|---|---|---|---|
| Switch on / off | volume knob | POWER key (hold) or volume cap | volume knob |
| Tune the TX slot | keypad, `*`, OK | keypad, `*`, SET | keypad, `*`, OK |
| Delete / go back | BACK | BAND | BACK |
| Open the menu | OK on the home screen | MENU or SET | the green menu key, or OK |
| Pick the TX slot | d-pad up / down | ▲ / ▼ keys | d-pad up / down |
| Volume | volume knob, d-pad left / right | volume cap (inner knob) | volume knob, d-pad left / right |
| Step through memories | channel knob | channel ring (outer knob) | channel knob |
| Memories screen | P1 | menu → Memories | menu → Memories |
| Mute | P2 | menu → Mute | menu → Mute |
| Hands-free | upper side button | side button | upper side button |
| Roster | lower side button | menu → Roster | lower side button |
| Clear the TX slot | `#` on the home screen | `#` | `#` |
| Emergency alert | hold the emergency button | same | same |
| Talk | hold the PTT bar on the side, or Caps Lock | same | same |

### The menu
Memories · Slots · Mute · Hands-free · Mic clicks · Earpiece (once you own one) · Roster ·
Callsign (shows yours; set it with `/callsign`) · Close. Up / down (or the channel knob)
moves, OK switches or opens, BACK leaves.

### Memories and slots
- **Memories screen**: browse with up / down or the channel knob. **OK** on a stored memory
  tunes it on the TX slot. Type a frequency and press **OK** to store it there; `#` clears it.
- **Slots screen**: pick a slot, **OK** makes it the TX slot, type a frequency and **OK** to
  tune that slot, `#` leaves it.
- On the home screen the **channel knob** steps through your stored memories and tunes the
  one you stop on.

### Messages on the screen
| Screen | Meaning |
|---|---|
| ACCESS CODE | The channel needs a 4-digit code |
| CODE REJECTED | Wrong code |
| TRY LATER | Too many wrong codes: wait 30 s |
| RESTRICTED | Your job or grade is not allowed on it |
| OUT OF BAND | Not a frequency the radio can tune |
| NO CHANNEL | The TX slot is empty |
| NO SIGNAL | Too close to a jammer to transmit |
| WAIT | Emergency cooldown |

### The head unit (MV-90)
Sit in the driver or front passenger seat of a radio car and press **F10**. You keep
driving while it is open; F10 or Esc closes it.

| Control | What it does |
|---|---|
| **PWR** | Switch the head unit on / off (a tap) |
| **0-9** · `*` · **OK** | Type and tune the car's frequency |
| **CLR** | Delete a character |
| `#` | Cancel typing; on the main screen, clear the frequency |
| **PRE** · channel knob | Step through your memories |
| **MUT** | Mute the speaker |
| Volume knob | Volume |
| **EMERG** | Click the cover to flip it up, then hold the button for the emergency alert |
| Hand mic | Hold to talk through the car |

The keyboard works while it is open: 0-9, `*`, `#`, Enter (OK), Backspace (CLR), up / down
(channel knob), left / right (volume knob) and your talk key. Knobs also turn by dragging
around them or with the mouse wheel.

---

## 6. Admin panel: quick start

You need the `nzr.admin` ace (Step 2) or a framework group from `Config.Admin.groups`.

1. **Open it**: `/radioadmin`.
2. **Channels** → **New rule**: type the frequency, choose who gets in (**Open**, **Code** or
   **Job**), then the 4-digit code or the jobs with their lowest grade, and a name. Every row
   is checked as you type; a rule inside one of the fixed ranges wins over the range there.
   Search and the Open / Code / Job filter help on long lists.
3. **Vehicles** → **New car**: the spawn name, a label and a range multiplier (×0.5 to ×3.0).
   Sitting in a car? **Add this car** takes it straight from your seat.
4. **Save** (or Ctrl + S). The rules apply at once on the whole server. Players who lose
   access to a channel are taken off it on their handhelds; when you change a channel's code,
   everyone has to enter the new one. Close with Esc; with edits not yet saved it asks first.
5. **Live** shows radios switched on, channels in use (handhelds and head units), who is
   talking and every jammer that is out with its time left. Set a waypoint on a jammer or
   take it down from there.

The ranges from `Config.Channels.Restricted` are listed in the sidebar, read only. Change
them in `config/modules/channels.lua`.

---

## 7. Commands and keys

### Admin (ace `nzr.admin`, or a framework group in `Config.Admin.groups`)
| Command | What it does |
|---|---|
| `/radioadmin` | Radio control window: channel locks, radio cars, live view, jammers |
| `/radiogrip x y z rx ry rz` | Only with `Config.Debug = true`: move the radio in your hand live and print the config line to the F8 console |

### Players
| Key / command | What it does |
|---|---|
| hold **Caps Lock** | Talk on your TX channel (through the car when the head unit is on and you sit in an operating seat) |
| **F10** · `/radio` | Raise / lower the radio; in a radio car's front seats, open / close the head unit |
| `/callsign [text]` | Set your callsign (up to 8 characters); without text it clears it |
| `/radiorange` | Show on the map for 10 s how far your radio reaches from here |
| no default key | Hands-free on / off |
| no default key | Mute / unmute |
| no default key | Talk on the next channel slot |
| no default key | Show / hide the roster |
| no default key | Hold for the emergency alert |
| no default key | Route to the last emergency |
| **0-9 · Backspace · Enter · arrows · Num \*** | Radio keypad, only while the radio is up |

Every key is a FiveM key mapping: players can rebind them in **Settings → Key Bindings →
FiveM** (they all start with "Radio"). Change the defaults in `Config.Keys` and the command
names in `Config.Commands` (`false` turns a command off).

---

## 8. For developers

### Server exports
```lua
local radio = exports['nayzeee-radio']

radio:getPlayerRadio(src)                       -- { model, power, slots, txSlot, muted, handsfree, callsign, ... } or nil
radio:setPlayerFrequency(src, slot, freq)       --> ok, reason   slot nil = TX slot; freq false = leave the slot
radio:setPlayerFrequency(src, slot, freq, true) -- force: skip the channel locks
radio:setPower(src, on)                         --> ok, reason ('noradio')
radio:isTalking(src)                            -- transmitting right now
radio:getChannelMembers(freq)                   -- { src, ... } with a switched-on radio tuned to freq in any slot

radio:addChannelRule(freq, rule)                --> ok, err   kept until removed or the radio restarts, never saved
radio:removeChannelRule(freq)                   --> ok
-- rule = { access = 'code' | 'job' | 'open', code = '1234', jobs = { police = 0 }, label = 'SWAT', requireDuty = true }
```

`setPlayerFrequency` reasons: `offline`, `noradio`, `invalid`, `denied`, `code`, `locked`,
`busy`. A frequency set on a radio that is off is checked again when it is switched on.
Rules from `addChannelRule` win over admin rules and the config ranges.

### Client exports
```lua
exports['nayzeee-radio']:isRadioOpen()              -- the radio is up
exports['nayzeee-radio']:isTalking()
exports['nayzeee-radio']:getFrequency(slot)         -- 155.5 | nil (slot nil = TX slot)
exports['nayzeee-radio']:setFrequency(freq, slot, cb) --> true | false, reason ('power' | 'invalid'); cb(reply) gets the server's answer
exports['nayzeee-radio']:raise()
exports['nayzeee-radio']:lower()
exports['nayzeee-radio']:getModel()                 -- 'handheld' | 'fieldpro' | 'military' | nil
exports['nayzeee-radio']:useRadio(data)             -- ox_inventory: client = { export = 'nayzeee-radio.useRadio' }
```

`useRadio` is only for item setups of your own. The install files do not need it: the
server already picks up the use of every item.

### Events
| Event | Side | Use |
|---|---|---|
| `ServerConfig.EmergencyHook(source, frequency, coords)` | server, `config_server.lua` | Runs on every emergency alert. Wire your dispatch script here |
| `nzr:alerts:emergency ({ talker, name, callsign, fkey, coords })` | client, listen only | Arrives on every client that receives the caller's frequency (muted radios and tuned cars too) |
| `nzr:radio:state (record)` | client, listen only | Your own radio record after every change the server makes |
| `nzr:rx:start (talker, info)` · `nzr:rx:stop (talker, q)` | client, listen only | Someone starts / stops being heard. `info = { fkey, slot, mode = 'radio' \| 'car' \| 'leak', q, name, callsign, emergency }` |

Every `nzr:*` event a client sends is checked by the server like any other player input
(sender, item, seat, distance, rate). Do not trigger them from other scripts: use the exports.

### State bags (read-only for other scripts)
```lua
Player(src).state.nzr_hold     -- { m = 'handheld'|'fieldpro'|'military', r = raised, t = talking } | nil
Player(src).state.nzr_job      -- { name, label, grade, gradeLabel, onDuty, isBoss }
Entity(veh).state.nzr_vradio   -- head unit: { on, f = '155.50' | nil, v = 0..1, mute, label }
GlobalState.nzr_labels         -- { ['155.50'] = { label, access = 'open'|'code'|'job' }, ranges = { { from, to, label, access } } }
GlobalState.nzr_jammers        -- { [id] = { t = type, x, y, z, h, o = owner server id, e = expiry (os.time) } }
GlobalState.nzr_vehicles       -- { models = { [hash] = { label, range, model } }, classes = { [n] = true } }
```

Codes are never in a state bag. Each file starts with a header that lists its API and
events. The `bridge/` folder is open: add or fix an adapter for any script there.

---

## 9. FAQ and troubleshooting

**The console says "WRONG FOLDER NAME" and the resource stops.**
Rename the folder to exactly `nayzeee-radio` and restart.

**The resource does not start ("ox_lib", "pma-voice" or "nayzeee-radio-props" not found).**
All three must be started before `nayzeee-radio` in server.cfg, and OneSync must be on.

**My framework is not detected (everyone is standalone).**
Start your framework before this resource, or force it: `Config.Framework = 'esx'` (or
`'qbcore'`, `'qbox'`). Set `Config.Bridge.debug = true` to see what was detected.

**Using the radio item does nothing, or the item shows as unknown.**
Add the items for your inventory (Step 4) and restart the inventory. On ox_inventory every
item must keep `consume = 0`. If you renamed an item in `config/items.lua`, rename it in the
install file you used and rename the picture too. Stop any other radio script that registers
the `radio` item.

**Item pictures are missing.**
ox_inventory loads them from this resource. Every other inventory needs
`html/img/items/*.png` copied into its picture folder (Step 4).

**The radio is invisible, or a toast says "The radio models are not loaded".**
Make sure `nayzeee-radio-props` is in your resources and started (`ensure
nayzeee-radio-props` before the script), and that its `stream/` folder holds the `.ydr` files
and `nzr_props.ytyp` (Step 1). Do not rename or remove files in it. Clear your client cache
after an update.

**Nobody hears me on the radio.**
- Both radios must be switched on, on the same frequency, and the other side must not be
  muted.
- Check the screen: NO CHANNEL means your TX slot is empty, NO SIGNAL means a jammer is too
  close.
- Too far apart? Try `/radiorange`, get higher, or use a radio car.
- pma-voice must be running and the player's voice chat on in the FiveM settings.
- Within 4 m (`Config.Audio.nearSkip`) you hear each other in person, not through the radio.
- Stop other radio scripts; they fight over pma-voice's voice target.

**pma-voice and the raised radio.**
While the radio is up the game renders a scripted camera, and pma-voice then listens around
the camera by default. The camera sits right at your face, so nothing changes in practice.
If you would rather turn that pma-voice behaviour off, add
`setr voice_disableAutomaticListenerOnCamera 1` to server.cfg.

**I cannot join a channel.**
RESTRICTED: your job or grade is not on the rule (or you are off duty with
`requireDuty`). ACCESS CODE: type the 4-digit code. TRY LATER: three wrong codes, wait 30 s.
OUT OF BAND: outside `Config.Channels.min` to `max`.

**The head unit does not open.**
The car must be a radio car (an emergency-class vehicle, a model in
`Config.Vehicles.models`, or one added in `/radioadmin` → Vehicles), you must sit in the
driver or front passenger seat (`Config.Vehicles.seats`), and `Config.Vehicles.enabled` must
be on. Outside a radio car, F10 raises your handheld, and only on foot.

**`/radioadmin` says I am not allowed.**
Add `add_ace group.admin nzr.admin allow` to server.cfg and make sure you are in
`group.admin` (`add_principal identifier.license:xxxx group.admin`), or have one of the
framework groups in `Config.Admin.groups`.

**I cannot place a jammer.**
Get out of the vehicle, aim at the ground within 3 m, on a dry spot that is not too steep and
not on a car or person. You can only run `Config.Jammers.maxPerPlayer` (1) at a time.

**Nobody can hack or pick up a jammer.**
"Pick up" is for its owner and `Config.Jammers.seizeJobs`; "Hack" for everyone else, or only
`Config.Jammers.hackJobs` when that is set. After a failed hack you wait
`Config.Jammers.failLockout` (20 s). Without a target script, walk up to it and look for the
**[E]** prompt.

**Jammers are gone after a restart.**
Placed jammers are not saved. When the resource stops, running jammers go back to their
owners if they are online.

**The database user may not create tables.**
Run `sql/install.sql` once.

**Memories and callsigns are lost without oxmysql.**
Create the folder `nayzeee-radio/data/` and make sure the server may write to it (Step 3).

**Typing on the radio's keypad switches my weapon.**
The keypad mappings only act while the radio is up, and the game's weapon keys are blocked
then. If another script uses the same keys, rebind the "Radio keypad" entries in
**Settings → Key Bindings → FiveM**.

**Performance.**
Nothing runs every frame unless you use the radio:

| Thread | Idle | Faster only when |
|---|---|---|
| Radios in other players' hands | wakes every 500 ms, sweeps once a second | someone near you has a radio up |
| Raised radio (camera, cursor, keys) | not running | every frame while your radio is up |
| Talking (voice, gunfire pick-up) | not running | every frame while you transmit |
| Receiving (volume, dropouts, speaker distance) | not running | every 100 ms while you hear someone, 50 ms on a weak link |
| Under-water check | not running | once a second while your radio is on |
| Radio screen (browser) | closed | while the radio is up; closed 2 min after the last use |
| Vehicles | nothing on foot (a 1 s check only without ox_lib's cache events) | every 500 ms while you sit in a vehicle |
| Jammer props and static | nothing while no jammer is out | a scan every 1-5 s by distance to the nearest one; every 250 ms inside its radius |
| Built-in [E] prompt (no target script) | every 1 s | every 250 ms near a jammer, every frame while the prompt shows |
| Server: radio items | every 5 s | only for radios that are on |
| Server: who hears whom | every 250 ms, nothing to do | every `Config.Signal.refresh` (1 s) while anyone talks |
| Server: roster | every 5 s | only for players watching it |

**Still stuck?** Turn on `Config.Debug = true` and `Config.Bridge.debug = true`, restart, and
bring the console output to [discord.gg/nayzeeedev](https://discord.gg/nayzeeedev).
