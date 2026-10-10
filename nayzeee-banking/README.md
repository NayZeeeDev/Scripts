# 🏦 NAYZEEE Banking

Immersive banking for **ESX Legacy, QBCore and Qbox** — personal, shared, society and savings accounts, physical cards with PINs and limits, credit-scored loans, bills, and scheduled transfers. Built on the NAYZEEE v5 design language (black · white · teal `#08afa2` · red `#e5484d`, Lexend).

---

## 📦 Dependencies

| Resource | Required | Notes |
|---|---|---|
| A framework | ✅ | `es_extended` (ESX Legacy 1.9+), `qb-core` or `qbx_core` — `Config.Framework = 'auto'` finds it |
| OneSync | ✅ | The server checks where a player is before cash moves |
| `oxmysql` | ✅ | Database layer |
| `ox_lib` | ✅ | Callbacks, notifications, input dialogs |
| `ox_target` | ⭕ | Optional — falls back to a key press |
| `ox_inventory` | ⭕ | Optional — cash moves through the `money` item |

---

## 🔧 Install

1. Import `install/install.sql` into your database. Already running an earlier build? Run `install/update.sql` as well.
2. Drop the folder in `resources/[nayzeee]/nayzeee-banking`. **The folder must be named exactly `nayzeee-banking`** — every export, event and NUI callback is namespaced to it. Rename it and the resource prints the reason and stops itself rather than half-working.
3. Add to `server.cfg` **after** your framework (`es_extended`, `qb-core` or `qbx_core`) and your inventory:
   ```cfg
   ensure nayzeee-banking
   add_ace group.admin nayzeee.banking allow
   ```
4. Open `config.lua` and set your bank locations, society jobs and log webhooks.
5. Restart the server. Personal and society accounts are created automatically.

{% hint style="warning" %}
**On QBCore or Qbox, remove `qb-banking` / `Renewed-Banking` / any other banking script** — two banks mirroring the same `bank` money fight each other. Boss menu money in `qb-management` (or its `management_funds` table) is kept in step automatically.
{% endhint %}

{% hint style="info" %}
Existing money is not migrated. If you're moving off another banking script, run a one-off query to copy `users.accounts` bank balances into `nz_bank_accounts.balance`.
{% endhint %}

---

## ⚙️ Key settings

| Setting | Default | Description |
|---|---|---|
| `Config.Accounts.startingBalance` | `2500` | Balance a new personal account opens with |
| `Config.Accounts.transferFee` | `0.0` | Fraction taken on player-to-player transfers |
| `Config.Accounts.societyAccess` | table | Job → grades allowed to reach the society account |
| `Config.Cards.maxPerAccount` | `3` | Cards allowed per account |
| `Config.Cards.express` | `2500` | Payments under this skip the PIN when express is on |
| `Config.ATM.requireCard` | `true` | An active card is needed to use an ATM |
| `Config.ATM.pinAttempts` | `3` | Wrong PINs before the card auto-blocks |
| `Config.Savings.interestRate` | `0.02` | Paid every `payoutMinutes` |
| `Config.Loans.tiers` | table | Amount, interest, term and credit gate per tier |
| `Config.Credit.bands` | table | Score → label shown in the UI |
| `Config.Bills.latePenalty` | `0.15` | Added once a bill goes overdue |
| `Config.Scheduled.intervals` | table | Hourly / daily / weekly standing orders |
| `Config.DirectDeposit.enabled` | `true` | Players choose bank or cash for wages |
| `Config.Locale` | `'en'` | Which file in `locales/` the client prompts and notifications come from |

**Translating.** Copy `locales/en.lua` to, say, `locales/de.lua`, change `Locales['en']` to `Locales['de']`, translate the right-hand side and set `Config.Locale = 'de'`. A line you leave out falls back to English, and a key with no English line shows as the key itself rather than breaking anything. So far this covers the branch prompts and target labels, the notifications raised on the client and the phone-store text; messages written by the server scripts are still English in those files. The text inside the bank UI, the ATM screen and the phone app lives in the `web/` files and is edited there.

---

## 💳 What's in it

**Accounts** — personal, savings, shared (up to 8 members with per-member deposit / withdraw / transfer rights) and society accounts gated by job and grade.

**Cards** — four types (debit, secured, unsecured credit, platinum credit) with real credit lines, statements, minimum payments and interest. Four styles, 4-digit PINs, daily spend limits with a live meter, express contactless, freeze / unfreeze, report lost, paid replacements, and an optional physical inventory item. Wrong PINs at an ATM block the card.

**Loans** — four tiers gated by credit score. Instalments pull automatically, missed payments cost credit, three misses default the loan and add a penalty. Early payoff refunds part of the interest.

**Credit score** — 0–850, moved by on-time payments, late payments, cleared loans and defaults. Defaulted players cannot borrow again until they settle.

**Savings** — interest on a timer, deposit and withdrawal tracking, optional savings goal with a progress ring.

**Bills** — jobs on the issuer list can invoice a player from their society account. Overdue bills gain a late fee. Players can switch on auto-pay.

**Society payroll** — optional. ESX pays wages by default; switch `Config.Payroll.mode` to `bank` and management sets a wage per grade instead, with direct deposit honoured.

**Investments** — an in-bank market with sparklines, average entry pricing, and separate realised and unrealised profit. Hands price control to `nayzeee-trading` when it's running.

**Joint cards** — member-specific cards on shared accounts with their own daily limits.

**Billing bridge** — invoices from esx_billing, okokBilling, QBCore and lb-phone land in this bank's bills tab.

**Scheduled transfers** — standing orders on an hourly, daily or weekly rhythm. Pauses itself after three failed runs.

**ATMs** — a cut-down terminal: balance, deposit, withdraw, transfer, bills. Card and PIN gated.

---

## 💳 Card types

Every card is one of four types, set in `Config.CardTypes`. The `kind` field decides how it behaves:

