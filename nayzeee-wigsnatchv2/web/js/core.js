/* ═══════════════════════════════════════════════════════════
   WIG SNATCH V3 · NUI core
   helpers · preferences · audio · toasts · banners · reveal · prompts
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
const pct = (v) => Math.round((Number(v) || 0) * 100) + '%';

function hexRgb(hex) {
  const h = String(hex || '#08afa2').replace('#', '');
  const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
function mix(hex, to, k) {
  const a = hexRgb(hex), b = hexRgb(to);
  return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * k).toString(16).padStart(2, '0')).join('');
}
function luminance(hex) {
  const [r, g, b] = hexRgb(hex).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function tintVars(hex) {
  const [r, g, b] = hexRgb(hex);
  return `--c:${hex};--cw:rgba(${r},${g},${b},.11);--ce:rgba(${r},${g},${b},.34);--cg:rgba(${r},${g},${b},.17);--cs:rgba(${r},${g},${b},.38);--cf:rgba(${r},${g},${b},.06);--cc:${hex}`;
}

const S = {
  cfg: { version: '3.1.0', tiers: [], grades: [], games: {}, tools: [], statuses: {} },
  tiers: {}, grades: {},
  prefs: { accent: '#08afa2', alert: '#e5484d', scale: 1, toastPos: 'top-right', sounds: true, volume: 0.7, reduceMotion: false, banners: 'all', keyPull: 'Space', keyMashL: 'KeyA', keyMashR: 'KeyD', editable: true, presets: [] },
  skew: 0,
  view: null, timer: 0,
};

function tier(id) { return S.tiers[id] || { id, label: id || 'Wig', color: '#a7aeb3' }; }
function tierStyle(id) { return tintVars(tier(id).color); }
function gradeLabel(id) { return (S.grades[id] || {}).label || id || 'Hair'; }
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
  if (code.startsWith('Arrow')) return { ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→' }[code] || code;
  return code.toUpperCase();
}

/* ─────────────── preferences ─────────────── */
function applyPrefs(p) {
  if (!p) return;
  S.prefs = Object.assign({}, S.prefs, p);
  const P = S.prefs, st = document.documentElement.style;
  const set = (name, hex) => {
    const [r, g, b] = hexRgb(hex);
    st.setProperty(`--${name}`, hex);
    st.setProperty(`--${name}-rgb`, `${r},${g},${b}`);
    st.setProperty(`--${name}-hi`, mix(hex, '#ffffff', 0.2));
    st.setProperty(`--${name}-lo`, mix(hex, '#000000', 0.3));
    st.setProperty(`--${name}-wash`, `rgba(${r},${g},${b},.11)`);
    st.setProperty(`--${name}-edge`, `rgba(${r},${g},${b},.34)`);
  };
  set('teal', P.accent);
  set('red', P.alert);
  st.setProperty('--on-accent', luminance(P.accent) > 0.38 ? '#061413' : '#ffffff');
  document.body.classList.toggle('calm', !!P.reduceMotion);
  $('#toasts').dataset.pos = P.toastPos || 'top-right';
  rescale();
}

function rescale() {
  const s = clamp(Math.min(innerHeight / 1080, innerWidth / 1920), 0.6, 2) * clamp(Number(S.prefs.scale) || 1, 0.8, 1.25);
  document.documentElement.style.setProperty('--z', s);
}
addEventListener('resize', rescale);
rescale();

