/* ═══════════════════════════════════════════════════════════
   Tuning UI · core + tuning menu
   ═══════════════════════════════════════════════════════════ */
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-tuning';
let CFG = null;

async function post(name, data = {}) {
  if (window.__mock) return window.__mock(name, data);
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
    const txt = await r.text();
    return txt ? JSON.parse(txt) : null;
  } catch (e) { return null; }
}

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => (n == null ? '-' : (n < 0 ? '-$' : '$') + Math.abs(Math.round(n)).toLocaleString('en-US'));
const same = (a, b) => {
  if (a === b) return true;
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) < 1e-4;
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object') return false;
  const ka = Object.keys(a), kb = Object.keys(b);
  return ka.length === kb.length && ka.every((k) => same(a[k], b[k]));
};
const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
const T = (k, fb) => (CFG && CFG.strings && CFG.strings[k]) || fb;

function throttle(fn, ms) {
  let last = 0, timer = null, args = null;
  const t = (...a) => {
    args = a;
    const now = Date.now();
    if (now - last >= ms) { last = now; fn(...args); }
    else if (!timer) timer = setTimeout(() => { last = Date.now(); timer = null; fn(...args); }, ms - (now - last));
  };
  t.cancel = () => { clearTimeout(timer); timer = null; };  // drop a pending trailing call
  return t;
}

function el(html) {
  const t = document.createElement('template');
  t.innerHTML = html.trim();
  return t.content.firstElementChild;
}

function flash(msg, kind = 'e') {
  const box = $('#flashes');
  const f = el(`<div class="flash ${kind} anim-up"><i class="fa-solid ${kind === 'e' ? 'fa-circle-exclamation' : 'fa-circle-check'}"></i><span>${esc(msg)}</span></div>`);
  box.innerHTML = '';
  box.appendChild(f);
  setTimeout(() => f.remove(), 3800);
}

// fit a 1920x1080 layout to any resolution
function scaleStage() {
  const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
  const st = $('#stage');
  st.style.zoom = s;
  st.style.width = (window.innerWidth / s) + 'px';
  st.style.height = (window.innerHeight / s) + 'px';
}
window.addEventListener('resize', scaleStage);
scaleStage();

/* ═══════════════ colour helpers + picker ═══════════════ */
const hex2rgb = (h) => { h = h.replace('#', ''); if (h.length === 3) h = h.split('').map((c) => c + c).join(''); const n = parseInt(h, 16); return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }; };
const rgb2hex = (c) => '#' + [c.r, c.g, c.b].map((v) => clamp(Math.round(v), 0, 255).toString(16).padStart(2, '0')).join('');
function rgb2hsv({ r, g, b }) { r /= 255; g /= 255; b /= 255; const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn; let h = 0; if (d) { if (mx === r) h = ((g - b) / d) % 6; else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4; h /= 6; if (h < 0) h += 1; } return { h, s: mx ? d / mx : 0, v: mx }; }
function hsv2rgb({ h, s, v }) { const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s); const m = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][((i % 6) + 6) % 6]; return { r: Math.round(m[0] * 255), g: Math.round(m[1] * 255), b: Math.round(m[2] * 255) }; }
const swatchBg = (c) => (String(c).includes(',') && !String(c).includes('gradient') ? `linear-gradient(135deg,${c})` : c);

const Saved = {
  get() { try { return JSON.parse(localStorage.getItem('nzt_swatches') || '[]'); } catch (e) { return []; } },
  add(hex) { try { const l = Saved.get().filter((x) => x !== hex); l.unshift(hex); localStorage.setItem('nzt_swatches', JSON.stringify(l.slice(0, 14))); } catch (e) {} },
};