| Type | Kind | Entry | How it spends |
|---|---|---|---|
| Debit Card | `debit` | No credit check | Straight from the linked account |
| Secured Card | `secured` | Deposit, any score | A credit line equal to the deposit you put up |
| Unsecured Card | `credit` | Score 500+ | A credit line with no deposit |
| Platinum Credit | `credit` | Score 700+ | The high line at the lowest rate |

A secured card holds the deposit until the card is closed, then returns it — so a player with a wrecked score can rebuild one by paying their own money back on time. Closing a card with a balance is refused while `closeRequiresZero` is on.

Add, remove or rename types freely. Each entry takes `label`, `price`, `minCredit`, `apr`, `creditLimit` (or a `deposit` block for secured), `dailyLimit`, `item` and `blurb`.

---

## 🧾 Credit lines

Credit and secured cards run a real billing cycle. Charges build a balance, a statement is cut on a timer with a minimum payment, interest is applied to whatever is carried, and missing the minimum adds a late fee and costs credit score. Three misses freeze the card until the balance clears.

| Setting | Default | Description |
|---|---|---|
| `Config.CreditCards.statementMinutes` | `120` | How often a statement is cut |
| `Config.CreditCards.dueMinutes` | `60` | Time to pay after a statement lands |
| `Config.CreditCards.minPaymentPct` | `0.10` | Minimum payment as a share of the balance |
| `Config.CreditCards.minPaymentFloor` | `250` | ...but never less than this |
| `Config.CreditCards.lateFee` | `500` | Added when a statement goes unpaid |
| `Config.CreditCards.missedBeforeFreeze` | `3` | Missed statements before the card freezes |
| `Config.Credit.highUtilisation` | `0.80` | Running the line this hot costs score |

Shops, fuel pumps, rentals — anything can take a card:

```lua
local ok, msg = exports['nayzeee-banking']:chargeCard(cardId, 4200, 'Premium Deluxe Motorsport')
local ok, msg = exports['nayzeee-banking']:chargeCardByNumber('4417 0921 5530 8812', 860, 'Ammu-Nation')
```

Debit cards route the charge to the account, credit cards to the line. The caller doesn't need to know which.

---

## 🎒 Inventory items

Set `Config.Cards.physicalItem = true` and each card type hands out its own item, carrying the card id, holder, account and last four digits in metadata. `install/items.md` has the block for ox_inventory, qb-inventory, qs-inventory and ESX.

`install/images/` has a 3D icon per card type, plus one for every type in every style (`card_debit_teal.png`, `card_credit_chrome.png` …). On ox_inventory each card shows the style the player picked, and changes when they restyle it (`Config.Cards.skinImages`). Other inventories show the per-type image. The icons are drawn from the same colours as the cards in the app; `tools/cardicons.py` renders them again if you add a style.

The same renders are in the bank itself (`web/images/cards/`): every card in your wallet list shows as its own card, ordering or restyling a card shows a big preview and the four styles to click, the phone's card chips show the card, and the ATM screen shows the card you put in. The live card on the Cards page is drawn to match — gold chip, contactless mark, type badge — and leans toward the mouse.

Every entry must be non-stackable — the `cardId` in the metadata is what ties an item to a specific card, and two cards sharing a stack would share an identity. The default ESX inventory keeps no metadata, so leave `physicalItem = false` there.

Using the item shows the card's details. It also means cards can be stolen, planted or handed over in RP — pair it with `markCardStolen`.

**At an ATM the card you carry is the card that goes in.** With more than one on you, the player picks which. No card on you, no ATM. A card that isn't yours still works — on its own account only, with its PIN, inside its daily limit — so a stolen card is worth something, and the owner should report it. Three wrong PINs block it. Replacing a card swaps the holder's item for the new one; old plastic stops working.

---

## 💼 Society payroll

Bosses set a wage per job grade from the **Society** tab. Grades come straight from ESX, so nothing needs listing twice. Wages are drawn from the society account on the interval the boss picks and land in each employee's personal account — or their pocket, if they turned direct deposit off.

| Setting | Default | Description |
|---|---|---|
| `Config.Payroll.maxWage` | `25000` | Highest wage a boss can set per grade |
| `Config.Payroll.minDuty` | `false` | Require a duty flag before paying |

If the society account cannot cover a run, the payment stops and every manager online gets told.

---

## 📈 Investments

A market lives inside the bank. Prices walk on a timer with a pull back toward their starting value, capped by a floor and ceiling per asset. Buying and selling both charge a fee, positions are tracked with an average entry price, and realised profit is banked separately from unrealised.

| Setting | Default | Description |
|---|---|---|
| `Config.Market.tickMinutes` | `5` | How often prices move |
| `Config.Market.tradeFee` | `0.01` | Charged on both sides of a trade |
| `Config.Market.minTrade` | `100` | Smallest order |
| `Config.Market.maxHolding` | `5000000` | Cap on one player's position per asset |
| `Config.Market.assets` | table | Ticker, label, starting price, volatility, floor, ceiling |

{% hint style="info" %}
On `auto`, if `nayzeee-trading` is running it becomes the price feed and the internal walk stands down. Any other market resource can drive prices through `setMarketPrice`.
{% endhint %}

---

## 👥 Joint cards

A shared-account owner can issue a card to one specific member from the **Shared** tab. The card carries its own daily limit, so a crew boss can hand out spending power without granting withdrawal rights on the account itself.

| Setting | Default | Description |
|---|---|---|
| `Config.JointCards.maxPerMember` | `1` | Cards one member may hold on one account |
| `Config.JointCards.defaultLimit` | `2500` | Starting daily limit on a member card |
| `Config.JointCards.ownerSeesAll` | `true` | Owner can view and freeze member cards |

Members see and can change the PIN on their own card. Everything else — limit, style, freezing, destroying — stays with the owner.

---

## 🔌 Billing bridge

Invoices raised by other creators' resources land in this bank instead of their own tables, so players only ever look in one place. Handlers are always registered and simply never fire if that resource isn't installed.

