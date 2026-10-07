# nayzeee-backpack — install

## 1. Dependencies
ox_lib, ox_inventory, es_extended.

## 2. Stream files — READ THIS FIRST

Every bag needs **three** files, not two:

```
stream/yourbag.ydr     <- the model
stream/yourbag.ytd     <- its textures
stream/yourbag.ytyp    <- the archetype  ** REQUIRED **
```

And the ytyp must be declared in `fxmanifest.lua`:

```lua
data_file 'DLC_ITYP_REQUEST' 'stream/yourbag.ytyp'
```

{% hint style="danger" %}
Miss the `.ytyp` or that `data_file` line and you get **"model is not
registered"** even though the `.ydr` is sitting right there. The game never
registers the archetype, so the script can't spawn it.
{% endhint %}

One `data_file` line per ytyp. If your props live in a separate stream
resource, delete these lines — that resource declares its own.

## 3. ox_inventory item
Add to `ox_inventory/data/items.lua`:

```lua
['backpack'] = {
    label = 'Backpack',
    weight = 1000,
    stack = false,
    close = true,
    description = 'Wearable storage.',
    client = {
        image = 'backpack.png',
    },
    server = {
        export = 'nayzeee-backpack.usebackpack'
    },
},
```

`stack = false` matters — each bag needs its own metadata id so stashes stay separate.

## 4. server.cfg
```
ensure ox_lib
ensure ox_inventory
ensure nayzeee-backpack
```

## 5. Add a backpack to Config
```lua
['backpack'] = {
    label = 'Backpack',
    model = 'nayzeee_backpack_016',
},
```

The item key must match the ox_inventory item name.

## Tuning a bag's position
Set `Config.Debug = true`, equip the bag, then:

- `/bagnudge z -0.05` — move one axis, updates live
- `/bagnudge rz 5` — rotate
- `/bagprint` — prints a Config-ready offset block

Paste the result into that bag's `offset` key. Bags built from the same
clothing base share a pivot, so most need nothing.

## Notes
- Stash contents live with the item, not the player. Hand someone your bag and the contents go with it.
- Props sync to other players through a statebag; no extra events needed.
- The server verifies the player actually holds a bag before showing the prop.

---

## Backpack Studio (v1.2)

Set `Config.Debug = true`, then `/bagtune` in game (also bindable under
FiveM keybinds).

**Bag list (left)** — every backpack in your config, showing slot count,
skin count, and whether it already has a tuned offset. Click one to
preview it on your back.

**Fit tab** — bone selector, position and rotation sliders with
selectable step sizes, hold-to-repeat nudge buttons, and turn-character
buttons. Copy gives you a paste-ready `offset` block.

**Look tab** — swap texture variants live, see the bag's storage
settings, and test the put-on / take-off / open animations. Copy here
gives you the whole config entry, offset included.

**Icon tab** — lifts the prop 180m above the map so only sky sits
behind it, hides the HUD and your ped, and lets you spin and zoom.
Capture saves automatically if `screenshot-basic` is running; otherwise
the UI hides so you can grab the shot yourself, then cut it out against
the flat sky.

## Per-bag settings

```lua
['backpack_duffel'] = {
    label  = 'Duffel Bag',
    model  = 'nayzeee_backpack_duffel',
    slots  = 20,        -- overrides Config.Storage.slots
    weight = 40000,     -- overrides Config.Storage.weight
    variants = {
        [0] = 'Default',
        [1] = 'Red',
    },
    offset = { ... },   -- only if the bag sits wrong
},
```

Anything omitted falls back to the defaults.

## Animations

`Config.Animations` controls the put-on, take-off and open animations.
Set `enabled = false` to turn them off, or swap the dict/anim for your
own. `freeze = true` locks the player in place for the duration.

Animations do not play on spawn, only on an actual equip or unequip.

---

## Where bag models live

Models do **not** have to be in this resource. `Config.Backpacks` only stores
a model **name** — the script calls `RequestModel` on it like any other GTA
model, so it works no matter which resource streams it.

Two options:

