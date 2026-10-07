/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V2 · NUI
   ═══════════════════════════════════════════════════════════ */
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
const PREVIEW = !RES;

async function post(name, data = {}) {
  if (PREVIEW) return window.Mock ? window.Mock.handle(name, data) : null;
  try {
    const r = await fetch(`https://${RES}/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
    });
    const t = await r.text();
    return t ? JSON.parse(t) : null;
  } catch (e) { return null; }
}

/* ─────────────── helpers ─────────────── */
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Math.round(Number(n) || 0).toLocaleString('en-US');
const num = (n) => (Number(n) || 0).toLocaleString('en-US');
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);

function hexRgb(hex) {
  const h = String(hex || '#08afa2').replace('#', '');
  const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
function tintVars(hex) {
  const [r, g, b] = hexRgb(hex);
  return `--c:${hex};--cw:rgba(${r},${g},${b},.11);--ce:rgba(${r},${g},${b},.34);--cg:rgba(${r},${g},${b},.17);--cs:rgba(${r},${g},${b},.38);--cf:rgba(${r},${g},${b},.06);--cc:${hex}`;
}

const S = {
  cfg: { version: '2.0.0', tiers: [], clashKey: 'Space' },
  tiers: {},
  skew: 0,
  view: null, vault: null, tab: 'profile', lb: 'snatches', sel: null,
  fence: null, fenceSel: new Set(), barber: null, cuts: null,
  bountyOpen: null, timer: 0,
};

function tier(id) { return S.tiers[id] || { id, label: id || 'Wig', color: '#a7aeb3' }; }
function tierStyle(id) { return tintVars(tier(id).color); }
function serverNow() { return Math.floor(Date.now() / 1000 + S.skew); }

function ago(ts) {
  const d = Math.max(0, serverNow() - (ts || 0));
  if (d < 60) return 'just now';
  if (d < 3600) return Math.floor(d / 60) + 'm ago';
  if (d < 86400) return Math.floor(d / 3600) + 'h ago';
  return Math.floor(d / 86400) + 'd ago';
}
function left(ts) {
  const d = Math.max(0, (ts || 0) - serverNow());
  const h = Math.floor(d / 3600), m = Math.floor((d % 3600) / 60), s = d % 60;
  if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m`;
  return `${m}:${String(s).padStart(2, '0')}`;
}
function initials(name) {
  return String(name || '?').trim().split(/\s+/).slice(0, 2).map((p) => p[0] || '').join('').toUpperCase() || '?';
}
function keyLabel(code) {
  if (!code) return 'SPACE';
  if (code === 'Space') return 'SPACE';
  if (code.startsWith('Key')) return code.slice(3);
  if (code.startsWith('Digit')) return code.slice(5);
  return code.toUpperCase();
}

/* ─────────────── scale ─────────────── */
function rescale() {
  const s = clamp(Math.min(innerHeight / 1080, innerWidth / 1920), 0.6, 2);
  document.documentElement.style.zoom = s;
}
addEventListener('resize', rescale);
rescale();

/* ─────────────── audio ─────────────── */
let AC = null;
function ac() { if (!AC) { try { AC = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) {} } return AC; }
function tone(freq, dur = 0.08, type = 'sine', vol = 0.05, slide = 0) {
  const a = ac(); if (!a) return;
  const o = a.createOscillator(), g = a.createGain();
  o.type = type; o.frequency.value = freq;
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(40, freq + slide), a.currentTime + dur);
  g.gain.setValueAtTime(vol, a.currentTime);
  g.gain.exponentialRampToValueAtTime(0.0001, a.currentTime + dur);
  o.connect(g); g.connect(a.destination);
  o.start(); o.stop(a.currentTime + dur + 0.02);
}
const SFX = {
  hit: () => { tone(660, 0.06, 'triangle', 0.06); tone(990, 0.05, 'sine', 0.03); },
  miss: () => tone(160, 0.14, 'sawtooth', 0.04, -60),
  tick: () => tone(1200, 0.03, 'sine', 0.02),
  win: () => { [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => tone(f, 0.16, 'triangle', 0.05), i * 70)); },
  lose: () => { [392, 330, 262].forEach((f, i) => setTimeout(() => tone(f, 0.2, 'sawtooth', 0.03), i * 90)); },
  toast: () => tone(880, 0.05, 'sine', 0.025),
  cash: () => { tone(1318, 0.06, 'square', 0.025); setTimeout(() => tone(1760, 0.09, 'square', 0.02), 60); },
  reveal: (rank) => { const base = 392 + rank * 60; [0, 4, 7, 12].forEach((s, i) => setTimeout(() => tone(base * Math.pow(2, s / 12), 0.22, 'triangle', 0.045), i * 80)); },
  start: () => { tone(300, 0.1, 'square', 0.03); setTimeout(() => tone(450, 0.12, 'square', 0.03), 110); },
};

const playing = new Set();
function playSound(name, volume = 0.6, duration = 3000) {
  const a = new Audio(`sounds/${name}.ogg`);
  a.volume = clamp(volume, 0, 1);
  a.loop = true;
  a.play().catch(() => {});
  playing.add(a);
  setTimeout(() => {
    const step = () => { a.volume = Math.max(0, a.volume - 0.08); if (a.volume > 0.01) setTimeout(step, 30); else { a.pause(); playing.delete(a); } };
    step();
  }, Math.max(200, duration - 250));
}

/* ═══════════════ TOASTS ═══════════════ */
const ICONS = { success: 'fa-check', error: 'fa-xmark', warning: 'fa-triangle-exclamation', info: 'fa-info' };
function toast(d) {
  const kind = ICONS[d.kind] ? d.kind : 'info';
  const el = document.createElement('div');
  el.className = `toast t-${kind}`;
  const dur = d.duration || 4200;
  el.innerHTML = `<div class="ch-frame"><div class="ch-in"><div class="ti"><i class="fa-solid ${ICONS[kind]}"></i></div><p>${esc(d.message)}</p><div class="prog"></div></div></div>`;
  const box = $('#toasts');
  box.appendChild(el);
  while (box.children.length > 5) box.firstElementChild.remove();
  el.querySelector('.prog').animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }], { duration: dur, easing: 'linear', fill: 'forwards' });
  SFX.toast();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 220); }, dur);
}

/* ═══════════════ BANNERS ═══════════════ */
function banner(p) {
  const el = document.createElement('div');
  let icon = 'fa-hand', html = '', color = '#08afa2';
  if (p.kind === 'snatch') {
    color = p.color || tier(p.tier).color;
    html = `<b>${esc(p.actor)}</b> snatched <b>${esc(p.target)}</b>'s <em>${esc(p.label || p.tierLabel + ' wig')}</em>`;
  } else if (p.kind === 'streak') {
    icon = 'fa-fire'; color = '#e5a50a';
    html = `<b>${esc(p.actor)}</b> is on a <em>${esc(p.streak)} snatch streak</em>`;
  } else if (p.kind === 'bounty') {
    icon = 'fa-crosshairs'; color = '#e5484d';
    html = `<em>${money(p.amount)}</em> bounty on <b>${esc(p.target)}</b>`;
  } else return;
  el.className = 'banner';
  el.setAttribute('style', tintVars(color));
  el.innerHTML = `<div class="ch-frame"><div class="ch-in"><div class="ti"><i class="fa-solid ${icon}"></i></div><p>${html}</p>${p.city ? '<span class="city">City</span>' : ''}</div></div>`;
  const box = $('#banners');
  box.appendChild(el);
  while (box.children.length > 3) box.firstElementChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 240); }, 5200);
}

