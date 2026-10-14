# Module: transport

Carry, help up, stretchers (push, raise / lower, load into the ambulance), hospital beds &
tables, and the walk-in **ambulance treatment bay** with its HUD and supplies shelves.

## Files

| File | What it does |
|---|---|
| `config/modules/transport.lua` | `Config.Transport` (carry, help up, stretcher, vehicles, beds, bay, supplies, billing) |
| `locales/en/transport.lua` | strings `transport.*` (the bay HUD gets `NZA.LocaleTable('transport')`) |
| `server/modules/transport.lua` | carry, help up, out of a vehicle, stretcher records (take / register / push / height / swap / place / off / load / unload / store), beds & tables, cleanup watchdog, `transport:*` bus events |
| `server/modules/transport_bay.lua` | bay slots, enter / exit, patient in / out, supplies (per-shift limits), watchdog (vehicle deleted, medic down / offline) |
| `client/modules/transport.lua` | shared helpers, the patient-side positioning (`Tr.Apply`) driven by the `nzaTr` state bag, NPC scanner, patient options, patient radial items, help up |
| `client/modules/transport_carry.lua` | fireman carry (carrier loop, context: stretcher / bed / vehicle seat) |
| `client/modules/transport_stretcher.lua` | stretcher: take, push, raise / lower (+ optional low-model swap), load / unload slide, return, targets on the cot and the ambulance, the `stretcher` hospital point type, stretcher radial items |
| `client/modules/transport_bed.lua` | bed-like hospital points: transfer from stretcher / carry, help off the table |
| `client/modules/transport_bay.lua` | treatment bay: local interior + lights + dressing props, enter / exit (also from a passenger seat), patient in / out, HUD, supplies, key mappings, ambulance target, bay radial items |
| `html/apps/bay/app.js`, `app.css` | NUI app `bay`: top vitals strip with exit pill, patient card, warnings, crew, tool keys, big monitor, supplies window |

## Features

### Carry
- Patient option **Carry** (order 10) on downed players and NPC patients (states from
  `Carry.states`; `alive` off by default). The medic bends down (`Carry.pickup`), then lifts the
  patient over the shoulder: synced anims (`missfinale_c2mcs_1` / `nm firemans_carry`), the
  patient is attached to the carrier (`Carry.attach`). A player patient's own client attaches
  itself; an NPC is attached by the carrier (network control is requested first).
- While carrying: walk only (`Carry.maxSpeed`), no weapons, no vehicles. Prompts: **[G] Put down**
  and a context **[E]**: *Place on the stretcher* (free cot within 2.6 m), *Place on the &lt;bed&gt;*
  (bed-like point within `Beds.range`), *Put in the vehicle* (any car with a free rear / front
  passenger seat from `Carry.seats`). **Take out of the vehicle** is a patient option + radial item.
- The carry ends when the carrier goes down / leaves / gets too far, when the patient wakes up
  (`alive` → put down on their feet) or leaves. Server watchdog every 1.5 s.

### Help up
- **Help up** (order 11) on a *wounded* patient who is stabilised and fully awake (state bag
  `stab` + `avpu = 'A'`); the server re-checks `NZA.Patients.CanStand` and sets `alive`
  (`nza:revived` for players, a get-up anim for NPCs). Errors say why (still bleeding, not awake,
  blood loss, chest).

### Stretcher (`Config.Props.stretcher`, fallback `Config.PropFallbacks.stretcher`)
- **Take stretcher** at the back doors of a configured ambulance (`Stretcher.vehicles`, target
  on the model, also the radial). The doors open, the cot rolls out foot-first and swings round
  behind the ambulance, and you start pushing it. One cot out per ambulance (`maxPerVehicle`).
  Also from a hospital **Stretcher bay** point (`stretcher` type, placed with the builder).
- **Push**: the cot is attached in front of you (`push.pos`, foot-end handle in the hands) with the
  push pose (`push.anim`), walk speed (`push.maxSpeed`, `lowSpeed` while lowered). The medic first
  steps up to the handle. **[G] Let go** (the cot is put on the ground and frozen), **[H] Raise /
  Lower** (lever anim; the state is shown in the prompt; when `Config.Props.stretcher_low` exists the
  cot entity is swapped for the folded model), **[E]** context: *Load into the ambulance* (patient
  on it, at the back doors), *Return the stretcher* (empty, at an ambulance or a stretcher bay),
  *Transfer to the &lt;bed&gt;*.
