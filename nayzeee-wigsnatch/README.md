# Wig Snatch V2

Player-vs-player wig snatching. Every snatch is a live tug-of-war between both players, every wig is a unique item with a tier, a style and a history, and getting snatched gives you ways to get even.

## ✨ Features

| Feature | What it does |
| --- | --- |
| **The Clash** | Both players fight in real time. A cursor sweeps a track, press the key while it's in the zone to pull the rope. First to the end wins, or whoever is ahead at the buzzer. The server runs the rope, so macros and fake hits do nothing. |
| **Blindside** | Grab someone from behind and the rope starts in your favour. |
| **Lace glue** | Glue your lace down: you pull harder and the snatcher's zone shrinks. Snatching a glued wig rolls better tiers. |
| **6 tiers** | Common to Mythic, with luck from streaks, glue, bounties, revenge and your title. Legendary and Mythic pulls are announced to the city. |
| **Unique wigs** | Serial number, tier, style name, length, lace type, condition, who it came from and every past owner. |
| **Wear wigs** | Put on any wig that fits your character. If someone snatches it, your real hair shows underneath. A decoy. |
| **Bald with a timer** | Losing your real hair leaves you bald until it grows back. Survives relogs. A barber can fix it early. |
| **Revenge** | Snatch back whoever snatched you for bonus rep and luck. Feuds keep paying. |
| **Bounties** | Put money on whoever snatched you. The next person to snatch them collects. Unclaimed bounties refund. |
| **Trading** | Sell or gift wigs to nearby players. They get a prompt with the wig's details and price. |
| **Buyer + market** | Text the buyer, he runs to you. Each tier's price drops as the city floods it, then recovers. |
| **Catalog** | Every hairstyle maps to a style name. Collect them all for milestone rewards. |
| **Titles + perks** | 8 titles from Fresh Face to Snatch Legend. Shorter cooldowns, wider zones, better prices, more luck. |
| **Haircuts** | Scissors and clippers: offer a cut, they accept, you pick the style. Clippers can force a buzz cut on someone cuffed, downed or with their hands up. |
| **Barbers** | Grow your hair back, undo a haircut, repair wigs. |
| **Wig Vault** | Tablet with profile, wigs, catalog, bounties, leaderboards and the city feed. |
| **Protection** | Victim immunity, new player protection, protected jobs, safezone statebags + export, optional passive mode. |
| **0.00 resmon** | No loops while idle. Everything runs on events. |

## 🧩 Requirements

| Resource | Required | Notes |
| --- | --- | --- |
| OneSync | Yes | Server checks distances and positions |
| ox_lib | Yes | Callbacks, commands, zones |
| oxmysql | Yes | Tables are created automatically |
| Framework | Yes | ESX Legacy, QBCore or Qbox (auto-detected) |
| Inventory | Yes | ox_inventory (recommended), qb-inventory and forks, qs-inventory. Plain ESX inventory works without wig metadata. |
| ox_target / qb-target | Recommended | Without one, use `/snatch` or a keybind |

## 🚀 Installation

