# NAYZEEE Billing 2.0

Billing, invoicing and point-of-sale for FiveM, built on the NAYZEEE UI v5 design system.
Works with **ESX, QBCore and Qbox** and connects to **nayzeee-banking, Renewed-Banking, okokBanking, fd_banking, qb-banking, qb-management and ESX society accounts**.

Discord: discord.gg/nayzeeedev

---

## Features

**For citizens**
- A billing tablet that **everyone** can open (`/billing` or `F6`) to see, pay and track their bills
- Pay with bank or cash, **in full or in installments**
- **Tips** on company invoices (preset %), sent to the employee or the company
- **Dispute** an invoice; the company's managers review it and accept or reject it
- Full history with search and filters, plus receipts with a barcode and a receipt item
- **Reference numbers** per company (`BS-000142`, `LSPD-000031`): find any invoice by typing its reference in the title bar or with `/invoice BS-142`, and copy it with one click
- Notifications on login for unpaid invoices and payouts

**For employees**
- Catalog billing with categories, search and item images. **Prices are enforced by the server**
- Custom line items (per-company toggle), discounts capped per company, notes, custom due dates
- Quick bills (one-click presets)
- **Offline billing** for remote jobs (police, EMS): search any character in the database
- Commission on every paid invoice (global or per-company rate)
- **Cash registers** with a live customer display: the customer watches the order build up, then pays from their own screen with card/cash and a tip

**For bosses**
- Company dashboard: today / 7 days / 30 days revenue, outstanding balance, 7-day revenue chart, top employees, live company account balance
- Company invoice list: cancel, **refund** and resolve disputes. A refund returns everything the customer paid and comes fully out of the company account (commission already paid out and routed tax are not clawed back). Accepting a dispute on a partly paid invoice refunds it.
- Manage the company's own products, categories and quick bills in-game

**For admins** (`/billingadmin`)
- Server overview: revenue by company, outstanding totals, detected framework/banking/inventory
- Create, edit, reset or delete companies (stored in the database, overrides `companies.lua`)
- Catalog editor for any company, with an inventory item picker for images
- Place cash registers at your position, teleport to them, set waypoints, delete them
- Search every invoice on the server, plus an activity log (also sent to Discord webhooks, globally and per company)

**Automation**
- Due dates, automatic **overdue** status and a one-time **late fee**
- Optional **auto-collect**: overdue invoices are charged from the bank after X days
- Sales tax can be routed to a government account (`Config.Tax.Account`)

---

## Installation

