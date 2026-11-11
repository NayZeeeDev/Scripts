// Runs tools/hairkit (the 3D wig builder) for server/hairprops.lua and relays its output.
// hairkit is a separate program, so the conversion never blocks the server thread.
// FXServer runs every server .js of a resource in one shared scope: keep this file's names to itself
(() => {
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const RESOURCE = GetCurrentResourceName();
const HERE = path.resolve(GetResourcePath(RESOURCE));
let running = null;

function kitFor(kits) {
  const rel = process.platform === 'win32' ? kits.windows : kits.linux;
  if (!rel) return null;
  const p = path.resolve(HERE, rel);
  return p.startsWith(HERE + path.sep) && fs.existsSync(p) ? p : null;
}

// a clothing pack folder from Config.HairProps.Packs: absolute, or relative to the server folder (where
// server.cfg is, e.g. 'resources/[clothing]/my_hair') or to the resources folder ('[clothing]/my_hair')
function packDir(p) {
  const clean = String(p).trim().replace(/^["']|["']$/g, '');
  if (!clean) return null;
  const tries = [];
  if (path.isAbsolute(clean)) tries.push(clean);
  else {
    const parts = HERE.split(path.sep);
    const at = parts.lastIndexOf('resources');
    const server = at > 0 ? parts.slice(0, at).join(path.sep) || path.sep : null;
    if (server) tries.push(path.resolve(server, clean), path.resolve(server, 'resources', clean));
    tries.push(path.resolve(process.cwd(), clean), path.resolve(process.cwd(), 'resources', clean));
  }
  for (const t of tries) { try { if (fs.statSync(t).isDirectory()) return t; } catch (e) { /* next */ } }
  return null;
}

// tell the Lua side whether this server can build 3D wigs at all
on('nz-wig:hairkit:check', (kits) => {
  const kit = kitFor(kits || {});
  emit('nz-wig:hairkit:kit', !!kit, process.platform);
});

on('nz-wig:hairkit:run', (job) => {
  if (running) return emit('nz-wig:hairkit:msg', job.src, 'busy', {});
  const kit = kitFor(job.kits || {});
  if (!kit) return emit('nz-wig:hairkit:msg', job.src, 'error', { message: `hairkit for ${process.platform} is missing (tools/hairkit)` });

  if (process.platform !== 'win32') { try { fs.chmodSync(kit, 0o755); } catch (e) { /* read-only install: it may already be executable */ } }
  const roots = (job.roots || []).slice();
  for (const p of job.packs || []) {
    const d = packDir(p);
    if (d) roots.push(d);
    else emit('nz-wig:hairkit:msg', job.src, 'warn', { message: `Config.HairProps.Packs: couldn't find "${p}" (a resource name, or a folder like resources/[clothing]/my_hair)` });
  }
  const rootsFile = path.join(path.dirname(kit), '.roots.txt');
  try { fs.writeFileSync(rootsFile, roots.join('\n')); } catch (e) {
    return emit('nz-wig:hairkit:msg', job.src, 'error', { message: 'could not write ' + rootsFile + ': ' + e.message });
  }
  const args = [job.mode === 'rebuild' ? 'build' : job.mode, '--out', path.resolve(job.out), '--roots-file', rootsFile, '--tex', String(job.tex || 256)];
  if (job.mode === 'rebuild') args.push('--all');
  if (job.genders) args.push('--genders', String(job.genders));
  // the hair drop folder (hairstyles/ in this resource)
  if (job.drop) {
    const drop = path.resolve(job.drop);
    if (drop.startsWith(HERE + path.sep)) {
      try { fs.mkdirSync(drop, { recursive: true }); } catch (e) { /* read-only install */ }
      args.push('--drop', drop);
    }
  }
  const tmpFiles = [rootsFile];
  if (job.sliceNames && job.sliceNames.length) {
    const namesFile = path.join(path.dirname(kit), '.slicenames.txt');
    try { fs.writeFileSync(namesFile, job.sliceNames.join('\n')); args.push('--slice-names', namesFile); tmpFiles.push(namesFile); } catch (e) { /* none this time */ }
  }
  // hairstyles the salon uses: they also get slice props (the style goes on row by row)
  if (job.slices && job.slices.length) {
    const slicesFile = path.join(path.dirname(kit), '.slices.txt');
    try { fs.writeFileSync(slicesFile, job.slices.join('\n')); args.push('--slices', slicesFile); } catch (e) { /* no slices this time */ }
  }

  let buf = '', tail = [];
  try {
    running = spawn(kit, args, { cwd: path.dirname(kit), windowsHide: true });
  } catch (e) {
    running = null;
    return emit('nz-wig:hairkit:msg', job.src, 'error', { message: 'could not start hairkit: ' + e.message });
  }
  const line = (l) => {
    if (l.startsWith('@')) {
      try { const m = JSON.parse(l.slice(1)); emit('nz-wig:hairkit:msg', job.src, m.kind, m.data || {}); } catch (e) { /* not ours */ }
    } else if (l.trim()) {
      tail.push(l); if (tail.length > 30) tail.shift();
      if (job.mode !== 'scan') console.log(`^5[${RESOURCE}]^7 hairkit: ${l}`);
    }
  };
  running.stdout.on('data', (d) => {
    buf += d.toString();
    let i;
    while ((i = buf.indexOf('\n')) >= 0) { line(buf.slice(0, i).replace(/\r$/, '')); buf = buf.slice(i + 1); }
  });
  running.stderr.on('data', (d) => { tail.push(d.toString()); if (tail.length > 30) tail.shift(); });
  running.on('error', (e) => { tail.push(e.message); });
  running.on('close', (code) => {
    if (buf) line(buf);
    running = null;
    for (const f of tmpFiles) { try { fs.unlinkSync(f); } catch (e) { /* fine */ } }
    emit('nz-wig:hairkit:exit', job.src, job.mode, code === null ? -1 : code, tail.slice(-8).join('\n'));
  });
});
})();