/* ═══════════════ LEVEL UP / SPEECH / PROGRESS ═══════════════ */
let luT = 0;
function levelup(d) {
  const el = $('#levelup');
  el.innerHTML = `<div class="ch-frame"><div class="ch-in"><span>New title</span><b>${esc(d.title)}</b><em>Level ${esc(d.level)}</em></div></div>`;
  el.hidden = false;
  el.style.animation = 'none'; void el.offsetWidth; el.style.animation = '';
  SFX.win();
  clearTimeout(luT); luT = setTimeout(() => (el.hidden = true), 3800);
}

let spT = 0;
function speech(d) {
  const el = $('#speech');
  el.innerHTML = `<div class="ch-frame"><div class="ch-in"><i class="fa-solid fa-comment"></i><p>${esc(d.text)}</p></div></div>`;
  el.hidden = false;
  clearTimeout(spT); spT = setTimeout(() => (el.hidden = true), 4200);
}

let prRaf = 0;
function progress(d) {
  const el = $('#progress');
  $('.pr-label', el).textContent = d.label || '';
  el.hidden = false;
  const bar = $('.pr-bar i', el), time = $('.pr-time', el);
  const t0 = performance.now(), dur = d.duration || 3000;
  cancelAnimationFrame(prRaf);
  const step = (t) => {
    const k = clamp((t - t0) / dur, 0, 1);
    bar.style.width = (k * 100) + '%';
    time.textContent = ((dur - (t - t0)) / 1000).toFixed(1) + 's';
    if (k < 1) prRaf = requestAnimationFrame(step); else el.hidden = true;
  };
  prRaf = requestAnimationFrame(step);
}

/* ═══════════════ CLASH ═══════════════ */
const C = { on: false, d: null, x: 0, dir: 1, zl: 0.4, zw: 0.16, lock: 0, lastHit: 0, t0: 0, raf: 0, p: 0, endT: 0 };
const el = {
  clash: $('#clash'), track: $('.track'), zone: $('.track-zone'), cur: $('.track-cursor'), knot: $('.rope-knot'),
  mine: $('.rope-half.mine'), theirs: $('.rope-half.theirs'), time: $('.cl-time'), clock: $('.cl-clock'),
  flash: $('.cl-flash'), res: $('.cl-result'), mods: $('.cl-mods'),
};

function placeZone() {
  // keep the new zone away from the cursor so a hit can't be chained instantly
  let l, tries = 0;
  do { l = Math.random() * (1 - C.zw); tries++; } while (tries < 12 && Math.abs((l + C.zw / 2) - C.x) < 0.25);
  C.zl = l;
  el.zone.style.left = (l * 100) + '%';
  el.zone.style.width = (C.zw * 100) + '%';
}

function renderRope() {
  const d = C.d; if (!d) return;
  const mine = d.role === 'snatcher' ? C.p : -C.p;
  const k = clamp(50 + (mine / d.winAt) * 50, 0, 100);
  el.mine.style.width = k + '%';
  el.theirs.style.width = (100 - k) + '%';
  el.knot.style.left = k + '%';
}

function flash(text, good) {
  el.flash.textContent = text;
  el.flash.className = 'cl-flash ' + (good ? 'good' : 'bad');
  void el.flash.offsetWidth;
  el.flash.classList.add('go');
}

function clashLoop(t) {
  if (!C.on) return;
  const dt = Math.min(0.05, (t - (C.last || t)) / 1000);
  C.last = t;
  C.x += C.dir * C.d.speed * dt;
  if (C.x >= 1) { C.x = 1; C.dir = -1; }
  if (C.x <= 0) { C.x = 0; C.dir = 1; }
  el.cur.style.left = (C.x * 100) + '%';
  el.track.classList.toggle('locked', performance.now() < C.lock);
  const rem = Math.max(0, C.d.duration - (performance.now() - C.t0));
  el.time.textContent = (rem / 1000).toFixed(1);
  el.clock.classList.toggle('hot', rem < 2000);
  C.raf = requestAnimationFrame(clashLoop);
}

function clashStart(d) {
  clearTimeout(C.endT);
  Object.assign(C, { on: true, d, x: Math.random(), dir: 1, zw: clamp(d.zone || 0.16, 0.05, 0.6), lock: 0, lastHit: 0, t0: performance.now(), p: d.p || 0, last: 0 });
  el.res.hidden = true;
  $('.cl-side.me .cl-role').textContent = d.role === 'snatcher' ? 'You · Snatching' : 'You · Defending';
  $('.cl-side.me .cl-name').textContent = d.me || 'You';
  $('.cl-side.them .cl-role').textContent = d.role === 'snatcher' ? 'Holding on' : 'Snatching';
  $('.cl-side.them .cl-name').textContent = d.opp || '';
  $('.cl-key').textContent = keyLabel(d.key || S.cfg.clashKey);
  const mods = [];
  if (d.blind) mods.push(`<span class="chip" style="${tintVars('#e5a50a')}"><i class="fa-solid fa-eye-slash"></i>Blindside</span>`);
  if (d.glued) mods.push(`<span class="chip" style="${tintVars(d.role === 'victim' ? '#08afa2' : '#e5484d')}"><i class="fa-solid fa-droplet"></i>Glued down</span>`);
  if (d.layer === 'wig') mods.push(`<span class="chip"><i class="fa-solid fa-masks-theater"></i>Wearing a wig</span>`);
  el.mods.innerHTML = mods.join('');
  placeZone();
  renderRope();
  el.clash.hidden = false;
  el.clash.style.animation = 'none'; void el.clash.offsetWidth; el.clash.style.animation = '';
  SFX.start();
  cancelAnimationFrame(C.raf);
  C.raf = requestAnimationFrame(clashLoop);
}

function clashPress() {
  const now = performance.now();
  if (now < C.lock || now - C.lastHit < 230) return;
  const inZone = C.x >= C.zl && C.x <= C.zl + C.zw;
  if (inZone) {
    C.lastHit = now;
    post('clashHit');
    flash('Clean pull', true);
    SFX.hit();
    el.track.classList.add('hit');
    setTimeout(() => el.track.classList.remove('hit'), 120);
    placeZone();
    if (PREVIEW && window.Mock) window.Mock.localHit(C.d.role);
  } else {
    C.lock = now + (C.d.lockout || 380);
    flash('Missed', false);
    SFX.miss();
    el.clash.classList.remove('shake'); void el.clash.offsetWidth; el.clash.classList.add('shake');
  }
}

