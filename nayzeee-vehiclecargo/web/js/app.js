'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-vehiclecargo';
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

const S = {
  static: null, view: null,
  term: null, floor: 'main', stockSel: null, offers: null, offersFor: null,
  lb: null, lbTab: 'earned', admin: null, adminTab: 'vehicles', adminOnly: false, vForm: {}, lForm: {},
  shop: null, shopSel: null,
  lt: { wins: {}, order: [], focus: null, z: 10, stage: 'desk', start: false, unlocked: 0, seq: 0, fresh: null, pending: null, user: 'user' },
  ws: null, hud: null, hudMax: 0, hudPos: null, hudEdit: null, feed: [], busy: false,
};

/* ───────── transport ───────── */
async function post(action, data = {}) {
  if (window.__mock) return window.__mock(action, data);
  try {
    const r = await fetch(`https://${RES}/req`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action, data }) });
    return await r.json();
  } catch (e) { return { ok: false }; }
}

/* owner preferences: accent, laptop finish, wallpaper, clock, sounds, glass */
const PREF_DEFAULT = { accent: 'teal', finish: 'graphite', wallpaper: 'accent', clock: '12', fastboot: false, sounds: true, glass: true, radio: true };
S.prefs = { ...PREF_DEFAULT }; S.myPrefs = { ...PREF_DEFAULT }; S.radio = null; S.planDel = new Set();
const prefOpts = () => obj(S.static?.prefOptions || S.bootOptions);
function mixHex(hex, to, k) {
  const a = hexRgb(hex), b = hexRgb(to);
  return a.map((v, i) => Math.round(v + (b[i] - v) * k));
}
function applyPrefs(p) {
  p = { ...PREF_DEFAULT, ...obj(p) }; S.prefs = p;
  const acc = arr(prefOpts().accents).find(a => a.id === p.accent)?.color || '#08afa2';
  const fin = arr(prefOpts().finishes).find(f => f.id === p.finish) || { a: '#17191b', b: '#0a0b0c' };
  const base = hexRgb(acc), hi = mixHex(acc, '#ffffff', .3), lo = mixHex(acc, '#000000', .35);
  const lum = (.2126 * base[0] + .7152 * base[1] + .0722 * base[2]) / 255;
  const st = document.documentElement.style, css = c => `rgb(${c.join(',')})`;
  st.setProperty('--teal', acc); st.setProperty('--teal-hi', css(hi)); st.setProperty('--teal-lo', css(lo));
  st.setProperty('--acc', base.join(',')); st.setProperty('--acc-hi', hi.join(',')); st.setProperty('--acc-lo', lo.join(','));
  st.setProperty('--on-acc', lum > .55 ? '#0b0d0e' : (lum > .38 ? '#04140f' : '#ffffff'));
  st.setProperty('--bz1', fin.a); st.setProperty('--bz2', fin.b);
  const w = $('#lt-wall'); if (w) w.dataset.w = p.wallpaper;
  $('#laptop').classList.toggle('glass', !!p.glass);
  $$('[data-clock]').forEach(el => { el.textContent = clockTxt(); });
}

/* small UI sounds (WebAudio, no files) */
let actx = null;
function beep(kind) {
  if (!S.prefs.sounds || S.view !== 'laptop') return;
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const o = actx.createOscillator(), g = actx.createGain(), t = actx.currentTime;
    const f = { click: [1400, .018, .04], open: [660, .05, .12], note: [880, .06, .18], boot: [523, .09, .5] }[kind] || [1000, .02, .05];
    o.type = kind === 'boot' ? 'sine' : 'triangle'; o.frequency.setValueAtTime(f[0], t);
    if (kind === 'boot') o.frequency.exponentialRampToValueAtTime(1046, t + .35);
    g.gain.setValueAtTime(f[1], t); g.gain.exponentialRampToValueAtTime(.0001, t + f[2]);
    o.connect(g); g.connect(actx.destination); o.start(t); o.stop(t + f[2] + .02);
  } catch (e) { /* audio blocked */ }
}

/* ───────── helpers ───────── */
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = n => '$' + Math.round(Number(n) || 0).toLocaleString('en-US');
const obj = v => (v && typeof v === 'object' && !Array.isArray(v)) ? v : {};
const arr = v => Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);
const clone = v => JSON.parse(JSON.stringify(v ?? {}));
const clamp = (n, a, b) => Math.max(a, Math.min(b, n));

function fmtTime(sec) {
  sec = Math.max(0, Math.floor(sec));
  const m = Math.floor(sec / 60), s = sec % 60;
  return m > 0 ? `${m}:${String(s).padStart(2, '0')}` : `${s}s`;
}
function ago(t) {
  const d = Math.max(0, Date.now() / 1000 - t);
  if (d < 60) return 'Just now';
  if (d < 3600) return `${Math.floor(d / 60)}m ago`;
  if (d < 86400) return `${Math.floor(d / 3600)}h ago`;
  return `${Math.floor(d / 86400)}d ago`;
}
const clockTxt = () => new Date().toLocaleTimeString(S.prefs?.clock === '24' ? 'en-GB' : 'en-US', { hour: S.prefs?.clock === '24' ? '2-digit' : 'numeric', minute: '2-digit', hour12: S.prefs?.clock !== '24' });
const dateTxt = () => new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
function hexRgb(h) { h = String(h || '#9ea5aa').replace('#', ''); return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)); }
function rv(id) { return rvc(R(id).color); }
function rvc(hex) {
  const [a, b, c] = hexRgb(hex);
  return `--c:${hex};--cw:rgba(${a},${b},${c},.11);--ce:rgba(${a},${b},${c},.34)`;
}
function R(id) {
  const ill = S.static?.illegal;
  if (ill && id === ill.id) return ill;
  return arr(S.static?.rarities).find(r => r.id === id) || { id, label: id, color: '#9ea5aa', index: 1, valueMult: 1 };
}
const rar = id => `<span class="chip r" style="${rv(id)}">${R(id).illegal ? '<i class="fa-solid fa-skull"></i>' : ''}${esc(R(id).label)}</span>`;
const allRar = () => arr(S.static?.rarities).concat(S.static?.illegal ? [S.static.illegal] : []);

/* v5 building blocks */
const tile = (fa, cls = '') => `<div class="tile ${cls}"><i class="fa-solid ${fa}"></i></div>`;
const stat = (fa, label, value, cls = '', delta = '') => `<div class="stat">${tile(fa, cls)}<div class="stat-txt"><span>${label}</span><b>${value}</b></div>${delta}</div>`;
const panel = (title, sub, act, body, o = {}) => `<section class="panel ${o.cls || ''}" ${o.style ? `style="${o.style}"` : ''}>
  <div class="p-head"><div>${o.icon || ''}<h2>${title}</h2>${sub ? `<p>${sub}</p>` : ''}</div>${act || ''}</div>
  <div class="p-body ${o.pad ? 'pad' : ''}">${body}</div></section>`;
