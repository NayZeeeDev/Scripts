# NayZeee Store

FiveM webstore demo built in the NAYZEEE UI style (Lexend, black surfaces, one teal accent, red Close pill).

Open `index.html` in a browser. Everything is in that one file.

## Pages
- Home: hero + live server card, stats, featured, categories, why us, Discord, reviews, payments, stack marquee
- Store / category: filter, sort, grid, and a Compare layout for membership tiers
- Package: gallery, price, quantity, gift to another player, wishlist, tabs, related
- Cart drawer: quantities, coupon, totals
- Checkout: items, Cfx.re sign in, coupon + creator code, payment method, terms, pay
- Wishlist, Support / FAQ, legal pages

Demo coupon codes: `SEASON4` (20% off memberships), `WELCOME5` ($5 off). Creator codes: `NAYZEEE`, `KANE`, `MAYA`.
Press `/` anywhere to search.

## Hooking up Tebex
1. Tebex panel → Webstore → Headless API → copy the **public token**.
2. In `index.html` set `const TEBEX_TOKEN = 'your-token';`
3. Categories and packages then load from Tebex, the basket is created on Tebex, and Pay redirects to the hosted Tebex checkout (with Cfx.re login).

Edit `STORE` at the top of the script for the server name, connect command, Discord link, reviews and FAQ.
