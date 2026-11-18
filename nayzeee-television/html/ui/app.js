/* ═══════════════════════════════════════════════════════════
   NAYZEEE Television — NUI (media panel · remote · admin · HUD)
   ═══════════════════════════════════════════════════════════ */
'use strict';

const IN_GAME = typeof window.GetParentResourceName === 'function';
const RES = IN_GAME ? window.GetParentResourceName() : 'nayzeee-television';
const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const fmt = (t) => {
  if (!isFinite(t) || t < 0) t = 0;
  t = Math.floor(t);
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(s).padStart(2, '0');
};
const initials = (n) => String(n || '?').trim().split(/\s+/).map((p) => p[0]).join('').slice(0, 2).toUpperCase();

async function post(name, data) {
  if (!IN_GAME) return DEMO.post(name, data || {});
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}) });
    const t = await r.text();
    return t ? JSON.parse(t) : null;
  } catch (e) { return null; }
}

let clockOffset = 0;
const setClock = (now) => { if (typeof now === 'number') clockOffset = now - Date.now(); };
const serverNow = () => Date.now() + clockOffset;
const mediaPos = (m) => (m ? (m.paused ? (m.pausedAt || 0) : Math.max(0, (serverNow() - m.startedAt) / 1000)) : 0);

/* ─────────────── icons ─────────────── */
const I = {
  tv: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="m8 2.5 4 3.5 4-3.5M8 21h8"/></svg>',
  play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.5v15l13-7.5z"/></svg>',
  pause: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4.5" width="4" height="15" rx="1"/><rect x="14" y="4.5" width="4" height="15" rx="1"/></svg>',
  next: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M5 5v14l10-7zM16.5 5h2.5v14h-2.5z"/></svg>',
  prev: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M19 5v14L9 12zM5 5h2.5v14H5z"/></svg>',
  stop: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>',
  loop: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3l3 3-3 3"/><path d="M4 11V9a3 3 0 0 1 3-3h13M7 21l-3-3 3-3"/><path d="M20 13v2a3 3 0 0 1-3 3H4"/></svg>',
  vol: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9.5h3.5L12 5v14l-4.5-4.5H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/></svg>',
  mute: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9.5h3.5L12 5v14l-4.5-4.5H4z"/><path d="m16 9.5 5 5M21 9.5l-5 5"/></svg>',
  power: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 3v8"/><path d="M6.6 6.6a8 8 0 1 0 10.8 0"/></svg>',
  plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  minus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 12h14"/></svg>',
  x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5 9 17.5 20 6.5"/></svg>',
  up: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="m6 15 6-6 6 6"/></svg>',
  down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>',
  left: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="m15 6-6 6 6 6"/></svg>',
  right: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6"/></svg>',
  back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/></svg>',
  home: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><path d="M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5h-5v5H5a1 1 0 0 1-1-1z"/></svg>',
  playpause: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><path d="M4 6v12l8-6z"/><path d="M15 6v12M19 6v12" stroke-linecap="round"/></svg>',
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="3"/><path d="M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"/></svg>',
  source: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8M12 17v4"/></svg>',
  kbd: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="2.5" y="6" width="19" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></svg>',
  link: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M10 14a4.2 4.2 0 0 0 6 0l3-3a4.2 4.2 0 0 0-6-6l-1 1"/><path d="M14 10a4.2 4.2 0 0 0-6 0l-3 3a4.2 4.2 0 0 0 6 6l1-1"/></svg>',
  queue: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M4 6h12M4 11h12M4 16h7"/><path d="m15 14 5 3-5 3z" fill="currentColor"/></svg>',
  history: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 12a8.5 8.5 0 1 0 2.5-6L3.5 8.5"/><path d="M3.5 3.5v5h5M12 7.5V12l3 2"/></svg>',
  star: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>',
  starF: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>',
  grid: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>',
  display: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M9 21h6M12 17v4M7 13l3-3 2 2 4-4"/></svg>',
  lock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>',
  unlock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 7.5-2"/></svg>',
  users: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7M21.5 20a6.5 6.5 0 0 0-4-6"/></svg>',
  chain: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="2.5" y="8" width="9" height="8" rx="4"/><rect x="12.5" y="8" width="9" height="8" rx="4"/></svg>',
  remote: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="7" y="2.5" width="10" height="19" rx="4"/><circle cx="12" cy="9" r="2.2"/><path d="M10 15h.01M14 15h.01M12 18h.01"/></svg>',
  hand: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12M11 11V4a1.5 1.5 0 0 1 3 0v7M14 11V5.5a1.5 1.5 0 0 1 3 0V14a7 7 0 0 1-7 7h-.6a6 6 0 0 1-4.6-2.2L2.6 15a1.6 1.6 0 0 1 2.3-2.2L8 15"/></svg>',
  trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/></svg>',
  pin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 21s-6.5-5.8-6.5-11a6.5 6.5 0 0 1 13 0c0 5.2-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/></svg>',
  move: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18M3 12h18M9 6l3-3 3 3M9 18l3 3 3-3M6 9l-3 3 3 3M18 9l3 3-3 3"/></svg>',
  edit: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/></svg>',
  wall: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="3" y="5" width="18" height="11" rx="1"/><path d="M3 20h18M7 16v4M17 16v4"/></svg>',
  target: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2.5"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></svg>',
  ruler: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="m3 17 14-14 4 4L7 21z"/><path d="m7 13 2 2M10 10l2 2M13 7l2 2"/></svg>',
  box: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><path d="M12 3 3.5 7.5v9L12 21l8.5-4.5v-9z"/><path d="M3.5 7.5 12 12l8.5-4.5M12 12v9"/></svg>',
  alert: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 9v5M12 17.5v.01"/><path d="M10.3 3.9 2.5 17.5A2 2 0 0 0 4.2 20.5h15.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/></svg>',
  refresh: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/></svg>',
  eye: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
  film: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/></svg>',
  yt: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><rect x="2.5" y="5.5" width="19" height="13" rx="4"/><path d="m10 9 5 3-5 3z" fill="currentColor"/></svg>',
  tw: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="2.2" fill="currentColor"/><path d="M8.2 8.2a5.4 5.4 0 0 0 0 7.6M15.8 8.2a5.4 5.4 0 0 1 0 7.6M5.3 5.3a9.5 9.5 0 0 0 0 13.4M18.7 5.3a9.5 9.5 0 0 1 0 13.4"/></svg>',
  kk: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M13.5 2.5 5 13.5h6l-1.5 8 8.5-11h-6z"/></svg>',
  music: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M9 18V5.5l11-2V16"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/></svg>',
  image: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2.5"/><circle cx="9" cy="9.5" r="1.7"/><path d="m4 18 5.5-5.5 4 4L16 14l4.5 4.5"/></svg>',
};
const KIND = {
  youtube: { label: 'YouTube', icon: 'yt' }, twitch: { label: 'Twitch', icon: 'tw' }, kick: { label: 'Kick', icon: 'kk' },
  hls: { label: 'Live stream', icon: 'tw' }, video: { label: 'Video', icon: 'film' }, audio: { label: 'Audio', icon: 'music' }, image: { label: 'Image', icon: 'image' },
};
const BRANDS = window.BRANDS || {};
['tiktok', 'vimeo', 'soundcloud', 'streamable', 'medal', 'instagram', 'dailymotion', 'reddit', 'rumble', 'plex', 'pluto'].forEach((k) => {
  if (!KIND[k]) KIND[k] = { label: BRANDS[k] ? BRANDS[k].name : k, icon: 'film' };
});
/* transparent platform logo (brand colour by default) */
function logo(kind, brand, size, color) {
  const b = brand && BRANDS[brand] ? brand : BRANDS[kind] ? kind : null;
  if (!b) return I[(KIND[kind] || KIND.video).icon].replace('<svg ', `<svg width="${size || 16}" height="${size || 16}" `);
  const c = color || (['tiktok', 'dailymotion'].includes(b) ? '#fff' : BRANDS[b].color);
  return window.brandSvg(b, size || 16, c);
}
const klabel = (kind, brand) => (brand && BRANDS[brand] ? BRANDS[brand].name : (KIND[kind] || KIND.video).label);
/* every platform the TVs can play, shown as a logo strip */
const PLATFORMS = ['youtube', 'tiktok', 'twitch', 'kick', 'vimeo', 'soundcloud', 'streamable', 'medal', 'instagram', 'dailymotion', 'reddit', 'rumble', 'pluto', 'plex'];