function clashTick(p) {
  if (!C.on) return;
  const before = C.p;
  C.p = Number(p) || 0;
  renderRope();
  const mine = C.d.role === 'snatcher' ? C.p - before : before - C.p;
  if (mine < 0) SFX.tick();
}

function clashEnd(r) {
  const wasOn = C.on;
  C.on = false;
  cancelAnimationFrame(C.raf);
  if (!wasOn || r.cancelled) { el.clash.hidden = true; return; }
  if (r.p !== undefined) { C.p = r.p; renderRope(); }
  let title, sub, win;
  if (r.role === 'snatcher') {
    win = r.win;
    title = r.win ? 'Snatched' : 'Shoved off';
    sub = r.win ? `You got ${esc(r.opp)}'s hair` : `${esc(r.opp)} held on`;
  } else {
    win = r.win;
    title = r.win ? 'Held on' : 'Snatched';
    sub = r.win ? `${esc(r.opp)} couldn't get it` : `${esc(r.opp)} took your ${r.layer === 'wig' ? 'wig' : 'hair'}`;
  }
  el.res.className = 'cl-result ' + (win ? 'win' : 'lose');
  el.res.innerHTML = `<b>${title}</b><span>${sub}</span>`;
  el.res.hidden = false;
  win ? SFX.win() : SFX.lose();
  C.endT = setTimeout(() => { el.clash.hidden = true; }, 1700);
}

addEventListener('keydown', (e) => {
  if (C.on) {
    if (e.code === (C.d.key || S.cfg.clashKey) && !e.repeat) { e.preventDefault(); clashPress(); }
    return;
  }
  if (e.key === 'Escape') {
    if (!$('#modal').hidden) return closeModal();
    if (S.view) return closeApp();
  }
});

/* ═══════════════ REVEAL ═══════════════ */
let rvT = 0;
function reveal(r) {
  const w = r.wig || {};
  const t = tier(w.tier);
  const rank = Math.max(0, S.cfg.tiers.findIndex((x) => x.id === w.tier));
  const chips = [];
  if (r.xp) chips.push(`<span class="chip t-success"><i class="fa-solid fa-arrow-up"></i>+${num(r.xp)} rep</span>`);
  if (r.streak > 1) chips.push(`<span class="chip t-warning"><i class="fa-solid fa-fire"></i>${r.streak} streak</span>`);
  if (r.blind) chips.push(`<span class="chip"><i class="fa-solid fa-eye-slash"></i>Blindside</span>`);
  if (r.revenge) chips.push(`<span class="chip t-error"><i class="fa-solid fa-rotate-left"></i>Revenge</span>`);
  if (r.bounty) chips.push(`<span class="chip t-success"><i class="fa-solid fa-crosshairs"></i>Bounty ${money(r.bounty)}</span>`);
  if (r.newStyle) chips.push(`<span class="chip" style="${tintVars('#08afa2')}"><i class="fa-solid fa-book-open"></i>New in catalog</span>`);
  if (r.worn) chips.push(`<span class="chip"><i class="fa-solid fa-masks-theater"></i>It was a wig</span>`);
  const box = $('#reveal');
  box.setAttribute('style', tintVars(t.color));
  box.innerHTML = `<div class="rv-frame"><div class="rv-in">
    <div class="rv-glyph"><i class="fa-solid fa-crown"></i></div>
    <div class="rv-tier">${esc(t.label)}</div>
    <div class="rv-name">${esc(w.length ? w.length + '" ' : '')}${esc(w.style || 'Wig')}</div>
    <div class="rv-sub">${esc(w.lace || '')}${w.from ? ' · from ' + esc(w.from) : ''}</div>
    <div class="rv-grid">
      <div class="rv-cell"><span>Worth</span><b>${money(w.value)}</b></div>
      <div class="rv-cell"><span>Condition</span><b>${esc(w.cond ?? 100)}%</b></div>
      <div class="rv-cell"><span>Hands</span><b>${num((w.hops || 0) + 1)}</b></div>
    </div>
    <div class="rv-chips">${chips.join('')}</div>
  </div></div>`;
  box.hidden = false;
  box.classList.remove('out');
  box.style.animation = 'none'; void box.offsetWidth; box.style.animation = '';
  SFX.reveal(rank);
  clearTimeout(rvT);
  rvT = setTimeout(hideReveal, 5600);
}
function hideReveal() {
  const box = $('#reveal');
  if (box.hidden) return;
  box.classList.add('out');
  setTimeout(() => { box.hidden = true; box.classList.remove('out'); }, 260);
}
$('#reveal').addEventListener('click', hideReveal);

/* ═══════════════ APP SHELL ═══════════════ */
const app = $('#app'), body = $('#appBody');

function setHead(title, sub) {
  $('#appTitle').textContent = title;
  $('#appSub').textContent = sub || '';
  $('#appVer').textContent = 'v' + (S.cfg.version || '2.0.0');
}

function openApp(view, data) {
  S.view = view;
  closeModal();
  app.hidden = false;
  app.classList.toggle('sm', view === 'barber' || view === 'cuts');
  const fr = $('.app-frame'); fr.style.animation = 'none'; void fr.offsetWidth; fr.style.animation = '';
  if (view === 'vault') { S.tab = (data && data.tab) || 'profile'; S.sel = null; S.bountyOpen = null; body.innerHTML = loading(); loadVault(); }
  else if (view === 'fence') { S.fence = data; S.fenceSel = new Set(); renderFence(); }
  else if (view === 'barber') { S.barber = data; renderBarber(); }
  else if (view === 'cuts') { S.cuts = data; renderCuts(); }
  clearInterval(S.timer);
  S.timer = setInterval(liveTick, 1000);
}

function closeApp(silent) {
  if (!S.view) return;
  S.view = null;
  app.hidden = true;
  closeModal();
  clearInterval(S.timer);
  if (!silent) post('close');
}

function loading() { return `<div class="view"><div class="empty"><i class="fa-solid fa-circle-notch fa-spin"></i>Loading</div></div>`; }

app.addEventListener('click', (e) => {
  const b = e.target.closest('[data-act]');
  if (!b) return;
  const act = b.dataset.act, v = b.dataset.v;
  ACT[act] && ACT[act](v, b, e);
});
app.addEventListener('input', (e) => {
  if (e.target.matches('[data-int]')) e.target.value = e.target.value.replace(/[^\d]/g, '').slice(0, 7);
});

/* live countdowns */
function liveTick() {
  $$('[data-until]').forEach((n) => {
    const u = Number(n.dataset.until);
    n.textContent = u > serverNow() ? left(u) : (n.dataset.done || '0:00');
  });
}

/* ═══════════════ VAULT ═══════════════ */
async function loadVault() {
  const d = await post('vaultFetch');
  if (!d || S.view !== 'vault') return;
  S.vault = d;
  S.skew = (d.now || Date.now() / 1000) - Date.now() / 1000;
  if (d.version) S.cfg.version = d.version;
  if (S.sel && !arr(d.wigs).some((w) => w.key === S.sel)) S.sel = null;
  renderVault();
}

