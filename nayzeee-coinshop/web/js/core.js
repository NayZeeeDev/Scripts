/* ════════════════════════════════════════════════════════════════════════
   nayzeee-coinshop — core: state, helpers, transport, theme, render loop
   ════════════════════════════════════════════════════════════════════════ */
'use strict';
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-coinshop';
const $app = document.getElementById('app');
const $toasts = document.getElementById('toasts');
const $td = document.getElementById('td');

const S = {
  open: false, loading: true, loc: {}, cfg: null, me: null, admin: false,
  items: [], cats: [], deals: [], favs: new Set(), settings: {},
  page: 'home', cat: 'all', q: '', sort: 'featured', tag: null, heroIdx: 0,
  modal: null, history: null, histTab: 'purchases', busy: null,
  adm: { tab: 'dashboard', dash: null, logs: null, logQ: '', players: null, playerQ: '', codes: null, codeQ: '', pkgQ: '', pkgCat: 'all', deals: null },
};

// ── helpers ──────────────────────────────────────────────────────────────
function t(key, ...a) {
  let s = S.loc[key] ?? key;
  let i = 0;
  return String(s).replace(/%[sd]/g, () => (a[i++] ?? ''));
}
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const num = n => Number(n || 0).toLocaleString('en-US');
const initials = s => String(s || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase() || '?';
const wait = ms => new Promise(r => setTimeout(r, ms));
function clock(sec) {
  sec = Math.max(0, Math.floor(sec));
  const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
  if (d > 0) return `${d}d ${h}h ${String(m).padStart(2, '0')}m`;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}
function ago(ts) {
  if (!ts) return '—';
  const s = Date.now() / 1000 - Number(ts);
  if (s < 60) return t('UI_JUST_NOW');
  if (s < 3600) return t('UI_MIN_AGO', Math.floor(s / 60));
  if (s < 86400) return t('UI_HOUR_AGO', Math.floor(s / 3600));
  if (s < 86400 * 30) return t('UI_DAY_AGO', Math.floor(s / 86400));
  return new Date(ts * 1000).toLocaleDateString();
}
const CAT_ICON = { vehicle: 'fa-car-side', item: 'fa-box-open', weapon: 'fa-crosshairs', tool: 'fa-screwdriver-wrench' };
const DEFAULT_COIN = `<svg viewBox="0 0 24 24"><defs><linearGradient id="cg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="var(--teal-hi)"/><stop offset="1" stop-color="var(--teal-lo)"/></linearGradient></defs><circle cx="12" cy="12" r="11" fill="url(#cg)"/><circle cx="12" cy="12" r="8.2" fill="none" stroke="rgba(0,0,0,.35)" stroke-width="1.2"/><path d="M8.5 8.5h7v3.8l-3.2 3.2H8.5z" fill="rgba(0,0,0,.55)"/></svg>`;
function coin() {
  const u = S.settings.coinIcon;
  return `<span class="coin">${u ? `<img src="${esc(u)}" alt="">` : DEFAULT_COIN}</span>`;
}
function img(src, fb = 'fa-image') {
  return src ? `<img src="${esc(src)}" alt="" onerror="this.outerHTML='<i class=&quot;fas ${fb} noimg&quot;></i>'">` : `<i class="fas ${fb} noimg"></i>`;
}
function catIcon(icon, fallback = 'fa-tag') {
  if (!icon) return `<i class="fas ${fallback}"></i>`;
  if (/^(https?:|data:|nui:)/.test(icon)) return `<span class="ic"><img src="${esc(icon)}" alt=""></span>`;
  return `<i class="fas ${esc(icon.replace(/^fas?\s+/, ''))}"></i>`;
}
function avatar(p, size) {
  return `<div class="avatar" ${size ? `style="width:${size}px;height:${size}px"` : ''}>${p && p.avatar ? `<img src="${esc(p.avatar)}" alt="" onerror="this.remove()">` : ''}${p && !p.avatar ? esc(initials(p.name)) : ''}</div>`;
}
const item = id => S.items.find(i => i.id === id);
const SHOP = () => S.items.filter(i => i.enabled !== false);
const deal = id => S.deals.find(d => d.id === id);
function isSingle(it) { return !!it.single; }
function soldOut(it) { return it.stock !== null && it.stock !== undefined && it.stock <= 0; }

// ── transport ────────────────────────────────────────────────────────────
async function post(name, data) {
  if (window.__NZC_MOCK__) return window.__NZC_MOCK__(name, data);
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}) });
    return await r.json();
  } catch (e) { return null; }
}
async function req(name, data) { return (await post('req', { name, data: data || {} })) || { error: 'ERR_GENERIC' }; }
function errText(res) {
  let msg = t(res.error);
  if (res.extra && res.extra.length) msg = t(res.error, ...res.extra);
  return msg;
}
// Request with busy flag + error toast. Returns data or null.
async function call(name, data, opts = {}) {
  if (S.busy) return null;
  S.busy = opts.busy || name;
  render();
  const res = await req(name, data);
  S.busy = null;
  if (res.error) { toast(errText(res), true); render(); return null; }
  if (opts.success) toast(opts.success);
  render();
  return res.data === undefined ? true : res.data;
}
function openUrl(url) {
  if (!url) return;
  if (window.invokeNative) window.invokeNative('openUrl', url);
  else window.open(url, '_blank');
}

