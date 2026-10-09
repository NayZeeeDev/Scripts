# 🧪 NAYZEEE Banking — test plan

Work top to bottom. Each phase assumes the one before it passed, so a failure early on will cause false failures later. Don't skip ahead.

Before you start, open a second client (or grab a friend) — about a third of these need two players.

---

## ⚙️ Phase 0 — Speed the clocks up

Half the systems run on timers measured in hours. Testing them at production values wastes a day. Set these first, test, then put them back.

```lua
Config.Savings.payoutMinutes        = 2
Config.Loans.paymentIntervalMin     = 2
Config.CreditCards.statementMinutes = 2
Config.CreditCards.dueMinutes       = 1
Config.Bills.overdueMinutes         = 2
Config.Debug                        = true
```

{% hint style="danger" %}
Write these down. Shipping with `statementMinutes = 2` means every credit card on your server bills every two minutes.
{% endhint %}

---

## 🚀 Phase 1 — Boot

| # | Test | Expected |
|---|---|---|
| 1.1 | Import `sql/install.sql`, start the resource | No SQL errors in console |
| 1.2 | `ensure nayzeee-banking` after `es_extended` | Starts clean, no red text |
| 1.3 | Check the tables | 12 `nz_bank_*` tables exist |
| 1.4 | Join the server | A row appears in `nz_bank_accounts` with your identifier, type `personal` |
| 1.5 | Check society rows | One `society` row per job in `Config.Accounts.societyAccess` |
| 1.6 | Restart the resource twice | No duplicate accounts created |
| 1.7 | Rename the folder to `banking`, restart | Console prints the folder-name error and stops the resource. No peds, no UI, no exports |
| 1.8 | Rename it back | Starts normally |
| 1.9 | Restart the resource five times in a row | Exactly one teller per branch, one target eye on each, none floating in mid-air |
| 1.10 | Move a bank's coords in config, restart | The old eye is gone — no ghost at the previous spot |

**Stop here if 1.4 fails.** Nothing else will work.

---

## 🏦 Phase 2 — Open the UI

| # | Test | Expected |
|---|---|---|
| 2.1 | Walk to a bank ped, use the target | Intro plays **inside the UI frame**, progress bar advances through named steps, then the bar, sidebar and panels shift in from the right |
| 2.1a | Watch the transition | Nothing snaps into place — the intro slides left as the UI slides in |
| 2.1b | Set a different `Config.UI.accent`, restart | Every teal element repaints, nothing stays the old colour |
| 2.1c | Open any modal | Background dims but stays readable, no blur |
| 2.1d | Turn off `Config.Cards.enabled`, restart | Cards tab gone, ordering refused server-side |
| 2.2 | Check the header | Server name from config, not "Los Santos" if you changed it |
| 2.3 | Press `ESC` | Closes, mouse released, you can move |
| 2.4 | Reopen, click Close | Same |
| 2.5 | Open, then `/car` or move around after closing | No stuck NUI focus |
| 2.6 | Visit every sidebar page | **Nothing scrolls on any page.** Resize the window shorter and repeat |
| 2.7 | Set `Config.Target = 'none'`, restart | Key prompt appears instead, `E` opens it |

---

## 💵 Phase 3 — Money movement

This is the foundation. Everything else moves money through these paths.

| # | Test | Expected |
|---|---|---|
| 3.1 | Deposit 1000 cash | Cash down 1000, balance up 1000, row in Transactions |
| 3.2 | Deposit more than you're carrying | Refused, no money moves |
| 3.3 | Deposit 0, then -500 | Both refused |
| 3.4 | Withdraw 1000 | Cash up, balance down |
| 3.5 | Withdraw more than the balance | Refused |
| 3.6 | Transfer to the other player's account number | Their balance up, yours down, both see a row |
| 3.7 | Transfer to a made-up account number | "No account with that number" |
| 3.8 | Transfer to your own number | Refused |
| 3.9 | Set `transferFee = 0.05`, transfer 1000 | 1050 leaves you, 1000 arrives, separate fee row |
| 3.10 | Transaction search and category filter | Filters correctly, pagination works |

### Race condition check — do not skip

| # | Test | Expected |
|---|---|---|
| 3.11 | Spam the Withdraw confirm button as fast as you can on a balance of 1000, withdrawing 1000 each time | Exactly one succeeds. Balance never goes negative |
| 3.12 | Two players transferring into the same shared account at once | Both land, final balance is the sum, no lost write |

