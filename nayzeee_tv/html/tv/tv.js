/* ═══════════════════════════════════════════════════════════
   NAYZEEE OS — runs inside every in-world screen (DUI)
   Media playback · drift-corrected sync · 3D audio effects ·
   smart-TV home screen driven by the remote
   ═══════════════════════════════════════════════════════════ */
'use strict';

const $ = (s) => document.querySelector(s);
const stage = $('#stage');
const playerEl = $('#player');

/* ─────────────── icons (original line set) ─────────────── */
const I = {
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></svg>',
  source: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8M12 17v4M10 9l3 2-3 2z"/></svg>',
  home: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><path d="M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5h-5v5H5a1 1 0 0 1-1-1z"/></svg>',
  library: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="3.5" y="4" width="4" height="16" rx="1"/><rect x="9.5" y="4" width="4" height="16" rx="1"/><path d="m16 5.2 3.8-1 3 15.4-3.8 1z"/></svg>',
  queue: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M4 6h12M4 11h12M4 16h7"/><path d="m15 14 5 3-5 3z" fill="currentColor"/></svg>',
  settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="3"/><path d="M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"/></svg>',
  wifi: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.6 16a5 5 0 0 1 6.8 0"/><circle cx="12" cy="19.3" r=".9" fill="currentColor"/></svg>',
  play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.5v15l13-7.5z"/></svg>',
  pause: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4.5" width="4" height="15" rx="1"/><rect x="14" y="4.5" width="4" height="15" rx="1"/></svg>',
  vol: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9.5h3.5L12 5v14l-4.5-4.5H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/></svg>',
  mute: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9.5h3.5L12 5v14l-4.5-4.5H4z"/><path d="m16 9.5 5 5M21 9.5l-5 5"/></svg>',
  yt: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><rect x="2.5" y="5.5" width="19" height="13" rx="4"/><path d="m10 9 5 3-5 3z" fill="currentColor"/></svg>',
  tw: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><circle cx="12" cy="12" r="2.2" fill="currentColor"/><path d="M8.2 8.2a5.4 5.4 0 0 0 0 7.6M15.8 8.2a5.4 5.4 0 0 1 0 7.6M5.3 5.3a9.5 9.5 0 0 0 0 13.4M18.7 5.3a9.5 9.5 0 0 1 0 13.4"/></svg>',
  kk: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M13.5 2.5 5 13.5h6l-1.5 8 8.5-11h-6z"/></svg>',
  link: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M10 14a4.2 4.2 0 0 0 6 0l3-3a4.2 4.2 0 0 0-6-6l-1 1"/><path d="M14 10a4.2 4.2 0 0 0-6 0l-3 3a4.2 4.2 0 0 0 6 6l1-1"/></svg>',
  tv: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="m8 2.5 4 3.5 4-3.5M8 21h8"/></svg>',
  music: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"><path d="M9 18V5.5l11-2V16"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/></svg>',
  image: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2.5"/><circle cx="9" cy="9.5" r="1.7"/><path d="m4 18 5.5-5.5 4 4L16 14l4.5 4.5"/></svg>',
  film: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/></svg>',
  chev: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6"/></svg>',
  loop: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3l3 3-3 3"/><path d="M4 11V9a3 3 0 0 1 3-3h13M7 21l-3-3 3-3"/><path d="M20 13v2a3 3 0 0 1-3 3H4"/></svg>',
};
const KIND_ICON = { youtube: 'yt', twitch: 'tw', kick: 'kk', hls: 'tw', video: 'film', audio: 'music', image: 'image' };
const KIND_LABEL = { youtube: 'YouTube', twitch: 'Twitch', kick: 'Kick', hls: 'Live stream', video: 'Video', audio: 'Audio', image: 'Image',
  tiktok: 'TikTok', vimeo: 'Vimeo', soundcloud: 'SoundCloud', streamable: 'Streamable', medal: 'Medal', instagram: 'Instagram',
  dailymotion: 'Dailymotion', reddit: 'Reddit', rumble: 'Rumble', plex: 'Plex' };
const BRANDS = window.BRANDS || {};
const brandKey = (kind, brand) => (brand && BRANDS[brand] ? brand : BRANDS[kind] ? kind : null);
/* platform logo (transparent brand mark) — falls back to a line icon */
function kicon(kind, brand, size) {
  const b = brandKey(kind, brand);
  return b ? window.brandSvg(b, size || 24) : I[KIND_ICON[kind] || 'film'];
}
const klabel = (kind, brand) => { const b = brandKey(kind, brand); return (b && BRANDS[b].name) || KIND_LABEL[kind] || 'Media'; };
/* app tiles: brand gradient + logo colour */
const TILE = {
  youtube: ['#ff3b3b', '#c40d0d', '#fff'], tiktok: ['#1d2024', '#030303', '#fff'], twitch: ['#a970ff', '#6420d6', '#fff'],
  kick: ['#17191b', '#050606', '#53FC19'], vimeo: ['#3fcaf5', '#0e8fbd', '#fff'], soundcloud: ['#ff7a2f', '#e04400', '#fff'],
  plex: ['#22272b', '#0b0c0d', '#EBAF00'], pluto: ['#fff45a', '#e2d300', '#111'], medal: ['#1d2024', '#050607', '#FFAD33'],
  streamable: ['#3aa6ff', '#0b6fd0', '#fff'], instagram: ['#f9a03f', '#d62976', '#fff', '#7a2ae2'], dailymotion: ['#262a2e', '#050606', '#fff'],
  reddit: ['#ff6a2f', '#d63a00', '#fff'], rumble: ['#98d65a', '#5f9a2c', '#fff'],
};
const tileStyle = (k) => { const t = TILE[k]; if (!t) return ''; return `background:linear-gradient(155deg,${t[0]},${t[3] ? t[1] + ',' + t[3] : t[1]});color:${t[2]}`; };
document.querySelectorAll('[data-icon]').forEach((el) => { el.innerHTML = I[el.dataset.icon] || ''; });

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const fmt = (t) => {
  if (!isFinite(t) || t < 0) t = 0;
  t = Math.floor(t);
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(s).padStart(2, '0');
};

/* ─────────────── state ─────────────── */
const S = {
  tv: null,
  res: (location.hostname.match(/^cfx-nui-(.+)$/) || [])[1] || 'nayzeee_tv',
  offset: 0, clockSet: false,
  brand: { name: 'NAYZEEE', os: 'NAYZEEE OS', version: '1.0.0' },
  featured: [], channels: [], library: [],
  sync: { SeekDrift: 1.25, NudgeDrift: 0.12 },
  ui: { page: 'home', tab: 0, zone: 'tabs', idx: {}, railIdx: 3, prevZone: 'tabs', src: 'youtube', sources: false, list: 'library' },
  query: '', results: [], searchMsg: '',
  adapter: null, mediaKey: null,
  audio: { volume: 0, lowpass: 22000, pan: 0 },
  lastInput: Date.now(), heroIdx: 0, booting: false,
};

const serverNow = () => performance.now() + S.offset;
function setClock(now) {
  if (typeof now !== 'number') return;
  const off = now - performance.now();
  // queued messages arrive late → only accept smaller offsets when the jump is real
  if (!S.clockSet || off > S.offset || off < S.offset - 250) S.offset = off;
  S.clockSet = true;
}
const expectedPos = (m) => (m ? (m.paused ? (m.pausedAt || 0) : Math.max(0, (serverNow() - m.startedAt) / 1000)) : 0);

function report(kind, data) {
  if (!S.tv) return;
  fetch(`https://${S.res}/tv:report`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tv: S.tv.id, key: S.tv.media ? S.tv.media.key : null, kind, data }),
  }).catch(() => {});
}
const action = (data) => report('action', data);

/* ─────────────── layout: virtual 1080p stage → real DUI size & aspect ─────────────── */
function layout() {
  const W = window.innerWidth || 1280, H = window.innerHeight || 720;
  const aspect = (S.tv && S.tv.aspect) || 16 / 9;
  const vh = 1080, vw = Math.round(vh * Math.max(0.5, aspect));
  stage.style.width = vw + 'px';
  stage.style.height = vh + 'px';
  stage.style.transform = `scale(${W / vw},${H / vh})`;
}
window.addEventListener('resize', layout);
layout();

