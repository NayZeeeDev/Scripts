/* ════════════════════════════════════════════════════════════════════════
   NAYZEEE v5 · racing NUI — core
   No build step. Pages render to strings, events are delegated.
   ════════════════════════════════════════════════════════════════════════ */
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nayzeee-racing';
const $app = document.getElementById('app');
const $modal = document.getElementById('modal');
const $toasts = document.getElementById('toasts');

let T = {};
const S = {
  open: false, booted: false, cfg: null, profile: null, canTracks: false, canEvents: false, activeLobby: null,
  settings: {}, locales: { en: 'English' }, page: 'home', history: [], inbox: 0, busy: null,
  lobbies: null, lobby: null, tracks: null, board: null, crew: null, viewProfile: null, rooms: new Set(),
  f: {},        // form state for the current page / modal
};

// ── i18n / format ───────────────────────────────────────────────────────
function t(key, ...args) {
  let s = T[key] != null ? String(T[key]) : key;
  let i = 0;
  return s.replace(/%%|%[sd]|%\.\df/g, m => (m === '%%' ? '%' : (args[i] != null ? args[i++] : '')));
}
const esc = v => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const loc = () => T['CURRENCY_LOCALE'] || 'en-US';
function money(n, currency) {
  n = Math.round(Number(n) || 0);
  if (currency === 'crypto') return `${n.toLocaleString(loc())} ${t('CRYPTO_SYMBOL')}`;
  try { return new Intl.NumberFormat(loc(), { style: 'currency', currency: T['CURRENCY_CODE'] || 'USD', maximumFractionDigits: 0 }).format(n); }
  catch (e) { return '$' + n.toLocaleString(); }
}
const num = (n, d = 0) => (Number(n) || 0).toLocaleString(loc(), { maximumFractionDigits: d, minimumFractionDigits: 0 });
function clock(ms, short) {
  if (ms == null || isNaN(ms)) return '—';
  ms = Math.max(0, Math.floor(ms));
  const m = Math.floor(ms / 60000), s = Math.floor(ms % 60000 / 1000), x = ms % 1000;
  if (short) return `${m}:${String(s).padStart(2, '0')}.${String(Math.floor(x / 10)).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}.${String(x).padStart(3, '0')}`;
}
function dist(m) {
  m = Number(m) || 0;
  if (S.settings.units === 'mph') { const mi = m / 1609.344; return mi >= 0.1 ? `${num(mi, 1)} mi` : `${num(m * 1.09361)} yd`; }
  return m >= 1000 ? `${num(m / 1000, 1)} km` : `${num(m)} m`;
}
function hours(sec) {
  sec = Math.floor(Number(sec) || 0);
  const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}
