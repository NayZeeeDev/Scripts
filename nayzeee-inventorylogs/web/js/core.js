'use strict';
/* ═══ state ═════════════════════════════════════════════════════════════ */
const S = { open: false, page: 'dashboard', boot: null, d: {}, items: null, itemMap: {}, img: {} };
const IS_FIVEM = typeof GetParentResourceName === 'function';
const RES = IS_FIVEM ? GetParentResourceName() : 'nayzeee-inventorylogs';
const $ = (q, el = document) => el.querySelector(q);
const $$ = (q, el = document) => [...el.querySelectorAll(q)];

/* ═══ bridge ════════════════════════════════════════════════════════════ */
async function post(ev, data = {}) {
  if (!IS_FIVEM) return window.MOCK ? window.MOCK(ev, data) : { ok: false, err: 'Preview' };
  try {
    const r = await fetch(`https://${RES}/${ev}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
    const t = await r.text();
    return t ? JSON.parse(t) : {};
  } catch (e) { return { ok: false, err: 'The game did not answer.' }; }
}
async function rpc(name, data = {}) { return (await post('rpc', { name, data })) || { ok: false, err: 'No response' }; }
/** rpc that toasts errors; returns data, or null on failure */
async function call(name, data, okMsg) {
  const r = await rpc(name, data);
  if (!r.ok) { toast(r.err || 'That did not work.', 'error'); return null; }
  if (okMsg) toast(okMsg, 'success');
  return r.data === undefined ? true : r.data;
}

/* ═══ helpers ═══════════════════════════════════════════════════════════ */
const esc = s => String(s ?? '').replace(/[&<>"'`]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' }[c]));
const num = n => Number(n || 0).toLocaleString('en-US');
const now = () => Math.floor(Date.now() / 1000);
const clone = v => v === undefined ? undefined : JSON.parse(JSON.stringify(v));
const debounce = (fn, ms = 250) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
const can = t => !!(S.boot && S.boot.me.perms[t]);
function ago(t) {
  if (!t) return 'never';
  const s = now() - t;
  if (s < 45) return 'just now';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  if (s < 86400) return Math.floor(s / 3600) + 'h ago';
  if (s < 604800) return Math.floor(s / 86400) + 'd ago';
  return date(t);
}
function date(t, time = true) {
  if (!t) return '-';
  const d = new Date(t * 1000);
  const s = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: d.getFullYear() !== new Date().getFullYear() ? 'numeric' : undefined });
  return time ? `${s}, ${d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}` : s;
}
const clock = t => new Date(t * 1000).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', second: '2-digit' });
const initials = n => String(n || '?').replace(/[^\p{L}\p{N} ]/gu, '').trim().split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase() || '?';
function hexA(hex, a) {
  const h = String(hex || '#08afa2').replace('#', '');
  const n = parseInt(h.length === 3 ? h.split('').map(x => x + x).join('') : h, 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}
function typeLabel(t) { const x = (S.boot && S.boot.types || []).find(y => y.id === t); return x ? x.label : String(t || '').replace(/_/g, ' '); }
function badge(t) { const c = (S.boot && S.boot.colors || {})[t] || '#9ea5aa'; return `<span class="badge" style="--c:${c};--cw:${hexA(c, .12)};--ce:${hexA(c, .34)}">${esc(typeLabel(t))}</span>`; }
function copy(text) { post('copy', { text }); toast('Copied', 'success'); }

function btn(label, a, cls = '', o = {}) {
  const attrs = [`data-a="${a}"`];
  if (o.v !== undefined) attrs.push(`data-v="${esc(o.v)}"`);
  if (o.title) attrs.push(`title="${esc(o.title)}"`);
  if (o.disabled) attrs.push('disabled');
  return `<button class="btn ${cls}${label ? '' : ' ico'}" ${attrs.join(' ')}>${o.icon ? `<i class="${o.icon}"></i>` : ''}${label ? esc(label) : ''}</button>`;
}
const chip = (t, cls = '', icon) => `<span class="chip ${cls}">${icon ? `<i class="${icon}"></i>` : ''}${esc(t)}</span>`;
function av(name, cls = '', online, img) {
  return `<div class="av ${cls}">${img ? `<img src="${esc(img)}" onerror="this.remove()">` : esc(initials(name))}${online !== undefined ? `<i class="st ${online ? 'on' : ''}"></i>` : ''}</div>`;
}
const empty = (icon, title, text = '') => `<div class="empty"><i class="${icon}"></i><b>${esc(title)}</b>${text ? `<p>${esc(text)}</p>` : ''}</div>`;
const loading = () => `<div class="loading"><div class="spin"></div></div>`;
const ph = (title, sub, actions = '') => `<div class="ph"><div class="ph-t"><h1>${esc(title)}</h1>${sub ? `<p>${esc(sub)}</p>` : ''}</div><div class="ph-a">${actions}</div></div>`;
const seg = (list, cur, a) => `<div class="seg">${list.map(([k, l, extra]) => `<button class="${String(k) === String(cur) ? 'on' : ''}" data-a="${a}" data-v="${esc(k)}">${esc(l)}${extra || ''}</button>`).join('')}</div>`;
const tabs = (list, cur, a) => `<div class="tabs">${list.map(([k, l, icon]) => `<button class="${k === cur ? 'on' : ''}" data-a="${a}" data-v="${k}">${icon ? `<i class="${icon}"></i>` : ''}${esc(l)}</button>`).join('')}</div>`;
const note = (html, cls = '', icon = 'fas fa-circle-info') => `<div class="note ${cls}"><i class="${icon}"></i><div>${html}</div></div>`;

/* ═══ item images ═══════════════════════════════════════════════════════ */
function imgUrl(name, image) {
  if (S.img[name]) return S.img[name];
  const base = (S.boot && S.boot.imagepath) || 'nui://ox_inventory/web/images';
  if (!image && S.itemMap[name] && S.itemMap[name].image) image = S.itemMap[name].image;
  if (image) return /^[a-z]+:\/\//i.test(image) || image.startsWith('data:') ? image : `${base}/${image}`;
  return `${base}/${name}.png`;
}
function thumb(name, image, cls = '') {
  return `<div class="thumb ${cls}"><img src="${esc(imgUrl(name, image))}" onerror="this.outerHTML='<i class=&quot;fas fa-box&quot;></i>'"></div>`;
}
async function loadItems(force) {
  if (S.items && !force) return S.items;
  const r = await rpc('items:list');
  S.items = r.ok ? r.data : [];
  S.itemMap = {};
  S.items.forEach(i => S.itemMap[i.name] = i);
  let dl = $('#dl-items');
  if (!dl) { dl = document.createElement('datalist'); dl.id = 'dl-items'; document.body.appendChild(dl); }
  dl.innerHTML = S.items.map(i => `<option value="${esc(i.name)}">${esc(i.label)}</option>`).join('');
  return S.items;
}
const itemLabel = n => (S.itemMap[n] && S.itemMap[n].label) || n;

/* ═══ sounds ════════════════════════════════════════════════════════════ */
let actx;
function sound(kind) {
  if (!S.ui || S.ui.sounds === false) return;
  if (S.boot && S.boot.prefs && S.boot.prefs.sounds === false) return;
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const tones = { ok: [660, 990], error: [300, 220], tick: [520] }[kind] || [600];
    tones.forEach((f, i) => {
      const o = actx.createOscillator(), g = actx.createGain();
      o.type = 'sine'; o.frequency.value = f;
      const t = actx.currentTime + i * 0.08;
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.045, t + 0.015); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
      o.connect(g); g.connect(actx.destination); o.start(t); o.stop(t + 0.17);
    });
  } catch (e) { /* no audio */ }
}

