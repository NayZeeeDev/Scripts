/* ═══════════════════════════════════════════════════════════
   THE WASH — NUI (NAYZEEE UI v3)
   ═══════════════════════════════════════════════════════════ */
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nz_moneywash';
const $stage = document.getElementById('stage');
const $toasts = document.getElementById('toasts');

let theme = { brand: 'THE WASH', subtitle: 'Off-book operations', version: 'v1.0.0' };
let labels = {};
let cur = null;          // active panel controller
let clockOffset = 0;     // server unix - local unix

/* ─────────────── utils ─────────────── */
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Math.floor(n || 0).toLocaleString('en-US');
const pct = (n, d = 0) => (n * 100).toFixed(d) + '%';
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const nowS = () => Date.now() / 1000 + clockOffset;
const fmtT = (s) => { s = Math.max(0, Math.floor(s)); return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); };
const initials = (name) => String(name || '?').split(/\s+/).map((p) => p[0] || '').join('').slice(0, 2).toUpperCase();
const syncClock = (serverNow) => { if (serverNow) clockOffset = serverNow - Date.now() / 1000; };

function post(name, body) {
  return fetch(`https://${RES}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body || {}),
  }).then((r) => r.json()).catch(() => null);
}
const request = (name, ...args) => post('request', { name, args });

function hexToRgba(hex, a) {
  const h = hex.replace('#', '');
  const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

function applyTheme(t) {
  theme = Object.assign(theme, t || {});
  const r = document.documentElement.style;
  if (t.teal) { r.setProperty('--teal', t.teal); r.setProperty('--teal-wash', hexToRgba(t.teal, 0.11)); r.setProperty('--teal-edge', hexToRgba(t.teal, 0.34)); }
  if (t.tealHi) r.setProperty('--teal-hi', t.tealHi);
  if (t.tealLo) r.setProperty('--teal-lo', t.tealLo);
  if (t.red) { r.setProperty('--red', t.red); r.setProperty('--red-wash', hexToRgba(t.red, 0.11)); r.setProperty('--red-edge', hexToRgba(t.red, 0.34)); }
  if (t.redLo) r.setProperty('--red-lo', t.redLo);
  if (t.amber) { r.setProperty('--amber', t.amber); r.setProperty('--amber-wash', hexToRgba(t.amber, 0.11)); r.setProperty('--amber-edge', hexToRgba(t.amber, 0.34)); }
  if (t.font) r.setProperty('--font', `'${t.font}'`);
}

/* ─────────────── icons ─────────────── */
const I = {
  check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
  info: '<path d="M12 8v5M12 16.5v.01"/><circle cx="12" cy="12" r="9"/>',
  alert: '<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
  cash: '<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.6"/><path d="M6 9.5v5M18 9.5v5"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  drop: '<path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z"/>',
  flame: '<path d="M12 3c1 4 5 5.5 5 10a5 5 0 0 1-10 0c0-2.5 1.5-4 2.5-5 .3 1.6 1 2.6 2 3 0-3-.5-5.5.5-8z"/>',
  shield: '<path d="M12 3 4.5 6v6c0 4.5 3.2 7.8 7.5 9 4.3-1.2 7.5-4.5 7.5-9V6L12 3z"/>',
  book: '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5v-15z"/><path d="M4 20.5A2.5 2.5 0 0 1 6.5 18H20v3H6.5"/>',
  bank: '<path d="M3 10h18L12 4 3 10zM5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18"/>',
  chart: '<path d="M4 17h2l1.5-6L10 19l2.5-14L15 15l1.5-4H20"/>',
  gauge: '<path d="M4 16a8 8 0 1 1 16 0"/><path d="M12 16l4-5"/>',
  scan: '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M4 12h16"/>',
  users: '<circle cx="9" cy="8" r="3.2"/><path d="M3 20a6 6 0 0 1 12 0"/><path d="M16 4.5a3.2 3.2 0 0 1 0 6.3M18 14a6 6 0 0 1 3 6"/>',
  spin: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>',
  wrench: '<path d="M14.7 6.3a4 4 0 0 0 5 5L12 19a2.1 2.1 0 0 1-3-3l7.6-7.6"/><path d="M14.7 6.3 17 4l3 3-2.3 2.3"/>',
  box: '<path d="M3.5 7.5 12 3l8.5 4.5v9L12 21l-8.5-4.5v-9z"/><path d="M3.5 7.5 12 12l8.5-4.5M12 12v9"/>',
  doc: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
  scissors: '<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><path d="M8 7.5 20 18M8 16.5 20 6"/>',
  layers: '<path d="m12 3 9 5-9 5-9-5 9-5z"/><path d="m3 13 9 5 9-5"/>',
  mix: '<path d="M4 6h16M7 12h10M10 18h4"/>',
};
const svg = (n) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${I[n] || ''}</svg>`;

/* ─────────────── building blocks ─────────────── */
function shell(o) {
  const keys = (o.keys || [['ESC', 'Close']]).map((k) => `<span><span class="key">${k[0]}</span>${k[1]}</span>`).join('');
  return `<div class="frame enter" style="width:${o.width}px">
    <div class="shell"${o.height ? ` style="height:${o.height}px"` : ''}>
      <div class="bar">
        <div class="bar-brand${o.side ? '' : ' auto'}"><div class="mark"></div>
          <div class="bar-name"><div class="title-txt">${esc(theme.brand)}</div><div class="sub">${esc(o.sub || theme.subtitle)}</div></div></div>
        <div class="bar-mid"><span class="dot ${o.dot || ''}"></span><p>${o.status || ''}</p><span class="ver">${esc(theme.version)}</span></div>
        <button class="pill-close" data-act="close">Close</button>
      </div>
      <div class="body${o.side ? '' : ' single'}">
        ${o.side ? `<nav class="side">${o.side}</nav>` : ''}
        <main class="main${o.tight ? ' tight' : ''}" id="main">${o.main}</main>
      </div>
      <div class="statusbar">${keys}<span class="push">${o.right || ''}</span></div>
    </div></div>`;
}

const head = (title, sub, right = '') => `<div class="head"><div><h1>${title}</h1>${sub ? `<p>${sub}</p>` : ''}</div>${right}</div>`;
const clockBox = (big, small) => `<div class="clock"><b>${big}</b><span>${small}</span></div>`;
const stat = (icon, label, value, tone = '', id = '') =>
  `<div class="stat"><div class="tile ${tone}">${svg(icon)}</div><div class="stat-txt"><span>${label}</span><b${id ? ` id="${id}"` : ''}>${value}</b></div></div>`;
const meter = (v, tone = '') => `<div class="meter ${tone}"><i style="width:${clamp(v, 0, 1) * 100}%"></i></div>`;
const heatTone = (h) => (h >= 60 ? 'hot' : h >= 25 ? 'warm' : 'live');
const heatChip = (h) => (h >= 60 ? 'red' : h >= 25 ? 'amber' : '');
const empty = (icon, title, text) => `<div class="empty">${svg(icon)}<b>${title}</b><span>${text}</span></div>`;
const setRange = (el) => { if (!el) return; const p = ((el.value - el.min) / ((el.max - el.min) || 1)) * 100; el.style.setProperty('--p', p + '%'); };
const stageName = (s) => ['Loaded', 'Washed', 'Re-serialised', 'Banded'][s] || 'Stage ' + s;

/* ─────────────── panel host ─────────────── */
function open(panel, data) {
  const C = Panels[panel];
  if (!C) return finish(null);
  cur = Object.assign(Object.create(C), { panel, data, st: {} });
  if (cur.init) cur.init();
  $stage.classList.add('on');
  draw();
}

function draw() {
  if (!cur) return;
  $stage.innerHTML = cur.render();
  $stage.querySelectorAll('input[type=range]').forEach(setRange);
  if (cur.after) cur.after();
}

function teardown() {
  if (cur && cur.destroy) cur.destroy();
  cur = null;
  $stage.innerHTML = '';
  $stage.classList.remove('on');
}

function finish(result) {
  teardown();
  post('result', { result });
}

$stage.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (!el || !cur) return;
  if (el.dataset.act === 'close') return finish(null);
  if (cur.on) cur.on(el.dataset.act, el, e);
});
$stage.addEventListener('input', (e) => {
  if (e.target.type === 'range') setRange(e.target);
  if (cur && cur.input) cur.input(e.target, e);
});
document.addEventListener('keydown', (e) => {
  if (!cur) return;
  if (e.key === 'Escape') { e.preventDefault(); return finish(null); }
  if (cur.key) cur.key(e);
});