1. Drop `nayzeee-wigsnatch` into your resources.
2. Add the items from `INSTALL/` (`ox_inventory.txt`, `qb-core.txt` or `esx_items.sql`) and copy `INSTALL/images/*.png` into its image folder.
3. Start it after your framework, inventory and target:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure ox_target
   ensure nayzeee-wigsnatch
   ```
4. Give admins the command: `add_ace group.admin command.wigadmin allow`
5. Restart. The database tables create themselves (`sql/install.sql` is there if you prefer to run it by hand).

> Coming from V1? Remove the old resource. Old plain `wig` items still sell to the buyer as Common wigs.

## 🎒 Items

| Item | Use |
| --- | --- |
| `wig` | Snatched wig. Use it to wear it (or open the vault). |
| `wig_glue` | Glue your lace down for 20 minutes. |
| `wig_kit` | Repair a wig's condition from the vault. |
| `hair_clippers` | Buzz cuts (offered or forced). |
| `scissors` | Haircuts the other player accepts. |

## ⌨️ Commands

| Command | Who | What |
| --- | --- | --- |
| `/snatch` | Everyone | Snatch the closest player in front of you (bindable with `Config.Snatch.Keybind`) |
| `/wigs` | Everyone | Open the Wig Vault |
| `/sellwigs` | Everyone | Text the buyer |
| `/wigpassive` | Everyone | Toggle passive mode (if enabled) |
| `/wigadmin restore <id>` | Admin | Give their hair back |
| `/wigadmin givewig <id> [tier]` | Admin | Give a wig |
| `/wigadmin resetcd <id>` | Admin | Clear their cooldown |
| `/wigadmin protect <id> [mins]` | Admin | Protect them for a while (0 removes) |
| `/wigadmin xp <id> <amount>` | Admin | Add reputation |
| `/wigadmin glue <id> [mins]` | Admin | Apply glue |

## 🔌 Exports

**Server**

```lua
exports['nayzeee-wigsnatch']:IsBald(source)              -- boolean
exports['nayzeee-wigsnatch']:GetHairState(source)        -- { bald, wig, cut }
exports['nayzeee-wigsnatch']:RestoreHair(source)         -- clears bald + haircut
exports['nayzeee-wigsnatch']:SetProtected(source, true)  -- for safezone scripts
exports['nayzeee-wigsnatch']:GiveWig(source, 'legendary')
exports['nayzeee-wigsnatch']:GetStats(source)
exports['nayzeee-wigsnatch']:IsInClash(source)
```

**Client**

```lua
exports['nayzeee-wigsnatch']:ReapplyHair()   -- call after your appearance script reloads the skin
exports['nayzeee-wigsnatch']:GetHairState()
exports['nayzeee-wigsnatch']:IsBusy()
exports['nayzeee-wigsnatch']:OpenVault('wigs')
```

## ⚙️ Config highlights

| Setting | Default | Description |
| --- | --- | --- |
| `Config.Clash.Duration` | `6500` | Length of a clash in ms |
| `Config.Clash.Key` | `Space` | Pull key (JavaScript key code) |
| `Config.Clash.Push` | `14 / 15` | Rope movement per pull (snatcher / victim) |
| `Config.Clash.Zone` | `0.16 / 0.18` | Zone size (snatcher / victim) |
| `Config.Snatch.Cooldown` | `90` | Seconds between attempts |
| `Config.Snatch.RegrowMinutes` | `45` | Bald timer. 0 = barber only |
| `Config.Snatch.WornWigReveals` | `natural` | What shows when a worn wig is snatched |
| `Config.Protection.VictimImmunity` | `600` | Seconds before a victim can be snatched again |
| `Config.Protection.NewPlayerHours` | `2` | New character protection |
| `Config.Tiers` | 6 tiers | Weights, prices, rep, lace and length per tier |
| `Config.Bounty.OnlyRevenge` | `true` | Bounties only on people who snatched you |
| `Config.Market.DropPerSale` | `0.04` | Price drop per wig sold of a tier |

Discord webhooks live in `config_server.lua`, which never reaches players.

## 🛠️ Troubleshooting

| Issue | Solution |
| --- | --- |
| Hair resets after using a clothing store | Your appearance script reapplied the whole skin. Call `exports['nayzeee-wigsnatch']:ReapplyHair()` after it loads, or add its event to the list at the bottom of `client/hair.lua`. |
| Wrong hair shows after a snatch | Use base-game drawables in `Config.Snatch.BaldStyle` and `Config.Tools.Cuts`. |
| No third-eye options | Start ox_target / qb-target before this resource, or set `Config.Target = 'none'` and use `/snatch`. |
| Wigs have no tier in the inventory | You're on the plain ESX inventory, which has no metadata. Use ox_inventory. |
| The clash key doesn't respond | Another resource is holding NUI focus. Close it, or change `Config.Clash.Key`. |
| Police can't be snatched | Intended. Edit `Config.Protection.Jobs`. |
