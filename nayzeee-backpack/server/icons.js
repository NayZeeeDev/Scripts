// Writes icon PNGs from the icon studio into this resource's icons/ folder.
// Plain Node built-ins only. The copy into ox_inventory is done from Lua
// (server/icons.lua): newer FXServer builds block Node from writing into
// another resource unless server.cfg grants it.
const fs = require('fs');
const path = require('path');

const RESOURCE = GetCurrentResourceName();
const OWN_DIR = path.resolve(path.join(GetResourcePath(RESOURCE), 'icons'));

on('nayzeee-backpack:icon:write', (src, name, b64) => {
    let ok = false;
    try {
        if (!/^[\w-]+$/.test(name)) throw new Error('bad name');
        const data = b64.startsWith('data:') ? b64.slice(b64.indexOf(',') + 1) : b64;
        const buf = Buffer.from(data, 'base64');
        // PNG signature check, so nothing else ever lands on disk
        if (buf.length < 8 || buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a png');

        const out = path.resolve(path.join(OWN_DIR, name + '.png'));
        if (!out.startsWith(OWN_DIR + path.sep)) throw new Error('path escaped');
        if (!fs.existsSync(OWN_DIR)) fs.mkdirSync(OWN_DIR, { recursive: true });
        fs.writeFileSync(out, buf);
        ok = true;
        console.log(`^2[nayzeee-backpack]^0 icon saved: icons/${name}.png (${Math.round(buf.length / 1024)} KB)`);
    } catch (err) {
        console.log(`^1[nayzeee-backpack]^0 icon ${name} failed: ${err && err.message ? err.message : err}`);
    }
    emit('nayzeee-backpack:icon:written', src, name, ok, b64);
});
