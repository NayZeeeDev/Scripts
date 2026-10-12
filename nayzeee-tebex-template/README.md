# NAYZEEE Tebex Template

A complete Tebex webstore template in the NAYZEEE UI style (Lexend, black layered surfaces, one accent, red Close pill). Same file set as the Carbide bundle, so it drops into Tebex the same way. The NayZeee ghost logo and lightning banner are built in.

## Files

| File | What it is |
| --- | --- |
| `layout.html` | Shared shell: head/SEO, nav, cart drawer, gift modal, options modal, search, wishlist, review modal, footer, Tebex.js checkout, all shared CSS/JS, framework logos |
| `index.html` | Homepage: hero + latest release card, stats, sale countdown, holiday event, trusted-by, featured, bundle builder, categories, why us, updates feed, Discord, reviews, payments, compatibility marquee, FAQ |
| `category.html` | Category page with filter + sort |
| `category/tiered.html` | Subscription page: Monthly / Quarterly / Yearly switch, live script count and total value, one plan card, feature tiles, included scripts, FAQ |
| `package.html` | Package page: gallery, buy box, logo chips, version, rating, add to cart, buy now, gift, wishlist, share, review, tabs (Description, Preview, Dependencies, Changelog, Terms), related, sticky buy bar |
| `checkout.html` | Basket page (`/checkout/basket`) |
| `username.html` | Login page (auto-redirects to Cfx.re when Tebex gives an external login URL) |
| `options.html` | Package options (server pick, variables, custom price, Discord link). Opens inside a modal |
| `cms-page.html` | Custom pages you create in Tebex |
| `module.featuredpackage.html` | The package card. Tebex Featured Package modules use it, and every grid in the store includes it |
| `module.payments.html` | Recent payments marquee (Tebex module), also feeds the purchase toasts |
| `module.giftcardbalance.html` | Gift card balance checker (Tebex module) |
| `module.wishlist.twig` | Wishlist modal (saved in the visitor's browser) |
| `module.volume-discount.twig` | "Spend X more for Y% off" bar in the cart |
| `module.holiday.twig` | Seasonal themes, scenes, countdowns and daily gift events |
| `module.sale.twig` | Store-wide discount banner with countdown |
| `module.bundle.twig` | Build-your-own-bundle section |
| `module.reviews.twig` | Write-a-review modal that posts to a Discord webhook |
| `module.heartbeat.twig` | Live usage cards powered by Heartbeat (servers / players per script, store totals on the homepage) |
| `module.cursor.twig` | Custom cursor: the feather arrow, and the Deku character over links and buttons, recoloured to the accent. Mouse devices only |
| `scheme/EN.json` `DE.json` `FR.json` `NL.json` | Every setting shown in Tebex → Webstore → Templates → Settings, in four languages |

## Install

1. Zip the contents of this folder (the files, not the folder itself) and upload it in Tebex → Webstore → Templates → Upload.
2. Open the template settings and fill tabs 01 to 04. Everything has a default, so the store works before you touch anything.
3. Logo: the ghost is built in (`logo-mode` Ghost) and floats with a teal glow. The name next to it reads "NayZeee Development" (`brand-name` + `brand-sub`). Switch to Logo to use the one uploaded in Tebex, or Mark for the chamfer mark.

## Settings worth knowing

- **Accent colours** (01): `accent-colour`, `accent-hi-colour`, `accent-lo-colour` and `accent-rgb`. Keep all four in sync when you change the accent.
- **Hero** (03): `hero-ghost-toggle` hides the floating ghost. `release-package-id` shows a full-thumbnail "Latest release" card. `hero-video` shows a YouTube showcase instead. `hero-bg` replaces the built-in banner behind the hero, `hero-bg-opacity` tunes it.
- **Sale countdown** (03): `sale-toggle` Show, then `sale-end`, `sale-code`, `sale-text`. Optional `sale-start` counts down to the start first.
- **Bundle builder** (04): set `bundle-tier-1-count` / `-pct` / `-code` (and tiers 2, 3). Create each code as a Tebex coupon with a minimum package count. Exclude your subscription and bundle categories with `bundle-exclude-cats`. Scripts show with their full-width thumbnails.
- **Reviews** (04): paste a Discord webhook into `review-webhook`. Visitors get a Write a review button on the homepage and every package page. Reviews land in your channel; publish the good ones by pasting them into `review-1..3-*`.
- **Updates feed, trusted-by, Discord live count** (04 / 02): `update-1..6-*`, `trusted-logos` or `trusted-names`, `discord-guild-id` (enable the widget in Discord).
- **Seasonal themes** (05): `holiday-mode` Auto switches on the 1st of each month. Each theme has its own scene, particles, nav countdown and homepage event panel. Fill `event-<theme>-days` for the daily gift calendar. Preview with `?holiday=christmas` in the URL, `?holiday=off` to preview without a theme.
- **Tags** (06): `bestseller-ids` and `new-ids` are comma-separated package IDs. Descriptions can also carry `TAGS: Best seller` or `TAGS: New`.
- **Subscription page** (06): create three packages in your tiered category named Monthly, Quarterly and Yearly (or set `tier-monthly-id` / `tier-quarterly-id` / `tier-yearly-id`). The switch shows the percent saved vs monthly automatically. The script count and total value are counted from the store, so they grow as you release scripts. Put your Bundles category ID in `tier-exclude-cats` so bundles are not counted. `tier-perk-1..4` is the checklist, `tier-feat-1..4-*` the four feature tiles, `tier-faq-1..4-*` the FAQ.
- **Volume discount** (08): turn on, then `volume-tier-1-at`, `-pct`, `-code`.
- **Cursor** (01): `cursor-toggle` Off restores the normal cursor. `cursor-url` / `cursor-pointer-url` swap in your own 32px PNGs. The built-in ones are the 32px frames from your .cur files with their original hotspots.
- **Footer credit** (10): `footer-built` + `footer-built-name` (default "Built by NayZeee Dev").

## Package description markers

Put these on their own lines at the end of a package description in Tebex. They are hidden on the page and turned into UI on the cards and the package page:

```
FRAMEWORKS: ESX, QBCore, Qbox          → logo chips (ESX, QBCore, QBox, ox, Standalone are recognised)
VERSION: 2.4.1                         → version tag on the card and next to the title
RATING: 4.9 (124)                      → stars + review count
TAGS: New, Lifetime updates            → badges (New = teal NEW pill, Best seller = gold pill)
IMAGES: https://cdn/1.png, https://cdn/2.png   → gallery thumbnails
VIDEO: https://www.youtube.com/watch?v=XXXX    → Preview tab + gallery thumb
DEPENDENCIES: ox_lib https://github.com/overextended/ox_lib, ox_target   → Dependencies tab (URL optional)
CHANGELOG: v2.4.1 - New compass styles | v2.4.0 - Qbox support   → Changelog tab, entries separated by |
```

## Live usage (Heartbeat)

Heartbeat (heartbeat.re) crawls FiveM servers and their resource lists, so **nothing has to be added to your scripts**. A script is counted by its resource folder name.

1. Paste your key into `heartbeat-key` (tab 06 · Live usage).
2. Add `HEARTBEAT: nayzeee-inventorylogs` (the resource name) to each package description, or set `heartbeat-resource-<packageId>`.
3. The package page shows "Servers using this script / Players enjoying this script". The homepage shows totals for every resource starting with `heartbeat-prefix` (default `nayzeee`).

Numbers are fetched by the visitor's browser (Heartbeat allows CORS), use `?period=current` for live figures, and are cached for `heartbeat-refresh` seconds (default 5 min) to stay inside the free key's 60 requests/minute. Add `?hb=demo` to any URL to preview the cards with sample numbers. Rate-limit or network errors simply hide the card.

## Gifting

The package page has a Send as gift button. It opens a modal that POSTs the recipient username to Tebex's gift endpoint (`/checkout/packages/add/{id}/gift`). If a package has gifting disabled in Tebex, the button is hidden. Gifted items show "Gift to NAME" in the cart.

## How the cart works

- Add to cart loads Tebex's add route in a hidden iframe. If the package needs options (server, variables, Discord), the options page appears in a modal. Otherwise the drawer refreshes and opens.
- Not signed in: the visitor goes to `/login` (Cfx.re), then the add is replayed automatically. The bundle builder remembers the selection the same way.
- Checkout opens Tebex.js hosted checkout, with `/checkout/basket` as the fallback.
- Coupons, gift cards and creator codes post to the standard Tebex routes.

## Languages

`scheme/DE.json`, `FR.json` and `NL.json` translate the settings dashboard: tab names, the quick-start note and the descriptions of the settings you touch most. Field names stay English because they match the keys. Descriptions without a translation show the English text.

## Docs site

`../nayzeee-docs/index.html` is the docs site (docs.nayzeeedev.com). It is a single self-contained file: scripts, pages and images live in the `SCRIPTS` array inside it.
