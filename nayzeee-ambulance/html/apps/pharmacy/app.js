/* ═══════════════════════════════════════════════════════════
   NAYZEEE AMBULANCE · Pharmacy (app 'pharmacy')        module: pharmacy
   v5 window, no sidebar: section tabs + purse in the title bar.
     Counter    shelf rail (icon dock, tray count per shelf), formulary list (rows with
                shelf-level gauge, unit price, inline stepper), product inspector (lightbox
                stage with stock dial, instrument list, quantity + Add), counter tray dock
                (item tiles, totals with a rolling counter, cash / bank rings, Dispense),
                dark dispense slip in the inspector column after payment
     Cover      member card (generic, no brand), how cover works, Basic / Plus / Premium
                plans (buy, renew, switch with credit for unused days)
     Bills      open medical bills (pay one / pay all), recently paid
     Stock      (perm 'pharmacy') shelf levels, order from the supplier (society pays),
                put items from your inventory on the shelf
     Sales log  latest sales of the department
   Compact mode 'invoice': a medic sends a bill to a patient.

   Lua → JS   open { mode = 'shop'|'desk', point, tab, shop, categories, products, wallet,
                     payment, tax, discount, maxLines, insurance, bills, canManage, me, now, locale }
              open { mode = 'invoice', sid, name, max, presets, wait, insurance, cut, locale }
   JS → Lua   pharmacy:buy { lines[{ id, qty }], method, total } → { ok, receipt, data } | { ok = false, msg, data? }
              pharmacy:insurance { plan, method } → { ok, result, data }
              pharmacy:payBills { id | 'all', method } → { ok, result, data }
              pharmacy:refresh → { ok, data }      pharmacy:staff → { ok, staff }
              pharmacy:restock { id, qty, from = 'order'|'inventory' } → { ok, staff, msg }
              pharmacy:invoice { sid, amount, reason } → { ok, info } | { ok = false, msg }
   Keys: ESC close (closes a dialog first) · / search · ↑↓ browse · + add · Enter dispense / send
   Preview: index.html?app=pharmacy&view=shop|receipt|insurance|bills|stock|sales|desk|invoice
   ═══════════════════════════════════════════════════════════ */