function Picker(root, init, onChange) {
  let hsv = rgb2hsv(init || { r: 8, g: 175, b: 162 });
  root.innerHTML = `
    <div class="picker">
      <div class="sv"><i class="dot"></i></div>
      <div class="hue"><i class="dot"></i></div>
      <div class="pick-row"><span class="prev"></span><input class="field" maxlength="7" spellcheck="false"></div>
      <div class="saved"></div>
    </div>`;
  const sv = $('.sv', root), hue = $('.hue', root), prev = $('.prev', root), hexIn = $('input', root), saved = $('.saved', root);
  const paint = (fire = true) => {
    const c = hsv2rgb(hsv);
    sv.style.background = rgb2hex(hsv2rgb({ h: hsv.h, s: 1, v: 1 }));
    $('.dot', sv).style.left = hsv.s * 100 + '%';
    $('.dot', sv).style.top = (1 - hsv.v) * 100 + '%';
    $('.dot', hue).style.left = hsv.h * 100 + '%';
    prev.style.background = rgb2hex(c);
    if (document.activeElement !== hexIn) hexIn.value = rgb2hex(c).toUpperCase();
    if (fire) onChange(c);
  };
  const drag = (area, fn) => area.addEventListener('mousedown', (e) => {
    const move = (ev) => { const r = area.getBoundingClientRect(); fn(clamp((ev.clientX - r.left) / r.width, 0, 1), clamp((ev.clientY - r.top) / r.height, 0, 1)); paint(); };
    move(e);
    const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); };
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', up);
  });
  drag(sv, (x, y) => { hsv.s = x; hsv.v = 1 - y; });
  drag(hue, (x) => { hsv.h = Math.min(x, 0.999); });
  hexIn.addEventListener('input', () => { if (/^#?[0-9a-f]{6}$/i.test(hexIn.value)) { hsv = rgb2hsv(hex2rgb(hexIn.value)); paint(); } });
  const renderSaved = () => {
    saved.innerHTML = `<button class="add" title="Save colour"><i class="fa-solid fa-plus"></i></button>` + Saved.get().map((x) => `<button data-hex="${x}" style="background:${x}"></button>`).join('');
    $('.add', saved).onclick = () => { Saved.add(rgb2hex(hsv2rgb(hsv))); renderSaved(); };
    $$('[data-hex]', saved).forEach((b) => (b.onclick = () => { hsv = rgb2hsv(hex2rgb(b.dataset.hex)); paint(); }));
  };
  renderSaved();
  paint(false);
  return { get: () => hsv2rgb(hsv), set: (c) => { hsv = rgb2hsv(c); paint(false); } };
}

function range(opts) {
  // opts: { label, min, max, step, value, fmt, hint, onInput }
  const w = el(`<div class="rng"><div class="rng-top"><b>${esc(opts.label)}</b><span></span></div><input type="range" min="${opts.min}" max="${opts.max}" step="${opts.step}">${opts.hint ? `<div class="hint">${esc(opts.hint)}</div>` : ''}</div>`);
  const inp = $('input', w), out = $('span', w);
  const upd = () => { const p = ((inp.value - opts.min) / (opts.max - opts.min)) * 100; inp.style.setProperty('--p', p + '%'); out.textContent = opts.fmt ? opts.fmt(+inp.value) : inp.value; };
  inp.value = opts.value; upd();
  inp.addEventListener('input', () => { upd(); opts.onInput && opts.onInput(+inp.value); });
  w.set = (v) => { inp.value = v; upd(); };
  w.get = () => +inp.value;
  return w;
}
/* ═══════════════ TUNING MENU ═══════════════
   Left: category accordion. Centre: option name + price. Bottom: ← → browser.
   Right: option list / editors. Top right: toolbar, cart, balance. */
const Tune = {
  s: null, st: null, cur: null, cat: null, cmp: false, catalog: null,
  listOpen: (() => { try { return localStorage.getItem('nzt_list') !== '0'; } catch (e) { return true; } })(),
};
Object.defineProperty(Tune, 'item', { get: () => Tune.cur });

const CLASSES = ['Compact', 'Sedan', 'SUV', 'Coupe', 'Muscle', 'Sports Classic', 'Sports', 'Super', 'Motorcycle', 'Off-road', 'Industrial', 'Utility', 'Van', 'Cycle', 'Boat', 'Helicopter', 'Plane', 'Service', 'Emergency', 'Military', 'Commercial', 'Train', 'Open Wheel'];
const pad2 = (n) => String(n).padStart(2, '0');
const short = (n) => (n >= 1e6 ? '$' + (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + 'M' : n >= 1e4 ? '$' + Math.round(n / 1e3) + 'K' : money(n));

Tune.open = function (s) {
  Tune.s = s;
  Tune.st = s.state;
  Tune.catalog = null;
  if (!s.resume || !s.categories.some((c) => c.id === Tune.cat)) { Tune.cur = null; Tune.cat = s.categories[0] && s.categories[0].id; }
  const name = `${s.vehicle.make ? s.vehicle.make + ' ' : ''}${s.vehicle.label}`;
  $('#tpShop').textContent = s.shop.label;
  $('#tpTag').textContent = `${s.role === 'mechanic' ? 'Workshop' : s.role === 'admin' ? 'Admin' : 'Tuning'} · v${s.version || (CFG && CFG.version) || '1.0.0'}`;
  $('#stName').textContent = name;
  $('#stClass').textContent = CLASSES[s.vehicle.class] || 'Vehicle';
  $('#stPlate').textContent = s.vehicle.plate;
  const role = $('#stRole');
  role.hidden = s.role === 'customer';
  role.textContent = s.role === 'mechanic' ? 'Mechanic' : s.role === 'admin' ? 'Admin · Free' : '';
  $('#tBal').textContent = s.role === 'admin' ? 'Free' : short((s.money && s.money.bank) || 0);
  $('#tVeh').textContent = (s.vehicle.model || s.vehicle.label || '').toLowerCase();
  $('[data-t="builds"]').hidden = $('[data-t="save"]').hidden = !CFG.builds;
  $('[data-t="lab"]').hidden = !CFG.perf.enabled;
  $('[data-q="testdrive"]').disabled = !CFG.testDrive || s.role !== 'customer';
  Drawer.close();
  Spot.close();
  $('#tune').hidden = false;
  Tune.modes();
  Tune.applyState(s.state);
  Rail.render();
  if (Tune.cur && s.resume) { const id = Tune.cur.id; Tune.cur = null; Tune.select(id); } else Tune.clearItem();
  if (!s.canBuy && s.reason) flash(s.reason, 'e');
};

Tune.hide = function () {
  $('#tune').hidden = true;
  Drawer.close();
  Spot.close();
  Tune.s = null;
  Drawer.waiting = false;
  $('#hotspots').innerHTML = '';
  if (Tune.cmp) { Tune.cmp = false; $('#cmpBadge').hidden = true; }
  $$('#hints button').forEach((b) => b.classList.remove('on'));
};

Tune.close = () => post('close');

/* ---------- mode toggle (self-service / order) ---------- */
Tune.modes = function () {
  const s = Tune.s, box = $('#modes');
  const modes = s.role === 'customer' ? (s.modes || []) : [];
  const cur = (Tune.st && Tune.st.mode) || s.mode;
  const name = { self: 'Self-Service', order: 'Order' };
  if (s.role === 'mechanic') box.innerHTML = '<span class="mode on"><i class="fa-solid fa-user-gear"></i>Mechanic quote</span>';
  else if (s.role === 'admin') box.innerHTML = '<span class="mode on"><i class="fa-solid fa-bolt"></i>Admin</span>';
  else box.innerHTML = modes.map((m) => `<button class="mode ${m === cur ? 'on' : ''}" data-m="${m}" ${modes.length < 2 ? 'disabled' : ''}>${name[m] || m}</button>`).join('');
  $$('[data-m]', box).forEach((b) => (b.onclick = async () => {
    const st = await post('setMode', { mode: b.dataset.m });
    if (st) { Tune.applyState(st); Tune.modes(); }
  }));
};

/* ---------- cart state ---------- */
Tune.line = (id) => (Tune.st && Tune.st.lines ? Tune.st.lines.find((l) => l.id === id) : null);
Tune.valueOf = (id, installed) => { const l = Tune.line(id); return l ? l.value : installed; };
Tune.priceText = (p) => {
  if (!Tune.s) return '';
  if (Tune.s.role === 'admin') return 'Free';
  if (p == null) return Tune.s.showPrices ? '-' : '';
  return p === 0 ? 'Free' : money(p);
};

Tune.applyState = function (st) {
  if (!st) return;
  Tune.st = st;
  const n = (st.lines || []).length;
  $('#cartN').hidden = !n;
  $('#cartN').textContent = n;
  $('#cartTotal').textContent = Tune.s && Tune.s.role === 'admin' ? 'Free' : st.totals ? money(st.totals.total) : n ? n + ' item' + (n > 1 ? 's' : '') : '$0';
  $('#cartBtn').classList.toggle('has', n > 0);
  $('#undo').disabled = !st.canUndo;
  $('#redo').disabled = !st.canRedo;
  Stats.render(st.stats);
  if (Drawer.kind === 'cart') Drawer.render();
  if (Tune.cur && Tune.cur.refresh) Tune.cur.refresh();
  Rail.marks();
  Tune.centre();
};

Tune.setCart = async function (id, value, label) {
  const st = await post('setCart', { id, value: value === undefined ? null : value });
  if (!st) { flash('That part could not be added.'); return null; }
  Tune.applyState(st);
  if (st.added) Toast.show(`${label || st.added} added to cart`, 'fa-circle-check');
  else if (value === null || value === undefined) Toast.show(`${(CFG.parts[id] || {}).label || 'Part'} removed`, 'fa-circle-minus');
  return st;
};

/* ---------- selection ---------- */
Tune.leave = function () {
  if (Tune.cur) { preview.cancel(); post('restore', { id: Tune.cur.id }); post('leaveItem'); }
  Tune.cur = null;
};

Tune.clearItem = function () {
  Tune.leave();
  $('#editor').hidden = true;
  Tune.showBrowse(false);
  Rail.marks();
  Tune.centre();
};

Tune.catOf = (id) => (Tune.s.categories.find((c) => c.items.some((i) => i.id === id)) || {});

Tune.select = async function (id, optLabel) {
  if (Tune.cur && Tune.cur.id === id) { if (optLabel) Tune.jump(optLabel); return; }
  Tune.leave();
  const token = {};
  Tune._tok = token;
  const d = await post('item', { id });
  if (!d || Tune._tok !== token || !Tune.s) return;
  Tune.cur = { id, d, opts: null, idx: 0, refresh: null };
  const cat = Tune.catOf(id);
  if (cat.id && Tune.cat !== cat.id) { Tune.cat = cat.id; Rail.render(); }
  Rail.marks();
  $('#edTitle').textContent = d.label;
  $('#edSub').textContent = cat.label || '';
  const view = $('#view');
  view.innerHTML = '';
  view.scrollTop = 0;
  const R = Items[d.kind] || (d.options ? Items.list : d.action ? Items.action : Items.list);
  const listy = R === Items.list;
  $('#editor').hidden = listy && !Tune.listOpen;
  $('#editor').classList.toggle('compact', listy);
  if (!listy) Tune.showBrowse(false);
  R(view, d);
  if (optLabel) Tune.jump(optLabel);
  Tune.centre();
  const a = $(`#plist [data-id="${id}"]`);
  if (a) a.scrollIntoView({ block: 'nearest' });
};

Tune.jump = function (label) {
  const c = Tune.cur;
  if (!c || !c.opts) return;
  const i = c.opts.findIndex((o) => o.label === label);
  if (i >= 0) Tune.hover(i, true);
};

Tune.hover = function (i, scroll) {
  const c = Tune.cur;
  if (!c || !c.opts || !c.opts[i]) return;
  c.idx = i;
  preview(c.id, c.opts[i].value);
  if (c.box) {
    $$('.row', c.box).forEach((r) => r.classList.toggle('kb', +r.dataset.i === i));
    const r = $(`.row[data-i="${i}"]`, c.box);
    if (r && scroll) r.scrollIntoView({ block: 'nearest' });
  }
  Tune.centre();
};

Tune.unhover = function () {
  const c = Tune.cur;
  if (!c || !c.opts) return;
  preview.cancel();
  post('restore', { id: c.id });
  c.idx = Math.max(0, c.opts.findIndex((o) => same(o.value, Tune.valueOf(c.id, c.d.installed))));
  if (c.draw) c.draw();
  Tune.centre();
};

Tune.browse = function (dir) {
  const c = Tune.cur;
  if (!c || !c.opts || !c.opts.length) return;
  Tune.hover((c.idx + dir + c.opts.length) % c.opts.length, true);
};

Tune.pick = function (i) {
  const c = Tune.cur;
  if (!c || !c.opts || !c.opts[i]) return;
  c.idx = i;
  const o = c.opts[i];
  const inCart = Tune.line(c.id);
  if (inCart && same(inCart.value, o.value)) return Tune.setCart(c.id, null);
  if (!inCart && same(o.value, c.d.installed)) return Toast.show(`${o.label} is already fitted`, 'fa-circle-info');
  Tune.setCart(c.id, o.value, o.label);
};

Tune.addCurrent = function () {
  const c = Tune.cur;
  if (!c) return;
  if (c.opts) return Tune.pick(c.idx);
  const b = $('#view [data-apply]');
  if (b && !b.disabled) b.click();
};

Tune.showBrowse = (on) => { $('#browse').hidden = !on; };

/* option dock: name, price, state chip and the ← → browser */
Tune.centre = function () {
  if (!Tune.s) return;
  const c = Tune.cur;
  const title = $('#oTitle'), price = $('#oPrice'), desc = $('#oDesc'), crumb = $('#crumb'), st = $('#oState');
  $('#odock').classList.toggle('idle', !c);
  if (!c) {
    const v = Tune.s.vehicle;
    crumb.innerHTML = `<i class="fa-solid fa-car-side"></i>${esc(CLASSES[v.class] || 'Vehicle')} · ${esc(v.plate)}`;
    title.textContent = `${v.make ? v.make + ' ' : ''}${v.label}`;
    price.textContent = '';
    desc.textContent = Tune.s.role === 'mechanic' ? 'Build a quote for the customer: pick a part, browse with ← →, press Enter.' : 'Pick a part, browse with ← →, press Enter to add it. Click the markers on the car to jump to a part.';
    st.textContent = ''; st.className = 'ost';
    return;
  }
  const cat = Tune.catOf(c.id);
  crumb.innerHTML = `<button id="crumbBack" title="Back (Backspace)"><i class="fa-solid fa-xmark"></i></button>${esc(cat.label || '')}<i class="fa-solid fa-angle-right"></i><b>${esc(c.d.label)}</b>`;
  $('#crumbBack').onclick = Tune.clearItem;
  const line = Tune.line(c.id);
  const chip = (cls, txt) => { st.className = 'ost ' + cls; st.textContent = txt; };
  if (c.opts && c.opts.length) {
    const o = c.opts[c.idx] || c.opts[0];
    const inst = same(o.value, c.d.installed);
    const inCart = line && same(line.value, o.value);
    title.textContent = o.label;
    price.textContent = inst && !line ? '' : Tune.priceText(o.price);
    desc.textContent = o.desc || '';
    if (inCart) chip('cart', 'In cart'); else if (inst) chip('inst', line ? 'Fitted now' : 'Fitted'); else chip('', 'Preview');
    const n = c.opts.length;
    $('#bCount').textContent = `${c.idx + 1} / ${n}`;
    const ticks = $('#bTicks');
    if (n <= 40) {
      if (ticks.childElementCount !== n || ticks.dataset.id !== c.id) { ticks.dataset.id = c.id; ticks.innerHTML = '<i></i>'.repeat(n); $$('i', ticks).forEach((t, i) => (t.onclick = () => Tune.hover(i, true))); ticks.classList.remove('bar'); }
      $$('i', ticks).forEach((t, i) => { t.className = i === c.idx ? 'on' : same(c.opts[i].value, c.d.installed) ? 'inst' : line && same(c.opts[i].value, line.value) ? 'cart' : ''; });
    } else {
      ticks.dataset.id = c.id; ticks.classList.add('bar');
      ticks.innerHTML = `<b style="width:${((c.idx + 1) / n) * 100}%"></b>`;
    }
    const add = $('#bAdd');
    if (inCart) { add.className = 'btn warn'; add.innerHTML = '<i class="fa-solid fa-xmark"></i>Remove'; }
    else if (inst && !line) { add.className = 'btn'; add.innerHTML = '<i class="fa-solid fa-check"></i>Fitted'; }
    else if (inst && line) { add.className = 'btn'; add.innerHTML = '<i class="fa-solid fa-rotate-left"></i>Keep stock'; }
    else { add.className = 'btn pri'; add.innerHTML = '<i class="fa-solid fa-cart-plus"></i>Add to cart'; }
    $('#bList').classList.toggle('on', Tune.listOpen);
  } else {
    title.textContent = c.d.label;
    const p = c.price != null ? c.price : c.d.price != null ? c.d.price : c.d.prices ? c.d.prices.index : null;
    price.textContent = line ? Tune.priceText(line.price) : Tune.priceText(p);
    desc.textContent = line ? line.desc || '' : 'Set it up in the panel on the right.';
    if (line) chip('cart', 'In cart'); else chip('', 'Editor');
  }
};

/* ═══════════════ PARTS CATALOG: category rail + part list ═══════════════ */
const Rail = {};
Rail.render = function () {
  const s = Tune.s;
  $('#rail').innerHTML = s.categories.map((c) => `<button class="rc ${c.id === Tune.cat ? 'on' : ''}" data-c="${c.id}" title="${esc(c.label)}"><i class="fa-solid ${c.icon}"></i><span>${esc(c.label)}</span><em data-n="${c.id}"></em></button>`).join('');
  $$('#rail .rc').forEach((b) => (b.onclick = () => Rail.pick(b.dataset.c)));
  const cat = s.categories.find((c) => c.id === Tune.cat) || s.categories[0];
  if (!cat) return;
  $('#plTitle').textContent = cat.label;
  $('#plist').innerHTML = cat.items.map((i) => `<button class="ai" data-id="${i.id}"><i class="fa-solid ${i.icon}"></i><span>${esc(i.label)}</span><em></em></button>`).join('');
  $$('#plist .ai').forEach((b) => (b.onclick = () => Tune.select(b.dataset.id)));
  Rail.marks();
};
Rail.pick = function (id) {
  if (Tune.cat === id) return;
  Tune.cat = id;
  Rail.render();
  $('#plist').scrollTop = 0;
};
Rail.marks = function () {
  if (!Tune.s) return;
  $$('#plist .ai').forEach((b) => {
    const l = Tune.line(b.dataset.id);
    b.classList.toggle('on', !!Tune.cur && Tune.cur.id === b.dataset.id);
    b.classList.toggle('mod', !!l);
    $('em', b).textContent = l ? Tune.priceText(l.price) : '';
  });
  Tune.s.categories.forEach((c) => {
    const n = c.items.filter((i) => Tune.line(i.id)).length;
    const e = $(`#rail [data-n="${c.id}"]`);
    if (e) { e.textContent = n || ''; e.hidden = !n; }
    if (c.id === Tune.cat) $('#plSub').textContent = n ? `${n} of ${c.items.length} changed` : `${c.items.length} part${c.items.length === 1 ? '' : 's'}`;
  });
};
Rail.step = function (dir) {
  const cat = Tune.s.categories.find((c) => c.id === Tune.cat);
  if (!cat || !cat.items.length) return;
  const ids = cat.items.map((i) => i.id);
  const i = Tune.cur ? ids.indexOf(Tune.cur.id) : -1;
  Tune.select(ids[(i + dir + ids.length) % ids.length]);
};
Rail.cat = function (dir) {
  const cats = Tune.s.categories;
  const i = cats.findIndex((c) => c.id === Tune.cat);
  Rail.pick(cats[(i + dir + cats.length) % cats.length].id);
};

/* ═══════════════ HOTSPOTS ═══════════════ */
const Hot = {
  render(list) {
    const box = $('#hotspots');
    if (!Tune.s || Tune.cmp) { box.innerHTML = ''; return; }
    const keep = {};
    list.forEach((h) => {
      let b = $(`[data-k="${h.k}"]`, box);
      if (!b) {
        const lbl = h.item ? (CFG.parts[h.item] || {}).label : (Tune.s.categories.find((c) => c.id === h.cat) || {}).label;
        b = el(`<button class="hs" data-k="${h.k}"><span class="dm"><i class="fa-solid ${h.icon}"></i></span><span class="hl">${esc(lbl || '')}</span></button>`);
        b.onclick = async () => {
          // pick the part, then frame that whole area of the car (after the part's own camera preset)
          if (h.item) await Tune.select(h.item);
          else {
            const cat = Tune.s.categories.find((c) => c.id === h.cat);
            if (!cat) return;
            Tune.cat = cat.id;
            Rail.render();
            await Tune.select(cat.items[0].id);
          }
          setTimeout(() => post('camera', { spot: h.k }), 60);
        };
        box.appendChild(b);
      }
      b.style.left = h.x * 100 + '%';
      b.style.top = h.y * 100 + '%';
      b.classList.toggle('on', !!Tune.cur && (Tune.cur.id === h.item || Tune.catOf(Tune.cur.id).id === h.cat));
      keep[h.k] = true;
    });
    $$('.hs', box).forEach((b) => { if (!keep[b.dataset.k]) b.remove(); });
  },
};

/* ═══════════════ SPOTLIGHT SEARCH ═══════════════ */
const Spot = { kb: 0, res: [] };
Spot.open = async function () {
  if (!Tune.s) return;
  $('#spot').hidden = false;
  const inp = $('#spotIn');
  inp.value = '';
  inp.focus();
  Spot.run();
  if (!Tune.catalog) {
    Tune.catalog = (await post('catalog')) || {};
    if (!$('#spot').hidden) Spot.run();
  }
};
Spot.close = () => { $('#spot').hidden = true; $('#spotIn').blur(); };
Spot.run = function () {
  const q = $('#spotIn').value.trim().toLowerCase();
  const res = [];
  Tune.s.categories.forEach((c) => c.items.forEach((i) => {
    if (!q || i.label.toLowerCase().includes(q) || c.label.toLowerCase().includes(q)) res.push({ id: i.id, a: c.label, b: i.label, icon: i.icon });
  }));
  if (q && Tune.catalog) {
    Object.entries(Tune.catalog).forEach(([id, opts]) => {
      const part = CFG.parts[id];
      if (!part) return;
      opts.forEach((o) => { if (o.label.toLowerCase().includes(q)) res.push({ id, a: part.label, b: o.label, opt: o.label, price: o.price, icon: part.icon }); });
    });
  }
  Spot.res = res.slice(0, 60);
  Spot.kb = 0;
  const box = $('#spotRes');
  box.innerHTML = Spot.res.length ? Spot.res.map((r, i) => `<button class="sr ${i === 0 ? 'kb' : ''}" data-i="${i}"><span class="si"><i class="fa-solid ${r.icon}"></i></span><span class="st"><b>${esc(r.b)}</b><small>${esc(r.a)}${r.opt ? ' option' : ''}</small></span>${r.price != null ? `<em>${Tune.priceText(r.price)}</em>` : ''}<span class="go">↵</span></button>`).join('')
    : '<div class="empty"><i class="fa-solid fa-magnifying-glass"></i><b>Nothing found</b><span>Try a part or option name.</span></div>';
  $$('.sr', box).forEach((b) => (b.onclick = () => Spot.go(+b.dataset.i)));
};
Spot.go = function (i) {
  const r = Spot.res[i];
  if (!r) return;
  Spot.close();
  Tune.select(r.id, r.opt);
};
Spot.key = function (e) {
  if (e.key === 'Escape') { e.preventDefault(); return Spot.close(); }
  if (e.key === 'Enter') { e.preventDefault(); return Spot.go(Spot.kb); }
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    Spot.kb = clamp(Spot.kb + (e.key === 'ArrowDown' ? 1 : -1), 0, Spot.res.length - 1);
    $$('#spotRes .sr').forEach((b, i) => b.classList.toggle('kb', i === Spot.kb));
    const b = $('#spotRes .sr.kb');
    if (b) b.scrollIntoView({ block: 'nearest' });
  }
};
$('#spotIn').addEventListener('input', throttle(Spot.run, 90));
$('#spotIn').addEventListener('keydown', Spot.key);
$('#spotX').onclick = Spot.close;

/* ═══════════════ TOASTS ═══════════════ */
const Toast = {
  show(text, icon = 'fa-circle-check') {
    const box = $('#toasts');
    const t = el(`<div class="tst anim-up"><i class="fa-solid ${icon}"></i><span>${esc(text)}</span><button><i class="fa-solid fa-xmark"></i></button></div>`);
    $('button', t).onclick = () => t.remove();
    box.appendChild(t);
    while (box.children.length > 4) box.firstElementChild.remove();
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 300); }, 3200);
  },
};