function ago(ts) {
  if (!ts) return '—';
  const s = Date.now() / 1000 - Number(ts);
  if (s < 60) return t('UI_JUST_NOW');
  if (s < 3600) return t('UI_MIN_AGO', Math.floor(s / 60));
  if (s < 86400) return t('UI_HOUR_AGO', Math.floor(s / 3600));
  return t('UI_DAY_AGO', Math.floor(s / 86400));
}
const ordinal = n => `${n}${t('ORD_' + (n % 100 >= 11 && n % 100 <= 13 ? 'th' : ['th', 'st', 'nd', 'rd'][n % 10] || 'th'))}`;
const initials = s => String(s || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase() || '?';

function hexToRgb(hex) {
  const m = /^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i.exec(hex || '');
  return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : null;
}
function applyTheme(accent, danger, scale, hudScale) {
  const root = document.documentElement.style;
  const a = hexToRgb(accent);
  if (a) {
    const mix = (c, f) => c.map(v => Math.max(0, Math.min(255, Math.round(v * f))));
    root.setProperty('--teal', accent);
    root.setProperty('--teal-hi', `rgb(${mix(a, 1.21).join(',')})`);
    root.setProperty('--teal-lo', `rgb(${mix(a, 0.72).join(',')})`);
    root.setProperty('--teal-wash', `rgba(${a.join(',')},.11)`);
    root.setProperty('--teal-edge', `rgba(${a.join(',')},.34)`);
  }
  const r = hexToRgb(danger);
  if (r) {
    root.setProperty('--red', danger);
    root.setProperty('--red-wash', `rgba(${r.join(',')},.11)`);
    root.setProperty('--red-edge', `rgba(${r.join(',')},.34)`);
  }
  if (scale && scale !== 1) { $app.style.zoom = scale; $modal.style.zoom = scale; }
  if (hudScale) root.setProperty('--hud', hudScale);
}

// ── transport ───────────────────────────────────────────────────────────
async function post(name, data) {
  if (window.__NZR_MOCK__) return window.__NZR_MOCK__(name, data);
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}) });
    return await r.json();
  } catch (e) { return null; }
}
async function req(name, data) {
  const res = (await post('req', { name, data: data || {} })) || { error: 'ERR_GENERIC' };
  return res;
}
// Request with busy state + error toast. Returns data or null.
async function call(name, data, opts = {}) {
  if (S.busy) return null;
  S.busy = opts.busy || name;
  render();
  const res = await req(name, data);
  S.busy = null;
  if (res.error) {
    let msg = t(res.error);
    if (res.extra && res.extra.length) msg += ` — ${res.extra.join(', ')}`;
    toast(msg, true);
    render();
    return null;
  }
  if (opts.success) toast(opts.success);
  render();
  return res.data === undefined ? true : res.data;
}
const busy = k => S.busy === k;

function joinRoom(room) { if (S.rooms.has(room)) return; S.rooms.add(room); req('room:join', { room }); }
function leaveRooms(keep = []) {
  for (const r of [...S.rooms]) if (!keep.includes(r)) { S.rooms.delete(r); req('room:leave', { room: r }); }
}

// ── toasts ──────────────────────────────────────────────────────────────
function toast(text, err, ms = 4000) {
  const el = document.createElement('div');
  el.className = 'toast' + (err ? ' err' : '');
  el.style.setProperty('--dur', ms + 'ms');
  el.innerHTML = `<div class="ti"><i class="fas ${err ? 'fa-xmark' : 'fa-check'}"></i></div><div><b>${esc(err ? t('UI_ERROR') : t('UI_DONE'))}</b><p>${esc(text)}</p></div>`;
  $toasts.appendChild(el);
  while ($toasts.children.length > 4) $toasts.firstChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 220); }, ms);
}

