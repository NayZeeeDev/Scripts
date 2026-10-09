// Wig Studio writer: saves the small PNGs the studio keyed in the NUI into the photo resource
// (Config.Studio.Resource, default nzw_shots, next to this resource) and keeps its index.json.
// The photos live outside this resource so updating Wig Snatch never wipes them.
// On start it also moves in photos from older versions (this resource's shots/ folder) and gets back
// any it can find in ox_inventory/web/images. Plain Node built-ins only.
// The copy into ox_inventory is done from Lua (server/studio.lua).
// FXServer runs every server .js of a resource in one shared scope: keep this file's names to itself
(() => {
const fs = require('fs');
const path = require('path');

const RESOURCE = GetCurrentResourceName();
// Config.Studio.Resource, handed over by server/studio.lua (set before this runs)
let SHOTS_RES = 'nzw_shots';
const NAME = /^wig_([mf])_(\d{1,4})_(\d{1,3})$/;

function dirOf(res) {
  const p = GetResourcePath(res);
  return p && p !== '' ? path.resolve(p) : null;
}
// the photo resource: where it is if the server knows it, else next to this resource
function shotsDir() {
  if (GetResourceState(SHOTS_RES) !== 'missing') { const d = dirOf(SHOTS_RES); if (d) return d; }
  return path.resolve(path.join(dirOf(RESOURCE), '..', SHOTS_RES));
}
let DIR = null, INDEX = null;
function init() {
  if (DIR) return;
  SHOTS_RES = GetConvar('nzwig_shots_resource', '') || 'nzw_shots';
  DIR = shotsDir();
  INDEX = path.join(DIR, 'index.json');
}

const MANIFEST = `fx_version 'cerulean'
game 'gta5'

-- Wig Studio photos for Wig Snatch V2, made in-game with /wigstudio.
-- Keep this folder when you update Wig Snatch: your photos live here.
description 'Wig Studio photos for Wig Snatch V2'

files {
    '*.png',
    'index.json',
}
`;

function ensureResource() {
  init();
  if (!fs.existsSync(DIR)) fs.mkdirSync(DIR, { recursive: true });
  const fx = path.join(DIR, 'fxmanifest.lua');
  if (!fs.existsSync(fx)) fs.writeFileSync(fx, MANIFEST);
}

function list() {
  return fs.readdirSync(DIR)
    .map((f) => NAME.exec(f.replace(/\.png$/i, '')))
    .filter((m) => m)
    .map((m) => `${m[1]}/${Number(m[2])}_${Number(m[3])}`)
    .sort();
}

// photos from older versions (shots/ in this resource) and the copies in ox_inventory
function migrate() {
  let moved = 0;
  const from = [path.join(dirOf(RESOURCE), 'shots')];
  const ox = dirOf('ox_inventory');
  if (ox) from.push(path.join(ox, 'web', 'images'));
  for (const dir of from) {
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (!/\.png$/i.test(f) || !NAME.test(f.replace(/\.png$/i, ''))) continue;
      const out = path.join(DIR, f.toLowerCase());
      if (fs.existsSync(out)) continue;
      try { fs.copyFileSync(path.join(dir, f), out); moved++; } catch (e) { /* skip it */ }
    }
  }
  return moved;
}

function rebuild() {
  try {
    init();
    ensureResource();
    const moved = migrate();
    const keys = list();
    fs.writeFileSync(INDEX, JSON.stringify(keys));
    if (moved) console.log(`^2[${RESOURCE}]^0 wig studio: moved ${moved} photo(s) into ${SHOTS_RES}/`);
    emit('nz-wig:studio:indexed', keys, moved > 0);
  } catch (err) {
    console.log(`^1[${RESOURCE}]^0 could not set up ${SHOTS_RES}/: ${err && err.message ? err.message : err}`);
    console.log(`^3    add to server.cfg: add_filesystem_permission ${RESOURCE} write ${SHOTS_RES}^0`);
    emit('nz-wig:studio:indexed', [], false);
  }
}
setImmediate(rebuild);

on('nz-wig:studio:write', (src, name, b64) => {
  let ok = false, key = null;
  try {
    const m = NAME.exec(String(name));
    if (!m) throw new Error('bad name');
    const buf = Buffer.from(b64.startsWith('data:') ? b64.slice(b64.indexOf(',') + 1) : b64, 'base64');
    // PNG signature check, so nothing else ever lands on disk
    if (buf.length < 8 || buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a png');

    ensureResource();
    const out = path.resolve(path.join(DIR, name + '.png'));
    if (!out.startsWith(DIR + path.sep)) throw new Error('path escaped');
    fs.writeFileSync(out, buf);

    key = `${m[1]}/${Number(m[2])}_${Number(m[3])}`;
    const keys = list();
    fs.writeFileSync(INDEX, JSON.stringify(keys));
    ok = true;
    console.log(`^2[${RESOURCE}]^0 wig studio saved ${SHOTS_RES}/${name}.png (${Math.round(buf.length / 1024)} KB)`);
  } catch (err) {
    console.log(`^1[${RESOURCE}]^0 wig studio ${name} failed: ${err && err.message ? err.message : err}`);
    if (err && /EACCES|EPERM|permission/i.test(String(err.message))) console.log(`^3    add to server.cfg: add_filesystem_permission ${RESOURCE} write ${SHOTS_RES}^0`);
  }
  emit('nz-wig:studio:written', src, name, ok, key, b64);
});
})();
