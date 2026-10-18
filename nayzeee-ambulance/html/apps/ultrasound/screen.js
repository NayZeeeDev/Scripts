/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Ultrasound cart monitor (DUI)          module: ultrasound
   Mirrors the medic's live B-mode picture on the cart's own screen with the
   same imaging engine as the NUI (window.NZUS from app.js Part 1).
   Lua: client/modules/ultrasound_world.lua (startDui / duiSend). Messages are
   listed in screen.html. Generic device labelling only.
   ═══════════════════════════════════════════════════════════ */
(() => {
  'use strict';
  const U = window.NZUS;
  if (!U) return;
  const $ = s => document.querySelector(s);
  const root = $('#scr');
  const bm = $('.bm'), mm = $('.mm'), ecgC = $('.ecg');
  const LAB = {
    liver: 'LIVER', spleen: 'SPLEEN', kidney: 'KIDNEY', diaphragm: 'DIAPHRAGM', pleural: 'PLEURAL FLUID', spine: 'SPINE',
    free_ruq: "FLUID · MORISON'S", free_luq: 'FLUID · SPLENORENAL', free_pelvis: 'FREE FLUID', bladder: 'BLADDER', uterus: 'UTERUS',
    prostate: 'PROSTATE', rv: 'RV', lv: 'LV', ra: 'RA', la: 'LA', effusion: 'EFFUSION', rib: 'RIB', pleura: 'PLEURA',
  };
  const WNAME = {
    ruq: ['w_ruq', 'Right upper quadrant'], luq: ['w_luq', 'Left upper quadrant'], pelvis: ['w_pelvis', 'Pelvis'],
    cardiac: ['w_cardiac', 'Heart · below the breastbone'], lung_r: ['w_lung_r', 'Right chest wall'], lung_l: ['w_lung_l', 'Left chest wall'],
    bowel: ['no_window', 'no window'], air: ['no_contact', 'Probe off the skin'],
  };
  const WSHORT = { ruq: 'RUQ', luq: 'LUQ', pelvis: 'PELV', cardiac: 'HEART', lung_r: 'LUNG R', lung_l: 'LUNG L', bowel: '—', air: '—' };
  const RHY = { sinus: 'SINUS', stach: 'S.TACH', sbrady: 'S.BRADY', afib: 'AFIB', vf: 'VF', vt: 'VT', pea: 'PEA', asystole: 'ASYSTOLE' };
  let LOC = {};
  const T = (k, fb) => (LOC[k] !== undefined ? String(LOC[k]) : fb);

  const S = {
    kind: 'scan', seed: 4512, views: {}, labels: true, sex: 'm', inited: false, frozen: false, held: false,
    win: 'air', contact: false, q: 0, shift: 0, vis: 1, depth: 16, gain: 55, focus: 8, mm: false, tilt: 0,
    needle: null, eff: null, vit: {}, lastMsg: 0,
  };
  let engine = null, trace = null;
  const scenes = {};
  const sceneFor = w => scenes[w] || (scenes[w] = U.scene(w, Object.assign({ sex: S.sex }, S.views[w] || {}), S.seed));

  /* ── layout: canvases follow the screen size the DUI was created with ── */
  function fit() {
    const box = $('.img').getBoundingClientRect();
    const w = Math.max(64, Math.floor(box.width)), h = Math.max(64, Math.floor(box.height));
    const bh = S.mm ? Math.floor(h * 0.58) : h;
    if (bm.width !== w || bm.height !== bh) { bm.width = w; bm.height = bh; if (engine) engine.redraw(); }
    if (mm.width !== w || mm.height !== h - bh) { mm.width = w; mm.height = Math.max(1, h - bh); mctx.fillStyle = '#000'; mctx.fillRect(0, 0, mm.width, mm.height); mx = 0; }
    const eb = ecgC.getBoundingClientRect();
    if (eb.width && (ecgC.width !== Math.floor(eb.width) || ecgC.height !== Math.floor(eb.height))) { ecgC.width = Math.floor(eb.width); ecgC.height = Math.floor(eb.height); }
  }
  const mctx = mm.getContext('2d');
  let mx = 0;

  function boot() {
    if (engine) return;
    engine = U.BMode(bm, { seed: S.seed, lines: 120, samples: 200 });
    engine.set({ depth: S.depth, gain: S.gain, focus: S.focus, contact: false });
    if (window.NZA && NZA.vitals && NZA.vitals.Trace) {
      try { trace = NZA.vitals.Trace(ecgC, { type: 'ecg', rhythm: 'sinus', rate: 80, color: '#1fe0b0' }); } catch (e) { trace = null; }
    }
  }

  /* ── depth scale + labels + needle guide drawn over the sector ── */
  const ov = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  ov.setAttribute('class', 'ov');
  $('.img').appendChild(ov);
  function overlay() {
    if (!engine) return;
    const st = engine.st, sec = engine.sector(), W = bm.width, H = bm.height;
    ov.setAttribute('viewBox', `0 0 ${W} ${$('.img').clientHeight}`);
    let s = '';
    const xr = Math.min(W - 10, sec.x0 + (sec.R0 + st.depth) * Math.sin(sec.HALF) * sec.k + 14);
    for (let cm = 0; cm <= st.depth; cm++) {
      const y = sec.y0 + cm * sec.k;
      if (y > H - 2) break;
      const big = cm % 5 === 0;
      s += `<line class="tk" x1="${xr}" y1="${y.toFixed(1)}" x2="${xr + (big ? 7 : 4)}" y2="${y.toFixed(1)}"/>`;
      if (big && cm) s += `<text class="tn" x="${xr + 10}" y="${(y + 3).toFixed(1)}">${cm}</text>`;
    }
    const fy = sec.y0 + st.focus * sec.k;
    s += `<path class="fc" d="M${xr - 2} ${fy.toFixed(1)}l-6 -4v8z"/>`;
    const mk = engine.toPx(-sec.R0 * Math.sin(sec.HALF) * 1.6 - 0.9, sec.zTop - 0.1);
    s += `<g class="mkr" transform="translate(${mk[0].toFixed(1)} ${(mk[1] + 4).toFixed(1)})"><circle r="3.6"/><circle r="1.4" class="in"/></g>`;
    if (S.mm) { const a = engine.toPx(0, 0), b = engine.toPx(0, st.depth); s += `<line class="ml" x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${Math.min(b[1], H)}"/>`; }
    if (S.labels && st.scene && st.scene.labels && st.contact && st.q > 0.45) {
      (st.scene.labels(st) || []).forEach(l => {
        const p = engine.toPx(l.x, l.z);
        if (p[1] < sec.y0 + 6 || p[1] > H - 6 || p[0] < 8 || p[0] > W - 30 || !engine.fromPx(p[0], p[1])) return;
        s += `<text class="lab ${l.small ? 'sm' : ''} ${l.tone || ''}" x="${p[0].toFixed(1)}" y="${p[1].toFixed(1)}">${esc(T('lab_' + l.k, LAB[l.k] || l.k))}</text>`;
      });
    }
    const n = st.needle;
    if (n && n.guide) {
      const a = engine.toPx(n.ex, n.ez), b = engine.toPx(n.ex + Math.sin(n.ang) * 16, n.ez + Math.cos(n.ang) * 16);
      s += `<line class="ng" x1="${a[0].toFixed(1)}" y1="${a[1].toFixed(1)}" x2="${b[0].toFixed(1)}" y2="${b[1].toFixed(1)}"/>`;
    }
    ov.innerHTML = s;
  }
  const esc = v => String(v).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  /* ── M-mode sweep (centre line over time) ── */
  function sweepM() {
    if (!S.mm || !engine || mm.height < 4) return;
    const col = engine.mline(mm.height);
    const img = mctx.createImageData(2, mm.height);
    for (let i = 0; i < mm.height; i++) {
      const v = Math.round(col[i] * 255);
      for (let k = 0; k < 2; k++) { const p = (i * 2 + k) * 4; img.data[p] = v * 0.97; img.data[p + 1] = v * 0.99; img.data[p + 2] = v; img.data[p + 3] = 255; }
    }
    mctx.putImageData(img, mx, 0);
    mctx.fillStyle = 'rgba(31,224,176,.8)'; mctx.fillRect((mx + 3) % mm.width, 0, 1, mm.height);
    mctx.fillStyle = '#000'; mctx.fillRect((mx + 2) % mm.width, 0, 1, mm.height);
    mx = (mx + 2) % mm.width;
  }

  /* ── side panel ── */
  function side() {
    const w = S.contact ? S.win : 'air';
    const nm = WNAME[w] || WNAME.bowel;
    $('.wname').textContent = T(nm[0], nm[1]);
    $('.win').textContent = S.contact ? (WSHORT[w] || '—') : '—';
    const bars = Math.round(S.q * 5);
    document.querySelectorAll('.qbar i').forEach((b, i) => b.classList.toggle('on', i < bars));
    $('.dep').textContent = Math.round(S.depth);
    $('.gai').textContent = Math.round(S.gain);
    $('.foc').textContent = Math.round(S.focus);
    root.classList.toggle('nocontact', !S.contact && !S.needle);
    root.classList.toggle('frozen', S.frozen || S.held);
    root.classList.toggle('mmode', S.mm);
    const v = S.vit || {};
    const hr = Math.round(v.ecgRate || v.hr || 0);
    $('.hrv').textContent = hr ? String(hr) : '--';
    $('.rh').textContent = T('rh_' + (v.rhythm || 'sinus'), RHY[v.rhythm] || (v.rhythm || '').toUpperCase() || '—');
    $('.rh').className = `rh ${v.rhythm === 'vf' || v.rhythm === 'vt' || v.rhythm === 'asystole' || v.rhythm === 'pea' ? 'red' : ''}`;
    $('.spo2').textContent = v.spo2 ? `${Math.round(v.spo2)}` : '--';
    $('.spo2').className = `spo2 ${v.spo2 && v.spo2 < 92 ? 'red' : ''}`;
    $('.bp').textContent = v.sys ? `${Math.round(v.sys)}/${Math.round(v.dia || v.sys * 0.62)}` : '--/--';
    $('.rr').textContent = v.rr ? String(Math.round(v.rr)) : '--';
    const nd = $('.ndl');
    if (S.needle && S.needle.on) { nd.textContent = `NDL ${S.needle.depth.toFixed(1)} cm`; nd.classList.add('on'); } else nd.classList.remove('on');
  }

  function clock() {
    const d = new Date();
    $('.clk').textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  }

  /* ── message handling ── */
  function apply(d) {
    if (!d || typeof d !== 'object') return;
    S.lastMsg = performance.now();
    if (d.type === 'init') {
      LOC = d.locale && typeof d.locale === 'object' ? d.locale : {};
      document.querySelectorAll('[data-l]').forEach(el => { const k = el.getAttribute('data-l'); if (LOC[k] !== undefined) el.textContent = LOC[k]; });
      S.kind = d.kind === 'pericardio' ? 'pericardio' : 'scan';
      S.seed = (d.seed || 4512) >>> 0;
      S.views = d.views && typeof d.views === 'object' ? d.views : {};
      S.labels = d.labels !== false;
      S.sex = d.sex === 'f' ? 'f' : 'm';
      Object.keys(scenes).forEach(k => delete scenes[k]);
      if (engine) { engine = null; }
      boot();
      if (S.kind === 'pericardio') { S.depth = 18; S.focus = 9; engine.set({ effusion: d.mm || 12 }); }
      $('.study').textContent = d.study || `US-${String(S.seed % 100000).padStart(5, '0')}`;
      root.classList.remove('standby');
      root.classList.toggle('peri', S.kind === 'pericardio');
      S.inited = true; S.held = false;
    } else if (d.type === 'probe') {
      if (!S.inited) return;
      S.held = false;
      S.contact = d.contact === true;
      S.win = typeof d.win === 'string' ? d.win : 'air';
      ['q', 'shift', 'vis', 'depth', 'gain', 'focus', 'tilt'].forEach(k => { if (typeof d[k] === 'number' && isFinite(d[k])) S[k] = d[k]; });
      S.frozen = d.frozen === true;
      if (S.mm !== (d.mm === true)) { S.mm = d.mm === true; requestAnimationFrame(fit); }
    } else if (d.type === 'needle') {
      if (!S.inited) return;
      if (d.off) { S.needle = null; return; }
      S.needle = { on: (+d.depth || 0) > 0.05, guide: true, ex: -6.6, ez: 0, ang: +d.ang || 0.86, depth: +d.depth || 0, inPlane: 1 };
      if (typeof d.eff === 'number') S.eff = d.eff;
      if (typeof d.q === 'number') S.q = d.q;
      S.contact = true; S.win = 'cardiac'; S.frozen = false;
    } else if (d.type === 'vitals') {
      S.vit = d.vitals && typeof d.vitals === 'object' ? d.vitals : {};
      if (trace && trace.set) trace.set({ rhythm: S.vit.rhythm || 'sinus', rate: Math.max(S.vit.ecgRate || S.vit.hr || 0, S.vit.rhythm === 'asystole' ? 0 : 20) });
      if (engine) engine.set({ hr: S.vit.ecgRate || S.vit.hr || 80, rhythm: S.vit.rhythm || 'sinus', rr: S.vit.rr || 14, arrest: S.vit.rhythm === 'asystole' || S.vit.rhythm === 'pea' });
    } else if (d.type === 'freeze') {
      S.held = true;
    }
  }
  window.addEventListener('message', e => {
    let d = e.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (err) { return; } }
    apply(d);
  });

  /* ── render loop (~18 fps: plenty for a texture on a prop) ── */
  let last = performance.now(), acc = 0, sideT = 0;
  function loop(now) {
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    acc += dt; sideT += dt;
    if (engine && acc >= 0.055) {
      const fdt = Math.min(acc, 0.12);
      acc = 0;
      fit();
      const contact = S.contact || !!(S.needle);
      const w = S.kind === 'pericardio' ? 'cardiac' : S.win;
      const sc = contact && w !== 'air' ? sceneFor(w) : null;
      const patch = { contact, q: contact ? S.q : 0, shift: S.shift, vis: S.vis, depth: S.depth, gain: S.gain, focus: S.focus, frozen: S.frozen || S.held, tilt: S.tilt, needle: S.needle };
      if (sc) patch.scene = sc;
      if (S.eff !== null) patch.effusion = S.eff;
      engine.set(patch);
      engine.frame(fdt);
      if (!S.frozen && !S.held) sweepM();
      overlay();
    }
    if (sideT > 0.2) { sideT = 0; side(); clock(); }
    requestAnimationFrame(loop);
  }
  requestAnimationFrame(loop);
  window.addEventListener('resize', fit);

  /* ── browser demo: screen.html?demo=1 ── */
  if (/[?&]demo=1/.test(location.search)) {
    const views = { ruq: { pleural: 45, free: 9 }, luq: {}, pelvis: { free: 11 }, cardiac: { effusion: 14, collapse: true }, lung_r: { slide: true }, lung_l: { ptx: true, size: 30 } };
    apply({ type: 'init', kind: 'scan', seed: 4512, study: 'US-04512', views, labels: true, sex: 'm' });
    apply({ type: 'vitals', vitals: { hr: 118, ecgRate: 118, rhythm: 'stach', sys: 84, dia: 52, spo2: 91, rr: 26 } });
    const order = ['ruq', 'cardiac', 'lung_l', 'pelvis'];
    const DEP = { ruq: 16, cardiac: 18, lung_l: 8, pelvis: 14 };
    let i = 0;
    const next = () => { const w = order[i++ % order.length]; apply({ type: 'probe', contact: true, win: w, q: 0.95, shift: 0, vis: 1, depth: DEP[w], gain: 55, focus: DEP[w] / 2, mm: w === 'lung_l' }); };
    next();
    const p = new URLSearchParams(location.search).get('win');
    if (p) apply({ type: 'probe', contact: true, win: p, q: 0.95, shift: 0, vis: 1, depth: DEP[p] || 16, gain: 55, focus: (DEP[p] || 16) / 2, mm: p === 'lung_l' });
    else setInterval(next, 4000);
  }
})();