// ── fragments ───────────────────────────────────────────────────────────
function btn(label, a, cls = 'btn-line', o = {}) {
  const attrs = Object.entries(o.data || {}).map(([k, v]) => `data-${k}="${esc(v)}"`).join(' ');
  const spin = o.busyKey && busy(o.busyKey);
  const dis = o.disabled || (S.busy && !o.free);
  return `<button class="btn ${cls} ${o.size || ''} ${o.full ? 'full' : ''}" data-a="${a}" ${attrs} ${dis ? 'disabled' : ''}>${spin ? '<span class="spinner"></span>' : (o.icon ? `<i class="${o.icon}"></i>` : '')}${esc(label)}</button>`;
}
function stat(label, value, icon, tone = '', small = '') {
  return `<div class="stat"><div class="tile ${tone}"><i class="${icon}"></i></div><div class="stat-txt"><span>${esc(label)}</span><b>${value}${small ? `<small>${esc(small)}</small>` : ''}</b></div></div>`;
}
function empty(icon, title, text, action = '') {
  return `<div class="empty"><i class="${icon}"></i><b>${esc(title)}</b>${text ? `<span>${esc(text)}</span>` : ''}${action}</div>`;
}
function skeleton(n = 4) {
  return Array.from({ length: n }, () => `<div class="skel"><div class="sk sq"></div><div style="flex:1;display:flex;flex-direction:column;gap:6px"><div class="sk" style="height:9px;width:55%"></div><div class="sk" style="height:7px;width:35%"></div></div></div>`).join('');
}
function avatar(p, cls = '', opts = {}) {
  if (!p) return `<div class="av ${cls}">?</div>`;
  const ini = esc(initials(p.alias || p.name));
  const inner = p.avatar ? `<img src="${esc(p.avatar)}" onerror="this.replaceWith('${ini.replace(/'/g, '')}')">` : ini;
  return `<div class="av ${cls} ${opts.online ? 'online' : ''}" style="--c:${esc(p.color || 'var(--teal)')}">${inner}<span class="ring"></span></div>`;
}
function crewTag(c) {
  if (!c) return '';
  return `<span class="crewtag" style="color:${esc(c.color)};border-color:${esc(c.color)}55;background:${esc(c.color)}18">${esc(c.tag)}</span>`;
}
function posBadge(pos, status) {
  if (status === 'eliminated') return `<div class="pos out">${pos}</div>`;
  if (status && status !== 'finished') return `<div class="pos dnf">DNF</div>`;
  return `<div class="pos ${pos <= 3 ? 'p' + pos : ''}">${pos}</div>`;
}
function eloDelta(d) {
  if (d == null || d === 0) return '';
  return `<span class="delta ${d > 0 ? 'up' : 'down'}">${d > 0 ? '+' : ''}${d}</span>`;
}
function rankOf(elo) {
  const ranks = (S.cfg && S.cfg.ELO.Ranks) || [];
  let r = ranks[0] || { name: '—', min: 0, max: 1000 }, i = 0;
  ranks.forEach((x, k) => { if (elo >= x.min) { r = x; i = k; } });
  return { rank: r, index: i, next: ranks[i + 1] || null };
}
function rankProgress(elo) {
  const { rank, next } = rankOf(elo);
  if (!next) return 100;
  return Math.max(0, Math.min(100, (elo - rank.min) / (next.min - rank.min) * 100));
}
function statusTag(status) {
  const map = { pending: 'live', mobilizing: 'warn', countdown: 'warn', racing: 'hot', finished: 'off', cancelled: 'off' };
  return `<span class="tag ${map[status] || 'off'}">${esc(t('LOBBY_STATUS_' + status))}</span>`;
}
function modeIcon(m) { return { standard: 'fas fa-flag-checkered', drift: 'fas fa-wind', time_trial: 'fas fa-stopwatch', elimination: 'fas fa-skull' }[m] || 'fas fa-flag-checkered'; }
function typeIcon(ty) { return { ranked: 'fas fa-trophy', crew: 'fas fa-people-group', unranked: 'fas fa-road', practice: 'fas fa-stopwatch' }[ty] || 'fas fa-road'; }
function visIcon(v) { return { public: 'fas fa-globe', private: 'fas fa-lock', crew: 'fas fa-people-group' }[v] || 'fas fa-globe'; }
// "2d 4h" / "3h 10m" until a unix time
function timeLeft(ts) {
  const s = Math.max(0, Number(ts) - Date.now() / 1000);
  const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
  return d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${m}m` : `${m}m`;
}
function badge(b) {
  const def = ((S.cfg && S.cfg.Seasons && S.cfg.Seasons.Badges) || {})[b.badge] || { label: b.badge, icon: 'medal', color: '#08afa2' };
  return `<span class="sbadge" style="color:${esc(def.color)};border-color:${esc(def.color)}66;background:${esc(def.color)}1c" title="${esc(t('SEASON_BADGE_TIP', b.season, b.position))}"><i class="fas fa-${esc(def.icon)}"></i>S${esc(b.season)} · ${esc(def.label)}</span>`;
}
function vImage(v) {
  const url = v && (v.image || (S.cfg && S.cfg.General.VehicleImagesUrl && v.name ? S.cfg.General.VehicleImagesUrl.replace('{car}', v.name) : null));
  return url ? `<img src="${esc(url)}" onerror="this.outerHTML='<i class=&quot;fas fa-car-side&quot;></i>'">` : '<i class="fas fa-car-side"></i>';
}

// ── map ─────────────────────────────────────────────────────────────────
function activeMap() {
  const M = S.maps;
  if (!M || !M.List) return null;
  const id = S.settings.mapStyle && M.List[S.settings.mapStyle] ? S.settings.mapStyle : M.Default;
  const m = M.List[id];
  return m && (m.image || m.stream) && m.bounds ? m : null;
}

// Game texture as an image URL (streamed .ytd). The preview build swaps these for local files.
function nuiImg(dict, tex) {
  const k = `${dict}/${tex}`;
  return (window.__NUIIMG && window.__NUIIMG[k]) || `https://nui-img/${k}`;
}
const fmtTile = (pattern, r, c) => String(pattern).replace('%d', r).replace('%d', c);

