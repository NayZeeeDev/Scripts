(() => {
  const NH = window.NH;
  const W = NH.W;

  // Which widgets care about which keys from Lua
  const GROUP = {
    h: 'st', a: 'st', st: 'st', ox: 'st', tk: 'st', hu: 'st', th: 'st', sr: 'st', vr: 'st', rd: 'st',
    cash: 'info', bank: 'info', job: 'info', grd: 'info', hs: 'info', id: 'info',
    hr: 'clk', mn: 'clk', dow: 'clk', wx: 'clk',
    hdg: 'cmp', str: 'loc', crs: 'loc', zn: 'loc', pst: 'loc', dir: 'loc', lim: 'loc',
    spd: 'veh', rpm: 'veh', gr: 'veh', fu: 'veh', en: 'veh', li: 'veh', lk: 'veh', ind: 'veh', eng: 'veh', bl: 'veh', cr: 'veh', hb: 'veh', odo: 'veh',
    alt: 'air', agl: 'air', vs: 'air', pt: 'air', rl: 'air', vh: 'air', lg: 'air',
    wp: 'wpn', wl: 'wpn', clip: 'wpn', ammo: 'wpn',
    vm: 'mode', radar: 'mode', pz: 'mode',
  };

  // ---------------- Vehicle derived state ----------------
  const MUL = { mph: 2.236936, kmh: 3.6, kts: 1.943844 };
  const LABEL = { mph: 'MPH', kmh: 'KMH', kts: 'KTS' };

  NH.vehUnitKey = () => {
    const m = NH.S.vm;
    if (m === 'air') return 'kts';
    if (m === 'boat' && NH.cur.boat.units === 'kts') return 'kts';
    return NH.cur.units === 'kmh' ? 'kmh' : 'mph';
  };
  NH.vehUnit = () => LABEL[NH.vehUnitKey()];

  let bpm = 72, tripStart = null;
  NH.resetTrip = () => { tripStart = null; };
  NH.vehState = () => {
    const S = NH.S;
    if (!S.vm && NH.editing) return Object.assign({}, NH.DEMO_SPEEDO, { unit: NH.vehUnit(), fuelWarn: NH.cur.speedo.fuelWarn });
    const u = NH.vehUnitKey();
    const sp = Math.round((S.spd || 0) / 10 * MUL[u]);
    const max = u === 'kmh' ? 300 : u === 'kts' ? 160 : 180;
    const km = NH.cur.units === 'kmh';
    if (tripStart === null && S.odo != null) tripStart = S.odo;
    const dist = (S.odo || 0) / (km ? 1000 : 1609.34);
    const trip = Math.max(0, (S.odo || 0) - (tripStart ?? S.odo ?? 0)) / (km ? 1000 : 1609.34);
    bpm += ((70 + sp * 2.1) - bpm) * 0.15;
    const now = new Date();
    const v = {
      sp, sr: Math.min(1, sp / max), rpm: (S.rpm || 0) / 100, gear: String(S.gr ?? 'N'),
      fuel: S.fu ?? 100, eng: S.en ?? 100, unit: LABEL[u],
      odo: String(Math.floor(dist)).padStart(6, '0') + (km ? ' KM' : ' MI'),
      belt: !!S.bl, hb: !!S.hb, li: S.li || 0, lk: !!S.lk, ind: S.ind || 0, cr: !!S.cr, running: !!S.eng,
      fuelWarn: NH.cur.speedo.fuelWarn,
      time: `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`,
      bpm: Math.round(bpm), cad: sp > 1 ? Math.min(125, Math.round(55 + sp * 1.4)) : 0, dist: trip.toFixed(2), dunit: km ? 'KM' : 'MI',
    };
    NH.veh = { spUnit: u === 'kmh' ? sp : Math.round((S.spd || 0) / 10 * (NH.cur.units === 'kmh' ? MUL.kmh : MUL.mph)) };
    return v;
  };

  // ---------------- Sounds (WebAudio, no files) ----------------
  let ctx = null;
  const tone = (freq, dur, vol, type = 'sine', when = 0) => {
    if (!NH.cur.sound) return;
    try {
      ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
      const t = ctx.currentTime + when;
      const o = ctx.createOscillator(), gn = ctx.createGain();
      o.type = type; o.frequency.value = freq;
      gn.gain.setValueAtTime(0, t);
      gn.gain.linearRampToValueAtTime(vol * NH.cur.volume, t + 0.005);
      gn.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(gn).connect(ctx.destination);
      o.start(t); o.stop(t + dur + 0.02);
    } catch (_) { /* audio unavailable */ }
  };
  const SFX = {
    buckle: () => { tone(1500, 0.05, 0.25, 'square'); tone(2100, 0.06, 0.22, 'square', 0.07); },
    unbuckle: () => { tone(1300, 0.05, 0.2, 'square'); tone(800, 0.08, 0.18, 'square', 0.06); },
    chime: () => { tone(880, 0.45, 0.18); tone(660, 0.6, 0.16, 'sine', 0.3); },
    tick: () => tone(2400, 0.018, 0.12, 'square'),
    tock: () => tone(1700, 0.018, 0.1, 'square'),
    click: () => tone(1800, 0.02, 0.1, 'square'),
  };
  NH.sfx = n => SFX[n] && SFX[n]();

  let chimeT = null, tickT = null, lastBelt = null, tickFlip = false;
  function vehSounds() {
    const S = NH.S;
    if (S.bl !== lastBelt) {
      if (lastBelt !== null && S.vm && S.hb) NH.sfx(S.bl ? 'buckle' : 'unbuckle');
      lastBelt = S.bl;
    }
    const mph = (S.spd || 0) / 10 * MUL.mph;
    const wantChime = NH.cur.speedo.chime && S.vm === 'car' && S.hb && !S.bl && S.eng && mph > 12;
    if (wantChime && !chimeT) { NH.sfx('chime'); chimeT = setInterval(() => NH.sfx('chime'), 2600); }
    if (!wantChime && chimeT) { clearInterval(chimeT); chimeT = null; }
    const wantTick = NH.cur.speedo.tick && S.vm && (S.ind || 0) > 0;
    if (wantTick && !tickT) tickT = setInterval(() => NH.sfx((tickFlip = !tickFlip) ? 'tick' : 'tock'), 420);
    if (!wantTick && tickT) { clearInterval(tickT); tickT = null; }
  }

  // ---------------- Toast ----------------
  let toastT = null;
  NH.toast = (msg) => {
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toastT);
    toastT = setTimeout(() => t.classList.remove('show'), 1600);
  };

  // ---------------- Apply settings ----------------
  NH.applySettings = () => {
    const c = NH.cur;
    const root = document.documentElement;
    root.style.setProperty('--pa', c.panelAlpha);
    NH.applySeason(c);
    document.body.classList.toggle('cinematic', !!c.cinematic && !NH.editing);
    for (const id in W) if (W[id].apply) W[id].apply();
    renderAll();
  };

  function renderMode() {
    const S = NH.S;
    const b = document.body.classList;
    b.toggle('in-veh', !!S.vm);
    b.toggle('paused', !!S.pz);
    b.toggle('radar', !!S.radar);
    document.body.dataset.vm = S.vm || '';
  }

  function renderAll() {
    renderMode();
    const all = { st: 1, info: 1, clk: 1, cmp: 1, loc: 1, veh: 1, air: 1, wpn: 1, mode: 1, edit: NH.editing ? 1 : 0 };
    for (const id in W) if (W[id].render) W[id].render(all);
    NH.updateVisibility();
    NH.place();
  }

  NH.update = (d) => {
    const groups = {};
    for (const k in d) {
      NH.S[k] = d[k];
      groups[GROUP[k] || 'x'] = 1;
    }
    if (groups.mode) { renderMode(); if ('vm' in d) { NH.resetTrip(); if (!('odo' in d)) delete NH.S.odo; } }
    if (groups.veh) groups.loc = 1; // speeding check on the sign
    for (const id in W) if (W[id].render) W[id].render(groups);
    if (groups.mode || groups.wpn || groups.st) {
      NH.updateVisibility();
      if (groups.mode) requestAnimationFrame(NH.place); // after the speedometer is in the DOM
    }
    if (groups.veh || groups.mode) vehSounds();
  };

  // ---------------- Messages from Lua ----------------
  window.addEventListener('message', (e) => {
    const m = e.data;
    if (!m || !m.t) return;
    switch (m.t) {
      case 'u': NH.update(m.d); break;
      case 'init':
        NH.applyServerDefaults(m.defaults);
        if (m.watermark) NH.cfg.watermark = Object.assign(NH.cfg.watermark, m.watermark);
        if (m.weaponImages !== undefined) NH.cfg.weaponImages = m.weaponImages;
        if (m.keys) NH.cfg.keys = m.keys;
        NH.cfg.belt = m.belt;
        NH.saved = NH.merge(NH.clone(NH.DEFAULTS), m.settings || {});
        NH.cur = NH.saved;
        NH.applySettings();
        break;
      case 'map': NH.map = m.m; NH.place(); break;
      case 'vis': document.body.classList.toggle('hidden', !m.v); break;
      case 'settings': if (m.open) NH.settingsUI.open(); else NH.settingsUI.close(); break;
      case 'panel': if (m.open) NH.panel.open(m.s); else NH.panel.close(false); break;
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' && e.key !== 'Backspace' && e.key !== 'F7') return;
    if (e.key === 'Backspace' && /INPUT|TEXTAREA/.test(document.activeElement?.tagName)) return;
    if (NH.editing) { NH.settingsUI.editLayout(false); return; }
    if (NH.panel.isOpen) { NH.panel.close(); return; }
    if (NH.settingsUI.isOpen && e.key === 'Escape') NH.settingsUI.close();
  });

  window.addEventListener('resize', () => NH.place());

  // ---------------- Boot ----------------
  NH.buildWidgets();
  NH.panel.build();
  NH.settingsUI.build();
  NH.applySettings();
  if (NH.IS_GAME) NH.post('ready');
  else NH.demo();
})();
