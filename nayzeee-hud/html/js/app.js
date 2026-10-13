(() => {
  const NH = window.NH;
  const W = NH.W;

  // Which widgets care about which keys from Lua
  const GROUP = {
    h: 'st', a: 'st', st: 'st', ox: 'st', tk: 'st', hu: 'st', th: 'st', sr: 'st', vr: 'st', rd: 'st',
    cash: 'info', bank: 'info', dm: 'info', gng: 'info', pn: 'info', pl: 'info', plm: 'info', av: 'info', ava: 'info', dom: 'clk', mon: 'clk', rt: 'st', vrc: 'st', vrn: 'st', vrd: 'st', ch: 'xh', hn: 'veh', nos: 'veh', nosOn: 'veh', job: 'info', grd: 'info', hs: 'info', id: 'info',
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
      sp1: ((S.spd || 0) / 10 * MUL[u]).toFixed(1), sp, sr: Math.min(1, sp / max), rpm: (S.rpm || 0) / 100, gear: String(S.gr ?? 'N'),
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
    fuel: () => { tone(740, 0.18, 0.14); tone(740, 0.18, 0.14, 'sine', 0.25); },
    note: () => { tone(1320, 0.07, 0.08); tone(1760, 0.1, 0.07, 'sine', 0.06); },
    nerr: () => { tone(420, 0.09, 0.1, 'triangle'); tone(320, 0.14, 0.09, 'triangle', 0.08); },
  };
  NH.sfx = n => SFX[n] && SFX[n]();

  let chimeT = null, tickT = null, lastBelt = null, tickFlip = false, lastFuel = null;
  function vehSounds() {
    const S = NH.S;
    if (S.vm && S.fu !== undefined) {
      if (NH.cur.speedo.fuelWarn && lastFuel !== null && lastFuel >= 15 && S.fu < 15) NH.sfx('fuel');
      lastFuel = S.fu;
    } else lastFuel = null;
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
    if (NH.syncSquadsSettings) NH.syncSquadsSettings();
    NH.applyUI();
    NH.applyCrosshair();
    teamProxy();
  };

  // ---------------- Team HUD in Edit layout ----------------
  // A stand-in for the squads team HUD, so it moves and resizes with the rest of the layout and saves with it.
  let proxy = null, pdrag = null;
  const placeTeam = (el, pos) => {
    const set = pos && typeof pos.x === 'number';
    Object.assign(el.style, set
      ? { left: `${pos.x}%`, top: `${pos.y}%`, right: 'auto', bottom: 'auto', transformOrigin: 'top left' }
      : { left: '', top: '', right: '', bottom: '', transformOrigin: '' });
  };
  function teamProxy() {
    const d = NH.cfg.squadsData, st = NH.cur.squads;
    const show = NH.editing && window.TeamHud && d && st && st.hud !== false && (d.features || {}).Hud !== false;
    if (!show) { pdrag = null; if (proxy) { proxy.remove(); proxy = null; } return; }
    if (pdrag) return;
    const el = TeamHud.preview(st.hudStyle, { ...st, imgTpl: NH.cfg.weaponImages });
    el.classList.remove('tpv');
    el.id = 'teamProxy';
    el.dataset.label = 'Team HUD';
    placeTeam(el, st.hudPos);
    if (proxy) proxy.replaceWith(el); else document.body.appendChild(el);
    proxy = el;
  }
  document.addEventListener('pointerdown', (e) => {
    const el = NH.editing && e.target.closest('#teamProxy');
    if (!el) return;
    const r = el.getBoundingClientRect();
    pdrag = { dx: e.clientX - r.left, dy: e.clientY - r.top, w: r.width, h: r.height };
    el.classList.add('dragging');
    e.preventDefault();
    e.stopPropagation();
  }, true);
  document.addEventListener('pointermove', (e) => {
    if (!pdrag || !proxy) return;
    const x = Math.max(0, Math.min(window.innerWidth - pdrag.w, e.clientX - pdrag.dx));
    const y = Math.max(0, Math.min(window.innerHeight - pdrag.h, e.clientY - pdrag.dy));
    placeTeam(proxy, { x: x / window.innerWidth * 100, y: y / window.innerHeight * 100 });
  });
  document.addEventListener('pointerup', () => {
    if (!pdrag) return;
    pdrag = null;
    if (!proxy) return;
    proxy.classList.remove('dragging');
    const r = proxy.getBoundingClientRect();
    NH.cur.squads.hudPos = { x: +(r.left / window.innerWidth * 100).toFixed(2), y: +(r.top / window.innerHeight * 100).toFixed(2) };
    NH.syncSquadsSettings();
    NH.settingsUI?.markDirty();
  });
  document.addEventListener('wheel', (e) => {
    if (!NH.editing || !e.target.closest('#teamProxy')) return;
    const st = NH.cur.squads;
    st.hudScale = Math.max(70, Math.min(130, (st.hudScale || 100) + (e.deltaY < 0 ? 5 : -5)));
    TeamHud.applyVars(proxy, st);
    NH.syncSquadsSettings();
    NH.settingsUI?.markDirty();
    NH.toast?.(`Team HUD: ${st.hudScale}%`);
  }, { passive: true });
  document.addEventListener('contextmenu', (e) => {
    if (!NH.editing || !e.target.closest('#teamProxy')) return;
    e.preventDefault();
    NH.cur.squads.hudPos = false;
    NH.applySettings();
    NH.settingsUI?.markDirty();
  });

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
    if ('sr' in d && NH.cfg.stressNotify && NH.S.sr !== undefined && d.sr > NH.S.sr) NH.toast('Feeling more stressed');
    for (const k in d) {
      NH.S[k] = d[k];
      groups[GROUP[k] || 'x'] = 1;
    }
    if (groups.mode) { renderMode(); W.street.apply(); if ('vm' in d) { NH.resetTrip(); if (!('odo' in d)) delete NH.S.odo; } }
    if (groups.veh) groups.loc = 1; // speeding check on the sign
    for (const id in W) if (W[id].render) W[id].render(groups);
    if (groups.mode || groups.wpn || groups.st) {
      NH.updateVisibility();
      if (groups.mode) requestAnimationFrame(NH.place); // after the speedometer is in the DOM
    }
    if (groups.veh || groups.mode) vehSounds();
    if (groups.xh) NH.renderCrosshair();
  };

  // ---------------- Messages from Lua ----------------
  // ---------------- Squads (own page in a frame, so its styles never touch the HUD) ----------------
  let sqFrame = null, sqFocused = false;
  NH.squadsFrame = () => {
    if (sqFrame) return sqFrame;
    sqFrame = document.createElement('iframe');
    sqFrame.id = 'squads';
    sqFrame.src = 'squads/index.html';
    sqFrame.setAttribute('allowtransparency', 'true');
    document.body.appendChild(sqFrame);
    return sqFrame;
  };
  // squads player settings are edited in the HUD settings; the squads frame draws the team HUD
  NH.setSquadsData = (d) => {
    NH.cfg.squadsData = d;
    NH.DEFAULTS.squads = NH.clone(d.defaults || {});
  };
  NH.toSquads = (action, data) => { if (sqFrame) sqFrame.contentWindow.postMessage({ action, data }, '*'); };
  NH.syncSquadsSettings = () => { if (NH.cfg.squadsData && NH.cur.squads) NH.toSquads('settings', NH.cur.squads); };
  NH.sqFocus = (on) => sqFocus(on);
  const sqFocus = (on) => {
    sqFocused = on;
    document.body.classList.toggle('squads-focus', on);
    if (on && sqFrame) { sqFrame.focus(); try { sqFrame.contentWindow.focus(); } catch (_) { /* ignore */ } }
  };

  window.addEventListener('message', (e) => {
    const m = e.data;
    if (!m) return;
    if (!m.t) { // squads messages use { action, data }
      if (m.action && sqFrame && e.source !== sqFrame.contentWindow) sqFrame.contentWindow.postMessage(m, '*');
      return;
    }
    switch (m.t) {
      case 'u': NH.update(m.d); break;
      case 'init':
        NH.applyServerDefaults(m.defaults);
        if (m.watermark) {
          NH.cfg.watermark = Object.assign(NH.cfg.watermark, m.watermark);
          if (m.watermark.showText === false) NH.DEFAULTS.watermark.show = 'logo';
        }
        if (m.weaponImages !== undefined) NH.cfg.weaponImages = m.weaponImages;
        NH.cfg.crosshair = m.crosshair !== false;
        if (m.mapFit) NH.cfg.mapFit = m.mapFit;
        if (m.keys) NH.cfg.keys = m.keys;
        NH.cfg.belt = m.belt;
        if (m.squadsData) NH.setSquadsData(m.squadsData);
        NH.cfg.stressNotify = !!m.stressNotify;
        NH.popsAfter = Date.now() + 5000;
        if (m.squads) NH.squadsFrame();
        NH.saved = NH.merge(NH.clone(NH.DEFAULTS), m.settings || {});
        if (NH.cfg.squadsData) NH.saved.squads = NH.merge(NH.clone(NH.DEFAULTS.squads), NH.cfg.squadsData.settings || {}); // the squads module owns these
        for (const id of ['street', 'sign']) {
          const L = NH.saved.layout && NH.saved.layout[id];
          if (L && L.x != null) { delete L.x; delete L.y; } // older pinned spot: let it dock again (keeps its size)
        }
        NH.cur = NH.saved;
        NH.applySettings();
        break;
      case 'map': NH.map = m.m; NH.place(); break;
      case 'sqfocus': sqFocus(!!m.on); break;
      case 'accounts': W.info.pop(m.kind, 0, m.amount); break;
      case 'vis':
        document.body.classList.toggle('hidden', !m.v);
        if (m.v) NH.popsAfter = Date.now() + 5000; // character just loaded: balances jump, don't pop
        break;
      case 'settings': if (m.open) NH.settingsUI.open(); else NH.settingsUI.close(); break;
      case 'notify': NH.notify(m); break;
      case 'progress': NH.progress(m); break;
      case 'textui': NH.textUI(m); break;
      case 'panel': if (m.open) NH.panel.open(m.s); else NH.panel.close(false); break;
    }
  });

  document.addEventListener('keydown', (e) => {
    if (sqFocused && sqFrame) { // keys pressed before the frame took focus still reach the squads menu
      sqFrame.contentWindow.document.dispatchEvent(new KeyboardEvent('keydown', { key: e.key, shiftKey: e.shiftKey, bubbles: true }));
      return;
    }
    if (e.key !== 'Escape' && e.key !== 'Backspace' && e.key !== 'F7') return;
    if (e.key === 'Backspace' && /INPUT|TEXTAREA/.test(document.activeElement?.tagName)) return;
    if (NH.editing) { NH.settingsUI.editLayout(false); return; }
    if (NH.panel.isOpen) { NH.panel.close(); return; }
    if (NH.settingsUI.isOpen && e.key === 'Escape') NH.settingsUI.close();
  });

  window.addEventListener('resize', () => NH.place());

  // ---------------- Boot ----------------
  NH.buildWidgets();
  NH.buildUI();
  NH.buildCrosshair();
  NH.panel.build();
  NH.settingsUI.build();
  NH.applySettings();
  if (NH.IS_GAME) NH.post('ready');
  else NH.demo();
})();
