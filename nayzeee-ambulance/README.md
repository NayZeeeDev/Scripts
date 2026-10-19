```
███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗
████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝
██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗
██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝
██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗
╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝
 █████╗ ███╗   ███╗██████╗ ██╗   ██╗██╗      █████╗ ███╗   ██╗ ██████╗███████╗
██╔══██╗████╗ ████║██╔══██╗██║   ██║██║     ██╔══██╗████╗  ██║██╔════╝██╔════╝
███████║██╔████╔██║██████╔╝██║   ██║██║     ███████║██╔██╗ ██║██║     █████╗
██╔══██║██║╚██╔╝██║██╔══██╗██║   ██║██║     ██╔══██║██║╚██╗██║██║     ██╔══╝
██║  ██║██║ ╚═╝ ██║██████╔╝╚██████╔╝███████╗██║  ██║██║ ╚████║╚██████╗███████╗
╚═╝  ╚═╝╚═╝     ╚═╝╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝
```

# NAYZEEE Ambulance

**Version 1.0.0** · Support: [discord.gg/nayzeeedev](https://discord.gg/nayzeeedev)

A complete EMS job for FiveM. Real injuries instead of a health bar, field care and hospital
procedures you actually perform, hospitals you build in game, dispatch, NPC 911 calls with
recorded voices, billing and insurance. One resource, every framework.

- **ESX · QBCore · Qbox · ox_core · Standalone**, detected by itself.
- **10 inventories, 5 target scripts (or none), 10 phones, 8 dispatch scripts**, all optional.
- **Server-authoritative.** The server owns every injury, vital sign, item and dollar.
- **Easy mode** per department: every minigame can become a short timed action.

---

## Contents

1. [Features](#1-features)
2. [Requirements](#2-requirements)
3. [Installation](#3-installation)
4. [Configuration](#4-configuration)
5. [Easy mode (Simple care)](#5-easy-mode-simple-care)
6. [Hospital builder: quick start](#6-hospital-builder-quick-start)
7. [Commands and keys](#7-commands-and-keys)
8. [For developers](#8-for-developers)
9. [FAQ and troubleshooting](#9-faq-and-troubleshooting)

---

## 1. Features

### Injuries and physiology
- **15 body regions** and **9 injury types** (gunshot, shrapnel, stab, laceration, abrasion,
  contusion, fracture, burn, internal). Every wound has a severity, a bleed rate in mL/min, pain,
  contamination and its own details: wound length and depth, retained bullets and fragments,
  fracture kind and angle, burn degree and area, the organ that bleeds inside.
- **Damage turns into injuries**: weapons, melee, falls (height), vehicle crashes (seat belt
  aware), fire, drowning. Headshots can stop the heart.
- **Blood volume, not hit points.** Blood loss drives heart rate, blood pressure, SpO2,
  breathing, temperature and consciousness (AVPU). Saline, blood units and TXA change it.
- **Conditions**: haemothorax, tension pneumothorax, cardiac tamponade, concussion, hypoxia,
  airway obstruction, overdose, cardiac arrest, hypothermia, infection, spinal injury.
- **Eight heart rhythms** (sinus, sinus tachy / brady, AF, VF, VT, PEA, asystole) on every monitor.
- Injuries, conditions and death **survive relog and restart**.

### Being the patient
- Downed stage with a pose and **crawl**, a **bleed-out clock** that runs with your real bleed
  rate and pauses once you are stabilised.
- **Call EMS** with one key (G), **give up** after a minimum time, cardiac arrest, death screen,
  **respawn at the nearest hospital** recovery point (fee, insurance, optional item loss).
- Screen effects that match your state: limp, shaking, blur, tunnel vision, cold, breathlessness.

### Field care
- **Head-to-toe check** with a holographic body map and a findings stack. Hidden problems show
  up as you find them.
- **Pulse check**, **breathing check** with a stethoscope and synthesised breath sounds.
- **Bleed control** (pressure, packing, dressing), **tourniquet** (time written on the strap),
  **cervical collar**, **oxygen mask**, **foil blanket**, medication with doses.
- **Recovery position**: an unconscious patient on their back snores and loses oxygen; roll them on
  their side to keep the airway open (log-rolled with the head in line when a spinal injury or
  collar is present).
- **Field resuscitation** from the trauma kit: pelvic binder, IO drill, IV access, fluids,
  pressure infuser, TXA. The **patient monitor** works on its own and inside other procedures.
- **CPR & defibrillator**: compressions to a metronome, rescue breaths, an unbranded monitor /
  defibrillator (pads, analysis, charge, shock), adrenaline, two-rescuer codes, ROSC and a debrief.
- **Airway**: bag-valve mask, suction and video-laryngoscope intubation.
- **Splints**, **crutches** and a drivable, pushable **wheelchair**.
- **Medical bag** you set down on scene (it keeps its contents), **body bag** and **morgue**.

### Transport
- **Carry**, **help up**, **stretchers** (push, raise and lower, load into the ambulance).
- A walk-in **ambulance treatment bay** with its own HUD and supply shelves.
- Hospital **beds and tables**: lie a patient on any bed, X-ray table or treatment couch.

### Hospital procedures
- **Wound closure (suture)** in a full-screen 3D close-up.
- **Bullet and fragment removal** on the operating table or in the treatment bay: locate (probe or
  X-ray film), disinfect, incise, expose, extract, control the bleeding, close and dress. The
  patient keeps losing blood while the wound is open.
- **Burn care and skin graft**: cool, test the depth, debride, excise, harvest, mesh, staple, dress.
- **X-ray**: AP and lateral films built from the patient's real injuries, read on a lightbox,
  **set displaced bones** under live fluoroscopy, **apply a cast**.
- **Ultrasound (eFAST)**, **chest drain**, **needle decompression**, **pericardiocentesis**.
- **Angiography**: steer a catheter through the vessels, find the internal bleed with contrast
  and seal it with a coil, on the in-world monitor.
- **Blood service**: donation chair, blood bank, labelled blood units with group and expiry,
  IV stand, transfusion. The wrong group causes a reaction.

### Hospitals and departments
- **Hospitals are built in game** with `/nzadmin`. No coordinates in config files.
- **Departments** with ranks, salaries, permissions per rank, uniforms, vehicles and a map pin.
- Sites: shift clock, uniform locker, staff store, command desk, supply cabinet, vehicle bay,
  helipad, lift stops, ward beds, recovery points, reception desk, waiting area board, pharmacy,
  blood bank, blood donation chair, operating table, X-ray table, lightbox, ultrasound cart,
  angiography suite, morgue, stretcher bay.
- **Check-in desk** with an NPC receptionist, queue numbers, a live waiting area board, staff
  calls to free beds and an **AI doctor** when nobody is on duty. New patients reach on-duty
  staff as a toast and a pager line; "Call next" also works from the ops board.
- **Pharmacy** counter, **health insurance** plans with a card, **billing** (insurance share,
  unpaid bills paid later, society money and a medic cut, external invoice scripts).

### Dispatch and calls
- Incoming-call card, an **RX-10 pager**, unit statuses, the **ops board**, `/911`, callsigns,
  phone integration and the **EMS radial menu** (F6).
- **NPC 911 calls**: 11 data-driven scenarios (overdose, car crash, fall, gunshot, stabbing,
  drowning, burn, cardiac arrest, elderly fall, assault, crush) with real NPC patients you treat
  with the full toolset, **recorded caller voices**, scene props, fire and smoke, hand-over
  rewards.
- An **AI ambulance** answers downed players while no medic is on duty.

---

## 2. Requirements

| | |
|---|---|
| **FiveM server** | OneSync enabled (`set onesync on`) |
| **[ox_lib](https://github.com/overextended/ox_lib)** | required |
| **[oxmysql](https://github.com/overextended/oxmysql)** | required, with a MySQL or MariaDB database |
| **Framework** | ESX, QBCore, Qbox, ox_core, or none (standalone) |
| **Inventory** | ox_inventory, qb-inventory, ps-inventory, lj-inventory, qs-inventory, codem-inventory, tgiann-inventory, origen_inventory, core_inventory or the ESX default inventory |
| **Target** (optional) | ox_target, qb-target, qtarget, interact, sleepless_interact. Without one, a built-in **[E]** prompt is used |

Everything else is optional and detected automatically: notifications, phones (lb-phone,
qs-smartphone, qs-smartphone-pro, npwd, yseries, gksphone, okokPhone, roadphone, high-phone,
renewed-phone, qb-phone), external dispatch (cd_dispatch, ps-dispatch, qs-dispatch, rcore_dispatch,
core_dispatch, tk_dispatch, origen_police, lb-tablet), vehicle keys, fuel, clothing and
society banking.

---

## 3. Installation

### Step 1 · Put the resource in place
1. Extract the download into your `resources` folder.
2. The folder **must be named exactly `nayzeee-ambulance`**. Any other name stops the resource
   with a red message in the console, because exports, events, the NUI and the streamed props
   all use that name.

### Step 2 · server.cfg
Start it **after** ox_lib, oxmysql, your framework, your inventory and your target script:

```cfg
ensure ox_lib
ensure oxmysql
ensure es_extended        # or qb-core / qbx_core (leave out for standalone)
ensure ox_inventory       # your inventory
ensure ox_target          # your target script (optional)

ensure nayzeee-ambulance

# admins: hospital builder, /revive, /heal, NPC call tools
add_ace group.admin nza.admin allow
# add_principal identifier.license:xxxx group.admin   (if you are not in group.admin yet)
```

### Step 3 · Database
Nothing to do: every table is created on the first start. If your database user is not allowed
to create tables, run `sql/install.sql` once (16 tables, safe to run again).

### Step 4 · Items
The resource uses 48 items. `install/` holds them for every inventory and `html/img/items/`
has a picture for each one. Pick your inventory:

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
| **ESX default inventory** | Run `install/esx_items.sql`. Weights are in kg; for gram-based servers regenerate it with `lua5.4 install/generate.lua --esx-grams`. |

Restart the server after adding items. More detail, item renaming and picture order:
`install/README.md`.

### Step 5 · Framework
| Framework | Setup |
|---|---|
| **ESX** | Medic jobs are `Config.Jobs.medic` (`ambulance`, `ems`). Duty uses `job.onDuty`; older servers with an `offambulance` job work too (`Config.Bridge.offDutyPrefix`). Society money goes to `esx_addonaccount` (or okokBanking / fd_banking). |
| **QBCore** | Same jobs. Duty is the QBCore duty. Society money uses Renewed-Banking, okokBanking, fd_banking, qb-banking or qb-management (detected). |
| **Qbox** | Detected before QBCore. Same as QBCore, society through qbx_management or a banking script. |
| **ox_core** | Detected after Qbox. Medic jobs are ox_core groups with the names in `Config.Jobs.medic` (group grade = job grade). Characters log in on duty (`Config.Bridge.oxOnDuty = true`); duty is toggled at the hospital duty point. Society money uses the group's ox_core account. ox_core pays no salaries, so hospital paychecks follow `Config.Hospital.paycheck`. |
| **Standalone** | Medics are players with an ace: `add_ace identifier.license:xxxx nza.medic allow` (optional grade `nza.medic.3`, boss `nza.medic.boss`). Police: `nza.police`. Use ox_inventory for items. Without any inventory, `Config.Bridge.standaloneFreeItems = true` makes every medical item count as present (test servers). |

You can force any integration in `config/modules/bridge.lua` (`framework`, `inventory`,
`target`, `notify`, `phone`, `dispatch`, `keys`, `fuel`, `clothing`, `society`).

### Step 6 · Remove your old ambulance script
Stop `esx_ambulancejob`, `qb-ambulancejob`, `wasabi_ambulance` or any other death / EMS script.
Two scripts fighting over death and revive will break both. Common revive events and death
exports keep working for your other scripts (see [For developers](#8-for-developers)).

### Step 7 · Start and build
Restart the server, join as an admin and type `/nzadmin` to build your first hospital
([quick start](#6-hospital-builder-quick-start)). Until a department exists, medics get their
permissions from `Config.DefaultPerms` by job grade.

---

## 4. Configuration

Every config file is open (not escrowed) and every option has a short comment.

### Core files
| File | What you set there |
|---|---|
| `config/config.lua` | Debug, language, framework, **medic and police jobs**, duty rule, public / police / default permissions per grade, admin ace and groups, **command names**, UI (font, window shape, scale, sounds), **damage → injuries** (weapon groups, single weapons, falls, crashes, fire, drowning), **physiology** (blood volume, arrest and death thresholds, healing, infection, hypothermia), **wounded stage** (knock-down threshold, clock, crawl, give up, call EMS), **death & respawn** (timers, fee, item and cash loss), **easy mode** default, **persistence**, **billing** defaults |
| `config/items.lua` | `Config.Items`: the item name your inventory uses for each key (rename here, never the key). `Config.ItemDefs`: label, weight, description, category, image, used to build the install files |
| `config/props.lua` | `Config.Props`: every streamed prop model (swap for your own), `Config.PropScreens` (texture slots for screens), `Config.PropFallbacks` (native models used when a custom prop fails) |
| `config/modules/bridge.lua` | Which framework / inventory / target / notify / phone / dispatch / keys / fuel / clothing / society script to use (`'auto'` by default), external dispatch, standalone aces, phone 911 numbers, built-in target key |

### Feature files (`config/modules/`)
| File | Feature |
|---|---|
| `wounded.lua` | Downed HUD, screen effects, poses, crawl, death camera, fallback respawn spots |
| `assess.lua` | Patient menu, head-to-toe check, pulse and breathing checks, help them walk |
| `firstaid.lua` | First aid items, bleed control, tourniquet, collar, oxygen, foil blanket, medication |
| `field.lua` | Field resuscitation steps, IO / IV, fluids, TXA, the patient monitor |
| `cpr.lua` | CPR, defibrillator, team size, ROSC chances, keys, billing |
| `intubation.lua` | BVM, suction, intubation difficulty and outcomes |
| `splint.lua` | Splints, crutches (key / command), wheelchair |
| `suture.lua` | Wound closure procedure and its supplies |
| `bullet.lua` | Bullet / fragment removal: supplies, where it may be done (operating table, treatment bay), blood loss, the operating table props |
| `burn.lua` | Burn care and skin graft |
| `xray.lua` | X-ray table, films, lightbox reading, setting bones, casts |
| `ultrasound.lua` | eFAST scan, chest drain, needle decompression, pericardiocentesis |
| `angio.lua` | Angiography suite, catheter, contrast, coils |
| `blood.lua` | Blood units, bank, donation, IV stand, transfusion reactions |
| `transport.lua` | Carry, help up, stretchers, vehicles that carry one, beds and tables, the treatment bay |
| `medbag.lua` | Medical bag, body bag, morgue rewards |
| `hospital.lua` | Defaults for new departments, site placement controls, duty, paychecks, supply cabinet, garages, beds, blips |
| `checkin.lua` | Check-in desk, queue numbers, waiting area board, AI doctor, bed rest |
| `pharmacy.lua` | Pharmacy catalogue and stock, insurance plans, **billing options** (insurance share, unpaid bills, external invoice scripts, auto collect), medic bills, admin commands |
| `dispatch.lua` | Calls, statuses, call card keys, pager, ops board, radial menu, `/911`, `/callsign`, blips |
| `calls.lua` | NPC 911 calls (frequency, scenarios, locations, voices, rewards) and the **AI medic** |

### Language
Every text is in `locales/en/*.lua`. To translate: copy `locales/en` to `locales/de` (for
example), change `NZA.AddLocale('en'` to `NZA.AddLocale('de'` at the top of each file, translate
the values and set `Config.Locale = 'de'`. Missing keys fall back to English.

---

## 5. Easy mode (Simple care)

Not every server wants minigames. With easy mode a medic performs a procedure as a short timed
action (ox_lib progress bar or circle) instead of the minigame.

- **Default** for medics without a department and for new departments:
  `Config.EasyMode.default` in `config/config.lua` (`style = 'bar' | 'circle'`).
- **Per department**: `/nzadmin` → your department → **Profile** → **Simple care**. Switch it on
  for the whole department or **choose per permission** (for example easy X-ray, real suture).
- An easy action scores `Config.EasyMode.score` (78 by default).
- The supplies of the treatment are still needed, but no X-ray, operating table, blood unit or
  special room (for example the X-ray table and lightbox, or the ultrasound cart).
- The server still checks a minimum time for every procedure, so nothing can be skipped.

---

## 6. Hospital builder: quick start

You need the `nza.admin` ace (Step 2). Department bosses (rank permission `manage`) get the
same console from their **Command Desk**, limited to their own department.

1. **Open the console**: `/nzadmin`.
2. **Register a department**: give it a name and a short code. The internal name is fixed
   once registered.
3. **Profile**
   - Link the framework job (for example `ambulance`) so its members join automatically.
   - Stand at the main entrance and press **Set base point**. The map pin appears there.
   - Pick the pin colour, icon and size.
4. **Ranks**: build the rank ladder, set the pay and tick the permissions per rank (`All`,
   `None`, `Same as the rank below`).
5. **Uniforms**: dress your character, then **Save** it to the male or female side.
6. **Sites**: open a zone and click **Set a new site**. You enter site survey mode:
   - aim at the floor or a counter; the marker is teal when the spot is clear;
   - **E** set here · **← / →** turn · **mouse wheel** nudge · **Page Up / Page Down** lift ·
     **Shift** coarse · **Alt** fine · **G** lock the angle · **Backspace / Esc** back out.

   | Zone | Sites |
   |---|---|
   | Staff base | Shift Clock, Uniform Locker, Staff Store, Command Desk, Supply Cabinet |
   | Front desk | Reception desk, Waiting area board |
   | Wards | Ward Bed, Recovery Point (where the dead wake up) |
   | Dispensary | Pharmacy |
   | Blood service | Blood bank, Blood donation chair |
   | Theatre | Operating table |
   | Imaging | X-ray table, Lightbox |
   | Sonography | Ultrasound cart |
   | Cath lab | Angiography suite |
   | Lifts | Lift Stop (same group = linked floors) |
   | Mortuary | Morgue |
   | Other | Stretcher bay |

7. **Fleet**: add the vehicles each rank may take, then place a **Vehicle Bay** and a
   **Helipad**.
8. **Save** your department changes (Save or Ctrl + S). Sites are stored the moment you set
   them and appear for every player at once.

Tip: place at least one **Recovery Point** per hospital. Until one exists, respawns use the
fallback spots in `config/modules/wounded.lua`.

---

## 7. Commands and keys

### Admin (ace `nza.admin`, or a framework group in `Config.Admin.groups`)
| Command | What it does |
|---|---|
| `/nzadmin` | Department Console and hospital builder |
| `/revive [id]` | Revive (yourself without an id) |
| `/heal [id]` | Remove injuries, keep standing (yourself without an id) |
| `/injure [id] [region] [type] [severity]` | Add an injury (testing) |
| `/nzacall [type] [here]` | Create an NPC call (`here` = next to you) |
| `/nzacallclear` · `/nzacalls` | Remove every NPC scene · list open scenes |
| `/nzainsurance [id] [plan\|none] [days]` | Set a player's insurance |
| `/nzabills [id]` | List or clear a player's open bills |

`/kill [id]` is off by default (`Config.Commands.kill`). Every command name can be changed or
turned off in `config/config.lua` and the module configs.

### Players and medics
| Key / command | What it does |
|---|---|
| **G** | Call EMS while downed |
| hold **E** | Give up (after the minimum time) · respawn on the death screen |
| **F6** · `/emsmenu` | EMS radial menu (duty, dispatch, patient, stretcher, bag, NPC calls) |
| **F7** · `/pager` | Show or hide the pager |
| **E** · **X** | Respond to · dismiss the incoming call |
| `/dispatch` | Ops board (no default key) |
| `/911 <what happened>` | Call EMS from chat |
| `/callsign <name>` | Set your unit callsign |
| `/nzainteract` | Patient menu without a target script (key `nza_interact`, unbound) |
| `/crutches` | Use or put away crutches (key unbound) |
| `/nzamonitor` | Take the mouse on the patient monitor |
| **Backspace** · **F1–F4** | Treatment bay: leave · check · supplies · IV stand · monitor |
| **X** | Stand up from the blood donation chair while waiting |

Every key is a FiveM key mapping: players can rebind them in **Settings → Key Bindings → FiveM**.

---

## 8. For developers

### Server exports
```lua
local amb = exports['nayzeee-ambulance']

amb:GetPatient(src)                    -- full patient snapshot (injuries, vitals, devices) or nil
amb:GetPatientByPid(pid)               -- same, by pid ('p:<identifier>' or 'n:<netId>')
amb:IsDowned(src)                      -- wounded, arrest or dead
amb:IsDead(src)                        -- arrest or dead
amb:GetState(src)                      -- 'alive' | 'wounded' | 'arrest' | 'dead'
amb:Revive(src, full)                  -- full = true also heals every injury
amb:Heal(src)
amb:AddInjury(src, region, type, severity)          --> injury id
amb:GetVitals(src)   amb:GetInjuries(src)   amb:GetTriage(src)
amb:CreateNPCPatient(opts)             --> pid
amb:SetPatientMeta(pid, key, value)

amb:CallEMS(src, message, coords)      --> ok, callId   (phones, dispatch, other scripts)
amb:RequestAIMedic(pidOrSrc, opts)     amb:CancelAIMedic(pidOrSrc)

amb:Charge(target, amount, reason, opts)            -- insurance, unpaid bills, society, medic cut
amb:GetInsurance(identifier)   amb:SetInsurance(identifier, plan, days)
amb:GetBills(identifier, status)   amb:PayBills(src, method)

amb:GetBloodStock(bankKey)   amb:CreateBloodBag(meta)   amb:BloodCompatible(recipient, donor)
amb:IsInCpr(pidOrSrc)   amb:GetCode(pidOrSrc)
amb:IsIntubated(srcOrPid)   amb:VentilatePatient(srcOrPid, seconds)
amb:GetTransportState(src)   amb:GetCheckinQueue(hospital)
amb:GetMedbagContents(bagId)   amb:GetBodyBags()
amb:AddFinding(pid, key, data)   amb:GetFindings(pid)
```

### Client exports
```lua
exports['nayzeee-ambulance']:isDead()        -- also IsDead, isPlayerDead, GetDeathStatus (arrest or dead)
exports['nayzeee-ambulance']:isDowned()      -- also isPlayerDowned (anything but alive)
exports['nayzeee-ambulance']:isInLastStand() -- wounded
exports['nayzeee-ambulance']:GetState()      -- 'alive' | 'wounded' | 'arrest' | 'dead'
exports['nayzeee-ambulance']:GetSelfSnapshot()
exports['nayzeee-ambulance']:OpenPharmacy(pointId, tab)
exports['nayzeee-ambulance']:ClosePharmacy()
exports['nayzeee-ambulance']:SendBill(serverId)
```

### Events
| Event | Side | Use |
|---|---|---|
| `nza:callEMS (src, message, coords?)` | server-local `TriggerEvent` | Create an EMS call from another server script |
| `hospital:server:RevivePlayer` | server | QBCore-style revive (admin, or on-duty medic within 10 m) |
| `esx_ambulancejob:revive` | server | ESX-style revive (admin only) |
| `esx_ambulancejob:heal` · `wasabi_ambulance:revive` · `wasabi_ambulance:revivePlayer` | server | Heal / revive for scripts written for those resources |
| `esx:onPlayerDeath` / `esx:onPlayerSpawn` | client (local) | Fired for ESX scripts when you go down / are revived |

Revives from other scripts' client events are ignored on purpose: a revive always comes from
the server.

### State bags (read-only for other scripts)
```lua
Player(src).state.nza       -- { st = 'alive'|'wounded'|'arrest'|'dead', avpu, bleed = 0..3, stab, clock, inj, tri, ... }
Player(src).state.nzaJob    -- { name, label, grade, gradeLabel, onDuty, isBoss, medic, police }
LocalPlayer.state.isDead    -- also dead, inLastStand, laststand, isDowned (for HUDs)
```

Developer documentation: `docs/ARCHITECTURE.md` (contracts), `docs/modules/core-api.md` (the
core API) and `docs/modules/<module>.md` for each feature. The `bridge/` folder is open: add or
fix an adapter for any script there.

---

## 9. FAQ and troubleshooting

**The console says "WRONG FOLDER NAME" and the resource stops.**
Rename the folder to exactly `nayzeee-ambulance` and restart.

**"ox_lib" or "oxmysql" not found / the resource does not start.**
Both must be started before `nayzeee-ambulance` in server.cfg, and OneSync must be on.

**My framework is not detected (everyone is standalone).**
Start your framework before this resource, or force it: `Config.Framework = 'esx'` (or
`'qbcore'`, `'qbox'`). Set `Config.Bridge.debug = true` to see what was detected.

**Items do nothing or show as unknown.**
Add the items for your inventory (Step 4) and restart the inventory. On ox_inventory every item
must keep `consume = 0`. If you renamed an item in `config/items.lua`, regenerate the install
files with `lua5.4 install/generate.lua` and rename the picture too.

**Item pictures are missing.**
ox_inventory loads them from this resource. Every other inventory needs
`html/img/items/*.png` copied into its picture folder (Step 4).

**Medics have no options on patients.**
- Check the job name is in `Config.Jobs.medic`.
- With `Config.Jobs.requireDuty = true` the medic must be on duty (shift clock site, the F6
  radial, or your framework's duty).
- Check the medic's rank has the permission (`/nzadmin` → Ranks), or `Config.DefaultPerms`
  before any department exists.
- No target script running? Look for the built-in **[E]** prompt or use `/nzainteract`.

**Where do medics get trauma kits, intubation kits, surgical kits and other supplies?**
From the **Supply Cabinet** site (Staff base zone): on-duty staff take them for free, limited
per shift, and some only with the matching rank permission. Change the list in
`config/modules/hospital.lua` → `storage.items`. The ambulance treatment bay has its own supply
shelves (`config/modules/transport.lua` → `Bay.supplies`).

**The database user may not create tables.**
Run `sql/install.sql` once.

**Props are invisible or fall back to plain GTA models.**
Do not rename or remove files in `stream/`. Clear your client cache after an update. The
fallback models in `Config.PropFallbacks` are used when a custom model cannot load.

**No NPC calls come in.**
NPC calls need at least `Config.Calls.generation.minMedics` medics on duty who take NPC calls
(F6 → Dispatch → NPC calls), and the first call comes 45–120 s after that
(`Config.Calls.generation.firstDelay`). Admins can test with `/nzacall`.

**Players respawn at the wrong place.**
Place a **Recovery Point** in each hospital (`/nzadmin` → Sites → Wards). Until then the
fallback spots in `config/modules/wounded.lua` are used.

**My HUD / inventory still thinks the player is alive while downed.**
Point it at `exports['nayzeee-ambulance']:isDead()` / `isDowned()`, or read
`LocalPlayer.state.isDead`.

**Money does not reach the society.**
Check `Config.Billing.society` (default `ambulance`) and that your banking script is started
(`Config.Bridge.society`). Insurance and unpaid-bill options are in
`config/modules/pharmacy.lua` → `billing`.

**Still stuck?** Turn on `Config.Debug = true` and `Config.Bridge.debug = true`, restart, and bring
the console output to [discord.gg/nayzeeedev](https://discord.gg/nayzeeedev).
