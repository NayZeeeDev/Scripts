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
| **Private wash units** | Lease a unit through the laundromat's back door: GTA's counterfeit cash factory with all of its own equipment switched off. Each unit is its own routing bucket, so crews only ever see their own floor. Build it out with machine crates, manage it from the unit terminal (machines, crew keys, supplies, upgrades). |
| **Money counter** | A counting machine with a live screen everyone nearby can read, heist cash-counter sounds and banknotes flicking out. Counted & strapped stacks pay **+3% at the books**; it can also count your cash and dirty money just for show. |
| **Money pallet** | Finished loads nobody comes back for move onto a pallet that visibly fills with cash. Load them into a duffel, or risk someone grabbing a stack. |
| **Police raids** | 911 calls from inside a unit point to the door with the unit number. Police can breach any unit, scan and seize what they find. A door alarm upgrade warns the crew. |

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
   ensure bob74_ipl        # loads GTA's counterfeit factory interior used by wash units
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

## Wash units

1. **Lease:** at the laundromat's back room (`Config.Facility.entrance`), open **Wash units** and lease one ($250,000 from the bank by default). You're taken straight inside.
2. **Build:** at the **unit terminal** by the door, order machine crates under *Supplies* (washer, press, guillotine, counter, plus paper, solvent and repair kits). Use a crate inside the unit to place it with the see-through preview. The unit holds 6 machines, 10 with both expansion upgrades.
3. **Crew:** the leaseholder hands out keys by server ID under *Crew*. Key holders can enter, build and run machines; only the leaseholder renovates and takes keys back.
4. **Upgrades:**
   - **Soundproofing** cuts 911 calls from machines by 35% per level.
   - **Floor expansion** adds 2 machine slots per level.
   - **Door alarm** warns the crew when police breach.
5. **Police:** a 911 call from a unit lists it at the door. Police open **Wash units → Breach a unit**, force the door (10 s) and land inside that unit, where they can scan and seize.

Requirements:
- **The interior must be loaded.** That's GTA's biker counterfeit factory, which `bob74_ipl` loads.
- **Entity sets get switched off** each time someone enters, so the floor is always empty.
- **Kits only work inside a unit** by default. Set `Config.Placement.mode = 'world'` or `'both'` to allow building anywhere indoors.
- **Check the spawn point.** The point inside (`Config.Facility.interior.inside`) is the factory's usual door spot; nudge it if your build differs.

## Money counter

Target the counter:
- **Count & strap stacks:** feeds every uncounted Clean Stack you carry. The screen ticks up with the heist cash-counter sounds, and the stacks come out strapped (+3% at the books, shown as *strapped* in Cook the Books).
- **Count my cash:** shows your clean cash and dirty money on the screen. Roleplay only.

The screen is a DUI page (`web/counter.html`) drawn in the world, so everyone within 8 m can read it. The model, table, timings, bonus, sounds and particle effect are all in `Config.Counter`.

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
