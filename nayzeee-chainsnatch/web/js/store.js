/* ═══════════════════════════════════════════════════════════
   CHAIN SNATCH · Jewelry store
   The backpack shop, over the counter: brand + chips up top, wallet
   in the corner, the name and price floating above the chain, round
   arrows either side, pills along the bottom. Exclusive chains get
   the gold "made for" tag above their name.
   ═══════════════════════════════════════════════════════════ */
'use strict';

(function () {
  const el = $('#store');
  const money = (n) => '$' + Math.floor(n || 0).toLocaleString('en-US');
  const ic = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">${d}</svg>`;
  const BAG = ic('<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><path d="M3 6h18M16 10a4 4 0 0 1-8 0"/>');
  const PERSON = ic('<circle cx="12" cy="7" r="4"/><path d="M5 21v-1a7 7 0 0 1 14 0v1"/>');
  const COUNTER = ic('<path d="M3 9l2-5h14l2 5M3 9v10a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V9M3 9h18"/>');

  let D = null;
  let tab = 'buy', index = 0, mode = 'counter', busy = false;
  let list = [];
  const chosen = {}; // key -> texture letter

  el.innerHTML = `
    <div class="veil"></div>
    <div class="st-spin" id="stSpin"></div>
    <div class="s-top">
      <div class="s-brand"><div class="mark"></div><b id="stTitle">Jewelry Store</b></div>
      <div class="s-chips" id="stTabs"></div>
    </div>
    <div class="s-corner">
      <div class="s-wallet"><span id="stCur">Cash</span> <b id="stWallet">$0</b></div>
      <button class="pill-close" id="stClose">Leave</button>
    </div>
    <div class="s-label" id="stLabel">
      <div id="stExcl"></div>
      <div class="l-theme" id="stTheme"></div>
      <div class="l-name" id="stName"></div>
      <div class="l-price" id="stPrice"></div>
      <div class="l-tags" id="stTags"></div>
    </div>
    <button class="s-arrow l" id="stPrev">${ic('<path d="M15 6l-6 6 6 6"/>')}</button>
    <button class="s-arrow r" id="stNext">${ic('<path d="M9 6l6 6-6 6"/>')}</button>
    <div class="s-toast" id="stToast"></div>
    <div class="s-bottom">
      <div class="s-repairs hide" id="stRepairs"></div>
      <div class="s-swatches" id="stSwatches"></div>
      <div class="s-actions" id="stActions">
        <button class="s-btn" id="stTry"></button>
        <button class="s-btn buy" id="stBuy"></button>
      </div>
      <div class="s-work hide" id="stWork"><i></i></div>
      <div class="s-dots" id="stDots"></div>
      <div class="s-meta" id="stMeta"></div>
    </div>`;
  el.hidden = true;

  const q = (id) => document.getElementById(id);
  const cur = () => list[index] || null;
  const letterOf = (it) => (it ? chosen[it.key] || (arr(it.variants)[0] || {}).letter : null);
  const entry = (it) => (it ? { key: it.key, letter: letterOf(it) } : null);

  function filtered() {
    const items = arr(D && D.items);
    return tab === 'craft' ? items.filter((i) => i.recipe) : items;
  }

  /* ---------- tell Lua what should be on the counter ---------- */
  function sendView(dir) {
    const n = list.length;
    const at = (o) => (n === 0 ? null : list[((index + o) % n + n) % n]);
    const prev = n > 2 ? at(-1) : (n === 2 && index === 1 ? at(-1) : null);
    const next = n > 2 ? at(1) : (n === 2 && index === 0 ? at(1) : null);
    post('store:view', { prev: entry(prev), cur: entry(at(0)), next: entry(next), dir: dir || 0 });
  }

  function go(dir) {
    if (list.length < 2 || busy || tab === 'repair') return;
    index = (index + dir + list.length) % list.length;
    sendView(list.length > 2 ? dir : 0);
    renderItem(true);
  }

  /* ---------- the chips up top: Buy · Craft · Repair ---------- */
  function renderTabs() {
    const repairs = arr(D.repairs).length;
    const tabs = [['buy', 'Buy'], ...(D.craft ? [['craft', 'Craft']] : []), ['repair', repairs ? `Repair (${repairs})` : 'Repair']];
    q('stTabs').innerHTML = tabs.map(([k, l]) => `<button class="s-chip ${tab === k ? 'on' : ''}" data-tab="${k}" ${busy ? 'disabled' : ''}>${l}</button>`).join('');
  }

  function setTab(t) {
    if (busy || t === tab) return;
    tab = t;
    if (mode === 'tryon') post('store:mode', { mode: 'counter' });
    list = filtered();
    index = 0;
    renderTabs();
    sendView(0);
    renderItem(true);
  }

  /* ---------- the featured chain ---------- */
  let swapTimer = null;
  function renderItem(animate) {
    const it = cur();
    const repairing = tab === 'repair';
    const letter = letterOf(it);
    const v = it && arr(it.variants).find((x) => x.letter === letter);

    const fill = () => {
      q('stExcl').innerHTML = it && it.exclusive && !repairing
        ? `<span class="st-excl">${icon('user')}Made for ${esc(it.madeFor || 'you')}</span>` : '';
      if (repairing) {
        q('stTheme').textContent = 'Repairs';
        q('stName').textContent = arr(D.repairs).length ? 'Broken chains' : 'Nothing to repair';
        q('stPrice').innerHTML = '<span style="opacity:.6;font-size:13px">Chains that snapped in a snatch</span>';
        q('stTags').innerHTML = '';
        return;
      }
      if (!it) {
        q('stTheme').textContent = '';
        q('stName').textContent = 'Nothing here';
        q('stPrice').innerHTML = `<span style="opacity:.6;font-size:13px">${tab === 'craft' ? 'Nothing can be crafted' : 'Nothing for sale'}</span>`;
        q('stTags').innerHTML = '';
        return;
      }
      q('stTheme').textContent = it.exclusive ? 'Exclusive' : (v && v.label) || 'Jewellery';
      q('stName').textContent = it.label;
      if (tab === 'craft') {
        q('stPrice').innerHTML = '<em>Crafted</em> from materials';
        q('stTags').innerHTML = arr(it.recipe).map((m) => `<span class="${m.have >= m.count ? 'own' : 'no'}">${esc(m.label)} ${m.have}/${m.count}</span>`).join('');
      } else {
        q('stPrice').innerHTML = `<em>${money(it.price)}</em>`;
        q('stTags').innerHTML = [
          arr(it.variants).length > 1 ? `<span>${arr(it.variants).length} finishes</span>` : '',
          it.recipe ? '<span>craftable</span>' : '',
        ].join('');
      }
    };

    clearTimeout(swapTimer);
    if (animate) {
      q('stLabel').classList.add('swap');
      swapTimer = setTimeout(() => { fill(); q('stLabel').classList.remove('swap'); }, 200);
    } else {
      fill();
    }

    // repairs list
    const rp = q('stRepairs');
    rp.classList.toggle('hide', !repairing);
    rp.innerHTML = repairing ? arr(D.repairs).map((r) => `<div class="s-repair">
        <span class="th">${chainImg(r.image, 'gem')}</span>
        <div><b>${esc(r.label)}</b><small>broken</small></div>
        <button class="s-btn buy sm" data-repair="${r.slot}" ${busy || (D.wallet && D.wallet.amount < r.price) ? 'disabled' : ''}>Repair · ${money(r.price)}</button>
      </div>`).join('') : '';

    // textures
    const sw = q('stSwatches');
    sw.innerHTML = !repairing && it && arr(it.variants).length > 1
      ? arr(it.variants).map((x) => `<button class="${x.letter === letter ? 'on' : ''}" data-letter="${x.letter}">${esc(x.label || 'Finish ' + x.letter.toUpperCase())}</button>`).join('')
      : '';

    // try on + buy / craft
    q('stActions').classList.toggle('hide', repairing);
    const buy = q('stBuy');
    if (tab === 'craft') {
      const ready = it && arr(it.recipe).every((m) => m.have >= m.count);
      buy.innerHTML = `${ic('<path d="M4 20 15 9"/><path d="M15 4v2M19 8h2M18 5l1.5-1.5"/>')}${ready ? 'Craft it' : 'Missing materials'} <span class="key">ENTER</span>`;
      buy.disabled = !it || !ready || busy;
    } else {
      buy.innerHTML = it ? `${BAG}Buy · ${money(it.price)} <span class="key">ENTER</span>` : 'Nothing selected';
      buy.disabled = !it || busy || (D.wallet && it.price > D.wallet.amount);
    }
    q('stTry').innerHTML = mode === 'tryon' ? `${COUNTER}Back to counter <span class="key">T</span>` : `${PERSON}Try on <span class="key">T</span>`;
    q('stTry').classList.toggle('on', mode === 'tryon');

    // position dots
    const dots = q('stDots');
    if (repairing) dots.innerHTML = '';
    else if (list.length > 1 && list.length <= 16) dots.innerHTML = list.map((_, i) => `<i class="${i === index ? 'on' : ''}"></i>`).join('');
    else dots.innerHTML = list.length > 16 ? `<span style="font-size:10px;color:rgba(255,255,255,.6)">${index + 1} / ${list.length}</span>` : '';

    q('stMeta').innerHTML = repairing ? '<span><span class="key">ESC</span> leave</span>'
      : `<span><span class="key">A</span><span class="key">D</span> browse</span><span>drag to spin</span><span><span class="key">T</span> try on</span><span><span class="key">ESC</span> leave</span>`;

    q('stPrev').classList.toggle('hide', list.length < 2 || repairing);
    q('stNext').classList.toggle('hide', list.length < 2 || repairing);
  }

  /* ---------- actions ---------- */
  function buy() {
    const it = cur();
    if (!it || busy || q('stBuy').disabled || tab === 'repair') return;
    busy = true;
    renderItem(false);
    post(tab === 'craft' ? 'store:craft' : 'store:buy', { key: it.key, letter: letterOf(it) });
    setTimeout(() => { if (busy) { busy = false; renderTabs(); renderItem(false); } }, (tab === 'craft' ? 12000 : 4000));
  }

  function toggleTry() {
    if (!cur() || tab === 'repair') return;
    post('store:mode', { mode: mode === 'tryon' ? 'counter' : 'tryon' });
  }

  let toastTimer = null;
  function sToast(text, bad) {
    const t = q('stToast');
    t.textContent = text;
    t.classList.toggle('bad', !!bad);
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 1400);
  }

  function close() { post('store:close'); }

  q('stPrev').onclick = () => go(-1);
  q('stNext').onclick = () => go(1);
  q('stBuy').onclick = buy;
  q('stTry').onclick = toggleTry;
  q('stClose').onclick = close;
  el.addEventListener('click', (e) => {
    const t = e.target.closest('[data-tab]');
    if (t) return setTab(t.dataset.tab);
    const s = e.target.closest('[data-letter]');
    if (s) {
      const it = cur();
      chosen[it.key] = s.dataset.letter;
      post('store:variant', { key: it.key, letter: s.dataset.letter });
      return renderItem(false);
    }
    const r = e.target.closest('[data-repair]');
    if (r && !r.disabled && !busy) {
      busy = true;
      renderItem(false);
      post('store:repair', { slot: +r.dataset.repair });
      setTimeout(() => { if (busy) { busy = false; renderTabs(); renderItem(false); } }, 10000);
    }
  });

  /* drag to spin, wheel to browse */
  (function () {
    const c = q('stSpin');
    let drag = false, lx = 0, acc = 0, raf = null, lastWheel = 0;
    const flush = () => { raf = null; if (acc) { post('store:spin', { delta: acc * 0.45 }); acc = 0; } };
    c.addEventListener('pointerdown', (e) => { drag = true; lx = e.clientX; c.classList.add('drag'); c.setPointerCapture(e.pointerId); });
    c.addEventListener('pointerup', () => { drag = false; c.classList.remove('drag'); });
    c.addEventListener('pointermove', (e) => {
      if (!drag) return;
      acc += e.clientX - lx; lx = e.clientX;
      if (!raf) raf = requestAnimationFrame(flush);
    });
    c.addEventListener('wheel', (e) => {
      e.preventDefault();
      const now = Date.now();
      if (now - lastWheel < 280 || mode === 'tryon') return;
      lastWheel = now;
      go(e.deltaY > 0 ? 1 : -1);
    }, { passive: false });
  })();

  document.addEventListener('keydown', (e) => {
    if (!D || el.hidden) return;
    const k = e.key.toLowerCase();
    if (k === 'escape' || k === 'backspace') { e.preventDefault(); close(); }
    else if ((k === 'a' || k === 'arrowleft') && mode === 'counter') go(-1);
    else if ((k === 'd' || k === 'arrowright') && mode === 'counter') go(1);
    else if (k === 'enter') buy();
    else if (k === 't') toggleTry();
  });

  function setWallet(w) {
    if (!w) return;
    D.wallet = w;
    q('stCur').textContent = w.currency || 'Cash';
    q('stWallet').textContent = money(w.amount);
  }

  /* ---------- from Lua ---------- */
  H['store:open'] = (d) => {
    D = d;
    tab = 'buy'; index = 0; busy = false; mode = 'counter';
    q('stTitle').textContent = d.title || (d.text && d.text.store_title) || 'Jewelry Store';
    setWallet(d.wallet);
    list = filtered();
    el.classList.remove('tryon');
    renderTabs();
    renderItem(false);
    q('stLabel').style.left = '50%';
    q('stLabel').style.top = '34%';
    el.hidden = false;
    sendView(0);
  };
  H['store:label'] = (p) => {
    // never let the label ride up into the chips
    q('stLabel').style.left = Math.min(Math.max(p.x * innerWidth, 260), innerWidth - 260) + 'px';
    q('stLabel').style.top = Math.max(p.y * innerHeight, 210) + 'px';
  };
  H['store:mode'] = (d) => {
    mode = d.mode;
    el.classList.toggle('tryon', mode === 'tryon');
    renderItem(false);
  };
  H['store:working'] = (d) => {
    busy = true;
    const w = q('stWork');
    w.classList.remove('hide');
    w.firstElementChild.animate([{ width: '0%' }, { width: '100%' }], { duration: d.ms || 3000, easing: 'linear', fill: 'forwards' });
    renderTabs();
    renderItem(false);
  };
  H['store:result'] = (d) => {
    busy = false;
    q('stWork').classList.add('hide');
    if (d.items) {
      const key = cur() && cur().key;
      D.items = d.items;
      list = filtered();
      const i = list.findIndex((x) => x.key === key);
      index = i >= 0 ? i : Math.min(index, Math.max(0, list.length - 1));
    }
    if (d.repairs) D.repairs = d.repairs;
    setWallet(d.wallet);
    sToast(d.ok ? (tab === 'repair' ? 'Good as new' : 'Yours now') : 'Not this time', !d.ok);
    renderTabs();
    renderItem(false);
  };
  H['store:close'] = () => { el.hidden = true; D = null; };
})();
