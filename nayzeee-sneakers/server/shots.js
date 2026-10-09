// Sneaker Studio writer: saves the small PNGs the studio keyed in the NUI into shots/ and keeps
// shots/index.json up to date. Plain Node built-ins only, no image work happens here.
// The copy into ox_inventory is done from Lua (server/studio.lua): newer FXServer builds block
// Node from writing into another resource unless server.cfg grants it.
// own scope: FiveM runs every server .js of a resource in one context, so top-level names would clash
(() => {
  const fs = require('fs');
  const path = require('path');

  const RESOURCE = GetCurrentResourceName();
  const DIR = path.resolve(path.join(GetResourcePath(RESOURCE), 'shots'));
  const INDEX = path.join(DIR, 'index.json');
  const NAME = /^nzs_[a-z0-9_]{1,60}$/;

  function readIndex() {
    try {
      const list = JSON.parse(fs.readFileSync(INDEX, 'utf8'));
      return Array.isArray(list) ? list : [];
    } catch (e) { return []; }
  }

  // rebuild the index from the files on disk (picks up photos copied in by hand)
  function rebuild() {
    try {
      if (!fs.existsSync(DIR)) fs.mkdirSync(DIR, { recursive: true });
      const names = fs.readdirSync(DIR).filter((f) => f.endsWith('.png')).map((f) => f.slice(0, -4)).filter((n) => NAME.test(n)).sort();
      fs.writeFileSync(INDEX, JSON.stringify(names));
      emit('nzs:shots:indexed', names.length);
    } catch (err) {
      console.log(`^1[${RESOURCE}]^0 could not index shots/: ${err && err.message ? err.message : err}`);
    }
  }
  setImmediate(rebuild);

  on('nzs:shots:write', (src, name, b64) => {
    let ok = false;
    try {
      if (!NAME.test(String(name))) throw new Error('bad name');
      const buf = Buffer.from(b64.startsWith('data:') ? b64.slice(b64.indexOf(',') + 1) : b64, 'base64');
      // PNG signature check, so nothing else ever lands on disk
      if (buf.length < 8 || buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a png');

      const out = path.resolve(path.join(DIR, name + '.png'));
      if (!out.startsWith(DIR + path.sep)) throw new Error('path escaped');
      if (!fs.existsSync(DIR)) fs.mkdirSync(DIR, { recursive: true });
      fs.writeFileSync(out, buf);

      const list = readIndex();
      if (!list.includes(name)) { list.push(name); list.sort(); fs.writeFileSync(INDEX, JSON.stringify(list)); }
      ok = true;
      console.log(`^2[${RESOURCE}]^0 sneaker studio saved shots/${name}.png (${Math.round(buf.length / 1024)} KB)`);
    } catch (err) {
      console.log(`^1[${RESOURCE}]^0 sneaker studio ${name} failed: ${err && err.message ? err.message : err}`);
    }
    emit('nzs:shots:written', src, name, ok, b64);
  });
})();
