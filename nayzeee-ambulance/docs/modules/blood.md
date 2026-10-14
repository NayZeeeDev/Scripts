# Module: blood — donation, blood bank, labelled bags, IV stand & transfusion

Owner files: `server/modules/blood.lua`, `server/modules/blood_donation.lua`, `server/modules/blood_stand.lua`,
`client/modules/blood.lua`, `client/modules/blood_donation.lua`, `client/modules/blood_stand.lua`,
`config/modules/blood.lua` (`Config.Blood`), `locales/en/blood.lua` (`blood.*`),
`html/apps/donation/**` (app `donation` + `lcd.html` DUI), `html/apps/ivstand/**` (app `ivstand`).

## 1. Features

### Labelled blood units
- Every unit is an item `Config.Items.blood_bag` with label metadata:
  `{ serial = 'BB-482913', type = 'O-', ml = 450, donor, created, expires, product, label, description }`
  (`label` / `description` show in ox_inventory). Serials are unique and stored in `nza_blood`
  (status: 0 in a bank, 1 in circulation, 2 transfused, 3 discarded).
- Units expire after `Bags.shelfDays` real days (warning `warnDays` before). Expired units cannot be hung
  (`Bags.useExpired`), are discarded on deposit, and are swept out of the banks automatically.
- Using a blood bag item opens the printed label (app `donation`, mode `label`): barcode + serial, ABO box
  (Rh negative printed inverted), product, volume, collected / expiry, donor. No brand on the label
  (generic "Regional Blood Service").
- Every bag drawn in the NUI (`NZABlood.bagSVG`) is a detailed PVC unit: pillow shape that bulges as it fills,
  hatched welded seams, hanger slot + eyelets, printed mL scale, paper label (ABO, RhD, mini barcode), meniscus
  and bubbles, outlet ports with twist-off covers and - on red cell units - the sealed tubing segments kept for
  crossmatching. Saline bags are clear with a teal NaCl label.

### Type & screen
- Patient option **Type & screen** (perm `TypeScreen.perm`, any state) → bedside card test (progress) →
  `NZA.Treat 'blood:type'` sets `patient.meta.bloodTyped = true`, adds the finding `bloodtype`
  (`NZA.Findings`) and tells a player patient their group. From then on the IV stand, the bag picker and the
  label's crossmatch strip show compatibility. A donation also types the donor. Optional fee (`TypeScreen.fee`).

### Blood bank (point type `bloodbank`)
- Window (app `donation`, mode `bank`, UI v5): **Stock** (8 group tiles with units / mL, units table with
  serial, group, volume, donor, collected, expiry + relative time, amber = soon, red = expired → discard),
  **Issue a unit** (pick a group, preview of the label of the unit that will be issued — first in, first out;
  decanted into an empty collection bag when `Bank.needEmptyBag`), **Your bags** (labels of the units you
  carry, put back / discard), **Log** (deposits, issues, donations, expiries, opening stock).
- **Issue a unit** shows the bag and its label side by side and a compatibility grid (*"O+ can be given to"*:
  the 8 recipient groups lit teal / dashed).
- Stock per department (`point.hospital`) or one shared stock (`Bank.shared`). Anti-hoarding window
  (`maxWithdraw` per `withdrawWindow` minutes), capacity `maxStock`.
- New banks get an opening stock once (`Bank.seed`); the city donates random units over time
  (`Bank.npcDonors`).

### Donation (point type `donation`)
- Every client dresses a streamed donation chair (`Config.Props.donation_chair`) with the collection mixer
  (`blood_mixer`), a bag lying on its tray that visibly fills (`bloodbag_0/25/50/75/100`, synced to everyone
  through `GlobalState.nzaBloodChairs`) and a decorative IV stand. The mixer LCD shows the live mL counter
  (DUI `html/apps/donation/lcd.html` replaces `nz_amb_screen` while you are near an active chair).
- **Donate blood** (anyone): eligibility (alive, blood ≥ `minBloodPct`, pain ≤ `maxPain`, no open / bleeding
  wounds, no running drip, `cooldownDays` since the last donation) → the donor sits (reclined pose).
- Mode `self` / `medic` / `both`: the donor presses **E** to run it alone, or a medic uses **Draw blood** on the
  chair (perm `Donation.perm`); the donor then sees the collection scale passively (mode `watch`).
