# nayzeee-chainsnatch 1.1 — install & guide

Chains you can buy, craft, wear, flex, throw, set down, give, swap and snatch. Any chain **clothing** you download is
converted into a **prop** by the built-in converter (chainkit), with every texture kept.

## 1. Dependencies

| Required | Optional |
|---|---|
| `ox_lib` | `ox_target` or `qb-target` (third-eye options) |
| `ox_inventory`, `qb-inventory` or `qs-inventory` (item metadata) | `screenshot-basic` (icon studio) |
| ESX, QBCore, Qbox (or none, with ox_inventory) | |

```
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure screenshot-basic
ensure nayzeee-chainsnatch
ensure nayzeee-chainprops      # created by the converter the first time it builds
```

Admins need the studio permission (or be in an admin group, `config_server.lua`):

```
add_ace group.admin nayzeee.chains allow
```

The converter creates and restarts `nayzeee-chainprops` by itself. Let it run those commands:

```
add_ace resource.nayzeee-chainsnatch command.refresh allow
add_ace resource.nayzeee-chainsnatch command.ensure allow
add_ace resource.nayzeee-chainsnatch command.restart allow
```

If the console says *could not write into ox_inventory/web/images*, your FXServer build restricts
cross-resource writes. Add this and restart:

```
add_filesystem_permission nayzeee-chainsnatch write ox_inventory
```

## 2. The item

One item for **every** chain: `install/ox_inventory.lua` (or `install/qb-core.lua`). Which chain it is, its
texture, its name and its picture are in the metadata, so new chains never need new items.

## 3. Add chains

1. Put each chain in `chains/<Chain Name>/`: its `.ydd` and every `_diff_` `.ytd` texture.
2. `/chainstudio` → **Convert** → **Build**. (On start, `AutoScan` + `AutoBuild` do this for you.)
3. **Fit** tab → **From clothing** → nudge if needed → **Save**. Or press *From clothing for every unfitted chain*.
4. Pictures: chainkit already drew one per texture. For nicer ones: **Icon** tab → *Every chain*.

`/givechain [id] [name]` gives one, `/chainlist` lists them all.

### Crafting materials

The store's **Craft** tab pays in items instead of money (`Config.Store.Craft`, `gold_bar` + `diamond` by
default). Use items your server already has, or add them to your inventory.

### Chains people wear as clothing

Chains in your clothing packs (`mp_m_freemode_01_pack^teef_###_u.ydd`) can be converted too:
list those resources in `Config.Convert.ScanResources`. The accessory slot also holds ties and scarves, so name
the chain packs instead of scanning everything. Once converted, a chain someone wears from the clothing store
can be **snatched**: it comes off their outfit and the snatcher gets it as an item (`Config.Snatch.Clothing`).
Hook your appearance script into `Config.OnClothingChainRemoved` so it's saved.

---

## The converter (chainkit)

`tools/chainkit` is a small CodeWalker.Core program the server runs. For each chain it:

- reads the high detail mesh out of the clothing `.ydd`, strips the rigging
- moves the pivot to the **centre of the chain** (so it turns in place, sits right on a table and in the
  hand) and remembers where it sat on the body, which is what **From clothing** uses
- keeps the chain's own normal + specular maps (`normal_spec`), so gold and diamonds still shine
- makes **one prop per texture** (`_a_`, `_b_`, …): props can't swap textures the way clothing does
- writes `nayzeee-chainprops/stream/*.ydr`, one `nzc_chains.ytyp`, `chainmap.json` and an icon per prop,
  loads every file back to check it, and only rebuilds what changed

Ready-to-run programs for Linux and Windows go in `tools/chainkit/linux-x64` and `tools/chainkit/win-x64`
(in the release zip). See [`tools/README.md`](tools/README.md) to build them yourself.

## The studio — `/chainstudio` (admin)

**Fit** — *On the neck* and *In the hand*, each with:
- **Start from**: *From clothing* (exactly where the clothing sat), *Neck*, *Long chain*; in the hand
  *Dangle right / left*, *In the fist*
- **Move** left/right, forward/back, up/down (relative to the character) with step sizes; hold to repeat
- **Rotate** Turn / Tilt / Lean around the **chain's own centre**
- **Bone**, **Exact values**, *config.lua* copy, *Last saved*, *Default*
- **Pose** preview for the hand fit
- Keys: arrows / PgUp / PgDn move, Q E turn, R F tilt, Z C lean, SHIFT ×5, ALT fine, CTRL+S save,
  drag to orbit, scroll to zoom

Fits are saved **per body**: on a male ped you save the male fit, on a female ped the female one (each falls
back to the other). Everything goes to `data/overrides.json` and reaches every player live.