const empty = (fa, t, s = '') => `<div class="empty"><i class="fa-solid ${fa}"></i><b>${t}</b>${s ? `<span>${s}</span>` : ''}</div>`;
const head = (title, sub, right = '') => `<div class="head"><div><h1>${title}</h1><p>${sub}</p></div>${right}</div>`;
const clock = (b, s) => `<div class="clock"><b>${b}</b><span>${s}</span></div>`;
const keys = list => list.map(([k, l]) => `<span><span class="key">${k}</span>${l}</span>`).join('');
const initials = n => String(n || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join('') || '?';
const sw = (on, act, id) => `<button class="sw ${on ? 'on' : ''}" data-act="${act}" data-id="${esc(id)}"><i></i></button>`;
const ring = (frac, big, small, size = 42) => { const C = 2 * Math.PI * size; return `<div class="ring"><svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="${size}" stroke="#1c2023" stroke-width="7" fill="none"/>
  <circle cx="50" cy="50" r="${size}" style="stroke:var(--teal)" stroke-width="7" fill="none" stroke-linecap="round" stroke-dasharray="${C}" stroke-dashoffset="${C * (1 - clamp(frac, 0, 1))}"/></svg>
  <div class="in"><div><b>${big}</b><span>${small}</span></div></div></div>`; };

function fit() {
  const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
  document.documentElement.style.setProperty('--scale', s);
  S.scale = s;
}
window.addEventListener('resize', fit); fit();
function show(id, on) { $(id).classList.toggle('hidden', !on); }

/* ───────── shared rules (mirror of shared/utils.lua) ───────── */
const Cargo = {
  up(track, lvl) { const t = S.static.upgrades[track]; const l = arr(t?.levels); return l[lvl || 0] || l[0]; },
  rarityAt(i) { const l = arr(S.static.rarities); return l[clamp(i, 1, l.length) - 1]; },
  parts() { return arr(S.static.workshop.Parts); },
  score(build, wsLevel) {
    build = obj(build); const W = S.static.workshop;
    let perf = 0, style = 0;
    const add = (p, n) => { if (p.kind === 'perf') perf += n; else style += n; };
    for (const p of Cargo.parts()) {
      const v = build[p.id];
      if (v === undefined || v === null) continue;
      if (p.type === 'level') add(p, clamp(Number(v) || 0, 0, p.max) * p.points);
      else if (p.type === 'toggle') { if (v === true) add(p, p.points); }
      else if (p.type === 'part' || p.type === 'livery') { if (Number(v) >= 0) add(p, p.points); }
      else if (p.type === 'paint' && typeof v === 'object') {
        const f = arr(W.Finishes).find(f => f.id === Number(v.finish)); let n = f ? f.points : 0;
        if (v.p && v.s && v.p !== v.s) n += W.TwoTonePoints;
        if (Number(v.pearl) > 0) n += 1;
        add(p, n);
      } else if (p.type === 'wheels' && typeof v === 'object') {
        let n = 0;
        if (v.type !== undefined && v.type !== null) { n = p.points; if (v.type === 7 || v.type === 12) n += W.HighEndWheelBonus; if (v.custom) n += W.CustomTyres.points; }
        if (v.color !== undefined && v.color !== null) n += W.RimColor.points;
        add(p, n);
      } else if (p.type === 'tint' || p.type === 'plate') { if (Number(v) !== 0) add(p, p.points); }
      else if (p.type === 'xenon' || p.type === 'neon') add(p, p.points);
    }
    let total = perf + style; const b = W.Balance;
    if (perf >= b.perf && style >= b.style) total += b.points;
    const lvl = Cargo.up('workshop', wsLevel);
    total *= (lvl?.scoreMult || 1);
    return { score: Math.min(100, Math.floor(total)), perf, style };
  },
  rarityFromScore(base, score, maxGain) {
    if (R(base).illegal) return base;
    let gain = 0; arr(S.static.workshop.ScoreToRarity).forEach((need, i) => { if (score >= need) gain = i + 1; });
    gain = Math.min(gain, maxGain || 0);
    return Cargo.rarityAt(R(base).index + gain).id;
  },
  cost(old, neu, baseRarity) {
    old = obj(old); neu = obj(neu); const W = S.static.workshop;
    const mult = W.CostMult[baseRarity] || 1; let total = 0; const lines = [];
    const charge = (p, amt, label) => { if (amt <= 0) return; amt = Math.floor(amt * mult); total += amt; lines.push({ label: label || p.label, cost: amt }); };
    const same = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
    for (const p of Cargo.parts()) {
      const o = old[p.id], n = neu[p.id];
      if (p.type === 'level') { const a = Number(o) || 0, b = Number(n) || 0; if (b > a) { let s = 0; for (let st = a + 1; st <= b; st++) s += p.price * st; charge(p, s, `${p.label} stage ${b}`); } }
      else if (p.type === 'toggle') { if (n === true && o !== true) charge(p, p.price); }
      else if (p.type === 'part' || p.type === 'livery') { const b = n ?? -1; if (b >= 0 && b !== (o ?? -1)) charge(p, p.price); }
      else if (p.type === 'wheels') { if (n && typeof n === 'object') { const ot = obj(o), has = x => x !== undefined && x !== null;
        if (has(n.type) && (n.type !== ot.type || n.index !== ot.index)) charge(p, p.price);
        if (n.custom && !ot.custom) charge(p, W.CustomTyres.price, 'Custom Tyres');
        if (has(n.color) && n.color !== ot.color) charge(p, W.RimColor.price, 'Rim Colour'); } }
      else if (p.type === 'paint') { if (n && typeof n === 'object' && !same({ p: o?.p, s: o?.s, finish: o?.finish, pearl: o?.pearl }, { p: n.p, s: n.s, finish: n.finish, pearl: n.pearl })) charge(p, p.price); }
      else { if (n !== undefined && n !== null && n !== o && !(p.type !== 'xenon' && p.type !== 'neon' && Number(n) === 0)) charge(p, p.price); }
    }
    return { total, lines };
  },
  baseValue(st, contacts) {
    const base = R(st.base_rarity), cur = R(st.rarity);
    let v = st.value * (cur.valueMult / base.valueMult);
    v *= 1 - (1 - clamp(st.condition ?? 100, 0, 100) / 100) * S.static.conditionWeight;
    v *= 1 + (st.score || 0) * S.static.workshop.ValuePerPoint;
    v *= 1 + (Cargo.up('contacts', contacts)?.saleBonus || 0);
    return Math.floor(v);
  },
};

/* ───────── toasts / modal ───────── */
function toast(title, text = '', ok = true) {
  const el = document.createElement('div');
  el.className = 'toast ' + (ok ? '' : 'err');
  el.innerHTML = `<div class="ti"><i class="fa-solid ${ok ? 'fa-check' : 'fa-exclamation'}"></i></div><div><b>${esc(title)}</b>${text ? `<p>${esc(text)}</p>` : ''}</div>`;
  $('#toasts').appendChild(el);
  beep('note');
  setTimeout(() => el.remove(), 3300);
}

let modalResolve = null;
function modal({ title, text, html, confirm = 'Confirm', danger = false, cancel = 'Cancel', icon }) {
  return new Promise(res => {
    if (modalResolve) { const r = modalResolve; modalResolve = null; r(false); }
    modalResolve = res;
    $('#modal').innerHTML = `<div class="modal">
      <div class="modal-b">${tile(icon || (danger ? 'fa-triangle-exclamation' : 'fa-circle-question'), danger ? 'red' : '')}
        <div><h4>${esc(title)}</h4>${text ? `<p>${esc(text)}</p>` : ''}</div></div>
      ${html ? `<div class="modal-x">${html}</div>` : ''}
      <div class="modal-f">${cancel ? `<button class="btn" data-act="mdNo">${esc(cancel)}</button>` : ''}
        ${confirm ? `<button class="btn ${danger ? 'danger' : 'primary'}" data-act="mdYes">${esc(confirm)}</button>` : ''}</div>
    </div>`;
    show('#modal', true);
  });
}
function closeModal(v) { show('#modal', false); $('#modal').innerHTML = ''; if (modalResolve) { const r = modalResolve; modalResolve = null; r(v); } }
const modalOpen = () => !$('#modal').classList.contains('hidden');

/* ═══════════════════════════════════════════════════════════
   LAPTOP APPS
   ═══════════════════════════════════════════════════════════ */
const APPS = [
  { id: 'overview', label: 'Dashboard', icon: 'fa-gauge-high', exe: 'dashboard.exe', w: 1180, h: 770 },
  { id: 'contracts', label: 'Contracts', icon: 'fa-file-signature', exe: 'contracts.exe', w: 1180, h: 770 },
  { id: 'stock', label: 'Inventory', icon: 'fa-car-side', exe: 'inventory.exe', w: 1260, h: 780, fill: true, badge: t => t.stock.length || null },
  { id: 'upgrades', label: 'Upgrades', icon: 'fa-layer-group', exe: 'upgrades.exe', w: 1180, h: 780 },
  { id: 'floorplan', label: 'Floor Plan', icon: 'fa-border-all', exe: 'floorplan.exe', w: 1180, h: 780 },
  { id: 'scanner', label: 'Scanner', icon: 'fa-satellite-dish', exe: 'scanner.exe', w: 960, h: 660, lock: t => !t.warehouse.scanner, badge: t => arr(t.hot).length || null },
  { id: 'tracker', label: 'Tracker Tools', icon: 'fa-tower-broadcast', exe: 'tracker.exe', w: 1120, h: 720 },
  { id: 'ledger', label: 'Ledger', icon: 'fa-receipt', exe: 'ledger.exe', w: 1120, h: 770 },
  { id: 'leaderboard', label: 'Leaderboard', icon: 'fa-ranking-star', exe: 'leaderboard.exe', w: 940, h: 720 },
  { id: 'associates', label: 'Associates', icon: 'fa-user-group', exe: 'associates.exe', w: 880, h: 620 },
  { id: 'settings', label: 'Settings', icon: 'fa-gear', exe: 'settings.exe', w: 900, h: 660 },
];
const appOf = id => APPS.find(a => a.id === id);
const appsFor = () => APPS;
const ADMIN_TABS = [
  { id: 'vehicles', icon: 'fa-car', label: 'Vehicles' }, { id: 'locations', icon: 'fa-location-dot', label: 'Locations' },
  { id: 'interior', icon: 'fa-warehouse', label: 'Interior' }, { id: 'brokers', icon: 'fa-user-tie', label: 'Brokers' }, { id: 'presets', icon: 'fa-border-all', label: 'Presets' },
  { id: 'warehouses', icon: 'fa-key', label: 'Owned' }, { id: 'players', icon: 'fa-users', label: 'Players' },
];

function renderApp(id) {
  if (!S.term) return '';
  switch (id) {
    case 'overview': return appOverview();
    case 'contracts': return appContracts();
    case 'stock': return appStock();
    case 'upgrades': return appUpgrades();
    case 'floorplan': return appFloorplan();
    case 'scanner': return appScanner();
    case 'tracker': return appTracker();
    case 'ledger': return appLedger();
    case 'leaderboard': return appLeaderboard();
    case 'associates': return appAssociates();
    case 'settings': return appSettings();
  }
  return '';
}
const isOwner = () => S.term && S.term.role === 'owner';
const can = k => !!(S.term && obj(S.term.perms)[k]);
const lowerFull = t => t.warehouse.lowerCount >= t.warehouse.lowerCapacity;

/* dashboard */
const KIND = {
  sale: ['fa-sack-dollar', '', 'Sold'], export: ['fa-ship', '', 'Exported'], sourced: ['fa-car-on', '', 'Sourced'], chop: ['fa-gears', '', 'Chopped'],
  contract: ['fa-file-signature', 'off', 'Contract'], failed: ['fa-triangle-exclamation', 'red', 'Failed'], design: ['fa-spray-can-sparkles', 'off', 'Design'],
  repair: ['fa-screwdriver-wrench', 'off', 'Repair'], upgrade: ['fa-layer-group', 'off', 'Upgrade'], purchase: ['fa-warehouse', 'off', 'Purchase'], scrap: ['fa-recycle', 'off', 'Scrapped'],
  insure: ['fa-shield-halved', 'off', 'Insured'], claim: ['fa-file-invoice-dollar', '', 'Insurance claim'], seized: ['fa-handcuffs', 'red', 'Seized'],
  bribe: ['fa-money-bill-transfer', 'off', 'Bribe'], prestige: ['fa-crown', '', 'Prestige'], keys: ['fa-key', 'off', 'Keys'],
};
function feedRow(l) {
  const k = KIND[l.kind] || ['fa-circle', 'off', l.kind];
  const amt = l.amount ? `<b class="${l.amount > 0 ? 'pos' : ''}">${l.amount > 0 ? '+' : '−'}${money(Math.abs(l.amount))}</b>` : `<b class="dim">—</b>`;
  return `<div class="row"><div class="av ${k[1] === '' ? 'teal' : ''}" ${k[1] === 'red' ? 'style="color:var(--red);background:var(--red-wash);border-color:var(--red-edge)"' : ''}><i class="fa-solid ${k[0]}"></i></div>
    <div class="row-txt"><b>${k[2]} · ${esc(l.label || '')}</b><span>${ago(l.t)}${l.rarity ? ' · ' + esc(R(l.rarity).label) : ''}${l.data && l.data.reason ? ' · ' + esc(l.data.reason) : ''}</span></div>
    <div class="row-end">${amt}</div></div>`;
}
function appOverview() {
  const t = S.term, p = t.profile, w = t.warehouse;
  const next = arr(S.static.rarities).find(r => r.level > p.level);
  const counts = {}; t.stock.forEach(s => counts[s.rarity] = (counts[s.rarity] || 0) + 1);
  const maxC = Math.max(1, ...Object.values(counts));
  const stockValue = t.stock.reduce((a, s) => a + (s.baseValue || 0), 0);
  const progress = `
    <div style="display:flex;gap:16px;align-items:center">
      ${ring(p.xpNeed ? p.xpInto / p.xpNeed : 1, p.level, 'Level')}
      <div style="flex:1;display:flex;flex-direction:column;gap:8px">
        <div class="kv"><span>Experience</span><b>${p.xpNeed ? `${p.xpInto.toLocaleString()} / ${p.xpNeed.toLocaleString()}` : 'Max level'}</b></div>
        <div class="kv"><span>Next unlock</span>${next ? `<span>${rar(next.id)} <span class="dim">at level ${next.level}</span></span>` : '<b>All tiers</b>'}</div>
        <div class="kv"><span>Main floor</span><b>${w.stockCount} / ${w.capacity}</b></div>
        <div class="kv"><span>Lower level</span>${w.lowerOpen ? `<b>${w.lowerCount} / ${w.lowerCapacity}</b>` : '<span class="tag off"><i class="fa-solid fa-lock"></i>Locked</span>'}</div>
      </div>
    </div>
    <div style="display:flex;flex-direction:column;gap:9px;margin-top:4px">
      ${allRar().map(r => `<div style="display:grid;grid-template-columns:96px 1fr 22px;gap:10px;align-items:center;${rv(r.id)}">${rar(r.id)}
        <div class="bar-line r"><i style="width:${((counts[r.id] || 0) / maxC) * 100}%"></i></div><span class="dim" style="font-size:11px;text-align:right">${counts[r.id] || 0}</span></div>`).join('')}
    </div>`;
  return head('Dashboard', 'Progress, money and the latest activity for this warehouse.', clock(`Level ${p.level}`, p.xpNeed ? `${(p.xpNeed - p.xpInto).toLocaleString()} XP to go` : 'Max level'))
    + `<div class="stats">
        ${stat('fa-sack-dollar', 'Total earned', money(p.earned))}
        ${stat('fa-car-on', 'Vehicles sourced', p.sourced)}
        ${stat('fa-handshake', 'Vehicles sold', p.sold)}
      </div>
      <div class="stats">
        ${stat('fa-warehouse', 'Stock value', money(stockValue))}
        ${stat('fa-fire', 'Clean streak', p.streak, '', p.streak > 0 ? `<div class="delta"><i class="fa-solid fa-arrow-up"></i>+${Math.min(p.streak * 2, 10)}%</div>` : '')}
        ${stat('fa-triangle-exclamation', 'Failed jobs', p.failed, 'red')}
      </div>
      ${heatAndPrestige(t)}
      <div class="cols">
        ${panel('Progress', 'Level, unlocks and stock by rarity', '', progress, { pad: true })}
        ${panel('Recent activity', 'Latest entries for this warehouse', `<button class="btn ghost" data-act="tab" data-id="ledger"><i class="fa-solid fa-receipt"></i>Ledger</button>`,
          t.ledger.length ? t.ledger.slice(0, 7).map(feedRow).join('') : empty('fa-wave-square', 'Nothing yet', 'Take a contract and your activity shows up here.'))}
      </div>`;
}

function heatAndPrestige(t) {
  const p = t.profile, w = t.warehouse, out = [];
  if (w.raids) {
    const pct = Math.min(100, (w.heat / Math.max(1, w.heatMax)) * 100), warn = (w.heatWarn / Math.max(1, w.heatMax)) * 100;
    const state = w.raid ? ['red', 'Raid in progress'] : w.heat >= w.heatMax ? ['red', 'Raid imminent'] : w.heat >= w.heatWarn ? ['red', 'Police are asking questions'] : w.heat > w.heatMax * .3 ? ['', 'Warm'] : ['', 'Cool'];
    const b = obj(S.static.bribe), canBribe = can('bribe') && w.heat > 0 && !w.raid;
    out.push(panel('Police heat', 'Stored cars build heat. Hot and illegal cars build it fastest.', `<span class="tag ${state[0] === 'red' ? 'hot' : 'live'}">${state[1]}</span>`, `
      <div class="kv"><span>Heat</span><b>${w.heat} / ${w.heatMax}</b></div>
      <div class="meter heat"><i style="width:${pct}%"></i><span class="tick" style="left:${warn}%"><span>Warning</span></span></div>
      <div class="chips" style="margin-top:6px">
        <button class="btn ${canBribe ? 'primary' : ''}" data-act="bribe" ${canBribe ? '' : 'disabled'}><i class="fa-solid fa-money-bill-transfer"></i>Pay off a contact · ${money(b.Price || 0)} <span class="dim">(−${b.Step || 0})</span></button>
        ${w.claims > 0 ? `<button class="btn" data-act="claims" ${isOwner() ? '' : 'disabled'}><i class="fa-solid fa-file-invoice-dollar"></i>Collect claims · ${money(w.claims)}</button>` : ''}
      </div>`, { pad: true }));
  }
  if (p.prestigeMax > 0) {
    const stars = Array.from({ length: p.prestigeMax }, (_, i) => `<i class="fa-solid fa-star" style="color:${i < p.prestige ? 'var(--teal)' : 'var(--line)'}"></i>`).join('');
    out.push(panel('Prestige', p.prestige ? `Prestige ${p.prestige} · +${Math.round(p.saleBonus * 100)}% sale money · +${Math.round(p.xpBonus * 100)}% XP` : `Reach level ${S.static.levels.Max} to prestige`,
      p.prestige ? `<span class="tag live"><i class="fa-solid fa-crown"></i>P${p.prestige}</span>` : '', `
      <div class="chips" style="font-size:14px;gap:4px">${stars}</div>
      <div class="note"><span class="dot"></span><span>Your level goes back to 1. You keep your contracts, earn a badge and a permanent bonus on every sale and every XP gain.</span></div>
      <button class="btn ${p.canPrestige ? 'primary' : ''} wide" data-act="prestige" ${p.canPrestige ? '' : 'disabled'}><i class="fa-solid fa-crown"></i>${p.prestige >= p.prestigeMax ? 'Max prestige' : `Prestige${p.prestigeCost ? ' · ' + money(p.prestigeCost) : ''}`}</button>`, { pad: true }));
  }
  return out.length ? `<div class="cols even">${out.join('')}</div>` : '';
}

/* contracts */
function appContracts() {
  const t = S.term, p = t.profile, full = t.warehouse.stockCount >= t.warehouse.capacity;
  const intel = Cargo.up('intel', t.warehouse.upgrades.intel);
  let note;
  if (t.mission) note = `<div class="note"><span class="dot red"></span><span>You already have an active job. <b>Finish it first.</b></span></div>`;
  else if (!t.policeOk) note = `<div class="note"><span class="dot red"></span><span>Not enough <b>police on duty</b> for contracts right now.</span></div>`;
  else if (p.sourceCd > 0) note = `<div class="note"><span class="dot red"></span><span>Your contacts are laying low for <b data-cd="${Date.now() + p.sourceCd * 1000}">${fmtTime(p.sourceCd)}</b>.</span></div>`;
  else if (full) note = `<div class="note"><span class="dot red"></span><span>Your main floor is <b>full</b>. Sell or scrap a car, or upgrade Storage.</span></div>`;
  else note = `<div class="note"><span class="dot"></span><span>Intel network: <b>${Math.round((intel?.rollUp || 0) * 100)}%</b> chance any contract comes back one rarity higher.</span></div>`;
  const busy = !!t.mission || !t.policeOk || p.sourceCd > 0 || !can('contracts');
  if (!can('contracts') && !t.mission) note = `<div class="note"><span class="dot red"></span><span>Your crew role can't take contracts. Ask the owner.</span></div>`;
  const top = arr(t.contracts).filter(x => x.unlocked && !x.illegal).slice(-1)[0];
  return head('Contracts', 'Pick a tier. Higher tiers pay more and fight back harder.', clock(money(top?.fee || 0), 'Top unlocked fee'))
    + note
    + `<div class="ct-grid">${t.contracts.map(c => {
      const ill = !!c.illegal, sp = !!c.special, idx = ill ? 6 : sp ? 3 : R(c.rarity).index;
      const roomy = ill ? !lowerFull(t) : !full;
      const cooling = (c.cd || 0) > 0;
      const ok = c.unlocked && !busy && roomy && c.pool > 0 && !cooling;
      let state;
      if (ill && c.needsLower) state = `<span class="tag off"><i class="fa-solid fa-stairs"></i>Needs Lower Level</span>`;
      else if (!c.unlocked) state = `<span class="tag off"><i class="fa-solid fa-lock"></i>Level ${c.level}</span>`;
      else if (cooling) state = `<span class="tag hot"><i class="fa-solid fa-hourglass-half"></i><span data-cd="${Date.now() + c.cd * 1000}">${fmtTime(c.cd)}</span></span>`;
      else state = `<span class="chip r">Lv ${c.level}+</span>`;
      const sub = ill ? (c.needsLower ? 'Buy the Lower Level upgrade to run these' : (lowerFull(t) ? 'Lower level is full' : 'Stored downstairs · 4 slots'))
        : sp ? esc(c.desc || '') : (c.unlocked ? `${c.pool} vehicles in the pool` : `Unlocks at level ${c.level}`);
      const style = sp ? rvc(c.color || '#08afa2') : rv(c.rarity);
      return `<section class="panel ct ${c.unlocked ? '' : 'locked'} ${ill ? 'illegal' : ''} ${sp ? 'special' : ''}" style="${style}">
        <div class="p-head"><div><div class="tier">${ill ? '<i class="fa-solid fa-skull"></i>' : sp ? `<i class="${esc(c.icon || 'fa-solid fa-star')}"></i>` : ''}${esc(c.label)}</div><p>${sub}</p></div>${state}</div>
        <div class="p-body pad">
          <div class="mini" style="grid-template-columns:1fr 1fr 1fr">
            <div><span>Fee</span><b>${money(c.fee)}</b></div><div><span>XP</span><b>+${c.xp}</b></div>
            <div><span>Threat</span><div class="threat">${Array.from({ length: 6 }, (_, i) => `<i class="${i < idx ? 'on' : ''}"></i>`).join('')}</div></div>
          </div>
          <button class="btn ${ok ? 'primary' : ''} wide" ${ok ? '' : 'disabled'} data-act="source" data-id="${c.rarity}">
            <i class="fa-solid ${!c.unlocked ? 'fa-lock' : cooling ? 'fa-hourglass-half' : 'fa-bolt'}"></i>${!c.unlocked ? 'Locked' : cooling ? 'Cooling down' : 'Take contract'}</button>
        </div></section>`;
    }).join('')}</div>`
    + crewJobsBlock(t);
}
function crewJobsBlock(t) {
  const cj = t.crewJobs; if (!cj || !arr(cj.jobs).length) return '';
  const enough = cj.here >= cj.min, allowed = can('crewjob');
  return `<div class="grp" style="margin:0">Crew jobs <span class="dim" style="font-weight:300">· ${cj.here} of your crew inside · needs ${cj.min}</span></div>
    <div class="ct-grid">${arr(cj.jobs).map(j => {
      const cooling = j.cd > 0, ok = j.unlocked && !cooling && enough && allowed && !t.mission && t.policeOk;
      const state = !j.unlocked ? `<span class="tag off"><i class="fa-solid fa-lock"></i>Level ${j.level}</span>`
        : cooling ? `<span class="tag hot"><i class="fa-solid fa-hourglass-half"></i><span data-cd="${Date.now() + j.cd * 1000}">${fmtTime(j.cd)}</span></span>`
        : `<span class="chip r">${j.cars} cars</span>`;
      return `<section class="panel ct crew ${j.unlocked ? '' : 'locked'}" style="${rv(j.rarity)}">
        <div class="p-head"><div><div class="tier"><i class="${esc(j.icon || 'fa-solid fa-people-group')}"></i>${esc(j.label)}</div><p>${esc(j.desc || '')}</p></div>${state}</div>
        <div class="p-body pad">
          <div class="mini" style="grid-template-columns:1fr 1fr 1fr">
            <div><span>Fee</span><b>${money(j.fee)}</b></div><div><span>Cars</span><b>${esc(j.rarityLabel || '')}</b></div><div><span>Bonus</span><b class="pos">${money(j.bonusCash)}</b></div>
          </div>
          <button class="btn ${ok ? 'primary' : ''} wide" ${ok ? '' : 'disabled'} data-act="crewJob" data-id="${esc(j.id)}">
            <i class="fa-solid ${!j.unlocked ? 'fa-lock' : 'fa-people-group'}"></i>${!j.unlocked ? 'Locked' : !enough ? `Need ${cj.min} inside` : !allowed ? 'Not your role' : 'Start crew job'}</button>
        </div></section>`;
    }).join('')}</div>`;
}

/* inventory */
function buildChips(b) {
  b = obj(b); const out = [];
  for (const p of Cargo.parts()) {
    const v = b[p.id]; if (v === undefined || v === null) continue;
    let txt = p.label;
    if (p.type === 'level') txt += ` ${v}`;
    if (p.type === 'paint') { const f = arr(S.static.workshop.Finishes).find(f => f.id === v.finish); txt = `${f ? f.label : ''} paint`; }
    out.push(`<span class="tag live">${esc(txt)}</span>`);
  }
  return out.length ? out.join('') : '<span class="tag off">Factory stock</span>';
}
function appStock() {
  const t = S.term, w = t.warehouse;
  if (S.floor === 'lower' && !w.lowerOpen) S.floor = 'main';
  const list = t.stock.filter(s => (s.floor || 'main') === S.floor);
  const seg = `<div class="seg">
    <button class="${S.floor === 'main' ? 'on' : ''}" data-act="floor" data-id="main"><i class="fa-solid fa-warehouse"></i>Main floor · ${w.stockCount}/${w.capacity}</button>
    <button class="${S.floor === 'lower' ? 'on' : ''} ${w.lowerOpen ? '' : 'lock'}" ${w.lowerOpen ? 'data-act="floor" data-id="lower"' : ''}><i class="fa-solid ${w.lowerOpen ? 'fa-stairs' : 'fa-lock'}"></i>Lower level · ${w.lowerCount}/${w.lowerCapacity || 4}</button></div>`;
  const dealBtn = can('sell') && obj(S.static.crewSale).Enabled
    ? `<button class="btn ${S.deal ? 'primary' : ''}" data-act="dealMode"><i class="fa-solid fa-people-arrows"></i>${S.deal ? 'Cancel crew sale' : 'Crew sale'}</button>` : '';
  const title = head('Inventory', S.floor === 'lower' ? 'Illegal vehicles stored downstairs. They sell high and draw heavy attention.' : 'Design, repair and sell the cars on your floor.', `<div style="display:flex;gap:8px;align-items:center">${dealBtn}${seg}</div>`);
  if (!list.length) return title + empty(S.floor === 'lower' ? 'fa-skull' : 'fa-car-side', S.floor === 'lower' ? 'Nothing downstairs' : 'No vehicles in stock',
    S.floor === 'lower' ? 'Illegal contracts land down here.' : 'Source one from Contracts and it lands here.')
    + `<div><button class="btn primary" data-act="tab" data-id="contracts"><i class="fa-solid fa-file-signature"></i>Open contracts</button></div>`;
  if (!list.find(s => s.id === S.stockSel)) S.stockSel = list[0].id;
  const s = list.find(x => x.id === S.stockSel);
  const dl = S.deal;
  const rows = list.map(x => `
    <button class="row stripe ${dl ? (dl.pick.has(x.id) ? 'on' : '') : x.id === S.stockSel ? 'on' : ''}" style="${rv(x.rarity)}" data-act="${dl ? 'dealToggle' : 'stockSel'}" data-id="${x.id}" ${dl && x.status !== 'stored' ? 'disabled' : ''}>
      ${dl ? `<i class="fa-solid ${dl.pick.has(x.id) ? 'fa-square-check' : 'fa-square'}" style="color:${dl.pick.has(x.id) ? 'var(--teal)' : 'var(--ink-3)'};font-size:15px"></i>` : ''}
      <div class="row-txt"><b>${esc(x.label)}${x.hot ? ' <i class="fa-solid fa-fire" style="color:var(--red);font-size:10px" title="Hot"></i>' : ''}${x.insured ? ' <i class="fa-solid fa-shield-halved" style="color:var(--teal);font-size:10px" title="Insured"></i>' : ''}</b><span>${esc(x.plate || '')} · ${esc(R(x.rarity).label)}${x.status !== 'stored' ? ' · on a sale run' : ''}</span></div>
      <div class="row-end"><b>${money(x.baseValue)}</b><span>${x.condition}% · ${x.score} pts</span></div>
    </button>`).join('');
  return title + `<div class="t-split">${panel('Vehicles', dl ? `${dl.pick.size} picked for the crew sale` : `${list.length} stored`, '', rows)}${dl ? dealPanel() : stockDetail(s)}</div>`;
}
/* crew sale: pick cars, pick a buyer, give every car a driver */
function dealPanel() {
  const C = obj(S.static.crewSale), dl = S.deal, t = S.term;
  const picked = t.stock.filter(x => dl.pick.has(x.id));
  const enough = picked.length >= C.MinCars && picked.length <= C.MaxCars;
  const intro = `<div class="note"><span class="dot"></span><span>Pick <b>${C.MinCars} to ${C.MaxCars}</b> cars. Every car needs its own driver from your crew inside the warehouse. Hits only lower the price of the car that took them, a lost car doesn't kill the deal, and the crew gets a <b>${Math.round((C.Cut || 0) * 100)}% cut</b> each once every car is dropped.</span></div>`;
  if (!dl.offers) {
    return `<section class="panel" id="stock-detail"><div class="p-head"><div><h2>Crew sale</h2><p>${picked.length ? picked.map(x => esc(x.label)).join(' · ') : 'Nothing picked yet'}</p></div></div>
      <div class="p-body pad">${intro}
        <button class="btn ${enough ? 'primary' : ''} wide" data-act="dealOffers" ${enough ? '' : 'disabled'}><i class="fa-solid fa-handshake"></i>Find buyers for ${picked.length || ''} car${picked.length === 1 ? '' : 's'}</button>
      </div></section>`;
  }
  const o = dl.offers, crew = arr(o.crew), opts = arr(o.options), cur = opts[dl.opt] || opts[0];
  const need = picked.length, cd = o.cooldown > 0;
  const opt = (x, i) => `<button class="inc ${x.hot ? 'urgent' : ''} ${dl.opt === i ? 'on' : ''}" data-act="dealOpt" data-id="${i}" style="text-align:left;cursor:pointer;${dl.opt === i ? 'border-color:var(--teal);box-shadow:0 0 0 1px var(--teal) inset' : ''}">
      <div class="inc-top"><span class="chip ${x.hot ? 'red' : ''}">${esc(x.label)}</span><span class="ref">${x.mode === 'split' ? 'Split run' : esc(x.place || '')}${x.dist ? ` · ${(x.dist / 1000).toFixed(1)} km` : ''}</span></div>
      <h3>${esc(x.name)}</h3><div class="offer-amt pos">${money(x.total)}</div>
      <div class="meta"><span>${x.mode === 'split' ? 'Every car to its own drop' : 'All cars to one drop'}${x.hot ? ' · <b style="color:var(--red)">crews tailing</b>' : ''}</span></div></button>`;
  const drv = id => dl.assign[id];
  const rows = arr(cur.cars).map(c => `<div class="row"><div class="row-txt"><b>${esc(c.label)}</b><span>${esc(c.place || '')} · ${money(c.amount)}</span></div>
      <select class="input sm" data-driver="${c.stockId}" style="width:170px"><option value="">Pick a driver</option>
        ${crew.map(m => `<option value="${m.src}" ${String(drv(c.stockId)) === String(m.src) ? 'selected' : ''}>${esc(m.name)}${m.src === o.me ? ' (you)' : ''}</option>`).join('')}</select></div>`).join('');
  const chosen = arr(cur.cars).map(c => String(drv(c.stockId) || ''));
  const ready = chosen.every(Boolean) && new Set(chosen).size === chosen.length && chosen.includes(String(o.me)) && !cd;
  const warn = crew.length < need ? `<div class="note"><span class="dot red"></span><span>Only <b>${crew.length}</b> of your crew ${crew.length === 1 ? 'is' : 'are'} inside and free. You need <b>${need}</b> drivers.</span></div>`
    : cd ? `<div class="note"><span class="dot red"></span><span>Next sale in <b data-cd="${Date.now() + o.cooldown * 1000}">${fmtTime(o.cooldown)}</b>.</span></div>` : '';
  return `<section class="panel" id="stock-detail"><div class="p-head"><div><h2>Crew sale · ${need} cars</h2><p>Pick a buyer, then give every car a driver. You drive one.</p></div>
      <button class="btn ghost sm" data-act="dealBack"><i class="fa-solid fa-arrow-left"></i>Change cars</button></div>
    <div class="p-body pad" id="detail-body">
      <div class="offers">${opts.map(opt).join('')}</div>
      <div class="grp" style="margin:4px 0 0">Drivers</div>
      ${rows}${warn}
      <button class="btn ${ready ? 'primary' : ''} wide" data-act="dealStart" ${ready ? '' : 'disabled'}><i class="fa-solid fa-truck-fast"></i>Start crew sale · ${money(cur.total)}</button>
    </div></section>`;
}
function stockDetail(s) {
  const t = S.term, owner = isOwner(), selling = s.status !== 'stored';
  const ws = Cargo.up('workshop', t.warehouse.upgrades.workshop), hasWs = arr(ws?.categories).length > 0 || S.static.workshop.Mode === 'external';
  const ticks = arr(S.static.workshop.ScoreToRarity);
  const offers = S.offersFor === s.id ? S.offers : null;
  const ill = R(s.rarity).illegal;
  const chips = `${s.rarity !== s.base_rarity ? `${rar(s.base_rarity)}<i class="fa-solid fa-arrow-right dim" style="font-size:10px"></i>` : ''}${rar(s.rarity)}`;
  const body = `
    <div class="mini" style="grid-template-columns:repeat(4,1fr)">
      <div><span>Base value</span><b class="pos">${money(s.baseValue)}</b></div>
      <div><span>Condition</span><b>${s.condition}%</b><div class="bar-line ${s.condition < 60 ? 'red' : ''}" style="margin-top:7px"><i style="width:${s.condition}%"></i></div></div>
      <div><span>Build score</span><b>${s.score} <span class="dim" style="font-weight:300;font-size:11px">/ 100</span></b></div>
      <div><span>Repair</span><b>${s.repairCost > 0 ? money(s.repairCost) : '—'}</b></div>
    </div>
    ${ill ? `<div class="note"><span class="dot red"></span><span>Illegal vehicles keep their tier. Builds still raise the value, and <b>every sale run draws attackers</b>.</span></div>` : `<div>
      <div class="kv"><span>Rarity progress</span><span class="dim" style="font-size:11px">Model list price ${money(s.value)}</span></div>
      <div class="meter"><i style="width:${s.score}%"></i>${ticks.map((n, i) => `<span class="tick" style="left:${n}%"><span>${i + 1 > (ws?.maxRarityGain || 0) ? '<i class="fa-solid fa-lock"></i> ' : ''}+${i + 1}</span></span>`).join('')}</div>
    </div>`}
    <div class="chips">${buildChips(s.build)}</div>
    <div class="chips">
      <button class="btn primary" data-act="design" data-id="${s.id}" ${selling || !hasWs || !can('design') ? 'disabled' : ''}><i class="fa-solid fa-spray-can-sparkles"></i>${hasWs ? 'Customize in the back' : 'Design bay locked'}</button>
      <button class="btn" data-act="repair" data-id="${s.id}" ${selling || s.condition >= 100 || !can('repair') ? 'disabled' : ''}><i class="fa-solid fa-screwdriver-wrench"></i>Repair${s.repairCost > 0 ? ' · ' + money(s.repairCost) : ''}</button>
      ${can('sell') ? `<button class="btn" data-act="offers" data-id="${s.id}" ${selling ? 'disabled' : ''}><i class="fa-solid fa-handshake"></i>Find buyers</button>
      <button class="btn danger" data-act="scrap" data-id="${s.id}" ${selling ? 'disabled' : ''}><i class="fa-solid fa-recycle"></i>Scrap</button>` : ''}
    </div>
    ${insuranceRow(s, selling)}
    ${offers ? offersBlock(s, offers) : ''}`;
  return `<section class="panel" id="stock-detail"><div class="p-head"><div><h2>${esc(s.label)}</h2><p>${esc(s.plate || '')}${selling ? ' · on a sale run' : ''}</p></div><div class="chips" style="align-items:center">${chips}</div></div>
    <div class="p-body pad" id="detail-body">${body}</div></section>`;
}
function insuranceRow(s, selling) {
  const I = obj(S.static.insurance); if (!I.Enabled) return '';
  if (s.insured) return `<div class="note"><span class="dot"></span><span><b>Insured.</b> If this car is lost on a sale or seized in a raid you get ${Math.round(I.Payout * 100)}% of its value back.</span>${s.hot ? '<span class="tag hot" style="margin-left:auto"><i class="fa-solid fa-fire"></i>Hot</span>' : ''}</div>`;
  const why = s.insurable ? `Pay <b>${money(s.premium)}</b> once. Pays out <b>${Math.round(I.Payout * 100)}%</b> of its value if it's lost or seized.`
    : s.hot ? 'Hot cars (tracked or stolen) can\'t be insured.' : 'This car can\'t be insured.';
  return `<div class="note"><span class="dot ${s.insurable ? '' : 'red'}"></span><span>${why}</span><span style="flex:1"></span>
    ${s.insurable ? `<button class="btn sm" data-act="insure" data-id="${s.id}" ${selling || !can('insurance') ? 'disabled' : ''}><i class="fa-solid fa-shield-halved"></i>Insure · ${money(s.premium)}</button>` : ''}</div>`;
}
function offersBlock(s, o) {
  const wants = arr(S.static.wants);
  const wl = id => wants.find(w => w.id === id)?.label || id;
  const cd = o.cooldown > 0;
  return `<div class="kv" style="margin-top:4px"><b>Buyers bidding</b>${cd ? `<span class="tag hot"><i class="fa-solid fa-hourglass-half"></i>Next sale <span data-cd="${Date.now() + o.cooldown * 1000}">${fmtTime(o.cooldown)}</span></span>`
      : o.streak > 0 ? `<span class="tag live">+${Math.round(o.streak * 100)}% clean streak</span>` : ''}</div>
    <div class="offers">
      ${arr(o.offers).map(b => `<article class="inc ${b.hot ? 'urgent' : ''}">
        <div class="inc-top"><span class="chip ${b.hot ? 'red' : ''}">${esc(b.label)}</span><span class="ref">${b.place ? esc(b.place) + ' · ' : ''}${(b.dist / 1000).toFixed(1)} km</span></div>
        <h3>${esc(b.name)}</h3>
        <div class="offer-amt pos">${money(b.amount)}</div>
        <div class="chips">${arr(b.wants).map(w => `<span class="tag ${arr(b.met).includes(w) ? 'live' : 'off'}"><i class="fa-solid ${arr(b.met).includes(w) ? 'fa-check' : 'fa-minus'}"></i>${esc(wl(w))}</span>`).join('')}</div>
        <div class="meta"><span>${b.hot ? '<b style="color:var(--red)">Crew tailing the buyer</b>' : 'Quiet route'}</span><span style="margin-left:auto"></span>
          <button class="btn primary sm" data-act="sellStart" data-id="${s.id}" data-buyer="${b.index}" ${cd ? 'disabled' : ''}><i class="fa-solid fa-truck-fast"></i>Deliver</button></div>
      </article>`).join('')}
      <article class="inc" style="border-left-color:var(--line)">
        <div class="inc-top"><span class="chip" style="color:var(--ink-2);background:var(--raise);border-color:var(--line)">Quick export</span><span class="ref">Instant</span></div>
        <h3>Off the floor</h3>
        <div class="offer-amt">${money(o.quick)}</div>
        <p>${Math.round(S.static.quickSale * 100)}% of value. No drive, no risk, less XP.</p>
        <div class="meta"><span>No delivery</span><span style="margin-left:auto"></span><button class="btn sm" data-act="sellQuick" data-id="${s.id}"><i class="fa-solid fa-bolt"></i>Export now</button></div>
      </article>
    </div>`;
}

/* upgrades */
function upEffect(track, l) {
  if (!l) return '';
  switch (track) {
    case 'capacity': return `${l.slots} cars on the main floor`;
    case 'workshop': return `${l.name}${l.maxRarityGain ? ` · up to +${l.maxRarityGain} rarity` : ''}`;
    case 'intel': return `${Math.round(l.rollUp * 100)}% hot tips · ${Math.round(l.cooldownCut * 100)}% shorter cooldown${l.scanner ? ' · scanner' : ''}`;
    case 'contacts': return `${l.buyers} buyers · +${Math.round(l.saleBonus * 100)}% on sales`;
    case 'repair': return `${Math.round(l.costMult * 100)}% repair cost`;
    case 'lower': return l.open ? '4 illegal slots · Illegal contracts' : 'Closed off';
    case 'tracker': return l.custom ? 'Free garage strip · your own removal spot' : l.garage ? `Garage strips trackers · ${money(l.garageFee)}` : 'Tracker shops only';
  }
  return '';
}
function appUpgrades() {
  const t = S.term, u = t.warehouse.upgrades, owner = isOwner(), U = S.static.upgrades;
  const tracks = ['capacity', 'workshop', 'lower', 'intel', 'tracker', 'contacts', 'repair'].filter(k => U[k]);
  const owned = obj(u.owned_styles);
  const swatch = { basic: 'linear-gradient(135deg,#2a2e31,#15181a)', branded: 'linear-gradient(135deg,#067d74,#0fd4c4)', urban: 'linear-gradient(135deg,#1c2023,#b8262b)' };
  const card = (cfg, tally, body) => `<section class="panel"><div class="p-head"><div style="display:flex;gap:11px;align-items:center">${tile(cfg.icon.replace('fa-solid ', ''))}
    <div><h2>${esc(cfg.label)}</h2><p>${esc(cfg.desc)}</p></div></div>${tally}</div><div class="p-body pad">${body}</div></section>`;
  return head('Upgrades', owner ? 'Every upgrade is permanent for this warehouse.' : 'Only the owner can buy upgrades.', clock(money(t.stock.reduce((a, s) => a + (s.baseValue || 0), 0)), 'Stock value'))
    + `<div class="up-grid">${tracks.map(track => {
      const cfg = U[track], lv = u[track] || 0, levels = arr(cfg.levels), nxt = levels[lv + 1];
      return card(cfg, `<span class="tally">${lv + 1} / ${levels.length}</span>`, `
        <div class="pips">${levels.map((_, i) => `<i class="${i <= lv ? 'on' : ''}"></i>`).join('')}</div>
        <div class="kv"><span>Now</span><b>${upEffect(track, levels[lv])}</b></div>
        <div class="kv"><span>Next</span>${nxt ? `<b class="pos">${upEffect(track, nxt)}</b>` : '<span class="tag live">Maxed</span>'}</div>
        ${nxt && owner ? `<button class="btn primary wide" data-act="upgrade" data-track="${track}"><i class="fa-solid fa-arrow-up"></i>Upgrade · ${money(nxt.price)}</button>` : ''}`);
    }).join('')}
    ${card(U.style, '', `<div class="styles">${arr(U.style.styles).map(st => `<button class="sty ${u.style === st.id ? 'on' : ''}" ${owner ? `data-act="style" data-id="${st.id}"` : ''}>
      <i style="background:${swatch[st.id] || swatch.basic}"></i><p><b>${esc(st.label)}</b>${u.style === st.id ? 'Active' : (owned[st.id] || st.price === 0 ? 'Owned' : money(st.price))}</p></button>`).join('')}</div>`)}
    </div>`;
}

/* floor plan */
let planBox = null;   // kept for callers that reset it; each plan now fits its own spots
function planBounds(slots, area) {
  const pts = arr(slots);
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  const take = (x, y) => { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); };
  pts.forEach(s => take(s.x, -s.y));
  if (area && area.min) { take(area.min.x, -area.min.y); take(area.max.x, -area.max.y); }
  if (x0 === Infinity) return { x: 0, y: 0, w: 40, h: 24 };
  x0 -= 3.5; x1 += 3.5; y0 -= 3.5; y1 += 3.5;
  if (x1 - x0 < 24) { const c = (x0 + x1) / 2; x0 = c - 12; x1 = c + 12; }
  if (y1 - y0 < 14) { const c = (y0 + y1) / 2; y0 = c - 7; y1 = c + 7; }
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}
// Same test as Cargo.CarFits in shared/utils.lua: inside the floor and clear of props
function carFits(s, area) {
  if (!area || !area.min) return true;
  const r = (s.w || 0) * Math.PI / 180, c = Math.cos(r), n = Math.sin(r);
  for (const [ox, oy] of [[-1.15, -2.5], [1.15, -2.5], [1.15, 2.5], [-1.15, 2.5], [0, 0]]) {
    const px = s.x + ox * c - oy * n, py = s.y + ox * n + oy * c;
    if (px < area.min.x || px > area.max.x || py < area.min.y || py > area.max.y) return false;
    for (const o of arr(area.obstacles)) if (px > o.min.x - .3 && px < o.max.x + .3 && py > o.min.y - .3 && py < o.max.y + .3) return false;
  }
  return true;
}
function planArea(area) {
  if (!area || !area.min) return '';
  const box = (a, cls) => `<rect class="${cls}" x="${a.min.x}" y="${-a.max.y}" width="${a.max.x - a.min.x}" height="${a.max.y - a.min.y}"/>`;
  return box(area, 'pa-floor') + arr(area.obstacles).map(o => box(o, 'pa-obs')).join('');
}
// opts = { area, edit, sel }
function planSvg(slots, filled = 0, labels = false, pick = null, opts = {}) {
  const b = planBounds(slots, opts.area);
  const cars = arr(slots).map((s, i) => {
    const on = i < filled, del = pick && pick.has(i), sel = opts.edit && opts.sel === i, bad = opts.area && !carFits(s, opts.area);
    const fill = del || bad ? 'rgba(229,72,77,.35)' : on ? 'rgba(var(--acc),.28)' : 'rgba(255,255,255,.03)';
    const stroke = sel ? '#fff' : del || bad ? '#e5484d' : on ? 'var(--teal)' : 'rgba(255,255,255,.22)';
    const tag = opts.edit ? `data-i="${i}"` : pick ? `data-act="planPick" data-id="${i}"` : '';
    return `<g class="sp ${sel ? 'sel' : ''}" ${tag} transform="translate(${s.x.toFixed(2)},${(-s.y).toFixed(2)}) rotate(${(-(s.w || 0)).toFixed(1)})">
      <rect x="-1.05" y="-2.35" width="2.1" height="4.7" rx=".55" style="fill:${fill};stroke:${stroke}" stroke-width="${sel ? .2 : .12}"/>
      <rect x="-.8" y="-2.2" width="1.6" height=".42" rx=".15" style="fill:${on ? 'var(--teal-hi)' : 'rgba(255,255,255,.3)'}"/></g>
      ${labels ? `<text data-l="${i}" x="${s.x.toFixed(2)}" y="${(-s.y + .4).toFixed(2)}" text-anchor="middle" font-size="1.05" font-weight="600" fill="${on ? '#fff' : 'rgba(255,255,255,.4)'}" font-family="Lexend" pointer-events="none">${i + 1}</text>` : ''}`;
  }).join('');
  return `<svg viewBox="${b.x} ${b.y} ${b.w} ${b.h}" preserveAspectRatio="xMidYMid meet">${planArea(opts.area)}${cars}</svg>`;
}

