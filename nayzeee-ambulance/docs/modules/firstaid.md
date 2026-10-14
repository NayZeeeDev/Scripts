# firstaid — Bleed control, tourniquet, collar, oxygen, foil blanket, medication, first aid items

Everything a first aider or medic does at the roadside to keep a patient alive: a three-step
**Bleed control** minigame (direct pressure → wound packing → wrap / pressure dressing), a
three-step **Tourniquet** (place high & tight + pull the slack → twist the windlass → lock the
clip, time written on the strap), a two-step **Cervical collar** (measure & size → fasten while
holding the head in line), the medic **Medication** dose panel, **Oxygen mask**, **Foil blanket**
and the six **first aid items** usable from the inventory or on someone else.

| Side | Files |
|---|---|
| client | `client/modules/firstaid.lua` (helpers, items, worn props, patient options, exam routes, radial) · `client/modules/firstaid_treat.lua` (the `treat` NUI runner) |
| server | `server/modules/firstaid.lua` (helpers, state bag, timers, usable items, instant treatments) · `server/modules/firstaid_procs.lua` (procedures) · `server/modules/firstaid_meds.lua` (medication) |
| NUI | `html/apps/treat/app.js` · `html/apps/treat/app.css` |
| config / locale | `config/modules/firstaid.lua` (`Config.Firstaid`) · `locales/en/firstaid.lua` (`firstaid.*`, 479 keys incl. every NUI string) |

Preview: `html/index.html?app=treat` (+ `&step=pack|wrap`), `&demo=torso[&step=dressing]`,
`&demo=tq[&step=twist|lock]`, `&demo=collar[&step=fasten]`, `&demo=meds`, `&demo=kit`.

---

## Features

### The close-up scene (bleed / tourniquet / collar)
- Medic turns to the patient, kneels for a lying patient (`NZA.Anim.Kneel`, then the tending
  loop) or works standing; `NZA.Cam.Close` on the region bone (wound), the elbow / knee
  (tourniquet) or the neck (collar).
- World anchors: the three joints of the limb (shoulder/hip → elbow/knee → wrist/ankle), or the
  region bone + pelvis + neck for torso wounds, or head / neck / chest for the collar.
- The overlay draws everything at **real scale**: px per cm is derived from the limb segment on
  screen (thigh 44 cm, lower leg 42, upper arm 30, forearm 26; torso 55 cm), so a 1 cm gunshot
  hole, an 8 cm gauze pad and a 7.5 cm bandage look right at any camera distance.
- Procedural wounds per type (gunshot hole + abrasion collar, shrapnel holes, stab slit, ragged
  laceration from `injury.length`, abrasion patch), a blood-soaked patch that grows with the blood
  lost, **arterial jets on every heartbeat** (pseudo-3D: they rise toward the camera and land),
  venous rivulets running to the ground side, persistent stains anchored to the wound.
- **Top-left context card** (corner bracket): avatar in a spinning severity ring, procedure kicker
  + patient name, severity chip; a **holographic body glyph** with the wound's region lit and a
  pulsing diamond, beside an instrument list (wound, site, flow, severity — tone notches); four
  **vital status rings** (HR with a heartbeat ping at the live rate, SYS, SpO₂, RR — from
  `NZA.Patient.Watch`); a tip note with a glowing bar (deep wound, under tourniquet, spinal
  precautions…). After finishing it becomes the result card: a **score ring** (0–100, fills in),
  per-step score bars and the outcome message. No letter grades.
- **Handheld device** right-middle, left of the core tool belt (`right: 304px`): our own industrial
  design — moulded shell, rubber side grips, corner screws, model plate, glass screen with
  scanlines, three physical keys (MODE / ZERO / MUTE), amber warning sticker and serial. Generic
  labelling only, **no brand**: **HM-2 · Haemostat monitor** (rolling flow counter + trend arrow,
  flow trace with grid and fill, instrument rows, step gauge), **TQ-1 · Windlass gauge** (pressure
  dial with the occlusion band, distal pulse LED, flow, time on), **CS-4 · Neck sizer** (sizing post
  / in-line bubble level + size chart).
