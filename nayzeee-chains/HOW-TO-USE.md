# NayZeee Chains — how to use it

## The idea in 30 seconds

Chains you download for FiveM are **clothing**: a `.ydd` file (the model) and one `.ytd` file per colour.
Clothing can't be held up, thrown, put on a table or snatched. So the script **turns every chain into a prop
for you**. You never open CodeWalker and you never write config for a chain.

If you know nayzeee-backpack, this is the difference:

| | nayzeee-backpack | nayzeee-chains |
|---|---|---|
| The models | come as props, you add `.ydr` / `.ytd` / `.ytyp` + a config entry | you drop the **clothing files** in a folder, the script makes the props |
| Items | one item per bag | **one item for every chain** (`nz_chain`), paste it once |
| Fitting | `/bagstudio` | **automatic**: the chain sits exactly where the clothing sat (studio only to change it) |
| Pictures | icon studio | drawn **automatically** when a chain is converted (icon studio for nicer ones) |

You only install **one folder**, `nayzeee-chains`. The script makes the second one by itself:

| Folder | What it is |
|---|---|
| `nayzeee-chains` | the script, the UI and the converter (`tools/chainkit`) |
| `nayzeee-chainprops` | the chain props. **Created by the script** the first time it converts a chain, next to `nayzeee-chains`, and restarted by it after every build. Don't edit it, don't put files in it |

---

## Install (once)

1. Put `nayzeee-chains` in your `resources` (`nayzeee-chainprops` appears next to it after the first build).
2. Add this to `server.cfg`:

   ```
   ensure ox_lib
   ensure ox_inventory
   ensure screenshot-basic
   ensure nayzeee-chains

   add_ace group.admin nayzeee.chains allow
   add_ace resource.nayzeee-chains command.refresh allow
   add_ace resource.nayzeee-chains command.ensure allow
   add_ace resource.nayzeee-chains command.restart allow

   add_unsafe_child_process_permission "nayzeee-chains"
   add_filesystem_permission nayzeee-chains write ox_inventory
   add_filesystem_permission nayzeee-chains write nayzeee-chainprops
   ```

   - **Don't** add `ensure nayzeee-chainprops`: the script starts it itself, right after it has converted any new
     chains, so a new chain shows up after **one** restart. (With the ensure line it starts too early and new chains
     need a second restart.)
   - The three `add_ace resource…` lines let the script start and restart `nayzeee-chainprops` after it converts a chain.
   - `add_unsafe_child_process_permission` lets it run the converter (newer FXServer builds block this by default:
     without it the console says *could not start chainkit: Access to this API has been restricted*).
   - The two `add_filesystem_permission` lines let it put the chain pictures into ox_inventory and nayzeee-chainprops.
   On the very first start the console may say it can't find `nayzeee-chainprops`: that's fine, it doesn't exist
   until the first chain is built.
3. Open `install/ox_inventory.lua` and paste the item into `ox_inventory/data/items.lua`.
   (qb-inventory / qs-inventory: `install/qb-core.lua`.)
4. Restart the server. In game, `/chainstudio` opens the studio.

---

## Add a chain (every time, 3 steps)

**1. Make a folder** in `nayzeee-chains/chains/`, named what players should see:

```
nayzeee-chains/chains/
└─ Diamond Cuban Chain/
   ├─ teef_000_u.ydd              ← the model
   └─ teef_diff_000_a_uni.ytd     ← colour A
```

**2. Put the chain's files in it**: the `.ydd` and **every** `.ytd` that came with it. A chain with three
colours has three `.ytd` files (`_a_`, `_b_`, `_c_`): put them all in, each becomes its own look.
Don't rename them, and don't put them in a `stream` folder.

- **Male and female files in one download?** Leave them together in the same folder: they become two chains,
  *Name (Male)* and *Name (Female)*, each with its own textures.
- **The folder is the chain's id.** To change the name players see later, use the studio's **Look** tab.
  Renaming the folder makes it a *new* chain (the old one is kept, nothing is lost).
- Subfolders are fine (`Cuban Pack/stream/…`): the name comes from the first folder that isn't `stream`, `male` …

**3. Build it.** Restart the server: new chains are converted on start, before the props load, so one restart is
enough. Or in game, without a restart: `/chainstudio` → **Convert** tab → **Build**, wait for *"Converted 1 chain(s)"*.

That's it: **no fitting needed**. Try it: **Look** tab → **Put one in my pockets**, or `/givechain [id] diamond`.