// ── toasts ───────────────────────────────────────────────────────────────
function toast(text, bad) {
  const el = document.createElement('div');
  el.className = 'toast' + (bad ? ' bad' : '');
  el.innerHTML = `<i class="fas ${bad ? 'fa-circle-exclamation' : 'fa-circle-check'}"></i><span>${esc(text)}</span>`;
  $toasts.appendChild(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 220); }, 3600);
  while ($toasts.children.length > 4) $toasts.firstChild.remove();
}

// ── theme ────────────────────────────────────────────────────────────────
function hexToRgb(hex) {
  const m = /^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i.exec(hex || '');
  return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : null;
}
const mix = (c, f) => c.map(v => Math.max(0, Math.min(255, Math.round(v * f))));
const lighten = (c, a) => c.map(v => Math.round(v + (255 - v) * a));
function applyTheme(s) {
  const root = document.documentElement.style;
  const a = hexToRgb(s.accent);
  if (a) {
    root.setProperty('--teal', s.accent);
    root.setProperty('--teal-hi', `rgb(${mix(a, 1.21).join(',')})`);
    root.setProperty('--teal-lo', `rgb(${mix(a, .72).join(',')})`);
    root.setProperty('--teal-wash', `rgba(${a.join(',')},.11)`);
    root.setProperty('--teal-edge', `rgba(${a.join(',')},.34)`);
  }
  const r = hexToRgb(s.danger);
  if (r) {
    root.setProperty('--red', s.danger);
    root.setProperty('--red-wash', `rgba(${r.join(',')},.11)`);
    root.setProperty('--red-edge', `rgba(${r.join(',')},.34)`);
  }
  const b = hexToRgb(s.background);
  if (b) {
    root.setProperty('--base', s.background);
    root.setProperty('--inset', `rgb(${lighten(b, .012).join(',')})`);
    root.setProperty('--panel', `rgb(${lighten(b, .025).join(',')})`);
    root.setProperty('--raise', `rgb(${lighten(b, .055).join(',')})`);
    root.setProperty('--raise-2', `rgb(${lighten(b, .085).join(',')})`);
  }
  if (hexToRgb(s.text)) root.setProperty('--ink', s.text);
  root.setProperty('--bg-op', String(Math.min(1, Math.max(0, Number(s.bgOpacity) || 0))));
  root.setProperty('--bg-blur', `${Math.max(0, Number(s.bgBlur) || 0)}px`);
  root.setProperty('--r-card', `${Math.max(0, Math.min(24, Number(s.cardRadius) || 10))}px`);
}

// ── render loop ──────────────────────────────────────────────────────────
const VIEWS = {};      // page renderers (views.js / admin.js)
const MODALS = {};     // modal renderers
const ACT = {};        // click actions

function render() {
  if (!S.open) { $app.classList.remove('on'); $app.innerHTML = ''; return; }
  // Remember scroll positions, patch the live DOM in place (no innerHTML swap, so nothing
  // re-mounts: open animations play once, focus and caret stay, images never reload)
  const scrolls = {};
  $app.querySelectorAll('[data-keep]').forEach(el => { scrolls[el.dataset.keep] = el.scrollTop; });
  const tpl = document.createElement('template');
  tpl.innerHTML = shell();
  morphChildren($app, tpl.content);
  $app.classList.add('on');
  $app.querySelectorAll('[data-keep]').forEach(el => { el.scrollTop = scrolls[el.dataset.keep] || 0; });
  tick();
}