- Stage labels are dark chips with a tone diamond; targets are four-bracket reticles that turn
  slowly (no dashed circles, no leader lines). The dressing waits on whichever side of the wound
  stays clear of the HUD.
- `NZA.ui.ProcPanel` (core): instruction column bottom-left (readout dial + instrument list, step
  spine with `steps` names → *Next: …*, text with key caps, flash line, Done), tool belt on the
  right edge with icons (gauze, gauze roll, bandage, dressing pad, strap, windlass, clip, ruler,
  collar) and the hold-to-cancel ring. Tag: `Bleed control · <site>`, `Tourniquet · <site>`, `C-spine`.

### Bleed control (`NZA.Proc 'stopbleed'`, perm `StopBleed.perm` = basic)
1. **Direct pressure** – a gloved hand with a gauze pad follows the mouse; **hold LMB** on the
   wound. The wound drifts as the patient moves, so you have to follow it. Bleed meter falls while
   pressing on target, rises when you let go or slip off. Finish: bleed under `pressureTarget` for
   `pressureHold` s. Deep wounds can't go below ~20 % with pressure alone.
2. **Pack the wound** (deep gunshot / stab / shrapnel by `StopBleed.pack` severity, or depth ≥
   `packDepth`) – drag gauze from the roll beside the wound into it, `packStrips` times (a feed near
   the rim counts half, a miss is wasted gauze). Then hold pressure on the packing until the bleed
   stops. Gauze folds stay in the wound and soak red.
3. **Wrap** (limbs) – circle the mouse around the wound; every full circle is one turn of bandage
   drawn across the limb, overlapping by half. A tension gauge (angular speed) must stay in the
   even band: too fast = too tight (warning), too slow = loose. Then clip the end (**E** / click).
   **Pressure dressing** (torso / head / neck) – drag the dressing over the wound (coverage
   counts), then hold each of the four corners until it sticks.
- Result `{ score, steps = { pressure, pack, wrap|dressing }, lost }`. Server: each step ≥
  `failScore` sets `treat.packed` / `treat.bandaged` + `quality`, and the base bleed drops by up to
  `qualityBonus` (40 %) for a perfect job. An **unpacked** dressing on a heavy bleed
  (`soak.minBleed`) with quality under `soak.quality` **soaks through** after `soak.after` s
  (`treat.bandaged` cleared, patient + watching medics notified).
- Already under a tourniquet: the minigame starts with a trickle so you can pack and dress the
  wound before converting the tourniquet.

### Tourniquet (`NZA.Proc 'tourniquet'`, perm basic, item tourniquet)
1. **Place it high and tight** – a rail runs along the whole limb (the elbow / knee joint zone in
   red, the wound ring); drag the strap along it. Live readout "6 cm above the wound", "On the
   joint", "Below the wound". **Space** confirms: below the wound or over the joint is refused (and
   costs score). Then **pull the slack**: drag the teal tab away from the limb and release in the
   green band (less slack = fewer turns needed; yanking too hard slips the buckle).
2. **Twist the windlass** – draw circles with the mouse (anywhere: the turning of the cursor path
   drives the rod, 1 circle = 1 turn, reverse to ease off). Pressure builds by `turnGain` per turn
   (leg / arm) toward the **occlusion pressure = systolic + 60 (arm) / +100 (leg)** from the real
   vitals. A loose strap (venous only) makes it bleed *more*. The distal pulse LED blinks and beeps
   with the heart rate until the artery is closed. Stop turning and it unwinds. Over
   `overMargin` above occlusion = over-tightened (warning, score penalty, extra pain).
3. **Lock the clip** – keep it tight and turn the rod into the clip (the clip lights up teal
   within `clipWindow`°), press **E** or click. Locking misaligned or loose is refused. The time is
   written on the strap (in-game clock, or real time with `clock = 'real'`) and shown as a tag.
- Server: the region the strap really sits on (strap below an upper-arm/thigh wound is recorded on
  the lower segment so physiology keeps the wound bleeding), `devices.tourniquet[region] =
  os.time()`, `meta.tqPos[region] = { s, f }` (exact position for the prop), `meta.tqBy`,
  `treat.tourniquet` + `quality.tourniquet` on every injury it covers.