/* ---------- item renderers ---------- */
const Items = {};
const preview = throttle((id, value) => post('preview', { id, value }), 70);

function priceBar(view, label, price, onApply, extra = '') {
  Tune.cur && (Tune.cur.price = price);
  const pb = el(`<div class="pricebar"><div class="p"><small>${esc(label)}</small><span>${Tune.priceText(price)}</span></div><div class="hrow">${extra}<button class="btn pri" data-apply><i class="fa-solid fa-check"></i>Add to build</button></div></div>`);
  $('[data-apply]', pb).onclick = onApply;
  view.appendChild(pb);
  return pb;
}

function optionRows(view, d, opts, { onPick, icon } = {}) {
  const box = el('<div class="rows opts"></div>');
  const cur = () => Tune.valueOf(d.id, d.installed);
  const c = Tune.cur;
  c.opts = opts;
  c.idx = Math.max(0, opts.findIndex((o) => same(o.value, cur())));
  const draw = () => {
    box.innerHTML = opts.map((o, i) => {
      const sel = same(o.value, cur());
      const inst = same(o.value, d.installed);
      return `<button class="row ${sel ? 'sel' : ''} ${i === c.idx ? 'kb' : ''}" data-i="${i}">
        ${icon ? `<span class="ic"><i class="fa-solid ${icon}"></i></span>` : ''}
        <span class="tx"><b>${esc(o.label)}</b>${o.desc ? `<span>${esc(o.desc)}</span>` : ''}</span>
        <span class="rt">${inst ? '<span class="tag">Installed</span>' : ''}${sel && !inst ? '<span class="tag t">In cart</span>' : ''}<span class="pr">${inst ? '' : Tune.priceText(o.price)}</span></span>
      </button>`;
    }).join('');
    $$('.row', box).forEach((r) => {
      const i = +r.dataset.i;
      r.onmouseenter = () => Tune.hover(i);
      r.onclick = () => (onPick ? onPick(opts[i]) : Tune.pick(i));
    });
  };
  box.onmouseleave = () => Tune.unhover();
  c.draw = draw;
  c.box = box;
  draw();
  view.appendChild(box);
  c.refresh = draw;
  Tune.showBrowse(true);
  Tune.centre();
  const k = $('.row.kb', box);
  if (k) setTimeout(() => k.scrollIntoView({ block: 'center' }), 0);
  return box;
}