/* ═══════════════ MEDIA ADAPTERS ═══════════════ */
function loadScript(src) {
  return new Promise((res, rej) => { const s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
}
let ytApi = null;
function loadYT() {
  if (!ytApi) ytApi = new Promise((res) => { window.onYouTubeIframeAPIReady = res; loadScript('https://www.youtube.com/iframe_api').catch(() => {}); });
  return ytApi;
}
let twApi = null;
const loadTW = () => (twApi = twApi || loadScript('https://player.twitch.tv/js/embed/v1.js'));

const PLEX_SESSION = 'nztv' + Math.random().toString(36).slice(2, 10);
function mediaUrl(m) {
  if (m.src === 'local') return `https://cfx-nui-${S.res}/html/media/${encodeURIComponent(m.file)}`;
  if (m.kind === 'kick' && m.hls) return m.hls;
  if (m.kind === 'streamable' && m.direct) return m.direct;
  if (m.kind === 'reddit') return m.hls;
  // every TV needs its own Plex transcode session
  if (m.kind === 'plex' && /transcode\/universal/.test(m.url)) return `${m.url}&session=${PLEX_SESSION}&X-Plex-Session-Identifier=${PLEX_SESSION}&X-Plex-Client-Identifier=${PLEX_SESSION}`;
  return m.url;
}

/* YouTube (videos, live, playlists) */
class YouTubeAdapter {
  constructor(m) {
    this.m = m; this.vol = S.audio.volume; this.seekLead = 0.35;
    this.div = document.createElement('div');
    this.div.id = 'yt' + Math.random().toString(36).slice(2);
    playerEl.appendChild(this.div);
    loadYT().then(() => this.create());
  }
  create() {
    if (this.dead) return;
    const m = this.m;
    const vars = { autoplay: 1, controls: 0, disablekb: 1, modestbranding: 1, rel: 0, playsinline: 1, iv_load_policy: 3, fs: 0, cc_load_policy: 0,
      start: Math.floor(expectedPos(m)), origin: location.origin, widget_referrer: location.origin, enablejsapi: 1 };
    if (!m.id && m.list) { vars.listType = 'playlist'; vars.list = m.list; }
    this.p = new YT.Player(this.div.id, {
      width: '100%', height: '100%', videoId: m.id || undefined, playerVars: vars,
      events: {
        onReady: () => { this.ready = true; this.setVolume(this.vol); if (this.m.paused) this.p.pauseVideo(); else this.p.playVideo(); syncCheck(); },
        onStateChange: (e) => this.state(e.data),
        onError: (e) => { report('error', 'youtube ' + e.data); osdToast(e.data === 101 || e.data === 150 ? 'The owner of this video does not allow it to play on TVs' : 'This video cannot be played'); },
      },
    });
  }
  state(s) {
    if (s === 1) {
      setBuffer(false);
      const d = this.p.getVideoData ? this.p.getVideoData() : null;
      if (d && d.title && !this.titled) { this.titled = true; report('title', d.title); }
      if (!this.durRep) {
        const dur = this.p.getDuration();
        if (d && d.isLive) { this.durRep = true; report('duration', 0); }
        else if (dur > 0) { this.durRep = true; report('duration', dur); }
      }
      if (!this.m.id && this.m.list && !this.plRep) {
        const pl = this.p.getPlaylist && this.p.getPlaylist();
        if (pl && pl.length) { this.plRep = true; report('playlist', pl); }
      }
    } else if (s === 3) setBuffer(true);
    else if (s === 0) report('ended');
  }
  update(m) {
    this.m = m;
    if (this.ready && m.id && m.id !== this.curId()) {
      this.titled = this.durRep = false;
      this.p.loadVideoById({ videoId: m.id, startSeconds: expectedPos(m) });
    }
  }
  curId() { try { return this.p.getVideoData().video_id; } catch (e) { return null; } }
  time() { return this.ready ? this.p.getCurrentTime() : 0; }
  seek(t) { if (this.ready) this.p.seekTo(t, true); }
  play() { if (this.ready && ![1, 3].includes(this.p.getPlayerState())) this.p.playVideo(); }
  pause() { if (this.ready && this.p.getPlayerState() !== 2) this.p.pauseVideo(); }
  setVolume(v) {
    this.vol = v;
    if (!this.ready) return;
    this.p.setVolume(Math.round(v * 100));
    if (v <= 0.002) this.p.mute(); else if (this.p.isMuted()) this.p.unMute();
  }
  destroy() { this.dead = true; try { this.p && this.p.destroy(); } catch (e) {} this.div.remove(); }
}

/* Twitch (channels, VODs, clips) */
class TwitchAdapter {
  constructor(m) {
    this.m = m; this.vol = S.audio.volume; this.seekLead = 0.5;
    this.div = document.createElement('div');
    this.div.id = 'tw' + Math.random().toString(36).slice(2);
    playerEl.appendChild(this.div);
    if (m.clip) {
      this.noSync = true; this.ready = true;
      this.div.innerHTML = `<iframe src="https://clips.twitch.tv/embed?clip=${encodeURIComponent(m.clip)}&parent=${location.hostname}&autoplay=true&muted=false" allow="autoplay"></iframe>`;
      return;
    }
    if (!m.video) this.noSync = true;
    loadTW().then(() => this.create()).catch(() => osdToast('Twitch could not be reached'));
  }
  create() {
    if (this.dead) return;
    const m = this.m;
    const o = { width: '100%', height: '100%', parent: [location.hostname], autoplay: true, muted: false };
    if (m.video) { o.video = 'v' + m.video; o.time = Math.floor(expectedPos(m)) + 's'; } else o.channel = m.channel;
    this.p = new Twitch.Player(this.div.id, o);
    this.p.addEventListener(Twitch.Player.READY, () => { this.ready = true; this.p.setMuted(false); this.setVolume(this.vol); syncCheck(); });
    this.p.addEventListener(Twitch.Player.PLAYING, () => {
      setBuffer(false);
      if (m.video && !this.durRep) { const d = this.p.getDuration(); if (d > 0) { this.durRep = true; report('duration', d); } }
    });
    this.p.addEventListener(Twitch.Player.ENDED, () => report('ended'));
  }
  time() { return this.ready && this.p ? this.p.getCurrentTime() : 0; }
  seek(t) { if (this.ready && this.p) this.p.seek(t); }
  play() { if (this.ready && this.p && this.p.isPaused()) this.p.play(); }
  pause() { if (this.ready && this.p && !this.p.isPaused()) this.p.pause(); }
  setVolume(v) { this.vol = v; if (this.ready && this.p) { this.p.setVolume(clamp(v, 0, 1)); this.p.setMuted(v <= 0.002); } }
  destroy() { this.dead = true; this.div.remove(); }
}

/* Vimeo — full control through Vimeo's player API */
let vimeoApi = null;
const loadVimeo = () => (vimeoApi = vimeoApi || loadScript('https://player.vimeo.com/api/player.js'));
class VimeoAdapter {
  constructor(m) {
    this.m = m; this.t = 0; this.vol = S.audio.volume; this.seekLead = 0.4; this.paused = true;
    this.div = document.createElement('div');
    playerEl.appendChild(this.div);
    loadVimeo().then(() => this.create()).catch(() => osdToast('Vimeo could not be reached'));
  }
  create() {
    if (this.dead) return;
    const m = this.m;
    const o = { autoplay: true, controls: false, muted: false, dnt: true, title: false, byline: false, portrait: false, keyboard: false, pip: false };
    if (m.hash) o.url = `https://vimeo.com/${m.id}/${m.hash}`; else o.id = Number(m.id);
    this.p = new Vimeo.Player(this.div, o);
    this.p.ready().then(() => {
      this.ready = true;
      this.setVolume(this.vol);
      this.p.setCurrentTime(expectedPos(this.m)).catch(() => {});
      if (!this.m.paused) this.play();
      this.p.getDuration().then((d) => { if (d > 0) report('duration', d); }).catch(() => {});
      this.p.getVideoTitle().then((t) => { if (t) report('title', t); }).catch(() => {});
      syncCheck();
    }).catch(() => osdToast('This Vimeo video cannot be embedded'));
    this.p.on('timeupdate', (d) => { this.t = d.seconds; });
    this.p.on('play', () => { this.paused = false; setBuffer(false); });
    this.p.on('pause', () => { this.paused = true; });
    this.p.on('bufferstart', () => setBuffer(true));
    this.p.on('bufferend', () => setBuffer(false));
    this.p.on('ended', () => report('ended'));
  }
  time() { return this.t; }
  seek(t) { if (this.ready) { this.t = t; this.p.setCurrentTime(t).catch(() => {}); } }
  play() { if (this.ready && this.paused) { this.paused = false; this.p.play().catch(() => { this.paused = true; }); } }
  pause() { if (this.ready && !this.paused) { this.paused = true; this.p.pause().catch(() => {}); } }
  setVolume(v) { this.vol = v; if (this.ready) this.p.setVolume(clamp(v, 0, 1)).catch(() => {}); }
  destroy() { this.dead = true; try { if (this.p) this.p.destroy(); } catch (e) {} this.div.remove(); }
}

/* SoundCloud — the widget API gives play / pause / seek / volume */
let scApi = null;
const loadSC = () => (scApi = scApi || loadScript('https://w.soundcloud.com/player/api.js'));
class SoundCloudAdapter {
  constructor(m) {
    this.m = m; this.t = 0; this.seekLead = 0.3; this.paused = true;
    this.f = document.createElement('iframe');
    this.f.allow = 'autoplay';
    this.f.src = `https://w.soundcloud.com/player/?url=${encodeURIComponent(m.url)}&auto_play=true&visual=true&hide_related=true&show_comments=false&show_user=true&show_reposts=false&show_teaser=false&buying=false&sharing=false&download=false`;
    playerEl.appendChild(this.f);
    loadSC().then(() => this.bind()).catch(() => osdToast('SoundCloud could not be reached'));
  }
  bind() {
    if (this.dead) return;
    const W = window.SC.Widget, E = W.Events;
    this.w = W(this.f);
    this.w.bind(E.READY, () => {
      this.ready = true;
      this.setVolume(S.audio.volume);
      this.w.getDuration((ms) => { if (ms > 0) report('duration', ms / 1000); });
      this.w.getCurrentSound((snd) => { if (snd && snd.title) report('title', (snd.user && snd.user.username ? snd.user.username + ' — ' : '') + snd.title); });
      this.w.seekTo(expectedPos(this.m) * 1000);
      if (!this.m.paused) this.play();
      syncCheck();
    });
    this.w.bind(E.PLAY_PROGRESS, (e) => { this.t = e.currentPosition / 1000; });
    this.w.bind(E.PLAY, () => { this.paused = false; setBuffer(false); });
    this.w.bind(E.PAUSE, () => { this.paused = true; });
    this.w.bind(E.FINISH, () => report('ended'));
  }
  time() { return this.t; }
  seek(t) { if (this.ready) { this.t = t; this.w.seekTo(t * 1000); } }
  play() { if (this.ready && this.paused) { this.paused = false; this.w.play(); } }
  pause() { if (this.ready && !this.paused) { this.paused = true; this.w.pause(); } }
  setVolume(v) { if (this.ready) this.w.setVolume(Math.round(clamp(v, 0, 1) * 100)); }
  destroy() { this.dead = true; this.f.remove(); }
}

/* Platform embeds that cannot be remote-controlled (TikTok, Medal, Instagram, Dailymotion, Rumble, Kick fallback).
   startSync: the embed takes a start time, so late joiners land on the right moment and seeks reload it.
   click: the embed needs a tap to start — the TV taps it.
   Volume can't be set on these, so the picture/sound unloads when you are out of earshot and comes back when you return. */
const EMBEDS = {
  tiktok: { url: (m) => `https://www.tiktok.com/player/v1/${m.id}?autoplay=1&loop=0&controls=0&progress_bar=0&play_button=0&volume_control=0&fullscreen_button=0&timestamp=0&music_info=0&description=0&rel=0&native_context_menu=0&closed_caption=0`, tiktok: true },
  medal: { url: (m) => `https://medal.tv/clip/${encodeURIComponent(m.id)}?autoplay=1&mute=0&loop=0&controls=0` },
  instagram: { url: (m) => `https://www.instagram.com/${m.ptype === 'reel' ? 'reel' : 'p'}/${encodeURIComponent(m.id)}/embed/`, click: [0.5, 0.42] },
  dailymotion: { url: (m, p) => `https://www.dailymotion.com/embed/video/${encodeURIComponent(m.id)}?autoplay=1&mute=0&start=${p}&queue-enable=false&ui-start-screen-info=0&sharing-enable=false&ui-logo=0`, startSync: true },
  rumble: { url: (m, p) => `https://rumble.com/embed/${encodeURIComponent(m.embed)}/?autoplay=2&start=${p}`, startSync: true },
  streamable: { url: (m, p) => `https://streamable.com/e/${encodeURIComponent(m.id)}?autoplay=1&nocontrols=1&t=${p}`, startSync: true },
  kick: { url: (m) => `https://player.kick.com/${encodeURIComponent(m.channel)}?autoplay=true&muted=false` },
};
class EmbedAdapter {
  constructor(m, o) {
    this.m = m; this.o = o; this.ready = true; this.on = false;
    this.noSync = !o.startSync; this.driftLimit = 6;
    if (!m.paused) this.load(o.startSync ? expectedPos(m) : 0);
  }
  load(pos) {
    this.kill();
    const f = document.createElement('iframe');
    f.allow = 'autoplay; encrypted-media; fullscreen; picture-in-picture';
    f.src = this.o.url(this.m, Math.floor(pos));
    playerEl.appendChild(f);
    this.f = f; this.on = true; this.base = pos; this.t0 = performance.now();
    setTimeout(() => setBuffer(false), 1800);
    if (this.o.click) {
      const [x, y] = this.o.click;
      setTimeout(() => { if (this.f === f) report('click', { x, y }); }, 2600);
    }
  }
  kill() { if (this.f) this.f.remove(); this.f = null; this.on = false; }
  time() { return this.on ? this.base + (performance.now() - this.t0) / 1000 : expectedPos(this.m); }
  seek(t) { if (this.o.startSync && !this.silenced) this.load(t); }
  play() { if (!this.on && !this.silenced) this.load(this.o.startSync ? expectedPos(this.m) : 0); }
  pause() { if (this.on) this.kill(); }
  update(m) { this.m = m; }
  post(type) { try { this.f.contentWindow.postMessage({ type, 'x-tiktok-player': true }, '*'); } catch (e) {} }
  setVolume(v) {
    if (this.o.tiktok && this.f) this.post(v < 0.02 ? 'mute' : 'unMute');
    if (v < 0.015 && this.on && !this.o.tiktok) { this.silenced = true; this.kill(); }
    else if (v > 0.03 && this.silenced) { this.silenced = false; if (!this.m.paused || this.m.live) this.load(this.o.startSync ? expectedPos(this.m) : 0); }
  }
  destroy() { this.kill(); }
}

/* <video>/<audio> + hls.js with a WebAudio chain for muffling and stereo */
class HtmlAdapter {
  constructor(m) {
    this.m = m; this.src = mediaUrl(m); this.cors = true; this.audioOnly = m.kind === 'audio'; this.seekLead = 0.05;
    const el = document.createElement(this.audioOnly ? 'audio' : 'video');
    el.playsInline = true; el.autoplay = true; el.preload = 'auto';
    el.crossOrigin = 'anonymous';
    this.el = el;
    el.addEventListener('loadedmetadata', () => {
      this.ready = true;
      if (!this.durRep) {
        this.durRep = true;
        const d = el.duration;
        report('duration', isFinite(d) && d > 0 && !this.liveHls ? d : 0);
      }
      syncCheck();
    });
    el.addEventListener('playing', () => { setBuffer(false); this.graph(); });
    el.addEventListener('waiting', () => setBuffer(true));
    el.addEventListener('ended', () => report('ended'));
    el.addEventListener('error', () => this.fail());
    playerEl.appendChild(el);
    if (this.audioOnly) showAudioViz(m, this);
    this.attach();
  }
  attach() {
    const isHls = this.m.kind === 'hls' || this.m.kind === 'reddit' || (this.m.kind === 'kick' && this.m.hls) || /\.m3u8(\?|$)/i.test(this.src);
    if (isHls && window.Hls && Hls.isSupported()) {
      this.hls = new Hls({ lowLatencyMode: !!this.m.live, backBufferLength: 30, maxBufferLength: 30 });
      this.hls.on(Hls.Events.LEVEL_LOADED, (_, d) => { if (d.details && d.details.live) this.liveHls = true; });
      this.hls.on(Hls.Events.ERROR, (_, d) => {
        if (!d.fatal) return;
        if (d.type === Hls.ErrorTypes.NETWORK_ERROR && (this.retries = (this.retries || 0) + 1) < 4) this.hls.startLoad();
        else if (d.type === Hls.ErrorTypes.MEDIA_ERROR) this.hls.recoverMediaError();
        else { report('error', 'hls ' + d.details); osdToast('The stream could not be loaded'); }
      });
      this.hls.loadSource(this.src);
      this.hls.attachMedia(this.el);
    } else {
      this.el.src = this.src;
    }
  }
  fail() {
    // no CORS headers: retry as a plain element (volume only, no muffling)
    if (this.cors && !this.hls) {
      this.cors = false;
      this.el.removeAttribute('crossorigin');
      this.el.src = this.src;
      return;
    }
    report('error', 'media ' + (this.el.error && this.el.error.code));
    osdToast('This file could not be played');
  }
  graph() {
    if (this.ctx || !this.cors) { this.apply(); return; }
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const src = ctx.createMediaElementSource(this.el);
      this.lp = ctx.createBiquadFilter(); this.lp.type = 'lowpass'; this.lp.frequency.value = 22000; this.lp.Q.value = 0.7;
      this.pan = ctx.createStereoPanner ? ctx.createStereoPanner() : null;
      this.gain = ctx.createGain();
      this.analyser = ctx.createAnalyser(); this.analyser.fftSize = 256;
      let node = src.connect(this.lp);
      if (this.pan) node = node.connect(this.pan);
      node.connect(this.gain).connect(this.analyser).connect(ctx.destination);
      this.el.volume = 1;
      this.ctx = ctx;
      if (ctx.state === 'suspended') ctx.resume();
    } catch (e) { this.ctx = null; this.cors = false; }
    this.apply();
  }
  apply() {
    const a = S.audio;
    if (this.ctx) {
      const t = this.ctx.currentTime;
      this.gain.gain.setTargetAtTime(a.volume, t, 0.08);
      this.lp.frequency.setTargetAtTime(clamp(a.lowpass, 200, 22000), t, 0.12);
      if (this.pan) this.pan.pan.setTargetAtTime(a.pan, t, 0.1);
    } else {
      this.el.volume = clamp(a.volume, 0, 1);
    }
  }
  time() { return this.el.currentTime; }
  seek(t) { try { this.el.currentTime = t; } catch (e) {} }
  play() { if (this.el.paused) this.el.play().catch(() => {}); }
  pause() { if (!this.el.paused) this.el.pause(); }
  setRate(r) { if (Math.abs(this.el.playbackRate - r) > 0.001) this.el.playbackRate = r; }
  setVolume() { this.apply(); }
  destroy() {
    hideAudioViz();
    if (this.hls) this.hls.destroy();
    this.el.pause(); this.el.removeAttribute('src'); try { this.el.load(); } catch (e) {}
    this.el.remove();
    if (this.ctx) this.ctx.close();
  }
}

class ImageAdapter {
  constructor(m) {
    this.ready = true; this.noSync = true;
    this.img = new Image();
    this.img.onload = () => setBuffer(false);
    this.img.onerror = () => osdToast('Image could not be loaded');
    this.img.src = mediaUrl(m);
    playerEl.appendChild(this.img);
  }
  time() { return 0; } seek() {} play() {} pause() {} setVolume() {}
  destroy() { this.img.remove(); }
}

function makeAdapter(m) {
  switch (m.kind) {
    case 'youtube': return new YouTubeAdapter(m);
    case 'twitch': return new TwitchAdapter(m);
    case 'kick': return m.hls ? new HtmlAdapter(m) : new EmbedAdapter(m, EMBEDS.kick);
    case 'vimeo': return new VimeoAdapter(m);
    case 'soundcloud': return new SoundCloudAdapter(m);
    case 'streamable': return m.direct ? new HtmlAdapter(m) : new EmbedAdapter(m, EMBEDS.streamable);
    case 'tiktok': case 'medal': case 'instagram': case 'dailymotion': case 'rumble': return new EmbedAdapter(m, EMBEDS[m.kind]);
    case 'image': return new ImageAdapter(m);
    default: return new HtmlAdapter(m);
  }
}

/* audio-only visualiser */
let vizRaf = 0;
function showAudioViz(m, ad) {
  $('#audioViz').classList.remove('hidden');
  $('#avTitle').textContent = m.title || 'Audio';
  $('#avSub').textContent = (m.by ? 'Played by ' + m.by : 'Now playing');
  const art = document.querySelector('.av-art');
  art.style.backgroundImage = m.thumb ? `url("${m.thumb}")` : '';
  const cv = $('#avCanvas'), g = cv.getContext('2d');
  const bars = 64, buf = new Uint8Array(128);
  const draw = () => {
    vizRaf = requestAnimationFrame(draw);
    g.clearRect(0, 0, cv.width, cv.height);
    if (ad.analyser) ad.analyser.getByteFrequencyData(buf);
    const t = performance.now() / 1000;
    for (let i = 0; i < bars; i++) {
      let v = ad.analyser ? buf[Math.floor(i * 1.6)] / 255 : (ad.el && !ad.el.paused ? 0.25 + 0.35 * Math.abs(Math.sin(t * 2.2 + i * 0.45) * Math.cos(t * 1.3 + i * 0.13)) : 0.04);
      const h = Math.max(6, v * cv.height);
      const x = i * (cv.width / bars);
      const grd = g.createLinearGradient(0, cv.height - h, 0, cv.height);
      grd.addColorStop(0, '#0fd4c4'); grd.addColorStop(1, 'rgba(6,125,116,.35)');
      g.fillStyle = grd;
      g.fillRect(x + 3, cv.height - h, cv.width / bars - 8, h);
    }
  };
  cancelAnimationFrame(vizRaf);
  draw();
}
function hideAudioViz() { cancelAnimationFrame(vizRaf); $('#audioViz').classList.add('hidden'); }

/* ─────────────── media lifecycle ─────────────── */
let bufTimer = 0;
function setBuffer(on) {
  clearTimeout(bufTimer);
  if (on) bufTimer = setTimeout(() => $('#buffer').classList.remove('hidden'), 600);
  else $('#buffer').classList.add('hidden');
}

function destroyAdapter() {
  if (S.adapter) { try { S.adapter.destroy(); } catch (e) {} }
  S.adapter = null; S.mediaKey = null;
  playerEl.innerHTML = '';
  setBuffer(false);
}

function mediaChanged(initial) {
  const m = S.tv && S.tv.media;
  if (!m) {
    destroyAdapter();
    hideInfo();
    if (S.ui.page === 'player') S.ui.page = 'home';
    render();
    return;
  }
  if (m.key !== S.mediaKey) {
    destroyAdapter();
    S.mediaKey = m.key;
    setBuffer(true);
    S.adapter = makeAdapter(m);
    applyAudio();
    if (!initial || S.ui.page === 'home') S.ui.page = 'player';
    S.ui.sources = false;
    render();
    if (!S.booting) showInfo(5000);
  } else {
    const wasPaused = S.lastPaused;
    if (S.adapter && S.adapter.update) S.adapter.update(m);
    syncCheck();
    if (wasPaused !== m.paused) showInfo(m.paused ? 0 : 3000);
    render();
  }
  S.lastPaused = m.paused;
}

/* drift correction — keeps every viewer frame-close to the server clock */
function syncCheck() {
  const a = S.adapter, m = S.tv && S.tv.media;
  if (!a || !m || !a.ready || m.live || !S.tv.power) return;
  if (a.noSync) { if (m.paused) a.pause(); else a.play(); return; }
  const exp = expectedPos(m);
  if (m.duration && exp > m.duration) return;
  const diff = exp - a.time();
  if (m.paused) {
    a.pause();
    if (Math.abs(diff) > 0.5) a.seek(exp);
    return;
  }
  a.play();
  if (Math.abs(diff) > (a.driftLimit || S.sync.SeekDrift)) {
    a.seek(exp + (a.seekLead || 0));
    if (a.setRate) a.setRate(1);
  } else if (a.setRate) {
    a.setRate(Math.abs(diff) > S.sync.NudgeDrift ? 1 + clamp(diff * 0.5, -0.08, 0.08) : 1);
  }
}
setInterval(syncCheck, 1000);

function applyAudio() { if (S.adapter && S.adapter.setVolume) S.adapter.setVolume(S.audio.volume); }

/* ═══════════════ TV OS ═══════════════ */
/* streaming apps use their real logo on a brand-coloured tile */
const BRAND_APPS = ['youtube', 'tiktok', 'twitch', 'kick', 'vimeo', 'soundcloud', 'plex', 'pluto', 'medal', 'streamable', 'instagram', 'dailymotion', 'reddit', 'rumble'];
const LINK_ONLY = { tiktok: 1, vimeo: 1, soundcloud: 1, medal: 1, streamable: 1, instagram: 1, dailymotion: 1, reddit: 1, rumble: 1 };
let APPS = [];
function buildApps() {
  APPS = BRAND_APPS.filter((k) => k !== 'plex' || S.plex).map((k) => ({ id: k, label: (BRANDS[k] && BRANDS[k].name) || k, brand: k })).concat(BASE_APPS);
}
const BASE_APPS = [
  { id: 'web', label: 'Web Video', cls: 'ap-web', icon: 'link' },
  { id: 'library', label: 'Library', cls: 'ap-lib', icon: 'library' },
  { id: 'queue', label: 'Up Next', cls: 'ap-q', icon: 'queue' },
  { id: 'channels', label: 'Channels', cls: 'ap-ch', icon: 'tv' },
  { id: 'settings', label: 'Settings', cls: 'ap-set', icon: 'settings' },
];
buildApps();
let SEARCH_SRC = [];
function buildSources() {
  SEARCH_SRC = ['youtube', 'tiktok', 'twitch', 'kick', 'vimeo', 'soundcloud'].concat(S.plex ? ['plex'] : [])
    .map((k) => ({ id: k, label: BRANDS[k] ? BRANDS[k].name : k, brand: k })).concat([{ id: 'web', label: 'Any link' }]);
  // a link-only app opened from the grid gets its own chip
  if (S.ui && S.ui.src && !SEARCH_SRC.some((x) => x.id === S.ui.src) && BRANDS[S.ui.src]) SEARCH_SRC.splice(SEARCH_SRC.length - 1, 0, { id: S.ui.src, label: BRANDS[S.ui.src].name, brand: S.ui.src });
}
buildSources();
const SETTINGS = [
  { key: 'picture', label: 'Picture mode', sub: 'Colour and contrast of the picture', values: ['standard', 'vivid', 'cinema', 'warm', 'game'] },
  { key: 'fit', label: 'Picture size', sub: 'How video fills the screen', values: ['contain', 'cover', 'stretch'] },
  { key: 'loop', label: 'Repeat', sub: 'Replay when the video ends', values: [false, true] },
  { key: 'ambient', label: 'Ambient mode', sub: 'Clock screensaver when idle', values: [true, false] },
  { key: 'osd', label: 'On-screen info', sub: 'Show title bar when playback changes', values: [true, false] },
  { key: 'about', label: 'About this TV', sub: '', values: null },
];
const VAL_LABEL = { standard: 'Standard', vivid: 'Vivid', cinema: 'Cinema', warm: 'Warm', game: 'Game', contain: 'Fit', cover: 'Fill', stretch: 'Stretch', true: 'On', false: 'Off' };

const RAIL_PAGE = { home: 3, search: 1, list: 4 };

function mediaCard(e, extra) {
  return Object.assign({ type: 'media', url: e.url, title: e.title || e.url, sub: e.sub || klabel(e.kind, e.brand) + (e.by ? ' · ' + e.by : ''),
    thumb: e.thumb, kind: e.kind, brand: e.brand, live: e.live, by: e.by, pos: e.pos, dur: e.dur }, extra || {});
}
const minsLeft = (pos, dur) => { const m = Math.max(1, Math.round((dur - pos) / 60)); return m >= 60 ? Math.floor(m / 60) + 'h ' + (m % 60) + 'm left' : m + ' min left'; };

function homeRows() {
  const t = S.tv, tab = S.ui.tab;
  if (tab === 1) {
    const ch = (S.channels || []).map((c, i) => ({ type: 'media', url: c.url, title: c.name, sub: (c.group ? c.group + ' · ' : '') + 'Channel ' + (c.number || i + 1), num: c.number || i + 1, live: /twitch|kick|m3u8/i.test(c.url) || !!c.brand, thumb: c.thumb, brand: c.brand, kind: /youtu/i.test(c.url) ? 'youtube' : /twitch/i.test(c.url) ? 'twitch' : /kick/i.test(c.url) ? 'kick' : 'video', ch: i + 1 }));
    const fe = (S.featured || []).filter((f) => f.url).map((f) => ({ type: 'media', url: f.url, title: f.title, sub: f.subtitle, thumb: f.image }));
    return [
      { title: 'Channels', sub: ch.length ? ch.length + ' channels · CH ▲ ▼ on your remote' : 'CH ▲ ▼ on your remote', items: ch.length ? ch : [{ type: 'empty', label: 'No channels set up on this server' }] },
      { title: 'Featured', items: fe.length ? fe : [{ type: 'empty', label: 'Nothing featured right now' }] },
    ];
  }
  if (tab === 2) {
    const q = (t.queue || []).map((e, i) => mediaCard(e, { qi: i + 1 }));
    return [
      { title: 'Apps', apps: true, items: APPS.map((a) => Object.assign({ type: 'app' }, a)) },
      { title: 'Up Next', sub: q.length ? q.length + ' queued' : '', items: q.length ? q : [{ type: 'empty', label: 'The queue is empty' }] },
    ];
  }
  const m = t.media;
  const h = (t.history || []).filter((e) => !m || e.url !== m.url).map((e) => mediaCard(e));
  if (m) h.unshift({ type: 'media', now: true, url: m.url, title: m.title || klabel(m.kind, m.brand), sub: klabel(m.kind, m.brand), thumb: m.kind === 'image' ? null : m.thumb, kind: m.kind, brand: m.brand, live: m.live, by: m.by });
  return [
    { title: m ? 'Now Playing & Continue Watching' : 'Continue Watching', items: h.length ? h : [{ type: 'empty', label: 'Things you watch show up here' }] },
    { title: 'Apps', apps: true, items: APPS.map((a) => Object.assign({ type: 'app' }, a)) },
  ];
}

function listItems() {
  const l = S.ui.list;
  if (l === 'library') {
    return (S.library || []).map((f) => ({ type: 'media', url: 'local:' + f.file, title: f.title || f.file, sub: f.subtitle || 'Server library', thumb: f.thumb,
      kind: /\.(png|jpe?g|gif|webp)$/i.test(f.file) ? 'image' : /\.(mp3|wav|ogg|m4a)$/i.test(f.file) ? 'audio' : 'video' }));
  }
  if (l === 'queue') return (S.tv.queue || []).map((e, i) => mediaCard(e, { qi: i + 1 }));
  if (l === 'settings') return SETTINGS.map((s) => Object.assign({ type: 'setting' }, s));
  return [];
}

function zoneLen(z) {
  if (z === 'hero') return 1;
  if (z === 'tabs') return 3;
  if (z === 'rail') return 7;
  if (z === 'sbox') return 1;
  if (z === 'chips') return SEARCH_SRC.length;
  if (z === 'results') return S.results.length;
  if (z === 'list') return listItems().length;
  if (z === 'sources') return APPS.length - 1;
  if (z.startsWith('row')) { const r = homeRows()[+z.slice(3)]; return r ? r.items.length : 0; }
  return 0;
}
const idx = (z) => clamp(S.ui.idx[z] || 0, 0, Math.max(0, zoneLen(z) - 1));

function zoneOrder() {
  const p = S.ui.page;
  if (p === 'home') return ['hero', 'tabs', ...homeRows().map((_, i) => 'row' + i)];
  if (p === 'search') return S.results.length ? ['sbox', 'chips', 'results'] : ['sbox', 'chips'];
  if (p === 'list') return ['list'];
  return [];
}

/* ─────────────── input ─────────────── */
function onKey(key, mine) {
  const wasAmbient = !$('#ambient').classList.contains('hidden');
  S.lastInput = Date.now();
  if (wasAmbient) { hideAmbient(); return; }
  if (!S.tv || !S.tv.power || S.booting) return;
  const ui = S.ui, m = S.tv.media;

  if (key === 'info') { $('#osdInfo').classList.contains('hidden') ? showInfo(6000) : hideInfo(); return; }
  if (key.startsWith('app:')) {
    ui.sources = false;
    openApp(key.slice(4), mine);
    render();
    return report2(mine);
  }
  if (key === 'home') {
    ui.sources = false;
    if (ui.page === 'home' && m) ui.page = 'player';
    else { ui.page = 'home'; ui.zone = 'tabs'; }
  } else if (key === 'sources') {
    ui.sources = !ui.sources; ui.idx.sources = 0;
  } else if (key === 'search') {
    openSearch(ui.src);
  } else if (key === 'settings') {
    openList('settings');
  } else if (key === 'back') {
    if (ui.sources) ui.sources = false;
    else if (ui.zone === 'rail') ui.zone = ui.prevZone || 'tabs';
    else if (ui.page === 'search' || ui.page === 'list') { ui.page = 'home'; ui.zone = 'tabs'; }
    else if (ui.page === 'home' && m) ui.page = 'player';
  } else if (ui.sources) {
    navSources(key, mine);
  } else if (ui.page === 'player') {
    if (key === 'ok' || key === 'up' || key === 'down') showInfo(5000);
    else if ((key === 'left' || key === 'right') && mine && m && !m.live) action({ action: 'control', name: 'seekRel', data: key === 'left' ? -10 : 10 });
    if (key === 'left' || key === 'right') showInfo(3000);
    return report2(mine);
  } else {
    navigate(key, mine);
  }
  render();
  report2(mine);
}
function report2(mine) { if (mine) report('ui', S.ui); }

function navSources(key, mine) {
  const n = zoneLen('sources');
  const i = idx('sources');
  if (key === 'up') S.ui.idx.sources = clamp(i - 1, 0, n - 1);
  else if (key === 'down') S.ui.idx.sources = clamp(i + 1, 0, n - 1);
  else if (key === 'ok') { S.ui.sources = false; openApp(APPS[i].id, mine); }
}

function navigate(key, mine) {
  const ui = S.ui;
  if (ui.zone === 'rail') {
    if (key === 'up') ui.railIdx = clamp(ui.railIdx - 1, 0, 6);
    else if (key === 'down') ui.railIdx = clamp(ui.railIdx + 1, 0, 6);
    else if (key === 'right') ui.zone = ui.prevZone || zoneOrder()[0];
    else if (key === 'ok') railSelect(ui.railIdx, mine);
    return;
  }
  const order = zoneOrder();
  if (!order.includes(ui.zone)) ui.zone = order[0] || 'tabs';
  const z = ui.zone, zi = order.indexOf(z), i = idx(z), n = zoneLen(z);
  const grid = z === 'results' ? 4 : 1;

  if (key === 'left') {
    if (z === 'list' || z === 'sbox' || i === 0 || (z === 'results' && i % grid === 0)) {
      ui.prevZone = z; ui.zone = 'rail'; ui.railIdx = RAIL_PAGE[ui.page] != null ? RAIL_PAGE[ui.page] : 3;
      if (ui.page === 'list') ui.railIdx = { library: 4, queue: 5, settings: 6 }[ui.list] || 4;
    } else {
      ui.idx[z] = i - 1;
      if (z === 'tabs') { ui.tab = i - 1; resetRows(); }
    }
  } else if (key === 'right') {
    if (i < n - 1) {
      ui.idx[z] = i + 1;
      if (z === 'tabs') { ui.tab = i + 1; resetRows(); }
    }
  } else if (key === 'up') {
    if (z === 'list' && i > 0) ui.idx.list = i - 1;
    else if (z === 'results' && i >= grid) ui.idx.results = i - grid;
    else if (zi > 0) ui.zone = order[zi - 1];
  } else if (key === 'down') {
    if (z === 'list' && i < n - 1) ui.idx.list = i + 1;
    else if (z === 'results' && i + grid < n) ui.idx.results = i + grid;
    else if (zi < order.length - 1) ui.zone = order[zi + 1];
  } else if (key === 'ok') {
    activate(z, i, mine);
  }
}

function resetRows() { Object.keys(S.ui.idx).forEach((k) => { if (k.startsWith('row')) S.ui.idx[k] = 0; }); }

function railSelect(i, mine) {
  const ui = S.ui;
  if (i === 0) { ui.zone = ui.prevZone || 'tabs'; return; }
  if (i === 1) openSearch(ui.src);
  else if (i === 2) { ui.sources = true; ui.idx.sources = 0; ui.zone = ui.prevZone || 'tabs'; }
  else if (i === 3) { ui.page = 'home'; ui.zone = 'tabs'; }
  else if (i === 4) openList('library');
  else if (i === 5) openList('queue');
  else if (i === 6) openList('settings');
}

function openSearch(src) {
  const ui = S.ui;
  ui.page = 'search'; ui.zone = 'sbox'; ui.src = src || ui.src || 'youtube';
  buildSources();
  ui.idx.chips = Math.max(0, SEARCH_SRC.findIndex((s) => s.id === ui.src));
  computeResults();
}
function openList(which) { S.ui.page = 'list'; S.ui.list = which; S.ui.zone = 'list'; S.ui.idx.list = 0; }

function openApp(id, mine) {
  if (id === 'pluto') { S.ui.page = 'home'; S.ui.tab = 1; S.ui.idx.tabs = 1; S.ui.zone = 'row0'; resetRows(); return; }
  if (id === 'plex') { openSearch('plex'); S.results = []; S.searchMsg = 'Loading your Plex library…'; if (mine) action({ action: 'plex' }); return; }
  if (BRANDS[id] || id === 'web') openSearch(id);
  else if (id === 'library' || id === 'queue' || id === 'settings') openList(id);
  else if (id === 'channels') { S.ui.page = 'home'; S.ui.tab = 1; S.ui.idx.tabs = 1; S.ui.zone = 'row0'; resetRows(); }
}

function playItem(it, mine) {
  const m = S.tv.media;
  if (m && m.url === it.url) { S.ui.page = 'player'; return; }
  if (!mine) return;
  if (it.qi) action({ action: 'control', name: 'qPlay', data: it.qi });
  else action({ action: 'play', url: it.url, title: it.title, start: it.pos || undefined, thumb: it.thumb, duration: it.plexDur });
}

function activate(z, i, mine) {
  const ui = S.ui, m = S.tv.media;
  if (z === 'hero') {
    if (m) { ui.page = 'player'; return; }
    const f = S.featured[S.heroIdx % Math.max(1, S.featured.length)];
    if (f && f.url) { if (mine) action({ action: 'play', url: f.url, title: f.title }); }
    else ui.zone = 'tabs';
  } else if (z === 'tabs') {
    ui.zone = 'row0';
  } else if (z.startsWith('row')) {
    const it = homeRows()[+z.slice(3)].items[i];
    if (!it || it.type === 'empty') return;
    if (it.type === 'app') openApp(it.id, mine);
    else playItem(it, mine);
  } else if (z === 'sbox') {
    if (mine) action({ action: 'keyboard', value: S.query, hint: ui.src === 'youtube' ? 'Search YouTube or paste a link' : ui.src === 'web' ? 'Paste a video or stream link' : 'Channel name or link' });
  } else if (z === 'chips') {
    ui.src = SEARCH_SRC[i].id;
    if (ui.src === 'plex') { S.results = []; S.searchMsg = 'Loading your Plex library…'; if (mine) action({ action: 'plex' }); return; }
    computeResults(mine);
  } else if (z === 'results') {
    const it = S.results[i];
    if (it) playItem(it, mine);
  } else if (z === 'list') {
    const it = listItems()[i];
    if (!it) return;
    if (it.type === 'setting') {
      if (!it.values) { osdToast(`${S.brand.os || 'NAYZEEE OS'} ${S.brand.version || ''} · ${S.tv.label}`); return; }
      const cur = it.key === 'loop' ? !!S.tv.loop : (S.tv.settings || {})[it.key];
      const vi = it.values.indexOf(cur == null ? it.values[0] : cur);
      const next = it.values[(vi + 1) % it.values.length];
      if (mine) {
        if (it.key === 'loop') action({ action: 'control', name: 'loop', data: next });
        else action({ action: 'control', name: 'setting', data: { key: it.key, value: next } });
      }
    } else playItem(it, mine);
  }
}

const LINK_HOSTS = { youtube: /youtu\.?be/i, twitch: /twitch\.tv/i, kick: /kick\.com/i, tiktok: /tiktok\.com/i, vimeo: /vimeo\.com/i,
  soundcloud: /soundcloud\.com/i, streamable: /streamable\.com/i, medal: /medal\.tv/i, instagram: /instagram\.com/i,
  dailymotion: /dailymotion\.com|dai\.ly/i, reddit: /redd\.?it/i, rumble: /rumble\.com/i };
const looksUrl = (t) => /^(https?:\/\/|local:|[\w-]+\.[a-z]{2,}\/)/i.test(t.trim());

function computeResults(mine) {
  const q = (S.query || '').trim(), src = S.ui.src;
  S.searchMsg = '';
  if (!q) { S.results = []; return; }
  if (looksUrl(q)) {
    const k = Object.keys(LINK_HOSTS).find((key) => LINK_HOSTS[key].test(q)) || 'video';
    S.results = [{ type: 'media', url: q, title: 'Play this ' + (k === 'video' ? 'link' : klabel(k) + ' link'), sub: q, kind: k }];
  } else if (src === 'twitch') {
    const ch = q.replace(/\s+/g, '').toLowerCase();
    S.results = [{ type: 'media', url: 'https://www.twitch.tv/' + ch, title: ch, sub: 'Twitch channel', live: true, kind: 'twitch', thumb: `https://static-cdn.jtvnw.net/previews-ttv/live_user_${ch}-640x360.jpg` }];
  } else if (src === 'kick') {
    const ch = q.replace(/\s+/g, '').toLowerCase();
    S.results = [{ type: 'media', url: 'https://kick.com/' + ch, title: ch, sub: 'Kick channel', live: true, kind: 'kick' }];
  } else if (src === 'web') {
    S.results = []; S.searchMsg = 'Paste a full link to a video, stream or image.';
  } else if (LINK_ONLY[src]) {
    S.results = []; S.searchMsg = `Paste a ${klabel(src)} link — press OK on the search box.`;
  } else if (src === 'plex') {
    S.searchMsg = S.results.length ? '' : 'Pick something from your library';
  } else {
    S.results = []; S.searchMsg = 'Searching YouTube…';
    if (mine) action({ action: 'search', q });
  }
}

function onTyped(text, mine) {
  S.lastInput = Date.now();
  hideAmbient();
  S.query = String(text || '').slice(0, 256);
  if (S.ui.page !== 'search') openSearch(S.ui.src);
  computeResults(mine);
  if (S.results.length) { S.ui.zone = 'results'; S.ui.idx.results = 0; }
  render();
  report2(mine);
}

function onOsData(d) {
  if (!d) return;
  if (d.kind === 'plex') {
    S.results = (d.results || []).map((r) => ({ type: 'media', url: r.url, title: r.title, sub: r.sub, thumb: r.thumb, kind: 'plex', brand: 'plex', dur: r.duration, plexDur: r.duration }));
    S.searchMsg = S.results.length ? '' : 'Your Plex library is empty';
    if (S.results.length && S.ui.page === 'search' && S.ui.src === 'plex') { S.ui.zone = 'results'; S.ui.idx.results = 0; }
  } else if (d.kind === 'search' && d.q === S.query.trim()) {
    S.results = (d.results || []).map((r) => ({ type: 'media', url: r.url, title: r.title, sub: r.channel, thumb: r.thumb, kind: 'youtube' }));
    S.searchMsg = S.results.length ? '' : 'No results for “' + d.q + '”';
    if (S.results.length && S.ui.page === 'search') { S.ui.zone = 'results'; S.ui.idx.results = 0; }
  } else if (d.kind === 'searchError') {
    S.searchMsg = d.text;
  }
  render();
}

/* ─────────────── rendering ─────────────── */
function bg(el, url) { el.style.backgroundImage = url ? `url("${url}")` : ''; el.classList.toggle('art', !url); }

function cardHtml(it, focus) {
  if (it.type === 'empty') return `<div class="card empty ${focus ? 'focus' : ''}"><span>${esc(it.label)}</span></div>`;
  if (it.type === 'app') return appHtml(it, focus);
  const style = it.thumb ? `style="background-image:url('${esc(it.thumb)}')"` : '';
  if (it.now) {
    const m = S.tv.media;
    const pct = m && m.duration ? clamp(expectedPos(m) / m.duration, 0, 1) * 100 : (m && m.live ? 100 : 0);
    return `<div class="card now ${it.thumb ? '' : 'art'} ${focus ? 'focus' : ''}" ${style}>
      <span class="c-now"><span class="eq ${m && m.paused ? 'paused' : ''}"><i></i><i></i><i></i></span>${m && m.live ? 'Live now' : m && m.paused ? 'Paused' : 'Now playing'}</span>
      <div class="c-meta"><b>${esc(it.title)}</b><span>${esc(it.sub || '')}${it.by ? ' · ' + esc(it.by) : ''}</span></div>
      <div class="c-prog ${m && m.live ? 'live' : ''}"><i data-np-prog style="width:${pct}%"></i></div></div>`;
  }
  const live = it.live ? '<span class="c-badge live">● Live</span>' : '';
  const kind = it.num ? `<span class="c-num">${it.num}</span>` : `<span class="c-kind">${kicon(it.kind, it.brand)}</span>`;
  const prog = it.pos && it.dur ? `<span class="c-left">${minsLeft(it.pos, it.dur)}</span><div class="c-prog"><i style="width:${clamp(it.pos / it.dur, 0, 1) * 100}%"></i></div>` : '';
  return `<div class="card ${it.thumb ? '' : 'art'} ${it.ch ? 'chan' : ''} ${focus ? 'focus' : ''}" ${style}>
    ${kind}${live}<div class="c-meta"><b>${esc(it.title)}</b><span>${esc(it.sub || '')}</span></div>${prog}</div>`;
}

function appHtml(it, focus) {
  const inner = it.brand ? `<i class="brand" style="${tileStyle(it.brand)}">${window.brandSvg(it.brand, 70)}</i>` : `<i class="${it.cls}">${I[it.icon]}</i>`;
  return `<div class="app ${focus ? 'focus' : ''} ${it.brand === 'tiktok' ? 'tt' : ''}">${inner}<b>${esc(it.label)}</b></div>`;
}

/* details line under the focused row, like a real smart TV */
function detailHtml(it) {
  if (!it || it.type === 'empty') return '';
  if (it.type === 'app') {
    const desc = { youtube: 'Videos, live streams and playlists', twitch: 'Live channels, VODs and clips', kick: 'Live channels', web: 'Any video, stream or image link',
      library: 'Media stored on this server', queue: 'What plays next on this screen', channels: 'Preset channels — CH ▲ ▼ on the remote', settings: 'Picture, repeat and screen options' }[it.id] || '';
    return `<div class="row-detail"><b>${esc(it.label)}</b><div class="rd-meta"><span>${esc(desc)}</span><span class="sep"></span><span class="ok">Press OK to open</span></div></div>`;
  }
  const parts = [`<span class="pill">${kicon(it.kind, it.brand)}${esc(klabel(it.kind, it.brand))}</span>`];
  if (it.now) parts.push(`<span class="ok">${S.tv.media && S.tv.media.paused ? 'Paused' : 'Playing on this screen'}</span>`);
  else if (it.live) parts.push('<span class="ok">Live now</span>');
  else if (it.pos && it.dur) parts.push(`<span class="ok">Resume at ${fmt(it.pos)}</span><span class="sep"></span><span>${minsLeft(it.pos, it.dur)}</span>`);
  else if (it.qi) parts.push(`<span class="ok">#${it.qi} in the queue</span>`);
  if (it.by) parts.push(`<span class="sep"></span><span>${esc(it.by)}</span>`);
  if (it.ch) parts.push(`<span class="sep"></span><span>CH ${it.num}</span>`);
  return `<div class="row-detail"><b>${esc(it.title)}</b><div class="rd-meta">${parts.join('')}</div></div>`;
}

function heroData() {
  const m = S.tv.media;
  if (m) {
    return { chip: m.live ? 'Live' : m.paused ? 'Paused' : 'Now Playing', live: !!m.live, title: m.title || klabel(m.kind, m.brand),
      sub: klabel(m.kind, m.brand) + (m.by ? ' · started by ' + m.by : ''), btn: 'Resume', img: m.kind === 'image' ? null : m.thumb };
  }
  const f = S.featured.length ? S.featured[S.heroIdx % S.featured.length] : null;
  if (f) return { chip: 'Featured', title: f.title, sub: f.subtitle || '', btn: f.url ? 'Watch Now' : 'Browse', img: f.image };
  return { chip: S.brand.os || 'NAYZEEE OS', title: 'Welcome home', sub: 'Pick something to watch with your remote', btn: 'Browse', img: null };
}

function heroMeta() {
  const m = S.tv.media;
  if (!m) return '';
  const out = [`<span class="hm hm-src">${kicon(m.kind, m.brand)}${esc(klabel(m.kind, m.brand))}</span>`];
  out.push(`<span class="hm hm-ok">${m.live ? 'Live' : m.paused ? 'Paused' : 'In sync with everyone nearby'}</span>`);
  if (m.duration) out.push(`<span class="sep"></span><span class="hm">${fmt(m.duration)}</span>`);
  if (m.items) out.push(`<span class="sep"></span><span class="hm">${m.index} of ${m.items.length}</span>`);
  if (S.tv.loop) out.push(`<span class="sep"></span><span class="hm">${I.loop.replace('<svg', '<svg width="22" height="22"')}Repeat</span>`);
  out.push(`<span class="hm hm-q">${(S.tv.settings || {}).picture === 'cinema' ? 'CINEMA' : 'HD'}</span>`);
  return out.join('');
}

function render() {
  if (!S.tv) return;
  const ui = S.ui, t = S.tv;
  const os = $('#os');
  const showOs = t.power && !S.booting && (ui.page !== 'player' || ui.sources);
  os.classList.toggle('hidden', !showOs);
  if (!showOs) return;
  os.classList.toggle('over-media', !!t.media);
  const overlayOnly = ui.page === 'player';
  ['.rail', '.topbar', '.os-bg', '.os-shade'].forEach((s) => { os.querySelector(s).style.display = overlayOnly ? 'none' : ''; });

  // rail
  const rail = $('#rail');
  rail.classList.toggle('open', ui.zone === 'rail' && !overlayOnly);
  const curRail = ui.page === 'list' ? ({ library: 4, queue: 5, settings: 6 }[ui.list]) : RAIL_PAGE[ui.page];
  rail.querySelectorAll('.rail-item').forEach((el) => {
    const i = +el.dataset.rail;
    el.classList.toggle('cur', i === curRail);
    el.classList.toggle('focus', ui.zone === 'rail' && i === ui.railIdx);
  });
  $('#railName').textContent = t.label || 'Guest';
  $('#tbLabel').textContent = t.label || '';

  ['Home', 'Search', 'List'].forEach((p) => $('#page' + p).classList.toggle('on', ui.page === p.toLowerCase()));

  if (ui.page === 'home') renderHome();
  else if (ui.page === 'search') renderSearch();
  else if (ui.page === 'list') renderList();

  // sources overlay
  const so = $('#sources');
  so.classList.toggle('hidden', !ui.sources);
  if (ui.sources) {
    const si = idx('sources');
    $('#srcList').innerHTML = APPS.slice(0, -1).map((a, i) => `<div class="src ${i === si ? 'focus' : ''}">${a.brand ? `<i style="${tileStyle(a.brand)}">${window.brandSvg(a.brand, 30)}</i>` : `<i class="${a.cls}">${I[a.icon]}</i>`}${esc(a.label)}</div>`).join('');
    const box = $('#srcList'), fEl = box.children[si];
    if (fEl) box.style.transform = `translateY(${-Math.max(0, fEl.offsetTop - 520)}px)`;
  }
}

function renderHome() {
  const ui = S.ui;
  const h = heroData();
  bg($('#osBg'), h.img);
  const chip = $('#heroChip');
  chip.textContent = h.chip; chip.classList.toggle('live', !!h.live);
  $('#heroTitle').textContent = h.title;
  $('#heroSub').textContent = h.sub;
  $('#heroBtn').textContent = h.btn;
  $('#heroMeta').innerHTML = heroMeta();
  document.querySelector('.hero-btn').classList.toggle('focus', ui.zone === 'hero');
  document.querySelectorAll('.tab').forEach((el, i) => {
    el.classList.toggle('cur', i === ui.tab);
    el.classList.toggle('focus', ui.zone === 'tabs' && i === idx('tabs'));
  });
  const rows = homeRows();
  $('#rows').innerHTML = rows.map((r, ri) => {
    const z = 'row' + ri, fi = ui.zone === z ? idx(z) : -1;
    const step = r.apps ? 202 : 466;
    const visible = r.apps ? 7 : 3;
    const shift = Math.max(0, (ui.zone === z ? idx(z) : (ui.idx[z] || 0)) - visible + 2) * step;
    return `<div class="row"><h4>${esc(r.title)}${r.sub ? `<small>${esc(r.sub)}</small>` : ''}</h4>
      <div class="row-track" style="transform:translateX(${-shift}px)">${r.items.map((it, i) => cardHtml(it, i === fi)).join('')}</div>
      ${fi >= 0 && ri > 0 ? detailHtml(r.items[fi]) : ''}</div>`;
  }).join('');
  const rowIndex = ui.zone.startsWith('row') ? +ui.zone.slice(3) : 0;
  $('#rows').style.transform = `translateY(${rowIndex > 0 ? -430 : 0}px)`;
  document.querySelector('.hero').style.opacity = rowIndex > 0 ? '0' : '1';
  document.querySelector('.tabs').style.opacity = rowIndex > 0 ? '0' : '1';
}

function renderSearch() {
  const ui = S.ui;
  $('#searchText').textContent = S.query;
  $('#searchPh').classList.toggle('hidden', !!S.query);
  document.querySelector('.search-box').classList.toggle('focus', ui.zone === 'sbox');
  $('#searchSources').innerHTML = SEARCH_SRC.map((s, i) =>
    `<div class="chip ${ui.src === s.id ? 'cur' : ''} ${ui.zone === 'chips' && idx('chips') === i ? 'focus' : ''}">${s.brand ? window.brandSvg(s.brand, 26) : I.link}${esc(s.label)}</div>`).join('');
  const fi = ui.zone === 'results' ? idx('results') : -1;
  $('#searchResults').innerHTML = S.results.map((it, i) => cardHtml(it, i === fi)).join('');
  const rowShift = fi >= 8 ? Math.floor((fi - 4) / 4) * 256 : 0;
  $('#searchResults').style.transform = `translateY(${-rowShift}px)`;
  $('#searchMsg').textContent = S.results.length ? '' : S.searchMsg;
}

function renderList() {
  const ui = S.ui, items = listItems(), fi = idx('list');
  const titles = { library: ['Library', 'Media stored on this server'], queue: ['Up Next', (S.tv.queue || []).length + ' in the queue'], settings: ['Settings', S.tv.label] };
  const [title, sub] = titles[ui.list] || ['', ''];
  $('#listTitle').textContent = title;
  $('#listSub').textContent = sub;
  const shift = Math.max(0, fi - 5) * 124;
  $('#list').style.transform = `translateY(${-shift}px)`;
  $('#list').innerHTML = items.length ? items.map((it, i) => {
    if (it.type === 'setting') {
      const cur = it.key === 'loop' ? !!S.tv.loop : (S.tv.settings || {})[it.key];
      const val = it.values ? (VAL_LABEL[String(cur == null ? it.values[0] : cur)] || cur) : (S.brand.version || '');
      return `<div class="li ${i === fi ? 'focus' : ''}"><div class="li-th">${I[it.key === 'loop' ? 'loop' : it.key === 'about' ? 'tv' : 'settings']}</div>
        <div class="li-t"><b>${esc(it.label)}</b><span>${esc(it.sub)}</span></div><div class="li-v">${esc(val)}${I.chev}</div></div>`;
    }
    return `<div class="li ${i === fi ? 'focus' : ''}"><div class="li-th" ${it.thumb ? `style="background-image:url('${esc(it.thumb)}')"` : ''}>${it.thumb ? '' : kicon(it.kind, it.brand)}</div>
      <div class="li-t"><b>${esc(it.title)}</b><span>${esc(it.sub || '')}</span></div><div class="li-v">${it.qi ? '#' + it.qi : ''}${I.play}</div></div>`;
  }).join('') : `<div class="li"><div class="li-t"><b>${ui.list === 'queue' ? 'Nothing queued' : 'Nothing here yet'}</b><span>${ui.list === 'queue' ? 'Add videos from the media panel or your phone' : 'Ask an admin to add files to the library'}</span></div></div>`;
}

/* ─────────────── OSD ─────────────── */
let infoTimer = 0, infoRaf = 0;
function showInfo(ms) {
  const m = S.tv && S.tv.media;
  if (!m || !S.tv.power) return;
  if (ms && S.tv.settings && S.tv.settings.osd === false) return;
  const el = $('#osdInfo');
  el.classList.remove('hidden');
  $('#oiThumb').style.backgroundImage = m.thumb ? `url("${m.thumb}")` : 'linear-gradient(150deg,#141b1c,#07090a)';
  const chip = $('#oiChip');
  chip.textContent = m.live ? '● Live' : klabel(m.kind, m.brand);
  chip.classList.toggle('live', !!m.live);
  $('#oiLabel').textContent = S.tv.label + (m.by ? ' · ' + m.by : '');
  $('#oiTitle').textContent = m.title || klabel(m.kind, m.brand);
  clearTimeout(infoTimer);
  if (ms) infoTimer = setTimeout(hideInfo, ms);
  cancelAnimationFrame(infoRaf);
  const tick = () => {
    const mm = S.tv && S.tv.media;
    if (!mm) return hideInfo();
    const pos = expectedPos(mm), dur = mm.duration || 0;
    const pct = dur ? clamp(pos / dur, 0, 1) * 100 : (mm.live ? 100 : 0);
    $('#oiFill').style.width = pct + '%';
    $('#oiKnob').style.left = pct + '%';
    $('#oiKnob').style.display = mm.live ? 'none' : '';
    $('#oiPos').textContent = mm.live ? 'Live' : fmt(pos);
    $('#oiDur').textContent = mm.live ? '' : dur ? fmt(dur) : '--:--';
    $('#oiState').textContent = mm.paused ? 'Paused' : S.tv.loop ? 'Repeat on' : '';
    infoRaf = requestAnimationFrame(tick);
  };
  tick();
}
function hideInfo() { clearTimeout(infoTimer); cancelAnimationFrame(infoRaf); $('#osdInfo').classList.add('hidden'); }

let volTimer = 0;
function showVolume() {
  if (!S.tv.power || S.booting) return;
  const el = $('#osdVol');
  const v = Math.round((S.tv.volume || 0) * 100);
  el.classList.remove('hidden');
  el.classList.toggle('muted', !!S.tv.muted);
  $('#ovIcon').innerHTML = S.tv.muted || v === 0 ? I.mute : I.vol;
  const lit = Math.round(v / 5);
  $('#ovSeg').innerHTML = Array.from({ length: 20 }, (_, i) => `<i class="${i < lit ? 'on' : ''} ${i === lit - 1 ? 'tip' : ''}"></i>`).join('');
  $('#ovNum').textContent = S.tv.muted ? '—' : v;
  clearTimeout(volTimer);
  volTimer = setTimeout(() => el.classList.add('hidden'), 2200);
}

let chTimer = 0;
function showChannel() {
  const c = S.channels[(S.tv.channel || 1) - 1];
  if (!c) return;
  $('#ocNum').textContent = c.number || S.tv.channel;
  $('#ocName').textContent = c.name;
  $('#osdCh').classList.remove('hidden');
  clearTimeout(chTimer);
  chTimer = setTimeout(() => $('#osdCh').classList.add('hidden'), 3500);
}

let toastTimer = 0;
function osdToast(text) {
  const el = $('#osdToast');
  el.textContent = text;
  el.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add('hidden'), 4000);
}

