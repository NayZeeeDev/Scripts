# Requests from the UI originality pass — group `checkin` (apps checkin, bed, pharmacy + the waiting-area board)

Everything below is outside the files this pass may edit. The apps already work around each point.

## 1. Pharmacy server: insurance member number prefix `NZ-` (server/modules/pharmacy_billing.lua:231)

The serial generator returns `'NZ-' .. … .. '-' .. …`. The number is printed on the insurance member
card (NUI "Cover" tab) and in the `insurance_card` item metadata — a card is a physical object, and
`NZ-` reads as the product name. Please switch the prefix to a generic one, e.g. `HC-` (health
cover), or make it `Config.Pharmacy.insurance.serialPrefix` with `'HC'` as default. Existing serials
can stay as they are. The NUI preview already uses `HC-7KQ4-H2MX`.

## 2. Core `NZA.ui.FlipClock`: optional static separators

The odometer blinks every non-digit (`.odo .c { animation: nza-blink }`). That is right for clocks,
but the pharmacy tray shows its total (`$1,250`) with the same rolling counter, where `$` and `,`
must not blink. The app overrides it locally (`.ph-tot .odo .c { animation: none }`). A
`FlipClock(host, { blink: false })` option (adds a class that stops the separator blink) would let
other apps roll money / counts without their own override.

## 3. Lead (optional): wording in `Config.Props` / prop comments

`client/modules/checkin_tv.lua` replaces the texture of `Config.Props.tv_board`. The board page itself
now carries no product name or logo (generic cross glyph, department name only). If the
`tv_board` model's own bezel texture still prints the product name, the props owner should swap it
for a generic model code (e.g. "WD-55") so the board is clean when the DUI is not drawn.