**Look** — name, value, a name per texture (Gold, Iced, …), *Put one in my pockets*.

**Icon** — the backpack icon studio for chains: chroma box under the map, backdrop and angle chips, zoom,
*This chain* / *Every chain* (every texture). Keyed in the NUI, saved to `icons/` and `ox_inventory/web/images`
as `<prop>.png`, which is what the item's `metadata.image` points at.

**Convert** — what's new / changed / removed, *Check again*, *Build*, *Rebuild all*, *Redraw icons*, live progress.

---

## Playing

| | |
|---|---|
| **Wear** | use the item, or `/chain` (K) → *Put on*. Wearing takes it out of your pockets, so it can't be dropped or duped while on. Stays on through relogs. |
| **Take off** | `/chain` → *Take off* |
| **Hold up** | `/chain` → *Hold up* (or `/chainhold`). Everyone sees it in your hand. **G** throw, **E** set down, **BACKSPACE** put it back on |
| **Throw** | aims where you look, arcs, bounces off walls. Lands on the ground, or a player standing there **catches** it |
| **Set down** | ghost follows where you look: **E** place, **SCROLL** turn (SHIFT fine), **↑ ↓** tilt, **BACKSPACE** cancel. Works from the neck, the hand or straight from your pockets |
| **Pick up** | third-eye the chain (*Pick up*, *Pick up & wear*) or **E** without a target script |
| **Wear someone else's** | it's just an item: snatch it, catch it, pick it up, put it on |
| **Give / swap** | `/chain` → *Give*, *Put it on them*, *Swap chains*; they accept with **Y** |
| **Snatch** | third-eye a player → *Snatch Chain* (or `/snatch`). A tug of war: both mash **SPACE**, the server moves the rope. Grab from behind for a head start. Cuffed / hands up / downed players can't fight back. 15% of the time the chain **snaps** and hits the floor for anyone to grab |

## The jewelry store

Walk up to the jeweller (or `/chainstore`): the camera moves over the counter and the chains float above it
on a tilted display. **A / D**, the arrows or the wheel browse, drag spins, **T** tries it on your character,
**ENTER** buys, **ESC** leaves. Set the spot with `/chainstorehere` (admin) → `Config.Store.Locations`.

| Tab | |
|---|---|
| **Buy** | cash or bank (`Config.Store.Currency`). Price per chain in the studio's Look tab |
| **Craft** | the same chain for materials instead of money |
| **Repair** | chains that **snapped** in a snatch come off *broken*: they can't be worn until the jeweller fixes them (`Config.Store.Repair`) |

### Exclusive chains (tied to a game license)

Studio → **Look** → **Owners** → pick the player(s). From then on:

- only those players' **game licenses** see the chain in the store, and only they can buy it (the server
  checks the license on every purchase; other players never even receive the owners' licenses)
- anyone else can only get one by **snatching** it from them, or if an owner **gives** it away
- the item says who it was made for, and who it was snatched from

No owners = anyone can buy it. Untick *For sale* to take a chain out of the store completely.

## Giving

`/chain` → **Give**, **Put it on them** (straight on their neck, theirs goes in their pockets) or **Swap chains**
(you both wear one: couples). Pocket chains have a give button too. The other player gets a prompt:
**Y** accept, **X** decline (rebindable). Nothing moves until they accept.

## illenium-appearance

Chains converted from a clothing pack are jewellery now: the clothing store won't put them on and says
*"This chain must be purchased at the jewelry store."* Install the 3-step addon in
[`install/illenium-appearance`](install/illenium-appearance/README.md). Other clothing scripts:
`Config.Appearance.Enforce` takes a jewellery chain back off within two seconds.

## Exports (server)

```lua
exports['nayzeee-chainsnatch']:GetWornChain(src)          -- { chain, variant, label, metadata, holding } | nil
exports['nayzeee-chainsnatch']:GiveChain(src, key, letter)
exports['nayzeee-chainsnatch']:TakeWornChain(src)         -- takes it off, returns its metadata (yours to keep)
exports['nayzeee-chainsnatch']:DropChain(metadata, coords)
exports['nayzeee-chainsnatch']:GetChains()
```

Client: `exports['nayzeee-chainsnatch']:IsJewelleryDrawable(ped, drawable)` (accessory slot 7), used by the
illenium addon.

## Performance

| Thread | Idle | Busier when |
|---|---|---|
| Everyone's chains | 2000ms | someone in range wears one (500ms; statebag changes redraw at once) |
| Chains on the ground | 3000ms | some placed (1500ms) |
| Placing / holding / tug | — | only while you do it |
| Studio / icon box | — | studio open |

Converting runs in its own process, so the server thread never waits on it.
