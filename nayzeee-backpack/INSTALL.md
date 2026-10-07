# nayzeee-backpack 2.0 — install & guide

## 1. Dependencies

| Required | Optional |
|---|---|
| `ox_lib`, `ox_inventory` | `ox_target` (third-eye options) |
| one of `es_extended`, `qbx_core`, `qb-core` (or none) | `oxmysql` (placed bags survive restarts) |
| | `screenshot-basic` (icon studio) |

The framework is detected automatically (`Config.Framework = 'auto'`).

```
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure screenshot-basic
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

## 2. Stream files

See [`stream/README.md`](stream/README.md). Short version: every bag needs a
`.ydr`, `.ytd` **and** `.ytyp`, and every `.ytyp` needs a `data_file
'DLC_ITYP_REQUEST'` line in `fxmanifest.lua`. Purse poses (`.ycd`) go in
`stream/anims/` and need nothing else.

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

## 4. Database (optional)

Run `install.sql` if `Config.Placement.persist = true`.

---

## Adding a new bag or purse

1. Drop the `.ydr / .ytd / .ytyp` in `stream/` and add its `data_file` line.
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

## Taking a bag off

**Take off** is saved on the item, so a stowed bag stays stowed through
relogs, reconnects and server restarts.

---

## The store

Walk up to the shop keeper: the camera moves over the counter and the bags
float above it. **A / D**, the arrows or the mouse wheel slide to the next bag,
drag spins it, **ENTER** buys, **T** tries it on your character, **ESC** leaves.
Theme chips sit at the top, type chips at the bottom; no side panel.

Set `display.bag` to where the bags should float and `display.heading` to the
way the shop keeper faces; the camera stands `camDistance` back on the
customer's side. Use `display.cam` for an exact camera spot instead.

---

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

### Exports (server)

```lua
exports['nayzeee-backpack']:GetWornBag(src)        -- bagKey, state
exports['nayzeee-backpack']:GetBagStash(src)       -- stash id of the worn bag
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
| `/bagmenu` `/openbag` `/placebag` `/bagnearby` | everyone | bindable in key settings |
| `/robbag` `/searchbag` | everyone / police | fallbacks without ox_target |
| `/bagstore` | everyone | when `Config.Shop.openMode` is `command` or `both` |

## Performance

Every loop idles and only goes per-frame while it has work:

| Thread | Idle | Per-frame only when |
|---|---|---|
| Worn bag scope / vehicle check | 2000ms | someone near you wears a bag (750ms) |
| Carry pose check | 1500ms | wearing a purse (600ms, never per-frame) |
| Status publisher | 1000ms | — (statebag only written on change) |
| Placement | — | placing |
| Placed bag streaming | 3000ms | bags placed (1500ms) |
| Shop | — | store open |
| Studio / icon box | — | studio open |

## Escrow

`fxmanifest.lua` already has `escrow_ignore` (config, integrations, the
framework bridge) and the `/assetpacks` dependency. Escrow only encrypts
`.lua` files, so `web/` and `server/icons.js` ship readable.
