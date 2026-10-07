// Writes icon PNGs from the icon studio. Plain Node built-ins only.
const fs = require('fs');
const path = require('path');

const RESOURCE = GetCurrentResourceName();
const OWN_DIR = path.resolve(path.join(GetResourcePath(RESOURCE), 'icons'));

function inventoryDir() {
    if (GetResourceState('ox_inventory') === 'missing') return null;
    const p = GetResourcePath('ox_inventory');
    return p ? path.resolve(path.join(p, 'web', 'images')) : null;
}

function writeInto(dir, name, buf) {
    const out = path.resolve(path.join(dir, name + '.png'));
    if (!out.startsWith(dir + path.sep)) throw new Error('path escaped');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(out, buf);
    return out;
}

on('nayzeee-backpack:icon:write', (src, name, b64, toInventory) => {
    let ok = false;
    let where = '';
    try {
        if (!/^[\w-]+$/.test(name)) throw new Error('bad name');
        const data = b64.startsWith('data:') ? b64.slice(b64.indexOf(',') + 1) : b64;
        const buf = Buffer.from(data, 'base64');
        // PNG signature check, so nothing else ever lands on disk
        if (buf.length < 8 || buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a png');

        writeInto(OWN_DIR, name, buf);
        ok = true;

        if (toInventory) {
            const inv = inventoryDir();
            if (inv) {
                writeInto(inv, name, buf);
                where = ' → ox_inventory/web/images';
            }
        }
        console.log(`^2[nayzeee-backpack]^0 icon saved: ${name}.png (${Math.round(buf.length / 1024)} KB)${where}`);
    } catch (err) {
        console.log(`^1[nayzeee-backpack]^0 icon ${name} failed: ${err && err.message ? err.message : err}`);
    }
    emit('nayzeee-backpack:icon:written', src, name, ok, where);
});