const TABS = [
  ['profile', 'fa-user', 'Profile'],
  ['wigs', 'fa-box-archive', 'My Wigs'],
  ['catalog', 'fa-book-open', 'Catalog'],
  ['bounties', 'fa-crosshairs', 'Bounties'],
  ['leaders', 'fa-ranking-star', 'Leaderboard'],
  ['feed', 'fa-tower-broadcast', 'City Feed'],
];

function renderVault() {
  const d = S.vault; if (!d) return;
  const me = d.me;
  setHead('Wig Vault', `${me.title} · Level ${me.level} · ${me.name}`);
  const counts = { wigs: arr(d.wigs).length, bounties: arr(d.revenge).length };
  const rail = TABS.map(([id, ic, lb]) => {
    let badge = '';
    if (id === 'wigs' && counts.wigs) badge = `<span class="badge">${counts.wigs}</span>`;
    if (id === 'bounties' && me.bountyOnMe) badge = `<span class="badge red">${money(me.bountyOnMe)}</span>`;
    return `<button class="rail-btn ${S.tab === id ? 'on' : ''}" data-act="tab" data-v="${id}"><i class="fa-solid ${ic}"></i>${lb}${badge}</button>`;
  }).join('');
  const st = me.stats;
  body.innerHTML = `<div class="rail">${rail}
      <div class="rail-foot"><b>${num(st.snatches)}</b> snatched · <b>${num(st.defends)}</b> held<br><b>${money(st.earned)}</b> earned</div>
    </div>
    <div class="view ${S.tab === 'wigs' ? 'split' : ''}" id="vview">${VIEWS[S.tab]()}</div>`;
  liveTick();
}

function hairCard(me) {
  const h = me.hair || {};
  let icon = 'fa-user', title = 'Natural hair', sub = 'Nothing to report. Keep it that way.', tone = 't-success', action = '';
  if (h.wig) {
    icon = 'fa-masks-theater'; tone = '';
    title = h.wig.label || 'Wearing a wig';
    sub = `${h.wig.cond ?? 100}% condition · if it gets snatched, your ${h.bald ? 'bald head' : 'real hair'} shows`;
    action = `<button class="btn sm" data-act="unwear"><i class="fa-solid fa-arrow-rotate-left"></i>Take off</button>`;
  } else if (h.bald) {
    icon = 'fa-user-slash'; tone = 't-error';
    title = 'Bald';
    sub = h.bald.u > 0 ? `Regrows in <span data-until="${h.bald.u}" data-done="any second">${left(h.bald.u)}</span> · or visit a barber` : 'Visit a barber to grow it back';
  } else if (h.cut) {
    icon = 'fa-scissors'; tone = 't-info';
    title = 'Fresh haircut';
    sub = 'Someone gave you a new look. A barber can undo it.';
  }
  const flags = [];
  if (me.glueUntil > serverNow()) flags.push(`<span class="chip t-success"><i class="fa-solid fa-droplet"></i>Glued · <span data-until="${me.glueUntil}">${left(me.glueUntil)}</span></span>`);
  if (me.cooldownUntil > serverNow()) flags.push(`<span class="chip t-warning"><i class="fa-solid fa-hourglass-half"></i>Cooldown · <span data-until="${me.cooldownUntil}" data-done="ready">${left(me.cooldownUntil)}</span></span>`);
  if (me.newUntil > serverNow()) flags.push(`<span class="chip"><i class="fa-solid fa-shield"></i>New player · <span data-until="${me.newUntil}">${left(me.newUntil)}</span></span>`);
  if (me.passive) flags.push(`<span class="chip"><i class="fa-solid fa-dove"></i>Passive</span>`);
  if (me.bountyOnMe) flags.push(`<span class="chip t-error"><i class="fa-solid fa-crosshairs"></i>${money(me.bountyOnMe)} on your head</span>`);
  if (me.stats.streak > 1) flags.push(`<span class="chip t-warning"><i class="fa-solid fa-fire"></i>${me.stats.streak} streak</span>`);
  return `<div class="card"><div class="hair ${tone}"><div class="ti ${tone}" style="${h.wig ? tierStyle(h.wig.tier) : ''}"><i class="fa-solid ${icon}"></i></div>
      <div class="hair-tx"><b>${esc(title)}</b><span>${sub}</span></div>${action}</div>
      ${flags.length ? `<div class="flags">${flags.join('')}</div>` : ''}</div>`;
}

