/* ═══════════════════════════════════════════════════════════
   Player UI
   Every clickable thing carries data-a="<action>"; ACTIONS below is the
   single place an action is handled, so a button can never fall through.
   ═══════════════════════════════════════════════════════════ */
const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const App = {
  L: {}, version: '', open: false, id: null, compact: false, view: 'queue',
  favs: [], recent: [], records: null, playlists: null, links: null, jam: null, jams: null,
  people: null, search: null, searchQ: '', busy: false,
  hud: null, hudEdit: false, hudTok: 0, dragSeek: null, confirmFn: null, openPl: null,
  brand: { watermark: true, logo: '', name: '' },
  settings: {
    master: 1, effects: true, streamer: false, compact: false,
    bass: 0, mid: 0, treble: 0,
    skin: 'compact', cover: 'square', glow: false, blur: false, viz: true,
    font: 'Lexend', animIn: 'fade', animOut: 'fade',
  },
};
const t = (k, ...a) => { let s = App.L[k] ?? k; a.forEach(v => { s = s.replace('%s', v); }); return s; };

const fmt = s => {
  s = Math.max(0, Math.floor(s || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = String(s % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${x}` : `${m}:${x}`;
};
const savedKey = tr => tr ? (tr.id || tr.url || '') : '';
const isFav = tr => !!tr && Array.isArray(App.favs) && App.favs.some(f => savedKey(f) === savedKey(tr));
const takeFavs = d => { if (Array.isArray(d)) App.favs = d; };
const cur = () => App.id ? Engine.get(App.id) : null;
const canControl = e => !!e && (e.access !== 'owner' || e.mine);
const hide = () => App.settings.streamer;
const LINKISH = /^(https?:\/\/|[A-Za-z0-9_-]{11}$)/;

/* ─────────── appearance ─────────── */
const SKINS = [['compact','Compact'],['boxy','Boxy'],['gallery','Gallery'],['minimal','Minimal'],['macos','macOS'],['shell','Shell'],['bar','Bar']];
const COVERS = [['square','Square'],['canvas','Canvas'],['vinyl','Vinyl'],['none','None']];
const ANIMS = [['fade','Fade'],['slideLeft','Slide left'],['slideRight','Slide right'],['slideTop','Slide top'],
  ['slideBottom','Slide bottom'],['grow','Grow'],['shrink','Shrink'],['swingLeft','Swing left'],
  ['swingRight','Swing right'],['tiltLeft','Tilt left'],['tiltRight','Tilt right']];
const FONTS = ['Lexend','System','Inter','Roboto','Montserrat','Oswald','Bebas Neue','Courier New'];

function applyAppearance() {
  const np = $('np'), s = App.settings;
  np.className = 'np';
  $('npWrap').classList.toggle('edit', !!App.hudEdit);
  np.classList.add('skin-' + (s.skin || 'compact'), 'cov-' + (s.cover || 'square'));
  if (s.glow) np.classList.add('glow');
  if (s.blur) np.classList.add('blurbg');
  if (!s.viz) np.classList.add('no-viz');
  np.style.setProperty('--np-font', s.font === 'System' ? 'system-ui' : `'${s.font}'`);
  placeHud();
}

function playAnim(kind) {
  const np = $('np'), s = App.settings;
  np.classList.remove('anim-in', 'anim-out', ...[...np.classList].filter(c => c.startsWith('in-') || c.startsWith('out-')));
  void np.offsetWidth;
  if (kind === 'in') np.classList.add('anim-in', 'in-' + (s.animIn || 'fade'));
  else np.classList.add('anim-out', 'out-' + (s.animOut || 'fade'));
}

function applyBrand() {
  const b = App.brand || {};
  document.querySelectorAll('.mark').forEach(el => {
    el.classList.toggle('hidden', b.watermark === false);
    if (b.watermark !== false && b.logo) {
      el.style.backgroundImage = `url("${b.logo}")`;
      el.classList.add('custom');
    } else {
      el.style.backgroundImage = '';
      el.classList.remove('custom');
    }
  });
  const sub = $('ctxSub');
  if (b.name && sub && !sub.dataset.locked) sub.dataset.brand = b.name;
}

/* ─────────── locale ─────────── */
function applyLocale() {
  document.querySelectorAll('[data-l]').forEach(el => { el.textContent = t(el.dataset.l); });
  $('urlIn').placeholder = t('search_ph');
  $('ver').textContent = 'v' + App.version;
}

/* ─────────── open / close ─────────── */
// Compact shows only the now-playing rail, so the link / search row rides along with it.
function applyCompact() {
  const row = $('entryRow'), rail = document.querySelector('.rail'), main = document.querySelector('.main');
  $('player').classList.toggle('compact', App.compact);
  if (App.compact) { if (row.parentElement !== rail) rail.insertBefore(row, rail.querySelector('.seek')); }
  else if (row.parentElement !== main) main.insertBefore(row, $('list'));
}
const entryHidden = (e, view) => !!(e && e.turntable) || (!App.compact && !['queue', 'search'].includes(view));

function openUI(id, compact) {
  App.id = id; App.open = true;
  const e = cur();
  App.compact = !!compact;
  const vin = !!(e && e.turntable), jam = !!(e && e.kind === 'jam');
  $('player').hidden = false;
  applyCompact();
  $('player').classList.toggle('vmode', vin);
  $('ctxTitle').textContent = jam ? t('jam') : e && e.kind === 'vehicle' ? t('carplay') : vin ? t('turntable') : t('boombox');
  const sub = e && e.kind === 'boombox' ? (e.label || '') : '';
  $('ctxSub').textContent = sub.toLowerCase() === $('ctxTitle').textContent.toLowerCase() ? '' : sub;
  $('urlIn').value = '';
  Engine.unlock();
  if (vin && !['tracks','records','settings'].includes(App.view)) App.view = 'tracks';
  if (!vin && ['tracks','records'].includes(App.view)) App.view = 'queue';
  render();
  go(App.view);
}

function closeUI(tell) {
  if (!App.open) return;
  App.open = false; App.id = null; App.hudEdit = false;
  $('player').hidden = true;
  $('scrim').hidden = true;
  if (tell) post('close');
}

/* ─────────── render ─────────── */
function render() {
  if (!App.open) return;
  const e = cur();
  if (!e) return;
  const tr = e.track, ctl = canControl(e), hidden = hide();
  const vin = !!e.turntable, rec = e.vinyl, jam = e.kind === 'jam';

  $('stDot').className = 'dot' + (tr ? (e.playing ? ' live' : ' paused') : '');
  $('stText').textContent = tr ? (e.playing ? t('live') : t('paused')) : t('idle');
  $('lockChip').hidden = e.access !== 'owner';
  $('groupChip').hidden = !(e.groupSize > 1);
  if (e.groupSize > 1) $('groupTxt').textContent = t('link_count', e.groupSize);

  // art
  const art = $('art'), img = $('artImg');
  const thumb = tr && !hidden && !vin ? tr.thumb : null;
  art.classList.toggle('vinyl', vin && !!rec);
  art.classList.toggle('spinning', vin && !!rec && !!e.playing);
  art.classList.toggle('has', vin ? !!rec : (!!thumb || (!!tr && hidden)));
  if (thumb && img.dataset.src !== thumb) { img.dataset.src = thumb; img.src = thumb; }
  if (!thumb) { img.removeAttribute('src'); img.dataset.src = ''; }
  if (rec) {
    const cover = hidden ? '' : rec.cover || '';
    ['vCover', 'vLabel'].forEach(k => {
      const el = $(k);
      if (el.dataset.src !== cover) { el.dataset.src = cover; if (cover) el.src = cover; else el.removeAttribute('src'); }
      el.hidden = !cover;
    });
  }
  const needle = vin && rec && rec.loading;
  $('loadTxt').textContent = needle ? t('needle') : t('loading');
  art.classList.toggle('loading', App.loadingId === e.id || !!needle);
  art.classList.toggle('needle', !!needle);
  $('emptyT').textContent = vin ? t('no_record') : t('nothing');
  $('emptyS').textContent = vin ? t('no_record_s') : t('nothing_sub');

  // meta
  if (vin && rec && !tr) {
    $('tTitle').textContent = hidden ? t('hidden') : rec.album;
    $('tAuthor').textContent = hidden ? t('muted_stream') : rec.artist;
  } else if (vin && !rec) {
    $('tTitle').textContent = t('no_record'); $('tAuthor').textContent = t('no_record_s');
  } else {
    $('tTitle').textContent = tr ? (hidden ? t('hidden') : tr.title) : t('nothing');
    $('tAuthor').textContent = tr ? (hidden ? t('muted_stream') : (tr.author || '') + (vin && rec ? `, ${rec.album}` : '')) : t('nothing_sub');
  }
  const fav = document.querySelector('[data-a=favNow]');
  fav.hidden = vin;
  fav.disabled = !tr;
  fav.classList.toggle('on', isFav(tr));
  fav.innerHTML = `<i class="fa-${isFav(tr) ? 'solid' : 'regular'} fa-heart"></i>`;

  // transport
  $('playBtn').innerHTML = `<i class="fa-solid fa-${e.playing ? 'pause' : 'play'}"></i>`;
  document.querySelectorAll('.transport button').forEach(b => { b.disabled = !ctl || (!tr && !['shuffle','loop'].includes(b.dataset.a)); });
  if (vin && rec && !tr) $('playBtn').disabled = !ctl;
  $('shuffleBtn').classList.toggle('on', !!e.shuffle);
  $('loopBtn').classList.toggle('on', !!e.loop);
  $('seekBar').classList.toggle('off', !ctl || !tr || !(tr.duration > 0));

  // dials
  const vol = $('volSlider'), rng = $('rangeSlider');
  if (document.activeElement !== vol) vol.value = Math.round((e.volume ?? 0.7) * 100);
  rng.min = e.rangeMin; rng.max = e.rangeMax;
  if (document.activeElement !== rng) rng.value = Math.round(e.range);
  vol.disabled = rng.disabled = !ctl;
  $('rangeDial').hidden = jam;
  paintRange(vol); paintRange(rng);
  $('volVal').textContent = vol.value + '%';
  $('rangeVal').textContent = rng.value + ' m';
  $('volIco').className = 'fa-solid ' + (vol.value == 0 ? 'fa-volume-xmark' : vol.value < 45 ? 'fa-volume-low' : 'fa-volume-high');

  // entry row + footer
  $('entryRow').hidden = entryHidden(e, App.view);
  document.querySelectorAll('#entryRow button').forEach(b => { b.disabled = !ctl; });
  $('urlIn').disabled = !ctl;
  const boom = e.kind === 'boombox';
  $('carryBtn').hidden = !(boom && e.portable && e.state === 'placed' && e.canPickup);
  $('packBtn').hidden = !(boom && (e.canPickup || e.carriedByMe));
  $('ejectBtn').hidden = !(vin && rec);
  $('stopBtn').disabled = !ctl || !tr;

  $('qCount').textContent = (e.queue || []).length;
  $('fCount').textContent = App.favs.length;
  $('tCount').textContent = rec ? rec.tracks.length : 0;
  const lc = $('lCount');
  lc.textContent = e.groupSize > 1 ? e.groupSize : 0;
  lc.hidden = !(e.groupSize > 1);
  $('sizeBtn').innerHTML = `<i class="fa-solid fa-${App.compact ? 'up-right-and-down-left-from-center' : 'down-left-and-up-right-to-center'}"></i>`;

  const dragging = document.activeElement && document.activeElement.type === 'range' && $('list').contains(document.activeElement);
  const typing = document.activeElement && document.activeElement.tagName === 'INPUT' && $('list').contains(document.activeElement);
  if (!dragging && !typing) renderView();
}

function paintRange(el) {
  const p = ((el.value - el.min) / (el.max - el.min || 1)) * 100;
  el.style.setProperty('--p', p + '%');
}

/* ─────────── views ─────────── */
function go(view) {
  App.view = view;
  document.querySelectorAll('.nav-i').forEach(b => b.classList.toggle('on', b.dataset.v === view));
  if (view === 'records') loadRecords();
  else if (view === 'playlists') loadPlaylists();
  else if (view === 'links') loadLinks();
  else if (view === 'jam') loadJams();
  const e = cur();
  if (e) $('entryRow').hidden = entryHidden(e, view);
  renderView();
}

function head(title, sub, extra) {
  return `<div class="vhead"><div><h2>${esc(title)}</h2>${sub ? `<p>${esc(sub)}</p>` : ''}</div>${extra || ''}</div>`;
}

function emptyState(icon, title, sub) {
  return `<div class="empty"><i class="fa-solid ${icon}"></i><b>${esc(title)}</b><span>${esc(sub)}</span></div>`;
}

function songRow(tr, opts) {
  const o = opts || {};
  const hidden = hide();
  const th = tr.thumb && !hidden ? `<img src="${esc(tr.thumb)}" alt="">` : '<i class="fa-solid fa-music"></i>';
  return `<div class="row ${o.now ? 'now' : ''}">
    ${o.idx !== undefined ? `<span class="idx ${o.now ? 'now' : ''}">${o.now && o.playing ? '<i class="fa-solid fa-volume-high"></i>' : o.idx}</span>` : ''}
    <div class="thumb">${th}</div>
    <div class="row-txt"><b>${esc(hidden ? t('hidden') : tr.title)}</b><span>${esc(hidden ? '' : (tr.author || '') + (o.by ? `, ${o.by}` : ''))}</span></div>
    <span class="dur">${tr.duration > 0 ? fmt(tr.duration) : ''}</span>
    <div class="acts">${o.acts || ''}</div></div>`;
}

const RENDER = {
  queue(e, ctl) {
    const q = e.queue || [];
    let h = head(t('up_next'), q.length ? t('pl_songs', q.length) : t('empty_queue_s'));
    h += q.length ? q.map((tr, i) => songRow(tr, { idx: i + 1, by: tr.by, acts:
        `<button class="icon-btn" data-a="qplay" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-play"></i></button>
         <button class="icon-btn del" data-a="qdel" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-xmark"></i></button>` })).join('')
      : emptyState('fa-list-ul', t('empty_queue'), t('empty_queue_s'));
    return h;
  },

  search(e, ctl) {
    let h = head(t('search'), App.searchQ ? `"${App.searchQ}"` : t('search_hint_s'));
    if (App.busy) h += `<div class="empty"><div class="spin"></div><b>${esc(t('searching'))}</b></div>`;
    else if (App.search === null) h += emptyState('fa-magnifying-glass', t('search_hint'), t('search_hint_s'));
    else if (!App.search.length) h += emptyState('fa-magnifying-glass', t('no_results'), t('no_results_s'));
    else h += App.search.map((r, i) => songRow(r, { acts:
        `<button class="icon-btn heart ${isFav(r) ? 'on' : ''}" data-a="favSearch" data-i="${i}"><i class="fa-${isFav(r) ? 'solid' : 'regular'} fa-heart"></i></button>
         <button class="icon-btn" data-a="sPlay" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-play"></i></button>
         <button class="icon-btn" data-a="sQueue" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-plus"></i></button>` })).join('');
    return h;
  },

  liked(e, ctl) {
    const nowKey = savedKey(e.track);
    let h = head(t('liked'), t('pl_songs', App.favs.length));
    h += App.favs.length ? App.favs.map((tr, i) => songRow(tr, { idx: i + 1, now: savedKey(tr) === nowKey, playing: e.playing, acts:
        `<button class="icon-btn" data-a="libPlay" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-play"></i></button>
         <button class="icon-btn" data-a="libQueue" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-plus"></i></button>
         <button class="icon-btn heart on" data-a="libFav" data-i="${i}"><i class="fa-solid fa-heart"></i></button>` })).join('')
      : emptyState('fa-heart', t('empty_favs'), t('empty_favs_s'));
    return h;
  },

  recent(e, ctl) {
    const nowKey = savedKey(e.track);
    let h = head(t('recent'), t('pl_songs', App.recent.length));
    h += App.recent.length ? App.recent.map((tr, i) => songRow(tr, { now: savedKey(tr) === nowKey, playing: e.playing, acts:
        `<button class="icon-btn" data-a="recPlay" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-play"></i></button>
         <button class="icon-btn heart ${isFav(tr) ? 'on' : ''}" data-a="recFav" data-i="${i}"><i class="fa-${isFav(tr) ? 'solid' : 'regular'} fa-heart"></i></button>
         <button class="icon-btn del" data-a="recDel" data-i="${i}"><i class="fa-solid fa-trash-can"></i></button>` })).join('')
      : emptyState('fa-clock-rotate-left', t('empty_recent'), t('empty_recent_s'));
    return h;
  },

  playlists(e, ctl) {
    const d = App.playlists;
    if (d === 'loading' || !d) return '<div class="empty"><div class="spin"></div></div>';
    if (App.openPl) return RENDER.playlistOne(e, ctl);

    let h = head(t('playlists'), t('pl_none_s'), `<div class="head-acts">
        <button class="btn-teal" data-a="plNew"><i class="fa-solid fa-plus"></i>${esc(t('pl_new'))}</button>
      </div>`);
    h += `<div class="maker">
        <div class="field-in"><i class="fa-solid fa-link"></i><input id="plLink" placeholder="${esc(t('pl_import_s'))}"></div>
        <button class="btn-line" data-a="plImport"><i class="fa-solid fa-download"></i>${esc(t('pl_import'))}</button>
      </div>
      <div class="maker">
        <div class="field-in"><i class="fa-solid fa-wand-magic-sparkles"></i><input id="plPrompt" placeholder="${esc(t('pr_ph'))}"></div>
        <button class="btn-line" data-a="plPrompt"><i class="fa-solid fa-sparkles"></i>${esc(t('pr_make'))}</button>
      </div>`;

    const KIND = { blend: ['fa-code-merge', t('k_blend')], collab: ['fa-user-group', t('k_collab')], prompted: ['fa-wand-magic-sparkles', t('k_prompted')] };
    const card = p => {
      const k = KIND[p.kind];
      return `<div class="pcard" data-a="plOpen" data-pl="${p.id}">
        <div class="pcard-art"><i class="fa-solid ${k ? k[0] : 'fa-rectangle-list'}"></i></div>
        <div class="pcard-t"><b>${esc(p.name)}</b><span>${esc(t('pl_songs', p.count))}${p.mine ? '' : ' · ' + esc(t('pl_by', p.owner))}</span></div>
        <div class="pcard-tags">
          ${k ? `<span class="tag">${esc(k[1])}</span>` : ''}
          ${p.mixed ? `<span class="tag">${esc(t('k_mixed'))}</span>` : ''}
          ${p.shared ? `<span class="tag teal">${esc(t('k_shared'))}</span>` : ''}
        </div></div>`;
    };
    const mine = d.mine || [], shared = (d.shared || []).filter(p => !p.mine);
    if (!mine.length && !shared.length) h += emptyState('fa-rectangle-list', t('pl_none'), t('pl_none_s'));
    if (mine.length) h += `<div class="grp">${esc(t('pl_mine'))}</div><div class="pgrid">${mine.map(card).join('')}</div>`;
    if (shared.length) h += `<div class="grp">${esc(t('pl_shared_t'))}</div><div class="pgrid">${shared.map(card).join('')}</div>`;
    return h;
  },

  playlistOne(e, ctl) {
    const d = App.playlists || {};
    const all = [...(d.mine || []), ...(d.shared || [])];
    const p = all.find(x => x.id === App.openPl);
    if (!p) { App.openPl = null; return RENDER.playlists(e, ctl); }
    let h = `<div class="back" data-a="plBack"><i class="fa-solid fa-chevron-left"></i> ${esc(t('playlists'))}</div>`;
    h += head(p.name, `${t('pl_songs', p.count)}${p.mine ? '' : ' · ' + t('pl_by', p.owner)}`, `<div class="head-acts">
        <button class="btn-teal" data-a="plPlay" data-pl="${p.id}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-play"></i>${esc(t('pl_play'))}</button>
        ${e.track && p.canEdit ? `<button class="btn-line" data-a="plAddNow" data-pl="${p.id}"><i class="fa-solid fa-plus"></i>${esc(t('pl_add_here'))}</button>` : ''}
      </div>`);
    if (p.mine) {
      h += `<div class="chips">
        <button class="chipb ${p.shared ? 'on' : ''}" data-a="plShare" data-pl="${p.id}"><i class="fa-solid fa-share-nodes"></i>${esc(p.shared ? t('pl_unshare') : t('pl_share'))}</button>
        <button class="chipb ${p.mixed ? 'on' : ''}" data-a="plMixed" data-pl="${p.id}"><i class="fa-solid fa-sliders"></i>${esc(t('k_mixed'))}</button>
        <button class="chipb" data-a="plCollab" data-pl="${p.id}"><i class="fa-solid fa-user-group"></i>${esc(t('k_collab'))}${p.collabs ? ` (${p.collabs})` : ''}</button>
        <button class="chipb del" data-a="plDel" data-pl="${p.id}"><i class="fa-solid fa-trash-can"></i>${esc(t('pl_del'))}</button>
      </div>`;
    }
    h += (p.tracks || []).length
      ? p.tracks.map((tr, i) => songRow(tr, { idx: i + 1, acts:
          `<button class="icon-btn" data-a="plTrack" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-play"></i></button>
           ${p.canEdit ? `<button class="icon-btn del" data-a="plTrackDel" data-i="${i}" data-pl="${p.id}"><i class="fa-solid fa-xmark"></i></button>` : ''}` })).join('')
      : emptyState('fa-music', t('pl_empty'), t('pl_add_here'));
    return h;
  },

  records(e, ctl) {
    const list = App.records;
    if (list === null) return '<div class="empty"><div class="spin"></div></div>';
    let h = head(t('records'), t('pl_songs', list.length));
    h += list.length ? `<div class="pgrid">${list.map((r, i) => `
      <div class="pcard" data-a="puton" data-i="${i}">
        <div class="pcard-art">${r.cover ? `<img src="${esc(r.cover)}" alt="">` : '<i class="fa-solid fa-record-vinyl"></i>'}</div>
        <div class="pcard-t"><b>${esc(r.album)}</b><span>${esc(r.artist)}${r.year ? ` · ${esc(r.year)}` : ''}</span></div>
        <div class="pcard-tags"><span class="tag">${esc(t('tracks_n', r.count))}</span>
          <span class="tag teal">${esc(t('put_on'))}</span></div>
      </div>`).join('')}</div>` : emptyState('fa-record-vinyl', t('no_records'), t('no_records_s'));
    return h;
  },

  tracks(e, ctl) {
    const rec = e.vinyl;
    if (!rec) return emptyState('fa-record-vinyl', t('no_record'), t('no_record_s'));
    let h = head(rec.album, `${rec.artist}${rec.year ? ` · ${rec.year}` : ''}`, '');
    h += rec.tracks.map((title, i) => {
      const now = e.track && rec.idx === i + 1;
      return `<div class="row ${now ? 'now' : ''}">
        <span class="idx ${now ? 'now' : ''}">${now && e.playing ? '<i class="fa-solid fa-volume-high"></i>' : i + 1}</span>
        <div class="row-txt"><b>${esc(hide() ? t('hidden') : title)}</b><span>${esc(hide() ? '' : rec.artist)}</span></div>
        <div class="acts"><button class="icon-btn" data-a="vtrack" data-i="${i}" ${ctl ? '' : 'disabled'}><i class="fa-solid fa-play"></i></button></div>
      </div>`;
    }).join('');
    return h;
  },

  links(e, ctl) {
    const list = App.links;
    if (list === 'loading' || !list) return '<div class="empty"><div class="spin"></div></div>';
    let h = head(t('links'), t('link_this'));
    if (e.group) h += `<div class="chips"><button class="chipb del" data-a="unlink"><i class="fa-solid fa-link-slash"></i>${esc(t('link_drop'))}</button></div>`;
    h += list.length ? list.map(sp => `<div class="row ${sp.linked ? 'now' : ''}">
        <div class="thumb"><i class="fa-solid fa-tower-broadcast"></i></div>
        <div class="row-txt"><b>${esc(sp.label || 'Speaker')}</b><span>${sp.distance}m${sp.linked ? ' · ' + esc(t('link_in')) : sp.busy ? ' · ' + esc(t('link_busy')) : ''}</span></div>
        <div class="acts"><button class="icon-btn ${sp.linked ? 'del' : ''}" data-a="${sp.linked ? 'unlinkOne' : 'link'}" data-id="${esc(sp.id)}" ${ctl ? '' : 'disabled'}>
          <i class="fa-solid fa-${sp.linked ? 'link-slash' : 'link'}"></i></button></div></div>`).join('')
      : emptyState('fa-link-slash', t('link_none'), t('link_none_s'));
    return h;
  },

  jam(e, ctl) {
    if (App.jams === 'loading' || App.jams === null) return '<div class="empty"><div class="spin"></div></div>';
    let h = head(t('jam'), t('jam_s'), App.jam ? '' : `<div class="head-acts">
        <button class="btn-teal" data-a="jamStart"><i class="fa-solid fa-plus"></i>${esc(t('jam_start'))}</button></div>`);
    if (App.jam) {
      h += `<div class="jam-card">
        <div class="jam-h"><b>${esc(App.jam.name)}</b><span>${esc(t('jam_host', App.jam.host))}</span></div>
        <div class="jam-m">${App.jam.members.map(m => `<span class="tag ${m.host ? 'teal' : ''}">${esc(m.name)}${m.host ? ' ★' : ''}</span>`).join('')}</div>
        <button class="btn-red" data-a="jamLeave"><i class="fa-solid fa-right-from-bracket"></i>${esc(t('jam_leave'))}</button>
      </div>
      <div class="audio-note ok"><i class="fa-solid fa-headphones"></i><span>${esc(t('jam_note'))}</span></div>`;
    }
    const others = (App.jams || []).filter(j => !j.mine);
    if (others.length) {
      h += `<div class="grp">${esc(t('jam_open'))}</div>` + others.map(j => `<div class="row">
          <div class="thumb"><i class="fa-solid fa-user-group"></i></div>
          <div class="row-txt"><b>${esc(j.name)}</b><span>${esc(t('jam_host', j.host))} · ${esc(t('jam_people', j.count))}</span></div>
          <div class="acts"><button class="icon-btn" data-a="jamJoin" data-id="${j.id}"><i class="fa-solid fa-right-to-bracket"></i></button></div>
        </div>`).join('');
    } else if (!App.jam) {
      h += emptyState('fa-user-group', t('jam_none'), t('jam_none_s'));
    }
    return h;
  },

  settings(e) { return renderSettings(e); },
};

function renderView() {
  const box = $('list'), e = cur();
  if (!e) return;
  const fn = RENDER[App.view] || RENDER.queue;
  box.innerHTML = fn(e, canControl(e));
  box.querySelectorAll('input[type=range]').forEach(paintRange);
}

/* ─────────── settings ─────────── */
function skinPreview(k) {
  const sq = '<span class="sq"></span>';
  const lines = '<span style="flex:1;display:flex;flex-direction:column;gap:3px"><span class="ln" style="width:80%"></span><span class="ln" style="width:55%"></span></span>';
  if (k === 'gallery') return `<span class="pv col"><span class="ln" style="height:14px;border-radius:2px"></span><span class="ln" style="width:70%;margin:0 auto"></span></span>`;
  if (k === 'minimal') return `<span class="pv"><span class="ln" style="flex:1;height:4px;border-radius:99px"></span></span>`;
  if (k === 'macos') return `<span class="pv"><span class="bar"></span>${sq}${lines}</span>`;
  if (k === 'shell') return `<span class="pv"><span class="bar" style="background:rgba(8,175,162,.35)"></span>${lines}</span>`;
  if (k === 'boxy') return `<span class="pv" style="gap:5px">${sq}${sq}${lines}</span>`;
  if (k === 'bar') return `<span class="pv" style="padding:6px 3px">${sq}<span class="ln" style="flex:1"></span></span>`;
  return `<span class="pv">${sq}${lines}</span>`;
}
function coverPreview(k) {
  if (k === 'canvas') return `<span class="pv"><span class="ln" style="width:70%;height:18px;border-radius:3px;margin:auto"></span></span>`;
  if (k === 'vinyl') return `<span class="pv" style="justify-content:center"><span class="circ"></span></span>`;
  if (k === 'none') return `<span class="pv" style="justify-content:center"><span style="color:var(--ink-3);font-size:11px">—</span></span>`;
  return `<span class="pv" style="justify-content:center"><span class="sq" style="width:16px;height:16px"></span></span>`;
}

function renderSettings(e) {
  const s = App.settings;
  let h = head(t('settings'), '');
  if (e.kind === 'boombox' && e.mine) {
    h += `<div class="grp">${esc(t('this_speaker'))}</div>
      <div class="set"><div class="set-txt"><b>${esc(t('access'))}</b></div>
        <div class="seg"><button data-a="access" data-v="anyone" class="${e.access !== 'owner' ? 'on' : ''}">${esc(t('access_all'))}</button>
        <button data-a="access" data-v="owner" class="${e.access === 'owner' ? 'on' : ''}">${esc(t('access_owner'))}</button></div></div>`;
  }
  if (e.kind === 'vehicle' && e.unit) {
    h += `<div class="grp">${esc(t('this_speaker'))}</div>
      <div class="set"><div class="set-txt"><b>${esc(t('remove_unit'))}</b></div>
      <button class="btn-red" data-a="askUnit"><i class="fa-solid fa-screwdriver-wrench"></i>${esc(t('remove'))}</button></div>`;
  }
  h += `<div class="grp">${esc(t('personal'))}</div>
    <div class="set"><div class="set-txt"><b>${esc(t('master'))}</b></div>
      <input type="range" min="0" max="100" step="1" value="${Math.round(s.master * 100)}" data-s="master"></div>
    <div class="set"><div class="set-txt"><b>${esc(t('effects'))}</b><span>${esc(t('effects_s'))}</span></div>
      <button class="sw ${s.effects ? 'on' : ''}" data-a="tog" data-s="effects"><i></i></button></div>`;

  if (NP.enabled) {
    const sc = Math.round((s.hudScale ?? NP.scale) * 100);
    h += `<div class="grp">${esc(t('np_card'))}</div>
      <div class="set"><div class="set-txt"><b>${esc(t('np_show'))}</b><span>${esc(t('np_show_s'))}</span></div>
        <button class="sw ${s.hud !== false ? 'on' : ''}" data-a="togHud"><i></i></button></div>
      <div class="set"><div class="set-txt"><b>${esc(t('np_size'))}</b></div>
        <div class="set-row"><input type="range" min="80" max="140" step="5" value="${sc}" data-s="hudScale"><span class="val" id="npScaleVal">${sc}%</span></div></div>
      <div class="set"><div class="set-txt"><b>${esc(App.hudEdit ? t('np_drag') : t('np_move'))}</b></div>
        <div class="set-row">
          <button class="btn-line" data-a="hudReset"><i class="fa-solid fa-rotate-left"></i>${esc(t('np_reset'))}</button>
          <button class="${App.hudEdit ? 'btn-teal' : 'btn-line'}" data-a="hudMove"><i class="fa-solid fa-${App.hudEdit ? 'check' : 'up-down-left-right'}"></i>${esc(App.hudEdit ? t('np_done') : t('np_move'))}</button>
        </div></div>
      <div class="grp">${esc(t('ap_player'))}</div><div class="pick">` +
      SKINS.map(([k, label]) => `<button data-a="skin" data-v="${k}" class="${s.skin === k ? 'on' : ''}">${skinPreview(k)}${esc(label)}</button>`).join('') + `</div>
      <div class="grp">${esc(t('ap_cover'))}</div><div class="pick">` +
      COVERS.map(([k, label]) => `<button data-a="cover" data-v="${k}" class="${s.cover === k ? 'on' : ''}">${coverPreview(k)}${esc(label)}</button>`).join('') + `</div>
      <div class="set"><div class="set-txt"><b>${esc(t('ap_glow'))}</b><span>${esc(t('ap_glow_s'))}</span></div>
        <button class="sw ${s.glow ? 'on' : ''}" data-a="tog" data-s="glow"><i></i></button></div>
      <div class="set"><div class="set-txt"><b>${esc(t('ap_blur'))}</b><span>${esc(t('ap_blur_s'))}</span></div>
        <button class="sw ${s.blur ? 'on' : ''}" data-a="tog" data-s="blur"><i></i></button></div>
      <div class="set"><div class="set-txt"><b>${esc(t('ap_viz'))}</b><span>${esc(t('ap_viz_s'))}</span></div>
        <button class="sw ${s.viz !== false ? 'on' : ''}" data-a="tog" data-s="viz"><i></i></button></div>
      <div class="set"><div class="set-txt"><b>${esc(t('ap_font'))}</b></div>
        <select class="fontsel" data-s="font">${FONTS.map(f => `<option ${s.font === f ? 'selected' : ''}>${esc(f)}</option>`).join('')}</select></div>
      <div class="set"><div class="set-txt"><b>${esc(t('ap_in'))}</b></div>
        <select class="fontsel" data-s="animIn">${ANIMS.map(([k, l]) => `<option value="${k}" ${s.animIn === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>
      <div class="set"><div class="set-txt"><b>${esc(t('ap_out'))}</b></div>
        <select class="fontsel" data-s="animOut">${ANIMS.map(([k, l]) => `<option value="${k}" ${s.animOut === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>`;
  }

  const st = Engine.status(App.id);
  const canFx = st && st.fx;
  h += `<div class="grp">${esc(t('ap_sound'))}</div>
    <div class="audio-note ${canFx ? 'ok' : 'warn'}">
      <i class="fa-solid fa-${canFx ? 'circle-check' : 'triangle-exclamation'}"></i>
      <span>${esc(canFx ? t('fx_on') : (st ? t('fx_off') : t('fx_idle')))}</span></div>`;
  [['bass', t('eq_bass')], ['mid', t('eq_mid')], ['treble', t('eq_treble')]].forEach(([k, label]) => {
    const v = s[k] || 0;
    h += `<div class="set"><div class="eqrow" style="flex:1">
      <span class="lbl">${esc(label)}</span>
      <input type="range" min="-12" max="12" step="1" value="${v}" data-s="${k}" ${canFx ? '' : 'disabled'}>
      <span class="val" id="eqv-${k}">${v > 0 ? '+' : ''}${v} dB</span></div></div>`;
  });
  h += `<div class="set"><div class="set-txt"><b>${esc(t('eq_reset'))}</b></div>
      <button class="btn-line" data-a="eqReset"><i class="fa-solid fa-rotate-left"></i>${esc(t('np_reset'))}</button></div>`;
  if (App.streamerAllowed) {
    h += `<div class="set"><div class="set-txt"><b>${esc(t('streamer'))}</b><span>${esc(t('streamer_s'))}</span></div>
      <button class="sw ${s.streamer ? 'on' : ''}" data-a="tog" data-s="streamer"><i></i></button></div>`;
  }
  return h;
}

/* ─────────── loaders ─────────── */
async function loadLists() {
  const d = await post('lists');
  if (d) { takeFavs(d.favs); if (Array.isArray(d.recent)) App.recent = d.recent; }
  render();
}
async function loadRecords() {
  App.records = null;
  const d = await post('vinylOwned');
  App.records = Array.isArray(d) ? d : [];
  if (App.view === 'records') renderView();
}
async function loadPlaylists() {
  if (App.playlists === 'loading') return;
  App.playlists = 'loading';
  const d = await post('playlists');
  App.playlists = d && typeof d === 'object' ? d : { mine: [], shared: [] };
  if (App.view === 'playlists') renderView();
}
async function loadLinks() {
  App.links = 'loading';
  const d = await post('linksNearby');
  App.links = Array.isArray(d) ? d : [];
  if (App.view === 'links') renderView();
}
async function loadJams() {
  App.jams = 'loading';
  const d = await post('jamList');
  App.jams = (d && d.list) || [];
  App.jam = (d && d.mine) || null;
  if (App.view === 'jam') renderView();
}

async function runSearch(query, mode) {
  App.searchQ = query;
  App.search = null;
  App.busy = true;
  go('search');
  const res = await post('search', { query });
  App.busy = false;
  App.search = Array.isArray(res) ? res : [];
  if (mode) {
    const first = App.search[0];
    if (first) post('play', { input: first.id, mode });
  }
  if (App.view === 'search') renderView();
}

/* ─────────── actions ─────────── */
function confirmBox(title, text, okLabel, fn) {
  $('mTitle').textContent = title; $('mText').textContent = text;
  $('mOk').textContent = okLabel;
  App.confirmFn = fn;
  $('scrim').hidden = false;
}

function submit(mode) {
  const inp = $('urlIn');
  const v = inp.value.trim();
  if (!v) { inp.parentElement.classList.add('err'); setTimeout(() => inp.parentElement.classList.remove('err'), 900); return; }
  if (LINKISH.test(v)) { post('play', { input: v, mode }); inp.value = ''; return; }
  runSearch(v);
  inp.value = '';
}

// only accept a real playlist payload; anything else leaves what we already have
const plAfter = d => {
  if (d && typeof d === 'object' && (Array.isArray(d.mine) || Array.isArray(d.shared))) App.playlists = d;
  renderView();
};

const ACTIONS = {
  // nav + transport
  go: (b) => go(b.dataset.v),
  toggle: () => post('toggle'),
  prev: () => post('prev'),
  next: () => post('next'),
  loop: () => post('loop'),
  shuffle: () => post('shuffle'),
  carry: () => post('carry'),
  pack: () => post('pack'),
  eject: () => { post('vinylEject'); setTimeout(loadRecords, 400); },
  askStop: () => confirmBox(t('confirm_stop'), t('confirm_stop_s'), t('stop'), () => post('stop')),
  askUnit: () => confirmBox(t('confirm_unit'), t('confirm_unit_s'), t('remove'), () => post('removeUnit')),
  access: (b) => { const e = cur(); if (e) { e.access = b.dataset.v; renderView(); } post('access', { value: b.dataset.v }); },

  // entry
  playInput: () => submit('now'),
  queueInput: () => submit('queue'),

  // queue
  qplay: (b, i) => post('queuePlay', { value: i + 1 }),
  qdel: (b, i) => post('queueRemove', { value: i + 1 }),

  // search results
  sPlay: (b, i) => { const r = App.search[i]; if (r) post('play', { input: r.id, mode: 'now' }); },
  sQueue: (b, i) => { const r = App.search[i]; if (r) post('play', { input: r.id, mode: 'queue' }); },
  favSearch: async (b, i) => { const r = App.search[i]; if (!r) return; takeFavs(await post('fav', { track: r })); render(); },

  // library
  libPlay: (b, i) => { const tr = App.favs[i]; if (tr) post('playSaved', { track: tr, mode: 'now' }); },
  libQueue: (b, i) => { const tr = App.favs[i]; if (tr) post('playSaved', { track: tr, mode: 'queue' }); },
  libFav: async (b, i) => { const tr = App.favs[i]; if (!tr) return; takeFavs(await post('fav', { track: tr })); render(); },
  recPlay: (b, i) => { const tr = App.recent[i]; if (tr) post('playSaved', { track: tr, mode: 'now' }); },
  recFav: async (b, i) => { const tr = App.recent[i]; if (!tr) return; takeFavs(await post('fav', { track: tr })); render(); },
  recDel: async (b, i) => { const tr = App.recent[i]; if (!tr) return; const d = await post('recentRemove', { track: tr }); if (d) App.recent = d; renderView(); },
  favNow: async () => { const e = cur(); if (!e || !e.track) return; takeFavs(await post('fav', { track: e.track })); render(); },

  // playlists
  plOpen: (b) => { App.openPl = +b.dataset.pl; renderView(); },
  plBack: () => { App.openPl = null; renderView(); },
  plNew: async () => {
    const name = await askText(t('pl_name'));
    if (name) post('plCreate', { name }).then(plAfter);
  },
  plImport: () => {
    const v = ($('plLink') || {}).value || '';
    if (!v.trim()) return;
    App.playlists = 'loading'; renderView();
    post('plImport', { link: v.trim() }).then(d => { App.playlists = d || { mine: [], shared: [] }; renderView(); });
  },
  plPrompt: () => {
    const v = ($('plPrompt') || {}).value || '';
    if (!v.trim()) return;
    App.playlists = 'loading'; renderView();
    post('plPrompted', { prompt: v.trim() }).then(d => { App.playlists = d || { mine: [], shared: [] }; renderView(); });
  },
  plPlay: (b) => post('plPlay', { playlist: +b.dataset.pl, mode: 'now' }),
  plAddNow: (b) => { const e = cur(); if (e && e.track) post('plAdd', { playlist: +b.dataset.pl, track: e.track }).then(plAfter); },
  plShare: (b) => post('plShare', { playlist: +b.dataset.pl }).then(plAfter),
  plMixed: (b) => post('plMixed', { playlist: +b.dataset.pl }).then(plAfter),
  plDel: (b) => confirmBox(t('pl_del'), t('pl_del_s'), t('pl_del'), () => {
    post('plDelete', { playlist: +b.dataset.pl }).then(d => { App.openPl = null; plAfter(d); });
  }),
  plCollab: async (b) => {
    const people = await post('people');
    if (!people || !people.length) return toast(t('nobody'));
    pickPerson(people, t('k_collab'), p => post('plCollab', { playlist: +b.dataset.pl, target: p.src }).then(plAfter));
  },
  plTrack: (b, i) => {
    const d = App.playlists || {};
    const p = [...(d.mine || []), ...(d.shared || [])].find(x => x.id === App.openPl);
    const tr = p && p.tracks[i];
    if (tr) post('playSaved', { track: tr, mode: 'now' });
  },
  plTrackDel: (b, i) => post('plRemove', { playlist: +b.dataset.pl, index: i + 1 }).then(plAfter),
  blend: async () => {
    const people = await post('people');
    if (!people || !people.length) return toast(t('nobody'));
    pickPerson(people, t('k_blend'), p => post('plBlend', { target: p.src }).then(plAfter));
  },

  // records / turntable
  puton: (b, i) => { const r = App.records[i]; if (r) { post('vinylInsert', { item: r.item }); setTimeout(() => go('tracks'), 400); } },
  vtrack: (b, i) => post('queuePlay', { value: i + 1 }),

  // links
  link: (b) => { post('link', { other: b.dataset.id }); setTimeout(loadLinks, 500); },
  unlink: () => { post('unlink'); setTimeout(loadLinks, 500); },
  unlinkOne: () => { post('unlink'); setTimeout(loadLinks, 500); },

  // jam
  jamStart: async () => {
    const name = await askText(t('jam_name'));
    if (name === null) return;
    await post('jamCreate', { name });
    loadJams();
  },
  jamJoin: (b) => post('jamJoin', { id: +b.dataset.id }).then(() => loadJams()),
  jamLeave: () => post('jamLeave').then(() => loadJams()),

  // settings
  tog: (b) => {
    const k = b.dataset.s;
    const on = k === 'viz' ? !(App.settings.viz !== false) : !App.settings[k];
    App.settings[k] = on;
    Engine.setSettings(App.settings);
    applyAppearance();
    renderView();
    post('settings', { [k]: on });
  },
  togHud: () => {
    App.settings.hud = !(App.settings.hud !== false);
    if (!App.settings.hud) App.hudEdit = false;
    renderView(); refreshHud();
    post('settings', { hud: App.settings.hud });
  },
  hudMove: () => { App.hudEdit = !App.hudEdit; applyAppearance(); renderView(); refreshHud(); },
  hudReset: () => {
    Object.assign(App.settings, { hudX: NP.x, hudY: NP.y, hudScale: NP.scale });
    placeHud(); renderView();
    post('settings', { hudX: NP.x, hudY: NP.y, hudScale: NP.scale });
  },
  skin: (b) => { App.settings.skin = b.dataset.v; applyAppearance(); playAnim('in'); renderView(); post('settings', { skin: b.dataset.v }); },
  cover: (b) => { App.settings.cover = b.dataset.v; applyAppearance(); renderView(); post('settings', { cover: b.dataset.v }); },
  eqReset: () => {
    Object.assign(App.settings, { bass: 0, mid: 0, treble: 0 });
    Engine.setSettings(App.settings); renderView();
    post('settings', { bass: 0, mid: 0, treble: 0 });
  },
};

/* inline prompt (window.prompt is blocked inside NUI) */
function askText(label) {
  $('mTitle').textContent = label;
  $('mText').innerHTML = `<input class="modal-in" id="mInput" maxlength="60" placeholder="${esc(label)}">`;
  $('mOk').textContent = t('ok');
  App.confirmFn = null;
  $('scrim').hidden = false;
  setTimeout(() => { const i = $('mInput'); if (i) i.focus(); }, 30);
  return new Promise(res => { App.promptRes = res; });
}

function pickPerson(people, title, fn) {
  $('mTitle').textContent = title;
  $('mText').innerHTML = `<div class="people">${people.map(p => `<button class="chipb" data-person="${p.src}">${esc(p.name)}</button>`).join('')}</div>`;
  $('mOk').hidden = true;
  App.confirmFn = null;
  $('scrim').hidden = false;
  $('mText').querySelectorAll('[data-person]').forEach(b => {
    b.onclick = () => { $('scrim').hidden = true; $('mOk').hidden = false; fn(people.find(p => p.src == b.dataset.person)); };
  });
}
function toast(msg) {
  const sub = $('ctxSub'), prev = sub.dataset.prev ?? sub.textContent;
  sub.dataset.prev = prev; sub.textContent = msg;
  setTimeout(() => { sub.textContent = prev; delete sub.dataset.prev; }, 2200);
}

/* ─────────── ticker ─────────── */
const vizBuf = new Uint8Array(128);
function drawViz(id) {
  const cv = $('viz'), g = cv.getContext('2d');
  const W = cv.width, H = cv.height;
  g.clearRect(0, 0, W, H);
  const e = id && Engine.get(id);
  if (!e || !e.track || !App.settings.viz) return;
  const data = e.playing ? Engine.levels(id, vizBuf) : null;
  const bars = App.compact ? 24 : 48, gap = App.compact ? 3 : 4, bw = (W - gap * (bars - 1)) / bars;
  const tNow = performance.now() / 1000;
  for (let i = 0; i < bars; i++) {
    let v;
    if (data) {
      const lo = Math.floor(Math.pow(i / bars, 1.6) * 96), hi = Math.max(lo + 1, Math.floor(Math.pow((i + 1) / bars, 1.6) * 96));
      let sum = 0; for (let j = lo; j < hi; j++) sum += data[j];
      v = sum / (hi - lo) / 255;
    } else v = e.playing ? 0.12 + 0.1 * Math.sin(tNow * 3 + i * 0.5) : 0.06;
    const h = Math.max(3, v * H * 0.95);
    const x = i * (bw + gap);
    const grd = g.createLinearGradient(0, H, 0, H - h);
    grd.addColorStop(0, 'rgba(8,175,162,.95)');
    grd.addColorStop(1, 'rgba(15,212,196,.55)');
    g.fillStyle = grd;
    g.fillRect(x, H - h, bw, h);
  }
}

function tick() {
  if (App.open) {
    const e = cur();
    if (e && e.track) {
      const dur = e.track.duration || 0;
      const pos = App.dragSeek != null ? App.dragSeek : Math.min(Engine.expected(e), dur || Infinity);
      const pct = dur > 0 ? Math.min(100, (pos / dur) * 100) : 0;
      $('seekFill').style.width = pct + '%';
      $('seekKnob').style.left = pct + '%';
      $('tPos').textContent = fmt(pos);
      $('tDur').textContent = dur > 0 ? fmt(dur) : '--:--';
    } else {
      $('seekFill').style.width = '0%'; $('seekKnob').style.left = '0%';
      $('tPos').textContent = '0:00'; $('tDur').textContent = '0:00';
    }
    drawViz(App.id);
  }
  if (App.hud) drawHud();
  requestAnimationFrame(tick);
}

/* ─────────── now playing card ─────────── */
const NP = { enabled: true, nearby: true, minLevel: 0.08, x: 98.5, y: 3, scale: 1 };

function pickHud() {
  if (App.hudEdit) return 'preview';
  if (!NP.enabled || App.settings.hud === false) return null;
  const list = Engine.audible();
  const own = list.find(x => (x.kind === 'vehicle' || x.kind === 'jam') && x.dist === 0);
  if (own) return own.id;
  if (!NP.nearby) return null;
  const best = list.find(x => x.level >= NP.minLevel);
  return best ? best.id : null;
}

function placeHud() {
  const w = $('npWrap'), st = App.settings;
  const x = st.hudX ?? NP.x, y = st.hudY ?? NP.y, sc = st.hudScale ?? NP.scale;
  w.style.left = x + '%';
  w.style.top = y + '%';
  w.style.transform = `translateX(-100%) scale(${sc})`;
}

function refreshHud() {
  const id = pickHud();
  const changed = id !== App.hud;
  const wrap = $('npWrap');
  if (!id) {
    if (App.hud && !wrap.hidden) {
      playAnim('out');
      const tok = ++App.hudTok;
      setTimeout(() => { if (tok === App.hudTok) wrap.hidden = true; }, 300);
    }
    App.hud = null;
    return;
  }
  App.hud = id;
  if (changed || wrap.hidden) {
    wrap.hidden = false;
    App.hudTok = (App.hudTok || 0) + 1;
    applyAppearance();
    playAnim('in');
  }
  renderHud();
}
setInterval(refreshHud, 300);

function renderHud() {
  const np = $('np'), wrap = $('npWrap'), img = $('npImg');
  if (App.hud === 'preview') {
    wrap.hidden = false;
    const e = App.id && Engine.get(App.id);
    const tr = e && e.track;
    $('npTitle').textContent = tr && !hide() ? tr.title : t('np_preview');
    $('npAuthor').textContent = tr && !hide() ? tr.author || '' : t('np_preview_s');
    img.hidden = !(tr && tr.thumb && !hide());
    if (!img.hidden && img.dataset.src !== tr.thumb) { img.dataset.src = tr.thumb; img.src = tr.thumb; }
    np.classList.remove('muted');
    np.classList.add('np-spin');
    return;
  }
  const e = App.hud && Engine.get(App.hud);
  if (!e || !e.track) { wrap.hidden = true; return; }
  const hidden = hide();
  $('npTitle').textContent = hidden ? t('streamer') : e.track.title;
  $('npAuthor').textContent = hidden ? t('muted_stream') : e.track.author || '';
  const thumb = !hidden && e.track.thumb ? e.track.thumb : null;
  if (thumb) { if (img.dataset.src !== thumb) { img.dataset.src = thumb; img.src = thumb; } img.hidden = false; }
  else img.hidden = true;
  $('npBlur').style.backgroundImage = thumb ? `url("${thumb}")` : 'none';
  np.classList.toggle('muted', hidden || !e.playing);
  np.classList.toggle('np-spin', !!e.playing && !hidden);
}

const hudBuf = new Uint8Array(128);
function drawHud() {
  if (App.hud === 'preview') {
    const bars = $('npEq').children, tt = performance.now() / 180;
    for (let i = 0; i < 4; i++) bars[i].style.height = Math.max(12, (0.35 + 0.3 * Math.sin(tt + i * 1.7)) * 100) + '%';
    $('npFill').style.width = '40%';
    return;
  }
  const e = Engine.get(App.hud);
  if (!e || !e.track) return;
  const dur = e.track.duration || 0;
  $('npFill').style.width = dur > 0 ? Math.min(100, Engine.expected(e) / dur * 100) + '%' : '0%';
  const d = e.playing ? Engine.levels(App.hud, hudBuf) : null;
  const bars = $('npEq').children, tt = performance.now() / 180;
  for (let i = 0; i < 4; i++) {
    const v = d ? d[2 + i * 9] / 255 : (e.playing && !hide() ? 0.35 + 0.3 * Math.sin(tt + i * 1.7) : 0.15);
    bars[i].style.height = Math.max(12, v * 100) + '%';
  }
}

function bindHudDrag() {
  const np = $('npWrap');
  np.addEventListener('mousedown', ev => {
    if (!App.hudEdit) return;
    ev.preventDefault();
    const r = np.getBoundingClientRect();
    const offX = r.right - ev.clientX, offY = ev.clientY - r.top;
    np.classList.add('drag');
    const mv = e2 => {
      const right = Math.min(window.innerWidth, Math.max(r.width, e2.clientX + offX));
      const top = Math.min(window.innerHeight - r.height, Math.max(0, e2.clientY - offY));
      App.settings.hudX = +(right / window.innerWidth * 100).toFixed(2);
      App.settings.hudY = +(top / window.innerHeight * 100).toFixed(2);
      placeHud();
    };
    const up = () => {
      document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up);
      np.classList.remove('drag');
      post('settings', { hudX: App.settings.hudX, hudY: App.settings.hudY });
    };
    document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
  });
}

/* ─────────── hints ─────────── */
function showHints(list) {
  const h = $('hints');
  if (!list) { h.hidden = true; return; }
  h.innerHTML = list.map(x => `<div><span class="key">${esc(x.key)}</span>${esc(x.label)}</div>`).join('');
  h.hidden = false;
}

/* ─────────── wiring ─────────── */
function bind() {
  // one dispatcher for the whole window
  document.addEventListener('click', ev => {
    const b = ev.target.closest('[data-a]');
    if (!b || b.disabled) return;
    const fn = ACTIONS[b.dataset.a];
    if (fn) fn(b, +b.dataset.i);
  });

  $('closeBtn').onclick = () => closeUI(true);
  $('sizeBtn').onclick = () => {
    App.compact = !App.compact;
    applyCompact();
    post('settings', { compact: App.compact });
    render();
  };
  $('mCancel').onclick = () => {
    $('scrim').hidden = true; $('mOk').hidden = false;
    if (App.promptRes) { const r = App.promptRes; App.promptRes = null; r(null); }
  };
  $('mOk').onclick = () => {
    const input = $('mInput');
    $('scrim').hidden = true;
    if (input && App.promptRes) { const r = App.promptRes; App.promptRes = null; r(input.value.trim() || null); return; }
    if (App.confirmFn) App.confirmFn();
  };

  $('urlIn').onkeydown = ev => { if (ev.key === 'Enter') submit(ev.shiftKey ? 'queue' : 'now'); };
  $('mText').addEventListener('keydown', ev => { if (ev.key === 'Enter' && ev.target.id === 'mInput') $('mOk').click(); });

  const vol = $('volSlider'), rng = $('rangeSlider');
  vol.oninput = () => { paintRange(vol); $('volVal').textContent = vol.value + '%'; };
  vol.onchange = () => { post('volume', { value: vol.value / 100 }); vol.blur(); };
  rng.oninput = () => { paintRange(rng); $('rangeVal').textContent = rng.value + ' m'; };
  rng.onchange = () => { post('range', { value: +rng.value }); rng.blur(); };

  const bar = $('seekBar');
  const posAt = ev => {
    const r = bar.getBoundingClientRect();
    const e = cur(); const dur = e && e.track ? e.track.duration : 0;
    return Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width)) * dur;
  };
  bar.onmousedown = ev => {
    bar.classList.add('drag');
    App.dragSeek = posAt(ev);
    const mv = e2 => { App.dragSeek = posAt(e2); };
    const up = e2 => {
      document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up);
      bar.classList.remove('drag');
      post('seek', { value: posAt(e2) });
      setTimeout(() => { App.dragSeek = null; }, 250);
    };
    document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
  };

  $('list').addEventListener('change', ev => {
    const k = ev.target.dataset.s;
    if (!k) return;
    if (k === 'master') post('settings', { master: ev.target.value / 100 });
    else if (k === 'hudScale') post('settings', { hudScale: ev.target.value / 100 });
    else if (['font', 'animIn', 'animOut'].includes(k)) {
      App.settings[k] = ev.target.value;
      applyAppearance();
      if (k !== 'font') playAnim(k === 'animIn' ? 'in' : 'out');
      post('settings', { [k]: ev.target.value });
    } else if (['bass', 'mid', 'treble'].includes(k)) post('settings', { [k]: +ev.target.value });
    if (ev.target.type === 'range') ev.target.blur();
  });

  $('list').addEventListener('input', ev => {
    const k = ev.target.dataset.s;
    if (k === 'master') { paintRange(ev.target); Engine.setSettings({ master: ev.target.value / 100 }); }
    if (k === 'hudScale') {
      paintRange(ev.target);
      App.settings.hudScale = ev.target.value / 100;
      const o = $('npScaleVal'); if (o) o.textContent = ev.target.value + '%';
      placeHud();
    }
    if (['bass', 'mid', 'treble'].includes(k)) {
      paintRange(ev.target);
      const v = +ev.target.value;
      App.settings[k] = v;
      const out = $('eqv-' + k); if (out) out.textContent = (v > 0 ? '+' : '') + v + ' dB';
      Engine.setSettings(App.settings);
    }
  });

  $('list').addEventListener('keydown', ev => {
    if (ev.key !== 'Enter') return;
    if (ev.target.id === 'plLink') ACTIONS.plImport();
    if (ev.target.id === 'plPrompt') ACTIONS.plPrompt();
  });

  document.addEventListener('keydown', ev => {
    if (!App.open) return;
    if (ev.key === 'Escape') {
      if (!$('scrim').hidden) { $('scrim').hidden = true; $('mOk').hidden = false; return; }
      closeUI(true);
    }
  });
}

/* ─────────── messages from Lua ─────────── */
window.addEventListener('message', ({ data: m }) => {
  if (!m || !m.action) return;
  switch (m.action) {
    case 'init':
      App.L = m.locale || {}; App.version = m.version || '';
      App.streamerAllowed = m.streamerAllowed !== false;
      if (m.nowPlaying) Object.assign(NP, m.nowPlaying);
      if (m.brand) App.brand = m.brand;
      Engine.setConfig(m.audio);
      applyLocale(); applyBrand();
      break;
    case 'settings':
      App.settings = Object.assign(App.settings, m.data);
      Engine.setSettings(App.settings);
      applyAppearance();
      if (App.open) render();
      renderHud();
      break;
    case 'clock': Engine.setClock(m.server); break;
    case 'reset': Engine.reset(m.list || []); render(); renderHud(); break;
    case 'emitter':
      Engine.setEmitter(m.data);
      if (App.open && m.data.id === App.id) render();
      if (App.hud === m.data.id) renderHud();
      break;
    case 'remove':
      Engine.removeEmitter(m.id);
      if (App.id === m.id) closeUI(false);
      if (App.hud === m.id) refreshHud();
      break;
    case 'spatial': Engine.spatial(m.list || []); break;
    case 'open': openUI(m.id, m.compact); break;
    case 'close': closeUI(false); break;
    case 'lists':
      takeFavs(m.favs);
      if (Array.isArray(m.recent)) App.recent = m.recent;
      render();
      break;
    case 'loading':
      App.loadingId = m.on ? m.id : null;
      if (App.open) render();
      break;
    case 'jam': App.jam = m.data || null; if (App.view === 'jam') renderView(); break;
    case 'hints': showHints(m.list); break;
  }
});

bind();
bindHudDrag();
requestAnimationFrame(tick);
post('ready');
