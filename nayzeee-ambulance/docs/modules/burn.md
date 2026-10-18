# Module: burn — burn care & skin graft

Two server-validated procedures played in ONE full-screen 3D close-up (NUI app `burn`, built on the
shared engine `html/core/nza3d.js`):

| Procedure | `NZA.Proc` name | Perm | Supplies (Config.Items keys) | Steps |
|---|---|---|---|---|
| Burn care | `burn` | `Config.Burn.perm` (`burn`) | `saline` (always) + `burn_dressing` (when dressed here) + optional `dressing` (secures large burns) | 1 cool · 2 test depth · 3 debride · 8 dress |
| Skin graft | `graft` | `Config.Burn.Graft.perm` (`graft`) | `graft_kit` (always) + `burn_dressing` (when dressed) | 4 excise · 5 harvest · 6 mesh · 7 lay & staple · 8 dress |

Partial-thickness burns go 1 → 2 → 3 → 8. When the depth test finds full-thickness skin, the medic
chooses **Graft now** (G) — the app asks the server first — or **Dress, graft later** (D). Graft now
finishes burn care with `continue = true` (the dressing is left for the graft) and the graft session
starts in the same app without closing it. The graft needs the patient on a surgery point or in the
ambulance treatment bay (`patient.meta.bed.type` / `patient.meta.bay`, see `Config.Burn.Graft.locations`)
— **except in easy mode**, where only the supplies are needed.

Files: `client/modules/burn.lua`, `server/modules/burn.lua`, `config/modules/burn.lua`,
`locales/en/burn.lua`, `html/apps/burn/app.js`, `html/apps/burn/app.css`.

## Features

**Scene (WebGL, nza3d).** The burn is drawn on the patient's real region (limb cylinder / torso) and
skin tone. On top of the engine's skin the burn module patches THIS scene's skin shader with its own
partial-thickness layer (generated per burn): weeping cherry-salmon dermis with punctate capillaries,
mottled ivory deep-partial pallor that hugs the eschar, torn sheets of dead epidermis with rolled,
lifted edges, a hot blotchy erythema that calms as the burn cools, wet clear-coat gloss on the open
dermis and relief from a generated normal map. Full-thickness areas are separate conformed plates:
waxy-white to leathery-brown eschar with charred crust, grey ash bloom, sparse fissures, thrombosed
vessels and a dark junction line. Intact blisters are glossy, fluid-filled domes over raised skin; loose
dead skin is curled, translucent sheets with soot caught in them. Soot is a washable black haze, heavier
patches and fine ash flecks (engine layers). Steam rises while the burn is hot under saline.

1. **Cool the burn** — hold LMB: a saline bottle pours a real stream (engine jet) that washes soot and
   wets the skin. A 2D heat model (surface + deep reservoir, diffusion, perfusion, evaporating saline
   film) gives every millimetre its own temperature: stop too early and the deep heat warms the surface
   back up; pour at a cold area too long and the patient is over-cooled (hypothermia warning, body
   cooling on the server). The burn counts as cooled when `coolFrac` of it stays under the target for
   `holdTime` after you stop. Bottles run out (two per saline item) and are swapped automatically.
2. **Test the depth** — diascope (glass disc) pressed with LMB: partial-thickness skin blanches under
   the glass, full thickness stays fixed. Slide to test cell after cell; the imager builds a depth map,
   the case card shows the estimated full-thickness percentage.
3. **Debride** — forceps: grip a blister roof or a loose sheet and pull it about `pullMm` away; let go
   early and it falls back. The base underneath turns raw, wet and pink (the burn surface texture is
   repainted live).
4. **Excise** — knife: trace the marked outline round each full-thickness area within `traceTol` mm; the
   eschar lifts off and leaves a glistening, bleeding bed. Straying into healthy skin bleeds and costs.
5. **Harvest** — a second scene on the donor thigh (the side away from the burn): hold LMB at the start
   line and push the dermatome at a steady `speedMin–speedMax` mm/s, wheel = pressure (keep it in the
   band while it drifts). The strip quality (thin / ragged / stalls) follows your hand.
6. **Mesh** — a 3D mesher bench: choose the carrier ratio (1:1.5 or 1:3, Q/E or the segmented control in
   the column, suggested by the bed area); hold LMB and circle the pointer clockwise round the crank to
   feed the graft through the rollers. Too fast (`crankMax` turns/s) tears it. The imager shows the
   expansion plan (how much of the bed the meshed graft will cover).
7. **Lay & staple** — pick the meshed graft up, lay it over the bed (Q/E turn while carried), then staple
   every marked point round the edge (`stapleSpacing` mm). Enough staples → Enter to go on.
8. **Dress** — pick the burn dressing up by an edge, lay it over the whole burn, rub it down until it
   sticks. Burns ≥ `secureAbove` cm² get the optional sterile dressing on top when carried.

**HUD.** Core `NZA.ui.ProcPanel` (left instruction column with the 240° dial + instrument list, step
spine, "Next" line; right-edge tool belt 1–8 with the hold-to-cancel ring). Top-left: the handheld
wound imager (generic device: model code `WI-6`, lens, LED, laser warning sticker — no brand) with a
live heat map (palettes lava / iron / grey, freeze, AR overlay on the burn with T), depth map, tissue
map, excision map, donor map, expansion plan, graft-fit and cover views, a per-mode instrument list
and a trend trace. Top-right: the case card (patient ring with initials, body map with the burn and
donor site, depth / area · %TBSA / core temp / pain bar, result chips). Patient lines use `NZA.speech`.
The result page shows the grade and the server outcome. A loading veil covers shader warm-up.

