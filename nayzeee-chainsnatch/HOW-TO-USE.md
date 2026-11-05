# Chain Snatch — how to use it

## The idea in 30 seconds

Chains you download for FiveM are **clothing**: a `.ydd` file (the model) and one `.ytd` file per colour.
Clothing can't be held up, thrown, put on a table or snatched. So the script **turns every chain into a prop
for you**. You never open CodeWalker and you never write config for a chain.

If you know nayzeee-backpack, this is the difference:

| | nayzeee-backpack | nayzeee-chainsnatch |
|---|---|---|
| The models | come as props, you add `.ydr` / `.ytd` / `.ytyp` + a config entry | you drop the **clothing files** in a folder, the script makes the props |
| Items | one item per bag | **one item for every chain** (`nz_chain`), paste it once |
| Fitting | `/bagstudio` | `/chainstudio`, one click: **From clothing** |
| Pictures | icon studio | drawn **automatically** when a chain is converted (icon studio for nicer ones) |

It comes as two folders:

| Folder | What it is |
|---|---|
| `nayzeee-chainsnatch` | the script, the UI and the converter (`tools/chainkit`) |
| `nayzeee-chainprops` | the chain props. **Made by the script**: don't edit it, don't put files in it |

---

## Install (once)

1. Put both folders in your `resources`.
2. Add this to `server.cfg`:

   ```
   ensure ox_lib
   ensure ox_inventory
   ensure screenshot-basic
   ensure nayzeee-chainsnatch
   ensure nayzeee-chainprops

   add_ace group.admin nayzeee.chains allow
   add_ace resource.nayzeee-chainsnatch command.refresh allow
   add_ace resource.nayzeee-chainsnatch command.ensure allow
   add_ace resource.nayzeee-chainsnatch command.restart allow
   ```

   The last three let the script restart `nayzeee-chainprops` by itself after it converts a chain.
3. Open `install/ox_inventory.lua` and paste the item into `ox_inventory/data/items.lua`.
   (qb-inventory / qs-inventory: `install/qb-core.lua`.)
4. Restart the server. In game, `/chainstudio` opens the studio.

---

## Add a chain (every time, 4 steps)

**1. Make a folder** in `nayzeee-chainsnatch/chains/`, named what players should see:

```
nayzeee-chainsnatch/chains/
└─ Diamond Cuban Chain/
   ├─ teef_000_u.ydd              ← the model
   └─ teef_diff_000_a_uni.ytd     ← colour A
```

**2. Put the chain's files in it**: the `.ydd` and **every** `.ytd` that came with it. A chain with three
colours has three `.ytd` files (`_a_`, `_b_`, `_c_`): put them all in, each becomes its own look.
Don't rename them, and don't put them in a `stream` folder.

**3. Build it.** In game: `/chainstudio` → **Convert** tab → **Build**. Wait for *"Converted 1 chain(s)"*.
(Or just restart the server: new chains are built on start.)

**4. Fit it.** **Fit** tab → **From clothing** → nudge it if needed → **Save**. That's it.

Try it: **Look** tab → **Put one in my pockets**, or `/givechain [id] diamond`.

Optional, all in the studio:

- **Look** tab: the store price, a name per colour (*Gold*, *Iced* …), for sale or not
- **Fit** tab → **In the hand**: how it sits when someone holds it up
- **Icon** tab: a nicer inventory picture (the converter already drew one)
- Fits are saved **per body**: fit it again on a female ped for female players

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

1. `config.lua` → `Config.Convert.ScanResources = { 'your_clothing_resource' }` → restart (or **Build**).
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
| `/chain` (K) | everyone | the chain menu: take off, hold up, set down, give, swap |
| `/snatch` | everyone | snatch the chain of the player in front of you |

---

## Something's wrong?

| You see | Do this |
|---|---|
| *chainkit isn't installed* | `tools/chainkit/linux-x64/chainkit` (Linux) or `tools/chainkit/win-x64/chainkit.exe` (Windows) is missing. It's in the release zip |
| Build says *no texture (.ytd) found* | the `.ytd` files aren't in the chain's folder |
| The chain is invisible / *model is not registered* | `nayzeee-chainprops` isn't started: check the `ensure` and `add_ace` lines, restart |
| The chain floats in front of the neck when they run | it isn't fitted yet: **Fit** → **From clothing** → **Save** |
| No picture on the item | restart `ox_inventory` once after the first build (it loads new pictures on start) |
| *could not write into ox_inventory/web/images* | add `add_filesystem_permission nayzeee-chainsnatch write ox_inventory` to `server.cfg` |
| Looks right on men, wrong on women | fit it again on a female ped and **Save**: fits are per body |

Keep `nayzeee-chainsnatch/data/` when you update the script: your fits, prices and owners are in it.