/* floor plan editor: drag spots, scroll to turn, select to remove */
let planDrag = null;
function planSlots() { return S.planEdit ? S.planEdit.slots : arr(S.term.layout.slots); }
function planEditStart() {
  if (!S.planEdit) S.planEdit = { slots: clone(arr(S.term.layout.slots)), sel: -1, dirty: false };
  return S.planEdit;
}
function svgPt(svg, e) {
  const pt = svg.createSVGPoint(); pt.x = e.clientX; pt.y = e.clientY;
  return pt.matrixTransform(svg.getScreenCTM().inverse());
}
function planPlace(i) {
  const s = S.planEdit.slots[i], root = document.getElementById('planEd'); if (!root) return;
  const g = root.querySelector(`g.sp[data-i="${i}"]`), t = root.querySelector(`text[data-l="${i}"]`);
  if (g) {
    g.setAttribute('transform', `translate(${s.x.toFixed(2)},${(-s.y).toFixed(2)}) rotate(${(-(s.w || 0)).toFixed(1)})`);
    const ok = carFits(s, S.term.layout.area), r = g.querySelector('rect');
    if (r) { r.style.stroke = ok ? '#fff' : '#e5484d'; r.style.fill = ok ? 'rgba(var(--acc),.18)' : 'rgba(229,72,77,.35)'; }
  }
  if (t) { t.setAttribute('x', s.x.toFixed(2)); t.setAttribute('y', (-s.y + .4).toFixed(2)); }
}
document.addEventListener('pointerdown', e => {
  const g = e.target.closest && e.target.closest('#planEd g.sp'); if (!g || !can('layout')) return;
  const ed = planEditStart(), i = num(g.dataset.i), s = ed.slots[i]; if (!s) return;
  const p = svgPt(g.ownerSVGElement, e);
  planDrag = { i, svg: g.ownerSVGElement, ox: p.x - s.x, oy: p.y + s.y, sx: e.clientX, sy: e.clientY, moved: false };
  ed.sel = i;
  e.preventDefault();
});
document.addEventListener('pointermove', e => {
  if (!planDrag) return;
  if (!planDrag.moved && Math.hypot(e.clientX - planDrag.sx, e.clientY - planDrag.sy) < 3) return;
  planDrag.moved = true;
  const p = svgPt(planDrag.svg, e), s = S.planEdit.slots[planDrag.i];
  s.x = Math.round((p.x - planDrag.ox) * 100) / 100;
  s.y = Math.round(-(p.y - planDrag.oy) * 100) / 100;
  S.planEdit.dirty = true;
  planPlace(planDrag.i);
});
document.addEventListener('pointerup', () => { if (!planDrag) return; planDrag = null; refreshBodies(); });
document.addEventListener('wheel', e => {
  const g = e.target.closest && e.target.closest('#planEd g.sp'); if (!g || !can('layout')) return;
  e.preventDefault();
  const ed = planEditStart(), i = num(g.dataset.i), s = ed.slots[i]; if (!s) return;
  s.w = (((s.w || 0) + (e.deltaY > 0 ? 1 : -1) * (e.shiftKey ? 5 : 15)) % 360 + 360) % 360;
  ed.sel = i; ed.dirty = true;
  planPlace(i);
}, { passive: false });