// Tiles of a map in world space (single image or a streamed grid)
function mapTiles(m) {
  const b = m.bounds, W = b.maxX - b.minX, H = b.maxY - b.minY;
  if (!m.stream) return [{ href: m.image, x: b.minX, y: -b.maxY, w: W, h: H }];
  const rows = m.stream.rows || 3, cols = m.stream.cols || 2, tw = W / cols, th = H / rows, out = [];
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    out.push({ href: nuiImg(fmtTile(m.stream.dict, r, c), fmtTile(m.stream.texture, r, c)), x: b.minX + c * tw, y: -b.maxY + r * th, w: tw, h: th });
  }
  return out;
}

// Small thumbnail of a whole map (settings picker)
function mapThumb(m) {
  const b = m.bounds;
  const tiles = mapTiles(m).map(t => `<image href="${esc(t.href)}" x="${t.x}" y="${t.y}" width="${t.w + 1}" height="${t.h + 1}" preserveAspectRatio="none"/>`).join('');
  return `<svg viewBox="${b.minX} ${-b.maxY} ${b.maxX - b.minX} ${b.maxY - b.minY}" preserveAspectRatio="xMidYMid meet">${tiles}</svg>`;
}

// Track outline from preview points [[x,y],...] (world coords), drawn over the GTA map
function trackSvg(points, circuit, h = 120) {
  if (!points || points.length < 2) return `<div class="tmap" style="height:${h}px"></div>`;
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const [x, y] of points) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
  // world box around the track, padded and fitted to a 16:9 frame
  let w = Math.max(maxX - minX, 200), hh = Math.max(maxY - minY, 200);
  const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  w *= 1.3; hh *= 1.3;
  const ratio = 300 / 170;
  if (w / hh < ratio) w = hh * ratio; else hh = w / ratio;
  const vb = `${(cx - w / 2).toFixed(1)} ${(-cy - hh / 2).toFixed(1)} ${w.toFixed(1)} ${hh.toFixed(1)}`;
  const r = w * 0.011;
  const P = points.map(([x, y]) => [x, -y]);
  const d = P.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ') + (circuit ? ' Z' : '');
  const dots = P.slice(1, circuit ? undefined : -1).map(p => `<circle class="cp" cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="${(r * 0.55).toFixed(1)}"/>`).join('');
  const s0 = P[0], f = P[P.length - 1];
  const map = activeMap();
  const img = map ? `${mapTiles(map).map(t => `<image href="${esc(t.href)}" x="${t.x.toFixed(1)}" y="${t.y.toFixed(1)}" width="${(t.w + 1).toFixed(1)}" height="${(t.h + 1).toFixed(1)}" preserveAspectRatio="none"/>`).join('')}
    <rect class="shade" x="${map.bounds.minX}" y="${-map.bounds.maxY}" width="${map.bounds.maxX - map.bounds.minX}" height="${map.bounds.maxY - map.bounds.minY}"/>` : '';
  return `<div class="tmap ${map ? 'has-map' : ''}" style="height:${h}px"><svg viewBox="${vb}" preserveAspectRatio="xMidYMid meet">
    ${img}<path class="glow" d="${d}" vector-effect="non-scaling-stroke"/><path class="line" d="${d}" vector-effect="non-scaling-stroke"/>${dots}
    ${circuit ? '' : `<circle class="fi" cx="${f[0].toFixed(1)}" cy="${f[1].toFixed(1)}" r="${r.toFixed(1)}"/>`}
    <circle class="st" cx="${s0[0].toFixed(1)}" cy="${s0[1].toFixed(1)}" r="${(r * 1.1).toFixed(1)}"/></svg></div>`;
}

