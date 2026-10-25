# nayzeee-backpack — install & guide

## 1. Dependencies

| Required | Optional |
|---|---|
| `ox_lib`, `ox_inventory` | `ox_target` (third-eye options) |
| one of `es_extended`, `qbx_core`, `qb-core` (or none) | `oxmysql` (placed bags survive restarts, wardrobe import) |
| | `illenium-appearance` (outfit bag wardrobe import) |
| | `screenshot-basic` (icon studio) |

The framework is detected automatically (`Config.Framework = 'auto'`).

It comes as **two folders**: put both in `resources/`.

| Folder | What's in it |
|---|---|
| `nayzeee-backpack-props` | bag models, textures, purse poses, the duffel props, no code |
| `nayzeee-backpack` | the script and its UI, no props |

Keeping them apart means restarting or updating the script never makes
players re-download a single model, and adding a bag never touches the script.

```
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure screenshot-basic
ensure nayzeee-backpack-props
ensure nayzeee-backpack
```

Give your admins the studio permission (or keep them in an `admin` group):

```
add_ace group.admin nayzeee.backpack allow
```

If the server console says *could not write into ox_inventory/web/images*
after an icon capture, your FXServer build restricts cross-resource writes.
Add this and restart (icons are still saved in `icons/` either way):

```
add_filesystem_permission nayzeee-backpack write ox_inventory
```

## 2. Props

Everything streams from `nayzeee-backpack-props/stream/` (see its
[README](../nayzeee-backpack-props/stream/README.md)). Every bag needs a
`.ydr`, `.ytd` **and** `.ytyp` in its own folder; the props manifest registers
every `.ytyp` by itself. Purse poses (`.ycd`) go in `stream/anims/`.

Your props in another resource? Set `Config.PropsResource` to its name (or
`false`); the script only needs the model **names** in `Config.Backpacks`.

## 3. Items

Start the server and run **`/bagitems`** (console or in game as admin). It
prints a ready-to-paste `ox_inventory/data/items.lua` entry for every bag that
doesn't have one yet. They look like this:

```lua
['nayzeee_backpack_pug'] = {
    label = 'Pug Backpack',
    weight = 1000,
    stack = false,          -- required: every bag has its own stash
    close = true,
    description = '8 slots · 10.0kg',
    client = { image = 'nayzeee_backpack_pug.png' },
    server = { export = 'nayzeee-backpack.usenayzeee_backpack_pug' },
},
```