**A. Drop them in `nayzeee-backpack/stream/`**
Add one line to fxmanifest.lua per ytyp:
```lua
data_file 'DLC_ITYP_REQUEST' 'stream/your_bag.ytyp'
```

**B. Keep them in your own stream resource** (recommended if you already
have one, or if you buy bags from different creators)
```
my-backpack-props/
├─ fxmanifest.lua      <- declares its own DLC_ITYP_REQUEST lines
└─ stream/
   ├─ vonnie_backpack_lean.ydr
   ├─ vonnie_backpack_lean.ytd
   └─ vonnie_backpack_lean.ytyp
```
Then in this script, just reference the name:
```lua
['backpack_lean'] = {
    label = 'Lean Backpack',
    model = 'vonnie_backpack_lean',
},
```
Nothing else changes. Updating nayzeee-backpack never touches your models.

If a model isn't streaming, the tuner and the client both print a clear
console line naming the model rather than failing silently.

## Adding a bag, start to finish

1. Stream the model (either option above).
2. Add an entry to `Config.Backpacks` with the model name.
3. Add the matching item to `ox_inventory/data/items.lua`.
4. `Config.Debug = true`, `/bagtune`, pick the bag, tune it, hit Copy.
5. Paste the offset in, set Debug back to false.

Most bags built from the same clothing base need no tuning at all — step 4
is only for the ones that sit wrong.

---

## Physical drop

`Config.Drop` — the bag hits the ground as its **own model**, not a generic
ox_inventory bag. Anyone can loot it.

```lua
Config.Drop = {
    enabled      = true,
    onDeath      = true,   -- drop when the player dies
    onRob        = true,   -- robbery drops it rather than handing it over
    despawn      = 900,    -- seconds (0 = never)
    keepContents = true,   -- false wipes the stash on drop
}
```

`onRob = true` is the better setup: the robber still has to pick the bag up,
so there's a window where a third party can grab it or the victim can fight
back for it.

## Weight affects movement

Off by default. `Config.WeightEffects.enabled = true` to opt in.

Penalties scale off **how full the bag is**, not its capacity — an empty
duffel costs nothing, a stuffed one hurts.

```lua
Config.WeightEffects = {
    enabled       = false,
    threshold     = 0.5,   -- nothing happens below 50% full
    minMoveRate   = 0.88,  -- movement multiplier at 100% full
    staminaDrain  = 2.0,   -- stamina drains this much faster at full
    noSprintAbove = 0.0,   -- 0.85 would block sprinting past 85% full
}
```

## Robbery

`Config.Robbery` — take a bag off someone's back. It's already visible on
their ped, which is what makes it work.

```lua
Config.Robbery = {
    enabled        = true,
    requireHandsUp = true,   -- victim must have hands up
    requireCuffed  = false,  -- or be cuffed
    allowDead      = true,   -- dead players can always be looted
    requireWeapon  = true,   -- robber needs a weapon out
    distance       = 2.0,
    duration       = 5000,
    cooldown       = 30,     -- seconds per victim, stops farming
    policeEvent    = nil,    -- set an event name to alert PD
}
```

Uses ox_target on players when available, `/robbag` as a fallback.

**Server-side checks** — distance, cooldown, whether the victim actually
holds the bag, and whether it's a real configured backpack are all verified
on the server. The client only asks.

If the robber's inventory is full, the bag drops at their feet rather than
vanishing.

---

## Placeable bags

`Config.Placement` — set a bag down as a world prop that stays put and stays
lootable. Dead drops, stash points, chop shops.

Third-eye yourself and pick **Set down**, or use the `/placebag` keybind. You
get a ghost preview: **scroll** to rotate, **E** to place, **X** to cancel.

Placed bags get their own ox_target options — **Open** and **Pick up**.

```lua
Config.Placement = {
    enabled      = true,
    maxDistance  = 3.0,
    ownerOnly    = false,  -- true = only the placer can pick it back up
    pickupAnyone = true,   -- false = lootable but it stays put
    persist      = true,   -- survives a restart (needs oxmysql)
    despawn      = 0,      -- seconds (0 = never)
    maxPerPlayer = 3,
}
```

