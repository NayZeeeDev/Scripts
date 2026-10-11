> **Merged into nayzeee-hud.** This module now ships inside the `nayzeee-hud` resource: use `ensure nayzeee-hud` instead of `ensure nayzeee-squads`, and edit `squads/config.lua` (the table is `SquadsConfig`). `exports['nayzeee-squads']` calls keep working. The squads compass was removed in favour of the HUD compass.

# nayzeee-squads

Squads and crews for FiveM: browse and create squads, ranks you name yourself, squad-vs-squad ELO
and K/D/A, leaderboards, team HUD, nametags, blips, pings, rally points, ready checks and squadmate
revives. ESX Legacy, QBCore and Qbox are detected automatically, and it runs standalone too.

## Install

1. Drop the folder in your resources and add `ensure nayzeee-squads` to `server.cfg`,
   after `ox_lib` and `oxmysql`.
2. Nothing to import. The resource creates its tables on first start and adds any new columns
   when you update, so there's no SQL to run. (`sql/nayzeee-squads.sql` is only there for databases
   whose user isn't allowed to create tables.)
3. Add your Discord bot token to `server.cfg` (never to `config.lua`, which is sent to clients):

   ```cfg
   set nz_squads_bot_token "YOUR_BOT_TOKEN"
   ```

   Then set `Config.Discord.GuildId` to your Discord server ID. The bot has to be in that server
   to read members' server avatars.
4. Give your staff access to the admin menu:

   ```cfg
   add_ace group.admin nz_squads.admin allow
   ```

5. Optional: turn on Discord role sync in `Config.Roles` (see below).

### Requirements

- **ox_lib** — callbacks, keybinds, progress bars
- **oxmysql** — only when `Config.Persistence` is true. To run without a database, set it to `false`
  and remove the `'@oxmysql/lib/MySQL.lua'` line from `fxmanifest.lua`. Squads then last until the
  next restart and no stats are tracked.
- Optional: **pma-voice** (squad radio), **ox_target** (invite by looking at a player),
  **ox_inventory** (revive items)

## Commands and keys

| Input | What it does |
| --- | --- |
| `/squads` | Opens the menu |
| `/squadadmin` | Staff view of every squad |
| `/squadroles` | Re-sync every online player's Discord roles (staff) |
| `/squadnick <name>` | Set your squad nickname (blank clears it) |
| Middle mouse (tap) | Ping where you're looking |
| Middle mouse (hold) | Ping wheel |
| `G` | Revive the nearest downed squadmate |
| Mouse button 4 (hold) | See nametags further away |

Every key is rebindable by players in the FiveM keybind settings.

## Squad types

Players choose one when they create a squad, and it can't be changed afterwards.

| | Temporary | Permanent |
| --- | --- | --- |
| Saved between restarts | no | yes |
| ELO and K/D/A | never tracked | tracked |
| Leaderboard | not listed | listed |
| Alliances | not available | available |
| Ends when | the last member leaves, or `TempMaxHours` passes | the owner disbands it |

Temporary squads exist only in memory, so they never touch the database. They get their own id
range and their own radio channel block, so they can't collide with saved squads.

Turn either type off in `Config.SquadTypes`. With `Config.Persistence = false`, every squad is
temporary regardless.

## Affiliations

Squads can ally with each other. Allies see each other's blips and nametags, can't damage each
other, and **never trade ELO** — a kill between allied squads doesn't score a fight.

```lua
Config.Affiliations = {
    MaxPerSquad = 2,       -- 0 turns the whole system off
    RequireBoth = true,    -- both squads have to accept
    Friendly    = true,    -- allies can't hurt each other
    ShareBlips  = true,
    ShareTags   = true,
    MinRankPerm = 'edit',  -- which rank permission can manage alliances
}
```

Alliances are managed from the Allies tab. Both squads must be permanent, and each one is capped at
`MaxPerSquad`. Players can still hide allied blips and nametags in their own settings.

## Ranks

Each squad has its own rank list. Members with the `ranks` permission can rename ranks, reorder
them, pick an icon and choose what each one can do: invite, remove members, change ranks, edit the
squad, manage ranks, set rally points, start ready checks and disband.