// live countdowns: any element with data-until="unix"
setInterval(() => {
  document.querySelectorAll('[data-until]').forEach((el) => { el.textContent = fmtT(Number(el.dataset.until) - nowS()); });
}, 1000);

/* ═══════════════════════════════════════════════════════════
   PANELS
   ═══════════════════════════════════════════════════════════ */
const Panels = {};

/* ─────────────── LOAD THE DRUM ─────────────── */
Panels.load = {
  init() {
    const d = this.data;
    this.st.src = 0;
    this.st.amount = this.maxFor(0);
  },
  maxFor(i) { const s = this.data.sources[i]; return Math.max(0, Math.min(this.data.max, s ? s.total : 0)); },
  cycle(a) { const d = this.data; return d.baseTime + (a / 1000) * d.perThousand; },
  render() {
    const d = this.data, st = this.st;
    const src = d.sources[st.src];
    const max = this.maxFor(st.src);
    const ok = max >= d.min;
    const rows = d.sources.map((s, i) => `
      <div class="row pick${i === st.src ? ' sel' : ''}" data-act="src" data-i="${i}">
        <div class="av">${esc(initials(s.label))}</div>
        <div class="row-txt"><b>${esc(s.label)}</b><span>Trace at birth ~${s.heat}</span></div>
        <div class="row-end"><b>${money(s.total)}</b><span>on you</span></div>
      </div>`).join('');
    const main = `
      ${head('Load the drum', `Feeding <b style="color:var(--white);font-weight:500">${esc(d.station)}</b>${d.op ? ' · ' + esc(d.op) : ''}. Bigger loads run longer and draw more attention.`,
        clockBox(d.rate ? pct(d.rate) : '—', 'street wash rate'))}
      <div class="stats">
        ${stat('cash', 'Load', money(st.amount), '', 'l-amount')}
        ${stat('clock', 'Est. cycle (med spin)', fmtT(this.cycle(st.amount)), '', 'l-cycle')}
        ${stat('bank', 'Rough clean value', money(st.amount * (d.rate || 0.75)), '', 'l-value')}
      </div>
      <div class="cols even">
        <section class="panel"><div class="p-head"><div><h2>Dirty money</h2><p>What you're carrying</p></div></div>
          <div class="p-body">${rows}</div></section>
        <section class="panel"><div class="p-head"><div><h2>Amount</h2><p>${money(d.min)} – ${money(d.max)} per load</p></div></div>
          <div class="p-body pad" style="gap:14px">
            <div class="field"><label>Load size <b id="l-amt2">${money(st.amount)}</b></label>
              <input type="range" id="l-range" min="${Math.min(d.min, max)}" max="${Math.max(max, d.min)}" step="100" value="${st.amount}" ${ok ? '' : 'disabled'}></div>
            <div class="field"><label>Exact</label><input type="number" id="l-num" value="${st.amount}" min="${d.min}" max="${max}" ${ok ? '' : 'disabled'}></div>
            <div class="chips">
              <button class="chip-btn" data-act="q" data-q=".25">25%</button><button class="chip-btn" data-act="q" data-q=".5">50%</button>
              <button class="chip-btn" data-act="q" data-q=".75">75%</button><button class="chip-btn" data-act="q" data-q="1">Max</button>
            </div>
            <div>
              <div class="kv"><span>Your stash</span><b>${money(src ? src.total : 0)}</b></div>
              <div class="kv"><span>Machine wear</span><b>${Math.floor(d.wear || 0)}%</b></div>
            </div>
          </div></section>
      </div>
      <div class="actions"><span class="note">${ok ? 'The cash goes in the drum the moment you confirm.' : `You need at least ${money(d.min)} of this cash.`}</span>
        <button class="btn-line" data-act="close">Cancel</button>
        <button class="btn-teal" data-act="go" ${ok ? '' : 'disabled'}>Load the drum</button></div>`;
    return shell({ width: 980, main, status: `<b>${esc(d.station)}</b> · door open`, keys: [['ESC', 'Cancel'], ['↵', 'Load']] });
  },
  sync() {
    const st = this.st;
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
    set('l-amount', money(st.amount)); set('l-amt2', money(st.amount));
    set('l-cycle', fmtT(this.cycle(st.amount))); set('l-value', money(st.amount * (this.data.rate || 0.75)));
    const r = document.getElementById('l-range'); if (r && Number(r.value) !== st.amount) { r.value = st.amount; setRange(r); }
    const n = document.getElementById('l-num'); if (n && document.activeElement !== n) n.value = st.amount;
  },
  setAmount(v) { this.st.amount = clamp(Math.floor(v || 0), Math.min(this.data.min, this.maxFor(this.st.src)), this.maxFor(this.st.src)); this.sync(); },
  input(el) {
    if (el.id === 'l-range') this.setAmount(Number(el.value));
    if (el.id === 'l-num') { const v = Number(el.value); if (v >= this.data.min) this.setAmount(v); }
  },
  on(act, el) {
    if (act === 'src') { this.st.src = Number(el.dataset.i); this.st.amount = this.maxFor(this.st.src); draw(); }
    if (act === 'q') this.setAmount(Math.max(this.data.min, this.maxFor(this.st.src) * Number(el.dataset.q)));
    if (act === 'go') this.submit();
  },
  key(e) { if (e.key === 'Enter') this.submit(); },
  submit() {
    const src = this.data.sources[this.st.src];
    if (!src || this.st.amount < this.data.min || this.st.amount > this.maxFor(this.st.src)) return;
    finish({ source: src.key, amount: this.st.amount });
  },
};

