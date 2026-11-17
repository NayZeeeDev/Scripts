# nayzeee-multicharacter 2.0

A cinematic, AAA-style lobby for your characters, in the spirit of Call of Duty's operator lobby. It runs on
**ESX Legacy, QBCore and Qbox** with `ox_lib` and `oxmysql`.

Features:
- **8 themed 3D lobbies**: supercar at dusk, penthouse rooftop, neon studio, Vinewood boutique, Del Perro sunset, private jet, tactical helipad and street-tuner garage
- **Lighting moods**: Golden Hour, Midnight Neon, Clean Studio and Moody Dusk, lit by a 3-point studio light rig
- **Camera**: a cinematic camera with idle sway and drift, plus Squad, Duo, Outfit and Face views
- **Poses**: solo poses with handheld props, and paired couple animations
- **Showcase weapon**: picked from the character's real inventory, or a whitelist you set
- **Companion pets**
- **Squads and couples**: persistent links that both players accept. Linked characters show up in each other's lobby, even when the other player is offline.
- **Departures**: a theme-specific cutscene into the world (drive off, board the jet, lift off in the heli, walk out)
- **Title screen**: "Press ENTER to continue" once loading finishes
- **Interface**: spawn selector, procedural ambient sound and UI sounds with a mute toggle
- **Performance**: 0.00 resmon while playing

## Install
1. Drop the `nayzeee-multicharacter` folder into your resources. **The folder name must stay exactly this.**
2. Remove or stop any other multicharacter (`qb-multicharacter`, `esx_multicharacter`, `qbx` built-in characters, …).
   - **ESX:** set `Config.Multichar = true` in es_extended.
   - **Qbox:** set `characters.useExternalCharacters = true` in `qbx_core/config/client.lua`.
3. Make sure `oxmysql` and `ox_lib` start before this resource:
   ```
   ensure oxmysql
   ensure ox_lib
   ensure nayzeee-multicharacter
   ```
4. Tables are created automatically on first start (`sql/install.sql` is there if you prefer running it yourself).

The UI is prebuilt in `web/dist`. You only need Node if you want to change the interface:
```
cd web && npm install && npm run build
```

## Configure
| File | What's in it |
|---|---|
| `config/config.lua` | Branding/accent, title screen, slots, registration, camera, lighting rig, audio, squads, spawn, relog |
| `config/themes.lua` | The 8 lobby scenes. Everything is placed **relative to the main character**, so you can move a whole scene by changing `main`. |
| `config/moods.lua` | Lighting / mood presets |
| `config/poses.lua` | Solo poses + props, `Config.CoupleAnimations` (with an empty template for your own paired anims) |
| `config/weapons.lua` | Showcase weapon modes (`inventory` / `whitelist` / `both`), per-class hold animations |
| `config/pets.lua` | Pets, access mode, idle animations |
| `config/spawns.lua` | Spawn selector points |
| `config/server.lua` | Webhooks, Tebex, admin ace, delete tables, rate limits |

### Tuning a scene in game
Every server's map mods differ, so walk each theme once:
- `/mc_lobby <themeId>` (admin) previews a theme.
- `/mc_coords` copies your position and camera, both absolute and relative to the theme's main mark, ready to paste into `themes.lua`.
- Peds are snapped to the floor automatically. If feet float or clip, nudge `Config.Scene.footHeight`.

### Departure cutscenes
Each theme has a `departure` timeline: camera points plus timed steps such as `enterVehicle`, `drive`, `fly`,
`taxi`, `walkTo`, `anim`, `ptfx` and `sound`. See `docs/CONTRACT.md` §8 for every step.

Helicopters and jets spawn crew in the front seats. Characters also enter by exact seat index with
`CPED_CONFIG_FLAG_PreventAutoShuffleToDriversSeat`, so they always sit in the cabin.

## Commands
| Command | Who | |
|---|---|---|
| `/relog` | everyone | Back to the lobby (cooldown) |
| `/mc_lobby <theme>` | admin | Preview a lobby theme |
| `/mc_coords` | admin | Copy position + camera |
| `/mc_addslots <id> <n>`, `/mc_setslots <id> <n>`, `/mc_slotsinfo <id>` | admin | Slot management |
| `/mc_delchar <charid>`, `/mc_disable <charid>`, `/mc_enable <charid>`, `/mc_forcerelog <id>` | admin | Character management |

## Upgrading from 1.x
The new tables use the `multichar_` prefix. To keep poses, favourites and backstories from 1.x, run the
optional `INSERT … SELECT` at the bottom of `sql/install.sql`.