The top rank is the owner and always holds every permission. A member can only act on ranks below
their own, so an officer can never kick another officer.

## ELO and K/D/A

Kills only count when the killer and the victim are in **different** squads. Squadmate kills,
suicides and kills on unsquadded players are ignored.

When two squads trade kills, the fight is tracked as an engagement. `Config.Elo.EngagementTimeout`
seconds after the last kill, the fight is scored: whoever got more kills wins, ratings move by
standard ELO, and both squads see the result. Higher-rated squads move less per fight, and a bigger
kill margin moves the rating further.

Assists go to squadmates who damaged the victim within `Config.Elo.AssistWindow` seconds.
Everything is reported by the victim's client, so it costs one network event per death.

## Discord role sync

Players can be given Discord roles automatically for being in a squad, for their squad's tier and
for their rank. It reuses the bot token and `GuildId` from the avatar settings, so there is nothing
new to set up besides the role ids.

```lua
Config.Roles = {
    Enabled = true,
    InSquad = '000000000000000000',   -- anyone in a squad
    Owner   = '000000000000000000',   -- squad owners
    Tiers   = { Gold = '000000000000000000', Elite = '000000000000000000' },
    Ranks   = { ['Officer'] = '000000000000000000' },
}
```

Leave any id blank to skip that role. Roles update when a player joins or leaves a squad, when
their rank changes, and when their squad moves up or down a tier after a fight. With
`RemoveOnLeave` on, a role is taken back as soon as it no longer applies.

**The bot needs the Manage Roles permission, and its own role has to sit above every role you list
here.** Discord refuses the change otherwise, and the console says so.

Every call goes through one queue with a gap between requests, so a busy server won't hit Discord's
rate limits. If you do get limited, raise `QueueDelay`.

Run `/squadroles` after editing the config to re-sync everyone online. Note that `Ranks` matches on
rank *name*, so it only fits servers where squads keep the default rank names — tier and squad roles
work everywhere.

## Nicknames

Members can pick a name they go by inside the squad — from the pen icon on their own row in the
Squad tab, or `/squadnick <name>`. It replaces their character name on the team HUD, nametags,
blips, compass, chat and the roster; the roster still shows the real name beside it in small text.

Nicknames are unique inside a squad, so nobody can pass themselves off as a squadmate. Ranks with
the `kick` permission can reset one below their rank. Length, cooldown and the command live in
`Config.Nicknames`.

## Nametags

What shows above a squadmate's head is set by the server in `Config.Nametag`, and each player can
switch any of it off for themselves:

- **Name** — the player's name
- **Tag** — the squad tag, drawn as the crew tag beside the name
- **Role** — their rank name underneath
- **Health** — the health and armour bar
- **Allies** — allied squads get tags too, in a different colour

## Squad blips

Each squad picks a colour and a marker when it's created, and every member shows in it on the map.
Owners can change both later from the edit screen. Players decide for themselves whether to show
blips at all, whether to use each squad's own colour or one colour for everyone, and whether allied
squads appear.

Add or remove markers in `Config.SquadBlip.Sprites`.

## Automatic radio

With `Config.Voice.AutoJoin`, players go onto their squad's pma-voice channel the moment they join
a squad, and back to whatever channel they were on before when they leave. Temporary squads use a
separate channel block so the two never overlap.

Leave `PlayerCanOptOut` on and players can switch this off in their settings; turn it off to make
squad radio mandatory.

## Compass

A heading strip across the top of the screen with the direction and degrees, the street and area
you're in, and markers for squadmates (red and pulsing when they're down), allied players, the rally
point, your waypoint and live pings — each with its distance. Anything off to the side pins to the
edge with an arrow so you know which way to turn.

It only sends your heading when you actually turn, and markers and the street refresh twice a
second. `Config.Compass` sets what it shows, whether everyone gets it or only players in a squad,
and the range; players can turn it, the street name or the markers off for themselves.

## Notifications

Pick the system with `Config.Notify.System`:

