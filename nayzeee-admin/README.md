# 🛡️ nayzeee-admin

Staff panel, quick menu, moderation, reports and server tools for ESX, QBCore, Qbox and standalone.

{% hint style="info" %}
Idle cost is 0.00 ms. Every loop (noclip, names, coords, spectate, tools, duty blips) only runs while it is switched on.
{% endhint %}

## 📦 Dependencies

| Resource | Required | Notes |
| --- | --- | --- |
| ox_lib | Yes | Callbacks, zones, raycast, cache |
| oxmysql | Yes | Database |
| es_extended / qb-core / qbx_core | No | Detected automatically |
| ox_inventory / qb-inventory | No | Inventory view, give and remove items |
| nayzeee-notify | No | Used for notifications and announcements when running |
| pma-voice | No | Staff call |
| screenshot-basic | No | Player screenshots |

## ⚙️ Installation

1. Drop `nayzeee-admin` into your resources folder.
2. Add `ensure nayzeee-admin` after `ox_lib`, `oxmysql` and your framework.
3. Put your license in `Config.Owners` in `config.lua`. Owners always have full access.
4. Start the server. Tables are created on their own (`Config.AutoInstallSQL`). You can also run `sql/install.sql` yourself.
5. Press `F10` in game, open **Staff > Members** and add your team. `F9` opens the quick menu.

{% hint style="warning" %}
Only add licenses you trust to `Config.Owners`. Owners skip every permission check.
{% endhint %}

## 🔧 Main settings

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Framework` | `'auto'` | `auto`, `esx`, `qb`, `qbox` or `standalone` |
| `Config.Owners` | `{}` | Licenses with full access |
| `Config.HierarchyProtection` | `true` | Staff cannot act on staff above them |
| `Config.DefaultDuty` | `true` | Staff join on duty |
| `Config.Warnings.MaxBeforeBan` | `3` | Auto ban after this many warnings, `0` to turn off |
| `Config.Jail.TimeMode` | `'playtime'` | `playtime` only counts down while online, `date` uses real time |
| `Config.Weather.Builtin` | `false` | `true` makes this resource sync weather and time |
| `Config.Map.Image` | `''` | Map image for the live map (put it in `web/img/`) |
| `Config.Logs.Webhooks` | `''` | Discord webhook per log category |
| `Config.Logs.Chat` | `false` | Log chat messages (category `chat`) |
| `Config.Keybinds` | all `''` | Extra admin actions you can put on a key |
| `Config.Discord.RoleSync` | `false` | Give staff groups from Discord roles |

## ⌨️ Commands

| Command | Default key | Description |
| --- | --- | --- |
| `/admin` | F10 | Open the panel |
| `/adminq` | F9 | Quick menu |
| `/adminsearch` | - | Panel with search open |
| `/noclip` | - | Toggle noclip |
| `/tpm` | - | Teleport to waypoint |
| `/back` | - | Back to last position |
| `/names` | - | Names and IDs over heads |
| `/coords` | - | Coords box, `/coords copy` copies vec4 |
| `/inspect` | - | Entity inspector |
| `/spectate id` | - | Spectate a player |
| `/admincar` | - | Save the car you sit in to your garage |
| `/report` | - | Players open a report |
| `/sentence` | - | Players check their jail time |
| `/sc message` | - | Message every staff member online |
| `/revive [id]` `/heal [id]` | - | No id = yourself |
| `/car model` `/dv` `/fix` | - | Spawn, delete or repair a vehicle |
| `/kick /ban /warn /jail /unjail /bring /goto /tp /announce /staff /staffduty` | - | Chat and console commands |

Keys can be changed in GTA Settings, Key Bindings, FiveM. Turn off any command you already have in another resource (for example `/revive` from your ambulance job) with `enabled = false`.

## ⌨️ Keybinds

The panel and quick menu close on the same key that opened them.

**Panel**

| Keys | Action |
| --- | --- |
| `Esc` or your panel key | Close |
| `Ctrl K` or `/` | Search players, pages and actions |
| `Alt 1-9` | Jump to a page |
| `Alt Q` | Switch to the quick menu |
| `Alt D` | Toggle duty |
| `?` | Show every shortcut |

**Quick menu** (change them in **Settings > Quick menu keys**, saved per player)

| Default | Action | Default | Action |
| --- | --- | --- | --- |
| `1` | Noclip | `T` | Teleport to waypoint |
| `2` | God mode | `B` | Back to last position |
| `3` | Invisible | `H` / `R` | Heal / revive yourself |
| `4` | Super jump | `C` | Copy coords |
| `5` | Fast run | `I` | Entity inspector |
| `6` | Infinite ammo | `F` / `G` / `M` / `X` | Repair / flip / max / delete vehicle |
| `7` / `8` | Names / IDs | `N` / `V` | Jump to player ID box / vehicle box |
| `9` | Coords | `P` / `O` | Open panel / reports |
| `0` | Freeze self | `D` / `A` | Toggle duty / announce |

**Bindable actions** (`Config.Keybinds`, no default key, nothing runs until you press it): duty, god mode, invisibility, player IDs, freeze, heal, revive, repair, flip, delete vehicle, copy coords, open reports, open players.

{% hint style="info" %}
Keybinds are key mappings, not loops. The resource still idles at 0.00 ms.
{% endhint %}

## 🔐 Permissions

Groups are edited in **Staff > Groups**. Each group has a level, colour, optional Discord role, duty outfit and a permission list. `*` gives everything. Add your own permissions in `shared/permissions.lua` under `Addon` and check them from other resources:

```lua
exports['nayzeee-admin']:HasPermission(source, 'my.permission')
```

## 🧩 Exports (server)

```lua
exports['nayzeee-admin']:IsStaff(src)
exports['nayzeee-admin']:IsOnDuty(src)
exports['nayzeee-admin']:GetStaffGroup(src)
exports['nayzeee-admin']:Log(category, action, staffSrc, target, message)
exports['nayzeee-admin']:BanPlayer(targetSrc, reason, duration, staffSrc)   -- duration like '3d', 'perm'
exports['nayzeee-admin']:CreateBan({ name, license, identifiers, reason, duration })
exports['nayzeee-admin']:RemoveBan(banId)
exports['nayzeee-admin']:WarnPlayer(targetSrc, reason, staffSrc)
exports['nayzeee-admin']:JailPlayer(targetSrc, duration, reason, staffSrc)
exports['nayzeee-admin']:UnjailPlayer(targetSrc)
exports['nayzeee-admin']:IsJailed(src)
```

## 🪝 Hooks

`config/hooks.lua` runs your code on ban, unban and warn, lets you plug in a custom weather script, and has `AllowMovement` for anticheats so noclip and teleports are not flagged.

## 🗺️ Zones

Zone behaviours live in `config/zones.lua` (safe zone, speed limit, no vehicles, message). Add your own there and they show up in **World > Zones**.

## 🛠️ Troubleshooting

| Issue | Solution |
| --- | --- |
| Panel does not open | Your license is not in `Config.Owners` and you are not a member yet |
| Live map is empty | Set `Config.Map.Image` and matching `Bounds` |
| Screenshots fail | Start `screenshot-basic` |
| Staff call does nothing | Start `pma-voice` |
| Anticheat kicks on noclip | Add your anticheat call in `Hooks.AllowMovement` |
| Revive does not work | Set `Config.Integrations.Revive` to your ambulance resource |