function appFloorplan() {
  const t = S.term, L = t.layout, owner = can('layout'), w = t.warehouse, ed = S.planEdit;
  const cur = arr(L.presets).find(p => p.id === L.preset);
  const mode = L.custom ? 'Your own layout' : cur ? cur.label : 'Server default';
  const cmd = S.static.layoutCommand || 'cargolayout';
  const slots = planSlots(), sel = ed ? ed.sel : -1, bad = slots.filter(s => !carFits(s, L.area)).length;
  const bar = !owner ? '' : `<div class="plan-bar">
      <span class="dim" style="font-size:11.5px;flex:1">${ed && ed.dirty ? `<b class="white">Unsaved changes</b> · ${slots.length} spots${bad ? ` · <b style="color:var(--red)">${bad} clip the walls or props</b>` : ''}` : 'Drag a spot to move it · scroll on it to turn · click to select'}</span>
      ${sel >= 0 ? `<button class="btn icon ghost" data-act="planTurn" data-id="-15" title="Turn left"><i class="fa-solid fa-rotate-left"></i></button>
        <button class="btn icon ghost" data-act="planTurn" data-id="15" title="Turn right"><i class="fa-solid fa-rotate-right"></i></button>
        <button class="btn sm danger" data-act="planDrop" ${slots.length > 1 ? '' : 'disabled'}><i class="fa-solid fa-trash"></i>Remove #${sel + 1}</button>` : ''}
      <button class="btn sm" data-act="planAdd" ${slots.length < L.max ? '' : 'disabled'}><i class="fa-solid fa-plus"></i>Add</button>
      ${ed && ed.dirty ? `<button class="btn sm" data-act="planDiscard">Discard</button><button class="btn sm primary" data-act="planSave"><i class="fa-solid fa-floppy-disk"></i>Save</button>` : ''}
    </div>`;
  return head('Floor Plan', `Choose how your cars sit on the main floor, up to ${L.max} spots.`, clock(mode, `${slots.length} spots · ${w.stockCount} cars parked`))
    + `<div class="cols even" style="grid-template-columns:1.6fr 1fr">
      ${panel('Current floor', owner ? 'Drag, turn and remove spots right here' : 'Top-down view · teal spots are taken', '', `<div class="plan ${owner ? 'edit' : ''}" id="${owner ? 'planEd' : ''}" style="height:300px">${planSvg(slots, w.stockCount, true, null, { area: L.area, edit: owner, sel })}</div>${bar}`, { pad: true })}
      ${panel('Your own layout', 'Walk the floor and drop every spot yourself', '', `
        <div class="note"><span class="dot"></span><span>The laptop closes and a ghost car follows where you look. <b>E</b> place · <b>SCROLL</b> rotate · <b>Z</b> undo · <b>ENTER</b> save.</span></div>
        <div class="kv"><span>Spots allowed</span><b>${L.max}</b></div>
        <div class="kv"><span>Also works from the floor</span><b>/${esc(cmd)}</b></div>
        <div class="kv"><span>Red outline</span><b>Hits a wall or prop</b></div>
        <button class="btn primary wide" data-act="layoutCustom" ${owner ? '' : 'disabled'}><i class="fa-solid fa-location-crosshairs"></i>Place my own spots</button>
        <button class="btn wide" data-act="layoutReset" ${owner && (L.custom || L.preset) ? '' : 'disabled'}><i class="fa-solid fa-rotate-left"></i>Back to server default</button>`, { pad: true })}
    </div>
    <div class="grp" style="margin:0">Presets</div>
    <div class="pl-grid">${arr(L.presets).map(p => {
      const on = !L.custom && L.preset === p.id;
      return `<button class="pl ${on ? 'on' : ''}" ${owner && !on ? `data-act="layoutPreset" data-id="${esc(p.id)}"` : ''}>
        <div class="plan">${planSvg(p.slots, 0, false, null, { area: L.area })}</div>
        <div class="kv"><b>${esc(p.label)}</b>${on ? '<span class="tag live">Active</span>' : `<span class="dim" style="font-size:11px">${arr(p.slots).length} spots${p.admin ? ' · server' : ''}</span>`}</div></button>`;
    }).join('')}</div>`;
}

/* scanner */
function appScanner() {
  const t = S.term, hot = arr(t.hot);
  if (!t.warehouse.scanner) return head('Scanner', 'Picks up tracked cars other players are moving.')
    + empty('fa-satellite-dish', 'Scanner offline', 'Upgrade the Intel Network to level 3 to see tracked cars on the move.')
    + `<div><button class="btn primary" data-act="tab" data-id="upgrades"><i class="fa-solid fa-layer-group"></i>Open upgrades</button></div>`;
  const blip = h => { const a = (h.id * 137.5) % 360 * Math.PI / 180, r = 18 + (h.id * 53) % 26; return `<i style="left:${50 + Math.cos(a) * r}%;top:${50 + Math.sin(a) * r}%"></i>`; };
  return head('Scanner', 'Tracked cars other crews are moving right now. Get in the driver seat and it is yours.',
      `<button class="btn" data-act="scanRefresh"><i class="fa-solid fa-rotate"></i>Rescan</button>`)
    + `<div style="display:flex;gap:18px;align-items:center">
        <div class="radar">${hot.map(blip).join('')}</div>
        <div style="flex:1;display:flex;flex-direction:column;gap:8px">
          <div class="kv"><span>Signals</span><b>${hot.length}</b></div>
          <div class="kv"><span>Source</span><b>Live tracker pings</b></div>
          <div class="note"><span class="dot red"></span><span>Steal it into <b>your warehouse</b>, or take it to a <b>chop shop</b> for quick cash.</span></div>
        </div></div>`
    + panel('Signals', hot.length ? 'Nearest first is up to you' : 'Quiet out there', '', hot.length ? hot.map(h => `
      <div class="row stripe" style="${rv(h.rarity)}"><div class="row-txt"><b>${esc(h.label)}</b><span>${esc(R(h.rarity).label)} · tracker on</span></div>
        ${h.illegal ? '<span class="flag ill"><i class="fa-solid fa-skull"></i>Illegal</span>' : ''}
        <button class="btn primary sm" data-act="waypoint" data-x="${h.x}" data-y="${h.y}"><i class="fa-solid fa-location-arrow"></i>Waypoint</button></div>`).join('')
      : empty('fa-tower-broadcast', 'No tracked cars', 'Signals show up when someone drives off with the tracker still on.'));
}

/* tracker tools */
function appTracker() {
  const t = S.term, w = t.warehouse, lv = w.upgrades.tracker || 0, levels = arr(S.static.upgrades.tracker?.levels), L2 = levels[1] || {};
  const nxt = levels[lv + 1];
  const risk = [['fa-tower-broadcast', 'Police live track', 'Officers on duty see the car move in real time.'],
    ['fa-skull-crossbones', 'Attack waves', 'Crews home in on the signal while it is on.'],
    ['fa-user-ninja', 'Hijackers', 'Players with the scanner can take it into their own warehouse.'],
    ['fa-gears', 'Chop shops', 'Thieves can strip it for cash. You lose the car.']];
  const method = (on, icon, title, sub, body) => `<section class="panel ${on ? '' : 'off'}"><div class="p-head"><div style="display:flex;gap:11px;align-items:center">${tile(icon, on ? '' : 'off')}
    <div><h2>${title}</h2><p>${sub}</p></div></div>${on ? '<span class="tag live">Ready</span>' : '<span class="tag off"><i class="fa-solid fa-lock"></i>Locked</span>'}</div><div class="p-body pad">${body}</div></section>`;
  return head('Tracker Tools', 'Some cars come with a tracker. Kill it before it brings trouble to your door.',
      nxt && isOwner() ? `<button class="btn primary" data-act="tab" data-id="upgrades"><i class="fa-solid fa-arrow-up"></i>Upgrade · ${money(nxt.price)}</button>` : '<span class="tag live">Tracker Workshop maxed</span>')
    + panel('If you leave it on', 'What a live tracker does', '', `<div class="risk">${risk.map(r => `<div><i class="fa-solid ${r[0]}"></i><b>${r[1]}</b><span>${r[2]}</span></div>`).join('')}</div>`, { pad: true })
    + `<div class="trk">
      ${method(true, 'fa-screwdriver-wrench', 'Tracker shops', 'Always available', `<div class="kv"><span>Where</span><b>Shop blips on the map</b></div><div class="kv"><span>Cost</span><b>Free</b></div>`)}
      ${method(lv >= 1, 'fa-warehouse', 'Garage strip', 'Tracker Workshop level 2', `<div class="kv"><span>Where</span><b>Drive it home</b></div><div class="kv"><span>Fee</span><b>${lv >= 2 ? 'Free' : money(L2.garageFee || 0)}</b></div>`)}
      ${method(lv >= 2, 'fa-location-crosshairs', 'Your own spot', 'Tracker Workshop level 3', `
        <div class="kv"><span>Spot</span>${w.trackerSpot ? '<b class="pos">Placed</b>' : '<b>Not placed</b>'}</div>
        <button class="btn wide" data-act="trackerHowTo" ${lv >= 2 && isOwner() ? '' : 'disabled'}><i class="fa-solid fa-circle-info"></i>${w.trackerSpot ? 'Move my spot' : 'How to place it'}</button>`)}
    </div>`;
}

/* ledger */
function appLedger() {
  const l = S.term.ledger;
  const sales = l.filter(x => x.kind === 'sale' || x.kind === 'export' || x.kind === 'chop').slice(0, 24).reverse();
  const max = Math.max(1, ...sales.map(x => x.amount));
  const net = l.reduce((a, x) => a + (x.amount || 0), 0);
  const table = l.length ? `<table><thead><tr><th>Entry</th><th>Rarity</th><th>When</th><th class="r-al">Amount</th></tr></thead><tbody>
    ${l.map(x => { const k = KIND[x.kind] || ['fa-circle', 'off', x.kind]; return `<tr><td><b>${k[2]}</b> · ${esc(x.label || '')}${x.data && x.data.reason ? ` <span class="dim">· ${esc(x.data.reason)}</span>` : ''}</td>
      <td>${x.rarity ? rar(x.rarity) : ''}</td><td>${ago(x.t)}</td>
      <td class="r-al">${x.amount ? `<b class="${x.amount > 0 ? 'pos' : ''}">${x.amount > 0 ? '+' : '−'}${money(Math.abs(x.amount))}</b>` : '—'}</td></tr>`; }).join('')}
    </tbody></table>` : empty('fa-receipt', 'No entries yet');
  return head('Ledger', 'Every contract, design, repair and sale for this warehouse.', clock(`${net >= 0 ? '+' : '−'}${money(Math.abs(net))}`, 'Net across these entries'))
    + panel('Recent sales', `${sales.length} sales`, '', sales.length ? `<div class="spark">${sales.map(x => `<i style="height:${(x.amount / max) * 100}%" title="${money(x.amount)}"></i>`).join('')}</div>` : '<span class="dim" style="font-size:12px">No sales yet.</span>', { pad: true })
    + panel('Entries', 'Last 40', '', `<div style="padding:4px 6px">${table}</div>`);
}

/* leaderboard */
function appLeaderboard() {
  const segs = `<div class="seg"><button class="${S.lbTab === 'earned' ? 'on' : ''}" data-act="lbTab" data-id="earned"><i class="fa-solid fa-sack-dollar"></i>Top earners</button><button class="${S.lbTab === 'levels' ? 'on' : ''}" data-act="lbTab" data-id="levels"><i class="fa-solid fa-ranking-star"></i>Top levels</button></div>`;
  if (!S.lb) {
    S.lb = 'loading';
    post('leaderboard').then(r => { S.lb = r || { earned: [], levels: [] }; refresh(); });
  }
  if (S.lb === 'loading') return head('Leaderboard', 'The best on the server.', segs) + `<div class="panel"><div class="p-body">${'<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:52%"></div><div class="sk" style="height:7px;width:32%;margin-top:7px"></div></div></div>'.repeat(5)}</div></div>`;
  const rows = arr(S.lb[S.lbTab]);
  return head('Leaderboard', 'The best on the server.', segs)
    + panel(S.lbTab === 'earned' ? 'Top earners' : 'Top levels', 'Top 15', '', rows.length ? rows.map((r, i) => `
      <div class="row"><div class="av ${i === 0 ? 'teal' : ''}">${i + 1}</div><div class="row-txt"><b>${esc(r.name || 'Unknown')}</b><span>Level ${r.level} · ${r.sourced} sourced · ${r.sold} sold · best ${money(r.best_sale)}</span></div>
      <div class="row-end"><b class="${i === 0 ? 'pos' : ''}">${S.lbTab === 'earned' ? money(r.earned) : 'Level ' + r.level}</b><span>${S.lbTab === 'earned' ? 'earned' : Number(r.xp).toLocaleString() + ' XP'}</span></div></div>`).join('')
      : empty('fa-ranking-star', 'No one yet'));
}

/* associates */
const PERM_LABEL = { contracts: 'Contracts', crewjob: 'Crew jobs', sell: 'Sell', design: 'Design', repair: 'Repair', wash: 'Wash', upgrades: 'Upgrades', layout: 'Floor plan', crew: 'Manage crew', insurance: 'Insurance', bribe: 'Bribes' };
function appAssociates() {
  const t = S.term, w = t.warehouse, owner = isOwner(), list = arr(w.associates), roles = arr(S.static.roles);
  const role = id => roles.find(r => r.id === id) || roles[roles.length - 1] || { label: 'Crew', icon: 'fa-solid fa-user' };
  return head('Associates', `Give each one a role. Anyone near the drop when you sell gets a ${Math.round(S.static.associateCut * 100)}% cut.`,
      can('crew') ? `<button class="btn primary" data-act="assocPick" ${list.length >= w.maxAssociates ? 'disabled' : ''}><i class="fa-solid fa-user-plus"></i>Add nearby player</button>` : '')
    + panel('Crew', `${list.length} of ${w.maxAssociates}`, '', list.length ? list.map(a => { const r = role(a.role); return `
      <div class="row"><div class="av" style="color:${esc(r.color || 'inherit')}"><i class="${esc(r.icon)}"></i></div><div class="row-txt"><b>${esc(a.name)}</b><span>${esc(r.label)}</span></div>
      ${owner ? `<select class="input sm" data-role="${esc(a.identifier)}" style="width:150px">${roles.map(x => `<option value="${esc(x.id)}" ${x.id === r.id ? 'selected' : ''}>${esc(x.label)}</option>`).join('')}</select>` : `<span class="tag live">${esc(r.label)}</span>`}
      ${can('crew') && !(role(a.role).perms || {}).crew || owner ? `<button class="btn danger sm" data-act="assocRemove" data-id="${esc(a.identifier)}"><i class="fa-solid fa-user-minus"></i>Remove</button>` : ''}</div>`; }).join('')
      : empty('fa-user-group', 'No associates yet', `Add up to ${w.maxAssociates} trusted players.`))
    + panel('Roles', 'What each role can do (the owner can do everything)', '', `<div style="padding:4px 6px"><table><thead><tr><th>Role</th><th>Can</th></tr></thead><tbody>
      ${roles.map(r => `<tr><td><b><i class="${esc(r.icon)}" style="color:${esc(r.color || 'inherit')};margin-right:6px"></i>${esc(r.label)}</b></td>
        <td>${Object.keys(obj(r.perms)).filter(k => r.perms[k]).map(k => `<span class="tag off">${esc(PERM_LABEL[k] || k)}</span>`).join(' ')}</td></tr>`).join('')}
      </tbody></table></div>`)
    + `<div class="note"><span class="dot"></span><span>Anyone else can <b>knock</b> at your door. You get a prompt and decide who comes in.</span></div>`;
}

/* settings (owner preferences, saved on the warehouse) */
const swd = (on, act, id, dis) => `<button class="sw ${on ? 'on' : ''}" data-act="${act}" data-id="${esc(id)}" ${dis ? 'disabled' : ''}><i></i></button>`;
function appSettings() {
  const p = S.prefs, o = prefOpts(), owner = isOwner(), dis = owner ? '' : 'disabled', w = S.term.warehouse;
  const ch = S.term.radioChannel;
  return head('Settings', owner ? 'How your laptop looks and behaves. Saved on your warehouse, so your crew sees it too.' : 'Set by the owner. Only they can change these.',
      clock(`v${esc(S.static.version)}`, 'Installed version'))
    + `<div class="cols even">
      ${panel('Accent colour', 'Laptop, HUD, design bay and placement markers', '', `<div class="sw-acc">${arr(o.accents).map(a => `<button class="${p.accent === a.id ? 'on' : ''}" style="background:${esc(a.color)}" title="${esc(a.label)}" data-act="pref" data-k="accent" data-v="${esc(a.id)}" ${dis}></button>`).join('')}</div>`, { pad: true })}
      ${panel('Laptop finish', 'The body around the screen', '', `<div class="sw-fin">${arr(o.finishes).map(f => `<button class="${p.finish === f.id ? 'on' : ''}" data-act="pref" data-k="finish" data-v="${esc(f.id)}" ${dis}><i style="background:linear-gradient(160deg,${esc(f.a)},${esc(f.b)})"></i>${esc(f.label)}</button>`).join('')}</div>`, { pad: true })}
    </div>`
    + panel('Wallpaper', 'Desktop background', '', `<div class="walls">${arr(o.wallpapers).map(wp => `<button class="${p.wallpaper === wp.id ? 'on' : ''}" data-act="pref" data-k="wallpaper" data-v="${esc(wp.id)}" ${dis}><div class="lt-wall" data-w="${esc(wp.id)}"></div><span>${esc(wp.label)}</span></button>`).join('')}</div>`, { pad: true })
    + `<div class="cols even">
      ${panel('System', 'Laptop behaviour', '', `
        <div class="sw-line"><span>24-hour clock</span>${swd(p.clock === '24', 'prefClock', 'clock', !owner)}</div>
        <div class="sw-line"><span>Skip the boot and sign-in screens</span>${swd(p.fastboot, 'prefToggle', 'fastboot', !owner)}</div>
        <div class="sw-line"><span>Click and notification sounds</span>${swd(p.sounds, 'prefToggle', 'sounds', !owner)}</div>
        <div class="sw-line"><span>See-through windows</span>${swd(p.glass, 'prefToggle', 'glass', !owner)}</div>`, { pad: true })}
      ${panel('Crew radio', S.static.radio ? 'Everyone on the crew joins one channel when a job starts' : 'Turned off by the server', '', S.static.radio ? `
        <div class="sw-line"><span>Put my crew on the radio during jobs</span>${swd(p.radio, 'prefToggle', 'radio', !owner)}</div>
        <div class="kv"><span>Channel</span><b>${ch ? 'CH ' + esc(ch) : '—'}</b></div>
        <div class="kv"><span>Right now</span>${S.radio ? `<span class="radio-chip"><i class="fa-solid fa-walkie-talkie"></i>Live on CH ${esc(S.radio)}</span>` : '<b class="dim">Not on a job</b>'}</div>
        <div class="dim" style="font-size:11px;line-height:1.5">You go back to your old channel when the job ends.</div>`
        : empty('fa-walkie-talkie', 'Crew radio is off', 'The server owner can enable it in the config.'), { pad: true })}
    </div>
    <div class="cols even">
      ${panel('Mission HUD', 'Drag it anywhere on screen', '', `<div class="kv"><span>Command</span><b>/${esc(S.static.hudCommand || 'cargohud')}</b></div>
        <button class="btn wide" data-act="hudMove"><i class="fa-solid fa-up-down-left-right"></i>Move HUD now</button>`, { pad: true })}
      ${panel('Warehouse', esc(w.name), '', `<div class="kv"><span>Owner</span><b>${esc(w.owner || '')}</b></div>
        <button class="btn danger wide" data-act="exit"><i class="fa-solid fa-door-open"></i>Leave warehouse</button>`, { pad: true })}
    </div>`;
}
async function savePref(k, v) {
  if (!isOwner()) { toast('Owner only', 'Only the owner can change these.', false); return; }
  const next = { ...S.prefs, [k]: v };
  applyPrefs(next); refreshBodies();
  const r = await post('prefs', next);
  if (r && r.profile) { S.term = r; S.myPrefs = { ...obj(r.prefs) }; applyPrefs(r.prefs); refreshBodies(); renderChrome(); }
  else toast('Not saved', 'Try again in a moment.', false);
}

/* ═══════════════════════════════════════════════════════════
   ADMIN (laptop app + standalone /cargoadmin panel)
   ═══════════════════════════════════════════════════════════ */
function renderTerminal() {
  $('#term-root').innerHTML = `
    <div class="bar"><div class="bar-brand"><div class="mark"></div><div class="bar-name"><div class="title-txt">Cargo Admin</div><div class="sub">Server tools</div></div></div>
      <div class="bar-mid"><span class="dot"></span><p>Changes apply <b>live</b> · no restart needed</p><span class="ver">v${esc(S.static.version)}</span></div>
      <button class="pill-close" data-act="close">Close</button></div>
    <div class="body"><nav class="side">
      <div class="grp" style="margin-top:2px">Manage</div>
      ${ADMIN_TABS.map(k => `<button class="nav ${S.adminTab === k.id ? 'on' : ''}" data-act="adminTab" data-id="${k.id}"><i class="fa-solid ${k.icon}"></i>${k.label}</button>`).join('')}
    </nav><main class="main" id="t-body">${tabAdmin(true)}</main></div>
    <div class="statusbar">${keys([['ESC', 'Close'], ['/cargoslots', 'Interior layout']])}</div>`;
}

function tabAdmin(standalone) {
  if (!S.admin) {
    S.admin = 'loading';
    post('adminData').then(r => { S.admin = r || null; refresh(); });
  }
  if (S.admin === 'loading' || !S.admin) return head('Admin', 'Loading server data…') + `<div class="panel"><div class="p-body">${'<div class="skel"><div class="sk circ"></div><div style="flex:1"><div class="sk" style="height:9px;width:52%"></div></div></div>'.repeat(4)}</div></div>`;
  const a = S.admin, tot = obj(a.totals);
  const segs = standalone ? clock(money(tot.earned), `${tot.sold || 0} sold · ${tot.sourced || 0} sourced`)
    : `<div class="seg">${ADMIN_TABS.map(k => `<button class="${S.adminTab === k.id ? 'on' : ''}" data-act="adminTab" data-id="${k.id}"><i class="fa-solid ${k.icon}"></i>${k.label}</button>`).join('')}</div>`;
  const title = standalone ? (ADMIN_TABS.find(k => k.id === S.adminTab)?.label || 'Admin') : 'Admin';
  const rarList = arr(a.rarities).length ? arr(a.rarities) : allRar().map(r => r.id);
  const rarOpts = sel => rarList.map(id => `<option value="${id}" ${sel === id ? 'selected' : ''}>${esc(R(id).label)}</option>`).join('');
  const v4 = c => c && c.x !== undefined && c.x !== null ? `${Number(c.x).toFixed(2)}, ${Number(c.y).toFixed(2)}, ${Number(c.z).toFixed(2)}${c.w !== undefined && c.w !== null ? ` <span class="dim">· ${Number(c.w).toFixed(1)}°</span>` : ''}` : '<span class="dim">—</span>';

  if (S.adminTab === 'vehicles') {
    const f = S.vForm;
    return head(title, 'Default cars plus anything you add. Addon models work too. Illegal cars only spawn for Illegal contracts.', segs)
      + panel(f.editing ? `Edit ${esc(f.model)}` : 'Add vehicle', 'Saved to the database, live right away', '', `
        <div class="form" style="grid-template-columns:1.2fr 1.2fr 1fr 1fr auto">
          <div class="field"><label>Spawn name</label><input data-form="v" data-k="model" value="${esc(f.model || '')}" ${f.editing ? 'readonly' : ''} placeholder="sultanrs"></div>
          <div class="field"><label>Label</label><input data-form="v" data-k="label" value="${esc(f.label || '')}" placeholder="Sultan RS"></div>
          <div class="field"><label>Rarity</label><select data-form="v" data-k="rarity">${rarOpts(f.rarity || 'common')}</select></div>
          <div class="field"><label>Base value</label><input type="number" data-form="v" data-k="value" value="${esc(f.value || '')}" placeholder="50000"></div>
          <div style="display:flex;gap:8px">${f.editing ? `<button class="btn" data-act="vCancel">Cancel</button>` : ''}<button class="btn primary" data-act="vSave"><i class="fa-solid fa-floppy-disk"></i>Save</button></div>
        </div>`, { pad: true })
      + panel('Vehicle pool', `${arr(a.vehicles).length} models`, '', `<div style="padding:4px 6px"><table><thead><tr><th>Model</th><th>Label</th><th>Rarity</th><th>Value</th><th>Source</th><th>On</th><th></th></tr></thead><tbody>
        ${arr(a.vehicles).map(v => `<tr><td>${esc(v.model)}</td><td><b>${esc(v.label)}</b></td><td>${rar(v.rarity)}</td><td>${money(v.value)}</td>
          <td><span class="tag ${v.custom ? 'live' : 'off'}">${v.custom ? (v.override ? 'Override' : 'Custom') : 'Default'}</span></td>
          <td>${sw(v.enabled, 'vToggle', v.model)}</td>
          <td class="r-al" style="white-space:nowrap"><button class="btn icon ghost" data-act="vEdit" data-id="${esc(v.model)}"><i class="fa-solid fa-pen"></i></button>
          ${v.custom ? `<button class="btn icon danger" data-act="vDelete" data-id="${esc(v.model)}" title="${v.override ? 'Revert to default' : 'Delete'}"><i class="fa-solid ${v.override ? 'fa-rotate-left' : 'fa-trash'}"></i></button>` : ''}</td></tr>`).join('')}
        </tbody></table></div>`);
  }
  if (S.adminTab === 'locations') {
    const f = S.lForm, ready = f.door && f.garage && f.spawn && f.name;
    const pts = [
      ['door', 'Front door', 'Walk up here to Enter or Knock. Face the door.', 'fa-door-closed'],
      ['garage', 'Garage entrance', 'Drive a sourced car here to store it.', 'fa-warehouse'],
      ['garageExit', 'Garage exit', 'Where you come out with "Leave through the garage". Optional.', 'fa-right-from-bracket'],
      ['spawn', 'Sale car spawn', 'The car you sell waits here. Face the road.', 'fa-car-side'],
    ];
    return head(title, 'Warehouses players buy from a broker. Every one you add shows at every broker straight away. Many players can own the same one, each in a private bucket.', segs)
      + panel(f.id ? `Edit warehouse #${f.id}` : 'Add a warehouse', 'Name it, price it, then place its four points in the world', `<button class="btn ghost" data-act="lImport" title="Re-read Config.SeedWarehouses"><i class="fa-solid fa-file-import"></i>Import from config</button>`, `
        <div class="form" style="grid-template-columns:1.6fr 1fr">
          <div class="field"><label>Name</label><input data-form="l" data-k="name" value="${esc(f.name || '')}" placeholder="Cypress Flats"></div>
          <div class="field"><label>Price</label><input type="number" data-form="l" data-k="price" value="${esc(f.price ?? '')}" placeholder="1000000"></div>
        </div>
        <table><tbody>${pts.map(([k, l, d, ic]) => `<tr class="pt-row"><td style="width:34px">${tile(ic, f[k] ? '' : 'off')}</td><td class="nm"><b>${l}</b><span>${d}</span></td>
          <td>${v4(f[k])}</td><td class="r-al" style="white-space:nowrap">
          <button class="btn sm ${f[k] ? '' : 'primary'}" data-act="lPlace" data-id="${k}"><i class="fa-solid fa-location-crosshairs"></i>${f[k] ? 'Move' : 'Place'}</button></td></tr>`).join('')}</tbody></table>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <button class="btn" data-act="lPlace" data-id="all"><i class="fa-solid fa-list-ol"></i>Place all in order</button>
          ${f.id || f.name ? `<button class="btn" data-act="lCancel">Clear</button>` : ''}
          <button class="btn primary" data-act="lSave" ${ready ? '' : 'disabled'}><i class="fa-solid fa-floppy-disk"></i>${f.id ? 'Save changes' : 'Add warehouse'}</button></div>`, { pad: true })
      + panel('Warehouses', `${arr(a.locations).length} total`, '', `<div style="padding:4px 6px"><table><thead><tr><th>#</th><th>Name</th><th>Price</th><th>Front door</th><th>Owners</th><th>On</th><th></th></tr></thead><tbody>
        ${arr(a.locations).map(l => `<tr><td>${l.id}</td><td><b>${esc(l.name)}</b></td><td>${money(l.price)}</td><td>${v4(l.door)}</td><td>${l.owners}</td><td>${sw(l.enabled, 'lToggle', l.id)}</td>
          <td class="r-al" style="white-space:nowrap"><button class="btn icon ghost" data-act="lTp" data-id="${l.id}" title="Teleport"><i class="fa-solid fa-person-walking-arrow-right"></i></button>
          <button class="btn icon ghost" data-act="lEdit" data-id="${l.id}" title="Edit"><i class="fa-solid fa-pen"></i></button>
          <button class="btn icon danger" data-act="lDelete" data-id="${l.id}" title="Delete"><i class="fa-solid fa-trash"></i></button></td></tr>`).join('')}
        </tbody></table></div>`)
      + `<div class="note"><span class="dot"></span><span>Placing closes the panel. Aim with your camera, <b>SCROLL</b> to rotate, <b>E</b> to place, and the panel comes back. The inside is set up in the <b>Interior</b> tab.</span></div>`;
  }
  if (S.adminTab === 'interior') {
    const i = obj(a.interior), set = obj(a.interiorSet), h = obj(a.here), low = obj(i.lower);
    const rows = [
      ['entry', 'Arrival point', 'Where people appear inside', 'main', i.entry],
      ['exit', 'Exit door', 'Third-eye here to leave', 'main', i.exit],
      ['laptop', 'Laptop', 'The desk the laptop sits on', 'main', i.laptop],
      ['design', 'Design bay', 'Where cars are customized', 'main', i.design],
    ];
    const inside = !!h.inside;
    const status = inside
      ? `<div class="note"><span class="dot"></span><span>${h.preview ? 'You are in the <b>setup copy</b>.' : 'You are <b>inside a warehouse</b>.'} Aim with your camera: points show a <b>cylinder and a line</b>, car spots a <b>ghost car</b>. Scroll to rotate, <b>E</b> to place.</span></div>`
      : `<div class="note"><span class="dot red"></span><span>Open a private, empty copy of the interior to set it up. Leave through the exit door when you are done.</span><span style="flex:1"></span>
          <button class="btn primary" data-act="iPreview"><i class="fa-solid fa-person-walking-arrow-right"></i>Open setup copy</button></div>`;
    return head(title, 'Every warehouse shares this interior. Owners can still pick their own floor layout.', segs)
      + status
      + panel('Points', 'Doors, laptop and design bay · the stairs to the lower level are part of the interior', '', `<div style="padding:4px 6px"><table><thead><tr><th>Point</th><th>Floor</th><th>Position</th><th>Source</th><th></th></tr></thead><tbody>
        ${rows.map(([k, l, d, f, c]) => `<tr class="pt-row"><td class="nm"><b>${l}</b><span>${d}</span></td>
          <td><span class="tag ${f === 'lower' ? 'hot' : 'off'}">${f === 'lower' ? 'Lower' : 'Main'}</span></td><td>${v4(c)}</td>
          <td><span class="tag ${set[k] ? 'live' : 'off'}">${set[k] ? 'Placed' : 'Default'}</span></td>
          <td class="r-al" style="white-space:nowrap">${set[k] ? `<button class="btn icon ghost" data-act="iReset" data-id="${k}" title="Back to default"><i class="fa-solid fa-rotate-left"></i></button>` : ''}
            <button class="btn sm ${inside ? 'primary' : ''}" data-act="iPlace" data-id="${k}" ${inside ? '' : 'disabled'}><i class="fa-solid fa-location-crosshairs"></i>Place</button></td></tr>`).join('')}
        </tbody></table></div>`)
      + `<div class="cols even" style="grid-template-columns:1fr 1fr 1fr">
        ${panel('Main floor spots', `${arr(i.slots).length} of ${S.static.layoutMax || 32} · default for every warehouse`, set.slots ? `<button class="btn icon ghost" data-act="iReset" data-id="slots" title="Back to default"><i class="fa-solid fa-rotate-left"></i></button>` : '', `
          <div class="plan" style="height:190px">${planSvg(i.slots, 0, true)}</div>
          <div class="field"><label>Also save as a preset owners can pick (optional)</label><input class="input" id="i-preset" placeholder="e.g. Showroom"></div>
          <button class="btn ${inside ? 'primary' : ''} wide" data-act="iSpots" data-id="main" ${inside ? '' : 'disabled'}><i class="fa-solid fa-car-side"></i>Place spots</button>`, { pad: true })}
        ${panel('Floor area & props', `Presets fit inside the dashed box and skip the ${arr(obj(a.floor).obstacles).length} red area${arr(obj(a.floor).obstacles).length === 1 ? '' : 's'}`, set.floor ? `<button class="btn icon ghost" data-act="iReset" data-id="floor" title="Back to default"><i class="fa-solid fa-rotate-left"></i></button>` : '', `
          <div class="plan" style="height:190px">${planSvg(arr(i.slots), 0, false, null, { area: a.floor })}</div>
          <div class="note"><span class="dot"></span><span>Walk to one corner, <b>E</b>, then the opposite corner, <b>E</b>. Mark shelves, pillars and parked props as obstacles.</span></div>
          <div class="row-btns" style="display:flex;gap:8px">
            <button class="btn ${inside ? 'primary' : ''}" style="flex:1" data-act="iFloor" data-id="floor" ${inside ? '' : 'disabled'}><i class="fa-solid fa-vector-square"></i>Floor area</button>
            <button class="btn" style="flex:1" data-act="iFloor" data-id="obstacle" ${inside ? '' : 'disabled'}><i class="fa-solid fa-cubes"></i>Add obstacle</button>
            <button class="btn icon danger" data-act="iFloorClear" title="Clear obstacles"><i class="fa-solid fa-trash"></i></button></div>`, { pad: true })}
        ${panel('Illegal spots downstairs', 'Always 4 · move them, never remove them', set.lowerSlots ? `<button class="btn icon ghost" data-act="iReset" data-id="lowerSlots" title="Back to default"><i class="fa-solid fa-rotate-left"></i></button>` : '', `
          <div class="plan" style="height:190px">${planSvg(low.slots, 0, true)}</div>
          <div class="note"><span class="dot red"></span><span>Spot 1 to 4 in order. <b>E</b> moves the red one, <b>Z</b> steps back.</span></div>
          <button class="btn ${inside ? 'primary' : ''} wide" data-act="iSpots" data-id="lower" ${inside ? '' : 'disabled'}><i class="fa-solid fa-skull"></i>Move the 4 spots</button>`, { pad: true })}
      </div>`;
  }
  if (S.adminTab === 'brokers') {
    const list = arr(a.brokers);
    return head(title, 'NPCs that sell warehouses. Every enabled location is listed at every broker.', segs)
      + `<div class="note"><span class="dot"></span><span><b>Place broker</b>, then aim where they should stand. Scroll turns them, <b>E</b> places. Do it outside a warehouse.</span><span style="flex:1"></span>
        <button class="btn primary" data-act="bPlace"><i class="fa-solid fa-user-plus"></i>Place broker</button></div>`
      + panel('Brokers', `${list.length} placed`, '', list.length ? `<div style="padding:4px 6px"><table><thead><tr><th>#</th><th>Position</th><th>Heading</th><th></th></tr></thead><tbody>
        ${list.map((b, i) => `<tr><td>${i + 1}</td><td><b>${v4(b)}</b></td><td>${Math.round(Number(b.w) || 0)}°</td>
          <td class="r-al" style="white-space:nowrap"><button class="btn icon ghost" data-act="bTp" data-id="${i}" title="Teleport"><i class="fa-solid fa-person-walking-arrow-right"></i></button>
          <button class="btn icon danger" data-act="bRemove" data-id="${i + 1}"><i class="fa-solid fa-trash"></i></button></td></tr>`).join('')}
        </tbody></table></div>` : empty('fa-user-tie', 'No brokers yet', 'Without a broker, players cannot buy a warehouse.'));
  }
  if (S.adminTab === 'presets') {
    const list = arr(a.presets);
    return head(title, 'Floor layouts owners can pick from the laptop Floor Plan app.', segs)
      + `<div class="note"><span class="dot"></span><span>Make a new one with <b>/cargoslots</b> inside a warehouse: drop the spots, press <b>ENTER</b> and give it a name.</span></div>`
      + panel('Presets', `${list.length} available`, '', `<div style="padding:4px 6px"><table><thead><tr><th>Name</th><th>Spots</th><th>Source</th><th></th></tr></thead><tbody>
        ${list.map(p => `<tr><td><b>${esc(p.label)}</b></td><td>${p.count}</td><td><span class="tag ${p.admin ? 'live' : 'off'}">${p.admin ? 'Admin made' : 'Built in'}</span></td>
          <td class="r-al">${p.admin ? `<button class="btn icon danger" data-act="pDelete" data-id="${esc(p.id)}"><i class="fa-solid fa-trash"></i></button>` : ''}</td></tr>`).join('')}
        </tbody></table></div>`);
  }
  if (S.adminTab === 'warehouses') {
    return head(title, 'Every owned warehouse on the server.', segs)
      + panel('Owned warehouses', `${arr(a.warehouses).length} total`, '', arr(a.warehouses).length ? `<div style="padding:4px 6px"><table><thead><tr><th>#</th><th>Owner</th><th>Location</th><th>Stock</th><th>Upgrades</th><th>Associates</th><th></th></tr></thead><tbody>
        ${arr(a.warehouses).map(w => { const u = obj(w.upgrades); return `<tr><td>${w.id}</td><td><b>${esc(w.owner)}</b></td><td>${esc(w.location)}</td><td>${w.stock}</td>
          <td>S${(u.capacity || 0) + 1} · D${(u.workshop || 0) + 1} · L${(u.lower || 0) + 1} · I${(u.intel || 0) + 1} · T${(u.tracker || 0) + 1} · C${(u.contacts || 0) + 1} · R${(u.repair || 0) + 1}</td><td>${w.associates}</td>
          <td class="r-al"><button class="btn sm danger" data-act="wWipe" data-id="${w.id}"><i class="fa-solid fa-trash"></i>Wipe</button></td></tr>`; }).join('')}
        </tbody></table></div>` : empty('fa-warehouse', 'No warehouses owned yet'));
  }
  return head(title, 'Profiles, XP and cooldowns.', segs)
    + panel('Players', `${arr(a.players).length} profiles`, '', `<div style="padding:4px 6px"><table><thead><tr><th>Name</th><th>Level</th><th>XP</th><th>Sourced</th><th>Sold</th><th>Earned</th><th>Give XP</th><th></th></tr></thead><tbody>
      ${arr(a.players).map(p => `<tr><td><b>${esc(p.name || p.identifier)}</b></td><td>${p.level}</td><td>${Number(p.xp).toLocaleString()}</td><td>${p.sourced}</td><td>${p.sold}</td><td>${money(p.earned)}</td>
        <td style="width:150px"><div style="display:flex;gap:6px"><input class="input" style="height:27px" type="number" placeholder="500" data-xp="${esc(p.identifier)}"><button class="btn icon" data-act="pXp" data-id="${esc(p.identifier)}"><i class="fa-solid fa-plus"></i></button></div></td>
        <td class="r-al"><button class="btn icon ghost" data-act="pCd" data-id="${esc(p.identifier)}" title="Reset cooldowns"><i class="fa-solid fa-clock-rotate-left"></i></button></td></tr>`).join('')}
    </tbody></table></div>`);
}

/* ═══════════════════════════════════════════════════════════
   BROKER (warehouse shop)
   ═══════════════════════════════════════════════════════════ */
function renderShop() {
  const s = S.shop; if (!s) return;
  if (!s.locations.find(l => l.id === S.shopSel)) S.shopSel = (s.locations.find(l => !l.owned) || s.locations[0] || {}).id;
  const sel = s.locations.find(l => l.id === S.shopSel);
  const maxed = s.owned >= s.max;
  const canBuy = sel && !sel.owned && !maxed && s.cash >= sel.price;
  $('#shop-root').innerHTML = `
    <div class="bar"><div class="bar-brand"><div class="mark"></div><div class="bar-name"><div class="title-txt">Warehouse Broker</div><div class="sub">Commercial listings</div></div></div>
      <div class="bar-mid"><span class="dot ${maxed ? 'red' : ''}"></span><p>${maxed ? `You own <b>${s.owned} of ${s.max}</b> warehouses` : `Balance <b>${money(s.cash)}</b> · you own <b>${s.owned} of ${s.max}</b>`}</p><span class="ver">v${esc(s.version)}</span></div>
      <button class="pill-close" data-act="close">Close</button></div>
    <div class="body solo"><main class="main">
      ${head('Buy a warehouse', 'Every warehouse is private. Others can buy the same building, but nobody sees your floor except you and your crew.', clock(`${s.capacity} slots`, `Upgradable to ${s.maxCapacity || 32}`))}
      ${panel('Listings', `${s.locations.length} buildings`, '', s.locations.length ? s.locations.map(l => `
        <div class="row ${l.id === S.shopSel ? 'on' : ''}" data-act="shopSel" data-id="${l.id}" style="cursor:pointer">${tile('fa-warehouse', l.owned ? '' : 'off')}
          <div class="row-txt"><b>${esc(l.name)}</b><span>${l.owned ? 'You own a unit here' : 'Private vehicle warehouse'} · ${l.owners} owner${l.owners === 1 ? '' : 's'}</span></div>
          ${l.owned ? '<span class="tag live">Owned</span>' : ''}
          <button class="btn icon ghost" data-act="shopWay" data-id="${l.id}" title="Set waypoint"><i class="fa-solid fa-location-arrow"></i></button>
          <div class="row-end" style="min-width:96px"><b>${money(l.price)}</b><span>one-time</span></div></div>`).join('')
        : empty('fa-warehouse', 'Nothing listed', 'An admin needs to add a location first.'))}
      <div class="note">${sel ? `<span class="dot ${sel.owned ? 'red' : ''}"></span><span>${sel.owned ? `You already own <b>${esc(sel.name)}</b>` : `Selected <b>${esc(sel.name)}</b>`}</span>` : ''}<span style="flex:1"></span>
        <button class="btn primary" data-act="buy" ${canBuy ? '' : 'disabled'}><i class="fa-solid fa-key"></i>Buy · ${money(sel?.price)}</button></div>
    </main></div>
    <div class="statusbar">${keys([['ESC', 'Close'], ['↵', 'Buy selected']])}<span class="grow"></span><span>Waypoint is set after you buy</span></div>`;
}

/* ═══════════════════════════════════════════════════════════
   LAPTOP OS: boot, login, desktop, windows, taskbar
   ═══════════════════════════════════════════════════════════ */
const AREA = { w: 1604, h: 818 };        // window area inside the screen
const LT = S.lt;

function openLaptop(data) {
  S.term = data; S.lb = null; S.admin = null; S.offers = null; S.offersFor = null; planBox = null; S.planDel.clear(); S.planEdit = null; S.deal = null;
  LT.user = data.username || data.profile?.name || 'user';
  LT.seq++; LT.start = false;
  for (const id of Object.keys(LT.wins)) if (!appsFor(data).find(a => a.id === id)) closeWin(id, true);
  applyPrefs(data.prefs);
  const warm = Date.now() - LT.unlocked < 5 * 60 * 1000;
  LT.stage = (S.prefs.fastboot || warm) ? 'desk' : 'boot';
  $('#laptop').innerHTML = `<div class="lt" id="lt"><div class="lt-screen">
    <div class="lt-wall" id="lt-wall" data-w="${esc(S.prefs.wallpaper)}"></div>
    <div id="lt-desk"><div class="lt-menu" id="lt-menu"></div><div class="lt-icons" id="lt-icons"></div><div class="lt-widgets" id="lt-widgets"></div>
      <div class="lt-wins" id="lt-wins"></div><div id="lt-start"></div><div class="lt-bar" id="lt-bar"></div></div>
    <div id="lt-over"></div></div></div>`;
  show('#laptop', true);
  renderChrome(); renderWins();
  if (LT.stage === 'boot') { bootSeq(); beep('boot'); } else unlock();
}

function bootSeq() {
  const seq = LT.seq;
  $('#lt-desk').classList.add('hidden');
  $('#lt-over').innerHTML = `<div class="lt-boot"><div class="mark"></div><div class="ld"><i></i></div></div>`;
  setTimeout(() => { if (seq === LT.seq) loginSeq(); }, 1350);
}
function loginSeq() {
  const seq = LT.seq; LT.stage = 'login';
  $('#lt-wall').classList.add('blur');
  $('#lt-over').innerHTML = `<div class="lt-login" data-act="skipLogin">
    <div class="clk"><b data-clock>${clockTxt()}</b><span>${dateTxt()}</span></div>
    <div class="lt-av">${esc(initials(LT.user))}</div><div class="nm">${esc(LT.user)}</div>
    <div class="lt-pass"><span id="lt-dots"></span><button><i class="fa-solid fa-arrow-right"></i></button></div>
    <div class="hint" id="lt-hint">Signing in</div></div>`;
  let n = 0;
  const type = () => {
    if (seq !== LT.seq || LT.stage !== 'login') return;
    if (n < 9) { n++; $('#lt-dots').textContent = '•'.repeat(n); setTimeout(type, 70 + Math.random() * 60); return; }
    const h = $('#lt-hint'); h.textContent = 'Welcome back'; h.classList.add('ok');
    setTimeout(() => { if (seq === LT.seq) unlock(); }, 480);
  };
  setTimeout(type, 420);
}
function unlock() {
  LT.stage = 'desk'; LT.unlocked = Date.now();
  $('#lt-over').innerHTML = '';
  $('#lt-wall').classList.remove('blur');
  $('#lt-desk').classList.remove('hidden');
  if (LT.pending) { const p = LT.pending; LT.pending = null; openApp(p); }
}
function closeLaptop() {
  LT.seq++;
  applyPrefs(S.myPrefs);
  const lt = $('#lt');
  if (lt) { lt.classList.add('out'); setTimeout(() => { if (S.view !== 'laptop') { show('#laptop', false); $('#laptop').innerHTML = ''; } }, 260); }
  else show('#laptop', false);
}

/* desktop chrome: menubar, icons, widgets, taskbar, start menu */
function renderChrome() {
  const t = S.term; if (!t || !$('#lt-desk')) return;
  const p = t.profile, w = t.warehouse, apps = appsFor(t);
  const focus = appOf(LT.focus);
  $('#lt-menu').innerHTML = `<div class="mark"></div><b>${focus ? esc(focus.label) : 'Desktop'}</b><span>${esc(w.name)}</span><span class="grow"></span>
    <span class="ver">v${esc(t.version)}</span><i class="fa-solid fa-wifi"></i><i class="fa-solid fa-battery-three-quarters"></i><b data-clock>${clockTxt()}</b>`;
  $('#lt-icons').innerHTML = apps.map(a => {
    const lock = a.lock && a.lock(t), badge = a.badge && a.badge(t);
    return `<button class="ico ${lock ? 'lock' : ''}" data-act="open" data-id="${a.id}"><div class="gl"><i class="fa-solid ${a.icon}"></i></div><span>${a.label}</span>
      ${lock ? '<div class="lk"><i class="fa-solid fa-lock"></i></div>' : badge ? `<div class="bd">${badge}</div>` : ''}</button>`;
  }).join('');
  const cd = p.sourceCd > 0, full = w.stockCount >= w.capacity;
  $('#lt-widgets').innerHTML = `
    <div class="wg wg-clock"><b data-clock>${clockTxt()}</b><span>${dateTxt()}</span></div>
    <div class="wg"><h5><i class="fa-solid fa-warehouse"></i>Business<span class="grow"></span><span>${t.role === 'owner' ? 'Owner' : 'Associate'}</span></h5>
      <div class="wg-biz">${ring(p.xpNeed ? p.xpInto / p.xpNeed : 1, p.level, 'Level')}<div class="kvs">
        <div class="kv"><span>Main floor</span><b class="${full ? 'neg' : ''}">${w.stockCount} / ${w.capacity}</b></div>
        <div class="kv"><span>Lower level</span>${w.lowerOpen ? `<b>${w.lowerCount} / ${w.lowerCapacity}</b>` : '<span class="dim">Locked</span>'}</div>
        <div class="kv"><span>Earned</span><b class="pos">${money(p.earned)}</b></div>
        <div class="kv"><span>Clean streak</span><b>${p.streak}</b></div></div></div></div>
    <div class="wg"><h5><i class="fa-solid fa-signal"></i>Status</h5><div style="display:flex;flex-direction:column;gap:9px">
      <div class="kv"><span style="display:flex;align-items:center;gap:9px"><span class="dot ${t.mission || cd ? 'red' : ''}"></span>Contracts</span>${t.mission ? '<b class="neg">On a job</b>' : cd ? `<b data-cd="${Date.now() + p.sourceCd * 1000}">${fmtTime(p.sourceCd)}</b>` : '<b class="pos">Open</b>'}</div>
      <div class="kv"><span style="display:flex;align-items:center;gap:9px"><span class="dot ${t.policeOk ? '' : 'red'}"></span>Police on duty</span><b>${t.policeOk ? 'Enough' : 'Too few'}</b></div>
      ${S.static.radio ? `<div class="kv"><span style="display:flex;align-items:center;gap:9px"><span class="dot ${S.radio ? '' : 'red'}"></span>Crew radio</span><b>${S.radio ? 'Live · CH ' + esc(S.radio) : (S.prefs.radio ? 'CH ' + esc(t.radioChannel) + ' on jobs' : 'Off')}</b></div>` : ''}
      ${w.scanner ? `<div class="kv"><span style="display:flex;align-items:center;gap:9px"><span class="dot ${arr(t.hot).length ? 'red' : ''}"></span>Scanner</span><b>${arr(t.hot).length} signal${arr(t.hot).length === 1 ? '' : 's'}</b></div>` : ''}
    </div></div>
    <div class="wg"><h5><i class="fa-solid fa-bolt"></i>Quick actions</h5><div class="acts">
      <button class="btn primary" data-act="open" data-id="contracts"><i class="fa-solid fa-file-signature"></i>Contracts</button>
      <button class="btn" data-act="open" data-id="stock"><i class="fa-solid fa-car-side"></i>Inventory</button>
      <button class="btn" data-act="open" data-id="floorplan"><i class="fa-solid fa-border-all"></i>Floor plan</button>
      <button class="btn danger" data-act="exit"><i class="fa-solid fa-door-open"></i>Leave</button></div></div>`;
  renderTaskbar();
  $('#lt-start').innerHTML = LT.start ? `<div class="lt-start">
    <div class="who"><div class="av teal">${esc(initials(p.name))}</div><div class="who-txt"><b>${esc(p.name)}</b><span>Level ${p.level} · ${t.role === 'owner' ? 'Owner' : 'Associate'}</span>
      <div class="xpbar"><i style="width:${p.xpNeed ? (p.xpInto / p.xpNeed) * 100 : 100}%"></i></div></div></div>
    <div class="grid">${apps.map(a => `<button class="ico ${a.lock && a.lock(t) ? 'lock' : ''}" data-act="open" data-id="${a.id}"><div class="gl"><i class="fa-solid ${a.icon}"></i></div><span>${a.label}</span></button>`).join('')}</div>
    <div class="ft"><button class="btn sm" data-act="exit"><i class="fa-solid fa-door-open"></i>Leave warehouse</button><span style="flex:1"></span>
      <button class="btn sm danger" data-act="power"><i class="fa-solid fa-power-off"></i>Shut down</button></div></div>` : '';
}
function renderTaskbar() {
  const t = S.term, p = t.profile, w = t.warehouse;
  $('#lt-bar').innerHTML = `<button class="tb pw" data-act="power" title="Shut down"><i class="fa-solid fa-power-off"></i></button>
    <button class="tb st ${LT.start ? 'on' : ''}" data-act="startMenu" title="Apps"><div class="mark"></div></button><div class="sep"></div>
    <div class="apps">${LT.order.map(id => { const a = appOf(id), wn = LT.wins[id];
      return `<button class="tb run ${LT.focus === id && !wn.min ? 'focus on' : ''}" data-act="task" data-id="${id}" title="${a.label}"><i class="fa-solid ${a.icon}"></i></button>`; }).join('')}</div>
    <div class="tray"><span class="chip">Lv ${p.level}</span><span><i class="fa-solid fa-car-side"></i> <b>${w.stockCount}/${w.capacity}</b></span>
      <i class="fa-solid fa-wifi"></i><i class="fa-solid fa-battery-three-quarters"></i><div class="tc"><b data-clock>${clockTxt()}</b><span>${new Date().toLocaleDateString('en-US')}</span></div></div>`;
}

/* windows */
function openApp(id) {
  const t = S.term, a = appOf(id);
  if (!t || !a || (a.admin && !t.isAdmin)) return;
  if (LT.stage !== 'desk') { LT.pending = id; return; }
  if (id === 'leaderboard') S.lb = null;
  let w = LT.wins[id];
  if (!w) {
    const ww = Math.min(a.w, AREA.w - 40), hh = Math.min(a.h, AREA.h - 16), n = LT.order.length % 6;
    w = LT.wins[id] = { x: Math.round((AREA.w - ww) / 2) + n * 24, y: clamp(Math.round((AREA.h - hh) / 2) - 10 + n * 18, 6, Math.max(6, AREA.h - hh - 6)), w: ww, h: hh, z: 0, min: false, max: false };
    LT.order.push(id); LT.fresh = id; beep('open');
  }
  w.min = false; LT.start = false;
  focusWin(id, true);
  renderWins(); renderChrome();
}
function closeWin(id, silent) {
  delete LT.wins[id]; LT.order = LT.order.filter(x => x !== id);
  if (LT.focus === id) LT.focus = LT.order.filter(x => !LT.wins[x].min).sort((a, b) => LT.wins[b].z - LT.wins[a].z)[0] || null;
  if (!silent) { renderWins(); renderChrome(); }
}
function focusWin(id, quiet) {
  const w = LT.wins[id]; if (!w) return;
  w.z = ++LT.z; LT.focus = id;
  if (quiet) return;
  $$('#lt-wins .win').forEach(el => { const on = el.dataset.app === id; el.classList.toggle('focus', on); if (on) el.style.zIndex = w.z; });
  const m = $('#lt-menu b'); if (m) m.textContent = appOf(id).label;
  renderTaskbar();
}
function winHtml(id) {
  const a = appOf(id), w = LT.wins[id], user = String(LT.user).replace(/\s+/g, '');
  return `<div class="win ${w.max ? 'max' : ''} ${w.min ? 'min' : ''} ${LT.focus === id ? 'focus' : ''} ${LT.fresh === id ? 'new' : ''}" data-app="${id}" style="left:${w.x}px;top:${w.y}px;width:${w.w}px;height:${w.h}px;z-index:${w.z}">
    <div class="win-h" data-drag="${id}"><i class="fa-solid ${a.icon}"></i><div class="path">C:/Users/${esc(user)}/Cargo/<b>${a.exe}</b></div>
      <div class="ctl"><button data-act="winMin" data-id="${id}" title="Minimize"><i class="fa-solid fa-minus"></i></button>
        <button data-act="winMax" data-id="${id}" title="${w.max ? 'Restore' : 'Maximize'}"><i class="fa-solid ${w.max ? 'fa-compress' : 'fa-expand'}"></i></button>
        <button class="x" data-act="winClose" data-id="${id}" title="Close"><i class="fa-solid fa-xmark"></i></button></div></div>
    <div class="win-b"><main class="main ${a.fill ? 'fill' : ''}" data-body="${id}">${renderApp(id)}</main></div>
    <div class="win-f"><span>C:/Users/${esc(user)}/Cargo</span><span class="grow"></span><span><b>${a.label}</b></span><span>|</span><span>v${esc(S.term.version)}</span></div></div>`;
}
function keepScroll(fn) {
  const pos = {};
  $$('[data-body]').forEach(el => { pos[el.dataset.body] = [el.scrollTop, ...$$('.p-body', el).map(p => p.scrollTop)]; });
  fn();
  $$('[data-body]').forEach(el => { const p = pos[el.dataset.body]; if (!p) return; el.scrollTop = p[0]; $$('.p-body', el).forEach((b, i) => { if (p[i + 1] !== undefined) b.scrollTop = p[i + 1]; }); });
}
function renderWins() {
  const box = $('#lt-wins'); if (!box) return;
  keepScroll(() => { box.innerHTML = LT.order.map(winHtml).join(''); });
  LT.fresh = null;
}
function refreshBodies() {
  keepScroll(() => { $$('[data-body]').forEach(el => { el.innerHTML = renderApp(el.dataset.body); }); });
}

/* one refresh for whatever is on screen */
function refresh() {
  if (S.view === 'laptop') { refreshBodies(); renderChrome(); }
  else if (S.view === 'admin') renderTerminal();
}

/* window dragging + HUD dragging */
(() => {
  let drag = null;
  document.addEventListener('mousedown', e => {
    if (S.hudEdit && e.target.closest('#hud')) {
      const r = S.hudEdit; drag = { hud: true, sx: e.clientX, sy: e.clientY, x: r.x, y: r.y }; e.preventDefault(); return;
    }
    const win = e.target.closest('.win');
    if (win && LT.focus !== win.dataset.app) focusWin(win.dataset.app);
    if (S.view === 'laptop' && LT.start && !e.target.closest('.lt-start') && !e.target.closest('[data-act="startMenu"]')) { LT.start = false; renderChrome(); }
    const h = e.target.closest('[data-drag]');
    if (!h || e.target.closest('button')) return;
    const w = LT.wins[h.dataset.drag]; if (!w || w.max) return;
    drag = { id: h.dataset.drag, sx: e.clientX, sy: e.clientY, x: w.x, y: w.y, el: win };
    e.preventDefault();
  });
  document.addEventListener('mousemove', e => {
    if (!drag) return;
    const sc = S.scale || 1, dx = (e.clientX - drag.sx) / sc, dy = (e.clientY - drag.sy) / sc;
    if (drag.hud) {
      S.hudEdit.x = clamp(Math.round(drag.x + dx), 0, 1920 - 380); S.hudEdit.y = clamp(Math.round(drag.y + dy), 0, 1080 - 120);
      placeHud(S.hudEdit); return;
    }
    const w = LT.wins[drag.id]; if (!w) return;
    w.x = clamp(Math.round(drag.x + dx), 120 - w.w, AREA.w - 120); w.y = clamp(Math.round(drag.y + dy), 0, AREA.h - 38);
    drag.el.style.left = w.x + 'px'; drag.el.style.top = w.y + 'px';
  });
  document.addEventListener('mouseup', () => { drag = null; });
  document.addEventListener('dblclick', e => {
    const h = e.target.closest('[data-drag]'); if (!h || e.target.closest('button')) return;
    const w = LT.wins[h.dataset.drag]; w.max = !w.max; renderWins();
  });
})();

/* clocks tick */
setInterval(() => { $$('[data-clock]').forEach(el => { el.textContent = clockTxt(); }); }, 10000);

/* ═══════════════════════════════════════════════════════════
   DESIGN BAY · GTA-style mod menu
   Hover previews on the car, ENTER keeps it, BACKSPACE reverts.
   Nothing is charged until "Apply build".
   ═══════════════════════════════════════════════════════════ */
const VIS = 11;
const same = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

function wsPartAvail(p) {
  const av = obj(S.ws.data.avail);
  if (p.type === 'part' || p.type === 'level') return Number(obj(av.parts)[p.id] || 0);
  if (p.type === 'livery') return Number(av.livery || 0);
  if (p.type === 'wheels') return Object.values(obj(av.wheels)).some(n => Number(n) > 0) ? 1 : 0;
  return 1;
}
function wsStatus(p, v) {
  const W = S.static.workshop;
  if (v === undefined || v === null) return 'Stock';
  switch (p.type) {
    case 'level': return `Stage ${v}`;
    case 'toggle': return v ? 'Installed' : 'Stock';
    case 'part': return `Option ${v + 1}`;
    case 'livery': return `Livery ${v + 1}`;
    case 'paint': return `${arr(W.Colors)[v.p - 1]?.[0] || ''} · ${arr(W.Finishes).find(f => f.id === v.finish)?.label || ''}`;
    case 'wheels': {
      const rim = v.color !== undefined && v.color !== null ? arr(W.RimColors).find(c => c[0] === v.color)?.[1] : null;
      const type = v.type !== undefined && v.type !== null ? `${arr(W.WheelTypes).find(w => w[0] === v.type)?.[1] || ''} #${(v.index || 0) + 1}` : 'Stock';
      return rim ? `${type} · ${rim}` : type;
    }
    case 'tint': return arr(W.Tints).find(t => t[0] === v)?.[1] || 'Stock';
    case 'plate': return arr(W.Plates).find(t => t[0] === v)?.[1] || 'Stock';
    case 'xenon': return arr(W.XenonColors).find(t => t[0] === v)?.[1] || 'On';
    case 'neon': return arr(W.NeonColors)[v - 1]?.[0] || 'On';
  }
  return 'Set';
}
const setPart = (b, id, v) => { if (v === null || v === undefined) delete b[id]; else b[id] = v; };
const paintOf = b => ({ p: 1, s: 1, finish: 0, pearl: 0, ...obj(b.paint) });
const rgb = c => `rgb(${c[1]},${c[2]},${c[3]})`;