/* ═══ toasts ════════════════════════════════════════════════════════════ */
function toast(msg, type = 'info', ms) {
  const box = $('#toasts');
  const icon = { success: 'fas fa-circle-check', error: 'fas fa-circle-exclamation', warning: 'fas fa-triangle-exclamation', info: 'fas fa-circle-info' }[type] || 'fas fa-circle-info';
  const el = document.createElement('div');
  el.className = 'toast ' + type;
  el.innerHTML = `<i class="${icon}"></i><span>${esc(msg)}</span>`;
  box.appendChild(el);
  if (type === 'error') sound('error'); else if (type === 'success') sound('ok');
  setTimeout(() => { el.style.transition = 'opacity .25s'; el.style.opacity = 0; setTimeout(() => el.remove(), 260); }, ms || (type === 'error' ? 5200 : 3600));
}

/* ═══ modals ════════════════════════════════════════════════════════════ */
let modalResolve = null;
function form(o) {
  closeModal(null);
  const f = (o.fields || []).map(fieldHtml).join('');
  $('#modal').innerHTML = `<div class="modal-back" data-a="modalBack"><div class="frame modal ${o.size || ''}"><div class="shell">
    <div class="modal-h"><div class="ic ${o.tone || ''}"><i class="${o.icon || 'fas fa-pen'}"></i></div><div><h3>${esc(o.title)}</h3>${o.sub ? `<p>${esc(o.sub)}</p>` : ''}</div></div>
    <div class="modal-b">${o.body || ''}${f ? `<div class="fgrid" style="${o.cols === 1 ? 'grid-template-columns:1fr' : ''}">${f}</div>` : ''}</div>
    <div class="modal-f">${o.cancel === false ? '' : `<button class="btn btn-ghost" data-a="modalCancel">${esc(o.cancel || 'Cancel')}</button>`}
      ${o.ok === false ? '' : `<button class="btn ${o.okClass || 'btn-teal'}" data-a="modalOk">${esc(o.ok || 'Confirm')}</button>`}</div>
  </div></div></div>`;
  const first = $('#modal input:not([type=checkbox]),#modal textarea,#modal select');
  if (first && o.focus !== false) setTimeout(() => first.focus(), 30);
  if (o.mounted) o.mounted();
  return new Promise(res => { modalResolve = res; S.modalOpts = o; });
}
function fieldHtml(x) {
  const id = 'f_' + x.name;
  const v = x.value ?? '';
  let inner;
  if (x.type === 'select') inner = `<select class="sel" name="${x.name}" id="${id}">${(x.options || []).map(op => { const [val, lab] = Array.isArray(op) ? op : [op, op]; return `<option value="${esc(val)}" ${String(val) === String(v) ? 'selected' : ''}>${esc(lab)}</option>`; }).join('')}</select>`;
  else if (x.type === 'textarea') inner = `<textarea class="txt ${x.mono ? 'mono' : ''}" name="${x.name}" id="${id}" placeholder="${esc(x.placeholder || '')}" rows="${x.rows || 3}">${esc(v)}</textarea>`;
  else if (x.type === 'check') return `<label class="chk ${x.span ? 'span' : ''}" style="${x.span ? 'grid-column:1/-1' : ''}"><input type="checkbox" name="${x.name}" ${v ? 'checked' : ''}><span class="box"></span>${esc(x.label)}</label>`;
  else if (x.type === 'html') return `<div style="grid-column:1/-1">${x.html}</div>`;
  else inner = `<input class="inp" name="${x.name}" id="${id}" type="${x.type || 'text'}" value="${esc(v)}" placeholder="${esc(x.placeholder || '')}" ${x.list ? `list="${x.list}"` : ''} ${x.min !== undefined ? `min="${x.min}"` : ''} autocomplete="off">`;
  const presets = x.presets ? `<div class="presets">${x.presets.map(p => { const [val, lab] = Array.isArray(p) ? p : [p, p]; return `<span class="chip" data-a="preset" data-v="${esc(val)}" data-f="${x.name}">${esc(lab)}</span>`; }).join('')}</div>` : '';
  return `<div class="field ${x.span ? 'span' : ''}"><label for="${id}">${esc(x.label || '')}${x.hint ? `<small>${esc(x.hint)}</small>` : ''}</label>${inner}${presets}${x.help ? `<div class="hint">${esc(x.help)}</div>` : ''}</div>`;
}
function modalValues() { const out = {}; $$('#modal [name]').forEach(el => { out[el.name] = el.type === 'checkbox' ? el.checked : el.value; }); return out; }
function closeModal(val) { $('#modal').innerHTML = ''; if (modalResolve) { const r = modalResolve; modalResolve = null; r(val); } }
function confirmBox(title, sub, o = {}) {
  return form({ title, sub, icon: o.icon || 'fas fa-triangle-exclamation', tone: o.tone ?? 'red', ok: o.ok || 'Confirm', okClass: o.okClass || 'btn-solid-red', body: o.body || '', fields: o.fields }).then(v => v === null ? null : (o.fields ? v : true));
}
function infoBox(title, body, o = {}) { return form({ title, sub: o.sub, icon: o.icon || 'fas fa-circle-info', body, ok: o.ok || 'Close', cancel: false, size: o.size, focus: false }); }