/* ─────────────── PROGRAM THE CYCLE (washer control panel) ─────────────── */
const TEMP_ORDER = { cold: 1, warm: 2, hot: 3 };
Panels.program = {
  init() {
    syncClock(this.data.serverNow);
    Object.assign(this.st, { temp: 'warm', spin: 'med', solvent: false });
  },
  band(dye) { return this.data.dyeBands.find((b) => dye <= b.max) || this.data.dyeBands[this.data.dyeBands.length - 1]; },
  predict() {
    const d = this.data, st = this.st, b = d.batch;
    const dye = st.solvent ? Math.floor(b.dye / 2) : b.dye;
    const ideal = this.band(dye).ideal;
    const diff = Math.abs(TEMP_ORDER[ideal] - TEMP_ORDER[st.temp]);
    const pen = diff === 0 ? 0 : diff === 1 ? d.penalty.one : d.penalty.two;
    const q = (st.solvent ? d.solventBonus : 0) - pen;
    const spin = d.spins[st.spin];
    const alert = clamp((d.alert.base + b.heat * d.alert.perHeat) * spin.noise, 0, 1);
    const heatAfter = clamp(b.heat - d.heatDrop - (d.temps[st.temp].heatBonus || 0), 0, 100);
    return { q, time: spin.time, jam: spin.jam / 100, alert, heatAfter };
  },
  render() {
    const d = this.data, st = this.st, b = d.batch, p = this.predict();
    const suits = {};
    d.dyeBands.forEach((x) => { suits[x.ideal] = x.label; });
    const temp = ['cold', 'warm', 'hot'].map((k) => `<button class="${st.temp === k ? 'on' : ''}" data-act="temp" data-k="${k}">
      <b>${esc(d.temps[k].label)}</b><span>Suits: ${esc(suits[k] || '—')}<br>Heat −${d.heatDrop + (d.temps[k].heatBonus || 0)}</span></button>`).join('');
    const spin = ['low', 'med', 'high'].map((k) => `<button class="${st.spin === k ? 'on' : ''}" data-act="spin" data-k="${k}">
      <b>${k === 'low' ? 'Low' : k === 'med' ? 'Medium' : 'High'}</b><span>${fmtT(d.spins[k].time)} · jam ${d.spins[k].jam}%<br>Noise ×${d.spins[k].noise}</span></button>`).join('');
    const qTone = p.q < -0.001 ? 'red' : '';
    const main = `
      ${head('Program the cycle', 'Read the bills, then pick a program. Wrong temperature ruins notes; a fast spin is loud and jams more.',
        clockBox(money(b.amount), esc(b.serial)))}
      <div class="cols">
        <section class="panel"><div class="p-head"><div><h2>Batch</h2><p>${esc(b.source)}</p></div><span class="chip ${heatChip(b.heat)}">${esc(b.serial)}</span></div>
          <div class="p-body pad" style="gap:12px">
            <div>
              <div class="kv"><span>Bills look</span><span class="tag ${b.dyeKey === 'heavy' ? 'hot' : b.dyeKey === 'medium' ? 'warm' : 'live'}">${esc(b.dyeLabel)}</span></div>
              <div class="kv"><span>Load</span><b>${money(b.amount)}</b></div>
              <div class="kv"><span>Quality now</span><b>${pct(b.quality)}</b></div>
              <div class="kv"><span>Heat</span><b>${b.heat}</b></div>
            </div>
            ${meter(b.heat / 100, b.heat >= 60 ? 'red' : b.heat >= 25 ? 'amber' : '')}
            <div class="kv"><span>Machine wear</span><b>${Math.floor(d.wear)}%</b></div>
            ${meter(d.wear / 100, d.wear >= 60 ? 'red' : '')}
          </div></section>
        <section class="panel"><div class="p-head"><div><h2>Program</h2><p>WIWANG 69 Express · industrial</p></div></div>
          <div class="p-body pad" style="gap:14px">
            <div><div class="sec-label">Temperature</div><div class="seg">${temp}</div></div>
            <div><div class="sec-label">Spin</div><div class="seg">${spin}</div></div>
            <div class="sw-line"><span>Dye solvent<small>${d.solvent > 0 ? `${d.solvent} in your bag · halves the dye, +${pct(d.solventBonus)} quality` : 'You have none'}</small></span>
              <span class="sw ${st.solvent ? 'on' : ''} ${d.solvent > 0 ? '' : 'dis'}" data-act="solvent"><i></i></span></div>
          </div></section>
      </div>
      <div class="stats four">
        ${stat('clock', 'Cycle', fmtT(p.time))}
        ${stat('wrench', 'Jam risk', pct(p.jam, 1), p.jam > 0.25 ? 'red' : '')}
        ${stat('alert', '911 call risk', pct(p.alert, 1), p.alert > 0.3 ? 'red' : p.alert > 0.15 ? 'amber' : '')}
        ${stat('drop', 'Quality impact', (p.q >= 0 ? '+' : '') + pct(p.q, 1), qTone)}
      </div>
      <div class="actions"><span class="note">Heat after wash: <b style="color:var(--white)">${p.heatAfter}</b></span>
        <button class="btn-line" data-act="close">Cancel</button><button class="btn-teal" data-act="go">Start cycle</button></div>`;
    return shell({ width: 1060, main, status: `<b>${esc(d.station)}</b> · door closed · drum loaded`, keys: [['ESC', 'Cancel'], ['↵', 'Start']] });
  },
  on(act, el) {
    if (act === 'temp') { this.st.temp = el.dataset.k; draw(); }
    if (act === 'spin') { this.st.spin = el.dataset.k; draw(); }
    if (act === 'solvent' && this.data.solvent > 0) { this.st.solvent = !this.st.solvent; draw(); }
    if (act === 'go') finish({ temp: this.st.temp, spin: this.st.spin, solvent: this.st.solvent });
  },
  key(e) { if (e.key === 'Enter') finish({ temp: this.st.temp, spin: this.st.spin, solvent: this.st.solvent }); },
};

