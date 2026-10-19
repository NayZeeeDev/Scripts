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
| `client/modules/medbag.lua` | placing, bag targets, hand carry, bag window glue (layout, par list), radial items |
| `client/modules/medbag_body.lua` | bagging (zip-up card runner), toe tag card, body bag options, carry + context, vehicle unload prompt, the bagged player's hidden/attached ped, point type `morgue`, radial items |
| `html/apps/medbag/app.js`, `app.css` | NUI app `medbag`: bag window (pockets dock + the open bag), zip-up card, toe tag |

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

### Bag window (NUI `medbag`, mode `bag`) — our own composition (docs/design/ORIGINAL.md)
Two docks on the screen edges around a clear centre, so the bag on the floor stays in view and
moved items visibly travel between you and the bag. The bag itself is drawn **open, seen from
above** — not a slot grid:
- **The open bag** (right dock): the shell takes the bag's colour (stitched seam, reflective strip
  along the front), the **lid** is flipped back with its **mesh pocket**, a **zipper hinge** with two
  pulls joins it to the body, the **main compartment** holds supplies under **elastic loops**, and two
  tall **side pouches** with velcro flaps take big items (saline, blood, binder). Each compartment
  shows its name and `used/total`. Compartments are config (`Storage.compartments`: place `main |
  lid | left | right`, slot count, columns) and map to slot numbers in order, so the server keeps a
  plain slot list. Stacks read as stacks (copies peek out behind the item). Opening the window
  swings the lid back, runs the zipper and settles the supplies in one by one.