/* ═══ events ════════════════════════════════════════════════════════════ */
const A = {};   // click: data-a
const IN = {};  // input: data-in
const CH = {};  // change: data-ch
A.modalOk = async () => {
  const o = S.modalOpts || {}; const vals = modalValues();
  if (o.validate) { const err = o.validate(vals); if (err) return toast(err, 'error'); }
  // onOk: async work done while the pop-up stays open; it closes only when that returns true
  if (o.onOk) {
    const b = $('#modal [data-a="modalOk"]');
    if (!b || b.disabled) return;
    b.disabled = true;
    let done = false;
    try { done = await o.onOk(vals); } finally { if (b.isConnected) b.disabled = false; }
    if (!done || S.modalOpts !== o) return;
  }
  closeModal(vals);
};
A.modalCancel = () => closeModal(null);
A.modalBack = (v, el, e) => { if (e.target === el) closeModal(null); };
A.preset = (v, el) => { const f = $(`#modal [name="${el.dataset.f}"]`); if (f) { f.value = v; f.dispatchEvent(new Event('input', { bubbles: true })); } };

document.addEventListener('click', e => {
  const el = e.target.closest('[data-a]');
  if (!el || el.disabled) return;
  const fn = A[el.dataset.a];
  // never cancel a click on a form control inside a clickable area (checkboxes in pop-ups)
  if (fn) { if (el.tagName !== 'INPUT' && el.tagName !== 'LABEL' && !e.target.closest('label, input, select, textarea')) e.preventDefault(); fn(el.dataset.v, el, e); }
});
document.addEventListener('input', e => { const el = e.target.closest('[data-in]'); if (el && IN[el.dataset.in]) IN[el.dataset.in](el.value, el, e); });
document.addEventListener('change', e => { const el = e.target.closest('[data-ch]'); if (el && CH[el.dataset.ch]) CH[el.dataset.ch](el.type === 'checkbox' ? el.checked : el.value, el, e); });
document.addEventListener('keydown', e => {
  if (e.key === 'Enter' && e.target.dataset && e.target.dataset.enter && A[e.target.dataset.enter]) { e.preventDefault(); A[e.target.dataset.enter](e.target.value, e.target, e); return; }
  if (e.key === 'Enter' && $('#modal').innerHTML && e.target.tagName !== 'TEXTAREA') { e.preventDefault(); A.modalOk(); return; }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's' && S.open) { e.preventDefault(); if (A.hotSave) A.hotSave(); return; }
  if (e.key === 'Escape') {
    if ($('#modal').innerHTML) return closeModal(null);
    if (S.open) return A.close();
  }
});