/* ─────────────── ambient / clock / boot / power ─────────────── */
setInterval(() => {
  const m = S.tv && S.tv.media, el = document.querySelector('[data-np-prog]');
  if (el && m && m.duration) el.style.width = clamp(expectedPos(m) / m.duration, 0, 1) * 100 + '%';
}, 1000);

function tickClock() {
  const d = new Date();
  const hm = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  $('#tbClock').textContent = hm;
  $('#tbDate').textContent = d.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });
  $('#ambTime').textContent = hm;
  $('#ambDate').textContent = d.toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' });
}
setInterval(tickClock, 5000); tickClock();

function hideAmbient() { $('#ambient').classList.add('hidden'); }
setInterval(() => {
  if (!S.tv || !S.tv.power || S.tv.media || S.booting) return hideAmbient();
  const s = S.tv.settings || {};
  if (s.ambient !== false && Date.now() - S.lastInput > 300000) $('#ambient').classList.remove('hidden');
}, 5000);

// rotate featured hero
setInterval(() => {
  if (!S.tv || S.tv.media || S.featured.length < 2 || S.ui.page !== 'home' || S.ui.zone === 'hero') return;
  S.heroIdx++;
  render();
}, 12000);

function boot() {
  S.booting = true;
  stage.classList.remove('off', 'powering-off');
  stage.classList.add('powering-on');
  $('#bootWord').textContent = S.brand.name || 'NAYZEEE';
  $('#boot').classList.remove('hidden');
  render();
  setTimeout(() => stage.classList.remove('powering-on'), 700);
  setTimeout(() => {
    S.booting = false;
    $('#boot').classList.add('hidden');
    if (S.tv && S.tv.media) { S.ui.page = 'player'; showInfo(5000); }
    render();
  }, 2400);
}

