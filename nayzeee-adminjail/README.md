# NAYZEEE Admin Jail 1.0.0

Server-authoritative OOC admin jail for QBCore, Qbox, ESX and standalone.
`discord.gg/nayzeeedev`

## Install

1. Drop `nayzeee-adminjail` in your resources and `ensure` it **after** `ox_lib`, `oxmysql` and your framework.
2. Give staff access (either works):
   ```cfg
   add_ace group.admin nayzeee.adminjail allow
   ```
   or list their framework groups in `Config.Permissions.groups`.
3. Start the server. Tables are created automatically.
   (`install/nayzeee-adminjail.sql` is only there if you want to create the tables yourself.)

Requires OneSync (the server checks player positions itself).

## Commands

| Command | |
|---|---|
| `/adminjail` | Admin panel |
| `/ajail [id] [minutes] [reason]` | Works from the server console too. `me` works as the id |
| `/aunjail [id]` | |
| `HOME` (rebindable) | Collapse / expand the jail HUD |

Command names can be changed in `Config.Commands`. Avoid `jail` / `unjail`: police and prison scripts register those too, and whichever resource starts last takes the command over.

### Commands not working?

Run this in the **server console** (F8 won't work):

```
adminjail_perms [server id]
```

It prints whether that player has access, which check granted it, and the exact `add_ace` line to give them access if not.

## How restarts, reconnects and spawn selectors are handled

- **The timer lives on the server.** It stores `remaining` plus a timestamp, so nothing ticks every second and the client never sends time.
- **Time only counts while the player is actually in jail.** Leaving the server, sitting in the character menu or picking a spawn all pause it. Set `Config.Sentence.countOffline = true` for real-time sentences instead.
- **Spawn selectors:** when a jailed player loads in, the client waits until they have *really* spawned before moving them to jail. That means the ped is visible, the screen has faded in, no scripted or switch camera is active, and no other resource has NUI focus (spawn menus, multichar, apartments, housing). Then it fades out, moves them and fades in.
- If something teleports them out right after placement (a late spawn script, a death respawn at a hospital), they're **pulled back with no penalty** for `Config.Spawn.pullbackWindow` seconds.
- **Server restarts:** active sentences are loaded from the DB on start. Running sentences are saved every `flushInterval` seconds and on txAdmin's shutdown warning.
- **Resource restarts:** players who are online get re-attached automatically.
- `Config.Scope = 'license'` (default) jails the whole account, so switching characters doesn't dodge it. Use `'character'` to jail one character only.

## Cinematics

All of it can be toggled in `Config.Cinematic`.

- **Sentencing:** the GTA character-switch camera lifts the player into the sky, they're put in the prison jumpsuit off-camera, and the camera drops them into the jail. Then comes a **mugshot booking**: they hold a printed booking board (name, case number, date), and two camera flashes go off, front and side profile. Meanwhile a **booking card** shows their real in-game headshot against a height chart, with the case number and a "SENTENCED" stamp.
- **Reconnect or respawn:** a quick fade back into jail and a "Sentence resumed" card with the time left.
- **Escape attempt:** an alarm sound, a red pulsing screen, camera shake and an "ESCAPE ATTEMPT" banner, then they're dragged back. Online staff get a live alert.
- **Release:** a "You're free" summary card (time served, escape attempts, work cycles, time worked off), and the sky camera takes them to the release point with their own outfit back on.

## Prison outfit

Jailed players wear a jumpsuit (`Config.Outfit`, per gender, freemode peds). Their real outfit is saved in resource KVP on their own PC, keyed by sentence and character, so it comes back on release even after a server restart, reconnect or character swap.

## Inmate tags

Other players see an "ADMIN JAIL · INMATE" tag above jailed players' heads (`Config.Overhead`). It's driven by state bags, so nothing runs while nobody is jailed.

## Escapes

The client reports leaving the zone right away, and the server also checks positions itself through OneSync every `serverInterval` ms. That catches noclip and mod menus that skip the client check. Penalties stack: `penalty + escalation × previous attempts`, capped at `maxPenalty`.

## Work program

The server picks each task at random from the location's `work` points. It checks the player is standing at the point when they start and when they finish, and that the full duration passed. Remote-triggering the events does nothing. The reduction per cycle and the hourly cap are tracked server side and survive reconnects.

There are six task types: sweep (broom), mop, scrub (sponge), pick up litter, repair the fence (hammer) and wipe windows. Each has its own animation and hand prop, plus optional particles. Add your own with `anim` + `prop`, or a GTA `scenario`. Progress uses a built-in ring that matches the UI (`Config.Progress = 'nayzeee'`), with X to cancel, or ox_lib's bar or circle.

## Admin panel

- **Overview:** live timers, today's sentences and escapes, a 7-day sentence chart, recently closed sentences, live escape alerts
- **New sentence:** search online players, or players who **left in the last 3 hours** (jail combat-loggers; the sentence starts when they rejoin). Prior sentence counts, reason presets, quick durations and location picker.
- **Inmates:** every open sentence (online and offline): add or remove time, transfer to another location, release, or teleport to the inmate
- **History:** searchable by player or staff, paginated

Open `web/index.html` in a normal browser to preview the UI with demo data: `?view=sentence`, `?view=hud`, `?fx=booking`, `?fx=release`, `?fx=alarm`, `?fx=resume`, `?fx=task`.

## Performance

- Not jailed: **no threads** on the client.
- Jailed: one 1000 ms watcher. The work marker only draws per-frame while you're within `viewDistance` of the current task.
- Cinematics only run during the moment itself (a few seconds), and nothing stays resident.
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

-- client
exports['nayzeee-adminjail']:IsJailed()
exports['nayzeee-adminjail']:GetRemaining()  -- seconds
exports['nayzeee-adminjail']:GetLocation()

-- state bag, readable by any resource
Player(src).state.adminJailed   -- server
LocalPlayer.state.adminJailed   -- client
```