- **Place on Stretcher** (patient option, order 12, needs a free cot within `findRange` m) / **Put
  the patient on it** (cot target) / from a carry (prompt). The patient lies on the mattress
  (`patient.pos/rot/anim`), attached to the cot. **Take off the stretcher** lays them beside it.
- **Load**: the cot rolls in through the doors (keyframed slide, `load.slideMs`) to the per-model
  spot (`vehicles.<model>.pos/rot`), legs fold (`load.autoLower`), doors close. With a patient on
  it the server emits bus **`transport:loaded (src, p, vehNet, strNet)`** (dispatch → TRN) and sets
  `meta.vehicle`. **Unload** (ambulance target / radial) rolls it out and you push it again.
- **Return**: an empty cot at an ambulance (any configured one) or at a stretcher bay is put away.
  Empty cots nobody touched for `abandon` s are removed; cots whose ambulance was deleted too.

### Beds & tables
- Any hospital point whose type is in `Beds.types` (`bed surgery xray angio ultrasound donation`)
  or whose data / type data has `bed = true` is bed-like. From a stretcher (prompt, cot target
  *Move the patient to the bed*, patient option *Move the patient to the bed*) or from a carry, the
  patient is laid at the point coords (+ type nudge, or `point.data.lie = { x, y, z }`), frozen with
  the lying anim (`donation` sits). The server sets **`patient.meta.bed = { point, type, hospital }`**
  (procedures read it), `meta.inBed` for `heal` types, and reserves the point with
  `NZA.Hospitals.OccupyBed` (released on every move). Emits `transport:bed (src, p, point)`.
- **Help patient off the table** (order 13; the X-ray module hands its own option over through
  `NZA.Transport.OwnsHelpOff / HelpOff`) — needs a patient who can stand; they get up beside it.
  An *alive* player on a bed can also hold **[X] Get up** (`Beds.selfLeave`). Carrying / placing
  the patient on a stretcher from a bed also clears the bed.
- Optional transport fee (`Billing`): charged once to a player patient who came by ambulance when
  they are placed on a hospital point.

### Ambulance treatment bay
- **Enter treatment bay** at the back doors (target on the ambulance model / radial) while it stands
  still, or from a **passenger seat** at any speed (radial, not the driver). Fade → the interior
  model (`Config.Props.bay_shell`) is spawned **locally** at the ambulance's slot on a hidden grid
  under Mount Chiliad (`Bay.base + slot offset`, `columns`, `spacing`, `maxSlots`), lit every frame
  with `DrawLightWithRange` (`Bay.lights`), dressed with local props (`Bay.props`: monitor on the
  shelf, sharps bin, kit case) and a local cot at `Bay.stretcher`. Medics appear at `Bay.medics`
  spots; collision is waited for; the minimap is hidden (`hideRadar`). If the interior model is
  missing a native block (`fallbackFloor`) is used so nobody falls.
- The patient on the loaded stretcher comes along with the first medic: `patient.meta.bay = vehNet`
  for the patient AND every medic inside (core view rules + procedures). Player patients move
  themselves (their client spawns the interior too); NPCs are moved by the medic.
- Several medics can be inside (crew list on the HUD). When the last one leaves, the patient goes
  back onto the stretcher in the ambulance. Leaving puts you behind the ambulance's **current** back
  doors (the client lines up with the doors once the vehicle streamed in), or back into a free
  passenger seat when it is still driving. Leaving is blocked while a procedure runs.
- Vehicle deleted → everyone is kicked out where it last was and the patient is laid down there.
  A medic who goes down inside is put outside. Disconnects are cleaned up.
