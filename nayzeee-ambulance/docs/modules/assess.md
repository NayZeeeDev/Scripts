# assess — Examination, Check Pulse, Check Breathing, Ask to Walk

Everything a medic does to find out what is wrong before treating: the top-down
**Examination** with injuries to treat, a 3-step **pulse check**, a 3-step **breathing
check** with a stethoscope and synthesised breath sounds, and **Ask to Walk**. It also owns
the server-side **discovered findings** (`NZA.Findings`) that make hidden problems visible.

| Side | Files |
|---|---|
| client | `client/modules/assess.lua` (helpers, patient menu, radial, ask to walk, proc runner) · `assess_exam.lua` · `assess_pulse.lua` · `assess_breathing.lua` |
| server | `server/modules/assess.lua` (findings API, exam/walk callbacks) · `assess_pulse.lua` · `assess_breathing.lua` |
| NUI | `html/apps/exam/**` · `html/apps/pulse/**` · `html/apps/breathing/**` |
| config / locale | `config/modules/assess.lua` (`Config.Assess`) · `locales/en/assess.lua` (`assess.*`) |

---

## Features

### Examine Patient (`exam`)
- Medic kneels (`NZA.Anim.Kneel`), top-down camera (`NZA.Cam.TopDown`, or orbit), live
  medic snapshot (`NZA.Patient.Watch`).
- **8 region labels** (head, neck, chest, abdomen, arms, legs) anchored to bones with
  `NZA.Anchors`: name + status **Healthy / Minor / Serious / Critical / Treated**, a dot on
  the body and a thin leader line. Labels are laid out in two columns (patient's left and
  right limbs on their own side, midline regions alternate) and de-overlapped every frame,
  so leader lines never cross the body. Count badge when a region has several problems.
- **Injuries to treat** card for the selected region: type, severity, plain findings
  (bleeding word, no exit wound / fragments, X-ray results, contamination, size of cuts,
  open fracture / deformity angle, burn depth & area, soot, tourniquet time), treatments
  already done, healing progress, and the next treatment(s) from `NZA.ExamRoutes` with the
  items you carry as have/need (`✓ Bandage 8/1`) and a **Treat injury** button.
- **Hidden problems** only appear after a check found them (`patient.meta.findings`):
  internal bleeding, haemothorax, pneumothorax, tamponade, airway compromise, fluid / spasm
  in the lungs. Before that the exam only gives clues ("Belly tense and tender",
  "Penetrating wound: check for internal bleeding", "Chest wound: listen to both lungs").
- Notes visible without a check: concussion, abnormal pupils, spinal tenderness.
- **General card**: consciousness (AVPU), skin (shock signs), blue lips, fast / no
  breathing, last pulse and breathing results with age, general findings, devices.
- Bottom-left summary (EXAMINATION, bleeding level, N injuries to treat, state, bleed-out
  flip clock or *Stabilized*), bottom buttons **Check pulse / Check breathing / Stop
  bleeding** (the last one runs the route with id `stopbleed` on the worst bleed, selected
  region first; hidden when no such route exists or nothing bleeds).
- Patient **speech subtitles** on open and when you touch a painful region (pain level
  after painkillers / morphine, patient sex, AVPU: groans when only responding to pain,
  silent when unresponsive). Player patients only when `Speech.players = true`.
- After a treatment / check started from the exam, the exam **reopens by itself** once the
  minigame is over (`Exam.reopenAfterTreat`), without the medic standing up in between.

### Check Pulse (`pulse`, `NZA.Proc 'pulse'`)
1. **Find the pulse** – pick the site (**1** carotid, **2** radial; the radial is on the left
   wrist when the right arm has a tourniquet), **scroll** (or ↑/↓) sets finger pressure
   (Light → Deep meter). The *under your fingers* trace only shows beats inside the right
   pressure band: too light = nothing, too hard = occluded (trace turns amber). Each site
   has its own band, narrower for a weak pulse. A world marker on the wrist / neck throbs on
   every beat you can feel. **N** = "no radial pulse" (switches to the carotid) or "no pulse"
   at the carotid; only allowed after `absentAfter` seconds of palpation.
2. **Count** – **Space** starts a 15 s count, tap **Space** on every beat; good taps click
   high, taps without a beat click low and show red on the trace.