The outfit bag is a **client** export (it needs the player's clothes), so its
item looks different. `/bagitems` prints this one too:

```lua
['outfit_bag'] = {
    label = 'Outfit Bag',
    weight = 500,
    stack = false,
    close = true,
    client = { image = 'outfit_bag.png', export = 'nayzeee-backpack.useOutfitBag' },
},
```

**Coming from `nayzeee-outfitbag`?** Delete that resource, take it out of
`server.cfg`, and change the item's export from `nayzeee-outfitbag.useBag` to
`nayzeee-backpack.useOutfitBag`. Bags people already own keep their outfits:
the metadata format is the same.

## 4. Database (optional)

Run `install.sql` if `Config.Placement.persist = true`.

---

## Adding a new bag or purse

1. Drop the `.ydr / .ytd / .ytyp` in a new folder in `nayzeee-backpack-props/stream/`.
2. Add an entry to `Config.Backpacks` (purses: `category = 'pocketbook'`, `carry = 'purse'`).
3. `/bagitems` → paste the item into ox_inventory.
4. `/bagtune` → pick the bag → **Carry preset** → nudge → **Save fit to server**.
5. **Icon** tab → Enter icon studio → **This bag**. Done.

No copy-pasting offsets: Save writes to `data/overrides.json`, which every
client picks up live. **Keep `data/overrides.json` when you update the script.**

---

## The studio — `/bagtune` (admin)

### Fit
- **Carry preset** — Back, Low back, Chest, hips, shoulders, hands, forearms.
  Presets are defined relative to the *character*, so they land in the right
  place no matter where a bag's pivot is.
- **Attach bone** — the real bone names (the old list had several mislabeled
  ids, e.g. "Right Hand" was actually the forearm). Switching bone keeps the
  bag where it is in the world, it just follows the new bone.
- **Move** — Left/Right/Forward/Back/Up/Down relative to the character, with
  step sizes. Hold a button to repeat.
- **Rotate** — Turn / Tilt / Lean around the **bag's own centre**. These props
  are converted from clothing so their pivot is far from the mesh; rotating
  around it used to swing the bag in a big arc. Now it turns in place.
- **Pose preview** — loops a carry pose so you can fit a purse to the hand.
- **Exact values** — raw position/rotation, plus *Last saved*, *config.lua*
  and *Clear saved*.
- Keys: arrows / PgUp / PgDn move, Q E turn, R F tilt, Z C lean,
  SHIFT ×5, ALT fine, CTRL+S save, drag to orbit, scroll to zoom.

On open the studio runs a quick probe to learn how the game applies attach
rotations. If that ever fails the dot in the header turns amber and it falls
back to "measured mode" (raw X/Y/Z rotation, still around the bag's centre).

### Look
- **Variants** — all three formats work (texture list, `{label, texture}`,
  `{label, model}`).
- **Storage & store** — edit slots, weight, price and label live. Existing
  bags are resized the next time they're opened.
- **How it's carried** — carry style + default pose, saved per bag.
- **Test animations** — the camera swings to the front so you actually see them.

### Icon
Works like uz_AutoShot, made for bag props:
1. **Enter icon studio** — the bag floats in a lit chroma box under the map.
2. Pick a backdrop colour the bag doesn't use (magenta for green bags, green for pink ones).
3. Drag to orbit, scroll to zoom, or use the angle chips.
4. **This bag** or **Every bag** (optionally every variant).

Each shot is keyed, trimmed, centred on a transparent 512×512 PNG and written
to `icons/` **and** `ox_inventory/web/images/` (`Config.IconCapture.saveToInventory`).
Variant icons are saved as `item_2.png` and bought variants show them.
Restart ox_inventory for brand-new image files to appear. No yarn or node
modules needed.

---

## Purses & pocketbooks

`carry = 'purse'` (or any key in `Config.Carry.Styles`) makes the player loop
an **upper-body** pose while the bag is worn: legs walk and run normally, the
arm holds the bag instead of letting it swing. It pauses automatically in
vehicles, swimming, climbing, ragdoll, with a weapon out, during progress bars
and while another script (emotes) is animating, then comes back by itself.

The default pose is **Carry**, GTA's own one-handed carry (the jerrycan /
briefcase hold), so the arm hangs naturally and the walk stays clean. The
custom photo poses are still in the list as *(custom)*; they look great
standing still but stiffen the upper body while walking.

Players can pick their pose from the bag menu (**Change pose**), saved on the
item. `Config.Carry.walkStyle` optionally sets a walk style while carrying.

**Fitting a purse:** `/bagtune` → pick the purse (its carry pose starts by
itself) → Carry preset **Right hand** → nudge / rotate → **Save fit**. Every
purse model has its own pivot, so each one needs this once; after that the
saved fit is what everyone sees.

Crossbody bags like the shoulder bag aren't purses: give them
`category = 'shoulder'` and no `carry`, and they're worn on the body.

---

## Placing a bag

Bag menu → **Set down** (or `/placebag`). The ghost follows where you look:
**E** place, **SCROLL** rotate (**SHIFT** fine), **BACKSPACE** cancel. Works
on floors, tables and counters; walls are refused (`maxSlope`). The loop uses
an async raycast and only moves the ghost when the hit changes, so it sits at
~0.00–0.01ms while placing.

Placed bags only exist as props within `renderDistance`.

## Opening a bag

Opening isn't a stash popping up any more. You set the bag down in front of
you and go through it (`Config.OpenBag`):

- **Backpacks** — kneel, unzip, rummage (`style = 'kneel'`).
- **Duffels** — stand over it (`style = 'stand'`). The **Duffel Bag** lies
  open on the ground. The money only shows while there is money in it
  (`money`, `black_money` or `markedbills`, see `cashItems`); put cash in
  and it fills, take the last of it out and it empties the moment your hand
  reaches in. Every time you take cash out you reach in and grab it with its
  own animation.
- **Purses / hand-carry bags** open the quick way, in your hands.

Everyone nearby sees the bag on the floor. Closing the inventory picks it back
up; getting knocked down, dying or getting in a car closes it for you.

Any bag can get an open look: `open = { style = 'stand', model = 'my_open_prop',
cashModel = 'my_open_prop_cash', heading = 0.0 }` in its `Config.Backpacks` entry.

### Duffel props & cash grab animation

The open duffel models and the cash grab animation are by **BzZz**
(bzzz_money), used with permission. They're renamed (`nayzeee_duffel_a/b`,
`nayzeee_duffel_typ`, `nayzeee_grab_cash_01`) so they never clash with an
installed bzzz_money, and they are in `escrow_ignore`: BzZz's licence says his
props are never escrowed. To re-make them from a newer bzzz_money:
`python3 tools/rename_bzzz.py <bzzz_money folder> stream` (run inside
`nayzeee-backpack-props`).