| Resource | Event caught |
|---|---|
| esx_billing | `esx_billing:sendBill` |
| okokBilling | `okokBilling:createBill` |
| QBCore invoices | `qb-phone:server:sendNewMail` |
| lb-phone | `lb-phone:invoice:create` |
| Anything else | `nz_bank:bridgeBill` |

{% hint style="warning" %}
Event names drift between forks and versions. If a billing resource isn't coming through, check its actual event name and set it in `Config.Bridge`.
{% endhint %}

Other creators can bill without touching events at all:

```lua
exports['nayzeee-banking']:sendBill(playerId, 'mechanic', 2500, 'Engine rebuild', 'T. Kane')
```

---

## 🎨 Appearance

Server owners repaint the whole UI from one block. Only `accent` really needs changing — the washes, edges and glows are derived from it at runtime.

```lua
Config.UI = {
    accent      = '#08afa2',   -- Buttons, highlights, charts, card faces
    accentLight = '#0fd4c4',   -- Hover and glow
    accentDark  = '#067d74',   -- Button gradient base
    danger      = '#e5484d',   -- Negative amounts, warnings, close button
    background  = '#08090a',   -- Shell background
    panel       = '#0e1011',   -- Panel background
}
```

### Your logo

```lua
Config.UI.logo = 'https://i.imgur.com/yourlogo.png'
-- or from your own resource:
Config.UI.logo = 'nui://my-assets/images/logo.png'
```

It replaces the built-in mark on the intro **and** in the top left of the UI. If the image fails to load, the mark comes back on its own rather than leaving a gap. Landscape logos work best — it's capped at 230×78 on the intro and 104×26 in the title bar.

### Intro

```lua
Config.Intro = {
    enabled  = true,
    duration = 1600,               -- how long it holds before the UI arrives
    tagline  = 'Secure Banking',   -- line under the logo
}
```

The hand-off overlaps rather than cutting: the logo lifts away while the shell scales in behind it, then the sidebar and panels stagger in. Switching pages afterwards is instant — the stagger only plays on open.

---

## 🔌 Turning features off

Each of these removes its tab from the UI and closes the server callbacks behind it:

| Setting | Removes |
|---|---|
| `Config.Cards.enabled` | Cards tab, card ordering, ATM card checks |
| `Config.Savings.enabled` | Savings tab and interest payouts |
| `Config.Loans.enabled` | Loans tab and lending |
| `Config.Bills.enabled` | Bills tab and the billing bridge |
| `Config.Market.enabled` | Investments tab and the price ticker |

---

## 🏧 The machine

The page becomes the prop's screen texture, and **the buttons you press are the ones modelled on the machine** — the four down each side of the glass and the number pad below it.

You look around with the mouse inside a set of limits. A button lights up when it falls under the middle of your view — on the plastic *and* on the screen at the same time — and left click pushes it. The number pad types digits and PINs; the side buttons mean whatever the screen beside them says.

{% hint style="info" %}
The screen itself has no cursor and no way to reach Lua. The client works out which physical button is being looked at and tells the page which one to light, and **the PIN never exists in the browser at all**, only the number of dots to draw. Whether a PIN is right, and whether cash may move, is decided on the server.
{% endhint %}

| Setting | Default | Description |
|---|---|---|
| `Config.ATM.screen.mode` | `'texture'` | `'texture'` or `'draw'` |
| `Config.ATM.screen.island` | per model | Where the page lands on the texture |
| `Config.ATM.screen.outside` | `'#000000'` | The rest of the sheet |
| `Config.ATM.screen.aim` | vec3 | The middle of the screen, from the prop's origin |
| `Config.ATM.screen.camera` | table | `back`, `up`, `side`, `tilt`, `fov` |
| `Config.ATM.screen.camera.sensitivity` | `4.0` | Mouse speed |
| `Config.ATM.screen.camera.lookUp` / `lookDown` / `lookSide` | `18` / `52` / `28` | Degrees of travel from the starting angle |
| `Config.ATM.buttons.proximity` | `0.030` | How close to the middle of your view a button must be |

The starting angle is **worked out from where the camera stands**, not set by hand — point it at the machine's face, a little below the glass so the keypad is in frame from the start. Move `back`, `up` or `side` and the angle follows; a hand-set one would be wrong the moment anything else changed.

Looking down travels further than looking up, because reaching the keypad takes more than reaching the top of the screen. Horizontal distance is scaled by the aspect ratio, so what you have to hit is a circle rather than an ellipse that changes shape on an ultrawide.

### Where the page lands on the texture

These prop textures are **atlases** — the screen face is only a patch of the sheet, and the rest of it is other parts of the prop. Drawing the page across the whole sheet is what makes it come out squashed and off to one side. `island` is that patch, as a fraction of the texture: `x` and `y` are its top-left corner, `w` and `h` its size. The page is scaled into it, so no part of the layout has to know.

{% hint style="warning" %}
`AddReplaceTexture` keys on a texture **name**, not on an object — so while you are at a machine, every other ATM sharing that texture shows the same screen, and any other surface using it takes the colour in `outside`. On the Fleeca wall unit that is the lit sign above the machine. The swap only lasts for the session. This is the trade every DUI ATM makes; the only way out is a streamed model whose screen has a texture name nothing else uses, at which point `island` goes back to full-page.

`mode = 'draw'` avoids all of it by painting a flat panel in front of the machine instead. It needs no knowledge of the model, but it reads as a sticker rather than a screen.
{% endhint %}

### Calibration

Three commands, all needing `Config.Debug = true`:

| Command | For |
|---|---|
| `/atmbuttons` | Look at each button in turn and press `ENTER`. It traces where you are actually aiming, records it against the prop, and prints a block to paste into `Config.ATM.buttons`. `BACKSPACE` goes back, `ESC` prints what you have. |
| `/atmuv` | Nudge the screen patch live. Arrows move, `TAB` swaps between position and size, `[` `]` change the step, `ENTER` prints it. |
| `/atmkeys` | Press a key and it prints its control ID for `Config.ATM.keypad`. |

