#!/usr/bin/env node
/* ═══════════════════════════════════════════════════════════
   NAYZEEE ICONS · package
   node icons/package.js
   Builds a drop-in FiveM resource at dist/nz_icons/ and zips it
   to dist/nz_icons.zip. Run icons/build.js first if you changed icons.
   ═══════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ICONS = __dirname;
const PACK = path.join(ICONS, '..');
const DIST = path.join(PACK, 'dist');
const OUT = path.join(DIST, 'nz_icons');
const VERSION = '1.0.0';
const { icons, alias } = require('./src/icons.js');

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'cheatsheet'), { recursive: true });

const copy = (from, to) => fs.cpSync(path.join(ICONS, from), path.join(OUT, to), { recursive: true });
copy('nz-icons.css', 'nz-icons.css');
copy('nz-icons-fa.css', 'nz-icons-fa.css');
copy('nz-icons.svg', 'nz-icons.svg');
copy('nz-icons.js', 'nz-icons.js');
copy('svg', 'svg');

/* cheatsheet, rewired to work from inside the resource */
fs.cpSync(path.join(PACK, 'core', 'nz-core.css'), path.join(OUT, 'cheatsheet', 'nz-core.css'));
copy('nz-icons.data.js', 'cheatsheet/nz-icons.data.js');
let html = fs.readFileSync(path.join(ICONS, 'index.html'), 'utf8')
  .replace('href="../core/nz-core.css"', 'href="nz-core.css"')
  .replace('href="nz-icons.css"', 'href="../nz-icons.css"')
  .replace(/icons\/nz-icons/g, 'nz-icons')
  .replace(/icons\/svg\//g, 'svg/')
  .replace(/Edit <b>icons\/src\/icons\.js<\/b>, then run <b>node icons\/build\.js<\/b> to regenerate every format\./,
    'Part of the NAYZEEE UI pack · nz_icons v' + VERSION);
fs.writeFileSync(path.join(OUT, 'cheatsheet', 'index.html'), html);

fs.writeFileSync(path.join(OUT, 'fxmanifest.lua'), `fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nz_icons'
author 'NAYZEEE'
description 'NAYZEEE icon set: ${icons.length} brand icons for NUI (CSS classes, SVG, sprite, Font Awesome drop-in)'
version '${VERSION}'

-- No scripts: this resource only serves files to other resources' NUI pages.
-- From another resource's html:  <link rel="stylesheet" href="nui://nz_icons/nz-icons.css">
files {
  'nz-icons.css',
  'nz-icons-fa.css',
  'nz-icons.svg',
  'nz-icons.js',
  'svg/*.svg',
}
`);

const names = icons.map(i => i.name);
fs.writeFileSync(path.join(OUT, 'README.md'), `# nz_icons · NAYZEEE icons v${VERSION}

${icons.length} original NAYZEEE icons (plus ${Object.keys(alias).length} aliases) for FiveM NUI pages. Chamfered corners, a 1.75 stroke and an optional teal accent.
Open \`cheatsheet/index.html\` in a browser to search every icon and click to copy it.

## Two ways to use it

**A. Bundle the files inside each script (best for scripts you sell).**
Copy the files you need into the script's \`html/\` folder and list them in that script's \`fxmanifest.lua\`:

\`\`\`lua
files {
  'html/index.html',
  'html/nz-icons.css',
}
\`\`\`
\`\`\`html
<link rel="stylesheet" href="nz-icons.css">
\`\`\`
Customers then don't need to install anything extra.

**B. Run it as a shared resource (handy on your own server).**
Drop the \`nz_icons\` folder into \`resources/\`, add \`ensure nz_icons\` to server.cfg (before the scripts that use it), then point any NUI page at it:

\`\`\`html
<link rel="stylesheet" href="nui://nz_icons/nz-icons.css">
\`\`\`

## Writing icons

| File | Use it like |
|------|-------------|
| \`nz-icons.css\` | \`<i class="nzi nzi-car"></i>\` takes the text colour and size. Sizes: \`nzi-xs\` \`nzi-sm\` \`nzi-lg\` \`nzi-xl\` \`nzi-2x\` \`nzi-3x\`. Extras: \`nzi-fw\` (fixed width), \`nzi-spin\` |
| \`nz-icons-fa.css\` | Load **after** Font Awesome. Existing \`<i class="fa-solid fa-car"></i>\` markup shows the NAYZEEE icon. Covers 344 Font Awesome names; any other name still comes from Font Awesome |
| \`nz-icons.js\` | \`<i data-nzi="car"></i>\` becomes an inline SVG, or \`el.innerHTML = NZI.svg('car')\`. Supports the teal accent |
| \`nz-icons.svg\` | Sprite: \`<svg class="nzi-svg"><use href="nz-icons.svg#car"/></svg>\` (needs \`nz-icons.css\` or \`nz-icons.js\` for the \`nzi-svg\` sizing). Browsers block this when you open a page straight from disk; it works in game |
| \`svg/<name>.svg\` | Plain files, e.g. \`<img src="svg/car.svg">\` (draws in black; recolour with CSS \`filter\` or use the options above) |

**Teal accent (duotone):** set \`--nzi-accent: #08afa2\` on a parent element and each icon's accent detail turns teal. Works with \`nz-icons.js\`, the sprite and the SVG files. The \`nzi\` CSS classes are single-colour.

**Colour and size** come from the surrounding text: \`<i class="nzi nzi-heart" style="color:#e5484d;font-size:24px"></i>\`.

## Icon names

${names.join(' · ')}

Aliases: ${Object.entries(alias).map(([a, t]) => `${a} → ${t}`).join(' · ')}
`);

/* zip */
const zip = path.join(DIST, 'nz_icons.zip');
fs.rmSync(zip, { force: true });
execSync(`zip -qr -X "${zip}" nz_icons`, { cwd: DIST });
const count = execSync(`find nz_icons -type f | wc -l`, { cwd: DIST }).toString().trim();
console.log(`dist/nz_icons/ (${count} files) · dist/nz_icons.zip ${(fs.statSync(zip).size / 1024).toFixed(0)} KB`);
