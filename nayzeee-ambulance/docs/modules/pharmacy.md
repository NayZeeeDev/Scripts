# Module: pharmacy (pharmacy shop, health insurance, billing)

Pharmacy counters placed in game, a full storefront window, health insurance plans with an
insurance card, and `NZA.Billing` — the one billing pipeline every treatment, transport and
respawn fee goes through (insurance share, bank / cash, unpaid bills, society + medic cut,
external invoice scripts).

## Files

| File | What it does |
|---|---|
| `server/modules/pharmacy.lua` | catalogue, per-department stock, sessions, restrictions, pricing, buy, staff stock / restock, sales log, auto restock |
| `server/modules/pharmacy_billing.lua` | `NZA.Insurance`, `NZA.Billing`, bills, external invoice adapters, medic → patient bills, insurance card usable, admin commands, auto collect, exports |
| `client/modules/pharmacy.lua` | `pharmacy` position type (NPC, blip, targets, prompt), check-in desk prompt, window session, NUI callbacks, "Send bill" interaction + radial item, exports |
| `html/apps/pharmacy/app.js` + `app.css` | the `pharmacy` NUI app (v5 window + compact bill window) |
| `config/modules/pharmacy.lua` | `Config.Pharmacy` |
| `locales/en/pharmacy.lua` | every string (`pharmacy.*`), also the NUI's |

## Features

### Counters (position type `pharmacy`)
- Placed in the EMS Manager (Positions → Pharmacy). Position data (editable per position):
  `npc` (pharmacist), `staffOnly` (supply counter for on-duty department members), `blip`,
  `insurance`, `bills`, `model` (custom ped model).
- Pharmacist NPC: local ped, invincible, frozen, idle scenario; the model is picked by position
  id from `npc.models`, so a counter always has the same face. Turns to you and waves when you
  open the window, turns to you again after a purchase.
- Map blip per public counter (`blip`), named after the counter label.
- "[E] Pharmacy · Pillbox Pharmacy" prompt at the counter (or "· 3 open bill(s) · $2,055" when
  you owe money). Hidden when the bridge already shows its built-in [E] target prompt.
- Target options: Browse the pharmacy, Health insurance, Pay medical bills, Manage stock
  (perm `pharmacy`, own department).
- Check-in desks (`checkin` positions of the check-in module): "[H] Pay medical bills · 3 open
  · $2,055" while you have open bills (`desk.onlyWithBills = false` shows it always). Opens the
  window in **desk mode** (Bills + Insurance, no shop).
- The window closes when you walk more than `interact.maxDistance` away, go down, or the
  counter is removed.

### Shop (v5 window)
- Title bar: NAYZEEE mark, PHARMACY + department, location chip with "Open" dot, search
  (`/` focuses it, clear button), red Close pill. Status bar with key caps, your name and the
  NAYZEEE signature.
- Sidebar: Shop (All products + every category with counts, icons), Services (Insurance with
  Active / Inactive / Expired, Bills with the open count in red), Staff (Stock with the
  low + sold-out count, Sales log), Wallet card (cash, bank, current plan) pinned to the bottom.
- Header: category title + product count, the active discount chip ("Plus · −20%"),
  Featured / Price / A–Z sort.
- Product cards: item image (`Bridge.Inv.Image`, falls back to the category icon), discount
  tag, Popular tag, stock badge (n left / Low stock amber / Sold out red), category, name,
  2-line description, struck old price, price, "max n per order", `+` button that turns into a
  − qty + stepper once the product is in the order. Restricted products stay visible with a lock
  overlay and the reason ("On-duty medics only", "Needs a medical permission", job / grade /
  licence) unless `showRestricted = false`. Available products sort before sold-out and locked.
- Your order: count badge (bumps on add), lines with image, unit × qty, line total, stepper,
  remove, empty state, Empty order. Summary: subtotal, insurance / staff discount line, sales
  tax (when set), big total, Pay with Cash / Bank (balances, "Short $x" in red), Pay $X
  (`Enter`), inline error messages (stock changed, money, price changed — the window refreshes
  itself from the server reply).
- Success: animated check, printed thermal receipt (receipt no., lines, discount, total, paid
  by, date, barcode), "You saved $x", New order.

### Health insurance
- Member card (NAYZEEE Health Insurance, plan, cover %, holder, member no., valid until,
  Active / Expired), coverage period meter with days left, "how cover works" with a $1,000
  split bar.
- Plans Basic / Plus / Premium (config): price per period, cover %, pharmacy discount %,
  validity, insurance card, Most popular / Your plan ribbons. Buy, renew (+days, capped at
  `maxDays` ahead) or switch (credit for the unused days of the old plan when `prorate`).
  Confirmation dialog, pay with cash or bank.
