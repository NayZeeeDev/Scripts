# nayzeee-bodybag `v2.0.0`

**Body disposal + a full Funeral Home job** for ESX Legacy.

Bag a body, carry it, hide it in a trunk, burn it, dissolve it, bury it or dump it at sea, and leave
evidence the police can find. Or do it the legit way: the coroner collects the body, the morgue logs it,
and the funeral director holds a real service that ends with a permanent headstone.

**Requires:** OneSync · `es_extended` · `ox_lib` · `ox_target` · `ox_inventory` · `oxmysql`

---

## Install

1. Put the resource in your resources folder and ensure it **after** its dependencies:
   ```
   ensure ox_lib
   ensure ox_target
   ensure ox_inventory
   ensure es_extended
   ensure nayzeee-bodybag
   ```
2. Run **`sql/funeral_job.sql` once**. It adds the `funeral` job with 4 grades. The other tables are created automatically.
3. Copy everything in `images/` to `ox_inventory/web/images/`.
4. Add the items below to `ox_inventory/data/items.lua`.
5. **Set your funeral home locations.** The defaults are placeholders next to the Pacific Bluffs cemetery.
   Stand on each spot in-game, type **`/nzcoords`**, copy the result into `Config.Funeral.Locations` and `Config.Funeral.Plots`,
   then set `Config.Funeral.SetupDone = true`.
6. Restart.

> Images not included: `coffin.png`, `bodybag.png`, `ashes.png`, `flowers.png`, `urn.png`, `death_certificate.png`.

## ox_inventory items

The `server = { export = ... }` lines make the items usable. Tools explain how to use them when you use them.

```lua
['bodybag'] = { label = 'Body Bag', weight = 1200, stack = true, close = true,
    server = { export = 'nayzeee-bodybag.useTool' },
    description = 'Heavy-duty zippered bag. For... storage.' },

['body_crate'] = { label = 'Military Crate', weight = 8000, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useCrate' },
    description = 'Sealed crate. Sinks like a rock.' },

['coffin'] = { label = 'Coffin', weight = 15000, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useCoffin' },
    description = 'A proper send-off.' },

['shovel'] = { label = 'Shovel', weight = 2500, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useTool' },
    description = 'Six feet is the standard.' },

['powersaw'] = { label = 'Power Saw', weight = 4000, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useTool' },
    description = 'Cuts through anything. Anything.' },

['woodsaw'] = { label = 'Wood Saw', weight = 1500, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useTool' },
    description = 'Slow, quiet, gets it done.' },

['gasmask'] = { label = 'Gas Mask', weight = 800, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useGasmask' },
    description = 'Protects against toxic fumes. Use to put on/take off.' },

['acid'] = { label = 'Hydrochloric Acid 32%', weight = 3000, stack = true, close = true,
    server = { export = 'nayzeee-bodybag.useTool' },
    description = 'Dissolves organic material completely.' },

['matches'] = { label = 'Matches', weight = 50, stack = true, close = true,
    server = { export = 'nayzeee-bodybag.useTool' },
    description = 'Three Brown safety matches.' },

['burn_barrel'] = { label = 'Burn Barrel', weight = 6000, stack = false, close = true,
    server = { export = 'nayzeee-bodybag.useBarrel' },
    description = 'Red sulfur drum. Burns hot.' },

['severed_head']  = { label = 'Severed Head',  weight = 4500, stack = false, close = true, description = 'Wrapped in a black bag. Do not open.' },
['severed_hands'] = { label = 'Severed Hands', weight = 1200, stack = false, close = true, description = 'No fingerprints, no ID.' },
['severed_feet']  = { label = 'Severed Feet',  weight = 1800, stack = false, close = true, description = 'They won\'t be walking anywhere.' },
['skull']         = { label = 'Skull',         weight = 900,  stack = false, close = true, description = 'A trophy. Or a warning.' },
['ashes']         = { label = 'Ashes',         weight = 400,  stack = true,  close = true, description = 'All that remains.' },

-- Funeral home
['flowers'] = { label = 'Bouquet of Flowers', weight = 200, stack = true, close = true,
    server = { export = 'nayzeee-bodybag.useTool' },
    description = 'For the departed.' },
['urn'] = { label = 'Urn', weight = 1500, stack = false, close = true, description = 'Their ashes, at rest.' },
['death_certificate'] = { label = 'Death Certificate', weight = 10, stack = false, close = true,
    description = 'Official record of death.' },
```

---

## How players use it

**Everything is one third-eye option per object.** It opens a menu, and every action says what it does.
If you can't do something yet, the action is **greyed out and tells you exactly what's missing**
("You need a shovel", "Carry a body bag here first", "The trunk is locked").

| Key / command | What it does |
|---|---|
| **`[H]` while carrying** | "What can I do *here*?": load into a crate, barrel or trunk, lower into a grave, dump in the water, store in the morgue, place a casket. |
| **`[G]`** | Put down what you're carrying. |
| **`/bodyhelp`** | In-game guide: every method step by step, which tools you have (✓ / ✗), and GPS to the cemetery, dump spots and funeral home. |
| **Use a tool item** | Explains how that tool is used. |

