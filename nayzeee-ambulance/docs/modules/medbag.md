# Module: medbag (medical bag, body bag, morgue)

A rolling medical bag that holds supplies on scene, and the full body-bag workflow from the
deceased patient to the morgue.

## Files

| File | What it does |
|---|---|
| `config/modules/medbag.lua` | `Config.Medbag` (Bag, Storage, Access, Body, Morgue) |
| `locales/en/medbag.lua` | strings `medbag.*` (Lua + the NUI app, which gets `NZA.LocaleTable('medbag')`) |
| `server/modules/medbag.lua` | bag storage (`nza_bags`), usable item, ground bags (server-created objects), carry, pick up, open, moves, kit / sort / lock / empty, access rules, watchdog, persistence |
| `server/modules/medbag_body.lua` | procedure `bodybag`, body records, carry / drop / stretcher / vehicle, open, toe tag, morgue delivery (respawn / reward / records), watchdog |
| `client/modules/medbag.lua` | placing, bag targets, hand carry, NUI glue, radial items |
| `client/modules/medbag_body.lua` | bagging (staged progress), body bag options, carry + context, vehicle unload prompt, the bagged player's hidden/attached ped, point type `morgue`, radial items |
| `html/apps/medbag/app.js`, `app.css` | NUI app `medbag` (HUD side panels) |

## Features

### Medical bag
- **Use the item** (`Config.Items.medbag`): bend down and set the bag on the ground in front of you
  (never through a wall; pockets face you). The bag is a networked object created by the server
  (`Config.Props.medbag`, `Bag.model` to override, `extraModels` count as bags too).
- Every bag has an id (`MB-7K2QF`) stored in the item's metadata. Pick it up again and the contents
  stay with it; the item description shows `Bag MB-7K2QF · 14 items · 2.3 kg`.
- **Target options** on the bag: *Open medical bag*, *Carry medical bag*, *Pick up medical bag*.
- **Carry in hand**: the prop hangs from the right hand (`Bag.Carry.bone/pos/rot`, jerry-can arm
  pose), jog speed by default. Prompts: **[G]** put down, **[E]** open it while holding it,
  **[H]** pack it away. Weapons and vehicles are blocked while carrying. Going down drops the bag.
- **Ground bags survive restarts** (`Bag.persist`); bags removed by cleanup scripts come back.
  `maxOut` limits how many bags one player can leave on the ground. A duplicated item with an id
  that is already out is refused.
- **Access** (`Config.Medbag.Access`): owner, medics (on duty, optional perm), police, anyone,
  admins. The owner can **lock** a bag (only the owner and admins can open or take it then).

### Storage window (NUI `medbag`)
HUD side panels on the right so the world and the bag stay visible (HUD design: panels
`rgba(12,13,16,.92)`, r12, teal rail, glowing bars):
- **Medical Bag · Unit storage**: 5-column slot grid (slot numbers, item pictures, counts), owner /
  "Your bag" / Locked chips, sort and lock buttons, red Close pill, capacity bar (teal → amber 80 % →
  red 95 %) with kg and slots used.
- **Transfer amount**: stepper (−/+ / type / mouse wheel) and `1 / 5 / 10 / ALL` chips,
  **Pack kit** (tops the bag up from your pockets to `Storage.kit`), **Empty bag** (confirm modal).
- **Personnel · Equipment & pockets**: your inventory (any inventory through the bridge), search,
  items that may not go in the bag dimmed with a red badge, your own capacity bar
  (`ox_inventory` / QB / ESX limit, or `personalMax`).
- **Moves**: click = move the transfer amount, Shift + click = all, right click = one, drag & drop
  to a specific slot, drag inside the bag to rearrange / merge / swap, drag a bag item onto the
  pockets panel to take it out. Moves are queued and applied in order; the changed slot pulses.
- **Tooltips** beside the hovered slot: picture, name, category, description, weight each / total,
  stack, metadata (blood type, serial, ...), what a click does.
- **Transfer cards** over the world: `PACKED 5×` (teal) / `REMOVED 1×` (white) with the item picture
  and name, up to six in a row, each with a timer line.
- Several medics can have the same bag open; everyone sees each other's moves live. Walking away,
  the bag being taken, losing access or going down closes the window.
- Keys: `1/2/3/4` = 1/5/10/all, `+`/`-` step, `F` search, `Esc` close.