/* option lists: { title, focus, opts:[{label, val, swatch, note}], get(b), set(b, v) } */
function optList(key) {
  const W = S.static.workshop, b = S.ws.build;
  const [kind, id] = key.split(':');
  if (kind === 'paint') {
    const set = (bb, v) => { const p = paintOf(bb); p[id] = v; bb.paint = p; };
    const get = bb => bb.paint ? bb.paint[id] : undefined;
    if (id === 'p' || id === 's') return { title: id === 'p' ? 'Primary colour' : 'Secondary colour', focus: 'paint', get, set, opts: arr(W.Colors).map((c, i) => ({ label: c[0], val: i + 1, swatch: rgb(c) })) };
    if (id === 'finish') return { title: 'Finish', focus: 'paint', get, set, opts: arr(W.Finishes).map(f => ({ label: f.label, val: f.id, note: `+${f.points} pts` })) };
    if (id === 'pearl') return { title: 'Pearlescent', focus: 'paint', get, set, opts: arr(W.Pearls).map(p => ({ label: p[1], val: p[0] })) };
  }
  if (kind === 'wheels') {
    const counts = obj(S.ws.data.avail.wheels), cur = obj(b.wheels);
    if (id === 'type') return { title: 'Wheel type', focus: 'wheels', get: bb => bb.wheels ? bb.wheels.type : undefined,
      set: (bb, v) => { const o = obj(bb.wheels); bb.wheels = { type: v, index: 0, custom: !!o.custom }; if (o.color !== undefined && o.color !== null) bb.wheels.color = o.color; },
      opts: arr(W.WheelTypes).filter(t => Number(counts[String(t[0])] || 0) > 0).map(t => ({ label: t[1], val: t[0], note: (t[0] === 7 || t[0] === 12) ? `+${W.HighEndWheelBonus} pts` : '' })) };
    if (id === 'index') { const n = Number(counts[String(cur.type)] || 0);
      return { title: 'Rims', focus: 'wheels', get: bb => bb.wheels ? bb.wheels.index : undefined, set: (bb, v) => { bb.wheels = { ...obj(bb.wheels), index: v }; },
        opts: Array.from({ length: n }, (_, i) => ({ label: `Rim ${i + 1}`, val: i })) }; }
    if (id === 'color') return { title: 'Rim colour', focus: 'wheels', get: bb => bb.wheels && bb.wheels.color !== undefined ? bb.wheels.color : null,
      set: (bb, v) => {
        const o = { ...obj(bb.wheels) };
        if (v === null) delete o.color; else o.color = v;
        if ((o.type === undefined || o.type === null) && o.color === undefined) delete bb.wheels; else bb.wheels = o;
      },
      opts: [{ label: 'Stock colour', val: null }, ...arr(W.RimColors).map(c => ({ label: c[1], val: c[0], note: `+${W.RimColor.points} pts` }))] };
    if (id === 'custom') return { title: 'Custom tyres', focus: 'wheels', get: bb => !!obj(bb.wheels).custom, set: (bb, v) => { bb.wheels = { ...obj(bb.wheels), custom: v }; },
      opts: [{ label: 'Stock tyres', val: false }, { label: 'Custom tyres', val: true, note: `+${W.CustomTyres.points} pts` }] };
  }
  const p = Cargo.parts().find(x => x.id === id); const n = wsPartAvail(p);
  const base = { title: p.label, focus: p.id, get: bb => bb[p.id], set: (bb, v) => setPart(bb, p.id, v) };
  switch (p.type) {
    case 'level': return { ...base, opts: [{ label: 'Stock', val: null }, ...Array.from({ length: Math.min(p.max, n) }, (_, i) => ({ label: `Stage ${i + 1}`, val: i + 1, note: `+${(i + 1) * p.points} pts` }))] };
    case 'toggle': return { ...base, opts: [{ label: 'Stock', val: null }, { label: 'Installed', val: true, note: `+${p.points} pts` }] };
    case 'part': case 'livery': return { ...base, opts: [{ label: 'Stock', val: null }, ...Array.from({ length: n }, (_, i) => ({ label: `${p.type === 'livery' ? 'Livery' : p.label} ${i + 1}`, val: i }))] };
    case 'tint': return { ...base, opts: arr(W.Tints).map(t => ({ label: t[1], val: t[0] === 0 ? null : t[0] })) };
    case 'plate': return { ...base, opts: arr(W.Plates).map(t => ({ label: t[1], val: t[0] === 0 ? null : t[0] })) };
    case 'xenon': return { ...base, opts: [{ label: 'Off', val: null }, ...arr(W.XenonColors).map(t => ({ label: t[1], val: t[0] }))] };
    case 'neon': return { ...base, opts: [{ label: 'Off', val: null }, ...arr(W.NeonColors).map((c, i) => ({ label: c[0], val: i + 1, swatch: rgb(c) }))] };
  }
  return { ...base, opts: [] };
}
function optPrice(L, val) {
  const ws = S.ws, cand = clone(ws.saved);
  L.set(cand, val);
  return Cargo.cost(ws.saved, cand, ws.data.stock.base_rarity).total;
}