- **Timers** (server, every `checkEvery` s): after `warnAfter` s the patient and the medic who
  applied it (+ watchers) get a warning; after `damageAfter` s the limb below gets a `damage`
  injury once. **Remove tourniquet** (option, perm `removePerm`) gives the item back
  (`removeReturns`) and warns when the wound starts bleeding again.

### Cervical collar (`NZA.Proc 'collar'`, perm splint, item cervical_collar)
1. **Measure** – drag a stack of gloved fingers from the shoulder line up to the chin (the
   patient's neck height in finger widths is fixed per patient, 2–5), then pick the size with
   **1–4** (No-neck / Short / Regular / Tall) on the sizing chart.
2. **Fit and fasten** – hold **Space** to fasten the velcro; the head keeps drifting, move the
   mouse to keep the bubble of the in-line level inside the circle. Fastening only progresses in
   line.
- Server: `devices.collar = true`, the `spinal` condition gets `stable = true, collar = os.time()`
  (physiology resolves it twice as fast with a collar), neck fractures get `treat.splinted`. Wrong
  size still fits but scores lower and says so. **Remove collar** warns while the spine isn't
  cleared and returns the collar.

### Medication (dose panel, perm `Meds.perm` = meds)
- HUD panel: drug list (count in your inventory, active timer), description, live vitals strip
  (HR, BP, RR, SpO₂, pain, AVPU), **Dose** and **Route** segmented controls, warnings as notes with
  glowing bars, summary + **Administer**. Red warnings turn the button into **Hold to give anyway**;
  missing drug / no IV access / can't swallow block it.
- Drugs (config): morphine 2.5 / 5 / 10 mg IV/IM, adrenaline 0.5 / 1 mg IM/IV (outside and during
  CPR), naloxone 0.4 / 0.8 / 2 mg IN/IM/IV, TXA 1 g IV (needs IV / IO / port), antibiotics 1 / 2 g
  IV/IM, painkillers 1 g oral.
- Warnings: slow breathing / low pressure for morphine, stacking morphine, naloxone blocking
  morphine, low pain, adrenaline with a pulse / fast heart / given < 3 min ago, opioid signs (or
  none) for naloxone + "stand clear", TXA without much bleeding / already on board, antibiotics
  already on board, painkillers on top of morphine.
- Server: `NZA.Patients.GiveMed(pid, drug, { dose, route, by })`. Morphine pushed with RR under
  `morphineRR` adds opioid load (`lowRRDepression` × dose). **Naloxone** that reverses an opioid
  overdose wakes the patient after 2.5 s: wounded → alive when they can stand, an agitated line as
  a speech subtitle, NPCs turn on the medic and berate them, players get a jolt message.
- The medic plays an injection animation holding `Config.Props.syringe`.

### First aid items (everyone, perm per `Config.PublicPerms`)
`Bridge.Inv.RegisterUsable` for bandage, medkit, painkillers, ice pack, burn dressing, foil
blanket → the server asks the client to run it on **yourself** (progress bar + animation; no
animation while downed). **First aid…** on a patient opens the kit chooser: every item with your
count and what it would do to *this* patient ("Bandage: Deep laceration · Left forearm", "No burns
to dress"), keys 1–6.
- **Bandage** – the worst *minor* bleed (≤ `maxBleed`), quality `quality` (soak rules apply);
  heavier bleeds are refused with "use Control bleeding".
- **Medkit** – every abrasion / contusion up to `maxSeverity` and severity-1 laceration
  (bandaged / cooled / dressed) + `Heal(heal)` (a little blood back).
- **Painkillers** – `GiveMed('painkillers')`, not while they still work (`stack`) or on morphine,
  awake patients only.
- **Ice pack** – cools a contusion (`treat.cooled`, pain ↓) or takes the swelling down on a
  fracture (pain × `fracturePain`, once).
- **Burn dressing** – burns up to `maxDegree` / `maxSeverity`: cooled + dressed; worse burns are
  sent to burn care.
- **Foil blanket** – `devices.foil` (physiology rewarms, less cooling when wet).

### Oxygen mask (perm airway, item oxygen_mask)
`devices.oxygen` (SpO₂ support in physiology, faster smoke clearance). Refused when intubated.
`consume` / `removeReturns` configurable.

### Worn props (every client)
From the `nza` state bag (`tq`, `collar`) and this module's `nzaFa` bag (`o2`, `foil`, exact
tourniquet positions) every client attaches local props to patients within `Props.range`:
`Config.Props.tourniquet_worn` on the right bone at the right spot along it,
`Config.Props.collar` on the neck, oxygen mask and foil blanket when those models exist (see
`docs/requests/firstaid.md`). Missing models are skipped silently.

---

## Controls

| Where | Keys |
|---|---|
| Pressure | hold LMB on the wound · move to follow it · hold ESC abort |
| Packing | drag gauze roll → wound · hold LMB to press the packing |
| Wrap | circle the mouse around the wound · E / click the clip |
| Dressing | drag the dressing · hold LMB on each corner |
| Tourniquet | drag the strap · Space confirm · drag the tab · draw circles (reverse eases off) · E / click lock |
| Collar | drag the finger stack · 1–4 size · hold Space fasten + move the mouse |
| Medication | ↑ ↓ drug · 1–3 dose · Q W R route · Enter give (hold the button on red warnings) · ESC |
| First aid | 1–6 / click use · ↑ ↓ · ESC |
| Result card | Enter / ESC close (auto after 9 s) |

`Config.Firstaid.Keys.confirm` / `.lock` change Space / E (KeyboardEvent.code names).

---

## Config (`Config.Firstaid`)

| Key | Meaning |
|---|---|
| `Keys.confirm / lock` | minigame keys |
| `Interact.distance / stopBleed / tourniquet / meds / collar / oxygen / foil / kit / minBleed / tqBleed / icons` | patient options |
| `Radial.enabled / range` | EMS radial (Patient) entries |
| `StopBleed.perm / types / minBleed / abrasionMin / pack / packDepth / items.{pack,wrap,dressing} / minTime / maxTime / easyTime / failScore / qualityBonus / pressureTarget / pressureHold / packStrips / wrapTurns / tensionBand / anim / camera / soak.{enabled,minBleed,quality,after}` | bleed control |
| `Tourniquet.perm / item / minTime / maxTime / easyTime / minBleed / jointZone / idealAbove / armLength / legLength / occlusion.{arm,leg,min,max} / turnGain / overMargin / unwind / clipWindow / overPain / clock / warnAfter / damageAfter / damage / checkEvery / removeReturns / removePerm / camera` | tourniquet |
| `Collar.perm / item / minTime / maxTime / easyTime / fastenSeconds / drift / removeReturns / camera` | collar |
| `Oxygen.perm / item / consume / removeReturns / anim` | oxygen mask |
| `Foil.perm / item / removeReturns` | foil blanket |
| `Items.<key>.enabled / self / duration / anim / …` (+ `bandage.maxBleed / quality`, `medkit.maxSeverity / heal`, `painkillers.stack`, `ice_pack.fracturePain`, `burn_dressing.maxDegree / maxSeverity`), `Items.othersAnim` | first aid items |
| `Meds.perm / anim / prop / keepOpen / morphineRR / morphineSys / lowRRDepression / naloxoneWake / agitated / camera / drugs[]` | medication (drug list: id, item key, icon, routes, doses { dose, mg }, default, access) |
| `Props.range / tourniquet.{prop, default} / collar / oxygen / foil` | worn props (prop key, bone, pos, rot) |
| `Billing.stopbleed / tourniquet / collar / oxygen / meds` | fee for player patients when an on-duty medic treats them (0 = free) |

Items (`Config.Items`): bandage gauze tourniquet ice_pack medkit painkillers burn_dressing
foil_blanket cervical_collar oxygen_mask morphine adrenaline naloxone txa antibiotics.
Props (`Config.Props`): tourniquet_worn collar syringe (+ requested oxygen_mask foil_blanket).

---

## Events, callbacks, registries

| Name | Kind | Notes |
|---|---|---|
| `NZA.Proc 'stopbleed'` | proc | payload `{ injury? }`; items per step; states alive/wounded/arrest; result `{ score, steps, lost }` |
| `NZA.Proc 'tourniquet'` | proc | payload `{ injury?, region? }`; result `{ score, seg, frac, pressure, over, misLocks, time, steps }`; server re-checks occlusion |
| `NZA.Proc 'collar'` | proc | result `{ score, size, align, measured }`; server re-scores size vs truth |
| `NZA.Treat` | treat | `fa_bandage fa_medkit fa_painkillers fa_ice fa_burn fa_foil` (self allowed, payload `{ injury? }`), `fa_foil_off fa_oxygen fa_oxygen_off fa_collar_off fa_tq_off { region }`, `fa_med { drug, dose (index), route }` |
| `nza:firstaid:kit (target)` | callback | → `{ name, self, state, items = { { key, item, usable, text } } }` (4/s, ≤ 4.5 m) |
| `nza:firstaid:meds (target)` | callback | → panel data `{ now, name, state, pain, vitals, access, active, given, lastAdrenaline, bleeding }` (perm meds) |
| `nza:firstaid:use` | S→C | item key, after an inventory use |
| `nza:firstaid:agitated` | S→C | NPC net id, naloxone wake-up reaction on the medic's client |
| state bag `nzaFa` | replicated | `{ o2, foil, tq = { [region] = { s, f } | false } }` |
| bus (server) | | `firstaid:tq_warn (p, region)` `firstaid:tq_damage (p, region)` `firstaid:soaked (p, inj)` |
| NUI `treat` | | JS → Lua `treat:finish {result}` `treat:abort` `treat:tqPlace {seg, frac}` `treat:give {drug, dose, route}` `treat:use {key}` `treat:close`; Lua → JS `open` `anchors` `vitals` `result` `given` `meds` |
| `NZA.ExamRoutes` | client | `stopbleed` (order 10), `tourniquet` (12), `collar` (14, neck), `ice` (30), `burndressing` (34), `painrelief` (40), `morphine` (41, opens the dose panel) |
| `NZA.Interact.Add` | client | `nza_fa_stopbleed` 40 · `nza_fa_tq` 41 · `nza_fa_meds` 43 · `nza_fa_collar` 44 · `nza_fa_oxygen` 45 · `nza_fa_foil` 46 · `nza_fa_kit` 47 · `nza_fa_tqoff` 48 · `nza_fa_collaroff / oxygenoff / foiloff` 49 |
| `NZA.RadialItems` | client | parent `patient`: `fa_stopbleed fa_tourniquet fa_meds fa_kit` |

Client API: `NZA.Firstaid.Start.bleed/tq/collar/meds/kit/oxygen/tqOff/collarOff/foilOff(entity,
target, …)`, `NZA.Firstaid.UseItem(key, entity?, target?, injuryId?)`.
Server API: `NZA.Firstaid.Plan(p, inj)`, `.Eligible[key](p, preferId)`, `.TqCovers(p, region)`,
`.SyncBag(p)`, `.ReconcileTq(p)`, `.Notify(p, msg)`, `.Bill(src, p, kind)`.

## Security
- Every action goes through `NZA.Treat` / `NZA.Proc` (permission, server-side distance, items,
  rate limits, minTime / maxTime). Scores are clamped; a stop-bleeding finish faster than 2.5 s per
  step is capped at 40; the tourniquet must reach the server-computed occlusion pressure; the
  collar size is checked against the server's truth; the client never decides which region a
  tourniquet covers.
- Callbacks are rate-limited and distance-checked; medication needs the `meds` permission.

## Easy mode
All three procedures run as the core progress bar (`easyTime`) and need only their supplies: the
server uses the ideal technique (packing + dressing, tourniquet high on the upper segment, correct
collar size). In easy mode the medication panel does not require an IV / IO line.

## Known limits
- GTA peds have no visible wound under clothing, so wounds, blood, gauze, bandages and the strap
  are drawn by the overlay at the anchored bone positions; persistent worn props exist for the
  tourniquet and collar (oxygen mask / foil blanket once their models are added).
- Torso wounds anchor to the region bone (no surface offset); with unusual camera angles the drawn
  wound can sit a few centimetres off the skin surface.
- Bandages and packing are not persistent props (the wound state is, in `injury.treat`).
- Vitals in the card update only for viewers allowed to watch the patient (medics); first aiders
  see the vitals from the start of the procedure.