// ── avatars (DiceBear) ──────────────────────────────────────────────────
const AVATAR_PARTS = {
  'avataaars-neutral': {
    eyes: ['default', 'closed', 'cry', 'eyeRoll', 'happy', 'hearts', 'side', 'squint', 'surprised', 'wink', 'winkWacky', 'xDizzy'],
    eyebrows: ['default', 'defaultNatural', 'angry', 'angryNatural', 'flatNatural', 'frownNatural', 'raisedExcited', 'raisedExcitedNatural', 'sadConcerned', 'sadConcernedNatural', 'unibrowNatural', 'upDown', 'upDownNatural'],
    mouth: ['default', 'smile', 'twinkle', 'serious', 'tongue', 'concerned', 'disbelief', 'eating', 'grimace', 'sad', 'screamOpen', 'vomit'],
  },
  'pixel-art': {
    eyes: ['variant01', 'variant02', 'variant03', 'variant04', 'variant05', 'variant06', 'variant07', 'variant08', 'variant09', 'variant10', 'variant11', 'variant12'],
    mouth: ['happy01', 'happy02', 'happy03', 'happy04', 'happy05', 'happy06', 'happy07', 'happy08', 'happy09', 'happy10', 'happy11', 'happy12', 'happy13', 'sad01', 'sad02', 'sad03', 'sad04', 'sad05'],
  },
  'fun-emoji': {
    eyes: ['closed', 'closed2', 'crying', 'cute', 'glasses', 'love', 'pissed', 'plain', 'sad', 'shades', 'sleepClose', 'stars', 'tearDrop', 'wink', 'wink2'],
    mouth: ['cute', 'drip', 'faceMask', 'kissHeart', 'lilSmile', 'pissed', 'plain', 'sad', 'shout', 'shy', 'sick', 'smileLol', 'smileTeeth', 'tongueOut', 'wideSmile'],
  },
};
function avatarUrl(a) {
  const q = new URLSearchParams({ seed: a.seed || 'racer', backgroundColor: (a.color || '#08afa2').replace('#', '') });
  for (const [k, v] of Object.entries(a.parts || {})) if (v) q.set(k, v);
  return `https://api.dicebear.com/9.x/${a.style}/svg?${q.toString()}`;
}
function parseAvatar(url) {
  const m = /api\.dicebear\.com\/\d+\.x\/([\w-]+)\/svg\?(.*)$/.exec(url || '');
  if (!m) return null;
  const q = new URLSearchParams(m[2]);
  const parts = {};
  for (const k of Object.keys(AVATAR_PARTS[m[1]] || {})) if (q.get(k)) parts[k] = q.get(k);
  return { style: m[1], seed: q.get('seed') || 'racer', parts };
}
const randSeed = () => Math.random().toString(36).slice(2, 10);