- Minigame (`NZA.Proc 'donation'`, app `donation` mode `donate`, kit ProcPanel):
  1. **Inflate the cuff** — hold Space, let go inside the band (40–60 mmHg); 3 tries.
  2. **Pump with the pulse** — the donor's pulse wave scrolls through the **CM-450 collection scale**
     (top-left: bag gauge on a rocking mixer tray, volume rolling counter, flow, donor pulse, elapsed, pleth lane
     with the squeeze window); press Space as each systolic peak crosses the window. Timing quality (dial) drives
     the flow (`flow.trickle` … `flow.maxFlow` mL/s); squeezes are stamped on the wave (clean / close / off /
     missed). A second, glanceable cue sits in the procedure column (**pulse ring**, `pp.slot`): a sweep hand
     goes round once per heartbeat and crosses the teal squeeze window at the top on the peak, a red ripple marks
     every beat, the foam squeeze ball in the centre squashes (and glows by grade) on every press, the last 16
     squeezes sit on the outer ring (newest at the top), with the BPM and clean / close / off / missed counts.
  3. **Seal the bag** — C clamps the line, hold E to slide the needle out. The readout turns to *Sealed 100 %*
     with collected mL, rhythm % and best streak.
  Result: grade, the printed label of the new unit, where it went.
- Server: collected mL clamped by elapsed time × `flow.maxFlow` and the unit size; easy mode = a full unit.
  `AddBlood(-mL)` to the donor; ≥ `minUsable` → `NZA.Blood.CreateBag` with the donor's group into the chair's
  bank / the donor / the collector (`bagTo`); reward (`reward.money`, `items`, `medicPay`); cooldown stored in
  `nza_blood_donors`; weakness (walk style, no sprint, short screen effect) for `weakness.minutes`
  (restored after a reconnect). An aborted donation still costs the blood already drawn.

### IV stand (app `ivstand`) — `NZA.Blood.OpenStand(target, info?)`
Opened from the ambulance treatment bay (F3, the transport module calls `NZA.Blood.OpenStand`), the patient
option **IV stand**, the EMS radial (Patient), the examination route **Transfuse / IV fluids** (bleeding
injury and blood volume below `examRoute.belowPct`), hospital beds / surgery (any module).
- Right-docked HUD panel: patient, group chip (or **Type & screen**), access chip (or **Place IV**), warmed
  fluids chip (bay / bed), live vitals (HR, NIBP, MAP colour band, SpO₂), blood volume, bleeding, saline /
  blood given.
- Two hooks: hang **saline** (`saline_bag`) or a **blood unit** from your inventory (picker shows group,
  serial, expiry, compatibility: universal / compatible / not typed / incompatible / expired). Known mismatch →
  red warning (hang anyway only if `allowIncompatible`); untyped non-O− → warning with Type & screen.
  Inside the bay the **ambulance fridge** (`bayStock`, refills after `bayRefill` minutes) can **Bag a unit**.
- Live ECG strip under the numbers (`NZA.vitals.Trace`, rate and rhythm from the patient, rhythm label).
- Each hook card shows the bag (fill follows the volume), a **drip chamber** under it whose drops fall at the
  real drop rate (blood set 15 gtt/mL, fluid set 20 gtt/mL; a continuous stream above 6 drops/s, still when
  clamped or paused), the line running, and the **pressure infuser sleeve** - a mesh bladder around the bag that
  swells and glows with the bag pressure (red when over-pressured). Left / rate / drip (gtt/min) rows.
- Selected hook: roller clamp (slider, Q / E), pressure infuser (240° dial, Space pumps `pump` mmHg, leaks
  `leak` mmHg/s, red over 300), live flow mL/min and time to empty; **Unhang** (the rest of a blood unit is
  discarded). The selected unit's printed label sits beside the panel with the crossmatch strip.
- **TXA 1 g** slow push: hold T (Shift = too fast → BP dip) — status ring; needs `txa` item and access.
- Alerts (glowing-bar notes): transfusion reaction (Stop blood), no line, paused infusions, group unknown,
  over 1 L of saline.
- "Place an IV first": calls the field module's `nza_field_iv` option and reopens the stand when the line is
  in; without the field module a quick placement (`placeIv`, `iv_kit`, progress bar).
