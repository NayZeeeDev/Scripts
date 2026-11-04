# Redesign brief: garage menu, admin locations, vehicle dossier

The owner's verdict on the current garage menu, the admin location pages and the admin
vehicle detail: **"they look way too similar to JG Advanced Garages — make them different,
more detailed and better quality while keeping my UI style."**

Current state (what to move AWAY from), screenshots of our build:
- garage menu: `/root/.claude/uploads/939d8efe-994e-5a21-be29-bbf4e311b951/39b60a1c-image.jpg`
  (centered window, 3-column grid of image cards, chip filters row, "Your spaces" meter)
- admin garages: `…/51ef6ce0-image.jpg` (sidebar, table with icon buttons per row, small
  vector map on the right, pagination)
- admin vehicle detail: `…/a50335a2-image.jpg` (6 equal cards: Details, Impound, Installed
  mods, Finance, Ownership history, Service history)

Do NOT open the "reference screenshots" listed in docs/UI_KIT.md §5 for these three screens
(they are the competitor's screens and are the reason the result looked alike). Read the
owner's own style files instead: `docs/design/nayzeee-ui-v5.html` and
`docs/design/nayzeee-ui-design.html`, plus docs/UI_KIT.md §1–2 (tokens, components, CEF rules).

## Style rules (unchanged, non-negotiable)

Lexend + JetBrains Mono (plates, ids, coordinates), the window frame with the chamfered
bottom-right corner and film grain, teal brand mark, red **Close** pill at the far right of
window headers, solid-teal toggles, white-active pill segmented controls/tabs, chips,
uppercase 11px section headings (700, .12em, ink-3), option rows, teal primary / outline /
red destructive buttons, opaque windows (`--base`), tokens only (never hardcode the teal —
use `var(--teal*)`), tabular numbers. CEF: no backdrop-filter, no color-mix(), no :has(), no
CSS nesting. Every string through `t()`. Must fit 1920×1080 and 1280×720 without page scroll
(inner panels may scroll). Keyboard support everywhere it makes sense.

"Better than JG" means: more information per screen without clutter, a clear focal point,
richer visuals made from data we actually have (no fake numbers), smooth 130–220ms motion,
excellent empty / loading / error states.

---------------------------------------------------------------------------------------

## 1. Garage menu → "Showroom" (src/apps/garage/**, src/apps/impound/**)

A two-pane showroom instead of a card grid. Window `min(1240px, 94vw)` × `min(930px, 92vh)`
(garage and impound). The stage takes spare height (up to 400px) when the detail sections are
short; an in-flow "Upgrades · Details ↓" / "Back to top" bar appears only when the sections
overflow.

**Header:** brand mark, garage name (+ kind subtitle: Public garage / Hangar / Marina /
Private garage · group label / Job garage · job label). headerExtra: capacity as a **slot
strip** (one small rounded cell per space, teal = used, line = free; above 24 spaces show a
compact bar + "9 / 40"), "Enter interior" (walk icon) when `canGoInside`, private-garage
controls (group switcher, Members, Sell garage) as today, red Close pill.

**Left rail (≈ 360px) — the collection:**
- SearchInput (`/` focuses it, shows the keycap), then filter chips with counts (All,
  Favourites, Here, Shared, Impounded, Out — hide chips with 0 except All), and a small
  Select for sort (Relevance, Name, Mileage, Condition, Last driven) plus a density toggle
  (comfortable rows with thumbnails ↔ compact rows; `settings.interface.defaultView`
  'grid' = comfortable, 'list' = compact).
- Rows **grouped by vehicle class** (`classLabel`, fall back to "Other") under uppercase
  section headings with counts ("SUPER · 3"). Group-by toggle: Class / Status / None.
- Row: thumbnail on an inset tile, name (ellipsis) + nickname, PlateTag, a status line with a
  coloured dot (teal "Here", ink "At Mirror Park", amber "Out", red "Impounded", grey
  "Blocked"), favourite star, and a 3px engine-health bar along the row's bottom edge.
  Selected row: teal wash + glowing left bar (v5 nav item style). Smooth scroll-into-view.
- Keyboard: ↑/↓ select, Enter drive, F favourite, R rename, Esc closes the top modal / app.

**Right — the showcase of the selected vehicle:**
- **Stage** (≈ 260–300px tall): the vehicle image large on a "turntable": radial spotlight,
  elliptical floor shadow, a faint perspective floor grid and a thin teal horizon line (all
  CSS gradients). Overlays: top-left class Badge + vehicle-type icon; top-right favourite
  IconButton and "Shared by X" Badge; bottom-left big name (24px/600), nickname in quotes,
  make; bottom-right a **registration plate** component (dark inset plate, mono 15px white
  plate text, tiny "SAN ANDREAS" caption, 1px line).
- **Status strip** (4 cells with hairline dividers): Location (garage / Out / impound
  name), Mileage, Last driven (relative: "2 days ago"), Sharing ("Shared with 2" / "Shared
  by Marcus" / "Private").
- Two-column detail sections (scroll inside the showcase if needed):
  - CONDITION: segmented 10-cell gauges for Engine, Body, Fuel with %; tone auto. Next to
    them the **damage glyph**: a top-down car outline SVG (doors, bonnet/boot, windows,
    4–6 tyres) where damaged parts glow red and burst tyres amber, from `damage`
    (DamageSummary). Caption: "2 windows smashed · 1 tyre burst" / "No visible damage" /
    "No damage data". `needsService` → amber callout "Needs service".
  - PERFORMANCE (from `stats`, absent for unknown models → hide the section): Top speed as
    a big number (km/h, or mph when distanceUnit = 'mi'), seats, and four rating bars
    (Speed, Acceleration, Braking, Traction 0–100).
  - UPGRADES (from `mods`): Engine, Brakes, Transmission, Suspension, Armour with level
    pips (0 = Stock) and Turbo on/off. `mods` null → "No upgrade data".
  - FINANCE (financed only): remaining balance, payment, Pips for payments made, next
    payment countdown / overdue state, Pay button (existing flow).
  - IMPOUND (impounded only): reason, fee, by, release countdown.
  - TRAILER (when `trailer`): "Trailer stored with it: <label>".
- **Action dock** pinned at the bottom of the showcase: primary teal "Drive out" with an
  `Enter` keycap (loading state while spawning); when it cannot be driven, show the reason
  inline and the useful alternative ("Set waypoint", "Recover · $250", "Pay $500 at the
  impound"). Secondary buttons with icon + label: Rename, Transfer, Share, Sell, Track.
  Everything that exists today must still work (all modals and flows in garage/modals).
- Spawner garages (job / public spawner): same two panes; rail lists spawner vehicles
  (label, plate template, price), showcase shows stage + performance + "Take out · $price".
- Impound app: same showroom pattern (rail of impounded vehicles; showcase with impound
  details: impounded by, reason, fee, release countdown; dock: "Pay $fee & drive out",
  staff "Release" action). ImpoundFormApp is unchanged.
- Empty states: no vehicles (garage icon, explain how to store one), filter empty ("No
  vehicles match" + clear filters), loading skeleton rows.

## 2. Admin location pages → "Map command" (src/apps/admin/shared/**, pages/{Garages,JobGarages,PrivateGarages,Impounds}Page.tsx, AdminApp.tsx, admin.css)

Map-first layout instead of table + side map. One component (LocationListPage) serves the
four location pages.

- **KPI strip** (4 tiles, numbers from `data.locationStats` + locations): e.g. Garages →
  Locations (11 of 12 enabled), Vehicles parked, Out right now, With interior. Impounds →
  Impounds, Vehicles held, Job-restricted, Default fee range. Job → Fleet / Spawner
  garages, Fleet vehicles parked, Out now, Jobs covered. Private → Locations, Owned copies
  (GroupInfo if available, else parked), Vehicles parked, For sale.
- **Directory (left, ≈ 420px):** toolbar (SearchInput, vehicle-type Segmented All / Car /
  Sea / Air, status Select All / Enabled / Disabled, sort Select Name / Most vehicles / Id),
  Import + Create (teal) buttons. Below: scrollable **location cards** (not a table): type
  icon tile (car / boat / plane), name + mono `#id`, chips (access: Everyone / Job · police /
  Gang · ballas / 3 players; mode: Quick menu / Interior / Both; capacity), a stats line
  (parked · out · impounded or held), and an enabled Toggle. Hover highlights its map pin;
  selected card has the teal edge. Disabled cards are dimmed.
- **Map (right, fills the rest):** `MapView` rebuilt on the three calibrated images in
  `web/public/maps/` (see §4): style Segmented top-left (Satellite / Dark / Atlas, remembered
  per viewer in localStorage inside try/catch), zoom +/−, "Fit all" and "Reset" top-right,
  wheel zoom around the cursor, drag to pan, legend bottom-left (Car / Sea / Air /
  Disabled), live cursor world coordinates bottom-right (mono "X 215.4 · Y −810.2").
  Pins: type-coloured markers with the vehicle-type icon; selected pin larger with a soft
  pulse ring and a name label; hover tooltip card (name, type, parked count). Click empty
  map → deselect; double-click a pin → edit.
- **Inspector** (slides over the bottom of the map when a location is selected): name, kind,
  enabled state, coordinates (mono + copy), points (open / store / spawn counts),
  restriction details, capacity, interior name, stats; actions Edit (teal), Teleport,
  Points (in-world manager, existing flow), Enable/Disable, Delete (red, ConfirmDialog).
  These replace the per-row icon buttons.
- The shell (AdminApp) may be polished but keeps the nav structure and page names.
- The location editor (`src/apps/admin/locations/**`) is owned by another task: do not
  edit it; open it exactly as today.

## 3. Admin vehicle detail → "Dossier" (src/apps/admin/vehicles/**, pages/PlayerVehiclesPage.tsx)

- **Hero band** (full width): vehicle image on a small stage (same turntable look as the
  showroom), name 22px + nickname, badges (state, Financed, Blocked, Impounded), the plate
  component, model in mono, class + "212 km/h" when stats exist. Right side: owner card
  (Avatar, name, identifier mono, "Change owner") and the action group: Block/Unblock,
  Impound/Release, Delete (red). Back button returns to the player view.
- **Pill tabs** under the hero (white active): Overview · Condition · Upgrades & paint ·
  Finance · History · Activity · Data.
  - Overview: "Attention" callouts first (needs service, finance overdue / next payment,
    impounded with release time, blocked); then a facts list (Garage, State, Last driven,
    Mileage, Vehicle type, Owner type, Job / gang, Nickname), condition at a glance (gauges
    + small damage glyph) and the 5 latest activity entries.
  - Condition: large top-down damage diagram (same SVG family as the showroom glyph, with
    labels: doors, bonnet, boot, windows, tyres), health numbers (engine / body / tank as
    /1000 and %), fuel, "Edit condition" (existing DetailsModal).
  - Upgrades & paint: performance upgrades with level pips; colours as real swatches
    (primary, secondary, pearlescent, wheel, interior, dashboard from GTA colour indexes via
    `props/catalog.ts`; neon / tyre smoke / xenon from RGB or index), wheels, window tint,
    plate style, livery, extras. "Edit modifications" opens the existing PropsEditor.
  - Finance: balance, payment, progress (Pips), interval, next payment / overdue, edit and
    remove (existing modals).
  - History: one timeline merging ownership and service records (filter chips All /
    Ownership / Service), with add/edit via the existing modals.
  - Activity: paginated `admin:vehicle:activity` log (VehicleActivity), newest first, each
    entry with an icon per event family, a readable sentence (e.g. "Taken out at Legion
    Square", "Stored at Pillbox", "Impounded at Davis · $500", unknown events: the event
    name), actor name, relative time + exact time tooltip, expandable details.
  - Data: read-only JSON of the props with a copy button and "Open editor".
- The player search and player vehicle list may be restyled to match (cards / rich rows)
  but keep every feature (search, pagination, assign vehicle, open detail).

## 4. Maps (`web/public/maps/{satellite,dark,atlas}.webp`, 1500×2000 each)

All three images share one frame. World → image fraction (0–1):

```
u = (0.16576 * x + 690.4) / 1500
v = (1348.4 - 0.164 * y) / 2000
```

(x, y = GTA world coordinates; u from the left edge, v from the top edge.) Inverse for the
cursor readout: `x = (u * 1500 - 690.4) / 0.16576`, `y = (1348.4 - v * 2000) / 0.164`.
The satellite and dark sources were low resolution and are upscaled, so keep the default
zoom moderate. Load them as `./maps/<name>.webp` (relative to index.html). Background
colours outside the image: satellite #143e6b, dark #394a51, atlas #1662ad.