const VIEWS = {
  profile() {
    const d = S.vault, me = d.me, st = me.stats;
    const span = (me.nextXp || me.xp) - me.levelXp;
    const pct = me.nextXp ? clamp(((me.xp - me.levelXp) / Math.max(1, span)) * 100, 0, 100) : 100;
    const attempts = st.snatches + st.fails;
    const rate = attempts ? Math.round((st.snatches / attempts) * 100) : 0;
    const fights = st.defends + st.snatched;
    const hold = fights ? Math.round((st.defends / fights) * 100) : 0;
    const p = me.perks || {};
    const perk = (label, v, suffix = '%') => `<div class="perk ${v ? '' : 'off'}"><span>${label}</span><b>${v ? '+' + Math.round(v * 100) + suffix : '-'}</b></div>`;
    const best = st.best_tier ? tier(st.best_tier) : null;
    return `
      <div class="hero">
        <div class="mono">${esc(initials(me.name))}</div>
        <div class="hero-tx">
          <small>${esc(me.title)}</small>
          <b>${esc(me.name)}</b>
          <em>${num(me.xp)} reputation${me.nextTitle ? ` · ${num(me.nextXp - me.xp)} to ${esc(me.nextTitle)}` : ' · max title'}</em>
          <div class="xp"><div class="xp-bar"><i style="width:${pct}%"></i></div></div>
        </div>
        <div class="lvl"><span>Level</span><b>${me.level}</b></div>
      </div>
      <div class="sec">${hairCard(me)}</div>
      <div class="sec">
        <div class="sec-h"><h3>Record</h3><span>${best ? `Best pull: <b style="color:${best.color}">${esc(best.label)}</b>` : ''}</span></div>
        <div class="grid4">
          <div class="stat"><span><i class="fa-solid fa-hand"></i>Snatched</span><b>${num(st.snatches)}<small>${rate}% rate</small></b></div>
          <div class="stat"><span><i class="fa-solid fa-shield-halved"></i>Held on</span><b>${num(st.defends)}<small>${hold}%</small></b></div>
          <div class="stat"><span><i class="fa-solid fa-fire"></i>Best streak</span><b>${num(st.best_streak)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-user-slash"></i>Lost hair</span><b>${num(st.snatched)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-sack-dollar"></i>Earned</span><b>${money(st.earned)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-crosshairs"></i>Bounties</span><b>${num(st.bounties_claimed)}<small>${money(st.bounty_earned)}</small></b></div>
          <div class="stat"><span><i class="fa-solid fa-rotate-left"></i>Revenge</span><b>${num(st.revenges)}</b></div>
          <div class="stat"><span><i class="fa-solid fa-scissors"></i>Cuts · Buzzes</span><b>${num(st.cuts)}<small>· ${num(st.buzzes)}</small></b></div>
        </div>
      </div>
      <div class="grid2">
        <div class="card"><div class="sec-h"><h3>Perks</h3><span>${esc(me.title)}</span></div>
          <div class="perks">${perk('Shorter cooldown', p.cooldown)}${perk('Wider clash zone', p.zone, ' pts')}${perk('Better buyer prices', p.sell)}${perk('Tier luck', p.luck)}</div></div>
        <div class="card"><div class="sec-h"><h3>Titles</h3><span>${me.level} / ${arr(d.levels).length}</span></div>
          <div class="perks">${arr(d.levels).slice(Math.max(0, me.level - 2), me.level + 2).map((l, i, a) => {
            const idx = arr(d.levels).indexOf(l) + 1;
            return `<div class="perk ${idx <= me.level ? '' : 'off'}"><span>${idx === me.level ? '<i class="fa-solid fa-caret-right" style="color:var(--teal);margin-right:6px"></i>' : ''}${esc(l.title)}</span><b>${num(l.xp)}</b></div>`;
          }).join('')}</div></div>
      </div>`;
  },

  wigs() {
    const d = S.vault, wigs = arr(d.wigs);
    if (!wigs.length) return `<div class="wig-list"><div class="empty"><i class="fa-solid fa-box-open"></i>No wigs yet. Go take some.</div></div>`;
    const sel = wigs.find((w) => w.key === S.sel) || wigs[0];
    S.sel = sel.key;
    const total = wigs.reduce((a, w) => a + (w.value || 0), 0);
    return `<div class="wig-list">
        <div class="sec-h"><h3>${wigs.length} wig${wigs.length === 1 ? '' : 's'}</h3><span>Worth about ${money(total)} to the buyer</span></div>
        <div class="wig-grid">${wigs.map((w) => wigCard(w, w.key === sel.key)).join('')}</div>
      </div>
      <div class="detail">${wigDetail(sel)}</div>`;
  },

  catalog() {
    const d = S.vault, styles = arr(d.styles), cat = d.catalog || {};
    const have = styles.filter((s) => cat[s]).length;
    const rewards = arr(d.catalogRewards);
    const max = styles.length || 1;
    const miles = rewards.map((r, i) => `<div class="mile ${have >= r.count ? 'got' : ''}" style="left:${(r.count / max) * 100}%"><i class="fa-solid ${have >= r.count ? 'fa-check' : 'fa-gift'}"></i><span>${r.count} · ${money(r.money)}</span></div>`).join('');
    return `
      <div class="cat-prog">
        <b>${have}<small> / ${styles.length}</small></b>
        <div class="miles"><div class="miles-bar"><i style="width:${(have / max) * 100}%"></i></div>${miles}</div>
      </div>
      <div class="note">Every hairstyle maps to one style name. Snatch different looks to fill the book. Your best tier per style is kept.</div>
      <div class="cat-grid">${styles.map((s) => {
        const c = cat[s];
        if (!c) return `<div class="cat locked"><i class="fa-solid fa-lock"></i><b>${esc(s)}</b><span>Not found</span></div>`;
        const t = tier(c.tier);
        return `<div class="cat" style="${tintVars(t.color)}"><i class="fa-solid fa-crown"></i><b>${esc(s)}</b><span>${esc(t.label)}${c.times > 1 ? ' · x' + c.times : ''}</span></div>`;
      }).join('')}</div>`;
  },

  bounties() {
    const d = S.vault, cfg = d.bountyCfg || {};
    const board = arr(d.bounties), rev = arr(d.revenge);
    const boardHtml = board.length ? board.map((b, i) => `
      <div class="row"><div class="rank ${i < 3 ? 'r' + (i + 1) : ''}">${i + 1}</div>
        <div class="row-tx"><b><span class="dot ${b.online ? 'on' : ''}"></span>${esc(b.name)}</b><span>${b.count} bount${b.count === 1 ? 'y' : 'ies'} · ${esc(arr(b.placers).join(', '))}</span></div>
        <div class="row-val">${money(b.total)}<small>${ago(b.created)}</small></div></div>`).join('')
      : `<div class="empty"><i class="fa-solid fa-crosshairs"></i>Nobody is wanted right now</div>`;
    const revHtml = rev.length ? rev.map((r) => {
      const open = S.bountyOpen === r.identifier;
      return `<div class="row" style="flex-wrap:wrap">
        <div class="row-tx"><b><span class="dot ${r.online ? 'on' : ''}"></span>${esc(r.name)}</b><span>Got you ${r.times}x · ${ago(r.last)}${r.bounty ? ' · ' + money(r.bounty) + ' on them' : ''}</span></div>
        ${cfg.enabled ? `<button class="btn sm ${open ? 'ghost' : 'red'}" data-act="bountyToggle" data-v="${esc(r.identifier)}"><i class="fa-solid ${open ? 'fa-xmark' : 'fa-crosshairs'}"></i>${open ? 'Cancel' : 'Bounty'}</button>` : ''}
        ${open ? `<div style="width:100%"><div class="binput">
            <label class="field"><i class="fa-solid fa-dollar-sign"></i><input id="bAmt" data-int placeholder="${num(cfg.min)} - ${num(cfg.max)}" autofocus></label>
            <button class="btn teal" data-act="bountyPlace" data-v="${esc(r.identifier)}">Place</button></div>
          <div class="note">${Math.round((cfg.fee || 0) * 100)}% fee. Whoever snatches ${esc(r.name)} next collects the rest. Expires and refunds if nobody does.</div></div>` : ''}
      </div>`;
    }).join('') : `<div class="empty"><i class="fa-solid fa-face-smile"></i>Nobody snatched you recently</div>`;
    return `<div class="grid2" style="align-items:start">
      <div><div class="sec-h"><h3>Most wanted</h3><span>${board.length} target${board.length === 1 ? '' : 's'}</span></div><div class="list">${boardHtml}</div></div>
      <div><div class="sec-h"><h3>Who got you</h3><span>Last 24h</span></div><div class="list">${revHtml}</div>
        <div class="note" style="margin-top:10px"><i class="fa-solid fa-rotate-left" style="color:var(--red);margin-right:6px"></i>Snatch them back yourself for revenge rep and better tier luck.</div></div>
    </div>`;
  },

  leaders() {
    const d = S.vault, lbs = d.leaderboards || {};
    const segs = [['snatches', 'Snatches'], ['defends', 'Held on'], ['best_streak', 'Streak'], ['earned', 'Earned'], ['bounty_earned', 'Bounties']];
    const rows = arr(lbs[S.lb]);
    const fmt = (v) => (S.lb === 'earned' || S.lb === 'bounty_earned') ? money(v) : num(v);
    return `<div class="seg">${segs.map(([k, l]) => `<button class="${S.lb === k ? 'on' : ''}" data-act="lb" data-v="${k}">${l}</button>`).join('')}</div>
      <div class="list">${rows.length ? rows.map((r, i) => `
        <div class="row ${r.name === d.me.name ? 'me' : ''}"><div class="rank ${i < 3 ? 'r' + (i + 1) : ''}">${i + 1}</div>
          <div class="row-tx"><b><span class="dot ${r.online ? 'on' : ''}"></span>${esc(r.name)}</b><span>${esc(r.title || '')}</span></div>
          <div class="row-val">${fmt(r.value)}</div></div>`).join('') : `<div class="empty"><i class="fa-solid fa-ranking-star"></i>No one on the board yet</div>`}</div>`;
  },

  feed() {
    const rows = arr(S.vault.feed);
    if (!rows.length) return `<div class="empty"><i class="fa-solid fa-tower-broadcast"></i>The city is quiet</div>`;
    return `<div class="list">${rows.map((f) => {
      let icon = 'fa-hand', color = '#08afa2', text = '';
      if (f.kind === 'snatch') { color = tier(f.tier).color; text = `<b>${esc(f.actor_name)}</b> snatched <b>${esc(f.target_name)}</b>'s <em>${esc(f.label || tier(f.tier).label)}</em>${f.amount ? ` and collected ${money(f.amount)}` : ''}`; }
      else if (f.kind === 'buzz') { icon = 'fa-user-slash'; color = '#e5484d'; text = `<b>${esc(f.actor_name)}</b> buzzed <b>${esc(f.target_name)}</b> bald`; }
      else if (f.kind === 'bounty') { icon = 'fa-crosshairs'; color = '#e5484d'; text = `<b>${esc(f.actor_name)}</b> put <em>${money(f.amount)}</em> on <b>${esc(f.target_name)}</b>`; }
      else if (f.kind === 'claim') { icon = 'fa-sack-dollar'; color = '#e5a50a'; text = `<b>${esc(f.actor_name)}</b> collected <em>${money(f.amount)}</em> for <b>${esc(f.target_name)}</b>`; }
      else return '';
      return `<div class="row feed-row" style="${tintVars(color)}"><div class="ti"><i class="fa-solid ${icon}"></i></div><p>${text}</p><time>${ago(f.created)}</time></div>`;
    }).join('')}</div>`;
  },
};

function condColor(c) { return c >= 70 ? '#08afa2' : c >= 40 ? '#e5a50a' : '#e5484d'; }

function wigCard(w, on, selectable) {
  const t = tier(w.tier);
  return `<button class="wig ${on ? 'on' : ''} ${selectable && S.fenceSel.has(w.key) ? 'sel' : ''}" style="${tintVars(t.color)}" data-act="${selectable ? 'fsel' : 'wsel'}" data-v="${esc(w.key)}">
    ${selectable ? '<span class="check"><i class="fa-solid fa-check"></i></span>' : ''}
    <div class="wig-top"><span class="tier">${esc(t.label)}</span>${selectable ? '' : `<span class="wig-val">${money(w.value)}</span>`}</div>
    <div class="wig-name">${w.generic ? 'Wig' : esc(w.length + '" ' + w.style)}</div>
    <div class="wig-sub">${w.generic ? 'Unmarked' : esc(w.lace)}${w.hops ? ` · ${w.hops + 1} owners` : ''}</div>
    <div class="cond"><div class="cond-bar"><i style="width:${w.cond}%;--cc:${condColor(w.cond)}"></i></div><span>${selectable ? money(w.value) : w.cond + '%'}</span></div>
  </button>`;
}

function wigDetail(w) {
  const d = S.vault, t = tier(w.tier);
  const fits = !w.generic && w.fits && w.fits === d.myModel;
  const canRepair = d.hasMeta && !w.generic && w.cond < 100;
  const owners = arr(w.owners);
  const date = w.ts ? new Date(w.ts * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '-';
  return `<div class="d-head" style="${tintVars(t.color)}"><div class="d-glyph"><i class="fa-solid fa-crown"></i></div>
      <b>${w.generic ? 'Wig' : esc(w.length + '" ' + w.style)}</b><span>${esc(t.label)}${w.generic ? '' : ' · ' + esc(w.lace)}</span></div>
    <div class="kv">
      <div><span>Buyer pays</span><b>${money(w.value)}</b></div>
      <div><span>Condition</span><b style="color:${condColor(w.cond)}">${w.cond}%</b></div>
      ${w.generic ? '' : `<div><span>Fits</span><b>${w.fits === 'm' ? 'Male' : 'Female'} characters</b></div>
      <div><span>Serial</span><b>${esc(w.serial)}</b></div>
      <div><span>Snatched by</span><b>${esc(w.by || '-')}</b></div>
      <div><span>First taken</span><b>${date}</b></div>`}
    </div>
    ${owners.length ? `<div class="card inset" style="${tintVars(t.color)}"><div class="sec-h" style="margin-bottom:4px"><h3>Provenance</h3><span>${w.hops ? `${w.hops}x stolen` : 'Fresh'}</span></div>
      <div class="chain">${owners.map((o, i) => `<div>${esc(o)}<small>${i === 0 ? 'last worn by' : ''}</small></div>`).join('')}</div></div>` : ''}
    <div class="actions">
      ${w.generic ? '' : `<button class="btn teal wide" data-act="wear" data-v="${esc(w.key)}" ${fits ? '' : 'disabled'}><i class="fa-solid fa-masks-theater"></i>${fits ? 'Wear it' : "Doesn't fit you"}</button>`}
      ${canRepair ? `<button class="btn wide" data-act="repair" data-v="${esc(w.key)}" ${d.me.kits > 0 ? '' : 'disabled'}><i class="fa-solid fa-wand-magic-sparkles"></i>Use wig kit${d.me.kits > 0 ? ` (${d.me.kits})` : ' (none)'}</button>` : ''}
      ${d.trading ? `<button class="btn wide" data-act="offer" data-v="${esc(w.key)}"><i class="fa-solid fa-handshake"></i>Sell or gift to a player</button>` : ''}
    </div>`;
}

/* ═══════════════ FENCE ═══════════════ */
function renderFence() {
  const f = S.fence; if (!f) return;
  const wigs = arr(f.wigs);
  setHead(f.label || 'Buyer', `${wigs.length} wig${wigs.length === 1 ? '' : 's'} on you${f.sellPerk ? ` · +${f.sellPerk}% from your title` : ''}${f.dirty ? ' · pays dirty' : ''}`);
  const total = wigs.filter((w) => S.fenceSel.has(w.key)).reduce((a, w) => a + (w.value || 0), 0);
  const market = arr(f.market).map((m) => {
    const t = tier(m.id);
    return `<div class="mk" style="${tintVars(t.color)}"><span>${esc(t.label)}</span><b>${m.demand}%</b><div class="cond-bar"><i style="width:${m.demand}%;--cc:${condColor(m.demand)}"></i></div></div>`;
  }).join('');
  body.innerHTML = `<div class="view fence">
    <div class="sec-h"><h3>Market demand</h3><span>Prices drop as the city floods a tier, then recover</span></div>
    <div class="market">${market}</div>
    <div class="sec-h"><h3>Your wigs</h3><span><button class="btn sm ghost" data-act="fall">${S.fenceSel.size === wigs.length && wigs.length ? 'Clear' : 'Select all'}</button></span></div>
    ${wigs.length ? `<div class="wig-grid">${wigs.map((w) => wigCard(w, false, true)).join('')}</div>` : `<div class="empty"><i class="fa-solid fa-box-open"></i>Nothing left to sell</div>`}
    <div class="sellbar"><div class="total"><span>${S.fenceSel.size} selected</span><b class="${f.dirty ? 'dirty' : ''}">${money(total)}</b></div>
      <button class="btn teal" data-act="sell" ${S.fenceSel.size ? '' : 'disabled'}><i class="fa-solid fa-sack-dollar"></i>Sell</button></div>
  </div>`;
}

/* ═══════════════ BARBER ═══════════════ */
function renderBarber() {
  const b = S.barber; if (!b) return;
  setHead('Barber', `${money(b.money)} on you`);
  const h = b.state || {};
  let title = 'Your hair is fine', sub = 'Nothing to fix today.', btn = `<button class="btn" disabled>Nothing to do</button>`, icon = 'fa-user', tone = 't-success';
  if (h.bald) {
    title = 'Bald'; icon = 'fa-user-slash'; tone = 't-error';
    sub = h.bald.u > 0 ? `Grows back by itself in <span data-until="${h.bald.u}">${left(h.bald.u)}</span>` : "It won't grow back by itself";
    btn = `<button class="btn teal" data-act="restore"><i class="fa-solid fa-seedling"></i>Grow it back · ${money(b.restorePrice)}</button>`;
  } else if (h.cut) {
    title = 'Haircut from someone'; icon = 'fa-scissors'; tone = 't-info';
    sub = 'Go back to your own style.';
    btn = `<button class="btn teal" data-act="restore"><i class="fa-solid fa-arrow-rotate-left"></i>Undo haircut · ${b.resetPrice ? money(b.resetPrice) : 'Free'}</button>`;
  }
  if (h.wig) sub += ' You are wearing a wig over it.';
  const wigs = arr(b.wigs);
  body.innerHTML = `<div class="view">
    <div class="card" style="margin-bottom:16px"><div class="hair"><div class="ti ${tone}"><i class="fa-solid ${icon}"></i></div>
      <div class="hair-tx"><b>${title}</b><span>${sub}</span></div>${btn}</div></div>
    <div class="sec-h"><h3>Wig repairs</h3><span>${wigs.length ? 'Back to 100%' : ''}</span></div>
    <div class="list">${wigs.length ? wigs.map((w) => {
      const t = tier(w.tier);
      return `<div class="row" style="${tintVars(t.color)}"><div class="ti"><i class="fa-solid fa-crown"></i></div>
        <div class="row-tx"><b>${esc(w.length + '" ' + w.style)}</b><span>${esc(t.label)} · <span style="color:${condColor(w.cond)}">${w.cond}%</span></span></div>
        <button class="btn sm" data-act="brepair" data-v="${esc(w.key)}">Repair · ${money(w.repair)}</button></div>`;
    }).join('') : `<div class="empty" style="padding:22px"><i class="fa-solid fa-wand-magic-sparkles"></i>No damaged wigs on you</div>`}</div>
  </div>`;
  liveTick();
}

/* ═══════════════ CUTS ═══════════════ */
function renderCuts() {
  const c = S.cuts; if (!c) return;
  setHead(c.tool === 'clippers' ? 'Clippers' : 'Scissors', `Pick a cut for ${c.client}`);
  body.innerHTML = `<div class="view">
    <div class="cuts">${arr(c.cuts).map((x) => `<button class="cut" data-act="cut" data-v="${x.index}"><i class="fa-solid ${c.tool === 'clippers' ? 'fa-wand-magic' : 'fa-scissors'}"></i><b>${esc(x.label)}</b><span>Style ${x.drawable}</span></button>`).join('')}</div>
    <div class="note" style="margin-top:12px">They already agreed. The cut stays until they visit a barber or lose their hair.</div>
  </div>`;
}

/* ═══════════════ MODAL ═══════════════ */
function modal(html, tint) {
  const m = $('#modal');
  m.innerHTML = `<div class="m-box" style="${tint ? tintVars(tint) : ''}"><div class="ch-frame"><div class="ch-in">${html}</div></div></div>`;
  m.hidden = false;
}
function closeModal() { const m = $('#modal'); m.hidden = true; m.innerHTML = ''; }
$('#modal').addEventListener('click', (e) => {
  if (e.target.id === 'modal') closeModal(); // buttons inside bubble up to the #app handler
});

function confirmBox(title, text, okLabel, onOk, tint = '#08afa2') {
  modal(`<h4>${title}</h4><p>${text}</p><div class="m-actions"><button class="btn ghost" data-act="mclose">Cancel</button><button class="btn teal" data-act="mok">${okLabel}</button></div>`, tint);
  ACT.mok = () => { closeModal(); onOk(); };
}

let offerState = null;
async function offerModal(key) {
  const w = arr(S.vault.wigs).find((x) => x.key === key);
  if (!w) return;
  offerState = { key, target: null, gift: false, players: [] };
  modal(`<h4>Sell or gift</h4><p>${esc(w.length + '" ' + w.style)} · they get a prompt to accept.</p><div class="pick" id="offPick"><div class="empty" style="padding:16px"><i class="fa-solid fa-circle-notch fa-spin"></i></div></div>`, tier(w.tier).color);
  const list = arr(await post('nearby'));
  offerState.players = list;
  renderOffer(w);
}
function renderOffer(w) {
  const o = offerState;
  const box = $('.m-box .ch-in'); if (!box) return;
  box.innerHTML = `<h4>Sell or gift</h4><p>${esc(w.length + '" ' + w.style)} · they get a prompt to accept.</p>
    <div class="pick">${o.players.length ? o.players.map((p) => `<button class="${o.target === p.src ? 'on' : ''}" data-act="opick" data-v="${p.src}"><span class="dot on"></span>${esc(p.name)}<small>${p.dist}m</small></button>`).join('')
      : '<div class="empty" style="padding:16px"><i class="fa-solid fa-user-group"></i>Nobody close enough</div>'}</div>
    <div class="toggle"><span>Gift it (free)</span><button class="sw ${o.gift ? 'on' : ''}" data-act="ogift"><i></i></button></div>
    ${o.gift ? '' : `<div class="binput"><label class="field"><i class="fa-solid fa-dollar-sign"></i><input id="oPrice" data-int placeholder="Price" value="${o.price || ''}"></label></div>`}
    <div class="m-actions"><button class="btn ghost" data-act="mclose">Cancel</button><button class="btn teal" data-act="osend" ${o.target ? '' : 'disabled'}><i class="fa-solid fa-paper-plane"></i>Send offer</button></div>`;
}

/* ═══════════════ ACTIONS ═══════════════ */
const ACT = {
  close: () => closeApp(),
  mclose: () => closeModal(),
  tab: (v) => { S.tab = v; S.bountyOpen = null; renderVault(); },
  lb: (v) => { S.lb = v; $('#vview').innerHTML = VIEWS.leaders(); },
  wsel: (v) => { S.sel = v; $('#vview').innerHTML = VIEWS.wigs(); },
  wear: (v) => { post('wear', { key: v }); closeApp(true); },
  unwear: () => { post('unwear'); closeApp(true); },
  repair: (v) => { post('repair', { key: v }); },
  offer: (v) => offerModal(v),
  opick: (v) => { const w = arr(S.vault.wigs).find((x) => x.key === offerState.key); offerState.price = ($('#oPrice') || {}).value; offerState.target = Number(v); renderOffer(w); },
  ogift: () => { const w = arr(S.vault.wigs).find((x) => x.key === offerState.key); offerState.price = ($('#oPrice') || {}).value; offerState.gift = !offerState.gift; renderOffer(w); },
  osend: async () => {
    const o = offerState; if (!o || !o.target) return;
    const price = o.gift ? 0 : Number(($('#oPrice') || {}).value || 0);
    closeModal();
    const r = await post('offer', { target: o.target, key: o.key, price });
    if (r && r.ok) loadVault();
  },
  bountyToggle: (v) => { S.bountyOpen = S.bountyOpen === v ? null : v; $('#vview').innerHTML = VIEWS.bounties(); const i = $('#bAmt'); i && i.focus(); },
  bountyPlace: (v) => {
    const amt = Number(($('#bAmt') || {}).value || 0);
    const cfg = S.vault.bountyCfg || {};
    const r = arr(S.vault.revenge).find((x) => x.identifier === v);
    if (!amt || amt < cfg.min || amt > cfg.max) { toast({ kind: 'error', message: `Bounty must be between ${money(cfg.min)} and ${money(cfg.max)}` }); return; }
    const net = Math.floor(amt * (1 - (cfg.fee || 0)));
    confirmBox('Place bounty', `Pay <b style="color:var(--white)">${money(amt)}</b> to put <b style="color:var(--white)">${money(net)}</b> on ${esc(r ? r.name : 'them')}. Whoever snatches them next collects it.`, 'Place bounty', async () => {
      const res = await post('placeBounty', { identifier: v, amount: amt });
      if (res && res.ok) { S.bountyOpen = null; loadVault(); }
    }, '#e5484d');
  },
  fsel: (v) => { S.fenceSel.has(v) ? S.fenceSel.delete(v) : S.fenceSel.add(v); renderFence(); },
  fall: () => { const w = arr(S.fence.wigs); if (S.fenceSel.size === w.length) S.fenceSel.clear(); else w.forEach((x) => S.fenceSel.add(x.key)); renderFence(); },
  sell: () => {
    const keys = [...S.fenceSel];
    const total = arr(S.fence.wigs).filter((w) => S.fenceSel.has(w.key)).reduce((a, w) => a + w.value, 0);
    const go = async () => {
      const r = await post('fenceSell', { keys });
      if (r && r.ok && r.result) {
        SFX.cash();
        S.fence.wigs = r.result.wigs; S.fence.market = r.result.market;
        S.fenceSel.clear();
        if (S.view === 'fence') renderFence();
      }
    };
    keys.length > 1 ? confirmBox('Sell wigs', `Sell ${keys.length} wigs for about <b style="color:var(--white)">${money(total)}</b>?`, 'Sell', go) : go();
  },
  restore: () => post('barberRestore'),
  brepair: (v) => post('barberRepair', { key: v }),
  cut: (v) => { post('cutPick', { index: Number(v) }); closeApp(true); },
};

/* ═══════════════ PROMPT ═══════════════ */
let pqT = 0, pqId = null;
function promptOpen(d) {
  pqId = d.id;
  const icon = d.kind === 'haircut' ? (d.tool === 'clippers' ? 'fa-wand-magic' : 'fa-scissors') : 'fa-handshake';
  let wig = '';
  if (d.wig) {
    const w = d.wig;
    wig = `<div class="pq-wig">${wigCard(Object.assign({}, w, { key: 'pq' }), false, false).replace('data-act="wsel"', '')}</div>`;
  }
  const box = $('#prompt');
  box.innerHTML = `<div class="pq"><div class="ch-frame"><div class="ch-in">
    <div class="pq-b"><div class="ti tint"><i class="fa-solid ${icon}"></i></div><div class="pq-tx"><h4>${esc(d.title)}</h4><p>${esc(d.body)}</p></div></div>
    ${wig}
    <div class="pq-f"><div class="prog"></div>
      <button class="btn red" data-pq="0"><i class="fa-solid fa-xmark"></i>Decline</button>
      <button class="btn teal" data-pq="1"><i class="fa-solid fa-check"></i>${d.price ? 'Pay ' + money(d.price) : 'Accept'}</button></div>
  </div></div></div>`;
  box.hidden = false;
  const dur = (d.timeout || 20) * 1000;
  $('.pq-f .prog', box).animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }], { duration: dur, easing: 'linear', fill: 'forwards' });
  SFX.toast();
  clearTimeout(pqT);
  pqT = setTimeout(() => promptReply(false), dur);
}
function promptReply(accept) {
  if (pqId === null) return;
  const id = pqId;
  pqId = null;
  clearTimeout(pqT);
  $('#prompt').hidden = true;
  post('promptReply', { id, accept });
}
function promptClose() { pqId = null; clearTimeout(pqT); $('#prompt').hidden = true; }
$('#prompt').addEventListener('click', (e) => {
  const b = e.target.closest('[data-pq]');
  if (b) promptReply(b.dataset.pq === '1');
});

/* ═══════════════ MESSAGES ═══════════════ */
const HANDLERS = {
  toast, banner, levelup, speech, progress,
  sound: (d) => playSound(d.name, d.volume, d.duration),
  'clash:start': clashStart, 'clash:tick': clashTick, 'clash:end': clashEnd,
  reveal,
  'app:open': (d) => openApp(d.view, d.data),
  'app:close': () => closeApp(true),
  'app:refresh': (d) => {
    if (S.view === 'vault') loadVault();
    else if (S.view === 'barber') post('barberFetch').then((b) => { if (b && S.view === 'barber') { S.barber = b; renderBarber(); } });
  },
  'prompt:open': promptOpen,
  'prompt:close': promptClose,
};

addEventListener('message', (e) => {
  const m = e.data || {};
  const h = HANDLERS[m.action];
  if (h) h(m.data || {});
});

/* ═══════════════ BOOT ═══════════════ */
(async function boot() {
  let cfg = null;
  for (let i = 0; i < 6 && !cfg; i++) {
    cfg = await post('ready');
    if (!cfg) await new Promise((r) => setTimeout(r, 1000));
  }
  if (cfg) {
    S.cfg = Object.assign(S.cfg, cfg);
    arr(cfg.tiers).forEach((t) => (S.tiers[t.id] = t));
    S.cfg.tiers = arr(cfg.tiers);
    $('#toasts').dataset.pos = cfg.notifyPosition || 'top-right';
  }
})();

window.WS = { handle: (action, data) => HANDLERS[action] && HANDLERS[action](data || {}), S };