/* ─────────────── TIMING (guillotine cuts / jam release) ─────────────── */
Panels.timing = {
  init() {
    const d = this.data;
    Object.assign(this.st, { r: 0, results: [], pos: 0, dir: 1, locked: false, verdict: '' });
    this.rounds = d.rounds || 1;
    this.newZone();
    this.last = performance.now();
    this.started = this.last;
    const loop = (t) => {
      if (cur !== this) return;
      const dt = Math.min(0.05, (t - this.last) / 1000);
      this.last = t;
      if (!this.st.locked) {
        this.st.pos += this.st.dir * dt * 0.85 * (d.speed || 1);
        if (this.st.pos >= 1) { this.st.pos = 1; this.st.dir = -1; }
        if (this.st.pos <= 0) { this.st.pos = 0; this.st.dir = 1; }
        const n = document.getElementById('t-needle');
        if (n) n.style.left = (this.st.pos * 100) + '%';
        if (t - this.started > 7000) this.strike();
      }
      this.raf = requestAnimationFrame(loop);
    };
    this.raf = requestAnimationFrame(loop);
  },
  destroy() { cancelAnimationFrame(this.raf); },
  newZone() {
    const w = clamp(this.data.zone || 0.18, 0.06, 0.5);
    this.st.zone = { s: 0.08 + Math.random() * (0.84 - w), w };
    this.started = performance.now();
  },
  render() {
    const d = this.data, st = this.st;
    const isCut = d.mode === 'cut';
    const total = isCut ? d.total : this.rounds;
    const done = isCut ? d.round - 1 : st.r;
    const pips = Array.from({ length: total }, (_, i) => {
      let c = '';
      if (isCut) { if (i < d.round - 1) c = 'good'; if (i === d.round - 1) c = st.results[0] || 'now'; }
      else c = st.results[i] || (i === st.r ? 'now' : '');
      return `<i class="${c}"></i>`;
    }).join('');
    const cuts = isCut ? Array.from({ length: d.round - 1 }, (_, i) => `<i style="left:${((i + 1) / (d.total + 1)) * 100}%"></i>`).join('') : '';
    const main = `
      ${head(isCut ? `Cut ${d.round} of ${d.total}` : 'Clear the jam',
        isCut ? 'Drop the blade when the needle crosses the guide. Dead centre is a perfect cut.' : 'Hit the release each time the needle crosses the gap. Miss once and you tear bills.',
        `<div class="pips">${pips}</div>`)}
      ${isCut ? `<div class="sheet-vis">${cuts}</div>` : ''}
      <div class="track" id="t-track"><div class="ticks"></div>
        <div class="zone" style="left:${st.zone.s * 100}%;width:${st.zone.w * 100}%"><i></i></div>
        <div class="needle" id="t-needle" style="left:${st.pos * 100}%"></div></div>
      <div class="actions"><span class="note verdict ${st.verdict}" id="t-verdict">${st.verdict ? st.verdict.toUpperCase() : `${done}/${total}`}</span>
        <button class="btn-teal" data-act="hit">${isCut ? 'Drop blade' : 'Release'}</button></div>`;
    return shell({ width: 620, tight: true, main, sub: isCut ? 'Guillotine' : 'Maintenance', status: isCut ? 'Blade armed' : '<b>Jammed</b> · drum stalled',
      dot: isCut ? '' : 'red', keys: [['SPACE', isCut ? 'Cut' : 'Release'], ['E', 'Strike'], ['ESC', 'Step away']] });
  },
  key(e) { if (e.code === 'Space' || e.key === 'e' || e.key === 'E') { e.preventDefault(); this.strike(); } },
  on(act) { if (act === 'hit') this.strike(); },
  strike() {
    const st = this.st;
    if (st.locked) return;
    st.locked = true;
    const z = st.zone, p = st.pos;
    let res = 'miss';
    if (p >= z.s && p <= z.s + z.w) res = (p >= z.s + z.w * 0.3 && p <= z.s + z.w * 0.7) ? 'perfect' : 'good';
    st.results.push(res);
    st.verdict = res;
    const track = document.getElementById('t-track');
    if (track) track.classList.add('hit-' + res);
    const v = document.getElementById('t-verdict');
    if (v) { v.className = 'note verdict ' + res; v.textContent = res.toUpperCase(); }
    setTimeout(() => {
      if (cur !== this) return;
      st.r += 1;
      if (st.r >= this.rounds) return finish(st.results);
      st.locked = false; st.verdict = '';
      this.newZone();
      draw();
    }, 520);
  },
};

/* ─────────────── INSPECT MACHINE ─────────────── */
Panels.inspect = {
  init() { syncClock(this.data.serverNow); },
  render() {
    const d = this.data;
    const stateTxt = { idle: 'Idle', open: 'Door open', loaded: 'Loaded', ready: 'Ready', running: 'Running', jammed: 'Jammed', done: 'Done', cutting: 'Cutting' }[d.state] || d.state;
    const b = d.batch;
    const main = `
      ${head(esc(d.label), [d.op, d.placed && d.owner ? 'Owner ' + d.owner : null].filter(Boolean).map(esc).join(' · ') || 'Machine diagnostics')}
      <div class="stats">
        ${stat('gauge', 'State', esc(stateTxt), d.state === 'jammed' ? 'red' : '')}
        ${stat('wrench', 'Wear', Math.floor(d.wear) + '%', d.wear >= 60 ? 'red' : d.wear >= 35 ? 'amber' : '')}
        ${stat('alert', 'Jam chance / run', d.jam + '%', d.jam >= 25 ? 'red' : '')}
      </div>
      ${d.state === 'running' && d.remaining != null ? `<div class="banner teal">${svg('spin')}<span>Cycle finishes in <b data-until="${nowS() + d.remaining}">${fmtT(d.remaining)}</b></span></div>` : ''}
      ${b ? `<article class="inc ${b.heat >= 60 ? 'urgent' : b.heat >= 25 ? 'amber' : ''}">
          <div class="inc-top"><span class="chip ${heatChip(b.heat)}">${esc(stageName(b.stage))}</span><span class="ref">${esc(b.serial)}</span></div>
          <h3>${money(b.amount)} · ${esc(b.source)}</h3>
          <p>${b.reserialized ? 'Serials re-printed — the paper trail is broken.' : 'Original serials still on the notes.'}</p>
          <div class="meta"><span>Heat <b>${b.heat}</b></span><span>Quality <b>${pct(b.quality)}</b></span><span>Bills <b>${esc(b.dyeLabel)}</b></span></div>
        </article>` : empty('box', 'Nothing inside', 'No batch is loaded in this machine right now.')}
      <div class="actions"><button class="btn-line" data-act="close">Close</button></div>`;
    return shell({ width: 680, tight: true, main, sub: 'Diagnostics', status: `<b>${esc(d.label)}</b> · ${esc(stateTxt)}`, dot: d.state === 'jammed' ? 'red' : '' });
  },
};

