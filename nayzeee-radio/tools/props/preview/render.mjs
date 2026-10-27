// Headless preview renderer for nzprops (NAYZEEE Radio).
//
//   node render.mjs --list props.json --out <dir> [--modules <node_modules dir>] [--size 640]
//                   [--views front,back,top] [--chromium /opt/pw-browsers/chromium]
//
// props.json: [{ "name": "nzr_x", "glb": "/abs/path/nzr_x.glb", "views"?: [...], "cams"?: [...], "lights"?: [...],
//                "parts"?: [{ "glb": "/abs/part.glb", "pos": [x, y, z] }], "transparent"?: bool, "fit"?: bool|number,
//                "exposure"?: number, "fill"?: number (camera-side fill light) }, ...]
// Writes <out>/<name>_<view>.png for every prop and view (+ <name>_<cam.name>.png per extra camera:
// { name, pos: [x,y,z], target: [x,y,z], fov, clipZ? } in GTA prop space; lights: { pos, intensity, distance?, color? }).
// parts: extra glbs placed at GTA offsets (the radios' assembled body + parts render). transparent: no background
// and no floor (item icons); fit: frame the bounding box tightly. three + playwright-core are loaded from
// --modules (default: ./node_modules next to this file).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const args = {};
for (let i = 0; i < argv.length; i++) if (argv[i].startsWith('--')) args[argv[i].slice(2)] = argv[i + 1];
const modules = path.resolve(args.modules || path.join(here, 'node_modules'));
const outDir = path.resolve(args.out || path.join(here, 'renders'));
const size = parseInt(args.size || '640', 10);
const views = (args.views || 'front,back,top').split(',');
const chromiumPath = args.chromium || process.env.NZR_CHROMIUM || '/opt/pw-browsers/chromium';
const list = JSON.parse(fs.readFileSync(args.list, 'utf8'));
fs.mkdirSync(outDir, { recursive: true });

const { chromium } = await import(pathToFileURL(path.join(modules, 'playwright-core', 'index.mjs')).href);

const glbs = new Map();
for (const p of list) {
  glbs.set(p.name, path.resolve(p.glb));
  (p.parts || []).forEach((q, i) => glbs.set(`${p.name}~${i}`, path.resolve(q.glb)));
}
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary' };
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let file = null;
  if (url.pathname === '/' || url.pathname === '/index.html') file = path.join(here, 'index.html');
  else if (url.pathname.startsWith('/modules/')) file = path.join(modules, decodeURIComponent(url.pathname.slice(9)));
  else if (url.pathname.startsWith('/glb/')) file = glbs.get(decodeURIComponent(url.pathname.slice(5)));
  if (file && !path.resolve(file).startsWith(modules) && !file.endsWith('.glb') && file !== path.join(here, 'index.html')) file = null;
  if (!file || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end('not found'); return; }
  res.writeHead(200, { 'content-type': mime[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const browser = await chromium.launch({
  executablePath: chromiumPath,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl'],
});
let failed = 0;
try {
  const page = await browser.newPage({ viewport: { width: size, height: size } });
  page.on('pageerror', e => console.log('[pageerror]', e.message));
  page.on('console', m => { if (m.type() === 'error') console.log('[console]', m.text()); });
  await page.goto(`http://127.0.0.1:${port}/index.html`);
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
  for (const p of list) {
    try {
      const pviews = p.views || views;
      const parts = (p.parts || []).map((q, i) => ({ url: `/glb/${encodeURIComponent(p.name + '~' + i)}`, pos: q.pos }));
      const extra = { cams: p.cams || [], lights: p.lights || [], parts, transparent: !!p.transparent, fit: p.fit || false,
        exposure: p.exposure || 0, fill: p.fill || 0 };
      const shots = await page.evaluate(([u, v, s, x]) => window.renderProp(u, v, s, x), [`/glb/${encodeURIComponent(p.name)}`, pviews, size, extra]);
      const names = pviews.concat(extra.cams.map(c => c.name));
      shots.forEach((d, i) => {
        const file = path.join(outDir, `${p.name}_${names[i]}.png`);
        fs.writeFileSync(file, Buffer.from(d.split(',')[1], 'base64'));
      });
      console.log('rendered', p.name);
    } catch (e) {
      failed++;
      console.log('FAILED', p.name, e.message);
    }
  }
} finally {
  await browser.close();
  server.close();
}
process.exit(failed ? 3 : 0);