1. Requirements: [ox_lib](https://github.com/overextended/ox_lib), [oxmysql](https://github.com/overextended/oxmysql), OneSync (default on modern servers).
2. Drop `nayzeee-billing` into your resources folder and add it to `server.cfg` **after** your framework, inventory and banking resources:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core        # or es_extended / qb-core
   ensure nayzeee-banking # or your banking script
   ensure nayzeee-billing
   ```
3. Grant admin access (either works):
   ```cfg
   add_ace group.admin nayzeee.billing.admin allow
   ```
   or put the framework group in `Config.AdminGroups`.
4. Start the server. Database tables are created and migrated automatically. Upgrading from 1.x keeps all your data.

### Receipt item

**ox_inventory** (`ox_inventory/data/items.lua`):
```lua
['receipt'] = {
    label = 'Receipt',
    weight = 10,
    stack = false,
    close = true,
    client = { export = 'nayzeee-billing.useReceipt' },
},
```

**qb-core** (`qb-core/shared/items.lua`):
```lua
receipt = { name = 'receipt', label = 'Receipt', weight = 10, type = 'item', image = 'receipt.png', unique = true, useable = true, shouldClose = true, description = 'A payment receipt' },
```

**ESX** without ox_inventory has no item metadata, so the receipt item can't show which invoice it belongs to. Set `Config.Receipts.GiveReceiptItem = false` or use ox_inventory.

---

## Banking

`Config.Banking.System = 'auto'` detects the first started resource in this order:

| System | Company money | Balance on dashboard | Statements |
|---|---|---|---|
| nayzeee-banking (ESX / QBCore / Qbox) | ✓ | ✓ | ✓ (personal + company ledger) |
| Renewed-Banking | ✓ | ✓ | ✓ (`handleTransaction`) |
| okokBanking | ✓ | ✓ | – |
| fd_banking | ✓ | ✓ | – |
| qb-banking (v2) | ✓ | ✓ | ✓ (`CreateBankStatement`) |
| qb-management | ✓ | ✓ | – |
| esx_addonaccount | ✓ (`society_<job>`) | ✓ | – |
| custom | your functions in `Config.Banking.Custom` | | |

If no banking system is found, company payments go to the employee who sent the invoice.

### nayzeee-banking integration

nayzeee-banking (ESX, QBCore or Qbox) owns the real bank balances, so billing goes through it instead of the framework's `bank` money. Both resources key players the same way (ESX identifier, or `citizenid` on QBCore/Qbox), so no mapping is needed.

On QBCore/Qbox, if you keep `qb-banking` or `Renewed-Banking` running next to nayzeee-banking, leave `Config.Banking.System = 'auto'`: it picks nayzeee-banking first, and nayzeee-banking keeps their society balances in step. Pointing billing at qb-banking/Renewed directly would bypass the bank's ledger.

- **Company money** uses `addSocietyMoney`, `removeSocietyMoney` and `getSocietyBalance`. The company's job (or its `account` field) must be listed in nayzeee-banking's `Config.Accounts.societyAccess`, otherwise the society account doesn't exist and payments fall back to the employee.
- **Personal bank payments** use `getBalance`, `removeMoney` and `addMoney`, so the customer's statement shows `Invoice BS-000142 · Burgershot` under the **Bill** category, frozen accounts can't pay, and payouts to offline employees land in their account immediately.
- Turn the personal part off with `Config.Banking.Nayzeee.UsePersonalAccounts = false`.

Your banking app can also read and pay bills through billing's exports (see below). For example, a "Bills" tab in nayzeee-banking can call `GetPlayerInvoices` and `PayInvoice`.

---

## Exports

### Server
```lua
-- Create an invoice from any script (system invoice when sender is omitted)
local invoiceId, err = exports['nayzeee-billing']:CreateInvoice({
    target = playerSourceOrIdentifier,
    company = 'police',                 -- optional company id
    sender = officerSource,             -- optional
    senderName = 'LS DMV',              -- optional, for system invoices
    items = {
        { name = 'Speeding', price = 500, quantity = 1 },
        { productId = 'fine_dui' },     -- catalog product (company price)
    },
    notes = 'Plate 46EEK572',
    dueDays = 7,
})

exports['nayzeee-billing']:GetPlayerInvoices(sourceOrIdentifier, includeClosed)
exports['nayzeee-billing']:GetUnpaidTotal(sourceOrIdentifier)
exports['nayzeee-billing']:HasUnpaidInvoices(sourceOrIdentifier)
exports['nayzeee-billing']:PayInvoice(source, invoiceId, 'bank', partialAmount)
exports['nayzeee-billing']:CancelInvoice(invoiceId, reason)
exports['nayzeee-billing']:GetInvoice(invoiceId)
exports['nayzeee-billing']:GetCompany(companyId)
exports['nayzeee-billing']:GetCompanyStats(companyId)
```
The 1.x signature `CreateInvoice(sender, target, items, companyLabel)` still works.

### Server events
```lua
AddEventHandler('nayzeee-billing:server:invoiceCreated', function(invoice) end)
AddEventHandler('nayzeee-billing:server:invoicePaid', function(invoice, payment) end) -- payment = { amount, tip, method, payer }
AddEventHandler('nayzeee-billing:server:invoiceCancelled', function(invoiceId, reason) end)
AddEventHandler('nayzeee-billing:server:invoiceRefunded', function(invoiceId, amount) end)
```

### Client
```lua
exports['nayzeee-billing']:OpenBilling()   -- optional tab: 'bills', 'new', 'history', 'dash'
exports['nayzeee-billing']:OpenAdmin()
exports['nayzeee-billing']:IsOpen()
```

---

## Reference numbers

Every invoice gets a reference players can quote, search and type:

- `Config.Invoices.ReferenceFormat = 'company'` gives each company its own counter: `BS-000001`, `BS-000002`, ... The prefix is the company's **Reference prefix** (set in `/billingadmin`) or its short name. Personal invoices and invoices from other scripts use `Config.Invoices.PersonalPrefix` (`INV`).
- `'random'` uses codes like `INV-7KQ2MZ4P` instead.
- Find an invoice from the box in the title bar or with `/invoice BS-000142`. The short form `/invoice bs-142` works too. You only get a result for invoices you're allowed to see (sender, recipient, the company's bosses, admins, or holding the receipt), and "not found" looks the same either way so references can't be guessed.
- Every invoice and receipt has a copy button next to its reference.

Existing invoices keep their old references.

## Previewing the UI

Open `html/index.html` in a browser to see the UI with sample data:
`?tab=home|bills|new|history|dash|cinvoices|catalog`, `?view=admin`, `?view=pos`, `?view=display`.

---

## What changed from 1.x

**Security**
- Invoice prices, quantities, discounts and totals were trusted from the client. The server now rebuilds every line from the company catalog, clamps discounts per company and enforces the maximum amount.
- Admin callbacks (save company, products, registers...) had no server-side permission check. Every admin and boss action is now checked on the server.
- Anyone could read any invoice by ID. Invoices are now visible only to the sender, the recipient, the company's bosses, admins, or a player holding its receipt.
- Paying the same invoice twice in quick succession could charge twice. Payments are now locked per invoice and use an optimistic database update.
- Any client could open the register display (and steal NUI focus) on any player. Register sessions are now validated on the server: the employee's job and both players' distance to the register.
- XSS in the UI: player and product names were inserted as raw HTML. All text is now escaped.

**Bugs**
- `StartRegisterSession` was defined twice, so registers never assigned a customer. The register flow is rebuilt.
- Bank teller cash collection never worked (`Config.CashRegister.UseTarget` didn't exist).
- A company with 0% tax (police, EMS) showed and charged 8% in the UI.
- Edits to `companies.lua` companies made in the admin panel were lost on restart. They now persist.
- Companies created in the admin panel never reached the client.
- Offline payouts used `playerConnecting`, which runs before the character is loaded. They now run on the framework's player-loaded event.
- The `CreateInvoice` export called a client callback from the server and never worked.
- `ADD COLUMN IF NOT EXISTS` failed on MySQL 8. Migrations are now portable.
- Due dates and `InvoiceExpiry` were never used. Overdue handling is now implemented.
- The "Pay Now" button on the register sent invoice ID `'register'`, which always failed.