Items.list = (view, d) => {
  if (d.kind === 'airride') view.appendChild(el(`<div class="note" style="margin-bottom:10px"><i class="fa-solid fa-wind"></i><span>Adjust height while driving with <b>Page Up / Page Down</b>. Presets: ${d.presets.map((p) => esc(p.label)).join(' · ')}.</span></div>`));
  if (d.kind === 'swap') view.appendChild(el(`<div class="note" style="margin-bottom:10px"><i class="fa-solid fa-volume-high"></i><span>Hover a swap and press <b>R</b> to hear it.</span></div>`));
  if (d.kind === 'nitrous') view.appendChild(el(`<div class="note" style="margin-bottom:10px"><i class="fa-solid fa-fire-flame-simple"></i><span>Hold <b>Shift</b> to boost, hold <b>X</b> to purge.</span></div>`));
  if (d.kind === 'ecu') view.appendChild(el(`<div class="note" style="margin-bottom:10px"><i class="fa-solid fa-microchip"></i><span>This fits the hardware. A mechanic tunes it afterwards on the tablet in <b>ECU Studio</b>: timing, mixture, power, grip and more.</span></div>`));
  if (d.kind === 'sound') view.appendChild(el(`<div class="note" style="margin-bottom:10px"><i class="fa-solid fa-volume-high"></i><span>Browse a note and press <b>R</b> to rev it. Only this car changes, other cars of the same model keep theirs.</span></div>`));
  if (d.kind === 'gearbox') view.appendChild(el(`<div class="note" style="margin-bottom:10px"><i class="fa-solid fa-arrow-down-up-across-line"></i><span>Manual: shift with <b>↑ / ↓</b>, switch modes with <b>K</b>. Downshifting into the red damages the engine.</span></div>`));
  if (d.kind === 'drivetrain' || d.kind === 'tyres' || d.kind === 'ceramic' || d.kind === 'driftKit') view.appendChild(el(`<div class="note" style="margin-bottom:10px"><i class="fa-solid fa-car-burst"></i><span>Handling changes are felt on the road. Take it for a test drive.</span></div>`));
  optionRows(view, d, d.options || [], { icon: d.icon });
};

Items.action = (view, d) => {
  const inCart = !!Tune.line(d.id);
  let info = '';
  if (d.health) info = meter([['Engine', d.health.engine], ['Body', d.health.body]]);
  if (d.dirt != null) info = meter([['Dirt', d.dirt, true]]);
  if (d.wear) info = meter(Object.entries(d.wear).map(([k, v]) => [cap(k), Math.round(v)]));
  view.innerHTML = `<div class="card">${info || '<span class="dim">Ready when you are.</span>'}</div>`;
  const pb = priceBar(view, 'Price', d.price, () => Tune.setCart(d.id, inCart ? null : true).then(() => { const v = $('#view'); v.innerHTML = ''; Items.action(v, d); Tune.centre(); }));
  if (inCart) { const b = $('[data-apply]', pb); b.className = 'btn warn'; b.innerHTML = '<i class="fa-solid fa-xmark"></i>Remove'; }
};

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
function meter(rows) {
  return `<div class="meter">${rows.map(([n, v, inv]) => {
    const bad = inv ? v > 60 : v < 40, warn = inv ? v > 30 : v < 70;
    return `<div class="mt"><span>${esc(n)}</span><div class="trk"><i class="${bad ? 'b' : warn ? 'w' : ''}" style="width:${clamp(v, 0, 100)}%"></i></div><b>${Math.round(v)}%</b></div>`;
  }).join('')}</div>`;
}

Items.wheels = async (view, d) => {
  Tune.showBrowse(false);
  const types = d.types || [];
  if (!types.length) { view.innerHTML = '<div class="empty"><i class="fa-solid fa-circle-dot"></i><b>No rims available</b></div>'; return; }
  let cur = Tune.valueOf('wheels', d.installed);
  let type = types.find((t) => t.id === cur.type) ? cur.type : types[0].id;
  const chips = el(`<div class="chips" style="margin-bottom:12px">${types.map((t) => `<button class="chip ${t.id === type ? 'on' : ''}" data-t="${t.id}"><i class="fa-solid ${t.icon}"></i>${esc(t.label)}<small>${t.count}</small></button>`).join('')}</div>`);
  const list = el('<div></div>');
  view.appendChild(chips);
  view.appendChild(list);
  const load = async () => {
    list.innerHTML = '';
    const opts = await post('wheelList', { type });
    if (!opts || !Tune.cur || Tune.cur.id !== 'wheels') return;
    optionRows(list, d, opts, { icon: 'fa-circle-dot' });
  };
  $$('.chip', chips).forEach((c) => (c.onclick = () => { type = +c.dataset.t; $$('.chip', chips).forEach((x) => x.classList.toggle('on', x === c)); load(); }));
  load();
};

function swatchGrid(colors, isSel, isInst, onHover, onPick, nameEl, priceFn) {
  const g = el(`<div class="swatches">${colors.map((c, i) => `<button class="swatch" data-i="${i}" style="background:${swatchBg(c[2])}" title="${esc(c[1])}"></button>`).join('')}</div>`);
  const draw = () => $$('.swatch', g).forEach((s) => { const c = colors[+s.dataset.i]; s.classList.toggle('sel', isSel(c)); s.classList.toggle('inst', isInst(c)); });
  $$('.swatch', g).forEach((s) => {
    const c = colors[+s.dataset.i];
    s.onmouseenter = () => { onHover(c); if (nameEl) nameEl.innerHTML = `<b>${esc(c[1])}</b><span class="dim">${priceFn ? Tune.priceText(priceFn(c)) : ''}</span>`; };
    s.onclick = () => onPick(c);
  });
  draw();
  g.redraw = draw;
  return g;
}

Items.color = (view, d) => {
  const groups = CFG.paints.map((g) => ({ id: g.id, label: g.label, colors: g.colors }));
  if (CFG.chameleon) groups.push({ id: 'chameleon', label: 'Chameleon', colors: CFG.chameleon });
  if (d.rgb) groups.push({ id: 'rgb', label: 'Custom' });
  const cur = () => Tune.valueOf(d.id, d.installed);
  const c0 = cur();
  let gid = c0.mode === 'rgb' ? 'rgb' : (groups.find((g) => g.colors && g.colors.some((c) => c[0] === c0.index)) || groups[0]).id;
  const tabs = el(`<div class="seg" style="margin-bottom:12px">${groups.map((g) => `<button data-g="${g.id}">${esc(g.label)}</button>`).join('')}</div>`);
  const body = el('<div></div>');
  view.appendChild(tabs);
  view.appendChild(body);
  const draw = () => {
    $$('button', tabs).forEach((b) => b.classList.toggle('on', b.dataset.g === gid));
    body.innerHTML = '';
    const g = groups.find((x) => x.id === gid);
    if (gid === 'rgb') {
      const pv = cur();
      let finish = pv.mode === 'rgb' ? pv.finish || 0 : 1;
      const holder = el('<div></div>');
      body.appendChild(holder);
      const pk = Picker(holder, pv.mode === 'rgb' ? pv : { r: 8, g: 175, b: 162 }, (c) => preview(d.id, { mode: 'rgb', r: c.r, g: c.g, b: c.b, finish }));
      const fin = el(`<div style="margin-top:12px"><span class="lbl">Finish</span><div class="seg">${CFG.finishes.map((f) => `<button data-f="${f[0]}" class="${f[0] === finish ? 'on' : ''}">${esc(f[1])}</button>`).join('')}</div></div>`);
      body.appendChild(fin);
      $$('[data-f]', fin).forEach((b) => (b.onclick = () => { finish = +b.dataset.f; $$('[data-f]', fin).forEach((x) => x.classList.toggle('on', x === b)); const c = pk.get(); preview(d.id, { mode: 'rgb', ...c, finish }); }));
      priceBar(body, 'Custom colour', d.prices.rgb, () => { const c = pk.get(); Saved.add(rgb2hex(c)); Tune.setCart(d.id, { mode: 'rgb', r: c.r, g: c.g, b: c.b, finish }); });
      Tune.item.refresh = null;
      return;
    }
    const name = el('<div class="swname"><b>&nbsp;</b></div>');
    const grid = swatchGrid(g.colors,
      (c) => cur().mode === 'index' && cur().index === c[0],
      (c) => d.installed.mode === 'index' && d.installed.index === c[0],
      (c) => preview(d.id, { mode: 'index', index: c[0] }),
      (c) => Tune.setCart(d.id, { mode: 'index', index: c[0] }),
      name, () => (gid === 'chameleon' ? d.prices.chameleon : d.prices.index));
    grid.onmouseleave = () => { preview.cancel(); post('restore', { id: d.id }); };
    body.appendChild(grid);
    body.appendChild(name);
    Tune.item.refresh = () => grid.redraw();
  };
  $$('button', tabs).forEach((b) => (b.onclick = () => { gid = b.dataset.g; draw(); }));
  draw();
};