The side-button positions shipped for the Fleeca machine were derived by projecting them back out of a screenshot at a known camera — the glass centre came back within a millimetre of where it was aimed, so those are right. The number pad sits at a steep angle at the bottom of frame and is harder to measure that way, so **run `/atmbuttons` once per model** and paste the result. It takes about a minute, and it is also how you support an ATM model of your own.

### The keyboard

The number row, `ENTER` and `BACKSPACE` are bound **by key name** through FiveM's own keybind system, so they work on any build and appear in the game's settings under "ATM keypad" if a player wants to rebind them. `Config.ATM.keypad` keeps control IDs as a second route for anyone who prefers them; both end up in the same place and a duplicate press is dropped.

That indirection exists because the number row's control IDs are **not** consistent between builds — the zero key in particular. Binding by name sidesteps it.

| Setting | Default | Description |
|---|---|---|
| `Config.ATM.allowControls` | `{ 37 }` | Controls that stay live at the machine — 37 is TAB, the inventory on most setups |

Everything else is disabled while the camera is locked, so nobody wanders off mid-transaction. If your server binds a phone or anything else you want reachable at an ATM, add its control ID here; `/atmkeys` finds it.

While another resource holds the screen — an inventory, say — the machine keeps its picture but stops listening, so a click meant for an inventory slot cannot also push a button on the ATM behind it.

{% hint style="info" %}
With the in-world screen on, it **is** the interface: if a session cannot start, the player is told the machine is busy rather than being dropped onto the fullscreen keypad. That pad is only for servers running with `Config.ATM.screen.enabled = false`.
{% endhint %}


---

### Transfers at the machine

The keypad has no letters, so a machine transfer goes to a **saved payee**: the side buttons show up to six names (`More` pages through the rest), or press the payee's number on the keypad, then type the amount. Players save payees from the transfer window in the bank or on the phone ("Save as payee"), and manage them in Settings. Up to 12 each; the table (`nz_bank_payees`) is created on start.

### Where cash can move

Deposits and withdrawals only go through **at a branch the player is standing in, or at an ATM the server watched them start a session at** — checked on every request, so a bank menu opened anywhere else can still transfer and pay bills, but can't move cash. The ATM fee, the ATM cap and the PIN come from that session, never from the client.

| Setting | Default | Description |
|---|---|---|
| `Config.Security.branchRange` | `12.0` | Metres from a teller in `Config.Banks` that still count as inside |
| `Config.Security.atmRange` | `3.5` | Metres from the machine a session can start |

---

## 💵 What comes out of the machine

Cash pushes out of the dispenser on a withdrawal and gets drawn back in on a deposit. There is only ever one card: it leaves the hand as it reaches the slot and carries on into the reader, and on the way out it slides back to the mouth of the slot and the hand takes it. A statement feeds out of the receipt slot.

| Setting | Default | Description |
|---|---|---|
| `Config.ATM.slots.enabled` | `true` | All of it |
| `Config.ATM.slots.cashProp` | `prop_anim_cash_pile_01` | What comes out of the dispenser |
| `Config.ATM.slots.receiptProp` | `prop_fib_letter` | The statement |
| `Config.ATM.slots.default` | table | `cash`, `card` and `receipt` slots |
| `Config.ATM.slots.models` | table | Per-model overrides |

Each slot is a point on the prop — `x` left and right, `z` up and down — plus `inner` and `outer`, how deep the item sits at each end of its trip. Props ease out rather than sliding at a constant speed, so they decelerate into the slot. `outer` is always taken as the end on the player's side, so a slot written the wrong way round still moves the right way.

Place them against a real machine with `/atmslot` (`Config.Debug = true`): a grey marker shows the inner end and a teal one the outer. Arrows move, `TAB` switches axis, `]` cycles slot, `G` switches which end you are moving, `ENTER` prints a block.
{% endhint %}

---

## 📱 Phone app

`Config.Phone.enabled` registers a banking app on the player's phone. The supported phones are detected and registered on their own — when this script starts, when the phone starts after it, and again after a phone restart. If no supported phone is running the app simply is not added and nothing else changes. When the app cannot be added, the F8 console says which phone refused it and why.

