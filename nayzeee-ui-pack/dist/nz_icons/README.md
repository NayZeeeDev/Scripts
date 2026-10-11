# nz_icons · NAYZEEE icons v1.0.0

211 original NAYZEEE icons (plus 34 aliases) for FiveM NUI pages. Chamfered corners, a 1.75 stroke and an optional teal accent.
Open `cheatsheet/index.html` in a browser to search every icon and click to copy it.

## Two ways to use it

**A. Bundle the files inside each script (best for scripts you sell).**
Copy the files you need into the script's `html/` folder and list them in that script's `fxmanifest.lua`:

```lua
files {
  'html/index.html',
  'html/nz-icons.css',
}
```
```html
<link rel="stylesheet" href="nz-icons.css">
```
Customers then don't need to install anything extra.

**B. Run it as a shared resource (handy on your own server).**
Drop the `nz_icons` folder into `resources/`, add `ensure nz_icons` to server.cfg (before the scripts that use it), then point any NUI page at it:

```html
<link rel="stylesheet" href="nui://nz_icons/nz-icons.css">
```

## Writing icons

| File | Use it like |
|------|-------------|
| `nz-icons.css` | `<i class="nzi nzi-car"></i>` takes the text colour and size. Sizes: `nzi-xs` `nzi-sm` `nzi-lg` `nzi-xl` `nzi-2x` `nzi-3x`. Extras: `nzi-fw` (fixed width), `nzi-spin` |
| `nz-icons-fa.css` | Load **after** Font Awesome. Existing `<i class="fa-solid fa-car"></i>` markup shows the NAYZEEE icon. Covers 344 Font Awesome names; any other name still comes from Font Awesome |
| `nz-icons.js` | `<i data-nzi="car"></i>` becomes an inline SVG, or `el.innerHTML = NZI.svg('car')`. Supports the teal accent |
| `nz-icons.svg` | Sprite: `<svg class="nzi-svg"><use href="nz-icons.svg#car"/></svg>` (needs `nz-icons.css` or `nz-icons.js` for the `nzi-svg` sizing). Browsers block this when you open a page straight from disk; it works in game |
| `svg/<name>.svg` | Plain files, e.g. `<img src="svg/car.svg">` (draws in black; recolour with CSS `filter` or use the options above) |

**Teal accent (duotone):** set `--nzi-accent: #08afa2` on a parent element and each icon's accent detail turns teal. Works with `nz-icons.js`, the sprite and the SVG files. The `nzi` CSS classes are single-colour.

**Colour and size** come from the surrounding text: `<i class="nzi nzi-heart" style="color:#e5484d;font-size:24px"></i>`.

## Icon names

arrow-up · arrow-down · arrow-l · arrow-r · arrow-ur · chev-u · chev-d · chev-l · chev-r · x · check · plus · minus · search · filter · funnel · sliders · menu · more · more-v · grid · list · edit · trash · copy · save · download · upload · lock · unlock · eye · eye-off · bell · info · alert · error · help · success · home · refresh · rot-l · rot-r · history · external · link · login · logout · power · clock · timer · calendar · star · cog · swap · sortd · sortu · play · pause · target · flag · ruler · percent · keyboard · mouse · user · users · user-plus · user-x · person · id · badge · crown · face · smile · hand · wave · walk · sit · dance · heart · pulse · shield · shield-check · food · drop · bolt · brain · thermo · wind · mic · mic-off · volume · mute · seat · signal · wifi · battery · gauge · car · taxi · truck · motorbike · bicycle · boat · heli · plane · fuel · key · engine · wheel · wrench · garage · light · door · window · hood · trunk · nav · route · siren · medkit · cuff · flame · box · crate · fish · pickaxe · leaf · chef · pan · gavel · hammer · scissors · briefcase · camera · flask · ingot · spring · chip · scale · barrel · ammo · powder · drill · cash · card · bank · wallet · coin · receipt · chart · trend-up · trend-down · dep · wd · cart · bag · tag · gem · store · phone · call · radio · pistol · knife · bandage · pill · syringe · bottle · coffee · laptop · usb · keycard · backpack · dice · note · file · clipboard · palette · shirt · tank · pants · shoe · hat · glasses · mask · glove · chain · hanger · pin · map · compass · building · hospital · sun · moon · cloud · rain · tree · mail · message · send · broadcast · bell-ring · terminal · code · bug · database · server · ban · teleport

Aliases: arrow-left → arrow-l · arrow-right → arrow-r · chevron-up → chev-u · chevron-down → chev-d · chevron-left → chev-l · chevron-right → chev-r · close → x · settings → cog · gear → cog · delete → trash · health → heart · armor → shield · hunger → food · thirst → drop · stamina → bolt · stress → brain · money → cash · ems → medkit · police → badge · mechanic → wrench · warning → alert · spectate → eye · location → pin · vehicle → car · weapon → pistol · inventory → backpack · job → briefcase · fire → flame · water → drop · gold → ingot · speed → gauge · seatbelt → seat · voice → mic · notify → bell