(() => {
  const esc = NZA.esc, icon = NZA.icon;
  const APP = 'pharmacy';
  let LOC = {};
  const T = (k, fb, ...a) => {
    let s = LOC[k] !== undefined ? String(LOC[k]) : (fb !== undefined ? fb : k);
    let i = 0;
    return s.replace(/%(%|s|d|i)/g, (m, c) => (c === '%' ? '%' : (i < a.length ? String(a[i++]) : '')));
  };
  const money = n => NZ.money(Number(n) || 0);
  const num = (v, d = 0) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
  const arr = v => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));
  const initials = n => String(n || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]).join('').toUpperCase() || '?';
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const pad = n => String(n).padStart(2, '0');

  const CAT_ICON = { medicines: 'pill', dressings: 'bandage', lines: 'iv', airway: 'lungs', bones: 'bone', devices: 'kit',
    first_aid: 'medkit', medication: 'pill', wound_care: 'bandage', fluids: 'iv', orthopedic: 'bone', equipment: 'kit', surgery: 'scalpel', documents: 'file' };
  const CAT_FB = { medicines: 'Medicines', dressings: 'Bleeding & dressings', lines: 'Drips & lines', airway: 'Airway', bones: 'Bones & joints', devices: 'Kit & devices',
    first_aid: 'First response', medication: 'Medicines', wound_care: 'Bleeding & dressings', fluids: 'Drips & lines', orthopedic: 'Bones & joints', equipment: 'Kit & devices', surgery: 'Theatre', documents: 'Paperwork' };
  const kindIcon = k => {
    k = String(k || '');
    if (/transport/.test(k)) return 'ambulance';
    if (/respawn|ai_doctor/.test(k)) return 'hospital';
    if (/xray/.test(k)) return 'xray';
    if (/cpr|defib/.test(k)) return 'heart';
    if (/angio/.test(k)) return 'monitor';
    if (/assess/.test(k)) return 'stetho';
    if (/invoice/.test(k)) return 'receipt';
    return 'bandage';
  };

  const S = {
    d: null, view: 'shop', cat: 'all', q: '', sort: 'featured',
    cart: new Map(), method: 'bank', busy: false, receipt: null, msg: null, hl: null,
    staff: null, staffBusy: false, qty: {}, rowBusy: null, skew: 0, inv: null, sel: null, iq: 1, odo: null,
  };
  let root = null, win = null, dim = null, modal = null, invTimer = 0;

  /* ═════════════════════════ data helpers ═════════════════════════ */
  function normalize(d) {
    d = d || {};
    d.products = arr(d.products).map(p => Object.assign({}, p, { price: num(p.price), was: p.was ? num(p.was) : null, discount: num(p.discount), limit: Math.max(1, num(p.limit, 25)) }));
    d.categories = arr(d.categories);
    d.wallet = Object.assign({ cash: 0, bank: 0 }, d.wallet || {});
    d.payment = Object.assign({ cash: true, bank: true, default: 'bank' }, d.payment || {});
    d.discount = Object.assign({ pct: 0 }, d.discount || {});
    d.shop = d.shop || {};
    d.insurance = d.insurance || { enabled: false };
    d.insurance.plans = arr(d.insurance.plans);
    d.bills = d.bills || { enabled: false };
    d.bills.list = arr(d.bills.list);
    d.bills.history = arr(d.bills.history);
    if (d.now) S.skew = num(d.now) * 1000 - Date.now();
    return d;
  }
  function apply(data) {
    if (!data || typeof data !== 'object') return;
    const keep = { mode: S.d && S.d.mode, point: S.d && S.d.point, shop: S.d && S.d.shop };
    S.d = normalize(Object.assign({}, S.d || {}, data));
    if (keep.shop && (!data.shop || !data.shop.location)) S.d.shop = Object.assign({}, data.shop || {}, { location: keep.shop.location || (data.shop && data.shop.label), dept: (data.shop && data.shop.dept) || keep.shop.dept });
    clampCart();
  }
  const nowSec = () => Math.floor((Date.now() + S.skew) / 1000);
  const prods = () => (S.d && S.d.products) || [];
  const prod = id => prods().find(p => p.id === id) || null;
  const isShop = () => S.d && S.d.mode !== 'desk';
  const hasStock = p => p.stock !== undefined && p.stock !== null;
  const maxFor = p => (!p || p.locked ? 0 : Math.max(0, Math.min(p.limit || 25, hasStock(p) ? num(p.stock) : Infinity)));
  const catLabel = id => { const c = ((S.d && S.d.categories) || []).find(x => x.id === id); return (c && c.label) || T(`cat_${id}`, CAT_FB[id] || id); };
  const catIcon = id => { const c = ((S.d && S.d.categories) || []).find(x => x.id === id); return (c && c.icon) || CAT_ICON[id] || 'tag'; };
  const wallet = m => num(S.d && S.d.wallet && S.d.wallet[m]);
  const payOk = m => !!(S.d && S.d.payment && S.d.payment[m] !== false);

  function date(ts, withYear = true) { if (!ts) return '--'; const d = new Date(num(ts) * 1000); return `${d.getDate()} ${MON[d.getMonth()]}${withYear ? ` ${d.getFullYear()}` : ''}`; }
  function stamp(ts) {
    if (!ts) return '--';
    const d = new Date(num(ts) * 1000), n = new Date(nowSec() * 1000);
    const hm = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    return d.toDateString() === n.toDateString() ? hm : `${d.getDate()} ${MON[d.getMonth()]} ${hm}`;
  }

  function clampCart() {
    [...S.cart].forEach(([id, q]) => {
      const p = prod(id), m = maxFor(p);
      if (!p || m <= 0) S.cart.delete(id); else if (q > m) S.cart.set(id, m);
    });
  }

  function totals() {
    let sub = 0, count = 0, saved = 0;
    S.cart.forEach((q, id) => { const p = prod(id); if (p) { sub += p.price * q; count += q; if (p.was) saved += (p.was - p.price) * q; } });
    const pct = num(S.d && S.d.discount && S.d.discount.pct);
    const discount = Math.floor(sub * pct + 0.5);
    const taxPct = num(S.d && S.d.tax);
    const tax = Math.floor((sub - discount) * taxPct + 0.5);
    return { sub, discount, tax, total: sub - discount + tax, count, pct, taxPct, saved: saved + discount };
  }

  /* images: inventory picture, falls back to the category icon */
  const img = (src, fb, cls = '') => (src ? `<img class="${cls}" src="${esc(src)}" data-fb="${esc(fb)}" alt="" draggable="false">` : `<span class="ph-fb">${icon(fb)}</span>`);
  function hookImgs(host) {
    host.querySelectorAll('img[data-fb]').forEach(im => {
      const fail = () => { const s = document.createElement('span'); s.className = 'ph-fb'; s.innerHTML = icon(im.dataset.fb || 'box'); im.replaceWith(s); };
      if (im.complete && im.naturalWidth === 0 && im.getAttribute('src')) { fail(); return; }
      im.addEventListener('error', fail, { once: true });
    });
  }

  /* ═════════════════════════ window ═════════════════════════ */
  function teardown() {
    if (modal) { modal.close(); modal = null; }
    if (win) { win.destroy(); win = null; }
    if (dim) { dim.remove(); dim = null; }
    clearInterval(invTimer); invTimer = 0;
  }

  /* ═════════════════════════ window shell ═════════════════════════
     Title bar: section tabs (Counter · Cover · Bills · Shelf stock · Sales log) and the
     purse (cash / bank). No sidebar: the counter uses the whole body. */
  function insState() {
    const c = S.d.insurance.current;
    if (!c) return 'none';
    return c.active && num(c.expires) > nowSec() ? 'active' : 'expired';
  }
  const insStatusLabel = () => ({ active: T('ui_active', 'Active'), expired: T('ui_expired', 'Expired'), none: T('ui_inactive', 'Inactive') }[insState()]);

  // status ring in a 100 box (rotated so it starts at 12 o'clock)
  function ring(p, { r = 42, w = 8, ticks = 0, cls = '' } = {}) {
    const C = 2 * Math.PI * r, off = C * (1 - Math.max(0, Math.min(1, p)));
    let tk = '';
    for (let i = 0; i < ticks; i++) {
      const a = (i / ticks) * Math.PI * 2, big = i % 5 === 0, r1 = 49.5, r2 = big ? 45.5 : 47.4;
      tk += `<line x1="${(50 + r1 * Math.sin(a)).toFixed(2)}" y1="${(50 - r1 * Math.cos(a)).toFixed(2)}" x2="${(50 + r2 * Math.sin(a)).toFixed(2)}" y2="${(50 - r2 * Math.cos(a)).toFixed(2)}"${big ? ' class="b"' : ''}/>`;
    }
    return `<svg class="ph-rs ${cls}" viewBox="0 0 100 100">${tk ? `<g class="tk">${tk}</g>` : ''}<circle class="tr" cx="50" cy="50" r="${r}" stroke-width="${w}"/><circle class="ar" cx="50" cy="50" r="${r}" stroke-width="${w}" stroke-dasharray="${C.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}"/></svg>`;
  }

  function tabs() {
    const d = S.d, t = [];
    if (isShop()) t.push({ v: 'shop', ic: 'pill', l: T('ui_tab_counter', 'Counter') });
    if (d.insurance.enabled) { const st = insState(); t.push({ v: 'insurance', ic: 'shield', l: T('ui_insurance', 'Cover'), dot: st === 'active' ? 'ok' : st === 'expired' ? 'bad' : 'off' }); }
    if (d.bills.enabled) t.push({ v: 'bills', ic: 'receipt', l: T('ui_bills', 'Bills'), n: d.bills.list.length, tone: 'bad' });
    if (d.canManage && isShop()) {
      const att = S.staff ? num(S.staff.low) + num(S.staff.out) : 0;
      t.push({ v: 'stock', ic: 'box', l: T('ui_stock', 'Shelf stock'), n: att, tone: 'warn' }, { v: 'sales', ic: 'chart', l: T('ui_sales', 'Sales log') });
    }
    return t;
  }

  function midHTML() {
    const open = isShop() ? `<span class="ph-open"><i></i>${esc(T('ui_open', 'Open'))}</span>` : '';
    return `<nav class="ph-tabs">${tabs().map(t => `<button data-act="tab" data-v="${t.v}" class="${S.view === t.v ? 'on' : ''}">${icon(t.ic)}<span>${esc(t.l)}</span>${t.n ? `<i class="n ${t.tone || ''}">${t.n}</i>` : ''}${t.dot ? `<i class="d ${t.dot}"></i>` : ''}</button>`).join('')}</nav>${open}`;
  }

  // title-bar tabs + purse (kept under this name: every data change calls it)
  function renderSide() {
    if (!win) return;
    win.setMid(midHTML());
    win.act.innerHTML = `<div class="ph-purse">
      <span class="pw" data-w="cash">${icon('cash')}<em>${esc(T('ui_cash', 'Cash'))}</em><b>${money(wallet('cash'))}</b></span>
      <span class="pw" data-w="bank">${icon('bank')}<em>${esc(T('ui_bank', 'Bank'))}</em><b>${money(wallet('bank'))}</b></span>
    </div>`;
  }

  function flashWallet(m) {
    if (!win) return;
    const r = win.act.querySelector(`.pw[data-w="${m}"]`);
    if (r) { r.classList.remove('flash'); void r.offsetWidth; r.classList.add('flash'); }
  }

  function status() {
    if (!win) return;
    const keys = [{ key: 'ESC', label: T('ui_k_close', 'Close') }];
    if (S.view === 'shop') keys.push({ key: '/', label: T('ui_k_search', 'Search') }, { key: '↑↓', label: T('ui_k_browse', 'Browse') }, { key: '+', label: T('ui_k_add', 'Add to tray') }, { key: 'Enter', label: T('ui_k_pay', 'Dispense') });
    const me = S.d.me && S.d.me.name ? `<span>${esc(S.d.me.name)}</span>` : '';
    win.setStatus(keys, me);
  }

  function build() {
    dim = NZA.el('div', 'nza-dim');
    root.appendChild(dim);
    const desk = !isShop();
    const sh = S.d.shop || {};
    win = NZA.ui.Win(root, {
      title: (desk ? T('ui_desk', 'Billing desk') : T('ui_brand', 'Pharmacy')).toUpperCase(),
      sub: sh.location || sh.label || sh.dept || '',
      onClose: () => NZA.close(APP),
    });
    win.el.classList.add('ph-win');
    renderSide();
    renderMain();
  }

  function go(v) {
    closeModal();
    S.view = v;
    if ((S.view === 'stock' || S.view === 'sales') && !S.staff && !S.staffBusy) loadStaff();
    renderSide();
    renderMain();
  }

  function renderMain() {
    if (!win) return;
    const m = win.main;
    m.classList.toggle('ph-flush', S.view === 'shop');
    S.odo = null;
    if (S.view === 'shop') {
      m.innerHTML = `<div class="ph-counter">
        <nav class="ph-rail"></nav>
        <section class="ph-form">
          <div class="ph-head"><div class="ph-ht"></div>
            <label class="ph-search ${S.q ? 'has' : ''}">${icon('search')}<input id="ph-q" placeholder="${esc(T('ui_search', 'Find a product'))}" value="${esc(S.q)}" spellcheck="false" autocomplete="off"><button class="clr" data-act="clrq">${icon('x')}</button><kbd>/</kbd></label>
            <div class="ph-head-r"></div></div>
          <div class="ph-cols"><span>${esc(T('ui_col_item', 'Item'))}</span><span>${esc(T('ui_col_shelf', 'Shelf'))}</span><span>${esc(T('ui_col_unit', 'Unit'))}</span><span></span></div>
          <div class="ph-list"></div>
        </section>
        <aside class="ph-insp"></aside>
        <section class="ph-tray">
          <div class="ph-tl"></div>
          <div class="ph-tiles"></div>
          <div class="ph-sum"><div class="ph-sl"></div><div class="ph-tot"><span>${esc(T('ui_total', 'To pay'))}</span><div class="ph-odo"></div></div></div>
          <div class="ph-payc"></div>
        </section>
      </div>`;
      S.odo = NZA.ui.FlipClock(m.querySelector('.ph-odo'), { value: money(totals().total) });
      renderHead(); renderGrid(); renderInsp(); renderCart();
    } else if (S.view === 'insurance') {
      m.innerHTML = insHTML();
    } else if (S.view === 'bills') {
      m.innerHTML = billsHTML();
    } else if (S.view === 'stock') {
      m.innerHTML = stockHTML();
      hookImgs(m);
    } else if (S.view === 'sales') {
      m.innerHTML = salesHTML();
    }
    status();
  }

  /* ═════════════════════════ counter: formulary ═════════════════════════ */
  function visible() {
    const q = S.q.trim().toLowerCase();
    const list = prods().filter(p => (S.cat === 'all' || p.category === S.cat)
      && (!q || `${p.label} ${p.description || ''} ${catLabel(p.category)}`.toLowerCase().includes(q)));
    const rank = p => (p.locked ? 2 : (hasStock(p) && num(p.stock) <= 0 ? 1 : 0));
    list.sort((a, b) => {
      const r = rank(a) - rank(b);
      if (r) return r;
      if (S.sort === 'price') return a.price - b.price || num(a.order) - num(b.order);
      if (S.sort === 'name') return String(a.label).localeCompare(String(b.label));
      if (S.cat === 'all' && !!b.featured !== !!a.featured) return b.featured ? 1 : -1;
      return num(a.order) - num(b.order);
    });
    return list;
  }

  function shelves() {
    const list = [{ id: 'all', icon: 'grid', label: T('cat_all_short', 'All') }];
    S.d.categories.forEach(c => { if (num(c.count) > 0) list.push({ id: c.id, icon: c.icon || CAT_ICON[c.id] || 'tag', label: c.label || catLabel(c.id) }); });
    return list;
  }
  function inTray(cat) { let n = 0; S.cart.forEach((q, id) => { const p = prod(id); if (p && (cat === 'all' || p.category === cat)) n += q; }); return n; }

  function renderRail() {
    const r = win && win.main.querySelector('.ph-rail');
    if (!r) return;
    r.innerHTML = `<span class="ph-rl">${esc(T('ui_shelves', 'Shelves'))}</span>` + shelves().map((s, k) => {
      const n = s.id === 'all' ? 0 : inTray(s.id);
      return `<button class="ph-shelf ${S.cat === s.id ? 'on' : ''}" data-act="cat" data-v="${esc(s.id)}" style="--i:${k}"><span class="ti">${icon(s.icon)}${n ? `<i>${n}</i>` : ''}</span><span class="tl">${esc(s.label)}</span></button>`;
    }).join('');
  }

  function renderHead() {
    const h = win && win.main.querySelector('.ph-head');
    if (!h) return;
    const n = visible().length;
    const title = S.cat === 'all' ? T('ui_formulary', 'Full formulary') : catLabel(S.cat);
    const d = S.d.discount || {};
    const perk = num(d.pct) > 0
      ? `<span class="ph-perk">${icon(d.kind === 'staff' ? 'badge' : 'shield-check')}<span><b>${esc(d.kind === 'staff' ? T('ui_staff_discount', 'Staff discount') : (d.plan || T('ui_insurance', 'Cover')))}</b> −${Math.round(num(d.pct) * 100)}%</span></span>` : '';
    const sorts = [['featured', T('ui_sort_featured', 'Suggested')], ['price', T('ui_sort_price', 'Price')], ['name', T('ui_sort_name', 'Name')]];
    h.querySelector('.ph-ht').innerHTML = `<small>${esc(T('ui_shelf', 'Shelf'))}</small><h1>${esc(title)}<span class="cnt">${n}</span></h1>`;
    h.querySelector('.ph-head-r').innerHTML = `${perk}<div class="segc">${sorts.map(([v, l]) => `<button data-act="sort" data-v="${v}" class="${S.sort === v ? 'on' : ''}">${esc(l)}</button>`).join('')}</div>`;
  }

  function gaugeHTML(p) {
    if (p.locked) return `<span class="ph-gauge lock">${icon('lock')}</span>`;
    if (!hasStock(p)) return `<span class="ph-gauge inf"><span class="bars">${'<i class="on"></i>'.repeat(5)}</span><b>${esc(T('ui_always', 'Stocked'))}</b></span>`;
    const st = num(p.stock), cap = Math.max(st, num(p.max) || 20);
    const lv = st <= 0 ? 0 : Math.max(1, Math.min(5, Math.ceil((st / cap) * 5)));
    const cls = st <= 0 ? 'out' : p.low ? 'low' : '';
    return `<span class="ph-gauge ${cls}"><span class="bars">${[1, 2, 3, 4, 5].map(i => `<i class="${i <= lv ? 'on' : ''}"></i>`).join('')}</span><b>${st <= 0 ? esc(T('ui_sold_out', 'Empty')) : st}</b></span>`;
  }

  function rowHTML(p, k) {
    const inCart = S.cart.get(p.id) || 0;
    const max = maxFor(p);
    const out = hasStock(p) && num(p.stock) <= 0;
    const tags = [];
    if (p.was && p.discount > 0) tags.push(`<span class="ph-tag teal">−${Math.round(p.discount * 100)}%</span>`);
    if (p.featured && !p.locked) tags.push(`<span class="ph-tag line">${icon('star')}${esc(T('ui_featured', 'Staff pick'))}</span>`);
    if (p.limit < 25 && !p.locked) tags.push(`<span class="ph-tag">${esc(T('ui_max', 'Max %d', p.limit))}</span>`);
    let ctl;
    if (p.locked) ctl = `<span class="ph-lockt" title="${esc(p.lockText || '')}">${icon('lock')}</span>`;
    else if (inCart > 0) ctl = `<div class="ph-step"><button data-act="dec" data-id="${esc(p.id)}">${icon('minus')}</button><b>${inCart}</b><button class="plus" data-act="inc" data-id="${esc(p.id)}" ${inCart >= max ? 'disabled' : ''}>${icon('plus')}</button></div>`;
    else ctl = `<button class="ph-add" data-act="add" data-id="${esc(p.id)}" ${max <= 0 ? 'disabled' : ''} title="${esc(T('ui_add', 'Add to tray'))}">${icon('plus')}</button>`;
    return `<div class="ph-row ${S.sel === p.id ? 'sel' : ''} ${p.locked ? 'locked' : ''} ${out ? 'out' : ''} ${inCart ? 'intray' : ''}" data-act="sel" data-id="${esc(p.id)}" style="--i:${Math.min(k, 14)}">
      <span class="ph-th">${img(p.image, catIcon(p.category))}</span>
      <div class="ph-nm"><div class="l1"><b>${esc(p.label)}</b>${tags.join('')}</div><span>${esc(p.locked ? (p.lockText || '') : (p.description || ''))}</span></div>
      ${gaugeHTML(p)}
      <span class="ph-pr"><b>${money(p.price)}</b><small>${esc(T('ui_each', 'each'))}</small></span>
      <span class="ph-ctl">${ctl}</span>
    </div>`;
  }

  function renderGrid() {
    const g = win && win.main.querySelector('.ph-list');
    if (!g) return;
    const list = visible();
    const prev = S.sel;
    if (!S.sel || !list.some(p => p.id === S.sel)) S.sel = list.length ? list[0].id : (S.sel && prod(S.sel) ? S.sel : null);
    const top = g.scrollTop;
    g.innerHTML = list.length ? list.map(rowHTML).join('')
      : `<div class="ph-empty"><span class="i">${icon('search')}</span><b>${esc(T('ui_no_match', 'Nothing matches "%s"', S.q))}</b><span>${esc(T('ui_no_match_sub', 'Try another word or another shelf.'))}</span></div>`;
    g.scrollTop = top;
    hookImgs(g);
    if (prev !== S.sel) { S.iq = 1; renderInsp(); }
  }

  // re-render one row in place (keeps the list's scroll and avoids re-animating everything)
  function refreshCard(id) {
    const g = win && win.main.querySelector('.ph-list');
    const old = g && g.querySelector(`.ph-row[data-id="${CSS.escape(id)}"]`);
    const p = prod(id);
    if (!old || !p) { renderGrid(); return; }
    const k = document.createElement('div');
    k.innerHTML = rowHTML(p, 0);
    const n = k.firstElementChild;
    n.style.animation = 'none';
    old.replaceWith(n);
    hookImgs(n);
    if (id === S.sel) renderInsp();
  }

  function select(id, scroll) {
    if (!prod(id)) return;
    S.sel = id; S.iq = 1;
    const g = win && win.main.querySelector('.ph-list');
    if (g) g.querySelectorAll('.ph-row').forEach(r => r.classList.toggle('sel', r.dataset.id === id));
    if (scroll && g) { const r = g.querySelector(`.ph-row[data-id="${CSS.escape(id)}"]`); if (r && r.scrollIntoView) r.scrollIntoView({ block: 'nearest' }); }
    if (S.receipt) S.receipt = null;
    renderInsp();
  }

  /* ═════════════════════════ counter: inspector ═════════════════════════ */
  function renderInsp() {
    const host = win && win.main.querySelector('.ph-insp');
    if (!host) return;
    if (S.receipt) { host.innerHTML = slipHTML(S.receipt); hookImgs(host); return; }
    const p = prod(S.sel);
    if (!p) { host.innerHTML = `<div class="ph-empty"><span class="i">${icon('pill')}</span><b>${esc(T('ui_pick', 'Pick a product'))}</b><span>${esc(T('ui_pick_sub', 'Its details show up here.'))}</span></div>`; return; }
    const pct = num(S.d.discount && S.d.discount.pct);
    const yours = Math.floor(p.price * (1 - pct) + 0.5);
    const inCart = S.cart.get(p.id) || 0, max = maxFor(p), room = Math.max(0, max - inCart);
    const out = hasStock(p) && num(p.stock) <= 0;
    S.iq = Math.max(1, Math.min(Math.max(1, room), S.iq || 1));
    const fill = hasStock(p) ? Math.max(0, Math.min(1, num(p.stock) / Math.max(num(p.stock), num(p.max) || 20))) : 1;
    host.innerHTML = `
      <div class="ph-stage">
        <span class="ph-shelfchip">${icon(catIcon(p.category))}${esc(catLabel(p.category))}</span>
        <span class="ph-code">${esc(String(p.id).toUpperCase().replace(/_/g, '-').slice(0, 14))}</span>
        <div class="ph-dial">${ring(fill, { r: 44, w: 3, ticks: 60, cls: out ? 'red' : p.low ? 'amber' : 'teal' })}</div>
        <div class="ph-hero">${img(p.image, catIcon(p.category), 'hero')}</div>
        ${p.was && p.discount > 0 ? `<span class="ph-save">−${Math.round(p.discount * 100)}%</span>` : ''}
      </div>
      <div class="ph-iname"><h2>${esc(p.label)}</h2><p>${esc(p.description || '')}</p></div>
      <div class="ph-ilist">
        <div class="ph-irow"><span>${esc(T('ui_i_unit', 'Shelf price'))}</span><b>${money(p.price)}</b></div>
        ${pct > 0 ? `<div class="ph-irow teal"><span>${esc(T('ui_i_yours', 'With your discount'))}</span><b>${money(yours)}</b></div>` : ''}
        <div class="ph-irow ${out ? 'red' : p.low ? 'amber' : ''}"><span>${esc(T('ui_i_stock', 'On the shelf'))}</span><b>${hasStock(p) ? num(p.stock) : esc(T('ui_always', 'Stocked'))}</b></div>
        <div class="ph-irow"><span>${esc(T('ui_i_limit', 'Per order'))}</span><b>${p.locked ? '—' : p.limit}</b></div>
        <div class="ph-irow white"><span>${esc(T('ui_i_tray', 'In your tray'))}</span><b>${inCart}</b></div>
      </div>
      <div class="ph-iact">${p.locked
        ? `<div class="ph-lockbox">${icon('lock')}<span>${esc(p.lockText || T('ui_locked', 'Not for you'))}</span></div>`
        : `<div class="ph-iq"><button data-act="iq" data-d="-1" ${S.iq <= 1 ? 'disabled' : ''}>${icon('minus')}</button><b>${S.iq}</b><button data-act="iq" data-d="1" ${S.iq >= room ? 'disabled' : ''}>${icon('plus')}</button></div>
           <button class="btn-teal ph-iadd" data-act="iadd" data-id="${esc(p.id)}" ${room <= 0 ? 'disabled' : ''}>${icon(room <= 0 ? 'check' : 'plus')}<span>${esc(room <= 0 ? (out ? T('ui_sold_out', 'Empty') : T('ui_i_full', 'Limit reached')) : T('ui_i_add', 'Add %d to tray', S.iq))}</span></button>`}</div>`;
    hookImgs(host);
  }

  /* ═════════════════════════ counter: tray ═════════════════════════ */
  function tileHTML(id, q) {
    const p = prod(id);
    if (!p) return '';
    return `<div class="ph-tile ${S.hl === id ? 'hl' : ''}" data-act="sel" data-id="${esc(id)}">
      <span class="im">${img(p.image, catIcon(p.category))}<i>${q}</i></span>
      <div class="t"><b>${esc(p.label)}</b><span>${money(p.price * q)}</span></div>
      <button class="rm" data-act="rm" data-id="${esc(id)}" title="${esc(T('ui_clear', 'Remove'))}">${icon('x')}</button>
    </div>`;
  }

  function payBtns(total) {
    return ['cash', 'bank'].map(m => {
      const have = wallet(m), short = have < total;
      const cover = total > 0 ? Math.min(1, have / total) : 1;
      return `<button data-act="method" data-m="${m}" class="ph-pm ${S.method === m ? 'on' : ''} ${short && total > 0 ? 'short' : ''}" ${payOk(m) ? '' : 'disabled'}>
        <span class="r">${ring(cover, { r: 40, w: 10, cls: short && total > 0 ? 'red' : 'teal' })}${icon(m === 'cash' ? 'cash' : 'bank')}</span>
        <span class="t"><b>${esc(T(`ui_${m}`, m === 'cash' ? 'Cash' : 'Bank'))}</b><small>${short && total > 0 ? esc(T('ui_short', 'Short %s', money(total - have))) : money(have)}</small></span></button>`;
    }).join('');
  }

  function renderCart() {
    const c = win && win.main.querySelector('.ph-tray');
    if (!c) return;
    renderRail();
    const t = totals();
    const lines = [...S.cart];
    const d = S.d.discount || {};
    const discLabel = d.kind === 'staff' ? T('ui_staff_discount', 'Staff discount') : d.kind === 'both' ? T('ui_both_discount', 'Cover + staff') : T('ui_ins_discount', '%s cover', d.plan || '');
    const cap = Math.max(1, num(S.d.maxLines, 30));
    c.querySelector('.ph-tl').innerHTML = `<span class="ph-tring">${ring(lines.length / cap, { r: 42, w: 7, ticks: 30, cls: 'teal' })}<b class="${S.hl ? 'bump' : ''}">${t.count}</b></span>
      <div><small>${esc(T('ui_order', 'Tray'))}</small><b>${esc(t.count === 1 ? T('ui_item', '1 item') : T('ui_items', '%d items', t.count))}</b>
      ${lines.length ? `<button class="ph-clear" data-act="clear">${icon('trash')}${esc(T('ui_clear_all', 'Clear'))}</button>` : ''}</div>`;
    c.querySelector('.ph-tiles').innerHTML = lines.length ? lines.map(([id, q]) => tileHTML(id, q)).join('')
      : `<div class="ph-tempty"><span class="i">${icon('crate')}</span><div><b>${esc(T('ui_empty_order', 'The tray is empty'))}</b><span>${esc(T('ui_empty_order_sub', 'Pick from the formulary — items land here.'))}</span></div></div>`;
    c.querySelector('.ph-sl').innerHTML = `
      <div class="ln"><span>${esc(T('ui_subtotal', 'Subtotal'))}</span><b>${money(t.sub)}</b></div>
      ${t.pct > 0 && t.sub > 0 ? `<div class="ln disc"><span>${icon(d.kind === 'staff' ? 'badge' : 'shield-check')}${esc(discLabel)} −${Math.round(t.pct * 100)}%</span><b>−${money(t.discount)}</b></div>` : ''}
      ${t.taxPct > 0 ? `<div class="ln"><span>${esc(T('ui_tax', 'Sales tax'))} ${Math.round(t.taxPct * 1000) / 10}%</span><b>${money(t.tax)}</b></div>` : ''}`;
    if (S.odo) S.odo.set(money(t.total));
    const canPay = lines.length && !S.busy && payOk(S.method) && wallet(S.method) >= t.total;
    const msg = S.msg ? `<div class="ph-msg ${S.msg.kind}">${icon(S.msg.kind === 'err' ? 'error' : S.msg.kind === 'warn' ? 'alert' : 'check')}<span>${esc(S.msg.text)}</span></div>` : '';
    c.querySelector('.ph-payc').innerHTML = `<div class="ph-pay">${payBtns(t.total)}</div>
      <button class="btn-teal ph-paybtn ${S.busy ? 'busy' : ''}" data-act="pay" ${canPay ? '' : 'disabled'}>${S.busy
        ? `<span class="ph-spin"></span>${esc(T('ui_paying', 'Dispensing'))}`
        : `${icon('check')}${esc(T('ui_pay', 'Dispense'))}${lines.length ? '<kbd>Enter</kbd>' : ''}`}</button>${msg}`;
    hookImgs(c);
    S.hl = null;
  }

  /* dispense slip (dark, in the inspector column) */
  function slipHTML(r) {
    const lines = arr(r.lines);
    const kind = r.discountKind;
    const dl = kind === 'staff' ? T('ui_staff_discount', 'Staff discount') : kind === 'both' ? T('ui_both_discount', 'Cover + staff') : T('ui_ins_discount', '%s cover', r.plan || '');
    const saved = lines.reduce((s, l) => { const p = prod(l.id); return s + (p && p.was ? (p.was - num(l.unit)) * num(l.qty) : 0); }, 0) + num(r.discount);
    const by = T('ui_paid_by', 'Paid by %s', T(`ui_${r.method}`, r.method === 'cash' ? 'Cash' : 'Bank'));
    return `<div class="ph-slip">
      <div class="ph-slh">
        <span class="ph-stamp">${ring(1, { r: 44, w: 4, ticks: 40, cls: 'teal' })}${icon('check')}</span>
        <div><small>${esc(T('ui_paid', 'Dispensed'))}</small><b>${esc(r.no || '')}</b><span>${esc(date(r.time))} · ${esc(stamp(r.time).slice(-5))}</span></div>
      </div>
      <p class="ph-slp ${r.partial ? 'warn' : ''}">${esc(r.partial ? T('ui_partial', 'Some items did not fit — %s refunded.', money(r.refund)) : T('ui_paid_sub', 'Everything is in your pockets.'))}</p>
      <div class="ph-sll">${lines.map((l, k) => `<div class="ph-sline" style="--i:${k}"><em>${num(l.qty)}×</em><span>${esc(l.label || l.name)}</span><b>${money(l.total)}</b></div>`).join('')}</div>
      <div class="ph-sls">
        <div class="ln"><span>${esc(T('ui_subtotal', 'Subtotal'))}</span><b>${money(r.subtotal)}</b></div>
        ${num(r.discount) > 0 ? `<div class="ln disc"><span>${esc(dl)}</span><b>−${money(r.discount)}</b></div>` : ''}
        ${num(r.tax) > 0 ? `<div class="ln"><span>${esc(T('ui_tax', 'Sales tax'))}</span><b>${money(r.tax)}</b></div>` : ''}
        ${num(r.refund) > 0 ? `<div class="ln"><span>${esc(T('reason_refund', 'Refund'))}</span><b>−${money(r.refund)}</b></div>` : ''}
      </div>
      <div class="ph-slt"><span>${esc(by)}</span><b>${money(r.total)}</b></div>
      ${saved > 0 ? `<div class="ph-saved">${icon('tag')}${esc(T('ui_saved', 'You saved %s', money(saved)))}</div>` : ''}
      <button class="btn-line ph-again" data-act="neworder">${icon('plus')}${esc(T('ui_new_order', 'Start a new tray'))}</button>
    </div>`;
  }

  function addToCart(id, n) {
    const p = prod(id);
    if (!p) return;
    if (S.receipt) { S.receipt = null; renderInsp(); }
    const max = maxFor(p);
    if (n > 0 && !S.cart.has(id) && S.cart.size >= num(S.d.maxLines, 30)) {
      S.msg = { kind: 'warn', text: T('err_too_many', 'Too many different products in one order.') };
      renderCart();
      return;
    }
    const q = Math.max(0, Math.min(max, (S.cart.get(id) || 0) + n));
    if (q > 0) S.cart.set(id, q); else S.cart.delete(id);
    if (n > 0) { S.hl = id; NZA.audio.click(780); } else NZA.audio.click(520);
    S.msg = null;
    refreshCard(id);
    renderCart();
  }

  async function pay() {
    if (S.busy || !S.cart.size || S.receipt) return;
    const t = totals();
    if (wallet(S.method) < t.total) {
      S.msg = { kind: 'err', text: T('err_no_money', 'Not enough money.') };
      NZA.audio.fail();
      return renderCart();
    }
    S.busy = true; S.msg = null;
    renderCart();
    const lines = [...S.cart].map(([id, qty]) => ({ id, qty }));
    const method = S.method;
    const res = await NZA.post(`${APP}:buy`, { lines, method, total: t.total });
    S.busy = false;
    if (!win) return;
    if (res && res.ok) {
      if (res.data) apply(res.data);
      S.cart.clear();
      S.receipt = res.receipt || { lines: [], total: t.total, method };
      NZA.audio.success();
      renderSide(); renderHead(); renderGrid(); renderInsp(); renderCart();
      flashWallet(method);
    } else {
      if (res && res.data) apply(res.data);
      S.msg = { kind: 'err', text: (res && res.msg) || T('ui_failed', 'Payment failed') };
      NZA.audio.fail();
      renderSide(); renderHead(); renderGrid(); renderInsp(); renderCart();
    }
  }

  /* ═════════════════════════ shared view bits ═════════════════════════ */
  function methodSeg() {
    return `<div class="ph-method"><span class="lbl">${esc(T('ui_pay_with', 'Pay from'))}</span><div class="segc">${['cash', 'bank'].filter(payOk).map(m =>
      `<button data-act="method" data-m="${m}" class="${S.method === m ? 'on' : ''}">${esc(T(`ui_${m}`, m === 'cash' ? 'Cash' : 'Bank'))}<small>${money(wallet(m))}</small></button>`).join('')}</div></div>`;
  }
  const emptyView = (ic, title, sub = '') => `<div class="ph-empty" style="flex:1"><span class="i">${icon(ic)}</span><b>${esc(title)}</b>${sub ? `<span>${esc(sub)}</span>` : ''}</div>`;
  function closeModal() { if (modal) { modal.close(); modal = null; } }
  function confirm({ title, text, ic = 'shield', label, onOk }) {
    closeModal();
    modal = NZA.ui.Modal({
      title, text, icon: ic, tone: 'teal', host: root,
      actions: [
        { label: T('ui_cancel', 'Cancel'), kind: 'line', onClick: () => { modal = null; } },
        { label: label || T('ui_confirm', 'Confirm'), kind: 'teal', onClick: () => { modal = null; onOk(); } },
      ],
    });
    const mw = modal.el.querySelector('.nza-modal');
    if (mw) mw.style.pointerEvents = 'auto';
  }

  /* ═════════════════════════ insurance ═════════════════════════ */
  function insHTML() {
    const ins = S.d.insurance;
    if (!ins.enabled) return `<div class="ph-view">${emptyView('shield', T('ui_ins_disabled', 'Health insurance is not sold at this counter.'))}</div>`;
    const cur = ins.current, st = insState(), now = nowSec();
    const card = cur ? `<div class="ph-icard ${st === 'expired' ? 'expired' : ''}">
        <div class="top"><span class="ph-cross">${icon('cross')}</span><div class="br"><b>${esc(T('ui_ins_card_t', 'HEALTH COVER'))}</b><span>${esc((S.d.shop && (S.d.shop.dept || S.d.shop.label)) || T('ui_ins_title', 'Health insurance'))}</span></div>
          <span class="st ph-tag ${st === 'active' ? 'teal' : 'red'}">${esc(insStatusLabel())}</span></div>
        <div class="chip"></div>
        <div class="plan"><div><span>${esc(T('ui_ins_current', 'Your plan'))}</span><b>${esc(cur.label)}</b></div>
          <div class="cov"><span>${esc(T('ui_ins_cover_s', 'Cover'))}</span><b>${Math.round(num(cur.cover) * 100)}%</b></div></div>
        <div class="rows"><div><span>${esc(T('ui_ins_holder', 'Holder'))}</span><b>${esc((S.d.me && S.d.me.name) || '')}</b></div>
          <div><span>${esc(T('ui_ins_member', 'Member no.'))}</span><b class="ph-mono">${esc(cur.serial || '--')}</b></div>
          <div><span>${esc(T('ui_ins_valid', 'Valid until'))}</span><b>${esc(date(cur.expires))}</b></div></div>
      </div>`
      : `<div class="ph-icard none"><span class="i">${icon('shield')}</span><b>${esc(T('ui_ins_none', 'You are not insured'))}</b><p>${esc(T('ui_ins_none_sub', 'Every medical bill is paid in full from your own pocket. Pick a plan to get covered.'))}</p></div>`;
    // example split: 1,000 bill with the current (or the popular) plan's cover
    const ref = (cur && st === 'active' && cur) || ins.plans.find(p => p.popular) || ins.plans[0];
    const cov = ref ? num(ref.cover) : 0;
    const insPays = Math.round(1000 * cov);
    let period = '';
    if (cur && st === 'active') {
      const total = Math.max(1, num(cur.expires) - num(cur.started || now));
      const left = Math.max(0, num(cur.expires) - now);
      const days = Math.floor(left / 86400);
      period = `<div class="ph-days"><div class="ph-sec" style="margin-bottom:9px">${esc(T('ui_ins_period', 'Coverage period'))}</div>${NZA.ui.meterHTML({ value: left / total, tone: left < 86400 ? 'amber' : '' })}
        <small><span>${esc(date(cur.started || now))}</span><b style="color:var(--white);font-weight:600">${esc(days >= 1 ? T('ui_ins_days_left', '%d days left', days) : T('ui_ins_hours_left', '%d hours left', Math.max(1, Math.ceil(left / 3600))))}</b><span>${esc(date(cur.expires))}</span></small></div>`;
    } else if (cur) {
      period = `<div class="ph-note" style="--x:0"><b style="color:#ff8a8d">${esc(T('ui_ins_expired_on', 'Expired on %s', date(cur.expires)))}</b><p>${esc(T('ui_ins_none_sub', ''))}</p></div>`;
    }
    const how = `<div class="ph-how">
        <div class="ph-note"><b>${esc(T('ui_ins_how', 'How cover works'))}</b><p>${esc(T('ui_ins_how_text', 'A $1,000 bill with 65% cover: insurance pays $650, you pay $350. Bills you cannot pay wait for you in the Bills tab.'))}</p></div>
        ${period}
        ${ref ? `<div class="ph-split"><div class="bar"><i class="a" style="width:${Math.max(18, cov * 100)}%">${money(insPays)}</i><i class="b">${money(1000 - insPays)}</i></div>
          <small><span>${esc(T('ui_inv_ins_pays', 'Insurance pays'))} · ${esc(ref.label)}</span><span>${esc(T('ui_inv_pat_pays', 'Patient pays'))}</span></small></div>` : ''}
      </div>`;
    const plans = ins.plans.map((p, k) => {
      const yours = cur && cur.plan === p.id && st === 'active';
      const rib = yours ? `<span class="rib white">${icon('check')}${esc(T('ui_ins_yours', 'Your plan'))}</span>`
        : p.popular ? `<span class="rib">${icon('star')}${esc(T('ui_ins_popular', 'Most popular'))}</span>` : '';
      const action = p.action || 'buy';
      const label = action === 'renew' ? T('ui_ins_renew', 'Renew +%d days', num(p.days)) : action === 'switch' ? T('ui_ins_switch', 'Switch to %s', p.label) : T('ui_ins_buy', 'Get %s', p.label);
      const cls = action === 'switch' ? 'btn-line' : 'btn-teal';
      const pay = num(p.pay !== undefined ? p.pay : p.price);
      const note = p.allowed === false ? `<small class="w">${esc(p.reason || '')}</small>`
        : num(p.credit) > 0 ? `<small class="t">${esc(T('ui_ins_credit', '%s credit for your unused days', money(p.credit)))}</small>`
          : `<small>${esc(T('ui_ins_new_expiry', 'Covered until %s', date(p.newExpires || (now + num(p.days) * 86400))))}</small>`;
      return `<div class="ph-plan ${p.popular ? 'popular' : ''} ${yours ? 'current' : ''}" style="animation-delay:${k * 60}ms">${rib}
        <div class="hd"><span class="ic">${icon(p.icon || 'shield')}</span><div><h3>${esc(p.label)}</h3><p>${esc(p.desc || '')}</p></div></div>
        <div class="pr"><b>${money(pay)}</b><span>${esc(T('ui_ins_per', '/ %d days', num(p.days)))}</span>${pay !== num(p.price) ? `<s>${money(p.price)}</s>` : ''}</div>
        <ul>
          <li>${icon('shield-check')}<span>${esc(T('ui_ins_cover', '%d%% of medical bills covered', Math.round(num(p.cover) * 100)))}</span></li>
          <li>${icon('pill')}<span>${esc(T('ui_ins_pharmacy', '%d%% off at every pharmacy', Math.round(num(p.pharmacy) * 100)))}</span></li>
          <li>${icon('calendar')}<span>${esc(T('ui_ins_days', 'Valid %d days, renew any time', num(p.days)))}</span></li>
          ${ins.card !== false ? `<li>${icon('id')}<span>${esc(T('ui_ins_card', 'Insurance card included'))}</span></li>` : ''}
        </ul>
        <div class="act"><button class="${cls}" data-act="plan" data-plan="${esc(p.id)}" ${p.allowed === false ? 'disabled' : ''}>${esc(label)}</button>${note}</div>
      </div>`;
    }).join('');
    return `<div class="ph-view">
      <div class="w-head"><div><h1>${esc(T('ui_ins_title', 'Health insurance'))}</h1><p>${esc(T('ui_ins_sub', 'Insurance pays its share of every treatment, ambulance and respawn bill, and lowers pharmacy prices.'))}</p></div>${methodSeg()}</div>
      <div class="ph-ins-top">${card}${how}</div>
      <div class="ph-sec">${esc(T('ui_ins_plans', 'Plans'))}</div>
      <div class="ph-plans">${plans}</div>
    </div>`;
  }

  function choosePlan(id) {
    const p = S.d.insurance.plans.find(x => x.id === id);
    if (!p || p.allowed === false) return;
    const pay = num(p.pay !== undefined ? p.pay : p.price);
    if (pay > wallet(S.method)) { NZA.toast({ title: T('ui_ins_title', 'Health insurance'), message: T('err_no_money', 'Not enough money.'), type: 'error' }); NZA.audio.fail(); return; }
    const until = date(p.newExpires || (nowSec() + num(p.days) * 86400));
    confirm({
      title: T('ui_ins_confirm', 'Confirm insurance'), ic: p.icon || 'shield',
      text: T('ui_ins_confirm_text', '**%s plan** for **%s** from your %s. Covered until %s.', p.label, money(pay), T(`method_${S.method}`, S.method), until),
      label: T('ui_confirm', 'Confirm'),
      onOk: () => buyPlan(id),
    });
  }

  async function buyPlan(id) {
    if (S.busy) return;
    S.busy = true;
    const btn = win && win.main.querySelector(`[data-plan="${CSS.escape(id)}"]`);
    if (btn) { btn.disabled = true; btn.innerHTML = '<span class="ph-spin"></span>'; }
    const method = S.method;
    const res = await NZA.post(`${APP}:insurance`, { plan: id, method });
    S.busy = false;
    if (!win) return;
    if (res && res.ok) {
      if (res.data) apply(res.data);
      NZA.audio.success();
      renderSide(); renderMain(); flashWallet(method);
    } else {
      NZA.toast({ title: T('ui_ins_title', 'Health insurance'), message: (res && res.msg) || T('ui_failed', 'Payment failed'), type: 'error' });
      NZA.audio.fail();
      renderMain();
    }
  }

  /* ═════════════════════════ bills ═════════════════════════ */
  function billRow(b, paid) {
    const meta = [`<i>${icon('clock')}${esc(stamp(paid ? b.paidAt || b.created : b.created))}</i>`];
    if (b.medicName) meta.push(`<i>${icon('user')}${esc(T('ui_bills_by', 'by %s', b.medicName))}</i>`);
    if (num(b.covered) > 0) meta.push(`<i class="t">${icon('shield-check')}${esc(T('ui_bills_ins', 'insurance paid %s', money(b.covered)))}</i>`);
    return `<div class="ph-bill ${paid ? 'paid' : ''}" data-bill="${esc(b.id)}">
      <span class="ic">${icon(paid ? 'check' : kindIcon(b.kind))}</span>
      <div class="txt"><b>${esc(b.reason || T('reason_default', 'Medical care'))}</b><span>${meta.join('')}</span></div>
      <div class="am"><b>${money(b.amount)}</b><span class="ph-mono">#${esc(b.id)}</span></div>
      ${paid ? '' : `<button class="btn-teal btn-sm" data-act="paybill" data-id="${esc(b.id)}" ${wallet(S.method) < num(b.amount) ? 'disabled' : ''}>${esc(T('ui_bills_pay', 'Pay'))}</button>`}
    </div>`;
  }

  function billsHTML() {
    const b = S.d.bills;
    if (!b.enabled) return `<div class="ph-view">${emptyView('receipt', T('ui_bills_disabled', 'Bills cannot be paid at this counter.'))}</div>`;
    const total = b.list.reduce((s, x) => s + num(x.amount), 0);
    const covered = [...b.list, ...b.history].reduce((s, x) => s + num(x.covered), 0);
    const open = b.list.length
      ? b.list.map(x => billRow(x, false)).join('')
      : emptyView('check', T('ui_bills_none', 'No open bills'), T('ui_bills_none_sub', 'You are all square with the hospital.')).replace('class="i"', 'class="i ok"');
    const hist = b.history.length ? b.history.map(x => billRow(x, true)).join('') : `<div class="ph-empty"><span class="i">${icon('history')}</span><span>--</span></div>`;
    return `<div class="ph-view">
      <div class="w-head"><div><h1>${esc(T('ui_bills_title', 'Medical bills'))}</h1><p>${esc(T('ui_bills_sub', 'Bills you could not pay at the time of treatment. Pay them here, one by one or all at once.'))}</p></div>${methodSeg()}</div>
      <div class="w-stats">
        <div class="w-stat"><span class="si ${b.list.length ? 'red' : 'teal'}">${icon('receipt')}</span><div><span>${esc(T('ui_bills_open', 'Open bills'))}</span><b>${b.list.length}</b></div></div>
        <div class="w-stat"><span class="si ${total ? 'red' : ''}">${icon('cash')}</span><div><span>${esc(T('ui_bills_due', 'Total due'))}</span><b class="${total ? 'red' : ''}">${money(total)}</b></div></div>
        <div class="w-stat"><span class="si teal">${icon('shield-check')}</span><div><span>${esc(T('ui_bills_covered', 'Insurance paid'))}</span><b>${money(covered)}</b></div></div>
      </div>
      <div class="ph-bills-wrap">
        <div class="w-panel"><div class="w-phead"><div><h2>${esc(T('ui_bills_open', 'Open bills'))}</h2><p>${esc(T('ui_bills_due', 'Total due'))} · ${money(total)}</p></div>
          ${b.list.length > 1 ? `<button class="btn-teal btn-sm" data-act="payall" ${wallet(S.method) < total ? 'disabled' : ''}>${icon('check')}${esc(T('ui_bills_pay_all', 'Pay all %s', money(total)))}</button>` : ''}</div>
          <div class="w-pbody">${open}</div></div>
        <div class="w-panel"><div class="w-phead"><div><h2>${esc(T('ui_bills_history', 'Recently paid'))}</h2></div></div><div class="w-pbody">${hist}</div></div>
      </div>
    </div>`;
  }

  function payBill(which) {
    const list = S.d.bills.list;
    const pick = which === 'all' ? list : list.filter(b => String(b.id) === String(which));
    if (!pick.length) return;
    const total = pick.reduce((s, x) => s + num(x.amount), 0);
    if (wallet(S.method) < total) { NZA.toast({ title: T('title_billing', 'Medical billing'), message: T('err_no_money', 'Not enough money.'), type: 'error' }); return; }
    const run = async () => {
      if (S.busy) return;
      S.busy = true;
      pick.forEach(b => { const r = win && win.main.querySelector(`.ph-bill[data-bill="${CSS.escape(String(b.id))}"]`); if (r) r.classList.add('paying'); });
      const method = S.method;
      const res = await NZA.post(`${APP}:payBills`, { id: which === 'all' ? 'all' : num(which), method });
      S.busy = false;
      if (!win) return;
      if (res && res.ok) {
        if (res.data) apply(res.data);
        NZA.audio.success();
        renderSide(); renderMain(); flashWallet(method);
      } else {
        if (res && res.data) apply(res.data);
        NZA.toast({ title: T('title_billing', 'Medical billing'), message: (res && res.msg) || T('ui_failed', 'Payment failed'), type: 'error' });
        NZA.audio.fail();
        renderMain();
      }
    };
    if (which === 'all') {
      confirm({ title: T('ui_bills_title', 'Medical bills'), ic: 'receipt', text: T('ui_bills_pay_all', 'Pay all %s', `**${money(total)}**`), label: T('ui_bills_pay', 'Pay'), onOk: run });
    } else run();
  }

  /* ═════════════════════════ staff: stock & sales ═════════════════════════ */
  async function loadStaff() {
    S.staffBusy = true;
    const res = await NZA.post(`${APP}:staff`, {});
    S.staffBusy = false;
    if (!win) return;
    if (res && res.ok && res.staff) {
      S.staff = res.staff;
      S.staff.products = arr(S.staff.products);
      S.staff.sales = arr(S.staff.sales);
    } else {
      NZA.toast({ title: T('ui_stock', 'Stock'), message: (res && res.msg) || T('err_error', 'Something went wrong. Try again.'), type: 'error' });
    }
    renderSide();
    if (S.view === 'stock' || S.view === 'sales') renderMain();
  }

  const loading = () => `<div class="ph-loading"><span class="ph-spin"></span>${esc(T('ui_staff_loading', 'Loading stock'))}</div>`;

  function staffStats(st) {
    const s = st.stats || {};
    return `<div class="w-stats">
      <div class="w-stat"><span class="si teal">${icon('trend-up')}</span><div><span>${esc(T('ui_sales_today', 'Sales today'))}</span><b>${money(s.today)}</b><small>${esc(T('ui_orders', '%d orders', num(s.todayCount)))}</small></div></div>
      <div class="w-stat"><span class="si">${icon('chart')}</span><div><span>${esc(T('ui_sales_week', 'Last 7 days'))}</span><b>${money(s.week)}</b><small>${esc(T('ui_orders', '%d orders', num(s.weekCount)))}</small></div></div>
      <div class="w-stat"><span class="si">${icon('bank')}</span><div><span>${esc(T('ui_society', 'Society balance'))}</span><b>${money(st.society && st.society.balance)}</b><small class="ph-mono">${esc((st.society && st.society.name) || '')}</small></div></div>
      <div class="w-stat"><span class="si ${num(st.out) ? 'red' : num(st.low) ? 'amber' : 'teal'}">${icon('alert')}</span><div><span>${esc(T('ui_attention', 'Low / sold out'))}</span><b>${num(st.low)} / ${num(st.out)}</b></div></div>
    </div>`;
  }

  function qtyFor(p, st) { const room = Math.max(0, num(p.max) - num(p.stock)); const q = S.qty[p.id]; return Math.max(1, Math.min(num(st.orderMax, 50), room || 1, q || room || 1)); }

  function stockHTML() {
    const st = S.staff;
    const head = `<div class="w-head"><div><h1>${esc(T('ui_stock_title', 'Stock'))}</h1><p>${esc(T('ui_stock_sub', 'Shelf levels for %s. Orders are paid by the department society.', (st && st.dept) || S.d.shop.dept || S.d.shop.location || ''))}</p></div>
      <button class="btn-line" data-act="reloadStaff">${icon('refresh')}${esc(T('ui_refresh', 'Refresh'))}</button></div>`;
    if (!st) return `<div class="ph-view">${head}${loading()}</div>`;
    const bal = num(st.society && st.society.balance);
    const rows = st.products.map((p, k) => {
      const room = Math.max(0, num(p.max) - num(p.stock));
      const ratio = num(p.max) > 0 ? num(p.stock) / num(p.max) : 0;
      const tone = num(p.stock) <= 0 ? 'red' : ratio <= 0.25 ? 'amber' : '';
      const q = qtyFor(p, st);
      const cost = num(p.orderUnit) * q;
      return `<div class="ph-stock-row ${S.rowBusy === p.id ? 'busy' : ''}" data-id="${esc(p.id)}" style="animation-delay:${Math.min(k, 12) * 25}ms">
        <div class="im">${img(p.image, catIcon(p.category))}</div>
        <div class="txt"><b>${esc(p.label)}</b><span>${esc(catLabel(p.category))} · ${money(p.price)} · ${esc(T('ui_unit_cost', '%s per unit', money(p.orderUnit)))}</span></div>
        <div class="ph-shelf"><div class="top"><span>${esc(T('ui_shelf', 'Shelf'))}</span><b class="${tone}">${num(p.stock)}<small> / ${num(p.max)}</small></b></div>${NZA.ui.meterHTML({ value: ratio, tone, segs: true })}</div>
        <div class="ctl">${room > 0 ? `
          <div class="ph-step sm"><button data-act="rq" data-d="-1" data-id="${esc(p.id)}" ${q <= 1 ? 'disabled' : ''}>${icon('minus')}</button><b>${q}</b><button class="plus" data-act="rq" data-d="1" data-id="${esc(p.id)}" ${q >= Math.min(room, num(st.orderMax, 50)) ? 'disabled' : ''}>${icon('plus')}</button></div>
          <button class="btn-teal" data-act="order" data-id="${esc(p.id)}" ${bal < cost ? 'disabled' : ''}>${esc(T('ui_order_btn', 'Order %s', money(cost)))}</button>
          ${st.fromInventory && num(p.have) > 0 ? `<button class="btn-line" data-act="frominv" data-id="${esc(p.id)}">${icon('backpack')}${esc(T('ui_from_inv', 'From inventory (%d)', num(p.have)))}</button>` : ''}`
          : `<span class="chipx sm teal">${icon('check')}${esc(T('ui_full', 'Full'))}</span>`}</div>
      </div>`;
    }).join('');
    return `<div class="ph-view">${head}${staffStats(st)}
      <div class="ph-list">${rows || emptyView('box', T('ui_sales_none', 'No sales yet'))}</div></div>`;
  }

  function salesHTML() {
    const st = S.staff;
    const head = `<div class="w-head"><div><h1>${esc(T('ui_sales_title', 'Sales log'))}</h1><p>${esc(T('ui_sales_sub', 'The latest sales at the counters of %s.', (st && st.dept) || S.d.shop.dept || S.d.shop.location || ''))}</p></div>
      <button class="btn-line" data-act="reloadStaff">${icon('refresh')}${esc(T('ui_refresh', 'Refresh'))}</button></div>`;
    if (!st) return `<div class="ph-view">${head}${loading()}</div>`;
    const rows = st.sales.map(s => {
      const items = arr(s.items).map(i => `${num(i.qty)}× ${i.label || i.id}`).join(', ');
      return `<tr><td class="ph-mono">${esc(stamp(s.created))}</td><td><b>${esc(s.name || '?')}</b></td>
        <td class="items" title="${esc(items)}">${esc(items)}</td>
        <td><span class="chipx sm ${s.kind === 'insurance' ? 'teal' : ''}">${icon(s.kind === 'insurance' ? 'shield' : 'cart')}${esc(s.kind === 'insurance' ? T('ui_kind_insurance', 'Insurance') : T('ui_kind_shop', 'Shop'))}</span></td>
        <td>${icon(s.method === 'cash' ? 'cash' : 'bank')}</td>
        <td class="num"><b>${money(s.total)}</b>${num(s.discount) > 0 ? `<div style="font-size:10px;color:var(--teal-hi)">−${money(s.discount)}</div>` : ''}</td></tr>`;
    }).join('');
    return `<div class="ph-view">${head}${staffStats(st)}
      <div class="w-panel" style="padding:14px 16px">${rows ? `<table class="w-table ph-sales"><thead><tr><th>${esc(T('ui_col_time', 'Time'))}</th><th>${esc(T('ui_col_customer', 'Customer'))}</th><th>${esc(T('ui_col_items', 'Items'))}</th><th></th><th>${esc(T('ui_col_method', 'Paid'))}</th><th class="num">${esc(T('ui_col_total', 'Total'))}</th></tr></thead><tbody>${rows}</tbody></table>`
        : emptyView('chart', T('ui_sales_none', 'No sales yet'))}</div></div>`;
  }

  async function restock(id, from) {
    const st = S.staff;
    const p = st && st.products.find(x => x.id === id);
    if (!p || S.rowBusy) return;
    const q = from === 'inventory' ? Math.min(num(p.have), Math.max(1, num(p.max) - num(p.stock))) : qtyFor(p, st);
    S.rowBusy = id;
    renderMain();
    const res = await NZA.post(`${APP}:restock`, { id, qty: q, from });
    S.rowBusy = null;
    if (!win) return;
    if (res && res.ok) {
      if (res.staff) { S.staff = res.staff; S.staff.products = arr(S.staff.products); S.staff.sales = arr(S.staff.sales); }
      delete S.qty[id];
      NZA.toast({ title: T('ui_stock', 'Stock'), message: res.msg || '', type: 'success', icon: 'box' });
      NZA.audio.success();
      const r = await NZA.post(`${APP}:refresh`, {});
      if (r && r.ok && r.data) apply(r.data);
    } else {
      NZA.toast({ title: T('ui_stock', 'Stock'), message: (res && res.msg) || T('err_error', 'Something went wrong. Try again.'), type: 'error' });
      NZA.audio.fail();
    }
    if (!win) return;
    renderSide(); renderMain();
  }

  /* ═════════════════════════ send bill (medic) ═════════════════════════ */
  function openInvoice(data) {
    S.d = null;
    S.inv = { d: data, amount: 0, reason: '', preset: null, busy: false, done: null, err: null, wait: num(data.wait), until: Date.now() + num(data.wait) * 1000 };
    dim = NZA.el('div', 'nza-dim');
    root.appendChild(dim);
    win = NZA.ui.Win(root, { title: T('ui_inv_title', 'Send bill').toUpperCase(), sub: data.name || '', onClose: () => NZA.close(APP), status: [{ key: 'ESC', label: T('ui_k_close', 'Close') }, { key: 'Enter', label: T('ui_k_send', 'Send') }] });
    win.el.classList.add('ph-compact');
    win.setMid(`<span class="ph-loc">${icon('receipt')}<b>${esc(T('title_billing', 'Medical billing'))}</b></span>`);
    renderInvoice();
    if (S.inv.wait > 0) {
      invTimer = setInterval(() => {
        if (!S.inv || Date.now() >= S.inv.until) { clearInterval(invTimer); invTimer = 0; }
        updInvoice();
      }, 500);
    }
  }

  function invCalc() {
    const v = S.inv, d = v.d;
    const amount = Math.max(0, Math.floor(num(v.amount)));
    const cover = d.insurance ? num(d.insurance.cover) : 0;
    const covered = Math.min(amount, Math.floor(amount * cover + 0.5));
    const pays = amount - covered;
    const cut = Math.floor(pays * num(d.cut));
    return { amount, covered, pays, cut, cover };
  }

  function renderInvoice() {
    const v = S.inv, d = v.d;
    if (v.done) {
      win.main.innerHTML = `<div class="ph-done" style="padding:30px 10px"><div class="ph-check">${icon('check')}</div><h3>${esc(v.done)}</h3></div>`;
      return;
    }
    const presets = arr(d.presets);
    win.main.innerHTML = `<div class="ph-inv">
      <div class="ph-pat"><span class="av">${esc(initials(d.name))}</span><div><b>${esc(d.name || '?')}</b><span>ID ${esc(d.sid)} · ${esc(T('ui_inv_sub', 'Bill for your care'))}</span></div>
        <span class="chipx ${d.insurance ? 'teal' : ''}">${icon(d.insurance ? 'shield-check' : 'shield')}${esc(d.insurance ? T('ui_inv_ins', '%s plan pays %d%%', d.insurance.label, Math.round(num(d.insurance.cover) * 100)) : T('ui_inv_no_ins', 'Not insured - pays everything'))}</span></div>
      ${presets.length ? `<div class="ph-field"><label>${esc(T('ui_inv_presets', 'Quick amounts'))}</label><div class="chips">${presets.map(p => `<button class="chipx ${v.preset === p.key ? 'on' : ''}" data-act="preset" data-k="${esc(p.key)}">${esc(p.label)} · ${money(p.amount)}</button>`).join('')}</div></div>` : ''}
      <div class="ph-field"><label>${esc(T('ui_inv_amount', 'Amount'))}</label><div class="ph-amount"><span>$</span><input id="ph-amt" inputmode="numeric" maxlength="7" placeholder="0" value="${v.amount ? esc(v.amount) : ''}" autocomplete="off"><small>${esc(T('ui_inv_max', 'Up to %s', money(d.max)))}</small></div></div>
      <div class="ph-field"><label>${esc(T('ui_inv_reason', 'Reason'))}</label><input id="ph-reason" class="input" maxlength="80" placeholder="${esc(T('ui_inv_reason_ph', 'What was the care for?'))}" value="${esc(v.reason)}" autocomplete="off"></div>
      <div class="ph-break"></div>
      <div class="ph-note"><p>${esc(T('ui_inv_note', 'Unpaid bills are kept and paid later at any pharmacy.'))}</p></div>
      <div class="ph-msgbox"></div>
      <div class="ph-inv-foot"><button class="btn-line" data-act="invcancel">${esc(T('ui_cancel', 'Cancel'))}</button><button class="btn-teal" data-act="send"></button></div>
    </div>`;
    updInvoice();
    const a = win.main.querySelector('#ph-amt');
    if (a) setTimeout(() => a.focus(), 60);
  }

  function updInvoice() {
    const v = S.inv;
    if (!v || !win || v.done) return;
    const d = v.d, c = invCalc();
    const br = win.main.querySelector('.ph-break');
    if (br) {
      br.innerHTML = `<div class="ln t"><span>${esc(T('ui_inv_ins_pays', 'Insurance pays'))}</span><b>${money(c.covered)}</b></div>
        <div class="ln"><span>${esc(T('ui_inv_pat_pays', 'Patient pays'))}</span><b>${money(c.pays)}</b></div>
        ${num(d.cut) > 0 ? `<div class="ln c"><span>${esc(T('ui_inv_cut', 'Your cut (%d%%)', Math.round(num(d.cut) * 100)))}</span><b>${money(c.cut)}</b></div>` : ''}`;
    }
    const wait = Math.max(0, Math.ceil((v.until - Date.now()) / 1000));
    const btn = win.main.querySelector('[data-act="send"]');
    if (btn) {
      btn.disabled = v.busy || wait > 0 || c.amount < 1 || c.amount > num(d.max);
      btn.innerHTML = v.busy ? `<span class="ph-spin"></span>` : wait > 0 ? `${icon('clock')}${esc(T('ui_inv_wait', 'Wait %ds', wait))}` : `${icon('send')}${esc(T('ui_inv_send', 'Send bill %s', money(c.amount)))}`;
    }
    const mb = win.main.querySelector('.ph-msgbox');
    if (mb) mb.innerHTML = v.err ? `<div class="ph-msg err">${icon('error')}<span>${esc(v.err)}</span></div>` : '';
    const box = win.main.querySelector('.ph-amount');
    if (box) box.style.borderColor = c.amount > num(d.max) ? 'var(--red)' : '';
  }

  async function sendInvoice() {
    const v = S.inv;
    if (!v || v.busy || v.done) return;
    const c = invCalc();
    if (c.amount < 1 || c.amount > num(v.d.max) || Date.now() < v.until) return;
    v.busy = true; v.err = null;
    updInvoice();
    const res = await NZA.post(`${APP}:invoice`, { sid: v.d.sid, amount: c.amount, reason: v.reason.trim() });
    v.busy = false;
    if (!win || S.inv !== v) return;
    if (res && res.ok) {
      v.done = T('invoice_sent', 'Bill of %s sent to %s.', money(c.amount), v.d.name || '');
      NZA.audio.success();
      renderInvoice();
    } else {
      v.err = (res && res.msg) || T('err_error', 'Something went wrong. Try again.');
      NZA.audio.fail();
      updInvoice();
    }
  }

  /* ═════════════════════════ events ═════════════════════════ */
  function onClick(e) {
    const b = e.target.closest('[data-act]');
    if (!b || !root.contains(b) || b.disabled) return;
    const id = b.dataset.id;
    switch (b.dataset.act) {
      case 'add': return addToCart(id, 1);
      case 'inc': return addToCart(id, 1);
      case 'dec': return addToCart(id, -1);
      case 'rm': e.stopPropagation(); S.cart.delete(id); NZA.audio.click(440); refreshCard(id); return renderCart();
      case 'clear': S.cart.clear(); S.msg = null; renderGrid(); renderInsp(); return renderCart();
      case 'sel': return select(id);
      case 'cat': S.cat = b.dataset.v; renderRail(); renderHead(); return renderGrid();
      case 'tab': return go(b.dataset.v);
      case 'iq': { const p = prod(S.sel); if (!p) return; S.iq = Math.max(1, (S.iq || 1) + num(b.dataset.d)); NZA.audio.click(640); return renderInsp(); }
      case 'iadd': { const q = S.iq || 1; S.iq = 1; return addToCart(id, q); }
      case 'sort': S.sort = b.dataset.v; renderHead(); return renderGrid();
      case 'method':
        if (!payOk(b.dataset.m)) return;
        S.method = b.dataset.m; S.msg = null;
        if (S.view === 'shop') return renderCart();
        return renderMain();
      case 'pay': return pay();
      case 'neworder': S.receipt = null; renderInsp(); return renderCart();
      case 'clrq': {
        e.preventDefault();
        S.q = '';
        const q = win.el.querySelector('#ph-q');
        if (q) { q.value = ''; q.focus(); }
        win.el.querySelector('.ph-search').classList.remove('has');
        renderHead(); return renderGrid();
      }
      case 'plan': return choosePlan(b.dataset.plan);
      case 'paybill': return payBill(id);
      case 'payall': return payBill('all');
      case 'reloadStaff': S.staff = null; renderMain(); return loadStaff();
      case 'rq': {
        const p = S.staff && S.staff.products.find(x => x.id === id);
        if (!p) return;
        S.qty[id] = qtyFor(p, S.staff) + num(b.dataset.d);
        S.qty[id] = qtyFor(p, S.staff);
        return renderMain();
      }
      case 'order': return restock(id, 'order');
      case 'frominv': return restock(id, 'inventory');
      case 'preset': {
        const v = S.inv; const p = arr(v.d.presets).find(x => x.key === b.dataset.k);
        if (!p) return;
        const prevLabel = v.preset && (arr(v.d.presets).find(x => x.key === v.preset) || {}).label;
        v.preset = p.key; v.amount = num(p.amount); v.err = null;
        if (!v.reason || v.reason === prevLabel) v.reason = p.label;
        win.main.querySelectorAll('[data-act="preset"]').forEach(x => x.classList.toggle('on', x === b));
        const a = win.main.querySelector('#ph-amt'); if (a) a.value = v.amount;
        const r = win.main.querySelector('#ph-reason'); if (r) r.value = v.reason;
        return updInvoice();
      }
      case 'invcancel': return NZA.close(APP);
      case 'send': return sendInvoice();
    }
  }

  function onInput(e) {
    const t = e.target;
    if (t.id === 'ph-q') {
      S.q = t.value;
      t.closest('.ph-search').classList.toggle('has', !!S.q);
      if (S.view !== 'shop') return;
      renderHead(); renderGrid();
    } else if (t.id === 'ph-amt' && S.inv) {
      const clean = t.value.replace(/[^0-9]/g, '').slice(0, 7);
      if (clean !== t.value) t.value = clean;
      S.inv.amount = num(clean); S.inv.err = null;
      if (S.inv.preset) { S.inv.preset = null; win.main.querySelectorAll('[data-act="preset"]').forEach(x => x.classList.remove('on')); }
      updInvoice();
    } else if (t.id === 'ph-reason' && S.inv) {
      S.inv.reason = t.value;
    }
  }

  const typing = e => e.target && /^(INPUT|TEXTAREA)$/.test(e.target.tagName);
  function browse(e, d) {
    if (typing(e) || S.view !== 'shop' || modal || !win) return false;
    const list = visible();
    if (!list.length) return false;
    const i = list.findIndex(p => p.id === S.sel);
    select(list[Math.max(0, Math.min(list.length - 1, (i < 0 ? 0 : i + d)))].id, true);
    return true;
  }

  NZA.app(APP, {
    init(el) {
      root = el;
      el.addEventListener('click', onClick);
      el.addEventListener('input', onInput);
      el.addEventListener('focusin', e => { if (e.target.id === 'ph-amt') e.target.parentElement.classList.add('focus'); });
      el.addEventListener('focusout', e => { if (e.target.id === 'ph-amt') e.target.parentElement.classList.remove('focus'); });
    },
    open(data) {
      teardown();
      data = data || {};
      LOC = Object.assign({}, data.locale || {});
      S.busy = false; S.msg = null; S.receipt = null; S.staff = null; S.qty = {}; S.rowBusy = null; S.inv = null;
      S.cart = new Map(); S.q = ''; S.cat = 'all'; S.sort = 'featured'; S.sel = null; S.iq = 1; S.odo = null;
      if (data.mode === 'invoice') return openInvoice(data);
      S.d = normalize(Object.assign({}, data));
      const pd = S.d.payment.default === 'cash' ? 'cash' : 'bank';
      S.method = payOk(pd) ? pd : (pd === 'cash' ? 'bank' : 'cash');
      const tab = data.tab;
      const allowed = v => (v === 'shop' && isShop()) || (v === 'insurance' && S.d.insurance.enabled) || (v === 'bills' && S.d.bills.enabled) || ((v === 'stock' || v === 'sales') && S.d.canManage && isShop());
      S.view = allowed(tab) ? tab : isShop() ? 'shop' : (S.d.bills.enabled && S.d.bills.list.length ? 'bills' : S.d.insurance.enabled ? 'insurance' : 'bills');
      build();
      if (S.view === 'stock' || S.view === 'sales') loadStaff();
    },
    close() {
      teardown();
      S.inv = null;
    },
    msg: {
      data(d) { if (S.d && win) { apply(d); renderSide(); win.setMid(midHTML()); renderMain(); } },
      wallet(w) { if (S.d && win) { S.d.wallet = Object.assign(S.d.wallet, w || {}); renderSide(); if (S.view === 'shop') renderCart(); } },
    },
    keys: {
      Escape(e) {
        if (modal) { closeModal(); return true; }
        if (e.target && e.target.id === 'ph-q' && S.q) { onClick({ target: win.el.querySelector('[data-act="clrq"]'), preventDefault() {} }); return true; }
        return false;
      },
      Enter(e) {
        if (modal) { const ok = modal.el.querySelector('.btn-teal'); if (ok) ok.click(); return true; }
        if (S.inv) { sendInvoice(); return true; }
        if (e.target && e.target.id === 'ph-q') { e.target.blur(); return true; }   // never pay from the search box
        if (S.view === 'shop' && S.cart.size && !S.receipt) { pay(); return true; }
        if (S.view === 'shop' && S.receipt) { S.receipt = null; renderInsp(); renderCart(); return true; }
        return false;
      },
      ArrowDown(e) { return browse(e, 1); },
      ArrowUp(e) { return browse(e, -1); },
      '+'(e) { if (typing(e) || S.view !== 'shop' || !S.sel || modal) return false; addToCart(S.sel, 1); return true; },
      '/'(e) {
        if (typing(e) || S.view !== 'shop' || !win) return false;
        const q = win.el.querySelector('#ph-q');
        if (q) { q.focus(); q.select(); return true; }
        return false;
      },
    },
    preview() { preview(); },
  });

  /* ═════════════════════════ preview (browser only) ═════════════════════════ */
  function preview() {
    const view = new URLSearchParams(location.search).get('view') || 'shop';
    const now = Math.floor(Date.now() / 1000);
    const im = n => `img/items/${n}.png`;
    const P = (id, name, label, cat, price, extra = {}) => Object.assign({ id, name, label, category: cat, price, limit: 25, image: im(name), order: 0 }, extra);
    const products = [
      P('painkillers', 'painkillers', 'Painkillers', 'medicines', 30, { was: 40, discount: 0.25, featured: true, description: 'Fast-acting pain relief tablets.' }),
      P('antibiotics', 'antibiotics', 'Antibiotics', 'medicines', 120, { stock: 22, max: 30, description: 'Treats and prevents wound infection.' }),
      P('morphine', 'morphine', 'Morphine', 'medicines', 250, { stock: 14, max: 20, limit: 5, locked: true, lock: 'perm', lockText: 'Needs a medical permission', description: 'Strong pain relief. Watch the breathing.' }),
      P('adrenaline', 'adrenaline', 'Adrenaline 1 mg', 'medicines', 220, { stock: 9, max: 20, limit: 5, locked: true, lock: 'perm', lockText: 'Needs a medical permission', description: 'For cardiac arrest, every 3-5 minutes.' }),
      P('bandage', 'bandage', 'Bandage', 'dressings', 18, { was: 25, discount: 0.28, featured: true, description: 'Elastic roll for dressing cuts and slowing a bleed.' }),
      P('tourniquet', 'tourniquet', 'Tourniquet', 'dressings', 45, { was: 60, discount: 0.25, featured: true, description: 'Windlass strap that stops heavy bleeding from a limb.' }),
      P('gauze', 'gauze', 'Gauze', 'dressings', 15, { description: 'Sterile gauze for packing wounds and soaking up blood.' }),
      P('dressing', 'sterile_dressing', 'Sterile Dressing', 'dressings', 20, { description: 'Adhesive sterile dressing for closed wounds.' }),
      P('burn_dressing', 'burn_dressing', 'Burn Dressing', 'dressings', 45, { was: 60, discount: 0.25, description: 'Sterile hydrogel dressing that cools and covers burns.' }),
      P('suture_kit', 'suture_kit', 'Suture Kit', 'dressings', 140, { stock: 0, max: 30, description: 'Needle, thread and tools to close a wound.' }),
      P('saline', 'saline', 'Saline', 'lines', 35, { description: 'Sterile 0.9% saline for flushing wounds.' }),
      P('iv_kit', 'iv_kit', 'IV Kit', 'lines', 120, { stock: 18, max: 30, description: 'Cannula, line and fittings for IV access.' }),
      P('saline_bag', 'saline_bag', 'Saline 500 ml', 'lines', 90, { stock: 26, max: 30, description: 'Bag of 0.9% saline for infusion.' }),
      P('oxygen_mask', 'oxygen_mask', 'Oxygen Mask', 'airway', 260, { stock: 7, max: 12, locked: true, lock: 'perm', lockText: 'Needs a medical permission', description: 'High-flow oxygen for low saturation.' }),
      P('splint', 'splint', 'Splint', 'bones', 153, { was: 180, discount: 0.15, stock: 12, max: 20, description: 'Mouldable splint for a broken arm or leg.' }),
      P('ice_pack', 'ice_pack', 'Ice Pack', 'bones', 15, { was: 20, discount: 0.25, description: 'Instant cold pack for sprains and swelling.' }),
      P('crutches', 'crutches', 'Crutches', 'bones', 350, { stock: 6, max: 10, description: 'Walk with a broken leg.' }),
      P('medkit', 'medikit', 'Medkit', 'devices', 112, { was: 150, discount: 0.25, stock: 3, max: 40, low: true, featured: true, description: 'Complete first-aid kit for patching yourself up.' }),
      P('foil_blanket', 'foil_blanket', 'Foil Blanket', 'devices', 30, { description: 'Keeps a patient warm and fights hypothermia.' }),
      P('stethoscope', 'stethoscope', 'Stethoscope', 'devices', 300, { stock: 8, max: 10, locked: true, lock: 'medics', lockText: 'On-duty medics only', description: 'Listen to the heart and lungs.' }),
      P('wheelchair', 'wheelchair', 'Wheelchair', 'devices', 2400, { stock: 4, max: 4, limit: 1, description: 'Folding wheelchair.' }),
      P('bodybag', 'bodybag', 'Body Bag', 'devices', 150, { stock: 20, max: 20, locked: true, lock: 'perm', lockText: 'Needs a medical permission', description: 'For transporting the deceased to the morgue.' }),
    ].map((p, i) => Object.assign(p, { order: i + 1 }));
    const counts = {};
    products.forEach(p => { counts[p.category] = (counts[p.category] || 0) + 1; });
    const cats = [['medicines', 'pill', 'Medicines'], ['dressings', 'bandage', 'Bleeding & dressings'], ['lines', 'iv', 'Drips & lines'], ['airway', 'lungs', 'Airway'], ['bones', 'bone', 'Bones & joints'], ['devices', 'kit', 'Kit & devices']]
      .map(([id, ic, label]) => ({ id, icon: ic, label, count: counts[id] || 0 }));
    const plans = [
      { id: 'basic', label: 'Basic', desc: 'Essential cover for the occasional patch-up.', price: 1500, days: 7, cover: 0.4, pharmacy: 0.1, icon: 'shield', action: 'switch', credit: 0, pay: 1500, allowed: true, newExpires: now + 7 * 86400 },
      { id: 'plus', label: 'Plus', desc: 'The everyday plan for people who live a little dangerously.', price: 3500, days: 14, cover: 0.65, pharmacy: 0.2, icon: 'shield-check', popular: true, action: 'renew', credit: 0, pay: 3500, allowed: true, newExpires: now + 25 * 86400 },
      { id: 'premium', label: 'Premium', desc: 'Near-complete cover and the best pharmacy prices.', price: 9000, days: 30, cover: 0.9, pharmacy: 0.35, icon: 'crown', action: 'switch', credit: 2750, pay: 6250, allowed: true, newExpires: now + 30 * 86400 },
    ];
    const insured = view !== 'none';
    if (!insured) plans.forEach(p => { p.action = 'buy'; p.credit = 0; p.pay = p.price; p.newExpires = now + p.days * 86400; });
    const data = {
      mode: view === 'desk' ? 'desk' : 'shop', point: 12, tab: view === 'receipt' ? 'shop' : view,
      shop: { label: 'Pillbox Pharmacy', location: 'Pillbox Pharmacy', dept: 'Pillbox Hill Medical' },
      categories: cats, products: view === 'desk' ? [] : products,
      wallet: { cash: 1240, bank: 18575 }, payment: { cash: true, bank: true, default: 'bank' }, tax: 0,
      discount: insured ? { pct: 0.2, kind: 'insurance', plan: 'Plus', insurance: 0.2, staff: 0 } : { pct: 0 }, maxLines: 30,
      insurance: {
        enabled: true, card: true, maxDays: 90, plans,
        current: insured ? { plan: 'plus', label: 'Plus', icon: 'shield-check', cover: 0.65, pharmacy: 0.2, days: 14, expires: now + 11 * 86400 + 5 * 3600, started: now - 3 * 86400, serial: 'HC-7KQ4-H2MX', active: true } : null,
      },
      bills: {
        enabled: true,
        list: [
          { id: 1042, amount: 1450, covered: 2693, reason: 'Surgery - bullet extraction', kind: 'surgery', medicName: 'Dr. Maya Reyes', status: 'unpaid', created: now - 3600 * 5 },
          { id: 1037, amount: 380, covered: 705, reason: 'Ambulance transport', kind: 'transport', medicName: 'Theo Kane', status: 'unpaid', created: now - 86400 - 7200 },
          { id: 1029, amount: 225, covered: 0, reason: 'Hospital respawn', kind: 'respawn', status: 'unpaid', created: now - 86400 * 3 },
        ],
        history: [
          { id: 1011, amount: 240, covered: 445, reason: 'Treatment - deep laceration', kind: 'firstaid_suture', medicName: 'Priya Nair', status: 'paid', created: now - 86400 * 6, paidAt: now - 86400 * 5 },
          { id: 998, amount: 90, covered: 0, reason: 'Consultation', kind: 'invoice', medicName: 'Sam Brooks', status: 'paid', created: now - 86400 * 9, paidAt: now - 86400 * 9 },
        ],
        total: 2055,
      },
      canManage: true, me: { name: 'Ilse Varga' }, now,
    };
    if (view === 'desk') { data.categories = []; data.canManage = false; }
    const staff = {
      dept: 'Pillbox Hill Medical', low: 2, out: 1, orderMax: 50, fromInventory: true,
      stats: { today: 4380, todayCount: 17, week: 31240, weekCount: 128 },
      society: { name: 'society_ambulance', balance: 84210 },
      products: products.filter(p => p.max).map(p => ({ id: p.id, name: p.name, label: p.label, category: p.category, image: p.image, stock: p.stock, max: p.max, price: p.price, orderUnit: Math.ceil((p.was || p.price) * 0.45), have: p.id === 'splint' ? 4 : p.id === 'iv_kit' ? 9 : 0 })),
      sales: [
        { id: 311, name: 'Ilse Varga', items: [{ id: 'bandage', label: 'Bandage', qty: 4 }, { id: 'painkillers', label: 'Painkillers', qty: 2 }], total: 106, discount: 26, method: 'bank', kind: 'shop', created: now - 420 },
        { id: 310, name: 'Lena Ortiz', items: [{ id: 'insurance:premium', label: 'Insurance - Premium', qty: 1 }], total: 9000, discount: 0, method: 'bank', kind: 'insurance', created: now - 1900 },
        { id: 309, name: 'Dr. Maya Reyes', items: [{ id: 'iv_kit', label: 'IV Kit', qty: 5 }, { id: 'saline_bag', label: 'Saline 500 ml', qty: 4 }], total: 768, discount: 192, method: 'bank', kind: 'shop', created: now - 3600 },
        { id: 308, name: 'Jamal Price', items: [{ id: 'crutches', label: 'Crutches', qty: 1 }], total: 350, discount: 0, method: 'cash', kind: 'shop', created: now - 7400 },
        { id: 307, name: 'Ava Chen', items: [{ id: 'medkit', label: 'Medkit', qty: 2 }, { id: 'ice_pack', label: 'Ice Pack', qty: 1 }, { id: 'tourniquet', label: 'Tourniquet', qty: 1 }], total: 251, discount: 63, method: 'cash', kind: 'shop', created: now - 86400 - 3000 },
        { id: 306, name: 'Theo Kane', items: [{ id: 'splint', label: 'Splint', qty: 2 }], total: 306, discount: 0, method: 'bank', kind: 'shop', created: now - 86400 - 9000 },
      ],
    };
    const clone = o => JSON.parse(JSON.stringify(o));
    let live = clone(data);
    NZA.mock(`${APP}:buy`, req => {
      let sub = 0;
      const lines = req.lines.map(l => { const p = live.products.find(x => x.id === l.id); sub += p.price * l.qty; return { id: p.id, name: p.name, label: p.label, qty: l.qty, unit: p.price, total: p.price * l.qty, image: p.image }; });
      const disc = Math.floor(sub * live.discount.pct + 0.5);
      live.wallet[req.method] -= sub - disc;
      req.lines.forEach(l => { const p = live.products.find(x => x.id === l.id); if (p.stock !== undefined) p.stock -= l.qty; });
      return { ok: true, data: clone(live), receipt: { no: `RX-${new Date().toISOString().slice(2, 10).replace(/-/g, '')}-0427`, lines, subtotal: sub, discount: disc, discountKind: live.discount.kind, discountPct: live.discount.pct, plan: live.discount.plan, tax: 0, total: sub - disc, refund: 0, method: req.method, time: Math.floor(Date.now() / 1000) } };
    });
    NZA.mock(`${APP}:insurance`, req => {
      const p = live.insurance.plans.find(x => x.id === req.plan);
      live.wallet[req.method] -= p.pay;
      live.insurance.current = { plan: p.id, label: p.label, icon: p.icon, cover: p.cover, pharmacy: p.pharmacy, days: p.days, expires: p.newExpires, started: now, serial: 'HC-7KQ4-H2MX', active: true };
      live.insurance.plans.forEach(x => { x.action = x.id === p.id ? 'renew' : 'switch'; });
      live.discount = { pct: p.pharmacy, kind: 'insurance', plan: p.label };
      return { ok: true, data: clone(live) };
    });
    NZA.mock(`${APP}:payBills`, req => {
      const pick = req.id === 'all' ? live.bills.list : live.bills.list.filter(b => b.id === req.id);
      pick.forEach(b => { live.wallet[req.method] -= b.amount; b.status = 'paid'; b.paidAt = Math.floor(Date.now() / 1000); live.bills.history.unshift(b); });
      live.bills.list = live.bills.list.filter(b => !pick.includes(b));
      return { ok: true, data: clone(live) };
    });
    NZA.mock(`${APP}:refresh`, () => ({ ok: true, data: clone(live) }));
    NZA.mock(`${APP}:staff`, () => new Promise(r => setTimeout(() => r({ ok: true, staff: clone(staff) }), 250)));
    NZA.mock(`${APP}:restock`, req => {
      const p = staff.products.find(x => x.id === req.id);
      p.stock = Math.min(p.max, p.stock + req.qty);
      staff.society.balance -= p.orderUnit * req.qty;
      return { ok: true, staff: clone(staff), msg: `Ordered ${req.qty} x ${p.label} - the society paid the supplier.` };
    });
    NZA.mock(`${APP}:invoice`, () => new Promise(r => setTimeout(() => r({ ok: true, info: { amount: 750 } }), 300)));

    if (view === 'invoice') {
      NZA.demo(APP, {
        mode: 'invoice', sid: 27, name: 'Ilse Varga', max: 15000, wait: 0, cut: 0.25,
        insurance: { label: 'Plus', cover: 0.65 },
        presets: [{ key: 'consult', amount: 250, label: 'Consultation' }, { key: 'treatment', amount: 750, label: 'Treatment' }, { key: 'transport', amount: 500, label: 'Ambulance transport' }, { key: 'surgery', amount: 2500, label: 'Surgery' }],
      });
      const a = document.querySelector('#app-pharmacy [data-k="treatment"]');
      if (a) a.click();
      return;
    }
    NZA.demo(APP, clone(live));
    if (view === 'shop' || view === 'receipt') {
      addToCart('bandage', 1); addToCart('bandage', 1); addToCart('bandage', 1);
      addToCart('painkillers', 1); addToCart('painkillers', 1);
      addToCart('tourniquet', 1);
      addToCart('splint', 1);
      if (view === 'receipt') pay();
    }
  }
})();
