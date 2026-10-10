# nayzeee-squads

Squads and crews for FiveM, rebuilt from the ground up for v3. Browse and create squads, ranks you
name yourself, squad-vs-squad ELO and K/D/A, join requests, a message of the day, an activity log,
playtime and last-seen tracking, alliances, leaderboards, a team HUD, nametags, blips, pings, a
compass, rally points, ready checks and squadmate revives. ESX Legacy, QBCore and Qbox are detected
automatically, and it runs standalone too.

Every notification goes through **ox_lib** (`lib.notify`). There are no built-in toasts.

## Install

1. Drop the folder in your resources and add `ensure nayzeee-squads` to `server.cfg`, after
   `ox_lib` and `oxmysql`.
2. Nothing to import. The resource creates its tables on first start and adds any new columns when
   you update. `sql/nayzeee-squads.sql` is only there for databases whose user can't create tables.
3. Optional, for Discord avatars and role sync: put your bot token in `server.cfg` (never in
   `config.lua`, which is sent to clients) and set `Config.Discord.GuildId`.

   ```cfg
   set nz_squads_bot_token "YOUR_BOT_TOKEN"
   ```

4. Give your staff the admin menu:

   ```cfg
   add_ace group.admin nz_squads.admin allow
   ```

### Requirements

- **ox_lib** — notifications, callbacks, keybinds, progress bars, context menus, text UI
- **oxmysql** — only when `Config.Persistence` is true. Without a database every squad is
  temporary and no stats are kept.
- Optional: **pma-voice** (squad radio), **ox_target** (invite by looking at a player),
  **ox_inventory** (revive items)

## Commands and keys

| Input | What it does |
| --- | --- |
| `/squads` | Opens the menu |
| `/sq <message>` | Squad chat without opening the menu |
| `/sqinvite <id>` | Invite a player by server ID |
| `/sqleave` | Leave your squad |
| `/squadnick <name>` | Set your squad nickname (blank clears it) |
| `/squadadmin` | Staff view of every squad |
| `/squadroles` | Re-sync every online player's Discord roles (staff) |
| `Y` / `U` | Accept or decline the on-screen prompt (invites, ready checks) |
| Middle mouse (tap / hold) | Ping where you're looking / open the ping wheel |
| `G` | Revive the nearest downed squadmate |
| Mouse button 4 (hold) | See nametags further away |

Every key is rebindable by players in the FiveM keybind settings. Commands live in
`Config.Commands`, prompt keys in `Config.Prompts`.

## What's new in v3

- **UI rebuilt in the NAYZEEE v5 style** — sidebar navigation, overview page with stat tiles,
  members, chat, allies, stats, activity, browse, leaderboard, settings and staff pages.
- **ox_lib notifications only.** The old built-in toasts and notify adapters are gone.
- **Join requests** — players can ask to join a locked or invite-only squad. Anyone with the
  `invite` permission sees the request (with an optional note) and accepts or declines it.
  `Config.JoinRequests` sets the expiry, note length and how many a player can have open.
- **Message of the day** — ranks with the `motd` permission can set a note that shows on the
  overview and is sent to members when they join.
- **Squad blurb** — a short description shown in the browser and on the squad preview.
- **Activity log** — joins, leaves, kicks, promotions, ownership changes, alliances, fights, MOTD
  and edits are kept per squad (memory plus `nz_squad_log`), shown on the overview and the
  Activity page. `Config.LogRetentionDays` prunes old lines.
- **Playtime and last seen** — every member's time in the squad is tracked, offline members show
  when they were last on, and the leaderboards can sort by playtime.
- **On-screen prompts** — invites and ready checks show a card you answer with two keys, so
  nobody has to open the menu mid-fight.
- **Kill streaks** — streaks of `Config.Elo.StreakFrom` or more show in the killfeed and roster.
- **Revive flow on ox_lib** — text UI prompt, context menu to pick the item, progress bar with the
  CPR animation.
- **Leaderboard sorting** — squads by rating, wins or K/D; players by kills, K/D, revives or playtime.
- **Staff tools** — rename a squad, clear its MOTD, season reset for every saved squad, and the
  squad's activity log in the staff view.
- **Quiet mode** — one setting that mutes every squad notification and sound except invites and
  downed alerts.
- New exports: `AreAllied`, `SquadMessage`, `NotifySquad` (server), `IsAlly`, `CloseMenu` (client),
  and server events `nz_squads:server:created / joined / left / disbanded / matchScored`.

## Squad types

Players choose one when they create a squad, and it can't be changed afterwards.

| | Temporary | Permanent |
| --- | --- | --- |
| Saved between restarts | no | yes |
| ELO and K/D/A | never tracked | tracked |
| Leaderboard, alliances, activity log | no | yes |
| Ends when | the last member leaves, or `TempMaxHours` passes | the owner disbands it |