{% hint style="warning" %}
3.11 is the single most important test in this document. If money can be duplicated here, nothing else matters.
{% endhint %}

---

## 💳 Phase 4 — Debit cards

| # | Test | Expected |
|---|---|---|
| 4.1 | Order a debit card, PIN 1234 | Card price leaves the account, card appears on the Cards page |
| 4.2 | Try a 3-digit and a 5-digit PIN | Both refused |
| 4.3 | Order past `maxPerAccount` | Refused with a clear message |
| 4.4 | Change the daily limit and style | Saves, card face changes colour |
| 4.5 | Freeze the card, then unfreeze | Status flips, card face greys out while frozen |
| 4.6 | Report it lost | Status goes to Reported, cannot be unfrozen |
| 4.7 | Order a replacement | New card number, old one gone, fee charged |
| 4.8 | Change the PIN | Saves without error |
| 4.9 | `exports['nayzeee-banking']:chargeCard(id, 500, 'Test')` from console | Balance drops, "Test" in the ledger |
| 4.10 | Charge past the daily limit | Refused |

---

## 🧾 Phase 5 — Credit and secured cards

| # | Test | Expected |
|---|---|---|
| 5.1 | Try to order an Unsecured card with a 300 score | Refused, message names the score needed |
| 5.2 | `/bankadmin credit <id> 750`, order it again | Approved |
| 5.3 | Order a Secured card with a 5000 deposit | 5000 + fee leaves the account, credit limit shows 5000 |
| 5.4 | Deposit below the minimum | Refused |
| 5.5 | `chargeCard` 2000 on the credit card | Balance owed 2000, available drops, charge in the statement |
| 5.6 | Charge past the credit limit | Refused, names how much is left |
| 5.7 | Wait for a statement | Minimum payment appears, due timer counts down, interest row added |
| 5.8 | Pay the minimum before the due time | Missed stays 0, credit score goes up |
| 5.9 | Let one statement lapse unpaid | Late fee added, score drops, missed = 1 |
| 5.10 | Let three lapse | Card freezes, cannot unfreeze until the balance clears |
| 5.11 | Pay it off, then unfreeze | Works |
| 5.12 | Close the secured card | Deposit returns to the account |
| 5.13 | Try to close a card carrying a balance | Refused |
| 5.14 | Charge above 80% of the limit, wait for a statement | Score takes the utilisation hit |

---

## 🏧 Phase 6 — ATM

| # | Test | Expected |
|---|---|---|
| 6.1 | Use an ATM with no card | Refused, tells you to order one |
| 6.1a | Walk up and use an ATM | Character turns to the machine, holds a card, reaches forward, then stands at it — **all before** the pad appears |
| 6.1d | Do it on a female ped | Same sequence, no errors |
| 6.1b | Set `Config.ATM.animation.enabled = false` | Pad opens immediately, no animation |
| 6.1c | Close the ATM | Character takes the card back out and steps away |
| 6.1e | Use an ATM with `screen.enabled = true` | The UI appears **on the machine's own screen**, perfectly aligned, not floating |
| 6.1f | Back away slightly and look again | Still aligned — the LOD variants are replaced too |
| 6.1g | Use the arrow keys and Enter | Options move and fire without touching the mouse |
| 6.1h | Type digits and a PIN on the keyboard | Enters correctly, Backspace deletes |
| 6.1i | Click an option with the mouse | It fires. Clicking needs no calibration — if the picture itself sits wrong on the machine, run `/atmtune` |
| 6.1j | Try each ATM model on your map | All four replace correctly |
| 6.1k | Walk away and use another ATM | Texture is cleaned up and re-applied, no leftovers |
| 6.1j | Withdraw from the in-world screen | Cash arrives, the balance on the screen updates without reopening |
| 6.1k | Enter a wrong PIN | The dots shake and clear, attempts still count toward the block |
| 6.1l | Set `screen.enabled = false` | The old fullscreen pad is used instead, everything still works |
| 6.2 | Use it with an active card | Character turns to the machine, holds a card, puts it in — **only then** does the keypad appear |
| 6.2c | Watch the hands | A card prop is in hand during the insert and gone afterwards |
| 6.2d | Close the ATM | Character takes the card back out and steps away before the tasks clear |
| 6.2e | Set `animation.enabled = false` | Pad opens immediately, no character movement |
| 6.2a | Watch the rest of the screen | Only the small pad is drawn — the game is still visible around it, and no bank account shows behind it |
| 6.2b | Type on your keyboard instead | Digits register, Backspace deletes, ESC cancels |
| 6.3 | Wrong PIN three times | Keypad shakes each time, card auto-blocks, `nz_bank_cards.status` = blocked |
| 6.3b | Cancel on the keypad | Focus released, you can move immediately |
| 6.4 | Check the nav in ATM mode | Only Dashboard, Transactions, Savings, Bills. No Shared, Society, Cards, Investments, Settings |
| 6.5 | Withdraw past `Config.ATM.maxWithdraw` | Refused |
| 6.6 | Set `withdrawFee = 0.02`, withdraw 1000 | 1020 leaves, separate fee row |
| 6.7 | Turn on express pay, use the ATM again | No PIN prompt under the threshold |
| 6.8 | Set `padAnimation` to `horizontal`, then `none` | Pad slides in sideways, then appears with no animation |
| 6.9 | With `physicalItem = true`, check inventory at the ATM | Card is gone while you are using it, back when you close |
| 6.10 | Disconnect while at an ATM | Card is in your inventory on rejoin |
| 6.11 | Use an ATM twice with `pinEveryUse = true` | PIN asked both times |