- **HUD** (`bay` app, no focus): top strip with the ECG + pleth sweep, drip rate, rhythm, the
  **BACKSPACE Exit treatment bay** pill, unit / plate / moving speed, and HR · SpO₂ · NIBP + MAP ·
  RR · Temp · Blood loss tiles (alarm colours). Patient card (triage, bleeding-out flip clock /
  stabilised / arrest + rhythm, bleed + blood meters, injuries with severity pips and status, lines
  with bag fill and rate, devices). Warnings (glowing notes): *Surgery costs the patient blood — hang
  a unit first* (retained fragments / internal bleeding and no blood running), active bleeding,
  no IV access, cardiac arrest, hypothermia, ambulance moving. Crew card. Tool keys:
  **F1 Examine** (assess module), **F2 Supplies**, **F3 IV stand** (blood module through the bus),
  **F4 Monitor** (other module through the bus, otherwise the built-in big NAYZEEE monitor).
  While any other procedure app is open the HUD collapses to the top strip.
- **Supplies shelves** (F2, radial, or the target on the cabinets): v5 window with categories, item
  cards (image, left this shift with a segmented meter, in your pockets, quantity stepper, Take /
  Take all). Free items with per-medic limits (`supplies.items[].max`) that reset when the medic
  goes on duty or after `shiftLength` s. Server checks the bay, limit, `maxPerTake`, inventory space.

## Controls

| Where | Key (default) | Action |
|---|---|---|
| carrying | G / E | put down / context (stretcher, bed, vehicle seat) |
| pushing | G / H / E | let go / raise-lower / context (load, return, transfer to bed) |
| on a bed (alive) | hold X | get up |
| bay (key mappings, rebindable) | Backspace / F1 / F2 / F3 / F4 | exit / examine / supplies / IV stand / monitor |
| supplies window | Esc or F2, + / − | close, quantity of the first item |

## Config keys (`Config.Transport`)

`perm radial radialRange` ·
`Carry { enabled perm states distance maxSpeed carrier carried attach pickup keys{drop,context} seats seatRange dropAhead }` ·
`HelpUp { enabled perm distance anim npcGetUp }` ·
`Stretcher { enabled model lowModel distance findRange maxPerVehicle abandon push{bone pos rot anim maxSpeed lowSpeed grabMs} patient{pos rot lowZ anim} lever keys{release context height} load{slideMs openDoors closeDoors autoLower} vehicles{<model> = {pos rot rear doors bay}} rearReach }` ·
`Beds { enabled range types{<type> = {pos heading heal anim}} anim leaveSide selfLeave{enabled control label hold} }` ·
`Bay { enabled shell fallbackFloor base spacing columns maxSlots stretcher medics shelves ivHooks props lights perm rearReach maxEnterSpeed fadeMs hideRadar exitBehind keys warnings{surgeryBlood bleeding noAccess arrest cold moving} supplies{enabled shiftLength categories items maxPerTake} }` ·
`Billing { enabled transport reason }`.

## Events, callbacks, APIs

**State bags (server-set, replicated)**
- patient `nzaTr = { m = 'carry'|'str'|'bed'|'bay'|'seat'|'free', n, c, s, b, bt, at, v, seat, slot, stand, from }`
- stretcher entity `nzaStr = { pid, pk (target), pusher, veh, low, home }`
- ambulance entity `nzaAmb = { str, inside, bay (crew count) }`
- patient meta (core): `carried stretcher bed inBed vehicle bay`; medics in a bay: `meta.bay`.

**Callbacks** (`lib.callback`, reply `true, data | false, { err, msg }`):
`nza:transport:carry (target)`, `drop ({ veh?, seat? })`, `helpUp (target)`, `outVehicle (target)`,
`str:take ({ veh? | point? })`, `str:register (token, net)`, `str:push (net, on)`, `str:height (net, low)`,
`str:swap (net, newNet)`, `str:place (net, target)`, `str:off (net)`, `str:load (net, veh)`,
`str:unload (veh)`, `str:store (net, veh?, point?)`, `bed:place (point, net?)`, `bed:leave (target)`,
`bed:self ()`, `bay:enter (veh)`, `bay:exit ()`, `bay:supplies ()`, `bay:take (key, count)`.

**Net events**: S→C `nza:transport:carryEnd`, `nza:transport:pushEnd (net)`, `nza:transport:bay:crew
({ crew, patient })`, `nza:transport:bay:tick ({ speed, plate })`, `nza:transport:bay:kick ({ at })`;
C→S `nza:transport:selfRelease` (a dead player about to respawn). The client also listens to
`nza:wounded:respawn` to let go before the respawn teleport.