Items.smoke = (view, d) => {
  let c = Tune.valueOf(d.id, d.installed);
  const presets = el(`<div class="swatches" style="margin-bottom:12px">${d.presets.map((x) => `<button class="swatch" data-h="${x}" style="background:${x}"></button>`).join('')}</div>`);
  view.appendChild(presets);
  const holder = el('<div></div>');
  view.appendChild(holder);
  const pk = Picker(holder, c, (x) => { c = x; preview(d.id, x); });
  $$('.swatch', presets).forEach((s) => (s.onclick = () => { c = hex2rgb(s.dataset.h); pk.set(c); preview(d.id, c); }));
  priceBar(view, 'Tyre smoke', d.price, () => Tune.setCart(d.id, { r: c.r, g: c.g, b: c.b }));
};

Items.neon = (view, d) => {
  let v = JSON.parse(JSON.stringify(Tune.valueOf(d.id, d.installed)));
  const car = el(`<div class="car-top"><div class="body"></div>
    <button class="side s-f" data-s="f" title="Front"></button><button class="side s-b" data-s="b" title="Rear"></button>
    <button class="side s-l" data-s="l" title="Left"></button><button class="side s-r" data-s="r" title="Right"></button></div>`);
  const all = el(`<div class="chips" style="justify-content:center;margin-bottom:12px"><button class="chip" data-all="1">All on</button><button class="chip" data-all="0">All off</button></div>`);
  const presets = el(`<div class="swatches" style="margin-bottom:12px">${d.presets.map((x) => `<button class="swatch" data-h="${x}" style="background:${x}"></button>`).join('')}</div>`);
  const holder = el('<div></div>');
  [car, all, presets, holder].forEach((x) => view.appendChild(x));
  const paint = () => {
    car.style.setProperty('--glow', rgb2hex(v.color));
    $$('.side', car).forEach((s) => s.classList.toggle('on', !!v[s.dataset.s]));
    preview(d.id, v);
  };
  const pk = Picker(holder, v.color, (c) => { v.color = c; paint(); });
  $$('.side', car).forEach((s) => (s.onclick = () => { v[s.dataset.s] = !v[s.dataset.s]; paint(); }));
  $$('[data-all]', all).forEach((b) => (b.onclick = () => { const on = b.dataset.all === '1'; v.l = v.r = v.f = v.b = on; paint(); }));
  $$('.swatch', presets).forEach((s) => (s.onclick = () => { v.color = hex2rgb(s.dataset.h); pk.set(v.color); paint(); }));
  paint();
  priceBar(view, 'Underglow', d.price, () => Tune.setCart(d.id, v));
};

Items.neonPattern = (view, d) => {
  let v = JSON.parse(JSON.stringify(Tune.valueOf(d.id, d.installed)));
  v.speed = v.speed || 5;
  const rows = el(`<div class="rows" style="margin-bottom:12px">${d.patterns.map((p) => `<button class="row" data-p="${p[0]}"><span class="ic"><i class="fa-solid fa-wave-square"></i></span><span class="tx"><b>${esc(p[1])}</b></span></button>`).join('')}</div>`);
  const sp = range({ label: 'Speed', min: 1, max: 10, step: 1, value: v.speed, onInput: (x) => { v.speed = x; preview(d.id, v); } });
  const dual = el('<div style="margin-top:12px"><span class="lbl">Second colour</span><div></div></div>');
  [rows, sp, dual].forEach((x) => view.appendChild(x));
  Picker($('div', dual), v.color2 || { r: 255, g: 255, b: 255 }, (c) => { v.color2 = c; preview(d.id, v); });
  const draw = () => { $$('.row', rows).forEach((r) => r.classList.toggle('sel', r.dataset.p === v.id)); dual.hidden = v.id !== 'dual'; };
  $$('.row', rows).forEach((r) => (r.onclick = () => { v.id = r.dataset.p; draw(); preview(d.id, v); }));
  draw();
  priceBar(view, 'Underglow mode', d.price, () => Tune.setCart(d.id, v.id === 'static' ? { id: 'static', speed: 5 } : v));
};

Items.xenonColor = (view, d) => {
  if (d.needsXenon) view.appendChild(el(`<div class="note w" style="margin-bottom:10px"><i class="fa-solid fa-lightbulb"></i><span>Xenon headlights will be fitted with this colour.</span></div>`));
  const cur = () => Tune.valueOf(d.id, d.installed);
  const name = el('<div class="swname"><b>&nbsp;</b></div>');
  const grid = swatchGrid(d.colors, (c) => cur().mode === 'index' && cur().index === c[0], (c) => d.installed.mode === 'index' && d.installed.index === c[0],
    (c) => preview(d.id, { mode: 'index', index: c[0] }), (c) => Tune.setCart(d.id, { mode: 'index', index: c[0] }), name, () => d.prices.index);
  grid.onmouseleave = () => { preview.cancel(); post('restore', { id: d.id }); };
  view.appendChild(grid);
  view.appendChild(name);
  Tune.item.refresh = () => grid.redraw();
  if (d.rgbAllowed) {
    view.appendChild(el('<div class="sect">Custom colour</div>'));
    const holder = el('<div></div>');
    view.appendChild(holder);
    const c0 = cur().mode === 'rgb' ? cur() : { r: 220, g: 235, b: 255 };
    const pk = Picker(holder, c0, (c) => preview(d.id, { mode: 'rgb', ...c }));
    priceBar(view, 'Custom headlights', d.prices.rgb, () => { const c = pk.get(); Tune.setCart(d.id, { mode: 'rgb', r: c.r, g: c.g, b: c.b }); });
  }
};

function sliderItem(view, d, label, fmt) {
  if (d.disabled) view.appendChild(el(`<div class="note w" style="margin-bottom:10px"><i class="fa-solid fa-triangle-exclamation"></i><span>${esc(d.disabled)}</span></div>`));
  let v = +Tune.valueOf(d.id, d.installed);
  const r = range({ label, min: d.slider.min, max: d.slider.max, step: d.slider.step, value: v, fmt, onInput: (x) => { v = x; preview(d.id, x); } });
  view.appendChild(el('<div class="card"></div>')).appendChild(r);
  const reset = `<button class="btn ghost" data-reset><i class="fa-solid fa-rotate-left"></i></button>`;
  const pb = priceBar(view, label, d.price, () => Tune.setCart(d.id, v), reset);
  $('[data-reset]', pb).onclick = () => { v = +d.installed; r.set(v); preview(d.id, v); };
  if (d.disabled) $('[data-apply]', pb).disabled = true;
}
Items.wheelSize = (view, d) => sliderItem(view, d, 'Rim diameter', (x) => x.toFixed(2));
Items.wheelWidth = (view, d) => sliderItem(view, d, 'Tyre width', (x) => x.toFixed(2));
Items.height = (view, d) => sliderItem(view, d, 'Ride height', (x) => (x === 0 ? 'Stock' : (x > 0 ? '-' : '+') + Math.abs(Math.round(x * 1000)) + ' mm'));

Items.stance = (view, d) => {
  const v = JSON.parse(JSON.stringify(Tune.valueOf(d.id, d.installed)));
  const mm = (x) => (x >= 0 ? '+' : '') + Math.round(x * 1000) + ' mm';
  const deg = (x) => x.toFixed(1) + '°';
  const card = el('<div class="card stack"></div>');
  const defs = [['oF', 'Front track', d.offset, mm], ['oR', 'Rear track', d.offset, mm], ['cF', 'Front camber', d.camber, deg], ['cR', 'Rear camber', d.camber, deg]];
  const ranges = defs.map(([k, label, lim, fmt]) => {
    const r = range({ label, min: lim.min, max: lim.max, step: lim.step, value: v[k] || 0, fmt, onInput: (x) => { v[k] = x; preview(d.id, v); } });
    card.appendChild(r);
    return [k, r];
  });
  view.appendChild(el('<div class="note" style="margin-bottom:10px"><i class="fa-solid fa-circle-info"></i><span>Track pushes the wheels out. Camber tilts the tops in.</span></div>'));
  view.appendChild(card);
  const pb = priceBar(view, 'Fitment', d.price, () => Tune.setCart(d.id, v), `<button class="btn ghost" data-reset><i class="fa-solid fa-rotate-left"></i></button>`);
  $('[data-reset]', pb).onclick = () => { ranges.forEach(([k, r]) => { v[k] = 0; r.set(0); }); preview(d.id, v); };
};

