// Headless preview renderer: node render.mjs --assets <dir with mesh.json + png> --out <dir> [--views iso,top,bottom,side,icon]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, arr) => (v.startsWith('--') ? a.push([v.slice(2), arr[i + 1]]) : null, a), []));
const assets = path.resolve(args.assets || path.join(here, 'assets'));
const outDir = path.resolve(args.out || path.join(here, 'renders'));
const views = (args.views || 'iso,top,bottom,side,icon').split(',');
fs.mkdirSync(outDir, { recursive: true });

const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let p = url.pathname.startsWith('/assets/') ? path.join(assets, url.pathname.slice(8)) : path.join(here, url.pathname === '/' ? 'index.html' : url.pathname);
  if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end('nf'); return; }
  res.writeHead(200, { 'content-type': mime[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl'] });
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
page.on('console', m => console.log('[page]', m.text()));
page.on('pageerror', e => console.log('[pageerror]', e.message));
for (const v of views) {
  const transparent = v === 'icon' ? '1' : '0';
  await page.goto(`http://127.0.0.1:${port}/index.html?view=${v}&transparent=${transparent}&size=1024`);
  await page.waitForFunction(() => window.__done === true, null, { timeout: 120000 });
  const file = path.join(outDir, `${v}.png`);
  await page.locator('canvas').screenshot({ path: file, omitBackground: transparent === '1' });
  console.log('wrote', file);
}
await browser.close();
server.close();