### Disposal methods
| Method | How |
|---|---|
| **Body bag** | Third-eye a dead body → *Handle Body* → *Place In Body Bag*. Works on dead players and locals. |
| **Crate / Coffin** | Use the item to place it → load a carried bag in, or put a body straight in from next to it. |
| **Vehicle trunk** | Carry the body to the back of a car → `[H]`. Most cars fit 2, the hearse fits 4 (coffins too). |
| **Burn barrel** | Place it → load a bag → *Light It Up* (matches). Ashes + skull chance. |
| **Acid** | Wear the gas mask (use the item) → bag menu → *Dissolve With Acid*. Nothing remains. |
| **Burial** | Shovel → *Bury*. Anywhere gives a shallow grave police can dig up. At the cemetery hole you get a tombstone. |
| **Water** | Carry to a dump spot → `[H]`. Crates sink forever, bags may wash ashore. |
| **Dismember** | Saw → *Handle Body* → *Dismember*. Yields remains and leaves blood. |

### If you get bagged 🆕
Your screen goes dark and a **live panel** shows what's happening ("Someone is carrying you…",
"Locked in a car trunk", "The barrel is getting hot…"), the time, and what happens if your body is destroyed.
Chat and push-to-talk still work. After `Config.Victim.GiveUpAfter` minutes you can type **`/acceptfate`**
instead of waiting.

### Evidence & police
DNA from everyone who handles a body · police see it on *Inspect* · some DNA survives fire, soil and water ·
witness calls with a search-area blip · police trunk search · bodies rot, smell and become unidentifiable.

---

## Funeral Home 🆕

A whitelisted ESX job (`funeral`, grades 0–3). Everything happens at third-eye spots: Staff, Garage, Morgue, Crematory, Counter and Cemetery Plots.

```
Clock in ─▶ Take a hearse ─▶ Answer a coroner call ─▶ Bag / pick up the body ─▶ Load the hearse
   ─▶ Morgue: [H] Store Body  (logged + paid)
         ├─▶ Issue Death Certificate   (item for the family)
         ├─▶ Cremate                   (named urn + paid)
         └─▶ Prepare For A Funeral     (embalmed, in a coffin on the prep table)
                 ─▶ Hearse ─▶ Cemetery plot ─▶ Place Casket ─▶ Begin Service (write the epitaph)
                 ─▶ Lower The Casket ─▶ permanent headstone + paid
```

- **Anyone** can *Call The Coroner* from a body's menu. On-duty staff get a GPS route.
- **Anyone** can buy coffins and flowers at the counter, *Pay Respects* at a headstone, and *Lay Flowers*. Headstones count both.
- **Mourners** within range are told when a service starts and ends, and everyone gets a map blip if `AnnounceServerWide` is on.
- **Police** can read morgue records with DNA.
- Headstones are **permanent** (saved in the DB). The director can clear a plot.
- Pay goes to the employee's bank. Swap `Config.Hooks.FuneralPay` for a society account if you prefer.
- Hearse keys: fill in `Config.Hooks.GiveVehicleKeys` for your key script.

Bodies logged into the morgue follow `Config.CK.OnDisposal`, just like disposal: CK or hospital respawn.

---

## CK

| | |
|---|---|
| `Config.CK.OnDisposal = 'ck'` | A destroyed body (or morgue intake) means that character is logged, the player is kicked, and **only that character** is deleted (or locked). |
| `'respawn'` | The victim wakes up in hospital with NLR (`Config.Hooks.Respawn`). |
| `/ck [id] [reason]` | Consent request to the victim (expires). |
| `/forceck [id] [reason]` | Staff / console. |

## Staff commands
| | |
|---|---|
| `/bodyadmin` | Every active body: teleport, free the victim, delete graves, clear all |
| `/nzcoords` | Shows your position as `vec3` / `vec4`. Click to copy for the config |

## Hooks (bottom of `config.lua`)
`Respawn` (client) · `IsPlayerDead` (server) · `PoliceAlert` (server, for ps-dispatch etc.) ·
`GiveVehicleKeys` (client) · `FuneralPay` (server)

## Exports
```lua
-- server
exports['nayzeee-bodybag']:IsBagged(serverId)
exports['nayzeee-bodybag']:GetActiveCounts()          -- { containers, barrels, trunks, graves }
exports['nayzeee-bodybag']:IsCharacterCKd(identifier)
exports['nayzeee-bodybag']:GetCKHistory(identifier)
-- client
exports['nayzeee-bodybag']:IsCarrying()   -- 'bodybag' | 'crate' | 'coffin' | nil
exports['nayzeee-bodybag']:IsBagged()
exports['nayzeee-bodybag']:IsMaskOn()
```
Statebags: `nzBagged` (player inside a bag) · `nzFuneralDuty` (funeral staff on duty).

---

## Changelog 2.0.0

- **New interaction design.**
  - Each object has one menu, and every action has a description, requirements and time.
  - Locked actions explain why.
  - New `[H]` carry menu and `/bodyhelp` guide.
  - Tool items explain how to use them, and "Next step" tips guide new players (`Config.Tips`).
- **Victim experience:** live status panel, timer, and `/acceptfate` after a wait.
- **Funeral Home job:**
  - duty, hearse garage (fits 4) and coroner calls
  - morgue records, death certificates and cremation into an urn
  - shop
  - funeral services with epitaphs, permanent headstones, respects and flowers
- **Trunks:** per-vehicle rules (`Config.Trunk.Overrides`).
- **Staff:** `/nzcoords` setup helper.
- **Alerts:** police and coroner alerts share one system, and coroner calls get a GPS route.

**Upgrading from 1.x:**
- Add the new items and run `sql/funeral_job.sql`.
- Tool items now use `server = { export = 'nayzeee-bodybag.useTool' }`.
- New config sections: `Victim`, `Funeral`, `Trunk.Overrides`, `Tips`, `HelpCommand`, `CarryMenuKey`, plus 2 new hooks.