---

## 👥 Phase 7 — Shared accounts

| # | Test | Expected |
|---|---|---|
| 7.1 | Open a shared account | Creation cost charged, account appears with you as Owner |
| 7.2 | Name it 2 characters | Refused |
| 7.3 | Add the other player by server ID | They appear as a member and get a notification |
| 7.4 | Add a made-up server ID | Refused |
| 7.5 | Add the same person twice | Refused |
| 7.6 | As the member, try to withdraw | Refused until the owner grants it |
| 7.7 | Grant withdraw, try again | Works |
| 7.8 | As the member, try to remove another member | Refused — owner only |
| 7.9 | Issue a member card to them | They see it on their Cards page with the joint limit, badged MEMBER CARD |
| 7.10 | As that member, change the card's limit | Refused |
| 7.11 | As that member, change its PIN | Allowed |
| 7.12 | Close the shared account with money in it | Balance moves to your personal account, members lose access |

---

## 🐖 Phase 8 — Savings

| # | Test | Expected |
|---|---|---|
| 8.1 | Open savings | Account appears |
| 8.2 | Open a second one | Refused |
| 8.3 | Deposit 10,000 | Balance and "total deposited" both move |
| 8.4 | Wait for a payout | Interest lands, notification fires, "total earned" climbs |
| 8.5 | Set a goal of 25,000 | Ring shows the right percentage, centred in the donut |
| 8.6 | Withdraw everything | Works, no interest paid on zero |

---

## 💰 Phase 9 — Loans

| # | Test | Expected |
|---|---|---|
| 9.1 | Request a loan above your score | Locked, button says why |
| 9.2 | Take a Standard loan | Money lands, loan panel populates |
| 9.3 | Request a second loan | Refused, one at a time |
| 9.4 | Confirm the buttons | "Make a payment" and "Pay off" both fully visible, not clipped |
| 9.5 | Wait for an auto-payment with funds in the account | Taken automatically, score up |
| 9.6 | Empty the account, wait | Missed payment, score down, notification |
| 9.7 | Miss three | Loan defaults, penalty added |
| 9.8 | Try to borrow while defaulted | Refused |
| 9.9 | Settle the default | Borrowing unlocks |
| 9.10 | Take another, pay it off early | Interest discount applied, message states the saving |
| 9.11 | Take a loan and clear it instantly | Allowed, but **no credit gain** and the message says so |
| 9.12 | Try to borrow again straight after | Refused until the cooldown is up, with the minutes left |
| 9.13 | Spam small payments (1 each) | Balance drops, credit score does **not** move |
| 9.14 | Pay a full instalment twice inside one cycle | Credit moves once, not twice |
| 9.15 | Check what landed in the account | Loan amount minus the arrangement fee |
| 9.16 | Spam the Pay off button as fast as you can | Charged **once**. Balance never drops twice, credit never moves twice |
| 9.17 | Spam Request loan | One loan created, extra clicks refused |
| 9.18 | Spam Settle on a defaulted loan | Charged once |
| 9.19 | Confirm any modal while the server is stalled | Button re-enables within 12 seconds with a message, never sticks |

---

## 📄 Phase 10 — Bills

