# NAYZEEE Billing 1.0.0

Personal and society billing, invoice templates, group permissions, pay by reference, physical invoices and cash registers for FiveM.
Works on **ESX, QBCore and Qbox**. Built on the NAYZEEE UI v5 design system; every colour and every string is configurable.

Discord: discord.gg/nayzeeedev

---

## Features

**Dashboard**
- Greeting header with Pay by reference / Pay All / New Invoice, plus balance, outstanding, money in and money out cards
- **Weekly Summary**: banking-style bars, received and paid side by side for each of the last 7 days (today highlighted), with the week total and the change against last week
- **Up next**: open invoices as a ticket you flip through (most urgent first) with paid progress, due time and a copyable reference
- Latest activity feed, profile and status card in the sidebar, keyboard shortcuts (`N` new invoice, `R` pay by reference, `S` switch account, `1`–`9` pages)
- **Personal and society accounts**, each with its own balance. Switch from the sidebar.

**Invoices**
- **Received / Sent** tables with search, status filters (with counts), due-date filters and pagination
- Right-click any row to **View**, **Pay**, **Print** or **Cancel**
- **Bulk payments**: tick several invoices and pay them in one click
- Side detail panel with a paper-style invoice, reference copy button, payment history, disputes, refunds and print
- **Pay by reference**: look up any invoice by reference (e.g. `LSPD-7KQ2MZ4P`) and pay it from your own cash or bank, even if it's someone else's. References carry 8 random characters, so they can't be guessed.
- Installments, tips (society invoices), disputes, refunds to whoever paid
- **Refunds** take the revenue share back from the issuer (unclaimed payouts first, then their bank) and routed VAT back from the VAT society; the society covers the rest. Personal invoices are refunded by their sender.

**Society billing**
- Send invoices as your job, and bill other configured societies (society-to-society)
- Society-received invoices are paid from the society account
- **VAT** on new invoices (per-society rate or exempt), optionally routed to a dedicated society (e.g. `government`)
- **Revenue share**: the issuing employee earns a % of every society invoice they send (excluding VAT)

**Templates**
- Tabs with custom name, icon and colour, plus a live preview
- Drag & drop to reorder, edit prices inline, add and delete items
- Society templates are seeded from `presets.lua` and then edited in-game; global presets are shared by everyone; players can keep personal templates
- The create-invoice modal picks a template and an item, or a custom reason and amount

**Permissions** (per society)
- Groups (Manager, Finance, Sales, Limited, plus your own) with toggles across 17 permissions in Invoices / Templates / Management
- Assign any employee, online or offline, to a group from the UI
- Defaults come from job grades (`sendGrade`, `manageGrade`, framework boss)
- Bosses and `manageGrade` employees always have the Manager group. An assignment lapses when the employee's grade changes (promotion, demotion, rehire), so it falls back to the grade default.

**Activity log**
- Every invoice, payment, template change and permission change, with who did it and when
- Search, category filters, pagination; personal and society views

**Inspect** (admins, and society members with the *inspect* permission)
- Look up any citizen by name or identifier, or any society, and see their full billing history, outstanding balance and total paid
- Non-admins only see invoices involving their own society ("Job View")
- Admins can cancel, **delete single records** and **clear every record for an identifier**

**More**
- **Physical invoice item** for online citizen recipients; using it opens the paper invoice with a Pay button. Receipt item on payment. **Print invoice** gives a copy.
- **Overdue collection**: flag expired invoices with a one-time late fee, or collect automatically from the bank after X days, **including offline characters**. Society recipients are charged from their society account.
- **Cash registers** with a live customer display and checkout on the customer's screen
- **Billing Admin** page (sidebar, or `/billingadmin`) with **register placement**: *Spawn prop* puts a till prop on the counter with a crosshair raycast for restaurants without a till; *Existing register* aims a ball at a till that's already in the map to set the third-eye target. A key bar at the bottom of the screen shows the controls. In-game registers can be moved the same way.
- **F7 keymapping** (configurable and rebindable)
- **Editable bridges**: framework, banking, inventory, notifications, logger
- **JSON locales** (`locales/en.json`), **UI colours** from config
- **Imports** from esx_billing, okokBilling and qb-phone
- **Compatibility**: `esx_billing:sendBill` and the esx_billing callbacks keep working

---

## Installation

