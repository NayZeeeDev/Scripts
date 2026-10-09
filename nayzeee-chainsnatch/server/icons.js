// Icon files. Plain Node built-ins only.
//  - the icon studio's PNGs land in this resource's icons/ folder
//  - chainkit's drawn icons (nayzeee-chainprops/icons) are handed to Lua so it can copy them into
//    ox_inventory/web/images (newer FXServer builds block Node from writing into another resource)
const fs = require('fs');
const path = require('path');

const RESOURCE = GetCurrentResourceName();
const OWN_DIR = path.resolve(path.join(GetResourcePath(RESOURCE), 'icons'));
const NAME = /^[\w-]{1,80}$/;

on('nzc:icon:write', (src, name, b64) => {
  let ok = false;
  try {
    if (!NAME.test(name)) throw new Error('bad name');
    const data = b64.startsWith('data:') ? b64.slice(b64.indexOf(',') + 1) : b64;
    const buf = Buffer.from(data, 'base64');
    // PNG signature check, so nothing else ever lands on disk
    if (buf.length < 8 || buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a png');
    const out = path.resolve(path.join(OWN_DIR, name + '.png'));
    if (!out.startsWith(OWN_DIR + path.sep)) throw new Error('path escaped');
    if (!fs.existsSync(OWN_DIR)) fs.mkdirSync(OWN_DIR, { recursive: true });
    fs.writeFileSync(out, buf);
    ok = true;
    console.log(`^2[${RESOURCE}]^0 icon saved: icons/${name}.png (${Math.round(buf.length / 1024)} KB)`);
  } catch (err) {
    console.log(`^1[${RESOURCE}]^0 icon ${name} failed: ${err && err.message ? err.message : err}`);
  }
  emit('nzc:icon:written', src, name, ok, b64);
});

// copy chainkit icons for props that have no studio icon yet
on('nzc:icons:fromKit', (propsResource, names, force) => {
  let dir;
  try { dir = path.resolve(path.join(GetResourcePath(propsResource), 'icons')); } catch (e) { return; }
  let n = 0;
  for (const name of names || []) {
    if (!NAME.test(name)) continue;
    if (!force && fs.existsSync(path.join(OWN_DIR, name + '.png'))) continue; // the studio's own shot wins
    const file = path.join(dir, name + '.png');
    if (!fs.existsSync(file)) continue;
    try {
      emit('nzc:icon:copy', name, fs.readFileSync(file).toString('base64'));
      n++;
    } catch (e) { /* skip it */ }
  }
  if (n > 0) console.log(`^5[${RESOURCE}]^0 copied ${n} chainkit icon(s) into the inventory images`);
});