| # | Test | Expected |
|---|---|---|
| 10.1 | As a police/mechanic boss, issue a bill to the other player | They get a notification, it appears on their Bills tab |
| 10.2 | Pay it | Amount leaves them, lands in the society account |
| 10.3 | Let one go overdue | Late fee added, tag turns red |
| 10.4 | Turn on auto-pay in Settings, issue another | Paid instantly, notification says so |
| 10.5 | Auto-pay on with an empty account | Stays pending, not lost |
| 10.6 | From a job that isn't an issuer | Refused |
| 10.7 | `exports['nayzeee-banking']:sendBill(id, 'police', 500, 'Test')` | Bill appears |
| 10.8 | If you run esx_billing, send a bill through it | Lands in this bank's Bills tab, not the old table |

---

## ⏱️ Phase 11 — Scheduled transfers

| # | Test | Expected |
|---|---|---|
| 11.1 | Create one to the other player | Appears as Running with a countdown |
| 11.2 | Wait for it to fire | Money moves, both sides notified |
| 11.3 | Empty the source account, wait | Fails with a notification, doesn't cancel yet |
| 11.4 | Let it fail three times | Auto-pauses |
| 11.5 | Resume it | Countdown restarts |
| 11.6 | Delete it | Gone |
| 11.7 | Create past `maxPerPlayer` | Refused |

---

## 🔗 Phase 12 — ESX mirror

The part most likely to bite you. Watch both numbers at once.

| # | Test | Expected |
|---|---|---|
| 12.1 | Deposit 5000 in the bank UI, then `/checkbalance` or any ESX balance script | Both read the same |
| 12.2 | Buy a car from a vehicle shop | Money leaves, bank UI shows it as an external payment within `syncSeconds` |
| 12.3 | `xPlayer.addAccountMoney('bank', 10000)` from console | Appears in the bank UI as an external deposit |
| 12.4 | Check for double-counting | Balance went up 10,000 exactly once, not 20,000 |
| 12.5 | Leave a player idle for five minutes | Balance stays stable, doesn't drift up or down |
| 12.6 | Wait for an ESX paycheck on a society job | Wage lands in the bank, **and the society balance drops by the same amount** |
| 12.7 | Check the society ledger | Row labelled "Wages paid" |
| 12.8 | Compare society balances | `nz_bank_accounts` and `addon_account_data` agree |

{% hint style="danger" %}
12.6 and 12.8 catch the worst possible bug: a one-way society mirror pays wages out of thin air and the society account never drains. If the society balance climbs back after a paycheck, stop and check `mirrorSociety`.
{% endhint %}

### If you switch to `Config.Payroll.mode = 'bank'`

| # | Test | Expected |
|---|---|---|
| 12.9 | Set a wage on your grade from the Society tab | Saves, shows as Paying |
| 12.10 | Wait an interval | Paid once, from the society account |
| 12.11 | Confirm you aren't paid twice | ESX's paycheck no longer fires |
| 12.12 | Empty the society account, wait | Payment stops, every manager online is warned |
| 12.13 | Turn direct deposit off in Settings | Next wage arrives as cash instead |

---

## 👔 Phase 13 — Multi-job

Skip if you don't run one.

| # | Test | Expected |
|---|---|---|
| 13.1 | Console prints on start with `Debug = true` | Names the detected multi-job resource |
| 13.2 | Clock into your second job | Society tab follows to that department |
| 13.3 | Set `allowInactiveJobs = true`, restart | Society tab shows a tab per department |
| 13.4 | Switch between them | Balances, transactions and payroll all follow the selected tab |
| 13.5 | Change jobs while the UI is open | Refreshes on its own |
| 13.6 | A grade not in `societyAccess` | No society tab at all |

---

## 📈 Phase 14 — Investments

| # | Test | Expected |
|---|---|---|
| 14.1 | Open Investments | Five assets, sparklines drawn, prices sensible |
| 14.2 | Wait for a tick | Prices move, percentages update |
| 14.3 | Buy 5000 of one | Money leaves with the fee, position appears |
| 14.4 | Buy below `minTrade` | Refused |
| 14.5 | Buy more than you have | Refused |
| 14.6 | Sell half | Money returns minus fee, units halve, P/L reported |
| 14.7 | Sell everything | Position clears, realised P/L moves |
| 14.8 | Sell an asset you don't hold | Refused |
| 14.9 | Restart the resource | Prices and holdings survive |
| 14.10 | Donut centre label | Dead centre, not offset |

---