function powerOff() {
  stage.classList.add('powering-off');
  hideInfo(); hideAmbient();
  setTimeout(() => {
    stage.classList.remove('powering-off');
    if (S.tv && S.tv.power) return; // switched back on during the animation
    stage.classList.add('off');
    destroyAdapter();
  }, 650);
}

function applySettings() {
  const s = (S.tv && S.tv.settings) || {};
  playerEl.className = 'player pic-' + (s.picture || 'standard') + ' fit-' + (s.fit || 'contain');
}

/* ─────────────── message handling ─────────────── */
const NULLABLE = { media: true, group: true, remoteHolder: true };

function applyTv(tv, booting) {
  S.tv = tv;
  if (!tv.queue) tv.queue = [];
  if (!tv.history) tv.history = [];
  if (tv.media === false) tv.media = null;
  stage.className = 'stage style-' + (tv.style || 'flat');
  if (tv.ui && typeof tv.ui === 'object' && tv.ui.page) S.ui = Object.assign(S.ui, tv.ui, { sources: false });
  if (tv.media && S.ui.page === 'home' && !tv.ui) S.ui.page = 'player';
  layout();
  applySettings();
  if (!tv.power) { stage.classList.add('off'); return; }
  if (booting) boot(); else render();
  mediaChanged(true);
}

