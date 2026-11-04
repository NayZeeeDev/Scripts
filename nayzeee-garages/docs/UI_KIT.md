# nayzeee-garages — NUI design system & UI kit contract

The interface uses the **NayZeee UI** style (reference files: `docs/design/nayzeee-ui-v5.html`
and `docs/design/nayzeee-ui-design.html` — read both). The owner chose a **mix**:

- **From v5:** Lexend font, the window frame with the **chamfered bottom-right corner**
  (clip-path), subtle film grain overlay, teal rail on the title bar, the teal chamfer
  **brand mark**, tags/badges, tables, empty states, skeleton loaders, v5 nav item
  (teal wash + glowing left bar).
- **From the design sheet:** solid-teal toggles (white knob → dark knob when on),
  pill segmented controls with a white active segment, chips, **uppercase section
  headings** (11px, 700, letter-spacing .12em, ink-3), option rows (label + grey
  description left, control right), style cards, sliders, HUD panels (`--hud`
  translucent, radius 12) for in-world widgets.
- **Same in both:** colours, surfaces, buttons (teal primary / outline / red destructive),
  and the **red "Close" pill** at the far right of every window header.

Hard rules (FiveM CEF):
- NO `backdrop-filter`, NO `color-mix()`, NO `:has()`, NO CSS nesting. Use rgba + gradients.
- Motion: 130ms `cubic-bezier(.4,0,.2,1)` for hovers; 200–250ms for panels sliding/fading.
  Respect `prefers-reduced-motion`.
- Everything must look right over a bright game scene: windows are opaque (`--base`),
  HUD widgets use `--hud` (rgba(12,13,16,.78)).
- Never hardcode the teal: use `var(--teal)` family (admins can change the accent).
- Tabular numbers everywhere (`font-variant-numeric: tabular-nums`).
- Text must never overflow its box: ellipsis on names, wrap on descriptions.
- All UI copy goes through `t('English text')` from `@/lib/i18n`.

This is an **original** design. Never copy another product's look, names or branding. The
current screens (garage Showroom, admin Map command and Dossier, Key ring, Locksmith, Contract)
are the reference for new work; the old reference screenshots in §5 are historical.