Items.extras = (view, d) => {
  const v = Object.assign({}, Tune.valueOf(d.id, d.installed));
  const box = el(`<div class="rows">${d.extras.map((i) => `<div class="row" data-x="${i}"><span class="ic"><i class="fa-solid fa-puzzle-piece"></i></span><span class="tx"><b>Extra ${i}</b></span><button class="sw ${v[i] ? 'on' : ''}"><i></i></button></div>`).join('')}</div>`);
  view.appendChild(box);
  $$('[data-x]', box).forEach((r) => ($('.sw', r).onclick = () => { const k = r.dataset.x; v[k] = !v[k]; $('.sw', r).classList.toggle('on', v[k]); preview(d.id, v); }));
  priceBar(view, 'Extras', d.price, () => Tune.setCart(d.id, v));
};

Items.plateText = (view, d) => {
  let v = Tune.valueOf(d.id, d.installed);
  const plate = el(`<div class="plate"><span>${esc(v)}</span></div>`);
  const inp = el(`<input class="field" maxlength="${d.max}" spellcheck="false" value="${esc(v)}">`);
  const msg = el(`<div class="hint muted" style="margin-top:8px;font-size:11px">${d.min}-${d.max} characters · letters, numbers and spaces</div>`);
  view.appendChild(plate);
  view.appendChild(inp);
  view.appendChild(msg);
  inp.oninput = () => { inp.value = inp.value.toUpperCase().replace(/[^A-Z0-9 ]/g, ''); v = inp.value; $('span', plate).textContent = v || ' '; };
  priceBar(view, 'Custom plate', d.price, () => {
    const p = v.trim();
    if (p.length < d.min || p.length > d.max || p !== v) return flash('Plates need 2-8 characters and no leading or trailing spaces.');
    Tune.setCart(d.id, p);
  });
};

['mod', 'toggle', 'customTires', 'drift', 'bulletproof', 'antilag', 'launch', 'airride', 'locator', 'rearWheels', 'plateIndex', 'tint', 'livery', 'roofLivery', 'nitrous', 'swap',
  'tyres', 'drivetrain', 'gearbox', 'ceramic', 'driftKit', 'sound', 'ecu'].forEach((k) => (Items[k] = Items.list));
['repair', 'clean', 'service'].forEach((k) => (Items[k] = Items.action));
/* ---------- quick actions ---------- */
const Quick = {
  max: async () => { const st = await post('maxPerformance'); if (st) { Tune.applyState(st); Toast.show('Best performance parts added', 'fa-gauge-high'); } },
  random: async () => { const st = await post('randomize'); if (st) { Tune.applyState(st); Toast.show('Random build loaded', 'fa-dice'); } },
  clear: async () => { const st = await post('clearCart'); if (st) { Tune.applyState(st); if (Tune.cur) { const id = Tune.cur.id; Tune.cur = null; Tune.select(id); } } },
  testdrive: async () => { const r = await post('testDrive'); if (r && r.ok === false) flash(r.error || 'Test drive unavailable.'); },
};
$$('#quick [data-q]').forEach((b) => (b.onclick = () => Quick[b.dataset.q]()));

/* ═══════════════ STATS CARD ═══════════════ */
const Stats = {
  render(st) {
    if (!st) return;
    const b = st.base, p = st.preview;
    const delta = (a, c, fmt, lowerBetter) => {
      const d = c - a;
      if (Math.abs(d) < 0.005) return '';
      const good = lowerBetter ? d < 0 : d > 0;
      return `<span class="${good ? 'teal' : 'red'}">${d > 0 ? '+' : ''}${fmt(d)}</span>`;
    };
    $('#kHp').textContent = p.hp;
    $('#kHpD').innerHTML = delta(b.hp, p.hp, (x) => Math.round(x));
    $('#k060').textContent = p.zero60.toFixed(2) + 's';
    $('#k060D').innerHTML = delta(b.zero60, p.zero60, (x) => x.toFixed(2) + 's', true);
    $('#kTop').textContent = p.top;
    $('#kTopD').innerHTML = delta(b.top, p.top, (x) => Math.round(x));
    const names = [['speed', 'Top speed'], ['accel', 'Acceleration'], ['brake', 'Braking'], ['grip', 'Grip']];
    $('#stBars').innerHTML = names.map(([k, n]) => {
      const bv = b.bars[k] * 100, pv = p.bars[k] * 100, up = pv >= bv;
      const d = pv - bv;
      return `<div class="sbar"><div class="h"><span>${n}</span><em class="${Math.abs(d) < 0.3 ? 'muted' : up ? 'teal' : 'red'}">${Math.abs(d) < 0.3 ? Math.round(pv) : (d > 0 ? '+' : '') + d.toFixed(1)}</em></div>
        <div class="t"><i class="b" style="width:${Math.min(bv, pv)}%"></i><i class="p ${up ? 'up' : 'dn'}" style="left:${Math.min(bv, pv)}%;width:${Math.abs(d)}%"></i></div></div>`;
    }).join('');
    const w = $('#stWear');
    const tags = [];
    if (st.km) tags.push(`<span class="tag"><i class="fa-solid fa-road"></i> ${Math.round(st.km).toLocaleString('en-US')} km</span>`);
    if (st.wear) Object.entries(st.wear).forEach(([k, v]) => { if (v < 100) tags.push(`<span class="tag ${v < 40 ? 'r' : v < 70 ? 'a' : ''}">${cap(k)} ${Math.round(v)}%</span>`); });
    if (p.nitrous) tags.push(`<span class="tag t"><i class="fa-solid fa-fire-flame-simple"></i> NOS ${p.nitrous}</span>`);
    w.innerHTML = tags.join('');
    w.hidden = !tags.length;
  },
};

/* ═══════════════ DRAWER: cart / builds / lab / history ═══════════════ */
const Drawer = { kind: null, pay: null, waiting: false };
Drawer.open = function (kind) {
  Drawer.kind = kind;
  const t = { cart: ['Cart', 'Review and pay'], builds: ['Builds', 'Save, load and share'], lab: ['Performance lab', 'Timed runs and leaderboards'], history: ['Service history', 'Everything done to this car'] }[kind];
  $('#dTitle').textContent = t[0];
  $('#dSub').textContent = t[1];
  $('#dClear').hidden = kind !== 'cart';
  $('#dFoot').hidden = kind !== 'cart';
  $('#drawer').classList.add('open');
  $$('#toolbar [data-t]').forEach((b) => b.classList.toggle('on', b.dataset.t === kind || (kind === 'builds' && b.dataset.t === 'save')));
  if (kind === 'cart') Drawer.render();
  else Tabs[kind]($('#dList'));
};
Drawer.close = () => {
  Drawer.kind = null;
  $('#drawer').classList.remove('open');
  $$('#toolbar [data-t]').forEach((b) => { if (b.dataset.t !== 'stats') b.classList.remove('on'); });
};
Drawer.toggle = (kind) => (Drawer.kind === kind ? Drawer.close() : Drawer.open(kind));

Drawer.primaryLabel = () => {
  const s = Tune.s;
  if (s.role === 'admin') return ['fa-bolt', 'Apply build'];
  if (s.role === 'mechanic') return ['fa-file-invoice-dollar', 'Send quote'];
  return (Tune.st.mode || s.mode) === 'order' ? ['fa-clipboard-check', 'Place order'] : ['fa-credit-card', 'Purchase & install'];
};