3. **Judge** – **1/2** regular/irregular, **3/4/5** weak/normal/bounding, **Enter** submit,
   **R** count again.
- Result card: grade, *your finding vs patient* (rate, rhythm, strength, site with
  palpable carotid/radial chips, heart rate vs wrist rate in atrial fibrillation),
  feedback bullets, findings recorded. **Enter** closes.
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

### Check Breathing (`breathing`, `NZA.Proc 'breathing'`)
1. **Look & feel** – the world marker on the chest rises with every breath (real RR and
   depth: laboured, shallow, agonal gasps, apnoea). **Space** starts a 15 s count, tap on
   every rise. **N** = no chest rise (after `noBreathAfter` s). *What you see* card: dusky
   lips (SpO₂ < 90), accessory muscles, gurgling, stridor / snoring, which side barely moves,
   shallow / agonal, flail segment, unresponsive.
2. **Listen** – needs `Config.Items.stethoscope` (never consumed; the medic holds
   `Config.Props.stethoscope`). The 6 zones (R/L upper, middle, lower) are anchored on the
   front of the chest from the skeleton. Move the stethoscope with the mouse, **hold the
   mouse button** to listen (also works on the device's acoustic map). Device *NAYZEEE
   AUSCULT*: zone name, scrolling sound trace, hold progress, lung wireframe map with the
   zones, air entry meter, sides 0/2. Breath sounds are synthesised with WebAudio per zone
   and condition: vesicular, reduced, absent, crackles, wheeze, stridor, gurgling, silence.
   Without a stethoscope this step is skipped.
3. **Call** – **1-9**: normal / reduced L / reduced R / absent L / absent R / crackles / wheeze /
   noisy airway / not breathing, **Enter** submit.
- Result card: grade, rate yours vs patient, pattern, call vs truth (partial credit for the
  right side with the wrong severity), zones heard; the acoustic map then shows the real
  sound of every zone (teal normal, amber reduced, red absent, C/W/S/G added sounds).
- Truth: pneumothorax (big / tension → absent, else reduced, drained → recovers),
  haemothorax by volume (bases first), drowning water → crackles (and gurgling), smoke →
  wheeze, airway obstruction / swelling / snoring → stridor, intubation → secured,
  apnoea → silence.

### Ask to Walk
- **NPC** patient who is `alive`, conscious (AVPU A/V), not carried / on a stretcher / in a
  bed / bagged, and has no leg or pelvis fracture (or a splinted one with
  `Walk.allowSplinted`): stands up (get-up clip) and follows the medic
  (`TaskFollowToOffsetOfEntity`), limping (`Walk.limpClipset`) with leg injuries, jogging
  to catch up. Stops when asked again (**Tell to wait here**), when placed somewhere
  (carried, stretcher, vehicle, attached), when it goes down, when the medic goes down or
  gets more than `Walk.maxDistance` away. The server tracks it in `patient.meta.escort`.
- **Player** patient: gets a "walk with the medic" toast.

### Radial menu
`NZA.RadialItems` under parent `patient`: Examine / Check pulse / Check breathing / Ask to walk
on the nearest patient within `Radial.range`.

---

## Controls

| Where | Keys |
|---|---|
| Exam | click a region / ↑ ↓ Tab · Enter treat the first available route · 1 pulse · 2 breathing · 3 stop bleeding · ESC close |
| Pulse | Scroll / ↑ ↓ pressure · 1 carotid · 2 radial · Space start count / tap · N no pulse here · 1-5 judge · R recount · Enter submit / done · hold ESC stop |
| Breathing | Space start count / tap · N no chest rise · Enter next · hold LMB listen · 1-9 call · Enter submit / done · hold ESC stop |

Pulse and breathing keys are configurable (`Config.Assess.Pulse.keys`, `.Breathing.keys`,
KeyboardEvent.code names).

---

## Config (`Config.Assess`)

| Key | Meaning |
|---|---|
| `Interact.perm / distance / examine / pulse / breathing / icons` | patient menu options |
| `Radial.enabled / range` | EMS radial entries |
| `Exam.camera / height / maxDistance / anim / idle / reopenAfterTreat / reopenWait / notifyPatient` | examination |
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
