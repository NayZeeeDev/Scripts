// Runs tools/sneakerkit (the 3D shoe prop builder) for server/props.lua and relays what it prints.
// sneakerkit is its own program, so a build never blocks the server thread.
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

// tell the Lua side whether this server can build shoe props at all
on('nzs:kit:check', (kits) => {
  const kit = kitFor(kits || {});
  emit('nzs:kit:found', !!kit, process.platform);
});

on('nzs:kit:run', (job) => {
  if (running) return emit('nzs:kit:msg', job.src, 'busy', {});
  const kit = kitFor(job.kits || {});
  if (!kit) return emit('nzs:kit:msg', job.src, 'error', { message: `sneakerkit for ${process.platform} is missing (tools/sneakerkit)` });

  if (process.platform !== 'win32') { try { fs.chmodSync(kit, 0o755); } catch (e) { /* read-only install: it may already be executable */ } }
  const rootsFile = path.join(path.dirname(kit), '.roots.txt');
  try { fs.writeFileSync(rootsFile, (job.roots || []).join('\n')); } catch (e) {
    return emit('nzs:kit:msg', job.src, 'error', { message: 'could not write ' + rootsFile + ': ' + e.message });
  }
  const args = [job.mode === 'rebuild' ? 'build' : job.mode, '--out', path.resolve(job.out), '--roots-file', rootsFile, '--tex', String(job.tex || 512)];
  if (job.mode === 'rebuild') args.push('--all');
  if (job.icons) args.push('--icons', path.resolve(job.icons));
  args.push('--keep', path.join(HERE, 'shots'));   // photos taken in the studio are never replaced

  let buf = '';
  const tail = [];
  try {
    running = spawn(kit, args, { cwd: path.dirname(kit), windowsHide: true });
  } catch (e) {
    running = null;
    return emit('nzs:kit:msg', job.src, 'error', { message: 'could not start sneakerkit: ' + e.message });
  }
  const line = (l) => {
    if (l.startsWith('@')) {
      try { const m = JSON.parse(l.slice(1)); emit('nzs:kit:msg', job.src, m.kind, m.data || {}); } catch (e) { /* not ours */ }
    } else if (l.trim()) {
      tail.push(l); if (tail.length > 30) tail.shift();
      if (job.mode !== 'scan') console.log(`^5[${RESOURCE}]^7 sneakerkit: ${l}`);
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
    try { fs.unlinkSync(rootsFile); } catch (e) { /* fine */ }
    emit('nzs:kit:exit', job.src, job.mode, code === null ? -1 : code, tail.slice(-8).join('\n'));
  });
});