### Body bag
- **Place in body bag** (patient option, order 90; also in the radial *Patient* submenu): dead
  players and NPC patients, permission `Body.perm` (`bodybag`), the body bag item (used at the end).
  Dead **ambient NPCs** that are not patients yet get the same option (`anyDeadPed`).
- Procedure `bodybag` (server session, `minTime`, distance watchdog): turn to the body, three
  progress steps with animations (*Unfolding the body bag… / Rolling the body in… / Zipping it
  closed…*, `Body.steps`, total `Body.time`). Easy mode = one bar.
- The bag (`Config.Props.bodybag`) lies where the body was. A **player** stays a patient (state
  `dead`, state bag `bag = true`): their own client hides the ped and attaches it inside the bag,
  wherever the bag goes; the death screen shows "You are in a body bag". An **NPC** ped is removed
  and its patient record replaced by the body record.
- Options on the bag: **Carry body bag**, **Deliver to the morgue** (bag within `Morgue.range` of a
  morgue), **Read the toe tag** (name, time of death, cause of death, who bagged it), **Open body
  bag** (players only: the body lies there again; `returnItem` gives the bag back).
- **Carrying** (over the shoulder, walk only): **[G]** put it down, **[E]** context:
  *Deliver to the morgue* / *Lay it on the stretcher* (a free cot from the transport module; the bag
  rides along when the cot is pushed or loaded into the ambulance) / *Put it in the vehicle* (behind
  any car or van, boot / back doors open, `Vehicle.max` bags per vehicle). Behind a vehicle with bags
  inside: **[E] Take the body bag out** (also a radial item).
- Watchdog: carrier goes down / leaves → the bag is put down where they were; cot or vehicle
  deleted → the bag drops there; bag prop removed → it comes back.
- Revive / respawn of a bagged player (admin `/revive`, own respawn) releases them from the bag.

### Morgue
- Point type **`morgue`** (hospital builder → *Morgue*), option *Deliver body bag* (carried or a bag
  next to it), plus the bag option and the carry context. `Morgue.fallback` spots (with a marker)
  work while no morgue point is built.
- **Players**: record entry ("Delivered to the morgue (Pillbox)"), then the wounded module's
  respawn flow (`NZA.Wounded.ForceRespawn`) at the hospital (`respawn = 'hospital'`) or at the morgue
  itself (`'morgue'`), respawn fee only with `Morgue.fee = true`. Without the wounded module the
  player is revived and moved to `NZA.Hospitals.RespawnPoint` (fade).
- **NPCs**: removed, reward to the medic (`reward.npc`, account `reward.account`), optional
  `reward.society` into `Config.Billing.society`; the dispatch call is closed when every patient of it
  is gone.

## Controls

| Where | Key (default) | Action |
|---|---|---|
| holding a medical bag | G / E / H | put down / open / pack into inventory |
| storage window | click, Shift + click, right click, drag | move amount / all / one / to a slot |
| storage window | 1 2 3 4, + −, F, Esc | amount 1/5/10/all, step, search, close |
| carrying a body bag | G / E | put down / context (morgue, stretcher, vehicle) |
| behind a vehicle with body bags | E | take one out |

Keys are GTA controls in `Config.Medbag.Bag.Carry.keys` and `Config.Medbag.Body.Carry.keys`.

## Config keys (`Config.Medbag`)

- `radial`
- `Bag { enabled model extraModels whoCanPlace placeAhead distance openRange maxOut persist putDown pickUp
  Carry { enabled bone pos rot anim maxSpeed keys { drop open stow } } }`
- `Storage { slots maxWeight maxStack mode extra blocked blockWeapons weights defaultWeight personalMax
  personalFallback moveRate { count window } kit { { item, count } } }`
- `Access { owner medics perm police anyone lock admins }`
- `Body { enabled perm requireItem distance time anyDeadPed unbag returnItem groundOffset bagHeading insideOffset
  steps { { label share dict clip flag } } Carry { enabled bone pos rot anim pickup maxSpeed putAhead dropHeading
  keys { drop context } } Stretcher { enabled range pos rot } Vehicle { enabled range max openDoor blockedClasses models } }`
- `Morgue { range respawn fee reward { npc player account society } fallback fallbackMarker }`

## Events, callbacks, exports