/* link detection — mirrors shared/utils.lua for instant feedback */
function detect(raw) {
  const u = String(raw || '').trim();
  if (!u) return null;
  if (/^local:/i.test(u)) return { kind: 'video', label: 'Server library' };
  if (/(youtube\.com|youtu\.be)/i.test(u)) return { kind: 'youtube', label: /[?&]list=/.test(u) && !/[?&]v=/.test(u) ? 'YouTube playlist' : /\/live\//.test(u) ? 'YouTube live' : 'YouTube video' };
  if (/twitch\.tv/i.test(u)) return { kind: 'twitch', label: /\/videos\//.test(u) ? 'Twitch VOD' : /clip/.test(u) ? 'Twitch clip' : 'Twitch live channel' };
  if (/kick\.com/i.test(u)) return { kind: 'kick', label: 'Kick live channel' };
  if (/tiktok\.com/i.test(u)) return { kind: 'tiktok', label: 'TikTok video' };
  if (/vimeo\.com/i.test(u)) return { kind: 'vimeo', label: 'Vimeo video' };
  if (/soundcloud\.com/i.test(u)) return { kind: 'soundcloud', label: /\/sets\//.test(u) ? 'SoundCloud playlist' : 'SoundCloud track' };
  if (/streamable\.com/i.test(u)) return { kind: 'streamable', label: 'Streamable clip' };
  if (/medal\.tv/i.test(u)) return { kind: 'medal', label: 'Medal clip' };
  if (/instagram\.com\/(p|reel|reels|tv)\//i.test(u)) return { kind: 'instagram', label: 'Instagram post' };
  if (/dailymotion\.com|dai\.ly/i.test(u)) return { kind: 'dailymotion', label: 'Dailymotion video' };
  if (/reddit\.com\/.*comments|v\.redd\.it|redd\.it/i.test(u)) return { kind: 'reddit', label: 'Reddit video' };
  if (/rumble\.com/i.test(u)) return { kind: 'rumble', label: 'Rumble video' };
  if (/pluto\.tv/i.test(u) && /\.m3u8/i.test(u)) return { kind: 'hls', brand: 'pluto', label: 'Pluto TV channel' };
  if (/(watch|app)\.plex\.tv/i.test(u)) return null; // Plex's website can't be embedded — see the Live tab / Plex app
  if (/plex\.tv\/.*\.m3u8/i.test(u)) return { kind: 'hls', brand: 'plex', label: 'Plex live channel' };
  if (/X-Plex-Token|:32400/i.test(u)) return { kind: 'plex', label: 'Plex' };
  const ext = (u.split(/[?#]/)[0].match(/\.(\w+)$/) || [])[1];
  if (!ext || !/^https?:\/\//i.test(u)) return null;
  const e = ext.toLowerCase();
  if (e === 'm3u8') return { kind: 'hls', label: 'HLS live stream' };
  if (/^(mp4|webm|ogv|mov|m4v)$/.test(e)) return { kind: 'video', label: 'Video file' };
  if (/^(mp3|wav|ogg|m4a|aac|flac|opus)$/.test(e)) return { kind: 'audio', label: 'Audio file' };
  if (/^(png|jpe?g|gif|webp|avif)$/.test(e)) return { kind: 'image', label: 'Image' };
  return null;
}

/* ─────────────── UI sound (soft tick for the remote) ─────────────── */
let actx = null;
function tick(freq = 1900, dur = 0.025, vol = 0.05) {
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const o = actx.createOscillator(), g = actx.createGain();
    o.type = 'triangle'; o.frequency.value = freq;
    g.gain.setValueAtTime(vol, actx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, actx.currentTime + dur);
    o.connect(g).connect(actx.destination);
    o.start(); o.stop(actx.currentTime + dur);
  } catch (e) {}
}

/* ═══════════════ TOASTS ═══════════════ */
function toast(text, kind = 'info', title) {
  const box = $('#toasts');
  const el = document.createElement('div');
  const err = kind === 'error';
  el.className = 'toast' + (err ? ' error' : '');
  el.innerHTML = `<div class="ti">${err ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M12 8v5M12 16.5v.01"/><circle cx="12" cy="12" r="9"/></svg>' : I.check}</div>
    <div><b>${esc(title || (err ? 'Television' : 'Television'))}</b><p>${esc(text)}</p></div>`;
  box.appendChild(el);
  while (box.children.length > 4) box.firstChild.remove();
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, 4200);
}

/* ═══════════════ PROMPT & PLACEMENT ═══════════════ */
function renderPrompt(d) {
  const el = $('#prompt');
  if (!d || !d.show) { el.innerHTML = ''; return; }
  el.innerHTML = `<div class="prompt"><div class="mark"></div><div class="pr-txt"><b>${esc(d.title)}</b><span>${esc(d.sub || '')}</span></div>
    <div class="pr-keys">${(d.keys || []).map((k) => `<span><span class="key">${esc(k.key)}</span>${esc(k.label)}</span>`).join('')}</div></div>`;
}

function renderPlacement(d) {
  const el = $('#placement');
  if (!d || !d.show) { el.innerHTML = ''; return; }
  el.innerHTML = `<div class="place">
    <div class="place-card"><div class="mark"></div><div><b>${esc(d.title)}</b><span>${esc(d.sub || '')}</span></div>
      <span class="place-state tag ${d.valid ? 'live' : 'hot'}">${d.valid ? 'Valid spot' : 'Find a surface'}</span>
      ${d.snap === undefined ? '' : `<span class="tag ${d.snap ? 'live' : 'off'}">Wall snap ${d.snap ? 'on' : 'off'}</span>`}</div>
    <div class="place-keys">${(d.keys || []).map((k) => `<span><span class="key">${esc(k.key)}</span>${esc(k.label)}</span>`).join('')}</div></div>`;
}

/* ═══════════════ MODAL ═══════════════ */
function modal({ title, text, confirm = 'Confirm', cancel = 'Cancel', danger = false, input = null, placeholder = '', value = '' }) {
  return new Promise((resolve) => {
    const el = $('#modal');
    el.innerHTML = `<div class="modal-wrap"><div class="modal"><div class="modal-b"><div class="warn ${danger ? '' : 'teal'}">${danger ? I.alert : I.info}</div>
      <div style="flex:1;min-width:0"><h4>${esc(title)}</h4><p>${esc(text || '')}</p>
      ${input ? `<div class="field"><label>${esc(input)}</label><input id="mInput" placeholder="${esc(placeholder)}" value="${esc(value)}"></div>` : ''}</div></div>
      <div class="modal-f"><button class="btn-line" data-m="0">${esc(cancel)}</button><button class="${danger ? 'btn-red' : 'btn-teal'}" data-m="1">${esc(confirm)}</button></div></div></div>`;
    const inp = $('#mInput');
    if (inp) { inp.focus(); inp.select(); }
    const done = (ok) => { const v = inp ? inp.value : true; el.innerHTML = ''; resolve(ok ? v : null); };
    el.querySelectorAll('[data-m]').forEach((b) => b.addEventListener('click', () => done(b.dataset.m === '1')));
    if (inp) inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') done(true); if (e.key === 'Escape') { e.stopPropagation(); done(false); } });
  });
}
const modalOpen = () => !!$('#modal').innerHTML;

/* ═══════════════ MEDIA PANEL ═══════════════ */
const P = { open: false, d: null, tv: null, view: 'now', url: '', results: [], searching: false, q: '', perms: null, linkSel: new Set(), brand: {} };

function openPanel(msg) {
  setClock(msg.now);
  P.open = true; P.d = msg.data; P.tv = msg.data.tv; P.brand = msg.brand || {};
  P.view = P.tv.media ? 'now' : 'browse';
  P.perms = msg.data.perms ? JSON.parse(JSON.stringify(msg.data.perms)) : null;
  P.linkSel = new Set((msg.data.linkable || []).filter((l) => l.linked).map((l) => l.id));
  renderPanel();
  progressLoop();
}
function closePanel(send = true) {
  P.open = false;
  $('#panel').innerHTML = '';
  if (send) post('close', { what: 'panel' });
}

const ctl = (action, data) => post('control', { id: P.tv.id, action, data });

function navBtn(id, icon, label, tally) {
  return `<button class="nav ${P.view === id ? 'on' : ''}" data-act="view" data-v="${id}">${I[icon]}${esc(label)}${tally != null ? `<span class="tally">${tally}</span>` : ''}</button>`;
}

function renderPanel() {
  if (!P.open) return;
  const t = P.tv, d = P.d;
  const role = d.isAdmin ? 'Admin' : d.isOwner ? 'Owner' : d.canManage ? 'Manager' : 'Guest';
  const linked = d.linkable ? d.linkable.filter((l) => l.linked).length : 0;
  const focus = saveFocus();
  $('#panel').innerHTML = `<div class="win-wrap"><div class="frame"><div class="shell">
    <div class="bar">
      <div class="bar-brand"><div class="mark"></div><div class="bar-name"><div class="title-txt">${esc(P.brand.product || 'Television')}</div><div class="sub">${esc(t.label)}</div></div></div>
      <div class="bar-mid"><span class="dot ${t.power ? '' : 'off'}"></span>
        <p>${t.power ? 'Connected to' : 'Standby —'} <b>${esc(t.label)}</b>${t.group ? ` · <b>${linked + 1}</b> linked screens` : ''}${t.locked ? ' · locked' : ''}</p>
        <span class="ver">v${esc(P.brand.version || '1.0.0')}</span></div>
      <div class="bar-act">
        <button class="icon-btn pwr ${t.power ? 'on' : 'off'}" data-act="power" title="Power">${I.power}</button>
        <button class="icon-btn" data-act="openRemote" title="Remote">${I.remote}</button>
        <button class="pill-close" data-act="close">Close</button>
      </div>
    </div>
    <div class="body">
      <nav class="side">
        <div class="who"><div class="av">${esc(initials(d.me))}</div><div class="who-txt"><b>${esc(d.me)}</b><span>${role} · ${esc(t.label)}</span></div></div>
        <div class="shift"><span>${t.media ? esc(t.media.title || (KIND[t.media.kind] || {}).label || 'Playing') : 'Nothing playing'}</span>
          <b class="${t.power ? '' : 'off'}"><span class="dot ${t.power ? '' : 'off'}"></span>${t.power ? (t.media ? (t.media.live ? 'Live' : t.media.paused ? 'Paused' : 'On air') : 'On') : 'Off'}</b></div>
        ${navBtn('now', 'play', 'Now Playing')}
        <div class="grp">Watch</div>
        ${navBtn('browse', 'search', 'Browse')}
        ${navBtn('queue', 'queue', 'Up Next', (t.queue || []).length)}
        ${navBtn('history', 'history', 'History', (t.history || []).length || null)}
        ${navBtn('favorites', 'star', 'Favorites', (d.favorites || []).length || null)}
        <div class="grp">Screen</div>
        ${navBtn('display', 'display', 'Display')}
        ${d.canManage ? navBtn('access', 'users', 'Access') + navBtn('links', 'chain', 'Links', t.group ? linked + 1 : null) : ''}
        <div class="side-foot">
          <button class="btn-line btn-sm w100" data-act="openRemote">${I.remote}Use remote</button>
          ${d.canManage && !t.permanent ? `<button class="btn-red btn-sm w100" data-act="pickup">${I.hand}Pick up screen</button>` : ''}
        </div>
      </nav>
      <main class="main" id="pmain">${panelView()}</main>
    </div>
    <div class="statusbar">
      <span><span class="key">ESC</span>Close</span><span><span class="key">↵</span>Play link</span><span><span class="key">⇧↵</span>Add to queue</span>
      <div class="sb-right">${t.loop ? '<span class="tag live">Repeat</span>' : ''}<span>Volume <b>${t.muted ? 'muted' : Math.round((t.volume || 0) * 100) + '%'}</b></span></div>
    </div>
  </div></div></div>`;
  restoreFocus(focus);
}

function saveFocus() {
  const a = document.activeElement;
  if (!a || !a.id || !/INPUT|TEXTAREA/.test(a.tagName)) return null;
  return { id: a.id, s: a.selectionStart, e: a.selectionEnd };
}
function restoreFocus(f) {
  if (!f) return;
  const el = document.getElementById(f.id);
  if (el) { el.focus(); try { el.setSelectionRange(f.s, f.e); } catch (e) {} }
}

function urlBar(id = 'purl') {
  const det = detect(P.url);
  return `<div><div class="url-bar"><div class="src-ic ${det ? 'ok' : ''}">${det ? logo(det.kind, det.brand, 18) : I.link}</div>
      <input id="${id}" data-input="url" placeholder="Paste a link from YouTube, TikTok, Twitch, Kick, Vimeo, SoundCloud…${P.d.search ? ' — or search YouTube' : ''}" value="${esc(P.url)}" spellcheck="false">
      ${P.d.search && P.url && !det ? `<button class="btn-line btn-sm" data-act="search">${I.search}Search</button>` : ''}
      <button class="btn-line btn-sm" data-act="queueUrl">${I.queue}Queue</button>
      <button class="btn-teal btn-sm" data-act="playUrl">${I.play}Play</button></div>
    <p class="url-hint">${det ? `Detected <b>${esc(det.label)}</b> — plays in sync for everyone nearby` : /plex\.tv/i.test(P.url) && !/\.m3u8/i.test(P.url) ? 'Plex\'s website can\'t play on TVs — use the <b>Live</b> channels or the Plex library below' : P.url ? 'Not a supported link yet' : 'Everyone near the screen sees and hears the same moment — even if they arrive late.'}</p>
    <div class="works"><span>Works with</span>${PLATFORMS.filter((k) => k !== 'plex' || P.d.plex).map((k) => `<i title="${esc(BRANDS[k] ? BRANDS[k].name : k)}">${logo(k, k, 15)}</i>`).join('')}<span>+ mp4 · m3u8 · mp3 · images</span></div></div>`;
}

function mcard(it, opts = {}) {
  return `<div class="mcard"><div class="mc-art" ${it.thumb ? `style="background-image:url('${esc(it.thumb)}')"` : ''}>${it.thumb ? `<span class="mc-logo">${logo(it.kind, it.brand, 13)}</span>` : logo(it.kind, it.brand, 28)}
      ${it.live ? '<span class="chip red">● Live</span>' : ''}${opts.num ? `<span class="mc-num">${opts.num}</span>` : ''}
      <div class="mc-act"><button data-act="queueItem" data-url="${esc(it.url)}" data-title="${esc(it.title || '')}" title="Add to queue">${I.queue}</button>
        <button data-act="playItem" data-url="${esc(it.url)}" data-title="${esc(it.title || '')}" title="Play now">${I.play}</button></div></div>
    <div class="mc-t"><b>${esc(it.title || it.url)}</b><span>${esc(it.sub || klabel(it.kind, it.brand))}</span></div></div>`;
}

function rowItem(it, i, acts) {
  const prog = it.pos && it.dur ? `<div class="row-prog"><i style="width:${clamp(it.pos / it.dur, 0, 1) * 100}%"></i></div>` : '';
  return `<div class="row">${i != null ? `<span class="idx">${i}</span>` : ''}<div class="th" ${it.thumb ? `style="background-image:url('${esc(it.thumb)}')"` : ''}>${it.thumb ? '' : logo(it.kind, it.brand, 18)}${prog}</div>
    <div class="row-txt"><b>${esc(it.title || it.url)}</b><span class="row-src">${logo(it.kind, it.brand, 11)}${esc(klabel(it.kind, it.brand))}${it.by ? ' · ' + esc(it.by) : ''}${it.pos && it.dur ? ' · ' + fmt(it.dur - it.pos) + ' left' : ''}</span></div><div class="row-act">${acts}</div></div>`;
}

function panelView() {
  const t = P.tv, d = P.d, v = P.view;
  const m = t.media;

  if (v === 'now') {
    if (!m) {
      return `<div class="head"><div><h1>Now Playing</h1><p>${t.power ? 'The screen is on the home screen.' : 'The screen is in standby — playing something turns it on.'}</p></div></div>
        <div class="empty">${I.tv}<b>Nothing is playing</b><span>Paste a link below, browse your history, or use the remote to pick something on the TV.</span></div>${urlBar()}`;
    }
    const k = { label: klabel(m.kind, m.brand) };
    const dur = m.duration || 0;
    return `<div class="head"><div><h1>Now Playing</h1><p>Synced for everyone in range of <b style="color:var(--white);font-weight:500">${esc(t.label)}</b>.</p></div>
        <div class="head-act"><button class="btn-ghost" data-act="fav" data-url="${esc(m.url)}" data-title="${esc(m.title || '')}" data-thumb="${esc(m.thumb || '')}" data-kind="${esc(m.kind)}">${isFav(m.url) ? I.starF : I.star}${isFav(m.url) ? 'Saved' : 'Favorite'}</button></div></div>
      <div class="np" style="--np-bg:url('${esc(m.thumb || '')}')">
        <div class="np-art" ${m.thumb ? `style="background-image:url('${esc(m.thumb)}')"` : ''}>${m.thumb ? '' : logo(m.kind, m.brand, 40)}${m.live ? '<span class="chip red live-b">● Live</span>' : ''}</div>
        <div class="np-info">
          <div class="np-top"><span class="chip brand-chip">${logo(m.kind, m.brand, 12)}${esc(k.label)}</span>${m.paused ? '' : '<span class="eq"><i></i><i></i><i></i><i></i></span>'}${m.paused ? '<span class="chip grey">Paused</span>' : ''}<span class="by">${m.by ? 'Started by ' + esc(m.by) : ''}${m.items ? ` · ${m.index}/${m.items.length} in playlist` : ''}</span></div>
          <h3>${esc(m.title || k.label)}</h3>
          <div class="seek"><div class="seek-bar ${m.live ? 'live' : ''}" id="seekBar" data-act="seek"><i id="seekFill"></i>${m.live ? '' : '<em id="seekKnob"></em>'}</div>
            <div class="seek-t"><span id="seekPos">${m.live ? 'LIVE' : fmt(mediaPos(m))}</span><span id="seekDur">${m.live ? '' : dur ? fmt(dur) : '--:--'}</span></div></div>
          <div class="ctrls">
            <button class="cbtn" data-act="ctl" data-a="prev" title="Previous">${I.prev}</button>
            <button class="cbtn big" data-act="ctl" data-a="toggle" title="Play / pause">${m.paused ? I.play : I.pause}</button>
            <button class="cbtn" data-act="ctl" data-a="next" title="Next">${I.next}</button>
            <button class="cbtn" data-act="ctl" data-a="stop" title="Stop">${I.stop}</button>
            <span class="sep"></span>
            <button class="cbtn ${t.loop ? 'on' : ''}" data-act="ctl" data-a="loop" title="Repeat">${I.loop}</button>
            ${(d.channels || []).length ? `<span class="sep"></span><button class="cbtn" data-act="chan" data-dir="-1" title="Channel down">${I.down}</button>
              <span class="ch-num" title="Channel">${t.channel ? 'CH ' + ((d.channels[t.channel - 1] || {}).number || t.channel) : 'CH'}</span>
              <button class="cbtn" data-act="chan" data-dir="1" title="Channel up">${I.up}</button>` : ''}
            <div class="vol"><button class="cbtn" data-act="ctl" data-a="mute">${t.muted ? I.mute : I.vol}</button>
              <div class="rng"><input type="range" min="0" max="100" value="${Math.round((t.volume || 0) * 100)}" data-input="volume"><span>${t.muted ? '—' : Math.round((t.volume || 0) * 100)}</span></div></div>
          </div>
        </div>
      </div>
      ${urlBar()}
      ${(t.queue || []).length ? `<section class="panel"><div class="p-head"><div><h2>Up Next</h2><p>${t.queue.length} queued — plays automatically</p></div><button class="btn-ghost" data-act="view" data-v="queue">${I.queue}Manage</button></div>
        <div class="p-body">${t.queue.slice(0, 3).map((e, i) => rowItem(e, i + 1, `<button class="icon-btn" data-act="ctl" data-a="qPlay" data-n="${i + 1}" title="Play now">${I.play}</button>`)).join('')}</div></section>` : ''}`;
  }

  if (v === 'browse') {
    const chans = d.channels || [], lib = d.library || [];
    if (d.plex && !P.plexLoaded) loadPlex();
    return `<div class="head"><div><h1>Browse</h1><p>YouTube, TikTok, Twitch, Kick, Vimeo, SoundCloud, Streamable, Medal, Instagram, Dailymotion, Reddit, Rumble, live-TV channels${P.d.plex ? ', your Plex library' : ''}, direct video, HLS, audio, images and server media.</p></div></div>
      ${urlBar()}
      ${P.searching ? '<div class="note">Searching YouTube…</div>' : ''}
      ${P.results.length ? `<section><div class="grp" style="margin:0 0 10px">Results for “${esc(P.q)}”</div><div class="mgrid">${P.results.map((r) => mcard({ ...r, sub: r.channel })).join('')}</div></section>` : ''}
      ${d.plex ? `<section><div class="grp" style="margin:0 0 10px">${logo('plex', 'plex', 14)}&nbsp;Plex — recently added</div>${P.plex && P.plex.length ? `<div class="mgrid">${P.plex.map((r) => mcardPlex(r)).join('')}</div>` : `<div class="mgrid">${'<div class="mcard skel-card"><div class="mc-art sk"></div><div class="mc-t"><div class="sk" style="height:9px;width:70%"></div><div class="sk" style="height:7px;width:40%;margin-top:6px"></div></div></div>'.repeat(4)}</div>`}</section>` : ''}
      ${['movie', 'music'].map((k) => { const c = (d.collections || []).filter((x) => x.kind === k); return c.length ? `<section><div class="grp" style="margin:0 0 10px">${k === 'movie' ? 'Cinema' : 'Music'}</div><div class="mgrid">${c.map((x) => mcard({ url: x.url, title: x.title, sub: (x.category || '') + (x.subtitle ? ' · ' + x.subtitle : ''), thumb: x.thumb, kind: detect(x.url) ? detect(x.url).kind : (k === 'music' ? 'audio' : 'video') })).join('')}</div></section>` : ''; }).join('')}
      ${chans.length ? `<section><div class="grp" style="margin:0 0 10px">Channels</div><div class="mgrid">${chans.slice(0, 60).map((c, i) => mcard({ url: c.url, title: c.name, kind: detect(c.url) ? detect(c.url).kind : 'hls', brand: c.brand, live: true, sub: (c.group ? c.group + ' · ' : '') + 'CH ' + (c.number || i + 1), thumb: c.thumb }, { num: c.number || i + 1 })).join('')}</div></section>` : ''}
      ${lib.length ? `<section><div class="grp" style="margin:0 0 10px">Server library</div><div class="mgrid">${lib.map((f) => mcard({ url: 'local:' + f.file, title: f.title || f.file, sub: f.subtitle || 'Server media', thumb: f.thumb, kind: detect('https://x/' + f.file) ? detect('https://x/' + f.file).kind : 'video' })).join('')}</div></section>` : ''}
      ${!chans.length && !lib.length && !P.results.length ? `<div class="empty">${I.search}<b>Paste any link to start</b><span>Tip: YouTube playlists play in order and keep everyone on the same video.</span></div>` : ''}`;
  }

  if (v === 'queue') {
    const q = t.queue || [];
    return `<div class="head"><div><h1>Up Next</h1><p>Plays automatically when the current video ends${t.loop ? ' — repeat is on' : ''}.</p></div>
        <div class="head-act">${q.length ? `<button class="btn-red btn-sm" data-act="ctl" data-a="qClear">${I.trash}Clear queue</button>` : ''}</div></div>
      ${urlBar()}
      ${q.length ? `<div class="p-body" style="padding:0">${q.map((e, i) => rowItem(e, i + 1,
        `<button class="icon-btn" data-act="qMove" data-n="${i + 1}" data-dir="-1" title="Move up" ${i === 0 ? 'disabled' : ''}>${I.up}</button>
         <button class="icon-btn" data-act="qMove" data-n="${i + 1}" data-dir="1" title="Move down" ${i === q.length - 1 ? 'disabled' : ''}>${I.down}</button>
         <button class="icon-btn" data-act="ctl" data-a="qPlay" data-n="${i + 1}" title="Play now">${I.play}</button>
         <button class="icon-btn danger" data-act="ctl" data-a="qRemove" data-n="${i + 1}" title="Remove">${I.x}</button>`)).join('')}</div>`
        : `<div class="empty">${I.queue}<b>The queue is empty</b><span>Use Queue next to any link to line up videos for the room.</span></div>`}`;
  }

  if (v === 'history') {
    const h = t.history || [];
    return `<div class="head"><div><h1>History</h1><p>What this screen played recently.</p></div>
        <div class="head-act">${h.length && d.canManage ? `<button class="btn-line btn-sm" data-act="ctl" data-a="histClear">${I.trash}Clear</button>` : ''}</div></div>
      ${h.length ? `<div class="p-body" style="padding:0">${h.map((e) => rowItem(e, null,
        `<button class="icon-btn ${isFav(e.url) ? 'on' : ''}" data-act="fav" data-url="${esc(e.url)}" data-title="${esc(e.title || '')}" data-thumb="${esc(e.thumb || '')}" data-kind="${esc(e.kind || '')}" title="Favorite">${isFav(e.url) ? I.starF : I.star}</button>
         <button class="icon-btn" data-act="queueItem" data-url="${esc(e.url)}" data-title="${esc(e.title || '')}" title="Queue">${I.queue}</button>
         <button class="icon-btn" data-act="playItem" data-url="${esc(e.url)}" data-title="${esc(e.title || '')}" data-start="${e.pos || ''}" title="${e.pos ? 'Resume at ' + fmt(e.pos) : 'Play'}">${I.play}</button>`)).join('')}</div>`
        : `<div class="empty">${I.history}<b>Nothing played yet</b><span>Everything played on this screen shows up here.</span></div>`}`;
  }

  if (v === 'favorites') {
    const f = d.favorites || [];
    return `<div class="head"><div><h1>Favorites</h1><p>Your personal saved links — available on every screen.</p></div></div>
      ${f.length ? `<div class="mgrid">${f.map((e) => mcard(e)).join('')}</div>
        <div class="p-body" style="padding:0">${f.map((e) => rowItem(e, null, `<button class="icon-btn danger" data-act="unfav" data-url="${esc(e.url)}" title="Remove">${I.x}</button>`)).join('')}</div>`
        : `<div class="empty">${I.star}<b>No favorites yet</b><span>Tap the star on anything playing or in history to save it.</span></div>`}`;
  }

  if (v === 'display') {
    const s = t.settings || {};
    const seg = (key, opts) => `<div class="segc">${opts.map(([val, lab]) => `<button class="${(s[key] || opts[0][0]) === val ? 'on' : ''}" data-act="setting" data-k="${key}" data-val="${val}">${lab}</button>`).join('')}</div>`;
    const sw = (key, on, act = 'settingBool') => `<button class="sw ${on ? 'on' : ''}" data-act="${act}" data-k="${key}" data-val="${on ? 0 : 1}"><i></i></button>`;
    return `<div class="head"><div><h1>Display</h1><p>Picture and behaviour of this screen. Changes apply for everyone watching.</p></div></div>
      <section class="panel"><div class="p-pad">
        <div class="opt"><div class="opt-t"><b>Power</b><small>${t.power ? 'The screen is on' : 'The screen is in standby'}</small></div>${sw('power', t.power, 'power')}</div>
        <div class="opt"><div class="opt-t"><b>Volume</b><small>Base volume — sound still fades with distance and walls</small></div>
          <div class="rng" style="max-width:260px"><input type="range" min="0" max="100" value="${Math.round((t.volume || 0) * 100)}" data-input="volume"><span>${Math.round((t.volume || 0) * 100)}%</span></div></div>
        <div class="opt"><div class="opt-t"><b>Picture mode</b><small>Colour and contrast</small></div>${seg('picture', (d.pictures || ['standard']).map((k) => [k, k.charAt(0).toUpperCase() + k.slice(1)]))}</div>
        <div class="opt"><div class="opt-t"><b>Sleep timer</b><small>${t.sleepAt ? 'Turns off in ' + Math.max(1, Math.ceil((t.sleepAt - serverNow()) / 60000)) + ' min' : 'Turn this screen off after a while'}</small></div>
          <div class="segc">${(d.sleepOptions || [0]).map((m) => `<button class="${(t.sleepAt ? 0 : -1) === -1 && m === 0 ? 'on' : ''}" data-act="sleep" data-m="${m}">${m ? m + 'm' : 'Off'}</button>`).join('')}</div></div>
        <div class="opt"><div class="opt-t"><b>Picture size</b><small>How video and images fill the screen</small></div>${seg('fit', [['contain', 'Fit'], ['cover', 'Fill'], ['stretch', 'Stretch']])}</div>
        <div class="opt"><div class="opt-t"><b>Repeat</b><small>Replay the current video when it ends</small></div>${sw('loop', t.loop, 'loopSw')}</div>
        <div class="opt"><div class="opt-t"><b>Ambient mode</b><small>Clock screensaver when nothing is playing</small></div>${sw('ambient', s.ambient !== false)}</div>
        <div class="opt"><div class="opt-t"><b>On-screen info</b><small>Title bar on the TV when playback changes</small></div>${sw('osd', s.osd !== false)}</div>
        ${d.canManage ? `<div class="opt"><div class="opt-t"><b>Screen name</b><small>Shown on the TV, remote and phone app</small></div>
          <div style="display:flex;gap:8px"><input class="inp" id="rename" value="${esc(t.label)}" style="width:200px"><button class="btn-line btn-sm" data-act="rename">Save</button></div></div>` : ''}
        ${d.canManage && t.kind !== 'wall' ? `<div class="opt"><div class="opt-t"><b>Remote</b><small>${t.remote ? 'Move where the remote lives' : 'Place a physical remote near this screen'}</small></div>
          <button class="btn-line btn-sm" data-act="remotePlace">${I.pin}${t.remote ? 'Move remote' : 'Place remote'}</button></div>` : ''}
      </div></section>`;
  }

  if (v === 'access' && d.canManage) {
    const p = P.perms || { public: false, jobs: {}, gangs: {} };
    const chips = (obj, kind) => Object.keys(obj || {}).map((k) => `<span class="pchip">${esc(k)} <em>${obj[k]}+</em><button data-act="permDel" data-kind="${kind}" data-name="${esc(k)}">${I.x}</button></span>`).join('') || '<span class="note">None</span>';
    return `<div class="head"><div><h1>Access</h1><p>Who can use the remote, the media panel and the phone app on this screen.</p></div>
        <div class="head-act"><button class="btn-teal btn-sm" data-act="permSave">${I.check}Save access</button></div></div>
      <section class="panel"><div class="p-pad">
        <div class="opt"><div class="opt-t"><b>Public</b><small>Anyone nearby can control it</small></div><button class="sw ${p.public ? 'on' : ''}" data-act="permPublic"><i></i></button></div>
        <div class="opt"><div class="opt-t"><b>Locked</b><small>Only you${d.isAdmin ? ' and admins' : ''} can control it — overrides everything below</small></div><button class="sw ${t.locked ? 'on' : ''}" data-act="lock"><i></i></button></div>
      </div></section>
      <div class="grid2">
        <section class="panel"><div class="p-head"><div><h2>Jobs</h2><p>Job name and minimum grade</p></div></div><div class="p-pad">
          <div class="chips-in" style="margin-bottom:12px">${chips(p.jobs, 'jobs')}</div>
          <div style="display:flex;gap:8px"><input class="inp" id="jobName" placeholder="police"><input class="inp" id="jobGrade" placeholder="0" style="width:64px"><button class="btn-line btn-sm" data-act="permAdd" data-kind="jobs">${I.plus}Add</button></div></div></section>
        <section class="panel"><div class="p-head"><div><h2>Gangs</h2><p>Gang name and minimum grade</p></div></div><div class="p-pad">
          <div class="chips-in" style="margin-bottom:12px">${chips(p.gangs, 'gangs')}</div>
          <div style="display:flex;gap:8px"><input class="inp" id="gangName" placeholder="ballas"><input class="inp" id="gangGrade" placeholder="0" style="width:64px"><button class="btn-line btn-sm" data-act="permAdd" data-kind="gangs">${I.plus}Add</button></div></div></section>
      </div>
      <section class="panel"><div class="p-pad">
        ${d.isAdmin ? `<div class="opt"><div class="opt-t"><b>ACE permission</b><small>Players with this ace can always control it</small></div><input class="inp" id="permAce" value="${esc(p.ace || '')}" placeholder="nayzeee-television.cinema" style="width:220px"></div>` : ''}
        ${(p.allowed || []).length ? `<div class="opt"><div class="opt-t"><b>Allowed players</b><small>Can always control this screen</small></div>
          <div class="chips-in" style="justify-content:flex-end;max-width:60%">${p.allowed.map((a) => `<span class="pchip">${esc(a.name)}<button data-act="disallow" data-key="${esc(a.key)}">${I.x}</button></span>`).join('')}</div></div>` : ''}
        <div class="opt"><div class="opt-t"><b>Allow a player</b><small>Give one person access by server ID</small></div>
          <div style="display:flex;gap:8px"><input class="inp" id="allowId" placeholder="ID" style="width:80px"><button class="btn-line btn-sm" data-act="allow">${I.plus}Allow</button></div></div>
      </div></section>`;
  }

  if (v === 'links' && d.canManage) {
    const list = d.linkable || [];
    return `<div class="head"><div><h1>Links</h1><p>Mirror this screen to others — bars, clubs and casinos show the exact same moment. Only the loudest screen plays sound, so there is no echo.</p></div>
        <div class="head-act">${t.group ? `<button class="btn-line btn-sm" data-act="unlink">${I.x}Unlink this screen</button>` : ''}<button class="btn-teal btn-sm" data-act="link">${I.chain}Link selected</button></div></div>
      ${list.length ? `<div class="checks">${list.map((l) => `<button class="check ${P.linkSel.has(l.id) ? 'on' : ''}" data-act="linkSel" data-id="${esc(l.id)}"><i>${P.linkSel.has(l.id) ? I.check : ''}</i>${esc(l.label)}<small>${l.linked ? 'linked' : l.group ? 'in another group' : ''}</small></button>`).join('')}</div>`
        : `<div class="empty">${I.chain}<b>No screens nearby</b><span>Screens you own within 60m show up here.</span></div>`}`;
  }
  return '';
}

async function loadPlex() {
  P.plexLoaded = true;
  const r = await post('plex', { op: 'recent' });
  P.plex = (r && r.items) || [];
  if (P.open && P.view === 'browse') renderPanel();
}
function mcardPlex(r) {
  return mcard({ url: r.url, title: r.title, sub: r.sub, thumb: r.thumb, kind: 'plex', brand: 'plex' }).replace('data-act="playItem"', `data-act="playItem" data-thumb="${esc(r.thumb || '')}" data-dur="${r.duration || ''}"`);
}

const isFav = (url) => (P.d && (P.d.favorites || []).some((f) => f.url === url));

let progRaf = 0;
function progressLoop() {
  cancelAnimationFrame(progRaf);
  const step = () => {
    if (!P.open && !R.open) return;
    const t = P.open ? P.tv : R.tv;
    const m = t && t.media;
    if (m && !m.live) {
      const pos = mediaPos(m), dur = m.duration || 0, pct = dur ? clamp(pos / dur, 0, 1) * 100 : 0;
      const f = $('#seekFill'), k = $('#seekKnob'), p = $('#seekPos');
      if (f) f.style.width = pct + '%';
      if (k) k.style.left = pct + '%';
      if (p) p.textContent = fmt(Math.min(pos, dur || pos));
      const rp = $('#rmPos');
      if (rp) rp.textContent = fmt(pos) + (dur ? ' / ' + fmt(dur) : '');
    } else if (m && m.live) {
      const f = $('#seekFill');
      if (f) f.style.width = '100%';
    }
    progRaf = requestAnimationFrame(step);
  };
  step();
}

async function playUrl(url, title, queue, extra) {
  url = (url || '').trim();
  if (!url) return;
  const r = await ctl(queue ? 'queue' : 'play', Object.assign({ url, title: title || undefined }, extra || {}));
  if (r && r.ok && !queue) { P.url = ''; P.view = 'now'; renderPanel(); }
  if (r && r.ok && queue) { P.url = ''; renderPanel(); }
}

async function doSearch() {
  P.q = P.url.trim();
  if (!P.q) return;
  P.searching = true; renderPanel();
  const r = await post('search', { q: P.q });
  P.searching = false;
  P.results = (r && r.results) || [];
  renderPanel();
}

async function toggleFav(el) {
  const item = { url: el.dataset.url, title: el.dataset.title, thumb: el.dataset.thumb || undefined, kind: el.dataset.kind || undefined };
  const r = await post('favorite', { op: isFav(item.url) ? 'remove' : 'add', item });
  if (r && r.list) { P.d.favorites = r.list; renderPanel(); }
}

const PanelActs = {
  close: () => closePanel(),
  view: (el) => { P.view = el.dataset.v; renderPanel(); },
  power: () => ctl('power'),
  openRemote: () => { closePanel(false); post('openRemote', { id: P.tv.id }); },
  pickup: async () => {
    const ok = await modal({ title: 'Pick up this screen?', text: `${P.tv.label} goes back into your inventory. Its queue and history are cleared.`, confirm: 'Pick up', danger: true });
    if (ok !== null) { closePanel(false); post('pickup', { id: P.tv.id }); }
  },
  ctl: (el) => ctl(el.dataset.a, el.dataset.n ? +el.dataset.n : undefined),
  qMove: (el) => ctl('qMove', { i: +el.dataset.n, dir: +el.dataset.dir }),
  playUrl: () => playUrl(P.url),
  queueUrl: () => playUrl(P.url, null, true),
  search: doSearch,
  playItem: (el) => playUrl(el.dataset.url, el.dataset.title, false, { start: +el.dataset.start || undefined, thumb: el.dataset.thumb || undefined, duration: +el.dataset.dur || undefined }),
  queueItem: (el) => playUrl(el.dataset.url, el.dataset.title, true),
  fav: toggleFav,
  unfav: async (el) => { const r = await post('favorite', { op: 'remove', item: { url: el.dataset.url } }); if (r && r.list) { P.d.favorites = r.list; renderPanel(); } },
  seek: (el, e) => {
    const m = P.tv.media;
    if (!m || m.live || !m.duration) return;
    const r = el.getBoundingClientRect();
    ctl('seek', clamp((e.clientX - r.left) / r.width, 0, 1) * m.duration);
  },
  setting: (el) => ctl('setting', { key: el.dataset.k, value: el.dataset.val }),
  settingBool: (el) => ctl('setting', { key: el.dataset.k, value: el.dataset.val === '1' }),
  loopSw: () => ctl('loop'),
  chan: (el) => ctl('channel', +el.dataset.dir),
  sleep: (el) => ctl('sleep', +el.dataset.m),
  rename: () => { const v = $('#rename').value.trim(); if (v) post('manage', { id: P.tv.id, op: 'rename', data: v }); },
  remotePlace: () => { closePanel(false); post('remotePlace', { id: P.tv.id }); },
  lock: () => post('manage', { id: P.tv.id, op: 'lock' }),
  permPublic: () => { P.perms.public = !P.perms.public; renderPanel(); },
  permAdd: (el) => {
    const kind = el.dataset.kind, pre = kind === 'jobs' ? 'job' : 'gang';
    const name = $('#' + pre + 'Name').value.trim().toLowerCase(), grade = parseInt($('#' + pre + 'Grade').value, 10) || 0;
    if (!name) return;
    P.perms[kind] = P.perms[kind] || {};
    P.perms[kind][name] = grade;
    renderPanel();
  },
  permDel: (el) => { delete P.perms[el.dataset.kind][el.dataset.name]; renderPanel(); },
  permSave: () => {
    const ace = $('#permAce');
    post('manage', { id: P.tv.id, op: 'perms', data: { public: !!P.perms.public, jobs: P.perms.jobs || {}, gangs: P.perms.gangs || {}, ace: ace ? ace.value.trim() : undefined } });
  },
  allow: async () => { const id = parseInt($('#allowId').value, 10); if (id) { await post('manage', { id: P.tv.id, op: 'allow', data: id }); refreshPanel(); } },
  disallow: async (el) => { await post('manage', { id: P.tv.id, op: 'disallow', data: el.dataset.key }); refreshPanel(); },
  linkSel: (el) => { const id = el.dataset.id; P.linkSel.has(id) ? P.linkSel.delete(id) : P.linkSel.add(id); renderPanel(); },
  link: async () => { await post('manage', { id: P.tv.id, op: 'link', data: [...P.linkSel] }); refreshPanel(); },
  unlink: async () => { await post('manage', { id: P.tv.id, op: 'unlink' }); refreshPanel(); },
};

async function refreshPanel() {
  const r = await post('panelRefresh', { id: P.tv.id });
  if (r && P.open) { P.d = r; P.tv = r.tv; renderPanel(); }
}

/* ═══════════════ REMOTE ═══════════════ */
const R = { open: false, tv: null, physical: false, kbd: null, channels: [] };

function openRemote(msg) {
  setClock(msg.now);
  R.open = true; R.tv = msg.tv; R.physical = !!msg.physical; R.channels = msg.channels || []; R.kbd = null;
  renderRemote();
  progressLoop();
}
function closeRemote(send = true) {
  R.open = false; R.kbd = null;
  $('#remote').innerHTML = '';
  if (send) post('close', { what: 'remote' });
}

function rk(act, icon, cls = 'round', label = '', title = '') {
  const app = cls.startsWith('app');
  return `<button class="rk ${cls}" data-rk="${act}" title="${esc(title || label)}">${icon}${label && !app ? `<span class="rk-l">${esc(label)}</span>` : ''}${app ? esc(label) : ''}</button>`;
}

function renderRemote() {
  if (!R.open) return;
  const t = R.tv, m = t.media;
  const k = m ? (KIND[m.kind] || KIND.video) : null;
  $('#remote').innerHTML = `<div class="remote-wrap">
    <div class="rm-side">
      ${R.kbd ? `<div class="rm-card kbd-card"><div class="kh"><div class="tile" style="width:28px;height:28px">${I.kbd}</div><div><b>Type on the TV</b><span>${esc(R.kbd.hint || 'Search or paste a link')}</span></div></div>
        <textarea id="kbdText" spellcheck="false" placeholder="${esc(R.kbd.hint || '')}">${esc(R.kbd.value || '')}</textarea>
        <div class="kf"><button class="btn-line btn-sm" data-rk="kbdCancel">Cancel</button><button class="btn-teal btn-sm" data-rk="kbdSend">${I.check}Send to TV</button></div></div>` : ''}
      <div class="rm-card">
        <div class="rm-pair"><div class="mark"></div><div class="txt"><b>${esc(t.label)}</b><span><span class="dot ${t.power ? '' : 'off'}" style="display:inline-block;margin-right:6px;vertical-align:middle"></span>${t.power ? 'Paired' : 'Standby'} · ${R.physical ? 'Remote in hand' : 'Virtual remote'}</span></div></div>
        ${m ? `<div class="rm-np"><div class="th" ${m.thumb ? `style="background-image:url('${esc(m.thumb)}')"` : ''}></div><div class="np-t"><b>${esc(m.title || k.label)}</b><span id="rmPos">${m.live ? '● Live' : ''}</span></div></div>` : ''}
      </div>
      <div class="rm-card"><div class="rm-keys">
        <span><span class="key">← ↑ → ↓</span>Navigate</span><span><span class="key">↵</span>OK</span>
        <span><span class="key">⌫</span>Back</span><span><span class="key">H</span>Home</span>
        <span><span class="key">+ −</span>Volume</span><span><span class="key">Space</span>Play / pause</span>
        <span><span class="key">PgUp/Dn</span>Channel</span><span><span class="key">K</span>Type a CH number</span>
      </div></div>
      <div class="rm-actions">
        <button class="btn-line btn-sm" data-rk="panel">${I.grid}Media panel</button>
        ${R.physical ? `<button class="btn-line btn-sm" data-rk="putDown">${I.hand}Put down</button>` : ''}
        <button class="pill-close" data-rk="close">Close</button>
      </div>
    </div>

    <div class="remote">
      <div class="rm-top">${rk('ctl:power', I.power, 'small power', '', 'Power')}<span class="rm-led" id="rmLed"></span>${rk('kbd', I.kbd, 'small', '', 'Keyboard')}</div>
      <div class="rm-row">${rk('key:settings', I.menu, 'small', 'Menu')}${rk('key:sources', I.source, 'small', 'Source')}${rk('key:info', I.info, 'small', 'Info')}</div>
      <div class="dpad">
        <button class="dp up" data-rk="key:up">${I.up}</button><button class="dp down" data-rk="key:down">${I.down}</button>
        <button class="dp left" data-rk="key:left">${I.left}</button><button class="dp right" data-rk="key:right">${I.right}</button>
        <button class="dp-ok" data-rk="key:ok">OK</button>
      </div>
      <div class="rm-row">${rk('key:back', I.back, 'round', 'Back')}${rk('key:home', I.home, 'round', 'Home')}${rk('ctl:toggle', I.playpause, 'round', 'Play')}</div>
      <div class="rockers">
        <div><div class="rocker"><button data-rk="ctl:volStep:1">${I.plus}</button><i></i><button data-rk="ctl:volStep:-1">${I.minus}</button></div><div class="rocker-l">VOL</div></div>
        <div class="mid-keys">${rk('ctl:mute', t.muted ? I.mute : I.vol, 'small', '', 'Mute')}${rk('ctl:stop', I.stop, 'small', '', 'Stop')}</div>
        <div><div class="rocker"><button data-rk="ctl:channel:1">${I.up}</button><i></i><button data-rk="ctl:channel:-1">${I.down}</button></div><div class="rocker-l">CH</div></div>
      </div>
      <div class="apps-keys">
        ${['youtube', 'tiktok', 'twitch', 'kick', 'soundcloud', 'vimeo'].map((b) => `<button class="rk app brand" data-rk="key:app:${b}" title="${esc(BRANDS[b] ? BRANDS[b].name : b)}">${logo(b, b, 15)}<span>${esc(BRANDS[b] ? BRANDS[b].name : b)}</span></button>`).join('')}
      </div>
      <div class="rm-row" style="margin-top:2px">${rk('key:search', I.search, 'small', 'Search')}${rk('key:app:pluto', logo('pluto', 'pluto', 17), 'small', 'Live TV')}${rk('key:app:library', I.grid, 'small', 'Library')}</div>
      <div class="rm-brand"><b>${esc((window.__brand && window.__brand.name) || 'NAYZEEE')}</b></div>
    </div>
  </div>`;
  if (R.kbd) { const ta = $('#kbdText'); ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); }
}

function flashLed() {
  const l = $('#rmLed');
  if (!l) return;
  l.classList.add('on');
  setTimeout(() => l.classList.remove('on'), 140);
}

async function remoteAct(act, el) {
  tick(act.startsWith('key:ok') ? 1500 : 1900);
  flashLed();
  if (el) { el.classList.add('press'); setTimeout(() => el.classList.remove('press'), 130); }
  const parts = act.split(':');
  if (parts[0] === 'key') return post('key', { id: R.tv.id, key: parts.slice(1).join(':') });
  if (parts[0] === 'ctl') {
    const a = parts[1];
    const data = parts[2] != null ? +parts[2] : undefined;
    return post('control', { id: R.tv.id, action: a, data });
  }
  if (act === 'kbd') { R.kbd = { value: '', hint: 'Search or paste a link' }; return renderRemote(); }
  if (act === 'kbdCancel') { R.kbd = null; return renderRemote(); }
  if (act === 'kbdSend') {
    const v = $('#kbdText').value.trim();
    R.kbd = null; renderRemote();
    if (v) post('type', { id: R.tv.id, text: v });
    return;
  }
  if (act === 'panel') { closeRemote(false); return post('openPanel', { id: R.tv.id }); }
  if (act === 'putDown') { closeRemote(false); return post('remotePutDown', {}); }
  if (act === 'close') return closeRemote();
}

const KEYMAP = {
  ArrowUp: 'key:up', ArrowDown: 'key:down', ArrowLeft: 'key:left', ArrowRight: 'key:right', Enter: 'key:ok', Backspace: 'key:back',
  h: 'key:home', H: 'key:home', i: 'key:info', I: 'key:info', s: 'key:sources', S: 'key:sources',
  '+': 'ctl:volStep:1', '=': 'ctl:volStep:1', '-': 'ctl:volStep:-1', _: 'ctl:volStep:-1', m: 'ctl:mute', M: 'ctl:mute',
  ' ': 'ctl:toggle', PageUp: 'ctl:channel:1', PageDown: 'ctl:channel:-1', p: 'ctl:power', P: 'ctl:power', k: 'kbd', K: 'kbd',
};
const RK_SEL = { 'key:up': '.dp.up', 'key:down': '.dp.down', 'key:left': '.dp.left', 'key:right': '.dp.right', 'key:ok': '.dp-ok' };

/* ═══════════════ ADMIN ═══════════════ */
const A = { open: false, d: null, props: [], cats: [], tab: 'dashboard', q: '', filter: 'all', cat: 'all', pq: '', sel: null,
  form: { label: '', range: '', defaultUrl: '', autoplay: false, loop: false, public: true, remote: true, width: 3 }, cal: null, groupSel: new Set(), edit: null, docked: false };

function openAdmin(msg) {
  setClock(msg.now);
  A.open = true; A.d = msg.data; A.props = msg.props || A.props; A.cats = msg.categories || A.cats; A.me = msg.me;
  if (msg.tab) A.tab = msg.tab;
  A.brand = msg.brand || {};
  A.logs = null;
  if (msg.calibrate) setTimeout(() => AdminActs.calStart(null, null, msg.calibrate), 50);
  renderAdmin();
}
function closeAdmin(send = true) {
  A.open = false; A.cal = null; A.docked = false;
  $('#admin').innerHTML = '';
  if (send) post('close', { what: 'admin' });
}
async function refreshAdmin() {
  const d = await post('adminRefresh', {});
  if (d && A.open) { A.d = d; renderAdmin(); }
}
const adm = async (op, data) => { const r = await post('admin', { op, data }); await refreshAdmin(); return r; };

function aNav(id, icon, label, tally) {
  return `<button class="nav ${A.tab === id ? 'on' : ''}" data-aact="tab" data-v="${id}">${I[icon]}${esc(label)}${tally != null ? `<span class="tally">${tally}</span>` : ''}</button>`;
}

function renderAdmin() {
  if (!A.open) return;
  const st = A.d.stats || {};
  const focus = saveFocus();
  const docked = A.tab === 'calibrator' && A.cal;
  $('#admin').innerHTML = `<div class="win-wrap ${docked ? 'docked' : ''}"><div class="frame admin-frame ${docked ? 'dock' : ''}"><div class="shell">
    <div class="bar">
      <div class="bar-brand"><div class="mark"></div><div class="bar-name"><div class="title-txt">Screen Manager</div><div class="sub">${esc((A.brand && A.brand.name) || 'NAYZEEE')} Television · Admin</div></div></div>
      <div class="bar-mid"><span class="dot"></span><p>Live — <b>${st.total || 0}</b> screens · <b>${st.playing || 0}</b> playing · <b>${st.viewers || 0}</b> watching</p><span class="ver">${esc(A.d.storage || '')}</span></div>
      <div class="bar-act"><button class="icon-btn" data-aact="refresh" title="Refresh">${I.refresh}</button><button class="pill-close" data-aact="close">Close</button></div>
    </div>
    <div class="body">
      <nav class="side">
        <div class="who"><div class="av">${esc(initials(A.me))}</div><div class="who-txt"><b>${esc(A.me || 'Admin')}</b><span>Administrator · ${esc(A.d.framework || '')}</span></div></div>
        ${aNav('dashboard', 'grid', 'Dashboard')}
        <div class="grp">Screens</div>
        ${aNav('screens', 'tv', 'All screens', st.total || 0)}
        ${aNav('create', 'plus', 'Create')}
        ${aNav('groups', 'chain', 'Link groups', st.groups || null)}
        <div class="grp">Tools</div>
        ${aNav('calibrator', 'ruler', 'Calibrator')}
        ${aNav('library', 'box', 'Prop library', A.props.length)}
        ${aNav('logs', 'history', 'Logs')}
      </nav>
      <main class="main">${adminView()}</main>
    </div>
    <div class="statusbar"><span><span class="key">ESC</span>Close</span><span><b>${A.props.filter((p) => p.available).length}</b> of ${A.props.length} props available</span>
      <div class="sb-right"><span>Storage <b>${esc(A.d.storage || '')}</b></span></div></div>
  </div></div></div>`;
  restoreFocus(focus);
}

function statusTag(s) {
  if (!s.power) return '<span class="tag off">Standby</span>';
  if (s.playing) return s.live ? '<span class="tag hot">● Live</span>' : s.paused ? '<span class="tag off">Paused</span>' : '<span class="tag live">Playing</span>';
  return '<span class="tag off">Home</span>';
}

function adminView() {
  const d = A.d, st = d.stats || {}, list = d.screens || [];

  if (A.tab === 'dashboard') {
    const playing = list.filter((s) => s.playing && s.power);
    return `<div class="head"><div><h1>Dashboard</h1><p>Every screen in the city — player TVs, cinema screens, venue walls and linked groups.</p></div>
        <div class="head-act"><button class="btn-red btn-sm" data-aact="stopAll">${I.stop}Stop all playback</button></div></div>
      <div class="stats">
        <div class="stat"><div class="tile">${I.tv}</div><div class="stat-txt"><span>Screens</span><b>${st.total || 0}</b></div></div>
        <div class="stat"><div class="tile">${I.play}</div><div class="stat-txt"><span>Playing now</span><b>${st.playing || 0}</b></div></div>
        <div class="stat"><div class="tile white">${I.eye}</div><div class="stat-txt"><span>Players watching</span><b>${st.viewers || 0}</b></div></div>
        <div class="stat"><div class="tile">${I.chain}</div><div class="stat-txt"><span>Link groups</span><b>${st.groups || 0}</b></div></div>
      </div>
      <section class="panel"><div class="p-head"><div><h2>On air</h2><p>Screens playing right now</p></div><button class="btn-ghost" data-aact="tab" data-v="screens">${I.tv}All screens</button></div>
        <div class="p-body">${playing.length ? playing.map((s) => `<div class="row"><div class="th" ${s.thumb ? `style="background-image:url('${esc(s.thumb)}')"` : ''}>${s.thumb ? '' : I.tv}</div>
          <div class="row-txt"><b>${esc(s.playing)}</b><span>${esc(s.label)} · ${s.watchers} watching${s.group ? ' · linked' : ''}</span></div>${statusTag(s)}
          <div class="row-act"><button class="icon-btn" data-aact="tp" data-id="${s.id}" title="Teleport">${I.pin}</button><button class="icon-btn danger" data-aact="stop" data-id="${s.id}" title="Stop">${I.stop}</button></div></div>`).join('')
          : `<div class="empty">${I.tv}<b>Nothing on air</b><span>Screens that are playing show up here with how many players are watching.</span></div>`}</div></section>
      <div class="grid2">
        <section class="panel"><div class="p-head"><div><h2>Quick create</h2><p>Permanent screens survive restarts</p></div></div><div class="p-body">
          <button class="btn-teal" data-aact="tab" data-v="create">${I.plus}Place a screen prop</button>
          <button class="btn-line" data-aact="quickWall">${I.wall}Draw a wall screen</button>
          <button class="btn-line" data-aact="quickExisting">${I.target}Use a prop in this MLO</button></div></section>
        <section class="panel"><div class="p-head"><div><h2>System</h2><p>Resource status</p></div></div><div class="p-pad note">
          Framework <b>${esc(d.framework)}</b> · storage <b>${esc(d.storage)}</b><br>Permanent screens <b>${st.permanent || 0}</b> · player screens <b>${(st.total || 0) - (st.permanent || 0)}</b><br>
          Calibrated models <b>${Object.keys(d.calibration || {}).length}</b> · players online <b>${st.players || 0}</b></div></section>
      </div>`;
  }

  if (A.tab === 'screens') {
    const q = A.q.toLowerCase();
    const rows = list.filter((s) => {
      if (A.filter === 'playing' && !(s.playing && s.power)) return false;
      if (A.filter === 'permanent' && !s.permanent) return false;
      if (A.filter === 'player' && s.permanent) return false;
      if (A.filter === 'locked' && !s.locked) return false;
      return !q || [s.label, s.model, s.owner, s.playing, s.id].some((v) => v && String(v).toLowerCase().includes(q));
    });
    return `<div class="head"><div><h1>All screens</h1><p>Search, teleport, lock, stop, move or delete any screen.</p></div></div>
      <div class="toolbar"><div class="search field">${I.search}<input id="aq" data-ainput="q" placeholder="Search by name, model, owner or what is playing" value="${esc(A.q)}"></div>
        <div class="fchips">${[['all', 'All'], ['playing', 'Playing'], ['permanent', 'Permanent'], ['player', 'Player'], ['locked', 'Locked']].map(([k, l]) => `<button class="fchip ${A.filter === k ? 'on' : ''}" data-aact="filter" data-v="${k}">${l}</button>`).join('')}</div></div>
      ${A.edit ? editForm(list.find((s) => s.id === A.edit)) : ''}
      <section class="panel"><div class="p-pad" style="padding:6px 6px 2px">${rows.length ? `<table class="tbl"><thead><tr><th>Screen</th><th>Owner</th><th>Status</th><th>Watching</th><th></th></tr></thead><tbody>
        ${rows.map((s) => `<tr><td><b>${esc(s.label)}</b><small>${esc(s.kind === 'wall' ? 'Wall screen' : s.model)} · ${esc(s.id)}${s.group ? ' · linked' : ''}</small></td>
          <td>${esc(s.owner || '—')}<small>${s.permanent ? 'Permanent' : 'Player placed'}</small></td>
          <td>${statusTag(s)}${s.playing ? `<small style="max-width:200px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(s.playing)}</small>` : ''}</td>
          <td>${s.watchers}</td>
          <td><div class="acts">
            <button class="icon-btn" data-aact="tp" data-id="${s.id}" title="Teleport">${I.pin}</button>
            <button class="icon-btn" data-aact="playOn" data-id="${s.id}" title="Play a link">${I.play}</button>
            <button class="icon-btn ${s.power ? 'on' : ''}" data-aact="power" data-id="${s.id}" title="Power">${I.power}</button>
            <button class="icon-btn ${s.locked ? 'on' : ''}" data-aact="lock" data-id="${s.id}" title="Lock">${s.locked ? I.lock : I.unlock}</button>
            <button class="icon-btn" data-aact="stop" data-id="${s.id}" title="Stop">${I.stop}</button>
            ${s.kind !== 'existing' ? `<button class="icon-btn" data-aact="move" data-id="${s.id}" title="Move">${I.move}</button>` : ''}
            <button class="icon-btn" data-aact="edit" data-id="${s.id}" title="Edit">${I.edit}</button>
            <button class="icon-btn danger" data-aact="del" data-id="${s.id}" title="Delete">${I.trash}</button></div></td></tr>`).join('')}</tbody></table>`
        : `<div class="empty" style="margin:10px">${I.search}<b>No screens match</b><span>Try another search or filter.</span></div>`}</div></section>`;
  }

  if (A.tab === 'create') {
    const pq = A.pq.toLowerCase();
    const props = A.props.filter((p) => (A.cat === 'all' || p.cat === A.cat) && (!pq || p.label.toLowerCase().includes(pq) || p.model.includes(pq)));
    const f = A.form;
    const sel = A.props.find((p) => p.model === A.sel);
    return `<div class="head"><div><h1>Create a screen</h1><p>Place any of ${A.props.length} supported props, draw a custom screen on any wall or billboard, or take over a prop that already exists in an MLO.</p></div></div>
      <div class="split">
        <section class="panel"><div class="p-head"><div><h2>Prop</h2><p>${sel ? esc(sel.label) + ' · ' + esc(sel.model) : 'Pick a model to place'}</p></div></div><div class="p-pad" style="display:flex;flex-direction:column;gap:10px">
          <div class="search field">${I.search}<input id="apq" data-ainput="pq" placeholder="Search props" value="${esc(A.pq)}"></div>
          <div class="fchips"><button class="fchip ${A.cat === 'all' ? 'on' : ''}" data-aact="cat" data-v="all">All</button>${A.cats.map((c) => `<button class="fchip ${A.cat === c.id ? 'on' : ''}" data-aact="cat" data-v="${c.id}">${esc(c.label)}</button>`).join('')}</div>
          <div class="pgrid">${props.map((p) => `<button class="pcard ${A.sel === p.model ? 'on' : ''} ${p.available ? '' : 'na'}" data-aact="pick" data-v="${esc(p.model)}"><span class="pc-ic">${I.tv}</span><b>${esc(p.label)}</b><span>${esc(p.model)}</span></button>`).join('')}</div>
        </div></section>
        <section class="panel"><div class="p-head"><div><h2>Settings</h2><p>Applied to the new screen</p></div></div><div class="p-pad" style="display:flex;flex-direction:column;gap:12px">
          <div class="field"><label>Name</label><input id="fLabel" data-form="label" placeholder="${esc(sel ? sel.label : 'Vinewood Cinema')}" value="${esc(f.label)}"></div>
          <div class="grid2"><div class="field"><label>Audio range (m)</label><input id="fRange" data-form="range" placeholder="${sel ? sel.range : 'auto'}" value="${esc(f.range)}"></div>
            <div class="field"><label>Wall width (m)</label><input id="fWidth" data-form="width" value="${esc(f.width)}"></div></div>
          <div class="field"><label>Default video (autoplay on restart)</label><input id="fUrl" data-form="defaultUrl" placeholder="https://…" value="${esc(f.defaultUrl)}"></div>
          <div class="opt"><div class="opt-t"><b>Autoplay default</b><small>Starts playing when the server starts</small></div><button class="sw ${f.autoplay ? 'on' : ''}" data-aact="fsw" data-k="autoplay"><i></i></button></div>
          <div class="opt"><div class="opt-t"><b>Repeat</b><small>Loop the default video</small></div><button class="sw ${f.loop ? 'on' : ''}" data-aact="fsw" data-k="loop"><i></i></button></div>
          <div class="opt"><div class="opt-t"><b>Public</b><small>Anyone can use the remote</small></div><button class="sw ${f.public ? 'on' : ''}" data-aact="fsw" data-k="public"><i></i></button></div>
          <div class="opt"><div class="opt-t"><b>Place a remote</b><small>Physical remote with a marker</small></div><button class="sw ${f.remote ? 'on' : ''}" data-aact="fsw" data-k="remote"><i></i></button></div>
          <button class="btn-teal" data-aact="place" data-v="prop" ${sel ? '' : 'disabled style="opacity:.5"'}>${I.tv}Place prop</button>
          <div class="grid2"><button class="btn-line" data-aact="place" data-v="wall">${I.wall}Wall screen</button><button class="btn-line" data-aact="place" data-v="existing">${I.target}Existing prop</button></div>
        </div></section>
      </div>`;
  }

  if (A.tab === 'groups') {
    const groups = {};
    list.forEach((s) => { if (s.group) (groups[s.group] = groups[s.group] || []).push(s); });
    const keys = Object.keys(groups);
    return `<div class="head"><div><h1>Link groups</h1><p>Linked screens mirror one feed — perfect for bars, clubs, casinos and stadiums. Only the loudest screen near each player plays sound.</p></div>
        <div class="head-act"><button class="btn-teal btn-sm" data-aact="group">${I.chain}Link ${A.groupSel.size || ''} selected</button></div></div>
      ${keys.length ? keys.map((g) => `<section class="panel"><div class="p-head"><div><h2>${esc(groups[g][0].label)} + ${groups[g].length - 1}</h2><p>${groups[g].length} screens · ${groups[g][0].playing ? esc(groups[g][0].playing) : 'idle'}</p></div>
        <button class="btn-ghost" data-aact="ungroup" data-v="${esc(g)}">${I.x}Unlink all</button></div>
        <div class="p-body">${groups[g].map((s) => `<div class="row"><div class="th">${I.tv}</div><div class="row-txt"><b>${esc(s.label)}</b><span>${esc(s.model || 'Wall screen')}</span></div>${statusTag(s)}</div>`).join('')}</div></section>`).join('') : ''}
      <section class="panel"><div class="p-head"><div><h2>Create a group</h2><p>Select two or more screens</p></div></div><div class="p-pad"><div class="checks">
        ${list.map((s) => `<button class="check ${A.groupSel.has(s.id) ? 'on' : ''}" data-aact="gsel" data-id="${s.id}"><i>${A.groupSel.has(s.id) ? I.check : ''}</i>${esc(s.label)}<small>${s.group ? 'linked' : esc(s.model || 'wall')}</small></button>`).join('')}
      </div></div></section>`;
  }

  if (A.tab === 'calibrator') {
    if (!A.cal) {
      return `<div class="head"><div><h1>Calibrator</h1><p>Fine-tune where the picture sits on a prop. Saved per model, shared with every player instantly, no restart.</p></div></div>
        <div class="empty">${I.ruler}<b>Stand in front of a prop screen</b><span>Then start the calibrator — a teal outline shows the picture edges and a red line shows which way it faces.</span>
          <button class="btn-teal" data-aact="calStart" style="margin-top:6px">${I.target}Calibrate nearest screen</button></div>
        <section class="panel"><div class="p-head"><div><h2>Calibrated models</h2><p>Overrides saved to data/calibration.json</p></div></div><div class="p-body">
          ${Object.keys(d.calibration || {}).map((m) => `<div class="row"><div class="th">${I.ruler}</div><div class="row-txt"><b>${esc(m)}</b><span>${(() => { const c = d.calibration[m]; return `${(+c.w).toFixed(2)} × ${(+c.h).toFixed(2)} m · faces ${c.face}`; })()}</span></div>
            <button class="icon-btn danger" data-aact="calResetModel" data-v="${esc(m)}" title="Reset">${I.trash}</button></div>`).join('') || '<div class="note">No models calibrated yet — everything uses auto-fit.</div>'}
        </div></section>`;
    }
    const c = A.cal, s = c.screen;
    const row = (k, label, min, max, step) => `<div class="cal-row"><label>${label}</label><div class="rng"><input type="range" min="${min}" max="${max}" step="${step}" value="${s[k]}" data-cal="${k}"></div>
      <input type="number" step="${step}" value="${(+s[k]).toFixed(3)}" data-caln="${k}"></div>`;
    return `<div class="head"><div><h1>Calibrator</h1><p>${esc(c.label)} · <b style="color:var(--white);font-weight:500">${esc(c.model)}</b></p></div></div>
      <section class="panel"><div class="p-pad">
        ${row('x', 'Offset X', -3, 3, 0.002)}${row('y', 'Offset Y', -3, 3, 0.002)}${row('z', 'Offset Z', -2, 6, 0.002)}
        ${row('w', 'Width', 0.05, 30, 0.002)}${row('h', 'Height', 0.05, 20, 0.002)}${row('tilt', 'Tilt °', -60, 60, 0.5)}
        <div class="opt"><div class="opt-t"><b>Facing</b><small>Which side of the model the picture is on</small></div>
          <div class="segc">${['-y', '+y', '-x', '+x'].map((f) => `<button class="${s.face === f ? 'on' : ''}" data-aact="calFace" data-v="${f}">${f}</button>`).join('')}</div></div>
        <div class="opt"><div class="opt-t"><b>Aspect lock</b><small>Keep 16:9 while changing width</small></div><button class="sw ${c.lock ? 'on' : ''}" data-aact="calLock"><i></i></button></div>
      </div></section>
      <div class="grid2"><button class="btn-line" data-aact="calAuto">${I.refresh}Auto-fit</button><button class="btn-red" data-aact="calReset">${I.trash}Reset saved</button></div>
      <div class="grid2"><button class="btn-line" data-aact="calStop">Cancel</button><button class="btn-teal" data-aact="calSave">${I.check}Save for ${esc(c.model)}</button></div>
      <p class="note">${c.saved ? 'This model already has a saved calibration.' : 'This model currently uses auto-fit.'} Hold Shift while dragging for fine steps.</p>`;
  }

  if (A.tab === 'logs') {
    if (!A.logs) { A.logs = []; post('admin', { op: 'logs' }).then((r) => { A.logs = (r && r.res) || []; if (A.open && A.tab === 'logs') renderAdmin(); }); }
    const tagFor = { media: 'live', place: 'off', admin: 'live', danger: 'hot' };
    return `<div class="head"><div><h1>Logs</h1><p>Placements, admin actions and what was played. Add a Discord webhook in config_server.lua to keep them.</p></div>
        <div class="head-act"><button class="btn-ghost" data-aact="logsRefresh">${I.refresh}Refresh</button></div></div>
      <section class="panel"><div class="p-pad" style="padding:6px 6px 2px">${A.logs.length ? `<table class="tbl"><thead><tr><th>When</th><th>Who</th><th>What</th><th>Screen</th></tr></thead><tbody>
        ${A.logs.map((l) => `<tr><td>${new Date(l.at * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</td><td>${esc(l.who)}</td>
          <td><span class="tag ${tagFor[l.kind] || 'off'}">${esc(l.kind)}</span> <b>${esc(l.title)}</b>${l.text ? `<small style="max-width:360px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(l.text)}</small>` : ''}</td>
          <td>${esc(l.tv || '—')}</td></tr>`).join('')}</tbody></table>` : `<div class="empty" style="margin:10px">${I.history}<b>Nothing logged yet</b><span>Placements, admin actions and media changes show up here.</span></div>`}</div></section>`;
  }

  if (A.tab === 'library') {
    const avail = A.props.filter((p) => p.available).length;
    const pq = A.pq.toLowerCase();
    const props = A.props.filter((p) => (A.cat === 'all' || p.cat === A.cat) && (!pq || p.label.toLowerCase().includes(pq) || p.model.includes(pq)));
    return `<div class="head"><div><h1>Prop library</h1><p><b style="color:var(--teal);font-weight:600">${avail}</b> of ${A.props.length} models are in your game build. Missing ones are hidden from players automatically. Add your own streamed props in <b style="color:var(--white);font-weight:500">data/props.lua</b>.</p></div></div>
      <div class="toolbar"><div class="search field">${I.search}<input id="apq2" data-ainput="pq" placeholder="Search props" value="${esc(A.pq)}"></div></div>
      <div class="fchips"><button class="fchip ${A.cat === 'all' ? 'on' : ''}" data-aact="cat" data-v="all">All</button>${A.cats.map((c) => `<button class="fchip ${A.cat === c.id ? 'on' : ''}" data-aact="cat" data-v="${c.id}">${esc(c.label)}</button>`).join('')}</div>
      <section class="panel"><div class="p-pad" style="padding:6px 6px 2px"><table class="tbl"><thead><tr><th>Prop</th><th>Category</th><th>Audio range</th><th>Calibration</th><th>Status</th></tr></thead><tbody>
        ${props.map((p) => `<tr><td><b>${esc(p.label)}</b><small>${esc(p.model)}</small></td><td>${esc((A.cats.find((c) => c.id === p.cat) || {}).label || p.cat)}</td><td>${p.range} m</td>
          <td>${(A.d.calibration || {})[p.model] ? '<span class="tag live">Saved</span>' : '<span class="tag off">Auto</span>'}</td>
          <td>${p.available ? '<span class="tag live">Available</span>' : '<span class="tag hot">Not in build</span>'}</td></tr>`).join('')}</tbody></table></div></section>`;
  }
  return '';
}

function editForm(s) {
  if (!s) return '';
  const p = s.perms || { public: true, jobs: {}, gangs: {} };
  const jobs = Object.entries(p.jobs || {}).map(([k, v]) => `${k}:${v}`).join(', ');
  const gangs = Object.entries(p.gangs || {}).map(([k, v]) => `${k}:${v}`).join(', ');
  return `<section class="panel"><div class="p-head"><div><h2>Edit ${esc(s.label)}</h2><p>${esc(s.id)}</p></div><button class="btn-ghost" data-aact="editClose">${I.x}Close</button></div>
    <div class="p-pad" style="display:flex;flex-direction:column;gap:12px">
      <div class="grid3"><div class="field"><label>Name</label><input id="eLabel" value="${esc(s.label)}"></div>
        <div class="field"><label>Audio range (m)</label><input id="eRange" value="${s.range}"></div>
        <div class="field"><label>ACE</label><input id="eAce" value="${esc(p.ace || '')}" placeholder="optional"></div></div>
      <div class="field"><label>Default video</label><input id="eUrl" value="${esc(s.defaultUrl || '')}" placeholder="https://…"></div>
      <div class="grid2"><div class="field"><label>Jobs (name:grade, …)</label><input id="eJobs" value="${esc(jobs)}" placeholder="police:0, ambulance:2"></div>
        <div class="field"><label>Gangs (name:grade, …)</label><input id="eGangs" value="${esc(gangs)}" placeholder="ballas:0"></div></div>
      <div class="grid3">
        <div class="opt"><div class="opt-t"><b>Public</b></div><button class="sw ${p.public ? 'on' : ''}" id="ePublic" data-aact="esw"><i></i></button></div>
        <div class="opt"><div class="opt-t"><b>Autoplay</b></div><button class="sw ${s.autoplay ? 'on' : ''}" id="eAuto" data-aact="esw"><i></i></button></div>
        <div class="opt"><div class="opt-t"><b>Locked</b></div><button class="sw ${s.locked ? 'on' : ''}" id="eLock" data-aact="esw"><i></i></button></div></div>
      <div style="display:flex;justify-content:flex-end;gap:8px"><button class="btn-line" data-aact="editClose">Cancel</button><button class="btn-teal" data-aact="editSave" data-id="${s.id}">${I.check}Save</button></div>
    </div></section>`;
}

const parsePairs = (str) => {
  const o = {};
  String(str || '').split(',').map((x) => x.trim()).filter(Boolean).forEach((x) => { const [k, v] = x.split(':'); if (k) o[k.trim().toLowerCase()] = parseInt(v, 10) || 0; });
  return o;
};

function calPreview() { post('calibPreview', { model: A.cal.model, screen: A.cal.screen }); }

const AdminActs = {
  close: () => { if (A.cal) post('calibStop', { model: A.cal.model }); closeAdmin(); },
  refresh: refreshAdmin,
  tab: (el) => { if (A.cal && el.dataset.v !== 'calibrator') { post('calibStop', { model: A.cal.model }); A.cal = null; } A.tab = el.dataset.v; A.edit = null; renderAdmin(); },
  filter: (el) => { A.filter = el.dataset.v; renderAdmin(); },
  cat: (el) => { A.cat = el.dataset.v; renderAdmin(); },
  pick: (el) => { A.sel = el.dataset.v; renderAdmin(); },
  fsw: (el) => { A.form[el.dataset.k] = !A.form[el.dataset.k]; renderAdmin(); },
  stopAll: async () => { if ((await modal({ title: 'Stop every screen?', text: 'All playback in the city stops immediately.', confirm: 'Stop all', danger: true })) !== null) adm('stopAll'); },
  stop: (el) => adm('stop', el.dataset.id),
  power: (el) => adm('power', el.dataset.id),
  lock: (el) => adm('lock', el.dataset.id),
  tp: (el) => { post('adminTp', { id: el.dataset.id }); },
  move: (el) => post('adminMove', { id: el.dataset.id }),
  edit: (el) => { A.edit = el.dataset.id; renderAdmin(); },
  editClose: () => { A.edit = null; renderAdmin(); },
  esw: (el) => el.classList.toggle('on'),
  editSave: async (el) => {
    const data = {
      id: el.dataset.id, label: $('#eLabel').value.trim(), range: parseFloat($('#eRange').value) || undefined, defaultUrl: $('#eUrl').value.trim(),
      autoplay: $('#eAuto').classList.contains('on'), locked: $('#eLock').classList.contains('on'),
      perms: { public: $('#ePublic').classList.contains('on'), jobs: parsePairs($('#eJobs').value), gangs: parsePairs($('#eGangs').value), ace: $('#eAce').value.trim() },
    };
    A.edit = null;
    await adm('update', data);
  },
  del: async (el) => {
    const s = (A.d.screens || []).find((x) => x.id === el.dataset.id);
    if ((await modal({ title: 'Delete this screen?', text: `${s ? s.label : 'The screen'} and its remote are removed for everyone. This cannot be undone.`, confirm: 'Delete screen', danger: true })) !== null) adm('delete', el.dataset.id);
  },
  playOn: async (el) => {
    const url = await modal({ title: 'Play a link', text: 'Starts playing on this screen (and its linked group) for everyone in range.', confirm: 'Play', input: 'Link', placeholder: 'https://…' });
    if (url) adm('play', { id: el.dataset.id, url });
  },
  place: (el) => {
    const f = A.form;
    const sel = A.props.find((p) => p.model === A.sel);
    const form = { model: A.sel, label: f.label || (sel && sel.label) || (el.dataset.v === 'wall' ? 'Wall Screen' : undefined), range: parseFloat(f.range) || undefined, width: parseFloat(f.width) || 3,
      defaultUrl: f.defaultUrl, autoplay: f.autoplay, loop: f.loop, remote: f.remote, perms: { public: f.public, jobs: {}, gangs: {} } };
    A.open = false; $('#admin').innerHTML = '';
    post('adminPlace', { mode: el.dataset.v, form });
  },
  quickWall: () => { A.open = false; $('#admin').innerHTML = ''; post('adminPlace', { mode: 'wall', form: { label: 'Wall Screen', width: 4, remote: false, perms: { public: true, jobs: {}, gangs: {} } } }); },
  quickExisting: () => { A.open = false; $('#admin').innerHTML = ''; post('adminPlace', { mode: 'existing', form: { remote: true, perms: { public: true, jobs: {}, gangs: {} } } }); },
  gsel: (el) => { const id = el.dataset.id; A.groupSel.has(id) ? A.groupSel.delete(id) : A.groupSel.add(id); renderAdmin(); },
  group: async () => { if (A.groupSel.size < 2) return toast('Select at least two screens.', 'error'); await adm('group', [...A.groupSel]); A.groupSel.clear(); renderAdmin(); },
  ungroup: (el) => adm('ungroup', el.dataset.v),
  logsRefresh: () => { A.logs = null; renderAdmin(); },
  calStart: async (el, e, id) => {
    const r = await post('calibStart', { id });
    if (!r) return;
    A.cal = { id: r.id, label: r.label, model: r.model, screen: Object.assign({ tilt: 0 }, r.screen), auto: r.auto, saved: r.saved, lock: false };
    renderAdmin();
  },
  calFace: (el) => { A.cal.screen.face = el.dataset.v; calPreview(); renderAdmin(); },
  calLock: () => { A.cal.lock = !A.cal.lock; renderAdmin(); },
  calAuto: () => { A.cal.screen = Object.assign({}, A.cal.auto); calPreview(); renderAdmin(); },
  calReset: async () => { await post('calibReset', { model: A.cal.model }); A.cal.screen = Object.assign({}, A.cal.auto); A.cal.saved = false; calPreview(); refreshAdmin(); },
  calResetModel: async (el) => { await post('calibReset', { model: el.dataset.v }); refreshAdmin(); },
  calStop: () => { post('calibStop', { model: A.cal.model }); A.cal = null; renderAdmin(); },
  calSave: async () => { await post('calibSave', { model: A.cal.model, screen: A.cal.screen }); A.cal = null; refreshAdmin(); },
};

/* ═══════════════ MY TV SETTINGS (/tvsettings) ═══════════════ */
const PS = { open: false, volume: 1, streamer: false };
function renderSettings() {
  const el = $('#settings');
  if (!PS.open) { el.innerHTML = ''; return; }
  const v = Math.round(PS.volume * 100);
  el.innerHTML = `<div class="modal-wrap"><div class="modal" style="width:min(400px,92vw)">
    <div class="modal-b"><div class="warn teal">${I.vol}</div><div style="flex:1;min-width:0"><h4>My TV settings</h4><p>Only changes what you hear. Everyone else is unaffected.</p></div></div>
    <div style="padding:0 18px 12px">
      <div class="opt"><div class="opt-t"><b>My volume</b><small>Every TV you hear, scaled</small></div>
        <div class="rng" style="max-width:190px"><input type="range" min="0" max="100" value="${v}" data-input="personal"><span>${v}%</span></div></div>
      <div class="opt"><div class="opt-t"><b>Streamer mode</b><small>Mutes every TV for you — keeps your stream free of copyrighted audio</small></div>
        <button class="sw ${PS.streamer ? 'on' : ''}" data-ps="streamer"><i></i></button></div>
    </div>
    <div class="modal-f"><button class="btn-teal" data-ps="close">${I.check}Done</button></div></div></div>`;
}
document.addEventListener('click', (e) => {
  const b = e.target.closest('#settings [data-ps]');
  if (!b) return;
  if (b.dataset.ps === 'streamer') { PS.streamer = !PS.streamer; post('personal', { streamer: PS.streamer }); renderSettings(); }
  if (b.dataset.ps === 'close') { PS.open = false; renderSettings(); post('personal', { close: true }); }
});
document.addEventListener('input', (e) => {
  if (e.target.dataset.input !== 'personal') return;
  PS.volume = +e.target.value / 100;
  e.target.parentElement.querySelector('span').textContent = e.target.value + '%';
  post('personal', { volume: PS.volume });
});

/* ═══════════════ EVENTS ═══════════════ */
document.addEventListener('click', (e) => {
  const pa = e.target.closest('#panel [data-act]');
  if (pa && PanelActs[pa.dataset.act]) { PanelActs[pa.dataset.act](pa, e); return; }
  const ra = e.target.closest('#remote [data-rk]');
  if (ra) { remoteAct(ra.dataset.rk, ra); return; }
  const aa = e.target.closest('#admin [data-aact]');
  if (aa && AdminActs[aa.dataset.aact]) AdminActs[aa.dataset.aact](aa, e);
});

// never rebuild the panel under a slider that is being dragged
const dragging = () => document.activeElement && document.activeElement.type === 'range' && pointerDown;
let pointerDown = false;
document.addEventListener('pointerdown', () => { pointerDown = true; });
document.addEventListener('pointerup', () => {
  pointerDown = false;
  if (P.dirty) { P.dirty = false; renderPanel(); }
});

let volTimer = 0;
document.addEventListener('input', (e) => {
  const t = e.target;
  if (t.dataset.input === 'url') {
    P.url = t.value;
    const bar = t.closest('.url-bar');
    const det = detect(P.url);
    if (bar) {
      const ic = bar.querySelector('.src-ic');
      ic.classList.toggle('ok', !!det);
      ic.innerHTML = det ? logo(det.kind, det.brand, 18) : I.link;
      const hint = bar.parentElement.querySelector('.url-hint');
      if (hint) hint.innerHTML = det ? `Detected <b>${esc(det.label)}</b> — plays in sync for everyone nearby` : P.url ? (P.d.search ? 'Press Enter to search YouTube' : 'Not a supported link yet') : 'Paste a link';
    }
  } else if (t.dataset.input === 'volume') {
    const v = +t.value;
    const lab = t.parentElement.querySelector('span');
    if (lab) lab.textContent = v + (P.view === 'display' ? '%' : '');
    clearTimeout(volTimer);
    volTimer = setTimeout(() => ctl('volume', v / 100), 90);
  } else if (t.dataset.ainput) {
    A[t.dataset.ainput] = t.value;
    renderAdmin();
  } else if (t.dataset.form) {
    A.form[t.dataset.form] = t.value;
  } else if (t.dataset.cal || t.dataset.caln) {
    const k = t.dataset.cal || t.dataset.caln;
    let v = parseFloat(t.value);
    if (!isFinite(v)) return;
    if (e.shiftKey) v = Math.round(v * 1000) / 1000;
    const s = A.cal.screen;
    if (A.cal.lock && (k === 'w' || k === 'h')) { if (k === 'w') { s.w = v; s.h = v / (16 / 9); } else { s.h = v; s.w = v * (16 / 9); } }
    else s[k] = v;
    // mirror the paired control without re-rendering (keeps the slider grabbed)
    document.querySelectorAll(`[data-cal="${k}"],[data-caln="${k}"]`).forEach((o) => { if (o !== t) o.value = o.type === 'number' ? (+s[k]).toFixed(3) : s[k]; });
    if (A.cal.lock) ['w', 'h'].forEach((kk) => document.querySelectorAll(`[data-cal="${kk}"],[data-caln="${kk}"]`).forEach((o) => { if (o !== t) o.value = o.type === 'number' ? (+s[kk]).toFixed(3) : s[kk]; }));
    calPreview();
  }
});

document.addEventListener('keydown', (e) => {
  if (modalOpen()) return;
  const inInput = /INPUT|TEXTAREA|SELECT/.test(document.activeElement && document.activeElement.tagName);
  if (e.key === 'Escape') {
    if (PS.open) { PS.open = false; renderSettings(); post('personal', { close: true }); return; }
    if (R.open && R.kbd) { R.kbd = null; renderRemote(); return; }
    if (A.open && A.edit) { A.edit = null; renderAdmin(); return; }
    if (P.open) closePanel();
    else if (R.open) closeRemote();
    else if (A.open) AdminActs.close();
    return;
  }
  if (P.open && e.key === 'Enter' && document.activeElement && document.activeElement.dataset.input === 'url') {
    e.preventDefault();
    if (!detect(P.url) && P.d.search && !e.shiftKey) doSearch();
    else playUrl(P.url, null, e.shiftKey);
    return;
  }
  if (R.open) {
    if (R.kbd && document.activeElement && document.activeElement.id === 'kbdText') {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); remoteAct('kbdSend'); }
      return;
    }
    if (inInput) return;
    const act = KEYMAP[e.key];
    if (act) {
      e.preventDefault();
      if (e.repeat && !/^key:(up|down|left|right)$|volStep/.test(act)) return;
      remoteAct(act, RK_SEL[act] ? $(RK_SEL[act]) : null);
    }
  }
});

/* ═══════════════ MESSAGES ═══════════════ */
window.addEventListener('message', (e) => {
  const d = e.data;
  if (!d || !d.type) return;
  switch (d.type) {
    case 'toast': toast(d.text, d.kind, d.title); break;
    case 'prompt': renderPrompt(d); break;
    case 'placement': renderPlacement(d); break;
    case 'panel':
      if (d.brand) window.__brand = d.brand;
      d.show ? openPanel(d) : closePanel(false);
      break;
    case 'panelPatch':
      if (P.open && P.tv && P.tv.id === d.id) {
        setClock(d.now);
        for (const k in d.patch) P.tv[k] = d.patch[k] === false && (k === 'media' || k === 'group') ? null : d.patch[k];
        const keys = Object.keys(d.patch);
        if (keys.every((k) => k === 'ui')) break; // TV OS navigation only — nothing in the panel changes
        if (dragging()) P.dirty = true; else renderPanel();
      }
      break;
    case 'remote':
      if (d.brand) window.__brand = d.brand;
      d.show ? openRemote(d) : closeRemote(false);
      break;
    case 'remotePatch':
      if (R.open && R.tv && R.tv.id === d.id) {
        setClock(d.now);
        for (const k in d.patch) R.tv[k] = d.patch[k] === false && (k === 'media' || k === 'group') ? null : d.patch[k];
        if (!R.kbd) renderRemote();
      }
      break;
    case 'keyboard':
      if (R.open) { R.kbd = { value: d.value || '', hint: d.hint }; renderRemote(); }
      break;
    case 'settings':
      PS.open = !!d.show; PS.volume = d.volume == null ? 1 : d.volume; PS.streamer = !!d.streamer;
      renderSettings();
      break;
    case 'admin':
      if (d.show) openAdmin(d);
      else { A.open = false; $('#admin').innerHTML = ''; }
      break;
  }
});

/* ═══════════════ BROWSER PREVIEW (outside FiveM) ═══════════════ */
const DEMO = {
  post: async (name, data) => {
    if (name === 'control') {
      const t = P.open ? P.tv : R.tv;
      if (data.action === 'toggle' && t.media) { t.media.paused = !t.media.paused; }
      if (data.action === 'volume') t.volume = data.data;
      if (data.action === 'volStep') t.volume = clamp(t.volume + (data.data > 0 ? 0.05 : -0.05), 0, 1);
      if (data.action === 'mute') t.muted = !t.muted;
      if (data.action === 'loop') t.loop = !t.loop;
      if (data.action === 'power') t.power = !t.power;
      P.open ? renderPanel() : renderRemote();
      return { ok: true };
    }
    if (name === 'calibStart') return { id: 'a', label: 'Living Room TV', model: 'prop_tv_flat_01', screen: { x: 0, y: -0.06, z: 1.02, w: 1.22, h: 0.686, face: '-y' }, auto: { x: 0, y: -0.05, z: 1, w: 1.2, h: 0.675, face: '-y' }, saved: false };
    return { ok: true, list: P.d ? P.d.favorites : [] };
  },
};

if (!IN_GAME) {
  document.body.classList.add('demo');
  const q = new URLSearchParams(location.search);
  const now = Date.now();
  const tv = {
    id: 'a1b2c3d4', label: 'Living Room TV', power: true, volume: 0.62, muted: false, loop: false, group: 'g1', locked: false, style: 'flat', model: 'prop_tv_flat_01', kind: 'prop', permanent: false, remote: true,
    settings: { picture: 'standard', fit: 'contain', ambient: true, osd: true },
    media: { key: 'k', kind: 'youtube', url: 'https://youtu.be/x', title: 'Midnight Drive — 3 Hour Synthwave Mix for Late Night Cruising', by: 'Maya Reyes', startedAt: now - 1394000, duration: 10800, paused: false },
    queue: [{ url: 'https://twitch.tv/x', title: 'Late Night Racing League — Finals', kind: 'twitch', by: 'Theo Kane' }, { url: 'https://x/a.mp4', title: 'Vinewood Premiere Trailer', kind: 'video', by: 'John Doe' }],
    history: [{ url: 'https://youtu.be/x', title: 'Midnight Drive — 3 Hour Synthwave Mix', kind: 'youtube', by: 'Maya Reyes', pos: 1394, dur: 10800 }, { url: 'https://www.tiktok.com/@x/video/1', title: 'Pier sunset drift compilation', kind: 'tiktok', by: 'Theo Kane' },
      { url: 'https://soundcloud.com/a/b', title: 'Vinewood Nights (Live Set)', kind: 'soundcloud', by: 'Sam Brooks', pos: 600, dur: 3600 }, { url: 'https://kick.com/x', title: 'city_radio', kind: 'kick', by: 'Sam Brooks' }],
  };
  const data = { tv, canManage: true, isOwner: true, isAdmin: false, me: 'John Doe', search: true, favorites: [{ url: 'https://youtu.be/x', title: 'Midnight Drive — 3 Hour Synthwave Mix', kind: 'youtube' }],
    library: [{ file: 'intro.mp4', title: 'City Intro' }], channels: [{ number: 1, name: 'City News', url: 'https://www.twitch.tv/citynews' }, { number: 2, name: 'Lo-fi Radio', url: 'https://www.youtube.com/watch?v=jfKfPfyJRdk' }],
    pictures: ['game', 'movie', 'night', 'standard', 'vivid'], sleepOptions: [0, 15, 30, 60, 90],
    collections: [{ kind: 'movie', category: 'Animation', title: 'Big Buck Bunny', url: 'https://x/BigBuckBunny.mp4' }, { kind: 'movie', category: 'Sci-Fi', title: 'Tears of Steel', url: 'https://x/TearsOfSteel.mp4' }, { kind: 'music', category: 'Chill', title: 'Lofi Radio', url: 'https://www.youtube.com/watch?v=jfKfPfyJRdk' }],
    perms: { public: false, jobs: { police: 0 }, gangs: {} }, linkable: [{ id: 'b', label: 'Bar Screen Left', linked: true }, { id: 'c', label: 'Bar Screen Right', linked: false }] };
  const brand = { name: 'NAYZEEE', product: 'Television', version: '1.0.0' };
  window.__brand = brand;
  const view = q.get('view') || 'panel';
  if (view === 'panel') { openPanel({ data, now, brand }); if (q.get('v')) { P.view = q.get('v'); renderPanel(); } }
  if (view === 'remote') { openRemote({ tv, now, physical: true, brand }); if (q.get('kbd')) { R.kbd = { value: 'lofi beats', hint: 'Search YouTube or paste a link' }; renderRemote(); } renderPrompt({ show: false }); }
  if (view === 'hud') {
    renderPrompt({ show: true, title: 'Living Room TV', sub: 'Playing · Midnight Drive — Synthwave Mix', keys: [{ key: 'E', label: 'Media panel' }, { key: 'G', label: 'Use remote' }, { key: 'H', label: 'Pick up' }] });
    renderPlacement({ show: true, title: 'Place screen', sub: 'Flat Screen TV', valid: true, snap: true, keys: [{ key: 'E', label: 'Place' }, { key: '⇅', label: 'Scroll · rotate' }, { key: 'PgUp', label: 'Raise' }, { key: 'PgDn', label: 'Lower' }, { key: 'Alt', label: 'Wall snap' }, { key: '⌫', label: 'Cancel' }] });
    toast('Flat Screen TV placed.', 'success'); toast('You are not allowed to control this screen.', 'error');
  }
  if (view === 'admin') {
    const screens = [
      { id: 'a1b2c3d4', label: 'Living Room TV', model: 'prop_tv_flat_01', kind: 'prop', owner: 'John Doe', permanent: false, power: true, playing: 'Midnight Drive — Synthwave Mix', source: 'youtube', watchers: 3, range: 20, group: null, perms: { public: false, jobs: {}, gangs: {} } },
      { id: 'cin00001', label: 'Vinewood Cinema', model: 'v_ilev_cin_screen', kind: 'existing', owner: 'Server', permanent: true, power: true, playing: 'Friday Night Premiere', live: false, watchers: 14, range: 100, perms: { public: true, jobs: {}, gangs: {} } },
      { id: 'bar00001', label: 'Bahama Bar — Left', model: 'prop_tv_flat_michael', kind: 'prop', owner: 'Server', permanent: true, power: true, playing: 'Late Night Racing League', live: true, watchers: 6, range: 26, group: 'g1', perms: { public: true, jobs: {}, gangs: {} } },
      { id: 'bar00002', label: 'Bahama Bar — Right', model: 'prop_tv_flat_michael', kind: 'prop', owner: 'Server', permanent: true, power: true, playing: 'Late Night Racing League', live: true, watchers: 4, range: 26, group: 'g1', perms: { public: true, jobs: {}, gangs: {} } },
      { id: 'mrpd0001', label: 'MRPD Briefing Wall', kind: 'wall', owner: 'Server', permanent: true, power: false, watchers: 0, range: 30, locked: true, perms: { public: false, jobs: { police: 0 }, gangs: {} } },
    ];
    const props = [['prop_tv_flat_01', 'Flat Screen TV', 'flat', 20], ['prop_tv_flat_michael', 'Large Flat TV', 'flat', 26], ['prop_tv_03', 'Classic CRT TV', 'crt', 16], ['v_ilev_cin_screen', 'Cinema Screen', 'cinema', 100], ['prop_laptop_01a', 'Laptop', 'laptop', 8], ['ch_prop_arcade_street_01a', 'Cabinet — Street', 'arcade', 9], ['xm_prop_x17_tv_scrn_01', 'Facility Panel 01', 'facility', 35], ['prop_monitor_w_large', 'Wide Monitor', 'monitor', 12], ['xs_prop_arena_bigscreen_01', 'Arena Big Screen', 'cinema', 140]]
      .map(([model, label, cat, range], i) => ({ model, label, cat, range, available: i !== 8 }));
    openAdmin({ data: { screens, stats: { total: 5, playing: 4, viewers: 27, groups: 1, permanent: 4, players: 48 }, storage: 'oxmysql', framework: 'qbx', calibration: { prop_tv_flat_michael: { w: 1.9, h: 1.07, face: '-y' } } },
      props, categories: [{ id: 'flat', label: 'Flat Screens' }, { id: 'crt', label: 'Retro CRT' }, { id: 'cinema', label: 'Cinema & Walls' }, { id: 'laptop', label: 'Laptops' }, { id: 'arcade', label: 'Arcade & Casino' }], now, brand, me: 'Admin Nay', tab: q.get('tab') || 'dashboard' });
    if (q.get('tab') === 'calibrator') AdminActs.calStart();
  }
}
