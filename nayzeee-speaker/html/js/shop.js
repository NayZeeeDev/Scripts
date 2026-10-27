/* ═══════════════════════════════════════════════════════════
   Record shop — over the counter
   3D: the game draws the sleeves; this page is the label, chips, buttons and hints on top.
   2D: no props in stream/ (or display = '2d'): the records are drawn here as cover cards.
   Builds its own DOM (#nzShop) and only listens while it is open, so it never touches the player UI.
   Shares post() (engine.js) and esc() (app.js) with the player page, which loads them first.
   ═══════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  const money = n => '$' + Math.max(0, Math.round(n || 0)).toLocaleString('en-US');
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  // covers go into url('...') and src="...": keep only http(s) links and encode anything that could break out
  const safeUrl = u => (typeof u === 'string' && /^https?:\/\//i.test(u)
    ? u.replace(/["'()\\\s<>]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0')) : '');

  const ICON = {
    left: '<path d="M15 6l-6 6 6 6"/>',
    right: '<path d="M9 6l6 6-6 6"/>',
    bag: '<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><path d="M3 6h18M16 10a4 4 0 0 1-8 0"/>',
    head: '<path d="M3 18v-6a9 9 0 0 1 18 0v6"/><path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z"/>',
    stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    mute: '<path d="M11 5 6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6"/>',
  };
  const ic = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${ICON[name]}</svg>`;
  const key = k => `<span class="nzs-key">${k}</span>`;

  /* ─────────── DOM ─────────── */
  const root = document.createElement('div');
  root.id = 'nzShop';
  root.hidden = true;
  root.innerHTML = `
    <div class="nzs-veil"></div>
    <div class="nzs-stage"><div class="nzs-glow"></div><div class="nzs-cards"></div></div>
    <div class="nzs-spin"></div>
    <header class="nzs-top">
      <div class="nzs-brand"><span class="nzs-mark"></span><b class="nzs-title"></b></div>
      <div class="nzs-chips"></div>
    </header>
    <div class="nzs-corner">
      <div class="nzs-wallet"><span class="nzs-acct"></span><b class="nzs-cash"></b></div>
      <button class="nzs-leave" type="button"></button>
    </div>
    <div class="nzs-label">
      <div class="nzs-genre"></div>
      <div class="nzs-name"></div>
      <div class="nzs-by"></div>
      <div class="nzs-price"></div>
      <div class="nzs-desc"></div>
      <div class="nzs-now"><i></i><i></i><i></i><span></span></div>
    </div>
    <button class="nzs-arrow nzs-l" type="button">${ic('left')}</button>
    <button class="nzs-arrow nzs-r" type="button">${ic('right')}</button>
    <div class="nzs-toast"><div><b></b><span></span></div></div>
    <footer class="nzs-bottom">
      <div class="nzs-actions">
        <button class="nzs-btn nzs-listen" type="button"></button>
        <button class="nzs-btn nzs-buy" type="button"></button>
      </div>
      <div class="nzs-dots"></div>
      <div class="nzs-meta"></div>
    </footer>`;
  document.body.appendChild(root);
  const $ = sel => root.querySelector(sel);
  const el = {
    title: $('.nzs-title'), mark: $('.nzs-mark'), chips: $('.nzs-chips'), acct: $('.nzs-acct'), cash: $('.nzs-cash'),
    leave: $('.nzs-leave'), label: $('.nzs-label'), genre: $('.nzs-genre'), name: $('.nzs-name'), by: $('.nzs-by'),
    price: $('.nzs-price'), desc: $('.nzs-desc'), now: $('.nzs-now'), nowTxt: $('.nzs-now span'),
    prev: $('.nzs-arrow.nzs-l'), next: $('.nzs-arrow.nzs-r'), toast: $('.nzs-toast'), listen: $('.nzs-btn.nzs-listen'),
    buy: $('.nzs-btn.nzs-buy'), dots: $('.nzs-dots'), meta: $('.nzs-meta'), spin: $('.nzs-spin'), cards: $('.nzs-cards'),
    top: $('.nzs-top'),
  };

  /* ─────────── state ─────────── */
  let D = { items: [], genres: [], owned: {}, wallet: 0 };
  let T = {};
  let mode = '3d';
  let genre = 'all', query = '';
  let list = [], index = 0;
  let buying = false, buyTimer = null;
  let listen = { item: null, state: 'idle', length: 30, at: 0, title: '' };
  let anchor = null;                 // 3D label position from the game, 0..1
  const cards = new Map();           // 2D: item -> card element
  let lastStep = 0;

  const isOpen = () => !root.hidden;
  const cur = () => list[index] || null;
  const tx = (k, ...a) => { let s = T[k] ?? k; a.forEach(v => { s = s.replace('%s', () => v); }); return s; };
  const ownedN = item => +(D.owned && D.owned[item]) || 0;

  /* ─────────── list + filters ─────────── */
  function filtered() {
    const q = query.trim().toLowerCase();
    return D.items.filter(r => {
      if (genre === '@owned') { if (!ownedN(r.item)) return false; }
      else if (genre !== 'all' && r.genre !== genre) return false;
      if (q && !`${r.album} ${r.artist} ${r.genre || ''} ${r.year || ''}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }

  const wrap = o => list.length ? list[((index + o) % list.length + list.length) % list.length] : null;

  // what stands where: with two records only show the other one on one side
  function slots() {
    const n = list.length;
    return {
      prev: n > 2 || (n === 2 && index === 1) ? wrap(-1) : null,
      cur: wrap(0),
      next: n > 2 || (n === 2 && index === 0) ? wrap(1) : null,
    };
  }

  function sendView(dir) {
    const s = slots();
    const n = list.length;
    post('shopView', {
      prev: s.prev && s.prev.item, cur: s.cur && s.cur.item, next: s.next && s.next.item, dir: dir || 0,
      warm: n > 3 ? [wrap(-2).item, wrap(2).item] : [],
    });
    if (mode === '2d') layoutCards(dir || 0);
  }

  function go(dir) {
    const n = list.length;
    if (n < 2 || buying) return;
    const now = performance.now();
    if (now - lastStep < 140) return;
    lastStep = now;
    const old = index;
    index = (index + dir + n) % n;
    // two records: the motion follows where the other one actually is
    const d = n === 2 ? (index > old ? 1 : -1) : dir;
    sendView(d);
    renderItem(true);
  }

  function setFilter(fn) {
    const keep = cur() && cur().item;
    fn();
    list = filtered();
    const i = keep ? list.findIndex(r => r.item === keep) : -1;
    index = i >= 0 ? i : 0;
    renderChips();
    sendView(0);
    renderItem(true);
  }

  /* ─────────── chips ─────────── */
  function chip(label, on, onClick, extra) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'nzs-chip' + (on ? ' nzs-on' : '') + (extra ? ' ' + extra : '');
    b.innerHTML = label;
    b.onclick = onClick;
    return b;
  }

  let searchIn = null;
  function renderChips() {
    const box = el.chips;
    const focused = searchIn && document.activeElement === searchIn;
    box.innerHTML = '';
    box.appendChild(chip(esc(T.all), genre === 'all', () => setFilter(() => { genre = 'all'; })));
    (D.genres || []).forEach(g => box.appendChild(chip(esc(g), genre === g, () => setFilter(() => { genre = g; }))));
    const mine = D.items.filter(r => ownedN(r.item)).length;
    if (mine > 0 || genre === '@owned') {
      const sep = document.createElement('span'); sep.className = 'nzs-sep'; box.appendChild(sep);
      box.appendChild(chip(`${esc(T.owned)} <em>${mine}</em>`, genre === '@owned',
        () => setFilter(() => { genre = genre === '@owned' ? 'all' : '@owned'; }), 'nzs-own'));
    }
    const s = document.createElement('label');
    s.className = 'nzs-search' + (query ? ' nzs-filled' : '');
    s.innerHTML = `${ic('search')}<input type="text" spellcheck="false" autocomplete="off" maxlength="40">`;
    searchIn = s.querySelector('input');
    searchIn.placeholder = T.search;
    searchIn.value = query;
    searchIn.oninput = () => {
      query = searchIn.value;
      s.classList.toggle('nzs-filled', !!query);
      list = filtered();
      index = 0;
      sendView(0);
      renderItem(false);
    };
    box.appendChild(s);
    if (focused) { searchIn.focus(); searchIn.setSelectionRange(query.length, query.length); }
  }

  /* ─────────── the featured record ─────────── */
  let swapTimer = null;
  function fillLabel(r) {
    el.label.classList.toggle('nzs-empty', !r);
    if (!r) {
      el.genre.textContent = '';
      el.name.textContent = T.nothing;
      el.by.textContent = T.nothing_s;
      el.price.innerHTML = '';
      el.desc.textContent = '';
      return;
    }
    el.genre.textContent = r.genre || (r.year ? String(r.year) : '');
    el.name.textContent = r.album;
    const parts = [esc(r.artist)];
    if (r.year && r.genre) parts.push(esc(r.year));
    parts.push(esc(r.tracks === 1 ? T.track : tx('tracks', r.tracks)));
    el.by.innerHTML = parts.join('<i>·</i>');
    const n = ownedN(r.item);
    const tags = n ? `<span class="nzs-tag nzs-own">${esc(n > 1 ? tx('own_n', n) : T.own)}</span>` : '';
    el.price.innerHTML = `<em>${r.price > 0 ? money(r.price) : esc(T.free)}</em>${tags}`;
    el.desc.textContent = r.desc || '';
  }

  function renderItem(animate) {
    const r = cur();
    clearTimeout(swapTimer);
    if (animate) {
      el.label.classList.add('nzs-swap');
      swapTimer = setTimeout(() => { fillLabel(cur()); el.label.classList.remove('nzs-swap'); placeLabel(); }, 200);
    } else {
      fillLabel(r);
      placeLabel();
    }
    renderButtons();
    renderNow();

    const n = list.length;
    if (n > 1 && n <= 16) el.dots.innerHTML = list.map((_, i) => `<i class="${i === index ? 'nzs-on' : ''}"></i>`).join('');
    else el.dots.innerHTML = n > 16 ? `<span>${esc(tx('of', index + 1, n))}</span>` : '';
    el.prev.classList.toggle('nzs-off', n < 2);
    el.next.classList.toggle('nzs-off', n < 2);
  }

  function renderButtons() {
    const r = cur();
    const b = el.buy;
    const short = r && r.price > (D.wallet || 0);
    b.disabled = !r || buying || short;
    b.classList.toggle('nzs-busy', buying);
    if (!r) b.innerHTML = `${ic('bag')}<span>${esc(T.buy)}</span>`;
    else if (buying) b.innerHTML = `<i class="nzs-spinner"></i><span>${esc(T.buying)}</span>`;
    else b.innerHTML = `${ic('bag')}<span>${r.price > 0 ? `${esc(T.buy)} · ${money(r.price)}` : esc(T.take)}</span>${key('ENTER')}`;

    const l = el.listen;
    const mine = r && listen.item === r.item;
    const state = mine ? listen.state : 'idle';
    l.hidden = D.preview === false;
    l.disabled = !r || D.streamer;
    l.dataset.state = D.streamer ? 'muted' : state;
    if (D.streamer) l.innerHTML = `${ic('mute')}<span>${esc(T.muted)}</span>`;
    else if (state === 'loading') l.innerHTML = `<i class="nzs-spinner"></i><span>${esc(T.finding)}</span>${key('L')}`;
    else if (state === 'playing') {
      l.innerHTML = `<span class="nzs-eq"><i></i><i></i><i></i><i></i></span><span>${esc(T.stop)}</span>${key('L')}<b class="nzs-prog"></b>`;
      const bar = l.querySelector('.nzs-prog');
      const done = clamp((performance.now() - listen.at) / (listen.length * 1000), 0, 1);
      bar.style.transition = 'none';
      bar.style.transform = `scaleX(${done})`;
      requestAnimationFrame(() => requestAnimationFrame(() => {
        bar.style.transition = `transform ${Math.max(0, listen.length * (1 - done))}s linear`;
        bar.style.transform = 'scaleX(1)';
      }));
    } else l.innerHTML = `${ic('head')}<span>${esc(T.listen)}</span>${key('L')}`;
  }

  function renderNow() {
    const r = cur();
    const on = !!(r && listen.item === r.item && listen.state === 'playing' && listen.title);
    el.now.classList.toggle('nzs-on', on);
    el.nowTxt.textContent = on ? `${T.preview}  ${listen.title}` : '';
  }

  function renderMeta() {
    const spin = mode === '2d' ? T.flip : T.spin;
    el.meta.innerHTML = [
      `<span>${key('A')}${key('D')}${esc(T.browse)}</span>`,
      `<span>${esc(spin)}</span>`,
      D.preview === false || D.streamer ? '' : `<span>${key('L')}${esc(T.hint_listen)}</span>`,
      `<span>${key('ENTER')}${esc(T.hint_buy)}</span>`,
      `<span>${key('ESC')}${esc(T.hint_leave)}</span>`,
    ].join('');
  }

  /* label: above the featured sleeve (3D: where the game says it is) */
  function placeLabel() {
    const lab = el.label;
    if (mode === '2d') { lab.style.left = ''; lab.style.top = ''; return; }
    if (!anchor) { lab.style.left = '50%'; lab.style.top = '30%'; return; }
    const w = innerWidth, h = innerHeight;
    const half = Math.min(lab.offsetWidth / 2 + 24, w / 2);
    const minY = el.top.getBoundingClientRect().bottom + 14 + lab.offsetHeight;
    lab.style.left = clamp(anchor.x * w, half, w - half) + 'px';
    lab.style.top = clamp(anchor.y * h, minY, h * 0.62) + 'px';
  }

  /* ─────────── 2D cards ─────────── */
  function hue(s) { let h = 0; for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) % 360; return h; }

  function art(r) {
    const url = safeUrl(r.cover);
    if (url) return `<img src="${esc(url)}" alt="" draggable="false">`;
    return `<div class="nzs-gen" style="--h:${hue(r.album + r.artist)}"><i class="nzs-mark"></i><b>${esc(r.album)}</b><span>${esc(r.artist)}</span></div>`;
  }

  function makeCard(r) {
    const c = document.createElement('div');
    c.className = 'nzs-card';
    c.dataset.item = r.item;
    const url = safeUrl(r.cover);
    c.innerHTML = `
      <div class="nzs-tilt">
        <div class="nzs-disc"><div class="nzs-vinyl"><div class="nzs-lbl"${url ? ` style="background-image:url('${esc(url)}')"` : ''}></div></div><i class="nzs-sheen"></i></div>
        <div class="nzs-sleeve">${art(r)}<i class="nzs-ring"></i><i class="nzs-gloss"></i><span class="nzs-sticker"></span></div>
        <div class="nzs-back" style="--h:${hue(r.album + r.artist)}">
          <header><i class="nzs-mark"></i><div><b>${esc(r.album)}</b><span>${esc(r.artist)}</span></div></header>
          <ol>${(Array.isArray(r.titles) ? r.titles : []).map(t => `<li>${esc(t)}</li>`).join('')}</ol>
          <footer><span>${esc([r.year, r.tracks === 1 ? T.track : tx('tracks', r.tracks)].filter(Boolean).join(' · '))}</span><i></i></footer>
        </div>
      </div>`;
    stickerOf(c, r.item);
    return c;
  }

  function stickerOf(c, item) {
    const s = c.querySelector('.nzs-sticker');
    const n = ownedN(item);
    s.textContent = n ? (n > 1 ? tx('own_n', n) : T.own) : '';
    s.classList.toggle('nzs-on', !!n);
  }

  function leaveCard(c, dir) {
    const o = +c.dataset.o || 0;
    c.dataset.o = String(clamp(o - dir, -2, 2));
    c.classList.add('nzs-gone');
    c.dataset.leaving = '1';
    setTimeout(() => { if (c.dataset.leaving) c.remove(); }, 520);
  }

  function layoutCards(dir) {
    const s = slots();
    const want = new Map();
    if (s.cur) want.set(s.cur.item, 0);
    if (s.prev) want.set(s.prev.item, -1);
    if (s.next) want.set(s.next.item, 1);
    for (const [item, c] of [...cards]) {
      const o = +c.dataset.o, w = want.get(item);
      if (w === undefined || w !== o - dir) { leaveCard(c, dir); cards.delete(item); }
    }
    for (const [item, o] of want) {
      let c = cards.get(item);
      if (!c) {
        const r = D.items.find(x => x.item === item);
        if (!r) continue;
        c = makeCard(r);
        c.dataset.o = String(dir ? clamp(o + dir, -2, 2) : o);
        c.classList.add(dir ? 'nzs-gone' : 'nzs-rise');
        el.cards.appendChild(c);
        void c.offsetWidth;                // start from there, then glide in
        cards.set(item, c);
      }
      c.classList.remove('nzs-gone', 'nzs-rise');
      c.dataset.o = String(o);
    }
  }

  function clearCards() {
    cards.clear();
    el.cards.innerHTML = '';
  }

  /* ─────────── actions ─────────── */
  function buy() {
    const r = cur();
    if (!r || buying || el.buy.disabled) return;
    buying = true;
    renderButtons();
    post('shopBuy', { item: r.item });
    clearTimeout(buyTimer);
    buyTimer = setTimeout(() => { if (buying) { buying = false; renderButtons(); } }, 8000);
  }

  function toggleListen() {
    const r = cur();
    if (!r || D.streamer || D.preview === false || el.listen.disabled) return;
    post('shopListen', { item: r.item });
  }

  let toastTimer = null;
  function toast(head, sub, bad) {
    const t = el.toast;
    t.querySelector('b').textContent = head;
    t.querySelector('span').textContent = sub || '';
    t.classList.toggle('nzs-bad', !!bad);
    t.classList.remove('nzs-show');
    void t.offsetWidth;
    t.classList.add('nzs-show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('nzs-show'), bad ? 2200 : 1700);
  }

  function close() {
    if (!isOpen()) return;
    hide();
    post('shopClose');
  }

  function hide() {
    root.hidden = true;
    document.body.classList.remove('nzs-shop-open');
    if (searchIn) searchIn.blur();
    clearCards();
    listen = { item: null, state: 'idle', length: 30, at: 0, title: '' };
  }

  el.prev.onclick = () => go(-1);
  el.next.onclick = () => go(1);
  el.buy.onclick = buy;
  el.listen.onclick = toggleListen;
  el.leave.onclick = close;

  /* drag to spin (3D: the game turns the sleeve; 2D: the card flips), wheel to browse */
  (function () {
    let drag = null, acc = 0, raf = 0, lastWheel = 0;
    const flush = () => { raf = 0; if (acc) { post('shopSpin', { delta: acc * 0.45 }); acc = 0; } };
    const featuredTilt = () => { const c = cur() && cards.get(cur().item); return c && c.querySelector('.nzs-tilt'); };

    function down(e) {
      if (e.button !== 0) return;
      const card = e.target.closest && e.target.closest('.nzs-card');
      if (mode === '2d' && card && card.dataset.o !== '0') {
        const o = +card.dataset.o;
        if (o) go(o > 0 ? 1 : -1);
        return;
      }
      drag = { x: e.clientX, moved: 0, deg: 0, tilt: mode === '2d' ? featuredTilt() : null };
      e.currentTarget.setPointerCapture(e.pointerId);
      e.currentTarget.classList.add('nzs-drag');
      if (drag.tilt) { drag.tilt.classList.add('nzs-held'); drag.tilt.style.transform = 'rotateY(0deg)'; }
    }
    function move(e) {
      if (!drag) return;
      const dx = e.clientX - drag.x;
      drag.x = e.clientX;
      drag.moved += Math.abs(dx);
      if (drag.tilt) {
        drag.deg = clamp(drag.deg + dx * 0.5, -180, 180);
        drag.tilt.style.transform = `rotateY(${drag.deg}deg)`;
      } else {
        acc += dx;
        if (!raf) raf = requestAnimationFrame(flush);
      }
    }
    function up(e) {
      if (!drag) return;
      e.currentTarget.classList.remove('nzs-drag');
      const t = drag.tilt;
      if (t) {
        t.style.transform = '';
        t.classList.remove('nzs-held');
        t.classList.add('nzs-return');
        setTimeout(() => t.classList.remove('nzs-return'), 600);
      }
      drag = null;
    }
    for (const layer of [el.spin, el.cards]) {
      layer.addEventListener('pointerdown', down);
      layer.addEventListener('pointermove', move);
      layer.addEventListener('pointerup', up);
      layer.addEventListener('pointercancel', up);
    }
    root.addEventListener('wheel', e => {
      if (e.target.closest('.nzs-chips')) return;
      e.preventDefault();
      const now = Date.now();
      if (now - lastWheel < 260) return;
      lastWheel = now;
      go(e.deltaY > 0 || e.deltaX > 0 ? 1 : -1);
    }, { passive: false });
  })();

  document.addEventListener('keydown', e => {
    if (!isOpen()) return;
    const k = e.key.toLowerCase();
    if (searchIn && document.activeElement === searchIn) {
      if (k === 'escape' || k === 'enter') { e.preventDefault(); searchIn.blur(); }
      return;
    }
    let used = true;
    if (k === 'escape' || k === 'backspace') close();
    else if (k === 'a' || k === 'arrowleft') go(-1);
    else if (k === 'd' || k === 'arrowright') go(1);
    else if (k === 'enter') buy();
    else if (k === 'l') { if (!e.repeat) toggleListen(); }
    else if (k === '/') { if (searchIn) searchIn.focus(); }
    else used = false;
    if (used) { e.preventDefault(); e.stopPropagation(); }
  }, true);

  addEventListener('resize', () => { if (isOpen()) placeLabel(); });

  function applyBrand(b) {
    el.mark.innerHTML = '';
    el.mark.classList.remove('nzs-img');
    if (!b || b.watermark === false || !b.logo) return;
    const img = new Image();
    img.onload = () => { el.mark.classList.add('nzs-img'); el.mark.appendChild(img); };
    img.src = b.logo;
  }

  /* ─────────── messages from Lua ─────────── */
  addEventListener('message', ({ data: m }) => {
    if (!m || typeof m.action !== 'string' || !m.action.startsWith('shop:')) return;
    const d = m.data || {};
    switch (m.action) {
      case 'shop:ping': post('shopReady'); break;
      case 'shop:open':
        D = Object.assign({ items: [], genres: [], owned: {}, wallet: 0 }, d);
        D.items = Array.isArray(D.items) ? D.items : [];
        D.genres = Array.isArray(D.genres) ? D.genres : [];
        if (!D.owned || Array.isArray(D.owned)) D.owned = {};
        T = d.text || {};
        mode = d.mode === '2d' ? '2d' : '3d';
        genre = 'all'; query = ''; index = 0; buying = false; anchor = null;
        listen = { item: null, state: 'idle', length: d.previewLength || 30, at: 0, title: '' };
        root.className = 'nzs-' + mode;
        el.title.textContent = d.title || T.title;
        el.acct.textContent = d.account === 'bank' ? T.bank : T.cash;
        el.cash.textContent = money(D.wallet);
        el.leave.textContent = T.leave;
        applyBrand(d.brand);
        clearCards();
        list = filtered();
        renderChips();
        renderMeta();
        root.hidden = false;
        document.body.classList.add('nzs-shop-open');
        renderItem(false);
        sendView(0);
        break;
      case 'shop:label':
        anchor = { x: +d.x || 0.5, y: +d.y || 0.3 };
        placeLabel();
        break;
      case 'shop:covers':
        for (const r of D.items) if (d[r.item]) r.cover = d[r.item];
        for (const [item, c] of cards) {
          if (!d[item]) continue;
          const url = safeUrl(d[item]);
          const sl = c.querySelector('.nzs-sleeve');
          if (url && !sl.querySelector('img')) {
            sl.querySelector('.nzs-gen')?.remove();
            sl.insertAdjacentHTML('afterbegin', `<img src="${esc(url)}" alt="" draggable="false">`);
            c.querySelector('.nzs-lbl').style.backgroundImage = `url('${url}')`;
          }
        }
        break;
      case 'shop:preview':
        if (d.state === 'idle') {
          if (d.error && (!d.item || (cur() && cur().item === d.item))) toast(T.nope, d.error, true);
          listen = { item: null, state: 'idle', length: listen.length, at: 0, title: '' };
        } else {
          listen = { item: d.item, state: d.state, length: d.length || listen.length,
            at: d.state === 'playing' ? performance.now() : 0, title: d.title || '' };
        }
        renderButtons();
        renderNow();
        break;
      case 'shop:result': {
        buying = false;
        clearTimeout(buyTimer);
        if (d.wallet != null) { D.wallet = d.wallet; el.cash.textContent = money(d.wallet); }
        if (d.owned && !Array.isArray(d.owned)) D.owned = d.owned;
        const r = D.items.find(x => x.item === d.item);
        if (d.ok) {
          toast(T.yours, r ? `${r.album} · ${r.artist}` : '');
          const c = r && cards.get(r.item);
          if (c) {
            stickerOf(c, r.item);
            const t = c.querySelector('.nzs-tilt');
            t.classList.remove('nzs-flip'); void t.offsetWidth; t.classList.add('nzs-flip');
          }
        } else toast(T.nope, d.reason, true);
        renderChips();
        fillLabel(cur());
        renderButtons();
        break;
      }
      case 'shop:close': if (isOpen()) hide(); break;
    }
  });

  post('shopReady');
})();