## 📱 Phase 14b — Phone app

Skip if you do not run lb-phone.

| # | Test | Expected |
|---|---|---|
| 14b.1 | Start the server with lb-phone running | Banking app on the phone's home screen |
| 14b.2 | Restart lb-phone only | App comes back on its own |
| 14b.3 | Open the app | Balance matches the bank UI exactly |
| 14b.3a | Tap the eye | Balance hides and comes back |
| 14b.3b | Check the Money tab blocks | Savings, investments and borrow all show real figures |
| 14b.3c | Use the Pay keypad | Amount builds, C clears, backspace deletes |
| 14b.4 | Send money from the app | Arrives, and both sides see the transaction |
| 14b.5 | Send to a made-up account number | Refused with the same message as the bank UI |
| 14b.6 | Freeze a card from the app | Card frozen in the bank UI too |
| 14b.7 | Pay a bill from the Activity tab | Paid, the badge count drops |
| 14b.7a | Pay a loan instalment from Upcoming | Taken, credit moves once |
| 14b.8 | Deposit at a bank with the app open | App balance updates on its own |
| 14b.9 | Set `Config.Phone.enabled = false`, restart | App is gone, nothing else changes |

---

## 🛡️ Phase 15 — Admin

| # | Test | Expected |
|---|---|---|
| 15.1 | `/bankadmin` as a non-admin | Refused |
| 15.2 | `/bankadmin give <id> 5000` | Lands, logged as Admin in the ledger |
| 15.3 | `/bankadmin take <id> 5000` | Removed |
| 15.4 | `/bankadmin freeze <id>` | Target cannot deposit, withdraw or transfer |
| 15.5 | `/bankadmin check <id>` | Prints every account and the credit score |
| 15.6 | `/bankadmin credit <id> 800` | Score changes, band label updates |
| 15.7 | `/paysociety 1000` as a boss | Society down, personal up |
| 15.8 | `/paysociety` as a regular employee | Refused |

---

## 🔐 Phase 16 — Try to break it

Do these last, and do them properly. This is where money gets duplicated.

| # | Test | Expected |
|---|---|---|
| 16.1 | Open the UI, F8 → `SendNUIMessage` nothing — instead trigger the NUI callback with a server callback name not in the allowlist | Blocked |
| 16.2 | Trigger `nz_bank:deposit` client-side with a negative amount | Refused |
| 16.3 | Trigger it with a decimal like 100.7 | Rounded, never rounds in your favour twice |
| 16.4 | Trigger it with a huge number (`1e15`) | Refused or handled, no overflow |
| 16.5 | Call `nz_bank:withdraw` for an account ID you don't own | Refused |
| 16.6 | Call `nz_bank:setPayroll` as a regular employee | Refused |
| 16.7 | Call `nz_bank:removeMember` on an account you're only a member of | Refused |
| 16.8 | Disconnect mid-transfer | No money lost or duplicated |
| 16.9 | Restart the resource mid-transfer | Same |
| 16.10 | Name an account with `<script>` or SQL quotes | Stripped or escaped, UI doesn't break |

---

## 🚦 Phase 17 — Before you ship

| # | Test | Expected |
|---|---|---|
| 17.1 | **Put every timer in Phase 0 back to production values** | Double-check `statementMinutes` |
| 17.1b | Confirm the version in `fxmanifest.lua` | Matches what you publish |
| 17.2 | `Config.Debug = false` | No debug spam in console |
| 17.3 | Fill in the Discord webhooks, run a transfer and a robbery-adjacent action | Embeds arrive in the right channels |
| 17.4 | `txAdmin`/console resmon while the UI is open | Idle under 0.05ms, open under 0.10ms |
| 17.5 | Resmon with 20+ players online | Sync loop doesn't spike |
| 17.6 | Check the server console after an hour of play | No recurring errors or warnings |
| 17.7 | Restart the server, reopen every page | All data intact |

---

## 🔎 What to watch while testing

Keep these open in a second window:

```sql
-- balances should only ever move in ways you caused
SELECT account_number, type, label, balance FROM nz_bank_accounts;

-- every movement, newest first
SELECT id, account_id, category, direction, amount, balance_after, label
FROM nz_bank_transactions ORDER BY id DESC LIMIT 20;

-- the mirror agreeing with itself
SELECT a.owner, a.balance AS bank, d.money AS esx
FROM nz_bank_accounts a
JOIN addon_account_data d ON d.owner IS NULL
WHERE a.type = 'society';
```