/* menus: { title, items:[{label, icon, right, desc, dis, go|fn|opt}] } */
function menuOf(e) {
  const ws = S.ws, d = ws.data, W = S.static.workshop, b = ws.build;
  if (e.key === 'root') {
    const order = ['cosmetic', 'performance', 'light'];
    const groups = order.filter(g => W.Groups[g]).concat(Object.keys(W.Groups).filter(g => !order.includes(g)));
    const allowed = arr(d.groups);
    const { total } = Cargo.cost(ws.saved, b, d.stock.base_rarity);
    const dirty = !same(b, ws.saved), broke = total > (d.cash ?? Infinity);
    return { title: 'Categories', items: [
      ...groups.map(g => { const ok = allowed.includes(g), n = Cargo.parts().filter(p => p.group === g).length;
        return { label: W.Groups[g].label, icon: ok ? W.Groups[g].icon : 'fa-solid fa-lock', right: ok ? `${n} parts` : 'Locked', chev: ok, dis: !ok,
          desc: ok ? `Browse <b>${esc(W.Groups[g].label.toLowerCase())}</b> parts. Hover to preview, ENTER to keep.` : 'Upgrade the <b>Design Bay</b> from the laptop to unlock this category.',
          go: ok ? { key: 'group:' + g } : null }; }),
      { label: 'Headlights', icon: 'fa-solid fa-lightbulb', right: ws.lights ? 'On' : 'Off', desc: 'Toggle the headlights while you work.', fn: () => { ws.lights = !ws.lights; post('wsLights', { on: ws.lights }); } },
      { label: 'Wash & clean', icon: 'fa-solid fa-soap', right: d.clean ? '<i class="fa-solid fa-check ck"></i>' : money(S.static.washPrice || 0), dis: !!d.clean,
        desc: d.clean ? 'Spotless already.' : `Wash off the dirt and grime for <b>${money(S.static.washPrice || 0)}</b>. Buyers notice a clean car.`, fn: () => ACT.wsWash() },
      { label: dirty ? `Apply build` : 'No changes yet', icon: 'fa-solid fa-check', act: true, right: dirty ? money(total) : '', dis: !dirty || broke,
        desc: broke ? `<b style="color:var(--red)">Not enough money.</b> Balance ${money(d.cash)}.` : dirty ? `Pay <b>${money(total)}</b> and save the build. Score and rarity update straight away.` : 'Change something first.', fn: () => ACT.wsBuy() },
      { label: 'Reset changes', icon: 'fa-solid fa-rotate-left', dis: !dirty, desc: 'Put everything back to the saved build.', fn: () => { ws.build = clone(ws.saved); wsChanged(); } },
      { label: 'Exit design bay', icon: 'fa-solid fa-arrow-right-from-bracket', desc: dirty ? 'You have changes that are not applied yet.' : 'Back to the warehouse.', fn: () => ACT.wsClose() },
    ] };
  }
  if (e.key.startsWith('group:')) {
    const g = e.key.slice(6);
    return { title: W.Groups[g].label, items: Cargo.parts().filter(p => p.group === g).map(p => {
      const n = wsPartAvail(p), v = b[p.id], set = v !== undefined && v !== null;
      const sub = p.type === 'paint' ? 'paint' : p.type === 'wheels' ? 'wheels' : null;
      return { label: p.label, icon: p.icon, right: n > 0 ? `<span style="${set ? 'color:inherit' : ''}">${esc(wsStatus(p, v))}</span>` : 'N/A', chev: n > 0, dis: n <= 0,
        desc: n > 0 ? `<b>${p.kind === 'perf' ? 'Performance' : 'Style'}</b> · up to +${p.type === 'level' ? p.points * p.max : p.points} pts · from ${money(p.price)}` : 'Not available on this model.',
        go: n > 0 ? (sub ? { key: sub } : { key: 'part:' + p.id, list: true }) : null };
    }) };
  }
  if (e.key === 'paint') {
    const pv = b.paint, W2 = W;
    return { title: 'Respray', items: [
      { label: 'Stock paint', icon: 'fa-solid fa-ban', right: pv ? '' : '<i class="fa-solid fa-check ck"></i>', desc: 'Go back to the factory paint.', fn: () => { delete ws.build.paint; wsChanged('paint'); } },
      { label: 'Primary colour', icon: 'fa-solid fa-fill-drip', right: pv ? esc(arr(W2.Colors)[pv.p - 1]?.[0] || '') : 'Stock', chev: true, go: { key: 'paint:p', list: true }, desc: 'Main body colour.' },
      { label: 'Secondary colour', icon: 'fa-solid fa-fill', right: pv ? esc(arr(W2.Colors)[pv.s - 1]?.[0] || '') : 'Stock', chev: true, go: { key: 'paint:s', list: true }, desc: `Two-tone adds <b>+${W2.TwoTonePoints} pts</b>.` },
      { label: 'Finish', icon: 'fa-solid fa-wand-magic-sparkles', right: pv ? esc(arr(W2.Finishes).find(f => f.id === pv.finish)?.label || '') : 'Stock', chev: true, go: { key: 'paint:finish', list: true }, desc: 'Better finishes score higher.' },
      { label: 'Pearlescent', icon: 'fa-solid fa-gem', right: pv ? esc(arr(W2.Pearls).find(x => x[0] === pv.pearl)?.[1] || 'None') : 'Stock', chev: true, go: { key: 'paint:pearl', list: true }, desc: 'Any pearl adds <b>+1 pt</b>.' },
    ] };
  }
  if (e.key === 'wheels') {
    const wv = b.wheels, W2 = W, hasType = !!wv && wv.type !== undefined && wv.type !== null;
    return { title: 'Wheels', items: [
      { label: 'Stock wheels', icon: 'fa-solid fa-ban', right: wv ? '' : '<i class="fa-solid fa-check ck"></i>', desc: 'Go back to the factory wheels.', fn: () => { delete ws.build.wheels; wsChanged('wheels'); } },
      { label: 'Wheel type', icon: 'fa-solid fa-circle-dot', right: wv && wv.type != null ? esc(arr(W2.WheelTypes).find(t => t[0] === wv.type)?.[1] || '') : 'Stock', chev: true, go: { key: 'wheels:type', list: true }, desc: `High-end and track wheels add <b>+${W2.HighEndWheelBonus} pts</b>.` },
      { label: 'Rims', icon: 'fa-solid fa-life-ring', right: hasType ? `#${wv.index + 1}` : '—', chev: hasType, dis: !hasType, go: hasType ? { key: 'wheels:index', list: true } : null, desc: hasType ? 'Pick a rim for this wheel type.' : 'Pick a wheel type first.' },
      { label: 'Rim colour', icon: 'fa-solid fa-palette', right: wv && wv.color != null ? esc(arr(W2.RimColors).find(c => c[0] === wv.color)?.[1] || '') : 'Stock', chev: true, go: { key: 'wheels:color', list: true }, desc: `Works on stock wheels too · +${W2.RimColor.points} pt · ${money(W2.RimColor.price)}` },
      { label: 'Custom tyres', icon: 'fa-solid fa-circle', right: hasType ? (wv.custom ? 'On' : 'Off') : '—', chev: hasType, dis: !hasType, go: hasType ? { key: 'wheels:custom', list: true } : null, desc: `+${W2.CustomTyres.points} pts · ${money(W2.CustomTyres.price)}` },
    ] };
  }
  // option list
  const L = optList(e.key.replace(/^part:/, 'part:'));
  return { title: L.title, list: L, items: L.opts.map(o => {
    const kept = same(L.get(e.snap), o.val), price = optPrice(L, o.val);
    return { label: o.label, swatch: o.swatch, opt: o, right: kept ? '<i class="fa-solid fa-check ck"></i>' : (price > 0 ? money(price) : 'Free'),
      desc: `${esc(o.label)}${o.note ? ` · <b>${esc(o.note)}</b>` : ''}${kept ? ' · <b>current</b>' : price > 0 ? ` · ${money(price)}` : ''}` };
  }) };
}

function wsTop() { return S.ws.stack[S.ws.stack.length - 1]; }
function wsPush(go) {
  const e = { key: go.key, idx: 0, top: 0 };
  if (go.list) {
    e.snap = clone(S.ws.build);
    const L = optList(go.key);
    const cur = L.opts.findIndex(o => same(L.get(S.ws.build), o.val));
    e.idx = Math.max(0, cur);
  }
  S.ws.stack.push(e);
  renderMenu();
  if (go.list) post('wsPreview', { build: S.ws.build, focus: optList(go.key).focus });
}
function wsBack() {
  const ws = S.ws;
  if (ws.stack.length <= 1) return ACT.wsClose();
  const e = ws.stack.pop();
  if (e.snap) { ws.build = clone(e.snap); wsChanged(); return; }
  renderMenu();
}
function wsMove(dir) {
  const e = wsTop(), m = menuOf(e), n = m.items.length; if (!n) return;
  e.idx = (e.idx + dir + n) % n;
  wsHover();
}
function wsHover() {
  const e = wsTop(), m = menuOf(e), it = m.items[e.idx];
  if (m.list && it && it.opt) { m.list.set(S.ws.build, it.opt.val); wsChanged(m.list.focus); return; }
  renderMenu();
}
function wsSelect() {
  const e = wsTop(), m = menuOf(e), it = m.items[e.idx];
  if (!it || it.dis) return;
  if (m.list) { m.list.set(S.ws.build, it.opt.val); e.snap = clone(S.ws.build); renderMenu(); return; }
  if (it.go) return wsPush(it.go);
  if (it.fn) { it.fn(); renderMenu(); }
}

function renderMenu() {
  const ws = S.ws; if (!ws) return;
  const d = ws.data, st = d.stock, W = S.static.workshop;
  const e = wsTop(), m = menuOf(e), n = m.items.length;
  e.idx = clamp(e.idx, 0, Math.max(0, n - 1));
  if (e.idx < e.top) e.top = e.idx;
  if (e.idx >= e.top + VIS) e.top = e.idx - VIS + 1;
  const { score, perf, style } = Cargo.score(ws.build, d.level);
  const projected = Cargo.rarityFromScore(st.base_rarity, score, d.maxRarityGain);
  const { total } = Cargo.cost(ws.saved, ws.build, st.base_rarity);
  const value = Cargo.baseValue({ ...st, score, rarity: projected }, d.contacts);
  const broke = total > (d.cash ?? Infinity);
  const cur = m.items[e.idx];
  const crumbs = ws.stack.length > 1 ? `${esc(menuOf(ws.stack[ws.stack.length - 2]).title)} › ` : '';
  $('#ws-menu').innerHTML = `
    <div class="gm-head"><span class="ver">v${esc(S.static.version)}</span><b>${esc(st.label)}</b><span>${esc(d.levelName)} · ${esc(st.plate || '')}</span></div>
    <div class="gm-sub">${crumbs}${esc(m.title)}<span>${n ? e.idx + 1 : 0} / ${n}</span></div>
    <div class="gm-list">${m.items.slice(e.top, e.top + VIS).map((it, k) => { const i = e.top + k;
      return `<button class="gm-it ${i === e.idx ? 'on' : ''} ${it.dis ? 'dis' : ''} ${it.act ? 'act' : ''}" data-mi="${i}">
        <span class="l">${it.swatch ? `<span class="sw8" style="background:${it.swatch}"></span>` : it.icon ? `<i class="${it.icon.includes('fa-') && !it.icon.includes(' ') ? 'fa-solid ' : ''}${esc(it.icon)}"></i>` : ''}${esc(it.label)}</span>
        <span class="r">${it.right || ''}${it.chev ? '<i class="fa-solid fa-chevron-right chev"></i>' : ''}</span></button>`; }).join('')}</div>
    ${n > VIS ? `<div class="gm-scroll"><i class="fa-solid fa-caret-up"></i><i class="fa-solid fa-caret-down"></i></div>` : ''}
    <div class="gm-desc">${cur?.desc || '&nbsp;'}</div>
    <div class="gm-foot">
      <div class="gm-score"><div class="n">${score}</div><div style="flex:1">
        <div class="kv"><span>Performance <b>${perf}</b> · Style <b>${style}</b></span><span class="chips" style="align-items:center">${rar(st.base_rarity)}${projected !== st.base_rarity ? `<i class="fa-solid fa-arrow-right dim" style="font-size:10px"></i>${rar(projected)}` : ''}</span></div>
        ${R(st.base_rarity).illegal ? '<div class="dim" style="font-size:10.5px;margin-top:8px">Illegal cars keep their tier. The build raises the value.</div>'
          : `<div class="meter"><i style="width:${score}%"></i>${arr(W.ScoreToRarity).map((v, i) => `<span class="tick" style="left:${v}%"><span>${i + 1 > d.maxRarityGain ? '<i class="fa-solid fa-lock"></i> ' : ''}+${i + 1}</span></span>`).join('')}</div>`}
      </div></div>
      <div class="gm-tot"><div class="kv" style="flex-direction:column;align-items:flex-start;gap:3px"><span>Sale value <b>${money(value)}</b></span><span>Balance ${money(d.cash)}</span></div>
        <div style="text-align:right"><span class="dim" style="font-size:10.5px">Changes</span><b class="${broke ? 'neg' : ''}" style="display:block">${money(total)}</b></div></div>
      <div class="gm-keys">${keys([['↑↓', 'Browse'], ['ENTER', 'Select'], ['BKSP', 'Back'], ['DRAG', 'Rotate'], ['WHEEL', 'Zoom']])}</div>
    </div>`;
}