## Handing a bag over

Bag menu → **Hand to someone**, third-eye a player → **Hand over bag**, or
`/handbag`. The other player gets a **Take it / No thanks** prompt
(`Config.Handoff.timeout`). When they take it, everyone around sees it: a bag
you're wearing comes off your back, you hold it out, it's in their hand, and
then on their back. The contents go with it. Works for every backpack, purse
and duffel, and for the outfit bag (its own menu → **Hand to someone**, outfits
and all).

It's refused when either of you is dead, cuffed or in a car, when your bag is
open on the ground, when they already have a bag (`Config.OneBagOnly`), can't
carry the weight, or can't use a job bag. Job bags can't be handed over unless
`Config.Handoff.jobBags = true`. Everything is checked again at the moment the
bag changes hands, and every hand-off is logged with the contents.

## Name tags

Wear a bag and use a **Bag Name Tag** (or bag menu → **Name tag**). The
editor shows a live preview while you pick:

| | Options (all in `Config.NameTags`) |
|---|---|
| **Text** | up to 18 characters, a blocked-words list keeps it clean |
| **Tag** | leather (stitched), metal, dark, paper, neon sign, text only |
| **Font** | 12 Google Fonts: script, marker, pixel, neon, spooky… add any family you like |
| **Colour** | swatches, any colour from the picker, or a two-colour gradient |
| **Effect** | glow, flicker, shimmer, rainbow, pulse, wave, glitch, outline |
| **Particles** | sparkles, hearts, stars, snow, embers, bubbles, money, music notes |

The tag hangs off the bag on a little string and sways. Everyone within
`distance` (5m) sees it, nearest `maxVisible` first, never through walls; it
shows on bags that are set down too, and a padlocked bag gets a small lock on
its tag. The bag is renamed to the tag text in the inventory (`renameItem`).
The first tag uses the item; changing it later is free (`editFree`). Every
choice is checked against the config on the server before it's saved.

Cost: nothing runs per frame unless a tagged bag is within reach of your
camera; then only those few tags are positioned each frame.

## Padlocks

Wear a bag and use a **Bag Padlock** (or bag menu → **Padlock it**), then
pick a 4-digit code. The lock is on the bag itself, so it stays locked
wherever the bag goes: robbed, dropped on death, handed over, set down.

Opening a padlocked bag:

