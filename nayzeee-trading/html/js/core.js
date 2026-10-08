/* ═══════════════════════════════════════════════════════════
   Core: DOM helpers, formatting, icons, NUI bridge, sound, state
   ═══════════════════════════════════════════════════════════ */
const NZ = window.NZ = {};

// ── DOM ─────────────────────────────────────────────────────────
NZ.$ = (sel, root = document) => root.querySelector(sel);
NZ.$$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
NZ.h = (html) => {
  const t = document.createElement('template');
  t.innerHTML = html.trim();
  return t.content.firstElementChild;
};
const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
NZ.esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ESC[c]);
NZ.text = (el, v) => { if (el && el.textContent !== v) el.textContent = v; };
NZ.cls = (el, name, on) => el && el.classList.toggle(name, !!on);

// ── events ──────────────────────────────────────────────────────
const listeners = {};
NZ.on = (ev, fn) => {
  (listeners[ev] = listeners[ev] || []).push(fn);
  return () => { listeners[ev] = listeners[ev].filter((f) => f !== fn); };
};
NZ.emit = (ev, data) => (listeners[ev] || []).slice().forEach((fn) => fn(data));

// ── formatting ──────────────────────────────────────────────────
const F2 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const F4 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 4, maximumFractionDigits: 4 });
const F0 = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
const FQ = new Intl.NumberFormat('en-US', { maximumFractionDigits: 4 });

NZ.dp = (p) => (Math.abs(p) >= 1 ? 2 : 4);
NZ.tick = (p) => (Math.abs(p) >= 1 ? 0.01 : 0.0001);
NZ.roundTick = (p) => { const t = NZ.tick(p); return Math.round(p / t) * t; };
NZ.px = (p) => (p == null || isNaN(p) ? '—' : (Math.abs(p) >= 1 ? F2 : F4).format(p));
NZ.money = (v) => (v == null || isNaN(v) ? '—' : (v < 0 ? '-$' : '$') + F2.format(Math.abs(v)));
NZ.money0 = (v) => (v < 0 ? '-$' : '$') + F0.format(Math.abs(v));
NZ.signed = (v) => (v == null || isNaN(v) ? '—' : (v > 0 ? '+$' : v < 0 ? '-$' : '$') + F2.format(Math.abs(v)));
NZ.pct = (v, sign = true) => (v == null || !isFinite(v) ? '—' : (sign && v > 0 ? '+' : '') + v.toFixed(2) + '%');
NZ.qty = (q) => FQ.format(q);
NZ.compact = (v) => {
  const a = Math.abs(v);
  if (a >= 1e9) return (v / 1e9).toFixed(2) + 'B';
  if (a >= 1e6) return (v / 1e6).toFixed(2) + 'M';
  if (a >= 1e4) return (v / 1e3).toFixed(1) + 'K';
  return F0.format(v);
};
NZ.dir = (v) => (v > 0 ? 'up' : v < 0 ? 'dn' : '');
const pad = (n) => String(n).padStart(2, '0');
NZ.clock = (t, secs) => {
  const d = new Date(t * 1000);
  return pad(d.getHours()) + ':' + pad(d.getMinutes()) + (secs ? ':' + pad(d.getSeconds()) : '');
};
NZ.date = (t) => new Date(t * 1000).toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long' });
NZ.shortDate = (t) => new Date(t * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
NZ.ago = (t) => {
  const s = Math.max(0, NZ.state.t - t);
  if (s < 60) return 'just now';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  return Math.floor(s / 3600) + 'h ago';
};
NZ.countdown = (s) => {
  s = Math.max(0, Math.floor(s));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
  return h ? `${h}h ${pad(m)}m` : `${pad(m)}:${pad(x)}`;
};
NZ.initials = (name) => String(name || '?').split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase();

// ── icons (stroke, 24px grid) ───────────────────────────────────
const I = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  candles: '<path d="M7 3v4M7 17v4M17 3v5M17 15v6"/><rect x="5" y="7" width="4" height="10" rx="1"/><rect x="15" y="8" width="4" height="7" rx="1"/>',
  briefcase: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M3 13h18"/>',
  list: '<path d="M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01"/>',
  pulse: '<path d="M4 17h2l1.5-6L10 19l2.5-14L15 15l1.5-4H20"/>',
  news: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
  trophy: '<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4z"/><path d="M17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3"/>',
  wallet: '<path d="M19 7V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-3"/><path d="M21 9h-6a3 3 0 0 0 0 6h6V9z"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.9 4.9 7 7M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1 7 17M17 7l2.1-2.1"/>',
  star: '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9L12 3z"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<path d="M5 12h14"/>',
  bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
  power: '<path d="M12 3v9"/><path d="M6.3 6.3a8 8 0 1 0 11.4 0"/>',
  wifi: '<path d="M2 8.8a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M12 19.5h.01"/>',
  battery: '<rect x="2" y="7" width="18" height="10" rx="2"/><path d="M22 11v2"/><rect x="5" y="10" width="10" height="4" rx=".5" fill="currentColor" stroke="none"/>',
  max: '<rect x="5" y="5" width="14" height="14" rx="2"/>',
  restore: '<rect x="4" y="8" width="12" height="12" rx="2"/><path d="M8 8V6a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2"/>',
  home: '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1v-9z"/>',
  calc: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 7h8M8 11.5h.01M12 11.5h.01M16 11.5h.01M8 15.5h.01M12 15.5h.01M16 15.5h.01"/>',
  arrowUp: '<path d="M12 19V5M6 11l6-6 6 6"/>',
  arrowRight: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
  alert: '<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 8v.01M12 11v5"/>',
  pause: '<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  sidebar: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16"/>',
  coin: '<circle cx="12" cy="12" r="9"/><path d="M14.5 9.5c-.5-1-1.5-1.5-2.5-1.5-1.7 0-3 .9-3 2s1.3 1.8 3 2 3 .9 3 2-1.3 2-3 2c-1 0-2-.5-2.5-1.5M12 6.5V8M12 16v1.5"/>',
  bolt: '<path d="M13 3 4 14h7l-1 7 9-11h-7l1-7z"/>',
  volume: '<path d="M11 5 6 9H3v6h3l5 4V5z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/>',
  user: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
  flatten: '<path d="M4 12h16M8 8l-4 4 4 4M16 8l4 4-4 4"/>',
  bank: '<path d="M3 10h18M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 21h18M12 3l9 5H3l9-5z"/>',
  target: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/><circle cx="12" cy="12" r=".5" fill="currentColor"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
};
NZ.icon = (n, extra = '') => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" ${extra}>${I[n] || ''}</svg>`;