Notifications are **not** a kit component. `<Toasts />` (`src/components/Toasts.tsx`) is
mounted once in `App.tsx` and only draws what Lua sends with the `notify` message, which
happens only while one of our windows holds NUI focus (FiveM then draws our page above every
other resource's NUI, so the configured notify resource would be hidden behind the window).
Everything else is shown by the notify integration (`bridge/client/notify.lua`). Apps raise a
notification with `toast()` from `@/lib/store`, never by rendering one themselves.

---------------------------------------------------------------------------------------

## 1. Tokens (`src/styles/tokens.css`, owned by the UI kit agent)

```
--void #000000  --base #08090a  --side #050607  --panel #0e1011  --raise #15181a
--raise-2 #1c2023  --inset #0b0c0d  --hud rgba(12,13,16,.78)
--line rgba(255,255,255,.10)  --line-soft rgba(255,255,255,.06)
--line-hair rgba(255,255,255,.035)  --lift rgba(255,255,255,.055)
--white #ffffff  --ink #f2f4f5  --ink-2 #9ea5aa  --ink-3 #63696d
--teal #08afa2  --teal-hi #0fd4c4  --teal-lo #067d74  --teal-rgb 8,175,162
--teal-wash rgba(8,175,162,.11)  --teal-edge rgba(8,175,162,.34)  --on-teal #00201d
--red #e5484d  --red-lo #b8262b  --red-wash rgba(229,72,77,.11)  --red-edge rgba(229,72,77,.34)
--amber #e5a50a  --amber-wash rgba(229,165,10,.12)  --amber-edge rgba(229,165,10,.36)
--blue #58a6ff
--r-xs 4px  --r-sm 6px  --r-md 10px  --r-lg 14px  --r-pill 999px
--sh-1 0 1px 2px rgba(0,0,0,.6)
--sh-2 0 2px 6px rgba(0,0,0,.5), 0 10px 28px rgba(0,0,0,.45)
--sh-3 0 10px 24px rgba(0,0,0,.6), 0 40px 80px rgba(0,0,0,.7)
--fast 130ms cubic-bezier(.4,0,.2,1)   --slide 220ms cubic-bezier(.4,0,.2,1)
--font 'Lexend', system-ui, sans-serif   --mono 'JetBrains Mono', ui-monospace, monospace
--chamfer 22px   (window bottom-right cut)
```
(`lib/theme.ts` overwrites the `--teal*` + `--on-teal` vars at runtime from settings.)

Type scale: window title 15/600 white · page title 20/600 (-.02em) · section heading
11/700 uppercase .12em ink-3 · option label 13/600 · body 12/400 · helper 11/300 ink-3 ·
big numbers 20–27/600 (-.03em) · plates 9.5–10.5 mono 700 uppercase.

---------------------------------------------------------------------------------------

## 2. Component API (`src/components/ui`, import from `@/components/ui`)

The UI kit agent implements **exactly** these exports. App agents only use these (plus
local components inside their own folders). Every component accepts an optional
`className`. CSS class prefix: `nz-` (BEM-ish: `nz-btn`, `nz-btn--teal`).

```tsx
// Layout
<Window title icon? subtitle? badge?: ReactNode headerExtra?: ReactNode onClose? width?: number|string
        height?: number|string footer?: ReactNode watermark?: boolean className? bodyClassName?>
  children
</Window>
//  Centered (unless className positions it) opaque window: v5 frame + chamfer + grain,
//  header = brand mark + title (+ subtitle/badge) … headerExtra … red <PillClose> (when onClose).
//  Body scrolls. footer renders in a status-bar style strip (inset bg, keycaps allowed).
<Panel title? subtitle? actions? padded?=true className?>children</Panel>     // card surface (--panel)
<Section title? description? actions?>children</Section>                         // uppercase heading block
<OptionRow label description? control: ReactNode />                             // label left, control right
<Divider />
<Modal open title icon? onClose width?=420 footer?: ReactNode children />
//  Dialog over the current window: dims the window (rgba(0,0,0,.55)), --panel surface,
//  radius 12, X icon button top-right, registers useEscape → onClose. Renders via portal
//  into #root so it stacks above windows.
<ConfirmDialog open title message confirmLabel tone?: 'teal'|'red' icon? onConfirm onCancel busy? />

// Buttons
<Button variant?: 'teal'|'white'|'line'|'red'|'ghost' (default 'line') size?: 'sm'|'md'|'lg'
        icon?: IconName iconRight?: IconName badge?: ReactNode loading? disabled? full?
        type? onClick? title?>label</Button>
<IconButton icon: IconName label: string (tooltip + aria) variant?: 'ghost'|'line'|'teal'|'red'
            size?: 'sm'|'md' active? disabled? onClick? />
<PillClose onClick label?='Close' />            // the red pill
<Kbd>E</Kbd>                                     // keycap

// Inputs (all controlled)
<Field label? hint? error? required? children /> // label above control
<Input value onChange(value: string) placeholder? icon?: IconName mono? suffix?: ReactNode
       maxLength? disabled? autoFocus? onEnter?() type?='text' />
<NumberInput value: number onChange(n: number) min? max? step? suffix? disabled? />
<SearchInput value onChange placeholder? onEnter? shortcut?: string (shows keycap, e.g. 'Enter') autoFocus? />
<Select<T extends string|number> value: T|null onChange(v: T) options: { value: T; label: string;
        hint?: string; icon?: IconName; disabled?: boolean }[] placeholder? icon? disabled?
        size?: 'sm'|'md' searchable? />      // custom dropdown (no native <select>)
<MultiSelect<T> value: T[] onChange options placeholder? />
<Toggle checked onChange(b) disabled? label? description? />   // design-sheet toggle
<Segmented<T> value onChange options: { value: T; label: string; icon?: IconName }[] size? />
<Tabs<T> value onChange items: { value: T; label: string; icon?: IconName; count?: number }[]
        variant?: 'pill'|'underline' />
<Slider value onChange min max step? suffix? />
<ColorSwatches value: string onChange colors: string[] />   // + hex input

// Display
<Chip active? onClick? icon? count?: number>label</Chip>        // filter chip
<Badge tone?: 'teal'|'amber'|'red'|'neutral'|'white'|'blue' icon? size?: 'sm'|'md'>text</Badge>
<PlateTag plate />                                               // mono plate tag
<Stat label icon value: number suffix?='%' tone?: 'auto'|'teal'|'amber'|'red' extra?: ReactNode />
//  fuel/engine/body card: uppercase label + icon, big value + small suffix, bar under it.
//  tone 'auto': teal ≥ 50, amber ≥ 25, red below.
<Bar value max?=100 tone? height?=3 />                           // thin progress bar
<Ring value size?=34 stroke?=3 tone? children? />                // circular gauge
<Pips total done tone? />                                        // segmented progress (finance)
<Meter label icon? used total />                                 // "Your spaces 6/12" capacity
<Table<Row> columns: { key: string; header: ReactNode; width?: number|string; align?:
       'left'|'right'|'center'; render?: (row: Row) => ReactNode }[] rows: Row[] rowKey(row) =>
       string|number onRowClick?(row) empty?: ReactNode loading? dense? />
<Pagination page pageCount onChange total? pageSize? />          // "1–10 of 34 items"
<EmptyState icon title description? action? compact? />
<Spinner size? />  <Skeleton width? height? radius? />  <SkeletonRows count? />
<Tooltip content: ReactNode side?: 'top'|'bottom'|'left'|'right'>trigger</Tooltip>
<InfoDot text />                                                  // (i) with tooltip
<Menu items: { label: string; icon?: IconName; onSelect(): void; danger?: boolean;
       disabled?: boolean; hint?: string }[] trigger?: ReactNode align?: 'left'|'right'
       side?: 'top'|'bottom' label? />  // "⋯" menu; side 'top' opens above the trigger
                                       // (action bars at the bottom of a window)
<Avatar name size? />                                             // initials tile
<BrandMark size?: 'sm'|'md'|'lg' />                               // teal chamfer mark
<KeyHint keys: string[] label />                                  // keycaps + label
<VehicleImage image: string|null vehicleType: VehicleType alt? className? />
//  (in src/components/VehicleImage.tsx, re-exported) tries settings.imageUrl, then
//  ./vehicles/<model>.png, then an SVG silhouette per vehicle type. Lazy, object-fit contain.

// Icons (src/components/icons.tsx, re-exported)
<Icon name: IconName size?=16 strokeWidth?=1.6 className? />
type IconName =
 'car'|'boat'|'plane'|'heli'|'bike'|'truck'|'trailer'|'garage'|'search'|'list'|'grid'|'walk'|
 'close'|'check'|'checkCircle'|'star'|'starFilled'|'wrench'|'pin'|'clock'|'fuel'|'engine'|
 'shield'|'transfer'|'tag'|'users'|'user'|'userPlus'|'more'|'chevronDown'|'chevronUp'|
 'chevronLeft'|'chevronRight'|'arrowRight'|'arrowLeft'|'plus'|'minus'|'edit'|'trash'|'ban'|
 'lock'|'unlock'|'cog'|'key'|'camera'|'door'|'building'|'impound'|'briefcase'|'import'|'sort'|
 'info'|'warning'|'money'|'cart'|'palette'|'gauge'|'spray'|'wheel'|'sparkle'|'bulb'|'sliders'|
 'history'|'crown'|'eye'|'eyeOff'|'refresh'|'map'|'layers'|'route'|'link'|'copy'|'code'|
 'calendar'|'save'|'logout'|'sidebar'|'filter'|'hash'|'percent'|'receipt'|'parking'
```

Utilities exported from `@/components/ui` as well: `cx` (clsx re-export).

Global helpers already provided by the foundation (do not rewrite):
- `@/lib/nui`: `fetchNui(name, data)`, `request(name, data, { toastError })` (a failed request
  raises an error notification through `toast()`; `toastError: false` turns it off),
  `mockNui(name, handler)`, `isBrowser`.
- `@/lib/store`: `useApp(app)` → `{ open, data, close, update, replace }`, `useUi`,
  `useSettings()`, `toast({ type, message, title? })`, `closeApp(app)`.
  `toast()` always posts to Lua's `notify` callback (message ≤ 300 characters, title ≤ 60) and
  Lua decides where it is drawn: inside the interface (`<Toasts />`) while a window holds
  focus, otherwise the configured notify integration. In the browser dev harness it draws the
  toast locally and logs it with `console.info`.
- `@/lib/escape`: `useEscape(handler, active)` (Escape key stack).
- `@/lib/i18n`: `t(text, vars)`.
- `@/lib/format`: `money`, `distance`, `distanceValue`, `toKm`, `percent`, `date`,
  `dateTime`, `hoursLabel`, `secondsUntil`, `vehicleImageUrl`, `localVehicleImage`.
- `@/lib/types`: every data type.

**Escape behaviour:** every app root calls `useEscape(() => close(), open)`. Modals call
`useEscape(onClose, open)` (built into `<Modal>`). The most recent handler wins.

---------------------------------------------------------------------------------------

## 3. Ownership (who writes which files)

| Agent | Files |
|-------|-------|
| UI kit (W1) | `src/styles/*`, `src/components/**`, `src/apps/hud/*` (Prompt, Hint), `src/dev/mocks/hud.ts`, `src/dev/KitGallery.tsx` |
| Garage (W2) | `src/apps/garage/**`, `src/apps/impound/**`, `src/apps/forsale/**`, `src/dev/mocks/{garage,impound,forsale}.ts` |
| World (W3) | `src/apps/interior/**` (InteriorHud, InteriorPanelApp), `src/apps/setup/**`, `src/apps/creator/**`, `src/dev/mocks/{interior,setup,creator}.ts` |
| Admin A (W4) | `src/apps/admin/AdminApp.tsx`, `src/apps/admin/admin.css`, `src/apps/admin/shared/**`, `src/apps/admin/pages/{GaragesPage,JobGaragesPage,PrivateGaragesPage,ImpoundsPage}.tsx`, `src/apps/admin/locations/**`, `src/dev/mocks/admin.ts` |
| Admin B (W5) | `src/apps/admin/pages/{InteriorsPage,PlayerVehiclesPage,SettingsPage}.tsx`, `src/apps/admin/vehicles/**` (incl. the vehicle Dossier, `vehicles/dossier/**`), `src/apps/admin/interiors/**`, `src/apps/admin/settings/**`, `src/dev/mocks/adminVehicles.ts` |
| Key ring | `src/apps/keys/**` (`KeysApp`, KeyRail, KeyShow, ShareModal, glyphs, `model.ts`, `keys.css`), `src/dev/mocks/keys.ts` |
| Locksmith | `src/apps/locksmith/**` (`LocksmithApp`, `locksmith.css`), `src/dev/mocks/locksmith.ts` |
| Contract | `src/apps/contract/**` (`ContractApp`, ContractDocument, `signature.tsx` pad, `contract.css`), `src/dev/mocks/contract.ts` |

Shared pieces between apps: the garage owner's Showroom parts live in `src/apps/garage/showroom/`
(Rail, Stage, SlotStrip, blocks, DamageGlyph, keyboard `keys.ts`) and are also imported by the
impound app; the admin Dossier imports `glyphShape` / `GlyphShape` from
`src/apps/garage/showroom/DamageGlyph.tsx` (keep those exports stable). The Key ring and
Locksmith follow the Showroom's two-pane layout. Admin location pages ("Map command") share
`src/apps/admin/shared/**` (map, inspector, command CSS).

Fixed entry exports (imported by `src/App.tsx` / `AdminApp.tsx` — keep names & paths):
`GarageApp`, `ImpoundApp`, `ImpoundFormApp`, `ForSaleApp`, `SetupApp`, `CreatorApp`,
`InteriorHud`, `InteriorPanelApp`, `AdminApp`, `KeysApp`, `LocksmithApp`, `ContractApp`,
`Prompt`, `Hint`, and admin pages `GaragesPage`, `JobGaragesPage`, `PrivateGaragesPage`,
`ImpoundsPage`, `InteriorsPage`, `PlayerVehiclesPage`, `SettingsPage` (each
`(props: AdminPageProps)`). `App.tsx` also mounts `Toasts` (`src/components/Toasts.tsx`, owned
by the UI kit agent but not exported from `@/components/ui`).

Each app owns a CSS file next to it (e.g. `src/apps/garage/garage.css`) imported by its
root component. Prefix classes with the app (`nz-garage__…`). Never style another
agent's classes.

---------------------------------------------------------------------------------------

## 4. Dev harness & self-checking

- `npm run dev` (port 5173) or `npm run build && npm run preview` (port 4173).
- Mock scenarios: `registerMock({ id, group, label, messages })` from `@/dev/registry`, and
  `mockNui(name, handler)` from `@/lib/nui` to answer callbacks. Open with `?mock=<id>`;
  add `&panel=0` to hide the dev panel for screenshots. Kit gallery: `?kit=1`.
  Scenarios of the newer screens: `hud-toasts`, `hud-toasts-stack`, `hud-toasts-window`
  (in-interface notifications), `keys-*` (physical, virtual, temp, tracking, range, share,
  towing, hotwired, backalley, names, empty), `locksmith-*` (legal, illegal, materials, broke,
  virtual, unregistered, shared, empty), `contract-*` (draft, draft-alone, draft-sent,
  draft-declined, draft-expired, review, review-broke, review-topup, review-late,
  review-expired, review-withdrawn, view, view-unverified), `admin-vehicles-bike` / `-boat` /
  `-heli` (dossier condition outlines).
- Screenshot with the pre-installed Playwright (`require('playwright')`, chromium):
  viewport 1920×1080 (the in-game size) and also 1280×720 (small screens must still fit).
  Look at your screenshots and fix what looks off.
- `npx tsc --noEmit` must report **zero errors in your files**. While other agents are
  still writing, errors in *their* files may appear — ignore those, fix yours.

---------------------------------------------------------------------------------------

## 5. Reference screenshots (historical — do not use for these screens)

> **Historical.** These screenshots were the first brief, before the redesign. The garage,
> impound, admin location pages, vehicle manager, key ring, locksmith and contract screens
> have since been rebuilt (Showroom, Map command, Dossier). Do not use the list below to design
> or check those screens; use the current screens and the mock scenarios (`?mock=<id>`)
> instead. It only remains as a record of which information each screen was asked to show.

All under `/root/.claude/uploads/939d8efe-994e-5a21-be29-bbf4e311b951/`:

Garage / player screens
- `dd56bc91-image.png` grid view + expanded vehicle panel (fuel/engine/body, location chip, Out badge, needs-service, favourites, Transfer/Sell/Share)
- `a587829c-image.png` list view + finance block (recurring payment, balance, payments pips, next payment) + rename modal
- `ff5bb11a-image.png` transfer modal (Garage/Player switch, destination with spaces left, fee button)
- `31caa6b4-image.png` air hangar (Out badge, loading state on Drive)
- `69d38a7c-image.png` boat marina
- `2a779fd5-image.png` private garage menu (Private badge, Spaces 4/8, Manage, Go inside)
- `a606c789-image.png` manage members modal (choose player, role, You/Owner, rule text)
- `66a8863f-image.png` garage-for-sale card (copies available, storage, parking, interior, tour, buy)
- `a0d9e2ca-image.png` confirm purchase
- `4fb92372-image.png` impound menu (impounded by, reason, fee, available time, Drive $fee)
- `5a1cbf0a-image.png` impound vehicle form
- `d21a466a-image.png` job garage spawner list
- `0967ce76-image.png`, `4fdb4d7e-image.png` vehicle setup (liveries / extras)
- `b24043a7-image.png` interior stats HUD (top right)

Creator / admin
- `6f0b74ef-image.png` admin interiors table
- `b015dd27-image.png` create interior modal (IPL profile, coordinates, use current position)
- `55f65c2b-image.png` creator details tab · `19682116-image.png` cutscene tab · `f3fb2df0-image.png` vehicle slot placement + key hint
- `ccfc8094-image.png` admin garages table + map with pins
- `42b236e5-image.png` settings (tabs, search, save)
- `d1305686-image.png`, `30e23f18-image.png` edit location form
- `d075370b-image.png` job & gang garages table · `efe86bc4-image.png` create job garage form
- `6ac4fe39-image.png` create impound form
- `1d2ccec9-image.png`, `b946c5db-image.png`, `8ee9a40b-image.png` player vehicles search/table
- `814dca70-image.png` vehicle detail dashboard
- `fba77daf-image.png`, `c1817562-image.png`, `c2106320-image.png` edit vehicle props (categories, performance, cosmetics)
- `4e12a947-image.png` service history editor · `4906b7ae-image.png` assign vehicle

Where those screens are plain, do better: clearer hierarchy, better empty/loading/error
states, keyboard support, sensible defaults, no dead ends.