/* ─────────────── audio ─────────────── */
let AC = null;
function ac() { if (!AC) { try { AC = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) {} } return AC; }
function vol() { return S.prefs.sounds === false ? 0 : clamp(Number(S.prefs.volume ?? 0.7), 0, 1); }
function tone(freq, dur = 0.08, type = 'sine', v = 0.05, slide = 0) {
  const a = ac(); if (!a || !vol()) return;
  const o = a.createOscillator(), g = a.createGain();
  o.type = type; o.frequency.value = freq;
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(40, freq + slide), a.currentTime + dur);
  g.gain.setValueAtTime(v * vol(), a.currentTime);
  g.gain.exponentialRampToValueAtTime(0.0001, a.currentTime + dur);
  o.connect(g); g.connect(a.destination);
  o.start(); o.stop(a.currentTime + dur + 0.02);
}
// short filtered noise burst (snips, razor scrapes)
function noise(dur = 0.06, v = 0.08, freq = 4000, q = 2, type = 'bandpass') {
  const a = ac(); if (!a || !vol()) return;
  const n = Math.floor(a.sampleRate * dur), buf = a.createBuffer(1, n, a.sampleRate), d = buf.getChannelData(0);
  for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / n);
  const s = a.createBufferSource(), f = a.createBiquadFilter(), g = a.createGain();
  s.buffer = buf; f.type = type; f.frequency.value = freq; f.Q.value = q;
  g.gain.value = v * vol();
  s.connect(f); f.connect(g); g.connect(a.destination);
  s.start();
}
const SFX = {
  hit: () => { tone(660, 0.06, 'triangle', 0.06); tone(990, 0.05, 'sine', 0.03); },
  miss: () => tone(160, 0.14, 'sawtooth', 0.04, -60),
  tick: () => tone(1200, 0.03, 'sine', 0.02),
  key: () => tone(880, 0.03, 'square', 0.02),
  win: () => { [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => tone(f, 0.16, 'triangle', 0.05), i * 70)); },
  lose: () => { [392, 330, 262].forEach((f, i) => setTimeout(() => tone(f, 0.2, 'sawtooth', 0.03), i * 90)); },
  toast: () => tone(880, 0.05, 'sine', 0.025),
  cash: () => { tone(1318, 0.06, 'square', 0.025); setTimeout(() => tone(1760, 0.09, 'square', 0.02), 60); },
  reveal: (rank) => { const base = 392 + rank * 60; [0, 4, 7, 12].forEach((s, i) => setTimeout(() => tone(base * Math.pow(2, s / 12), 0.22, 'triangle', 0.045), i * 80)); },
  start: () => { tone(300, 0.1, 'square', 0.03); setTimeout(() => tone(450, 0.12, 'square', 0.03), 110); },
  snip: () => { noise(0.035, 0.22, 5200, 3); setTimeout(() => noise(0.03, 0.18, 6400, 4), 45); },
  razor: () => noise(0.16, 0.1, 2600, 0.8, 'highpass'),
  struggle: () => tone(220 + Math.random() * 60, 0.05, 'triangle', 0.03),
};

const FILES = { clippers: 'clippers', scissors: 'scissors' };
const loops = new Map();
// one-shot positional sound: real files where we have them, synthesized otherwise
function playSound(name, volume = 0.6, duration = 700) {
  if (SFX[name] && !FILES[name]) {
    const reps = Math.max(1, Math.round(duration / 260));
    for (let i = 0; i < reps; i++) setTimeout(() => SFX[name](), i * 240);
    return;
  }
  const file = FILES[name] || name;
  const a = new Audio(`sounds/${file}.ogg`);
  a.volume = clamp(volume * vol(), 0, 1);
  a.play().catch(() => {});
  setTimeout(() => {
    const step = () => { a.volume = Math.max(0, a.volume - 0.08); if (a.volume > 0.01) setTimeout(step, 30); else a.pause(); };
    step();
  }, Math.max(200, duration - 250));
}
// held sound (clippers while the mouse is down)
function loopSound(name, on) {
  let a = loops.get(name);
  if (on) {
    if (!a) { a = new Audio(`sounds/${FILES[name] || name}.ogg`); a.loop = true; loops.set(name, a); }
    a.volume = clamp(0.55 * vol(), 0, 1);
    if (a.paused) a.play().catch(() => {});
  } else if (a && !a.paused) {
    a.pause(); a.currentTime = 0;
  }
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
  let icon = 'fa-hand', html = '', color = S.prefs.accent;
  if (p.kind === 'snatch') {
    color = p.color || tier(p.tier).color;
    html = `<b>${esc(p.actor)}</b> snatched <b>${esc(p.target)}</b>'s <em>${esc(p.label || p.tierLabel + ' wig')}</em>`;
  } else if (p.kind === 'steal') {
    icon = 'fa-rotate-left'; color = p.color || S.prefs.accent;
    html = `<b>${esc(p.actor)}</b> took their <em>${esc(p.label || 'wig')}</em> back from <b>${esc(p.target)}</b>`;
  } else if (p.kind === 'streak') {
    icon = 'fa-fire'; color = '#e5a50a';
    html = `<b>${esc(p.actor)}</b> is on a <em>${esc(p.streak)} snatch streak</em>`;
  } else if (p.kind === 'bounty') {
    icon = 'fa-crosshairs'; color = S.prefs.alert;
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

/* ═══════════════ LEVEL UP / SPEECH / PROGRESS / HINT / STRUGGLE ═══════════════ */
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
    time.textContent = Math.max(0, (dur - (t - t0)) / 1000).toFixed(1) + 's';
    if (k < 1) prRaf = requestAnimationFrame(step); else el.hidden = true;
  };
  prRaf = requestAnimationFrame(step);
}