let previewTimer = null;
function wsChanged(focus) {
  renderMenu();
  clearTimeout(previewTimer);
  previewTimer = setTimeout(() => post('wsPreview', { build: S.ws.build, focus }), 40);
}

/* menu mouse + camera drag */
document.addEventListener('mouseover', e => {
  if (S.view !== 'workshop') return;
  const it = e.target.closest('[data-mi]'); if (!it) return;
  const e2 = wsTop(), i = Number(it.dataset.mi);
  if (e2.idx !== i) { e2.idx = i; wsHover(); }
});
document.addEventListener('click', e => {
  if (S.view !== 'workshop') return;
  const it = e.target.closest('[data-mi]'); if (!it) return;
  wsTop().idx = Number(it.dataset.mi); wsSelect();
});
document.addEventListener('contextmenu', e => { if (S.view === 'workshop' && e.target.closest('#ws-menu')) { e.preventDefault(); wsBack(); } });
(() => {
  let down = false, lx = 0, ly = 0, acc = { dx: 0, dy: 0 }, raf = null;
  const flush = () => { raf = null; if (acc.dx || acc.dy) { post('wsCam', acc); acc = { dx: 0, dy: 0 }; } };
  document.addEventListener('mousedown', e => { if (e.target.id === 'ws-drag') { down = true; lx = e.clientX; ly = e.clientY; } });
  document.addEventListener('mouseup', () => { down = false; });
  document.addEventListener('mousemove', e => {
    if (!down) return; acc.dx += e.clientX - lx; acc.dy += e.clientY - ly; lx = e.clientX; ly = e.clientY;
    if (!raf) raf = requestAnimationFrame(flush);
  });
  document.addEventListener('wheel', e => {
    if (S.view !== 'workshop') return;
    if (e.target.id === 'ws-drag') post('wsCam', { zoom: Math.sign(e.deltaY) });
    else if (e.target.closest('#ws-menu')) wsMove(Math.sign(e.deltaY));
  }, { passive: true });
})();

/* ═══════════════════════════════════════════════════════════
   MISSION HUD (movable with /cargohud)
   ═══════════════════════════════════════════════════════════ */
const HUD_DEFAULT = { x: 1504, y: 250 };
function placeHud(p) { const el = $('#hud'); const q = p || S.hudPos || HUD_DEFAULT; el.style.left = q.x + 'px'; el.style.top = q.y + 'px'; }
const SAMPLE_HUD = { mode: 'sell', label: 'Pegassi Zentorno', rarity: 'legendary', offer: 412500, agreed: 438000, health: 82, remaining: 412,
  counts: { hit: 2, rammed: 1, shot: 0 }, buyer: { name: 'Marcus Hale', label: 'Collector' }, distance: 2140, objective: 'Deliver to the buyer' };

let hudTick = null, shownOffer = null;
function hudSteps(h) {
  if (h.tracker) h._trk = true;
  const steps = [{ id: 'find', label: h.stolen ? 'Get in the driver seat' : 'Find it and take it' }];
  if (h._trk || h.step === 'tracker') steps.push({ id: 'tracker', label: 'Lose the tracker' });
  if (h.chopOnly || h.step === 'chop') steps.push({ id: 'chop', label: 'Take it to a chop shop' });
  else steps.push({ id: 'deliver', label: h.illegal ? 'Store it downstairs' : 'Drive it to your warehouse' });
  let cur = steps.findIndex(s => s.id === h.step); if (cur < 0) cur = 0;
  return steps.map((s, i) => `<div class="hd-step ${i < cur ? 'done' : i === cur ? 'now' : ''}"><i>${i < cur ? '<i class="fa-solid fa-check"></i>' : ''}</i>${esc(s.label)}</div>`).join('');
}
function renderHud() {
  const h = S.hud || (S.hudEdit ? SAMPLE_HUD : null);
  const el = $('#hud');
  if (!h) { show('#hud', false); clearInterval(hudTick); hudTick = null; shownOffer = null; return; }
  show('#hud', true);
  if (h.remaining > S.hudMax) S.hudMax = h.remaining;
  const warn = h.remaining <= 30;
  const flags = [
    h.tracker ? '<span class="flag pulse"><i class="fa-solid fa-tower-broadcast"></i>Tracked</span>' : '',
    h.attack ? '<span class="flag pulse"><i class="fa-solid fa-crosshairs"></i>Under attack</span>' : '',
    h.illegal ? '<span class="flag ill"><i class="fa-solid fa-skull"></i>Illegal</span>' : '',
    h.stolen ? '<span class="flag mut"><i class="fa-solid fa-user-ninja"></i>Stolen</span>' : '',
    h.chopOnly ? '<span class="flag mut"><i class="fa-solid fa-gears"></i>Chop only</span>' : '',
  ].join('');
  const radio = S.radio ? `<span class="radio-chip"><i class="fa-solid fa-walkie-talkie"></i>CH ${esc(S.radio)}</span>` : '';
  const top = `<div class="hd-top">${rar(h.rarity)}${flags}${radio}<span class="grow"></span><span class="hd-time ${warn ? 'warn' : ''}"><i class="fa-solid fa-stopwatch"></i><span id="hd-t">${fmtTime(h.remaining)}</span></span></div>
    <div class="hd-name">${esc(h.label)}${h.plate ? `<small>${esc(h.plate)}</small>` : ''}</div>`;
  const tbar = `<div class="hd-tbar ${warn ? 'warn' : ''}"><i id="hd-tb" style="width:${S.hudMax ? (h.remaining / S.hudMax) * 100 : 100}%"></i></div>`;
  let body;
  if (h.mode === 'source') {
    body = `<div class="hd-obj"><span class="dot ${h.attack ? 'red' : ''}"></span><span>${esc(h.objective || '')}</span></div><div class="hd-steps">${hudSteps(h)}</div>`;
  } else {
    const c = obj(h.counts), D = S.static?.damage || {}, hp = clamp(Math.round(h.health ?? 100), 0, 100);
    const diff = (h.offer || 0) - (h.agreed || 0), pct = h.agreed ? Math.round(diff / h.agreed * 1000) / 10 : 0;
    const segs = Array.from({ length: 20 }, (_, i) => `<i class="${i < Math.ceil(hp / 5) ? (hp >= 60 ? 't' : hp >= 35 ? 'a' : 'r') : ''}"></i>`).join('');
    const hit = k => S.hudHit && S.hudHit.kind === k && Date.now() - S.hudHit.t < 700 ? 'hit' : '';
    body = `${h.objective ? `<div class="hd-obj"><span class="dot ${h.attack ? 'red' : ''}"></span><span>${esc(h.objective)}</span></div>` : ''}
      <div class="hd-offer"><div><span>Buyer pays</span><b id="hd-offer" class="${diff < 0 && S.hudHit && Date.now() - S.hudHit.t < 900 ? 'drop' : ''}">${money(shownOffer ?? h.offer)}</b></div>
        <div class="dl"><span>Agreed ${money(h.agreed)}</span><em class="${diff >= 0 ? 'ok' : ''}">${diff >= 0 ? 'Full price' : `−${money(-diff)} · ${pct}%`}</em></div></div>
      <div><div class="kv" style="margin-bottom:6px"><span>Condition</span><b>${hp}%</b></div><div class="hd-cond">${segs}</div></div>
      <div class="hd-cnt">
        <div class="${hit('hit')}"><span><i class="${esc(D.hit?.icon || 'fa-solid fa-car-burst')}"></i>Hits</span><b>${c.hit || 0}</b></div>
        <div class="${hit('rammed')}"><span><i class="${esc(D.rammed?.icon || 'fa-solid fa-car-side')}"></i>Rams</span><b>${c.rammed || 0}</b></div>
        <div class="${hit('shot')}"><span><i class="${esc(D.shot?.icon || 'fa-solid fa-crosshairs')}"></i>Shots</span><b>${c.shot || 0}</b></div></div>
      <div class="hd-feed" id="hd-feed">${feedHtml()}</div>
      <div class="hd-buyer"><div class="av teal"><i class="fa-solid fa-user-tie"></i></div><div class="row-txt"><b>${esc(h.buyer?.name || 'Buyer')}</b><span>${esc(h.buyer?.label || '')}${h.buyer?.place ? ' · ' + esc(h.buyer.place) : ''}</span></div>
        <div class="row-end"><b>${h.distance != null ? (h.distance / 1000).toFixed(2) + ' km' : '—'}</b><span>to the drop</span></div></div>`;
  }
  el.innerHTML = `<div class="hd" style="${rv(h.rarity)}">${top}${tbar}${body}</div>`;
  el.classList.toggle('edit', !!S.hudEdit);
  el.dataset.tip = 'Drag to move · ENTER save · R reset · ESC cancel';
  placeHud(S.hudEdit);
  if (h.mode === 'sell') tweenOffer(h.offer);
  if (!hudTick) hudTick = setInterval(() => {
    const x = S.hud; if (!x) return;
    x.remaining = Math.max(0, x.remaining - 1);
    const t = $('#hd-t'); if (t) { t.textContent = fmtTime(x.remaining); t.parentElement.classList.toggle('warn', x.remaining <= 30); }
    const b = $('#hd-tb'); if (b && S.hudMax) b.style.width = (x.remaining / S.hudMax) * 100 + '%';
  }, 1000);
}
function tweenOffer(to) {
  const from = shownOffer ?? to; if (from === to) { shownOffer = to; return; }
  const t0 = performance.now(), dur = 650;
  const step = now => {
    const k = Math.min(1, (now - t0) / dur), v = from + (to - from) * (1 - Math.pow(1 - k, 3));
    shownOffer = v; const el = $('#hd-offer'); if (el) el.textContent = money(v);
    if (k < 1) requestAnimationFrame(step); else shownOffer = to;
  };
  requestAnimationFrame(step);
}
const feedHtml = () => S.feed.map(f => `<div class="flash"><i class="${esc(f.icon)}"></i>${esc(f.text)}</div>`).join('');
function hudFlash(f) {
  S.hudHit = { kind: f.kind, t: Date.now() };
  S.feed.unshift({ icon: S.static?.damage?.[f.kind]?.icon || 'fa-solid fa-car-burst', text: `${f.label} · −${f.pct}%`, t: Date.now() });
  S.feed = S.feed.slice(0, 3);
  setTimeout(() => { S.feed = S.feed.filter(x => Date.now() - x.t < 2600); const fe = $('#hd-feed'); if (fe) fe.innerHTML = feedHtml(); }, 2700);
}
function hudEditStart(pos) {
  S.hudPos = pos || null;
  S.hudEdit = { ...(pos || HUD_DEFAULT) };
  renderHud();
}
function hudEditEnd(mode) {
  const e = S.hudEdit; if (!e) return;
  S.hudEdit = null;
  if (mode === 'save') { S.hudPos = { x: e.x, y: e.y }; post('hudSave', { x: e.x, y: e.y }); toast('HUD position saved'); }
  else if (mode === 'reset') { S.hudPos = null; post('hudSave', { reset: true }); toast('HUD position reset'); }
  else post('hudSave', { cancel: true });
  placeHud(); renderHud();
}

/* ═══════════════════════════════════════════════════════════
   BANNER · SMS · CINEMATIC · LEVEL UP
   ═══════════════════════════════════════════════════════════ */
let bannerTimer = null;
function banner(b) {
  const el = $('#banner');
  const words = String(b.title || '').split(' ');
  const title = words.length > 1 ? `${esc(words.slice(0, -1).join(' '))} <em>${esc(words.slice(-1)[0])}</em>` : `<em>${esc(b.title)}</em>`;
  const stats = arr(b.stats).map(s => `<div><span>${esc(s[0])}</span><b>${esc(s[1])}</b></div>`).join('');
  const extra = [];
  if (b.counts) extra.push(`${b.counts.hit || 0} hits · ${b.counts.rammed || 0} rams · ${b.counts.shot || 0} shots`);
  if (b.streak) extra.push(`clean streak ${b.streak}`);
  if (arr(b.cuts).length) extra.push('associate cuts: ' + arr(b.cuts).map(c => `${esc(c.name)} ${money(c.amount)}`).join(', '));
  el.innerHTML = `<div class="bn ${b.kind === 'fail' ? 'fail' : ''}"><h2>${title}</h2>
    <div class="s">${b.rarity ? rar(b.rarity) : ''}<span>${esc(b.subtitle || '')}</span></div>${stats ? `<div class="st">${stats}</div>` : ''}${extra.length ? `<div class="x">${extra.join(' · ')}</div>` : ''}</div>`;
  show('#banner', true);
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => { const bn = $('.bn', el); if (bn) bn.classList.add('out'); setTimeout(() => show('#banner', false), 450); }, b.kind === 'fail' ? 5000 : 7500);
}

function sms(m) {
  const box = $('#sms');
  const el = document.createElement('div'); el.className = 'sms';
  el.innerHTML = `<div class="av"><i class="fa-solid fa-user-secret"></i></div><div class="tx">
    <div class="tp"><i class="fa-solid fa-message"></i>Messages<span class="grow"></span>now</div>
    <b>${esc(m.from || 'Unknown')}</b><p>${esc(m.text || '')}</p></div>`;
  box.prepend(el);
  while (box.children.length > 3) box.lastChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 320); }, 8000);
}

function cine(on) {
  $('#cine').classList.toggle('on', !!on);
  document.body.classList.toggle('cine', !!on);
}

let lvTimer = null;
function levelUp(level, prestige) {
  const el = $('#lvlup');
  el.innerHTML = prestige
    ? `<div class="lv"><div class="ic"><i class="fa-solid fa-crown"></i></div><div><span>Prestige up</span><b>Prestige ${esc(prestige)}</b></div></div>`
    : `<div class="lv"><div class="ic"><i class="fa-solid fa-angles-up"></i></div><div><span>Level up</span><b>Level ${esc(level)}</b></div></div>`;
  show('#lvlup', true);
  clearTimeout(lvTimer);
  lvTimer = setTimeout(() => { const lv = $('.lv', el); if (lv) lv.classList.add('out'); setTimeout(() => show('#lvlup', false), 400); }, 3600);
}

const audio = $('#music');
let fadeTimer = null;
function music(m) {
  if (!m.file) return;
  clearInterval(fadeTimer);
  const vol = m.volume || .35;
  const start = () => {
    audio.src = `sounds/${m.file}`; audio.loop = !m.last; audio.volume = 0; audio.play().catch(() => {});
    let v = 0; fadeTimer = setInterval(() => { v = Math.min(vol, v + .03); audio.volume = v; if (v >= vol) clearInterval(fadeTimer); }, 60);
  };
  if (!audio.paused) { let v = audio.volume; fadeTimer = setInterval(() => { v = Math.max(0, v - .05); audio.volume = v; if (v <= 0) { clearInterval(fadeTimer); start(); } }, 40); }
  else start();
}

/* ═══════════════════════════════════════════════════════════
   PLACEMENT GUIDE · SPEC CARD
   ═══════════════════════════════════════════════════════════ */
function guide(g) {
  const el = $('#guide');
  if (!g || g.hide) { show('#guide', false); return; }
  el.innerHTML = `<h4>${esc(g.title || 'Place')}</h4>${g.status ? `<div class="st"><span class="dot"></span>${esc(g.status)}</div>` : '<div style="height:10px"></div>'}
    <div class="rows">${arr(g.keys).map(k => `<div class="r"><span class="key">${esc(k[0])}</span><span>${esc(k[1])}</span></div>`).join('')}</div>`;
  show('#guide', true);
}
function spec(d) {
  const el = $('#spec');
  if (!d || d.hide) { show('#spec', false); return; }
  if (d.car) {
    const c = d.car, ill = R(c.rarity).illegal;
    el.innerHTML = `<div class="sc" style="${rv(c.rarity)}">
      <div class="sc-top">${c.base && c.base !== c.rarity ? `${rar(c.base)}<i class="fa-solid fa-arrow-right dim" style="font-size:9px"></i>` : ''}${rar(c.rarity)}<span class="grow"></span><span class="sc-plate">${esc(c.plate || '')}</span></div>
      <h3>${esc(c.label)}</h3>
      <div class="sc-g">
        <div><span>Condition</span><b>${c.condition}%</b><div class="bar-line ${c.condition < 60 ? 'red' : ''}"><i style="width:${clamp(c.condition, 0, 100)}%"></i></div></div>
        <div><span>Build</span><b>${c.score}<span style="display:inline;font-size:10px;color:var(--ink-3)"> / 100</span></b></div>
        <div><span>Worth</span><b class="pos">${money(c.value)}</b></div>
      </div>
      <div class="sc-f"><i class="fa-solid ${ill ? 'fa-skull' : 'fa-eye'}"></i>${ill ? 'Illegal stock · sells high, draws attention' : 'Third-eye to customize in the back'}</div></div>`;
    el.classList.remove('off');
    show('#spec', true);
  }
  if (d.offscreen) el.classList.add('off');
  if (d.x !== undefined) { const sc = S.scale || 1; el.classList.remove('off'); el.style.left = (d.x * window.innerWidth / sc) + 'px'; el.style.top = (d.y * window.innerHeight / sc - 10) + 'px'; }
}

/* ═══════════════════════════════════════════════════════════
   ACTIONS
   ═══════════════════════════════════════════════════════════ */
async function termCall(action, data, okMsg) {
  if (S.busy) return; S.busy = true;
  const r = await post(action, data); S.busy = false;
  if (r && r.profile) { S.term = r; planBox = null; if (okMsg) toast(okMsg); refresh(); return r; }
  if (r && r.ok === false) toast('That didn\'t go through', 'Check your balance and try again.', false);
  return r;
}
function adminApply(r, msg = 'Live for everyone now.') {
  if (r && r.vehicles) { if (!r.here && S.admin && S.admin.here) r.here = S.admin.here; S.admin = r; refresh(); toast('Saved', msg); }
  else if (r !== true) toast('Failed', 'The server refused the change.', false);
}
const num = v => Number(v);

