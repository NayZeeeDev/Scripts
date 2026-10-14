/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · field — field resuscitation (7 steps) and IV cannulation

   Lua → JS
     open      { mode = 'resus'|'iv', plan, keys, locale, focus = { patient, site, stand, kit } }
     step      { proc = 'binder'|'io'|'resus'|'reassess'|'iv', status = 'run'|'skip'|'blocked', data, reason }
     outcome   { proc, ok, outcome | reason }           (server answer for a finished step)
     vitals    { hr, sys, dia, map, spo2, rr, temp, etco2, rhythm, bleed, state, injury }
     clot      server model of the resuscitate step (see server/modules/field_procs.lua)
     popped    {}                                         the clot gave way
     focus     { what }                                   camera focus key highlight
     summary   { before, after, steps[], devices, given, clot }   step 7
     bags      { saline, txa, foil, bags[], infusions[] }
   JS → Lua (NUI callbacks 'field:<event>')
     result { proc, result }  skip { proc }  abort {}  done {}  focus { what }
     binderDrop {} → { ok }   phase { proc, phase, site }   drill { x, y, angle, dx, dy, lift, depth }
     needle {} → { ok, needles }   hang { kind, serial?, rate } → { ok, inf }   rate { id, rate }
     takedown { id } → { ok }   txa { seconds } → { ok }   foil {} → { ok }   nibp {}   ivTq { on }
   ═══════════════════════════════════════════════════════════ */