function hint(d) {
  const el = $('#hint');
  if (!d.show) { el.hidden = true; return; }
  el.innerHTML = `<div class="ch-frame"><div class="ch-in">${arr(d.keys).map((k) => `<span class="kc">${esc(k)}</span>`).join('')}<span>${esc(d.text || '')}</span></div></div>`;
  el.hidden = false;
}

function struggle(d) {
  const el = $('#struggle');
  if (d.hide) { el.hidden = true; return; }
  if (d.kind) {
    el.dataset.kind = d.kind;
    el.innerHTML = `<div class="ch-frame"><div class="ch-in">
      <div class="st-top"><span class="st-title"><i class="fa-solid ${d.kind === 'tied' ? 'fa-link' : 'fa-people-pulling'}"></i>${d.kind === 'tied' ? 'Tied up' : 'Being held'}</span>
        ${d.show === false ? '' : '<span class="st-keys"><span class="kc">A</span><span class="kc">D</span>Struggle</span>'}</div>
      <div class="st-bar"><i></i></div></div></div>`;
    el.hidden = false;
  }
  if (d.value !== undefined) {
    const i = $('.st-bar i', el);
    if (i) i.style.width = clamp(d.value * 100, 0, 100) + '%';
    if (d.value < 1) { SFX.struggle(); el.classList.remove('jolt'); void el.offsetWidth; el.classList.add('jolt'); }
  }
}