| Value | Uses |
| --- | --- |
| `'auto'` | NayZeee Notify when it's running, otherwise the squad UI's own toasts |
| `'builtin'` | the squad UI's own toasts |
| `'nayzeee'` | NayZeee Notify |
| `'ox_lib'` | `lib.notify` |
| `'esx'` | `ESX.ShowNotification` |
| `'qb'` / `'qbx'` | QBCore / Qbox notify |
| `'okok'` | okokNotify |
| `'mythic'` | mythic_notify |
| `'custom'` | the `custom` function at the bottom of `bridge/client.lua` |

Every adapter lives in `bridge/client.lua`, so a different export name is a one-line change. If the
chosen system errors (resource not running, wrong export), messages fall back to the built-in toasts
and the console says why — nothing gets silently dropped. The killfeed, fight results, ready checks
and revive prompts always stay in the squad UI.

## Player preferences

Everything in the Settings tab is per-player, saved on their own client, and kept between sessions:

- **Team HUD** — show or hide, card or flat-bar style, left-edge colour (squad colour, teal,
  health-driven or none), size, background opacity, profile pictures, animated avatars, armour bar,
  rank name, kills and deaths, voice indicator, compact mode, how many cards, and bar colours
- **Nametags** — the whole tag, plus name, squad tag, rank, health bar, allied squads, and colour
- **Blips** — show or hide, squad colours vs your own, allied squads, and your own colour
- **Alerts** — chat pop-ups and sound, ping pop-ups and sound, downed alerts, killfeed, fight results
- **Voice** — auto-join the squad radio channel
- **Compass** — show or hide, street name, markers

## Exports

**Server**

```lua
exports['nayzeee-squads']:GetPlayerSquad(src)        -- squad table or nil
exports['nayzeee-squads']:GetSquad(squadId)
exports['nayzeee-squads']:GetAllSquads()
exports['nayzeee-squads']:IsInSquad(src)
exports['nayzeee-squads']:AreInSameSquad(srcA, srcB)
exports['nayzeee-squads']:GetSquadRank(src)          -- { level, name }
exports['nayzeee-squads']:HasSquadPerm(src, 'kick')
exports['nayzeee-squads']:AddSquadElo(squadId, 25)   -- returns the new rating
```

**Client**

```lua
exports['nayzeee-squads']:GetSquad()
exports['nayzeee-squads']:IsInSquad()
exports['nayzeee-squads']:IsSquadMember(serverId)
exports['nayzeee-squads']:GetSquadRank()
exports['nayzeee-squads']:HasSquadPerm('rally')
exports['nayzeee-squads']:GetSquadElo()
exports['nayzeee-squads']:OpenMenu()
```

## Customising

`config.lua` and everything in `bridge/` stay readable under escrow, so you can change framework
behaviour without touching the protected files.

- `bridge/server.lua` — character names, identifiers, item checks, who is allowed to use squads, and
  the revive call. Point `Bridge.Revive` at your own ambulance job if you use one.
- `bridge/client.lua` — how downed state is detected, and what happens on the client when someone is
  revived.
- `Config.Features` — switch off anything you don't want. Turning off `Combat` disables ELO and
  K/D/A entirely.

## Troubleshooting

**Every squad comes out temporary / "squads cannot be saved".** Permanent squads need the database.
Check the server console on start — it prints exactly why:

- `oxmysql is not started` — put `ensure oxmysql` **before** `ensure nayzeee-squads` in `server.cfg`.
- `Could not create or upgrade the database tables` — usually the connection string or a database
  user without `CREATE`/`ALTER` rights. Fix that, or run `sql/nayzeee-squads.sql` by hand.
- `Config.Persistence is false` — every squad is temporary by design.

The create screen also shows the reason, and players can no longer pick a permanent squad and get a
temporary one without being told.

**Team HUD isn't showing.** It needs `Config.Features.Hud`, the player's own "Show team HUD"
setting, and to be in a squad. Your own card shows at the top even when you're alone (turn that
off with "Show your own card").

## Performance

Idle cost is effectively zero: nothing loops while you are not in a squad.

- The server sends health and armour only when they change, at most every 750ms, and far-away
  members' coordinates only after they move more than 3m.
- Blip, nametag and voice loops run only while you are in a squad with that feature on.
- The ping draw loop stops as soon as the last ping expires.
- Squad list updates only go to players who have the menu open, and rapid changes are grouped.
- Kills are reported once per death by the victim, not per hit.