**Server bus emitted**: `transport:loaded (src, p, vehNet, strNet)`, `transport:unloaded (src, p|nil, vehNet)`,
`transport:bed (src, p, point)`, `transport:carry (src, p, on)`, `transport:bay (src, vehNet, inside)`.
Listened: `patient:removed player:unloaded state:changed wounded:respawned staff:changed`.

**Client bus emitted**: `transport:mine (mode, cmd)`, `bay:entered (vehNet, target|nil)`,
`bay:left (vehNet)`, `bay:ivstand (target, info)`, `bay:monitor (target, info)` — `info = { veh, slot,
bay = true, origin, hooks = { IV hook world positions }, cot = vector4 }`. A module that handles
the IV stand / big monitor in the bay listens to these (or defines `NZA.Blood.OpenStand(target, info)`).

**Server API**: `NZA.Transport.Info(p)`, `Free(p, at?)`, `Release(p)`, `PatientBag(p, tbl)`,
`VehicleRear(veh, extra)`, `BayOrigin(slot)`, `InBay(src)`, `BayOf(vehNet)`, `BayExitAt(vehNet)`,
`LeaveBay(p)`, `DeleteStretcher(rec)`. Export `GetTransportState(src)`.

**Client API**: `NZA.Transport.Carry.Start/Drop/End/Active`, `NZA.Transport.Str.TakeFromVehicle/
TakeFromPoint/Grab/Release/ToggleHeight/PlacePatient/TakeOff/Load/Unload/Store/FreeNear/All/Models`,
`NZA.Transport.Bed.IsBed/Nearest/Occupied/Transfer/PlaceFromCarry/HelpOff/Label`,
`NZA.Transport.Bay.Enter/Exit/Active/Origin/PatientSpot/Info/OpenSupplies/Tool`,
`NZA.Transport.HelpUp / OutOfVehicle / HelpOff`, `NZA.Transport.OwnsHelpOff = true`.

**Registries**: `NZA.Interact` options `nza_tr_carry nza_tr_helpup nza_tr_onstretcher
nza_tr_offstretcher nza_tr_tobed nza_tr_bedleave nza_tr_outveh`; `NZA.RadialItems` parent `patient`
(`tr_carry tr_drop tr_helpup tr_outveh`), parent `stretcher` (`tr_str_take tr_str_push tr_str_release
tr_str_height tr_str_load tr_str_unload tr_str_return tr_bay_enter`), root while inside a bay
(`tr_bay_exit tr_bay_supplies`); point type `stretcher`; Bridge targets on the cot models and the
configured ambulance models.

**NUI app `bay`**: Lua → `open { locale, keys, unit, crew, me, warnings, tools }`, `patient (lite | false)`,
`crew`, `tick`, `monitor { on }`, `tools`, `supplies (list)`, `suppliesClose`; JS → `bay:take { key, count }`,
`bay:supplies { open = false }`, `bay:action { id }`.
Preview: `index.html?app=bay` (`&demo=empty|supplies|monitor|arrest|moving`).

## Security
Every callback: rate limit, permission (`NZA.Staff.Can`), the medic alive, server-side distances
(medic ↔ patient, cot, ambulance back doors, bed point), current state (carried / on a cot /
loaded / in a bay / occupied bed / pushed by someone else). New cots are registered with a one-use
token and checked for model, type and distance (wrong ones are deleted). Supplies: in a bay, per-shift
limit, `maxPerTake`, inventory space. Only a dead player can release themselves (respawn).

## Known limits
- The cot is one model: raise / lower is a state (speed, loading) unless a folded model
  `Config.Props.stretcher_low` is added (then the entity is swapped; see docs/requests/transport.md).
- In-vehicle cot offsets are tuned for the native `ambulance`; add your own models to
  `Stretcher.vehicles` with their `pos / rot / rear`.
- The bay interior is local per client; things other modules spawn in the bay must also be local or
  networked near the bay origin (`NZA.Transport.Bay.Info()`).
- Only verified with stubbed-native smoke tests (server flows incl. NPC bay round trips and the
  watchdogs, client file loading) and headless browser previews — not on a live server here.
