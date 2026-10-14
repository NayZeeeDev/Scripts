# Originality rules (customer requirement)

The customer showed screenshots of a competing ambulance script as a **feature and quality
reference only** (index with paths: `/tmp/nza-work/reference/INDEX.md`). Customers and viewers
must never be able to say this resource copies another creator. That means: match and beat
its depth, but every screen must have **its own layout, composition, visual language and
wording**. When in doubt, change it.

Also: **no NAYZEEE name or logo on props or on in-world device faces** (anything drawn to look
like a physical device: monitors, defibrillator, pager, haemostat, injector, ultrasound,
fluoroscopy, lightbox, TV board, DUI screens). Use generic device labelling (device type,
model code, warning stickers). Windows built with `.nza-win` keep the UI pack signature.

## 1. Look-alikes that are NOT allowed

| Screen | Their signature (do not reproduce) |
|---|---|
| Procedure panel | One wide box bottom-centre: `1/4` + dash segments, title + text left, stats right, numbered tool pills in a row, `ESC Hold to abort` pill bottom-right. (Core now ships a different HUD — keep apps off the bottom-centre.) |
| Wounded | Split-flap digit cards + big `WOUNDED` + `STABILIZED — CLOCK PAUSED`, key row `W Crawl S Stop A D Turn G Call EMS E Give up` under it, bottom-centre. |
| Examination | Big `EXAMINATION` title bottom-left with a red summary line; region labels with `Healthy/Critical` tags joined to the body by leader lines; `INJURIES TO TREAT` card on the right with item counts and a `Treat injury` button; `Check pulse / Check breathing / Stop bleeding` buttons along the bottom. |
| Speech | `◂ PATIENT · NAME  line` strip bottom-centre. |
| Prompt | `[E] Check in — treat injuries · Check-in Desk` text on the right-middle edge. |
| Pulse / breathing | `Find the pulse` 1/3, site + pressure + palpating stats, `under your fingers` wave box, result page with a big letter grade and a `your finding vs patient` table. |
| Call card / pager | `URGENT 10-52 Gunshot Wound` card with `X dismiss / E respond`; green LCD pager `P2 OVERDOSE / street / 310M ETA` with `BACK DECL / Y ACK` and the `DSP>ENR>SCN>CARE>TRN>HSP` chain. |
| Check-in | White paper receipt `YOUR NUMBER A-001 / TRIAGE CRITICAL / PATIENTS AHEAD / WAITING / ISSUED / barcode / Please keep this ticket`; TV board `Now serving / waiting list / incoming ambulances / staff on duty` in that arrangement. |
| Radial | Ring with the medic name + `10-7` in the centre and `Dispatch / Patient / Stretcher / Go on duty` wedges. |
| Device faces | Their exact device screen layouts (defib `ASYSTOLE / code timer / 200 J / compressions 12/30`, intubation `DESATURATING`, haemostat, IO drill layer bars, thermal camera, mesher, ultrasound 6-window grid with POS/NEG, angio `distance to bleed / coil %`). Same medical data is fine; the arrangement must be ours. |
| Windows | Their pharmacy (category list with counts + product cards with struck old price + cart column), medic-bag storage (bag slots + `1/5/10/ALL` transfer + `REMOVED 1X` toasts), manager (folder explorer). |
| Copy | Do not reuse their phrases, e.g. "Hold to abort", "Treat injury", "Injuries to treat", "Examination", "Stabilized — clock paused", "Find the pulse", "Under your fingers", "Drop the binder here", "Fill blood bag", "Exit treatment bay", "surgery costs blood — hang a unit first", "Check in — treat injuries", "Now serving", "Incoming ambulances", "Your number", "Please keep this ticket", "Removed 1x", "on the beat", "You have arrived at the scene". Write our own short, plain, imperative lines. |

## 2. The NAYZEEE visual language (use these instead)

From the customer's own designs (`docs/design/nayzeee-ui-v5.html`, `nayzeee-ui-hud-design.html`) and
the shared kit (`html/core/nza.js` / `nza.css`):

- **Corner brackets**: teal L-bracket on the top-left corner of key cards instead of full top rails.
- **Spines, not dashes**: vertical step spine for progress; vertical lists over horizontal strips.
- **Dials & rings**: 240° dials for measured values, the HUD design's status rings (icon in a
  progress ring) for timers, holds and vitals. Rolling (odometer) mono counters — never split-flap.
- **Instrument lists**: label left / mono value right rows with a tone notch, instead of rows of
  big stats.
- **Belts & docks on the edges**: tools as icon slots on the right edge (core ProcPanel), action
  sets as vertical stacks or radial menus — never a row of pills along the bottom-centre.
- **Dark label chips** for anything over a bright 3D scene (text never floats on the scene).
- **Body & region work**: holographic body map in a side card (front/back toggle, region hotspots,
  colour-coded, tooltip on hover) and diamond markers on the 3D body — no leader-line labels.
- **Device faces**: our own industrial design — dark bezel, generic model code, our own screen grid
  (instrument lists, dials, traces from `NZA.vitals`), physical-looking buttons. No brand.
- **Placement**: centre for the scene; top-left/top-right for context cards; bottom-left for the
  procedure column; right edge for tools; top-centre for transient voice/status.
- **Motion**: things slide in from their edge; values roll; rings fill; the current step node pulses.

## 3. Checklist for every app

1. Open the matching reference screenshot(s) and your app's preview side by side.
2. Would a viewer who knows the other script recognise the layout, a widget or a phrase? Change it.
3. No NAYZEEE text or logo on device faces / props / DUI screens.
4. Bright-scene readability: every text block sits on a dark chip or card.
5. Polish to "wow": depth (shadows, inner highlights), motion, real data, no placeholder text,
   no overlapping widgets at 1920×1080 and 1280×720 (`--nza-zoom` scales the HUD).
