# nayzeee-bodybag `v1.2.0`

Advanced body disposal for ESX Legacy. Bag, crate, coffin, trunk, dismember, cremate,
dissolve, bury, dump, forensics, CK.

**Requires:** OneSync · `es_extended` · `ox_lib` · `ox_target` · `ox_inventory` · `oxmysql`

---

## Install

1. Drop the resource in and ensure it **after** its dependencies:
   ```
   ensure ox_lib
   ensure ox_target
   ensure ox_inventory
   ensure es_extended
   ensure nayzeee-bodybag
   ```
2. Copy everything in `images/` to `ox_inventory/web/images/`
3. Add the items below to `ox_inventory/data/items.lua`
4. Restart. The database tables are created automatically on first start
   (`sql/install.sql` is only needed if your DB user can't create tables).

> No `coffin.png`, `bodybag.png` or `ashes.png` are included. Add your own images or ox_inventory shows a placeholder.

## ox_inventory items

The `server = { export = ... }` lines are what make crates, coffins, barrels and the gas mask
usable. They're already wired up in this resource, so you don't need to add any code.

```lua
['bodybag'] = { label = 'Body Bag', weight = 1200, stack = true, close = true,
    description = 'Heavy-duty zippered bag. For... storage.' },

['body_crate'] = { label = 'Military Crate', weight = 8000, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useCrate' },
    description = 'Sealed crate. Sinks like a rock.' },

['coffin'] = { label = 'Coffin', weight = 15000, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useCoffin' },
    description = 'A proper send-off.' },

['shovel'] = { label = 'Shovel', weight = 2500, stack = false, close = true,
    description = 'Six feet is the standard.' },

['powersaw'] = { label = 'Power Saw', weight = 4000, stack = false, close = true,
    description = 'Cuts through anything. Anything.' },

['woodsaw'] = { label = 'Wood Saw', weight = 1500, stack = false, close = true,
    description = 'Slow, quiet, gets it done.' },

['gasmask'] = { label = 'Gas Mask', weight = 800, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useGasmask' },
    description = 'Protects against toxic fumes. Use to put on/take off.' },

['acid'] = { label = 'Hydrochloric Acid 32%', weight = 3000, stack = true, close = true,
    description = 'Dissolves organic material completely.' },

['matches'] = { label = 'Matches', weight = 50, stack = true, close = true,
    description = 'Three Brown safety matches.' },

['burn_barrel'] = { label = 'Burn Barrel', weight = 6000, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useBarrel' },
    description = 'Red sulfur drum. Burns hot.' },

['severed_head'] = { label = 'Severed Head', weight = 4500, stack = false, close = true,
    description = 'Wrapped in a black bag. Do not open.' },

['severed_hands'] = { label = 'Severed Hands', weight = 1200, stack = false, close = true,
    description = 'No fingerprints, no ID.' },

['severed_feet'] = { label = 'Severed Feet', weight = 1800, stack = false, close = true,
    description = 'They won\'t be walking anywhere.' },

['skull'] = { label = 'Skull', weight = 900, stack = false, close = true,
    description = 'A trophy. Or a warning.' },

['ashes'] = { label = 'Ashes', weight = 400, stack = true, close = true,
    description = 'All that remains.' },
```

---

## How it plays

Everything is done with **third-eye (ox_target)**. `[G]` drops whatever you're carrying (rebindable in FiveM key bindings).

| Step | What you do |
|---|---|
| **Bag** | Third-eye a dead body → *Place In Body Bag*. Works on dead **players and locals (NPCs)**. |
| **Carry** | Third-eye the bag → *Pick Up*. Only one person can hold it. Going down or getting tackled drops it. |
| **Crate / Coffin** | Use the item to place it → third-eye it while carrying a bag → *Load Body*. Or place it next to a body → *Place Body In Nearby Crate/Coffin* (no bag needed). Empty ones can be packed up. |
| **Trunk** 🆕 | Carry a bag to the back of a car → *Put Body In Trunk*. Drive off. *Take Body Out Of Trunk* drops it behind the car. Locked cars can't be opened (police can). |
| **Remove Body** | Third-eye any full container → the victim comes back out. |
| **Barrel** | Use `burn_barrel` → load a bag → *Light It Up* (matches) → 45 s → ashes + skull chance. *Take Body Out* works before it's lit. |
| **Acid** | Put the gas mask **on** (use the item) → third-eye a bag → *Pour Acid*. No mask = fume damage. Nothing is left. |
| **Bury** | Shovel + third-eye a container → shallow grave (dirt pile). At the cemetery: *Lower Into Grave* → bury → tombstone with name + date. |
| **Exhume** | The digger or police, with a shovel. Police see surviving DNA. |
| **Water** | Carry to a dump spot (piers in config) → *Dump Body Here*. Crates sink forever; raw bags wash ashore later and the police get a blip. |
| **Dismember** | Saw + third-eye a dead player → head/hands/feet, blood at the scene, body unidentifiable. |

### Forensics & police 🆕
- Everyone who **bags, carries or loads** a body leaves their DNA (character name) on it.
- Police **Inspect** a body → see the DNA list. Decomposition makes bodies unidentifiable after the `skeletal` stage.
- DNA can survive cremation (written on the ashes / skull item), burial, and water (`EvidenceDestroyed` % in each section).
- **Witness calls:** dismembering, burning, acid, digging and dumping each have a % chance to alert police with a rough search-area blip (`Config.Dispatch`).
- Police get **Search Trunk For Bodies** on any car.
- Rotting bodies make everyone nearby smell them, even inside a trunk.

### Victim side
- Black screen + "You are inside a body bag...". Chat and push-to-talk still work, and your ped follows the bag so people hear you.
- If you get **revived** (admin, medic, bleed-out), you climb out (`Config.ReleaseOnRevive`).

---

## CK

`Config.CK.OnDisposal = 'ck'` (default): any destroyed body = that character is logged, the player is
kicked, then **only that character** is deleted (or locked with `DeleteCharacter = false`).
It still works if the victim logs off while bagged. NPC bodies never CK anyone.
Set `'respawn'` for classic hospital-respawn servers (edit `Config.Hooks.Respawn` for your ambulance script).

| Command | Who | What |
|---|---|---|
| `/ck [id] [reason]` | anyone | Victim gets a consent dialog (expires after `RequestTimeout` s) |
| `/forceck [id] [reason]` | staff / console | Instant CK |
| `/bodyadmin` 🆕 | staff | Every active body: teleport, free the victim, delete graves, clear all |

---

## Hooks (plug in your own scripts — bottom of `config.lua`)

| Hook | Side | Use it for |
|---|---|---|
| `Config.Hooks.Respawn()` | client | Your ambulance job's respawn (respawn mode only) |
| `Config.Hooks.IsPlayerDead(id)` | server | Custom death detection. Return `nil` to use the built-in check |
| `Config.Hooks.PoliceAlert(coords, title, msg)` | server | ps-dispatch / cd_dispatch / your own. Return `true` to skip the built-in alert |

## Exports

```lua
-- server
exports['nayzeee-bodybag']:IsBagged(serverId)          -- is this player inside a bag/crate/trunk?
exports['nayzeee-bodybag']:GetActiveCounts()           -- { containers, barrels, trunks, graves }
exports['nayzeee-bodybag']:IsCharacterCKd(identifier)  -- locked by CK? (DeleteCharacter = false)
exports['nayzeee-bodybag']:GetCKHistory(identifier)

-- client
exports['nayzeee-bodybag']:IsCarrying()   -- 'bodybag' | 'crate' | 'coffin' | nil
exports['nayzeee-bodybag']:IsBagged()     -- am I inside a bag?
exports['nayzeee-bodybag']:IsMaskOn()     -- gas mask worn?
```
Player statebag `nzBagged` is also set while someone is bagged, so your other scripts can check it.

## Discord logs

Set `Config.Logs.Webhook` (everything) and/or `Config.Logs.CKWebhook` (CKs only).

## Custom prop

`stream/xm_prop_body_bag.ydr` is the Black LosSantos Coroner Bag. It **replaces** the vanilla GTA body bag,
so it shows up automatically. Any other resource using `xm_prop_body_bag` will show it too. Delete the file to revert.

---

## Changelog 1.2.0

**Fixes**
- **Security:** the server now checks distance, death and items on every action. Before this, a modded client could bag (and therefore CK) any player from anywhere on the map.
- *Light It Up* showed up without matches (config key typo `requiresMatches`).
- Bags, crates and graves could disappear when no player was nearby (OneSync culling). They now persist.
- New props sometimes never settled on the ground. The client gave up if the prop hadn't streamed in yet, and every client fought over it.
- Two players could pick up the same bag. Two players could bag the same body.
- A disposed body that got exhumed could CK or respawn the victim a second time, or teleport a random player who had reused that server ID.
- Shallow graves are now restored after a restart (the old version saved them to the DB but never loaded them).
- Police exhume and cemetery detection are checked on the server instead of trusted from the client.
- Barrel fire was started once per player in range. Now there's one fire and the particles are cleaned up properly.
- The CK delete now runs after the kick, so ESX's save-on-drop can't race it.
- Victims are restored when the resource restarts, instead of being stuck invisible.
- Server messages now use the same NAYZEEE notify style as the client.
- The `fa-shovel` icon (Font Awesome Pro only) is replaced with `fa-trowel` so the icon actually shows.

**New:** vehicle trunks, NPC bodies, DNA/forensics, police witness alerts + blips, police trunk search,
take a body out of a barrel, inspect barrels, revive-while-bagged release, decomposition smell everywhere
plus unidentifiable skeletons, `/bodyadmin`, Discord webhooks, CK request expiry + cooldown,
auto DB setup, config hooks, more exports, drop when downed or ragdolled.

**Config changes** if you're upgrading: `Config.CK.LogWebhook` → `Config.Logs.Webhook`.
New sections: `UI`, `Carry`, `Trunk`, `Dispatch`, `Admin`, `Logs`, `Hooks`.