| Who | What happens |
|---|---|
| Whoever locked it | Opens as normal (`ownerSkipsCode`) |
| Someone who knows the code | Types it once, then opens as normal until a restart or the code changes (`rememberCode`) |
| Anyone else | **Enter the code**, **Pick the lock** (lockpick + ox_lib skill check; a fail can snap the pick) or **Cut it off** (bolt cutters, 6s) |
| Police searching | Same as anyone else, unless `policeOpen = true` |

Three wrong codes lock you out for a minute. Picking or cutting destroys the
padlock; the owner taking it off (bag menu → **Take the padlock off**) gets it
back. The item tooltip shows *Padlocked*, every lock, pick and cut is logged,
and the code itself is stored as a salted hash only the server can check.

`/bagitems` prints the padlock, lockpick and bolt cutter items if you don't
have them yet.

## Sounds

Bags zip open and shut, buckles click when you put one on or take it off,
it thuds when it's set down or dropped, fabric rustles when it changes hands,
and padlocks click, scrape and snap. Everyone within `Config.Sounds.range`
hears it, quieter with distance and from the side it came from.

The sounds are generated live in the browser (no audio files, nothing to
license). Rather use recordings? Put `.ogg` files in `web/sounds/` and map
them in `Config.Sounds.files`, e.g. `zip_open = 'sounds/zip_open.ogg'`.
Turn any one off with `levels.<name> = 0`.

## Finding your bags

Bag menu → **Find my bags** (or `/mybags`) lists every bag you've set down,
nearest first, with the street, the distance and whether it's locked. Pick one
for a waypoint.

## Bags in cars

Get in a car and your bag goes on a free seat: front passenger first, then
the back (`Config.Vehicle.seats`). It sits upright and leans against the seat
back, the same way round it sits on you, for any bag model.

Passengers come first. A seat someone is climbing into counts as taken, so the
bag moves to the next free seat (or out of sight if the car is full) before
they sit down. Two people with bags each get their own seat. On motorcycles and
bicycles the bag stays on your back (`wornClasses`). Get out and it's back on
you. Every client works the seats out the same way from who's in the car, so
everyone sees the bag on the same seat with no extra network traffic.

`Config.Vehicle.enabled = false` goes back to hiding bags in cars (or keeping
them on your back with `Config.ShowInVehicle = true`).

## Taking a bag off

**Take off** is saved on the item, so a stowed bag stays stowed through
relogs, reconnects and server restarts.

---

## The store

