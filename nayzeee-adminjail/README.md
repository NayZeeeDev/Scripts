# NAYZEEE Admin Jail v2

Server-authoritative OOC admin jail for QBCore, Qbox, ESX and standalone.
`discord.gg/nayzeeedev`

## Install

1. Drop `nayzeee-adminjail` in your resources and `ensure` it **after** `ox_lib`, `oxmysql` and your framework.
2. Give staff access (either works):
   ```cfg
   add_ace group.admin nayzeee.adminjail allow
   ```
   or list their framework groups in `Config.Permissions.groups`.
3. Start the server. Tables are created automatically, and v1 sentences and history are imported once.
   (`install/nayzeee-adminjail.sql` is only there if you want to create the tables yourself.)

Requires OneSync (the server checks player positions itself).

## Commands

| Command | |
|---|---|
| `/adminjail` | Admin panel |
| `/jail [id] [minutes] [reason]` | Works from the server console too |
| `/unjail [id]` | |
| `HOME` (rebindable) | Collapse / expand the jail HUD |

## How restarts, reconnects and spawn selectors are handled

- **The timer lives on the server.** It stores `remaining` plus a timestamp, so nothing ticks every second and the client never sends time.
- **Time only counts while the player is actually in jail.** Leaving the server, sitting in the character menu or picking a spawn all pause it. Set `Config.Sentence.countOffline = true` for real-time sentences instead.
- **Spawn selectors:** when a jailed player loads in, the client waits until they have *really* spawned before moving them to jail. That means the ped is visible, the screen has faded in, no scripted or switch camera is active, and no other resource has NUI focus (spawn menus, multichar, apartments, housing). Then it fades out, moves them and fades in.
- If something teleports them out right after placement (a late spawn script, a death respawn at a hospital), they're **pulled back with no penalty** for `Config.Spawn.pullbackWindow` seconds.
- **Server restarts:** active sentences are loaded from the DB on start. Running sentences are saved every `flushInterval` seconds and on txAdmin's shutdown warning.
- **Resource restarts:** players who are online get re-attached automatically.
- `Config.Scope = 'license'` (default) jails the whole account, so switching characters doesn't dodge it. Use `'character'` to jail one character only.

## Escapes

The client reports leaving the zone right away, and the server also checks positions itself through OneSync every `serverInterval` ms. That catches noclip and mod menus that skip the client check. Penalties stack: `penalty + escalation × previous attempts`, capped at `maxPenalty`.

## Work program

The server picks each task at random from the location's `work` points. It checks the player is standing at the point when they start and when they finish, and that the full duration passed. Remote-triggering the events does nothing. The reduction per cycle and the hourly cap are tracked server side and survive reconnects. Task types (`sweep`, `scrub`, `trash`) use GTA scenarios, or you can add your own with `anim` + `prop`.

## Admin panel

- **Overview:** live timers, today's sentences and escapes, recently closed sentences
- **New sentence:** search online players, or players who **left in the last 3 hours** (jail combat-loggers; the sentence starts when they rejoin). Prior sentence counts, reason presets, quick durations and location picker.
- **Inmates:** every open sentence (online and offline): add or remove time, transfer to another location, release
- **History:** searchable by player or staff, paginated

Open `web/index.html` in a normal browser to preview the UI with demo data (`?view=sentence`, `?view=hud`, …).

## Performance

- Not jailed: **no threads** on the client.
- Jailed: one 1000 ms watcher. The work marker only draws per-frame while you're within `viewDistance` of the current task.
- Melee, weapons, godmode and inventory are blocked through native state and state bags, not per-frame control disabling.
- Server: one 1 s loop over the jailed list only.

## Exports

```lua
-- server (target = server id or identifier)
exports['nayzeee-adminjail']:IsJailed(target)
exports['nayzeee-adminjail']:GetSentence(target)        -- table or nil
exports['nayzeee-adminjail']:GetAll()
exports['nayzeee-adminjail']:Jail(src, minutes, reason, locationId, adminName)
exports['nayzeee-adminjail']:JailOffline(identifier, minutes, reason, locationId, adminName, name)
exports['nayzeee-adminjail']:Release(target, by)
exports['nayzeee-adminjail']:AdjustTime(target, minutes, by)
-- v1 names still work: IsPlayerJailed, GetJailedData, JailPlayer, ReleasePlayer, GetAllJailed

-- client
exports['nayzeee-adminjail']:IsJailed()
exports['nayzeee-adminjail']:GetRemaining()  -- seconds
exports['nayzeee-adminjail']:GetLocation()

-- state bag, readable by any resource
Player(src).state.adminJailed   -- server
LocalPlayer.state.adminJailed   -- client
```