// ── NUI bridge ──────────────────────────────────────────────────
NZ.resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;

NZ.post = async (name, data) => {
  if (!NZ.resource) return NZ.preview ? NZ.preview.post(name, data) : null;
  const res = await fetch(`https://${NZ.resource}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {}),
  });
  return res.json();
};

NZ.api = async (action, data) => {
  try {
    return (await NZ.post('api', { action, data })) || { ok: false, err: 'No response' };
  } catch (e) {
    return { ok: false, err: 'Connection lost' };
  }
};

// ── sound (synthesised, no audio files) ─────────────────────────
const Sound = NZ.sound = {
  ctx: null, master: null, noiseBuf: null, vol: 0.6, on: true, keys: true,

  init() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return false;
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.gain.value = this.vol;
      this.master.connect(this.ctx.destination);
      const len = this.ctx.sampleRate * 0.5;
      this.noiseBuf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const d = this.noiseBuf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
    return true;
  },

  setVolume(v) { this.vol = v; if (this.master) this.master.gain.value = v; },

  tone(freq, at, dur, o = {}) {
    const c = this.ctx, t = c.currentTime + at;
    const osc = c.createOscillator(), g = c.createGain();
    osc.type = o.type || 'sine';
    osc.frequency.setValueAtTime(freq, t);
    if (o.to) osc.frequency.exponentialRampToValueAtTime(o.to, t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(o.gain || 0.15, t + (o.attack || 0.004));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    osc.connect(g).connect(this.master);
    osc.start(t);
    osc.stop(t + dur + 0.05);
  },

  noise(at, dur, o = {}) {
    const c = this.ctx, t = c.currentTime + at;
    const src = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
    src.buffer = this.noiseBuf;
    f.type = 'bandpass';
    f.frequency.value = o.freq || 2500;
    f.Q.value = o.q || 1;
    g.gain.setValueAtTime(o.gain || 0.08, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f).connect(g).connect(this.master);
    src.start(t, Math.random() * 0.3);
    src.stop(t + dur + 0.02);
  },

  sfx: {
    fill() { this.tone(1318.5, 0, 0.32, { gain: 0.16 }); this.tone(1760, 0.085, 0.55, { gain: 0.15 }); this.tone(3520, 0.085, 0.25, { gain: 0.025 }); },
    place() { this.noise(0, 0.035, { gain: 0.14, freq: 3800, q: 2.5 }); this.tone(1046.5, 0, 0.08, { type: 'triangle', gain: 0.07 }); },
    cancel() { this.tone(740, 0, 0.12, { type: 'triangle', gain: 0.08, to: 440 }); },
    reject() { this.tone(196, 0, 0.11, { type: 'square', gain: 0.045 }); this.tone(164.8, 0.13, 0.17, { type: 'square', gain: 0.045 }); },
    alert() { [0, 0.13, 0.26].forEach((t) => this.tone(1568, t, 0.1, { type: 'triangle', gain: 0.12 })); },
    news() { this.tone(987.8, 0, 0.2, { gain: 0.08 }); this.tone(1318.5, 0.11, 0.3, { gain: 0.08 }); },
    key() { this.noise(0, 0.028, { gain: 0.05 + Math.random() * 0.03, freq: 2200 + Math.random() * 1800, q: 1.4 }); },
    click() { this.noise(0, 0.016, { gain: 0.045, freq: 4200, q: 2 }); },
    boot() { [523.25, 659.25, 783.99, 1046.5].forEach((f, i) => this.tone(f, i * 0.075, 1.2, { gain: 0.06, attack: 0.03 })); },
    unlock() { this.tone(880, 0, 0.12, { gain: 0.07 }); this.tone(1318.5, 0.08, 0.22, { gain: 0.07 }); },
    shutdown() { [783.99, 659.25, 523.25].forEach((f, i) => this.tone(f, i * 0.09, 0.55, { gain: 0.06, attack: 0.02 })); },
    margin() { for (let i = 0; i < 6; i++) this.tone(i % 2 ? 660 : 880, i * 0.16, 0.14, { type: 'square', gain: 0.04 }); },
  },

  play(name) {
    if (!this.on || (name === 'key' && !this.keys)) return;
    if (!this.init()) return;
    const fx = this.sfx[name];
    if (fx) fx.call(this);
  },
};

// keyboard clicks while typing anywhere in the device
document.addEventListener('keydown', (e) => {
  if (e.repeat || !NZ.state.open) return;
  if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT')) Sound.play('key');
});

// ── state ───────────────────────────────────────────────────────
const S = NZ.state = {
  open: false, device: null, cfg: {}, player: {}, profile: null,
  accounts: {}, active: 'practice', alerts: [],
  syms: [], by: {}, t: 0, session: { code: 'open' }, news: [], cal: [], unreadNews: 0,
  settings: { volume: 0.6, sounds: true, keySounds: true, confirm: false, hotkeys: true, compact: false, wallpaper: 'teal' },
  watch: [], focus: null,
};

NZ.load = (boot) => {
  S.cfg = boot.cfg || {};
  S.player = boot.player || {};
  S.t = boot.t;
  S.session = boot.session || { code: 'open' };
  S.news = boot.news || [];
  S.cal = boot.calendar || [];
  S.syms = (boot.market || []).map((m, i) => {
    const row = (boot.quotes || [])[i] || [];
    m.q = { last: row[0], bid: row[1], ask: row[2], vol: row[3] || 0, hi: row[4], lo: row[5], dir: 0, dvol: 0 };
    return m;
  });
  S.by = {};
  S.syms.forEach((m) => { S.by[m.s] = m; });
  NZ.loadProfile(boot);
};

NZ.loadProfile = (boot) => {
  S.profile = boot.profile || null;
  S.accounts = boot.accounts || {};
  S.alerts = boot.alerts || [];
  if (S.profile) {
    Object.assign(S.settings, S.profile.settings || {});
    S.watch = (S.profile.watchlist || []).filter((s) => S.by[s]);
    S.active = S.profile.active === 'live' && S.accounts.live ? 'live' : 'practice';
  }
  if (!S.focus || !S.by[S.focus]) S.focus = S.watch[0] || (S.syms.find((m) => m.tradable) || {}).s;
  NZ.applySettings();
};

NZ.applySettings = () => {
  Sound.on = S.settings.sounds;
  Sound.keys = S.settings.keySounds;
  Sound.setVolume(S.settings.volume);
  NZ.emit('settings');
};

NZ.onQuotes = (d) => {
  const minute = Math.floor(d.t / 60) !== Math.floor(S.t / 60);
  S.t = d.t;
  for (let i = 0; i < d.q.length; i++) {
    const m = S.syms[i];
    if (!m) continue;
    const r = d.q[i], q = m.q;
    q.dir = r[0] > q.last ? 1 : r[0] < q.last ? -1 : 0;
    q.last = r[0]; q.bid = r[1]; q.ask = r[2];
    q.dvol = Math.max(0, r[3] - q.vol);
    q.vol = r[3]; q.hi = r[4]; q.lo = r[5];
    if (minute && m.spark) { m.spark.push(q.last); if (m.spark.length > 60) m.spark.shift(); }
  }
  NZ.emit('quotes');
};

NZ.change = (m) => (m.prev ? ((m.q.last - m.prev) / m.prev) * 100 : 0);
NZ.isCrypto = (sym) => (S.by[sym] || {}).type === 'crypto';
NZ.halted = (m) => m.halt && m.halt > S.t;
NZ.tradableNow = (m, type) => {
  if (!m.tradable) return 'Indices are not tradable';
  if (NZ.halted(m)) return m.s + ' is halted';
  if (m.type === 'crypto') return null;
  const c = S.session.code;
  if (c === 'open') return null;
  if (c === 'closed') return type === 'market' ? 'Market is closed' : null;
  return type === 'market' || type === 'stop' || type === 'trail' ? 'Only limit orders trade in extended hours' : null;
};

NZ.account = () => S.accounts[S.active];

// live account maths from the latest quotes
NZ.metrics = (acc = NZ.account()) => {
  if (!acc) return null;
  let mv = 0, ex = 0, upnl = 0;
  for (const p of acc.positions) {
    const m = S.by[p.sym];
    const last = m ? m.q.last : p.avg;
    mv += p.qty * last;
    ex += Math.abs(p.qty) * last;
    upnl += p.qty * (last - p.avg);
  }
  const lev = S.cfg.leverage || 1;
  const equity = acc.cash + mv;
  const day = equity - acc.dayStart;
  return {
    equity, exposure: ex, upnl, day,
    dayPct: acc.dayStart ? (day / acc.dayStart) * 100 : 0,
    bp: Math.max(0, equity * lev - ex),
    withdrawable: Math.max(0, Math.min(acc.cash, equity - ex / lev)),
    net: acc.realized - acc.fees,
  };
};

NZ.position = (sym, acc = NZ.account()) => (acc ? acc.positions.find((p) => p.sym === sym) : null);

NZ.fee = (sym, qty, price) => {
  const f = S.cfg.fees;
  if (!f) return 0;
  if (NZ.isCrypto(sym)) return Math.round(qty * price * f.crypto.pct * 100) / 100;
  return Math.round(Math.min(Math.max(f.stock.min, qty * f.stock.perShare), qty * price * f.stock.maxPct) * 100) / 100;
};

NZ.sessionLabel = () => {
  const c = S.session.code;
  return { open: 'Market open', pre: 'Pre-market', post: 'After hours', closed: 'Market closed' }[c] || c;
};
NZ.sessionDot = () => ({ open: '', pre: 'amber', post: 'amber', closed: 'red' }[S.session.code] || '');
NZ.sessionNext = () => {
  if (!S.session.enabled || !S.session.next) return '24/7 trading';
  const left = NZ.countdown(S.session.next - S.t);
  return { open: 'closes in ', pre: 'opens in ', post: 'ends in ', closed: 'pre-market in ' }[S.session.code] + left;
};

NZ.saveSettings = async () => {
  const res = await NZ.api('settings', { settings: S.settings });
  if (res.ok) Object.assign(S.settings, res.data);
  NZ.applySettings();
};