**`balance_after` is your audit trail.** Walk down the column — each row's `balance_after` should equal the row above it plus or minus that row's amount. If it ever jumps, two writes raced and you've found a duplication bug.

---

## 🐞 Bug report template

When something fails, capture this before moving on:

```
Phase / test number:
What I did:
What I expected:
What happened:
Server console output:
F8 console output:
Relevant config values:
Rows from nz_bank_transactions around the failure:
```


---

## 🗄️ Schema degradation

Worth running once on a copy of a live database, because it is the failure that takes everything down if it is not handled.

| # | Do | Expect |
|---|---|---|
| S.1 | Start the server on a database that has **not** had `update.sql` imported | Console lists the missing columns and names each feature it switched off |
| S.2 | Third-eye the bank NPC | The UI opens normally. Overdraft and the phone's Recent list are absent; nothing errors |
| S.3 | Deposit, withdraw, transfer | All work, and the rows land in `nz_bank_transactions` |
| S.4 | Take a loan, then pay it off | Both work. Credit does not move on repayment, which is the feature that is off |
| S.5 | Open the phone app | Loads. No overdraft block, Recent is empty, everything else works |
| S.6 | Import `update.sql`, restart | Console says nothing is missing. All three features come back |
| S.7 | Stop the MySQL server, then open the bank | "The bank did not answer", not "your account is still being set up" |
| S.8 | With MySQL still down, open the phone app | A "Can't reach the bank" screen with a Try again button — no console errors about reading properties of null |


---

## 🏧 The in-world screen

| # | Do | Expect |
|---|---|---|
| A.1 | Third-eye an ATM | Camera zooms, screen appears **on that machine only** |
| A.2 | Look at the ATM next to it, and the lit sign above | Both untouched. If either goes black, you are in `texture` mode |
| A.3 | Move the mouse | The camera looks around, stopping at the limits — never past the machine |
| A.4 | Look at a side button | The label lights on the screen. Nothing is drawn on the machine itself |
| A.5 | Left click | It presses. The label is the one beside that physical button |
| A.6 | Look down at the number pad, press a key | The digit appears. `pin_enter` confirms, `pin_clear` deletes |
| A.6b | Type `100` on the keyboard | All three digits land, zero included |
| A.6c | Press TAB at the machine | The inventory opens; clicking in it does not press an ATM button |
| A.7 | Run `/atmbuttons` on each model | Every button records where you aim; paste the printed block |
| A.8 | Run `/atmuv` at a Fleeca machine | The page moves inside the glass; `ENTER` prints the island |
| A.5 | Type `1` on the number row | A `1` appears, not a `2` |
| A.6 | Any digit that does nothing | `/atmkeys` with `Config.Debug` on, press it, put the printed ID in `Config.ATM.keypad` |
| A.7 | Withdraw | Cash slides out of the dispenser; the shutter sound runs with it |
| A.8 | Deposit | Cash slides in instead |
| A.9 | Statement | Paper feeds from the receipt slot, summary on screen |
| A.10 | `Esc` | Card ejects, camera returns — **no pause menu** |
| A.10b | Straight after, third-eye the same machine again | The in-world screen opens again, never the fullscreen pad |
| A.11 | Walk away mid-session | No crash — the entity is re-checked every frame |


---

## 🧯 Failure handling

| # | Do | Expect |
|---|---|---|
| F.1 | At an ATM, press Statement | A statement, or a decline you can read — never a spinner that never ends |
| F.2 | Stop MySQL, then press Statement | "The bank did not answer" after `timeoutSeconds`, and the screen returns to the menu |
| F.3 | Look around while at an ATM | The minimap is hidden and nothing spins |
| F.4 | Leave the ATM | The minimap comes back |
| F.5 | Put a nonsense model in `Config.ATM.slots.cashProp`, withdraw | One console line naming it, no error, everything else still works |
| F.6 | Check the console after any failed action | A line naming the callback and the reason |


---

## 🖼️ Logo

| # | Do | Expect |
|---|---|---|
| L.1 | Drop a PNG at `web/images/logo.png`, restart | It replaces the wordmark in the bank, the ATM and the phone |
| L.2 | Rename the file so it is missing, restart | The built-in wordmark comes back. No errors |
| L.3 | Set `Config.UI.logo` to a full `https://` URL | Used as given, not rewritten |
| L.4 | Set `Config.UI.logo = ''` | Wordmark everywhere |