Walk up to the shop keeper: the camera moves over the counter and the bags
float above it. **A / D**, the arrows or the mouse wheel slide to the next bag,
drag spins it, **ENTER** buys, **T** tries it on your character, **ESC** leaves.
Theme chips sit at the top, type chips at the bottom; no side panel.
Every bag shows how it compares to the one you're wearing (`+3 slots · +5kg vs
yours`, teal when it's an upgrade, red when it's smaller).

Set `display.bag` to where the bags should float and `display.heading` to the
way the shop keeper faces; the camera stands `camDistance` back on the
customer's side. Use `display.cam` for an exact camera spot instead.

---

## Outfit bag

Use the item and pick:

- **Set it down** — the bag goes on the ground and opens. Walk off past
  `returnDistance` and it comes back to your pockets on its own.
- **Quick change** — open it right from your inventory, nothing on the ground.

In the bag:

| | |
|---|---|
| **Save current outfit** | saves what you're wearing (hair and hair colour too, `saveHair`) |
| **Wear** / **1–9** | puts the whole look on with an animation |
| **Wear one piece** | just the shoes, just the hat… each with its own animation |
| **Hover** | preview yourself in it before you change (`previewPed`) |
| **Undo** | back to what you had on before the last change |
| **Pin** / **Tag** | pinned outfits stay on top; colour tags filter the list |
| **Update** / **Rename** / **Delete** | update an outfit with what you're wearing now |
| **Share** | copies a code (`NZO1-...`); paste it into any bag with the paste button |
| **Import** | pulls your saved outfits from illenium-appearance |
| **Lock** | locked bags only open for you; unlocked ones can be opened by anyone nearby, who can wear and **copy** outfits into their own bag (`Config.OutfitBag.access`) |

Outfits saved on another character model are greyed out instead of turning
you into a mess. A bag that's on the ground when the server crashes or you
disconnect is handed back on your next login.

## Jobs

Bags with `job = 'ambulance'` (or a list) are job bags:

- Only that job sees them (Issued tab) and only they can wear them.
- `price = 0` → **Collect**. The *same* bag comes back every time, contents
  and all, because its stash id is remembered per character.
- `kit = { { 'bandage', 10 }, ... }` fills it the first time it's issued.
- `Config.Jobs.requireDuty`, `autoIssue`, `autoReturn` for duty-based kit.
- `Config.Drop.keepJobBags` / `Config.Robbery.protectJobBags`.
- Police can **Search backpack** on cuffed / downed / hands-up players
  (`Config.Jobs.policeSearch`).

### Integrations

`integrations.lua` ships with wasabi_ambulance, wasabi_police, qb-ambulancejob,
qb-policejob, qbx_medical, qbx_police, esx_ambulancejob, esx_policejob and the
ps / cd / qs / core dispatch scripts. They switch on when their resource is
running. Other creators can register their own from their resource:

```lua
exports['nayzeee-backpack']:RegisterIntegration('my_script', {
    resource = 'my_script',
    client = { isDead = function() ... end, isCuffed = function() ... end },
    server = { canWear = function(src, bagKey) return true end },
})
```

The full hook list is at the top of `integrations.lua`.

Bag stashes only open for a player right after this script (or
`GetBagStash`) opened them, so nobody can open a bag from the client by its
stash id and skip a padlock or a private placed bag.

### Exports (server)

```lua
exports['nayzeee-backpack']:GetWornBag(src)        -- bagKey, state
exports['nayzeee-backpack']:GetBagStash(src)       -- stash id of the worn bag (that player may open it once, within 15s)
exports['nayzeee-backpack']:OpenBag(src)
exports['nayzeee-backpack']:GiveBag(src, key, variant)
```

---

## Commands

| Command | Who | |
|---|---|---|
| `/bagtune` | admin | studio |
| `/bagitems` | admin / console | print missing ox_inventory items |
| `/givebag id bag [variant]` | admin / console | give a bag |
| `/bagmenu` `/openbag` `/placebag` `/bagnearby` | everyone | bindable in key settings (defaults: `Config.Keybinds`) |
| `/mybags` | everyone | find bags you've set down |
| `/handbag` | everyone | hand your bag to the closest player |
| `/robbag` `/searchbag` | everyone / police | fallbacks without ox_target |
| `/bagstore` | everyone | when `Config.Shop.openMode` is `command` or `both` |

## Performance

Every loop idles and only goes per-frame while it has work:

| Thread | Idle | Per-frame only when |
|---|---|---|
| Worn bag scope / vehicle seats | 2000ms | someone near you wears a bag (750ms), a bag is in a car (250ms) |
| Carry pose check | 1500ms | wearing a purse (600ms, never per-frame) |
| Status publisher | 1000ms | — (statebag only written on change) |
| Placement | — | placing |
| Placed bag streaming | 3000ms | bags placed (1500ms) |
| Shop | — | store open |
| Outfit bag | — | a bag is on the ground near you (500ms) or the menu is open (300ms) |
| Open bag (kneel / duffel) | — | the bag is open (250ms) |
| Hand-off | — | per frame for the ~3s a bag changes hands near you |
| Name tags | 750ms | a tagged bag is near your camera (250ms scan, per-frame positions) |
| Studio / icon box | — | studio open |

## Escrow

Both manifests already have `escrow_ignore` and the `/assetpacks` dependency:
the script leaves config, integrations and the framework bridge readable, and
the props resource leaves BzZz's duffel props and animation unescrowed (his
licence). Escrow only encrypts `.lua` files, so `web/` and `server/icons.js`
ship readable.
