# Hairstyle props

GTA can't put a hairstyle on an object: hair only exists as part of a ped. So to show the exact
hairstyle on the foam head at a wig table, each hairstyle is turned into a prop, the same way the
nayzeee-sneakers shoes were turned from clothing into props. Until a hairstyle has a prop, the table
shows the generic wig (`nz_wig_shell`). Nothing else needs them.

## How the script finds them

1. `Config.TableProps.HairPropMap`: `['m:150'] = 'nzw_juice_dreads'` (gender : hairstyle number = prop).
   The hairstyle number is the `#` shown in the Workshop and the Wig Studio.
2. `Config.TableProps.HairProps = 'nzw_%s_%d'`: a prop named `nzw_f_12` is used for female hairstyle 12.

If neither is streamed, the generic wig is used.

Every hair prop has its origin on the `SKEL_Head` bone and faces +Y like a ped, which is exactly
where `Config.TableProps.Head.point` sits on the foam head, so it drops straight on.

## Making them

Hair models come from your own game files (export `hair_XXX_u.ydd` + `hair_diff_XXX_*.ytd` with
CodeWalker from `mp_f_freemode_01` / `mp_m_freemode_01`) or from a hair pack you have the rights to.
Convert each one with `tools/convert-hair.sh` (see `tools/README.md`) into a separate
`nzw_hairprops` resource. Keep those props on your own server: don't put Rockstar's or another
creator's hair inside a resource you sell.