**Callbacks** (`lib.callback`, replies `{ ok = true, ... } | { ok = false, err, msg }`):
`nza:medbag:put (token|nil, coords, heading)`, `open (id|nil)`, `move (id, { dir, from, to, count, name })`,
`action (id, 'sort'|'lock'|'kit'|'empty', data)`, `carry (id)`, `held (token, net)`, `pickup (id)`, `stow ()`,
`me ()` (pockets refresh every 4 s while a bag is open);
`nza:medbag:body:adopt (pedNet)`, `body:carry (id)`, `body:drop (coords, heading)`, `body:stretcher (cotNet)`,
`body:vehicle (vehNet)`, `body:open (id)`, `body:deliver (pointId, id?)`, `body:tag (id)`.
Procedure: `bodybag` (`NZA.Proc`, states `{ dead = true }`, item used at the finish).

**Net events**: C→S `nza:medbag:close (id)`; S→C `nza:medbag:place (token)`, `nza:medbag:sync (id, bag)`,
`nza:medbag:closed (id, reason)`, `nza:medbag:carryEnd ()`, `nza:medbag:body:carryEnd ()`,
`nza:medbag:body:release (coords, heading, teleport)`.

**State bags**: `nzaMedbag` (bag prop), `nzaBag` + `nzaBody` (body bag prop), `nzaInBag` (player),
`nzaBodyOn` (cot), `nzaBodies` (vehicle). Patient meta `bodybag = id` (core state bag `bag`).

**Server bus**: `medbag:placed`, `medbag:picked`, `medbag:moved`, `bodybag:bagged (src, body)`,
`bodybag:morgue (src, body, point)`. Listens to `state:changed`, `patient:revived`, `wounded:respawned`,
`player:unloaded`.

**NUI app `medbag`**: Lua → `open { locale, bag, me, kit }`, `sync { bag }`, `me { me }`, `busy { on }`;
JS → `medbag:move`, `medbag:action`, `medbag:close`. Preview `index.html?app=medbag`
(`&demo=tip|tipme|drag|locked|empty|full`); the preview simulates every move locally.

**Exports (server)**: `GetMedbagContents(id) → { { slot, name, count, metadata } }`,
`GetBodyBags() → { { id, pid, kind, name, mode, coords } }`.

**Client API**: `NZA.Medbag.Open / Carry / PutDown / Stow / PickUp / Carrying / NearestBag / GroundSpot`,
`NZA.Medbag.BagBody / CarryBody / DropBody / Deliver / BodyCarrying / NearestMorgue`.

**Registries**: `NZA.Interact` `nza_bodybag`, `nza_bodybag_carry`, `nza_bodybag_deliver`, `nza_bodybag_tag`,
`nza_bodybag_open`; `Bridge.Target.Model` on the bag models; `Bridge.Target.Ped` `nza_bodybag_ambient`;
point type `morgue`; radial `mb_open mb_drop mb_stow bb_drop bb_unload` (root), `bb_place` (patient);
`Bridge.Inv.RegisterUsable(Config.Items.medbag)`.

## Security

Every callback: rate limit, the player alive and on foot, server-side distances (bag / body / cot /
vehicle / morgue point), access rules and permissions (`NZA.Staff.Can`). Moves are checked against the
real inventory slot (name and count re-read, stale slots refused), item rules, slot capacity, weight
and a per-bag lock; items leave the pockets before they enter the bag and the bag is restored when an
inventory refuses an item. Hand / cot props are registered with one-use tokens and checked for model
and distance. The item must still be in the player's inventory when the bag is put down.

## Known limits

- The body bag prop is the native `xm_prop_body_bag`; its carry / stretcher offsets are config values
  tuned without an in-game check (`Body.Carry.pos/rot`, `Body.Stretcher.pos/rot`, `bagHeading`).
- A body bag on a stretcher is not a transport "patient": transport can still place a patient on that
  cot or store it (see docs/requests/medbag.md). The bag then drops where the cot was.
- Bags cannot be put down inside the (local) ambulance treatment bay.
- Personal capacity comes from ox_inventory / QBCore / ESX; other inventories use `personalFallback`.
- Verified with a stubbed-native smoke test of both server files (39 checks: place, open, deposits,
  metadata, rules, rearrange, withdraw, kit, sort, lock, access, weight cap, empty, carry, put down,
  stow, re-place, pick up, NPC + player body bag, toe tag, vehicle, stretcher, morgue, revive), a
  client load test and headless-browser previews — not on a live server here.