**Persistence** needs `install.sql` run against your database. Without
oxmysql the script warns on start and keeps placed bags in memory only.

Server verifies distance, ownership, the per-player cap, and the one-bag
rule on pickup. Client coords are never trusted.

## Prompts and keybinds

`Config.Prompts` holds every label so you can rewrite or translate them.

Third-eye **yourself** for:
- **Open backpack**
- **Set down**

Keybinds (bindable in FiveM settings, unbound by default):
- `/openbag` — open the bag you're wearing
- `/placebag` — start placement mode
- `/robbag` — fallback robbery if ox_target isn't installed

Set `Config.Prompts.useTarget = false` to disable the ox_target options and
use keybinds only.

---

## Context menu (v1.6)

Using the bag item opens an ox_lib context menu rather than jumping
straight into the stash:

- **Open backpack** — shows slots and weight in the description
- **Set down** — asks private or public, then starts placement mode
- **Take off / Put on** — stows the bag

`Config.Prompts` holds every label for translation.

## Private and public placed bags

When setting a bag down the player picks:

- **Private** — only they can open or pick it up
- **Public** — anyone can

The owner can flip it later with a third-eye option on the placed bag
(`Config.Placement.allowRetoggle`). Ownership is by ESX identifier, so it
survives a reconnect.

```lua
Config.Placement = {
    askAccess     = true,
    defaultAccess = 'private',
    allowRetoggle = true,
}
```

Access is enforced **server-side** on both open and pickup. Each client is
told separately whether a placed bag is theirs, so the target options
differ per player without leaking ownership.

## Taking the bag off

A stowed bag stays in the inventory and stays usable — it just isn't on
the player's back.

⚠️ **Decide this one deliberately:**

```lua
Config.Robbery.allowStowed = true
```

With `false`, taking your bag off hides it from robbers completely, and
players will use that to dodge robberies entirely — it makes the whole
robbery system opt-out. `true` (the default) means a stowed bag can still
be taken, which keeps it honest.

---

## Logging

`Config.Logs` — every event logs to the **server console** regardless, and to
a **Discord webhook** if you set one.

```lua
Config.Logs = {
    enabled = true,
    webhook = '',          -- empty = console only

    events = {
        equip    = false,  -- noisy
        open     = false,  -- noisy
        stow     = false,
        rob      = true,
        drop     = true,
        place    = true,
        pickup   = true,
        access   = false,
        contents = true,   -- snapshot what was inside
    },
}
```

**Why `contents = true` matters.** Robbery and death drops are what you'll be
asked to adjudicate. The snapshot is taken *before* the bag changes hands, so
you can see exactly what was inside at the moment it was taken — otherwise
you're taking someone's word for it.

Every entry includes the player's **licence identifier**, not just their name,
so a name change doesn't break the trail.

`open` and `equip` are off by default because they fire constantly. Turn them
on only while investigating something specific.

---

## Getting a placed bag back

Two ways, so a bag is never stranded:

**With ox_target** — third-eye the placed bag for Open, Pick up, and
Make private/public if it's yours.

**Without ox_target** (or with `Config.Prompts.useTarget = false`) — walk
within 2m and a `[E] Backpack` prompt appears. Pressing E opens the same
menu.

There's also a `/bagnearby` keybind that works either way, bindable in
FiveM settings.

The menu greys out what you can't do rather than hiding it — a private bag
that isn't yours shows Open as **Locked** and Pick up as **Not yours**, so
players understand *why* rather than wondering where the option went.

Picking a bag up puts it straight back in your inventory and on your back.

---

## Bag Store

`Config.Shop` — the bag is spawned as a **real prop floating in front of the
player and spun** while they browse. What they see is exactly what they get.

**Filters** are two rows: **Theme** (realistic, cartoon, animal, halloween)
and **Type** (backpacks, pocketbooks, duffels). Both come straight off each
bag's `theme` and `category` fields, so adding a bag adds it to the shop with
no shop config to touch.

A bag with no `price` is not sold in the store.

