// Runs tools/bagkit (the clothing-bag converter) for server/clothingbags.lua and relays its output.
// bagkit is a separate program, so converting never blocks the server thread.
// FiveM runs every server .js file of a resource in ONE context: wrap it so names never clash.
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

// tell the Lua side whether this server can convert bags at all
on('nayzeee-backpack:bagkit:check', (kits) => {
  const kit = kitFor(kits || {});
  emit('nayzeee-backpack:bagkit:kit', !!kit, process.platform);
});

on('nayzeee-backpack:bagkit:run', (job) => {
  if (running) return emit('nayzeee-backpack:bagkit:msg', job.src, 'busy', {});
  const kit = kitFor(job.kits || {});
  if (!kit) return emit('nayzeee-backpack:bagkit:msg', job.src, 'error', { message: `bagkit for ${process.platform} is missing (tools/bagkit)` });

  if (process.platform !== 'win32') { try { fs.chmodSync(kit, 0o755); } catch (e) { /* read-only install: it may already be executable */ } }
  const rootsFile = path.join(path.dirname(kit), '.roots.txt');
  const lines = (job.roots || []).concat((job.drops || []).map((d) => 'drop:' + path.resolve(HERE, d)));
  try { fs.writeFileSync(rootsFile, lines.join('\n')); } catch (e) {
    return emit('nayzeee-backpack:bagkit:msg', job.src, 'error', { message: 'could not write ' + rootsFile + ': ' + e.message });
  }
  const cmd = job.mode === 'rebuild' || job.mode === 'prune' ? 'build' : job.mode;
  const args = [cmd, '--out', path.resolve(job.out), '--roots-file', rootsFile,
    '--tex', String(job.tex || 1024), '--icons', String(job.icons == null ? 256 : job.icons), '--lod', String(job.lod || 100),
    '--tris', String(job.tris == null ? 45000 : job.tris)];
  if (job.mode === 'rebuild') args.push('--all');
  if (job.mode === 'prune') args.push('--prune');

  let buf = '';
  const tail = [];
  try {
    running = spawn(kit, args, { cwd: path.dirname(kit), windowsHide: true });
  } catch (e) {
    running = null;
    return emit('nayzeee-backpack:bagkit:msg', job.src, 'error', { message: 'could not start bagkit: ' + e.message });
  }
  const line = (l) => {
    if (l.startsWith('@')) {
      try { const m = JSON.parse(l.slice(1)); emit('nayzeee-backpack:bagkit:msg', job.src, m.kind, m.data || {}); } catch (e) { /* not ours */ }
    } else if (l.trim()) {
      tail.push(l); if (tail.length > 30) tail.shift();
      if (job.mode !== 'scan') emit('nayzeee-backpack:bagkit:line', l); // server/clothingbags.lua decides (debug only)
    }
  };
  running.stdout.setEncoding('utf8');
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
    try { fs.unlinkSync(rootsFile); } catch (e) { /* fine */ }
    emit('nayzeee-backpack:bagkit:exit', job.src, job.mode, code === null ? -1 : code, tail.slice(-8).join('\n'));
  });
});
})();