// ── DOM morph ────────────────────────────────────────────────────────────
// Nodes are matched by position, or by key (id / data-keep) when they have one.
const keyOf = n => n.nodeType === 1 ? (n.id || n.getAttribute('data-keep') || '') : '';
const sameNode = (a, b) => a.nodeType === b.nodeType && (a.nodeType !== 1 || (a.tagName === b.tagName && a.namespaceURI === b.namespaceURI && keyOf(a) === keyOf(b)));

function morphChildren(from, to) {
  const want = Array.from(to.childNodes);
  for (let i = 0; i < want.length; i++) {
    const t = want[i];
    let f = from.childNodes[i];
    const tk = keyOf(t);
    if (tk) {
      let match = null;
      for (let j = i; j < from.childNodes.length; j++) { const c = from.childNodes[j]; if (c.nodeType === 1 && keyOf(c) === tk && c.tagName === t.tagName) { match = c; break; } }
      if (match) { if (match !== f) from.insertBefore(match, f || null); f = match; }
      else { from.insertBefore(t, f || null); continue; }
    } else if (f && keyOf(f)) {
      from.insertBefore(t, f); continue;      // keep the keyed live node for a later template node
    }
    if (!f) { from.appendChild(t); continue; }
    if (sameNode(f, t)) morphNode(f, t); else from.replaceChild(t, f);
  }
  while (from.childNodes.length > want.length) from.removeChild(from.lastChild);
}

function morphNode(f, t) {
  if (f.nodeType !== 1) { if (f.nodeValue !== t.nodeValue) f.nodeValue = t.nodeValue; return; }
  for (let i = f.attributes.length - 1; i >= 0; i--) { const n = f.attributes[i].name; if (!t.hasAttribute(n)) f.removeAttribute(n); }
  for (let i = 0; i < t.attributes.length; i++) { const { name, value } = t.attributes[i]; if (f.getAttribute(name) !== value) f.setAttribute(name, value); }
  const tag = f.tagName;
  if (tag === 'INPUT') {
    if (t.type === 'checkbox' || t.type === 'radio') { if (f.checked !== t.checked) f.checked = t.checked; }
    else syncValue(f, t.value);
    return;
  }
  if (tag === 'TEXTAREA') { syncValue(f, t.value); return; }
  morphChildren(f, t);
  if (tag === 'SELECT' && f.value !== t.value) f.value = t.value;
}

// Set an input's value without jumping the caret of the field being typed in
function syncValue(el, value) {
  if (el.value === value) return;
  const active = el === document.activeElement;
  let s = null, e = null;
  if (active) { try { s = el.selectionStart; e = el.selectionEnd; } catch (_) { } }
  el.value = value;
  if (active && s !== null) { try { el.setSelectionRange(Math.min(s, value.length), Math.min(e, value.length)); } catch (_) { } }
}

// Countdowns update text only (no re-render)
function tick() {
  const now = Date.now() / 1000;
  document.querySelectorAll('[data-until]').forEach(el => {
    const left = Number(el.dataset.until) - now;
    el.textContent = left > 0 ? clock(left) : t('UI_EXPIRED');
  });
}
setInterval(tick, 1000);

// ── events ───────────────────────────────────────────────────────────────
document.addEventListener('click', e => {
  const el = e.target.closest('[data-a]');
  if (!el || !$app.contains(el) && !el.closest('#app')) return;
  if (el.dataset.stop !== undefined) e.stopPropagation();
  const fn = ACT[el.dataset.a];
  if (fn) { e.preventDefault(); fn(el.dataset.v, el, e); }
});
// data-f="path" binds an input to state; data-r re-renders on input
document.addEventListener('input', e => {
  const el = e.target;
  if (!el.dataset || !el.dataset.f) return;
  setPath(el.dataset.f, el.type === 'checkbox' ? el.checked : el.value);
  if (el.dataset.live && ACT[el.dataset.live]) ACT[el.dataset.live](el.value, el);
  if (el.dataset.r !== undefined) render();
});
document.addEventListener('keydown', e => {
  if (!S.open) return;
  if (e.key === 'Escape') {
    if (S.modal) { closeModal(); render(); } else close();
  } else if (e.key === 'Enter' && e.target && e.target.dataset && e.target.dataset.enter) {
    const fn = ACT[e.target.dataset.enter];
    if (fn) fn(e.target.value, e.target);
  }
});
function setPath(path, value) {
  const parts = path.split('.');
  let o = S;
  for (let i = 0; i < parts.length - 1; i++) { o[parts[i]] = o[parts[i]] || {}; o = o[parts[i]]; }
  o[parts[parts.length - 1]] = value;
}
function getPath(path) { return path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), S); }