/* ─────────────── COOK THE BOOKS ─────────────── */
function suspicion(front, alloc, amount, declared, heat, flags, r) {
  let dev = 0;
  front.categories.forEach((c) => { dev += Math.abs((alloc[c.key] || 0) - c.share); });
  dev /= 2;
  const over = Math.max(0, (declared + amount) - front.dailyCap) / front.dailyCap;
  return clamp(dev * r.wDeviation + over * r.wOverCap + (heat / 100) * r.wHeat + flags * r.wRecentFlags, 0, 1);
}

Panels.books = {
  init() {
    const d = this.data;
    syncClock(d.now);
    d.batches = d.batches || [];
    d.pending = d.pending || [];
    this.st.view = 'declare';
    this.st.sel = new Set(d.batches.map((b) => b.id));
    this.st.alloc = {};
    d.front.categories.forEach((c) => { this.st.alloc[c.key] = Math.round(c.share * 100); });
    this.fixAlloc();
    this.st.mode = 'clearing';
    this.st.busy = false;
    this.st.receipt = null;
  },
  sealed() { return this.data.auditUntil && this.data.auditUntil > nowS(); },
  fixAlloc(keepKey) {
    const keys = this.data.front.categories.map((c) => c.key);
    let sum = keys.reduce((a, k) => a + this.st.alloc[k], 0);
    const fixKey = keys.filter((k) => k !== keepKey).pop() || keys[0];
    this.st.alloc[fixKey] = clamp(this.st.alloc[fixKey] + (100 - sum), 0, 100);
  },
  setAlloc(key, v) {
    const keys = this.data.front.categories.map((c) => c.key);
    const others = keys.filter((k) => k !== key);
    v = clamp(Math.round(v), 0, 100);
    const rest = 100 - v;
    const otherSum = others.reduce((a, k) => a + this.st.alloc[k], 0);
    this.st.alloc[key] = v;
    others.forEach((k) => { this.st.alloc[k] = otherSum > 0 ? Math.round((this.st.alloc[k] / otherSum) * rest) : Math.round(rest / others.length); });
    this.fixAlloc(key);
  },
  calc() {
    const d = this.data, st = this.st;
    const picked = d.batches.filter((b) => st.sel.has(b.id));
    const amount = picked.reduce((a, b) => a + b.amount, 0);
    const heat = amount > 0 ? picked.reduce((a, b) => a + b.heat * b.amount, 0) / amount : 0;
    let value = picked.reduce((a, b) => a + b.value, 0);
    if (st.mode === 'instant') value = Math.floor(value * (1 - d.rules.instantFee));
    const shares = {};
    Object.keys(st.alloc).forEach((k) => { shares[k] = st.alloc[k] / 100; });
    const s = amount > 0 ? suspicion(d.front, shares, amount, d.declared, heat, d.flags, d.rules) : 0;
    const audit = amount > 0 ? clamp(d.rules.auditBase + s * d.rules.auditScale, 0, 1) : 0;
    return { picked, amount, heat, value, s, audit };
  },
  side() {
    const d = this.data, st = this.st, m = d.market || {};
    const nav = (k, icon, label, tally) => `<button class="nav ${st.view === k ? 'on' : ''}" data-act="view" data-k="${k}">${svg(icon)}${label}${tally != null ? `<span class="tally">${tally}</span>` : ''}</button>`;
    return `
      <div class="who"><div class="av">${esc(initials(d.name))}</div><div class="who-txt"><b>${esc(d.name)}</b><span>Bookkeeper · ${esc(d.front.label)}</span></div></div>
      <div class="shift"><span>Wash rate</span><b class="${m.event && m.event.mod < 0 ? 'red' : ''}"><span class="dot ${m.event && m.event.mod < 0 ? 'red' : ''}"></span>${m.rate ? pct(m.rate) : '—'}</b></div>
      ${nav('declare', 'book', 'Declare revenue', d.batches.length)}
      <div class="grp">Money</div>
      ${nav('clearing', 'bank', 'Clearing house', d.pending.length)}
      ${nav('market', 'chart', 'Wash market')}
      <div class="side-foot">Every entry is <b>signed</b>. Flagged entries get pulled by the Treasury — with your name on them.</div>`;
  },
  render() {
    const v = this.st.view;
    const main = v === 'clearing' ? this.viewClearing() : v === 'market' ? this.viewMarket() : this.viewDeclare();
    const sealed = this.sealed();
    return shell({
      width: 1180, height: 820, side: this.side(), main, sub: this.data.front.sub,
      status: sealed ? `<b>${esc(this.data.front.label)}</b> · books sealed by Treasury` : `<b>${esc(this.data.front.label)}</b> · back office`,
      dot: sealed ? 'red' : '',
      keys: [['ESC', 'Close'], ['↵', 'Sign the books']],
      right: `Declared today <b>${money(this.data.declared)}</b> / ${money(this.data.front.dailyCap)}`,
    }) + (this.st.receipt ? this.receipt() : '');
  },
  viewDeclare() {
    const d = this.data, st = this.st, c = this.calc();
    const sealed = this.sealed();
    const rows = d.batches.length ? d.batches.map((b) => `
      <div class="row pick${st.sel.has(b.id) ? ' sel' : ''}" data-act="pick" data-id="${esc(b.id)}">
        <div class="av">${b.members > 1 ? svg('users') : esc(b.serial.slice(0, 2))}</div>
        <div class="row-txt"><b>${esc(b.serial)}</b><span>Q ${pct(b.quality)} · heat ${b.heat}${b.crew > 0 ? ` · crew +${pct(b.crew)}` : ''}</span></div>
        <div class="row-end"><b>${money(b.amount)}</b><span>→ ${money(b.value)}</span></div>
        <span class="sw ${st.sel.has(b.id) ? 'on' : ''}"><i></i></span>
      </div>`).join('') : empty('box', 'No clean stacks on you', `Bring ${esc(labels[d.finalItem] || 'banded stacks')} from the guillotine to declare them here.`);
    const lines = d.front.categories.map((cat) => {
      const v = st.alloc[cat.key];
      const off = Math.abs(v / 100 - cat.share);
      return `<div class="alloc-row">
        <div class="alloc-top"><span>${esc(cat.label)}</span><b id="a-${cat.key}" class="${off > 0.15 ? 'bad' : off > 0.07 ? 'off' : ''}">${v}%</b></div>
        <div class="alloc-track"><input type="range" min="0" max="100" step="1" value="${v}" data-alloc="${cat.key}">
          <span class="typ" style="left:calc(${cat.share * 100}% - 1px)"></span></div>
        <div class="alloc-foot"><span>Typical ${Math.round(cat.share * 100)}%</span><span id="am-${cat.key}">${money((c.amount * v) / 100)}</span></div></div>`;
    }).join('');
    const sTone = c.s >= d.rules.flagAt ? 'red' : c.s >= d.rules.flagAt * 0.6 ? 'amber' : '';
    return `
      ${sealed ? `<div class="banner">${svg('shield')}<span><b>Treasury audit in progress.</b> The books are sealed for <b data-until="${d.auditUntil}">${fmtT(d.auditUntil - nowS())}</b>. Pending clearings from this front were partly frozen.</span></div>` : ''}
      ${head(esc(d.front.label), `${esc(d.front.sub || '')} · Declare washed stacks as revenue. Stick close to the usual mix and under the daily cap.`,
        clockBox(money(d.declared), `of ${money(d.front.dailyCap)} declared · 24h`))}
      <div class="stats four">
        ${stat('cash', 'Declaring', money(c.amount), '', 'b-amount')}
        ${stat('bank', st.mode === 'instant' ? 'Cash now' : 'Clears to bank', money(c.value), '', 'b-value')}
        ${stat('scan', 'Suspicion', pct(c.s), sTone, 'b-sus')}
        ${stat('shield', 'Audit chance', pct(c.audit, 1), c.audit > 0.25 ? 'red' : '', 'b-audit')}
      </div>
      <div class="cols">
        <section class="panel"><div class="p-head"><div><h2>Stacks on you</h2><p>Tap to include · value at today's rate</p></div>
          <button class="btn-ghost" data-act="all">${svg('check')}All</button></div>
          <div class="p-body">${rows}</div></section>
        <section class="panel"><div class="p-head"><div><h2>Revenue lines</h2><p>How the money shows up on paper</p></div>
          <button class="btn-ghost" data-act="typical">${svg('mix')}Typical mix</button></div>
          <div class="p-body pad" style="gap:14px">
            <div class="alloc">${lines}</div>
            <div class="choice">
              <button class="${st.mode === 'clearing' ? 'on' : ''}" data-act="mode" data-k="clearing"><b>Clearing house <em>bank</em></b>
                <span>Full value. Lands in ${d.rules.clearingMinutes} min — an audit can freeze part of it.</span></button>
              <button class="${st.mode === 'instant' ? 'on' : ''}" data-act="mode" data-k="instant"><b>Cash out now <em>−${pct(d.rules.instantFee)}</em></b>
                <span>Skimmed by the manager. Paid in cash, nothing pending.</span></button>
            </div>
          </div></section>
      </div>
      <div class="actions"><span class="note" id="b-note">${c.s >= d.rules.flagAt ? 'This entry will be flagged for review.' : 'Looks like a normal day of business.'}</span>
        <button class="btn-teal" data-act="sign" ${sealed || !c.picked.length || st.busy ? 'disabled' : ''}>Sign the books</button></div>`;
  },
  viewClearing() {
    const d = this.data;
    const rows = d.pending.map((p) => `<tr><td><b>${esc((p.front || '').toUpperCase())}</b></td><td><b>${money(p.amount)}</b></td>
      <td>${p.seized > 0 ? `<span class="chip red">−${money(p.seized)}</span>` : '<span class="chip off">none</span>'}</td>
      <td><b data-until="${p.release_at}">${fmtT(p.release_at - nowS())}</b></td></tr>`).join('');
    return `
      ${head('Clearing house', 'Clean deposits waiting to settle into your bank. If the front gets audited before they land, part of them is frozen.')}
      <section class="panel"><div class="p-head"><div><h2>Pending</h2><p>Paid out automatically while you're in the city</p></div></div>
        <div class="p-body pad">${d.pending.length ? `<table><thead><tr><th>Front</th><th>Amount</th><th>Frozen</th><th>Lands in</th></tr></thead><tbody>${rows}</tbody></table>`
          : empty('bank', 'Nothing clearing', 'Deposits you send through the clearing house show up here until they land.')}</div></section>`;
  },
  viewMarket() {
    const m = this.data.market || {}, hist = (m.history || []).slice();
    if (m.rate != null) hist.push(m.rate);
    const W = 820, H = 150, lo = 0.45, hi = 0.95;
    const pts = hist.map((v, i) => [hist.length > 1 ? (i / (hist.length - 1)) * W : W / 2, H - ((v - lo) / (hi - lo)) * H]);
    const line = pts.map((p) => p.map((n) => n.toFixed(1)).join(',')).join(' ');
    const area = pts.length ? `0,${H} ${line} ${W},${H}` : '';
    const e = m.event;
    return `
      ${head('Wash market', 'One rate for the whole city. The more everyone launders, the worse it gets — and the news moves it too.',
        `<div class="clock"><div class="rate-big">${m.rate ? pct(m.rate) : '—'}<small>per $1</small></div></div>`)}
      <div class="stats">
        ${stat('chart', 'Current rate', m.rate ? pct(m.rate, 1) : '—')}
        ${stat('layers', 'Saturation', pct(m.saturation || 0), (m.saturation || 0) > 0.6 ? 'red' : '')}
        ${stat('info', 'Street news', e ? esc(e.label) : 'Quiet', e ? (e.mod < 0 ? 'red' : '') : '')}
      </div>
      <section class="panel"><div class="p-head"><div><h2>Rate history</h2><p>Last ${hist.length} readings</p></div></div>
        <div class="p-body pad"><svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
          <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--teal)" stop-opacity=".28"/><stop offset="1" stop-color="var(--teal)" stop-opacity="0"/></linearGradient></defs>
          ${[0.5, 0.7, 0.9].map((v) => `<line x1="0" x2="${W}" y1="${H - ((v - lo) / (hi - lo)) * H}" y2="${H - ((v - lo) / (hi - lo)) * H}" stroke="rgba(255,255,255,.06)"/>`).join('')}
          ${area ? `<polygon points="${area}" fill="url(#g)"/><polyline points="${line}" fill="none" stroke="var(--teal)" stroke-width="2" vector-effect="non-scaling-stroke"/>` : ''}
        </svg></div></section>
      ${e ? `<article class="inc ${e.mod < 0 ? 'urgent' : ''}"><div class="inc-top"><span class="chip ${e.mod < 0 ? 'red' : ''}">${e.mod < 0 ? 'Headwind' : 'Tailwind'} ${(e.mod > 0 ? '+' : '') + pct(e.mod)}</span>
          <span class="ref">ends in <span data-until="${e.endsAt}">${fmtT(e.endsAt - nowS())}</span></span></div><h3>${esc(e.label)}</h3><p>${esc(e.note || '')}</p></article>` : ''}`;
  },
  receipt() {
    const r = this.st.receipt;
    const lines = (r.lines || []).map((l) => `<div class="kv"><span>${esc(l.serial)} · ${money(l.amount)}</span><b>${money(l.value)}</b></div>`).join('');
    return `<div class="modal-wrap" style="position:fixed"><div class="modal enter">
      <div class="modal-b"><div class="warn ${r.audited ? '' : 'teal'}">${svg(r.audited ? 'alert' : 'check')}</div>
        <div style="flex:1"><h4>${r.audited ? 'Signed — and the Treasury noticed' : 'Books signed'}</h4>
          <div class="big">${money(r.payout)}</div>
          <p>${r.mode === 'instant' ? 'Paid out in cash. Nothing pending.' : `Clearing to your bank in <b style="color:var(--white)" data-until="${r.releaseAt}">${fmtT(r.releaseAt - nowS())}</b>.`}
            Rate ${pct(r.rate)}${r.crew > 0 ? ` · crew +${pct(r.crew)}` : ''} · suspicion ${pct(r.suspicion)}${r.flagged ? ' · <b style="color:var(--red)">flagged</b>' : ''}.</p>
          ${r.audited ? '<p style="margin-top:8px;color:var(--red)">An audit is about to open on this front. Anything still clearing here will be partly frozen.</p>' : ''}
          <div style="margin-top:10px">${lines}</div></div></div>
      <div class="modal-f"><button class="btn-white" data-act="done">Done</button></div></div></div>`;
  },
  updateLive() {
    const d = this.data, c = this.calc();
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
    set('b-amount', money(c.amount)); set('b-value', money(c.value)); set('b-sus', pct(c.s)); set('b-audit', pct(c.audit, 1));
    set('b-note', c.s >= d.rules.flagAt ? 'This entry will be flagged for review.' : 'Looks like a normal day of business.');
    d.front.categories.forEach((cat) => {
      const v = this.st.alloc[cat.key];
      const el = document.getElementById('a-' + cat.key);
      if (el) { el.textContent = v + '%'; const off = Math.abs(v / 100 - cat.share); el.className = off > 0.15 ? 'bad' : off > 0.07 ? 'off' : ''; }
      set('am-' + cat.key, money((c.amount * v) / 100));
      const r = document.querySelector(`input[data-alloc="${cat.key}"]`);
      if (r && Number(r.value) !== v) { r.value = v; setRange(r); }
    });
    const tileOf = (id) => document.getElementById(id)?.closest('.stat')?.querySelector('.tile');
    const sT = tileOf('b-sus'); if (sT) sT.className = 'tile ' + (c.s >= d.rules.flagAt ? 'red' : c.s >= d.rules.flagAt * 0.6 ? 'amber' : '');
    const aT = tileOf('b-audit'); if (aT) aT.className = 'tile ' + (c.audit > 0.25 ? 'red' : '');
  },
  input(el) {
    if (el.dataset.alloc) { this.setAlloc(el.dataset.alloc, Number(el.value)); this.updateLive(); }
  },
  on(act, el) {
    const st = this.st;
    if (act === 'view') { st.view = el.dataset.k; draw(); }
    if (act === 'pick') { const id = el.dataset.id; if (st.sel.has(id)) st.sel.delete(id); else st.sel.add(id); draw(); }
    if (act === 'all') { if (st.sel.size === this.data.batches.length) st.sel.clear(); else this.data.batches.forEach((b) => st.sel.add(b.id)); draw(); }
    if (act === 'typical') { this.data.front.categories.forEach((c) => { st.alloc[c.key] = Math.round(c.share * 100); }); this.fixAlloc(); draw(); }
    if (act === 'mode') { st.mode = el.dataset.k; draw(); }
    if (act === 'sign') this.sign();
    if (act === 'done') finish(null);
  },
  key(e) { if (e.key === 'Enter' && this.st.view === 'declare' && !this.st.receipt) this.sign(); },
  async sign() {
    const d = this.data, st = this.st, c = this.calc();
    if (st.busy || !c.picked.length || this.sealed()) return;
    st.busy = true; draw();
    const shares = {};
    Object.keys(st.alloc).forEach((k) => { shares[k] = st.alloc[k] / 100; });
    const res = await request('nzmw:books:submit', d.front.id, c.picked.map((b) => b.id), shares, st.mode);
    if (cur !== this) return;
    st.busy = false;
    if (!res || !res.ok) { toast({ title: 'Not signed', message: (res && res.err) || 'Something went wrong.', type: 'error' }); return draw(); }
    syncClock(res.now);
    const ids = new Set(c.picked.map((b) => b.id));
    d.batches = d.batches.filter((b) => !ids.has(b.id));
    st.sel = new Set(d.batches.map((b) => b.id));
    d.declared += c.amount;
    if (res.flagged) d.flags += 1;
    if (res.mode === 'clearing') d.pending.push({ front: d.front.id, amount: res.payout, seized: 0, release_at: res.releaseAt });
    st.receipt = res;
    draw();
  },
};

