# hairstyles/

Drop **female** hairstyles here, one folder per hairstyle. The folder name becomes the hairstyle's name.

```
hairstyles/
├─ Knotless Braids/
│  ├─ hair_000_u.ydd
│  ├─ hair_diff_000_a_uni.ytd      ← texture A
│  └─ hair_diff_000_b_uni.ytd      ← texture B (optional)
└─ Kiki Bob/
   ├─ mp_f_freemode_01^hair_003_u.ydd
   └─ mp_f_freemode_01^hair_diff_003_uni.ytd
```

Then restart the server (or `/wigstudio` → 3D wigs → **Build**). Each hairstyle:

- becomes a **real hairstyle characters can wear**: hairkit puts it in a female hair pack inside
  `nzw_hairprops` (`mp_f_freemode_01_mp_f_nzw_salon`), so you don't need to make a clothing pack for it;
- gets its **foam head prop** for the wig tables;
- if the folder is named after a **salon style**, that style uses it by itself, with its salon slices (the hair
  going on row by row). Any other name: link it to a style in `/wigstudio` → Salon look.

Folder names the salon styles pick up (capitals, spaces and dashes don't matter):

| Style | Folder name |
|---|---|
| Classic Three-Strand Braid | `Three Strand` |
| French Braid / Dutch Braid / Fishtail Braid | `French Braid`, `Dutch Braid`, `Fishtail Braid` |
| Box Braids / Knotless Braids | `Box Braids`, `Knotless Braids` |
| Cornrows (Straight Backs) | `Cornrows` |
| Stitch / Fulani / Lemonade Braids | `Stitch Braids`, `Fulani Braids`, `Lemonade Braids` |
| Boho / Goddess Braids | `Boho` or `Goddess Braids` |
| Passion / Senegalese Twists | `Passion Twists`, `Senegalese Twists` |
| Faux Locs / Butterfly Locs | `Faux Locs` or `Butterfly Locs` |
| Halo Braid (Crown Braid) | `Halo Braid` |
| Space Buns with Feed-In Braids | `Space Buns` |
| Bubble Braid / Waterfall Braid | `Bubble Braid`, `Waterfall Braid` |
| Traditional Sew-In Weave | `Sew In` |

Good to know

- Any file names work. With several `.ydd` in one folder, textures pair by number (`hair_003` ↔ `hair_diff_003`)
  or by name (`bob.ydd` ↔ `bob_a.ytd`), and they're called *Name 1*, *Name 2*.
- Female only: files named `mp_m_…` are left out.
- A `.ytd` that's 0 bytes is left out. If the colour texture is inside the `.ydd`, it's taken from there.
  If a download has no colour texture at all, the console says so (the hairstyle would show white).
- Every hairstyle keeps its number in the pack, so adding or removing one never changes anyone else's hair.
  A removed one keeps its place until a new hairstyle takes it.
- Players see new hairstyles after they reconnect (clothing can't be added to a game that's already running).
- Keep this folder when you update the script. Don't put these files in a `stream/` folder: this folder is
  only read by hairkit, it's never streamed itself.
