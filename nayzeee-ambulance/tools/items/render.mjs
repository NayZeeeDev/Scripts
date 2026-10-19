// Renders the inventory item pictures (html/img/items) and the minigame tool-belt pictures
// (html/img/tools) with three.js in headless Chromium, then hands the raw frames to post.py.
//
//   node tools/items/render.mjs [--set items|tools|all] [--only bandage,gauze] [--raw <dir>]
//        [--modules <node_modules>] [--chromium /opt/pw-browsers/chromium] [--glb <dir>] [--no-post]
//
// --raw     where the 1024² premultiplied RGBA frames go (default /tmp/nza-work/items/raw)
// --modules node_modules holding three@0.170.0 + playwright-core (see README.md)
// --glb     folder with props-pipeline glb exports (<dir>/<name>/<name>.glb or <dir>/<name>.glb)
// --dest    root the PNGs are written under (default: this repository → html/img/items + html/img/tools)
// --sheets  folder for the contact sheets (default /tmp/nza-work/items/sheets)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..');
const argv = process.argv.slice(2);
const args = {};
for (let i = 0; i < argv.length; i++) if (argv[i].startsWith('--')) { const k = argv[i].slice(2); const nx = argv[i + 1]; if (nx === undefined || nx.startsWith('--')) args[k] = true; else { args[k] = nx; i++; } }

const candidates = [args.modules, process.env.NZA_MODULES, path.join(here, 'node_modules'), '/tmp/nza-work/items/node_modules', '/tmp/nza-work/props/preview_node/node_modules', path.join(repo, 'tools/props/preview/node_modules')].filter(Boolean);
const modules = candidates.map(p => path.resolve(p)).find(p => fs.existsSync(path.join(p, 'three')) && fs.existsSync(path.join(p, 'playwright-core')));
if (!modules) { console.error('three + playwright-core not found; see tools/items/README.md (npm install in a work folder, pass --modules)'); process.exit(2); }
const rawDir = path.resolve(args.raw || '/tmp/nza-work/items/raw');
const glbDir = path.resolve(args.glb || '/tmp/nza-work/props/out');
const fontsDir = path.join(repo, 'tools/props/fonts');
const chromiumPath = args.chromium || process.env.NZA_CHROMIUM || '/opt/pw-browsers/chromium';
const sets = (!args.set || args.set === 'all') ? ['items', 'tools'] : String(args.set).split(',');
const only = args.only ? new Set(String(args.only).split(',')) : null;

const { chromium } = await import(pathToFileURL(path.join(modules, 'playwright-core', 'index.mjs')).href);

const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary', '.woff2': 'font/woff2' };
const inside = (root, f) => { const r = path.resolve(f); return r === root || r.startsWith(root + path.sep); };
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = decodeURIComponent(url.pathname);
  let file = null;
  if (p === '/' || p === '/index.html') file = path.join(here, 'index.html');
  else if (p.startsWith('/modules/')) { file = path.join(modules, p.slice(9)); if (!inside(modules, file)) file = null; }
  else if (p.startsWith('/fonts/')) { file = path.join(fontsDir, p.slice(7)); if (!inside(fontsDir, file)) file = null; }
  else if (p.startsWith('/glb/')) {
    const n = path.basename(p.slice(5));
    file = [path.join(glbDir, n, `${n}.glb`), path.join(glbDir, `${n}.glb`)].find(f => fs.existsSync(f)) || null;
  } else if (p.endsWith('.js')) { file = path.join(here, p.slice(1)); if (!inside(here, file)) file = null; }
  if (!file || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end('not found'); return; }
  res.writeHead(200, { 'content-type': mime[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const browser = await chromium.launch({
  executablePath: chromiumPath,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--force-color-profile=srgb'],
});
let failed = 0;
const done = [];
try {
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  page.on('pageerror', e => console.log('[pageerror]', e.message));
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') console.log(`[${m.type()}]`, m.text()); });
  await page.goto(`http://127.0.0.1:${port}/index.html`);
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 180000 });
  for (const set of sets) {
    const names = (await page.evaluate(s => window.listModels(s), set)).filter(n => !only || only.has(n));
    fs.mkdirSync(path.join(rawDir, set), { recursive: true });
    for (const name of names) {
      const t0 = Date.now();
      try {
        const r = await page.evaluate(([s, n]) => window.renderModel(s, n), [set, name]);
        fs.writeFileSync(path.join(rawDir, set, `${name}.rgba`), Buffer.from(r.data, 'base64'));
        done.push(`${set}/${name}`);
        console.log(`rendered ${set}/${name} (${Date.now() - t0} ms)`);
      } catch (e) {
        failed++;
        console.log(`FAILED ${set}/${name}: ${e.message}`);
      }
    }
  }
} finally {
  await browser.close();
  server.close();
}
if (!args['no-post'] && done.length) {
  const py = spawnSync('python3', [path.join(here, 'post.py'), '--raw', rawDir, '--repo', path.resolve(args.dest || repo), '--sets', sets.join(','), ...(args.sheets ? ['--sheets', path.resolve(args.sheets)] : []), ...(only ? ['--only', [...only].join(',')] : [])], { stdio: 'inherit' });
  if (py.status) failed++;
}
process.exit(failed ? 3 : 0);