| Phone | Resource | How it is registered | Live refresh |
|---|---|---|---|
| lb-phone | `lb-phone` | `AddCustomApp` / `RemoveCustomApp` ([docs](https://docs.lbscripts.com/phone/custom-apps/), [template](https://github.com/lbphone/lb-phone-app-template)) | Yes, `SendCustomAppMessage` |
| Quasar Smartphone PRO | `qs-smartphone-pro` | `addCustomApp` / `removeCustomApp` ([docs](https://docs.quasar-store.com/player-systems/smartphone-pro/create-custom-apps), [template](https://github.com/quasar-store-organizations/custom-app-template)) | Each time the app is opened |
| okokPhone | `okokPhone` | `loadApp` ([custom app template](https://github.com/luxu-gg/okokphone_custom_app)) | No push — catches up when the page is shown again |
| YSeries (YPhone / YFlip) | `yseries`, `yphone`, `yflip-phone` | `AddCustomApp` / `RemoveCustomApp` ([docs](https://docs.teamsgg.dev/paid-scripts/phone/custom-apps), [template](https://github.com/TeamsGG-Development/yseries-custom-app-templates)) | No push — catches up when the page is shown again |

Every phone loads the same page, `web/phone/index.html?phone=lb|qs|okok|ys`; the query tells the page which bridge it is sitting in. Only lb-phone documents a way to push a message into an open app, so on the others a balance that moves while the app is already on screen shows up the next time it is opened.

Not supported, on purpose:

- **The original qs-smartphone** (not PRO) — its custom apps are files copied into the phone's own `html/apps` and `client/apps` folders, not a page another resource can hand it.
- **NPWD** — external apps are React modules built against its own toolkit and loaded into its bundle, not an iframe page, so this UI cannot be dropped in as-is.
- **okokPhone removal** — the template documents no export for taking an app back off, so on okokPhone the icon stays until the phone restarts.

| Setting | Default | Description |
|---|---|---|
| `Config.Phone.enabled` | `true` | Register the app at all |
| `Config.Phone.resource` | `'auto'` | `'auto'` uses the first supported phone that is running; name one (e.g. `'qs-smartphone-pro'`) to pin it |
| `Config.Phone.appName` | `Banking` | Name on the home screen |
| `Config.Phone.preinstalled` | `true` | `false` puts it in the phone's app store (lb-phone, YSeries) |
| `Config.Phone.price` | `0` | Store price when it is not preinstalled (lb-phone) |
| `Config.Phone.nearbyRadius` | `12.0` | How far "nearby" reaches, in metres |
| `Config.Phone.maxRequest` | `25000` | Most one player can ask another for |
| `Config.Phone.maxOpenRequests` | `3` | Requests you can have waiting with one person |
| `Config.Phone.requestMinutes` | `120` | Before a request goes overdue |

Three tabs along the bottom:

- **Money** — balance with a hide toggle, card chips, then stacked blocks for savings, investing, borrowing and bills. Each one opens its own screen.
- **Pay** — a full-screen keypad in the accent colour, then **Send** or **Request**
- **Activity** — unpaid bills, money other people have asked you for and the next loan instalment under *Upcoming*, each with its own Pay button, then recent transactions

{% hint style="info" %}
**Cash never moves on the phone.** There is no Add money and no Withdraw — putting notes in and taking them out needs an ATM or a teller, which is what keeps machines and branches worth walking to. Everything that is just numbers moving works from the phone.
{% endhint %}

### Business

Anyone whose job and grade can use a society account at a branch also gets it on the phone (`Config.Phone.business`): a **Business** card on the home screen, and a page with the balance, **Add money** and **Take out** between the business and their own account, **Send from** the business, the payroll and the latest activity. Every move goes through the same server checks as the bank, so a rank that can't touch society money at a branch can't on the phone either. Works on every supported phone, YSeries included.

### Sending and requesting

Tapping Send or Request opens a picker with these ways to find somebody:

| Tab | Where it comes from | Needs |
|---|---|---|
| **Nearby** | Players within `nearbyRadius`, closest first | Nothing |
| **Recent** | People you have sent money to before | `install/update.sql` |
| **Contacts** | The player's own phone contacts | `Config.Phone.contacts` |
| **Saved** | Payees saved from the bank's Send money window | A server that sends `payees` |

An account number can always be typed in instead. A **request** creates a bill the other player pays from their own phone, so it runs through the bills system already in place — limits, overdue penalties and auto-pay all apply to it.

Contacts are the one part that reaches outside this resource. The phone keeps them in its own tables keyed by phone number, so the number has to be walked back to an owner before it means anything to a bank. `Config.Phone.contacts` holds those table and column names because they belong to the phone, not to this script, and they move between versions. The defaults are lb-phone's. If the lookup fails, the console says so once, Contacts comes back empty, and Nearby and Recent carry on working.

### Investing

The Investing screen shows the portfolio total and what it has made or lost, your own positions, and then the whole market. **Tapping any asset opens its own page** — the price, a full chart, and your position in that one asset: units held, average price paid, current value and profit or loss. Buy and Sell sit at the bottom. Holding two assets means two separate positions, each with its own page and its own numbers.

### Borrowing

Loans can be taken out from the phone. With no loan it lists the tiers, greying out the ones your credit score cannot reach yet; with a loan open it shows what is still owed, how far through you are, and **a countdown to the next instalment** — turning red as it gets close. Pay the instalment or clear the balance from the same screen.

Cards, accounts, bills and settings open as sheets over the top. It calls the same server callbacks as the bank UI, so a limit or permission set in config applies on the phone without being configured twice. An open app refreshes itself whenever a balance moves.

The UI lives in `web/phone/` and is deliberately phone-shaped rather than a shrunk desktop layout, so porting it to another phone resource means adding one adapter to `client/cl_phone.lua` — that file is left out of escrow for exactly that reason.

---

## 🔊 Sounds

Seven sound files live in `web/sounds/` — a keypad press, the card going into the reader, notes being counted, the dispenser, an approval, a decline and a statement printing. **Every one was made for this resource.** Nothing is licensed in from anywhere else, so they ship with it and there is nothing to credit.

| Setting | Default | Description |
|---|---|---|
| `Config.Sounds.enabled` | `true` | `false` silences everything |
| `Config.Sounds.volume` | `0.6` | Overall, `0.0` to `1.0` |
| `Config.Sounds.files` | table | Point any name at your own `.ogg` in `web/sounds/` |

They all play through the bank's own NUI page, which stays loaded even while hidden — so the ATM screen and the phone both go through it and there is one volume to set. Another resource can borrow it:

```lua
exports['nayzeee-banking']:playSound('approved', 0.5)
```

---

## 💳 Overdraft protection

When a payment would take a personal account below zero, two things can save it, in this order.

**Savings first.** The shortfall moves out of the player's own savings, so nothing is borrowed and nothing is charged. If that covers it, the payment goes through and no line is drawn on at all.

**Then the line.** The account goes negative up to a limit for a fee, with interest once the grace period is up. Paying money back in closes it automatically.

| Setting | Default | Description |
|---|---|---|
| `Config.Overdraft.enabled` | `true` | The whole feature |
| `Config.Overdraft.optIn` | `true` | Players switch it on themselves; `false` makes it always on |
| `Config.Overdraft.savingsFirst` | `true` | Cover from savings before borrowing |
| `Config.Overdraft.savingsFee` | `0.00` | On what gets swept across |
| `Config.Overdraft.limit` | `2500` | How far below zero |
| `Config.Overdraft.scaleWithCredit` | `true` | Better credit earns a wider line |
| `Config.Overdraft.minLimit` | `500` | The line at the bottom of the credit range |
| `Config.Overdraft.fee` | `35` | Charged when the account goes overdrawn |
| `Config.Overdraft.feePerUse` | `false` | `true` charges on every payment while overdrawn |
| `Config.Overdraft.graceMinutes` | `60` | Before interest starts |
| `Config.Overdraft.interestRate` | `0.05` | On what is owed, per tick |
| `Config.Overdraft.interestMinutes` | `60` | How often interest is charged |
| `Config.Overdraft.creditPenalty` | `-8` | Credit hit when it first happens |
| `Config.Overdraft.creditReward` | `3` | Credit back when it clears |

{% hint style="warning" %}
Overdraft cover is worked out **before** the account is locked, because covering may move money out of savings and that is a second account — holding two at once is how a deadlock starts. The final decision is then re-made inside the lock against the real balance, so two payments racing each other cannot both slip through on the same headroom.
{% endhint %}

It is opt-in on purpose. An account quietly going negative is the kind of surprise players open tickets about. A player cannot switch it off while still overdrawn.

---

## 📄 Bank statements

What the account opened at, what came in and went out broken down by category, and every line behind it with its running balance.

| Setting | Default | Description |
|---|---|---|
| `Config.Statements.enabled` | `true` | The Statements page, the phone screen and the ATM option |
| `Config.Statements.fee` | `0` | Charged per statement |
| `Config.Statements.maxRows` | `250` | Lines on one statement |
| `Config.Statements.atmPeriod` | `'week'` | What the ATM prints |

Available in three places: the **Statements** page in the bank UI, a **Statement** screen on the phone, and out of the **receipt slot** at an ATM, with the paper feeding out of the machine.

{% hint style="info" %}
The opening balance is read off the running balance of the last transaction *before* the period, not worked backwards from today. A statement of an old month stays correct no matter what has happened to the account since.
{% endhint %}

```lua
local statement = exports['nayzeee-banking']:getStatement(accountId, 'month')
```

---

## 🗄️ Upgrading an existing install

`install/update.sql` adds the columns that arrived after the first release. Import it once; it is safe to run again.

{% hint style="danger" %}
If you imported an older copy of `update.sql`, **check it worked.** The old version used `ADD COLUMN IF NOT EXISTS`, which MariaDB accepts and **MySQL 8 rejects outright** — leaving the database unpatched with no obvious error. The current file works on 5.7, 8 and MariaDB, and ends with a `SELECT` that lists the six columns so you can see them.
{% endhint %}

The resource checks these columns on start and prints what is missing. Anything absent switches its own feature off:

| Missing | What stops working | Everything else |
|---|---|---|
| `nz_bank_transactions.counterparty` | The phone's **Recent** list | Keeps working |
| `nz_bank_accounts.od_since` / `od_fees`, `nz_bank_settings.overdraft` | **Overdraft protection** | Keeps working |
| `nz_bank_loans.paid_count` / `started_at` / `last_credit` | **Loan anti-churn** and credit from repayments | Keeps working |

No missing column can take the bank down. Each optional part of the account payload is read behind its own guard, so a feature that fails is simply left out rather than leaving players looking at an error.

---

## 🧯 When something goes wrong

Every server callback in this resource is registered through one wrapper. ox_lib does not reply when a callback throws — it logs and stops — which leaves the client in `lib.callback.await` forever. On screen that is a spinner that never finishes, with no error anywhere to read.

So a callback that errors **returns a failure instead**, and prints what went wrong:

```
[nayzeee-banking] nz_bank:accountStatement errored and returned a failure instead of hanging:
[nayzeee-banking]   Unknown column 'counterparty_name' in field list
```

The ATM screen has the matching half: any request it makes gives up after `Config.ATM.timeoutSeconds` and shows a decline rather than waiting forever. Between the two, a broken feature is something you can read and report, not something that strands the player.

---

## 🏦 Fleeca Bank branding

Out of the box the bank is **Fleeca Bank**: a white badge with a teal **F**, the name in bold capitals and a small line of print, in the same style as the Sneaker Co. boxes.

| File | Where it shows |
|---|---|
| `web/images/mark.png` (`Config.UI.mark`) | The badge: title bar, intro, PIN pad, ATM boot, phone header |
| `web/images/logo.png` (`Config.UI.logo`) | Badge + name: ATM header and statements, phone splash |
| `web/phone/icon.png` | The phone app icon |

`Config.UI.name` is the name in the title bar, the intro and on the ATM. To rebrand, change `MONOGRAM`, `NAME`, `TAGLINE` or the colours at the top of `tools/logo.py` and run `python3 tools/logo.py`, or drop your own PNGs in with the same names.

### Using a card at a machine

With physical cards on, **using the card item while stood at an ATM puts that card in the machine** — no menu, no notification. Anywhere else, using it shows whose card it is. On ox_inventory this goes through the item's client export (`install/items.md`); on qs-inventory and the ESX route the items are registered as usable on start.

---

## 🖼️ Your logo

Drop a PNG into **`web/images/`** and name it in `Config.UI.logo`:

```lua
Config.UI.logo = 'logo.png'
```

That is the whole job. It appears in the top left of the bank UI, on the ATM screen, on the lock screen and intro, and in the phone app. If the file is not there the built-in wordmark is used instead, so leaving it alone breaks nothing.

| | |
|---|---|
| Format | PNG with a transparent background |
| Shape | Roughly 3:1, around 600 x 200 |
| Colour | Light artwork — every surface it lands on is dark |

A full URL works too, if you would rather host it elsewhere — `https://...` or `nui://my-assets/images/logo.png` are both left as they are.

{% hint style="info" %}
`web/images/` is **left out of escrow**, so the file can be replaced whenever you like without touching anything else.

The bank UI, the ATM screen and the phone app sit at three different depths in the resource, so no single relative path could work for all of them. A bare filename is turned into a full URL once, server-side, and anything that already looks like a URL is passed through untouched.
{% endhint %}

---

## 🧩 Compatibility

| Setting | Default | Options |
|---|---|---|
| `Config.Inventory` | `ox_inventory` | `ox_inventory`, `qs-inventory`, `qb-inventory`, `esx` |
| `Config.Target` | `ox_target` | `ox_target`, `qb-target`, `none` (key press + marker) |
| `Config.Society` | auto-detect | `addon_account_data`, `management_funds`, `bank_accounts`, or your own table and columns |
| `Config.CurrencyRight` | `false` | `true` renders `1 500$` |

Branches always have a way in. The target option goes on the teller, or on a small zone where the marker stands when `Config.SpawnPeds = false`. If the configured target resource is not actually running, the key press takes over until it starts, and its options are put back if it restarts.

A wrong `Config.Inventory` value falls back to ESX money rather than eating someone's cash. The society table is probed on first sync and the detected one is printed with `Debug = true`.

### Branch opening hours

```lua
Config.WorkingHours = { enabled = false, openHour = 6, closeHour = 22, atmsAlwaysOpen = true }
```

Branches close overnight, ATMs keep working. That's the point — night-time players get pushed onto cards and ATM limits instead of full banking. Windows crossing midnight work (`openHour = 22, closeHour = 6`).

### Housekeeping

| Setting | Default | Description |
|---|---|---|
| `Config.MaxSavedTransactions` | `250` | Rows kept per account; older ones are trimmed. `0` keeps everything |
| `Config.UpdateCheck` | off | Point at a JSON endpoint returning `{ "version": "1.0.0" }` |
| `Config.Accounts.numberChangeCost` | `250` | Reissue your own account number |
| `Config.Cards.pinChangePrice` | `0` | Charge for a PIN change |
| `Config.Cards.limitResetHours` | `24` | Rolling window the card limit resets on |
| `Config.Cards.member` | `1` / `2500` | Cards per member on a shared account, and their limit |
| `Config.Loans.chargeOffline` | `true` | `false` pauses instalments while the borrower is offline |
| `Config.Loans.cooldownMinutes` | `120` | Wait after settling before borrowing again |
| `Config.Loans.minHoldMinutes` | `60` | Clear it sooner and it does nothing for your credit |
| `Config.Loans.minPaymentsForCredit` | `2` | Instalments needed before clearing improves your score |
| `Config.Loans.originationFee` | `0.02` | Taken off the top when the loan lands |

{% hint style="warning" %}
Those four exist because without them a player takes a loan, clears it on the spot, and farms credit score for nothing. Credit is now awarded once per payment cycle, only for payments that cover the instalment, and only on clearing a loan that was actually carried.
{% endhint %}

{% hint style="info" %}
The card limit is a rolling window, not a calendar day. A card maxed at 23:55 is not free again five minutes later.
{% endhint %}

---

## 🔗 Framework integration (ESX · QBCore · Qbox)

`server/sv_framework.lua` is the only file that knows which framework is running. Everything else works on one player shape — identifier (the ESX identifier, or the QBCore/Qbox `citizenid`), job and grade, cash and the framework's `bank` money — so every feature behaves the same on all three.

| | ESX | QBCore | Qbox |
|---|---|---|---|
| Player bank money mirrored | `bank` account | `PlayerData.money.bank` | `PlayerData.money.bank` |
| Society money mirrored | `esx_addonaccount` / `addon_account_data` | `qb-management` / `management_funds` | `management_funds` |
| Offline job (scheduled transfers, society rights) | `users.job` | `players.job` | `players.job` |
| Multi-job | a multi-job resource | `qb-multijob` | built in (`PlayerData.jobs`) |
| Card items usable | ox export / `RegisterUsableItem` | ox export / `CreateUseableItem` | ox export |
| Admins | ESX group or ACE | ACE (`group.admin`) or QB permission | ACE (`group.admin`) |

QBCore grade names are labels ("Chief"), so `Config.Accounts.societyAccess` is matched without caring about case, and a grade marked `isboss` counts as `'boss'` — the same list works on every framework.

### ESX details


Our tables are the source of truth, so ESX's own `bank` account and the `esx_addonaccount` society balances are mirrored against them — in both directions. Our balance is pushed out the moment it changes, and anything that moves ESX's figure behind our back is folded into our ledger on the next sync. Nothing on the server has to be patched.

That includes wages. ESX already pays them out of `society_<job>` every `Config.PaycheckInterval`, so by default it keeps doing exactly that and the money simply lands in this bank.

| Setting | Default | Description |
|---|---|---|
### Who pays wages

One switch:

```lua
Config.Payroll.mode = 'esx'   -- ESX pays, nothing to set up  (default)
Config.Payroll.mode = 'bank'  -- this resource pays instead
```

On `esx`, the Payroll panel in the Society tab just says so, and everything else in `Config.Payroll` is ignored.

On `bank`, each player's ESX paycheck is switched off with `xPlayer.togglePaycheck(false)` so nobody is paid twice, bosses set a wage per grade from the Society tab, and direct deposit is honoured.

On **QBCore and Qbox** `esx` mode means "the framework pays": its own salary loop keeps paying into the `bank` money and it lands in this bank through the mirror. Those frameworks pay everyone from one loop with no per-player switch, so for `bank` mode **turn the framework's paycheck off in its own config** — the resource prints a reminder on start.

{% hint style="warning" %}
`togglePaycheck` is ESX Legacy 1.9+. On an older build the resource prints a warning — either stay on `esx` mode, or patch the pay line in `es_extended/server/paycheck.lua`:

```lua
TriggerEvent('nz_bank:paycheck', xPlayer.source, salary, xPlayer.job.label)
```
{% endhint %}

---

## 📁 What is where

```
nayzeee-banking/
├─ config.lua            open — every setting
├─ lock.lua              open — folder name check
├─ locales/              open — Lua-side strings
├─ install/
│  ├─ install.sql        run this once
│  ├─ uninstall.sql      drops every table
│  ├─ items.md           card items for every inventory
│  ├─ images/            card item images (3D, one per type and per style)
│  └─ REPLACE_paycheck.lua   optional, pre-1.9 ESX only
├─ server/
│  ├─ sv_bridge.lua      open — billing integrations
│  ├─ sv_esx.lua         open — framework mirror
│  ├─ sv_multijob.lua    open — multi-job adapters
│  └─ …                  protected
├─ client/
│  ├─ cl_phone.lua       open — phone app registration
│  ├─ cl_atm_dui.lua     the in-world ATM screen
│  └─ …
└─ web/
   ├─ atm.html           the ATM display
   └─ phone/             the phone app
```

The three integration files are left out of escrow on purpose — event names and export signatures drift between forks, and you shouldn't need a re-release to fix one.

---

## 🧰 Exports

```lua
exports['nayzeee-banking']:getBalance(identifier)
exports['nayzeee-banking']:addMoney(identifier, amount, label, category)
exports['nayzeee-banking']:removeMoney(identifier, amount, label, category)

exports['nayzeee-banking']:getSocietyBalance(job)
exports['nayzeee-banking']:addSocietyMoney(job, amount, label)
exports['nayzeee-banking']:removeSocietyMoney(job, amount, label)

exports['nayzeee-banking']:createBill(identifier, issuerJob, amount, reason, senderName)
exports['nayzeee-banking']:markCardStolen(cardId, thiefSource)

-- integration
exports['nayzeee-banking']:sendBill(target, issuerJob, amount, reason, sender)
exports['nayzeee-banking']:getAccountByNumber(accountNumber)
exports['nayzeee-banking']:transferBetween(fromNumber, toNumber, amount, label)
exports['nayzeee-banking']:getSummary(identifier)   -- for phones, MDTs, dashboards

-- payroll
exports['nayzeee-banking']:setWage(job, grade, amount, minutes)

-- multi-job
exports['nayzeee-banking']:refreshJobs(identifier)
exports['nayzeee-banking']:getPlayerSocieties(identifier)

-- market
exports['nayzeee-banking']:getMarketPrice(assetId)
exports['nayzeee-banking']:setMarketPrice(assetId, price)
exports['nayzeee-banking']:getHoldings(identifier)

-- cards
exports['nayzeee-banking']:chargeCard(cardId, amount, label)
exports['nayzeee-banking']:chargeCardByNumber(cardNumber, amount, label)
exports['nayzeee-banking']:getCardInfo(cardId)
exports['nayzeee-banking']:markCardStolen(cardId, thiefSource)
```

Route a paycheck through the player's direct-deposit choice:

```lua
TriggerEvent('nz_bank:paycheck', source, amount, 'Police')
```

---

## 🗑️ Uninstalling

`install/uninstall.sql` drops every table this resource created. There's no undo — take a backup first.

---

## 🛠️ Commands

| Command | Description |
|---|---|
| `/bankadmin give <id\|account> <amount>` | Add money to an account |
| `/bankadmin take <id\|account> <amount>` | Remove money |
| `/bankadmin freeze\|unfreeze <id>` | Lock or unlock every account a player holds |
| `/bankadmin check <id\|account>` | Print balances and credit score |
| `/bankadmin credit <id> <score>` | Set a credit score |
| `/bankadmin wipeloans <id>` | Clear all loans on a player |
| `/paysociety <amount>` | Boss payout from society to personal |

---

## 🧭 UI shortcuts

| Key | Action |
|---|---|
| `ESC` | Close |
| `D` | Deposit |
| `W` | Withdraw |
| `T` | Transfer |

---

## 🚑 Troubleshooting

| Issue | Solution |
|---|---|
| A modal hangs on confirm | A server callback errored. Check the console — if it mentions `nz_bank_loans`, run `install/update.sql` |
| The ATM screen sits off the prop | The offsets do not match your model — `Config.Debug = true`, then `/atmtune` |
| ATM keys do nothing when clicked | Same cause: the keypad origin is off. Tune it, or set `Config.ATM.screen.enabled = false` to use the pad |
| Phone app never appears | lb-phone was not running when the resource started — restart this resource, or check the console for the reason it was rejected |
| An ATM circle glows with no "Use ATM" label | You are outside `Config.ATM.targetDistance` but inside ox_target's own scan range — usually the wall unit behind a Fleeca counter. Raise that value, or remove `prop_fleeca_atm` from `Config.ATMModels` |
| A target eye floats where a ped used to be | Restart the resource once — target options are now cleared on stop and stray peds swept on start |
| "WRONG FOLDER NAME" in console | The folder is not named `nayzeee-banking`. Rename it and restart |
| UI opens empty | The player has no personal account yet — rejoin, or check `esx:playerLoaded` is firing |
| "The bank did not respond" | A server callback errored; check the server console for the SQL error above it |
| Society tab missing | The job isn't in `Config.Accounts.societyAccess`, or the grade isn't listed |
| ATM says you need a card | `Config.ATM.requireCard` is on and the personal account has no active card |
| Cash doesn't move | Set `Config.Inventory` to match your setup and check `Config.MoneyItem` |
| Wages paid twice | `Config.Payroll.mode` is `bank` and the `paycheck.lua` patch was applied on top of it — use one or the other |
| Society balance climbs back after wages | `mirrorSociety` is off, or `esx_addonaccount` is not running |
| Balance differs between scripts | `mirrorBank` is off, or the other script writes straight to the database |
| Interest never pays | `Config.Savings.requireOnline` is `true` and the owner is offline |
| Wages never run | No amount is set on that grade, or the society account is empty |
| Payroll shows "No access" | Your grade isn't listed in `Config.Accounts.societyAccess` |
| Society tab vanishes on job switch | Expected with `allowInactiveJobs` off — turn it on to keep every department reachable |
| Multi-job roster not detected | Set `Config.MultiJob.resource` and `export` by hand, or point the SQL fallback at your table |
| Prices never move | `Config.Market.priceSource` points at a resource that isn't running |
| Bills from another script don't arrive | Its event name differs — set it in `Config.Bridge` |
| Credit card won't issue | The account isn't personal, the score is under `minCredit`, or a loan is in default |
| Card won't close | It's carrying a balance and `closeRequiresZero` is on |
| No card items appear | `Config.Cards.physicalItem` is off, or the items aren't in `ox_inventory/data/items.lua` |
| Statements never cut | The card is `debit` — only credit and secured cards bill |