// ── modal helpers ───────────────────────────────────────────────────────
let MODAL = null;   // { render(), on: {} }
function openModal(m) { MODAL = m; renderModal(); }
function closeModal(value) {
  const m = MODAL;
  MODAL = null;
  $modal.innerHTML = '';
  if (m && m.resolve) m.resolve(value);
}
function renderModal() {
  if (!MODAL) { $modal.innerHTML = ''; return; }
  const ae = document.activeElement;
  const fid = ae && ae.id && $modal.contains(ae) ? ae.id : null;
  let s0, s1;
  if (fid) { try { s0 = ae.selectionStart; s1 = ae.selectionEnd; } catch (e) { /* noop */ } }
  const sc = {};
  $modal.querySelectorAll('[data-scroll]').forEach(el => { sc[el.dataset.scroll] = el.scrollTop; });
  $modal.innerHTML = `<div class="overlay" data-a="modalBg">${MODAL.render()}</div>`;
  $modal.querySelectorAll('[data-scroll]').forEach(el => { if (sc[el.dataset.scroll] != null) el.scrollTop = sc[el.dataset.scroll]; });
  if (fid) { const el = document.getElementById(fid); if (el) { el.focus(); try { if (s0 != null) el.setSelectionRange(s0, s1); } catch (e) { /* noop */ } } }
}
function confirmBox({ title, text, ok, danger = true, icon }) {
  return new Promise(resolve => openModal({
    resolve,
    render: () => `<div class="modal"><div class="modal-b"><div class="micon ${danger ? '' : 'teal'}"><i class="${icon || (danger ? 'fas fa-triangle-exclamation' : 'fas fa-circle-question')}"></i></div>
      <div><h5>${esc(title)}</h5><p>${esc(text || '')}</p></div></div>
      <div class="modal-f">${btn(t('UI_CANCEL'), 'modalNo', 'btn-line', { free: true })}${btn(ok || t('UI_CONFIRM'), 'modalYes', danger ? 'btn-red' : 'btn-teal', { free: true })}</div></div>`,
    on: { modalYes: () => closeModal(true), modalNo: () => closeModal(null) },
  }));
}
function promptBox({ title, text, value = '', max = 32, placeholder = '', ok, type = 'text' }) {
  return new Promise(resolve => {
    openModal({
      resolve,
      render: () => `<div class="modal"><div class="modal-b"><div class="micon teal"><i class="fas fa-pen"></i></div>
        <div><h5>${esc(title)}</h5>${text ? `<p>${esc(text)}</p>` : ''}
        <div class="field"><input id="prompt-in" type="${type}" maxlength="${max}" value="${esc(value)}" placeholder="${esc(placeholder)}"></div></div></div>
        <div class="modal-f">${btn(t('UI_CANCEL'), 'modalNo', 'btn-line', { free: true })}${btn(ok || t('UI_SAVE'), 'modalVal', 'btn-teal', { free: true })}</div></div>`,
      on: { modalNo: () => closeModal(null), modalVal: () => closeModal(document.getElementById('prompt-in').value) },
    });
    const inp = document.getElementById('prompt-in');
    inp.focus();
    inp.addEventListener('keydown', e => { if (e.key === 'Enter') closeModal(inp.value); });
  });
}

// ── event delegation ────────────────────────────────────────────────────
const ACT = {};
function setPath(obj, path, val) {
  const keys = path.split('.');
  let o = obj;
  for (let i = 0; i < keys.length - 1; i++) { if (o[keys[i]] == null) o[keys[i]] = {}; o = o[keys[i]]; }
  o[keys[keys.length - 1]] = val;
}
function onClick(e, inModal) {
  const el = e.target.closest('[data-a]');
  if (!el || el.disabled) return;
  const a = el.dataset.a;
  if (a === 'modalBg') { if (e.target === el && MODAL && !MODAL.sticky) closeModal(null); return; }
  const fn = (inModal && MODAL && MODAL.on && MODAL.on[a]) || ACT[a];
  if (fn) { e.preventDefault(); fn(el.dataset, el, e); }
}
$app.addEventListener('click', e => onClick(e, false));
$modal.addEventListener('click', e => onClick(e, true));
function onField(e, inModal) {
  const el = e.target;
  if (!el.dataset || !el.dataset.m) return;
  let v = el.value;
  if (el.type === 'checkbox') v = el.checked;
  if (el.dataset.t === 'num') v = el.value === '' ? '' : Number(el.value);
  if (el.dataset.t === 'upper') { v = v.toUpperCase().replace(/[^A-Z0-9]/g, ''); el.value = v; }
  setPath(S, el.dataset.m, v);
  if (el.dataset.on && ACT[el.dataset.on]) ACT[el.dataset.on](el.dataset, el);
  if (el.dataset.r !== undefined) (inModal ? renderModal() : render());
}
$app.addEventListener('input', e => onField(e, false));
$modal.addEventListener('input', e => onField(e, true));
$app.addEventListener('change', e => { if (e.target.tagName === 'SELECT') onField(e, false); });
$modal.addEventListener('change', e => { if (e.target.tagName === 'SELECT') onField(e, true); });