1. Requirements: [ox_lib](https://github.com/overextended/ox_lib), [oxmysql](https://github.com/overextended/oxmysql), OneSync.
2. Put `nayzeee-billing` in your resources and start it **after** your framework, inventory and banking:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure es_extended        # or qb-core / qbx_core
   ensure ox_inventory
   ensure nayzeee-banking    # or your banking script
   ensure nayzeee-billing
   add_ace group.admin nayzeee.billing.admin allow
   ```
3. Configure `config.lua`, `societies.lua` (jobs that bill as a society) and `presets.lua` (starting templates).
4. Restart. Tables are created and upgraded automatically; data from older installs is kept.

### Items

**ox_inventory** (`ox_inventory/data/items.lua`):
```lua
['billing_invoice'] = { label = 'Invoice', weight = 5, stack = false, close = true, client = { export = 'nayzeee-billing.useInvoice' } },
['billing_receipt'] = { label = 'Receipt', weight = 5, stack = false, close = true, client = { export = 'nayzeee-billing.useInvoice' } },
```

**qb-core** (`qb-core/shared/items.lua`):
```lua
billing_invoice = { name = 'billing_invoice', label = 'Invoice', weight = 5, type = 'item', image = 'billing_invoice.png', unique = true, useable = true, shouldClose = true, description = 'An invoice' },
billing_receipt = { name = 'billing_receipt', label = 'Receipt', weight = 5, type = 'item', image = 'billing_receipt.png', unique = true, useable = true, shouldClose = true, description = 'A payment receipt' },
```

The default ESX inventory keeps no item metadata. Use ox_inventory, or set `Config.Items.Invoice.Enabled` / `Receipt.Enabled` to `false`.

---

## Banking

`Config.BankingIntegration = 'auto'` uses the first started backend:

1. `nayzeee-banking` (personal and society accounts; statements read "Invoice LSPD-7KQ2MZ4P · LSPD" under *Bill*)
2. `qb-banking`
3. `okokBanking`
4. `Renewed-Banking`
5. `qb-management`
6. ESX shared accounts (`esx_addonaccount`, when `es_extended` runs)
7. `wasabi_banking`
8. `none`

Personal invoices only need the framework. Society invoices need a society backend; without one, society money goes to the issuing employee. Invoices from scripts (no employee) are held and credited to the society account as soon as it can be reached.

`fd_banking` and `custom` (your own functions in `Config.Banking.Custom`) can be selected explicitly.

> **wasabi_banking**: the adapter uses `AddMoney('society', job, amount)`, `RemoveMoney('society', job, amount)` and `GetAccountBalance(job, 'society')`. Check these against your version.

**nayzeee-banking**: list every society job in its `Config.Accounts.societyAccess` so the society account exists. If nayzeee-banking intercepts `esx_billing:sendBill` (its `Config.Bridge.events`), remove that entry so invoices aren't created twice.

---

## Register placement

Open **Billing Admin** (sidebar > Admin, or `/billingadmin`), pick a mode, fill in the label, society and radius, then **Start placing** (the UI closes while you place):

| Mode | Use it when | Controls |
|---|---|---|
| Spawn prop | The restaurant has no till | The till follows your crosshair as you look around · **Scroll** rotate (Shift: fine) · **E** place · **G** cancel |
| Existing register | The map already has a till | Aim the ball at the till (that spot is the third-eye target) · **Scroll** third-eye radius · **E** place · **G** cancel |
| My position | Quick add | Adds the register where you stand |

Props come from `Config.Registers.Placement.Props` (only those models can be placed); spawned tills are local objects created for players within `PropDistance`. Use the crosshair button on an in-game register to move it. Config registers accept `model` and `heading` too.

## Imports

Run in the server console (or as an admin):
```
billingimport esx_billing
billingimport okokBilling
billingimport qb-phone
```
Each row is imported once (re-running skips what's already there). Imported invoices get new references.

---

## Developer interfaces

### Client exports
```lua
exports['nayzeee-billing']:OpenBilling(page?)            -- overview / received / sent / templates / activity / permissions / inspect
exports['nayzeee-billing']:CloseBilling()
exports['nayzeee-billing']:OpenCreate(recipientServerId?)
exports['nayzeee-billing']:OpenPayByReference(ref?)
exports['nayzeee-billing']:OpenInvoice(invoiceId)
exports['nayzeee-billing']:IsOpen()
```
UI state event: `AddEventHandler('nayzeee-billing:client:uiState', function(open, mode) end)`

### Server exports
```lua
local ref, err = exports['nayzeee-billing']:CreateInvoice({
    target = source or identifier,     -- or targetSociety = 'police'
    society = 'mechanic',              -- sender society (optional)
    sender = employeeSource,           -- optional
    senderName = 'LS DMV',             -- optional, system invoices
    items = { { label = 'Tow', amount = 250, quantity = 1 } },
    reason = 'Towing', notes = '...', dueDays = 7, vat = 0.08,
})
exports['nayzeee-billing']:GetInvoice(ref)
exports['nayzeee-billing']:GetInvoices(sourceOrIdentifier, { status = 'open' | 'all', limit = 50 })
exports['nayzeee-billing']:GetUnpaidTotal(sourceOrIdentifier)
exports['nayzeee-billing']:HasUnpaidInvoices(sourceOrIdentifier)
exports['nayzeee-billing']:PayInvoice(source, ref, 'bank' | 'cash', partialAmount?)
exports['nayzeee-billing']:CancelInvoice(ref, reason)
exports['nayzeee-billing']:GetSocietyStats(society)
```
The legacy `CreateInvoice(sender, target, items, company)` and `GetPlayerInvoices` still work.

### Server events
```lua
nayzeee-billing:server:invoiceCreated   (invoice)
nayzeee-billing:server:invoicePaid      (invoice, { amount, tip, method, payer })
nayzeee-billing:server:invoiceCancelled (ref, reason)
nayzeee-billing:server:invoiceRefunded  (ref, amount)
```

---

## Customising

- **Colours**: `Config.UI.Colors` (accent, chart colours, danger/warning/success, background, panel)
- **Text**: copy `locales/en.json` to `locales/<lang>.json`, translate it and set `Config.Locale`. Missing keys fall back to English.
- **Framework**: `bridge/framework/esx.lua`, `qb.lua`, or implement `custom.lua` and set `Config.Framework = 'custom'`
- **Banking / inventory / notifications / logs**: `bridge/banking.lua`, `bridge/inventory.lua`, `bridge/client.lua`, `bridge/logger.lua`

## Browser preview

Open `html/index.html` in a browser to see the UI with sample data. Pages: `?page=overview|received|sent|templates|activity|permissions|inspect`, with `&account=society` for the society view, `&modal=create|ref|tpl`, `&rail=91`, or `?view=paper|pos|display`.