- `Config.Items.insurance_card` is given / updated with metadata (plan, holder, identifier,
  serial, expiry, label, description). Using the card shows it to you and the nearest player.

### Bills
- Stat tiles (open bills, total due, insurance paid), open bills with reason, time, medic,
  insurance share, amount, Pay; Pay all with confirmation; recently paid.
- `NZA.Billing.Charge` stores an unpaid bill when the patient can't pay (bank, then cash).
  Bills are paid at any pharmacy or check-in desk; the society on the bill gets the money and
  the medic who treated still gets the cut when online (`lateMedicCut`). Optional auto
  collect from the bank (`billing.autoCollect`).

### Staff (perm `pharmacy`, own department; admins everywhere)
- Stock: sales today / last 7 days / society balance / low + sold out tiles; every stocked
  product with a shelf meter (amber low, red empty), order quantity stepper, "Order $x"
  (society pays `stock.orderCost` × base price per unit) and "From inventory (n)" (put your
  own items on the shelf).
- Sales log: time, customer, items, shop / insurance, cash / bank, total and discount.
- Stock is kept per department ("pool"); shelves refill a little by themselves every
  `autoRestock.interval` minutes.

### Send bill (medics)
- Patient menu (players) "Send bill" and EMS radial → Patient → Send bill (nearest player).
- Compact window: patient, insurance chip ("Plus plan pays 65%"), quick amounts, amount,
  reason, live split (insurance pays / patient pays / your cut), cooldown, Send bill (`Enter`).

## Controls
| Key | Where | Action |
|---|---|---|
| E (`interact.key`) | at a counter | open the pharmacy |
| H (`desk.key`) | at a check-in desk with open bills | open the billing desk |
| / | shop | focus search |
| Enter | shop / receipt / dialogs / bill window | pay / new order / confirm / send |
| ESC | window | close (closes a dialog or clears the search first) |

## Config (`Config.Pharmacy`)
`enabled` · `interact` (target, prompt, key, keyLabel, distance, maxDistance) · `desk`
(enabled, onlyWithBills, key, keyLabel, distance) · `pointDefaults` (npc, staffOnly, blip,
insurance, bills) · `npc` (models, scenario, greet, faceTime) · `blip` (sprite, colour,
scale, shortRange) · `payment` (cash, bank, default) · `tax` · `staffDiscount` ·
`stackDiscounts` · `maxLines` · `maxQuantity` · `showRestricted` · `income` (toSociety, share)
· `categories[{ id, icon }]` · `products[{ item | name, price, discount, category, stock,
limit, perm, medicOnly, jobs, minGrade, license, featured, label, description }]` · `stock`
(enabled, orderCost, orderMax, fromInventory, autoRestock{ enabled, interval, amount, charge },
lowAt) · `staff` (perm, salesLog, keepDays) · `insurance` (enabled, giveCard,
cardShowDistance, maxDays, prorate, toSociety, plans[{ id, price, days, cover, pharmacy, icon,
popular }]) · `billing` (useInsurance, insurerPays, otherAccount, unpaidBills, maxUnpaid,
lateMedicCut, notify, autoCollect{ enabled, interval, onLoad }, external, externalKinds,
externalFallback, externalSender, custom) · `invoice` (enabled, perm, distance, max, cooldown,
presets) · `commands` (insurance, bills) · `rates` (open, buy, action).
`Config.Billing` (config/config.lua): `enabled society account medicCut`.

## API

### Server
```lua
NZA.Billing.Charge(target, amount, reason, opts) → true, info | false, err
  -- target: server id | identifier | 'p:<identifier>' | { kind = 'player', sid } | Patient
  -- opts: { medic = src, kind, pid, society, account = 'bank'|'cash', insurance = false,
  --         external = false, silent = true, noBill = true }
  -- info: { amount, covered, pay, paid, method, plan, planLabel, unpaid, bill, invoiced, society, cut }
  -- err: 'no_target' (NPC / unknown), 'external_failed', 'cannot_pay'
NZA.Billing.Bills(identifier, status?) → rows   NZA.Billing.Unpaid(identifier) → total, count, rows
NZA.Billing.CreateBill(identifier, amount, reason, opts) → id
NZA.Billing.PayBill(src, id | 'all', method, ctx?) → ok, { paid, count, method } | err
NZA.Billing.Society(opts) → society account   NZA.Billing.Push(identifier, src?)
NZA.Insurance.Get(src | identifier | 'p:id' | target) → { plan, label, icon, cover, pharmacy, expires, started, serial, active, left } | nil
NZA.Insurance.Raw(x) · Plans() · Quote(identifier, plan) · Set(identifier, plan, days, opts) · Remove(identifier)
NZA.Pharmacy.Catalogue() → products, byId · Stock(pool, product) · Session(src, pointId) · OpenData(src, ctx) · LogSale(...)
```
All database calls await: call them from a thread, an event handler or a callback.

