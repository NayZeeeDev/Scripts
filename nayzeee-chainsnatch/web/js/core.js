/* ═══════════════════════════════════════════════════════════
   CHAIN SNATCH · core
   helpers, inline SVG icons, toasts, the key hint, the message router
   ═══════════════════════════════════════════════════════════ */
'use strict';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-chainsnatch';
const post = (name, data = {}) =>
  fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) })
    .catch(() => {});
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const arr = (v) => Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);

const S = { cfg: { self: RES, props: 'nayzeee-chainprops', inventory: 'ox_inventory' }, v: Date.now() };

/* ---------------- icons (inline SVG, 24px grid, stroked) ---------------- */
const PATHS = {
  check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  alert: '<path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8v.01"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>',
  gem: '<path d="M6 3.5h12l3.5 5L12 20.5 2.5 8.5z"/><path d="M2.5 8.5h19M9 3.5 7.5 8.5 12 20.5 16.5 8.5 15 3.5"/>',
  chain: '<path d="M9.5 14.5 14.5 9.5"/><path d="M11 6.5l1.5-1.5a4 4 0 0 1 5.7 5.7L16.7 12.2"/><path d="M13 17.5l-1.5 1.5a4 4 0 0 1-5.7-5.7l1.5-1.5"/>',
  hand: '<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V11M11 10.5V4.5a1.5 1.5 0 0 1 3 0V11M14 10.5V6a1.5 1.5 0 0 1 3 0v8a7 7 0 0 1-7 7h-.5a6 6 0 0 1-4.6-2.2L2.8 16a1.6 1.6 0 0 1 2.4-2.1L8 16.5"/>',
  up: '<path d="M12 19V5M6 11l6-6 6 6"/>',
  down: '<path d="M12 5v14M6 13l6 6 6-6"/>',
  left: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
  right: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  place: '<path d="M4 18h16"/><path d="M12 4v9M8 9l4 4 4-4"/>',
  off: '<path d="M7 7.5a6.5 6.5 0 1 0 10 0"/><path d="M12 3v8"/>',
  rotate: '<path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 4v5h-5"/>',
  tilt: '<path d="M4 16 20 8"/><path d="M4 20h16"/>',
  camera: '<path d="M4 8h3l1.5-2h7L17 8h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
  box: '<path d="M3.5 7.5 12 3.5l8.5 4v9L12 20.5l-8.5-4z"/><path d="M3.5 7.5 12 11.5l8.5-4M12 11.5v9"/>',
  wand: '<path d="M4 20 15 9"/><path d="M15 4v2M19 8h2M18 5l1.5-1.5M14 9l1 1"/>',
  save: '<path d="M5 4h11l3 3v13H5z"/><path d="M8 4v5h7V4M8 20v-6h8v6"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
  paste: '<path d="M9 4h6v3H9z"/><path d="M15 5.5h3v15H6v-15h3"/>',
  undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  gift: '<rect x="3.5" y="8" width="17" height="4" rx="1"/><path d="M5 12v8.5h14V12M12 8v12.5M12 8S10.5 3.5 8 4.5 8.5 8 12 8zM12 8s1.5-4.5 4-3.5S15.5 8 12 8z"/>',
  tag: '<path d="M3.5 12.5V4.5h8l9 9-8 8z"/><circle cx="8" cy="9" r="1.3"/>',
  bolt: '<path d="M13 3 5 14h6l-1 7 8-11h-6z"/>',
  folder: '<path d="M3.5 6.5h6l2 2h9v10h-17z"/>',
  bone: '<circle cx="12" cy="5" r="2"/><path d="M12 7v10M8 21l4-4 4 4M7 11h10"/>',
  eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  throw: '<path d="M5 19c2-6 6-11 14-13"/><path d="M14 4.5 19 6l-1.5 5"/>',
};
function icon(name) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${PATHS[name] || PATHS.chain}</svg>`;
}
const fillIcons = (root) => $$('[data-icon]', root).forEach((el) => { el.innerHTML = icon(el.dataset.icon); });
fillIcons(document);

/* ---------------- chain pictures ----------------
   ox_inventory/web/images (the real item icon) → this resource's icons/ (studio shots, after a restart)
   → nayzeee-chainprops/icons (drawn by chainkit) → an icon */
function imgSources(prop) {
  if (!prop) return [];
  const p = encodeURIComponent(prop), v = `?v=${S.v}`;
  const out = [];
  if (S.cfg.inventory) out.push(`nui://${S.cfg.inventory}/web/images/${p}.png${v}`);
  out.push(`nui://${S.cfg.self}/icons/${p}.png${v}`);
  out.push(`nui://${S.cfg.props}/icons/${p}.png${v}`);
  return out;
}
function chainImg(prop, fallback = 'chain') {
  const src = imgSources(prop);
  if (!src.length) return icon(fallback);
  return `<img src="${src[0]}" data-next="${esc(src.slice(1).join('|'))}" data-fb="${fallback}" alt="" onerror="imgNext(this)">`;
}
window.imgNext = (el) => {
  const rest = (el.dataset.next || '').split('|').filter(Boolean);
  if (!rest.length) { el.outerHTML = icon(el.dataset.fb || 'chain'); return; }
  el.dataset.next = rest.slice(1).join('|');
  el.src = rest[0];
};

/* ---------------- key caps in hint text: <kc>E</kc> ---------------- */
function keyText(t) {
  return esc(t).replace(/&lt;kc&gt;(.*?)&lt;\/kc&gt;/g, (_, k) => `<span class="kc">${k}</span>`);
}

/* ---------------- toasts ---------------- */
const TOAST_ICON = { success: 'check', error: 'x', warning: 'alert', info: 'info' };
function toast(d) {
  const kind = ['success', 'error', 'warning'].includes(d.kind) ? d.kind : (d.kind === 'inform' ? 'info' : (d.kind || 'info'));
  const dur = d.duration || 4500;
  const el = document.createElement('div');
  el.className = `toast t-${TOAST_ICON[kind] ? kind : 'info'}`;
  el.innerHTML = `<div class="ch-frame"><div class="ch-in"><span class="ti">${icon(TOAST_ICON[kind] || 'info')}</span><p>${esc(d.message)}</p><i class="prog"></i></div></div>`;
  const box = $('#toasts');
  box.appendChild(el);
  while (box.children.length > 5) box.firstChild.remove();
  el.querySelector('.prog').animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }], { duration: dur, easing: 'linear', fill: 'forwards' });
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 220); }, dur);
}

/* ---------------- hint ---------------- */
function hint(d) {
  const el = $('#hint');
  if (!d || !d.text) { el.hidden = true; return; }
  $('.hint-tx', el).innerHTML = keyText(d.text);
  el.hidden = false;
}

/* ---------------- router ---------------- */
const H = {
  init(d) {
    Object.assign(S.cfg, d || {});
    document.documentElement.style.setProperty('--z', d.scale || 1);
    $('#toasts').dataset.pos = d.toasts || 'top-right';
  },
  toast, hint,
};
window.addEventListener('message', (e) => {
  const { action, data } = e.data || {};
  const fn = H[action];
  if (fn) { try { fn(data || {}); } catch (err) { console.error(action, err); } }
});