function applyPatch(p) {
  const t = S.tv;
  if (!t) return;
  const prevPower = t.power;
  for (const k in p) t[k] = (p[k] === false && NULLABLE[k]) ? null : p[k];
  if ('power' in p && p.power !== prevPower) {
    if (p.power) { boot(); mediaChanged(true); } else powerOff();
  }
  if ('media' in p && t.power) mediaChanged(false);
  if (('volume' in p || 'muted' in p) && t.power) showVolume();
  if ('channel' in p && t.power) showChannel();
  if ('settings' in p) applySettings();
  if ('label' in p || 'history' in p || 'queue' in p || 'loop' in p || 'settings' in p) render();
}

function unload() {
  destroyAdapter();
  hideInfo(); hideAmbient();
  S.tv = null;
  stage.className = 'stage off';
  $('#os').classList.add('hidden');
}

window.addEventListener('message', (e) => {
  let d = e.data;
  if (typeof d === 'string') { try { d = JSON.parse(d); } catch (err) { return; } }
  if (!d || !d.type) return;
  switch (d.type) {
    case 'init':
      setClock(d.now);
      if (d.res) S.res = d.res;
      S.brand = d.brand || S.brand; S.featured = d.featured || []; S.channels = d.channels || []; S.library = d.library || [];
      if (d.sync) S.sync = d.sync;
      S.plex = !!d.plex; S.search = !!d.search;
      buildApps(); buildSources();
      S.query = ''; S.results = []; S.searchMsg = '';
      S.ui = { page: 'home', tab: 0, zone: 'tabs', idx: {}, railIdx: 3, prevZone: 'tabs', src: 'youtube', sources: false, list: 'library' };
      destroyAdapter();
      applyTv(d.tv, d.booting);
      break;
    case 'patch': setClock(d.now); applyPatch(d.patch || {}); break;
    case 'clock': setClock(d.now); syncCheck(); break;
    case 'audio':
      S.audio.volume = clamp(+d.volume || 0, 0, 1);
      S.audio.lowpass = +d.lowpass || 22000;
      S.audio.pan = clamp(+d.pan || 0, -1, 1);
      applyAudio();
      break;
    case 'key': onKey(d.key, d.mine); break;
    case 'typed': onTyped(d.text, d.mine); break;
    case 'osData': onOsData(d.data); break;
    case 'unload': unload(); break;
  }
});

