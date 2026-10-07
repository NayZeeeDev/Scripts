/* Bag store UI — over the counter */
(function () {
  const $ = (id) => document.getElementById(id);
  const post = (name, data) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).catch(() => {});
  const ic = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">${d}</svg>`;
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const money = (n) => '$' + (n || 0).toLocaleString();

  let D = { items: [], owned: {}, wallet: 0, themes: [], categories: [] };
  let theme = 'all', cat = 'all', jobOnly = false;
  let list = [], index = 0;
  let mode = 'counter';
  let buying = false;
  const chosen = {}; // key -> variant id

  const isOpen = () => $('shop').classList.contains('open');
  const cur = () => list[index] || null;
  const variantOf = (item) => (item ? (chosen[item.key] != null ? chosen[item.key] : (item.variants[0] ? item.variants[0].id : null)) : null);
  const entry = (item) => (item ? { key: item.key, variant: variantOf(item) } : null);

  function filtered() {
    return D.items.filter((i) => {
      if (jobOnly) { if (!i.job) return false; } else if (i.job) return false;
      if (theme !== 'all' && i.theme !== theme) return false;
      if (cat !== 'all' && i.category !== cat) return false;
      return true;
    });
  }

  /* ---------- tell Lua what should be on the counter ---------- */
  function sendView(dir) {
    const n = list.length;
    const at = (o) => (n === 0 ? null : list[((index + o) % n + n) % n]);
    const c = at(0);
    // with 1 bag there are no neighbours; with 2 only show the other on one side
    const prev = n > 2 ? at(-1) : (n === 2 && index === 1 ? at(-1) : null);
    const next = n > 2 ? at(1) : (n === 2 && index === 0 ? at(1) : null);
    post('shopView', { prev: entry(prev), cur: entry(c), next: entry(next), dir: dir || 0 });
  }

  function go(dir) {
    if (list.length < 2 || buying) return;
    index = (index + dir + list.length) % list.length;
    sendView(list.length > 2 ? dir : 0);
    renderItem(true);
  }

  /* ---------- chips ---------- */
  function chip(label, on, onClick, extra) {
    const b = document.createElement('button');
    b.className = 's-chip' + (on ? ' on' : '') + (extra ? ' ' + extra : '');
    b.textContent = label;
    b.onclick = onClick;
    return b;
  }

  function setFilter(fn) {
    fn();
    list = filtered();
    index = 0;
    renderChips();
    sendView(0);
    renderItem(true);
  }

  function renderChips() {
    const top = $('themeChips');
    top.innerHTML = '';
    const jobCount = D.items.filter((i) => i.job).length;

    if (Array.isArray(D.themes) && D.themes.length && !jobOnly) {
      D.themes.forEach((t) => top.appendChild(chip(t.label, theme === t.key, () => setFilter(() => { theme = t.key; }))));
    }
    if (D.useJobTab !== false && jobCount > 0) {
      if (top.children.length) { const s = document.createElement('span'); s.className = 's-sep'; top.appendChild(s); }
      if (jobOnly) top.appendChild(chip('Store', false, () => setFilter(() => { jobOnly = false; })));
      top.appendChild(chip(`${D.jobTabLabel || 'Issued'} (${jobCount})`, jobOnly, () => setFilter(() => { jobOnly = !jobOnly; theme = 'all'; }), 'job'));
    }

    const bottom = $('catChips');
    bottom.innerHTML = '';
    if (Array.isArray(D.categories) && D.categories.length) {
      D.categories.forEach((c) => bottom.appendChild(chip(c.label, cat === c.key, () => setFilter(() => { cat = c.key; }))));
    }
  }

  /* ---------- the featured bag ---------- */
  let swapTimer = null;
  function renderItem(animate) {
    const item = cur();
    const label = $('label');

    const fill = () => {
      if (!item) {
        $('lTheme').textContent = '';
        $('lName').textContent = 'Nothing here';
        $('lPrice').innerHTML = '<span style="opacity:.6;font-size:13px">Try another theme or type</span>';
        $('lTags').innerHTML = '';
        return;
      }
      $('lTheme').textContent = item.job ? `${item.job} issue` : item.theme;
      $('lName').textContent = item.label;
      $('lPrice').innerHTML = item.price === 0 ? '<em>Issued</em>' : `<em>${money(item.price)}</em>`;
      $('lTags').innerHTML = [
        `<span>${item.slots} slots</span>`,
        `<span>${(item.weight / 1000).toFixed(item.weight % 1000 ? 1 : 0)} kg</span>`,
        item.carry ? '<span>hand carry</span>' : '',
        D.owned && D.owned[item.key] ? '<span class="own">owned</span>' : '',
      ].join('');
    };

    clearTimeout(swapTimer);
    if (animate) {
      label.classList.add('swap');
      swapTimer = setTimeout(() => { fill(); label.classList.remove('swap'); }, 200);
    } else {
      fill();
    }

    // swatches
    const sw = $('swatches');
    sw.innerHTML = '';
    if (item && item.variants.length > 1) {
      item.variants.forEach((v) => {
        const b = document.createElement('button');
        b.textContent = v.label;
        if (variantOf(item) === v.id) b.classList.add('on');
        b.onclick = () => {
          chosen[item.key] = v.id;
          post('shopVariant', { key: item.key, variant: v.id });
          renderItem(false);
        };
        sw.appendChild(b);
      });
    }

    // buy button
    const buy = $('buyBtn');
    buy.disabled = !item || buying;
    buy.innerHTML = !item ? 'Nothing selected'
      : `${ic('<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><path d="M3 6h18M16 10a4 4 0 0 1-8 0"/>')}
         ${item.price === 0 ? 'Collect' : 'Buy · ' + money(item.price)} <span class="key">ENTER</span>`;
    if (item && item.price > (D.wallet || 0)) buy.disabled = true;

    // sell link
    const sell = $('sellBtn');
    const canSell = item && D.canSell && item.price > 0 && D.owned && D.owned[item.key];
    sell.classList.toggle('hide', !canSell);
    if (canSell) sell.textContent = `Sell yours back for ${money(Math.floor(item.price * (D.sellRate || 0.5)))}`;

    // position dots
    const dots = $('dots');
    if (list.length > 1 && list.length <= 16) {
      dots.innerHTML = list.map((_, i) => `<i class="${i === index ? 'on' : ''}"></i>`).join('');
    } else {
      dots.innerHTML = list.length > 16 ? `<span style="font-size:10px;color:rgba(255,255,255,.6)">${index + 1} / ${list.length}</span>` : '';
    }

    $('meta').innerHTML = `<span><span class="key">A</span><span class="key">D</span> browse</span>
      <span>drag to spin</span><span><span class="key">T</span> try on</span><span><span class="key">ESC</span> leave</span>`;

    $('prev').classList.toggle('hide', list.length < 2);
    $('next').classList.toggle('hide', list.length < 2);
  }

  /* ---------- actions ---------- */
  function buy() {
    const item = cur();
    if (!item || buying || $('buyBtn').disabled) return;
    buying = true;
    renderItem(false);
    post('shopBuy', { key: item.key, variant: variantOf(item) });
    setTimeout(() => { if (buying) { buying = false; renderItem(false); } }, 4000);
  }

  function setMode(m) {
    mode = m;
    $('shop').classList.toggle('tryon', m === 'tryon');
    $('tryBtn').classList.toggle('on', m === 'tryon');
    $('tryBtn').innerHTML = m === 'tryon'
      ? `${ic('<path d="M3 9l2-5h14l2 5M3 9v10a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V9M3 9h18"/>')}Back to counter <span class="key">T</span>`
      : `${ic('<circle cx="12" cy="7" r="4"/><path d="M5 21v-1a7 7 0 0 1 14 0v1"/>')}Try on <span class="key">T</span>`;
  }

  function toggleTry() {
    if (!cur()) return;
    post('shopMode', { mode: mode === 'tryon' ? 'counter' : 'tryon' });
  }

  let toastTimer = null;
  function toast(text, bad) {
    const t = $('toast');
    t.textContent = text;
    t.classList.toggle('bad', !!bad);
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 1400);
  }

  function close() {
    $('shop').classList.remove('open');
    post('shopClose');
  }

  $('prev').onclick = () => go(-1);
  $('next').onclick = () => go(1);
  $('buyBtn').onclick = buy;
  $('tryBtn').onclick = toggleTry;
  $('sellBtn').onclick = () => { const i = cur(); if (i) post('shopSell', { key: i.key }); };
  $('shopClose').onclick = close;

  /* drag to spin, wheel to browse */
  (function () {
    const c = $('spin');
    let drag = false, lx = 0, acc = 0, raf = null, lastWheel = 0;
    const flush = () => { raf = null; if (acc) { post('shopSpin', { delta: acc * 0.45 }); acc = 0; } };
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
    if (!isOpen()) return;
    const k = e.key.toLowerCase();
    if (k === 'escape' || k === 'backspace') { e.preventDefault(); close(); }
    else if ((k === 'a' || k === 'arrowleft') && mode === 'counter') go(-1);
    else if ((k === 'd' || k === 'arrowright') && mode === 'counter') go(1);
    else if (k === 'enter') buy();
    else if (k === 't') toggleTry();
  });

  /* ---------- messages from Lua ---------- */
  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
      case 'shopOpen':
        D = data;
        theme = 'all'; cat = 'all'; jobOnly = false; index = 0; buying = false;
        $('shopTitle').textContent = data.title || 'Bag Store';
        $('wallet').textContent = money(data.wallet);
        $('wallet').parentElement.firstChild.textContent = (data.currency || 'Cash') + ' ';
        list = filtered();
        if (!list.length && D.items.some((i) => i.job)) { jobOnly = true; list = filtered(); }
        setMode('counter');
        renderChips();
        renderItem(false);
        $('label').style.left = '50%'; $('label').style.top = '34%';
        $('shop').classList.add('open');
        sendView(0);
        break;
      case 'shopLabel':
        $('label').style.left = (data.x * 100) + 'vw';
        $('label').style.top = (data.y * 100) + 'vh';
        break;
      case 'shopMode':
        setMode(data.mode);
        break;
      case 'shopResult':
        buying = false;
        if (data.wallet != null) { D.wallet = data.wallet; $('wallet').textContent = money(data.wallet); }
        if (data.owned) D.owned = data.owned;
        toast(data.ok ? 'Yours now' : 'Not this time', !data.ok);
        renderItem(false);
        break;
      case 'shopClose':
        $('shop').classList.remove('open');
        break;
      default: break;
    }
  });
})();