/* ═══════════════ REVEAL ═══════════════ */
let rvT = 0;
function wigVisual(w, cls = 'rv-glyph') {
  if (w && w.image) return `<div class="${cls} photo"><img src="${esc(w.image)}" alt="" onerror="this.parentNode.classList.remove('photo');this.remove()"><i class="fa-solid ${w.kind === 'bundle' ? 'fa-wind' : 'fa-crown'}"></i></div>`;
  return `<div class="${cls}"><i class="fa-solid ${w && w.kind === 'bundle' ? 'fa-wind' : 'fa-crown'}"></i></div>`;
}
function reveal(r) {
  const w = r.wig || {};
  const t = tier(w.tier);
  const rank = Math.max(0, S.cfg.tiers.findIndex((x) => x.id === w.tier));
  const chips = [];
  if (r.xp) chips.push(`<span class="chip t-success"><i class="fa-solid fa-arrow-up"></i>+${num(r.xp)} rep</span>`);
  if (r.streak > 1) chips.push(`<span class="chip t-warning"><i class="fa-solid fa-fire"></i>${r.streak} streak</span>`);
  if (r.blind) chips.push(`<span class="chip"><i class="fa-solid fa-eye-slash"></i>Blindside</span>`);
  if (r.revenge) chips.push(`<span class="chip t-error"><i class="fa-solid fa-rotate-left"></i>Revenge</span>`);
  if (r.steal) chips.push(`<span class="chip t-success"><i class="fa-solid fa-rotate-left"></i>Taken back</span>`);
  if (r.crafted) chips.push(`<span class="chip t-success"><i class="fa-solid fa-screwdriver-wrench"></i>Handmade</span>`);
  if (r.bounty) chips.push(`<span class="chip t-success"><i class="fa-solid fa-crosshairs"></i>Bounty ${money(r.bounty)}</span>`);
  if (r.newStyle) chips.push(`<span class="chip" style="${tintVars(S.prefs.accent)}"><i class="fa-solid fa-book-open"></i>New in catalog</span>`);
  if (r.worn) chips.push(`<span class="chip"><i class="fa-solid fa-masks-theater"></i>It was a wig</span>`);
  const box = $('#reveal');
  box.setAttribute('style', tintVars(t.color));
  box.innerHTML = `<div class="rv-frame"><div class="rv-in">
    ${wigVisual(w)}
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

/* ═══════════════ PROMPT ═══════════════ */
let pqT = 0, pqId = null;
function promptOpen(d) {
  pqId = d.id;
  const icons = { haircut: 'fa-scissors', cut: 'fa-scissors', puton: 'fa-hat-wizard', takeoff: 'fa-hand-sparkles', trade: 'fa-handshake' };
  let wig = '';
  if (d.wig) wig = `<div class="pq-wig">${goodCard(Object.assign({}, d.wig, { key: 'pq' }), { plain: true })}</div>`;
  const box = $('#prompt');
  box.innerHTML = `<div class="pq"><div class="ch-frame"><div class="ch-in">
    <div class="pq-b"><div class="ti tint"><i class="fa-solid ${icons[d.kind] || 'fa-circle-question'}"></i></div><div class="pq-tx"><h4>${esc(d.title)}</h4><p>${esc(d.body)}</p></div></div>
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

/* ═══════════════ GOODS (wigs + bundles) ═══════════════ */
function condColor(c) { return c >= 70 ? S.prefs.accent : c >= 40 ? '#e5a50a' : S.prefs.alert; }

function goodTitle(w) {
  if (w.generic) return w.kind === 'bundle' ? 'Hair bundle' : 'Wig';
  return `${w.length}" ${w.style}`;
}
function goodSub(w) {
  if (w.generic) return 'Unmarked';
  if (w.kind === 'bundle') return `${gradeLabel(w.grade)} hair · from ${w.from || 'unknown'}`;
  const bits = [w.lace];
  if (w.dyed) bits.push('dyed');
  if (w.burnt) bits.push('burnt');
  if (w.hops) bits.push(`${w.hops + 1} owners`);
  return bits.filter(Boolean).join(' · ');
}
function goodColor(w) { return w.kind === 'bundle' ? '#c9a27a' : tier(w.tier).color; }
function goodTag(w) { return w.kind === 'bundle' ? gradeLabel(w.grade) : tier(w.tier).label; }

// opts: { act, selected, checked, value (right text), plain }
function goodCard(w, opts = {}) {
  const c = goodColor(w);
  const act = opts.plain ? '' : `data-act="${opts.act || 'wsel'}" data-v="${esc(w.key)}"`;
  const cond = w.kind === 'bundle' ? null : (w.cond ?? 100);
  return `<button class="wig ${opts.selected ? 'on' : ''} ${opts.checked ? 'sel' : ''} ${w.image ? 'has-img' : ''}" style="${tintVars(c)}" ${act}>
    ${opts.check ? '<span class="check"><i class="fa-solid fa-check"></i></span>' : ''}
    ${w.image ? `<div class="wig-img"><img src="${esc(w.image)}" alt="" onerror="this.parentNode.remove()"></div>` : ''}
    <div class="wig-top"><span class="tier">${esc(goodTag(w))}</span>${opts.check ? '' : `<span class="wig-val">${opts.value !== undefined ? opts.value : money(w.value)}</span>`}</div>
    <div class="wig-name">${esc(goodTitle(w))}</div>
    <div class="wig-sub">${esc(goodSub(w))}</div>
    ${cond === null ? `<div class="cond"><span class="swatch" data-hc="${w.color ?? ''}"></span><span class="grow">${w.length || '-'}" length</span><span>${opts.check ? money(w.value) : ''}</span></div>`
      : `<div class="cond"><div class="cond-bar"><i style="width:${cond}%;--cc:${condColor(cond)}"></i></div><span>${opts.check ? money(w.value) : cond + '%'}</span></div>`}
  </button>`;
}

/* hair colour swatches need the game's palette */
S.palette = null;
async function palette() {
  if (S.palette) return S.palette;
  const p = await post('hairPalette');
  S.palette = arr(p).length ? arr(p) : ['#1c1f21', '#272a2c', '#312e2c', '#35261c', '#4b321f', '#5c3b24', '#6d4c35', '#6b503b'];
  return S.palette;
}
function paintSwatches(root = document) {
  if (!S.palette) return;
  $$('[data-hc]', root).forEach((el) => {
    const i = Number(el.dataset.hc);
    if (el.dataset.hc !== '' && S.palette[i]) el.style.background = S.palette[i];
  });
}