/* ═══ pages ═════════════════════════════════════════════════════════════ */
const PAGES = {};
const NAV = [
  ['Overview', ['dashboard', 'logs', 'economy', 'audit']],
  ['Players', ['players', 'finder', 'global', 'rollback']],
  ['Security', ['antidupe', 'staff']],
  ['@inventory', ['storage', 'ed_items', 'ed_weapons', 'ed_shops', 'ed_stashes', 'ed_crafting', 'ed_other', 'ed_files']],
  ['You', ['settings']],
];
function page(key, def) { PAGES[key] = Object.assign({ key, tier: 'view' }, def); }
const pageAllowed = p => p && can(p.tier) && (!p.when || p.when());
/** Editor pages come from the inventory integration: which exist, their names and their files */
const invPage = key => ((S.boot && S.boot.inventory && S.boot.inventory.pages) || []).find(p => p.key === key);
function applyInventoryPages() {
  ((S.boot.inventory && S.boot.inventory.pages) || []).forEach(p => { const P = PAGES[p.key]; if (P) { P.label = p.label; P.icon = p.icon || P.icon; } });
}
const pd = key => (S.d[key] = S.d[key] || {});

function applyTheme(ui) {
  S.ui = ui || {};
  const r = document.documentElement.style;
  r.setProperty('--scale', Math.min(1.3, Math.max(0.7, Number(S.ui.scale) || 1)));
  if (S.ui.accent) { r.setProperty('--teal', S.ui.accent); r.setProperty('--teal-wash', hexA(S.ui.accent, .11)); r.setProperty('--teal-edge', hexA(S.ui.accent, .34)); }
  if (S.ui.danger) { r.setProperty('--red', S.ui.danger); r.setProperty('--red-wash', hexA(S.ui.danger, .11)); r.setProperty('--red-edge', hexA(S.ui.danger, .34)); }
}