- **Easy mode** (the medic's department easy flag for `Stand.perm`): only the supplies count - hanging a bag or
  pushing TXA without IV / IO access puts a line in by itself (`placeIv.site`), no 'Place an IV first' alert.
- World: every client draws the stand from the patient's `nzaStand` state bag — a tripod stand beside the
  patient with the bags on its hooks (blood bags swap their fill model as they empty, saline bag model), or
  the bags on the bay's IV hooks (`NZA.Transport.Bay.Info().hooks`) for medics in the same bay. A bag that runs above gravity flow
  (the pressure infuser is squeezing it) gets the `pressure_infuser` prop around it on its hook. The stand
  follows the patient when moved more than 5 m; empty bags hang 10 minutes, then go.

### Transfusion reaction
Incompatible blood (core flags `infusion.incompatible`) → stages by incompatible mL received
(`Reaction.stages`): patient lines (speech) to the medics, a red toast to the medic who hung it, condition
`reaction { stage, ml }` (exam + IV stand alert), haemolysis `AddBlood(-haemolysis[stage] mL/min)` on top of
the core reaction effect (fever, tachycardia, hypotension). It fades `feverMinutes` after the last drop.

### Billing
`Billing.unit / saline / txa` per item hung, `TypeScreen.fee` once per patient (through `NZA.Billing.Charge`,
on-duty medics only, player patients only).

## 2. Controls

| Where | Keys |
|---|---|
| Donation chair (seated) | **E** start (self-service), **X** stand up (key mapping `nza_blood_standup`, rebindable) |
| Donation minigame | **Space** hold = pump the cuff / tap = squeeze with the pulse, **C** clamp, hold **E** needle out, **Enter** finish, hold **ESC** cancel (kit ring) |
| IV stand | **Space** pump the infuser, **Q / E** roller clamp −/+, hold **T** TXA (Shift = fast), **1 / 2** select hook, **ESC** close picker / panel, right-drag orbit the camera |
| Bank window | click, **F5** refresh, **ESC** close |

Keys of the apps are `KeyboardEvent.code` names in `Config.Blood.Donation.keys` / `Config.Blood.Stand.keys`.

## 3. Config (`config/modules/blood.lua`)

`Bags { item empty ml bagSize serialPrefix shelfDays warnDays useExpired product }` ·
`TypeScreen { enabled perm seconds distance order icon anim animStand fee }` ·
`Bank { perm prop distance shared needEmptyBag maxWithdraw withdrawWindow maxStock discardExpired seed npcDonors{ enabled interval maxPerType } logSize }` ·
`Donation { enabled mode perm cooldownDays minBloodPct maxPain noInjuries minTime maxTime easyTime minUsable bagTo items selfItems reward{ money account items medicPay } weakness{ minutes clipset noSprint fx fxSeconds } flow{ perfect good maxFlow trickle ease cuffBand cuffRate sealHold } sit{ dict clip offset heading } medicAnim medicSpot selfAnim mixer bagOnMixer stand camera lcd{ enabled width height range } standKey keys }` ·
`Stand { perm bloodPerm maxBags salineMl gravity pressureGain maxPressure pump leak maxRate warmInBay allowIncompatible requireAccess placeIv{ interact fallback item seconds site } txa{ item perm push } interact{ enabled order distance icon } radial examRoute{ enabled belowPct } placement{ side along } camera bayStock bayRefill keys range }` ·
`Reaction { enabled stages haemolysis feverMinutes speech alertMedic }` · `Billing { unit saline txa }`.
Items are referenced by KEY (`Config.Items[key]`), props by `Config.Props` keys.

## 4. API, events, callbacks

**Server** (`NZA.Blood`):
```lua
NZA.Blood.CreateBag(meta) → metadata            -- meta { type, ml?, donor?, donorId?, created?, expires?, bank? }
NZA.Blood.TakeBag(src, slot | serial | { serial?, slot?, type?, recipient? }, opts?) → metadata | nil, reasonText
NZA.Blood.Compatible(recipient, donor) → bool   -- recipient = group | pid | Patient (NZA.Const.CanReceive)
NZA.Blood.GiveBag(src, meta) → bool             NZA.Blood.BagsOf(src, recipient?) → { slot, serial, type, ml, donor, created, expires, expired, soon, compatible }
NZA.Blood.IsTyped(p) → bool                     NZA.Blood.Stock(bankKey) → units    NZA.Blood.BankKey(point) → key
NZA.Blood.AddToBank(bankKey, meta, actor?)      NZA.Blood.Log(bankKey, action, unit, actor)
NZA.Blood.Bill(src, p, kind, n?, price?)        NZA.Blood.DonorEligible(src) → ok, reason, msg
NZA.Blood.StandOf(pid) → stand                  NZA.Blood.ItemName(key)   NZA.Blood.Cfg(section)
```
Exports: `GetBloodStock(bankKey)`, `CreateBloodBag(meta)`, `BloodCompatible(recipient, donor)`.

**Treatments** (`NZA.Treat`): `blood:type`, `ivstand:hang { kind, serial?, slot?, type?, rate, force?, hook?, at?, h? }`,
`ivstand:rate { id, rate }`, `ivstand:takedown { id }`, `ivstand:txa { seconds }`, `ivstand:access`.
**Procedure** (`NZA.Proc`): `donation` (target = the seated donor, payload `{ point }`).

**Callbacks**: `nza:blood:bank:open|deposit|withdraw|fill|discard`, `nza:blood:bags (recipient?)`,
`nza:blood:donation:check (pointId)`, `nza:blood:donation:sit (pointId)`, `nza:blood:me ()`,
`nza:blood:stand:info (target)`, `nza:blood:stand:fill (type?)`.
**Net events**: C→S `nza:blood:donation:leave (pointId)`, `nza:blood:donation:progress (pointId, ml)`;
S→C `nza:blood:label (bag)`, `nza:blood:weak (seconds)`, `nza:blood:donation:stood (pointId)`.
**State**: `GlobalState.nzaBloodChairs`, patient state bag `nzaStand`.
**Bus**: server `blood:typed (src, p, group)`, `blood:donated (src, p, ml, meta|nil)`, `blood:hung (src, p, inf)`,
`blood:reaction (p, stage)`; client `blood:typed (target, group)`.

**Client** (`NZA.Blood`): `OpenStand(target, info?)`, `CloseStand()`, `StandOpen()`, `TypeScreen(entity, target)`,
`OpenBank(point)`, `Sit(point, entity)`, `Draw(point)`, `StandUp()`, `Busy()`, `Seated()`, `Weak(seconds)`.
Registries: point types `bloodbank`, `donation`; `NZA.Interact` `nza_blood_type`, `nza_blood_stand`;
`NZA.ExamRoutes` `transfuse`; `NZA.RadialItems` `blood_stand`.

**NUI** — `donation`: open `{ mode = donate|watch|bank|label, locale, data, keys, self }` (QA helper in the
browser preview: `NZA.apps.donation._demo('collect'|'seal'|'done')`, `?mode=bank|label|watch`; IV stand
`?state=react|noline|untyped|field`, `NZA.apps.ivstand._demo('squeeze'|'picker'|'sel2')`), msgs `result`, `watch`,
`bank`; posts `donation:progress|finish|abort|bank|close`. `ivstand`: open `{ locale, keys, cfg, data, bay }`, msgs
`data`, `snap`; posts `ivstand:hang|rate|takedown|txa|type|iv|fill|refresh|close`. Shared JS helpers for both
apps: `window.NZABlood = { labelHTML, bagSVG, barcode, fmtType, dateText, relDays, expiryTone }`.

## 5. Data
`nza_blood` (units), `nza_blood_donors` (cooldown, count, weakness), `nza_blood_log` (bank log) — created on
start; SQL in `docs/requests/blood.md`. KVP `nza_blood_seed:<bank>` marks seeded banks.

## 6. Known limits
- The reclined sit clip (`Donation.sit`) and its chair offset are a best guess for `nz_amb_donation_chair`;
  tune `sit.offset` / `heading` in game. The medic stands at `medicSpot` (chair-local).
- The minigame is played by whoever runs the procedure (the donor in self-service, the medic when a medic
  draws); the donor sees the passive collection scale while a medic draws.
- Infusion rates are client intents (roller clamp × infuser) clamped by the server to `Stand.maxRate`.
  The core has no rate setter: a rate change re-hangs the same infusion (same id and volume left).
- The mixer DUI replaces the screen texture of every mixer on that client, so only the nearest active chair
  shows its counter at a time.
- The 'Place an IV first' hand-over relies on the field module's `nza_field_iv` option name.
- Bags hung by other modules appear on the stand only after a medic opens it (adoption).
