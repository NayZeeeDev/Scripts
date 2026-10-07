# stream/

Put your bag models and purse poses here. (They're kept out of git because of size.)

```
stream/
├─ nayzeee_backpack.ytyp
├─ nayzeee_backpack_cutebear/
│  ├─ nayzeee_backpack_cutebear.ydr
│  ├─ nayzeee_backpack_cutebear.ytd
│  └─ nayzeee_backpack_cutebear.ytyp
├─ ... one folder per bag ...
└─ anims/
   ├─ clementine@withyourbag01.ycd
   ├─ clementine@withyourbag02.ycd
   ├─ clementine@withyourbag03.ycd
   ├─ clementine@withyourbag04.ycd
   ├─ clementine@withyourbag05.ycd
   └─ f_modelpose_withbag_1@avenelanim.ycd
```

## Models

Every bag needs **three** files: `.ydr` (model), `.ytd` (textures) and `.ytyp`
(archetype). Each `.ytyp` also needs a line in `fxmanifest.lua`:

```lua
data_file 'DLC_ITYP_REQUEST' 'stream/your_bag/your_bag.ytyp'
```

Miss either and the console says *model is not registered* even though the
`.ydr` is there.

## Poses

The `.ycd` files just need to be anywhere in `stream/`; no manifest line. The
dict / clip names are already set in `Config.Carry.Poses`:

| dict | clip |
|---|---|
| `clementine@withyourbag01` … `05` | `withyourbag01_clip` … `05` |
| `f_modelpose_withbag_1@avenelanim` | `f_modelpose_withbag_1_clip` |

The Clementine poses are licensed one copy per server and can't be shared, so
don't commit them to a public repo.