// Debounce helper for search / availability checks
const debouncers = {};
function debounce(key, ms, fn) { clearTimeout(debouncers[key]); debouncers[key] = setTimeout(fn, ms); }

// ── render root ─────────────────────────────────────────────────────────
function render() {
  if (!S.open) return;
  const sc = {};
  $app.querySelectorAll('[data-scroll]').forEach(el => { sc[el.dataset.scroll] = el.scrollTop; });
  const ae = document.activeElement;
  const fid = ae && ae.id && $app.contains(ae) ? ae.id : null;
  let s0, s1;
  if (fid) { try { s0 = ae.selectionStart; s1 = ae.selectionEnd; } catch (e) { /* noop */ } }
  $app.innerHTML = window.renderApp ? window.renderApp() : '';
  $app.querySelectorAll('[data-scroll]').forEach(el => { if (sc[el.dataset.scroll] != null) el.scrollTop = sc[el.dataset.scroll]; });
  if (fid) { const el = document.getElementById(fid); if (el) { el.focus(); try { if (s0 != null) el.setSelectionRange(s0, s1); } catch (e) { /* noop */ } } }
  if (MODAL) renderModal();
}

// ── open / close / messages ─────────────────────────────────────────────
async function openApp(d) {
  S.open = true;
  if (d && d.settings) S.settings = d.settings;
  $app.className = 'on';
  render();
  const res = await req('boot');
  if (res.data) {
    S.booted = true;
    S.cfg = res.data.config;
    S.profile = res.data.profile;
    S.canTracks = res.data.canTracks;
    S.canEvents = res.data.canEvents;
    S.activeLobby = res.data.activeLobby || null;
    S.season = res.data.season || null;
    if (!S.profile) S.page = 'signup';
    else if (S.page === 'signup') S.page = 'home';
    if (S.profile) req('inbox:count').then(r => { S.inbox = r.data || 0; render(); });
  }
  if (window.enterPage) window.enterPage(S.page, true);
  render();
}
function closeApp(fromGame) {
  if (!S.open) return;
  S.open = false;
  leaveRooms();
  if (MODAL) closeModal(null);
  $app.className = '';
  $app.innerHTML = '';
  if (!fromGame) post('close');
}
ACT.close = () => closeApp();

const PUSH = {};
window.addEventListener('message', e => {
  const m = e.data || {};
  const d = m.data;
  switch (m.action) {
    case 'open': openApp(d); break;
    case 'close': closeApp(true); break;
    case 'toast': if (S.open) toast(d.text, d.kind === 'error'); break;
    case 'push': {
      const fn = PUSH[d.channel] || (d.channel.startsWith('lobby:') ? PUSH.lobby : null);
      if (fn) fn(d.data, d.channel);
      break;
    }
    default: if (window.HUD && window.HUD[m.action]) window.HUD[m.action](d);
  }
});
document.addEventListener('keydown', e => {
  if (e.key !== 'Escape') return;
  if (MODAL) { if (!MODAL.sticky) closeModal(null); return; }
  if (S.open) closeApp();
});

// ── boot ────────────────────────────────────────────────────────────────
(async () => {
  const r = await post('ready');
  if (r) {
    T = r.locale || {};
    S.settings = r.settings || {};
    S.locales = r.locales || S.locales;
    S.maps = r.maps || null;
    applyTheme(r.accent, r.danger, r.scale, r.hudScale);
  }
})();