Drawer.render = function () {
  const s = Tune.s, st = Tune.st;
  if (!s || !st) return;
  const lines = st.lines || [];
  $('#dSub').textContent = lines.length ? `${lines.length} change${lines.length > 1 ? 's' : ''}` : 'Nothing selected yet';
  $('#dList').innerHTML = lines.length ? lines.map((l) => `
    <div class="line" data-go="${l.id}"><span class="ic"><i class="fa-solid ${l.icon}"></i></span>
      <span class="tx"><b>${esc(l.label)}</b><span>${esc(l.desc || describe(l))}</span></span>
      <span class="pr">${Tune.priceText(l.price)}</span>
      <button class="x" data-rm="${l.id}"><i class="fa-solid fa-xmark"></i></button></div>`).join('')
    : '<div class="empty"><i class="fa-solid fa-cart-shopping"></i><b>Your cart is empty</b><span>Pick parts on the left. Press Enter or click an option to add it.</span></div>';
  $$('[data-rm]', $('#dList')).forEach((b) => (b.onclick = (e) => { e.stopPropagation(); Tune.setCart(b.dataset.rm, null); }));
  $$('[data-go]', $('#dList')).forEach((b) => (b.onclick = () => Tune.select(b.dataset.go)));

  const pays = (s.payments || []).slice();
  if (s.components) pays.push('components');
  if (!Drawer.pay || !pays.includes(Drawer.pay)) Drawer.pay = pays[0];
  const payLabel = (p) => p === 'bank' ? `Bank <small class="muted">${money(s.money.bank)}</small>` : p === 'cash' ? `Cash <small class="muted">${money(s.money.cash)}</small>` : `Parts <small class="muted">${s.components.count}</small>`;
  const t = st.totals;
  const [icon, label] = Drawer.primaryLabel();
  const blocked = s.role === 'customer' && !s.canBuy;
  const mode = st.mode || s.mode;
  const foot = $('#dFoot');
  foot.innerHTML = `
    ${CFG.discounts && s.role !== 'admin' ? `<div class="hrow"><input class="field grow" id="dCode" placeholder="Discount code" value="${esc(st.code || '')}" spellcheck="false">${st.code ? `<button class="btn sm warn" id="dCodeX">Remove</button>` : `<button class="btn sm" id="dCodeOk">Apply</button>`}</div>` : ''}
    ${t ? `<div class="totals">
      <div><span>Parts</span><b>${money(t.subtotal)}</b></div>
      ${t.surcharge ? `<div class="sur"><span>Self-service (no mechanic) +${t.surcharge}%</span><b>incl.</b></div>` : ''}
      ${t.discount ? `<div class="disc"><span>Discount (${st.codePct}%)</span><b>-${money(t.discount)}</b></div>` : ''}
      ${t.labour ? `<div><span>Labour</span><b>${money(t.labour)}</b></div>` : ''}
      ${t.tax ? `<div><span>Tax</span><b>${money(t.tax)}</b></div>` : ''}
      <div class="grand"><span>Total</span><b>${s.role === 'admin' ? 'Free' : money(t.total)}</b></div></div>` : '<div class="note"><i class="fa-solid fa-circle-info"></i><span>The workshop will price this job.</span></div>'}
    ${s.role !== 'admin' && s.role !== 'mechanic' && t && t.total > 0 ? `<div class="seg" id="dPay">${pays.map((p) => `<button data-p="${p}" class="${p === Drawer.pay ? 'on' : ''}">${payLabel(p)}</button>`).join('')}</div>` : ''}
    ${blocked ? `<div class="note e"><i class="fa-solid fa-lock"></i><span>${esc(s.reason || 'You cannot buy parts for this vehicle.')}</span></div>` : ''}
    ${s.role === 'customer' && mode === 'order' ? `<div class="note"><i class="fa-solid fa-user-gear"></i><span>${s.mechanics} mechanic${s.mechanics === 1 ? '' : 's'} on duty. Your money is held until the job is done.</span></div>` : ''}
    ${s.role === 'customer' && mode === 'self' && s.partsMode === 'all' ? '<div class="note w"><i class="fa-solid fa-box-open"></i><span>Self-service uses the parts in your pockets (engine oil, tyres, kits...).</span></div>' : ''}
    <div class="hrow">
      ${CFG.testDrive && s.role === 'customer' ? `<button class="btn" id="dDrive"><i class="fa-solid fa-road"></i>Test drive</button>` : ''}
      <button class="btn pri grow" id="dGo" ${!lines.length || blocked || Drawer.waiting ? 'disabled' : ''}><i class="fa-solid ${Drawer.waiting ? 'fa-spinner fa-spin' : icon}"></i>${Drawer.waiting ? 'Waiting for customer' : label}</button>
    </div>`;

  const code = $('#dCodeOk');
  if (code) code.onclick = async () => { const r = await post('checkCode', { code: $('#dCode').value.trim() }); if (r) { Tune.applyState(r); if (!r.ok) flash(r.error || 'Invalid code.'); else Toast.show(`Code applied: ${r.codePct}% off`, 'fa-tags'); } };
  const codeX = $('#dCodeX');
  if (codeX) codeX.onclick = async () => { const r = await post('clearCode'); if (r) Tune.applyState(r); };
  $$('#dPay [data-p]').forEach((b) => (b.onclick = () => { Drawer.pay = b.dataset.p; $$('#dPay button').forEach((x) => x.classList.toggle('on', x === b)); }));
  const drive = $('#dDrive');
  if (drive) drive.onclick = Quick.testdrive;
  $('#dGo').onclick = Drawer.go;
};

Drawer.go = async function () {
  const s = Tune.s;
  if (s.role === 'mechanic') return Drawer.pickCustomer();
  const btn = $('#dGo');
  btn.disabled = true;
  const r = await post('checkout', { payment: Drawer.pay });
  if (!r || !r.ok) { btn.disabled = false; flash((r && r.error) || 'Checkout failed.'); }
};

Drawer.pickCustomer = async function () {
  const list = (await post('customers')) || [];
  Modal.show(`
    <div class="edge"><div class="shell">
      <header class="bar"><div class="ttl"><b>Send quote</b><span>Choose who pays for this build</span></div><button class="pill-close" data-close>Close</button></header>
      <div class="body scroll">${list.length ? `<div class="rows">${list.map((p) => `<button class="row" data-t="${p.id}"><span class="ic"><i class="fa-solid ${p.driver ? 'fa-car' : 'fa-user'}"></i></span><span class="tx"><b>${esc(p.name)}</b><span>${p.driver ? 'In the driver seat' : 'Nearby'}</span></span><i class="fa-solid fa-paper-plane chev"></i></button>`).join('')}</div>`
        : '<div class="empty"><i class="fa-solid fa-user-slash"></i><b>Nobody nearby</b><span>The customer must be within 15 metres.</span></div>'}</div>
    </div></div>`, 'mini', true);
  $$('#dlg [data-t]').forEach((b) => (b.onclick = async () => {
    Modal.hide(true);
    const r = await post('sendQuote', { target: +b.dataset.t });
    if (!r || !r.ok) return flash((r && r.error) || 'Could not send the quote.');
    Drawer.waiting = true;
    Drawer.render();
    Toast.show(`Quote for ${money(r.total)} sent`, 'fa-paper-plane');
  }));
};

Tune.quoteAnswer = function (a) {
  Drawer.waiting = false;
  if (Tune.s && Drawer.kind === 'cart') Drawer.render();
  if (!a.accepted) flash('The customer declined the quote.');
};
const Tabs = {};