```lua
['backpack'] = {
    label    = 'Polar Bear Backpack',
    model    = 'nayzeee_backpack_016',
    category = 'backpack',
    theme    = 'animal',
    price    = 2500,
    slots    = 8,
    weight   = 10000,
},
```

Selecting a skin swaps the texture on the spinning prop live.

**Locations** take coords, a heading, an optional shop ped and blip. ox_target
on the ped when available, `[E]` proximity prompt otherwise.

```lua
Config.Shop = {
    currency = 'cash',   -- or 'bank'
    canSell  = true,
    sellRate = 0.5,      -- fraction returned when selling back
}
```

**Server-side checks:** price is read from the config, never from the client;
funds, carry space and the one-bag rule are all verified; the payment is
refunded if the item can't be added. Selling a bag with contents is blocked
so nobody wipes their own stash by accident.

---

## Shop access modes

```lua
Config.Shop.openMode = 'ped'  -- 'ped' | 'command' | 'both'
```

- **`ped`** — physical store. A shop keeper (or a marker, if you leave `ped`
  as nil) at each entry in `Config.Shop.Locations`.
- **`command`** — no physical store at all. `/bagstore` from anywhere.
  Locations are ignored entirely.
- **`both`** — a store exists *and* the command works.

```lua
Config.Shop.command     = 'bagstore'
Config.Shop.commandJobs = nil          -- or { 'police', 'mechanic' }
Config.Shop.keybind     = false        -- true = also rebindable in FiveM settings
```

`commandJobs` restricts the command to specific ESX jobs. Useful if the store
is meant to be a job perk rather than open to everyone.

Locations without a `ped` draw a marker instead and use an `[E]` prompt, so
you can run a discreet back-alley store with no NPC standing there.

## Turning filters off

```lua
Config.Shop.useThemes     = true   -- false hides the theme row entirely
Config.Shop.useCategories = true   -- false hides the type row
Config.Shop.showSearch    = true
```

Trim the `Themes` list to only what your server uses, or switch it off for a
plain catalogue. The UI adapts — hidden rows don't leave a gap.

## Large catalogues

With 40+ bags the search box does the heavy lifting. It matches the **label,
the model name, and the theme**, so `croc`, `pocketbook` or `halloween` all
narrow the list. A count above the grid shows "12 of 43" when filtered.

---

## Job-only bags

Add a `job` field and the bag becomes part of that job's kit. It only shows in
the shop for players on that job, and only they can wear it.

```lua
['bag_police'] = {
    label    = 'Patrol Pack',
    model    = 'nayzeee_bag_police',
    category = 'backpack',
    theme    = 'realistic',
    job      = 'police',          -- or { 'police', 'sheriff', 'state' }
    grade    = 0,                 -- minimum job grade
    price    = 0,                 -- 0 shows as "Issued" with a Collect button
    slots    = 14,
    weight   = 20000,
},
```

In the shop a **VIEW** row appears with **Store** and **Issued (n)**. Job bags
never appear in the normal store view, and a mechanic never sees police bags
at all — they aren't in their catalogue.

`price = 0` renders as *Issued / Free / Collect* and the sell option is hidden,
so nobody cashes out department kit.

**Enforced server-side in three places:** buying, wearing, and on job change.
Going off duty or getting fired takes the bag off your back immediately.

```lua
Config.Shop.useJobTab   = true
Config.Shop.jobTabLabel = 'Issued'
```

## Performance

Every thread idles long and only drops to per-frame when it has something to
do. Notable gates:

| Thread | Idle | Runs per-frame when |
|---|---|---|
| Vehicle visibility | 2000ms | wearing a bag (500ms) |
| Placed-bag prompt | 800ms | standing next to a placed bag |
| Shop marker | 1200ms | within 15m of a marker location |
| Shop prompt | 900ms | within 2.5m of a store |
| Weight penalty | 1000ms | over the fill threshold, on foot |
| Studio camera | 1000ms | studio open (`Config.Debug`) |

The studio and its icon HUD thread only exist when `Config.Debug = true` — ship
with it **false** and that code never loads.
