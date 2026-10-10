# THE WASH — `nz_moneywash`

A money-laundering pipeline for FiveM where every step is a physical, synced machine. Dirty cash goes through the **washer**, then the **re-serial press**, then the **guillotine**, and finally gets **declared as revenue at a front business**. Every load is tracked server-side, police can trace it, the books can be audited, and the whole city shares one laundering rate.

Built on the [bzzz_money](https://bzzz.tebex.io/) prop pack. The UI uses NAYZEEE UI v3.

**Frameworks:** ESX · QBCore · Qbox  **Inventories:** ox_inventory · qb-inventory (and forks)  **Targets:** ox_target · qb-target · built-in fallback

---

## What makes it different

| System | What happens |
|---|---|
| **Living machines** | Every prop is driven by server state, so everyone nearby sees the same thing: the door swings, money tumbles in the drum, the press runs, the blade drops, and the sheet goes from `moneycut_a` → `b` → `c`. A live status read-out floats above each machine. |
| **Read the bills** | Loads come in *Speckled*, *Ink bleed* or *Dye-pack burst*. Pick the wrong temperature and you ruin notes. Spin speed trades cycle time against noise (more 911 calls) and jam risk. Dye solvent halves the dye. |
| **Serial trace** | Every batch has a serial range and a heat value. Police with a **UV Serial Scanner** can scan a player or a machine and see where the money came from and the initials of whoever loaded it. The **re-serial press** reprints the serials and breaks that chain. |
| **Dynamic wash market** | One rate for the whole city. The more money everyone launders in the last hour, the lower it goes. Random street events (Treasury crackdown, Casino weekend…) push it up or down. |
| **Cook the Books** | Washed stacks are declared at a front as revenue split across that business's real lines (bar sales, private dances…). Drift from the usual mix or exceed the daily cap and suspicion rises, and an audit can follow. Every entry is signed. |
| **Clearing house** | Take full value to your bank after a delay, or cash out now at a fee. A Treasury audit on a front freezes part of anything still clearing there. |
| **Treasury audits** | Police and government roles can inspect a front's ledger. Flagged entries show the full name of whoever signed them. They can also order an audit by hand. |
| **Mid-cycle heists** | Anyone without keys can pry open someone else's running or finished machine with a crowbar. The owner gets a break-in alert. Cash ripped out mid-cycle comes out half-washed. |
| **Wear & jams** | Machines wear down. Jams stall the cycle and smoke until someone clears them in a timing minigame; a miss shreds bills. A repair kit resets wear. |
| **Crew line bonus** | When different people run consecutive stations within 45 minutes, the batch pays up to +15%. |
| **Set up anywhere** | Players can buy machine crates and place them indoors with a ghost preview, sharing them with their gang or job. Police can seize them, along with any cash inside. |

---

## Install

1. **Props:** keep `bzzz_money` as its **own resource** and start it **before** this one. Don't merge it in: restarting a resource with spawned props can crash clients, and loading a `.ytyp` twice breaks the props.
2. Requires **ox_lib** and **oxmysql**. ESX needs **ox_inventory**, because batch metadata lives on items.
3. Drop `nz_moneywash` into your resources folder. Tables are created automatically on first start (`sql/install.sql` is there if you prefer to create them yourself).
4. Add the items:
   - ox_inventory → `install/ox_inventory_items.lua`
   - qb-inventory → `install/qb_items.lua`
   - Images → `install/images/` (cut from the prop pack). Solvent, repair kit and scanner need your own icons.
5. `server.cfg`
   ```
   ensure ox_lib
   ensure oxmysql
   ensure bzzz_money
   ensure lev_laundromat   # the MLO the default operation lives in
   ensure nz_moneywash
   ```

## The laundromat (default setup)

Out of the box the operation lives in the **lev_laundromat MLO** (La Mesa, building origin `898.05, -1038.16, 34.25`):

- **Basement → wash room:** 2 washers on the north wall, the guillotine in the middle, the re-serial press along the south wall. Nine pieces of MLO clutter that sat where the machines go are hidden while the resource runs (`hide` in `config/locations.lua`).
- **Shop floor → 6 working coin washers:** the laundromat's own row of washers is hidden and the script's washers stand in their exact spots. They look like normal machines until someone loads one with dirty cash, and anyone in the shop can see the drum full of money. Delete entries from the `laundromat_shop` operation to keep some originals as decoration.
- **Money pallet (basement):** if a finished load sits in a machine for 3 minutes and whoever ran it isn't within 15 m, it gets moved onto the pallet so the machine frees up. The pallet shows stacks of money while it holds anything. **Load into duffel bag** to take your loads (bank-heist cash-grab animation, a duffel on the floor fills up). Others can **Grab a stack** (slow, alerts the owner, may call police); police can **Seize the cash**. The shop washers send their unclaimed loads down to the same pallet.
- **Back office → front business:** "Cook the books" at the office desk, with revenue lines for self-service machines, wash & fold, dry cleaning and vending.

The positions were worked out from the MLO's own `.ymap`/`.ytyp`, not tested in game. If anything sits a little off, fix it in game:

- **Move machine (admin):** target any idle machine, place it with the see-through preview (scroll to rotate, Shift for fine steps, E to confirm). The new spot is saved and survives restarts, and the server console prints the config line if you want to make it permanent.
- **Reset to config spot (admin):** undoes a move.

Admin means the `command.nzmw` ace (`group.admin` by default).

## Configure

| File | What's in it |
|---|---|
| `config/config.lua` | Frameworks, UI colour tokens, props & offsets, dirty money sources, stage timings, wash program, wear, heat, theft, crew, market, books, audits, placement |
| `config/locations.lua` | Fixed operations (machines + decor + optional teleport entrance) and **front businesses** (categories, typical shares, daily cap) |
| `config/sv_config.lua` | Discord webhook + a dispatch hook (ps-dispatch / cd_dispatch / anything) |

**UI colours:** `Config.UI` drives every colour in the NUI (teal, red, amber, font).

**Dirty money:** QBCore `markedbills` (metadata `worth`), ox `black_money` items and the ESX `black_money` account all work out of the box. Add your own in `Config.DirtySources`.

**Shorter loop:** set `Config.Stages.printer.enabled = false` and/or `Config.Stages.cutter.enabled = false`. Items re-route automatically.

**Printer offsets:** the prop author didn't publish ped offsets for the press, so `Config.Offsets.printer` is a starting point. Set `Config.Debug = true` and run `/nzmw_offsets` to draw every offset in-game while you tune.

## Commands

| Command | Who | What |
|---|---|---|
| `/nzmw event` | admin | Force a market event |
| `/nzmw audit <frontId>` | admin | Force a Treasury audit on a front |
| `/nzmw rate` | admin | Print the current rate & saturation |
| `/uvscan` | police | Scan the nearest player (only when no target resource is running) |
| `/nzmw_offsets` | debug | Toggle offset markers |
| Move machine / Reset (target) | admin | Reposition any machine in game |

## Flow cheat-sheet

```
Dirty money ─▶ WASHER  open · load · close · program (temp / spin / solvent) · [jam?] · unload
           ─▶ Wet Cash ─▶ PRESS  + paper rolls · re-serialise · [jam?] · collect
           ─▶ Uncut Sheets ─▶ GUILLOTINE  feed · 3 timing cuts · bundle
           ─▶ Clean Stacks ─▶ FRONT  Cook the Books · clearing (bank) or instant (cash)
```

Payout = `amount × market rate × quality × (1 + crew) × (1 − heat penalty)`, minus the instant fee if you cash out now.

## Security notes

- The server owns every state change. Items only carry a batch id; value, heat, dye and quality never leave the server, so metadata can't be spoofed.
- Every callback checks distance, access, machine state and the session lock. The cutter enforces a minimum interval between cuts.
- The NUI can only reach a whitelisted set of server callbacks.

## Credits

Props & animations: **BzZz** — https://bzzz.tebex.io/ (props must stay unescrowed; point customers to the original pack for updates).