> **How does it fit itself?** Clothing is rigged to one of the character's bones (the upper spine), relative to where
> that bone sits in the skeleton's rest pose. The script knows that rest pose and the converter remembers the bone and
> where the chain sat, so the prop is stuck to the same bone with the clothing's exact offset. It moves like the
> clothing did, for male and female bodies, and nothing extra is streamed: the chain is still one small prop, so it
> never fights your clothing packs.

Optional, all in the studio:

- **Look** tab: the store price, a name per colour (*Gold*, *Iced* …), for sale or not
- **Fit** tab → **In the hand**: how it sits when someone holds it up
- **Icon** tab: a nicer inventory picture (the converter already drew one)
- **Fit** tab: only if you want a chain to sit differently than the clothing did (a saved fit always wins).
  Fits are saved **per body**: fit it again on a female ped for female players. In the chain list, an outlined
  **N** means "fits itself", a filled one "saved in the studio"

---

## A custom chain for one player

A player paid for their own chain (a name pendant, a crew piece …):

1. Add it like any chain (above).
2. **Look** tab → **Owners** → click their name if they're online, or paste their **license** if they
   aren't (txAdmin → Players → their name → `license:…`).
3. Set the price → **Save**.

Now only that player sees it in the jewelry store, and only they can buy it. Anyone else can only get it by
**snatching it** from them, or if they **give** it to someone. The item says *made for [name]*.

Want to hand it over for free instead? `/givechain [their id] "chain name"`.

---

## Chains already in your clothing store (optional)

If your server already has chains in a clothing pack and you want them sold at the jewelry store instead:

1. `config.lua` → `Config.ScanResources = { 'your_clothing_resource' }` → restart `nayzeee-chains`
   (the config is read on start, so a Build alone won't see the change).
2. Add the chains to block to `Config.Appearance.Block`. The studio's **Look** tab shows the exact line to paste.
3. illenium-appearance: install the small addon in `install/illenium-appearance` (3 steps, its README).

Nothing in your clothing packs is blocked unless you list it.

---

## Commands

| Command | Who | |
|---|---|---|
| `/chainstudio` | admin | fit, name, price, owners, icons, convert |
| `/givechain [id] [name]` | admin / console | give a chain (part of the name is enough) |
| `/chainlist` | admin / console | every chain and its key |
| `/chainstorehere` | admin | prints where you stand, for `Config.Store.Locations` |
| `/chain` (K) | everyone | the chain menu (also opens when you use the chain in your inventory): put on / take off, hold up, set down, hand to someone, put it on them, swap |
| `/snatch` | everyone | snatch the chain of the player in front of you |

---

## Something's wrong?

| You see | Do this |
|---|---|
| *chainkit isn't installed* | `tools/chainkit/linux-x64/chainkit` (Linux) or `tools/chainkit/win-x64/chainkit.exe` (Windows) is missing. It's in the release zip |
| A chain didn't convert | the **Convert** tab lists it under *Couldn't convert* with the reason (also in the server console). Usually: its `_diff_` `.ytd` files aren't in its folder |
| *N chain(s) have no files any more* | their folder was moved, renamed or emptied (an update). They're **kept**, so nobody loses one. Put the files back, or press **Remove gone chains** |
| The chain is invisible / *model is not registered* | `nayzeee-chainprops` isn't started: check the `add_ace` lines (the console says why it didn't start), restart |
| A new chain only shows after a **second** restart | take `ensure nayzeee-chainprops` out of `server.cfg`: the script starts it after converting |
| The chain sits wrong on the neck | the studio has a saved fit for it: **Fit** tab → red **×** (forget the saved fit). It then fits itself |
| No picture on the item | restart `ox_inventory` once after the first build (it loads new pictures on start) |
| *could not start chainkit: Access to this API has been restricted* / *child spawn not allowed* | add `add_unsafe_child_process_permission "nayzeee-chains"` to `server.cfg` and restart |
| *No room in your pockets* with empty pockets | the console prints `inventory: ox_inventory` a few seconds after start: if it says anything else, `ensure ox_inventory` above `ensure nayzeee-chains` |
| *could not write into ox_inventory/web/images* | add `add_filesystem_permission nayzeee-chains write ox_inventory` to `server.cfg` |
| Looks right on men, wrong on women | the chain was made for men only: fit it on a female ped and **Save** (fits are per body) |

**Updating the script?** Keep these three folders from your old copy: `chains/` (your chain files), `data/` (fits,
prices, owners, chains on the ground) and `icons/` (studio pictures). Replace everything else.
