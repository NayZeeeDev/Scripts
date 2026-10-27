/* ═══════════════════════════════════════════════════════════
   Speaker — phone app
   One speaker at a time is the "device" the app controls (like a Connect device). Everything
   comes from client/phone.lua: phoneState is polled while the app is in use, and the playback
   position runs locally between answers.
   ═══════════════════════════════════════════════════════════ */
(() => {
'use strict';

const RES = (/^cfx-nui-(.+)$/.exec(location.hostname) || [])[1] || 'nayzeee-speaker';
const QS = new URLSearchParams(location.search);
const $ = id => document.getElementById(id);
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clamp01 = v => (v > 0 ? (v < 1 ? v : 1) : 0);

/* ───────── strings (English built in; Locales.<lang>.phone overrides any of them) ───────── */
const T = {
  appName: 'Speaker', home: 'Home', search: 'Search', library: 'Library', jam: 'Jam',
  connecting: 'Connecting', noSpeaker: 'No speaker', refresh: 'Refresh', back: 'Back', unknown: 'Unknown song',
  playingOn: 'Playing on', speaker: 'Speaker', nowPlaying: 'Now playing', onDeck: 'On the deck', switchDev: 'Switch',
  nothingPlaying: 'Nothing playing', idleHint: 'Pick a song, a playlist or your liked songs.',
  idleRecord: 'Put a record on at the turntable to hear it here.',
  chooseSpeaker: 'Choose a speaker', chooseSub: 'Everything you play from the app goes to this speaker.',
  pickSub: 'Where should this play?',
  noDevices: 'No speakers in reach', noDevicesSub: 'Place a speaker, get in a car with CarPlay, or start a jam with friends.',
  inCar: 'In your car', jamDevice: 'Your jam', meters: '%s m away', here: 'Right here', yours: 'Yours', linked: '+%s linked',
  others: 'Other speakers', idle: 'Idle',
  qSearchSub: 'Find any song', qLikedSub: 'Your hearts', qQueue: 'Queue', qRecord: 'Record',
  queueEmpty: 'Nothing queued', queued: '%s queued', qJamSub: 'Listen together',
  upNext: 'Up next', onRecord: 'On the record', trackOf: 'Track %s of %s', repeatMode: 'Repeat', shuffle: 'Shuffle',
  searchPh: 'Songs or artists', searchHint: 'Find a song', searchHintSub: 'Type a song or an artist, then press enter.',
  noResults: 'Nothing found', noResultsSub: 'Try other words.',
  playsOn: 'Plays on %s', recordsOnly: '%s only plays records', recordsShort: 'Records only', recordsOnlyAll: 'Your speakers in reach only play records',
  noSpeakerShort: 'No speaker in reach to play on',
  liked: 'Liked Songs', playlist: 'Playlist', songs: '%s songs', song: '1 song', by: 'by %s',
  newPl: 'New playlist', newPlRow: 'Make a playlist', newPlSub: 'Give it a name, then add songs to it from any song menu.',
  plName: 'Playlist name', create: 'Create',
  yourPl: 'Your playlists', sharedPl: 'Shared in the city',
  kBlend: 'Blend', kCollab: 'Collaborative', kPrompted: 'Prompted', kMixed: 'Mixed', kShared: 'Shared',
  play: 'Play', playNow: 'Play now', addQueue: 'Add to queue', like: 'Add to Liked Songs', unlike: 'Remove from Liked Songs',
  addPl: 'Add to playlist', addPlSub: 'Pick one of your playlists.', noEditable: 'You have no playlists to add to yet.',
  empty: 'Nothing in here yet', emptySub: 'Heart a song to save it here.',
  noPl: 'No playlists yet', noPlSub: 'Create one, or heart songs to fill Liked Songs.',
  jamTitle: 'Listen together', jamSub: 'Everyone in a jam hears the same music in their own ears, anywhere in the city.',
  jamStart: 'Start a jam', jamName: 'Name your jam (optional)', jamLeave: 'Leave', jamControl: 'Play to jam',
  jamHost: 'Hosted by %s', jamPeople: '%s listening', jamOpen: 'Jams you can join', jamNone: 'No other jams right now.',
  join: 'Join', liveJam: 'Live jam', start: 'Start',
  cancel: 'Cancel', done: 'Done', sentTo: 'Sent to %s', addedQueue: 'Added to the queue', addedTo: 'Added to %s',
  offline: "Can't reach the speakers", offlineSub: 'Close the app and open it again.',
};
const t = (k, ...a) => {
  let s = T[k] != null ? String(T[k]) : k;
  for (const v of a) s = s.replace('%s', () => String(v));
  return s;
};
const countText = n => (n === 1 ? t('song') : t('songs', n || 0));

/* ───────── game bridge ───────── */
function post(name, data) {
  const ctl = typeof AbortController === 'function' ? new AbortController() : null;
  const timer = ctl ? setTimeout(() => ctl.abort(), 16000) : 0;
  return fetch(`https://${RES}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {}), signal: ctl ? ctl.signal : undefined,
  }).then(r => (r.ok ? r.json() : null)).catch(() => null).finally(() => clearTimeout(timer));
}
// A Lua list arrives as a JSON array; an empty one can arrive as {}. Anything else is not a list.
const asList = v => (Array.isArray(v) ? v : v && typeof v === 'object' && !Object.keys(v).length ? [] : null);

const store = {
  get(k) { try { return localStorage.getItem('nzspk.phone.' + k); } catch (_) { return null; } },
  set(k, v) {
    try { if (v == null) localStorage.removeItem('nzspk.phone.' + k); else localStorage.setItem('nzspk.phone.' + k, v); } catch (_) { /* storage off */ }
  },
};

/* ───────── state ───────── */
const S = {
  tab: 'home', name: T.appName, features: { search: true, playlists: true, jam: true },
  devices: [], byId: new Map(), active: null, want: store.get('device'),
  clock: { server: 0, perf: 0 }, loaded: false, fails: 0, offline: false,
  hold: new Map(), drag: null,
  favs: [], favKeys: new Set(), lib: null, openPl: null,
  query: '', results: null, searching: false,
  jams: null, jam: null,
  np: false, sheet: null, scrollPos: {}, lastTouch: performance.now(),
};

const serverNow = () => S.clock.server + (performance.now() - S.clock.perf);
function posOf(d) {
  if (!d || !d.track) return 0;
  const dur = d.track.duration || 0;
  let p = d.playing ? (serverNow() - (d.startedAt || 0)) / 1000 : d.pos || 0;
  if (!(p > 0)) p = 0;
  return dur > 0 && p > dur ? dur : p;
}
const fmt = s => {
  s = Math.max(0, Math.floor(s || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = String(s % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${x}` : `${m}:${x}`;
};

/* ───────── tracks ───────── */
const keyOf = tr => (tr ? `${tr.src || 'yt'}:${tr.id || tr.url || ''}` : '');
const canHeart = tr => !!tr && !tr.record && !!(tr.id || tr.url);
const isFav = tr => canHeart(tr) && S.favKeys.has(keyOf(tr));
function setFavs(list) { S.favs = list; S.favKeys = new Set(list.map(keyOf)); }
const saved = tr => ({
  src: tr.src || 'yt', id: tr.id, url: tr.url, search: tr.search,
  title: tr.title, author: tr.author, duration: tr.duration || 0, thumb: tr.thumb,
});
// the speaker's song, or the record sitting on a turntable that isn't playing one
function nowTrack(d) {
  if (!d) return null;
  if (d.track) return d.track;
  if (d.record) return { title: d.record.album, author: d.record.artist, thumb: d.record.cover, duration: 0, record: true };
  return null;
}

/* ───────── markup helpers ───────── */
function cover(u, big) {
  if (!u || typeof u !== 'string') return null;
  const m = /^https?:\/\/i\d?\.ytimg\.com\/vi(?:_webp)?\/([\w-]{6,})\//.exec(u);
  // YouTube: hq (4:3 with bars, zoomed past them) for big art, mq (16:9, no bars) for small
  if (m) return big ? { src: `https://i.ytimg.com/vi/${m[1]}/hqdefault.jpg`, cls: 'yt' } : { src: `https://i.ytimg.com/vi/${m[1]}/mqdefault.jpg`, cls: '' };
  if (!/^(https?:|nui:|\.\.\/|data:image\/)/.test(u)) return null;
  return { src: u, cls: '' };
}
const img = (c, lazy) => (c ? `<img class="${c.cls}" src="${esc(c.src)}" alt=""${lazy ? ' loading="lazy"' : ''} decoding="async" onerror="this.remove()">` : '');
const art = (u, o = {}) => `<span class="art ${o.cls || ''}"><i class="fa-solid ${o.icon || 'fa-music'}"></i>${img(cover(u, o.big), o.lazy)}</span>`;
const ambient = u => img(cover(u, false));
const eq = on => `<span class="eq ${on ? 'on' : ''}"><i></i><i></i><i></i></span>`;
const sec = (title, count) => `<div class="sec"><h2>${esc(title)}</h2>${count !== '' && count != null ? `<span class="count">${esc(count)}</span>` : ''}</div>`;
const emptyBox = (icon, title, sub, extra = '') =>
  `<div class="empty"><span class="ei"><i class="fa-solid ${icon}"></i></span><b>${esc(title)}</b>${sub ? `<span>${esc(sub)}</span>` : ''}${extra}</div>`;

const ICONS = { car: 'fa-car', jam: 'fa-user-group', vinyl: 'fa-record-vinyl', speaker: 'fa-radio' };
const devIcon = d => ICONS[d && d.icon] || 'fa-radio';
function devWhere(d) {
  const bits = [];
  if (d.kind === 'vehicle') bits.push(t('inCar'));
  else if (d.kind === 'jam') bits.push(t('jamDevice'));
  else bits.push(d.d > 1 ? t('meters', d.d) : t('here'));
  if (d.mine && d.kind === 'boombox') bits.push(t('yours'));
  if (d.linked) bits.push(t('linked', d.linked));
  return bits.join(' · ');
}
const active = () => S.byId.get(S.active) || null;

/* ───────── sliders: seek + volume ───────── */
const slider = (kind, d, off) => `<div class="sl${off ? ' off' : ''}" data-sl="${kind}" data-live="${kind}" data-dev="${esc(d.id)}"><div class="sl-t"><div class="sl-f"></div><div class="sl-k"></div></div></div>`;
const canSeek = d => !!(d && d.track && d.track.duration > 0);
const seekBar = d => `<div class="seek">${slider('seek', d, !canSeek(d))}<div class="times"><span data-live="pos" data-dev="${esc(d.id)}">0:00</span><span data-live="dur" data-dev="${esc(d.id)}">-:--</span></div></div>`;
const volBar = d => `<div class="vol"><i class="fa-solid fa-volume-low"></i>${slider('vol', d)}<i class="fa-solid fa-volume-high"></i></div>`;

function transport(d) {
  const id = esc(d.id), tr = nowTrack(d), on = d.playing && !!d.track, deck = d.turntable;
  return `<div class="transport">
    <button class="ib mode${d.shuffle && !deck ? ' on' : ''}" data-a="act" data-w="shuffle" data-dev="${id}" aria-label="${esc(t('shuffle'))}"${deck ? ' disabled' : ''}><i class="fa-solid fa-shuffle"></i></button>
    <button class="ib step" data-a="act" data-w="prev" data-dev="${id}" aria-label="Previous"${d.track ? '' : ' disabled'}><i class="fa-solid fa-backward-step"></i></button>
    <button class="ib play" data-a="toggle" data-dev="${id}" aria-label="${on ? 'Pause' : 'Play'}"${tr ? '' : ' disabled'}><i class="fa-solid fa-${on ? 'pause' : 'play'}"></i></button>
    <button class="ib step" data-a="act" data-w="next" data-dev="${id}" aria-label="Next"${d.track ? '' : ' disabled'}><i class="fa-solid fa-forward-step"></i></button>
    <button class="ib mode${d.loop && !deck ? ' on' : ''}" data-a="act" data-w="loop" data-dev="${id}" aria-label="${esc(t('repeatMode'))}"${deck ? ' disabled' : ''}><i class="fa-solid fa-repeat"></i></button>
  </div>`;
}

/* ═══════════════ VIEWS ═══════════════ */
function homeView() {
  if (S.offline) return emptyBox('fa-plug-circle-xmark', t('offline'), t('offlineSub'),
    `<div class="pills"><button class="pill line" data-a="refresh"><i class="fa-solid fa-rotate"></i>${esc(t('refresh'))}</button></div>`);
  if (!S.loaded) return '<div class="skel" style="height:320px"></div>';
  if (!S.devices.length) {
    return emptyBox('fa-tower-broadcast', t('noDevices'), t('noDevicesSub'), `<div class="pills">
      ${S.features.jam ? `<button class="pill teal" data-a="tab" data-v="jam"><i class="fa-solid fa-user-group"></i>${esc(t('jamStart'))}</button>` : ''}
      <button class="pill line" data-a="refresh"><i class="fa-solid fa-rotate"></i>${esc(t('refresh'))}</button></div>`);
  }
  const d = active();
  const others = S.devices.filter(x => x !== d);
  return heroCard(d) + quickActions(d) +
    (others.length ? sec(t('others'), others.length) + `<div class="list">${others.map(otherRow).join('')}</div>` : '');
}

function heroCard(d) {
  const tr = nowTrack(d), live = d.playing && !!d.track;
  const head = `<button class="hero-dev" data-a="devices" aria-label="${esc(t('chooseSpeaker'))}">
      <span class="ico${live ? ' on' : ''}"><i class="fa-solid ${devIcon(d)}"></i></span>
      <span class="who"><span class="micro${live ? ' teal' : ''}">${esc(t(live ? 'playingOn' : 'speaker'))}</span><b>${esc(d.label)}</b><small>${esc(devWhere(d))}</small></span>
      <i class="fa-solid fa-chevron-right"></i>
    </button>`;
  let body;
  if (!tr) {
    body = `<div class="idle">${art('', { icon: devIcon(d) })}<b>${esc(t('nothingPlaying'))}</b>
      <span>${esc(t(d.turntable ? 'idleRecord' : 'idleHint'))}</span>
      ${d.turntable ? '' : `<div class="pills">
        ${S.features.search ? `<button class="pill teal" data-a="quick" data-v="search"><i class="fa-solid fa-magnifying-glass"></i>${esc(t('search'))}</button>` : ''}
        <button class="pill line" data-a="playList" data-pl="liked"${S.favs.length ? '' : ' disabled'}><i class="fa-solid fa-heart"></i>${esc(t('liked'))}</button></div>`}
      </div>${volBar(d)}`;
  } else {
    const chips = [];
    if (d.record) chips.push(`<span class="chip teal"><i class="fa-solid fa-record-vinyl"></i>${esc(t('trackOf', d.record.idx, d.record.count))}</span>`);
    else if (d.queued) chips.push(`<span class="chip">${esc(t('queued', d.queued))}</span>`);
    if (d.loop && !d.turntable) chips.push(`<span class="chip teal"><i class="fa-solid fa-repeat"></i>${esc(t('repeatMode'))}</span>`);
    if (d.shuffle && !d.turntable) chips.push(`<span class="chip teal"><i class="fa-solid fa-shuffle"></i>${esc(t('shuffle'))}</span>`);
    body = `<div class="hero-main" data-a="openNp">${art(tr.thumb, { big: true, icon: tr.record ? 'fa-record-vinyl' : 'fa-music' })}
        <div class="hero-info"><span class="micro">${esc(t(tr.record ? 'onDeck' : 'nowPlaying'))}</span>
          <div class="hero-title">${esc(tr.title || t('unknown'))}</div>
          <div class="hero-artist ell">${esc(tr.author || '')}</div>
          ${chips.length ? `<div class="chips">${chips.join('')}</div>` : ''}</div></div>
      ${seekBar(d)}${transport(d)}${volBar(d)}`;
  }
  return `<div class="hero-frame"><div class="hero"><div class="ambient">${tr ? ambient(tr.thumb) : ''}</div>${head}${body}</div></div>`;
}

function quickActions(d) {
  const qa = (v, icon, cls, title, sub) => `<button class="qa" data-a="quick" data-v="${v}"><span class="qi ${cls}"><i class="fa-solid ${icon}"></i></span>
    <span class="qt"><b>${esc(title)}</b><small>${esc(sub)}</small></span></button>`;
  const tiles = [];
  if (S.features.search) tiles.push(qa('search', 'fa-magnifying-glass', '', t('search'), t(d.turntable ? 'recordsShort' : 'qSearchSub')));
  tiles.push(qa('liked', 'fa-heart', 'liked', t('liked'), S.lib ? countText(S.favs.length) : t('qLikedSub')));
  tiles.push(d.turntable
    ? qa('queue', 'fa-record-vinyl', 'teal', t('qRecord'), d.record ? t('trackOf', d.record.idx, d.record.count) : t('nothingPlaying'))
    : qa('queue', 'fa-list-ul', 'teal', t('qQueue'), d.queued ? t('queued', d.queued) : t('queueEmpty')));
  if (S.features.jam) tiles.push(qa('jam', 'fa-user-group', '', t('jam'), S.jam ? S.jam.name : t('qJamSub')));
  return `<div class="quick">${tiles.join('')}</div>`;
}

function otherRow(d) {
  const tr = nowTrack(d), live = d.playing && !!d.track;
  const sub = tr ? `${live ? eq(true) : ''}${esc(tr.title || '')} · ${esc(devWhere(d))}` : `${esc(t('idle'))} · ${esc(devWhere(d))}`;
  return `<div class="row" data-a="pickDev" data-dev="${esc(d.id)}">
    ${tr ? art(tr.thumb, { icon: devIcon(d), lazy: true }) : art('', { icon: devIcon(d) })}
    <div class="rt"><b>${esc(d.label)}</b><span>${sub}</span></div>
    <div class="acts">${tr ? `<button class="ib" data-a="toggle" data-dev="${esc(d.id)}" aria-label="${live ? 'Pause' : 'Play'}"><i class="fa-solid fa-${live ? 'pause' : 'play'}"></i></button>` : ''}</div>
  </div>`;
}

function trackRow(tr, i, from, o = {}) {
  const fav = isFav(tr);
  const sub = [tr.author, tr.duration ? fmt(tr.duration) : ''].filter(Boolean).map(esc).join(' · ');
  return `<div class="row${o.now ? ' now' : ''}" data-a="play" data-from="${from}" data-i="${i}">
    ${o.num ? `<span class="num">${o.now ? eq(o.live) : i + 1}</span>` : ''}${art(tr.thumb, { lazy: true })}
    <div class="rt"><b>${esc(tr.title || t('unknown'))}</b><span>${sub || '&nbsp;'}</span></div>
    <div class="acts">
      ${canHeart(tr) ? `<button class="ib sm${fav ? ' liked' : ''}" data-a="heart" data-from="${from}" data-i="${i}" aria-label="${esc(t(fav ? 'unlike' : 'like'))}"><i class="fa-${fav ? 'solid' : 'regular'} fa-heart"></i></button>` : ''}
      <button class="ib sm" data-a="more" data-from="${from}" data-i="${i}" aria-label="More"><i class="fa-solid fa-ellipsis"></i></button>
    </div></div>`;
}

function searchTarget() {
  const d = active();
  if (!S.loaded) return '';
  if (!d) return `<div class="target warn"><i class="fa-solid fa-circle-info"></i><span class="ell">${esc(t('noSpeakerShort'))}</span></div>`;
  return `<div class="target${d.turntable ? ' warn' : ''}"><i class="fa-solid ${devIcon(d)}"></i>
    <span class="ell">${esc(t(d.turntable ? 'recordsOnly' : 'playsOn', d.label))}</span>
    <button data-a="devices">${esc(t('switchDev'))}</button></div>`;
}

function searchBody() {
  if (S.searching) return '<div class="spin"></div>';
  if (S.results === null) return emptyBox('fa-music', t('searchHint'), t('searchHintSub'));
  if (!S.results.length) return emptyBox('fa-magnifying-glass', t('noResults'), t('noResultsSub'));
  return `<div class="list">${S.results.map((r, i) => trackRow(r, i, 'res')).join('')}</div>`;
}

const KIND_ICON = { blend: 'fa-code-merge', collab: 'fa-user-group', prompted: 'fa-wand-magic-sparkles' };
function kindLabel(p) {
  const k = { blend: 'kBlend', collab: 'kCollab', prompted: 'kPrompted' }[p.kind];
  if (k) return t(k);
  if (p.mixed) return t('kMixed');
  return p.shared ? t('kShared') : t('playlist');
}
const plMeta = p => [kindLabel(p), countText(p.count), p.mine ? '' : t('by', p.owner || '?')].filter(Boolean).join(' · ');
function plArt(p, big) {
  const thumbs = [...new Set((asList(p.tracks) || []).map(x => x && x.thumb).filter(Boolean))].slice(0, 4);
  if (thumbs.length >= 4) return `<span class="art mosaic">${thumbs.map(u => `<span>${img(cover(u, false), true)}</span>`).join('')}</span>`;
  return art(thumbs[0], { icon: KIND_ICON[p.kind] || 'fa-list', big, lazy: !big });
}
const plRow = p => `<div class="row" data-a="openPl" data-pl="${esc(p.id)}">${plArt(p)}
  <div class="rt"><b>${esc(p.name)}</b><span>${esc(plMeta(p))}</span></div>
  <div class="acts">${p.count ? `<button class="ib teal sm" data-a="playList" data-pl="${esc(p.id)}" aria-label="${esc(t('play'))}"><i class="fa-solid fa-play"></i></button>` : ''}</div></div>`;

function allPlaylists() {
  const lib = S.lib || { mine: [], shared: [] };
  const mine = lib.mine, ids = new Set(mine.map(p => p.id));
  return { mine, shared: lib.shared.filter(p => !p.mine && !ids.has(p.id)) };
}
function openList() {
  if (S.openPl === 'liked') return { key: 'liked', liked: true, name: t('liked'), tracks: S.favs, count: S.favs.length };
  const { mine, shared } = allPlaylists();
  const p = mine.concat(shared).find(x => x.id === S.openPl);
  return p ? Object.assign({ key: p.id, tracks: asList(p.tracks) || [] }, p) : null;
}

function libraryView() {
  if (S.lib === null) return '<div class="spin"></div>';
  if (S.openPl != null) {
    const v = playlistView();
    if (v) return v;
    S.openPl = null;
  }
  const { mine, shared } = allPlaylists();
  let h = `<div class="list">
    <div class="row" data-a="openPl" data-pl="liked">${art('', { cls: 'liked', icon: 'fa-heart' })}
      <div class="rt"><b>${esc(t('liked'))}</b><span>${esc(t('playlist'))} · ${esc(countText(S.favs.length))}</span></div>
      <div class="acts">${S.favs.length ? `<button class="ib teal sm" data-a="playList" data-pl="liked" aria-label="${esc(t('play'))}"><i class="fa-solid fa-play"></i></button>` : ''}</div></div>
    ${S.features.playlists ? `<div class="row" data-a="newPl">${art('', { cls: 'add', icon: 'fa-plus' })}
      <div class="rt"><b>${esc(t('newPl'))}</b><span>${esc(t('newPlRow'))}</span></div></div>` : ''}
  </div>`;
  if (mine.length) h += sec(t('yourPl'), mine.length) + `<div class="list">${mine.map(plRow).join('')}</div>`;
  if (shared.length) h += sec(t('sharedPl'), shared.length) + `<div class="list">${shared.map(plRow).join('')}</div>`;
  if (!mine.length && !shared.length && S.features.playlists) h += emptyBox('fa-list', t('noPl'), t('noPlSub'));
  return h;
}

function playlistView() {
  const p = openList();
  if (!p) return '';
  const d = active(), cur = d && d.track ? keyOf(d.track) : '', live = !!(d && d.playing);
  const has = p.tracks.length > 0;
  const meta = [countText(p.count), p.liked || p.mine ? '' : t('by', p.owner || '?')].filter(Boolean).join(' · ');
  return `<button class="back" data-a="backLib"><i class="fa-solid fa-chevron-left"></i>${esc(t('back'))}</button>
    <div class="pl-head">${p.liked ? art('', { cls: 'liked', icon: 'fa-heart', big: true }) : plArt(p, true)}
      <div class="pt"><span class="micro">${esc(p.liked ? t('playlist') : kindLabel(p))}</span><h3>${esc(p.name)}</h3><p>${esc(meta)}</p></div></div>
    <div class="pl-btns">
      <button class="pill teal" data-a="playList" data-pl="${esc(p.key)}"${has ? '' : ' disabled'}><i class="fa-solid fa-play"></i>${esc(t('play'))}</button>
      <button class="pill line" data-a="playList" data-pl="${esc(p.key)}" data-shuffle="1"${has ? '' : ' disabled'}><i class="fa-solid fa-shuffle"></i>${esc(t('shuffle'))}</button>
    </div>
    ${has ? `<div class="list">${p.tracks.map((tr, i) => trackRow(tr, i, 'pl', { num: true, now: !!cur && keyOf(tr) === cur, live })).join('')}</div>`
      : emptyBox('fa-music', t('empty'), t('emptySub'))}`;
}

function jamView() {
  if (S.jams === null) return '<div class="spin"></div>';
  const j = S.jam;
  let h;
  if (j) {
    const members = asList(j.members) || [];
    h = `<div class="jam-hero live"><div class="jam-rings"></div>
      <span class="micro teal live-dot">${esc(t('liveJam'))}</span><h3>${esc(j.name)}</h3>
      <p>${esc(t('jamHost', j.host || '?'))} · ${esc(t('jamPeople', j.count || members.length))}</p>
      <div class="members">${members.map(m => `<span class="member${m.host ? ' host' : ''}"><span class="av">${esc(initials(m.name))}</span><span class="ell">${esc(m.name)}</span></span>`).join('')}</div>
      <div class="pills"><button class="pill teal" data-a="jamControl"><i class="fa-solid fa-sliders"></i>${esc(t('jamControl'))}</button>
        <button class="pill red" data-a="jamLeave"><i class="fa-solid fa-right-from-bracket"></i>${esc(t('jamLeave'))}</button></div></div>`;
  } else {
    h = `<div class="jam-hero"><div class="jam-rings"></div><span class="micro teal">${esc(t('jam'))}</span>
      <h3>${esc(t('jamTitle'))}</h3><p>${esc(t('jamSub'))}</p>
      <div class="pills"><button class="pill teal" data-a="jamStart"><i class="fa-solid fa-plus"></i>${esc(t('jamStart'))}</button></div></div>`;
  }
  const others = (S.jams || []).filter(x => x && !x.mine);
  h += sec(t('jamOpen'), others.length || '');
  h += others.length
    ? `<div class="list">${others.map(x => `<div class="row" data-a="jamJoin" data-id="${esc(x.id)}">
        <span class="art"><i class="fa-solid fa-user-group"></i></span>
        <div class="rt"><b>${esc(x.name)}</b><span>${esc(x.host || '')} · ${esc(t('jamPeople', x.count || 0))}</span></div>
        <div class="acts"><button class="pill sm line" data-a="jamJoin" data-id="${esc(x.id)}">${esc(t('join'))}</button></div></div>`).join('')}</div>`
    : `<div class="empty" style="padding:22px 12px"><span>${esc(t('jamNone'))}</span></div>`;
  return h;
}
const initials = n => String(n || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase() || '?';

/* ───────── mini player, now playing, queue ───────── */
function miniHTML() {
  const d = active(), tr = nowTrack(d);
  if (!d || !tr) return '';
  const live = d.playing && !!d.track;
  return `<div class="ambient">${ambient(tr.thumb)}</div>${art(tr.thumb, { icon: tr.record ? 'fa-record-vinyl' : 'fa-music' })}
    <div class="mt"><b>${esc(tr.title || t('unknown'))}</b><span><i class="fa-solid ${devIcon(d)}"></i><em>${esc(d.label)}</em></span></div>
    <button class="ib" data-a="devices" aria-label="${esc(t('chooseSpeaker'))}"><i class="fa-solid fa-tower-broadcast"></i></button>
    <button class="ib" data-a="toggle" data-dev="${esc(d.id)}" aria-label="${live ? 'Pause' : 'Play'}"><i class="fa-solid fa-${live ? 'pause' : 'play'}"></i></button>
    <div class="mini-bar" data-live="bar" data-dev="${esc(d.id)}"><i></i></div>`;
}

function queueHTML(d) {
  const id = esc(d.id);
  if (d.record) {
    const list = asList(d.record.tracks) || [];
    return sec(t('onRecord'), t('trackOf', d.record.idx, d.record.count)) + list.map((title, i) => {
      const now = i + 1 === d.record.idx;
      return `<div class="row${now ? ' now' : ''}" data-a="qPlay" data-dev="${id}" data-i="${i + 1}">
        <span class="num">${now ? eq(d.playing) : i + 1}</span>
        <div class="rt"><b>${esc(title)}</b><span>${esc(d.record.artist || '')}</span></div></div>`;
    }).join('');
  }
  const q = asList(d.queue) || [];
  return sec(t('upNext'), q.length || '') + (q.length
    ? q.map((tr, i) => `<div class="row" data-a="qPlay" data-dev="${id}" data-i="${i + 1}">${art(tr.thumb, { lazy: true })}
        <div class="rt"><b>${esc(tr.title || t('unknown'))}</b><span>${esc(tr.author || '')}</span></div>
        <div class="acts"><button class="ib sm" data-a="qRemove" data-dev="${id}" data-i="${i + 1}" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button></div></div>`).join('')
    : `<div class="empty"><span>${esc(t('queueEmpty'))}</span></div>`);
}

const npHead = d => `<button class="ib" data-a="closeNp" aria-label="Close"><i class="fa-solid fa-chevron-down"></i></button>
  <button class="np-dev" data-a="devices"><span class="micro">${esc(t('playingOn'))}</span><b>${esc(d.label)}</b></button>
  <button class="ib" data-a="npQueue" aria-label="${esc(t('upNext'))}"><i class="fa-solid fa-list-ul"></i></button>`;

function npHTML() {
  const d = active();
  if (!d) return '';
  const tr = nowTrack(d), fav = isFav(d.track);
  return `<div class="np-art">${art(tr && tr.thumb, { big: true, icon: tr ? (tr.record ? 'fa-record-vinyl' : 'fa-music') : devIcon(d) })}</div>
    <div class="np-meta"><div class="mt"><b>${esc(tr ? tr.title || t('unknown') : t('nothingPlaying'))}</b>
      <span>${esc(tr ? tr.author || '' : t(d.turntable ? 'idleRecord' : 'idleHint'))}</span></div>
      ${canHeart(d.track) ? `<button class="ib${fav ? ' liked' : ''}" data-a="heartNow" data-dev="${esc(d.id)}" aria-label="${esc(t(fav ? 'unlike' : 'like'))}"><i class="fa-${fav ? 'solid' : 'regular'} fa-heart"></i></button>
      <button class="ib" data-a="moreNow" data-dev="${esc(d.id)}" aria-label="More"><i class="fa-solid fa-ellipsis"></i></button>` : ''}</div>
    ${seekBar(d)}${transport(d)}${volBar(d)}
    <button class="np-dev-row" data-a="devices"><i class="fa-solid ${devIcon(d)}"></i><span class="ell">${esc(d.label)} · ${esc(devWhere(d))}</span><i class="fa-solid fa-chevron-right"></i></button>
    <div class="np-q" id="npQueue">${queueHTML(d)}</div>`;
}

/* ───────── sheets ───────── */
function devicesSheet(sh) {
  const rows = S.devices.map(d => {
    const tr = nowTrack(d), cur = d.id === S.active, live = d.playing && !!d.track, off = sh.pick && d.turntable;
    return `<button class="dev${cur ? ' cur' : ''}${live ? ' playing' : ''}${off ? ' off' : ''}" data-a="pickDev" data-dev="${esc(d.id)}"${off ? ' disabled' : ''}>
      <span class="di"><i class="fa-solid ${devIcon(d)}"></i></span>
      <span class="dt"><b>${esc(d.label)}</b><span>${esc(devWhere(d))}${tr ? ` · <em>${esc(tr.title || '')}</em>` : ''}</span></span>
      <span class="tick">${cur ? '<i class="fa-solid fa-check"></i>' : live ? eq(true) : ''}</span></button>`;
  }).join('');
  return `<div class="grab"></div>
    <div class="sheet-head"><div class="st"><h3>${esc(t('chooseSpeaker'))}</h3><p>${esc(t(sh.pick ? 'pickSub' : 'chooseSub'))}</p></div>
      <button class="ib" data-a="refresh" aria-label="${esc(t('refresh'))}"><i class="fa-solid fa-rotate"></i></button></div>
    <div class="sheet-body">${rows || emptyBox('fa-tower-broadcast', t('noDevices'), t('noDevicesSub'))}</div>`;
}

function trackSheet(sh) {
  const tr = sh.track, fav = isFav(tr);
  const opt = (a, icon, label, extra = '') => `<button class="dev" data-a="${a}"${extra}><span class="di"><i class="fa-${icon}"></i></span><span class="dt"><b>${esc(label)}</b></span></button>`;
  let body;
  if (sh.step === 'playlists') {
    const mine = (S.lib ? S.lib.mine : []).filter(p => p.canEdit !== false);
    body = mine.length ? mine.map(p => `<button class="dev" data-a="plAdd" data-pl="${esc(p.id)}">${plArt(p)}
        <span class="dt"><b>${esc(p.name)}</b><span>${esc(countText(p.count))}</span></span></button>`).join('')
      : emptyBox('fa-list', t('noPl'), t('noEditable'));
  } else {
    body = (sh.noPlay ? '' : opt('sPlay', 'solid fa-play', t('playNow')) + opt('sQueue', 'solid fa-list-ul', t('addQueue')))
      + (canHeart(tr) ? opt('sHeart', `${fav ? 'solid' : 'regular'} fa-heart`, t(fav ? 'unlike' : 'like')) : '')
      + (S.features.playlists && canHeart(tr) ? opt('sPlaylists', 'solid fa-circle-plus', t('addPl')) : '');
  }
  return `<div class="grab"></div>
    <div class="sheet-head">${art(tr.thumb, { cls: 'sheet-art' })}<div class="st"><h3 class="ell">${esc(sh.step === 'playlists' ? t('addPl') : tr.title || t('unknown'))}</h3>
      <p class="ell">${esc(sh.step === 'playlists' ? tr.title || '' : tr.author || '')}</p></div></div>
    <div class="sheet-body">${body}</div>`;
}

function openSheet(kind, opts = {}) {
  if (S.sheet) closeSheet(null, true);
  S.sheet = Object.assign({ kind }, opts);
  const el = $('sheet');
  el.hidden = false;
  renderSheet(true);
  requestAnimationFrame(() => requestAnimationFrame(() => { if (S.sheet && S.sheet.kind === kind) el.classList.add('open'); }));
}
function closeSheet(result, instant) {
  const sh = S.sheet;
  if (!sh) return;
  S.sheet = null;
  const el = $('sheet');
  el.classList.remove('open');
  const done = () => { if (!S.sheet) { el.hidden = true; put($('sheetCard'), ''); } };
  if (instant) done(); else setTimeout(done, 300);
  if (sh.resolve) sh.resolve(result === undefined ? null : result);
}
function renderSheet(force) {
  const sh = S.sheet;
  if (!sh) return;
  if (sh.kind === 'devices') put($('sheetCard'), devicesSheet(sh));
  else if (sh.kind === 'track' && force) put($('sheetCard'), trackSheet(sh));
}

// a bottom sheet with one text field; resolves the text, '' (allowEmpty) or null (cancelled)
function ask({ title, sub, placeholder, ok, allowEmpty }) {
  return new Promise(resolve => {
    openSheet('ask', { resolve });
    put($('sheetCard'), `<div class="grab"></div>
      <div class="sheet-head"><div class="st"><h3>${esc(title)}</h3>${sub ? `<p>${esc(sub)}</p>` : ''}</div></div>
      <form class="sheet-body" id="askForm" autocomplete="off">
        <input class="sheet-input" id="askIn" maxlength="40" placeholder="${esc(placeholder || '')}" spellcheck="false">
        <div class="pills"><button type="button" class="pill line" data-a="closeSheet">${esc(t('cancel'))}</button>
          <button type="submit" class="pill teal">${esc(ok || t('done'))}</button></div></form>`);
    $('askForm').addEventListener('submit', e => {
      e.preventDefault();
      const v = ($('askIn').value || '').trim();
      if (v || allowEmpty) closeSheet(v);
    });
    setTimeout(() => { const i = $('askIn'); if (i) i.focus(); }, 320);
  });
}

function toast(msg) {
  const el = $('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(S.toastT);
  S.toastT = setTimeout(() => el.classList.remove('show'), 1900);
}

/* ═══════════════ RENDER ═══════════════ */
// Replace a region's markup only when it changed. Covers that are already loaded are moved into the
// new markup instead of being created again, so a re-render never flashes the artwork.
function put(el, html) {
  if (!el || el._h === html) return;
  el._h = html;
  const loaded = new Map();
  el.querySelectorAll('img').forEach(i => {
    if (!i.complete || !i.naturalWidth) return;
    const k = i.getAttribute('src');
    if (!loaded.has(k)) loaded.set(k, []);
    loaded.get(k).push(i);
  });
  el.innerHTML = html;
  if (!loaded.size) return;
  el.querySelectorAll('img').forEach(i => {
    const keep = (loaded.get(i.getAttribute('src')) || []).shift();
    if (keep) { keep.className = i.className; i.replaceWith(keep); }
  });
}

function render() {
  if (S.drag) { S.dirty = true; return tick(); }   // never swap a slider out from under the pointer
  S.dirty = false;
  const d = active(), live = !!(d && d.playing && d.track);
  $('title').textContent = S.tab === 'home' ? S.name : t(S.tab);
  put($('devPill'), `<span class="dot-ico"><i class="fa-solid ${d ? devIcon(d) : 'fa-tower-broadcast'}"></i></span>
    <b>${esc(d ? d.label : t(S.loaded ? 'noSpeaker' : 'connecting'))}</b><i class="fa-solid fa-chevron-down chev"></i>`);
  $('devPill').classList.toggle('on', live);

  if (S.tab === 'home') put($('v-home'), homeView());
  else if (S.tab === 'search') { put($('searchTarget'), searchTarget()); put($('searchBody'), searchBody()); }
  else if (S.tab === 'library') put($('v-library'), libraryView());
  else if (S.tab === 'jam') put($('v-jam'), jamView());

  const mini = $('mini');
  put(mini, miniHTML());
  mini.hidden = !mini._h;
  $('app').classList.toggle('has-mini', !mini.hidden);

  if (S.np) {
    if (!d) closeNp();
    else {
      put($('npHead'), npHead(d));
      put($('npBody'), npHTML());
      const tr = nowTrack(d);
      put($('npAmbient'), tr ? ambient(tr.thumb) : '');
    }
  }
  renderSheet(false);
  tick();
}

// progress, times and volume, written in place (no re-render) a few times a second
function tick() {
  const els = document.querySelectorAll('[data-live]');
  for (let i = 0; i < els.length; i++) {
    const el = els[i], d = S.byId.get(el.dataset.dev);
    if (!d) continue;
    const kind = el.dataset.live, dragging = S.drag && S.drag.id === d.id && S.drag.kind === kind;
    if (kind === 'vol') { if (!dragging) setV(el, clamp01(d.volume)); continue; }
    const dur = d.track ? d.track.duration || 0 : 0;
    const p = S.drag && S.drag.id === d.id && S.drag.kind === 'seek' ? S.drag.v * dur : posOf(d);
    if (kind === 'seek' || kind === 'bar') { if (!dragging) setV(el, dur > 0 ? p / dur : 0); }
    else if (kind === 'pos') setText(el, fmt(p));
    else if (kind === 'dur') setText(el, dur > 0 ? fmt(dur) : '-:--');
  }
}
function setV(el, v) {
  const s = v.toFixed(4);
  if (el._v !== s) { el._v = s; el.style.setProperty('--v', s); }
}
function setText(el, s) { if (el.textContent !== s) el.textContent = s; }

/* ═══════════════ DATA ═══════════════ */
let pollT = 0, polling = false;
function schedule(ms) {
  clearTimeout(pollT);
  if (ms == null) {
    const idle = performance.now() - S.lastTouch;
    ms = document.hidden ? 5000 : idle > 300000 ? 10000 : idle > 30000 ? 4000 : 1000;
  }
  pollT = setTimeout(() => poll(false), ms);
}
const soon = (ms = 350) => schedule(ms);

async function poll(fresh) {
  if (polling) return schedule(150);
  clearTimeout(pollT);
  polling = true;
  const data = await post('phoneState', { active: S.active || S.want, fresh: !!fresh });
  polling = false;
  if (data && typeof data === 'object') {
    S.fails = 0;
    apply(data);
  } else if (++S.fails >= 3 && !S.loaded) {
    S.offline = true;
    render();
  }
  schedule();
}

function apply(data) {
  S.clock = { server: +data.now || 0, perf: performance.now() };
  const now = performance.now(), list = [], byId = new Map();
  for (const d of asList(data.devices) || []) {
    if (!d || typeof d.id !== 'string') continue;
    const h = S.hold.get(d.id);
    if (h) { if (h.until > now) Object.assign(d, h.patch); else S.hold.delete(d.id); }
    list.push(d);
    byId.set(d.id, d);
  }
  S.devices = list;
  S.byId = byId;
  S.loaded = true;
  S.offline = false;
  const before = S.active;
  // the speaker the player picked, while it's in reach; otherwise whatever is playing, else the nearest
  if (S.want && byId.has(S.want)) S.active = S.want;
  else if (!S.active || !byId.has(S.active)) {
    const d = list.find(x => x.playing && x.track) || list[0];
    S.active = d ? d.id : null;
  }
  if (S.active !== before && S.active) soon(60);   // fetch its queue
  render();
}

// show a change straight away; the server's answer replaces it once it is in
function hold(d, patch, ms = 1400) {
  Object.assign(d, patch);
  const h = S.hold.get(d.id);
  S.hold.set(d.id, { patch: Object.assign(h && h.until > performance.now() ? h.patch : {}, patch), until: performance.now() + ms });
}

async function loadLibrary() {
  const d = await post('phoneLibrary');
  if (d && typeof d === 'object') {
    const favs = asList(d.favs);
    if (favs) setFavs(favs);
    const pl = d.playlists && typeof d.playlists === 'object' ? d.playlists : {};
    S.lib = { mine: asList(pl.mine) || [], shared: asList(pl.shared) || [] };
  } else if (!S.lib) {
    S.lib = { mine: [], shared: [] };
  }
  render();
}

async function loadJams() {
  const d = await post('phoneJams');
  S.jams = (d && asList(d.list)) || [];
  S.jam = d && d.mine && typeof d.mine === 'object' && d.mine.id != null ? d.mine : null;
  render();
}

/* ═══════════════ COMMANDS ═══════════════ */
function send(d, what, value) {
  if (!d) return;
  post('phoneAction', { id: d.id, what, value });
  soon();
}

function toggle(d) {
  if (!d || !nowTrack(d)) return;
  if (d.track) {
    const p = posOf(d);
    hold(d, d.playing ? { playing: false, pos: p } : { playing: true, startedAt: serverNow() - p * 1000 });
  }
  send(d, 'toggle');
  render();
}

function act(d, what) {
  if (!d) return;
  if (what === 'loop' || what === 'shuffle') { hold(d, { [what]: !d[what] }); render(); }
  send(d, what);
}

// the speaker a song or list should go to: the active one, or ask
async function target() {
  const d = active();
  if (d && !d.turntable) return d;
  if (!S.devices.some(x => !x.turntable)) {
    toast(t(S.devices.length ? 'recordsOnlyAll' : 'noSpeakerShort'));
    return null;
  }
  const id = await new Promise(resolve => openSheet('devices', { pick: true, resolve }));
  const picked = id && S.byId.get(id);
  return picked && !picked.turntable ? picked : null;
}

async function playTrack(tr, mode) {
  if (!tr) return;
  const d = await target();
  if (!d) return;
  post('phonePlay', { id: d.id, track: saved(tr), mode: mode === 'queue' ? 'queue' : 'now' });
  toast(mode === 'queue' ? t('addedQueue') : t('sentTo', d.label));
  soon(900);
}

async function playList(key, start, shuffle) {
  const d = await target();
  if (!d) return;
  post('phonePlayList', { id: d.id, list: key === 'liked' ? 'liked' : +key, start: start || 1, shuffle: !!shuffle });
  toast(t('sentTo', d.label));
  soon(1200);
}

async function heart(tr) {
  if (!canHeart(tr)) return;
  const k = keyOf(tr), had = S.favKeys.has(k);
  if (had) S.favKeys.delete(k); else S.favKeys.add(k);   // light the heart now
  render();
  const list = asList(await post('phoneFav', { track: saved(tr) }));
  if (list) setFavs(list);
  else { if (had) S.favKeys.add(k); else S.favKeys.delete(k); }   // refused: put it back
  render();
}

function itemOf(b) {
  const i = +b.dataset.i;
  if (b.dataset.from === 'res') return S.results && S.results[i];
  if (b.dataset.from === 'pl') { const p = openList(); return p && p.tracks[i]; }
  return null;
}

function openNp() {
  if (!active()) return;
  S.np = true;
  render();
  const np = $('np');
  np.classList.add('open');
  np.setAttribute('aria-hidden', 'false');
  $('npScroll').scrollTop = 0;
  soon(50);
}
function closeNp() {
  S.np = false;
  const np = $('np');
  np.classList.remove('open');
  np.setAttribute('aria-hidden', 'true');
}

function setTab(tab) {
  const sc = $('scroll');
  if (tab === S.tab) {
    if (tab === 'library' && S.openPl != null) { S.openPl = null; render(); }
    sc.scrollTo({ top: 0, behavior: 'smooth' });
    if (tab === 'search') focusSearch();
    return;
  }
  S.scrollPos[S.tab] = sc.scrollTop;
  S.tab = tab;
  for (const v of ['home', 'search', 'library', 'jam']) $('v-' + v).hidden = v !== tab;
  document.querySelectorAll('.tab').forEach(x => x.classList.toggle('on', x.dataset.v === tab));
  render();
  sc.scrollTop = S.scrollPos[tab] || 0;
  if (tab === 'library') loadLibrary();
  else if (tab === 'jam') loadJams();
  else if (tab === 'search' && S.results === null) focusSearch();
}
const focusSearch = () => setTimeout(() => { const q = $('q'); if (q) q.focus(); }, 60);

async function runSearch(query) {
  query = String(query || '').trim();
  if (query.length < 2 || S.searching) return;
  S.query = query;
  S.searching = true;
  render();
  const res = await post('phoneSearch', { query });
  S.searching = false;
  S.results = asList(res) || [];
  render();
  $('scroll').scrollTop = 0;
}

const A = {
  tab: b => setTab(b.dataset.v),
  refresh: () => { poll(true); if (S.tab === 'jam') loadJams(); if (S.tab === 'library') loadLibrary(); },
  devices: () => { openSheet('devices'); poll(true); },
  pickDev: b => {
    const id = b.dataset.dev;
    if (!S.byId.has(id)) return;
    S.want = S.active = id;
    store.set('device', id);
    if (S.sheet && S.sheet.kind === 'devices') closeSheet(id);
    render();
    soon(50);
  },
  closeSheet: () => closeSheet(null),
  openNp, closeNp,
  npQueue: () => { const q = $('npQueue'); if (q) $('npScroll').scrollTo({ top: q.offsetTop - 70, behavior: 'smooth' }); },
  toggle: b => toggle(S.byId.get(b.dataset.dev)),
  act: b => act(S.byId.get(b.dataset.dev), b.dataset.w),
  qPlay: b => send(S.byId.get(b.dataset.dev), 'queuePlay', +b.dataset.i),
  qRemove: b => {
    const d = S.byId.get(b.dataset.dev), i = +b.dataset.i;
    if (!d) return;
    if (Array.isArray(d.queue)) {
      const queue = d.queue.filter((_, j) => j !== i - 1);
      hold(d, { queue, queued: queue.length });
      render();
    }
    send(d, 'queueRemove', i);
  },
  heartNow: b => { const d = S.byId.get(b.dataset.dev); heart(d && d.track); },
  moreNow: b => { const d = S.byId.get(b.dataset.dev); if (d && d.track) openSheet('track', { track: d.track, noPlay: true }); },
  heart: b => heart(itemOf(b)),
  play: b => {
    const tr = itemOf(b);
    if (!tr) return;
    if (b.dataset.from === 'pl') return playList(openList().key, +b.dataset.i + 1, false);
    playTrack(tr, 'now');
  },
  more: b => { const tr = itemOf(b); if (tr) openSheet('track', { track: tr, from: b.dataset.from, i: +b.dataset.i }); },
  sPlay: () => {
    const sh = S.sheet;
    closeSheet(null, true);
    if (sh.from === 'pl') return playList(openList().key, sh.i + 1, false);
    playTrack(sh.track, 'now');
  },
  sQueue: () => { const sh = S.sheet; closeSheet(null, true); playTrack(sh.track, 'queue'); },
  sHeart: () => { const sh = S.sheet; closeSheet(null); heart(sh.track); },
  sPlaylists: () => {
    S.sheet.step = 'playlists';
    renderSheet(true);
    if (!S.lib) loadLibrary().then(() => renderSheet(true));
  },
  plAdd: async b => {
    const sh = S.sheet;
    closeSheet(null);
    const id = +b.dataset.pl, p = S.lib && S.lib.mine.find(x => x.id === id);
    const res = await post('phonePlAdd', { playlist: id, track: saved(sh.track) });
    if (res && typeof res === 'object' && !Array.isArray(res)) {
      S.lib = { mine: asList(res.mine) || [], shared: asList(res.shared) || [] };
      if (p) toast(t('addedTo', p.name));
      render();
    }
  },
  quick: b => {
    const v = b.dataset.v;
    if (v === 'search') { setTab('search'); focusSearch(); }
    else if (v === 'liked') { S.openPl = 'liked'; if (S.tab === 'library') render(); else setTab('library'); }
    else if (v === 'queue') { openNp(); setTimeout(A.npQueue, 360); }
    else if (v === 'jam') setTab('jam');
  },
  clearSearch: () => { const q = $('q'); q.value = ''; $('qClear').hidden = true; S.results = null; render(); q.focus(); },
  openPl: b => { S.openPl = b.dataset.pl === 'liked' ? 'liked' : +b.dataset.pl; render(); $('scroll').scrollTop = 0; },
  backLib: () => { S.openPl = null; render(); },
  playList: b => playList(b.dataset.pl, 1, !!b.dataset.shuffle),
  newPl: async () => {
    const name = await ask({ title: t('newPl'), sub: t('newPlSub'), placeholder: t('plName'), ok: t('create') });
    if (!name) return;
    const res = await post('phonePlCreate', { name });
    if (res && typeof res === 'object' && !Array.isArray(res)) {
      S.lib = { mine: asList(res.mine) || [], shared: asList(res.shared) || [] };
      render();
    }
  },
  jamStart: async () => {
    const name = await ask({ title: t('jamStart'), sub: t('jamSub'), placeholder: t('jamName'), ok: t('start'), allowEmpty: true });
    if (name === null) return;
    joined(await post('phoneJamCreate', { name }));
  },
  jamJoin: async b => joined(await post('phoneJamJoin', { id: +b.dataset.id })),
  jamLeave: async () => {
    const was = S.jam && S.jam.emitter;
    await post('phoneJamLeave');
    if (was && S.want === was) { S.want = null; store.set('device', null); }
    S.jam = null;
    await loadJams();
    poll(true);
  },
  jamControl: () => {
    if (!S.jam) return;
    S.want = S.active = S.jam.emitter;
    store.set('device', S.want);
    setTab('home');
    poll(true);
  },
};

// after starting or joining a jam, the app plays into it
async function joined(view) {
  if (view && typeof view === 'object' && view.emitter) {
    S.jam = view;
    S.want = S.active = view.emitter;
    store.set('device', S.want);
  }
  await loadJams();
  poll(true);
}

/* ═══════════════ INPUT ═══════════════ */
document.addEventListener('click', ev => {
  const b = ev.target.closest('[data-a]');
  if (!b || b.disabled) return;
  const fn = A[b.dataset.a];
  if (!fn) return;
  ev.preventDefault();
  fn(b, ev);
});

const touched = () => {
  const idle = performance.now() - S.lastTouch > 30000;
  S.lastTouch = performance.now();
  if (idle) soon(0);    // back from idle polling
};
['pointerdown', 'keydown', 'wheel'].forEach(e => document.addEventListener(e, touched, { passive: true, capture: true }));

// sliders (seek / volume): drag anywhere on the 28 px tall bar
function dragTo(ev) {
  const g = S.drag, r = g.el.getBoundingClientRect();
  g.v = clamp01((ev.clientX - r.left) / (r.width || 1));
  g.el.style.setProperty('--v', g.v.toFixed(4));
  g.el._v = null;
  if (g.kind === 'vol') {
    const d = S.byId.get(g.id);
    if (d) hold(d, { volume: g.v }, 1600);
    const now = performance.now();
    if (now - g.sent > 140) { g.sent = now; post('phoneAction', { id: g.id, what: 'volume', value: +g.v.toFixed(3) }); }
  }
  tick();
}
document.addEventListener('pointerdown', ev => {
  const el = ev.target.closest('[data-sl]');
  if (!el || el.classList.contains('off') || ev.button > 0) return;
  const d = S.byId.get(el.dataset.dev);
  if (!d) return;
  ev.preventDefault();
  S.drag = { el, id: d.id, kind: el.dataset.sl, v: 0, sent: 0 };
  el.classList.add('drag');
  try { el.setPointerCapture(ev.pointerId); } catch (_) { /* old CEF */ }
  dragTo(ev);
});
document.addEventListener('pointermove', ev => { if (S.drag) dragTo(ev); });
function endDrag() {
  const g = S.drag;
  if (!g) return;
  S.drag = null;
  g.el.classList.remove('drag');
  const d = S.byId.get(g.id);
  if (S.dirty) render();
  if (!d) return;
  if (g.kind === 'vol') {
    hold(d, { volume: g.v }, 1600);
    post('phoneAction', { id: d.id, what: 'volume', value: +g.v.toFixed(3) });
  } else if (canSeek(d)) {
    const p = g.v * d.track.duration;
    hold(d, d.playing ? { startedAt: serverNow() - p * 1000 } : { pos: p });
    send(d, 'seek', Math.floor(p));
  }
  tick();
}
document.addEventListener('pointerup', endDrag);
document.addEventListener('pointercancel', endDrag);

$('searchForm').addEventListener('submit', ev => {
  ev.preventDefault();
  const q = $('q');
  runSearch(q.value);
  q.blur();
});
$('q').addEventListener('input', () => { $('qClear').hidden = !$('q').value; });

$('scroll').addEventListener('scroll', () => {
  $('top').classList.toggle('scrolled', $('scroll').scrollTop > 4);
}, { passive: true });

document.addEventListener('keydown', ev => {
  if (ev.key !== 'Escape') return;
  if (S.sheet) { closeSheet(null); ev.stopPropagation(); }
  else if (S.np) { closeNp(); ev.stopPropagation(); }
});

document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(false); });

// lb-phone can nudge the app when one of its speakers changes (client/phone.lua)
window.addEventListener('message', ev => {
  const m = ev.data;
  if (m && (m.nzspk === 'poke' || (m.data && m.data.nzspk === 'poke'))) soon(60);
});

/* ═══════════════ START ═══════════════ */
function applyStrings() {
  document.querySelectorAll('[data-t]').forEach(el => { el.textContent = t(el.dataset.t); });
  $('q').placeholder = t('searchPh');
  document.querySelector('.tab[data-v="search"]').hidden = S.features.search === false;
  document.querySelector('.tab[data-v="jam"]').hidden = S.features.jam === false;
}

function brand(b) {
  const el = $('brand');
  if (!b || typeof b !== 'object') return;
  el.hidden = b.watermark === false;
  if (b.watermark === false || !b.logo || el.querySelector('img')) return;
  const logo = new Image();
  logo.alt = '';
  logo.onload = () => el.classList.add('custom');
  logo.onerror = () => logo.remove();
  logo.src = b.logo;
  el.appendChild(logo);
}

function setInset(name, v) {
  v = Number(v);
  if (v >= 0 && v <= 160) document.documentElement.style.setProperty(name, v + 'px');
}

async function init() {
  applyStrings();
  render();
  const [info] = await Promise.all([post('phoneInit'), poll(true)]);
  if (info && typeof info === 'object') {
    if (info.strings && typeof info.strings === 'object' && !Array.isArray(info.strings)) {
      for (const k of Object.keys(info.strings)) if (typeof info.strings[k] === 'string') T[k] = info.strings[k];
    }
    if (typeof info.name === 'string' && info.name) S.name = info.name;
    if (info.features && typeof info.features === 'object') Object.assign(S.features, info.features);
    if (info.insets && typeof info.insets === 'object') {
      if (!QS.has('top')) setInset('--st', info.insets.top);
      if (!QS.has('bottom')) setInset('--sb', info.insets.bottom);
    }
    brand(info.brand);
    applyStrings();
  }
  if (S.features.search === false && S.tab === 'search') setTab('home');
  render();
  loadLibrary();
  if (S.features.jam !== false) loadJams();
}

setInterval(() => { if (!document.hidden) tick(); }, 250);
init();
})();