/* ─────────────── TREASURY LEDGER (audit) ─────────────── */
Panels.audit = {
  init() { syncClock(this.data.now); },
  render() {
    const d = this.data;
    const active = d.auditUntil && d.auditUntil > nowS();
    const cats = d.front.categories;
    const colors = ['var(--teal)', 'var(--white)', 'var(--amber)', 'var(--red)', 'var(--ink-3)'];
    const rows = (d.rows || []).map((r) => {
      const flagged = r.flagged === 1 || r.flagged === true;
      const mix = cats.map((c, i) => `<i style="width:${((r.allocation || {})[c.key] || 0) * 100}%;background:${colors[i % colors.length]}"></i>`).join('');
      const ago = Math.max(0, nowS() - r.created_at);
      return `<tr class="${flagged ? 'flag' : ''}"><td>${ago < 3600 ? Math.floor(ago / 60) + 'm' : Math.floor(ago / 3600) + 'h'} ago</td>
        <td><b>${esc(r.name)}</b></td><td><b>${money(r.amount)}</b></td><td><div class="mix">${mix}</div></td>
        <td><span class="chip ${flagged ? 'red' : r.suspicion > d.flagAt * 0.6 ? 'amber' : ''}">${pct(r.suspicion)}</span></td>
        <td style="font-size:10.5px">${esc(String(r.serials || '').split(',').slice(0, 2).join(', '))}${String(r.serials || '').split(',').length > 2 ? '…' : ''}</td></tr>`;
    }).join('');
    const legend = cats.map((c, i) => `<span style="display:inline-flex;align-items:center;gap:6px;margin-left:12px"><i style="width:8px;height:8px;border-radius:2px;background:${colors[i % colors.length]};display:inline-block"></i>${esc(c.label)}</span>`).join('');
    const main = `
      ${head(esc(d.front.label) + ' — ledger', 'Last 48 hours of declared revenue. Flagged entries were pulled for review and show the full signature.',
        active ? `<div class="clock"><b data-until="${d.auditUntil}">${fmtT(d.auditUntil - nowS())}</b><span>audit in progress</span></div>` : clockBox('Open', 'books status'))}
      <div class="stats">
        ${stat('cash', 'Declared · 24h', money(d.declared), d.declared > d.front.dailyCap ? 'red' : '')}
        ${stat('doc', 'Daily cap', money(d.front.dailyCap))}
        ${stat('alert', 'Flagged · 24h', d.flags, d.flags > 0 ? 'red' : '')}
      </div>
      <section class="panel" style="flex:1"><div class="p-head"><div><h2>Entries</h2><p>Revenue mix per entry ${legend}</p></div></div>
        <div class="p-body pad">${rows ? `<table><thead><tr><th>When</th><th>Signed</th><th>Amount</th><th>Mix</th><th>Suspicion</th><th>Serials</th></tr></thead><tbody>${rows}</tbody></table>`
          : empty('book', 'Clean books', 'Nothing has been declared here in the last two days.')}</div></section>
      <div class="actions"><span class="note">Opening an audit seals the books and freezes ${'part of'} every pending clearing from this front.</span>
        <button class="btn-red" data-act="audit" ${active ? 'disabled' : ''}>Order Treasury audit</button></div>`;
    return shell({ width: 1120, height: 720, main, sub: 'Treasury · forensic accounting', status: `<b>${esc(d.front.label)}</b> · ${active ? 'under audit' : 'records request'}`, dot: active ? 'red' : '' });
  },
  async on(act) {
    if (act !== 'audit') return;
    const res = await request('nzmw:audit:start', this.data.front.id);
    if (cur !== this) return;
    if (!res || !res.ok) return toast({ title: 'Audit', message: (res && res.err) || 'Failed.', type: 'error' });
    this.data.auditUntil = res.auditUntil;
    toast({ title: 'Audit opened', message: `${this.data.front.label} is sealed. Pending clearings were frozen.`, type: 'success' });
    draw();
  },
};

