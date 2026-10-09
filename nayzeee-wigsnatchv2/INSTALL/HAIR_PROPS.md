# 3D wigs (hairstyle props)

GTA can only draw a hairstyle on a ped, never on an object. So for the foam head on the wig tables to wear
the exact hairstyle, every hairstyle is turned into a prop: the same thing that was done by hand for the
nayzeee-sneakers shoes, but automatic, by **hairkit** (`tools/hairkit`).

## What happens

1. When the server starts, hairkit looks through every started resource for freemode hair files
   (`mp_m_freemode_01_<pack>^hair_000_u.ydd` + its `^hair_diff_000_a_uni.ytd`).
2. New or changed hair is converted into props in **`nzw_hairprops`** (created next to this resource);
   hair that was removed loses its prop. `Config.HairProps.AutoBuild = false` only reports it instead.
3. `nzw_hairprops` is refreshed and restarted, and every player gets the new hairstyle -> prop map.
4. `/wigstudio` > **3D wigs** shows how many hairstyles have a prop and what's new, changed or gone, with
   **Build**, **Check again** and **Rebuild every hairstyle**. Hairstyles with a prop get a **3D** tag.

Each prop is matched to its hairstyle with the game's collection natives (pack name + slot in the pack), so
it stays right when packs are added, removed or reordered.

## Base game hairstyles

The server doesn't have GTA's own files, so base game and Rockstar DLC hair can't be read there. Run this
once on a PC with GTA V installed and upload the `nzw_hairprops` folder it fills:

```text
hairkit.exe game --gta "C:\Program Files\Rockstar Games\Grand Theft Auto V" --out nzw_hairprops
```

Until a hairstyle has a prop, the foam head shows the generic wig (`nz_wig_shell`).

## server.cfg

hairkit is a separate program the server starts. Let this resource refresh and restart `nzw_hairprops`:

```cfg
add_ace resource.nayzeee-wigsnatchv2 command.refresh allow
add_ace resource.nayzeee-wigsnatchv2 command.ensure allow
add_ace resource.nayzeee-wigsnatchv2 command.restart allow
```

Some hosts don't allow starting programs. Then run hairkit yourself (see `tools/README.md`) and upload
`nzw_hairprops`.

## Good to know

- One prop per hairstyle; all its textures share it. Colour is the hair's own texture (grey textures are
  tinted dark brown), not the wig's dye colour.
- Hair props are as heavy as the hair itself (often 0.5 to 2 MB each) and every player downloads them.
  `Config.HairProps.TextureSize` keeps the textures small.
- Keep `nzw_hairprops` on your own server: it's made from your hair packs and the game's files.
- Manual overrides still work: `Config.TableProps.HairPropMap = { ['m:150'] = 'my_prop' }`.