(() => {
  const APP = 'field';
  const { clamp, esc } = NZA;
  const icon = n => NZA.icon(n);
  const W = () => window.innerWidth, H = () => window.innerHeight;
  const now = () => performance.now();
  let loc = {};
  function L(k, f, vars) {
    let s = loc[k] !== undefined ? loc[k] : NZA.t(`field.${k}`, f);
    if (vars) Object.keys(vars).forEach(v => { s = String(s).split(`{${v}}`).join(vars[v]); });
    return s;
  }
  const post = (ev, d) => NZA.post(`${APP}:${ev}`, d || {});
  const smooth = x => x * x * (3 - 2 * x);
  const fmt1 = n => (Math.round(n * 10) / 10).toFixed(1);
  const grade = s => (s >= 92 ? 'S' : s >= 80 ? 'A' : s >= 65 ? 'B' : s >= 50 ? 'C' : s >= 35 ? 'D' : 'F');

  /* ═══════════════════════════ STATE ═══════════════════════════ */
  const S = {
    open: false, mode: 'resus', plan: {}, keys: {}, preview: false,
    proc: null, status: '', data: {}, n: 1, total: 7, phase: '',
    vit: {}, bleed: 0, injury: null, band: [60, 70], clot: null,
    mouse: { x: 0, y: 0, down: false }, held: {}, results: [], focus: 'patient',
    b: null, io: null, rs: null, iv: null, waiting: false,
  };
  const ui = { host: null, focus: null, dev: null, inf: null, ov: null, pp: null, ghost: null, scene: null };
  let raf = 0, lastT = 0;

  const anchors = () => (NZA.apps[APP] ? NZA.apps[APP].anchors.map : {}) || {};
  function apx(id) {
    const a = anchors()[id];
    if (!a || a.visible === false) return null;
    return { x: a.x * W(), y: a.y * H() };
  }
  const pxScale = () => H() / 1080;

  /* ═══════════════════════════ SMALL WIDGETS ═══════════════════════════ */
  function Syringe(host, o) {
    o = Object.assign({ cap: 10, vol: 0, mode: 'push', fluid: 'clear', band: null, maxRate: 1, flashAt: null, label: '' }, o);
    const root = NZA.el('div', 'syr');
    const fluidCol = { clear: 'rgba(170,215,235,.55)', lido: 'rgba(150,200,255,.6)', blood: 'rgba(150,20,28,.92)', marrow: 'rgba(120,14,20,.95)', txa: 'rgba(200,235,225,.6)' };
    root.innerHTML = `
      <svg viewBox="0 0 300 70">
        <defs><linearGradient id="syrg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="rgba(255,255,255,.22)"/><stop offset=".5" stop-color="rgba(255,255,255,.05)"/><stop offset="1" stop-color="rgba(255,255,255,.14)"/></linearGradient></defs>
        <rect x="2" y="33" width="26" height="4" rx="1" fill="#c8d0d4"/>
        <rect x="26" y="28" width="20" height="14" rx="3" fill="#2b3135" stroke="rgba(255,255,255,.25)"/>
        <rect class="liq" x="46" y="22" width="0" height="26" fill="${fluidCol[o.fluid] || fluidCol.clear}"/>
        <rect x="46" y="20" width="200" height="30" rx="4" fill="url(#syrg)" stroke="rgba(255,255,255,.45)" stroke-width="1.4"/>
        <g class="grad" stroke="rgba(255,255,255,.45)" stroke-width="1"></g>
        <rect x="244" y="14" width="8" height="42" rx="2" fill="#3a4246"/>
        <g class="pl"><rect class="pist" x="0" y="21" width="9" height="28" rx="2" fill="#1d2023"/><rect class="rod" x="9" y="31" width="52" height="8" fill="#aeb8bd"/>
          <rect class="thumb" x="58" y="12" width="9" height="46" rx="3" fill="#e9eef0" stroke="#08afa2" stroke-width="2"/></g>
      </svg>
      <div class="syr-row"><span>${esc(o.label)}</span><span><b class="vol">0.0</b> / ${o.cap} ml</span></div>
      ${o.band ? '<div class="syr-meter"></div><div class="syr-row"><span class="rl"></span><span><b class="rate">0.00</b> ml/s</span></div>' : ''}`;
    host.appendChild(root);
    const g = root.querySelector('.grad');
    for (let i = 0; i <= o.cap; i++) {
      const x = 46 + (i / o.cap) * 200;
      g.insertAdjacentHTML('beforeend', `<line x1="${x}" y1="20" x2="${x}" y2="${i % 5 === 0 ? 29 : 25}"/>`);
    }
    let vol = o.vol, rate = 0, dragging = false, lastMove = now(), acc = 0, flashed = false, fluid = o.fluid, dead = false;
    const draw = () => {
      const x = 46 + clamp(vol / o.cap, 0, 1) * 200;
      root.querySelector('.liq').setAttribute('width', Math.max(0, x - 46));
      root.querySelector('.liq').setAttribute('fill', fluidCol[fluid] || fluidCol.clear);
      root.querySelector('.pl').setAttribute('transform', `translate(${x},0)`);
      root.querySelector('.vol').textContent = fmt1(vol);
      if (o.band) {
        const m = root.querySelector('.syr-meter');
        const tone = rate > o.band[1] ? 'red' : rate >= o.band[0] ? '' : 'amber';
        m.innerHTML = NZA.ui.meterHTML({ value: clamp(rate / o.maxRate, 0, 1), zone: [o.band[0] / o.maxRate, Math.min(1, o.band[1] / o.maxRate)], tone, lg: true });
        const rb = root.querySelector('.rate');
        rb.textContent = rate.toFixed(2);
        rb.className = `rate ${rate > o.band[1] ? 'red' : rate >= o.band[0] && rate > 0.01 ? 'teal' : ''}`;
        root.querySelector('.rl').textContent = rate < 0.01 ? L('syr_idle', 'Drag the plunger') : rate > o.band[1] ? L('syr_fast', 'Too fast') : rate >= o.band[0] ? L('syr_band', 'In the band') : L('syr_slow', 'Slow');
      }
    };
    const onDown = e => { if (e.button !== 0 || dead) return; dragging = true; root.classList.add('drag'); e.preventDefault(); e.stopPropagation(); };
    const onMove = e => {
      if (!dragging || dead) return;
      const px = root.offsetWidth * (NZA.zoom || 1);
      const dv = (e.movementX / Math.max(40, px)) * 300 / 200 * o.cap;
      let nv = vol + dv;
      if (o.mode === 'push') nv = Math.min(vol, nv); else nv = Math.max(vol, nv);
      nv = clamp(nv, 0, o.cap);
      const d = Math.abs(nv - vol);
      if (d > 0) { acc += d; vol = nv; lastMove = now(); }
      if (o.flashAt !== null && !flashed && o.mode === 'pull' && vol >= o.flashAt) { flashed = true; fluid = 'marrow'; o.onFlash && o.onFlash(); }
      draw();
      o.onChange && o.onChange(vol, rate);
    };
    const onUp = () => { if (!dragging) return; dragging = false; root.classList.remove('drag'); o.onRelease && o.onRelease(vol, rate); };
    root.addEventListener('mousedown', onDown);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    let tPrev = now();
    const tick = () => {
      if (dead) return;
      const t = now(), dt = Math.max(0.001, (t - tPrev) / 1000); tPrev = t;
      const inst = acc / dt; acc = 0;
      const k = 1 - Math.exp(-dt / 0.35);
      rate += (inst - rate) * k;
      if (t - lastMove > 600) rate *= 0.85;
      if (rate < 0.005) rate = 0;
      if (o.band) draw();
      o.onTick && o.onTick(vol, rate, dragging);
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    draw();
    return {
      el: root, get vol() { return vol; }, get rate() { return rate; }, get dragging() { return dragging; },
      set(v) { vol = clamp(v, 0, o.cap); draw(); },
      fluid(f) { fluid = f; draw(); },
      destroy() { dead = true; window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp); root.remove(); },
    };
  }

  function gaugeSVG() {
    let ticks = '';
    for (let v = 0; v <= 300; v += 10) {
      const a = (-120 + (v / 300) * 240) * Math.PI / 180;
      const r1 = v % 50 === 0 ? 40 : 45, r2 = 50;
      ticks += `<line x1="${59 + Math.sin(a) * r1}" y1="${59 - Math.cos(a) * r1}" x2="${59 + Math.sin(a) * r2}" y2="${59 - Math.cos(a) * r2}" stroke="${v >= 250 ? '#ff6b70' : 'rgba(255,255,255,.55)'}" stroke-width="${v % 50 === 0 ? 2 : 1}"/>`;
      if (v % 100 === 0) ticks += `<text x="${59 + Math.sin(a) * 31}" y="${62 - Math.cos(a) * 31}" text-anchor="middle" font-size="8.5" font-weight="700" fill="rgba(255,255,255,.7)" font-family="Lexend">${v}</text>`;
    }
    return `<svg viewBox="0 0 118 118">
      <circle cx="59" cy="59" r="57" fill="#15181a" stroke="#050505" stroke-width="2"/>
      <circle cx="59" cy="59" r="53" fill="#f2f3f0"/>
      <circle cx="59" cy="59" r="53" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="1"/>
      <g style="filter:invert(1)">${ticks}</g>
      <text x="59" y="78" text-anchor="middle" font-size="6.5" font-weight="700" fill="#555" font-family="Lexend" letter-spacing="1">mmHg</text>
      <rect x="53" y="84" width="12" height="12" rx="3" fill="#08afa2"/><path d="M56 87h5v2.6h-2.6v3.4H56z" fill="#fff"/>
      <g class="ndl"><path d="M57.6 59 L59 14 L60.4 59 Z" fill="#e5484d"/><circle cx="59" cy="59" r="5" fill="#222"/></g>
    </svg>`;
  }

  function arcSVG(maxAngle) {
    const R = 36, cx = 43, cy = 44;
    const pt = deg => { const a = (180 + (deg / 45) * 180) * Math.PI / 180; return [cx + Math.cos(a) * R, cy + Math.sin(a) * R]; };
    const arc = (a, b, col, w) => { const p1 = pt(a), p2 = pt(b); return `<path d="M${p1[0]} ${p1[1]} A${R} ${R} 0 0 1 ${p2[0]} ${p2[1]}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round"/>`; };
    return `<svg viewBox="0 0 86 52">${arc(0, 45, 'rgba(255,255,255,.12)', 6)}${arc(0, maxAngle, 'rgba(61,220,132,.75)', 6)}<line class="an" x1="${cx}" y1="${cy}" x2="${cx}" y2="${cy - R + 4}" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/></svg>`;
  }

  /* ═══════════════════════════ LAYOUT ═══════════════════════════ */
  function build() {
    const host = ui.host;
    if (ui.pp) { ui.pp.destroy(); ui.pp = null; }
    if (ui.ov) { ui.ov.remove(); ui.ov = null; }
    if (ui.ghost) { ui.ghost.remove(); ui.ghost = null; }
    clearMarks();
    host.innerHTML = '';
    ui.focus = NZA.el('div', 'fd-focus nza-hud solid nza-int');
    host.appendChild(ui.focus);
    ui.dev = NZA.el('div', 'fd-dev nza-int');
    host.appendChild(ui.dev);
    ui.inf = NZA.el('div', 'fd-inf nza-hud solid nza-int');
    ui.inf.style.display = 'none';
    host.appendChild(ui.inf);
    const layer = document.getElementById('nza-layer-anchors');
    ui.ov = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    ui.ov.setAttribute('class', 'fd-ov');
    layer.appendChild(ui.ov);
    ui.ghost = NZA.el('div', 'fd-ghost');
    ui.ghost.style.display = 'none';
    layer.appendChild(ui.ghost);
    ui.pp = NZA.ui.ProcPanel(host, {
      step: 1, total: S.total, title: '', text: '', stats: [], tools: [],
      hints: [{ keys: [L('k_rclick', 'Right click')], label: L('h_orbit', 'orbit') }, { keys: ['Shift', L('k_rclick', 'Right click')], label: L('h_pan', 'pan') }],
      onAbort: () => abort(), onTool: k => tool(k),
    });
    const rawSet = ui.pp.set;
    ui.pp.set = n => { if (n && 'text' in n) lastText = n.text; if (n && 'stats' in n) lastStats = ''; return rawSet(n); };
    renderFocus();
  }

  function renderFocus() {
    if (!ui.focus) return;
    const f = S.keys.focus || { patient: 'F1', site: 'F2', stand: 'F3', kit: 'F4' };
    const items = S.mode === 'iv'
      ? [['patient', f.patient, L('f_patient', 'Patient')], ['site', f.site, L('f_arm', 'Arm')]]
      : [['patient', f.patient, L('f_patient', 'Patient')], ['site', f.site, L('f_site', 'Site')], ['stand', f.stand, L('f_stand', 'IV stand')], ['kit', f.kit, L('f_kit', 'Kit')]];
    const standOk = S.proc === 'resus' || S.proc === 'reassess' || (S.rs && S.rs.stand);
    ui.focus.innerHTML = items.map(([id, key, label]) => `<button data-f="${id}" class="${S.focus === id ? 'on' : ''} ${id === 'stand' && !standOk ? 'off' : ''}"><kbd>${esc(key)}</kbd>${esc(label)}</button>`).join('')
      + `<span class="sep"></span><span class="tip"><b>${esc(L('k_scroll', 'Scroll'))}</b> ${esc(L('h_zoom', 'zoom'))}</span>`;
    ui.focus.querySelectorAll('button').forEach(b => b.addEventListener('click', () => focusCam(b.dataset.f)));
  }
  function focusCam(what) {
    if (what === 'stand' && !(S.proc === 'resus' || S.proc === 'reassess' || (S.rs && S.rs.stand))) return;
    S.focus = what; renderFocus(); post('focus', { what }); NZA.audio.click(700);
  }

  function devFrame(title, body, opts = {}) {
    ui.dev.innerHTML = `<div class="dev ${opts.cls || ''}">
      <div class="d-top"><div class="dev-brand"><span class="nz-mark"></span>NAYZEEE · ${esc(opts.brand || L('dev_brand', 'Field'))}</div><span class="d-hw"><span class="dev-btn">${icon('minus')}</span><span class="dev-btn">${icon('plus')}</span><span class="dev-btn">${icon('power')}</span></span><span class="dev-led ${opts.led || ''}"></span></div>
      <div class="dev-screen d-scr"><div class="d-cap"><span class="dev-led ${opts.capLed || ''}"></span>${esc(title)}<span class="r">${esc(opts.right || '')}</span></div>${body}</div>
    </div>`;
    ui.dev.style.display = '';
    return ui.dev;
  }
  const q = sel => ui.host && ui.host.querySelector(sel);

  // readout above the step card: a MAP dial (IV: needle angle) + an instrument list
  function readout() {
    if (S.mode === 'iv') {
      const iv = S.iv || {}, band = S.data.angle || [15, 30];
      const a = iv.angle || 0;
      const off = a && (a < band[0] || a > band[1]);
      return {
        wide: { label: L('st_angle', 'Angle'), value: a ? Math.round(a) : '--', unit: '°', tone: off ? 'amber' : 'teal',
          meter: { value: a / 45, zone: [band[0] / 45, band[1] / 45], tone: off ? 'amber' : '' }, caption: L('cap_angle', 'Insert at {a}–{b}°', { a: band[0], b: band[1] }), captionTone: off ? 'amber' : '' },
        stats: [
          { id: 'site', label: L('st_site', 'Site'), value: S.data.siteLabel || L('site_forearm', 'Forearm'), small: true },
          { id: 'att', label: L('st_attempts', 'Attempts'), value: `${iv.attempts || 1}/${S.data.attempts || 2}` },
          { id: 'g', label: L('st_cannula', 'Cannula'), value: `${S.data.gauge || 18}G` },
        ],
      };
    }
    const map = S.proc === 'resus' && S.clot ? S.clot.map : (S.vit.map || null);
    const [lo, hi] = S.band;
    const low = (S.data && S.data.lowMap) || 52;
    const tone = !map ? '' : map < low ? 'red' : map < lo ? 'amber' : map > hi ? 'amber' : 'teal';
    const b = S.bleed || 0;
    const stats = [
      { id: 'bleed', label: L('st_bleed', 'Bleed'), value: b >= 10 ? Math.round(b) : fmt1(b), unit: 'mL/min', tone: b >= 25 ? 'red' : b >= 5 ? 'amber' : 'teal' },
      { id: 'inj', label: L('st_injury', 'Injury'), value: S.injury ? (S.injury.regionLabel || S.injury.region) : '--', small: true },
    ];
    if (S.metric) stats.push(Object.assign({ id: 'metric' }, S.metric));
    return {
      wide: { label: L('st_map', 'MAP'), value: map || '--', unit: 'mmHg', tone,
        meter: { value: map ? (map - 30) / 80 : 0, zone: [(lo - 30) / 80, (hi - 30) / 80], tone: tone === 'teal' ? '' : tone },
        caption: L('cap_target', 'Target {a}–{b}', { a: lo, b: hi }), captionTone: tone === 'teal' ? 'teal' : '' },
      stats,
    };
  }
  function metric(m) { S.metric = m; stats(); }

  let lastStats = '', lastText = '';
  function stats() {
    if (!ui.pp) return;
    const r = readout(), key = JSON.stringify(r);
    if (key !== lastStats) { lastStats = key; ui.pp.set({ stats: r.stats, wide: r.wide }); }
  }
  function setText(t) { if (ui.pp && t !== lastText) { lastText = t; ui.pp.set({ text: t }); } }

  function stepNames() {
    if (S.mode === 'iv') return IV_STEPS.map(ivTitle);
    return [L('t_binder', 'Pelvic binder'), L('t_site', 'Choose IO site'), L('t_drill', 'Drill'), L('t_confirm', 'Confirm'), L('t_flush', 'Confirm and flush'), L('t_resus', 'Resuscitate'), L('t_reassess', 'Reassess')];
  }
  const hintsCam = () => [{ keys: [L('k_rclick', 'Right click')], label: L('h_orbit', 'orbit') }, { keys: ['Shift', L('k_rclick', 'Right click')], label: L('h_pan', 'pan') }];

  /* ═══════════════════════════ MARKERS & OVERLAY ═══════════════════════════ */
  const markerIds = new Set();
  function mark(id, opts) { markerIds.add(id); return NZA.ui.Marker(APP, id, opts); }
  function clearMarks() { markerIds.forEach(id => { try { NZA.ui.Marker(APP, id, {}).remove(); } catch (e) { /* gone */ } }); markerIds.clear(); }
  function ov(html) { if (ui.ov) ui.ov.innerHTML = html || ''; }
  function ghost(show, html, x, y, near) {
    if (!ui.ghost) return;
    ui.ghost.style.display = show ? '' : 'none';
    if (!show) return;
    if (html !== null && html !== undefined) ui.ghost.innerHTML = html;
    ui.ghost.style.left = `${x}px`; ui.ghost.style.top = `${y}px`;
    ui.ghost.classList.toggle('near', !!near);
  }

  /* ═══════════════════════════ STEP CONTROL ═══════════════════════════ */
  const STEP_N = { binder: 1, io: 2, resus: 6, reassess: 7 };
  const H_ = {};   // handlers per proc

  function setStep(proc, status, data, reason) {
    const prev = S.proc && H_[S.proc];
    if (prev && prev.leave) prev.leave();
    clearMarks(); ov(''); ghost(false);
    ui.inf.style.display = 'none';
    S.proc = proc; S.status = status; S.data = data || {}; S.reason = reason; S.waiting = false;
    if (S.data.band) S.band = S.data.band;
    if (S.data.injury) S.injury = S.data.injury;
    if (S.data.bleed !== undefined) S.bleed = S.data.bleed;
    S.n = S.mode === 'iv' ? 1 : (STEP_N[proc] || 1);
    if (ui.host) ui.host.classList.remove('grab', 'aim');
    S.metric = null;
    const fl = ui.pp.el.querySelector('.pp-flash'); if (fl) fl.className = 'pp-flash';
    ui.pp.set({ step: S.n, total: S.total, tag: '', titleTone: '', hints: hintsCam(), steps: stepNames() });
    stats();
    renderFocus();
    const h = H_[proc];
    if (!h) return;
    if (status === 'run') h.enter();
    else h.blocked ? h.blocked(status, reason) : blockedPanel(proc, status, reason);
  }

  const PROC_EN = { binder: 'Pelvic binder', io: 'Intraosseous access', resus: 'Resuscitate', reassess: 'Reassess', iv: 'IV cannulation' };
  function blockedPanel(proc, status, reason) {
    const title = L(`t_${proc}`, PROC_EN[proc] || proc);
    if (status === 'easy') {
      ui.pp.set({ title, titleTone: '', text: reason || L('easy_text', 'Easy mode — hold still while you work.'), tools: [] });
      devFrame(title.toUpperCase(), `<div class="d-note">${NZA.rich(reason || L('easy_text', 'Easy mode — hold still while you work.'))}</div>`, {});
      return;
    }
    const text = status === 'skip' ? (reason || L('skip_text', 'Not needed — skipping.')) : (reason || L('blocked_text', 'You can not do this step right now.'));
    ui.pp.set({ title, titleTone: status === 'skip' ? 'ok' : 'bad', text, tools: [{ key: 'N', label: L('tool_continue', 'Continue'), icon: 'arrow-r', state: 'active' }] });
    devFrame(title.toUpperCase(), `<div class="d-note">${NZA.rich(text)}</div>`, { capLed: status === 'skip' ? '' : 'red' });
  }

  function sendResult(proc, result) {
    if (S.waiting) return;
    S.waiting = true;
    S.lastResult = { proc, result };
    ui.pp.flash('ok', L('checking', 'Done — checking…'), 0);
    if (S.preview) { setTimeout(() => NZA.apps[APP].msg.outcome({ proc, ok: true, outcome: { score: result.score, grade: grade(result.score), msg: L('ok_generic', 'Done') } }), 500); return; }
    post('result', { proc, result });
  }
  function skip() {
    if (S.waiting) return;
    S.waiting = true;
    post('skip', { proc: S.proc });
    if (S.preview) S.waiting = false;
  }
  function abort() {
    post('abort', {});
    if (S.preview) NZA.toast({ title: L('aborted', 'Aborted'), message: L('aborted_text', 'Field resuscitation stopped.'), type: 'error' });
  }

  function tool(k) {
    const h = H_[S.proc];
    if (S.status !== 'run') { if (String(k).toUpperCase() === 'N') skip(); return; }
    if (h && h.tool) h.tool(String(k));
  }

  /* ═══════════════════════════ STEP 1 · PELVIC BINDER ═══════════════════════════ */
  H_.binder = {
    enter() {
      const d = S.data;
      S.b = { phase: 'drop', drag: false, tension: 0, attempts: 1, tab: null, band: d.band || [60, 80] };
      this.ui();
    },
    ui() {
      const b = S.b, d = S.data;
      const why = d.indicated ? L(`why_${d.why || 'bleed'}`, 'Pelvic injury') : L('why_none', 'No pelvic injury found');
      if (b.phase === 'drop') {
        ui.pp.set({
          title: L('t_binder', 'Pelvic binder'), tag: why,
          text: L('binder_drop', 'Drag the **binder** from the kit onto the pelvis and let go.'),
          tools: [{ key: '1', label: L('tool_binder', 'Pelvic binder'), icon: 'shield', state: 'active', sub: d.count !== undefined ? `×${d.count}` : '' },
            { key: 'N', label: d.indicated ? L('tool_skip', 'Skip') : L('tool_skip_ok', 'Not needed — skip'), icon: 'arrow-r' }],
        });
        mark('kit', { label: L('m_binder', 'Pelvic binder'), tone: 'teal', dot: 'white' });
        mark('pelvis', { label: L('m_drop', 'Drop the binder here'), dot: 'ring' });
      } else if (b.phase === 'strap') {
        ui.pp.set({
          title: L('t_binder', 'Pelvic binder'), tag: why,
          text: L('binder_strap', 'Pull the strap tab across the body into the green band and let go. Tension {t}%.', { t: Math.round(b.tension) }),
          tools: [{ key: '1', label: L('tool_binder', 'Pelvic binder'), icon: 'shield', state: 'done' }],
        });
        mark('strapB', { label: '', dot: 'white' });
      }
      this.dev();
    },
    dev() {
      const b = S.b;
      const [lo, hi] = b.band;
      const ticks = [0, 20, 40, 60, 80, 100].map(v => `<span class="tick" style="bottom:${v / 120 * 100}%"></span><span class="tick r" style="bottom:${v / 120 * 100}%"></span>`).join('');
      devFrame(L('d_binder', 'Strap tension'), `
        <div class="d-row">
          <div class="d-tension"><span class="zone" style="bottom:${lo / 120 * 100}%;height:${(hi - lo) / 120 * 100}%"></span>${ticks}<span class="fill" style="height:0"></span></div>
          <div class="d-binder">
            <div><div class="d-lbl">${esc(L('d_tension', 'Tension'))}</div><div class="d-big tn">0<span class="u">%</span></div></div>
            <svg viewBox="0 0 200 84"><path d="M10 50 Q100 4 190 50" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="22" stroke-linecap="round"/>
              <path class="bstrap" d="M10 50 Q100 4 190 50" fill="none" stroke="#08afa2" stroke-width="22" stroke-linecap="round" stroke-dasharray="0 400"/>
              <rect x="88" y="16" width="24" height="16" rx="3" fill="#0b0d0e" stroke="rgba(255,255,255,.4)"/><text x="100" y="72" text-anchor="middle" font-size="9" font-family="Lexend" font-weight="700" fill="rgba(255,255,255,.4)" letter-spacing="2">${esc(L('d_pelvis', 'PELVIS'))}</text></svg>
            <div class="d-note bnote">${esc(b.phase === 'drop' ? L('d_binder_drop', 'Slide it under the pelvis first.') : L('d_binder_band', 'Let go inside the band ({lo}–{hi}%).', { lo, hi }))}</div>
          </div>
        </div>
        <div class="d-chips"><span class="d-chip ${b.phase === 'strap' ? 'on' : ''}">${esc(L('d_placed', 'Under pelvis'))}</span><span class="d-chip">${esc(L('d_attempt', 'Attempt'))} ${b.attempts}</span></div>`,
      { brand: L('dev_binder', 'Pelvic binder'), right: `${lo}–${hi}%` });
    },
    devTick() {
      const b = S.b;
      const fill = q('.d-tension .fill');
      if (!fill) return;
      const t = b.tension;
      fill.style.height = `${clamp(t / 120, 0, 1) * 100}%`;
      fill.className = `fill ${t > b.band[1] ? 'red' : t >= b.band[0] ? '' : 'amber'}`;
      const tn = q('.tn'); if (tn) tn.innerHTML = `${Math.round(t)}<span class="u">%</span>`;
      tn.className = `d-big tn ${t > b.band[1] ? 'red' : t >= b.band[0] ? 'teal' : ''}`;
      const st = q('.bstrap'); if (st) st.setAttribute('stroke-dasharray', `${clamp(t / 100, 0, 1.2) * 220} 400`);
      metric({ label: L('st_tension', 'Tension'), value: Math.round(t), unit: '%', tone: t > b.band[1] ? 'red' : t >= b.band[0] ? 'teal' : t > 0 ? 'amber' : '' });
    },
    tool(k) {
      if (k.toUpperCase() === 'N') return skip();
      if (k === '1' && S.b.phase === 'drop') { S.b.carry = true; S.b.drag = true; ui.host.classList.add('grab'); }
    },
    down(e) {
      const b = S.b;
      if (b.phase === 'drop') {
        const k = apx('kit');
        if (k && Math.hypot(e.clientX - k.x, e.clientY - k.y) < 90 * pxScale()) { b.drag = true; ui.host.classList.add('grab'); NZA.audio.click(500); }
      } else if (b.phase === 'strap') {
        const tab = b.tab || apx('strapA');
        if (tab && Math.hypot(e.clientX - tab.x, e.clientY - tab.y) < 70 * pxScale()) { b.drag = true; ui.host.classList.add('grab'); NZA.audio.click(500); }
      }
    },
    move(e) {
      const b = S.b;
      if (b.phase === 'drop' && b.drag) {
        const p = apx('pelvis');
        const near = p && Math.hypot(e.clientX - p.x, e.clientY - p.y) < 80 * pxScale();
        ghost(true, `<span class="ic">${icon('shield')}</span>${esc(L('tool_binder', 'Pelvic binder'))}`, e.clientX, e.clientY, near);
      }
      if (b.phase === 'strap' && b.drag) {
        const A = apx('strapA'), B = apx('strapB');
        if (!A || !B) return;
        const vx = B.x - A.x, vy = B.y - A.y, len2 = vx * vx + vy * vy || 1;
        const t = ((e.clientX - A.x) * vx + (e.clientY - A.y) * vy) / len2;
        const prev = b.tension;
        b.tension = clamp(t * 100, 0, 120);
        b.tab = { x: A.x + vx * clamp(t, 0, 1.2), y: A.y + vy * clamp(t, 0, 1.2) };
        if (Math.floor(prev / 10) !== Math.floor(b.tension / 10)) NZA.audio.tick();
        ui.pp.set({ text: L('binder_strap', 'Pull the strap tab across the body into the green band and let go. Tension {t}%.', { t: Math.round(b.tension) }) });
        this.devTick();
      }
    },
    up(e) {
      const b = S.b;
      if (b.phase === 'drop' && b.drag) {
        b.drag = false; ui.host.classList.remove('grab'); ghost(false);
        const p = apx('pelvis');
        if (p && Math.hypot(e.clientX - p.x, e.clientY - p.y) < 80 * pxScale()) {
          b.phase = 'wait';
          const go = r => {
            if (!S.b || S.proc !== 'binder') return;
            if (r && r.ok === false) { b.phase = 'drop'; ui.pp.flash('bad', (r && r.msg) || L('binder_drop_fail', 'Could not place the binder.')); return; }
            b.phase = 'strap'; clearMarks(); NZA.audio.success();
            ui.pp.flash('ok', L('binder_placed', 'Binder under the pelvis. Now tighten the strap.'));
            this.ui();
          };
          if (S.preview) go({ ok: true }); else post('binderDrop', {}).then(go);
        } else {
          ui.pp.flash('warn', L('binder_miss', 'Drop it on the pelvis marker.'));
        }
      } else if (b.phase === 'strap' && b.drag) {
        b.drag = false; ui.host.classList.remove('grab');
        const t = b.tension, [lo, hi] = b.band;
        if (t >= lo && t <= hi) {
          b.phase = 'done';
          const mid = (lo + hi) / 2;
          const score = Math.round(clamp(100 - Math.abs(t - mid) * 2 - (b.attempts - 1) * 12, 0, 100));
          NZA.audio.success();
          sendResult('binder', { tension: Math.round(t), attempts: b.attempts, score });
        } else {
          b.attempts += 1;
          NZA.audio.fail();
          ui.pp.flash(t > hi ? 'bad' : 'warn', t > hi ? L('binder_tight', 'Too tight — {t}%. Ease it back.', { t: Math.round(t) }) : L('binder_loose', 'Too loose — {t}%. Pull it further across.', { t: Math.round(t) }));
          b.tension = 0; b.tab = null; this.devTick();
          const n = q('.d-chips'); if (n) n.lastElementChild.textContent = `${L('d_attempt', 'Attempt')} ${b.attempts}`;
        }
      }
    },
    frame() {
      const b = S.b;
      if (!b) return;
      if (b.phase === 'strap' || b.phase === 'done') {
        const A = apx('strapA'), B = apx('strapB');
        if (!A || !B) { ov(''); return; }
        const tab = b.tab || A;
        const [lo, hi] = b.band;
        const P = f => ({ x: A.x + (B.x - A.x) * f, y: A.y + (B.y - A.y) * f });
        const z1 = P(lo / 100), z2 = P(hi / 100);
        const w = 26 * pxScale();
        ov(`<line x1="${A.x}" y1="${A.y}" x2="${B.x}" y2="${B.y}" stroke="rgba(255,255,255,.35)" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="2 ${w * 0.5}" opacity=".55"/>
          <line x1="${z1.x}" y1="${z1.y}" x2="${z2.x}" y2="${z2.y}" stroke="rgba(61,220,132,.55)" stroke-width="${w + 12}" stroke-linecap="butt"/>
          <line x1="${A.x}" y1="${A.y}" x2="${tab.x}" y2="${tab.y}" stroke="#121820" stroke-width="${w}" stroke-linecap="round"/>
          <line x1="${A.x}" y1="${A.y}" x2="${tab.x}" y2="${tab.y}" stroke="${b.tension > hi ? '#e5484d' : b.tension >= lo ? '#08afa2' : '#5e6a72'}" stroke-width="3" stroke-dasharray="10 7"/>`);
        if (b.phase === 'strap') mark('tab', { label: L('m_pull', 'Pull'), tone: 'red', dot: 'red tab', at: { x: tab.x / W(), y: tab.y / H() } });
      } else ov('');
    },
    leave() { ghost(false); },
  };

  /* ═══════════════════════════ STEPS 2-5 · INTRAOSSEOUS ═══════════════════════════ */
  const IO_SITES = ['r_tibia', 'l_tibia', 'r_humerus', 'l_humerus'];
  const SITE_EN = { r_tibia: 'Right tibia', l_tibia: 'Left tibia', r_humerus: 'Right humeral head', l_humerus: 'Left humeral head' };
  const LAYER_EN = { air: 'Above skin', soft: 'Soft tissue', cortex: 'Cortex', marrow: 'Marrow', far: 'Far cortex', through: 'Through the bone' };
  const WHY_EN = { fracture: 'Fracture', tourniquet: 'Tourniquet', burn: 'Burn', wound: 'Wound', invalid: 'Not possible' };
  const siteName = id => L(`site_${id}`, SITE_EN[id] || id);
  const LAYER_ORDER = ['soft', 'cortex', 'marrow', 'far'];
  H_.io = {
    enter() {
      S.io = { phase: 'site', site: null, needles: 1, depth: 0, lift: 1, drilling: false, drift: { x: 0, y: 0 }, aim: { x: 0, y: 0 }, angle: 0,
        angleSum: 0, angleN: 0, maxAngle: 0, torque: [], fails: 0, aspirated: false, ext: false, lido: { ml: 0, rate: 0, peak: 0 }, flush: { ml: 0, rate: 0, peak: 0 }, layer: 'air', snd: 0, lostRes: false };
      this.site();
    },
    /* ── step 2 · site ── */
    site() {
      const io = S.io, sites = S.data.sites || {};
      io.phase = 'site'; S.n = 2;
      metric({ label: L('st_needles', 'Needles'), value: `${io.needles}/${S.data.attempts || 3}` });
      ui.pp.set({
        step: 2, title: L('t_site', 'Choose IO site'), tag: L('tag_io', 'Intraosseous access'),
        text: L('site_text', 'Click a marker or press its key: the **proximal tibia** below the knee or the **humeral head**.'),
        tools: IO_SITES.map((id, i) => ({ key: String(i + 1), label: siteName(id), icon: 'bone', state: sites[id] && sites[id].ok === false ? 'locked' : '' })),
      });
      IO_SITES.forEach(id => {
        const st = sites[id] || { ok: true };
        mark(id, { label: st.ok === false ? `${siteName(id)} · ${L(`why_site_${st.why}`, WHY_EN[st.why] || st.why || '')}` : siteName(id), dot: st.ok === false ? 'red' : '', tone: st.ok === false ? 'red' : '' });
      });
      devFrame(L('d_site', 'IO site'), `<div class="d-sites">${IO_SITES.map((id, i) => {
        const st = sites[id] || { ok: true };
        return `<button class="d-site ${st.ok === false ? 'bad' : ''}" data-s="${id}"><kbd>${i + 1}</kbd>${esc(siteName(id))}<span class="why">${esc(st.ok === false ? L(`why_site_${st.why}`, WHY_EN[st.why] || st.why || '') : L('site_ok', 'Clear'))}</span></button>`;
      }).join('')}</div><div class="d-note">${NZA.rich(L('site_note', 'Never drill a **fractured** bone or below a **tourniquet**.'))}</div>`, { brand: L('dev_io', 'IO driver'), right: `${io.needles}/${S.data.attempts || 3}` });
      ui.dev.querySelectorAll('.d-site').forEach(b => b.addEventListener('click', () => this.pick(b.dataset.s)));
    },
    pick(id) {
      const st = (S.data.sites || {})[id];
      if (!id || (st && st.ok === false)) { ui.pp.flash('bad', st ? L(`why_site_${st.why}_long`, L(`why_site_${st.why}`, 'Contraindicated')) : ''); NZA.audio.fail(); return; }
      S.io.site = id;
      clearMarks();
      NZA.audio.click(820);
      post('phase', { proc: 'io', phase: 'drill', site: id });
      S.focus = 'site'; renderFocus();
      this.drillUi();
    },
    layers() {
      const kind = /humerus/.test(S.io.site || '') ? 'humerus' : 'tibia';
      return (S.data.layers || {})[kind] || { soft: 7, cortex: 3, marrow: 12, far: 3 };
    },
    /* ── step 3 · drill ── */
    drillUi() {
      const io = S.io, ly = this.layers();
      io.phase = 'drill'; S.n = 3; io.depth = 0; io.drilling = false; io.lostRes = false; io.layer = 'air'; io.torque = [];
      const k = S.keys.drill || 'Space';
      ui.pp.set({
        step: 3, title: L('t_drill', 'Drill'), tag: siteName(io.site),
        text: L('drill_text', 'Move the mouse to line the driver up with the bone (under {max}°), hold {Click} to reach the skin, then hold {{key}} to drill. Let go when the resistance is lost.', { max: S.data.maxAngle || 15, key: keyName(k) }),
        tools: [{ key: '1', label: L('tool_driver', 'IO driver'), icon: 'drill', state: 'active', sub: `${L('needle', 'Needle')} ${io.needles}/${S.data.attempts || 3}` }],
        hints: [{ keys: [L('k_hold', 'Hold'), keyName(k)], label: L('h_drill', 'drill') }, { keys: [L('k_click', 'Click')], label: L('h_pressure', 'pressure') }].concat(hintsCam()),
      });
      mark('site', { anchor: io.site, label: '', dot: 'white ring' });
      ui.host.classList.add('aim');
      const total = 4 + ly.soft + ly.cortex + ly.marrow + ly.far + 5;
      const y = mm => ((mm + 4) / total) * 100;
      let acc = 0;
      const seg = (cls, label, mm) => { const s = `<div class="ly ${cls}" style="top:${y(acc)}%;height:${mm / total * 100}%">${esc(label)}</div>`; acc += mm; return s; };
      acc = -4;
      const col = seg('air', '', 4) + seg('soft', L('ly_soft', 'Soft tissue'), ly.soft) + seg('cortex', L('ly_cortex', 'Cortex'), ly.cortex) + seg('marrow', L('ly_marrow', 'Marrow'), ly.marrow) + seg('far', L('ly_far', 'Far cortex'), ly.far) + seg('beyond', '', 5);
      io.total = total;
      devFrame(L('d_drill', 'IO drill'), `
        <div class="d-row">
          <div class="d-layers">${col}<span class="needle" style="height:0"></span><span class="tip" style="top:0"></span></div>
          <div class="d-col">
            <div class="d-row" style="gap:6px;align-items:center"><div class="d-arc">${arcSVG(S.data.maxAngle || 15)}<span class="v av">0°</span></div><div><div class="d-lbl">${esc(L('d_offaxis', 'Off axis'))}</div><div class="d-val oa">0°</div></div></div>
            <div><div class="d-lbl">${esc(L('d_depth', 'Depth'))}</div><div class="d-big dp" style="font-size:24px">0.0<span class="u">mm</span></div></div>
            <div><div class="d-lbl">${esc(L('d_tip', 'Tip in'))}</div><div class="d-val ti">${esc(L('ly_air', 'Above skin'))}</div></div>
          </div>
        </div>
        <div class="d-lbl" style="margin-top:8px">${esc(L('d_resist', 'Resistance'))}</div><canvas class="d-spark"></canvas>
        <div class="d-keys"><span><kbd>${esc(keyName(k))}</kbd>${esc(L('d_trigger', 'Trigger'))}</span><span><kbd>${esc(L('k_click', 'Click'))}</kbd>${esc(L('d_pressure', 'Pressure'))}</span></div>`,
      { brand: L('dev_io', 'IO driver'), right: `${io.needles}/${S.data.attempts || 3}`, capLed: '' });
    },
    layerAt(depth) {
      const ly = this.layers();
      if (depth <= 0) return 'air';
      let d = depth;
      for (const k of LAYER_ORDER) { if (d <= ly[k]) return k; d -= ly[k]; }
      return 'through';
    },
    drillFail(why) {
      const io = S.io;
      io.drilling = false; io.failed = why; io.fails += 1;
      NZA.audio.fail();
      const max = S.data.attempts || 3;
      ui.pp.flash('bad', L(`drill_fail_${why}`, why), 0);
      if (io.needles >= max) {
        ui.pp.set({ text: L('drill_out', 'No needles left for this attempt.'), tools: [{ key: 'N', label: L('tool_giveup', 'Give up IO'), icon: 'x' }] });
        return;
      }
      ui.pp.set({ text: L('drill_retry', 'Pull the needle and take a new one.'), tools: [{ key: 'R', label: L('tool_newneedle', 'New needle'), icon: 'needle', state: 'active' }, { key: 'N', label: L('tool_giveup', 'Give up IO'), icon: 'x' }] });
    },
    newNeedle() {
      const io = S.io;
      if (!io.failed) return;
      const go = r => {
        if (!r || r.ok === false) { ui.pp.flash('bad', (r && r.msg) || L('no_needle', 'No IO needle set left.')); return; }
        io.needles = r.needles || io.needles + 1; io.failed = null;
        ui.pp.flash('ok', L('needle_new', 'New needle on the driver.'));
        this.drillUi();
      };
      if (S.preview) go({ ok: true, needles: io.needles + 1 }); else post('needle', {}).then(go);
    },
    drillDone() {
      const io = S.io, ly = this.layers();
      const intoFar = io.depth - (ly.soft + ly.cortex + ly.marrow);
      io.overshoot = Math.max(0, intoFar);
      io.drilling = false;
      if (intoFar > 1.0) return this.drillFail('far');
      NZA.audio.success();
      ui.pp.flash(intoFar > 0 ? 'warn' : 'ok', intoFar > 0 ? L('drill_touch_far', 'In — the tip is touching the far cortex.') : L('drill_ok', 'Loss of resistance. The needle is in the marrow.'));
      setTimeout(() => this.confirmUi(), 900);
    },
    /* ── step 4 · confirm ── */
    confirmUi() {
      const io = S.io;
      io.phase = 'confirm'; S.n = 4;
      metric({ label: L('st_depth', 'Depth'), value: fmt1(io.depth), unit: 'mm', tone: 'teal' });
      ui.host.classList.remove('aim');
      post('phase', { proc: 'io', phase: 'confirm', site: io.site });
      ui.pp.set({
        step: 4, title: L('t_confirm', 'Confirm'), tag: siteName(io.site),
        text: L('confirm_text', 'Take the stylet out, screw on the syringe and **drag the plunger back** to aspirate. Marrow blood means you are in.'),
        tools: [{ key: '1', label: L('tool_syringe', 'Syringe 10 ml'), icon: 'syringe', state: 'active' }],
        hints: hintsCam(),
      });
      mark('site', { anchor: io.site, label: L('m_io', 'IO needle'), dot: 'white' });
      devFrame(L('d_confirm', 'Aspirate'), `<div class="syrh"></div><div class="d-note cn">${esc(L('confirm_note', 'Pull back about 1 ml.'))}</div>`, { brand: L('dev_io', 'IO driver') });
      io.syr = Syringe(ui.dev.querySelector('.syrh'), {
        cap: 10, vol: 0, mode: 'pull', fluid: 'clear', label: L('syr_aspirate', 'Aspirate'), flashAt: S.data.aspirateMl || 1,
        onFlash: () => {
          io.aspirated = true; NZA.audio.success();
          ui.pp.flash('ok', L('confirm_ok', 'Marrow blood in the barrel. The needle is in.'));
          const n = q('.cn'); if (n) n.textContent = L('confirm_ok', 'Marrow blood in the barrel. The needle is in.');
          setTimeout(() => this.flushUi(), 1300);
        },
      });
    },
    /* ── step 5 · flush ── */
    flushUi() {
      const io = S.io;
      if (io.syr) { io.syr.destroy(); io.syr = null; }
      io.phase = 'flush'; S.n = 5; io.tool = null;
      ui.pp.set({ step: 5, title: L('t_flush', 'Confirm and flush'), tag: siteName(io.site), hints: hintsCam() });
      this.flushTools();
      devFrame(L('d_flush', 'Flush'), `<div class="syrh"></div><div class="d-note fn"></div>`, { brand: L('dev_io', 'IO driver') });
      this.flushText();
    },
    flushTools() {
      const io = S.io, d = S.data;
      const hasLido = d.lidocaine !== false;
      ui.pp.set({
        tools: [
          { key: '1', label: L('tool_ext', 'Extension set'), icon: 'tube', state: io.ext ? 'done' : io.tool === 'ext' ? 'active' : '' },
          { key: '2', label: L('tool_lido', 'Lidocaine 2%'), icon: 'syringe', state: io.lido.ml >= (d.lidoMl || 2) - 0.05 ? 'done' : !io.ext || !hasLido ? 'locked' : io.tool === 'lido' ? 'active' : '', sub: hasLido ? `${d.lidoMl || 2} ml` : '×0' },
          { key: '3', label: L('tool_flush', 'Saline flush'), icon: 'drop', state: io.flush.ml >= (d.flushMl || 10) - 0.1 ? 'done' : !io.ext ? 'locked' : io.tool === 'flush' ? 'active' : '', sub: `${d.flushMl || 10} ml` },
        ],
      });
    },
    flushText() {
      const io = S.io, d = S.data;
      let text;
      if (!io.ext) text = L('flush_ext', 'Prime the **extension set** and connect it to the hub.');
      else if (io.tool === 'lido') text = L('flush_lido', 'Keep pushing **slowly**: lidocaine going in. {a} of {b} ml.', { a: fmt1(io.lido.ml), b: d.lidoMl || 2 });
      else if (io.tool === 'flush') text = L('flush_flush', 'Flush the line: {a} of {b} ml.', { a: fmt1(io.flush.ml), b: d.flushMl || 10 });
      else if (d.responsive !== false && d.lidocaine !== false && io.lido.ml < (d.lidoMl || 2) - 0.05) text = L('flush_pick_lido', 'The patient is awake: give **lidocaine 2%** before the flush (2).');
      else text = L('flush_pick', 'Flush the line with **saline** (3).');
      ui.pp.set({ text });
      const n = q('.fn'); if (n) n.innerHTML = NZA.rich(io.tool ? L('flush_drag', 'Drag the plunger toward the needle. Stay in the band.') : L('flush_pick_tool', 'Pick a syringe.'));
    },
    useSyringe(kind) {
      const io = S.io, d = S.data;
      if (io.syr) { io.syr.destroy(); io.syr = null; }
      io.tool = kind;
      const host = ui.dev.querySelector('.syrh');
      const cap = kind === 'lido' ? (d.lidoMl || 2) : (d.flushMl || 10);
      const band = kind === 'lido' ? (d.lidoRate || [0.08, 0.45]) : (d.flushRate || [1.5, 6]);
      const rec = kind === 'lido' ? io.lido : io.flush;
      io.syr = Syringe(host, {
        cap: kind === 'lido' ? 5 : 10, vol: cap - rec.ml, mode: 'push', fluid: kind === 'lido' ? 'lido' : 'clear', band, maxRate: band[1] * 1.8,
        label: kind === 'lido' ? L('tool_lido', 'Lidocaine 2%') : L('tool_flush', 'Saline flush'),
        onChange: (vol, rate) => {
          rec.ml = clamp(cap - vol, 0, cap);
          if (rate > 0.01) { rec.samples = (rec.samples || 0) + 1; rec.rateSum = (rec.rateSum || 0) + rate; rec.peak = Math.max(rec.peak, rate); }
          if (rate > band[1] * 1.25 && !rec.warned) { rec.warned = true; ui.pp.flash('bad', kind === 'lido' ? L('lido_fast', 'Too fast — that burns.') : L('flush_fast', 'Too fast — the patient pulls away.')); }
          this.flushText();
          if (rec.ml >= cap - 0.05 && !rec.done) {
            rec.done = true; rec.rate = rec.samples ? rec.rateSum / rec.samples : 0;
            NZA.audio.success();
            io.tool = null; this.flushTools(); this.flushText();
            if (kind === 'flush') setTimeout(() => this.finish(), 700);
          }
        },
      });
      this.flushTools(); this.flushText();
    },
    finish() {
      const io = S.io, d = S.data;
      const avgAngle = io.angleN ? io.angleSum / io.angleN : 0;
      let score = 100 - avgAngle * 1.6 - Math.max(0, io.maxAngle - (d.maxAngle || 15)) * 1.5 - (io.needles - 1) * 15 - (io.overshoot || 0) * 12;
      const lr = d.lidoRate || [0.08, 0.45], fr = d.flushRate || [1.5, 6];
      if (io.lido.ml > 0 && io.lido.rate > lr[1]) score -= 10;
      if (io.flush.rate > fr[1]) score -= 8;
      if (d.responsive !== false && d.lidocaine !== false && io.lido.ml < 1) score -= 15;
      score = Math.round(clamp(score, 0, 100));
      sendResult('io', {
        site: io.site, angle: Math.round(avgAngle * 10) / 10, overshoot: Math.round((io.overshoot || 0) * 10) / 10, needles: io.needles,
        aspirated: io.aspirated, lido: { ml: Math.round(io.lido.ml * 10) / 10, rate: Math.round((io.lido.rate || 0) * 100) / 100 },
        flush: { ml: Math.round(io.flush.ml * 10) / 10, rate: Math.round((io.flush.rate || 0) * 100) / 100 }, score,
      });
    },
    tool(k) {
      const io = S.io;
      const K = k.toUpperCase();
      if (K === 'N' && (io.phase === 'site' || io.failed)) return skip();
      if (io.phase === 'site' && /^[1-4]$/.test(k)) return this.pick(IO_SITES[Number(k) - 1]);
      if (io.phase === 'drill' && K === 'R') return this.newNeedle();
      if (io.phase === 'flush') {
        if (k === '1' && !io.ext) { io.ext = true; NZA.audio.click(900); ui.pp.flash('ok', L('ext_ok', 'Extension set primed and connected.')); this.flushTools(); this.flushText(); return; }
        if (k === '2' && io.ext && S.data.lidocaine !== false && io.lido.ml < (S.data.lidoMl || 2) - 0.05) return this.useSyringe('lido');
        if (k === '3' && io.ext && io.flush.ml < (S.data.flushMl || 10) - 0.1) {
          if (S.data.responsive !== false && S.data.lidocaine !== false && io.lido.ml < 1 && !io.warnedLido) { io.warnedLido = true; ui.pp.flash('warn', L('flush_nolido', 'Awake patient: the flush hurts without lidocaine. Press 3 again to flush anyway.')); return; }
          return this.useSyringe('flush');
        }
      }
    },
    down(e) {
      const io = S.io;
      if (io.phase === 'site') {
        let best = null, bd = 60 * pxScale();
        IO_SITES.forEach(id => { const p = apx(id); if (p) { const d = Math.hypot(e.clientX - p.x, e.clientY - p.y); if (d < bd) { bd = d; best = id; } } });
        if (best) this.pick(best);
      }
    },
    key(e, downKey) {
      const io = S.io;
      const k = S.keys.drill || 'Space';
      if (io.phase !== 'drill' || io.failed) return false;
      if (e.code !== k && e.key !== k) return false;
      if (downKey) {
        if (e.repeat) return true;
        if (io.lift > 0.08) { ui.pp.flash('warn', L('drill_press', 'Hold {Click} to press the driver onto the skin first.')); return true; }
        if (io.angle > (S.data.maxAngle || 15) && io.depth < 0.1) { ui.pp.flash('warn', L('drill_align', 'Line up first: {a}° off axis.', { a: Math.round(io.angle) })); return true; }
        io.drilling = true;
      } else if (io.drilling) {
        io.drilling = false;
        const layer = this.layerAt(io.depth);
        if (layer === 'marrow' || layer === 'far') this.drillDone();
      }
      return true;
    },
    frame(dt) {
      const io = S.io;
      if (!io) return;
      if (io.phase === 'drill') this.drillFrame(dt);
      else if (io.phase !== 'site') {
        const p = apx(io.site);
        ov(p ? `<circle cx="${p.x}" cy="${p.y}" r="${9 * pxScale()}" fill="none" stroke="#08afa2" stroke-width="2"/>` : '');
      }
    },
    drillFrame(dt) {
      const io = S.io, d = S.data;
      const site = apx(io.site);
      const k = pxScale();
      // aim = cursor offset from the site; drift = hand tremor fighting the bone
      if (site) { io.aim.x = (S.mouse.x - site.x) / k; io.aim.y = (S.mouse.y - site.y) / k; }
      const ppd = d.pxPerDeg || 3.2;
      const layer = this.layerAt(io.depth);
      const trem = (d.tremor || 7) * (io.drilling ? (layer === 'cortex' || layer === 'far' ? 1 : 0.35) : 0);
      const t = now() / 1000;
      const tx = Math.sin(t * 1.3) * 0.6 + Math.sin(t * 2.9 + 1.7) * 0.4, ty = Math.cos(t * 1.1 + 0.5) * 0.6 + Math.sin(t * 2.3) * 0.4;
      io.drift.x += ((tx * trem) - io.drift.x) * Math.min(1, dt * 1.6);
      io.drift.y += ((ty * trem) - io.drift.y) * Math.min(1, dt * 1.6);
      const ax = io.aim.x / ppd + io.drift.x, ay = io.aim.y / ppd + io.drift.y;
      io.angle = Math.min(60, Math.hypot(ax, ay));
      const target = S.mouse.down ? 0 : 1;
      io.lift += (target - io.lift) * Math.min(1, dt * 7);
      if (io.drilling && io.lift > 0.3) { io.drilling = false; }
      if (io.drilling && !io.failed) {
        const sp = d.speed || { soft: 7, cortex: 1.3, marrow: 8, far: 1.1 };
        const speed = layer === 'air' ? 10 : (sp[layer] || 2);
        io.depth += speed * dt * (layer === 'cortex' || layer === 'far' ? (1 - Math.min(0.6, io.angle / 40)) : 1);
        io.angleSum += io.angle * dt; io.angleN += dt; io.maxAngle = Math.max(io.maxAngle, io.angle);
        const nl = this.layerAt(io.depth);
        if ((nl === 'cortex' || nl === 'far') && io.angle > (d.bendAngle || 26)) return this.drillFail('bent');
        if (nl === 'marrow' && !io.lostRes) { io.lostRes = true; ui.pp.flash('ok', L('drill_loss', 'Loss of resistance — let go of the trigger!'), 1600); NZA.audio.beep(1250, 70, 0.06); }
        if (nl === 'through') return this.drillFail('through');
        io.snd -= dt;
        if (io.snd <= 0) { io.snd = 0.075; NZA.audio.tone(nl === 'cortex' || nl === 'far' ? 135 : nl === 'marrow' ? 430 : 290, 85, { vol: 0.028, type: 'sawtooth' }); }
      }
      io.layer = this.layerAt(io.depth);
      const res = { air: 0.02, soft: 0.25, cortex: 0.9, marrow: 0.12, far: 0.95, through: 0.05 }[io.layer] || 0;
      io.torque.push(io.drilling ? res + (Math.random() - 0.5) * 0.12 : io.torque.length ? io.torque[io.torque.length - 1] * 0.9 : 0);
      if (io.torque.length > 120) io.torque.shift();
      // device
      const tipTop = ((io.depth + 4 - io.lift * 3) / io.total) * 100;
      const tip = q('.d-layers .tip'); if (tip) tip.style.top = `${clamp(tipTop, 0, 100)}%`;
      const ndl = q('.d-layers .needle'); if (ndl) ndl.style.height = `${clamp(tipTop, 0, 100)}%`;
      const maxA = d.maxAngle || 15;
      const an = q('.d-arc .an');
      if (an) an.setAttribute('transform', `rotate(${(clamp(io.angle, 0, 45) / 45) * 180 - 90} 43 44)`);
      const av = q('.d-arc .v'); if (av) { av.textContent = `${Math.round(io.angle)}°`; av.className = `v ${io.angle > maxA ? 'red' : 'teal'}`; }
      const oa = q('.oa'); if (oa) { oa.textContent = io.angle > maxA ? L('d_realign', 'Realign') : L('d_aligned', 'Aligned'); oa.className = `d-val oa ${io.angle > maxA ? 'red' : 'teal'}`; }
      const dp = q('.dp'); if (dp) dp.innerHTML = `${fmt1(io.depth)}<span class="u">mm</span>`;
      metric({ label: L('st_offaxis', 'Off axis'), value: Math.round(io.angle), unit: '°', tone: io.angle > maxA ? 'red' : 'teal' });
      const ti = q('.ti'); if (ti) { ti.textContent = L(`ly_${io.layer}`, LAYER_EN[io.layer] || io.layer); ti.className = `d-val ti ${io.layer === 'marrow' ? 'teal' : io.layer === 'far' || io.layer === 'through' ? 'red' : ''}`; }
      const cv = q('.d-spark');
      if (cv) {
        const { w, h } = NZA.fitCanvas(cv);
        const c = cv.getContext('2d');
        c.clearRect(0, 0, w, h);
        c.strokeStyle = 'rgba(255,255,255,.06)'; c.beginPath(); c.moveTo(0, h - 1); c.lineTo(w, h - 1); c.stroke();
        c.strokeStyle = io.layer === 'marrow' ? '#0fd4c4' : '#f3c35a'; c.lineWidth = 1.6 * (w / cv.clientWidth || 1); c.beginPath();
        io.torque.forEach((v, i) => { const x = (i / 119) * w, y = h - 2 - clamp(v, 0, 1) * (h - 6); if (i) c.lineTo(x, y); else c.moveTo(x, y); });
        c.stroke();
      }
      if (!io.failed) setText((io.lift > 0.3
        ? L('drill_text_aim', 'Line the driver up with the bone (under {max}°) and hold {Click} to reach the skin. {a}° off axis.', { max: maxA, a: Math.round(io.angle) })
        : io.drilling ? (io.layer === 'cortex' ? L('drill_text_cortex', 'Through the cortex — keep it straight. {a}° off axis.', { a: Math.round(io.angle) }) : io.layer === 'marrow' ? L('drill_loss', 'Loss of resistance — let go of the trigger!') : L('drill_text_drilling', 'Drilling… {d} mm.', { d: fmt1(io.depth) }))
          : L('drill_text_ready', 'On the skin. Hold {{key}} to drill. {a}° off axis.', { key: keyName(S.keys.drill || 'Space'), a: Math.round(io.angle) })));
      // overlay: site ring + driver axis toward the cursor
      if (site) {
        const col = io.angle > maxA ? '#e5484d' : '#08afa2';
        const len = Math.min(140 * k, Math.hypot(S.mouse.x - site.x, S.mouse.y - site.y));
        const ang = Math.atan2(S.mouse.y - site.y, S.mouse.x - site.x);
        const ex = site.x + Math.cos(ang) * len, ey = site.y + Math.sin(ang) * len;
        const rz = (maxA * (d.pxPerDeg || 3.2)) * k;
        ov(`<circle cx="${site.x}" cy="${site.y}" r="${rz}" fill="rgba(8,175,162,.08)" stroke="rgba(8,175,162,.5)" stroke-dasharray="4 4"/>
          <circle cx="${site.x}" cy="${site.y}" r="${6 * k}" fill="${col}"/>
          <line x1="${site.x}" y1="${site.y}" x2="${ex}" y2="${ey}" stroke="${col}" stroke-width="2" stroke-dasharray="${io.lift > 0.3 ? '6 5' : 'none'}"/>
          <circle cx="${S.mouse.x}" cy="${S.mouse.y}" r="${(10 + io.lift * 12) * k}" fill="none" stroke="${col}" stroke-width="2"/>`);
      }
      // stream the driver pose to Lua (~20 Hz)
      io.sendT = (io.sendT || 0) - dt;
      if (io.sendT <= 0 && !S.preview) {
        io.sendT = 0.05;
        const l = Math.hypot(ax, ay) || 1;
        post('drill', { x: S.mouse.x / W(), y: S.mouse.y / H(), angle: Math.round(io.angle * 10) / 10, dx: ax / l, dy: ay / l, lift: Math.round(io.lift * 100) / 100, depth: Math.round(io.depth * 10) / 10 });
      }
    },
    leave() { const io = S.io; if (io && io.syr) { io.syr.destroy(); io.syr = null; } if (io) io.drilling = false; },
  };

  /* ═══════════════════════════ STEP 6 · RESUSCITATE ═══════════════════════════ */
  H_.resus = {
    enter() {
      const d = S.data;
      S.rs = { pressure: 0, clamp: 0.66, sel: null, bags: (d.infusions || []).filter(b => b.mine !== false), counts: d.counts || {}, txa: null, txaDone: !!d.txaActive,
        foil: !!d.foilOn, mapHist: [], tegHist: [], lastPost: 0, lastRate: {}, salineIn: 0, bloodIn: 0, given: {}, stand: true, firmAt: 0, confirmBlood: 0, popped: 0 };
      const rs = S.rs;
      if (rs.bags.length) rs.sel = rs.bags[0].id;
      S.clot = null;
      ui.pp.set({
        title: L('t_resus', 'Resuscitate'), tag: d.access ? `${d.access.kind === 'io' ? 'IO' : 'IV'} · ${d.access.siteLabel || d.access.site || ''}` : '',
        text: L('resus_text', 'Hang a bag, squeeze the infuser and open the clamp until the MAP sits in the band. Hold it there while the clot firms.'),
        hints: [{ keys: [keyName(S.keys.squeeze || 'Space')], label: L('h_squeeze', 'squeeze') }, { keys: ['Q', 'E'], label: L('h_clamp', 'clamp') }].concat(hintsCam()),
      });
      this.tools();
      mark('access', { label: d.access ? `${d.access.kind === 'io' ? 'IO' : 'IV'}` : '', dot: 'white' });
      devFrame(L('d_clot', 'Clot'), `
        <div class="d-row" style="align-items:flex-end"><div style="flex:1"><div class="d-lbl">${esc(L('d_firm', 'Clot firmness'))}</div><div class="d-big teal fm">0<span class="u">%</span></div></div>
          <div style="text-align:right"><div class="d-lbl">MAP</div><div class="d-big mp" style="font-size:26px">--</div></div></div>
        <canvas class="d-teg" style="margin-top:8px"></canvas>
        <div class="d-row" style="margin-top:7px;align-items:center"><div class="d-lbl st" style="flex:1">${esc(L('cs_wait', 'Waiting for flow'))}</div><div class="d-val hd" style="margin:0;font-family:var(--mono)">--</div></div>
        <canvas class="d-strip" style="margin-top:5px"></canvas>`, { brand: L('dev_clot', 'Clot monitor'), right: ' ', rightHtml: true });
      const cap = ui.dev.querySelector('.d-cap .r'); if (cap) cap.classList.add('ch');
      ui.inf.style.display = '';
      ui.inf.innerHTML = `
        <div class="ic1"><div class="gauge">${gaugeSVG()}</div>
          <div class="press"><div class="nza-label">${esc(L('i_pressure', 'Bag pressure'))}</div><div class="lcd"><span>0</span><span>0</span><span>0</span><i>mmHg</i></div></div></div>
        <div class="ic2"><div class="nza-label">${esc(L('i_bags', 'On the stand'))}</div><div class="fd-bags"></div><div class="fd-txa-h"></div></div>
        <div class="ic3">
          <div class="fd-tiles">
            <div class="fd-tile"><div class="l">${esc(L('i_rate', 'Infusion'))}</div><div class="v t-rt">0<span class="u">ml/min</span></div></div>
            <div class="fd-tile"><div class="l">${esc(L('i_saline', 'Saline in'))}</div><div class="v t-si">0<span class="u">ml</span></div></div>
            <div class="fd-tile"><div class="l">${esc(L('i_blood', 'Blood in'))}</div><div class="v t-bi">0<span class="u">ml</span></div></div>
            <div class="fd-tile"><div class="l">${esc(L('i_txa', 'TXA push'))}</div><div class="v t-tx">${rs.txaDone ? '✓' : '0.0'}<span class="u">/${d.txaPush || 10} s</span></div></div>
          </div>
          <div class="fd-ctl"><button class="sq"><kbd>${esc(keyName(S.keys.squeeze || 'Space'))}</kbd>${esc(L('i_squeeze', 'Squeeze'))}</button>
            <button class="pm" data-c="-1">−</button><div class="clamp"><div class="t"><span>${esc(L('i_clamp', 'Roller clamp'))}</span><b class="cl">66%</b></div><div class="cm"></div></div><button class="pm" data-c="1">+</button></div>
        </div>`;
      ui.inf.querySelector('.sq').addEventListener('mousedown', e => { e.stopPropagation(); this.squeeze(); });
      ui.inf.querySelectorAll('.pm').forEach(b => b.addEventListener('click', e => { e.stopPropagation(); this.clampBy(Number(b.dataset.c) * 0.1); }));
      this.bagsUi();
      this.infTick(0);
    },
    tools() {
      const rs = S.rs, d = S.data, c = rs.counts || {};
      const saline = rs.bags.find(b => b.kind === 'saline' && b.left > 0);
      const blood = rs.bags.find(b => b.kind === 'blood' && b.left > 0);
      const bb = (d.bags || [])[0];
      const bloodSub = !d.blood ? L('tool_blood_none', 'No blood bank') : blood ? L('tool_running', 'Running') : bb ? `${bb.type} · ${bb.compatible === true ? L('compatible', 'Compatible') : bb.compatible === false ? L('incompatible', 'Incompatible') : L('untyped', 'Untyped')}` : '×0';
      ui.pp.set({
        tools: [
          { key: '1', label: L('tool_saline', 'Saline 500 ml'), icon: 'iv', state: saline ? (rs.sel === saline.id ? 'active' : 'done') : (c.saline || 0) < 1 ? 'locked' : '', sub: saline ? L('tool_running', 'Running') : `×${c.saline || 0}` },
          { key: '2', label: L('tool_blood', 'Blood'), icon: 'bloodbag', state: blood ? (rs.sel === blood.id ? 'active' : 'done') : (!d.blood || !bb) ? 'locked' : bb.compatible === false ? 'need' : '', sub: bloodSub },
          { key: '3', label: L('tool_txa', 'TXA 1 g'), icon: 'syringe', state: rs.txaDone ? 'done' : rs.txa ? 'active' : (c.txa || 0) < 1 ? 'locked' : '', sub: rs.txaDone ? '' : `×${c.txa || 0}` },
          { key: '4', label: L('tool_foil', 'Foil blanket'), icon: 'blanket', state: rs.foil ? 'done' : (c.foil || 0) < 1 ? 'locked' : '', sub: rs.foil ? '' : `×${c.foil || 0}` },
          { key: '5', label: L('tool_squeeze', 'Squeeze infuser'), icon: 'gauge' },
          { key: '6', label: L('tool_nibp', 'Cycle NIBP'), icon: 'cuff' },
        ],
      });
    },
    bagsUi() {
      const rs = S.rs;
      const box = ui.inf.querySelector('.fd-bags');
      if (!box) return;
      const list = rs.bags.filter(b => b.left > 0);
      if (!list.length) { box.innerHTML = `<div class="fd-bag empty">${esc(L('i_nobag', 'No bag hanging — press 1 or 2'))}</div>`; return; }
      box.innerHTML = list.map(b => {
        const blood = b.kind === 'blood';
        const name = blood ? `${L('bag_blood_short', 'Blood')} ${b.bag && b.bag.type ? b.bag.type : ''}` : L('bag_saline_short', 'Saline {ml} ml', { ml: b.ml });
        return `<div class="fd-bag ${blood ? 'blood' : ''} ${rs.sel === b.id ? 'sel' : ''}" data-id="${esc(b.id)}"><span class="bi">${icon(blood ? 'bloodbag' : 'iv')}</span>
          <span class="bt"><b>${esc(name)}</b><span>${esc(L('i_left', '{n} ml left', { n: Math.round(b.left) }))} · ${Math.round(b.rate || 0)} ml/min${b.paused ? ` · ${L('paused', 'paused')}` : ''}</span><span class="lvl"><i style="width:${clamp(b.left / (b.ml || 500), 0, 1) * 100}%"></i></span></span>
          <button class="down">${esc(L('take_down_btn', 'Take down'))}</button></div>`;
      }).join('');
      box.querySelectorAll('.fd-bag').forEach(c => {
        c.addEventListener('click', e => { if (e.target.closest('.down')) return; rs.sel = c.dataset.id; this.bagsUi(); this.tools(); });
        c.querySelector('.down').addEventListener('click', e => { e.stopPropagation(); this.takeDown(c.dataset.id); });
      });
    },
    hang(kind) {
      const rs = S.rs, d = S.data;
      if (rs.bags.filter(b => b.left > 0).length >= ((d.infusion || {}).maxBags || 3)) { ui.pp.flash('warn', L('too_many', 'Three bags are already running.')); return; }
      let serial = null, type = null;
      if (kind === 'blood') {
        const bb = (d.bags || [])[0];
        if (!d.blood || !bb) { ui.pp.flash('bad', d.blood ? L('no_blood', 'You carry no blood.') : L('no_blood_module', 'Blood needs the blood bank.')); return; }
        if (bb.compatible === false && now() - rs.confirmBlood > 3000) { rs.confirmBlood = now(); ui.pp.flash('bad', L('blood_incompat', '{t} is NOT compatible with this patient. Press 2 again to hang it anyway.', { t: bb.type })); return; }
        if (bb.compatible !== true && bb.compatible !== false && now() - rs.confirmBlood > 3000) { rs.confirmBlood = now(); ui.pp.flash('warn', L('blood_untyped', 'The patient is not typed. Only O- is safe. Press 2 again to hang {t}.', { t: bb.type })); return; }
        serial = bb.serial; type = bb.type;
      } else if ((rs.counts.saline || 0) < 1) { ui.pp.flash('bad', L('no_saline', 'No saline bag left.')); return; }
      const rate = Math.max(1, Math.round(this.rateFor(kind)));
      const go = r => {
        if (!r || r.ok === false || !r.inf) { ui.pp.flash('bad', (r && r.msg) || L('hang_fail', 'Could not hang the bag.')); return; }
        rs.bags.push(Object.assign({ mine: true }, r.inf));
        rs.sel = r.inf.id;
        if (kind === 'saline') rs.counts.saline = Math.max(0, (rs.counts.saline || 1) - 1);
        if (kind === 'blood') d.bags = (d.bags || []).filter(b => b.serial !== serial);
        NZA.audio.click(880);
        ui.pp.flash('ok', kind === 'blood' ? L('hung_blood', 'Blood {t} running.', { t: type || '' }) : L('hung_saline', 'Saline running.'));
        this.bagsUi(); this.tools();
      };
      if (S.preview) go({ ok: true, inf: { id: `i${Date.now() % 1000}`, kind, ml: kind === 'blood' ? 450 : 500, left: kind === 'blood' ? 450 : 500, rate, bag: type ? { type } : null } });
      else post('hang', { kind, serial, rate }).then(go);
    },
    takeDown(id) {
      const rs = S.rs;
      const go = r => {
        if (!r || r.ok === false) { ui.pp.flash('bad', (r && r.msg) || L('takedown_fail', 'Could not take the bag down.')); return; }
        const b = rs.bags.find(x => x.id === id);
        if (b) { if (b.kind === 'blood') rs.bloodIn += (b.ml - b.left); else rs.salineIn += (b.ml - b.left); }
        rs.bags = rs.bags.filter(x => x.id !== id);
        if (rs.sel === id) rs.sel = rs.bags.length ? rs.bags[0].id : null;
        NZA.audio.click(400); this.bagsUi(); this.tools();
      };
      if (S.preview) go({ ok: true }); else post('takedown', { id }).then(go);
    },
    rateFor(kind) {
      const rs = S.rs, inf = S.data.infusion || {};
      const acc = S.data.access && S.data.access.kind === 'io' ? (inf.ioFactor || 0.45) : 1;
      const gravity = (inf.gravity || 60) * acc;
      const r = gravity * rs.clamp * (1 + (inf.pressureGain || 1.4) * rs.pressure / (inf.maxPressure || 300));
      return clamp(r, rs.clamp > 0.005 ? 1 : 1, S.data.maxRate || 160);
    },
    squeeze() {
      const rs = S.rs, inf = S.data.infusion || {};
      rs.pressure = clamp(rs.pressure + (inf.pump || 22), 0, inf.maxPressure || 300);
      rs.sqT = now();
      NZA.audio.noise(120, { vol: 0.06, lp: 900, hp: 200 });
    },
    clampBy(d) { const rs = S.rs; rs.clamp = clamp(Math.round((rs.clamp + d) * 100) / 100, 0, 1); NZA.audio.tick(); },
    txaStart() {
      const rs = S.rs;
      if (rs.txaDone || rs.txa) return;
      if ((rs.counts.txa || 0) < 1) { ui.pp.flash('bad', L('no_txa', 'No TXA in the kit.')); return; }
      const box = ui.inf.querySelector('.fd-txa-h');
      const push = S.data.txaPush || 10;
      box.innerHTML = `<div class="fd-txa"><div class="t">${esc(L('txa_title', 'TXA 1 g in 10 ml'))}<span>${esc(L('txa_slow', 'Over {s} s or more', { s: push }))}</span></div><div class="sh"></div></div>`;
      const t0 = { start: 0 };
      rs.txa = Syringe(box.querySelector('.sh'), {
        cap: 10, vol: 10, mode: 'push', fluid: 'txa', band: [0.15, 10 / push], maxRate: (10 / push) * 2, label: L('tool_txa', 'TXA 1 g'),
        onChange: vol => {
          if (!t0.start && vol < 9.9) t0.start = now();
          if (vol <= 0.05 && !rs.txaDone) {
            const secs = (now() - t0.start) / 1000;
            rs.txaDone = true;
            const fin = r => {
              if (r && r.ok === false) { rs.txaDone = false; ui.pp.flash('bad', r.msg || L('txa_fail', 'TXA not given.')); return; }
              ui.pp.flash(secs < push * 0.6 ? 'warn' : 'ok', secs < push * 0.6 ? L('txa_fast', 'TXA in — too fast, the pressure dips.') : L('txa_ok', 'TXA given. The clot will hold better.'));
              rs.counts.txa = Math.max(0, (rs.counts.txa || 1) - 1);
              setTimeout(() => { if (rs.txa) { rs.txa.destroy(); rs.txa = null; box.innerHTML = ''; } this.tools(); }, 900);
            };
            if (S.preview) fin({ ok: true }); else post('txa', { seconds: Math.round(secs * 10) / 10 }).then(fin);
          }
        },
        onTick: () => { const tx = ui.inf.querySelector('.t-tx'); if (tx && t0.start && !rs.txaDone) tx.innerHTML = `${fmt1((now() - t0.start) / 1000)}<span class="u">/${push} s</span>`; },
      });
      this.tools();
    },
    foil() {
      const rs = S.rs;
      if (rs.foil) return;
      const go = r => { if (r && r.ok === false) { ui.pp.flash('bad', r.msg || L('foil_fail', 'No foil blanket.')); return; } rs.foil = true; ui.pp.flash('ok', L('foil_ok', 'Foil blanket on — keep them warm.')); this.tools(); };
      if (S.preview) go({ ok: true }); else post('foil', {}).then(go);
    },
    tool(k) {
      const rs = S.rs;
      if (k.toUpperCase() === 'N') return skip();
      if (k === '1') { const s = rs.bags.find(b => b.kind === 'saline' && b.left > 0); if (s) { rs.sel = s.id; this.bagsUi(); this.tools(); } else this.hang('saline'); }
      if (k === '2') { const s = rs.bags.find(b => b.kind === 'blood' && b.left > 0); if (s) { rs.sel = s.id; this.bagsUi(); this.tools(); } else this.hang('blood'); }
      if (k === '3') this.txaStart();
      if (k === '4') this.foil();
      if (k === '5') this.squeeze();
      if (k === '6') { post('nibp', {}); NZA.audio.click(600); ui.pp.flash('ok', L('nibp_cycle', 'Cuff cycling…'), 1400); }
    },
    key(e, down) {
      const sq = S.keys.squeeze || 'Space';
      if (e.code === sq || e.key === sq) { if (down && !e.repeat) this.squeeze(); return true; }
      if (down && (e.code === (S.keys.clampDown || 'KeyQ') || e.key === '[' || e.key === 'ArrowLeft')) { this.clampBy(-0.05); return true; }
      if (down && (e.code === (S.keys.clampUp || 'KeyE') || e.key === ']' || e.key === 'ArrowRight')) { this.clampBy(0.05); return true; }
      return false;
    },
    infTick(dt) {
      const rs = S.rs, inf = S.data.infusion || {};
      rs.pressure = Math.max(0, rs.pressure - (inf.leak || 6) * dt);
      const p = Math.round(rs.pressure);
      const nd = ui.inf.querySelector('.ndl'); if (nd) nd.setAttribute('transform', `rotate(${-120 + (p / (inf.maxPressure || 300)) * 240} 59 59)`);
      const lcd = ui.inf.querySelectorAll('.lcd span'); const ps = String(p).padStart(3, '0');
      lcd.forEach((s, i) => { s.textContent = ps[i]; });
      const sq = ui.inf.querySelector('.sq'); if (sq) sq.classList.toggle('on', now() - (rs.sqT || 0) < 160);
      const cl = ui.inf.querySelector('.cl'); if (cl) cl.textContent = `${Math.round(rs.clamp * 100)}%`;
      const cm = ui.inf.querySelector('.cm'); if (cm) cm.innerHTML = NZA.ui.meterHTML({ value: rs.clamp });
      const sel = rs.bags.find(b => b.id === rs.sel && b.left > 0);
      const rate = sel ? Math.round(this.rateFor(sel.kind)) : 0;
      const total = rs.bags.filter(b => b.left > 0).reduce((a, b) => a + (b.id === rs.sel ? rate : (b.rate || 0)), 0);
      const rt = ui.inf.querySelector('.t-rt'); if (rt) rt.innerHTML = `${total}<span class="u">ml/min</span>`;
      let si = rs.salineIn, bi = rs.bloodIn;
      rs.bags.forEach(b => { if (b.kind === 'blood') bi += b.ml - b.left; else si += b.ml - b.left; });
      const se = ui.inf.querySelector('.t-si'); if (se) { se.innerHTML = `${Math.round(si)}<span class="u">ml</span>`; se.className = `v t-si ${si > ((inf.dilution || 1000)) ? 'amber' : ''}`; }
      const be = ui.inf.querySelector('.t-bi'); if (be) be.innerHTML = `${Math.round(bi)}<span class="u">ml</span>`;
      if (rs.txaDone) { const tx = ui.inf.querySelector('.t-tx'); if (tx && !rs.txa) tx.innerHTML = `✓<span class="u">${esc(L('given', 'given'))}</span>`; }
      // post the new flow for the selected bag (throttled)
      if (sel && (Math.abs((rs.lastRate[sel.id] || sel.rate || 0) - rate) >= 2) && now() - rs.lastPost > 650) {
        rs.lastPost = now(); rs.lastRate[sel.id] = rate; sel.rate = rate;
        if (!S.preview) post('rate', { id: sel.id, rate });
      }
    },
    clotTick() {
      const c = S.clot, rs = S.rs;
      if (!c) return;
      const fm = q('.fm'); if (fm) fm.innerHTML = `${Math.floor(c.firm)}<span class="u">%</span>`;
      S.metric = { label: L('st_clot', 'Clot'), value: Math.floor(c.firm), unit: '%', tone: c.firm >= 100 ? 'teal' : c.state === 'popped' ? 'red' : '' };
      const mp = q('.mp');
      if (mp) { mp.textContent = c.map; mp.className = `d-big mp ${c.map >= S.band[0] && c.map <= S.band[1] ? 'teal' : c.map > S.band[1] ? 'amber' : 'red'}`; mp.style.fontSize = '26px'; }
      const st = q('.d-scr .st');
      const stTxt = { band: L('cs_band', 'In the band — holding'), below: L('cs_below', 'Low — open up a little'), low: L('cs_low', 'Too low — the clot can not form'), high: L('cs_high', 'High — ease off'),
        own: L('cs_own', 'Above the band on their own — no fluids needed'), popped: L('cs_popped', 'Clot popped'), firm: L('cs_firm', 'Clot holding'), arrest: L('cs_arrest', 'No output') }[c.state] || c.state;
      if (st) { st.textContent = stTxt; st.style.color = c.state === 'band' || c.state === 'firm' || c.state === 'own' ? 'var(--teal-hi)' : c.state === 'below' || c.state === 'high' ? '#f3c35a' : '#ff8a8d'; }
      const hd = q('.hd'); if (hd) hd.textContent = c.state === 'firm' ? '✓' : c.warn ? `${L('pop_in', 'pop')} ${fmt1(Math.max(0, c.warn))} s` : c.eta ? `${c.eta} s` : '--';
      const ch = q('.ch');
      if (ch) {
        const m = c.mods || {};
        ch.innerHTML = [[L('chip_txa', 'TXA'), m.txa ? 'on' : ''], [L('chip_warm', 'Warm'), m.cold ? (m.foil ? 'warn' : 'bad') : 'on'], [L('chip_dil', 'Dil {n}%', { n: m.dil || 0 }), m.dilution ? 'bad' : ''],
          [L('chip_pops', 'Pops {n}', { n: c.pops || 0 }), c.pops ? 'bad' : '']].map(([t, cls]) => `<span class="d-chip ${cls}">${esc(t)}</span>`).join('');
      }
      if (c.bags && !S.preview) {
        // server truth for what is left / running
        const mine = c.bags.filter(b => b.mine);
        mine.forEach(b => { const x = rs.bags.find(y => y.id === b.id); if (x) { x.left = b.left; x.paused = b.paused; } else rs.bags.push(b); });
        rs.bags.forEach(x => { if (!mine.find(b => b.id === x.id)) { if (x.kind === 'blood') rs.bloodIn += x.ml - (x.left || 0); else rs.salineIn += x.ml - (x.left || 0); x.left = 0; } });
        rs.bags = rs.bags.filter(x => x.left > 0);
        if (rs.sel && !rs.bags.find(b => b.id === rs.sel)) rs.sel = rs.bags.length ? rs.bags[0].id : null;
        this.bagsUi();
      }
      if (c.bleed !== undefined) { S.bleed = c.bleed; stats(); }
      if (c.txa) rs.txaDone = true;
      if (c.foil) rs.foil = true;
      rs.mapHist.push(c.map); if (rs.mapHist.length > 60) rs.mapHist.shift();
      rs.tegHist.push(c.firm); if (rs.tegHist.length > 90) rs.tegHist.shift();
      this.drawTeg(); this.drawStrip();
      const txt = c.state === 'firm' ? L('resus_firm', 'Clot holding at 100%. Keep the line open.')
        : c.state === 'band' ? L('resus_band', 'In the band. Hold it while the clot firms: {s} s. Clot {f}%.', { s: c.eta || '--', f: Math.floor(c.firm) })
          : c.state === 'own' ? L('resus_own', 'The pressure holds on its own. Keep the fluids low: {s} s. Clot {f}%.', { s: c.eta || '--', f: Math.floor(c.firm) })
            : c.state === 'high' ? L('resus_high', 'MAP {m} — too high. Close the clamp before the clot pops.', { m: c.map })
              : c.state === 'below' ? L('resus_below', 'MAP {m} — a little low. Open the clamp or squeeze the infuser.', { m: c.map })
                : c.state === 'low' ? L('resus_low', 'MAP {m} — too low for a clot. Run fluid in now.', { m: c.map })
                  : c.state === 'popped' ? L('resus_popped', 'The clot popped. Bleeding is back up — bring the pressure down.') : '';
      if (txt) ui.pp.set({ text: txt, titleTone: c.state === 'firm' ? 'ok' : c.state === 'popped' || c.state === 'low' ? 'bad' : '' });
      if (c.state === 'firm' && !rs.firmAt) {
        rs.firmAt = now();
        NZA.audio.success();
        ui.pp.flash('ok', L('resus_done', 'The clot is firm.'), 0);
        const after = (S.data.autoContinue || 1.6) * 1000;
        setTimeout(() => { if (S.proc === 'resus' && S.rs === rs) this.finish(); }, after);
      }
    },
    finish() {
      const rs = S.rs;
      if (!rs || rs.finished) return;
      rs.finished = true;
      const c = S.clot || {};
      const score = clamp(100 - (c.pops || 0) * 20, 0, 100);
      sendResult('resus', { score, pops: c.pops || 0 });
    },
    drawTeg() {
      const cv = q('.d-teg'); if (!cv) return;
      const { w, h } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      c.clearRect(0, 0, w, h);
      const mid = h / 2;
      c.strokeStyle = 'rgba(255,255,255,.07)'; c.lineWidth = 1;
      for (let i = 1; i < 6; i++) { c.beginPath(); c.moveTo((w / 6) * i, 0); c.lineTo((w / 6) * i, h); c.stroke(); }
      c.beginPath(); c.moveTo(0, mid); c.lineTo(w, mid); c.stroke();
      const hist = S.rs.tegHist; if (hist.length < 2) return;
      const n = 90;
      const pts = hist.map((v, i) => [(i / (n - 1)) * w, (clamp(v, 0, 100) / 100) * (h / 2 - 4)]);
      const grad = c.createLinearGradient(0, 0, 0, h); grad.addColorStop(0, 'rgba(15,212,196,.35)'); grad.addColorStop(0.5, 'rgba(15,212,196,.05)'); grad.addColorStop(1, 'rgba(15,212,196,.35)');
      c.fillStyle = grad; c.beginPath(); c.moveTo(0, mid);
      pts.forEach(([x, a]) => c.lineTo(x, mid - a)); for (let i = pts.length - 1; i >= 0; i--) c.lineTo(pts[i][0], mid + pts[i][1]);
      c.closePath(); c.fill();
      c.strokeStyle = '#0fd4c4'; c.lineWidth = 1.8; c.shadowColor = '#0fd4c4'; c.shadowBlur = 6;
      c.beginPath(); pts.forEach(([x, a], i) => (i ? c.lineTo(x, mid - a) : c.moveTo(x, mid - a))); c.stroke();
      c.beginPath(); pts.forEach(([x, a], i) => (i ? c.lineTo(x, mid + a) : c.moveTo(x, mid + a))); c.stroke();
      c.shadowBlur = 0;
    },
    drawStrip() {
      const cv = q('.d-strip'); if (!cv) return;
      const { w, h } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      c.clearRect(0, 0, w, h);
      const lo = 35, hi = 95;
      const y = v => h - ((clamp(v, lo, hi) - lo) / (hi - lo)) * h;
      c.fillStyle = 'rgba(61,220,132,.12)'; c.fillRect(0, y(S.band[1]), w, y(S.band[0]) - y(S.band[1]));
      c.strokeStyle = 'rgba(61,220,132,.5)'; c.lineWidth = 1; c.setLineDash([3, 3]);
      [S.band[0], S.band[1]].forEach(v => { c.beginPath(); c.moveTo(0, y(v)); c.lineTo(w, y(v)); c.stroke(); });
      c.strokeStyle = 'rgba(229,72,77,.5)'; const lm = S.data.lowMap || 52; c.beginPath(); c.moveTo(0, y(lm)); c.lineTo(w, y(lm)); c.stroke();
      c.setLineDash([]);
      const hist = S.rs.mapHist; if (hist.length < 2) return;
      c.strokeStyle = '#fff'; c.lineWidth = 1.8; c.beginPath();
      hist.forEach((v, i) => { const x = (i / 59) * w; if (i) c.lineTo(x, y(v)); else c.moveTo(x, y(v)); });
      c.stroke();
      const last = hist[hist.length - 1];
      c.fillStyle = last >= S.band[0] && last <= S.band[1] ? '#0fd4c4' : '#f3c35a';
      c.beginPath(); c.arc(((hist.length - 1) / 59) * w, y(last), 3.2, 0, Math.PI * 2); c.fill();
    },
    frame(dt) { if (S.rs) this.infTick(dt); },
    leave() { const rs = S.rs; if (rs && rs.txa) { rs.txa.destroy(); rs.txa = null; } ui.inf.style.display = 'none'; },
  };

  /* ═══════════════════════════ STEP 7 · REASSESS ═══════════════════════════ */
  H_.reassess = {
    enter() {
      ui.pp.set({ title: L('t_reassess', 'Reassess'), text: L('reassess_wait', 'Rechecking the patient…'), tools: [] });
      devFrame(L('d_reassess', 'Reassess'), `<div class="d-note">${esc(L('reassess_wait', 'Rechecking the patient…'))}</div>`, { brand: L('dev_field', 'Field') });
    },
    show(s) {
      const b = s.before || {}, a = s.after || {};
      if (a.bleed !== undefined) S.bleed = a.bleed;
      if (a.map) S.vit.map = a.map;
      S.metric = null; stats();
      const row = (k, bv, av, good) => `<span class="k">${esc(k)}</span><span class="b">${esc(bv ?? '--')}</span><span class="a ${good === true ? 'teal' : good === false ? 'red' : ''}">${esc(av ?? '--')}</span>`;
      const steps = (s.steps || []).map(st => `<div class="s"><span class="g ${st.skipped ? 'skip' : `g-${st.grade}`}">${esc(st.skipped ? '–' : st.grade || '?')}</span><span>${esc(st.label)}</span><i>${esc(st.skipped ? L('skipped', 'skipped') : st.note || `${st.score ?? ''}`)}</i></div>`).join('');
      devFrame(L('d_reassess', 'Reassess'), `
        <div class="fd-cmp"><span class="h"></span><span class="h">${esc(L('before', 'Before'))}</span><span class="h">${esc(L('now', 'Now'))}</span>
          ${row(L('st_bleed', 'Bleed'), b.bleed !== undefined ? `${fmt1(b.bleed)}` : '--', a.bleed !== undefined ? `${fmt1(a.bleed)}` : '--', a.bleed !== undefined && b.bleed !== undefined ? a.bleed < b.bleed : null)}
          ${row('MAP', b.map, a.map, a.map >= S.band[0] && a.map <= S.band[1] + 8)}
          ${row('HR', b.hr, a.hr, a.hr && b.hr ? a.hr <= b.hr : null)}
          ${row('SpO₂', b.spo2, a.spo2, a.spo2 >= 94)}</div>
        <div class="d-sep"></div><div class="fd-steps">${steps}</div>
        <div class="d-chips">${(s.devices || []).map(d => `<span class="d-chip on">${esc(d)}</span>`).join('')}</div>`, { brand: L('dev_field', 'Field'), right: s.grade || '' });
      ui.pp.complete({
        title: L('t_done', 'Patient reassessed'), label: L('finish', 'Finish'),
        text: s.text || L('reassess_text', 'Bleed {a} mL/min (was {b}). Hand over and transport.', { a: fmt1(a.bleed || 0), b: fmt1(b.bleed || 0) }),
        onDone: () => { post('done', {}); if (S.preview) NZA.toast({ title: L('t_done', 'Patient reassessed'), message: L('report_saved', 'Report written to the patient record.') }); },
      });
    },
  };

  /* ═══════════════════════════ IV CANNULATION ═══════════════════════════ */
  const IV_STEPS = ['tq', 'find', 'insert', 'advance', 'withdraw', 'secure'];
  const IV_EN = { tq: 'Tourniquet', find: 'Find the vein', insert: 'Insert the needle', advance: 'Advance the cannula', withdraw: 'Withdraw the needle', secure: 'Secure the line' };
  const ivTitle = id => L(`iv_t_${id}`, IV_EN[id] || id);
  H_.iv = {
    enter() {
      const d = S.data;
      S.total = 6;
      S.iv = { phase: 'tq', tq: false, fill: 0, attempts: 1, angle: 22, tip: 0, inVein: false, inT: 0, blown: false, flash: 0, mark: null, bounce: 0, palpQ: 0,
        cannula: 0, withdraw: 0, secured: false, flushed: false, spill: false, misses: 0, angleUsed: [], palp: false };
      d.siteLabel = d.siteLabel || L(`site_r_${d.site}`, d.site);
      this.go('tq');
    },
    go(ph) {
      const iv = S.iv;
      iv.phase = ph; S.n = IV_STEPS.indexOf(ph) + 1;
      ui.pp.set({ step: S.n, total: 6, title: ivTitle(ph), tag: L('t_iv', 'IV cannulation'), steps: stepNames() });
      stats();
      this.tools();
      if (ph === 'tq' || ph === 'find') this.armDev(); else this.xsecDev();
      this.text();
      if (ph === 'tq') mark('tq', { label: L('m_tq', 'Tourniquet'), dot: 'white' });
      else if (ph === 'find') mark('site', { label: L('m_forearm', 'Forearm'), dot: 'ring' });
      else clearMarks();
    },
    tools() {
      const iv = S.iv, ph = iv.phase;
      const releasing = iv.tq && (ph === 'withdraw' || ph === 'secure');
      const tq = { key: '1', label: releasing ? L('iv_tool_tq_off', 'Release tourniquet') : L('iv_tool_tq', 'Tourniquet'), icon: 'clamp',
        state: ph === 'tq' || releasing ? 'active' : iv.tq || ph === 'withdraw' || ph === 'secure' ? 'done' : '', sub: iv.tq && !releasing ? L('iv_tq_on_short', 'On') : '' };
      const tools = [tq,
        { key: '2', label: L('iv_tool_cannula', 'Cannula {g}G', { g: S.data.gauge || 18 }), icon: 'needle', state: ph === 'insert' || ph === 'advance' ? 'active' : ['withdraw', 'secure'].includes(ph) ? 'done' : 'locked' },
        { key: '3', label: L('iv_tool_dressing', 'Dressing'), icon: 'bandage', state: iv.secured ? 'done' : ph === 'secure' ? 'active' : 'locked' },
        { key: '4', label: L('iv_tool_flush', 'Flush'), icon: 'drop', state: iv.flushed ? 'done' : ph === 'secure' && iv.secured ? '' : 'locked' },
      ];
      ui.pp.set({ tools });
    },
    text() {
      const iv = S.iv, a = S.data.angle || [15, 30];
      const t = {
        tq: L('iv_tq', 'Put the **tourniquet** on the upper arm (1) and wait for the veins to fill.'),
        find: iv.fill < 1 ? L('iv_fill', 'Veins filling… {p}%', { p: Math.round(iv.fill * 100) }) : L('iv_find', 'Hold {Click} over the forearm to **palpate**. A springy, straight vein bounces back. Let go to mark it.'),
        insert: iv.inVein ? L('iv_flash', 'Flashback! Stop advancing.') : L('iv_insert', 'Set the angle ({a}–{b}°) with the wheel or ↑ ↓, then hold {{key}} to advance the needle.', { a: a[0], b: a[1], key: keyName(S.keys.insert || 'Space') }),
        advance: L('iv_advance', 'Lower the needle and hold {{key}} to slide the cannula off it into the vein. {p}%', { key: keyName(S.keys.advance || 'KeyE'), p: Math.round(iv.cannula * 100) }),
        withdraw: iv.tq ? L('iv_withdraw_tq', 'Release the **tourniquet** (1) before you pull the needle.') : L('iv_withdraw', 'Press on the vein and **drag the needle back** out of the cannula.'),
        secure: !iv.secured ? L('iv_secure', 'Cover the cannula with the **dressing** (3).') : !iv.flushed ? L('iv_flush', 'Flush the line (4) to check it runs.') : L('iv_done', 'Line in and running.'),
      }[iv.phase];
      ui.pp.set({ text: t });
    },
    armDev() {
      const d = S.data, map = d.map || { veins: [], best: 0, spot: 0.5 };
      const veins = map.veins.map((v, i) => {
        const y = v.y * 150, b = v.bend * 150;
        return `<path class="vn" data-i="${i}" d="M8 ${y + b * 0.6} C 90 ${y - b} 200 ${y + b} 292 ${y - b * 0.5}" fill="none" stroke="rgb(58,84,150)" stroke-width="${3 + v.width * 5}" stroke-linecap="round" opacity="0.12"/>`;
      }).join('');
      devFrame(L('d_arm', 'Forearm'), `
        <svg class="d-arm" viewBox="0 0 300 150">
          <defs><linearGradient id="skn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b78468"/><stop offset=".5" stop-color="#d4a387"/><stop offset="1" stop-color="#a87459"/></linearGradient></defs>
          <rect x="2" y="8" width="296" height="134" rx="60" fill="url(#skn)"/>
          <g class="veins">${veins}</g>
          <text x="12" y="146" font-size="7" fill="rgba(255,255,255,.4)" font-family="Lexend" font-weight="700" letter-spacing="1.5">${esc(L('d_wrist', 'WRIST'))}</text>
          <text x="288" y="146" text-anchor="end" font-size="7" fill="rgba(255,255,255,.4)" font-family="Lexend" font-weight="700" letter-spacing="1.5">${esc(L('d_elbow', 'ELBOW'))}</text>
          <g class="fing" style="display:none"><circle r="14" fill="rgba(255,255,255,.12)" stroke="#fff" stroke-width="1.5"/><circle class="rip" r="14" fill="none" stroke="#0fd4c4" stroke-width="2" opacity="0"/></g>
          <g class="pin" style="display:none"><circle r="6" fill="#08afa2" stroke="#fff" stroke-width="2"/></g>
        </svg>
        <div class="d-row" style="margin-top:8px;align-items:center"><div class="d-lbl" style="flex:1">${esc(L('d_bounce', 'Bounce'))}</div><div class="d-val bq" style="margin:0">--</div></div>
        <div class="d-bounce"></div>`, { brand: L('dev_iv', 'Cannulation'), right: `${S.data.gauge || 18}G` });
      const svg = ui.dev.querySelector('.d-arm');
      const pos = e => {
        const r = svg.getBoundingClientRect();
        return { x: clamp((e.clientX - r.left) / r.width, 0, 1) * 300, y: clamp((e.clientY - r.top) / r.height, 0, 1) * 150 };
      };
      svg.addEventListener('mousedown', e => { if (e.button !== 0 || S.iv.phase !== 'find' || S.iv.fill < 1) return; e.stopPropagation(); S.iv.palp = true; this.palpate(pos(e)); });
      svg.addEventListener('mousemove', e => { if (S.iv.palp) this.palpate(pos(e)); });
      if (this._up) window.removeEventListener('mouseup', this._up);
      window.addEventListener('mouseup', this._up = () => { if (S.iv && S.iv.palp) { S.iv.palp = false; this.markAt(); } });
    },
    veinDist(p) {
      const map = S.data.map || { veins: [] };
      let best = { d: 999, i: -1, v: null };
      map.veins.forEach((v, i) => {
        const tt = p.x / 300;
        // the vein path is a cubic: approximate y at x
        const y0 = v.y * 150, b = v.bend * 150;
        const P = [y0 + b * 0.6, y0 - b, y0 + b, y0 - b * 0.5];
        const yy = (1 - tt) ** 3 * P[0] + 3 * (1 - tt) ** 2 * tt * P[1] + 3 * (1 - tt) * tt * tt * P[2] + tt ** 3 * P[3];
        const d = Math.abs(p.y - yy) / (3 + v.width * 5);
        if (d < best.d) best = { d, i, v };
      });
      return best;
    },
    palpate(p) {
      const iv = S.iv, map = S.data.map || {};
      iv.cur = p;
      const b = this.veinDist(p);
      let q2 = b.v ? Math.exp(-(b.d * b.d) / 1.6) * (0.55 + b.v.width * 0.4) : 0;
      const spot = (map.spot || 0.5) * 300;
      const straight = b.i === map.best ? Math.exp(-((p.x - spot) ** 2) / (2 * 55 * 55)) : 0.35;
      q2 *= 0.55 + 0.45 * straight;
      iv.bounce = clamp(q2, 0, 1); iv.near = b;
      const f = ui.dev.querySelector('.fing'); if (f) { f.style.display = ''; f.setAttribute('transform', `translate(${p.x},${p.y})`); }
      const rip = ui.dev.querySelector('.rip'); if (rip) { rip.setAttribute('opacity', iv.bounce); rip.setAttribute('r', 10 + iv.bounce * 14); }
      ui.dev.querySelectorAll('.vn').forEach(v => { v.setAttribute('opacity', 0.12 + 0.35 * iv.fill + (Number(v.dataset.i) === b.i ? iv.bounce * 0.25 : 0)); });
      const bq = q('.bq'); if (bq) { bq.textContent = iv.bounce > 0.7 ? L('b_good', 'Springy — good vein') : iv.bounce > 0.35 ? L('b_ok', 'Soft') : L('b_none', 'Nothing'); bq.className = `d-val bq ${iv.bounce > 0.7 ? 'teal' : iv.bounce > 0.35 ? 'amber' : ''}`; }
      const bm = q('.d-bounce'); if (bm) bm.innerHTML = NZA.ui.meterHTML({ value: iv.bounce, zone: [0.7, 1], lg: true });
      if (iv.bounce > 0.7 && Math.random() < 0.08) NZA.audio.tick();
    },
    markAt() {
      const iv = S.iv;
      const f = ui.dev.querySelector('.fing'); if (f) f.style.display = 'none';
      if (!iv.cur || iv.bounce < 0.35) { ui.pp.flash('warn', L('iv_nothing', 'No vein under your fingers. Feel along the forearm.')); return; }
      iv.mark = iv.cur; iv.palpQ = iv.bounce; iv.vein = iv.near && iv.near.v;
      const pin = ui.dev.querySelector('.pin'); if (pin) { pin.style.display = ''; pin.setAttribute('transform', `translate(${iv.mark.x},${iv.mark.y})`); }
      ui.pp.flash(iv.bounce > 0.7 ? 'ok' : 'warn', iv.bounce > 0.7 ? L('iv_marked_good', 'Good vein marked.') : L('iv_marked_soft', 'Marked — a soft, small vein. Harder to hit.'));
      NZA.audio.click(820);
      setTimeout(() => { if (S.iv === iv && iv.phase === 'find') { iv.tip = 0; iv.inVein = false; iv.inT = 0; iv.blown = false; this.go('insert'); } }, 800);
    },
    xsecDev() {
      devFrame(L('d_xsec', 'Needle view'), `<canvas class="d-xsec" data-wheel="1"></canvas>
        <div class="d-row" style="margin-top:8px"><div style="flex:1"><div class="d-lbl">${esc(L('d_angle', 'Angle'))}</div><div class="d-big xa" style="font-size:22px">--</div></div>
          <div style="flex:1"><div class="d-lbl">${esc(L('d_chamber', 'Flash chamber'))}</div><div class="d-val xf">${esc(L('d_empty', 'Empty'))}</div></div></div>`, { brand: L('dev_iv', 'Cannulation'), right: `${S.data.gauge || 18}G` });
      const cv = ui.dev.querySelector('.d-xsec');
      cv.addEventListener('wheel', e => { e.preventDefault(); this.setAngle(S.iv.angle - Math.sign(e.deltaY) * 1); }, { passive: false });
      cv.addEventListener('mousedown', e => { if (e.button === 0 && S.iv.phase === 'withdraw') { e.stopPropagation(); S.iv.dragNeedle = true; } });
      if (this._mv) window.removeEventListener('mousemove', this._mv);
      if (this._mu) window.removeEventListener('mouseup', this._mu);
      window.addEventListener('mousemove', this._mv = e => {
        const iv = S.iv;
        if (!iv || !iv.dragNeedle || iv.phase !== 'withdraw' || !cv.isConnected) return;
        const px = Math.max(40, cv.offsetWidth * (NZA.zoom || 1));
        iv.withdraw = clamp((iv.withdraw || 0) + Math.max(0, -(e.movementX || 0)) / px * 2.2, 0, 1);
        if (iv.withdraw >= 1) this.withdrawn();
      });
      window.addEventListener('mouseup', this._mu = () => { if (S.iv) S.iv.dragNeedle = false; });
    },
    setAngle(a) {
      const iv = S.iv;
      if (iv.phase !== 'insert' || iv.tip > 2) return;
      iv.angle = clamp(Math.round(a), 5, 45);
      stats();
    },
    veinGeom() {
      const v = S.iv.vein || { depth: 4, width: 0.9 };
      const skin = 46, entryX = 58;
      const depthPx = 10 + v.depth * 9;
      const ry = 6 + v.width * 7, rx = 34 + v.width * 14;
      const cx = entryX + depthPx / Math.tan(22 * Math.PI / 180) * (0.85 + (1 - S.iv.palpQ) * 0.3), cy = skin + depthPx;
      return { skin, entryX, cx, cy, rx, ry };
    },
    xsecFrame(dt) {
      const iv = S.iv, d = S.data;
      const cv = q('.d-xsec'); if (!cv) return;
      const { w, h } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      const sx = w / 300, sy = h / 150;
      const g = this.veinGeom();
      const insertKey = S.keys.insert || 'Space';
      // advance the needle
      if (iv.phase === 'insert' && S.held[insertKey] && !iv.blown && !iv.miss) {
        iv.tip += dt * 38;
        if (iv.angleUsed.length < 1) iv.angleUsed.push(iv.angle);
      }
      if (iv.phase === 'advance' && S.held[insertKey] && !iv.blown) iv.tip += dt * 30;
      const a = iv.angle * Math.PI / 180;
      const tipX = g.entryX + Math.cos(a) * iv.tip, tipY = g.skin + Math.sin(a) * iv.tip;
      const inside = ((tipX - g.cx) ** 2) / (g.rx ** 2) + ((tipY - g.cy) ** 2) / (g.ry ** 2) <= 1;
      if (iv.phase === 'insert' || iv.phase === 'advance') {
        if (inside) {
          if (!iv.inVein) { iv.inVein = true; NZA.audio.beep(1100, 60, 0.05); if (iv.phase === 'insert') ui.pp.flash('ok', L('iv_flash', 'Flashback! Stop advancing.'), 1500); this.text(); }
          iv.flash = Math.min(1, iv.flash + dt * 2.5);
        } else if (iv.inVein && tipY > g.cy) {
          // went through the back wall
          iv.blown = true; iv.inVein = false; this.blown(); return;
        } else if (iv.tip > 175 && !iv.miss && iv.phase === 'insert') {
          iv.miss = true; iv.misses += 1;
          ui.pp.flash('warn', tipY < g.cy ? L('iv_miss_flat', 'Too flat — you went over the vein. Pull back and steepen.') : L('iv_miss_steep', 'Too steep — you went under the vein. Pull back and flatten.'));
          setTimeout(() => { if (S.iv === iv) { iv.tip = 0; iv.miss = false; } }, 1200);
        }
        if (iv.phase === 'insert' && iv.inVein && !S.held[insertKey] && !iv.blown) { iv.inT += dt; if (iv.inT > 0.5) { iv.inT = 0; this.go('advance'); } }
      }
      if (iv.phase === 'advance' && S.held[S.keys.advance || 'KeyE']) {
        iv.cannula = clamp(iv.cannula + dt * 0.55, 0, 1); this.text();
        if (iv.cannula >= 1) { NZA.audio.success(); ui.pp.flash('ok', L('iv_cannula_in', 'Cannula in the vein.')); this.go('withdraw'); }
      }
      // draw
      c.clearRect(0, 0, w, h);
      c.save(); c.scale(sx, sy);
      const sk = c.createLinearGradient(0, g.skin, 0, 150); sk.addColorStop(0, '#d9a98b'); sk.addColorStop(0.08, '#c48c70'); sk.addColorStop(1, '#8e5a44');
      c.fillStyle = '#0b0d0e'; c.fillRect(0, 0, 300, g.skin);
      c.fillStyle = sk; c.fillRect(0, g.skin, 300, 150 - g.skin);
      c.fillStyle = 'rgba(255,255,255,.05)'; for (let i = 0; i < 300; i += 22) c.fillRect(i, g.skin + 14, 12, 1);
      // vein
      c.fillStyle = iv.blown ? '#5a1f28' : '#3b4f8f';
      c.beginPath(); c.ellipse(g.cx, g.cy, g.rx, g.ry, 0, 0, Math.PI * 2); c.fill();
      c.fillStyle = iv.blown ? 'rgba(90,20,30,.55)' : '#7a1d26';
      c.beginPath(); c.ellipse(g.cx, g.cy, g.rx - 3, g.ry - 3, 0, 0, Math.PI * 2); c.fill();
      if (iv.blown) { c.fillStyle = 'rgba(80,10,25,.45)'; c.beginPath(); c.ellipse(g.cx, g.cy + 8, g.rx + 20, g.ry + 16, 0, 0, Math.PI * 2); c.fill(); }
      // angle band guide
      const band = d.angle || [15, 30];
      c.strokeStyle = 'rgba(61,220,132,.28)'; c.lineWidth = 1; c.setLineDash([3, 3]);
      band.forEach(b => { const r = b * Math.PI / 180; c.beginPath(); c.moveTo(g.entryX, g.skin); c.lineTo(g.entryX - Math.cos(r) * 52, g.skin - Math.sin(r) * 52); c.stroke(); });
      c.setLineDash([]);
      // needle (+ cannula sleeve) coming from the upper left
      const back = 120;
      const bx = tipX - Math.cos(a) * back, by = tipY - Math.sin(a) * back;
      const withdrawOff = iv.withdraw * 70;
      const nx = tipX - Math.cos(a) * withdrawOff, ny = tipY - Math.sin(a) * withdrawOff;
      c.lineCap = 'round';
      if (iv.phase !== 'secure') {
        c.strokeStyle = '#cfd6da'; c.lineWidth = 2.2; c.beginPath(); c.moveTo(bx - Math.cos(a) * withdrawOff, by - Math.sin(a) * withdrawOff); c.lineTo(nx, ny); c.stroke();
      }
      // cannula sleeve
      const sleeveTip = Math.min(iv.tip, iv.tip - 6 + iv.cannula * 16);
      const stx = g.entryX + Math.cos(a) * sleeveTip, sty = g.skin + Math.sin(a) * sleeveTip;
      c.strokeStyle = 'rgba(8,175,162,.85)'; c.lineWidth = 5; c.beginPath(); c.moveTo(bx + Math.cos(a) * 40, by + Math.sin(a) * 40); c.lineTo(stx, sty); c.stroke();
      // hub + flash chamber
      const hx = bx + Math.cos(a) * 30, hy = by + Math.sin(a) * 30;
      c.save(); c.translate(hx, hy); c.rotate(a);
      c.fillStyle = '#e9eef0'; c.fillRect(-22, -6, 26, 12);
      c.fillStyle = `rgba(160,20,30,${iv.flash})`; c.fillRect(-18, -4, 18 * iv.flash, 8);
      c.restore();
      c.restore();
      const xa = q('.xa'); if (xa) { xa.textContent = `${iv.angle}°`; xa.className = `d-big xa ${iv.angle < band[0] || iv.angle > band[1] ? 'amber' : 'teal'}`; xa.style.fontSize = '22px'; }
      const xf = q('.xf'); if (xf) { xf.textContent = iv.flash > 0.1 ? L('d_flash', 'Flashback') : L('d_empty', 'Empty'); xf.className = `d-val xf ${iv.flash > 0.1 ? 'red' : ''}`; }
    },
    blown() {
      const iv = S.iv, max = S.data.attempts || 2;
      NZA.audio.fail();
      ui.pp.flash('bad', L('iv_blown', 'Through the back wall — the vein is blown.'), 0);
      if (!S.preview && S.data.responsive) NZA.speech({ name: S.data.name || '', text: L('say_ouch', 'Ouch!'), ms: 1800 });
      setTimeout(() => {
        if (S.iv !== iv) return;
        if (iv.attempts >= max) { this.finish(true); return; }
        iv.attempts += 1; iv.blown = false; iv.flash = 0; iv.tip = 0; iv.inVein = false; iv.cannula = 0; iv.mark = null; stats();
        this.go('find');
        ui.pp.flash('warn', L('iv_new_site', 'New cannula — find another spot.'));
      }, 1600);
    },
    withdrawn() {
      const iv = S.iv;
      if (iv.phase !== 'withdraw') return;
      if (iv.tq) { iv.spill = true; ui.pp.flash('bad', L('iv_spill', 'Blood everywhere — the tourniquet was still on.')); }
      else { NZA.audio.success(); ui.pp.flash('ok', L('iv_needle_out', 'Needle out into the sharps bin.')); }
      iv.withdraw = 1;
      setTimeout(() => this.go('secure'), 700);
    },
    finish(failed) {
      const iv = S.iv;
      const band = S.data.angle || [15, 30];
      const ang = iv.angleUsed[0] || iv.angle;
      let score = 100 - (iv.attempts - 1) * 18 - iv.misses * 6 - (iv.spill ? 15 : 0) - (iv.flushed ? 0 : 6) - Math.round((1 - iv.palpQ) * 25);
      if (ang < band[0] || ang > band[1]) score -= 10;
      sendResult('iv', { site: S.data.site, attempts: iv.attempts, angle: ang, secured: iv.secured, failed: !!failed, score: Math.round(clamp(failed ? 10 : score, 0, 100)) });
    },
    tool(k) {
      const iv = S.iv;
      if (k === '1') {
        if (iv.phase === 'tq' && !iv.tq) { iv.tq = true; iv.fill = 0; post('ivTq', { on: true }); NZA.audio.click(500); ui.pp.flash('ok', L('iv_tq_on', 'Tourniquet on. Veins filling…')); this.go('find'); return; }
        if (iv.tq && (iv.phase === 'withdraw' || iv.phase === 'secure' || iv.phase === 'advance')) { iv.tq = false; post('ivTq', { on: false }); NZA.audio.click(400); ui.pp.flash('ok', L('iv_tq_off', 'Tourniquet released.')); this.tools(); this.text(); }
        return;
      }
      if (k === '3' && iv.phase === 'secure' && !iv.secured) { iv.secured = true; NZA.audio.click(900); ui.pp.flash('ok', L('iv_secured', 'Cannula covered and secured.')); this.tools(); this.text(); return; }
      if (k === '4' && iv.phase === 'secure' && iv.secured && !iv.flushed) {
        iv.flushed = true; NZA.audio.success(); ui.pp.flash('ok', L('iv_flushed', 'Flushes easily — no swelling.')); this.tools(); this.text();
        setTimeout(() => this.finish(false), 700);
      }
      if (k === 'Enter' && iv.phase === 'secure' && iv.secured) this.finish(false);
    },
    key(e, down) {
      const iv = S.iv;
      if (down && iv.phase === 'insert' && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) { this.setAngle(iv.angle + (e.key === 'ArrowUp' ? 1 : -1)); return true; }
      if (down && e.key === 'Enter' && iv.phase === 'secure' && iv.secured) { this.finish(false); return true; }
      return false;
    },
    frame(dt) {
      const iv = S.iv;
      if (!iv) return;
      if (iv.tq && iv.fill < 1) {
        iv.fill = Math.min(1, iv.fill + dt / (S.data.tourniquetFill || 3));
        if (iv.phase === 'find') { this.text(); ui.dev.querySelectorAll('.vn').forEach(v => v.setAttribute('opacity', 0.12 + 0.35 * iv.fill)); }
      }
      if (['insert', 'advance', 'withdraw', 'secure'].includes(iv.phase)) this.xsecFrame(dt);
    },
    leave() {
      if (this._up) window.removeEventListener('mouseup', this._up);
      if (this._mv) window.removeEventListener('mousemove', this._mv);
      if (this._mu) window.removeEventListener('mouseup', this._mu);
    },
  };

  /* ═══════════════════════════ INPUT ═══════════════════════════ */
  function keyName(code) {
    if (!code) return '';
    if (code === 'Space') return L('k_space', 'Space');
    if (/^Key[A-Z]$/.test(code)) return code.slice(3);
    if (/^Digit\d$/.test(code)) return code.slice(5);
    return code;
  }
  const onDown = e => {
    if (!S.open || e.button !== 0) return;
    S.mouse.down = true; S.mouse.x = e.clientX; S.mouse.y = e.clientY;
    if (e.target.closest && e.target.closest('.pp, .fd-focus, .fd-inf, .fd-dev')) return;
    const h = H_[S.proc]; if (h && h.down && S.status === 'run') h.down(e);
  };
  const onMove = e => {
    if (!S.open) return;
    S.mouse.x = e.clientX; S.mouse.y = e.clientY;
    const h = H_[S.proc]; if (h && h.move && S.status === 'run') h.move(e);
  };
  const onUp = e => {
    if (!S.open || e.button !== 0) return;
    S.mouse.down = false;
    const h = H_[S.proc]; if (h && h.up && S.status === 'run') h.up(e);
  };

  function keyDown(e) {
    S.held[e.code] = true; S.held[e.key] = true;
    if (/^F[1-4]$/.test(e.key)) {
      const f = S.keys.focus || {};
      const map = { [f.patient || 'F1']: 'patient', [f.site || 'F2']: 'site', [f.stand || 'F3']: 'stand', [f.kit || 'F4']: 'kit' };
      if (map[e.key]) { focusCam(map[e.key]); return true; }
    }
    const h = H_[S.proc];
    if (h && h.key && S.status === 'run' && h.key(e, true)) return true;
    if (e.key === 'Enter' && ui.pp && ui.pp.key(e)) return true;
    if (/^[1-6]$/.test(e.key) || /^[nNrR]$/.test(e.key)) { tool(e.key); return true; }
    return false;
  }
  function keyUp(e) {
    S.held[e.code] = false; S.held[e.key] = false;
    const h = H_[S.proc];
    if (h && h.key && S.status === 'run') h.key(e, false);
    return true;
  }

  /* ═══════════════════════════ LOOP ═══════════════════════════ */
  function loop(t) {
    if (!S.open) return;
    const dt = Math.min(0.05, (t - (lastT || t)) / 1000); lastT = t;
    const h = H_[S.proc];
    if (h && h.frame && S.status === 'run') { try { h.frame(dt); } catch (err) { console.error('[field]', err); } }
    if (S.preview && ui.scene) drawScene();
    raf = requestAnimationFrame(loop);
  }

  /* ═══════════════════════════ PREVIEW SCENE (browser only) ═══════════════════════════ */
  const PREV = {
    pelvis: { x: 0.47, y: 0.5 }, strapA: { x: 0.47, y: 0.64 }, strapB: { x: 0.47, y: 0.36 }, kit: { x: 0.45, y: 0.19 }, stand: { x: 0.4, y: 0.79 },
    l_tibia: { x: 0.665, y: 0.43 }, r_tibia: { x: 0.665, y: 0.57 }, l_humerus: { x: 0.31, y: 0.36 }, r_humerus: { x: 0.31, y: 0.64 }, access: { x: 0.665, y: 0.57 },
    tq: { x: 0.32, y: 0.5 }, site: { x: 0.52, y: 0.5 },
  };
  function previewAnchors() {
    const data = {};
    Object.keys(PREV).forEach(k => { data[k] = { x: PREV[k].x, y: PREV[k].y, visible: true, d: 1.5 }; });
    window.postMessage({ app: APP, action: 'anchors', data }, '*');
  }
  function drawScene() {
    const cv = ui.scene;
    const w = cv.width = W(), h = cv.height = H();
    const c = cv.getContext('2d');
    if (!ui.sceneBg) {
      const bg = document.createElement('canvas'); bg.width = w; bg.height = h;
      const g = bg.getContext('2d');
      g.fillStyle = '#3a3c3e'; g.fillRect(0, 0, w, h);
      for (let i = 0; i < 26000; i++) { const v = 40 + Math.random() * 60; g.fillStyle = `rgba(${v},${v},${v + 4},.5)`; g.fillRect(Math.random() * w, Math.random() * h, 2 + Math.random() * 3, 2 + Math.random() * 3); }
      const vg = g.createRadialGradient(w / 2, h / 2, h * 0.2, w / 2, h / 2, h * 0.9); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.55)');
      g.fillStyle = vg; g.fillRect(0, 0, w, h);
      ui.sceneBg = bg;
    }
    c.drawImage(ui.sceneBg, 0, 0);
    const P = k => ({ x: PREV[k].x * w, y: PREV[k].y * h });
    const s = h / 1080;
    const rr = (x, y, ww, hh, r, col) => { c.fillStyle = col; c.beginPath(); c.roundRect(x, y, ww, hh, r); c.fill(); };
    c.save(); c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 30 * s; c.shadowOffsetY = 8 * s;
    // legs
    rr(0.5 * w, 0.405 * h, 0.33 * w, 0.075 * h, 30 * s, '#232b3a'); rr(0.5 * w, 0.52 * h, 0.33 * w, 0.075 * h, 30 * s, '#232b3a');
    rr(0.82 * w, 0.4 * h, 0.035 * w, 0.085 * h, 16 * s, '#111'); rr(0.82 * w, 0.515 * h, 0.035 * w, 0.085 * h, 16 * s, '#111');
    // arms
    rr(0.27 * w, 0.31 * h, 0.2 * w, 0.06 * h, 26 * s, '#2a3446'); rr(0.27 * w, 0.63 * h, 0.2 * w, 0.06 * h, 26 * s, '#2a3446');
    rr(0.45 * w, 0.315 * h, 0.04 * w, 0.05 * h, 20 * s, '#c99b7d'); rr(0.45 * w, 0.635 * h, 0.04 * w, 0.05 * h, 20 * s, '#c99b7d');
    // torso + pelvis + head
    rr(0.22 * w, 0.355 * h, 0.3 * w, 0.29 * h, 70 * s, '#2a3446');
    rr(0.41 * w, 0.37 * h, 0.12 * w, 0.26 * h, 40 * s, '#232b3a');
    c.fillStyle = '#c99b7d'; c.beginPath(); c.ellipse(0.17 * w, 0.5 * h, 0.05 * w, 0.075 * h, 0, 0, Math.PI * 2); c.fill();
    c.fillStyle = '#2b1f18'; c.beginPath(); c.ellipse(0.155 * w, 0.5 * h, 0.035 * w, 0.07 * h, 0, 0, Math.PI * 2); c.fill();
    c.restore();
    // belt
    rr(0.445 * w, 0.37 * h, 0.012 * w, 0.26 * h, 4 * s, '#111');
    // blood pool
    c.fillStyle = 'rgba(90,10,14,.55)'; c.beginPath(); c.ellipse(0.5 * w, 0.66 * h, 0.06 * w, 0.03 * h, 0.2, 0, Math.PI * 2); c.fill();
    if (S.proc && S.proc !== 'binder' || (S.b && (S.b.phase === 'done'))) { rr(0.43 * w, 0.355 * h, 0.075 * w, 0.29 * h, 12 * s, '#1b2a30'); c.fillStyle = '#08afa2'; c.fillRect(0.462 * w, 0.48 * h, 0.012 * w, 0.04 * h); }
    // kit case (open) + sharps + stand
    const k = P('kit');
    c.save(); c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 24 * s;
    rr(k.x - 150 * s, k.y - 120 * s, 300 * s, 120 * s, 14 * s, '#2a3033'); rr(k.x - 150 * s, k.y, 300 * s, 150 * s, 14 * s, '#30373a');
    c.restore();
    rr(k.x - 136 * s, k.y + 14 * s, 272 * s, 122 * s, 10 * s, '#1c2124');
    rr(k.x - 120 * s, k.y + 28 * s, 70 * s, 95 * s, 8 * s, S.proc === 'binder' && S.b && S.b.phase === 'drop' ? '#1b2a30' : '#151a1c');
    c.fillStyle = '#08afa2'; c.fillRect(k.x - 92 * s, k.y + 60 * s, 14 * s, 14 * s);
    rr(k.x - 30 * s, k.y + 40 * s, 60 * s, 24 * s, 8 * s, '#3b4448'); rr(k.x + 50 * s, k.y + 34 * s, 70 * s, 12 * s, 5 * s, '#d7dde0'); rr(k.x + 50 * s, k.y + 60 * s, 70 * s, 12 * s, 5 * s, '#d7dde0');
    c.fillStyle = '#08afa2'; c.fillRect(k.x - 60 * s, k.y + 146 * s, 24 * s, 6 * s); c.fillRect(k.x + 36 * s, k.y + 146 * s, 24 * s, 6 * s);
    rr(k.x + 190 * s, k.y - 10 * s, 70 * s, 90 * s, 8 * s, '#e3c13a'); rr(k.x + 186 * s, k.y - 16 * s, 78 * s, 26 * s, 8 * s, '#d9822b');
    if (S.proc === 'resus' || S.proc === 'reassess') {
      const st = P('stand');
      c.strokeStyle = '#9aa3a8'; c.lineWidth = 5 * s; [0, 2.1, 4.2].forEach(a => { c.beginPath(); c.moveTo(st.x, st.y); c.lineTo(st.x + Math.cos(a) * 70 * s, st.y + Math.sin(a) * 70 * s); c.stroke(); });
      rr(st.x - 26 * s, st.y - 46 * s, 52 * s, 80 * s, 10 * s, 'rgba(210,230,240,.75)');
      c.strokeStyle = 'rgba(230,240,245,.6)'; c.lineWidth = 2 * s; c.beginPath(); c.moveTo(st.x, st.y + 30 * s); c.quadraticCurveTo(0.45 * w, 0.8 * h, P('access').x, P('access').y); c.stroke();
    }
  }

  /* ═══════════════════════════ APP ═══════════════════════════ */
  NZA.app(APP, {
    full: true, escClose: false, modalKeys: true,
    init(el) {
      ui.host = el;
      window.addEventListener('mousedown', onDown, true);
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', onUp);
    },
    open(d) {
      d = d || {};
      S.open = true;
      if (d.locale) loc = Object.assign({}, loc, d.locale);
      S.mode = d.mode === 'iv' ? 'iv' : 'resus';
      S.plan = d.plan || {}; S.keys = d.keys || {}; S.total = S.mode === 'iv' ? 6 : 7; S.results = [];
      S.band = (S.plan.band) || [60, 70]; S.bleed = S.plan.bleed || 0; S.injury = S.plan.injury || null; S.focus = 'patient';
      S.proc = null; S.status = ''; S.clot = null; S.b = S.io = S.rs = S.iv = null;
      build();
      ui.dev.style.display = 'none';
      ui.pp.set({ step: 1, total: S.total, title: S.mode === 'iv' ? L('t_iv', 'IV cannulation') : L('t_field', 'Field resuscitation'), text: L('starting', 'Opening the kit…'), tools: [], steps: stepNames() });
      stats();
      lastT = 0; cancelAnimationFrame(raf); raf = requestAnimationFrame(loop);
    },
    close() {
      S.open = false;
      const h = H_[S.proc]; if (h && h.leave) { try { h.leave(); } catch (e) { /* closing */ } }
      cancelAnimationFrame(raf);
      clearMarks();
      if (ui.pp) { ui.pp.destroy(); ui.pp = null; }
      if (ui.ov) { ui.ov.remove(); ui.ov = null; }
      if (ui.ghost) { ui.ghost.remove(); ui.ghost = null; }
      if (ui.scene) { ui.scene.remove(); ui.scene = null; ui.sceneBg = null; }
      if (ui.host) ui.host.innerHTML = '';
      S.proc = null;
    },
    keys: new Proxy({}, { get: (_, k) => (k === 'Escape' ? undefined : e => (S.open ? keyDown(e) : false)) }),
    keysUp: new Proxy({}, { get: () => e => (S.open ? keyUp(e) : false) }),
    msg: {
      step(d) { if (!d) return; setStep(d.proc, d.status || 'run', d.data, d.reason); },
      outcome(d) {
        if (!d) return;
        S.waiting = false;
        const o = d.outcome || {};
        if (d.ok && !o.failed) {
          S.results.push({ proc: d.proc, score: o.score, grade: o.grade });
          ui.pp.flash('ok', `${o.msg || L('ok_generic', 'Done')} · ${o.grade || grade(o.score || 0)}`, 0);
        } else {
          ui.pp.flash('bad', o.msg || d.msg || L(`err_${d.reason}`, L('step_failed', 'That did not work.')), 0);
        }
        if (d.proc === 'iv' && ui.pp) ui.pp.set({ tools: [] });
      },
      vitals(v) {
        if (!v) return;
        S.vit = v;
        if (v.bleed !== undefined && !(S.proc === 'resus' && S.clot)) S.bleed = v.bleed;
        if (v.injury) S.injury = v.injury;
        stats();
      },
      clot(c) { if (!c || S.proc !== 'resus' || !S.rs) return; S.clot = c; H_.resus.clotTick(); },
      popped() { if (S.proc !== 'resus') return; NZA.audio.alarm(2); ui.pp.flash('bad', L('popped', 'The clot popped! Bleeding is back up.'), 3200); if (S.rs) S.rs.popped += 1; },
      focus(d) { if (d && d.what) { S.focus = d.what; renderFocus(); } },
      summary(s) { if (S.proc !== 'reassess') setStep('reassess', 'run', {}); H_.reassess.show(s || {}); },
      bags(b) { if (!b || !S.rs) return; if (b.counts) S.rs.counts = b.counts; if (b.bags) S.data.bags = b.bags; H_.resus.tools(); },
      drill(d) { if (d && d.flash && ui.pp) ui.pp.flash(d.type || 'warn', d.flash); },
    },
    preview() {
      S.preview = true;
      ui.scene = document.createElement('canvas'); ui.scene.className = 'fd-scene';
      document.body.appendChild(ui.scene);
      const plan = { band: [60, 70], bleed: 101, injury: { region: 'abdomen', regionLabel: 'Abdomen', type: 'internal' } };
      NZA.open(APP, { mode: 'resus', plan, keys: { drill: 'Space', squeeze: 'Space', clampDown: 'KeyQ', clampUp: 'KeyE', insert: 'Space', advance: 'KeyE', focus: { patient: 'F1', site: 'F2', stand: 'F3', kit: 'F4' } } });
      previewAnchors();
      NZA.demo('monitor', { name: 'Michael Garcia', nibpAuto: 30, nibpTime: 2.5 });
      const vit = { hr: 139, ecgRate: 139, spo2: 97, sys: 87, dia: 51, map: 63, rr: 22, temp: 35.6, etco2: 33, rhythm: 'stach', state: 'wounded' };
      NZA.apps[APP].msg.vitals({ map: 63, hr: 139, spo2: 97 });
      setInterval(() => NZA.apps.monitor.msg.vitals(Object.assign({}, vit, { hr: vit.hr + Math.round(Math.random() * 2) })), 1000);
      NZA.apps.monitor.msg.vitals(vit);
      setTimeout(() => NZA.apps.monitor.msg.nibp(), 200);
      NZA.apps[APP].demoStep('binder');
    },
    // browser preview helper: jump to a step / phase with demo data
    demoStep(which, sub) {
      const sites = { r_tibia: { ok: true, region: 'r_lower_leg' }, l_tibia: { ok: false, why: 'fracture', region: 'l_lower_leg' }, r_humerus: { ok: true, region: 'r_upper_arm' }, l_humerus: { ok: true, region: 'l_upper_arm' } };
      const ioData = { sites, layers: { tibia: { soft: 6.5, cortex: 3.2, marrow: 13, far: 3 }, humerus: { soft: 12, cortex: 2.6, marrow: 16, far: 3 } }, maxAngle: 15, bendAngle: 26, attempts: 3,
        speed: { soft: 7, cortex: 1.3, marrow: 8, far: 1.1 }, pxPerDeg: 3.2, tremor: 7, aspirateMl: 1, lidoMl: 2, lidoRate: [0.08, 0.45], flushMl: 10, flushRate: [1.5, 6], lidocaine: true, responsive: true,
        injury: { region: 'abdomen', regionLabel: 'Abdomen' }, bleed: 101 };
      if (which === 'binder') { setStep('binder', 'run', { indicated: true, why: 'fracture', band: [60, 80], count: 1, injury: { regionLabel: 'Pelvis' }, bleed: 241 }); if (sub === 'strap') { S.b.phase = 'strap'; clearMarks(); H_.binder.ui(); S.b.tension = 72; S.b.tab = null; const A = apx('strapA'), B = apx('strapB'); if (A && B) S.b.tab = { x: A.x + (B.x - A.x) * 0.72, y: A.y + (B.y - A.y) * 0.72 }; H_.binder.devTick(); } }
      if (which === 'site') setStep('io', 'run', ioData);
      if (which === 'drill') { setStep('io', 'run', ioData); H_.io.pick('r_tibia'); const p = apx('r_tibia'); S.mouse.x = p.x + 30; S.mouse.y = p.y - 26; S.mouse.down = true; S.io.lift = 0; S.io.depth = 7.8; S.io.drilling = false; S.io.torque = Array.from({ length: 80 }, (_, i) => (i < 30 ? 0.25 : 0.88) + (Math.random() - 0.5) * 0.1); }
      if (which === 'confirm') { setStep('io', 'run', ioData); H_.io.pick('r_tibia'); H_.io.confirmUi(); S.io.syr.set(1.4); S.io.syr.fluid('marrow'); ui.pp.flash('ok', L('confirm_ok', 'Marrow blood in the barrel. The needle is in.'), 0); }
      if (which === 'flush') { setStep('io', 'run', ioData); H_.io.pick('r_tibia'); S.io.aspirated = true; H_.io.flushUi(); S.io.ext = true; H_.io.useSyringe('lido'); S.io.syr.set(2 - 0.8); S.io.lido.ml = 0.8; H_.io.flushText(); }
      if (which === 'resus') {
        setStep('resus', 'run', { band: [60, 70], hold: 24, lowMap: 52, autoContinue: 1.6, access: { kind: 'io', site: 'r_lower_leg', siteLabel: 'Right tibia' }, maxRate: 66, txaPush: 10,
          infusion: { gravity: 60, ioFactor: 0.45, pressureGain: 1.4, maxPressure: 300, leak: 6, pump: 22, maxBags: 3, dilution: 1000 },
          counts: { saline: 2, txa: 1, foil: 1 }, blood: true, bags: [{ serial: 'NZ-0042', type: 'O-', ml: 450, compatible: true }],
          infusions: [{ id: 'i1', kind: 'saline', ml: 500, left: 382, rate: 58, mine: true }], injury: { regionLabel: 'Abdomen' }, bleed: 19 });
        S.rs.pressure = 186; S.rs.clamp = 0.66; S.rs.salineIn = 0;
        const hist = [52, 53, 55, 57, 58, 60, 61, 62, 63, 64, 63, 64, 65, 64, 63, 63, 64, 62, 63, 64, 65, 66, 64, 63];
        hist.forEach((m, i) => { S.clot = { map: m, firm: Math.min(93, i * 4.3), state: 'band', eta: 8, pops: 0, mods: { txa: false, cold: true, foil: false, dil: 12 }, bleed: 19 }; H_.resus.clotTick(); });
      }
      if (which === 'reassess') {
        setStep('reassess', 'run', {});
        H_.reassess.show({ before: { bleed: 241, map: 52, hr: 141, spo2: 93 }, after: { bleed: 11.4, map: 64, hr: 118, spo2: 97 }, grade: 'A',
          steps: [{ label: 'Pelvic binder', grade: 'A', score: 88 }, { label: 'IO access · right tibia', grade: 'B', score: 74 }, { label: 'Resuscitate', grade: 'S', score: 94 }],
          devices: ['Binder', 'IO R tibia', 'Saline 380 ml', 'TXA 1 g', 'Clot 100%'] });
      }
      if (which === 'iv') {
        NZA.close('monitor');
        NZA.open(APP, { mode: 'iv', plan: {}, keys: S.keys });
        previewAnchors();
        setStep('iv', 'run', { site: 'r_lower_arm', siteLabel: 'Right forearm', angle: [15, 30], attempts: 2, gauge: 18, tourniquetFill: 3, flash: 0.9, responsive: true, name: 'Michael Garcia',
          map: { veins: [{ y: 0.28, bend: 0.04, width: 0.7, depth: 3.5 }, { y: 0.52, bend: 0.01, width: 1.15, depth: 3 }, { y: 0.76, bend: -0.06, width: 0.65, depth: 5 }], best: 1, spot: 0.5 } });
        if (sub === 'find') { S.iv.tq = true; S.iv.fill = 1; H_.iv.go('find'); H_.iv.palpate({ x: 150, y: 80 }); S.iv.palp = false; }
        if (sub === 'insert') { S.iv.tq = true; S.iv.fill = 1; S.iv.mark = { x: 150, y: 78 }; S.iv.palpQ = 0.85; S.iv.vein = S.data.map.veins[1]; H_.iv.go('insert'); S.iv.angle = 22; S.iv.tip = 58; }
      }
    },
  });
})();