/* ─────────────── UV SCAN ─────────────── */
Panels.scan = {
  render() {
    const d = this.data;
    const cards = (d.batches || []).map((b) => {
      const trail = (b.trail || []).map((t) => `<div><span>${new Date(t.t * 1000).toTimeString().slice(0, 5)}</span>${esc(t.text)}</div>`).join('');
      return `<article class="inc ${b.reserialized ? '' : b.heat >= 60 ? 'urgent' : b.heat >= 25 ? 'amber' : ''}">
        <div class="inc-top"><span class="chip ${b.reserialized ? 'off' : heatChip(b.heat)}">${esc(b.verdict)}</span><span class="ref">${esc(b.serial)}</span></div>
        <h3>${money(b.amount)} · ${esc(b.item || '')}</h3>
        <p>${b.origin ? `Serial range matches <b style="color:var(--white)">${esc(b.origin)}</b>. Notes first logged by <b style="color:var(--white)">${esc(b.loader)}</b>.` : b.reserialized ? 'Serials were re-printed. No usable trail on the notes themselves.' : 'Trace too faint to pull an origin.'}</p>
        <div class="meta"><span>Heat <b>${b.heat}</b></span><span>Stage <b>${esc(stageName(b.stage))}</b></span><span>Re-serialised <b>${b.reserialized ? 'yes' : 'no'}</b></span></div>
        ${trail ? `<div class="trail">${trail}</div>` : ''}</article>`;
    }).join('');
    const dirty = (d.dirty || []).map((x) => `<div class="row"><div class="av">${svg('cash')}</div><div class="row-txt"><b>${esc(x.label)}</b><span>Unwashed</span></div><div class="row-end"><b>${money(x.total)}</b></div><span class="tag hot">Dirty</span></div>`).join('');
    const nothing = !cards && !dirty;
    const main = `
      ${head('UV serial scan', esc(d.subject || ''), clockBox((d.batches || []).length + (d.dirty || []).length, 'hits'))}
      ${d.kind === 'station' ? `<div class="stats">${stat('gauge', 'State', esc(d.state))}${stat('wrench', 'Wear', Math.floor(d.wear) + '%')}${stat('users', 'Registered to', esc(d.owner || 'Operation'))}</div>` : ''}
      <section class="panel" style="flex:1;min-height:200px"><div class="p-head"><div><h2>Findings</h2><p>Serial ranges cross-checked against flagged cash</p></div></div>
        <div class="p-body">${nothing ? empty('scan', 'Nothing glows', 'No marked bills or laundering batches detected.') : dirty + cards}</div></section>`;
    return shell({ width: 820, height: 640, tight: true, main, sub: 'LSPD · financial crimes', status: `UV scanner · <b>${nothing ? 'clean' : 'hits found'}</b>`, dot: nothing ? '' : 'red' });
  },
};

