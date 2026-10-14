# assess — head-to-toe check, pulse check, breathing check, help them walk

Everything a medic does to find out what is wrong before treating: the top-down
**head-to-toe check** with a holographic body map and a findings stack, a 3-step **pulse
check**, a 3-step **breathing check** with a stethoscope and synthesised breath sounds, and
**help them walk**. It also owns the server-side **discovered findings** (`NZA.Findings`)
that make hidden problems visible.

UI originality: every screen follows `docs/design/ORIGINAL.md` (NAYZEEE language: corner
brackets, status rings, instrument lists, diamond markers, edge docks, rolling counters).
No device face carries a brand.

| Side | Files |
|---|---|
| client | `client/modules/assess.lua` (helpers, patient menu, radial, help them walk, proc runner) · `assess_exam.lua` · `assess_pulse.lua` · `assess_breathing.lua` |
| server | `server/modules/assess.lua` (findings API, exam/walk callbacks) · `assess_pulse.lua` · `assess_breathing.lua` |
| NUI | `html/apps/exam/**` · `html/apps/pulse/**` · `html/apps/breathing/**` |
| config / locale | `config/modules/assess.lua` (`Config.Assess`) · `locales/en/assess.lua` (`assess.*`) |

---

## Features

### Head-to-toe check (`exam`)
- Medic kneels (`NZA.Anim.Kneel`), top-down camera (`NZA.Cam.TopDown`, or orbit), live
  medic snapshot (`NZA.Patient.Watch`).
- **Patient card** (top-left, corner bracket): name, priority and state chips, the number
  of open problems, a **time-left status ring** with a rolling counter (bleed-out clock, or
  *Holding steady* when stabilised), then an **observations** instrument list with tone
  notches: bleeding level (4-segment bar), consciousness (AVPU), skin / shock signs, blue
  lips, fast / no breathing, last pulse and breathing results with age, and device chips
  (IV line, oxygen, collar, binder, intubated, foil blanket).
- **Body map** card under it: holographic front / back figure (**F** or the segmented
  switch turns it), regions coloured by status (**Clear / Minor / Serious / Severe /
  Treated**), diamond hotspots per injury, height ruler and legend. Hover shows the region,
  click selects it.
- **Diamond markers on the 3D body** (`NZA.Anchors`, one per region, coloured by status);
  the selected region gets a dark label chip with its open count. No leader lines.
- **Findings stack** (top-right): region header with a severity status ring, severity chip,
  open count and a pain ring; then one card per problem with a **severity ring**, type,
  site, status, plain findings with tone notches (bleeding word, no exit wound / fragments,
  X-ray results, contamination, size, open fracture / deformity angle, burn depth & area,
  soot, tourniquet time), treatments already done, healing bar, and the **next care step**
  from `NZA.ExamRoutes`: a supplies table (carried / uses, red when short), the primary
  action button (**Enter**) and the alternatives under *Or instead*. Suspected problems
  have a dashed amber card.
- **Hidden problems** only appear after a check found them (`patient.meta.findings`):
  internal bleeding, haemothorax, pneumothorax, tamponade, airway compromise, fluid / spasm
  in the lungs. Before that the check only gives clues ("Belly tense and tender",
  "Penetrating wound: check for internal bleeding", "Chest wound: listen to both lungs").
- Notes visible without a check: concussion, abnormal pupils, spinal tenderness.
- **Checks dock** on the right edge: three status rings — **1 Pulse** (last rate), **2
  Breathing**, **3 Bleed control** (runs the route with id `stopbleed` on the worst bleed,
  selected region first; dimmed when nothing bleeds). Key legend bottom-left.
- Patient **speech** (core voice card, top-centre) on open and when you touch a painful
  region (pain level after painkillers / morphine, patient sex, AVPU: groans when only
  responding to pain, silent when unresponsive). Player patients only when
  `Speech.players = true`.
- After a treatment / check started from here, the check **reopens by itself** once the
  minigame is over (`Exam.reopenAfterTreat`), without the medic standing up in between.

### Pulse check (`pulse`, `NZA.Proc 'pulse'`)
Core procedure HUD (column bottom-left, tool belt right edge). Steps named in the spine:
*Locate the artery → Count the beats → Describe it*.
1. **Locate the artery** – pick the site on the belt (**1** neck, **2** wrist; the wrist is
   the left one when the right arm has a tourniquet), **scroll** (or ↑/↓) sets finger
   pressure on the readout's 240° dial (*Feather → Hard*). The **palpation scope** in the
   column (a polar radar trace swept once every 4 s) only lifts on beats inside the right
   pressure band: too light = flat, too hard = flattened artery (trace turns amber). Each
   site has its own band, narrower for a weak pulse. A world marker on the wrist / neck
   throbs on every beat you can feel. **N** = nothing at the wrist (moves to the neck) or
   nothing at the neck; only allowed after `absentAfter` seconds of palpation.