Tabs.builds = async function (view) {
  view.innerHTML = `
    <div class="sect">Save this build</div>
    <div class="hrow"><input class="field grow" id="bName" maxlength="32" placeholder="Build name" spellcheck="false"><button class="btn pri" id="bSave" ${!(Tune.st.lines || []).length ? 'disabled' : ''}><i class="fa-solid fa-floppy-disk"></i>Save</button></div>
    <div class="sect">Load a build code</div>
    <div class="hrow"><input class="field grow" id="bCode" placeholder="NZ-XXXXXX" spellcheck="false"><button class="btn" id="bLoad"><i class="fa-solid fa-download"></i>Load</button></div>
    <div class="sect">My builds</div><div id="bList"><div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div></div>`;
  $('#bSave').onclick = async () => {
    const name = $('#bName').value.trim();
    if (!name) return flash('Give the build a name.');
    const r = await post('saveBuild', { name });
    if (!r || !r.ok) return flash((r && r.error) || 'Could not save.');
    flash(`Saved. Share code: ${r.code}`, 's');
    Tabs.builds(view);
  };
  const load = async (code) => {
    const r = await post('loadBuild', { code });
    if (!r || !r.ok) return flash((r && r.error) || 'Build not found.');
    Tune.applyState(r);
    flash(`${r.name} loaded: ${r.applied} part${r.applied === 1 ? '' : 's'}${r.skipped ? `, ${r.skipped} don't fit this car` : ''}.`, 's');
  };
  $('#bLoad').onclick = () => { const c = $('#bCode').value.trim(); if (c) load(c); };
  const list = (await post('builds')) || [];
  const box = $('#bList', view);   // scoped: the option dock has its own #bList button
  if (!box) return;
  box.innerHTML = list.length ? `<div class="rows">${list.map((b) => `
    <div class="row"><span class="ic"><i class="fa-solid fa-layer-group"></i></span><span class="tx"><b>${esc(b.name)}</b><span>${esc(b.code)} · ${b.count} parts · ${esc(b.model || 'any')} · used ${b.uses}x</span></span>
      <span class="rt"><button class="ibtn" data-l="${esc(b.code)}" title="Load"><i class="fa-solid fa-download"></i></button><button class="ibtn" data-c="${esc(b.code)}" title="Copy code"><i class="fa-regular fa-copy"></i></button><button class="ibtn" data-d="${esc(b.code)}" title="Delete"><i class="fa-solid fa-trash"></i></button></span></div>`).join('')}</div>`
    : '<div class="empty"><i class="fa-solid fa-layer-group"></i><b>No builds yet</b><span>Save a build to reuse it on this car or share the code.</span></div>';
  $$('[data-l]', box).forEach((b) => (b.onclick = () => load(b.dataset.l)));
  $$('[data-c]', box).forEach((b) => (b.onclick = () => { copyText(b.dataset.c); flash('Code copied.', 's'); }));
  $$('[data-d]', box).forEach((b) => (b.onclick = async () => { await post('deleteBuild', { code: b.dataset.d }); Tabs.builds(view); }));
};

function copyText(t) {
  const ta = document.createElement('textarea');
  ta.value = t; document.body.appendChild(ta); ta.select();
  try { document.execCommand('copy'); } catch (e) {}
  ta.remove();
}

Tabs.lab = async function (view) {
  const tests = CFG.perf.tests;
  if (!Tabs.lab.test) Tabs.lab.test = tests[0].id;
  if (!Tabs.lab.scope) Tabs.lab.scope = 'model';
  view.innerHTML = `
    <div class="sect">Run a test</div>
    <div class="rows">${tests.map((t) => `<div class="row"><span class="ic"><i class="fa-solid fa-stopwatch"></i></span><span class="tx"><b>${esc(t.label)}</b><span>${t.kind === 'brake' ? 'Reach speed, brake to a stop' : 'From a standstill'}</span></span><button class="btn sm pri" data-run="${t.id}"><i class="fa-solid fa-flag-checkered"></i>Run</button></div>`).join('')}</div>
    <div class="note" style="margin-top:8px"><i class="fa-solid fa-circle-info"></i><span>Running a test closes the menu. Unbought parts are removed first.</span></div>
    <div class="sect">Leaderboard</div>
    <div class="hrow" style="margin-bottom:8px"><select class="field grow" id="lTest">${tests.map((t) => `<option value="${t.id}" ${t.id === Tabs.lab.test ? 'selected' : ''}>${esc(t.label)}</option>`).join('')}</select>
      <div class="seg" id="lScope" style="width:190px"><button data-s="model">This car</button><button data-s="all">All cars</button></div></div>
    <div id="lBoard"></div>`;
  $$('[data-run]', view).forEach((b) => (b.onclick = () => post('perfStart', { test: b.dataset.run })));
  $('#lTest').onchange = (e) => { Tabs.lab.test = e.target.value; board(); };
  $$('#lScope button').forEach((b) => { b.classList.toggle('on', b.dataset.s === Tabs.lab.scope); b.onclick = () => { Tabs.lab.scope = b.dataset.s; $$('#lScope button').forEach((x) => x.classList.toggle('on', x === b)); board(); }; });
  const board = async () => {
    const rows = (await post('perfBoard', { test: Tabs.lab.test, scope: Tabs.lab.scope })) || [];
    const box = $('#lBoard');
    if (!box) return;
    box.innerHTML = rows.length ? `<table class="tbl"><thead><tr><th>#</th><th>Driver</th><th>Car</th><th style="text-align:right">Time</th></tr></thead><tbody>${rows.map((r, i) => `<tr><td><b class="${i < 3 ? 'teal' : ''}">${i + 1}</b></td><td>${esc(r.name)}</td><td class="dim">${esc(r.label || r.model)}</td><td style="text-align:right"><b>${(+r.t).toFixed(3)}s</b></td></tr>`).join('')}</tbody></table>`
      : '<div class="empty"><i class="fa-solid fa-trophy"></i><b>No times yet</b><span>Be the first to set one.</span></div>';
  };
  board();
};

Tabs.history = async function (view) {
  view.innerHTML = '<div class="empty"><i class="fa-solid fa-spinner fa-spin"></i></div>';
  const h = await post('history');
  if (!h || Drawer.kind !== 'history') return;
  const wear = h.wear || {};
  view.innerHTML = `
    <div class="grid2" style="margin-bottom:10px"><div class="tile"><small>Odometer</small><b>${Math.round(h.km || 0).toLocaleString('en-US')} km</b></div><div class="tile"><small>Jobs on record</small><b>${h.rows.length}</b></div></div>
    ${Object.keys(wear).length ? `<div class="card">${meter(Object.entries(wear).map(([k, v]) => [cap(k), v]))}</div>` : ''}
    <div class="sect">Service log</div>
    ${h.rows.length ? h.rows.map((r) => `<div class="card"><div class="hrow"><b class="grow" style="font-weight:500">${esc(r.shopLabel)}</b><span class="tag ${r.kind === 'order' ? 't' : ''}">${esc(r.kind)}</span><b>${money(r.total)}</b></div>
      <div class="muted" style="font-size:10.5px;margin-top:5px">${new Date(r.t * 1000).toLocaleString()}${r.mechanic_name ? ' · ' + esc(r.mechanic_name) : ''}</div>
      <div class="chips" style="margin-top:9px">${(r.items || []).map((i) => `<span class="tag">${esc(i.label)}</span>`).join('')}</div></div>`).join('')
      : '<div class="empty"><i class="fa-solid fa-clock-rotate-left"></i><b>No history</b><span>Work done on this car will show up here.</span></div>'}`;
};

function describe(l) {
  const v = l.value;
  if (v === true) return 'Install';
  if (v === false) return 'Remove';
  if (typeof v === 'number') return v === -1 ? 'Stock' : 'Option ' + (v + 1);
  if (typeof v === 'string') return v;
  if (v && v.mode === 'rgb') return rgb2hex(v).toUpperCase();
  if (v && v.mode === 'index') return 'Colour #' + v.index;
  if (v && v.type !== undefined) return v.index === -1 ? 'Stock rims' : 'Rim ' + (v.index + 1);
  return 'Custom';
}
/* ═══════════════ INPUT: camera drag, toolbar, keys ═══════════════ */
(() => {
  const drag = $('#drag');
  let down = false, lx = 0, ly = 0;
  // mouse movement is summed and sent every 30 ms so no drag distance is lost between sends
  let acc = [0, 0], timer = null;
  const flush = () => { timer = null; if (acc[0] || acc[1]) { post('camera', { dx: acc[0], dy: acc[1] }); acc = [0, 0]; } };
  drag.addEventListener('mousedown', (e) => { down = true; lx = e.clientX; ly = e.clientY; Spot.close(); });
  window.addEventListener('mouseup', () => { down = false; });
  window.addEventListener('mousemove', (e) => {
    if (!down) return;
    acc[0] += e.clientX - lx; acc[1] += e.clientY - ly;
    lx = e.clientX; ly = e.clientY;
    if (!timer) timer = setTimeout(flush, 30);
  });
  drag.addEventListener('wheel', (e) => post('camera', { zoom: e.deltaY }), { passive: true });
})();

const Hint = {
  async toggle(what, btn) {
    if (what === 'turntable') { const on = !btn.classList.contains('on'); btn.classList.toggle('on', on); return post('camera', { turntable: on }); }
    if (what === 'compare') return;
    const r = await post('toggle', { what });
    if (what !== 'rev') btn.classList.toggle('on', !!r);
  },
  compare(on) {
    if (Tune.cmp === on) return;
    Tune.cmp = on;
    $('#cmpBadge').hidden = !on;
    $('[data-h="compare"]').classList.toggle('on', on);
    if (on) $('#hotspots').innerHTML = '';
    post('compare', { on });
  },
};
$$('#hints [data-h]').forEach((b) => {
  if (b.dataset.h === 'compare') {
    b.onmousedown = () => Hint.compare(true);
    b.onmouseup = b.onmouseleave = () => Hint.compare(false);
  } else b.onclick = () => Hint.toggle(b.dataset.h, b);
});

async function undo(redo) {
  const st = await post('undo', { redo });
  if (!st) return;
  Tune.applyState(st);
  if (Tune.cur) { const id = Tune.cur.id; Tune.cur = null; Tune.select(id); }
}

const Toolbar = {
  stats: () => { $('#stats').hidden = !$('#stats').hidden; $('[data-t="stats"]').classList.toggle('on', !$('#stats').hidden); },
  search: () => (($('#spot').hidden) ? Spot.open() : Spot.close()),
  builds: () => Drawer.toggle('builds'),
  save: () => { Drawer.open('builds'); setTimeout(() => { const i = $('#bName'); if (i) i.focus(); }, 50); },
  lab: () => Drawer.toggle('lab'),
  history: () => Drawer.toggle('history'),
  undo: () => undo(false),
  redo: () => undo(true),
  cart: () => Drawer.toggle('cart'),
};
$$('#toolbar [data-t]').forEach((b) => (b.onclick = () => Toolbar[b.dataset.t]()));

const typing = () => ['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement && document.activeElement.tagName);

window.addEventListener('keydown', (e) => {
  if (!$('#modal').hidden) { if (e.key === 'Escape') Modal.hide(); return; }
  if (Tab && Tab.open) return Tab.key(e);
  if (Ed && Ed.open) { if (e.key === 'Escape' && !typing()) Ed.close(); else if (e.key === 'F2' || (e.key === 'w' && e.altKey)) { e.preventDefault(); post('ed:walk'); } return; }
  if (Remote && Remote.open) { if (e.key === 'Escape') Remote.cancel(); return; }
  if ($('#tune').hidden) return;
  if (!$('#spot').hidden) return;
  if (e.key === 'Escape') {
    if (typing()) return document.activeElement.blur();
    if (Drawer.kind) return Drawer.close();
    if (Tune.cur) return Tune.clearItem();
    return Tune.close();
  }
  if (typing()) return;
  const k = e.key.toLowerCase();
  if (k === 'f' || k === '/' || (e.ctrlKey && k === 'k')) { e.preventDefault(); return Spot.open(); }
  if (k === 'h') return Hint.compare(true);
  if (k === 't') return Hint.toggle('turntable', $('[data-h="turntable"]'));
  if (k === 'l') return Hint.toggle('lights', $('[data-h="lights"]'));
  if (k === 'o') return Hint.toggle('doors', $('[data-h="doors"]'));
  if (k === 'r') return Hint.toggle('rev', $('[data-h="rev"]'));
  if (k === 'c') return Drawer.toggle('cart');
  if (k === 'z') return undo(e.shiftKey);
  if (e.key === 'Backspace') return Tune.clearItem();
  if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { e.preventDefault(); return Tune.browse(e.key === 'ArrowRight' ? 1 : -1); }
  if (e.key === 'ArrowUp' || e.key === 'ArrowDown') { e.preventDefault(); return Rail.step(e.key === 'ArrowDown' ? 1 : -1); }
  if (k === 'q' || k === 'e') return Rail.cat(k === 'e' ? 1 : -1);
  if (e.key === 'Enter') { e.preventDefault(); return Tune.addCurrent(); }
});
window.addEventListener('keyup', (e) => { if (e.key.toLowerCase() === 'h' && !$('#tune').hidden) Hint.compare(false); });

$('#tpClose').onclick = Tune.close;
$('#dBack').onclick = Drawer.close;
$('#dClear').onclick = Quick.clear;
$('#edClose').onclick = () => {
  if (Tune.cur && Tune.cur.opts) { Tune.listOpen = false; try { localStorage.setItem('nzt_list', '0'); } catch (e) {} $('#editor').hidden = true; Tune.centre(); }
  else Tune.clearItem();
};
$('#bPrev').onclick = () => Tune.browse(-1);
$('#bNext').onclick = () => Tune.browse(1);
$('#bAdd').onclick = Tune.addCurrent;
$('#bList').onclick = () => {
  Tune.listOpen = !Tune.listOpen;
  try { localStorage.setItem('nzt_list', Tune.listOpen ? '1' : '0'); } catch (e) {}
  if (Tune.cur && Tune.cur.opts) $('#editor').hidden = !Tune.listOpen;
  Tune.centre();
};