/* ═══════════════════════════════════════════════════════════
   TOAST / PROGRESS / HINT
   ═══════════════════════════════════════════════════════════ */
function toast(t) {
  const err = t.type === 'error';
  const dur = t.duration || 5000;
  const el = document.createElement('div');
  el.className = 'toast' + (err ? ' err' : '');
  el.style.setProperty('--d', dur + 'ms');
  el.innerHTML = `<div class="ti">${svg(err ? 'info' : t.type === 'success' ? 'check' : 'info')}</div><div><b>${esc(t.title)}</b><p>${esc(t.message)}</p></div>`;
  $toasts.prepend(el);
  while ($toasts.children.length > 5) $toasts.lastChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 230); }, dur);
}

const $prog = document.getElementById('progress');
const $progFill = document.getElementById('progress-fill');
function progress(label, duration) {
  document.getElementById('progress-label').textContent = label;
  $prog.classList.remove('hidden', 'fail');
  $progFill.style.transition = 'none';
  $progFill.style.width = '0%';
  void $progFill.offsetWidth;
  $progFill.style.transition = `width ${duration}ms linear`;
  $progFill.style.width = '100%';
}
function progressEnd(ok) {
  if (!ok) { $prog.classList.add('fail'); $progFill.style.transition = 'none'; }
  setTimeout(() => $prog.classList.add('hidden'), ok ? 120 : 600);
}

const $hint = document.getElementById('hint');
function hint(text) {
  if (!text) return $hint.classList.add('hidden');
  $hint.textContent = text;
  $hint.classList.remove('hidden');
}

/* ═══════════════════════════════════════════════════════════
   MESSAGES
   ═══════════════════════════════════════════════════════════ */
window.addEventListener('message', (e) => {
  const m = e.data || {};
  switch (m.action) {
    case 'init': applyTheme(m.theme || {}); labels = m.labels || {}; break;
    case 'open': teardown(); open(m.panel, m.data || {}); break;
    case 'close': teardown(); break;
    case 'toast': toast(m); break;
    case 'progress': progress(m.label, m.duration); break;
    case 'progressEnd': progressEnd(m.ok); break;
    case 'hint': hint(m.text); break;
  }
});

post('ready');
