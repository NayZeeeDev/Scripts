# Items

Images for every boombox are in `install/images/` (copy them into your inventory's image folder).
Records use `vinyl_record.png` (or give each album its own cover image). The CarPlay unit (`nayzeee_carplay`) has no image yet.

## ox_inventory — `ox_inventory/data/items.lua`

```lua
['nayzeee_audio_a'] = { label = 'Pulse Tower Speaker', weight = 1500, stack = false, close = true },
['nayzeee_audio_b'] = { label = 'Echo Column Speaker', weight = 1500, stack = false, close = true },
['nayzeee_audio_c'] = { label = 'Drum Hub Speaker',    weight = 1800, stack = false, close = true },
['nayzeee_audio_d'] = { label = 'Orb Speaker',         weight = 1200, stack = false, close = true },
['nayzeee_audio_e'] = { label = 'Carry Cube Speaker',  weight = 2000, stack = false, close = true },
['nayzeee_audio_f'] = { label = 'Roll Bar Speaker',    weight = 2200, stack = false, close = true },
['nayzeee_audio_g'] = { label = 'Turntable',           weight = 6000, stack = false, close = true },
['nayzeee_audio_h'] = { label = 'Studio Speaker Set',  weight = 8000, stack = false, close = true },
['nayzeee_carplay'] = { label = 'CarPlay Unit',        weight = 800,  stack = true,  close = true },

-- one per record (the item name must match its key in vinyls.lua)
['vinyl_takecare']       = { label = 'Record: Take Care',            weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_21']             = { label = 'Record: 21',                   weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_carter4']        = { label = 'Record: Tha Carter IV',        weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_aiyoungboy']     = { label = 'Record: AI YoungBoy',          weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_music']          = { label = 'Record: MUSIC',                weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_2014fhd']        = { label = 'Record: 2014 Forest Hills Dr', weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_ghettogospel']   = { label = 'Record: Ghetto Gospel',        weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_ibarelyknowher'] = { label = 'Record: I Barely Know Her',    weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_artist']         = { label = 'Record: Artist',               weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_bigscoom']       = { label = 'Record: BIG SCOOM Vol. 1',     weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_itoldyou']       = { label = 'Record: I Told You',           weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_kehlani']        = { label = 'Record: Kehlani',              weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_forbrokenears']  = { label = 'Record: For Broken Ears',      weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_thriller']       = { label = 'Record: Thriller',             weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
['vinyl_heartbreak']     = { label = 'Record: Heart Break',          weight = 300, stack = true, close = true, client = { image = 'vinyl_record.png' } },
```

No `client` / `server` export blocks are needed: the items are registered as usable through ESX / QB / Qbox.

## ESX (default inventory) — SQL

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
nayzeee_audio_a = { name = 'nayzeee_audio_a', label = 'Pulse Tower Speaker', weight = 1500, type = 'item', image = 'nayzeee_audio_a.png', unique = true, useable = true, shouldClose = true, description = 'Portable speaker' },
-- repeat for b … h, and nayzeee_carplay
```
