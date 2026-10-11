/* ════════════════════════════════════════════════════════════════════════
   NAYZEEE v5 — multicharacter NUI
   ════════════════════════════════════════════════════════════════════════ */
(() => {
'use strict';

// FiveM injects GetParentResourceName. Never define it here.
const IN_GAME = typeof window.GetParentResourceName === 'function';
const RES = IN_GAME ? window.GetParentResourceName() : 'nayzeee-multicharacter';

async function post(name, data = {}) {
  if (!IN_GAME) return window.NZM_MOCK ? window.NZM_MOCK(name, data) : true;
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
    return await r.json();
  } catch (e) { console.error('[nzm]', name, e); return false; }
}

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const root = $('#root');

// ── state ────────────────────────────────────────────────────────────────
const st = {
  cfg: null, L: {}, pending: [], view: 'closed',
  data: null, chars: [], bySlot: {}, selected: 1,
  plates: [], shots: {}, busy: false, showBulletin: true,
  settings: {}, create: null, spawn: { options: [], selected: null }, shop: { cart: {} },
  modal: null, settingsTab: 'general',
};

const T = (k, ...a) => {
  let s = st.L[k] ?? k;
  a.forEach(v => { s = s.replace(/%s/, v); });
  return s;
};

// ── formatting ───────────────────────────────────────────────────────────
const money = n => {
  const c = st.cfg?.ui?.currency || { locale: 'en-US', code: 'USD' };
  try { return new Intl.NumberFormat(c.locale, { style: 'currency', currency: c.code, maximumFractionDigits: 0 }).format(n || 0); }
  catch { return '$' + Math.round(n || 0).toLocaleString(); }
};
const pad = n => String(n).padStart(2, '0');
function parseISO(iso) {
  const m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(iso || '');
  return m ? { y: +m[1], m: +m[2], d: +m[3] } : null;
}
function fmtDate(iso) {
  const p = parseISO(iso); if (!p) return '-';
  const f = st.cfg?.ui?.dateFormat || 'MM/DD/YYYY';
  return f.replace('YYYY', p.y).replace('MM', pad(p.m)).replace('DD', pad(p.d));
}
function ageOf(y, m, d) {
  const now = new Date(); let a = now.getFullYear() - y;
  if (now.getMonth() + 1 < m || (now.getMonth() + 1 === m && now.getDate() < d)) a--;
  return a;
}
const ZOD = [['capricorn', 1, 19], ['aquarius', 2, 18], ['pisces', 3, 20], ['aries', 4, 19], ['taurus', 5, 20], ['gemini', 6, 20], ['cancer', 7, 22], ['leo', 8, 22], ['virgo', 9, 22], ['libra', 10, 22], ['scorpio', 11, 21], ['sagittarius', 12, 21], ['capricorn', 12, 31]];
function zodiac(m, d) {
  for (const [name, mm, dd] of ZOD) if (m < mm || (m === mm && d <= dd)) return T('z_' + name);
  return T('z_capricorn');
}
function height(cm) {
  if (!cm) return '-';
  const unit = st.cfg?.ui?.heightUnit || 'both';
  const inch = Math.round(cm / 2.54), ft = `${Math.floor(inch / 12)}'${inch % 12}"`;
  if (unit === 'metric') return `${cm} cm`;
  if (unit === 'imperial') return ft;
  return `${ft} <small>${cm} cm</small>`;
}
function playtime(sec) {
  sec = sec || 0;
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
  if (h >= 48) return `${Math.floor(h / 24)}d ${h % 24}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}
function ago(unix) {
  if (!unix) return T('never');
  const s = Math.max(0, Date.now() / 1000 - unix);
  if (s < 90) return T('just_now');
  if (s < 3600) return T('minutes_ago', Math.floor(s / 60));
  if (s < 86400) return T('hours_ago', Math.floor(s / 3600));
  return T('days_ago', Math.floor(s / 86400));
}
const initials = c => ((c.firstname || '?')[0] + (c.lastname || '')[0]).toUpperCase();
const fullName = c => `${c.firstname} ${c.lastname}`;
const shortId = c => String(c.id || '').includes(':') ? String(c.id).split(':')[0].toUpperCase() : c.id;

// ── sound ────────────────────────────────────────────────────────────────
let actx;
function blip(f = 720, dur = 0.045, vol = 0.035) {
  if (!st.cfg?.ui?.sounds || st.settings.sounds === false) return;
  try {
    actx = actx || new AudioContext();
    const o = actx.createOscillator(), g = actx.createGain();
    o.type = 'sine'; o.frequency.value = f;
    g.gain.setValueAtTime(vol, actx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, actx.currentTime + dur);
    o.connect(g).connect(actx.destination); o.start(); o.stop(actx.currentTime + dur);
  } catch { /* audio unavailable */ }
}

// ── theme / scale ────────────────────────────────────────────────────────
function hexRgb(h) {
  const m = /^#?([0-9a-f]{6})$/i.exec(h || ''); if (!m) return null;
  const n = parseInt(m[1], 16); return `${n >> 16 & 255},${n >> 8 & 255},${n & 255}`;
}
function applyTheme(t = {}) {
  const r = document.documentElement.style;
  if (t.accent) { r.setProperty('--teal', t.accent); const rgb = hexRgb(t.accent); if (rgb) r.setProperty('--teal-rgb', rgb); }
  if (t.accentHigh) r.setProperty('--teal-hi', t.accentHigh);
  if (t.accentLow) r.setProperty('--teal-lo', t.accentLow);
  if (t.danger) r.setProperty('--red', t.danger);
  if (t.background) r.setProperty('--base', t.background);
  if (t.panel) r.setProperty('--panel', t.panel);
}
function fit() {
  const user = (st.cfg?.ui?.scale || 1) * (st.settings.scale || 1);
  if (!IN_GAME) {
    // Browser preview: letterboxed 16:9 stage
    const s = Math.min(innerWidth / 1920, innerHeight / 1080);
    const ox = (innerWidth - 1920 * s) / 2, oy = (innerHeight - 1080 * s) / 2;
    root.style.transform = `translate(${ox}px,${oy}px) scale(${s * user})`;
    root.style.width = `${1920 / user}px`;
    root.style.height = `${1080 / user}px`;
    return;
  }
  const s = (innerHeight / 1080) * user;
  root.style.transform = `scale(${s})`;
  root.style.width = `${innerWidth / s}px`;
  root.style.height = `${innerHeight / s}px`;
}
let replateT;
addEventListener('resize', () => { fit(); clearTimeout(replateT); replateT = setTimeout(() => post('replate'), 200); });

// ── data ─────────────────────────────────────────────────────────────────
function setData(d) {
  st.data = d;
  st.chars = d.characters || [];
  st.bySlot = {};
  st.chars.forEach(c => { st.bySlot[c.slot] = c; if (c.headshot) st.shots[c.slot] = c.headshot; });
  if (d.selected) st.selected = d.selected;
  if (st.selected > d.shown) st.selected = 1;
}
const slotState = s => {
  const c = st.bySlot[s];
  if (c) return c.locked ? 'over' : (c.disabled ? 'disabled' : 'char');
  return s <= st.data.total ? 'empty' : 'locked';
};

// ── views ────────────────────────────────────────────────────────────────
function setView(v) {
  st.view = v;
  root.classList.toggle('on', v !== 'closed');
  const sel = v === 'select';
  $('#top').hidden = !(sel || v === 'create' || v === 'spawn');
  $('#dossier').classList.toggle('on', sel);
  $('#bulletin').classList.toggle('on', sel && st.showBulletin && !!st.cfg?.ui?.bulletin?.enabled);
  $('#roster').hidden = !sel;
  $('#keys').hidden = !(sel || v === 'create' || v === 'spawn');
  $('#create').classList.toggle('on', v === 'create');
  $('#spawn').classList.toggle('on', v === 'spawn');
  $('#shop').classList.toggle('on', v === 'shop');
  $('#plates').hidden = !sel;
  if (v !== 'select') closeModal();
  applyBars();
  renderKeys();
}

function renderAll() {
  renderTop(); renderDossier(); renderBulletin(); renderRoster(); renderPlates(); renderKeys();
}

// ── top bar ──────────────────────────────────────────────────────────────
const SOCIAL = { discord: 'fa-brands fa-discord', youtube: 'fa-brands fa-youtube', tiktok: 'fa-brands fa-tiktok', twitch: 'fa-brands fa-twitch', x: 'fa-brands fa-x-twitter', instagram: 'fa-brands fa-instagram', website: 'fa-solid fa-globe', rules: 'fa-solid fa-scale-balanced' };
function renderTop() {
  const ui = st.cfg.ui, d = st.data;
  const used = st.chars.length, total = d ? d.total : 0;
  const meter = d ? Array.from({ length: Math.min(total, 12) }, (_, i) => `<i class="${i < used ? 'on' : ''}"></i>`).join('') : '';
  const socials = (ui.socials || []).filter(s => s.url).map(s => `<button class="icon-btn" data-url="${esc(s.url)}" title="${esc(s.kind)}"><i class="${SOCIAL[s.kind] || 'fa-solid fa-link'}"></i></button>`).join('');
  $('#top').innerHTML = `
    <div class="brand"><div class="mark"></div><div><b>${esc(ui.title)}</b><span>${esc(ui.subtitle || '')}</span></div><span class="ver" style="margin-left:auto">v${esc(st.cfg.version)}</span></div>
    <div class="top-mid">
      ${ui.showOnline && d ? `<span style="display:flex;align-items:center;gap:9px"><span class="dot"></span>${T('online', `<b>${d.online}</b>`)}</span><span class="sep"></span>` : ''}
      ${d ? `<span style="display:flex;align-items:center;gap:10px"><span class="slotmeter">${meter}</span>${T('slots_used', `<b>${used}</b>`, `<b>${total}</b>`)}</span>` : ''}
    </div>
    <div class="top-r">
      ${ui.bulletin?.enabled ? `<button class="icon-btn ${st.showBulletin ? 'on' : ''}" data-act="bulletin" title="${T('bulletin')}"><i class="fa-solid fa-newspaper"></i></button>` : ''}
      <button class="icon-btn" data-act="settings" title="${T('settings')}"><i class="fa-solid fa-gear"></i></button>
      ${ui.credits?.enabled && ui.credits.groups?.length ? `<button class="icon-btn" data-act="credits" title="${T('credits')}"><i class="fa-solid fa-users"></i></button>` : ''}
      ${socials ? `<span class="vr"></span>${socials}` : ''}
      ${ui.store?.enabled ? `<span class="vr"></span><button class="btn btn-ghost sm" data-url="${esc(ui.store.url)}"><i class="fa-solid fa-store"></i>${esc(ui.store.label || 'Store')}</button>` : ''}
      <span class="vr"></span>
      <button class="pill-close" data-act="quit">${T('quit')}</button>
    </div>`;
}

// ── dossier ──────────────────────────────────────────────────────────────
function portrait(c, cls = '') {
  const url = st.shots[c.slot];
  return `<div class="av ${cls}">${url ? `<img src="${esc(url)}" alt="">` : `<span>${esc(initials(c))}</span>`}</div>`;
}
function kvRow(icon, label, value) { return `<span><i class="fa-solid fa-${icon}"></i>${label}</span><b>${value}</b>`; }

function renderDossier() {
  const s = st.selected, state = slotState(s), c = st.bySlot[s], F = st.cfg.fields, ui = st.cfg.ui;
  let head = '', body = '', foot = '';

  if (c) {
    const dob = parseISO(c.dob);
    const chips = [];
    if (c.favorite) chips.push(`<span class="chip gold"><i class="fa-solid fa-star"></i>${T('favorite')}</span>`);
    if (F.citizenid) chips.push(`<span class="chip mute"><i class="fa-solid fa-id-card"></i>${esc(shortId(c))}</span>`);
    if (F.job) chips.push(`<span class="chip"><i class="fa-solid fa-briefcase"></i>${esc(c.job === 'unemployed' ? T('unemployed') : c.jobLabel)}</span>`);
    if (c.disabled) chips.push(`<span class="chip red"><i class="fa-solid fa-lock"></i>${T('disabled')}</span>`);
    if (c.locked) chips.push(`<span class="chip amber"><i class="fa-solid fa-circle-exclamation"></i>${T('over_limit')}</span>`);
    if (c.createdAt && Date.now() / 1000 - c.createdAt < 86400) chips.push(`<span class="chip">${T('new')}</span>`);

    head = `<div class="who">${portrait(c, 'xl')}<div class="grow"><h1>${esc(fullName(c))}</h1><div class="meta">${chips.join('')}</div></div></div>`;

    const rows = [];
    if (F.dob && dob) rows.push(kvRow('cake-candles', T('date_of_birth'), `${fmtDate(c.dob)}${F.age ? `<small>${T('years', ageOf(dob.y, dob.m, dob.d))}</small>` : ''}`));
    if (F.zodiac && dob) rows.push(kvRow('moon', T('zodiac'), zodiac(dob.m, dob.d)));
    if (F.gender) rows.push(kvRow(c.gender === 'f' ? 'venus' : 'mars', T('gender'), c.gender === 'f' ? T('female') : T('male')));
    if (F.nationality && c.nationality) rows.push(kvRow('earth-americas', T('nationality'), esc(c.nationality)));
    if (F.height && c.height) rows.push(kvRow('ruler-vertical', T('height'), height(c.height)));
    if (F.job) rows.push(kvRow('briefcase', T('job'), `${esc(c.job === 'unemployed' ? T('unemployed') : c.jobLabel)}${c.gradeLabel && c.job !== 'unemployed' ? `<small>${esc(c.gradeLabel)}</small>` : ''}`));
    if (F.phone && c.phone) rows.push(kvRow('phone', T('phone'), esc(c.phone)));
    if (F.playtime) rows.push(kvRow('hourglass-half', T('playtime'), playtime(c.playtime)));
    if (F.lastPlayed) rows.push(kvRow('clock', T('last_played'), ago(c.lastPlayed)));
    (c.custom || []).forEach(x => rows.push(kvRow((x.icon || 'circle-info').replace(/^fa-/, ''), esc(x.label), esc(x.value))));

    const stats = (F.cash || F.bank) ? `<div class="stats">
      ${F.cash ? `<div class="stat"><div class="tile"><i class="fa-solid fa-wallet"></i></div><div><span>${T('cash')}</span><b>${money(c.cash)}</b></div></div>` : ''}
      ${F.bank ? `<div class="stat"><div class="tile"><i class="fa-solid fa-building-columns"></i></div><div><span>${T('bank')}</span><b>${money(c.bank)}</b></div></div>` : ''}
    </div>` : '';

    const partner = c.partner ? `<div class="partner"><div class="tile ${c.partner.type === 'couple' ? 'red' : ''}"><i class="fa-solid fa-${c.partner.type === 'couple' ? 'heart' : 'user-group'}"></i></div>
      <div class="grow"><b>${esc(c.partner.name)}</b><span>${T(c.partner.type === 'couple' ? 'couple' : 'friend')}</span></div>
      <button class="icon-btn danger" data-act="unpartner" title="${T('remove_partner')}"><i class="fa-solid fa-xmark"></i></button></div>` : '';

    const story = F.backstory && st.cfg.reg.backstory.enabled ? `<div class="note"><div class="grow"><div class="ttl">${T('backstory')}<button class="icon-btn" style="width:24px;height:24px;font-size:10px" data-act="backstory" title="${T('edit')}"><i class="fa-solid fa-pen"></i></button></div>${c.backstory ? esc(c.backstory) : `<span style="color:var(--ink-3)">${T('no_backstory')}</span>`}</div></div>` : '';

    if (c.disabled) body += `<div class="note red"><i class="fa-solid fa-lock" style="color:var(--red);margin-top:2px"></i><div class="grow">${T('disabled_body')}</div></div>`;
    if (c.locked) body += `<div class="note amber"><i class="fa-solid fa-circle-exclamation" style="color:var(--amber);margin-top:2px"></i><div class="grow">${T('over_limit_body')}</div></div>`;
    body += stats + `<div class="kv">${rows.join('')}</div>` + partner + story;

    const playable = !c.disabled && !c.locked;
    foot = `<button class="btn btn-teal lg full" data-act="play" ${playable ? '' : 'disabled'}><i class="fa-solid fa-play"></i>${T('play')}</button>
      <div class="row-gap">
        <button class="btn btn-ghost grow" data-act="pose"><i class="fa-solid fa-person"></i>${T('pose')}</button>
        <button class="icon-btn star ${c.favorite ? 'on' : ''}" style="height:32px;width:36px" data-act="favorite" title="${T(c.favorite ? 'unfavorite' : 'favorite')}"><i class="fa-solid fa-star"></i></button>
        ${st.data.canDelete ? `<button class="btn btn-red" data-act="delete"><i class="fa-solid fa-trash"></i>${T('delete')}</button>` : ''}
      </div>`;
  } else if (state === 'empty') {
    head = `<div class="who"><div class="av xl"><i class="fa-solid fa-user-plus ph"></i></div><div class="grow"><h1>${T('empty_slot')}</h1><div class="meta"><span class="chip mute">${T('slot', s)}</span></div></div></div>`;
    body = `<div class="empty"><div class="tile"><i class="fa-solid fa-plus"></i></div><b>${T('create_character')}</b><span>${T('empty_body', s)}</span></div>`;
    foot = `<button class="btn btn-teal lg full" data-act="create"><i class="fa-solid fa-user-plus"></i>${T('create_character')}</button>`;
  } else {
    head = `<div class="who"><div class="av xl"><i class="fa-solid fa-lock ph"></i></div><div class="grow"><h1>${T('locked_slot')}</h1><div class="meta"><span class="chip amber">${T('slot', s)}</span></div></div></div>`;
    body = `<div class="empty"><div class="tile amber"><i class="fa-solid fa-lock"></i></div><b>${T('locked_slot')}</b><span>${T('locked_body')}</span></div>`;
    foot = `${ui.store?.enabled ? `<button class="btn btn-teal lg full" data-url="${esc(ui.store.url)}"><i class="fa-solid fa-store"></i>${T('open_store')}</button>` : ''}
      ${st.data.tebex ? `<button class="btn btn-ghost full" data-act="redeem"><i class="fa-solid fa-ticket"></i>${T('redeem_code')}</button>` : ''}`;
  }

  $('#dossier').innerHTML = `<div class="frame"><div class="shell">
    <div class="p-head" style="padding:18px">${head}</div>
    <div class="p-body">${body}</div>
    <div class="p-foot">${foot}</div></div></div>`;
}

// ── bulletin ─────────────────────────────────────────────────────────────
function renderBulletin() {
  const b = st.cfg.ui.bulletin;
  if (!b?.enabled) { $('#bulletin').innerHTML = ''; return; }
  $('#bulletin').innerHTML = `<div class="frame"><div class="shell">
    <div class="p-head"><div class="tile"><i class="fa-solid fa-newspaper"></i></div><div class="grow"><h2>${T('bulletin')}</h2></div>
      <button class="icon-btn" data-act="bulletin"><i class="fa-solid fa-xmark"></i></button></div>
    <div class="p-body">${(b.items || []).map(i => `<div class="bul"><div class="t"><span class="tag live">${esc(i.tag || '')}</span><small>${esc(i.date ? fmtDate(i.date) : '')}</small></div><b>${esc(i.title)}</b><p>${esc(i.body)}</p></div>`).join('')}</div>
  </div></div>`;
}

// ── roster ───────────────────────────────────────────────────────────────
function card(s) {
  const state = slotState(s), c = st.bySlot[s], on = s === st.selected ? 'on' : '';
  if (c) {
    return `<button class="scard ${on} ${state !== 'char' ? 'dim' : ''}" data-slot="${s}">
      <span class="num">${pad(s)}</span>
      <div class="hd">${portrait(c)}<div><b>${esc(fullName(c))}</b><span>${esc(c.job === 'unemployed' ? T('unemployed') : c.jobLabel)}</span></div></div>
      <div class="ft"><span>${c.favorite ? '<i class="fa-solid fa-star fav"></i> ' : ''}${playtime(c.playtime)}</span>
        <span>${state === 'disabled' ? `<span class="chip red">${T('disabled')}</span>` : state === 'over' ? `<span class="chip amber"><i class="fa-solid fa-lock"></i></span>` : ago(c.lastPlayed)}</span></div>
    </button>`;
  }
  if (state === 'empty') return `<button class="scard empty-s ${on}" data-slot="${s}"><span class="num">${pad(s)}</span><div class="tile"><i class="fa-solid fa-plus"></i></div><b>${T('create_character')}</b></button>`;
  return `<button class="scard lock ${on}" data-slot="${s}"><span class="num">${pad(s)}</span><div class="tile amber"><i class="fa-solid fa-lock"></i></div><b>${T('locked_slot')}</b></button>`;
}
function renderRoster() {
  if (!st.data) return;
  const cards = Array.from({ length: st.data.shown }, (_, i) => card(i + 1)).join('');
  const arrows = st.data.shown > 7;
  $('#roster').innerHTML = `${arrows ? '<button class="nav-arrow" data-act="prev"><i class="fa-solid fa-chevron-left"></i></button>' : ''}
    <div class="track">${cards}</div>
    ${arrows ? '<button class="nav-arrow" data-act="next"><i class="fa-solid fa-chevron-right"></i></button>' : ''}`;
  const on = $('.scard.on', $('#roster'));
  if (on) on.scrollIntoView({ block: 'nearest', inline: 'center' });
}

function renderKeys() {
  const k = (key, label) => `<span><span class="key">${key}</span>${label}</span>`;
  let html = '';
  if (st.view === 'select') html = k('&larr; &rarr;', T('key_navigate')) + k('Enter', T('key_play')) + (st.data?.canDelete ? k('Del', T('key_delete')) : '') + k('Esc', T('key_overview'));
  else if (st.view === 'create') html = k('Esc', T('key_back'));
  else if (st.view === 'spawn') html = k('&uarr; &darr;', T('key_navigate')) + k('Enter', T('spawn'));
  $('#keys').innerHTML = html;
}

// ── nameplates ───────────────────────────────────────────────────────────
function renderPlates() {
  const html = (st.plates || []).filter(p => p.visible).map(p => {
    const c = st.bySlot[p.slot], state = slotState(p.slot);
    let cls = p.slot === st.selected ? 'on' : '', inner;
    if (c) inner = `<i class="fa-solid ${c.favorite ? 'fa-star' : 'fa-user'}"></i>${esc(fullName(c))}<small>${esc(c.job === 'unemployed' ? T('unemployed') : c.jobLabel)}</small>`;
    else if (state === 'empty') { cls += ' ghost'; inner = `<i class="fa-solid fa-plus"></i>${T('create_character')}`; }
    else { cls += ' locked'; inner = `<i class="fa-solid fa-lock"></i>${T('locked_slot')}`; }
    return `<div class="plate ${cls}" data-slot="${p.slot}" style="left:${(p.x * 100).toFixed(3)}%;top:${(p.y * 100).toFixed(3)}%"><div class="lbl">${inner}</div></div>`;
  }).join('');
  $('#plates').innerHTML = html;
}

// ── selection actions ────────────────────────────────────────────────────
function select(slot, focus = true) {
  if (!st.data || slot < 1 || slot > st.data.shown) return;
  if (slot !== st.selected) blip(680);
  st.selected = slot;
  renderDossier(); renderRoster(); renderPlates();
  post('select', { slot, focus });
}
function primary() {
  const s = st.selected, state = slotState(s);
  if (state === 'char') { blip(880, .07); post('play', { slot: s }); }
  else if (state === 'empty') startCreate(s);
}

// ── create ───────────────────────────────────────────────────────────────
function startCreate(slot) {
  post('createStart', { slot }).then(ok => {
    if (!ok) return;
    const R = st.cfg.reg;
    st.create = { slot, firstname: '', lastname: '', d: '', m: '', y: '', gender: R.genders[0] || 'm', height: R.height.default,
      nationality: R.nationality.enabled ? '' : null, backstory: '', touched: {}, server: {}, sending: false };
    renderCreate();
    setView('create');
  });
}

const NAME_RX = /^[A-Za-z][A-Za-z' -]*$/;
function checkName(v) {
  const R = st.cfg.reg; v = v.trim();
  if (!v) return T('v_required');
  if (v.length < R.nameMin) return T('v_min', R.nameMin);
  if (v.length > R.nameMax) return T('v_max', R.nameMax);
  if (!NAME_RX.test(v)) return T('v_letters');
  const low = v.toLowerCase().replace(/[^a-z]/g, '');
  if ((R.blacklist || []).some(w => low.includes(w.toLowerCase()))) return T('v_blacklist');
  return null;
}
function checkDob(c) {
  const R = st.cfg.reg, y = +c.y, m = +c.m, d = +c.d;
  if (!y || !m || !d || m < 1 || m > 12 || y < 1900 || String(c.y).length !== 4) return T('v_date');
  const days = new Date(y, m, 0).getDate();
  if (d > days) return T('v_date');
  const a = ageOf(y, m, d);
  if (a < R.minAge) return T('v_age_min', R.minAge);
  if (a > R.maxAge) return T('v_age_max', R.maxAge);
  return null;
}
function createErrors() {
  const c = st.create, R = st.cfg.reg, e = {};
  e.firstname = checkName(c.firstname);
  e.lastname = checkName(c.lastname);
  e.dob = checkDob(c);
  if (R.height.enabled && (c.height < R.height.min || c.height > R.height.max)) e.height = T('v_height', R.height.min, R.height.max);
  if (R.nationality.enabled && R.nationality.required && !c.nationality) e.nationality = T('v_nationality');
  if (R.backstory.enabled) {
    const b = c.backstory.trim();
    if (!b && R.backstory.required) e.backstory = T('v_required');
    else if (b && b.length < R.backstory.min) e.backstory = T('v_min', R.backstory.min);
    else if (b.length > R.backstory.max) e.backstory = T('v_max', R.backstory.max);
  }
  Object.keys(c.server).forEach(k => { if (c.server[k]) e[k] = c.server[k]; });
  Object.keys(e).forEach(k => { if (!e[k]) delete e[k]; });
  return e;
}

function natDropdown(value) {
  return `<div class="dd" id="nat"><button class="dd-btn ${value ? '' : 'ph'}" data-act="dd">${esc(value || T('select_nationality'))}</button>
    <div class="dd-pop"><input class="input" id="nat-q" placeholder="${T('search')}" autocomplete="off"><div class="dd-list" id="nat-list"></div></div></div>`;
}
function natList(q = '') {
  const list = st.cfg.nationalities.filter(n => n.toLowerCase().includes(q.toLowerCase()));
  $('#nat-list').innerHTML = list.length ? list.map((n, i) => `<button data-nat="${esc(n)}" class="${n === st.create.nationality ? 'on' : ''} ${i === 0 ? 'hl' : ''}">${esc(n)}</button>`).join('') : `<div class="none">${T('no_matches')}</div>`;
}

function renderCreate() {
  const c = st.create, R = st.cfg.reg;
  const g = (id, icon, label) => `<button class="gcard ${c.gender === id ? 'on' : ''}" data-gender="${id}"><div class="tile"><i class="fa-solid fa-${icon}"></i></div><b>${label}</b></button>`;
  $('#create').innerHTML = `<div class="frame"><div class="shell">
    <div class="p-head"><div class="tile"><i class="fa-solid fa-user-plus"></i></div><div class="grow"><h2>${T('create_title')}</h2><p>${T('create_sub', c.slot)}</p></div></div>
    <div class="p-body">
      <div class="grid2">
        <div class="field" data-f="firstname"><label>${T('first_name')}<em></em></label><input id="c-first" maxlength="${R.nameMax}" placeholder="John" autocomplete="off" spellcheck="false"></div>
        <div class="field" data-f="lastname"><label>${T('last_name')}<em></em></label><input id="c-last" maxlength="${R.nameMax}" placeholder="Doe" autocomplete="off" spellcheck="false"></div>
      </div>
      <div class="field" data-f="dob"><label>${T('dob')}<em></em></label>
        <div class="dob"><input id="c-d" inputmode="numeric" maxlength="2" placeholder="${T('day')}"><input id="c-m" inputmode="numeric" maxlength="2" placeholder="${T('month')}"><input id="c-y" inputmode="numeric" maxlength="4" placeholder="${T('year')}"></div>
        <div class="dobinfo" id="dobinfo"></div>
      </div>
      <div class="field" data-f="gender"><label>${T('gender')}<em></em></label><div class="gcards">${R.genders.includes('m') ? g('m', 'mars', T('male')) : ''}${R.genders.includes('f') ? g('f', 'venus', T('female')) : ''}</div></div>
      ${R.height.enabled ? `<div class="field" data-f="height"><label>${T('height')}<em></em></label><div class="range"><input type="range" id="c-h" min="${R.height.min}" max="${R.height.max}" value="${c.height}"><b id="c-hv"></b></div></div>` : ''}
      ${R.nationality.enabled ? `<div class="field" data-f="nationality"><label>${T('nationality')}<em></em></label>${natDropdown(c.nationality)}</div>` : ''}
      ${R.backstory.enabled ? `<div class="field" data-f="backstory"><label>${T('backstory')}${R.backstory.required ? '' : ` <span style="margin-right:auto;opacity:.7">&nbsp;· ${T('optional')}</span>`}<em></em></label><textarea id="c-story" maxlength="${R.backstory.max}" placeholder="${T('backstory_hint')}"></textarea><div class="count" id="c-count"></div></div>` : ''}
    </div>
    <div class="p-foot"><div class="row-gap"><button class="btn btn-line" data-act="createBack"><i class="fa-solid fa-arrow-left"></i>${T('back')}</button>
      <button class="btn btn-teal lg grow" id="c-submit" data-act="createSubmit"><i class="fa-solid fa-check"></i>${T('create')}</button></div></div>
  </div></div>`;
  updateCreate();
  setTimeout(() => $('#c-first')?.focus(), 60);
}

function updateCreate() {
  const c = st.create; if (!c) return;
  const e = createErrors(), R = st.cfg.reg;
  $$('#create .field[data-f]').forEach(f => {
    const k = f.dataset.f, em = $('label em', f), err = e[k], show = c.touched[k] || c.server[k];
    f.classList.toggle('bad', !!(err && show));
    if (em) { em.textContent = err && show ? err : (show && !err ? T('v_ok') : ''); em.className = err && show ? 'bad' : (show ? 'ok' : ''); }
  });
  const info = $('#dobinfo');
  if (info) {
    const y = +c.y, m = +c.m, d = +c.d;
    info.innerHTML = !e.dob ? `<span class="chip mute">${T('years', ageOf(y, m, d))}</span><span class="chip">${zodiac(m, d)}</span>` : '';
  }
  const hv = $('#c-hv'); if (hv) hv.innerHTML = height(c.height);
  const cnt = $('#c-count'); if (cnt) cnt.textContent = `${c.backstory.trim().length} / ${R.backstory.max}`;
  const btn = $('#c-submit');
  if (btn) { btn.disabled = c.sending || Object.keys(e).length > 0; btn.innerHTML = c.sending ? `<span class="spinner"></span>${T('creating')}` : `<i class="fa-solid fa-check"></i>${T('create')}`; }
}

async function submitCreate() {
  const c = st.create;
  ['firstname', 'lastname', 'dob', 'height', 'nationality', 'backstory'].forEach(k => { c.touched[k] = true; });
  c.server = {};
  if (Object.keys(createErrors()).length) return updateCreate();
  c.sending = true; updateCreate();
  const res = await post('createSubmit', { form: {
    firstname: c.firstname, lastname: c.lastname, dobD: +c.d, dobM: +c.m, dobY: +c.y,
    height: c.height, nationality: c.nationality, backstory: c.backstory,
  } });
  c.sending = false;
  if (res && res.ok) { blip(990, .09); return; }
  c.server = (res && res.errors) || {};
  updateCreate();
  if (res && res.msg) toast(res.msg, 'error');
}

// ── spawn ────────────────────────────────────────────────────────────────
function renderSpawn() {
  const sp = st.spawn;
  $('#spawn').innerHTML = `<div class="frame"><div class="shell">
    <div class="p-head"><div class="tile"><i class="fa-solid fa-location-dot"></i></div><div class="grow"><h2>${T('spawn_title')}</h2><p>${T('spawn_sub')}</p></div></div>
    <div class="p-body">${sp.options.map(o => `<button class="srow ${o.id === sp.selected ? 'on' : ''}" data-spawn="${esc(o.id)}">
      <div class="tile ${o.kind === 'house' ? 'amber' : ''}"><i class="fa-solid fa-${esc((o.icon || 'location-dot').replace(/^fa-/, ''))}"></i></div>
      <div class="grow"><b>${esc(o.label)}</b><span>${esc(o.desc || '')}</span></div>
      ${o.kind === 'last' ? `<span class="tag live">${T('last_location')}</span>` : o.kind === 'house' ? `<span class="tag warn"><i class="fa-solid fa-house"></i></span>` : ''}
    </button>`).join('')}</div>
    <div class="p-foot"><button class="btn btn-teal lg full" data-act="spawnGo" ${st.busy ? 'disabled' : ''}>${st.busy ? `<span class="spinner"></span>${T('spawning')}` : `<i class="fa-solid fa-location-arrow"></i>${T('spawn')}`}</button></div>
  </div></div>`;
}
let hoverT;
function spawnPick(id, immediate) {
  if (st.spawn.selected === id) return;
  st.spawn.selected = id; renderSpawn(); blip(620);
  clearTimeout(hoverT);
  hoverT = setTimeout(() => post('spawnHover', { id }), immediate ? 0 : 140);
}
async function spawnGo() {
  if (st.busy || !st.spawn.selected) return;
  st.busy = true; renderSpawn(); blip(990, .09);
  const ok = await post('spawnConfirm', { id: st.spawn.selected });
  if (!ok) { st.busy = false; renderSpawn(); toast(T('t_error'), 'error'); }
}

// ── starter shop ─────────────────────────────────────────────────────────
function shopTotal() {
  return st.cfg.shop.items.reduce((sum, it) => sum + (st.shop.cart[it.key] || 0) * it.price, 0);
}
function renderShop() {
  const shop = st.cfg.shop, total = shopTotal(), left = shop.budget - total, pct = Math.min(100, total / shop.budget * 100);
  const cards = shop.items.map(it => {
    const q = st.shop.cart[it.key] || 0, canAdd = q < it.max && it.price <= left;
    return `<div class="icard ${q ? 'on' : ''}">
      <div class="img">${it.image ? `<img src="${esc(it.image)}" onerror="this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid fa-box'}))">` : `<i class="fa-solid fa-${it.type === 'vehicle' ? 'car' : 'box'}"></i>`}
        <span class="chip ${it.type === 'vehicle' ? 'amber' : 'mute'}">${T(it.type === 'vehicle' ? 'vehicle' : 'item')}</span></div>
      <div class="bd"><div class="t"><b>${esc(it.label)}</b><span class="price">${money(it.price)}</span></div>
        <div class="step"><button data-q="-1" data-k="${esc(it.key)}" ${q ? '' : 'disabled'}><i class="fa-solid fa-minus"></i></button><span>${q}</span><button data-q="1" data-k="${esc(it.key)}" ${canAdd ? '' : 'disabled'}><i class="fa-solid fa-plus"></i></button><small>${T('max_qty', it.max)}</small></div></div>
    </div>`;
  }).join('');
  const lines = shop.items.filter(it => st.shop.cart[it.key]).map(it => `<div class="cline"><span>${st.shop.cart[it.key]}x ${esc(it.label)}</span><b>${money(st.shop.cart[it.key] * it.price)}</b></div>`).join('');
  $('#shop').innerHTML = `<div class="frame win"><div class="shell">
    <div class="p-head"><div class="tile"><i class="fa-solid fa-cart-shopping"></i></div><div class="grow"><h2>${T('shop_title')}</h2><p>${T('shop_sub')}</p></div><span class="ver">v${esc(st.cfg.version)}</span></div>
    <div class="shop-body"><div class="shop-grid">${cards}</div>
      <div class="cart">
        <div class="budget"><div><span>${T('remaining')}</span><b>${money(left)}</b></div><span>${T('budget')} ${money(shop.budget)}</span></div>
        <div class="meter ${left < 0 ? 'over' : ''}"><i style="width:${pct}%"></i></div>
        <div class="sect">${T('cart')}</div>
        <div class="cart-list">${lines || `<div class="hint">${T('cart_empty')}</div>`}</div>
        <div class="budget"><span>${T('total')}</span><b style="font-size:17px">${money(total)}</b></div>
        <div class="row-gap"><button class="btn btn-line" data-act="shopSkip">${T('skip')}</button><button class="btn btn-teal grow" data-act="shopBuy" ${left < 0 || st.busy ? 'disabled' : ''}>${st.busy ? '<span class="spinner"></span>' : '<i class="fa-solid fa-check"></i>'}${T('confirm_purchase')}</button></div>
      </div></div>
  </div></div>`;
}

// ── modals ───────────────────────────────────────────────────────────────
function openModal(html, cls = '') {
  st.modal = true;
  $('#modal').innerHTML = `<div class="overlay" data-act="modalBg"><div class="modal ${cls}">${html}</div></div>`;
  blip(560);
}
function closeModal() { st.modal = null; $('#modal').innerHTML = ''; }

function modalDelete() {
  const c = st.bySlot[st.selected]; if (!c) return;
  const name = fullName(c), need = st.cfg.typeToConfirm;
  openModal(`<div class="modal-h"><div class="tile red"><i class="fa-solid fa-trash"></i></div><div class="grow"><h4>${T('delete_title')}</h4><p>${esc(name)}</p></div></div>
    <div class="modal-body"><p>${T('delete_body', `<b>${esc(name)}</b>`)}</p>
      ${need ? `<div class="field"><label class="plain">${T('delete_type', `<b style="color:var(--white)">${esc(name)}</b>`)}</label><input id="del-in" autocomplete="off" spellcheck="false"></div>` : ''}</div>
    <div class="modal-f"><button class="btn btn-line" data-act="modalClose">${T('cancel')}</button><button class="btn btn-red" id="del-go" data-act="deleteGo" ${need ? 'disabled' : ''}><i class="fa-solid fa-trash"></i>${T('delete_confirm')}</button></div>`, 'danger');
  const inp = $('#del-in');
  if (inp) {
    inp.focus();
    inp.addEventListener('input', () => { $('#del-go').disabled = inp.value.trim().toLowerCase() !== name.toLowerCase(); });
  }
}
async function deleteGo() {
  const c = st.bySlot[st.selected]; if (!c) return;
  const btn = $('#del-go'); btn.disabled = true; btn.innerHTML = '<span class="spinner"></span>';
  const res = await post('delete', { slot: c.slot, confirm: $('#del-in')?.value || '' });
  closeModal();
  toast(res?.msg || T('t_error'), res?.ok ? 'success' : 'error');
}

function modalPose() {
  const c = st.bySlot[st.selected]; if (!c) return;
  st.poseTemp = c.pose || null;
  const draw = () => $('#pose-grid').innerHTML = st.cfg.poses.map(p => `<button class="opt ${st.poseTemp === p.id ? 'on' : ''}" data-pose="${esc(p.id)}">${esc(p.label)}</button>`).join('');
  openModal(`<div class="modal-h"><div class="tile"><i class="fa-solid fa-person"></i></div><div class="grow"><h4>${T('pose_title')}</h4><p>${T('pose_sub')}</p></div></div>
    <div class="modal-body"><div class="poses" id="pose-grid"></div></div>
    <div class="modal-f"><button class="btn btn-line" data-act="poseCancel">${T('cancel')}</button><button class="btn btn-teal" data-act="poseSave">${T('save')}</button></div>`, 'wide');
  st.drawPoses = draw; draw();
}

function modalBackstory() {
  const c = st.bySlot[st.selected]; if (!c) return;
  const max = st.cfg.reg.backstory.max;
  openModal(`<div class="modal-h"><div class="tile"><i class="fa-solid fa-feather"></i></div><div class="grow"><h4>${T('backstory_title')}</h4><p>${esc(fullName(c))}</p></div></div>
    <div class="modal-body"><div class="field"><textarea id="bs-in" maxlength="${max}" style="min-height:160px" placeholder="${T('backstory_hint')}">${esc(c.backstory || '')}</textarea><div class="count" id="bs-c"></div></div></div>
    <div class="modal-f"><button class="btn btn-line" data-act="modalClose">${T('cancel')}</button><button class="btn btn-teal" data-act="backstorySave">${T('save')}</button></div>`, 'wide');
  const t = $('#bs-in'), cnt = () => { $('#bs-c').textContent = `${t.value.trim().length} / ${max}`; };
  t.addEventListener('input', cnt); cnt(); t.focus();
}

function modalCredits() {
  const g = st.cfg.ui.credits.groups || [];
  openModal(`<div class="modal-h"><div class="tile"><i class="fa-solid fa-users"></i></div><div class="grow"><h4>${T('credits')}</h4></div><button class="icon-btn" data-act="modalClose"><i class="fa-solid fa-xmark"></i></button></div>
    <div class="modal-body">${g.map(x => `<div class="sect">${esc(x.title)}</div><div class="people">${(x.people || []).map(p => `<div class="person"><div class="av">${p.image ? `<img src="${esc(p.image)}">` : esc((p.name || '?')[0])}</div><div><b>${esc(p.name)}</b><span>${esc(p.role || '')}</span></div></div>`).join('')}</div>`).join('')}</div>`, 'wide');
}

function modalQuit() {
  openModal(`<div class="modal-h"><div class="tile red"><i class="fa-solid fa-right-from-bracket"></i></div><div class="grow"><h4>${T('quit_confirm')}</h4></div></div>
    <div class="modal-body"><p>${T('quit_body')}</p></div>
    <div class="modal-f"><button class="btn btn-line" data-act="modalClose">${T('cancel')}</button><button class="btn btn-red" data-act="quitGo">${T('quit')}</button></div>`, 'danger');
}

// settings
const TABS = [['general', 'sliders', 's_general'], ['camera', 'camera', 's_camera'], ['world', 'cloud-sun', 's_world'], ['audio', 'music', 's_audio'], ['account', 'id-card', 's_account']];
function swLine(key, title, desc) {
  return `<button class="sw-line" data-set="${key}"><div><b>${title}</b><span>${desc}</span></div><span class="sw ${st.settings[key] ? 'on' : ''}"><i></i></span></button>`;
}
function settingsPane() {
  const s = st.settings, cfg = st.cfg;
  switch (st.settingsTab) {
    case 'general': return `${swLine('fps', T('s_fps'), T('s_fps_d'))}${swLine('bars', T('s_bars'), T('s_bars_d'))}${cfg.ui.sounds ? swLine('sounds', T('s_sounds'), T('s_sounds_d')) : ''}
      <h5>${T('s_scale')}</h5><div class="seg">${[0.85, 0.9, 1, 1.1].map(v => `<button class="${s.scale === v ? 'on' : ''}" data-scale="${v}">${Math.round(v * 100)}%</button>`).join('')}</div>`;
    case 'camera': return `<h5>${T('s_distance')}</h5><div class="seg">${['close', 'normal', 'far'].map(v => `<button class="${s.distance === v ? 'on' : ''}" data-dist="${v}">${T('s_' + v)}</button>`).join('')}</div>`;
    case 'world': {
      const times = [[-1, T('s_auto')], [8, '08:00'], [12, '12:00'], [18, '18:00'], [21, '21:00'], [0, '00:00']];
      return `${cfg.scenePick ? `<h5>${T('s_scene')}</h5><div class="opts"><button class="opt ${s.scene === 'auto' ? 'on' : ''}" data-scene="auto">${T('s_auto')}</button>${cfg.scenes.map(x => `<button class="opt ${s.scene === x.id ? 'on' : ''}" data-scene="${esc(x.id)}">${esc(x.label)}</button>`).join('')}</div>` : ''}
        <h5>${T('s_filter')}</h5><div class="opts">${cfg.filters.map(f => `<button class="opt ${s.filter === f.id ? 'on' : ''}" data-filter="${esc(f.id)}">${esc(f.label)}</button>`).join('')}</div>
        <h5>${T('s_weather')}</h5><div class="opts"><button class="opt ${s.weather === 'auto' ? 'on' : ''}" data-weather="auto">${T('s_auto')}</button>${cfg.weathers.map(w => `<button class="opt ${s.weather === w ? 'on' : ''}" data-weather="${w}">${w.charAt(0) + w.slice(1).toLowerCase()}</button>`).join('')}</div>
        <h5>${T('s_time')}</h5><div class="seg">${times.map(([h, l]) => `<button class="${s.hour === h ? 'on' : ''}" data-hour="${h}">${l}</button>`).join('')}</div>`;
    }
    case 'audio': return `<button class="sw-line" data-set="music.enabled"><div><b>${T('s_music')}</b><span>${T('s_music_d')}</span></div><span class="sw ${s.music.enabled ? 'on' : ''}"><i></i></span></button>
      <h5>${T('s_volume')}</h5><div class="range"><input type="range" min="0" max="100" value="${Math.round(s.music.volume * 100)}" id="vol"><b id="vol-v">${Math.round(s.music.volume * 100)}%</b></div>
      <h5>${T('s_source')}</h5><div class="field"><input id="music-url" value="${esc(s.music.url)}" placeholder="${esc(cfg.music.url || 'https://')}"><span class="hint">${T('s_source_d')}</span></div>`;
    case 'account': {
      const sl = st.data?.slots || {};
      return `<div class="stats"><div class="stat"><div class="tile"><i class="fa-solid fa-users"></i></div><div><span>${T('s_slots')}</span><b>${sl.total ?? '-'} <small style="font-size:11px;color:var(--ink-3)">/ ${sl.max ?? '-'}</small></b></div></div>
        <div class="stat"><div class="tile amber"><i class="fa-solid fa-crown"></i></div><div><span>${esc(sl.source || 'default')}</span><b>${sl.base ?? '-'} + ${sl.extra ?? 0}</b></div></div></div>
        <p class="hint">${T('s_slots_d', sl.total ?? '-')}</p>
        ${st.data?.tebex ? `<h5>${T('s_redeem')}</h5><div class="field"><div class="row-gap"><input class="input grow" id="redeem-in" placeholder="tbx-xxxxxxxxxxxxx-xxxxxx"><button class="btn btn-teal" data-act="redeemGo">${T('s_redeem_btn')}</button></div><span class="hint">${T('s_redeem_d')}</span></div>` : ''}`;
    }
  }
  return '';
}
function modalSettings(tab) {
  if (tab) st.settingsTab = tab;
  openModal(`<div class="modal-h"><div class="tile"><i class="fa-solid fa-gear"></i></div><div class="grow"><h4>${T('settings')}</h4></div><span class="ver">v${esc(st.cfg.version)}</span></div>
    <div class="settings"><nav class="snav">${TABS.map(([id, icon, k]) => `<button class="${st.settingsTab === id ? 'on' : ''}" data-tab="${id}"><i class="fa-solid fa-${icon}"></i>${T(k)}</button>`).join('')}</nav>
      <div class="spane" id="spane">${settingsPane()}</div></div>
    <div class="modal-f"><button class="btn btn-line sp" data-act="settingsReset"><i class="fa-solid fa-rotate-left"></i>${T('s_reset')}</button><button class="btn btn-teal" data-act="modalClose">${T('close')}</button></div>`, 'xwide');
  bindSettingsInputs();
}
function redrawSettings() { const p = $('#spane'); if (!p) return; p.innerHTML = settingsPane(); $$('.snav button').forEach(b => b.classList.toggle('on', b.dataset.tab === st.settingsTab)); bindSettingsInputs(); }
function bindSettingsInputs() {
  const vol = $('#vol');
  if (vol) vol.addEventListener('input', () => { st.settings.music.volume = vol.value / 100; $('#vol-v').textContent = vol.value + '%'; music.volume(); saveSettings(); });
  const url = $('#music-url');
  if (url) url.addEventListener('change', () => { st.settings.music.url = url.value.trim(); music.start(true); saveSettings(); });
}
let saveT;
function saveSettings(now) {
  clearTimeout(saveT);
  const go = async () => { const r = await post('settings', { settings: st.settings }); if (r && typeof r === 'object') st.settings = r; };
  if (now) go(); else saveT = setTimeout(go, 250);
}
// Letterbox bars only while our own cameras are on screen (never over the editor, shop or the game)
function applyBars() {
  const cine = st.view === 'select' || st.view === 'create' || st.view === 'spawn';
  $('#bars').classList.toggle('on', !!st.settings?.bars && cine);
}
function applyLocalSettings() {
  applyBars();
  fit();
}

// ── toast / busy / welcome ───────────────────────────────────────────────
function toast(text, type = 'success') {
  if (!text) return;
  const el = document.createElement('div');
  el.className = `toast ${type === 'error' ? 'error' : ''}`;
  el.innerHTML = `<i class="fa-solid fa-${type === 'error' ? 'circle-exclamation' : 'check'}"></i><span>${esc(text)}</span>`;
  $('#toasts').appendChild(el);
  if (type === 'error') blip(260, .12, .04);
  setTimeout(() => el.remove(), 3600);
}
function setBusy(on, text) {
  st.busy = !!on;
  $('#busy').classList.toggle('on', !!on && st.view === 'select');
  $('#busy b').textContent = text || T('loading');
  if (st.view === 'select') {
    const b = $('#dossier [data-act="play"]');
    if (b) { b.disabled = !!on; b.innerHTML = on ? `<span class="spinner"></span>${T('loading')}` : `<i class="fa-solid fa-play"></i>${T('play')}`; }
  }
}

// ── music ────────────────────────────────────────────────────────────────
const music = {
  el: null, yt: false,
  src() { const cfg = st.cfg.music || {}; return (st.settings.music?.url || cfg.url || '').trim(); },
  ytId(u) { const m = /(?:youtu\.be\/|v=|embed\/|shorts\/)([\w-]{11})/.exec(u); return m && m[1]; },
  start(force) {
    const cfg = st.cfg.music || {};
    if (!cfg.enabled || !st.settings.music?.enabled || !this.src()) return this.stop();
    if (this.el && !force) return;
    this.stop();
    const url = this.src(), id = this.ytId(url), box = $('#music');
    if (id) {
      this.yt = true;
      box.innerHTML = `<iframe id="yt" allow="autoplay" src="https://www.youtube.com/embed/${id}?autoplay=1&loop=1&playlist=${id}&controls=0&enablejsapi=1"></iframe>`;
      this.el = $('#yt');
      this.el.addEventListener('load', () => setTimeout(() => this.volume(), 800));
    } else {
      this.yt = false;
      const a = new Audio(url); a.loop = true; this.el = a; this.volume();
      a.play().catch(() => {});
    }
  },
  volume() {
    const v = st.settings.music?.volume ?? 0.15;
    if (!this.el) return;
    if (this.yt) this.el.contentWindow?.postMessage(JSON.stringify({ event: 'command', func: 'setVolume', args: [Math.round(v * 100)] }), '*');
    else this.el.volume = v;
  },
  stop() {
    if (!this.el) return;
    if (this.yt) $('#music').innerHTML = ''; else { this.el.pause(); this.el.src = ''; }
    this.el = null;
  },
};

// ── events (delegated) ───────────────────────────────────────────────────
document.addEventListener('click', e => {
  const t = e.target.closest('[data-act],[data-slot],[data-url],[data-spawn],[data-gender],[data-nat],[data-q],[data-pose],[data-tab],[data-set],[data-scale],[data-dist],[data-scene],[data-filter],[data-weather],[data-hour]');
  if (!$('#nat')?.contains(e.target)) $('#nat')?.classList.remove('open');
  if (!t) return;
  const d = t.dataset;

  if (d.url) { if (IN_GAME && window.invokeNative) window.invokeNative('openUrl', d.url); else window.open(d.url, '_blank'); return; }
  if (d.slot && (t.classList.contains('scard') || t.classList.contains('plate'))) return select(+d.slot, true);
  if (d.spawn) return spawnPick(d.spawn);
  if (d.gender) { if (st.create && st.create.gender !== d.gender) { st.create.gender = d.gender; $$('.gcard').forEach(g => g.classList.toggle('on', g.dataset.gender === d.gender)); blip(640); post('createGender', { gender: d.gender }); } return; }
  if (d.nat) { st.create.nationality = d.nat; st.create.touched.nationality = true; delete st.create.server.nationality; const b = $('#nat .dd-btn'); b.textContent = d.nat; b.classList.remove('ph'); $('#nat').classList.remove('open'); updateCreate(); return; }
  if (d.q) {
    const it = st.cfg.shop.items.find(x => x.key === d.k); if (!it) return;
    const q = Math.max(0, Math.min(it.max, (st.shop.cart[it.key] || 0) + +d.q));
    st.shop.cart[it.key] = q; if (!q) delete st.shop.cart[it.key];
    blip(d.q > 0 ? 760 : 520); renderShop(); return;
  }
  if (d.pose) { st.poseTemp = d.pose; st.drawPoses?.(); post('posePreview', { slot: st.selected, pose: d.pose }); return; }
  if (d.tab) { st.settingsTab = d.tab; redrawSettings(); return; }
  if (d.set) {
    if (d.set === 'music.enabled') { st.settings.music.enabled = !st.settings.music.enabled; st.settings.music.enabled ? music.start(true) : music.stop(); }
    else st.settings[d.set] = !st.settings[d.set];
    applyLocalSettings(); redrawSettings(); saveSettings(); return;
  }
  if (d.scale) { st.settings.scale = +d.scale; applyLocalSettings(); redrawSettings(); saveSettings(); return; }
  if (d.dist) { st.settings.distance = d.dist; redrawSettings(); saveSettings(); return; }
  if (d.scene) { st.settings.scene = d.scene; redrawSettings(); saveSettings(); return; }
  if (d.filter !== undefined) { st.settings.filter = d.filter; redrawSettings(); saveSettings(); return; }
  if (d.weather) { st.settings.weather = d.weather; redrawSettings(); saveSettings(); return; }
  if (d.hour) { st.settings.hour = +d.hour; redrawSettings(); saveSettings(); return; }

  switch (d.act) {
    case 'play': return primary();
    case 'create': return startCreate(st.selected);
    case 'delete': return modalDelete();
    case 'deleteGo': return deleteGo();
    case 'pose': return modalPose();
    case 'poseCancel': { const c = st.bySlot[st.selected]; post('posePreview', { slot: st.selected, pose: c?.pose || null }); return closeModal(); }
    case 'poseSave': post('meta', { slot: st.selected, key: 'pose', value: st.poseTemp }); return closeModal();
    case 'favorite': { const c = st.bySlot[st.selected]; if (c) { blip(820); post('meta', { slot: c.slot, key: 'favorite', value: !c.favorite }); } return; }
    case 'unpartner': return post('meta', { slot: st.selected, key: 'partner', value: null });
    case 'backstory': return modalBackstory();
    case 'backstorySave': post('meta', { slot: st.selected, key: 'backstory', value: $('#bs-in').value }); return closeModal();
    case 'bulletin': st.showBulletin = !st.showBulletin; renderTop(); return setView(st.view);
    case 'settings': return modalSettings();
    case 'credits': return modalCredits();
    case 'redeem': return modalSettings('account');
    case 'redeemGo': return redeem();
    case 'settingsReset': post('settingsReset').then(r => { if (r) { st.settings = r; applyLocalSettings(); redrawSettings(); } }); return;
    case 'quit': return modalQuit();
    case 'quitGo': return post('quit');
    case 'modalClose': return closeModal();
    case 'modalBg': if (e.target === t) closeModal(); return;
    case 'prev': return select(Math.max(1, st.selected - 1));
    case 'next': return select(Math.min(st.data.shown, st.selected + 1));
    case 'createBack': st.create = null; setView('select'); renderAll(); return post('createCancel');
    case 'createSubmit': return submitCreate();
    case 'dd': { const dd = $('#nat'); dd.classList.toggle('open'); if (dd.classList.contains('open')) { natList(''); const q = $('#nat-q'); q.value = ''; q.focus(); } return; }
    case 'spawnGo': return spawnGo();
    case 'shopSkip': st.busy = true; return post('shopSkip');
    case 'shopBuy': return shopBuy();
  }
});

async function redeem() {
  const inp = $('#redeem-in'); if (!inp || !inp.value.trim()) return;
  const res = await post('redeem', { code: inp.value.trim() });
  toast(res?.msg || T('t_error'), res?.ok ? 'success' : 'error');
  if (res?.ok) inp.value = '';
}
async function shopBuy() {
  if (st.busy) return;
  st.busy = true; renderShop();
  const res = await post('shopConfirm', { cart: st.shop.cart });
  if (!res || !res.ok) { st.busy = false; renderShop(); toast(res?.msg || T('t_error'), 'error'); }
}

document.addEventListener('input', e => {
  const c = st.create; if (!c) return;
  const id = e.target.id;
  const map = { 'c-first': 'firstname', 'c-last': 'lastname', 'c-story': 'backstory' };
  if (map[id]) { c[map[id]] = e.target.value; c.touched[map[id]] = true; delete c.server[map[id]]; }
  else if (id === 'c-d' || id === 'c-m' || id === 'c-y') {
    e.target.value = e.target.value.replace(/\D/g, '');
    c[id.slice(2)] = e.target.value;
    if (c.d && c.m && c.y.length === 4) c.touched.dob = true;
    if (id === 'c-d' && e.target.value.length === 2) $('#c-m').focus();
    if (id === 'c-m' && e.target.value.length === 2) $('#c-y').focus();
  } else if (id === 'c-h') { c.height = +e.target.value; }
  else if (id === 'nat-q') { natList(e.target.value); return; }
  else return;
  updateCreate();
});
document.addEventListener('focusout', e => {
  const c = st.create; if (!c) return;
  const map = { 'c-first': 'firstname', 'c-last': 'lastname' };
  if (map[e.target.id]) { c.touched[map[e.target.id]] = true; updateCreate(); }
});

document.addEventListener('keydown', e => {
  const typing = /INPUT|TEXTAREA/.test(document.activeElement?.tagName);
  if (e.key === 'Escape') {
    if ($('#nat.open')) return $('#nat').classList.remove('open');
    if (st.modal) { if ($('[data-act="poseCancel"]')) return $('[data-act="poseCancel"]').click(); return closeModal(); }
    if (st.view === 'select') return post('overview');
    if (st.view === 'create') return $('[data-act="createBack"]')?.click();
    return;
  }
  if (e.key === 'Enter' && document.activeElement?.id === 'nat-q') { const first = $('#nat-list button'); if (first) first.click(); e.preventDefault(); return; }
  if (typing || st.modal) return;
  if (st.view === 'select' && st.data) {
    if (e.key === 'ArrowRight' || e.key === 'd') select(st.selected >= st.data.shown ? 1 : st.selected + 1);
    else if (e.key === 'ArrowLeft' || e.key === 'a') select(st.selected <= 1 ? st.data.shown : st.selected - 1);
    else if (e.key === 'Enter') primary();
    else if (e.key === 'Delete' && st.bySlot[st.selected] && st.data.canDelete) modalDelete();
  } else if (st.view === 'spawn') {
    const ids = st.spawn.options.map(o => o.id), i = ids.indexOf(st.spawn.selected);
    if (e.key === 'ArrowDown') spawnPick(ids[(i + 1) % ids.length]);
    else if (e.key === 'ArrowUp') spawnPick(ids[(i - 1 + ids.length) % ids.length]);
    else if (e.key === 'Enter') spawnGo();
  }
});

// ── messages from Lua ────────────────────────────────────────────────────
function handle(action, d) {
  switch (action) {
    case 'open':
      setData(d); st.create = null; st.busy = false; st.shop = { cart: {} };
      renderAll(); setView('select'); music.start(); break;
    case 'data':
      setData(d); if (st.view === 'select') renderAll(); else renderTop(); break;
    case 'select':
      if (d.slot !== st.selected) { st.selected = d.slot; if (st.view === 'select') { renderDossier(); renderRoster(); renderPlates(); } } break;
    case 'plates':
      st.plates = d.items || []; renderPlates(); break;
    case 'headshot':
      st.shots[d.slot] = d.url;
      if (st.view === 'select') { renderRoster(); if (d.slot === st.selected) renderDossier(); } break;
    case 'busy': setBusy(d.on, d.text); break;
    case 'toast': toast(d.text, d.type); break;
    case 'spawn':
      st.busy = false; st.spawn = { options: d.options || [], selected: d.selected };
      renderTop(); renderSpawn(); setView('spawn'); break;
    case 'shop':
      st.busy = false; st.shop = { cart: {} }; renderShop(); setView('shop'); break;
    case 'settings':
      st.settings = d; applyLocalSettings(); break;
    case 'welcome': {
      const w = $('#welcome'); w.innerHTML = `<h1>${esc(d.title)}</h1>${d.text ? `<p>${esc(d.text)}</p>` : ''}<i></i>`;
      w.classList.add('on'); setTimeout(() => w.classList.remove('on'), 3200); break;
    }
    case 'countdown': {
      const el = $('#countdown'); let n = d.seconds;
      const tick = () => { el.innerHTML = `<b>${n}</b><span>${T('create_title')}</span>`; if (n-- <= 0) { el.classList.remove('on'); return; } setTimeout(tick, 1000); };
      el.classList.add('on'); tick(); break;
    }
    case 'hide': setView('hidden'); setBusy(false); break;
    case 'close': setView('closed'); setBusy(false); music.stop(); st.shots = {}; st.plates = []; break;
  }
}

window.addEventListener('message', e => {
  const m = e.data; if (!m || !m.action) return;
  if (!st.cfg) { st.pending.push(m); return; }
  handle(m.action, m.data || {});
});

// Expose for the browser preview harness
window.NZM = { handle: (a, d) => handle(a, d), state: st };

// ── boot ─────────────────────────────────────────────────────────────────
post('ready').then(cfg => {
  if (!cfg || typeof cfg !== 'object') return;
  st.cfg = cfg; st.L = cfg.locale || {}; st.settings = cfg.settings || {};
  st.showBulletin = !!cfg.ui?.bulletin?.enabled;
  applyTheme(cfg.ui?.theme); applyLocalSettings();
  st.pending.splice(0).forEach(m => handle(m.action, m.data || {}));
});
fit();
})();
