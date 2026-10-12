# NAYZEEE Tebex Template

A complete Tebex webstore template in the NAYZEEE UI style (Lexend, black layered surfaces, one accent, red Close pill). Same file set as the Carbide bundle, so it drops into Tebex the same way.

## Files

| File | What it is |
| --- | --- |
| `layout.html` | Shared shell: head/SEO, nav, cart drawer, gift modal, options modal, search, wishlist, footer, Tebex.js checkout, all shared CSS/JS |
| `index.html` | Homepage: hero + latest release card, stats, featured, categories, why us, Discord, reviews, payments, compatibility marquee, FAQ |
| `category.html` | Category page with filter + sort |
| `category/tiered.html` | Subscription tiers (Tebex "tiered" category) |
| `package.html` | Package page: gallery, buy box, add to cart, buy now, gift, wishlist, share, tabs, related |
| `checkout.html` | Basket page (`/checkout/basket`) |
| `username.html` | Login page (auto-redirects to Cfx.re when Tebex gives an external login URL) |
| `options.html` | Package options (server pick, variables, custom price, Discord link). Opens inside a modal |
| `cms-page.html` | Custom pages you create in Tebex |
| `module.featuredpackage.html` | The package card. Tebex Featured Package modules use it, and every grid in the store includes it |
| `module.payments.html` | Recent payments marquee (Tebex module) |
| `module.giftcardbalance.html` | Gift card balance checker (Tebex module) |
| `module.wishlist.twig` | Wishlist modal (saved in the visitor's browser) |
| `module.volume-discount.twig` | "Spend X more for Y% off" bar in the cart |
| `module.holiday.twig` | Seasonal themes, switch automatically each month |
| `scheme/EN.json` | Every setting shown in Tebex → Webstore → Templates → Settings |

## Install

1. Zip the contents of this folder (the files, not the folder itself) and upload it in Tebex → Webstore → Templates → Upload.
2. Upload your logo in Tebex → Webstore → Settings. The template picks it up automatically.
3. Open the template settings and fill tab 01 to 04. Everything has a default, so the store works before you touch anything.

## Settings worth knowing

- **Accent colours** (01): `accent-colour`, `accent-hi-colour`, `accent-lo-colour` and `accent-rgb`. Keep all four in sync when you change the accent.
- **Latest release card** (03): set `release-package-id` to a package ID and the hero shows a changelog card for it. Set `hero-image` instead to show an image.
- **Reviews, FAQ, Why us** (04): plain text fields. Leave a review text or FAQ question empty to hide it.
- **Seasonal themes** (05): `holiday-mode` Auto switches on the 1st of each month. Jan New Year, Feb Valentine's, Mar St. Patrick's, Apr Easter, May Spring, Jun Summer, Jul 4th of July, Aug Summer sale, Sep Autumn, Oct Halloween, Nov Thanksgiving, Dec Christmas. `holiday-recolor` Off keeps your accent and only adds particles and the badge.
- **Tiered category**: set `tier-featured-id` to highlight a plan.
- **Volume discount** (08): turn on, then set `volume-tier-1-at` (subtotal), `-pct` (percent) and `-code` (a coupon you created in Tebex). The bar in the cart applies the code with one click.

## Package description markers

Put these on their own lines at the end of a package description in Tebex. They are hidden on the page and turned into UI on the cards and the package page:

```
FRAMEWORKS: ESX, QBCore, Qbox          → logo chips (ESX, QBCore, QBox, ox, Standalone are recognised)
VERSION: 2.4.1                         → clean version tag on the card and next to the title
RATING: 4.9 (124)                      → stars + review count
TAGS: New, Lifetime updates            → badges ("Best seller" here also triggers the gold tag)
IMAGES: https://cdn/1.png, https://cdn/2.png   → gallery thumbnails
VIDEO: https://www.youtube.com/watch?v=XXXX    → Preview tab + gallery thumb
DEPENDENCIES: ox_lib https://github.com/overextended/ox_lib, ox_target   → Dependencies tab (URL optional)
CHANGELOG: v2.4.1 - New compass styles | v2.4.0 - Qbox support   → Changelog tab, entries separated by |
```

**Best seller tag.** Gold gradient pill with a flame icon, top-left of the card and in the package header. Set `bestseller-ids` in settings (comma-separated package IDs) or add `Best seller` to a package's TAGS.

## Seasonal themes and events

`holiday-mode` Auto switches on the 1st of each month. Every theme recolours the accent, adds a background scene (moon and fog for Halloween, string lights and snow caps for Christmas, fireworks for New Year and 4th of July, sun for summer) and particles, and shows a badge in the nav with a live countdown to the holiday.

The homepage gets an **event panel** with the countdown and a **daily gift calendar**. Fill `event-<theme>-days` with one entry per day, `Title;CODE;packageId`, separated by `|`. The last entry lands on the holiday, so 24 entries for Christmas gives you a 1 to 24 December advent calendar. Codes are coupons you create in Tebex. Visitors see locked doors for future days, today's gift with a copy button, and can reopen past days.

Preview any theme by adding `?holiday=christmas` (or newyear, valentine, stpatrick, easter, spring, summer, july4, summersale, autumn, halloween, thanksgiving) to the store URL.

## Also on the homepage

- `hero-video`: YouTube showcase in the hero instead of the release card.
- `trusted-logos` / `trusted-names`: a "Trusted by" row of servers.
- `update-1..6-*`: a Latest updates feed with version tags.

## Gifting

The package page has a Send as gift button. It opens a modal that POSTs the recipient username to Tebex's gift endpoint (`/checkout/packages/add/{id}/gift`). Carbide fetched `…/single/gift?username=` with a GET, which does not add the gift to the basket. If a package has gifting disabled in Tebex, the button is hidden. Gifted items show "Gift to NAME" in the cart.

## How the cart works

- Add to cart loads Tebex's add route in a hidden iframe. If the package needs options (server, variables, Discord), the options page appears in a modal. Otherwise the drawer refreshes and opens.
- Not signed in: the visitor goes to `/login` (Cfx.re), then the add is replayed automatically.
- Checkout opens Tebex.js hosted checkout, with `/checkout/basket` as the fallback.
- Coupons, gift cards and creator codes post to the standard Tebex routes.

## Demo

`../nayzeee-store/index.html` is a static single-file demo of the same design with placeholder products. The template folder is the real thing.
