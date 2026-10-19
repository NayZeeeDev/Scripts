/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · field — field resuscitation (7 steps) and IV cannulation

   Layout (with the core procedure HUD: step column bottom-left, tool belt right edge):
     · the PM-4 monitor top-left (monitor app)
     · VIEW selector (camera focus keys) inside the step column's slot
     · an instrument RACK mounted beside the tool belt (right-middle, left of the belt):
       one device per step — BT-3 binder tensioner, IO-7 driver (bubble level + bone
       cross-section), SX-10 syringe (vertical, rate dial), CA-2 clot analyser +
       PI-3 pressure infuser (step 6), VF-2 vein finder / NC-1 needle cam (IV), handover card.
     · in-world diamond markers + an overlay for the strap / drill aim (anchors layer)
   Devices carry generic model codes and warning stickers, never a brand.

   Lua → JS
     open      { mode = 'resus'|'iv', plan, keys, locale, focus = { patient, site, stand, kit } }
     step      { proc = 'binder'|'io'|'resus'|'reassess'|'iv', status = 'run'|'skip'|'blocked'|'easy', data, reason }
     outcome   { proc, ok, outcome | reason }           (server answer for a finished step)
     vitals    { hr, sys, dia, map, spo2, rr, temp, etco2, rhythm, bleed, state, injury }
     clot      server model of the resuscitate step (see server/modules/field_procs.lua)
     popped    {}                                         the clot gave way
     focus     { what }                                   camera focus key highlight
     summary   { before, after, steps[], devices, given, clot }   step 7
     bags      { counts, bags[] }
     drill     { flash, type }
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
  const fmt1 = n => (Math.round(n * 10) / 10).toFixed(1);
  const grade = s => (s >= 92 ? 'S' : s >= 80 ? 'A' : s >= 65 ? 'B' : s >= 50 ? 'C' : s >= 35 ? 'D' : 'F');
  const toneOf = (v, lo, hi) => (v > hi ? 'red' : v >= lo ? 'teal' : v > 0 ? 'amber' : '');

  /* ═══════════════════════════ STATE ═══════════════════════════ */
  const S = {
    open: false, mode: 'resus', plan: {}, keys: {}, preview: false,
    proc: null, status: '', data: {}, n: 1, total: 7, phase: '',
    vit: {}, bleed: 0, injury: null, band: [60, 70], clot: null,
    mouse: { x: 0, y: 0, down: false }, held: {}, results: [], focus: 'patient',
    b: null, io: null, rs: null, iv: null, waiting: false,
  };
  const ui = { host: null, view: null, rack: null, dev: null, inf: null, ov: null, pp: null, ghost: null, scene: null };
  let raf = 0, lastT = 0;

  const anchors = () => (NZA.apps[APP] ? NZA.apps[APP].anchors.map : {}) || {};
  function apx(id) {
    const a = anchors()[id];
    if (!a || a.visible === false) return null;
    return { x: a.x * W(), y: a.y * H() };
  }
  const pxScale = () => H() / 1080;
  // is the pointer over the open kit case? (screen box of its corners, else a ring around the centre)
  const KIT_PTS = ['kitA', 'kitB', 'kitC', 'kitD', 'kitE', 'kitF'];
  function overKit(x, y) {
    const pts = KIT_PTS.map(apx).filter(Boolean);
    const c = apx('kit');
    if (c) pts.push(c);
    if (!pts.length) return false;
    if (pts.length >= 3) {
      const pad = 16 * pxScale();
      const xs = pts.map(p => p.x), ys = pts.map(p => p.y);
      if (x >= Math.min(...xs) - pad && x <= Math.max(...xs) + pad && y >= Math.min(...ys) - pad && y <= Math.max(...ys) + pad) return true;
    }
    return !!c && Math.hypot(x - c.x, y - c.y) < 110 * pxScale();
  }

  /* ═══════════════════════════ DRAWING HELPERS ═══════════════════════════ */
  // 240° dial (value / zone 0..1) — used by the tensioner, the syringe rate and the infuser
  function dialSVG(v, { zone = null, tone = '', ticks = 12, label = '' } = {}) {
    const R = 44, C = 60, A0 = 150, SW = 240;
    const pt = (f, r = R) => { const a = (A0 + SW * clamp(f, 0, 1)) * Math.PI / 180; return [C + r * Math.cos(a), C + r * Math.sin(a)]; };
    const arc = (f0, f1, r = R) => { const [x0, y0] = pt(f0, r), [x1, y1] = pt(f1, r); return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${(f1 - f0) * SW > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`; };
    let tk = '';
    for (let i = 0; i <= ticks; i++) { const [a, b] = pt(i / ticks, R + 7), [c, d] = pt(i / ticks, R + (i % 3 ? 10 : 13)); tk += `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${d.toFixed(1)}"/>`; }
    const f = clamp(v, 0, 1);
    const [nx, ny] = pt(f);
    return `<svg viewBox="0 0 120 108" class="dz ${tone}">
      <g class="tk">${tk}</g><path class="tr" d="${arc(0, 1)}"/>
      ${zone ? `<path class="zn" d="${arc(zone[0], zone[1])}"/>` : ''}
      ${f > 0.004 ? `<path class="fl" d="${arc(0, Math.max(f, 0.005))}"/><circle class="nb" cx="${nx.toFixed(2)}" cy="${ny.toFixed(2)}" r="3.4"/>` : ''}
      ${label ? `<text x="60" y="100" class="lb">${esc(label)}</text>` : ''}
    </svg>`;
  }
  // rounded-rect path without CanvasRenderingContext2D.roundRect (older CEF builds)
  function rrPath(c, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath();
  }
  // instrument list rows: label left, mono value right, tone notch
  const row = (cls, label, value, tone = '') => `<div class="m-row ${cls} ${tone}"><span class="k">${esc(label)}</span><span class="v">${value}</span></div>`;
  function setRow(sel, value, tone) { const r = q(sel); if (!r) return; r.querySelector('.v').innerHTML = value; r.className = r.className.replace(/\b(teal|amber|red|dim)\b/g, '').trim() + (tone ? ` ${tone}` : ''); }

  /* ── vertical syringe (drag the plunger; push = drag down, pull = drag up) ── */
  function Syringe(host, o) {
    o = Object.assign({ cap: 10, vol: 0, mode: 'push', fluid: 'clear', band: null, maxRate: 1, flashAt: null, label: '', compact: false }, o);
    const root = NZA.el('div', `syr ${o.band ? 'wb' : ''} ${o.compact ? 'cmp' : ''} ${o.mode}`);
    const fluidCol = { clear: 'rgba(175,220,240,.5)', lido: 'rgba(150,200,255,.62)', blood: 'rgba(150,20,28,.92)', marrow: 'rgba(110,12,18,.96)', txa: 'rgba(196,236,226,.6)' };
    const TOP = 140, BOT = 264, LEN = BOT - TOP, ROD = LEN + 8, VH = 296;
    let grads = '';
    const step = o.cap <= 5 ? 0.5 : 1;
    for (let i = 0; i <= o.cap + 1e-6; i += step) {
      const y = BOT - (i / o.cap) * LEN, major = Math.abs(i % (o.cap <= 5 ? 1 : 2)) < 1e-6;
      grads += `<line x1="${major ? 38 : 42}" y1="${y.toFixed(1)}" x2="48" y2="${y.toFixed(1)}"/>`;
      if (major && i > 0) grads += `<text x="10" y="${(y + 2.3).toFixed(1)}">${i}</text>`;
    }
    const gid = `syrg${Math.random().toString(36).slice(2, 7)}`;
    root.innerHTML = `
      <div class="syr-col"><svg viewBox="0 0 64 ${VH}">
        <defs><linearGradient id="${gid}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="rgba(255,255,255,.2)"/><stop offset=".35" stop-color="rgba(255,255,255,.04)"/><stop offset=".8" stop-color="rgba(255,255,255,.1)"/><stop offset="1" stop-color="rgba(255,255,255,.22)"/></linearGradient></defs>
        <g class="pl"><rect class="thumb" x="15" y="${-ROD - 7}" width="34" height="7" rx="3"/><rect class="rod" x="29.5" y="${-ROD}" width="5" height="${ROD}" rx="1"/><path class="rodx" d="M26 ${-ROD + 2}h12M26 -10h12"/><rect class="stop" x="17" y="0" width="30" height="7" rx="2"/><path class="ribs" d="M17 2.3h30M17 4.7h30"/></g>
        <rect class="liq" x="17" y="${BOT}" width="30" height="0" fill="${fluidCol[o.fluid] || fluidCol.clear}"/>
        <rect class="flange" x="4" y="${TOP - 6}" width="56" height="6" rx="2"/>
        <rect class="barrel" x="16" y="${TOP}" width="32" height="${LEN}" rx="3" fill="url(#${gid})"/>
        <g class="gr">${grads}</g>
        <path class="hub" d="M24 ${BOT}h16l-2 10h-12z"/><rect class="luer" x="27" y="${BOT + 10}" width="10" height="7" rx="1"/>
        <line class="ndl" x1="32" y1="${BOT + 17}" x2="32" y2="${VH}"/>
      </svg><span class="syr-grip">${icon('chev-u')}${icon('chev-d')}</span></div>
      <div class="syr-side">
        <div class="syr-k">${esc(o.label)}</div>
        <div class="syr-v"><b class="vol">0.0</b><i>/ ${o.cap} ml</i></div>
        ${o.band ? `<div class="syr-dial"><div class="sd"></div><div class="sdv"><b class="rate">0.00</b><i>ml/s</i></div></div><div class="syr-bar"><span class="zn" style="left:${(clamp(o.band[0] / o.maxRate, 0, 1) * 100).toFixed(1)}%;width:${((clamp(o.band[1] / o.maxRate, 0, 1) - clamp(o.band[0] / o.maxRate, 0, 1)) * 100).toFixed(1)}%"></span><span class="nd"></span><span class="sc"><i>0</i><i class="rv">0.00 ml/s</i><i>${o.maxRate.toFixed(1)}</i></span></div><div class="syr-st"><span class="dot"></span><span class="rl"></span></div>`
          : `${o.flashAt ? `<div class="syr-dial fc"><div class="sd"></div><div class="sdv"><b class="fcv">0.0</b><i>${esc(L('syr_of', 'of {n} ml', { n: o.flashAt }))}</i></div><span class="fcl">${esc(L('syr_drawn', 'Drawn'))}</span></div>` : ''}<div class="syr-ret"></div>`}
      </div>`;
    host.appendChild(root);
    let vol = o.vol, rate = 0, dragging = false, lastMove = now(), acc = 0, flashed = false, fluid = o.fluid, dead = false;
    // Holding the plunger still moves it by itself at a steady speed inside the target band (a drag
    // of a few pixels a second is not something a mouse can do); dragging still works for fine
    // control and takes over while the mouse moves. api.auto(true) runs it without a hold (keys).
    const autoRate = o.autoRate || (o.band ? o.band[0] + (o.band[1] - o.band[0]) * 0.7 : 1.2);
    let lastDrag = 0, lastY = null, autoOn = false;
    const liq = root.querySelector('.liq'), pl = root.querySelector('.pl');
    const draw = () => {
      const y = BOT - clamp(vol / o.cap, 0, 1) * LEN;
      liq.setAttribute('y', (y + 7).toFixed(1));
      liq.setAttribute('height', Math.max(0, BOT - y - 7).toFixed(1));
      liq.setAttribute('fill', fluidCol[fluid] || fluidCol.clear);
      pl.setAttribute('transform', `translate(0,${y.toFixed(1)})`);
      root.querySelector('.vol').textContent = fmt1(vol);
      if (!o.band && o.flashAt) {
        const f = clamp(vol / o.flashAt, 0, 1), tone = flashed ? 'red' : f > 0.01 ? 'teal' : '';
        root.querySelector('.fc .sd').innerHTML = dialSVG(f, { zone: [0.92, 1], tone, ticks: 9 });
        const fb = root.querySelector('.fcv');
        fb.textContent = fmt1(Math.min(vol, o.flashAt));
        fb.className = `fcv ${tone}`;
        root.querySelector('.fc').classList.toggle('hit', flashed);
      }
      if (o.band) {
        const tone = rate > o.band[1] ? 'red' : rate >= o.band[0] && rate > 0.01 ? 'teal' : rate > 0.01 ? 'amber' : '';
        root.querySelector('.sd').innerHTML = dialSVG(rate / o.maxRate, { zone: [o.band[0] / o.maxRate, Math.min(1, o.band[1] / o.maxRate)], tone, ticks: 9 });
        const rb = root.querySelector('.rate');
        rb.textContent = rate.toFixed(2);
        rb.className = `rate ${tone}`;
        const nd = root.querySelector('.syr-bar .nd');
        nd.style.left = `${(clamp(rate / o.maxRate, 0, 1) * 100).toFixed(1)}%`;
        nd.className = `nd ${tone}`;
        root.querySelector('.syr-bar .rv').textContent = `${rate.toFixed(2)} ml/s`;
        const st = root.querySelector('.syr-st');
        st.className = `syr-st ${tone}`;
        root.querySelector('.rl').textContent = rate < 0.01 ? L('syr_idle', 'Idle') : rate > o.band[1] ? L('syr_fast', 'Too fast') : rate >= o.band[0] ? L('syr_band', 'On target') : L('syr_slow', 'Too slow');
      }
    };
    const barrelPx = () => Math.max(40, root.querySelector('.syr-col svg').getBoundingClientRect().height * (LEN / VH));
    const applyVol = nv => {
      if (o.mode === 'push') nv = Math.min(vol, nv); else nv = Math.max(vol, nv);
      nv = clamp(nv, 0, o.cap);
      const d = Math.abs(nv - vol);
      if (d > 0) { acc += d; vol = nv; lastMove = now(); }
      if (o.flashAt !== null && !flashed && o.mode === 'pull' && vol >= o.flashAt) { flashed = true; fluid = 'marrow'; autoOn = false; o.onFlash && o.onFlash(); }
      draw();
      o.onChange && o.onChange(vol, rate);
    };
    const onDown = e => { if (e.button !== 0 || dead) return; dragging = true; lastY = e.clientY; lastDrag = 0; root.classList.add('drag'); e.preventDefault(); e.stopPropagation(); };
    const onMove = e => {
      if (!dragging || dead) return;
      // screen distance since the last event (movementY can be missing in embedded browsers)
      const dy = lastY === null ? 0 : e.clientY - lastY;
      lastY = e.clientY;
      if (!dy) return;
      lastDrag = now();
      applyVol(vol - (dy / barrelPx()) * o.cap);
    };
    const onUp = () => { if (!dragging) return; dragging = false; lastY = null; root.classList.remove('drag'); o.onRelease && o.onRelease(vol, rate); };
    root.querySelector('.syr-col').addEventListener('mousedown', onDown);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    let tPrev = now();
    const tick = () => {
      if (dead) return;
      const t = now(), dt = Math.max(0.001, (t - tPrev) / 1000); tPrev = t;
      // held still (or auto): the plunger moves at the steady speed
      if ((dragging && t - lastDrag > 180) || autoOn) {
        const full = o.mode === 'push' ? vol <= 0 : vol >= o.cap;
        if (!full) applyVol(vol + autoRate * Math.min(dt, 0.25) * (o.mode === 'push' ? -1 : 1));
        else autoOn = false;
      }
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
      auto(on) { autoOn = !!on && !dead; },
      set(v) { vol = clamp(v, 0, o.cap); draw(); },
      fluid(f) { fluid = f; if (f === 'marrow') flashed = true; draw(); },
      ret(html) { const r = root.querySelector('.syr-ret'); if (r) r.innerHTML = html; },
      destroy() { dead = true; window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp); root.remove(); },
    };
  }

  /* ═══════════════════════════ LAYOUT ═══════════════════════════ */
  const UNITS = {
    bt: ['BT-3', 'u_bt', 'Binder tensioner', 'stk_pinch', 'Pinch point'],
    io: ['IO-7', 'u_io', 'IO driver', 'stk_sharp', 'Sharp · single use'],
    sx: ['SX-10', 'u_sx', 'Syringe', 'stk_luer', 'Luer lock'],
    ca: ['CA-2', 'u_ca', 'Clot analyser', 'stk_bio', 'Biohazard'],
    pi: ['PI-3', 'u_pi', 'Pressure infuser', 'stk_press', '300 mmHg max'],
    vf: ['VF-2', 'u_vf', 'Vein finder', 'stk_led', 'Do not stare into LED'],
    nc: ['NC-1', 'u_nc', 'Needle cam', 'stk_sharp', 'Sharp · single use'],
    note: ['FX-1', 'u_note', 'Field unit', '', ''],
  };
  const serial = (k) => `SN ${String(4100 + (k.charCodeAt(0) * 37 + k.length * 911) % 5800).padStart(4, '0')}-${String(1000 + (k.charCodeAt(1 % k.length) * 53) % 8999)}`;
  function moduleHTML(u, title, body, opts = {}) {
    const U = UNITS[u] || UNITS.note;
    return `<div class="fd-mod u-${u} ${opts.cls || ''}" data-u="${u}">
      <i class="m-scw a"></i><i class="m-scw b"></i><i class="m-scw c"></i><i class="m-scw d"></i><i class="m-grip"></i>
      <div class="m-plate"><b>${esc(U[0])}</b><span>${esc(L(U[1], U[2]))}</span><span class="m-led ${opts.led || ''}"></span></div>
      <div class="m-scr"><div class="m-cap"><span class="t">${esc(title)}</span><span class="r">${opts.right || ''}</span></div>${body}<i class="m-glass"></i></div>
      <div class="m-foot">${U[3] ? `<span class="m-stk"><b>!</b>${esc(L(U[3], U[4]))}</span>` : ''}<span class="m-sn">${serial(u)}</span></div>
    </div>`;
  }
  // mount one or more devices in the rack beside the tool belt
  function rack(mods, cls = '') {
    ui.rack.className = `fd-rack nza-int ${cls}`;
    ui.rack.innerHTML = `<i class="fd-rail"><i></i><i></i></i>${mods.join('')}`;
    ui.rack.style.display = '';
    ui.rack.classList.remove('in'); void ui.rack.offsetWidth; ui.rack.classList.add('in');
    ui.dev = ui.rack;
    return ui.rack;
  }
  function devFrame(title, body, opts = {}) { return rack([moduleHTML(opts.unit || 'note', title, body, opts)], opts.rackCls || ''); }

  function build() {
    const host = ui.host;
    if (ui.pp) { ui.pp.destroy(); ui.pp = null; }
    if (ui.ov) { ui.ov.remove(); ui.ov = null; }
    if (ui.ghost) { ui.ghost.remove(); ui.ghost = null; }
    clearMarks();
    host.innerHTML = '';
    ui.rack = NZA.el('div', 'fd-rack nza-int');
    host.appendChild(ui.rack);
    ui.dev = ui.rack;
    const layer = document.getElementById('nza-layer-anchors');
    ui.ov = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    ui.ov.setAttribute('class', 'fd-ov');
    layer.appendChild(ui.ov);
    ui.ghost = NZA.el('div', 'fd-ghost');
    ui.ghost.style.display = 'none';
    layer.appendChild(ui.ghost);
    ui.pp = NZA.ui.ProcPanel(host, {
      step: 1, total: S.total, title: '', text: '', stats: [], tools: [], steps: stepNames(),
      hints: hintsCam(), onAbort: () => abort(), onTool: k => tool(k),
    });
    const rawSet = ui.pp.set;
    ui.pp.set = n => { if (n && 'text' in n) lastText = n.text; if (n && 'stats' in n) lastStats = ''; return rawSet(n); };
    ui.view = NZA.el('div', 'fd-view nza-hud solid nza-int');
    ui.pp.slot.prepend(ui.view);
    renderView();
  }

  /* camera VIEW selector (lives in the step column): one key cycles the views, or click one */
  const viewKey = () => (typeof S.keys.focus === 'string' && S.keys.focus !== '' ? S.keys.focus : 'Tab');
  const standOk = () => !!(S.proc === 'resus' || S.proc === 'reassess' || (S.rs && S.rs.stand));
  const viewItems = () => (S.mode === 'iv'
    ? [['patient', L('f_patient', 'Body'), 'person'], ['site', L('f_arm', 'Arm'), 'target']]
    : [['patient', L('f_patient', 'Body'), 'person'], ['site', L('f_site', 'Access'), 'target'], ['stand', L('f_stand', 'Drip'), 'iv'], ['kit', L('f_kit', 'Kit'), 'kit']]);
  function renderView() {
    if (!ui.view) return;
    const ok = standOk();
    ui.view.innerHTML = `<span class="vl">${icon('camera')}<span>${esc(L('view', 'View'))}</span><kbd class="vk">${esc(keyName(viewKey()))}</kbd></span><span class="vs">${viewItems().map(([id, label, ic]) => `<button data-f="${id}" class="${S.focus === id ? 'on' : ''} ${id === 'stand' && !ok ? 'off' : ''}"><span class="vi">${icon(ic)}</span><span class="vt"><b>${esc(label)}</b></span></button>`).join('')}</span>`;
    ui.view.querySelectorAll('button').forEach(b => b.addEventListener('click', () => focusCam(b.dataset.f)));
  }
  const renderFocus = renderView;
  function focusCam(what) {
    if (what === 'stand' && !standOk()) return;
    S.focus = what; renderView(); post('focus', { what }); NZA.audio.click(700);
  }
  function cycleView(dir) {
    const ids = viewItems().map(v => v[0]).filter(id => id !== 'stand' || standOk());
    const i = ids.indexOf(S.focus);
    focusCam(ids[((i < 0 ? 0 : i + dir) % ids.length + ids.length) % ids.length]);
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
          meter: { value: a / 45, zone: [band[0] / 45, band[1] / 45], tone: off ? 'amber' : '' }, caption: L('cap_angle', 'Enter at {a}–{b}°', { a: band[0], b: band[1] }), captionTone: off ? 'amber' : '' },
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
        caption: L('cap_target', 'Aim {a}–{b}', { a: lo, b: hi }), captionTone: tone === 'teal' ? 'teal' : '' },
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
    return [L('s_binder', 'Bind the pelvis'), L('s_site', 'Pick the IO site'), L('s_drill', 'Drive the needle'), L('s_aspirate', 'Draw back'), L('s_flush', 'Flush the line'), L('s_resus', 'Hold the pressure'), L('s_recheck', 'Recheck')];
  }
  const hintsCam = () => [{ keys: [L('k_rclick', 'Right mouse')], label: L('h_orbit', 'turn') }, { keys: ['Shift', L('k_rclick', 'Right mouse')], label: L('h_pan', 'slide') }, { keys: [L('k_scroll', 'Wheel')], label: L('h_zoom', 'zoom') }];

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
    S.proc = proc; S.status = status; S.data = data || {}; S.reason = reason; S.waiting = false;
    if (S.data.band && proc === 'resus') S.band = S.data.band;   // the binder's band is its strap tension, not the MAP target
    if (S.data.injury) S.injury = S.data.injury;
    if (S.data.bleed !== undefined) S.bleed = S.data.bleed;
    S.n = S.mode === 'iv' ? 1 : (STEP_N[proc] || 1);
    if (ui.host) ui.host.classList.remove('grab', 'aim');
    S.metric = null;
    const fl = ui.pp.el.querySelector('.pp-flash'); if (fl) fl.className = 'pp-flash';
    ui.pp.set({ step: S.n, total: S.total, tag: '', titleTone: '', hints: hintsCam(), steps: stepNames() });
    stats();
    renderView();
    const h = H_[proc];
    if (!h) return;
    if (status === 'run') h.enter();
    else h.blocked ? h.blocked(status, reason) : blockedPanel(proc, status, reason);
  }

  const PROC_EN = { binder: 'Bind the pelvis', io: 'IO access', resus: 'Hold the pressure', reassess: 'Recheck', iv: 'IV cannulation' };
  const PROC_TITLE = { binder: 's_binder', io: 's_site', resus: 's_resus', reassess: 's_recheck', iv: 't_iv' };
  const PROC_UNIT = { binder: 'bt', io: 'io', resus: 'pi', reassess: 'note', iv: 'vf' };
  function blockedPanel(proc, status, reason) {
    const title = L(PROC_TITLE[proc] || `t_${proc}`, PROC_EN[proc] || proc);
    const noteBody = (txt, tone) => `<div class="m-note ${tone}"><span class="ni">${icon(tone === 'red' ? 'alert' : tone === 'teal' ? 'check' : 'clock')}</span><span>${NZA.rich(txt)}</span></div>`;
    if (status === 'easy') {
      const txt = reason || L('easy_text', 'Easy mode — hold still while you work.');
      ui.pp.set({ title, titleTone: '', text: txt, tools: [] });
      devFrame(title, noteBody(txt, ''), { unit: PROC_UNIT[proc] });
      return;
    }
    const text = status === 'skip' ? (reason || L('skip_text', 'Not needed — moving on.')) : (reason || L('blocked_text', 'This step can not start right now.'));
    ui.pp.set({ title, titleTone: status === 'skip' ? 'ok' : 'bad', text, tools: [{ key: 'N', label: L('tool_continue', 'Continue'), icon: 'arrow-r', state: 'active' }] });
    devFrame(title, noteBody(text, status === 'skip' ? 'teal' : 'red'), { unit: PROC_UNIT[proc], led: status === 'skip' ? '' : 'red' });
  }

  function sendResult(proc, result) {
    if (S.waiting) return;
    S.waiting = true;
    S.lastResult = { proc, result };
    ui.pp.flash('ok', L('checking', 'Logged — checking…'), 0);
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
    if (S.preview) NZA.toast({ title: L('aborted', 'Stopped'), message: L('aborted_text', 'Field resuscitation cancelled.'), type: 'error' });
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
          title: L('s_binder', 'Bind the pelvis'), tag: why,
          text: L('binder_drop', 'Click the **binder** in the kit (or press 1), then click the **hip marker** to lay it under the hips.'),
          tools: [{ key: '1', label: L('tool_binder', 'Pelvic binder'), icon: 'cuff', state: 'active', sub: d.count !== undefined ? `×${d.count}` : '' },
            { key: 'N', label: d.indicated ? L('tool_skip', 'Skip') : L('tool_skip_ok', 'Skip — not needed'), icon: 'arrow-r' }],
        });
        mark('kit', { label: L('m_binder', 'Binder'), tone: 'teal', dot: 'fd-dia white' });
        mark('pelvis', { label: L('m_drop', 'Under the hips'), dot: 'fd-dia fd-target' });
      } else if (b.phase === 'strap') {
        ui.pp.set({
          title: L('s_binder', 'Bind the pelvis'), tag: why,
          text: L('binder_strap', 'Grab the strap handle and draw it across the hips. Release when the ring turns teal. Tension {t}%.', { t: Math.round(b.tension) }),
          tools: [{ key: '1', label: L('tool_binder', 'Pelvic binder'), icon: 'cuff', state: 'done' }],
        });
      }
      this.dev();
    },
    dev() {
      const b = S.b;
      const [lo, hi] = b.band;
      const teeth = Array.from({ length: 18 }, (_, i) => `<i style="--i:${i}"></i>`).join('');
      devFrame(L('d_binder', 'Belt tension'), `
        <div class="m-split">
          <div class="m-dial bt"><div class="dzh">${dialSVG(0, { zone: [lo / 120, hi / 120], ticks: 12 })}</div><div class="dv"><span class="tn"></span><i>%</i></div><span class="dl">${esc(L('d_tension', 'Tension'))}</span></div>
          <div class="m-list">
            ${row('r-pl', L('d_placed', 'Placed'), b.phase === 'drop' ? '—' : icon('check'), b.phase === 'drop' ? 'dim' : 'teal')}
            ${row('r-tg', L('d_target', 'Target'), `${lo}–${hi}<small>%</small>`)}
            ${row('r-at', L('d_attempt', 'Attempt'), String(b.attempts))}
          </div>
        </div>
        <div class="m-teeth">${teeth}</div>
        <div class="m-state bst"><span class="dot"></span><span class="tx">${esc(b.phase === 'drop' ? L('d_binder_drop', 'Waiting for the binder.') : L('d_binder_band', 'Release between {lo} and {hi}%.', { lo, hi }))}</span></div>`,
      { unit: 'bt', right: `<span class="m-chip">${esc(L('d_pelvis', 'Hips'))}</span>` });
      b.odo = NZA.ui.FlipClock(q('.m-dial.bt .tn'), { value: '0' });
      this.devTick();
    },
    devTick() {
      const b = S.b;
      const t = b.tension, [lo, hi] = b.band;
      const tone = toneOf(t, lo, hi);
      const dz = q('.m-dial.bt .dzh'); if (!dz) return;
      dz.innerHTML = dialSVG(t / 120, { zone: [lo / 120, hi / 120], tone, ticks: 12 });
      if (b.odo) { b.odo.set(String(Math.round(t))); b.odo.tone(tone === 'teal' ? 'teal' : tone === 'red' ? 'red' : tone === 'amber' ? 'amber' : ''); }
      const n = Math.round(clamp(t / 120, 0, 1) * 18);
      ui.dev.querySelectorAll('.m-teeth i').forEach((e, i) => { const v = (i + 0.5) / 18 * 120; e.className = i < n ? (v > hi ? 'on red' : v >= lo ? 'on teal' : 'on') : (v >= lo && v <= hi ? 'zone' : ''); });
      const st = q('.bst');
      if (st && b.phase !== 'drop') {
        st.className = `m-state bst ${tone}`;
        st.querySelector('.tx').textContent = t > hi ? L('bs_over', 'Over-tight — ease back') : t >= lo ? L('bs_ok', 'On target — let go') : t > 0 ? L('bs_under', 'Keep drawing across') : L('d_binder_band', 'Release between {lo} and {hi}%.', { lo, hi });
      }
      metric({ label: L('st_tension', 'Tension'), value: Math.round(t), unit: '%', tone });
      if (b.phase === 'strap') setText(L('binder_strap', 'Grab the strap handle and draw it across the hips. Release when the ring turns teal. Tension {t}%.', { t: Math.round(t) }));
    },
    carryText() {
      ui.pp.set({ text: L('binder_carry_text', 'You have the **binder**. Now click the **hip marker** to lay it under the hips.') });
    },
    tool(k) {
      if (k.toUpperCase() === 'N') return skip();
      if (k === '1' && S.b.phase === 'drop') { S.b.carry = true; S.b.drag = true; S.b.sticky = true; S.b.from = null; ui.host.classList.add('grab'); this.carryText(); }
    },
    down(e) {
      const b = S.b;
      if (b.phase === 'drop') {
        // already carrying (picked with a click or the tool key): this click drops it - see up()
        if (!b.drag && overKit(e.clientX, e.clientY)) {
          b.drag = true; b.sticky = false; b.from = { x: e.clientX, y: e.clientY };
          ui.host.classList.add('grab'); NZA.audio.click(500);
          this.move(e);
        }
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
        ghost(true, `<span class="ic">${icon('cuff')}</span><span class="gt"><b>${esc(L('tool_binder', 'Pelvic binder'))}</b><small>${esc(near ? L('binder_release', 'Let go to lay it') : L('binder_carry', 'Carry it over the hips'))}</small></span>`, e.clientX, e.clientY, near);
      }
      if (b.phase === 'strap' && b.drag) {
        const A = apx('strapA'), B = apx('strapB');
        if (!A || !B) return;
        const vx = B.x - A.x, vy = B.y - A.y, len2 = vx * vx + vy * vy || 1;
        const t = ((e.clientX - A.x) * vx + (e.clientY - A.y) * vy) / len2;
        const prev = b.tension;
        b.tension = clamp(t * 100, 0, 120);
        b.tab = { x: A.x + vx * clamp(t, 0, 1.2), y: A.y + vy * clamp(t, 0, 1.2) };
        if (Math.floor(prev / (120 / 18)) !== Math.floor(b.tension / (120 / 18))) NZA.audio.tick();
        ui.pp.set({ text: L('binder_strap', 'Grab the strap handle and draw it across the hips. Release when the ring turns teal. Tension {t}%.', { t: Math.round(b.tension) }) });
        this.devTick();
      }
    },
    up(e) {
      const b = S.b;
      if (b.phase === 'drop' && b.drag) {
        const p = apx('pelvis');
        const onHips = p && Math.hypot(e.clientX - p.x, e.clientY - p.y) < 80 * pxScale();
        // a click (no drag) on the case picks the binder up: keep carrying until the next click
        if (!onHips && b.from && Math.hypot(e.clientX - b.from.x, e.clientY - b.from.y) < 14 * pxScale()) {
          b.sticky = true; b.from = null; this.carryText();
          return;
        }
        if (!onHips && b.sticky && overKit(e.clientX, e.clientY)) return;   // clicked the case again: still holding it
        b.drag = false; b.sticky = false; b.from = null; ui.host.classList.remove('grab'); ghost(false);
        if (onHips) {
          b.phase = 'wait';
          const go = r => {
            if (!S.b || S.proc !== 'binder') return;
            if (r && r.ok === false) { b.phase = 'drop'; ui.pp.flash('bad', (r && r.msg) || L('binder_drop_fail', 'The binder would not go under.')); return; }
            b.phase = 'strap'; clearMarks(); NZA.audio.success();
            ui.pp.flash('ok', L('binder_placed', 'Binder is under the hips. Now tension the strap.'));
            this.ui();
          };
          if (S.preview) go({ ok: true }); else post('binderDrop', {}).then(go);
        } else {
          ui.pp.flash('warn', L('binder_miss', 'Missed — drop it on the hip marker.'));
          this.ui();
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
          ui.pp.flash(t > hi ? 'bad' : 'warn', t > hi ? L('binder_tight', 'Over-tight at {t}% — slacken and try again.', { t: Math.round(t) }) : L('binder_loose', 'Too slack at {t}% — draw it further across.', { t: Math.round(t) }));
          b.tension = 0; b.tab = null; this.devTick();
          setRow('.r-at', String(b.attempts), b.attempts > 1 ? 'amber' : '');
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
        const k = pxScale();
        const P = f => ({ x: A.x + (B.x - A.x) * f, y: A.y + (B.y - A.y) * f });
        const len = Math.hypot(B.x - A.x, B.y - A.y) || 1;
        const ux = (B.x - A.x) / len, uy = (B.y - A.y) / len, nx = -uy, ny = ux;
        const z1 = P(lo / 100), z2 = P(hi / 100), end = P(1.2);
        const w = 22 * k;
        const tone = toneOf(b.tension, lo, hi);
        const col = tone === 'red' ? '#ff6b70' : tone === 'teal' ? '#0fd4c4' : tone === 'amber' ? '#f3c35a' : '#9aa5ab';
        // chevrons along the path (direction of pull)
        let chev = '';
        for (let d = 46 * k; d < len * 1.2 - 20 * k; d += 34 * k) {
          const c = { x: A.x + ux * d, y: A.y + uy * d }, s = 6 * k;
          chev += `<path d="M${c.x - ux * s + nx * s} ${c.y - uy * s + ny * s}L${c.x} ${c.y}L${c.x - ux * s - nx * s} ${c.y - uy * s - ny * s}" />`;
        }
        const bracket = (p, dir) => { const s = (w / 2 + 9 * k), t = 7 * k * dir; return `<path d="M${p.x + nx * s + ux * t} ${p.y + ny * s + uy * t}L${p.x + nx * s} ${p.y + ny * s}L${p.x - nx * s} ${p.y - ny * s}L${p.x - nx * s + ux * t} ${p.y - ny * s + uy * t}"/>`; };
        const R = 21 * k, C = 2 * Math.PI * R, fr = clamp(b.tension / 120, 0, 1);
        const lx = tab.x + nx * (R + 16 * k), ly = tab.y + ny * (R + 16 * k);
        const pulse = ((now() / 1400) % 1);
        const chipTxt = b.drag ? `${Math.round(b.tension)}%` : L('m_pull', 'Grip');
        const cw = (chipTxt.length * 7.4 + 20) * k;
        ov(`<line x1="${A.x}" y1="${A.y}" x2="${end.x}" y2="${end.y}" stroke="rgba(10,12,14,.55)" stroke-width="${w + 6 * k}" stroke-linecap="round"/>
          <line x1="${A.x}" y1="${A.y}" x2="${end.x}" y2="${end.y}" stroke="rgba(255,255,255,.12)" stroke-width="${w}" stroke-linecap="round"/>
          <line x1="${z1.x}" y1="${z1.y}" x2="${z2.x}" y2="${z2.y}" stroke="rgba(15,212,196,.22)" stroke-width="${w}" />
          <g fill="none" stroke="rgba(255,255,255,.4)" stroke-width="${1.6 * k}" stroke-linecap="round" stroke-linejoin="round">${chev}</g>
          <g fill="none" stroke="#0fd4c4" stroke-width="${2.4 * k}" stroke-linecap="round" stroke-linejoin="round">${bracket(z1, 1)}${bracket(z2, -1)}</g>
          <line x1="${A.x}" y1="${A.y}" x2="${tab.x}" y2="${tab.y}" stroke="#1d2a33" stroke-width="${w - 4 * k}" stroke-linecap="round"/>
          <line x1="${A.x}" y1="${A.y}" x2="${tab.x}" y2="${tab.y}" stroke="${col}" stroke-width="${2 * k}" stroke-dasharray="${8 * k} ${6 * k}" opacity=".9"/>
          ${b.phase === 'strap' ? `<g>
            <circle cx="${tab.x}" cy="${tab.y}" r="${R + (4 + pulse * 14) * k}" fill="none" stroke="${col}" stroke-width="${2 * k}" opacity="${(0.55 * (1 - pulse)).toFixed(2)}"/>
            <circle cx="${tab.x}" cy="${tab.y}" r="${R}" fill="rgba(12,13,16,.92)" stroke="rgba(255,255,255,.14)" stroke-width="${4 * k}"/>
            <circle cx="${tab.x}" cy="${tab.y}" r="${R}" fill="none" stroke="${col}" stroke-width="${4 * k}" stroke-linecap="round" stroke-dasharray="${(C * fr).toFixed(1)} ${C.toFixed(1)}" transform="rotate(-90 ${tab.x} ${tab.y})" style="filter:drop-shadow(0 0 4px ${col})"/>
            <g stroke="#fff" stroke-width="${2 * k}" stroke-linecap="round" opacity=".9"><line x1="${tab.x - 7 * k}" y1="${tab.y - 5 * k}" x2="${tab.x + 7 * k}" y2="${tab.y - 5 * k}"/><line x1="${tab.x - 7 * k}" y1="${tab.y}" x2="${tab.x + 7 * k}" y2="${tab.y}"/><line x1="${tab.x - 7 * k}" y1="${tab.y + 5 * k}" x2="${tab.x + 7 * k}" y2="${tab.y + 5 * k}"/></g>
            <rect x="${lx - cw / 2}" y="${ly - 12 * k}" width="${cw}" height="${24 * k}" rx="${7 * k}" fill="rgba(12,13,16,.92)" stroke="rgba(255,255,255,.1)"/>
            <text x="${lx}" y="${ly + 4.2 * k}" text-anchor="middle" font-size="${12 * k}" font-weight="700" fill="${b.drag ? col : '#fff'}" style="font-family:var(--font)">${esc(chipTxt)}</text>
          </g>` : ''}`);
      } else ov('');
    },
    leave() { ghost(false); },
  };

  /* ═══════════════════════════ STEPS 2-5 · INTRAOSSEOUS ═══════════════════════════ */
  const IO_SITES = ['r_tibia', 'l_tibia', 'r_humerus', 'l_humerus'];
  const SITE_EN = { r_tibia: 'Right tibia', l_tibia: 'Left tibia', r_humerus: 'Right humeral head', l_humerus: 'Left humeral head' };
  const LAYER_EN = { air: 'Air', soft: 'Tissue', cortex: 'Bone wall', marrow: 'Marrow', far: 'Back wall', through: 'Out the back' };
  const WHY_EN = { fracture: 'Fracture', tourniquet: 'Tourniquet', burn: 'Burn', wound: 'Wound', invalid: 'Not possible' };
  const siteName = id => L(`site_${id}`, SITE_EN[id] || id);
  const LAYER_ORDER = ['soft', 'cortex', 'marrow', 'far'];
  // body map positions (front view, patient's right on the viewer's left)
  const SITE_XY = { r_humerus: [27, 38], l_humerus: [73, 38], r_tibia: [40, 132], l_tibia: [60, 132] };
  function bodySVG(sites) {
    const dia = (id, i) => {
      const st = sites[id] || { ok: true }, [x, y] = SITE_XY[id];
      return `<g class="st ${st.ok === false ? 'bad' : 'ok'}" data-s="${id}" transform="translate(${x} ${y})"><rect x="-5" y="-5" width="10" height="10" rx="1.5" transform="rotate(45)"/><text x="${x < 50 ? -10 : 10}" y="3" text-anchor="${x < 50 ? 'end' : 'start'}">${i + 1}</text></g>`;
    };
    return `<svg viewBox="0 0 100 168" class="m-body">
      <defs><linearGradient id="fdholo" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="rgba(15,212,196,.22)"/><stop offset="1" stop-color="rgba(15,212,196,.04)"/></linearGradient></defs>
      <g class="sil"><circle cx="50" cy="13" r="9"/>
        <path d="M38 26h24l6 6 4 34-6 2-4-26v30l2 30h-10l-2-26-2 26h-10l2-30V42l-4 26-6-2 4-34z"/>
        <path d="M41 92h8v68h-9zM51 92h8l1 68h-9z"/></g>
      <g class="scan"><rect x="0" y="0" width="100" height="2"/></g>
      ${IO_SITES.map(dia).join('')}
    </svg>`;
  }
  H_.io = {
    enter() {
      S.io = { phase: 'site', site: null, needles: 1, depth: 0, lift: 1, drilling: false, drift: { x: 0, y: 0 }, aim: { x: 0, y: 0 }, angle: 0, ax: 0, ay: 0,
        angleSum: 0, angleN: 0, maxAngle: 0, torque: [], fails: 0, aspirated: false, ext: false, lido: { ml: 0, rate: 0, peak: 0 }, flush: { ml: 0, rate: 0, peak: 0 }, layer: 'air', snd: 0, lostRes: false };
      this.site();
    },
    /* ── step 2 · site ── */
    site() {
      const io = S.io, sites = S.data.sites || {};
      io.phase = 'site'; S.n = 2;
      metric({ label: L('st_needles', 'Needles'), value: `${io.needles}/${S.data.attempts || 3}` });
      ui.pp.set({
        step: 2, title: L('s_site', 'Pick the IO site'), tag: L('tag_io', 'Intraosseous access'),
        text: L('site_text', 'Press a site key or click its marker: the **tibia** just below the knee, or the **humeral head** at the shoulder.'),
        tools: IO_SITES.map((id, i) => ({ key: String(i + 1), label: siteName(id), icon: 'bone', state: sites[id] && sites[id].ok === false ? 'locked' : '' })),
      });
      IO_SITES.forEach(id => {
        const st = sites[id] || { ok: true };
        mark(id, { label: st.ok === false ? `${siteName(id)} · ${L(`why_site_${st.why}`, WHY_EN[st.why] || st.why || '')}` : siteName(id), dot: st.ok === false ? 'fd-dia red' : 'fd-dia', tone: st.ok === false ? 'red' : '' });
      });
      const okN = IO_SITES.filter(id => !(sites[id] && sites[id].ok === false)).length;
      devFrame(L('d_site', 'Site check'), `
        <div class="m-split top">
          ${bodySVG(sites)}
          <div class="m-sites">${IO_SITES.map((id, i) => {
            const st = sites[id] || { ok: true };
            return `<button class="d-site ${st.ok === false ? 'bad' : ''}" data-s="${id}"><kbd>${i + 1}</kbd><span class="sn">${esc(siteName(id))}<small>${esc(st.ok === false ? L(`why_site_${st.why}`, WHY_EN[st.why] || st.why || '') : L('site_ok', 'Clear'))}</small></span><span class="sd">${icon(st.ok === false ? 'x' : 'check')}</span></button>`;
          }).join('')}</div>
        </div>
        <div class="m-note amber"><span class="ni">${icon('alert')}</span><span>${NZA.rich(L('site_note', 'No drilling into a **broken** bone or below a **tourniquet**.'))}</span></div>`,
      { unit: 'io', right: `<span class="m-chip">${okN}/4 ${esc(L('site_clear', 'clear'))}</span>` });
      ui.dev.querySelectorAll('.d-site').forEach(b => {
        b.addEventListener('click', () => this.pick(b.dataset.s));
        b.addEventListener('mouseenter', () => { const g = ui.dev.querySelector(`.m-body .st[data-s="${b.dataset.s}"]`); if (g) g.classList.add('hl'); });
        b.addEventListener('mouseleave', () => ui.dev.querySelectorAll('.m-body .st').forEach(g => g.classList.remove('hl')));
      });
      ui.dev.querySelectorAll('.m-body .st').forEach(g => g.addEventListener('click', () => this.pick(g.dataset.s)));
    },
    pick(id) {
      const st = (S.data.sites || {})[id];
      if (!id || (st && st.ok === false)) { ui.pp.flash('bad', st ? L(`why_site_${st.why}_long`, L(`why_site_${st.why}`, 'Contraindicated')) : ''); NZA.audio.fail(); return; }
      S.io.site = id;
      clearMarks();
      NZA.audio.click(820);
      post('phase', { proc: 'io', phase: 'drill', site: id });
      S.focus = 'site'; renderView();
      this.drillUi();
    },
    layers() {
      const kind = /humerus/.test(S.io.site || '') ? 'humerus' : 'tibia';
      return (S.data.layers || {})[kind] || { soft: 7, cortex: 3, marrow: 12, far: 3 };
    },
    /* ── step 3 · drive the needle ── */
    drillUi() {
      const io = S.io, ly = this.layers();
      io.phase = 'drill'; S.n = 3; io.depth = 0; io.drilling = false; io.lostRes = false; io.layer = 'air'; io.torque = [];
      const k = S.keys.drill || 'Space';
      const maxA = S.data.maxAngle || 15;
      ui.pp.set({
        step: 3, title: L('s_drill', 'Drive the needle'), tag: siteName(io.site),
        text: L('drill_text', 'Center the bubble inside the ring (under {max}°), press {Click} to seat the needle on the skin, then hold {{key}} to drive it. Release the moment it gives way.', { max: maxA, key: keyName(k) }),
        tools: [{ key: '1', label: L('tool_driver', 'IO driver'), icon: 'drill', state: 'active', sub: `${L('needle', 'Needle')} ${io.needles}/${S.data.attempts || 3}` }],
        hints: [{ keys: [L('k_hold', 'Hold'), keyName(k)], label: L('h_drill', 'drive') }, { keys: [L('k_click', 'Click')], label: L('h_pressure', 'seat') }].concat(hintsCam()),
      });
      mark('site', { anchor: io.site, label: '', dot: 'fd-dia white' });
      ui.host.classList.add('aim');
      io.total = 4 + ly.soft + ly.cortex + ly.marrow + ly.far + 5;
      const tolR = (maxA / 30) * 40;
      let rings = '';
      [10, 20, 30].forEach(a => { rings += `<circle class="rg" cx="52" cy="52" r="${(a / 30) * 40}"/>`; });
      devFrame(L('d_drill', 'Drive'), `
        <div class="m-split">
          <div class="m-level"><svg viewBox="0 0 104 104">
            <circle class="bz" cx="52" cy="52" r="50"/><circle class="gl" cx="52" cy="52" r="44"/>${rings}
            <circle class="tol" cx="52" cy="52" r="${tolR.toFixed(1)}"/>
            <path class="xh" d="M52 10v84M10 52h84"/>
            <circle class="bub" cx="52" cy="52" r="7.5"/><circle class="bhl" cx="50" cy="50" r="2.4"/>
          </svg><span class="dl">${esc(L('d_level', 'Level'))}</span></div>
          <div class="m-list">
            ${row('r-oa', L('d_offaxis', 'Off level'), '0<small>°</small>', 'teal')}
            ${row('r-dp', L('d_depth', 'Depth'), '0.0<small>mm</small>')}
            ${row('r-ti', L('d_tip', 'Tip layer'), esc(L('ly_air', LAYER_EN.air)))}
            ${row('r-ct', L('d_contact', 'Contact'), esc(L('contact_off', 'Lifted')), 'dim')}
          </div>
        </div>
        <canvas class="m-xs"></canvas>
        <div class="m-trace"><span>${esc(L('d_resist', 'Torque'))}</span><canvas class="d-spark"></canvas></div>`,
      { unit: 'io', right: `<span class="m-chip">${esc(L('needle', 'Needle'))} ${io.needles}/${S.data.attempts || 3}</span>` });
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
        ui.pp.set({ text: L('drill_out', 'Out of needles for this attempt.'), tools: [{ key: 'N', label: L('tool_giveup', 'Stop IO'), icon: 'x' }] });
        return;
      }
      ui.pp.set({ text: L('drill_retry', 'Back the needle out and load a fresh one.'), tools: [{ key: 'R', label: L('tool_newneedle', 'Fresh needle'), icon: 'needle', state: 'active' }, { key: 'N', label: L('tool_giveup', 'Stop IO'), icon: 'x' }] });
    },
    newNeedle() {
      const io = S.io;
      if (!io.failed) return;
      const go = r => {
        if (!r || r.ok === false) { ui.pp.flash('bad', (r && r.msg) || L('no_needle', 'No IO needle set left.')); return; }
        io.needles = r.needles || io.needles + 1; io.failed = null;
        ui.pp.flash('ok', L('needle_new', 'Fresh needle loaded.'));
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
      ui.pp.flash(intoFar > 0 ? 'warn' : 'ok', intoFar > 0 ? L('drill_touch_far', 'Seated — the tip just touches the back wall.') : L('drill_ok', 'Seated in the marrow.'));
      setTimeout(() => this.confirmUi(), 900);
    },
    /* ── step 4 · draw back ── */
    confirmUi() {
      const io = S.io;
      io.phase = 'confirm'; S.n = 4;
      metric({ label: L('st_depth', 'Depth'), value: fmt1(io.depth), unit: 'mm', tone: 'teal' });
      ui.host.classList.remove('aim');
      post('phase', { proc: 'io', phase: 'confirm', site: io.site });
      ui.pp.set({
        step: 4, title: L('s_aspirate', 'Draw back'), tag: siteName(io.site),
        text: L('confirm_text', 'Remove the stylet, fit the syringe and **hold the plunger** (or press 1) to draw back. Dark blood in the barrel means you are in.'),
        tools: [{ key: '1', label: L('tool_syringe', 'Syringe 10 ml'), icon: 'syringe', state: 'active' }],
        hints: hintsCam(),
      });
      mark('site', { anchor: io.site, label: L('m_io', 'IO needle'), dot: 'fd-dia white' });
      devFrame(L('d_confirm', 'Draw back'), `<div class="syrh"></div><div class="m-note cn"><span class="ni">${icon('info')}</span><span>${esc(L('confirm_note', 'About 1 ml is enough.'))}</span></div>`, { unit: 'sx', right: `<span class="m-chip">10 ml</span>` });
      io.syr = Syringe(ui.dev.querySelector('.syrh'), {
        cap: 10, vol: 0, mode: 'pull', fluid: 'clear', label: L('syr_barrel', 'In the barrel'), flashAt: S.data.aspirateMl || 1,
        onFlash: () => {
          io.aspirated = true; NZA.audio.success();
          ui.pp.flash('ok', L('confirm_ok', 'Dark return in the barrel — you are in the marrow.'));
          setRow('.r-ret', `${icon('drop')}${esc(L('ret_marrow', 'Marrow'))}`, 'red');
          const n = q('.cn'); if (n) { n.className = 'm-note teal cn'; n.innerHTML = `<span class="ni">${icon('check')}</span><span>${esc(L('confirm_ok', 'Dark return in the barrel — you are in the marrow.'))}</span>`; }
          setTimeout(() => this.flushUi(), 1300);
        },
      });
      io.syr.ret(`<div class="m-list">${row('r-ret', L('d_return', 'Return'), esc(L('ret_none', 'None yet')), 'dim')}${row('r-dep', L('d_depth', 'Depth'), `${fmt1(io.depth)}<small>mm</small>`)}${row('r-st', L('st_site', 'Site'), esc(siteName(io.site)))}</div>`);
    },
    /* ── step 5 · flush ── */
    flushUi() {
      const io = S.io;
      if (io.syr) { io.syr.destroy(); io.syr = null; }
      io.phase = 'flush'; S.n = 5; io.tool = null;
      ui.pp.set({ step: 5, title: L('s_flush', 'Flush the line'), tag: siteName(io.site), hints: hintsCam() });
      this.flushTools();
      devFrame(L('d_flush', 'Flush'), `<div class="syrh"></div><div class="m-note fn"></div>`, { unit: 'sx', right: '<span class="m-chip fc"></span>' });
      this.flushText();
    },
    flushTools() {
      const io = S.io, d = S.data;
      const hasLido = d.lidocaine !== false;
      ui.pp.set({
        tools: [
          { key: '1', label: L('tool_ext', 'Extension line'), icon: 'tube', state: io.ext ? 'done' : io.tool === 'ext' ? 'active' : '' },
          { key: '2', label: L('tool_lido', 'Lidocaine 2%'), icon: 'syringe', state: io.lido.ml >= (d.lidoMl || 2) - 0.05 ? 'done' : !io.ext || !hasLido ? 'locked' : io.tool === 'lido' ? 'active' : '', sub: hasLido ? `${d.lidoMl || 2} ml` : '×0' },
          { key: '3', label: L('tool_flush', 'Flush syringe'), icon: 'drop', state: io.flush.ml >= (d.flushMl || 10) - 0.1 ? 'done' : !io.ext ? 'locked' : io.tool === 'flush' ? 'active' : '', sub: `${d.flushMl || 10} ml` },
        ],
      });
    },
    flushText() {
      const io = S.io, d = S.data;
      let text;
      if (!io.ext) text = L('flush_ext', 'Prime the **extension line** and lock it onto the hub (1).');
      else if (io.tool === 'lido') text = L('flush_lido', 'Ease the **lidocaine** in — slow and steady. {a} of {b} ml.', { a: fmt1(io.lido.ml), b: d.lidoMl || 2 });
      else if (io.tool === 'flush') text = L('flush_flush', 'Push the saline through. {a} of {b} ml.', { a: fmt1(io.flush.ml), b: d.flushMl || 10 });
      else if (d.responsive !== false && d.lidocaine !== false && io.lido.ml < (d.lidoMl || 2) - 0.05) text = L('flush_pick_lido', 'Patient is awake — numb the marrow with **lidocaine 2%** first (2).');
      else text = L('flush_pick', 'Push **saline** through the line (3).');
      ui.pp.set({ text });
      const n = q('.fn');
      if (n) n.innerHTML = `<span class="ni">${icon(io.tool ? 'arrow-down' : 'syringe')}</span><span>${NZA.rich(io.tool ? L('flush_drag', 'Hold the plunger to push at a steady speed, or drag it down. Keep the needle in the teal arc.') : L('flush_pick_tool', 'Choose a syringe.'))}</span>`;
      const fc = q('.fc');
      if (fc) fc.innerHTML = `${io.ext ? icon('check') : icon('x')}${esc(L('fc_line', 'Line'))}`;
      if (fc) fc.className = `m-chip fc ${io.ext ? 'teal' : ''}`;
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
        label: kind === 'lido' ? L('tool_lido', 'Lidocaine 2%') : L('tool_flush', 'Flush syringe'),
        onChange: (vol, rate) => {
          rec.ml = clamp(cap - vol, 0, cap);
          if (rate > 0.01) { rec.samples = (rec.samples || 0) + 1; rec.rateSum = (rec.rateSum || 0) + rate; rec.peak = Math.max(rec.peak, rate); }
          if (rate > band[1] * 1.25 && !rec.warned) { rec.warned = true; ui.pp.flash('bad', kind === 'lido' ? L('lido_fast', 'Too quick — that stings.') : L('flush_fast', 'Too quick — the patient flinches.')); }
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
      if (io.phase === 'confirm' && k === '1' && io.syr && !io.aspirated) return io.syr.auto(true);
      if (io.phase === 'flush') {
        if (k === '1' && !io.ext) { io.ext = true; NZA.audio.click(900); ui.pp.flash('ok', L('ext_ok', 'Extension line primed and locked.')); this.flushTools(); this.flushText(); return; }
        if (k === '2' && io.ext && S.data.lidocaine !== false && io.lido.ml < (S.data.lidoMl || 2) - 0.05) return this.useSyringe('lido');
        if (k === '3' && io.ext && io.flush.ml < (S.data.flushMl || 10) - 0.1) {
          if (S.data.responsive !== false && S.data.lidocaine !== false && io.lido.ml < 1 && !io.warnedLido) { io.warnedLido = true; ui.pp.flash('warn', L('flush_nolido', 'Patient is awake: saline without lidocaine will hurt. Press 3 again to go ahead.')); return; }
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
        if (io.lift > 0.08) { ui.pp.flash('warn', L('drill_press', 'Press {Click} first to seat the needle on the skin.')); return true; }
        if (io.angle > (S.data.maxAngle || 15) && io.depth < 0.1) { ui.pp.flash('warn', L('drill_align', 'Center the bubble first — off by {a}°.', { a: Math.round(io.angle) })); return true; }
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
        const k = pxScale();
        ov(p ? `<circle cx="${p.x}" cy="${p.y}" r="${12 * k}" fill="none" stroke="#0fd4c4" stroke-width="2" stroke-dasharray="${4 * k} ${3 * k}" stroke-dashoffset="${((now() / 60) % 70).toFixed(1)}"/><circle cx="${p.x}" cy="${p.y}" r="${(12 + ((now() / 1600) % 1) * 16) * k}" fill="none" stroke="#0fd4c4" stroke-width="1.5" opacity="${(0.6 * (1 - ((now() / 1600) % 1))).toFixed(2)}"/>` : '');
      }
    },
    // bone cross-section: skin on top, tissue, cortical ring around the marrow canal, the needle coming in at the off-level angle
    drawXs() {
      const io = S.io, cv = q('.m-xs');
      if (!cv) return;
      const { w, h } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      const s = w / 288;
      const ly = this.layers();
      const tot = ly.soft + ly.cortex + ly.marrow + ly.far;
      const k = (h / s - 22) / (tot + 5);            // px per mm (in 288-wide units)
      c.save(); c.scale(s, s);
      const Wd = 288, Hd = h / s;
      c.clearRect(0, 0, Wd, Hd);
      const skinY = 12, cx = Wd * 0.42;
      const R = ((ly.cortex * 2 + ly.marrow) / 2) * k;
      const by = skinY + ly.soft * k + R;
      // air
      c.fillStyle = '#05080a'; c.fillRect(0, 0, Wd, Hd);
      // tissue body (soft tissue around the bone)
      const tg = c.createLinearGradient(0, skinY, 0, Hd);
      tg.addColorStop(0, '#d39a7c'); tg.addColorStop(0.06, '#b8735c'); tg.addColorStop(0.5, '#8e4a3c'); tg.addColorStop(1, '#5a2a24');
      c.fillStyle = tg; c.beginPath(); c.moveTo(0, skinY + 6); c.quadraticCurveTo(cx, skinY - 6, Wd, skinY + 6); c.lineTo(Wd, Hd); c.lineTo(0, Hd); c.closePath(); c.fill();
      // skin line + fibres
      c.strokeStyle = 'rgba(255,220,200,.55)'; c.lineWidth = 1.4; c.beginPath(); c.moveTo(0, skinY + 6); c.quadraticCurveTo(cx, skinY - 6, Wd, skinY + 6); c.stroke();
      c.strokeStyle = 'rgba(255,255,255,.05)'; c.lineWidth = 1;
      for (let i = 0; i < 9; i++) { c.beginPath(); c.moveTo(0, skinY + 14 + i * 9); c.bezierCurveTo(Wd * 0.3, skinY + 8 + i * 9, Wd * 0.6, skinY + 20 + i * 9, Wd, skinY + 12 + i * 9); c.stroke(); }
      // cortical bone ring (slightly oval) + trabecular marrow
      c.save(); c.translate(cx, by); c.scale(1.35, 1);
      const bg = c.createRadialGradient(-R * 0.3, -R * 0.4, R * 0.2, 0, 0, R);
      bg.addColorStop(0, '#fbf3df'); bg.addColorStop(1, '#cdbf9c');
      c.fillStyle = bg; c.beginPath(); c.arc(0, 0, R, 0, Math.PI * 2); c.fill();
      c.strokeStyle = 'rgba(80,60,30,.35)'; c.lineWidth = 0.8;
      for (let i = 1; i < 4; i++) { c.beginPath(); c.arc(0, 0, R - (ly.cortex * k * i) / 4, 0, Math.PI * 2); c.stroke(); }
      const mr = R - ly.cortex * k;
      const mg = c.createRadialGradient(0, 0, mr * 0.1, 0, 0, mr);
      mg.addColorStop(0, '#8e1e22'); mg.addColorStop(1, '#5a0f13');
      c.fillStyle = mg; c.beginPath(); c.arc(0, 0, mr, 0, Math.PI * 2); c.fill();
      c.fillStyle = 'rgba(255,190,150,.16)';
      for (let i = 0; i < 46; i++) { const a = (i * 2.399) % (Math.PI * 2), r = mr * Math.sqrt(((i * 0.618) % 1)); c.beginPath(); c.arc(Math.cos(a) * r, Math.sin(a) * r, 1.1 + (i % 3) * 0.5, 0, Math.PI * 2); c.fill(); }
      c.restore();
      // layer legend (right side, no leader lines)
      const lyY = { soft: skinY + (ly.soft * k) / 2 + 2, cortex: skinY + ly.soft * k + (ly.cortex * k) / 2 + 2, marrow: by, far: by + R - (ly.cortex * k) / 2 };
      c.font = '700 7.5px Lexend'; c.textAlign = 'right';
      LAYER_ORDER.forEach(id => {
        const on = io.layer === id;
        const txt = String(L(`ly_${id}`, LAYER_EN[id])).toUpperCase();
        const tw = c.measureText(txt).width + 10;
        c.fillStyle = on ? (id === 'marrow' ? 'rgba(15,212,196,.92)' : id === 'far' ? 'rgba(229,72,77,.92)' : 'rgba(255,255,255,.9)') : 'rgba(5,8,10,.72)';
        rrPath(c, Wd - 6 - tw, lyY[id] - 7, tw, 13, 3); c.fill();
        c.fillStyle = on ? '#031513' : 'rgba(255,255,255,.62)';
        c.fillText(txt, Wd - 11, lyY[id] + 2.6);
      });
      // needle: pivots at the skin entry by the off-level angle (signed by the aim direction)
      const sgn = io.ax >= 0 ? 1 : -1;
      const ang = clamp(io.angle, 0, 50) * sgn * Math.PI / 180;
      const entryY = skinY - 0.5;
      const tip = io.depth * k - io.lift * 9;
      const dx = Math.sin(ang), dy = Math.cos(ang);
      const tx = cx + dx * tip, ty = entryY + dy * tip;
      const col = io.angle > (S.data.maxAngle || 15) ? '#ff6b70' : '#0fd4c4';
      // ideal axis
      c.setLineDash([3, 3]); c.strokeStyle = 'rgba(15,212,196,.45)'; c.lineWidth = 1; c.beginPath(); c.moveTo(cx, 0); c.lineTo(cx, by + R); c.stroke(); c.setLineDash([]);
      // hub + shaft
      const hx = tx - dx * (tip + 18), hy = ty - dy * (tip + 18);
      const sh = c.createLinearGradient(hx - 3, 0, hx + 3, 0); sh.addColorStop(0, '#9aa4a9'); sh.addColorStop(0.5, '#f1f5f7'); sh.addColorStop(1, '#7d878c');
      c.strokeStyle = sh; c.lineWidth = 3; c.lineCap = 'round'; c.beginPath(); c.moveTo(hx, hy); c.lineTo(tx, ty); c.stroke();
      c.save(); c.translate(hx, hy); c.rotate(-ang); c.fillStyle = '#1d2226'; c.fillRect(-7, -14, 14, 12); c.fillStyle = col; c.fillRect(-7, -4, 14, 2.5); c.restore();
      c.fillStyle = '#fff'; c.shadowColor = col; c.shadowBlur = 8; c.beginPath(); c.arc(tx, ty, 2.4, 0, Math.PI * 2); c.fill(); c.shadowBlur = 0;
      c.restore();
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
      io.ax = ax; io.ay = ay;
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
        if (nl === 'marrow' && !io.lostRes) { io.lostRes = true; ui.pp.flash('ok', L('drill_loss', 'It gave way — release the trigger now!'), 1600); NZA.audio.beep(1250, 70, 0.06); }
        if (nl === 'through') return this.drillFail('through');
        io.snd -= dt;
        if (io.snd <= 0) { io.snd = 0.075; NZA.audio.tone(nl === 'cortex' || nl === 'far' ? 135 : nl === 'marrow' ? 430 : 290, 85, { vol: 0.028, type: 'sawtooth' }); }
      }
      io.layer = this.layerAt(io.depth);
      const res = { air: 0.02, soft: 0.25, cortex: 0.9, marrow: 0.12, far: 0.95, through: 0.05 }[io.layer] || 0;
      io.torque.push(io.drilling ? res + (Math.random() - 0.5) * 0.12 : io.torque.length ? io.torque[io.torque.length - 1] * 0.9 : 0);
      if (io.torque.length > 120) io.torque.shift();
      // device: bubble level
      const maxA = d.maxAngle || 15;
      const off = io.angle > maxA;
      const bub = q('.m-level .bub');
      if (bub) {
        const l = Math.hypot(ax, ay) || 1, r = Math.min(40, (Math.min(io.angle, 30) / 30) * 40);
        const bx = 52 + (ax / l) * r, by2 = 52 + (ay / l) * r;
        bub.setAttribute('cx', bx.toFixed(1)); bub.setAttribute('cy', by2.toFixed(1));
        const hl = q('.m-level .bhl'); if (hl) { hl.setAttribute('cx', (bx - 2.2).toFixed(1)); hl.setAttribute('cy', (by2 - 2.4).toFixed(1)); }
        q('.m-level').classList.toggle('off', off);
      }
      setRow('.r-oa', `${Math.round(io.angle)}<small>°</small>`, off ? 'red' : 'teal');
      setRow('.r-dp', `${fmt1(io.depth)}<small>mm</small>`, io.drilling ? 'teal' : '');
      setRow('.r-ti', esc(L(`ly_${io.layer}`, LAYER_EN[io.layer] || io.layer)), io.layer === 'marrow' ? 'teal' : io.layer === 'far' || io.layer === 'through' ? 'red' : io.layer === 'cortex' ? 'amber' : '');
      setRow('.r-ct', esc(io.lift < 0.3 ? L('contact_on', 'On skin') : L('contact_off', 'Lifted')), io.lift < 0.3 ? 'teal' : 'dim');
      metric({ label: L('st_offaxis', 'Off level'), value: Math.round(io.angle), unit: '°', tone: off ? 'red' : 'teal' });
      this.drawXs();
      const cv = q('.d-spark');
      if (cv) {
        const { w, h } = NZA.fitCanvas(cv);
        const c = cv.getContext('2d');
        c.clearRect(0, 0, w, h);
        c.fillStyle = 'rgba(229,72,77,.08)'; c.fillRect(0, 0, w, h * 0.3);
        c.strokeStyle = 'rgba(255,255,255,.06)'; c.beginPath(); c.moveTo(0, h - 1); c.lineTo(w, h - 1); c.stroke();
        c.strokeStyle = io.layer === 'marrow' ? '#0fd4c4' : '#f3c35a'; c.lineWidth = 1.6 * (w / cv.clientWidth || 1); c.beginPath();
        io.torque.forEach((v, i) => { const x = (i / 119) * w, y = h - 2 - clamp(v, 0, 1) * (h - 6); if (i) c.lineTo(x, y); else c.moveTo(x, y); });
        c.stroke();
      }
      if (!io.failed) setText((io.lift > 0.3
        ? L('drill_text_aim', 'Center the bubble inside the ring (under {max}°), then press {Click} to seat the needle. Off by {a}°.', { max: maxA, a: Math.round(io.angle) })
        : io.drilling ? (io.layer === 'cortex' ? L('drill_text_cortex', 'Through the bone wall — keep it level. Off by {a}°.', { a: Math.round(io.angle) }) : io.layer === 'marrow' ? L('drill_loss', 'It gave way — release the trigger now!') : L('drill_text_drilling', 'Driving… {d} mm.', { d: fmt1(io.depth) }))
          : L('drill_text_ready', 'Needle on the skin. Hold {{key}} to drive it in. Off by {a}°.', { key: keyName(S.keys.drill || 'Space'), a: Math.round(io.angle) })));
      // overlay: tolerance ring with bracket ticks + a reticle that closes as the needle seats
      if (site) {
        const col = off ? '#ff6b70' : '#0fd4c4';
        const rz = (maxA * ppd) * k;
        const mx = S.mouse.x, my = S.mouse.y;
        const rr = (12 + io.lift * 10) * k, C = 2 * Math.PI * rr, seat = clamp(1 - io.lift, 0, 1);
        let br = '';
        [0, 90, 180, 270].forEach(a => { const r = a * Math.PI / 180, x = site.x + Math.cos(r) * rz, y = site.y + Math.sin(r) * rz, tx2 = -Math.sin(r) * 7 * k, ty2 = Math.cos(r) * 7 * k; br += `<path d="M${x - tx2} ${y - ty2}L${x + tx2} ${y + ty2}"/>`; });
        ov(`<circle cx="${site.x}" cy="${site.y}" r="${rz}" fill="rgba(8,175,162,.06)" stroke="rgba(15,212,196,.42)" stroke-dasharray="${3 * k} ${5 * k}"/>
          <g stroke="#0fd4c4" stroke-width="${2.2 * k}" stroke-linecap="round">${br}</g>
          <line x1="${site.x}" y1="${site.y}" x2="${mx}" y2="${my}" stroke="${col}" stroke-width="${1.6 * k}" stroke-dasharray="${io.lift > 0.3 ? `${5 * k} ${4 * k}` : 'none'}" opacity=".85"/>
          <circle cx="${site.x}" cy="${site.y}" r="${4 * k}" fill="${col}"/>
          <circle cx="${mx}" cy="${my}" r="${rr}" fill="rgba(12,13,16,.35)" stroke="rgba(255,255,255,.18)" stroke-width="${3 * k}"/>
          <circle cx="${mx}" cy="${my}" r="${rr}" fill="none" stroke="${col}" stroke-width="${3 * k}" stroke-linecap="round" stroke-dasharray="${(C * seat).toFixed(1)} ${C.toFixed(1)}" transform="rotate(-90 ${mx} ${my})"/>
          <g stroke="${col}" stroke-width="${1.6 * k}"><line x1="${mx - rr - 6 * k}" y1="${my}" x2="${mx - rr + 3 * k}" y2="${my}"/><line x1="${mx + rr - 3 * k}" y1="${my}" x2="${mx + rr + 6 * k}" y2="${my}"/><line x1="${mx}" y1="${my - rr - 6 * k}" x2="${mx}" y2="${my - rr + 3 * k}"/><line x1="${mx}" y1="${my + rr - 3 * k}" x2="${mx}" y2="${my + rr + 6 * k}"/></g>`);
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

  /* ═══════════════════════════ STEP 6 · HOLD THE PRESSURE ═══════════════════════════ */
  H_.resus = {
    enter() {
      const d = S.data;
      S.rs = { pressure: 0, clamp: 0.66, sel: null, bags: (d.infusions || []).filter(b => b.mine !== false), counts: d.counts || {}, txa: null, txaDone: !!d.txaActive,
        foil: !!d.foilOn, mapHist: [], tegHist: [], lastPost: 0, lastRate: {}, salineIn: 0, bloodIn: 0, given: {}, stand: true, firmAt: 0, confirmBlood: 0, popped: 0 };
      const rs = S.rs;
      if (rs.bags.length) rs.sel = rs.bags[0].id;
      // the counts in the plan date from when the app opened: refresh what the medic carries now
      if (!S.preview) post('bags', {});
      S.clot = null;
      ui.pp.set({
        title: L('s_resus', 'Hold the pressure'), tag: d.access ? `${d.access.kind === 'io' ? 'IO' : 'IV'} · ${d.access.siteLabel || d.access.site || ''}` : '',
        text: L('resus_text', 'Hang fluid, pump the bulb and open the clamp until MAP sits on the target arc. Keep it there until the clot sets.'),
        hints: [{ keys: [keyName(S.keys.squeeze || 'Space')], label: L('h_squeeze', 'pump') }, { keys: ['Q', 'E'], label: L('h_clamp', 'clamp') }].concat(hintsCam()),
      });
      this.tools();
      mark('access', { label: d.access ? `${d.access.kind === 'io' ? 'IO' : 'IV'}` : '', dot: 'fd-dia white' });
      const clot = moduleHTML('ca', L('d_clot', 'Clot formation'), `
        <div class="m-split">
          <div class="m-clot"><svg viewBox="0 0 104 104" class="cr"></svg><div class="cv"><span class="fm"></span><i>%</i></div><span class="dl">${esc(L('d_firm', 'Clot'))}</span></div>
          <div class="m-list">
            ${row('r-map', 'MAP', '--')}
            ${row('r-hold', L('c_hold', 'Hold'), '--')}
            ${row('r-txa', L('chip_txa', 'TXA'), '—', 'dim')}
            ${row('r-warm', L('chip_warm', 'Warmth'), '—', 'dim')}
            ${row('r-dil', L('chip_dil', 'Dilution'), '0<small>%</small>')}
            ${row('r-pop', L('chip_pops', 'Breaks'), '0')}
          </div>
        </div>
        <div class="m-state cst"><span class="dot"></span><span class="tx">${esc(L('cs_wait', 'No flow yet'))}</span></div>
        <div class="m-trend"><span>${esc(L('c_trend', 'MAP trend'))}</span><canvas class="d-strip"></canvas></div>`, { right: '<span class="m-chip ch"></span>' });
      const inf = moduleHTML('pi', L('d_infuser', 'Line & pressure'), `
        <div class="pi-top">
          <div class="m-dial pi"><div class="dzh"></div><div class="dv"><span class="pv"></span><i>mmHg</i></div><span class="dl">${esc(L('i_pressure', 'Cuff pressure'))}</span></div>
          <div class="pi-stand"><div class="pi-hook"></div><div class="fd-bags"></div></div>
          <div class="pi-clamp"><span class="ck">${esc(L('i_clamp', 'Clamp'))}</span><button class="wheel" data-wheel="1"><i class="rid"></i><i class="cap up">${icon('chev-u')}</i><i class="cap dn">${icon('chev-d')}</i></button><b class="cl">66%</b></div>
        </div>
        <div class="pi-bot">
          <button class="pi-bulb"><span class="bb"></span><span class="bt"><b>${esc(L('i_squeeze', 'Pump'))}</b><kbd>${esc(keyName(S.keys.squeeze || 'Space'))}</kbd></span></button>
          <div class="m-list two">
            ${row('r-rt', L('i_rate', 'Flow'), '0<small>ml/min</small>')}
            ${row('r-si', L('i_saline', 'Crystalloid'), '0<small>ml</small>')}
            ${row('r-bi', L('i_blood', 'Blood'), '0<small>ml</small>')}
            ${row('r-tx', L('i_txa', 'TXA'), rs.txaDone ? icon('check') : '—', rs.txaDone ? 'teal' : 'dim')}
          </div>
        </div>
        <div class="fd-txa-h"></div>`, { right: '<span class="m-chip nb"></span>' });
      rack([clot, inf], 'wide');
      ui.inf = ui.rack.querySelector('.u-pi');
      rs.pOdo = NZA.ui.FlipClock(ui.inf.querySelector('.dv .pv'), { value: '0' });
      rs.fOdo = NZA.ui.FlipClock(ui.rack.querySelector('.m-clot .fm'), { value: '0' });
      ui.inf.querySelector('.pi-bulb').addEventListener('mousedown', e => { e.stopPropagation(); this.squeeze(); });
      const wheel = ui.inf.querySelector('.wheel');
      wheel.addEventListener('mousedown', e => { e.stopPropagation(); const r = wheel.getBoundingClientRect(); this.clampBy(e.clientY < r.top + r.height / 2 ? 0.05 : -0.05); });
      wheel.addEventListener('wheel', e => { e.preventDefault(); this.clampBy(-Math.sign(e.deltaY) * 0.02); }, { passive: false });
      this.bagsUi();
      this.clotRing(0);
      this.infTick(0);
    },
    tools() {
      const rs = S.rs, d = S.data, c = rs.counts || {};
      const saline = rs.bags.find(b => b.kind === 'saline' && b.left > 0);
      const blood = rs.bags.find(b => b.kind === 'blood' && b.left > 0);
      const bb = (d.bags || [])[0];
      const bloodSub = !d.blood ? L('tool_blood_none', 'No blood bank') : blood ? L('tool_running', 'Running') : bb ? `${bb.type} · ${bb.compatible === true ? L('compatible', 'Match') : bb.compatible === false ? L('incompatible', 'No match') : L('untyped', 'Untyped')}` : '×0';
      ui.pp.set({
        tools: [
          { key: '1', label: L('tool_saline', 'Saline 0.9%'), icon: 'iv', state: saline ? (rs.sel === saline.id ? 'active' : 'done') : (c.saline || 0) < 1 ? 'locked' : '', sub: saline ? L('tool_running', 'Running') : `500 ml ×${c.saline || 0}` },
          { key: '2', label: L('tool_blood', 'Blood unit'), icon: 'bloodbag', state: blood ? (rs.sel === blood.id ? 'active' : 'done') : (!d.blood || !bb) ? 'locked' : bb.compatible === false ? 'need' : '', sub: bloodSub },
          { key: '3', label: L('tool_txa', 'TXA 1 g'), icon: 'syringe', state: rs.txaDone ? 'done' : rs.txa ? 'active' : (c.txa || 0) < 1 ? 'locked' : '', sub: rs.txaDone ? '' : `×${c.txa || 0}` },
          { key: '4', label: L('tool_foil', 'Warming foil'), icon: 'blanket', state: rs.foil ? 'done' : (c.foil || 0) < 1 ? 'locked' : '', sub: rs.foil ? '' : `×${c.foil || 0}` },
          { key: '5', label: L('tool_squeeze', 'Pump bulb'), icon: 'gauge' },
          { key: '6', label: L('tool_nibp', 'Read BP'), icon: 'cuff' },
        ],
      });
    },
    bagsUi() {
      const rs = S.rs;
      const box = ui.inf && ui.inf.querySelector('.fd-bags');
      if (!box) return;
      const list = rs.bags.filter(b => b.left > 0);
      const nb = ui.inf.querySelector('.m-chip.nb'); if (nb) nb.textContent = `${list.length}/${(S.data.infusion || {}).maxBags || 3}`;
      if (!list.length) { box.innerHTML = `<div class="fd-bag empty"><span class="eh">${icon('iv')}</span><span>${esc(L('i_nobag', 'Nothing hanging — press 1 or 2'))}</span></div>`; return; }
      box.innerHTML = list.map(b => {
        const blood = b.kind === 'blood';
        const short = blood ? (b.bag && b.bag.type ? b.bag.type : L('bag_blood_short', 'Blood')) : L('bag_saline_tag', 'NaCl');
        const lvl = clamp(b.left / (b.ml || 500), 0, 1);
        const drip = b.paused ? 0 : clamp((b.rate || 0) / 80, 0.08, 1);
        return `<div class="fd-bag ${blood ? 'blood' : ''} ${rs.sel === b.id ? 'sel' : ''} ${b.paused ? 'paused' : ''}" data-id="${esc(b.id)}" title="${esc(blood ? L('bag_blood_short', 'Blood') : L('bag_saline_short', 'Saline {ml} ml', { ml: b.ml }))}">
          <button class="down" title="${esc(L('take_down_btn', 'Remove'))}">${icon('x')}</button>
          <svg viewBox="0 0 44 74" class="bg"><path class="bo" d="M8 6h28l4 6v42q0 8-8 8H12q-8 0-8-8V12z"/>
            <clipPath id="bc${esc(b.id)}"><path d="M8 6h28l4 6v42q0 8-8 8H12q-8 0-8-8V12z"/></clipPath>
            <rect class="fl" x="0" y="${(10 + (1 - lvl) * 52).toFixed(1)}" width="44" height="70" clip-path="url(#bc${esc(b.id)})"/>
            <path class="hl" d="M10 12v38"/><rect class="lb" x="12" y="22" width="20" height="16" rx="1.5"/><path class="lbl" d="M15 27h14M15 31h10"/>
            <path class="pt" d="M18 62h8v8h-8z"/><circle class="hk" cx="22" cy="3" r="2.6"/></svg>
          <span class="dc" style="--drip:${(1.6 - drip * 1.3).toFixed(2)}s"><i></i></span>
          <span class="bn">${esc(short)}</span><span class="bl">${Math.round(b.left)}<small>ml</small></span>
        </div>`;
      }).join('');
      box.querySelectorAll('.fd-bag').forEach(c => {
        c.addEventListener('mousedown', e => e.stopPropagation());
        c.addEventListener('click', e => { if (e.target.closest('.down')) return; rs.sel = c.dataset.id; this.bagsUi(); this.tools(); });
        c.querySelector('.down').addEventListener('click', e => { e.stopPropagation(); this.takeDown(c.dataset.id); });
      });
    },
    hang(kind) {
      const rs = S.rs, d = S.data;
      if (rs.bags.filter(b => b.left > 0).length >= ((d.infusion || {}).maxBags || 3)) { ui.pp.flash('warn', L('too_many', 'Three bags already hanging.')); return; }
      let serialNo = null, type = null;
      if (kind === 'blood') {
        const bb = (d.bags || [])[0];
        if (!d.blood || !bb) { ui.pp.flash('bad', d.blood ? L('no_blood', 'You carry no blood.') : L('no_blood_module', 'Blood needs the blood bank.')); return; }
        if (bb.compatible === false && now() - rs.confirmBlood > 3000) { rs.confirmBlood = now(); ui.pp.flash('bad', L('blood_incompat', '{t} does NOT match this patient. Press 2 again to hang it anyway.', { t: bb.type })); return; }
        if (bb.compatible !== true && bb.compatible !== false && now() - rs.confirmBlood > 3000) { rs.confirmBlood = now(); ui.pp.flash('warn', L('blood_untyped', 'No blood type yet — only O− is safe. Press 2 again to hang {t}.', { t: bb.type })); return; }
        serialNo = bb.serial; type = bb.type;
      } else if ((rs.counts.saline || 0) < 1) { ui.pp.flash('bad', L('no_saline', 'No saline bag left.')); return; }
      const rate = Math.max(1, Math.round(this.rateFor(kind)));
      const go = r => {
        if (!r || r.ok === false || !r.inf) { ui.pp.flash('bad', (r && r.msg) || L('hang_fail', 'The bag would not hang.')); return; }
        rs.bags.push(Object.assign({ mine: true }, r.inf));
        rs.sel = r.inf.id;
        if (kind === 'saline') rs.counts.saline = Math.max(0, (rs.counts.saline || 1) - 1);
        if (kind === 'blood') d.bags = (d.bags || []).filter(b => b.serial !== serialNo);
        NZA.audio.click(880);
        ui.pp.flash('ok', kind === 'blood' ? L('hung_blood', 'Blood {t} running.', { t: type || '' }) : L('hung_saline', 'Saline running.'));
        this.bagsUi(); this.tools();
      };
      if (S.preview) go({ ok: true, inf: { id: `i${Date.now() % 1000}`, kind, ml: kind === 'blood' ? 450 : 500, left: kind === 'blood' ? 450 : 500, rate, bag: type ? { type } : null } });
      else post('hang', { kind, serial: serialNo, rate }).then(go);
    },
    takeDown(id) {
      const rs = S.rs;
      const go = r => {
        if (!r || r.ok === false) { ui.pp.flash('bad', (r && r.msg) || L('takedown_fail', 'The bag would not come down.')); return; }
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
      return clamp(r, 1, S.data.maxRate || 160);
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
      box.innerHTML = `<div class="fd-txa"><div class="t"><b>${esc(L('txa_title', 'TXA 1 g / 10 ml'))}</b><span>${esc(L('txa_slow', 'Hold the plunger · over ≥ {s} s', { s: push }))}</span></div><div class="sh"></div></div>`;
      const t0 = { start: 0 };
      rs.txa = Syringe(box.querySelector('.sh'), {
        cap: 10, vol: 10, mode: 'push', fluid: 'txa', band: [0.15, 10 / push], maxRate: (10 / push) * 2, label: L('tool_txa', 'TXA 1 g'), compact: true,
        onChange: vol => {
          if (!t0.start && vol < 9.9) t0.start = now();
          if (vol <= 0.05 && !rs.txaDone) {
            const secs = (now() - t0.start) / 1000;
            rs.txaDone = true;
            const fin = r => {
              if (r && r.ok === false) { rs.txaDone = false; ui.pp.flash('bad', r.msg || L('txa_fail', 'TXA not given.')); return; }
              ui.pp.flash(secs < push * 0.6 ? 'warn' : 'ok', secs < push * 0.6 ? L('txa_fast', 'TXA in — too fast, pressure dips.') : L('txa_ok', 'TXA in. The clot will hold better.'));
              rs.counts.txa = Math.max(0, (rs.counts.txa || 1) - 1);
              setTimeout(() => { if (rs.txa) { rs.txa.destroy(); rs.txa = null; box.innerHTML = ''; } this.tools(); }, 900);
            };
            if (S.preview) fin({ ok: true }); else post('txa', { seconds: Math.round(secs * 10) / 10 }).then(fin);
          }
        },
        onTick: () => { if (t0.start && !rs.txaDone) setRow('.r-tx', `${fmt1((now() - t0.start) / 1000)}<small>/${push} s</small>`, 'amber'); },
      });
      this.tools();
    },
    foil() {
      const rs = S.rs;
      if (rs.foil) return;
      const go = r => { if (r && r.ok === false) { ui.pp.flash('bad', r.msg || L('foil_fail', 'No foil blanket.')); return; } rs.foil = true; ui.pp.flash('ok', L('foil_ok', 'Foil on — keep the heat in.')); this.tools(); };
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
      if (k === '6') { post('nibp', {}); NZA.audio.click(600); ui.pp.flash('ok', L('nibp_cycle', 'Taking a BP…'), 1400); }
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
      if (!ui.inf) return;
      rs.pressure = Math.max(0, rs.pressure - (inf.leak || 6) * dt);
      const p = Math.round(rs.pressure), maxP = inf.maxPressure || 300;
      const pd = Math.round(p / 3);
      if (pd !== rs.lastPd) {
        rs.lastPd = pd;
        ui.inf.querySelector('.m-dial.pi .dzh').innerHTML = dialSVG(p / maxP, { zone: [0.6, 1], tone: p > maxP * 0.6 ? 'teal' : p > 0 ? 'amber' : '', ticks: 10 });
        rs.pOdo.set(String(p));
      }
      const bulb = ui.inf.querySelector('.pi-bulb'); if (bulb) bulb.classList.toggle('on', now() - (rs.sqT || 0) < 180);
      const cl = ui.inf.querySelector('.cl'); if (cl) cl.textContent = `${Math.round(rs.clamp * 100)}%`;
      const wh = ui.inf.querySelector('.wheel'); if (wh) { wh.style.setProperty('--roll', `${(rs.clamp * 140).toFixed(1)}px`); wh.style.setProperty('--open', rs.clamp.toFixed(2)); }
      const sel = rs.bags.find(b => b.id === rs.sel && b.left > 0);
      const rate = sel ? Math.round(this.rateFor(sel.kind)) : 0;
      const total = rs.bags.filter(b => b.left > 0).reduce((a, b) => a + (b.id === rs.sel ? rate : (b.rate || 0)), 0);
      let si = rs.salineIn, bi = rs.bloodIn;
      rs.bags.forEach(b => { if (b.kind === 'blood') bi += b.ml - b.left; else si += b.ml - b.left; });
      const sig = `${total}|${Math.round(si)}|${Math.round(bi)}|${rs.txaDone}`;
      if (sig !== rs.lastSig) {
        rs.lastSig = sig;
        setRow('.r-rt', `${total}<small>ml/min</small>`, total > 0 ? 'teal' : '');
        setRow('.r-si', `${Math.round(si)}<small>ml</small>`, si > (inf.dilution || 1000) ? 'amber' : '');
        setRow('.r-bi', `${Math.round(bi)}<small>ml</small>`, bi > 0 ? 'red' : '');
        if (rs.txaDone && !rs.txa) setRow('.r-tx', `${icon('check')}<small>${esc(L('given', 'given'))}</small>`, 'teal');
      }
      // post the new flow for the selected bag (throttled)
      if (sel && (Math.abs((rs.lastRate[sel.id] || sel.rate || 0) - rate) >= 2) && now() - rs.lastPost > 650) {
        rs.lastPost = now(); rs.lastRate[sel.id] = rate; sel.rate = rate;
        const dc = ui.inf.querySelector(`.fd-bag[data-id="${sel.id}"] .dc`); if (dc) dc.style.setProperty('--drip', `${(1.6 - clamp(rate / 80, 0.08, 1) * 1.3).toFixed(2)}s`);
        if (!S.preview) post('rate', { id: sel.id, rate });
      }
    },
    clotRing(firm, state) {
      const svg = ui.rack && ui.rack.querySelector('.m-clot .cr');
      if (!svg) return;
      const N = 36, lit = Math.floor(clamp(firm, 0, 100) / 100 * N + 1e-6);
      let segs = '';
      for (let i = 0; i < N; i++) {
        const a0 = (-90 + (360 / N) * i + 1.6) * Math.PI / 180, a1 = (-90 + (360 / N) * (i + 1) - 1.6) * Math.PI / 180;
        const r1 = 36, r2 = 46;
        const p = (r, a) => `${(52 + Math.cos(a) * r).toFixed(2)} ${(52 + Math.sin(a) * r).toFixed(2)}`;
        segs += `<path class="${i < lit ? 'on' : ''}" d="M${p(r1, a0)}L${p(r2, a0)}A${r2} ${r2} 0 0 1 ${p(r2, a1)}L${p(r1, a1)}A${r1} ${r1} 0 0 0 ${p(r1, a0)}z"/>`;
      }
      svg.innerHTML = `<circle class="in" cx="52" cy="52" r="31"/>${segs}`;
      svg.setAttribute('class', `cr ${state || ''}`);
    },
    clotTick() {
      const c = S.clot, rs = S.rs;
      if (!c) return;
      if (rs.fOdo) rs.fOdo.set(String(Math.floor(c.firm)));
      this.clotRing(c.firm, c.state === 'popped' ? 'bad' : c.firm >= 100 ? 'done' : c.state === 'band' || c.state === 'own' ? 'ok' : 'warn');
      S.metric = { label: L('st_clot', 'Clot'), value: Math.floor(c.firm), unit: '%', tone: c.firm >= 100 ? 'teal' : c.state === 'popped' ? 'red' : '' };
      const inBand = c.map >= S.band[0] && c.map <= S.band[1];
      setRow('.r-map', `${c.map}<small>mmHg</small>`, inBand ? 'teal' : c.map > S.band[1] ? 'amber' : 'red');
      setRow('.r-hold', c.state === 'firm' ? icon('check') : c.warn ? `<span class="warn">${esc(L('pop_in', 'breaks in'))} ${fmt1(Math.max(0, c.warn))}</span><small>s</small>` : c.eta ? `${c.eta}<small>s</small>` : '--', c.state === 'firm' ? 'teal' : c.warn ? 'red' : '');
      const m = c.mods || {};
      setRow('.r-txa', m.txa ? `${icon('check')}<small>${esc(L('c_on', 'on board'))}</small>` : '—', m.txa ? 'teal' : 'dim');
      setRow('.r-warm', esc(m.cold ? (m.foil ? L('c_foil', 'Foil on') : L('c_cold', 'Cold')) : L('c_warm', 'Warm')), m.cold ? (m.foil ? 'amber' : 'red') : 'teal');
      setRow('.r-dil', `${m.dil || 0}<small>%</small>`, m.dilution ? 'red' : '');
      setRow('.r-pop', String(c.pops || 0), c.pops ? 'red' : '');
      const st = q('.cst');
      const stTxt = { band: L('cs_band', 'On target — holding'), below: L('cs_below', 'Just under'), low: L('cs_low', 'Too low to clot'), high: L('cs_high', 'Over — ease off'),
        own: L('cs_own', 'Holding unassisted'), popped: L('cs_popped', 'Clot broke'), firm: L('cs_firm', 'Set'), arrest: L('cs_arrest', 'No output') }[c.state] || c.state;
      if (st) { st.className = `m-state cst ${c.state === 'band' || c.state === 'firm' || c.state === 'own' ? 'teal' : c.state === 'below' || c.state === 'high' ? 'amber' : 'red'}`; st.querySelector('.tx').textContent = stTxt; }
      const ch = q('.m-chip.ch'); if (ch) { ch.textContent = c.state === 'firm' ? L('c_set', 'Set') : `${Math.floor(c.firm)}%`; ch.className = `m-chip ch ${c.state === 'firm' ? 'teal' : ''}`; }
      if (c.bags && !S.preview) {
        // server truth for what is left / running
        const mine = c.bags.filter(b => b.mine);
        mine.forEach(b => { const x = rs.bags.find(y => y.id === b.id); if (x) { x.left = b.left; x.paused = b.paused; } else rs.bags.push(b); });
        rs.bags.forEach(x => { if (!mine.find(b => b.id === x.id)) { if (x.kind === 'blood') rs.bloodIn += x.ml - (x.left || 0); else rs.salineIn += x.ml - (x.left || 0); x.left = 0; } });
        rs.bags = rs.bags.filter(x => x.left > 0);
        if (rs.sel && !rs.bags.find(b => b.id === rs.sel)) rs.sel = rs.bags.length ? rs.bags[0].id : null;
        this.bagsUi();
      }
      if (c.bleed !== undefined) { S.bleed = c.bleed; }
      stats();
      if (c.txa) rs.txaDone = true;
      if (c.foil) rs.foil = true;
      rs.mapHist.push(c.map); if (rs.mapHist.length > 60) rs.mapHist.shift();
      this.drawStrip();
      const txt = c.state === 'firm' ? L('resus_firm', 'Clot set at 100%. Leave the line open.')
        : c.state === 'band' ? L('resus_band', 'MAP on target. Keep it steady — clot {f}%, {s} s to go.', { s: c.eta || '--', f: Math.floor(c.firm) })
          : c.state === 'own' ? L('resus_own', 'Pressure holds without help. Keep the drip slow — clot {f}%, {s} s to go.', { s: c.eta || '--', f: Math.floor(c.firm) })
            : c.state === 'high' ? L('resus_high', 'MAP {m} — over target. Close the clamp before the clot breaks.', { m: c.map })
              : c.state === 'below' ? L('resus_below', 'MAP {m} — just under. Open the clamp a little or pump the bulb.', { m: c.map })
                : c.state === 'low' ? L('resus_low', 'MAP {m} — far too low to clot. Run fluid now.', { m: c.map })
                  : c.state === 'popped' ? L('resus_popped', 'The clot broke loose. Bleeding is up — bring MAP back into the arc.') : '';
      if (txt) ui.pp.set({ text: txt, titleTone: c.state === 'firm' ? 'ok' : c.state === 'popped' || c.state === 'low' ? 'bad' : '' });
      if (c.state === 'firm' && !rs.firmAt) {
        rs.firmAt = now();
        NZA.audio.success();
        ui.pp.flash('ok', L('resus_done', 'Clot set.'), 0);
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
    drawStrip() {
      const cv = q('.d-strip'); if (!cv) return;
      const { w, h } = NZA.fitCanvas(cv);
      const c = cv.getContext('2d');
      c.clearRect(0, 0, w, h);
      const lo = 35, hi = 95;
      const y = v => h - ((clamp(v, lo, hi) - lo) / (hi - lo)) * h;
      c.fillStyle = 'rgba(15,212,196,.12)'; c.fillRect(0, y(S.band[1]), w, y(S.band[0]) - y(S.band[1]));
      c.strokeStyle = 'rgba(15,212,196,.55)'; c.lineWidth = 1; c.setLineDash([3, 3]);
      [S.band[0], S.band[1]].forEach(v => { c.beginPath(); c.moveTo(0, y(v)); c.lineTo(w, y(v)); c.stroke(); });
      c.strokeStyle = 'rgba(229,72,77,.5)'; const lm = S.data.lowMap || 52; c.beginPath(); c.moveTo(0, y(lm)); c.lineTo(w, y(lm)); c.stroke();
      c.setLineDash([]);
      const hist = S.rs.mapHist; if (hist.length < 2) return;
      const pts = hist.map((v, i) => [(i / 59) * w, y(v)]);
      const g = c.createLinearGradient(0, 0, 0, h); g.addColorStop(0, 'rgba(255,255,255,.16)'); g.addColorStop(1, 'rgba(255,255,255,0)');
      c.fillStyle = g; c.beginPath(); c.moveTo(pts[0][0], h); pts.forEach(([x, yy]) => c.lineTo(x, yy)); c.lineTo(pts[pts.length - 1][0], h); c.closePath(); c.fill();
      c.strokeStyle = '#fff'; c.lineWidth = 1.8 * (w / (cv.clientWidth || w)); c.lineJoin = 'round'; c.beginPath();
      pts.forEach(([x, yy], i) => (i ? c.lineTo(x, yy) : c.moveTo(x, yy)));
      c.stroke();
      const last = hist[hist.length - 1];
      c.fillStyle = last >= S.band[0] && last <= S.band[1] ? '#0fd4c4' : '#f3c35a';
      c.shadowColor = c.fillStyle; c.shadowBlur = 8;
      c.beginPath(); c.arc(pts[pts.length - 1][0], y(last), 3.4 * (w / (cv.clientWidth || w)), 0, Math.PI * 2); c.fill(); c.shadowBlur = 0;
    },
    frame(dt) { if (S.rs) this.infTick(dt); },
    leave() { const rs = S.rs; if (rs && rs.txa) { rs.txa.destroy(); rs.txa = null; } ui.inf = null; },
  };

  /* ═══════════════════════════ STEP 7 · RECHECK / HANDOVER ═══════════════════════════ */
  H_.reassess = {
    enter() {
      ui.pp.set({ title: L('s_recheck', 'Recheck'), text: L('reassess_wait', 'Rechecking vitals…'), tools: [] });
      rack([`<div class="fd-card ho"><div class="ho-h"><span class="t">${esc(L('d_reassess', 'Handover'))}</span></div><div class="m-note"><span class="ni">${icon('clock')}</span><span>${esc(L('reassess_wait', 'Rechecking vitals…'))}</span></div></div>`]);
    },
    show(s) {
      const b = s.before || {}, a = s.after || {};
      if (a.bleed !== undefined) S.bleed = a.bleed;
      if (a.map) S.vit.map = a.map;
      S.metric = null; stats();
      const trend = (k, bv, av, good, unit = '') => {
        const has = av !== undefined && av !== null && bv !== undefined && bv !== null;
        const up = has && Number(av) > Number(bv), same = has && Number(av) === Number(bv);
        const tone = good === true ? 'teal' : good === false ? 'red' : '';
        return `<div class="ho-r ${tone}"><span class="k">${esc(k)}</span><span class="b">${esc(bv ?? '--')}</span><span class="ar ${same ? 'eq' : up ? 'up' : 'dn'}">${icon(same ? 'minus' : up ? 'arrow-ur' : 'arrow-r')}</span><span class="a">${esc(av ?? '--')}<small>${esc(unit)}</small></span></div>`;
      };
      const score = (s.steps || []).filter(st => !st.skipped && st.score !== undefined);
      const avg = score.length ? Math.round(score.reduce((x, st) => x + Number(st.score || 0), 0) / score.length) : null;
      const RC = 2 * Math.PI * 15;
      const steps = (s.steps || []).map(st => {
        const sc = st.skipped ? 0 : clamp(Number(st.score ?? (st.grade ? { S: 96, A: 85, B: 72, C: 57, D: 42, F: 20 }[st.grade] : 0)) / 100, 0, 1);
        const tone = st.skipped ? 'skip' : sc >= 0.65 ? 'ok' : sc >= 0.35 ? 'mid' : 'low';
        return `<div class="ho-s ${tone}"><span class="nd"><svg class="rg" viewBox="0 0 36 36"><circle class="bg" cx="18" cy="18" r="15"/><circle class="fg" cx="18" cy="18" r="15" stroke-dasharray="${(RC * sc).toFixed(1)} ${RC.toFixed(1)}" transform="rotate(-90 18 18)"/></svg>${icon(st.skipped ? 'minus' : 'check')}</span>
          <span class="tx"><b>${esc(st.label)}</b><small>${esc(st.skipped ? L('skipped', 'skipped') : st.note || '')}</small></span><span class="pc">${st.skipped ? '–' : `${Math.round(sc * 100)}`}<small>${st.skipped ? '' : '%'}</small></span></div>`;
      }).join('');
      rack([`<div class="fd-card ho">
        <div class="ho-h"><span class="t">${esc(L('d_reassess', 'Handover'))}</span>${avg !== null ? `<span class="ho-q"><svg class="rg" viewBox="0 0 36 36"><circle class="bg" cx="18" cy="18" r="15"/><circle class="fg" cx="18" cy="18" r="15" stroke-dasharray="${(RC * avg / 100).toFixed(1)} ${RC.toFixed(1)}" transform="rotate(-90 18 18)"/></svg><b>${avg}</b></span>` : ''}</div>
        <div class="ho-cols"><span></span><span>${esc(L('before', 'Start'))}</span><span></span><span>${esc(L('now', 'Now'))}</span></div>
        ${trend(L('st_bleed', 'Bleed'), b.bleed !== undefined ? fmt1(b.bleed) : '--', a.bleed !== undefined ? fmt1(a.bleed) : '--', a.bleed !== undefined && b.bleed !== undefined ? a.bleed < b.bleed : null, 'ml/m')}
        ${trend('MAP', b.map, a.map, a.map >= S.band[0] && a.map <= S.band[1] + 8)}
        ${trend('HR', b.hr, a.hr, a.hr && b.hr ? a.hr <= b.hr : null)}
        ${trend('SpO₂', b.spo2, a.spo2, a.spo2 >= 94)}
        <div class="ho-sp">${steps}</div>
        <div class="ho-dev">${(s.devices || []).map(d => `<span class="m-chip teal">${esc(d)}</span>`).join('')}</div>
      </div>`]);
      ui.pp.complete({
        title: L('t_done', 'Ready for handover'), label: L('finish', 'Finish'),
        text: s.text || L('reassess_text', 'Bleeding down to {a} mL/min from {b}. Package the patient and move.', { a: fmt1(a.bleed || 0), b: fmt1(b.bleed || 0) }),
        onDone: () => { post('done', {}); if (S.preview) NZA.toast({ title: L('t_done', 'Ready for handover'), message: L('report_saved', 'Saved to the patient record.') }); },
      });
    },
  };

  /* ═══════════════════════════ IV CANNULATION ═══════════════════════════ */
  const IV_STEPS = ['tq', 'find', 'insert', 'advance', 'withdraw', 'secure'];
  const IV_EN = { tq: 'Tourniquet on', find: 'Feel for a vein', insert: 'Needle in', advance: 'Slide the cannula', withdraw: 'Needle out', secure: 'Dress and flush' };
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
      if (ph === 'tq') mark('tq', { label: L('m_tq', 'Tourniquet'), dot: 'fd-dia white' });
      else if (ph === 'find') mark('site', { label: L('m_forearm', 'Forearm'), dot: 'fd-dia fd-target' });
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
        tq: L('iv_tq', 'Band the upper arm with the **tourniquet** (1) and let the veins fill.'),
        find: iv.fill < 1 ? L('iv_fill', 'Veins filling… {p}%', { p: Math.round(iv.fill * 100) }) : L('iv_find', 'Hold {Click} on the forearm and press. A good vein springs back — let go to mark it.'),
        insert: iv.inVein ? L('iv_flash', 'Blood in the chamber — stop there.') : L('iv_insert', 'Set {a}–{b}° with the wheel or ↑ ↓, then hold {{key}} to go in.', { a: a[0], b: a[1], key: keyName(S.keys.insert || 'Space') }),
        advance: L('iv_advance', 'Drop the angle and hold {{key}} to slide the cannula home. {p}%', { key: keyName(S.keys.advance || 'KeyE'), p: Math.round(iv.cannula * 100) }),
        withdraw: iv.tq ? L('iv_withdraw_tq', 'Take the **tourniquet** off (1) before the needle comes out.') : L('iv_withdraw', 'Press above the tip and **drag the needle out** of the cannula.'),
        secure: !iv.secured ? L('iv_secure', 'Cover the hub with the **dressing** (3).') : !iv.flushed ? L('iv_flush', 'Flush it (4) to prove it runs.') : L('iv_done', 'Line in and running.'),
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
          <defs><linearGradient id="skn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b78468"/><stop offset=".5" stop-color="#d4a387"/><stop offset="1" stop-color="#a87459"/></linearGradient>
            <radialGradient id="sknl" cx=".5" cy=".3" r=".8"><stop offset="0" stop-color="rgba(255,255,255,.18)"/><stop offset="1" stop-color="rgba(255,255,255,0)"/></radialGradient></defs>
          <rect x="2" y="8" width="296" height="134" rx="60" fill="url(#skn)"/><rect x="2" y="8" width="296" height="134" rx="60" fill="url(#sknl)"/>
          <g class="veins">${veins}</g>
          <text x="14" y="146" font-size="7" fill="rgba(255,255,255,.4)" font-family="Lexend" font-weight="700" letter-spacing="1.5">${esc(L('d_wrist', 'WRIST'))}</text>
          <text x="286" y="146" text-anchor="end" font-size="7" fill="rgba(255,255,255,.4)" font-family="Lexend" font-weight="700" letter-spacing="1.5">${esc(L('d_elbow', 'ELBOW'))}</text>
          <g class="fing" style="display:none"><circle r="14" fill="rgba(255,255,255,.12)" stroke="#fff" stroke-width="1.5"/><circle class="rip" r="14" fill="none" stroke="#0fd4c4" stroke-width="2" opacity="0"/></g>
          <g class="pin" style="display:none"><rect x="-6" y="-6" width="12" height="12" rx="2" transform="rotate(45)" fill="#08afa2" stroke="#fff" stroke-width="2"/></g>
        </svg>
        <div class="m-split mid"><div class="m-list"><div class="m-row r-bq"><span class="k">${esc(L('d_bounce', 'Rebound'))}</span><span class="v">—</span></div></div><div class="d-bounce"></div></div>`,
      { unit: 'vf', right: `<span class="m-chip">${S.data.gauge || 18}G</span>` });
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
      setRow('.r-bq', esc(iv.bounce > 0.7 ? L('b_good', 'Springy') : iv.bounce > 0.35 ? L('b_ok', 'Soft') : L('b_none', 'Nothing')), iv.bounce > 0.7 ? 'teal' : iv.bounce > 0.35 ? 'amber' : 'dim');
      const bm = q('.d-bounce'); if (bm) bm.innerHTML = NZA.ui.meterHTML({ value: iv.bounce, zone: [0.7, 1], lg: true });
      if (iv.bounce > 0.7 && Math.random() < 0.08) NZA.audio.tick();
    },
    markAt() {
      const iv = S.iv;
      const f = ui.dev.querySelector('.fing'); if (f) f.style.display = 'none';
      if (!iv.cur || iv.bounce < 0.35) { ui.pp.flash('warn', L('iv_nothing', 'Nothing there. Feel further along the forearm.')); return; }
      iv.mark = iv.cur; iv.palpQ = iv.bounce; iv.vein = iv.near && iv.near.v;
      const pin = ui.dev.querySelector('.pin'); if (pin) { pin.style.display = ''; pin.setAttribute('transform', `translate(${iv.mark.x},${iv.mark.y})`); }
      ui.pp.flash(iv.bounce > 0.7 ? 'ok' : 'warn', iv.bounce > 0.7 ? L('iv_marked_good', 'Vein marked — firm and springy.') : L('iv_marked_soft', 'Marked — small and soft. Harder to hit.'));
      NZA.audio.click(820);
      setTimeout(() => { if (S.iv === iv && iv.phase === 'find') { iv.tip = 0; iv.inVein = false; iv.inT = 0; iv.blown = false; this.go('insert'); } }, 800);
    },
    xsecDev() {
      devFrame(L('d_xsec', 'Needle cam'), `<canvas class="d-xsec" data-wheel="1"></canvas>
        <div class="m-split mid"><div class="m-dial iv"><div class="dzh"></div><div class="dv"><span class="xa">--</span><i>°</i></div></div>
          <div class="m-list">
            ${row('r-xf', L('d_chamber', 'Flash chamber'), esc(L('d_empty', 'Empty')), 'dim')}
            ${row('r-xc', L('d_cannula', 'Cannula'), '0<small>%</small>')}
            ${row('r-xa', L('st_attempts', 'Attempts'), `${S.iv.attempts}/${S.data.attempts || 2}`)}
          </div></div>`, { unit: 'nc', right: `<span class="m-chip">${S.data.gauge || 18}G</span>` });
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
          if (!iv.inVein) { iv.inVein = true; NZA.audio.beep(1100, 60, 0.05); if (iv.phase === 'insert') ui.pp.flash('ok', L('iv_flash', 'Blood in the chamber — stop there.'), 1500); this.text(); }
          iv.flash = Math.min(1, iv.flash + dt * 2.5);
        } else if (iv.inVein && tipY > g.cy) {
          // went through the back wall
          iv.blown = true; iv.inVein = false; this.blown(); return;
        } else if (iv.tip > 175 && !iv.miss && iv.phase === 'insert') {
          iv.miss = true; iv.misses += 1;
          ui.pp.flash('warn', tipY < g.cy ? L('iv_miss_flat', 'Too shallow — you passed over it. Back out and go steeper.') : L('iv_miss_steep', 'Too steep — you passed under it. Back out and go flatter.'));
          setTimeout(() => { if (S.iv === iv) { iv.tip = 0; iv.miss = false; } }, 1200);
        }
        if (iv.phase === 'insert' && iv.inVein && !S.held[insertKey] && !iv.blown) { iv.inT += dt; if (iv.inT > 0.5) { iv.inT = 0; this.go('advance'); } }
      }
      if (iv.phase === 'advance' && S.held[S.keys.advance || 'KeyE']) {
        iv.cannula = clamp(iv.cannula + dt * 0.55, 0, 1); this.text();
        if (iv.cannula >= 1) { NZA.audio.success(); ui.pp.flash('ok', L('iv_cannula_in', 'Cannula home.')); this.go('withdraw'); }
      }
      // draw
      c.clearRect(0, 0, w, h);
      c.save(); c.scale(sx, sy);
      const sk = c.createLinearGradient(0, g.skin, 0, 150); sk.addColorStop(0, '#d9a98b'); sk.addColorStop(0.08, '#c48c70'); sk.addColorStop(1, '#8e5a44');
      c.fillStyle = '#05080a'; c.fillRect(0, 0, 300, g.skin);
      c.fillStyle = sk; c.fillRect(0, g.skin, 300, 150 - g.skin);
      c.strokeStyle = 'rgba(255,225,205,.5)'; c.lineWidth = 1.2; c.beginPath(); c.moveTo(0, g.skin); c.lineTo(300, g.skin); c.stroke();
      c.strokeStyle = 'rgba(255,255,255,.05)'; c.lineWidth = 1;
      for (let i = 0; i < 7; i++) { c.beginPath(); c.moveTo(0, g.skin + 12 + i * 13); c.bezierCurveTo(100, g.skin + 6 + i * 13, 200, g.skin + 18 + i * 13, 300, g.skin + 10 + i * 13); c.stroke(); }
      // vein
      c.fillStyle = iv.blown ? '#5a1f28' : '#3b4f8f';
      c.beginPath(); c.ellipse(g.cx, g.cy, g.rx, g.ry, 0, 0, Math.PI * 2); c.fill();
      c.fillStyle = iv.blown ? 'rgba(90,20,30,.55)' : '#7a1d26';
      c.beginPath(); c.ellipse(g.cx, g.cy, g.rx - 3, g.ry - 3, 0, 0, Math.PI * 2); c.fill();
      c.fillStyle = 'rgba(255,255,255,.12)'; c.beginPath(); c.ellipse(g.cx - g.rx * 0.2, g.cy - g.ry * 0.45, g.rx * 0.5, g.ry * 0.18, 0, 0, Math.PI * 2); c.fill();
      if (iv.blown) { c.fillStyle = 'rgba(80,10,25,.45)'; c.beginPath(); c.ellipse(g.cx, g.cy + 8, g.rx + 20, g.ry + 16, 0, 0, Math.PI * 2); c.fill(); }
      // angle band guide (wedge)
      const band = d.angle || [15, 30];
      const r0 = band[0] * Math.PI / 180, r1 = band[1] * Math.PI / 180;
      c.fillStyle = 'rgba(15,212,196,.1)'; c.beginPath(); c.moveTo(g.entryX, g.skin); c.arc(g.entryX, g.skin, 56, Math.PI + r0, Math.PI + r1); c.closePath(); c.fill();
      c.strokeStyle = 'rgba(15,212,196,.45)'; c.lineWidth = 1; c.setLineDash([3, 3]);
      [r0, r1].forEach(r => { c.beginPath(); c.moveTo(g.entryX, g.skin); c.lineTo(g.entryX - Math.cos(r) * 56, g.skin - Math.sin(r) * 56); c.stroke(); });
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
      // readouts
      const off = iv.angle < band[0] || iv.angle > band[1];
      const dz = q('.m-dial.iv .dzh');
      if (dz && dz.dataset.a !== String(iv.angle)) { dz.dataset.a = String(iv.angle); dz.innerHTML = dialSVG(iv.angle / 45, { zone: [band[0] / 45, band[1] / 45], tone: off ? 'amber' : 'teal', ticks: 9 }); const xa = q('.xa'); if (xa) xa.textContent = iv.angle; }
      setRow('.r-xf', esc(iv.flash > 0.1 ? L('d_flash', 'Blood') : L('d_empty', 'Empty')), iv.flash > 0.1 ? 'red' : 'dim');
      setRow('.r-xc', `${Math.round(iv.cannula * 100)}<small>%</small>`, iv.cannula >= 1 ? 'teal' : '');
    },
    blown() {
      const iv = S.iv, max = S.data.attempts || 2;
      NZA.audio.fail();
      ui.pp.flash('bad', L('iv_blown', 'Through the back wall — that vein is gone.'), 0);
      if (!S.preview && S.data.responsive) NZA.speech({ name: S.data.name || '', text: L('say_ouch', 'Ouch!'), ms: 1800 });
      setTimeout(() => {
        if (S.iv !== iv) return;
        if (iv.attempts >= max) { this.finish(true); return; }
        iv.attempts += 1; iv.blown = false; iv.flash = 0; iv.tip = 0; iv.inVein = false; iv.cannula = 0; iv.mark = null; stats();
        this.go('find');
        ui.pp.flash('warn', L('iv_new_site', 'New cannula — pick another spot.'));
      }, 1600);
    },
    withdrawn() {
      const iv = S.iv;
      if (iv.phase !== 'withdraw') return;
      if (iv.tq) { iv.spill = true; ui.pp.flash('bad', L('iv_spill', 'Blood everywhere — the tourniquet was still on.')); }
      else { NZA.audio.success(); ui.pp.flash('ok', L('iv_needle_out', 'Needle out and into the sharps bin.')); }
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
        if (iv.tq && (iv.phase === 'withdraw' || iv.phase === 'secure' || iv.phase === 'advance')) { iv.tq = false; post('ivTq', { on: false }); NZA.audio.click(400); ui.pp.flash('ok', L('iv_tq_off', 'Tourniquet off.')); this.tools(); this.text(); }
        return;
      }
      if (k === '3' && iv.phase === 'secure' && !iv.secured) { iv.secured = true; NZA.audio.click(900); ui.pp.flash('ok', L('iv_secured', 'Hub covered and taped.')); this.tools(); this.text(); return; }
      if (k === '4' && iv.phase === 'secure' && iv.secured && !iv.flushed) {
        iv.flushed = true; NZA.audio.success(); ui.pp.flash('ok', L('iv_flushed', 'Runs freely — no swelling.')); this.tools(); this.text();
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
    if (e.target.closest && e.target.closest('.pp, .fd-view, .fd-rack')) return;
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
    const vk = viewKey();
    if (e.code === vk || e.key === vk) { if (!e.repeat) cycleView(e.shiftKey ? -1 : 1); return true; }
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
    const dt = Math.min(0.1, (t - (lastT || t)) / 1000); lastT = t;   // real time down to 10 fps
    const h = H_[S.proc];
    if (h && h.frame && S.status === 'run') { try { h.frame(dt); } catch (err) { console.error('[field]', err); } }
    if (S.preview && ui.scene) drawScene();
    raf = requestAnimationFrame(loop);
  }

  /* ═══════════════════════════ PREVIEW SCENE (browser only) ═══════════════════════════ */
  const PREV = {
    pelvis: { x: 0.47, y: 0.5 }, strapA: { x: 0.47, y: 0.64 }, strapB: { x: 0.47, y: 0.36 }, kit: { x: 0.45, y: 0.19 }, stand: { x: 0.4, y: 0.79 },
    kitA: { x: 0.37, y: 0.2 }, kitB: { x: 0.53, y: 0.2 }, kitC: { x: 0.37, y: 0.33 }, kitD: { x: 0.53, y: 0.33 }, kitE: { x: 0.37, y: 0.08 }, kitF: { x: 0.53, y: 0.08 },
    l_tibia: { x: 0.6, y: 0.43 }, r_tibia: { x: 0.6, y: 0.57 }, l_humerus: { x: 0.31, y: 0.36 }, r_humerus: { x: 0.31, y: 0.64 }, access: { x: 0.6, y: 0.57 },
    tq: { x: 0.32, y: 0.5 }, site: { x: 0.52, y: 0.5 },
  };
  function previewAnchors() {
    const data = {};
    Object.keys(PREV).forEach(k => { data[k] = { x: PREV[k].x, y: PREV[k].y, visible: true, d: 1.5 }; });
    window.postMessage({ app: APP, action: 'anchors', data }, '*');
  }
  function drawScene() {
    const cv = ui.scene;
    const w = W(), h = H();
    if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; ui.sceneBg = null; }
    const c = cv.getContext('2d');
    const s = h / 1080;
    if (!ui.sceneBg) {
      // static layer: asphalt, kerb, patient, kit (drawn once)
      const bg = document.createElement('canvas'); bg.width = w; bg.height = h;
      const g = bg.getContext('2d');
      const base = g.createLinearGradient(0, 0, w, h); base.addColorStop(0, '#3d3f41'); base.addColorStop(1, '#2c2e30');
      g.fillStyle = base; g.fillRect(0, 0, w, h);
      for (let i = 0; i < 42000; i++) { const v = 34 + Math.random() * 70; g.fillStyle = `rgba(${v},${v},${v + 3},${0.35 + Math.random() * 0.4})`; const r = 1 + Math.random() * 2.6; g.fillRect(Math.random() * w, Math.random() * h, r, r); }
      // kerb + lane line
      g.fillStyle = '#56585a'; g.fillRect(0, h * 0.9, w, h * 0.1); g.fillStyle = 'rgba(0,0,0,.35)'; g.fillRect(0, h * 0.9, w, 6 * s);
      g.fillStyle = 'rgba(230,200,60,.55)'; for (let x = 0; x < w; x += 160 * s) g.fillRect(x, h * 0.06, 90 * s, 10 * s);
      const rr = (x, y, ww, hh, r, col) => { g.fillStyle = col; rrPath(g, x, y, ww, hh, r); g.fill(); };
      const shade = (x, y, ww, hh, r, c1, c2) => { const gr = g.createLinearGradient(0, y, 0, y + hh); gr.addColorStop(0, c1); gr.addColorStop(1, c2); rr(x, y, ww, hh, r, gr); };
      g.save(); g.shadowColor = 'rgba(0,0,0,.6)'; g.shadowBlur = 34 * s; g.shadowOffsetY = 10 * s;
      // legs
      shade(0.5 * w, 0.405 * h, 0.3 * w, 0.075 * h, 30 * s, '#2b3446', '#1b2230'); shade(0.5 * w, 0.52 * h, 0.3 * w, 0.075 * h, 30 * s, '#2b3446', '#1b2230');
      shade(0.79 * w, 0.398 * h, 0.04 * w, 0.088 * h, 18 * s, '#222', '#090909'); shade(0.79 * w, 0.513 * h, 0.04 * w, 0.088 * h, 18 * s, '#222', '#090909');
      // arms
      shade(0.27 * w, 0.31 * h, 0.2 * w, 0.06 * h, 26 * s, '#34405a', '#232c3e'); shade(0.27 * w, 0.63 * h, 0.2 * w, 0.06 * h, 26 * s, '#34405a', '#232c3e');
      shade(0.45 * w, 0.315 * h, 0.04 * w, 0.05 * h, 20 * s, '#d4a587', '#a77a5e'); shade(0.45 * w, 0.635 * h, 0.04 * w, 0.05 * h, 20 * s, '#d4a587', '#a77a5e');
      // torso + pelvis + head
      shade(0.22 * w, 0.355 * h, 0.3 * w, 0.29 * h, 70 * s, '#34405a', '#222a3a');
      shade(0.41 * w, 0.37 * h, 0.12 * w, 0.26 * h, 40 * s, '#2b3446', '#1b2230');
      g.fillStyle = '#c99b7d'; g.beginPath(); g.ellipse(0.17 * w, 0.5 * h, 0.05 * w, 0.075 * h, 0, 0, Math.PI * 2); g.fill();
      g.fillStyle = '#2b1f18'; g.beginPath(); g.ellipse(0.155 * w, 0.5 * h, 0.035 * w, 0.07 * h, 0, 0, Math.PI * 2); g.fill();
      g.restore();
      // shirt seam, buttons, belt
      g.fillStyle = 'rgba(0,0,0,.25)'; g.fillRect(0.3 * w, 0.497 * h, 0.11 * w, 2 * s);
      rr(0.445 * w, 0.37 * h, 0.012 * w, 0.26 * h, 4 * s, '#111'); rr(0.441 * w, 0.48 * h, 0.02 * w, 0.04 * h, 4 * s, '#9aa0a4');
      // blood pool
      const bp = g.createRadialGradient(0.5 * w, 0.66 * h, 4, 0.5 * w, 0.66 * h, 0.07 * w); bp.addColorStop(0, 'rgba(110,8,14,.8)'); bp.addColorStop(1, 'rgba(70,6,10,0)');
      g.fillStyle = bp; g.beginPath(); g.ellipse(0.5 * w, 0.665 * h, 0.075 * w, 0.035 * h, 0.2, 0, Math.PI * 2); g.fill();
      // kit case (open) + sharps bin
      const k = { x: PREV.kit.x * w, y: PREV.kit.y * h };
      g.save(); g.shadowColor = 'rgba(0,0,0,.6)'; g.shadowBlur = 26 * s; g.shadowOffsetY = 8 * s;
      shade(k.x - 160 * s, k.y - 128 * s, 320 * s, 126 * s, 16 * s, '#3a4246', '#2a3033'); shade(k.x - 160 * s, k.y, 320 * s, 156 * s, 16 * s, '#3c4448', '#2b3134');
      g.restore();
      rr(k.x - 146 * s, k.y + 14 * s, 292 * s, 128 * s, 12 * s, '#1a1f22');
      rr(k.x - 146 * s, k.y - 116 * s, 292 * s, 102 * s, 12 * s, '#22282b');
      // foam cut-outs + tools
      rr(k.x - 132 * s, k.y + 28 * s, 74 * s, 100 * s, 10 * s, '#11161a');
      rr(k.x - 124 * s, k.y + 36 * s, 58 * s, 84 * s, 6 * s, '#1f3a40'); g.fillStyle = 'rgba(15,212,196,.5)'; g.fillRect(k.x - 124 * s, k.y + 70 * s, 58 * s, 8 * s);
      rr(k.x - 40 * s, k.y + 34 * s, 72 * s, 30 * s, 12 * s, '#11161a'); rr(k.x - 34 * s, k.y + 38 * s, 58 * s, 22 * s, 9 * s, '#47525a'); rr(k.x + 14 * s, k.y + 42 * s, 22 * s, 14 * s, 4 * s, '#0fd4c4');
      [0, 26, 52].forEach(o => { rr(k.x + 48 * s, k.y + (32 + o) * s, 84 * s, 16 * s, 8 * s, '#11161a'); rr(k.x + 52 * s, k.y + (35 + o) * s, 68 * s, 10 * s, 5 * s, '#dfe5e8'); rr(k.x + 104 * s, k.y + (35 + o) * s, 16 * s, 10 * s, 3 * s, ['#e5a50a', '#9b6bff', '#3fd0ff'][o / 26]); });
      rr(k.x - 34 * s, k.y + 80 * s, 64 * s, 46 * s, 8 * s, '#11161a'); rr(k.x - 28 * s, k.y + 86 * s, 52 * s, 34 * s, 5 * s, '#f3f3ee');
      g.fillStyle = 'rgba(0,0,0,.4)'; g.fillRect(k.x - 22 * s, k.y + 94 * s, 40 * s, 3 * s); g.fillRect(k.x - 22 * s, k.y + 102 * s, 30 * s, 3 * s);
      // lid pockets
      rr(k.x - 132 * s, k.y - 104 * s, 130 * s, 78 * s, 8 * s, '#2c3337'); rr(k.x + 8 * s, k.y - 104 * s, 124 * s, 78 * s, 8 * s, '#2c3337');
      g.strokeStyle = 'rgba(255,255,255,.08)'; g.lineWidth = 2 * s; g.strokeRect(k.x - 126 * s, k.y - 98 * s, 118 * s, 66 * s);
      g.fillStyle = '#0fd4c4'; g.fillRect(k.x - 66 * s, k.y + 150 * s, 26 * s, 6 * s); g.fillRect(k.x + 40 * s, k.y + 150 * s, 26 * s, 6 * s);
      // sharps bin
      g.save(); g.shadowColor = 'rgba(0,0,0,.6)'; g.shadowBlur = 18 * s; g.shadowOffsetY = 6 * s;
      shade(k.x + 196 * s, k.y - 12 * s, 76 * s, 96 * s, 10 * s, '#f0cd45', '#c9a82a'); shade(k.x + 192 * s, k.y - 20 * s, 84 * s, 28 * s, 9 * s, '#e88a30', '#c86e1c');
      g.restore();
      g.fillStyle = 'rgba(0,0,0,.6)'; g.beginPath(); g.arc(k.x + 234 * s, k.y + 34 * s, 12 * s, 0, Math.PI * 2); g.fill();
      ui.sceneBg = bg;
    }
    c.drawImage(ui.sceneBg, 0, 0);
    const P = key => ({ x: PREV[key].x * w, y: PREV[key].y * h });
    const rr = (x, y, ww, hh, r, col) => { c.fillStyle = col; rrPath(c, x, y, ww, hh, r); c.fill(); };
    if ((S.proc && S.proc !== 'binder') || (S.b && (S.b.phase === 'done' || S.b.phase === 'strap'))) {
      c.save(); c.shadowColor = 'rgba(0,0,0,.5)'; c.shadowBlur = 16 * s;
      rr(0.425 * w, 0.355 * h, 0.085 * w, 0.29 * h, 14 * s, '#22333a'); c.restore();
      c.fillStyle = 'rgba(255,255,255,.07)'; for (let i = 0; i < 8; i++) c.fillRect(0.43 * w, (0.37 + i * 0.033) * h, 0.075 * w, 2 * s);
      rr(0.458 * w, 0.475 * h, 0.018 * w, 0.05 * h, 4 * s, '#0b0d0e'); c.fillStyle = '#0fd4c4'; c.fillRect(0.462 * w, 0.49 * h, 0.01 * w, 0.02 * h);
    }
    if (S.io && S.io.phase !== 'site' && S.io.phase !== 'drill' && S.io.site) {
      const p = P(S.io.site);
      rr(p.x - 10 * s, p.y - 10 * s, 20 * s, 20 * s, 5 * s, '#e9eef0'); c.fillStyle = '#d33'; c.beginPath(); c.arc(p.x, p.y, 4 * s, 0, Math.PI * 2); c.fill();
    }
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
      ui.rack.style.display = 'none';
      ui.pp.set({ step: 1, total: S.total, title: S.mode === 'iv' ? L('t_iv', 'IV cannulation') : L('t_field', 'Field resuscitation'), text: L('starting', 'Laying out the kit…'), tools: [], steps: stepNames() });
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
      ui.view = null; ui.rack = null; ui.dev = null; ui.inf = null;
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
          ui.pp.flash('ok', `${o.msg || L('ok_generic', 'Done')}${o.score !== undefined ? ` · ${Math.round(o.score)}%` : ''}`, 0);
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
      popped() { if (S.proc !== 'resus') return; NZA.audio.alarm(2); ui.pp.flash('bad', L('popped', 'Clot broke loose! Bleeding is up again.'), 3200); if (S.rs) S.rs.popped += 1; },
      focus(d) { if (d && d.what) { S.focus = d.what; renderFocus(); } },
      summary(s) { if (S.proc !== 'reassess') setStep('reassess', 'run', {}); H_.reassess.show(s || {}); },
      bags(b) { if (!b || !S.rs) return; if (b.counts) S.rs.counts = b.counts; if (b.bags) S.data.bags = b.bags; H_.resus.tools(); },
      drill(d) { if (d && d.flash && ui.pp) ui.pp.flash(d.type || 'warn', d.flash); },
    },
    preview() {
      S.preview = true;
      ui.scene = document.createElement('canvas'); ui.scene.className = 'fd-scene';
      document.body.appendChild(ui.scene);
      const plan = { band: [60, 70], bleed: 88, injury: { region: 'pelvis', regionLabel: 'Pelvis', type: 'internal' } };
      NZA.open(APP, { mode: 'resus', plan, keys: { drill: 'Space', squeeze: 'Space', clampDown: 'KeyQ', clampUp: 'KeyE', insert: 'Space', advance: 'KeyE', focus: 'Tab' } });
      previewAnchors();
      NZA.demo('monitor', { name: 'Pavel Lindqvist', nibpAuto: 30, nibpTime: 2.5 });
      const vit = { hr: 128, ecgRate: 128, spo2: 95, sys: 84, dia: 45, map: 58, rr: 22, temp: 35.6, etco2: 33, rhythm: 'stach', state: 'wounded' };
      NZA.apps[APP].msg.vitals({ map: 58, hr: 128, spo2: 95 });
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
        injury: { region: 'pelvis', regionLabel: 'Pelvis' }, bleed: 88 };
      if (which === 'binder') { setStep('binder', 'run', { indicated: true, why: 'fracture', band: [60, 80], count: 1, injury: { regionLabel: 'Pelvis' }, bleed: 196 }); if (sub === 'strap') { S.b.phase = 'strap'; clearMarks(); H_.binder.ui(); S.b.tension = 72; S.b.drag = true; S.b.tab = null; const A = apx('strapA'), B = apx('strapB'); if (A && B) S.b.tab = { x: A.x + (B.x - A.x) * 0.72, y: A.y + (B.y - A.y) * 0.72 }; H_.binder.devTick(); } }
      if (which === 'site') setStep('io', 'run', ioData);
      if (which === 'drill') { setStep('io', 'run', ioData); H_.io.pick('r_tibia'); const p = apx('r_tibia'); S.mouse.x = p.x + 30; S.mouse.y = p.y - 26; S.mouse.down = true; S.io.lift = 0; S.io.depth = 7.8; S.io.drilling = false; S.io.torque = Array.from({ length: 80 }, (_, i) => (i < 30 ? 0.25 : 0.88) + (Math.random() - 0.5) * 0.1); }
      if (which === 'confirm') { setStep('io', 'run', ioData); H_.io.pick('r_tibia'); S.io.depth = 11.2; H_.io.confirmUi(); S.io.syr.set(1.4); S.io.syr.fluid('marrow'); setRow('.r-ret', `${icon('drop')}${esc(L('ret_marrow', 'Marrow'))}`, 'red'); ui.pp.flash('ok', L('confirm_ok', 'Dark return in the barrel — you are in the marrow.'), 0); }
      if (which === 'flush') { setStep('io', 'run', ioData); H_.io.pick('r_tibia'); S.io.aspirated = true; H_.io.flushUi(); S.io.ext = true; H_.io.useSyringe('lido'); S.io.syr.set(5 - 0.8); S.io.lido.ml = 0.8; H_.io.flushText(); }
      if (which === 'resus') {
        setStep('resus', 'run', { band: [60, 70], hold: 24, lowMap: 52, autoContinue: 1.6, access: { kind: 'io', site: 'r_lower_leg', siteLabel: 'Right tibia' }, maxRate: 66, txaPush: 10,
          infusion: { gravity: 60, ioFactor: 0.45, pressureGain: 1.4, maxPressure: 300, leak: 6, pump: 22, maxBags: 3, dilution: 1000 },
          counts: { saline: 2, txa: 1, foil: 1 }, blood: true, bags: [{ serial: 'BB-0042', type: 'O-', ml: 450, compatible: true }],
          infusions: [{ id: 'i1', kind: 'saline', ml: 500, left: 382, rate: 58, mine: true }, { id: 'i2', kind: 'blood', ml: 450, left: 301, rate: 24, mine: true, bag: { type: 'O−' } }], injury: { regionLabel: 'Pelvis' }, bleed: 19 });
        S.rs.pressure = 186; S.rs.clamp = 0.66; S.rs.salineIn = 0;
        const hist = [52, 53, 55, 57, 58, 60, 61, 62, 63, 64, 63, 64, 65, 64, 63, 63, 64, 62, 63, 64, 65, 66, 64, 63];
        hist.forEach((m, i) => { S.clot = { map: m, firm: Math.min(93, i * 4.3), state: 'band', eta: 8, pops: 0, mods: { txa: false, cold: true, foil: false, dil: 12 }, bleed: 19 }; H_.resus.clotTick(); });
        if (sub === 'txa') H_.resus.txaStart();
      }
      if (which === 'reassess') {
        setStep('reassess', 'run', {});
        H_.reassess.show({ before: { bleed: 196, map: 52, hr: 136, spo2: 93 }, after: { bleed: 11.4, map: 64, hr: 118, spo2: 97 }, grade: 'A',
          steps: [{ label: 'Pelvic binder', grade: 'A', score: 88, note: 'strap 68%' }, { label: 'IO access · right tibia', grade: 'B', score: 74, note: '1 needle' }, { label: 'Hold the pressure', grade: 'S', score: 94, note: 'no breaks' }],
          devices: ['Binder', 'IO R tibia', 'Saline 380 ml', 'TXA 1 g', 'Clot 100%'] });
      }
      if (which === 'iv') {
        NZA.close('monitor');
        NZA.open(APP, { mode: 'iv', plan: {}, keys: S.keys });
        previewAnchors();
        setStep('iv', 'run', { site: 'r_lower_arm', siteLabel: 'Right forearm', angle: [15, 30], attempts: 2, gauge: 18, tourniquetFill: 3, flash: 0.9, responsive: true, name: 'Pavel Lindqvist',
          map: { veins: [{ y: 0.28, bend: 0.04, width: 0.7, depth: 3.5 }, { y: 0.52, bend: 0.01, width: 1.15, depth: 3 }, { y: 0.76, bend: -0.06, width: 0.65, depth: 5 }], best: 1, spot: 0.5 } });
        if (sub === 'find') { S.iv.tq = true; S.iv.fill = 1; H_.iv.go('find'); H_.iv.palpate({ x: 150, y: 80 }); S.iv.palp = false; }
        if (sub === 'insert') { S.iv.tq = true; S.iv.fill = 1; S.iv.mark = { x: 150, y: 78 }; S.iv.palpQ = 0.85; S.iv.vein = S.data.map.veins[1]; H_.iv.go('insert'); S.iv.angle = 22; S.iv.tip = 58; }
      }
    },
  });
})();