Exports: `Charge(target, amount, reason, opts)`, `GetInsurance(x)`, `SetInsurance(identifier,
plan, days) → bool`, `GetBills(identifier, status?)`, `PayBills(src, method)`.

Bus: `billing:charged (identifier, info)`, `billing:bill (identifier, bill)`,
`billing:paid (identifier, bills)`, `insurance:changed (identifier, row | nil)`,
`pharmacy:sale (src, sale)`, `pharmacy:restock (pool, productId, qty, from)`.

Commands (ace `nza.admin`): `/nzainsurance [id] [plan|none] [days]`, `/nzabills [id] [clear]`.

### Client
```lua
NZA.Pharmacy.Open(pointId, tab?) → bool   -- tab: shop | insurance | bills | stock | sales
NZA.Pharmacy.Close()   NZA.Pharmacy.IsOpen()   NZA.Pharmacy.Bill(serverId) → bool
```
Exports: `OpenPharmacy(pointId, tab?)`, `ClosePharmacy()`, `SendBill(serverId)`.

### Callbacks & events
| Name | Kind | Args → result |
|---|---|---|
| `nza:pharmacy:open` | callback | `(pointId, tab?)` → `{ ok, data }` (starts the session) |
| `nza:pharmacy:refresh` | callback | `(pointId)` → `{ ok, data }` |
| `nza:pharmacy:buy` | callback | `(pointId, lines[{ id, qty }], method, expectedTotal)` → `{ ok, receipt, data }` |
| `nza:pharmacy:staff` | callback | `(pointId)` → `{ ok, staff }` |
| `nza:pharmacy:restock` | callback | `(pointId, productId, qty, 'order'|'inventory')` → `{ ok, staff, msg }` |
| `nza:pharmacy:insurance:buy` | callback | `(pointId, plan, method)` → `{ ok, result, data }` |
| `nza:pharmacy:bills:pay` | callback | `(pointId, id | 'all', method)` → `{ ok, result, data }` |
| `nza:pharmacy:bills:count` | callback | `()` → `{ ok, count, total }` |
| `nza:pharmacy:invoice:info` / `:send` | callback | `(serverId)` / `(serverId, amount, reason)` |
| `nza:pharmacy:bills` | S→C | `(count, total)` after a bill is created or paid |

Errors come back as `{ ok = false, err, msg }` (`pharmacy.err_<err>`).

NUI (`pharmacy` app): `pharmacy:buy`, `pharmacy:insurance`, `pharmacy:payBills`,
`pharmacy:refresh`, `pharmacy:staff`, `pharmacy:restock`, `pharmacy:invoice`, `pharmacy:close`.
Preview: `html/index.html?app=pharmacy&view=shop|receipt|insurance|none|bills|stock|sales|desk|invoice`.

## Security
- A window session starts only through `nza:pharmacy:open` (point exists, type `pharmacy` /
  `checkin`, server-side distance ≤ `maxDistance + 1.5 m`, patient state alive, staff-only rule).
  Every later call re-checks the session point, the distance and the state.
- Prices, discounts, tax and totals are recomputed on the server; the client total must
  match (`price_changed`). Lines are merged, limited (`maxLines`, per-product `limit`),
  restriction checked (perm, medic on duty, job + grade, licence), stock reserved before the
  money is taken, items the inventory refuses are refunded.
- Insurance quotes and credits are server-side; money is checked and removed before the plan
  is written. Bills are always looked up by the caller's own identifier.
- Medic bills need the configured perm (on duty), a medic record, the target within
  `invoice.distance` (server coords), an amount within `invoice.max` and the cooldown.
- Staff actions need perm `pharmacy` in the counter's department (admins everywhere);
  society funds are checked before an order.
- Every callback is rate limited (`Config.Pharmacy.rates`).

## Known limits
- External invoice adapters: okokBilling (`okokBilling:CreateCustomInvoice` server event),
  esx_billing (`billing` table), qb-phone / jim-payments (`phone_invoices` table) and a custom
  function. Payloads follow those scripts' public docs; when an external script fails the
  bill is charged directly unless `externalFallback = false`.
- Licence checks: QBCore / Qbox metadata, ESX `esx_license`, standalone ace
  `nza.license.<name>` (see docs/requests/pharmacy.md for a bridge function).
- Without oxmysql, insurance and stock live in memory and unpaid bills cannot be stored
  (`Charge` then returns `false, 'cannot_pay'` for a player who can't pay).
- Item images come from the inventory when it has the file, else `html/img/items`; products
  that are not ours fall back to the category icon.
