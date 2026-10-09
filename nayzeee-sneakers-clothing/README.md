# nayzeee-sneakers-clothing

The wearable shoes for **nayzeee-sneakers**, as an addon clothing pack. It adds 5 male and 5 female shoes after
your existing ones and replaces nothing from the base game.

Everything is already set up (the `.ymt`, the `.meta` and the heels). All it needs is the shoe files.

## Setup

1. Put this folder in your `resources`.
2. Drop each shoe's `.ydd` and `.ytd` files into its folder, **as they came** (no renaming):

   | Folder in `stream/` | Shoe | Files from |
   |---|---|---|
   | `[male]/cup_runner` | Cup Runner | debranded clothing: `cup_runner` |
   | `[male]/fang_5` | Fang 5 | debranded clothing: `fang_5` |
   | `[male]/backcourt_low` | Backcourt Low | debranded clothing: `backcourt_low` |
   | `[male]/stack_trainer` | Stack Trainer | debranded clothing: `stack_trainer` |
   | `[male]/crevis_95` | Crevis 95 | crevis sneaker by jazlyn13 |
   | `[female]/alice` | Alice Western Boot | STRUT Alice Shoes |
   | `[female]/bianca` | Bianca Heel | STRUT Bianca Shoes (*Optimised* folder) |
   | `[female]/maisie` | Maisie Slingback | STRUT Maisie Shoes |
   | `[female]/omnia` | Omnia Ankle Boot | STRUT Omnia Shoes |
   | `[female]/mia` | Mia Knee Boot | [WM] Mia Colucci Boots |

3. Double-click **`RENAME-CLOTHING.bat`**. Every line should say `[ok]`:
   ```
   [ok] [male]/cup_runner  feet_000 + 5 textures
   [ok] [male]/fang_5  feet_001 + 15 textures
   ...
   ```
   It's safe to run again. If a line says `[x]` or `[!]`, fix what it says and run it again.
4. In `server.cfg`, start it before the script:
   ```
   ensure nayzeee-sneakers-clothing
   ensure nayzeee-sneakers
   ```
5. Restart, then close FiveM and clear your cache.

You don't need drawable numbers. nayzeee-sneakers finds each shoe in this pack by itself.

## What's in the pack

| Slot | Male | Textures | | Female | Textures | Heel height | Footsteps |
|---|---|---|---|---|---|---|---|
| 0 | Cup Runner | 5 | | Alice Western Boot | 26 | 0.37 | rubber |
| 1 | Fang 5 | 15 | | Bianca Heel | 18 (skin tone) | 1.36 | high heels |
| 2 | Backcourt Low | 3 | | Maisie Slingback | 16 (skin tone) | 1.01 | high heels |
| 3 | Stack Trainer | 3 | | Omnia Ankle Boot | 9 | 1.18 | high heels |
| 4 | Crevis 95 | 9 | | Mia Knee Boot | 4 | none | heavy boots |

The male shoes use trainer footsteps. The heel heights and footsteps for Alice, Bianca, Maisie and Omnia are
the creators' own recommended settings (from their *Optimal Durty Cloth Tool Settings* notes).

```
nayzeee-sneakers-clothing/
├── fxmanifest.lua
├── RENAME-CLOTHING.bat                        renames what you dropped in
├── mp_m_freemode_01_nayzeee_sneakers.meta     registers the male shoes
├── mp_f_freemode_01_nayzeee_sneakers.meta     registers the female shoes
├── tools/rename-clothing.ps1                  what the .bat runs
└── stream/
    ├── mp_m_freemode_01_nayzeee_sneakers.ymt      male shoe list
    ├── mp_f_freemode_01_nayzeee_sneakers.ymt      female shoe list
    ├── mp_creaturemetadata_f_nayzeee_sneakers.ymt heels
    ├── [male]/…
    └── [female]/…
```

## Renaming by hand

`RENAME-CLOTHING.bat` does this for you. If you'd rather rename by hand, these are the names:

| Shoe | Model | Textures |
|---|---|---|
| Cup Runner | `mp_m_freemode_01_nayzeee_sneakers^feet_000_u.ydd` | `mp_m_freemode_01_nayzeee_sneakers^feet_diff_000_a_uni.ytd` … `_e_uni` |
| Fang 5 | `mp_m_freemode_01_nayzeee_sneakers^feet_001_u.ydd` | `mp_m_freemode_01_nayzeee_sneakers^feet_diff_001_a_uni.ytd` … `_o_uni` |
| Backcourt Low | `mp_m_freemode_01_nayzeee_sneakers^feet_002_u.ydd` | `mp_m_freemode_01_nayzeee_sneakers^feet_diff_002_a_uni.ytd` … `_c_uni` |
| Stack Trainer | `mp_m_freemode_01_nayzeee_sneakers^feet_003_u.ydd` | `mp_m_freemode_01_nayzeee_sneakers^feet_diff_003_a_uni.ytd` … `_c_uni` |
| Crevis 95 | `mp_m_freemode_01_nayzeee_sneakers^feet_004_u.ydd` | `mp_m_freemode_01_nayzeee_sneakers^feet_diff_004_a_uni.ytd` … `_i_uni` |
| Alice | `mp_f_freemode_01_nayzeee_sneakers^feet_000_u.ydd` | `mp_f_freemode_01_nayzeee_sneakers^feet_diff_000_a_uni.ytd` … `_z_uni` |
| Bianca | `mp_f_freemode_01_nayzeee_sneakers^feet_001_r.ydd` | `mp_f_freemode_01_nayzeee_sneakers^feet_diff_001_a_whi.ytd` … `_r_whi` |
| Maisie | `mp_f_freemode_01_nayzeee_sneakers^feet_002_r.ydd` | `mp_f_freemode_01_nayzeee_sneakers^feet_diff_002_a_whi.ytd` … `_p_whi` |
| Omnia | `mp_f_freemode_01_nayzeee_sneakers^feet_003_u.ydd` | `mp_f_freemode_01_nayzeee_sneakers^feet_diff_003_a_uni.ytd` … `_i_uni` |
| Mia | `mp_f_freemode_01_nayzeee_sneakers^feet_004_u.ydd` | `mp_f_freemode_01_nayzeee_sneakers^feet_diff_004_a_uni.ytd` … `_d_uni` |

Bianca and Maisie end in `_r` / `_whi` because they have skin-tone textures. The rest end in `_u` / `_uni`.
Keep each texture's letter: the letter is the colourway in `nayzeee-sneakers/config/shoes.lua`.

## Good to know

- **Don't reorder the folders or rename the pack.** The order is baked into the `.ymt` files and matches the
  `slot` numbers in `nayzeee-sneakers/config/shoes.lua`. If you do rename the pack, change
  `Config.ClothingPack` in `nayzeee-sneakers/config/config.lua` to the new name.
- **Players can pick these shoes in your clothing menu** too, like any other addon clothing. If you only want
  them through the script, block those drawables in your clothing script's blacklist.
- **Adding more shoes later** means a new `.ymt`. Build them in grzyClothTool or Durty Cloth Tool as their own
  pack, then point that shoe's `drawable` in `config/shoes.lua` at it.