function panelHtml() {
  const p = PAGES[S.page];
  const b = S.boot;
  const navs = NAV.map(([grp, keys]) => {
    const items = keys.map(k => PAGES[k]).filter(pageAllowed);
    if (!items.length) return '';
    const title = grp === '@inventory' ? ((b.inventory && b.inventory.label) || 'Inventory') : grp;
    return `<div class="grp">${esc(title)}</div>` + items.map(x => `<button class="nav ${S.page === x.key ? 'on' : ''}" data-a="nav" data-v="${x.key}"><i class="${x.icon}"></i>${esc(x.label)}${x.badge ? x.badge() : ''}</button>`).join('');
  }).join('');
  const inv = b.inventory || {};
  const bridge = b.bridge ? `<span class="livechip on" title="Edits apply without a restart"><span class="dot"></span>Live editing</span>` : (b.editor && can('editor') && inv.pages && inv.pages.length ? `<span class="livechip warn" title="Install the bridge from INSTALL.md"><span class="dot"></span>Bridge missing</span>` : '');
  return `<div class="stage"><div class="frame win"><div class="shell">
    <div class="bar">
      <div class="bar-brand"><div class="mark"></div><div class="bar-title"><b>Inventory Manager</b><span>${esc(b.server)}</span></div></div>
      <div class="bar-mid"><div class="crumb" id="crumb"><i class="${p ? p.icon : ''}"></i><b>${esc(p ? p.label : '')}</b></div></div>
      ${bridge}
      ${bellHtml()}
      <span class="ver">v${esc(b.version)}</span>
      <button class="pill-close" data-a="close">Close</button>
    </div>
    <div class="body">
      <div class="side">
        <div class="who">${av(b.me.name, '', true)}<div class="who-txt"><b>${esc(b.me.name)}</b><span>${esc(Object.keys(b.me.perms).filter(k => b.me.perms[k] && k !== 'view').join(', ') || 'view only')}</span></div></div>
        <div class="nav-scroll" data-scroll="nav">${navs}</div>
      </div>
      <div class="main" id="main"></div>
    </div>
    <div class="statusbar"><span><span class="key">ESC</span>Close</span><span><span class="key">Ctrl S</span>Save in editors</span><span id="sbx"></span>
      <span class="sp">${esc(inv.label || 'inventory')} <b>${esc(inv.version || (inv.running ? 'running' : 'not running'))}</b> · ${esc(b.framework)}</span></div>
  </div></div></div>`;
}

/* Lists and editors are rebuilt on every change, so anything marked data-scroll="key" remembers how far
   it was scrolled and goes back there after a re-render (picking an item no longer jumps to the top). */