Turn either type off in `Config.SquadTypes`. With `Config.Persistence = false`, every squad is
temporary regardless.

## Ranks

Each squad has its own rank list. Members with the `ranks` permission can rename ranks, reorder
them, pick an icon and choose what each one can do: invite players and answer join requests,
remove members, change ranks, edit the squad, set the MOTD, manage ranks, set rally points, start
ready checks and disband.

The top rank is the owner and always holds every permission. A member can only act on ranks below
their own.

## ELO and K/D/A

Kills only count when the killer and the victim are in **different**, non-allied squads. When two
squads trade kills the fight is tracked as an engagement; `Config.Elo.EngagementTimeout` seconds
after the last kill it is scored, ratings move by standard ELO with a margin bonus, and both squads
see the result. Assists go to squadmates who damaged the victim within `Config.Elo.AssistWindow`.

## Affiliations

Squads can ally with each other. Allies see each other's blips and nametags, can't damage each
other, and never trade ELO. Both squads must be permanent and each is capped at
`Config.Affiliations.MaxPerSquad`.

## Notifications

```lua
Config.Notify = {
    Title    = 'Squads',
    Position = 'top-right',
    Duration = 4500,
    Icon     = 'users',
    Icons    = { invite = 'envelope', chat = 'message', ... },
}
```

Everything, on both the server and the client, is sent with `lib.notify`. Players can mute chat,
ping, request, killfeed and fight-result alerts individually, or everything at once with quiet mode.

## Player preferences

Everything in the Settings page is per-player, saved on their own client:

- **Team HUD** — show or hide, cards or flat bars, left-edge colour, size, opacity, profile
  pictures, armour bar, rank name, K/D, voice indicator, compact mode, card count, bar colours,
  and a drag-to-place position
- **Alerts** — quiet mode, chat, pings, downed alerts, join requests, killfeed, fight results
- **Nametags**, **Map blips**, **Voice** (auto radio), **Compass**

## Exports

**Server**

```lua
exports['nayzeee-squads']:GetPlayerSquad(src)        -- squad table or nil
exports['nayzeee-squads']:GetSquad(squadId)
exports['nayzeee-squads']:GetAllSquads()
exports['nayzeee-squads']:IsInSquad(src)
exports['nayzeee-squads']:AreInSameSquad(srcA, srcB)
exports['nayzeee-squads']:AreAllied(srcA, srcB)      -- same squad or allied squads
exports['nayzeee-squads']:GetSquadRank(src)          -- { level, name }
exports['nayzeee-squads']:HasSquadPerm(src, 'kick')
exports['nayzeee-squads']:AddSquadElo(squadId, 25)   -- returns the new rating
exports['nayzeee-squads']:SquadMessage(squadId, 'text')   -- system line in squad chat
exports['nayzeee-squads']:NotifySquad(squadId, 'text', 'inform')
```

**Client**

```lua
exports['nayzeee-squads']:GetSquad()
exports['nayzeee-squads']:IsInSquad()
exports['nayzeee-squads']:IsSquadMember(serverId)
exports['nayzeee-squads']:IsAlly(serverId)
exports['nayzeee-squads']:GetSquadRank()
exports['nayzeee-squads']:HasSquadPerm('rally')
exports['nayzeee-squads']:GetSquadElo()
exports['nayzeee-squads']:OpenMenu()
exports['nayzeee-squads']:CloseMenu()
```

## Customising

`config.lua` and everything in `bridge/` stay readable under escrow.

- `bridge/server.lua` — character names, identifiers, item checks, who is allowed to use squads,
  and the revive call. Point `Bridge.Revive` at your own ambulance job if you use one.
- `bridge/client.lua` — how downed state is detected, and what happens on the client when someone
  is revived.
- `Config.Features` — switch off anything you don't want.

## Troubleshooting

**Every squad comes out temporary.** Permanent squads need the database. The server console
prints exactly why on start: `oxmysql is not started` (put `ensure oxmysql` before this resource),
`Could not create or upgrade the database tables` (connection string or missing CREATE/ALTER
rights — fix that, or run the SQL file by hand), or `Config.Persistence is false`.

**No notifications.** This resource only uses `lib.notify`; make sure ox_lib is started before it.

**Team HUD isn't showing.** It needs `Config.Features.Hud`, the player's own "Show team HUD"
setting, and to be in a squad.

## Performance

Idle cost is effectively zero: nothing loops while you are not in a squad. The server sends health
and armour only when they change, far-away members' coordinates only after they move, blip and
nametag loops run only while you are in a squad with that feature on, the ping draw loop stops as
soon as the last ping expires, and kills are reported once per death by the victim.
