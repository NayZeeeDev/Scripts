'use strict';
/* ═══ state ═════════════════════════════════════════════════════════════ */
const S = {
  open: false, mode: null, page: 'dashboard', tab: {}, me: { isStaff: false, perms: [] }, boot: null,
  settings: { scale: 1, sounds: true, coordsPos: 'top-center', noclipPos: 'bottom-center', autoDuty: true, startPage: 'dashboard', hotkeys: true, qkeys: null },
  toggles: {}, cfg: { version: '1.0.0', locale: {} }, badges: { reports: 0, chats: 0 }, d: {}, teleports: [], keys: {}, binds: [], openedAt: 0,
};
const IS_FIVEM = typeof GetParentResourceName === 'function';
const RES = IS_FIVEM ? GetParentResourceName() : 'nayzeee-admin';
const $ = (q, el = document) => el.querySelector(q);
const $$ = (q, el = document) => [...el.querySelectorAll(q)];

/* ═══ bridge ════════════════════════════════════════════════════════════ */
async function post(ev, data = {}) {
  if (!IS_FIVEM) return window.MOCK ? window.MOCK(ev, data) : { ok: false };
  try {
    const r = await fetch(`https://${RES}/${ev}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    const t = await r.text();
    return t ? JSON.parse(t) : {};
  } catch (e) { return { ok: false, err: 'NUI error' }; }
}
async function rpc(name, data = {}) {
  const r = await post('rpc', { name, data });
  return r || { ok: false, err: 'No response' };
}
/** rpc that toasts errors and returns data or null */
async function call(name, data, okMsg) {
  const r = await rpc(name, data);
  if (!r.ok) { toast(r.err || 'Action failed', 'error'); return null; }
  if (okMsg) toast(okMsg, 'success');
  return r.data === undefined ? true : r.data;
}
async function loc(action, data) {
  const r = await post('local', { action, data });
  return r && r.ok ? (r.data === undefined ? true : r.data) : null;
}

/* ═══ helpers ═══════════════════════════════════════════════════════════ */
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const num = n => Number(n || 0).toLocaleString('en-US');
const money = n => '$' + num(Math.floor(n || 0));
const now = () => Math.floor(Date.now() / 1000);
function dur(s) {
  s = Math.max(0, Math.floor(s || 0));
  if (s < 60) return s + 's';
  const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
  if (d) return `${d}d ${h}h`;
  if (h) return `${h}h ${m}m`;
  return `${m}m`;
}
function ago(t) {
  if (!t) return 'never';
  const s = now() - t;
  if (s < 45) return 'just now';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  if (s < 86400) return Math.floor(s / 3600) + 'h ago';
  if (s < 604800) return Math.floor(s / 86400) + 'd ago';
  return date(t);
}
function date(t, time) {
  if (!t) return '-';
  const d = new Date(t * 1000);
  const s = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: d.getFullYear() !== new Date().getFullYear() ? 'numeric' : undefined });
  return time ? `${s}, ${d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}` : s;
}
const clock = t => new Date(t * 1000).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
const initials = n => String(n || '?').replace(/[^\p{L}\p{N} ]/gu, '').trim().split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase() || '?';
const can = p => S.me.isStaff && ((S.me.perms || []).includes('*') || (S.me.perms || []).includes(p));
const canAny = (...ps) => ps.some(can);
const debounce = (fn, ms = 250) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
const L = (k, d) => (S.cfg.locale && S.cfg.locale[k]) || d;

function btn(label, a, cls = '', o = {}) {
  const attrs = [`data-a="${a}"`];
  if (o.v !== undefined) attrs.push(`data-v="${esc(o.v)}"`);
  if (o.title) attrs.push(`title="${esc(o.title)}"`);
  if (o.disabled) attrs.push('disabled');
  return `<button class="btn ${cls}${label ? '' : ' ico'}" ${attrs.join(' ')}>${o.icon ? `<i class="${o.icon}"></i>` : ''}${label ? esc(label) : ''}</button>`;
}
const chip = (t, cls = '', icon) => `<span class="chip ${cls}">${icon ? `<i class="${icon}"></i>` : ''}${esc(t)}</span>`;
const av = (name, cls = '', online) => `<div class="av ${cls}">${esc(initials(name))}${online !== undefined ? `<i class="st ${online ? 'on' : ''}"></i>` : ''}</div>`;
const empty = (icon, title, text = '') => `<div class="empty"><i class="${icon}"></i><b>${esc(title)}</b>${text ? `<p>${esc(text)}</p>` : ''}</div>`;
const loading = () => `<div class="loading"><div class="spin"></div></div>`;
const sw = (on, a, v) => `<button class="sw ${on ? 'on' : ''}" data-a="${a}" ${v !== undefined ? `data-v="${esc(v)}"` : ''}></button>`;
const swv = on => `<span class="sw ${on ? 'on' : ''}"></span>`;
const ph = (title, sub, actions = '') => `<div class="ph"><div class="ph-t"><h1>${esc(title)}</h1>${sub ? `<p>${esc(sub)}</p>` : ''}</div><div class="ph-a">${actions}</div></div>`;
const seg = (list, cur, a) => `<div class="seg">${list.map(([k, l, extra]) => `<button class="${k === cur ? 'on' : ''}" data-a="${a}" data-v="${k}">${esc(l)}${extra || ''}</button>`).join('')}</div>`;
const tabs = (list, cur, a) => `<div class="tabs">${list.map(([k, l, icon]) => `<button class="${k === cur ? 'on' : ''}" data-a="${a}" data-v="${k}">${icon ? `<i class="${icon}"></i>` : ''}${esc(l)}</button>`).join('')}</div>`;
const flagDef = id => (S.boot && S.boot.flags || []).find(f => f.id === id) || { id, label: id, color: '#e5a50a' };
const flagChip = id => { const f = flagDef(id); return `<span class="chip" style="color:${esc(f.color)};border-color:${esc(f.color)}55;background:${esc(f.color)}18"><i class="fas fa-flag"></i>${esc(f.label)}</span>`; };
const hpBar = (hp, ar) => `<div class="hp"><div class="m h" title="Health"><i style="width:${Math.max(0, Math.min(100, (hp || 0) - 100))}%"></i></div><div class="m a" title="Armour"><i style="width:${Math.min(100, ar || 0)}%"></i></div></div>`;
const vehImg = m => (S.boot && S.boot.vehicleImages ? S.boot.vehicleImages.replace('%s', m) : '');
const itemImg = n => (S.boot && S.boot.itemImages ? S.boot.itemImages.replace('%s', n) : '');
const imgTag = (src, fallback) => src ? `<img src="${esc(src)}" onerror="this.outerHTML='<i class=\\'${fallback}\\'></i>'">` : `<i class="${fallback}"></i>`;
function copy(text) {
  if (IS_FIVEM) return loc('copy', { text });
  try { navigator.clipboard.writeText(text); } catch (e) { /* preview */ }
}

/* ═══ sounds ════════════════════════════════════════════════════════════ */
let actx;
function sound(kind) {
  if (!S.settings.sounds) return;
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const tones = { ping: [880, 1320], alert: [660, 880, 1100], soft: [520], error: [300, 220] }[kind] || [600];
    tones.forEach((f, i) => {
      const o = actx.createOscillator(), g = actx.createGain();
      o.type = 'sine'; o.frequency.value = f;
      const t = actx.currentTime + i * 0.09;
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.06, t + 0.015); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.16);
      o.connect(g); g.connect(actx.destination); o.start(t); o.stop(t + 0.18);
    });
  } catch (e) { /* no audio */ }
}

/* ═══ toasts ════════════════════════════════════════════════════════════ */
function toast(msg, type = 'info', title) {
  const box = $('#toasts');
  const icon = { success: 'fas fa-circle-check', error: 'fas fa-circle-exclamation', warning: 'fas fa-triangle-exclamation', info: 'fas fa-circle-info' }[type] || 'fas fa-circle-info';
  const el = document.createElement('div');
  el.className = 'toast ' + type;
  el.innerHTML = `<i class="${icon}"></i><div>${title ? `<b>${esc(title)}</b> ` : ''}<span>${esc(msg)}</span></div>`;
  box.appendChild(el);
  if (type === 'error') sound('error');
  setTimeout(() => { el.style.transition = 'opacity .25s'; el.style.opacity = 0; setTimeout(() => el.remove(), 260); }, 3600);
}

/* ═══ modals ════════════════════════════════════════════════════════════ */
let modalResolve = null;
/**
 * form({ title, sub, icon, tone, size, body, fields:[{name,label,type,value,options,placeholder,span,hint,presets}], ok, okClass, cancel })
 * resolves with the values object or null
 */
function form(o) {
  closeModal(null);
  const f = (o.fields || []).map(fieldHtml).join('');
  const html = `<div class="modal-back" data-a="modalBack"><div class="frame modal ${o.size || ''}"><div class="shell">
    <div class="modal-h"><div class="ic ${o.tone || ''}"><i class="${o.icon || 'fas fa-pen'}"></i></div><div><h3>${esc(o.title)}</h3>${o.sub ? `<p>${esc(o.sub)}</p>` : ''}</div></div>
    <div class="modal-b">${o.body || ''}${f ? `<div class="fgrid ${o.cols === 1 ? '' : ''}" style="${o.cols === 1 ? 'grid-template-columns:1fr' : ''}">${f}</div>` : ''}</div>
    <div class="modal-f">${o.cancel === false ? '' : `<button class="btn btn-ghost" data-a="modalCancel">${esc(o.cancel || 'Cancel')}</button>`}
      <button class="btn ${o.okClass || 'btn-teal'}" data-a="modalOk">${esc(o.ok || 'Confirm')}</button></div>
  </div></div></div>`;
  $('#modal').innerHTML = html;
  const first = $('#modal input:not([type=checkbox]),#modal textarea,#modal select');
  if (first) setTimeout(() => first.focus(), 30);
  return new Promise(res => { modalResolve = res; S.modalOpts = o; });
}
function fieldHtml(x) {
  const id = 'f_' + x.name;
  let inner;
  const v = x.value ?? '';
  if (x.type === 'select') inner = `<select class="sel" name="${x.name}" id="${id}">${(x.options || []).map(op => { const [val, lab] = Array.isArray(op) ? op : [op, op]; return `<option value="${esc(val)}" ${String(val) === String(v) ? 'selected' : ''}>${esc(lab)}</option>`; }).join('')}</select>`;
  else if (x.type === 'textarea') inner = `<textarea class="txt" name="${x.name}" id="${id}" placeholder="${esc(x.placeholder || '')}" maxlength="${x.max || 2000}">${esc(v)}</textarea>`;
  else if (x.type === 'check') return `<label class="chk ${x.span ? 'span' : ''}" style="${x.span ? 'grid-column:1/-1' : ''}"><input type="checkbox" name="${x.name}" ${v ? 'checked' : ''}><span class="box"></span>${esc(x.label)}</label>`;
  else if (x.type === 'html') return `<div class="${x.span ? 'span' : ''}" style="${x.span ? 'grid-column:1/-1' : ''}">${x.html}</div>`;
  else inner = `<input class="inp" name="${x.name}" id="${id}" type="${x.type || 'text'}" value="${esc(v)}" placeholder="${esc(x.placeholder || '')}" ${x.max ? `maxlength="${x.max}"` : ''} ${x.step ? `step="${x.step}"` : ''}>`;
  const presets = x.presets ? `<div class="presets">${x.presets.map(p => { const [val, lab] = Array.isArray(p) ? p : [p, p]; return `<span class="chip" data-a="preset" data-v="${esc(val)}" data-f="${x.name}">${esc(lab)}</span>`; }).join('')}</div>` : '';
  return `<div class="field ${x.span ? 'span' : ''}"><label for="${id}">${esc(x.label || '')}${x.hint ? `<small>${esc(x.hint)}</small>` : ''}</label>${inner}${presets}</div>`;
}
function modalValues() {
  const out = {};
  $$('#modal [name]').forEach(el => { out[el.name] = el.type === 'checkbox' ? el.checked : el.value; });
  return out;
}
function closeModal(val) {
  $('#modal').innerHTML = '';
  if (modalResolve) { const r = modalResolve; modalResolve = null; r(val); }
}
function confirmBox(title, sub, o = {}) {
  return form({ title, sub, icon: o.icon || 'fas fa-triangle-exclamation', tone: o.tone || 'red', ok: o.ok || 'Confirm', okClass: o.okClass || 'btn-solid-red', body: o.body || '' }).then(v => v !== null);
}
function infoBox(title, body, o = {}) {
  return form({ title, sub: o.sub, icon: o.icon || 'fas fa-circle-info', body, ok: 'Close', cancel: false, size: o.size });
}

/* ═══ actions / events ══════════════════════════════════════════════════ */
const A = {};   // click actions: data-a
const IN = {};  // input handlers: data-in
A.modalOk = () => {
  const o = S.modalOpts || {};
  const vals = modalValues();
  if (o.validate) { const err = o.validate(vals); if (err) return toast(err, 'error'); }
  closeModal(vals);
};
A.modalCancel = () => closeModal(null);
A.modalBack = (v, el, e) => { if (e.target === el) closeModal(null); };
A.preset = (v, el) => { const f = $(`#modal [name="${el.dataset.f}"]`); if (f) { f.value = v; f.focus(); } };

document.addEventListener('click', e => {
  const el = e.target.closest('[data-a]');
  if (!el) return;
  const fn = A[el.dataset.a];
  if (fn) { if (el.tagName !== 'INPUT') e.preventDefault(); fn(el.dataset.v, el, e); }
});
document.addEventListener('contextmenu', e => {
  const el = e.target.closest('[data-ctx]');
  if (el && A[el.dataset.ctx]) { e.preventDefault(); A[el.dataset.ctx](el.dataset.v, el, e); }
});
document.addEventListener('input', e => {
  const el = e.target.closest('[data-in]');
  if (el && IN[el.dataset.in]) IN[el.dataset.in](el.value, el, e);
});
document.addEventListener('change', e => {
  const el = e.target.closest('[data-ch]');
  if (el && A[el.dataset.ch]) A[el.dataset.ch](el.type === 'checkbox' ? el.checked : el.value, el, e);
});
/* ═══ keyboard ══════════════════════════════════════════════════════════ */
// GTA key labels ("F10", "PAGEUP", "K") and browser keys ("F10", "PageUp", "k") compared the same way
const keyNorm = k => String(k || '').toUpperCase().replace(/[\s_]/g, '').replace(/^ARROW/, '').replace(/^ESC$/, 'ESCAPE').replace(/^DEL$/, 'DELETE').replace(/^INS$/, 'INSERT').replace(/^PGUP$/, 'PAGEUP').replace(/^PGDN$/, 'PAGEDOWN');
const evKey = e => (e.code && /^Digit\d$/.test(e.code) ? e.code.slice(5) : e.code && /^Numpad\d$/.test(e.code) ? 'NUMPAD' + e.code.slice(6) : e.key === ' ' ? 'SPACE' : e.key);
const typing = e => { const t = e.target; return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable); };
const keyLabel = k => { const n = keyNorm(k); return ({ ESCAPE: 'Esc', PAGEUP: 'PgUp', PAGEDOWN: 'PgDn', DELETE: 'Del', INSERT: 'Ins', SPACE: 'Space', BACKSPACE: 'Bksp' })[n] || (n.length === 1 ? n : n.charAt(0) + n.slice(1).toLowerCase()); };
/** the key this menu was opened with (as the player bound it) closes it again */
function isOpenKey(e) {
  const k = S.mode === 'quick' ? S.keys.quick : S.mode === 'panel' ? S.keys.panel : null;
  return k && keyNorm(evKey(e)) === keyNorm(k);
}
const KEYHANDLERS = []; // page modules push (e) => true when they handled a key
document.addEventListener('keydown', e => {
  if (S.rebind) return rebindKey(e);
  if (e.key === 'Enter' && e.target.dataset && e.target.dataset.enter && A[e.target.dataset.enter]) { e.preventDefault(); A[e.target.dataset.enter](e.target.value, e.target, e); return; }
  if (e.key === 'Enter' && $('#modal').innerHTML && e.target.tagName !== 'TEXTAREA') { e.preventDefault(); A.modalOk(); return; }
  if (e.key === 'Escape') {
    if ($('#modal').innerHTML) return closeModal(null);
    if (S.palette) return closePalette();
    if (S.open) return A.close();
  }
  if (!S.open || S.mode === 'report') return;
  // same key that opened it closes it (ignore the press that opened it and key repeat)
  if (!e.repeat && Date.now() - S.openedAt > 350 && isOpenKey(e) && !(typing(e) && keyNorm(evKey(e)).length === 1)) { e.preventDefault(); return A.close(); }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k' && S.mode === 'panel') { e.preventDefault(); return openPalette(); }
  if (S.palette) return paletteKey(e);
  if ($('#modal').innerHTML || typing(e) || S.settings.hotkeys === false) return;
  if (e.key === '?') { e.preventDefault(); return A.keyHelp(); }
  for (const h of KEYHANDLERS) if (h(e)) { e.preventDefault(); return; }
});

/* ═══ pages registry ════════════════════════════════════════════════════ */
const PAGES = {};
const NAV = [
  ['Overview', ['dashboard', 'players', 'offline', 'map']],
  ['Moderation', ['reports', 'chats', 'moderation', 'logs']],
  ['World', ['vehicles', 'items', 'world']],
  ['Management', ['staff', 'server', 'settings']],
];
function page(key, def) { PAGES[key] = Object.assign({ key, perms: [] }, def); }
const pageAllowed = p => !p.perms.length || canAny(...p.perms);
const pd = key => (S.d[key] = S.d[key] || {});

/* ═══ shell ═════════════════════════════════════════════════════════════ */
function applyScale() { document.documentElement.style.setProperty('--scale', S.settings.scale || 1); }

function renderApp() {
  const app = $('#app');
  if (!S.open) { app.innerHTML = ''; return; }
  applyScale();
  if (S.mode === 'panel') app.innerHTML = panelHtml();
  else if (S.mode === 'quick') app.innerHTML = quickHtml();
  else if (S.mode === 'report') app.innerHTML = reportHtml();
  if (S.mode === 'panel') renderMain();
}

function panelHtml() {
  const p = PAGES[S.page];
  const g = S.me.group || {};
  const navs = NAV.map(([grp, keys]) => {
    const items = keys.map(k => PAGES[k]).filter(x => x && pageAllowed(x));
    if (!items.length) return '';
    return `<div class="grp">${esc(grp)}</div>` + items.map(x => {
      const b = x.badge ? x.badge() : '';
      return `<button class="nav ${S.page === x.key ? 'on' : ''}" data-a="nav" data-v="${x.key}"><i class="${x.icon}"></i>${esc(L(x.key, x.label))}${b}</button>`;
    }).join('');
  }).join('');
  return `<div class="stage"><div class="frame win"><div class="shell">
    <div class="bar">
      <div class="bar-brand"><div class="mark"></div><div class="bar-title"><b>Staff Panel</b><span>${esc(S.boot ? S.boot.server : 'Server tools')}</span></div></div>
      <div class="bar-mid"><div class="crumb" id="crumb"><i class="${p ? p.icon : ''}"></i><b>${esc(p ? L(p.key, p.label) : '')}</b></div></div>
      <button class="kbd-search" data-a="palette"><i class="fas fa-magnifying-glass"></i>Search players, pages, actions<span class="key">Ctrl K</span></button>
      <button class="duty ${S.me.duty ? 'on' : ''}" data-a="toggleDuty"><span class="dot"></span>${S.me.duty ? 'On duty' : 'Off duty'}</button>
      ${can('reports.view') ? `<button class="bell" data-a="nav" data-v="reports" title="Open reports"><i class="fas fa-bell"></i>${S.badges.reports ? `<b>${S.badges.reports > 99 ? '99+' : S.badges.reports}</b>` : ''}</button>` : ''}
      <span class="ver">v${esc(S.cfg.version)}</span>
      <button class="pill-close" data-a="close">Close</button>
    </div>
    <div class="body">
      <div class="side">
        <div class="who">${av(S.me.name, '', true)}<div class="who-txt"><b>${esc(S.me.name || 'Staff')}</b><span><i class="dotc" style="background:${esc(g.color || '#08afa2')}"></i>${esc(g.label || '')}</span></div></div>
        <div class="nav-scroll">${navs}</div>
        <div class="side-foot">${can('self.quickmenu') ? btn('Quick menu', 'openQuick', 'btn-ghost full sm', { icon: 'fas fa-bolt' }) : ''}</div>
      </div>
      <div class="main" id="main"></div>
    </div>
    <div class="statusbar"><span><span class="key">ESC</span>${S.keys.panel ? `<span class="key">${esc(keyLabel(S.keys.panel))}</span>` : ''}Close</span><span><span class="key">Ctrl K</span>Search</span><span><span class="key">Alt</span><span class="key">1-9</span>Pages</span><span class="click" data-a="keyHelp"><span class="key">?</span>All keys</span><span id="sbx"></span>
      <span class="sp"><i class="live"></i><b id="sb-online">${S.d.dashboard && S.d.dashboard.data ? S.d.dashboard.data.online : '-'}</b> online</span></div>
  </div></div></div>`;
}

async function renderMain() {
  const main = $('#main'); if (!main) return;
  const p = PAGES[S.page];
  if (!p || !pageAllowed(p)) { main.innerHTML = empty('fas fa-lock', 'No access', 'Your group cannot open this page.'); return; }
  main.innerHTML = p.render();
  if (p.mounted) p.mounted();
}
const rerender = () => { if (S.open && S.mode === 'panel') renderMain(); };

function refreshNav() {
  if (S.mode !== 'panel' || !S.open) return;
  $$('.nav').forEach(n => { const p = PAGES[n.dataset.v]; const t = n.querySelector('.tally'); if (t) t.remove(); if (p && p.badge) n.insertAdjacentHTML('beforeend', p.badge()); });
  const bell = $('.bell'); if (bell) { const b = bell.querySelector('b'); if (b) b.remove(); if (S.badges.reports) bell.insertAdjacentHTML('beforeend', `<b>${S.badges.reports}</b>`); }
}

async function go(key, extra) {
  const prev = PAGES[S.page];
  if (prev && prev.leave && key !== S.page) prev.leave();
  if (!PAGES[key]) key = 'dashboard';
  S.page = key;
  if (S.mode !== 'panel') return;
  $$('.nav').forEach(n => n.classList.toggle('on', n.dataset.v === key));
  const p = PAGES[key];
  const cr = $('#crumb'); if (cr) cr.innerHTML = `<i class="${p.icon}"></i><b>${esc(L(p.key, p.label))}</b>`;
  if (p.enter) p.enter(extra);
  renderMain();
}
A.nav = v => go(v);
A.close = () => { if (S.page && PAGES[S.page] && PAGES[S.page].leave) PAGES[S.page].leave(); closeModal(null); closePalette(); post('close'); hideUI(); };
A.openQuick = () => { if (!can('self.quickmenu')) return; if (PAGES[S.page] && PAGES[S.page].leave) PAGES[S.page].leave(); closePalette(); S.mode = 'quick'; S.openedAt = Date.now(); renderApp(); };
A.openPanel = v => {
  if (!can('self.panel')) return;
  S.mode = 'panel'; S.openedAt = Date.now();
  if (v && PAGES[v] && pageAllowed(PAGES[v])) S.page = v;
  if (!PAGES[S.page] || !pageAllowed(PAGES[S.page])) S.page = (Object.values(PAGES).find(pageAllowed) || PAGES.settings).key;
  renderApp(); if (PAGES[S.page].enter) PAGES[S.page].enter(); renderMain();
};
A.toggleDuty = async () => {
  const r = await call('staff:duty', { state: !S.me.duty });
  if (r !== null) { S.me.duty = !!r; $$('.duty').forEach(d => { d.classList.toggle('on', !!r); d.innerHTML = `<span class="dot"></span>${r ? 'On duty' : 'Off duty'}`; }); }
};

/* panel hotkeys: Alt+1..9 pages, Alt+Q quick menu, Alt+D duty */
KEYHANDLERS.push(e => {
  if (S.mode !== 'panel' || !e.altKey) return false;
  const k = keyNorm(evKey(e));
  if (/^[1-9]$/.test(k)) { const list = navPages(); const p = list[+k - 1]; if (p) go(p.key); return true; }
  if (k === 'Q') { A.openQuick(); return true; }
  if (k === 'D') { A.toggleDuty(); return true; }
  return false;
});
KEYHANDLERS.push(e => { if (S.mode === 'panel' && e.key === '/' && !e.altKey) { openPalette(); return true; } return false; });
function navPages() { return NAV.flatMap(([, keys]) => keys).map(k => PAGES[k]).filter(x => x && pageAllowed(x)); }

/** cheat sheet of every key in the menu that is open */
A.keyHelp = () => {
  const row = (keys, label) => `<div class="li" style="padding:8px 4px"><div class="tx"><b style="font-weight:400">${esc(label)}</b></div><div class="rt" style="display:flex;gap:4px">${keys.map(k => `<span class="key">${esc(k)}</span>`).join('')}</div></div>`;
  let body;
  if (S.mode === 'quick') {
    const list = quickKeyList().filter(x => x.key);
    body = `<div class="g2" style="gap:0 18px">${row(['Esc'].concat(S.keys.quick ? [keyLabel(S.keys.quick)] : []), 'Close')}${row(['?'], 'This list')}${list.map(x => row([keyLabel(x.key)], x.label)).join('')}</div>`;
  } else {
    const pages = navPages().slice(0, 9).map((p, i) => row(['Alt', String(i + 1)], L(p.key, p.label))).join('');
    body = `<div class="g2" style="gap:0 18px"><div>${row(['Esc'].concat(S.keys.panel ? [keyLabel(S.keys.panel)] : []), 'Close')}${row(['Ctrl', 'K'], 'Search')}${row(['/'], 'Search')}${row(['Alt', 'Q'], 'Quick menu')}${row(['Alt', 'D'], 'Toggle duty')}${row(['?'], 'This list')}${row(['\u2191', '\u2193', 'Enter'], 'Pick in search')}</div><div>${pages}</div></div>`;
  }
  infoBox('Keyboard shortcuts', body + `<p class="muted" style="margin-top:12px;font-size:10.5px">Quick menu keys can be changed in Settings. Game keys are in GTA Settings, Key Bindings, FiveM.</p>`, { icon: 'fas fa-keyboard', size: 'lg' });
};
function hideUI() { S.open = false; S.mode = null; $('#app').innerHTML = ''; }

/* ═══ command palette ═══════════════════════════════════════════════════ */
function openPalette() {
  if (S.mode !== 'panel') return;
  S.palette = { q: '', idx: 0, players: S.d.players && S.d.players.list || [] };
  $('#palette').innerHTML = `<div class="palette" data-a="palBack"><div class="frame"><div class="shell">
    <div class="pal-in"><i class="fas fa-magnifying-glass"></i><input id="palq" data-in="pal" placeholder="Search players, pages and actions" autocomplete="off"><span class="key">ESC</span></div>
    <div class="pal-list" id="pal-list"></div></div></div></div>`;
  paletteList();
  setTimeout(() => $('#palq').focus(), 20);
  if (!S.palette.players.length) rpc('players:list').then(r => { if (r.ok && S.palette) { S.palette.players = r.data; paletteList(); } });
}
function closePalette() { S.palette = null; $('#palette').innerHTML = ''; }
A.palBack = (v, el, e) => { if (e.target === el) closePalette(); };
A.palette = openPalette;
IN.pal = v => { S.palette.q = v.toLowerCase(); S.palette.idx = 0; paletteList(); };
function paletteItems() {
  const q = S.palette.q;
  const items = [];
  Object.values(PAGES).filter(pageAllowed).forEach(p => items.push({ icon: p.icon, t: L(p.key, p.label), s: 'Page', run: () => go(p.key) }));
  S.palette.players.forEach(p => items.push({ icon: 'fas fa-user', t: `${p.name}`, s: `ID ${p.id}${p.char ? ' · ' + p.char : ''}`, k: 'Player', run: () => { go('players'); openProfile(p.id); } }));
  const tg = [['noclip', 'Noclip'], ['god', 'God mode'], ['invis', 'Invisibility'], ['names', 'Player names'], ['ids', 'Player IDs'], ['coords', 'Show coords']];
  tg.forEach(([k, l]) => items.push({ icon: 'fas fa-toggle-on', t: `Toggle ${l}`, k: 'Self', run: () => toggleSelf(k) }));
  items.push({ icon: 'fas fa-location-dot', t: 'Teleport to waypoint', k: 'Self', run: () => loc('tpWaypoint') });
  items.push({ icon: 'fas fa-crosshairs', t: 'Entity inspector', k: 'Tool', run: () => loc('inspector') });
  items.push({ icon: 'fas fa-bullhorn', t: 'New announcement', k: 'World', run: () => { go('world'); S.tab.world = 'announce'; rerender(); } });
  if (!q) return items.slice(0, 40);
  return items.filter(i => (i.t + ' ' + (i.s || '')).toLowerCase().includes(q)).slice(0, 40);
}
function paletteList() {
  const list = paletteItems();
  S.palette.list = list;
  const box = $('#pal-list'); if (!box) return;
  box.innerHTML = list.length ? list.map((i, n) => `<div class="pal-it ${n === S.palette.idx ? 'on' : ''}" data-a="palRun" data-v="${n}"><i class="${i.icon}"></i><div class="tx"><b>${esc(i.t)}</b>${i.s ? `<span>${esc(i.s)}</span>` : ''}</div><span class="k">${esc(i.k || '')}</span></div>`).join('') : empty('fas fa-magnifying-glass', 'Nothing found');
}
function paletteKey(e) {
  if (!S.palette || !S.palette.list) return;
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    S.palette.idx = (S.palette.idx + (e.key === 'ArrowDown' ? 1 : -1) + S.palette.list.length) % Math.max(1, S.palette.list.length);
    paletteList();
    const on = $('.pal-it.on'); if (on) on.scrollIntoView({ block: 'nearest' });
  } else if (e.key === 'Enter') { e.preventDefault(); A.palRun(S.palette.idx); }
}
A.palRun = v => { const it = S.palette && S.palette.list[+v]; closePalette(); if (it) it.run(); };

/* ═══ tiny chart helpers (svg) ══════════════════════════════════════════ */
function lineChart(series, labels, o = {}) {
  const W = o.w || 640, H = o.h || 190, P = { l: 30, r: 10, t: 12, b: 22 };
  const all = series.flatMap(s => s.values);
  const max = Math.max(o.min || 4, ...all) * 1.15;
  const n = Math.max(2, labels.length);
  const x = i => P.l + (W - P.l - P.r) * (i / (n - 1));
  const y = v => H - P.b - (H - P.t - P.b) * (v / max);
  let g = '<g class="grid">';
  for (let i = 0; i <= 4; i++) { const yy = P.t + (H - P.t - P.b) * i / 4; g += `<line x1="${P.l}" x2="${W - P.r}" y1="${yy}" y2="${yy}"/><text x="${P.l - 6}" y="${yy + 3}" text-anchor="end">${Math.round(max - max * i / 4)}</text>`; }
  g += '</g>';
  const step = Math.ceil(labels.length / 8);
  const lx = labels.map((l, i) => i % step === 0 ? `<text x="${x(i)}" y="${H - 6}" text-anchor="middle">${esc(l)}</text>` : '').join('');
  const paths = series.map((s, si) => {
    if (!s.values.length) return '';
    const pts = s.values.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`);
    const area = `M${x(0)},${H - P.b} L${pts.join(' L')} L${x(s.values.length - 1)},${H - P.b} Z`;
    return `<defs><linearGradient id="lg${si}${o.id || ''}" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="${s.color}" stop-opacity=".28"/><stop offset="1" stop-color="${s.color}" stop-opacity="0"/></linearGradient></defs>
      ${s.fill !== false ? `<path d="${area}" fill="url(#lg${si}${o.id || ''})"/>` : ''}<path d="M${pts.join(' L')}" fill="none" stroke="${s.color}" stroke-width="1.8" stroke-linejoin="round" ${s.dash ? 'stroke-dasharray="4 3"' : ''}/>`;
  }).join('');
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" style="height:${H}px">${g}${lx}${paths}</svg>`;
}
function barChart(values, labels, o = {}) {
  const W = o.w || 640, H = o.h || 170, P = { l: 30, r: 8, t: 10, b: 22 };
  const max = Math.max(o.min || 1, ...values) * 1.12;
  const bw = (W - P.l - P.r) / Math.max(1, values.length);
  let g = '<g class="grid">';
  for (let i = 0; i <= 3; i++) { const yy = P.t + (H - P.t - P.b) * i / 3; g += `<line x1="${P.l}" x2="${W - P.r}" y1="${yy}" y2="${yy}"/><text x="${P.l - 6}" y="${yy + 3}" text-anchor="end">${o.fmt ? o.fmt(max - max * i / 3) : Math.round(max - max * i / 3)}</text>`; }
  g += '</g>';
  const bars = values.map((v, i) => {
    const h = (H - P.t - P.b) * (v / max);
    return `<rect x="${P.l + i * bw + bw * 0.2}" y="${H - P.b - h}" width="${bw * 0.6}" height="${Math.max(0, h)}" rx="3" fill="url(#bg${o.id || ''})"><title>${esc(labels[i])}: ${o.fmt ? o.fmt(v) : v}</title></rect><text x="${P.l + i * bw + bw / 2}" y="${H - 6}" text-anchor="middle">${esc(labels[i])}</text>`;
  }).join('');
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" style="height:${H}px"><defs><linearGradient id="bg${o.id || ''}" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#0fd4c4"/><stop offset="1" stop-color="#067d74"/></linearGradient></defs>${g}${bars}</svg>`;
}
