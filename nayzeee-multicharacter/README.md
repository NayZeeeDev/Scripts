# nayzeee-multicharacter

Cinematic character selection, registration, starter shop and spawn selector for **ESX Legacy**, **QBCore** and **Qbox**.

## Install

1. Drop the folder in your resources as **`nayzeee-multicharacter`** (the name is locked).
2. Remove or stop your old multicharacter: `esx_multicharacter`, `qb-multicharacter`, or any other one. The install report in the server console flags anything still running.
3. Ensure order in `server.cfg`:
   ```
   ensure oxmysql
   ensure ox_lib
   ensure es_extended        # or qb-core / qbx_core
   ensure illenium-appearance # your clothing script
   ensure nayzeee-multicharacter
   ```
4. Framework setup:
   - **ESX Legacy**: set `Config.Multichar = true` in es_extended's config. esx_identity is not needed; registration is built in.
   - **QBCore**: remove `qb-multicharacter`. qb-spawn is not needed; the spawn selector is built in.
   - **Qbox**: in `qbx_core/config/client.lua` set `characters.useExternalCharacters = true`.
5. Start the server. Tables are created automatically (`sql/install.sql` if your DB user can't create tables).

## Optional convars (server.cfg)

```
set nzm_webhook "https://discord.com/api/webhooks/..."   # ServerConfig.Logs.enabled = true
set nzm_discord_token "BOT_TOKEN"                         # Config.Slots.discord.enabled = true
set sv_tebexSecret "TEBEX_SECRET"                         # ServerConfig.Tebex.enabled = true
add_ace group.vip nayzeee.slots.vip allow                 # VIP slots from Config.Slots.ace
```

## Commands

| Command | Who | What |
|---|---|---|
| `/relog` | players (or ACE in `Config.Relog.command.ace`) | back to character selection |
| `/partner [id] [couple\|friend]` | players | show up next to another player's character in the lineup |
| `/mc_setslots [id\|license] [extra]` | admin | set granted extra slots |
| `/mc_addslots [id\|license] [amount]` | admin | add (or remove) granted extra slots |
| `/mc_slotsinfo [id]` | admin | where a player's slots come from |
| `/mc_delchar [charid]` | admin | delete a character |
| `/mc_disable [charid]` / `/mc_enable [charid]` | admin | lock / unlock a character |
| `/mc_forcerelog [id]` | admin | send a player back to selection |
| `/mc_coords` | admin | copy position + camera to clipboard for building scenes |

## Exports (server)

```lua
exports['nayzeee-multicharacter']:Relog(src)
exports['nayzeee-multicharacter']:InSelection(src)
exports['nayzeee-multicharacter']:GetSlots(src)          -- total, info
exports['nayzeee-multicharacter']:AddSlots(srcOrLicense, amount)
exports['nayzeee-multicharacter']:GetPlaytime(charId)    -- seconds
exports['nayzeee-multicharacter']:GetCharacterMeta(charId)
```

Client event after the player lands in the world: `nayzeee-multicharacter:spawned` (isNew).

## Editable files (not escrowed)

- `config/*.lua` – everything tunable, scenes, spawn points, nationalities, server settings
- `locales/*.lua` – every string in the UI and messages
- `bridge/server/*.lua` – framework calls, vehicle giving (owned_vehicles / player_vehicles columns), housing spawns
- `bridge/client/*.lua` – HUD toggle, notify, weather sync pause, appearance editor

## Performance

Nothing runs on the client once you're in the world. Selection threads (camera depth of field, spawn transitions) all end when the UI closes. Relog points use ox_lib points, so there's no loop until you're standing at one. Server side there's one 5-minute playtime flush.