// tell the client this browser is listening (it holds messages until then)
fetch(`https://${S.res}/tv:ready`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ slot: new URLSearchParams(location.search).get('slot') }) }).catch(() => {});

/* ─────────────── browser preview (?demo) ─────────────── */
if (/[?&]demo/.test(location.search)) {
  const now = 100000;
  window.postMessage({
    type: 'init', now, booting: false, res: 'nayzeee_tv',
    brand: { name: 'NAYZEEE', os: 'NAYZEEE OS', version: '1.0.0' },
    featured: [{ title: 'Friday Night Cinema', subtitle: 'Doors open 9pm at the Vinewood screen — bring the crew', url: null }],
    channels: [{ number: 1, name: 'City News', url: 'https://www.twitch.tv/citynews' }, { number: 2, name: 'Lo-fi Radio', url: 'https://www.youtube.com/watch?v=jfKfPfyJRdk' }],
    library: [{ file: 'intro.mp4', title: 'City Intro' }],
    tv: {
      id: 'demo', label: 'Living Room TV', style: /crt/.test(location.search) ? 'crt' : 'flat', aspect: /crt/.test(location.search) ? 4 / 3 : 16 / 9, power: true, volume: 0.6,
      settings: { picture: 'standard', fit: 'contain', ambient: true, osd: true }, media: false, queue: [], loop: false,
      history: [
        { url: 'https://www.youtube.com/watch?v=a', title: 'Midnight Drive — Synthwave Mix', kind: 'youtube', by: 'Maya Reyes' },
        { url: 'https://www.twitch.tv/x', title: 'Late Night Racing League', kind: 'twitch', by: 'Theo Kane' },
        { url: 'https://cdn.example.com/stream.m3u8', title: 'Vinewood Premiere Live', kind: 'hls', by: 'John Doe' },
        { url: 'local:intro.mp4', title: 'City Intro', kind: 'video', by: 'Server' },
      ],
      ui: null,
    },
  }, '*');
  const keys = (new URLSearchParams(location.search).get('keys') || '').split(',').filter(Boolean);
  setTimeout(() => keys.forEach((k) => onKey(k, false)), 100);
}