- **Par levels** (`Storage.kit`): every supply on the restock list carries a **par bar** under its
  name (teal = at par, amber = short); a supply that is missing altogether leaves a **shadow
  outline** in a free slot (dashed amber, `0/10`, the item's silhouette). **Click an outline** to pack
  that supply from your pockets up to its par level (grey outline = you carry none). The readout has
  a *Par* row (`8 / 11 stocked`), **Restock** shows how many units it can pack (`+12`) or how many are
  still short (`2 short`), and pocket rows the bag needs get a teal **Bag needs 4** chip.
- **Bag header**: the bag drawn front-on in its colour, name (or "Medical bag"), id, owner / Locked /
  In your hand; buttons *Name & colour* (owner), *Sort by type*, *Lock*, red Close pill. A load dial
  (teal → amber 80 % → red zone, knob) with an instrument list (Load kg, Slots, Units, Par).
- **Your pockets** (left dock): a vertical list of your inventory (any inventory through the
  bridge): picture, name, category and unit weight, count, a go-button. A status ring around the
  header icon fills with your own load (`ox_inventory` / QB / ESX limit, or `personalMax`); filter
  field. Items that may not go in a bag stay dimmed with "Stays in your pockets".
- **Quantity dial** (under the pockets): a 240° dial with a rolling counter in the centre, preset
  notches on the arc (`1 · 5 · 10 · Stack`), click the arc / mouse wheel / − + to set it, and a
  gesture list (Click, Hold, Shift, RMB, Drag).
- **Name & colour**: the owner names the bag ("Trauma", "Airway", max `nameLength`) and picks one of
  `Bag.colours` (red / orange / green / magenta models). The whole open bag previews the colour live;
  on save the bag on the ground switches model at once; the inventory item shows the name.
- **Bag log** (under the bag): the latest moves (time, picture, item, "into the bag" / "to pockets"
  or "P. Nair took it" with the colleague's initials, `+5` / `−1`). It gives way first when space is
  short (fades out at the bottom).
- **Moving items**: click = the dial quantity · **hold = pour** (a ring fills around the item and a
  `+n` counter climbs faster the longer you hold; release to move that many) · Shift + click =
  whole stack · right click = one · drag onto any slot of any compartment (or rearrange / merge /
  swap inside the bag, or drop a bag item on the pockets; the target compartment's name lights up).
  Moves are queued and applied in order; the item image flies from the source to its new slot / row,
  which flashes when it lands.
- **Tooltips** beside the dock: picture, name, category, description, weight each / total, count,
  par level (`7 / 10 · 3 short`), metadata (blood type, serial, ...), what a click does. Shadow
  outlines get their own tooltip (par level, how many you carry, what a click packs).
- Several medics can have the same bag open; everyone sees each other's moves live (and in the log).
  Walking away, the bag being taken, losing access or going down closes the window. Pockets refresh
  every 4 s while open.
- Keys: `1/2/3/4` = 1 / 5 / 10 / stack, `+`/`-` step, `F` filter, `Enter` save the name, `Esc` close.

### Body bag
- **Place in body bag** (patient option, order 90; also in the radial *Patient* submenu): dead
  players and NPC patients, permission `Body.perm` (`bodybag`), the body bag item (used at the end).
  Dead **ambient NPCs** that are not patients yet get the same option (`anyDeadPed`).
- Procedure `bodybag` (server session, `minTime`, distance watchdog): turn to the body, then three
  steps with their animations (*Unfold the bag beside the body / Roll the body in / Zip it closed*,
  `Body.steps`, total `Body.time`). While they run the **zip-up card** sits bottom-left above the
  minimap (NUI `medbag`, mode `zip`, no focus, the game keeps the controls): the deceased's initials,
  name, time and cause of death, a vertical step spine (done = teal check, current pulses), and a
  real **zipper** whose teeth interlock as the slider runs to the end stop, with a rolling percentage.
  It turns *Sealed* at the end. **[X]** (`Body.cancelKey`) stops. `Body.zipCard = false` uses plain
  ox_lib bars instead. Easy mode = one bar.
- The bag (`Config.Props.bodybag`) lies where the body was. A **player** stays a patient (state
  `dead`, state bag `bag = true`): their own client hides the ped and attaches it inside the bag,
  wherever the bag goes; the death screen shows "You are in a body bag". An **NPC** ped is removed
  and its patient record replaced by the body record.
- Options on the bag: **Carry body bag**, **Deliver to the morgue** (bag within `Morgue.range` of a
  morgue), **Read the toe tag**, **Open body bag** (players only: the body lies there again;
  `returnItem` gives the bag back).
- **Toe tag** (NUI `medbag`, mode `tag`, no focus, `Body.tagSeconds`): a manila tag on the right edge
  with a metal eyelet and its string, filled in by hand in blue ink — tag number, name, date and time
  of death, sex · age, cause, *Found at* (street + area, recorded when the bag was closed), who bagged
  it, the call id (or blood type) and a red rubber stamp (*Hold for ID* / *Unclaimed* for NPCs). While
  the bag window is open the tag comes as a toast instead.
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
| storage window | click a shadow outline | pack that supply up to its par level |
| bagging a body | X | stop (zip-up card) |
| carrying a body bag | G / E | put down / context (morgue, stretcher, vehicle) |
| behind a vehicle with body bags | E | take one out |

Keys are GTA controls in `Config.Medbag.Bag.Carry.keys`, `Config.Medbag.Body.Carry.keys` and
`Config.Medbag.Body.cancelKey`.

## Config keys (`Config.Medbag`)

- `radial`
- `Bag { enabled model extraModels colours { { id model hex } } defaultColour nameLength whoCanPlace placeAhead
  distance openRange maxOut persist putDown pickUp Carry { enabled bone pos rot anim maxSpeed keys { drop open stow } } }`
- `Storage { slots maxWeight maxStack mode extra blocked blockWeapons weights defaultWeight personalMax
  personalFallback moveRate { count window } compartments { { id place slots cols } } kit { { item, count } } }`
  (`kit` = the par levels: restock targets, par bars and shadow outlines)
- `Access { owner medics perm police anyone lock admins }`
- `Body { enabled perm requireItem distance time anyDeadPed unbag returnItem groundOffset bagHeading insideOffset
  zipCard cancelKey { control label } tagSeconds steps { { label share dict clip flag } } Carry { enabled bone pos rot anim pickup maxSpeed putAhead dropHeading
  keys { drop context } } Stretcher { enabled range pos rot } Vehicle { enabled range max openDoor blockedClasses models } }`
- `Morgue { range respawn fee reward { npc player account society } fallback fallbackMarker }`

## Events, callbacks, exports

**Callbacks** (`lib.callback`, replies `{ ok = true, ... } | { ok = false, err, msg }`):
`nza:medbag:put (token|nil, coords, heading)`, `open (id|nil)` → `{ bag, me, kit = { { name, label, image, count } }, colours }`,
`move (id, { dir, from, to, count, name })`,
`action (id, 'sort'|'lock'|'kit'|'empty'|'style', data)`, `carry (id)`, `held (token, net)`, `pickup (id)`, `stow ()`,
`me ()` (pockets refresh every 4 s while a bag is open);
`nza:medbag:body:adopt (pedNet)`, `body:carry (id)`, `body:drop (coords, heading)`, `body:stretcher (cotNet)`,
`body:vehicle (vehNet)`, `body:open (id)`, `body:deliver (pointId, id?)`,
`body:tag (id)` → `{ id, name, kind, tod, date, cause, by, where, sex, age, blood, call }`.
Procedure: `bodybag` (`NZA.Proc`, states `{ dead = true }`, item used at the finish; start data
`{ time, name, tod, cause }` feeds the zip-up card; finish result `{ score, at, heading, where }`,
`where` is cleaned server-side: no control characters or `< >`, max 60).

**Net events**: C→S `nza:medbag:close (id)`; S→C `nza:medbag:place (token)`, `nza:medbag:sync (id, bag, { moved, by })`,
`nza:medbag:closed (id, reason)`, `nza:medbag:carryEnd ()`, `nza:medbag:body:carryEnd ()`,
`nza:medbag:body:release (coords, heading, teleport)`.

**State bags**: `nzaMedbag = { id, owner, locked, name, colour }` (bag prop), `nzaBag` + `nzaBody` (body bag prop), `nzaInBag` (player),
`nzaBodyOn` (cot), `nzaBodies` (vehicle). Patient meta `bodybag = id` (core state bag `bag`).

**Server bus**: `medbag:placed`, `medbag:picked`, `medbag:moved`, `bodybag:bagged (src, body)`,
`bodybag:morgue (src, body, point)`. Listens to `state:changed`, `patient:revived`, `wounded:respawned`,
`player:unloaded`.

**NUI app `medbag`** (one app, three modes; Lua tracks it in `NZA.Medbag.UIMode = 'bag'|'zip'|'tag'|nil`):
- `open { mode = 'bag', locale, bag, me, kit, colours, layout }`, then `sync { bag, moved?, by? }`, `me { me }`;
  JS → `medbag:move`, `medbag:action`, `medbag:close` (focus + cursor).
- `open { mode = 'zip', locale, zip = { name, sub, steps = { { label, share } }, key, keyLabel } }`, then
  `zipStep { i, ms }` per step and `zipDone {}` (no focus).
- `open { mode = 'tag', locale, ms, tag = { id, name, kind, tod, date, cause, by, where, sex, age, blood, call } }` (no focus).
Preview `index.html?app=medbag` (`&demo=tip|tippar|ghost|tipme|drag|pour|fly|style|stack|locked|empty|bare|full|zip|zipdone|tag|tagnpc`);
the preview simulates every move, restock and shadow-outline click locally.

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
- A colour change while the bag is in your hand shows on the prop the next time it is put down.
- Personal capacity comes from ox_inventory / QBCore / ESX; other inventories use `personalFallback`.
- `Storage.compartments` only changes how the window draws the slots; keep their total equal to
  `Storage.slots` (extra slots are added to the main compartment, missing ones are not drawn).
- Shadow outlines appear only for supplies with no plain stack in the bag (a stack with metadata does
  not count towards par, as on the server's restock).
- Verified with a stubbed-native smoke test of both server files (place, open + par list, deposits,
  metadata, rules, rearrange, withdraw, kit, sort, lock, access, name & colour with the model swap,
  weight cap, empty, carry, put down, stow, re-place, pick up, NPC + player body bag with zip card data,
  toe tag with place, vehicle, stretcher, morgue, revive), a client flow test (bag window layout + par
  list, zip-up card steps / cancel / sealed / bars fallback, toe tag card and its toast fallback),
  a headless-browser interaction test (click, shadow-outline pack, right click, Shift + click, keys,
  restock, drag into the lid, Esc) and screenshots at 1920×1080 and 1280×720 — not on a live server here.