const SCROLL = {};
document.addEventListener('scroll', e => { const t = e.target; if (t && t.dataset && t.dataset.scroll) SCROLL[t.dataset.scroll] = t.scrollTop; }, true);
function keepScroll(root) {
  $$('[data-scroll]', root).forEach(el => { const y = SCROLL[el.dataset.scroll]; if (y) el.scrollTop = y; });
}
function renderApp() {
  const app = $('#app');
  if (!S.open || !S.boot) { app.innerHTML = ''; return; }
  app.innerHTML = panelHtml();
  keepScroll(app);
  renderMain();
}
function renderMain() {
  const main = $('#main'); if (!main) return;
  const p = PAGES[S.page];
  if (!pageAllowed(p)) { main.innerHTML = empty('fas fa-lock', 'No access', 'Your group cannot open this page.'); return; }
  main.innerHTML = p.render();
  // plain pages remember their scroll too (refreshing the dashboard no longer jumps up)
  $$('.content:not(.flush):not([data-scroll])', main).forEach(el => { el.dataset.scroll = 'page:' + S.page; });
  keepScroll(main);
  if (p.mounted) p.mounted();
}
const rerender = () => { if (S.open) renderMain(); };
function refreshNav() { $$('.nav').forEach(n => { const p = PAGES[n.dataset.v]; const t = n.querySelector('.tally'); if (t) t.remove(); if (p && p.badge) n.insertAdjacentHTML('beforeend', p.badge()); }); }

async function go(key, extra) {
  const prev = PAGES[S.page];
  if (prev && prev.canLeave && key !== S.page && !(await prev.canLeave())) return;
  if (prev && prev.leave && key !== S.page) prev.leave();
  if (!pageAllowed(PAGES[key])) key = 'dashboard';
  S.page = key;
  $$('.nav').forEach(n => n.classList.toggle('on', n.dataset.v === key));
  const p = PAGES[key];
  const cr = $('#crumb'); if (cr) cr.innerHTML = `<i class="${p.icon}"></i><b>${esc(p.label)}</b>`;
  renderMain();
  if (p.enter) await p.enter(extra);
}
A.nav = v => go(v);
A.close = async () => {
  const p = PAGES[S.page];
  if (p && p.canLeave && !(await p.canLeave())) return;
  if (p && p.leave) p.leave();
  closeModal(null);
  S.open = false;
  $('#app').innerHTML = '';
  post('close');
};

window.addEventListener('message', async e => {
  const m = e.data || {};
  if (m.action === 'open') {
    applyTheme(m.ui);
    const r = await rpc('boot');
    if (!r.ok) { toast(r.err || 'Could not open the panel.', 'error'); post('close'); return; }
    S.boot = r.data;
    applyInventoryPages();
    S.open = true;
    if (!pageAllowed(PAGES[S.page])) S.page = 'dashboard';
    renderApp();
    const p = PAGES[S.page];
    if (p && p.enter) p.enter();
    loadItems(true);
  } else if (m.action === 'close') { S.open = false; $('#app').innerHTML = ''; }
});

/* ═══ reusable bits ═════════════════════════════════════════════════════ */
function pager(st, a) {
  if (!st || !st.pages || st.pages <= 1) return st && st.total !== undefined ? `<div class="pager"><span>${num(st.total)} rows</span></div>` : '';
  return `<div class="pager"><span>${num(st.total)} rows · page ${st.page} of ${st.pages}</span><div class="row-btns">
    ${btn('', a, 'sm btn-ghost', { v: 1, icon: 'fas fa-angles-left', disabled: st.page <= 1 })}${btn('Previous', a, 'sm', { v: st.page - 1, icon: 'fas fa-chevron-left', disabled: st.page <= 1 })}
    ${btn('Next', a, 'sm', { v: st.page + 1, icon: 'fas fa-chevron-right', disabled: st.page >= st.pages })}${btn('', a, 'sm btn-ghost', { v: st.pages, icon: 'fas fa-angles-right', disabled: st.page >= st.pages })}</div></div>`;
}

/** Item picker field (typeahead with the item catalogue) */
function itemField(name, label, value = '', o = {}) {
  return { name, label, value, list: 'dl-items', placeholder: o.placeholder || 'Start typing an item name', span: o.span, help: o.help };
}