function openModal(type, data) { S.modal = Object.assign({ type }, data || {}); }
function closeModal() { S.modal = null; }

// ── lifecycle ────────────────────────────────────────────────────────────
function close() {
  S.open = false;
  S.modal = null;
  render();
  post('close');
}

async function boot() {
  S.loading = true;
  render();
  const res = await req('boot');
  if (res.error) { toast(errText(res), true); S.loading = false; render(); return; }
  const d = res.data;
  S.me = d.me; S.admin = d.admin; S.cfg = d.config; S.settings = d.settings || {};
  S.favs = new Set(d.favorites || []);
  setCatalog(d);
  applyTheme(S.settings);
  S.loading = false;
  render();
}

function setCatalog(d) {
  const now = Date.now() / 1000;
  S.items = d.items || [];
  S.cats = d.categories || [];
  S.deals = (d.deals || []).map(x => Object.assign(x, { until: x.remaining != null ? now + x.remaining : null }));
  S.items.forEach(i => { if (i.sale && i.saleEnds) i.saleUntil = i.saleEnds; });
  if (S.heroIdx >= S.deals.length) S.heroIdx = 0;
}

async function reloadCatalog() {
  const res = await req('catalog');
  if (res.data) { setCatalog(res.data); render(); }
}

function setCoins(c) {
  if (!S.me) return;
  S.me.coins = c;
  render();
  const w = document.querySelector('.wallet b');
  if (w && w.animate) w.animate([{ color: 'var(--teal-hi)' }, { color: '#fff' }], { duration: 600, easing: 'ease' });
}

// ── test drive HUD ───────────────────────────────────────────────────────
let tdTimer = null;
function testDriveHud(d) {
  clearInterval(tdTimer);
  if (!d || !d.active) { $td.classList.remove('on'); $td.innerHTML = ''; return; }
  const total = d.seconds;
  const end = Date.now() + total * 1000;
  $td.innerHTML = `<div class="td"><div class="tile"><i class="fas fa-car-side"></i></div>
    <div class="td-t"><b>${esc(t('TD_TITLE'))}</b><span>${esc(t('TD_HINT'))}</span></div>
    <div class="td-time" id="td-time">${clock(total).slice(3)}</div><div class="td-bar" id="td-bar" style="width:100%"></div></div>`;
  $td.classList.add('on');
  const upd = () => {
    const left = Math.max(0, (end - Date.now()) / 1000);
    const tm = document.getElementById('td-time'), bar = document.getElementById('td-bar');
    if (!tm) return;
    tm.textContent = clock(left).slice(3);
    tm.classList.toggle('low', left <= 10);
    bar.style.width = `${(left / total) * 100}%`;
    if (left <= 0) clearInterval(tdTimer);
  };
  upd();
  tdTimer = setInterval(upd, 250);
}

// ── NUI messages ─────────────────────────────────────────────────────────
window.addEventListener('message', e => {
  const m = e.data || {};
  const d = m.data;
  switch (m.action) {
    case 'open': S.open = true; S.modal = null; boot(); break;
    case 'close': S.open = false; S.modal = null; render(); break;
    case 'testdrive': testDriveHud(d); break;
    case 'push':
      if (!d) break;
      if (d.channel === 'coins') setCoins(d.data);
      else if (d.channel === 'catalog') reloadCatalog();
      break;
  }
});

(async () => {
  const r = await post('ready');
  if (r) {
    S.loc = r.locale || {};
    if (r.scale && r.scale !== 1) document.documentElement.style.zoom = r.scale;
  }
})();
