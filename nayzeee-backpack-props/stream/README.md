# nayzeee-backpack-props / stream

Bag models, textures and animations for **nayzeee-backpack**. Props only, no
code: restarting the script never re-streams these.

```
stream/
├─ nayzeee_backpack.ytyp
├─ nayzeee_backpack_cutebear/
│  ├─ nayzeee_backpack_cutebear.ydr
│  ├─ nayzeee_backpack_cutebear.ytd
│  └─ nayzeee_backpack_cutebear.ytyp
├─ ... one folder per bag ...
├─ duffel/                      BzZz open duffels (renamed, never escrowed)
└─ anims/
   ├─ nayzeee_grab_cash_01.ycd  BzZz cash grab (renamed, never escrowed)
   ├─ clementine@withyourbag01.ycd … 05.ycd
   └─ f_modelpose_withbag_1@avenelanim.ycd
```

## Adding a bag

Drop its `.ydr` (model), `.ytd` (textures) and `.ytyp` (archetype) in a new
folder here. That's it for this resource: `fxmanifest.lua` registers every
`.ytyp` in `stream/` by itself. Then add the bag to `Config.Backpacks` in
nayzeee-backpack.

If the console says *model is not registered*, the `.ytyp` is missing or its
archetype name doesn't match the `.ydr`'s file name.

## Converting a clothing bag

Bags made as clothing (`.ydd` + a `.ytd` per colour, e.g. `hand_000_u.ydd`,
`hand_diff_000_a_uni.ytd`) aren't props yet. `tools/convert_bag.sh` turns one
into a prop: removes the ped skinning, swaps the ped shaders for prop shaders,
makes every colour a small texture pack sharing one model, shrinks textures
to 1024 with mipmaps and writes the `.ytyp`:

```
tools/convert_bag.sh nayzeee_bag_mybag hand_000_u.ydd hand_diff_000_a_uni.ytd hand_diff_000_b_uni.ytd
```

It needs the .NET 8 SDK, Python 3 with Pillow + numpy, and CodeWalker's
source (see the top of the script). `tools/render_bag.py` and
`tools/variants_sheet.py` draw the result (every colour) so you can check it
before it goes in game.

## Nayzeee originals (bagforge)

Barrel Bag, Dome Satchel, Croc Top-Handle, Sweetheart Tote, Crochet Hobo and
Velvet Weekender, plus the Graffiti, Split Check, Drip and Monogram
backpacks, are built entirely from code in `tools/bagforge`: shapes in
`designs.py`, materials (leather, patent, croc, velvet, crochet, tartan,
prints) in `textures.py`, and the colour list in `catalog.py`. To change a
colour or add one, edit `catalog.py` and rebuild:

```
tools/forge_bags.sh              # every bag
tools/forge_bags.sh barrel       # just one
```

Then match the `variants` list in `Config.Backpacks`. Handbags pivot on the
top of their handles, so the purse hold grips them by the handles. Backpacks
sit where the converted clothing backpacks do, so they use the default worn
fit; their texture layout (front art, back, sides, label patch) is in
`packtex.py`. Worn, their straps wrap over the shoulders and under the arms;
each also has a `<model>_loose.ydr` twin with the straps lying flat, and a
`<colour>_loose` archetype per colour that reuses that colour's `.ytd`. The
script shows the loose twin whenever the bag isn't on a back (`loose = true`
in `Config.Backpacks`).

## Poses

`.ycd` files anywhere in `stream/` just work. The dict / clip names are set in
`Config.Carry.Poses`:

| dict | clip |
|---|---|
| `clementine@withyourbag01` … `05` | `withyourbag01_clip` … `05` |
| `f_modelpose_withbag_1@avenelanim` | `f_modelpose_withbag_1_clip` |

The Clementine poses are licensed one copy per server: don't commit them to a
public repo.

## BzZz duffels

`duffel/` and `anims/nayzeee_grab_cash_01.ycd` are BzZz's (bzzz_money), used
with permission and renamed so they never clash with an installed
bzzz_money. To rebuild them from a newer bzzz_money:

```
python3 tools/rename_bzzz.py <path to bzzz_money> stream
```