const ACT = {
  close: () => post('close'),
  mdYes: () => closeModal(true),
  mdNo: () => closeModal(false),
  exit: async () => { if (await modal({ title: 'Leave the warehouse?', text: 'The laptop shuts down and you walk out the front door.', confirm: 'Leave', icon: 'fa-door-open' })) post('exit'); },

  /* laptop shell */
  open: d => openApp(d.id),
  tab: d => openApp(d.id),
  power: () => post('laptopClose'),
  startMenu: () => { LT.start = !LT.start; renderChrome(); },
  task: d => {
    const w = LT.wins[d.id]; if (!w) return;
    if (w.min) { w.min = false; focusWin(d.id, true); renderWins(); }
    else if (LT.focus === d.id) { w.min = true; LT.focus = null; renderWins(); }
    else focusWin(d.id);
    renderChrome();
  },
  winMin: d => { LT.wins[d.id].min = true; if (LT.focus === d.id) LT.focus = null; renderWins(); renderChrome(); },
  winMax: d => { const w = LT.wins[d.id]; w.max = !w.max; renderWins(); },
  winClose: d => closeWin(d.id),
  skipLogin: () => { if (LT.stage === 'login') unlock(); },
  pref: d => savePref(d.k, d.v === 'true' ? true : d.v === 'false' ? false : d.v),
  prefToggle: d => savePref(d.id, !S.prefs[d.id]),
  prefClock: () => savePref('clock', S.prefs.clock === '24' ? '12' : '24'),
  hudMove: () => post('hudMove'),
  scanRefresh: async () => { const r = await post('terminal'); if (r && r.profile) { S.term = r; refresh(); toast('Scan complete', `${arr(r.hot).length} signal(s)`); } },
  waypoint: d => { post('waypoint', { x: num(d.x), y: num(d.y) }); toast('Waypoint set', 'Check your map.'); },
  floor: d => { S.floor = d.id; S.stockSel = null; S.offers = null; S.offersFor = null; refreshBodies(); },

  /* business */
  stockSel: d => { S.stockSel = num(d.id); S.offers = null; S.offersFor = null; refreshBodies(); },
  source: async d => {
    const c = S.term.contracts.find(x => x.rarity === d.id), r = c.special ? { label: c.label } : R(d.id);
    const text = c.illegal ? `Costs ${money(c.fee)}. Illegal cars are watched: expect a tracker, armed crews and police interest. It goes downstairs when you deliver.`
      : `Costs ${money(c.fee)}. The target goes on your GPS and the clock starts right away.`;
    if (!await modal({ title: `Take a ${r.label} contract?`, text, confirm: 'Take contract', icon: c.illegal ? 'fa-skull' : 'fa-file-signature', danger: !!c.illegal })) return;
    const res = await post('source', { rarity: d.id });
    if (!res || res.ok === false) toast('Contract not available', 'Check cooldown, capacity and police on duty.', false);
  },
  design: d => post('design', { id: num(d.id) }),
  repair: d => termCall('repair', { id: num(d.id) }, 'Vehicle repaired'),
  scrap: async d => {
    const s = S.term.stock.find(x => x.id === num(d.id));
    if (!await modal({ title: `Scrap the ${s.label}?`, text: 'It is crushed for parts and you get 10% of its value back. This cannot be undone.', confirm: 'Scrap vehicle', danger: true })) return;
    termCall('scrap', { id: num(d.id) }, 'Vehicle scrapped');
  },
  offers: async d => {
    const r = await post('offers', { id: num(d.id) });
    if (r && r.offers) { S.offers = r; S.offersFor = num(d.id); refreshBodies(); const b = $('#detail-body'); if (b) b.scrollTop = b.scrollHeight; }
    else toast('No buyers right now', 'Try again in a moment.', false);
  },
  sellStart: async d => {
    const o = arr(S.offers.offers).find(x => String(x.index) === d.buyer);
    if (!await modal({ title: `Deliver to ${o.name}?`, text: `They're offering ${money(o.amount)}. Every hit, ram and bullet on the way lowers the price.`, confirm: 'Start delivery', icon: 'fa-truck-fast' })) return;
    const r = await post('sellStart', { id: num(d.id), buyer: num(d.buyer) });
    if (!r || r.ok === false) toast('Sale could not start', 'Check your sale cooldown.', false);
  },
  sellQuick: async d => {
    if (!await modal({ title: 'Quick export?', text: `Sell instantly for ${money(S.offers.quick)}.`, confirm: 'Export', icon: 'fa-ship' })) return;
    S.offers = null; S.offersFor = null;
    termCall('sellQuick', { id: num(d.id) }, 'Vehicle exported');
  },
  upgrade: async d => {
    const cfg = S.static.upgrades[d.track], lv = S.term.warehouse.upgrades[d.track] || 0, nxt = arr(cfg.levels)[lv + 1];
    if (!await modal({ title: `Upgrade ${cfg.label}?`, text: `${upEffect(d.track, nxt)}. This costs ${money(nxt.price)} and is permanent for this warehouse.`, confirm: 'Upgrade', icon: 'fa-arrow-up' })) return;
    termCall('upgrade', { track: d.track }, `${cfg.label} upgraded`);
  },
  style: async d => {
    const st = arr(S.static.upgrades.style.styles).find(s => s.id === d.id), owned = obj(S.term.warehouse.upgrades.owned_styles);
    if (S.term.warehouse.upgrades.style === d.id) return;
    if (!owned[d.id] && st.price > 0 && !await modal({ title: `Switch to ${st.label}?`, text: `Costs ${money(st.price)} once. Switching back later is free.`, confirm: 'Buy style', icon: 'fa-paint-roller' })) return;
    termCall('upgrade', { track: 'style', choice: d.id }, `${st.label} style active`);
  },
  layoutPreset: async d => {
    const p = arr(S.term.layout.presets).find(x => x.id === d.id);
    if (!await modal({ title: `Use ${p.label}?`, text: 'Your cars move to the new spots straight away. Cars past the spot count stay stored but are not shown.', confirm: 'Apply layout', icon: 'fa-border-all' })) return;
    termCall('layoutPreset', { id: d.id }, `${p.label} applied`);
  },
  layoutReset: async () => { if (await modal({ title: 'Back to the server default?', text: 'Your own layout or preset is cleared.', confirm: 'Reset', icon: 'fa-rotate-left' })) termCall('layoutReset', {}, 'Layout reset'); },
  layoutCustom: () => post('layoutCustom'),
  planPick: d => { const i = num(d.id); S.planDel.has(i) ? S.planDel.delete(i) : S.planDel.add(i); refreshBodies(); },
  planTurn: d => { const ed = S.planEdit; if (!ed || ed.sel < 0) return; const s = ed.slots[ed.sel]; s.w = (((s.w || 0) + num(d.id)) % 360 + 360) % 360; ed.dirty = true; refreshBodies(); },
  planDrop: () => { const ed = S.planEdit; if (!ed || ed.sel < 0 || ed.slots.length <= 1) return; ed.slots.splice(ed.sel, 1); ed.sel = -1; ed.dirty = true; refreshBodies(); },
  planAdd: () => {
    const ed = planEditStart(), L = S.term.layout; if (ed.slots.length >= L.max) return;
    const a = L.area, last = ed.slots[ed.slots.length - 1] || {};
    const z = last.z ?? a?.z ?? 0;
    ed.slots.push(a && a.min ? { x: (a.min.x + a.max.x) / 2, y: (a.min.y + a.max.y) / 2, z, w: 0 } : { x: (last.x || 0) + 3.5, y: last.y || 0, z, w: last.w || 0 });
    ed.sel = ed.slots.length - 1; ed.dirty = true; refreshBodies();
  },
  planDiscard: () => { S.planEdit = null; refreshBodies(); },
  planSave: async () => {
    const ed = S.planEdit; if (!ed) return;
    const bad = ed.slots.filter(s => !carFits(s, S.term.layout.area)).length;
    if (bad && !await modal({ title: `Save with ${bad} clipping spot${bad === 1 ? '' : 's'}?`, text: 'Red spots overlap a wall or prop. Cars parked there will clip into it.', confirm: 'Save anyway', danger: true })) return;
    const slots = ed.slots; S.planEdit = null;
    termCall('layoutSet', { slots }, 'Floor plan saved');
  },
  planClear: () => { S.planDel.clear(); refreshBodies(); },
  planRemove: async () => {
    const n = S.planDel.size, slots = arr(S.term.layout.slots).filter((_, i) => !S.planDel.has(i));
    if (!n || !slots.length) return;
    if (!await modal({ title: `Remove ${n} spot${n === 1 ? '' : 's'}?`, text: 'Your floor becomes your own layout. Cars past the new spot count stay in stock but are not parked on the floor.', confirm: 'Remove', danger: true })) return;
    S.planDel.clear();
    termCall('layoutSet', { slots }, `${n} spot${n === 1 ? '' : 's'} removed`);
  },
  trackerHowTo: () => post('trackerHowTo'),
  lbTab: d => { S.lbTab = d.id; refresh(); },
  assocPick: async () => {
    const list = arr(await post('nearby'));
    const html = list.length ? `<div style="display:flex;flex-direction:column;gap:6px;max-height:280px;overflow:auto">${list.map(p => `<button class="row" data-act="assocAdd" data-id="${p.id}"><div class="av">${esc(initials(p.name))}</div><div class="row-txt"><b>${esc(p.name)}</b><span>Server ID ${p.id}</span></div><span class="tag live">Add</span></button>`).join('')}</div>`
      : empty('fa-user-slash', 'Nobody close by', 'They need to be within 25 m of you.');
    modal({ title: 'Add an associate', text: 'Pick a player standing near you.', html, confirm: null, cancel: 'Close', icon: 'fa-user-plus' });
  },
  assocAdd: d => { closeModal(false); termCall('assocAdd', { id: num(d.id) }, 'Associate added'); },
  dealMode: () => { S.deal = S.deal ? null : { pick: new Set(), offers: null, opt: 0, assign: {} }; refreshBodies(); },
  dealToggle: d => {
    const dl = S.deal; if (!dl) return; const id = num(d.id), max = obj(S.static.crewSale).MaxCars || 4;
    if (dl.pick.has(id)) dl.pick.delete(id); else if (dl.pick.size < max) dl.pick.add(id); else toast('That\'s the limit', `Up to ${max} cars in one deal.`, false);
    dl.offers = null; refreshBodies();
  },
  dealOffers: async () => {
    const dl = S.deal; if (!dl) return;
    const r = await post('dealOffers', { ids: [...dl.pick] });
    if (!r || r.ok === false || !r.options) { toast('No buyers', 'Check your role, the cars and try again.', false); return; }
    dl.offers = r; dl.opt = 0; dl.assign = {};
    // you take the first car, the rest of the crew the others in order
    const crew = arr(r.crew).map(m => m.src).sort((a, b) => (a === r.me ? -1 : b === r.me ? 1 : 0));
    arr(r.options[0].cars).forEach((c, i) => { if (crew[i] !== undefined) dl.assign[c.stockId] = crew[i]; });
    refreshBodies();
  },
  dealOpt: d => { if (S.deal) { S.deal.opt = num(d.id); refreshBodies(); } },
  dealBack: () => { if (S.deal) { S.deal.offers = null; refreshBodies(); } },
  dealStart: async () => {
    const dl = S.deal; if (!dl || !dl.offers) return;
    const cur = dl.offers.options[dl.opt];
    if (!await modal({ title: `Start the crew sale for ${money(cur.total)}?`, text: 'Every driver gets their car outside. Nobody is paid until every car is dropped or lost.', confirm: 'Start crew sale', icon: 'fa-people-arrows' })) return;
    const assign = {}; Object.entries(dl.assign).forEach(([k, v]) => { assign[k] = num(v); });
    const r = await post('dealStart', { option: dl.opt + 1, assign });
    if (!r || r.ok === false) { toast('Crew sale not started', 'Check the drivers are inside and free.', false); return; }
    S.deal = null;
  },
  insure: async d => {
    const s = S.term.stock.find(x => x.id === num(d.id)); if (!s) return;
    if (await modal({ title: `Insure the ${s.label}?`, text: `Costs ${money(s.premium)} once. Pays out if it is lost on a sale or seized in a raid.`, confirm: 'Insure', icon: 'fa-shield-halved' })) termCall('insure', { id: s.id }, 'Insured');
  },
  claims: () => termCall('claims', {}, 'Claims collected'),
  bribe: async () => {
    const b = obj(S.static.bribe);
    if (await modal({ title: 'Pay off a contact?', text: `${money(b.Price)} drops your heat by ${b.Step}.`, confirm: 'Pay', icon: 'fa-money-bill-transfer' })) termCall('bribe', { steps: 1 }, 'Heat lowered');
  },
  prestige: async () => {
    const p = S.term.profile;
    if (await modal({ title: `Prestige ${p.prestige + 1}?`, text: `Your level goes back to 1${p.prestigeCost ? ` and it costs ${money(p.prestigeCost)}` : ''}. You keep your unlocks and get a permanent bonus.`, confirm: 'Prestige', icon: 'fa-crown' })) termCall('prestige', {}, 'Prestige up');
  },
  crewJob: async d => {
    const cj = arr(S.term.crewJobs?.jobs).find(j => j.id === d.id); if (!cj) return;
    if (!await modal({ title: `Start ${cj.label}?`, text: `Costs ${money(cj.fee)}. Everyone in your crew inside the warehouse gets a car to bring home. All of them home = ${money(cj.bonusCash)} each.`, confirm: 'Start crew job', icon: 'fa-people-group' })) return;
    const r = await post('crewJob', { id: d.id });
    if (!r || r.ok === false) toast('Crew job not available', 'Check the crew inside, cooldown and capacity.', false);
  },
  assocRemove: async d => { if (await modal({ title: 'Remove associate?', text: 'They lose access to this warehouse straight away.', confirm: 'Remove', danger: true })) termCall('assocRemove', { identifier: d.id }, 'Associate removed'); },

  /* broker */
  shopSel: d => { S.shopSel = num(d.id); renderShop(); },
  shopWay: d => { const l = S.shop.locations.find(x => x.id === num(d.id)); if (l && l.door) { post('waypoint', { x: l.door.x, y: l.door.y }); toast('Waypoint set', l.name); } },
  buy: async () => {
    const l = S.shop.locations.find(x => x.id === S.shopSel);
    if (!l || l.owned) return;
    if (!await modal({ title: `Buy ${l.name}?`, text: `${money(l.price)} from your bank. Your unit is private, and the door goes on your GPS.`, confirm: 'Buy warehouse', icon: 'fa-key' })) return;
    const r = await post('buy', { location: l.id });
    if (!r || r.ok === false) toast('Purchase failed', 'Check your balance.', false);
  },

  /* admin */
  adminTab: d => { S.adminTab = d.id; refresh(); },
  vSave: async () => {
    const f = S.vForm; if (!f.model) return;
    const existing = arr(S.admin.vehicles).find(v => v.model === f.model);
    const r = await post('adminSaveVehicle', { model: f.model, label: f.label || f.model, rarity: f.rarity || 'common', value: num(f.value) || 0, enabled: existing ? existing.enabled : true });
    S.vForm = {}; adminApply(r);
  },
  vEdit: d => { const v = arr(S.admin.vehicles).find(x => x.model === d.id); S.vForm = { ...v, editing: true }; refresh(); },
  vCancel: () => { S.vForm = {}; refresh(); },
  vToggle: async d => { const v = arr(S.admin.vehicles).find(x => x.model === d.id); adminApply(await post('adminSaveVehicle', { ...v, enabled: !v.enabled })); },
  vDelete: async d => { if (await modal({ title: `Remove ${d.id}?`, text: 'Custom entries are deleted. Overrides go back to the default values.', confirm: 'Remove', danger: true })) adminApply(await post('adminDeleteVehicle', { model: d.id })); },
  lPlace: async d => { const r = await post('adminPlace', { draft: { ...S.lForm }, key: d.id }); if (r === false || (r && r.ok === false)) toast('Leave the warehouse first', 'Place warehouses from /cargoadmin outside.', false); },
  lImport: async () => { if (await modal({ title: 'Import from config?', text: 'Warehouses in Config.SeedWarehouses are added, and ones with the same name get the config coords and price.', confirm: 'Import', icon: 'fa-file-import' })) adminApply(await post('adminImportSeeds'), 'Warehouses imported.'); },
  lSave: async () => { const f = S.lForm; const r = await post('adminSaveLocation', { id: f.id, name: f.name, price: num(f.price) || 0, door: f.door, garage: f.garage, garageExit: f.garageExit, spawn: f.spawn, enabled: f.enabled !== false }); S.lForm = {}; adminApply(r, 'Every broker lists it now.'); },
  lCancel: () => { S.lForm = {}; refresh(); },
  lEdit: d => { const l = arr(S.admin.locations).find(x => x.id === num(d.id)); S.lForm = { ...l }; refresh(); },
  lToggle: async d => { const l = arr(S.admin.locations).find(x => x.id === num(d.id)); adminApply(await post('adminSaveLocation', { ...l, enabled: !l.enabled })); },
  lTp: d => { const l = arr(S.admin.locations).find(x => x.id === num(d.id)); post('adminTeleport', { coords: l.door }); },
  lDelete: async d => { if (await modal({ title: 'Delete location?', text: 'If anyone owns a warehouse here it is disabled instead, so owners keep access.', confirm: 'Delete', danger: true })) adminApply(await post('adminDeleteLocation', { id: num(d.id) })); },
  iPreview: async () => { const r = await post('adminPreview'); if (r === false || (r && r.ok === false)) toast('Could not open the setup copy', 'Leave the warehouse you are in first.', false); },
  iPlace: async d => { const r = await post('adminInterior', { key: d.id }); if (r === false || (r && r.ok === false)) toast('Go inside first', 'Open the setup copy.', false); },
  iSpots: async d => { const name = ($('#i-preset')?.value || '').trim(); const r = await post('adminSpots', { floor: d.id, preset: name || undefined }); if (r === false || (r && r.ok === false)) toast('Go inside first', 'Open the setup copy.', false); },
  iReset: async d => { if (await modal({ title: 'Back to the default?', text: 'This point goes back to the position in the config.', confirm: 'Reset', icon: 'fa-rotate-left' })) adminApply(await post('adminInteriorReset', { keys: [d.id] }), 'Interior updated.'); },
  bPlace: async () => { const r = await post('adminPlaceBroker'); if (r === false || (r && r.ok === false)) toast('Leave the warehouse first', 'Brokers are placed from /cargoadmin outside.', false); },
  bTp: d => { const b = arr(S.admin.brokers)[num(d.id)]; if (b) post('adminTeleport', { coords: b }); },
  bRemove: async d => { if (await modal({ title: 'Remove this broker?', text: 'The NPC disappears for everyone.', confirm: 'Remove', danger: true })) adminApply(await post('adminRemoveBroker', { index: num(d.id) })); },
  iFloor: d => post('adminFloor', { kind: d.id }),
  iFloorClear: async () => { if (await modal({ title: 'Clear every obstacle?', text: 'Presets will use the whole floor area again.', confirm: 'Clear', danger: true })) adminApply(await post('adminFloorClear')); },
  pDelete: async d => { if (await modal({ title: 'Delete this preset?', text: 'Owners using it fall back to the server default.', confirm: 'Delete', danger: true })) adminApply(await post('adminDeletePreset', { id: d.id })); },
  wWipe: async d => { if (await modal({ title: `Wipe warehouse #${d.id}?`, text: 'The warehouse and every vehicle inside are deleted. Anyone inside is sent out.', confirm: 'Wipe warehouse', danger: true })) adminApply(await post('adminWipe', { id: num(d.id) })); },
  pXp: async d => { const i = document.querySelector(`[data-xp="${CSS.escape(d.id)}"]`); const n = num(i?.value); if (!n) return; adminApply(await post('adminXp', { identifier: d.id, amount: n })); },
  pCd: async d => adminApply(await post('adminCooldowns', { identifier: d.id })),

  /* design bay */
  wsClose: async () => {
    const ws = S.ws; if (!ws) return;
    if (!same(ws.build, ws.saved) && !await modal({ title: 'Leave without applying?', text: 'Your unapplied changes are thrown away.', confirm: 'Leave', danger: true })) return;
    post('wsClose');
  },
  wsWash: async () => {
    const ws = S.ws; if (S.busy || !ws || ws.data.clean) return;
    S.busy = true;
    const r = await post('wsWash'); S.busy = false;
    if (!r || r.ok === false) { toast('Wash failed', 'Check your balance.', false); return; }
    ws.data.clean = true; if (r.cash !== undefined) ws.data.cash = r.cash;
    toast('Washed', 'Spotless.');
    renderMenu();
  },
  wsBuy: async () => {
    const ws = S.ws; if (S.busy || !ws) return;
    const { total } = Cargo.cost(ws.saved, ws.build, ws.data.stock.base_rarity);
    if (total > 0 && !await modal({ title: `Apply build for ${money(total)}?`, text: 'Paid from your balance. The score and rarity update straight away.', confirm: 'Apply build', icon: 'fa-spray-can-sparkles' })) return;
    S.busy = true;
    const r = await post('wsBuy', { build: ws.build }); S.busy = false;
    if (!r || r.ok === false || !r.stock) { toast('Build not saved', 'Check your balance and try again.', false); return; }
    const before = ws.data.stock.rarity;
    ws.data.stock.rarity = r.stock.rarity; ws.data.stock.score = r.stock.score; ws.data.cash = r.cash;
    ws.saved = clone(obj(r.stock.build)); ws.build = clone(ws.saved);
    if (R(r.stock.rarity).index > R(before).index && !R(before).illegal) toast(`Rarity raised to ${R(r.stock.rarity).label}`, `Build score ${r.stock.score}`);
    else toast('Build saved', `Build score ${r.stock.score}`);
    ws.stack = [ws.stack[0]];
    renderMenu();
  },
};

document.addEventListener('click', e => {
  const el = e.target.closest('[data-act]'); if (!el || el.disabled) return;
  beep('click');
  const fn = ACT[el.dataset.act]; if (fn) fn(el.dataset, el, e);
});
document.addEventListener('input', e => {
  const el = e.target; const f = el.dataset.form; if (!f) return;
  (f === 'v' ? S.vForm : S.lForm)[el.dataset.k] = el.value;
  if (f === 'l') { const b = document.querySelector('[data-act="lSave"]'); if (b) b.disabled = !(S.lForm.name && S.lForm.door && S.lForm.garage && S.lForm.spawn); }
});
document.addEventListener('change', e => {
  const el = e.target;
  if (el.dataset && el.dataset.role) { termCall('setRole', { identifier: el.dataset.role, role: el.value }, 'Role updated'); return; }
  if (el.dataset && el.dataset.driver && S.deal) { S.deal.assign[el.dataset.driver] = el.value ? num(el.value) : undefined; refreshBodies(); return; } const f = el.dataset.form; if (!f) return;
  (f === 'v' ? S.vForm : S.lForm)[el.dataset.k] = el.value;
});
document.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT' && e.key !== 'Escape') return;
  if (S.hudEdit) {
    if (e.key === 'Enter') hudEditEnd('save');
    else if (e.key === 'Escape') hudEditEnd('cancel');
    else if (e.key === 'r' || e.key === 'R') hudEditEnd('reset');
    return;
  }
  if (modalOpen()) { if (e.key === 'Escape') closeModal(false); else if (e.key === 'Enter') { e.preventDefault(); closeModal(true); } return; }
  if (S.view === 'workshop') {
    const k = e.key;
    if (k === 'ArrowUp' || k === 'ArrowLeft') { e.preventDefault(); wsMove(-1); }
    else if (k === 'ArrowDown' || k === 'ArrowRight') { e.preventDefault(); wsMove(1); }
    else if (k === 'Enter') { e.preventDefault(); wsSelect(); }
    else if (k === 'Backspace') { e.preventDefault(); wsBack(); }
    else if (k === 'Escape') ACT.wsClose();
    return;
  }
  if (e.key === 'Escape') {
    if (S.view === 'laptop') { if (LT.start) { LT.start = false; renderChrome(); return; } post('laptopClose'); return; }
    if (S.view) post('close');
  } else if (e.key === 'Enter' && S.view === 'shop') { const b = $('[data-act="buy"]'); if (b && !b.disabled) b.click(); }
});

/* live cooldown counters */
setInterval(() => {
  $$('[data-cd]').forEach(el => {
    const left = (Number(el.dataset.cd) - Date.now()) / 1000;
    el.textContent = fmtTime(left);
    if (left <= 0 && S.view === 'laptop') { el.removeAttribute('data-cd'); post('terminal').then(r => { if (r && r.profile) { S.term = r; refresh(); } }); }
  });
}, 1000);

/* ═══════════════════════════════════════════════════════════
   MESSAGES FROM LUA
   ═══════════════════════════════════════════════════════════ */
function openView(view, data, stat) {
  if (stat) S.static = stat;
  closeModal(false);
  ['#terminal', '#shop', '#workshop'].forEach(id => show(id, false));
  if (view !== 'laptop' && S.view === 'laptop') closeLaptop();
  S.view = view;
  if (view === 'laptop') openLaptop(data);
  else if (view === 'admin') {
    S.adminOnly = true; S.admin = data.admin || null;
    if (data.tab) S.adminTab = data.tab;
    if (data.placed) { S.lForm = { ...(data.draft || {}), ...data.placed }; S.adminTab = 'locations'; }
    show('#terminal', true); renderTerminal();
  } else if (view === 'shop') {
    S.shop = data; S.shopSel = null; show('#shop', true); renderShop();
  } else if (view === 'workshop') {
    const st = data.stock; st.build = obj(st.build);
    S.ws = { data, build: clone(st.build), saved: clone(st.build), stack: [{ key: 'root', idx: 0, top: 0 }], lights: true };
    show('#workshop', true); renderMenu();
  }
}
function closeAll() {
  closeModal(false);
  if (S.view === 'laptop') closeLaptop();
  ['#terminal', '#shop', '#workshop'].forEach(id => show(id, false));
  S.view = null; S.ws = null; S.adminOnly = false;
}

window.addEventListener('message', e => {
  const { action, data } = e.data || {};
  switch (action) {
    case 'open': openView(data.view, data.data, data.static); break;
    case 'close': closeAll(); break;
    case 'laptopApp': if (S.view === 'laptop' && data && data.app) openApp(data.app); break;
    case 'hud': {
      if (data.flash) hudFlash(data.flash);
      if (data.mode === 'none') { S.hud = null; S.hudMax = 0; S.feed = []; }
      else { if (S.hud && S.hud.mode !== data.mode) S.hudMax = 0; S.hud = { ...(S.hud && S.hud.mode === data.mode ? S.hud : {}), ...data }; }
      renderHud(); break;
    }
    case 'hudPos': S.hudPos = data && data.pos && data.pos.x != null ? data.pos : null; placeHud(); break;
    case 'hudEdit': hudEditStart(data && data.pos); break;
    case 'banner': banner(data); break;
    case 'levelUp': levelUp(data.level, data.prestige); break;
    case 'sms': sms(data || {}); break;
    case 'cine': cine(data && data.on); break;
    case 'music': music(data); break;
    case 'prefs': if (data && data.options) S.bootOptions = data.options; S.myPrefs = { ...PREF_DEFAULT, ...obj(data && data.prefs) }; if (S.view !== 'laptop') applyPrefs(S.myPrefs); break;
    case 'guide': guide(data); break;
    case 'spec': spec(data); break;
    case 'radio': S.radio = data && data.channel ? data.channel : null; if (S.hud) renderHud(); if (S.view === 'laptop') { renderChrome(); refreshBodies(); } break;
  }
});
placeHud();
