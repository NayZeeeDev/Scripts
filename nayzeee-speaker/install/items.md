# Items

Images for every item are in `install/images/` (copy them into your inventory's image folder). Each file is
named like its item (`nayzeee_audio_a.png`, `vinyl_takecare.png`, `nayzeee_carplay.png`, ...), so ox_inventory
finds them without an `image` field. `vinyl_record.png` is a generic record for albums you add yourself
(regenerate per-album images with `python3 tools/item_images.py` in nayzeee-speaker-assets).

| Item | What it is |
|---|---|
| `nayzeee_audio_a` … `nayzeee_audio_f` | the six portable speakers (Pulse Tower, Echo Column, Drum Hub, Orb, Carry Cube, Roll Bar) |
| `nayzeee_audio_g` | the Turntable: plays records only |
| `nayzeee_audio_h` | the Studio Set (too big to carry) |
| `nayzeee_carplay` | CarPlay unit, only needed with `Config.Carplay.install.use = true` |
| `vinyl_<key>` | one per record in `vinyls.lua`; the item name must match its key there |

Records are sold in the record shop (`Config.RecordShop`), so every record needs its item. A record whose item
your inventory doesn't know is left out of the shop, and the server console names it.

## ox_inventory — `ox_inventory/data/items.lua`

Also the block to use on **Qbox** (it runs on ox_inventory).

```lua
['nayzeee_audio_a'] = { label = 'Pulse Tower Speaker', weight = 1500, stack = false, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['nayzeee_audio_b'] = { label = 'Echo Column Speaker', weight = 1500, stack = false, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['nayzeee_audio_c'] = { label = 'Drum Hub Speaker',    weight = 1800, stack = false, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['nayzeee_audio_d'] = { label = 'Orb Speaker',         weight = 1200, stack = false, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['nayzeee_audio_e'] = { label = 'Carry Cube Speaker',  weight = 2000, stack = false, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['nayzeee_audio_f'] = { label = 'Roll Bar Speaker',    weight = 2200, stack = false, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['nayzeee_audio_g'] = { label = 'Turntable',           weight = 6000, stack = false, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['nayzeee_audio_h'] = { label = 'Studio Speaker Set',  weight = 8000, stack = false, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['nayzeee_carplay'] = { label = 'CarPlay Unit',        weight = 800,  stack = true,  close = true, server = { export = 'nayzeee-speaker.useItem' } },

-- one per record (the item name must match its key in vinyls.lua; its image is install/images/<item>.png)
['vinyl_takecare']       = { label = 'Record: Take Care',               weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_21']             = { label = 'Record: 21',                      weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_carter4']        = { label = 'Record: Tha Carter IV',           weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_aiyoungboy']     = { label = 'Record: AI YoungBoy',             weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_music']          = { label = 'Record: MUSIC',                   weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_2014fhd']        = { label = 'Record: 2014 Forest Hills Drive', weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_ghettogospel']   = { label = 'Record: Ghetto Gospel',           weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_ibarelyknowher'] = { label = 'Record: I Barely Know Her',       weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_artist']         = { label = 'Record: Artist',                  weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_bigscoom']       = { label = 'Record: BIG SCOOM Vol. 1',        weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_itoldyou']       = { label = 'Record: I Told You',              weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_kehlani']        = { label = 'Record: Kehlani',                 weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_forbrokenears']  = { label = 'Record: For Broken Ears',         weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_thriller']       = { label = 'Record: Thriller',                weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },
['vinyl_heartbreak']     = { label = 'Record: Heart Break',             weight = 300, stack = true, close = true, server = { export = 'nayzeee-speaker.useItem' } },

-- a record you import yourself (/vinylimport prints its item name), with the generic image:
-- ['vinyl_myalbum']     = { label = 'Record: My Album', weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' }, server = { export = 'nayzeee-speaker.useItem' } },
```

The `server = { export = 'nayzeee-speaker.useItem' }` part is what makes the items usable when ox_inventory runs
without ESX / QBCore / Qbox (ox_core, ND and others): leave it out there and using a speaker, record or CarPlay unit
does nothing (the server console lists the items that are missing it). With ESX / QB / Qbox it is optional, since the
items are also registered as usable through the framework. Renamed the resource folder? Change `nayzeee-speaker` to match.

## ESX (default inventory) — SQL

Copy the images into your inventory's image folder; each file is already named like its item.

```sql
INSERT IGNORE INTO `items` (`name`, `label`, `weight`) VALUES
('nayzeee_audio_a', 'Pulse Tower Speaker', 2), ('nayzeee_audio_b', 'Echo Column Speaker', 2),
('nayzeee_audio_c', 'Drum Hub Speaker', 2),    ('nayzeee_audio_d', 'Orb Speaker', 1),
('nayzeee_audio_e', 'Carry Cube Speaker', 2),  ('nayzeee_audio_f', 'Roll Bar Speaker', 2),
('nayzeee_audio_g', 'Turntable', 6),           ('nayzeee_audio_h', 'Studio Speaker Set', 8),
('nayzeee_carplay', 'CarPlay Unit', 1),
('vinyl_takecare', 'Record: Take Care', 1), ('vinyl_21', 'Record: 21', 1),
('vinyl_carter4', 'Record: Tha Carter IV', 1), ('vinyl_aiyoungboy', 'Record: AI YoungBoy', 1),
('vinyl_music', 'Record: MUSIC', 1), ('vinyl_2014fhd', 'Record: 2014 Forest Hills Drive', 1),
('vinyl_ghettogospel', 'Record: Ghetto Gospel', 1), ('vinyl_ibarelyknowher', 'Record: I Barely Know Her', 1),
('vinyl_artist', 'Record: Artist', 1), ('vinyl_bigscoom', 'Record: BIG SCOOM Vol. 1', 1),
('vinyl_itoldyou', 'Record: I Told You', 1), ('vinyl_kehlani', 'Record: Kehlani', 1),
('vinyl_forbrokenears', 'Record: For Broken Ears', 1), ('vinyl_thriller', 'Record: Thriller', 1),
('vinyl_heartbreak', 'Record: Heart Break', 1);
```

## QBCore — `qb-core/shared/items.lua`

```lua
nayzeee_audio_a = { name = 'nayzeee_audio_a', label = 'Pulse Tower Speaker', weight = 1500, type = 'item', image = 'nayzeee_audio_a.png', unique = true,  useable = true, shouldClose = true, description = 'Portable speaker' },
nayzeee_audio_b = { name = 'nayzeee_audio_b', label = 'Echo Column Speaker', weight = 1500, type = 'item', image = 'nayzeee_audio_b.png', unique = true,  useable = true, shouldClose = true, description = 'Portable speaker' },
nayzeee_audio_c = { name = 'nayzeee_audio_c', label = 'Drum Hub Speaker',    weight = 1800, type = 'item', image = 'nayzeee_audio_c.png', unique = true,  useable = true, shouldClose = true, description = 'Portable speaker' },
nayzeee_audio_d = { name = 'nayzeee_audio_d', label = 'Orb Speaker',         weight = 1200, type = 'item', image = 'nayzeee_audio_d.png', unique = true,  useable = true, shouldClose = true, description = 'Portable speaker' },
nayzeee_audio_e = { name = 'nayzeee_audio_e', label = 'Carry Cube Speaker',  weight = 2000, type = 'item', image = 'nayzeee_audio_e.png', unique = true,  useable = true, shouldClose = true, description = 'Portable speaker' },
nayzeee_audio_f = { name = 'nayzeee_audio_f', label = 'Roll Bar Speaker',    weight = 2200, type = 'item', image = 'nayzeee_audio_f.png', unique = true,  useable = true, shouldClose = true, description = 'Portable speaker' },
nayzeee_audio_g = { name = 'nayzeee_audio_g', label = 'Turntable',           weight = 6000, type = 'item', image = 'nayzeee_audio_g.png', unique = true,  useable = true, shouldClose = true, description = 'Plays records' },
nayzeee_audio_h = { name = 'nayzeee_audio_h', label = 'Studio Speaker Set',  weight = 8000, type = 'item', image = 'nayzeee_audio_h.png', unique = true,  useable = true, shouldClose = true, description = 'Studio speakers' },
nayzeee_carplay = { name = 'nayzeee_carplay', label = 'CarPlay Unit',        weight = 800,  type = 'item', image = 'nayzeee_carplay.png', unique = false, useable = true, shouldClose = true, description = 'Car head unit' },

vinyl_takecare       = { name = 'vinyl_takecare',       label = 'Record: Take Care',               weight = 300, type = 'item', image = 'vinyl_takecare.png',       unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_21             = { name = 'vinyl_21',             label = 'Record: 21',                      weight = 300, type = 'item', image = 'vinyl_21.png',             unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_carter4        = { name = 'vinyl_carter4',        label = 'Record: Tha Carter IV',           weight = 300, type = 'item', image = 'vinyl_carter4.png',        unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_aiyoungboy     = { name = 'vinyl_aiyoungboy',     label = 'Record: AI YoungBoy',             weight = 300, type = 'item', image = 'vinyl_aiyoungboy.png',     unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_music          = { name = 'vinyl_music',          label = 'Record: MUSIC',                   weight = 300, type = 'item', image = 'vinyl_music.png',          unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_2014fhd        = { name = 'vinyl_2014fhd',        label = 'Record: 2014 Forest Hills Drive', weight = 300, type = 'item', image = 'vinyl_2014fhd.png',        unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_ghettogospel   = { name = 'vinyl_ghettogospel',   label = 'Record: Ghetto Gospel',           weight = 300, type = 'item', image = 'vinyl_ghettogospel.png',   unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_ibarelyknowher = { name = 'vinyl_ibarelyknowher', label = 'Record: I Barely Know Her',       weight = 300, type = 'item', image = 'vinyl_ibarelyknowher.png', unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_artist         = { name = 'vinyl_artist',         label = 'Record: Artist',                  weight = 300, type = 'item', image = 'vinyl_artist.png',         unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_bigscoom       = { name = 'vinyl_bigscoom',       label = 'Record: BIG SCOOM Vol. 1',        weight = 300, type = 'item', image = 'vinyl_bigscoom.png',       unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_itoldyou       = { name = 'vinyl_itoldyou',       label = 'Record: I Told You',              weight = 300, type = 'item', image = 'vinyl_itoldyou.png',       unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_kehlani        = { name = 'vinyl_kehlani',        label = 'Record: Kehlani',                 weight = 300, type = 'item', image = 'vinyl_kehlani.png',        unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_forbrokenears  = { name = 'vinyl_forbrokenears',  label = 'Record: For Broken Ears',         weight = 300, type = 'item', image = 'vinyl_forbrokenears.png',  unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_thriller       = { name = 'vinyl_thriller',       label = 'Record: Thriller',                weight = 300, type = 'item', image = 'vinyl_thriller.png',       unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
vinyl_heartbreak     = { name = 'vinyl_heartbreak',     label = 'Record: Heart Break',             weight = 300, type = 'item', image = 'vinyl_heartbreak.png',     unique = false, useable = true, shouldClose = true, description = 'Vinyl record' },
```

Copy the images into `qb-inventory/html/images/` (or your inventory's image folder).