2. **Count the beats** – **Space** opens the 15 s window (amber arc on the scope rim), tap
   **Space** on every beat; the count rolls in the scope centre, taps land on the rim (teal
   on a beat, red between beats) and in the scope's instrument list.
3. **Describe it** – verdict picker with glyph keys: **1/2** regular / irregular, **3/4/5**
   weak / normal / bounding; **Enter** submits, **R** counts again.
- **Debrief** card (top-right, slides in): score ring with a rolling score and a one-word
  verdict, *n of m calls right*, a rate scale (your count as a diamond against the real
  band), rhythm and strength scales (truth ticked, your pick tagged), sites felt, notes and
  findings logged to the chart. The column shows *Your call* and **Done** (**Enter**).
- Physiology: radial absent under `radialMinSys`, carotid under `carotidMinSys`, nothing in
  arrest; HRV for sinus rhythms, chaotic intervals and **pulse deficit** at the wrist for
  AFib, **pulsus paradoxus** (fades on inspiration) with a tamponade, strength from systolic
  pressure / MAP.
- **Anti-cheat**: the client only receives an obfuscated beat schedule (Park-Miller stream
  added to 12-bit values) and pressure bands. The heart rate, rhythm and strength are never
  sent; the server re-scores the raw taps against its own schedule (rate counted vs beats
  really felt in the window, tap timing ±`tapWindow`, rhythm, strength, "no pulse" calls,
  pressure kept in band) and returns the truth only in the outcome. `minTime` enforced by
  the core.

### Breathing check (`breathing`, `NZA.Proc 'breathing'`)
Core procedure HUD; steps *Watch and count → Sweep the zones → Name the sound*.
1. **Watch and count** – the world marker on the chest rises with every breath (real RR and
   depth: laboured, shallow, agonal gasps, apnoea). **Space** opens a 15 s **count window**
   (strip in the column with a moving head and a tick per tap, rolling count), tap on every
   rise. **N** = no chest rise (after `noBreathAfter` s). The **On sight** list in the
   column (tone notches): dusky lips (SpO₂ < 90), accessory muscles, gurgling, stridor /
   snoring, which side barely moves, shallow / agonal, flail segment, unresponsive.
