(() => {
  const NH = window.NH;

  NH.IS_GAME = typeof window.GetParentResourceName === 'function';
  NH.RES = NH.IS_GAME ? window.GetParentResourceName() : 'nayzeee-hud';

  NH.post = (name, data) => {
    if (!NH.IS_GAME) return Promise.resolve(null);
    return fetch(`https://${NH.RES}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then(r => r.json()).catch(() => null);
  };

  NH.DEFAULTS = {
    v: 1,
    season: 'auto', particles: true, decor: true, seasonAccent: true,
    accent: '#b8f02a', panelAlpha: 0.78, scale: 1, units: 'mph', cinematic: false,
    sound: true, volume: 0.6,
    status: {
      enabled: true, style: 'ring', color: 'vibrant', dir: 'row', autoHide: true,
      show: { health: true, armor: true, hunger: true, thirst: true, stamina: true, stress: true, oxygen: true, voice: true },
    },
    speedo: { style: 'modern', lights: true, chime: true, tick: true, fuelWarn: true },
    air: { style: 'pfd' },
    boat: { units: 'kts' },
    cycle: { style: 'watch' },
    map: { mode: 'vehicle', frame: true, street: true, streetOnFoot: true, sign: true, signStyle: 'us', blink: true, compass: true, compassStyle: 'tape', compassWhen: 'always' },
    info: { enabled: true, style: 'pills', job: true, cash: true, bank: true, id: true, headshot: true },
    weapon: { enabled: true, style: 'card', image: true },
    clock: { enabled: true, style: 'pill', day: true, h24: false, source: 'game', weather: true },
    watermark: { enabled: true, style: 'stack', effect: 'gloss' },
    layout: {},
  };

  NH.clone = o => JSON.parse(JSON.stringify(o));

  NH.merge = (base, over) => {
    if (!over || typeof over !== 'object') return base;
    for (const k of Object.keys(over)) {
      const v = over[k];
      if (v && typeof v === 'object' && !Array.isArray(v) && base[k] && typeof base[k] === 'object') NH.merge(base[k], v);
      else if (v !== undefined && v !== null) base[k] = v;
    }
    return base;
  };

  NH.getPath = (obj, path) => path.split('.').reduce((o, k) => (o == null ? o : o[k]), obj);
  NH.setPath = (obj, path, value) => {
    const keys = path.split('.');
    let o = obj;
    for (let i = 0; i < keys.length - 1; i++) o = o[keys[i]] = o[keys[i]] || {};
    o[keys[keys.length - 1]] = value;
  };

  // Server-side defaults from config.lua
  NH.applyServerDefaults = (d) => {
    if (!d) return;
    const D = NH.DEFAULTS;
    if (d.season) D.season = d.season;
    if (d.accent) D.accent = d.accent;
    if (d.units) D.units = d.units;
    if (d.statusStyle) D.status.style = d.statusStyle;
    if (d.speedoStyle) D.speedo.style = d.speedoStyle;
    if (d.minimap) D.map.mode = d.minimap;
  };

  NH.hexToRgb = (hex) => {
    const m = /^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i.exec(hex || '');
    return m ? `${parseInt(m[1], 16)},${parseInt(m[2], 16)},${parseInt(m[3], 16)}` : '184,240,42';
  };

  NH.money = n => '$' + Math.round(Number(n) || 0).toLocaleString('en-US');

  NH.S = {};        // raw state pushed from Lua
  NH.cfg = {
    watermark: { enabled: true, title: 'NAYZEEE', subtitle: 'ROLEPLAY', logo: '' },
    weaponImages: 'https://docs.fivem.net/weapons/%s.png',
    belt: true, keys: [], framework: 'standalone',
  };
  NH.saved = NH.clone(NH.DEFAULTS);  // persisted settings
  NH.cur = NH.saved;                 // currently applied (draft while settings are open)
  NH.map = { l: 1.6, b: 97.2, w: 14.06, h: 17.62 };
})();
