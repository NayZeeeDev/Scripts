# NayZeee Optimizer v1.1.0

FPS optimizer, kill/hit effects, and a server performance tracker for FiveM.

## Install

1. Keep the folder named exactly `nayzeee-optimizerv2`.
2. In `server.cfg`, start it **before** your other resources:
   ```
   ensure nayzeee-optimizerv2
   ```
3. Let the resource run `refresh`, restart probed resources and use the profiler:
   ```
   add_ace resource.nayzeee-optimizerv2 command allow
   ```
   And let it add its probe line to your other resources. FiveM blocks one resource from editing another unless server.cfg allows it, one line per resource. The optimizer writes those lines for you into its own folder on every start, so you only add this once:
   ```
   exec @nayzeee-optimizerv2/probe_permissions.cfg
   ```
   Start the server once so the file fills with your resources, then restart. New resources you add later are picked up on the following restart.
4. Admins: anyone with the `command` ace, qb-core/qbx `admin`/`god`, ESX `admin`/`superadmin`, or a txAdmin login already counts. To add someone else, give them the ace or list their identifier in `Config.Admin.identifiers`:
   ```
   add_ace group.admin optimizer.admin allow
   ```
   Not sure why someone has no Health tab? Run `optimizeradmin <playerId>` in the server console. It says whether they are an admin and why, or prints their identifiers to paste into the config.

## Player menu

`/optimizer` or **F7**. Profiles, per-option toggles with FPS/visual impact badges, benchmark, frame-cap guide, hardware scan with graphics recommendations, kill/hit effects, settings export/import codes, reset to defaults.

Rows with a padlock are locked by the server (`Config.Locked`). Rows with an amber line conflict with another running resource (`Config.Conflicts`).

## Health tab (admins)

Shows server tick grade, hitches per hour, memory, a 60-minute hitch timeline and a graded resource table with three views:

| View | Source | Load column |
|---|---|---|
| Server | probe reports + last deep scan | % of server main thread |
| All clients | telemetry from every player sharing data | median ms per frame across players |
| My client | the admin's own probe reports | ms per frame on this PC |

Grades: Excellent, Good, OK, Poor, Bad. Verdicts: Healthy, Monitor, Edit recommended, Edit required, Remove or replace. Each Poor/Bad row carries a hint (blocking call, per-frame loops, event spam, memory growth).

### Data sources

- **Probe** (`probe.lua`): loaded into each Lua resource via `shared_script '@nayzeee-optimizerv2/probe.lua'`. It times that resource's own threads, event handlers, NUI callbacks, commands, timeouts and exports, and reads its Lua memory. Works on the server and on every client. Lua resources only.
- **Deep scan**: the built-in FXServer profiler (`optimizerscan`). Covers every runtime (JS/C# too) on the server. Expect a small hitch while the trace is written.
- **Client telemetry**: players send FPS, 1% lows and their probe table once a minute. Players can opt out in Advanced > Share performance data; owners can disable it with `Config.Health.clientTelemetry`.

### Probe install

From the Health tab (Probes & scan) click **Install**, or in the server console:

```
optimizerprobe install restart  # add it everywhere, refresh, restart those resources
optimizerprobe install          # add it, activate on the next restart
optimizerprobe restart          # restart resources still waiting for their probe
optimizerprobe status           # coverage, pending restarts, permission problems
optimizerprobe remove           # revert everywhere
```

Adding it by hand: the line goes at the top of that resource's **fxmanifest.lua** (not inside a .lua script), then `refresh` and `restart <resource>`. A manifest edit does nothing until the resource is refreshed and restarted.

Core resources other scripts depend on (qb-core, ox_lib, oxmysql, inventories, `Config.Probe.neverRestart`, and anything listed as a dependency) are never restarted live. They pick up the probe on the next server restart. `Config.Probe.autoInstall` installs on startup, `Config.Probe.autoInstallNew` installs into resources that start later. `Config.Probe.exclude` lists resources never touched (txAdmin's `monitor`, system resources, build tools).

Legacy `__resource.lua` manifests are skipped; add the line by hand.

## Console / admin commands

```
optimizerhealth                       full report
optimizerscan [frames]                profiler deep scan (default 500)
optimizerprobe install [restart]|restart|status|permissions|remove  probe management
optimizeradmin <playerId>             is this player an admin, and why
optimizerpreset <id|all> <preset>     push a profile to a player or everyone
optimizerreset                        reset monitoring counters
```

Client: `/optimizersetup` (re-run wizard), `/optimizerunstuck` (restore control), `/optimizerbench` (benchmark).

## Known limits

- Per-resource client timing needs the probe; FiveM gives scripts no other access to resmon data.
- On Windows, server memory is this resource's Lua heap (no process API). On Linux it is the real process RSS.
- The refresh-rate reading in the hardware scan is an estimate; the frame-cap target you pick is what the adaptive optimizer uses.
- Fix Textures teleports the player briefly and sets invincibility for about a second. Whitelist the resource in your anticheat or disable it with `Config.Background.textureFix.enabled = false`.

## Exports

Client: `GetSettings`, `SetSetting(key, value)`, `ApplyPreset(name)`, `GetFPS`, `GetClientHealth`, `RunBenchmark`.
Server: `GetHealth`, `GetHealthStats`, `GetServerResources`, `GetClientAggregate`, `RunScan(frames)`.