function inventoryGrid(items, a, sel) {
  if (!items || !items.length) return empty('fas fa-box-open', 'Nothing in here');
  return `<div class="inv">${items.map(it => {
    const dur = it.metadata && typeof it.metadata.durability === 'number' && it.metadata.durability <= 100 ? `<span class="dur"><i style="width:${Math.max(0, it.metadata.durability)}%"></i></span>` : '';
    return `<div class="slot ${sel === it.slot ? 'on' : ''}" data-a="${a}" data-v="${it.slot}" title="${esc(it.name)}">
      <span class="sl">${it.slot}</span><span class="cnt">x${num(it.count)}</span>
      <img src="${esc(imgUrl(it.name, it.metadata && it.metadata.image ? it.metadata.image + '.png' : null))}" onerror="this.outerHTML='<div class=&quot;ph-i&quot;><i class=&quot;fas fa-box&quot;></i></div>'">
      <b>${esc(it.label || it.name)}</b>${dur}</div>`;
  }).join('')}</div>`;
}

function metaHtml(m) {
  if (!m || (typeof m === 'object' && !Object.keys(m).length)) return '<span class="muted">No metadata</span>';
  return `<div class="pre">${esc(JSON.stringify(m, null, 2))}</div>`;
}

/* ═══ notifications toggle + settings ═══════════════════════════════════ */
function bellHtml() {
  const p = (S.boot && S.boot.prefs) || {};
  if (S.boot && S.boot.notifyEnabled === false) return '';
  const on = p.notify !== false;
  return `<button class="bellbtn ${on ? 'on' : ''}" data-a="bellToggle" title="${on ? 'In-game alerts are on. Click to mute them.' : 'In-game alerts are muted. Click to turn them on.'}"><i class="fas fa-${on ? 'bell' : 'bell-slash'}"></i></button>`;
}
async function setPrefs(changes, msg) {
  const r = await call('prefs:set', changes);
  if (!r) return;
  S.boot.prefs = r;
  const b = $('.bellbtn'); if (b) b.outerHTML = bellHtml();
  if (S.page === 'settings') rerender();
  if (msg) toast(msg, 'success', 1800);
}
A.bellToggle = () => { const on = S.boot.prefs.notify !== false; setPrefs({ notify: !on }, on ? 'In-game alerts muted' : 'In-game alerts on'); };
A.prefToggle = (v, el) => setPrefs({ [v]: el.checked });

page('settings', {
  label: 'My settings', icon: 'fas fa-sliders',
  render() {
    const p = S.boot.prefs || {};
    const row = (key, title, sub, disabled) => `<label class="setrow ${disabled ? 'off' : ''}"><div class="tx"><b>${esc(title)}</b><span>${esc(sub)}</span></div>
      <span class="switch"><input type="checkbox" data-a="prefToggle" data-v="${key}" ${p[key] !== false ? 'checked' : ''} ${disabled ? 'disabled' : ''}><i></i></span></label>`;
    const master = p.notify !== false;
    return ph('My settings', 'These only change things for you, and follow you across characters') + `<div class="content"><div class="stack" style="max-width:720px">
      ${S.boot.notifyEnabled === false ? note('In-game alerts are turned off for everyone in <b>Config.NotifyStaff</b>.', 'amber') : ''}
      <div class="card"><div class="card-h"><h3><i class="fas fa-bell"></i>In-game alerts</h3></div><div class="card-b np">
        ${row('notify', 'Show alerts in game', 'Pop-up notifications while you play. Turn this off to mute all of them.')}
        ${row('flags', 'Flagged items and money spikes', 'Items from untrusted scripts, amounts over a threshold, sudden money gains.', !master)}
        ${row('dupes', 'Dupe alerts', 'Duplicate serials, dupe attempts and item supply spikes.', !master)}
        ${row('staff', 'Other staff actions', 'Gives, removals, wipes, rollbacks, server-wide actions and inventory restarts by other staff.', !master)}
      </div></div>
      <div class="card"><div class="card-h"><h3><i class="fas fa-volume-high"></i>Panel</h3></div><div class="card-b np">
        ${row('sounds', 'Sounds', 'Quiet clicks when an action succeeds or fails.')}
      </div></div>
      <p class="muted" style="font-size:11px">Everything is still logged and sent to webhooks. These settings only change what shows up on your screen.</p>
    </div></div>`;
  },
});