2. **Sweep the zones** – needs `Config.Items.stethoscope` (never consumed; the medic holds
   `Config.Props.stethoscope`). The 6 zones (R/L upper, middle, lower) are anchored on the
   front of the chest from the skeleton and shown as diamond markers. Move the chest piece
   with the mouse, **hold the mouse button** to listen (also works on the unit's pads).
   **AX-4 auscultation unit** (top-right; generic device: model plate, serial, warning
   sticker, no brand): zone tag + LIVE indicator, a scrolling **log-frequency spectrogram**
   (60 Hz – 1.6 kHz: breath noise blooms, crackles as clicks, wheeze / stridor as tonal
   lines), a **6-pad chest map** (hex pads with dwell rings, ticked when heard) and an
   instrument list (zone, dwell bar, sides 0/2, **R·L air-entry balance** meter). Breath
   sounds are synthesised with WebAudio per zone and condition: vesicular, reduced, absent,
   crackles, wheeze, stridor, gurgling, silence. Without a stethoscope this step is skipped.
3. **Name the sound** – picker in the column: *Both sides* (**1** normal, **6** crackles,
   **7** wheeze, **8** noisy airway, **9** not breathing, each with a sound glyph) and a *One
   side only* matrix (reduced / absent × right / left: **3 2 / 5 4**), **Enter** submits.
- **Debrief** card slides in under the unit: score ring + rolling score, verdict, rate scale
  (yours vs real band) with the breathing pattern chip, your sound vs the real one (partial
  credit for the right side with the wrong severity), the 6 zones in their true colours
  (dimmed when you never heard them), notes and findings logged. The unit's pads switch to
  the truth (teal normal, amber reduced, red absent, white C/W/S/G added sounds) with a
  legend.
- Truth: pneumothorax (big / tension → absent, else reduced, drained → recovers),
  haemothorax by volume (bases first), drowning water → crackles (and gurgling), smoke →
  wheeze, airway obstruction / swelling / snoring → stridor, intubation → secured,
  apnoea → silence.

### Help them walk
- **NPC** patient who is `alive`, conscious (AVPU A/V), not carried / on a stretcher / in a
  bed / bagged, and has no leg or pelvis fracture (or a splinted one with
  `Walk.allowSplinted`): stands up (get-up clip) and follows the medic
  (`TaskFollowToOffsetOfEntity`), limping (`Walk.limpClipset`) with leg injuries, jogging
  to catch up. Stops when asked again (**Tell them to wait**), when placed somewhere
  (carried, stretcher, vehicle, attached), when it goes down, when the medic goes down or
  gets more than `Walk.maxDistance` away. The server tracks it in `patient.meta.escort`.
- **Player** patient: gets a "walk with the medic" toast.

### Radial menu
`NZA.RadialItems` under parent `patient`: Head-to-toe check / Take a pulse / Assess breathing / Help them walk
on the nearest patient within `Radial.range`.

---

## Controls

| Where | Keys |
|---|---|
| Head-to-toe | click a region (map or body) / ↑ ↓ · F turn the map · Enter start the next care step · 1 pulse · 2 breathing · 3 bleed control · ESC close |
| Pulse | Scroll / ↑ ↓ pressure · 1 neck · 2 wrist · Space open the window / tap · N nothing here · 1-5 describe · R count again · Enter submit / done · hold ESC leave |
| Breathing | Space open the window / tap · N no chest rise · Enter next · hold LMB listen · 1-9 name the sound · Enter submit / done · hold ESC leave |

Pulse and breathing keys are configurable (`Config.Assess.Pulse.keys`, `.Breathing.keys`,
KeyboardEvent.code names).

---

## Config (`Config.Assess`)

| Key | Meaning |
|---|---|
| `Interact.perm / distance / examine / pulse / breathing / icons` | patient menu options |
| `Radial.enabled / range` | EMS radial entries |
| `Exam.camera / height / maxDistance / anim / idle / reopenAfterTreat / reopenWait / notifyPatient` | head-to-toe check |
| `Speech.enabled / players / onOpen / onTouch / cooldown / duration / levels / lines.{m,f}.{none,mild,moderate,severe,groan}` | patient subtitles |
| `Pulse.minTime / maxTime / easyTime / countSeconds / absentAfter / radialMinSys / carotidMinSys / weakSys / boundingSys / tapWindow / startSite / camera / anim / keys` | pulse check |
| `Breathing.minTime / maxTime / easyTime / countSeconds / listenSeconds / requireStethoscope / noBreathAfter / drowningCrackles / haemoAbsent / pneumoAbsent / camera / anim / listenAnim / prop / keys` | breathing check |
| `Walk.enabled / perm / allowSplinted / maxDistance / offset / stopRange / jogDistance / getUpAnim / limpClipset / playerPrompt / cooldown` | ask to walk |
| `Billing.exam / pulse / breathing` | optional fee for player patients (0 = free; once per 10 min per medic & patient) |
| `Records` | write pulse/breathing results to `nza_records` (via the core's proc record) |

Items: `Config.Items.stethoscope`. Props: `Config.Props.stethoscope`.

---

## APIs for other modules

### Server: `NZA.Findings` (discovered findings)
```lua
NZA.Findings.Add(pid, key, data) → finding
NZA.Findings.Remove(pid, key) → bool      NZA.Findings.Has(pid, key) → bool
NZA.Findings.Get(pid) → { [key] = finding } (copy)
NZA.Findings.Clear(pid, filter?)          -- filter(finding, key) → true = drop
exports['nayzeee-ambulance']:AddFinding(pid, key, data)  /  :GetFindings(pid)
```
`data` (all optional, plain values): `cond` (condition name: the finding is dropped when the
condition is cleared), `injury` (injury id: dropped when the injury is removed), `side`
(`'left'|'right'`), `group` (exam body group; none = General card), `region`, `source`
(`'breathing'|'pulse'|'ultrasound'|'xray'|'angio'|...`), `text` (detail line shown in the
exam), `by` (medic src), `organ`... Stored in `patient.meta.findings` (persisted for
players, included in the medic snapshot). Cleared on a full revive; `pulseless` / `apnoea`
are cleared on ROSC. Bus: `findings:changed (p, key, finding|nil)`.

Keys this module writes: `pulse` `{ rate, site, rhythm, strength }`, `breathing`
`{ rate, call }`, `no_radial_pulse`, `pulseless`, `irregular_pulse`, `tamponade_suspected`,
`haemothorax_suspected_<side>`, `pneumothorax_suspected_<side>`, `aspiration_suspected`,
`bronchospasm_suspected`, `airway_compromise`, `apnoea`.

**How other checks reveal hidden problems in the exam**
- Suspected condition card: any finding with `cond` set to a condition that is still
  present and is one of `haemothorax pneumothorax tamponade airway hypoxia`, e.g.
  ultrasound: `NZA.Findings.Add(pid, 'haemothorax_suspected_right', { cond = 'haemothorax', side = 'right', group = 'chest', source = 'ultrasound', text = 'Fluid above the liver (45 mm)' })`.
- Internal bleeding: a finding with `injury = <internal injury id>`, or the key
  `internal_suspected_<region>` / `internal_suspected_<group>` (e.g.
  `internal_suspected_abdomen`). Internal injuries with `treat.coiled` / `treat.xrayMarked`
  are always shown.

### Client: `NZA.ExamRoutes` (treatment buttons in the exam)
```lua
NZA.ExamRoutes = NZA.ExamRoutes or {}
table.insert(NZA.ExamRoutes, {
    id = 'suture', label = 'Suture the wound', icon = 'needle', perm = 'suture', order = 20,
    types = { 'laceration', 'stab' },          -- injury types or condition names (suspected conditions)
    regions = nil,                             -- or { 'chest', ... }
    items = { [Config.Items.suture_kit] = 1 }, -- shown as have/need; Treat is disabled when missing
    available = function(inj, snap) return true end,  -- false + reason → greyed with reason; false + nil → hidden
    run = function(target, inj, snap) ... end, -- may block (NZA.Proc.Run); the exam reopens afterwards
})
```
Suspected conditions are passed as `inj = { id = 'c:<finding key>', type = <condition>,
condition = true, region, group, side, severity, finding }`. Up to 4 routes per injury,
available first, then by `order`. The route with id **`stopbleed`** drives the *Stop
bleeding* button.

### Client helpers (`NZA.Assess`)
`Start.exam|pulse|breathing(entity, target)`, `Busy()`, `RunProc(o)`, `Track(app, defs, own)`
(anchors incl. `fn` anchors), `Cam`, `Anim`, `Prop`, `ItemCount`, `ItemLabel`,
`NearestPatient(range)`, `Walk(entity, target)`, `StopWalk(reason)`, `Following(entity)`.

---

## Events, callbacks, NUI

| Name | Kind | Notes |
|---|---|---|
| `nza:assess:exam (target)` | callback | perm `Interact.perm`, distance ≤ examDistance + 1, notifies player patients, optional fee |
| `nza:assess:walk (target, on)` | callback | ask / stop; validates state, AVPU, placement, leg fractures, cooldown; sets `meta.escort` |
| `nza:assess:outcome (nonce)` | callback | fallback fetch of the last pulse/breathing outcome |
| `nza:assess:walkPrompt` | S→C | `{ medic, ms }` toast for player patients |
| `NZA.Proc 'pulse'`, `'breathing'` | proc | perm `Interact.perm`, states alive/wounded/arrest/dead, maxDist 3 m, `minTime`/`maxTime`/`easyTime` from config |
| bus `assess:exam (src, p)`, `assess:done (src, p, kind, outcome)`, `findings:changed` | server bus | |
| exam NUI | `exam:touch {group}` `exam:treat {id, route}` `exam:action {action, group}` `exam:close` | Lua → `open`, `view` |
| pulse NUI | `pulse:site {site}` `pulse:finish {result}` `pulse:abort` `pulse:close` | Lua → `open`, `result`, `anchors` |
| breathing NUI | `breathing:step {step}` `breathing:finish {result}` `breathing:abort` `breathing:close` | Lua → `open`, `result`, `anchors` |

Easy mode: both checks run as the core progress bar; the outcome then uses the truth as the
medic's finding, records every true finding and shows the summary in the result toast.

---

## Known limits
- The medic snapshot from the core already contains exact vitals (the bedside monitor
  needs them), so the obfuscated schedule protects the minigame, not the data itself.
- Zone anchors are computed from spine / clavicle bones with fixed offsets (13–15 cm in
  front of the spine, 8–12 cm sideways); unusual ped scales may need `Breathing` camera tuning.
- NPC following needs network control of the ped; when another player takes ownership the
  task is re-requested every 0.5 s (brief pauses are possible).
- Breath sounds need WebAudio in the NUI (CEF has it); `Config.UI.sounds = false` mutes
  them, the trace and the air entry meter still work.
- Speech lines live in `Config.Assess.Speech.lines` (translate there).
