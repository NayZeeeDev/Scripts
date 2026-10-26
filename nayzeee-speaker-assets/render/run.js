#!/usr/bin/env node
// Drives the WebGL2 renderer in headless Chromium (Playwright).
//   node render/run.js <jobs.json>
// jobs.json: { "verbose": bool, "jobs": [ { "out": "<raw rgba path>", "width", "height", "instances": [{ "glb": "<abs path>", "matrix": [16] }], ... } ] }
// Each job writes width*height*4 bytes of straight-alpha RGBA8 (rows bottom-up) to job.out and a <out>.json with stats.
'use strict';
const fs = require('fs');
const path = require('path');

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  process.stderr.write('render: cannot load "playwright"; run with NODE_PATH="$(npm root -g)"\n');
  process.exit(3);
}

const HERE = __dirname;
const ORIGIN = 'http://nz-render.localhost';
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.glb': 'model/gltf-binary', '.json': 'application/json' };
// SwiftShader (CPU) WebGL2: works without a GPU, deterministic output.
const ARGS = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
  '--disable-background-networking', '--disable-component-update', '--disable-default-apps', '--disable-sync',
  '--no-first-run', '--disable-gpu-watchdog'];

async function main() {
  const jobFile = process.argv[2];
  if (!jobFile) { process.stderr.write('usage: node run.js <jobs.json>\n'); process.exit(2); }
  const spec = JSON.parse(fs.readFileSync(jobFile, 'utf8'));
  const verbose = !!spec.verbose;
  const exe = process.env.NZ_CHROMIUM || '/opt/pw-browsers/chromium';
  const browser = await chromium.launch({ executablePath: fs.existsSync(exe) ? exe : undefined, args: ARGS, headless: true });
  let failed = 0;
  try {
    const page = await browser.newPage();
    page.on('console', (m) => {
      if (verbose || m.type() === 'error' || m.type() === 'warning') process.stderr.write(`[page:${m.type()}] ${m.text()}\n`);
    });
    page.on('pageerror', (e) => process.stderr.write(`[page:error] ${e.message}\n`));
    await page.route(`${ORIGIN}/**`, async (route) => {
      const url = new URL(route.request().url());
      let file;
      if (url.pathname.startsWith('/fs/')) file = decodeURIComponent(url.pathname.slice(3));
      else file = path.join(HERE, path.normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, ''));
      if (!fs.existsSync(file) || !fs.statSync(file).isFile()) return route.fulfill({ status: 404, body: `not found: ${file}` });
      return route.fulfill({ status: 200, body: fs.readFileSync(file), contentType: MIME[path.extname(file)] || 'application/octet-stream' });
    });
    await page.goto(`${ORIGIN}/index.html`);
    await page.waitForFunction(() => window.NZ && window.NZ.ready, null, { timeout: 30000 });
    for (const job of spec.jobs) {
      const t0 = Date.now();
      job.instances = job.instances.map((it) => ({ ...it, url: `${ORIGIN}/fs${encodeURI(path.resolve(it.glb))}` }));
      try {
        const res = await page.evaluate((j) => window.NZ.renderJob(j), job);
        fs.writeFileSync(job.out, Buffer.from(res.b64, 'base64'));
        res.stats.wallMs = Date.now() - t0;
        fs.writeFileSync(`${job.out}.json`, JSON.stringify(res.stats));
        if (verbose) process.stderr.write(`render: ${job.label || job.out} ${res.width}x${res.height} ${JSON.stringify(res.stats.ms)} wall ${res.stats.wallMs} ms\n`);
      } catch (e) {
        failed++;
        process.stderr.write(`render: job ${job.label || job.out} failed: ${e.message}\n`);
      }
    }
  } finally {
    await browser.close();
  }
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { process.stderr.write(`render: ${e.stack || e}\n`); process.exit(1); });