## Controls

| Input | Action |
|---|---|
| 1–8 | pick the tool for a step (only the current step's tool is live) |
| LMB (hold) | pour · press · grip · cut · push · crank · carry · staple · rub |
| Wheel | zoom; dermatome pressure during step 5 |
| RMB drag / Shift+RMB | look around / pan (engine controls) · R recentre |
| T | heat overlay on the burn |
| Q / E | carrier ratio (step 6) · turn the graft / dressing while carried |
| G / D | graft now / dress and graft later (decision after the depth test) |
| Enter | go on when a step is good enough · close the result |
| Esc (hold) | cancel the procedure |

## Config (`config/modules/burn.lua` → `Config.Burn`)

`perm minTime maxTime easyTime maxDist allowSelf items optional secureAbove` (burn care) ·
`Graft = { perm minTime maxTime easyTime maxDist items requireLocation locations needCare
continueWindow donorRegions donorInjury bloodPerCm2 donorBloodPerCm2 maxBlood minCoverage minStaples
minExcised }` · `cooledBelow sootLeftMax debridedMin healBonus painRelief overcoolWet overcoolMax` ·
`interact radial usableItem useRange order skinTones` · `Game = { quality bottleMl bottles salineFlow
refillTime salineTemp jetRadius target holdTime coolFrac overcool sootDone rebound assessCover
pressTime diascopeMm pullMm traceTol traceDone graftWidth speedMin speedMax pressureBand pressureDrift
feedPerTurn crankMax stapleSpacing stapleTol stuckDone coverMin weights graftWeights fallbackTime }`
(sent to the NUI as `data.cfg`).

## Server (authoritative)

- `NZA.Proc.Register('burn' | 'graft', …)`: perm, distance, states (alive / wounded), items
  (`consume = 'finish'`, the dressing is taken by hand only when it was used), `minTime`, easy time.
- `onStart` re-checks the injury (`CareEligible` / `GraftEligible`), the burn dressing, the room (graft,
  not in easy mode) and returns the case (burn numbers, tone, seed, donor, supplies, graft pre-check).
- `onFinish` clamps every client number (`surfaceTemp sootLeft debrided stuck cover overcool excised
  excisedCm2 donorCm2 coverage staples`), caps the score by the configured step weights, and applies:
  `treat.cooled / irrigated / debrided / dressed / grafted`, `quality`, burn temp / soot / assessed /
  excised / ratio, pain relief, contamination, heal bonus (definitive care only), over-cooling →
  `meta.wet` (core body cooling), graft blood loss (`AddBlood(-ml)`), a dressed donor-site graze.
- "Graft now" continuity: burn care that ends with `continue` is remembered per patient+injury+medic
  for `continueWindow` seconds; the following graft session skips `needCare` only for that medic.
- Easy mode: no minigame (core progress bar), every requirement except the supplies is skipped.

## Events, callbacks, API

- Callback `nza:burn:graftCheck (target, injuryId, continuing) → { ok, err, msg, easy }` (rate 4 / 2 s).
- S→C `nza:burn:use` (graft kit used → nearest patient).
- Server bus: `burn:done (src, p, inj, outcome)`, `graft:done (src, p, inj, outcome)`.
- Client bus: `burn:pain (patientEntity, pain)` when the patient reacts in the minigame.
- Server API `NZA.Burn.Find(p, id) · CareEligible(inj, easy) · GraftEligible(inj, easy, continued) ·
  Location(p) · Donor(p, inj) · Case(src, p, inj, mode, info)`.
- Client API `NZA.Burn.Start(entityOrTarget, injuryId, mode) → ok, outcome | reason` (blocks),
  `NZA.Burn.Pick(entity, target, mode)` (context menu when there are several burns),
  `NZA.Burn.CareEligible(inj)`, `NZA.Burn.GraftEligible(inj, snap?) → ok, reasonText`.
- NUI (`burn:*`): `finish (result) → { ok, pending }` then action `careDone` (continue) or `result`;
  `graftCheck → { ok, msg }`; `abort`; `pain { pain }`; `close` (core). Lua → JS actions: `open (case)`,
  `careDone`, `graft (case)`, `graftFail { msg }`, `result (outcome)`, `abort`.
- Registries: `NZA.ExamRoutes` `burn` (order 34) and `graft` (order 36, reason text when the patient is
  not in theatre / the bay); `NZA.Interact` `nza_burn`, `nza_graft` (order 63/64);
  `NZA.RadialItems` `burn_care`, `burn_graft` (parent `patient`); usable item `Config.Items.graft_kit`.

## Preview

`html/index.html?app=burn` (full-thickness thigh burn, burn care), `&mode=graft` (straight to the
graft), `&deg=2` (partial thickness only). `NZA.apps.burn.demoTo(stage)` plays the procedure to a
stage for screenshots: `cooling cooled testing tested debriding decision excising excised harvesting
harvested meshing placing stapling dressing done`.

## Known limits

- The partial-thickness look patches the engine's skin shader text at compile time (anchors
  `vec3 nzaPart =` … `nzaCol = mix(nzaCol, nzaFull, …)`). If the engine changes those lines the patch
  is skipped and the engine's own burn colouring is used — nothing breaks.
- Engine `fluids.drops` always lands as blood, so blister serum is painted as a wet film instead.
- Without WebGL2 the app falls back to a timed progress card (`Game.fallbackTime`) with a fixed score.
